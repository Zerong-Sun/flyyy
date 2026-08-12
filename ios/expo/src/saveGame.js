/**
 * Pure save serialize / migrate / hydrate — no React or AsyncStorage.
 * Used by useGame and Node unit tests.
 */

import { EVENT_BY_ID } from './eventData.js';

export const SAVE_KEY = 'wanli-trader/slot-1';
export const SAVE_VERSION = 2;

export const PERSIST = [
  'cash', 'bagLimit', 'cargoCap', 'inv', 'ticket', 'minsToDep', 'gameMin',
  'city', 'visited', 'log', 'legs', 'bizLegs', 'cargoLots', 'profitable',
  'profit', 'km', 'savedAt', 'intro', 'focusDest', 'unlockedAch',
  'optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce',
  'locale',
  'fontScale', 'colorBlind',
  'rep', 'level',
  'eventSeed', 'seenEventEpisodes',
];

/** Chain upgrades from stored version up to SAVE_VERSION. */
export function migrateSave(raw, targetVersion = SAVE_VERSION) {
  const data = { ...raw };
  let ver = data.saveVersion == null ? 1 : Number(data.saveVersion);
  if (Number.isNaN(ver)) ver = 1;

  if (ver > targetVersion) {
    return { ok: false, reason: 'future', version: ver, data: null };
  }

  // v0 / missing → v1: ensure arrays and ticket.extraKg
  if (ver < 1) {
    ver = 1;
  }

  // v1 → v2: seed event rolls without discarding existing progress and start a
  // clean encounter history. The derived legacy seed remains stable thereafter.
  if (ver < 2) {
    data.eventSeed = data.eventSeed
      || `legacy:${data.city || 'unknown'}:${Number(data.gameMin || 0)}:${Number(data.savedAt || 0)}`;
    data.seenEventEpisodes = [];
    ver = 2;
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
  if (!cities[next.city]) return null;
  if (!Array.isArray(next.inv)) next.inv = [];
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
    if (!row || typeof row !== 'object' || !EVENT_BY_ID[row.eventId]) return;
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
  // Drop focus / ticket legs that point at unknown hubs (corrupt or downsized saves).
  if (next.focusDest && !cities[next.focusDest]) next.focusDest = '';
  if (next.ticket) {
    if (!cities[next.ticket.toId]) {
      next.ticket = null;
      next.minsToDep = 0;
    } else if (next.ticket.extraKg == null) {
      next.ticket.extraKg = 0;
    }
  }
  next.visited = next.visited.filter((id) => cities[id]);
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
