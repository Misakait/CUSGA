using Godot;
using CUSGA.core.autoloads;

namespace CUSGA.core.ui.hud;

public partial class TimePanelUI : Control
{
    private Label _dayLabel = null!;
    private Label _phaseLabel = null!;
    private Label _timeLabel = null!;
    private ProgressBar _phaseProgress = null!;

    public override void _Ready()
    {
        _dayLabel = GetNode<Label>("%DayLabel");
        _phaseLabel = GetNode<Label>("%PhaseLabel");
        _timeLabel = GetNode<Label>("%TimeLabel");
        _phaseProgress = GetNode<ProgressBar>("%PhaseProgress");

        TimeSystem.Instance.TimeChanged += OnTimeChanged;

        Refresh(
            TimeSystem.Instance.TotalTimePassed,
            TimeSystem.Instance.CurrentDay,
            TimeSystem.Instance.IsNight,
            TimeSystem.Instance.PhaseProgress,
            TimeSystem.PhaseLength
        );
    }

    public override void _ExitTree()
    {
        if (TimeSystem.Instance != null)
        {
            TimeSystem.Instance.TimeChanged -= OnTimeChanged;
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
}
