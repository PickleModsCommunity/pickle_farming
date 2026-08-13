# TEBBY.md - pickle_farming

## Overview

`pickle_farming` is a FiveM resource that implements a multi-framework farming activity. Players plant seeds (including vegetables and illicit crops) in designated field zones, water them using a `garden_pitcher`, and harvest them with a `garden_shovel` once fully grown. Harvested raw produce is then processed at a processing station and sold for money at a selling NPC. Plant growth state is synced server-wide via `GlobalState.Plants`. Supported frameworks: ESX, QBCore, and a Standalone stub (currently empty).

## Code design

### Architecture

The resource follows a strict client/server/shared split expressed through the FiveM `fxmanifest.lua` script glob patterns:

- **Shared scripts** – `config.lua`, `core/shared.lua`, `locales/`, `bridge/**/shared.lua`, `modules/**/shared.lua` load on both sides.
- **Client scripts** – `bridge/**/client.lua`, `modules/**/client.lua`, `core/client.lua`.
- **Server scripts** – `bridge/**/server.lua`, `modules/**/server.lua`, `core/server.lua`.

### Main flows

1. **Planting** – Using a seed item triggers `RegisterUsableItem` (server, `modules/plants/server.lua`), which fires `pickle_farming:plantSeed` to the player's client. The client calls `CreatePlant` → `IsPlantable` (material or zone check) → server callback `pickle_farming:createPlant`. On success the server removes the seed, waits `PlantTime` seconds, then writes the plant into `Plants` and syncs via `GlobalState.Plants`.

2. **Watering** – The client poll loop detects proximity (`< 1.5 units`). When the plant is `< 100%` grown, pressing `INPUT_CONTEXT` calls `InteractPlant` → server callback `pickle_farming:waterPlant`. The server checks for `garden_pitcher` in inventory, waits `WaterTime`, then increments `plant.water` clamped to `WaterNeeded`, and calls `UpdatePlants()` to push `GlobalState.Plants`.

3. **Harvesting** – When `water >= WaterNeeded` (100%), pressing the interact key calls server callback `pickle_farming:harvestPlant`. The server checks for `garden_shovel`, waits `HarvestTime`, gives random `Rewards` items, removes the plant from `Plants`, calls `UpdatePlants()`, and fires `pickle_farming:removePlant` to all clients.

4. **Plant rendering** – A client thread polls all `GlobalState.Plants` every tick, spawning local prop objects (`CreateLocalPlant`) within `RenderDistance` and deleting them when out of range. Growth progress is smoothly lerped using `lerp()` and the prop's `Offsets.Start`/`Offsets.End` vectors.

5. **Exchange (Process/Sell)** – A separate client thread handles exchange locations. "Process" type consumes N raw items and yields 1 processed item (with optional ox_lib skill check). "Exchange" type converts all matching inventory items to money at a random rate. Both types are configurable in `Config.Exchange[]`.

### Anti-double-action guard

Both client and server maintain an `Interact` flag. Client: a single `local Interact = false` that blocks re-entry. Server: `Interact[source]` keyed by player source ID. These are intentional concurrency guards, not bugs.

### Conventions

- Framework functions (`ShowNotification`, `Search`, `AddItem`, `RemoveItem`, `CanCarryItem`, `RegisterCallback`, `RegisterUsableItem`, `ServerCallback`, `ShowHelpNotification`) are abstracted entirely in bridge files. Core logic never calls ESX/QBCore directly.
- `GlobalState.Plants` is the single source of truth for all plant data; `UpdatePlants()` must be called after every mutation.
- `_L(key)` is the locale lookup helper defined in `locales/locale.lua`; a missing key returns `ERR_TRANSLATE_<key>_404`.
- `dprint(...)` is a debug-only print gated by `Config.Debug`.
- `v3(vec4)` splits a `vector4` into `vector3 + w` (heading). Used extensively for location configs.

## Important files

