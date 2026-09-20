using System;
using System.Collections.Generic;
using CUSGA.resources.encounters;
using Godot;

namespace CUSGA.core.map;

public sealed class TerrainSpawnPlacement(
    Resource terrainData,
    Vector2I localGridPos,
    Vector2 boardPosition,
    MonsterStatMultiplier encounterVarianceMultiplier)
{
    public Resource TerrainData { get; } =
        terrainData ?? throw new ArgumentNullException(nameof(terrainData));

    public Vector2I LocalGridPos { get; } = localGridPos;
    public Vector2 BoardPosition { get; } = boardPosition;
    public MonsterStatMultiplier EncounterVarianceMultiplier { get; } =
        encounterVarianceMultiplier ?? MonsterStatMultiplier.Identity;

    public TerrainSpawnPlacement(
        Resource terrainData,
        Vector2I localGridPos,
        Vector2 boardPosition)
        : this(terrainData, localGridPos, boardPosition, MonsterStatMultiplier.Identity)
    {
    }
}

public sealed class RoomTerrainLayoutGenerator(Random random)
{
    private readonly Random _random = random ?? throw new ArgumentNullException(nameof(random));

    /// <summary>
    /// 根据旧 C# 地形配置生成布局，保留旧调用方的强类型入口。
    /// </summary>
    /// <param name="profile">旧 C# 地形配置。</param>
    /// <returns>按配置生成的地形摆放结果。</returns>
    public IReadOnlyList<TerrainSpawnPlacement> Generate(RoomTerrainProfile profile)
    {
        return Generate((Resource)profile);
    }

    /// <summary>
    /// 根据 C# 或 GDScript 地形配置生成布局。
    /// </summary>
    /// <param name="profile">包含稳定地形配置字段的 Resource。</param>
    /// <returns>按配置生成的地形摆放结果。</returns>
    public IReadOnlyList<TerrainSpawnPlacement> Generate(Resource profile)
    {
        ArgumentNullException.ThrowIfNull(profile);

        Godot.Collections.Array<Resource> terrainPool = ReadResourceArray(profile, "TerrainPool");
        if (terrainPool.Count == 0)
        {
            return [];
        }

        int gridColumns = Math.Max(ReadInt(profile, "GridColumns", 1), 1);
        int gridRows = Math.Max(ReadInt(profile, "GridRows", 1), 1);
        int availableSlots = gridColumns * gridRows;
        int minCount = Math.Clamp(ReadInt(profile, "MinCount", 0), 0, availableSlots);
        int maxCount = Math.Clamp(
            Math.Max(ReadInt(profile, "MaxCount", minCount), minCount),
            minCount,
            availableSlots
        );
        int count = _random.Next(minCount, maxCount + 1);

        Vector2 placementMin = ReadVector2(profile, "PlacementMin", Vector2.Zero);
        Vector2 placementMax = ReadVector2(profile, "PlacementMax", Vector2.Zero);
        Resource varianceRange = ReadResource(profile, "EncounterVarianceRange");

        var cells = BuildCells(gridColumns, gridRows);
        Shuffle(cells);

        var placements = new List<TerrainSpawnPlacement>(count);
        for (int i = 0; i < count; i++)
        {
            Resource entry = ChooseTerrainEntry(terrainPool);
            Resource terrainData = ReadTerrainData(entry);
            if (terrainData == null)
            {
                continue;
            }

            Vector2I cell = cells[i];
            placements.Add(new TerrainSpawnPlacement(
                terrainData,
                cell,
                CellCenterToBoardPosition(
                    cell,
                    gridColumns,
                    gridRows,
                    placementMin,
                    placementMax
                ),
                RollMultiplier(varianceRange)
            ));
        }

        return placements;
    }

