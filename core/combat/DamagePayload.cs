using CUSGA.core.constants;
using CUSGA.entities;
using System;
using Godot;

namespace CUSGA.core.combat;

/// <summary>
/// 控制伤害载荷会触发哪些直接攻击修饰。
/// </summary>
[Flags]
public enum DamageModifierFlags
{
    /// <summary>
    /// 不触发任何直接攻击修饰。
    /// </summary>
    None = 0,

    /// <summary>
    /// 允许目标使用闪避率完全规避本次伤害。
    /// </summary>
    Evasion = 1 << 0,

    /// <summary>
    /// 允许来源使用暴击率和暴击伤害倍率修正本次伤害。
    /// </summary>
    Critical = 1 << 1,

    /// <summary>
    /// 允许本次伤害在最终扣血前应用随机浮动。
    /// </summary>
    RandomVariance = 1 << 2,

    /// <summary>
    /// 允许来源根据实际造成伤害触发吸血。
    /// </summary>
    Lifesteal = 1 << 3,

    /// <summary>
    /// 普通直接攻击默认启用的修饰集合。
    /// </summary>
    DefaultCombat = Evasion | Critical | RandomVariance | Lifesteal
}

/// <summary>
/// 伤害基础公式类型。
/// </summary>
public enum DamageType
{
    /// <summary>
    /// 物理伤害，受物理攻击、防御和物理穿透影响。
    /// </summary>
    Physical,

    /// <summary>
    /// 法术伤害，受法术强度、抗性和法术穿透影响。
    /// </summary>
    Magic,

    /// <summary>
    /// 真实伤害，不经过基础攻防减免。
    /// </summary>
    Real
}

/// <summary>
/// 描述一次伤害结算所需的来源、目标、数值、属性与流程配置。
/// </summary>
public class DamagePayload
{
    /// <summary>
    /// 造成伤害的来源节点。
    /// </summary>
    public Node Source { get; set; }

    /// <summary>
    /// 接收伤害的目标节点。
    /// </summary>
    public Node Target { get; set; }

    /// <summary>
    /// 伤害类型，决定基础伤害是否经过物理、防御或真实伤害公式。
    /// </summary>
    public DamageType Type { get; set; }

    /// <summary>
    /// 伤害基础数值。
    /// </summary>
    public int Damage { get; set; }

    /// <summary>
    /// 伤害五行属性。
    /// </summary>
    public ElementType Element { get; set; }

    /// <summary>
    /// 本次伤害启用的直接攻击修饰集合。
    /// </summary>
    public DamageModifierFlags DamageModifiers { get; set; } = DamageModifierFlags.DefaultCombat;

    /// <summary>
    /// 标记本次伤害是否属于额外伤害。
    /// </summary>
    public bool IsExtraDamage { get; set; } = false;

    /// <summary>
    /// 判断本次伤害是否启用指定修饰。
    /// </summary>
    /// <param name="modifier">需要判断的伤害修饰。</param>
    /// <returns>启用该修饰时返回 true；否则返回 false。</returns>
    public bool HasDamageModifier(DamageModifierFlags modifier)
    {
        return modifier != DamageModifierFlags.None && (DamageModifiers & modifier) == modifier;
    }
}
