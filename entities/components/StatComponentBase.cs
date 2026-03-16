using Godot;
using System;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class StatComponentBase : Node
{
    [Signal]
    public delegate void ValueChangedEventHandler(int currentValue, int maxValue);

    [Signal]
    public delegate void DepletedEventHandler(); // 归零时触发

    [Export]
    protected int _maxValue = 100;

    protected int _currentValue;

    public override void _Ready()
    {
        _currentValue = _maxValue;
    }

    public virtual void Add(int amount)
    {
        _currentValue = Mathf.Min(_currentValue + amount, _maxValue);
        EmitSignal(SignalName.ValueChanged, _currentValue, _maxValue);
    }

    public virtual void Subtract(int amount)
    {
        _currentValue = Mathf.Max(_currentValue - amount, 0);
        EmitSignal(SignalName.ValueChanged, _currentValue, _maxValue);

        if (_currentValue <= 0)
        {
            EmitSignal(SignalName.Depleted);
        }
    }
}
