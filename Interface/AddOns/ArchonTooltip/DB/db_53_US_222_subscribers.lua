local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Druid-Feral','Priest-Discipline','Hunter-BeastMastery','Priest-Holy','Shaman-Restoration','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Hunter-Marksmanship','DemonHunter-Havoc',}
local provider = {region='US',realm='Tichondrius',name='US',type='subscribers',zone=53,date='2026-09-08',data={Ac='Acrock:BAEBNQAECoEYAAQBAAkJLiVuBwDxAgmODQAAAwBjAHUNAAADAGIAfw0AAAMAXgCpDQAAAwBbAFwNAAADAGIAXQ0AAAMAXwBlDQAAAgBbAKQNAAABAFoAMw0AAAMAYQABAAcJzSRuBwDxAgeODQAAAgBjAH8NAAACAF4AXA0AAAIAYgBdDQAAAgBfAGUNAAACAFsApA0AAAEAWgAzDQAAAgBaAAIABgkwGzUNAO0BBo4NAAABAFEAdQ0AAAMAYgB/DQAAAQACAKkNAAADAFsAXA0AAAEAWABdDQAAAQA2AAMAAQnxJXwNAHIAATMNAAABAGEAAAA=.Acrokitten:BAEANQAFFAIIAgABNQAECgkJGQAEAK0lAA==.Acromonkx:BAEANQADCgQIBAABNQAECgkJGQAEAK0lAA==.Acrosham:BAEANQAECggICQABNQAECgkJGQAEAK0lAA==.Acroxd:BAEANQAECgQIBQABNQAECgkJGAABAC4lAA==.',
Al='Alyndrastine:BAEANQAECgUIBwAAAA==.',
An='Analcus:BAEANQAECgMIBAABNQAECgkJFwAFAKUkAA==.Angrophobe:BAEANQAECggIBQAAAA==.',
Ar='Arcaneski:BAEBNQAECoEWAAIGAAkJBBBzOQBUAgmODQAAAwA2AHUNAAADAEEAfw0AAAMALQCpDQAAAwAzAFwNAAADADAAXQ0AAAIAEgBlDQAAAgAWAKQNAAABAA4AMw0AAAIALgAGAAkJBBBzOQBUAgmODQAAAwA2AHUNAAADAEEAfw0AAAMALQCpDQAAAwAzAFwNAAADADAAXQ0AAAIAEgBlDQAAAgAWAKQNAAABAA4AMw0AAAIALgAAAA==.',
As='Ashahid:BAEANQAECgcIDwABNQAECggIDwAHAAAAAA==.',
Au='Aurtlaymor:BAEANQAFFAIIAgAAAA==.',
Ba='Babayäga:BAECNQAFFIEHAAMBAAUJEQ8RAwD9AAWODQAAAgA9AHUNAAABAA0Afw0AAAEAIwCpDQAAAgAXADMNAAABADsAAQADCVcUEQMA/QADjg0AAAIAPQB/DQAAAQAjADMNAAABADsAAgACCScH0QMAqQACdQ0AAAEADQCpDQAAAgAXADUABAqBGgADAQAJCf0g0A0AnQIAAQAICaMe0A0AnQIAAgAFCfEeaRAAxQEAAAA=.Ballthazzar:BAEANQABCgEIAQABNQAECgYICwAHAAAAAA==.Ballthazzard:BAEANQAECgYICwAAAA==.Bazoogi:BAEANQAECggIEAABNQAFFAcIDwAIAIUjAA==.',
Be='Bernisunders:BAEANQAECgUIBgABNQAECgkJGAAJAFsMAA==.',
Bi='Bigbootybrad:BAEANQAECgQIAgABNQAECgcIAQAHAAAAAA==.',
Bo='Bonaparte:BAEANQADCgUIBwABNQAECgMIAwAHAAAAAA==.Bovinemight:BAEANQADCggIFwABNQABCgIIAgAHAAAAAA==.',
Br='Brokill:BAEANQADCgIIAgABNQAECgUICQAHAAAAAA==.',
Bu='Bubble:BAEANQAECgIIAwAAAA==.Bugboss:BAEANQAECgYIBgAAAA==.Bunnygamer:BAEBNQAECoEXAAMCAAkJWyAoAwDkAgmODQAAAwBaAHUNAAACAGIAfw0AAAIAXQCpDQAAAwBjAFwNAAACAFQAXQ0AAAIAXABlDQAAAwA8AKQNAAADACcAMw0AAAMAVgACAAgJNh0oAwDkAgiODQAAAwBaAHUNAAACAGIAqQ0AAAMAYwBcDQAAAQAfAF0NAAACAFwAZQ0AAAMAPACkDQAAAwAnADMNAAADAFYAAQACCeAieG8AmAACfw0AAAIAXQBcDQAAAQBUAAE1AAUUBwgMAAoACyIA.',
Cc='Cchronie:BAEANQAECgQIBAAAAA==.',
Ch='Chillwookie:BAEANQADCgYIBgAAAA==.Churchill:BAEANQAECgMIAwAAAA==.',
Co='Corelak:BAEANQAECgQIBQABNQAECgcIDAAHAAAAAA==.',
Cr='Crackbackk:BAEANQAECggIEAAAAA==.Crdk:BAEANQADCggICAAAAA==.',
Cy='Cyts:BAEANQADCgYIBgABNQAECgkJGgAGAN8hAA==.',
Da='Dabroski:BAEANQAECgQIBAABNQAECggIAgAHAAAAAA==.Damoris:BAEANQADCggICAABNQAECgcICwAHAAAAAA==.Darkwëaver:BAEANQADCgEIAQABNQAFFAEIAQAHAAAAAA==.',
De='Deadtrew:BAEANQADCgcIBwABNQAECggIDgAHAAAAAA==.Deathdragoon:BAEANQAECgQIBAABNQAECgcIEgAHAAAAAA==.',
Do='Dontlineme:BAEANQAECgQIBQAAAA==.Doomedvision:BAEANQAECgUICAAAAA==.Downbeatx:BAEANQAECgQIBAABNQAFFAEIAQAHAAAAAA==.',
Dr='Dractuah:BAEANQADCgIIAgAAAA==.Dragundznutz:BAEBNQAECoEYAAILAAkJjRxlAwAhAwmODQAAAwBIAHUNAAADAFsAfw0AAAMAWQCpDQAAAwBdAFwNAAADAEgAXQ0AAAMAUwBlDQAAAgA1AKQNAAABABIAMw0AAAMAUgALAAkJjRxlAwAhAwmODQAAAwBIAHUNAAADAFsAfw0AAAMAWQCpDQAAAwBdAFwNAAADAEgAXQ0AAAMAUwBlDQAAAgA1AKQNAAABABIAMw0AAAMAUgAAAA==.Drakedekay:BAEANQAECgYICAAAAA==.Drstagger:BAEANQAECgcIDgAAAA==.',
Du='Durpn:BAECNQAFFIEIAAIMAAUJHx61AADfAQWODQAAAwBKAHUNAAABAFAAfw0AAAEAPACpDQAAAgBQADMNAAABAFoADAAFCR8etQAA3wEFjg0AAAMASgB1DQAAAQBQAH8NAAABADwAqQ0AAAIAUAAzDQAAAQBaADUABAqBGgACDAAJCW4l6gAAvAMADAAJCW4l6gAAvAMAAAA=.',
['Dø']='Døxy:BAEANQAECgUIBwAAAA==.',
Ea='Earrl:BAEANQAECgcIDwAAAA==.Eavvie:BAEBNQAECoEZAAIGAAkJKSH8CwBcAwmODQAAAwBbAHUNAAADAFkAfw0AAAMAQwCpDQAAAwBfAFwNAAADAFoAXQ0AAAMARgBlDQAAAgBTAKQNAAACAFQAMw0AAAMAWgAGAAkJKSH8CwBcAwmODQAAAwBbAHUNAAADAFkAfw0AAAMAQwCpDQAAAwBfAFwNAAADAFoAXQ0AAAMARgBlDQAAAgBTAKQNAAACAFQAMw0AAAMAWgAAAA==.',
Ec='Eckszugzug:BAEBNQAFFIEKAAMFAAYJehqYAABhAgaODQAAAwBjAHUNAAACAEsAfw0AAAEANwCpDQAAAQBiAFwNAAABADIAMw0AAAIAGgAFAAYJehqYAABhAgaODQAAAwBjAHUNAAACAEsAfw0AAAEANwCpDQAAAQBiAFwNAAABADIAMw0AAAEAGgANAAEJ7QEYAQBLAAEzDQAAAQAEAAAA.',
Ev='Evdh:BAEANQAECggICAABNQAECgkJGQAGACkhAA==.Evdk:BAEANQAECggICAABNQAECgkJGQAGACkhAA==.',
Fa='Falselight:BAEANQADCgQIBAABNQAECggIEAAHAAAAAA==.Fancytacos:BAEANQADCggIDgABNQAECgkJFwAFAC4kAA==.Farnesse:BAEANQADCgQIBAAAAA==.Fatherdoland:BAEANQADCgYIBgAAAA==.Fatherfauci:BAEANQAECgYIBgAAAA==.',
Fe='Felforeman:BAEANQAECgQIBAAAAA==.',
Fi='Fidèle:BAEANQAECgcIDwAAAA==.',
Fl='Flybyz:BAEBNQAECoEaAAIOAAkJOCMFAQCRAwmODQAAAwBbAHUNAAADAGEAfw0AAAMAWgCpDQAAAwBaAFwNAAADAGIAXQ0AAAMAVQBlDQAAAwBeAKQNAAACAD8AMw0AAAMAYwAOAAkJOCMFAQCRAwmODQAAAwBbAHUNAAADAGEAfw0AAAMAWgCpDQAAAwBaAFwNAAADAGIAXQ0AAAMAVQBlDQAAAwBeAKQNAAACAD8AMw0AAAMAYwAAAA==.',
Fo='Fod:BAEANQAECgcIDAABNQAECggIAgAHAAAAAA==.',
Fr='Frostietutes:BAEANQAECgUIBQAAAA==.',
Fu='Fuggmonlee:BAEANQADCggICAAAAA==.Furiousrow:BAEBNQAECoEpAAMPAAkJqiHmAQBmAwmODQAABQBXAHUNAAAFAGIAfw0AAAUAYgCpDQAABQBjAFwNAAAFAF0AXQ0AAAQANgBlDQAABABPAKQNAAADAEEAMw0AAAUAYgAPAAkJVSHmAQBmAwmODQAAAQBXAHUNAAABAGIAfw0AAAEAYgCpDQAAAQBjAFwNAAABAF0AXQ0AAAEANgBlDQAAAQBPAKQNAAACAEEAMw0AAAEAWgAQAAkJbRn8DQDDAgmODQAABAAqAHUNAAAEAFQAfw0AAAQAVgCpDQAABABXAFwNAAAEAD8AXQ0AAAMAGwBlDQAAAwA7AKQNAAABACMAMw0AAAQAYgAAAA==.',
['Fï']='Fïdele:BAEANQADCggICgABNQAECgcIDwAHAAAAAA==.',
Ga='Gaelsi:BAEANQADCggICAABNQAECgQIBwAHAAAAAA==.',
Ge='Genshiip:BAEANQAECgUIBQABNQAECgkJGAARAOggAA==.',
Go='Goonofwar:BAEANQADCggIDgABNQAECgQIBAAHAAAAAA==.Goose:BAEBNQAFFIEGAAIGAAUJyRN6AgDDAQWODQAAAgBYAHUNAAABAEsAfw0AAAEADQCpDQAAAQAsADMNAAABACAABgAFCckTegIAwwEFjg0AAAIAWAB1DQAAAQBLAH8NAAABAA0AqQ0AAAEALAAzDQAAAQAgAAAA.Gortlock:BAEANQADCgYICQAAAA==.',
Gw='Gwapp:BAEANQAECgMIAwABNQAECgkJHwASAJ0jAA==.',
Ha='Harreks:BAECNQAFFIEHAAIOAAUJGgzRAQCSAQWODQAAAgBGAHUNAAABACQAfw0AAAEADQCpDQAAAgAKADMNAAABABcADgAFCRoM0QEAkgEFjg0AAAIARgB1DQAAAQAkAH8NAAABAA0AqQ0AAAIACgAzDQAAAQAXADUABAqBGgACDgAJCeMVNgkAawIADgAJCeMVNgkAawIAAAA=.',
Ho='Hoffa:BAEBNQAECoEfAAISAAkJnSPdAADNAwmODQAABABiAHUNAAAEAGIAfw0AAAQAYQCpDQAABgBgAFwNAAADAGIAXQ0AAAMAYABlDQAAAgBhAKQNAAABACcAMw0AAAQAYgASAAkJnSPdAADNAwmODQAABABiAHUNAAAEAGIAfw0AAAQAYQCpDQAABgBgAFwNAAADAGIAXQ0AAAMAYABlDQAAAgBhAKQNAAABACcAMw0AAAQAYgAAAA==.Holybro:BAEANQAECgUICQAAAA==.',
Ic='Iconickx:BAEBNQAECoEaAAMTAAkJqyJ+AwCFAwmODQAAAwBiAHUNAAADAGAAfw0AAAMAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAMAXwBlDQAAAgBNAKQNAAADACcAMw0AAAMAXwATAAkJqyJ+AwCFAwmODQAAAwBiAHUNAAADAGAAfw0AAAMAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAMAXwBlDQAAAgBNAKQNAAACACcAMw0AAAMAXwAUAAEJdwhCGQBIAAGkDQAAAQAVAAAA.',
Iz='Izpanda:BAEANQAECgYIBgAAAA==.',
Ja='Jackmerrius:BAEBNQAECoEXAAIVAAkJDSYPAAACBAmODQAAAwBjAHUNAAADAGMAfw0AAAIAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAXwBlDQAAAgBhAKQNAAACAFoAMw0AAAMAYgAVAAkJDSYPAAACBAmODQAAAwBjAHUNAAADAGMAfw0AAAIAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAXwBlDQAAAgBhAKQNAAACAFoAMw0AAAMAYgAAAA==.Jackspaladin:BAEANQADCgEIAQABNQAECggIDgAHAAAAAA==.Jackswarrior:BAEANQAECgYICAABNQAECggIDgAHAAAAAA==.Jadefirejuri:BAEANQAECgQIBwABNQAFFAYIDAAWAMgaAA==.Jarudy:BAEANQADCggICQABNQAECgkJGQAXAKEmAA==.Jasemetadin:BAEANQAECgMIBQAAAA==.Jaygrips:BAEANQAECggIAgAAAA==.Jayw:BAEANQADCgYIBgABNQAECggIAgAHAAAAAA==.',
Jb='Jbodangle:BAEANQAECgcICwAAAA==.',
Jo='Johnpeters:BAEANQAECgYIDgAAAA==.',
Jp='Jpo:BAEBNQAECoEYAAIYAAkJFiIpBgAVAwmODQAAAwBeAHUNAAADAFsAfw0AAAMAXwCpDQAAAwBcAFwNAAADAGIAXQ0AAAMAWwBlDQAAAgBeAKQNAAACADcAMw0AAAIARgAYAAkJFiIpBgAVAwmODQAAAwBeAHUNAAADAFsAfw0AAAMAXwCpDQAAAwBcAFwNAAADAGIAXQ0AAAMAWwBlDQAAAgBeAKQNAAACADcAMw0AAAIARgAAAA==.',
Jw='Jwvoker:BAEANQAECgYIEAABNQAECggIAgAHAAAAAA==.',
Ke='Kenpachî:BAEANQAECggIEwAAAA==.Ketrew:BAEANQAECggIDgAAAA==.',
Kh='Khallexis:BAEANQAECgUICgAAAA==.Khayame:BAECNQAFFIEMAAMWAAYJyBoMAABXAgaODQAAAwBdAHUNAAACAFMAfw0AAAIAVACpDQAAAgAsAFwNAAABAB4AMw0AAAIASwAWAAYJfxgMAABXAgaODQAAAwBdAHUNAAACAFMAfw0AAAIAVACpDQAAAgAsAFwNAAABAB4AMw0AAAEAKAAYAAEJVh2oCABeAAEzDQAAAQBLADUABAqBGwADFgAJCYkhZAAAWwMAFgAJCTMgZAAAWwMAGAAGCb4daRoAHQIAAAA=.',
Ki='Kibitokai:BAEANQADCgIIAgABNQAECgcICwAHAAAAAA==.Killserenity:BAEANQAECgYIDAAAAA==.',
Kn='Knockzsham:BAECNQAFFIEJAAIZAAUJ2hvEAADyAQWODQAAAwBCAHUNAAACABsAfw0AAAEAXgCpDQAAAgBKADMNAAABAF0AGQAFCdobxAAA8gEFjg0AAAMAQgB1DQAAAgAbAH8NAAABAF4AqQ0AAAIASgAzDQAAAQBdADUABAqBGgACGQAJCegkigAA0AMAGQAJCegkigAA0AMAAAA=.',
Ko='Kovidmage:BAEANQAECgUIBAABNQAECgYIBgAHAAAAAA==.',
Kr='Kronuk:BAEANQAECggIEAAAAA==.',
Ku='Kumkwat:BAEANQAECgEIAQABNQAFFAYIDAAWAMgaAA==.',
Ky='Kylista:BAEANQAECgYICQAAAA==.',
La='Lanikiss:BAEBNQAECoEXAAIFAAkJpSRkAgDGAwmODQAAAgBhAHUNAAADAGIAfw0AAAMAWACpDQAAAwBeAFwNAAADAGAAXQ0AAAMAYQBlDQAAAgBbAKQNAAACAFMAMw0AAAIAYAAFAAkJpSRkAgDGAwmODQAAAgBhAHUNAAADAGIAfw0AAAMAWACpDQAAAwBeAFwNAAADAGAAXQ0AAAMAYQBlDQAAAgBbAKQNAAACAFMAMw0AAAIAYAAAAA==.Lanî:BAEANQAECgIIBAABNQAECgkJFwAFAKUkAA==.Lanîa:BAEANQAECgQIBAABNQAECgkJFwAFAKUkAA==.Lanîcus:BAEANQAECgIIBAABNQAECgkJFwAFAKUkAA==.Largeduck:BAEANQADCgMIAwABNQAECgkJHQAEAJogAA==.',
Le='Leoarcmage:BAEANQADCgUIBQAAAA==.',
Li='Lichardawkns:BAEANQADCgIIAwABNQAECgkJGAAJAFsMAA==.Lichie:BAECNQAFFIEIAAIIAAYJ2RpHAABAAgaODQAAAgBcAHUNAAABADgAfw0AAAEAUwCpDQAAAgBPAFwNAAABAEoAMw0AAAEAGQAIAAYJ2RpHAABAAgaODQAAAgBcAHUNAAABADgAfw0AAAEAUwCpDQAAAgBPAFwNAAABAEoAMw0AAAEAGQA1AAQKgRgAAggACQkTJrMAAOQDAAgACQkTJrMAAOQDAAAA.Lilbirch:BAEANQAECgcIDgABNQAECgUICQAHAAAAAA==.Lilgrippy:BAEANQAECgYIBgABNQAECgUICQAHAAAAAA==.',
Lo='Lofixo:BAEANQADCgIIAgABNQAECgkJHQAOACoZAA==.',
Ly='Lyeinoh:BAEANQAECgMIAwAAAA==.',
Ma='Machx:BAEANQAECgQIBAABNQAECgkJFwAaALUWAA==.Machxr:BAEBNQAECoEXAAQaAAkJtRbSAgB0AgmODQAAAwBDAHUNAAADAEsAfw0AAAMAPQCpDQAAAwBJAFwNAAADACsAXQ0AAAIAMQBlDQAAAgAfAKQNAAABACgAMw0AAAMATgAaAAgJBRjSAgB0AgiODQAAAwBDAHUNAAACAEsAfw0AAAMAPQCpDQAAAwBJAFwNAAACACsAXQ0AAAIAMQCkDQAAAQAoADMNAAADAE4AGwADCfQOqB8A0gADdQ0AAAEAQABcDQAAAQATAGUNAAABAB8AHAABCa0E/y4ASgABZQ0AAAEACwAAAA==.Malfuriousa:BAEANQADCggIEQABNQAECgYIBgAHAAAAAA==.',
Md='Mdubss:BAEANQAFFAIIAgAAAA==.',
Me='Meowcolm:BAEANQAECgMIAwABNQAECgkJFwAdAFAiAA==.',
My='Mysà:BAEANQAECgUICgAAAA==.Myza:BAEANQAECgQIBQABNQAECgUICgAHAAAAAA==.',
Na='Nastyplot:BAEANQAECgUICQAAAA==.',
Ne='Nepu:BAECNQAFFIEMAAIGAAYJxBufAABJAgaODQAAAwBdAHUNAAACADAAfw0AAAIAQwCpDQAAAgBTAFwNAAABADwAMw0AAAIASQAGAAYJxBufAABJAgaODQAAAwBdAHUNAAACADAAfw0AAAIAQwCpDQAAAgBTAFwNAAABADwAMw0AAAIASQA1AAQKgRwAAgYACQlCJjQCAMsDAAYACQlCJjQCAMsDAAAA.Neurohunt:BAEANQADCgMIAwABNQAECgkJFwAVAA0mAA==.Neuromage:BAEANQAECggICAABNQAECgkJFwAVAA0mAA==.Neuromonk:BAEANQAECgIIAgABNQAECgkJFwAVAA0mAA==.',
No='Notxyllah:BAEANQAECgYICgABNQAECgcIEQAHAAAAAA==.',
Oa='Oakleys:BAEBNQAECoEZAAIMAAkJfyYTAAAMBAmODQAAAwBjAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGIAXQ0AAAMAYwBlDQAAAgBeAKQNAAACAGEAMw0AAAMAYgAMAAkJfyYTAAAMBAmODQAAAwBjAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGIAXQ0AAAMAYwBlDQAAAgBeAKQNAAACAGEAMw0AAAMAYgAAAA==.Oaklock:BAEANQAECgMIAwABNQAECgkJGQAMAH8mAA==.',
Pa='Pandauid:BAEANQAECgcICwAAAA==.',
Pe='Pezly:BAEBNQAECoEZAAIcAAkJ6B4YAwA0AwmODQAAAwBdAHUNAAADAFMAfw0AAAMAYACpDQAAAwBdAFwNAAADAFkAXQ0AAAMASwBlDQAAAgAyAKQNAAACACEAMw0AAAMAXwAcAAkJ6B4YAwA0AwmODQAAAwBdAHUNAAADAFMAfw0AAAMAYACpDQAAAwBdAFwNAAADAFkAXQ0AAAMASwBlDQAAAgAyAKQNAAACACEAMw0AAAMAXwAAAA==.',
Pf='Pfìzer:BAEBNQAECoEWAAIYAAkJcB/BBAAzAwmODQAAAwBgAHUNAAADAFUAfw0AAAMAWwCpDQAAAwBjAFwNAAADAFQAXQ0AAAIARwBlDQAAAgBNAKQNAAABACAAMw0AAAIAVgAYAAkJcB/BBAAzAwmODQAAAwBgAHUNAAADAFUAfw0AAAMAWwCpDQAAAwBjAFwNAAADAFQAXQ0AAAIARwBlDQAAAgBNAKQNAAABACAAMw0AAAIAVgAAAA==.',
Pi='Pinkysuavo:BAEANQAECgUIBQABNQAFFAQIBwAFAIAXAA==.',
Po='Pocampo:BAEANQADCgYIBgAAAA==.Pokeymcpoke:BAEANQADCggICQABNQAECgcIEQAHAAAAAA==.Popmage:BAEANQADCgUIBQABNQAFFAYICAAdAJoSAA==.Poppydk:BAEANQAECgcIBwABNQAFFAYICAAdAJoSAA==.Popwarrior:BAEANQAECgEIAQABNQAFFAYICAAdAJoSAA==.',
Ps='Psichopathic:BAEANQADCggICAABNQAECgcIDwAHAAAAAA==.',
['Pô']='Pôpdk:BAEBNQAFFIEIAAIdAAYJmhIWAQDRAQaODQAAAQAwAHUNAAACAEQAfw0AAAEAGACpDQAAAgBZAFwNAAABACAAMw0AAAEAFgAdAAYJmhIWAQDRAQaODQAAAQAwAHUNAAACAEQAfw0AAAEAGACpDQAAAgBZAFwNAAABACAAMw0AAAEAFgAAAA==.Pôppally:BAEANQAFFAEIAQABNQAFFAYICAAdAJoSAA==.',
Ra='Ratweaver:BAEANQADCgMIAwABNQAECggIEgAHAAAAAA==.',
Ri='Rideslow:BAEANQAECgIIBAABNQAECgkJFgABAI4lAA==.Rinjdael:BAEANQADCggIDgABNQAECgUICgAHAAAAAA==.',
Ro='Rokstedi:BAEANQAECgMIAgABNQADCggIBgAHAAAAAA==.',
Ru='Rudycheck:BAEBNQAECoEZAAMXAAkJoSYwAQC5AwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAgBfAKQNAAACAGMAMw0AAAMAYgAXAAkJoSYwAQC5AwmODQAAAgBjAHUNAAACAGMAfw0AAAIAYwCpDQAAAgBjAFwNAAACAGMAXQ0AAAIAYwBlDQAAAgBfAKQNAAABAGMAMw0AAAIAYgAeAAgJaCAwBwD/AgiODQAAAQBfAHUNAAABAFQAfw0AAAEAWwCpDQAAAQBYAFwNAAABAF4AXQ0AAAEATACkDQAAAQA7ADMNAAABAEgAAAA=.Rudylight:BAEANQADCgQIBAABNQAECgkJGQAXAKEmAA==.Rudyrudyrudy:BAEANQAECgEIAgABNQAECgkJGQAXAKEmAA==.Rudyxo:BAEANQAECgMIAwABNQAECgkJGQAXAKEmAA==.Rudyxoxo:BAEANQADCgQIBAABNQAECgkJGQAXAKEmAA==.Rumpers:BAEANQAECgcIDwAAAA==.',
Sa='Sacerdotaii:BAEANQAECgEIAQABNQAECggIDwAHAAAAAA==.Sacerdotal:BAEANQAECggIDwAAAA==.',
Sc='Scruzz:BAECNQAFFIEGAAIcAAQJ1Q3FAQBjAQSODQAAAwAdAHUNAAABAEoAqQ0AAAEAIgAzDQAAAQADABwABAnVDcUBAGMBBI4NAAADAB0AdQ0AAAEASgCpDQAAAQAiADMNAAABAAMANQAECoEaAAIcAAkJcCCaAQB9AwAcAAkJcCCaAQB9AwAAAA==.',
Se='Sense:BAECNQAFFIENAAIRAAYJzyQHAAB9AgaODQAAAwBkAHUNAAACAFgAfw0AAAIAZACpDQAAAwBkAFwNAAABAEwAMw0AAAIAZAARAAYJzyQHAAB9AgaODQAAAwBkAHUNAAACAFgAfw0AAAIAZACpDQAAAwBkAFwNAAABAEwAMw0AAAIAZAA1AAQKgRsAAhEACQlBJhYAAPgDABEACQlBJhYAAPgDAAAA.',
Sk='Skullfury:BAEANQAECgMIAwABNQAECgcIEAAHAAAAAA==.Skullfurý:BAEANQAECgcIEAAAAA==.Skyes:BAEBNQAECoEYAAIEAAkJfSVJAADLAwmODQAAAwBjAHUNAAADAGAAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGEAXQ0AAAMAWwBlDQAAAgBhAKQNAAACAFIAMw0AAAIAYwAEAAkJfSVJAADLAwmODQAAAwBjAHUNAAADAGAAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGEAXQ0AAAMAWwBlDQAAAgBhAKQNAAACAFIAMw0AAAIAYwAAAA==.Skyphyr:BAEANQADCgcIBwABNQAECgkJGAAEAH0lAA==.',
Sl='Slicerwind:BAEANQAECgQIBAAAAA==.Slipbringer:BAEANQAECgEIAQABNQAECgkJFwAdAFAiAA==.Slipreaper:BAEBNQAECoEXAAIdAAkJUCKlAgCOAwmODQAAAwBhAHUNAAADAF4Afw0AAAMAXQCpDQAAAwBQAFwNAAADAFsAXQ0AAAMAWwBlDQAAAQBCAKQNAAABAEsAMw0AAAMAYwAdAAkJUCKlAgCOAwmODQAAAwBhAHUNAAADAF4Afw0AAAMAXQCpDQAAAwBQAFwNAAADAFsAXQ0AAAMAWwBlDQAAAQBCAKQNAAABAEsAMw0AAAMAYwAAAA==.',
Sm='Smazo:BAEBNQAECoEZAAMZAAkJ4Bq0DgCnAgmODQAAAwBcAHUNAAACAE8Afw0AAAIASwCpDQAAAwA9AFwNAAADAF8AXQ0AAAMANABlDQAAAwAtAKQNAAADAFEAMw0AAAMAJQAZAAkJ4Bq0DgCnAgmODQAAAwBcAHUNAAACAE8Afw0AAAIASwCpDQAAAgA9AFwNAAACAF8AXQ0AAAIANABlDQAAAgAtAKQNAAADAFEAMw0AAAMAJQAIAAQJGRbaRQA0AQSpDQAAAQBNAFwNAAABAEEAXQ0AAAEAOABlDQAAAQAbAAAA.',
Sn='Sneakysnacks:BAEANQADCggIEAABNQAFFAUICAAMAB8eAA==.',
So='Soulmana:BAEANQAECgYIDgAAAA==.',
Sp='Spacegoatst:BAEANQAECgQIBAABNQAECgkJFwAVAA0mAA==.Sparkdragoon:BAEANQADCggICAABNQAECgcIEgAHAAAAAA==.',
St='Stabassman:BAEANQADCgQIBAAAAA==.Stevncolbear:BAEANQADCgIIAgABNQAECgkJGAAJAFsMAA==.Stormlights:BAEBNQAECoEZAAISAAkJBCDVBABIAwmODQAAAwBcAHUNAAADAFsAfw0AAAMAVwCpDQAAAwBYAFwNAAADAGMAXQ0AAAMAPQBlDQAAAgBUAKQNAAACADAAMw0AAAMAUwASAAkJBCDVBABIAwmODQAAAwBcAHUNAAADAFsAfw0AAAMAVwCpDQAAAwBYAFwNAAADAGMAXQ0AAAMAPQBlDQAAAgBUAKQNAAACADAAMw0AAAMAUwAAAA==.Stormratx:BAEANQAECgYIDgAAAA==.',
Sw='Swayicus:BAEANQAECgIIAgABNQAECgkJFwAFAKUkAA==.Sweaterss:BAEANQADCgEIAgAAAA==.',
Ta='Taaurminator:BAEANQADCggIBgAAAA==.Talilen:BAEANQADCgEIAQABNQAFFAIIAgAHAAAAAA==.',
Te='Testblade:BAEANQADCggICAABNQAFFAIIAgAHAAAAAA==.Testblink:BAEANQAFFAIIAgAAAA==.Testname:BAEANQADCggICAABNQAFFAIIAgAHAAAAAA==.',
Tg='Tgb:BAEANQADCggIBwABNQAFFAEIAQAHAAAAAA==.',
Th='Thicknscaly:BAECNQAFFIEMAAMKAAcJCyIUAACBAgeODQAAAgBIAHUNAAACAGIAfw0AAAIASQCpDQAAAQBkAF0NAAACAGQAZQ0AAAEAZAAzDQAAAgBAAAoABgmnHxQAAIECBo4NAAABAEgAdQ0AAAEAYgB/DQAAAQAyAF0NAAACAGQAZQ0AAAEAZAAzDQAAAQBAAAsABQmZE5QAALIBBY4NAAABAB0AdQ0AAAEAIwB/DQAAAQBJAKkNAAABAGQAMw0AAAEACwA1AAQKgRYAAwsACQlMJtYAALADAAsACQkNJdYAALADAAoABAmKJvIDAMoBAAAA.',
Ti='Ticklemydead:BAEANQAECgYICgAAAA==.Ticklemyswrd:BAEANQAECgUIDgABNQAECgYICgAHAAAAAA==.',
Tm='Tmoneskee:BAEANQADCgYICwAAAA==.',
To='Torend:BAEANQAECggICwAAAA==.',
Un='Unbearievabl:BAEBNQAECoEYAAIGAAkJZCHsCQBuAwmODQAAAwBbAHUNAAACAGIAfw0AAAIAYgCpDQAAAwBjAFwNAAACAB4AXQ0AAAMAYQBlDQAAAwBbAKQNAAADAEcAMw0AAAMAWwAGAAkJZCHsCQBuAwmODQAAAwBbAHUNAAACAGIAfw0AAAIAYgCpDQAAAwBjAFwNAAACAB4AXQ0AAAMAYQBlDQAAAwBbAKQNAAADAEcAMw0AAAMAWwABNQAFFAcIDAAKAAsiAA==.Unholybro:BAEANQAECgQIBgABNQAECgUICQAHAAAAAA==.',
Ur='Uratuna:BAEANQADCgcIEgAAAA==.',
Va='Varbdk:BAEANQADCgEIAQAAAA==.',
Vi='Vinedragöön:BAEANQABCgMIAQABNQAECgcIEgAHAAAAAA==.Vitamiinp:BAEANQAFFAEIAQAAAA==.Vitaminndee:BAEANQADCgEIAQABNQAFFAEIAQAHAAAAAA==.',
Wa='Warrbean:BAEBNQAECoEbAAIFAAkJxiLPBQCLAwmODQAABABgAHUNAAADAGIAfw0AAAMAYgCpDQAAAwBcAFwNAAADAF8AXQ0AAAMASwBlDQAAAgBbAKQNAAACADcAMw0AAAQAYAAFAAkJxiLPBQCLAwmODQAABABgAHUNAAADAGIAfw0AAAMAYgCpDQAAAwBcAFwNAAADAF8AXQ0AAAMASwBlDQAAAgBbAKQNAAACADcAMw0AAAQAYAAAAA==.',
We='Wecontduit:BAEANQADCgIIAgABNQADCgYIBgAHAAAAAA==.Weekly:BAEANQAECgcICQABNQAECgkJHwASAJ0jAA==.Wetpissgodxo:BAECNQAFFIEHAAIFAAQJgBerAgCGAQSODQAAAwBiAHUNAAABADoAfw0AAAEAFACpDQAAAgA/AAUABAmAF6sCAIYBBI4NAAADAGIAdQ0AAAEAOgB/DQAAAQAUAKkNAAACAD8ANQAECoEeAAMFAAkJ9yESCQBfAwAFAAkJviASCQBfAwANAAMJ9CGGCAAwAQAAAA==.',
Wh='Whizzletit:BAEBNQAECoEWAAICAAkJcxo+AgAQAwmODQAAAwBcAHUNAAADAFcAfw0AAAMAYQCpDQAAAwA2AFwNAAADAFEAXQ0AAAMAVwBlDQAAAgAxAKQNAAABACIAMw0AAAEAFwACAAkJcxo+AgAQAwmODQAAAwBcAHUNAAADAFcAfw0AAAMAYQCpDQAAAwA2AFwNAAADAFEAXQ0AAAMAVwBlDQAAAgAxAKQNAAABACIAMw0AAAEAFwAAAA==.Whizzletoot:BAEANQAECgYIBgABNQAECgkJFgACAHMaAA==.',
Wi='Wildvsman:BAEANQAECgEIAQAAAA==.',
Wo='Wobblucie:BAEBNQAECoEXAAMSAAkJkh7MBQAxAwmODQAAAwBNAHUNAAADAGAAfw0AAAMAWgCpDQAAAwBSAFwNAAADAFcAXQ0AAAIAVABlDQAAAgBKAKQNAAABABMAMw0AAAMAWwASAAkJkh7MBQAxAwmODQAAAgBNAHUNAAADAGAAfw0AAAMAWgCpDQAAAwBSAFwNAAADAFcAXQ0AAAIAVABlDQAAAgBKAKQNAAABABMAMw0AAAMAWwAfAAEJYBO9NQA+AAGODQAAAQAxAAAA.',
Xc='Xcecute:BAEANQADCggIFgABNQAECgcIEQAHAAAAAA==.',
Xy='Xylla:BAEANQAECgcIEQAAAA==.Xymixalot:BAEANQADCgUIBQABNQAECgcIEQAHAAAAAA==.',
Yo='Youknowthis:BAECNQAFFIEHAAIGAAUJNBQrAgDPAQWODQAAAgA5AHUNAAABADQAfw0AAAEABQCpDQAAAgAuADMNAAABAGAABgAFCTQUKwIAzwEFjg0AAAIAOQB1DQAAAQA0AH8NAAABAAUAqQ0AAAIALgAzDQAAAQBgADUABAqBGQACBgAJCf4kQAMAuAMABgAJCf4kQAMAuAMAAAA=.',
Yu='Yuzuwu:BAEANQAECgYICQAAAA==.',
Za='Zazski:BAEANQAECgMIBAABNQAECgkJFgAGAAQQAA==.',
Zo='Zoraclefu:BAEBNQAECoEWAAIMAAkJbyN0AgBjAwmODQAAAwBgAHUNAAADAGAAfw0AAAMAYQCpDQAAAwBeAFwNAAADAFoAXQ0AAAMAWgBlDQAAAgBYAKQNAAABAE0AMw0AAAEAVAAMAAkJbyN0AgBjAwmODQAAAwBgAHUNAAADAGAAfw0AAAMAYQCpDQAAAwBeAFwNAAADAFoAXQ0AAAMAWgBlDQAAAgBYAKQNAAABAE0AMw0AAAEAVAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
