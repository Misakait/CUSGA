using System;
using Godot;
using CUSGA.core.autoloads;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.core.application;
using CUSGA.resources.item.card;
using CUSGA.resources.monsters;
using Godot.Collections;

namespace CUSGA.core.gameflow;

public partial class WorldInteractionCoordinator : Node
{
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

    private EncounterManager _encounterManager;
    private WorldCombatScenePresenter _combatScenePresenter = null!;
    private TerrainInteractionExecutor _terrainInteractionExecutor = null!;
    private BoardController _boardController = null!;
    private GameplayPort _gameplayPort = null!;
    private Control _backpackFlyTarget;
    private TimeSystem _timeSystem;
    // 统一处理地图按钮与棋盘地形之间互斥的长按状态。
    private WorldHoldInteractionController _holdInteractionController = null!;

    public override void _Ready()
    {
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _backpackFlyTarget = GetNodeOrNull<Control>(BackpackFlyTargetPath);
        _encounterManager = GetNode<EncounterManager>(EncounterManagerPath);
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
            _encounterManager
        );
        _holdInteractionController = GetNode<WorldHoldInteractionController>(HoldInteractionControllerPath);

        _boardController.CardClicked += OnBoardCardClicked;
        _boardController.CardPressed += OnBoardCardPressed;
        _boardController.CardReleased += OnBoardCardReleased;
        _boardController.CardSpawned += OnBoardCardSpawned;
        _gameplayPort.EncounterRequested += OnEncounterRequested;

