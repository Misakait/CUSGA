using Godot;
using System.Collections.Generic;
using CUSGA.core.constants;
using CUSGA.core.environment;

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
        var weather = WeatherManager.Instance.CurrentWeather;

        //  结合天气系统的修正
        if (weather != null && weather.ElementModifiers.TryGetValue(attackElement, out float weatherMult))
        {
            multiplier *= weatherMult;
        }

        return multiplier;
    }
}
