using System;
using Godot;
using CUSGA.core.board;
using CUSGA.entities;
using CUSGA.entities.components;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;
using Godot.Collections;

namespace CUSGA.core.gameflow;

public partial class WorldInteractionCoordinator : Node
{
    // GDScript 信号没有 C# 生成的 SignalName 常量，因此集中保存稳定协议名称。
    private static readonly StringName EncounterRequestedSignal = "EncounterRequested";
    private static readonly StringName TimeChangedSignal = "TimeChanged";

    [Signal] public delegate void PassageGuardEncounterFinishedEventHandler(bool isVictory);

    /// <summary>
    /// 当局外长按完成时通知 GDScript 地图拥有者执行其保留的业务流程。
    /// </summary>
    /// <param name="owner">完成本次长按的有效节点拥有者。</param>
    [Signal] public delegate void WorldHoldCompletedEventHandler(Node owner);

    [Export] public NodePath BoardControllerPath { get; set; } = null!;
    [Export] public NodePath GameplayPortPath { get; set; } = null!;
    [Export] public NodePath BackpackFlyTargetPath { get; set; } = null!;
    [Export] public NodePath EncounterManagerPath { get; set; } = null!;
    /// <summary>
    /// 指向统一管理局外长按输入与圆环反馈的子组件。
    /// </summary>
    [Export] public NodePath HoldInteractionControllerPath { get; set; } = new("WorldHoldInteractionController");
    public NodePath ScreenTransitionsPath { get; set; } = new("/root/ScreenTransitions");

    [ExportGroup("World View")]
    [Export] public NodePath WorldRootPath { get; set; } = new("../..");
    [Export] public NodePath MapSystemPath { get; set; } = new("../../MapSystem");
    [Export] public NodePath MapCanvasLayerPath { get; set; } = new("../../MapSystem/CanvasLayer");
    [Export] public NodePath HudLayerPath { get; set; } = new("../../UI/HUDLayer");

    // 遭遇管理器只依赖稳定的 Node 方法协议，兼容 C# 与 GDScript 实现。
    private Node _encounterManager;
    private WorldCombatScenePresenter _combatScenePresenter = null!;
    private TerrainInteractionExecutor _terrainInteractionExecutor = null!;
    private BoardController _boardController = null!;
    // GameplayPort 已切换为 GDScript；这里只依赖稳定的属性、方法和信号协议。
    private Node _gameplayPort = null!;
    // 保存同一个 Callable 实例，确保退出场景树时能准确解除 GDScript 信号连接。
    private Callable _encounterRequestedCallable;
    private Control _backpackFlyTarget;
    // 时间 Autoload 以稳定 Node 协议持有，兼容旧 C# 与生产 GDScript 实现。
    private Node _timeSystem;
    // 保存时间快照回调，保证退出场景树时解除的是同一个 Callable。
    private Callable _timeChangedCallable;
    // 统一处理地图按钮与棋盘地形之间互斥的长按状态。
    private Node _holdInteractionController = null!;

