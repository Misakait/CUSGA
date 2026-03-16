using Godot;
using System;

namespace CUSGA.core.autoloads;

public partial class TimeSystem : Node
{

	// 昼夜更替广播
	[Signal] public delegate void DayNightToggledEventHandler(bool isNight);

	// 天数增加广播
	[Signal] public delegate void DayPassedEventHandler(int currentDay);

	// 触发天赋选择界面广播
	[Signal] public delegate void TalentSelectionTriggeredEventHandler();

	private int _totalTimePassed = 0; // 记录开局以来的总时间流逝
	private int _currentDay = 1;
	private bool _isNight = false;

	public void PassTime(int amount)
	{
		int previousTime = _totalTimePassed;
		_totalTimePassed += amount;

		GD.Print($"时间流逝了 {amount} 点，当前总时间：{_totalTimePassed}");

		CheckTimeTransitions(previousTime, _totalTimePassed);
	}

	private void CheckTimeTransitions(int oldPoints, int newPoints)
	{
		int oldPhase = oldPoints / 100;
		int newPhase = newPoints / 100;

		if (newPhase > oldPhase)
		{
			_isNight = !_isNight; // 昼夜翻转
			EmitSignal(SignalName.DayNightToggled, _isNight);

			// 如果阶段是偶数，说明新的一天开始了
			if (newPhase % 2 == 0)
			{
				_currentDay++;
				EmitSignal(SignalName.DayPassed, _currentDay);

				// 触发天赋选择
				if (_currentDay % 7 == 0)
				{
					EmitSignal(SignalName.TalentSelectionTriggered);
				}
			}
		}
	}
}
