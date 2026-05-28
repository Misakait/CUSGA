using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.status;

public sealed partial class ShieldStatusInstance(
    ShieldStatusData data,
    Node source,
    Node owner,
    float shieldAmount
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly ShieldStatusData _data = data;

    public override int GetHookPriority(StatusHookPhase phase)
    {
        return phase == StatusHookPhase.BeforeHealthDamage
            ? 100
            : base.GetHookPriority(phase);
    }

    /// <summary>
    /// 当前剩余可吸收的伤害量。
    /// </summary>
    public float ShieldAmount { get; private set; } = Mathf.Max(0f, shieldAmount);

    /// <summary>
    /// 获取护盾在 UI 悬停提示中显示的剩余吸收量描述。
    /// </summary>
    /// <returns>格式化后的剩余护盾说明。</returns>
    public override string DisplayDescription => $"抵挡{Mathf.RoundToInt(ShieldAmount)}点伤害";

    public override void OnBeforeHealthDamage(DamagePayload payload, ref float damage)
    {
        if (damage <= 0f)
        {
            return;
        }

        if (ShieldAmount <= 0f)
        {
            return;
        }

        float absorbed = Mathf.Min(ShieldAmount, damage);

        ShieldAmount -= absorbed;
        damage -= absorbed;

        if (ShieldAmount <= 0f)
        {
            Owner.GetStatusComponentOrNull()
                ?.RemoveStatus(Id);
        }
    }

    public override void OnReapplied(StatusEffectInstance incoming)
    {
        if (incoming is not ShieldStatusInstance shield)
        {
            return;
        }

        ShieldAmount += shield.ShieldAmount;
    }
}
