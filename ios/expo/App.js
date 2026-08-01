import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  ScrollView,
  Pressable,
  StyleSheet,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { useGame } from './src/hooks/useGame';
import { TABS } from './src/gameData';
import { COLORS } from './src/theme';
import { AssetIcon } from './src/components/ui';
import { GlobeScreen } from './src/components/GlobeScreen';
import { MarketScreen, FlightsScreen, MarketSheets } from './src/components/MarketFlights';
import { BagsScreen, MoreScreen, OverlaySheets } from './src/components/BagsMore';

function TabContent({ game }) {
  const { state } = game;

  switch (state.tab) {
    case 'market':
      return <MarketScreen game={game} />;
    case 'flights':
      return <FlightsScreen game={game} />;
    case 'bags':
      return <BagsScreen game={game} />;
    case 'more':
      return <MoreScreen game={game} />;
    case 'globe':
    default:
      return <GlobeScreen game={game} />;
  }
}

function GameApp() {
  const game = useGame();
  const { state, city, clockText, money, setTab, loaded } = game;
  const scrollRef = useRef(null);
  const prevTab = useRef(state.tab);

  useEffect(() => {
    if (prevTab.current !== state.tab) {
      prevTab.current = state.tab;
      scrollRef.current?.scrollTo({ y: 0, animated: false });
    }
  }, [state.tab]);

  if (!loaded) {
    return (
      <SafeAreaView style={styles.root}>
        <StatusBar barStyle="light-content" />
        <View style={styles.loading}>
          <ActivityIndicator color={COLORS.orange} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.root} edges={['top', 'left', 'right']}>
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <View style={styles.brandRow}>
          <AssetIcon path="assets/logo_mark.webp" size={22} />
          <Text style={styles.brand}>Airborne Trader</Text>
        </View>
        <View style={styles.headerMeta}>
          <Text style={styles.cityLabel}>{city.iata}</Text>
          <Text style={styles.clock}>{clockText}</Text>
          <View style={styles.cashRow}>
            <View style={styles.cashDot} />
            <Text style={styles.cash}>{money(state.cash)}</Text>
          </View>
        </View>
      </View>

      <ScrollView
        ref={scrollRef}
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        nestedScrollEnabled
      >
        <TabContent game={game} />
      </ScrollView>

      {state.toast ? (
        <View style={styles.toast}>
          <View
            style={[
              styles.toastDot,
              { backgroundColor: state.toastKind === 'bad' ? COLORS.red : COLORS.teal },
            ]}
          />
          <Text style={styles.toastText}>{state.toast}</Text>
        </View>
      ) : null}

      <SafeAreaView edges={['bottom']} style={styles.tabBarSafe}>
        <View style={styles.tabBar}>
          {TABS.map((tab) => {
            const active = state.tab === tab.k;
            return (
              <Pressable
                key={tab.k}
                onPress={() => setTab(tab.k)}
                accessibilityRole="tab"
                accessibilityState={{ selected: active }}
                accessibilityLabel={tab.label}
                style={({ pressed }) => [styles.tabItem, pressed && styles.tabPressed]}
              >
                <AssetIcon
                  path={tab.icon}
                  size={25}
                  tintColor={active ? COLORS.orange : COLORS.muted2}
                />
                <Text style={[styles.tabLabel, active && styles.tabLabelActive]}>
                  {tab.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
      </SafeAreaView>

      <MarketSheets game={game} />
      <OverlaySheets game={game} />
    </SafeAreaView>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <GameApp />
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: COLORS.bg,
  },
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: COLORS.border,
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 6,
  },
  brand: {
    fontSize: 14,
    fontWeight: '700',
    color: COLORS.text,
    letterSpacing: -0.2,
  },
  headerMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  cityLabel: {
    fontFamily: 'monospace',
    fontSize: 13,
    fontWeight: '700',
    color: COLORS.teal,
  },
  clock: {
    flex: 1,
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.text,
  },
  cashRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  cashDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: COLORS.teal,
  },
  cash: {
    fontSize: 13,
    fontWeight: '700',
    color: COLORS.text,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 96,
  },
  toast: {
    position: 'absolute',
    left: 20,
    right: 20,
    bottom: 112,
    zIndex: 40,
    elevation: 40,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 14,
    backgroundColor: 'rgba(18, 42, 61, 0.96)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
  },
  toastDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  toastText: {
    flex: 1,
    fontSize: 14,
    color: COLORS.text,
    lineHeight: 18,
  },
  tabBarSafe: {
    backgroundColor: 'rgba(11, 28, 44, 0.96)',
  },
  tabBar: {
    flexDirection: 'row',
    paddingTop: 8,
    paddingBottom: 8,
    paddingHorizontal: 4,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: COLORS.border,
    backgroundColor: 'rgba(11, 28, 44, 0.96)',
  },
  tabItem: {
    flex: 1,
    alignItems: 'center',
    gap: 3,
    paddingVertical: 3,
  },
  tabPressed: {
    opacity: 0.5,
  },
  tabLabel: {
    fontSize: 10,
    fontWeight: '600',
    color: COLORS.muted2,
    letterSpacing: -0.04,
  },
  tabLabelActive: {
    color: COLORS.orange,
  },
});
