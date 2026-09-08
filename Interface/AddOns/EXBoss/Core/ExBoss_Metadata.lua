-- [[ ExBoss Metadata ]]
-- 此文件由打包脚本自动生成或修改，用于控制版本号。
-- 请勿手动通过 Git 提交修改此文件中的版本号，除非你是为了测试。

ExBoss_MetaData = {
    version = "v26.9.8.1030",
    changelog = {
        version = "v26.9.4.0415",
        title = "v26.9.4.0415 更新日志",
        publishedAt = "2026-09-04 04:15",
        fontSize = 14,
        content = [[
@H1@ v26.9.4.0415

@CN@ @H2@ 小怪CD
@CN@ - 现在在设置勾选DPS/治疗 不启用坦克技能提示时 会正确的过滤

@CN@ @H2@ 配置系统
@CN@ - 新增配置过滤功能

@EN@ @H2@ Trash Mob CDs
@EN@ - Tank-skill alerts are now correctly filtered when “Disable tank-skill alerts for DPS/Healers” is enabled.

@EN@ @H2@ Profile System
@EN@ - Added profile filtering.

@H1@ v26.9.3.1122

@CN@ @H2@ 小怪CD
@CN@ - 修复了L1预锁定时不播放首个技能语音的问题
@CN@ - 优化L1预锁定逻辑

@EN@ @H2@ Trash Mob Cooldowns
@EN@ - Fixed an issue where the first ability voice alert did not play during L1 pre-locking.
@EN@ - Optimized the L1 pre-locking logic.

@H1@ v26.9.1.1224

@CN@ @H2@ 性能优化
@CN@ - 本轮整体性能优化初步完成 性能消耗大幅度降低

@CN@ - 我们注意到了一个EXUI渲染时高频重绘的问题 现在将计时条改完传入DUR渲染后
@CN@ 整体性能较S2发布时性能消耗降低90% (如果开启计时条对比)

@CN@ - 得益于我们的事件分发系统架构 我们在(开发版本)做了性能预警功能 现在我们可以非常快的在第一时间发现性能问题并处理

@CN@ - 往后我们预计每周进行简单的性能审查优化 并且每半个月进行一次深度的性能优化

@CN@ - 还有很多地方可以优化 但是以当前的性能表现优化后几乎对体感和帧数不明显 因此优先级较低

@CN@ @H2@ EXUI 和框架池
@CN@ - 界面重载后的首次进入世界会异步预创建 TimerBar、BunBar 和姓名板 CD 图标，达到目标后再释放，避免战斗中首次创建多个控件造成瞬时卡顿。

@CN@ - 姓名板CD图标改为专用完整复合池。姓名板消失后图标会归还池中，不再随 nameplate1~40隐藏。

@CN@ - TimerBar Collection 的 ItemRoot 已接入框架池，释放后可以完整复用。

@CN@ - 预加载使用独立的低预算异步任务。若过程中进入战斗，会先释放已完整创建的对象，再执行 CancelAsync()脱战后自动重新开始。

@CN@ - PS:Lua Coroutine 会分配独立调用栈 此内存增长是正常现象 并属于可回收内存。

@CN@ @H2@ 语音包
@CN@ - 第三方语音包仅在首次查询时扫描一次，并在当前登录会话中缓存包列表与目录索引，避免每次播放声音时重复扫描。

@CN@ @H2@ EXBoss
@CN@ - 重做 TimerBar 运行时渲染逻辑。倒数文字和进度填充现在通过 EXUI 使用暴雪原生 Duration 驱动。
@CN@ - 普通帧不再为每条活动计时条重复构建和应用完整 Presentation；只有新增、时间校正或名称、图标、颜色等静态内容变化时才刷新。
@CN@ - 到零等待、施法释放、校时、A/B 怪物改判以及 Scheduler 调度规则保持不变。
@CN@ - 本次优化覆盖 Boss、小怪、Pull Timer、Test Timer 和 External Timer，不仅限于小怪计时条。

@CN@ @H2@ 小怪CD
@CN@ - 我们已经收到一些零散的场景下某些技能语音没提示的问题 将在明天修复

@EN@ @H2@ Performance Optimizations
@EN@ - The initial phase of this performance optimization pass is complete, with a significant reduction in overall resource usage.

@EN@ - We identified a high-frequency redraw issue in EXUI. After switching timer bars to Duration-based rendering, overall performance cost has been reduced by approximately 90% compared with the S2 release when timer bars are enabled.

@EN@ - Thanks to our event-dispatch architecture, we have added performance alerts to the development build. This allows us to identify and address performance issues much more quickly.

@EN@ - Going forward, we plan to conduct a lightweight performance review and optimization pass every week, along with an in-depth optimization pass every two weeks.

@EN@ - There are still more areas that could be optimized. However, given the current performance level, further improvements would have little noticeable effect on responsiveness or frame rate, so they are currently a lower priority.

@EN@ @H2@ EXUI and Frame Pools
@EN@ - After the first login following a UI reload, TimerBar, BunBar, and nameplate cooldown icons are pre-created asynchronously and then released into their pools once the target capacity is reached. This avoids brief hitches caused by creating multiple controls for the first time during combat.

@EN@ - Nameplate cooldown icons now use a dedicated composite frame pool. When a nameplate disappears, its icons are returned to the pool instead of accumulating as hidden objects across nameplate1–40.

@EN@ - TimerBar Collection ItemRoot frames are now pooled and can be fully reused after release.

@EN@ - Preloading uses a separate low-budget asynchronous task. If combat begins while preloading is in progress, all fully created objects are released before CancelAsync() is called. Preloading resumes automatically after combat ends.

@EN@ - Note: Lua coroutines allocate independent call stacks. The resulting memory increase is normal and reclaimable.

@EN@ @H2@ Voice Packs
@EN@ - Third-party voice packs are now scanned only on the first lookup. Their pack list and directory index are cached for the current login session, preventing repeated scans whenever a sound is played.

@EN@ @H2@ EXBoss
@EN@ - Reworked the TimerBar runtime rendering pipeline. Countdown text and progress fills are now driven through EXUI using Blizzard's native Duration system.
@EN@ - Active timer bars no longer rebuild and apply their full Presentation every frame. They are refreshed only when first created, time-corrected, or when static content such as the name, icon, or color changes.
@EN@ - Zero-time waiting, cast release, time calibration, A/B mob reassignment, and Scheduler rules remain unchanged.
@EN@ - This optimization applies to Boss, trash mob, Pull, Test, and External timers—not only trash mob timer bars.

@EN@ @H2@ Trash Mob Cooldowns
@EN@ - We have received reports of a few isolated situations where voice alerts for certain abilities do not play. We plan to fix these issues tomorrow.

@H1@ v26.9.1.0408

@CN@ @H2@ 性能优化
@CN@ - 优化了状态系统的和一些事件的性能

@CN@ @H2@ 锚点
@CN@ - 修复了大多锚点问题 如果还有错误的情况 建议重置单模块(右上角点击)

@EN@ @H2@ Performance Optimizations
@EN@ - Improved the performance of the state system and certain events.

@EN@ @H2@ Anchors
@EN@ - Fixed most anchor-related issues. If you still encounter problems, try resetting the affected module individually by scrolling to the Top-right of its settings page and clicking the reset button.

@H1@ v26.8.31.1641

@CN@ @H2@ 状态系统
@CN@ - 我们注意到了某些插件会在某些场景下出现一些问题 导致客户端会在极短时间内收到3-4千条事件
@CN@ (然后导致我们这些依赖正常低频事件刷新的插件卡顿 背锅) 我们目前已经加上事件节流来解决这个问题
@CN@ - 补充地图判定刷新事件 这解决了部份小怪CD错误的问题

@CN@ @H2@ 错误修复
@CN@ - 修复了使用Criteria获取副本首领进度时 因为非zhCN客户端导致的小怪判定错误
@CN@ (这是一个很早期的偷懒硬编码 修复后会解决一些怪物判定的问题)

@CN@ @H2@ 说明
@CN@ - 小怪内置CD因为12.0暴雪的限制 我们是采用推理的方式去锁定怪物 推理分为两个层面
@CN@ - L1的意思是 在第一层就能够锁定 : 第一层通常是各种静态资料 如地图位置等等
@CN@ (通常意味着你开怪瞬间就能看到技能CD情况)
@CN@ - L2的意思是 在L1过滤后 如果候选还存在2只以上的怪物 则会根据怪物的施法特征进行推理
@CN@ (通常意味着你开怪后看不到技能CD/又或者是错误的技能CD 但是在第一次施法时能够正确的校准并且正确的提醒)
@CN@ - 语音和技能CD是两种不同的调度 语音需要在施法瞬间播放 因此能推理的条件有限
@CN@ - 技能CD则是可以在怪物读条完后收集特征再推里 所以准确度较高
@CN@ - 本赛季暴雪不修改的情况下 我们能慢慢调试恢复到90%以上的准确率

@CN@ @H2@ %i:1762
@CN@ - 重做了1号BOSS后的4波怪物 现在能够在推理L1直接被锁定(如果不额外拉取别的怪物情况下)
@CN@ - 修复了整个副本大多怪物的判定问题
@CN@ - 修复了%n:138489技能不提示的问题 (新增了这只怪物的技能语音/配置作者需要补充修改)

@CN@ @H2@ %i:2923
@CN@ - 重做了大多数的小怪 并解决了大多数问题
@CN@ - 1/2号BOSS后面的小怪 仍然需要在读条开始时才能锁定视别(或是预先推理 然后读条开始时校准)

@CN@ @H2@ 开发计划
@CN@ - 我们会在今天会做一次性能审查和优化

@EN@ ## State System
@EN@ - We identified an issue where certain addons can, in some situations, cause the client to receive 3,000–4,000 events within a very short period of time.
@EN@ This can cause addons like ours, which rely on normal low-frequency event updates, to lag and take the blame. We have now added event throttling to address this.
@EN@ - Added map-detection refresh events. This resolves some incorrect trash cooldown detections.

@EN@ ## Bug Fixes
@EN@ - Fixed incorrect trash identification caused by non-zhCN clients when using Criteria to obtain dungeon boss progress.
@EN@ This was an early hardcoded shortcut; fixing it resolves several trash-identification issues.

@EN@ ## Notes
@EN@ - Due to Blizzard's 12.0 restrictions, built-in trash cooldowns identify mobs through inference. This inference has two layers.
@EN@ - L1 means a mob can be identified in the first layer. This layer usually uses static information, such as map location.
@EN@ This normally means you can see skill cooldowns as soon as combat starts.
@EN@ - L2 means that, after L1 filtering, two or more candidates still remain. The addon then identifies the mob through its casting characteristics.
@EN@ This normally means you may not see skill cooldowns, or may see incorrect cooldowns, when combat starts. However, the addon can calibrate correctly on the first cast and provide accurate alerts afterward.
@EN@ - Voice alerts and skill cooldowns use two separate scheduling systems. Voice alerts must play at the moment a cast begins, so the available inference conditions are limited.
@EN@ - Skill cooldowns can collect features after a cast finishes before making an inference, so their accuracy is generally higher.
@EN@ - As long as Blizzard does not make further changes this season, we can gradually test and restore accuracy to above 90%.

@EN@ ## %i:1762
@EN@ - Reworked the four trash waves after the first boss. They can now be identified directly at L1, provided no additional mobs are pulled.
@EN@ - Fixed identification issues for most trash mobs in the dungeon.
@EN@ - Fixed %n:138489 skills not being announced. Added this mob's skill voice/configuration data; configuration authors will need to update their setups.

@EN@ ## %i:2923
@EN@ - Reworked most trash mobs and resolved most issues.
@EN@ - Trash after the first and second bosses still needs to be identified when casting begins, or inferred in advance and calibrated when casting starts.

@EN@ ## Development Plan
@EN@ - We will conduct a performance review and optimization pass today.

@H1@ v26.8.29.2102

@CN@ @H2@ 通用
@CN@ - 修复了一些会导致报错的问题

@CN@ @H2@ 所有小怪和BOSS
@CN@ - 因为暴雪在近期又改了一些小怪的身份 所以导致一些功能原本好的又失效
@CN@ - 我们当前已经收集完所有小怪的相关问题

@CN@ - "所有问题都会在这周末修复完"

@CN@ - (因为暴雪的限制 不可能做到100% 但是至少周末后能修复到90%以上)
@CN@ - 剩余10%我们会在之后做针对性的处里(如果技术上能做到的话)

@CN@ @H2@ 关于BOSS
@CN@ - 所有的BOSS额外提示我们也会在周末完成 由于时间关系暂时无法给所有设置都有自定义选项

@EN@ @H2@ General
@EN@ - Fixed several issues that could cause errors.

@EN@ @H2@ All Trash Mobs and Bosses
@EN@ - Blizzard recently changed the identities/IDs of some trash mobs again, which caused some previously working features to stop functioning.
@EN@ - We have now finished collecting all known issues related to trash mobs.

@EN@ - "All of these issues will be fixed by the end of this weekend."

@EN@ - Due to Blizzard's restrictions, it is impossible to achieve 100% functionality, but we expect to have at least 90% of these issues fixed by the end of the weekend.
@EN@ - We will address the remaining 10% individually afterward, where technically possible.

@EN@ @H2@ About Bosses
@EN@ - We will also finish adding all additional boss alerts by the end of the weekend.
@EN@ - Due to time constraints, we are currently unable to provide customizable options for every setting.

@H1@ v26.8.28.0712

@CN@ @H2@ 通用
@CN@ - 临时修复 %i:1762 的一些小怪问题
@CN@ - 仍然有一些小怪没修复 我们会在这两天陆续修复
@CN@ - 怪物数量的预锁定现在会在5秒缓存后释放
@CN@ - 删除了所有依赖仇恨事件的逻辑 现在依赖怪物战斗的State Transition来做CallBack

@CN@ @H2@ 公告
@CN@ - 我们注意到了暴雪对一些怪物的判断逻辑进行了改动修复 我们正在针对这些怪物的推理逻辑重做中 预计24小时内修复完成

@CN@ @H2@ WAGO
@CN@ - 升级了导入API到V7 如果你是配置分享作者
@CN@ 该使用新的EXBossWagoAPI:ImportProfile()来导入配置 (建议重新生成字符串)

@EN@ @H2@ General
@EN@ - Temporarily fixed issues affecting some trash mobs in %i:1762. More mobs still need fixes and will be addressed over the next two days.
@EN@ - Trash-mob count pre-reservations are now released after the 5-second cache expires.
@EN@ - Removed all threat-event-based logic. Runtime updates now rely on trash combat State Transition callbacks.

@EN@ @H2@ Announcement
@EN@ - We have noticed that Blizzard changed the identification behavior for certain mobs. We are rebuilding the inference logic for those trash and expect to complete the fixes within 24 hours.

@EN@ @H2@ WAGO
@EN@ - Updated the import API to V7. If you are a profile-sharing author, use the new EXBossWagoAPI:ImportProfile() to import profiles. Regenerating your export strings is recommended.

@H1@ v26.8.25.0013

@CN@ @H2@ 通用

@CN@ - 新的更新日志系统上线 以后每次更新都会主动告知更新内容和后续修复/开发计划

@CN@ @H2@ 通用设置
@CN@ - 加入了一键关闭团本提示勾选框
@CN@ - 加入了施法进度条的开关

@CN@ @H2@ 施法进度条
@CN@ - 修复了一些施法进度条不显示的问题(大多都在BOSS)
@CN@ - 如果还有遇到任何施法进度条不显示的地方请回报给我 谢谢!

@CN@ @H2@ 中央5秒倒数
@CN@ - 重做了整套系统 现在可以完全正常显示 如果你当前设置导致图标/时间偏移比较多
@CN@ 可以在设置页面的预览面板直接用鼠标拖动到正确位置

@CN@ @H2@ %i:2825
@CN@ - 修复了 %s:1252825 不显示的问题 现在会正确显示冷却时间和持续时间

@EN@ @H2@ General

@EN@ - The new changelog system is now live. From now on, every update will automatically notify you of what has changed and what fixes or features are planned next.

@EN@ @H2@ General Settings
@EN@ - Added a checkbox to disable all raid alerts with one click.
@EN@ - Added a toggle for cast bars.

@EN@ @H2@ Cast Bars
@EN@ - Fixed several issues where cast bars failed to appear, mostly during boss encounters.
@EN@ - If you still encounter any missing cast bars, please report them to me. Thank you!

@EN@ @H2@ Central 5-Second Countdown
@EN@ - Reworked the entire system, which should now display correctly. If your current settings cause the icon or timer text to be significantly offset,
@EN@ you can drag them directly to the correct position in the preview panel on the settings page.

@EN@ @H2@ %i:2825
@EN@ - Fixed an issue where %s:1252825 was not displayed. Its cooldown and duration will now appear correctly.

@H1@ v26.8.23.1113

@CN@ @H2@ 测试
@CN@ - 这是一个测试内容

@EN@ @H2@ TEST
@EN@ - TEST UPDATE
        ]],
    },
}
