namespace CUSGA.core.constants;

/// <summary>
/// 提供战斗数值公式共享常数，避免不同伤害分支使用不一致的基准值。
/// </summary>
public static class CombatConstants
{
    /// <summary>
    /// 伤害公式中的全局常数 C，同时用于攻击侧分子和防御侧分母。
    /// </summary>
    public const float DamageFormulaConstant = 100f;
}
