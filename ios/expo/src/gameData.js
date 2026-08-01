/* ============================================================
   Content API — cities, products and flights
   ------------------------------------------------------------
   Everything playable enters the game through three functions.
   Register a hub and it appears on the globe, in the market, on
   every departure board, in the notes and in the achievements
   with no further wiring.

     defineCity({
       id:'doha', name:'Doha', airport:'Hamad International',
       iata:'DOH', icao:'OTHH', country:'Qatar', cont:'Asia',
       hero:'assets/city_doha.webp', lat:25.27, lon:51.61,
       elev:13, tz:3,
       airline:['QR','Qatar Airways'],
       note:'Gulf transfer hub …',
       costIndex:1.02,              // local price level, 1 = neutral
       demand:{ Textiles:1.2 },     // category appetite for imports
       products:[ … ], flights:[ … ] // optional nested content
     })

     defineProduct({
       id:'doh_pearl', home:'doha', name:'Gulf Pearls',
       category:'Crafts', icon:'assets/p_doh_pearl.webp',
       w:0.2, base:2600,
       volatility:1.4,              // widens/narrows the spread
       demandIn:{ london:1.25 }     // per-city standing premium
     })

     defineFlight({
       from:'doha', to:'istanbul', dep:'01:30', no:'QR 239',
       airline:'Qatar Airways', mins:230, econ:210, biz:640,
       stops:'Nonstop', aircraft:'A350-1000',
       replace:true                 // supersede the generated leg
     })

     removeCity('doha')             // also drops its goods + routes

   Only the ids are required. Missing fields fall back: IATA from
   the id, icon from the category, block time and fares from
   great-circle distance, airline from the city name.

   Art note: Metro bundles images from literal require() paths in
   src/assets.js, so add the file there too — an unknown path
   falls back to the generic product tile rather than crashing.
   ============================================================ */

export const CITIES = {};
export const CIDS = [];
export const PRODUCTS = {};
export const PRODUCT_IDS = [];
export const FLIGHTS = [];
export const AIRLINE = {};
export const NOTE_TEXT = {};

const CAT_ICON = {
  Electronics: 'assets/p_cat_electronics.webp',
  Energy: 'assets/p_cat_energy.webp',
  Toys: 'assets/p_cat_toys.webp',
  Crafts: 'assets/p_generic.webp',
  Machinery: 'assets/p_fra_machinery.webp',
  Textiles: 'assets/p_ist_textile.webp',
  Cosmetics: 'assets/p_cdg_cosmetics.webp',
  Food: 'assets/p_ams_cheese.webp',
  Spices: 'assets/p_dxb_spice.webp',
  Tea: 'assets/p_lhr_tea.webp',
  Confectionery: 'assets/p_ist_lokum.webp',
  'Daily goods': 'assets/p_ams_flower.webp',
};

