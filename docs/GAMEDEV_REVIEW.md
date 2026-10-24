# 万里行商游戏开发审阅与优化

本轮以当前工作区的 Godot 4.7.1 桌面端、Expo SDK 54 手机端和 Python 数据管线为基准。保留已有改动、双端不同的经济平衡和存档格式。重点是进度可靠性、玩家设置、时间正确性、可操作性、实测性能和持续验收。

## 审阅依据

参考 [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/184b72be02884f782a0058f2eeae2ce4277453e4) 的固定提交 `184b72be02884f782a0058f2eeae2ce4277453e4`，读取 router、save-systems、performance-optimization、godot-gdscript-headless-testing、godot-ui-control、game-ui-ux。以下问题是对本项目代码的审阅结论；技能仓库提供审阅方法，不构成项目测试结果。未批量安装技能或升级引擎。

- [存档技能](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/save-systems/SKILL.md)：对应 01、02、05，审查检查点、失败处理、恢复和版本兼容。
- [界面技能](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/game-ui-ux/SKILL.md)：对应 07–09，检查玩家偏好、安全区和焦点；Godot 控件技能用于具体实现。
- [性能技能](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/184b72be02884f782a0058f2eeae2ce4277453e4/skills/disciplines/performance-optimization/SKILL.md)：对应 10、11，先测量，再修改热点并核对结果。
- [无界面测试技能](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/184b72be02884f782a0058f2eeae2ce4277453e4/skills/godot/godot-gdscript-headless-testing/SKILL.md)：对应 12，检查资源导入、退出码、日志错误与超时。

## 执行清单

| 编号 | 优先级 | 现状与影响 | 实施方案 | 验收条件 |
|---|---|---|---|---|
| 01 | P1 | 桌面只在部分状态事件后保存；等待时钟、需求变化可能没有检查点；保存失败会清除 dirty | 30 秒检查点、失败保留 dirty 并延迟重试、飞行中保持禁止保存 | 等待进度可恢复；写失败恢复后成功；飞行中不写 |
| 02 | P1 | 字号、语言、减少动态等修改未全部触发存档；手动保存会强制取消暂停 | 增加 settings_changed，统一触发保存；恢复保存前暂停状态 | 设置可以保存和重载；暂停中保存后仍暂停 |
| 03 | P1 | 读档仅恢复 SFX，总线 UI 和 Transition 仍为默认音量 | 让 SFX 总线设置统一更新整个音效组 | 三个总线读档后音量相同，包括静音量 |
| 04 | P2 | 同一 BGM 在重复开面板时从头播放 | 当前音轨相同且在播放时直接返回 | 同曲不重启；停止后仍可重播 |
| 05 | P1 | 手机端有效主存档会跳过未来版本备份检查，读入可玩但后续无法保存 | 读档先检查两份版本，再选择有效副本 | 有效主档与未来备份组合仍受保护 |
| 06 | P1 | 手机时钟每次推进 6 分钟，即使距离起飞仅剩 1–5 分钟 | 提取纯时间推进函数，在起飞点截断 | 任意剩余分钟数都不越过起飞时间；无机票正常推进 |
| 07 | P2 | 音效失败时的触觉回退绕过关闭震动选项 | 回退使用最新震动设置 | 关闭震动后不发出回退震动 |
| 08 | P2 | 手机 Modal 独立于主页面安全区，固定 fade，无键盘避让 | 弹窗安全区、键盘避让、减少动态效果、模态可访问语义 | Metro 打包成功；设备验证列入真机验收 |
| 09 | P2 | 桌面新游戏及工作面板没有统一初始键盘焦点 | 面板构建后聚焦首个可见且可用控件 | 无鼠标可进入面板并使用 Tab；已有文本输入不被抢焦点 |
| 10 | P1 | 航班搜索对已起飞及不符合筛选的记录也逐条深拷贝、计算新闻 | 先执行不依赖报价的筛选；相同城市、日期、存档的事件使用有界缓存 | 与旧路径逐项结果一致；记录同机前后耗时；换日/换存档正确 |
| 11 | P2 | 性能测试每帧读低频更新的 FPS；稀疏时区日期缺口会错误取最后日期偏移 | 直接测量微秒帧间隔并报告 p50/p95/p99；时区取最近较早日期 | 有效采样和分位数；时区日期前、中、后边界回归 |
| 12 | P1 | 现有 Godot runner 绑定 macOS，未覆盖 verify 场景，缺少 PR 验收工作流 | 跨平台引擎发现、干净导入、隔离存档、场景覆盖、统一质量入口与 CI | 日志错误/超时返回失败；本地全套回归；CI 配置与数据依赖说明 |

