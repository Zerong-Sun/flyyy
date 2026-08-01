import React from 'react';
import {
  Modal,
  Pressable,
  View,
  Text,
  Image,
  StyleSheet,
} from 'react-native';
import { assetSource } from '../assets';
import { COLORS } from '../theme';

export function Card({ children, style }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

function isTextChild(node) {
  return node == null
    || typeof node === 'string'
    || typeof node === 'number'
    || typeof node === 'boolean';
}

/** Wrap plain / interpolated labels so RN never sees raw strings under Pressable. */
function ButtonLabel({ children, style }) {
  if (isTextChild(children)) {
    return <Text style={style}>{children}</Text>;
  }
  if (Array.isArray(children) && children.every(isTextChild)) {
    return <Text style={style}>{children}</Text>;
  }
  return children;
}

export function Button({
  variant = 'primary',
  onPress,
  children,
  style,
  textStyle,
  disabled,
}) {
  const variantStyle = {
    primary: styles.btnPrimary,
    secondary: styles.btnSecondary,
    ghost: styles.btnGhost,
  }[variant] || styles.btnPrimary;

  const variantText = {
    primary: styles.btnPrimaryText,
    secondary: styles.btnSecondaryText,
    ghost: styles.btnGhostText,
  }[variant] || styles.btnPrimaryText;

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.btn,
        variantStyle,
        pressed && styles.btnPressed,
        disabled && styles.btnDisabled,
        style,
      ]}
    >
      <ButtonLabel style={[styles.btnText, variantText, textStyle]}>
        {children}
      </ButtonLabel>
    </Pressable>
  );
}

export function AssetIcon({ path, size = 24, tintColor, style }) {
  return (
    <Image
      source={assetSource(path)}
      style={[
        { width: size, height: size },
        tintColor ? { tintColor } : null,
        style,
      ]}
      resizeMode="contain"
    />
  );
}

export function ScreenTitle({ title, subtitle, style }) {
  return (
    <View style={[styles.titleWrap, style]}>
      <Text style={styles.title}>{title}</Text>
      {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
    </View>
  );
}

export function Sheet({ visible, onClose, children, center }) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={[styles.backdrop, center && styles.backdropCenter]}>
        <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />
        <View style={[center ? styles.sheetCenter : styles.sheetBody, styles.sheetForeground]}>
          {!center && <View style={styles.sheetHandle} />}
          {children}
        </View>
      </View>
    </Modal>
  );
}

export function SegControl({ options, value, onChange, style }) {
  return (
    <View style={[styles.segWrap, style]}>
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <Pressable
            key={opt.value}
            onPress={() => onChange(opt.value)}
            style={[styles.segItem, active && styles.segItemActive]}
          >
            <Text style={[styles.segText, active && styles.segTextActive]}>
              {opt.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Toggle({ label, sub, value, onToggle }) {
  return (
    <Pressable style={styles.toggleRow} onPress={onToggle}>
      <View style={styles.toggleBody}>
        <Text style={styles.toggleLabel}>{label}</Text>
        {sub ? <Text style={styles.toggleSub}>{sub}</Text> : null}
      </View>
      <View style={[styles.track, value && styles.trackOn]}>
        <View style={[styles.knob, value && styles.knobOn]} />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 12,
  },
  toggleBody: {
    flex: 1,
    minWidth: 0,
  },
  toggleLabel: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  toggleSub: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 2,
    lineHeight: 16,
  },
  track: {
    width: 46,
    height: 27,
    borderRadius: 14,
    backgroundColor: COLORS.border2,
    padding: 2,
    justifyContent: 'center',
  },
  trackOn: {
    backgroundColor: COLORS.teal,
  },
  knob: {
    width: 23,
    height: 23,
    borderRadius: 12,
    backgroundColor: '#F2F6FA',
  },
  knobOn: {
    alignSelf: 'flex-end',
  },
  card: {
    backgroundColor: COLORS.panel,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border,
    overflow: 'hidden',
  },
  btn: {
    borderRadius: 16,
    paddingVertical: 14,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnPrimary: {
    backgroundColor: COLORS.orange,
  },
  btnSecondary: {
    backgroundColor: COLORS.panel2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
  },
  btnGhost: {
    backgroundColor: 'transparent',
  },
  btnPressed: {
    opacity: 0.88,
    transform: [{ scale: 0.98 }],
  },
  btnDisabled: {
    opacity: 0.45,
  },
  btnText: {
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.2,
  },
  btnPrimaryText: {
    color: COLORS.bg,
  },
  btnSecondaryText: {
    color: COLORS.text,
  },
  btnGhostText: {
    color: COLORS.blue,
  },
  titleWrap: {
    paddingHorizontal: 16,
  },
  title: {
    fontSize: 32,
    fontWeight: '700',
    letterSpacing: -0.8,
    color: COLORS.text,
    lineHeight: 34,
  },
  subtitle: {
    fontSize: 13,
    color: COLORS.muted,
    marginTop: 3,
  },
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(4, 12, 20, 0.6)',
    justifyContent: 'flex-end',
  },
  backdropCenter: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  sheetBody: {
    backgroundColor: '#132D40',
    borderTopLeftRadius: 26,
    borderTopRightRadius: 26,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
    paddingBottom: 26,
    maxHeight: '92%',
  },
  sheetCenter: {
    backgroundColor: 'rgba(24, 46, 63, 0.98)',
    borderRadius: 22,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: COLORS.border2,
    marginHorizontal: 32,
    overflow: 'hidden',
    alignSelf: 'center',
    width: '100%',
    maxWidth: 340,
  },
  sheetHandle: {
    alignSelf: 'center',
    width: 38,
    height: 5,
    borderRadius: 3,
    backgroundColor: '#3A566D',
    marginTop: 8,
    marginBottom: 6,
  },
  sheetForeground: {
    zIndex: 2,
    elevation: 2,
  },
  segWrap: {
    flexDirection: 'row',
    backgroundColor: COLORS.panel2,
    borderRadius: 10,
    padding: 2,
  },
  segItem: {
    flex: 1,
    paddingVertical: 7,
    borderRadius: 8,
    alignItems: 'center',
  },
  segItemActive: {
    backgroundColor: COLORS.border2,
  },
  segText: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.muted,
    letterSpacing: -0.08,
  },
  segTextActive: {
    color: COLORS.text,
  },
});
