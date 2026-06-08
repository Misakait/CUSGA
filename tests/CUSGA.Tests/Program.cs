using CUSGA.core.application;
using CUSGA.core.attributes;
using CUSGA.core.combat;
using CUSGA.core.combat.buffs;
using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;
using CUSGA.core.combat.status;
using CUSGA.core.constants;
using CUSGA.core.crafting;
using CUSGA.core.inventory;
using CUSGA.core.map;
using CUSGA.core.autoloads;
using CUSGA.entities.components;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using CUSGA.resources.crafting;
using CUSGA.resources.item;
using CUSGA.resources.item.card;
using CUSGA.resources.item.equipment;
using CUSGA.resources.monster;
using CUSGA.resources.monsters;
using CUSGA.resources.stats;
using Godot;
using System.Reflection;
using System.Runtime.CompilerServices;

var tests = new TerrainRandomizationTests();
tests.GeneratedLayoutUsesProfileAndCarriesVarianceMultiplier();
tests.StorePersistsGeneratedTerrainBoardPositionsAndVariance();
tests.EncounterMonsterScalerDuplicatesAndScalesAllEncounterStats();
tests.MonsterSkillComponentReturnsConfiguredCombatSkills();
tests.MonsterSkillComponentRandomSkillComesFromConfiguredSkillSet();
tests.CraftingSimulationAllowsOutputWhenConsumedMaterialsFreeSlot();
tests.CraftingSimulationRejectsOutputWhenFreedSlotsStillCannotHoldResult();
tests.CraftingFailureDoesNotConsumeMaterialsWhenOutputWouldNotFit();
tests.BattleDeckExpandsWhenAddingBeyondInitialCapacity();
tests.RegularInventoryKeepsFixedCapacityWhenFull();
tests.QuickTransferMovesSkillCardBetweenInventoryAndBattleDeck();
tests.BulkTransferMovesOnlySkillCardsWithoutReplacingOtherItems();
tests.NewEquipmentSlotsAcceptCurrentItemTags();
tests.MagicItemSlotRequiresExplicitMagicItemTag();
tests.EquipmentDataCanAllowBothRingSlots();
tests.QuickEquipUsesEmptyCompatibleSlotBeforeReplacingEquipment();
tests.QuickEquipReplacesOccupiedSlotWhenNoEmptyCompatibleSlot();
tests.EquippedTorchAppliesEncounterMultiplierUntilUnequipped();
tests.GatheringEncounterModifierOnlyReducesNightChance();
tests.StartingStatsExposeCombatExpansionDefaults();
tests.PhysicalDamageFormulaAppliesFixedAndRatePenetration();
tests.MagicDamageFormulaClampsOverPenetratedResistance();
tests.DamageFormulaResolvesEvasionCriticalVarianceAndLifesteal();
tests.DamageFormulaCalculatesActualDamageBeforeLifesteal();
tests.DamagePayloadWithoutModifiersSkipsDirectAttackModifiers();
tests.DefaultDamageStillAppliesDirectAttackModifiers();
tests.DamagePayloadWithoutModifiersStillUsesBeforeHealthDamageHooks();
tests.StatusDamageDefaultsToNoDirectAttackModifiers();
tests.StatusDamageCanEnableCriticalWithoutOtherDirectAttackModifiers();
tests.AttributeComponentInitializesExpandedCombatAttributes();
tests.AttributeComponentSynchronizesHealthAndEnergyMaxima();
tests.AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent();
tests.AttributeComponentPreservesCurrentVitalsOnUnchangedRecalculation();
tests.AttributeComponentPreservesCurrentVitalsWhenMaximaIncrease();
tests.AttributeComponentClampsCurrentVitalsWhenMaximaShrink();
tests.HealthComponentReturnsActualDamageTaken();
tests.VitalComponentBaseReturnsActualHealingAndLoss();
tests.DamageEffectRepeatsFixedTargetForConfiguredHitCount();
tests.DamageEffectRandomCandidatePerHitFiltersDeadCandidates();
tests.BeforeSkillExecutionSkipsStatusesRemovedEarlierInSameHookPass();
tests.HitCountModifierAppliesForConfiguredAttackSkillUsesOnly();
tests.HitCountModifierDoesNotAffectSingleHitDamageOrConsumeUse();
tests.NextAttackDamageBonusAppliesToEverySegmentForConfiguredAttackSkillUses();
tests.NonAttackSkillDoesNotConsumeAttackSkillUseModifiers();

Console.WriteLine("All CUSGA tests passed.");

internal sealed partial class TerrainRandomizationTests
{
    // 验证 RoomTerrainLayoutGenerator 是否能根据给定的配置文件（Profile）正确生成地形布局
    public void GeneratedLayoutUsesProfileAndCarriesVarianceMultiplier()
    {
        var sand = CreateTerrainCardDataStub();
        var stone = CreateTerrainCardDataStub();
        var profile = CreateRoomTerrainProfileStub();
        profile.MinCount = 2;
        profile.MaxCount = 4;
        profile.GridColumns = 5;
        profile.GridRows = 3;
        profile.PlacementMin = new Vector2(300, 200);
        profile.PlacementMax = new Vector2(900, 560);
        profile.EncounterVarianceRange = CreateMultiplierRange(
            CreateMultiplier(1.25f, 1.1f, 1.2f, 1.3f, 1.4f, 0.9f),
            CreateMultiplier(1.25f, 1.1f, 1.2f, 1.3f, 1.4f, 0.9f)
        );
        profile.TerrainPool =
        [
            CreatePoolEntry(sand, 1f),
            CreatePoolEntry(stone, 1f)
        ];
        var generator = new RoomTerrainLayoutGenerator(new Random(1234));

        IReadOnlyList<TerrainSpawnPlacement> layout = generator.Generate(profile);

        Assert.True(layout.Count >= profile.MinCount && layout.Count <= profile.MaxCount);
        Assert.Equal(layout.Count, layout.Select(p => p.LocalGridPos).Distinct().Count());
        Assert.True(layout.All(p => p.BoardPosition.X >= profile.PlacementMin.X));
        Assert.True(layout.All(p => p.BoardPosition.X <= profile.PlacementMax.X));
        Assert.True(layout.All(p => p.BoardPosition.Y >= profile.PlacementMin.Y));
        Assert.True(layout.All(p => p.BoardPosition.Y <= profile.PlacementMax.Y));
        Assert.True(layout.All(p => p.TerrainData == sand || p.TerrainData == stone));
        Assert.True(layout.All(p => p.EncounterVarianceMultiplier.MaxHealth == 1.25f));
        Assert.True(layout.All(p => p.EncounterVarianceMultiplier.Speed == 0.9f));
    }

    // 验证 RoomTerrainStore 是否能正确地保存和读取地形数据
    public void StorePersistsGeneratedTerrainBoardPositionsAndVariance()
    {
        var roomPos = new Vector2I(2, 3);
        var terrainData = CreateTerrainCardDataStub();
        var store = CreateRoomTerrainStoreStub();

        store.CreateRoomLayout(
            roomPos,
            [
                new TerrainSpawnPlacement(
                    terrainData,
                    new Vector2I(0, 0),
                    new Vector2(400, 300),
                    CreateMultiplier(maxHealth: 1.4f, speed: 0.8f)
                ),
                new TerrainSpawnPlacement(
                    terrainData,
                    new Vector2I(1, 2),
                    new Vector2(520, 460),
                    CreateMultiplier()
                )
            ]
        );

        Assert.True(store.HasRoom(roomPos));
        Assert.True(store.TryGet(roomPos, new Vector2I(0, 0), out TerrainInstance terrain));
        Assert.Equal(new Vector2(400, 300), terrain.BoardPosition);
        Assert.Equal(1.4f, terrain.EncounterVarianceMultiplier.MaxHealth);
        Assert.Equal(0.8f, terrain.EncounterVarianceMultiplier.Speed);
    }

