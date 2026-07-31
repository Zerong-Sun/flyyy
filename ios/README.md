# Airborne Trader — iOS 原型

这里是《环球航商》的 iOS 交互式设计原型，不是原生 Xcode 工程。原型通过 Design Canvas 文档运行，覆盖环球首页、市场、购买、航班、登机、抵达和出售流程。

## 入口

- `Airborne Trader iOS.dc.html` — 可交互原型入口
- `ios-frame.jsx` — iOS 设备框架与通用组件
- `support.js` — Design Canvas 运行时支持代码
- `screenshots/` — 设计评审截图

直接在支持 Design Canvas 的预览环境中打开入口文档即可。资源引用均使用相对路径，整个 `ios/` 目录可以独立复制或提交。

## 资源结构

```text
ios/
├── Airborne Trader iOS.dc.html
├── ios-frame.jsx
├── support.js
├── README.md
├── assets/
│   ├── achievements/   # 成就图标
│   ├── animations/     # 起飞、巡航、降落过场
│   ├── brand/          # App 图标、Logo、启动图
│   ├── cities/         # 城市卡片图片
│   ├── icons/          # 页面与状态图标
│   ├── products/       # 商品图片
│   └── world/          # 地球贴图
└── screenshots/
```

## 当前版本

- 6 个示例枢纽城市及其市场、航班和价格情报
- 5 个底部导航页签
- 买入 → 订票 → 加速 → 飞行过场 → 抵达 → 卖出的完整演示链路
- 与 Godot 主工程共用的视觉方向和内容命名约定

## 与 Godot 主工程的关系

`ios/` 是独立的展示原型资源；实际游戏逻辑仍位于 `game/`，数据生成仍位于 `etl/`。修改 Godot 资产后，需要按 iOS 原型所需的尺寸和命名重新导出对应资源，不会自动同步。
