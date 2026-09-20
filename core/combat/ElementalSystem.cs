using Godot;
using System.Collections.Generic;
using CUSGA.core.constants;

namespace CUSGA.core.combat;

public static class ElementalSystem
{
    private const float COUNTERMODIFIER = 1.5f;
    private const float RESISTMODIFIER = 0.5f;
    private static readonly Dictionary<(ElementType attack, ElementType defense), float> _damageMatrix = new()
    {
        // 相克矩阵：1.5倍伤害
        {(ElementType.Metal, ElementType.Wood), COUNTERMODIFIER},
        {(ElementType.Wood, ElementType.Earth), COUNTERMODIFIER},
        {(ElementType.Earth, ElementType.Water), COUNTERMODIFIER},
        {(ElementType.Water, ElementType.Fire), COUNTERMODIFIER},
        {(ElementType.Fire, ElementType.Metal), COUNTERMODIFIER},
        // 被克制矩阵：0.5倍伤害
        {(ElementType.Wood, ElementType.Metal), RESISTMODIFIER},
        {(ElementType.Water, ElementType.Earth), RESISTMODIFIER},
        {(ElementType.Fire, ElementType.Water), RESISTMODIFIER},
        {(ElementType.Earth, ElementType.Wood), RESISTMODIFIER},
        {(ElementType.Metal, ElementType.Fire), RESISTMODIFIER},
    };

    public static float CalculateMultiplier(ElementType attackElement, ElementType defenseElement)
    {
        float multiplier = 1.0f;

        // 五行基础倍率查询
        if (_damageMatrix.TryGetValue((attackElement, defenseElement), out float baseMultiplier))
        {
            multiplier = baseMultiplier;
        }
        // 通过稳定的 Autoload 节点路径读取天气，兼容 GDScript 管理器和旧 C# 管理器。
        Node weatherManager = GetWeatherManager();
        Resource weather = weatherManager?.Get("CurrentWeather").AsGodotObject() as Resource;

        // 结合天气系统的修正；枚举键按原 ElementType 整数值保存。
        if (weather != null && TryReadWeatherMultiplier(weather, (int)attackElement, out float weatherMult))
        {
            multiplier *= weatherMult;
        }

        return multiplier;
    }

    /// <summary>
    /// 从当前场景树获取天气 Autoload。
    /// </summary>
    /// <returns>天气管理器节点；编辑器或测试环境未启动场景树时返回 null。</returns>
    private static Node GetWeatherManager()
    {
        if (Engine.GetMainLoop() is not SceneTree tree || tree.Root == null)
        {
            return null;
        }

        return tree.Root.GetNodeOrNull<Node>("WeatherManager");
    }

    /// <summary>
    /// 读取天气 Resource 中指定元素的倍率，兼容 GDScript/C# Dictionary Variant。
    /// </summary>
    /// <param name="weather">天气配置资源。</param>
    /// <param name="elementKey">ElementType 的稳定整数值。</param>
    /// <param name="multiplier">读取到的倍率。</param>
    /// <returns>找到数值倍率时返回 true，否则返回 false。</returns>
    private static bool TryReadWeatherMultiplier(Resource weather, int elementKey, out float multiplier)
    {
        multiplier = 1.0f;
        Variant rawModifiers = weather.Get("ElementModifiers");
        if (rawModifiers.VariantType != Variant.Type.Dictionary)
        {
            return false;
        }

        Godot.Collections.Dictionary modifiers = rawModifiers.AsGodotDictionary();
        if (!modifiers.TryGetValue(elementKey, out Variant rawMultiplier))
        {
            return false;
        }

        if (rawMultiplier.VariantType is not (Variant.Type.Int or Variant.Type.Float))
        {
            return false;
        }

        multiplier = (float)rawMultiplier.AsDouble();
        return true;
    }
}