    /// <summary>
    /// 根据权重从地形池中随机选择一个地形条目。
    /// 权重越高的地形，被选中的概率越大。
    /// </summary>
    /// <param name="terrainPool">包含候选地形条目的地形池。</param>
    /// <returns>选中的地形条目。如果池为空或没有有效数据，则返回 null。</returns>
    private Resource ChooseTerrainEntry(Godot.Collections.Array<Resource> terrainPool)
    {
        // 计算所有有效地形的权重总和
        float totalWeight = 0f;
        foreach (Resource entry in terrainPool)
        {
            if (ReadTerrainData(entry) == null)
            {
                continue;
            }

            totalWeight += Math.Max(ReadFloat(entry, "Weight", 1f), 0f);
        }


        // 边界情况处理（总权重小于等于 0）
        // 如果所有地形的权重都为 0，或者池子里没有有效地形
        if (totalWeight <= 0f)
        {
            // 直接返回池子里的第一个有效地形（不进行随机）
            foreach (Resource entry in terrainPool)
            {
                if (ReadTerrainData(entry) != null)
                {
                    return entry;
                }
            }
            // 如果连有效的地形都没有，只能返回 null
            return null;
        }


        // 轮盘赌算法进行带权随机抽取
        // 在 [0, totalWeight) 范围内掷一个随机数
        double roll = _random.NextDouble() * totalWeight;
        float accumulated = 0f;
        foreach (Resource entry in terrainPool)
        {
            if (ReadTerrainData(entry) == null)
            {
                continue;
            }
            // 将当前地形的权重累加到“扇区”中
            accumulated += Math.Max(ReadFloat(entry, "Weight", 1f), 0f);
            // 如果随机数落在了当前累加权重的范围内，说明抽中了该地形
            if (roll <= accumulated)
            {
                return entry;
            }
        }

        return null;
    }

    /// <summary>
    /// 从迁移中的 Resource 读取资源数组，并过滤掉非 Resource 元素。
    /// </summary>
    /// <param name="resource">待读取的配置资源。</param>
    /// <param name="propertyName">数组字段名称。</param>
    /// <returns>过滤后的 Resource 数组。</returns>
    private static Godot.Collections.Array<Resource> ReadResourceArray(
        Resource resource,
        string propertyName)
    {
        var resources = new Godot.Collections.Array<Resource>();
        Variant value = resource.Get(propertyName);
        if (value.VariantType != Variant.Type.Array)
        {
            return resources;
        }

        foreach (Variant item in value.AsGodotArray())
        {
            if (item.AsGodotObject() is Resource nestedResource)
            {
                resources.Add(nestedResource);
            }
        }

        return resources;
    }

    /// <summary>
    /// 从迁移中的 Resource 读取嵌套 Resource 字段。
    /// </summary>
    /// <param name="resource">待读取的配置资源。</param>
    /// <param name="propertyName">字段名称。</param>
    /// <returns>嵌套 Resource；字段缺失时返回 null。</returns>
    private static Resource ReadResource(Resource resource, string propertyName)
    {
        Variant value = resource.Get(propertyName);
        return value.AsGodotObject() as Resource;
    }

    /// <summary>
    /// 从迁移中的 Resource 读取整数配置。
    /// </summary>
    /// <param name="resource">待读取的配置资源。</param>
    /// <param name="propertyName">字段名称。</param>
    /// <param name="fallback">字段缺失或类型不匹配时的默认值。</param>
    /// <returns>转换后的整数配置。</returns>
    private static int ReadInt(Resource resource, string propertyName, int fallback)
    {
        Variant value = resource.Get(propertyName);
        return value.VariantType switch
        {
            Variant.Type.Int => value.AsInt32(),
            Variant.Type.Float => (int)value.AsSingle(),
            _ => fallback
        };
    }

    /// <summary>
    /// 从迁移中的 Resource 读取二维坐标配置。
    /// </summary>
    /// <param name="resource">待读取的配置资源。</param>
    /// <param name="propertyName">字段名称。</param>
    /// <param name="fallback">字段缺失或类型不匹配时的默认坐标。</param>
    /// <returns>资源中的二维坐标或默认值。</returns>
    private static Vector2 ReadVector2(Resource resource, string propertyName, Vector2 fallback)
    {
        Variant value = resource.Get(propertyName);
        return value.VariantType == Variant.Type.Vector2
            ? value.AsVector2()
            : fallback;
    }

