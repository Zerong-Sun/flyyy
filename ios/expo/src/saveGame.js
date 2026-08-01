/**
 * Pure save serialize / migrate / hydrate — no React or AsyncStorage.
 * Used by useGame and Node unit tests.
 */

export const SAVE_KEY = 'airborne-trader/slot-1';
export const SAVE_VERSION = 1;

export const PERSIST = [
  'cash', 'bagLimit', 'cargoCap', 'inv', 'ticket', 'minsToDep', 'gameMin',
  'city', 'visited', 'log', 'legs', 'bizLegs', 'cargoLots', 'profitable',
  'profit', 'km', 'savedAt', 'intro', 'focusDest', 'unlockedAch',
  'optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce',
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

  // Future: if (ver < 2) { …; ver = 2; }

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
