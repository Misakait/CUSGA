using CUSGA.core.constants;
using CUSGA.entities;
using Godot;

namespace CUSGA.core.combat;

public enum DamageType
{
    Physical,
    Magic,
    Real
}

public class DamagePayload
{
    public Node Source { get; set; }
    public Node Target { get; set; }
    public DamageType Type { get; set; }
    public int Damage { get; set; }
    public ElementType Element { get; set; }

    /// <summary>
    /// Controls default direct-damage modifiers: evasion, critical hits, random variance, and lifesteal.
    /// Status hooks, elemental multipliers, shields, damage caps, and health damage still run when disabled.
    /// </summary>
    public bool AppliesDefaultCombatModifiers { get; set; } = true;

    public bool IsExtraDamage { get; set; } = false;
}
