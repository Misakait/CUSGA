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
    public bool IsExtraDamage { get; set; } = false;
}
