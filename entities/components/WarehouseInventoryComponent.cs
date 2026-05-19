using Godot;
using CUSGA.core.constants;

namespace CUSGA.entities.components;

public partial class WarehouseInventoryComponent : InventoryComponent
{
    public override StringName DragSourceSystem => TagConsts.SystemWarehouse;
}
