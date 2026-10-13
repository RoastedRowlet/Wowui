-- V2 owns presentation. control/component nodes that declare `path` are bound by
-- the standard layer below (read, write, NotifyModuleValueChanged); nodes that
-- declare `ref` keep their owner adapters, records and writes.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local Pages, Session = {}, {}
UI.SettingsDeclarationSchemaRevision = 1 -- Static declaration rules; bump when accepted schema changes.
local GM = _G.ExwindTools.GUIMetrics
if not GM then error("ExwindGUIMetrics.lua must load before ExwindSettingsV2.lua") end
local POOL, GAP, PAD = "EXUI.SettingsV2.Node", GM.space.settingsV2Gap, GM.space.settingsV2Padding
Factory:InitCompositePool(POOL)

local Fields = {
    card = "title titlePosition titleAlign collapsible collapsed help children",
    group = "title children", row = "children separator", cell = "children",
    actions = "children position align", columns = "columns children",
    ["repeat"] = "source template",
    control = "ref controlType mode path label description options optionsSource media multiple search min max step inputWidthPercent",
    component = "ref component path label opts optionsRef",
    text = "text textSource", hint = "text textSource",
    button = "text action clickKey presentation",
}
local Common = "id kind visible enabled width weight height"
local ControlTypes = { input=true, multiline=true, checkbox=true, switch=true, card=true,
    choice=true, tristate=true, select=true, slider=true, color=true, field=true }
-- Standard binding layer: the control types and composite components a `path`
-- node may declare. Records, choice groups and custom content stay on owners.
local PathControlTypes = { switch=true, checkbox=true, card=true, input=true, select=true, slider=true, color=true }
local RowControlTypes = { switch=true, input=true, select=true, slider=true, color=true }
local SelectMedia = { font=true, sound=true, statusbar=true, border=true, background=true }
local StandardComponents = { fontgroup=true, icongroup=true, timerbargroup=true, anchorgroup=true,
    soundgroup=true, widgetlayout=true, modulecommonsettings=true, glow_settings=true, texturegroup=true }
local PathControlFields = "controlType label description options optionsSource media multiple search min max step inputWidthPercent"
local PathOnlyFields = { "label", "description", "options", "optionsSource", "media", "multiple", "search",
    "min", "max", "step", "inputWidthPercent", "component", "opts", "optionsRef" }
local AdapterMethods = { "mount", "update", "measure", "layout", "setEnabled", "setVisible", "release" }
local ControlMethods = { "mount", "release" }
local Build, MountNode, ReleaseNode, RefreshNode, LayoutNode
local Mounted = setmetatable({}, { __mode = "k" }) -- parent -> 存活的 V2 会话

local function Check(ok, message)
    if not ok then error("SettingsV2: " .. message, 3) end
end

local function Name(value)
    return type(value) == "string" and value ~= ""
end

