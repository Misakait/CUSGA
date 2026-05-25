#nullable enable

using CUSGA.entities.components;
using CUSGA.resources.map;
using Godot;

namespace CUSGA.core.map;

/// <summary>
/// 计算入夜生成驻守通道表时使用的最终概率。
/// </summary>
[GlobalClass]
public partial class PassageGuardProbabilityProvider : RefCounted
{
    /// <summary>
    /// 根据全局配置和玩家标签计算最终驻守概率。
    /// </summary>
    /// <param name="settings">通道驻守全局配置；为空时返回 0。</param>
    /// <param name="tags">玩家标签组件；为空时只应用无标签要求的修正。</param>
    /// <returns>已限制在 0 到 1 之间的最终概率。</returns>
    public float Calculate(PassageGuardSettings settings, TagComponent? tags)
    {
        if (settings == null)
        {
            return 0f;
        }

        float additiveSum = 0f;
        float multiplierProduct = 1f;
        foreach (PassageGuardProbabilityModifier modifier in settings.ProbabilityModifiers)
        {
            if (modifier == null || !Applies(modifier, tags))
            {
                continue;
            }

            additiveSum += modifier.AdditiveChance;
            multiplierProduct *= modifier.Multiplier;
        }

        return Mathf.Clamp((settings.BaseGuardChance + additiveSum) * multiplierProduct, 0f, 1f);
    }

    private static bool Applies(PassageGuardProbabilityModifier modifier, TagComponent? tags)
    {
        return modifier.RequiredTag.IsEmpty || (tags != null && tags.HasTag(modifier.RequiredTag));
    }
}
