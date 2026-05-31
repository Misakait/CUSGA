using CUSGA.core.constants;
using System;

namespace CUSGA.core.combat;

/// <summary>
/// 提供独立于 Godot 场景树的伤害基础公式计算。
/// </summary>
public static class DamageFormula
{
    /// <summary>
    /// 根据技能威力、攻击者物攻、防御方物抗和物理穿透计算物理基础伤害。
    /// </summary>
    /// <param name="skillPower">技能威力，负数会按 0 处理。</param>
    /// <param name="attackerPhysAtk">攻击者有效物理攻击，负数会按 0 处理。</param>
    /// <param name="defenderPhysDef">防御方有效计算前的物理抗性，负数会按 0 处理。</param>
    /// <param name="physicalPenetrationRate">攻击者物理穿透率，取值会限制在 0 到 1。</param>
    /// <param name="fixedPhysicalPenetration">攻击者固定物理穿透，负数会按 0 处理。</param>
    /// <returns>返回套用物理攻防比值后的基础伤害。</returns>
    public static float CalculatePhysicalBaseDamage(
        float skillPower,
        float attackerPhysAtk,
        float defenderPhysDef,
        float physicalPenetrationRate,
        float fixedPhysicalPenetration = 0f
    )
    {
        float effectiveDefense = CalculateEffectiveResistance(
            defenderPhysDef,
            physicalPenetrationRate,
            fixedPhysicalPenetration
        );

        return CalculateBaseDamage(skillPower, attackerPhysAtk, effectiveDefense);
    }

    /// <summary>
    /// 根据技能威力、攻击者法强、防御方法抗和法术穿透计算法术基础伤害。
    /// </summary>
    /// <param name="skillPower">技能威力，负数会按 0 处理。</param>
    /// <param name="attackerMagPower">攻击者有效法术强度，负数会按 0 处理。</param>
    /// <param name="defenderMagResist">防御方有效计算前的法术抗性，负数会按 0 处理。</param>
    /// <param name="magicPenetrationRate">攻击者法术穿透率，取值会限制在 0 到 1。</param>
    /// <param name="fixedMagicPenetration">攻击者固定法术穿透，负数会按 0 处理。</param>
    /// <returns>返回套用法术攻防比值后的基础伤害。</returns>
    public static float CalculateMagicBaseDamage(
        float skillPower,
        float attackerMagPower,
        float defenderMagResist,
        float magicPenetrationRate,
        float fixedMagicPenetration = 0f
    )
    {
        float effectiveResistance = CalculateEffectiveResistance(
            defenderMagResist,
            magicPenetrationRate,
            fixedMagicPenetration
        );

        return CalculateBaseDamage(skillPower, attackerMagPower, effectiveResistance);
    }

    /// <summary>
    /// 根据原始抗性、百分比穿透和固定穿透计算参与伤害公式的有效抗性。
    /// </summary>
    /// <param name="rawResistance">防御方原始抗性，负数会按 0 处理。</param>
    /// <param name="penetrationRate">攻击者百分比穿透率，取值会限制在 0 到 1。</param>
    /// <param name="fixedPenetration">攻击者固定穿透，负数会按 0 处理。</param>
    /// <returns>返回不会低于 0 的有效抗性。</returns>
    public static float CalculateEffectiveResistance(
        float rawResistance,
        float penetrationRate,
        float fixedPenetration
    )
    {
        float normalizedResistance = Math.Max(0f, rawResistance);
        float normalizedRate = Math.Clamp(penetrationRate, 0f, 1f);
        float normalizedFixedPenetration = Math.Max(0f, fixedPenetration);

        return Math.Max(
            normalizedResistance * (1f - normalizedRate) - normalizedFixedPenetration,
            0f
        );
    }

    /// <summary>
    /// 根据闪避率和本次随机值判断是否闪避。
    /// </summary>
    /// <param name="evasionRate">闪避率，取值会限制在 0 到 1。</param>
    /// <param name="evasionRoll">本次随机值，取值会限制在 0 到 1。</param>
    /// <returns>触发闪避时返回 true。</returns>
    public static bool ShouldEvade(float evasionRate, float evasionRoll)
    {
        return Math.Clamp(evasionRoll, 0f, 1f) < Math.Clamp(evasionRate, 0f, 1f);
    }

    /// <summary>
    /// 根据暴击率和本次随机值判断是否暴击。
    /// </summary>
    /// <param name="critRate">暴击率，取值会限制在 0 到 1。</param>
    /// <param name="critRoll">本次随机值，取值会限制在 0 到 1。</param>
    /// <returns>触发暴击时返回 true。</returns>
    public static bool ShouldCrit(float critRate, float critRoll)
    {
        return Math.Clamp(critRoll, 0f, 1f) < Math.Clamp(critRate, 0f, 1f);
    }

    /// <summary>
    /// 计算本次伤害使用的暴击修正系数。
    /// </summary>
    /// <param name="isCritical">本次是否暴击。</param>
    /// <param name="critDamage">暴击伤害倍率，低于 1 时按 1 处理。</param>
    /// <returns>返回暴击或非暴击对应的倍率。</returns>
    public static float CalculateCriticalModifier(bool isCritical, float critDamage)
    {
        return isCritical
            ? Math.Max(1f, critDamage)
            : 1f;
    }

    /// <summary>
    /// 根据配置范围和本次随机值计算随机浮动系数。
    /// </summary>
    /// <param name="minimum">随机浮动下限。</param>
    /// <param name="maximum">随机浮动上限。</param>
    /// <param name="roll">本次随机值，取值会限制在 0 到 1。</param>
    /// <returns>返回线性插值后的随机浮动倍率。</returns>
    public static float CalculateRandomVariance(float minimum, float maximum, float roll)
    {
        float min = Math.Min(minimum, maximum);
        float max = Math.Max(minimum, maximum);
        float normalizedRoll = Math.Clamp(roll, 0f, 1f);

        return min + (max - min) * normalizedRoll;
    }

    /// <summary>
    /// 根据理论最终伤害和防御方当前生命计算实际扣血量。
    /// </summary>
    /// <param name="finalDamage">理论最终伤害。</param>
    /// <param name="defenderCurrentHealth">防御方当前生命值。</param>
    /// <returns>返回不会超过当前生命值的实际扣血量。</returns>
    public static int CalculateActualDamage(int finalDamage, int defenderCurrentHealth)
    {
        return Math.Min(
            Math.Max(0, finalDamage),
            Math.Max(0, defenderCurrentHealth)
        );
    }

    /// <summary>
    /// 根据实际伤害和吸血率计算恢复生命值。
    /// </summary>
    /// <param name="finalActualDamage">最终实际扣血量。</param>
    /// <param name="lifestealRate">吸血率，取值会限制在 0 到 1。</param>
    /// <returns>返回取整后的吸血治疗量。</returns>
    public static int CalculateLifestealAmount(int finalActualDamage, float lifestealRate)
    {
        float normalizedDamage = Math.Max(0, finalActualDamage);
        float normalizedRate = Math.Clamp(lifestealRate, 0f, 1f);

        return (int)MathF.Round(
            normalizedDamage * normalizedRate,
            MidpointRounding.AwayFromZero
        );
    }

    private static float CalculateBaseDamage(
        float skillPower,
        float attackerPower,
        float effectiveResistance
    )
    {
        float constant = CombatConstants.DamageFormulaConstant;

        return Math.Max(0f, skillPower)
            * (Math.Max(0f, attackerPower) + constant)
            / (Math.Max(0f, effectiveResistance) + constant);
    }
}
