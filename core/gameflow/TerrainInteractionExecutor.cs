using System.Collections.Generic;
using Godot;
using Godot.Collections;
using CUSGA.core.board;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;
using CUSGA.resources.interaction.operations;
using CUSGA.resources.monsters;

namespace CUSGA.core.gameflow;

public sealed class TerrainInteractionExecutor(
    Node gameplayPort,
    BoardController boardController,
    Node encounterManager,
    Node timeSystem)
{
    /// <summary>
    /// 执行指定地形卡的交互操作序列。
    /// </summary>
    /// <param name="card">触发交互的棋盘卡视图。</param>
    /// <param name="terrain">被交互的地形实例。</param>
    /// <param name="effectiveTimeCostOverride">输入开始时快照到的有效采集时间；为空时由交互资源现场计算。</param>
    public void Execute(
        Node2D card,
        TerrainInstance terrain,
        int? effectiveTimeCostOverride = null)
    {
        Player player = GetPlayer(gameplayPort);
        string terrainName = terrain.TerrainData == null
            ? string.Empty
            : terrain.TerrainData.Get("CardName").AsString();
        GD.Print($"[TerrainInteractionExecutor] Click terrain: {terrainName}");
        Resource interactionResource = terrain.TerrainData == null
            ? null
            : terrain.TerrainData.Get("InteractionBehavior").AsGodotObject() as Resource;
        if (interactionResource == null)
        {
            return;
        }

        var worldCtx = new WorldInteractionContext
        {
            Gameplay = new GameplayInteractionPort(gameplayPort),
            Board = new BoardInteractionPort(boardController, card),
            Encounters = new EncounterInteractionPort(encounterManager, gameplayPort),
            TimeSystem = timeSystem,
            Terrain = terrain,
            SourceGlobalPosition = card.GlobalPosition,
        };

        if (interactionResource is TerrainInteraction interaction)
        {
            GD.Print($"[TerrainInteractionExecutor] Build C# ops from {interaction.GetType().Name}");
            var buildCtx = new TerrainInteractionBuildContext
            {
                Player = player,
                Terrain = terrain,
                TimeSystem = timeSystem,
                EffectiveTimeCostOverride = effectiveTimeCostOverride
            };

            IReadOnlyList<TerrainOp> ops = interaction.BuildOps(buildCtx);
            ApplyOps(ops, worldCtx);
            return;
        }

        if (!interactionResource.HasMethod("build_ops"))
        {
            GD.PushError(
                $"地形交互资源 {interactionResource.GetType().Name} 未实现 BuildOps 或 build_ops，无法执行。"
            );
            return;
        }

        GD.Print($"[TerrainInteractionExecutor] Build GDScript ops from {interactionResource.GetType().Name}");
        Variant builtOps = effectiveTimeCostOverride.HasValue
            ? interactionResource.Call("build_ops", player, terrain, effectiveTimeCostOverride.Value)
            : interactionResource.Call("build_ops", player, terrain);
        ApplyGDScriptOps(interactionResource, builtOps, terrain, worldCtx);
    }

    /// <summary>
    /// 应用 C# 交互资源已经构建好的操作序列。
    /// </summary>
    /// <param name="ops">交互资源返回的有序操作。</param>
    /// <param name="context">执行操作所需的运行时端口。</param>
    private static void ApplyOps(IReadOnlyList<TerrainOp> ops, WorldInteractionContext context)
    {
        GD.Print($"[TerrainInteractionExecutor] Ops count = {ops.Count}");
        foreach (TerrainOp op in ops)
        {
            op.Apply(context);
        }
    }

    /// <summary>
    /// 将 GDScript 资源返回的操作描述映射为现有运行时端口调用。
    /// </summary>
    /// <param name="interaction">返回描述的 GDScript 资源。</param>
    /// <param name="builtOps">GDScript 返回的 Dictionary 数组。</param>
    /// <param name="terrain">当前地形实例，用于记录可重复采集状态。</param>
    /// <param name="context">执行操作所需的运行时端口。</param>
    private static void ApplyGDScriptOps(
        Resource interaction,
        Variant builtOps,
        TerrainInstance terrain,
        WorldInteractionContext context)
    {
        if (builtOps.VariantType != Variant.Type.Array)
        {
            GD.PushError("GDScript 地形交互的 build_ops 必须返回 Array[Dictionary]。\n");
            return;
        }

        Godot.Collections.Array rawOps = builtOps.AsGodotArray();
        GD.Print($"[TerrainInteractionExecutor] GDScript ops count = {rawOps.Count}");
        foreach (Variant rawOp in rawOps)
        {
            if (rawOp.VariantType != Variant.Type.Dictionary)
            {
                GD.PushError("GDScript 地形交互返回了非 Dictionary 操作，已跳过。\n");
                continue;
            }

            Godot.Collections.Dictionary op = rawOp.AsGodotDictionary();
            string type = op.TryGetValue("type", out Variant typeValue)
                ? typeValue.AsString()
                : string.Empty;
            switch (type)
            {
                case "pass_time":
                    ApplyOps(
                        [new PassTimeOp(op["amount"].AsInt32())],
                        context
                    );
                    break;
                case "spawn_loot":
                    Godot.Collections.Array drops = ConvertDrops(op["drops"]);
                    if (drops.Count > 0)
                    {
                        ApplyOps([new SpawnLootOp(drops)], context);
                    }
                    break;
                case "mark_harvested":
                    ApplyOps([new MarkHarvestedOp()], context);
                    break;
                case "check_gathering_encounter":
                    ApplyOps(
                        [new CheckGatheringEncounterOp(op["gathering_tag"].AsStringName())],
                        context
                    );
                    break;
                case "record_reusable_gathering":
                    interaction.Call(
                        "record_successful_harvest",
                        terrain,
                        ReadTotalTime(context.TimeSystem)
                    );
                    break;
                case "enter_vault":
                    ApplyOps([new EnterVaultOp()], context);
                    break;
                case "open_farming_panel":
                    ApplyOps([new OpenFarmingPanelOp()], context);
                    break;
                case "spawn_monster":
                    MonsterData monster = op.TryGetValue("monster", out Variant monsterValue)
                        ? monsterValue.AsGodotObject() as MonsterData
                        : null;
                    ApplyOps([new MonsterSpawnOpOp(monster)], context);
                    break;
                case "remove_source_card":
                    ApplyOps([new RemoveSourceCardOp()], context);
                    break;
                default:
                    GD.PushError($"未知 GDScript 地形操作类型：{type}。\n");
                    break;
            }
        }
    }

    /// <summary>
    /// 将 GDScript 返回的非泛型数组过滤为棋盘掉落操作需要的跨语言堆叠数组。
    /// </summary>
    /// <param name="rawDrops">GDScript 操作中的 drops 字段。</param>
    /// <returns>保留旧 C# 与 GDScript ItemStack 原始引用、过滤无效元素后的数组。</returns>
    private static Godot.Collections.Array ConvertDrops(Variant rawDrops)
    {
        Godot.Collections.Array drops = [];
        if (rawDrops.VariantType != Variant.Type.Array)
        {
            return drops;
        }

        foreach (Variant value in rawDrops.AsGodotArray())
        {
            if (value.AsGodotObject() is RefCounted stack
                && ItemStackProtocol.TryRead(stack, out _, out _))
            {
                drops.Add(Variant.From(stack));
            }
        }

        return drops;
    }

    /// <summary>
    /// 从旧 C# 或生产 GDScript TimeSystem 读取累计时间。
    /// </summary>
    /// <param name="timeSystem">实现 TotalTimePassed 属性协议的时间节点。</param>
    /// <returns>当前累计时间；节点或属性无效时返回零。</returns>
    private static int ReadTotalTime(Node timeSystem)
    {
        if (timeSystem == null)
        {
            return 0;
        }

        Variant value = timeSystem.Get("TotalTimePassed");
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? value.AsInt32()
            : 0;
    }

    private sealed class GameplayInteractionPort(Node gameplayPort) : IInteractionGameplayPort
    {
        public void RequestOpenFarmingPanel(TerrainInstance terrain)
        {
            gameplayPort.Call("RequestOpenFarmingPanel", terrain);
        }

        public void RequestOpenWarehouse()
        {
            gameplayPort.Call("RequestOpenWarehouse");
        }

        public void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message)
        {
            gameplayPort.Call("RequestEncounter", terrain, monster, message);
        }

        public void RequestEncounter(TerrainInstance terrain, Array<MonsterData> monsters, string message)
        {
            gameplayPort.Call("RequestEncounter", terrain, monsters, message);
        }
    }

    private sealed class BoardInteractionPort(BoardController boardController, Node2D sourceCard) : IInteractionBoardPort
    {
        public void SpawnLootCards(Godot.Collections.Array drops, Vector2 spawnOrigin)
        {
            boardController.SpawnLootCards(drops, spawnOrigin);
        }

        public void RemoveSourceCard()
        {
            boardController.RemoveCard(sourceCard);
        }
    }

    private sealed class EncounterInteractionPort(
        Node encounterManager,
        Node gameplayPort) : IInteractionEncounterPort
    {
        public GatheringEncounterResult ResolveGatheringEncounter(StringName resourceTag)
        {
            float encounterChanceMultiplier = GetNightEncounterChanceMultiplier(
                GetPlayer(gameplayPort)?.Equipment
            );
            if (encounterManager == null || !encounterManager.HasMethod("ResolveGatheringEncounter"))
            {
                return GatheringEncounterResult.None();
            }

            Variant raw = encounterManager.Call(
                "ResolveGatheringEncounter",
                resourceTag,
                encounterChanceMultiplier
            );
            return raw.AsGodotObject() as GatheringEncounterResult
                ?? GatheringEncounterResult.None();
        }

        /// <summary>
        /// 从任一语言的装备组件读取夜晚遭遇倍率。
        /// </summary>
        /// <param name="equipment">实现稳定倍率查询协议的装备节点。</param>
        /// <returns>配置有效时返回装备倍率；节点缺失或返回值无效时返回中性倍率 1。</returns>
        private static float GetNightEncounterChanceMultiplier(Node equipment)
        {
            if (equipment?.HasMethod("GetNightEncounterChanceMultiplier") != true)
            {
                return 1.0f;
            }

            Variant value = equipment.Call("GetNightEncounterChanceMultiplier");
            return value.VariantType is Variant.Type.Int or Variant.Type.Float
                ? value.AsSingle()
                : 1.0f;
        }
    }

    /// <summary>
    /// 从任一语言 GameplayPort 的稳定 Player 属性读取生产玩家。
    /// </summary>
    /// <param name="gameplayPort">提供 Player 属性的 GameplayPort 节点。</param>
    /// <returns>玩家实例；节点为空、字段缺失或类型不符时返回 null。</returns>
    private static Player GetPlayer(Node gameplayPort)
    {
        if (gameplayPort == null)
        {
            return null;
        }

        return gameplayPort.Get("Player").AsGodotObject() as Player;
    }
}
