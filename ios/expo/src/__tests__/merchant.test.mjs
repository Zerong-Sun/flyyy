import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CITIES, PRODUCTS } from '../gameData.js';
import { freshMerchant, refreshOffers, acceptOrder, expireMerchant, recordMerchantSale, equipAbility, merchantArrival, journeyEvent, resolveJourney, canChooseJourney, JOURNEY_EVENTS, saleQuote, consumeDeal, merchantSellData, merchantFare, purchaseTotal, merchantUnit, sanitizeMerchant } from '../merchantLogic.js';
import { migrateSave, hydrateSave, serializeSave } from '../saveGame.js';
const base = () => ({ city: 'istanbul', eventSeed: 'merchant-test', gameMin: 0, legs: 0, cash: 50000, profit: 0, travelExpenses: 0, inv: [], locale: 'zh', merchant: freshMerchant(), minsToDep: 0 });
const orderState = () => {
  let s = refreshOffers(base());
  assert.ok(s.merchant.offers.length > 0);
  s = acceptOrder(s, s.merchant.offers[0].id);
  return s;
};

test('orders use reachable routes, >=24h windows, and do not reroll on reopen', () => {
  const s = refreshOffers(base());
  assert.ok(s.merchant.offers.every((o) => o.deadline >= 1440 && o.arrival < o.deadline && o.city !== s.city));
  assert.equal(refreshOffers(s), s);
  const accepted = acceptOrder(s, s.merchant.offers[0].id);
  assert.equal(acceptOrder(accepted, 'other'), accepted);
});
test('partial delivery pays once, chains three stages, and expiry preserves inventory', () => {
  let s = orderState();
  for (let stage = 1; stage <= 3; stage += 1) {
    const o = s.merchant.order;
    assert.equal(o.stage, stage);
    s = { ...s, city: o.city, inv: [{ id: o.product, n: o.qty, cost: 100, slot: 'bag' }] };
    if (o.qty > 1) {
      const partial = recordMerchantSale(s, o.product, o.qty - 1, 100);
      assert.equal(partial.bonus, 0);
      s = partial.state;
    }
    const done = recordMerchantSale(s, o.product, 1, 100);
    assert.equal(done.bonus, o.bonus);
    assert.equal(done.state.merchant.order, null);
    assert.equal(recordMerchantSale(done.state, o.product, 1, 100).bonus, 0);
    s = done.state;
    assert.ok(s.merchant.offers.length);
    if (stage < 3) s = acceptOrder(s, s.merchant.offers[0].id);
    else assert.equal(s.merchant.offers[0].stage, 1);
  }
  const withOrder = acceptOrder(s, s.merchant.offers[0].id);
  const expired = expireMerchant({ ...withOrder, gameMin: withOrder.merchant.order.deadline });
  assert.equal(expired.merchant.order, null);
  assert.deepEqual(expired.inv, s.inv);
});
test('product and category milestones produce stable replaceable candidates; flights unlock travel skills', () => {
  let s = orderState();
  const id = s.merchant.order.product;
  s = recordMerchantSale(s, id, 1, 4000).state;
  assert.equal(s.merchant.candidates.length, 2);
  const candidate = s.merchant.candidates[0];
  s = equipAbility(s, candidate.id);
  assert.equal(s.merchant.active.id, candidate.id);
  assert.equal(equipAbility(s, candidate.id), s);
  for (let i = 0; i < 5; i++) s = merchantArrival({ ...s, legs: i + 1 });
  const flightSkill = s.merchant.candidates.find((a) => a.scope === 'flights');
  assert.ok(flightSkill);
  s = equipAbility(s, flightSkill.id);
  assert.equal(s.merchant.active.id, flightSkill.id);
  assert.notEqual(s.merchant.active.id, candidate.id);
});
test('all 30 events have real outcomes, affordable guards, and idempotent choices', () => {
  assert.equal(JOURNEY_EVENTS.length, 30);
  assert.equal(new Set(JOURNEY_EVENTS.map((e) => e.id)).size, 30);
  assert.equal(new Set(JOURNEY_EVENTS.map((e) => e.kind)).size, 10);
  for (const ev of JOURNEY_EVENTS) {
    let s = orderState();
    const id = s.merchant.order.product;
    s.inv = [{ ...PRODUCTS[id], id, n: 2, cost: 100, slot: 'bag' }];
    const e = { ...ev, city: s.merchant.order.city, key: `test-${ev.id}`, arrival: 600 };
    assert.ok(canChooseJourney(s, e), ev.id);
    const result = resolveJourney(s, e, true);
    assert.notDeepEqual(result, s);
    assert.ok(result.cash >= 0);
    assert.equal(resolveJourney(result, e, true), result);
    assert.equal(resolveJourney(s, e, false).cash, s.cash);
    if (['speculate', 'insurance', 'extend', 'fare', 'supply', 'tip'].includes(e.kind)) assert.equal(canChooseJourney({ ...s, cash: 0 }, e), false);
  }
});
test('journey draws survive reload and exclude unusable stock/order events', () => {
  const s = base();
  const ticket = { no: 'TEST1', toId: 'dubai', mins: 100, merchantKey: 'stable-flight' };
  const e = journeyEvent(s, ticket);
  assert.deepEqual(journeyEvent({ ...s, merchant: sanitizeMerchant(s.merchant) }, ticket), e);
  assert.ok(['fare', 'supply', 'tip'].includes(e.kind));
  assert.equal(journeyEvent(resolveJourney(s, e, false), ticket), null);
});
test('locked coverage is shared across stacks and consumed by partial sales/discard', () => {
  let s = orderState();
  const id = s.merchant.order.product;
  s = { ...s, city: s.merchant.order.city, inv: [{ id, n: 2, cost: 20, w: 1, slot: 'bag' }, { id, n: 2, cost: 20, w: 1, slot: 'cargo' }] };
  s.merchant.deals[id] = { kind: 'lock', unit: 123, mult: 1, city: s.city, expires: 100, remaining: 2 };
  const normal = merchantUnit(s, id, s.city, 'sell');
  assert.equal(merchantSellData(s).gross, 246 + normal * 2);
  assert.equal(saleQuote(s, s.inv[0], 1), 123);
  s = consumeDeal(s, id, 1);
  assert.equal(saleQuote(s, s.inv[0], 2), 123 + normal);
  assert.equal(saleQuote({ ...s, gameMin: 100 }, s.inv[0], 2), normal * 2);
});
test('bonuses and advances settle only once; discount previews respect caps', () => {
  let s = orderState();
  const o = s.merchant.order;
  const bonus = o.bonus;
  const e = { ...JOURNEY_EVENTS.find((row) => row.kind === 'advance'), key: 'advance', arrival: 1, city: o.city };
  s = resolveJourney(s, e, true);
  assert.equal(s.cash - 50000, bonus * .25);
  const result = recordMerchantSale({ ...s, city: o.city }, o.product, o.qty, 100);
  assert.equal(result.bonus, bonus * .5);
  s.merchant.coupon = { expires: 100 };
  assert.equal(merchantFare(s, 2000), 1850);
  const id = o.product;
  s.merchant.supply = { city: s.city, expires: 100 };
  assert.equal(purchaseTotal(s, id, 100), merchantUnit(s, id, s.city) * 100 - Math.min(100, merchantUnit(s, id, s.city) * 12));
});
test('merchant save migration and malformed fields are safe', () => {
  const legacy = migrateSave({ saveVersion: 4 });
  assert.deepEqual(legacy.data.merchant, freshMerchant());
  const s = orderState();
  assert.deepEqual(sanitizeMerchant(JSON.parse(JSON.stringify(s.merchant))), s.merchant);
  const bad = sanitizeMerchant({ order: { qty: 'bad' }, sales: { x: -1 }, candidates: [null], deals: { unknown: {} } });
  assert.deepEqual(bad, freshMerchant());
});
