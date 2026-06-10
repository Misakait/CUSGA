using CUSGA.resources.item.equipment;
using Godot;

namespace CUSGA.resources.item.tool;

[GlobalClass]
public partial class ToolData : EquipmentData
{
    // 这个工具针对什么标签生效
    [Export] public StringName TargetGatheringTag { get; set; }

    // 多获得的个数
    [Export] public int YieldGrowth { get; set; } = 0;

    /// <summary>
    /// 获取或设置该工具为匹配采集标签减少的游戏时间点数。
    /// </summary>
    [Export(PropertyHint.Range, "0,999,1,or_greater")]
    public int GatheringTimeReduction { get; set; } = 0;
}
