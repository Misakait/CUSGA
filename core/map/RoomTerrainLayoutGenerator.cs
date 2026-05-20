using System;
using System.Collections.Generic;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using Godot;

namespace CUSGA.core.map;

public sealed class TerrainSpawnPlacement(
    TerrainCardData terrainData,
    Vector2I localGridPos,
    Vector2 boardPosition,
    MonsterStatMultiplier encounterVarianceMultiplier)
{
    public TerrainCardData TerrainData { get; } =
        terrainData ?? throw new ArgumentNullException(nameof(terrainData));

    public Vector2I LocalGridPos { get; } = localGridPos;
    public Vector2 BoardPosition { get; } = boardPosition;
    public MonsterStatMultiplier EncounterVarianceMultiplier { get; } =
        encounterVarianceMultiplier ?? MonsterStatMultiplier.Identity;

    public TerrainSpawnPlacement(
        TerrainCardData terrainData,
        Vector2I localGridPos,
        Vector2 boardPosition)
        : this(terrainData, localGridPos, boardPosition, MonsterStatMultiplier.Identity)
    {
    }
}

public sealed class RoomTerrainLayoutGenerator(Random random)
{
    private readonly Random _random = random ?? throw new ArgumentNullException(nameof(random));

    public IReadOnlyList<TerrainSpawnPlacement> Generate(RoomTerrainProfile profile)
    {
        ArgumentNullException.ThrowIfNull(profile);

        if (profile.TerrainPool == null || profile.TerrainPool.Length == 0)
        {
            return [];
        }

        int gridColumns = Math.Max(profile.GridColumns, 1);
        int gridRows = Math.Max(profile.GridRows, 1);
        int availableSlots = gridColumns * gridRows;
        int minCount = Math.Clamp(profile.MinCount, 0, availableSlots);
        int maxCount = Math.Clamp(Math.Max(profile.MaxCount, minCount), minCount, availableSlots);
        int count = _random.Next(minCount, maxCount + 1);

        var cells = BuildCells(gridColumns, gridRows);
        Shuffle(cells);

        var placements = new List<TerrainSpawnPlacement>(count);
        for (int i = 0; i < count; i++)
        {
            RoomTerrainPoolEntry entry = ChooseTerrainEntry(profile);
            if (entry?.TerrainData == null)
            {
                continue;
            }

            Vector2I cell = cells[i];
            placements.Add(new TerrainSpawnPlacement(
                entry.TerrainData,
                cell,
                CellCenterToBoardPosition(
                    cell,
                    gridColumns,
                    gridRows,
                    profile.PlacementMin,
                    profile.PlacementMax
                ),
                RollMultiplier(profile.EncounterVarianceRange)
            ));
        }

        return placements;
    }

    /// <summary>
    /// 根据权重从地形池中随机选择一个地形条目。
    /// 权重越高的地形，被选中的概率越大。
    /// </summary>
    /// <param name="profile">包含地形池配置的地形配置文件</param>
    /// <returns>选中的地形条目。如果池为空或没有有效数据，则返回 null。</returns>
    private RoomTerrainPoolEntry ChooseTerrainEntry(RoomTerrainProfile profile)
    {
        // 计算所有有效地形的权重总和
        float totalWeight = 0f;
        foreach (RoomTerrainPoolEntry entry in profile.TerrainPool)
        {
            if (entry?.TerrainData == null)
            {
                continue;
            }

            totalWeight += Math.Max(entry.Weight, 0f);
        }


        // 边界情况处理（总权重小于等于 0）
        // 如果所有地形的权重都为 0，或者池子里没有有效地形
        if (totalWeight <= 0f)
        {
            // 直接返回池子里的第一个有效地形（不进行随机）
            foreach (RoomTerrainPoolEntry entry in profile.TerrainPool)
            {
                if (entry?.TerrainData != null)
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
        foreach (RoomTerrainPoolEntry entry in profile.TerrainPool)
        {
            if (entry?.TerrainData == null)
            {
                continue;
            }
            // 将当前地形的权重累加到“扇区”中
            accumulated += Math.Max(entry.Weight, 0f);
            // 如果随机数落在了当前累加权重的范围内，说明抽中了该地形
            if (roll <= accumulated)
            {
                return entry;
            }
        }

        return null;
    }

    private MonsterStatMultiplier RollMultiplier(MonsterStatMultiplierRange range)
    {
        if (range == null)
        {
            return MonsterStatMultiplier.Identity;
        }

        MonsterStatMultiplier min = range.Min;
        MonsterStatMultiplier max = range.Max;
        return new MonsterStatMultiplier
        {
            MaxHealth = RollFloat(min.MaxHealth, max.MaxHealth),
            PhysAtk = RollFloat(min.PhysAtk, max.PhysAtk),
            PhysDef = RollFloat(min.PhysDef, max.PhysDef),
            MagPower = RollFloat(min.MagPower, max.MagPower),
            MagResist = RollFloat(min.MagResist, max.MagResist),
            Speed = RollFloat(min.Speed, max.Speed)
        };
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
