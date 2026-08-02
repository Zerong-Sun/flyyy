import React from 'react';
import {
  View,
  Text,
  Image,
  TextInput,
  Pressable,
  StyleSheet,
} from 'react-native';
import { CITIES } from '../gameData';
import { assetSource } from '../assets';
import { gcKm } from '../gameLogic';
import { COLORS } from '../theme';
import { AssetIcon, Button, Card } from './ui';
import { Globe } from './Globe';

export function GlobeScreen({ game }) {
  const {
    state,
    city,
    bagText,
    cargoText,
    bagKg,
    destinations,
    localTime,
    searchResults,
    hm,
    setQuery,
    setFocusDest,
    watchDest,
    closePinCity,
    openFF,
    cancelTicket,
    setTab,
    t,
    tf,
  } = game;

  const ticket = state.ticket;
  const searching = state.query.trim().length > 0;
  const ratio = state.bagLimit > 0 ? Math.min(1, bagKg / state.bagLimit) : 0;
  const bagColor = ratio > 0.9 ? COLORS.red : ratio > 0.7 ? COLORS.orange : COLORS.text;
  const depLabel = !ticket
    ? ''
    : state.minsToDep <= 0
      ? t('globe.boarding_now', 'Boarding now')
      : tf('globe.to_departure', { t: hm(state.minsToDep) }, `${hm(state.minsToDep)} to departure`);
  const cabinLabel = ticket
    ? t(ticket.cabin === 'economy' ? 'globe.cabin_economy' : 'globe.cabin_business', ticket.cabin === 'economy' ? 'Economy' : 'Business')
    : '';

  return (
    <View style={styles.wrap}>
      <View style={styles.searchRow}>
        <Text style={styles.searchGlyph}>⌕</Text>
        <TextInput
          style={styles.searchInput}
          value={state.query}
          onChangeText={setQuery}
          placeholder={t('globe.search_placeholder', 'Search airports, cities, IATA')}
          placeholderTextColor={COLORS.muted2}
          autoCorrect={false}
          returnKeyType="search"
        />
        {searching ? (
          <Pressable onPress={() => setQuery('')} hitSlop={10}>
            <Text style={styles.searchClear}>{t('globe.clear', 'Clear')}</Text>
          </Pressable>
        ) : null}
      </View>

      {ticket ? (
        <View style={styles.ticketBanner}>
          <AssetIcon path="assets/ic_fast_forward.webp" size={26} tintColor={COLORS.orange} />
          <View style={styles.ticketBody}>
            <Text style={styles.ticketLine}>
              {ticket.no} · {ticket.from} → {ticket.to}
            </Text>
            <Text style={styles.ticketSub}>
              {depLabel} · {cabinLabel}
            </Text>
          </View>
          <Pressable
            style={styles.speedBtn}
            onPress={openFF}
            accessibilityRole="button"
            accessibilityLabel={t('globe.speed_up_a11y', 'Speed up to takeoff')}
          >
            <Text style={styles.speedBtnText}>{t('globe.speed_up', 'Speed up')}</Text>
          </Pressable>
          <Pressable
            style={styles.cancelBtn}
            onPress={cancelTicket}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={t('globe.cancel_ticket', 'Cancel ticket')}
          >
            <Text style={styles.cancelBtnText}>{t('globe.cancel', 'Cancel')}</Text>
          </Pressable>
        </View>
      ) : null}

      {searching ? (
        <View style={styles.results}>
          {searchResults.length === 0 ? (
            <Text style={styles.noResults}>
              {tf('globe.no_results', { q: state.query.trim() }, `No hub matches "${state.query.trim()}".`)}
            </Text>
          ) : (
            searchResults.map((c) => (
              <Pressable
                key={c.id}
                onPress={() => setFocusDest(c.id)}
                style={({ pressed }) => [styles.resultRow, pressed && styles.rowPressed]}
              >
                <Text style={styles.resultIata}>{c.iata}</Text>
                <View style={styles.resultBody}>
                  <Text style={styles.resultName} numberOfLines={1}>{c.airport}</Text>
                  <Text style={styles.resultSub}>{c.name} · {c.country}</Text>
                </View>
                <Text style={styles.chevron}>›</Text>
              </Pressable>
            ))
          )}
        </View>
      ) : (
        <>
          <Globe game={game} />

          {state.pinCity && CITIES[state.pinCity] ? (() => {
            const pin = CITIES[state.pinCity];
            const pinName = t(`city.${state.pinCity}`, pin.name);
            const pinCountry = t(`city.${state.pinCity}.country`, pin.country);
            const visited = state.visited.includes(state.pinCity);
            const km = gcKm(city, pin);
            return (
              <Card style={styles.pinCard}>
                <View style={styles.pinCardTop}>
                  <View style={styles.pinCardBody}>
                    <Text style={styles.pinCardName}>{pinName}</Text>
                    <Text style={styles.pinCardMeta}>
                      {pin.iata} · {pinCountry} · {tf('fmt.km', { n: km.toLocaleString('en-US') }, `${km.toLocaleString('en-US')} km`)}
                    </Text>
                    <Text style={styles.pinCardVisit}>
                      {visited ? t('globe.visited', 'Visited') : t('globe.not_visited', 'Not visited yet')}
                    </Text>
                  </View>
                  <Pressable onPress={closePinCity} hitSlop={10} accessibilityRole="button" accessibilityLabel={t('globe.close', 'Close')}>
                    <Text style={styles.pinCardClose}>✕</Text>
                  </Pressable>
                </View>
                <View style={styles.pinCardActions}>
                  <Button
                    variant="primary"
                    style={styles.pinCardBtn}
                    onPress={() => setFocusDest(state.pinCity)}
                  >
                    {t('globe.find_flights', 'Find flights')}
                  </Button>
                  <Button
                    variant="secondary"
                    style={styles.pinCardBtn}
                    onPress={() => watchDest(state.pinCity)}
                  >
                    {t('globe.watch_market', 'Watch in Market')}
                  </Button>
                </View>
              </Card>
            );
          })() : null}

          <Card style={styles.heroCard}>
            <View style={styles.heroImageWrap}>
              <Image
                source={assetSource(city.hero)}
                style={styles.heroImage}
                resizeMode="cover"
              />
              <View style={styles.heroGradient} />
              <View style={styles.heroLabels}>
                <View style={styles.heroTextCol}>
                  <Text style={styles.cityName}>{city.name}</Text>
                  <Text style={styles.cityAirport} numberOfLines={1}>
                    {city.airport} · {city.iata} / {city.icao} · {city.country}
                  </Text>
                </View>
                <View style={styles.hereBadge}>
                  <Text style={styles.hereBadgeText}>{t('globe.you_are_here', 'You are here')}</Text>
                </View>
              </View>
            </View>

            <View style={styles.statsRow}>
              <View style={styles.statCell}>
                <Text style={styles.statLabel}>{t('globe.local_time', 'Local time')}</Text>
                <Text style={styles.statValue}>{localTime}</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.statCell}>
                <Text style={styles.statLabel}>{t('globe.carry_on', 'Carry-on')}</Text>
                <Text style={[styles.statValue, { color: bagColor }]}>{bagText}</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.statCell}>
                <Text style={styles.statLabel}>{t('globe.cargo', 'Cargo')}</Text>
                <Text style={styles.statValue}>{cargoText}</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.statCell}>
                <Text style={styles.statLabel}>{t('globe.routes', 'Routes')}</Text>
                <Text style={styles.statValue}>
                  {tf('globe.cities_count', { n: destinations.length }, `${destinations.length} cities`)}
                </Text>
              </View>
            </View>

            <View style={styles.elevRow}>
              <Text style={styles.elevText}>
                {tf('globe.field_elev', { n: city.elev }, `Field elevation ${city.elev} ft`)}
              </Text>
            </View>
          </Card>

          <View style={styles.actions}>
            <Button variant="primary" style={styles.actionBtn} onPress={() => setTab('market')}>
              {t('globe.trade_here', 'Trade here')}
            </Button>
            <Button variant="secondary" style={styles.actionBtn} onPress={() => setTab('flights')}>
              {t('globe.find_flight', 'Find a flight')}
            </Button>
          </View>

          <Text style={styles.disclaimer}>
            {t('globe.disclaimer', 'Flight network rebuilt from public aviation data. Not real ticketing information.')}
          </Text>
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    paddingTop: 12,
    paddingBottom: 24,
  },
  pinCard: {
    marginHorizontal: 16,
    marginTop: 10,
    padding: 14,
    gap: 12,
  },
  pinCardTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
  },
  pinCardBody: {
    flex: 1,
    minWidth: 0,
  },
  pinCardName: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.text,
  },
  pinCardMeta: {
    fontSize: 13,
    color: COLORS.muted,
    marginTop: 3,
  },
  pinCardVisit: {
    fontSize: 12,
    color: COLORS.teal,
    marginTop: 4,
  },
  pinCardClose: {
    fontSize: 16,
    color: COLORS.muted2,
    padding: 4,
  },
  pinCardActions: {
    flexDirection: 'row',
    gap: 8,
  },
  pinCardBtn: {
    flex: 1,
  },
  searchRow: {
    marginHorizontal: 16,
    marginBottom: 8,
    paddingHorizontal: 12,
    height: 40,
    borderRadius: 13,
    backgroundColor: COLORS.panel3,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  searchGlyph: {
    fontSize: 17,
    color: COLORS.muted2,
  },
  searchInput: {
    flex: 1,
    fontSize: 15,
    color: COLORS.text,
    padding: 0,
  },
  searchClear: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.blue,
  },
  results: {
    paddingHorizontal: 16,
    paddingTop: 6,
    gap: 8,
  },
  noResults: {
    fontSize: 13,
    color: COLORS.muted,
    paddingVertical: 18,
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 12,
    backgroundColor: COLORS.panel,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  rowPressed: {
    backgroundColor: '#1B3A51',
  },
  resultIata: {
    fontFamily: 'monospace',
    fontSize: 15,
    fontWeight: '700',
    color: COLORS.teal,
    width: 42,
  },
  resultBody: {
    flex: 1,
    minWidth: 0,
  },
  resultName: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  resultSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  chevron: {
    fontSize: 20,
    color: COLORS.muted2,
  },
  ticketBanner: {
    marginHorizontal: 16,
    marginBottom: 8,
    padding: 10,
    borderRadius: 14,
    backgroundColor: 'rgba(232, 154, 60, 0.12)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(232, 154, 60, 0.35)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    // Sit above the globe stage — its glow/pan layer overflows and steals taps.
    zIndex: 20,
    elevation: 20,
  },
  ticketBody: {
    flex: 1,
    minWidth: 0,
  },
  ticketLine: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.text,
    letterSpacing: -0.08,
  },
  ticketSub: {
    fontSize: 11,
    color: COLORS.muted,
    marginTop: 1,
  },
  speedBtn: {
    paddingVertical: 7,
    paddingHorizontal: 11,
    borderRadius: 10,
    backgroundColor: COLORS.orange,
  },
  speedBtnText: {
    fontSize: 12,
    fontWeight: '700',
    color: COLORS.bg,
  },
  cancelBtn: {
    paddingVertical: 7,
    paddingHorizontal: 9,
    borderRadius: 10,
    backgroundColor: COLORS.panel3,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
  },
  cancelBtnText: {
    fontSize: 12,
    fontWeight: '600',
    color: COLORS.muted,
  },
  heroCard: {
    marginHorizontal: 16,
    marginTop: 4,
  },
  heroImageWrap: {
    height: 124,
    position: 'relative',
  },
  heroImage: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: COLORS.panel3,
  },
  heroGradient: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(11, 28, 44, 0.55)',
  },
  heroLabels: {
    position: 'absolute',
    left: 14,
    right: 14,
    bottom: 10,
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
  },
  heroTextCol: {
    flex: 1,
    minWidth: 0,
  },
  cityName: {
    fontSize: 22,
    fontWeight: '700',
    color: COLORS.text,
    letterSpacing: -0.5,
  },
  cityAirport: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  hereBadge: {
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: 8,
    backgroundColor: 'rgba(60, 184, 164, 0.18)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(60, 184, 164, 0.4)',
  },
  hereBadgeText: {
    fontSize: 11,
    fontWeight: '600',
    color: COLORS.teal,
  },
  statsRow: {
    flexDirection: 'row',
    padding: 10,
  },
  statCell: {
    flex: 1,
  },
  statLabel: {
    fontSize: 11,
    color: COLORS.muted,
  },
  statValue: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
    marginTop: 2,
  },
  statDivider: {
    width: StyleSheet.hairlineWidth,
    backgroundColor: COLORS.border,
    marginHorizontal: 8,
  },
  elevRow: {
    paddingHorizontal: 12,
    paddingBottom: 9,
  },
  elevText: {
    fontSize: 11,
    color: COLORS.muted2,
  },
  actions: {
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 16,
    marginTop: 12,
  },
  actionBtn: {
    flex: 1,
  },
  disclaimer: {
    marginTop: 16,
    marginHorizontal: 16,
    fontSize: 11,
    lineHeight: 16,
    color: COLORS.muted2,
  },
});