        _timeSystem = TimeSystem.Instance;
        if (_timeSystem != null)
        {
            _timeSystem.TimeChanged += OnTimeChanged;
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
        if (_gameplayPort != null)
        {
            _gameplayPort.EncounterRequested -= OnEncounterRequested;
        }
        if (_timeSystem != null)
        {
            _timeSystem.TimeChanged -= OnTimeChanged;
        }
        _holdInteractionController?.CancelActiveHold();
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
            _holdInteractionController.CancelActiveHold();
        }
    }

    private async void OnEncounterRequested(TerrainInstance terrain, Array<SkillCardData> battleDeck, Array<MonsterData> monsters, string message)
    {
        await _combatScenePresenter.EnterCombatAsync(battleDeck, monsters);
    }

    /// <summary>
    /// 为地图通道驻守怪物发起战斗，并在战斗结束后发出结果信号。
    /// </summary>
    /// <param name="monsters">通道驻守 encounter 配置出的怪物数组。</param>
    public async void RequestPassageGuardEncounter(Array<MonsterData> monsters)
    {
        GD.Print("RequestPassageGuardEncounter: monsters = ", monsters);
        bool isVictory = await _combatScenePresenter.EnterCombatAndWaitForResultAsync(
            _gameplayPort.PlayerBattleDeck.GetSkillCards(),
            monsters ?? []
        );
        EmitSignal(SignalName.PassageGuardEncounterFinished, isVictory);
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
        _holdInteractionController.BeginHold(
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

        _holdInteractionController.CancelHoldFor(owner);
    }

    private void OnBoardCardClicked(BoardCardView card)
    {
        ArgumentNullException.ThrowIfNull(card);

        ItemStack loot = card.GetLootStackOrNull();
        if (loot != null)
        {
            HandleLootCardClicked(card, loot);
            return;
        }

        TerrainInstance terrain = card.GetTerrainInstanceOrNull();
        if (terrain != null)
        {
            if (GetInteractionActionPointCost(terrain.TerrainData?.InteractionBehavior) > 0)
            {
                return;
            }

            HandleTerrainCardClicked(card, terrain);
        }
    }

    private void HandleLootCardClicked(BoardCardView card, ItemStack stack)
    {
        bool success = _gameplayPort.TryAddItemToInventory(stack);
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
        card.PlayFlyTo(target, () => _boardController.RemoveCard(card));
    }

    private void HandleTerrainCardClicked(BoardCardView card, TerrainInstance terrain)
    {
        _terrainInteractionExecutor.Execute(card, terrain);
    }

    private void OnBoardCardPressed(BoardCardView card)
    {
        if (TryGetHoldableTerrain(
                card,
                out TerrainInstance terrain,
                out TerrainInteraction interaction,
                out int actionPointCost))
        {
            _holdInteractionController.BeginHold(
                card,
                actionPointCost,
                Callable.From(() => CompleteTerrainHold(card, terrain, interaction, actionPointCost)),
                card.GetNodeOrNull<Sprite2D>("Icon") as Node ?? card
            );
        }
    }

    private void OnBoardCardReleased(BoardCardView card)
    {
        _holdInteractionController.CancelHoldFor(card);
    }

    private void OnBoardCardSpawned(BoardCardView card)
    {
        if (TryGetReusableGathering(card, out TerrainInstance terrain, out ReusableGatheringInteraction interaction))
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
        foreach (BoardCardView card in _boardController.GetActiveCardsSnapshot())
        {
            if (!IsInstanceValid(card)
                || !TryGetReusableGathering(card, out TerrainInstance terrain, out ReusableGatheringInteraction interaction))
            {
                continue;
            }

            RefreshReusableGatheringCard(card, terrain, interaction, totalTimePassed);
        }
    }

    private bool TryGetHoldableTerrain(
        BoardCardView card,
        out TerrainInstance terrain,
        out TerrainInteraction interaction,
        out int actionPointCost)
    {
        terrain = card?.GetTerrainInstanceOrNull();
        interaction = terrain?.TerrainData?.InteractionBehavior;
        actionPointCost = GetInteractionActionPointCost(interaction);
        if (terrain == null || interaction == null || actionPointCost <= 0)
        {
            return false;
        }

        if (interaction is not ReusableGatheringInteraction reusableGathering)
        {
            return true;
        }

        int totalTimePassed = GetCurrentTotalTime();
        RefreshReusableGatheringCard(card, terrain, reusableGathering, totalTimePassed);
        return reusableGathering.CanHarvest(terrain, totalTimePassed);
    }

    private void CompleteTerrainHold(
        BoardCardView card,
        TerrainInstance terrain,
        TerrainInteraction interaction,
        int actionPointCost)
    {
        if (!IsInstanceValid(card)
            || card.GetTerrainInstanceOrNull() != terrain)
        {
            return;
        }

        if (interaction is ReusableGatheringInteraction reusableGathering)
        {
            int totalTimePassed = GetCurrentTotalTime();
            if (!reusableGathering.CanHarvest(terrain, totalTimePassed))
            {
                RefreshReusableGatheringCard(card, terrain, reusableGathering, totalTimePassed);
                return;
            }
        }

        // 传回开始时快照的采集耗时，确保工具在长按中变化也不会改变已显示的等待成本。
        _terrainInteractionExecutor.Execute(card, terrain, actionPointCost);

        if (interaction is ReusableGatheringInteraction completedReusableGathering)
        {
            RefreshReusableGatheringCard(card, terrain, completedReusableGathering, GetCurrentTotalTime());
        }
    }

    private int GetInteractionActionPointCost(TerrainInteraction interaction)
    {
        if (interaction is ReusableGatheringInteraction reusableGathering)
        {
            return reusableGathering.GetEffectiveTimeCost(_gameplayPort.Player?.Equipment);
        }

        return Math.Max(0, interaction?.TimeCost ?? 0);
    }

    private static bool TryGetReusableGathering(
        BoardCardView card,
        out TerrainInstance terrain,
        out ReusableGatheringInteraction interaction)
    {
        terrain = card?.GetTerrainInstanceOrNull();
        interaction = terrain?.TerrainData?.InteractionBehavior as ReusableGatheringInteraction;
        return terrain != null && interaction != null;
    }

    private static void RefreshReusableGatheringCard(
        BoardCardView card,
        TerrainInstance terrain,
        ReusableGatheringInteraction interaction,
        int totalTimePassed)
    {
        bool canHarvest = interaction.CanHarvest(terrain, totalTimePassed);
        card.SetInteractionDisabled(!canHarvest);
    }

    private static int GetCurrentTotalTime()
    {
        return TimeSystem.Instance?.TotalTimePassed ?? 0;
    }
}
