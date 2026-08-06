import { createContext } from 'react';

export const COLORS = {
  bg: '#0B1C2C',
  panel: '#122A3D',
  panel2: '#152C3E',
  panel3: '#0F2536',
  border: '#24394B',
  border2: '#2A455A',
  text: '#F2F6FA',
  muted: '#A8B8C8',
  muted2: '#6C8298',
  muted3: '#7B90A4',
  orange: '#E89A3C',
  teal: '#3CB8A4',
  blue: '#7EB6D9',
  red: '#E05555',
  gold: '#C9A45C',
};

/**
 * Colour-blind-safe palette (Okabe-Ito) for pin states when
 * `state.colorBlind` is 'deuteranopia' / 'protanopia'.
 * Order mirrors Globe pin logic: here / ticketEnd / seen / default.
 */
export const CB_PINS = {
  deuteranopia: {
    here: '#0072B2', // vivid blue
    ticketEnd: '#E69F00', // orange
    seen: '#009E73', // bluish green
    rest: '#999999', // grey
  },
  protanopia: {
    here: '#0072B2',
    ticketEnd: '#E69F00',
    seen: '#009E73',
    rest: '#999999',
  },
};

/** Resolve the active pin colour map for a save state (falls back to COLORS). */
export function pinPaletteFor(colorBlind) {
  if (colorBlind && CB_PINS[colorBlind]) return CB_PINS[colorBlind];
  return {
    here: COLORS.teal,
    ticketEnd: COLORS.orange,
    seen: COLORS.teal,
    rest: COLORS.blue,
  };
}

/** Accessibility preferences shared across screens via React context. */
export const A11yContext = createContext({ fontScale: 1, colorBlind: 'off' });

