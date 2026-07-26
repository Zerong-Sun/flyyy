# 《环球航商》美术 · 音乐 · 文本需求规格

| 字段 | 内容 |
|------|------|
| 文档编号 | CAS-01 |
| 版本 | v1.4 |
| 产品 | 《环球航商》/ Airborne Trader |
| 关联 | [PRD_01.md](../PRD_01.md) §10 / §13–14 / §18 / §24 / §26.1 / §27 |
| 引擎 | Godot 4.x |
| 语言 | 简体中文（Demo）；英文键名与资源 ID 使用 ASCII |
| 状态 | 可玩 Demo（§27）+ 基础 UI Theme + 美术代码占位符；正式地球/过场/图标仍属美术包 D1 |

本文档供美术、音频、文案与程序导入共同遵守。与 PRD 冲突时以 PRD 玩法/法律约束为准，表现层以本文档为准。

---

## 0. 总原则

### 0.1 产品气质（一句话）

**「可旋转的真实世界航线图鉴」**——清晰、可信、略带旅途温度；不是科幻 HUD，不是战棋，不是电商后台。

### 0.2 核心体验锚点

1. **地球优先**：首屏品牌信号是球形地球与机场网络，不是大标题堆叠。  
2. **信息可读**：时间、资金、行李、航班倒计时永远可扫视。  
3. **克制装饰**：不用漂浮徽章、贴纸、多色霓虹堆叠在地球上。  
4. **合法与安全**：无酒烟药武危险品；无未授权航司 Logo / 品牌包装图；不暗示可现实购票。

### 0.3 分期范围

| 阶段 | 美术 | 音乐 | 文本 |
|------|------|------|------|
| **Demo（当前）** | 地球、机场点、航线、基础 UI、5s 过场、图标系统 | 少量 BGM + UI/过场 SFX | 20 城简介、≥5 商品/城、全 UI 中文、数据来源页 |
| **v0.2** | 城市插画/照片位、商品图鉴图标、成就图标 | 区域主题变奏 BGM | 500+ 城扩展文案 |
| **v1.0** | 完整视觉包装、启动动画、多语言字形 | 完整自适应配乐 | 多语言、精修百科 |

Demo **不要求**城市摄影图、航司 Logo、完整飞机驾驶舱模拟（PRD §24.4）。

### 0.4 禁止风格（明确不做）

- 默认「紫粉渐变霓虹 / 赛博 HUD 全息」套路。  
- 报纸排版风（细线密栏、零圆角公文感）作为主 UI。  
- 卡通夸张吉祥物抢戏地球。  
- 写实血腥、政治敏感符号、宗教圣物戏谑化。  
- 未授权商标、球队/奢侈品/香烟酒类包装复刻。

### 0.5 仓库现状盘点（2026-07-27；美术占位符收口）

对照本章资产 ID，核对 `game/assets/` 与运行时占位实现。  
**可玩 Demo（PRD §27）** 已落地基础 UI Theme、字体，以及地球/机场/网格/过场/图标的**代码生成占位符**。正式贴图 / 插画 / SVG 图标仍归美术包 D1。

| CAS ID / 类别 | 状态 | 现状说明 |
|---------------|------|----------|
| `EARTH_ALBEDO` | **占位（代码生成）** | 无正式 PNG/WebP；[`GlobeController._build_earth`](../game/scripts/render/GlobeController.gd) 运行时生成 1024×512 大洲椭圆近似贴图（亚欧/北美/南美/非洲/澳洲可辨） |
| `EARTH_NORMAL` / `EARTH_SPEC` / `EARTH_NIGHT` | **缺（可选）** | Demo 可省略 |
| `GRID_OVERLAY` | **占位（代码生成）** | [`_build_grid_overlay`](../game/scripts/render/GlobeController.gd)：每 15° 经纬线，`ImmediateMesh`，远淡近显 |
| `MESH_AIRPORT_PIN` | **占位（代码生成）** | 低模 Pin（圆柱+球头 ArrayMesh）；四色由程序驱动；无独立 glTF |
| `FX_ROUTE_LINE` | **占位** | `ImmediateMesh` 大圆弧 + Unshaded 材质 |
| `ICON_PLANE_TINY` | **占位（代码生成）** | 三角飞机标记；行程航线时显示并沿弧推进 |
| 过场三段视觉 `anim_flight_*` | **占位（几何动效）** | SFX 三段已齐；[`MainHUD._play_transition_fx`](../game/scripts/ui/MainHUD.gd) 起飞灯条 / 巡航弧线 / 降落条+城名；正式插画仍属 D1 |
| UI Theme（色板 + StyleBox） | **已齐（基础）** | [`ThemeFactory.gd`](../game/themes/ThemeFactory.gd) + [`DemoColors.gd`](../game/themes/DemoColors.gd)；挂载于 MainHUD |
| 图标图集 | **占位（代码生成）** | [`IconFactory.gd`](../game/themes/IconFactory.gd)：§1.2.E 全套 + 笔记/情报扩展；光栅 ImageTexture 挂按钮 |
| 字体（Noto Sans SC / JetBrains Mono） | **已齐（基础）** | [`game/assets/fonts/`](../game/assets/fonts/) OFL；见 LICENSE.txt |
| `bgm_globe_day` + §2.3 P0 SFX（17 项） | **已齐** | [`AUDIO_MANIFEST.csv`](../game/assets/audio/AUDIO_MANIFEST.csv) 与文件一一对应 |
| `bgm_market` / `bgm_menu` / `bgm_night` | **缺（P1）** | 规格预留 |
| 文本包：UI CSV + 20 城 + 100 商品 + 来源页 | **已齐** | 含字体署名 |
| 城市插画 / 商品图鉴图标 | **缺（P1）** | |

**运行时数据：** Godot 只读 [`game/data/world.json`](../game/data/world.json)（及 `flights.json`）；SQLite 为 ETL 校验产物。

**与美术包 D1 关系：** Theme/字体/代码占位符已满足可玩 Demo；正式 `EARTH_ALBEDO` PNG、过场插画三帧、SVG 图标图集仍属 D1 交付。

**美术包 D1 待交付清单（需求写入本文档，Demo 用占位符）：**

1. `earth_albedo_day_2k.png`（等距柱状 ≥2048×1024）  
2. `anim_flight_takeoff` / `cruise` / `land` 序列帧或 Motion 片  
3. `icon_*.svg` × §1.2.E 全套（24/32）+ `icon_plane_tiny`  
4. 可选：`MESH_AIRPORT_PIN.glb`、品牌字标 `logo_*`
---

## 1. 美术需求

### 1.1 视觉风格定义

| 维度 | 要求 |
|------|------|
| 关键词 | 航图 · 日光 · 港口城市 · 清晰信息 · 轻度旅行杂志 |
| 空间感 | 以 3D 地球为舞台；UI 为半透明信息层，不遮死地球主体 |
| 线条 | 航线干净、略发光但不刺眼；UI 边框细、圆角克制（4–8px） |
| 材质 | 地球：哑光陆地 + 略深海洋；金属仅用于少量图标（航徽几何形，非真航司） |
| 光影 | 桌面 Forward+；主光模拟日光；可有柔和昼夜分界（可选） |
| 动效 | 少而准：地球惯性旋转、按钮按下、倒计时闪烁、过场三段切换 |

#### 1.1.1 色彩系统（CSS / Godot Theme 变量）

落地时在 `game/themes/` 或全局 Theme 中定义同名常量：

