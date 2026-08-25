# Codex Pet Link 开源插件化设计

**日期：** 2026-08-24  
**状态：** 已确认（任务活动修订）

## 目标

把 `pet-pal/tools/codex-pet-link` 的 Swift PoC 独立为公开项目 `sengmitnick/codex-pet-link`。其他 macOS 用户不安装桌面 App，只需把一条安装指令发给 Codex，由 Codex 完成构建、安装插件、启动 Helper 和健康检查。眼镜中的赛博宠物不只显示“工作中”等抽象状态，还应像 Codex 自带宠物一样显示当前任务短标题和执行阶段。

推荐给其他用户的指令为：

```text
请安装并启动 https://github.com/sengmitnick/codex-pet-link，严格按照仓库 INSTALL.md 操作。完成后运行 codex-pet-link doctor，告诉我检查结果，并提醒我在插件的“钩子”页面检查后点击“全部信任”。
```

## 产品边界

- macOS 13 及以上。
- 使用 Swift Helper 汇总 Codex Hook、Codex App Server 和本地会话事件，并通过 BLE 广播任务活动。
- 不创建菜单栏 App、设置窗口、云端服务或 Codex 内嵌页面。
- 不上传任务内容，不要求 OpenAI API Key。
- 插件负责安装与服务管理，也负责把任务生命周期事件交给 Helper。
- BLE 默认只发送 Codex 生成或本地缩短后的任务标题和阶段，不发送完整 prompt、代码、回复或路径；用户可关闭标题传输并退回纯状态模式。
- 电脑重启后不要求登录时自动广播；用户重新打开 Codex 时，由 `SessionStart` Hook 恢复服务。

## 运行结构

```text
Codex lifecycle hooks -----------+
                                 v
Codex App Server thread.name -> Swift BLE Helper -> Rokid pet-pal
                                 ^
Codex JSONL failure fallback ----+
                                 |
Codex SessionStart -> launchd ensure
```

Helper 仍由 `launchd` 托管，以解决多个 Codex 会话并发启动、进程意外退出和终端关闭的问题。但 LaunchAgent plist 放在应用数据目录，而不是 `~/Library/LaunchAgents`：重启后它不会自行加载，必须由下一次 Codex `SessionStart` Hook 执行 `ensure`。

## 任务活动模型

每个 Codex 会话形成一条任务活动，包含短标题、任务状态、执行阶段和最近更新时间。标题优先使用 Codex App Server 返回的用户可见 `thread.name`；标题尚未生成或 App Server 暂时不可用时，使用 Hook 的用户 prompt 生成本地短标题。缩短过程删除附件标记、代码块、路径和多余空白，只保留第一条可读意图。

任务状态保持 `running / needs_input / ready / blocked`。执行阶段用于告诉用户 Codex 具体在做什么，例如“正在思考”“正在运行命令”“正在修改文件”“正在搜索”“等待确认”“已完成”。阶段来自 Hook 的工具事件，不把命令、参数、文件名或工具输出传给眼镜。

Helper 可以同时维护多条活动，但眼镜底栏只展示一条。选择顺序为：需处理、遇到问题、已完成、工作中；同级选择最近更新者。还有其他活动时追加简短数量提示，例如 `+1`。

## 眼镜呈现

任务活动继续位于底部状态栏，显示为一条可省略的文本，例如：

- `连接 Codex · 正在运行命令`
- `优化引导 · 正在修改文件`
- `修复蓝牙重连 · 等待确认 +1`

右上角只显示设备在线状态，不显示任务标题或阶段。没有活动时底栏显示 `Codex · 空闲`。有活动时底栏显示最高优先级任务，并在宠物上方显示完整多任务活动托盘，每条都包含标题和最近活动。任务标题变化触发一次短气泡；单纯的工具阶段更新不反复打断宠物动画。

## BLE 兼容

现有 12 字节状态特征值保持不变，旧版眼镜仍能收到五态。新增任务活动特征值承载短标题、阶段、活动数量和序号。活动消息采用可分片通知，按最低 BLE ATT 负载拆包；眼镜按消息序号重组，缺片或超时则丢弃，不覆盖最近完整活动。连接建立和 10 秒心跳时重发完整快照。

## 安装体验

安装脚本执行以下幂等步骤：

1. 检查 macOS、Swift 和 Codex CLI。
2. Release 构建 Swift Helper。
3. 安装到 `~/Library/Application Support/CodexPetLink/bin/codex-pet-link`。
4. 在 `~/.local/bin/codex-pet-link` 创建命令入口。
5. 添加 GitHub 仓库 marketplace，安装 `codex-pet-link` 插件。
6. 执行 `codex-pet-link ensure` 立即启动 BLE Helper。
7. 执行 `codex-pet-link doctor` 输出最终结果。

