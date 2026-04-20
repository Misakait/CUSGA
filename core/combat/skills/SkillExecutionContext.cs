using Godot;
using Godot.Collections;

namespace CUSGA.core.combat.skills;

public sealed partial class SkillExecutionContext(Node source, Array<SkillTarget> targets) : RefCounted
{
    public Node Source { get; } = source;
    public Array<SkillTarget> Targets { get; } = targets ?? [];

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

    public static SkillExecutionContext Self(Node source)
    {
        return new SkillExecutionContext(
            source,
            [
                new SkillTarget(source, SkillTargetRole.Primary)
            ]
        );
    }

    public static SkillExecutionContext FromSingleTarget(Node source, Node target)
    {
        var targets = new Array<SkillTarget>();

        if (target != null)
        {
            targets.Add(new SkillTarget(
                target,
                SkillTargetRole.Primary
            ));
        }

        return new SkillExecutionContext(source, targets);
    }

    public static SkillExecutionContext FromPrimaryTargets(
        Node source,
        Array<Node> targetNodes
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

        return new SkillExecutionContext(source, targets);
    }

    public static SkillExecutionContext FromSpread(
        Node source,
        Node primaryTarget,
        Array<Node> secondaryTargets
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

        return new SkillExecutionContext(source, targets);
    }
}
