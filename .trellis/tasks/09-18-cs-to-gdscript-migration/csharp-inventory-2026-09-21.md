# 剩余 C# 逐文件判定表（2026-09-21）

> 用途：为 C# 物理退役提供「删什么、为什么能删」的逐文件依据。本文档只做分类与取证，**不执行删除**。
>
> **权威口径**：机器校验的权威是 `tests/godot/test_final_migration_audit_contract.gd` 里的 `NO_TWIN_CS_CLASSIFICATION` + `KIND_ROW_COUNTS`（协议 12 / 内联 17 / 逻辑 9 / 对照 1，共 39）。本文档是该表的可读镜像（A 段由「全部 `.cs` 减去该表 39 行」机械导出），**改动任一处必须同步另一处**。

## 摘要

| 分类 | 数量 | 含义 | 退役处置 |
| --- | --- | --- | --- |
| A 同目录蛇形孪生 | 163 | 同目录已有同名蛇形 GDScript 生产实现 | C# 为迁移期垫片，随最终清理一并删除 |
| B 协议 / 接口垫片 | 12 | C# 侧协议接口；等价物是被读取的 GDScript 生产对象 | 与 A 同批删除（GDScript 不依赖其类型身份） |
| C 已内联 | 17 | 旧 C# 类的能力已内联进 `world_interaction_coordinator.gd` | 与 A 同批删除 |
| D 非 Resource 逻辑类 | 9 | 逻辑已由 GDScript 生产脚本或契约测试覆盖 | 与 A 同批删除（逐条见下表） |
| E C# 对照测试工程 | 1 | `tests/CUSGA.Tests/Program.cs` | 独立工程，是否保留为对照测试需开发者决定 |
| 合计 | 202 | 不含 `**/obj/**`、`**/bin/**` 生成文件 | — |

## 退役就绪证据（2026-09-21 复核）

| 证据 | 结果 |
| --- | --- |
| 资产引用 | `.tres` / `.res` / `.tscn` 指向 `.cs` 的 `ext_resource` / `script` **0 命中** |
| 生产 GDScript 路径引用 | `core/` / `scripts/` / `entities/` / `resources/` / `scenes/` 下 `.cs` 路径 **0 命中**（仅注释提及） |
| Autoload 运行时实测（run 86） | 10 个 Autoload 的脚本路径逐一取回，**全部是 GDScript**：`GlobalEventBus.gd` / `ItemsControl.gd` / `warehouse_inventory_component.gd` / `SceneManager.gd` / `ScreenTransitions.gd` / `SettingsManager.gd` / `weather_manager.gd` / `player_progression.gd` / `player_wallet.gd` / `time_system.gd` |
| 类型位置扫描 | 全仓生产 GDScript 对 72 个 C# 全局类名做「类型位置」正则扫描：唯一原始命中为 `boss_interaction.gd:32` 的 `"monster": Monster`，经核实是**值引用**（声明为 `@export var Monster: Resource`）→ 实际 **0 命中** |
| 全局类注册 | C# 全局类 72 个、GDScript 全局类 88 个，**同名冲突 0**（缓存口径），GDScript 侧从未以 C# 类型名声明 `class_name` |
| 测试侧 | 已改为 `ResourceLoader.exists()` 探测式可选，C# 缺席时相关套件整体 `skip`（批次 J） |
| 运行现状 | C# 程序集当前无法编译（`CS0246 Resource` @ `BoardCardState.cs`、`CS0246 EncounterManager` @ `WorldInteractionCoordinator.cs` / `TerrainInteractionExecutor.cs`），但主菜单 / 主场景 / 战斗场景全部实跑通过 —— C# 早已不是运行时实现路径 |

## A 同目录蛇形孪生（163）

