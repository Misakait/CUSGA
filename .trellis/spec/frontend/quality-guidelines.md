# Quality Guidelines

These rules apply to Godot scenes, GDScript, C# UI controls, and cross-language integration.

## GDScript Style

Follow the existing GDScript style:

- Use typed variables and return types when practical.
- Use `@export`, `@export_group`, and `@onready` for scene dependencies.
- Use `StringName` signal names with `&"signal_name"` where the current code does.
- Keep explanatory comments in Chinese.
- Use `push_error` for missing required scene dependencies and `push_warning` for degraded fallbacks.

## Scene Safety

When adding or changing scene scripts:

- Check required exported paths and autoloads.
- Use `get_node_or_null` for optional dependencies.
- Disconnect signals in `_exit_tree` when the script created the connection.
- Consider synchronous signal emission before awaiting. The passage guard controller connects before requesting combat because C# may emit the result immediately.
- Smoke-test changed scenes when practical.

## Generated Files

Do not hand-edit generated files under `scripts/generated/`. Change the source C# enum or generator, then run the codegen test through the editor MCP:

```text
test_run(suite="skill_targeting_type_codegen")
```

The CLI form (`godot-mono --headless --script res://tests/godot/skill_targeting_type_codegen_tests.gd`) is obsolete — see "本机验证工具链的实际边界" below.

## Runtime Validation

For GDScript, scenes, resources, C# `[GlobalClass]` changes, autoload access, or scene/runtime integration, validate through the **Godot editor MCP**. The editor must be open with this project loaded.

| Need | Editor MCP |
|---|---|
| Focused runtime runner under `tests/godot/` | `test_run(suite=..., test_name=...)` |
| Scene smoke test | `project_run(mode="custom", scene="res://scenes/X.tscn")` + `logs_read(source="game")`, then `project_manage(op="stop")` |
| Assert state inside the live game | `game_eval(code=...)` |
| Visual check of a UI change | `editor_screenshot(source="game")` |
| Refresh global class cache after adding a `class_name` | `filesystem_manage(op="scan")` |

Run only the focused checks that match the changed area. Do not substitute the removed CLI flags for any of these — see the boundary notes below.

## Do Not Generalize Beyond Current Examples

Do not add web accessibility, React hook, CSS, browser routing, or server-state requirements. The current UI is Godot UI and card/scene interaction. If a future feature introduces a new UI framework, create a new spec from actual code at that time.
## 本机验证工具链的实际边界

本节记录在本机（Windows + Godot **4.7.1**：一律走编辑器 MCP，不再使用命令行）实测出的验证手段边界。这些结论决定了「哪些检查能作为门禁、哪些不能」，照抄命令前务必先看这里。

> 本节在 2026-09-19 做过一次方向性修正。此前本节把 Godot 4.6.3 命令行（`godot-mono --headless`）当作主力验证手段；实际本机 CLI 是 4.6.3，而项目与 `addons/godot_ai` 都要求 4.7.1，**旧命令行整体不可用**。如果你的记忆或旧文档里还有 `--build-solutions` / `--check-only` / `--scene` / `--script` 这类开关，全部作废。

### 1. Scope / Trigger

当需要验证 GDScript / 场景 / 资源改动，或需要选择一条可信的验证命令时。

### 2. Signatures

```text
# 前提：Godot 编辑器已打开本项目。先确认会话存在：
editor_state
session_manage(op="list")

test_run(suite=..., test_name=...)                      # 跑 tests/godot/ 下的运行期 runner

project_run(mode="custom", scene="res://scenes/X.tscn") # 场景冒烟（真实游戏进程）
logs_read(source="game")                                # 读 SCRIPT ERROR / push_error
project_manage(op="stop")                               # 结束游戏

game_eval(code=...)                                     # 在运行中的游戏里断言取值
editor_screenshot(source="game")                        # UI 改动的目视确认
filesystem_manage(op="scan")                            # 刷新全局类缓存
```

编译仍然走命令行，与 MCP 无关：

```powershell
$env:CI='true'; dotnet build CUSGA.sln --no-restore
```

### 3. Contracts

