using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;

namespace CUSGA.core.application;

public partial class EncounterManager : Node
{
    public static EncounterManager Instance { get; private set; } = null!;

    /// <summary>
    /// 采集遭遇规则资源列表；使用通用 Resource 以兼容迁移中的 GDScript 规则。
    /// </summary>
    [Export] public Array<Resource> GatheringRules { get; set; } = [];

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

    /// <summary>
    /// 获取或设置提供昼夜与天数属性的时间节点；生产环境由 /root/TimeSystem 解析，测试可显式注入。
    /// </summary>
    public Node TimeSystemNode { get; set; }

    public override void _Ready()
    {
        Instance = this;
        TimeSystemNode ??= GetNodeOrNull<Node>("/root/TimeSystem");
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

        bool isNight = ReadBool(TimeSystemNode, "IsNight", false);
        float timeModifier = isNight ? NightChanceMultiplier : 1.0f;
        float equipmentModifier = isNight
            ? Mathf.Max(nightEncounterChanceMultiplier, 0.0f)
            : 1.0f;

        foreach (Resource rule in GatheringRules)
        {
            if (rule == null)
            {
                continue;
            }

            if (ReadStringName(rule, "TriggerTag") != resourceTag)
            {
                continue;
            }

            float finalChance = BaseGatheringSpawnChance
                * timeModifier
                * equipmentModifier
                * Mathf.Max(ReadFloat(rule, "ExtraChanceMultiplier", 1.0f), 0.0f);
            // float finalChance = 1.0f;
            GD.Print($"Resolving gathering encounter for tag: {resourceTag}, finalChance: {finalChance}");
            if (GD.Randf() <= finalChance)
            {
                Array<MonsterData> monsters = ReadMonsterArray(rule, "MonsterToSpawn");
                if (monsters.Count == 0)
                {
                    return GatheringEncounterResult.None();
                }
                foreach (MonsterData monster in monsters)
                {
                    GD.Print($"Gathering encounter triggered: {monster.MonsterName}");
                }
                return GatheringEncounterResult.Create(
                    monsters,
                    ReadString(rule, "SpawnMessage", string.Empty)
                );
            }
        }

        return GatheringEncounterResult.None();
    }

    /// <summary>
    /// 从规则 Resource 读取标签字段，兼容 StringName、String 和空值。
    /// </summary>
    /// <param name="rule">待读取的遭遇规则资源。</param>
    /// <param name="propertyName">属性名称。</param>
    /// <returns>规则标签；无法读取时返回空标签。</returns>
    private static StringName ReadStringName(Resource rule, string propertyName)
    {
        Variant value = rule.Get(propertyName);
        return value.VariantType switch
        {
            Variant.Type.StringName => value.AsStringName(),
            Variant.Type.String => new StringName(value.AsString()),
            _ => default
        };
    }

    /// <summary>
    /// 从规则 Resource 读取浮点倍率，缺失时返回指定默认值。
    /// </summary>
    /// <param name="rule">待读取的遭遇规则资源。</param>
    /// <param name="propertyName">属性名称。</param>
    /// <param name="fallback">属性不存在或类型不匹配时的默认值。</param>
    /// <returns>读取到的浮点倍率或默认值。</returns>
    private static float ReadFloat(Resource rule, string propertyName, float fallback)
    {
        Variant value = rule.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? (float)value.AsDouble()
            : fallback;
    }

    /// <summary>
    /// 从规则 Resource 读取提示文本，兼容旧 C# 与 GDScript 资源。
    /// </summary>
    /// <param name="rule">待读取的遭遇规则资源。</param>
    /// <param name="propertyName">属性名称。</param>
    /// <param name="fallback">属性不存在时的默认文本。</param>
    /// <returns>规则提示文本。</returns>
    private static string ReadString(Resource rule, string propertyName, string fallback)
    {
        Variant value = rule.Get(propertyName);
        return value.VariantType == Variant.Type.String ? value.AsString() : fallback;
    }

    /// <summary>
    /// 将规则中的非泛型怪物数组转换为遭遇结果需要的数组。
    /// </summary>
    /// <param name="rule">待读取的遭遇规则资源。</param>
    /// <param name="propertyName">怪物数组属性名称。</param>
    /// <returns>过滤掉空值和非 MonsterData 元素后的数组。</returns>
    private static Array<MonsterData> ReadMonsterArray(Resource rule, string propertyName)
    {
        Array<MonsterData> monsters = [];
        Variant value = rule.Get(propertyName);
        if (value.VariantType != Variant.Type.Array)
        {
            return monsters;
        }

        foreach (Variant item in value.AsGodotArray())
        {
            if (item.AsGodotObject() is MonsterData monster)
            {
                monsters.Add(monster);
            }
        }

        return monsters;
    }

    public Array<MonsterData> ScaleEncounterMonsters(
        TerrainInstance terrain,
        Array<MonsterData> monsters)
    {
        MonsterStatMultiplier terrainVariance =
            terrain?.EncounterVarianceMultiplier ?? MonsterStatMultiplier.Identity;
        MonsterStatMultiplier perDayGrowth = BuildPerDayGrowthMultiplier();
        int currentDay = ReadInt(TimeSystemNode, "CurrentDay", 1);

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

    private static bool ReadBool(Node source, StringName propertyName, bool fallback)
    {
        if (source == null)
        {
            return fallback;
        }

        Variant value = source.Get(propertyName);
        return value.VariantType == Variant.Type.Bool ? value.AsBool() : fallback;
    }

    private static int ReadInt(Node source, StringName propertyName, int fallback)
    {
        if (source == null)
        {
            return fallback;
        }

        Variant value = source.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? value.AsInt32()
            : fallback;
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
