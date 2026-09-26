# 昼夜动态滤镜 — 技术设计

## 1. 架构与边界

### 1.1 组件职责（单一职责，符合项目组件模式）

新增 **一个可复用组件**，只做一件事：把 `TimeSystem` 的时间状态换算成「世界层滤镜颜色」，并平滑追踪。

| 文件 | 类型 | 职责 |
|---|---|---|
| `core/ui/filters/day_night_filter.gd` | 脚本 | 读取 `TimeSystem` → 计算目标滤镜颜色 → 帧率无关平滑 → 写入自身 `color`。**不知道自己被挂在哪个场景、哪一层**。 |
| `scenes/ui_scenes/day_night_filter.tscn` | 场景 | 全屏锚定的 `ColorRect` + `CanvasItemMaterial(BLEND_MODE_MUL)` + 上述脚本，作为唯一可复用挂载单元。 |

组件**不负责**：场景层级选择、UI 白名单、时间推进、昼夜玩法规则。层级由各宿主场景自行决定（见 1.3），因此探索与战斗能各自采用不同的世界/UI 划分方式而复用同一份逻辑。

### 1.2 为什么不使用 Autoload 或 `CanvasModulate`

- **Autoload 单例**：全局只能存在一层，无法同时满足「探索 UI 在 `CanvasLayer` 上、战斗 UI 在默认 canvas 上」这两种不同的边界划分（见 1.4）。
- **`CanvasModulate`**：作用于整个 canvas，会连同 UI 一起变暗，与 D1/D5（UI 保持明亮）冲突。
- **`WorldEnvironment` 的 adjustment**：项目渲染后端是 `gl_compatibility`（`project.godot`），该后端的 `Environment` 调整能力有限且与 2D 玩法场景混用成本高。

结论：采用 **乘法混合的全屏覆盖层**（`ColorRect` + `BLEND_MODE_MUL`）。

### 1.3 混合模式选择（关键取舍）

`BLEND_MODE_MUL` 下最终像素为 `src * filter.rgb`：白色即完全不变，暗部不会被抬亮，符合「夜晚压暗 + 偏色」的物理直觉，也不会像 alpha 混合那样给画面蒙上一层灰雾。

- 项目已有的同类做法可参考 `scenes/player_scenes/PlayerChar.tscn:12-36` 的内联 `Shader` + `ShaderMaterial`（受击闪白），说明本项目的 2D 表现层允许使用材质覆盖。
- **已实测（实现阶段）**：`BLEND_MODE_MUL` 在 `gl_compatibility` 下正常工作。视口像素采样显示：夜晚世界像素 `Color(0.384, 0.322, 0.259)` 恰为白天原色 `Color(0.961, 0.702, 0.373)` 与滤镜色 `Color(0.400, 0.460, 0.700)` 的逐通道乘积，压暗正确且没有灰雾，回退方案未启用。
- **回退方案**：若 MUL 在该后端表现异常，改用 alpha 混合的深色覆盖（`color = Color(night_rgb, strength)`），观感为「蒙雾」而非「乘算压暗」，验收标准 AC1/AC2 不变。

### 1.4 挂载点与层级（两个场景分别处理）

**探索场景 `scenes/Main.tscn`（根 `Main`）**

- 世界内容全部位于默认 canvas（layer 0）：`MapSystem`（房间精灵、`DoorController`）、`BoardSystem`（棋盘卡牌、建筑）、`PlayerChar`（第 301 行）。
- 世界内容最高 `z_index` 为 **1000**：`core/board/board_card_view.gd:190`、`scripts/loot_scripts/loot_view.gd:193`。
- 探索 UI 全部在 `CanvasLayer` 内：`UI/HUDLayer`（默认 `layer = 1`）与 `MapSystem/CanvasLayer`（`scenes/map_scenes/map_control.tscn` 显式 `layer = 0`），以及 `ScreenTransitions`（Autoload，`layer = 20`）。
- **方案（已实现）**：在根下实例化 `day_night_filter.tscn`，`z_index = 1500`（高于世界最高的 1000，但仍是默认 canvas 成员）。该 `z_index` **内置在组件场景自身**，宿主场景不再写属性覆盖，避免每个挂载点各维护一份。
  - 世界内容（`z_index ≤ 1000`）→ 被压住并变暗 ✓
  - 所有 `CanvasLayer` 上的 UI（HUD、Tooltip、过场）→ 不受影响 ✓（`CanvasLayer` 画布整体位于默认 canvas 之上）
  - **不需要修改任何既有节点的 `layer` 属性**，改动面最小。
  - **已知不确定点**：`map_control.tscn` 的 `CanvasLayer` 显式写死 `layer = 0`，与默认 canvas 同层，二者的相对绘制顺序未在代码中确定。实现阶段必须实测「小地图面板打开时是否被压暗」。若被压暗，兜底方案是把该 `CanvasLayer` 的 `layer` 提升为 `2`、`UI/HUDLayer` 提升为 `3`（保持「HUD 在地图面板之上」的现状关系）；该 `CanvasLayer` 的节点路径 `../../MapSystem/CanvasLayer` 被 `core/gameflow/world_interaction_coordinator.gd` 通过 `MapCanvasLayerPath` 引用（契约见 `tests/godot/test_world_interaction_coordinator_contract.gd:128`），改 `layer` 属性**不改变路径**，因此不影响该引用。