## 保留的基础能力

- 桌面已具备 JSON 类型校验、临时文件替换、备份恢复和未来存档保护。
- 双端已有交易记账、联程/购票约束、旅程回顾和确定性新闻事件；保留现有回归。
- 桌面已有按城市/机场懒加载、航线数量限制及 60 FPS 上限；手机已有主要数据 memo 和前后台时钟门控。
- 本轮不整体重写 MainHUD/useGame，不改变商品、市场平衡和美术风格。通过提取时间逻辑和测试入口先建立可维护边界。

## 改动位置与具体行为

1. **检查点和重试**：`game/scripts/autoload/SaveSystem.gd` 每 30 秒保存等待进度，现金、库存、到达和设置变更仍采用 0.8 秒合并窗口。写入失败保留待保存状态，5 秒后再次尝试；成功后才清理标记。飞行中保持暂停写盘，未来版本保护不被重试绕过。
2. **设置与暂停**：`EventBus.gd` 增加 `settings_changed`，`MainHUD.gd` 的字号、语言、减少动态、色盲、字幕等入口发出事件。音频设置也发出事件。手动保存先记录暂停状态并在结束后恢复；成功/失败/重试提示补齐中英文。
3. **音量恢复**：`AudioService.gd` 的音效设置同步作用于 SFX、UI、Transition 三条总线，因此 `AppState.from_dict()` 恢复一次音效音量即可覆盖全部音效。
4. **音乐连续性**：同一已在播放的 AudioStream 不再重启；停止之后仍能再次播放，换曲行为保持正常。
5. **存档兼容**：`ios/expo/src/saveStorage.js` 在恢复前读取主档和备份；任一为未来版本都进入保护状态。读取过程不删除或覆盖原文件。
6. **起飞边界**：新增 `ios/expo/src/worldClock.js`，从 `useGame.js` 提取纯函数。距离起飞不足一个 tick 时只推进剩余分钟；到达计算继续由飞行逻辑负责。测试遍历 0–60 分钟各个相位，并覆盖小数、无机票、介绍和过场状态。
7. **触觉偏好**：`useGame.js` 的音效失败回退在真正执行时读取最新 `optHaptics`，避免异步音效请求完成后绕过已关闭的震动设置。
8. **手机弹窗**：`components/ui.js` 使用安全区 inset、KeyboardAvoidingView、模态可访问性与关闭手势；`App.js` 将减少动态设置传入共享上下文。减少动态开启时弹窗不再 fade，居中弹窗也限制最大高度。
9. **键盘焦点**：新增 `game/scripts/ui/FocusNavigation.gd`，面板创建结束后选取首个可见、启用且可聚焦的控件；已有输入焦点留在原位。`MainHUD.gd` 在新游戏和工作面板接入该行为。
10. **搜索热点**：`FlightSearch.gd` 先执行时间、目的地、未访问、时长、舱位和文本筛选，再计算新闻报价；票价限制仍使用调整后的报价。`NewsEvents.gd` 缓存当前日期/存档的城市事件，返回深拷贝，换上下文清空。
11. **可解释测量与时区**：`SmokePerf.gd` 直接采样 180 帧间隔并报告分位数，避免低频 FPS 数据造成假象；`GameClock.gd` 对稀疏时区表使用最近较早的已知偏移，覆盖表前、区间中、变更当天和表后日期。
12. **验收门禁**：`tools/test_godot.py` 发现跨平台 Godot，处理缺少缓存时的导入，按测试隔离存档，支持 verify 场景并把日志错误、异常跳过和超时视为失败。`tools/check_quality.py` 检查环境依赖，执行三端测试并输出结构化汇总，支持只重跑受影响的阶段。`.github/workflows/quality.yml` 增加 PR/push/manual 触发、只读权限、超时、源数据摘要和失败日志上传。同步修正两个过时测试契约：退休配色常量、20% 免费推荐比例；保留主题可读性及验证新的推荐开关/单商品上限。挑战/图鉴/重开测试改用固定种子与可用航班，避免直接选中新闻取消航班产生随机失败；取消与延误规则继续由联程、新闻和完整贸易闭环测试覆盖。

