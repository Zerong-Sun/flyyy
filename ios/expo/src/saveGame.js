/**
 * Pure save serialize / migrate / hydrate — no React or AsyncStorage.
 * Used by useGame and Node unit tests.
 */

import { PRODUCTS, DEFAULT_BAG_LIMIT, DEFAULT_CARGO_CAP } from './gameData.js';
import { gcKm } from './gameLogic.js';
import { EVENT_BY_ID } from './eventData.js';

export const SAVE_KEY = 'wanli-trader/slot-1';
export const SAVE_VERSION = 4;

export const PERSIST = [
  'cash', 'bagLimit', 'cargoCap', 'inv', 'ticket', 'minsToDep', 'gameMin',
  'city', 'visited', 'log', 'legs', 'bizLegs', 'cargoLots', 'profitable',
  'profit', 'travelExpenses', 'tripRecap', 'km', 'savedAt', 'intro', 'focusDest', 'unlockedAch',
  'optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce',
  'locale',
  'fontScale', 'colorBlind', 'themeMode',
  'rep', 'level',
  'eventSeed', 'seenEventEpisodes',
];

/** Chain upgrades from stored version up to SAVE_VERSION. */
export function migrateSave(raw, targetVersion = SAVE_VERSION) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { ok: false, reason: 'invalid', data: null };
  const data = { ...raw };
  let ver = data.saveVersion == null ? 1 : Number(data.saveVersion);
  if (!Number.isInteger(ver) || ver < 0) return { ok: false, reason: 'invalid', data: null };

  if (ver > targetVersion) {
    return { ok: false, reason: 'future', version: ver, data: null };
  }

  // v0 / missing → v1: ensure arrays and ticket.extraKg
  if (ver < 1) {
    ver = 1;
  }

  // v1 → v2: seed event rolls without discarding existing progress and start a
  // clean encounter history. The derived legacy seed remains stable thereafter.
  if (ver < 2 && targetVersion >= 2) {
    data.eventSeed = data.eventSeed
      || `legacy:${data.city || 'unknown'}:${Number(data.gameMin || 0)}:${Number(data.savedAt || 0)}`;
    data.seenEventEpisodes = [];
    ver = 2;
  }

  if (ver < 3 && targetVersion >= 3) {
    // Old saves did not retain travel spending. Start a documented accounting epoch.
    data.travelExpenses = 0;
    data.profit = 0;
    if (data.ticket && typeof data.ticket === 'object') data.ticket = { ...data.ticket, ledgerPaid: 0 };
    ver = 3;
  }

  if (ver < 4 && targetVersion >= 4) {
    // Trip recaps are optional and are initialized from the current landing.
    ver = 4;
  }
  data.saveVersion = ver;
  return { ok: true, reason: 'ok', version: ver, data };
}

/**
 * Apply migrated save onto a fresh initial-state object.
 * `cities` is CITIES map; returns null if city invalid after hydrate.
 */
