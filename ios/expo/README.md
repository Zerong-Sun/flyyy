# Airborne Trader — Expo Go (12-hub demo)

React Native port of the playable **12-hub** demo. Runs in **Expo Go SDK 54** on a phone over your local network.

Use this folder for the mobile flight trading game prototype.

## Start (LAN first)

```bash
cd "Mobile flight trading game/expo"
npm install
npx expo start
```

1. Install **Expo Go** on your iPhone or Android device.
2. Put your phone and computer on the **same Wi‑Fi**.
3. Scan the QR code shown in the terminal.

LAN is preferred — it is faster and more reliable than tunnel mode.

## If LAN fails

Corporate Wi‑Fi, guest networks, and VPNs often block device-to-device traffic. Try:

```bash
npx expo start --tunnel
```

If tunnel fails (e.g. ngrok errors):

- Disable VPN and retry LAN mode.
- Run `npx expo login` then restart.
- Use the iOS Simulator from a Mac: `npx expo start --ios`.
- As a last resort: `npx expo start --localhost` with USB debugging.

## Play loop

1. **Start in Istanbul** — intro screen, $6,944 cash, 23 kg carry-on.
2. **Market** — buy local or imported goods (mind weight limits).
3. **Flights** — book economy or business, add baggage if needed.
4. **Globe** — tap **Speed up** when a ticket is held.
5. **Cutscene** — takeoff → cruise → land (auto-advances).
6. **Sell sheet** — sell inventory at the destination, profit or loss.
7. Repeat across the twelve hubs.

One real second = six in-game minutes. A buy → fly → sell leg takes about a minute.

## What's in the build

Full port of the HTML prototype's game, minus the fake-phone chrome (device bezel,
lock-screen widget and push mockups) — the real OS provides those.

- **Globe** — drag to spin the world; a pin per hub, lit for where you are and where
  you've been. Airport search (IATA/ICAO/city/country), live local clock, carry-on and
  cargo load, route count, field elevation, and the boarding banner with Speed up.
- **Market** — local vs imported goods, price intel against your booked destination,
  buy sheet with quantity, carry-on/cargo choice and live weight check.
- **Flights** — departure board sorted by time, price, duration, new cities or business
  fare; booking sheet with cabin, baggage add-ons and the running total.
- **Bags** — load ring, per-lot manifest, sale review.
- **More** — Trader notes (unlock by landing), Achievements (12 goals on live stats),
  Trade log (every buy, booking, landing and sale), Data sources, Settings & save.
- **Settings** — haptics, boarding notifications, sound, 24-hour clock, reduce motion,
  save slot 1 and restart.
- **Persistence** — the run autosaves to device storage and comes back on relaunch.
- **Haptics** — real device feedback on every confirmation and warning.

## Adding cities, products and flights

All content is registered through three functions in [`src/gameData.js`](src/gameData.js):

```js
defineCity({
  id: 'doha', name: 'Doha', airport: 'Hamad International',
  iata: 'DOH', icao: 'OTHH', country: 'Qatar', cont: 'Asia',
  hero: 'assets/city_doha.webp', lat: 25.27, lon: 51.61, elev: 13, tz: 3,
  airline: ['QR', 'Qatar Airways'],
  note: 'Gulf transfer hub — re-export everything.',
  costIndex: 1.02,             // local price level, 1 = neutral
  demand: { Textiles: 1.2 },   // category appetite for imports
  products: [{ id: 'doh_pearl', name: 'Gulf Pearls', category: 'Crafts', w: 0.2, base: 2600 }],
  flights: [{ to: 'istanbul', dep: '01:30', no: 'QR 239', airline: 'Qatar Airways' }],
});

defineProduct({ id: 'doh_pearl', home: 'doha', volatility: 1.4, demandIn: { london: 1.25 } });
defineFlight({ from: 'doha', to: 'dubai', dep: '07:15', no: 'QR 1006', replace: true });
removeCity('doha');
```

Only the ids are required — everything else falls back: IATA from the id, icon
from the category, block time and fares from great-circle distance, airline from
the city name. Calling a define function again **merges** into the existing
record, which is how the seed tuning tables at the bottom of `gameData.js`
layer price levels, volatility and named services onto the base hubs.

A registered hub immediately appears on the globe, in the market, on every
departure board, in the trader notes and in the achievement counters.

Generated boards give two daily departures on hops under 4,200 km and one on
long-haul; `defineFlight` adds a named service on top, or `replace: true`
supersedes the generated leg for that city pair.

New art must also be added to [`src/assets.js`](src/assets.js) — Metro only
bundles literal `require()` paths. An unknown path falls back to the generic
product tile instead of crashing.

## Assets

Images load from the parent folder via Metro:

```text
Mobile flight trading game/assets/
```

No separate asset copy inside `expo/`.

## Data disclaimer

Flight routes are seeded from public aviation datasets (OurAirports, OpenFlights). Schedules, fares, and market prices are **simulated for play** — not real ticketing or financial data.
