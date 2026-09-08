---@diagnostic disable: undefined-global

-- 标签清单唯一来自构建器写入 EXBoss 核心的 PackManifest。
-- 不读取旧静态表、旧语音包 Lua 或 LibSharedMedia，避免“可选但不能播放”的幽灵条目。
ExBoss = ExBoss or {}
ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.LabelCatalog = ExBoss.Voice.LabelCatalog or {}
local Catalog = ExBoss.Voice.LabelCatalog

local function LText(key)
    local L = ExBoss and ExBoss.L
    return L and L[key] or key
end

local function GetManifestLabels()
    local manifest = ExBoss and ExBoss.Voice and ExBoss.Voice.PackManifest
    local labels = type(manifest) == "table" and manifest.labels or nil
    if type(labels) ~= "table" then
        return {}
    end

    local out, seen = {}, {}
    for _, label in ipairs(labels) do
        label = tostring(label or "")
        if label ~= "" and not seen[label] then
            seen[label] = true
            out[#out + 1] = label
        end
    end
    table.sort(out)
    return out
end

-- 所有新制式语音包共享同一标签 -> 文件名映射；包之间仅音频内容不同。
function Catalog.GetPackLabels(_)
    return GetManifestLabels()
end

function Catalog.GetStandardLabels()
    return GetManifestLabels()
end

-- 给语音页触发器下拉使用：返回 {text, value} 格式。
function Catalog.GetDropdownItems()
    local out = {}
    for _, label in ipairs(GetManifestLabels()) do
        out[#out + 1] = { LText(label), label }
    end
    table.sort(out, function(a, b)
        local ta = tostring(a and a[1] or "")
        local tb = tostring(b and b[1] or "")
        if ta == tb then
            return tostring(a and a[2] or "") < tostring(b and b[2] or "")
        end
        return ta < tb
    end)
    if #out == 0 then
        out[1] = { "（无标签）", "" }
    end
    return out
end
