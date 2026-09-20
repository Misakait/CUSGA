using Godot;

namespace CUSGA.resources.interaction.operations;

/// <summary>
/// 在可重复采集完成后扣减资源点剩余次数。
/// </summary>
public sealed partial class RecordReusableGatheringOp(ReusableGatheringInteraction interaction) : TerrainOp
{
    /// <summary>
    /// 获取要更新的可重复采集交互配置。
    /// </summary>
    public ReusableGatheringInteraction Interaction { get; } = interaction;

    /// <summary>
    /// 应用采集完成后的资源点状态变化。
    /// </summary>
    /// <param name="context">当前世界交互上下文。</param>
    public override void Apply(WorldInteractionContext context)
    {
        Interaction?.RecordSuccessfulHarvest(
            context.Terrain,
            ReadTotalTime(context.TimeSystem)
        );
    }

    private static int ReadTotalTime(Node timeSystem)
    {
        if (timeSystem == null)
        {
            return 0;
        }

        Variant value = timeSystem.Get("TotalTimePassed");
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? value.AsInt32()
            : 0;
    }
}