| Path | Purpose |
|------|---------|
| `fxmanifest.lua` | FiveM resource manifest; declares all script globs and `lua54 'yes'`. |
| `config.lua` | All operator-editable settings: plant timers, seeds, exchange locations, blips, `MaxPlayerPlants`, `RenderDistance`. |
| `core/shared.lua` | Shared utilities: `lerp()`, `v3()`, `dprint()`. |
| `core/client.lua` | Shared client helpers: `CreateNPC`, `CreateProp`, `PlayAnim`, `PlayEffect`, `CreateBlip`; also renders `Config.Blips` on startup. |
| `core/server.lua` | Empty — no shared server-side globals beyond what bridges provide. |
| `modules/plants/client.lua` | All plant client logic: local prop lifecycle, grow lerp loop, watering/harvesting interactions, proximity poll thread. |
| `modules/plants/server.lua` | All plant server logic: `Plants` table, `GlobalState` sync, callbacks for createPlant/waterPlant/harvestPlant, usable item registration. |
| `modules/exchange/client.lua` | NPC exchange client: proximity loop, NPC spawn/despawn, skill check integration, interaction handler. |
| `modules/exchange/server.lua` | Exchange server: `GetExchangeItems`, `ExchangeItems`, `exchangeProcess` callback. |
| `modules/materials/shared.lua` | Full GTA V material hash lookup table (named strings → hex hashes). Includes three custom `Farm`/`Farm2`/`Farm3` entries used for planting zone validation. |
| `locales/locale.lua` | `_L()` helper and `Language` table loader. |
| `locales/translations/en.lua` | English strings (reference locale). |
| `bridge/esx/client.lua` | ESX client bridge: `ShowNotification`, `ShowHelpNotification`, `ServerCallback`. Guards with resource-state check. |
| `bridge/esx/server.lua` | ESX server bridge: `RegisterCallback`, `Search`, `AddItem`, `RemoveItem`, `CanCarryItem`, `RegisterUsableItem`. |
| `bridge/qb/client.lua` | QBCore client bridge (same API surface as ESX bridge). |
| `bridge/qb/server.lua` | QBCore server bridge. Note: `CanCarryItem` always returns `true` (no QBCore equivalent). |
| `bridge/standalone/client.lua` | Empty stub — operators must implement the bridge API for custom frameworks. |
| `bridge/standalone/server.lua` | Empty stub — same. |
| `__INSTALLATION/Items/ox_inventory.lua` | ox_inventory item definitions for all seeds, raws, processed items, and tools. |
| `__INSTALLATION/Items/esx_limit.sql` | ESX (weight-limit variant) SQL item inserts. |
| `__INSTALLATION/Items/esx_weight.sql` | ESX (weight variant) SQL item inserts. |
| `__INSTALLATION/Items/qbcore.lua` | QBCore shared items definitions. |
| `__INSTALLATION/Images/` | Inventory icon PNGs for all crop stages and tools. |

## Intended behaviors

- **`Interact` flag on both sides** – The client `local Interact = false` and server `Interact[source]` table are deliberate anti-spam guards. A callback returning `false` (plant not found, bad state) resets the flag. If a callback is never called (network drop), `Interact` may remain `true` permanently — this is a known design limitation, not a bug to be fixed by removing the guard.

- **`CanCarryItem` always `true` in QBCore bridge** – `bridge/qb/server.lua` returns `true` unconditionally because QBCore has no direct carry-capacity API. This is documented in the code with a comment. Do not treat it as a missing implementation to fill in without understanding the QBCore inventory in use.

- **`core/server.lua` is empty** – The file exists (and is listed in the manifest) but contains no code. This is intentional; all server logic lives in the module and bridge files.

- **`bridge/standalone/` files are empty** – These are operator-fill stubs. They will always be empty in the upstream repo.

- **Hardcoded `GlobalState` key `Plants`** – `GlobalState.Plants` is set directly on the server and read by all clients. This is by design; do not rename it without updating both sides.

- **`Farm`, `Farm2`, `Farm3` material hashes** – Three custom numeric hashes at the bottom of `modules/materials/shared.lua` (`Farm = -1833527165`, `Farm2 = -700658213`, `Farm3 = 1109728704`). These are non-standard entries added specifically for farming map mods. They are not GTA engine materials and will not appear in other material references — this is intentional.

- **Heroin `WaterNeeded = 10`** – `heroin_seed` in `config.lua` has `WaterNeeded = 10` while all other seeds use `100`. This appears to be a deliberate design choice (faster illicit crop growth) rather than a typo, but it is the most likely value an operator would want to change.

- **Plant key collision loop** – In `modules/plants/server.lua`, if `os.time()` produces a key that already exists, the code appends `"_1"` in a `while` loop with `Wait(0)`. Repeated collisions result in keys like `1710000000_1_1_1`. This is intentional defensive coding, not a bug.

