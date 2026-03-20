using Godot;
using CUSGA.core.constants;
using CUSGA.core.inventory;

namespace CUSGA.core.ui.draggable;

public class DraggableData
{
    // 这个快递数据包是从哪个系统来的
    public StringName SourceSystem { get; set; } = TagConsts.SystemInventory;

    // 起点格子的索引
    public int FromIndex { get; set; }

    // 被拖拽的物品数据
    public ItemStack HeldStack { get; set; }
}
