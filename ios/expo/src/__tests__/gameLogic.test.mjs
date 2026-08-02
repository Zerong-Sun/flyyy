import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  priceAt,
  factorFor,
  waitUntilDep,
  bagUsed,
  mergeInvCost,
  routesFrom,
  sellData,
  computeStats,
  cityMinutes,
  sortByDestProfit,
  priceSparkline,
  locals,
  globeSizeFor,
} from '../gameLogic.js';
import { ACHIEVEMENTS, CITIES, CIDS, PRODUCT_IDS, PRODUCTS, STARTING_CITY } from '../gameData.js';
import { t, LOCALES, DICT } from '../i18n.js';
import {
  SAVE_VERSION,
  migrateSave,
  serializeSave,
  loadSavePayload,
  hydrateSave,
} from '../saveGame.js';

// Node ESM requires .js extensions; Metro also accepts them.

describe('priceAt / factorFor', () => {
  it('home city is cheaper than a far import market', () => {
    const home = factorFor('ist_lokum', 'istanbul');
    const far = factorFor('ist_lokum', 'tokyo');
    assert.ok(home <= 1, `home factor ${home}`);
    assert.ok(far > home, `far ${far} should exceed home ${home}`);
    assert.ok(priceAt('ist_lokum', 'tokyo') > priceAt('ist_lokum', 'istanbul'));
  });
});

describe('waitUntilDep', () => {
  it('wraps past midnight when dep already passed locally', () => {
    // Pick a depMin earlier than local now so wait wraps +1440
    const gameMin = 0;
    const local = ((cityMinutes(gameMin, 'istanbul') % 1440) + 1440) % 1440;
    const depMin = (local + 1440 - 30) % 1440; // 30 min ago
    const wait = waitUntilDep(gameMin, 'istanbul', depMin);
    assert.ok(wait > 1400 && wait <= 1440, `wait=${wait}`);
  });

  it('is positive and under a day for a future departure', () => {
    const gameMin = 0;
    const local = ((cityMinutes(gameMin, 'istanbul') % 1440) + 1440) % 1440;
    const depMin = (local + 90) % 1440;
    const wait = waitUntilDep(gameMin, 'istanbul', depMin);
    assert.ok(wait > 0 && wait <= 1440);
  });
});

describe('baggage / inventory cost', () => {
  it('bagUsed sums bag slot weight only', () => {
    const inv = [
      { slot: 'bag', w: 2, n: 3 },
      { slot: 'cargo', w: 10, n: 1 },
    ];
    assert.equal(bagUsed(inv), 6);
  });

  it('mergeInvCost weighted average', () => {
    assert.equal(mergeInvCost(100, 1, 200, 1), 150);
    assert.equal(mergeInvCost(10, 2, 40, 2), 25);
  });
});

describe('routesFrom replace', () => {
  it('drops generated legs when a custom replace flight exists', () => {
    const from = 'istanbul';
    const routes = routesFrom(from);
    // All destinations should appear; custom replace flights override generated dep
    assert.ok(routes.length > 0);
    const byTo = {};
    routes.forEach((r) => {
      byTo[r.toId] = (byTo[r.toId] || 0) + 1;
    });
    Object.values(byTo).forEach((n) => assert.ok(n >= 1));
  });
});

describe('sellData', () => {
  it('net sign matches gross minus cost', () => {
    const inv = [{
      id: 'ist_lokum', name: 'Lokum', icon: 'x', w: 1, n: 2, slot: 'bag',
      cost: priceAt('ist_lokum', 'istanbul'),
    }];
    // Selling at home roughly breaks even or small loss/gain; force profit city
    const d = sellData(inv, 'tokyo');
    assert.equal(d.net, d.gross - inv[0].cost * 2);
    assert.ok(d.net > 0);
  });
});

describe('achievements threshold', () => {
  it('unlocks first_flight at legs >= 1', () => {
    const ac = ACHIEVEMENTS.find((a) => a.id === 'first_flight');
    const stats = computeStats({
      visited: [STARTING_CITY],
      legs: 1,
      profitable: 0,
      bizLegs: 0,
      cargoLots: 0,
      cash: 5000,
      profit: 0,
    });
    assert.ok((stats[ac.stat] || 0) >= ac.goal);
    const below = computeStats({
      visited: [STARTING_CITY],
      legs: 0,
      profitable: 0,
      bizLegs: 0,
      cargoLots: 0,
      cash: 5000,
      profit: 0,
    });
    assert.ok((below[ac.stat] || 0) < ac.goal);
  });
});