    // 验证在遭遇战中，怪物数据是否被正确拷贝并根据乘数和天数缩放，同时确保原始数据不被污染
    public void EncounterMonsterScalerDuplicatesAndScalesAllEncounterStats()
    {
        var baseStats = CreateStartingStatsStub();
        baseStats.BasePhysAtk = 100f;
        baseStats.BasePhysDef = 400f;
        baseStats.BaseMagPower = 300f;
        baseStats.BaseMagResist = 800f;
        baseStats.BaseSpeed = 50f;
        baseStats.BaseMaxHealth = 100f;

        var monster = CreateMonsterDataStub();
        monster.MonsterName = "Scaled";
        monster.InitialAttributes = baseStats;
        monster.SkillSet = CreateMonsterSkillSet(CreateMonsterSkillEntry(CreateCombatSkillDataStub()));

        var scaler = new EncounterMonsterScaler(
            CreateMonsterDataStub,
            CreateStartingStatsStub
        );

        IReadOnlyList<MonsterData> scaled = scaler.ScaleMonsters(
            new[] { monster },
            CreateMultiplier(1.5f, 2f, 3f, 4f, 5f, 0.5f),
            CreateMultiplier(0.1f, 0.1f, 0.1f, 0.1f, 0.1f, 0.1f),
            currentDay: 3
        );

        MonsterData scaledMonster = scaled[0];
        Assert.NotSame(monster, scaledMonster);
        Assert.NotSame(baseStats, scaledMonster.InitialAttributes);
        Assert.Approximately(180f, scaledMonster.InitialAttributes.BaseMaxHealth);
        Assert.Approximately(240f, scaledMonster.InitialAttributes.BasePhysAtk);
        Assert.Approximately(1440f, scaledMonster.InitialAttributes.BasePhysDef);
        Assert.Approximately(1440f, scaledMonster.InitialAttributes.BaseMagPower);
        Assert.Approximately(4800f, scaledMonster.InitialAttributes.BaseMagResist);
        Assert.Approximately(30f, scaledMonster.InitialAttributes.BaseSpeed);
        Assert.Approximately(100f, baseStats.BaseMaxHealth);
        Assert.Approximately(100f, baseStats.BasePhysAtk);
        Assert.Same(monster.SkillSet, scaledMonster.SkillSet);
    }

    public void MonsterSkillComponentReturnsConfiguredCombatSkills()
    {
        var firstSkill = CreateCombatSkillDataStub();
        var secondSkill = CreateCombatSkillDataStub();
        var component = new MonsterSkillComponent();
        component.Initialize(
            CreateMonsterSkillSet(
                CreateMonsterSkillEntry(firstSkill),
                null,
                CreateMonsterSkillEntry(null),
                CreateMonsterSkillEntry(secondSkill)
            )
        );

        var skills = component.GetCombatSkills();

        Assert.Equal(2, skills.Count);
        Assert.Same(firstSkill, skills[0]);
        Assert.Same(secondSkill, skills[1]);
    }

    public void MonsterSkillComponentRandomSkillComesFromConfiguredSkillSet()
    {
        var skill = CreateCombatSkillDataStub();
        var component = new MonsterSkillComponent();
        component.Initialize(CreateMonsterSkillSet(CreateMonsterSkillEntry(skill)));

        CombatSkillData selected = component.GetRandomCombatSkill();

        Assert.Same(skill, selected);
    }

    public void CraftingSimulationAllowsOutputWhenConsumedMaterialsFreeSlot()
    {
        var material = CreateItemDataStub(maxStackSize: 99);
        var filler = CreateItemDataStub(maxStackSize: 99);
        var output = CreateItemDataStub(maxStackSize: 2);
        var inventory = new TestCraftingInventory(
            Stack(material, 5),
            Stack(filler, 1)
        );
        var recipe = CreateRecipe(output, outputAmount: 2, Ingredient(material, 5));
        var service = new CraftingService();

        Assert.True(service.CanCraft(inventory, recipe));
    }

    public void CraftingSimulationRejectsOutputWhenFreedSlotsStillCannotHoldResult()
    {
        var material = CreateItemDataStub(maxStackSize: 99);
        var filler = CreateItemDataStub(maxStackSize: 99);
        var output = CreateItemDataStub(maxStackSize: 2);
        var inventory = new TestCraftingInventory(
            Stack(material, 5),
            Stack(filler, 1)
        );
        var recipe = CreateRecipe(output, outputAmount: 3, Ingredient(material, 5));
        var service = new CraftingService();

        Assert.False(service.CanCraft(inventory, recipe));
        Assert.Equal(0, service.MaxCraftableQuantity(inventory, recipe));
    }

    public void CraftingFailureDoesNotConsumeMaterialsWhenOutputWouldNotFit()
    {
        var material = CreateItemDataStub(maxStackSize: 99);
        var filler = CreateItemDataStub(maxStackSize: 99);
        var output = CreateItemDataStub(maxStackSize: 2);
        var inventory = new TestCraftingInventory(
            Stack(material, 5),
            Stack(filler, 1)
        );
        var recipe = CreateRecipe(output, outputAmount: 3, Ingredient(material, 5));
        var service = new CraftingService();

        bool crafted = service.TryCraft(inventory, recipe, 1, out CraftingFailureReason failureReason);

        Assert.False(crafted);
        Assert.Equal(CraftingFailureReason.NotEnoughSpace, failureReason);
        Assert.Equal(5, inventory.CountWhere(item => item == material));
        Assert.Equal(1, inventory.CountWhere(item => item == filler));
        Assert.Equal(0, inventory.CountWhere(item => item == output));
    }

    /// <summary>
    /// 验证出战卡组在初始格子用尽后继续扩容，并始终留出一个可拖入的空槽。
    /// </summary>
    public void BattleDeckExpandsWhenAddingBeyondInitialCapacity()
    {
        var battleDeck = new BattleDeckComponent();
        battleDeck._Ready();
        var skillCard = CreateSkillCardDataStub();
        int initialCapacity = battleDeck.Capacity;

        Assert.True(battleDeck.CanAddItem(skillCard, initialCapacity + 1));

        int remaining = battleDeck.AddItem(skillCard, initialCapacity + 1);

        Assert.Equal(0, remaining);
        Assert.Equal(initialCapacity + 1, battleDeck.GetSkillCards().Count);
        Assert.Equal(initialCapacity + 2, battleDeck.Capacity);
        Assert.True(battleDeck.Slots[battleDeck.Capacity - 1].IsEmpty);
    }

    /// <summary>
    /// 验证普通背包仍保持固定容量，避免出战卡组扩容规则泄漏到所有背包。
    /// </summary>
    public void RegularInventoryKeepsFixedCapacityWhenFull()
    {
        var inventory = new InventoryComponent();
        inventory._Ready();
        var item = CreateItemDataStub(maxStackSize: 1);
        int initialCapacity = inventory.Capacity;

        Assert.False(inventory.CanAddItem(item, initialCapacity + 1));

        int remaining = inventory.AddItem(item, initialCapacity + 1);

        Assert.Equal(1, remaining);
        Assert.Equal(initialCapacity, inventory.Capacity);
    }

