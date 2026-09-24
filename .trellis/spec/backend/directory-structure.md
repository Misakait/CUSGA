# Directory Structure

`backend` 是 Trellis 的目录名称，在本项目中指 GDScript 的数据与玩法规则层，不表示 Web 后端。

- `core/application/`：运行时应用节点和玩法入口。
- `core/gameflow/`：世界交互、开局初始化、战斗/场景流程协调。
- `core/combat/`：战斗规则、技能、效果和战斗状态。
- `core/crafting/`、`core/map/`、`core/inventory/`、`core/shop/`：领域规则和服务脚本。
- `entities/`：玩家、怪物和场景实体。
- `entities/components/`：库存、装备、属性、生命、能量、状态、标签等可复用节点组件。
- `resources/`：可由编辑器配置的 `Resource` 脚本与 `.tres` 资产。
- `core/ui/`：与 Model 信号绑定的界面 View 和 Presenter。
- `tests/godot/`：Godot 运行时契约测试。

纯计算或资源规则尽量放在领域脚本中，通过参数协议测试；场景生命周期、信号连接和节点生成放在 Node/Control 脚本中。
