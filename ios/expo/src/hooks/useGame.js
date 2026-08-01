import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import {
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
  destinationsFrom,
  routesFrom,
  sellData,
} from '../gameLogic';

const SAVE_KEY = 'airborne-trader/slot-1';

/** Fields that survive a reload; transient UI state is rebuilt fresh. */
const PERSIST = [
  'cash', 'bagLimit', 'cargoCap', 'inv', 'ticket', 'minsToDep', 'gameMin',
  'city', 'visited', 'log', 'legs', 'bizLegs', 'cargoLots', 'profitable',
  'profit', 'km', 'savedAt', 'intro',
  'optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce',
];

const initialState = () => ({
  tab: 'globe',
  page: null,
  seg: 'local',
  query: '',
  sheet: null,
  selId: null,
  selFlight: null,
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
  optHaptics: true,
  optPush: true,
  optSound: true,
  opt24h: true,
  optReduce: false,
});

export function useGame() {
  const [state, setState] = useState(initialState);
  const [loaded, setLoaded] = useState(false);
  const cutRef = useRef(null);
  const toastRef = useRef(null);
  const saveRef = useRef(null);

  const tap = useCallback((kind) => {
    if (!state.optHaptics) return;
    const style = kind === 'bad'
      ? Haptics.NotificationFeedbackType.Warning
      : Haptics.NotificationFeedbackType.Success;
    Haptics.notificationAsync(style).catch(() => {});
  }, [state.optHaptics]);

  const buzz = useCallback((message, kind = 'ok') => {
    clearTimeout(toastRef.current);
    setState((s) => ({ ...s, toast: message, toastKind: kind }));
    toastRef.current = setTimeout(() => {
      setState((s) => ({ ...s, toast: null }));
    }, 2400);
    tap(kind);
  }, [tap]);

  /* ---- save / restore ------------------------------------------- */

  useEffect(() => {
    let alive = true;
    AsyncStorage.getItem(SAVE_KEY)
      .then((raw) => {
        if (!alive || !raw) return;
        const saved = JSON.parse(raw);
        setState((s) => {
          const next = { ...s };
          PERSIST.forEach((k) => {
            if (saved[k] !== undefined) next[k] = saved[k];
          });
          if (!CITIES[next.city]) return s;
          return next;
        });
      })
      .catch(() => {})
      .finally(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    if (!loaded) return undefined;
    clearTimeout(saveRef.current);
    saveRef.current = setTimeout(() => {
      const slice = {};
      PERSIST.forEach((k) => { slice[k] = state[k]; });
      AsyncStorage.setItem(SAVE_KEY, JSON.stringify(slice)).catch(() => {});
    }, 700);
    return () => clearTimeout(saveRef.current);
  }, [state, loaded]);

  /* ---- world clock ---------------------------------------------- */

  useEffect(() => {
    const t = setInterval(() => {
      setState((s) => {
        if (s.intro || s.cut) return s;
        const minsToDep = s.ticket ? Math.max(0, s.minsToDep - 6) : 0;
        return {
          ...s,
          gameMin: s.gameMin + 6,
          minsToDep,
          called: s.ticket ? s.called || minsToDep <= 30 : false,
        };
      });
    }, 1000);
    return () => {
      clearInterval(t);
      clearTimeout(cutRef.current);
      clearTimeout(toastRef.current);
    };
  }, []);

  const called = state.called;
  const pushOn = state.optPush;
  const ticketNo = state.ticket ? state.ticket.no : null;
  useEffect(() => {
    if (called && pushOn && ticketNo) {
      buzz(`Boarding call · ${ticketNo} · gate closing`, 'ok');
    }
  }, [called, pushOn, ticketNo, buzz]);

  const city = CITIES[state.city];
  const destId = state.ticket ? state.ticket.toId : '';
  const bagKg = bagUsed(state.inv);
  const cargoKg = cargoUsed(state.inv);
  const localIds = useMemo(() => locals(state.city), [state.city]);
  const importIds = useMemo(() => imports(state.city), [state.city]);
  const routes = useMemo(() => routesFrom(state.city), [state.city]);
  const destinations = useMemo(() => destinationsFrom(state.city), [state.city]);
  const stats = useMemo(() => computeStats(state), [state]);
  const sell = useMemo(() => sellData(state.inv, state.city), [state.inv, state.city]);

  const setTab = (tab) => setState((s) => ({ ...s, tab, page: null, query: '' }));
  const setPage = (page) => setState((s) => ({ ...s, page }));
  const setSeg = (seg) => setState((s) => ({ ...s, seg }));
  const setQuery = (query) => setState((s) => ({ ...s, query }));
  const setFilter = (filter) => setState((s) => ({ ...s, filter }));
  const closeSheet = () => setState((s) => ({ ...s, sheet: null }));
  const startGame = () => setState((s) => ({ ...s, intro: false }));
  const setRot = (rot) => setState((s) => ({ ...s, rot }));
  const setDragging = (dragging) => setState((s) => ({ ...s, dragging }));
  const toggleOpt = (key) => setState((s) => ({ ...s, [key]: !s[key] }));

  const logAdd = (icon, title, sub, amount, color) => setState((s) => ({
    ...s,
    log: [{ icon, title, sub, amount, color, t: s.gameMin }].concat(s.log).slice(0, 40),
  }));

  const openProduct = (id) => setState((s) => ({
    ...s, sheet: 'product', selId: id, qty: 1, slot: 'bag',
  }));

  const openFlight = (fl) => setState((s) => ({
    ...s, sheet: 'flight', selFlight: fl, cabin: 'economy', addon: '',
  }));

  const openFF = () => {
    if (!state.ticket) return;
    setState((s) => ({ ...s, sheet: 'ff' }));
  };

  const openSell = () => setState((s) => ({ ...s, sheet: 'sell' }));
  const setQty = (qty) => setState((s) => ({ ...s, qty: Math.max(1, qty) }));
  const setSlot = (slot) => setState((s) => ({ ...s, slot }));
  const setCabin = (cabin) => setState((s) => ({ ...s, cabin }));
  const setAddon = (addon) => setState((s) => ({ ...s, addon }));

  const buy = () => {
    const p = PRODUCTS[state.selId];
    if (!p) return;
    const n = state.qty;
    const slot = state.slot;
    const unit = priceAt(p.id, state.city);
    const cost = unit * n;
    const wt = p.w * n;
    if (cost > state.cash) {
      buzz(`Not enough cash — short ${money(cost - state.cash)}`, 'bad');
      return;
    }
    const cap = slot === 'bag' ? state.bagLimit : state.cargoCap;
    const used = slot === 'bag' ? bagKg : cargoKg;
    if (used + wt > cap) {
      buzz(`Over the ${slot === 'bag' ? 'carry-on' : 'cargo'} limit by ${(used + wt - cap).toFixed(1)} kg`, 'bad');
      return;
    }
    setState((st) => {
      const inv = st.inv.slice();
      const at = inv.findIndex((i) => i.id === p.id && i.slot === slot);
      if (at >= 0) inv[at] = { ...inv[at], n: inv[at].n + n };
      else inv.push({ id: p.id, name: p.name, icon: p.icon, w: p.w, n, slot, cost: unit });
      return {
        ...st,
        inv,
        cash: st.cash - cost,
        sheet: null,
        qty: 1,
        cargoLots: st.cargoLots + (slot === 'cargo' ? 1 : 0),
      };
    });
    logAdd(
      p.icon,
      `Bought ${n} × ${p.name}`,
      `${city.name} · ${fmtClock(cityMinutes(state.gameMin, state.city), state.opt24h)}`,
      `−${money(cost)}`,
      '#E05555',
    );
    buzz(`Bought ${n} × ${p.name} · ${money(cost)}`, 'ok');
  };

  const buyTicket = () => {
    const fl = state.selFlight;
    if (!fl) return;
    const add = ADDONS.find((a) => a.k === state.addon) || ADDONS[0];
    const total = (state.cabin === 'economy' ? fl.econ : fl.biz) + add.price;
    if (total > state.cash) {
      buzz('Not enough cash for this fare', 'bad');
      return;
    }
    const from = city;
    const to = CITIES[fl.toId];
    const kg = add.k === 'light' ? 10 : add.k === 'standard' ? 20 : add.k === 'heavy' ? 50 : 0;
    setState((st) => ({
      ...st,
      cash: st.cash - total,
      sheet: null,
      tab: 'globe',
      page: null,
      called: false,
      bagLimit: st.bagLimit + kg,
      ticket: {
        no: fl.no,
        from: from.iata,
        to: to.iata,
        toId: fl.toId,
        cabin: st.cabin,
        km: fl.km,
        dur: fl.dur,
        mins: fl.mins,
      },
      minsToDep: Math.max(30, fl.mins),
    }));
    logAdd(
      'assets/ic_flight.webp',
      `Booked ${fl.no}`,
      `${from.iata} → ${to.iata} · ${state.cabin === 'economy' ? 'Economy' : 'Business'}`,
      `−${money(total)}`,
      '#E05555',
    );
    buzz(`Ticket booked · ${fl.no} to ${to.name}`, 'ok');
  };

  const finishLanding = useCallback((ticket) => {
    const to = CITIES[ticket.toId];
    setState((s) => {
      const visited = s.visited.includes(ticket.toId) ? s.visited : [...s.visited, ticket.toId];
      const hasInv = s.inv.length > 0;
      const entry = {
        icon: 'assets/ic_flight.webp',
        title: `Landed in ${to.name}`,
        sub: `${ticket.no} · ${ticket.km.toLocaleString('en-US')} km`,
        amount: '',
        color: '#A8B8C8',
        t: s.gameMin,
      };
      return {
        ...s,
        cut: null,
        cutLine: '',
        ticket: null,
        minsToDep: 0,
        called: false,
        city: ticket.toId,
        rot: -to.lon,
        tab: 'globe',
        page: null,
        seg: 'local',
        visited,
        log: [entry].concat(s.log).slice(0, 40),
        gameMin: s.gameMin + s.minsToDep + ticket.mins,
        legs: s.legs + 1,
        km: s.km + ticket.km,
        bizLegs: s.bizLegs + (ticket.cabin === 'business' ? 1 : 0),
        sheet: hasInv ? 'sell' : null,
      };
    });
    buzz(`Landed in ${to.name}`, 'ok');
  }, [buzz]);

  const runCutscene = () => {
    const t = state.ticket;
    if (!t) return;
    const to = CITIES[t.toId];
    const steps = CUTSCENE_ART.map((step, i) => (
      i === 2 ? { ...step, title: to.name } : step
    ));
    const dur = state.optReduce ? 600 : 1700;
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
  };

  const sellAll = () => {
    const d = sellData(state.inv, state.city);
    setState((s) => ({
      ...s,
      cash: s.cash + d.gross,
      inv: [],
      sheet: null,
      lastSale: d.net,
      profit: s.profit + Math.max(0, d.net),
      profitable: s.profitable + (d.net > 0 ? 1 : 0),
    }));
    logAdd(
      'assets/ic_market.webp',
      `Sold ${d.rows.length} ${d.rows.length === 1 ? 'lot' : 'lots'}`,
      `${city.name} · ${fmtClock(cityMinutes(state.gameMin, state.city), state.opt24h)}`,
      `${d.net >= 0 ? '+' : '−'}${money(Math.abs(d.net))}`,
      d.net >= 0 ? '#3CB8A4' : '#E05555',
    );
    if (d.net >= 0) buzz(`Nice trade! ${money(d.net)} profit`, 'ok');
    else buzz(`Rough run — ${money(-d.net)} down. Next leg pays it back.`, 'bad');
  };

  const saveNow = () => {
    setState((s) => ({ ...s, savedAt: s.gameMin }));
    buzz('Progress saved to slot 1', 'ok');
  };

  const restart = () => {
    clearTimeout(cutRef.current);
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
  };

  const productRows = (state.seg === 'local' ? localIds : importIds).map((id) => {
    const q = PRODUCTS[id];
    const unit = priceAt(id, state.city);
    const tag = intel(id, state.city, destId);
    return {
      id,
      name: q.name,
      icon: q.icon,
      buy: money(unit),
      weight: `${q.w.toFixed(1)} kg`,
      meta: `${q.category} · sells here ${money(Math.round(unit * 0.92))}`,
      origin: q.home === state.city ? 'Local' : 'Import',
      tag: tag.text,
      tagKind: tag.kind,
    };
  });

  const sortedFlights = [...routes]
    .sort((a, b) => {
      if (state.filter === 'price') return a.econ - b.econ;
      if (state.filter === 'duration') return a.mins - b.mins;
      if (state.filter === 'unvisited') {
        const av = state.visited.includes(a.toId) ? 1 : 0;
        const bv = state.visited.includes(b.toId) ? 1 : 0;
        return av - bv || a.depMin - b.depMin;
      }
      if (state.filter === 'biz') return a.biz - b.biz;
      return a.depMin - b.depMin;
    })
    .slice(0, 9)
    .map((fl) => ({
      ...fl,
      dep: fmtClock(fl.depMin, state.opt24h),
      arr: fmtClock(fl.depMin + fl.mins + (CITIES[fl.toId].tz - city.tz) * 60, state.opt24h),
      from: city.iata,
      to: CITIES[fl.toId].iata,
      toName: CITIES[fl.toId].name,
      unvisited: !state.visited.includes(fl.toId),
    }));

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
  const add = ADDONS.find((a) => a.k === state.addon) || ADDONS[0];
  const fareTotal = state.selFlight
    ? (state.cabin === 'economy' ? state.selFlight.econ : state.selFlight.biz) + add.price
    : 0;

  return {
    state,
    city,
    destId,
    bagKg,
    cargoKg,
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
    unitHere,
    costTotal,
    wtTotal,
    over,
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
    setQty,
    setSlot,
    setCabin,
    setAddon,
    buy,
    buyTicket,
    runCutscene,
    sellAll,
    saveNow,
    restart,
    buzz,
  };
}
