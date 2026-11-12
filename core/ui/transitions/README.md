# UITransition 界面过渡组件

本目录提供轻缩放、上浮、侧滑和淡入淡出。组件只处理界面的位置、比例、透明度与过渡期间的鼠标遮罩，不依赖 CUSGA 的单例、库存、地图或暂停系统。

## 在新界面中使用

1. 将 `ui_transition.tscn` 从文件系统拖到新界面的场景树中。
2. 选中生成的 `UITransition` 节点，在检查器中展开 `Target Paths`，添加要动画的 `Control` 或 `Node2D` 路径。路径相对于组件节点；例如组件和 `Panel` 同级时填写 `../Panel`。
3. 在 `Motion Style` 选择效果，再调整打开时长、缩放幅度与错峰间隔。
4. 打开时先显示面板，再调用 `play_open()`；关闭时把隐藏操作作为 `play_close()` 的完成回调。

场景结构示例：

```text
MyUI
├── Panel
└── UITransition       # Target Paths = [../Panel]
```

界面脚本中的用法：

```gdscript
@onready var panel: Control = $Panel
@onready var transition: UITransition = $UITransition

## 显示面板并播放入场；无参数，无返回值。
func open_panel() -> void:
	panel.show()
	transition.play_open()

## 播放退场，完成后隐藏面板；无参数，无返回值。
func close_panel() -> void:
	transition.play_close(panel.hide)
```

组件不会自动显示或隐藏目标。关闭时不能立即调用 `hide()`，否则看不到退场。打开中改为关闭、关闭中改为打开会从当前状态继续；使用 `is_open_requested()` 判断目标打开状态，使用 `is_animating()` 判断是否仍在过渡。

## 用代码创建

```gdscript
var transition := UITransition.new()
add_child(transition)
transition.setup([$Panel], 0.02, 0.22, 0.0, UITransition.MotionStyle.SOFT_SCALE)
```

`setup(targets, strength = 0.02, duration = 0.22, stagger = 0.0, style = MotionStyle.SOFT_SCALE)` 的目标必须是互不重复、互非父子的 `Control` 或 `Node2D`。显式 `setup()` 的配置优先于入树时的检查器初始化。运行中修改检查器字段后，调用 `configure_from_inspector()` 重新应用；有效时返回 `true`，无效时返回 `false` 并保留上一份配置。

| 检查器字段 | 含义 | 默认值 |
| --- | --- | --- |
| `target_paths` | 相对于组件的动画目标路径数组 | 空；代码配置模式可留空 |
| `motion_style` | `SOFT_SCALE` 轻缩放、`RISE` 上浮、`SLIDE` 侧滑、`FADE` 淡入淡出 | `SOFT_SCALE` |
| `scale_strength` | 仅轻缩放使用，实际限制为 `0～0.04` | `0.02`，即 2% |
| `open_duration` | 单个目标的打开秒数，最少 `0.1` | `0.22` 秒 |
| `target_stagger` | 相邻目标开始打开的间隔，最少 `0` | `0` 秒，同步播放 |

打开总时长为 `open_duration + target_stagger × max(目标数量 - 1, 0)`，另加首次布局等待。关闭时长固定为 `UITransition.CLOSE_DURATION = 0.14` 秒，不错峰。上浮打开位移为 `(0, 12)`，关闭为 `(0, 6)`；侧滑打开为 `(16, 0)`，关闭为 `(8, 0)`，单位均为视口像素。轻缩放打开从 `1 - strength` 到 `1`，关闭到 `1 - strength / 2`。淡入淡出保持位置与比例不变。

## 接入约束

- 动画目标不能同时包含父节点和它的子节点，外框与内容需要同步时错峰设为 `0`。
- 选择不会被父 `Container` 每帧重排位置的承载层；不要让另一套动画同时写入相同目标的位置、比例或颜色。
- 业务代码负责键盘门禁、暂停和导航；组件在游戏暂停时仍会播放，不会自行改变暂停状态。
- `reset()` 取消动画和旧回调、恢复原始属性；不清除已配置的目标，缓存界面再次进入时可直接播放。
- `resume_open()` 用于外部视图已直接显示面板、但过渡仍记录为关闭的情况：先 `reset()` 取消残留退场，再把打开状态置为真，不重播入场。
- 组件离树会自动 `reset()`。宿主需要立即取消显示流程时也可以主动调用它。

## 兼容与复制

现有 `core/ui/ui_jelly_transition.gd` 是继承本组件的兼容入口，新界面直接使用本目录。动画实现只维护一份。

复制到另一个 Godot 4.7.1 项目时，将本目录（包括 UID 文件）放到相同的 `core/ui/transitions/` 路径，然后等待编辑器扫描即可。目录内没有 CUSGA 业务依赖。若要更换存放路径，使用 Godot 文件系统面板移动，让场景的脚本引用同步更新。
