# Steam 云存档策略

> 适用平台：Steam（PC）。移动端（iOS/AppStore）存档为本地键值存储，不在本文档范围。
> 相关文件：`game/scripts/autoload/SaveSystem.gd`、`game/data/steam_achievements.json`。

## 目标

1. 云存档在**任意机器**上恢复玩家进度（资金、库存、统计、图鉴、声望）。
2. 存档与 Steam **本地文件**策略（`file.write` / `file.read`）一致，避免云同步冲突。
3. 挑战模式与收藏家模式的存档按模式隔离，云端也遵循同样隔离规则。

## 存档文件与云端映射

| 模式 | 本地路径（user://） | 是否入云 | 说明 |
| --- | --- | --- | --- |
| 沙盒 | `save_demo.json` | 是 | 旧档兼容，保持文件名不变 |
| 挑战 | `save_challenge.json` | 是 | 30 日挑战单独存档 |
| 收藏家 | `save_collector.json` | 是 | 收藏进度单独存档 |
| 设置类 | 不落盘（运行时内存） | 否 | 如 `reduced_animations` 等 |

云端始终以 `SaveSystem.save_game()` 产出的 JSON 为单一事实源。**不做云端去重/合并**：Steam 云为按文件同步，冲突时采用"较新时间戳覆盖"策略。

## 实现约定（当前状态）

`SaveSystem` 已实现：

- `_path_for(mode)` → 按 `AppState.game_mode` 返回不同文件名。
- `save_game()` / `load_game()` 读写对应文件；`has_save(mode)` 判断是否存在。
- 每次 `save_game()` 会写入 `saved_unix`（`Time.get_unix_time_from_system()`），作为云端冲突裁决的时间戳字段。

PC 端接入 Steam 云：把 `user://` 重定向到 Steam 云目录（`SteamRemoteStorage`）即可，路径规则不变。切换磁盘/机器后首次启动自动拉取本地文件。

## 成就与云存档的关系

- 成就数据**不进入**云存档 JSON，统一由 Steamworks `SteamUserStats` 管理。
- 本仓库维护 `game/data/steam_achievements.json`，把游戏内成就 id（`ach_*`）映射到 Steam API name（去掉 `ach_` 前缀、大写、非字母数字转 `_`）。
- 游戏内解锁成就后，通过映射表调用 `SteamUserStats.SetAchievement(steam_name)`；启动时反向同步 `SteamUserStats` 已解锁项到 `AppState.unlocked_achievements`，保证两端一致。

## 多端覆盖核对（移动端）

`ios/expo/src/saveGame.js` 的 `PERSIST` 数组必须与 `SaveSystem.to_dict()` 键对齐，新增字段（如 `rep`、`level`）需同时加入。当前已对齐：
`rep`、`level`（声望系统）以及既有 `cash/inv/visited/legs/…`。

## 上线前 checklist

- [ ] Steam 后台创建全部成就（36 个）并填入与 `steam_achievements.json` 一致的 API name。
- [ ] 云存档勾选"允许使用 Steam 云"，路径不包含机器相关信息。
- [ ] 挑战模式 `save_challenge.json` 与沙盒互不影响（已按 mode 隔离）。
- [ ] 移动端 `PERSIST` 与 `to_dict()` 键保持一致（新增字段时同步更新）。
