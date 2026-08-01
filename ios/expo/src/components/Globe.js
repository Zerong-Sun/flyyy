import React, { useMemo, useRef } from 'react';
import {
  View,
  Text,
  Image,
  PanResponder,
  StyleSheet,
} from 'react-native';
import { CIDS, CITIES } from '../gameData';
import { assetSource } from '../assets';
import { COLORS } from '../theme';

const SIZE = 268;          // globe diameter
const IMG_W = SIZE * 2;    // equirectangular strip: full width = 360°
const R = Math.PI / 180;

/** Draggable world globe with a pin per hub — the app's home screen. */
export function Globe({ game }) {
  const { state, city, setRot, setDragging } = game;
  const rot = state.rot === null || state.rot === undefined ? -city.lon : state.rot;
  const rotRef = useRef(rot);
  rotRef.current = rot;

  const pan = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 3,
    onPanResponderGrant: () => setDragging(true),
    onPanResponderMove: (_e, g) => {
      setRot(rotRef.current + g.dx * 0.55 * (276 / SIZE));
    },
    onPanResponderRelease: () => setDragging(false),
    onPanResponderTerminate: () => setDragging(false),
  }), [setRot, setDragging]);

  // Wrap the strip so the world scrolls seamlessly in both directions.
  const raw = -((90 - rot) / 360) * IMG_W;
  const off = ((raw % IMG_W) + IMG_W) % IMG_W - IMG_W;

  const pins = CIDS.map((k) => {
    const c = CITIES[k];
    const rel = ((c.lon + rot + 540) % 360) - 180;
    const vis = Math.abs(rel) < 88;
    const edge = Math.cos(rel * R);
    const here = k === state.city;
    const seen = state.visited.includes(k);
    return {
      id: k,
      iata: c.iata,
      x: (50 + (rel / 90) * 50) / 100 * SIZE,
      y: (50 - (c.lat / 90) * 50) / 100 * SIZE,
      opacity: vis ? (here ? 1 : 0.4 + edge * 0.6) : 0,
      size: here ? 10 : 6,
      color: here ? COLORS.orange : seen ? COLORS.teal : COLORS.blue,
      label: vis && (here || (seen && edge > 0.5)),
      here,
    };
  });

  const hint = state.dragging
    ? `${city.name} · ${Math.round(((-rot % 360) + 360) % 360)}° E`
    : 'Drag to spin the world';

  return (
    <View style={styles.stage} pointerEvents="box-none">
      <View style={styles.glow} pointerEvents="none" />
      <View style={styles.circle} {...pan.panHandlers}>
        <Image
          source={assetSource('assets/earth.png')}
          style={[styles.strip, { left: off }]}
          resizeMode="stretch"
        />
        <Image
          source={assetSource('assets/earth.png')}
          style={[styles.strip, { left: off + IMG_W }]}
          resizeMode="stretch"
        />
        <View style={styles.shade} pointerEvents="none" />
      </View>

      <View style={styles.pinLayer} pointerEvents="none">
        {pins.map((p) => (
          <View key={p.id} style={[styles.pinWrap, { left: p.x, top: p.y, opacity: p.opacity }]}>
            <View
              style={[
                styles.pin,
                {
                  width: p.size,
                  height: p.size,
                  borderRadius: p.size / 2,
                  backgroundColor: p.color,
                  marginLeft: -p.size / 2,
                  marginTop: -p.size / 2,
                  shadowColor: p.here ? COLORS.orange : '#040E18',
                  shadowRadius: p.here ? 7 : 3,
                },
              ]}
            />
            {p.label ? (
              <Text style={[styles.pinLabel, p.here && styles.pinLabelHere]}>{p.iata}</Text>
            ) : null}
          </View>
        ))}
      </View>

      <Text style={styles.hint} pointerEvents="none">{hint}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  stage: {
    height: 318,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 2,
    overflow: 'hidden',
    zIndex: 0,
  },
  glow: {
    position: 'absolute',
    width: 320,
    height: 320,
    borderRadius: 160,
    backgroundColor: 'rgba(96, 168, 214, 0.09)',
  },
  circle: {
    width: SIZE,
    height: SIZE,
    borderRadius: SIZE / 2,
    overflow: 'hidden',
    backgroundColor: '#071722',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(217, 230, 240, 0.2)',
  },
  strip: {
    position: 'absolute',
    top: 0,
    width: IMG_W,
    height: SIZE,
  },
  shade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(4, 14, 24, 0.22)',
  },
  pinLayer: {
    position: 'absolute',
    width: SIZE,
    height: SIZE,
  },
  pinWrap: {
    position: 'absolute',
    alignItems: 'center',
  },
  pin: {
    shadowOpacity: 0.85,
    shadowOffset: { width: 0, height: 0 },
  },
  pinLabel: {
    marginTop: 3,
    fontSize: 9,
    fontWeight: '700',
    color: COLORS.muted,
    letterSpacing: 0.3,
  },
  pinLabelHere: {
    color: COLORS.orange,
  },
  hint: {
    position: 'absolute',
    bottom: 2,
    fontSize: 11,
    color: '#5E7488',
    letterSpacing: 0.2,
  },
});