- **必须走编辑器 MCP，不要退回命令行。** 本机 `godot-mono` 是 4.6.3，`addons/godot_ai` 要求 ≥ 4.7，`--build-solutions` 会直接 abort。编辑器未打开时应请用户打开 Godot，而不是改用命令行。
- **`project_run` 会加载 autoload，旧的 `--script` 模式不会。** C# 写的 autoload（`PlayerWallet`、`PlayerProgression` 等）只有在真实游戏进程里才存在。因此 `test_run` 只能覆盖自带夹具的纯规则 / 跨语言桥接；依赖 C# autoload 的场景必须用 `project_run` 跑真实游戏进程验证。
- **语法检查不作为门禁。** 旧的 `--check-only --script` 只做解析不做编译，任何引用 autoload 的脚本都会报 `Compile Error: Identifier not found: <AutoloadName>`，项目既有的 `warehouse_control.gd` 同样如此。不要把它的失败当成回归——该开关本身已不可用，也不要寻找替代品。
- **不要用 `--build-solutions`。** 原因同上；C# 编译请直接用 `dotnet build`，Godot 会加载 `.godot/mono/temp/bin/Debug/CUSGA.dll`，无需该开关。
- **运行 Godot 编辑器会改写受版本控制的文件。** 实测两种副作用：把 `.cs` 文件从空格**重排成 Tab**（违反本仓库 `.editorconfig` 的 `indent_style = space`），以及把 `CUSGA.csproj` 的 `Godot.NET.Sdk` 版本改成当前引擎版本。跑完编辑器后必须 `git status` 复查并 `git checkout` 还原非预期改动。
- **新增 `class_name` 后必须先让编辑器扫描一次**，否则加载会报 `Parse Error: Could not find type "X" in the current scope`。执行 `filesystem_manage(op="scan")`，确认 `.godot/global_script_class_cache.cfg` 里出现该名字即可（该文件在 `.godot/` 下，不入版本控制）。
- **`dotnet run --project tests/CUSGA.Tests` 在本机跑不起来。** 它在 Godot 运行时之外解析不了 GodotSharp，会以 `AccessViolationException` 崩在**项目原有的**用例上。C# 规则层要真正执行，需改写成 Godot runner（见 `tests/godot/shop_trade_tests.gd` 的做法：`load("res://xxx.cs").new()` 实例化 C# 节点）。
- 沙箱若限制写 `user://`（`%APPDATA%\Godot\app_userdata\CUSGA`），Godot 会在日志初始化处段错误崩溃，且**项目原有的 runner 也一样崩**。这是环境权限问题，不是项目问题。

### 4. Validation & Error Matrix

| 手段 | 能覆盖 | 不能覆盖 |
|---|---|---|
| `env CI=true dotnet build CUSGA.sln --no-restore` | C# 编译 | 运行期行为 |
| `project_run` + `logs_read(source="game")` | 场景能否加载、脚本能否编译、节点路径、autoload 装配 | 交互逻辑（需配合 `game_eval`） |
| `test_run(suite=...)` | 纯规则、跨语言桥接（自带夹具） | 依赖 C# autoload 的场景 |
| `game_eval` | 运行中的真实状态断言 | 启动期的加载错误 |
| `editor_screenshot(source="game")` | UI 实际渲染效果 | 逻辑正确性 |
| `filesystem_manage(op="scan")` | 刷新全局类缓存 | 不能作为门禁（会改文件） |
| 旧的 `--check-only --script` | **无**（已作废） | 不引用 autoload 的脚本语法 |

### 5. Good / Base / Bad Cases

- Good：改完场景后用 `project_run` 冒烟确认 `logs_read(source="game")` 无 `SCRIPT ERROR`，再用 `game_eval` 做交互断言，最后用 `git status` 确认没有非预期文件被改。
- Base：只跑 `dotnet build` + `project_run` 冒烟，能挡住绝大多数低级错误。
- Bad：试图用旧命令行做验证（`--build-solutions` 直接 abort）；把语法检查的 `Identifier not found` 当成自己引入的回归去修；或跑完编辑器不看 `git status`，把 C# 缩进重排一起提交。

### 6. Tests Required

- 每次改动后：`git status --porcelain` 与改动前对比，确认没有多出非本任务的修改。
- 新增 `class_name` 后：先 `filesystem_manage(op="scan")` 刷新缓存，再跑 `project_run` 冒烟。
- 改动 `tests/godot/` 下的 runner 后：用 `test_run` 跑到该 suite 通过。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 会直接 abort：本机 CLI 是 4.6.3，godot_ai 插件要求 4.7
godot-mono --headless --path . --build-solutions --quit

