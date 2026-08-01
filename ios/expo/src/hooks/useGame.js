import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import {
  ACHIEVEMENTS,
  ADDONS,
  CIDS,
  CITIES,
  CUTSCENE_ART,
  DEFAULT_BAG_LIMIT,
  DEFAULT_CARGO_CAP,
  PRODUCTS,
  STARTING_CASH,
  STARTING_CITY,
} from '../gameData';
import {
  bagUsed,
  cargoUsed,
  cityMinutes,
  clockLabel,
  computeStats,
  fmtClock,
  hhmm,
  hm,
  imports,
  intel,
  locals,
  money,
  priceAt,
  priceSparkline,
  destinationsFrom,
  routesFrom,
  sellData,
  sortByDestProfit,
  waitUntilDep,
} from '../gameLogic';
import { playSfx } from '../audio';
import {
  SAVE_KEY,
  serializeSave,
  loadSavePayload,
  corruptBackupKey,
} from '../saveGame';

const initialState = () => ({
  tab: 'globe',
  page: null,
  seg: 'local',
  query: '',
  focusDest: '',
  sheet: null,
  selId: null,
  selFlight: null,
  selInv: null,
  invQty: 1,
  qty: 1,
  slot: 'bag',
  cabin: 'economy',
  addon: '',
  filter: 'departure',
  cash: STARTING_CASH,
  bagLimit: DEFAULT_BAG_LIMIT,
  cargoCap: DEFAULT_CARGO_CAP,
  inv: [],
  ticket: null,
  minsToDep: 0,
  gameMin: 0,
  toast: null,
  toastKind: 'ok',
  cut: null,
  cutLine: '',
  city: STARTING_CITY,
  visited: [STARTING_CITY],
  log: [],
  lastSale: null,
  intro: true,
  legs: 0,
  bizLegs: 0,
  cargoLots: 0,
  profitable: 0,
  profit: 0,
  km: 0,
  savedAt: 0,
  called: false,
  rot: null,
  dragging: false,
  unlockedAch: [],
  overweightNote: '',
  pinCity: null,
  optHaptics: true,
  optPush: true,
  optSound: true,
  opt24h: true,
  optReduce: false,
});

function unlockedIds(stats, unlocked = []) {
  return ACHIEVEMENTS
    .filter((a) => unlocked.includes(a.id) || (stats[a.stat] || 0) >= a.goal)
    .map((a) => a.id);
}

function findInv(inv, selInv) {
  if (!selInv) return -1;
  return inv.findIndex((i) => i.id === selInv.id && i.slot === selInv.slot);
}

