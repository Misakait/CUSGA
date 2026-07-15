using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using CUSGA.core.application;
using CUSGA.core.crafting;
using CUSGA.entities.components;
using CUSGA.resources.crafting;
using CUSGA.resources.item;

namespace CUSGA.core.ui.crafting;

/// <summary>
/// 展示配方、材料持有量并处理合成操作的界面。
/// </summary>
public partial class CraftingUI : Control
{
    /// <summary>
    /// 获取或设置用于接收合成界面切换请求的游戏端口路径。
    /// </summary>
    [Export] public NodePath GameplayPortPath { get; set; }

    private GameplayPort _gameplayPort = null!;
    private CraftingComponent _crafting = null!;
    private InventoryComponent _inventory = null!;
    private GridContainer _recipeGrid = null!;
    private VBoxContainer _ingredientList = null!;
    private TextureRect _outputIcon = null!;
    private Label _outputNameLabel = null!;
    private Label _outputDescriptionLabel = null!;
    private SpinBox _quantitySpinBox = null!;
    private Button _craftButton = null!;
    private Label _statusLabel = null!;
    private CraftingRecipe _selectedRecipe;
    private readonly Dictionary<CraftingRecipe, Button> _recipeButtons = [];
    private bool _needsInventoryRefresh;

    /// <summary>
    /// 初始化界面控件并订阅游戏端口事件。
    /// </summary>
    public override void _Ready()
    {
        _recipeGrid = GetNode<GridContainer>("%RecipeGrid");
        _ingredientList = GetNode<VBoxContainer>("%IngredientList");
        _outputIcon = GetNode<TextureRect>("%OutputIcon");
        _outputNameLabel = GetNode<Label>("%OutputNameLabel");
        _outputDescriptionLabel = GetNode<Label>("%OutputDescriptionLabel");
        _quantitySpinBox = GetNode<SpinBox>("%QuantitySpinBox");
        _craftButton = GetNode<Button>("%CraftButton");
        _statusLabel = GetNode<Label>("%StatusLabel");

        GetNode<Button>("%CloseButton").Pressed += Close;
        _quantitySpinBox.ValueChanged += OnQuantityChanged;
        _craftButton.Pressed += OnCraftButtonPressed;

        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _gameplayPort.CraftingToggleRequested += HandleCraftingToggleRequest;
        VisibilityChanged += OnVisibilityChanged;

        Hide();
    }

    private void HandleCraftingToggleRequest(CraftingComponent crafting)
    {
        if (crafting == null)
        {
            GD.PushError("CraftingUI 收到空 CraftingComponent。");
            return;
        }

        if (Visible)
        {
            Close();
            return;
        }

        Open(crafting);
    }

    /// <summary>
    /// 绑定合成组件、刷新当前配方并显示界面。
    /// </summary>
    /// <param name="crafting">要展示的合成组件。</param>
    public void Open(CraftingComponent crafting)
    {
        BindCrafting(crafting);
        GenerateRecipeButtons();

        if (_selectedRecipe == null || !_crafting.Recipes.Contains(_selectedRecipe))
        {
            SelectRecipe(_crafting.Recipes.FirstOrDefault());
        }
        else
        {
            RefreshSelectedRecipe();
        }

        _needsInventoryRefresh = false;
        Show();
    }

    /// <summary>
    /// 隐藏合成界面。
    /// </summary>
    public void Close()
    {
        Hide();
    }

    private void BindCrafting(CraftingComponent crafting)
    {
        if (_crafting == crafting)
        {
            return;
        }

        DisconnectInventorySignal();

        _crafting = crafting;
        _inventory = crafting.Inventory;
        if (_inventory != null)
        {
            _inventory.InventoryChanged += OnInventoryChanged;
        }

        _selectedRecipe = null;
        _statusLabel.Text = "";
    }

