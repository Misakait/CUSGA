using Godot;
using CUSGA.core.inventory;
using CUSGA.resources.item;

namespace CUSGA.core.ui;

public static class ItemTooltipPresenter
{
    public static void Show(Node context, ItemStack stack)
    {
        if (stack == null || stack.IsEmpty)
        {
            Hide(context);
            return;
        }

        Show(context, stack.Item);
    }

    public static void Show(Node context, ItemData item)
    {
        if (item == null)
        {
            Hide(context);
            return;
        }

        Node tooltipPanel = GetTooltipPanel(context);
        tooltipPanel?.Call("show_tooltip", GetItemName(item), GetItemDescription(item));
    }

    public static void Hide(Node context)
    {
        Node tooltipPanel = GetTooltipPanel(context);
        tooltipPanel?.Call("hide_tooltip");
    }

    private static Node GetTooltipPanel(Node context)
    {
        if (context == null || !context.IsInsideTree())
        {
            return null;
        }

        var panels = context.GetTree().GetNodesInGroup("tooltip_panel");
        return panels.Count > 0 ? panels[0] : null;
    }

    private static string GetItemName(ItemData item)
    {
        if (!string.IsNullOrWhiteSpace(item.DisplayName))
        {
            return item.DisplayName;
        }

        return item.CardName ?? "";
    }

    private static string GetItemDescription(ItemData item)
    {
        if (!string.IsNullOrWhiteSpace(item.DisplayDescription))
        {
            return item.DisplayDescription;
        }

        return "暂无描述";
    }
}
