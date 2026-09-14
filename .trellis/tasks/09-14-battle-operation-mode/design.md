# Design: Battle operation mode

## Boundaries

| Owner | Responsibility |
| --- | --- |
| `core/autoloads/SettingsManager.gd` | Generic local settings loading, defaulted reading, writing, and safe recovery from absent or unreadable configuration. |
| `scripts/battle_scripts/battle_settings_panel.gd` | Presentation-only settings popup: opens/closes the panel, displays the selected mode, and emits a mode choice. |
| `scripts/battle_scripts/click_mode_action_bar.gd` | Presentation-only confirm/cancel controls for an active click-mode card selection. |
| `scripts/card_scripts/card_manager.gd` | Owns the active input mode, selected card/monster target, highlighting, confirmation, cancellation, energy consumption, and the existing drag behavior. |
| `scenes/battle_scenes/battle.tscn` | Declares the settings and action-bar controls, their layout, and paths to the above components. |

## Settings contract

`SettingsManager` is an autoload registered from `project.godot`. It manages a single `ConfigFile` at `user://settings.cfg` and exposes generic methods shaped as:

- `get_setting(section, key, default_value)` — returns the stored value when present, otherwise returns the supplied default.
- `set_setting(section, key, value)` — updates the in-memory configuration and saves it immediately.

The manager loads once at startup. A missing file is normal. A load failure, including malformed content, logs a warning and starts from an empty configuration so every consumer receives its documented default. A save failure logs an error but leaves the current-session value usable.

`CardManager` owns the battle-specific section/key and validates values against exactly `click` and `drag`. Missing or invalid values become `click` and are persisted when the user next changes the setting. This keeps the persistence service reusable and prevents it from accumulating battle-specific rules.

## UI and input flow

```text
Settings button → BattleSettingsPanel → mode_selected(mode)
                                    ↓
                       CardManager.set_operation_mode(mode)
                                    ↓
                  SettingsManager.set_setting("battle", "operation_mode", mode)

Click-mode input:
click card → CardManager records selected card and shows action bar
click enemy slot → CardManager records/highlights target
click 确定 → consume energy → DeckManager.play_card(card, target or PlayerManager)
click 取消 / change mode / lose player input → clear selection and highlights
```

The action bar is placed immediately above the hand area. It remains hidden until a click-mode card has been selected. Its controls are `Control` nodes and card input must ignore GUI-pointer positions, preventing a settings or turn-control click from becoming an accidental self-cast.

## Targeting behavior

The existing collision-layer-2 card slot on each monster remains the only click-mode enemy target source. `CardManager` stores the monster parent of the hit slot. The selected target drives the existing multi-target highlighting rules. When no monster is selected, the predicted and confirmed target is `PlayerManager`, satisfying the specified self default. The confirmed target is passed to `DeckManager.play_card`; battle resolution remains responsible for each existing `SkillTargetingType`'s final effect expansion.

Drag mode keeps its current press-drag-release path. Changing modes clears all transient click/drag selection and target highlights so state cannot leak between modes.

## Compatibility and rollback

- No C# resources, generated enum bridge, combat effect, or target-resolution contract changes.
- `ConfigFile` uses `user://`, so no repository configuration or game resource is modified at runtime.
- Removing the autoload registration and the three new scene/script integrations restores the former drag-only input. Deleting `user://settings.cfg` restores the default click preference.
- The project-local environment explicitly does not support Godot Mono tests; validation will be limited to source/scene review and repository change inspection.
