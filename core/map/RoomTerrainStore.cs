using System;
using System.Collections.Generic;
using Godot;
using CUSGA.resources.interaction;

namespace CUSGA.core.map;

public partial class RoomTerrainStore : Node
{
    // 第一个vector2i是房间坐标，第二个是房间内的地形卡坐标(房间内的坐标)
    private readonly Dictionary<Vector2I, Dictionary<Vector2I, TerrainInstance>> _terrainByRoom = [];

    public TerrainInstance GetOrCreate(Vector2I roomPos, Vector2I localGridPos, TerrainCardData terrainData)
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

        var instance = new TerrainInstance
        {
            LocalGridPos = localGridPos,
            TerrainData = terrainData,
            IsOccupied = false,
            IsHarvested = false,
            GrowthStage = 0
        };

        roomTerrains[localGridPos] = instance;
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
