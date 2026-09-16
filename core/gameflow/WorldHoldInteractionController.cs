using System;
using Godot;
using CUSGA.core.constants;
using CUSGA.core.ui.hud;

namespace CUSGA.core.gameflow;

/// <summary>
/// 协调局外长按的唯一活动状态、进度反馈、取消处理与完成回调。
/// </summary>
public partial class WorldHoldInteractionController : Node
{
    // 主场景 HUD 的稳定相对路径；属性默认值与空值恢复共用此常量，避免两处配置漂移。
    private const string DefaultProgressIndicatorPath = "../../../UI/HUDLayer/HUDRoot/WorldHoldProgressIndicator";

    /// <summary>
    /// 指向负责绘制鼠标圆形进度条的 HUD 组件；默认值匹配主场景结构，防止场景导出值未反序列化时退化为空路径。
    /// </summary>
    [Export]
    public NodePath ProgressIndicatorPath { get; set; } = new(DefaultProgressIndicatorPath);

    /// <summary>
    /// 获取当前是否存在尚未完成或取消的局外长按。
    /// </summary>
    public bool IsHolding => _activeOwner != null;

    // 只负责表现的圆环 UI，不保存或修改任何游戏状态。
    private WorldHoldProgressIndicator _progressIndicator = null!;

    // 正在插值进度的 Tween；取消时必须终止它以阻止延迟完成回调。
    private Tween _holdTween;

    // 发起当前长按的节点；用于阻止其他目标在同一时刻结算。
    private Node _activeOwner;

    // 只有进度完成时才调用的业务回调；取消路径必须清空它。
    private Callable _completionCallback;

    /// <summary>
    /// 解析 HUD 依赖并确保初始状态没有残留圆环。
    /// </summary>
    public override void _Ready()
    {
        if (ProgressIndicatorPath.IsEmpty)
        {
            // 运行时导出值可能因程序集热重载保持为空；恢复默认值可让当前游戏实例继续工作。
            GD.PushWarning("WorldHoldInteractionController.ProgressIndicatorPath 为空，已恢复主场景默认圆环路径。");
            ProgressIndicatorPath = new NodePath(DefaultProgressIndicatorPath);
        }

        _progressIndicator = GetNodeOrNull<WorldHoldProgressIndicator>(ProgressIndicatorPath)
            ?? throw new InvalidOperationException(
                $"WorldHoldInteractionController 无法解析圆环节点：{ProgressIndicatorPath}"
            );
        _progressIndicator.ClearHoldProgress();
    }

    /// <summary>
    /// 节点离开场景时终止尚未完成的长按，避免回调指向已经失效的局外视图。
    /// </summary>
    public override void _ExitTree()
    {
        CancelActiveHold();
    }

    /// <summary>
    /// 开始一个由行动值决定时长的局外长按。
    /// </summary>
    /// <param name="owner">发起交互的有效节点；新目标会取消先前目标的长按。</param>
    /// <param name="actionPointCost">本次交互实际消耗的行动值。</param>
    /// <param name="onCompleted">仅在进度完成后调用的无参业务回调。</param>
    /// <param name="progressTarget">用于绘制圆环的可见目标；为空时 HUD 会安全回退到鼠标位置。</param>
    public void BeginHold(Node owner, int actionPointCost, Callable onCompleted, Node progressTarget)
    {
        ArgumentNullException.ThrowIfNull(owner);

        CancelActiveHold();

        // 零消耗交互无需等待，直接回调以保留掉落拾取等即时交互的既有体验。
        if (actionPointCost <= 0)
        {
            onCompleted.Call();
            return;
        }

        _activeOwner = owner;
        _completionCallback = onCompleted;
        _progressIndicator.SetHoldProgressTarget(progressTarget);
        _progressIndicator.SetHoldProgress(0.0f);

        float durationSeconds = WorldInteractionTiming.GetHoldDurationSeconds(actionPointCost);
        _holdTween = CreateTween();
        _holdTween.TweenMethod(
            Callable.From<float>(_progressIndicator.SetHoldProgress),
            0.0f,
            1.0f,
            durationSeconds
        );
        _holdTween.Finished += CompleteActiveHold;
    }

    /// <summary>
    /// 仅当指定节点拥有当前长按时取消它，避免一个目标的释放误取消另一目标。
    /// </summary>
    /// <param name="owner">请求取消的交互节点。</param>
    public void CancelHoldFor(Node owner)
    {
        if (owner == null || _activeOwner != owner)
        {
            return;
        }

        CancelActiveHold();
    }

    /// <summary>
    /// 无条件取消当前长按，供全局鼠标释放、场景退出等兜底路径调用。
    /// </summary>
    public void CancelActiveHold()
    {
        if (_holdTween != null && _holdTween.IsValid())
        {
            _holdTween.Kill();
        }

        _holdTween = null;
        _activeOwner = null;
        _completionCallback = default;
        _progressIndicator?.ClearHoldProgress();
    }

    // Tween 完成后先清理输入状态与表现，再调用业务逻辑，避免完成回调重入时产生双重交互。
    private void CompleteActiveHold()
    {
        Node completedOwner = _activeOwner;
        Callable completedCallback = _completionCallback;

        _holdTween = null;
        _activeOwner = null;
        _completionCallback = default;
        _progressIndicator.ClearHoldProgress();

        if (completedOwner != null
            && IsInstanceValid(completedOwner))
        {
            completedCallback.Call();
        }
    }
}
