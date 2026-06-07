using Godot;
using Godot.Collections;

namespace CUSGA.resources.map;

/// <summary>
/// 保存通道驻守系统的全局配置。
/// </summary>
[GlobalClass]
public partial class PassageGuardSettings : Resource
{
    /// <summary>
    /// 基础驻守概率，使用 0 到 1 的小数表示。
    /// </summary>
    [Export(PropertyHint.Range, "0,1,0.01")]
    public float BaseGuardChance { get; set; } = 0.3f;

    /// <summary>
    /// 拥有该标签时，入夜生成驻守表会跳过 home 相关通道。
    /// </summary>
    [Export] public StringName HomeProtectionTag { get; set; } = default;

    /// <summary>
    /// 由标签触发的概率修正列表。
    /// </summary>
    [Export] public Array<PassageGuardProbabilityModifier> ProbabilityModifiers { get; set; } = [];

    /// <summary>
    /// 当 map_attribute 未配置 guard_encounter_pool 时使用的默认驻守怪物池。
    /// 若两者均为空，则通道不会生成驻守战斗。
    /// </summary>
    [Export] public Array<PassageGuardEncounterData> DefaultGuardPool { get; set; } = [];
}
