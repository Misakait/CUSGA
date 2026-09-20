using Godot;

namespace CUSGA.core.map;

[GlobalClass]
public partial class RoomTerrainProfile : Resource
{
    /// <summary>
    /// 当前房间可抽取的地形池；迁移期间允许 C# 与 GDScript 条目并存。
    /// </summary>
    [Export] public Godot.Collections.Array<Resource> TerrainPool { get; set; } = [];

    [Export] public int MinCount { get; set; } = 1;
    [Export] public int MaxCount { get; set; } = 3;
    [Export] public int GridColumns { get; set; } = 6;
    [Export] public int GridRows { get; set; } = 4;
    [Export] public Vector2 PlacementMin { get; set; } = new(360, 220);
    [Export] public Vector2 PlacementMax { get; set; } = new(920, 560);

    /// <summary>
    /// 遭遇怪物属性倍率范围资源；迁移期间允许 C# 与 GDScript 两种 Resource 实现。
    /// </summary>
    [Export] public Resource EncounterVarianceRange { get; set; }
}
