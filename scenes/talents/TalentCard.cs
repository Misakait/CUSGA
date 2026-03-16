using Godot;
using System;

namespace CUSGA.resources.talents;

public partial class TalentCard : Control
{
    public event Action<TalentData> OnCardClicked;

    private TalentData _talentData;

    [Export] private Label _titleLabel;
    [Export] private RichTextLabel _descLabel;
    [Export] private Button _clickArea;
    [Export] private TextureRect _texture;

    public override void _Ready()
    {
        _clickArea.Pressed += () =>
        {
            if (_talentData != null) OnCardClicked?.Invoke(_talentData);
        };
    }

    public void Initialize(TalentData data)
    {
        _talentData = data;

        if (_titleLabel != null) _titleLabel.Text = data.TalentName;
        if (_descLabel != null) _descLabel.Text = data.Description;
        if (_texture != null) _texture.Texture = data.TalentTexture;
    }
}
