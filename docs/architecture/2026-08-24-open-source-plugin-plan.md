# Codex Pet Link Task Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use box:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把状态型 BLE PoC 产品化为一句话可安装的 Codex 插件，并在 Rokid 眼镜底栏显示当前 Codex 任务短标题、执行阶段和并发活动数量。

**Architecture:** Codex 插件 Hooks 将输入立即归一化为不含代码、命令参数和路径的活动事件，并通过原子 inbox 文件交给 launchd 托管的 Swift Helper。Helper 用 Hook/JSONL 维护实时状态、用官方 App Server 的 `thread.name` 补全标题，同时保留旧 12 字节状态特征值并在新 BLE 特征值上分片发送任务活动；眼镜订阅两种特征值并对新消息重组。

**Tech Stack:** Swift 6、Foundation、CoreBluetooth、XCTest、launchd、POSIX shell、Codex plugins/hooks、Rokid Ink/JavaScript、Node.js tests、GitHub Actions。

---

## 文件结构

所有修改先留在 `pet-pal` 隔离 worktree。Swift Helper 位于 `tools/codex-pet-link/`，眼镜兼容修改保留在 `pet-pal`；独立仓库发布时只抽取 Helper 子树。

**Create:**

- `tools/codex-pet-link/Sources/CodexPetLinkCore/TaskActivity.swift`：活动、阶段、优先级和标题隐私模型。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/HookEvent.swift`：Hook JSON 最小化解析与工具类别映射。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/ActivityStore.swift`：多任务归并、选主活动和原子 inbox。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/AppServerTitleClient.swift`：用 `thread/read` 读取 `thread.name`。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/ActivityPacket.swift`：v2 活动负载与 20 字节 BLE 分片。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/ServicePaths.swift`：安装、inbox、配置和日志路径。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/LaunchAgentController.swift`：launchd 生命周期。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/Doctor.swift`：结构化健康检查。
- `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/{TaskActivity,HookEvent,ActivityStore,AppServerTitleClient,ActivityPacket,LaunchAgentController,Doctor}Tests.swift`
- `tools/codex-pet-link/scripts/{install,uninstall}.sh`
- `tools/codex-pet-link/tests/install.test.sh`
- `tools/codex-pet-link/plugins/codex-pet-link/.codex-plugin/plugin.json`
- `tools/codex-pet-link/plugins/codex-pet-link/hooks/hooks.json`
- `tools/codex-pet-link/plugins/codex-pet-link/scripts/{ensure-running,forward-event}.sh`
- `tools/codex-pet-link/plugins/codex-pet-link/skills/codex-pet-link/SKILL.md`
- `tools/codex-pet-link/.agents/plugins/marketplace.json`
- `tools/codex-pet-link/{INSTALL,SECURITY,CONTRIBUTING}.md`
- `tools/codex-pet-link/docs/protocol.md`
- `tools/codex-pet-link/.github/workflows/ci.yml`

**Modify:** `BLEPacket.swift`, `CodexBLEPeripheral.swift`, `CodexSessionWatcher.swift`, `main.swift`, Helper README/.gitignore、`src/pages/index/index.ink`、`tests/codex-ble-link.test.cjs`。

### Task 1: 建立任务活动领域模型

**Files:** create `TaskActivity.swift`; test `TaskActivityTests.swift`。

- [ ] **Step 1: 写失败测试**，覆盖标题清洗、24 字符/72 UTF-8 字节上限、`titles-off` 返回空标题，以及优先级 `needsInput > blocked > ready > running > idle`。

```swift
func testSanitizesPromptWithoutLeakingCodeOrPath() {
    XCTAssertEqual(TaskTitle.sanitize("修复 /Users/me/a.swift\n```swift\nsecret()\n```"), "修复")
}
func testPriorityMatchesPetSemantics() {
    XCTAssertGreaterThan(CodexTaskState.needsInput.activityPriority, CodexTaskState.blocked.activityPriority)
}
```

- [ ] **Step 2:** 运行 `cd tools/codex-pet-link && swift test --filter TaskActivityTests`，确认因类型不存在而 FAIL。
- [ ] **Step 3:** 实现 `TaskPhase`（idle/thinking/runningCommand/modifyingFiles/searching/waitingApproval/completed/problem）、`TaskActivity`、`TaskActivitySnapshot`、`TaskTitle.sanitize` 和状态优先级；清洗先去代码块、附件标记、绝对路径，再取首条可读意图和 Unicode 字符上限。
- [ ] **Step 4:** 重跑测试，预期 PASS。
- [ ] **Step 5:** 提交 `feat: model Codex task activity`。

### Task 2: 将 Codex Hooks 归一化为隐私安全事件

**Files:** create `HookEvent.swift`; test `HookEventTests.swift`。

- [ ] **Step 1: 写失败测试**，使用官方字段 `session_id`、`turn_id`、`prompt`、`tool_name`，断言 UserPromptSubmit→thinking、Bash/exec_command→runningCommand、Edit/Write/apply_patch→modifyingFiles、web/search→searching、PermissionRequest→waitingApproval、Stop→completed；编码事件不得含 tool_input 或路径。

```swift
let input = #"{"session_id":"s1","turn_id":"t1","prompt":"修复蓝牙重连","tool_input":{"cmd":"cat /secret"}}"#
let event = try HookEvent.parse(kind: .userPromptSubmit, data: Data(input.utf8), now: date)
XCTAssertEqual(event.title, "修复蓝牙重连")
XCTAssertFalse(String(decoding: try JSONEncoder().encode(event), as: UTF8.self).contains("/secret"))
```

- [ ] **Step 2:** 运行 `swift test --filter HookEventTests`，确认 FAIL。
- [ ] **Step 3:** 实现 `HookKind`、`NormalizedHookEvent: Codable` 和映射；未知工具只映射为 `.thinking`，不复制参数。
- [ ] **Step 4:** 重跑测试，预期 PASS。
- [ ] **Step 5:** 提交 `feat: normalize Codex hook activity`。

### Task 3: 实现并发活动存储和原子 inbox

**Files:** create `ActivityStore.swift`; test `ActivityStoreTests.swift`。

- [ ] **Step 1: 写失败测试**：原子写入两个 session 事件；消费后按状态优先级、再按更新时间选择主活动，`additionalCount == 1`；损坏文件移到 `rejected/`。

```swift
try HookInbox(root: root).enqueue(running)
try HookInbox(root: root).enqueue(needsInput)
var store = ActivityStore()
try store.consume(inbox: HookInbox(root: root))
XCTAssertEqual(store.snapshot().primary?.sessionID, "needs-input")
XCTAssertEqual(store.snapshot().additionalCount, 1)
```

- [ ] **Step 2:** 运行 `swift test --filter ActivityStoreTests`，确认 FAIL。
- [ ] **Step 3:** 实现 UUID 临时文件→原子 rename、按文件名消费、成功后删除、损坏文件隔离、事件归并和完成活动 30 分钟过期。
- [ ] **Step 4:** 重跑测试，预期 PASS。
- [ ] **Step 5:** 提交 `feat: queue concurrent Codex activities`。

### Task 4: 用 App Server 补全 Codex 任务标题

**Files:** create `AppServerTitleClient.swift`; test `AppServerTitleClientTests.swift`。

- [ ] **Step 1: 写失败测试**，注入假的逐行 JSON transport，断言发送 `thread/read` 且 `includeTurns=false`，只接收匹配 response id 的 `result.thread.name`；null name、超时和退出返回 nil。

```swift
let title = try await client.title(threadID: "s1")
XCTAssertEqual(transport.sentMethod, "thread/read")
XCTAssertEqual(transport.sentParams["includeTurns"] as? Bool, false)
XCTAssertEqual(title, "优化引导")
```

- [ ] **Step 2:** 运行 `swift test --filter AppServerTitleClientTests`，确认 FAIL。
- [ ] **Step 3:** 实现 `codex app-server --listen stdio://` 子进程 transport、JSON-RPC 初始化、递增 id、2 秒超时和崩溃后退避；结果再次 `TaskTitle.sanitize`。
- [ ] **Step 4:** 重跑测试；本地 smoke 只输出标题长度，预期非零且不打印标题。
- [ ] **Step 5:** 提交 `feat: resolve task titles from Codex app server`。

