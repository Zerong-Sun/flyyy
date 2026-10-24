# 六方面验证与修复清单

日期：2026-10-24。范围：本次游戏开发优化及工作区已有的单趟复盘功能，覆盖 Godot 桌面、Expo 手机与 Python 数据管线。基线为 `f3dcd02`，分支为 `codex/desktop-mobile-validation`。本轮将相互依赖的复盘实现及测试一并审阅，避免提交引用未跟踪文件的不可运行版本。

## 六方面验收

| 方面 | 检查内容 | 判定依据 |
|---|---|---|
| 需求完整性 | 对照 GAMEDEV_REVIEW 的 12 项承诺，以及 Demo/桌面 v0.3/手机 M3 的已有验收；检查设置、保存、起飞时间、焦点、搜索与构建 | 原 12 项均有实现；追加持续事件下的检查点测试。手机 M3 明确不要求移植桌面 500 城与联程；商业版门槛不冒充本次交付 |
| 逻辑正确性 | 交易现金与成本、票价/行李费用、旅程预测、事件报价与缓存、存档重载 | 新购商品售出后复盘可重载；费用分项与付款总额一致；搜索与旧报价优先路径逐项相等 |
| 边界情况 | 连续事件、写盘失败与重试、飞行期间、未来存档、起飞剩余 0–60 分钟、负数/字符串/溢出费用、彩色日志和中断 | 见 V01–V07；无鼠标焦点、时区缺口、新闻换日/换档仍在完整回归中 |
| 代码质量 | 不变数据筛选前置、纯逻辑提取、报告语义、缓存隔离、进程清理、Git 提交完整性 | 共用进程执行器；失败即失败；不复用旧报告；提交不夹带全仓 chmod 或嵌套工作区 |
| 测试覆盖 | Python 数据/资源/工具，手机纯逻辑，桌面 smoke 与 verify 场景；先失败再修复的针对性用例 | 彩色日志/注释配置在修复前 4 失败，票价分项 2 失败，新增商品复盘触发 Godot 断言；修复后定向回归通过 |
| 实际运行结果 | 完整生成数据下运行 Godot，引擎真实渲染，iOS/Android Metro 生产导出，推送后观察 CI | 分别记录下表；Hermes 导出不等于签名 IPA/APK；headless 测量不等于真实 GPU/手机帧率 |

## 修复项

