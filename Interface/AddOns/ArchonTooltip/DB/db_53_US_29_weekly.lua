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

local lookup = {'Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','Paladin-Holy','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Warrior-Arms','Shaman-Restoration','Evoker-Preservation','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Monk-Windwalker','Mage-Frost','Monk-Mistweaver','Monk-Brewmaster','Paladin-Protection',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=53,date='2026-10-27',data={An='Anabel:BAAANQAECgIIAQAAAA==.',
Au='Auvina:BAAANQADCgQIBAAAAA==.',
Ba='Backscratch:BAAANQADCgYIBgAAAA==.Badgirl:BAABNQAECn8aAAIBAAgKDxofZQCAAQABAAgKDxofZQCAAQAAAA==.Baggigy:BAABNQAECn8gAAQCAAcKxBWnMgBYAQACAAcKxBWnMgBYAQADAAMK7wa8rQBxAAAEAAIK2QO30gBIAAAAAA==.Balance:BAABNQAECn8cAAMFAAoKPRzgCQCiAgAFAAkK1hzgCQCiAgAGAAIKrxtyUgBZAAAAAA==.Battitude:BAAANQAECgIIAwAAAA==.',
Be='Bentpanda:BAABNQAECn8VAAIHAAgKixpjXgBbAgAHAAgKixpjXgBbAgAAAA==.',
Bl='Blarrg:BAAANQAECgUIBgABNQAECgcIIAACAMQVAA==.',
Bo='Bossfury:BAAANQAECgUIBAAAAA==.',
Bu='Bubbawubba:BAAANQAECgIIAgAAAA==.Buckangel:BAAANQAECgIIBAABNQAFFAcIBwAIAO4iAA==.',
Ca='Camarade:BAACNQAFFH8ZAAIJAAcKryE4AADkAQAJAAcKryE4AADkAQA1AAQKfzoAAgkACgpvJFoBADYDAAkACgpvJFoBADYDAAAA.Camouflage:BAABNQAECn81AAIHAAoKtSLECQCPAwAHAAoKtSLECQCPAwAAAA==.Caneangel:BAAANQAECgEIAQAAAA==.Capable:BAABNQAECn8hAAMKAAkK+RXiBACEAgAKAAkK+RXiBACEAgALAAcK/Q6EpACMAQAAAA==.',
Ch='Charvhug:BAABNQAECn8UAAIMAAcKah9AQwBIAQAMAAcKah9AQwBIAQABNQAECggIGgANAAQhAA==.Chilyn:BAABNQAECn8sAAIIAAgKAx5SHABgAgAIAAgKAx5SHABgAgAAAA==.',
Co='Corrupthell:BAAANQADCggIGAAAAA==.Cowi:BAAANQADCgMIAwABNQABCgIIAgAOAAAAAA==.',
Da='Dantte:BAAANQADCggIEgAAAA==.',
De='Deathien:BAAANQADCgcIEwAAAA==.Demir:BAACNQAFFH8HAAIBAAQK0A82HgC+AAABAAQK0A82HgC+AAA1AAQKfzsAAgEACgqWHiQ/AAcDAAEACgqWHiQ/AAcDAAAA.',
Dr='Drealius:BAAANQADCgUIBgAAAA==.',
El='Elementbaddy:BAAANQAECgEIAQAAAA==.',
Er='Eric:BAAANQADCgMJAwABNQAECgcIHAAPAOUcAA==.',
Fl='Flame:BAAANQADCgEIAQAAAA==.',
Fr='Frieren:BAABNQAECn8dAAIBAAkKfxU1nwBDAgABAAkKfxU1nwBDAgAAAA==.',
Fu='Fulgur:BAAANQADCgYICQAAAA==.Funshock:BAAANQADCggICAAAAA==.',
Ga='Garfish:BAAANQADCgYIBgAAAA==.Garnek:BAABNQAECn8sAAMMAAoKqAx+QABSAQAMAAkKlw1+QABSAQAQAAIKIgPutwBMAAAAAA==.',
Ge='Geterdone:BAAANQADCgUIBQAAAA==.',
Gi='Giovahni:BAAANQAECgEIAQAAAA==.',
Gu='Guys:BAAANQADCgQIBAAAAA==.',
Ha='Haghor:BAAANQAECgEIAQAAAA==.Hateeho:BAABNQAECn8oAAIPAAcKmw1agAATAQAPAAcKmw1agAATAQAAAA==.',
He='Hellmakerr:BAAANQAECgQIDAAAAA==.',
Hi='Hirolla:BAAANQADCggICwAAAA==.',
Ho='Hotflashes:BAAANQADCgUIDAAAAA==.',
Ir='Ironus:BAAANQADCggIEAAAAA==.',
Ja='Janaria:BAABNQAECn9BAAIPAAkKbiJ/DgDyAgAPAAkKbiJ/DgDyAgAAAA==.',
Jb='Jb:BAAANQAECgIIAgAAAA==.',
Je='Jery:BAAANQAECgQIBAAAAA==.',
Jo='Jorakmojek:BAAANQAECgUICAAAAA==.Jordanpoole:BAACNQAFFH8hAAIRAAgK0xmaAgA9AgARAAgK0xmaAgA9AgA1AAQKfykAAhEACgrWIOIEAMUCABEACgrWIOIEAMUCAAAA.Jovarix:BAAANQADCgMIAwAAAA==.Joyluka:BAABNQAECn8xAAINAAoKTySKCQArAwANAAoKTySKCQArAwAAAA==.',
Ka='Kadris:BAAANQADCgYICQAAAA==.Kalvin:BAAANQAECgQICgAAAA==.Kanari:BAABNQAECn8gAAQSAAcKERdICADBAAATAAcKZRSgYQAzAQASAAQKdxFICADBAAAUAAIK2wIacgBDAAAAAA==.',
Ke='Keanuweaves:BAAANQADCgQIAQAAAA==.Kelval:BAAANQAECgEIAQAAAA==.',
La='Lagoles:BAAANQAECggIDgABNQAFFAcIHgABACIVAA==.Lance:BAAANQAECgcIEQAAAA==.Landis:BAAANQAECgUIDgAAAA==.',
Le='Leaf:BAAANQAECgIIBAABNQAECgoKNQAHALUiAA==.',
Lo='Lockbounty:BAABNQAECn8aAAILAAkK2xoEOwCiAgALAAkK2xoEOwCiAgABNQAECgoKHAAFAD0cAA==.',
Ly='Lyledk:BAAANQAECgQIEAAAAA==.',
Ma='Macoroni:BAABNQAECn8cAAMHAAoKuhs+JAAGAwAHAAoKuhs+JAAGAwAVAAEKAADqjQAxAAAAAA==.Malkwas:BAAANQADCgYICAAAAA==.',
Mk='Mk:BAEBNQAECn8wAAIWAAkKVh72BwCWAgAWAAkKVh72BwCWAgAAAA==.',
Mo='Monsoon:BAAANQADCggICQAAAA==.Monzo:BAAANQAECgQIBAABNQAECgoKHAAFAD0cAA==.Morvayne:BAACNQAFFH8eAAMBAAcKIhX6CQBSAQABAAYKJRj6CQBSAQAXAAIKcQjnCgBUAAA1AAQKfzgAAgEACgqMISoaAJkCAAEACgqMISoaAJkCAAAA.Mozzarella:BAABNQAECn8bAAIIAAgKNxEUZwDiAQAIAAgKNxEUZwDiAQAAAA==.',
My='Myro:BAAANQAECgEJAQAAAA==.',
Ne='Nefarius:BAAANQADCggICgABNQAFFAIIBgAUAFcRAA==.',
Ni='Nightlock:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèbula:BAAANQAECgYICwAAAA==.',
Or='Orith:BAAANQAECgQICgAAAA==.',
Pa='Pandamonium:BAABNQAECn8cAAQYAAoKqhG7FQAgAgAYAAoKqhG7FQAgAgAZAAQKMgtQIwC8AAAWAAEKAABVdwAgAAAAAA==.',
Pe='Perdyblues:BAABNQAECn9GAAILAAoKRwx6PgCvAQALAAoKRwx6PgCvAQAAAA==.',
Po='Pom:BAAANQABCgIIAgAAAA==.Porkypine:BAAANQADCgcICQAAAA==.',
Pr='Priestlegend:BAAANQADCgcIBwAAAA==.',
Ps='Psymie:BAABNQAECn8cAAILAAcKJA3SdwAJAQALAAcKJA3SdwAJAQAAAA==.',
Ra='Rainootra:BAABNQAECn8cAAIFAAcKsw+PEgAHAQAFAAcKsw+PEgAHAQAAAA==.Razalghool:BAAANQAECgUIBgABNQAECggIGgANAAQhAA==.',
Se='Selitha:BAAANQADCgcIDQABNQAECggIHAABAHERAA==.',
Sh='Shockolate:BAAANQAECgIIBAAAAA==.Shoemaker:BAAANQAECgMIAwAAAA==.',
Si='Siege:BAAANQADCgcICwAAAA==.',
So='Soraya:BAAANQAECgUIBAAAAA==.',
Sr='Srrynadvance:BAAANQAECggICAABNQAFFAcIHgABACIVAA==.',
St='Stumper:BAAANQADCgYIBgAAAA==.',
Sw='Swaggasaurus:BAABNQAECn8VAAMNAAYK4xTCwwCUAQANAAYK4xTCwwCUAQAIAAEKQQ+9IgEyAAAAAA==.Swearenger:BAAANQADCgQIBAAAAA==.',
Sy='Syriena:BAAANQAECgUIDgAAAA==.',
Te='Tengoo:BAAANQAECgEIAQAAAA==.',
Th='Thewaitress:BAABNQAECn8aAAMNAAgKBCHJlQD4AQANAAgKBCHJlQD4AQAaAAQKsRLCTwCnAAAAAA==.Thylight:BAAANQADCgQIBAAAAA==.',
To='Toastcrunch:BAAANQAECgQIDwAAAA==.',
Va='Vanjalis:BAAANQAECgQIBAAAAA==.',
Vi='Viertien:BAAANQADCgYIBgAAAA==.',
Vy='Vynlor:BAAANQADCggICAAAAA==.',
Wa='Walder:BAAANQADCgIIBAAAAA==.',
Xa='Xalatath:BAAANQADCgYIBgAAAA==.',
Xo='Xoss:BAABNQAECn8WAAIQAAgKBRzOPgCcAQAQAAgKBRzOPgCcAQAAAA==.',
Ze='Zeroo:BAAANQADCgYIBgAAAA==.',
['Êl']='Êlvis:BAAANQADCgUIBQAAAA==.',
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
