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

    /// <summary>
    /// 扣除生命值并返回实际受到的伤害。
    /// </summary>
    /// <param name="amount">尝试造成的伤害量。</param>
    /// <param name="elementType">伤害五行属性。</param>
    /// <returns>返回受当前生命值限制后的实际扣血量。</returns>
    public int TakeDamage(int amount, ElementType elementType)
    {
        int actualDamage = Subtract(amount);

        if (actualDamage > 0)
        {
            EmitSignal(SignalName.DamageTaken, actualDamage, (int)elementType);
        }

        return actualDamage;
    }

}
