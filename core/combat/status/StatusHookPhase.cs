namespace CUSGA.core.combat.status;

public enum StatusHookPhase
{
    BeforeAttributeChange,
    AfterAttributeChanged,

    ModifyOutgoingDamage,
    ModifyIncomingDamageBeforeMitigation,
    ModifyIncomingDamageAfterMitigation,
    ModifyDamageHitCount,
    ModifyDamageEffectSegmentDamage,
    BeforeHealthDamage,

    BeforeSkillExecution,
    AfterSkillExecution,

    GlobalTurnStart,
    OwnerTurnStart,
    GlobalTurnEnd,
    OwnerTurnEnd,
    RoundStart,
    RoundEnd
}
