import { freshMerchant, refreshOffers, expireMerchant, acceptOrder, abandonOrder, equipAbility, dismissAbility, merchantArrival, merchantUnit, merchantFare, merchantBaggage, purchaseTotal, saleQuote, merchantSellData, recordMerchantSale, consumeDeal, journeyEvent, resolveJourney } from '../merchantLogic';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, AppState as NativeAppState, NativeModules } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import {
  ACHIEVEMENTS,
  ADDONS,
  CIDS,
  CITIES,
  CUTSCENE_ART,
  DEFAULT_BAG_LIMIT,
  MOBILE_BALANCE,
  DEFAULT_CARGO_CAP,
  NOTE_TEXT,
  PRODUCTS,
  SOURCES,
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
  marketPriceAt,
  money,
  pad,
  priceSparkline,
  destinationsFrom,
  routesFrom,
  routeOpportunities,
  sellData,
  sortByDestProfit,
  visibleFlightBoard,
  waitUntilDep,
} from '../gameLogic';
import { EVENT_BY_ID } from '../eventData';
import {
  activeEvents,
  eventGameDay,
  eventImpactText,
  localizedEvent,
  quoteFlightForEvents,
  unseenArrivalEvent,
} from '../eventLogic';
import { createStateStore } from '../stateStore';
import { advanceWorldClock } from '../worldClock';
import { readSave, resetSave, writeSave } from '../saveStorage';
import { travelCharge, saleCredit, refundTravel } from '../accounting';
import { playSfx } from '../audio';
import { f as i18nF, t as i18nT } from '../i18n';
import { serializeSave } from '../saveGame';
import {
  createTripForecast,
  landTripForecast,
  recordTripDiscard,
  recordTripSale,
} from '../tripRecap';

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
  tripRecap: null,
  merchant: freshMerchant(),
  journey: null,
  intro: true,
  legs: 0,
  bizLegs: 0,
  cargoLots: 0,
  profitable: 0,
  profit: 0,
  travelExpenses: 0,
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
  locale: 'en',
  fontScale: 1,
  colorBlind: 'off',
  themeMode: 'dark',
  eventSeed: `run:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`,
  seenEventEpisodes: [],
  eventPopup: null,
  eventReturnSheet: null,
});

function unlockedIds(stats, unlocked = []) {
  return ACHIEVEMENTS
    .filter((a) => unlocked.includes(a.id) || (stats[a.stat] || 0) >= a.goal)
    .map((a) => a.id);
}

/** Best-effort device language without expo-localization. iOS: SettingsManager,
 *  Android: I18nManager. Returns 'zh' or 'en'; never throws. */
function systemLocale() {
  try {
    const sm = NativeModules.SettingsManager;
    const settings = sm && sm.settings;
    const locale = (settings && (settings.AppleLocale || (settings.AppleLanguages && settings.AppleLanguages[0])))
      || (NativeModules.I18nManager && NativeModules.I18nManager.localeIdentifier)
      || '';
    return String(locale).toLowerCase().startsWith('zh') ? 'zh' : 'en';
  } catch (err) {
    return 'en';
  }
}

function findInv(inv, selInv) {
  if (!selInv) return -1;
  return inv.findIndex((i) => i.id === selInv.id && i.slot === selInv.slot);
}

