# Codex Pet Link 开源插件化设计

**日期：** 2026-08-24  
**状态：** 已确认

## 目标

把 `pet-pal/tools/codex-pet-link` 的 Swift PoC 独立为公开项目 `sengmitnick/codex-pet-link`。其他 macOS 用户不安装桌面 App，只需把一条安装指令发给 Codex，由 Codex 完成构建、安装插件、启动 Helper 和健康检查。

推荐给其他用户的指令为：

> 请安装并启动 https://github.com/sengmitnick/codex-pet-link，严格按照仓库 INSTALL.md 操作，完成后运行 `codex-pet-link doctor` 并告诉我检查结果。

## 产品边界

- macOS 13 及以上。
- 使用现有 Swift Helper 读取本机 Codex 会话并通过 BLE 广播状态。
- 不创建菜单栏 App、设置窗口、云端服务或 Codex 内嵌页面。
- 不上传任务内容，不要求 OpenAI API Key。
- 插件只负责让 Codex 能够安装、启动、停止、重启和诊断 Helper。
- 电脑重启后不要求登录时自动广播；用户重新打开 Codex 时，由 `SessionStart` Hook 恢复服务。

## 运行结构

```text
Codex SessionStart
       |
       v
Codex Pet Link plugin hook
       |
       v
codex-pet-link ensure
       |
       v
launchd user service ----> Swift BLE Helper ----> Rokid pet-pal
```

Helper 仍由 `launchd` 托管，以解决多个 Codex 会话并发启动、进程意外退出和终端关闭的问题。但 LaunchAgent plist 放在应用数据目录，而不是 `~/Library/LaunchAgents`：重启后它不会自行加载，必须由下一次 Codex `SessionStart` Hook 执行 `ensure`。

## 安装体验

安装脚本执行以下幂等步骤：

1. 检查 macOS、Swift 和 Codex CLI。
2. Release 构建 Swift Helper。
3. 安装到 `~/Library/Application Support/CodexPetLink/bin/codex-pet-link`。
4. 在 `~/.local/bin/codex-pet-link` 创建命令入口。
5. 添加 GitHub 仓库 marketplace，安装 `codex-pet-link` 插件。
6. 执行 `codex-pet-link ensure` 立即启动 BLE Helper。
7. 执行 `codex-pet-link doctor` 输出最终结果。

插件 Hook 首次运行需要用户在 Codex 中审查并信任。Helper 首次访问蓝牙时，macOS 可能要求为 Codex/ChatGPT 授予蓝牙权限；安装文档明确解释该步骤。

## 命令接口

- `codex-pet-link run`：前台运行 Helper，供 launchd 和调试使用。
- `codex-pet-link ensure`：服务已运行则无操作，否则写入 plist 并 bootstrap。
- `codex-pet-link start`：与 `ensure` 相同，向用户输出结果。
- `codex-pet-link stop`：从当前 GUI domain bootout。
- `codex-pet-link restart`：停止后重新启动。
- `codex-pet-link status [--json]`：报告 loaded、running、pid 和路径。
- `codex-pet-link doctor [--json]`：检查 sessions 目录、二进制、launchd 服务和日志。
- 原有 `--source fake|codex` 兼容为 `run --source ...`。

## Codex 插件

插件使用官方最小结构：

- `.codex-plugin/plugin.json`：项目与界面元数据。
- `hooks/hooks.json`：异步 `SessionStart` Hook，匹配 `startup|resume`。
- `scripts/ensure-running.sh`：调用稳定安装路径，缺失时静默退出并留下诊断日志。
- `skills/codex-pet-link/SKILL.md`：指导 Codex 执行安装、状态查询、重启和诊断。

不引入 MCP Server。当前需求只需要本机命令和 Hook，MCP/UI 会增加安装面和进程生命周期复杂度；以后如果确有 Codex 内可点击控制卡片的需求，再单独增加。

## 开源仓库

最终仓库地址为 `https://github.com/sengmitnick/codex-pet-link`，采用 MIT License，包含：

- Swift Package 与 XCTest。
- 安装/卸载脚本。
- Codex repo marketplace 和插件。
- BLE 协议、隐私、安全和故障排查文档。
- GitHub Actions 的 macOS 构建与测试。

现有 Helper 的 Git 历史通过 `git subtree split --prefix=tools/codex-pet-link` 保留。`pet-pal` 主干当前的多宠物和 onboarding 修改不参与抽取。

## 验收

1. 一条自然语言安装指令足以让另一台装有 Codex 和 Swift 的 Mac 完成安装。
2. 安装后 Helper 在终端退出时继续运行。
3. 同时打开多个 Codex 任务只存在一个 Helper。
4. 重启电脑后，首次重新打开 Codex 会恢复 Helper。
5. `doctor` 能区分未安装、sessions 缺失、服务未运行和正常运行。
6. 卸载不删除 Codex 会话或任何用户任务数据。
7. BLE 协议与眼镜端现有实现保持兼容。

