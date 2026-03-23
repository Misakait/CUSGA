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
    public Player Source { get; set; }
    public DamageType Type { get; set; }
    public int Damage { get; set; }
    public ElementType Element { get; set; }
}