**战斗场景 `scenes/battle_scenes/battle.tscn`（根 `Battle`）**

- 战斗世界与战斗 UI **同在默认 canvas**（战斗 HUD 不是 `CanvasLayer`），因此不能靠层级天然分离，必须显式划分。
- 事实清单：
  - 背景 `测试背景`：`z_index = -1000`（`battle.tscn:480`）
  - 战斗卡牌：`z_index = 1`（常态）/ `2`（悬停），常量在 `core/card_visual_config.gd:27,30`
  - 浮字与弹出层：`CombatFeedbackLayer` 是 `CanvasLayer`，`layer = 20` → 天然位于滤镜之上，保持明亮
  - 战斗 HUD 在两个 `Marker2D` 下：`UI`（血量条、能量条、属性面板、时间轴、设置面板、Tooltip、ClickModeActionBar）与 `Button`（`TurnEnd`、`DrawCard`）
- **方案（已实现）**：实例化 `day_night_filter.tscn`（`z_index = 1500` 内置）；并把 `UI` 与 `Button` 两个 `Marker2D` 的 `z_index` 提升为 `2000`。
  - 变暗（D5 决定的「世界」）：背景、怪物卡、手牌、玩家角色、`DeckManager`/`CardManager`/`MonsterManager`/`PlayerHand`/`ControlLock`/`PlayerManager` 内的所有内容 ✓
  - 保持明亮（D5 决定的「UI」）：`UI` 与 `Button` 下的全部 `Control` ✓
  - `Marker2D` 的子节点默认 `z_as_relative = true`，父节点提升 `z_index` 即可整体抬升，**不需要改动任何子节点的路径或属性**，因此 `battle_manager.gd:11` 的 `$UI/ActionTimeline`、`combat_feedback_director.gd:644,652` 的 `UI/BattleSettingsPanel` 等既有引用全部安全。
- **注意**：战斗卡牌悬停时 `z_index` 升到 `2`，仍远低于滤镜的 `1500`，因此卡牌不会「浮出」滤镜 ✓。

## 2. 数据流与契约

```
TimeSystem (Autoload, core/autoloads/time_system.gd)
        │  读 IsNight / get_PhaseProgress() / PhaseLength
        ▼
DayNightFilter._process(delta)
        │  计算目标颜色 → 帧率无关平滑
        ▼
ColorRect.color  (+ CanvasItemMaterial BLEND_MODE_MUL)
```

### 2.1 输入契约（只读，不新增 TimeSystem 接口）

| 来源 | 读取方式 | 依据 |
|---|---|---|
| `IsNight` | `time_system.get("IsNight")` | `core/autoloads/time_system.gd:28` |
| 阶段进度 | `time_system.call("get_PhaseProgress")` | `core/autoloads/time_system.gd:39-40` |
| 阶段长度 | `get_script_constant_map()["PhaseLength"]`（脚本常量，`Object.get()` 读不到常量） | `core/autoloads/time_system.gd:9` |

沿用 `scripts/map_scripts/UIMapWorldView.gd:23,197` 的既有风格：通过 `/root/TimeSystem` 解析 autoload，并用 `has_method` / `get` 容错，缺节点时 `push_warning` 并保持中性颜色，绝不阻断游戏。

**不订阅信号**：D3/D4 要求按阶段进度连续插值，`_process` 每帧读取当前状态即可覆盖「信号未触发但进度已变」的情况，也天然免疫「连续多次推进」造成的过渡错乱（R3）。

