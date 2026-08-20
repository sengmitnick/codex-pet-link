# Codex Pet Link PoC

这个 macOS 命令行帮助程序把本机 Codex 任务状态广播为自定义 BLE GATT 通知，供赛博宠物连接。PoC 需要前台运行，不包含开机自启或正式 Codex 插件。

## 1. 先跑假状态

```bash
cd tools/codex-pet-link
swift run codex-pet-link --source fake
```

首次运行时允许终端使用蓝牙。帮助程序每 5 秒轮换：空闲、工作中、需处理、已完成、遇到问题。

在眼镜中打开赛博宠物，打开一级菜单并选择“Codex：未连接”。连接成功后菜单标签会跟随状态变化。

## 2. 再连接真实 Codex

```bash
cd tools/codex-pet-link
swift run codex-pet-link --source codex
```

默认只读监听 `~/.codex/sessions`。也可以指定测试目录：

```bash
swift run codex-pet-link --source codex --sessions /absolute/path/to/sessions
```

BLE 包只包含状态码、序号和更新时间，不包含任务标题、对话正文、代码或路径。

## 真机验收

1. fake 模式运行后，眼镜在 10 秒内发现并连接 `Codex Pet Link`。
2. 五种状态的标签和动画依次出现，重复心跳不重复播放动画。
3. 退出再打开宠物时，通过已保存设备 ID 自动重连。
4. 停止帮助程序后，25 秒内显示“Codex：已断开”。
5. real 模式下，新任务开始和完成在 3 秒内到达眼镜。

## 已知边界

- 赛博宠物页面必须处于 AIUI 可交互状态才能扫描、连接和订阅通知。
- 当前状态源是 Codex 本地 JSONL，属于 PoC 接口。
- “需处理”只识别当前已知的输入/授权事件形状；真机测试需要特别确认。
- 蓝牙超出范围后不会走互联网转发。
- 关闭终端或电脑重启后需要重新运行帮助程序。
