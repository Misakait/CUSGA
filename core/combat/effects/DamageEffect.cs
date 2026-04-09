using CUSGA.entities.components;
using CUSGA.core.constants;
using Godot;
namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class DamageEffect : CardEffect
{
    [Export] public int BaseDamage { get; set; } = 10;
    [Export] public DamageType Type { get; set; } = DamageType.Physical;
    [Export] public ElementType Element { get; set; } = ElementType.None;

    public override void Execute(Node source, Node target)
    {
        var payload = new DamagePayload { Source = source, Target = target, Damage = BaseDamage, Type = Type, Element = Element };
        // 受伤的代码我还没完全弄好，只是示例，不过以后应该差不多这样
        target.GetNodeOrNull<DamageReceiverComponent>("DamageReceiverComponent")?.ReceiveDamage(payload);
    }
}
