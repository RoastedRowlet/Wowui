if GetLocale() ~= "ruRU" then return end

local _, ns = ...
local L = ns.L

-- Russian. Rules and argument notes are in enUS.lua. Every count is written as
-- "label: %d" or "x%d": a noun after a number changes form (1, 2-4, 5+).

-- == General ==
L.UNKNOWN_SOURCE               = "Неизвестно"
L.TITLE_VERSION                = "%s v%s"

-- == Context Labels ==
L.CTX_CITY                     = "Город"
L.CTX_WITH_COMBAT              = "%s (в бою)"
L.CTX_DUNGEON                  = "Подземелье / M+"
L.CTX_DUNGEON_PLAIN            = "Подземелье"
L.CTX_PVP                      = "PvP"
L.CTX_RAID                     = "Рейд"
L.CTX_SCENARIO                 = "Сценарий"
L.CTX_WORLD                    = "Открытый мир"

-- == Cause Definitions ==
L.DEF_ADDON                    = "Этот аддон выполнял слишком много работы, пока игра отрисовывала один кадр."
L.DEF_ENGINE                   = "Один медленный кадр самой игры, часто при загрузке модели или эффекта заклинания. Дело не в вашем интерфейсе."
L.DEF_GC                       = "Игра ненадолго остановилась, чтобы очистить временную память, созданную вашими аддонами (сборка мусора). Короткие и редкие паузы - это нормально."
L.DEF_LOADING                  = "Вы только что сменили зону или попали в новое место, и игра его подгружала."
L.DEF_SUSTAINED                = "Ваши кадры медленные уже какое-то время, а не только этот. Это указывает на настройки графики или ваш ПК, а не на аддоны."
L.DEF_UNCLEAR                  = "Этот кадр длился слишком долго, но мы не смогли связать его ни с вашими аддонами, ни с явной причиной в игре."

-- == Overlay Headlines ==
L.HEADLINE_ENGINE              = "Скачок движка"
L.HEADLINE_ENGINE_TIP          = "Движок игры: обычно ничего делать не нужно. Если повторяется в одном месте, игра подгружает там ресурсы."
L.HEADLINE_GC                  = "Очистка памяти"
L.HEADLINE_GC_TIP              = "Очистка памяти: обычно ничего. Если случается постоянно, какой-то аддон может расходовать память впустую - проверьте главные источники."
L.HEADLINE_LOADING             = "Загрузка зоны"
L.HEADLINE_LOADING_TIP         = "Загрузка местности: это нормально. Если WoW стоит на быстром SSD, такие паузы короче."
L.HEADLINE_SUSTAINED           = "Затяжное замедление"
L.HEADLINE_SUSTAINED_TIP       = "Затяжное замедление: снизьте тени, дальность обзора или эффекты и закройте фоновые программы."
L.HEADLINE_UNCLEAR             = "Причина неясна"
L.HEADLINE_UNCLEAR_TIP         = "Источник неясен: пока ничего менять не нужно. Следите за разделами Недавние и Главные, чтобы заметить закономерность."

-- == Menu Options ==
L.MENU_BANNERS                 = "Всплывающие баннеры"
L.MENU_BANNERS_ALL             = "Все (фризы в реальном времени + итоги пулла)"
L.MENU_BANNERS_OFF             = "Выкл. (только значок и подсказка)"
L.MENU_BANNERS_SUMMARY         = "Только итоги пулла"
L.MENU_CLEAR_HIST              = "Очистить историю фризов"
L.MENU_GROWTH_AUTO             = "Авто (умная привязка)"
L.MENU_GROWTH_DIR              = "Направление баннеров"
L.MENU_GROWTH_LD               = "Влево и вниз"
L.MENU_GROWTH_LU               = "Влево и вверх"
L.MENU_GROWTH_RD               = "Вправо и вниз"
L.MENU_GROWTH_RU               = "Вправо и вверх"
L.MENU_LOCK                    = "Закрепить положение"
L.MENU_RESET                   = "Вернуть к меню"
L.MENU_SIZE                    = "Размер кнопки"
L.MENU_SIZE_DEFAULT            = "По умолчанию (размер меню)"
L.MENU_SIZE_M                  = "Средний (64x64)"
L.MENU_SIZE_S                  = "Маленький (32x32)"
L.PREVIEW_MODE                 = "Режим предпросмотра"