| Token | Hex | 用途 |
|-------|-----|------|
| `--bg-deep` | `#0B1C2C` | 面板底、遮罩 |
| `--bg-panel` | `#122A3D` @ 88% opacity | 主面板 |
| `--ocean` | `#1A4A6E` | 地球海洋主色参考 |
| `--land` | `#3D6B4F` | 陆地主色参考 |
| `--ice` | `#D9E6F0` | 极地/高亮描边 |
| `--text-primary` | `#F2F6FA` | 主文字 |
| `--text-secondary` | `#A8B8C8` | 次要文字 |
| `--accent-amber` | `#E89A3C` | **加速至起飞**、关键 CTA |
| `--accent-teal` | `#3CB8A4` | 已访问、正向利润 |
| `--warn-red` | `#E05555` | 登机倒计时、错误 |
| `--economy` | `#7EB6D9` | 经济舱标签 |
| `--business` | `#C9A45C` | 公务舱标签 |
| `--border` | `#2A455A` | 分隔线 |

对比度：正文与面板底对比度 ≥ 4.5:1（WCAG AA 目标）。

#### 1.1.2 字体（UI 文本呈现）

| 用途 | 推荐方向 | 备注 |
|------|----------|------|
| UI 正文 | 开源无衬线，支持简体中文（如「思源黑体 / Noto Sans SC」） | 不得默认仅 Inter/Arial |
| 数字/时刻/IATA | 等宽或半等宽（如 IBM Plex Mono / JetBrains Mono 子集） | 航班号、金额对齐 |
| 品牌词「环球航商」 | 略宽字距的无衬线或温和人文无衬线 | 启动/主菜单用，游戏内 HUD 不抢地球 |

字号阶梯（1080p 基准）：

- 品牌大标题：36–48  
- 面板标题：20–22  
- 正文：15–16  
- 辅助/脚注：12–13  
- 角标 disclaimer：11–12，不透明约 70%

### 1.2 场景与关键视觉资产清单

#### A. 地球与地图（P0 · Demo）

| ID | 资产 | 规格 | 说明 |
|----|------|------|------|
| `EARTH_ALBEDO` | 地球漫反射贴图 | 等距柱状 2048×1024 或 4096×2048，PNG/WebP | 海岸清晰；国界可选细线；**无政治争议标注**；公有领域或自绘 |
| `EARTH_NORMAL` | 可选法线 | 同分辨率或半分辨率 | Demo 可省略 |
| `EARTH_SPEC` | 可选高光/海洋 mask | 同分辨率 | 增强海陆分离 |
| `EARTH_NIGHT` | 可选夜景灯光 | 同分辨率 | 后期 |
| `GRID_OVERLAY` | 经纬网格 | 矢量或 shader | 远景淡、近景显 |

**风格要求：** 偏自然真彩色或「地图出版」轻度风格化均可，但必须一眼可读大洲形状；禁止纯抽象噪点充当陆地。

#### B. 机场与航线（P0）

| ID | 资产 | 规格 | 说明 |
|----|------|------|------|
| `MESH_AIRPORT_PIN` | 机场点网格 | 低模 ≤200 tris；白模 + 材质色变 | 当前/选中/已访问/默认四色由程序驱动 |
| `FX_ROUTE_LINE` | 大圆弧材质 | Unshaded + 顶点色或细带状 mesh | 默认青白；当前行程琥珀 |
| `ICON_PLANE_TINY` | 可选飞机剪影 | 64×64 SVG/PNG | 仅当前航班；Demo 可用简单三角形代替 |

层级显示（对齐 PRD §10.3）：远景少标、近景多标；同时屏幕标签 ≤200（Demo 仅 20 点则全开亦可）。

#### C. 飞行过场（P0 · 5 秒）

三段叙事，**不**做真实大圆飞行模拟：

| 阶段 | 时长建议 | 画面内容 | 叠加信息 |
|------|----------|----------|----------|
| 起飞 | 0–1.6s | 跑道灯光/机头仰角剪影/云层掠过 | 航班号、起降 IATA、舱位 |
| 巡航 | 1.6–3.4s | 机翼侧影或地图弧线推进 | 距离、飞行时间 |
| 降落 | 3.4–5.0s | 跑道迎面/城市远景剪影 | 目的地城市名 |

资产形式任选其一（需统一风格）：

1. **序列帧/插画三帧** + 淡入淡出；或  
2. **简短 3D 镜头**（低模飞机 + 天空盒）；或  
3. **2D 动态图形**（Motion 风格信息片）。

导出：`anim_flight_takeoff` / `cruise` / `land`，每段可循环或单次；总时长锁 5.0s ±0.1s。

#### D. UI 壳与控件（P0）

| 组件 | 要求 |
|------|------|
| 主 HUD 顶栏 | 半透明深色条；左时间、右资金/行李/机场 |
| 左搜索栏 | 输入框 + 列表；选中高亮 `--accent-teal` |
| 右机场卡 | 信息密度中等；IATA 大号等宽 |
| 底栏 Tab | 城市 / 市场 / 航班 / 库存 / 旅行记录；当前 Tab 琥珀下划线 |
| 「加速至起飞」 | **唯一强 CTA**：`--accent-amber` 填充；可微脉冲，勿花哨 |
| 登机遮罩 | 全屏 75% 黑；中央卡片；不可点穿 |
| 面板 | 圆角 6–8px；1px `--border`；避免厚重卡片阴影堆叠 |

提供 9-slice / StyleBox：`panel_default`, `button_primary`, `button_ghost`, `button_danger`, `input_field`, `list_row`, `list_row_selected`。

#### E. 图标系统（P0）

统一 **线面结合 24×24 / 32×32**，笔画 1.5–2px，圆角端点。

| 图标 ID | 语义 |
|---------|------|
| `ic_city` | 城市 |
| `ic_market` | 市场/商品 |
| `ic_flight` | 航班 |
| `ic_inventory` | 库存/行李 |
| `ic_log` | 旅行记录 |
| `ic_attr` | 数据来源 |
| `ic_search` | 搜索 |
| `ic_random` | 随机机场 |
| `ic_economy` | 经济舱 |
| `ic_business` | 公务舱 |
| `ic_baggage` | 行李扩展 |
| `ic_cargo` | 货运 |
| `ic_fast_forward` | 加速 |
| `ic_save` / `ic_load` | 存读档 |
| `ic_money` | 资金 |
| `ic_weight` | 重量 |
| `ic_clock` | 时间 |
| `ic_warning` | 警告 |

格式：SVG 源文件 + 导出 PNG @1x/@2x；Godot 优先 SVG 或 Texture2D。

#### F. 商品与城市视觉（P1 · Demo 可占位 / v0.2 必做）

| 类型 | Demo | v0.2+ |
|------|------|-------|
| 商品图标 | 可用类别色块 + 首字；或 64×64 通用类别图标 | 每商品独特插画，**非品牌包装照** |
| 城市头图 | **不做**（PRD Demo） | 1280×720 插画或授权摄影，无水印 |

商品插画风格：静物、柔和投影、白/浅灰底；禁止酒瓶烟盒药瓶枪械。

#### G. 品牌与启动（P1）

| 资产 | 规格 |
|------|------|
| `logo_wordmark_zh` | 「环球航商」横式 SVG |
| `logo_mark` | 几何地球+航线抽象标，512×512 |
| `app_icon` | 512 / 256 / 128 PNG |
| `splash` | 1920×1080，地球构图 + 品牌 + disclaimer 一行 |

### 1.3 动效规范

| 场景 | 时长 | 缓动 | 备注 |
|------|------|------|------|
| 面板开关 | 180–220ms | ease-out | 透明度 + 轻微上移 8px |
| Tab 切换 | 120ms | linear | 内容淡入即可 |
| 倒计时闪烁（登机） | 周期 0.5s | — | 仅颜色/透明度，不缩放狂闪 |
| 加速确认弹窗 | 150ms | ease-out | |
| 地球双击聚焦 | 400–600ms | ease-in-out | 相机插值 |
| 过场三段切换 | 硬切或 200ms 叠化 | — | 总时长固定 5s |

无障碍：提供「减少动态」时关闭脉冲与闪烁（保留颜色状态）。

### 1.4 分辨率与安全区

