using Godot;
using CUSGA.entities;
namespace CUSGA.resources.talents;

[GlobalClass]
public partial class TagTalentEffect : TalentEffect
{
    [Export] public StringName TagToGrant { get; set; }

    public override void Apply(Player targetPlayer)
    {
        if (TagToGrant != null && !TagToGrant.IsEmpty)
        {
            targetPlayer.TagComponent.AddTag(TagToGrant);
            GD.Print($"玩家获得了特殊机制词条：{TagToGrant}");
        }
    }
}
