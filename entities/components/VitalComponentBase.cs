using Godot;
using System;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class VitalComponentBase : Node
{
    [Signal]
    public delegate void ValueChangedEventHandler(int currentValue, int maxValue);

    [Signal]
    public delegate void DepletedEventHandler(); // 归零时触发

    [Export]
    public int MaxValue { get; protected set; } = 100;

    public int CurrentValue { get; protected set; }

    public override void _Ready()
    {
        CurrentValue = MaxValue;
    }

    public virtual void InitializeMax(int newMaxValue)
    {
        MaxValue = newMaxValue;
        CurrentValue = MaxValue;
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
    }

    public virtual void Add(int amount)
    {
        CurrentValue = Mathf.Min(CurrentValue + amount, MaxValue);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
    }

    public virtual void Subtract(int amount)
    {
        CurrentValue = Mathf.Max(CurrentValue - amount, 0);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);

        if (CurrentValue <= 0)
        {
            EmitSignal(SignalName.Depleted);
        }
    }
}
