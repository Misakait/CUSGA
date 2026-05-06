using Godot;
using System;

namespace CUSGA.core.autoloads;

public partial class TimeSystem : Node
{

    public static TimeSystem Instance { get; private set; }
    // 昼夜更替广播
    [Signal] public delegate void DayNightToggledEventHandler(bool isNight);

    // 天数增加广播
    [Signal] public delegate void DayPassedEventHandler(int currentDay);

    // 触发天赋选择界面广播
    [Signal] public delegate void TalentSelectionTriggeredEventHandler();

    [Signal]
    public delegate void TimeChangedEventHandler(
        int totalTimePassed,
        int currentDay,
        bool isNight,
        int phaseProgress,
        int phaseLength
    );

    private int _totalTimePassed = 0; // 记录开局以来的总时间流逝
    private int _currentDay = 1;
    public const int PhaseLength = 100;

    public int TotalTimePassed => _totalTimePassed;
    public int CurrentDay => _currentDay;
    public bool IsNight { get; private set; } = false;
    public int PhaseProgress => _totalTimePassed % PhaseLength;

    public override void _EnterTree()
    {
        Instance = this;
    }
    public override void _ExitTree()
    {
        if (Instance == this)
        {
            Instance = null;
        }
    }
    public override void _Ready()
    {
        EmitTimeChanged();
    }
    public void PassTime(int amount)
    {
        if (amount <= 0)
        {
            return;
        }

        int previousTime = _totalTimePassed;
        _totalTimePassed += amount;

        GD.Print($"时间流逝了 {amount} 点，当前总时间：{_totalTimePassed}");

        CheckTimeTransitions(previousTime, _totalTimePassed);
        EmitTimeChanged();
    }

    private void CheckTimeTransitions(int oldPoints, int newPoints)
    {
        int oldPhase = oldPoints / PhaseLength;
        int newPhase = newPoints / PhaseLength;

        for (int phase = oldPhase + 1; phase <= newPhase; phase++)
        {
            IsNight = !IsNight;
            EmitSignal(SignalName.DayNightToggled, IsNight);

            if (phase % 2 == 0)
            {
                _currentDay++;
                EmitSignal(SignalName.DayPassed, _currentDay);

                if (_currentDay % 7 == 0)
                {
                    EmitSignal(SignalName.TalentSelectionTriggered);
                }
            }
        }
    }
    private void EmitTimeChanged()
    {
        EmitSignal(
            SignalName.TimeChanged,
            _totalTimePassed,
            _currentDay,
            IsNight,
            PhaseProgress,
            PhaseLength
        );
    }
}
