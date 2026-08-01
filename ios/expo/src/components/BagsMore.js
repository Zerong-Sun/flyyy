import React from 'react';
import {
  View,
  Text,
  Image,
  ScrollView,
  Pressable,
  Modal,
  Alert,
  StyleSheet,
} from 'react-native';
import {
  ACHIEVEMENTS,
  CIDS,
  CITIES,
  NOTE_TEXT,
  SOURCES,
  STARTING_CASH,
} from '../gameData';
import { assetSource } from '../assets';
import { money } from '../gameLogic';
import { COLORS } from '../theme';
import {
  AssetIcon,
  Button,
  Card,
  ScreenTitle,
  Sheet,
  Toggle,
} from './ui';

export function BagsScreen({ game }) {
  const { state, bagText, cargoText, bagKg, openSell, openInvItem } = game;
  const pct = state.bagLimit > 0
    ? Math.min(100, Math.round((bagKg / state.bagLimit) * 100))
    : 0;

  return (
    <View style={styles.screen}>
      <ScreenTitle title="Baggage" subtitle="Weight decides what you can carry" />

      <Card style={styles.weightCard}>
        <View style={[styles.ring, { borderColor: pct >= 90 ? COLORS.red : COLORS.teal }]}>
          <View style={styles.ringInner}>
            <Text style={styles.ringPct}>{pct}%</Text>
            <Text style={styles.ringLabel}>carry-on</Text>
          </View>
        </View>
        <View style={styles.weightStats}>
          <View>
            <Text style={styles.weightLabel}>Carry-on</Text>
            <Text style={styles.weightVal}>{bagText}</Text>
          </View>
          <View>
            <Text style={styles.weightLabel}>Cargo hold</Text>
            <Text style={styles.weightVal}>{cargoText}</Text>
          </View>
        </View>
      </Card>

      <View style={styles.list}>
        {state.inv.length === 0 ? (
          <View style={styles.emptyBox}>
            <Text style={styles.emptyTitle}>Nothing on board</Text>
            <Text style={styles.emptySub}>Buy goods in the market before you fly.</Text>
          </View>
        ) : (
          state.inv.map((item, idx) => (
            <Pressable
              key={`${item.id}-${item.slot}-${idx}`}
              style={styles.invRow}
              onPress={() => openInvItem(item)}
              accessibilityRole="button"
              accessibilityLabel={`${item.name}, ${item.n} units, ${(item.w * item.n).toFixed(1)} kilograms, ${item.slot === 'cargo' ? 'cargo' : 'carry-on'}`}
            >
              <Image source={assetSource(item.icon)} style={styles.invIcon} accessible={false} />
              <View style={styles.invBody}>
                <Text style={styles.invName}>{item.name}</Text>
                <Text style={styles.invMeta}>
                  {item.n} × {money(item.cost)} · {(item.w * item.n).toFixed(1)} kg
                </Text>
              </View>
              <View style={[styles.slotChip, item.slot === 'cargo' ? styles.slotCargo : styles.slotBag]}>
                <AssetIcon
                  path={item.slot === 'cargo' ? 'assets/ic_cargo.webp' : 'assets/ic_baggage.webp'}
                  size={16}
                  tintColor={item.slot === 'cargo' ? COLORS.gold : COLORS.blue}
                />
                <Text style={[styles.slotText, item.slot === 'cargo' ? styles.slotCargoText : styles.slotBagText]}>
                  {item.slot}
                </Text>
              </View>
            </Pressable>
          ))
        )}
      </View>

      {state.inv.length > 0 ? (
        <Button variant="primary" style={styles.sellBtn} onPress={openSell}>
          Review sale
        </Button>
      ) : null}
    </View>
  );
}

function BackButton({ onPress }) {
  return (
    <Pressable
      style={styles.backBtn}
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel="Back"
    >
      <Text style={styles.backArrow} accessible={false}>‹</Text>
    </Pressable>
  );
}

