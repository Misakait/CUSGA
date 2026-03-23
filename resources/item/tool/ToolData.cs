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
}