    /// <summary>
    /// 验证单张技能卡可以在背包和出战卡组之间快捷双向移动。
    /// </summary>
    public void QuickTransferMovesSkillCardBetweenInventoryAndBattleDeck()
    {
        var inventory = new InventoryComponent();
        inventory._Ready();
        var battleDeck = new BattleDeckComponent();
        battleDeck._Ready();
        var skillCard = CreateSkillCardDataStub();

        Assert.Equal(0, inventory.AddItem(skillCard, 1));

        Assert.True(inventory.TryMoveStackToFirstAvailableSlot(battleDeck, 0));
        Assert.True(inventory.GetStackAt(0).IsEmpty);
        Assert.Same(skillCard, battleDeck.GetStackAt(0).Item);

        Assert.True(battleDeck.TryMoveStackToFirstAvailableSlot(inventory, 0));
        Assert.True(battleDeck.GetStackAt(0).IsEmpty);
        Assert.Same(skillCard, inventory.GetStackAt(0).Item);
    }

    /// <summary>
    /// 验证批量快捷移动只移动匹配物品，并且不会用不同物品做交换。
    /// </summary>
    public void BulkTransferMovesOnlySkillCardsWithoutReplacingOtherItems()
    {
        var inventory = new InventoryComponent();
        inventory._Ready();
        var battleDeck = new BattleDeckComponent();
        battleDeck._Ready();
        var firstSkill = CreateSkillCardDataStub();
        var secondSkill = CreateSkillCardDataStub();
        var regularItem = CreateItemDataStub(maxStackSize: 1);

        Assert.Equal(0, inventory.AddItem(firstSkill, 1));
        Assert.Equal(0, inventory.AddItem(regularItem, 1));
        Assert.Equal(0, inventory.AddItem(secondSkill, 1));

        int moved = inventory.MoveAllMatchingStacksTo(battleDeck, item => item is SkillCardData);

        Assert.Equal(2, moved);
        Assert.True(inventory.GetStackAt(0).IsEmpty);
        Assert.Same(regularItem, inventory.GetStackAt(1).Item);
        Assert.True(inventory.GetStackAt(2).IsEmpty);
        Assert.Equal(2, battleDeck.GetSkillCards().Count);
        Assert.Same(firstSkill, battleDeck.GetStackAt(0).Item);
        Assert.Same(secondSkill, battleDeck.GetStackAt(1).Item);
    }

