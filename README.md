# Codex Pet Link

Codex Pet Link 把 Mac 上的 Codex 任务活动通过 Bluetooth LE 发给 Rokid 眼镜中的赛博宠物。眼镜底栏显示的是具体任务和当前阶段，例如 `优化引导 · 正在修改文件`，而不只是“工作中”。

## 一句话安装

把下面这句话发给 Codex：

> 请安装并启动 https://github.com/sengmitnick/codex-pet-link，严格按照仓库 INSTALL.md 操作，完成后运行 `codex-pet-link doctor` 并告诉我检查结果。

不需要桌面 App、云服务或 OpenAI API Key。安装后由 Codex 插件 Hooks 更新任务活动；重新启动电脑后，打开一个新的 Codex 任务会恢复 Helper。

## 显示内容

- 任务标题：优先使用 Codex App Server 的 `thread.name`，尚未生成时使用经过清洗和截断的用户意图。
- 执行阶段：正在思考、正在运行命令、正在修改文件、正在搜索、等待确认、已完成或遇到问题。
- 多任务：按需处理、异常、完成、运行的顺序选择一条，并显示额外数量 `+N`。
- 在线状态：眼镜右上角只显示 `Codex 在线`；任务活动留在底栏。

不会通过 BLE 发送完整 prompt、代码、命令参数、工具输出或文件路径。若不希望发送短任务标题，可执行：

```bash
codex-pet-link privacy titles-off
```

## 常用命令

```bash
codex-pet-link status --json
codex-pet-link doctor
codex-pet-link restart
codex-pet-link privacy titles-on
```

开发和真机测试见 [INSTALL.md](INSTALL.md)，协议见 [docs/protocol.md](docs/protocol.md)。

## 兼容性

- macOS 13+
- 安装了 Codex CLI 和 Swift 6 工具链
- Rokid 眼镜端 pet-pal 支持 v2 活动特征值
- 旧眼镜端仍可读取原有 12 字节 v1 状态特征值

蓝牙只覆盖本地距离；本项目不提供互联网中继。
