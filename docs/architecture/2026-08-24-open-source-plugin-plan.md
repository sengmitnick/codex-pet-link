# Codex Pet Link Open-source Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use box:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 macOS BLE Helper 产品化为可由另一位用户通过一句 Codex 指令安装、并在每次 Codex 启动时自动恢复的独立开源项目。

**Architecture:** Swift 可执行文件新增 launchd 服务管理命令，安装脚本将它放到用户稳定路径。仓库级 Codex marketplace 提供 Skill 和异步 `SessionStart` Hook；Hook 只调用幂等的 `ensure`，不托管长进程。

**Tech Stack:** Swift 6、Foundation、CoreBluetooth、XCTest、launchd、POSIX shell、Codex plugins/hooks、GitHub Actions。

---

## 文件结构

所有实现先在 `pet-pal` 隔离 worktree 的 `tools/codex-pet-link/` 下完成；Task 7 抽取后，该目录内容成为新仓库根目录。

**Create:**

- `tools/codex-pet-link/Sources/CodexPetLinkCore/ServicePaths.swift`：所有用户级安装和状态路径。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/LaunchAgentController.swift`：plist 生成与 launchctl 生命周期。
- `tools/codex-pet-link/Sources/CodexPetLinkCore/Doctor.swift`：可测试的健康检查报告。
- `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/LaunchAgentControllerTests.swift`
- `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/DoctorTests.swift`
- `tools/codex-pet-link/scripts/install.sh`
- `tools/codex-pet-link/scripts/uninstall.sh`
- `tools/codex-pet-link/tests/install.test.sh`
- `tools/codex-pet-link/plugins/codex-pet-link/.codex-plugin/plugin.json`
- `tools/codex-pet-link/plugins/codex-pet-link/hooks/hooks.json`
- `tools/codex-pet-link/plugins/codex-pet-link/scripts/ensure-running.sh`
- `tools/codex-pet-link/plugins/codex-pet-link/skills/codex-pet-link/SKILL.md`
- `tools/codex-pet-link/.agents/plugins/marketplace.json`
- `tools/codex-pet-link/LICENSE`
- `tools/codex-pet-link/INSTALL.md`
- `tools/codex-pet-link/SECURITY.md`
- `tools/codex-pet-link/CONTRIBUTING.md`
- `tools/codex-pet-link/docs/protocol.md`
- `tools/codex-pet-link/.github/workflows/ci.yml`

**Modify:**

- `tools/codex-pet-link/Sources/codex-pet-link/main.swift`：子命令路由和兼容参数。
- `tools/codex-pet-link/README.md`：开源项目首页和一句话安装。
- `tools/codex-pet-link/.gitignore`：本地构建与测试产物。

### Task 1: 定义稳定路径和 launchd plist

**Files:**

- Create: `tools/codex-pet-link/Sources/CodexPetLinkCore/ServicePaths.swift`
- Create: `tools/codex-pet-link/Sources/CodexPetLinkCore/LaunchAgentController.swift`
- Create: `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/LaunchAgentControllerTests.swift`

- [ ] **Step 1: 写 plist 和路径失败测试**

测试使用临时 home，断言 label 为 `com.rokid.codex-pet-link`、plist 不在 `~/Library/LaunchAgents`、`RunAtLoad=false`、`KeepAlive=true`，且 ProgramArguments 指向当前安装二进制和 `run`：

```swift
import Foundation
import XCTest
@testable import CodexPetLinkCore

final class LaunchAgentControllerTests: XCTestCase {
    func testServicePathsStayInsideUserDataDirectory() {
        let home = URL(fileURLWithPath: "/tmp/test-home")
        let paths = ServicePaths(homeDirectory: home)
        XCTAssertEqual(paths.executable.path, "/tmp/test-home/Library/Application Support/CodexPetLink/bin/codex-pet-link")
        XCTAssertEqual(paths.plist.path, "/tmp/test-home/Library/Application Support/CodexPetLink/com.rokid.codex-pet-link.plist")
        XCTAssertFalse(paths.plist.path.contains("Library/LaunchAgents"))
    }

