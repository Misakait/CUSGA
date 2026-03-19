using Godot;
using CUSGA.core.attributes;

namespace CUSGA.resources.item.equipment;

[GlobalClass]
public partial class SetBonusTier : Resource
{
    // 激活套装效果需要的件数
    [Export] public int RequiredPieces { get; set; }

    // 激活后给的属性
    [Export] public Godot.Collections.Dictionary<AttributeType, float> AttributeBonuses { get; set; } = [];

    // 激活后给的标签
    [Export] public Godot.Collections.Array<StringName> GrantedTags { get; set; } = [];
}
