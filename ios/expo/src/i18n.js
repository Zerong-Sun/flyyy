/**
 * Minimal i18n — en/zh dictionaries + a small lookup helper.
 * M3 I1: UI language switch; structure reserved for deeper adoption.
 */
export const LOCALES = ['en', 'zh'];

export const DICT = {
  en: {
    brand: 'Airborne Trader',
    tab_globe: 'Globe',
    tab_market: 'Market',
    tab_flights: 'Flights',
    tab_bags: 'Bags',
    tab_more: 'More',
    market_title: 'Market',
    flights_title: 'Flights',
    bags_title: 'Bags',
    more_title: 'More',
    settings_title: 'Settings & save',
    notes_title: 'Trader notes',
    ach_title: 'Achievements',
    log_title: 'Trade log',
    sources_title: 'Sources',
    market_here: 'Local goods',
    market_import: 'Imported goods',
    buy: 'Buy',
    sell: 'Sell',
    book: 'Book',
    departures: 'Departures',
    carry_on: 'Carry-on',
    cargo: 'Cargo',
    speed_up: 'Speed up',
    settings_lang: 'Language',
    settings_lang_sub: 'Switch UI between English and 中文.',
  },
  zh: {
    brand: '环球航商',
    tab_globe: '环球',
    tab_market: '市场',
    tab_flights: '航班',
    tab_bags: '行李',
    tab_more: '更多',
    market_title: '市场',
    flights_title: '航班',
    bags_title: '行李',
    more_title: '更多',
    settings_title: '设置与存档',
    notes_title: '商旅手记',
    ach_title: '成就',
    log_title: '交易记录',
    sources_title: '数据来源',
    market_here: '本地商品',
    market_import: '进口商品',
    buy: '买入',
    sell: '卖出',
    book: '预订',
    departures: '出发',
    carry_on: '随身行李',
    cargo: '货运',
    speed_up: '加速',
    settings_lang: '语言',
    settings_lang_sub: '在英文与中文之间切换界面。',
  },
};

export function t(locale, key, fallback = key) {
  const table = DICT[locale] || DICT.en;
  return table[key] ?? fallback;
}