| 编号 | 优先级 | 复现与影响 | 修复 | 回归证据 |
|---|---|---|---|---|
| V01 | P1 | 每 0.5 秒触发变更时，0.8 秒防抖被反复重置，30 秒检查点也被重置，进度可能始终不保存 | 周期到期直接到达写盘时刻，仍保留飞行保护和失败重试 | SmokeGamedevQuality 连续 61 次变更、读取实际存档核对时钟 |
| V02 | P1 | 抵达后售出预测中没有的商品，新增行缺少 unit_cost，保存后的复盘被 sanitize 丢弃 | 完整初始化新商品行，预测数量仍为 0，不制造行情偏差 | SmokeTripRecap 新商品售出后 sanitize 保留记录；原故障日志可见断言失败 |
| V03 | P1 | 手机票据新增 fareCost/baggageCost 未校验，负数、字符串或不匹配总额会破坏复盘记账 | 两项必须有限非负，合计与 totalPaid 相差不超过一美分；旧档两项均缺失时以总额作为票价、行李费为 0 | gameLogic.test.mjs：旧档、合法分项、负数、字符串、空值、缺项、不一致和溢出 |
| V04 | P1 | `--stage` 合并旧汇总，无版本关联；中断可能留下旧的全绿结果 | 每次调用重建报告、原子替换；区分 preflight/running/partial/passed/failed，局部检查不能代表全量 | test_quality_tools：旧记录不复用、全绿/失败区别、中断保留未完成 |
| V05 | P1 | ERROR/SKIP 前带 ANSI 颜色或缩进且引擎退出码为 0 时，门禁可能放行 | 先去除 ANSI 转义，再识别缩进后的错误；空测试集也拒绝通过 | 彩色 ERROR/SKIP、缩进错误、退出码和失败标记测试 |
| V06 | P1 | 存档隔离校验把注释里的 true 当配置；临时项目的 .godot 链接回开发缓存 | 精确匹配唯一启用配置；普通测试复制私有缓存，强制导入使用空缓存 | 注释配置拒绝；修改测试缓存不改变原缓存；fresh import 无旧缓存 |
| V07 | P2 | 超时仅结束父进程，嵌套 Godot/ETL 子进程可能继续运行 | 共用执行器，超时/中断清理进程组及另开会话的后代 | 实际启动另开会话的子进程，超时后不得写出标记文件 |
| V08 | P2 | 原 CI push 只覆盖 main，本次开发分支推送不触发质量门禁 | push 增加 codex/**，保留 PR/manual | YAML 检查与推送后的 GitHub Actions 状态 |
| V09 | P2 | 登机逻辑在 flight_in_progress=true 后再次保存，该调用必然返回 false | 移除无效调用，保留过场前有效检查点及到达后的保存 | 完整 FlightOps/联程回归与飞行期间禁止写盘用例 |
| V10 | P1 | 干净环境下载 BTS 后将解压 CSV 保存成 .zip，管线读取 .csv，导致真实航班层缺失；直接下载失败还可能覆盖旧源文件 | 使用管线约定的 CSV 文件名，流式下载到临时目录并原子替换；直接读取 ZIP 成员避免路径问题；CI 使用 --strict 拒绝静默降级 | test_fetch_sources：ZIP 文件名/嵌套成员、无 CSV、下载中断保护、正常下载、严格模式失败；由远程完整数据重建验证 |
| V11 | P1 | game/data 被忽略后，成就、新闻及 Steam 映射没有可重建输入；本机旧文件掩盖了新克隆无法启动相关系统的问题 | 将现有成就/新闻内容原样保留为 etl/config/runtime 输入；主 ETL 导出两者并派生 Steam 映射；质量与发行入口检查这些必需文件 | test_runtime_data 从空目录导出并验证确定性、覆盖旧输出；第二次 CI 的缺文件错误作为修复依据 |
| V12 | P2 | 滚动测试假定同一中英混排句在各系统上均超过 44px；Linux 字体回退使文字只有一行，导致错误失败 | 用显式三行长文本制造稳定溢出，继续对比 fit_content=true 可滚动、false 裁剪 | verify_detail_scroll；Linux 原始输出 22px/不可滚动，修复后重跑 |

## 执行记录

本机使用隔离 Python 3.12 环境，Godot 4.7.1 与已有 Node/Expo 依赖。完整日志位于 `dist/quality/verification/`，原始故障日志另存于其 `before/` 目录；日志、生成数据和导出资源不提交到 Git。

| 验证 | 结果 | 证据 |
|---|---|---|
| Python 全量 | 184 passed，3 skipped；3 项原因见下方 | python.log |
| 干净下载追加回归 | 5 项通过；在上述全量之后发现并修复，云端再验证完整管线 | fetch-sources.log；before/fetch-sources.log |
| 干净运行时数据导出 | 空目录输出、Steam 映射与确定性覆盖回归；随最终全量重跑 | tests/etl/test_runtime_data.py |
| 手机逻辑 | 77 passed，0 failed | mobile.log |
| Godot 空缓存导入、17 smoke + 10 场景 | 27/27 passed；headless 平均 6.900 ms、p95 8.210 ms | godot.log、godot/ |
| 桌面真实渲染 | SmokeUI、SmokeGamedevQuality 通过；已查看市场/航班截图，输入焦点可见 | render.log、render/、market.png、flights.png |
| iOS/Android 生产资源导出 | 两个平台均成功 | mobile-ios-export.log、mobile-android-export.log |
| Git 格式与工作流结构 | 通过；二进制资源哈希与 HEAD 相同，原文件模式保留 | git diff --cached --check；YAML 解析 |

## 尚不能由本机证明的项目

- 没有 Xcode simctl 或连接手机，刘海/横屏/软键盘、VoiceOver/TalkBack、实体震动及中端手机帧率仍需设备验收。
- 渲染 smoke 使用 OpenGL compatibility；正式 Forward+ 渲染器的 1080p 60 FPS 仍需目标硬件测量。
- Python 的原始美术 contact sheet 与旧 HTML 端 curated_cities.json 为既有可选素材，缺失引起的跳过会单独披露，不作为 Expo 核心测试通过的证据。
- 商业版数据授权、Steam 云存档、商店签名/上架属于后续发行门槛，不包含在本次代码修复与 commit/push 中。

首次完整三阶段同次执行通过，之后云端干净环境补充发现 V10–V12，已修复并重新验收。旧云端失败证据见 [运行 40107396992](https://github.com/Zerong-Sun/flyyy/actions/runs/40107396992)；远程最终结果以 [Game quality 运行记录](https://github.com/Zerong-Sun/flyyy/actions/workflows/quality.yml) 为准。本文的本机记录不预先声明远程通过。
