using System;
using System.Collections.Generic;
using CUSGA.resources.encounters;
using CUSGA.resources.monsters;
using CUSGA.resources.stats;
using Godot;

namespace CUSGA.core.application;

public sealed class EncounterMonsterScaler(Func<MonsterData> monsterFactory, Func<StartingStats> statsFactory)
{
    private readonly Func<MonsterData> _monsterFactory = monsterFactory ?? throw new ArgumentNullException(nameof(monsterFactory));
    private readonly Func<StartingStats> _statsFactory = statsFactory ?? throw new ArgumentNullException(nameof(statsFactory));

    public EncounterMonsterScaler()
        : this(static () => new MonsterData(), static () => new StartingStats())
    {
    }

    public IReadOnlyList<MonsterData> ScaleMonsters(
        IReadOnlyList<MonsterData> monsters,
        MonsterStatMultiplier terrainVariance,
        MonsterStatMultiplier perDayGrowth,
        int currentDay)
    {
        var scaledMonsters = new List<MonsterData>();
        if (monsters == null)
        {
            return scaledMonsters;
        }

        MonsterStatMultiplier terrain = terrainVariance ?? MonsterStatMultiplier.Identity;
        MonsterStatMultiplier day = BuildDayMultiplier(perDayGrowth, currentDay);

        foreach (MonsterData monster in monsters)
        {
            if (monster == null)
            {
                continue;
            }

            scaledMonsters.Add(ScaleMonster(monster, terrain, day));
        }

        return scaledMonsters;
    }

    private MonsterData ScaleMonster(
        MonsterData source,
        MonsterStatMultiplier terrain,
        MonsterStatMultiplier day)
    {
        MonsterData scaled = _monsterFactory();
        scaled.MonsterName = source.MonsterName;
        scaled.ElementalProperty = source.ElementalProperty;
        scaled.ModelScene = source.ModelScene;
        scaled.LootTable = source.LootTable;
        scaled.BehaviorTreeScene = source.BehaviorTreeScene;
        scaled.Faction = source.Faction;
        scaled.SkillCards = source.SkillCards;
        scaled.MaxHealth = ScaleInt(source.MaxHealth, terrain.MaxHealth, day.MaxHealth);

        if (source.InitialAttributes != null)
        {
            scaled.InitialAttributes = ScaleStats(source.InitialAttributes, terrain, day);
        }

        return scaled;
    }

    private StartingStats ScaleStats(
        StartingStats source,
        MonsterStatMultiplier terrain,
        MonsterStatMultiplier day)
    {
        StartingStats scaled = _statsFactory();
        scaled.BasePhysAtk = ScaleFloat(source.BasePhysAtk, terrain.PhysAtk, day.PhysAtk);
        scaled.PhysAtkGrowth = source.PhysAtkGrowth;
        scaled.BasePhysDef = ScaleFloat(source.BasePhysDef, terrain.PhysDef, day.PhysDef);
        scaled.PhysDefGrowth = source.PhysDefGrowth;
        scaled.BaseMagPower = ScaleFloat(source.BaseMagPower, terrain.MagPower, day.MagPower);
        scaled.MagPowerGrowth = source.MagPowerGrowth;
        scaled.BaseMagResist = ScaleFloat(source.BaseMagResist, terrain.MagResist, day.MagResist);
        scaled.MagResistGrowth = source.MagResistGrowth;
        scaled.BaseSpeed = ScaleFloat(source.BaseSpeed, terrain.Speed, day.Speed);
        scaled.SpeedGrowth = source.SpeedGrowth;
        return scaled;
    }

    private static MonsterStatMultiplier BuildDayMultiplier(
        MonsterStatMultiplier perDayGrowth,
        int currentDay)
    {
        MonsterStatMultiplier growth = perDayGrowth ?? new MonsterStatMultiplier
        {
            MaxHealth = 0f,
            PhysAtk = 0f,
            PhysDef = 0f,
            MagPower = 0f,
            MagResist = 0f,
            Speed = 0f
        };
        int elapsedDays = Math.Max(currentDay - 1, 0);

        return new MonsterStatMultiplier
        {
            MaxHealth = 1f + elapsedDays * growth.MaxHealth,
            PhysAtk = 1f + elapsedDays * growth.PhysAtk,
            PhysDef = 1f + elapsedDays * growth.PhysDef,
            MagPower = 1f + elapsedDays * growth.MagPower,
            MagResist = 1f + elapsedDays * growth.MagResist,
            Speed = 1f + elapsedDays * growth.Speed
        };
    }

    private static int ScaleInt(int value, float terrainMultiplier, float dayMultiplier)
    {
        return Mathf.Max(1, Mathf.RoundToInt(value * terrainMultiplier * dayMultiplier));
    }

    private static float ScaleFloat(float value, float terrainMultiplier, float dayMultiplier)
    {
        return value * terrainMultiplier * dayMultiplier;
    }
}
