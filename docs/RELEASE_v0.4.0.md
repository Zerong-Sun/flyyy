# 万里行商 v0.4.0 桌面版

这是 Windows 与 macOS 的可下载桌面版。游戏包含 500 个机场、商品市场、航班网络、贸易、成就和存档。航班与价格是游戏数据，不用于现实订票。

## 下载和运行

- **Windows 10/11 x64：**下载 `WanliTrader-v0.4.0-windows-x64.zip`，解压整个 `windows` 文件夹，运行 `WanliTrader.exe`。请保留旁边的 `WanliTrader.pck`。首次运行可能出现未知发布者提示。
- **macOS（Apple Silicon / Intel）：**下载 `WanliTrader-v0.4.0-macos-universal.zip`，解压后运行 `WanliTrader.app`。应用已做临时签名，但尚无 Apple 开发者证书公证；首次运行如被拦截，请到“系统设置 → 隐私与安全性”选择“仍要打开”。
- 可使用 `WanliTrader-v0.4.0-SHA256SUMS.txt` 校验下载文件。

## 本版改进

- 桌面端修复退款与货运折扣的收支核算、旧航程在新游戏中继续执行、异常存档校验，以及路线推荐的容量和需求计算。
- 手机端同步改进存档恢复、交易状态执行和退款计算；本次下载资产仅包含桌面客户端。
- 增加 Windows/macOS 导出配置与可复用的打包脚本。运行所需 JSON 数据包含在游戏包中，SQLite 生成数据库不随包分发。

## 验证范围

本版代码此前通过 Python 162 项、手机端 62 项和 Godot 13 套测试。发布时另检查两份 ZIP 的完整性和 SHA-256；macOS 成品包在 Intel Mac 上完成图形模式启动，Windows 的 PCK 完成数据与语言加载启动检查。Windows 可执行文件尚未在真实 Windows 电脑运行。

完整修复清单见 [VALIDATION_FIXES.md](https://github.com/Zerong-Sun/flyyy/blob/v0.4.0/docs/VALIDATION_FIXES.md)。