local function Number(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function Keys(value, fields, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be a plain table")
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in pairs(value) do Check(allowed[field], where .. ": unknown field " .. tostring(field)) end
end

local function Array(value, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be an array")
    local count = 0
    for key in pairs(value) do
        Check(type(key) == "number" and key >= 1 and key % 1 == 0, where .. ": invalid array index")
        count = count + 1
    end
    for i = 1, count do Check(value[i] ~= nil, where .. ": sparse array") end
    return count
end

-- Copy declarations only; never used for owner data or records.
local function DeclarationCopy(value, seen)
    local kind = type(value)
    Check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil",
        "declarations must contain only data")
    if kind ~= "table" then return value end
    Check(not seen[value] and getmetatable(value) == nil, "cyclic/metatable declaration")
    seen[value] = true
    local copy = {}
    for key, entry in pairs(value) do
        Check(type(key) == "string" or type(key) == "number", "invalid declaration key")
        copy[key] = DeclarationCopy(entry, seen)
    end
    seen[value] = nil
    return copy
end

local function Reference(owner, bucket, name, where)
    Check(Name(name), where .. " requires a named reference")
    if not owner then return end
    local value = owner[bucket] and owner[bucket][name]
    Check(type(value) == "function", where .. ": missing " .. bucket .. "." .. name)
end

-- All expected declaration failures travel as data. No callbacks or metamethods
-- are evaluated during preflight, including owner reference lookup.
local function Issue(path, message, nodeId, code)
    return false, { code=code or "INVALID_SCHEMA", path=path, nodeId=nodeId, message=message }
end

local function Pure(value, path, seen)
    local kind = type(value)
    if kind ~= "table" then
        if kind == "nil" or kind == "string" or kind == "boolean"
            or (kind == "number" and value == value and math.abs(value) < math.huge) then return true end
        return Issue(path, "declarations must contain finite plain data")
    end
    if getmetatable(value) ~= nil or seen[value] then return Issue(path, "cyclic/metatable declaration") end
    seen[value] = true
    for key, entry in next, value do
        if type(key) ~= "string" and type(key) ~= "number" then return Issue(path, "invalid declaration key") end
        local ok, issue = Pure(entry, path .. "." .. tostring(key), seen)
        if not ok then return false, issue end
    end
    seen[value] = nil
    return true
end

local function SchemaKeys(value, fields, path, id)
    if type(value) ~= "table" then return Issue(path, "expected a plain table", id) end
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in next, value do
        if not allowed[field] then return Issue(path .. "." .. tostring(field), "unknown field", id) end
    end
    return true
end

local function SchemaArray(value, path, id)
    if type(value) ~= "table" then return Issue(path, "expected an array", id) end
    local count = 0
    for key in next, value do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return Issue(path, "invalid array index", id) end
        count = count + 1
    end
    for i = 1, count do
        if rawget(value, i) == nil then return Issue(path .. "[" .. i .. "]", "sparse array", id) end
    end
    return true, count
end

local function SchemaReference(owner, bucket, name, path, id)
    if not Name(name) then return Issue(path, "named reference required", id) end
    if owner == nil then return true end
    local refs = rawget(owner, bucket)
    if type(refs) ~= "table" or type(rawget(refs, name)) ~= "function" then
        return Issue(path, "missing " .. bucket .. "." .. name, id)
    end
    return true
end

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- path/clickKey nodes write through owner.binding = { moduleKey, config }.
local function SchemaBinding(owner, path, id)
    if owner == nil then return true end
    local binding = rawget(owner, "binding")
    if type(binding) ~= "table" or not Name(rawget(binding, "moduleKey")) or type(rawget(binding, "config")) ~= "table" then
        return Issue(path, "path binding requires owner.binding { moduleKey, config }", id)
    end
    return true
end

-- Shared by declaration nodes and owner-built standard controls.
local function SchemaPathControl(spec, path, id)
    local function fail(field, message) return Issue(path .. "." .. field, message, id) end
    local kind = spec.controlType
    if not PathControlTypes[kind] then return fail("controlType", "path control requires switch/checkbox/card/input/select/slider/color") end
    if spec.mode ~= nil then return fail("mode", "mode belongs to owner choice controls") end
    for _, field in ipairs({ "label", "description" }) do
        if spec[field] ~= nil and type(spec[field]) ~= "string" then return fail(field, "expected string") end
    end
    if (kind == "switch" or kind == "checkbox" or kind == "card") and type(spec.label) ~= "string" then
        return fail("label", "label required")
    end
    if kind ~= "select" and (spec.options ~= nil or spec.optionsSource ~= nil or spec.media ~= nil
        or spec.multiple ~= nil or spec.search ~= nil) then return fail("options", "options require select") end
    if kind ~= "slider" and (spec.min ~= nil or spec.max ~= nil or spec.step ~= nil) then return fail("min", "bounds require slider") end
    if kind ~= "input" and spec.inputWidthPercent ~= nil then return fail("inputWidthPercent", "requires input") end
    if kind == "select" then
        local sources = (spec.options ~= nil and 1 or 0) + (spec.optionsSource ~= nil and 1 or 0) + (spec.media ~= nil and 1 or 0)
        if sources ~= 1 then return fail("options", "select requires exactly one of options, optionsSource, media") end
        if spec.multiple ~= nil and type(spec.multiple) ~= "boolean" then return fail("multiple", "expected boolean") end
        if spec.search ~= nil and type(spec.search) ~= "boolean" then return fail("search", "expected boolean") end
        if spec.media ~= nil and (not SelectMedia[spec.media] or spec.multiple ~= nil) then
            return fail("media", "media requires a single font/sound/statusbar/border/background select")
        end
        if spec.optionsSource ~= nil and (type(spec.optionsSource) ~= "string"
            or not spec.optionsSource:match("^[%a_][%w_%.]*$")) then
            return fail("optionsSource", "expected a global provider name")
        end
        if spec.options ~= nil then
            local ok, issue = SchemaArray(spec.options, path .. ".options", id)
            if not ok then return false, issue end
            local seen = {}
            for i, option in ipairs(spec.options) do
                local at = path .. ".options[" .. i .. "]"
                ok, issue = SchemaKeys(option, "value label", at, id)
                if not ok then return false, issue end
                if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
                local valueType = type(option.value)
                if valueType ~= "string" and valueType ~= "boolean" and not Finite(option.value) then
                    return Issue(at .. ".value", "expected string, number or boolean", id)
                end
                if seen[option.value] then return Issue(at .. ".value", "duplicate option value", id) end
                seen[option.value] = true
            end
        end
    elseif kind == "slider" then
        for _, field in ipairs({ "min", "max", "step" }) do
            if spec[field] ~= nil and not Finite(spec[field]) then return fail(field, "expected a finite number") end
        end
        if (spec.min or 0) > (spec.max or 100) or (spec.step or 1) <= 0 then return fail("step", "invalid slider bounds or step") end
    elseif kind == "input" and spec.inputWidthPercent ~= nil and not Number(spec.inputWidthPercent) then
        return fail("inputWidthPercent", "expected a positive finite number")
    end
    return true
end

local function ValidateNode(node, owner, ids, depth, location, columnCount, path, overflow)
    if type(node) ~= "table" or not Fields[node.kind] then return Issue(path, "unknown node kind") end
    local kind, id = node.kind, node.id
    local function fail(field, message) return Issue(path .. (field and "." .. field or ""), message, id) end
    local ok, issue = SchemaKeys(node, Common .. " " .. Fields[kind], path, id)
    if not ok then return false, issue end
    if not Name(id) or ids[id] then return fail("id", "missing/duplicate node id") end
    ids[id] = true
    local top = location == "page" or location == "ribbon"
    if top and kind ~= "card" and kind ~= "repeat" then return fail("kind", "page accepts card/repeat") end
    if not top and kind == "card" then return fail("kind", "card must be at page level") end
    if kind == "actions" and (location ~= "row" or columnCount) then return fail("kind", "actions requires a flow row") end
    if kind == "cell" and (location ~= "row" or not columnCount) then return fail("kind", "cell requires a shared-column row") end
    for _, field in ipairs({ "width", "weight", "height" }) do
        if node[field] ~= nil and not Number(node[field]) then return fail(field, "expected a positive finite number") end
    end
    if node.width and node.weight then return fail("weight", "width and weight are exclusive") end
    if (node.width or node.weight) and not (((location == "row" or location == "actions") and not columnCount)
        or (location == "ribbon" and kind == "card" and not node.weight)) then
        return fail("width", "width/weight require a flow item or fixed ribbon card")
    end
    if overflow and top and kind == "card" and not Number(node.width) then return fail("width", "overflow requires explicit card width") end
    if node.height and kind ~= "control" and kind ~= "component" and kind ~= "button" and kind ~= "text" and kind ~= "hint" then
        return fail("height", "height is leaf-only")
    end
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then
            ok, issue = SchemaReference(owner, "predicates", node[field], path .. "." .. field, id)
            if not ok then return false, issue end
        end
    end
    if kind == "card" or kind == "group" then
        if type(node.title) ~= "string" then return fail("title", "title required") end
        if kind == "card" then
            if node.titlePosition ~= nil and node.titlePosition ~= "top" and node.titlePosition ~= "bottom" then return fail("titlePosition", "invalid title position") end
            if node.titleAlign ~= nil and node.titleAlign ~= "start" and node.titleAlign ~= "center" then return fail("titleAlign", "invalid title alignment") end
            for _, field in ipairs({ "collapsible", "collapsed" }) do
                if node[field] ~= nil and type(node[field]) ~= "boolean" then return fail(field, "expected boolean") end
            end
            if node.collapsed and not node.collapsible then return fail("collapsed", "collapsed requires collapsible") end
            if node.help ~= nil and not Name(node.help) then return fail("help", "expected non-empty help") end
        end
    elseif (kind == "control" or kind == "component") and node.path ~= nil then
        if node.ref ~= nil then return fail("ref", "use ref or path") end
        if not Name(node.path) then return fail("path", "expected a non-empty path") end
        if kind == "control" then
            ok, issue = SchemaPathControl(node, path, id)
            if not ok then return false, issue end
        else
            if not StandardComponents[node.component] then return fail("component", "unknown standard component") end
            if node.label ~= nil and type(node.label) ~= "string" then return fail("label", "expected string") end
            if node.opts ~= nil and type(node.opts) ~= "table" then return fail("opts", "expected a plain table") end
            -- optionsRef names owner.options[ref]: runtime options (callbacks) merged over opts.
            if node.optionsRef ~= nil then
                if not Name(node.optionsRef) then return fail("optionsRef", "expected a named reference") end
                if owner then
                    local options = rawget(owner, "options")
                    if type(options) ~= "table" or type(rawget(options, node.optionsRef)) ~= "table" then
                        return fail("optionsRef", "missing options." .. node.optionsRef)
                    end
                end
            end
        end
        ok, issue = SchemaBinding(owner, path .. ".path", id)
        if not ok then return false, issue end
    elseif kind == "control" or kind == "component" then
        if not Name(node.ref) then return fail("ref", "reference required") end
        for _, field in ipairs(PathOnlyFields) do
            if node[field] ~= nil then return fail(field, "requires path") end
        end
        if kind == "control" and not ControlTypes[node.controlType] then return fail("controlType", "invalid control type") end
        if node.mode ~= nil and (node.controlType ~= "choice" or (node.mode ~= "single" and node.mode ~= "multiple")) then return fail("mode", "invalid choice mode") end
        if owner then
            local bucket = rawget(owner, kind == "control" and "controls" or "components")
            local adapter = type(bucket) == "table" and rawget(bucket, node.ref)
            if type(adapter) ~= "table" then return fail("ref", "missing owner adapter " .. node.ref) end
            for _, method in ipairs(kind == "control" and ControlMethods or AdapterMethods) do
                if type(rawget(adapter, method)) ~= "function" then return fail("ref", "adapter missing " .. method) end
            end
            for _, method in ipairs(AdapterMethods) do
                if rawget(adapter, method) ~= nil and type(rawget(adapter, method)) ~= "function" then return fail("ref", "invalid adapter " .. method) end
            end
        end
    elseif kind == "button" then
        if type(node.text) ~= "string" then return fail("text", "text required") end
        if (node.action ~= nil) == (node.clickKey ~= nil) then return fail("action", "use action or clickKey") end
        if node.clickKey ~= nil then
            if not Name(node.clickKey) then return fail("clickKey", "expected a non-empty key") end
            ok, issue = SchemaBinding(owner, path .. ".clickKey", id)
        else
            ok, issue = SchemaReference(owner, "actions", node.action, path .. ".action", id)
        end
        if not ok then return false, issue end
        if node.presentation ~= nil and node.presentation ~= "primary" and node.presentation ~= "secondary" and node.presentation ~= "danger" then return fail("presentation", "invalid button presentation") end
    elseif kind == "text" or kind == "hint" then
        if (node.text ~= nil) == (node.textSource ~= nil) then return fail("text", "use text or textSource") end
        if node.text ~= nil and type(node.text) ~= "string" then return fail("text", "expected string") end
        if node.textSource ~= nil then
            ok, issue = SchemaReference(owner, "texts", node.textSource, path .. ".textSource", id)
            if not ok then return false, issue end
        end
    elseif kind == "actions" then
        for _, field in ipairs({ "position", "align" }) do
            local value = node[field]
            if value ~= nil and value ~= "start" and value ~= "center" and value ~= "end" then return fail(field, "invalid alignment") end
        end
    elseif kind == "columns" then
        ok, issue = SchemaArray(node.columns, path .. ".columns", id)
        if not ok then return false, issue end
        columnCount = issue
        if columnCount == 0 then return fail("columns", "empty columns") end
        for i, column in ipairs(node.columns) do
            local columnPath = path .. ".columns[" .. i .. "]"
            ok, issue = SchemaKeys(column, "width weight", columnPath, id)
            if not ok then return false, issue end
            if (column.width and column.weight) or (column.width ~= nil and not Number(column.width))
                or (column.weight ~= nil and not Number(column.weight)) then return Issue(columnPath, "invalid column width/weight", id) end
        end
    elseif kind == "repeat" then
        if depth >= 2 then return fail("template", "at most two nested repeats") end
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if not ok then return false, issue end
        if type(node.template) ~= "table" then return fail("template", "template required") end
        if top and node.template.kind ~= "card" then return fail("template", "page repeat template must be card") end
        if columnCount and node.template.kind ~= "row" then return fail("template", "column repeat template must be row") end
        return ValidateNode(node.template, owner, ids, depth + 1, location, columnCount, path .. ".template", overflow)
    end
    if kind == "row" and node.separator ~= nil and type(node.separator) ~= "boolean" then return fail("separator", "expected boolean") end
    if node.children ~= nil then
        ok, issue = SchemaArray(node.children, path .. ".children", id)
        if not ok then return false, issue end
        if kind == "row" and columnCount and issue ~= columnCount then return fail("children", "cell count differs from columns") end
        local actions = 0
        for i, child in ipairs(node.children) do
            local childPath = path .. ".children[" .. i .. "]"
            if type(child) ~= "table" then return Issue(childPath, "expected node", id) end
            if kind == "columns" and child.kind ~= "row" and child.kind ~= "repeat" then return Issue(childPath, "columns accepts row/repeat", id) end
            if kind == "row" and columnCount and child.kind ~= "cell" then return Issue(childPath, "expected cell", id) end
            if child.kind == "actions" then
                actions = actions + 1
                if actions > 1 or i ~= #node.children then return Issue(childPath, "actions must be unique and last", id) end
            end
            ok, issue = ValidateNode(child, owner, ids, depth, kind, (kind == "columns" or kind == "row") and columnCount or nil, childPath, overflow)
            if not ok then return false, issue end
        end
    elseif kind == "card" or kind == "group" or kind == "row" or kind == "cell" or kind == "actions" or kind == "columns" then
        return fail("children", "children required")
    end
    return true
end

local function Validate(declaration, owner, options)
    local ok, issue = Pure(declaration, "page", {})
    if not ok then return false, issue end
    ok, issue = SchemaKeys(declaration, "version layout presentation cards", "page")
    if not ok then return false, issue end
    if declaration.version ~= 2 then return Issue("page.version", "version must be 2") end
    if declaration.layout ~= nil and declaration.layout ~= "stack" and declaration.layout ~= "ribbon" then return Issue("page.layout", "invalid layout") end
    if declaration.presentation ~= nil and (declaration.presentation ~= "toolbar" or declaration.layout ~= "ribbon") then return Issue("page.presentation", "toolbar requires ribbon") end
    if owner ~= nil and type(owner) ~= "table" then return Issue("owner", "owner must be a table", nil, "INVALID_ARGUMENT") end
    for _, name in ipairs({ "onHeightChanged", "onContentWidthChanged", "onRibbonLayout" }) do
        if owner and rawget(owner, name) ~= nil and type(rawget(owner, name)) ~= "function" then return Issue("owner." .. name, "expected callback", nil, "INVALID_ARGUMENT") end
    end
    if options ~= nil then
        ok, issue = Pure(options, "options", {})
        if not ok then issue.code = "INVALID_ARGUMENT"; return false, issue end
        ok, issue = SchemaKeys(options, "ribbonOverflow", "options")
        if not ok then issue.code = "INVALID_ARGUMENT"; return false, issue end
    end
    local overflow = options and options.ribbonOverflow
    if overflow ~= nil then
        ok, issue = SchemaKeys(overflow, "availableWidth title", "options.ribbonOverflow")
        if not ok then issue.code = "INVALID_ARGUMENT"; return false, issue end
        if declaration.layout ~= "ribbon" or not Number(overflow.availableWidth) or not Name(overflow.title) then
            return Issue("options.ribbonOverflow", "ribbon requires positive availableWidth and title", nil, "INVALID_ARGUMENT")
        end
    end
    ok, issue = SchemaArray(declaration.cards, "page.cards")
    if not ok then return false, issue end
    local ids = {}
    for i, node in ipairs(declaration.cards) do
        ok, issue = ValidateNode(node, owner, ids, 0, declaration.layout == "ribbon" and "ribbon" or "page", nil, "page.cards[" .. i .. "]", overflow ~= nil)
        if not ok then return false, issue end
    end
    return true
end

function UI:ValidateSettingsDeclarationV2(declaration, owner, options)
    return Validate(declaration, owner, options)
end

function UI:RegisterSettingsPageV2(pageId, declaration)
    Check(Name(pageId) and Pages[pageId] == nil, "missing/duplicate page id")
    local ok, issue = Validate(declaration)
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Pages[pageId] = DeclarationCopy(declaration, {})
end

local function Acquire(parent)
    local host = Factory:AcquireCompositeHost(POOL, parent)
    if host._v2Label then host._v2Label:Hide() end
    if host._v2SettingsSeparator then host._v2SettingsSeparator:Hide() end
    host:SetScript("OnMouseWheel", nil)
    host:EnableMouseWheel(false)
    host:SetSize(1, 1)
    host:Show()
    return host
end

-- Settings GUI lands on whole physical pixels (UI scale is usually fractional);
-- otherwise nine-slice surfaces such as switch knobs show their seams.
local function Place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    PixelUtil.SetPoint(frame, "TOPLEFT", parent, "TOPLEFT", x, -y, 0, 0)
    PixelUtil.SetSize(frame, math.max(1, width), math.max(1, height), 1, 1)
end

local function Records(node)
    local records = node.session.owner.sources[node.spec.source](node.scope)
    Array(records, node.spec.id .. " source")
    local seen = {}
    for _, record in ipairs(records) do
        Check(type(record) == "table" and not seen[record], node.spec.id .. ": records must be unique original tables")
        seen[record] = true
    end
    return records
end

local function Current(node)
    if not node.alive or not node.session.alive or node.session.cleanupFailed then return false end
    local scope = node.scope
    while scope do
        local repeatNode = scope._repeatNode
        if not repeatNode.alive then return false end
        local records = Records(repeatNode)
        if records[scope.index] ~= scope.item then return false end
        scope = scope.parent
    end
    return true
end

local function Interactive(node)
    if not Current(node) or not node.session.root:IsVisible() then return false end
    local card = node
    while card.parent and card.spec.kind ~= "card" do card = card.parent end
    if card.overflow and (node.session.overflowState ~= "open" or not node.session.surface
        or not node.session.surface.window:IsVisible()) then return false end
    while node do
        if node.visible == false or node.enabled == false then return false end
        if node.spec.kind == "card" and node.frame._exSettingsCardCollapsed then return false end
        node = node.parent
    end
    return true
end

local function Context(node)
    local generation = node.generation
    local function valid() return node.generation == generation and Current(node) end
    local ctx = { scope = node.scope }
    function ctx:IsCurrent() return valid() end
    function ctx:GetRibbonSession()
        if valid() and node.session.ribbonOverflow then return node.session end
    end
    function ctx:RegisterRibbonPopup(popup)
        Check(type(popup) == "table" and type(popup.isOpen) == "function"
            and type(popup.ownsFrame) == "function" and type(popup.close) == "function", "invalid ribbon popup")
        local session, card = node.session, node
        while card.parent and card.spec.kind ~= "card" do card = card.parent end
        -- Prefix controls are outside More; entering overflow remounts with a new context.
        if not valid() or not card.overflow or not session.surface then return function() end end
        session.popupSerial = (session.popupSerial or 0) + 1
        local entry = { node=node, generation=generation, surface=session.surface, popup=popup, serial=session.popupSerial }
        node.popups = node.popups or {}
        node.popups[entry] = true
        session.ribbonPopups = session.ribbonPopups or {}
        session.ribbonPopups[entry] = true
        local function unsubscribe()
            if node.popups then node.popups[entry] = nil end
            if session.ribbonPopups then session.ribbonPopups[entry] = nil end
        end
        entry.unsubscribe = unsubscribe
        return unsubscribe
    end
    function ctx:Guard(callback)
        Check(type(callback) == "function", "Guard expects a callback")
        return function(...)
            if valid() and Interactive(node) then return callback(...) end
        end
    end
    -- [决定] 测量世代：异步高度必须带上“测量它时使用的宽度”（measure 收到的 width）。
    -- 宽度与当前布局宽不一致（旧宽度的迟到报告）一律拒绝并返回 false；同步在 measure 内
    -- 返回高度的 owner 不需要调用。省略 width 表示 owner 保证它按当前宽度测量。
    function ctx:ReportHeight(height, requestedWidth)
        if not valid() then return false end
        Check(type(height) == "number" and height >= 0 and height < math.huge, "invalid reported height")
        Check(requestedWidth == nil or (type(requestedWidth) == "number" and requestedWidth == requestedWidth),
            "invalid reported width")
        if requestedWidth ~= nil and (node.width == nil or math.abs(node.width - requestedWidth) > 0.01) then
            return false
        end
        if node.reportedHeight ~= height then
            node.reportedHeight = height
            node.session:Invalidate()
        end
        return true
    end
    function ctx:Invalidate()
        if not valid() then return false end
        node.reportedHeight = nil
        node.session:Invalidate()
        return true
    end
    -- After a committed write: re-read every bound value and re-evaluate predicates.
    function ctx:RefreshPage()
        if not valid() then return false end
        node.session:Refresh()
        return true
    end
    -- 当前分配宽度（最近一次 measure 收到的 width）；尚未布局时为 nil。
    function ctx:GetRequestedWidth() return valid() and node.width or nil end
    return ctx
end

local function Text(node)
    local text = node.spec.text
    if node.spec.textSource then text = node.session.owner.texts[node.spec.textSource](node.scope) end
    Check(type(text) == "string", node.spec.id .. ": text source must return string")
    node.label:SetText(text)
end

-- Defaults operate on an existing EXUI control, never a value/configuration.
local ControlDefaults = {}
function ControlDefaults.update() end
function ControlDefaults.measure(widget, context, width)
    widget:SetWidth(width)
    return widget:GetHeight()
end
function ControlDefaults.layout(widget, context, width, height)
    Place(widget, widget:GetParent(), 0, 0, width, height)
end
function ControlDefaults.setEnabled(widget, context, enabled)
    local target = widget.checkbox or widget.editBox or widget
    if widget.SetDisabled then widget:SetDisabled(not enabled)
    elseif target.SetEnabled then target:SetEnabled(enabled)
    else Check(enabled, "control needs an owner setEnabled implementation") end
end
function ControlDefaults.setVisible(widget, context, visible)
    if not visible then
        if widget.CloseMenu then widget:CloseMenu() end
        local editBox = widget.editBox or widget
        if editBox.ClearFocus then editBox:ClearFocus() end
    end
    widget:SetShown(visible)
end

-- Card accessories live on the pooled card frame and are created once: a "?" beside the title
-- that shows `help` as a tooltip, and a hairline under a folded card's title.
local function CardAccessories(card)
    if card._v2Help then return end
    local header = card._exSettingsCardHeader
    local colors = UI.ControlAppearance.colors
    local help = CreateFrame("Button", nil, header)
    help:SetSize(22, 22)
    help.glyph = UI:CreateVisualFontString(help, _G.EXFONTFRAME, "GameFontHighlight")
    help.glyph:SetPoint("CENTER", 0, 1)
    help.glyph:SetText("?")
    UI.ControlAppearance.ApplyTextRole(help.glyph, "title", colors.muted)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._v2Text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card._v2Help = help
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line))
    card._v2CollapsedDivider = divider
