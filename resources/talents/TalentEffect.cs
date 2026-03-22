using Godot;
using CUSGA.entities;
namespace CUSGA.resources.talents;

[GlobalClass]
public abstract partial class TalentEffect : Resource
{
	public abstract void Apply(Player targetPlayer);
}
