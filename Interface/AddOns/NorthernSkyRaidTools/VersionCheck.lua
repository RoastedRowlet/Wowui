local _, NSI = ... -- Internal namespace

function NSI:RequestVersionNumber(type, name, encID, diffID)
    if (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or NSRT.Settings["Debug"]) then
        local unit, ver, url, ignore = self:GetVersionNumber(type, name, "player", encID, diffID)
        local requestID = type == "Encounter Alert" and GetTime() or nil
        self.VersionCheckData = {version = ver, type = type, name = name, url = url, lastclick = {}, requestID = requestID}
        self:VersionResponse({name = UnitName("player"), version = "No Response", ignoreCheck = ignore})
        self:Broadcast("NSI_VERSION_REQUEST", "RAID", type, name, encID, diffID, requestID)
        for unit in self:IterateGroupMembers() do
            if UnitInRaid(unit) and not UnitIsUnit("player", unit) then
                local index = UnitInRaid(unit)
                local response = select(8, GetRaidRosterInfo(index)) and "No Response" or "Offline"
                self:VersionResponse({name = UnitName(unit), version = response, ignoreCheck = false})
            end
        end
        return {name = UnitName("player"), version = ver, ignoreCheck = ignore}, url
    end
end
function NSI:VersionResponse(data)
    if self.NSUI and self.NSUI.version_scrollbox then
        self.NSUI.version_scrollbox:AddData(data)
    end
end


function NSI:GetVersionNumber(type, name, unit, encID, diffID)
    local ignoreCheck = false
    for u in self:IterateGroupMembers() do
       if C_FriendList.IsIgnored(u) then
            ignoreCheck = true
            break
       end
    end
    if type == "Addon" then
        local ver = C_AddOns.GetAddOnMetadata(name, "Version") or "Addon Missing"
        if ver ~= "Addon Missing" then
            ver = C_AddOns.IsAddOnLoaded(name) and ver or "Addon not enabled"
        end
        return unit, ver, "", ignoreCheck
    elseif type == "Note" then
        local note = self:GetNote()
        local hashed
        if C_AddOns.IsAddOnLoaded("MRT") then
            hashed = self:GetHash(note) or "Note Missing"
        else
            hashed = C_AddOns.GetAddOnMetadata("MRT", "Version") and "MRT not enabled" or "MRT not installed"
        end

        return unit, hashed, "", ignoreCheck
    elseif type == "Reminder" then
        local reminder = self.Reminder and self.Reminder ~= "" and self:GetHash(self.Reminder) or "Reminder Missing"
        return unit, reminder, "", ignoreCheck
    elseif type == "Encounter Alert" then
        local alerts = NSRT.EncounterAlerts[encID] and NSRT.EncounterAlerts[encID][diffID]
        if alerts then
            for alertKey, alert in pairs(alerts) do
                if (alert.internalID or alertKey) == name then
                    return unit, alert.enabled and "Enabled" or "Disabled", "", ignoreCheck
                end
            end
        end
        return unit, "Alert Missing", "", ignoreCheck
    end
end