- 设计基准：**1920×1080**；布局自适应到 1280×720。  
- UI 安全边距：距屏幕边缘 ≥16px。  
- 底栏高度约 48–56px；顶栏 48–52px。  
- 3D 视口占满；UI 为 CanvasLayer，不拉伸变形地球。

### 1.5 美术文件格式与导出

| 类型 | 源格式 | 引擎格式 | 色彩 |
|------|--------|----------|------|
| 光栅贴图 | PSD/Krita + PNG | PNG 或 WebP；Godot Import | sRGB |
| 矢量图标 | SVG（笔画可扩展） | SVG/PNG | — |
| 3D | Blender `.blend` + 导出 `.glb` | glTF 2.0 | — |
| UI 切图 | Figma/Penpot | 9-slice PNG | — |

最大贴图边长建议：地球 4096；UI 图集单边 ≤2048；图标 256。

### 1.6 美术命名规则

```text
{domain}_{object}_{variant}_{size}.{ext}
```

| 段 | 规则 | 示例 |
|----|------|------|
| domain | `ui` `earth` `fx` `icon` `product` `city` `brand` `anim` | `ui_` |
| object | 小写 snake | `button_primary` |
| variant | 可选：`default` `hover` `disabled` `amber` | |
| size | 可选：`24` `32` `2k` | |

**合法示例：**

- `earth_albedo_day_2k.png`  
- `icon_flight_32.svg`  
- `ui_panel_default.tres`（Godot）  
- `anim_flight_cruise_v1.png`（序列帧图集）  
- `product_tea_generic_64.png`  

**禁止：** 空格、中文文件名、`最终终版2`、依赖桌面路径的绝对引用。

目录建议：

```text
game/assets/
  brand/
  earth/
  icons/
  ui/
  anim/flight_transition/
  products/          # v0.2
  cities/            # v0.2
  fonts/
```

### 1.7 美术验收清单

- [ ] 地球大洲可辨，无错误镜像（经度方向与程序 lat/lon 约定一致：验证 PVG 在亚洲东侧）  
- [ ] 四态机场色可区分且不依赖色盲单一通道（辅以形状/标签）  
- [ ] CTA「加速至起飞」为全 UI 最醒目暖色按钮  
- [ ] 无航司 Logo、无违禁品图  
- [ ] 1080p 下 UI 文字清晰，disclaimer 可读但不抢主信息  
- [ ] 过场严格 ≤5.1s，三段语义可辨  

---

## 2. 音乐与音效需求

### 2.1 声音气质

**「航站楼日光 + 远方城市氛围」**：安静、开阔、不压迫；节奏稳定，避免重金属/恐怖/电子舞曲盖过信息阅读。

情绪板：

- 探索地球：缓慢、空气感、轻微脉冲  
- 市场买卖：短促、干净、收银/布料/陶瓷轻触感（非赌场）  
- 起飞过场：低频推进 + 柔和风噪，5 秒内起承转合  
- 警告/登机：清晰但不刺耳的提示音  

**禁止：** 赌场式连击音效、恐怖惊吓、尖锐警笛、未授权流行歌改编、重金属鼓点盖过 UI 可读性。

### 2.2 BGM 清单

| ID | 场景 | 时长 | BPM / 调性 | 纹理建议 | 循环 | Duck | 响度 | Demo |
|----|------|------|------------|----------|------|------|------|------|
| `bgm_globe_day` | 主界面/地球漫游 | 2:00–3:00 | ~72 BPM，D 大调或无明确调中心 pad | 柔和 pad + 稀疏脉冲；少鼓点 | Intro 可裁；`loop_start_ms`≈8000 | 过场时 -6dB | -16 ~ -14 LUFS | **P0 必交** |
| `bgm_market` | 市场/城市阅读 | 1:30–2:30 | 同 globe 或 +4～8 BPM | 弱变奏；减少 80Hz 以下 | 无缝 | 买卖 SFX 不 duck | -16 LUFS | P1 |
| `bgm_menu` | 新游戏/设置 | 1:00–2:00 | 更慢 | 更安静、更少脉冲 | 无缝 | 无 | -18 LUFS | P1 |
| `bgm_night` | 当地夜时变奏 | 同 day | 同 day | 低通更暗、高音减弱 | 同 day | 同 day | -16 LUFS | 可选 |

Demo 最少交付：`bgm_globe_day` + 静音开关；其余规范预留，不阻塞音频包 D1。

技术：

- 格式：**Ogg Vorbis**（`.ogg`）主交付；备份 WAV 24bit 工程源（可不入库）  
- 采样率：48 kHz；声道：立体声  
- 循环：文件内嵌 loop 点 **或** `AUDIO_MANIFEST.csv` 的 `loop_start_ms` / `loop_end_ms`  

### 2.3 SFX 清单（Demo P0）

| ID | 触发 | 时长 | 总线 | 峰值建议 | 叠音 | 备注 |
|----|------|------|------|----------|------|------|
| `sfx_ui_click` | 按钮 | ≤80ms | UI | -12 dBFS | ≤2 | 轻点击；可 CC0 |
| `sfx_ui_hover` | 可选悬停 | ≤40ms | UI | -18 dBFS | 1 | 默认可关；防疲劳 |
| `sfx_ui_open_panel` | 打开面板 | 100–150ms | UI | -14 dBFS | 1 | 可 CC0 |
| `sfx_ui_close_panel` | 关闭 | 80–120ms | UI | -14 dBFS | 1 | 可 CC0 |
| `sfx_search_type` | 可选键入 | ≤30ms | UI | -20 dBFS | 1 | 极轻；默认关 |
| `sfx_airport_select` | 选中机场 | ~120ms | SFX | -12 dBFS | 1 | 清脆定位感 |
| `sfx_buy` | 采购成功 | ~150ms | SFX | -10 dBFS | ≤2 | 基准音高 |
| `sfx_sell` | 出售成功 | ~150ms | SFX | -10 dBFS | ≤2 | **比 buy 高约 2–3 半音** |
| `sfx_error` | 失败/超重 | ~200ms | SFX | -10 dBFS | 1 | 勿尖锐；偏低沉 |
| `sfx_ticket_ok` | 购票成功 | ~250ms | SFX | -10 dBFS | 1 | 略长于 buy |
| `sfx_ff_confirm` | 加速确认 | ~200ms | SFX | -12 dBFS | 1 | |
| `sfx_boarding_alert` | 强制登机 | 400–600ms | SFX | -8 dBFS | 1 | 可两声脉冲；须可辨 |
| `sfx_takeoff` | 过场起飞段 | ~1.6s | Transition | -14 dBFS | 1 | 铺满段；触发 BGM duck |
| `sfx_cruise` | 巡航段 | ~1.8s（可循环垫） | Transition | -16 dBFS | 1 | |
| `sfx_landing` | 降落段 | ~1.6s | Transition | -14 dBFS | 1 | 收束 |
| `sfx_arrive` | 到达结算 | ~300ms | SFX | -10 dBFS | 1 | 正向 |

音高关系：`sell` > `buy` > `error`（相对音高，非绝对音名）。

### 2.4 混音与交互规则

| 规则 | 值 |
|------|-----|
| 主音量默认 | BGM 70% / SFX 100%（设置可调） |
| Ducking | 过场 Transition 播放时 BGM -6dB；结束后 300ms 回升 |
| 同事件叠音 | 同类 SFX 最多 2 层 |
| 静音 | 设置中一键静音；失焦是否静音跟随系统设置项 |
| 无障碍 | 提供「闪烁替代声音」时登机以声+色双通道 |

### 2.5 音频命名与目录

```text
audio_{type}_{name}_{variant}.ogg
```

- type: `bgm` | `sfx` | `amb`  
- 示例：`audio_bgm_globe_day.ogg`，`audio_sfx_ticket_ok.ogg`

