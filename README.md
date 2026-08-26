# Codex Pet Link

Codex Pet Link 把 Mac 上的 Codex 任务活动通过 Bluetooth LE 发给 Rokid 眼镜中的赛博宠物。眼镜像 Codex Pet 一样逐条显示任务标题和最近活动；底栏保留最高优先级任务，例如 `优化引导 · 已修改文件`，而不只是“工作中”。

## 一句话安装

把下面这句话发给 Codex：

```text
请安装并启动 https://github.com/sengmitnick/codex-pet-link，严格按照仓库 INSTALL.md 操作。完成后运行 codex-pet-link doctor，告诉我检查结果，并提醒我在插件的“钩子”页面检查后点击“全部信任”。
```

不需要桌面 App、云服务或 OpenAI API Key。首次安装或 Hooks 发生变更后，需要在 Codex 的插件“钩子”页面检查并点击“全部信任”，再打开一个新任务。信任会按 Hook 内容保存，普通重启电脑不需要重新确认。

未信任 Hooks 时，如果 Helper 已在运行，它会通过 Codex 本地会话识别已进入降级状态，并在眼镜任务区显示 `请信任 Hooks 并新建任务 · 等待确认`，不再只显示无法解释原因的粗状态。真实 Hook 活动到达后，该提示会自动消失。电脑重启后，未信任的 `SessionStart` Hook 无法自动恢复 Helper，可先手动运行 `codex-pet-link ensure`。

## 显示内容

- 任务标题：优先使用 Codex App Server 的 `thread.name`，尚未生成时使用经过清洗和截断的用户意图。
- 执行阶段：正在思考、正在运行命令、正在修改文件、正在搜索、等待确认、已完成或遇到问题。
- 多任务：像 Codex Pet 一样发送完整活动托盘，按需处理、异常、运行、完成排序；进行中的任务不会被刚完成的任务压到下面，每条都包含任务标题和最近活动。
- 最近活动：区分“正在运行命令”和“已运行命令”、“正在修改文件”和“已修改文件”，不会在工具结束后立刻退回笼统的“工作中”。
- 在线状态：眼镜右上角只显示 `Codex 在线`；任务活动显示在宠物活动托盘和底栏。
- 多任务显示：最多四张卡；五个及以上任务显示前三张详情和一张数量摘要。底栏额外任务数独立显示，不会被长标题省略。

## 连接眼镜

眼镜端默认不连接。进入“设备管理”，点击 `Codex：未连接` 开始搜索；搜索中再次点击可取消，连接成功后点击 `Codex：已连接` 可主动断开。

Helper 会持久广播一个短名称，例如 `Codex seng-MacBook-Air FC13`。附近只有一台 Helper 时眼镜自动连接；发现多台时会列出电脑名称，由用户明确选择。之前连接过的电脑只会排在候选第一位，不会绕过选择。

广播名称会向蓝牙范围内的设备暴露缩短后的电脑标签和四位随机后缀。它只用于辨认电脑，不是认证机制。

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

`doctor` 会输出当前 `bluetooth` / `advertisedName`，可用它核对眼镜候选列表中的电脑。

开发和真机测试见 [INSTALL.md](INSTALL.md)，协议见 [docs/protocol.md](docs/protocol.md)。

## 兼容性

- macOS 13+
- 安装了 Codex CLI 和 Swift 6 工具链
- Rokid 眼镜端 pet-pal 支持 v2 活动特征值
- 旧眼镜端仍可读取原有 12 字节 v1 状态特征值

蓝牙只覆盖本地距离；本项目不提供互联网中继。

Helper 的 LaunchAgent 会显式加入 Codex Desktop、Homebrew 和系统命令目录。不要依赖登录 Shell 的 `PATH`；否则系统服务虽在线，App Server 标题查询仍会失败并退回临时标题。
