import { CITIES, STARTING_CITY } from './gameData.js';
import { SAVE_KEY, loadSavePayload, corruptBackupKey } from './saveGame.js';

export const BACKUP_KEY = `${SAVE_KEY}-last-good`;
const parse = (raw, base = {}) => {
  if (!raw) return { ok: false, reason: 'missing' };
  try { return loadSavePayload(raw, base, CITIES, STARTING_CITY); }
  catch { return { ok: false, reason: 'invalid' }; }
};

/** Read without deleting anything. Future primary/backup formats remain protected. */
export async function readSave(storage, base) {
  const primary = parse(await storage.getItem(SAVE_KEY), base);
  if (primary.ok || primary.reason === 'future') return primary;
  const backup = parse(await storage.getItem(BACKUP_KEY), base);
  if (backup.ok) return { ...backup, recovered: true };
  if (backup.reason === 'future') return backup;
  return { ok: false, reason: primary.reason === 'missing' && backup.reason === 'missing' ? 'missing' : 'invalid' };
}

/** Callers serialize operations. No success is reported before the primary commits. */
export async function writeSave(storage, payload) {
  if (!parse(payload).ok) throw new Error('Invalid save payload');
  const previous = await storage.getItem(SAVE_KEY);
  const result = parse(previous);
  const backup = parse(await storage.getItem(BACKUP_KEY));
  if (result.reason === 'future' || backup.reason === 'future') throw new Error('Newer save protected');
  if (result.ok) await storage.setItem(BACKUP_KEY, previous);
  else if (previous) await storage.setItem(corruptBackupKey(), previous);
  await storage.setItem(SAVE_KEY, payload);
}

/** Explicit new run: replace both copies so recovery cannot resurrect the old run. */
export async function resetSave(storage, payload) {
  if (!parse(payload).ok) throw new Error('Invalid reset payload');
  for (const key of [SAVE_KEY, BACKUP_KEY]) {
    const previous = await storage.getItem(key);
    if (previous) await storage.setItem(`${key}-before-reset-${Date.now()}`, previous);
  }
  await storage.setItem(BACKUP_KEY, payload);
  await storage.setItem(SAVE_KEY, payload);
}
