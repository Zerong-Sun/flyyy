import { PRODUCTS } from './gameData.js';
import { EVENTS } from './eventData.js';
import { t } from './i18n.js';

const START_UTC_MINUTES = 9 * 60 + 40;

export const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

/** FNV-1a-ish stable 32-bit hash shared by every event roll. */
export function eventHash(value) {
  const text = String(value ?? '');
  let h = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  // Avalanche the FNV state so adjacent day suffixes do not produce correlated
  // low/high bands. This keeps a configured 18–20% daily roll statistically
  // close to its authored probability over normal play windows.
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}

export function eventRoll(seedText) {
  return eventHash(seedText) / 0x100000000;
}

/** Day zero is the first in-game day (Mar 12 in the existing demo clock). */
export function eventGameDay(gameMin) {
  return Math.max(0, Math.floor((START_UTC_MINUTES + Number(gameMin || 0)) / 1440));
}

export function eventEpisodeKey(eventId, startDay) {
  return `${eventId}|${startDay}`;
}

function episodeForDay(event, today, eventSeed) {
  const duration = Math.max(1, Math.floor(event.durationDays || 1));
  const probability = clamp(Number(event.probability || 0), 0, 1);
  let lastStart = -1;
  for (let day = 0; day <= today; day += 1) {
    // Rolls while an episode is already active are ignored rather than allowed
    // to restart or suppress a later eligible episode.
    if (lastStart >= 0 && day < lastStart + duration) continue;
    if (eventRoll(`${eventSeed}|event|${event.id}|${day}`) < probability) lastStart = day;
  }
  if (lastStart < 0 || today >= lastStart + duration) return null;
  const age = today - lastStart;
  return { startDay: lastStart, daysRemaining: duration - age };
}

/** Return data-driven active episodes for a game minute and run seed. */
export function activeEvents(gameMin, eventSeed, catalog = EVENTS) {
  const today = eventGameDay(gameMin);
  const out = [];
  catalog.forEach((event) => {
    const episode = episodeForDay(event, today, String(eventSeed || 'default'));
    if (!episode) return;
    out.push({
      ...event,
      ...episode,
      episodeKey: eventEpisodeKey(event.id, episode.startDay),
    });
  });
  return out;
}

export function activeEventsForCity(events, cityId) {
  return (events || []).filter((event) => event.cityId === cityId);
}

export function unseenArrivalEvent(events, cityId, seenEpisodes = []) {
  const seen = new Set((seenEpisodes || []).map((row) => row?.episodeKey).filter(Boolean));
  return activeEventsForCity(events, cityId).find((event) => !seen.has(event.episodeKey)) || null;
}

export function localizedEvent(event, locale = 'en') {
  const lang = locale === 'zh' ? 'zh' : 'en';
  return {
    ...event,
    headlineText: event?.headline?.[lang] || event?.headline?.en || event?.id || '',
    bodyText: event?.body?.[lang] || event?.body?.en || '',
  };
}

export function eventImpactText(event, locale = 'en') {
  if (!event) return '';
  const categories = (event.market?.categories || [])
    .map((category) => t(locale, `cat.${category}`, category))
    .join(locale === 'zh' ? '、' : ', ');
  const buy = Math.round((Number(event.market?.buyMult ?? 1) - 1) * 100);
  const sell = Math.round((Number(event.market?.sellMult ?? 1) - 1) * 100);
  const fare = Math.round((Number(event.flight?.fareMult ?? 1) - 1) * 100);
  const cancel = Math.round(Number(event.flight?.cancelProb ?? 0) * 100);
  const signed = (value) => `${value >= 0 ? '+' : ''}${value}%`;
  if (locale === 'zh') {
    return `影响：${categories} · 采购价 ${signed(buy)} · 售价 ${signed(sell)} · 票价 ${signed(fare)} · 班次削减约 ${cancel}%`;
  }
  return `Affected: ${categories} · buy ${signed(buy)} · sell ${signed(sell)} · airfare ${signed(fare)} · schedule reduction ${cancel}%`;
}

export function eventMarketMultiplier(productId, cityId, side = 'buy', events = []) {
  const product = PRODUCTS[productId];
  if (!product) return 1;
  let multiplier = 1;
  events.forEach((event) => {
    if (event.cityId !== cityId) return;
    const market = event.market || {};
    if (!(market.categories || []).includes(product.category)) return;
    multiplier *= Number(side === 'sell' ? market.sellMult : market.buyMult) || 1;
  });
  return clamp(multiplier, 0.5, 2);
}

export function eventAdjustedPrice(basePrice, productId, cityId, side = 'buy', events = []) {
  return Math.max(1, Math.round(Number(basePrice || 0) * eventMarketMultiplier(productId, cityId, side, events)));
}

/** Idempotently quote a base route against active origin/destination events. */
export function quoteFlightForEvents(flight, originCityId, events = [], eventSeed = 'default') {
  if (!flight) return null;
  const baseEcon = Number(flight.eventBaseEcon ?? flight.econ ?? 0);
  const baseBiz = Number(flight.eventBaseBiz ?? flight.biz ?? 0);
  const matched = (events || []).filter(
    (event) => event.cityId === originCityId || event.cityId === flight.toId,
  );
  let fareMult = 1;
  let unavailable = false;
  const flightKey = `${originCityId}>${flight.toId}|${flight.no || ''}|${flight.depMin ?? ''}`;
  matched.forEach((event) => {
    fareMult *= Number(event.flight?.fareMult ?? 1) || 1;
    const cancelProb = clamp(Number(event.flight?.cancelProb ?? 0), 0, 0.5);
    const roll = eventRoll(`${eventSeed}|event-flight|${event.id}|${event.startDay}|${flightKey}`);
    if (roll < cancelProb) unavailable = true;
  });
  fareMult = clamp(fareMult, 0.6, 2);
  return {
    ...flight,
    eventBaseEcon: baseEcon,
    eventBaseBiz: baseBiz,
    econ: Math.round(baseEcon * fareMult),
    biz: Math.round(baseBiz * fareMult),
    eventFareMult: fareMult,
    eventIds: matched.map((event) => event.id),
    eventUnavailable: unavailable,
  };
}
