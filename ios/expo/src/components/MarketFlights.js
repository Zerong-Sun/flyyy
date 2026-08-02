import React from 'react';
import {
  View,
  Text,
  Image,
  ScrollView,
  Pressable,
  StyleSheet,
} from 'react-native';
import { CITIES } from '../gameData';
import { money, tagColor, intel } from '../gameLogic';
import { assetSource } from '../assets';
import { COLORS } from '../theme';
import {
  AssetIcon,
  Button,
  ScreenTitle,
  SegControl,
  Sheet,
} from './ui';

function MiniSpark({ points }) {
  if (!points || points.length < 2) return null;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = Math.max(1, max - min);
  return (
    <View style={styles.sparkRow}>
      {points.map((v, i) => {
        const h = 4 + ((v - min) / span) * 14;
        return <View key={i} style={[styles.sparkBar, { height: h }]} />;
      })}
    </View>
  );
}

export function MarketScreen({ game }) {
  const { state, city, destId, productRows, setSeg, openProduct, setFocusDest, t, tf } = game;
  const sortCity = destId ? CITIES[destId] : null;
  const sortCityName = destId ? t(`city.${destId}`, CITIES[destId].name) : '';
  const marketSegs = [
    { value: 'local', label: t('market.seg_local', 'Local') },
    { value: 'imported', label: t('market.seg_imported', 'Imported') },
  ];

  return (
    <View style={styles.screen}>
      <ScreenTitle
        title={t('market_title', 'Market')}
        subtitle={
          sortCity
            ? tf('market.sorted_for', { city: city.name, dest: sortCityName }, `${city.name} · sorted for ${sortCityName}`)
            : `${city.name} · ${state.seg === 'local' ? t('market_here', 'local goods') : t('market_import', 'imports')}`
        }
      />
      {state.ticket && sortCity ? (
        <View style={styles.focusChip}>
          <Text style={styles.focusChipText}>
            {tf('market.ticket_to', { iata: sortCity.iata }, `Ticket → ${sortCity.iata}`)}
          </Text>
        </View>
      ) : state.focusDest && sortCity ? (
        <Pressable style={styles.focusChip} onPress={() => setFocusDest('')}>
          <Text style={styles.focusChipText}>
            {tf('market.watching', { iata: sortCity.iata }, `Watching ${sortCity.iata} · Clear`)}
          </Text>
        </Pressable>
      ) : null}
      <SegControl
        style={styles.seg}
        options={marketSegs}
        value={state.seg}
        onChange={setSeg}
      />
      <View style={styles.list}>
        {productRows.map((p) => (
          <Pressable
            key={p.id}
            style={({ pressed }) => [styles.productRow, pressed && styles.rowPressed]}
            onPress={() => openProduct(p.id)}
            accessibilityRole="button"
            accessibilityLabel={`${p.name}, ${p.buy}, ${p.weight}`}
          >
            <Image source={assetSource(p.icon)} style={styles.productIcon} accessible={false} />
            <View style={styles.productBody}>
              <View style={styles.productTitleRow}>
                <Text style={styles.productName} numberOfLines={1}>{p.name}</Text>
                <View style={[styles.originChip, p.isLocal ? styles.originLocal : styles.originImport]}>
                  <Text style={[styles.originText, p.isLocal ? styles.originLocalText : styles.originImportText]}>
                    {p.origin}
                  </Text>
                </View>
              </View>
              <Text style={styles.productMeta}>{p.meta}</Text>
              <MiniSpark points={p.spark} />
              {p.tag ? (
                <View style={styles.tagRow}>
                  <View style={[styles.tagDot, { backgroundColor: tagColor(p.tagKind) }]} />
                  <Text style={[styles.tagText, { color: tagColor(p.tagKind) }]}>{p.tag}</Text>
                </View>
              ) : null}
            </View>
            <View style={styles.productPriceCol}>
              <Text style={styles.productBuy}>{p.buy}</Text>
              <Text style={styles.productWeight}>{p.weight}</Text>
            </View>
          </Pressable>
        ))}
      </View>
      <View style={styles.tipCard}>
        <Text style={styles.tipTitle}>{t('market.tip_title', 'Over the limit?')}</Text>
        <Text style={styles.tipBody}>
          {t('market.tip_body', 'Buy baggage (+10 / +20 / +50 kg) when booking a flight.')}
        </Text>
      </View>
    </View>
  );
}

