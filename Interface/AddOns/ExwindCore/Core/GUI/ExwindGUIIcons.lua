-- 统一图标注册表：登记 Textures/Icons/Lucide 目录里已随插件发布的图标 ID。
-- 图标来自 Lucide（ISC 许可，部分 Feather 派生图标为 MIT，见 Textures/Icons/Lucide/LICENSE.txt）。
-- ID 就是 Lucide 官方图标名（https://lucide.dev/icons/）；规格：32×32 白色线条 TGA，线宽 2.5。
-- 新增图标：把对应 TGA 放进 Lucide 目录，并在下面 ids 中按名字补一行；两处必须一致。
-- 未登记的 ID 会直接报错（不做兜底），避免拼错名字后静默显示空白。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 贴图根目录（末尾带反斜杠）。
local ICON_ROOT = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\Lucide\\"

ExwindTools.GUIIcons = {
    ids = {
        ["activity"] = true,
        ["beer"] = true,
        ["blend"] = true,
        ["blocks"] = true,
        ["book-open"] = true,
        ["castle"] = true,
        ["chart-no-axes-column"] = true,
        ["crosshair"] = true,
        ["door-open"] = true,
        ["download"] = true,
        ["flame"] = true,
        ["headphones"] = true,
        ["heart-pulse"] = true,
        ["history"] = true,
        ["hourglass"] = true,
        ["house"] = true,
        ["image"] = true,
        ["info"] = true,
        ["key-round"] = true,
        ["layout-grid"] = true,
        ["list"] = true,
        ["map"] = true,
        ["map-pin"] = true,
        ["message-circle-more"] = true,
        ["message-square"] = true,
        ["messages-square"] = true,
        ["move"] = true,
        ["octagon-x"] = true,
        -- https://github.com/lucide-icons/lucide/blob/main/icons/paintbrush.svg (existing Lucide license)
        ["paintbrush"] = true,
        ["palette"] = true,
        ["pencil-line"] = true,
        ["play"] = true,
        -- Lucide 的 play 是线条三角；播放入口要的是实心三角，Lucide 没有对应图标，
        -- 按同一规格（40×40、32 位 BGRA、白色、alpha 为覆盖率）自绘，轮廓与
        -- play.tga 的外廓完全重合（同样 x 7-36 / y 3-36），圆角沿用其圆形线端。
        ["play-solid"] = true,
        ["refresh-cw"] = true,
        ["search"] = true,
        ["settings"] = true,
        ["shield"] = true,
        ["shield-plus"] = true,
        ["shopping-cart"] = true,
        ["skull"] = true,
        ["sliders-horizontal"] = true,
        ["sparkles"] = true,
        ["square"] = true,
        ["star"] = true,
        ["swords"] = true,
        ["timer"] = true,
        ["timer-reset"] = true,
        ["toolbox"] = true,
        ["trophy"] = true,
        ["type"] = true,
        ["volume-2"] = true,
        ["wand-sparkles"] = true,
        ["x"] = true,
    },
}

-- 取得已登记图标的游戏内贴图路径；未登记直接报错。
ExwindTools.UI = ExwindTools.UI or {}
function ExwindTools.UI:GetIcon(id)
    if not ExwindTools.GUIIcons.ids[id] then
        error("[GUIIcons] unknown icon id: " .. tostring(id), 2)
    end
    return ICON_ROOT .. id .. ".tga"
end
