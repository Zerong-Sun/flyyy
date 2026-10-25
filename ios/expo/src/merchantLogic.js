/** Pure merchant transactions; the hook applies each returned state exactly once. */
import { WORLD_CONTENT } from './worldContent.js';
import { PRODUCTS, CITIES, DEFAULT_BAG_LIMIT } from './gameData.js';
import { marketPriceAt, locals, routesFrom, waitUntilDep, sellData } from './gameLogic.js';
import { activeEvents, eventHash, quoteFlightForEvents } from './eventLogic.js';
export const MERCHANT_RULES = WORLD_CONTENT.merchant_rules;
export const JOURNEY_EVENTS = WORLD_CONTENT.journey_events;
const R = MERCHANT_RULES;
const clone = (v) => JSON.parse(JSON.stringify(v));
export const freshMerchant = () => ({ offers: [], order: null, batch: '', chain: 0, sales: {}, milestones: {}, candidates: [], active: null, flights: 0, seen: [], coupon: null, supply: null, lead: null, deals: {}, notice: '' });
const roll = (s, key) => eventHash(`${s.eventSeed}|merchant|${key}`);
export const merchantText = (s, zh, en) => s.locale === 'zh' ? zh : en;
export const eventText = (s, e, key) => e?.[`${key}_${s.locale === 'zh' ? 'zh' : 'en'}`] || '';
const currentEvents = (s) => activeEvents(s.gameMin, s.eventSeed);
const matches = (s, id, kind) => {
  const a = s.merchant?.active;
  return a?.kind === kind && (a.scope === `product:${id}` || a.scope === `category:${PRODUCTS[id]?.category}`);
};
export function merchantUnit(s, id, city, side = 'buy', events = currentEvents(s)) {
  const buy = marketPriceAt(id, city, 'buy', events) * (matches(s, id, 'buy') ? 1 - R.ability_buy : 1);
  if (side === 'buy') return buy;
  return Math.min(buy * 0.95, marketPriceAt(id, city, 'sell', events) * (matches(s, id, 'sell') ? 1 + R.ability_sell : 1));
}
export function purchaseTotal(s, id, n) {
  const total = merchantUnit(s, id, s.city) * n;
  const coupon = s.merchant?.supply;
  return total - (coupon?.city === s.city && coupon.expires > s.gameMin ? Math.min(100, total * .12) : 0);
}
export function merchantFare(s, base) {
  let fare = base * (s.merchant?.active?.kind === 'fare' ? 1 - R.ability_fare : 1);
  if (s.merchant?.coupon?.expires > s.gameMin) fare -= Math.min(150, fare * .15);
  return fare;
}
export function merchantBaggage(s, price) {
  return price * (s.merchant?.active?.kind === 'cargo' ? 1 - R.ability_cargo : 1);
}
export function expireMerchant(state) {
  if (!state.merchant?.order || state.gameMin < state.merchant.order.deadline) return state;
  const m = clone(state.merchant);
  m.order = null; m.chain = 0;
  m.notice = merchantText(state, '委托到期，货物仍可出售', 'Order expired; goods can still be sold');
  return { ...state, merchant: m };
}
export function refreshOffers(state, force = false) {
  let s = expireMerchant(state);
  const m = clone(s.merchant || freshMerchant());
  const batch = `${s.city}|${Math.floor(s.gameMin / 1440)}|${s.legs}`;
  if (!force && m.batch === batch) return s;
  m.batch = batch; m.offers = [];
  const events = currentEvents(s);
  const ids = locals(s.city);
  const seen = new Set();
  const routes = routesFrom(s.city).map((r) => quoteFlightForEvents(r, s.city, events, s.eventSeed))
    .sort((a, b) => waitUntilDep(s.gameMin, s.city, a.depMin) - waitUntilDep(s.gameMin, s.city, b.depMin));
  for (const route of routes) {
    if (!ids.length || seen.has(route.toId) || route.eventUnavailable) continue;
    seen.add(route.toId);
    const arrival = s.gameMin + waitUntilDep(s.gameMin, s.city, route.depMin) + route.mins;
    const hours = Math.max(R.min_hours, Math.ceil((arrival - s.gameMin) / 60 + 12));
    if (hours > R.max_hours) continue;
    const id = ids[roll(s, batch + route.toId) % ids.length];
    const unit = merchantUnit(s, id, s.city, 'buy', events);
    const n = Math.min(12, Math.floor(DEFAULT_BAG_LIMIT * .5 / PRODUCTS[id].w), Math.floor(Math.max(0, s.cash - merchantFare(s, route.econ)) / unit));
    if (n < 1) continue;
    const boost = m.lead?.city === s.city && m.lead.expires > s.gameMin ? 1.2 : 1;
    m.offers.push({ id: `${batch}|${route.toId}`, source: s.city, city: route.toId, product: id, qty: n, done: 0, deadline: s.gameMin + hours * 60, arrival, bonus: Math.round(Math.max(80, unit * n * R.order_bonus_rate) * boost), advance: 0, stage: 1 });
    if (m.offers.length === R.offer_count) break;
  }
  return { ...s, merchant: m };
}
export function acceptOrder(state, id) {
  const s = expireMerchant(state);
  if (s.merchant?.order) return s;
  const offer = s.merchant?.offers.find((o) => o.id === id && o.deadline > s.gameMin);
  if (!offer) return s;
  return { ...s, merchant: { ...s.merchant, order: clone(offer), offers: [], notice: '' } };
}
export function abandonOrder(s) {
  return { ...s, merchant: { ...s.merchant, order: null, chain: 0, notice: merchantText(s, '已结束委托，已赚收益保留', 'Order ended; previous earnings kept') } };
}
function unlock(s, m, scope, amount, threshold, category = '') {
  const level = Math.floor(amount / threshold);
  if (level <= (m.milestones[scope] || 0)) return;
  m.milestones[scope] = level;
  // Mobile has no perishable-goods simulation: category skills affect actual trade.
  const kinds = scope === 'flights' ? ['fare', 'cargo'] : ['sell', 'buy'];
  const kind = kinds[roll(s, scope + level) % kinds.length];
  const a = { id: `${scope}:${level}`, scope, kind, category };
  m.candidates = [...m.candidates.filter((row) => row.scope !== scope), a].slice(-R.candidate_limit);
}
export function equipAbility(s, id) {
  const a = s.merchant?.candidates.find((c) => c.id === id);
  if (!a) return s;
  return { ...s, merchant: { ...s.merchant, active: { ...a }, candidates: s.merchant.candidates.filter((c) => c.id !== id) } };
}
export function dismissAbility(s, id) {
  return { ...s, merchant: { ...s.merchant, candidates: s.merchant.candidates.filter((c) => c.id !== id) } };
}
export function abilityLabel(s, a) {
  if (!a) return merchantText(s, '尚无专长 · 销售或飞行解锁', 'Specialties unlock through sales or flights');
  const names = { buy: merchantText(s, '采购能手 · 进价 −8%', 'Buyer · buy −8%'), sell: merchantText(s, '议价行家 · 售价 +8%', 'Negotiator · sell +8%'), fare: merchantText(s, '航空常客 · 票价 −10%', 'Frequent flyer · fare −10%'), cargo: merchantText(s, '行李熟客 · 扩容费 −15%', 'Baggage regular · add-ons −15%') };
  const prefix = a.scope.startsWith('product:') ? (PRODUCTS[a.scope.slice(8)]?.name || '') : a.category;
  return `${prefix ? `${prefix} · ` : ''}${names[a.kind] || ''}`;
}
export function merchantArrival(state) {
  const m = clone(state.merchant || freshMerchant());
  m.flights += 1;
  unlock(state, m, 'flights', m.flights, R.flight_milestone);
  return refreshOffers({ ...state, merchant: m });
}
export function saleQuote(s, item, qty, events = currentEvents(s)) {
  const normal = merchantUnit(s, item.id, s.city, 'sell', events);
  const deal = s.merchant?.deals[item.id];
  if (!deal || deal.city !== s.city || deal.expires <= s.gameMin) return normal * qty;
  const covered = Math.min(qty, deal.remaining);
  let price = normal;
  if (deal.kind === 'lock') price = deal.unit;
  if (deal.kind === 'insurance') price = Math.max(normal, deal.unit);
  if (['buyer', 'speculate'].includes(deal.kind)) price *= deal.mult;
  return price * covered + normal * (qty - covered);
}
export function consumeDeal(s, id, qty) {
  const deal = s.merchant?.deals[id];
  if (!deal) return s;
  const m = clone(s.merchant);
  m.deals[id].remaining = Math.max(0, deal.remaining - qty);
  return { ...s, merchant: m };
}
/** Records progress and returns the bonus; caller credits all revenue atomically. */
export function recordMerchantSale(state, id, qty, revenue) {
  let s = consumeDeal(expireMerchant(state), id, qty);
  const m = clone(s.merchant || freshMerchant());
  const category = PRODUCTS[id].category;
  for (const [scope, threshold] of [[`product:${id}`, R.mobile_product_milestone], [`category:${category}`, R.mobile_category_milestone]]) {
    m.sales[scope] = (m.sales[scope] || 0) + revenue;
    unlock(s, m, scope, m.sales[scope], threshold, category);
  }
  let bonus = 0;
  const o = m.order;
  if (o?.city === s.city && o.product === id) {
    o.done = Math.min(o.qty, o.done + qty);
    if (o.done === o.qty) {
      bonus = Math.max(0, o.bonus - o.advance);
      m.chain = o.stage; m.order = null;
      m.notice = merchantText(s, `委托完成 +$${Math.round(bonus)}`, `Order complete +$${Math.round(bonus)}`);
      s = refreshOffers({ ...s, merchant: m }, true);
      s.merchant.offers = s.merchant.offers.map((offer) => o.stage < R.max_chain ? { ...offer, stage: o.stage + 1, bonus: Math.round(offer.bonus * (1 + R.chain_bonus_step * o.stage)) } : offer);
      if (o.stage >= R.max_chain) s.merchant.chain = 0;
      return { state: s, bonus };
    }
  }
  return { state: { ...s, merchant: m }, bonus };
}
export function merchantSellData(s, events = currentEvents(s)) {
  // Consume coverage in the preview copy across cargo / bag stacks of one product.
  let preview = s;
  const base = sellData(s.inv, s.city, s.locale, events);
  base.gross = 0;
  base.rows = base.rows.map((row, i) => {
    const grossValue = saleQuote(preview, s.inv[i], row.qty, events);
    preview = consumeDeal(preview, row.id, row.qty);
    base.gross += grossValue;
    const delta = grossValue - row.costValue;
    return { ...row, grossValue, gross: `$${Math.round(grossValue).toLocaleString()}`, delta: `${delta < 0 ? '−' : '+'}$${Math.round(Math.abs(delta)).toLocaleString()}`, color: delta < 0 ? '#E05555' : '#3CB8A4', meta: `${row.qty} × $${(grossValue / row.qty).toFixed(2)}` };
  });
  base.net = base.gross - base.cost;
  return base;
}
export function journeyEvent(s, ticket) {
  const key = ticket.merchantKey || `${s.legs}|${ticket.no}|${ticket.toId}|${s.gameMin + s.minsToDep}`;
  if (s.merchant?.seen.includes(key)) return null;
  const eligible = JOURNEY_EVENTS.filter((e) => {
    if (['lock', 'speculate', 'insurance', 'buyer'].includes(e.kind) && !s.inv.length) return false;
    if (['extend', 'rush', 'advance'].includes(e.kind) && !s.merchant?.order) return false;
    if (e.kind === 'advance' && s.merchant?.order?.advance > 0) return false;
    return true;
  });
  const ev = eligible[roll(s, key) % eligible.length];
  return ev ? { ...ev, key, city: ticket.toId, arrival: s.gameMin + s.minsToDep + ticket.mins } : null;
}
export function canChooseJourney(s, e) {
  if (!e || s.cash < (R.event_fees[e.kind] || 0)) return false;
  const o = s.merchant?.order;
  if (['extend', 'rush', 'advance'].includes(e.kind) && (!o || o.deadline <= s.gameMin)) return false;
  if (e.kind === 'rush' && o.deadline - s.gameMin < 12 * 60) return false;
  return true;
}
export function resolveJourney(state, e, accept) {
  if (!e || state.merchant?.seen.includes(e.key) || accept && !canChooseJourney(state, e)) return state;
  let s = { ...state, merchant: clone(state.merchant || freshMerchant()) };
  const m = s.merchant;
  m.seen = [...m.seen, e.key].slice(-128);
  if (!accept) return s;
  const fee = R.event_fees[e.kind] || 0;
  if (s.ticket?.tripForecast) s.ticket = { ...s.ticket, tripForecast: { ...s.ticket.tripForecast, journeyCost: (s.ticket.tripForecast.journeyCost || 0) + fee } };
  s.cash -= fee; s.travelExpenses += fee;
  const o = m.order;
  if (e.kind === 'extend') o.deadline += 6 * 60;
  if (e.kind === 'rush') { o.deadline -= 4 * 60; o.bonus *= 1.25; }
  if (e.kind === 'advance') { o.advance = o.bonus * .25; o.bonus *= .75; s.cash += o.advance; s.profit += o.advance; if (s.ticket?.tripForecast) s.ticket.tripForecast.journeyIncome = (s.ticket.tripForecast.journeyIncome || 0) + o.advance; }
  if (e.kind === 'fare') m.coupon = { expires: e.arrival + 72 * 60 };
  if (e.kind === 'supply') m.supply = { city: e.city, expires: e.arrival + 24 * 60 };
  if (e.kind === 'tip') m.lead = { city: e.city, expires: e.arrival + 72 * 60 };
  if (['lock', 'insurance', 'buyer', 'speculate'].includes(e.kind)) {
    const mult = e.kind === 'speculate' ? (roll(s, e.key + 'premium') % 100 < 60 ? 1.25 : .9) : 1.08;
    const lots = {};
    for (const item of s.inv) {
      const prev = lots[item.id] || { qty: 0, cost: 0 };
      lots[item.id] = { qty: prev.qty + item.n, cost: prev.cost + item.cost * item.n };
    }
    for (const [id, lot] of Object.entries(lots)) {
      const unit = e.kind === 'insurance' ? lot.cost / lot.qty * .9 : merchantUnit(s, id, e.city, 'sell') * .95;
      m.deals[id] = { kind: e.kind, city: e.city, unit, mult, remaining: lot.qty, expires: e.arrival + R.event_quote_hours * 60 };
    }
    if (e.kind === 'buyer') s.gameMin += 60;
    if (e.kind === 'speculate') m.notice = merchantText(s, `买家已回价：${mult > 1 ? '+25%' : '−10%'}`, `Buyer quote: ${mult > 1 ? '+25%' : '−10%'}`);
  }
  if (e.kind !== 'speculate') m.notice = eventText(s, e, 'action');
  return s;
}
export function sanitizeMerchant(raw) {
  const m = freshMerchant();
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return m;
  const num = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0;
  const ability = (a) => a && typeof a === 'object' && ['buy', 'sell', 'fare', 'cargo'].includes(a.kind) && typeof a.id === 'string' && typeof a.scope === 'string' && typeof a.category === 'string';
  const order = (o) => o && typeof o === 'object' && typeof o.id === 'string' && CITIES[o.city] && PRODUCTS[o.product] && ['qty', 'done', 'deadline', 'bonus', 'advance', 'stage', 'arrival'].every((k) => num(o[k])) && Number.isInteger(o.qty) && o.qty > 0 && o.done <= o.qty && o.stage >= 1 && o.stage <= R.max_chain;
  for (const key of ['chain', 'flights']) if (num(raw[key])) m[key] = Math.floor(raw[key]);
  for (const key of ['batch', 'notice']) if (typeof raw[key] === 'string') m[key] = raw[key].slice(0, 256);
  for (const key of ['sales', 'milestones']) if (raw[key] && typeof raw[key] === 'object') m[key] = Object.fromEntries(Object.entries(raw[key]).filter(([k, v]) => k !== '__proto__' && num(v)));
  m.active = ability(raw.active) ? clone(raw.active) : null;
  m.candidates = Array.isArray(raw.candidates) ? raw.candidates.filter(ability).slice(-3).map(clone) : [];
  m.offers = Array.isArray(raw.offers) ? raw.offers.filter(order).slice(0, 3).map(clone) : [];
  m.order = order(raw.order) ? clone(raw.order) : null;
  m.seen = Array.isArray(raw.seen) ? raw.seen.filter((k) => typeof k === 'string').slice(-128) : [];
  for (const key of ['coupon', 'supply', 'lead']) if (num(raw[key]?.expires) && (key === 'coupon' || CITIES[raw[key].city])) m[key] = clone(raw[key]);
  if (raw.deals && typeof raw.deals === 'object') for (const [id, d] of Object.entries(raw.deals)) {
    if (PRODUCTS[id] && d && CITIES[d.city] && ['lock', 'insurance', 'buyer', 'speculate'].includes(d.kind) && ['unit', 'mult', 'remaining', 'expires'].every((k) => num(d[k]))) m.deals[id] = clone(d);
  }
  return m;
}
