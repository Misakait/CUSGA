using CUSGA.resources.encounters;
using Godot;

namespace CUSGA.resources.interaction;

/// <summary>
/// 表示房间内某一个地形卡实例的运行时状态。
/// </summary>
public partial class TerrainInstance : RefCounted
{
    /// <summary>
    /// 获取或设置地形在当前房间局部网格中的位置。
    /// </summary>
    public Vector2I LocalGridPos { get; set; }

    /// <summary>
    /// 获取或设置地形卡在棋盘上的显示位置。
    /// </summary>
    public Vector2 BoardPosition { get; set; }

    /// <summary>
    /// 获取或设置该地形触发遭遇时应用的怪物属性浮动倍率。
    /// </summary>
    public MonsterStatMultiplier EncounterVarianceMultiplier { get; set; } =
        MonsterStatMultiplier.Identity;

    /// <summary>
    /// 获取或设置该实例使用的地形配置资源。
    /// </summary>
    public TerrainCardData TerrainData { get; set; }

    /// <summary>
    /// 获取或设置该地形是否被其它玩法占用。
    /// </summary>
    public bool IsOccupied { get; set; }

    /// <summary>
    /// 获取或设置旧一次性采集点是否已经被采集。
    /// </summary>
    public bool IsHarvested { get; set; }

    /// <summary>
    /// 获取或设置农场等成长型地形的成长阶段。
    /// </summary>
    public int GrowthStage { get; set; }

    /// <summary>
    /// 获取或设置可重复采集资源当前剩余采集次数；-1 表示尚未按资源配置初始化。
    /// </summary>
    public int RemainingGatheringCount { get; set; } = -1;

    /// <summary>
    /// 获取或设置可重复采集资源下一次恢复可采集的游戏总时间；0 表示当前没有冷却。
    /// </summary>
    public int RefreshReadyTotalTime { get; set; }
}
