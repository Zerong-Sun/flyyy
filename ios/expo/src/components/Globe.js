import React, { useEffect, useMemo, useRef } from 'react';
import {
  View,
  Text,
  Image,
  PanResponder,
  Pressable,
  StyleSheet,
  useWindowDimensions,
} from 'react-native';
import { CIDS, CITIES } from '../gameData';
import { globeSizeFor } from '../gameLogic';
import { assetSource } from '../assets';
import { COLORS } from '../theme';

const R = Math.PI / 180;

function projectPin(lon, lat, rot, size) {
  const rel = ((lon + rot + 540) % 360) - 180;
  const vis = Math.abs(rel) < 88;
  const edge = Math.cos(rel * R);
  return {
    x: (50 + (rel / 90) * 50) / 100 * size,
    y: (50 - (lat / 90) * 50) / 100 * size,
    vis,
    edge,
    opacity: vis ? 0.4 + edge * 0.6 : 0,
  };
}

function sampleArc(x0, y0, x1, y1, n, size) {
  const mx = (x0 + x1) / 2;
  const my = (y0 + y1) / 2;
  const cx = size / 2;
  const cy = size / 2;
  const dx = mx - cx;
  const dy = my - cy;
  const len = Math.hypot(dx, dy) || 1;
  const bulge = Math.round(size * 0.12);
  const qx = mx + (dx / len) * bulge;
  const qy = my + (dy / len) * bulge;
  const pts = [];
  for (let i = 0; i <= n; i += 1) {
    const t = i / n;
    const u = 1 - t;
    pts.push({
      x: u * u * x0 + 2 * u * t * qx + t * t * x1,
      y: u * u * y0 + 2 * u * t * qy + t * t * y1,
    });
  }
  return pts;
}

