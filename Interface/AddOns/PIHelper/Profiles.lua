--[[
	Shareable PI Helper settings. Export/import a string that copies every
	saved option except identity lists, UI chrome, and live PI lock state.
]]

local ADDON_NAME, addon = ...

local FORMAT_VERSION = 1
local PREFIX = "!PIH:" .. FORMAT_VERSION .. "!"
local WRAP_AT = 72

local SKIP = {
	whisperNames = true,
	sequenceNames = true,
	trackNames = true,
	trackingCollapsed = true,
	cooldownCollapsed = true,
	optionsScale = true,
	minimapAngle = true,
	version = true,
}

local GLOW_STYLES = {
	pixel = true,
	starburst = true,
	border = true,
	countdown = true,
	fill = true,
}

local function DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = DeepCopy(child)
	end
	return out
end

local function RestoreNumericKeys(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local converted = {}
	local changed = false
	for key, value in pairs(tbl) do
		local destKey = key
		if type(key) == "string" then
			local asNumber = tonumber(key)
			if asNumber and tostring(asNumber) == key then
				destKey = asNumber
				changed = true
			end
		end
		if type(value) == "table" then
			converted[destKey] = RestoreNumericKeys(value)
		else
			converted[destKey] = value
		end
	end
	if changed then
		return converted
	end
	return tbl
end

local function SnapshotSettings()
	local db = addon.db
	if type(db) ~= "table" then
		return nil, "settings are not loaded."
	end
	local defaults = addon.DEFAULTS
	local data = {}
	for key, default in pairs(defaults) do
		if not SKIP[key] then
			local value = db[key]
			if value == nil then
				value = default
			end
			data[key] = DeepCopy(value)
		end
	end
	return data
end

local function FillMissingSpellEnabled(db)
	local enabled = db.spellEnabled
	if type(enabled) ~= "table" then
		db.spellEnabled = {}
		enabled = db.spellEnabled
	end
	local spells = addon.DEFAULT_SPELLS
	for i = 1, #spells do
		local spell = spells[i]
		local spellID = spell.spellID
		if enabled[spellID] == nil then
			enabled[spellID] = spell.isPotion ~= true
		end
	end
end

local function SanitizeCustomSpells(db)
	local list = db.customSpells
	if type(list) ~= "table" then
		db.customSpells = {}
		return
	end
	local clean = {}
	for i = 1, #list do
		local entry = list[i]
		if type(entry) == "table" then
			local spellID = entry.spellID
			if type(spellID) == "string" then
				spellID = tonumber(spellID)
			end
			if type(spellID) == "number" then
				clean[#clean + 1] = {
					spellID = spellID,
					enabled = entry.enabled ~= false,
				}
			end
		end
	end
	db.customSpells = clean
end

local function ClampNumber(value, minV, maxV, fallback)
	if type(value) ~= "number" then
		return fallback
	end
	if value < minV then
		return minV
	end
	if value > maxV then
		return maxV
	end
	return value
end

local function SanitizeImported(db)
	if type(db.spellEnabled) ~= "table" then
		db.spellEnabled = {}
	else
		db.spellEnabled = RestoreNumericKeys(db.spellEnabled)
	end
	if type(db.spellScope) ~= "table" then
		db.spellScope = {}
	else
		db.spellScope = RestoreNumericKeys(db.spellScope)
	end
	SanitizeCustomSpells(db)
	if db.spellEnabled[1276166] == nil and db.spellEnabled[1276767] ~= nil then
		db.spellEnabled[1276166] = db.spellEnabled[1276767]
	end
	if db.spellScope[1276166] == nil and db.spellScope[1276767] ~= nil then
		db.spellScope[1276166] = db.spellScope[1276767]
	end
	db.spellEnabled[1276767] = nil
	db.spellScope[1276767] = nil
	FillMissingSpellEnabled(db)

	if not GLOW_STYLES[db.glowStyle] then
		db.glowStyle = "pixel"
	end
	db.glowThickness = ClampNumber(db.glowThickness, 1, 6, 2)
	db.glowSpeed = ClampNumber(db.glowSpeed, 0.05, 5, 1.5)
	db.glowPixelLines = math.floor(ClampNumber(db.glowPixelLines, 4, 16, 10) + 0.5)
	db.glowPixelLength = math.floor(ClampNumber(db.glowPixelLength, 4, 36, 20) + 0.5)
	if db.glowBorderPulse == nil then
		db.glowBorderPulse = true
	end
	if db.alertGlowStyle ~= "none" and db.alertGlowStyle ~= "starburst" then
		db.alertGlowStyle = "starburst"
	end
	if db.alertLayout ~= "overlay" and db.alertLayout ~= "left" and db.alertLayout ~= "right" and db.alertLayout ~= "none" then
		db.alertLayout = "overlay"
	end
	if db.whisperMode ~= "listed" and db.whisperMode ~= "sequence" then
		db.whisperMode = db.whisperSequence and "sequence" or "listed"
	end
	db.whisperSequence = db.whisperMode == "sequence"
	if db.trackRaidMode ~= "listed" then
		db.trackRaidMode = "all"
	end
	if db.trackPartyMode ~= "listed" then
		db.trackPartyMode = "all"
	end
	db.piGrace = ClampNumber(db.piGrace, 0, 15, 0)
	db.alertIconSize = math.floor(ClampNumber(db.alertIconSize, 32, 128, 64) + 0.5)
	db.alertTextSize = math.floor(ClampNumber(db.alertTextSize, 10, 32, 16) + 0.5)
	local anchors = {
		center = true,
		top = true,
		bottom = true,
		left = true,
		right = true,
		topleft = true,
		topright = true,
		bottomleft = true,
		bottomright = true,
	}
	if db.durationHost ~= "alert" and db.durationHost ~= "both" then
		db.durationHost = "frame"
	end
	if not anchors[db.durationAnchor] then
		db.durationAnchor = "center"
	end
	db.durationSize = math.floor(ClampNumber(db.durationSize, 8, 32, 12) + 0.5)
	db.durationX = math.floor(ClampNumber(db.durationX, -40, 40, 0) + 0.5)
	db.durationY = math.floor(ClampNumber(db.durationY, -40, 40, 0) + 0.5)
	local countdownAnchors = {
		top = true,
		center = true,
		bottom = true,
	}
	if db.countdownAnchor == "topleft" or db.countdownAnchor == "topright" then
		db.countdownAnchor = "top"
	elseif db.countdownAnchor == "bottomleft" or db.countdownAnchor == "bottomright" then
		db.countdownAnchor = "bottom"
	elseif db.countdownAnchor == "left" or db.countdownAnchor == "right" then
		db.countdownAnchor = "center"
	end
	if not countdownAnchors[db.countdownAnchor] then
		db.countdownAnchor = "top"
	end
	db.countdownHeight = math.floor(ClampNumber(db.countdownHeight, 0, 40, 0) + 0.5)
	db.countdownX = math.floor(ClampNumber(db.countdownX, -40, 40, 0) + 0.5)
	db.countdownY = math.floor(ClampNumber(db.countdownY, -40, 40, 0) + 0.5)
	db.durationRaid = db.durationRaid == true
	db.durationParty = db.durationParty == true
	db.raidSound = db.raidSound == true
	db.partySound = db.partySound == true
	if type(db.durationFont) ~= "string" or db.durationFont == "" then
		db.durationFont = "default"
	end
	db.durationR = ClampNumber(db.durationR, 0, 1, 1)
	db.durationG = ClampNumber(db.durationG, 0, 1, 1)
	db.durationB = ClampNumber(db.durationB, 0, 1, 1)
	db.durationA = ClampNumber(db.durationA, 0.05, 1, 1)
	if addon.NormalizeContextWatch then
		addon.NormalizeContextWatch(db)
	end
	if addon.SyncAlertSource then
		addon.SyncAlertSource()
	end
end

local function ApplySnapshot(data)
	local db = addon.db
	local defaults = addon.DEFAULTS
	for key, default in pairs(defaults) do
		if not SKIP[key] and data[key] ~= nil then
			local value = data[key]
			if type(default) == "table" then
				if type(value) == "table" then
					db[key] = DeepCopy(value)
				end
			elseif type(value) == type(default) then
				db[key] = value
			end
		end
	end
	SanitizeImported(db)
end

local function ListedNamesWarning(db)
	if db.trackRaidMode ~= "listed" and db.trackPartyMode ~= "listed" then
		return nil
	end
	local names = db.trackNames
	if type(names) == "table" and #names > 0 then
		return nil
	end
	return "Listed player tracking is on, but your tracked players list is empty."
end

local function WrapLines(text)
	local parts = {}
	for i = 1, #text, WRAP_AT do
		parts[#parts + 1] = text:sub(i, i + WRAP_AT - 1)
	end
	return table.concat(parts, "\n")
end

local function EncodePayload(payload)
	local enc = C_EncodingUtil
	if type(enc) ~= "table" then
		return nil, "this client cannot encode profiles."
	end
	local binary
	if enc.SerializeCBOR then
		local ok, result = pcall(enc.SerializeCBOR, payload)
		if ok and type(result) == "string" and result ~= "" then
			binary = result
		end
	end
	if not binary and enc.SerializeJSON then
		local ok, result = pcall(enc.SerializeJSON, payload)
		if ok and type(result) == "string" and result ~= "" then
			binary = result
		end
	end
	if not binary then
		return nil, "this client cannot encode profiles."
	end
	local packed = binary
	if enc.CompressDeflate then
		local ok, result = pcall(enc.CompressDeflate, binary)
		if ok and type(result) == "string" and result ~= "" then
			packed = result
		end
	end
	if not enc.EncodeBase64 then
		return nil, "this client cannot encode profiles."
	end
	local ok, encoded = pcall(enc.EncodeBase64, packed)
	if not ok or type(encoded) ~= "string" or encoded == "" then
		return nil, "could not encode this profile."
	end
	return PREFIX .. "\n" .. WrapLines(encoded)
end

local function DecodePayload(text)
	if type(text) ~= "string" then
		return nil, "paste a PI Helper profile string."
	end
	local compact = text:gsub("%s+", "")
	if compact == "" then
		return nil, "paste a PI Helper profile string."
	end
	local version, body = compact:match("^!PIH:(%d+)!(.+)$")
	if not version or not body then
		return nil, "that is not a PI Helper profile string."
	end
	version = tonumber(version)
	if not version then
		return nil, "that is not a PI Helper profile string."
	end
	if version > FORMAT_VERSION then
		return nil, "this profile needs a newer PI Helper."
	end
	if version < 1 then
		return nil, "that profile string is not supported."
	end
	local enc = C_EncodingUtil
	if type(enc) ~= "table" or not enc.DecodeBase64 then
		return nil, "this client cannot read profiles."
	end
	local ok, packed = pcall(enc.DecodeBase64, body)
	if not ok or type(packed) ~= "string" or packed == "" then
		return nil, "could not read this profile string."
	end
	local blob = packed
	if enc.DecompressDeflate then
		local decoded, result = pcall(enc.DecompressDeflate, packed)
		if decoded and type(result) == "string" and result ~= "" then
			blob = result
		end
	end
	local payload
	if enc.DeserializeCBOR then
		local parsed, result = pcall(enc.DeserializeCBOR, blob)
		if parsed and type(result) == "table" then
			payload = result
		end
	end
	if not payload and enc.DeserializeJSON then
		local parsed, result = pcall(enc.DeserializeJSON, blob)
		if parsed and type(result) == "table" then
			payload = result
		end
	end
	if type(payload) ~= "table" then
		return nil, "could not read this profile string."
	end
	if payload.addon ~= nil and payload.addon ~= "PIH" then
		return nil, "that is not a PI Helper profile string."
	end
	if type(payload.data) ~= "table" then
		return nil, "could not read this profile string."
	end
	return payload.data
end

function addon.ExportProfile()
	local data, err = SnapshotSettings()
	if not data then
		return nil, err
	end
	return EncodePayload({
		v = FORMAT_VERSION,
		addon = "PIH",
		data = data,
	})
end

function addon.ImportProfile(text)
	local data, err = DecodePayload(text)
	if not data then
		return false, err
	end
	if type(addon.db) ~= "table" then
		return false, "settings are not loaded."
	end
	ApplySnapshot(data)
	if addon.ApplySettings then
		addon.ApplySettings()
	end
	if addon.RefreshOptionsAfterImport then
		addon.RefreshOptionsAfterImport()
	end
	return true, nil, ListedNamesWarning(addon.db)
end
