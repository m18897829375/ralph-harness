# ralph-harness 修改方案

> 状态：待上游 PR 合并 | 涉及文件：3 个共 ~30 处修改
> 目标：将 grep 搜索方式替换为 search_index.py

## 涉及文件

| 文件 | 位置数 | 修改类型 |
|------|:--:|------|
| subprojects/ralph-harness/ralph.sh | ~10 | assemble_agent_context() 索引区块 |
| subprojects/ralph-harness/generator-prompt.md | ~9 | grep -> search_index.py |
| subprojects/ralph-harness/evaluator-prompt.md | ~12 | grep -> search_index.py |

## 核心替换模式

```
旧: grep "keyword" skill-index.json | grep -i "filter"
    grep -E "cat1|cat2" cli-index.json

新: python3 scripts/search_index.py --type skill --keyword "keyword" --category "filter"
    python3 scripts/search_index.py --type cli --category cat1 --category cat2
```

## 文件 1：ralph.sh (行 653-697)

函数 assemble_agent_context() 中：

- 行 654-655: SKILL_INDEX/CLI_INDEX 变量 -> SEARCH_SCRIPT 变量
- 行 657: 文件存在检查改为 [ -f "$SEARCH_SCRIPT" ]
- 行 659-660: "INDEX TABLE AWARENESS" -> "SEARCH INDEX"
- 行 663-682: 整个 SKILL INDEX if 块替换为 search_index.py 使用示例
- 行 684-693: 整个 CLI INDEX if 块替换为 search_index.py CLI 用法
- 行 695: grep 查询顺序 -> search_index.py 命令

## 文件 2：generator-prompt.md

- 行 104: "搜索索引表" 描述更新
- 行 108-113: "索引表参考" -> "搜索索引参考"，grep -> search_index.py
- 行 144-156: Step 2.5 操作步骤 grep -> search_index.py
- 行 210-212: build 阶段搜索 grep -> search_index.py

## 文件 3：evaluator-prompt.md

- 行 104-109: "索引表参考" -> "搜索索引参考"，grep -> search_index.py
- 行 162-171: 工具合理性验证 grep -> search_index.py
- 行 252-268: 评估工具选择 grep -> search_index.py

## 上游同步路径

1. Fork https://github.com/m18897829375/ralph-harness
2. 创建分支，应用以上修改
3. 提交 PR 到上游
4. PR 合并后: cd subprojects/ralph-harness && git pull
5. 删除本文件

## 前置依赖

依赖 harness 项目中 scripts/search_index.py 已创建。