export function MoreScreen({ game }) {
  const { state, stats, city, setPage, restart, saveNow, saveSub, toggleOpt } = game;
  const page = state.page;

  if (page === 'ach') {
    const unlockedList = state.unlockedAch || [];
    const unlocked = ACHIEVEMENTS.filter(
      (a) => unlockedList.includes(a.id) || (stats[a.stat] || 0) >= a.goal,
    ).length;
    const achPct = `${Math.round((unlocked / ACHIEVEMENTS.length) * 100)}%`;

    return (
      <View style={styles.screen}>
        <View style={styles.subHeader}>
          <BackButton onPress={() => setPage(null)} />
          <ScreenTitle title="Achievements" style={styles.subTitle} />
        </View>
        <Card style={styles.achSummary}>
          <View style={styles.achSummaryRow}>
            <Text style={styles.achSummaryLabel}>Unlocked</Text>
            <Text style={styles.achScore}>{unlocked} / {ACHIEVEMENTS.length}</Text>
          </View>
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: achPct }]} />
          </View>
        </Card>
        <View style={styles.list}>
          {ACHIEVEMENTS.map((ac) => {
            const val = stats[ac.stat] || 0;
            const done = unlockedList.includes(ac.id) || val >= ac.goal;
            const pct = `${Math.min(100, Math.round((val / ac.goal) * 100))}%`;
            return (
              <View key={ac.id} style={[styles.achRow, !done && styles.achRowLocked]}>
                <Image
                  source={assetSource(ac.icon)}
                  style={[styles.achIcon, !done && styles.achIconLocked]}
                  accessible={false}
                />
                <View style={styles.achBody}>
                  <Text style={styles.achName}>{ac.name}</Text>
                  <Text style={styles.achDesc}>{ac.desc}</Text>
                  {!done ? (
                    <View style={styles.miniTrack}>
                      <View style={[styles.miniFill, { width: pct }]} />
                    </View>
                  ) : null}
                </View>
                <View style={[styles.achChip, done ? styles.achChipDone : styles.achChipPending]}>
                  <Text style={[styles.achChipText, done ? styles.achChipTextDone : styles.achChipTextPending]}>
                    {done ? 'Done' : `${val}/${ac.goal}`}
                  </Text>
                </View>
              </View>
            );
          })}
        </View>
      </View>
    );
  }

  if (page === 'notes') {
    return (
      <View style={styles.screen}>
        <View style={styles.subHeader}>
          <BackButton onPress={() => setPage(null)} />
          <ScreenTitle
            title="Trader notes"
            subtitle={`${state.visited.length} cities visited`}
            style={styles.subTitle}
          />
        </View>
        <View style={styles.list}>
          {CIDS.map((cid) => {
            const c = CITIES[cid];
            const visited = state.visited.includes(cid);
            return (
              <Card key={cid} style={[styles.noteCard, !visited && styles.noteLocked]}>
                <View style={styles.noteHeroWrap}>
                  <Image source={assetSource(c.hero)} style={styles.noteHero} />
                  <View style={styles.noteHeroShade} />
                  <View style={styles.noteHeroLabels}>
                    <View style={styles.noteHeroText}>
                      <Text style={styles.noteCity}>{c.name}</Text>
                      <Text style={styles.noteCode}>{c.iata} · {c.country}</Text>
                    </View>
                    <View style={[styles.noteChip, visited ? styles.noteChipVisited : styles.noteChipLocked]}>
                      <Text style={[styles.noteChipText, visited ? styles.noteChipTextVisited : styles.noteChipTextLocked]}>
                        {visited ? 'Visited' : 'Locked'}
                      </Text>
                    </View>
                  </View>
                </View>
                <Text style={styles.noteBody}>
                  {visited ? NOTE_TEXT[cid] : 'Fly here to unlock trading notes for this hub.'}
                </Text>
              </Card>
            );
          })}
        </View>
      </View>
    );
  }

  if (page === 'log') {
    const net = state.cash - STARTING_CASH;
    return (
      <View style={styles.screen}>
        <View style={styles.subHeader}>
          <BackButton onPress={() => setPage(null)} />
          <ScreenTitle
            title="Trade log"
            subtitle={`${state.legs} ${state.legs === 1 ? 'leg' : 'legs'} flown`}
            style={styles.subTitle}
          />
        </View>

        <Card style={styles.logSummary}>
          <View style={styles.logCell}>
            <Text style={styles.logCellLabel}>Net profit</Text>
            <Text style={[styles.logCellVal, { color: net >= 0 ? COLORS.teal : COLORS.red }]}>
              {net >= 0 ? '+' : '−'}{money(Math.abs(net))}
            </Text>
          </View>
          <View style={styles.logDivider} />
          <View style={styles.logCell}>
            <Text style={styles.logCellLabel}>Distance</Text>
            <Text style={styles.logCellVal}>{state.km.toLocaleString('en-US')} km</Text>
          </View>
          <View style={styles.logDivider} />
          <View style={styles.logCell}>
            <Text style={styles.logCellLabel}>Legs</Text>
            <Text style={styles.logCellVal}>{state.legs}</Text>
          </View>
        </Card>

        {state.log.length === 0 ? (
          <View style={[styles.emptyBox, styles.logEmpty]}>
            <Text style={styles.emptyTitle}>No entries yet</Text>
            <Text style={styles.emptySub}>Every buy, booking, landing and sale lands here.</Text>
          </View>
        ) : (
          <View style={styles.list}>
            {state.log.map((l, i) => (
              <View key={`${l.title}-${l.t}-${i}`} style={styles.logRow}>
                <Image source={assetSource(l.icon)} style={styles.logIcon} />
                <View style={styles.logBody}>
                  <Text style={styles.logTitle} numberOfLines={1}>{l.title}</Text>
                  <Text style={styles.logSub}>{l.sub}</Text>
                </View>
                {l.amount ? (
                  <Text style={[styles.logAmount, { color: l.color }]}>{l.amount}</Text>
                ) : null}
              </View>
            ))}
          </View>
        )}
      </View>
    );
  }

  if (page === 'sources') {
    return (
      <View style={styles.screen}>
        <View style={styles.subHeader}>
          <BackButton onPress={() => setPage(null)} />
          <ScreenTitle title="Data sources" style={styles.subTitle} />
        </View>
        <View style={styles.warnBox}>
          <Text style={styles.warnText}>
            The flight network is rebuilt from public aviation data. Schedules, fares and prices are simulated for play — this is not real ticketing information.
          </Text>
        </View>
        <Card style={styles.sourcesCard}>
          {SOURCES.map((src, i) => (
            <View key={src.name} style={[styles.sourceRow, i < SOURCES.length - 1 && styles.sourceBorder]}>
              <View style={styles.sourceHeader}>
                <Text style={styles.sourceName}>{src.name}</Text>
                <View style={styles.licenseChip}>
                  <Text style={styles.licenseText}>{src.license}</Text>
                </View>
              </View>
              <Text style={styles.sourceUse}>{src.use}</Text>
            </View>
          ))}
        </Card>
      </View>
    );
  }

  if (page === 'settings') {
    const toggles = [
      ['optHaptics', 'Haptic feedback', 'A tap on every buy, sell and boarding call.'],
      ['optSound', 'Sound clicks', 'Light click feel on buy, sell, and takeoff (no audio files).'],
      ['optPush', 'Boarding notifications', 'Alert you when the gate is about to close.'],
      ['opt24h', '24-hour clock', 'Show all times as 00:00–23:59.'],
      ['optReduce', 'Reduce motion', 'Shorten the flight cutscene.'],
    ];

    return (
      <View style={styles.screen}>
        <View style={styles.subHeader}>
          <BackButton onPress={() => setPage(null)} />
          <ScreenTitle title="Settings & save" style={styles.subTitle} />
        </View>

        <Card style={styles.settingsCard}>
          {toggles.map(([key, label, sub], i) => (
            <View key={key} style={i < toggles.length - 1 ? styles.toggleBorder : null}>
              <Toggle
                label={label}
                sub={sub}
                value={!!state[key]}
                onToggle={() => toggleOpt(key)}
              />
            </View>
          ))}
        </Card>

        <Card style={styles.settingsCard}>
          <View style={styles.settingsRow}>
            <AssetIcon path="assets/ic_save.webp" size={22} tintColor={COLORS.text} />
            <View style={styles.settingsBody}>
              <Text style={styles.settingsTitle}>Save slot 1</Text>
              <Text style={styles.settingsSub}>{saveSub}</Text>
            </View>
          </View>
          <View style={styles.settingsActions}>
            <Button variant="secondary" style={styles.settingsBtn} onPress={saveNow}>
              Save now
            </Button>
          </View>
          <Text style={styles.settingsNote}>
            The run also saves itself as you play, and comes back when you reopen the app.
          </Text>
        </Card>

        <Card style={styles.settingsCard}>
          <View style={styles.settingsRow}>
            <AssetIcon path="assets/ic_city.webp" size={22} tintColor={COLORS.text} />
            <View style={styles.settingsBody}>
              <Text style={styles.settingsTitle}>New run</Text>
              <Text style={styles.settingsSub}>
                Restart in Istanbul with {money(STARTING_CASH)} cash
              </Text>
            </View>
          </View>
          <View style={styles.settingsActions}>
            <Button
              variant="secondary"
              style={styles.settingsBtn}
              onPress={() => {
                Alert.alert(
                  'Start a new run?',
                  'This clears your save and returns you to Istanbul.',
                  [
                    { text: 'Keep playing', style: 'cancel' },
                    { text: 'Restart', style: 'destructive', onPress: restart },
                  ],
                );
              }}
            >
              Restart game
            </Button>
          </View>
        </Card>

        <Text style={styles.version}>Airborne Trader · Demo build 0.3</Text>
      </View>
    );
  }

  const unlocked = ACHIEVEMENTS.filter(
    (a) => (state.unlockedAch || []).includes(a.id) || (stats[a.stat] || 0) >= a.goal,
  ).length;
  const menuRows = [
    { key: 'notes', label: 'Trader notes', icon: 'assets/ach_cities_10.webp', value: `${state.visited.length} / ${CIDS.length}` },
    { key: 'ach', label: 'Achievements', icon: 'assets/ach_legendary.webp', value: `${unlocked} / ${ACHIEVEMENTS.length}` },
    { key: 'log', label: 'Trade log', icon: 'assets/ic_log.webp', value: state.log.length ? String(state.log.length) : '' },
    { key: 'sources', label: 'Data sources', icon: 'assets/ic_attr.webp', value: '' },
    { key: 'settings', label: 'Settings & save', icon: 'assets/ic_save.webp', value: '' },
  ];

  return (
    <View style={styles.screen}>
      <ScreenTitle title="More" />
      <Card style={styles.menuCard}>
        {menuRows.map((row, i) => (
          <Pressable
            key={row.key}
            onPress={() => setPage(row.key)}
            style={({ pressed }) => [
              styles.menuRow,
              i < menuRows.length - 1 && styles.menuBorder,
              pressed && styles.menuRowPressed,
            ]}
          >
            <AssetIcon path={row.icon} size={22} tintColor={COLORS.text} />
            <Text style={styles.menuLabel}>{row.label}</Text>
            <Text style={styles.menuValue}>{row.value}</Text>
            <Text style={styles.menuChevron}>›</Text>
          </Pressable>
        ))}
      </Card>
      <Text style={styles.moreHint}>
        1 real second = 6 in-game minutes. A full trade run fits in about a minute.
      </Text>
      <Text style={styles.moreCity}>Currently in {city.name}</Text>
    </View>
  );
}