# 不作门禁：引用 autoload 的脚本必然报 Identifier not found
godot-mono --headless --path . --check-only --script res://scripts/x.gd
```

#### Correct

```powershell
# 1. 编译（命令行，与 MCP 无关）
$env:CI='true'; dotnet build CUSGA.sln --no-restore
```

```text
# 2. 运行期验证（编辑器 MCP，编辑器必须已打开）
project_run(mode="custom", scene="res://scenes/X.tscn")
logs_read(source="game")     # 确认无 SCRIPT ERROR
project_manage(op="stop")
```

```powershell
# 3. 确认没有非预期改动
git status --porcelain
```

## 编辑器插件调用外部内容工具

### 1. Scope / Trigger

当 `EditorPlugin` 通过 `OS.execute` 调用项目内的 Python 或其他外部内容工具，并根据结果重新扫描 Godot 资源时，必须把进程结果视为跨层契约。触发原因是“进程有日志”不等于“资源已安全写入”；错误地把失败显示为成功会直接误导内容维护者。

### 2. Signatures

```gdscript
func _run_python_script(arguments: PackedStringArray) -> Dictionary
func _read_result_payload(request_id: String) -> Dictionary
func _handle_operation_result(result: Dictionary, may_rescan_resources: bool) -> void
```

```python
RESULT_PREFIX = "TOOL_RESULT="
print_result(SyncResult(...), success, error, result_file, request_id)
# UTF-8 结果文件与控制台摘要均包含：
{
    "success": bool,
    "action": str,
    "changed_files": list[str],
    "warnings": list[str],
    "error": str,
    "request_id": str,
}
```

### 3. Contracts

- Python 工具必须以 `0` 表示整个操作成功；校验、备份、读写或运行时失败必须以非零退出。
- Godot 每次执行必须生成唯一 `request_id`，并通过 `--result-file`、`--request-id` 传给 Python；Python 以 UTF-8 原子写入完整 JSON 结果。
- 结果文件是机器状态主通道；控制台稳定前缀加 JSON 只作为结果文件不可读时的兼容回退和人工诊断，不得单凭普通日志或退出码构造成功。
- 编辑器插件只在请求标识匹配、`success=true` 且退出码为 `0` 时显示成功；只有 `changed_files` 包含真实 Godot 资源时才调用文件系统扫描。
- 结果文件缺失、JSON 损坏或请求标识不匹配必须失败，不能回退成“无详情成功”。
- Windows 优先使用 `py -3`，并允许通过环境变量指定解释器；插件必须在没有可用解释器时显示可操作的错误。
- 面向内容人员的同步动作需要确认提示，并在编辑器内显示成功、无变更与失败状态。

### 4. Validation & Error Matrix

| 条件 | Python 工具 | 编辑器插件 |
| --- | --- | --- |
| 表格或输入预检失败 | 输出失败摘要并以非零退出，不写资源 | 显示错误，不扫描资源 |
| 写入/备份失败 | 输出失败摘要并以非零退出 | 显示错误，不显示成功文案 |
| 退出码为 0 但结果文件缺失/无效 | 结果协议未完成 | 显示失败，不扫描资源 |
| 结果文件请求标识属于旧调用 | 旧结果不得参与本次判断 | 显示失败，不读取旧动作或改动列表 |
| Windows 控制台乱码或未捕获摘要 | UTF-8 结果文件仍保存完整状态 | 以结果文件为准，不受控制台影响 |
| 无可用 Python | 不适用 | 尝试平台候选后报告安装或环境变量指引 |
| 仅导出表格 | 成功摘要只列出表格文件 | 显示成功但不扫描 `res://resources/` |

### 5. Good / Base / Bad Cases

- Good：用户确认同步后，工具预检并备份资源，返回成功摘要；插件仅在摘要列出 `.tres` 更新时扫描文件系统。
- Base：表格和资源都没有变化；工具返回成功且 `changed_files` 为空，插件显示“无需同步”。
- Bad：插件因为退出码为零但结果缺失就自行构造“同步完成”，或读取上一次调用留下的成功文件。

### 6. Tests Required

- Python 单元测试必须覆盖：非法输入返回非零摘要且不创建资源、原子写入、批量写入失败后的回滚。
- 测试必须覆盖：成功与失败结果都以 UTF-8 写入文件、携带当前请求标识，并保持控制台摘要兼容。
- 测试必须覆盖：资源路径不能越出受管目录、根资源属性替换不会修改同名子资源字段。
- 修改 GDScript 交互层时，有可用 Godot 运行时后应验证确认框、成功/失败弹窗与“仅资源更新才扫描”的分支。

### 7. Wrong vs Correct

#### Wrong

```gdscript
var output := _run_python_script(["--sync"])
print("同步成功")
filesystem.scan()
```

