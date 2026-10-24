import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addTripSaleBonus,
  createTripForecast,
  landTripForecast,
  recordTripDiscard,
  recordTripSale,
  tripRecapTotals,
} from '../tripRecap.js';

test('trip P&L compares forecast to full-quality market, then isolates spoilage and travel', () => {
  const forecast = createTripForecast({
    from: 'ams', to: 'ist', fare: 120, baggage: 30,
    inventory: [{ id: 'tea', n: 4, cost: 20 }],
    quote: () => 40,
  });
  let recap = landTripForecast(forecast, 600);
  recap = recordTripSale(recap, 'ist', {
    id: 'tea', qty: 3, cost: 60, revenue: 105, fullQualityRevenue: 120,
  });
  recap = addTripSaleBonus(recap, 'ist', 5);
  const totals = tripRecapTotals(recap);
  assert.equal(recap.marketVariance, 5); // (120 + premium 5) - forecast value 120 for 3 units
  assert.equal(recap.qualityLoss, 15);
  assert.equal(totals.forecastNet, -70);
  assert.equal(totals.realizedNet, -100);
  assert.equal(totals.remainingQty, 1);
});

test('trip recap ignores sales in another city and accounts for discarded stock once', () => {
  const forecast = landTripForecast(createTripForecast({
    from: 'ams', to: 'ist', fare: 0, baggage: 0,
    inventory: [{ id: 'tea', n: 2, cost: 10 }], quote: () => 15,
  }));
  assert.equal(recordTripSale(forecast, 'lon', { id: 'tea', qty: 1, cost: 10, revenue: 12 }), forecast);
  const recap = recordTripDiscard(forecast, 'ist', 'tea', 1, 10);
  assert.equal(tripRecapTotals(recap).remainingQty, 1);
  assert.equal(tripRecapTotals(recap).realizedNet, -10);
});

test('goods bought after landing do not contaminate the forecast market variance', () => {
  const forecast = landTripForecast(createTripForecast({
    from: 'ams', to: 'ist', fare: 0, baggage: 0,
    inventory: [{ id: 'tea', n: 1, cost: 5 }], quote: () => 10,
  }));
  const recap = recordTripSale(forecast, 'ist', {
    id: 'tea', qty: 2, cost: 10, revenue: 24, fullQualityRevenue: 24,
  });
  assert.equal(recap.marketVariance, 2); // only the carried unit's price changed from $10 to $12
});
