# codex-provider-switch

Codex 桌面版 provider 切换工具。

## 功能

- 切换/添加/编辑/删除模型提供商
- 切换模型（预设或自定义）
- 解锁插件市场
- 统一会话显示（跨 provider 会话合并）

## 安装

```bash
git clone <repo-url>
cd codex-provider-switch
chmod +x main.sh
```

依赖：bash、uv、fzf（可选）

## 使用

```bash
# 交互菜单
./main.sh

# CLI
./main.sh switch    # 切换 provider
./main.sh model     # 切换模型
./main.sh add       # 添加 provider
./main.sh list      # 列出所有 provider
./main.sh unlock    # 解锁插件市场
./main.sh show-all  # 统一会话显示
```

## 平台支持

- Linux（原生）
- macOS（原生，BSD 工具链兼容）
- Windows（WSL / Git Bash）

## 致谢

- 插件市场解锁功能参考 [CodexPlusPlus](https://github.com/BigPizzaV3/CodexPlusPlus) 项目的 CDP 注入方案

## License

MIT