    /// <summary>
    /// 验证当前资源标签能被新的装备槽识别。
    /// </summary>
    public void NewEquipmentSlotsAcceptCurrentItemTags()
    {
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("LeatherHandguard_left"), 1),
            EquipmentSlot.LeftHandguard
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("LeatherHandguard_right"), 1),
            EquipmentSlot.RightHandguard
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("flametorch"), 1),
            EquipmentSlot.Torch
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("IronNecklace"), 1),
            EquipmentSlot.Pendant
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("IronRing"), 1),
            EquipmentSlot.Ring1
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("IronRing"), 1),
            EquipmentSlot.Ring2
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("IronBelt"), 1),
            EquipmentSlot.Belt
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("lifepotion", "lifepotion", TagConsts.MagicItem.ToString()), 1),
            EquipmentSlot.MagicItem
        ));
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("fire", "fire", TagConsts.MagicItem.ToString()), 1),
            EquipmentSlot.MagicItem
        ));
    }

    /// <summary>
    /// 验证魔法物品槽必须依赖明确的魔法物品标签，避免材料名称片段误判。
    /// </summary>
    public void MagicItemSlotRequiresExplicitMagicItemTag()
    {
        Assert.True(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("paper_talisman", "paper_talisman", TagConsts.MagicItem.ToString()), 1),
            EquipmentSlot.MagicItem
        ));
        Assert.False(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("goldingot"), 1),
            EquipmentSlot.MagicItem
        ));
        Assert.False(EquipmentComponent.CanEquipStack(
            Stack(CreateTaggedItemDataStub("woodenbowl"), 1),
            EquipmentSlot.MagicItem
        ));
    }

    /// <summary>
    /// 验证戒指资源可以明确配置两个戒指槽。
    /// </summary>
    public void EquipmentDataCanAllowBothRingSlots()
    {
        var ring = CreateEquipmentDataStub(EquipmentSlot.Ring1, EquipmentSlot.Ring2);
        var stack = Stack(ring, 1);

        Assert.True(EquipmentComponent.CanEquipStack(stack, EquipmentSlot.Ring1));
        Assert.True(EquipmentComponent.CanEquipStack(stack, EquipmentSlot.Ring2));
    }

    /// <summary>
    /// 验证快速装备会优先使用可兼容的空装备槽。
    /// </summary>
    public void QuickEquipUsesEmptyCompatibleSlotBeforeReplacingEquipment()
    {
        var inventory = new InventoryComponent();
        inventory._Ready();
        var equipment = new EquipmentComponent();
        var oldRing = CreateEquipmentDataStub(EquipmentSlot.Ring1, EquipmentSlot.Ring2);
        var newRing = CreateEquipmentDataStub(EquipmentSlot.Ring1, EquipmentSlot.Ring2);

        Assert.True(equipment.Equip(Stack(oldRing, 1), EquipmentSlot.Ring1));
        Assert.Equal(0, inventory.AddItem(newRing, 1));

        Assert.True(equipment.EquipFromInventoryToBestSlot(inventory, 0));

        Assert.True(inventory.GetStackAt(0).IsEmpty);
        Assert.True(equipment.TryGetEquippedStack(EquipmentSlot.Ring1, out var equippedFirstRing));
        Assert.True(equipment.TryGetEquippedStack(EquipmentSlot.Ring2, out var equippedSecondRing));
        Assert.Same(oldRing, equippedFirstRing.Item);
        Assert.Same(newRing, equippedSecondRing.Item);
    }

    /// <summary>
    /// 验证没有可兼容空槽时，快速装备会替换第一个可装备槽。
    /// </summary>
    public void QuickEquipReplacesOccupiedSlotWhenNoEmptyCompatibleSlot()
    {
        var inventory = new InventoryComponent();
        inventory._Ready();
        var equipment = new EquipmentComponent();
        var oldHelmet = CreateEquipmentDataStub(EquipmentSlot.Helmet);
        var newHelmet = CreateEquipmentDataStub(EquipmentSlot.Helmet);

        Assert.True(equipment.Equip(Stack(oldHelmet, 1), EquipmentSlot.Helmet));
        Assert.Equal(0, inventory.AddItem(newHelmet, 1));

        Assert.True(equipment.EquipFromInventoryToBestSlot(inventory, 0));

        Assert.Same(oldHelmet, inventory.GetStackAt(0).Item);
        Assert.True(equipment.TryGetEquippedStack(EquipmentSlot.Helmet, out var equippedHelmet));
        Assert.Same(newHelmet, equippedHelmet.Item);
    }

    /// <summary>
    /// 验证火把只在装备期间提供遭遇概率修正。
    /// </summary>
    public void EquippedTorchAppliesEncounterMultiplierUntilUnequipped()
    {
        var equipment = new EquipmentComponent
        {
            TorchNightEncounterChanceMultiplier = 0.4f
        };
        var torch = Stack(CreateTaggedItemDataStub("flametorch"), 1);

        Assert.True(equipment.Equip(torch, EquipmentSlot.Torch));
        Assert.Approximately(0.4f, equipment.GetNightEncounterChanceMultiplier());

        equipment.Unequip(EquipmentSlot.Torch);

        Assert.Approximately(1.0f, equipment.GetNightEncounterChanceMultiplier());
    }

    /// <summary>
    /// 验证遭遇概率修正只在夜晚生效。
    /// </summary>
    public void GatheringEncounterModifierOnlyReducesNightChance()
    {
        var time = new TimeSystem();
        time._EnterTree();
        try
        {
            var manager = new EncounterManager
            {
                GatheringRules =
                [
                    CreateGatheringEncounterRule(
                        "wood",
                        CreateMonsterDataStub()
                    )
                ],
                BaseGatheringSpawnChance = 1.0f,
                NightChanceMultiplier = 1.0f
            };

            Assert.True(manager.ResolveGatheringEncounter("wood", 0.0f).Triggered);

            time.PassTime(TimeSystem.PhaseLength);

            Assert.False(manager.ResolveGatheringEncounter("wood", 0.0f).Triggered);
        }
        finally
        {
            time._ExitTree();
        }
    }

    /// <summary>
    /// 验证新增战斗属性维度拥有明确默认值，并且基础五维枚举序号保持稳定。
    /// </summary>
    public void StartingStatsExposeCombatExpansionDefaults()
    {
        Assert.Equal(0, (int)AttributeType.PhysAtk);
        Assert.Equal(1, (int)AttributeType.PhysDef);
        Assert.Equal(2, (int)AttributeType.MagPower);
        Assert.Equal(3, (int)AttributeType.MagResist);
        Assert.Equal(4, (int)AttributeType.Speed);

        var stats = new StartingStats();

        Assert.Approximately(1000f, stats.BaseMaxHealth);
        Assert.Approximately(0f, stats.MaxHealthGrowth);
        Assert.Approximately(100f, stats.BaseMaxEnergy);
        Assert.Approximately(0f, stats.MaxEnergyGrowth);
        Assert.Approximately(0f, stats.BaseCritRate);
        Assert.Approximately(0f, stats.CritRateGrowth);
        Assert.Approximately(1.5f, stats.BaseCritDamage);
        Assert.Approximately(0f, stats.CritDamageGrowth);
        Assert.Approximately(0f, stats.BaseEvasionRate);
        Assert.Approximately(0f, stats.EvasionRateGrowth);
        Assert.Approximately(0f, stats.BaseLifestealRate);
        Assert.Approximately(0f, stats.LifestealRateGrowth);
        Assert.Approximately(0f, stats.BaseFixedPhysPenetration);
        Assert.Approximately(0f, stats.FixedPhysPenetrationGrowth);
        Assert.Approximately(0f, stats.BasePhysPenetrationRate);
        Assert.Approximately(0f, stats.PhysPenetrationRateGrowth);
        Assert.Approximately(0f, stats.BaseFixedMagicPenetration);
        Assert.Approximately(0f, stats.FixedMagicPenetrationGrowth);
        Assert.Approximately(0f, stats.BaseMagicPenetrationRate);
        Assert.Approximately(0f, stats.MagicPenetrationRateGrowth);
    }

    /// <summary>
    /// 验证物理基础伤害使用同一个全局常数，并同时应用固定穿透和百分比穿透。
    /// </summary>
    public void PhysicalDamageFormulaAppliesFixedAndRatePenetration()
    {
        float damage = DamageFormula.CalculatePhysicalBaseDamage(
            skillPower: 120f,
            attackerPhysAtk: 200f,
            defenderPhysDef: 300f,
            physicalPenetrationRate: 0.25f,
            fixedPhysicalPenetration: 25f
        );

        Assert.Approximately(120f, damage);
    }

    /// <summary>
    /// 验证法术穿透过量时有效法抗不会低于 0。
    /// </summary>
    public void MagicDamageFormulaClampsOverPenetratedResistance()
    {
        float damage = DamageFormula.CalculateMagicBaseDamage(
            skillPower: 60f,
            attackerMagPower: 200f,
            defenderMagResist: 120f,
            magicPenetrationRate: 1.5f,
            fixedMagicPenetration: 40f
        );

        Assert.Approximately(180f, damage);
    }

    /// <summary>
    /// 验证闪避、暴击、随机浮动和吸血的纯公式入口。
    /// </summary>
    public void DamageFormulaResolvesEvasionCriticalVarianceAndLifesteal()
    {
        Assert.True(DamageFormula.ShouldEvade(evasionRate: 0.3f, evasionRoll: 0.2f));
        Assert.False(DamageFormula.ShouldEvade(evasionRate: 0.3f, evasionRoll: 0.8f));
        Assert.True(DamageFormula.ShouldCrit(critRate: 0.4f, critRoll: 0.1f));
        Assert.False(DamageFormula.ShouldCrit(critRate: 0.4f, critRoll: 0.9f));
        Assert.Approximately(1.75f, DamageFormula.CalculateCriticalModifier(true, 1.75f));
        Assert.Approximately(1f, DamageFormula.CalculateCriticalModifier(false, 1.75f));
        Assert.Approximately(1.02f, DamageFormula.CalculateRandomVariance(0.95f, 1.05f, 0.7f));
        Assert.Equal(13, DamageFormula.CalculateLifestealAmount(51, 0.25f));
    }

    /// <summary>
    /// 验证吸血使用实际扣血量，而不是取整后的理论伤害。
    /// </summary>
    public void DamageFormulaCalculatesActualDamageBeforeLifesteal()
    {
        Assert.Equal(35, DamageFormula.CalculateActualDamage(finalDamage: 99, defenderCurrentHealth: 35));
        Assert.Equal(9, DamageFormula.CalculateLifestealAmount(finalActualDamage: 35, lifestealRate: 0.25f));
    }

    /// <summary>
    /// 验证没有直接攻击修饰的伤害不会闪避、暴击、随机浮动或吸血。
    /// </summary>
    public void DamagePayloadWithoutModifiersSkipsDirectAttackModifiers()
    {
        var probe = CreateDirectAttackModifierProbe();
        var payload = new DamagePayload
        {
            Source = probe.Source,
            Target = probe.Target,
            Damage = 10,
            Type = DamageType.Real,
            Element = ElementType.None,
            DamageModifiers = DamageModifierFlags.None
        };

        probe.Receiver.ReceiveDamage(payload);

        Assert.Equal(90, GetHealth(probe.Target).CurrentValue);
        Assert.Equal(50, GetHealth(probe.Source).CurrentValue);
    }

    /// <summary>
    /// 验证普通伤害 payload 默认仍会应用闪避等直接攻击修饰。
    /// </summary>
    public void DefaultDamageStillAppliesDirectAttackModifiers()
    {
        var source = CreateCombatEntity("Source", health: 100);
        var target = CreateCombatEntity("Target", health: 100);
        AddAttributes(target, new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseEvasionRate = 1f
        });
        var receiver = GetDamageReceiver(target);
        var payload = new DamagePayload
        {
            Source = source,
            Target = target,
            Damage = 10,
            Type = DamageType.Real,
            Element = ElementType.None
        };

        receiver.ReceiveDamage(payload);

        Assert.Equal(100, GetHealth(target).CurrentValue);
    }

    /// <summary>
    /// 验证跳过直接攻击修饰时仍会执行扣血前 Hook，例如护盾吸收。
    /// </summary>
    public void DamagePayloadWithoutModifiersStillUsesBeforeHealthDamageHooks()
    {
        var source = CreateCombatEntity("Source", health: 100);
        var target = CreateCombatEntity("Target", health: 100, withStatus: true);
        var shieldData = new ShieldStatusData
        {
            Id = new StringName("test_shield")
        };
        GetStatus(target).AddStatus(shieldData.CreateInstance(source, target, shieldAmount: 6f));
        var payload = new DamagePayload
        {
            Source = source,
            Target = target,
            Damage = 10,
            Type = DamageType.Real,
            Element = ElementType.None,
            DamageModifiers = DamageModifierFlags.None
        };

        GetDamageReceiver(target).ReceiveDamage(payload);

        Assert.Equal(96, GetHealth(target).CurrentValue);
        Assert.False(GetStatus(target).HasStatus(shieldData.Id));
    }

    /// <summary>
    /// 验证状态伤害默认不触发闪避、暴击、随机浮动或吸血。
    /// </summary>
    public void StatusDamageDefaultsToNoDirectAttackModifiers()
    {
        var probe = CreateDirectAttackModifierProbe();
        var burnData = new BurnStatusData
        {
            DamagePerStack = 10f,
            DamageType = DamageType.Real,
            Element = ElementType.None
        };

        burnData.CreateInstance(probe.Source, probe.Target).OnOwnerTurnStart();

        Assert.Equal(90, GetHealth(probe.Target).CurrentValue);
        Assert.Equal(50, GetHealth(probe.Source).CurrentValue);
    }

    /// <summary>
    /// 验证状态伤害可只开启暴击，不会同时触发闪避、随机浮动或吸血。
    /// </summary>
    public void StatusDamageCanEnableCriticalWithoutOtherDirectAttackModifiers()
    {
        var probe = CreateDirectAttackModifierProbe();
        var burnData = new BurnStatusData
        {
            DamagePerStack = 10f,
            DamageType = DamageType.Real,
            Element = ElementType.None,
            DamageModifiers = DamageModifierFlags.Critical
        };

        burnData.CreateInstance(probe.Source, probe.Target).OnOwnerTurnStart();

        Assert.Equal(70, GetHealth(probe.Target).CurrentValue);
        Assert.Equal(50, GetHealth(probe.Source).CurrentValue);
    }

    /// <summary>
    /// 验证运行时属性组件初始化全部新增战斗属性维度。
    /// </summary>
    public void AttributeComponentInitializesExpandedCombatAttributes()
    {
        var attributes = new AttributeComponent();
        var stats = new StartingStats
        {
            BaseMaxHealth = 1200f,
            BaseMaxEnergy = 80f,
            BaseFixedPhysPenetration = 18f,
            BasePhysPenetrationRate = 0.3f,
            BaseFixedMagicPenetration = 12f,
            BaseMagicPenetrationRate = 0.25f,
            BaseCritRate = 0.2f,
            BaseCritDamage = 1.75f,
            BaseEvasionRate = 0.1f,
            BaseLifestealRate = 0.15f
        };

        attributes.InitializeWithData(stats);

        Assert.Approximately(1200f, attributes.MaxHealth);
        Assert.Approximately(80f, attributes.MaxEnergy);
        Assert.Approximately(18f, attributes.FixedPhysPenetration);
        Assert.Approximately(0.3f, attributes.PhysPenetrationRate);
        Assert.Approximately(12f, attributes.FixedMagicPenetration);
        Assert.Approximately(0.25f, attributes.MagicPenetrationRate);
        Assert.Approximately(0.2f, attributes.CritRate);
        Assert.Approximately(1.75f, attributes.CritDamage);
        Assert.Approximately(0.1f, attributes.EvasionRate);
        Assert.Approximately(0.15f, attributes.LifestealRate);
    }

    /// <summary>
    /// 验证生命上限和能量上限由属性组件初始化并同步到同宿主资源组件。
    /// </summary>
    public void AttributeComponentSynchronizesHealthAndEnergyMaxima()
    {
        var owner = new Node { Name = "Components" };
        var health = new HealthComponent { Name = "HealthComponent" };
        var energy = new EnergyComponent { Name = "EnergyComponent" };
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        owner.AddChild(health);
        owner.AddChild(energy);
        owner.AddChild(attributes);

        attributes.InitializeWithData(new StartingStats
        {
            BaseMaxHealth = 1350f,
            BaseMaxEnergy = 90f
        });

        Assert.Equal(1350, health.MaxValue);
        Assert.Equal(1350, health.CurrentValue);
        Assert.Equal(90, energy.MaxValue);
        Assert.Equal(90, energy.CurrentValue);
    }

    /// <summary>
    /// 验证没有能量组件的单位仍然可以初始化属性。
    /// </summary>
    public void AttributeComponentIgnoresMaxEnergyWhenEnergyComponentIsAbsent()
    {
        var owner = new Node { Name = "Components" };
        var health = new HealthComponent { Name = "HealthComponent" };
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        owner.AddChild(health);
        owner.AddChild(attributes);

        attributes.InitializeWithData(new StartingStats
        {
            BaseMaxHealth = 777f,
            BaseMaxEnergy = 45f
        });

        Assert.Equal(777, health.MaxValue);
        Assert.Approximately(45f, attributes.MaxEnergy);
    }

    /// <summary>
    /// 验证普通属性重算不会把生命和能量隐式回满。
    /// </summary>
    public void AttributeComponentPreservesCurrentVitalsOnUnchangedRecalculation()
    {
        var owner = new Node { Name = "Components" };
        var health = new HealthComponent { Name = "HealthComponent" };
        var energy = new EnergyComponent { Name = "EnergyComponent" };
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        owner.AddChild(health);
        owner.AddChild(energy);
        owner.AddChild(attributes);

        attributes.InitializeWithData(new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseMaxEnergy = 50f
        });
        health.TakeDamage(30, ElementType.None);
        energy.Subtract(20);

        attributes.ForceRecalculateAll(owner);

        Assert.Equal(100, health.MaxValue);
        Assert.Equal(70, health.CurrentValue);
        Assert.Equal(50, energy.MaxValue);
        Assert.Equal(30, energy.CurrentValue);
    }

    /// <summary>
    /// 验证生命和能量上限提高时不会额外治疗当前值。
    /// </summary>
    public void AttributeComponentPreservesCurrentVitalsWhenMaximaIncrease()
    {
        var owner = new Node { Name = "Components" };
        var health = new HealthComponent { Name = "HealthComponent" };
        var energy = new EnergyComponent { Name = "EnergyComponent" };
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        owner.AddChild(health);
        owner.AddChild(energy);
        owner.AddChild(attributes);

        attributes.InitializeWithData(new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseMaxEnergy = 50f
        });
        health.TakeDamage(30, ElementType.None);
        energy.Subtract(20);

        attributes.AddPermanentBonus(AttributeType.MaxHealth, 40f, owner);
        attributes.AddPermanentBonus(AttributeType.MaxEnergy, 10f, owner);

        Assert.Equal(140, health.MaxValue);
        Assert.Equal(70, health.CurrentValue);
        Assert.Equal(60, energy.MaxValue);
        Assert.Equal(30, energy.CurrentValue);
    }

    /// <summary>
    /// 验证生命和能量上限降低时当前值会被钳制到新上限，但不会回满。
    /// </summary>
    public void AttributeComponentClampsCurrentVitalsWhenMaximaShrink()
    {
        var owner = new Node { Name = "Components" };
        var health = new HealthComponent { Name = "HealthComponent" };
        var energy = new EnergyComponent { Name = "EnergyComponent" };
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        owner.AddChild(health);
        owner.AddChild(energy);
        owner.AddChild(attributes);

        attributes.InitializeWithData(new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseMaxEnergy = 50f
        });
        health.TakeDamage(10, ElementType.None);
        energy.Subtract(5);

        attributes.AddPermanentBonus(AttributeType.MaxHealth, -30f, owner);
        attributes.AddPermanentBonus(AttributeType.MaxEnergy, -20f, owner);

        Assert.Equal(70, health.MaxValue);
        Assert.Equal(70, health.CurrentValue);
        Assert.Equal(30, energy.MaxValue);
        Assert.Equal(30, energy.CurrentValue);
    }

    /// <summary>
    /// 验证生命组件返回实际扣除生命，过量伤害不会被吸血错误放大。
    /// </summary>
    public void HealthComponentReturnsActualDamageTaken()
    {
        var health = new HealthComponent();
        health.InitializeMax(30);

        int firstActual = health.TakeDamage(12, ElementType.None);
        int secondActual = health.TakeDamage(99, ElementType.None);

        Assert.Equal(12, firstActual);
        Assert.Equal(18, secondActual);
        Assert.Equal(0, health.CurrentValue);
    }

    /// <summary>
    /// 验证资源基类返回实际变化量。
    /// </summary>
    public void VitalComponentBaseReturnsActualHealingAndLoss()
    {
        var energy = new EnergyComponent();
        energy.InitializeMax(10);

        int consumed = energy.Subtract(7);
        int overConsumed = energy.Subtract(9);
        int restored = energy.Add(4);
        int overRestored = energy.Add(99);

        Assert.Equal(7, consumed);
        Assert.Equal(3, overConsumed);
        Assert.Equal(4, restored);
        Assert.Equal(6, overRestored);
        Assert.Equal(10, energy.CurrentValue);
    }

    /// <summary>
    /// 验证伤害效果会按配置段数重复对固定目标造成独立伤害。
    /// </summary>
    public void DamageEffectRepeatsFixedTargetForConfiguredHitCount()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var target = CreateCombatEntity("Target", health: 100);
        var targetHealth = GetHealth(target);
        var damageTakenEvents = 0;
        targetHealth.DamageTaken += (_, _) => damageTakenEvents++;
        var effect = CreateRealDamageEffect(baseDamage: 10, hitCount: 3);
        var context = SkillExecutionContext.FromSingleTarget(source, target);

        effect.Execute(context);

        Assert.Equal(70, targetHealth.CurrentValue);
        Assert.Equal(3, damageTakenEvents);
    }

    /// <summary>
    /// 验证分段随机模式每段都会过滤已经无效的候选目标。
    /// </summary>
    public void DamageEffectRandomCandidatePerHitFiltersDeadCandidates()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var deadTarget = CreateCombatEntity("DeadTarget", health: 1);
        var aliveTarget = CreateCombatEntity("AliveTarget", health: 100);
        GetHealth(deadTarget).TakeDamage(1, ElementType.None);
        var aliveHealth = GetHealth(aliveTarget);
        var effect = CreateRealDamageEffect(baseDamage: 10, hitCount: 3);
        effect.HitTargetMode = DamageHitTargetMode.RandomCandidatePerHit;
        var context = SkillExecutionContext.FromSingleTarget(
            source,
            deadTarget,
            [deadTarget, aliveTarget]
        );

        effect.Execute(context);

        Assert.Equal(70, aliveHealth.CurrentValue);
        Assert.Equal(0, GetHealth(deadTarget).CurrentValue);
    }

    /// <summary>
    /// 验证技能开始 Hook 中被移除的状态不会继续参与本轮 Hook 调用。
    /// </summary>
    public void BeforeSkillExecutionSkipsStatusesRemovedEarlierInSameHookPass()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var statusComponent = GetStatus(source);
        var removedStatusId = new StringName("removed_before_hook_counter");
        var callCounter = new BeforeSkillExecutionCallCounter();
        var removerData = new RemovingBeforeSkillStatusData
        {
            Id = new StringName("remove_other_before_hook"),
            DefaultHookPriority = -100,
            TargetStatusId = removedStatusId
        };
        var counterData = new CountingBeforeSkillStatusData
        {
            Id = removedStatusId,
            Counter = callCounter
        };
        statusComponent.AddStatus(counterData.CreateInstance(source, source));
        statusComponent.AddStatus(removerData.CreateInstance(source, source));
        var skillContext = SkillExecutionContext.Self(source);
        var modifierContext = new SkillExecutionModifierContext(
            source,
            new CombatSkillData(),
            skillContext,
            hasDamageEffect: false
        );

        statusComponent.ProcessBeforeSkillExecution(modifierContext);

        Assert.False(statusComponent.HasStatus(removedStatusId));
        Assert.Equal(0, callCounter.Count);
    }

    /// <summary>
    /// 验证限次段数 Buff 只影响配置数量的多段攻击牌，且非攻击牌不会消耗次数。
    /// </summary>
    public void HitCountModifierAppliesForConfiguredAttackSkillUsesOnly()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var target = CreateCombatEntity("Target", health: 100);
        var targetHealth = GetHealth(target);
        var statusComponent = GetStatus(source);
        var status = new HitCountModifierStatusData
        {
            Id = new StringName("hit_count_plus_two_two_uses"),
            FlatHitCountBonusPerStack = 2,
            AttackSkillUses = 2
        };
        statusComponent.AddStatus(status.CreateInstance(source, source));

        var nonAttackSkill = new CombatSkillData();
        var attackSkill = CreateCombatSkill(CreateRealDamageEffect(baseDamage: 1, hitCount: 2));
        var context = SkillExecutionContext.FromSingleTarget(source, target);

        nonAttackSkill.Execute(context);
        attackSkill.Execute(context);
        attackSkill.Execute(context);
        attackSkill.Execute(context);

        Assert.Equal(90, targetHealth.CurrentValue);
        Assert.False(statusComponent.HasStatus(status.Id));
    }

    /// <summary>
    /// 验证段数 Buff 不会把单段伤害变成多段，也不会被单段攻击牌消耗。
    /// </summary>
    public void HitCountModifierDoesNotAffectSingleHitDamageOrConsumeUse()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var target = CreateCombatEntity("Target", health: 100);
        var targetHealth = GetHealth(target);
        var statusComponent = GetStatus(source);
        var status = new HitCountModifierStatusData
        {
            Id = new StringName("hit_count_plus_two_single_guard"),
            FlatHitCountBonusPerStack = 2,
            AttackSkillUses = 1
        };
        statusComponent.AddStatus(status.CreateInstance(source, source));

        var singleHitSkill = CreateCombatSkill(CreateRealDamageEffect(baseDamage: 1, hitCount: 1));
        var multiHitSkill = CreateCombatSkill(CreateRealDamageEffect(baseDamage: 1, hitCount: 2));
        var context = SkillExecutionContext.FromSingleTarget(source, target);

        singleHitSkill.Execute(context);

        Assert.Equal(99, targetHealth.CurrentValue);
        Assert.True(statusComponent.HasStatus(status.Id));

        multiHitSkill.Execute(context);

        Assert.Equal(95, targetHealth.CurrentValue);
        Assert.False(statusComponent.HasStatus(status.Id));
    }

    /// <summary>
    /// 验证限次基础伤害 Buff 会作用到攻击牌的每一段，并按攻击牌次数消耗。
    /// </summary>
    public void NextAttackDamageBonusAppliesToEverySegmentForConfiguredAttackSkillUses()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var target = CreateCombatEntity("Target", health: 200);
        var targetHealth = GetHealth(target);
        var statusComponent = GetStatus(source);
        var status = new NextAttackDamageBonusStatusData
        {
            Id = new StringName("next_two_attack_damage_plus_ten"),
            FlatSegmentDamageBonusPerStack = 10,
            AttackSkillUses = 2
        };
        statusComponent.AddStatus(status.CreateInstance(source, source));

        var attackSkill = CreateCombatSkill(CreateRealDamageEffect(baseDamage: 1, hitCount: 5));
        var context = SkillExecutionContext.FromSingleTarget(source, target);

        attackSkill.Execute(context);
        attackSkill.Execute(context);
        attackSkill.Execute(context);

        Assert.Equal(85, targetHealth.CurrentValue);
        Assert.False(statusComponent.HasStatus(status.Id));
    }

    /// <summary>
    /// 验证没有伤害效果的技能不会消耗限次攻击牌 Buff。
    /// </summary>
    public void NonAttackSkillDoesNotConsumeAttackSkillUseModifiers()
    {
        var source = CreateCombatEntity("Source", withStatus: true);
        var target = CreateCombatEntity("Target", health: 100);
        var statusComponent = GetStatus(source);
        var status = new NextAttackDamageBonusStatusData
        {
            Id = new StringName("next_attack_damage_plus_ten"),
            FlatSegmentDamageBonusPerStack = 10,
            AttackSkillUses = 1
        };
        statusComponent.AddStatus(status.CreateInstance(source, source));

        var nonAttackSkill = new CombatSkillData();
        var context = SkillExecutionContext.FromSingleTarget(source, target);

        nonAttackSkill.Execute(context);

        Assert.True(statusComponent.HasStatus(status.Id));
    }

    private static TerrainCardData CreateTerrainCardDataStub()
    {
        return (TerrainCardData)RuntimeHelpers.GetUninitializedObject(typeof(TerrainCardData));
    }

    private static RoomTerrainProfile CreateRoomTerrainProfileStub()
    {
        return (RoomTerrainProfile)RuntimeHelpers.GetUninitializedObject(typeof(RoomTerrainProfile));
    }

    private static RoomTerrainPoolEntry CreatePoolEntry(TerrainCardData terrainData, float weight)
    {
        var entry = (RoomTerrainPoolEntry)RuntimeHelpers.GetUninitializedObject(typeof(RoomTerrainPoolEntry));
        entry.TerrainData = terrainData;
        entry.Weight = weight;
        return entry;
    }

    private static MonsterStatMultiplierRange CreateMultiplierRange(
        MonsterStatMultiplier min,
        MonsterStatMultiplier max)
    {
        var range = (MonsterStatMultiplierRange)RuntimeHelpers.GetUninitializedObject(
            typeof(MonsterStatMultiplierRange)
        );
        range.Min = min;
        range.Max = max;
        return range;
    }

    private static MonsterStatMultiplier CreateMultiplier(
        float maxHealth = 1f,
        float physAtk = 1f,
        float physDef = 1f,
        float magPower = 1f,
        float magResist = 1f,
        float speed = 1f)
    {
        var multiplier = (MonsterStatMultiplier)RuntimeHelpers.GetUninitializedObject(
            typeof(MonsterStatMultiplier)
        );
        multiplier.MaxHealth = maxHealth;
        multiplier.PhysAtk = physAtk;
        multiplier.PhysDef = physDef;
        multiplier.MagPower = magPower;
        multiplier.MagResist = magResist;
        multiplier.Speed = speed;
        return multiplier;
    }

    private static MonsterData CreateMonsterDataStub()
    {
        return (MonsterData)RuntimeHelpers.GetUninitializedObject(typeof(MonsterData));
    }

    private static MonsterSkillSetData CreateMonsterSkillSet(params MonsterSkillEntryData?[] entries)
    {
        var skillSet = (MonsterSkillSetData)RuntimeHelpers.GetUninitializedObject(
            typeof(MonsterSkillSetData)
        );
        skillSet.Skills = [];
        foreach (var entry in entries)
        {
            skillSet.Skills.Add(entry!);
        }

        return skillSet;
    }

    private static MonsterSkillEntryData CreateMonsterSkillEntry(CombatSkillData? skill)
    {
        var entry = (MonsterSkillEntryData)RuntimeHelpers.GetUninitializedObject(
            typeof(MonsterSkillEntryData)
        );
        entry.Skill = skill;
        return entry;
    }

    private static CombatSkillData CreateCombatSkillDataStub()
    {
        return (CombatSkillData)RuntimeHelpers.GetUninitializedObject(typeof(CombatSkillData));
    }

    private static CombatSkillData CreateCombatSkill(params CardEffect[] effects)
    {
        var skill = new CombatSkillData();
        foreach (var effect in effects)
        {
            skill.Effects.Add(effect);
        }

        return skill;
    }

    private static DamageEffect CreateRealDamageEffect(int baseDamage, int hitCount)
    {
        return new DamageEffect
        {
            BaseDamage = baseDamage,
            HitCount = hitCount,
            Type = DamageType.Real,
            Element = ElementType.None,
            TargetScope = SkillEffectTargetScope.PrimaryOnly
        };
    }

    private static Node CreateCombatEntity(
        string name,
        int health = 100,
        bool withStatus = false
    )
    {
        var entity = new Node { Name = name };
        var components = new Node { Name = "Components" };
        var healthComponent = new HealthComponent { Name = "HealthComponent" };
        var receiver = new DamageReceiverComponent
        {
            Name = "DamageReceiverComponent",
            RandomVarianceMin = 1f,
            RandomVarianceMax = 1f
        };

        entity.AddChild(components);
        components.AddChild(healthComponent);
        components.AddChild(receiver);
        healthComponent.InitializeMax(health);

        if (withStatus)
        {
            components.AddChild(new StatusComponent { Name = "StatusComponent" });
        }

        return entity;
    }

    private static HealthComponent GetHealth(Node entity)
    {
        return entity.GetNode<HealthComponent>("Components/HealthComponent");
    }

    private static DamageReceiverComponent GetDamageReceiver(Node entity)
    {
        return entity.GetNode<DamageReceiverComponent>("Components/DamageReceiverComponent");
    }

    private static AttributeComponent AddAttributes(Node entity, StartingStats stats)
    {
        var attributes = new AttributeComponent { Name = "AttributeComponent" };
        entity.GetNode<Node>("Components").AddChild(attributes);
        attributes.InitializeWithData(stats);
        return attributes;
    }

    private static DirectAttackModifierProbe CreateDirectAttackModifierProbe()
    {
        var source = CreateCombatEntity("Source", health: 100);
        var target = CreateCombatEntity("Target", health: 100);
        AddAttributes(source, new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseCritRate = 1f,
            BaseCritDamage = 3f,
            BaseLifestealRate = 1f
        });
        AddAttributes(target, new StartingStats
        {
            BaseMaxHealth = 100f,
            BaseEvasionRate = 1f
        });
        GetHealth(source).TakeDamage(50, ElementType.None);
        var receiver = GetDamageReceiver(target);
        receiver.RandomVarianceMin = 2f;
        receiver.RandomVarianceMax = 2f;

        return new DirectAttackModifierProbe(source, target, receiver);
    }

    private sealed class DirectAttackModifierProbe(
        Node source,
        Node target,
        DamageReceiverComponent receiver
    )
    {
        public Node Source { get; } = source;
        public Node Target { get; } = target;
        public DamageReceiverComponent Receiver { get; } = receiver;
    }

    private static StatusComponent GetStatus(Node entity)
    {
        return entity.GetNode<StatusComponent>("Components/StatusComponent");
    }

    private sealed class BeforeSkillExecutionCallCounter
    {
        public int Count { get; set; }
    }

    private sealed partial class RemovingBeforeSkillStatusData : StatusEffectData
    {
        public StringName TargetStatusId { get; set; } = default!;

        public override StatusEffectInstance CreateInstance(Node source, Node owner)
        {
            return new RemovingBeforeSkillStatusInstance(this, source, owner);
        }
    }

    private sealed partial class RemovingBeforeSkillStatusInstance(
        RemovingBeforeSkillStatusData data,
        Node source,
        Node owner
    ) : StatusEffectInstance(data, source, owner)
    {
        private readonly RemovingBeforeSkillStatusData _data = data;

        public override void OnBeforeSkillExecution(SkillExecutionModifierContext context)
        {
            Owner.GetNodeOrNull<StatusComponent>("Components/StatusComponent")
                ?.RemoveStatus(_data.TargetStatusId);
        }
    }

    private sealed partial class CountingBeforeSkillStatusData : StatusEffectData
    {
        public BeforeSkillExecutionCallCounter Counter { get; init; } = new();

        public override StatusEffectInstance CreateInstance(Node source, Node owner)
        {
            return new CountingBeforeSkillStatusInstance(this, source, owner);
        }
    }

    private sealed partial class CountingBeforeSkillStatusInstance(
        CountingBeforeSkillStatusData data,
        Node source,
        Node owner
    ) : StatusEffectInstance(data, source, owner)
    {
        private readonly CountingBeforeSkillStatusData _data = data;

        public override void OnBeforeSkillExecution(SkillExecutionModifierContext context)
        {
            _data.Counter.Count++;
        }
    }

    private static StartingStats CreateStartingStatsStub()
    {
        return (StartingStats)RuntimeHelpers.GetUninitializedObject(typeof(StartingStats));
    }

    private static ItemData CreateItemDataStub(int maxStackSize)
    {
        var item = (ItemData)RuntimeHelpers.GetUninitializedObject(typeof(ItemData));
        item.MaxStackSize = maxStackSize;
        return item;
    }

    private static ItemData CreateTaggedItemDataStub(string cardId, params string[] tags)
    {
        var item = CreateItemDataStub(maxStackSize: 99);
        item.ItemTags = [];
        if (tags.Length == 0)
        {
            item.ItemTags.Add(new StringName(cardId));
        }
        else
        {
            foreach (string tag in tags)
            {
                item.ItemTags.Add(new StringName(tag));
            }
        }
        item.CardId = new StringName(cardId);
        return item;
    }

    private static SkillCardData CreateSkillCardDataStub()
    {
        return (SkillCardData)RuntimeHelpers.GetUninitializedObject(typeof(SkillCardData));
    }

    private static EquipmentData CreateEquipmentDataStub(params EquipmentSlot[] validSlots)
    {
        var item = (EquipmentData)RuntimeHelpers.GetUninitializedObject(typeof(EquipmentData));
        item.MaxStackSize = 1;
        item.ValidSlots = [.. validSlots];
        item.GrantedTags = [];
        item.AttributeBonuses = [];
        return item;
    }

    private static GatheringEncounterRule CreateGatheringEncounterRule(
        StringName triggerTag,
        MonsterData monster)
    {
        var rule = (GatheringEncounterRule)RuntimeHelpers.GetUninitializedObject(
            typeof(GatheringEncounterRule)
        );
        rule.TriggerTag = triggerTag;
        rule.MonsterToSpawn = [monster];
        rule.SpawnMessage = "test";
        return rule;
    }

    private static CraftingRecipe CreateRecipe(
        ItemData outputItem,
        int outputAmount,
        params CraftingIngredient[] inputs)
    {
        var recipe = (CraftingRecipe)RuntimeHelpers.GetUninitializedObject(typeof(CraftingRecipe));
        recipe.OutputItem = outputItem;
        recipe.OutputAmount = outputAmount;
        recipe.Inputs = [.. inputs];
        return recipe;
    }

    private static CraftingIngredient Ingredient(ItemData item, int amount)
    {
        var ingredient = (CraftingIngredient)RuntimeHelpers.GetUninitializedObject(
            typeof(CraftingIngredient)
        );
        ingredient.RequiredItem = item;
        ingredient.Amount = amount;
        return ingredient;
    }

    private static ItemStack Stack(ItemData item, int amount)
    {
        var stack = new ItemStack();
        stack.SetItem(item, amount);
        return stack;
    }

    private static RoomTerrainStore CreateRoomTerrainStoreStub()
    {
        var store = (RoomTerrainStore)RuntimeHelpers.GetUninitializedObject(typeof(RoomTerrainStore));
        SetPrivateField(
            store,
            "_terrainByRoom",
            new Dictionary<Vector2I, Dictionary<Vector2I, TerrainInstance>>()
        );
        SetPrivateField(
            store,
            "_terrainFactory",
            () => (TerrainInstance)RuntimeHelpers.GetUninitializedObject(typeof(TerrainInstance))
        );

        return store;
    }

    private static void SetPrivateField<T>(object target, string fieldName, T value)
    {
        FieldInfo field = target.GetType().GetField(
            fieldName,
            BindingFlags.Instance | BindingFlags.NonPublic
        ) ?? throw new MissingFieldException(target.GetType().FullName, fieldName);

        field.SetValue(target, value);
    }
}

