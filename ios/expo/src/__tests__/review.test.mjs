import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { CITIES, STARTING_CITY, DEFAULT_BAG_LIMIT, MOBILE_BALANCE } from '../gameData.js';
import { SAVE_KEY, SAVE_VERSION, serializeSave, loadSavePayload, migrateSave } from '../saveGame.js';
import { BACKUP_KEY, readSave, writeSave, resetSave } from '../saveStorage.js';
import { createStateStore } from '../stateStore.js';
import { refundTravel, travelCharge, saleCredit } from '../accounting.js';
import { routeOpportunities } from '../gameLogic.js';

const base = { cash: 6944, city: STARTING_CITY, inv: [], gameMin: 0, profit: 0, travelExpenses: 0, profitable: 0, locale: 'en' };
const payload = (changes = {}) => JSON.stringify(serializeSave({ ...base, ...changes }));
const hydrate = (changes) => loadSavePayload(payload(changes), base, CITIES, STARTING_CITY);
function memory(entries = []) {
  const map = new Map(entries);
  return { map, getItem: async (key) => map.get(key) ?? null, setItem: async (key, value) => { map.set(key, value); } };
}

describe('review: durable restore and restart', () => {
  it('protects a future backup even when the primary is valid', async () => {
    const future = JSON.stringify({ saveVersion: SAVE_VERSION + 1, cash: 999 });
    const storage = memory([[SAVE_KEY, payload()], [BACKUP_KEY, future]]);
    assert.equal((await readSave(storage, base)).reason, 'future');
    assert.equal(storage.map.get(BACKUP_KEY), future);
  });
  it('recovers a missing or corrupt primary from the last good copy', async () => {
    for (const raw of [null, '{broken']) {
      const storage = memory([[SAVE_KEY, raw], [BACKUP_KEY, payload({ cash: 1234 })]]);
      const restored = await readSave(storage, base);
      assert.equal(restored.data.cash, 1234);
      assert.equal(restored.recovered, true);
      assert.equal(storage.map.get(SAVE_KEY), raw, 'read must not delete evidence');
    }
  });
  it('reset replaces both copies; removing the new primary never revives the old run', async () => {
    const storage = memory([[SAVE_KEY, payload({ cash: 9000 })], [BACKUP_KEY, payload({ cash: 8000 })]]);
    await resetSave(storage, payload());
    storage.map.delete(SAVE_KEY);
    assert.equal((await readSave(storage, base)).data.cash, base.cash);
    assert.ok([...storage.map.keys()].some((key) => key.includes('before-reset')));
  });
  it('protects future primary and backup formats without deleting or overwriting', async () => {
    const future = JSON.stringify({ saveVersion: SAVE_VERSION + 1, cash: 999 });
    for (const key of [SAVE_KEY, BACKUP_KEY]) {
      const storage = memory([[key, future]]);
      assert.equal((await readSave(storage, base)).reason, 'future');
      await assert.rejects(writeSave(storage, payload()), /protected/);
      assert.equal(storage.map.get(key), future);
    }
  });
  it('a primary write failure leaves a recoverable valid checkpoint', async () => {
    const storage = memory([[SAVE_KEY, payload({ cash: 1234 })]]);
    const write = storage.setItem;
    storage.setItem = async (key, value) => { if (key === SAVE_KEY) throw new Error('disk full'); await write(key, value); };
    await assert.rejects(writeSave(storage, payload()));
    assert.equal((await readSave(storage, base)).data.cash, 1234);
    assert.equal(storage.map.get(BACKUP_KEY), storage.map.get(SAVE_KEY));
    await assert.rejects(resetSave(storage, payload()));
    assert.equal((await readSave(storage, base)).data.cash, 1234);
  });
  it('read failures propagate instead of masquerading as a new game', async () => {
    await assert.rejects(readSave({ getItem: async () => { throw new Error('unavailable'); } }, base));
  });
});

describe('review: malformed and legacy saves', () => {
  it('rejects inherited object keys as city/product IDs', () => {
    for (const city of ['constructor', '__proto__', 'toString']) assert.equal(hydrate({ city }).ok, false);
    for (const id of ['constructor', '__proto__', 'toString']) assert.equal(hydrate({ inv: [{ id, n: 1, cost: 10, slot: 'bag' }] }).ok, false);
  });
  it('sanitizes nested log values and deduplicates visited cities', () => {
    const result = hydrate({ log: [{ title: 'ok', sub: {}, amount: [], t: 'bad' }], visited: [STARTING_CITY, STARTING_CITY, '__proto__'] });
    assert.equal(result.ok, true);
    assert.equal(result.data.log[0].sub, '');
    assert.equal(result.data.log[0].amount, '');
    assert.deepEqual(result.data.visited, [STARTING_CITY]);
  });
  it('honors the requested migration target and old receipt accounting epoch', () => {
    assert.equal(migrateSave({ city: STARTING_CITY }, 2).version, 2);
    const legacy = loadSavePayload(JSON.stringify({ ...base, saveVersion: 2, ticket: { toId: 'dubai', totalPaid: 300 } }), base, CITIES, STARTING_CITY);
    assert.equal(legacy.data.ticket.ledgerPaid, 0);
    assert.equal(legacy.data.ticket.from, CITIES[STARTING_CITY].iata);
    const refunded = refundTravel(legacy.data, MOBILE_BALANCE.refundRate);
    assert.equal(refunded.cash, base.cash + 210);
    assert.equal(refunded.profit, 0);
    assert.equal(refunded.travelExpenses, 0);
  });
  it('rebuilds baggage from ticket and drops stale countdown without a ticket', () => {
    const result = hydrate({ bagLimit: 100000, ticket: null, minsToDep: 120 });
    assert.equal(result.data.bagLimit, DEFAULT_BAG_LIMIT);
    assert.equal(result.data.minsToDep, 0);
    assert.equal(hydrate({ ticket: { toId: 'dubai', from: 'JFK' } }).ok, false);
  });
});

describe('review: transactions and accounting', () => {
  it('applies batched gameplay actions once even when rendering is deferred/replayed', () => {
    const renders = [];
    const store = createStateStore(base, (value) => renders.push(value));
    let feedbackCount = 0;
    store.set((state) => { feedbackCount += 1; return { ...state, ...travelCharge(state, 300) }; });
    store.set((state) => { feedbackCount += 1; return { ...state, ...saleCredit(state, 500, 100) }; });
    assert.equal(store.current.cash, base.cash + 200);
    assert.equal(store.current.profit, 100);
    assert.equal(feedbackCount, 2);
    // React is handed values, so consuming them twice cannot replay transaction effects.
    [...renders, ...renders].forEach((value) => assert.equal(typeof value, 'object'));
    assert.equal(feedbackCount, 2);
  });
  it('rounds a small fare refund down to cents and uses the configured rate', () => {
    const state = { ...base, ticket: { totalPaid: 1, ledgerPaid: 1 }, travelExpenses: 1, profit: -1 };
    const refund = refundTravel(state, 0.7);
    assert.ok(Math.abs(refund.cash - base.cash - 0.7) < 1e-8);
    assert.ok(Math.abs(refund.travelExpenses - 0.3) < 1e-8);
    assert.equal(refundTravel(state, 0.5).travelExpenses, 0.5);
  });
  it('does not suggest paying for a second itinerary while a ticket is held', () => {
    assert.deepEqual(routeOpportunities({ ...base, ticket: { toId: 'dubai' } }), []);
  });
});
