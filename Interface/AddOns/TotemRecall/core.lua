-- Register Addon
TotemRecall = LibStub("AceAddon-3.0"):NewAddon("TotemRecall", "AceConsole-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local squareAtlas = C_Texture.GetAtlasInfo("SquareMask")
local db

local anchorPoints = {
    ["TOPLEFT"] = "Top Left", ["TOP"] = "Top", ["TOPRIGHT"] = "Top Right",
    ["LEFT"] = "Left", ["CENTER"] = "Center", ["RIGHT"] = "Right",
    ["BOTTOMLEFT"] = "Bottom Left", ["BOTTOM"] = "Bottom", ["BOTTOMRIGHT"] = "Bottom Right",
}

local parentFrameOptions = {
    "UIParent",
    "PlayerFrame",
    "UUF_Player",
    "ElvUF_Player",
    "EllesmereUIUnitFrames_Player",
    "MANUAL",
}

local parentFrameLabels = {
    ["UIParent"] = "Screen (UIParent)",
    ["PlayerFrame"] = "|cFF00AEF7Blizzard|r: Player Frame",
    ["UUF_Player"] = "|cFF8080FFUnhalted|rUF: Player Frame",
    ["ElvUF_Player"] = "|cff1784d1ElvUI|r: Player Frame",
    ["EllesmereUIUnitFrames_Player"] = "|cff0CD29DEUI|r: Player Frame",
    ["MANUAL"] = "Custom",
}

local defaults = {
    profile = {
        ParentFrameName = "UIParent",
        ParentSelectMode = "UIParent",
        ParentAnchor = "CENTER",
        TotemAnchor = "CENTER",
        UseSquareMask = true,
        XOffset = 0,
        YOffset = 0,
        IconScale = 1.0,
        IconSpacing = 0,
        GrowthDirection = "RIGHT",
        TimerXOffset = 0,
        TimerYOffset = 0,
        FontHeader = "Friz Quadrata TT",
        FontSize = 12,
        FontOutline = "OUTLINE",
        TestMode = false,
        TestCount = 1,
        useMasque = false,
    }
}
local testModeTicker -- Variable to hold the timer reference

local function DisableTestMode()
    if db.profile.TestMode then
        db.profile.TestMode = false
        TotemRecall:UpdateLayout()
        LibStub("AceConfigRegistry-3.0"):NotifyChange("TotemRecall")
    end
    -- Stop the timer if it exists
    if testModeTicker then
        testModeTicker:Cancel()
        testModeTicker = nil
    end
end

-- GUI Layout
local options = {
    name = "TotemRecall",
    type = "group",
    args = {
        -- Main Settings Tab
        settings = {
            name = "General Settings",
            type = "group",
            order = 1,
            args = {
                UseSquareMask = {
                    name = "Use Square Mask",
                    desc = "Requires UI Reload to fully revert if disabled.",
                    type = "toggle",
                    set = function(_, val) db.profile.UseSquareMask = val; TotemRecall:UpdateLayout() end,
                    get = function() return db.profile.UseSquareMask end,
                    order = 3,
                },
                TestMode = {
                    name = "Dummy icons",
                    desc = "Shows dummy icons. Auto-disables when closing settings.",
                    type = "toggle",
                    set = function(_, val)
                        db.profile.TestMode = val
                        TotemRecall:UpdateLayout()
                        if val then
                            -- Start the CPU-efficient monitor only when TestMode is ON
                            testModeTicker = C_Timer.NewTicker(0.5, function()
                                -- Check both the New Retail Settings and the AceConfig floating windows
                                local isSettingsOpen = (SettingsPanel and SettingsPanel:IsShown())
                                local isAceOpen = LibStub("AceConfigDialog-3.0").OpenFrames["TotemRecall"]

                                if not isSettingsOpen and not isAceOpen then
                                    DisableTestMode()
                                end
                            end)
                        elseif testModeTicker then
                            testModeTicker:Cancel()
                            testModeTicker = nil
                        end
                    end,
                    get = function() return db.profile.TestMode end,
                    order = 1,
                },
                TestCount = {
                    name = "Dummy Icon Count",
                    desc = "Number of dummy icons to show during Test Mode.",
                    type = "range",
                    min = 1, max = 4, step = 1,
                    set = function(_, val) db.profile.TestCount = val; TotemRecall:UpdateLayout() end,
                    get = function() return db.profile.TestCount end,
                    disabled = function() return not db.profile.TestMode end,
                    order = 2,
                },
                reset = {
                    name = "Reset Current Profile",
                    type = "execute",
                    confirm = true,
                    func = function() db:ResetProfile(); TotemRecall:UpdateLayout() end,
                    order = 4,
                },
                masqueToggle = {
                    name = "Masque Support",
                    desc = "Enable skinning via Masque (Requires 'Use Square Mask' and Reload)",
                    type = "toggle",
                    set = function(_, val)
                        db.profile.useMasque = val
                        print("|cFFFF0000TotemRecall:|r You must reload your UI for Masque changes to take effect.")
                    end,
                    get = function() return db.profile.useMasque end,
                    order = 5,
                },
                positioning = {
                    name = "Positioning & Scale",
                    type = "group",
                    inline = true,
                    order = 6,
                    args = {
                        ParentSelect = {
                            name = "Attach To",
                            desc = "Choose a common frame to attach totems to.",
                            type = "select",
                            values = function()
                                local t = {}
                                for _, key in ipairs(parentFrameOptions) do
                                    t[key] = parentFrameLabels[key]
                                end
                                return t
                            end,
                            sorting = parentFrameOptions,
                            set = function(_, val)
                                if val ~= "MANUAL" then
                                    db.profile.ParentFrameName = val
                                end
                                db.profile.ParentSelectMode = val
                                TotemRecall:UpdateLayout()
                            end,
                            get = function() return db.profile.ParentSelectMode or "UIParent" end,
                            order = 1,
                        },
                        ParentFrameName = {
                            name = "Parent Frame",
                            type = "input",
                            set = function(_, val) db.profile.ParentFrameName = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.ParentFrameName end,
                            order = 2,
                        },
                        IconScale = {
                            name = "Icon Scale",
                            type = "range", min = 0.5, max = 2.5, step = 0.05, isPercent = true,
                            set = function(_, val) db.profile.IconScale = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.IconScale end,
                            order = 3,
                        },
                        ParentAnchor = { name = "Parent Anchor Point", type = "select", values = anchorPoints,
                            set = function(_, val) db.profile.ParentAnchor = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.ParentAnchor end, order = 4 },
                        -- TotemAnchor = { name = "Totem Point", type = "select", 
                        --     values = {
                        --         ["CENTER"] = "Center",
                        --         ["LEFT"] = "Left",
                        --         ["RIGHT"] = "Right",
                        --         ["TOP"] = "Top",
                        --         ["BOTTOM"] = "Bottom",
                        --     },    
                        --     set = function(_, val) db.profile.TotemAnchor = val; TotemRecall:UpdateLayout() end,
                        --     get = function() return db.profile.TotemAnchor end, order = 5 },
                        XOffset = { name = "X Offset", type = "range", min = -500, max = 500, step = 0.1,
                            set = function(_, val) db.profile.XOffset = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.XOffset end, order = 8 },
                        YOffset = { name = "Y Offset", type = "range", min = -500, max = 500, step = 0.1,
                            set = function(_, val) db.profile.YOffset = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.YOffset end, order = 9 },
                        IconSpacing = {
                            name = "Icon Spacing",
                            desc = "Sets the distance between icons.",
                            type = "range",
                            min = -50, max = 50, step = 0.1,
                            set = function(_, val) db.profile.IconSpacing = val; TotemRecall:UpdateLayout() end,
                            get = function(_) return db.profile.IconSpacing end,
                            order = 6,
                        },
                        GrowthDirection = {
                            name = "Growth Direction",
                            desc = "Which way the totems expand from the first icon.",
                            type = "select",
                            values = {
                                ["LEFT"] = "Left",
                                ["RIGHT"] = "Right",
                                ["UP"] = "Up",
                                ["DOWN"] = "Down",
                            },
                            set = function(_, val) db.profile.GrowthDirection = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.GrowthDirection end,
                            order = 7,
                        },
                    }
                },
                fontSettings = {
                    name = "Font Settings",
                    type = "group",
                    inline = true,
                    order = 12,
                    args = {
                        FontHeader = {
                            type = "select",
                            dialogControl = "LSM30_Font",
                            name = "Font",
                            values = LSM:HashTable("font"),
                            get = function() return db.profile.FontHeader end,
                            set = function(_, val) db.profile.FontHeader = val; TotemRecall:UpdateLayout() end,
                        },
                        FontSize = {
                            name = "Font Size",
                            type = "range", min = 6, max = 32, step = 1,
                            get = function() return db.profile.FontSize end,
                            set = function(_, val) db.profile.FontSize = val; TotemRecall:UpdateLayout() end,
                        },
                        FontOutline = {
                            name = "Outline",
                            type = "select",
                            values = { [""] = "None", ["OUTLINE"] = "Thin", ["THICKOUTLINE"] = "Thick" },
                            get = function() return db.profile.FontOutline end,
                            set = function(_, val) db.profile.FontOutline = val; TotemRecall:UpdateLayout() end,
                        },
                         TimerXOffset = {
                            name = "Timer X Offset",
                            type = "range", min = -100, max = 100, step = 0.5,
                            set = function(_, val) db.profile.TimerXOffset = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.TimerXOffset end,
                            order = 10
                        },
                        TimerYOffset = {
                            name = "Timer Y Offset",
                            type = "range", min = -100, max = 100, step = 0.5,
                            set = function(_, val) db.profile.TimerYOffset = val; TotemRecall:UpdateLayout() end,
                            get = function() return db.profile.TimerYOffset end,
                            order =11
                        },
                    },
                },
            }
        },
    }
}

local function ModifyTotemButton(btn)
    -- MASQUE INTEGRATION
    if db.profile.useMasque and TotemRecall.MasqueGroup and not btn.__MasqueAdded then
        TotemRecall.MasqueGroup:AddButton(btn, {
            Icon = btn.Icon.Texture,
            Cooldown = btn.Icon.Cooldown,
        })
        btn.__MasqueAdded = true
    end

    -- SQUARE MASK LOGIC + Masque check
    local isMasqueEnabled = db.profile.useMasque and TotemRecall.MasqueGroup

    if db.profile.UseSquareMask then
        btn.Border:Hide()
        if squareAtlas then
            btn.Icon.TextureMask:SetTexture(squareAtlas.file or squareAtlas.filename)
            btn.Icon.TextureMask:SetTexCoord(squareAtlas.leftTexCoord, squareAtlas.rightTexCoord, squareAtlas.topTexCoord, squareAtlas.bottomTexCoord)
            if btn.Icon.Cooldown then
                btn.Icon.Cooldown:SetSwipeTexture(squareAtlas.file or squareAtlas.filename)
                btn.Icon.Cooldown:SetTexCoordRange({x=squareAtlas.leftTexCoord, y=squareAtlas.topTexCoord}, {x=squareAtlas.rightTexCoord, y=squareAtlas.bottomTexCoord})
            end
        end
    else
        btn.Border:SetShown(not isMasqueEnabled)
    end
end

local dummyButtons = {}

function TotemRecall:UpdateLayout()
    local parent = _G[db.profile.ParentFrameName]

    -- Fallback to UIParent if the chosen frame doesn't exist
    if not parent then
        parent = UIParent
    end

    if not TotemFrame then return end

    -- Standard Positioning
    TotemFrame:SetParent(parent)
    TotemFrame:SetFrameStrata("HIGH")
    TotemFrame:ClearAllPoints()
    TotemFrame:SetPoint(db.profile.TotemAnchor, parent, db.profile.ParentAnchor, db.profile.XOffset, db.profile.YOffset)
    TotemFrame:SetScale(db.profile.IconScale)

    -- Force Visibility for Test Mode
    if db.profile.TestMode then
        TotemFrame:SetAlpha(1)
        TotemFrame:Show()

        -- Hide existing dummies to refresh
        for _, btn in ipairs(dummyButtons) do btn:Hide() end

        for i = 1, db.profile.TestCount do
            if not dummyButtons[i] then
                local btn = CreateFrame("Button", "TotemRecallDummy"..i, TotemFrame, "TotemButtonTemplate")
                btn:SetFrameStrata("HIGH")
                btn:SetFrameLevel(100)
                btn:EnableMouse(false)
                btn:SetScript("OnLeave", nil)
                local icon = btn.Icon or btn.icon
                if icon then
                    local tex = icon.Texture or icon
                    if tex and tex.SetTexture then
                        tex:SetTexture("Interface\\Icons\\Spell_Nature_StoneSkinTotem")
                        tex:ClearAllPoints()
                        tex:SetAllPoints(icon)
                    end
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                    btn.Icon = icon
                end

                if btn.Duration then
                    btn.Duration:SetText("")
                    btn.Duration:Show()
                end

                dummyButtons[i] = btn
            end
            dummyButtons[i]:Show()
            ModifyTotemButton(dummyButtons[i])
        end
    else
        -- Hide dummies when test mode is off
        for _, btn in ipairs(dummyButtons) do btn:Hide() end
    end

    -- Positioning Logic
    local direction = db.profile.GrowthDirection
    local spacing = db.profile.IconSpacing
    local activeTotems = {}

    for _, child in ipairs({ TotemFrame:GetChildren() }) do
        if child:IsShown() and child.Icon and child:GetObjectType() == "Button" then
            table.insert(activeTotems, child)
        end
    end

    -- If no real totems, use dummies
    if #activeTotems == 0 and db.profile.TestMode then
        for i = 1, db.profile.TestCount do
            if dummyButtons[i] then table.insert(activeTotems, dummyButtons[i]) end
        end
    end

-- Position all buttons
    for i, btn in ipairs(activeTotems) do
        btn:ClearAllPoints()
        if i == 1 then
            -- Check if we are using dummies (Test Mode with no real totems)
            local yOffset = 0
            if db.profile.TestMode and #activeTotems == db.profile.TestCount then
                yOffset = -1 -- Nudge dummies down 1px to match real totem alignment
            end

            btn:SetPoint("CENTER", TotemFrame, "CENTER", 0, yOffset)
        else
            local prev = activeTotems[i-1]
            if direction == "RIGHT" then btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
            elseif direction == "LEFT" then btn:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
            elseif direction == "UP" then btn:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
            elseif direction == "DOWN" then btn:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
            end
        end

        ModifyTotemButton(btn)
    end
    if db.profile.useMasque and TotemRecall.MasqueGroup then
        TotemRecall.MasqueGroup:ReSkin()
    end
    for _, btn in ipairs(activeTotems) do
        if btn.Duration then
            local fontPath = LSM:Fetch("font", db.profile.FontHeader)
            btn.Duration:SetDrawLayer("OVERLAY", 7)
            btn.Duration:SetFont(fontPath, db.profile.FontSize, db.profile.FontOutline)
            btn.Duration:ClearAllPoints()
            btn.Duration:SetPoint("CENTER", btn, "CENTER",
                db.profile.TimerXOffset,
                db.profile.TimerYOffset
            )
        end
    end
end

function TotemRecall:OnInitialize()
    -- Initialize DB with Profiles
    self.db = LibStub("AceDB-3.0"):New("MyTotemDB", defaults, true)
    db = self.db
    -- Make sure Test mode is disabled on login
    db.profile.TestMode = false

    if testModeTicker then
        testModeTicker:Cancel()
        testModeTicker = nil
    end

    if db.profile.useMasque then
        local MQ = LibStub("Masque", true)
        if MQ then
            self.MasqueGroup = MQ:Group("TotemRecall")
        end
    end
    -- Tell the DB to refresh the UI whenever the profile changes
    local function RefreshEverything()
        db.profile.TestMode = false
        TotemRecall:UpdateLayout()
        if TotemRecall.MasqueGroup then
            TotemRecall.MasqueGroup:ReSkin()
        end
    end

    self.db.RegisterCallback(self, "OnProfileChanged", RefreshEverything)
    self.db.RegisterCallback(self, "OnProfileCopied", RefreshEverything)
    self.db.RegisterCallback(self, "OnProfileReset", RefreshEverything)

    -- Setup Options
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("TotemRecall", options)

    local category, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("TotemRecall", "TotemRecall")

    -- Function to handle opening the menu with a combat check
    local function OpenMenu()
        if InCombatLockdown() then
            print("|cFFFF0000TotemRecall:|r Options are disabled during combat.")
            return
        end
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(categoryID)
        end
    end

    self:RegisterChatCommand("tr", OpenMenu)
    self:RegisterChatCommand("totemrecall", OpenMenu)

    if _G["TotemButtonMixin"] then
        hooksecurefunc(TotemButtonMixin, "OnLoad", ModifyTotemButton)
    end

    -- Hook to ensure spacing is remembered when new totems are cast
    if TotemFrame then
        hooksecurefunc(TotemFrame, "Update", function()
            self:UpdateLayout()
        end)

        TotemFrame:HookScript("OnShow", function()
            self:UpdateLayout()
        end)
    end

    C_Timer.After(1, function() self:UpdateLayout() end)
end
