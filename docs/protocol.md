# BLE protocol

Service UUID: `7d6b0001-9d7e-4e8a-a7b7-5c2e8f4a1100`.

## advertisement identity

Peripheral Local Name 使用持久化、最多 28 UTF-8 字节的 `Codex <short-host> <suffix>`，例如 `Codex seng-MacBook-Air FC13`。`suffix` 是首次生成后保存的四位标识；电脑改名和 Helper 重启不会改变已保存名称。

Central 仍只用固定 Service UUID 做能力过滤，Local Name 仅用于多台 Helper 同场时给用户辨认，不得作为认证、授权或协议版本判断依据。该名称会被附近扫描设备看到，因此会暴露缩短后的电脑标签。

## v1 status

Characteristic UUID: `7d6b0002-9d7e-4e8a-a7b7-5c2e8f4a1100`.

固定 12 字节：magic `C7`、version `01`、state、progress、UInt32 little-endian sequence、UInt32 little-endian Unix seconds。该格式保持不变。

## activity

Characteristic UUID: `7d6b0003-9d7e-4e8a-a7b7-5c2e8f4a1100`。

每个通知最多 20 字节，帧头格式保持一致：

| Offset | Field |
| --- | --- |
| 0 | magic `C8` |
| 1 | version `01` 或 `02` |
| 2-3 | UInt16 little-endian message sequence |
| 4 | zero-based chunk index |
| 5 | chunk count；v1 为 1...6，v2 为 1...255 |
| 6 | payload bytes in this frame, 0...13 |
| 7... | payload chunk |

版本 `01` 是兼容快照，payload 为 `state, phase, additionalCount, titleByteCount, titleUTF8...`。

版本 `02` 是 Codex Pet 式完整活动托盘，payload 为：

`taskCount, [state, phase, titleByteCount, titleUTF8...]...`

标题最多 72 UTF-8 字节；单个快照最多 32 个活动。phase `0...7` 保持原含义，`8`、`9`、`10` 分别表示“已运行命令”“已修改文件”“已搜索”。接收端按 version、sequence 和 index 重组；缺片、重复 index、混合 sequence、非法 UTF-8 或 2 秒超时消息必须丢弃，不覆盖最后一个完整快照。

当前眼镜界面使用四个预计算的固定活动槽：四个以内逐条显示，五个及以上显示前三项和一条数量摘要。底栏额外任务数由独立固定宽度元素显示，不拼进可能被省略的任务标题。不要在 InkView 模板中用 `v-for` 或 `activity.title` 这类循环复合绑定；真机模板引擎可能只留下空容器。Helper 仍发送完整快照，后续接收端可以显示更多活动。

每次通知先发送版本 `02`，再发送版本 `01`。新版眼镜收到同 sequence 的版本 `02` 后忽略兼容帧；旧版眼镜忽略版本 `02`，继续读取版本 `01`。

连接建立、活动变化和 10 秒心跳都会重发完整快照。activity characteristic 不存在时，眼镜必须继续使用固定 12 字节 status characteristic。
