using Godot;
using CUSGA.resources.item;
namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class TerrainCardData : BaseCardData
{
	/// <summary>
	/// 获取或设置地形卡使用的交互资源。
	/// </summary>
	/// <remarks>
	/// 迁移期间同时接受 C# TerrainInteraction 与 GDScript Resource，具体执行
	/// 由 TerrainInteractionExecutor 按资源公开的操作协议分派。
	/// </remarks>
	[Export] public Resource InteractionBehavior { get; set; }
}