export function useGame() {
  const [state, setState] = useState(initialState);
  const [loaded, setLoaded] = useState(false);
  const cutRef = useRef(null);
  const toastRef = useRef(null);
  const saveRef = useRef(null);
  const stateRef = useRef(state);
  const interactedRef = useRef(false);
  const flyingRef = useRef(false);
  const calledEdgeRef = useRef(false);
  const suspendAutosaveRef = useRef(false);
  const pendingAchRef = useRef([]);
  stateRef.current = state;

  const tap = useCallback((kind) => {
    if (!stateRef.current.optHaptics) return;
    const style = kind === 'bad'
      ? Haptics.NotificationFeedbackType.Warning
      : Haptics.NotificationFeedbackType.Success;
    Haptics.notificationAsync(style).catch(() => {});
  }, []);

  const click = useCallback((sfxId) => {
    if (!stateRef.current.optSound) return;
    const fallback = () => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    };
    if (!sfxId) {
      fallback();
      return;
    }
    playSfx(sfxId).then((ok) => { if (!ok) fallback(); }).catch(fallback);
  }, []);

  const buzz = useCallback((message, kind = 'ok') => {
    clearTimeout(toastRef.current);
    setState((s) => ({ ...s, toast: message, toastKind: kind }));
    toastRef.current = setTimeout(() => {
      setState((s) => ({ ...s, toast: null }));
    }, 2400);
    tap(kind);
  }, [tap]);

  /** Pure: returns updated unlock ids; queues toast ids for a later effect. */
  const announceAchievements = useCallback((prevUnlocked, nextStats) => {
    const next = unlockedIds(nextStats, prevUnlocked);
    const fresh = next.filter((id) => !prevUnlocked.includes(id));
    if (fresh.length) pendingAchRef.current = pendingAchRef.current.concat(fresh);
    return next;
  }, []);

  const markInteracted = useCallback(() => {
    interactedRef.current = true;
  }, []);

  /* ---- save / restore ------------------------------------------- */

  useEffect(() => {
    let alive = true;
    AsyncStorage.getItem(SAVE_KEY)
      .then(async (raw) => {
        if (!alive || !raw) return;
        if (interactedRef.current) return;
        let result;
        try {
          result = loadSavePayload(raw, initialState(), CITIES, STARTING_CITY);
        } catch (err) {
          const bak = corruptBackupKey();
          await AsyncStorage.setItem(bak, raw).catch(() => {});
          await AsyncStorage.removeItem(SAVE_KEY).catch(() => {});
          setTimeout(() => buzz('Save was corrupted — started a new run. Backup kept on device.', 'bad'), 400);
          return;
        }
        if (!result.ok && result.reason === 'future') {
          // Park the newer save so autosave cannot clobber it; play a fresh run.
          const parked = `${SAVE_KEY}-future-${Date.now()}`;
          await AsyncStorage.setItem(parked, raw).catch(() => {});
          await AsyncStorage.removeItem(SAVE_KEY).catch(() => {});
          suspendAutosaveRef.current = false;
          setTimeout(() => {
            Alert.alert(
              'Save from a newer build',
              'That save was parked on this device. Continue with a new run here?',
              [
                {
                  text: 'OK',
                  onPress: () => buzz('New run — newer save kept as a backup key.', 'ok'),
                },
              ],
            );
          }, 400);
          return;
        }
        if (!result.ok) {
          const bak = corruptBackupKey();
          await AsyncStorage.setItem(bak, raw).catch(() => {});
          await AsyncStorage.removeItem(SAVE_KEY).catch(() => {});
          setTimeout(() => buzz('Save could not be restored — started fresh.', 'bad'), 400);
          return;
        }
        setState((s) => (interactedRef.current ? s : { ...s, ...result.data }));
      })
      .catch(() => {})
      .finally(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, [buzz]);

  useEffect(() => {
    if (!loaded || suspendAutosaveRef.current) return undefined;
    clearTimeout(saveRef.current);
    saveRef.current = setTimeout(() => {
      if (suspendAutosaveRef.current) return;
      const savedAt = stateRef.current.gameMin;
      const slice = serializeSave({ ...stateRef.current, savedAt });
      AsyncStorage.setItem(SAVE_KEY, JSON.stringify(slice))
        .then(() => {
          setState((s) => (s.savedAt === savedAt ? s : { ...s, savedAt }));
        })
        .catch(() => {});
    }, 700);
    return () => clearTimeout(saveRef.current);
  }, [state, loaded]);

  // Flush achievement toasts outside setState updaters.
  useEffect(() => {
    const pending = pendingAchRef.current;
    if (!pending.length) return undefined;
    pendingAchRef.current = [];
    const first = ACHIEVEMENTS.find((a) => a.id === pending[0]);
    if (!first) return undefined;
    const t = setTimeout(() => {
      click('sfx_ach');
      buzz(`Achievement unlocked — ${first.name}`, 'ok');
    }, 400);
    return () => clearTimeout(t);
  }, [state.unlockedAch, buzz, click]);

  const finishLanding = useCallback((ticket) => {
    const to = CITIES[ticket.toId];
    if (!to) return;
    const s0 = stateRef.current;
    const bagNow = bagUsed(s0.inv);
    const allowance = s0.bagLimit;
    const overweightKg = Math.max(0, bagNow - DEFAULT_BAG_LIMIT);
    setState((s) => {
      if (!s.ticket || s.ticket.toId !== ticket.toId) return s;
      const visited = s.visited.includes(ticket.toId) ? s.visited : [...s.visited, ticket.toId];
      const hasInv = s.inv.length > 0;
      const entry = {
        icon: 'assets/ic_flight.webp',
        title: `Landed in ${to.name}`,
        sub: `${ticket.no} · ${ticket.km.toLocaleString('en-US')} km`,
        amount: '',
        color: '#A8B8C8',
        t: s.gameMin + s.minsToDep + ticket.mins,
      };
      const next = {
        ...s,
        cut: null,
        cutLine: '',
        ticket: null,
        minsToDep: 0,
        called: false,
        bagLimit: DEFAULT_BAG_LIMIT,
        city: ticket.toId,
        rot: -to.lon,
        tab: 'globe',
        page: null,
        seg: 'local',
        focusDest: '',
        visited,
        log: [entry].concat(s.log).slice(0, 40),
        gameMin: s.gameMin + s.minsToDep + ticket.mins,
        legs: s.legs + 1,
        km: s.km + ticket.km,
        bizLegs: s.bizLegs + (ticket.cabin === 'business' ? 1 : 0),
        sheet: hasInv ? 'sell' : null,
        overweightNote: overweightKg > 0
          ? `Carry-on over by ${overweightKg.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`
          : '',
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return next;
    });
    flyingRef.current = false;
    calledEdgeRef.current = false;
    buzz(`Landed in ${to.name}`, 'ok');
    if (bagNow > allowance) {
      setTimeout(() => {
        buzz(`Your ${allowance} kg allowance covered this leg; base carry-on is ${DEFAULT_BAG_LIMIT} kg again.`, 'ok');
      }, 1200);
    }
    if (overweightKg > 0) {
      setTimeout(() => {
        buzz(`Carry-on over by ${overweightKg.toFixed(1)} kg — sell or discard in Bags.`, 'bad');
      }, 2600);
    }
  }, [announceAchievements, buzz]);

  const runCutscene = useCallback(() => {
    const t = stateRef.current.ticket;
    if (!t || stateRef.current.cut || flyingRef.current) return;
    const to = CITIES[t.toId];
    if (!to) {
      buzz('Ticket destination missing — ticket cleared', 'bad');
      setState((s) => ({
        ...s,
        ticket: null,
        minsToDep: 0,
        called: false,
        bagLimit: DEFAULT_BAG_LIMIT,
      }));
      return;
    }
    flyingRef.current = true;
    clearTimeout(cutRef.current);
    click('sfx_gate');
    const steps = CUTSCENE_ART.map((step, i) => (
      i === 2 ? { ...step, title: to.name } : step
    ));
    const dur = stateRef.current.optReduce ? 600 : 1700;
    let i = 0;
    setState((s) => ({
      ...s,
      sheet: null,
      cut: steps[0],
      cutLine: `${t.no} · ${t.from} → ${t.to} · ${t.km.toLocaleString('en-US')} km`,
    }));
    const tick = () => {
      i += 1;
      if (i < steps.length) {
        setState((s) => ({ ...s, cut: steps[i] }));
        cutRef.current = setTimeout(tick, dur);
      } else {
        finishLanding(t);
      }
    };
    cutRef.current = setTimeout(tick, dur);
  }, [buzz, click, finishLanding]);

  /* ---- world clock ---------------------------------------------- */

  useEffect(() => {
    if (!loaded) return undefined;
    const t = setInterval(() => {
      const cur = stateRef.current;
      if (cur.intro || cur.cut) return;
      setState((s) => {
        if (s.intro || s.cut) return s;
        const minsToDep = s.ticket ? Math.max(0, s.minsToDep - 6) : 0;
        const called = s.ticket ? (s.called || minsToDep <= 30) : false;
        if (
          s.ticket
          && minsToDep === 0
          && s.minsToDep > 0
          && !flyingRef.current
          && !s.cut
        ) {
          setTimeout(() => runCutscene(), 0);
        }
        return {
          ...s,
          gameMin: s.gameMin + 6,
          minsToDep,
          called,
        };
      });
    }, 1000);
    return () => {
      clearInterval(t);
      clearTimeout(cutRef.current);
      clearTimeout(toastRef.current);
    };
  }, [loaded, runCutscene]);

  // Boarding-call toast once per ticket edge.
  useEffect(() => {
    if (state.called && state.optPush && state.ticket && !calledEdgeRef.current) {
      calledEdgeRef.current = true;
      buzz(`Boarding call · ${state.ticket.no} · gate closing`, 'ok');
    }
    if (!state.ticket) calledEdgeRef.current = false;
  }, [state.called, state.optPush, state.ticket, buzz]);

  const city = CITIES[state.city];
  const destId = state.ticket ? state.ticket.toId : (state.focusDest || '');
  const bagKg = bagUsed(state.inv);
  const cargoKg = cargoUsed(state.inv);
  const localIds = useMemo(() => locals(state.city), [state.city]);
  const importIds = useMemo(() => imports(state.city), [state.city]);
  const routes = useMemo(() => routesFrom(state.city), [state.city]);
  const destinations = useMemo(() => destinationsFrom(state.city), [state.city]);
  const stats = useMemo(() => computeStats({
    visited: state.visited,
    legs: state.legs,
    profitable: state.profitable,
    bizLegs: state.bizLegs,
    cargoLots: state.cargoLots,
    cash: state.cash,
    profit: state.profit,
  }), [
    state.visited, state.legs, state.profitable, state.bizLegs,
    state.cargoLots, state.cash, state.profit,
  ]);
  const sell = useMemo(() => sellData(state.inv, state.city), [state.inv, state.city]);

  const setTab = useCallback((tab) => {
    markInteracted();
    setState((s) => ({ ...s, tab, page: null, query: '' }));
  }, [markInteracted]);
  const setPage = useCallback((page) => {
    markInteracted();
    setState((s) => ({ ...s, page }));
  }, [markInteracted]);
  const setSeg = useCallback((seg) => setState((s) => ({ ...s, seg })), []);
  const setQuery = useCallback((query) => {
    markInteracted();
    setState((s) => ({ ...s, query }));
  }, [markInteracted]);
  const setFocusDest = useCallback((focusDest) => {
    markInteracted();
    // Clearing focus stays on the current tab; setting focus opens Flights.
    if (!focusDest) {
      setState((s) => ({ ...s, focusDest: '', pinCity: null }));
      return;
    }
    setState((s) => ({
      ...s,
      focusDest,
      query: '',
      tab: 'flights',
      page: null,
      filter: 'departure',
      pinCity: null,
    }));
  }, [markInteracted]);

  const openPinCity = useCallback((id) => {
    if (!id || !CITIES[id]) return;
    setState((s) => ({ ...s, pinCity: id }));
  }, []);

  const closePinCity = useCallback(() => {
    setState((s) => ({ ...s, pinCity: null }));
  }, []);

  /** Focus a hub for market intel without opening Flights. */
  const watchDest = useCallback((focusDest) => {
    markInteracted();
    setState((s) => ({
      ...s,
      focusDest: focusDest || '',
      query: '',
      tab: 'market',
      page: null,
      pinCity: null,
    }));
  }, [markInteracted]);

  const setFilter = useCallback((filter) => setState((s) => ({ ...s, filter })), []);
  const closeSheet = useCallback(() => setState((s) => ({
    ...s, sheet: null, selInv: null, invQty: 1, overweightNote: s.sheet === 'sell' ? '' : s.overweightNote,
  })), []);
  const startGame = useCallback(() => {
    markInteracted();
    setState((s) => ({ ...s, intro: false }));
  }, [markInteracted]);
  const setRot = useCallback((rot) => {
    markInteracted();
    setState((s) => ({ ...s, rot }));
  }, [markInteracted]);
  const setDragging = useCallback((dragging) => {
    if (dragging) markInteracted();
    setState((s) => ({ ...s, dragging }));
  }, [markInteracted]);
  const toggleOpt = useCallback((key) => {
    markInteracted();
    setState((s) => ({ ...s, [key]: !s[key] }));
  }, [markInteracted]);

  const openProduct = useCallback((id) => setState((s) => ({
    ...s, sheet: 'product', selId: id, qty: 1, slot: 'bag',
  })), []);

  const openFlight = useCallback((fl) => setState((s) => ({
    ...s, sheet: 'flight', selFlight: fl, cabin: 'economy', addon: '',
  })), []);

  const openFF = useCallback(() => {
    if (!stateRef.current.ticket) return;
    setState((s) => ({ ...s, sheet: 'ff' }));
  }, []);

  const openSell = useCallback(() => setState((s) => ({ ...s, sheet: 'sell' })), []);

  const manageInBags = useCallback(() => {
    setState((s) => ({
      ...s,
      sheet: null,
      selInv: null,
      invQty: 1,
      overweightNote: '',
      tab: 'bags',
      page: null,
      query: '',
    }));
  }, []);

  const openInvItem = useCallback((item) => {
    if (!item) return;
    setState((s) => ({
      ...s,
      sheet: 'inv',
      selInv: { id: item.id, slot: item.slot },
      invQty: 1,
    }));
  }, []);

  const setQty = useCallback((qty) => setState((s) => ({ ...s, qty: Math.max(1, qty) })), []);
  const setInvQty = useCallback((qty) => setState((s) => {
    const idx = findInv(s.inv, s.selInv);
    const max = idx >= 0 ? s.inv[idx].n : 1;
    return { ...s, invQty: Math.max(1, Math.min(max, qty)) };
  }), []);
  const setSlot = useCallback((slot) => setState((s) => ({ ...s, slot })), []);
  const setCabin = useCallback((cabin) => setState((s) => ({ ...s, cabin })), []);
  const setAddon = useCallback((addon) => setState((s) => ({ ...s, addon })), []);

  const cancelTicket = useCallback(() => {
    markInteracted();
    setState((s) => {
      if (!s.ticket || s.cut) return s;
      return {
        ...s,
        ticket: null,
        minsToDep: 0,
        called: false,
        bagLimit: DEFAULT_BAG_LIMIT,
        sheet: null,
      };
    });
    flyingRef.current = false;
    calledEdgeRef.current = false;
    buzz('Ticket cancelled — baggage allowance reset', 'ok');
  }, [buzz, markInteracted]);

  const buy = useCallback(() => {
    markInteracted();
    let result = null;
    setState((st) => {
      const p = PRODUCTS[st.selId];
      if (!p) return st;
      const n = st.qty;
      const slot = st.slot;
      const unit = priceAt(p.id, st.city);
      const cost = unit * n;
      const wt = p.w * n;
      if (cost > st.cash) {
        result = { ok: false, msg: `Not enough cash — short ${money(cost - st.cash)}`, kind: 'bad' };
        return st;
      }
      const bagKgNow = bagUsed(st.inv);
      const cargoKgNow = cargoUsed(st.inv);
      const cap = slot === 'bag' ? st.bagLimit : st.cargoCap;
      const used = slot === 'bag' ? bagKgNow : cargoKgNow;
      if (used + wt > cap) {
        result = {
          ok: false,
          msg: `Over the ${slot === 'bag' ? 'carry-on' : 'cargo'} limit by ${(used + wt - cap).toFixed(1)} kg`,
          kind: 'bad',
        };
        return st;
      }
      const inv = st.inv.slice();
      const at = inv.findIndex((i) => i.id === p.id && i.slot === slot);
      if (at >= 0) {
        const prev = inv[at];
        const totalN = prev.n + n;
        inv[at] = {
          ...prev,
          n: totalN,
          cost: (prev.cost * prev.n + unit * n) / totalN,
        };
      } else {
        inv.push({ id: p.id, name: p.name, icon: p.icon, w: p.w, n, slot, cost: unit });
      }
      const here = CITIES[st.city];
      const entry = {
        icon: p.icon,
        title: `Bought ${n} × ${p.name}`,
        sub: `${here.name} · ${fmtClock(cityMinutes(st.gameMin, st.city), st.opt24h)}`,
        amount: `−${money(cost)}`,
        color: '#E05555',
        t: st.gameMin,
      };
      result = { ok: true, msg: `Bought ${n} × ${p.name} · ${money(cost)}`, kind: 'ok' };
      const next = {
        ...st,
        inv,
        cash: st.cash - cost,
        sheet: null,
        qty: 1,
        cargoLots: st.cargoLots + (slot === 'cargo' ? n : 0),
        log: [entry].concat(st.log).slice(0, 40),
      };
      next.unlockedAch = announceAchievements(st.unlockedAch || [], computeStats(next));
      return next;
    });
    if (result?.ok) click();
    if (result) setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [announceAchievements, buzz, click, markInteracted]);

  const buyTicket = useCallback(() => {
    markInteracted();
    let result = null;
    setState((st) => {
      if (st.ticket) {
        result = { ok: false, msg: 'Cancel your current ticket first', kind: 'bad' };
        return st;
      }
      const fl = st.selFlight;
      if (!fl) return st;
      const add = ADDONS.find((a) => a.k === st.addon) || ADDONS[0];
      const total = (st.cabin === 'economy' ? fl.econ : fl.biz) + add.price;
      if (total > st.cash) {
        result = { ok: false, msg: 'Not enough cash for this fare', kind: 'bad' };
        return st;
      }
      const from = CITIES[st.city];
      const to = CITIES[fl.toId];
      const kg = add.k === 'light' ? 10 : add.k === 'standard' ? 20 : add.k === 'heavy' ? 50 : 0;
      const wait = waitUntilDep(st.gameMin, st.city, fl.depMin);
      const entry = {
        icon: 'assets/ic_flight.webp',
        title: `Booked ${fl.no}`,
        sub: `${from.iata} → ${to.iata} · ${st.cabin === 'economy' ? 'Economy' : 'Business'}`,
        amount: `−${money(total)}`,
        color: '#E05555',
        t: st.gameMin,
      };
      result = { ok: true, msg: `Ticket booked · ${fl.no} to ${to.name}`, kind: 'ok' };
      flyingRef.current = false;
      calledEdgeRef.current = false;
      return {
        ...st,
        cash: st.cash - total,
        sheet: null,
        tab: 'globe',
        page: null,
        called: false,
        focusDest: fl.toId,
        bagLimit: DEFAULT_BAG_LIMIT + kg,
        ticket: {
          no: fl.no,
          from: from.iata,
          to: to.iata,
          toId: fl.toId,
          cabin: st.cabin,
          km: fl.km,
          dur: fl.dur,
          mins: fl.mins,
          extraKg: kg,
        },
        minsToDep: wait,
        log: [entry].concat(st.log).slice(0, 40),
      };
    });
    if (result?.ok) click('sfx_ticket');
    if (result) setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [buzz, click, markInteracted]);

  const sellAll = useCallback(() => {
    markInteracted();
    let result = null;
    setState((s) => {
      if (!s.inv.length) return s;
      const d = sellData(s.inv, s.city);
      const here = CITIES[s.city];
      const entry = {
        icon: 'assets/ic_market.webp',
        title: `Sold ${d.rows.length} ${d.rows.length === 1 ? 'lot' : 'lots'}`,
        sub: `${here.name} · ${fmtClock(cityMinutes(s.gameMin, s.city), s.opt24h)}`,
        amount: `${d.net >= 0 ? '+' : '−'}${money(Math.abs(d.net))}`,
        color: d.net >= 0 ? '#3CB8A4' : '#E05555',
        t: s.gameMin,
      };
      result = d;
      const next = {
        ...s,
        cash: s.cash + d.gross,
        inv: [],
        sheet: null,
        selInv: null,
        lastSale: d.net,
        profit: s.profit + Math.max(0, d.net),
        profitable: s.profitable + (d.net > 0 ? 1 : 0),
        log: [entry].concat(s.log).slice(0, 40),
        overweightNote: '',
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return next;
    });
    if (!result) return;
    click(result.net >= 0 ? 'sfx_profit' : 'sfx_loss');
    if (result.net >= 0) setTimeout(() => buzz(`Nice trade! ${money(result.net)} profit`, 'ok'), 0);
    else setTimeout(() => buzz(`Rough run — ${money(-result.net)} down. Next leg pays it back.`, 'bad'), 0);
  }, [announceAchievements, buzz, click, markInteracted]);

  const sellQty = useCallback((n) => {
    markInteracted();
    let result = null;
    setState((s) => {
      const idx = findInv(s.inv, s.selInv);
      if (idx < 0) return s;
      const item = s.inv[idx];
      const qty = Math.min(Math.max(1, n || s.invQty), item.n);
      const unit = priceAt(item.id, s.city);
      const gross = unit * qty;
      const net = gross - item.cost * qty;
      const inv = s.inv.slice();
      if (qty >= item.n) inv.splice(idx, 1);
      else inv[idx] = { ...item, n: item.n - qty };
      const here = CITIES[s.city];
      const entry = {
        icon: item.icon,
        title: `Sold ${qty} × ${item.name}`,
        sub: `${here.name} · ${fmtClock(cityMinutes(s.gameMin, s.city), s.opt24h)}`,
        amount: `${net >= 0 ? '+' : '−'}${money(Math.abs(net))}`,
        color: net >= 0 ? '#3CB8A4' : '#E05555',
        t: s.gameMin,
      };
      result = { net, msg: `Sold ${qty} × ${item.name} · ${money(gross)}`, kind: net >= 0 ? 'ok' : 'bad' };
      const next = {
        ...s,
        cash: s.cash + gross,
        inv,
        sheet: null,
        selInv: null,
        invQty: 1,
        lastSale: net,
        profit: s.profit + Math.max(0, net),
        profitable: s.profitable + (net > 0 ? 1 : 0),
        log: [entry].concat(s.log).slice(0, 40),
        overweightNote: (() => {
          const over = Math.max(0, bagUsed(inv) - DEFAULT_BAG_LIMIT);
          return over > 0
            ? `Carry-on over by ${over.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`
            : '';
        })(),
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return next;
    });
    if (!result) return;
    click(result.net >= 0 ? 'sfx_profit' : 'sfx_loss');
    setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [announceAchievements, buzz, click, markInteracted]);

  const discardQty = useCallback((n) => {
    const s0 = stateRef.current;
    const idx0 = findInv(s0.inv, s0.selInv);
    if (idx0 < 0) return;
    const item0 = s0.inv[idx0];
    const qty0 = Math.min(Math.max(1, n || s0.invQty), item0.n);
    Alert.alert(
      'Discard goods?',
      `Throw away ${qty0} × ${item0.name}? No refund.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Discard',
          style: 'destructive',
          onPress: () => {
            markInteracted();
            setState((s) => {
              const idx = findInv(s.inv, s.selInv);
              if (idx < 0) return s;
              const item = s.inv[idx];
              const qty = Math.min(Math.max(1, n || s.invQty), item.n);
              const inv = s.inv.slice();
              if (qty >= item.n) inv.splice(idx, 1);
              else inv[idx] = { ...item, n: item.n - qty };
              const over = Math.max(0, bagUsed(inv) - DEFAULT_BAG_LIMIT);
              return {
                ...s,
                inv,
                sheet: null,
                selInv: null,
                invQty: 1,
                overweightNote: over > 0
                  ? `Carry-on over by ${over.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`
                  : '',
              };
            });
            buzz(`Discarded ${qty0} × ${item0.name}`, 'bad');
          },
        },
      ],
    );
  }, [buzz, markInteracted]);

  const moveInvSlot = useCallback(() => {
    markInteracted();
    let result = null;
    setState((s) => {
      const idx = findInv(s.inv, s.selInv);
      if (idx < 0) return s;
      const item = s.inv[idx];
      const qty = Math.min(Math.max(1, s.invQty), item.n);
      const dest = item.slot === 'bag' ? 'cargo' : 'bag';
      const wt = item.w * qty;
      const destUsed = dest === 'bag' ? bagUsed(s.inv) : cargoUsed(s.inv);
      const cap = dest === 'bag' ? s.bagLimit : s.cargoCap;
      if (destUsed + wt > cap) {
        result = {
          ok: false,
          msg: `Not enough ${dest === 'bag' ? 'carry-on' : 'cargo'} space (${(destUsed + wt - cap).toFixed(1)} kg over)`,
          kind: 'bad',
        };
        return s;
      }
      const inv = s.inv.slice();
      if (qty >= item.n) inv.splice(idx, 1);
      else inv[idx] = { ...item, n: item.n - qty };
      const at = inv.findIndex((i) => i.id === item.id && i.slot === dest);
      if (at >= 0) {
        const prev = inv[at];
        const totalN = prev.n + qty;
        inv[at] = {
          ...prev,
          n: totalN,
          cost: (prev.cost * prev.n + item.cost * qty) / totalN,
        };
      } else {
        inv.push({
          id: item.id,
          name: item.name,
          icon: item.icon,
          w: item.w,
          n: qty,
          slot: dest,
          cost: item.cost,
        });
      }
      result = {
        ok: true,
        msg: `Moved ${qty} × ${item.name} to ${dest === 'bag' ? 'carry-on' : 'cargo'}`,
        kind: 'ok',
      };
      return {
        ...s,
        inv,
        sheet: null,
        selInv: null,
        invQty: 1,
        cargoLots: s.cargoLots + (dest === 'cargo' ? qty : 0),
      };
    });
    if (result) setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [buzz, markInteracted]);

  const saveNow = useCallback(() => {
    markInteracted();
    const savedAt = stateRef.current.gameMin;
    setState((s) => ({ ...s, savedAt }));
    const slice = serializeSave({ ...stateRef.current, savedAt });
    AsyncStorage.setItem(SAVE_KEY, JSON.stringify(slice)).catch(() => {});
    buzz('Progress saved to slot 1', 'ok');
  }, [buzz, markInteracted]);

  const restart = useCallback(() => {
    markInteracted();
    clearTimeout(cutRef.current);
    flyingRef.current = false;
    calledEdgeRef.current = false;
    setState((s) => ({
      ...initialState(),
      optHaptics: s.optHaptics,
      optPush: s.optPush,
      optSound: s.optSound,
      opt24h: s.opt24h,
      optReduce: s.optReduce,
    }));
    AsyncStorage.removeItem(SAVE_KEY).catch(() => {});
    buzz('New run — back in Istanbul', 'ok');
  }, [buzz, markInteracted]);

  const productRows = useMemo(() => {
    const baseIds = state.seg === 'local' ? localIds : importIds;
    const ids = destId ? sortByDestProfit(baseIds, state.city, destId) : baseIds;
    return ids.map((id) => {
      const q = PRODUCTS[id];
      const unit = priceAt(id, state.city);
      const tag = intel(id, state.city, destId);
      const spark = priceSparkline(id, state.city, 5);
      const destPrice = destId ? priceAt(id, destId) : null;
      return {
        id,
        name: q.name,
        icon: q.icon,
        buy: money(unit),
        weight: `${q.w.toFixed(1)} kg`,
        meta: destPrice != null
          ? `${q.category} · here ${money(unit)} · there ${money(destPrice)}`
          : `${q.category} · local price ${money(unit)}`,
        origin: q.home === state.city ? 'Local' : 'Import',
        tag: tag.text,
        tagKind: tag.kind,
        spark,
      };
    });
  }, [state.seg, state.city, destId, localIds, importIds]);

  const sortedFlights = useMemo(() => {
    const localNow = ((cityMinutes(state.gameMin, state.city) % 1440) + 1440) % 1440;
    // True next departure by local clock (independent of focus / filter order).
    const nextKey = [...routes]
      .filter((f) => f.depMin >= localNow)
      .sort((a, b) => a.depMin - b.depMin)[0];
    const nextId = nextKey ? `${nextKey.no}-${nextKey.toId}-${nextKey.depMin}` : null;

    let list = [...routes].sort((a, b) => {
      if (state.focusDest) {
        const af = a.toId === state.focusDest ? 0 : 1;
        const bf = b.toId === state.focusDest ? 0 : 1;
        if (af !== bf) return af - bf;
      }
      const ap = a.depMin < localNow ? 1 : 0;
      const bp = b.depMin < localNow ? 1 : 0;
      if (ap !== bp) return ap - bp;
      if (state.filter === 'price') return a.econ - b.econ;
      if (state.filter === 'duration') return a.mins - b.mins;
      if (state.filter === 'unvisited') {
        const av = state.visited.includes(a.toId) ? 1 : 0;
        const bv = state.visited.includes(b.toId) ? 1 : 0;
        return av - bv || a.depMin - b.depMin;
      }
      if (state.filter === 'biz') return a.biz - b.biz;
      return a.depMin - b.depMin;
    }).slice(0, 12);

    return list.map((fl) => {
      const past = fl.depMin < localNow;
      const key = `${fl.no}-${fl.toId}-${fl.depMin}`;
      return {
        ...fl,
        dep: fmtClock(fl.depMin, state.opt24h),
        arr: fmtClock(fl.depMin + fl.mins + (CITIES[fl.toId].tz - city.tz) * 60, state.opt24h),
        from: city.iata,
        to: CITIES[fl.toId].iata,
        toName: CITIES[fl.toId].name,
        unvisited: !state.visited.includes(fl.toId),
        focused: fl.toId === state.focusDest,
        past,
        isNext: key === nextId,
      };
    });
  }, [routes, state.filter, state.visited, state.focusDest, state.opt24h, state.gameMin, state.city, city]);

  const q = state.query.trim().toLowerCase();
  const searchResults = q
    ? CIDS.filter((k) => k !== state.city)
      .map((k) => CITIES[k])
      .filter((c) => `${c.iata} ${c.icao} ${c.airport} ${c.name} ${c.country}`.toLowerCase().includes(q))
      .slice(0, 6)
    : [];

  const selProduct = state.selId ? PRODUCTS[state.selId] : null;
  const unitHere = selProduct ? priceAt(selProduct.id, state.city) : 0;
  const costTotal = unitHere * state.qty;
  const wtTotal = selProduct ? selProduct.w * state.qty : 0;
  const slotUsed = state.slot === 'bag' ? bagKg : cargoKg;
  const slotCap = state.slot === 'bag' ? state.bagLimit : state.cargoCap;
  const over = slotUsed + wtTotal > slotCap;
  const canBuy = !!selProduct && !over && costTotal <= state.cash;
  const add = ADDONS.find((a) => a.k === state.addon) || ADDONS[0];
  const addonKg = add.k === 'light' ? 10 : add.k === 'standard' ? 20 : add.k === 'heavy' ? 50 : 0;
  const bookingBagLimit = state.ticket ? state.bagLimit : DEFAULT_BAG_LIMIT + addonKg;
  const fareTotal = state.selFlight
    ? (state.cabin === 'economy' ? state.selFlight.econ : state.selFlight.biz) + add.price
    : 0;
  const canBook = !!state.selFlight && !state.ticket && fareTotal <= state.cash;
  const bagOverKg = Math.max(0, bagKg - bookingBagLimit);
  const selInvItem = (() => {
    const idx = findInv(state.inv, state.selInv);
    return idx >= 0 ? state.inv[idx] : null;
  })();
  const invUnit = selInvItem ? priceAt(selInvItem.id, state.city) : 0;
  const invGross = selInvItem ? invUnit * state.invQty : 0;

  return {
    state,
    loaded,
    city,
    destId,
    bagKg,
    cargoKg,
    bagOverKg,
    stats,
    sell,
    productRows,
    sortedFlights,
    routes,
    destinations,
    searchResults,
    clockText: clockLabel(state.gameMin, state.opt24h),
    localTime: fmtClock(cityMinutes(state.gameMin, state.city), state.opt24h),
    bagText: `${bagKg.toFixed(1)} / ${state.bagLimit} kg`,
    cargoText: `${cargoKg.toFixed(1)} / ${state.cargoCap} kg`,
    saveSub: `Last saved ${state.savedAt ? `${hm(state.gameMin - state.savedAt)} ago` : 'at takeoff'} · slot 1`,
    selProduct,
    selInvItem,
    invUnit,
    invGross,
    unitHere,
    costTotal,
    wtTotal,
    over,
    canBuy,
    canBook,
    slotUsed,
    slotCap,
    fareTotal,
    add,
    hm,
    hhmm,
    money,
    priceAt,
    setTab,
    setPage,
    setSeg,
    setQuery,
    setFocusDest,
    watchDest,
    openPinCity,
    closePinCity,
    setFilter,
    setRot,
    setDragging,
    toggleOpt,
    closeSheet,
    startGame,
    openProduct,
    openFlight,
    openFF,
    openSell,
    openInvItem,
    manageInBags,
    setQty,
    setInvQty,
    setSlot,
    setCabin,
    setAddon,
    buy,
    buyTicket,
    cancelTicket,
    runCutscene,
    sellAll,
    sellQty,
    discardQty,
    moveInvSlot,
    saveNow,
    restart,
    buzz,
  };
}
