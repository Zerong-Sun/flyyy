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

let ready = false;
const cache = {};

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
