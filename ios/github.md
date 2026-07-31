repo: Zerong-Sun/flyyy
branch: main

## Last sync

date: 2026-07-31T05:20:51Z

### Updated in this project

- Built an iOS phone port of the Godot demo: globe home, 5-tab bar, buy/book/fly/sell loop.
- Ported the game's colour tokens, icon set, city hero art and product art.
- Modelled 6 hub cities with per-city markets, flight boards and price intel.
- Added three static design variants (globe-first, swipe-to-buy, boarding-pass style).

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
