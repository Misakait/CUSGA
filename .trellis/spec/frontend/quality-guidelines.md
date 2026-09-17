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

Do not hand-edit generated files under `scripts/generated/`. Change the source C# enum or generator, then run:

```bash
godot-mono --headless --path . --script res://tests/godot/skill_targeting_type_codegen_tests.gd
```

## Runtime Validation

For GDScript, scenes, resources, C# `[GlobalClass]` changes, autoload access, or scene/runtime integration, use Godot headless validation:

```bash
godot-mono --headless --path . --build-solutions --quit
godot-mono --headless --path . --check-only --script res://path/to/changed_script.gd
godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd
godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5
```

Run only the focused Godot tests that match the changed area, plus build-solutions when C# resources/global classes changed.

## Do Not Generalize Beyond Current Examples

Do not add web accessibility, React hook, CSS, browser routing, or server-state requirements. The current UI is Godot UI and card/scene interaction. If a future feature introduces a new UI framework, create a new spec from actual code at that time.

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
