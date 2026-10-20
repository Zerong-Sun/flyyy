/** Apply gameplay transactions once, before React schedules rendering.
 * React receives values rather than side-effecting updater functions. */
export function createStateStore(initial, publish) {
  const store = { current: initial };
  store.set = (update) => {
    const next = typeof update === 'function' ? update(store.current) : update;
    if (next !== store.current) {
      store.current = next;
      publish(next);
    }
    return next;
  };
  return store;
}
