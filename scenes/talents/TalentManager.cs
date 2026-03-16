using CUSGA.core.autoloads;
using Godot;
using System;
using System.Collections.Generic;

namespace CUSGA.resources.talents;

public partial class TalentManager : CanvasLayer
{
    [Export] public Godot.Collections.Array<TalentData> AllTalentsPool;
    [Export] public PackedScene CardScenePrefab;
    [Export] public HBoxContainer CardsContainer;

    public event Action<TalentData> OnTalentAcquired;
    private readonly Random _random = new();
    private List<TalentData> _availableTalents = [];

    public override void _Ready()
    {
        Hide();
        _availableTalents = [.. AllTalentsPool];
        var timeSystem = GetNode<TimeSystem>("/root/TimeSystem");
        timeSystem.TalentSelectionTriggered += PopUpTalentSelection;
    }

    private void PopUpTalentSelection()
    {
        if (_availableTalents.Count == 0)
        {
            GD.Print("天赋已全部学完，没有可用的天赋卡了！");
            return;
        }

        GetTree().Paused = true;
        Show();
        DrawThreeTalents();
    }

    public void OnTalentSelected(TalentData selectedTalent)
    {
        GD.Print($"玩家选择了天赋：{selectedTalent.TalentName}");
        // 从牌堆移除此牌
        _availableTalents.Remove(selectedTalent);
        OnTalentAcquired?.Invoke(selectedTalent);

        Hide();
        GetTree().Paused = false;
    }

    private void DrawThreeTalents()
    {
        // 洗牌
        for (int i = _availableTalents.Count - 1; i > 0; i--)
        {
            int j = _random.Next(i + 1);
            (_availableTalents[i], _availableTalents[j]) = (_availableTalents[j], _availableTalents[i]);
        }

        // 清除上一次挂载的卡牌资源
        foreach (Node child in CardsContainer.GetChildren())
        {
            child.QueueFree();
        }

        int drawCount = Mathf.Min(3, _availableTalents.Count);

        for (int i = 0; i < drawCount; i++)
        {
            TalentData data = _availableTalents[i];
            TalentCard newCard = CardScenePrefab.Instantiate<TalentCard>();

            CardsContainer.AddChild(newCard);

            newCard.Initialize(data);
            newCard.OnCardClicked += OnTalentSelected;
        }
    }
}
