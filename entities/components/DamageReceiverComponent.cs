using CUSGA.core.attributes;
using CUSGA.core.combat;
using CUSGA.core.constants;
using Godot;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class DamageReceiverComponent : Node
{
    private readonly RandomNumberGenerator _rng = new();

    [Export]
    public float RandomVarianceMin { get; set; } = 0.95f;

    [Export]
    public float RandomVarianceMax { get; set; } = 1.05f;

    public override void _Ready()
    {
        _rng.Randomize();
    }

    /// <summary>
    /// 接收伤害载荷，按战斗公式结算闪避、暴击、属性克制、随机浮动和吸血。
    /// </summary>
    /// <param name="payload">伤害来源、目标、技能威力、伤害类型和五行属性。</param>
    public void ReceiveDamage(DamagePayload payload)
    {
        Node defenderComponents = GetParent();
        Node defenderRoot = payload.Target ?? defenderComponents?.GetParent() ?? defenderComponents;

        if (defenderComponents == null)
        {
            GD.PushError($"{nameof(DamageReceiverComponent)} has no parent defender.");
            return;
        }

        var attackerStats = FindComponent<AttributeComponent>(payload.Source, "AttributeComponent");
        var defenderStats = FindComponent<AttributeComponent>(defenderRoot, "AttributeComponent")
            ?? defenderComponents.GetNodeOrNull<AttributeComponent>("AttributeComponent");

        var attackerStatus = FindComponent<StatusComponent>(payload.Source, "StatusComponent");
        var defenderStatus = FindComponent<StatusComponent>(defenderRoot, "StatusComponent")
            ?? defenderComponents.GetNodeOrNull<StatusComponent>("StatusComponent");

        if (
            payload.AppliesDefaultCombatModifiers &&
            DamageFormula.ShouldEvade(defenderStats?.EvasionRate ?? 0f, _rng.Randf())
        )
        {
            GD.Print(
                $"[Damage] Target: {defenderRoot?.Name ?? defenderComponents.Name} | " +
                $"Source: {payload.Source?.Name ?? "Unknown"} | " +
                "Damage: 0 | Evaded: True | " +
                $"Element: {payload.Element} | " +
                $"Type: {payload.Type}"
            );
            return;
        }

        float damage = CalculateBaseDamage(payload, attackerStats, defenderStats);
        bool isCritical = false;
        if (payload.AppliesDefaultCombatModifiers)
        {
            isCritical = DamageFormula.ShouldCrit(attackerStats?.CritRate ?? 0f, _rng.Randf());
            damage *= DamageFormula.CalculateCriticalModifier(isCritical, attackerStats?.CritDamage ?? 1f);
        }

        attackerStatus?.ProcessModifyOutgoingDamage(payload, ref damage);
        defenderStatus?.ProcessModifyIncomingDamageBeforeMitigation(payload, ref damage);

        ApplyElementMultiplier(payload, defenderRoot, ref damage);

        defenderStatus?.ProcessModifyIncomingDamageAfterMitigation(payload, ref damage);
        defenderStatus?.ProcessBeforeHealthDamage(payload, ref damage);
        if (payload.AppliesDefaultCombatModifiers)
        {
            ApplyRandomVariance(ref damage);
        }

        int finalDamage = Mathf.Max(0, Mathf.RoundToInt(damage));
        var defenderHealth = FindComponent<HealthComponent>(defenderRoot, "HealthComponent")
            ?? defenderComponents.GetNodeOrNull<HealthComponent>("HealthComponent");
        int actualDamage = defenderHealth?.TakeDamage(finalDamage, payload.Element) ?? 0;
        if (payload.AppliesDefaultCombatModifiers)
        {
            ApplyLifesteal(payload.Source, attackerStats, actualDamage);
        }

        GD.Print(
            $"[Damage] Target: {defenderRoot?.Name ?? defenderComponents.Name} | " +
            $"Source: {payload.Source?.Name ?? "Unknown"} | " +
            $"Damage: {actualDamage} | " +
            $"Critical: {isCritical} | " +
            $"Element: {payload.Element} | " +
            $"Type: {payload.Type}"
        );
    }

    private static float CalculateBaseDamage(
        DamagePayload payload,
        AttributeComponent attackerStats,
        AttributeComponent defenderStats
    )
    {
        float skillPower = Mathf.Max(0f, payload.Damage);

        return payload.Type switch
        {
            DamageType.Physical => DamageFormula.CalculatePhysicalBaseDamage(
                skillPower,
                attackerStats?.PhysAtk ?? 0f,
                defenderStats?.PhysDef ?? 0f,
                attackerStats?.PhysPenetrationRate ?? 0f,
                attackerStats?.FixedPhysPenetration ?? 0f
            ),
            DamageType.Magic => DamageFormula.CalculateMagicBaseDamage(
                skillPower,
                attackerStats?.MagPower ?? 0f,
                defenderStats?.MagResist ?? 0f,
                attackerStats?.MagicPenetrationRate ?? 0f,
                attackerStats?.FixedMagicPenetration ?? 0f
            ),
            // 真实伤害不走攻防比值，仍然保留后续状态和属性克制修正入口。
            DamageType.Real => skillPower,
            _ => skillPower
        };
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

    private void ApplyRandomVariance(ref float damage)
    {
        damage *= DamageFormula.CalculateRandomVariance(
            RandomVarianceMin,
            RandomVarianceMax,
            _rng.Randf()
        );
        damage = Mathf.Max(0f, damage);
    }

    private static void ApplyLifesteal(
        Node source,
        AttributeComponent attackerStats,
        int actualDamage
    )
    {
        int healAmount = DamageFormula.CalculateLifestealAmount(
            actualDamage,
            attackerStats?.LifestealRate ?? 0f
        );

        if (healAmount <= 0)
        {
            return;
        }

        FindComponent<HealthComponent>(source, "HealthComponent")
            ?.Add(healAmount);
    }

    private static T FindComponent<T>(Node owner, string componentName)
        where T : Node
    {
        if (owner == null)
        {
            return null;
        }

        return owner.GetNodeOrNull<T>(componentName)
            ?? owner.GetNodeOrNull<T>($"Components/{componentName}");
    }
}