-- == Severity Levels ==
L.SEV_CALM                     = "Спокойно"
L.SEV_CRITICAL                 = "Критично"
L.SEV_ELEVATED                 = "Повышено"

-- == Slash Commands ==
L.SLASH_BANNERS                = "Всплывающие баннеры: %s"
L.SLASH_BANNERS_ALL            = "все (фризы в реальном времени и итоги пулла)"
L.SLASH_BANNERS_OFF            = "выкл. - цвет значка и подсказка продолжают работать"
L.SLASH_BANNERS_SUMMARY        = "только итоги пулла"
L.SLASH_DISABLED               = "Мониторинг отключён."
L.SLASH_ENABLED                = "Мониторинг включён."
L.SLASH_LOCKED                 = "Кнопка закреплена."
L.SLASH_RESET                  = "Кнопка возвращена под миникарту."
L.SLASH_UNLOCKED               = "Кнопка откреплена - перетащите её куда хотите."
L.SLASH_USAGE_BANNERS          = "/sa banners all|summary|off - какие всплывающие баннеры показывать"
L.SLASH_USAGE_HEADER           = "Команды StutterAlert:"
L.SLASH_USAGE_LOCK             = "/sa lock - закрепить кнопку на месте"
L.SLASH_USAGE_REPORT           = "/sa report - открыть полный отчёт и советы"
L.SLASH_USAGE_RESET            = "/sa reset - вернуть кнопку под миникарту"
L.SLASH_USAGE_TOGGLE           = "/sa toggle - включить или выключить мониторинг"
L.SLASH_USAGE_UNLOCK           = "/sa unlock - открепить, чтобы перетащить кнопку"

-- == Post-pull Summary ==
L.SUMMARY_PULL                 = "Последний пулл  -  фризы: %d (аддоны %d, игра %d)"
L.SUMMARY_PULL_CLEAN           = "Последний пулл: без фризов. Плавно."

-- == Tooltips ==
L.TT_ACTION_ADDON              = "- Фризы от аддонов: обновите, перенастройте или отключите постоянных нарушителей."
L.TT_ACTION_ENGINE             = "- Фризы игры/движка: обычно разовые, когда игра загружает модель или эффект. Если повторяются в одном месте, снизьте настройки графики."
L.TT_ACTION_HEADER             = "Как улучшить производительность:"
L.TT_CTX_COMBAT                = "в бою"
L.TT_CTX_ENEMIES               = "врагов: %d"
L.TT_CTX_LATENCY               = "мир %d ms"
L.TT_CTX_PREFIX                = "В этот момент: %s"
L.TT_HINT_BANNERS_OFF          = "Всплывающие баннеры убавлены. Мониторинг продолжается - ПКМ, чтобы изменить."
L.TT_HINT_CLEAR                = "Shift+ЛКМ - очистить историю"
L.TT_HINT_LOCKED               = "Открепите командой /sa unlock, чтобы переместить."
L.TT_HINT_MENU                 = "ПКМ - меню"
L.TT_HINT_UNLOCKED             = "Перетащите, чтобы переместить. Закрепите командой /sa lock."
L.TT_HITCH_EXPLAIN             = "Фриз - это один кадр, который отрисовывался слишком долго и дал заметное подёргивание."
L.TT_RECENT_HEADER             = "Недавние фризы"
L.TT_RECENT_NONE               = "Фризов пока не зафиксировано."
L.TT_RECENT_RIGHT              = "%d ms  -  %s  -  %s"
L.TT_RECENT_RIGHT_MULT         = "%d ms  -  x%d от обычного  -  %s"
L.TT_SEVERITY                  = "Уровень: %s"
L.TT_THROTTLED                 = "Мониторинг на паузе - частота кадров ограничена"
L.TT_THROTTLED_CVAR            = "Каждый кадр точно попадает в ваш лимит (%s), так что здесь нет фризов. Обнаружение возобновится само."
L.TT_THROTTLED_WHY             = "Все кадры одинаковой длины - это ограничение частоты кадров, а не фриз. Обнаружение возобновится само."
L.TT_TIME_HOUR                 = "%d ч назад"
L.TT_TIME_MIN                  = "%d мин назад"
L.TT_TIME_SEC                  = "%d сек назад"
L.TT_TOP_HEADER                = "Главные источники фризов (с последней очистки)"
L.TT_TOP_RIGHT                 = "фризы: %d  -  пик %d ms  -  %s"