    /// <summary>
    /// 从迁移中的地形池条目读取 TerrainData，兼容 C# 与 GDScript Resource。
    /// </summary>
    /// <param name="entry">待读取的地形池条目。</param>
    /// <returns>条目中的地形卡；字段缺失或类型不匹配时返回 null。</returns>
    private static Resource ReadTerrainData(Resource entry)
    {
        if (entry == null)
        {
            return null;
        }

        Variant value = entry.Get("TerrainData");
        return value.AsGodotObject() as Resource;
    }

    /// <summary>
    /// 从迁移中的 Resource 读取浮点配置，并在字段缺失时返回中性默认值。
    /// </summary>
    /// <param name="resource">待读取的资源。</param>
    /// <param name="propertyName">导出字段名称。</param>
    /// <param name="fallback">字段缺失或类型不匹配时使用的默认值。</param>
    /// <returns>资源中的浮点配置或默认值。</returns>
    private static float ReadFloat(Resource resource, string propertyName, float fallback)
    {
        if (resource == null)
        {
            return fallback;
        }

        Variant value = resource.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? (float)value.AsDouble()
            : fallback;
    }

    private MonsterStatMultiplier RollMultiplier(Resource range)
    {
        if (range == null)
        {
            return MonsterStatMultiplier.Identity;
        }

        return new MonsterStatMultiplier
        {
            MaxHealth = RollFloat(ReadMultiplier(range, "MinMaxHealth"), ReadMultiplier(range, "MaxMaxHealth")),
            PhysAtk = RollFloat(ReadMultiplier(range, "MinPhysAtk"), ReadMultiplier(range, "MaxPhysAtk")),
            PhysDef = RollFloat(ReadMultiplier(range, "MinPhysDef"), ReadMultiplier(range, "MaxPhysDef")),
            MagPower = RollFloat(ReadMultiplier(range, "MinMagPower"), ReadMultiplier(range, "MaxMagPower")),
            MagResist = RollFloat(ReadMultiplier(range, "MinMagResist"), ReadMultiplier(range, "MaxMagResist")),
            Speed = RollFloat(ReadMultiplier(range, "MinSpeed"), ReadMultiplier(range, "MaxSpeed"))
        };
    }

    /// <summary>
    /// 从迁移中的 Resource 读取一个倍率字段，并为旧资源或缺失字段提供中性默认值。
    /// </summary>
    /// <param name="range">倍率范围资源。</param>
    /// <param name="propertyName">导出字段名称。</param>
    /// <returns>可用于随机抽样的倍率；无法读取时返回 1。</returns>
    private static float ReadMultiplier(Resource range, string propertyName)
    {
        Variant value = range.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? (float)value.AsDouble()
            : 1f;
    }

    private float RollFloat(float min, float max)
    {
        if (max < min)
        {
            (min, max) = (max, min);
        }

        return min + (float)_random.NextDouble() * (max - min);
    }

    private static List<Vector2I> BuildCells(int gridColumns, int gridRows)
    {
        var cells = new List<Vector2I>(gridColumns * gridRows);
        for (int y = 0; y < gridRows; y++)
        {
            for (int x = 0; x < gridColumns; x++)
            {
                cells.Add(new Vector2I(x, y));
            }
        }

        return cells;
    }

    private void Shuffle<T>(IList<T> values)
    {
        for (int i = values.Count - 1; i > 0; i--)
        {
            int swapIndex = _random.Next(i + 1);
            (values[i], values[swapIndex]) = (values[swapIndex], values[i]);
        }
    }

    private static Vector2 CellCenterToBoardPosition(
        Vector2I cell,
        int gridColumns,
        int gridRows,
        Vector2 placementMin,
        Vector2 placementMax)
    {
        float xT = (cell.X + 0.5f) / gridColumns;
        float yT = (cell.Y + 0.5f) / gridRows;
        return new Vector2(
            Mathf.Lerp(placementMin.X, placementMax.X, xT),
            Mathf.Lerp(placementMin.Y, placementMax.Y, yT)
        );
    }
}
