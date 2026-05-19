using Godot;
using CUSGA.core.inventory;
using CUSGA.resources.item;

namespace CUSGA.core.ui;

public sealed class ItemTooltipPresenter(Node tooltipPanel)
{
    public static ItemTooltipPresenter Empty { get; } = new(null);

    private readonly Node _tooltipPanel = tooltipPanel;

    public void Show(ItemStack stack)
    {
        if (stack == null || stack.IsEmpty)
        {
            Hide();
            return;
        }

        Show(stack.Item);
    }

    public void Show(ItemData item)
    {
        if (item == null)
        {
            Hide();
            return;
        }

        if (!HasTooltipPanel())
        {
            return;
        }

        _tooltipPanel.Call("show_tooltip", GetItemName(item), GetItemDescription(item));
    }

    public void Hide()
    {
        if (HasTooltipPanel())
        {
            _tooltipPanel.Call("hide_tooltip");
        }
    }

    private bool HasTooltipPanel()
    {
        return _tooltipPanel != null && GodotObject.IsInstanceValid(_tooltipPanel);
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