-- == Granular Game Causes ==
L.HEADLINE_SCENE               = "Насыщенная сцена"
L.HEADLINE_SCENE_TIP           = "Насыщенная сцена: нормально на больших пуллах или в людных местах, когда игра загружает модели и эффекты. Поможет меньшая дальность обзора и плотность эффектов."
L.DEF_SCENE                    = "Одновременно появилось много существ, и игра загрузила их модели и эффекты за один кадр. Часто бывает на больших пуллах или в толпе. Дело не в аддонах."
L.HEADLINE_COMBAT_FX           = "Боевые эффекты"
L.HEADLINE_COMBAT_FX_TIP       = "Боевые эффекты: визуальные эффекты заклинаний и частицы, загружаемые посреди боя. Поможет снижение плотности заклинаний, плотности частиц и проецируемых текстур."
L.DEF_COMBAT_FX                = "Во время боя загрузился эффект заклинания, всплеск частиц или проецируемая текстура. Часто бывает на боссах и небольших группах. Дело не в аддонах."
L.HEADLINE_STREAMING           = "Подгрузка мира"
L.HEADLINE_STREAMING_TIP       = "Подгрузка мира: игра загружает местность, пока вы перемещаетесь. Больше всего помогает быстрый SSD; меньшая дальность обзора смягчает."
L.DEF_STREAMING                = "Игра подгружала местность и текстуры, когда вы попали на новую территорию. Часто бывает в полёте или верхом. Дело не в аддонах."

-- == Toast Banners ==
L.TOAST_ONE                    = "%s  -  %d ms"
L.TOAST_MANY                   = "%s  x%d  -  пик %d ms"

-- == Last Pulls (tooltip) ==
L.TT_PULLS_HEADER              = "Последние 5 пуллов (эта сессия)"
L.TT_PULLS_NONE                = "В этой сессии ещё нет завершённых пуллов."
L.TT_PULL_CLEAN                = "Чисто - без фризов"
L.TT_PULL_LINE                 = "фризы: %d (игра %d, аддоны %d)  -  худший %d ms"

-- == Post-pull Summary (additional) ==
L.SUMMARY_PULL_WORST           = "Последний пулл  -  фризы: %d, худший %s %d ms (игра: %d)"

-- == Tooltip hint (additional) ==
L.TT_HINT_EXPORT               = "ЛКМ - полный отчёт и советы"

-- == Export Report ==
L.EXPORT_SCOPE                 = "Данные ниже охватывают всё с момента последней очистки истории."
L.EXPORT_TLDR                  = "Зафиксировано фризов: %d  -  от аддонов: %d, от игры: %d."
L.EXPORT_TLDR_CLEAN            = "Фризов не зафиксировано. Пока всё плавно."
L.EXPORT_WORST                 = "Худший аддон: %s  -  %d ms (x%d от его обычной нагрузки)"
L.EXPORT_WORST_NOMULT          = "Худший аддон: %s  -  %d ms"
L.EXPORT_TOP_HEADER            = "Главные источники среди аддонов:"
L.EXPORT_TOP_LINE              = "  - %s  -  фризы: %d, пик %d ms"
L.EXPORT_CAUSES_HEADER         = "Причины в игре (не аддоны):"
L.EXPORT_CAUSE_LINE            = "  - %s: %d"
L.EXPORT_BASELINE              = "Типичное время кадра: %d ms"
L.EXPORT_BASELINE_WARMING      = "Типичное время кадра: ещё измеряется."

