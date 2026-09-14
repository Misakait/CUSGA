# Implementation plan: Battle operation mode

## Ordered checklist

1. Add `SettingsManager.gd` as a generic `ConfigFile`-backed autoload in `project.godot`, with documented default/failure behavior and Chinese maintenance comments.
2. Add small battle UI components for the mode popup and click-mode action bar. They emit UI intent only and do not contain card or combat rules.
3. Add the settings button/popup at the battle scene's upper-right and the hidden confirm/cancel action bar immediately above the hand area.
4. Extend `CardManager` with persisted mode access, click-mode selection state, monster-target picking/highlighting, explicit confirm/cancel handling, and clearing on mode/state transitions.
5. Preserve the present drag-input branch and refactor only the shared raycast/highlight helpers necessary to support both modes.
6. Update/create the project gameplay-mechanics document with the two operation modes, default target rule, UI confirmation rule, persistence location, and no gameplay-numeric changes.
7. Inspect every changed script and scene for node paths, signal connections, default values, Chinese comments, and unintended diff scope; do not run Godot Mono or automated tests because the local project override prohibits them.
8. Run the Trellis quality-review workflow with the same environment limitation, append the required learning feedback and commit description to `临时反馈文档.md`, then prepare the requested commit (without committing unless asked).

## Risk controls

| Risk | Control |
| --- | --- |
| GUI click accidentally self-casts | Ignore click-mode world input while a `Control` is under the pointer; action buttons use their own signals. |
| Stale selection after a turn, mode change, or cancellation | Centralize cleanup in one `clear_click_selection` path that hides the action bar and removes target highlights. |
| Invalid or corrupted preferences | Validate battle values in `CardManager`; use `ConfigFile` fallback defaults in `SettingsManager`. |
| Regression in drag play | Keep the existing drag branch and use shared helpers without changing its release decision. |
| Scene-path mismatch | Use exported `NodePath` fields for component-to-manager bindings and verify paths in the edited `.tscn`. |

## Rollback points

- After steps 1–3, revert only the autoload and scene/UI components if the settings UI cannot bind safely.
- After steps 4–5, revert the `CardManager` branch while retaining the generic settings service if a targeting regression is found.
- Before handoff, remove all new pieces together to return to the current drag-only behavior.
