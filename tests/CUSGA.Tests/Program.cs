using CUSGA.core.application;
using CUSGA.core.map;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;
using CUSGA.resources.stats;
using Godot;
using System.Reflection;
using System.Runtime.CompilerServices;

var tests = new TerrainRandomizationTests();
tests.GeneratedLayoutUsesProfileAndCarriesVarianceMultiplier();
tests.StorePersistsGeneratedTerrainBoardPositionsAndVariance();
tests.EncounterMonsterScalerDuplicatesAndScalesAllEncounterStats();

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
        baseStats.BasePhysAtk = 10f;
        baseStats.BasePhysDef = 20f;
        baseStats.BaseMagPower = 30f;
        baseStats.BaseMagResist = 40f;
        baseStats.BaseSpeed = 50f;

        var monster = CreateMonsterDataStub();
        monster.MonsterName = "Scaled";
        monster.MaxHealth = 100;
        monster.InitialAttributes = baseStats;

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
        Assert.Approximately(24f, scaledMonster.InitialAttributes.BasePhysAtk);
        Assert.Approximately(72f, scaledMonster.InitialAttributes.BasePhysDef);
        Assert.Approximately(144f, scaledMonster.InitialAttributes.BaseMagPower);
        Assert.Approximately(240f, scaledMonster.InitialAttributes.BaseMagResist);
        Assert.Approximately(30f, scaledMonster.InitialAttributes.BaseSpeed);
        Assert.Equal(100, monster.MaxHealth);
        Assert.Approximately(10f, baseStats.BasePhysAtk);
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

    private static StartingStats CreateStartingStatsStub()
    {
        return (StartingStats)RuntimeHelpers.GetUninitializedObject(typeof(StartingStats));
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

internal static class Assert
{
    public static void True(bool condition, string? message = null)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message ?? "Expected condition to be true.");
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
}