```text
game/assets/audio/
  bgm/
  sfx/
  amb/          # 可选环境音
  AUDIO_MANIFEST.csv
```

### 2.6 版权与交付物

每条音频附 `game/assets/audio/AUDIO_MANIFEST.csv`：

```text
id,filename,license,author,source_url,source,loop,loop_start_ms,loop_end_ms,bus,notes
```

| 字段 | 说明 |
|------|------|
| `source` | `procedural`（程序合成）或 `cc0` / `cc-by` / `original` |
| `bus` | `BGM` / `SFX` / `UI` / `Transition` |
| `loop` | `true`/`false` |

可用许可：原创、程序合成（游戏内标注）、CC0、CC-BY（需游戏内署名）。**禁止**未授权流行歌改编。  
CC0 / CC-BY 条目须同步出现在数据来源页（[`game/assets/i18n/attribution_zh.txt`](../game/assets/i18n/attribution_zh.txt)）。

生成工具：[`tools/audio-gen-kit/`](../tools/audio-gen-kit/)（`synthesize_demo_audio.py` + 可选 `fetch_cc0_ui.py`）。

### 2.7 音频验收

- [ ] `bgm_globe_day` + §2.3 P0 SFX 文件齐全，且与 `AUDIO_MANIFEST.csv` 行一一对应  
- [ ] 循环点无爆音/空洞感（BGM 头尾交叉淡化可接受）  
- [ ] 长时间地球界面不引起听觉疲劳  
- [ ] 登机提示在 70% 系统音量下可辨  
- [ ] 过场 5 秒音画段落对齐（takeoff / cruise / landing 时长与 §1.2.C 一致）  
- [ ] 静音开关关闭 BGM+SFX；分轨音量默认 BGM 70% / SFX 100%  
- [ ] Manifest 中 CC0/CC-BY 已写入数据来源页  

### 2.8 可选环境音（预留 · Demo 可不交付）

| ID | 场景 | 备注 |
|----|------|------|
| `amb_terminal` | 航站楼底噪 | 极低电平；可关 |
| `amb_cabin` | 过场客舱底噪 | 可与 `sfx_cruise` 合并 |

命名与目录同 §2.5 `amb/`。

### 2.9 Godot 音频总线

| 总线 | 父级 | 默认增益 | 用途 |
|------|------|----------|------|
| `Master` | — | 0 dB | 总闸 + 静音 |
| `BGM` | Master | -3 dB（约 70% 感知） | 循环配乐 |
| `SFX` | Master | 0 dB | 玩法反馈 |
| `UI` | Master | 0 dB | 点击/面板 |
| `Transition` | Master | 0 dB | 5s 过场；触发 BGM duck |

布局资源：`game/default_bus_layout.tres`。运行时由 `AudioService` 读写音量与 mute。

### 2.10 制作与合成约定

| 项 | 约定 |
|----|------|
| 采样 | 48 kHz stereo |
| 交付 | Ogg Vorbis；无 ffmpeg 时可先 WAV 再转码 |
| 程序合成 | `tools/audio-gen-kit/synthesize_demo_audio.py`；确定性种子，可复跑 |
| CC0 入库 | `fetch_cc0_ui.py` 拉取已知 CC0 包；失败则回退合成并 `source=procedural` |
| 响度 | BGM 目标 -16～-14 LUFS；SFX 峰值见表 §2.3（占位包允许近似） |
| 人声/外包补录 | 参照 `tools/audio-gen-kit/AUDIO_PROMPTS.md` 气质与禁止项 |

### 2.11 Godot Import 与播放约定

| 项 | 约定 |
|----|------|
| Import | Ogg：按 manifest `loop` 设置 loop；`loop_offset` 对齐 `loop_start_ms`（若引擎支持） |
| 播放器 | `AudioService`：BGM 单例 `AudioStreamPlayer`；SFX/UI 小池（≥4）防截断 |
| API | `play_sfx(id)`、`set_bgm(id)`、`set_muted(bool)`、`set_bus_volume(bus, linear)` |
| 静音 | 一键静音写 Master；分轨滑条写各 bus |
| 资源路径 | `res://assets/audio/` + manifest `filename` |

---

## 3. 文本需求

### 3.1 语言与语气

| 项 | 要求 |
|----|------|
| Demo 语言 | **简体中文** |
| 语气 | 冷静、博闻、旅行向；少网感梗、少感叹号堆砌 |
| 称呼 | 对玩家用「你」 |
| 专业度 | 可用 IATA/UTC 等术语，首次在教程中点到为止 |
| 禁止 | 歧视、地域攻击、政治动员、医疗/投资建议、虚假「官方航司合作」表述 |

**强制声明（须原样或语义等价常驻）：**

> 航班网络基于公开航空数据重建，不代表真实购票信息。

出现位置：主界面底栏、购票面板、数据来源页、启动页。

### 3.2 文案分型与字数

#### 3.2.1 UI 微文案

##### 新游戏（New Game）

| 键名（逻辑 ID） | 中文默认 | 备注 |
|-----------------|----------|------|
| `ui.new_game.title` | 选择起始机场 | |
| `ui.new_game.random` | 随机机场 | |
| `ui.new_game.start` | 以当前选中机场开始 | |
| `ui.new_game.search` | 搜索机场 | |
| `ui.new_game.no_results` | 未找到匹配机场 | |

##### 导航标签（Tabs）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.tab.city` | 城市 | |
| `ui.tab.market` | 市场 | |
| `ui.tab.flights` | 航班 | |
| `ui.tab.inventory` | 库存 | |
| `ui.tab.log` | 旅行记录 | |
| `ui.tab.attribution` | 数据来源 | |

##### 加速跳转（Fast Forward）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.ff.button` | 加速至起飞 | CTA |
| `ui.ff.confirm` | 将跳跃约 {hours} 游戏小时至起飞时刻。易腐商品品质会衰减，市场价格按新日期刷新。确认加速？ | |

##### 机票（Tickets）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.ticket.economy` | 经济舱购票 | |
| `ui.ticket.business` | 公务舱购票（10×） | |
| `ui.ticket.refund` | 退票（30% 手续费） | |
| `ui.ticket.no_ticket` | 未持有有效机票 | |

##### 登机（Boarding）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.boarding.title` | 强制登机（不可取消） | |
| `ui.boarding.countdown` | 登机倒计时：{minutes}分 | |

##### 系统通知（Notifications）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.notify.perishable_decay` | 部分商品品质已开始衰减，请尽快出售 | |
| `ui.notify.boarding_soon` | {flight} 将于30分钟内登机，请做好准备 | |
| `ui.notify.arrived` | 已抵达 {city}（{iata}） | |
| `ui.notify.left_boarding` | 已错过 {flight} 登机时间，请重新购票 | |

##### 确认对话框（Confirmations）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.confirm.refund` | 确定退票 {flight}？将收取30%手续费，退还 {amount}。此操作不可撤销。 | |
| `ui.confirm.purchase` | 确认购买 {qty}×{product}，共 {amount}？ | |
| `ui.confirm.baggage_extend` | 确认加购 {type} 行李扩展（+{kg}kg），费用 {amount}？ | |
| `ui.confirm.quit` | 确定退出游戏？未保存进度将丢失。 | |

##### 错误/警告（Errors & Warnings）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.error.overweight` | 行李超重：请加购行李扩展或改走货运 | |
| `ui.error.insufficient_funds` | 资金不足：需要 {need}，当前持有 {have} | |
| `ui.error.no_flights` | 该机场当前无可售定期航班 | |
| `ui.error.max_baggage` | 已超出最大行李容量上限 | |
| `ui.error.expired_product` | {product} 已过期，无法出售 | |
| `ui.error.already_boarding` | 正在登机流程中，无法执行此操作 | |
| `ui.error.save_failed` | 保存失败：{reason} | |

