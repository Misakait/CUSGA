using Godot;
using CUSGA.entities;
namespace CUSGA.resources.talents;

/// <summary>
/// 为玩家增加一层指定标签的天赋效果。
/// </summary>
[GlobalClass]
public partial class TagTalentEffect : TalentEffect
{
	/// <summary>
	/// 获取或设置天赋生效时赋予玩家的标签。
	/// </summary>
	[Export] public StringName TagToGrant { get; set; }

	/// <summary>
	/// 将配置的非空标签赋予目标玩家。
	/// </summary>
	/// <param name="targetPlayer">接收标签的玩家。</param>
	public override void Apply(Player targetPlayer)
	{
		if (TagToGrant != null && !TagToGrant.IsEmpty)
		{
			// 标签节点可能来自任一语言，通过稳定方法名避免天赋资源绑定具体实现类型。
			targetPlayer.TagComponent.Call("AddTag", TagToGrant);
			GD.Print($"玩家获得了特殊机制词条：{TagToGrant}");
		}
	}
}