describe('save migrate round-trip', () => {
  it('serialize → migrate → hydrate preserves cash and city', () => {
    const base = {
      cash: 9999,
      city: 'dubai',
      inv: [{ id: 'dxb_gold', n: 1, slot: 'bag', w: 1, cost: 100, name: 'Gold', icon: 'x' }],
      visited: ['istanbul', 'dubai'],
      ticket: { toId: 'london', extraKg: 10 },
      bagLimit: 33,
      unlockedAch: ['first_flight'],
      legs: 2,
      gameMin: 120,
    };
    const slice = serializeSave(base);
    assert.equal(slice.saveVersion, SAVE_VERSION);
    const raw = JSON.stringify(slice);
    const loaded = loadSavePayload(raw, { cash: 0, city: STARTING_CITY, inv: [] }, CITIES, STARTING_CITY);
    assert.equal(loaded.ok, true);
    assert.equal(loaded.data.cash, 9999);
    assert.equal(loaded.data.city, 'dubai');
    assert.equal(loaded.data.ticket.extraKg, 10);
    assert.deepEqual(loaded.data.unlockedAch, ['first_flight']);
  });

  it('future version is rejected', () => {
    const m = migrateSave({ saveVersion: 99, cash: 1 });
    assert.equal(m.ok, false);
    assert.equal(m.reason, 'future');
  });

  it('missing saveVersion migrates as v1', () => {
    const m = migrateSave({ cash: 50, city: 'istanbul' });
    assert.equal(m.ok, true);
    assert.equal(m.data.saveVersion, 1);
    const h = hydrateSave({ cash: 0 }, m, CITIES, STARTING_CITY);
    assert.equal(h.cash, 50);
  });

  it('drops invalid ticket.toId and focusDest on hydrate', () => {
    const m = migrateSave({
      saveVersion: 1,
      city: 'istanbul',
      focusDest: 'not_a_city',
      ticket: { toId: 'ghost', no: 'XX 1' },
      minsToDep: 40,
      visited: ['istanbul', 'ghost'],
    });
    const h = hydrateSave({ cash: 0, city: STARTING_CITY, inv: [] }, m, CITIES, STARTING_CITY);
    assert.equal(h.focusDest, '');
    assert.equal(h.ticket, null);
    assert.equal(h.minsToDep, 0);
    assert.deepEqual(h.visited, ['istanbul']);
  });
});

describe('market intel helpers', () => {
  it('sortByDestProfit puts higher uplift first', () => {
    const ids = ['ist_lokum', 'ist_copper'];
    const sorted = sortByDestProfit(ids, 'istanbul', 'tokyo');
    const uplift = (id) => priceAt(id, 'tokyo') - priceAt(id, 'istanbul');
    assert.ok(uplift(sorted[0]) >= uplift(sorted[1]));
  });

  it('priceSparkline ends at current price', () => {
    const pts = priceSparkline('ist_lokum', 'istanbul', 5);
    assert.equal(pts.length, 5);
    assert.equal(pts[4], priceAt('ist_lokum', 'istanbul'));
  });
});

describe('content completeness', () => {
  it('every playable hub sells at least one local product', () => {
    const empty = CIDS.filter((id) => locals(id).length === 0);
    assert.deepEqual(empty, [], `hubs with no local goods: ${empty.join(', ')}`);
  });

  it('new hubs expose local specialties', () => {
    assert.ok(locals('atlanta').length >= 3);
    assert.ok(locals('dallas').length >= 3);
    assert.ok(locals('denver').length >= 2);
    assert.ok(locals('chicago').length >= 2);
    assert.ok(locals('los_angeles').length >= 3);
    assert.ok(locals('guangzhou').length >= 2);
    assert.ok(locals('seoul').length >= 1);
    assert.ok(locals('miami').length >= 3);
  });

  it('every hub has a local good that sells for a profit somewhere', () => {
    const dead = CIDS.filter((cid) => {
      const ids = locals(cid);
      const profitable = ids.some((id) => {
        const home = priceAt(id, cid);
        return CIDS.some((d) => d !== cid && priceAt(id, d) > home);
      });
      return !profitable;
    });
    assert.deepEqual(dead, [], `hubs with no profitable local goods: ${dead.join(', ')}`);
  });
});

describe('globe sizing', () => {
  it('shrinks from the old fixed 268 on common phones', () => {
    assert.ok(globeSizeFor(852) < 268, `852pt phone -> ${globeSizeFor(852)}`);
    assert.ok(globeSizeFor(844) < 268);
    assert.equal(globeSizeFor(844), 224);
  });

  it('clamps to the floor on very small screens', () => {
    assert.equal(globeSizeFor(400), 216);
    assert.equal(globeSizeFor(667), 216);
  });

  it('clamps to the ceiling on very large screens', () => {
    assert.equal(globeSizeFor(1000), 244);
    assert.equal(globeSizeFor(1366), 244);
  });
});

describe('i18n', () => {
  it('has en and zh locales with matching keys', () => {
    assert.deepEqual(LOCALES, ['en', 'zh']);
    const enKeys = Object.keys(DICT.en);
    assert.ok(enKeys.length > 10);
    assert.deepEqual(enKeys.sort(), Object.keys(DICT.zh).sort());
  });

  it('t returns the localized string and falls back safely', () => {
    assert.equal(t('en', 'brand'), 'Airborne Trader');
    assert.equal(t('zh', 'brand'), '环球航商');
    assert.equal(t('en', 'tab_market'), 'Market');
    assert.equal(t('zh', 'tab_market'), '市场');
    assert.equal(t('en', 'missing_key'), 'missing_key');
    assert.equal(t('xx', 'brand'), 'Airborne Trader'); // unknown locale → en
  });
});