internal sealed class TestCraftingInventory : ICraftingInventory
{
    private readonly ItemStack[] _slots;

    public TestCraftingInventory(params ItemStack[] slots)
    {
        _slots = slots;
    }

    public IReadOnlyList<ItemStack> Slots => _slots;

    public bool CanStore(ItemData item)
    {
        return item != null;
    }

    public int CountWhere(Func<ItemData, bool> predicate)
    {
        ArgumentNullException.ThrowIfNull(predicate);

        int total = 0;
        foreach (ItemStack slot in _slots)
        {
            if (!slot.IsEmpty && predicate(slot.Item))
            {
                total += slot.Amount;
            }
        }

        return total;
    }

    public int AddItem(ItemData item, int amount)
    {
        if (item == null || amount <= 0 || item.ActualMaxStackSize <= 0)
        {
            return amount;
        }

        int remaining = amount;
        foreach (ItemStack slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item && !slot.IsFull)
            {
                remaining = slot.Add(remaining);
                if (remaining <= 0)
                {
                    return 0;
                }
            }
        }

        foreach (ItemStack slot in _slots)
        {
            if (!slot.IsEmpty)
            {
                continue;
            }

            int amountToAdd = Math.Min(remaining, item.ActualMaxStackSize);
            slot.SetItem(item, amountToAdd);
            remaining -= amountToAdd;
            if (remaining <= 0)
            {
                return 0;
            }
        }