### 2.2 颜色曲线（D3 + D4）

令 `t = phase_progress / phase_length`，取值 `[0, 1)`：

| 阶段 | 起点（`t = 0`） | 终点（`t → 1`） | 语义 |
|---|---|---|---|
| 白天（`IsNight == false`） | `day_color`（中性白） | `dusk_color`（暖黄） | 清晨明亮 → 黄昏转暖 |
| 夜晚（`IsNight == true`） | `night_color`（冷蓝、最暗） | `dawn_color`（淡青白） | 入夜最暗 → 黎明转亮 |

阶段边界的两个端点不相等（`dusk_color → night_color`、`dawn_color → day_color`），这个跳变**由平滑跟随吸收**，正是「有过渡」的来源。

### 2.3 平滑算法（R3）

```gdscript
# 帧率无关的指数平滑：alpha 只由 delta 与时间常数决定，
# 因此掉帧、连续推进时间、重复赋值都不会累积误差或留下错误终点。
var blend := 1.0 - exp(-delta / tau)
_current_color = _current_color.lerp(target_color, blend)
color = _current_color
```

- `tau = transition_time / 3.0`，使 `transition_time` 语义为「约 95% 收敛所需秒数」，便于在检查器中直观调参。
- `_ready()` 中**直接吸附**到目标颜色（不做过渡），避免进入探索 / 进入战斗时看到一次无意义的滤镜渐变。
- 组件在 `enabled == false` 时把 `color` 固定为白色并跳过计算。

### 2.4 参数（全部 `@export`，置于脚本顶部）

| 参数 | 默认值 | 说明 |
|---|---|---|
| `enabled` | `true` | 运行期开关，便于调试对比与无障碍需求 |
| `day_color` | `Color(1, 1, 1, 1)` | 白天清晨的中性色（乘法混合下 `1,1,1` 即不改变画面） |
| `dusk_color` | `Color(1.0, 0.86, 0.68, 1)` | 黄昏暖黄，几乎不压暗，只偏暖 |
| `night_color` | `Color(0.40, 0.46, 0.70, 1)` | 夜晚冷蓝，整体亮度约为原始的 50%（与原 `night_background_tint` 的 `0.45/0.45/0.55` 手感接近，避免视觉落差过大） |
| `dawn_color` | `Color(0.82, 0.90, 0.96, 1)` | 黎明淡青白，接近白天 |
| `transition_time` | `1.0` | 平滑收敛时间（秒） |

## 3. 兼容性与既有资产

### 3.1 移除既有夜晚变暗（D2）

`scripts/map_scripts/UIMapWorldView.gd` 中以下内容在本次改造后**删除**：

- 常量 `ORIGINAL_BACKGROUND_SELF_MODULATE_META`（第 9 行）与 `@export var night_background_tint`（第 18 行）
- 字段 `_is_night`（第 35 行）
- `_bind_time_system()` 中对 `DayNightToggled` 的连接与 `_exit_tree()` 中的断开（第 56-59、192-203 行）
- `_on_day_night_toggled()`、`_apply_background_time_tint()`、`_find_background()`、`_get_day_background_self_modulate()`、`_multiply_color()`（第 205-235 行）
- `ensure_scene_at()` 中的 `_apply_background_time_tint(room_scene)` 调用（第 131 行）
- `@onready var time_system`（第 23 行）—— 若删除后无其它引用点则一并移除

**必须保持的语义**：`_exit_tree()` 仍需断开 `map_world_model` 的 `current_room_changed`（第 52-55 行），不得连带删除。

### 3.2 受影响的既有测试（必须同步改写）

| 测试文件 | 位置 | 现断言 | 改造后 |
|---|---|---|---|
| `tests/godot/passage_guard_tests.gd` | `:291-326` | 夜晚把房间 `Background.self_modulate` 乘暗为 `Color(0.45, 0.45, 0.55, 1)`，且不影响其它 `Sprite` | 改为断言：房间背景 `self_modulate` **不再被时间系统修改**（保持调用前的原值）；复制房间仍保持原值。原设计意图「夜晚战斗背景保留变暗」由全局滤镜在战斗场景生效来承载，测试中改为断言战斗场景存在滤镜节点 |
| `tests/godot/test_reusable_gathering_interaction.gd` | `:893,906` | 夜间背景变暗效果被复制 | 同上，改为断言背景色不再被改动 |

改写时**不得删除测试**，只把契约从「背景自变暗」迁移到「背景保持原值 + 滤镜层承担变暗」。

