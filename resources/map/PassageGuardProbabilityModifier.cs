using Godot;

namespace CUSGA.resources.map;

/// <summary>
/// 描述一个由玩家标签触发的通道驻守概率修正。
/// </summary>
[GlobalClass]
public partial class PassageGuardProbabilityModifier : Resource
{
    /// <summary>
    /// 触发该修正所需的标签；为空时表示始终生效。
    /// </summary>
    [Export] public StringName RequiredTag { get; set; } = default;

    /// <summary>
    /// 固定概率点修正值，使用 0 到 1 的小数表示。
    /// </summary>
    [Export(PropertyHint.Range, "-1,1,0.01")]
    public float AdditiveChance { get; set; }

    /// <summary>
    /// 乘法倍率修正值。
    /// </summary>
    [Export(PropertyHint.Range, "0,10,0.01")]
    public float Multiplier { get; set; } = 1f;
}