    func testPlistStartsRunCommandAndDoesNotLoadAtLogin() throws {
        let paths = ServicePaths(homeDirectory: URL(fileURLWithPath: "/tmp/test-home"))
        let data = try LaunchAgentController.plistData(paths: paths)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(value["Label"] as? String, LaunchAgentController.label)
        XCTAssertEqual(value["ProgramArguments"] as? [String], [paths.executable.path, "run"])
        XCTAssertEqual(value["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(value["KeepAlive"] as? Bool, true)
    }
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `cd tools/codex-pet-link && swift test --filter LaunchAgentControllerTests`

Expected: FAIL，`ServicePaths` 和 `LaunchAgentController` 不存在。

- [ ] **Step 3: 实现路径和 plist**

```swift
// ServicePaths.swift
import Foundation

public struct ServicePaths: Sendable {
    public let homeDirectory: URL
    public var dataDirectory: URL { homeDirectory.appendingPathComponent("Library/Application Support/CodexPetLink") }
    public var binDirectory: URL { dataDirectory.appendingPathComponent("bin") }
    public var executable: URL { binDirectory.appendingPathComponent("codex-pet-link") }
    public var plist: URL { dataDirectory.appendingPathComponent("com.rokid.codex-pet-link.plist") }
    public var stdoutLog: URL { dataDirectory.appendingPathComponent("codex-pet-link.log") }
    public var stderrLog: URL { dataDirectory.appendingPathComponent("codex-pet-link.error.log") }
    public var sessions: URL {
        if let root = ProcessInfo.processInfo.environment["CODEX_HOME"], !root.isEmpty {
            return URL(fileURLWithPath: root).appendingPathComponent("sessions")
        }
        return homeDirectory.appendingPathComponent(".codex/sessions")
    }
    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }
}
```

```swift
// LaunchAgentController.swift
import Foundation

public struct LaunchAgentController {
    public static let label = "com.rokid.codex-pet-link"

    public static func plistData(paths: ServicePaths) throws -> Data {
        let value: [String: Any] = [
            "Label": label,
            "ProgramArguments": [paths.executable.path, "run"],
            "RunAtLoad": false,
            "KeepAlive": true,
            "StandardOutPath": paths.stdoutLog.path,
            "StandardErrorPath": paths.stderrLog.path,
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `cd tools/codex-pet-link && swift test --filter LaunchAgentControllerTests`

Expected: 2 tests PASS。

- [ ] **Step 5: 提交**

```bash
git add tools/codex-pet-link/Sources/CodexPetLinkCore tools/codex-pet-link/Tests/CodexPetLinkCoreTests
git commit -m "feat: define Codex Pet Link service paths"
```

### Task 2: 实现幂等服务生命周期

**Files:**

- Modify: `tools/codex-pet-link/Sources/CodexPetLinkCore/LaunchAgentController.swift`
- Modify: `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/LaunchAgentControllerTests.swift`

- [ ] **Step 1: 写 command runner 和幂等 ensure 失败测试**

新增注入式 runner，测试 loaded 时不 bootstrap，未 loaded 时依次创建目录、写 plist、调用 `launchctl bootstrap gui/<uid> <plist>`；测试 `stop` 调用 `bootout gui/<uid>/<label>`。

```swift
private final class RecordingRunner: LaunchCommandRunning, @unchecked Sendable {
    var results: [Int32]
    var calls: [[String]] = []
    init(results: [Int32]) { self.results = results }
    func run(_ arguments: [String]) -> Int32 {
        calls.append(arguments)
        return results.removeFirst()
    }
}

private func temporaryPaths() -> ServicePaths {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return ServicePaths(homeDirectory: home)
}

func testEnsureDoesNothingWhenAlreadyLoaded() throws {
    let runner = RecordingRunner(results: [0])
    let controller = LaunchAgentController(paths: temporaryPaths(), uid: 501, runner: runner)
    XCTAssertEqual(try controller.ensure(), .alreadyRunning)
    XCTAssertEqual(runner.calls, [["print", "gui/501/com.rokid.codex-pet-link"]])
}

func testEnsureBootstrapsWhenMissing() throws {
    let runner = RecordingRunner(results: [113, 0])
    let controller = LaunchAgentController(paths: temporaryPaths(), uid: 501, runner: runner)
    XCTAssertEqual(try controller.ensure(), .started)
    XCTAssertEqual(Array(runner.calls.last!.prefix(2)), ["bootstrap", "gui/501"])
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `cd tools/codex-pet-link && swift test --filter LaunchAgentControllerTests`

Expected: FAIL，缺少 `LaunchCommandRunning`、实例初始化和 `ensure()`。

- [ ] **Step 3: 实现 command runner、ensure、stop 和 status**

`ProcessLaunchCommandRunner` 固定执行 `/bin/launchctl`。`ensure()` 先执行 `print`，存在则返回 `.alreadyRunning`；不存在则原子写 plist 并 bootstrap。`stop()` 只对已加载服务 bootout。`status()` 返回 `loaded` 与 `running`，不通过进程名扫描，避免误杀其他用户进程。

- [ ] **Step 4: 补充并运行 stop/status/并发幂等测试**

Run: `cd tools/codex-pet-link && swift test --filter LaunchAgentControllerTests`

Expected: 所有 LaunchAgentController 测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add tools/codex-pet-link/Sources/CodexPetLinkCore/LaunchAgentController.swift tools/codex-pet-link/Tests/CodexPetLinkCoreTests/LaunchAgentControllerTests.swift
git commit -m "feat: manage the BLE helper with launchd"
```

### Task 3: 提供 CLI 子命令和 doctor

**Files:**

- Create: `tools/codex-pet-link/Sources/CodexPetLinkCore/Doctor.swift`
- Create: `tools/codex-pet-link/Tests/CodexPetLinkCoreTests/DoctorTests.swift`
- Modify: `tools/codex-pet-link/Sources/codex-pet-link/main.swift`

- [ ] **Step 1: 写 doctor 失败测试**

```swift
import Foundation
import XCTest
@testable import CodexPetLinkCore

final class DoctorTests: XCTestCase {
    func testHealthyReportRequiresExecutableSessionsAndService() throws {
        let fixture = try DoctorFixture()
        defer { fixture.remove() }
        try fixture.createExecutable()
        try FileManager.default.createDirectory(at: fixture.paths.sessions, withIntermediateDirectories: true)
        let report = Doctor.inspect(paths: fixture.paths, serviceLoaded: true)
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.checks.map(\.name), ["executable", "sessions", "service"])
    }

    func testMissingSessionsIsActionable() throws {
        let fixture = try DoctorFixture()
        defer { fixture.remove() }
        let report = Doctor.inspect(paths: fixture.paths, serviceLoaded: false)
        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.checks.contains { $0.name == "sessions" && !$0.passed })
    }
}

private final class DoctorFixture {
    let paths: ServicePaths
    init() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        paths = ServicePaths(homeDirectory: home)
        try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
    }
    func createExecutable() throws {
        try Data("binary".utf8).write(to: paths.executable)
    }
    func remove() { try? FileManager.default.removeItem(at: paths.homeDirectory) }
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `cd tools/codex-pet-link && swift test --filter DoctorTests`

Expected: FAIL，`Doctor` 不存在。

- [ ] **Step 3: 实现 Codable doctor 报告**

`DoctorCheck` 包含 `name`、`passed`、`message`，`DoctorReport` 包含 `isHealthy` 与 checks；文本输出逐项使用 `[ok]`/`[fail]`，JSON 输出使用 `JSONEncoder`，不得读取或打印会话正文。

- [ ] **Step 4: 重构 CLI 路由**

`main.swift` 接受 `run|ensure|start|stop|restart|status|doctor`。无子命令但含旧 `--source` 时按 `run` 处理；完全无参数时显示简短帮助，不隐式启动服务。`run` 默认 sessions 使用 `ServicePaths.sessions`，保留 `--sessions` 覆盖。

- [ ] **Step 5: 运行单元测试与 CLI smoke test**

Run:

```bash
cd tools/codex-pet-link
swift test
swift run codex-pet-link status --json
swift run codex-pet-link doctor --json
```

Expected: 现有 12 个测试和新增测试全部 PASS；两个命令输出合法 JSON，未安装状态不崩溃。

- [ ] **Step 6: 提交**

```bash
git add tools/codex-pet-link/Sources tools/codex-pet-link/Tests
git commit -m "feat: add service and diagnostic commands"
```

### Task 4: 构建幂等安装和卸载脚本

**Files:**

- Create: `tools/codex-pet-link/scripts/install.sh`
- Create: `tools/codex-pet-link/scripts/uninstall.sh`
- Create: `tools/codex-pet-link/tests/install.test.sh`
- Modify: `tools/codex-pet-link/.gitignore`

- [ ] **Step 1: 写隔离 HOME 的失败测试**

`tests/install.test.sh` 使用 `mktemp -d`，通过 `CODEX_PET_LINK_HOME` 和 `CODEX_PET_LINK_BUILD_BINARY` 注入测试路径，验证重复安装不会追加或损坏文件、可执行文件权限正确、卸载只删除 CodexPetLink 自有文件。

```sh
#!/bin/sh
set -eu
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fake="$fixture/fake-binary"
printf '#!/bin/sh\nexit 0\n' > "$fake"
chmod +x "$fake"
CODEX_PET_LINK_HOME="$fixture/home" CODEX_PET_LINK_BUILD_BINARY="$fake" scripts/install.sh --skip-plugin --skip-start
CODEX_PET_LINK_HOME="$fixture/home" CODEX_PET_LINK_BUILD_BINARY="$fake" scripts/install.sh --skip-plugin --skip-start
test -x "$fixture/home/Library/Application Support/CodexPetLink/bin/codex-pet-link"
test -L "$fixture/home/.local/bin/codex-pet-link"
CODEX_PET_LINK_HOME="$fixture/home" scripts/uninstall.sh --yes
test ! -e "$fixture/home/Library/Application Support/CodexPetLink"
```

- [ ] **Step 2: 运行并确认失败**

Run: `cd tools/codex-pet-link && sh tests/install.test.sh`

Expected: FAIL，`scripts/install.sh` 不存在。

- [ ] **Step 3: 实现安装脚本**

脚本使用 `set -eu`，拒绝非 Darwin，检查 `swift` 和 `codex`。默认执行 `swift build -c release` 并复制 `.build/release/codex-pet-link`；测试注入只允许显式环境变量。使用临时文件再 `mv`，创建 `~/.local/bin` symlink，随后执行：

```sh
codex plugin marketplace add sengmitnick/codex-pet-link
codex plugin add codex-pet-link@codex-pet-link
"$install_binary" ensure
"$install_binary" doctor
```

`--skip-plugin` 和 `--skip-start` 只用于测试与本地开发。脚本不得使用 `sudo`，不得修改 `~/.codex/config.toml` 或用户现有 hooks。

- [ ] **Step 4: 实现安全卸载**

卸载先执行安装二进制 `stop`，删除稳定 symlink、CodexPetLink 数据目录并调用 `codex plugin remove codex-pet-link`。只有 `--yes` 才非交互执行；不删除 `~/.codex/sessions`、marketplace 仓库或其他插件。

- [ ] **Step 5: 运行 shell 测试和 shellcheck 可用性检查**

Run:

```bash
cd tools/codex-pet-link
sh -n scripts/install.sh scripts/uninstall.sh tests/install.test.sh
sh tests/install.test.sh
```

Expected: syntax PASS，安装测试 PASS。

- [ ] **Step 6: 提交**

```bash
git add tools/codex-pet-link/scripts tools/codex-pet-link/tests tools/codex-pet-link/.gitignore
git commit -m "feat: add one-command user installation"
```

### Task 5: 创建 Codex 插件、Hook 和 Skill

**Files:**

- Create: `tools/codex-pet-link/plugins/codex-pet-link/.codex-plugin/plugin.json`
- Create: `tools/codex-pet-link/plugins/codex-pet-link/hooks/hooks.json`
- Create: `tools/codex-pet-link/plugins/codex-pet-link/scripts/ensure-running.sh`
- Create: `tools/codex-pet-link/plugins/codex-pet-link/skills/codex-pet-link/SKILL.md`
- Create: `tools/codex-pet-link/.agents/plugins/marketplace.json`

- [ ] **Step 1: 用 plugin-creator 生成 repo marketplace 骨架**

Run from `/Users/seng/.codex/skills/.system/plugin-creator`:

```bash
python3 scripts/create_basic_plugin.py codex-pet-link \
  --path /Users/seng/Documents/RokidAIUI/pet-pal/.worktrees/codex-pet-link-open-source/tools/codex-pet-link/plugins \
  --marketplace-path /Users/seng/Documents/RokidAIUI/pet-pal/.worktrees/codex-pet-link-open-source/tools/codex-pet-link/.agents/plugins/marketplace.json \
  --marketplace-name codex-pet-link \
  --with-skills --with-hooks --with-scripts --with-marketplace
```

Expected: 插件目录、manifest 和 marketplace 生成成功。

- [ ] **Step 2: 填写 manifest 与 marketplace 元数据**

manifest 使用 `0.1.0`、MIT、仓库 `https://github.com/sengmitnick/codex-pet-link`，界面名 `Codex Pet Link`，category `Developer Tools`，不声明 MCP/apps。marketplace 名称为 `codex-pet-link`，entry 保留 `AVAILABLE`/`ON_INSTALL`。

- [ ] **Step 3: 写 SessionStart Hook**

```json
{
  "description": "Ensure the local Codex Pet Link BLE helper is running.",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "^(startup|resume)$",
        "hooks": [
          {
            "type": "command",
            "command": "/bin/sh \"${PLUGIN_ROOT}/scripts/ensure-running.sh\"",
            "async": true,
            "timeout": 15,
            "statusMessage": "Checking Codex Pet Link"
          }
        ]
      }
    ]
  }
}
```

Hook 脚本只执行 `"$HOME/.local/bin/codex-pet-link" ensure`；命令缺失时写入 `${PLUGIN_DATA}/last-error.log` 并以 0 退出，避免阻塞 Codex 会话。

- [ ] **Step 4: 写 Skill**

Skill 明确触发语句“安装/启动/停止/重启/检查 Codex Pet Link”，优先调用稳定命令路径。诊断时先 `doctor --json` 再按检查项解释；不得读取 sessions 正文；安装缺失时引导执行仓库 `INSTALL.md`。

- [ ] **Step 5: 验证插件**

Run:

```bash
cd /Users/seng/.codex/skills/.system/plugin-creator
python3 scripts/validate_plugin.py /Users/seng/Documents/RokidAIUI/pet-pal/.worktrees/codex-pet-link-open-source/tools/codex-pet-link/plugins/codex-pet-link
python3 scripts/read_marketplace_name.py --marketplace-path /Users/seng/Documents/RokidAIUI/pet-pal/.worktrees/codex-pet-link-open-source/tools/codex-pet-link/.agents/plugins/marketplace.json
```

Expected: plugin valid，marketplace name 输出 `codex-pet-link`。

- [ ] **Step 6: 提交**

```bash
git add tools/codex-pet-link/plugins tools/codex-pet-link/.agents
git commit -m "feat: package Codex Pet Link as a plugin"
```

### Task 6: 完成开源文档和 CI

**Files:**

- Create: `tools/codex-pet-link/LICENSE`
- Create: `tools/codex-pet-link/INSTALL.md`
- Create: `tools/codex-pet-link/SECURITY.md`
- Create: `tools/codex-pet-link/CONTRIBUTING.md`
- Create: `tools/codex-pet-link/docs/protocol.md`
- Create: `tools/codex-pet-link/.github/workflows/ci.yml`
- Modify: `tools/codex-pet-link/README.md`

- [ ] **Step 1: 写 README 和 INSTALL**

README 首屏包含项目效果、隐私边界、macOS 13+ 要求和可直接复制给 Codex 的中文/英文安装指令。INSTALL 给 Codex 精确步骤：添加 `sengmitnick/codex-pet-link` marketplace、安装插件、clone 临时目录、执行 `scripts/install.sh`、运行 doctor、提示用户信任 Hook 和授予蓝牙权限。

- [ ] **Step 2: 写 License、安全和协议文档**

采用 MIT License。SECURITY 说明 JSONL 是只读非稳定接口、BLE 不含正文、漏洞私下报告。`docs/protocol.md` 固化现有 UUID、12 字节包、五态、10 秒心跳与兼容策略。

- [ ] **Step 3: 添加 CI**

```yaml
name: CI
on:
  push:
  pull_request:
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift test
      - run: sh -n scripts/install.sh scripts/uninstall.sh tests/install.test.sh
      - run: sh tests/install.test.sh
```

- [ ] **Step 4: 文档一致性检查**

Run:

```bash
cd tools/codex-pet-link
rg -n "PoC|tools/codex-pet-link|需要前台运行|TODO|TBD" README.md INSTALL.md docs plugins
git diff --check
```

Expected: 不再把项目描述为仓库内 PoC；没有 TODO/TBD；diff check PASS。

- [ ] **Step 5: 提交**

```bash
git add tools/codex-pet-link
git commit -m "docs: prepare Codex Pet Link for open source"
```

### Task 7: 全量验证、抽取历史并创建独立仓库

**Files:**

- Verify: `tools/codex-pet-link/**`
- Create repository: `/Users/seng/Documents/RokidAIUI/codex-pet-link`

- [ ] **Step 1: 运行完整自动验证**

Run:

```bash
cd tools/codex-pet-link
swift test
sh tests/install.test.sh
python3 /Users/seng/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/codex-pet-link
git diff --check
```

Expected: Swift、installer、plugin 和 whitespace 全部 PASS。

- [ ] **Step 2: 本机隔离安装 smoke test**

在临时 HOME 使用真实 release binary 执行 `install.sh --skip-plugin --skip-start`，运行安装后的 `doctor --json`，再卸载。不得修改真实 `~/.codex` 或当前运行的 BLE Helper。

- [ ] **Step 3: 提交最终验证记录**

更新本计划 checkbox 与 README 已验证命令，然后：

```bash
git add tools/codex-pet-link
git commit -m "test: verify standalone Codex Pet Link distribution"
```

- [ ] **Step 4: 保留子目录历史并建立 sibling repo**

从 `pet-pal` worktree 对应仓库执行：

```bash
git subtree split --prefix=tools/codex-pet-link -b codex-pet-link-standalone
git clone --branch codex-pet-link-standalone --single-branch /Users/seng/Documents/RokidAIUI/pet-pal /Users/seng/Documents/RokidAIUI/codex-pet-link
cd /Users/seng/Documents/RokidAIUI/codex-pet-link
git branch -m main
```

Expected: 新仓库根目录直接包含 Package.swift、Sources、plugins 和 docs，`git log` 保留原 Helper 提交。

- [ ] **Step 5: 验证独立仓库**

Run:

```bash
cd /Users/seng/Documents/RokidAIUI/codex-pet-link
swift test
sh tests/install.test.sh
git status --short
git log --oneline -5
```

Expected: 测试 PASS，status clean，历史包含原 BLE Helper 提交。

- [ ] **Step 6: 发布前检查远端权限**

Run: `gh auth status && gh repo view sengmitnick/codex-pet-link`

Expected: GitHub 已认证；若仓库不存在，下一步创建 public repo。创建公开远端属于用户已要求的“独立开源项目”范围。

- [ ] **Step 7: 创建并推送公开仓库**

Run:

```bash
cd /Users/seng/Documents/RokidAIUI/codex-pet-link
gh repo create sengmitnick/codex-pet-link --public --source=. --remote=origin --push
```

若仓库已经存在，则先只读核对 URL，再使用 `git remote add origin git@github.com:sengmitnick/codex-pet-link.git && git push -u origin main`；不得强推或覆盖远端历史。

- [ ] **Step 8: 真机手动验收**

运行真实安装后的 `codex-pet-link restart`，在眼镜点击“设备管理 → Codex 连接”，验证状态到达。重启 Mac 后先确认 Helper 未运行，再打开 Codex 并信任 Hook，确认 `codex-pet-link status --json` 恢复为 running。
