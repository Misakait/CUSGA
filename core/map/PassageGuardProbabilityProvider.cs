#nullable enable

using Godot;

namespace CUSGA.core.map;

/// <summary>
/// 计算入夜生成驻守通道表时使用的最终概率。
/// </summary>
[GlobalClass]
public partial class PassageGuardProbabilityProvider : RefCounted
{
    /// <summary>
    /// 根据全局配置和玩家标签计算最终驻守概率。
    /// </summary>
    /// <param name="settings">通道驻守全局配置；为空时返回 0。</param>
    /// <param name="tags">玩家标签组件节点；为空时只应用无标签要求的修正。</param>
    /// <returns>已限制在 0 到 1 之间的最终概率。</returns>
    public float Calculate(Resource settings, Node? tags)
    {
        if (settings == null)
        {
            return 0f;
        }

        float additiveSum = 0f;
        float multiplierProduct = 1f;
        foreach (Resource modifier in ReadResourceArray(settings, "ProbabilityModifiers"))
        {
            if (modifier == null || !Applies(modifier, tags))
            {
                continue;
            }

            additiveSum += ReadFloat(modifier, "AdditiveChance", 0f);
            multiplierProduct *= ReadFloat(modifier, "Multiplier", 1f);
        }

        float baseChance = ReadFloat(settings, "BaseGuardChance", 0f);
        return Mathf.Clamp((baseChance + additiveSum) * multiplierProduct, 0f, 1f);
    }

    /// <summary>
    /// 判断迁移中的概率修正资源是否满足标签条件。
    /// </summary>
    /// <param name="modifier">旧 C# 或新 GDScript 概率修正资源。</param>
    /// <param name="tags">玩家标签组件节点；为空时只有无标签修正可生效。</param>
    /// <returns>标签为空或玩家拥有所需标签时返回 true。</returns>
    private static bool Applies(Resource modifier, Node? tags)
    {
        StringName requiredTag = ReadStringName(modifier, "RequiredTag");
        // 标签组件可能来自任一语言，驻守兼容垫片只依赖共同保留的查询方法。
        return requiredTag.IsEmpty
            || (tags != null
                && tags.HasMethod("HasTag")
                && tags.Call("HasTag", requiredTag).AsBool());
    }

    /// <summary>
    /// 从 Resource 边界读取浮点配置，兼容 C# 与 GDScript 导出字段。
    /// </summary>
    /// <param name="resource">待读取的 Resource。</param>
    /// <param name="propertyName">导出属性名称。</param>
    /// <param name="fallback">属性缺失或类型不匹配时使用的默认值。</param>
    /// <returns>资源中的浮点配置或中性默认值。</returns>
    private static float ReadFloat(Resource resource, string propertyName, float fallback)
    {
        Variant value = resource.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? (float)value.AsDouble()
            : fallback;
    }

    /// <summary>
    /// 从 Resource 边界读取标签，兼容 StringName、String 和空值。
    /// </summary>
    /// <param name="resource">待读取的 Resource。</param>
    /// <param name="propertyName">导出属性名称。</param>
    /// <returns>资源中的标签；无法读取时返回空标签。</returns>
    private static StringName ReadStringName(Resource resource, string propertyName)
    {
        Variant value = resource.Get(propertyName);
        return value.VariantType switch
        {
            Variant.Type.StringName => value.AsStringName(),
            Variant.Type.String => new StringName(value.AsString()),
            _ => new StringName(string.Empty)
        };
    }

    /// <summary>
    /// 从配置 Resource 读取通用 Resource 数组，兼容 C# 和 GDScript 数组属性。
    /// </summary>
    /// <param name="resource">待读取的配置资源。</param>
    /// <param name="propertyName">数组属性名称。</param>
    /// <returns>过滤出 Resource 元素后的数组。</returns>
    private static Godot.Collections.Array<Resource> ReadResourceArray(Resource resource, string propertyName)
    {
        var resources = new Godot.Collections.Array<Resource>();
        Variant value = resource.Get(propertyName);
        if (value.VariantType != Variant.Type.Array)
        {
            return resources;
        }

        foreach (Variant item in value.AsGodotArray())
        {
            if (item.AsGodotObject() is Resource nestedResource)
            {
                resources.Add(nestedResource);
            }
        }

        return resources;
    }
}
