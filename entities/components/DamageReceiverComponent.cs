using Godot;
using CUSGA.core.attributes;
using CUSGA.core.combat;
using CUSGA.core.constants;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class DamageReceiverComponent : Node
{
    public void ReceiveDamage(DamagePayload payload)
    {
        var attackerStats = payload.Source?.GetNodeOrNull<AttributeComponent>("AttributeComponent");
        var defenderStats = GetParent().GetNodeOrNull<AttributeComponent>("AttributeComponent");

        var attackerStatus = payload.Source?.GetNodeOrNull<StatusComponent>("%StatusComponent");
        var defenderStatus = GetParent().GetNodeOrNull<StatusComponent>("%StatusComponent");

        float calculatedDamage = payload.Damage;

        // 攻击方增伤
        if (attackerStats != null)
        {
            if (payload.Type == DamageType.Physical)
            {
                float flatPhysPower = attackerStats.GetAttribute(AttributeType.PhysAtk)?.Value ?? 0f;
                calculatedDamage += flatPhysPower;

                float physBoostPct = attackerStats.GetAttribute(AttributeType.PhysDamageBoost)?.Value ?? 0f;
                calculatedDamage *= (1f + physBoostPct);
            }
            else if (payload.Type == DamageType.Magic)
            {
                float flatMagPower = attackerStats.GetAttribute(AttributeType.MagPower)?.Value ?? 0f;
                calculatedDamage += flatMagPower;

                float magicBoostPct = attackerStats.GetAttribute(AttributeType.MagicDamageBoost)?.Value ?? 0f;
                calculatedDamage *= (1f + magicBoostPct);
            }
        }

        // 元素反应区
        var targetElement = ElementType.None;
        if (GetParent() is Monster monster)
        {
            targetElement = monster.BaseData.ElementalProperty;
        }
        float elementMult = ElementalSystem.CalculateMultiplier(payload.Element, targetElement);
        calculatedDamage *= elementMult;

        // buff区
        if (attackerStatus != null)
        {
            foreach (var buff in attackerStatus.ActiveStatuses)
                buff.OnDealDamage(payload, ref calculatedDamage);
        }
        if (defenderStatus != null)
        {
            foreach (var buff in defenderStatus.ActiveStatuses)
                buff.OnReceiveDamage(payload, ref calculatedDamage);
        }

        // 防御抗性减伤区
        if (payload.Type != DamageType.Real && defenderStats != null)
        {
            float targetDefense = 0f;

            if (payload.Type == DamageType.Physical)
            {
                targetDefense = defenderStats.GetAttribute(AttributeType.PhysDef)?.Value ?? 0f;
            }
            else if (payload.Type == DamageType.Magic)
            {
                targetDefense = defenderStats.GetAttribute(AttributeType.MagResist)?.Value ?? 0f;
            }

            float finalDefense = Mathf.Max(0, targetDefense);
            float defenseMultiplier = 100f / (100f + finalDefense);
            calculatedDamage *= defenseMultiplier;
        }

        int finalDamageInt = Mathf.RoundToInt(calculatedDamage);
        GetParent().GetNodeOrNull<HealthComponent>("%HealthComponent")?.TakeDamage(finalDamageInt, payload.Element);
    }
}
