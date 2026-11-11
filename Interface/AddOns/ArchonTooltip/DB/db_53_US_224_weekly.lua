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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Monk-Brewmaster','Warrior-Fury','Hunter-BeastMastery','Druid-Balance','Paladin-Holy','Warlock-Demonology','Paladin-Protection','Warrior-Arms','Unknown-Unknown','Mage-Arcane','Mage-Frost','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','Druid-Guardian','Monk-Mistweaver','DeathKnight-Blood',}
local provider = {region='US',realm='Tortheldrin',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abandone:BAAANQAECgMIAwAAAA==.',
Ad='Adonis:BAABNQAECn82AAIBAAoKGglfnQB9AQABAAoKGglfnQB9AQAAAA==.',
Al='Althea:BAAANQAECgEIAQAAAA==.Altreyuzz:BAABNQAECn8YAAICAAcKSwSdWACsAAACAAcKSwSdWACsAAAAAA==.',
An='Anastarya:BAAANQAECgUICAAAAA==.Angery:BAAANQAECgYIBgAAAA==.Anmor:BAAANQAECgIIAgABNQAFFAQIDQABAJgRAA==.Antidemon:BAAANQAECgYIDAAAAA==.',
Ar='Arkazul:BAAANQAECgEIAwAAAA==.',
As='Astrozerg:BAAANQAECgcJCgABNQAFFAcIFwADANAmAA==.',
Az='Azeroth:BAAANQAECgEIAgAAAA==.',
Be='Bedeviled:BAAANQAECgEIAQAAAA==.',
Bl='Blòódhoof:BAAANQAECgEIAQAAAA==.',
Br='Brutalspasm:BAAANQAECgEIAQABNQAECgoKKQAEALYZAA==.',
Bu='Bubble:BAABNQAECn83AAIBAAoKtxxuTQCsAgABAAoKtxxuTQCsAgAAAA==.',
Ca='Cake:BAAANQADCggIEAAAAA==.Cassidin:BAACNQAFFH8NAAIBAAQKmBFQFADXAAABAAQKmBFQFADXAAA1AAQKfyoAAgEACgpxH9swAJECAAEACgpxH9swAJECAAAA.',
Ch='Charpette:BAAANQADCgEIAQAAAA==.Chooch:BAABNQAECn8gAAICAAoK/xeXHwD6AQACAAoK/xeXHwD6AQAAAA==.',
Ci='Cidril:BAABNQAECn8VAAIBAAgKhxTZswC3AQABAAgKhxTZswC3AQAAAA==.',
Cl='Clover:BAABNQAECn8gAAIFAAkKcBjhRwCUAgAFAAkKcBjhRwCUAgAAAA==.',
Co='Convoké:BAABNQAECn8kAAIGAAkKTR4dGAAHAwAGAAkKTR4dGAAHAwABNQAFFAMIEAABABYiAA==.',
Cr='Creating:BAABNQAECn83AAIBAAoKUhm8SgA6AgABAAoKUhm8SgA6AgAAAA==.',
De='Deathslip:BAAANQAECgYIDAAAAA==.Desp:BAAANQADCgcIBwAAAA==.',
Do='Donut:BAAANQAECggIDgAAAA==.Doobiesnibs:BAAANQAECggICAAAAA==.',
Dr='Drogyn:BAAANQADCgQIBQAAAA==.',
Du='Dudu:BAAANQAECggICAAAAA==.',
Ea='Earthsongs:BAAANQAECgQIBAABNQAFFAMIBQAHAFMLAA==.',
Em='Emryss:BAAANQADCgMIAwAAAA==.',
Er='Eris:BAABNQAECn86AAIIAAoKGyJ9CAAfAwAIAAoKGyJ9CAAfAwAAAA==.',
Ex='Exile:BAAANQADCgcIDgAAAA==.',
Fa='False:BAAANQAECgIIBQABNQAFFAUIDAACAEIaAA==.',
Fe='Feardis:BAAANQADCgUIBQAAAA==.',
Fr='Friendbot:BAAANQAECgYIDQAAAA==.',
Gi='Gihon:BAAANQAECgQIBgAAAA==.',
Gr='Groinwood:BAAANQAECgIIAgABNQAECgoKKQAEALYZAA==.',
Ha='Hairybuttlip:BAAANQABCgEIAQAAAA==.',
Ir='Ironheart:BAABNQAECn8wAAMBAAoKcRZpdADSAQABAAoK1BNpdADSAQAJAAQK6SGgNgAzAQAAAA==.',
Ja='Jackmerious:BAAANQABCgMIBgAAAA==.Jasnah:BAABNQAECn83AAIKAAkKCBecZgC3AQAKAAkKCBecZgC3AQAAAA==.',
Ka='Kaggar:BAAANQAECgIIAwABNQAFFAMIEAABABYiAA==.',
Ke='Keytosuccess:BAAANQADCgIIAgABNQAECgYIDAALAAAAAA==.',
Kh='Khruul:BAAANQADCgMIAwAAAA==.',
Ki='Killwhat:BAABNQAECn87AAMMAAoKrR/aLgB5AgAMAAoK6B7aLgB5AgANAAcKQhU3EwBBAQAAAA==.',
Ku='Kut:BAAANQAECggIBwAAAA==.',
La='Large:BAACNQAFFH8MAAMOAAUK6hHWFwA1AQAOAAQKtBLWFwA1AQAPAAMKvg8iEADOAAA1AAQKfx8ABA8ACgpMGXwfAEACAA8ACQoxGHwfAEACAA4ACQqYGGpXABwCABAAAgrFESkeAG8AAAAA.',
Me='Merkules:BAAANQADCgcIBwAAAA==.',
Mo='Moxie:BAACNQAFFH8QAAMOAAUK2R0LDQC7AQAOAAUK2R0LDQC7AQAQAAEK8wyHBABAAAA1AAQKfycABBAACgpMIrgBACYDABAACApAJbgBACYDAA4ACgpQGks6AIACAA8AAQoAACt1ADwAAAAA.',
Ms='Msdranderson:BAAANQAECgcICwAAAA==.',
Na='Natureheart:BAAANQAECgEIAQAAAA==.',
Ne='Nero:BAAANQAECgEIBAABNQAECgkJFwARADsVAA==.',
No='Nomadd:BAABNQAECn8pAAQEAAoKthkrCABpAgAEAAkKoxsrCABpAgAKAAMK4Al6IgGVAAASAAIK4REsMgBoAAAAAA==.Nori:BAAANQADCgMIAwABNQAFFAgILQAMAJ4lAA==.',
On='Onatoe:BAAANQAECgEIAwAAAA==.',
Oo='Oo:BAAANQADCgUIBwAAAA==.',
Op='Opulence:BAAANQAECgEIAQABNQAECgoKKQAEALYZAA==.',
Oz='Ozmenik:BAAANQAECgIIAgAAAA==.',
Pi='Pinksocks:BAAANQAECgMIAwAAAA==.',
Pr='Probem:BAAANQAECgEIAgAAAA==.',
Pu='Purple:BAABNQAECn8uAAIBAAoKdBpzXACDAgABAAoKdBpzXACDAgAAAA==.',
Re='Reidanduin:BAAANQAECgcICAABNQAFFAYIFAABAJkTAA==.Renbre:BAAANQAECgQIEgAAAA==.',
Ru='Rukar:BAAANQAECgQICwABNQAFFAMIEAABABYiAA==.',
Ry='Rynsker:BAABNQAECn8lAAIKAAoKEBU0bwBFAgAKAAoKEBU0bwBFAgAAAA==.',
Sa='Sabra:BAAANQAECgEIAgAAAA==.',
Sh='Shazam:BAAANQADCgQIBAABNQAECgoKOwAMAK0fAA==.',
Si='Sinoda:BAAANQAECgEIAQAAAA==.',
Te='Tetsue:BAAANQADCgIJAgAAAA==.',
Th='Thrillkiller:BAAANQADCggIAgAAAA==.',
To='Tonantzin:BAAANQADCgYICwABNQAECgkJFwARADsVAA==.',
Tu='Tubbs:BAABNQAECn8WAAITAAgKDBzQDgB3AgATAAgKDBzQDgB3AgAAAA==.',
Ty='Tyme:BAAANQAECgEIAQABNQAECgoKKQAEALYZAA==.',
Uu='Uu:BAAANQADCggJCAAAAA==.',
Va='Vansftw:BAAANQADCgcIBwAAAA==.',
Ve='Vestrevus:BAAANQADCgYICgAAAA==.',
Vi='Violetta:BAABNQAECn8VAAIUAAgKPxutEgBSAgAUAAgKPxutEgBSAgABNQAECgUICAALAAAAAA==.',
Vl='Vladilena:BAABNQAECn8XAAIRAAkKOxXORAAGAgARAAkKOxXORAAGAgAAAA==.',
Vo='Volis:BAABNQAFFH8GAAIVAAUKOAlvFgD7AAAVAAUKOAlvFgD7AAABNQAFFAcIFwADANAmAA==.Vorcthal:BAABNQAECn9EAAMQAAoKHiM4AgAEAwAOAAkKFyAyEABJAwAQAAkK0CA4AgAEAwAAAA==.Vorenormu:BAAANQADCgIIAgABNQAECgoKRAAQAB4jAA==.',
Wa='Waste:BAAANQADCgQIBAAAAA==.',
Xy='Xyla:BAAANQAECgQIBAAAAA==.',
Za='Zandros:BAABNQAECn8eAAIBAAoKJhR0XgAGAgABAAoKJhR0XgAGAgAAAA==.Zantt:BAAANQAECgQIBAAAAA==.',
Ze='Zelix:BAABNQAECn8iAAIFAAoKgAgicADFAQAFAAoKgAgicADFAQAAAA==.',
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