### 3.3 文档同步（AGENTS.md 规范二）

`docs/游戏机制与玩法内容.md` 需新增/改写昼夜表现段落，记录：滤镜作用范围（探索 + 战斗世界层）、四段颜色与默认数值、`transition_time`、以及「房间背景自变暗已移除」的事实与原因。

### 3.4 不涉及的场景

`scenes/main_menu_scenes/main_menu.tscn`、`scenes/Warehouse/Warehouse.tscn`、`scenes/Shop/Shop.tscn`（由 `core/autoloads/SceneManager.gd:7-11` 管理）为纯 UI 场景，没有「世界层」，不挂滤镜。

## 4. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| `BLEND_MODE_MUL` 在 `gl_compatibility` 下表现异常 | 夜色不正确 | 实现阶段截图验证；回退到 alpha 混合（见 1.3） |
| `map_control.tscn` 的 `CanvasLayer(layer = 0)` 被滤镜压暗 | **已实测未被压暗**（纯黑滤镜下该面板最大亮度仍为 `0.349`、943 个亮像素） | 兜底方案未启用，所有既有 `layer` 保持原值 |
| 战斗 UI 提升 `z_index` 后仍有个别 `Control` 被压暗 | HUD 可读性 | 逐个截图核对；必要时给对应节点单独提高 `z_index` |
| 删除 `UIMapWorldView` 变暗逻辑破坏其它调用方 | 运行时错误 | 删除前用 `rg` 全量检索 `night_background_tint`、`_apply_background_time_tint`、`_on_day_night_toggled`、`ORIGINAL_BACKGROUND_SELF_MODULATE_META` 的引用 |
| 战斗场景新增节点导致既有测试的场景结构断言失败 | 测试失败 | 新增节点放在根下、命名独立；核对 `tests/godot/` 中读取 `battle.tscn` / `Main.tscn` 文本的契约测试 |

**回滚点**：滤镜是新增文件，撤除挂载节点即可回到原状；`UIMapWorldView` 的删除与测试改写是唯一破坏性改动，通过 Git 单次提交隔离，必要时 revert。

## 5. 实现阶段必须实测的验证点

1. `editor_screenshot(source="game")` 确认 MUL 混合在 `gl_compatibility` 下生效，且白天/夜晚差异肉眼可辨。
2. 探索场景：卡牌（`z_index = 1000`）与掉落物是否被滤镜压住变暗。
3. 探索场景：`map_control` 小地图面板打开时是否被压暗（决定是否启用兜底 `layer` 调整）。
4. 战斗场景：血量条 / 能量条 / 属性面板 / 按钮 / 设置面板保持明亮；背景、怪物卡、手牌、玩家变暗。
5. 战斗场景：浮字（`CombatFeedbackLayer`，`layer = 20`）不被压暗。
6. 昼夜切换与连续推进时间时，画面为渐变而非跳变；进入战斗时无滤镜初帧闪烁。

## 6. 实现结果与偏差（实现阶段回填）

### 6.1 与设计不符、以实现为准的点

| 项 | 设计原写法 | 实际实现 | 原因 |
|---|---|---|---|
| `CanvasItemMaterial.blend_mode` | `1` | **`3`** | `BLEND_MODE_MUL` 的枚举值是 `3`，`1` 是 `BLEND_MODE_ADD`；写错不报错，只会得到发白的画面。已用 `api_manage(op="get_class")` 核实。 |
| 探索 / 战斗的 `z_index` | 挂载后由宿主场景设置 `1500` | 内置在 `day_night_filter.tscn` 的根节点 | 避免每个挂载点重复维护同一数值 |
| 阶段长度读取 | `time_system.get("PhaseLength")` | `get_script_constant_map()["PhaseLength"]` | `Object.get()` 只读属性，读不到脚本常量 |
| 验证手段 | `editor_screenshot` 目视确认 | `game_eval` + 视口像素采样 | 当前 agent 无法读取图像内容；程序化采样更精确、可复现，并能区分「内容被压暗」与「UI 半透明透出被压暗的世界」 |

### 6.2 实现阶段新发现的阻塞问题（已修复）

