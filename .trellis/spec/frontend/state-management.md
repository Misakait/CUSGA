# State Management

## Model、View、Controller 分工

- **Model**：保存资源配置、玩家和地图状态，执行合法性校验与状态变更，并通过信号广播事实。
- **View**：根据 Model 当前状态实例化场景、刷新 UI 和表现，不决定业务规则。
- **Controller**：解释键盘、鼠标和按钮输入，调用 Model 的方法，协调 View 的刷新时机。

单向数据流为：输入 → Controller → Model → 信号 → View。View 不绕过 Controller 修改 Model，Model 不访问 View 节点。

## 节点状态

- 只在单个场景有效的临时状态放在拥有它的节点上。
- 跨场景仍需保留的玩家进度、钱包、时间和设置放在已有 autoload 或专用 Model 资源中。
- 新增全局状态前先检查 `project.godot` 的 `[autoload]`，不要把同一状态复制到多个节点。
- 导出 `NodePath` 必须有可工作的默认值；`_ready` 中检查路径解析结果，并在错误消息中包含实际路径。

## 信号与生命周期

- 生产者只发出事实信号，不直接调用具体 View 的刷新方法。
- 连接前检查 `is_connected`，退出树时使用同一个 `Callable` 断开。
- 可能同步发射结果的调用，必须先连接信号再请求操作。
- 连接方进入场景树后应能从 Model 主动查询一次当前状态，避免错过已经发出的初始信号。
- 节点可能被 `queue_free` 时，缓存清理应先用 `is_instance_valid` 或 `is_queued_for_deletion` 判断，再按下标移除。

## 持久化与资源

- 可保存的数据使用 `Resource` 或现有 autoload 的持久化接口；View 不负责序列化。
- `.tres` 字段名、数组顺序和资源身份属于兼容协议，改名或复制资源前先检查所有引用。
- 缓存运行时实例时，同时保存其坐标或资源键；释放实例后必须移除缓存登记。
