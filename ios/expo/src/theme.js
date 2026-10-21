import { createContext } from 'react';
import { StyleSheet } from 'react-native';

// Midnight Port (dark) and Electric Bazaar (light) share the desktop palette.
const PALETTES = {
  dark: {
    bg: '#15131A', panel: '#211D25', panel2: '#302831', panel3: '#1A171E',
    border: '#5B4854', border2: '#725B68', text: '#FFF1DD', muted: '#DEC7BE',
    muted2: '#B7A29D', muted3: '#A99091', orange: '#FFAD78', teal: '#B8D27A',
    blue: '#A9C7DB', red: '#FF9A9A', gold: '#E2BD78',
  },
  light: {
    bg: '#F3FFD4', panel: '#FFFFF4', panel2: '#E7F2B8', panel3: '#F5FADD',
    border: '#BDCD7D', border2: '#AEBE70', text: '#1E214C', muted: '#4D4C6B',
    muted2: '#51516E', muted3: '#62627E', orange: '#5929BD', teal: '#9F2C54',
    blue: '#245A8C', red: '#A52843', gold: '#75500A',
  },
};
let activeMode = 'dark';
const darkToLight = Object.fromEntries(Object.keys(PALETTES.dark).map((key) => [PALETTES.dark[key].toLowerCase(), PALETTES.light[key]]));
const legacy = {
  '#0b1c2c': 'bg', '#122a3d': 'panel', '#152c3e': 'panel2', '#0f2536': 'panel3',
  '#24394b': 'border', '#2a455a': 'border2', '#f2f6fa': 'text', '#a8b8c8': 'muted',
  '#6c8298': 'muted2', '#7b90a4': 'muted3', '#e89a3c': 'orange', '#3cb8a4': 'teal',
  '#7eb6d9': 'blue', '#e05555': 'red', '#c9a45c': 'gold',
  '#1b3a51': 'panel2', '#071722': 'bg', '#07161f': 'bg', '#132d40': 'panel',
  '#16303f': 'border', '#3a566d': 'border2', '#c6d3df': 'muted', '#e3c08a': 'gold',
};
function colorFor(value) {
  if (typeof value !== 'string') return value;
  const key = value.toLowerCase();
  if (legacy[key]) return PALETTES[activeMode][legacy[key]];
  if (activeMode === 'light' && darkToLight[key]) return darkToLight[key];
  const rgba = key.match(/^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)$/);
  if (rgba) {
    const rgb = `#${[1, 2, 3].map((i) => Number(rgba[i]).toString(16).padStart(2, '0')).join('')}`;
    const role = legacy[rgb];
    if (role) {
      const hex = PALETTES[activeMode][role];
      const parts = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
      return `rgba(${parts.join(', ')}, ${rgba[4]})`;
    }
    if (activeMode === 'light' && rgb === '#ffffff') return `rgba(30, 33, 76, ${rgba[4]})`;
  }
  return value;
}

export function setThemeMode(mode) { activeMode = mode === 'light' ? 'light' : 'dark'; }
export function getThemeMode() { return activeMode; }
export const COLORS = new Proxy({}, {
  get(_target, key) { return PALETTES[activeMode][key]; },
  ownKeys() { return Reflect.ownKeys(PALETTES.dark); },
  getOwnPropertyDescriptor() { return { enumerable: true, configurable: true }; },
});

// React Native StyleSheet.create captures colour strings at module load. Resolve
// them when a style is read so a state update switches every screen together.
export function themedStyles(sheet) {
  return new Proxy(sheet, {
    get(target, key) {
      const raw = StyleSheet.flatten(target[key]);
      if (!raw) return raw;
      const mapped = {};
      for (const [prop, value] of Object.entries(raw)) {
        mapped[prop] = colorFor(value);
      }
      return mapped;
    },
  });
}

export const CB_PINS = {
  deuteranopia: { here: '#0072B2', ticketEnd: '#E69F00', seen: '#009E73', rest: '#999999' },
  protanopia: { here: '#0072B2', ticketEnd: '#E69F00', seen: '#009E73', rest: '#999999' },
};

export function pinPaletteFor(colorBlind) {
  if (colorBlind && CB_PINS[colorBlind]) return CB_PINS[colorBlind];
  return { here: COLORS.teal, ticketEnd: COLORS.orange, seen: COLORS.teal, rest: COLORS.blue };
}

export const A11yContext = createContext({ fontScale: 1, colorBlind: 'off' });
