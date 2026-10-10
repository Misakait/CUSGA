# 商店接入验证记录

日期：2026-10-10（Asia/Shanghai）。本任务实现与验证已完成，未提交 Git。

## 前置与数据保护

- editor_state 确认项目 CUSGA、Godot 4.7.1-stable，编辑器停留在 ShopNew。
- 用户明确批准最新方案：“好的快去吧”；任务已转为 in_progress。
- 原始玩家存档备份目录：`C:/Users/huhu9/AppData/Local/Temp/cusga-shop-validation-51m55b46`。
- manifest.json 记录 game_save.json、game_save.json.bak、settings.cfg 原路径和 SHA-256。
- 原始 game_save.json 与备份 SHA-256：`d33bfe4feb1d2e6662dcfec434a88a029dbb8d33ecd8a61c5b2d1b46370bdbe9`。
- 原始 settings.cfg SHA-256：`c5171b2b14d4395ca7e040608c93194edf0d11e52eb34b20a77e002fe1370b5d`。
- 真实运行测试结束，必须先停止游戏，再恢复并检查文件哈希。测试运行中可将 SaveManager.SaveFilePath 指向临时验证路径，防止测试交易修改玩家原档。

## 已执行验证

### Godot 编辑器与资源扫描

- `editor_state`：Godot `4.7.1-stable`，项目 `CUSGA`，编辑器已加载 `res://scenes/Shop/ShopNew.tscn`。
- `filesystem_manage(op="scan")`：扫描完成，编辑器文件系统稳定，无新增脚本解析错误。
- 主场景冒烟：`project_run(mode="main")` 成功启动，游戏辅助器上线，`logs_read(source="game")` 只有正常的 MCP 辅助器注册信息，没有本次改动产生的错误；随后已调用 `project_manage(op="stop")`，编辑器保持打开。

### 自动化测试

- `shop_new_contract`：8/8 通过，共 66 个断言。
- `warehouse_new_transfer`：5/5 通过。
- `warehouse_gold_refresh_contract`：6/6 通过。
- 覆盖购买数量、出售数量、零数量提示、拖入/换图/改数量不交易、明确点击才提交、原槽位身份、过期来源、数量不足原子失败和缓存生命周期。

### 真实运行验证

- ShopNew 商品格 89 个、仓库格 27 个、初始金币 1200。
- 购买数量设为 3 并点击购买：金币变为 930，提示“购买3件成功，共270金币”。
- 出售数量为 0 时点击出售图标：Notice 显示“请选择数量”，库存和金币不变。
- 将仓库物品拖入出售区：只更新待售图标，库存和金币不变。
- 设置出售数量为 1 后单独点击待售图标：出售成功，金币增加 45。
- 商店返回仓库并再次进入 ShopNew：商品格 89 个、仓库格 27 个，缓存重入和信号订阅正常。
- 整理、升级按钮、金币刷新和返回仓库路径已通过运行时检查；升级费用和容量沿用既有组件与数值。

### 存档与工作区保护

- 验证前记录 `game_save.json`、`game_save.json.bak`、`settings.cfg` 的 SHA-256。
- 验证结束后停止游戏并恢复隔离验证状态；三份文件哈希与验证前一致：
  - `game_save.json` / `game_save.json.bak`：`d33bfe4feb1d2e6662dcfec434a88a029dbb8d33ecd8a61c5b2d1b46370bdbe9`
  - `settings.cfg`：`c5171b2b14d4395ca7e040608c93194edf0d11e52eb34b20a77e002fe1370b5d`
- `git diff --check` 通过；未执行提交或推送，用户准备的未提交素材和场景均保留。

## 左侧空槽样式补验

- 用户指出商店左侧局外仓库的格子应使用 item_slot2。运行检查确认 27 个格子已实例化该场景，但空槽禁用时没有 disabled 样式，回退成默认灰块。
- `shop_item_slot.gd` 在 `_ready()` 中让 disabled 复用 normal；空槽仍禁用，不修改共享场景、原三态样式或交易输入。
- Godot MCP 扫描及 ShopNew 冒烟成功。运行节点的 disabled 为 true，normal 与 disabled 均指向 item_slot2 的同一 StyleBoxTexture；截图确认左侧 27 格边框恢复。
- Main 冒烟成功，游戏日志没有新增错误；停止游戏，编辑器保持打开。
- 补验发现旧验证记录之后的自动保存更新了时间字段，库存、金币与升级数据没有变化。停止游戏后恢复验证前备份并重新核对哈希。

## 物品详情与右键清空补验

- 复用 WarehouseNew 的 ItemTooltipPresenter 与 TooltipPanel 场景，商品/仓库格真实左键按下与松开后详情框可见，标题为“斧头”，截图显示名称与描述框。
- 商品选择后购买数量设为 3，再真实点击左侧仓库物品：购买图标仍存在、商品仍为斧头、数量仍为 3，金币仍为 1200。
- 真实右键点击购买图标：购买资源与图标清空、数量归零；不提交交易。
- 在隔离存档路径中注入 2 件测试物品，设置待售后真实右键点击出售图标：来源与图标清空、数量归零；金币仍为 1200、库存总数仍为 2。
- Godot 扫描及 ShopNew 启动成功；最终运行游戏日志只有正常辅助器注册，没有脚本错误。原聚焦套件 8/8 通过；本次行为使用真实运行验证。
- 初次运行检查使用了错误的绝对节点路径而触发调试中断，已停止该轮并以 /root/ShopNew 路径重新启动、完成以上验证；该错误不来自产品脚本。
- 原始存档在本轮运行前另备份至 `C:/Users/huhu9/AppData/Local/Temp/cusga-shop-tooltip-before`；停止游戏后恢复该备份并核对哈希，不复用上轮更早的备份。

## 已知基线问题

测试运行会同时报告 `test_item_room_content.gd` 无法实例化（Parse Error）。该错误在本次商店改动前已存在，未由本任务修改引入；本任务新增的测试套件全部通过，未扩大范围修复该旧问题。
