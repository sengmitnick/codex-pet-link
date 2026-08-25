# Installation

## 让 Codex 安装

在 Codex 中发送：

```text
Clone https://github.com/sengmitnick/codex-pet-link, read INSTALL.md, run ./scripts/install.sh, then run codex-pet-link doctor and report the result. Remind me to review the plugin Hooks, click Trust all, and start a new Codex task.
```

安装脚本会 release 构建 Swift Helper，将二进制放到 `~/Library/Application Support/CodexPetLink/bin/`，注册并安装仓库插件，随后启动用户级 launchd 服务。

首次广播时，macOS 可能要求 Codex/ChatGPT 使用蓝牙，请允许。插件安装或更新后，进入插件的“钩子”页面，检查后点击“全部信任”，然后新建一个 Codex 任务，使 Hooks 在新任务中加载。Hook 未变更时，重启电脑不需要重新信任。

如果尚未信任 Hooks，已在运行的 Helper 会从 Codex 本地会话读取粗状态作为降级处理，但不会有任务标题、工具阶段和多任务活动。重启电脑后，未信任的 `SessionStart` Hook 不会运行；信任前可手动执行 `codex-pet-link ensure` 启动 Helper。

## 手动执行

```bash
git clone https://github.com/sengmitnick/codex-pet-link.git
cd codex-pet-link
./scripts/install.sh
codex-pet-link doctor
```

测试广播而不读取真实任务：

```bash
codex-pet-link stop
codex-pet-link run --source fake
```

## 故障排查

```bash
codex-pet-link status --json
codex-pet-link doctor --json
codex-pet-link restart
tail -n 100 "$HOME/Library/Application Support/CodexPetLink/codex-pet-link.error.log"
```

如果眼镜只显示抽象状态，通常是眼镜端仍为 v1；更新 pet-pal 后重新连接。若 Mac 重启后未广播，新建一个 Codex 任务，`SessionStart` 会执行幂等恢复。

## 卸载

```bash
./scripts/uninstall.sh
```

卸载不会删除 `~/.codex/sessions` 或任何项目文件。
