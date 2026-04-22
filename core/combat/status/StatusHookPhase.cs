namespace CUSGA.core.combat.status;

public enum StatusHookPhase
{
    BeforeAttributeChange,
    AfterAttributeChanged,

    ModifyOutgoingDamage,
    ModifyIncomingDamageBeforeMitigation,
    ModifyIncomingDamageAfterMitigation,
    BeforeHealthDamage
}
