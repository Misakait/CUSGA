# 验证记录

## 执行环境

- Godot 4.7.1 编辑器 MCP，CUSGA 已连接；验证仅停游戏，不关闭编辑器。
- `project_run` 使用 `autosave=false`，避免编辑器内存副本覆盖磁盘新代码或用户布局。
- 原存档及关键用户文件备份：`C:/Users/huhu9/AppData/Local/Temp/cusga-warehouse-verify-ru8nvnat/manifest.json`。验证结束需恢复原存档，检查关键文件哈希。

## 修改前基线

- `warehouse_gold_refresh_contract`：6/6通过。
- `run_start_loadout_contract`：13/13通过。该套件在无树夹具下既有绝对节点路径错误、缺失时间系统警告和显式MissingPlayer负向用例错误，均不是本次改动引入。
- 发现阶段既有 `test_item_room_content.gd` 解析错误，不属于目标套件；不能宣称全套测试通过。
- 主菜单冒烟：启动live，无本次错误（run r13149930-10）。
- Main冒烟基线：启动live，无运行错误（run r13392234-11）。

## 本次变更验证

- 新转移套件 `warehouse_new_transfer`：5/5通过，39断言；旧金币6/6、开局13/13，总计目标24项通过。发现阶段旧room_content解析错误未改。
- 最新脚本扫描后新仓库启动live，无项目解析/运行错误；两区27/5格，均item_slot2，截图布局正常。
- 真实点击测试物品显示正确名称和描述。真实鼠标拖放（按住运动需要补充button_mask/relative，默认MCP motion不会触发原生拖拽）：仓库8个→行囊8个→指定仓库槽8个，数量守恒。
- 真实仓库升级：27→36格，金币1200→900，下一级费用300→600，已有槽节点实例ID不变；真实行囊升级和整理按钮有效，整理将物品从第1格排回第0格。
- 余额扣到1金币后CoinCount立即刷新，两处升级禁用；满级仓库54/行囊10格，两处显示“已满级”并禁用。
- 真实去商店按钮进入Shop；主菜单仓库事件进入WarehouseNew；真实返回按钮返回main_menu。读取切换结果必须等动画结束，不能在信号发出后同步读取目标子节点。
- 最新Main启动live，当前game日志无错误；该场景后台运行时eval可能不可用，未用其eval做额外运行断言。
- 两次临时eval错误均为测试代码：混合缩进造成编译错误、切换动画未完成立即读节点造成null。均停止后重启验证，未归为产品错误。
- 已停止游戏，编辑器仍打开。原game_save.json/.bak已逐字节恢复。旧Warehouse/CraftingUI/main_menu/item_slot2/project.godot哈希与执行前一致，用户改动未覆盖。
- git diff --check通过。没有Git提交或推送。
- trellis-check静态复核通过，无阻塞项、无需代码修复；样式、转移校验、生命周期、余额费用及节点路径均符合PRD。项目无独立lint/type-check命令，解析类型检查通过编辑器扫描与真实运行验证。
