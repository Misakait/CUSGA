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

    /// <summary>
    /// 初始化资源上限，并将当前值补满到新的上限。
    /// </summary>
    /// <param name="newMaxValue">新的资源上限。</param>
    public virtual void InitializeMax(int newMaxValue)
    {
        MaxValue = newMaxValue;
        CurrentValue = MaxValue;
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
    }

    /// <summary>
    /// 更新资源上限并保留当前值，只在当前值超出新上限时进行钳制。
    /// </summary>
    /// <param name="newMaxValue">新的资源上限，低于 1 时按 1 处理。</param>
    public virtual void SetMaxValuePreservingCurrent(int newMaxValue)
    {
        int normalizedMaxValue = Mathf.Max(1, newMaxValue);
        int oldMaxValue = MaxValue;
        int oldCurrentValue = CurrentValue;

        MaxValue = normalizedMaxValue;
        CurrentValue = Mathf.Clamp(CurrentValue, 0, MaxValue);

        if (oldMaxValue != MaxValue || oldCurrentValue != CurrentValue)
        {
            EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);
        }
    }

    /// <summary>
    /// 增加资源值并返回实际恢复量。
    /// </summary>
    /// <param name="amount">尝试增加的资源值。</param>
    /// <returns>返回受上限限制后的实际增加量。</returns>
    public virtual int Add(int amount)
    {
        if (amount <= 0 || CurrentValue >= MaxValue)
        {
            return 0;
        }

        int oldValue = CurrentValue;
        CurrentValue = Mathf.Min(CurrentValue + amount, MaxValue);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);

        return CurrentValue - oldValue;
    }

    /// <summary>
    /// 扣除资源值并返回实际扣除量。
    /// </summary>
    /// <param name="amount">尝试扣除的资源值。</param>
    /// <returns>返回受当前值限制后的实际扣除量。</returns>
    public virtual int Subtract(int amount)
    {
        if (amount <= 0 || CurrentValue <= 0)
        {
            return 0;
        }

        int oldValue = CurrentValue;
        CurrentValue = Mathf.Max(CurrentValue - amount, 0);
        EmitSignal(SignalName.ValueChanged, CurrentValue, MaxValue);

        if (CurrentValue <= 0)
        {
            EmitSignal(SignalName.Depleted);
        }

        return oldValue - CurrentValue;
    }
}
