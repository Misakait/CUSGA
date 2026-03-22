using CUSGA.resources.monsters;
using Godot;

namespace CUSGA.resources.encounters;

[GlobalClass]
public partial class GatheringEncounterRule : Resource
{
    // 触发条件：砍的是什么标签的资源
    [Export] public StringName TriggerTag { get; set; }

    // 生成的怪物
    [Export] public MonsterData MonsterToSpawn { get; set; }

    //生成时的 UI 提示语
    [Export] public string SpawnMessage { get; set; } = "糟糕！采集物变成了怪物！";

    // 生成概论的附加权重系数
    [Export] public float ExtraChanceMultiplier { get; set; } = 1.0f;
}