-- == Advice Panel ==
L.PANEL_REPORT_HEADER          = "Отчёт для отправки (Ctrl+C - копировать)"
L.ADVISE_WHY_HEADER            = "Откуда фризы?"
L.ADVISE_VERDICT_NONE          = "Фризов пока не зафиксировано. Поиграйте немного и загляните сюда снова."
L.ADVISE_VERDICT_GAME          = "Большинство фризов вызывает сама игра, а не ваши аддоны (%d из %d)."
L.ADVISE_VERDICT_ADDON         = "Большинство фризов вызывают ваши аддоны (%d из %d). Виновники - в отчёте справа."
L.ADVISE_WHERE                 = "Чаще всего они случаются: %s."
L.ADVISE_PAT_COMBAT            = "в бою"
L.ADVISE_PAT_TRAVEL            = "в пути"
L.ADVISE_PAT_ZONE              = "в зоне %s"
L.ADVISE_CAUSE_HEADER          = "Что их вызывает"
L.ADVISE_TRY_HEADER            = "Что можно попробовать"
L.ADVISE_RAID_NOTE             = "Ваши скачки сосредоточены в рейдах, поэтому ниже указаны ваши рейдовые настройки графики."
L.ADVISE_SETTINGS_OK           = "Ваши настройки графики и так скромные. Оставшиеся скачки, вероятно, связаны с оборудованием, драйверами или подгрузкой ресурсов - это не настройки, которые можно изменить здесь."
L.ADVISE_SETTINGS_HEADER       = "Ваши важные настройки"
L.ADVISE_SLIDER                = "Снизьте %s - сейчас %s (по умолчанию %s)"
L.ADVISE_TOGGLE                = "Отключите %s (сейчас вкл.)"
L.ADVISE_SETTING_LINE          = "%s: %s (по умолчанию %s)"
L.ADVISE_CHANGE_WHERE          = "Это меняется в меню игры: Система > Графика (и Дополнительно)."
L.ADVISE_AIO                   = "У вас также есть Advanced Interface Options - введите /aio, чтобы открыть полный список CVar."

L.ADVISE_TIP_COMBAT_FX         = "В бою загружаются эффекты заклинаний и частицы. Настройки ниже сильнее всего уменьшают эту нагрузку."
L.ADVISE_TIP_SCENE             = "Большие пуллы и толпы загружают много моделей сразу. Больше всего помогают плотность частиц и дальность обзора."
L.ADVISE_TIP_STREAMING         = "В пути мир подгружается с диска. Больше всего помогает SSD; снизьте дальность обзора, чтобы игра подгружала меньше за раз."
L.ADVISE_TIP_SUSTAINED         = "Ваши кадры медленные в целом, а не только скачками. Снизьте самые тяжёлые настройки и закройте фоновые программы (браузеры, оверлей Discord)."
L.ADVISE_TIP_ENGINE            = "Это единичные кадры, пока игра загружает модель или эффект. Часто это нормально; настройки ниже делают их реже."
L.ADVISE_TIP_GC                = "Частая очистка памяти обычно означает расточительный аддон. Посмотрите главные источники среди аддонов в отчёте."
L.ADVISE_TIP_LOADING           = "Скачки при загрузке - это нормально. Быстрый SSD их сокращает; больше менять нечего."

-- == Units and shared fragments ==
L.UNIT_KB                      = "%d КБ"
L.UNIT_MB                      = "%.1f МБ"
L.LIST_SEP                     = ", "
L.DUR_HM                       = "%d ч %d мин"
L.DUR_M                        = "%d мин"
L.DUR_S                        = "%d сек"

-- == Allocation buckets ==
L.ALLOC_NONE                   = "почти без выделения памяти"
L.ALLOC_SMALL                  = "с небольшим выделением памяти"
L.ALLOC_MEDIUM                 = "с выделением нескольких МБ"
L.ALLOC_LARGE                  = "с большим выделением памяти"

