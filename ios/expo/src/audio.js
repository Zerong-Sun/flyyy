/**
 * Optional SFX via expo-av. AAC (.m4a) for iOS/Android Metro + AVPlayer.
 * Falls back silently — useGame still plays haptic clicks.
 */
import { Audio } from 'expo-av';

const SOURCES = {
  sfx_ticket: require('../assets/audio/sfx/sfx_ticket.m4a'),
  sfx_gate: require('../assets/audio/sfx/sfx_gate.m4a'),
  sfx_profit: require('../assets/audio/sfx/sfx_profit.m4a'),
  sfx_loss: require('../assets/audio/sfx/sfx_loss.m4a'),
  sfx_ach: require('../assets/audio/sfx/sfx_ach.m4a'),
};

// Looping BGM scenes (AAC from game/assets/audio/bgm/*.ogg via ffmpeg).
const BGM_SOURCES = {
  bgm_globe_day: require('../assets/audio/bgm/bgm_globe_day.m4a'),
  bgm_market: require('../assets/audio/bgm/bgm_market.m4a'),
  bgm_menu: require('../assets/audio/bgm/bgm_menu.m4a'),
  bgm_night: require('../assets/audio/bgm/bgm_night.m4a'),
};

let ready = false;
const cache = {};
let bgmPlayer = null;
let currentBgm = null;
let bgmGeneration = 0;

async function ensureMode() {
  if (ready) return;
  try {
    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: false,
      shouldDuckAndroid: true,
    });
  } catch (_) {
    /* ignore */
  }
  ready = true;
}

export async function playSfx(id) {
  const src = SOURCES[id];
  if (!src) return false;
  try {
    await ensureMode();
    let sound = cache[id];
    if (!sound) {
      const created = await Audio.Sound.createAsync(src, { shouldPlay: false, volume: 0.85 });
      sound = created.sound;
      cache[id] = sound;
    }
    await sound.setPositionAsync(0);
    await sound.playAsync();
    return true;
  } catch (_) {
    return false;
  }
}

/** Play a looping BGM scene, stopping the previous track. No-op if already playing. */
export async function playBgm(id) {
  const src = BGM_SOURCES[id];
  if (!src) return false;
  if (currentBgm === id && bgmPlayer) return true;
  const generation = ++bgmGeneration;
  const previous = bgmPlayer;
  bgmPlayer = null;
  currentBgm = null;
  try {
    await ensureMode();
    if (previous) await previous.unloadAsync().catch(() => {});
    if (generation !== bgmGeneration) return false;
    const { sound } = await Audio.Sound.createAsync(src, { shouldPlay: false, volume: 0.5, isLooping: true });
    if (generation !== bgmGeneration) { await sound.unloadAsync().catch(() => {}); return false; }
    bgmPlayer = sound;
    currentBgm = id;
    await sound.playAsync();
    return true;
  } catch (_) { return false; }
}

export async function stopBgm() {
  ++bgmGeneration;
  const previous = bgmPlayer;
  bgmPlayer = null;
  currentBgm = null;
  if (previous) await previous.unloadAsync().catch(() => {});
}
