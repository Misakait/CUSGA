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
        scaled.SkillSet = source.SkillSet;

        if (source.InitialAttributes != null)
        {
            scaled.InitialAttributes = ScaleStats(source.InitialAttributes, terrain, day);
        }

        return scaled;
    }

    private StartingStats ScaleStats(
        Resource source,
        MonsterStatMultiplier terrain,
        MonsterStatMultiplier day)
    {
        StartingStats scaled = _statsFactory();
        scaled.BasePhysAtk = ScaleFloat(ReadStat(source, "BasePhysAtk", 100f), terrain.PhysAtk, day.PhysAtk);
        scaled.PhysAtkGrowth = ReadStat(source, "PhysAtkGrowth", 25f);
        scaled.BasePhysDef = ScaleFloat(ReadStat(source, "BasePhysDef", 100f), terrain.PhysDef, day.PhysDef);
        scaled.PhysDefGrowth = ReadStat(source, "PhysDefGrowth", 20f);
        scaled.BaseMagPower = ScaleFloat(ReadStat(source, "BaseMagPower", 100f), terrain.MagPower, day.MagPower);
        scaled.MagPowerGrowth = ReadStat(source, "MagPowerGrowth", 30f);
        scaled.BaseMagResist = ScaleFloat(ReadStat(source, "BaseMagResist", 100f), terrain.MagResist, day.MagResist);
        scaled.MagResistGrowth = ReadStat(source, "MagResistGrowth", 20f);
        scaled.BaseSpeed = ScaleFloat(ReadStat(source, "BaseSpeed", 100f), terrain.Speed, day.Speed);
        scaled.SpeedGrowth = ReadStat(source, "SpeedGrowth", 5f);
        scaled.BaseMaxHealth = ScaleFloat(ReadStat(source, "BaseMaxHealth", 1000f), terrain.MaxHealth, day.MaxHealth);
        scaled.MaxHealthGrowth = ReadStat(source, "MaxHealthGrowth");
        scaled.BaseMaxEnergy = ReadStat(source, "BaseMaxEnergy", 100f);
        scaled.MaxEnergyGrowth = ReadStat(source, "MaxEnergyGrowth");
        scaled.BaseFixedPhysPenetration = ReadStat(source, "BaseFixedPhysPenetration");
        scaled.FixedPhysPenetrationGrowth = ReadStat(source, "FixedPhysPenetrationGrowth");
        scaled.BasePhysPenetrationRate = ReadStat(source, "BasePhysPenetrationRate");
        scaled.PhysPenetrationRateGrowth = ReadStat(source, "PhysPenetrationRateGrowth");
        scaled.BaseFixedMagicPenetration = ReadStat(source, "BaseFixedMagicPenetration");
        scaled.FixedMagicPenetrationGrowth = ReadStat(source, "FixedMagicPenetrationGrowth");
        scaled.BaseMagicPenetrationRate = ReadStat(source, "BaseMagicPenetrationRate");
        scaled.MagicPenetrationRateGrowth = ReadStat(source, "MagicPenetrationRateGrowth");
        scaled.BaseCritRate = ReadStat(source, "BaseCritRate");
        scaled.CritRateGrowth = ReadStat(source, "CritRateGrowth");
        scaled.BaseCritDamage = ReadStat(source, "BaseCritDamage", 1.5f);
        scaled.CritDamageGrowth = ReadStat(source, "CritDamageGrowth");
        scaled.BaseEvasionRate = ReadStat(source, "BaseEvasionRate");
        scaled.EvasionRateGrowth = ReadStat(source, "EvasionRateGrowth");
        scaled.BaseLifestealRate = ReadStat(source, "BaseLifestealRate");
        scaled.LifestealRateGrowth = ReadStat(source, "LifestealRateGrowth");
        return scaled;
    }

    /// <summary>
    /// 读取跨语言 StartingStats Resource 的浮点字段。
    /// </summary>
    /// <param name="source">旧 C# 或新 GDScript 属性资源。</param>
    /// <param name="propertyName">字段名。</param>
    /// <param name="fallback">字段不存在时沿用的旧默认值。</param>
    /// <returns>可用于缩放计算的浮点值。</returns>
    private static float ReadStat(Resource source, string propertyName, float fallback = 0f)
    {
        Variant value = source.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? (float)value.AsDouble()
            : fallback;
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

    private static float ScaleFloat(float value, float terrainMultiplier, float dayMultiplier)
    {
        return value * terrainMultiplier * dayMultiplier;
    }
}
