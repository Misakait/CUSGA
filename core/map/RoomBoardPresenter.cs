using System;
using System.Collections.Generic;
using Godot;
using CUSGA.core.board;
using CUSGA.resources.interaction;
using CUSGA.core.constants;

namespace CUSGA.core.map;

public partial class RoomBoardPresenter : Node
{
    [Export] public NodePath MapInstantiatorPath { get; set; }
    [Export] public NodePath BoardControllerPath { get; set; }
    [Export] public NodePath TerrainStorePath { get; set; }

    [Export] public bool HideHarvestedTerrain { get; set; } = true;

    private Node _mapInstantiator = null!;
    private BoardController _boardController = null!;
    private RoomTerrainStore _terrainStore = null!;

    private Callable _roomEnteredCallable;

    public override void _Ready()
    {
        if (MapInstantiatorPath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.MapInstantiatorPath 未设置。");
        }

        if (BoardControllerPath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.BoardControllerPath 未设置。");
        }

        if (TerrainStorePath.IsEmpty)
        {
            throw new InvalidOperationException("RoomBoardPresenter.TerrainStorePath 未设置。");
        }

        _mapInstantiator = GetNode<Node>(MapInstantiatorPath);
        _boardController = GetNode<BoardController>(BoardControllerPath);
        _terrainStore = GetNode<RoomTerrainStore>(TerrainStorePath);

        _roomEnteredCallable = Callable.From<Vector2I, Node2D>(OnRoomEntered);

        if (!_mapInstantiator.HasSignal(GDSignals.OnEnteredRoom))
        {
            throw new InvalidOperationException(
                $"MapInstantiator 缺少信号 '{GDSignals.OnEnteredRoom}'"
            );
        }

        if (!_mapInstantiator.IsConnected(GDSignals.OnEnteredRoom, _roomEnteredCallable))
        {
            _mapInstantiator.Connect(GDSignals.OnEnteredRoom, _roomEnteredCallable);
        }
    }

    public override void _ExitTree()
    {
        if (_mapInstantiator != null &&
            _mapInstantiator.IsConnected(GDSignals.OnEnteredRoom, _roomEnteredCallable))
        {
            _mapInstantiator.Disconnect(GDSignals.OnEnteredRoom, _roomEnteredCallable);
        }
    }

    private void OnRoomEntered(Vector2I roomPos, Node2D roomScene)
    {
        if (roomScene == null || !IsInstanceValid(roomScene))
        {
            return;
        }

        _boardController.ClearAllCards();

        foreach (TerrainSpawnPoint spawnPoint in FindTerrainSpawnPoints(roomScene))
        {
            if (!spawnPoint.SpawnOnEnter)
            {
                continue;
            }

            if (spawnPoint.TerrainData == null)
            {
                GD.PushWarning($"TerrainSpawnPoint '{spawnPoint.Name}' 缺少 TerrainData。");
                continue;
            }

            TerrainInstance terrain = _terrainStore.GetOrCreate(
                roomPos,
                spawnPoint.LocalGridPos,
                spawnPoint.TerrainData
            );

            if (HideHarvestedTerrain && terrain.IsHarvested)
            {
                continue;
            }

            _boardController.SpawnTerrainCard(terrain, spawnPoint.GlobalPosition);
        }
    }

    private static IEnumerable<TerrainSpawnPoint> FindTerrainSpawnPoints(Node root)
    {
        foreach (Node child in root.GetChildren())
        {
            if (child is TerrainSpawnPoint spawnPoint)
            {
                yield return spawnPoint;
            }

            foreach (TerrainSpawnPoint nested in FindTerrainSpawnPoints(child))
            {
                yield return nested;
            }
        }
    }
}
