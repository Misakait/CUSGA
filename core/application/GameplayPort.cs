using System;
using Godot;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using Godot.Collections;

namespace CUSGA.core.application;

public partial class GameplayPort : Node
{
    [Signal] public delegate void InventoryToggleRequestedEventHandler(InventoryComponent inventory);
    /// <summary>
    /// 请求切换背包界面，并以通用节点传递 GDScript InventoryComponent。
    /// </summary>
    /// <param name="inventory">需要显示的玩家库存节点。</param>
    [Signal] public delegate void InventoryNodeToggleRequestedEventHandler(Node inventory);
    [Signal] public delegate void CraftingToggleRequestedEventHandler(CraftingComponent crafting);
    [Signal] public delegate void CraftingOpenRequestedEventHandler(CraftingComponent crafting);
    [Signal] public delegate void CraftingNodeToggleRequestedEventHandler(Node crafting);
    [Signal] public delegate void CraftingNodeOpenRequestedEventHandler(Node crafting);
    [Signal] public delegate void FarmingPanelRequestedEventHandler(TerrainInstance terrain);
    [Signal] public delegate void WarehouseRequestedEventHandler(InventoryComponent playerInventory, InventoryComponent warehouseInventory);
    [Signal] public delegate void WarehouseNodeRequestedEventHandler(Node playerInventory, Node warehouseInventory);
    [Signal]
    public delegate void EncounterRequestedEventHandler(
        TerrainInstance terrain,
        Array<Resource> battleDeck,
        Array<MonsterData> monsters,
        string message
    );

    [Export]
    public NodePath PlayerPath { get; set; } = null!;
    [Export] public NodePath PlayerInventoryPath { get; set; } = new("Components/InventoryComponent");
    [Export] public NodePath PlayerBattleDeckPath { get; set; } = new("Components/BattleDeckComponent");
    [Export] public NodePath PlayerHealthPath { get; set; } = new("Components/HealthComponent");
    [Export] public NodePath PlayerCraftingPath { get; set; } = new("Components/CraftingComponent");
    [Export] public NodePath GlobalWarehousePath { get; set; } = new("/root/GlobalWarehouse");

    private Player _player = null!;
    // 同时缓存通用节点与旧强类型实例，才能在不改变现有 C# 路径的前提下逐步切换库存实现。
    private Node _playerInventoryNode = null!;
    private InventoryComponent _playerInventory = null!;
    private HealthComponent _playerHealth = null!;
    private Node _playerBattleDeck = null!;
    private Node _playerCraftingNode = null!;
    private CraftingComponent _playerCrafting = null!;
    private Node _globalWarehouseNode = null!;
    private InventoryComponent _globalWarehouseInventory = null!;

    public HealthComponent PlayerHealth =>
           _playerHealth;
    public InventoryComponent PlayerInventory =>
            _playerInventory;
    /// <summary>
    /// 获取玩家库存的通用节点边界。
    /// </summary>
    /// <returns>玩家场景中的库存节点。</returns>
    public Node PlayerInventoryNode =>
            _playerInventoryNode;
    /// <summary>
    /// 获取玩家的出战卡组节点。
    /// </summary>
    /// <returns>实现稳定库存与技能卡展开协议的节点。</returns>
    public Node PlayerBattleDeck =>
            _playerBattleDeck;
    public CraftingComponent PlayerCrafting =>
            _playerCrafting;
    public Node PlayerCraftingNode =>
            _playerCraftingNode;
    public InventoryComponent GlobalWarehouseInventory =>
            _globalWarehouseInventory;
    public Node GlobalWarehouseNode =>
            _globalWarehouseNode;

    public override void _Ready()
    {
        if (PlayerPath.IsEmpty)
        {
            throw new InvalidOperationException("GameplayPort.PlayerPath 未设置");
        }

        _player = GetNode<Player>(PlayerPath);
        _playerInventoryNode = _player.GetNodeOrNull<Node>(PlayerInventoryPath);
        _playerInventory = _playerInventoryNode as InventoryComponent;
        _playerBattleDeck = _player.GetNode<Node>(PlayerBattleDeckPath);
        _playerHealth = _player.GetNode<HealthComponent>(PlayerHealthPath);
        _playerCraftingNode = _player.GetNodeOrNull<Node>(PlayerCraftingPath);
        _playerCrafting = _playerCraftingNode as CraftingComponent;
        _globalWarehouseNode = GetNodeOrNull<Node>(GlobalWarehousePath);
        _globalWarehouseInventory = _globalWarehouseNode as InventoryComponent;
    }