##### 空状态（Empty States）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.empty.inventory` | 库存为空。前往市场采购当地特色商品开始贸易。 | |
| `ui.empty.flights` | 当前无可用的出港航班 | |
| `ui.empty.market` | 当前市场无商品在售 | |
| `ui.empty.log` | 尚未开始旅行。选择一个起始机场出发吧。 | |
| `ui.empty.save` | 暂无存档 | |

##### 设置页（Settings）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.settings.title` | 设置 | |
| `ui.settings.volume_master` | 主音量 | |
| `ui.settings.volume_bgm` | 音乐 | |
| `ui.settings.volume_sfx` | 音效 | |
| `ui.settings.back` | 返回 | |

##### 行李管理（Baggage）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.baggage.title` | 行李管理 | |
| `ui.baggage.weight_used` | 已用 {used} / 上限 {max} kg | |
| `ui.baggage.extend` | 扩展行李容量 | |
| `ui.baggage.extend_light` | 轻量扩展 +10kg（$70） | |
| `ui.baggage.extend_standard` | 标准扩展 +20kg（$125） | |
| `ui.baggage.extend_heavy` | 重型扩展 +50kg（$280） | |

##### 存档（Save）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.save.auto` | 自动存档中... | |
| `ui.save.complete` | 存档完成 | |
| `ui.save.manual` | 手动存档 | |
| `ui.save.load` | 读取存档 | |

##### 游戏结束（Game Over）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.game.bankrupt` | 资金耗尽，你已破产。旅行贸易就此告一段落。 | |
| `ui.game.start_new` | 开始新游戏 | |
| `ui.game.stats` | 本次旅行统计 | |
| `ui.game.total_cities` | 途经城市 | |
| `ui.game.total_profit` | 总利润 | |
| `ui.game.total_flights` | 搭乘航班 | |

##### 通用（Common）

| 键名 | 中文默认 | 备注 |
|------|----------|------|
| `ui.common.ok` | 确定 | |
| `ui.common.cancel` | 取消 | |
| `ui.common.back` | 返回 | |
| `ui.common.price` | 价格 | |
| `ui.common.qty` | 数量 | |
| `ui.common.total` | 合计 | |
| `ui.common.buy` | 购买 | |
| `ui.common.sell` | 出售 | |
| `ui.common.loading` | 加载中... | |
| `ui.disclaimer` | （见强制声明） | |

UI 字符串单行尽量 ≤20 字；按钮 ≤12 字。

#### 3.2.2 教程/引导（弱引导）

触发式，不强制模态长文。所有引导提示可跳过且在第一次触发后不再重复。每条配逻辑 ID：

| 键名 | 触发 | 文案 | 长度 |
|------|------|------|------|
| `tutorial.new_game` | 新档 | 欢迎来到环球航商。你将从这里出发，沿着真实航线在世界各地采购特产、赚取差价。建议先浏览当地市场特色商品，再选购前往下一站的机票。\n\n航班网络基于公开航空数据重建，不代表真实购票信息。 | 79字 |
| `tutorial.first_buy` | 首次购买商品 | 商品已放入行李。点击"航班"标签可查看所有出港航班。公务舱提供更多行李配额，适合长途贸易。 | 43字 |
| `tutorial.first_ticket` | 首次购票 | 机票已购买。你可使用"加速至起飞"跳跃时间至登机时刻，或等待游戏时间自然流逝。注意：加速时易腐商品的品质会衰减。 | 52字 |
| `tutorial.first_arrive` | 首次抵达目的地 | 欢迎抵达新城市。前往"市场"标签查看当地商品价格。原产地购买廉价、稀缺地高价售出，是利润的关键。 | 40字 |
| `tutorial.first_sell` | 首次出售商品 | 成功完成第一次出售。留意各城市间的供需差异和价差，规划一条利润最大化的航线将继续你的旅程。 | 37字 |

#### 3.2.3 城市文本（对齐 PRD §13）

| 字段 | 字数（汉字） | 内容要求 |
|------|--------------|----------|
| `short_description` | 80–150 | 卡片摘要：地理角色 + 气质一句 |
| `overview` | 150–300 | 城市定位、为何成为航线节点 |
| `history_summary` | 100–250 | 史实向，忌野史猎奇 |
| `geography_summary` | 80–200 | 气候、地貌、对旅行的影响 |
| `economy_summary` | 80–200 | 产业与贸易气质 |
| `food_summary` | 80–200 | **合法食品/特产**，不写酒桌文化细节 |
| `travel_note` | 50–150 | 实用提示：交通、气候、行李注意 |

**事实来源：** 优先 Wikidata 结构化事实 + 公共统计，**重新撰写**，禁止整段复制 Wikipedia（PRD §13.4）。  
每城保存 `source_ids` / `content_confidence`（A/B/C）。

Demo：20 座枢纽城必须齐套。命名与机场映射以 `etl/config/hubs_20.yaml` 为准。

**完整城市 JSON 示例（上海）：**

```json
{
  "city_id": "shanghai",
  "name_zh": "上海",
  "name_en": "Shanghai",
  "country_id": "CN",
  "country_zh": "中国",
  "timezone": "Asia/Shanghai",
  "short_description": "上海雄踞长江入海口，是中国最大的经济中心与航空门户。外滩万国建筑群与陆家嘴摩天楼隔江对望，近代开埠以来的贸易基因至今涌动在大小市集之间。",
  "overview": "上海地处东部海岸线中点，是连接中国南北航线与亚太国际网络的枢纽。浦东国际机场辐射全球主要城市，虹桥枢纽则服务国内航线网络。城市消费市场分层丰富，从南京路商圈到本地里弄市集，进口与本土商品均能找到买家。作为全球航线节点，上海是许多玩家在亚太区域贸易的支点城市。",
  "history_summary": "唐代设华亭县，南宋成镇，元朝正式设上海县。1843年开埠后迅速发展为远东金融与贸易中心。20世纪30年代有「东方巴黎」之称。浦东开发开放后，城市天际线与经济体量再次跃升，成为全球金融和航运枢纽。",
  "geography_summary": "位于长江三角洲冲积平原，地势平坦，平均海拔约4米。属亚热带季风气候，夏季湿热、冬季阴冷，梅雨季（6–7月）湿度偏高。黄浦江穿城而过，将市区分为浦西与浦东。紧邻东海，受台风外围影响时有强风。对旅行者的影响：6–9月潮湿多雨，轻便雨具与透气衣物为宜。",
  "economy_summary": "金融服务业、港口物流、高端制造和零售消费为四大支柱产业。上海港集装箱吞吐量常年居全球首位。自贸区政策使进口商品价格相对灵活，城市中等收入群体庞大，对进口食品、化妆品和文创产品需求旺盛，适合高价差品类贸易。",
  "food_summary": "本帮菜以浓油赤酱见长，红烧肉、油爆虾是其代表。南翔小笼包、生煎馒头和排骨年糕构成街头美食图景。城隍庙糕点、大白兔奶糖和阿婆糕是便于携带的特产。崇明岛出产优质大米与河鲜。国际餐饮文化高度融合，几乎能找到任何国家的代表风味。",
  "travel_note": "浦东机场距市中心约30公里，地铁2号线和磁浮可直达。行李运输注意：夏季高温高湿使烘焙类食品保质期缩短，建议优先携带真空包装或干货类特产。6–9月出行备折叠伞。浦东机场航站楼之间需预留额外中转时间。",
  "content_confidence": "A",
  "source_ids": ["wikidata:Q8686", "oag:city-shanghai"]
}
```

**精简示例（伊斯坦布尔）：**

