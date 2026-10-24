import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { advanceWorldClock } from '../worldClock.js';

const atGate = (minsToDep) => ({ gameMin: 120, minsToDep, ticket: { toId: 'dubai' }, called: false });
describe('world clock departure boundary', () => {
  it('stops exactly at departure for all phases of the six-minute tick', () => {
    for (let remaining = 0; remaining <= 60; remaining++) {
      let state = atGate(remaining);
      for (let tick = 0; tick < 12; tick++) state = advanceWorldClock(state);
      assert.equal(state.gameMin, 120 + remaining);
      assert.equal(state.minsToDep, 0);
      assert.equal(state.called, true);
    }
  });
  it('advances normally without a ticket and clears an obsolete boarding call', () => {
    const next = advanceWorldClock({ gameMin: 120, minsToDep: 10, ticket: null, called: true });
    assert.equal(next.gameMin, 126);
    assert.equal(next.minsToDep, 0);
    assert.equal(next.called, false);
  });
  it('does not advance during the introduction or a flight transition', () => {
    for (const extra of [{ intro: true }, { cut: 'flight' }]) {
      const state = { ...atGate(5), ...extra };
      assert.equal(advanceWorldClock(state), state);
    }
  });
  it('preserves the input snapshot and calls boarding at thirty minutes', () => {
    const before = atGate(35);
    const next = advanceWorldClock(before);
    assert.equal(next.minsToDep, 29);
    assert.equal(next.called, true);
    assert.equal(before.minsToDep, 35);
  });
  it('rejects invalid elapsed time and supports a fractional final tick', () => {
    const before = atGate(0.5);
    for (const step of [-1, 0, Infinity, NaN]) assert.equal(advanceWorldClock(before, step), before);
    assert.equal(advanceWorldClock(before).gameMin, 120.5);
  });
});
