using System;
using CUSGA.core.autoloads;
using CUSGA.core.constants;
using CUSGA.entities;
using CUSGA.resources.loot;
using Godot;

namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class VaultInteraction : TerrainInteraction
{
    public override void Execute(Node cardNode, Player player)
    {
        // 火山密库
        TimeSystem.Instance.PassTime(TimeCost);
        var globalEventBus = cardNode.GetNode("/root/GlobalEventBus");
        globalEventBus.EmitSignal(GDSignals.OnEnteredVault);
    }
}