    private void GenerateRecipeButtons()
    {
        foreach (Node child in _recipeGrid.GetChildren())
        {
            child.QueueFree();
        }

        _recipeButtons.Clear();

        foreach (var recipe in _crafting.Recipes)
        {
            Texture2D icon = recipe.OutputItem?.DisplayIcon;
            var button = new Button
            {
                CustomMinimumSize = new Vector2(64, 56),
                ToggleMode = true,
                Icon = icon,
                ExpandIcon = true,
                Text = icon == null ? GetItemName(recipe.OutputItem) : "",
                TooltipText = GetRecipeTitle(recipe),
                FocusMode = FocusModeEnum.None
            };

            var selectedRecipe = recipe;
            button.Pressed += () => SelectRecipe(selectedRecipe);
            _recipeGrid.AddChild(button);
            _recipeButtons[recipe] = button;
        }
    }

    private void SelectRecipe(CraftingRecipe recipe)
    {
        _selectedRecipe = recipe;
        _statusLabel.Text = "";
        RefreshSelectedRecipe();
    }

    private void RefreshSelectedRecipe()
    {
        RefreshRecipeButtonSelection();

        if (_selectedRecipe == null)
        {
            _outputIcon.Texture = null;
            _outputNameLabel.Text = "";
            _outputDescriptionLabel.Text = "";
            ClearIngredientList();
            _quantitySpinBox.Value = 1;
            _quantitySpinBox.Editable = false;
            _craftButton.Disabled = true;
            return;
        }

        if (_selectedRecipe.OutputItem == null)
        {
            _outputIcon.Texture = null;
            _outputNameLabel.Text = GetRecipeTitle(_selectedRecipe);
            _outputDescriptionLabel.Text = "";
            ClearIngredientList();
            _quantitySpinBox.Value = 1;
            _quantitySpinBox.Editable = false;
            _craftButton.Disabled = true;
            return;
        }

        _outputIcon.Texture = _selectedRecipe.OutputItem.DisplayIcon;
        _outputNameLabel.Text = GetRecipeTitle(_selectedRecipe);
        _outputDescriptionLabel.Text = _selectedRecipe.OutputItem.DisplayDescription ?? "";

        int maxCraftable = _crafting.MaxCraftableQuantity(_selectedRecipe);
        _quantitySpinBox.MinValue = 1;
        _quantitySpinBox.MaxValue = Math.Max(1, maxCraftable);
        _quantitySpinBox.Editable = maxCraftable > 0;
        if (_quantitySpinBox.Value < 1)
        {
            _quantitySpinBox.Value = 1;
        }
        else if (_quantitySpinBox.Value > _quantitySpinBox.MaxValue)
        {
            _quantitySpinBox.Value = _quantitySpinBox.MaxValue;
        }

        _craftButton.Disabled = maxCraftable <= 0;
        RefreshIngredientList(GetCraftQuantity());
    }

    private void RefreshRecipeButtonSelection()
    {
        foreach (var pair in _recipeButtons)
        {
            pair.Value.ButtonPressed = pair.Key == _selectedRecipe;
        }
    }

    private void RefreshIngredientList(int quantity)
    {
        ClearIngredientList();

        foreach (var requirement in BuildIngredientTotals(_selectedRecipe, quantity))
        {
            int owned = _inventory.ItemCnt(requirement.Key);
            var row = new HBoxContainer
            {
                CustomMinimumSize = new Vector2(0, 36)
            };

            var icon = new TextureRect
            {
                Texture = requirement.Key.DisplayIcon,
                CustomMinimumSize = new Vector2(32, 32),
                ExpandMode = TextureRect.ExpandModeEnum.FitWidthProportional,
                StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered
            };
            row.AddChild(icon);

            var label = new Label
            {
                Text = $"{GetItemName(requirement.Key)}  需要 {requirement.Value} / 拥有 {owned}",
                VerticalAlignment = VerticalAlignment.Center,
                SizeFlagsHorizontal = SizeFlags.ExpandFill
            };

            if (owned < requirement.Value)
            {
                label.AddThemeColorOverride("font_color", new Color(1f, 0.32f, 0.24f));
            }

            row.AddChild(label);
            _ingredientList.AddChild(row);
        }
    }

