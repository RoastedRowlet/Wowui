-- ExwindTools 的游戏内更新日志正文。由发布打包器写入；Core 只提供共享查看窗口。
ExwindTools_ChangelogData = {
    changelog = {
        version = "v26.9.3.1123",
        title = "v26.9.3.1123 更新日志",
        publishedAt = "2026-09-03 11:23",
        fontSize = 14,
        content = [[
@H1@ v26.9.3.1123

@CN@ @H2@ 状态管理系统
@CN@ 修复了 副本状态转移回调时 调用StaticPopup可能导致受保护界面污染报错的问题

@EN@ @H2@ State System
@EN@ Fixed an issue where invoking StaticPopup during instance state transitions could cause protected UI taint errors.

@H1@ v26.9.1.0409

@CN@ @H2@ 性能优化
@CN@ - 优化了状态系统的和一些事件的性能

@CN@ @H2@ 锚点
@CN@ - 修复了大多锚点问题 如果还有错误的情况 建议重置单模块(拉到底最下面点击)

@EN@ @H2@ Performance Optimizations
@EN@ - Improved the performance of the state system and certain events.

@EN@ @H2@ Anchors
@EN@ - Fixed most anchor-related issues. If you still encounter problems, try resetting the affected module individually by scrolling to the bottom of its settings page and clicking the reset button.

@H1@ v26.8.28.2349

@CN@ @H2@ 大秘境分数线
@CN@ - 更新S2赛季分数线

@CN@ @H2@ 周围怪物DEBUFF
@CN@ - 新增按天赋载入

@H1@ v26.8.24.2151

@CN@ @H2@ 0824测试
@CN@ - TEST
        ]],
    },
}
