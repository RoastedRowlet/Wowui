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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Mage-Frost','Druid-Balance','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Holy','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-10-06',data={As='Astaren:BAEANQAECgUICAAAAA==.',
Br='Bryl:BAECNQAFFIEPAAIBAAUKDRQ1DQBPAQWODQAABAA3AHUNAAADACcAfw0AAAIAOACpDQAABAA1ADMNAAACADQAAQAFCg0UNQ0ATwEFjg0AAAQANwB1DQAAAwAnAH8NAAACADgAqQ0AAAQANQAzDQAAAgA0ADUABAqBGAACAQAJCo8bazIAJgIAAQAJCo8bazIAJgIAAAA=.Brylic:BAECNQAFFIEHAAICAAMK9xdWBQDrAAOODQAAAwBLAHUNAAACAE0AqQ0AAAIAHwACAAMK9xdWBQDrAAOODQAAAwBLAHUNAAACAE0AqQ0AAAIAHwA1AAQKgSkAAgIACQocItIDADMDAAIACQocItIDADMDAAE1AAUUBQgPAAEADRQA.Brylicet:BAEANQADCgQIBAABNQAFFAUIDwABAA0UAA==.',
Co='Coldasfrick:BAEBNQAECoEcAAIDAAcKCiXFAwDeAgeODQAABABfAHUNAAAEAF8Afw0AAAUAYQCpDQAABQBfAFwNAAACAGEAXQ0AAAIAUwAzDQAABgBjAAMABwoKJcUDAN4CB44NAAAEAF8AdQ0AAAQAXwB/DQAABQBhAKkNAAAFAF8AXA0AAAIAYQBdDQAAAgBTADMNAAAGAGMAAAA=.Coolshirtbra:BAEANQAECgQIBAABNQAECggIIQAEANMaAA==.',
Da='Darkorin:BAEBNQAECoEoAAMFAAkKXyavAwDYAwmODQAABgBjAHUNAAAFAGMAfw0AAAUAXwCpDQAABQBjAFwNAAAEAFwAXQ0AAAQAYwBlDQAABQBjAKQNAAACAGMAMw0AAAQAYwAFAAkKXyavAwDYAwmODQAABgBjAHUNAAAFAGMAfw0AAAQAXwCpDQAABQBjAFwNAAAEAFwAXQ0AAAQAYwBlDQAABQBjAKQNAAACAGMAMw0AAAMAYwAGAAIK2hdw5QCCAAJ/DQAAAQBDADMNAAABADYAAAA=.',
Dr='Dragore:BAEBNQAECoElAAIHAAkKgCROAwCZAwmODQAABQBfAHUNAAAEAGAAfw0AAAQAVQCpDQAABQBeAFwNAAAEAGMAXQ0AAAQAXABlDQAABQBZAKQNAAAFAFoAMw0AAAEAYQAHAAkKgCROAwCZAwmODQAABQBfAHUNAAAEAGAAfw0AAAQAVQCpDQAABQBeAFwNAAAEAGMAXQ0AAAQAXABlDQAABQBZAKQNAAAFAFoAMw0AAAEAYQAAAA==.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBQAIAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBQAIAAAAAA==.Foxwu:BAEANQAECgQIBQAAAA==.',
Fr='Frickntotems:BAEANQAECgQIBQABNQAECggIHAADAAolAA==.Fries:BAECNQAFFIEWAAMJAAYKJBwQAgA0AgaODQAABQBGAHUNAAAEAFsAfw0AAAMAJACpDQAABQBZAFwNAAABAFsAMw0AAAQANAAJAAYKJBwQAgA0AgaODQAAAwBGAHUNAAAEAFsAfw0AAAMAJACpDQAABQBZAFwNAAABAFsAMw0AAAMANAAKAAIKvApBDQCfAAKODQAAAgAnADMNAAABAA8ANQAECoEjAAIJAAkKviSlBQBkAwAJAAkKviSlBQBkAwABNQAECggIDAAIAAAAAA==.',
Ga='Gardenweed:BAEANQAECgIIAgABNQAECgUICQAIAAAAAA==.',
Gu='Guthynn:BAEBNQAECoEZAAMLAAkKjCKSAQBgAwmODQAAAwBhAHUNAAADAFkAfw0AAAQAXACpDQAABQBeAFwNAAADAFoAXQ0AAAIAXABlDQAAAQA4AKQNAAADAFkAMw0AAAEAXAALAAkKjCKSAQBgAwmODQAAAwBhAHUNAAADAFkAfw0AAAQAXACpDQAABQBeAFwNAAADAFoAXQ0AAAIAXABlDQAAAQA4AKQNAAABAFkAMw0AAAEAXAAJAAEKohiygQBJAAGkDQAAAgA/AAAA.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irrogenia:BAEANQAECgYIEQAAAA==.',
Kc='Kcmndr:BAEANQAECgYICAABNQAFFAgIJQAMAB4kAA==.',
La='Lariàs:BAECNQAFFIEQAAINAAYKeiFXAABaAgaODQAAAwBgAHUNAAADAE8Afw0AAAIARQCpDQAAAwBdAFwNAAABAFQAMw0AAAQAWwANAAYKeiFXAABaAgaODQAAAwBgAHUNAAADAE8Afw0AAAIARQCpDQAAAwBdAFwNAAABAFQAMw0AAAQAWwA1AAQKgTYAAw0ACQqjI0QCAIIDAA0ACQqjI0QCAIIDAA4ABQrpAokSAXsAAAAA.',
Li='Lidariel:BAEANQADCgUICQABNQAECgkJFwAPAB0RAA==.Lidathra:BAEBNQAECoEXAAMPAAkKHREMGAAjAgmODQAAAwBCAHUNAAACAA4Afw0AAAIAJQCpDQAAAwBKAFwNAAADADYAXQ0AAAMALgBlDQAAAwAjAKQNAAABABgAMw0AAAMAJwAPAAkKHREMGAAjAgmODQAAAgBCAHUNAAACAA4Afw0AAAIAJQCpDQAAAgBKAFwNAAADADYAXQ0AAAMALgBlDQAAAwAjAKQNAAABABgAMw0AAAIAJwAQAAMK9xLzKQC3AAOODQAAAQAwAKkNAAABADwAMw0AAAEAJAAAAA==.Lidishi:BAEANQAECgQIBAABNQAECgkJFwAPAB0RAA==.Lilgup:BAECNQAFFIEJAAQPAAUKFxJUDAAiAQWODQAAAgASAHUNAAABABMAfw0AAAIAHwCpDQAAAgBWADMNAAACAEsADwAECikOVAwAIgEEjg0AAAEAEgB1DQAAAQATAH8NAAACAB8AMw0AAAIASwAQAAIK3Q1NCwCFAAKODQAAAQA0AKkNAAABABIAEQABCmYWrAoAQwABqQ0AAAEAOQA1AAQKgSIABA8ACQobG/4MAMMCAA8ACQobG/4MAMMCABAABAqRG14hACYBABEAAwqZI+YPABABAAAA.',
Lo='Lochru:BAEBNQAECoEiAAISAAkK6RvsBgDMAgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgASAAkK6RvsBgDMAgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lotide:BAEBNQAFFIENAAMTAAcKbw7qAwAiAgeODQAAAgAEAHUNAAACACoAfw0AAAIAMwCpDQAAAgAZAFwNAAACADMAXQ0AAAEATgAzDQAAAgAEABMABwpvDuoDACICB44NAAABAAQAdQ0AAAIAKgB/DQAAAgAzAKkNAAABABkAXA0AAAIAMwBdDQAAAQBOADMNAAABAAQAFAADCnsSyBUA6QADjg0AAAEAEwCpDQAAAQA/ADMNAAABADoAATUABRQFCAkADwAXEgA=.',
Mi='Migwangomage:BAECNQAFFIEGAAIMAAQKshR0HgBSAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+AAwABAqyFHQeAFIBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECoEiAAIMAAkKziYyAAAQBAAMAAkKziYyAAAQBAABNQAFFAgIBQAEAG8aAA==.Mikmilk:BAEANQAECgYIEgABNQAECggIIQAEANMaAA==.Mikronos:BAECNQAFFIEGAAIUAAMKjhP7EwD5AAOODQAAAwAtAHUNAAABACAAqQ0AAAIASAAUAAMKjhP7EwD5AAOODQAAAwAtAHUNAAABACAAqQ0AAAIASAA1AAQKgR4AAhQACQoQG98pALYCABQACQoQG98pALYCAAE1AAQKCAghAAQA0xoA.',
['Mà']='Màsterofhunt:BAEANQAECgYICwAAAA==.Màsterofwar:BAEANQAECgIIAgABNQAECgYICwAIAAAAAA==.',
Ne='Neodefender:BAECNQAFFIEFAAIGAAMKdBtIEQAKAQOODQAAAgAvAHUNAAABAFcAqQ0AAAIASwAGAAMKdBtIEQAKAQOODQAAAgAvAHUNAAABAFcAqQ0AAAIASwA1AAQKgSIAAgYACQpHIzIGAJADAAYACQpHIzIGAJADAAAA.',
Or='Orsp:BAECNQAFFIEVAAMVAAYK5RK6BgCLAQaODQAABQA+AHUNAAADADwAfw0AAAQAPgCpDQAAAwAfAFwNAAABACUAMw0AAAUAIgAVAAUKxBG6BgCLAQWODQAABAA+AHUNAAACADwAqQ0AAAEAHwBcDQAAAQAlADMNAAACACIAFgAFCroMaA8AdAEFjg0AAAEALQB1DQAAAQACAH8NAAAEAEkAqQ0AAAIAGAAzDQAAAwAQADUABAqBMwADFQAJCuEj+gIAowMAFQAJCuEj+gIAowMAFgAJCkoTVlcA7gEAAAA=.Orspp:BAEBNQAECoEcAAMVAAkKiRyPHgAlAgmODQAABgBhAHUNAAAFAGEAfw0AAAUAXQCpDQAABABdAFwNAAACACgAXQ0AAAEAPABlDQAAAgBJAKQNAAACAEEAMw0AAAEAIwAVAAYKQyCPHgAlAgaODQAABgBhAHUNAAADAGEAfw0AAAQAXQCpDQAAAgBdAFwNAAABACgAZQ0AAAIASQAWAAcK2g7xdQCBAQd1DQAAAgBSAH8NAAABACsAqQ0AAAIAHgBcDQAAAQAKAF0NAAABAC0ApA0AAAIAIwAzDQAAAQARAAE1AAUUBggVABUA5RIA.',
Pa='Pakk:BAEANQAECggIEwAAAA==.Pandotides:BAEANQAECggIDQABNQABCgIIAgAIAAAAAA==.Papadefensve:BAEANQAECgEIAQAAAA==.',
Ra='Razamon:BAEBNQAECoEXAAITAAkKARZxNgBeAgmODQAABABPAHUNAAADADsAfw0AAAMAWwCpDQAAAwBRAFwNAAACABkAXQ0AAAIAOQBlDQAAAgAdAKQNAAABAAsAMw0AAAMARgATAAkKARZxNgBeAgmODQAABABPAHUNAAADADsAfw0AAAMAWwCpDQAAAwBRAFwNAAACABkAXQ0AAAIAOQBlDQAAAgAdAKQNAAABAAsAMw0AAAMARgAAAA==.',
Re='Recurse:BAEANQADCggICAABNQAFFAYIDQAXAEkRAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAECggIHgAYANYhAA==.',
Sa='Sairal:BAEANQAECgQIBwABNQAFFAYIEAANAHohAA==.Sargala:BAEANQAECgIIAgAAAA==.',
Sc='Scootybooty:BAEANQAECgQIBQABNQAECgYIDwAIAAAAAA==.Scootypriest:BAEANQAECgYIDwAAAA==.',
Sm='Smitehaven:BAEBNQAECoEeAAIYAAgK1iGpCQDkAgiODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAGAAICtYhqQkA5AIIjg0AAAYAUwB1DQAABABZAH8NAAAEAF4AqQ0AAAQAWwBcDQAABABcAF0NAAADAFQAZQ0AAAIAUAAzDQAAAwBLAAAA.',
Tc='Tchoff:BAEANQADCgUIBQABNQAFFAcIHQAOADchAA==.',
Th='Thez:BAEANQAECgUICgABNQAECgkJIwANAJUhAA==.Thezadin:BAEANQAECgQIBAABNQAECgkJIwANAJUhAA==.Thezdin:BAEBNQAECoEjAAINAAkKlSHuAgBhAwmODQAABQBWAHUNAAAEAF8Afw0AAAQAXgCpDQAABABiAFwNAAAEAFwAXQ0AAAUAWgBlDQAAAwBRAKQNAAABADQAMw0AAAUAUQANAAkKlSHuAgBhAwmODQAABQBWAHUNAAAEAF8Afw0AAAQAXgCpDQAABABiAFwNAAAEAFwAXQ0AAAUAWgBlDQAAAwBRAKQNAAABADQAMw0AAAUAUQAAAA==.',
Ve='Velohm:BAEANQAECgMIBAAAAA==.',
Wi='Wildbless:BAECNQAFFIEZAAIYAAcKvAkTAwCqAQeODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgAzDQAABAAWABgABwq8CRMDAKoBB44NAAAGAEIAdQ0AAAQACwB/DQAABAAeAKkNAAAEACMAXA0AAAIABABdDQAAAQACADMNAAAEABYANQAECoEqAAIYAAkKch72CwC6AgAYAAkKch72CwC6AgABNQAECgQICAAIAAAAAA==.Wildkill:BAEBNQAECoEUAAIZAAcKziE5PgCLAgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAIAYwCkDQAAAwBcABkABwrOITk+AIsCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAgBjAKQNAAADAFwAATUABAoECAgACAAAAAA=.Wildshield:BAEANQAECgQICAAAAA==.',
Wr='Wrècks:BAEANQAECgYJBwABNQAECgUIBQAIAAAAAA==.Wrèckstorm:BAEBNQAECoEsAAMaAAkKnBxqBgAQAwmODQAABwBJAHUNAAAGAFkAfw0AAAYAWQCpDQAABgBFAFwNAAAFAE4AXQ0AAAUATwBlDQAAAwA5AKQNAAABADEAMw0AAAUASAAaAAkKnBxqBgAQAwmODQAABwBJAHUNAAAFAFkAfw0AAAUAWQCpDQAABQBFAFwNAAADAE4AXQ0AAAUATwBlDQAAAwA5AKQNAAABADEAMw0AAAUASAAUAAQKhRr0mgAxAQR1DQAAAQA8AH8NAAABAEcAqQ0AAAEAPgBcDQAAAgBMAAE1AAQKBQgFAAgAAAAA.',
Zo='Zoe:BAEANQAECgQICAAAAA==.Zogle:BAECNQAFFIEWAAIBAAcKIhjFAgBNAgeODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJAAzDQAAAwBYAAEABwoiGMUCAE0CB44NAAAFAE4AdQ0AAAMAHQB/DQAAAwA7AKkNAAAFAE8AXA0AAAIAPABdDQAAAQAkADMNAAADAFgANQAECoEoAAIBAAkKQyRSCABsAwABAAkKQyRSCABsAwABNQAECgQICAAIAAAAAA==.',
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
