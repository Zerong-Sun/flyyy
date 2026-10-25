import React, { useState } from 'react';
import { View, Text, Pressable, ScrollView } from 'react-native';
import { CITIES, PRODUCTS } from '../gameData';
import { abilityLabel, merchantText, MERCHANT_RULES } from '../merchantLogic';
import { COLORS, themedStyles } from '../theme';

export function MerchantBoard({ game }) {
  const [open, setOpen] = useState(false);
  const { state: s } = game;
  const m = s.merchant;
  if (!m) return null;
  const tr = (zh, en) => merchantText(s, zh, en);
  const order = m.order;
  const summary = order
    ? `${game.t(`city.${order.city}`, CITIES[order.city].name)} · ${order.done}/${order.qty} · ${Math.max(0, (order.deadline - s.gameMin) / 60).toFixed(1)}h`
    : m.notice || tr('24–72h 限时商机', '24–72h timed opportunities');
  const label = (o) => `${game.t(`city.${o.city}`, CITIES[o.city].name)} · ${game.t(`prod.${o.product}`, PRODUCTS[o.product].name)} ×${o.qty - o.done} · ${Math.max(0, (o.deadline - s.gameMin) / 60).toFixed(1)}h · +$${Math.round(o.bonus - o.advance)}${o.stage > 1 ? ` · ${o.stage}/3` : ''}`;
  const action = (title, onPress) => <Pressable accessibilityRole="button" onPress={onPress} style={styles.button}><Text style={styles.action}>{title}</Text></Pressable>;
  const sales = Object.entries(m.sales).map(([key, value]) => {
    const threshold = key.startsWith('product:') ? MERCHANT_RULES.mobile_product_milestone : MERCHANT_RULES.mobile_category_milestone;
    return { key, value, target: (Math.floor(value / threshold) + 1) * threshold };
  }).sort((a, b) => b.value / b.target - a.value / a.target);
  const near = sales[0];
  return <View style={styles.board}>
    <Pressable accessibilityRole="button" accessibilityState={{ expanded: open }} onPress={() => setOpen(!open)} style={styles.header}>
      <Text style={styles.summary} numberOfLines={1}>{open ? '▾' : '▸'} {summary}{m.candidates.length ? tr(' · 新专长', ' · New specialty') : ''}</Text>
    </Pressable>
    {open && <ScrollView style={styles.details} nestedScrollEnabled>
      {order ? <View style={styles.row}><Text style={styles.copy}>{label(order)}</Text>{action(tr('去交货', 'Deliver'), () => { if (order.city === s.city) game.openSell(); else game.setFocusDest(order.city); })}{action(tr('结束', 'End'), game.abandonMerchantOrder)}</View>
        : m.offers.filter((o) => o.deadline > s.gameMin).map((o) => <View key={o.id} style={styles.row}><Text style={styles.copy}>{label(o)}</Text>{action(tr('接单', 'Accept'), () => game.acceptMerchantOrder(o.id))}</View>)}
      {!order && !m.offers.some((o) => o.deadline > s.gameMin) && <Text style={styles.copy}>{tr('下次抵达或次日查看新商机', 'Check after arrival or next day')}</Text>}
      <Text style={styles.copy}>{tr('当前：', 'Active: ')}{abilityLabel(s, m.active)}</Text>
      {m.candidates.map((a) => <View key={a.id} style={styles.row}><Text style={styles.copy}>{abilityLabel(s, a)}</Text>{action(tr(m.active ? '替换' : '启用', m.active ? 'Replace' : 'Equip'), () => game.equipMerchantAbility(a.id))}{action('×', () => game.dismissMerchantAbility(a.id))}</View>)}
      {near && <Text style={styles.progress}>{near.key.startsWith('product:') ? game.t(`prod.${near.key.slice(8)}`, PRODUCTS[near.key.slice(8)]?.name || '') : near.key.slice(9)} · ${Math.round(near.value)} / ${near.target}</Text>}
      <Text style={styles.progress}>{tr('飞行专长', 'Flight specialty')} · {m.flights} / {(Math.floor(m.flights / MERCHANT_RULES.flight_milestone) + 1) * MERCHANT_RULES.flight_milestone}</Text>
    </ScrollView>}
  </View>;
}
const styles = themedStyles({
  board: { marginVertical: 8, borderWidth: 1, borderColor: COLORS.border, borderRadius: 10, padding: 8 },
  header: { minHeight: 40, justifyContent: 'center' },
  summary: { color: COLORS.teal, fontSize: 13, fontWeight: '600' },
  details: { maxHeight: 220 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingVertical: 4 },
  copy: { flex: 1, color: COLORS.text, fontSize: 12, lineHeight: 19 },
  button: { minHeight: 44, minWidth: 44, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 7 },
  action: { color: COLORS.teal, fontSize: 12, fontWeight: '600' },
  progress: { color: COLORS.muted, fontSize: 11, marginTop: 6 },
});
