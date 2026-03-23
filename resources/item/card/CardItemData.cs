using Godot;
using CUSGA.resources.item;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class CardItemData : ItemData
{
	[Export] public Resource GDScriptCardData { get; set; }

	public CardItemData()
	{
		MaxStackSize = 1;
	}
}
