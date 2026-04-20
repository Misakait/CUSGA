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
        target.GetNodeOrNull<DamageReceiverComponent>("Components/DamageReceiverComponent")?.ReceiveDamage(payload);
        GD.Print($"[伤害效果] 对目标 {target.Name} 发起攻击，基础伤害：{BaseDamage}");
    }
}