- **ox_lib optional** – `@ox_lib/init.lua` is listed first in `shared_scripts` with a comment saying to remove it if not using ox_lib. The skill check in the exchange module is gated by `Config.ExchangeSettings.EnableSkillCheck`. Removing the `@ox_lib/init.lua` line without setting `EnableSkillCheck = false` will cause a runtime error when processing.

## Common issues & fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Locale strings show as `ERR_TRANSLATE_<key>_404` | `Config.Language` value doesn't match a key in `locales/translations/`. | Ensure `Config.Language = "en"` (or your locale) and the matching file exists with `Language["en"] = { ... }`. |
| Seeds can't be used / no interaction | Item not registered in inventory or resource name mismatch. | Confirm the resource folder is named exactly `pickle_farming`. Run the correct SQL/Lua from `__INSTALLATION/Items/`. |
| Can't plant anywhere | `Config.Seeds[seed].Materials` and `Config.Seeds[seed].Zones` both fail to match the current location. | Verify the player is standing on a `Farm`/`Farm2`/`Farm3` material surface OR within the configured `Zones` radius. Increase zone radius or add more zones in `config.lua`. |
| `Interact` stuck as `true` on client | A server callback never fired back (network issue or script error on server). | Diagnose the server-side error first. The flag resets on the next successful interaction or resource restart. |
| "You need to have a gardening pitcher/shovel" | Player does not have `garden_pitcher` or `garden_shovel` in inventory. | Add items via `/giveitem` or ensure supply is available on the server. |
| ox_lib skill check errors | `@ox_lib/init.lua` line removed but `EnableSkillCheck` still `true`. | Set `Config.ExchangeSettings.EnableSkillCheck = false` in `config.lua`, or restore the ox_lib shared script line. |
| Plants disappear after server restart | `Plants` table lives in memory; there is no database persistence. | This is by design — all plants are lost on restart. To add persistence, operators must implement DB save/load around `UpdatePlants()`. |
| QBCore players can carry unlimited harvested items | `CanCarryItem` always returns `true` in the QBCore bridge. | Implement a weight/slot check inside `bridge/qb/server.lua:CanCarryItem` using your specific inventory resource's API. |
| Exchange NPC doesn't spawn | `Config.Exchange[i].NPCModel` is nil (e.g., the "Process" entry has no NPC). | Only "Exchange" type entries need an `NPCModel`. "Process" entries work as a world-location interact point without an NPC — this is intended. |
| Max plant count not enforced correctly | `CanPlayerPlant` has a Lua string interpolation bug in the error message (`("..playerPlants.."`). | The logic still works (the `elseif` evaluates correctly); only the notification text is malformed. The fix is to correct the string in `modules/plants/server.lua:CanPlayerPlant`. |

## Conventions

- **Lua 5.4** – `lua54 'yes'` is set in the manifest. Use `<const>`, `<close>`, integer division `//`, and bitwise operators freely, but maintain consistency with the existing style.
- **No semicolons** – All existing code uses newlines as statement terminators.
- **`local` at module scope** – Module-level state uses `local` (e.g., `local Interact = false`, `local LocalPlants = {}`). Server-side shared state is global (e.g., `Plants = {}`, `Interact = {}`).
- **Config-driven** – All tunable values (timers, distances, seed definitions, exchange locations, blips) live in `config.lua`. Core logic reads from `Config.*` at runtime; do not hardcode values in module files.
- **Bridge API surface** – Any new framework function must be added to all three bridge pairs (esx, qb, standalone) with the same signature. Do not add direct ESX/QBCore calls outside the bridge folder.
- **`_L()` for all player-facing strings** – Never use raw string literals in `ShowNotification` or `ShowHelpNotification`. Add keys to all locale files in `locales/translations/`.
- **`dprint()` for debug output** – Use `dprint()` (not `print()`) for any diagnostic output so it is gated by `Config.Debug`.
- **Callback naming** – Server callbacks follow the pattern `pickle_farming:<action>` (e.g., `pickle_farming:createPlant`). Net events follow the same namespace.
- **`UpdatePlants()` after every mutation** – Any server-side change to the `Plants` table must be followed immediately by `UpdatePlants()` to sync `GlobalState`.
- **File structure** – New game features go in `modules/<feature>/client.lua` and `modules/<feature>/server.lua`. Shared data (lookup tables, constants) go in `modules/<feature>/shared.lua`. The manifest globs pick these up automatically.