## 可复现验收

在装有 `etl/requirements.txt` 的 Python 3.11+ 环境下执行；Godot 使用 4.7.1，Node.js 使用支持 `node --test` 的版本。

```bash
python tools/check_quality.py
python tools/check_quality.py --stage godot  # 只验桌面，汇总明确标记 partial，不复用旧通过记录
python tools/test_godot.py SmokeGamedevQuality.gd SmokeSearchPerf.gd
python tools/test_godot.py SmokeUI.gd SmokeGamedevQuality.gd --render
cd ios/expo
npm ci
npm test
CI=1 EXPO_OFFLINE=1 npx expo export --platform ios --output-dir dist/ios
CI=1 EXPO_OFFLINE=1 npx expo export --platform android --output-dir dist/android
```

统一验收记录在 `dist/quality/summary.json` 及相邻日志中。测试写入临时 user 目录，不接触玩家的正式存档。本机原有两个 Python venv 链接指向已不存在的 Homebrew Python，因此本轮使用独立临时 Python 3.12 环境完成验收，未改写原环境。

首次克隆需要完整世界数据：先运行 `etl/scripts/01_fetch_sources.py`，再运行 `etl/scripts/run_pipeline.py --full` 和 `tools/export_expo_data.py`。CI 缓存公开数据并记录 SHA-256；初次下载的上游内容可能变化，更新数据版本时需同步审阅生成结果。缺少生成数据时统一入口会明确失败，不以跳过冒充全量验收。

## 性能证据

PVG 月中查询、固定存档、预加载后的三次中位数，采用最终验收复跑数据：全部未来航班 **2806→341 ms**，LHR **1900→43 ms**，≤$500 **2064→295 ms**，约快 7–45 倍。三组结果数量分别为 2496、31、1666，完整结果摘要均与修改前一致。首次修改后测量与最终复跑值均保留在 [性能测量](performance.md)。这些是本机 headless 调试进程的搜索耗时，不是正式包的 GPU FPS。

## 验证记录与发布边界

12 项代码和工具改动已完成。下表为首次优化验收记录；后续六方面复核、追加修复及新的全量结果见 [验证修复清单](VERIFICATION_FIXLIST.md)。首次汇总中的桌面结果来自夹具修复后的重跑；新的报告格式不再合并不同调用的结果。

| 检查 | 最终结果 | 证据 |
|---|---|---|
| Python 数据、资产、导出与测试工具 | 174 passed，3 skipped | `dist/quality/python.log` |
| 手机逻辑 | 74 passed，0 failed | `dist/quality/mobile.log` |
| Godot smoke 与验证场景 | 27/27 passed（17 smoke + 10 场景） | `dist/quality/godot.log` 与 `godot/` |
| 桌面真实渲染 | SmokeUI、SmokeGamedevQuality 通过 | `dist/quality/render.log`、`market-focus.png`、`flights-focus.png` |
| 手机生产资源导出 | iOS、Android 均通过 | `dist/quality/mobile-ios-export.log`、`mobile-android-export.log` |
| 工作流与改动格式 | YAML 结构、Python 编译、Godot 下载地址、`git diff --check` 通过 | 本地检查；Godot 下载地址 HTTP 200 |

3 项 Python 跳过原因：两项依赖未提供的原始美术 contact sheet，一项依赖旧 iOS HTML 导出的 `curated_cities.json`；没有跳过 Expo 核心逻辑。第一次全量执行发现的挑战夹具失败日志保留为 `godot-first-attempt.log`，修复后的完整桌面日志为 `godot.log`。

- 已执行桌面真实渲染 smoke，检查市场/航班面板及键盘焦点；渲染路径为 OpenGL compatibility，不代替 Forward+ 的正式包 GPU 验收。
- iOS 与 Android Metro 资源导出通过，属于 JavaScript/Hermes 与资产构建验证，不等同于生成签名 IPA/APK。
- 本机没有 `simctl`，手机刘海/横屏/软键盘/VoiceOver/TalkBack 与实体震动仍需设备验收。
- 新 CI 工作流的云端执行状态见后续验证清单；本地结果不等同于云端通过。
- 本轮未创建正式发布、修改签名证书、上传商店或替换现有发布包。
