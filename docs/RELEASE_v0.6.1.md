# 万里行商 v0.6.1 · 城市故事

- **500 城文案补齐**：每座城市都有独立中文正文，覆盖地点背景、地理、经济、饮食、文化和旅行提示；清除原有的通用占位描述。
- **天津内容与名称**：天津显示中文名，加入海河、港口经济、津味早点和杨柳青年画等内容。
- **100 城实景照片**：按航线连接度选择重点城市，并纳入天津。城市页展示照片作者、许可及原始图片链接；逐张信息见仓库中的 `game/assets/cities/photo_credits.json`。
- **市场操作说明**：商品买入按钮下增加“行李扩容 / 货运额度添加”分区与提示，避免把 +10 kg 等额度操作误读为商品合约。

此版本延续 v0.6.0 的限时商机、途中事件与双外观。城市文案覆盖审计和重建方式见 `docs/reports/2026-10-25-city-content-gaps.md`。

## 下载

- Windows 10/11 x64：`WanliTrader-v0.6.1-windows-x64.zip`。解压后运行 `WanliTrader.exe`，保留同目录的 `.pck` 文件。
- macOS（Apple Silicon / Intel）：`WanliTrader-v0.6.1-macos-universal.zip`。解压后运行 `WanliTrader.app`。应用未做 Apple 开发者公证，首次打开可能需要在“系统设置 → 隐私与安全性”选择“仍要打开”。
- 使用 `WanliTrader-v0.6.1-SHA256SUMS.txt` 校验下载文件。

本次下载附件仅包含桌面客户端；手机端仍通过 Expo Go 预览，没有新的 IPA / APK。

## 验证

完整 ETL 生成 500 城、2500 件商品，文案缺口为 0；城市内容定向测试 16 项通过，Godot `SmokeUI.gd` 和 `SmokeContent.gd` 通过。桌面发布包检查包括数据加载、Windows PCK 启动、ZIP 完整性及 SHA-256 校验。Windows 图形运行尚未在真实 Windows 设备上验证。
