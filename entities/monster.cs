using Godot;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.core.constants;
using CUSGA.core.combat;
using CUSGA.core.attributes;

namespace CUSGA.entities;

public partial class Monster : CharacterBody2D
{
    [Export] public MonsterData BaseData { get; private set; }

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

    public void ReceiveCardAttack(DamagePayload payload)
    {
        var attackerStats = payload.Source.GetNode<AttributeComponent>("AttributeComponent");
        var defenderStats = GetNode<AttributeComponent>("AttributeComponent");

        float calculatedDamage = payload.Damage;

        // 攻击方增伤
        if (payload.Type == DamageType.Physical)
        {
            float flatPhysPower = attackerStats.GetAttribute(AttributeType.PhysAtk)?.Value ?? 0f;
            calculatedDamage += flatPhysPower;

            float physBoostPct = attackerStats.GetAttribute(AttributeType.PhysDamageBoost)?.Value ?? 0f;
            calculatedDamage *= (1f + physBoostPct);
        }
        else if (payload.Type == DamageType.Magic)
        {
            float flatMagPower = attackerStats.GetAttribute(AttributeType.MagPower)?.Value ?? 0f;
            calculatedDamage += flatMagPower;

            float magicBoostPct = attackerStats.GetAttribute(AttributeType.MagicDamageBoost)?.Value ?? 0f;
            calculatedDamage *= (1f + magicBoostPct);
        }

        // 元素反应区
        float elementMult = ElementalSystem.CalculateMultiplier(payload.Element, BaseData.ElementalProperty);
        calculatedDamage *= elementMult;

        // 防御抗性减伤区
        if (payload.Type != DamageType.Real)
        {
            float targetDefense = 0f;

            if (payload.Type == DamageType.Physical)
            {
                targetDefense = defenderStats.GetAttribute(AttributeType.PhysDef)?.Value ?? 0f;
            }
            else if (payload.Type == DamageType.Magic)
            {
                targetDefense = defenderStats.GetAttribute(AttributeType.MagResist)?.Value ?? 0f;
            }

            // 最终护甲
            float finalDefense = Mathf.Max(0, targetDefense);

            float defenseMultiplier = 100f / (100f + finalDefense);

            calculatedDamage *= defenseMultiplier;
        }

        int finalDamageInt = Mathf.RoundToInt(calculatedDamage);
        GetNode<HealthComponent>("HealthComponent").TakeDamage(finalDamageInt, payload.Element);
    }
}