```json
{
  "city_id": "istanbul",
  "name_zh": "伊斯坦布尔",
  "name_en": "Istanbul",
  "country_id": "TR",
  "country_zh": "土耳其",
  "timezone": "Europe/Istanbul",
  "short_description": "伊斯坦布尔横跨博斯普鲁斯海峡，是世界上唯一地跨欧亚两洲的城市。古老巴扎与现代新机场并立，香料、纺织与甜点的贸易传统延续千年。",
  "overview": "伊斯坦布尔新机场是连接欧洲、亚洲和非洲的重要中转枢纽。城市承载拜占庭与奥斯曼帝国的深厚历史，大巴扎、香料市集和独立大道构成多层次的消费场景。本土纺织、手工陶瓷和香料在国际市场享有声誉，是贸易链路中最具异域特色的一站。",
  "history_summary": "公元前660年希腊人建立拜占庭，公元330年成为东罗马帝国首都君士坦丁堡。1453年奥斯曼帝国征服后至今仍为区域文化中心。近代土耳其共和国成立后，伊斯坦布尔继续作为经济文化第一大城市，新机场于2018年启用。",
  "geography_summary": "地处土耳其西北部，博斯普鲁斯海峡将城市分为欧洲区和亚洲区。属地中海—黑海过渡性气候，夏季温暖干燥，冬季凉爽多雨。海峡风力较强，偶尔影响渡轮通行。对旅行者来说，春秋两季（4–5月、9–10月）最宜出行，温差适中。",
  "economy_summary": "服务业与旅游为两大经济引擎，纺织、食品加工和手工艺品是传统支柱产业。大巴扎是世界上最古老的室内市集之一，活跃的商品交易历史超过500年。近年来物流与航空中转产业快速增长，伊斯坦布尔新机场目标是成为全球最大的航空枢纽之一。",
  "food_summary": "土耳其软糖（Lokum）是最具代表性的甜点，玫瑰、坚果和石榴风味兼具。香料巴扎提供孜然、藏红花、苏木那克等。土耳其茶与咖啡是社交日常。芝麻圈面包（Simit）和烤肉卷（Doner）是廉价街头美食。巴克拉瓦（Baklava）薄如蝉翼的酥皮夹心坚果与糖浆。",
  "travel_note": "机场距市中心约40公里，地铁M11线和机场巴士可往返。携带香料时建议密封袋包装，以防香味扩散到其他行李物品中。欧亚两区之间通过渡轮和地铁Marmaray连接。冬季偶有大雪可能影响航班起降。",
  "content_confidence": "A",
  "source_ids": ["wikidata:Q406"]
}
```

#### 3.2.4 商品文本（对齐 PRD §14）

| 字段 | 要求 |
|------|------|
| `name_zh` | 通用类别名，**不用注册商标**（可写「上海纺织品合约」不写某品牌全称） |
| `category` | 枚举：食品/香料/茶叶/咖啡/糖果/工艺品/纺织品/陶瓷/文具/玩具/日用品/机械/能源/电子/矿产；Demo **禁止** `纪念品`；允许轻合约、样品与高价值代购/核心器件 |
| `description` | 40–120 字：产地关联、保存注意、贸易趣味 |
| `weight_kg` | Demo：轻合约约 0.5–2；样品约 3–10；高价值代购/核心器件约 0.2–1.5（均 ≤12） |

每城 Demo ≥5 种；禁售类见 PRD §14.1（酒烟药武等）。

**商品 YAML 示例（含非模板化描述）：**

```yaml
products:
  - product_id: "pvg_longjing"
    name_zh: "龙井茶小包装"
    category: "茶叶"
    weight_kg: 0.2
    base_reference_price: 28.0
    reference_currency: "USD"
    shelf_life_hours: 3600
    fragility: 0.0
    rarity: 0.4
    description: "龙井茶产自杭州西湖周边丘陵，以上海为传统集散地。扁平炒青工艺带来特有的豆香与清甜尾韵。密封避光储存可保持风味半年以上。每年明前采摘的首批茶叶在海外市场可售出数倍于产地的价格。"

  - product_id: "pvg_silk_handkerchief"
    name_zh: "真丝手帕"
    category: "纺织品"
    weight_kg: 0.08
    base_reference_price: 24.0
    reference_currency: "USD"
    shelf_life_hours: 99999
    fragility: 0.0
    rarity: 0.35
    description: "苏杭地区出产的真丝是全球历史最悠久的奢侈品之一。手帕以12姆米以上的桑蚕丝织成，轻盈透气，折叠后几乎不占行李空间。注意避免与粗糙面料摩擦，干燥通风处保存可免虫蛀。在欧美和东亚时装市场都拥有稳定需求。"

  - product_id: "hnd_matcha_sweet"
    name_zh: "抹茶点心"
    category: "食品"
    weight_kg: 0.3
    base_reference_price: 14.0
    reference_currency: "USD"
    shelf_life_hours: 480
    fragility: 0.1
    rarity: 0.3
    description: "使用京都宇治产的煎茶碾磨成粉，与白巧克力和黄油烘焙。茶香浓郁而不苦涩，入口融化后有淡淡的回甘。保质期仅20天左右，跨洋贸易需考虑中转时间，抵达后尽快出售避免过期。在欧美茶叶爱好者群体中非常受欢迎。"

  - product_id: "dxb_saffron"
    name_zh: "藏红花小包装"
    category: "香料"
    weight_kg: 0.05
    base_reference_price: 45.0
    reference_currency: "USD"
    shelf_life_hours: 3600
    fragility: 0.0
    rarity: 0.55
    description: "全球最昂贵的香料之一，每克由约150朵藏红花的手工摘取柱头制成。主要产自伊朗，经迪拜交易市场分销全球。仅需数丝即可为米饭或甜点染上金黄色泽与独特麝香气息。体积微小、单价极高，是行李受限时最优的单位重量利润商品。"

  - product_id: "ist_lokum"
    name_zh: "土耳其软糖"
    category: "糖果"
    weight_kg: 0.5
    base_reference_price: 12.0
    reference_currency: "USD"
    shelf_life_hours: 1500
    fragility: 0.0
    rarity: 0.5
    description: "以淀粉和糖为基底，加入玫瑰水、坚果、椰子或石榴调味。切为方块后裹上一层细糖粉以防粘连。在干燥阴凉的条件下可保存数月。是连接东西方的商路上流传最久的甜食之一，至今仍是伊斯坦布尔大巴扎最受游客欢迎的手信。"
```

#### 3.2.5 数据来源页

必须依以下结构列出各数据源与许可义务。语气中立、条目化，勿写成广告。

##### 本游戏数据来源

**机场坐标与基础信息 — OurAirports**
数据来源：OurAirports 开放数据集（https://ourairports.com/data/）。
许可：Public Domain（Unlicense）。
说明：提供全球机场的IATA/ICAO代码、名称、经纬度、类型等基础信息。本游戏使用其中约 8.5 万条机场记录中的一部分用于地球端展示和航线分析。

**航线参考数据 — OpenFlights**
数据来源：OpenFlights 开放航线与航空公司数据集（https://openflights.org/data.html）。
许可：ODbL 1.0（Open Database License）。基于该数据生成的衍生数据库须以相同许可共享，并保留署名。

ODbL 主要义务摘要：
1. 署名：需注明数据来源于 OpenFlights。
2. 相同方式共享：使用本数据构建的衍生作品须以 ODbL 或兼容许可公开。
3. 无附加限制：不得以技术措施限制他人使用衍生数据库。
完整的 ODbL 法律文本请参阅：https://opendatacommons.org/licenses/odbl/1.0/

**航班时刻表 — 合成重建**
说明：本游戏中的航班号、起飞/到达时间由算法根据公开航线数据及航空业规则合成生成，并非任一同真实航空公司时刻表的完整拷贝。所有航班信息均为模拟数据，旨在提供一种合理的航线体验。

**商品价格参考 — 公开零售数据估算**
说明：各城市商品基准价为模型估算，非实时市场价。参考来源包括：公开电商平台年中年均价格、国际贸易统计年鉴中品类单价中位数、以及城市间对比生活方式网站调查数据。价格冻结基准日为 2025年3月1日。

