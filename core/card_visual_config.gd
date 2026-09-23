class_name CardVisualConfig
extends RefCounted

## 卡牌视觉数值的唯一来源。
##
## 战斗手牌（`scripts/card_scripts/card_manager.gd`）与非战斗复用点
## （`core/gameflow/run_start_skill_card_draft.gd`）都从这里读取，避免同一套
## 手感在两个界面里各自演化、逐渐不一致。
##
## 这些值原本是 `CardManager` 的 `@export` 默认值。提取到这里之后，
## `CardManager` 仍然保留同名 `@export`（默认值改为引用本脚本的常量）：测试会用
## `set("scale_tween_duration", 0.0)` 把动画时长置零以短路动画，场景也需要一个
## 可覆盖的入口，因此导出名与可写性都不能丢。
##
## 只放常量、不持有状态，所以继承 `RefCounted` 而不是 `Node`：它不需要进场景树。

## 卡牌常态缩放。
const CARD_NORMAL_SCALE: Vector2 = Vector2(1.0, 1.0)

## 卡牌被鼠标悬停时的放大倍率。
const CARD_HOVER_SCALE: Vector2 = Vector2(1.05, 1.05)

## 缩放动画的过渡时间（秒）。取值较短，悬停反馈才跟手。
const SCALE_TWEEN_DURATION: float = 0.08

## 卡牌常态渲染层级。
const CARD_Z_INDEX_NORMAL: int = 1

## 卡牌被悬停时的渲染层级：抬高到其他卡牌之上，避免放大后被邻居压住。
const CARD_Z_INDEX_HOVER: int = 2

## 选中卡牌向上移动的距离（像素）。
## 该值独立于悬停缩放，确保玩家即使移开鼠标也能识别出待确认的卡牌。
const CLICK_SELECTED_LIFT_DISTANCE: float = 36.0

## 选中卡牌上移所用的时间（秒）。
const CLICK_SELECTED_LIFT_DURATION: float = 0.12