#### Correct

```gdscript
var result: Dictionary = _run_python_script(PackedStringArray(["--auto"]))
if not bool(result.get("success", false)):
    _show_error(str(result.get("error", "同步失败")))
    return
if _payload_changed_resources(result.get("payload", {})):
    _queue_rescan_filesystem()
_show_info(str(result["payload"].get("action", "操作完成")))
```

## 内容同步的用户防误操作引导

### 1. Scope / Trigger

当编辑器插件让非程序使用者在 Godot 资源和外部内容文件之间同步时，必须在用户实际执行高风险动作前提供操作顺序和覆盖规则。仅在 README 说明是不够的，因为用户可能从菜单直接进入同步而没有阅读文档。

### 2. Signatures

```gdscript
const USAGE_METADATA_SECTION := "card_csv_sync"
const USAGE_METADATA_KEY := "has_seen_usage_guide"

func _should_show_usage_guide() -> bool
func _mark_usage_guide_read_and_open_table() -> void
func _request_safe_sync() -> void
```

### 3. Contracts

- `EditorSettings` 的项目元数据以 `USAGE_METADATA_SECTION` 和 `USAGE_METADATA_KEY` 记录首次引导已读状态；它只控制编辑器提示，不得写入表格、资源或同步状态。
- 用户第一次选择打开表格时，必须先展示“表格改卡”和“Godot 改卡”两条可执行顺序，并指出同一张卡不能双端同时编辑。
- 每次安全同步都必须再次展示同步方向、双端同时编辑的覆盖风险和 XLSX 锁定后产生 pending 文件的处理方法；首次引导不能替代高风险动作确认。
- `card_table/README.md` 保存字段、备份和恢复等完整参考说明；编辑器弹窗只提供足够完成当前操作的短说明。

### 4. Validation & Error Matrix

| 条件 | 编辑器行为 | 数据影响 |
| --- | --- | --- |
| 首次打开且元数据未标记 | 展示使用说明，确认后才打开或生成工作簿 | 不写卡牌资源 |
| 已读过首次说明 | 直接进入既有打开流程 | 不覆盖已有工作簿 |
| 请求安全同步 | 每次展示同步方向和风险提示 | 用户确认前不启动 Python 工具 |
| XLSX 被 Excel/WPS 占用 | 提示将生成 pending 文件，关闭后再同步 | 不直接覆盖被锁定工作簿 |
| 用户取消确认框 | 保持当前状态 | 不执行同步或资源扫描 |

### 5. Good / Base / Bad Cases

- Good：首次用户先看见“修改表格后保存并关闭，再同步”的顺序；之后每次同步仍可看见双端同时编辑的覆盖风险。
- Base：用户已经读过首次说明，点击打开表格不被重复打断；同步确认依然正常显示。
- Bad：只把注意事项写在 README，或只在首次启动时提示一次同步风险。用户以后从菜单直接同步时容易忘记关闭 XLSX 或覆盖另一端数据。

### 6. Tests Required

- 在可用 Godot 编辑器中清除该项目元数据后点击“打开卡牌表格”，断言先显示引导，确认后才调用既有打开流程。
- 再次打开表格，断言不重复显示首次引导，也不重建已有 XLSX。
- 每次点击“安全同步卡牌表格”，断言确认文本包含同步方向、双端编辑和 XLSX 锁定的风险；取消后不得启动外部工具。
- 检查 README 的标准流程与弹窗中的菜单名称、pending 行为保持一致。

### 7. Wrong vs Correct

#### Wrong

```gdscript
func _open_card_table() -> void:
	OS.shell_open(ProjectSettings.globalize_path(XLSX_FILE_PATH))
```

#### Correct

```gdscript
func _open_card_table() -> void:
	if _should_show_usage_guide():
		_usage_guide_dialog.popup_centered()
		return
	_open_card_table_after_guide()
```

## MCP test_run 的套件发现路径与转发壳

### 1. Scope / Trigger

当新增一个由 `test_run` 执行的 Godot 运行期契约套件时。触发原因是 `test_run` **只扫描 `res://tests` 顶层**且**只认 `test_*.gd`**：把套件写在别处不会报错，只会静默不执行，看起来像"没有失败"。

### 2. Signatures

```gdscript
# res://tests/godot/test_<name>_contract.gd —— 真正的实现
@tool
extends McpTestSuite

func suite_name() -> String:
	return "<name>_contract"

func test_<behavior>() -> void:
	assert_eq(actual, expected, "失败信息")
```

