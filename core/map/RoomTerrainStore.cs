using System;
using System.Collections.Generic;
using Godot;
using CUSGA.resources.encounters;
using CUSGA.resources.interaction;

namespace CUSGA.core.map;

public partial class RoomTerrainStore : Node
{
    // 第一个vector2i是房间坐标，第二个是房间内的地形卡坐标(房间内的坐标)
    private readonly Dictionary<Vector2I, Dictionary<Vector2I, TerrainInstance>> _terrainByRoom = [];
    private readonly Func<TerrainInstance> _terrainFactory = static () => new TerrainInstance();

    public TerrainInstance GetOrCreate(Vector2I roomPos, Vector2I localGridPos, TerrainCardData terrainData)
    {
        return GetOrCreate(
            roomPos,
            localGridPos,
            terrainData,
            Vector2.Zero,
            MonsterStatMultiplier.Identity
        );
    }

    public TerrainInstance GetOrCreate(
        Vector2I roomPos,
        Vector2I localGridPos,
        TerrainCardData terrainData,
        Vector2 boardPosition)
    {
        return GetOrCreate(
            roomPos,
            localGridPos,
            terrainData,
            boardPosition,
            MonsterStatMultiplier.Identity
        );
    }

    public TerrainInstance GetOrCreate(
        Vector2I roomPos,
        Vector2I localGridPos,
        TerrainCardData terrainData,
        Vector2 boardPosition,
        MonsterStatMultiplier encounterVarianceMultiplier)
    {
        ArgumentNullException.ThrowIfNull(terrainData);

        if (!_terrainByRoom.TryGetValue(roomPos, out var roomTerrains))
        {
            roomTerrains = [];
            _terrainByRoom[roomPos] = roomTerrains;
        }

        if (roomTerrains.TryGetValue(localGridPos, out var existing))
        {
            return existing;
        }

        TerrainInstance instance = CreateTerrainInstance(
            localGridPos,
            terrainData,
            boardPosition,
            encounterVarianceMultiplier
        );

        roomTerrains[localGridPos] = instance;
        return instance;
    }

    public bool HasRoom(Vector2I roomPos)
    {
        return _terrainByRoom.ContainsKey(roomPos);
    }

    public void CreateRoomLayout(Vector2I roomPos, IEnumerable<TerrainSpawnPlacement> placements)
    {
        ArgumentNullException.ThrowIfNull(placements);

        if (!_terrainByRoom.TryGetValue(roomPos, out var roomTerrains))
        {
            roomTerrains = [];
            _terrainByRoom[roomPos] = roomTerrains;
        }

        foreach (TerrainSpawnPlacement placement in placements)
        {
            if (placement == null)
            {
                continue;
            }

            if (roomTerrains.ContainsKey(placement.LocalGridPos))
            {
                throw new InvalidOperationException(
                    $"Room {roomPos} already contains terrain at {placement.LocalGridPos}."
                );
            }

            TerrainInstance instance = CreateTerrainInstance(
                placement.LocalGridPos,
                placement.TerrainData,
                placement.BoardPosition,
                placement.EncounterVarianceMultiplier
            );

            roomTerrains[placement.LocalGridPos] = instance;
        }
    }

    private TerrainInstance CreateTerrainInstance(
        Vector2I localGridPos,
        TerrainCardData terrainData,
        Vector2 boardPosition,
        MonsterStatMultiplier encounterVarianceMultiplier)
    {
        TerrainInstance instance = _terrainFactory();
        instance.LocalGridPos = localGridPos;
        instance.BoardPosition = boardPosition;
        instance.EncounterVarianceMultiplier =
            encounterVarianceMultiplier ?? MonsterStatMultiplier.Identity;
        instance.TerrainData = terrainData;
        instance.IsOccupied = false;
        instance.IsHarvested = false;
        instance.GrowthStage = 0;
        return instance;
    }

    public bool TryGet(Vector2I roomPos, Vector2I localGridPos, out TerrainInstance terrain)
    {
        terrain = null;

        if (!_terrainByRoom.TryGetValue(roomPos, out var roomTerrains))
        {
            return false;
        }

        return roomTerrains.TryGetValue(localGridPos, out terrain);
    }

    public IReadOnlyDictionary<Vector2I, TerrainInstance> GetRoomTerrainsOrEmpty(Vector2I roomPos)
    {
        if (_terrainByRoom.TryGetValue(roomPos, out var roomTerrains))
        {
            return roomTerrains;
        }

        return new Dictionary<Vector2I, TerrainInstance>();
    }
}
