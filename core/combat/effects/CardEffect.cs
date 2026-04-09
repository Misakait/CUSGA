using Godot;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public abstract partial class CardEffect : Resource
{
    public abstract void Execute(Node source, Node target);
}
