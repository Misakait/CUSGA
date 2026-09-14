# Implementation plan: Battle card impact feedback

## Ordered checklist

1. [x] Extend `Action` with a documented optional presentation-card reference while retaining all existing constructor call compatibility.
2. [x] Update `PlayerHand` so card removal can skip immediate discard animation, and make its discard presentation awaitable for action-queue sequencing.
3. [x] Update `DeckManager` to detach a played card from the hand before queueing its action, retain its presentation node, and expose one guarded completion method that appends the card data to the discard pile then plays the fade.
4. [x] Add `CardManager` exported selected-card lift parameters; animate the selected card upward and restore its hand position on every non-confirmation clear path.
5. [x] Extend `BattleManager` to play the retained card toward an explicit live monster target, execute the existing effect, invoke the reusable target hit animation, and finalize discard before advancing the queue.
6. [x] Update the gameplay document and relevant Trellis code-spec with the presentation sequencing and optional action-node contract.
7. [x] Statically inspect all changed GDScript, scene paths, action construction sites, discard paths, and docs. Do not run Godot Mono, compilation, or automated tests because the project-local override prohibits them.
8. [ ] Run the Trellis quality-review workflow with that validation limitation, append learning feedback and commit description to `临时反馈文档.md`, commit the focused changes, archive the task, and record the session.

## Risk controls

| Risk | Control |
| --- | --- |
| Card node disappears before flight | Remove it from hand layout without calling discard animation; only finalize after BattleManager presentation/effect flow. |
| Duplicate discard data or `queue_free` | Route all played-card disposal through one `DeckManager` completion method. |
| Existing monster/attack actions break | Keep the new Action reference optional and never require it outside player `CARD` actions. |
| Selection lift persists after cancellation | Centralize reset through `clear_click_selection(restore_hand_layout)` and restore all non-confirmation paths. |
| Invalid target causes animation error | Only play enemy flight/hit when the action target is still an active monster and its node is valid. |
| Magic animation timing spreads | Use CardManager exports for selection feedback and existing `CardAnimations` constants for flight/hit/discard. |
