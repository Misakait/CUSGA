using Godot;
using CUSGA.resources.weather;

namespace CUSGA.core.environment;

public partial class WeatherManager : Node
{
    public static WeatherManager Instance { get; private set; }

    [Signal]
    public delegate void WeatherChangedEventHandler(WeatherData newWeather);

    [Export] public WeatherData CurrentWeather { get; private set; }

    public override void _Ready()
    {
        Instance = this;
    }

    public void ChangeWeather(WeatherData newWeather)
    {
        CurrentWeather = newWeather;
        EmitSignal(SignalName.WeatherChanged, CurrentWeather);
        GD.Print($"[环境系统] 天气变更为：{newWeather.WeatherName}");
    }
}
