using Godot;
using Godot.Collections;
using CUSGA.core.combat.monster;
using CUSGA.core.combat.skills;
using CUSGA.resources.monster;

namespace CUSGA.entities.components;

/// <summary>
/// 持有怪物在战斗中可使用的战斗技能集合。
/// </summary>
[GlobalClass]
public partial class MonsterSkillComponent : Node
{
    [Export] public MonsterSkillSetData SkillSet { get; set; }

    public Node Host => GetParent();

    public override void _Ready()
    {
        ValidateSkillSet();
    }

    /// <summary>
    /// 在运行时替换当前怪物的技能集合。
    /// </summary>
    /// <param name="skillSet">此组件要暴露给战斗系统的怪物技能集合。</param>
    public void Initialize(MonsterSkillSetData skillSet)
    {
        SkillSet = skillSet;
        ValidateSkillSet();
    }

    private void ValidateSkillSet()
    {
        if (SkillSet == null)
        {
            GD.PushWarning($"{Host?.Name} has no MonsterSkillSetData.");
            return;
        }

        foreach (var entry in SkillSet.Skills)
        {
            if (entry == null)
            {
                GD.PushWarning($"{Host?.Name} has null skill entry in MonsterSkillSetData.");
                continue;
            }

            if (entry.Skill == null)
            {
                GD.PushWarning($"{Host?.Name} has MonsterSkillEntryData with null CombatSkillData.");
            }
        }
    }

    /// <summary>
    /// 获取当前怪物配置的非空战斗技能。
    /// </summary>
    /// <returns>只包含有效 <see cref="CombatSkillData"/> 条目的新数组。</returns>
    public Array<CombatSkillData> GetCombatSkills()
    {
        var result = new Array<CombatSkillData>();

        if (SkillSet == null)
        {
            return result;
        }

        foreach (var entry in SkillSet.Skills)
        {
            if (entry?.Skill == null)
            {
                continue;
            }

            result.Add(entry.Skill);
        }

        return result;
    }

    /// <summary>
    /// 为怪物自动回合选择一个已配置的战斗技能。
    /// </summary>
    /// <returns>已配置的战斗技能；没有技能时返回 null。</returns>
    public CombatSkillData GetRandomCombatSkill()
    {
        var skills = GetCombatSkills();
        if (skills.Count == 0)
        {
            return null;
        }

        var index = (int)(GD.Randi() % (uint)skills.Count);
        return skills[index];
    }

    /// <summary>
    /// 构建用于 UI 预览的只读展示数据。
    /// </summary>
    /// <returns>可见怪物技能的预览行。</returns>
    public Array<MonsterSkillPreview> GetSkillPreviews()
    {
        var result = new Array<MonsterSkillPreview>();

        if (SkillSet == null)
        {
            return result;
        }

        foreach (var entry in SkillSet.Skills)
        {
            if (entry == null)
            {
                continue;
            }

            if (!entry.VisibleInPreview)
            {
                continue;
            }

            if (entry.Skill == null)
            {
                continue;
            }

            result.Add(
                new MonsterSkillPreview(
                    skill: entry.Skill,
                    description: entry.GetPreviewDescription()
                )
            );
        }

        return result;
    }
}
