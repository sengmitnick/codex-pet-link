# Security and privacy

Codex Pet Link 完全在本机运行，不需要网络服务或 API Key。

BLE v2 默认发送：短任务标题、枚举状态、枚举阶段和额外活动数量。标题最多 24 个字符/72 UTF-8 字节，并删除代码块、附件标记和绝对路径。Hooks 的原始 JSON 不落盘；inbox 只保存归一化事件，不含 tool input、命令参数或输出。

`codex-pet-link privacy titles-off` 可关闭标题，仅发送状态和阶段。Bluetooth LE 广播不应被视为加密的秘密通道，请勿把短标题用于高度敏感任务命名。

报告漏洞时请勿在公开 issue 中附带用户 prompt、会话文件或蓝牙抓包中的私人标题。
