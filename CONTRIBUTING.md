# Contributing

提交变更前运行：

```bash
swift test
./IntegrationTests/install.test.sh
./IntegrationTests/hooks.test.sh
bash -n scripts/*.sh plugins/codex-pet-link/scripts/*.sh
```

涉及 BLE 时必须保留 v1 golden-byte 测试，并为 v2 分片、乱序、缺片和 UTF-8 边界增加测试。不要把真实 Codex 会话、prompt、文件路径或命令输出加入 fixture。
