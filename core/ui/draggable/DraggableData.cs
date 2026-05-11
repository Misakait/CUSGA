using Godot;
using CUSGA.core.constants;
using CUSGA.core.inventory;
using CUSGA.entities.components;

namespace CUSGA.core.ui.draggable;

public partial class DraggableData : RefCounted
{
    // 这个快递数据包是从哪个系统来的
    public StringName SourceSystem { get; set; } = TagConsts.SystemInventory;

    // 起点格子的索引
    public int FromIndex { get; set; }

    // 起点所属的背包容器
    public InventoryComponent SourceInventory { get; set; }

    // 被拖拽的物品数据
    public ItemStack HeldStack { get; set; }
}