```gdscript
# res://tests/test_<name>_contract.gd —— 4 行转发壳
@tool
extends "res://tests/godot/test_<name>_contract.gd"

## MCP 测试入口转发到 tests/godot，保持项目现有测试发现路径。
```

```text
test_run(suite="<name>_contract")
```

### 3. Contracts

- 发现逻辑在 `addons/godot_ai/handlers/test_handler.gd`：`DirAccess.open("res://tests")` 之后只接受 `file_name.begins_with("test_") and file_name.ends_with(".gd")`。**不递归子目录**，也不认 `*_tests.gd`。
- 因此 `tests/godot/*_tests.gd`（`world_hold_interaction_tests.gd`、`passage_guard_tests.gd` 等）**不会被 `test_run` 发现**——它们是另行驱动的旧式 `SceneTree` runner。写需要 `test_run` 执行的套件时不要照抄这个命名。
- `suite_name()` 的返回值就是 `suite=` 过滤键，必须唯一。
- 断言用 `McpTestSuite` 的 `assert_*`；一个 `test_*` 方法内首次失败后，该方法内后续断言被跳过（失败信息以第一条为准）。
- 套件应自建最小节点树、并用伪 Autoload 替代真实 `/root/...`，这样不依赖编辑器当前打开哪个场景；依赖项目主场景的套件在主场景未打开时会得到 `scene_warning`。

### 4. Validation & Error Matrix

| 条件 | 现象 | 处理 |
|---|---|---|
| 套件放 `tests/godot/` 且命名 `*_tests.gd` | `test_run` 返回 `total: 0`，无报错 | 实现改名 `test_*.gd` 放 `tests/godot/`，顶层加转发壳 |
| 套件放 `res://tests/` 的任意子目录 | 同上 | 同上 |
| `suite=` 名字写错 | `unknown_suite_error`，并列出 `suites_available` | 用返回的可用列表校正 |
| 套件断言依赖项目主场景节点 | 主场景未打开时出现 `scene_warning` 与失败 | 先 `scene_open` 主场景再复跑，或改为自建节点树 |
| 断言依赖 `preload` 的脚本，且该脚本刚被改过 | 可能读到旧缓存（响应里带 `cache_warning`） | 重启编辑器后再复跑，别把该次运行当作依赖改动的验证 |

### 5. Good / Base / Bad Cases

- Good：`tests/godot/test_dev_settings_contract.gd` 实现套件（`@tool extends McpTestSuite`），`tests/test_dev_settings_contract.gd` 只放 4 行转发壳，`test_run(suite="dev_settings_contract")` 直接命中。
- Base：套件用 `unique_name_in_owner` 自建最小控件树，并用伪 `TimeSystem` 替代真实 Autoload，因此不依赖打开哪个场景。
- Bad：把新套件写成 `tests/godot/dev_settings_tests.gd`。`test_run` 静默不执行它，报告里既没有失败也没有该套件，实际什么都没验证。

### 6. Tests Required

- 新增套件后跑 `test_run(suite="<新套件名>")`，断言 `total > 0`。`total: 0` 表示**没有被发现**，不是"通过"。
- 再跑一次不带 `suite` 的全量 `test_run`，断言 `failed == 0`，并确认新套件出现在 `suites_run` 列表里。
- 全量跑完后读 `logs_read(source="editor")`：`new_errors_since_last_call` 可能包含**既有负面路径测试故意触发的 `push_error`**（例如 `room_terrain_store` 的重复地形与空 `terrain_data`）。必须逐条按 `path`/`frames` 定位来源文件，确认不是本任务的回归再收工。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# res://tests/godot/dev_settings_tests.gd
# test_run 不递归子目录、也不认 *_tests.gd → 静默不执行
extends SceneTree
```

#### Correct

```gdscript
# res://tests/godot/test_dev_settings_contract.gd
@tool
extends McpTestSuite

func suite_name() -> String:
	return "dev_settings_contract"
```

```gdscript
# res://tests/test_dev_settings_contract.gd
@tool
extends "res://tests/godot/test_dev_settings_contract.gd"
```

## Variant 推断告警在本项目是硬错误

### 1. Scope / Trigger

在 GDScript 里用 `:=` 从一个返回 `Variant` 的表达式推断类型时。触发原因是本项目把 `inference_on_variant` 从警告提升为**错误**：这类写法直接 `Parse Error`，而且同一文件里每一处同类写法各报一条，很容易被误读成"改动大面积出错"。

### 2. Signatures

```gdscript
# 会 Parse Error：从 Variant 推断
var level := _new_player_level()          # func _new_player_level() -> Variant