    public Player Player => _player;

    public void RequestToggleInventory()
    {
        if (PlayerInventory != null)
        {
            EmitSignal(SignalName.InventoryToggleRequested, PlayerInventory);
            return;
        }

        EmitSignal(SignalName.InventoryNodeToggleRequested, PlayerInventoryNode);
    }

    public void RequestToggleCrafting()
    {
        if (PlayerCrafting != null)
        {
            EmitSignal(SignalName.CraftingToggleRequested, PlayerCrafting);
            return;
        }

        EmitSignal(SignalName.CraftingNodeToggleRequested, PlayerCraftingNode);
    }

    /// <summary>
    /// 请求打开合成界面（幂等，不切换）。
    /// </summary>
    /// <remarks>
    /// 与 <see cref="RequestToggleCrafting"/> 并存而不是复用它，是因为两者语义不同：切换版服务于快捷键
    /// （再按一次即关闭），而背包标题栏的"合成"按钮期望点击后一定是打开。若复用切换版，当合成界面
    /// 已因快捷键处于可见状态时，玩家点"合成"反而会把它关掉。
    /// 两个界面都不持有对方，一律经本端口转发，从而保持背包与合成零耦合。
    /// </remarks>
    public void RequestOpenCrafting()
    {
        if (PlayerCrafting != null)
        {
            EmitSignal(SignalName.CraftingOpenRequested, PlayerCrafting);
            return;
        }

        EmitSignal(SignalName.CraftingNodeOpenRequested, PlayerCraftingNode);
    }

    public bool TryAddItemToInventory(ItemStack stack)
    {
        ArgumentNullException.ThrowIfNull(stack);
        return _player.TryAddItemToInventory(stack);
    }

    public void RequestOpenFarmingPanel(TerrainInstance terrain)
    {
        EmitSignal(SignalName.FarmingPanelRequested, terrain);
    }

    public void RequestOpenWarehouse()
    {
        if (GlobalWarehouseNode == null)
        {
            GD.PushError("GameplayPort 未绑定全局仓库节点。");
            return;
        }

        if (PlayerInventory != null && GlobalWarehouseInventory != null)
        {
            EmitSignal(SignalName.WarehouseRequested, PlayerInventory, GlobalWarehouseInventory);
            return;
        }

        // 任一库存使用 GDScript 时都无法转换为旧强类型，统一走 Node 边界保留同一打开流程。
        EmitSignal(SignalName.WarehouseNodeRequested, PlayerInventoryNode, GlobalWarehouseNode);
    }

    public void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message)
    {
        Array<MonsterData> monsters = [];
        if (monster != null)
        {
            monsters.Add(monster);
        }

        RequestEncounter(terrain, monsters, message);
    }

    public void RequestEncounter(TerrainInstance terrain, Array<MonsterData> monsters, string message)
    {
        Array<MonsterData> scaledMonsters = EncounterManager.Instance != null
            ? EncounterManager.Instance.ScaleEncounterMonsters(terrain, monsters ?? [])
            : monsters ?? [];

        GD.Print($"RequestEncounter: terrain={terrain}, monsters={scaledMonsters}, message={message}");
        EmitSignal(
            SignalName.EncounterRequested,
            terrain,
            GetPlayerSkillCards(),
            scaledMonsters,
            message ?? string.Empty
        );
    }

    /// <summary>
    /// 获取按堆叠数量展开的玩家技能卡，并过滤迁移期数组中的无效元素。
    /// </summary>
    /// <returns>保持原顺序和 Resource 身份的跨语言技能卡数组。</returns>
    public Array<Resource> GetPlayerSkillCards()
    {
        Array<Resource> cards = [];
        if (PlayerBattleDeck?.HasMethod("GetSkillCards") != true)
        {
            return cards;
        }

        Variant rawCards = PlayerBattleDeck.Call("GetSkillCards");
        if (rawCards.VariantType != Variant.Type.Array)
        {
            return cards;
        }

        foreach (Variant rawCard in rawCards.AsGodotArray())
        {
            if (rawCard.AsGodotObject() is Resource skillCard
                && skillCard.HasMethod("ApplyEffect"))
            {
                cards.Add(skillCard);
            }
        }

        return cards;
    }
}
