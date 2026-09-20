using Godot;

namespace CUSGA.resources.interaction;

public sealed partial class WorldInteractionContext : RefCounted
{
    public required IInteractionGameplayPort Gameplay { get; init; }
    public required IInteractionBoardPort Board { get; init; }
    public required IInteractionEncounterPort Encounters { get; init; }

    /// <summary>
    /// 获取提供 PassTime 与时间属性协议的全局时间节点。
    /// </summary>
    public Node TimeSystem { get; init; }

    public required TerrainInstance Terrain { get; init; }
    public required Vector2 SourceGlobalPosition { get; init; }
}
