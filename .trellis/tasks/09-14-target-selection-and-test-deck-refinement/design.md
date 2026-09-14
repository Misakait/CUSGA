# 目标选择与测试卡池优化设计

## 变更边界

- `CardManager` 继续作为目标选择视觉状态与点击输入的唯一拥有者。
- 怪物卡面展示控件不改为物理碰撞节点；点击模式仅在 `gui_get_hovered_control()` 返回的控件属于怪物节点树时绕过 GUI 阻挡。
- `Monster` 继续只消费颜色、缩放和描边参数，不理解主/次目标的业务语义。
- 新测试牌仅扩展测试资源和战斗场景的初始牌组，不修改技能目标枚举或结算代码。

## 数据与输入流

```text
鼠标点击 → gui_get_hovered_control
    ├─ 非怪物 GUI → 保留拦截，避免误操作
    └─ 怪物卡面子控件 → CardManager 沿父链定位 Monster → 物理卡槽点查询 → 选择敌人

卡牌目标类型 → CardManager 视觉状态 → Monster 描边/缩放接口
测试牌资源 → battle.tscn.starting_deck_data → DeckManager 抽牌堆
```

## 参数

- 呼吸半周期：从 `0.50` 秒调整为 `0.25` 秒。
- 主描边宽度：从 `3px` 调整为 `2px`。
- 次级描边：新增 Inspector 导出颜色 `Color(0.55, 1.00, 0.65, 0.80)`。
- 初始牌池：七类测试牌各三份，共 21 张，避免 `DeckManager` 的最少 20 张补牌规则混入基础牌。

## 验证

- 扩展 Godot 场景测试，读取 `battle.tscn` 的初始牌组并断言全部七种目标类型各至少三张。
- 静态审阅点击 GUI 白名单：仅怪物节点树可穿透，其他 UI 保持拦截。
- 运行 C# 解决方案构建与 `git diff --check`；Godot Mono 不在本机运行。
