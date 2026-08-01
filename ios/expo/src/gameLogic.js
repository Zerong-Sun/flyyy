import { AIRLINE, CIDS, CITIES, FLIGHTS, PRODUCTS, PRODUCT_IDS } from './gameData.js';

const FACTORS = [1.58, 1.41, 1.24, 1.08, 0.95, 0.82];

export function hsh(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = (h * 16777619) >>> 0;
  }
  return h;
}

export function gcKm(a, b) {
  const R = 6371;
  const r = Math.PI / 180;
  const dLa = (b.lat - a.lat) * r;
  const dLo = (b.lon - a.lon) * r;
  const x = Math.sin(dLa / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLo / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.min(1, Math.sqrt(x))));
}

export const money = (n) => `$${Math.round(n).toLocaleString('en-US')}`;
export const pad = (n) => String(n).padStart(2, '0');
export const hhmm = (m) => {
  const mins = ((m % 1440) + 1440) % 1440;
  return `${pad(Math.floor(mins / 60))}:${pad(mins % 60)}`;
};

/** 24-hour or 12-hour wall clock, per the player's setting. */
export function fmtClock(m, use24 = true) {
  const mins = ((Math.round(m) % 1440) + 1440) % 1440;
  const h = Math.floor(mins / 60);
  const mm = pad(mins % 60);
  if (use24) return `${pad(h)}:${mm}`;
  const suffix = h < 12 ? 'AM' : 'PM';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${mm} ${suffix}`;
}

export function hm(m) {
  const h = Math.floor(m / 60);
  return h > 0 ? `${h}h ${pad(Math.round(m % 60))}m` : `${Math.round(m)}m`;
}

const one = (v) => (typeof v === 'number' && !Number.isNaN(v) ? v : 1);

/** Local price level × category appetite × standing order. */
export function demandFor(pid, city) {
  const p = PRODUCTS[pid];
  const B = CITIES[city];
  if (!p || !B) return 1;
  return one(B.demand && B.demand[p.category]) * one(p.demandIn && p.demandIn[city]) * one(B.costIndex);
}

export function factorFor(pid, city) {
  const p = PRODUCTS[pid];
  const dem = demandFor(pid, city);
  // Home is always the cheap side: local cost of living only, capped at par.
  if (p.home === city) return Math.round(Math.min(1, 0.92 * one(CITIES[city].costIndex)) * 100) / 100;
  const far = Math.min(1, gcKm(CITIES[p.home], CITIES[city]) / 9000);
  const base = FACTORS[hsh(`${pid}|${city}`) % FACTORS.length] + far * 0.22;
  const spread = 1 + (base - 1) * one(p.volatility);
  return Math.round(Math.max(0.35, spread * dem) * 100) / 100;
}

export function priceAt(pid, city) {
  return Math.round(PRODUCTS[pid].base * factorFor(pid, city));
}

/** One generated departure; idx spaces repeat services across the day. */
function legFor(cid, k, idx) {
  const A = CITIES[cid];
  const B = CITIES[k];
  const km = gcKm(A, B);
  const h = hsh(`${cid}>${k}#${idx}`);
  const mins = Math.round(km / 13.5 + 35);
  const code = AIRLINE[cid] || ['XX', 'Charter'];
  const econ = Math.round(((80 + km * 0.098) * (one(A.costIndex) + one(B.costIndex))) / 2 / 2) * 2;
  return {
    toId: k,
    km,
    mins,
    depMin: (6 * 60 + (h % 15) * 54 + idx * 555) % 1440,
    no: `${code[0]} ${100 + (h % 899)}`,
    airline: code[1],
    econ,
    biz: Math.round((econ * 3.1) / 10) * 10,
    dur: `${Math.floor(mins / 60)}h ${pad(mins % 60)}m`,
    stops: 'Nonstop',
    aircraft: null,
  };
}

export function routesFrom(cid) {
  if (!CITIES[cid]) return [];
  const custom = FLIGHTS.filter((f) => f.from === cid);
  const replaced = {};
  custom.forEach((f) => { if (f.replace) replaced[f.to] = true; });

  const out = [];
  CIDS.filter((k) => k !== cid && !replaced[k]).forEach((k) => {
    const daily = gcKm(CITIES[cid], CITIES[k]) < 4200 ? 2 : 1;
    for (let i = 0; i < daily; i += 1) out.push(legFor(cid, k, i));
  });

  custom.forEach((f) => {
    const g = legFor(cid, f.to, 9);
    const mins = f.mins || g.mins;
    const econ = f.econ || g.econ;
    out.push({
      ...g,
      depMin: f.depMin,
      mins,
      no: f.no || g.no,
      airline: f.airline || g.airline,
      econ,
      biz: f.biz || Math.round((econ * 3.1) / 10) * 10,
      dur: `${Math.floor(mins / 60)}h ${pad(mins % 60)}m`,
      stops: f.stops,
      aircraft: f.aircraft,
    });
  });

  return out.sort((a, b) => a.depMin - b.depMin);
}

/** Unique destinations served from a hub (routes may repeat a city). */
export function destinationsFrom(cid) {
  return routesFrom(cid).reduce((a, r) => (a.indexOf(r.toId) < 0 ? a.concat([r.toId]) : a), []);
}