| C# 文件 | GDScript 生产实现 |
| --- | --- |
| `core/application/EncounterManager.cs` | `res://core/application/encounter_manager.gd` |
| `core/application/GameplayPort.cs` | `res://core/application/gameplay_port.gd` |
| `core/attributes/AttributeChangeContext.cs` | `res://core/attributes/attribute_change_context.gd` |
| `core/attributes/AttributeChangedEvent.cs` | `res://core/attributes/attribute_changed_event.gd` |
| `core/attributes/AttributeChangeDirection.cs` | `res://core/attributes/attribute_change_direction.gd` |
| `core/attributes/AttributeChangeReason.cs` | `res://core/attributes/attribute_change_reason.gd` |
| `core/attributes/AttributeModifier.cs` | `res://core/attributes/attribute_modifier.gd` |
| `core/attributes/AttributeRecalculateRequest.cs` | `res://core/attributes/attribute_recalculate_request.gd` |
| `core/attributes/AttributeRecalculateScope.cs` | `res://core/attributes/attribute_recalculate_scope.gd` |
| `core/attributes/Attributes.cs` | `res://core/attributes/attributes.gd` |
| `core/attributes/IReadOnlyAttribute.cs` | `res://core/attributes/i_read_only_attribute.gd` |
| `core/autoloads/PlayerWallet.cs` | `res://core/autoloads/player_wallet.gd` |
| `core/autoloads/TimeSystem.cs` | `res://core/autoloads/time_system.gd` |
| `core/autoloads/WeatherManager.cs` | `res://core/autoloads/weather_manager.gd` |
| `core/board/BoardCardState.cs` | `res://core/board/board_card_state.gd` |
| `core/board/BoardCardView.cs` | `res://core/board/board_card_view.gd` |
| `core/board/BoardController.cs` | `res://core/board/board_controller.gd` |
| `core/combat/buffs/AttributeModifierStatusData.cs` | `res://core/combat/buffs/attribute_modifier_status_data.gd` |
| `core/combat/buffs/AttributeModifierStatusInstance.cs` | `res://core/combat/buffs/attribute_modifier_status_instance.gd` |
| `core/combat/buffs/BossDamageCapStatusData.cs` | `res://core/combat/buffs/boss_damage_cap_status_data.gd` |
| `core/combat/buffs/BossDamageCapStatusInstance.cs` | `res://core/combat/buffs/boss_damage_cap_status_instance.gd` |
| `core/combat/buffs/BurnStatusData.cs` | `res://core/combat/buffs/burn_status_data.gd` |
| `core/combat/buffs/BurnStatusInstance.cs` | `res://core/combat/buffs/burn_status_instance.gd` |
| `core/combat/buffs/HitCountModifierStatusData.cs` | `res://core/combat/buffs/hit_count_modifier_status_data.gd` |
| `core/combat/buffs/HitCountModifierStatusInstance.cs` | `res://core/combat/buffs/hit_count_modifier_status_instance.gd` |
| `core/combat/buffs/NextAttackDamageBonusStatusData.cs` | `res://core/combat/buffs/next_attack_damage_bonus_status_data.gd` |
| `core/combat/buffs/NextAttackDamageBonusStatusInstance.cs` | `res://core/combat/buffs/next_attack_damage_bonus_status_instance.gd` |
| `core/combat/buffs/ShieldStatusData.cs` | `res://core/combat/buffs/shield_status_data.gd` |
| `core/combat/buffs/ShieldStatusInstance.cs` | `res://core/combat/buffs/shield_status_instance.gd` |
| `core/combat/buffs/VulnerableStatusData.cs` | `res://core/combat/buffs/vulnerable_status_data.gd` |
| `core/combat/buffs/VulnerableStatusInstance.cs` | `res://core/combat/buffs/vulnerable_status_instance.gd` |
| `core/combat/DamageFormula.cs` | `res://core/combat/damage_formula.gd` |
| `core/combat/DamagePayload.cs` | `res://core/combat/damage_payload.gd` |
| `core/combat/DamageResolutionResult.cs` | `res://core/combat/damage_resolution_result.gd` |
| `core/combat/effects/ApplyShieldCardEffect.cs` | `res://core/combat/effects/apply_shield_card_effect.gd` |
| `core/combat/effects/ApplyStatusCardEffect.cs` | `res://core/combat/effects/apply_status_card_effect.gd` |
| `core/combat/effects/CardEffect.cs` | `res://core/combat/effects/card_effect.gd` |
| `core/combat/effects/DamageEffect.cs` | `res://core/combat/effects/damage_effect.gd` |
| `core/combat/effects/DamageEffectHitCountContext.cs` | `res://core/combat/effects/damage_effect_hit_count_context.gd` |
| `core/combat/effects/DamageEffectSegmentContext.cs` | `res://core/combat/effects/damage_effect_segment_context.gd` |
| `core/combat/effects/DamageHitTargetMode.cs` | `res://core/combat/effects/damage_hit_target_mode.gd` |
| `core/combat/effects/ModifyAttributeEffect.cs` | `res://core/combat/effects/modify_attribute_effect.gd` |
| `core/combat/effects/SkillEffectTargetScope.cs` | `res://core/combat/effects/skill_effect_target_scope.gd` |
| `core/combat/effects/SkillEffectTargetScopeUtility.cs` | `res://core/combat/effects/skill_effect_target_scope_utility.gd` |
| `core/combat/effects/SkillEffectTargetSelection.cs` | `res://core/combat/effects/skill_effect_target_selection.gd` |
| `core/combat/ElementalSystem.cs` | `res://core/combat/elemental_system.gd` |
| `core/combat/skills/CombatSkillData.cs` | `res://core/combat/skills/combat_skill_data.gd` |
| `core/combat/skills/SkillExecutionContext.cs` | `res://core/combat/skills/skill_execution_context.gd` |
| `core/combat/skills/SkillExecutionModifierContext.cs` | `res://core/combat/skills/skill_execution_modifier_context.gd` |
| `core/combat/skills/SkillTarget.cs` | `res://core/combat/skills/skill_target.gd` |
| `core/combat/skills/SkillTargetRole.cs` | `res://core/combat/skills/skill_target_role.gd` |
| `core/combat/status/AttributeChangeGuardStatusData.cs` | `res://core/combat/status/attribute_change_guard_status_data.gd` |
| `core/combat/status/AttributeChangeGuardStatusInstance.cs` | `res://core/combat/status/attribute_change_guard_status_instance.gd` |
| `core/combat/status/AttributeChangeTriggerStatusData.cs` | `res://core/combat/status/attribute_change_trigger_status_data.gd` |
| `core/combat/status/AttributeChangeTriggerStatusInstance.cs` | `res://core/combat/status/attribute_change_trigger_status_instance.gd` |
| `core/combat/status/AttributeModifierData.cs` | `res://core/combat/status/attribute_modifier_data.gd` |
| `core/combat/status/DurationExpirePolicy.cs` | `res://core/combat/status/duration_expire_policy.gd` |
| `core/combat/status/DurationTickTiming.cs` | `res://core/combat/status/duration_tick_timing.gd` |
| `core/combat/status/StackPolicy.cs` | `res://core/combat/status/stack_policy.gd` |
| `core/combat/status/StatusChangeContext.cs` | `res://core/combat/status/status_change_context.gd` |
| `core/combat/status/StatusChangedEvent.cs` | `res://core/combat/status/status_changed_event.gd` |
| `core/combat/status/StatusChangeReason.cs` | `res://core/combat/status/status_change_reason.gd` |
| `core/combat/status/StatusEffectData.cs` | `res://core/combat/status/status_effect_data.gd` |
| `core/combat/status/StatusEffectInstance.cs` | `res://core/combat/status/status_effect_instance.gd` |
| `core/combat/status/StatusHookPhase.cs` | `res://core/combat/status/status_hook_phase.gd` |
| `core/constants/CombatConstants.cs` | `res://core/constants/combat_constants.gd` |
| `core/constants/ElementType.cs` | `res://core/constants/element_type.gd` |
| `core/constants/EquipmentTypes.cs` | `res://core/constants/equipment_types.gd` |
| `core/constants/GDSignals.cs` | `res://core/constants/gd_signals.gd` |
| `core/constants/TagConsts.cs` | `res://core/constants/tag_consts.gd` |
| `core/constants/TimeCosts.cs` | `res://core/constants/time_costs.gd` |
| `core/constants/WorldInteractionTiming.cs` | `res://core/constants/world_interaction_timing.gd` |
| `core/crafting/CraftingFailureReason.cs` | `res://core/crafting/crafting_failure_reason.gd` |
| `core/crafting/CraftingService.cs` | `res://core/crafting/crafting_service.gd` |
| `core/debug/DebugLoadoutSeeder.cs` | `res://core/debug/debug_loadout_seeder.gd` |
| `core/gameflow/CurrentMapBackgroundResolver.cs` | `res://core/gameflow/current_map_background_resolver.gd` |
| `core/gameflow/WorldHoldInteractionController.cs` | `res://core/gameflow/world_hold_interaction_controller.gd` |
| `core/gameflow/WorldInteractionCoordinator.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `core/map/PassageGuardMonsterResolver.cs` | `res://core/map/passage_guard_monster_resolver.gd` |
| `core/map/PassageGuardProbabilityProvider.cs` | `res://core/map/passage_guard_probability_provider.gd` |
| `core/map/PassageGuardState.cs` | `res://core/map/passage_guard_state.gd` |
| `core/map/RoomBoardPresenter.cs` | `res://core/map/room_board_presenter.gd` |
| `core/map/RoomTerrainLayoutGenerator.cs` | `res://core/map/room_terrain_layout_generator.gd` |
| `core/map/RoomTerrainPoolEntry.cs` | `res://core/map/room_terrain_pool_entry.gd` |
| `core/map/RoomTerrainProfile.cs` | `res://core/map/room_terrain_profile.gd` |
| `core/map/RoomTerrainStore.cs` | `res://core/map/room_terrain_store.gd` |
| `core/progression/PlayerProgression.cs` | `res://core/progression/player_progression.gd` |
| `core/progression/UpgradeKind.cs` | `res://core/progression/upgrade_kind.gd` |
| `core/shop/ShopFailureReason.cs` | `res://core/shop/shop_failure_reason.gd` |
| `core/shop/ShopService.cs` | `res://core/shop/shop_service.gd` |
| `core/shop/ShopTradeBridge.cs` | `res://core/shop/shop_trade_bridge.gd` |
| `core/ui/AttributeSummaryUI.cs` | `res://core/ui/attribute_summary_ui.gd` |
| `core/ui/crafting/CraftingUI.cs` | `res://core/ui/crafting/crafting_ui.gd` |
| `core/ui/draggable/DraggableData.cs` | `res://core/ui/draggable/draggable_data.gd` |
| `core/ui/EquipmentSlotUI.cs` | `res://core/ui/equipment_slot_ui.gd` |
| `core/ui/hud/BackpackButton.cs` | `res://core/ui/hud/backpack_button.gd` |
| `core/ui/hud/HealthBarUI.cs` | `res://core/ui/hud/health_bar_ui.gd` |
| `core/ui/hud/HUDController.cs` | `res://core/ui/hud/hud_controller.gd` |
| `core/ui/hud/TimePanelUI.cs` | `res://core/ui/hud/time_panel_ui.gd` |
| `core/ui/hud/WorldHoldProgressIndicator.cs` | `res://core/ui/hud/world_hold_progress_indicator.gd` |
| `core/ui/InventoryUI.cs` | `res://core/ui/inventory_ui.gd` |
| `core/ui/ItemTooltipPresenter.cs` | `res://core/ui/item_tooltip_presenter.gd` |
| `core/ui/SlotUI.cs` | `res://core/ui/slot_ui.gd` |
| `core/ui/warehouse/WarehouseUI.cs` | `res://core/ui/warehouse/warehouse_ui.gd` |
| `entities/components/AttributeComponent.cs` | `res://entities/components/attribute_component.gd` |
| `entities/components/BattleDeckComponent.cs` | `res://entities/components/battle_deck_component.gd` |
| `entities/components/CraftingComponent.cs` | `res://entities/components/crafting_component.gd` |
| `entities/components/DamageReceiverComponent.cs` | `res://entities/components/damage_receiver_component.gd` |
| `entities/components/EnergyComponent.cs` | `res://entities/components/energy_component.gd` |
| `entities/components/EquipmentComponent.cs` | `res://entities/components/equipment_component.gd` |
| `entities/components/FactionComponent.cs` | `res://entities/components/faction_component.gd` |
| `entities/components/HealthComponent.cs` | `res://entities/components/health_component.gd` |
| `entities/components/InventoryComponent.cs` | `res://entities/components/inventory_component.gd` |
| `entities/components/LootComponent.cs` | `res://entities/components/loot_component.gd` |
| `entities/components/MonsterSkillComponent.cs` | `res://entities/components/monster_skill_component.gd` |
| `entities/components/SatietyComponent.cs` | `res://entities/components/satiety_component.gd` |
| `entities/components/StatusComponent.cs` | `res://entities/components/status_component.gd` |
| `entities/components/TagComponent.cs` | `res://entities/components/tag_component.gd` |
| `entities/components/VitalComponentBase.cs` | `res://entities/components/vital_component_base.gd` |
| `entities/components/WarehouseInventoryComponent.cs` | `res://entities/components/warehouse_inventory_component.gd` |
| `entities/Monster.cs` | `res://entities/monster.gd` |
| `entities/Player.cs` | `res://entities/player.gd` |
| `resources/debug/DebugGeneratedEquipmentEntry.cs` | `res://resources/debug/debug_generated_equipment_entry.gd` |
| `resources/debug/DebugItemStackEntry.cs` | `res://resources/debug/debug_item_stack_entry.gd` |
| `resources/debug/DebugLoadoutData.cs` | `res://resources/debug/debug_loadout_data.gd` |
| `resources/encounters/GatheringEncounterResult.cs` | `res://resources/encounters/gathering_encounter_result.gd` |
| `resources/encounters/GatheringEncounterRule.cs` | `res://resources/encounters/gathering_encounter_rule.gd` |
| `resources/encounters/MonsterStatMultiplierRange.cs` | `res://resources/encounters/monster_stat_multiplier_range.gd` |
| `resources/interaction/BossInteraction.cs` | `res://resources/interaction/boss_interaction.gd` |
| `resources/interaction/FarmingInteraction.cs` | `res://resources/interaction/farming_interaction.gd` |
| `resources/interaction/GatheringInteraction.cs` | `res://resources/interaction/gathering_interaction.gd` |
| `resources/interaction/ReusableGatheringInteraction.cs` | `res://resources/interaction/reusable_gathering_interaction.gd` |
| `resources/interaction/TerrainCardData.cs` | `res://resources/interaction/terrain_card_data.gd` |
| `resources/interaction/TerrainInstance.cs` | `res://resources/interaction/terrain_instance.gd` |
| `resources/interaction/VaultInteraction.cs` | `res://resources/interaction/vault_interaction.gd` |
| `resources/item/BaseCardData.cs` | `res://resources/item/base_card_data.gd` |
| `resources/item/card/ResourceCardData.cs` | `res://resources/item/card/resource_card_data.gd` |
| `resources/item/card/SkillCardData.cs` | `res://resources/item/card/skill_card_data.gd` |
| `resources/item/equipment/EquipmentData.cs` | `res://resources/item/equipment/equipment_data.gd` |
| `resources/item/equipment/EquipmentSetData.cs` | `res://resources/item/equipment/equipment_set_data.gd` |
| `resources/item/equipment/SetBonusTier.cs` | `res://resources/item/equipment/set_bonus_tier.gd` |
| `resources/item/ItemData.cs` | `res://resources/item/item_data.gd` |
| `resources/item/tool/ToolData.cs` | `res://resources/item/tool/tool_data.gd` |
| `resources/loot/LootDrop.cs` | `res://resources/loot/loot_drop.gd` |
| `resources/loot/LootTable.cs` | `res://resources/loot/loot_table.gd` |
| `resources/map/PassageGuardEncounterData.cs` | `res://resources/map/passage_guard_encounter_data.gd` |
| `resources/map/PassageGuardProbabilityModifier.cs` | `res://resources/map/passage_guard_probability_modifier.gd` |
| `resources/map/PassageGuardSettings.cs` | `res://resources/map/passage_guard_settings.gd` |
| `resources/monster/MonsterData.cs` | `res://resources/monster/monster_data.gd` |
| `resources/monster/MonsterSkillEntryData.cs` | `res://resources/monster/monster_skill_entry_data.gd` |
| `resources/monster/MonsterSkillPreview.cs` | `res://resources/monster/monster_skill_preview.gd` |
| `resources/monster/MonsterSkillSetData.cs` | `res://resources/monster/monster_skill_set_data.gd` |
| `resources/recipe/CraftingIngredient.cs` | `res://resources/recipe/crafting_ingredient.gd` |
| `resources/recipe/CraftingRecipe.cs` | `res://resources/recipe/crafting_recipe.gd` |
| `resources/recipe/RecipeBookData.cs` | `res://resources/recipe/recipe_book_data.gd` |
| `resources/stats/StartingStats.cs` | `res://resources/stats/starting_stats.gd` |
| `resources/talents/AttributeTalentEffect.cs` | `res://resources/talents/attribute_talent_effect.gd` |
| `resources/talents/TagTalentEffect.cs` | `res://resources/talents/tag_talent_effect.gd` |
| `resources/talents/TalentCard.cs` | `res://resources/talents/talent_card.gd` |
| `resources/talents/TalentData.cs` | `res://resources/talents/talent_data.gd` |
| `resources/talents/TalentEffect.cs` | `res://resources/talents/talent_effect.gd` |
| `resources/talents/TalentManager.cs` | `res://resources/talents/talent_manager.gd` |
| `resources/weather/WeatherData.cs` | `res://resources/weather/weather_data.gd` |