**汇率快照**
说明：本游戏内部使用 USD 作为统一结算货币。展示时本地货币按快照汇率折算为 CNY（人民币），快照冻结日为 2025年3月1日。汇率取自当日公开中间价。此汇率仅供游戏内参考，不反映实时金融市场。

**城市背景文字**
说明：城市简介、历史、地理、经济、饮食及旅行贴士均由游戏团队基于 Wikidata 结构化事实（CC0）原创撰写。未直接复制 Wikipedia 或其他受 CC BY-SA 许可约束的文本源。

**字体**
（若使用 CC-BY 或 OFL 字体，列出字体名、作者、许可与出处。）

**音频**
- Demo BGM（`bgm_globe_day`）及大部分玩法音效：程序合成（`tools/audio-gen-kit`），许可 `original-procedural`。  
- 部分 UI 点击/面板音效：Kenney UI Audio（CC0），作者 Kenney；入库镜像见 `game/assets/audio/AUDIO_MANIFEST.csv`。  
完整清单以 Manifest 为准，并同步 [`game/assets/i18n/attribution_zh.txt`](../game/assets/i18n/attribution_zh.txt)。

**重要声明**
本游戏中的航班网络、票价和航班时刻均为模拟或模型估算，不代表任何航空公司的真实运营信息或实时购票建议。所有商品价格为固定快照，不反映实时市场价格。本游戏内容仅供娱乐目的。

#### 3.2.6 系统通知与提示文案

##### 商品相关（Commodity Notices）

| 键名 | 中文默认 | 触发条件 |
|------|----------|----------|
| `ui.notify.quality_decay` | "{product} 品质已衰减至 {level}，建议尽快出售。" | 商品品质跌破阈值 |
| `ui.notify.product_expiring` | "{product} 将在 {hours} 小时内过期，建议尽快出售或丢弃。" | 商品临近保质期 |
| `ui.notify.product_rotten` | "{product} 已完全过期，从库存中自动移除。" | 商品过期 |

##### 航班相关（Flight Notices）

| 键名 | 中文默认 | 触发条件 |
|------|----------|----------|
| `ui.notify.flight_missed` | "已错过 {flight} 的登机时间，机票作废。请重新购票。" | 错过登机 |
| `ui.notify.last_call` | "{flight} 最后登机提醒，请立即前往登机口。" | 最后一次登机提醒 |
| `ui.notify.flight_departed` | "{flight} 已从 {origin} 出发前往 {dest}。" | 航班离港 |

##### 财务相关（Financial Notices）

| 键名 | 中文默认 | 触发条件 |
|------|----------|----------|
| `ui.notify.low_funds` | "当前资金低于 {threshold}，请谨慎消费。" | 资金低于阈值 |
| `ui.notify.profit_milestone` | "累计利润突破 {amount}！" | 利润里程碑 |

##### 存档提示（Save Prompts）

| 键名 | 中文默认 | 触发条件 |
|------|----------|----------|
| `ui.save.reminder` | "距离上次保存已 {minutes} 分钟，建议手动存档。" | 长时间未存档 |
| `ui.save.before_flight` | "即将登机，是否手动存档？" | 登机前 |

##### 退款/取消（Refund）

| 键名 | 中文默认 | 触发条件 |
|------|----------|----------|
| `ui.refund.refunded` | "已退票 {flight}，退款 {amount} 已到账。" | 退票成功 |
| `ui.refund.cannot_refund` | "已开始登机流程，无法退票。" | 退票失败 |

#### 3.2.7 加载/过渡文案

##### 加载画面世界趣闻（Loading Tips）

以下为15条随机显示的旅行/航空冷知识，预计在 Godot 加载屏幕每3–5秒切换一条：

| 索引 | 文案 |
|------|------|
| 1 | 全球每天约有10万架次商业航班起飞，连接超过1.7万对城市。 |
| 2 | 哈茨菲尔德-杰克逊机场（ATL）自1998年以来几乎每年都是全球最繁忙机场。 |
| 3 | 一架波音777的巡航速度约为900km/h，相当于每秒前进250米。 |
| 4 | 藏红花是世界上最贵的香料之一，每克价格可超过黄金。 |
| 5 | 香港国际机场建于填海造地的人工岛上，1998年启用前启德机场是世界上最难降落的机场之一。 |
| 6 | 阿姆斯特丹史基浦机场位于海平面以下约3米，跑道在荷兰围海造田的低地上。 |
| 7 | 新加坡樟宜机场连续多年被评为全球最佳机场，设有蝴蝶园与室内瀑布。 |
| 8 | 从东京飞往伦敦的航班，因地球自转和高空急流，去程比回程长约1小时。 |
| 9 | OpenFlights 航线数据库包含超过6万条航空公司运营的城市对航线。 |
| 10 | 民航客机通常在1万米左右的高度巡航，该高度层空气稀薄、阻力小、燃油经济性最佳。 |
| 11 | 北京首都机场T3航站楼单体建筑面积约98万平方米，是近几十年全球最大的航站楼之一。 |
| 12 | 茶叶是世界上仅次于水的第二大消费饮料，最早可追溯至中国商代。 |
| 13 | 伊斯坦布尔是世界上唯一横跨两大洲的城市，博斯普鲁斯海峡分隔了欧洲和亚洲。 |
| 14 | 迪拜国际机场免税店年销售额超过20亿美元，是世界上最大的机场零售空间之一。 |
| 15 | 芝加哥奥黑尔机场的IATA代码ORD源自其前身"Orchard Field"（果园机场）。 |

##### 出发/抵达过渡提示

| 键名 | 中文默认 | 场景 |
|------|----------|------|
| `ui.transition.departing` | "正在离开 {city}..." | 起飞过场 |
| `ui.transition.arriving` | "即将抵达 {city}..." | 降落过场 |
| `ui.transition.flight_info` | "{flight} | {origin} → {dest} | {distance}km | {cabin}" | 过场信息卡 |

### 3.3 文本格式与存储

| 内容 | 推荐格式 | 路径建议 |
|------|----------|----------|
| UI 字符串 | CSV 或 JSON（`key,zh_CN`） | `game/assets/i18n/zh_CN.csv` |
| 城市 | JSON（ETL `content/cities/{city_id}.json`） | 导入 `world.json` |
| 商品 | YAML/JSON | `etl/content/products/{city_id}.yaml` |
| 教程 | JSON 列表 | `game/assets/i18n/tutorial_zh.json` |

**JSON 城市示例：** 参见 §3.2.3 中上海与伊斯坦布尔的完整示例。

编码：**UTF-8无 BOM**；换行 LF。

### 3.4 文本命名规则

| 类型 | ID 规则 | 示例 |
|------|---------|------|
| UI key | `ui.{screen}.{element}` 小写点分 | `ui.ff.button` |
| 城市 | `city_id` snake ASCII | `hong_kong` |
| 商品 | `{iata_or_city}_{slug}` | `pvg_longjing` |
| 教程 | `tutorial.{event}` | `tutorial.first_ticket` |

商品 `slug`：英文小写、数字、下划线；≤32 字符。

### 3.5 数字与单位书写规范

| 类型 | 格式 |
|------|------|
| 货币 | 内结算 USD；展示 `$1234.56`（`EconomySystem.format_money`，不折算人民币） |
| 重量 | `12.5kg`，小数最多 1 位 |
| 时间 | UTC：`2025-03-01 12:00`；当地：同时区名或「当地」前缀 |
| 航班号 | 大写 IATA+数字，如 `MU510` |
| 机场 | 同时给中文名 + IATA：`上海浦东（PVG）` |

### 3.6 文案验收