/** Draggable world globe with pins, optional ticket arc, and inertia. */
export function Globe({ game }) {
  const { height } = useWindowDimensions();
  const SIZE = globeSizeFor(height);
  const IMG_W = SIZE * 2;
  const { state, city, setRot, setDragging, openPinCity, buzz, t, tf } = game;
  const rot = state.rot === null || state.rot === undefined ? -city.lon : state.rot;
  const rotRef = useRef(rot);
  rotRef.current = rot;
  const pinPressRef = useRef({ t: 0, x: 0, y: 0, id: null });
  const inertiaRef = useRef(null);
  const optReduceRef = useRef(state.optReduce);
  optReduceRef.current = state.optReduce;

  useEffect(() => () => {
    if (inertiaRef.current) cancelAnimationFrame(inertiaRef.current);
  }, []);

  const pan = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 3,
    onPanResponderGrant: () => {
      if (inertiaRef.current) cancelAnimationFrame(inertiaRef.current);
      setDragging(true);
    },
    onPanResponderMove: (_e, g) => {
      setRot(rotRef.current + g.dx * 0.55 * (276 / SIZE));
    },
    onPanResponderRelease: (_e, g) => {
      setDragging(false);
      if (optReduceRef.current) return;
      let vx = (g.vx || 0) * 22;
      if (Math.abs(vx) < 0.4) return;
      const step = () => {
        if (Math.abs(vx) < 0.12) return;
        setRot(rotRef.current + vx);
        vx *= 0.9;
        inertiaRef.current = requestAnimationFrame(step);
      };
      inertiaRef.current = requestAnimationFrame(step);
    },
    onPanResponderTerminate: () => setDragging(false),
  }), [setRot, setDragging, SIZE]);

  const raw = -((90 - rot) / 360) * IMG_W;
  const off = ((raw % IMG_W) + IMG_W) % IMG_W - IMG_W;

  const pins = CIDS.map((k) => {
    const c = CITIES[k];
    const p = projectPin(c.lon, c.lat, rot, SIZE);
    const here = k === state.city;
    const seen = state.visited.includes(k);
    const ticketEnd = state.ticket && (k === state.city || k === state.ticket.toId);
    return {
      id: k,
      iata: c.iata,
      name: c.name,
      x: p.x,
      y: p.y,
      opacity: p.vis ? (here || ticketEnd ? 1 : 0.4 + p.edge * 0.6) : 0,
      size: here || ticketEnd ? 10 : 6,
      color: here ? COLORS.teal : ticketEnd ? COLORS.orange : seen ? COLORS.teal : COLORS.blue,
      label: p.vis && (here || ticketEnd || (seen && p.edge > 0.5)),
      here,
      vis: p.vis,
    };
  });

  const arcPts = (() => {
    const t = state.ticket;
    if (!t || !CITIES[t.toId]) return [];
    const a = projectPin(CITIES[state.city].lon, CITIES[state.city].lat, rot, SIZE);
    const b = projectPin(CITIES[t.toId].lon, CITIES[t.toId].lat, rot, SIZE);
    if (!a.vis && !b.vis) return [];
    return sampleArc(a.x, a.y, b.x, b.y, 28, SIZE).filter((pt) => {
      const dx = pt.x - SIZE / 2;
      const dy = pt.y - SIZE / 2;
      return dx * dx + dy * dy <= (SIZE / 2 - 2) ** 2;
    });
  })();

  const hint = state.dragging
    ? tf('globe.drag_hint_dragging', { name: city.name, deg: Math.round(((-rot % 360) + 360) % 360) }, `${city.name} · ${Math.round(((-rot % 360) + 360) % 360)}° E`)
    : t('globe.drag_hint', 'Drag to spin · tap a pin for details');

  const onPinPressIn = (p, e) => {
    pinPressRef.current = {
      t: Date.now(),
      x: e.nativeEvent.pageX,
      y: e.nativeEvent.pageY,
      id: p.id,
    };
  };

  const onPinPressOut = (p, e) => {
    const start = pinPressRef.current;
    if (start.id !== p.id) return;
    const dt = Date.now() - start.t;
    const dx = Math.abs(e.nativeEvent.pageX - start.x);
    const dy = Math.abs(e.nativeEvent.pageY - start.y);
    if (dt >= 220 || dx > 12 || dy > 12) return;
    if (p.here) {
      buzz(t('globe.you_are_here', 'You are here'), 'ok');
      return;
    }
    openPinCity(p.id);
  };

  return (
    <View style={[styles.stage, { height: SIZE + 34 }]} pointerEvents="box-none">
      <View
        style={[styles.glow, { width: SIZE + 52, height: SIZE + 52, borderRadius: (SIZE + 52) / 2 }]}
        pointerEvents="none"
      />
      <View
        style={[styles.circle, { width: SIZE, height: SIZE, borderRadius: SIZE / 2 }]}
        {...pan.panHandlers}
      >
        <Image
          source={assetSource('assets/earth.webp')}
          style={[styles.strip, { left: off, width: IMG_W, height: SIZE }]}
          resizeMode="stretch"
          accessible={false}
        />
        <Image
          source={assetSource('assets/earth.webp')}
          style={[styles.strip, { left: off + IMG_W, width: IMG_W, height: SIZE }]}
          resizeMode="stretch"
          accessible={false}
        />
        <View style={styles.shade} pointerEvents="none" />
        {arcPts.map((pt, i) => (
          <View
            key={`arc-${i}`}
            pointerEvents="none"
            style={[styles.arcDot, { left: pt.x - 1.5, top: pt.y - 1.5, opacity: 0.35 + (i / arcPts.length) * 0.55 }]}
          />
        ))}
      </View>

      <View style={[styles.pinLayer, { width: SIZE, height: SIZE }]} pointerEvents="box-none">
        {pins.map((p) => (
          p.vis && p.opacity > 0.05 ? (
            <Pressable
              key={p.id}
              style={[styles.pinWrap, { left: p.x, top: p.y, opacity: p.opacity }]}
              onPressIn={(e) => onPinPressIn(p, e)}
              onPressOut={(e) => onPinPressOut(p, e)}
              hitSlop={10}
              accessibilityRole="button"
              accessibilityLabel={p.here ? tf('globe.pin_a11y_here', { name: p.name }, `${p.name}, you are here`) : tf('globe.pin_a11y', { name: p.name }, `${p.name} details`)}
            >
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
                    shadowColor: p.here ? COLORS.teal : '#040E18',
                    shadowRadius: p.here ? 7 : 3,
                  },
                ]}
                accessible={false}
              />
              {p.label ? (
                <Text style={[styles.pinLabel, p.here && styles.pinLabelHere]} accessible={false}>
                  {p.iata}
                </Text>
              ) : null}
            </Pressable>
          ) : (
            <View key={p.id} style={[styles.pinWrap, { left: p.x, top: p.y, opacity: 0 }]} pointerEvents="none" />
          )
        ))}
      </View>

      <Text style={styles.hint} pointerEvents="none">{hint}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  stage: {
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    zIndex: 0,
  },
  glow: {
    position: 'absolute',
    borderRadius: 160,
    backgroundColor: 'rgba(96, 168, 214, 0.09)',
  },
  circle: {
    overflow: 'hidden',
    backgroundColor: '#071722',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(217, 230, 240, 0.2)',
  },
  strip: {
    position: 'absolute',
    top: 0,
  },
  shade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(4, 14, 24, 0.22)',
  },
  arcDot: {
    position: 'absolute',
    width: 3,
    height: 3,
    borderRadius: 1.5,
    backgroundColor: COLORS.orange,
  },
  pinLayer: {
    position: 'absolute',
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
    letterSpacing: 0.4,
  },
  pinLabelHere: {
    color: COLORS.teal,
  },
  hint: {
    marginTop: 10,
    fontSize: 12,
    color: COLORS.muted2,
  },
});