export function useGame() {
  const [state, publishState] = useState(initialState);
  const storeRef = useRef(null);
  if (!storeRef.current) storeRef.current = createStateStore(state, publishState);
  const stateRef = storeRef.current;
  const setState = stateRef.set;
  const [loaded, setLoaded] = useState(false);
  const cutRef = useRef(null);
  const toastRef = useRef(null);
  const saveRef = useRef(null);
  const saveQueue = useRef(Promise.resolve());
  const loadedRef = useRef(false);
  const runGeneration = useRef(0);
  const flyingRef = useRef(false);
  const foregroundRef = useRef(true);
  const calledEdgeRef = useRef(false);
  const suspendAutosaveRef = useRef(false);
  const pendingAchRef = useRef([]);

  const loc = state.locale || 'en';
  /** Live-locale lookup helpers (read current locale via ref, safe inside callbacks). */
  const tr = useCallback((key, fallback) => i18nT(stateRef.current.locale || 'en', key, fallback), []);
  const trf = useCallback((key, vars, fallback) => i18nF(stateRef.current.locale || 'en', key, vars, fallback), []);
  /** Lookup helpers scoped to a state snapshot (for use inside setState updaters). */
  const stT = (st, key, fallback) => i18nT(st.locale || 'en', key, fallback);
  const stF = (st, key, vars, fallback) => i18nF(st.locale || 'en', key, vars, fallback);

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
      if (!stateRef.current.optHaptics) return;
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

  /** Called once per transaction; queue achievement feedback after commit. */
  const announceAchievements = useCallback((prevUnlocked, nextStats) => {
    const next = unlockedIds(nextStats, prevUnlocked);
    const fresh = next.filter((id) => !prevUnlocked.includes(id));
    if (fresh.length) pendingAchRef.current = pendingAchRef.current.concat(fresh);
    return next;
  }, []);

  const persist = useCallback(() => {
    if (!loadedRef.current || suspendAutosaveRef.current) return Promise.reject(new Error('Save not ready or protected'));
    const generation = runGeneration.current;
    const snapshot = { ...stateRef.current, savedAt: stateRef.current.gameMin };
    const payload = JSON.stringify(serializeSave(snapshot));
    const job = saveQueue.current.catch(() => {}).then(() => writeSave(AsyncStorage, payload));
    saveQueue.current = job;
    return job.then(() => {
      if (loadedRef.current && generation === runGeneration.current) setState((s) => ({ ...s, savedAt: snapshot.savedAt }));
    });
  }, []);

  /* ---- save / restore ------------------------------------------- */

  useEffect(() => {
    let alive = true;
    readSave(AsyncStorage, initialState())
      .then((result) => {
        if (!alive) return;
        if (result.ok) {
          setState({ ...stateRef.current, ...result.data });
          if (result.recovered) buzz(tr('msg.recovered', 'Recovered the previous saved progress.'), 'ok');
        } else if (result.reason === 'missing') {
          setState((s) => ({ ...s, locale: systemLocale() }));
        } else {
          suspendAutosaveRef.current = true;
          buzz(tr('msg.restore_protected', 'Save could not be loaded. Original files are protected; use New run to start again.'), 'bad');
        }
      })
      .catch(() => {
        if (!alive) return;
        suspendAutosaveRef.current = true;
        buzz(tr('msg.save_failed', 'Storage unavailable — progress has not been saved.'), 'bad');
      })
      .finally(() => { if (alive) { loadedRef.current = true; setLoaded(true); } });
    return () => { alive = false; loadedRef.current = false; };
  }, [buzz, tr]);

  // Only durable progress schedules a write; UI animation and toasts do not.
  const durablePayload = JSON.stringify({ ...serializeSave(state), savedAt: 0, gameMin: Math.floor(state.gameMin / 30) * 30, minsToDep: Math.ceil(state.minsToDep / 30) * 30 });
  useEffect(() => {
    if (!loaded || suspendAutosaveRef.current) return undefined;
    clearTimeout(saveRef.current);
    saveRef.current = setTimeout(() => { persist().catch(() => buzz(tr('msg.save_failed', 'Could not save progress'), 'bad')); }, 700);
    return () => clearTimeout(saveRef.current);
  }, [durablePayload, loaded, persist, buzz, tr]);

  useEffect(() => {
    if (!loaded) return undefined;
    const subscription = NativeAppState.addEventListener('change', (next) => {
      foregroundRef.current = next === 'active';
      if (next !== 'active') { clearTimeout(saveRef.current); persist().catch(() => {}); }
    });
    return () => subscription.remove();
  }, [loaded, persist]);

  // Flush achievement toasts outside setState updaters.
  useEffect(() => {
    const pending = pendingAchRef.current;
    if (!pending.length) return undefined;
    pendingAchRef.current = [];
    const first = ACHIEVEMENTS.find((a) => a.id === pending[0]);
    if (!first) return undefined;
    const t = setTimeout(() => {
      click('sfx_ach');
      buzz(trf('msg.ach_unlocked', { name: tr(`ach.${first.id}`, first.name) }, `Achievement unlocked — ${first.name}`), 'ok');
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
      const arrivalGameMin = s.gameMin + s.minsToDep + ticket.mins;
      const arrivalEvent = unseenArrivalEvent(
        activeEvents(arrivalGameMin, s.eventSeed),
        ticket.toId,
        s.seenEventEpisodes || [],
      );
      const showEvent = false;
      const seenEventEpisodes = showEvent
        ? [{
          episodeKey: arrivalEvent.episodeKey,
          eventId: arrivalEvent.id,
          startDay: arrivalEvent.startDay,
          seenAt: arrivalGameMin,
        }].concat(s.seenEventEpisodes || []).slice(0, 100)
        : (s.seenEventEpisodes || []);
      const entry = {
        icon: 'assets/ic_flight.webp',
        title: stF(s, 'log.landed', { name: stT(s, `city.${ticket.toId}`, to.name) }, `Landed in ${to.name}`),
        sub: stF(s, 'log.landed_sub', {
          no: ticket.no,
          km: stF(s, 'fmt.km', { n: ticket.km.toLocaleString('en-US') }, `${ticket.km.toLocaleString('en-US')} km`),
        }, `${ticket.no} · ${ticket.km.toLocaleString('en-US')} km`),
        amount: '',
        color: '#A8B8C8',
        t: arrivalGameMin,
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
        tab: hasInv ? 'market' : 'globe',
        page: null,
        seg: 'local',
        focusDest: '',
        visited,
        log: [entry].concat(s.log).slice(0, 40),
        gameMin: arrivalGameMin,
        legs: s.legs + 1,
        km: s.km + ticket.km,
        bizLegs: s.bizLegs + (ticket.cabin === 'business' ? 1 : 0),
        sheet: null,
        eventPopup: showEvent ? arrivalEvent : null,
        eventReturnSheet: showEvent && hasInv ? 'sell' : (showEvent && ticket.tripForecast ? 'tripRecap' : null),
        tripRecap: landTripForecast(ticket.tripForecast, arrivalGameMin),
        seenEventEpisodes,
        overweightNote: overweightKg > 0
          ? stF(s, 'msg.overweight_note', { n: overweightKg.toFixed(1) }, `Carry-on over by ${overweightKg.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`)
          : '',
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return merchantArrival(next);
    });
    flyingRef.current = false;
    calledEdgeRef.current = false;
    buzz(trf('msg.landed', { name: tr(`city.${ticket.toId}`, to.name) }, `Landed in ${to.name}`), 'ok');
    if (bagNow > allowance) {
      setTimeout(() => {
        buzz(trf('msg.allowance_ok', { n: allowance, base: DEFAULT_BAG_LIMIT }, `Your ${allowance} kg allowance covered this leg; base carry-on is ${DEFAULT_BAG_LIMIT} kg again.`), 'ok');
      }, 1200);
    }
    if (overweightKg > 0) {
      setTimeout(() => {
        buzz(trf('msg.overweight', { n: overweightKg.toFixed(1) }, `Carry-on over by ${overweightKg.toFixed(1)} kg — sell or discard in Bags.`), 'bad');
      }, 2600);
    }
  }, [announceAchievements, buzz]);

  const runCutscene = useCallback(() => {
    const current = stateRef.current;
    const originalTicket = current.ticket;
    const forecastMinute = current.gameMin + Math.max(0, current.minsToDep);
    const forecastEvents = activeEvents(forecastMinute, current.eventSeed);
    const t = originalTicket && CITIES[originalTicket.toId]
      ? {
        ...originalTicket,
        tripForecast: originalTicket.tripForecast || createTripForecast({
          from: originalTicket.from,
          to: originalTicket.toId,
          inventory: current.inv,
          fare: originalTicket.fareCost ?? originalTicket.totalPaid,
          baggage: originalTicket.baggageCost ?? 0,
          quote: (id, cityId) => merchantUnit(current, id, cityId, 'sell', forecastEvents),
        }),
      }
      : originalTicket;
    if (!t || stateRef.current.cut || flyingRef.current) return;
    const to = CITIES[t.toId];
    if (!to) {
      buzz(tr('msg.ticket_missing', 'Ticket destination missing — ticket cleared'), 'bad');
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
    const l = stateRef.current.locale || 'en';
    const steps = CUTSCENE_ART.map((step, i) => ({
      ...step,
      phase: i18nT(l, `cut.${step.phase}`, step.phase),
      title: i === 2
        ? i18nT(l, `city.${t.toId}`, to.name)
        : i18nT(l, `cut.${step.phase}.title`, step.title),
    }));
    const dur = stateRef.current.optReduce ? 600 : 1700;
    let i = 0;
    setState((s) => ({
      ...s,
      ticket: t,
      sheet: null,
      cut: steps[0],
      cutLine: `${t.no} · ${t.from} → ${t.to} · ${i18nF(l, 'fmt.km', { n: t.km.toLocaleString('en-US') }, `${t.km.toLocaleString('en-US')} km`)}`,
    }));
    const tick = () => {
      i += 1;
      if (i < steps.length) {
        setState((s) => ({ ...s, cut: steps[i] }));
        cutRef.current = setTimeout(tick, dur);
      } else {
        const event = journeyEvent(stateRef.current, t);
        if (event) setState((s) => ({ ...s, journey: event }));
        else finishLanding(t);
      }
    };
    cutRef.current = setTimeout(tick, dur);
  }, [buzz, click, finishLanding]);

  const chooseJourney = useCallback((accept) => {
    const s = stateRef.current;
    if (!s.journey || !s.ticket) return;
    const next = resolveJourney(s, s.journey, accept);
    if (next === s) return;
    setState({ ...next, journey: null });
    finishLanding(next.ticket);
  }, [finishLanding]);

  /* ---- world clock ---------------------------------------------- */

  useEffect(() => {
    if (!loaded) return undefined;
    const t = setInterval(() => {
      const cur = stateRef.current;
      if (cur.intro || cur.cut || !foregroundRef.current) return;
      setState((s) => {
        if (s.intro || s.cut) return s;
        const next = expireMerchant(advanceWorldClock(s));
        if (
          s.ticket
          && next.minsToDep === 0
          && s.minsToDep >= 0
          && !flyingRef.current
          && !s.cut
        ) {
          setTimeout(() => runCutscene(), 0);
        }
        return next;
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
      buzz(trf('msg.boarding_call', { no: state.ticket.no }, `Boarding call · ${state.ticket.no} · gate closing`), 'ok');
    }
    if (!state.ticket) calledEdgeRef.current = false;
  }, [state.called, state.optPush, state.ticket, buzz, trf]);

  const baseCity = CITIES[state.city];
  const city = {
    ...baseCity,
    name: i18nT(loc, `city.${state.city}`, baseCity.name),
    airport: i18nT(loc, `city.${state.city}.airport`, baseCity.airport),
    country: i18nT(loc, `city.${state.city}.country`, baseCity.country),
    cont: i18nT(loc, `city.${state.city}.cont`, baseCity.cont),
  };
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
  const worldEventDay = eventGameDay(state.gameMin);
  const worldEvents = useMemo(
    () => activeEvents(worldEventDay * 1440, state.eventSeed),
    [worldEventDay, state.eventSeed],
  );
  const currentEvents = useMemo(() => worldEvents
    .map((event) => ({
      ...localizedEvent(event, loc),
      impactText: eventImpactText(event, loc),
    }))
    .sort((a, b) => (a.cityId === state.city ? -1 : b.cityId === state.city ? 1 : a.cityId.localeCompare(b.cityId))),
  [worldEvents, loc, state.city]);
  const eventHistory = useMemo(() => (state.seenEventEpisodes || [])
    .map((row) => {
      const event = EVENT_BY_ID[row.eventId];
      if (!event) return null;
      return {
        ...localizedEvent(event, loc),
        ...row,
        seenDay: eventGameDay(row.seenAt),
        impactText: eventImpactText(event, loc),
      };
    })
    .filter(Boolean), [state.seenEventEpisodes, loc]);
  const popupEvent = useMemo(() => (state.eventPopup ? {
    ...localizedEvent(state.eventPopup, loc),
    impactText: eventImpactText(state.eventPopup, loc),
  } : null), [state.eventPopup, loc]);
  const sell = useMemo(
    () => merchantSellData(state, worldEvents),
    [state.inv, state.city, state.merchant, state.gameMin, loc, worldEvents],
  );

  const setTab = useCallback((tab) => {
    setState((s) => refreshOffers({ ...s, tab, page: null, query: '' }));
  }, []);
  const setPage = useCallback((page) => {
    setState((s) => ({ ...s, page }));
  }, []);
  const setSeg = useCallback((seg) => setState((s) => ({ ...s, seg })), []);
  const setQuery = useCallback((query) => {
    setState((s) => ({ ...s, query }));
  }, []);
  const setFocusDest = useCallback((focusDest) => {
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
  }, []);

  const openPinCity = useCallback((id) => {
    if (!id || !CITIES[id]) return;
    setState((s) => ({ ...s, pinCity: id }));
  }, []);

  const closePinCity = useCallback(() => {
    setState((s) => ({ ...s, pinCity: null }));
  }, []);

  /** Focus a hub for market intel without opening Flights. */
  const watchDest = useCallback((focusDest) => {
    setState((s) => ({
      ...s,
      focusDest: focusDest || '',
      query: '',
      tab: 'market',
      page: null,
      pinCity: null,
    }));
  }, []);

  const setFilter = useCallback((filter) => setState((s) => ({ ...s, filter })), []);
  const closeSheet = useCallback(() => setState((s) => ({
    ...s, sheet: null, selInv: null, invQty: 1, overweightNote: s.sheet === 'sell' ? '' : s.overweightNote,
  })), []);
  const dismissEvent = useCallback((openMarket = false) => {
    setState((s) => ({
      ...s,
      sheet: openMarket ? null : (s.eventReturnSheet || null),
      tab: openMarket ? 'market' : s.tab,
      page: openMarket ? null : s.page,
      seg: openMarket ? 'local' : s.seg,
      eventPopup: null,
      eventReturnSheet: null,
    }));
  }, []);
  const startGame = useCallback(() => {
    setState((s) => refreshOffers({ ...s, intro: false }));
  }, []);
  const setRot = useCallback((rot) => {
    setState((s) => ({ ...s, rot }));
  }, []);
  const setDragging = useCallback((dragging) => {
    if (dragging) markInteracted();
    setState((s) => ({ ...s, dragging }));
  }, []);
  const toggleOpt = useCallback((key) => {
    setState((s) => ({ ...s, [key]: !s[key] }));
  }, []);

  const setThemeMode = useCallback((mode) => {
    setState((s) => ({ ...s, themeMode: mode === 'light' ? 'light' : 'dark' }));
  }, []);

  const setFontScale = useCallback((scale) => {
    setState((s) => ({ ...s, fontScale: [1, 1.25, 1.5].includes(scale) ? scale : 1 }));
  }, []);

  const cycleColorBlind = useCallback((mode) => {
    setState((s) => ({ ...s, colorBlind: ['off', 'deuteranopia', 'protanopia'].includes(mode) ? mode : 'off' }));
  }, []);

  const setLocale = useCallback((lng) => {
    setState((s) => ({ ...s, locale: lng === 'zh' ? 'zh' : 'en' }));
  }, []);

  const openProduct = useCallback((id) => setState((s) => ({
    ...s, sheet: 'product', selId: id, qty: 1, slot: 'bag',
  })), []);

  const openFlight = useCallback((fl) => {
    if (!fl || fl.eventUnavailable) {
      buzz(tr('msg.event_flight_unavailable', 'This service is unavailable during the current event.'), 'bad');
      return;
    }
    setState((s) => ({
      ...s, sheet: 'flight', selFlight: fl, cabin: 'economy', addon: '',
    }));
  }, [buzz, tr]);

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
    setState((s) => {
      if (!s.ticket || s.cut) return s;
      return {
        ...s,
        ...refundTravel(s, MOBILE_BALANCE.refundRate),
        ticket: null,
        minsToDep: 0,
        called: false,
        bagLimit: DEFAULT_BAG_LIMIT,
        sheet: null,
      };
    });
    flyingRef.current = false;
    calledEdgeRef.current = false;
    buzz(trf('msg.ticket_cancelled_pct', { pct: Math.round(MOBILE_BALANCE.refundRate * 100) }, 'Ticket cancelled'), 'ok');
  }, [buzz, trf]);

  const buy = useCallback(() => {
    let result = null;
    setState((st) => {
      const p = PRODUCTS[st.selId];
      if (!p) return st;
      const n = st.qty;
      const slot = st.slot;
      const cost = purchaseTotal(st, p.id, n);
      const unit = cost / n;
      const wt = p.w * n;
      if (cost > st.cash) {
        result = { ok: false, msg: stF(st, 'msg.no_cash_short', { short: money(cost - st.cash) }, `Not enough cash — short ${money(cost - st.cash)}`), kind: 'bad' };
        return st;
      }
      const bagKgNow = bagUsed(st.inv);
      const cargoKgNow = cargoUsed(st.inv);
      const cap = slot === 'bag' ? st.bagLimit : st.cargoCap;
      const used = slot === 'bag' ? bagKgNow : cargoKgNow;
      if (used + wt > cap) {
        result = {
          ok: false,
          msg: stF(st, 'msg.over_limit', {
            slot: stT(st, slot === 'bag' ? 'slot.carry_on' : 'slot.cargo', slot === 'bag' ? 'carry-on' : 'cargo'),
            n: (used + wt - cap).toFixed(1),
          }, `Over the ${slot === 'bag' ? 'carry-on' : 'cargo'} limit by ${(used + wt - cap).toFixed(1)} kg`),
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
        title: stF(st, 'log.bought', { n, name: stT(st, `prod.${p.id}`, p.name) }, `Bought ${n} × ${p.name}`),
        sub: `${stT(st, `city.${st.city}`, here.name)} · ${fmtClock(cityMinutes(st.gameMin, st.city), st.opt24h, st.locale)}`,
        amount: `−${money(cost)}`,
        color: '#E05555',
        t: st.gameMin,
      };
      result = { ok: true, msg: stF(st, 'msg.bought', { n, name: stT(st, `prod.${p.id}`, p.name), total: money(cost) }, `Bought ${n} × ${p.name} · ${money(cost)}`), kind: 'ok' };
      const next = {
        ...st,
        inv,
        merchant: { ...st.merchant, supply: st.merchant.supply?.city === st.city ? null : st.merchant.supply },
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
  }, [announceAchievements, buzz, click]);

  const buyTicket = useCallback(() => {
    let result = null;
    setState((st) => {
      if (st.ticket) {
        result = { ok: false, msg: stT(st, 'msg.cancel_ticket_first', 'Cancel your current ticket first'), kind: 'bad' };
        return st;
      }
      const fl = quoteFlightForEvents(
        st.selFlight,
        st.city,
        activeEvents(st.gameMin, st.eventSeed),
        st.eventSeed,
      );
      if (!fl) return st;
      if (fl.eventUnavailable) {
        result = { ok: false, msg: stT(st, 'msg.event_flight_unavailable', 'This service is unavailable during the current event.'), kind: 'bad' };
        return { ...st, sheet: null, selFlight: null };
      }
      const add = ADDONS.find((a) => a.k === st.addon) || ADDONS[0];
      const fare = merchantFare(st, st.cabin === 'economy' ? fl.econ : fl.biz);
      const baggage = merchantBaggage(st, add.price);
      const total = fare + baggage;
      if (total > st.cash) {
        result = { ok: false, msg: stT(st, 'msg.no_cash_fare', 'Not enough cash for this fare'), kind: 'bad' };
        return st;
      }
      const from = CITIES[st.city];
      const to = CITIES[fl.toId];
      const kg = add.k === 'light' ? 10 : add.k === 'standard' ? 20 : add.k === 'heavy' ? 50 : 0;
      const wait = waitUntilDep(st.gameMin, st.city, fl.depMin);
      const cabinLabel = st.cabin === 'economy'
        ? stF(st, 'log.cabin_economy', {}, 'Economy')
        : stF(st, 'log.cabin_business', {}, 'Business');
      const entry = {
        icon: 'assets/ic_flight.webp',
        title: stF(st, 'log.booked', { no: fl.no }, `Booked ${fl.no}`),
        sub: stF(st, 'log.booked_sub', { from: from.iata, to: to.iata, cabin: cabinLabel }, `${from.iata} → ${to.iata} · ${st.cabin === 'economy' ? 'Economy' : 'Business'}`),
        amount: `−${money(total)}`,
        color: '#E05555',
        t: st.gameMin,
      };
      result = { ok: true, msg: stF(st, 'msg.ticket_booked', { no: fl.no, name: stT(st, `city.${fl.toId}`, to.name) }, `Ticket booked · ${fl.no} to ${to.name}`), kind: 'ok' };
      flyingRef.current = false;
      calledEdgeRef.current = false;
      return {
        ...st,
        ...travelCharge(st, total),
        merchant: { ...st.merchant, coupon: null },
        sheet: null,
        tab: 'globe',
        page: null,
        called: false,
        focusDest: fl.toId,
        bagLimit: DEFAULT_BAG_LIMIT + kg,
        ticket: {
          merchantKey: `${st.legs}|${fl.no}|${fl.toId}|${st.gameMin + wait}`,
          no: fl.no,
          from: from.iata,
          to: to.iata,
          toId: fl.toId,
          cabin: st.cabin,
          km: fl.km,
          dur: fl.dur,
          mins: fl.mins,
          extraKg: kg,
          fareCost: fare,
          baggageCost: baggage,
          totalPaid: total,
          ledgerPaid: total,
        },
        minsToDep: wait,
        log: [entry].concat(st.log).slice(0, 40),
      };
    });
    if (result?.ok) click('sfx_ticket');
    if (result) setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [buzz, click]);

  const sellAll = useCallback(() => {
    let result = null;
    setState((s) => {
      if (!s.inv.length) return s;
      const d = merchantSellData(s);
      let progressState = s;
      let bonus = 0;
      for (const row of d.rows) {
        const progress = recordMerchantSale(progressState, row.id, row.qty, row.grossValue);
        progressState = progress.state;
        bonus += progress.bonus;
        row.grossValue += progress.bonus;
      }
      d.gross += bonus; d.net += bonus;
      const here = CITIES[s.city];
      const entry = {
        icon: 'assets/ic_market.webp',
        title: d.rows.length === 1
          ? stF(s, 'log.sold_lot', { n: d.rows.length }, `Sold ${d.rows.length} lot`)
          : stF(s, 'log.sold_lots', { n: d.rows.length }, `Sold ${d.rows.length} lots`),
        sub: `${stT(s, `city.${s.city}`, here.name)} · ${fmtClock(cityMinutes(s.gameMin, s.city), s.opt24h, s.locale)}`,
        amount: `${d.net >= 0 ? '+' : '−'}${money(Math.abs(d.net))}`,
        color: d.net >= 0 ? '#3CB8A4' : '#E05555',
        t: s.gameMin,
      };
      result = d;
      const tripRecap = d.rows.reduce((recap, row) => recordTripSale(recap, s.city, {
        id: row.id,
        qty: row.qty,
        cost: row.costValue,
        revenue: row.grossValue,
        fullQualityRevenue: row.grossValue,
      }), s.tripRecap);
      const next = {
        ...progressState,
        ...saleCredit(s, d.gross, d.cost),
        inv: [],
        sheet: null,
        selInv: null,
        lastSale: d.net,
        tripRecap,

        log: [entry].concat(s.log).slice(0, 40),
        overweightNote: '',
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return next;
    });
    if (!result) return;
    click(result.net >= 0 ? 'sfx_profit' : 'sfx_loss');
    if (result.net >= 0) {
      setTimeout(() => buzz(trf('msg.nice_trade', { net: money(result.net) }, `Nice trade! ${money(result.net)} profit`), 'ok'), 0);
    } else {
      setTimeout(() => buzz(trf('msg.rough_run', { loss: money(-result.net) }, `Rough run — ${money(-result.net)} down. Next leg pays it back.`), 'bad'), 0);
    }
  }, [announceAchievements, buzz, click, trf]);

  const sellQty = useCallback((n) => {
    let result = null;
    setState((s) => {
      const idx = findInv(s.inv, s.selInv);
      if (idx < 0) return s;
      const item = s.inv[idx];
      const qty = Math.min(Math.max(1, n || s.invQty), item.n);
      const quoted = saleQuote(s, item, qty);
      const progress = recordMerchantSale(s, item.id, qty, quoted);
      const gross = quoted + progress.bonus;
      const net = gross - item.cost * qty;
      const inv = s.inv.slice();
      if (qty >= item.n) inv.splice(idx, 1);
      else inv[idx] = { ...item, n: item.n - qty };
      const here = CITIES[s.city];
      const entry = {
        icon: item.icon,
        title: stF(s, 'log.sold', { n: qty, name: stT(s, `prod.${item.id}`, item.name) }, `Sold ${qty} × ${item.name}`),
        sub: `${stT(s, `city.${s.city}`, here.name)} · ${fmtClock(cityMinutes(s.gameMin, s.city), s.opt24h, s.locale)}`,
        amount: `${net >= 0 ? '+' : '−'}${money(Math.abs(net))}`,
        color: net >= 0 ? '#3CB8A4' : '#E05555',
        t: s.gameMin,
      };
      result = {
        net,
        msg: stF(s, 'msg.sold', { n: qty, name: stT(s, `prod.${item.id}`, item.name), total: money(gross) }, `Sold ${qty} × ${item.name} · ${money(gross)}`),
        kind: net >= 0 ? 'ok' : 'bad',
      };
      const tripRecap = recordTripSale(s.tripRecap, s.city, {
        id: item.id, qty, cost: item.cost * qty, revenue: gross, fullQualityRevenue: gross,
      });
      const next = {
        ...progress.state,
        ...saleCredit(s, gross, item.cost * qty),
        inv,
        sheet: null,
        selInv: null,
        invQty: 1,
        lastSale: net,
        tripRecap,

        log: [entry].concat(s.log).slice(0, 40),
        overweightNote: (() => {
          const over = Math.max(0, bagUsed(inv) - DEFAULT_BAG_LIMIT);
          return over > 0
            ? stF(s, 'msg.overweight_note', { n: over.toFixed(1) }, `Carry-on over by ${over.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`)
            : '';
        })(),
      };
      next.unlockedAch = announceAchievements(s.unlockedAch || [], computeStats(next));
      return next;
    });
    if (!result) return;
    click(result.net >= 0 ? 'sfx_profit' : 'sfx_loss');
    setTimeout(() => buzz(result.msg, result.kind), 0);
  }, [announceAchievements, buzz, click]);

  const discardQty = useCallback((n) => {
    const s0 = stateRef.current;
    const idx0 = findInv(s0.inv, s0.selInv);
    if (idx0 < 0) return;
    const item0 = s0.inv[idx0];
    const qty0 = Math.min(Math.max(1, n || s0.invQty), item0.n);
    Alert.alert(
      tr('alert.discard_title', 'Discard goods?'),
      trf('alert.discard_body', { n: qty0, name: tr(`prod.${item0.id}`, item0.name) }, `Throw away ${qty0} × ${item0.name}? No refund.`),
      [
        { text: tr('alert.cancel', 'Cancel'), style: 'cancel' },
        {
          text: tr('alert.discard', 'Discard'),
          style: 'destructive',
          onPress: () => {
                    setState((s) => {
              const idx = findInv(s.inv, s.selInv);
              if (idx < 0) return s;
              const item = s.inv[idx];
              const qty = Math.min(Math.max(1, n || s.invQty), item.n);
              const inv = s.inv.slice();
              if (qty >= item.n) inv.splice(idx, 1);
              else inv[idx] = { ...item, n: item.n - qty };
              const over = Math.max(0, bagUsed(inv) - DEFAULT_BAG_LIMIT);
              const tripRecap = recordTripDiscard(s.tripRecap, s.city, item.id, qty, item.cost * qty);
              return {
                ...consumeDeal(s, item.id, qty),
                inv,
                profit: s.profit - item.cost * qty,
                tripRecap,
                sheet: tripRecap !== s.tripRecap ? 'tripRecap' : null,
                selInv: null,
                invQty: 1,
                overweightNote: over > 0
                  ? stF(s, 'msg.overweight_note', { n: over.toFixed(1) }, `Carry-on over by ${over.toFixed(1)} kg — sell, discard, or buy baggage on your next ticket.`)
                  : '',
              };
            });
            buzz(trf('msg.discarded', { n: qty0, name: tr(`prod.${item0.id}`, item0.name) }, `Discarded ${qty0} × ${item0.name}`), 'bad');
          },
        },
      ],
    );
  }, [buzz, tr, trf]);

  const moveInvSlot = useCallback(() => {
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
          msg: stF(s, 'msg.no_space', {
            slot: stT(s, dest === 'bag' ? 'slot.carry_on' : 'slot.cargo', dest === 'bag' ? 'carry-on' : 'cargo'),
            n: (destUsed + wt - cap).toFixed(1),
          }, `Not enough ${dest === 'bag' ? 'carry-on' : 'cargo'} space (${(destUsed + wt - cap).toFixed(1)} kg over)`),
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
        msg: stF(s, 'msg.moved', {
          n: qty,
          name: stT(s, `prod.${item.id}`, item.name),
          slot: stT(s, dest === 'bag' ? 'slot.carry_on' : 'slot.cargo', dest === 'bag' ? 'carry-on' : 'cargo'),
        }, `Moved ${qty} × ${item.name} to ${dest === 'bag' ? 'carry-on' : 'cargo'}`),
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
  }, [buzz]);

  const saveNow = useCallback(async () => {
    clearTimeout(saveRef.current);
    try { await persist(); buzz(tr('msg.saved', 'Progress saved to slot 1'), 'ok'); }
    catch { buzz(tr('msg.save_failed', 'Could not save progress'), 'bad'); }
  }, [buzz, tr, persist]);

  const restart = useCallback(async () => {
    if (!loadedRef.current) return;
    clearTimeout(cutRef.current);
    clearTimeout(saveRef.current);
    flyingRef.current = false;
    calledEdgeRef.current = false;
    loadedRef.current = false;
    setLoaded(false);
    runGeneration.current += 1;
    const previous = stateRef.current;
    const next = { ...initialState() };
    for (const key of ['optHaptics', 'optPush', 'optSound', 'opt24h', 'optReduce', 'locale', 'fontScale', 'colorBlind', 'themeMode']) next[key] = previous[key];
    const job = saveQueue.current.catch(() => {}).then(() => resetSave(AsyncStorage, JSON.stringify(serializeSave(next))));
    saveQueue.current = job;
    try {
      await job;
      suspendAutosaveRef.current = false;
      setState(next);
      buzz(tr('msg.new_run', 'New run — back in Istanbul'), 'ok');
    } catch {
      // Resume the prior ticket from its checkpoint if a cutscene was interrupted.
      setState((s) => ({ ...s, cut: null, cutLine: '' }));
      buzz(tr('msg.reset_failed', 'New run was not saved. Your current game remains open.'), 'bad');
    } finally {
      loadedRef.current = true;
      setLoaded(true);
    }
  }, [buzz, tr]);

  const productRows = useMemo(() => {
    const baseIds = state.seg === 'local' ? localIds : importIds;
    const ids = destId ? sortByDestProfit(baseIds, state.city, destId, worldEvents) : baseIds;
    return ids.map((id) => {
      const q = PRODUCTS[id];
      const unit = merchantUnit(state, id, state.city, 'buy', worldEvents);
      const tag = intel(id, state.city, destId, loc, worldEvents);
      const spark = priceSparkline(id, state.city, 5, worldEvents);
      const destPrice = destId ? merchantUnit(state, id, destId, 'sell', worldEvents) : null;
      const cat = i18nT(loc, `cat.${q.category}`, q.category);
      const name = i18nT(loc, `prod.${id}`, q.name);
      const isLocal = q.home === state.city;
      return {
        id,
        name,
        isLocal,
        icon: q.icon,
        buy: money(unit),
        weight: i18nF(loc, 'fmt.kg', { n: q.w.toFixed(1) }, `${q.w.toFixed(1)} kg`),
        meta: destPrice != null
          ? i18nF(loc, 'market.meta_dest', { cat, here: money(unit), there: money(destPrice) }, `${q.category} · here ${money(unit)} · there ${money(destPrice)}`)
          : i18nF(loc, 'market.meta_local', { cat, here: money(unit) }, `${q.category} · local price ${money(unit)}`),
        origin: isLocal ? i18nT(loc, 'market.origin_local', 'Local') : i18nT(loc, 'market.origin_import', 'Import'),
        tag: tag.text,
        tagKind: tag.kind,
        spark,
      };
    });
  }, [state.seg, state.city, state.merchant, destId, loc, localIds, importIds, worldEvents]);

  const sortedFlights = useMemo(() => {
    const localNow = ((cityMinutes(state.gameMin, state.city) % 1440) + 1440) % 1440;
    const quotedRoutes = routes.map((route) => quoteFlightForEvents(
      route,
      state.city,
      worldEvents,
      state.eventSeed,
    ));
    // True next departure by local clock (independent of focus / filter order).
    const nextKey = [...quotedRoutes]
      .filter((f) => !f.eventUnavailable && f.depMin >= localNow)
      .sort((a, b) => a.depMin - b.depMin)[0];
    const nextId = nextKey ? `${nextKey.no}-${nextKey.toId}-${nextKey.depMin}` : null;

    const sorted = [...quotedRoutes].sort((a, b) => {
      if (state.focusDest) {
        const af = a.toId === state.focusDest ? 0 : 1;
        const bf = b.toId === state.focusDest ? 0 : 1;
        if (af !== bf) return af - bf;
      }
      if (!!a.eventUnavailable !== !!b.eventUnavailable) return a.eventUnavailable ? 1 : -1;
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
    });
    // Preserve the existing 12-service board for normal traffic, then append
    // every event-cancelled service so cancellations remain visible and
    // explainable instead of silently disappearing behind the list cap.
    const list = visibleFlightBoard(sorted, 12);

    return list.map((fl) => {
      const past = fl.depMin < localNow;
      const key = `${fl.no}-${fl.toId}-${fl.depMin}`;
      const toCity = CITIES[fl.toId];
      const h = Math.floor(fl.mins / 60);
      const m = pad(fl.mins % 60);
      return {
        ...fl,
        dep: fmtClock(fl.depMin, state.opt24h, loc),
        arr: fmtClock(fl.depMin + fl.mins + (toCity.tz - baseCity.tz) * 60, state.opt24h, loc),
        from: baseCity.iata,
        to: toCity.iata,
        toName: i18nT(loc, `city.${fl.toId}`, toCity.name),
        dur: i18nF(loc, 'fmt.hm', { h, m }, `${h}h ${m}m`),
        stops: fl.stops === 'Nonstop' ? i18nT(loc, 'fmt.nonstop', 'Nonstop') : (fl.stops || ''),
        unvisited: !state.visited.includes(fl.toId),
        focused: fl.toId === state.focusDest,
        past,
        isNext: key === nextId,
      };
    });
  }, [routes, state.filter, state.visited, state.focusDest, state.opt24h, state.gameMin, state.city, state.eventSeed, loc, worldEvents]);

  const opportunities = useMemo(() => routeOpportunities(state, worldEvents,
    routes.map((route) => quoteFlightForEvents(route, state.city, worldEvents, state.eventSeed))),
  [state.inv, state.cash, state.city, state.gameMin, state.locale, state.ticket, state.eventSeed, routes, worldEvents]);

  const q = state.query.trim().toLowerCase();
  const searchResults = q
    ? CIDS.filter((k) => k !== state.city)
      .filter((k) => {
        const c = CITIES[k];
        const cLocal = i18nT(loc, `city.${k}`, c.name);
        const airportLocal = i18nT(loc, `city.${k}.airport`, c.airport);
        const countryLocal = i18nT(loc, `city.${k}.country`, c.country);
        return `${c.iata} ${c.icao} ${c.airport} ${c.name} ${c.country} ${cLocal} ${airportLocal} ${countryLocal}`.toLowerCase().includes(q);
      })
      .slice(0, 6)
      .map((k) => {
        const c = CITIES[k];
        return {
          ...c,
          name: i18nT(loc, `city.${k}`, c.name),
          airport: i18nT(loc, `city.${k}.airport`, c.airport),
          country: i18nT(loc, `city.${k}.country`, c.country),
        };
      })
    : [];

  const selProduct = state.selId ? PRODUCTS[state.selId] : null;
  const unitHere = selProduct ? merchantUnit(state, selProduct.id, state.city, 'buy', worldEvents) : 0;
  const sellUnitHere = selProduct ? merchantUnit(state, selProduct.id, state.city, 'sell', worldEvents) : 0;
  const costTotal = selProduct ? purchaseTotal(state, selProduct.id, state.qty) : 0;
  const wtTotal = selProduct ? selProduct.w * state.qty : 0;
  const slotUsed = state.slot === 'bag' ? bagKg : cargoKg;
  const slotCap = state.slot === 'bag' ? state.bagLimit : state.cargoCap;
  const over = slotUsed + wtTotal > slotCap;
  const canBuy = !!selProduct && !over && costTotal <= state.cash;

  const addons = useMemo(() => ADDONS.map((a) => ({
    ...a,
    label: i18nT(loc, `add.${a.k}`, a.label),
  })), [loc]);
  const add = addons.find((a) => a.k === state.addon) || addons[0];
  const addonKg = add.k === 'light' ? 10 : add.k === 'standard' ? 20 : add.k === 'heavy' ? 50 : 0;
  const bookingBagLimit = state.ticket ? state.bagLimit : DEFAULT_BAG_LIMIT + addonKg;
  const selFlight = state.selFlight
    ? quoteFlightForEvents(state.selFlight, state.city, worldEvents, state.eventSeed)
    : null;
  const fareTotal = selFlight
    ? merchantFare(state, state.cabin === 'economy' ? selFlight.econ : selFlight.biz) + merchantBaggage(state, add.price)
    : 0;
  const canBook = !!selFlight && !selFlight.eventUnavailable && !state.ticket && fareTotal <= state.cash;
  const bagOverKg = Math.max(0, bagKg - bookingBagLimit);
  const selInvItem = (() => {
    const idx = findInv(state.inv, state.selInv);
    return idx >= 0 ? state.inv[idx] : null;
  })();
  const invGross = selInvItem ? saleQuote(state, selInvItem, state.invQty, worldEvents) : 0;
  const invUnit = selInvItem ? invGross / state.invQty : 0;

  const achievements = useMemo(() => ACHIEVEMENTS.map((a) => ({
    ...a,
    name: i18nT(loc, `ach.${a.id}`, a.name),
    desc: i18nT(loc, `ach.${a.id}.desc`, a.desc),
  })), [loc]);

  const sources = useMemo(() => SOURCES.map((src, i) => ({
    ...src,
    license: i18nT(loc, `src.${i}.license`, src.license),
    use: i18nT(loc, `src.${i}.use`, src.use),
  })), [loc]);

  const noteText = useMemo(() => {
    const map = {};
    CIDS.forEach((cid) => { map[cid] = i18nT(loc, `note.${cid}`, NOTE_TEXT[cid]); });
    return map;
  }, [loc]);

  return {
    state,
    chooseJourney,
    acceptMerchantOrder: (id) => setState((s) => acceptOrder(s, id)),
    abandonMerchantOrder: () => setState(abandonOrder),
    equipMerchantAbility: (id) => setState((s) => equipAbility(s, id)),
    dismissMerchantAbility: (id) => setState((s) => dismissAbility(s, id)),
    loaded,
    city,
    destId,
    bagKg,
    cargoKg,
    bagOverKg,
    stats,
    sell,
    currentEvents,
    eventHistory,
    popupEvent,
    productRows,
    sortedFlights,
    opportunities,
    routes,
    destinations,
    searchResults,
    clockText: clockLabel(state.gameMin, state.opt24h, loc),
    localHour: Math.floor(((cityMinutes(state.gameMin, state.city) % 1440) + 1440) % 1440 / 60),
    localTime: fmtClock(cityMinutes(state.gameMin, state.city), state.opt24h, loc),
    locale: state.locale || 'en',
    t: (key, fallback) => i18nT(state.locale || 'en', key, fallback),
    tf: (key, vars, fallback) => i18nF(state.locale || 'en', key, vars, fallback),
    bagText: i18nF(loc, 'bags.usage', { n: bagKg.toFixed(1), cap: state.bagLimit }, `${bagKg.toFixed(1)} / ${state.bagLimit} kg`),
    cargoText: i18nF(loc, 'bags.usage', { n: cargoKg.toFixed(1), cap: state.cargoCap }, `${cargoKg.toFixed(1)} / ${state.cargoCap} kg`),
    saveSub: state.savedAt
      ? i18nF(loc, 'more.saved_ago', { time: hm(state.gameMin - state.savedAt, loc) }, `Last saved ${hm(state.gameMin - state.savedAt, loc)} ago · slot 1`)
      : i18nF(loc, 'more.saved_takeoff', {}, 'Last saved at takeoff · slot 1'),
    achievements,
    sources,
    addons,
    noteText,
    selProduct,
    selFlight,
    selInvItem,
    invUnit,
    invGross,
    unitHere,
    sellUnitHere,
    costTotal,
    wtTotal,
    over,
    canBuy,
    canBook,
    slotUsed,
    slotCap,
    fareTotal,
    add,
    hm: (m) => hm(m, loc),
    hhmm,
    money,
    flightFare: (price) => merchantFare(state, price),
    priceAt: (pid, cityId, side = 'sell') => merchantUnit(state, pid, cityId, side, worldEvents),
    marketIntel: (pid, cityId, destinationId) => intel(pid, cityId, destinationId, loc, worldEvents),
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
    setLocale,
    setFontScale,
    setThemeMode,
    cycleColorBlind,
    closeSheet,
    dismissEvent,
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
