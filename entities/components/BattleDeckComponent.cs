using Godot;
using Godot.Collections;
using CUSGA.core.constants;
using CUSGA.resources.item;
using CUSGA.resources.item.card;

namespace CUSGA.entities.components;

public partial class BattleDeckComponent : InventoryComponent
{
    public override StringName DragSourceSystem => TagConsts.SystemBattleDeck;

    protected override bool CanStoreItem(ItemData item)
    {
        return item is SkillCardData;
    }

    public Array<SkillCardData> GetSkillCards()
    {
        Array<SkillCardData> cards = [];

        foreach (var slot in Slots)
        {
            if (slot.IsEmpty || slot.Item is not SkillCardData skillCard)
            {
                continue;
            }

            for (int i = 0; i < slot.Amount; i++)
            {
                cards.Add(skillCard);
            }
        }

        return cards;
    }
}
