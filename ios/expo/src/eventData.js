/**
 * Expo city-event catalog.
 *
 * Categories intentionally use the same stable English identifiers as
 * gameData PRODUCTS; display names are localized at the UI boundary.
 */
export const EVENTS = [
  {
    id: 'istanbul_corridor_relief', cityId: 'istanbul', kind: 'policy',
    headline: { en: 'Temporary customs relief opens on the Eurasian corridor', zh: '欧亚贸易走廊启用临时通关优惠' },
    body: {
      en: 'Simplified export checks lower sourcing costs for textiles and crafts, while extra business traffic tightens flights.',
      zh: '纺织品与工艺品出口手续简化，本地采购成本下降；新增商务客流令航线略显紧张。',
    },
    probability: 0.18, durationDays: 3,
    market: { categories: ['Textiles', 'Crafts'], buyMult: 0.90, sellMult: 1.16 },
    flight: { fareMult: 1.08, cancelProb: 0.05 },
  },
  {
    id: 'dubai_sandstorm', cityId: 'dubai', kind: 'weather',
    headline: { en: 'Sandstorm cuts visibility at Dubai International', zh: '沙尘暴压低迪拜机场能见度' },
    body: {
      en: 'Intermittent runway restrictions slow free-zone warehouses and lift spot quotes for energy, spices, and crafts.',
      zh: '跑道间歇限流拖慢自由区仓储周转，能源、香料与工艺品的现货报价同步上扬。',
    },
    probability: 0.20, durationDays: 1,
    market: { categories: ['Energy', 'Spices', 'Crafts'], buyMult: 1.14, sellMult: 1.09 },
    flight: { fareMult: 1.16, cancelProb: 0.24 },
  },
  {
    id: 'london_customs_fx', cityId: 'london', kind: 'policy',
    headline: { en: 'Sterling swings as customs inspections tighten', zh: '英镑波动，海关加强抽检' },
    body: {
      en: 'Currency swings attract overseas buyers for tea and textiles, but tighter inspections squeeze air-cargo capacity.',
      zh: '汇率波动吸引海外买家采购茶叶与纺织品，边检加严则挤压航空货运舱位。',
    },
    probability: 0.16, durationDays: 2,
    market: { categories: ['Tea', 'Textiles'], buyMult: 1.05, sellMult: 1.18 },
    flight: { fareMult: 1.09, cancelProb: 0.06 },
  },
  {
    id: 'paris_fashion_week', cityId: 'paris', kind: 'cultural',
    headline: { en: 'Paris Fashion Week lifts boutique demand', zh: '巴黎时装周带动精品采购' },
    body: {
      en: 'Visiting buyers compete for cosmetics and confectionery gifts while premium travel demand fills late departures.',
      zh: '到访买家集中采购美妆与糖果礼盒，高端出行需求也令晚间航班趋紧。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Cosmetics', 'Confectionery'], buyMult: 1.07, sellMult: 1.18 },
    flight: { fareMult: 1.12, cancelProb: 0.04 },
  },
  {
    id: 'amsterdam_auction_stoppage', cityId: 'amsterdam', kind: 'infrastructure',
    headline: { en: 'Flower auction and ground crews stage a short stoppage', zh: '鲜花拍卖与地勤同步短停' },
    body: {
      en: 'A short stoppage tightens time-sensitive flower and food supply and forces Schiphol to consolidate services.',
      zh: '短暂停工令鲜花与食品等时效商品供应收紧，史基浦部分班次被迫合并。',
    },
    probability: 0.20, durationDays: 1,
    market: { categories: ['Daily goods', 'Food'], buyMult: 1.22, sellMult: 1.18 },
    flight: { fareMult: 1.12, cancelProb: 0.18 },
  },
  {
    id: 'frankfurt_industry_fair', cityId: 'frankfurt', kind: 'economic',
    headline: { en: 'Frankfurt industry fair tightens air capacity', zh: '法兰克福工业展挤压航空舱位' },
    body: {
      en: 'Factory buyers raise demand for machinery and leather samples as exhibitors fill regional flights.',
      zh: '制造业买家集中采购机械与皮革样品，参展客流同时推高区域航线需求。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Machinery', 'Crafts'], buyMult: 1.06, sellMult: 1.17 },
    flight: { fareMult: 1.14, cancelProb: 0.04 },
  },
  {
    id: 'beijing_cultural_fair', cityId: 'beijing', kind: 'cultural',
    headline: { en: 'Beijing cultural fair draws traditional-goods buyers', zh: '北京文博会催热传统商品' },
    body: {
      en: 'Collectors seek crafts and specialty foods while delegations add modest pressure to Capital Airport departures.',
      zh: '收藏买家集中寻找工艺品与特色食品，参会代表也令首都机场离港需求小幅增加。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Crafts', 'Food'], buyMult: 1.05, sellMult: 1.16 },
    flight: { fareMult: 1.08, cancelProb: 0.03 },
  },
  {
    id: 'shanghai_typhoon_port', cityId: 'shanghai', kind: 'weather',
    headline: { en: 'Typhoon bands approach the Yangtze Delta', zh: '台风外围逼近长三角' },
    body: {
      en: 'Strong winds throttle port and airport capacity, lifting replenishment costs for textiles, tea, and machinery.',
      zh: '强风迫使港区和机场分批限流，纺织品、茶叶与机械备件的补库成本上升。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Textiles', 'Tea', 'Machinery'], buyMult: 1.18, sellMult: 1.12 },
    flight: { fareMult: 1.15, cancelProb: 0.25 },
  },
  {
    id: 'hong_kong_jewellery_week', cityId: 'hong_kong', kind: 'economic',
    headline: { en: 'Hong Kong jewellery week draws regional buyers', zh: '香港珠宝拍卖周吸引区域买家' },
    body: {
      en: 'Auction houses compete for jewellery and licensed collectibles as buyer traffic fills short-haul flights.',
      zh: '拍卖行争抢珠宝与授权收藏品，集中到访的买家也推高短途航班需求。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Crafts', 'Toys'], buyMult: 1.08, sellMult: 1.19 },
    flight: { fareMult: 1.13, cancelProb: 0.03 },
  },
  {
    id: 'tokyo_typhoon_supply', cityId: 'tokyo', kind: 'weather',
    headline: { en: 'Kanto typhoon disrupts precision supply chains', zh: '关东台风打乱精密制造供应链' },
    body: {
      en: 'Bay-area factories pause shipments, tightening electronics and food logistics as Haneda reduces movements.',
      zh: '湾岸工厂暂停出货，电子与食品物流趋紧，羽田机场同时压缩进出港时刻。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Electronics', 'Food'], buyMult: 1.17, sellMult: 1.13 },
    flight: { fareMult: 1.13, cancelProb: 0.25 },
  },
  {
    id: 'singapore_trade_expo', cityId: 'singapore', kind: 'economic',
    headline: { en: 'Trade expo sends Changi demand surging', zh: '樟宜国际贸易展客流激增' },
    body: {
      en: 'Regional buyers seek cosmetics and crafts while exhibition traffic lifts both sale prices and airfares.',
      zh: '区域采购商集中寻找美妆与工艺品，展会客流令商品售价与客票同步走高。',
    },
    probability: 0.17, durationDays: 2,
    market: { categories: ['Cosmetics', 'Crafts'], buyMult: 1.07, sellMult: 1.20 },
    flight: { fareMult: 1.18, cancelProb: 0.04 },
  },
  {
    id: 'bangkok_monsoon_flood', cityId: 'bangkok', kind: 'weather',
    headline: { en: 'Monsoon flooding stalls Bangkok logistics', zh: '季风积水拖慢曼谷物流' },
    body: {
      en: 'Flooded roads slow spice and textile deliveries while thunderstorms constrain airport ground operations.',
      zh: '低洼道路积水拖慢香料与纺织品入城，雷暴也限制机场地面保障能力。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Spices', 'Textiles'], buyMult: 1.15, sellMult: 1.11 },
    flight: { fareMult: 1.10, cancelProb: 0.20 },
  },
  {
    id: 'atlanta_logistics_summit', cityId: 'atlanta', kind: 'economic',
    headline: { en: 'Atlanta logistics summit raises transfer demand', zh: '亚特兰大物流大会推高转运需求' },
    body: {
      en: 'Freight operators place fresh machinery and food orders while connecting delegates fill the hub.',
      zh: '货运企业增加机械与食品订单，转机参会者也让这座枢纽更加繁忙。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Machinery', 'Food'], buyMult: 1.06, sellMult: 1.17 },
    flight: { fareMult: 1.11, cancelProb: 0.04 },
  },
  {
    id: 'dallas_energy_expo', cityId: 'dallas', kind: 'economic',
    headline: { en: 'Dallas energy expo boosts equipment orders', zh: '达拉斯能源展拉动设备采购' },
    body: {
      en: 'Energy firms compete for contracts and machinery components as exhibition traffic tightens departures.',
      zh: '能源企业集中争取合同并采购机械部件，展会客流令离港座位趋紧。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Energy', 'Machinery'], buyMult: 1.07, sellMult: 1.18 },
    flight: { fareMult: 1.12, cancelProb: 0.03 },
  },
  {
    id: 'denver_snow_outdoor', cityId: 'denver', kind: 'weather',
    headline: { en: 'Rockies snowstorm collides with outdoor expo', zh: '落基山暴雪撞上户外用品展' },
    body: {
      en: 'Expo visitors lift food and craft demand while de-icing slows Denver airport operations.',
      zh: '展会游客推高食品与工艺纪念品需求，除冰作业则拖慢丹佛机场周转。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Food', 'Crafts'], buyMult: 1.09, sellMult: 1.19 },
    flight: { fareMult: 1.14, cancelProb: 0.25 },
  },
  {
    id: 'chicago_commodities_fair', cityId: 'chicago', kind: 'economic',
    headline: { en: 'Chicago commodities fair draws bulk buyers', zh: '芝加哥农贸展迎来集中采购' },
    body: {
      en: 'Regional buyers seek grain lots and machinery parts while commercial travel fills the morning bank.',
      zh: '区域买家集中采购粮食与机械零件，商务客流也填满早间航班波次。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Food', 'Machinery'], buyMult: 1.05, sellMult: 1.17 },
    flight: { fareMult: 1.10, cancelProb: 0.03 },
  },
  {
    id: 'los_angeles_film_market', cityId: 'los_angeles', kind: 'cultural',
    headline: { en: 'Los Angeles film market boosts props and tech demand', zh: '洛杉矶影视市场带动道具与科技采购' },
    body: {
      en: 'Production teams bid for props and electronics as international distributors arrive for screenings.',
      zh: '制作团队竞购影视道具与电子设备，国际发行商到访也推高航线需求。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Crafts', 'Electronics'], buyMult: 1.07, sellMult: 1.18 },
    flight: { fareMult: 1.12, cancelProb: 0.03 },
  },
  {
    id: 'guangzhou_canton_fair', cityId: 'guangzhou', kind: 'economic',
    headline: { en: 'Canton Fair lifts textile and ceramics orders', zh: '广交会开幕，纺织与陶瓷订单增加' },
    body: {
      en: 'Overseas buyers place fresh craft and tea orders while exhibition traffic raises regional fares.',
      zh: '海外买家集中下单工艺品与茶具，展会客流同时推高区域航线票价。',
    },
    probability: 0.18, durationDays: 3,
    market: { categories: ['Crafts', 'Tea'], buyMult: 1.06, sellMult: 1.20 },
    flight: { fareMult: 1.14, cancelProb: 0.03 },
  },
  {
    id: 'seoul_beauty_week', cityId: 'seoul', kind: 'cultural',
    headline: { en: 'Seoul beauty launch week draws duty-free buyers', zh: '首尔美妆新品周吸引免税买家' },
    body: {
      en: 'Retail groups compete for cosmetics launches while buyer delegations fill Incheon departures.',
      zh: '零售集团集中争夺美妆新品，采购代表团也令仁川离港需求升温。',
    },
    probability: 0.18, durationDays: 2,
    market: { categories: ['Cosmetics'], buyMult: 1.06, sellMult: 1.20 },
    flight: { fareMult: 1.11, cancelProb: 0.03 },
  },
  {
    id: 'miami_hurricane_watch', cityId: 'miami', kind: 'weather',
    headline: { en: 'Hurricane watch issued for Miami', zh: '迈阿密发布飓风观察预警' },
    body: {
      en: 'Residents stock up on food and daily goods while Miami International trims its schedule.',
      zh: '居民集中采购食品与日用品，迈阿密机场同时开始压缩航班计划。',
    },
    probability: 0.16, durationDays: 2,
    market: { categories: ['Food', 'Daily goods'], buyMult: 1.19, sellMult: 1.22 },
    flight: { fareMult: 1.18, cancelProb: 0.25 },
  },
];

export const EVENT_BY_ID = Object.fromEntries(EVENTS.map((event) => [event.id, event]));
