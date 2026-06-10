using System;
using Godot;
using CUSGA.core.autoloads;
using CUSGA.core.board;
using CUSGA.resources.interaction;
using CUSGA.core.constants;

namespace CUSGA.core.map;

public partial class RoomBoardPresenter : Node
{
    [Export] public NodePath MapSystemPath { get; set; }
    [Export] public NodePath BoardControllerPath { get; set; }
    [Export] public NodePath TerrainStorePath { get; set; }

    [Export] public bool HideHarvestedTerrain { get; set; } = true;

    private Node _mapSystem = null!;
    private BoardController _boardController = null!;
    private RoomTerrainStore _terrainStore = null!;
    private readonly RoomTerrainLayoutGenerator _layoutGenerator = new(new Random());

    private Callable _roomEnteredCallable;

    public override void _Ready()
    {
        if (MapSystemPath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.MapSystemPath 未设置。");
        }

        if (BoardControllerPath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.BoardControllerPath 未设置。");
        }

        if (TerrainStorePath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.TerrainStorePath 未设置。");
        }

        _mapSystem = GetNode<Node>(MapSystemPath);
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _terrainStore = GetNode<RoomTerrainStore>(TerrainStorePath);

        _roomEnteredCallable = Callable.From<Vector2I, Node2D>(OnRoomEntered);

        if (!_mapSystem.HasSignal(GDSignals.OnEnteredRoom))
        {
            throw new InvalidOperationException(
                $"MapSystem 缺少信号 '{GDSignals.OnEnteredRoom}'。请在 MapSystem 根节点脚本中声明并转发该信号。"
            );
        }

        if (!_mapSystem.IsConnected(GDSignals.OnEnteredRoom, _roomEnteredCallable))
        {
            _mapSystem.Connect(GDSignals.OnEnteredRoom, _roomEnteredCallable);
        }
    }

    public override void _ExitTree()
    {
        if (_mapSystem != null &&
             _mapSystem.IsConnected(GDSignals.OnEnteredRoom, _roomEnteredCallable))
        {
            _mapSystem.Disconnect(GDSignals.OnEnteredRoom, _roomEnteredCallable);
        }
    }

    private void OnRoomEntered(Vector2I roomPos, Node2D roomScene)
    {
        if (roomScene == null || !IsInstanceValid(roomScene))
        {
            return;
        }

        _boardController.ClearAllCards();
        GD.Print($"[RoomBoardPresenter] Enter room {roomPos}, scene={roomScene.Name}");

        if (!_terrainStore.HasRoom(roomPos))
        {
            CreateInitialRoomLayout(roomPos, roomScene);
        }

        foreach (TerrainInstance terrain in _terrainStore.GetRoomTerrainsOrEmpty(roomPos).Values)
        {
            if (terrain.TerrainData == null)
            {
                continue;
            }

            if (terrain.TerrainData.InteractionBehavior is ReusableGatheringInteraction reusable)
            {
                reusable.RefreshIfReady(terrain, TimeSystem.Instance?.TotalTimePassed ?? 0);
            }

            if (HideHarvestedTerrain && terrain.IsHarvested)
            {
                continue;
            }

            _boardController.SpawnTerrainCard(terrain, terrain.BoardPosition);
        }
    }

    private void CreateInitialRoomLayout(Vector2I roomPos, Node2D roomScene)
    {
        Variant profileValue = roomScene.Get("terrain_profile");
        if (profileValue.VariantType == Variant.Type.Nil ||
            profileValue.AsGodotObject() is not RoomTerrainProfile profile)
        {
            _terrainStore.CreateRoomLayout(roomPos, []);
            return;
        }

        _terrainStore.CreateRoomLayout(roomPos, _layoutGenerator.Generate(profile));
    }
}