export function FlightsScreen({ game }) {
  const { state, city, sortedFlights, setFilter, openFlight, setFocusDest, t, tf } = game;
  const focusCity = state.focusDest ? CITIES[state.focusDest] : null;
  const focusCityName = state.focusDest ? t(`city.${state.focusDest}`, CITIES[state.focusDest].name) : '';
  const flightFilters = [
    { value: 'departure', label: t('flight.filter_departure', 'Departure') },
    { value: 'price', label: t('flight.filter_price', 'Price') },
    { value: 'duration', label: t('flight.filter_duration', 'Duration') },
    { value: 'unvisited', label: t('flight.filter_unvisited', 'New cities') },
    { value: 'biz', label: t('flight.filter_biz', 'Business') },
  ];

  return (
    <View style={styles.screen}>
      <ScreenTitle
        title={t('flights_title', 'Flights')}
        subtitle={
          focusCity
            ? tf('flight.departing_focus', { iata: city.iata, name: focusCityName }, `Departing ${city.iata} · focused on ${focusCityName}`)
            : tf('flight.departing', { iata: city.iata }, `Departing ${city.iata} · next 24 h`)
        }
      />
      {focusCity ? (
        <Pressable style={styles.focusChip} onPress={() => setFocusDest('')}>
          <Text style={styles.focusChipText}>
            {tf('flight.to_focus', { iata: focusCity.iata }, `To ${focusCity.iata} · Clear`)}
          </Text>
        </Pressable>
      ) : null}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        nestedScrollEnabled
        contentContainerStyle={styles.filtersRow}
      >
        {flightFilters.map((f) => {
          const active = state.filter === f.value;
          return (
            <Pressable
              key={f.value}
              onPress={() => setFilter(f.value)}
              style={[styles.filterChip, active && styles.filterChipActive]}
            >
              <Text style={[styles.filterText, active && styles.filterTextActive]}>{f.label}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <View style={styles.list}>
        {sortedFlights.length === 0 ? (
          <View style={styles.emptyBox}>
            <Text style={styles.emptyTitle}>{t('flight.no_departures', 'No departures')}</Text>
            <Text style={styles.emptySub}>
              {t('flight.empty_sub', 'Try another filter or clear the destination focus.')}
            </Text>
          </View>
        ) : null}
        {sortedFlights.map((f) => (
          <Pressable
            key={`${f.no}-${f.toId}-${f.depMin}`}
            style={({ pressed }) => [
              styles.flightCard,
              f.focused && styles.flightCardFocused,
              f.past && styles.flightCardPast,
              pressed && styles.rowPressed,
            ]}
            onPress={() => openFlight(f)}
            accessibilityRole="button"
            accessibilityLabel={tf('flight.a11y', {
              no: f.no,
              to: f.toName,
              dep: f.dep,
              price: money(f.econ),
              extra: f.isNext ? t('flight.next', 'Next') : '',
            }, `${f.no} to ${f.toName}, departs ${f.dep}, economy ${money(f.econ)}${f.isNext ? ', next departure' : ''}`)}
          >
            <View style={styles.flightHeader}>
              <Text style={[styles.flightNo, f.past && styles.flightTextPast]}>{f.no}</Text>
              <Text style={[styles.flightAirline, f.past && styles.flightTextPast]} numberOfLines={1}>{f.airline}</Text>
              {f.isNext ? (
                <View style={styles.nextChip}>
                  <Text style={styles.nextChipText}>{t('flight.next', 'Next')}</Text>
                </View>
              ) : null}
              {f.past ? (
                <View style={styles.tomorrowChip}>
                  <Text style={styles.tomorrowChipText}>{t('flight.tomorrow', 'Tomorrow')}</Text>
                </View>
              ) : null}
              {f.focused ? (
                <View style={styles.newCityChip}>
                  <Text style={styles.newCityText}>{t('flight.focus', 'Focus')}</Text>
                </View>
              ) : null}
              {f.unvisited ? (
                <View style={styles.newCityChip}>
                  <Text style={styles.newCityText}>{t('flight.new_city', 'New city')}</Text>
                </View>
              ) : null}
            </View>
            <View style={styles.flightTimes}>
              <View>
                <Text style={styles.timeBig}>{f.dep}</Text>
                <Text style={styles.iataSmall}>{f.from}</Text>
              </View>
              <View style={styles.flightMid}>
                <Text style={styles.durText}>{f.dur}</Text>
                <View style={styles.flightLine} />
                <Text style={styles.stopsText}>{f.stops}</Text>
              </View>
              <View style={styles.flightArr}>
                <Text style={styles.timeBig}>{f.arr}</Text>
                <Text style={styles.iataSmall}>{f.to}</Text>
              </View>
            </View>
            <View style={styles.flightFooter}>
              <Text style={styles.econPrice}>{tf('flight.econ', { price: money(f.econ) }, `Econ ${money(f.econ)}`)}</Text>
              <Text style={styles.bizPrice}>{tf('flight.biz', { price: money(f.biz) }, `Biz ${money(f.biz)}`)}</Text>
              <Text style={styles.kmText}>
                {tf('fmt.km', { n: f.km.toLocaleString('en-US') }, `${f.km.toLocaleString('en-US')} km`)}
              </Text>
            </View>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

export function MarketSheets({ game }) {
  const {
    state,
    city,
    destId,
    selProduct,
    unitHere,
    costTotal,
    wtTotal,
    over,
    slotUsed,
    slotCap,
    fareTotal,
    canBuy,
    canBook,
    bagOverKg,
    money,
    priceAt,
    closeSheet,
    setQty,
    setSlot,
    setCabin,
    setAddon,
    buy,
    buyTicket,
    add,
    addons,
    locale,
    t,
    tf,
  } = game;

  const selFlight = state.selFlight;
  const forecast = selProduct
    ? (destId ? money(priceAt(selProduct.id, destId)) : t('sheet.pick_dest', '— pick a destination'))
    : '';
  const selIntel = selProduct ? intel(selProduct.id, state.city, destId, locale) : { kind: '' };
  const selCat = selProduct ? t(`cat.${selProduct.category}`, selProduct.category) : '';

  return (
    <>
      <Sheet visible={state.sheet === 'product'} onClose={closeSheet}>
        {selProduct ? (
          <ScrollView style={styles.sheetScroll} contentContainerStyle={styles.sheetPad}>
            <View style={styles.sheetHeader}>
              <Image source={assetSource(selProduct.icon)} style={styles.sheetIcon} />
              <View style={styles.sheetHeaderText}>
                <Text style={styles.sheetTitle}>{selProduct.name}</Text>
                <Text style={styles.sheetSub}>
                  {tf('sheet.sub_product', { cat: selCat, w: selProduct.w.toFixed(1) }, `${selProduct.category} · ${selProduct.w.toFixed(1)} kg each`)}
                </Text>
              </View>
            </View>

            <View style={styles.priceGrid}>
              <View style={styles.priceCell}>
                <Text style={styles.priceLabel}>{t('sheet.buy_here', 'Buy here')}</Text>
                <Text style={styles.priceVal}>{money(unitHere)}</Text>
              </View>
              <View style={styles.priceCell}>
                <Text style={styles.priceLabel}>{t('sheet.sells_here', 'Sells here')}</Text>
                <Text style={[styles.priceVal, styles.priceMuted]}>
                  {money(unitHere)}
                </Text>
              </View>
              <View style={[styles.priceCell, { flex: 1.2 }]}>
                <Text style={styles.priceLabel}>{t('sheet.at_dest', 'At destination')}</Text>
                <Text style={[styles.priceVal, { color: tagColor(selIntel.kind) }]}>
                  {forecast}
                </Text>
              </View>
            </View>

            <View style={styles.qtyRow}>
              <Text style={styles.qtyLabel}>{t('sheet.quantity', 'Quantity')}</Text>
              <View style={styles.qtyControl}>
                <Pressable style={styles.qtyBtn} onPress={() => setQty(state.qty - 1)}>
                  <Text style={styles.qtyBtnText}>−</Text>
                </Pressable>
                <Text style={styles.qtyVal}>{state.qty}</Text>
                <Pressable style={styles.qtyBtn} onPress={() => setQty(state.qty + 1)}>
                  <Text style={styles.qtyBtnText}>+</Text>
                </Pressable>
              </View>
            </View>

            <SegControl
              style={styles.slotSeg}
              options={[
                { value: 'bag', label: t('sheet.carry_on', 'Carry-on') },
                { value: 'cargo', label: t('sheet.cargo_hold', 'Cargo hold') },
              ]}
              value={state.slot}
              onChange={setSlot}
            />

            <Text style={styles.costLine}>
              {tf('sheet.total', { total: money(costTotal), wt: (slotUsed + wtTotal).toFixed(1), cap: slotCap }, `Total ${money(costTotal)} · ${(slotUsed + wtTotal).toFixed(1)} / ${slotCap} kg`)}
              {over ? tf('sheet.over_limit', {}, ' · over limit') : ''}
            </Text>

            <Button variant="primary" onPress={buy} disabled={!canBuy}>
              {over
                ? t('sheet.over_weight', 'Over weight limit')
                : costTotal > state.cash
                  ? t('sheet.no_cash', 'Not enough cash')
                  : tf('sheet.buy_qty', { n: state.qty, total: money(costTotal) }, `Buy ${state.qty} for ${money(costTotal)}`)}
            </Button>
          </ScrollView>
        ) : null}
      </Sheet>

      <Sheet visible={state.sheet === 'flight'} onClose={closeSheet}>
        {selFlight ? (
          <ScrollView style={styles.sheetScroll} contentContainerStyle={styles.sheetPad}>
            <View style={styles.flightSheetTop}>
              <Text style={styles.flightNo}>{selFlight.no}</Text>
              <Text style={styles.flightAirline}>{selFlight.airline}</Text>
            </View>
            <View style={styles.flightSheetRoute}>
              <View>
                <Text style={styles.sheetTimeBig}>{selFlight.dep}</Text>
                <Text style={styles.sheetCity}>{city.name}</Text>
              </View>
              <Text style={styles.sheetMid}>
                {selFlight.dur} · {tf('fmt.km', { n: selFlight.km.toLocaleString('en-US') }, `${selFlight.km.toLocaleString('en-US')} km`)}
              </Text>
              <View style={styles.flightArr}>
                <Text style={styles.sheetTimeBig}>{selFlight.arr}</Text>
                <Text style={styles.sheetCity}>{t(`city.${selFlight.toId}`, CITIES[selFlight.toId].name)}</Text>
              </View>
            </View>

            <Text style={styles.sectionLabel}>{t('sheet.cabin', 'Cabin')}</Text>
            {['economy', 'business'].map((cabin) => {
              const active = state.cabin === cabin;
              const price = cabin === 'economy' ? selFlight.econ : selFlight.biz;
              return (
                <Pressable
                  key={cabin}
                  onPress={() => setCabin(cabin)}
                  style={[styles.cabinRow, active && styles.cabinRowActive]}
                >
                  <AssetIcon
                    path={cabin === 'economy' ? 'assets/ic_economy.webp' : 'assets/ic_business.webp'}
                    size={26}
                    tintColor={active ? COLORS.text : COLORS.muted}
                  />
                  <View style={styles.cabinBody}>
                    <Text style={[styles.cabinLabel, active && styles.cabinLabelActive]}>
                      {cabin === 'economy' ? t('sheet.cabin_economy', 'Economy') : t('sheet.cabin_business', 'Business')}
                    </Text>
                    <Text style={styles.cabinSub}>
                      {cabin === 'economy' ? t('sheet.seat_standard', 'Standard seat') : t('sheet.seat_biz', 'Extra legroom · lounge access')}
                    </Text>
                  </View>
                  <Text style={styles.cabinPrice}>{money(price)}</Text>
                </Pressable>
              );
            })}

            <Text style={styles.sectionLabel}>{t('sheet.extra_weight', 'Extra weight')}</Text>
            {bagOverKg > 0 ? (
              <View style={styles.warnBanner}>
                <Text style={styles.warnBannerText}>
                  {tf('sheet.overweight_warn', { n: bagOverKg.toFixed(1) }, `Carry-on over by ${bagOverKg.toFixed(1)} kg — you can still fly; add baggage or lighten in Bags.`)}
                </Text>
              </View>
            ) : null}
            <View style={styles.addonRow}>
              {addons.map((a) => {
                const active = state.addon === a.k;
                return (
                  <Pressable
                    key={a.k || 'none'}
                    onPress={() => setAddon(a.k)}
                    style={[styles.addonChip, active && styles.addonChipActive]}
                  >
                    <Text style={[styles.addonLabel, active && styles.addonLabelActive]}>
                      {a.label}
                    </Text>
                    <Text style={styles.addonPrice}>{money(a.price)}</Text>
                  </Pressable>
                );
              })}
            </View>

            <View style={styles.totalRow}>
              <Text style={styles.totalLabel}>{t('sheet.total_row', 'Total')}</Text>
              <Text style={styles.totalVal}>{money(fareTotal)}</Text>
            </View>
            <Text style={styles.addonNote}>
              {tf('sheet.includes_addon', { label: add.label }, `Includes ${add.label} baggage`)}
            </Text>

            <Button variant="primary" onPress={buyTicket} disabled={!canBook}>
              {state.ticket
                ? t('sheet.ticket_booked', 'Ticket already booked')
                : fareTotal > state.cash
                  ? t('sheet.no_cash', 'Not enough cash')
                  : tf('sheet.buy_ticket', { total: money(fareTotal) }, `Buy ticket · ${money(fareTotal)}`)}
            </Button>
            <Text style={styles.boardingNote}>
              {t('sheet.boarding_note', 'Boarding is mandatory. Once the gate closes you fly, cargo and all.')}
            </Text>
          </ScrollView>
        ) : null}
      </Sheet>
    </>
  );
}

const styles = StyleSheet.create({
  screen: {
    paddingTop: 12,
    paddingBottom: 24,
  },
  seg: {
    marginHorizontal: 16,
    marginTop: 14,
  },
  list: {
    paddingHorizontal: 16,
    paddingTop: 12,
    gap: 8,
  },
  productRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    padding: 10,
    backgroundColor: COLORS.panel,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  rowPressed: {
    backgroundColor: '#1B3A51',
    transform: [{ scale: 0.99 }],
  },
  productIcon: {
    width: 42,
    height: 42,
    borderRadius: 10,
    backgroundColor: COLORS.bg,
  },
  productBody: {
    flex: 1,
    minWidth: 0,
  },
  productTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  productName: {
    flex: 1,
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    letterSpacing: -0.24,
  },
  originChip: {
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 5,
  },
  originLocal: {
    backgroundColor: 'rgba(60, 184, 164, 0.15)',
  },
  originImport: {
    backgroundColor: 'rgba(126, 182, 217, 0.15)',
  },
  originText: {
    fontSize: 10,
    fontWeight: '600',
  },
  originLocalText: {
    color: COLORS.teal,
  },
  originImportText: {
    color: COLORS.blue,
  },
  productMeta: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  tagRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 5,
    alignSelf: 'flex-start',
    paddingHorizontal: 7,
    paddingVertical: 2,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  tagDot: {
    width: 5,
    height: 5,
    borderRadius: 3,
  },
  tagText: {
    fontSize: 11,
    fontWeight: '600',
  },
  productPriceCol: {
    alignItems: 'flex-end',
  },
  productBuy: {
    fontSize: 16,
    fontWeight: '700',
    color: COLORS.text,
  },
  productWeight: {
    fontSize: 11,
    color: COLORS.muted2,
    marginTop: 1,
  },
  tipCard: {
    marginHorizontal: 16,
    marginTop: 14,
    padding: 12,
    borderRadius: 14,
    backgroundColor: 'rgba(60, 184, 164, 0.08)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(60, 184, 164, 0.22)',
  },
  tipTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.teal,
  },
  tipBody: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 3,
    lineHeight: 17,
  },
  focusChip: {
    alignSelf: 'flex-start',
    marginHorizontal: 16,
    marginTop: 10,
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 10,
    backgroundColor: 'rgba(232, 154, 60, 0.14)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(232, 154, 60, 0.35)',
  },
  focusChipText: {
    fontSize: 12,
    fontWeight: '600',
    color: COLORS.orange,
  },
  emptyBox: {
    padding: 28,
    alignItems: 'center',
    backgroundColor: COLORS.panel,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  emptyTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  emptySub: {
    fontSize: 13,
    color: COLORS.muted,
    marginTop: 4,
    textAlign: 'center',
  },
  filtersRow: {
    paddingHorizontal: 16,
    paddingTop: 14,
    gap: 7,
  },
  flightCardFocused: {
    borderColor: COLORS.orange,
  },
  flightCardPast: {
    opacity: 0.55,
  },
  flightTextPast: {
    color: COLORS.muted2,
  },
  nextChip: {
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 5,
    backgroundColor: 'rgba(60, 184, 164, 0.2)',
  },
  nextChipText: {
    fontSize: 10,
    fontWeight: '700',
    color: COLORS.teal,
  },
  tomorrowChip: {
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 5,
    backgroundColor: 'rgba(168, 184, 200, 0.15)',
  },
  tomorrowChipText: {
    fontSize: 10,
    fontWeight: '600',
    color: COLORS.muted,
  },
  sparkRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 2,
    height: 18,
    marginTop: 4,
  },
  sparkBar: {
    width: 3,
    borderRadius: 1,
    backgroundColor: 'rgba(96, 168, 214, 0.55)',
  },
  sheetScroll: {
    maxHeight: '100%',
  },
  filterChip: {
    paddingVertical: 7,
    paddingHorizontal: 12,
    borderRadius: 10,
    backgroundColor: COLORS.panel2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
  },
  filterChipActive: {
    backgroundColor: COLORS.border2,
  },
  filterText: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.muted,
  },
  filterTextActive: {
    color: COLORS.text,
  },
  flightCard: {
    padding: 12,
    backgroundColor: COLORS.panel,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  flightHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  flightNo: {
    fontFamily: 'monospace',
    fontSize: 12,
    fontWeight: '700',
    color: COLORS.teal,
  },
  flightAirline: {
    flex: 1,
    fontSize: 12,
    color: COLORS.muted,
  },
  newCityChip: {
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 5,
    backgroundColor: 'rgba(232, 154, 60, 0.15)',
  },
  newCityText: {
    fontSize: 10,
    fontWeight: '600',
    color: COLORS.orange,
  },
  flightTimes: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: 8,
  },
  timeBig: {
    fontSize: 20,
    fontWeight: '700',
    color: COLORS.text,
  },
  iataSmall: {
    fontSize: 11,
    color: COLORS.muted2,
    fontFamily: 'monospace',
  },
  flightMid: {
    flex: 1,
    alignItems: 'center',
    gap: 3,
  },
  durText: {
    fontSize: 10,
    color: COLORS.muted,
  },
  flightLine: {
    width: '100%',
    height: 1,
    backgroundColor: COLORS.border2,
  },
  stopsText: {
    fontSize: 10,
    color: COLORS.muted2,
  },
  flightArr: {
    alignItems: 'flex-end',
  },
  flightFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 10,
    paddingTop: 9,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: COLORS.border,
  },
  econPrice: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.blue,
  },
  bizPrice: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.gold,
  },
  kmText: {
    flex: 1,
    textAlign: 'right',
    fontSize: 12,
    color: COLORS.muted2,
  },
  sheetPad: {
    paddingHorizontal: 18,
    paddingBottom: 8,
    gap: 12,
  },
  sheetHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginTop: 4,
  },
  sheetIcon: {
    width: 56,
    height: 56,
    borderRadius: 13,
    backgroundColor: COLORS.bg,
  },
  sheetHeaderText: {
    flex: 1,
    minWidth: 0,
  },
  sheetTitle: {
    fontSize: 19,
    fontWeight: '700',
    color: COLORS.text,
    letterSpacing: -0.4,
  },
  sheetSub: {
    fontSize: 13,
    color: COLORS.muted,
    marginTop: 2,
  },
  priceGrid: {
    flexDirection: 'row',
    padding: 12,
    borderRadius: 14,
    backgroundColor: COLORS.panel3,
  },
  priceCell: {
    flex: 1,
  },
  priceLabel: {
    fontSize: 11,
    color: COLORS.muted,
  },
  priceVal: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.text,
    marginTop: 2,
  },
  priceMuted: {
    color: COLORS.muted3,
  },
  qtyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  qtyLabel: {
    flex: 1,
    fontSize: 15,
    color: COLORS.text,
  },
  qtyControl: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.panel3,
    borderRadius: 12,
    padding: 3,
  },
  qtyBtn: {
    width: 44,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 10,
  },
  qtyBtnText: {
    fontSize: 22,
    fontWeight: '600',
    color: COLORS.text,
  },
  qtyVal: {
    minWidth: 52,
    textAlign: 'center',
    fontSize: 19,
    fontWeight: '700',
    color: COLORS.text,
  },
  slotSeg: {
    marginTop: 4,
  },
  costLine: {
    fontSize: 13,
    color: COLORS.muted,
  },
  flightSheetTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 4,
  },
  flightSheetRoute: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 12,
  },
  sheetTimeBig: {
    fontSize: 26,
    fontWeight: '700',
    color: COLORS.text,
  },
  sheetCity: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  sheetMid: {
    flex: 1,
    textAlign: 'center',
    fontSize: 12,
    color: COLORS.muted2,
    paddingBottom: 6,
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: COLORS.muted2,
    letterSpacing: 0.4,
    textTransform: 'uppercase',
  },
  cabinRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 12,
    borderRadius: 15,
    backgroundColor: COLORS.panel3,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  cabinRowActive: {
    borderColor: COLORS.teal,
    backgroundColor: 'rgba(60, 184, 164, 0.08)',
  },
  cabinBody: {
    flex: 1,
  },
  cabinLabel: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.muted,
  },
  cabinLabelActive: {
    color: COLORS.text,
  },
  cabinSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 1,
  },
  cabinPrice: {
    fontSize: 17,
    fontWeight: '700',
    color: COLORS.text,
  },
  addonRow: {
    flexDirection: 'row',
    gap: 8,
  },
  addonChip: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 10,
    borderRadius: 12,
    backgroundColor: COLORS.panel3,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  addonChipActive: {
    borderColor: COLORS.orange,
    backgroundColor: 'rgba(232, 154, 60, 0.1)',
  },
  addonLabel: {
    fontSize: 14,
    fontWeight: '700',
    color: COLORS.muted,
  },
  addonLabelActive: {
    color: COLORS.orange,
  },
  addonPrice: {
    fontSize: 11,
    color: COLORS.muted,
    marginTop: 1,
  },
  totalRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
  },
  totalLabel: {
    flex: 1,
    fontSize: 15,
    color: COLORS.text,
  },
  totalVal: {
    fontSize: 22,
    fontWeight: '700',
    color: COLORS.text,
  },
  addonNote: {
    fontSize: 11,
    color: COLORS.muted2,
    marginTop: -6,
  },
  warnBanner: {
    backgroundColor: 'rgba(224, 85, 85, 0.14)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(224, 85, 85, 0.35)',
    marginBottom: 4,
  },
  warnBannerText: {
    fontSize: 13,
    color: COLORS.red,
    lineHeight: 18,
  },
  boardingNote: {
    fontSize: 11,
    color: COLORS.muted2,
    textAlign: 'center',
    lineHeight: 16,
  },
});
