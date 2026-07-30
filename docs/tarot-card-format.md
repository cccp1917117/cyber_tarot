# 塔罗牌格式规范 v1.0

本规范定义项目中一张塔罗牌的稳定身份、数据库表示、JSON 交换格式和图片要求。初始标准采用 RWS 78 张体系，自定义牌仍可扩展。

## 1. 两层模型

塔罗牌分成两层：

- `tarot_archetypes`：跨套牌不变的原型，例如“愚者”或“圣杯三”。
- `tarot_cards`：某套具体牌中的实现，包含该套牌的名字、牌义、图片和描述。

一副新牌组应创建 78 条 `tarot_cards`，分别引用已有的 78 条 `rws-78` 原型。不要为同一个新牌组复制一套原型。

## 2. 稳定牌码

牌码使用小写 ASCII，以连字符分隔。一旦发布，不因翻译或显示名称改变。

### 大阿卡纳

格式为 `major-NN`，编号为 `00` 至 `21`：

```text
major-00  愚者
major-01  魔术师
...
major-21  世界
```

本项目采用 RWS 顺序：`major-08` 为力量，`major-11` 为正义。

### 小阿卡纳

格式为 `minor-{suit}-{rank}`。

花色：

| 代码 | 中文 |
|---|---|
| `wands` | 权杖 |
| `cups` | 圣杯 |
| `swords` | 宝剑 |
| `pentacles` | 星币 |

点数：

```text
ace, two, three, four, five, six, seven,
eight, nine, ten, page, knight, queen, king
```

例如：

```text
minor-cups-three
minor-swords-queen
minor-pentacles-ace
```

### 自定义牌

自定义牌使用 `custom-` 前缀，例如 `custom-cosmic-gate`，并将 `arcana_type` 设为 `custom`。自定义牌可以不引用标准原型。

## 3. 固定顺序

`sequence_no` 从 0 开始：

- `0–21`：大阿卡纳。
- `22–35`：权杖。
- `36–49`：圣杯。
- `50–63`：宝剑。
- `64–77`：星币。

每个花色内部依次为王牌、二至十、侍从、骑士、王后、国王。

## 4. 牌义格式

正位和逆位必须分开保存；关键词必须是数组，不能保存成逗号拼接的字符串。

```json
{
  "meanings": {
    "upright": {
      "keywords": ["开始", "自由", "信任"],
      "meaning": "带着开放的心踏出第一步。"
    },
    "reversed": {
      "keywords": ["鲁莽", "迟疑", "风险"],
      "meaning": "重新评估风险与准备程度。"
    }
  }
}
```

数据库映射：

| JSON 字段 | 数据库字段 |
|---|---|
| `meanings.upright.keywords` | `tarot_cards.upright_keywords` |
| `meanings.upright.meaning` | `tarot_cards.upright_meaning` |
| `meanings.reversed.keywords` | `tarot_cards.reversed_keywords` |
| `meanings.reversed.meaning` | `tarot_cards.reversed_meaning` |

## 5. 图片规范

- 文件格式：PNG。
- MIME：`image/png`。
- 方向与比例：竖版，推荐严格使用 `2:3`。
- 最低尺寸：`1200 × 1800 px`。
- 色彩空间：sRGB。
- 文件路径：`tarot/{deck_slug}/{card_code}.png`。
- 每张图片记录字节数、宽高、SHA-256、替代文本和版权归属。

示例：

```text
tarot/rider-waite-smith/card-back.png
tarot/rider-waite-smith/major-00.png
tarot/rider-waite-smith/minor-cups-three.png
```

数据库只保存 `storage_key` 和文件元数据，图片本体放在文件系统或对象存储。

### 卡背

卡背属于整个牌组，通过 `tarot_decks.back_image_asset_id` 绑定，不在 78 张单牌中重复保存。

- 路径固定为 `tarot/{deck_slug}/card-back.png`。
- 不同牌组使用不同的图片资源。
- `back_is_reversible = true` 表示卡背旋转 180° 后仍然对称。
- 若 `back_is_reversible = false`，实体抽牌时可能从卡背方向提前看出正逆位，界面应避免展示方向。

## 6. 星座与 MBTI

星座、MBTI、元素、行星等不写入 `tarot_cards`。它们通过 `entity_term_associations` 关联，以便：

- 一张牌对应多个星座或人格类型。
- 记录 `relation_code`、`weight` 和解释。
- 将来增加新的关联体系而不修改塔罗牌表。

## 7. JSON 交换格式

机器校验文件位于：

```text
schemas/tarot-card.schema.json
```

完整示例位于：

```text
examples/tarot-card.major-00-fool.json
```

导入程序应先通过 JSON Schema 校验，再按以下顺序写入数据库：

1. 写入或复用 `media_assets`。
2. 创建 `catalog_entities`。
3. 写入 `tarot_cards`。
4. 将 `associations` 拆分写入 `entity_term_associations`。

## 8. 版本规则

- 当前版本：`1.0`。
- 新增可选字段：保持 `1.x`。
- 删除字段、改变字段语义或修改稳定牌码：升级到 `2.0`。
- 已发布的 `card_code`、`archetype_code` 和 `deck_slug` 不可复用给其他对象。