插件 Hook 首次运行需要用户在 Codex 中审查并信任。信任按 Hook 内容保存：普通重启不再询问，Hook 发生变更时需重新审查。Helper 首次访问蓝牙时，macOS 可能要求为 Codex/ChatGPT 授予蓝牙权限；安装文档明确解释该步骤。

未信任 Hooks 时使用可操作降级策略：如果安装脚本已启动 Helper，Helper 继续轮询 Codex JSONL 会话以判断 Codex 是否已有任务状态。当 JSONL 非空闲但 Hook 活动列表为空时，Helper 合成一条高优先级的 `请信任 Hooks 并新建任务 · 等待确认` 活动；真实 Hook 活动到达后自动替换它，完全空闲时不误提示。重启电脑后若 Hooks 仍未信任，`SessionStart` 不会恢复 Helper，用户需手动执行 `codex-pet-link ensure`。

## 命令接口

- `codex-pet-link run`：前台运行 Helper，供 launchd 和调试使用。
- `codex-pet-link ensure`：服务已运行则无操作，否则写入 plist 并 bootstrap。
- `codex-pet-link start`：与 `ensure` 相同，向用户输出结果。
- `codex-pet-link stop`：从当前 GUI domain bootout。
- `codex-pet-link restart`：停止后重新启动。
- `codex-pet-link status [--json]`：报告 loaded、running、pid 和路径。
- `codex-pet-link doctor [--json]`：检查 sessions 目录、二进制、launchd 服务和日志。
- `codex-pet-link hook`：从标准输入接收 Codex Hook JSON，只提取任务标识、短标题来源、状态和阶段后交给运行中的 Helper。
- `codex-pet-link privacy titles-on|titles-off`：控制 BLE 是否包含短任务标题。
- 原有 `--source fake|codex` 兼容为 `run --source ...`。

## Codex 插件

插件使用官方最小结构：

- `.codex-plugin/plugin.json`：项目与界面元数据。
- `hooks/hooks.json`：包含服务恢复、用户提交、工具执行、授权请求和任务停止 Hook。
- `scripts/ensure-running.sh`：在 `SessionStart` 调用稳定安装路径，缺失时静默退出并留下诊断日志。
- `scripts/forward-event.sh`：把 Hook 标准输入原样交给本机 Helper；Helper 只持久化归一化活动，不保留完整 Hook 输入。
- `skills/codex-pet-link/SKILL.md`：指导 Codex 执行安装、状态查询、重启和诊断。

不引入 MCP Server。当前需求只需要本机命令和 Hook，MCP/UI 会增加安装面和进程生命周期复杂度；以后如果确有 Codex 内可点击控制卡片的需求，再单独增加。

Hook 不直接连接 BLE 进程。`codex-pet-link hook` 将归一化后的单个事件原子写入应用数据目录的 `inbox/`；常驻 Helper 轮询并消费文件。这样多个 Codex 任务并发触发 Hook 时不会互相覆盖，Helper 暂时尚未启动时事件也不会丢失。原始 Hook JSON 不落盘。

## 开源仓库

最终仓库地址为 `https://github.com/sengmitnick/codex-pet-link`，采用 MIT License，包含：

- Swift Package 与 XCTest。
- 安装/卸载脚本。
- Codex repo marketplace 和插件。
- App Server 标题读取、BLE 协议、隐私、安全和故障排查文档。
- GitHub Actions 的 macOS 构建与测试。

现有 Helper 的 Git 历史通过 `git subtree split --prefix=tools/codex-pet-link` 保留。`pet-pal` 主干当前的多宠物和 onboarding 修改不参与抽取。

## 验收

1. 一条自然语言安装指令足以让另一台装有 Codex 和 Swift 的 Mac 完成安装。
2. 安装后 Helper 在终端退出时继续运行。
3. 同时打开多个 Codex 任务只存在一个 Helper。
4. 重启电脑后，首次重新打开 Codex 会恢复 Helper。
5. `doctor` 能区分未安装、sessions 缺失、服务未运行和正常运行。
6. 卸载不删除 Codex 会话或任何用户任务数据。
7. 新任务开始后，眼镜底栏在 3 秒内显示短任务名和当前阶段，不再只显示“工作中”。
8. 工具执行只改变阶段，不把命令、参数、代码或路径发送到 BLE。
9. App Server 有 `thread.name` 时优先显示该标题；无标题时显示经过清洗和截断的 prompt 摘要。
10. 多任务时按需处理、异常、完成、运行排序，逐条显示任务标题和最近活动，不折叠为几个笼统状态。
11. 关闭标题传输后，BLE 回退为纯状态文案。
12. 旧状态特征值与眼镜端现有实现保持兼容。