### Task 5: 新增 BLE v2 活动分片并保留 v1

**Files:** create `ActivityPacket.swift`; modify `BLEPacket.swift`, `CodexBLEPeripheral.swift`; test `ActivityPacketTests.swift` 和 `BLEPacketTests.swift`。

- [ ] **Step 1: 写失败测试**，新 UUID 为 `7d6b0003-9d7e-4e8a-a7b7-5c2e8f4a1100`；每帧最多 20 字节，头为 `[0xC8,1,seqLo,seqHi,index,count,payloadLength]`；乱序可重组、缺帧无快照，v1 golden bytes 不变。
- [ ] **Step 2:** 运行 `swift test --filter 'ActivityPacketTests|BLEPacketTests'`，确认 Activity FAIL、v1 PASS。
- [ ] **Step 3:** 实现负载 `[state,phase,additionalCount,titleByteCount,titleUTF8...]`，每帧 13 字节 payload、最多 6 帧、UInt16 序号；标题按完整 Unicode scalar 截到 72 UTF-8 bytes。
- [ ] **Step 4:** 同一 service 发布 status/activity 两个 characteristic；活动变化和 10 秒心跳先发 v1 再发全部 v2 帧；status read 仍是 12 字节。
- [ ] **Step 5:** 运行 Swift 全套，预期 PASS。
- [ ] **Step 6:** 提交 `feat: broadcast task activity over BLE`。

### Task 6: 服务生命周期、CLI 和 Hook 写入

**Files:** create `ServicePaths.swift`, `LaunchAgentController.swift`, `Doctor.swift` 及测试；modify `main.swift`。

