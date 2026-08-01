repo: Zerong-Sun/flyyy
branch: main

## Last sync

date: 2026-08-01T00:00:00Z

### Updated in this project

- Shipped `expo/` — a React Native (Expo Go SDK 54) build of the 12-hub demo that runs on a real phone.
- Added a documented content API (`defineCity` / `defineProduct` / `defineFlight` / `removeCity`) shared by the HTML prototype and the app.
- Demand-aware pricing: per-city `costIndex` and category `demand`, per-product `volatility` and `demandIn`.
- Departure boards now run twice-daily short hops plus named services that can replace a generated leg.

## Screen map

| Project screen | Repo files |
| --- | --- |
| Palette & type (all screens) | `game/themes/DemoColors.gd`, `game/themes/ThemeFactory.gd` |
| Globe home, city card | `game/scenes/globe/globe.tscn`, `game/scripts/ui/MainHUD.gd`, `game/assets/art/city_*_hero_720.webp` |
| Market, buy sheet | `game/scripts/ui/MainHUD.gd`, `etl/content/products/*.yaml`, `game/assets/art/product_*_64.webp` |
| Flights, ticket sheet | `game/scripts/ui/MainHUD.gd`, `etl/config/hubs_20.yaml` |
| Baggage | `game/scripts/ui/MainHUD.gd` |
| Flight cutscene | `game/assets/anim/flight_transition/`, `game/assets/art/anim_flight_*.webp` |
| Tab bar & inline icons | `game/assets/icons/icon_*_32.webp` |
| Lock-screen widget, push banner | new — no repo counterpart |
| Expo app (`expo/`) | port of `Airborne Trader iOS.dc.html`; data contract shared with `etl/config/hubs_20.yaml` |