# 正确：显式类型 + 字符串协议访问脚本自定义成员
var level: Node = _new_player_level()
level.call("GetLevel")
level.set("CurrentExperience", 100)
level.connect("LevelChanged", func(new_level: int) -> void: pass)
```

### 3. Contracts

- 报错原文：`Parse Error: The variable type is being inferred from a Variant value, so it will be typed as Variant. (Warning treated as error.)`
- 触发条件是 `:=`，不是"用了 Variant"。`var x: Variant = ...` 与不带推断的 `var x = ...` 都不触发该告警。
- 无 `class_name` 的脚本没有可用作类型标注的全局名。**不要为了消警把它收窄成 `Node` 之后再用点号访问脚本自定义信号与字段**——`Node` 静态类型下访问脚本成员同样失败。正确做法是保留 `Node` 类型、把脚本自定义成员一律走字符串协议（`call` / `set` / `get` / `connect`）。
- 这条规则与上一条「套件发现路径」叠加时最容易踩：新增套件往往同时包含「从 `track(...)` 拿实例」和「访问无 `class_name` 脚本的信号」，两个坑会连在一起报。

### 4. Validation & Error Matrix

| 写法 | 结果 | 处理 |
|---|---|---|
| `var x := <Variant 表达式>` | Parse Error（警告即错误） | 改 `var x: <显式类型> = ...`，或去掉 `:=` |
| `var x: Node = ...` 后 `x.ScriptSignal.connect(...)` | 静态检查失败 | 改 `x.connect("ScriptSignal", ...)` |
| `var x: Node = ...` 后读 `x.ScriptField` | 静态检查失败 | 改 `x.get("ScriptField")` |
| `filesystem_manage(op="scan")` 返回 `new_errors_since_last_call > 0` | 可能正是本类错误 | 立刻 `logs_read(source="editor", include_details=true)` 按 `path` 定位 |

### 5. Good / Base / Bad Cases

- Good：`tests/godot/test_player_level_contract.gd` 的 `_new_player_level() -> Node`，全部访问走 `call` / `set` / `connect` 字符串协议。
- Base：同一文件内用 `class FakeLevelSource extends Node` 声明的局部类**可以**直接点号访问，因为它是文件内具名类型，不涉及 Variant 推断。
- Bad：`var level := track(SCRIPT.new())` 后 `level.LevelChanged.connect(...)` —— 既触发 Variant 推断错误，又会在改成 `Node` 后因为点号访问脚本信号而二次失败。

### 6. Tests Required

- 新增或修改 `.gd` 后跑一次 `filesystem_manage(op="scan")`，确认返回里没有 `new_errors_since_last_call`；有则按 `path` 定位来源。
- 新增测试套件后跑 `test_run(suite="<name>")`，断言 `total > 0`。

### 7. Wrong vs Correct

#### Wrong

```gdscript
var level := _new_player_level()   # Parse Error: inferred from a Variant value
level.LevelChanged.connect(_on_level_changed)
```

#### Correct

```gdscript
var level: Node = _new_player_level()
level.connect("LevelChanged", _on_level_changed)
```


## 编辑器测试里构造 UI 夹具的四条硬约束

### 1. Scope / Trigger

在编辑器进程（`test_run`）里为**非 `@tool` 的生产 UI 脚本**搭行为测试夹具时。这三条约束都不会报"夹具搭错了"，而是让断言以看似业务失败的方式挂掉。

### 2. Signatures

```gdscript
# Window 系节点（PopupPanel / PopupMenu / AcceptDialog）用 min_size，不是 custom_minimum_size
node_set_property(path, "min_size", {"x": 260, "y": 0})

