using Godot;
using System;
using CUSGA.core.interfaces;

[GlobalClass]
public partial class HealthComponent : StatComponentBase, IDamageable
{
	// 血量专属信号：受伤带属性
	[Signal]
	public delegate void DamageTakenEventHandler(int amount, int elementType);

	public void TakeDamage(int amount, ElementType elementType)
	{
		if (_currentValue <= 0) return;
		EmitSignal(SignalName.DamageTaken, amount, (int)elementType);
		Subtract(amount);
	}

}