end

local function ControlAdapter(provider)
    return setmetatable({}, { __index=function(_, method) return rawget(provider, method) or ControlDefaults[method] end })
end

-- =========================================================
-- Standard binding layer
-- =========================================================
-- A binding addresses one value under a module DB root by a dot path; numeric
-- segments are numeric keys. Writes create missing intermediate tables, skip
-- equal values and notify through the single ValueController entry.
local Binding = {}
Binding.__index = Binding

function Binding:Read()
    local value = self.root
    for _, key in ipairs(self.segments) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

function Binding:Parent(create)
    local parent = self.root
    for i = 1, #self.segments - 1 do
        local key = self.segments[i]
        local child = parent[key]
        if child == nil and create then
            child = {}
            parent[key] = child
        end
        if type(child) ~= "table" then
            Check(child == nil, self.path .. ": segment " .. tostring(key) .. " is not a table")
            return nil
        end
        parent = child
    end
    return parent
end

function Binding:Key()
    return self.segments[#self.segments]
end

function Binding:Notify(phase)
    UI:NotifyModuleValueChanged(self.moduleKey, self.path, phase == "live" and "changing" or "committed")
end

-- phase: "live" (dragging), "commit", or "silent" (no notification).
function Binding:Write(value, phase)
    local parent, key = self:Parent(true), self:Key()
    if parent[key] == value then return false end
    parent[key] = value
    if phase ~= "silent" then self:Notify(phase) end
    return true
end

local function CreateBinding(moduleKey, root, path)
    Check(Name(moduleKey), "binding requires moduleKey")
    Check(type(root) == "table", "binding requires a root table")
    Check(Name(path), "binding requires a path")
    local segments = {}
    for part in path:gmatch("[^%.]+") do segments[#segments + 1] = tonumber(part) or part end
    Check(#segments > 0, "binding requires a path")
    return setmetatable({ moduleKey=moduleKey, root=root, path=path, segments=segments,
        parentPath=path:match("^(.*)%.[^%.]+$") }, Binding)
end

local function ReleaseBoundWidget(widget)
    UI:RestoreSettingsListControl(widget)
    if widget._exGridOwnedControls then
        for index = #widget._exGridOwnedControls, 1, -1 do
            Factory:ReleaseGridWidget(widget._exGridOwnedControls[index])
            widget._exGridOwnedControls[index] = nil
        end
        widget._exGridOwnedControls = nil
    end
    if widget._isCompositeHost then
        Factory:ReleaseCompositeHost(widget)
    elseif widget._fromPool then
        Factory:Release(widget._fromPool, widget)
    else
        widget:Hide()
        widget:SetParent(nil)
    end
end

-- optionsSource names a global provider (resolved at every mount). A table result
-- is used as-is; a string result keeps the "value:display,..." inline form.
local function SelectItems(spec)
    if spec.options then
        local items = {}
        for i, option in ipairs(spec.options) do items[i] = { option.label, option.value } end
        return items
    end
    local provider = _G
    for part in spec.optionsSource:gmatch("[^%.]+") do
        provider = type(provider) == "table" and provider[part] or nil
    end
    Check(type(provider) == "function", "optionsSource is not a function: " .. spec.optionsSource)
    local data = provider()
    if type(data) == "table" then return data end
    local items = {}
    for entry in tostring(data or ""):gmatch("([^,]+)") do
        local value, display = entry:match("^([^:]+):(.+)$")
        items[#items + 1] = (value and not spec.multiple) and { display, value } or entry
    end
    return items
end

local function IsOrdinaryRowControl(widget)
    local kind = widget._gridType
    if kind == "GridInput" then return widget.IsMultiLine and not widget:IsMultiLine() end
    return kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect"
        or kind == "GridColorButton" or kind == "GridSlider"
end

-- bindingFor(context) returns the binding of one mounted control.  A labelled
-- switch/input/select/slider/color is presented as a settings row: label and
-- description on the left, the control on the right, a divider between rows.
local function StandardControl(spec, bindingFor)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.controlType
    local adapter = {}
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        local function Commit(value)
            binding:Write(value, "commit")
            context:RefreshPage()
        end
        local width, value, widget = GM.size.controlDefaultWidth, binding:Read(), nil
        local search = { search = spec.search }
        if kind == "switch" or kind == "checkbox" or kind == "card" then
            widget = UI:CreateCheckbox(host, spec.label, value == true, function(checked) Commit(checked == true) end)
        elseif kind == "slider" then
            widget = UI:CreateSlider(host, width, spec.label or "", spec.min or 0, spec.max or 100, value or 0,
                spec.step or 1, nil, {
                    onLive = function(live) binding:Write(live, "live") end,
                    onCommit = Commit,
                })
        elseif kind == "input" then
            widget = UI:CreateEditBox(host, value or "", width, GM.size.controlHeight, spec.label,
                { onEnter = Commit, onEditFocusLost = Commit })
        elseif kind == "color" then
            widget = UI:CreateColorButton(host, spec.label or "", binding:Parent(false) or binding.root, binding:Key(), true,
                function()
                    binding:Notify("committed")
                    context:RefreshPage()
                end)
        elseif spec.media == "font" then
            widget = UI:CreateLSMDropdown(host, "font", width, spec.label, value, Commit, search)
        elseif spec.media == "sound" then
            widget = UI:CreateLSMSoundDropdown(host, width, spec.label, value, Commit, search)
        elseif spec.media then
            widget = UI:CreateLSMTextureDropdown(host, spec.media, width, spec.label, value, Commit, search)
        elseif spec.multiple then
            if type(value) ~= "table" then
                value = {}
                binding:Write(value, "silent")
            end
            widget = UI:CreateMultiSelectDropdown(host, width, spec.label, SelectItems(spec), value, function()
                binding:Notify("committed")
                context:RefreshPage()
            end, search)
        else
            widget = UI:CreateDropdown(host, width, spec.label, SelectItems(spec), value, Commit, search)
        end
        local state = { binding = binding, host = host, context = context }
        if spec.label and RowControlTypes[kind] then
            local ordinary = kind ~= "switch" and IsOrdinaryRowControl(widget)
            state.ordinary = ordinary
            state.valuePosition = kind == "slider" and "right" or nil
            state.row = UI:CreateSettingsRow(host, {
                label = spec.label, description = spec.description,
                controlKind = ordinary and "ordinary" or nil,
                controlMinWidth = ordinary and (kind == "slider" and GM.size.settingsRowSliderMinWidth
                    or GM.size.settingsRowControlMinWidth) or nil,
                inputWidthPercent = spec.inputWidthPercent,
            })
            UI:PrepareSettingsListControl(widget, {
                ordinaryControl = ordinary, hideLabel = true,
                presentation = kind == "switch" and "switch" or nil,
                valuePosition = state.valuePosition,
            })
            context._exSettingsRow = true
        end
        states[widget] = state
        return widget
    end
    function adapter.update(widget)
        local value = states[widget].binding:Read()
        if kind == "switch" or kind == "checkbox" or kind == "card" then
            widget:SetChecked(value == true)
            UI:ApplyControlAppearance(widget)
        elseif kind == "slider" then
            if tonumber(value) then widget:SetEXUIValue(tonumber(value), "silent") end
        elseif kind == "input" then
            if not widget:HasFocus() then widget:SetText(value == nil and "" or tostring(value)) end
        elseif kind == "color" then
            widget:UpdateColor()
        elseif not spec.media and not spec.multiple then
            UI:SetDropdownValue(widget, value)
        end
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        local row = state.row
        if not row then
            widget:SetWidth(width)
            return kind == "slider" and widget:GetHeight() or (spec.height or GM.size.controlHeight)
        end
        UI:SetSettingsRowLast(row, context._exRowLast ~= false)
        local height, x, y, controlWidth = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        widget:SetWidth(controlWidth)
        if state.ordinary or state.valuePosition then UI:UpdateSettingsListControlLayout(widget, controlWidth) end
        height, x, y = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        state.x, state.y = x, y
        return height
    end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        if not state.row then
            Place(widget, state.host, 0, 0, width, height)
            return
        end
        state.row:ClearAllPoints()
        state.row:SetPoint("TOPLEFT", state.host, "TOPLEFT", 0, 0)
        widget:ClearAllPoints()
        PixelUtil.SetPoint(widget, "TOPLEFT", state.row, "TOPLEFT", state.x, -state.y, 0, 0)
    end
    function adapter.release(widget, context)
        local state = states[widget]
        states[widget] = nil
        context._exSettingsRow, context._exRowLast = nil, nil
        ReleaseBoundWidget(widget)
        if state and state.row then state.row:Release() end
    end
    adapter.setEnabled, adapter.setVisible = ControlDefaults.setEnabled, ControlDefaults.setVisible
    return adapter
end

local DEFAULT_FONT_GROUP = { font = "Friz Quadrata TT", size = 14, r = 1, g = 1, b = 1, a = 1,
    outline = "", shadow = false, x = 0, y = 0 }
local DEFAULT_TIMER_BAR_GROUP = { width = 240, height = 24, texture = "Clean",
    barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
    barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
    showIcon = true, iconSide = "LEFT", iconWidth = 24, iconHeight = 24, iconOffsetX = -5, iconOffsetY = 0 }

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

-- Composite groups bind exactly as the settings-section page did: `path` is the
-- section path plus the component key; opts.bindRoot / opts.bindValue keep
-- their meaning. Components inside a card render body-only.
local function StandardComponent(spec, bindingFor, runtimeOpts)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.component
    local adapter = {}
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        local opts = CopyTable(spec.opts)
        for key, value in pairs(runtimeOpts or {}) do opts[key] = value end
        if opts.bodyOnly == nil then opts.bodyOnly = true end
        if kind == "modulecommonsettings" then
            opts.presentation = opts.presentation or "settings-list"
            opts._exTypedSettings = true
        end
        local key, parentPath, root, fullPath = binding:Key(), binding.parentPath, binding.root, binding.path
        local scoped = parentPath and binding:Parent(false) or root
        local width = math.max(GM.size.controlDefaultWidth, host:GetWidth())
        local function Options(pathPrefix)
            local result = CopyTable(opts)
            result._exWriteContext = { moduleKey = binding.moduleKey, pathPrefix = pathPrefix }
            return result
        end
        local function Notifier(notifyPath)
            return function()
                UI:NotifyModuleValueChanged(binding.moduleKey, notifyPath, "committed")
                context:RefreshPage()
            end
        end
        local widget
        if kind == "fontgroup" then
            local value = binding:Read()
            if not value then
                value = CopyTable(DEFAULT_FONT_GROUP)
                binding:Write(value, "commit")
            end
            widget = UI:CreateFontGroup(host, width, spec.label, value, Notifier(fullPath), Options(fullPath))
        elseif kind == "glow_settings" then
            widget = UI:CreateGlowSettings(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "widgetlayout" then
            widget = UI:CreateWidgetLayoutGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "soundgroup" then
            widget = UI:CreateSoundGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "modulecommonsettings" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local commonPath = bindKey and fullPath or (parentPath or "")
            widget = UI:CreateModuleCommonSettingsGroup(host, width, spec.label, scoped, bindKey,
                Notifier(commonPath), Options(commonPath))
        elseif kind == "anchorgroup" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local anchorPath = fullPath
            if not bindKey then
                local targetKey = (type(opts.attachTargetKey) == "string" and opts.attachTargetKey ~= "")
                    and opts.attachTargetKey or "customAttachTarget"
                anchorPath = parentPath and (parentPath .. "." .. targetKey) or targetKey
            end
            widget = UI:CreateAnchorGroup(host, width, spec.label, scoped, bindKey, Notifier(anchorPath), Options(anchorPath))
        elseif kind == "texturegroup" then
            local bindValue = opts.bindValue == true
            widget = UI:CreateTextureGroup(host, width, spec.label, bindValue and binding:Read() or scoped,
                not bindValue and key or nil, Notifier(fullPath), Options(fullPath))
        elseif kind == "icongroup" then
            local bindRoot, bindValue = opts.bindRoot == true, opts.bindValue == true
            local source = bindValue and binding:Read() or (bindRoot and root or scoped)
            local bindKey = (not bindRoot and not bindValue) and key or nil
            local iconPath = (bindValue or bindKey) and fullPath or (parentPath or "")
            widget = UI:CreateIconGroup(host, width, spec.label, source, bindKey, Notifier(iconPath), Options(iconPath))
        else -- timerbargroup
            local bindRoot = opts.bindRoot == true
            local value = bindRoot and root or binding:Read()
            if not value then
                value = CopyTable(DEFAULT_TIMER_BAR_GROUP)
                binding:Write(value, "commit")
            end
            local timerPath = bindRoot and (parentPath or "") or fullPath
            widget = UI:CreateTimerBarGroup(host, width, spec.label, value, nil, Notifier(timerPath), Options(timerPath))
        end
        states[widget] = { host = host, opts = opts, scoped = scoped,
            item = { type = kind, key = key, label = spec.label, opts = opts } }
        return widget
    end
    function adapter.update(widget)
        UI:RefreshCompositeGroupFromDB(widget)
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        local measured = UI:MeasureGridComponent(kind, width, state.opts, state.scoped, state.item)
        if type(measured) == "table" then
            local preferred = tonumber(measured.preferredHeight or measured.height)
            local minimum = tonumber(measured.minHeight)
            measured = preferred and minimum and math.max(preferred, minimum) or preferred or minimum
        end
        return tonumber(measured) or widget:GetHeight()
    end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        widget._exGridWidth = width
        UI:LayoutCompositeGroup(widget, width, height)
    end
    function adapter.release(widget)
        states[widget] = nil
        ReleaseBoundWidget(widget)
    end
    adapter.setEnabled, adapter.setVisible = ControlDefaults.setEnabled, ControlDefaults.setVisible
    return adapter
end

local PathControlSpecFields = PathControlFields .. " height"

function UI:CreateSettingsV2Binding(moduleKey, root, path)
    return CreateBinding(moduleKey, root, path)
end

-- Owner helpers: the same standard controls for records and other owner data.
-- bindingFor(context) returns UI:CreateSettingsV2Binding(...) for that mount.
function UI:CreateSettingsV2Control(spec, bindingFor)
    local ok, issue = SchemaKeys(spec, PathControlSpecFields, "control")
    if ok then ok, issue = SchemaPathControl(spec, "control") end
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(type(bindingFor) == "function", "CreateSettingsV2Control requires bindingFor")
    return StandardControl(DeclarationCopy(spec, {}), bindingFor)
end

-- runtimeOpts (optional) may carry callbacks; it is merged over spec.opts at mount.
function UI:CreateSettingsV2Component(spec, bindingFor, runtimeOpts)
    local ok, issue = SchemaKeys(spec, "component label opts", "component")
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(StandardComponents[spec.component], "unknown standard component " .. tostring(spec.component))
    Check(type(bindingFor) == "function", "CreateSettingsV2Component requires bindingFor")
    Check(runtimeOpts == nil or type(runtimeOpts) == "table", "runtimeOpts must be a table")
    return StandardComponent(DeclarationCopy(spec, {}), bindingFor, runtimeOpts)
end

Build = function(session, spec, parentFrame, scope, parent)
    local node = { session=session, spec=spec, scope=scope, parent=parent, alive=true, generation=1, children={} }
    local list = parent and parent.children or session.nodes
    list[#list + 1] = node
    if session.ribbonOverflow and spec.kind == "card" then
        node.deferred = true
        return node
    end
    MountNode(node, parentFrame)
    return node
end

MountNode = function(node, parentFrame)
    local session, spec, scope = node.session, node.spec, node.scope
    node.alive, node.deferred = true, false
    if spec.kind == "card" then
        node.frame = UI:CreateSettingsCard(parentFrame, spec)
        UI:PrepareSettingsListCard(node.frame, {
            preserveHeader=true, externalCollapsible=spec.collapsible == true, collapsed=spec.collapsed,
        })
        CardAccessories(node.frame)
        if session.presentation == "toolbar" then
            UI:ClearControlSurface(node.frame)
            UI:ClearControlSurface(node.frame:GetBody())
            UI:ClearControlSurface(node.frame._exSettingsCardHeader)
            if not node.frame._v2ToolbarDivider then
                node.frame._v2ToolbarDivider = node.frame:CreateTexture(nil, "ARTWORK")
            end
            local divider = node.frame._v2ToolbarDivider
            divider:SetColorTexture(unpack(_G.ExwindTools.GUIColors.sectionDivider))
            divider:ClearAllPoints()
            divider:SetPoint("TOPRIGHT", -1, -PAD)
            divider:SetPoint("BOTTOMRIGHT", -1, PAD)
            divider:SetWidth(1)
            divider:Show()
        end
        node.frame._v2Help._v2Text = spec.help
        node.body = Acquire(node.frame:GetBody())
        node.headerPoints = {}
        for i = 1, node.frame._exSettingsCardHeader:GetNumPoints() do
            node.headerPoints[i] = { node.frame._exSettingsCardHeader:GetPoint(i) }
        end
        PixelUtil.SetPoint(node.body, "TOPLEFT", node.frame:GetBody(), "TOPLEFT", PAD, -PAD, 0, 0)
        PixelUtil.SetPoint(node.body, "TOPRIGHT", node.frame:GetBody(), "TOPRIGHT", -PAD, -PAD, 0, 0)
        if spec.collapsible then
            node.toggleFont = { node.frame._exSettingsCardToggle._exGlyph:GetFont() }
            node.toggleSize = { node.frame._exSettingsCardToggle:GetSize() }
        end
        node.frame:SetLayoutInvalidationHandler(function(card)
            if spec.collapsible then
                card._exSettingsCardToggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
            end
            session:Refresh()
        end)
    else
        node.frame = Acquire(parentFrame)
        node.body = node.frame
    end
    node.context = Context(node)
    if spec.kind == "row" and spec.separator then
        if not node.frame._v2SettingsSeparator then
            node.frame._v2SettingsSeparator = UI:CreateSettingsSeparator(node.frame, 1)
        end
        node.separator = node.frame._v2SettingsSeparator
        node.separator:Show()
    end
    if spec.kind == "control" or spec.kind == "component" then
        if spec.path then
            local binding = session.owner.binding
            local function BindingFor() return CreateBinding(binding.moduleKey, binding.config, spec.path) end
            node.adapter = spec.kind == "control" and StandardControl(spec, BindingFor)
                or StandardComponent(spec, BindingFor, spec.optionsRef and session.owner.options[spec.optionsRef])
        else
            local provider = (spec.kind == "control" and session.owner.controls or session.owner.components)[spec.ref]
            node.adapter = spec.kind == "control" and ControlAdapter(provider) or provider
        end
        node.mountPending = true
        node.instance = node.adapter.mount(node.frame, node.context, spec)
        Check(node.instance ~= nil, spec.id .. ": mount must return instance")
        node.mountPending = false
        -- Keep the owner's original GUI width, not the width assigned by a prior layout.
        node.naturalWidth = node.instance.GetWidth and node.instance:GetWidth() or nil
        if spec.kind == "control" then
            Check(node.instance.GetParent and node.instance:GetParent() == node.frame,
                spec.id .. ": return original control hosted in the supplied GUI host")
            if node.instance.SetPageScroll then node.instance:SetPageScroll() end
            if spec.mode then
                Check(node.instance.mode == spec.mode, spec.id .. ": original choice mode differs")
            end
            if spec.controlType == "card" then
                Check(node.instance.checkbox ~= nil, spec.id .. ": card requires existing Checkbox")
                UI:PrepareSettingsListControl(node.instance, { presentation="card", hideLabel=false })
            end
        end
    elseif spec.kind == "button" then
        local onClick
        if spec.clickKey then
            -- Same State contract the settings-section buttons published.
            local moduleKey = session.owner.binding.moduleKey
            onClick = function()
                _G.ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = spec.clickKey, fullPath = spec.clickKey, ts = GetTime() })
            end
        else
            onClick = function(_, mouseButton) session.owner.actions[spec.action](node.context, mouseButton) end
        end
        node.button = UI:CreateButton(node.frame, spec.width or GM.size.controlDefaultWidth,
            spec.height or GM.size.controlHeight, spec.text,
            node.context:Guard(onClick), { variant=spec.presentation or "secondary", compact=true })
    elseif spec.kind == "text" or spec.kind == "hint" or spec.kind == "group" then
        if not node.frame._v2Label then
            node.frame._v2Label = UI:CreateVisualFontString(node.frame, _G.EXFONTFRAME, "GameFontHighlight")
        end
        node.label = node.frame._v2Label
        node.label:SetFontObject(spec.kind == "group" and "GameFontNormal" or "GameFontHighlight")
        node.label:SetJustifyH("LEFT")
        node.label:SetJustifyV("TOP")
        node.label:SetWordWrap(true)
        node.label:Show()
        local colors = UI.ControlAppearance.colors
        node.label:SetTextColor(unpack(spec.kind == "hint" and colors.muted or colors.text))
        if spec.kind == "group" then node.label:SetText(spec.title) else Text(node) end
    end
    if spec.kind ~= "repeat" then
        for _, child in ipairs(spec.children or {}) do Build(session, child, node.body, scope, node) end
    end
    return node
end

local function Retire(node)
    node.alive = false
    node.generation = (node.generation or 0) + 1
    for _, child in ipairs(node.children) do Retire(child) end
end

-- [决定] 释放必须“继续必要清理，最后报告原错”：任一节点的 owner.release 或清理步骤抛错，
-- 不得中断剩余节点与 root 回池；第一个错误被记录，清理全部完成后用原样重新抛出（对齐 V1 CardSession:Release）。
local function Capture(failures, ok, failure)
    if not ok and not failures.failed then failures.failed, failures.reason = true, failure end
end

local function Rethrow(failures)
    if failures.failed then error(failures.reason, 0) end
end

-- The existing protected release boundary is shared by nodes and overflow.
local function Cleanup(failures, callback, ...)
    Capture(failures, pcall(callback, ...))
end

local function ClosePopup(entry, reason)
    if not entry.popup.isOpen() then return end
    local generation, surface = entry.node.generation, entry.node.session.surface
    local ok, failure = entry.popup.close(reason)
    Check(ok ~= false, failure or "ribbon child popup refused to close")
    if entry.node.generation == generation and entry.node.session.surface == surface then
        Check(not entry.popup.isOpen(), "ribbon child popup remains open after close")
    end
end

ReleaseNode = function(node, failures)
    Retire(node)
    local own = {}
    if node.mountPending then Capture(own, false, "SettingsV2: incomplete adapter mount " .. node.spec.id) end
    for _, child in ipairs(node.children) do ReleaseNode(child, own) end
    node.children = {}
    if node.popups then
        for entry in pairs(node.popups) do
            entry.unsubscribe()
            Cleanup(own, ClosePopup, entry, "release")
        end
        node.popups = nil
    end
    if node.frame then Cleanup(own, node.frame.Hide, node.frame) end
    if node.adapter and node.instance ~= nil then
        if node.spec.kind == "control" and node.spec.controlType == "card" then
            Cleanup(own, UI.RestoreSettingsListControl, UI, node.instance)
        end
        Cleanup(own, node.adapter.release, node.instance, node.context)
    end
    if node.button then Cleanup(own, Factory.Release, Factory, node.button._fromPool, node.button) end
    if node.label then Cleanup(own, function() node.label:Hide(); node.label:SetText("") end) end
    if node.frame and not own.failed then
        if node.spec.kind == "card" then
            local card = node.frame
            Cleanup(own, function()
                if card._v2ToolbarDivider then card._v2ToolbarDivider:Hide() end
                if card._v2Help then
                    card._v2Help:Hide()
                    card._v2Help._v2Text = nil
                    card._v2CollapsedDivider:Hide()
                end
                if node.toggleFont then
                    card._exSettingsCardToggle._exGlyph:SetFont(unpack(node.toggleFont))
                    card._exSettingsCardToggle:SetSize(unpack(node.toggleSize))
                end
                UI:RestoreSettingsListCard(card)
                if node.headerPoints and #node.headerPoints > 0 then
                    card._exSettingsCardHeader:ClearAllPoints()
                    for _, point in ipairs(node.headerPoints) do card._exSettingsCardHeader:SetPoint(unpack(point)) end
                end
            end)
            if not own.failed and node.body then Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.body) end
            if not own.failed then Cleanup(own, card.Release, card) end
        else Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.frame) end
    end
    -- A dirty ancestor is quarantined, never returned around a failed child.
    Capture(failures, not own.failed, own.reason)
    if own.failed then node.session.cleanupFailed, node.session.cleanupFailure = true, own.reason end
    node.mountPending = nil
    node.instance, node.frame, node.body, node.context = nil, nil, nil, nil
    node.adapter, node.button, node.label, node.separator = nil, nil, nil, nil
    node.width, node.reportedHeight, node.naturalWidth = nil, nil, nil
    node.headerPoints, node.toggleFont, node.toggleSize = nil, nil, nil
end

local function SyncRepeat(node)
    local records = Records(node)
    local changed = #records ~= #node.children
    if not changed then
        for i, child in ipairs(node.children) do
            if child.scope.item ~= records[i] then changed = true; break end
        end
    end
    if not changed then return end
    -- No index-based reuse: reset only this repeat region, preserving other nodes.
    local failures = {}
    for _, child in ipairs(node.children) do Retire(child) end
    for _, child in ipairs(node.children) do ReleaseNode(child, failures) end
    node.children = {}
    -- 旧成员清理出错：区域保持为空（下次 Refresh 会重建），先报告原错，不在脏状态上继续建新成员。
    Rethrow(failures)
    for i, record in ipairs(records) do
        local scope = { item=record, index=i, parent=node.scope, _repeatNode=node }
        Build(node.session, node.spec.template, node.body, scope, node)
    end
end

local function Predicate(node, field)
    local ref = node.spec[field]
    if not ref then return true end
    local result = node.session.owner.predicates[ref](node.scope)
    Check(type(result) == "boolean", node.spec.id .. ": predicate must return ordinary boolean")
    return result
end

RefreshNode = function(node, parentVisible, parentEnabled)
    node.visible = parentVisible and Predicate(node, "visible")
    node.enabled = parentEnabled and Predicate(node, "enabled")
    node.managesEnabled = node.spec.enabled ~= nil or (node.parent and node.parent.managesEnabled)
    if node.deferred then return end
    node.frame:SetShown(node.visible)
    if node.spec.kind == "repeat" then SyncRepeat(node) end
    if node.adapter then
        node.reportedHeight = nil
        node.adapter.update(node.instance, node.context, node.spec)
        if node.managesEnabled then node.adapter.setEnabled(node.instance, node.context, node.enabled) end
        node.adapter.setVisible(node.instance, node.context, node.visible)
    elseif node.button then
        node.button:SetEnabled(node.enabled)
    elseif node.spec.kind == "text" or node.spec.kind == "hint" then Text(node) end
    local childrenVisible = node.visible and not (node.spec.kind == "card" and node.frame._exSettingsCardCollapsed)
    for _, child in ipairs(node.children) do RefreshNode(child, childrenVisible, node.enabled) end
end

local function HideNode(node)
    node.visible = false
    if node.frame then node.frame:Hide() end
    if node.adapter then node.adapter.setVisible(node.instance, node.context, false) end
    for _, child in ipairs(node.children) do HideNode(child) end
end

local function Align(value, spare)
    if value == "end" then return math.max(0, spare) end
    if value == "center" then return math.max(0, spare) / 2 end
    return 0
end

local function Natural(node)
    if node.spec.width then return node.spec.width end
    local kind = node.spec.kind
    if kind == "button" then
        return math.max(GM.size.buttonMinWidth,
            (node.button and node.button.GetFontString and node.button:GetFontString()
                and node.button:GetFontString():GetUnboundedStringWidth() or 0)
                + GM.space.buttonPaddingX * 2)
    end
    if kind == "text" or kind == "hint" then
        return math.max(1, node.label:GetUnboundedStringWidth())
    end
    if kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "tristate") then
        local widget = node.instance
        if widget.buttons and widget.minItemWidth then
            -- The existing ChoiceGroup uses these label/icon insets and item gap.
            local width, rowWidth, count, maximum = 0, 0, 0, 0
            for _, button in ipairs(widget.buttons) do
                local itemWidth = math.max(widget.minItemWidth,
                    button.label:GetUnboundedStringWidth() + (button._choiceItem.icon and 36 or 20))
                maximum = math.max(maximum, itemWidth)
                if count > 0 then rowWidth = rowWidth + widget.gap end
                rowWidth, count = rowWidth + itemWidth, count + 1
                if widget.columns and count == widget.columns then
                    width, rowWidth, count = math.max(width, rowWidth), 0, 0
                end
            end
            width = math.max(width, rowWidth)
            if widget.sizing ~= "content" then
                count = math.min(#widget.buttons, widget.columns or #widget.buttons)
                width = count * maximum + math.max(0, count - 1) * widget.gap
            end
            return math.max(1, width
                + ((widget.choiceStyle == "segmented" or widget.choiceStyle == "connected") and 4 or 0))
        end
    end
    -- Bound card checkboxes are as wide as their title (same metrics as the settings list);
    -- owner cards keep the width their owner gave them.
    if kind == "control" and node.spec.controlType == "card" and node.spec.path then
        local card = node.instance.checkbox._exSettingsCardSurface
        if card then
            return 14 + (node.instance._exSettingsCardIcon and 24 or 0)
                + math.ceil(card.Title:GetUnboundedStringWidth()) + 30
        end
    end
    -- The owner's original control width is its natural size. Explicit DSL
    -- widths still take precedence above; do not force every control to 160.
    if node.adapter then
        return math.max(kind == "control" and GM.size.buttonMinWidth or 1, node.naturalWidth or 0)
    end
    if kind == "columns" then
        local width = 0
        for _, column in ipairs(node.spec.columns) do width = width + (column.width or 160) + GAP end
        return math.max(1, width - GAP)
    end
    if node.spec.children or kind == "repeat" then
        local width, count = 0, 0
        local horizontal = kind == "row" or kind == "actions"
        for _, child in ipairs(node.children) do
            if child.visible then
                local childWidth = Natural(child)
                if horizontal then
                    width = width + childWidth + (count > 0 and GAP or 0)
                else width = math.max(width, childWidth) end
                count = count + 1
            end
        end
        if kind == "group" and node.spec.title ~= "" then
            width = math.max(width, node.label:GetUnboundedStringWidth())
        end
        if kind == "card" then
            -- [WEB-REQ 03/64-67] 卡片自然宽是“外宽”：内容自然宽 + 自身左右 padding（LayoutNode 会再扣一次 PAD*2），
            -- 并不小于标题（含折叠钮/帮助钮）所需宽度；否则无显式 width 的卡内容会被二次挤窄。
            local spec, title = node.spec, node.frame._exSettingsCardTitle
            local titleWidth = title and title:GetUnboundedStringWidth() or 0
            if spec.titleAlign == "center" then titleWidth = titleWidth + 8
            else titleWidth = titleWidth + (spec.collapsible and 36 or 0) + (spec.help and 26 or 0) end
            return math.max(1, width + PAD * 2, titleWidth)
        end
        return math.max(1, width)
    end
    return 160
end

local function Flexible(node)
    if node.spec.width then return false end
    local kind = node.spec.kind
    return node.spec.weight ~= nil or kind == "group" or kind == "row" or kind == "actions"
        or kind == "columns" or kind == "repeat" or kind == "component" or kind == "hint"
        or (kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "multiline"))
end

local function Grow(node)
    if node.spec.width then return 0 end
    if node.spec.weight then return node.spec.weight end
    local kind = node.spec.kind
    -- Action regions keep their requested placement; their child containers may grow.
    if kind == "group" or kind == "row" or kind == "columns" or kind == "repeat"
        or kind == "component" or kind == "hint" then return 1 end
    return 0
end

local function IsSettingsRow(node)
    return node ~= nil and node.context ~= nil and node.context._exSettingsRow == true
end

local function Stack(node, width, columns, offset)
    local y = offset or 0
    local visible = {}
    for _, child in ipairs(node.children) do
        if child.visible then visible[#visible + 1] = child end
    end
    for index, child in ipairs(visible) do
        local previous, nextChild = visible[index - 1], visible[index + 1]
        child.hideTrailingSeparator = node.spec.kind == "repeat" and nextChild == nil
        -- Consecutive settings rows form one list: no gap, divider only between rows.
        local row = IsSettingsRow(child)
        if row then child.context._exRowLast = not IsSettingsRow(nextChild) end
        if previous and not (row and IsSettingsRow(previous)) then y = y + GAP end
        local height = LayoutNode(child, width, columns)
        Place(child.frame, node.body, 0, y, width, height)
        y = y + height
    end
    return y
end

local function ColumnWidths(specs, width)
    local gap = math.min(GAP, width / (#specs * 2))
    local room = math.max(1, width - gap * (#specs - 1))
    local fixed, weight, flexible = 0, 0, 0
    for _, spec in ipairs(specs) do
        if spec.width then fixed = fixed + spec.width
        else weight = weight + (spec.weight or 1); flexible = flexible + 1 end
    end
    local fixedBudget = room - flexible * math.min(80, room / #specs)
    local scale = fixed > fixedBudget and fixedBudget / fixed or 1
    local widths = { gap=gap }
    for i, spec in ipairs(specs) do
        widths[i] = spec.width and spec.width * scale
            or math.max(1, room - fixed * scale) * (spec.weight or 1) / math.max(1, weight)
    end
    return widths
end

local function Flow(node, width)
    local lines, line, used = {}, {}, 0
    for _, child in ipairs(node.children) do
        if child.visible then
            local wanted = math.min(width, Natural(child))
            if child.spec.kind == "actions" and not child.spec.width then
                wanted = math.min(width, math.max(wanted, width * 0.55))
            end
            local minimum = Flexible(child) and math.min(wanted, 160) or wanted
            -- 0.01 容差：自然宽（逐项相加）与这里的累计宽浮点舍入顺序不同，刚好排满的一行不能因 1ulp 误差而换行。
            if #line > 0 and used + GAP + minimum > width + 0.01 then
                lines[#lines + 1], line, used = line, {}, 0
            end
            if #line > 0 then used = used + GAP end
            line[#line + 1] = { node=child, width=minimum, preferred=wanted }
            used = used + minimum
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    local y = 0
    for _, entries in ipairs(lines) do
        local occupied, demand, weight, height = GAP * (#entries - 1), 0, 0, 0
        for _, entry in ipairs(entries) do
            occupied = occupied + entry.width
            demand = demand + entry.preferred - entry.width
            weight = weight + Grow(entry.node)
        end
        local available = math.max(0, width - occupied)
        local preferredSpace = math.min(available, demand)
        local extra = available - preferredSpace
        local x = Align(node.spec.align, weight == 0 and extra or 0)
        for _, entry in ipairs(entries) do
            local child = entry.node
            local childWidth = entry.width
                + (demand > 0 and preferredSpace * (entry.preferred - entry.width) / demand or 0)
                + (weight > 0 and extra * Grow(child) / weight or 0)
            -- Position the actions region independently of its internal alignment.
            if child.spec.kind == "actions" and weight == 0 then
                local free = math.max(0, width - x - childWidth)
                x = x + Align(child.spec.position, free)
            end
            entry.x, entry.width = x, childWidth
            entry.height = LayoutNode(child, childWidth)
            height = math.max(height, entry.height)
            x = x + childWidth + GAP
        end
        for _, entry in ipairs(entries) do
            Place(entry.node.frame, node.body, entry.x, y + (height - entry.height) / 2, entry.width, entry.height)
        end
        y = y + height + GAP
    end
    return math.max(0, y - GAP)
end

LayoutNode = function(node, width, columns)
    width = math.max(1, width)
    node.frame:SetWidth(width)
    local kind, height = node.spec.kind, 0
    if node.adapter then
        if node.width ~= width then node.reportedHeight = nil end
        node.width = width
        local measured = node.adapter.measure(node.instance, node.context, width)
        -- Default single-line controls share one height. Owner measurements
        -- still describe multiline/custom content and explicit size contracts.
        local controlType = node.spec.controlType
        if node.adapter.measure == ControlDefaults.measure
            and (controlType == "input" or controlType == "checkbox" or controlType == "card"
                or controlType == "select" or controlType == "color") then
            measured = node.spec.height or GM.size.controlHeight
        end
        Check(type(measured) == "number" and measured >= 0 and measured < math.huge, node.spec.id .. ": invalid measure")
        height = math.max(node.spec.height or 0, node.reportedHeight or measured)
        node.adapter.layout(node.instance, node.context, width, height)
    elseif node.button then
        height = node.spec.height or GM.size.controlHeight
        Place(node.button, node.frame, 0, 0, width, height)
    elseif kind == "text" or kind == "hint" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        height = math.max(node.spec.height or 0, node.label:GetStringHeight())
    elseif kind == "row" and columns then
        local x, heights = 0, {}
        for i, child in ipairs(node.children) do
            heights[i] = child.visible and LayoutNode(child, columns[i]) or 0
            height = math.max(height, heights[i])
        end
        for i, child in ipairs(node.children) do
            Place(child.frame, node.body, x, (height - heights[i]) / 2, columns[i], heights[i])
            x = x + columns[i] + columns.gap
        end
    elseif kind == "row" or kind == "actions" then
        height = Flow(node, width)
    elseif kind == "card" then
        local innerWidth = math.max(1, width - PAD * 2)
        height = Stack(node, innerWidth)
        node.body:SetHeight(math.max(1, height))
        local card, title = node.frame, node.frame._exSettingsCardTitle
        -- 下置标题是功能区的组名：用小号说明字，页脚更矮；titleAlign="center" 让它居中。
        local caption = node.spec.titlePosition == "bottom"
        if caption then UI.ControlAppearance.ApplyTextRole(title, "hint") end
        title:ClearAllPoints()
        if node.spec.titleAlign == "center" then
            title:SetPoint("TOP", card._exSettingsCardHeader, "TOP", 0, caption and -5 or -8)
            title:SetWidth(math.max(1, width - 8))
            title:SetJustifyH("CENTER")
        else
            title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", 0, caption and -5 or -8)
            title:SetWidth(math.max(1, math.min(title:GetUnboundedStringWidth(),
                width - (node.spec.collapsible and 36 or 0))))
        end
        if node.spec.collapsible then
            local toggle = card._exSettingsCardToggle
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", title, "RIGHT", 8, 0)
            toggle:SetSize(28, 28)
            UI.ControlAppearance.ApplyTextRole(toggle._exGlyph, "pageTitle")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
        end
        local help, divider = card._v2Help, card._v2CollapsedDivider
        help:SetShown(node.spec.help ~= nil)
        if node.spec.help then
            help:ClearAllPoints()
            help:SetPoint("LEFT", node.spec.collapsible and card._exSettingsCardToggle or title, "RIGHT", 4, 0)
        end
        divider:ClearAllPoints()
        divider:SetPoint("BOTTOMLEFT", card._exSettingsCardHeader, "BOTTOMLEFT", 12, 0)
        divider:SetPoint("BOTTOMRIGHT", card._exSettingsCardHeader, "BOTTOMRIGHT", -12, 0)
        divider:SetHeight(1)
        divider:SetShown(node.spec.collapsible == true and card._exSettingsCardCollapsed == true)
        local hasHeader = (title:GetText() or "") ~= "" or node.spec.collapsible == true
        local headerHeight = hasHeader and (title:GetStringHeight() + (caption and 12 or 26)) or 0
        card._exSettingsListExternalHeader.height = headerHeight
        card._exSettingsCardHeader:SetShown(hasHeader)
        card._exSettingsCardHeader:SetHeight(math.max(1, headerHeight))
        card:GetBody():ClearAllPoints()
        PixelUtil.SetPoint(card:GetBody(), "TOPLEFT", card, "TOPLEFT", 0, -headerHeight, 0, 0)
        PixelUtil.SetPoint(card:GetBody(), "TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight, 0, 0)
        node.frame:SetContentHeight(height + PAD * 2)
        if node.spec.titlePosition == "bottom" then
            card:GetBody():ClearAllPoints()
            card:GetBody():SetPoint("TOPLEFT", card, "TOPLEFT")
            card:GetBody():SetPoint("TOPRIGHT", card, "TOPRIGHT")
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
            card._exSettingsCardHeader:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
        else
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("TOPLEFT", card, "TOPLEFT")
            card._exSettingsCardHeader:SetPoint("TOPRIGHT", card, "TOPRIGHT")
        end
        return node.frame:GetPreferredHeight()
    elseif kind == "columns" then
        height = Stack(node, width, ColumnWidths(node.spec.columns, width))
    elseif kind == "group" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        local hasTitle = node.spec.title ~= ""
        node.label:SetShown(hasTitle)
        height = Stack(node, width, nil, hasTitle and (node.label:GetStringHeight() + GAP) or 0)
    else
        height = Stack(node, width, columns)
    end
    if node.separator then
        node.separator:SetShown(not node.hideTrailingSeparator)
        if not node.hideTrailingSeparator then
            node.separator:ClearAllPoints()
            node.separator:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, -(height + GAP / 2))
            node.separator:SetWidth(width)
            height = height + GAP
        end
    end
    node.frame:SetHeight(math.max(1, height))
    return height
end

local OverflowHosts = setmetatable({}, { __mode="k" })

local function AcquireRibbonOverflowSurface(session)
    local surface = {}
    local function close(_, reason)
        if session.surface == surface then session:CloseRibbonOverflow(reason or "hidden") end
    end
    local window = UI:CreateFloatingWindow({ width=200, height=100, title=session.ribbonOverflow.title,
        closable=true, onCloseRequested=close, onHide=close })
    Check(not OverflowHosts[window], "overflow host is occupied")
    surface.window, session.surface = window, surface
    OverflowHosts[window] = surface
    local input = window._v2OverflowInput
    if not input then
        input = CreateFrame("Frame", nil, window)
        window._v2OverflowInput = input
    end
    surface.input = input
    -- ScrollFrame has no pool/release contract: keep it with its floating host.
    local scroll = window._v2OverflowScroll
    if not scroll then
        scroll = UI:CreateScrollFrame(window.content, nil, { horizontal=true })
        window._v2OverflowScroll = scroll
        scroll._v2Content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(scroll._v2Content)
    end
    scroll:SetParent(window.content)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", window.content, "BOTTOMRIGHT", -20, scroll:GetHorizontalScrollInset())
    scroll:Show()
    scroll._v2Content:Show()
    surface.scroll, surface.host = scroll, scroll._v2Content
    function surface:GetContentHost() return self.host end
    function surface:StartInput()
        if self.inputScheduled then return end
        self.inputScheduled = true
        local lease = self
        -- Do not consume the click that opened this lease. A late callback cannot
        -- register an event on a closed/reused floating host.
        C_Timer.After(0, function()
            if session.surface ~= lease or not session:IsRibbonOverflowOpen() then return end
            input:SetScript("OnEvent", function(_, event, button)
                if event ~= "GLOBAL_MOUSE_DOWN" or (button ~= "LeftButton" and button ~= "RightButton") then return end
                if session.surface ~= lease or not session:IsRibbonOverflowOpen() then return end
                for _, focus in ipairs(GetMouseFoci()) do
                    if session:OwnsRibbonFrame(focus) then return end
                    if session.surface ~= lease or not session:IsRibbonOverflowOpen() then return end
                end
                session:CloseRibbonOverflow("outside")
            end)
            input:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)
    end
    function surface:Present(anchor, contentWidth, contentHeight)
        local chromeX = GM.space.cardBodyPadding * 2 + 20
        local chromeY = GM.size.floatingHeaderHeight + GM.space.cardBodyPadding + self.scroll:GetHorizontalScrollInset()
        self.host:SetSize(math.max(1, contentWidth), math.max(1, contentHeight))
        self.window:SetSize(math.max(1, math.min(UIParent:GetWidth() - 20, contentWidth + chromeX)),
            math.max(1, math.min(UIParent:GetHeight() - 20, contentHeight + chromeY)))
        self.window:ClearAllPoints()
        self.window:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP)
        self.window:Show()
        self.scroll:UpdateScrollChildRect()
    end
    function surface:HideAfterRetire()
        self.input:SetScript("OnEvent", nil)
        self.input:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self.window:Hide()
        self.scroll:SetHorizontalScroll(0)
        self.scroll:SetVerticalScroll(0)
    end
    function surface:ReleaseAfterContent()
        self.scroll:Hide()
        self.window:Release()
        OverflowHosts[self.window] = nil
    end
    return surface
end

local function RibbonCards(session)
    local cards = {}
    local function append(node)
        if not node.visible then return end
        if node.spec.kind == "repeat" then
            for _, child in ipairs(node.children) do append(child) end
        else cards[#cards + 1] = node end
    end
    for _, node in ipairs(session.nodes) do append(node) end
    return cards
end

local function CloseOverflow(session, failures)
    if session.overflowState == "closing" then return end
    session.overflowState = "closing"
    local cards, surface = session.overflowNodes or {}, session.surface
    -- Retire every lease before the first owner release or visibility callback.
    for _, node in ipairs(cards) do Retire(node) end
    if surface then Cleanup(failures, surface.HideAfterRetire, surface) end
    for _, node in ipairs(cards) do
        if not node.deferred then ReleaseNode(node, failures) end
        node.deferred, node.overflow = true, false
    end
    if surface and not failures.failed then Cleanup(failures, surface.ReleaseAfterContent, surface) end
    session.surface, session.overflowNodes = nil, nil
    session.overflowState = failures.failed and "failed" or (session.alive and "closed" or "released")
    if failures.failed then session.cleanupFailed, session.cleanupFailure = true, failures.reason end
end

function Session:CloseRibbonOverflow(reason)
    if self.overflowState == "closing" then return true end
    if not self.surface and not self.overflowNodes then return true end
    local failures = {}
    CloseOverflow(self, failures)
    self:Invalidate()
    Rethrow(failures)
    return true
end

function Session:SetRibbonAvailableWidth(width)
    if not self.alive or self.cleanupFailed or self.overflowState == "failed" or not self.ribbonOverflow or not Number(width) then
        return Issue("options.ribbonOverflow.availableWidth", "active ribbon and positive finite width required", nil, "INVALID_ARGUMENT")
    end
    if self.ribbonOverflow.availableWidth ~= width then
        self:CloseRibbonOverflow("resize")
        self.ribbonOverflow.availableWidth = width
        self:Invalidate()
    end
    return true
end

function Session:IsRibbonOverflowOpen()
    return self.alive and self.overflowState == "open" and self.surface ~= nil
        and self.surface.window:IsVisible() or false
end

local function CurrentPopup(session, entry)
    return session.surface == entry.surface and entry.generation == entry.node.generation
        and Current(entry.node)
end

function Session:OwnsRibbonFrame(frame)
    if not self:IsRibbonOverflowOpen() then return false end
    local surface, cursor = self.surface, frame
    while cursor do
        if cursor == self.moreButton or cursor == surface.window then return true end
        if (type(cursor) ~= "table" and type(cursor) ~= "userdata") or type(cursor.GetParent) ~= "function" then break end
        cursor = cursor:GetParent()
    end
    for entry in pairs(self.ribbonPopups or {}) do
        if CurrentPopup(self, entry) and entry.popup.isOpen() and CurrentPopup(self, entry) then
            local owns = entry.popup.ownsFrame(frame)
            if self.surface ~= surface or not self:IsRibbonOverflowOpen() then return false end
            if owns and CurrentPopup(self, entry) then return true end
        end
    end
    return false
end

-- true: consumed by a child; false: no child, caller may close More next.
function Session:CloseRibbonChildPopup(reason)
    if not self:IsRibbonOverflowOpen() then return false end
    local latest
    for entry in pairs(self.ribbonPopups or {}) do
        if CurrentPopup(self, entry) and entry.popup.isOpen() and CurrentPopup(self, entry)
            and (not latest or latest.serial < entry.serial) then latest = entry end
    end
    if not latest then return false end
    ClosePopup(latest, reason or "escape")
    return true
end

function Session:RepositionRibbonOverflow()
    if not self.alive or self.overflowState ~= "open" or not self.surface then return false end
    self.surface.window:ClearAllPoints()
    self.surface.window:SetPoint("TOPRIGHT", self.moreButton, "BOTTOMRIGHT", 0, -GAP)
    return true
end

function Session:OpenRibbonOverflow()
    if not self.alive or self.cleanupFailed or not self.ribbonOverflow or not self.root:IsVisible() then return false end
    if self.overflowState == "opening" or self.overflowState == "closing" then return false end
    if self.overflowState == "open" then return true end
    if not self.ribbonMetrics or self.ribbonMetrics.overflowCount == 0 then return false end
    self.overflowState = "opening"
    -- Layout already owns the protected build/measure failure boundary.
    self:Layout()
    return self.overflowState == "open"
end

local function ArrangeRibbon(session)
    local cards, totalWidth = RibbonCards(session), PAD * 2
    for i, card in ipairs(cards) do totalWidth = totalWidth + card.spec.width + (i > 1 and GAP or 0) end
    local budget, count = session.ribbonOverflow.availableWidth, #cards
    local more = session.moreButton
    local moreWidth = math.max(GM.size.buttonMinWidth, more:GetFontString():GetUnboundedStringWidth() + GM.space.buttonPaddingX * 2)
    local prefix, barWidth = count, totalWidth
    if totalWidth > budget + 0.01 then
        prefix, barWidth = 0, PAD * 2 + moreWidth
        for _, card in ipairs(cards) do
            local candidate = barWidth + card.spec.width + GAP
            if candidate > budget + 0.01 then break end
            prefix, barWidth = prefix + 1, candidate
        end
    end
    local overflow = count - prefix
    local x, tallest, overflowWidth, overflowHeight = PAD, 0, PAD * 2, 0
    local nextOverflow = {}
    for i = prefix + 1, count do nextOverflow[#nextOverflow + 1] = cards[i] end
    if session.surface then
        local previous, changed = session.overflowNodes or {}, false
        if #previous ~= #nextOverflow then changed = true end
        for i, card in ipairs(nextOverflow) do if previous[i] ~= card then changed = true; break end end
        if changed then session:CloseRibbonOverflow("allocation-changed") end
    end
    session.overflowNodes = nextOverflow
    if overflow > 0 and session.overflowState == "opening" then AcquireRibbonOverflowSurface(session) end
    local failures = {}
    -- Newly excluded bar cards lose their complete old lease before any cleanup.
    for i = prefix + 1, count do
        if not session.surface and not cards[i].deferred then Retire(cards[i]) end
    end
    for i, card in ipairs(cards) do
        local inOverflow = i > prefix
        if inOverflow and not session.surface then
            if not card.deferred then ReleaseNode(card, failures); card.deferred = true end
            overflowWidth = overflowWidth + card.spec.width + (i > prefix + 1 and GAP or 0)
        else
            local parent = inOverflow and session.surface:GetContentHost() or session.root
            card.overflow = inOverflow
            if card.deferred then
                MountNode(card, parent)
                RefreshNode(card, true, card.parent == nil or card.parent.enabled)
            end
            local height = LayoutNode(card, card.spec.width)
            if session.presentation == "toolbar" then card.frame._v2ToolbarDivider:SetShown(i ~= prefix and i ~= count) end
            if inOverflow then
                Place(card.frame, parent, overflowWidth - PAD, PAD, card.spec.width, height)
                overflowWidth = overflowWidth + card.spec.width + GAP
                overflowHeight = math.max(overflowHeight, height)
            else
                Place(card.frame, parent, x, PAD, card.spec.width, height)
                x, tallest = x + card.spec.width + GAP, math.max(tallest, height)
            end
        end
    end
    Rethrow(failures)
    more:SetShown(overflow > 0)
    if overflow > 0 then
        tallest = math.max(tallest, GM.size.controlHeight)
        Place(more, session.root, x, PAD, moreWidth, GM.size.controlHeight)
    end
    if session.surface then
        overflowWidth = math.max(PAD * 2, overflowWidth - GAP)
        overflowHeight = overflowHeight + PAD * 2
        session.surface:Present(more, overflowWidth, overflowHeight)
        session.overflowState = "open"
        session.surface:StartInput()
    end
    local height = tallest + PAD * 2
    session.ribbonMetrics = { availableWidth=budget, barWidth=barWidth, barHeight=height, totalWidth=totalWidth,
        overflowCount=overflow, overflowWidth=overflow > 0 and overflowWidth or 0, overflowHeight=overflowHeight }
    return totalWidth, height
end

-- Mounted-node lookup for page services (preview focus, style presets). Repeat
-- templates share one id; the first mounted record wins.
function Session:ForEachNode(callback)
    local function Walk(nodes)
        for _, node in ipairs(nodes) do
            if node.alive and not node.deferred then
                if callback(node) == true then return true end
                if Walk(node.children) then return true end
            end
        end
    end
    if self.alive then Walk(self.nodes) end
end

function Session:FindNode(id)
    local found
    self:ForEachNode(function(node)
        if node.spec.id == id then found = node; return true end
    end)
    return found
end

function Session:GetHeight() return self.height or 0 end
function Session:GetContentWidth() return self.contentWidth or 0 end

-- [决定] Layout 出错恢复：测量/布局阶段抛错时必须清除 layingOut 锁，再原样报告原错，
-- 否则之后的所有 Invalidate/Refresh 都会在入口直接返回、页面永远不再重排（对齐 V1/网页 renderer 的 finally）。
function Session:Layout()
    if not self.alive or self.cleanupFailed or self.layingOut or self.overflowState == "failed" then return end
    self.layingOut = true
    local width, y = math.max(1, self.root:GetWidth() - PAD * 2), PAD
    local x, tallest = PAD, 0
    local function Arrange(node)
        if node.visible then
            if self.layout == "ribbon" and node.spec.kind == "repeat" then
                Place(node.frame, self.root, 0, 0, width + PAD * 2, 1)
                for _, child in ipairs(node.children) do Arrange(child) end
                node.frame:SetHeight(math.max(1, tallest + PAD * 2))
                return
            end
            local nodeWidth = self.layout == "ribbon" and Natural(node) or width
            local height = LayoutNode(node, nodeWidth)
            Place(node.frame, self.root, self.layout == "ribbon" and x or PAD, y, nodeWidth, height)
            if self.layout == "ribbon" then
                x, tallest = x + nodeWidth + GAP, math.max(tallest, height)
            else y = y + height + GAP end
        end
    end
    local ribbonWidth, ribbonHeight
    local ok, failure = pcall(function()
        if self.ribbonOverflow then ribbonWidth, ribbonHeight = ArrangeRibbon(self)
        else for _, node in ipairs(self.nodes) do Arrange(node) end end
    end)
    self.layingOut = false
    if not ok then
        if self.ribbonOverflow then
            local failures = {}
            local cards = RibbonCards(self)
            for _, node in ipairs(cards) do Retire(node) end
            CloseOverflow(self, failures)
            for _, node in ipairs(cards) do
                if not node.deferred then ReleaseNode(node, failures); node.deferred = true end
            end
            self.overflowState = "failed"
        end
        error(failure, 0)
    end
    local contentWidth = self.layout == "ribbon" and math.max(PAD * 2, x - GAP + PAD) or width + PAD * 2
    local height = math.max(PAD * 2, self.layout == "ribbon" and tallest + PAD * 2 or y - GAP + PAD)
    contentWidth, height = ribbonWidth or contentWidth, ribbonHeight or height
    self.root:SetHeight(height)
    -- 宿主回调：onHeightChanged(height) 报告真实高度；onContentWidthChanged(width) 报告真实内容宽（ribbon 的自然宽）。
    -- 两者都在布局锁释放、本次结果已落定之后才调用，回调里读 GetHeight/GetContentWidth 得到的就是这次结果。
    local heightChanged, widthChanged = self.height ~= height, self.contentWidth ~= contentWidth
    self.height, self.contentWidth = height, contentWidth
    if heightChanged and self.owner.onHeightChanged then self.owner.onHeightChanged(height) end
    if not self.alive then return end
    if widthChanged and self.owner.onContentWidthChanged then self.owner.onContentWidthChanged(contentWidth) end
    if self.alive and self.ribbonMetrics and self.owner.onRibbonLayout then
        local metrics = {}
        for key, value in pairs(self.ribbonMetrics) do metrics[key] = value end
        self.owner.onRibbonLayout(metrics)
    end
end

function Session:Invalidate()
    if not self.alive or self.cleanupFailed or self.overflowState == "failed" or self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        if not self.alive then return end
        self.pending = false
        self:Layout()
    end)
end

function Session:Refresh()
    if not self.alive or self.cleanupFailed or self.overflowState == "failed" then return false end
    if self.ribbonOverflow then
        self:CloseRibbonOverflow("refresh")
        self.overflowState = "closed"
    end
    for _, node in ipairs(self.nodes) do RefreshNode(node, true, true) end
    self:Invalidate()
end

-- Keep parent occupancy until all owned resources have been cleaned successfully.
function Session:Release()
    if not self.alive then return end
    self.alive = false
    local failures, root = {}, self.root
    if self.cleanupFailed then Capture(failures, false, self.cleanupFailure) end
    for _, node in ipairs(self.nodes) do Retire(node) end
    Cleanup(failures, function()
        root:SetScript("OnSizeChanged", nil)
        root:SetScript("OnHide", nil)
        root:SetScript("OnShow", nil)
    end)
    CloseOverflow(self, failures)
    for _, node in ipairs(self.nodes) do ReleaseNode(node, failures) end
    self.nodes = {}
    if self.moreButton then
        Cleanup(failures, Factory.Release, Factory, self.moreButton._fromPool, self.moreButton)
        self.moreButton = nil
    end
    Cleanup(failures, root.Hide, root)
    if not failures.failed then Cleanup(failures, Factory.ReleaseCompositeHost, Factory, root) end
    if not failures.failed and Mounted[self.parent] == self then Mounted[self.parent] = nil end
    self.root, self.surface = nil, nil
    self.overflowState = failures.failed and "failed" or "released"
    Rethrow(failures)
end

function UI:MountSettingsDeclarationV2(parent, declaration, owner, options)
    local ok, issue = Validate(declaration, owner, options)
    if not ok then return nil, issue end
    if (type(parent) ~= "table" and type(parent) ~= "userdata") or type(parent.GetWidth) ~= "function" or type(owner) ~= "table" then
        local _, invalid = Issue("parent", "parent and owner required", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    if Mounted[parent] then
        local _, invalid = Issue("parent", "parent already owns a V2 session or failed cleanup", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    declaration = DeclarationCopy(declaration, {})
    local session = setmetatable({ alive=true, owner=owner, nodes={}, layout=declaration.layout,
        presentation=declaration.presentation, parent=parent, overflowState="closed",
        ribbonOverflow=options and options.ribbonOverflow and DeclarationCopy(options.ribbonOverflow, {}) }, { __index=Session })
    session.root = Acquire(parent)
    Mounted[parent] = session
    session.root:SetPoint("TOPLEFT")
    session.root:SetPoint("TOPRIGHT")
    session.root:SetScript("OnSizeChanged", function(_, width)
        if session.width ~= width then session.width = width; session:Invalidate() end
    end)
    session.root:SetScript("OnHide", function()
        if not session.alive then return end
        session:CloseRibbonOverflow("parent-hidden")
        for _, node in ipairs(session.nodes) do HideNode(node) end
    end)
    session.root:SetScript("OnShow", function() session:Refresh() end)
    local mounted, failure = pcall(function()
        if session.ribbonOverflow then
            session.moreButton = UI:CreateButton(session.root, GM.size.buttonMinWidth, GM.size.controlHeight,
                session.ribbonOverflow.title, function()
                    if not session.alive then return end
                    if session.overflowState == "open" then session:CloseRibbonOverflow("toggle")
                    else session:OpenRibbonOverflow() end
                end, { variant="secondary", compact=true })
        end
        for _, spec in ipairs(declaration.cards) do Build(session, spec, session.root) end
        session:Refresh()
        session:Layout()
    end)
    if not mounted then
        local released, releaseFailure = pcall(function() session:Release() end)
        error(tostring(failure) .. (released and "" or "\nRelease: " .. tostring(releaseFailure)), 0)
    end
    return session
end

function UI:MountSettingsPageV2(parent, pageId, owner, options)
    local declaration = Pages[pageId]
    Check(declaration ~= nil, "unregistered page " .. tostring(pageId))
    local session, issue = self:MountSettingsDeclarationV2(parent, declaration, owner, options)
    Check(session ~= nil, issue and (issue.path .. ": " .. issue.message))
    return session
end

-- Context menus share the page reference/record rules and the existing menu painter.
local Menus, MenuSession = {}, {}
local MenuFields = {
    button = "text textSource action presentation", menu = "text textSource children",
    separator = "", ["repeat"] = "source template",
}

local function ValidateMenuNode(node, owner, ids, depth, submenuDepth)
    Check(type(node) == "table" and MenuFields[node.kind], "unknown menu node kind")
    Keys(node, "id kind visible enabled " .. MenuFields[node.kind], "menu node")
    Check(Name(node.id) and not ids[node.id], "missing/duplicate menu id " .. tostring(node.id))
    ids[node.id] = true
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then Reference(owner, "predicates", node[field], node.id) end
    end
    if node.kind == "repeat" then
        Check(depth < 2, "at most two nested menu repeats")
        Reference(owner, "sources", node.source, node.id)
        ValidateMenuNode(node.template, owner, ids, depth + 1, submenuDepth)
    elseif node.kind ~= "separator" then
        Check((node.text ~= nil) ~= (node.textSource ~= nil), node.id .. ": use text or textSource")
        if node.text ~= nil then Check(type(node.text) == "string", "menu text must be string") end
        if node.textSource ~= nil then Reference(owner, "texts", node.textSource, node.id) end
        if node.kind == "button" then
            Reference(owner, "actions", node.action, node.id)
            Check(node.presentation == nil or node.presentation == "primary" or node.presentation == "secondary"
                or node.presentation == "danger", "invalid menu presentation")
        else
            Check(submenuDepth < 1, "context menu supports one submenu level")
            Array(node.children, node.id .. ".children")
            for _, child in ipairs(node.children) do
                ValidateMenuNode(child, owner, ids, depth, submenuDepth + 1)
            end
        end
    end
end

local function ValidateMenu(declaration, owner)
    Keys(declaration, "version items", "menu")
    Check(declaration.version == 2, "menu version must be 2")
    Array(declaration.items, "menu items")
    local ids = {}
    for _, node in ipairs(declaration.items) do ValidateMenuNode(node, owner, ids, 0, 0) end
end

function UI:RegisterContextMenuV2(menuId, declaration)
    Check(Name(menuId) and Menus[menuId] == nil, "missing/duplicate menu id")
    local copy = DeclarationCopy(declaration, {})
    ValidateMenu(copy)
    Menus[menuId] = copy
end

function MenuSession:Release()
    if not self.alive then return end
    self.alive = false
    if self.frame and UI._contextMenu == self.frame and self.frame._v2Session == self then
        UI:HideContextMenu()
        self.frame._v2Session = nil
    end
end

function UI:ShowContextMenuV2(menuId, owner, options)
    Check(Menus[menuId] ~= nil, "unregistered menu " .. tostring(menuId))
    Check(type(owner) == "table" and type(owner.isCurrent) == "function", "menu owner requires isCurrent")
    options = options or {}
    ValidateMenu(Menus[menuId], owner)
    local previous = self._contextMenu and self._contextMenu._v2Session
    if previous then previous:Release() end
    local session = setmetatable({ alive=true, owner=owner }, { __index=MenuSession })
    local function predicate(name, scope)
        if name == nil then return true end
        local value = owner.predicates[name](scope)
        Check(type(value) == "boolean", "menu predicate must return ordinary boolean")
        return value
    end
    local function current(scope)
        if not session.alive or owner.isCurrent(scope) ~= true then return false end
        while scope do
            local records = owner.sources[scope._source](scope.parent)
            if records[scope.index] ~= scope.item then return false end
            scope = scope.parent
        end
        return true
    end
    local expand
    expand = function(nodes, scope, ancestors)
        local items = {}
        for _, node in ipairs(nodes) do
            if predicate(node.visible, scope) then
                local chain = {}
                for i, entry in ipairs(ancestors or {}) do chain[i] = entry end
                chain[#chain + 1] = { spec=node, scope=scope }
                if node.kind == "repeat" then
                    local records = owner.sources[node.source](scope)
                    Array(records, node.id .. " source")
                    local seen = {}
                    for i, record in ipairs(records) do
                        Check(type(record) == "table" and not seen[record], "menu requires unique original records")
                        seen[record] = true
                        local childScope = { item=record, index=i, parent=scope, _source=node.source }
                        for _, item in ipairs(expand({ node.template }, childScope, chain)) do
                            items[#items + 1] = item
                        end
                    end
                elseif node.kind == "separator" then
                    items[#items + 1] = { divider=true }
                else
                    local text = node.text or owner.texts[node.textSource](scope)
                    Check(type(text) == "string", "menu text source must return string")
                    local ctx = { scope=scope }
                    function ctx:IsCurrent() return current(scope) end
                    function ctx:Guard(callback)
                        Check(type(callback) == "function", "Guard expects a callback")
                        return function(...)
                            if not current(scope) then return end
                            for _, entry in ipairs(chain) do
                                if not predicate(entry.spec.visible, entry.scope)
                                    or not predicate(entry.spec.enabled, entry.scope) then return end
                            end
                            return callback(...)
                        end
                    end
                    local enabled = true
                    for _, entry in ipairs(chain) do enabled = enabled and predicate(entry.spec.enabled, entry.scope) end
                    local item = { text=text, disabled=not enabled, danger=node.presentation == "danger" }
                    if node.kind == "menu" then
                        item.submenu = expand(node.children, scope, chain)
                    else
                        item.onClick = ctx:Guard(function()
                            local ok, failure = pcall(owner.actions[node.action], ctx, "LeftButton")
                            session:Release()
                            if not ok then error(failure, 0) end
                        end)
                    end
                    items[#items + 1] = item
                end
            end
        end
        return items
    end
    local items = expand(Menus[menuId].items)
    if #items == 0 or owner.isCurrent(nil) ~= true then session.alive=false; return session end
    session.frame = self:ShowContextMenu({ items=items, x=options.x, y=options.y, title=options.title })
    session.frame._v2Session = session
    return session
end