const warn = (m) => console.warn('[content] ' + m);
const num = (...v) => {
  for (let i = 0; i < v.length; i += 1) {
    const x = v[i];
    if (x !== undefined && x !== null && x !== '' && !Number.isNaN(Number(x))) return Number(x);
  }
  return 0;
};
const toMin = (v) => {
  if (typeof v === 'number') return v;
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(v || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
};

export function defineCity(s) {
  if (!s || !s.id) { warn('a city needs an id'); return null; }
  const o = CITIES[s.id] || {};
  const c = {
    ...o,
    id: s.id,
    name: s.name || o.name || s.id,
    airport: s.airport || o.airport || `${s.name || s.id} Airport`,
    iata: String(s.iata || o.iata || s.id.slice(0, 3)).toUpperCase(),
    icao: String(s.icao || o.icao || '----').toUpperCase(),
    country: s.country || o.country || '—',
    cont: s.cont || s.continent || o.cont || 'Europe',
    hero: s.hero || o.hero || 'assets/p_generic.webp',
    lat: num(s.lat, o.lat, 0),
    lon: num(s.lon, o.lon, 0),
    elev: num(s.elev, o.elev, 0),
    tz: num(s.tz, o.tz, 0),
    costIndex: num(s.costIndex, o.costIndex, 1),
    demand: { ...o.demand, ...s.demand },
  };
  if (!CITIES[c.id]) CIDS.push(c.id);
  CITIES[c.id] = c;
  if (s.airline) {
    AIRLINE[c.id] = Array.isArray(s.airline)
      ? s.airline
      : [String(s.airline).slice(0, 2).toUpperCase(), String(s.airline)];
  } else if (!AIRLINE[c.id]) {
    AIRLINE[c.id] = [c.iata.slice(0, 2), `${c.name} Air`];
  }
  if (s.note) NOTE_TEXT[c.id] = s.note;
  else if (!NOTE_TEXT[c.id]) NOTE_TEXT[c.id] = 'No file on this hub yet. Trade here to open it.';
  (s.products || []).forEach((p) => defineProduct({ home: c.id, ...p }));
  (s.flights || []).forEach((f) => defineFlight({ from: c.id, ...f }));
  return c;
}

export function defineProduct(s) {
  if (!s || !s.id) { warn('a product needs an id'); return null; }
  if (!CITIES[s.home]) { warn(`product ${s.id} names an unknown home hub "${s.home}"`); return null; }
  const o = PRODUCTS[s.id] || {};
  const category = s.category || o.category || 'Goods';
  const p = {
    ...o,
    id: s.id,
    home: s.home,
    name: s.name || o.name || s.id,
    category,
    icon: s.icon || o.icon || CAT_ICON[category] || 'assets/p_generic.webp',
    w: num(s.w, s.weight, o.w, 1),
    base: num(s.base, s.price, o.base, 100),
    volatility: num(s.volatility, o.volatility, 1),
    demandIn: { ...o.demandIn, ...s.demandIn },
  };
  if (!PRODUCTS[p.id]) PRODUCT_IDS.push(p.id);
  PRODUCTS[p.id] = p;
  return p;
}

export function defineFlight(s) {
  if (!s || !CITIES[s.from] || !CITIES[s.to]) { warn('a flight needs valid from/to hub ids'); return null; }
  if (s.from === s.to) { warn(`flight from ${s.from} cannot land in itself`); return null; }
  const f = {
    from: s.from,
    to: s.to,
    depMin: toMin(s.dep) % 1440,
    no: s.no || null,
    airline: s.airline || null,
    mins: s.mins != null && s.mins !== '' ? Number(s.mins) : null,
    econ: s.econ != null && s.econ !== '' ? Number(s.econ) : null,
    biz: s.biz != null && s.biz !== '' ? Number(s.biz) : null,
    stops: s.stops || 'Nonstop',
    aircraft: s.aircraft || null,
    replace: !!s.replace,
  };
  FLIGHTS.push(f);
  return f;
}

export function removeCity(id) {
  if (!CITIES[id]) return false;
  delete CITIES[id];
  CIDS.splice(CIDS.indexOf(id), 1);
  PRODUCT_IDS.filter((p) => PRODUCTS[p].home === id).forEach((p) => {
    delete PRODUCTS[p];
    PRODUCT_IDS.splice(PRODUCT_IDS.indexOf(p), 1);
  });
  for (let i = FLIGHTS.length - 1; i >= 0; i -= 1) {
    if (FLIGHTS[i].from === id || FLIGHTS[i].to === id) FLIGHTS.splice(i, 1);
  }
  return true;
}

/* --- Seed hubs (positional shorthand kept for brevity) --------- */

const C = (id, name, airport, iata, icao, country, cont, hero, lat, lon, elev, tz) =>
  defineCity({ id, name, airport, iata, icao, country, cont, hero, lat, lon, elev, tz });

const CITY_SEED = {
  istanbul: C('istanbul', 'Istanbul', 'Istanbul Airport', 'IST', 'LTFM', 'Türkiye', 'Europe', 'assets/city_istanbul.webp', 41.28, 28.75, 325, 3),
  dubai: C('dubai', 'Dubai', 'Dubai International', 'DXB', 'OMDB', 'United Arab Emirates', 'Asia', 'assets/city_dubai.webp', 25.25, 55.37, 62, 4),
  london: C('london', 'London', 'London Heathrow', 'LHR', 'EGLL', 'United Kingdom', 'Europe', 'assets/city_london.webp', 51.47, -0.45, 83, 1),
  paris: C('paris', 'Paris', 'Paris Charles de Gaulle', 'CDG', 'LFPG', 'France', 'Europe', 'assets/city_paris.webp', 49.01, 2.55, 392, 2),
  amsterdam: C('amsterdam', 'Amsterdam', 'Amsterdam Schiphol', 'AMS', 'EHAM', 'Netherlands', 'Europe', 'assets/city_amsterdam.webp', 52.31, 4.77, -11, 2),
  frankfurt: C('frankfurt', 'Frankfurt', 'Frankfurt Airport', 'FRA', 'EDDF', 'Germany', 'Europe', 'assets/city_frankfurt.webp', 50.04, 8.56, 364, 2),
  beijing: C('beijing', 'Beijing', 'Beijing Capital International', 'PEK', 'ZBAA', 'China', 'Asia', 'assets/city_beijing.webp', 40.08, 116.6, 116, 8),
  shanghai: C('shanghai', 'Shanghai', 'Shanghai Pudong International', 'PVG', 'ZSPD', 'China', 'Asia', 'assets/city_shanghai.webp', 31.14, 121.81, 13, 8),
  hong_kong: C('hong_kong', 'Hong Kong', 'Hong Kong International', 'HKG', 'VHHH', 'Hong Kong', 'Asia', 'assets/city_hongkong.webp', 22.31, 113.92, 28, 8),
  tokyo: C('tokyo', 'Tokyo', 'Tokyo Haneda', 'HND', 'RJTT', 'Japan', 'Asia', 'assets/city_tokyo.webp', 35.55, 139.78, 21, 9),
  singapore: C('singapore', 'Singapore', 'Singapore Changi', 'SIN', 'WSSS', 'Singapore', 'Asia', 'assets/city_singapore.webp', 1.36, 103.99, 22, 8),
  bangkok: C('bangkok', 'Bangkok', 'Bangkok Suvarnabhumi', 'BKK', 'VTBS', 'Thailand', 'Asia', 'assets/city_bangkok.webp', 13.69, 100.75, 5, 7),
};

Object.values(CITY_SEED).forEach(defineCity);

/* Local price levels and category appetites — read by priceAt(). */
const CITY_TUNING = {
  istanbul: { costIndex: 0.9, demand: { Electronics: 1.2, Tea: 1.12 } },
  dubai: { costIndex: 1.06, demand: { Crafts: 1.18, Cosmetics: 1.12 } },
  london: { costIndex: 1.14, demand: { Tea: 0.86, Crafts: 1.1 } },
  paris: { costIndex: 1.12, demand: { Cosmetics: 0.88, Confectionery: 1.16 } },
  amsterdam: { costIndex: 1.05, demand: { Spices: 1.14 } },
  frankfurt: { costIndex: 1.09, demand: { Textiles: 1.12 } },
  beijing: { costIndex: 0.92, demand: { Cosmetics: 1.22, Food: 1.1 } },
  shanghai: { costIndex: 0.95, demand: { Machinery: 1.16 } },
  hong_kong: { costIndex: 1.08, demand: { Toys: 0.85, Crafts: 1.14 } },
  tokyo: { costIndex: 1.11, demand: { Electronics: 0.85, Textiles: 1.2 } },
  singapore: { costIndex: 1.04, demand: { Spices: 1.15 } },
  bangkok: { costIndex: 0.86, demand: { Machinery: 1.24, Electronics: 1.18 } },
};
Object.keys(CITY_TUNING).forEach((id) => defineCity({ id, ...CITY_TUNING[id] }));

const PR = (id, home, name, category, icon, w, base) =>
  defineProduct({ id, home, name, category, icon, w, base });

const PRODUCT_SEED = {
  ist_lokum: PR('ist_lokum', 'istanbul', 'Turkish Delight', 'Confectionery', 'assets/p_ist_lokum.webp', 2.4, 64),
  ist_ceramic: PR('ist_ceramic', 'istanbul', 'İznik Ceramics', 'Crafts', 'assets/p_ist_ceramic.webp', 5.8, 310),
  ist_copper: PR('ist_copper', 'istanbul', 'Hand-beaten Copper', 'Crafts', 'assets/p_ist_copper.webp', 9.2, 186),
  ist_textile: PR('ist_textile', 'istanbul', 'Bursa Textiles', 'Textiles', 'assets/p_ist_textile.webp', 12.5, 242),
  dxb_gold: PR('dxb_gold', 'dubai', 'Gold Jewellery Proxy', 'Crafts', 'assets/p_dxb_gold.webp', 0.28, 5800),
  dxb_spice: PR('dxb_spice', 'dubai', 'Souk Saffron Lot', 'Spices', 'assets/p_dxb_spice.webp', 0.4, 920),
  dxb_fabric: PR('dxb_fabric', 'dubai', 'Re-export Fabric Lot', 'Textiles', 'assets/p_dxb_fabric.webp', 6.5, 500),
  dxb_oil: PR('dxb_oil', 'dubai', 'Refined Oil Contract', 'Energy', 'assets/p_cat_energy.webp', 1.0, 1100),
  dxb_avionics: PR('dxb_avionics', 'dubai', 'Avionics Modules', 'Electronics', 'assets/p_cat_electronics.webp', 0.75, 5000),
  lhr_tea: PR('lhr_tea', 'london', 'Blended Tea Chest', 'Tea', 'assets/p_lhr_tea.webp', 3.1, 128),
  lhr_wool: PR('lhr_wool', 'london', 'Highland Wool Bolt', 'Textiles', 'assets/p_lhr_wool.webp', 7.8, 210),
  cdg_perfume: PR('cdg_perfume', 'paris', 'Grasse Perfume', 'Cosmetics', 'assets/p_cdg_perfume.webp', 1.1, 410),
  cdg_chocolate: PR('cdg_chocolate', 'paris', 'Maison Chocolates', 'Confectionery', 'assets/p_cdg_chocolate.webp', 2.2, 185),
  cdg_cosmetics: PR('cdg_cosmetics', 'paris', 'Atelier Skincare', 'Cosmetics', 'assets/p_cdg_cosmetics.webp', 1.6, 340),
  ams_cheese: PR('ams_cheese', 'amsterdam', 'Aged Gouda Wheel', 'Food', 'assets/p_ams_cheese.webp', 8.4, 96),
  ams_flower: PR('ams_flower', 'amsterdam', 'Cut Tulip Crate', 'Daily goods', 'assets/p_ams_flower.webp', 4.6, 74),
  fra_machinery: PR('fra_machinery', 'frankfurt', 'Precision Machinery', 'Machinery', 'assets/p_fra_machinery.webp', 14.0, 880),
  fra_leather: PR('fra_leather', 'frankfurt', 'Tanned Leather Roll', 'Crafts', 'assets/p_fra_leather.webp', 5.4, 265),
  pek_bronze: PR('pek_bronze', 'beijing', 'Bronze Censer', 'Crafts', 'assets/p_pek_bronze.webp', 6.2, 465),
  pek_herb: PR('pek_herb', 'beijing', 'Medicinal Herb Bundle', 'Food', 'assets/p_pek_herb.webp', 2.8, 158),
  pvg_silk: PR('pvg_silk', 'shanghai', 'Suzhou Silk Bolt', 'Textiles', 'assets/p_pvg_silk.webp', 4.2, 355),
  pvg_tea: PR('pvg_tea', 'shanghai', 'Longjing Tea Tin', 'Tea', 'assets/p_pvg_tea.webp', 1.4, 196),
  pvg_embroid: PR('pvg_embroid', 'shanghai', 'Su Embroidery Panel', 'Crafts', 'assets/p_pvg_embroidery.webp', 2.0, 520),
  hkg_jewelry: PR('hkg_jewelry', 'hong_kong', 'Bonded Jewellery Lot', 'Crafts', 'assets/p_hkg_jewelry.webp', 0.35, 4200),
  hkg_toys: PR('hkg_toys', 'hong_kong', 'Licensed Toy Pallet', 'Toys', 'assets/p_cat_toys.webp', 9.5, 340),
  hnd_elec: PR('hnd_elec', 'tokyo', 'Precision Sensors', 'Electronics', 'assets/p_hnd_electronics.webp', 0.9, 780),
  hnd_sake: PR('hnd_sake', 'tokyo', 'Junmai Sake Case', 'Food', 'assets/p_hnd_sake.webp', 11.2, 290),
  sin_orchid: PR('sin_orchid', 'singapore', 'Orchid Extract', 'Cosmetics', 'assets/p_sin_orchid.webp', 1.3, 430),
  sin_perfume: PR('sin_perfume', 'singapore', 'Duty-free Perfume', 'Cosmetics', 'assets/p_sin_perfume.webp', 0.9, 395),
  bkk_spice: PR('bkk_spice', 'bangkok', 'Thai Spice Crate', 'Spices', 'assets/p_bkk_spice.webp', 3.6, 142),
  bkk_lacquer: PR('bkk_lacquer', 'bangkok', 'Lacquerware Set', 'Crafts', 'assets/p_bkk_lacquer.webp', 4.8, 228),
  bkk_silk: PR('bkk_silk', 'bangkok', 'Thai Silk Bolt', 'Textiles', 'assets/p_bkk_silk.webp', 3.4, 268),
};

Object.values(PRODUCT_SEED).forEach(defineProduct);

/* Volatility and standing orders — optional per-product tuning. */
[
  { id: 'dxb_gold', home: 'dubai', volatility: 1.45, demandIn: { hong_kong: 1.2, tokyo: 1.15 } },
  { id: 'hkg_jewelry', home: 'hong_kong', volatility: 1.35, demandIn: { dubai: 1.22 } },
  { id: 'fra_machinery', home: 'frankfurt', volatility: 0.8, demandIn: { bangkok: 1.3, shanghai: 1.2 } },
  { id: 'ams_flower', home: 'amsterdam', volatility: 1.5, demandIn: { london: 1.18, paris: 1.14 } },
  { id: 'hnd_elec', home: 'tokyo', volatility: 0.9, demandIn: { istanbul: 1.25, bangkok: 1.2 } },
].forEach(defineProduct);

const AIRLINE_SEED = {
  istanbul: ['TK', 'Turkish Airlines'],
  dubai: ['EK', 'Emirates'],
  london: ['BA', 'British Airways'],
  paris: ['AF', 'Air France'],
  amsterdam: ['KL', 'KLM'],
  frankfurt: ['LH', 'Lufthansa'],
  beijing: ['CA', 'Air China'],
  shanghai: ['MU', 'China Eastern'],
  hong_kong: ['CX', 'Cathay Pacific'],
  tokyo: ['NH', 'All Nippon'],
  singapore: ['SQ', 'Singapore Airlines'],
  bangkok: ['TG', 'Thai Airways'],
};
Object.keys(AIRLINE_SEED).forEach((id) => defineCity({ id, airline: AIRLINE_SEED[id] }));

/* Named services layered on top of the generated boards. */
[
  { from: 'dubai', to: 'london', dep: '02:35', no: 'EK 001', airline: 'Emirates', aircraft: 'A380-800', biz: 2380 },
  { from: 'istanbul', to: 'tokyo', dep: '20:05', no: 'TK 198', airline: 'Turkish Airlines', aircraft: '787-9' },
  { from: 'singapore', to: 'london', dep: '23:55', no: 'SQ 322', airline: 'Singapore Airlines', aircraft: 'A350-900', replace: true },
  { from: 'hong_kong', to: 'paris', dep: '23:40', no: 'CX 279', airline: 'Cathay Pacific', aircraft: '777-300ER' },
  { from: 'amsterdam', to: 'istanbul', dep: '05:50', no: 'KL 1613', airline: 'KLM', aircraft: '737-800', econ: 180 },
].forEach(defineFlight);

export const ADDONS = [
  { k: '', label: 'None', price: 0 },
  { k: 'light', label: '+10kg', price: 40 },
  { k: 'standard', label: '+20kg', price: 70 },
  { k: 'heavy', label: '+50kg', price: 150 },
];

export const ACHIEVEMENTS = [
  { id: 'first_city', icon: 'assets/ach_first_city.webp', name: 'Wheels Down', desc: 'Reach a second city.', goal: 2, stat: 'cities' },
  { id: 'first_flight', icon: 'assets/ach_first_flight.webp', name: 'First Boarding Pass', desc: 'Complete one flight.', goal: 1, stat: 'legs' },
  { id: 'first_profit', icon: 'assets/ach_first_profit.webp', name: 'In The Black', desc: 'Turn a profit on one sale.', goal: 1, stat: 'profitable' },
  { id: 'hot_streak', icon: 'assets/ach_hot_streak.webp', name: 'Hot Streak', desc: 'Five profitable sales in a run.', goal: 5, stat: 'profitable' },
  { id: 'europe', icon: 'assets/ach_europe.webp', name: 'Old Continent', desc: 'Visit five European hubs.', goal: 5, stat: 'europe' },
  { id: 'asia', icon: 'assets/ach_asia.webp', name: 'Eastbound', desc: 'Visit five Asian hubs.', goal: 5, stat: 'asia' },
  { id: 'cities_10', icon: 'assets/ach_cities_10.webp', name: 'Frequent Flyer', desc: 'Visit ten hub cities.', goal: 10, stat: 'cities' },
  { id: 'countries_5', icon: 'assets/ic_city.webp', name: 'Passport Stamps', desc: 'Trade in five countries.', goal: 5, stat: 'countries' },
  { id: 'business_10', icon: 'assets/ach_business_10.webp', name: 'Up Front', desc: 'Fly ten business legs.', goal: 10, stat: 'bizLegs' },
  { id: 'cargo_20', icon: 'assets/ach_cargo_20.webp', name: 'Heavy Lifter', desc: 'Move 20 cargo shipments.', goal: 20, stat: 'cargoLots' },
  { id: 'wealth_100k', icon: 'assets/ach_wealth_100k.webp', name: 'Six Figures', desc: 'Hold $100,000 in cash.', goal: 100000, stat: 'cash' },
  { id: 'legendary', icon: 'assets/ach_legendary.webp', name: 'Legendary Trader', desc: 'Bank $1,000,000 in profit.', goal: 1000000, stat: 'profit' },
];

export const SOURCES = [
  { name: 'OurAirports', license: 'Public domain', use: 'Airport identifiers, ICAO/IATA codes, coordinates and elevation for the 12 playable hubs.' },
  { name: 'OpenFlights', license: 'ODbL', use: 'Airline names and route adjacency used to seed the departure boards.' },
  { name: 'Natural Earth', license: 'Public domain', use: 'Coastlines and landmass raster behind the globe.' },
  { name: 'IANA Time Zone Database', license: 'Public domain', use: 'UTC offsets driving each city local clock.' },
];

const NOTE_SEED = {
  istanbul: 'Straddles two continents and prices like it. Crafts leave cheap; anything electronic arrives dear.',
  dubai: 'A re-export machine. Gold and saffron move at volume, and the souk pays up for finished crafts.',
  london: 'Tea and wool are the honest trades. Fares out are steep — earn the margin before you book.',
  paris: 'Perfume and cosmetics carry almost no weight, which makes them the ideal carry-on cargo.',
  amsterdam: 'Flowers and cheese are cheap and heavy. Only worth it on a short hop with cargo space.',
  frankfurt: 'Machinery is the heaviest thing you can profitably carry. Buy the cargo block first.',
  beijing: 'Bronze and herbs price low locally and travel well westward.',
  shanghai: 'Silk and embroidery out of Suzhou — light, valuable, and in demand almost everywhere.',
  hong_kong: 'Bonded jewellery at near-zero weight. The single best value-per-kilo in the network.',
  tokyo: 'Sensors are tiny and precious; sake is bulky and sentimental. Pick one.',
  singapore: 'Duty-free by design. Buy scent here, sell it where duty is not free.',
  bangkok: 'Spice, silk and lacquer at low entry prices — the best place to start a thin wallet.',
};
Object.keys(NOTE_SEED).forEach((id) => defineCity({ id, note: NOTE_SEED[id] }));

export const STARTING_CASH = 6944;
export const STARTING_CITY = 'istanbul';
export const DEFAULT_BAG_LIMIT = 23;
export const DEFAULT_CARGO_CAP = 50;

export const TABS = [
  { k: 'globe', label: 'Globe', icon: 'assets/ic_city.webp' },
  { k: 'market', label: 'Market', icon: 'assets/ic_market.webp' },
  { k: 'flights', label: 'Flights', icon: 'assets/ic_flight.webp' },
  { k: 'bags', label: 'Bags', icon: 'assets/ic_inventory.webp' },
  { k: 'more', label: 'More', icon: 'assets/ic_log.webp' },
];

export const CUTSCENE_ART = [
  { phase: 'Gate closed', title: 'Boarding · Takeoff', art: 'assets/anim_flight_takeoff.webp', pct: '22%' },
  { phase: 'Cruising', title: '34,000 ft', art: 'assets/anim_flight_cruise.webp', pct: '62%' },
  { phase: 'Approach', title: 'Landing', art: 'assets/anim_flight_land.webp', pct: '100%' },
];
