using CUSGA.core.application;
using CUSGA.core.combat.skills;
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
tests.NewEquipmentSlotsAcceptCurrentItemTags();
tests.MagicItemSlotRequiresExplicitMagicItemTag();
tests.EquipmentDataCanAllowBothRingSlots();
tests.EquippedTorchAppliesEncounterMultiplierUntilUnequipped();
tests.GatheringEncounterModifierOnlyReducesNightChance();

Console.WriteLine("All CUSGA tests passed.");

internal sealed class TerrainRandomizationTests
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

        var monster = CreateMonsterDataStub();
        monster.MonsterName = "Scaled";
        monster.MaxHealth = 100;
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
        Assert.Equal(180, scaledMonster.MaxHealth);
        Assert.Approximately(240f, scaledMonster.InitialAttributes.BasePhysAtk);
        Assert.Approximately(1440f, scaledMonster.InitialAttributes.BasePhysDef);
        Assert.Approximately(1440f, scaledMonster.InitialAttributes.BaseMagPower);
        Assert.Approximately(4800f, scaledMonster.InitialAttributes.BaseMagResist);
        Assert.Approximately(30f, scaledMonster.InitialAttributes.BaseSpeed);
        Assert.Equal(100, monster.MaxHealth);
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