- [ ] **Step 1:** 写路径/plist失败测试：数据位于 `~/Library/Application Support/CodexPetLink`，plist 不在 `~/Library/LaunchAgents`，`RunAtLoad=false`、`KeepAlive=true`、参数为 `run`。
- [ ] **Step 2:** 实现注入式 launchctl runner；`ensure` 幂等 bootstrap，`stop` 用精确 label bootout。
- [ ] **Step 3:** 写 CLI/doctor失败测试，覆盖 `run/ensure/start/stop/restart/status/doctor/hook/privacy` 和旧 `--source` 兼容。
- [ ] **Step 4:** 实现命令；`hook EVENT` 只 enqueue 归一化事件；daemon 每 250ms 消费 inbox、每 1 秒 JSONL fallback、每 5 秒尝试 App Server 标题。
- [ ] **Step 5:** 运行 `swift test` 与 `swift run codex-pet-link status --json`，预期测试 PASS 且输出合法 JSON。
- [ ] **Step 6:** 提交 `feat: add service and hook command lifecycle`。

### Task 7: 制作一句话安装的 Codex 插件

**Files:** create shell scripts、plugin manifest/hooks/skill/marketplace 和 `tests/install.test.sh`。

- [ ] **Step 1:** 写 shell 失败测试：临时 HOME 和 stub 命令运行安装两次；断言稳定二进制路径、插件安装幂等、不会写 `~/Library/LaunchAgents`。
- [ ] **Step 2:** 实现 `install.sh`：检查 macOS 13、Swift、Codex CLI，release build，原子安装 binary，注册 marketplace/plugin，执行 ensure/doctor。
- [ ] **Step 3:** 实现 Hooks：SessionStart 调用 ensure 和 forward；UserPromptSubmit、PreToolUse、PostToolUse、PermissionRequest、Stop 调用 `forward-event.sh <Event>`，stdin pipe 给 `codex-pet-link hook <Event>`。
- [ ] **Step 4:** 实现 Skill，写清 install/status/restart/doctor/privacy 命令和重启恢复逻辑。
- [ ] **Step 5:** 实现安全卸载且不删除 `~/.codex/sessions`；运行 shell 测试 PASS。
- [ ] **Step 6:** 提交 `feat: install Codex Pet Link as a plugin`。

### Task 8: 眼镜端重组活动并显示任务名称

**Files:** modify `src/pages/index/index.ink`; modify `tests/codex-ble-link.test.cjs`。

- [ ] **Step 1:** 写 JS 失败测试：乱序中文分片后得到标题“优化引导”、阶段“正在修改文件”和 `+1`；缺片 2 秒后保留上个完整标题。
- [ ] **Step 2:** 写兼容测试：没有 v2 characteristic 仍连接并显示 v1；有 v2 时订阅两个 characteristic，cleanup 两者。
- [ ] **Step 3:** 运行 `node --test tests/codex-ble-link.test.cjs`，确认新增断言 FAIL。
- [ ] **Step 4:** 实现 `decodeCodexActivityFrame`/`CodexActivityReassembler` 和数据字段 `codexTaskTitle/codexTaskPhaseText/codexAdditionalActivityCount/codexActivityDisplayText`。
- [ ] **Step 5:** 底栏改为 `标题 · 阶段 +N`，无活动为 `Codex · 空闲`；右上角仍只显示在线；标题变化触发一次气泡，phase 更新不打断动画。
- [ ] **Step 6:** 重跑 Node 测试，预期 PASS。
- [ ] **Step 7:** 提交 `feat: show Codex task activity on glasses`。

### Task 9: 文档、CI、集成和真机交付

**Files:** create/update README、INSTALL、SECURITY、CONTRIBUTING、protocol、CI、LICENSE。

- [ ] **Step 1:** 文档明确一句话安装、`thread.name`/prompt fallback、标题关闭、Hook 不持久化原文、BLE v1/v2、重启恢复和诊断。
- [ ] **Step 2:** CI 在 macOS 执行 `swift test`，shell job 执行安装测试；README 给出复制给 Codex 的安装句子。
- [ ] **Step 3:** 全量运行 `swift test`、`bash tests/install.test.sh`、`node --test tests/codex-ble-link.test.cjs`、`bash -n`，全部成功。
- [ ] **Step 4:** 本机 smoke install→ensure→doctor→stop→SessionStart ensure；日志只出现 session id、state、phase 和标题长度。
- [ ] **Step 5:** `git subtree split --prefix=tools/codex-pet-link`，确认独立根包含 Package/plugin；不自行推送远端。
- [ ] **Step 6:** 合并前只带入 Helper 与两处眼镜文件的目标提交，不覆盖主干多宠物/图片生成改动；重叠时语义合并并重测。
- [ ] **Step 7:** 构建 Rokid 包交用户真机验证 BLE v2、中文标题、阶段、多任务、v1 fallback 和重连；不声称未执行的真机验证已完成。
- [ ] **Step 8:** 提交 `docs: document Codex task activity bridge`。

## 自检结果

- 任务标题、阶段、并发优先级、隐私开关、App Server fallback、Hook 恢复、BLE v1 兼容和真机边界均有对应任务。
- 无 TBD/TODO/“稍后实现”占位项。
- 类型统一使用 `TaskActivitySnapshot`、`TaskPhase`、`NormalizedHookEvent`、`ActivityPacket` 和 `codexActivityDisplayText`。