# 行为夹具：生产脚本 new() + 手工最小子树（name 与 unique_name_in_owner 必须与生产场景一致）
var popup := ALLOCATION_POPUP_SCRIPT.new() as PopupPanel
var grid := GridContainer.new()
grid.name = "AllocationGrid"
grid.unique_name_in_owner = true
popup.add_child(grid)
grid.owner = popup
scene_tree.root.add_child(popup)   # 入树时引擎已经调用过 _ready
```

### 3. Contracts

- `PopupPanel` / `PopupMenu` / `AcceptDialog` 继承自 `Window` 而非 `Control`，**没有** `custom_minimum_size`。误用返回 `PROPERTY_NOT_ON_CLASS`；在 `batch_execute` 里这会让整批已成功的子命令**原子回滚**（`rolled_back: true`），现场看起来像"什么也没发生"。`.tscn` 里手写 `custom_minimum_size` 不报错、加载时被静默忽略，历史场景中的此类行不要照抄。
- 非 `@tool` 脚本经 `PackedScene.instantiate()` 得到的是 **placeholder instance**，连 `_ready` 都无法调用（`Attempt to call a method on a placeholder instance`）。行为测试必须用 `脚本.new()` 构造；生产场景的脚本引用、唯一名、列数等**形状契约**另用 `instantiate()` 只读断言锁定，两者分工不要混。
- `scene_tree.root.add_child(脚本实例)` 会触发引擎正常调用一次 `_ready`。因此 `_ready` 里的**连接与节点生成都必须幂等**：连接前查 `is_connected`，生成前查哨兵（如"引用字典非空即返回"）。
- 断言"某个弹窗被关掉了"之前，必须让它**真的可见过**；否则在从未显示的状态下 `assert_false(popup.visible)` 会无意义地通过。
- 未入树的节点**不能**直接调 `get_tree()`：引擎会打印 `Parameter "data.tree" is null`。返回值同样是 `null`，所以逻辑"看起来没错"，但日志会被刷满噪音、掩盖真正的问题。判"在不在树里"要先 `is_inside_tree()` 收口，再取 `get_tree()`。
- 生产脚本用 `@export var XPath: NodePath` 携带相对路径默认值时，夹具必须**复刻生产层级**（例：`Main/UI/HUDLayer/HUDRoot/<界面>`），否则默认路径解析不到。额外收益：默认路径层级写错（少写一层 `..`）时测试会立刻失败，比运行起来才发现功能没触发便宜得多。

### 4. Validation & Error Matrix

| 现象 | 真实原因 | 处理 |
|---|---|---|
| `PROPERTY_NOT_ON_CLASS: custom_minimum_size not found on PopupPanel` | `Window` 系节点用 `min_size` | 改 `min_size`；注意 `batch_execute` 已整体回滚，需重发全部子命令 |
| `Attempt to call a method on a placeholder instance` | 用 `instantiate()` 构造了非 `@tool` 脚本的实例 | 改 `脚本.new()` + 手工子树 |
| `Parameter "data.tree" is null` | 未入树的节点调了 `get_tree()` | 先用 `is_inside_tree()` 判空，再取 `get_tree()` |
| 生成的行数翻倍、值标签永远停在占位符 | `_ready` 被执行两次，第二批引用覆盖了第一批 | 生成逻辑加哨兵，连接前查 `is_connected` |
| `Signal 'pressed' is already connected to given callable` | 同上，重复 `connect` | 同上 |
| `assert_false(popup.visible)` 意外通过 | 弹窗本来就没显示过 | 断言前先 `popup.visible = true`（或真实 `popup_centered()`） |

### 5. Good / Base / Bad Cases

- Good：`tests/godot/test_attribute_allocation_popup_contract.gd` 的 `_new_popup()` 用 `ALLOCATION_POPUP_SCRIPT.new()` 加四个手工唯一名子节点构造夹具，形状契约由 `test_production_popup_scene_uses_gdscript_and_unique_names` 用 `instantiate()` 只读锁定。
- Base：`tests/godot/test_attribute_summary_ui_contract.gd` 同样用脚本 `new()` 构造，并对 `add_child` 后的显式 `call("_ready")` 免疫——因为 `attribute_summary_ui.gd` 的 `connect` 从一开始就带 `is_connected` 幂等守卫。
- Bad：对 `packed_scene.instantiate()` 出来的节点调 `call("_ready")`——既拿不到可用实例，又掩盖了"引擎已自动跑过一次"的事实。

### 6. Tests Required

- 新增 UI 行为套件后，必须同时在**同一套件内**保留一条 `instantiate()` 只读的形状/唯一名断言，避免夹具与生产场景悄悄脱节。
- 涉及"累计后再提交"这类两段式交互时，必须断言**中间态没有副作用**（如属性值、可用点数在累计阶段保持不变），不能只断言最终态。

### 7. Wrong vs Correct

#### Wrong

```gdscript
var popup := packed_scene.instantiate() as PopupPanel   # placeholder instance
scene_tree.root.add_child(popup)
popup.call("_ready")                                    # Invalid call

func _build_rows() -> void:                             # 重复进入 Ready 会跑两遍
	for index in ALLOCATABLE_TYPES.size():
		_rows_grid.add_child(...)
