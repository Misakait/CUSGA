using CUSGA.core.attributes;
using CUSGA.core.combat;
using CUSGA.core.constants;
using Godot;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class DamageReceiverComponent : Node
{
    public void ReceiveDamage(DamagePayload payload)
    {
        Node defender = GetParent();

        if (defender == null)
        {
            GD.PushError($"{nameof(DamageReceiverComponent)} has no parent defender.");
            return;
        }

        var attackerStats = payload.Source?.GetNodeOrNull<AttributeComponent>("AttributeComponent");
        var defenderStats = defender.GetNodeOrNull<AttributeComponent>("AttributeComponent");

        var attackerStatus = payload.Source?.GetNodeOrNull<StatusComponent>("StatusComponent");
        var defenderStatus = defender.GetNodeOrNull<StatusComponent>("StatusComponent");

        float damage = Mathf.Max(0f, payload.Damage);

        ApplyAttackerAttributes(payload, attackerStats, ref damage);

        attackerStatus?.ProcessModifyOutgoingDamage(payload, ref damage);
        defenderStatus?.ProcessModifyIncomingDamageBeforeMitigation(payload, ref damage);

        ApplyElementMultiplier(payload, defender, ref damage);
        ApplyDefenseMitigation(payload, defenderStats, ref damage);

        defenderStatus?.ProcessModifyIncomingDamageAfterMitigation(payload, ref damage);
        defenderStatus?.ProcessBeforeHealthDamage(payload, ref damage);

        int finalDamage = Mathf.Max(0, Mathf.RoundToInt(damage));

        GD.Print(
            $"[Damage] Target: {defender.Name} | " +
            $"Source: {payload.Source?.Name ?? "Unknown"} | " +
            $"Damage: {finalDamage} | " +
            $"Element: {payload.Element} | " +
            $"Type: {payload.Type}"
        );

        defender.GetNodeOrNull<HealthComponent>("HealthComponent")
            ?.TakeDamage(finalDamage, payload.Element);
    }

    private static void ApplyAttackerAttributes(
        DamagePayload payload,
        AttributeComponent attackerStats,
        ref float damage
    )
    {
        if (attackerStats == null)
        {
            return;
        }

        switch (payload.Type)
        {
            case DamageType.Physical:
                {
                    damage += attackerStats.PhysAtk;
                    damage *= 1f + attackerStats.PhysDamageBoost;
                    break;
                }

            case DamageType.Magic:
                {
                    damage += attackerStats.MagPower;
                    damage *= 1f + attackerStats.MagicDamageBoost;
                    break;
                }

            case DamageType.Real:
                break;
        }

        damage = Mathf.Max(0f, damage);
    }

    private static void ApplyElementMultiplier(
        DamagePayload payload,
        Node defender,
        ref float damage
    )
    {
        ElementType targetElement = ElementType.None;

        if (defender is Monster monster)
        {
            targetElement = monster.BaseData.ElementalProperty;
        }

        float elementMultiplier = ElementalSystem.CalculateMultiplier(
            payload.Element,
            targetElement
        );

        damage *= elementMultiplier;
        damage = Mathf.Max(0f, damage);
    }

    private static void ApplyDefenseMitigation(
        DamagePayload payload,
        AttributeComponent defenderStats,
        ref float damage
    )
    {
        if (payload.Type == DamageType.Real)
        {
            return;
        }

        if (defenderStats == null)
        {
            return;
        }

        float defense = payload.Type switch
        {
            DamageType.Physical => defenderStats.PhysDef,
            DamageType.Magic => defenderStats.MagResist,
            _ => 0f
        };

        defense = Mathf.Max(0f, defense);

        float defenseMultiplier = 100f / (100f + defense);
        damage *= defenseMultiplier;
        damage = Mathf.Max(0f, damage);
    }
}
