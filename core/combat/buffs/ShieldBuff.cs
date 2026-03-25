using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.buffs;

public class ShieldBuff : StatusEffect
{
    public override StringName Id => new("Buff_GenericShield");

    public float ShieldAmount { get; set; }
    public override int InitRoundDuration { get; }

    public ShieldBuff(Node source, float amount, int roundDuration) : base(source)
    {
        ShieldAmount = amount;
        InitRoundDuration = roundDuration;
        RoundDuration = roundDuration;
    }

    public override void OnReceiveDamage(DamagePayload payload, ref float currentDamage)
    {
        if (currentDamage <= 0 || ShieldAmount <= 0) return;


        if (ShieldAmount >= currentDamage)
        {
            ShieldAmount -= currentDamage;
            currentDamage = 0;
        }
        else
        {
            currentDamage -= ShieldAmount;
            ShieldAmount = 0;
            Owner.GetNodeOrNull<StatusComponent>("%StatusComponent")?.RemoveStatus(Id);

        }
    }
}
