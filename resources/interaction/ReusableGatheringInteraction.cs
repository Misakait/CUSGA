using System;
using System.Collections.Generic;
using CUSGA.core.autoloads;
using CUSGA.core.constants;
using CUSGA.entities.components;
using CUSGA.resources.interaction.operations;
using CUSGA.resources.loot;
using Godot;

namespace CUSGA.resources.interaction;

/// <summary>
/// 表示可重复采集、按游戏时间冷却恢复的资源地形交互。
/// </summary>
[GlobalClass]
public partial class ReusableGatheringInteraction : TerrainInteraction
{
    /// <summary>
    /// 游戏时间点数到长按秒数的换算比例。
    /// </summary>
    public const float GameTimePointsPerHoldSecond = 10.0f;

    /// <summary>
    /// 获取或设置用于掉落和采集遭遇匹配的采集标签。
    /// </summary>
    [Export] public StringName GatheringTag { get; set; }

    /// <summary>
    /// 获取或设置采集完成后使用的掉落表。
    /// </summary>
    [Export] public LootTable DropTable { get; set; }

    /// <summary>
    /// 获取或设置每轮刷新后最多可采集的次数。
    /// </summary>
    [Export(PropertyHint.Range, "1,999,1,or_greater")]
    public int MaxHarvestCount { get; set; } = 1;

    /// <summary>
    /// 获取或设置采集耗尽后恢复所需的游戏时间点数。
    /// </summary>
    [Export(PropertyHint.Range, "0,9999,1,or_greater")]
    public int RefreshTimeCost { get; set; } = 100;

    /// <summary>
    /// 获取或设置工具减免后保留的最短采集游戏时间。
    /// </summary>
    [Export(PropertyHint.Range, "1,999,1,or_greater")]
    public int MinimumTimeCost { get; set; } = 1;

    /// <summary>
    /// 获取或设置该资源点只读取哪个装备槽的工具加成。
    /// </summary>
    [Export] public EquipmentSlot EffectiveToolSlot { get; set; } = EquipmentSlot.Axe;

    /// <summary>
    /// 根据已装备工具计算本次采集实际消耗的游戏时间。
    /// </summary>
    /// <param name="equipment">玩家当前装备组件；为空时不应用工具减免。</param>
    /// <returns>返回夹在最短时间以上的实际采集时间。</returns>
    public int GetEffectiveTimeCost(EquipmentComponent equipment)
    {
        int reduction = equipment?.GetGatheringTimeReduction(GatheringTag, EffectiveToolSlot) ?? 0;
        return Math.Max(GetMinimumTimeCost(), Math.Max(0, TimeCost) - reduction);
    }

    /// <summary>
    /// 根据已装备工具计算玩家需要长按的真实秒数。
    /// </summary>
    /// <param name="equipment">玩家当前装备组件；为空时不应用工具减免。</param>
    /// <returns>返回长按进度条需要运行的秒数。</returns>
    public float GetRequiredHoldSeconds(EquipmentComponent equipment)
    {
        return GetEffectiveTimeCost(equipment) / GameTimePointsPerHoldSecond;
    }

    /// <summary>
    /// 确保地形实例拥有可重复采集所需的运行时状态。
    /// </summary>
    /// <param name="terrain">要初始化的地形实例。</param>
    public void EnsureState(TerrainInstance terrain)
    {
        ArgumentNullException.ThrowIfNull(terrain);

        if (terrain.RemainingGatheringCount < 0)
        {
            terrain.RemainingGatheringCount = GetMaxHarvestCount();
            terrain.RefreshReadyTotalTime = 0;
        }
    }

    /// <summary>
    /// 如果冷却到期，恢复地形实例的可采集次数。
    /// </summary>
    /// <param name="terrain">要刷新的地形实例。</param>
    /// <param name="totalTimePassed">当前游戏总时间。</param>
    public void RefreshIfReady(TerrainInstance terrain, int totalTimePassed)
    {
        EnsureState(terrain);

        if (terrain.RemainingGatheringCount > 0 || terrain.RefreshReadyTotalTime <= 0)
        {
            return;
        }

        if (totalTimePassed < terrain.RefreshReadyTotalTime)
        {
            return;
        }

        terrain.RemainingGatheringCount = GetMaxHarvestCount();
        terrain.RefreshReadyTotalTime = 0;
    }

    /// <summary>
    /// 判断地形实例当前是否可以采集，并顺带刷新到期冷却。
    /// </summary>
    /// <param name="terrain">要检查的地形实例。</param>
    /// <param name="totalTimePassed">当前游戏总时间。</param>
    /// <returns>当前仍有可用采集次数时返回 true。</returns>
    public bool CanHarvest(TerrainInstance terrain, int totalTimePassed)
    {
        RefreshIfReady(terrain, totalTimePassed);
        return terrain.RemainingGatheringCount > 0;
    }

    /// <summary>
    /// 记录一次成功采集，并在次数耗尽时写入刷新到期时间。
    /// </summary>
    /// <param name="terrain">被采集的地形实例。</param>
    /// <param name="totalTimePassed">完成采集后的游戏总时间。</param>
    public void RecordSuccessfulHarvest(TerrainInstance terrain, int totalTimePassed)
    {
        EnsureState(terrain);

        if (terrain.RemainingGatheringCount <= 0)
        {
            return;
        }

        terrain.RemainingGatheringCount--;
        if (terrain.RemainingGatheringCount == 0)
        {
            terrain.RefreshReadyTotalTime = totalTimePassed + Math.Max(0, RefreshTimeCost);
        }
    }

    /// <summary>
    /// 构建可重复采集的运行时操作序列。
    /// </summary>
    /// <param name="context">采集交互构建上下文。</param>
    /// <returns>返回按顺序执行的采集操作。</returns>
    public override IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var ops = new List<TerrainOp>();
        if (!CanHarvest(context.Terrain, GetCurrentTotalTime()))
        {
            return ops;
        }

        EquipmentComponent equipment = context.Player?.Equipment;
        int effectiveTimeCost = GetBuildTimeCost(context, equipment);
        int extraYield = equipment?.GetGatheringYieldBonus(GatheringTag) ?? 0;
        var loots = DropTable?.RollLoot(extraYield) ?? [];

        ops.Add(new PassTimeOp(effectiveTimeCost));
        if (loots.Count > 0)
        {
            ops.Add(new SpawnLootOp(loots));
        }
        if (HasGatheringTag())
        {
            ops.Add(new CheckGatheringEncounterOp(GatheringTag));
        }
        ops.Add(new RecordReusableGatheringOp(this));

        return ops;
    }

    private int GetMaxHarvestCount()
    {
        return Math.Max(1, MaxHarvestCount);
    }

    private int GetMinimumTimeCost()
    {
        return Math.Max(1, MinimumTimeCost);
    }

    private int GetBuildTimeCost(
        TerrainInteractionBuildContext context,
        EquipmentComponent equipment)
    {
        if (context.EffectiveTimeCostOverride.HasValue)
        {
            return Math.Max(1, context.EffectiveTimeCostOverride.Value);
        }

        return GetEffectiveTimeCost(equipment);
    }

    private bool HasGatheringTag()
    {
        return GatheringTag != null && !GatheringTag.IsEmpty;
    }

    private static int GetCurrentTotalTime()
    {
        return TimeSystem.Instance?.TotalTimePassed ?? 0;
    }
}
