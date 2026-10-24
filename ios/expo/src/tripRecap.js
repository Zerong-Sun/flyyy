/** Pure trip forecast and realized P&L helpers shared by the mobile UI and tests. */

export function createTripForecast({ from, to, inventory, fare, baggage, quote }) {
  const items = {};
  let forecastRevenue = 0;
  let forecastCost = 0;
  (Array.isArray(inventory) ? inventory : []).forEach((item) => {
    if (!item || typeof item.id !== 'string' || !Number.isFinite(item.n) || item.n <= 0) return;
    const unit = Number(quote(item.id, to));
    if (!Number.isFinite(unit) || unit < 0) return;
    const cost = Math.max(0, Number(item.cost) || 0) * item.n;
    const revenue = unit * item.n;
    if (!items[item.id]) items[item.id] = { qty: 0, cost: 0, revenue: 0, soldQty: 0 };
    items[item.id].qty += item.n;
    items[item.id].cost += cost;
    items[item.id].revenue += revenue;
    forecastCost += cost;
    forecastRevenue += revenue;
  });
  return {
    from: String(from || ''),
    to: String(to || ''),
    status: 'forecast',
    fare: Math.max(0, Number(fare) || 0),
    baggage: Math.max(0, Number(baggage) || 0),
    items,
    forecastRevenue,
    forecastCost,
    actualRevenue: 0,
    actualCost: 0,
    marketVariance: 0,
    qualityLoss: 0,
    discardedCost: 0,
    soldQty: 0,
    discardedQty: 0,
  };
}

export function landTripForecast(forecast, arrivalMinute = 0) {
  if (!forecast || typeof forecast !== 'object') return null;
  return { ...forecast, status: 'landed', arrivalMinute: Math.max(0, Number(arrivalMinute) || 0) };
}

export function recordTripSale(recap, city, sale) {
  if (!recap || recap.status !== 'landed' || recap.to !== city || !sale || typeof sale.id !== 'string') return recap;
  const next = { ...recap, items: { ...recap.items } };
  const item = next.items[sale.id] ? { ...next.items[sale.id] } : { qty: 0, cost: 0, revenue: 0, soldQty: 0 };
  const qty = Math.max(0, Math.floor(Number(sale.qty) || 0));
  const revenue = Math.max(0, Number(sale.revenue) || 0);
  const cost = Math.max(0, Number(sale.cost) || 0);
  const fullQualityRevenue = Math.max(revenue, Number(sale.fullQualityRevenue) || revenue);
  const forecastQty = Math.max(0, item.qty - item.soldQty);
  const matchedQty = Math.min(qty, forecastQty);
  const unforecastQty = Math.max(0, qty - matchedQty);
  const fullQualityUnit = qty > 0 ? fullQualityRevenue / qty : 0;
  const forecastRevenue = item.qty > 0
    ? ((item.revenue / item.qty) * matchedQty) + (fullQualityUnit * unforecastQty)
    : fullQualityRevenue;
  item.soldQty += matchedQty;
  next.items[sale.id] = item;
  next.actualRevenue += revenue;
  next.actualCost += cost;
  next.marketVariance += fullQualityRevenue - forecastRevenue;
  next.qualityLoss += Math.max(0, fullQualityRevenue - revenue);
  next.soldQty += qty;
  return next;
}

export function recordTripDiscard(recap, city, id, qty, cost) {
  if (!recap || recap.status !== 'landed' || recap.to !== city) return recap;
  const items = { ...recap.items };
  if (items[id]) {
    const item = { ...items[id] };
    item.soldQty += Math.min(Math.max(0, Number(qty) || 0), Math.max(0, item.qty - item.soldQty));
    items[id] = item;
  }
  return {
    ...recap,
    items,
    discardedCost: recap.discardedCost + Math.max(0, Number(cost) || 0),
    discardedQty: recap.discardedQty + Math.max(0, Math.floor(Number(qty) || 0)),
  };
}

export function addTripSaleBonus(recap, city, bonus) {
  if (!recap || recap.status !== 'landed' || recap.to !== city) return recap;
  const amount = Math.max(0, Number(bonus) || 0);
  return { ...recap, actualRevenue: recap.actualRevenue + amount, marketVariance: recap.marketVariance + amount };
}

export function tripRecapTotals(recap) {
  if (!recap) return null;
  return {
    forecastNet: recap.forecastRevenue - recap.forecastCost - recap.fare - recap.baggage,
    realizedNet: recap.actualRevenue - recap.actualCost - recap.fare - recap.baggage - recap.discardedCost,
    remainingQty: Math.max(0, Object.values(recap.items || {}).reduce((n, item) => n + item.qty - item.soldQty, 0)),
  };
}