export function OverlaySheets({ game }) {
  const {
    state,
    city,
    sell,
    hm,
    closeSheet,
    runCutscene,
    sellAll,
    startGame,
    money,
    selInvItem,
    invGross,
    setInvQty,
    sellQty,
    discardQty,
    moveInvSlot,
    manageInBags,
  } = game;

  const ticket = state.ticket;
  const cut = state.cut;
  const invMax = selInvItem ? selInvItem.n : 1;
  const moveLabel = selInvItem?.slot === 'cargo' ? 'Move to carry-on' : 'Move to cargo';

  return (
    <>
      <Sheet visible={state.sheet === 'ff'} onClose={closeSheet} center>
        <View style={styles.ffBody}>
          <Text style={styles.ffTitle}>Speed up to takeoff?</Text>
          <Text style={styles.ffText}>
            {ticket
              ? `Skip the wait (${hm(state.minsToDep)} left) and fly ${ticket.from} → ${ticket.to} now.`
              : 'Skip the wait and board immediately.'}
          </Text>
        </View>
        <View style={styles.ffActions}>
          <Pressable style={styles.ffBtn} onPress={closeSheet}>
            <Text style={styles.ffCancel}>Cancel</Text>
          </Pressable>
          <View style={styles.ffDivider} />
          <Pressable style={styles.ffBtn} onPress={() => runCutscene()}>
            <Text style={styles.ffConfirm}>Speed up</Text>
          </Pressable>
        </View>
      </Sheet>

      <Sheet visible={state.sheet === 'sell'} onClose={closeSheet}>
        <ScrollView>
          <View style={styles.sellHeroWrap}>
            <Image source={assetSource(city.hero)} style={styles.sellHero} accessible={false} />
            <View style={styles.sellHeroShade} />
            <View style={styles.sellHeroLabels}>
              <Text style={styles.sellPhase}>Landed</Text>
              <Text style={styles.sellCity}>{city.name}</Text>
            </View>
          </View>
          <View style={styles.sheetPad}>
            {state.overweightNote ? (
              <View style={styles.warnBanner}>
                <Text style={styles.warnBannerText}>{state.overweightNote}</Text>
              </View>
            ) : null}
            <Text style={styles.sellHeadline}>
              {sell.net >= 0
                ? `Market looks good — ${money(sell.net)} net if you sell now.`
                : `Tough market — ${money(-sell.net)} down if you sell now.`}
            </Text>
            {sell.rows.map((row, idx) => (
              <View key={idx} style={styles.sellRow}>
                <Image source={assetSource(row.icon)} style={styles.sellIcon} accessible={false} />
                <View style={styles.sellRowBody}>
                  <Text style={styles.sellRowName}>{row.name}</Text>
                  <Text style={styles.sellRowMeta}>{row.meta}</Text>
                </View>
                <View style={styles.sellRowPrice}>
                  <Text style={[styles.sellDelta, { color: row.color }]}>{row.delta}</Text>
                  <Text style={styles.sellGross}>{row.gross}</Text>
                </View>
              </View>
            ))}
            <View style={styles.totalRow}>
              <Text style={styles.totalLabel}>Net profit</Text>
              <Text style={[styles.totalVal, { color: sell.net >= 0 ? COLORS.teal : COLORS.red }]}>
                {sell.net >= 0 ? '+' : '−'}{money(Math.abs(sell.net))}
              </Text>
            </View>
            <Button
              variant="primary"
              onPress={sellAll}
              style={styles.sellAllBtn}
              disabled={!state.inv.length}
            >
              Sell everything
            </Button>
            <Button
              variant="secondary"
              onPress={manageInBags}
              style={styles.manageBagsBtn}
            >
              Manage in Bags
            </Button>
            <Button variant="ghost" onPress={closeSheet}>
              Hold and look for a better market
            </Button>
          </View>
        </ScrollView>
      </Sheet>

      <Sheet visible={state.sheet === 'inv' && !!selInvItem} onClose={closeSheet}>
        {selInvItem ? (
          <ScrollView contentContainerStyle={styles.sheetPad}>
            <View style={styles.invSheetTop}>
              <Image source={assetSource(selInvItem.icon)} style={styles.invSheetIcon} accessible={false} />
              <View style={styles.invSheetBody}>
                <Text style={styles.invSheetName}>{selInvItem.name}</Text>
                <Text style={styles.invSheetMeta}>
                  {selInvItem.n} on hand · {selInvItem.slot === 'cargo' ? 'Cargo' : 'Carry-on'} · cost {money(selInvItem.cost)}
                </Text>
              </View>
            </View>

            <View style={styles.qtyRow}>
              <Text style={styles.qtyLabel}>Quantity</Text>
              <View style={styles.qtyControl}>
                <Pressable
                  style={styles.qtyBtn}
                  onPress={() => setInvQty(state.invQty - 1)}
                  accessibilityRole="button"
                  accessibilityLabel="Decrease quantity"
                >
                  <Text style={styles.qtyBtnText}>−</Text>
                </Pressable>
                <Text style={styles.qtyVal}>{state.invQty}</Text>
                <Pressable
                  style={styles.qtyBtn}
                  onPress={() => setInvQty(state.invQty + 1)}
                  accessibilityRole="button"
                  accessibilityLabel="Increase quantity"
                >
                  <Text style={styles.qtyBtnText}>+</Text>
                </Pressable>
              </View>
            </View>
            <Pressable onPress={() => setInvQty(invMax)}>
              <Text style={styles.qtyMaxHint}>Max {invMax}</Text>
            </Pressable>

            <Text style={styles.invSheetPrice}>
              Local price {money(invGross)} for {state.invQty}
            </Text>

            <Button variant="primary" onPress={() => sellQty(state.invQty)} style={styles.sellAllBtn}>
              {`Sell ${state.invQty} · ${money(invGross)}`}
            </Button>
            <Button variant="secondary" onPress={moveInvSlot} style={styles.manageBagsBtn}>
              {moveLabel}
            </Button>
            <Button variant="ghost" onPress={() => discardQty(state.invQty)}>
              Discard
            </Button>
          </ScrollView>
        ) : null}
      </Sheet>

      <Modal visible={!!cut} animationType="fade" transparent={false}>
        <View style={styles.cutscene}>
          <Image
            source={assetSource(cut?.art || 'assets/anim_flight_takeoff.webp')}
            style={styles.cutArt}
            resizeMode="cover"
            accessible={false}
          />
          <View style={styles.cutShade} />
          <View style={styles.cutContent}>
            <Text style={styles.cutPhase}>{cut?.phase || ''}</Text>
            <Text style={styles.cutTitle}>{cut?.title || ''}</Text>
            <Text style={styles.cutSub}>{state.cutLine}</Text>
            <View style={styles.cutTrack}>
              <View style={[styles.cutFill, { width: cut?.pct || '22%' }]} />
            </View>
            <Text style={styles.cutHint}>Flight time is on the world clock</Text>
          </View>
        </View>
      </Modal>

      <Modal visible={state.intro} animationType="fade">
        <View style={styles.intro}>
          <Image
            source={assetSource('assets/city_istanbul.webp')}
            style={styles.introBg}
            resizeMode="cover"
            accessible={false}
          />
          <View style={styles.introShade} />
          <View style={styles.introContent}>
            <Image source={assetSource('assets/logo_mark.webp')} style={styles.introLogo} accessible={false} />
            <Text style={styles.introTitle}>Airborne Trader</Text>
            <Text style={styles.introLead}>
              Twelve hub airports. Buy low where a thing is made, fly it somewhere it is scarce, sell high. Weight is the whole game.
            </Text>
            {[
              { icon: 'assets/ic_market.webp', title: 'Buy where it is made', sub: 'Local goods price low at their origin.' },
              { icon: 'assets/ic_flight.webp', title: 'Fly the network', sub: 'Book a real route, then speed up to land.' },
              { icon: 'assets/ic_inventory.webp', title: 'Mind the kilos', sub: '23 kg carry-on. Buy more, or use the hold.' },
            ].map((step) => (
              <View key={step.title} style={styles.introStep}>
                <View style={styles.introStepIcon}>
                  <AssetIcon path={step.icon} size={20} tintColor={COLORS.text} />
                </View>
                <View style={styles.introStepText}>
                  <Text style={styles.introStepTitle}>{step.title}</Text>
                  <Text style={styles.introStepSub}>{step.sub}</Text>
                </View>
              </View>
            ))}
            <Button variant="primary" onPress={startGame} style={styles.introBtn}>
              Start in Istanbul
            </Button>
            <Text style={styles.introFine}>
              Flight network rebuilt from public aviation data. Not real ticketing information.
            </Text>
          </View>
        </View>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  screen: {
    paddingTop: 12,
    paddingBottom: 24,
  },
  weightCard: {
    marginHorizontal: 16,
    marginTop: 16,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 18,
  },
  ring: {
    width: 104,
    height: 104,
    borderRadius: 52,
    borderWidth: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ringInner: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: COLORS.panel,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ringPct: {
    fontSize: 19,
    fontWeight: '700',
    color: COLORS.text,
  },
  ringLabel: {
    fontSize: 10,
    color: COLORS.muted,
    marginTop: 1,
  },
  weightStats: {
    flex: 1,
    gap: 9,
  },
  weightLabel: {
    fontSize: 11,
    color: COLORS.muted,
  },
  weightVal: {
    fontSize: 16,
    fontWeight: '600',
    color: COLORS.text,
    marginTop: 2,
  },
  list: {
    paddingHorizontal: 16,
    paddingTop: 14,
    gap: 8,
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
  invRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    padding: 10,
    backgroundColor: COLORS.panel,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  invIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: COLORS.bg,
  },
  invBody: {
    flex: 1,
    minWidth: 0,
  },
  invName: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  invMeta: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  slotChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 7,
  },
  slotBag: {
    backgroundColor: 'rgba(126, 182, 217, 0.15)',
  },
  slotCargo: {
    backgroundColor: 'rgba(201, 164, 92, 0.15)',
  },
  slotText: {
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  slotBagText: {
    color: COLORS.blue,
  },
  slotCargoText: {
    color: COLORS.gold,
  },
  sellBtn: {
    marginHorizontal: 16,
    marginTop: 14,
  },
  subHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 16,
  },
  subTitle: {
    flex: 1,
    paddingHorizontal: 0,
  },
  backBtn: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: COLORS.panel2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  backArrow: {
    fontSize: 28,
    lineHeight: 30,
    color: COLORS.muted,
    marginTop: -2,
  },
  achSummary: {
    marginHorizontal: 16,
    marginTop: 14,
    padding: 14,
  },
  achSummaryRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
  },
  achSummaryLabel: {
    flex: 1,
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  achScore: {
    fontSize: 19,
    fontWeight: '700',
    color: COLORS.orange,
  },
  progressTrack: {
    marginTop: 10,
    height: 6,
    borderRadius: 3,
    backgroundColor: COLORS.panel3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 3,
    backgroundColor: COLORS.teal,
  },
  achRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 11,
    backgroundColor: COLORS.panel,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.teal,
  },
  achRowLocked: {
    opacity: 0.75,
    borderColor: COLORS.border,
  },
  achIcon: {
    width: 44,
    height: 44,
    borderRadius: 11,
    backgroundColor: COLORS.bg,
  },
  achIconLocked: {
    opacity: 0.45,
  },
  achBody: {
    flex: 1,
    minWidth: 0,
  },
  achName: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  achDesc: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
    lineHeight: 16,
  },
  miniTrack: {
    marginTop: 6,
    height: 4,
    borderRadius: 2,
    backgroundColor: COLORS.panel3,
    overflow: 'hidden',
  },
  miniFill: {
    height: '100%',
    borderRadius: 2,
    backgroundColor: COLORS.teal,
  },
  achChip: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 7,
  },
  achChipDone: {
    backgroundColor: 'rgba(60, 184, 164, 0.15)',
  },
  achChipPending: {
    backgroundColor: COLORS.panel3,
  },
  achChipText: {
    fontSize: 11,
    fontWeight: '700',
  },
  achChipTextDone: {
    color: COLORS.teal,
  },
  achChipTextPending: {
    color: COLORS.muted,
  },
  noteCard: {
    overflow: 'hidden',
  },
  noteLocked: {
    opacity: 0.65,
  },
  noteHeroWrap: {
    height: 96,
    position: 'relative',
  },
  noteHero: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: COLORS.panel3,
  },
  noteHeroShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(11, 28, 44, 0.55)',
  },
  noteHeroLabels: {
    position: 'absolute',
    left: 13,
    right: 13,
    bottom: 8,
    flexDirection: 'row',
    alignItems: 'flex-end',
  },
  noteHeroText: {
    flex: 1,
  },
  noteCity: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.text,
  },
  noteCode: {
    fontSize: 11,
    color: COLORS.muted,
    fontFamily: 'monospace',
    marginTop: 1,
  },
  noteChip: {
    paddingHorizontal: 7,
    paddingVertical: 3,
    borderRadius: 6,
  },
  noteChipVisited: {
    backgroundColor: 'rgba(60, 184, 164, 0.15)',
  },
  noteChipLocked: {
    backgroundColor: COLORS.panel3,
  },
  noteChipText: {
    fontSize: 10,
    fontWeight: '700',
  },
  noteChipTextVisited: {
    color: COLORS.teal,
  },
  noteChipTextLocked: {
    color: COLORS.muted2,
  },
  noteBody: {
    padding: 10,
    fontSize: 12,
    color: '#C6D3DF',
    lineHeight: 17,
  },
  warnBox: {
    marginHorizontal: 16,
    marginTop: 14,
    padding: 13,
    borderRadius: 14,
    backgroundColor: 'rgba(232, 154, 60, 0.1)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(232, 154, 60, 0.28)',
  },
  warnText: {
    fontSize: 12,
    lineHeight: 18,
    color: '#E3C08A',
  },
  sourcesCard: {
    marginHorizontal: 16,
    marginTop: 12,
  },
  sourceRow: {
    padding: 12,
  },
  sourceBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#16303F',
  },
  sourceHeader: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 8,
  },
  sourceName: {
    flex: 1,
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  licenseChip: {
    paddingHorizontal: 7,
    paddingVertical: 2,
    borderRadius: 6,
    backgroundColor: 'rgba(126, 182, 217, 0.14)',
  },
  licenseText: {
    fontSize: 11,
    fontWeight: '600',
    color: COLORS.blue,
  },
  sourceUse: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 3,
    lineHeight: 17,
  },
  settingsCard: {
    marginHorizontal: 16,
    marginTop: 16,
    padding: 14,
  },
  toggleBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#16303F',
  },
  settingsNote: {
    fontSize: 11,
    color: COLORS.muted2,
    marginTop: 10,
    lineHeight: 16,
  },
  logSummary: {
    marginHorizontal: 16,
    marginTop: 14,
    padding: 14,
    flexDirection: 'row',
  },
  logCell: {
    flex: 1,
  },
  logCellLabel: {
    fontSize: 11,
    color: COLORS.muted,
  },
  logCellVal: {
    fontSize: 19,
    fontWeight: '700',
    color: COLORS.text,
    marginTop: 2,
  },
  logDivider: {
    width: StyleSheet.hairlineWidth,
    backgroundColor: COLORS.border,
    marginHorizontal: 12,
  },
  logEmpty: {
    marginHorizontal: 16,
    marginTop: 14,
  },
  logRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    paddingVertical: 11,
    paddingHorizontal: 13,
    backgroundColor: COLORS.panel,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
  },
  logIcon: {
    width: 34,
    height: 34,
    borderRadius: 9,
    backgroundColor: COLORS.bg,
  },
  logBody: {
    flex: 1,
    minWidth: 0,
  },
  logTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
  },
  logSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  logAmount: {
    fontSize: 15,
    fontWeight: '700',
  },
  settingsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  settingsBody: {
    flex: 1,
  },
  settingsTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  settingsSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 1,
  },
  settingsActions: {
    marginTop: 12,
  },
  settingsBtn: {
    width: '100%',
  },
  version: {
    marginTop: 18,
    textAlign: 'center',
    fontSize: 12,
    color: COLORS.muted2,
  },
  menuCard: {
    marginHorizontal: 16,
    marginTop: 16,
  },
  menuRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 13,
  },
  menuBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#16303F',
  },
  menuRowPressed: {
    backgroundColor: '#1B3A51',
  },
  menuLabel: {
    flex: 1,
    fontSize: 16,
    color: COLORS.text,
    letterSpacing: -0.3,
  },
  menuValue: {
    fontSize: 14,
    color: COLORS.muted2,
  },
  menuChevron: {
    fontSize: 20,
    color: COLORS.muted2,
  },
  moreHint: {
    marginTop: 16,
    marginHorizontal: 16,
    fontSize: 11,
    lineHeight: 16,
    color: COLORS.muted2,
  },
  moreCity: {
    marginTop: 8,
    marginHorizontal: 16,
    fontSize: 12,
    color: COLORS.muted,
  },
  ffBody: {
    padding: 20,
    alignItems: 'center',
  },
  ffTitle: {
    fontSize: 17,
    fontWeight: '700',
    color: COLORS.text,
    letterSpacing: -0.3,
  },
  ffText: {
    fontSize: 13,
    color: '#C6D3DF',
    marginTop: 6,
    lineHeight: 18,
    textAlign: 'center',
  },
  ffActions: {
    flexDirection: 'row',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: COLORS.border2,
  },
  ffBtn: {
    flex: 1,
    padding: 14,
    alignItems: 'center',
  },
  ffDivider: {
    width: StyleSheet.hairlineWidth,
    backgroundColor: COLORS.border2,
  },
  ffCancel: {
    fontSize: 17,
    color: COLORS.blue,
  },
  ffConfirm: {
    fontSize: 17,
    fontWeight: '700',
    color: COLORS.orange,
  },
  sellHeroWrap: {
    height: 120,
    position: 'relative',
  },
  sellHero: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: COLORS.panel3,
  },
  sellHeroShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(19, 45, 64, 0.75)',
  },
  sellHeroLabels: {
    position: 'absolute',
    left: 18,
    bottom: 8,
  },
  sellPhase: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.6,
    color: COLORS.orange,
    textTransform: 'uppercase',
  },
  sellCity: {
    fontSize: 26,
    fontWeight: '700',
    color: COLORS.text,
    letterSpacing: -0.6,
  },
  sheetPad: {
    paddingHorizontal: 18,
    paddingBottom: 8,
    gap: 10,
  },
  sellHeadline: {
    fontSize: 13,
    color: COLORS.muted,
    lineHeight: 18,
  },
  sellRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    padding: 10,
    backgroundColor: COLORS.panel3,
    borderRadius: 14,
  },
  sellIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: COLORS.bg,
  },
  sellRowBody: {
    flex: 1,
    minWidth: 0,
  },
  sellRowName: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  sellRowMeta: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
  },
  sellRowPrice: {
    alignItems: 'flex-end',
  },
  sellDelta: {
    fontSize: 16,
    fontWeight: '700',
  },
  sellGross: {
    fontSize: 11,
    color: COLORS.muted2,
    marginTop: 1,
  },
  totalRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    marginTop: 4,
  },
  totalLabel: {
    flex: 1,
    fontSize: 15,
    color: COLORS.text,
  },
  totalVal: {
    fontSize: 24,
    fontWeight: '700',
  },
  sellAllBtn: {
    backgroundColor: COLORS.teal,
  },
  manageBagsBtn: {
    marginTop: 0,
  },
  warnBanner: {
    backgroundColor: 'rgba(224, 85, 85, 0.14)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(224, 85, 85, 0.35)',
  },
  warnBannerText: {
    fontSize: 13,
    color: COLORS.red,
    lineHeight: 18,
  },
  invSheetTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 4,
  },
  invSheetIcon: {
    width: 52,
    height: 52,
    borderRadius: 12,
    backgroundColor: COLORS.bg,
  },
  invSheetBody: {
    flex: 1,
    minWidth: 0,
  },
  invSheetName: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.text,
  },
  invSheetMeta: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 3,
  },
  invSheetPrice: {
    fontSize: 13,
    color: COLORS.muted,
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
    fontSize: 16,
    fontWeight: '700',
    color: COLORS.text,
  },
  qtyMaxHint: {
    fontSize: 12,
    color: COLORS.teal,
    textAlign: 'right',
  },
  cutscene: {
    flex: 1,
    backgroundColor: '#07161F',
  },
  cutArt: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.85,
  },
  cutShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(7, 22, 31, 0.55)',
  },
  cutContent: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 78,
    paddingHorizontal: 26,
    alignItems: 'center',
  },
  cutPhase: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 2,
    color: COLORS.orange,
    textTransform: 'uppercase',
  },
  cutTitle: {
    fontSize: 30,
    fontWeight: '700',
    color: COLORS.text,
    marginTop: 8,
    textAlign: 'center',
    letterSpacing: -0.7,
  },
  cutSub: {
    fontSize: 14,
    color: '#C6D3DF',
    marginTop: 6,
    textAlign: 'center',
  },
  cutTrack: {
    marginTop: 20,
    width: '100%',
    height: 4,
    borderRadius: 2,
    backgroundColor: 'rgba(217, 230, 240, 0.2)',
    overflow: 'hidden',
  },
  cutFill: {
    height: '100%',
    borderRadius: 2,
    backgroundColor: COLORS.orange,
  },
  cutHint: {
    fontSize: 11,
    color: COLORS.muted3,
    marginTop: 10,
  },
  intro: {
    flex: 1,
    backgroundColor: '#07161F',
  },
  introBg: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.5,
  },
  introShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(7, 22, 31, 0.82)',
  },
  introContent: {
    flex: 1,
    justifyContent: 'flex-end',
    paddingHorizontal: 26,
    paddingBottom: 30,
  },
  introLogo: {
    width: 76,
    height: 76,
    borderRadius: 18,
    backgroundColor: COLORS.panel3,
  },
  introTitle: {
    fontSize: 38,
    fontWeight: '700',
    color: COLORS.text,
    marginTop: 18,
    letterSpacing: -1,
  },
  introLead: {
    fontSize: 15,
    color: '#C6D3DF',
    marginTop: 8,
    lineHeight: 22,
  },
  introStep: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginTop: 11,
  },
  introStepIcon: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  introStepText: {
    flex: 1,
  },
  introStepTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
  },
  introStepSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 1,
  },
  introBtn: {
    marginTop: 26,
  },
  introFine: {
    marginTop: 12,
    fontSize: 11,
    color: COLORS.muted2,
    textAlign: 'center',
    lineHeight: 16,
  },
});
