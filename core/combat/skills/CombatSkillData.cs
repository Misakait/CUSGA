using Godot;
using Godot.Collections;
using CUSGA.core.combat.effects;
using CUSGA.core.constants;
using CUSGA.entities.components;
using CUSGA.resources.item;

namespace CUSGA.core.combat.skills;

[GlobalClass]
public partial class CombatSkillData : BaseCardData
{
    [Export] public ElementType Element { get; set; } = ElementType.None;

    [Export] public SkillTargetingType TargetingType { get; set; } = SkillTargetingType.SingleEnemy;

    [Export] public Array<CardEffect> Effects { get; set; } = [];

    public bool RequiresTarget()
    {
        return TargetingType is not SkillTargetingType.Self
            and not SkillTargetingType.AllEnemies
            and not SkillTargetingType.AllUnits
            and not SkillTargetingType.RandomEnemy;

    }

    public void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(CombatSkillData)} '{CardId}' executed with null context.");
            return;
        }

        if (context.Targets.Count == 0)
        {
            GD.PushError($"{nameof(CombatSkillData)} '{CardId}' executed with empty targets.");
            return;
        }

        var statusComponent = context.Source.GetStatusComponentOrNull();
        var modifierContext = new SkillExecutionModifierContext(
            context.Source,
            this,
            context,
            HasDamageEffect()
        );

        statusComponent?.ProcessBeforeSkillExecution(modifierContext);

        try
        {
            foreach (var effect in Effects)
            {
                if (effect == null)
                {
                    continue;
                }

                effect.Execute(context);
            }
        }
        finally
        {
            statusComponent?.ProcessAfterSkillExecution(modifierContext);
        }
    }

    private bool HasDamageEffect()
    {
        foreach (var effect in Effects)
        {
            if (effect is DamageEffect)
            {
                return true;
            }
        }

        return false;
    }
}