- [ ] 20 城字段齐全且达字数下限  
- [ ] 100 种商品描述均为非模板化原创文案（40–120字/条）  
- [ ] 无禁售类别商品文案（酒、烟、药、武等）  
- [ ] 无未授权品牌名作为商品主名  
- [ ] 强制声明出现在主界面底栏、购票面板、数据来源页、启动页  
- [ ] UI 无截断（常见按钮在 1280 宽下不换行溢出）  
- [ ] 教程可跳过且不阻塞时间流逝规则（除设置/存档暂停）  
- [ ] 所有通知文案不重复、语义清晰  
- [ ] 加载画面15条趣闻可随机展示  
- [ ] 数据来源页包含所有必要条目且许可表述完整  

### 3.7 文本审核与质量控制流程

#### 3.7.1 提交前自检（作者自查）

每位文案贡献者在提交 PR / MR 前应完成：

- [ ] 每个字段是否达到最小字数（按 §3.2.3 / §3.2.4 标准）  
- [ ] 是否使用 Wikidata CC0 事实而非直接翻译 Wikipedia  
- [ ] 是否存在商标、品牌名称（除非是通用类别名）  
- [ ] 用词是否符合语气规范（冷静、博闻、旅行向；无网感梗、无感叹号堆砌）  
- [ ] 使用名称对玩家是否统一用「你」  
- [ ] 拼音、地名、IATA 等专业术语拼写自查  
- [ ] 是否在 `source_ids` 字段填写了事实来源  
- [ ] 内容置信度字段是否合理设置  

#### 3.7.2 评审维度（Reviewer Checklist）

| 维度 | 检查项 |
|------|--------|
| 风格一致性 | 语气是否符合冷静、博闻调性；是否统一用「你」称呼 |
| 事实准确性 | Wikidata 结构化事实是否被正确引用与转述 |
| 版权合规 | 是否误用 CC BY-SA 内容或其它非 CC0 源文本 |
| 敏感内容 | 是否存在 §3.1 "禁止" 项 |
| 可读性 | 是否存在过长句（单句>50字）、过度堆砌术语 |
| 游戏性 | 文案是否与玩法信息冲突（如过场文本遮挡倒计时） |

#### 3.7.3 禁用词与敏感词检查

可配置项目级 `.textlintrc` 或 pre-commit hook 进行以下自动检测：

1. **品牌名/商标检测**：匹配已知全球100大品牌名，回归词库
2. **敏感词检测**：「官方合作」「真实票价」「投资建议」等违规表述  
3. **感叹号滥用检测**：同一段落连续使用 ≥2 个「！」标记  
4. **网感梗检测**：「绝绝子」「yyds」「种草」「破防了」等高频网络用语词库  
5. **地域/族群歧视表述检测**：中国大陆网络敏感词库（政治、地域、族群）

使用方式：在 CI 中集成 `textlint` + 自定义规则文件 `textlintrc.json`。

### 3.8 多语言预留与扩展设计

Demo 阶段仅支持简体中文。以下设计确保文本框架未来可扩展英文及其它语言。

#### 3.8.1 i18n Key 映射表

| 组件 | 当前实现 | 多语言扩展方式 |
|------|----------|----------------|
| UI 字符串 | CSV `zh_CN.csv` | 增加 `en.csv` 列并行；Godot 导入为 `.translation` 资源 |
| 教程文案 | JSON `tutorial_zh.json` | 更名为 `tutorial_{locale}.json`，按 locale 加载 |
| 城市文本 | 世界数据中内嵌 `name_zh`，`short_description`，`overview` 等 | 扩展为 `texts.{locale}.short_description` 嵌套结构 |
| 商品文本 | 世界数据中内嵌 `name_zh`，`description` | 扩展为 `name.{locale}`，`description.{locale}` |
| 数据来源页 | 纯文本文件 `attribution_zh.txt` | 路径含 locale 变量：`attribution_{locale}.txt` |

#### 3.8.2 Godot Translation 导入约定

- CSV 文件第一行为 header：`keys,zh_CN,en,...`  
- 使用 Godot 内置的 `gettext` 或 CSV Translation 导入预设  
- Translation 资源仅打包当前语言的 `.translation` 文件以减包体  
- 文本 key 名与游戏代码中 `tr("ui.tab.city")` 调用一致  

#### 3.8.3 未来英文版本翻译约定

预计从简体中文翻译为英文（zh-CN → en）：

- 城市名称沿用国际通用英文名（如 "Shanghai"、"Istanbul"）  
- 商品名使用通用译名 + 英文说明（如 `Longjing Green Tea (Small Pack)`）  
- 保持冷静旅行的语气基调，英文使用第二人称 "you"  
- 专业术语采用 IATA/ICAO 标准英文缩写  
- 数据来源页英文版需同步更新许可表述至英文原文  

#### 3.8.4 社区翻译字段约定

如未来开放社区翻译：
- 除城市、商品描述外的 UI/教程文本通过 `crowdin.yml` 或 `weblate` 管理  
- 城市、商品文本走 PR/评审流程（因涉及 Wikidata 事实准确性）  
- 翻译贡献者须在数据来源页署名  

---

## 4. 跨职能协作与流水线

### 4.1 角色与交接

```text
文案定稿 → ETL/JSON 入库 → 程序绑定 key
美术导出 → game/assets/** → Godot Import 预设
音频导出 → game/assets/audio/** → AudioStream 资源 + Manifest
```

### 4.2 Godot 导入约定

| 资源 | Import 预设要点 |
|------|-----------------|
| UI 图标 | Filter on；Mipmaps on |
| 地球 albedo | Mode VRAM Compressed；sRGB |
| 字体 | 仅打包所用字符可后续优化；Demo 可打全中文 |
| Ogg | Loop 按 manifest |

### 4.3 版本与评审

- 资源变更走 PR；大图/音频考虑 Git LFS（`*.ogg` `*_2k.png`）。  
- 评审维度：风格一致性、可读性、版权、与玩法信息是否冲突（如过场遮挡倒计时）。  

### 4.4 里程碑交付包（Demo）

**美术包 D1：** 地球贴图、图标全套、UI StyleBox、过场三段、品牌字标。  
**音频包 D1：** `bgm_globe_day` + P0 SFX 表全项。  
**文本包 D1：** UI CSV + 20 城 JSON + 100 商品描述 + 数据来源页终稿。

验收以 PRD §27 + 本文档各章验收表为准。

---

## 5. 附录

### 5.1 Demo 20 城（文案/美术优先级）

ATL 亚特兰大 · DXB 迪拜 · DFW 达拉斯 · DEN 丹佛 · LHR 伦敦 · ORD 芝加哥 · IST 伊斯坦布尔 · LAX 洛杉矶 · HND 东京 · PVG 上海 · CDG 巴黎 · AMS 阿姆斯特丹 · CAN 广州 · FRA 法兰克福 · PEK 北京 · SIN 新加坡 · ICN 首尔 · HKG 香港 · BKK 曼谷 · MIA 迈阿密  

### 5.2 参考情绪（非抄袭）

- 航图印刷品的清爽分色  
- 当代航站楼指示系统设计  
- 旅行纪录片日间外景调性  

### 5.3 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-07-26 | 首版：覆盖美术/音乐/文本风格、内容、格式、命名与验收 |
| v1.1 | 2026-07-26 | §2 音频章补全（总线/环境音/合成约定/Import）+ Demo 音频包 D1 交付说明 |
| v1.2 | 2026-07-26 | 新增 §0.5 仓库现状盘点；标明阶段一不依赖美术包 D1 |
| v1.3 | 2026-07-26 | §0.5：基础 Theme + 字体标为已齐；对齐可玩 Demo §27 |
| v1.4 | 2026-07-27 | §0.5：地球/网格/Pin/飞机/过场几何/IconFactory 代码占位符已齐；明确 D1 待交付清单 |

---

**维护者：** 与程序仓库同仓维护；重大风格变更需同步更新 PRD 非目标/法律章节引用。
