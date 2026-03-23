using Godot;
using CUSGA.core.constants;

namespace CUSGA.resources.weather;

[GlobalClass]
public partial class WeatherData : Resource
{
    [Export] public string WeatherName { get; set; } = "晴天";

    // 天气对各个元素的伤害修正
    [Export] public Godot.Collections.Dictionary<ElementType, float> ElementModifiers { get; set; } = new();

    [Export] public float CropGrowthSpeedMultiplier { get; set; } = 1.0f;
    [Export] public bool CanExtinguishCampfire { get; set; } = false;
}
