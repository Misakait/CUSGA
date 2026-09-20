using Godot;
using System;
using CUSGA.core.constants;
using CUSGA.entities.components;
using System.Collections.Generic;
using CUSGA.core.inventory;
namespace CUSGA.entities;

public partial class Player : Node
{

    private HealthComponent _health;
    private SatietyComponent _satiety;
    public EnergyComponent Energy { get; private set; }
    public AttributeComponent Attributes { get; private set; }
    // 玩家库存只依赖稳定的节点方法协议，避免生产库存切换到 GDScript 后阻断 Player 初始化。
    private Node _inventory;
    /// <summary>
    /// 获取玩家的出战卡组组件节点。
    /// </summary>
    /// <remarks>
    /// 卡组通过稳定库存与 GetSkillCards 协议同时兼容 C# 和 GDScript 实现。
    /// </remarks>
    public Node BattleDeck { get; private set; }
    /// <summary>
    /// 获取玩家的装备组件节点。
    /// </summary>
    /// <remarks>
    /// 迁移期间通过稳定方法协议同时兼容 C# 与 GDScript 装备组件。
    /// </remarks>
    public Node Equipment { get; private set; }
    public StatusComponent Status { get; private set; }

    /// <summary>
    /// 获取玩家的标签组件节点。
    /// </summary>
    /// <remarks>
    /// 迁移期间通过稳定的 PascalCase 方法协议同时兼容 C# 与 GDScript 标签组件。
    /// </remarks>
    public Node TagComponent { get; private set; }

    private Node _globalEventBus;

    public override void _Ready()
    {
        _health = GetNode<HealthComponent>("Components/HealthComponent");
        _satiety = GetNode<SatietyComponent>("Components/SatietyComponent");
        Energy = GetNode<EnergyComponent>("Components/EnergyComponent");
        Equipment = GetNode<Node>("Components/EquipmentComponent");
        Attributes = GetNode<AttributeComponent>("Components/AttributeComponent");
        TagComponent = GetNode<Node>("Components/TagComponent");
        Status = GetNode<StatusComponent>("%StatusComponent");
        _inventory = GetNode<Node>("Components/InventoryComponent");
        BattleDeck = GetNode<Node>("Components/BattleDeckComponent");
        _satiety.Depleted += OnSatietyDepleted;
        _health.Depleted += OnPlayerDied;

        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        _globalEventBus.Connect(GDSignals.OnPlayerAcquiredTalent, Callable.From<Resource>(AbsorbTalent));
    }

    private void AbsorbTalent(Resource newTalent)
    {
        string talentName = newTalent.Get("TalentName").AsString();
        GD.Print($"主角感受到神秘力量涌入：{talentName}！");

        Variant effectsValue = newTalent.Get("Effects");
        if (effectsValue.VariantType != Variant.Type.Array)
        {
            return;
        }

        foreach (Variant effectValue in effectsValue.AsGodotArray())
        {
            if (effectValue.AsGodotObject() is Resource effect && effect.HasMethod("Apply"))
            {
                // 效果可能来自任一语言，通过稳定方法名保留同一个 Resource 实例。
                effect.Call("Apply", this);
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
            _globalEventBus.Disconnect("on_player_acquired_talent", Callable.From<Resource>(AbsorbTalent));
        }
    }

    /// <summary>
    /// 尝试把一个完整物品堆叠加入玩家库存。
    /// </summary>
    /// <param name="stack">通过 Item 与 Amount 属性提供数据的旧 C# 或 GDScript 物品堆叠。</param>
    /// <returns>库存完整接收堆叠时返回 <see langword="true"/>；容量不足时返回 <see langword="false"/>。</returns>
    public bool TryAddItemToInventory(RefCounted stack)
    {
        if (!ItemStackProtocol.TryRead(stack, out Resource item, out int amount))
        {
            return false;
        }

        // AddItem 的返回值是未放入数量；动态调用使同一路径兼容 C# 与 GDScript InventoryComponent。
        return _inventory.Call("AddItem", item, amount).AsInt32() == 0;
    }
}
