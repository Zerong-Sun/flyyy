/** Stop exactly at departure; boarding owns the next time jump to arrival. */
export function advanceWorldClock(state, minutes = 6) {
  if (state.intro || state.cut || !Number.isFinite(minutes) || minutes <= 0) return state;
  const elapsed = state.ticket ? Math.min(minutes, Math.max(0, state.minsToDep)) : minutes;
  const minsToDep = state.ticket ? Math.max(0, state.minsToDep - elapsed) : 0;
  return {
    ...state,
    gameMin: state.gameMin + elapsed,
    minsToDep,
    called: !!state.ticket && (state.called || minsToDep <= 30),
  };
}