    private void ClearIngredientList()
    {
        foreach (Node child in _ingredientList.GetChildren())
        {
            child.QueueFree();
        }
    }

    private void OnQuantityChanged(double value)
    {
        if (_selectedRecipe != null)
        {
            RefreshIngredientList(GetCraftQuantity());
        }
    }

    private void OnCraftButtonPressed()
    {
        if (_selectedRecipe == null)
        {
            return;
        }

        int quantity = GetCraftQuantity();
        if (_crafting.TryCraft(_selectedRecipe, quantity, out var failureReason))
        {
            int outputAmount = _selectedRecipe.OutputAmount * quantity;
            _statusLabel.Text = $"已合成 {GetItemName(_selectedRecipe.OutputItem)} x{outputAmount}";
            RefreshSelectedRecipe();
            return;
        }

        _statusLabel.Text = failureReason switch
        {
            CraftingFailureReason.MissingMaterials => "材料不足",
            CraftingFailureReason.NotEnoughSpace => "背包空间不足",
            CraftingFailureReason.InvalidQuantity => "数量无效",
            _ => "配方无效"
        };
        RefreshSelectedRecipe();
    }

    private void OnInventoryChanged()
    {
        if (!IsVisibleInTree())
        {
            // 父级 HUD 也会隐藏此节点；记录一次脏状态，恢复有效可见性后再合并刷新。
            _needsInventoryRefresh = true;
            return;
        }

        if (_selectedRecipe != null)
        {
            RefreshSelectedRecipe();
        }

        _needsInventoryRefresh = false;
    }

    private void OnVisibilityChanged()
    {
        if (!_needsInventoryRefresh || !IsVisibleInTree())
        {
            return;
        }

        if (_selectedRecipe != null)
        {
            RefreshSelectedRecipe();
        }

        _needsInventoryRefresh = false;
    }

    private int GetCraftQuantity()
    {
        return Math.Max(1, (int)Math.Round(_quantitySpinBox.Value));
    }

    private static Dictionary<ItemData, int> BuildIngredientTotals(CraftingRecipe recipe, int quantity)
    {
        Dictionary<ItemData, int> totals = [];
        if (recipe?.Inputs == null)
        {
            return totals;
        }

        foreach (var ingredient in recipe.Inputs)
        {
            if (ingredient?.RequiredItem == null || ingredient.Amount <= 0)
            {
                continue;
            }

            int requiredAmount = ingredient.Amount * quantity;
            if (totals.TryGetValue(ingredient.RequiredItem, out int currentAmount))
            {
                requiredAmount += currentAmount;
            }

            totals[ingredient.RequiredItem] = requiredAmount;
        }

        return totals;
    }

    private static string GetRecipeTitle(CraftingRecipe recipe)
    {
        if (!string.IsNullOrWhiteSpace(recipe?.RecipeName))
        {
            return recipe.RecipeName;
        }

        return GetItemName(recipe?.OutputItem);
    }

    private static string GetItemName(ItemData item)
    {
        if (item == null)
        {
            return "";
        }

        if (!string.IsNullOrWhiteSpace(item.DisplayName))
        {
            return item.DisplayName;
        }

        return item.CardName ?? "";
    }

    private void DisconnectInventorySignal()
    {
        if (_inventory != null)
        {
            _inventory.InventoryChanged -= OnInventoryChanged;
        }
    }

    /// <summary>
    /// 退出场景树时断开游戏端口与库存事件。
    /// </summary>
    public override void _ExitTree()
    {
        if (_gameplayPort != null)
        {
            _gameplayPort.CraftingToggleRequested -= HandleCraftingToggleRequest;
        }

        VisibilityChanged -= OnVisibilityChanged;
        DisconnectInventorySignal();
    }
}
