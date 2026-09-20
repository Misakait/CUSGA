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
    // 使用通用 Resource 承接 GDScript 技能集合；旧 C# MonsterSkillSetData 仍可直接赋值。
    [Export] public Resource SkillSet { get; set; }

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
        Initialize((Resource)skillSet);
    }

    /// <summary>
    /// 在运行时替换当前怪物的 C# 或 GDScript 技能集合。
    /// </summary>
    /// <param name="skillSet">包含 Skills 数组的技能集合 Resource。</param>
    public void Initialize(Resource skillSet)
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

        foreach (Resource entry in ReadSkillEntries())
        {
            if (entry == null)
            {
                GD.PushWarning($"{Host?.Name} has null skill entry in MonsterSkillSetData.");
                continue;
            }

            if (ReadCombatSkill(entry) == null)
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

        foreach (Resource entry in ReadSkillEntries())
        {
            CombatSkillData skill = ReadCombatSkill(entry);
            if (skill == null)
            {
                continue;
            }

            result.Add(skill);
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

        foreach (Resource entry in ReadSkillEntries())
        {
            if (entry == null)
            {
                continue;
            }

            if (!ReadVisibleInPreview(entry))
            {
                continue;
            }

            CombatSkillData skill = ReadCombatSkill(entry);
            if (skill == null)
            {
                continue;
            }

            result.Add(
                new MonsterSkillPreview(
                    skill: skill,
                    description: ReadPreviewDescription(entry)
                )
            );
        }

        return result;
    }

    /// <summary>
    /// 读取技能集合中的条目数组，并兼容旧 C# 强类型集合和 GDScript Resource。
    /// </summary>
    /// <returns>过滤掉空值后的技能条目 Resource 数组。</returns>
    private Array<Resource> ReadSkillEntries()
    {
        var result = new Array<Resource>();
        if (SkillSet == null)
        {
            return result;
        }

        if (SkillSet is MonsterSkillSetData legacySet)
        {
            foreach (MonsterSkillEntryData entry in legacySet.Skills)
            {
                if (entry != null)
                {
                    result.Add(entry);
                }
            }

            return result;
        }

        Variant rawSkills = SkillSet.Get("Skills");
        if (rawSkills.VariantType != Variant.Type.Array)
        {
            return result;
        }

        foreach (Variant value in rawSkills.AsGodotArray())
        {
            if (value.AsGodotObject() is Resource entry)
            {
                result.Add(entry);
            }
        }

        return result;
    }

    /// <summary>
    /// 从一个技能条目中读取 CombatSkillData。
    /// </summary>
    /// <param name="entry">待读取的技能条目 Resource。</param>
    /// <returns>条目中的战斗技能；字段缺失或类型不符时返回 null。</returns>
    private static CombatSkillData ReadCombatSkill(Resource entry)
    {
        if (entry is MonsterSkillEntryData legacyEntry)
        {
            return legacyEntry.Skill;
        }

        Variant value = entry.Get("Skill");
        return value.AsGodotObject() as CombatSkillData;
    }

    /// <summary>
    /// 读取技能条目的预览可见标志。
    /// </summary>
    /// <param name="entry">待读取的技能条目 Resource。</param>
    /// <returns>配置值；字段不存在时按旧默认值 true 处理。</returns>
    private static bool ReadVisibleInPreview(Resource entry)
    {
        if (entry is MonsterSkillEntryData legacyEntry)
        {
            return legacyEntry.VisibleInPreview;
        }

        Variant value = entry.Get("VisibleInPreview");
        return value.VariantType == Variant.Type.Nil || value.AsBool();
    }

    /// <summary>
    /// 读取技能条目的预览说明，统一调用迁移后的稳定方法名。
    /// </summary>
    /// <param name="entry">待读取的技能条目 Resource。</param>
    /// <returns>预览说明文本；条目没有该方法时返回空字符串。</returns>
    private static string ReadPreviewDescription(Resource entry)
    {
        if (entry is MonsterSkillEntryData legacyEntry)
        {
            return legacyEntry.GetPreviewDescription();
        }

        if (!entry.HasMethod("GetPreviewDescription"))
        {
            return string.Empty;
        }

        Variant value = entry.Call("GetPreviewDescription");
        return value.VariantType == Variant.Type.String ? value.AsString() : string.Empty;
    }
}
