using Godot;
using System;
using CUSGA.core.interfaces;
using CUSGA.core.constants;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class HealthComponent : VitalComponentBase, IDamageable
{

    [Signal]
    public delegate void DamageTakenEventHandler(int amount, int elementType);

    public void TakeDamage(int amount, ElementType elementType)
    {
        if (CurrentValue <= 0) return;
        EmitSignal(SignalName.DamageTaken, amount, (int)elementType);
        Subtract(amount);
    }

}