export function hydrateSave(baseState, migrated, cities, startingCity) {
  if (!migrated || !migrated.ok || !migrated.data) return null;
  const saved = migrated.data;
  const next = { ...baseState };
  PERSIST.forEach((k) => {
    if (saved[k] !== undefined) next[k] = saved[k];
  });
  const finiteNonNegative = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0;
  const sanitizeTrip = (raw, expectedStatus = null) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    if (!['forecast', 'landed'].includes(raw.status) || (expectedStatus && raw.status !== expectedStatus)) return null;
    if (typeof raw.from !== 'string' || typeof raw.to !== 'string' || !Object.prototype.hasOwnProperty.call(cities, raw.to)) return null;
    const numeric = ['fare', 'baggage', 'forecastRevenue', 'forecastCost', 'actualRevenue', 'actualCost', 'qualityLoss', 'discardedCost', 'soldQty', 'discardedQty'];
    if (numeric.some((key) => !finiteNonNegative(raw[key]))) return null;
    if (!Number.isInteger(raw.soldQty) || !Number.isInteger(raw.discardedQty)) return null;
    if (typeof raw.marketVariance !== 'number' || !Number.isFinite(raw.marketVariance)) return null;
    if (!raw.items || typeof raw.items !== 'object' || Array.isArray(raw.items)) return null;
    const items = {};
    for (const [id, item] of Object.entries(raw.items)) {
      if (!Object.prototype.hasOwnProperty.call(PRODUCTS, id) || !item || typeof item !== 'object') return null;
      if (['qty', 'cost', 'revenue', 'soldQty'].some((key) => !finiteNonNegative(item[key]))
          || !Number.isInteger(item.qty) || !Number.isInteger(item.soldQty) || item.soldQty > item.qty) return null;
      items[id] = { qty: item.qty, cost: item.cost, revenue: item.revenue, soldQty: item.soldQty };
    }
    return {
      from: raw.from, to: raw.to, status: raw.status, fare: raw.fare, baggage: raw.baggage, items,
      forecastRevenue: raw.forecastRevenue, forecastCost: raw.forecastCost,
      actualRevenue: raw.actualRevenue, actualCost: raw.actualCost, marketVariance: raw.marketVariance,
      qualityLoss: raw.qualityLoss, discardedCost: raw.discardedCost,
      soldQty: raw.soldQty, discardedQty: raw.discardedQty,
      ...(finiteNonNegative(raw.arrivalMinute) ? { arrivalMinute: raw.arrivalMinute } : {}),
    };
  };
  next.tripRecap = sanitizeTrip(next.tripRecap, 'landed');
  const known = (map, id) => typeof id === 'string' && Object.prototype.hasOwnProperty.call(map, id);
  if (!known(cities, next.city)) return null;
  const finite = (v) => typeof v === 'number' && Number.isFinite(v);
  for (const key of ['cash', 'bagLimit', 'cargoCap', 'minsToDep', 'gameMin', 'legs', 'bizLegs', 'cargoLots', 'profitable', 'km', 'savedAt']) {
    if (next[key] === undefined) next[key] = key === 'bagLimit' ? DEFAULT_BAG_LIMIT : key === 'cargoCap' ? DEFAULT_CARGO_CAP : 0;
    if (!finite(next[key]) || next[key] < 0) return null;
  }
  if (next.profit === undefined) next.profit = 0;
  if (!finite(next.profit)) return null;
  if (saved.travelExpenses === undefined) { next.travelExpenses = 0; next.profit = 0; }
  if (!finite(next.travelExpenses) || next.travelExpenses < 0) return null;
  for (const key of ['intro', 'optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce']) {
    if (typeof next[key] !== 'boolean') next[key] = baseState[key];
  }
  if (!['dark', 'light'].includes(next.themeMode)) next.themeMode = 'dark';
  if (next.inv === undefined) next.inv = [];
  if (!Array.isArray(next.inv)) return null;
  if (next.inv.some((i) => !i || !known(PRODUCTS, i.id) || !Number.isInteger(i.n) || i.n <= 0 || i.n > 1000000 || !finite(i.cost) || i.cost < 0 || !['bag', 'cargo'].includes(i.slot))) return null;
  next.inv = next.inv.map((i) => ({ ...i, w: PRODUCTS[i.id].w, name: PRODUCTS[i.id].name, icon: PRODUCTS[i.id].icon }));

  if (!Array.isArray(next.visited)) next.visited = [startingCity];
  if (!Array.isArray(next.log)) next.log = [];
  if (!Array.isArray(next.unlockedAch)) next.unlockedAch = [];
  if (typeof next.eventSeed !== 'string' || !next.eventSeed.trim()) {
    next.eventSeed = String(baseState.eventSeed || 'legacy-default');
  }
  next.eventSeed = next.eventSeed.trim().slice(0, 128);
  if (!Array.isArray(next.seenEventEpisodes)) next.seenEventEpisodes = [];
  const seenKeys = new Set();
  const sanitizedEpisodes = [];
  next.seenEventEpisodes.forEach((row) => {
    if (sanitizedEpisodes.length >= 100) return;
    if (!row || typeof row !== 'object' || !known(EVENT_BY_ID, row.eventId)) return;
    if (!Number.isInteger(row.startDay) || row.startDay < 0) return;
    const episodeKey = `${row.eventId}|${row.startDay}`;
    if (seenKeys.has(episodeKey)) return;
    seenKeys.add(episodeKey);
    const seenAt = Number(row.seenAt);
    sanitizedEpisodes.push({
      eventId: row.eventId,
      startDay: row.startDay,
      episodeKey,
      seenAt: Number.isFinite(seenAt) && seenAt >= 0 ? seenAt : 0,
    });
  });
  next.seenEventEpisodes = sanitizedEpisodes;
  if (next.rep == null) next.rep = 0;
  if (next.level == null) next.level = 1;
  if (!finite(next.rep) || next.rep < 0 || !Number.isInteger(next.level) || next.level < 1) return null;
  // Drop focus / ticket legs that point at unknown hubs (corrupt or downsized saves).
  if (next.focusDest && !known(cities, next.focusDest)) next.focusDest = '';
  next.log = next.log.filter((i) => i && typeof i === 'object' && typeof i.title === 'string')
    .slice(0, 40).map((row) => ({
      title: row.title,
      ...Object.fromEntries(['sub', 'amount', 'color', 'icon'].map((key) => [key, typeof row[key] === 'string' ? row[key] : ''])),
      t: finite(row.t) && row.t >= 0 ? row.t : 0,
    }));
  next.unlockedAch = next.unlockedAch.filter((id) => typeof id === 'string');
  if (next.ticket) {
    if (typeof next.ticket !== 'object' || !known(cities, next.ticket.toId)) {
      next.ticket = null;
      next.minsToDep = 0;
    } else if (next.ticket.extraKg == null) {
      next.ticket.extraKg = 0;
    }
  }
  if (next.ticket) {
    next.ticket = { ...next.ticket };
    for (const key of ['no', 'from', 'to', 'dur']) {
      if (next.ticket[key] != null && typeof next.ticket[key] !== 'string') return null;
    }
    if (next.ticket.km == null) next.ticket.km = gcKm(cities[next.city], cities[next.ticket.toId]);
    if (next.ticket.mins == null) next.ticket.mins = Math.round(next.ticket.km / 13.5 + 35);
    if (next.ticket.ledgerPaid === undefined) next.ticket.ledgerPaid = next.ticket.totalPaid || 0;
    for (const key of ['mins', 'km', 'extraKg', 'totalPaid', 'ledgerPaid']) {
      if (next.ticket[key] == null) next.ticket[key] = 0;
      if (!finite(next.ticket[key]) || next.ticket[key] < 0) return null;
    }
  }
  if (next.ticket) {
    if (next.ticket.ledgerPaid > next.ticket.totalPaid) return null;
    const { fareCost, baggageCost, totalPaid } = next.ticket;
    // Older saves only recorded the total. Keep that charge exactly once.
    if (fareCost === undefined && baggageCost === undefined) {
      next.ticket.fareCost = totalPaid;
      next.ticket.baggageCost = 0;
    } else if (!finiteNonNegative(fareCost) || !finiteNonNegative(baggageCost)
        || !Number.isFinite(fareCost + baggageCost)
        || Math.abs(fareCost + baggageCost - totalPaid) > 0.01) {
      return null;
    }
    if (next.ticket.tripForecast !== undefined) {
      next.ticket.tripForecast = sanitizeTrip(next.ticket.tripForecast, 'forecast');
      if (!next.ticket.tripForecast) delete next.ticket.tripForecast;
    }
    next.ticket.no = next.ticket.no || 'Legacy flight';
    next.ticket.from = next.ticket.from || cities[next.city].iata;
    next.ticket.to = next.ticket.to || cities[next.ticket.toId].iata;
    if (next.ticket.from !== cities[next.city].iata || next.ticket.toId === next.city) return null;
    if (!['economy', 'business'].includes(next.ticket.cabin)) next.ticket.cabin = 'economy';
  } else {
    next.ticket = null;
    next.minsToDep = 0;
  }
  next.bagLimit = DEFAULT_BAG_LIMIT + (next.ticket?.extraKg || 0);
  next.visited = [...new Set(next.visited.filter((id) => known(cities, id)))];
  if (!next.visited.length) next.visited = [startingCity];
  // Accessibility / locale sanity from possibly hand-edited or corrupt saves.
  if (![1, 1.25, 1.5].includes(next.fontScale)) next.fontScale = 1;
  if (!['off', 'deuteranopia', 'protanopia'].includes(next.colorBlind)) next.colorBlind = 'off';
  if (!['en', 'zh'].includes(next.locale)) next.locale = 'en';
  return next;
}

export function serializeSave(state, version = SAVE_VERSION) {
  const slice = { saveVersion: version };
  PERSIST.forEach((k) => { slice[k] = state[k]; });
  return slice;
}

export function corruptBackupKey(ts = Date.now()) {
  return `${SAVE_KEY}-corrupt-${ts}`;
}

/** Parse + migrate + hydrate. Throws on JSON parse error. */
export function loadSavePayload(rawString, baseState, cities, startingCity) {
  const parsed = JSON.parse(rawString);
  const migrated = migrateSave(parsed);
  if (!migrated.ok) return migrated;
  const hydrated = hydrateSave(baseState, migrated, cities, startingCity);
  if (!hydrated) {
    return { ok: false, reason: 'invalid', version: migrated.version, data: null };
  }
  return { ok: true, reason: 'ok', version: migrated.version, data: hydrated };
}
