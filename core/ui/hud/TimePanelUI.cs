using Godot;

namespace CUSGA.core.ui.hud;

public partial class TimePanelUI : Control
{
    private const int PhaseLength = 100;
    private static readonly StringName TimeChangedSignal = "TimeChanged";

    private Label _dayLabel = null!;
    private Label _phaseLabel = null!;
    private Label _timeLabel = null!;
    private ProgressBar _phaseProgress = null!;
    private Node _timeSystem = null!;
    private Callable _timeChangedCallable;

    public override void _Ready()
    {
        _dayLabel = GetNode<Label>("%DayLabel");
        _phaseLabel = GetNode<Label>("%PhaseLabel");
        _timeLabel = GetNode<Label>("%TimeLabel");
        _phaseProgress = GetNode<ProgressBar>("%PhaseProgress");

        _timeSystem = GetNodeOrNull<Node>("/root/TimeSystem");
        if (_timeSystem == null)
        {
            GD.PushError("TimePanelUI 未找到 TimeSystem Autoload。");
            return;
        }

        _timeChangedCallable = Callable.From<int, int, bool, int, int>(OnTimeChanged);
        if (!_timeSystem.HasSignal(TimeChangedSignal))
        {
            GD.PushError("TimePanelUI 需要 TimeSystem.TimeChanged 信号。");
            return;
        }
        if (!_timeSystem.IsConnected(TimeChangedSignal, _timeChangedCallable))
        {
            _timeSystem.Connect(TimeChangedSignal, _timeChangedCallable);
        }

        Refresh(
            ReadInt("TotalTimePassed", 0),
            ReadInt("CurrentDay", 1),
            ReadBool("IsNight", false),
            ReadInt("PhaseProgress", 0),
            PhaseLength
        );
    }

    public override void _ExitTree()
    {
        if (_timeSystem != null
            && _timeSystem.HasSignal(TimeChangedSignal)
            && _timeSystem.IsConnected(TimeChangedSignal, _timeChangedCallable))
        {
            _timeSystem.Disconnect(TimeChangedSignal, _timeChangedCallable);
        }
    }

    private void OnTimeChanged(
        int totalTimePassed,
        int currentDay,
        bool isNight,
        int phaseProgress,
        int phaseLength
    )
    {
        Refresh(
            totalTimePassed,
            currentDay,
            isNight,
            phaseProgress,
            phaseLength
        );
    }

    private void Refresh(
        int totalTimePassed,
        int currentDay,
        bool isNight,
        int phaseProgress,
        int phaseLength
    )
    {
        _dayLabel.Text = $"第 {currentDay} 天";
        _phaseLabel.Text = isNight ? "夜晚" : "白天";
        _timeLabel.Text = $"{phaseProgress} / {phaseLength}";

        _phaseProgress.MinValue = 0;
        _phaseProgress.MaxValue = phaseLength;
        _phaseProgress.Value = phaseProgress;
    }

    private int ReadInt(StringName propertyName, int fallback)
    {
        Variant value = _timeSystem.Get(propertyName);
        return value.VariantType is Variant.Type.Int or Variant.Type.Float
            ? value.AsInt32()
            : fallback;
    }

    private bool ReadBool(StringName propertyName, bool fallback)
    {
        Variant value = _timeSystem.Get(propertyName);
        return value.VariantType == Variant.Type.Bool ? value.AsBool() : fallback;
    }
}