```

#### Correct

```gdscript
var popup := ALLOCATION_POPUP_SCRIPT.new() as PopupPanel
# ...按生产唯一名挂好最小子树...
scene_tree.root.add_child(popup)
popup.call("_ready")                                    # 幂等，补调无害

func _build_rows() -> void:
	if not _value_labels.is_empty():                    # 幂等哨兵
		return
	for index in ALLOCATABLE_TYPES.size():
		_rows_grid.add_child(...)
```

## TypedArray 无法承载已释放实例

### 1. Scope / Trigger

- 触发条件：任何持有 `Array[T]`（`Array[Node2D]`、`Array[Resource]` 等类型化数组）的缓存，在元素被 `free()` / `queue_free()` 之后仍需遍历、清理或按值删除。
- 典型场景：手牌缓存、场上实体缓存、信号订阅登记表——这些容器都允许“外部先释放节点、缓存后同步”。
- 不适用：无类型 `Array` 与 `Dictionary` 不受此约束，但改用无类型容器会丢掉其余全部元素类型检查，不是推荐的替代方案。

### 2. Signatures

- 读取（正确）：`var item: Variant = typed_array[index]`
- 读取（悬空时报错）：`var item: T = typed_array[index]`、`for item: T in typed_array`
- 删除（正确）：`typed_array.remove_at(index)`
- 删除（悬空时被拒）：`typed_array.erase(freed_instance)`

### 3. Contracts

- 遍历可能含悬空实例的类型化数组时，循环变量与临时变量必须声明为 `Variant`；只有 `is_instance_valid()` 通过之后才允许 `as T` 收敛回具体类型。项目既有实现见 `CombatFeedbackDirector._exit_tree` 的“先在 Variant 层校验”写法。
- 移除失效元素必须按下标进行（`remove_at`），并倒序遍历，避免删除当前元素后跳过后续元素。
- TypedArray 的校验发生在写入、按类型读取、`erase` 三个入口；它不保证“存进去的实例永远有效”。

### 4. Validation & Error Matrix

| 写法 | 元素有效 | 元素已释放 |
|---|---|---|
| `var x: Variant = arr[i]` | 正常 | 正常，交给 `is_instance_valid` 判断 |
| `var x: T = arr[i]` / `for x: T in arr` | 正常 | `Trying to assign invalid previously freed instance.`，**当前函数中止** |
| `arr.erase(freed)` | 正常 | `Attempted to erase an invalid (previously freed?) object instance into a 'TypedArray'.`，**元素不会被移除** |
| `arr.remove_at(i)` | 正常 | 正常移除 |

### 5. Good / Base / Bad Cases

- Good：倒序遍历 + `Variant` 读取 + `remove_at`，清理真正生效，且不产生任何运行期错误。
- Base：容器里始终只有有效实例时三种写法表现一致——这正是该缺陷能长期潜伏的原因。
- Bad：用 `for card: Node2D in cache` 或 `cache.erase(card)` 实现“清理失效引用”。清理函数自己先报错中止，悬空引用永远清不掉，还会在每帧刷错误日志。

### 6. Tests Required

- 清理路径必须进入 `test_run` 可发现的 `McpTestSuite`：`test_runner` 会把测试期间捕获的 SCRIPT ERROR 直接判为失败，因此“清理函数自己报错”会被当场抓住（见 `tests/godot/test_player_hand_cache_contract.gd`）。
- 断言必须同时覆盖“失效引用被移除”与“有效元素仍被正常写入”，避免修复退化成“遇到悬空引用就整轮跳过”。
- 分别覆盖 `free()`（previously freed）与 `queue_free()`（`is_queued_for_deletion`）两条分支。
- 只断言数组长度而不关心运行期错误、或把用例留在 `extends SceneTree` runner 里，都不足以拦住这类缺陷。

### 7. Wrong vs Correct

#### Wrong

```gdscript
func _remove_invalid_cards() -> void:
	for card: Node2D in _cards.duplicate():          # 悬空实例：类型赋值错误，函数中止
		if not is_instance_valid(card):
			_cards.erase(card)                       # 悬空实例：erase 被 TypedArray 校验拒绝
```

#### Correct

```gdscript
func _remove_invalid_cards() -> void:
	for index: int in range(_cards.size() - 1, -1, -1):
		var card: Variant = _cards[index]            # Variant 层承接悬空实例
		if not is_instance_valid(card) or card.is_queued_for_deletion():
			_cards.remove_at(index)                  # 按下标删除，不经过类型校验
```
