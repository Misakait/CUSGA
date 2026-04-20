using CUSGA.core.combat.skills;
using Godot;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public abstract partial class CardEffect : Resource
{
    public abstract void Execute(SkillExecutionContext context);
}
