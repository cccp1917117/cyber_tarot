# 占卜方法 v1

占卜方法负责定义“抽什么、抽几次、放在哪个位置、是否区分正逆位”。提示物和塔罗牌仍是独立内容，实际抽取结果保存在占卜记录中。

## 初始方法

| 方法代码 | 名称 | 位置 | 内容类型 |
|---|---|---|---|
| `prompt-single` | 单提示物映照 | 当下映照 | 1 张提示物 |
| `prompt-three-time` | 提示物三时占卜 | 过去／现在／未来 | 3 张提示物 |
| `tarot-single` | 单张塔罗指引 | 今日指引 | 1 张塔罗牌 |
| `tarot-three-time` | 塔罗三时牌阵 | 过去／现在／未来 | 3 张塔罗牌 |
| `hybrid-theme-insight-action` | 主题・洞察・行动 | 主题／洞察／行动 | 1 张提示物＋2 张塔罗牌 |

## 方向规则

- 提示物使用 `neutral`，没有正逆位。
- 塔罗牌位置使用 `upright` 或 `reversed`。
- `back_is_reversible = false` 的牌组需要在界面中隐藏卡背方向，避免提前暴露正逆位。

## 抽取策略

- `random`：从位置允许的内容类型中等概率随机抽取。
- `weighted`：根据标签、星座、MBTI 或其他关联权重调整概率。
- `manual`：由用户或占卜师手动选择。

初始混合方法的“主题”位置使用 `weighted`，可以优先匹配用户上下文；其余位置使用随机抽取。

## 数据结构

```text
divination_methods
└── divination_method_positions
    └── divination_position_entity_kinds

reading_sessions
└── reading_draws
```

- `divination_methods`：方法名称、稳定代码、版本和状态。
- `divination_method_positions`：位置顺序、引导语、抽取数量、抽取策略和方向规则。
- `divination_position_entity_kinds`：限制位置允许提示物还是塔罗牌。
- `reading_sessions`：用户问题、使用的方法版本和占卜状态。
- `reading_draws`：实际抽到的内容、位置、方向、解释和用户回应。

数据库会拒绝：

- 在提示物位置放入塔罗牌，或反过来。
- 在提示物位置使用正位或逆位。
- 使用不属于当前方法的位置。
- 同一次占卜重复抽到同一个内容实体。
- 超过某个位置定义的抽取数量。

## 混合方法流程

```text
用户问题
  ↓
主题：抽取 1 张提示物
  ↓
洞察：抽取 1 张塔罗牌
  ↓
行动：抽取 1 张塔罗牌
  ↓
综合解释与用户回应
```

新增方法时，只需向方法、位置和允许类型三张表写入新配置，不需要建立新的结果表。