    public override void _Ready()
    {
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _gameplayPort = GetNode<Node>(GameplayPortPath);
        _backpackFlyTarget = GetNodeOrNull<Control>(BackpackFlyTargetPath);
        _encounterManager = GetNode<Node>(EncounterManagerPath);
        _timeSystem = GetNodeOrNull<Node>("/root/TimeSystem");
        Node screenTransitions = GetNodeOrNull<Node>(ScreenTransitionsPath);
        Node worldRoot = GetNode<Node>(WorldRootPath);
        Node mapSystem = GetNodeOrNull<Node>(MapSystemPath);
        var worldViewVisibility = new WorldViewVisibilityController(
            this,
            BoardControllerPath,
            MapSystemPath,
            MapCanvasLayerPath,
            HudLayerPath
        );
        _combatScenePresenter = new WorldCombatScenePresenter(
            worldRoot,
            mapSystem,
            new ScreenTransitionAdapter(this, screenTransitions),
            worldViewVisibility
        );
        _terrainInteractionExecutor = new TerrainInteractionExecutor(
            _gameplayPort,
            _boardController,
            _encounterManager,
            _timeSystem
        );
        _holdInteractionController = GetNode<Node>(HoldInteractionControllerPath);

        _boardController.CardClicked += OnBoardCardClicked;
        _boardController.CardPressed += OnBoardCardPressed;
        _boardController.CardReleased += OnBoardCardReleased;
        _boardController.CardSpawned += OnBoardCardSpawned;
        _encounterRequestedCallable = Callable.From<
            Variant,
            Variant,
            Variant,
            Variant
        >(OnEncounterRequested);
        if (!_gameplayPort.HasSignal(EncounterRequestedSignal))
        {
            GD.PushError("GameplayPort 缺少 EncounterRequested 信号，无法转发局外遭遇。");
        }
        else if (!_gameplayPort.IsConnected(EncounterRequestedSignal, _encounterRequestedCallable))
        {
            _gameplayPort.Connect(EncounterRequestedSignal, _encounterRequestedCallable);
        }

        _timeChangedCallable = Callable.From<int, int, bool, int, int>(OnTimeChanged);
        if (_timeSystem == null)
        {
            GD.PushError("WorldInteractionCoordinator 未找到 TimeSystem Autoload。");
        }
        else if (!_timeSystem.HasSignal(TimeChangedSignal))
        {
            GD.PushError("TimeSystem 缺少 TimeChanged 信号，无法刷新可重复采集状态。");
        }
        else if (!_timeSystem.IsConnected(TimeChangedSignal, _timeChangedCallable))
        {
            _timeSystem.Connect(TimeChangedSignal, _timeChangedCallable);
        }
    }

    public override void _ExitTree()
    {
        if (_boardController != null)
        {
            _boardController.CardClicked -= OnBoardCardClicked;
            _boardController.CardPressed -= OnBoardCardPressed;
            _boardController.CardReleased -= OnBoardCardReleased;
            _boardController.CardSpawned -= OnBoardCardSpawned;
        }
        if (_gameplayPort != null
            && _gameplayPort.IsConnected(EncounterRequestedSignal, _encounterRequestedCallable))
        {
            _gameplayPort.Disconnect(EncounterRequestedSignal, _encounterRequestedCallable);
        }
        if (_timeSystem != null
            && _timeSystem.HasSignal(TimeChangedSignal)
            && _timeSystem.IsConnected(TimeChangedSignal, _timeChangedCallable))
        {
            _timeSystem.Disconnect(TimeChangedSignal, _timeChangedCallable);
        }
        _holdInteractionController?.Call("cancel_active_hold");
    }

