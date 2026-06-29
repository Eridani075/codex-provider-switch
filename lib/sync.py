#!/usr/bin/env python3
"""codex-show-all: Unify all sessions to current provider so they all show up.

Scans ~/.codex for session files and SQLite databases,
rewrites model_provider to the current provider.

Usage:
  python3 show-all.py              # Auto-detect current provider
  python3 show-all.py <provider>   # Specify target provider
"""
import json
import os
import shutil
import sqlite3
import sys
import time
from pathlib import Path

CODEX_HOME = Path.home() / ".codex"
SESSION_DIRS = ["sessions", "archived_sessions"]
BACKUP_DIR = CODEX_HOME / "backups_state" / "provider-sync"
MAX_BACKUPS = 5


def get_current_provider():
    config = CODEX_HOME / "config.toml"
    if not config.exists():
        return "openai"
    for line in config.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("model_provider") and "=" in line:
            val = line.split("=", 1)[1].strip().strip('"')
            if val:
                return val
    return "openai"


def find_rollout_files():
    files = []
    for dirname in SESSION_DIRS:
        root = CODEX_HOME / dirname
        if root.exists():
            for path in root.rglob("rollout-*.jsonl"):
                files.append(path)
    return files


def find_sqlite_dbs():
    dbs = []
    sqlite_dir = CODEX_HOME / "sqlite"
    if sqlite_dir.exists():
        for db in sqlite_dir.glob("*.db"):
            dbs.append(db)
    legacy = CODEX_HOME / "state_5.sqlite"
    if legacy.exists():
        dbs.append(legacy)
    return dbs


def unify_jsonl(path, target_provider):
    """Rewrite model_provider in session_meta lines to target_provider.
    Returns (changed, thread_id, has_user_event).
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (PermissionError, OSError):
        return False, None, False

    changed = False
    thread_id = None
    has_user_event = '"user_message"' in text or '"user_input"' in text
    new_lines = []

    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if not stripped:
            new_lines.append(line)
            continue
        try:
            record = json.loads(stripped)
        except json.JSONDecodeError:
            new_lines.append(line)
            continue

        if record.get("type") == "session_meta":
            payload = record.get("payload", {})
            if thread_id is None:
                thread_id = payload.get("id")
            current = payload.get("model_provider")
            if current != target_provider:
                payload["model_provider"] = target_provider
                record["payload"] = payload
                new_lines.append(json.dumps(record, ensure_ascii=False) + "\n")
                changed = True
                continue

        new_lines.append(line)

    if changed:
        orig_mtime = path.stat().st_mtime
        path.write_text("".join(new_lines), encoding="utf-8")
        os.utime(path, (orig_mtime, orig_mtime))

    return changed, thread_id, has_user_event


def unify_sqlite(dbs, target_provider):
    """Update model_provider in threads table to target."""
    updated = 0
    for db_path in dbs:
        try:
            conn = sqlite3.connect(str(db_path))
            cur = conn.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='threads'")
            if not cur.fetchone():
                conn.close()
                continue
            cur.execute(
                "UPDATE threads SET model_provider = ? WHERE COALESCE(model_provider, '') <> ?",
                (target_provider, target_provider),
            )
            updated += cur.rowcount
            conn.commit()
            conn.close()
        except (sqlite3.Error, OSError):
            pass
    return updated


def create_backup(target_provider, changed_files, dbs):
    ts = time.strftime("%Y%m%dT%H%M%S")
    backup_path = BACKUP_DIR / ts
    backup_path.mkdir(parents=True, exist_ok=True)

    config = CODEX_HOME / "config.toml"
    if config.exists():
        shutil.copy2(config, backup_path / "config.toml")

    db_dir = backup_path / "db"
    db_dir.mkdir(exist_ok=True)
    for db in dbs:
        for suffix in ["", "-wal", "-shm"]:
            src = db.with_suffix(db.suffix + suffix)
            if src.exists():
                shutil.copy2(src, db_dir / src.name)

    meta = {
        "timestamp": ts,
        "target_provider": target_provider,
        "changed_files": [str(f) for f in changed_files],
    }
    (backup_path / "metadata.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    if BACKUP_DIR.exists():
        backups = sorted(BACKUP_DIR.iterdir(), reverse=True)
        for old in backups[MAX_BACKUPS:]:
            shutil.rmtree(old, ignore_errors=True)

    return backup_path


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else get_current_provider()

    print(f"统一所有会话到 provider: {target}")

    rollout_files = find_rollout_files()
    dbs = find_sqlite_dbs()

    if not rollout_files and not dbs:
        print("没有找到会话文件或数据库。")
        return

    changed_files = []
    for path in rollout_files:
        changed, thread_id, has_user_event = unify_jsonl(path, target)
        if changed:
            changed_files.append(path)

    if not changed_files and not dbs:
        print("没有需要修改的内容。")
        return

    backup_path = create_backup(target, changed_files, dbs)
    print(f"备份: {backup_path}")
    print(f"重写 {len(changed_files)} 个会话文件")

    if dbs:
        updated = unify_sqlite(dbs, target)
        print(f"更新 {updated} 条数据库记录 ({len(dbs)} 个数据库)")

    print("完成。重启 Codex 即可看到所有会话。")


if __name__ == "__main__":
    main()