**全屏 `Control` 挂在 `Node2D` 下会静默失效。** 战斗场景根节点是 `Node2D`，而 `Control` 的 anchors 以父级 `CanvasItem` 的 `anchorable_rect` 为参考；`Node2D` 的该矩形为空，于是全屏 anchors 算出 `size = (0, 0)`。此时滤镜照常进树、`visible` 为 `true`、`color` 可正常读写，但画面**没有任何变化，且不产生任何报错**。探索场景的根是普通 `Node`（非 `CanvasItem`），会回退到视口矩形，因此同一份组件在探索中正常、在战斗中失效——这种「一个场景好、另一个场景坏」的现象极易被误判成层级配错。

修复：脚本 `_ready()` 调用 `_fit_to_viewport()`，检测到退化尺寸时改用 `PRESET_TOP_LEFT` + 显式 `size = get_viewport_rect().size`。已由 `tests/godot/test_day_night_filter_contract.gd::test_day_night_filter_fits_viewport_under_node2d_parent` 锁定，并写入 `.trellis/spec/frontend/component-guidelines.md` 的「全屏覆盖层」小节。

### 6.3 验证结果

| 验证点 | 结果 |
|---|---|
| 颜色曲线（白天转暖 / 夜晚转亮） | 白天 `t=0 → Color(1, 1, 1)`、`t=0.99 → Color(1, 0.861, 0.683)`；夜晚 `t=0 → Color(0.40, 0.46, 0.70)`、`t=0.99 → Color(0.816, 0.896, 0.957)` ✓ |
| 过渡为渐变且收敛 | 首帧后仍在起点附近（蓝通道 `0.922`），约 2.9 秒后精确等于目标 `Color(0.610, 0.680, 0.830)` ✓ |
| 连续推进不出错（R3） | 从白天 `progress = 95` 连推 3 次跨越昼夜边界，最终精确收敛到 `Color(0.505, 0.570, 0.765)` ✓ |
| 世界被压暗 | 纯黑滤镜下世界采样点全部变黑；夜晚世界像素 = 白天原色 × 滤镜色（逐通道精确）✓ |
| UI 保持明亮（探索） | 纯黑滤镜下 HUD 文字最大亮度 `0.349`、背包按钮 `0.306`、小地图面板 `0.349` ✓ |
| UI 保持明亮（战斗） | `HpBar` / `HpText` / `PlayerAttributePanel` 为 `1.0`、`TurnEnd` 为 `0.875` ✓ |
| 浮字层不被压暗 | 纯黑滤镜下 `CombatFeedbackLayer` 内探针 Label 最大亮度为 `1.0` ✓ |
| 进入战斗无初帧渐变 | 战斗滤镜 `_ready` 后 `current == target == Color(0.61, 0.68, 0.83)` ✓ |
| 端到端流程 | 探索（夜晚）→ 真实遭遇入口进战斗 → 战斗结束返回探索：`MapSystem` 恢复可见、战斗实例已移除、滤镜保持正确、日志无任何 `SCRIPT ERROR` ✓ |
| 契约测试 | 新增 `day_night_filter_contract` 套件 4/4 通过 ✓ |

全量 `test_run()`：440 通过 / 12 失败 / 39 跳过。12 个失败经 `git status` 核对，涉及源文件（`board_controller.gd`、`campfire.tres`、`map_control.tscn` 的 uid 声明、`world_interaction_coordinator.gd` 等）均不在本次改动范围内，属既有失败。

### 6.4 测试改写实际落点

- `tests/godot/passage_guard_tests.gd`：`_test_map_instantiator_dims_loaded_backgrounds_without_touching_other_sprites` → `_test_map_instantiator_keeps_room_sprite_colors_untouched`，断言改为「地图实例化器不修改任何 Sprite 颜色」，并额外断言 `_on_day_night_toggled` / `_apply_background_time_tint` 已不存在；`_test_background_resolver_uses_map_instantiator_current_scene` 的夜间语义与 `Color(0.45, 0.45, 0.55)` 一并迁移为中性的 `Color(0.8, 0.8, 0.8)`。
- `tests/godot/test_reusable_gathering_interaction.gd`：`test_current_map_background_resolver_contract` 同上迁移为中性的 `Color(0.8, 0.8, 0.8)`。
- 新增 `tests/godot/test_day_night_filter_contract.gd` + `tests/test_day_night_filter_contract.gd` 转发壳（`test_run` 只发现 `tests/` 顶层的 `test_*.gd`）。
- 注：`tests/godot/passage_guard_tests.gd` 是 `extends SceneTree` 的旧式脚本，不在 `test_run` 发现路径上，已用 `script_manage(op="find_symbols")` 确认其解析正常、新旧符号切换正确。