    /// <summary>
    /// 监听全局鼠标松开，确保拖出目标范围后也会取消局外长按。
    /// </summary>
    /// <param name="event">Godot 输入事件。</param>
    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton
            {
                ButtonIndex: MouseButton.Left,
                Pressed: false
            })
        {
            _holdInteractionController.Call("cancel_active_hold");
        }
    }

    private async void OnEncounterRequested(
        Variant terrain,
        Variant battleDeck,
        Variant monsters,
        Variant message)
    {
        // GDScript 信号参数先以 Variant 接收，再在此处集中验证数组元素，避免泛型数组隐式封送。
        Array<Resource> cards = battleDeck.VariantType == Variant.Type.Array
            ? ConvertSkillCards(battleDeck.AsGodotArray())
            : [];
        Array<MonsterData> encounterMonsters = monsters.VariantType == Variant.Type.Array
            ? ConvertMonsters(monsters.AsGodotArray())
            : [];
        await _combatScenePresenter.EnterCombatAsync(
            cards,
            encounterMonsters
        );
    }

    /// <summary>
    /// 为地图通道驻守怪物发起战斗，并在战斗结束后发出结果信号。
    /// </summary>
    /// <param name="monsters">通道驻守 encounter 配置出的怪物数组。</param>
    public async void RequestPassageGuardEncounter(Array<MonsterData> monsters)
    {
        GD.Print("RequestPassageGuardEncounter: monsters = ", monsters);
        bool isVictory = await _combatScenePresenter.EnterCombatAndWaitForResultAsync(
            GetPlayerSkillCards(),
            monsters ?? []
        );
        EmitSignal(SignalName.PassageGuardEncounterFinished, isVictory);
    }

    /// <summary>
    /// 为 GDScript GameplayPort 提供非泛型数组到 EncounterManager 强类型倍率入口的安全桥。
    /// </summary>
    /// <param name="terrain">本次遭遇所在的地形实例。</param>
    /// <param name="monsters">GDScript 传入的动态怪物数组。</param>
    /// <returns>按原顺序过滤输入后，由 EncounterManager 生成的缩放怪物数组。</returns>
    public Array<MonsterData> ScaleEncounterMonsters(
        TerrainInstance terrain,
        Godot.Collections.Array monsters)
    {
        Array<MonsterData> filteredMonsters = ConvertMonsters(monsters);
        if (_encounterManager == null || !_encounterManager.HasMethod("ScaleEncounterMonsters"))
        {
            return filteredMonsters;
        }

        Variant scaled = _encounterManager.Call("ScaleEncounterMonsters", terrain, filteredMonsters);
        return scaled.VariantType == Variant.Type.Array
            ? ConvertMonsters(scaled.AsGodotArray())
            : filteredMonsters;
    }

    /// <summary>
    /// 为 GDScript 地图控件开始一个局外长按，并在进度填满后以信号通知对应拥有者。
    /// </summary>
    /// <param name="owner">本次长按的地图节点拥有者。</param>
    /// <param name="actionPointCost">开始时快照的实际行动值消耗。</param>
    /// <param name="progressTarget">地图方向按钮中用于绘制圆环的可见目标节点。</param>
    public void BeginWorldHoldForMap(Node owner, int actionPointCost, Node progressTarget)
    {
        if (_holdInteractionController == null || !IsInstanceValid(_holdInteractionController))
        {
            GD.PushError("WorldInteractionCoordinator 未找到 WorldHoldInteractionController，无法开始局外长按。");
            return;
        }

        // 由 C# 创建回调可避免 GDScript Callable 经 Object.call 封送后退化为空实例。
        _holdInteractionController.Call(
            "begin_hold",
            owner,
            actionPointCost,
            Callable.From(() => EmitSignal(SignalName.WorldHoldCompleted, owner)),
            progressTarget
        );
    }

    /// <summary>
    /// 为 GDScript 地图控件取消指定拥有者的局外长按。
    /// </summary>
    /// <param name="owner">请求取消的地图或棋盘节点拥有者。</param>
    public void CancelWorldHoldFor(Node owner)
    {
        if (_holdInteractionController == null || !IsInstanceValid(_holdInteractionController))
        {
            return;
        }

        _holdInteractionController.Call("cancel_hold_for", owner);
    }

    private void OnBoardCardClicked(Node2D card)
    {
        ArgumentNullException.ThrowIfNull(card);

        RefCounted loot = card.Call("GetLootStackOrNull").AsGodotObject() as RefCounted;
        if (loot != null)
        {
            HandleLootCardClicked(card, loot);
            return;
        }

        TerrainInstance terrain = card.Call("GetTerrainInstanceOrNull").AsGodotObject() as TerrainInstance;
        if (terrain != null)
        {
            if (GetInteractionActionPointCost(GetTerrainInteraction(terrain)) > 0)
            {
                return;
            }

            HandleTerrainCardClicked(card, terrain);
        }
    }

    private void HandleLootCardClicked(Node2D card, RefCounted stack)
    {
        Variant addResult = _gameplayPort.Call("TryAddItemToInventory", stack);
        bool success = addResult.VariantType == Variant.Type.Bool && addResult.AsBool();
        if (!success)
        {
            return;
        }

        if (_backpackFlyTarget == null)
        {
            _boardController.RemoveCard(card);
            return;
        }

        Vector2 target = _backpackFlyTarget.GetGlobalRect().GetCenter();
        card.Call("PlayFlyTo", target, Callable.From(() => _boardController.RemoveCard(card)));
    }

    private void HandleTerrainCardClicked(Node2D card, TerrainInstance terrain)
    {
        _terrainInteractionExecutor.Execute(card, terrain);
    }

    private void OnBoardCardPressed(Node2D card)
    {
        if (TryGetHoldableTerrain(
                card,
                out TerrainInstance terrain,
                out Resource interaction,
                out int actionPointCost))
        {
            _holdInteractionController.Call(
                "begin_hold",
                card,
                actionPointCost,
                Callable.From(() => CompleteTerrainHold(card, terrain, interaction, actionPointCost)),
                card.GetNodeOrNull<Sprite2D>("Icon") as Node ?? card
            );
        }
    }

    private void OnBoardCardReleased(Node2D card)
    {
        _holdInteractionController.Call("cancel_hold_for", card);
    }

    private void OnBoardCardSpawned(Node2D card)
    {
        if (TryGetReusableGathering(card, out TerrainInstance terrain, out Resource interaction))
        {
            RefreshReusableGatheringCard(card, terrain, interaction, GetCurrentTotalTime());
        }
    }

    private void OnTimeChanged(
        int totalTimePassed,
        int currentDay,
        bool isNight,
        int phaseProgress,
        int phaseLength)
    {
        foreach (Node2D card in _boardController.GetActiveCardsSnapshot())
        {
            if (!IsInstanceValid(card)
                || !TryGetReusableGathering(card, out TerrainInstance terrain, out Resource interaction))
            {
                continue;
            }

            RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
        }
    }

    private bool TryGetHoldableTerrain(
        Node2D card,
        out TerrainInstance terrain,
        out Resource interaction,
        out int actionPointCost)
    {
        terrain = card?.Call("GetTerrainInstanceOrNull").AsGodotObject() as TerrainInstance;
        interaction = GetTerrainInteraction(terrain);
        actionPointCost = GetInteractionActionPointCost(interaction);
        if (terrain == null || interaction == null || actionPointCost <= 0)
        {
            return false;
        }

        if (!IsReusableGathering(interaction))
        {
            return true;
        }

        int totalTimePassed = GetCurrentTotalTime();
        RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
        return CanHarvest(interaction, terrain, totalTimePassed);
    }

    private void CompleteTerrainHold(
        Node2D card,
        TerrainInstance terrain,
        Resource interaction,
        int actionPointCost)
    {
        if (!IsInstanceValid(card)
            || card.Call("GetTerrainInstanceOrNull").AsGodotObject() != terrain)
        {
            return;
        }

        if (IsReusableGathering(interaction))
        {
            int totalTimePassed = GetCurrentTotalTime();
            if (!CanHarvest(interaction, terrain, totalTimePassed))
            {
                RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
                return;
            }
        }

        // 传回开始时快照的采集耗时，确保工具在长按中变化也不会改变已显示的等待成本。
        _terrainInteractionExecutor.Execute(card, terrain, actionPointCost);

        if (IsReusableGathering(interaction))
        {
            RefreshReusableGatheringCard(card, terrain, interaction, GetCurrentTotalTime());
        }
    }

    private int GetInteractionActionPointCost(Resource interaction)
    {
        if (IsReusableGathering(interaction))
        {
            return GetReusableEffectiveTimeCost(interaction, GetGameplayPlayer()?.Equipment);
        }

        if (interaction == null)
        {
            return 0;
        }

        Variant value = interaction.Get("TimeCost");
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? Math.Max(0, value.AsInt32())
            : 0;
    }

    private static bool TryGetReusableGathering(
        Node2D card,
        out TerrainInstance terrain,
        out Resource interaction)
    {
        terrain = card?.Call("GetTerrainInstanceOrNull").AsGodotObject() as TerrainInstance;
        interaction = GetTerrainInteraction(terrain);
        return terrain != null && IsReusableGathering(interaction);
    }

    private static void RefreshReusableGatheringCard(
        Node2D card,
        TerrainInstance terrain,
        Resource interaction,
        int totalTimePassed)
    {
        bool canHarvest = CanHarvest(interaction, terrain, totalTimePassed);
        card.Call("SetInteractionDisabled", !canHarvest);
    }

    /// <summary>
    /// 判断资源是否为旧 C# 或新 GDScript 可重复采集交互。
    /// </summary>
    /// <param name="interaction">地形交互资源。</param>
    /// <returns>资源实现了可重复采集 API 时返回 true。</returns>
    private static bool IsReusableGathering(Resource interaction)
    {
        return interaction is ReusableGatheringInteraction
            || interaction?.HasMethod("get_effective_time_cost") == true;
    }

    /// <summary>
    /// 调用两种语言实现的可重复采集有效耗时 API。
    /// </summary>
    /// <param name="interaction">可重复采集交互资源。</param>
    /// <param name="equipment">当前玩家装备组件。</param>
    /// <returns>输入开始时应使用的有效采集耗时。</returns>
    private static int GetReusableEffectiveTimeCost(Resource interaction, Node equipment)
    {
        if (interaction is ReusableGatheringInteraction reusable)
        {
            return reusable.GetEffectiveTimeCost(equipment);
        }

        return interaction.Call("get_effective_time_cost", equipment).AsInt32();
    }

    /// <summary>
    /// 调用两种语言实现的可重复采集可用性 API。
    /// </summary>
    /// <param name="interaction">可重复采集交互资源。</param>
    /// <param name="terrain">地形运行时实例。</param>
    /// <param name="totalTimePassed">当前游戏总时间点数。</param>
    /// <returns>资源仍可采集时返回 true。</returns>
    private static bool CanHarvest(Resource interaction, TerrainInstance terrain, int totalTimePassed)
    {
        if (interaction is ReusableGatheringInteraction reusable)
        {
            return reusable.CanHarvest(terrain, totalTimePassed);
        }

        return interaction.Call("can_harvest", terrain, totalTimePassed).AsBool();
    }

    private int GetCurrentTotalTime()
    {
        if (_timeSystem == null)
        {
            return 0;
        }

        Variant value = _timeSystem.Get("TotalTimePassed");
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? value.AsInt32()
            : 0;
    }

    /// <summary>
    /// 从 GDScript GameplayPort 读取当前玩家节点。
    /// </summary>
    /// <returns>生产玩家实例；属性缺失或类型不符时返回 null。</returns>
    private Player GetGameplayPlayer()
    {
        if (_gameplayPort == null)
        {
            return null;
        }

        return _gameplayPort.Get("Player").AsGodotObject() as Player;
    }

    /// <summary>
    /// 调用 GameplayPort 的稳定卡组方法，并显式过滤 GDScript 动态数组。
    /// </summary>
    /// <returns>保持顺序和 Resource 身份的技能卡数组。</returns>
    private Array<Resource> GetPlayerSkillCards()
    {
        if (_gameplayPort?.HasMethod("GetPlayerSkillCards") != true)
        {
            return [];
        }

        Variant rawCards = _gameplayPort.Call("GetPlayerSkillCards");
        return rawCards.VariantType == Variant.Type.Array
            ? ConvertSkillCards(rawCards.AsGodotArray())
            : [];
    }

    /// <summary>
    /// 将 GDScript 技能卡数组转换为战斗层要求的通用 Resource 数组。
    /// </summary>
    /// <param name="rawCards">GameplayPort 信号或方法返回的动态数组。</param>
    /// <returns>过滤无效元素后保持原顺序和 Resource 身份的数组。</returns>
    private static Array<Resource> ConvertSkillCards(Godot.Collections.Array rawCards)
    {
        Array<Resource> cards = [];
        foreach (Variant value in rawCards)
        {
            if (value.AsGodotObject() is Resource card
                && card.HasMethod("ApplyEffect"))
            {
                cards.Add(card);
            }
        }

        return cards;
    }

    /// <summary>
    /// 将 GDScript 怪物数组转换为战斗层要求的强类型数组。
    /// </summary>
    /// <param name="rawMonsters">GameplayPort 信号返回的动态数组。</param>
    /// <returns>过滤无效元素后保持原顺序和 Resource 身份的数组。</returns>
    private static Array<MonsterData> ConvertMonsters(Godot.Collections.Array rawMonsters)
    {
        Array<MonsterData> monsters = [];
        foreach (Variant value in rawMonsters)
        {
            if (value.AsGodotObject() is MonsterData monster)
            {
                monsters.Add(monster);
            }
        }

        return monsters;
    }

    /// <summary>
    /// 从地形卡的通用 Resource 字段读取交互资源，兼容旧 C# 与新 GDScript 数据。
    /// </summary>
    /// <param name="terrain">包含地形配置的运行时实例。</param>
    /// <returns>InteractionBehavior 资源；配置为空或字段缺失时返回 null。</returns>
    private static Resource GetTerrainInteraction(TerrainInstance terrain)
    {
        if (terrain?.TerrainData == null)
        {
            return null;
        }

        return terrain.TerrainData.Get("InteractionBehavior").AsGodotObject() as Resource;
    }
}
