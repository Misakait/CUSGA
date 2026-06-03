using CUSGA.entities.components;
using CUSGA.core.constants;
using Godot;
using CUSGA.core.combat.skills;
using Godot.Collections;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class DamageEffect : CardEffect
{
    private readonly RandomNumberGenerator _targetRng = new();

    [Export] public int BaseDamage { get; set; } = 10;

    [Export] public int HitCount { get; set; } = 1;

    [Export]
    public DamageHitTargetMode HitTargetMode { get; set; }
        = DamageHitTargetMode.ContextTargets;

    [Export] public DamageType Type { get; set; } = DamageType.Physical;

    [Export] public ElementType Element { get; set; } = ElementType.None;
    [Export]
    public SkillEffectTargetScope TargetScope { get; set; }
            = SkillEffectTargetScope.PrimaryOnly;

    [Export] public float PrimaryDamageMultiplier { get; set; } = 1.0f;

    [Export] public float SecondaryDamageMultiplier { get; set; } = 1.0f;

    public DamageEffect()
    {
        _targetRng.Randomize();
    }

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(DamageEffect)} executed with null context.");
            return;
        }

        var effectiveHitCount = CalculateEffectiveHitCount(context);
        if (effectiveHitCount <= 0)
        {
            return;
        }

        if (HitTargetMode == DamageHitTargetMode.RandomCandidatePerHit)
        {
            ExecuteRandomCandidateHits(context, effectiveHitCount);
            return;
        }

        ExecuteContextTargetHits(context, effectiveHitCount);
    }

    private void ExecuteContextTargetHits(
        SkillExecutionContext context,
        int effectiveHitCount
    )
    {
        for (var hitIndex = 0; hitIndex < effectiveHitCount; hitIndex++)
        {
            foreach (var target in SkillEffectTargetScopeUtility.SelectTargets(context, TargetScope))
            {
                if (target.Unit == null)
                {
                    continue;
                }

                ApplyDamageToSelection(
                    context,
                    target,
                    hitIndex,
                    effectiveHitCount
                );
            }
        }
    }

    private void ExecuteRandomCandidateHits(
        SkillExecutionContext context,
        int effectiveHitCount
    )
    {
        for (var hitIndex = 0; hitIndex < effectiveHitCount; hitIndex++)
        {
            var candidates = SelectValidCandidates(context.CandidateTargets);
            if (candidates.Count == 0)
            {
                return;
            }

            var targetNode = candidates[_targetRng.RandiRange(0, candidates.Count - 1)];
            var selection = SkillEffectTargetSelection.FromTarget(
                new SkillTarget(targetNode, SkillTargetRole.Primary)
            );

            ApplyDamageToSelection(
                context,
                selection,
                hitIndex,
                effectiveHitCount
            );
        }
    }

    private int CalculateEffectiveHitCount(SkillExecutionContext context)
    {
        var hitCount = Mathf.Max(0, HitCount);
        var statusComponent = context.Source.GetStatusComponentOrNull();
        if (statusComponent == null)
        {
            return hitCount;
        }

        var hitCountContext = new DamageEffectHitCountContext(
            context.Source,
            context,
            this,
            hitCount
        );

        statusComponent.ProcessModifyDamageHitCount(hitCountContext, ref hitCount);
        return Mathf.Max(0, hitCount);
    }

    private void ApplyDamageToSelection(
        SkillExecutionContext context,
        SkillEffectTargetSelection target,
        int hitIndex,
        int effectiveHitCount
    )
    {
        var damage = CalculateDamageForTarget(target);
        var segmentContext = new DamageEffectSegmentContext(
            context.Source,
            context,
            this,
            target,
            hitIndex,
            effectiveHitCount
        );
        context.Source.GetStatusComponentOrNull()
            ?.ProcessModifyDamageEffectSegmentDamage(segmentContext, ref damage);
        damage = Mathf.Max(0, damage);

        ApplyDamageToNode(
            source: context.Source,
            target: target.Unit,
            damage: damage
        );
    }

    private int CalculateDamageForTarget(SkillEffectTargetSelection target)
    {
        float multiplier;

        if (target.IsSource)
        {
            multiplier = PrimaryDamageMultiplier;
        }
        else
        {
            multiplier = target.Role switch
            {
                SkillTargetRole.Primary => PrimaryDamageMultiplier,
                SkillTargetRole.Secondary => SecondaryDamageMultiplier,
                _ => 1.0f
            };
        }

        return Mathf.Max(0, Mathf.RoundToInt(BaseDamage * multiplier));
    }

    private static Array<Node> SelectValidCandidates(Array<Node> candidates)
    {
        var validCandidates = new Array<Node>();

        foreach (var candidate in candidates)
        {
            if (!IsValidDamageCandidate(candidate))
            {
                continue;
            }

            validCandidates.Add(candidate);
        }

        return validCandidates;
    }

    private static bool IsValidDamageCandidate(Node candidate)
    {
        if (candidate == null)
        {
            return false;
        }

        if (!IsInstanceValid(candidate) || candidate.IsQueuedForDeletion())
        {
            return false;
        }

        var health = candidate.GetNodeOrNull<HealthComponent>("Components/HealthComponent")
            ?? candidate.GetNodeOrNull<HealthComponent>("HealthComponent");

        return health is { CurrentValue: > 0 };
    }

    private void ApplyDamageToNode(Node source, Node target, int damage)
    {
        if (damage <= 0)
        {
            return;
        }

        var receiver = target.GetNodeOrNull<DamageReceiverComponent>(
            "Components/DamageReceiverComponent"
        );

        if (receiver == null)
        {
            GD.PushWarning($"Target '{target.Name}' has no DamageReceiverComponent.");
            return;
        }

        var payload = new DamagePayload
        {
            Source = source,
            Target = target,
            Damage = damage,
            Type = Type,
            Element = Element
        };

        receiver.ReceiveDamage(payload);

        GD.Print($"[伤害效果] {source.Name} 对 {target.Name} 造成 {damage} 点伤害，基础伤害：{BaseDamage}");
    }
}
