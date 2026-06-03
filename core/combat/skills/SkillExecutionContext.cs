using Godot;
using Godot.Collections;

namespace CUSGA.core.combat.skills;

public sealed partial class SkillExecutionContext(
    Node source,
    Array<SkillTarget> targets,
    Array<Node> candidateTargets = null
) : RefCounted
{
    public Node Source { get; } = source;
    public Array<SkillTarget> Targets { get; } = targets ?? [];
    public Array<Node> CandidateTargets { get; } = NormalizeCandidates(candidateTargets);

    public Node PrimaryTarget
    {
        get
        {
            foreach (var target in Targets)
            {
                if (target is { IsPrimary: true })
                    return target.Unit;
            }
            return Targets.Count > 0 ? Targets[0].Unit : null;
        }
    }

    /// <summary>
    /// 创建以施放者自身为目标的技能执行上下文。
    /// </summary>
    /// <param name="source">技能施放者。</param>
    /// <param name="candidateTargets">技能开始时锁定的随机候选目标池。</param>
    /// <returns>返回以施放者为主目标的技能上下文。</returns>
    public static SkillExecutionContext Self(
        Node source,
        Array<Node> candidateTargets = null
    )
    {
        return new SkillExecutionContext(
            source,
            [
                new SkillTarget(source, SkillTargetRole.Primary)
            ],
            candidateTargets
        );
    }

    /// <summary>
    /// 创建单目标技能执行上下文。
    /// </summary>
    /// <param name="source">技能施放者。</param>
    /// <param name="target">技能主目标。</param>
    /// <param name="candidateTargets">技能开始时锁定的随机候选目标池；为空时使用主目标作为候选。</param>
    /// <returns>返回包含单个主目标的技能上下文。</returns>
    public static SkillExecutionContext FromSingleTarget(
        Node source,
        Node target,
        Array<Node> candidateTargets = null
    )
    {
        var targets = new Array<SkillTarget>();

        if (target != null)
        {
            targets.Add(new SkillTarget(
                target,
                SkillTargetRole.Primary
            ));
        }

        return new SkillExecutionContext(
            source,
            targets,
            candidateTargets ?? TargetsToNodes(targets)
        );
    }

    /// <summary>
    /// 创建多个主目标技能执行上下文。
    /// </summary>
    /// <param name="source">技能施放者。</param>
    /// <param name="targetNodes">技能主目标集合。</param>
    /// <param name="candidateTargets">技能开始时锁定的随机候选目标池；为空时使用主目标集合作为候选。</param>
    /// <returns>返回包含多个主目标的技能上下文。</returns>
    public static SkillExecutionContext FromPrimaryTargets(
        Node source,
        Array<Node> targetNodes,
        Array<Node> candidateTargets = null
    )
    {
        var targets = new Array<SkillTarget>();

        foreach (var node in targetNodes)
        {
            if (node == null)
                continue;

            targets.Add(new SkillTarget(
                node,
                SkillTargetRole.Primary
            ));
        }

        return new SkillExecutionContext(
            source,
            targets,
            candidateTargets ?? TargetsToNodes(targets)
        );
    }

    /// <summary>
    /// 创建扩散技能执行上下文。
    /// </summary>
    /// <param name="source">技能施放者。</param>
    /// <param name="primaryTarget">扩散技能主目标。</param>
    /// <param name="secondaryTargets">扩散技能次目标集合。</param>
    /// <param name="candidateTargets">技能开始时锁定的随机候选目标池；为空时使用主次目标作为候选。</param>
    /// <returns>返回包含主目标和次目标的技能上下文。</returns>
    public static SkillExecutionContext FromSpread(
        Node source,
        Node primaryTarget,
        Array<Node> secondaryTargets,
        Array<Node> candidateTargets = null
    )
    {
        var targets = new Array<SkillTarget>();

        if (primaryTarget != null)
        {
            targets.Add(new SkillTarget(
                primaryTarget,
                SkillTargetRole.Primary
            ));
        }

        foreach (var secondary in secondaryTargets)
        {
            if (secondary == null)
                continue;

            if (secondary == primaryTarget)
                continue;

            targets.Add(new SkillTarget(
                secondary,
                SkillTargetRole.Secondary
            ));
        }

        return new SkillExecutionContext(
            source,
            targets,
            candidateTargets ?? TargetsToNodes(targets)
        );
    }

    private static Array<Node> NormalizeCandidates(Array<Node> candidateTargets)
    {
        var normalized = new Array<Node>();

        if (candidateTargets == null)
        {
            return normalized;
        }

        foreach (var target in candidateTargets)
        {
            if (target == null)
            {
                continue;
            }

            normalized.Add(target);
        }

        return normalized;
    }

    private static Array<Node> TargetsToNodes(Array<SkillTarget> targets)
    {
        var nodes = new Array<Node>();

        if (targets == null)
        {
            return nodes;
        }

        foreach (var target in targets)
        {
            if (target?.Unit == null)
            {
                continue;
            }

            nodes.Add(target.Unit);
        }

        return nodes;
    }
}