        return remaining;
    }

    public bool TryRemoveItems(IReadOnlyDictionary<ItemData, int> itemsToRemove)
    {
        if (itemsToRemove == null || itemsToRemove.Count == 0)
        {
            return false;
        }

        foreach (var itemToRemove in itemsToRemove)
        {
            if (itemToRemove.Key == null
                || itemToRemove.Value <= 0
                || CountWhere(item => item == itemToRemove.Key) < itemToRemove.Value)
            {
                return false;
            }
        }

        foreach (var itemToRemove in itemsToRemove)
        {
            RemoveItem(itemToRemove.Key, itemToRemove.Value);
        }

        return true;
    }

    private void RemoveItem(ItemData item, int amountToRemove)
    {
        int remainingToRemove = amountToRemove;
        for (int i = _slots.Length - 1; i >= 0 && remainingToRemove > 0; i--)
        {
            ItemStack slot = _slots[i];
            if (slot.IsEmpty || slot.Item != item)
            {
                continue;
            }

            int removed = Math.Min(slot.Amount, remainingToRemove);
            slot.SetItem(slot.Item, slot.Amount - removed);
            remainingToRemove -= removed;
        }
    }
}

internal static class Assert
{
    public static void True(bool condition, string? message = null)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message ?? "Expected condition to be true.");
        }
    }

    public static void False(bool condition, string? message = null)
    {
        if (condition)
        {
            throw new InvalidOperationException(message ?? "Expected condition to be false.");
        }
    }

    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"Expected {expected}, got {actual}.");
        }
    }

    public static void Approximately(float expected, float actual, float tolerance = 0.001f)
    {
        if (Math.Abs(expected - actual) > tolerance)
        {
            throw new InvalidOperationException($"Expected approximately {expected}, got {actual}.");
        }
    }

    public static void NotSame(object expectedDifferent, object actual)
    {
        if (ReferenceEquals(expectedDifferent, actual))
        {
            throw new InvalidOperationException("Expected different object instances.");
        }
    }

    public static void Same(object expected, object actual)
    {
        if (!ReferenceEquals(expected, actual))
        {
            throw new InvalidOperationException("Expected same object instance.");
        }
    }
}