## B–E 无孪生的 39 个文件（镜像契约分类表）

### KIND_PROTOCOL（协议 / 接口垫片，12）

| C# 文件 | GDScript 等价实现 / 归属 |
| --- | --- |
| `core/combat/effects/CardEffectProtocol.cs` | `res://core/combat/effects/card_effect.gd` |
| `core/combat/skills/CombatSkillDataProtocol.cs` | `res://core/combat/skills/combat_skill_data.gd` |
| `core/combat/status/AttributeModifierDataProtocol.cs` | `res://core/combat/status/attribute_modifier_data.gd` |
| `core/combat/status/StatusEffectDataProtocol.cs` | `res://core/combat/status/status_effect_data.gd` |
| `core/crafting/ICraftingInventory.cs` | `res://entities/components/inventory_component.gd` |
| `core/interfaces/IDamageable.cs` | `res://entities/components/damage_receiver_component.gd` |
| `core/inventory/ItemStackProtocol.cs` | `res://resources/item/item_stack.gd` |
| `core/shop/IPlayerWallet.cs` | `res://core/autoloads/player_wallet.gd` |
| `core/shop/IShopInventory.cs` | `res://entities/components/inventory_component.gd` |
| `resources/interaction/TerrainInstanceProtocol.cs` | `res://resources/interaction/terrain_instance.gd` |
| `resources/interaction/WorldInteractionPorts.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/monster/MonsterDataProtocol.cs` | `res://resources/monster/monster_data.gd` |