-- == Export Report: detail ==
L.EXPORT_CLIENT                = "Клиент %s (сборка %s)"
L.EXPORT_CLIENT_FLAVOR         = "Клиент %s %s (сборка %s)"
L.EXPORT_SPAN                  = "Измерено за %s игры  -  примерно %.1f в минуту."
L.EXPORT_THROTTLED             = "Не учтено выше ещё %s: частота кадров была ограничена (окно в фоне или заданный лимит FPS), поэтому ничего не измерялось."
L.EXPORT_BASELINE_CAP          = "Примечание: частота кадров ограничена значением %d (%s). Это нижняя граница здесь, и никакая настройка графики ниже её не поднимет - измените сам лимит."
L.EXPORT_CHRONIC_HEADER        = "Постоянная нагрузка от аддонов (в каждом кадре, с фризом или без):"
L.EXPORT_CHRONIC_TOTAL         = "  Все аддоны вместе: примерно %.2f ms каждого кадра."
L.EXPORT_CHRONIC_LINE          = "  - %s: %.2f ms/кадр"
L.EXPORT_TOP_LINE_VER          = "  - %s (%s)  -  фризы: %d, пик %d ms"
L.EXPORT_D_WHERE               = "      Где: %s"
L.EXPORT_D_CTX                 = "%s x%d"
L.EXPORT_D_SHARE               = "      В худший момент это было %d%% всего кадра"
L.EXPORT_D_SHARE_ALL           = "      В худший момент он занял практически весь кадр"
L.EXPORT_D_LIBRARY             = "      Это общий пакет библиотек - нагрузка принадлежит аддону, который его вызвал, а игра не позволяет его определить"
L.EXPORT_D_LIBRARY_HOST        = "      Это общий пакет библиотек (поставляется с %s) - нагрузка принадлежит аддону, который его вызвал"
L.EXPORT_D_MULT                = "      Пик: x%d от обычной нагрузки"
L.EXPORT_D_ALLOC               = "      Выделено %s в этом кадре"
L.EXPORT_D_PERIOD              = "      Регулярный ритм: примерно каждые %d сек (похоже на таймер)"
L.EXPORT_D_OVER                = "      Собственный счётчик сессии игры  -  кадров дольше 100 ms: %d, дольше 500 ms: %d"
L.EXPORT_D_OVER_NOTE           = "      (клиент считает всю сессию, включая экраны загрузки, которые StutterAlert не учитывает)"
L.EXPORT_D_CO                  = "      Давал скачки одновременно с %s (x%d) - вероятно, общий триггер"
L.EXPORT_D_VER_SPAN            = "      Записано на версиях с %s по %s"
L.EXPORT_D_VER_NOW             = "      Записано на версии %s; сейчас у вас %s"
L.EXPORT_D_MEM                 = "      Используемая память: %s"
L.EXPORT_D_MEM_GROW            = "      Используемая память: %s (выросла на %s с последней проверки)"
L.EXPORT_D_SIG                 = "      %d из %d с общей закономерностью: %s"
L.EXPORT_D_SIG_ALL             = "      У всех фризов общая закономерность: %s"
L.EXPORT_SIG_COMBAT            = "в бою"
L.EXPORT_SIG_CALM              = "вне боя"
L.EXPORT_SIG_EVENT             = "вызвано %s"

-- == Export Report: events ==
L.EXPORT_D_EV_PEAK             = "      События в этом кадре: %s"
L.EXPORT_D_EV_ITEM             = "%s x%d"
L.EXPORT_D_EV_COMMON           = "      Самое частое событие (%d из %d): %s"
L.EXPORT_D_EV_PREFIX           = "      Трафик аддонов: сообщения с префиксом %s (x%d)"
L.EXPORT_D_EV_BURST            = "      Ещё событий в этом кадре: %d  -  всплеск событий"
L.EXPORT_D_EV_NONE             = "      В этом кадре не было событий - работа шла из OnUpdate или таймера"

-- == CVar display names (the game's own options wording) ==
L.CVAR_MAX_FPS                 = "Макс. частота кадров"
L.CVAR_MAX_FPS_BK              = "Макс. частота кадров в фоне"
L.CVAR_VIEW_DISTANCE           = "Дальность обзора"
L.CVAR_ENV_DETAIL              = "Детализация окружения"
L.CVAR_GROUND_CLUTTER          = "Плотность растительности"
L.CVAR_SHADOW                  = "Качество теней"
L.CVAR_LIQUID                  = "Детализация жидкостей"
L.CVAR_SUNSHAFTS               = "Солнечные лучи"
L.CVAR_PARTICLE                = "Плотность частиц"
L.CVAR_SSAO                    = "Фоновое затенение"
L.CVAR_DEPTH                   = "Эффекты глубины"
L.CVAR_TEXTURE_RES             = "Разрешение текстур"
L.CVAR_PROJECTED               = "Проецируемые текстуры"
L.CVAR_SPELL_DENSITY           = "Плотность заклинаний"

-- == Client / Flavor Names ==
L.FLAVOR_RETAIL                = "Retail"
L.FLAVOR_MISTS                 = "Mists of Pandaria Classic"
L.FLAVOR_CATA                  = "Cataclysm Classic"
L.FLAVOR_WRATH                 = "Wrath of the Lich King Classic"
L.FLAVOR_TBC                   = "Burning Crusade Classic"
L.FLAVOR_CLASSIC_ERA           = "Classic Era"
