using Godot;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;

namespace CUSGA.entities;

[GlobalClass]
public partial class Monster : Node2D
{
    [Export]
    public MonsterData BaseData { get; set; }

    public HealthComponent Health { get; private set; }
    public AttributeComponent Attributes { get; private set; }
    public FactionComponent Faction { get; private set; }
    public Node BehaviorTree { get; private set; }
    private Node _modelContainer; // 用来挂载美术模型的空节点

    public override void _Ready()
    {
        Attributes = GetNode<AttributeComponent>("Components/AttributeComponent");
        Faction = GetNode<FactionComponent>("Components/FactionComponent");
        _modelContainer = GetNode<Node>("ModelContainer");
        BehaviorTree = GetNode<Node>("BehaviorTree");
        Health = GetNode<HealthComponent>("Components/HealthComponent");

        if (BaseData != null)
        {
            Initialize(BaseData);
        }
    }

    public void Initialize(MonsterData data)
    {
        BaseData = data;
        Attributes.InitializeWithData(data.InitialAttributes);
        Faction.Faction = data.Faction;
        Health.InitializeMax(data.MaxHealth);

        // 实例化图纸里配置的美术预制体
        if (data.ModelScene != null)
        {
            var visualModel = data.ModelScene.Instantiate();
            _modelContainer.AddChild(visualModel);
        }

        // 初始化行为树
        var behaviorTree = data.BehaviorTreeScene.Instantiate();
        if (behaviorTree != null)
        {
            BehaviorTree.AddChild(behaviorTree);
        }
    }
}
