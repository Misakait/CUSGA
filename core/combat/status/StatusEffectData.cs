using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public abstract partial class StatusEffectData : Resource
{
    [Export] public StringName Id { get; set; }
    [Export] public int MaxStacks { get; set; } = 1;
    [Export] public StackPolicy Policy { get; set; } = StackPolicy.ResetDuration;

    [Export] public DurationExpirePolicy ExpirePolicy { get; set; } = DurationExpirePolicy.FirstExpired;

    /// <summary>
    /// 同一 hook phase 内的默认执行优先级。
    /// 数值越小越早执行。
    /// </summary>
    [Export] public int DefaultHookPriority { get; set; } = 0;

    // 持续该单位自己的 N 次行动
    [Export] public int InitOwnerTurnDuration { get; set; } = 0;

    // 持续全场 N 次行动，不管是谁行动
    [Export] public int InitGlobalTurnDuration { get; set; } = 0;

    // 所有存活单位都至少行动过一次，算一轮
    [Export] public int InitRoundDuration { get; set; } = 0;

    public bool HasFiniteDuration =>
        InitOwnerTurnDuration > 0 ||
        InitGlobalTurnDuration > 0 ||
        InitRoundDuration > 0;

    public abstract StatusEffectInstance CreateInstance(Node source, Node owner);
}
