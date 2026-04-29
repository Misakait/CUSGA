using Godot;
using System;
using CUSGA.core.constants;
using CUSGA.entities.components;
using CUSGA.resources.talents;
using System.Collections.Generic;
using CUSGA.core.inventory;
namespace CUSGA.entities;

public partial class Player : Node
{

    private HealthComponent _health;
    private SatietyComponent _satiety;
    public EnergyComponent Energy { get; private set; }
    private AttributeComponent _attribute;
    private InventoryComponent _inventory;
    public EquipmentComponent Equipment { get; private set; }
    public StatusComponent Status { get; private set; }

    public TagComponent TagComponent { get; private set; }

    private Node _globalEventBus;

    public override void _Ready()
    {
        _health = GetNode<HealthComponent>("Components/HealthComponent");
        _satiety = GetNode<SatietyComponent>("Components/SatietyComponent");
        Energy = GetNode<EnergyComponent>("Components/EnergyComponent");
        Equipment = GetNode<EquipmentComponent>("Components/EquipmentComponent");
        _attribute = GetNode<AttributeComponent>("Components/AttributeComponent");
        TagComponent = GetNode<TagComponent>("Components/TagComponent");
        Status = GetNode<StatusComponent>("%StatusComponent");

        _satiety.Depleted += OnSatietyDepleted;
        _health.Depleted += OnPlayerDied;

        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        _globalEventBus.Connect(GDSignals.OnPlayerAcquiredTalent, Callable.From<TalentData>(AbsorbTalent));
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed("toggle_inventory"))
        {
            _globalEventBus.EmitSignal(GDSignals.OnInventoryToggled, _inventory);
        }
    }

    private void AbsorbTalent(TalentData newTalent)
    {
        GD.Print($"主角感受到神秘力量涌入：{newTalent.TalentName}！");
        if (newTalent.Effects != null)
        {
            foreach (TalentEffect effect in newTalent.Effects)
            {
                effect.Apply(this);
            }
        }
    }

    private void OnSatietyDepleted()
    {
        GD.Print("主角：我太饿了！开始掉血！");

        _health.TakeDamage(5, ElementType.None);
    }

    private void OnPlayerDied()
    {
        _globalEventBus.EmitSignal("player_died");
        GD.Print("主角死亡，游戏结束！");
    }

    public override void _ExitTree()
    {
        if (_satiety != null)
        {
            _satiety.Depleted -= OnSatietyDepleted;
        }

        if (_health != null)
        {
            _health.Depleted -= OnPlayerDied;
        }

        if (_globalEventBus != null)
        {
            _globalEventBus.Disconnect("on_player_acquired_talent", Callable.From<TalentData>(AbsorbTalent));
        }
    }

    public bool TryAddItemToInventory(ItemStack stack)
    {
        return _inventory.AddItem(stack.Item, stack.Amount) == 0;
    }
}