### KIND_INLINED（已内联进 GDScript 生产实现，17）

| C# 文件 | GDScript 等价实现 / 归属 |
| --- | --- |
| `core/gameflow/ScreenTransitionAdapter.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `core/gameflow/TerrainInteractionExecutor.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `core/gameflow/WorldCombatScenePresenter.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `core/gameflow/WorldViewVisibilityController.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/CheckGatheringEncounterOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/EnterVaultOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/MarkHarvestedOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/MonsterSpawnOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/OpenFarmingPanelOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/PassTimeOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/RecordReusableGatheringOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/RemoveSourceCardOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/SpawnLootOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/operations/TerrainOp.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/TerrainInteraction.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/TerrainInteractionBuildContext.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |
| `resources/interaction/WorldInteractionContext.cs` | `res://core/gameflow/world_interaction_coordinator.gd` |

### KIND_LOGIC（非 Resource 逻辑类，9）

| C# 文件 | GDScript 等价实现 / 归属 |
| --- | --- |
| `core/application/EncounterMonsterScaler.cs` | `res://core/application/encounter_manager.gd` |
| `core/combat/skills/SkillTargetingType.cs` | `res://scripts/generated/SkillTargetingType.gd` |
| `core/inventory/ItemStack.cs` | `res://resources/item/item_stack.gd` |
| `core/map/PassageGuardEdge.cs` | `res://core/map/passage_guard_state.gd` |
| `core/progression/PlayerDataPolicy.cs` | `res://core/autoloads/player_wallet.gd + res://core/progression/player_progression.gd` |
| `core/progression/UpgradeService.cs` | `res://core/progression/player_progression.gd` |
| `core/shop/ShopCatalog.cs` | `res://resources/shop/shop_catalog.gd` |
| `entities/components/ComponentLookup.cs` | `res://tests/godot/test_status_component_contract.gd` |
| `resources/encounters/MonsterStatMultiplier.cs` | `res://core/application/encounter_manager.gd` |

### KIND_TEST_HARNESS（C# 对照测试工程，1）

| C# 文件 | GDScript 等价实现 / 归属 |
| --- | --- |
| `tests/CUSGA.Tests/Program.cs` | （对照测试工程，无 GDScript 等价物；`tests/godot` 侧引用均已包在 `present(...)` 守卫内） |

## 退役前置条件（未满足前不删）

1. 开发者授权删除范围（`.cs` / `CUSGA.csproj` / `CUSGA.sln` / `project.godot` 的 `[dotnet]` 段 / `.uid` 旁车），并明确 E 类 `tests/CUSGA.Tests/Program.cs` 是否保留。
2. **新开一次编辑器会话**：当前会话内存里已加载 `CUSGA.dll`，同会话内删除无法得到干净结论。
3. 删除后复跑全量 GodotAI 测试 + 端到端冒烟（主菜单 → 进入游戏 → 核心玩法 → UI → 场景切换 → 存档读写 → 暂停恢复 → 退出）。
4. 移除 `core/application/gameplay_port.gd::_is_csharp_script_instance()` 双路分发与 `tests/godot/csharp_optional.gd` 垫片。