export function bagUsed(inv) {
  return inv.filter((i) => i.slot === 'bag').reduce((a, i) => a + i.w * i.n, 0);
}

export function cargoUsed(inv) {
  return inv.filter((i) => i.slot === 'cargo').reduce((a, i) => a + i.w * i.n, 0);
}

export function locals(cityId) {
  return PRODUCT_IDS.filter((id) => PRODUCTS[id].home === cityId);
}

export function imports(cityId) {
  return PRODUCT_IDS.filter((id) => PRODUCTS[id].home !== cityId)
    .sort((a, b) => hsh(a + cityId) - hsh(b + cityId))
    .slice(0, 6);
}

export function sellData(inv, cityId) {
  let gross = 0;
  let cost = 0;
  const rows = inv.map((i) => {
    const u = priceAt(i.id, cityId);
    const g = u * i.n;
    const c = i.cost * i.n;
    gross += g;
    cost += c;
    return {
      icon: i.icon,
      name: i.name,
      meta: `${i.n} × ${money(u)} · ${(i.w * i.n).toFixed(1)} kg`,
      gross: money(g),
      delta: `${g - c >= 0 ? '+' : '−'}${money(Math.abs(g - c))}`,
      color: g - c >= 0 ? '#3CB8A4' : '#E05555',
    };
  });
  return { rows, gross, net: gross - cost };
}

export function intel(pid, cityId, destId) {
  const here = priceAt(pid, cityId);
  if (destId) {
    const t = priceAt(pid, destId);
    const pct = Math.round((t / here - 1) * 100);
    const cn = CITIES[destId].name;
    if (pct >= 25) return { text: `+${pct}% in ${cn}`, kind: 'hot' };
    if (pct >= 5) return { text: `${cn}: +${pct}%`, kind: 'ok' };
    if (pct > -5) return { text: `${cn}: ${pct >= 0 ? '+' : ''}${pct}%`, kind: 'ok' };
    return { text: `${cn}: ${pct}%`, kind: 'cold' };
  }
  let best = null;
  destinationsFrom(cityId).forEach((toId) => {
    const t = priceAt(pid, toId);
    if (!best || t > best.p) best = { p: t, c: CITIES[toId].name };
  });
  if (best && best.p > here * 1.2) return { text: `Best: ${best.c} ${money(best.p)}`, kind: 'best' };
  return { text: '', kind: '' };
}

export function tagColor(kind) {
  if (kind === 'hot') return '#3CB8A4';
  if (kind === 'best') return '#E89A3C';
  if (kind === 'cold') return '#E05555';
  return '#A8B8C8';
}

export function computeStats(state) {
  const countries = {};
  let europe = 0;
  let asia = 0;
  state.visited.forEach((v) => {
    const c = CITIES[v];
    countries[c.country] = 1;
    if (c.cont === 'Europe') europe += 1;
    else if (c.cont === 'Asia') asia += 1;
  });
  return {
    cities: state.visited.length,
    legs: state.legs,
    profitable: state.profitable,
    europe,
    asia,
    countries: Object.keys(countries).length,
    bizLegs: state.bizLegs,
    cargoLots: state.cargoLots,
    cash: state.cash,
    profit: state.profit,
  };
}

export function utcMinutes(gameMin) {
  return 9 * 60 + 40 + gameMin;
}

export function cityMinutes(gameMin, cityId) {
  return utcMinutes(gameMin) + (CITIES[cityId].tz - 3) * 60;
}

export function clockLabel(gameMin, use24 = true) {
  const m = utcMinutes(gameMin);
  return `Mar ${12 + Math.floor(m / 1440)} · ${fmtClock(m, use24)}`;
}

/** Minutes until depMin on the city's local clock (wraps past midnight). */
export function waitUntilDep(gameMin, cityId, depMin) {
  const localNow = ((cityMinutes(gameMin, cityId) % 1440) + 1440) % 1440;
  let wait = depMin - localNow;
  if (wait <= 0) wait += 1440;
  return wait;
}

/** Weighted-average unit cost when stacking inventory. */
export function mergeInvCost(prevCost, prevN, unit, n) {
  const totalN = prevN + n;
  if (totalN <= 0) return 0;
  return (prevCost * prevN + unit * n) / totalN;
}

/**
 * Stable fake price history (3–5 points) ending at current local price.
 * Not real market data — for sparkline UI only.
 */
export function priceSparkline(pid, cityId, points = 5) {
  const now = priceAt(pid, cityId);
  const n = Math.max(3, Math.min(5, points));
  const out = [];
  for (let i = 0; i < n; i += 1) {
    const wobble = ((hsh(`${pid}|${cityId}|hist|${i}`) % 21) - 10) / 100;
    const t = i / (n - 1);
    out.push(Math.max(1, Math.round(now * (1 + wobble * (1 - t)))));
  }
  out[n - 1] = now;
  return out;
}

/** Sort product ids by profit uplift to dest (desc). */
export function sortByDestProfit(ids, fromCity, destId) {
  if (!destId) return ids.slice();
  return ids.slice().sort((a, b) => {
    const da = priceAt(a, destId) - priceAt(a, fromCity);
    const db = priceAt(b, destId) - priceAt(b, fromCity);
    return db - da;
  });
}
