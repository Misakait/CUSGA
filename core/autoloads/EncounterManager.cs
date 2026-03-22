using CUSGA.entities;
using CUSGA.resources.encounters;
using Godot;
using Godot.Collections;
namespace CUSGA.core.autoloads;

public partial class EncounterManager : Node
{
    public static EncounterManager Instance { get; private set; }
    [Export] public Array<GatheringEncounterRule> GatheringRules { get; set; } = [];
    [Export] public PackedScene Monster { get; set; }
    private const float nightModifier = 6.0f;
    private const float originSpawnChance = 0.05f;


    public override void _Ready()
    {
        Instance = this;
    }

    public void OnPlayerGatheringComplete(StringName resourceTag, Node resourceNode)
    {
        float dayNightModifier = TimeSystem.Instance.IsNight ? nightModifier : 1.0f;
        float spawnChance = originSpawnChance * dayNightModifier;

        if (GD.Randf() <= spawnChance)
        {
            TriggerGatheringEncounter(resourceTag, resourceNode);
        }
    }

    private void TriggerGatheringEncounter(StringName resourceTag, Node resourceNode)
    {
        foreach (var rule in GatheringRules)
        {
            if (rule.TriggerTag == resourceTag)
            {
                if (rule.MonsterToSpawn != null)
                {
                    var monster = Monster.Instantiate<Monster>();
                    monster.Initialize(rule.MonsterToSpawn);

                    //将怪物生成在资源的位置
                    resourceNode.GetParent().AddChild(monster);
                    monster.GlobalPosition = (resourceNode as Node2D).GlobalPosition;

                    resourceNode.QueueFree();

                    GD.Print(rule.SpawnMessage);
                }

                return;
            }
        }
    }
}
