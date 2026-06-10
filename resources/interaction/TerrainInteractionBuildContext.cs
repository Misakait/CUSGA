using Godot;
using CUSGA.entities;

namespace CUSGA.resources.interaction;

/// <summary>
/// 表示地形交互构建操作序列时可读取的运行时上下文。
/// </summary>
public partial class TerrainInteractionBuildContext : RefCounted
{
    /// <summary>
    /// 获取当前触发地形交互的玩家。
    /// </summary>
    public required Player Player { get; init; }

    /// <summary>
    /// 获取当前被交互的地形实例。
    /// </summary>
    public required TerrainInstance Terrain { get; init; }

    /// <summary>
    /// 获取本次交互在输入开始时已经快照的有效采集游戏时间；为空时由交互资源现场计算。
    /// </summary>
    public int? EffectiveTimeCostOverride { get; init; }
}
