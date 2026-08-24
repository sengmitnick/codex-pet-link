# BLE protocol

Service UUID: `7d6b0001-9d7e-4e8a-a7b7-5c2e8f4a1100`.

## v1 status

Characteristic UUID: `7d6b0002-9d7e-4e8a-a7b7-5c2e8f4a1100`.

固定 12 字节：magic `C7`、version `01`、state、progress、UInt32 little-endian sequence、UInt32 little-endian Unix seconds。该格式保持不变。

## v2 activity

Characteristic UUID: `7d6b0003-9d7e-4e8a-a7b7-5c2e8f4a1100`。

每个通知最多 20 字节：

| Offset | Field |
| --- | --- |
| 0 | magic `C8` |
| 1 | version `01` |
| 2-3 | UInt16 little-endian message sequence |
| 4 | zero-based chunk index |
| 5 | chunk count, 1...6 |
| 6 | payload bytes in this frame, 0...13 |
| 7... | payload chunk |

完整 payload 为 `state, phase, additionalCount, titleByteCount, titleUTF8...`。标题最多 72 UTF-8 字节。接收端按 sequence 和 index 重组；缺片、重复 index、混合 sequence、非法 UTF-8 或 2 秒超时消息必须丢弃，不覆盖最后一条完整活动。

连接建立、活动变化和 10 秒心跳都会重发完整快照。v2 characteristic 不存在时，眼镜必须继续使用 v1。
