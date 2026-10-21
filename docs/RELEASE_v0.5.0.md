# 万里行商 v0.5.0

桌面版新增两套可切换外观：**午夜港口 · Dark** 与 **电光集市 · Light**。在游戏内“设置”选择外观，切换后界面立即重建；偏好保存在本机，现有存档也会记录选择。旧存档默认使用 Dark。

手机 Expo 版同步加入两套外观，在“更多 → 设置与存档 → 外观”切换，选择随存档保存。手机源代码版本为 1.1.0；此 GitHub Release 的可下载文件仅包含桌面客户端，不包含新的 iOS/Android 安装包。

## 下载

- Windows 10/11 x64：`WanliTrader-v0.5.0-windows-x64.zip`。解压后运行 `WanliTrader.exe`，保留同目录的 `.pck` 文件。
- macOS（Apple Silicon / Intel）：`WanliTrader-v0.5.0-macos-universal.zip`。解压后运行 `WanliTrader.app`。应用未做 Apple 开发者公证，首次打开可能需要在“系统设置 → 隐私与安全性”选择“仍要打开”。
- 用 `WanliTrader-v0.5.0-SHA256SUMS.txt` 校验下载文件。

## 验证

Godot 内容、界面和双主题烟雾测试通过。手机端 63 项逻辑测试通过，Expo iOS 资源包生成成功。桌面发布脚本验证 Windows PCK 的数据与语言加载，并生成两平台 ZIP 与 SHA-256。Windows 可执行文件仍需在真实 Windows 设备上做图形运行验证。
