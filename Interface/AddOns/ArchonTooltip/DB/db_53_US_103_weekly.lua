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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline','Priest-Holy','Rogue-Assassination','Unknown-Unknown','Shaman-Elemental','DeathKnight-Blood','Druid-Balance','Shaman-Restoration','Priest-Shadow','Paladin-Retribution','Hunter-BeastMastery','Mage-Frost','Shaman-Enhancement','Evoker-Devastation','Warrior-Protection','DemonHunter-Devourer',}
local provider = {region='US',realm='Garithos',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Aciersilva:BAAANQAECgMIBAAAAA==.',
Ae='Aemeath:BAACNQAFFH8GAAMBAAMKpCKIEwC4AAABAAIK5iWIEwC4AAACAAEKIByNBgBUAAA1AAQKfyYAAwEACQpcJusDALIDAAEACQpcJusDALIDAAIABApKDuoeANAAAAE1AAUUCAguAAEAUiQA.',
Aj='Ajtwo:BAAANQAECgYIEQAAAA==.',
Ak='Akanbe:BAABNQAECn8iAAMDAAgKfiELAgAPAwADAAgKfiELAgAPAwAEAAIKqyD60gCnAAAAAA==.',
Al='Alucarde:BAAANQADCgcIDAAAAA==.',
An='Anniichan:BAABNQAECn8XAAMEAAgKYg1DdAC7AQAEAAgKYg1DdAC7AQADAAEKfQHdMgAYAAAAAA==.Anxious:BAAANQAECggIDQAAAA==.',
As='Aspburgerz:BAAANQADCgQIBAABNQAECgkJLgAFABkbAA==.',
Ba='Badgrammer:BAAANQADCgYICwAAAA==.',
Bi='Bigweed:BAAANQADCgYICAAAAA==.Billidan:BAAANQADCggIGgAAAA==.',
Bl='Bloødÿ:BAAANQAECgYIDQAAAA==.',
Bo='Bosephis:BAAANQAECgEIAwAAAA==.',
Ch='Chowlin:BAAANQADCggIBgAAAA==.',
Co='Coldslab:BAAANQAECgMIBAAAAA==.',
Cr='Crow:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.Crustybob:BAAANQADCgMIAwABNQAECgcIGAAHADsUAA==.',
De='Deathlyropes:BAAANQADCgYIDAAAAA==.',
Di='Diananight:BAAANQAECgUIEAAAAA==.Dinorèy:BAAANQADCgEIAQAAAA==.',
Dr='Drpuñetazos:BAAANQAECgIIBAAAAA==.',
Du='Dustocky:BAAANQAECgYIEgAAAA==.',
El='Elaina:BAAANQADCggIDAAAAA==.Element:BAAANQADCgEIAQABNQADCgYICQAGAAAAAA==.',
Ez='Ezbake:BAABNQAECn8hAAIIAAgK2BqwKgBuAgAIAAgK2BqwKgBuAgAAAA==.',
Fl='Flintlock:BAAANQAECgEIAQAAAA==.Flokighoul:BAAANQADCgYIBgAAAA==.Flokizuul:BAAANQAECgYIBgAAAA==.Florescence:BAABNQAECn8uAAIJAAkKByFLDgBWAwAJAAkKByFLDgBWAwAAAA==.',
Fr='Fractalella:BAAANQADCgYIBgAAAA==.Frudoc:BAAANQABCgIIAgAAAA==.',
Go='Goemon:BAAANQADCgYIHAAAAA==.Gorc:BAAANQAECgEIAQAAAA==.',
He='Hellion:BAAANQADCgMIAwAAAA==.',
Ho='Holymocha:BAAANQABCggIFAAAAA==.Hozz:BAAANQADCggIGAAAAA==.',
Id='Idiotbox:BAAANQADCgYIIQABNQAECgEIAQAGAAAAAA==.',
In='Incinerate:BAAANQADCgUJBQABNQADCgYICQAGAAAAAA==.Inkyy:BAAANQAECgYIEgAAAA==.',
Ji='Jinx:BAABNQAECn8mAAMCAAkKTx+0BwCDAgACAAgKfxy0BwCDAgABAAgKxR+4NAADAgABNQAFFAgILgABAFIkAA==.',
Ju='Julie:BAAANQADCgYIBgAAAA==.',
Ka='Kaela:BAAANQADCggIDgAAAA==.Kalicat:BAAANQADCggJDgABNQAECggIIQAIANgaAA==.Kanyequest:BAAANQADCggIEAABNQAECgcIGAAHADsUAA==.Kayde:BAAANQAECgQIBAAAAA==.',
Ke='Keepitscruby:BAAANQADCgUIBQABNQAECgcIGAAHADsUAA==.Keisel:BAABNQAECn8fAAIKAAcK8RwISQA7AgAKAAcK8RwISQA7AgAAAA==.',
Ki='Killingusall:BAAANQAECgEIAQAAAA==.',
Ku='Kuf:BAAANQAECgEIAQABNQAFFAUIFAALAFsRAA==.Kurzul:BAAANQADCggIIgAAAA==.',
Ky='Kyomi:BAAANQADCgYICAAAAA==.',
La='Landorath:BAAANQADCgYIBgAAAA==.Lastthought:BAAANQADCgEIAgAAAA==.',
Li='Lightfall:BAAANQAECgEIAQAAAA==.Lilbigterd:BAABNQAECn8hAAIMAAkKMRymSgCxAgAMAAkKMRymSgCxAgAAAA==.Lippers:BAAANQADCgYIFwAAAA==.',
Lu='Lukaga:BAAANQAECgEIAQAAAA==.Luxray:BAAANQAECgMIBQAAAA==.',
Ma='Magilou:BAAANQAECgMIAwAAAA==.Magyc:BAAANQADCgEIAQAAAA==.Mali:BAAANQADCggIGgAAAA==.Malomalo:BAAANQADCggIDAABNQAECgcIGAAHADsUAA==.Maple:BAABNQAECn8rAAINAAgKryMXFwA9AwANAAgKryMXFwA9AwAAAA==.Maxipriest:BAAANQAECgEIAQAAAA==.',
Md='Mdsnista:BAABNQAECn8jAAIOAAgKCBN5DADvAQAOAAgKCBN5DADvAQAAAA==.',
Mi='Minatowarloc:BAAANQADCgIIAwABNQAECgQIBgAGAAAAAA==.Minouimu:BAAANQAECgUIEQABNQAECgEIAQAGAAAAAA==.',
Mo='Molyporphs:BAAANQAECgQICwAAAA==.Montblanc:BAAANQADCgIIAgAAAA==.',
My='Mythic:BAAANQAECgQIBwAAAA==.',
Na='Navi:BAAANQADCggIFAAAAA==.',
Ne='Nerox:BAAANQABCgMIAwAAAA==.Neryssa:BAAANQAECgEIAwAAAA==.',
Nu='Nubcakez:BAAANQADCgMIAwAAAA==.Nubslice:BAAANQADCgcIBwAAAA==.Nuggetman:BAAANQAECgMJAwAAAA==.',
Pa='Patience:BAAANQADCgYIEgAAAA==.',
Pl='Plusultra:BAAANQAECgUIBgAAAA==.',
Py='Pyrenaeus:BAAANQADCgYICAAAAA==.',
Qm='Qmen:BAABNQAECn8aAAIMAAYKbxV0zgB4AQAMAAYKbxV0zgB4AQAAAA==.',
Qt='Qtora:BAABNQAECn8sAAIPAAkKlhraDACfAgAPAAkKlhraDACfAgAAAA==.',
Qu='Queso:BAABNQAECn8bAAIEAAcK6h+5QgBdAgAEAAcK6h+5QgBdAgAAAA==.',
Ra='Raxxar:BAABNQAECn8jAAINAAkKsiGWGgAtAwANAAkKsiGWGgAtAwAAAA==.',
Ri='Righteous:BAAANQADCgYICQAAAA==.',
Ro='Roldefoneer:BAAANQADCgMJAwAAAA==.Rothius:BAAANQADCgYIDAAAAA==.',
Se='Sephîroth:BAAANQAECgUIBQAAAA==.Sevik:BAAANQAECgIIAgABNQAECggIKwANAK8jAA==.',
Sh='Shalander:BAAANQADCggIGAAAAA==.Shaquiloheal:BAABNQAECn8YAAIHAAcKOxQNagDeAQAHAAcKOxQNagDeAQAAAA==.',
Si='Siaris:BAAANQADCggIGwAAAA==.Sinhfyre:BAAANQAECgIIAgAAAA==.',
Sn='Snerd:BAAANQABCgEIAQAAAA==.',
Sp='Spankadin:BAAANQAECgYIDQAAAA==.Spotter:BAAANQAECgMICAAAAA==.',
St='Stepsister:BAAANQADCggICAABNQAECgcIGwAEAOofAA==.Stillscruby:BAAANQAECgQICwABNQAECgcIGAAHADsUAA==.',
Su='Subslice:BAAANQADCgQICAAAAA==.Suf:BAACNQAFFH8UAAMLAAUKWxF2CwAwAQALAAQKWxF2CwAwAQAEAAIK8A0pJgCbAAA1AAQKfyYABAsACQrzF2geAEgCAAsACQrzF2geAEgCAAQABQoJFGGgAC8BAAMAAwomFB4XALsAAAAA.Sumting:BAAANQADCggIGAAAAA==.',
['Sí']='Síntor:BAAANQADCgYIDAAAAA==.',
Ta='Tazer:BAAANQADCggICAAAAA==.',
Th='Thighrabanks:BAAANQADCggIDQABNQAECgcIGAAHADsUAA==.',
Ti='Tirria:BAAANQADCgUIBQAAAA==.',
To='Tombtier:BAAANQADCgUIBQABNQAECggIJgAQALURAA==.',
Tr='Traquility:BAAANQADCgQJBAABNQADCgYICQAGAAAAAA==.Traumadealer:BAAANQAECgYIDAABNQAECgcIGAAHADsUAA==.',
Tw='Twiks:BAAANQADCgEIAQAAAA==.',
Vo='Volker:BAABNQAECn8dAAIRAAgKhBkhDgBKAgARAAgKhBkhDgBKAgAAAA==.',
Wa='Warrman:BAAANQAECgEIAQAAAA==.',
Xa='Xandus:BAAANQAECgYIBgAAAA==.Xandûs:BAABNQAECn8dAAMBAAkKbx1fHgCjAgABAAkKbx1fHgCjAgASAAMK/AW6YABjAAAAAA==.',
Ya='Yatogami:BAABNQAECn8cAAISAAYKySDKJAAdAgASAAYKySDKJAAdAgAAAA==.',
Yo='Yogo:BAAANQADCgYIFwAAAA==.',
Za='Zahaara:BAAANQABCgYIDAAAAA==.',
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
