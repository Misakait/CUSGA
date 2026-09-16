using Godot;

namespace CUSGA.core.ui.hud;

/// <summary>
/// 在鼠标位置附近绘制局外长按进度圆环的 HUD 表现组件。
/// 当前圆环会锚定到交互目标的可见区域右下角，鼠标位置只作为目标缺失时的安全回退。
/// </summary>
public partial class WorldHoldProgressIndicator : Control
{
    /// <summary>
    /// 圆环中心相对鼠标位置的屏幕偏移，避免遮挡正在指向的目标。
    /// 当前默认偏移为零，使圆心落在交互目标右下角；属性名称为兼容已保存场景配置而保留。
    /// </summary>
    [Export] public Vector2 CursorOffset { get; set; } = Vector2.Zero;

    /// <summary>
    /// 进度圆环的半径，单位为屏幕像素。
    /// </summary>
    [Export(PropertyHint.Range, "8,96,1,or_greater")]
    public float RingRadius { get; set; } = 16.0f;

    /// <summary>
    /// 圆环轨道与进度弧线的宽度，单位为屏幕像素。
    /// </summary>
    [Export(PropertyHint.Range, "1,16,0.5,or_greater")]
    public float RingWidth { get; set; } = 6.0f;

    /// <summary>
    /// 未完成部分使用的半透明轨道颜色。
    /// </summary>
    [Export] public Color TrackColor { get; set; } = new(0.08f, 0.10f, 0.14f, 0.72f);

    /// <summary>
    /// 已完成部分使用的进度颜色。
    /// </summary>
    [Export] public Color ProgressColor { get; set; } = new(0.35f, 0.95f, 0.60f, 0.96f);

    /// <summary>
    /// 获取当前显示的归一化进度。
    /// </summary>
    public float CurrentProgress => _currentProgress;

    /// <summary>
    /// 获取圆环当前是否正在显示。
    /// </summary>
    public bool IsHoldProgressVisible => _isHoldProgressVisible;

    // 当前由长按控制器推送的 0 到 1 进度值。
    private float _currentProgress;

    // 用于区分“进度为零但正在等待”和“当前不应绘制”的状态。
    private bool _isHoldProgressVisible;

    // 当前长按的可见锚点；取消或完成时清空，避免 HUD 持有已离场目标。
    private CanvasItem _holdProgressTarget;

    /// <summary>
    /// 获取当前长按目标右下角的屏幕坐标；目标无效时回退到鼠标位置。
    /// </summary>
    public Vector2 CurrentHoldTargetScreenPosition => ResolveHoldTargetScreenPosition();

    /// <summary>
    /// 初始化为不接收鼠标输入且默认隐藏的 HUD 覆盖层。
    /// </summary>
    public override void _Ready()
    {
        MouseFilter = MouseFilterEnum.Ignore;
        ClearHoldProgress();
    }

    /// <summary>
    /// 在可见期间持续重绘，使圆环跟随鼠标位置移动。
    /// </summary>
    /// <param name="delta">上一帧经过的秒数。</param>
    public override void _Process(double delta)
    {
        QueueRedraw();
    }

    /// <summary>
    /// 更新并显示局外长按的归一化进度。
    /// </summary>
    /// <param name="progress">范围为 0 到 1 的完成比例；超出范围的值会被夹紧。</param>
    public void SetHoldProgress(float progress)
    {
        _currentProgress = Mathf.Clamp(progress, 0.0f, 1.0f);
        _isHoldProgressVisible = true;
        Visible = true;
        SetProcess(true);
        QueueRedraw();
    }

    /// <summary>
    /// 指定本次长按圆环应跟随的可见交互目标。
    /// </summary>
    /// <param name="target">交互目标或其可见子节点；非 CanvasItem 节点会安全回退到鼠标位置。</param>
    public void SetHoldProgressTarget(Node target)
    {
        _holdProgressTarget = target as CanvasItem;
        QueueRedraw();
    }

    /// <summary>
    /// 清空长按进度并停止鼠标跟随重绘。
    /// </summary>
    public void ClearHoldProgress()
    {
        _currentProgress = 0.0f;
        _isHoldProgressVisible = false;
        _holdProgressTarget = null;
        Visible = false;
        SetProcess(false);
        QueueRedraw();
    }

    /// <summary>
    /// 绘制进度轨道与从正上方顺时针增长的完成弧线。
    /// </summary>
    public override void _Draw()
    {
        if (!_isHoldProgressVisible)
        {
            return;
        }

        // 圆心落在目标右下角时，四分之一圆环位于目标内，其余部分位于目标外。
        Vector2 center = CurrentHoldTargetScreenPosition + CursorOffset;
        float startAngle = -Mathf.Pi / 2.0f;
        float endAngle = startAngle + Mathf.Tau;

        DrawArc(center, RingRadius, startAngle, endAngle, 48, TrackColor, RingWidth, true);
        if (_currentProgress > 0.0f)
        {
            float progressEndAngle = startAngle + Mathf.Tau * _currentProgress;
            DrawArc(center, RingRadius, startAngle, progressEndAngle, 48, ProgressColor, RingWidth, true);
        }
    }

    /// <summary>
    /// 将不同类型的目标可见区域统一换算为 HUD 所需的右下角屏幕锚点。
    /// </summary>
    /// <returns>精灵或控件右下角的屏幕坐标；没有有效目标时返回当前鼠标位置。</returns>
    private Vector2 ResolveHoldTargetScreenPosition()
    {
        if (_holdProgressTarget == null || !IsInstanceValid(_holdProgressTarget))
        {
            return GetViewport().GetMousePosition();
        }

        if (_holdProgressTarget is Sprite2D)
        {
            return _holdProgressTarget.GetScreenTransform() * ((Sprite2D)_holdProgressTarget).GetRect().End;
        }

        if (_holdProgressTarget is Control)
        {
            return _holdProgressTarget.GetScreenTransform() * ((Control)_holdProgressTarget).Size;
        }

        return _holdProgressTarget.GetScreenTransform().Origin;
    }
}
