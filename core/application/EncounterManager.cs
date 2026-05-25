using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;
using CUSGA.resources.encounters;
using CUSGA.core.autoloads;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;

namespace CUSGA.core.application;

public partial class EncounterManager : Node
{
    public static EncounterManager Instance { get; private set; } = null!;

    [Export] public Array<GatheringEncounterRule> GatheringRules { get; set; } = [];

    [Export] public float BaseGatheringSpawnChance { get; set; } = 0.05f;
    [Export] public float NightChanceMultiplier { get; set; } = 6.0f;

    [ExportGroup("Monster Daily Growth")]
    [Export] public float MaxHealthDailyGrowth { get; set; } = 0f;
    [Export] public float PhysAtkDailyGrowth { get; set; } = 0f;
    [Export] public float PhysDefDailyGrowth { get; set; } = 0f;
    [Export] public float MagPowerDailyGrowth { get; set; } = 0f;
    [Export] public float MagResistDailyGrowth { get; set; } = 0f;
    [Export] public float SpeedDailyGrowth { get; set; } = 0f;

    private readonly EncounterMonsterScaler _monsterScaler = new();

    public override void _Ready()
    {
        Instance = this;
    }

    /// <summary>
    /// 结算采集遭遇。
    /// </summary>
    /// <param name="resourceTag">本次采集资源对应的标签。</param>
    /// <returns>遭遇结果；未触发时返回空结果。</returns>
    public GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag)
    {
        return ResolveGatheringEncounter(resourceTag, 1.0f);
    }

    /// <summary>
    /// 结算采集遭遇，并允许装备系统在夜晚压低遭遇概率。
    /// </summary>
    /// <param name="resourceTag">本次采集资源对应的标签。</param>
    /// <param name="nightEncounterChanceMultiplier">夜晚装备遭遇概率乘数。</param>
    /// <returns>遭遇结果；未触发时返回空结果。</returns>
    public GatheringEncounterResult ResolveGatheringEncounter(
        StringName resourceTag,
        float nightEncounterChanceMultiplier)
    {
        if (resourceTag.IsEmpty)
        {
            return GatheringEncounterResult.None();
        }

        bool isNight = TimeSystem.Instance?.IsNight == true;
        float timeModifier = isNight ? NightChanceMultiplier : 1.0f;
        float equipmentModifier = isNight
            ? Mathf.Max(nightEncounterChanceMultiplier, 0.0f)
            : 1.0f;

        foreach (var rule in GatheringRules)
        {
            if (rule == null)
            {
                continue;
            }

            if (rule.TriggerTag != resourceTag)
            {
                continue;
            }

            float finalChance = BaseGatheringSpawnChance
                * timeModifier
                * equipmentModifier
                * Mathf.Max(rule.ExtraChanceMultiplier, 0.0f);
            // float finalChance = 1.0f;
            GD.Print($"Resolving gathering encounter for tag: {resourceTag}, finalChance: {finalChance}");
            if (GD.Randf() <= finalChance)
            {
                if (rule.MonsterToSpawn == null)
                {
                    return GatheringEncounterResult.None();
                }
                foreach (var monster in rule.MonsterToSpawn)
                {
                    GD.Print($"Gathering encounter triggered: {monster.MonsterName}");
                }
                return GatheringEncounterResult.Create(
                    rule.MonsterToSpawn,
                    rule.SpawnMessage
                );
            }
        }

        return GatheringEncounterResult.None();
    }

    public Array<MonsterData> ScaleEncounterMonsters(
        TerrainInstance terrain,
        Array<MonsterData> monsters)
    {
        MonsterStatMultiplier terrainVariance =
            terrain?.EncounterVarianceMultiplier ?? MonsterStatMultiplier.Identity;
        MonsterStatMultiplier perDayGrowth = BuildPerDayGrowthMultiplier();
        int currentDay = TimeSystem.Instance?.CurrentDay ?? 1;

        IReadOnlyList<MonsterData> scaled = _monsterScaler.ScaleMonsters(
            monsters,
            terrainVariance,
            perDayGrowth,
            currentDay
        );

        var result = new Array<MonsterData>();
        foreach (MonsterData monster in scaled)
        {
            result.Add(monster);
        }

        return result;
    }

    private MonsterStatMultiplier BuildPerDayGrowthMultiplier()
    {
        return new MonsterStatMultiplier
        {
            MaxHealth = MaxHealthDailyGrowth,
            PhysAtk = PhysAtkDailyGrowth,
            PhysDef = PhysDefDailyGrowth,
            MagPower = MagPowerDailyGrowth,
            MagResist = MagResistDailyGrowth,
            Speed = SpeedDailyGrowth
        };
    }
}
