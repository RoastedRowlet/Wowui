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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Shaman-Elemental','Warlock-Destruction','Mage-Arcane','Unknown-Unknown','DeathKnight-Blood','Druid-Balance','Warrior-Arms','Shaman-Restoration','Priest-Shadow','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Druid-Feral','Warrior-Protection',}
local provider = {region='US',realm='Garithos',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Aciersilva:BAAANQAECgcIDAAAAA==.',
Ae='Aemeath:BAACNQAFFH8LAAMBAAUKSyPmCABeAQABAAUK0CLmCABeAQACAAEKIBy1BgBUAAA1AAQKfykAAwEACgoRJgUEALEDAAEACgoRJgUEALEDAAIABApKDksfANAAAAE1AAUUCQlDAAEA2iUA.',
Aj='Ajtwo:BAABNQAECn8bAAIDAAgK8gzbJwD3AAADAAgK8gzbJwD3AAAAAA==.',
Ak='Akanbe:BAABNQAECn8oAAMEAAoKch8QAgAPAwAEAAgKfiEQAgAPAwAFAAcKyxkjhwBDAQAAAA==.',
Al='Alucarde:BAAANQADCggIJQAAAA==.',
An='Anniichan:BAABNQAECn8bAAMFAAoKCAyodQC7AQAFAAoKCAyodQC7AQAEAAEKfQF9MwAYAAAAAA==.Anxious:BAABNQAECn8gAAMGAAoKMxjHSABEAgAGAAoKMxjHSABEAgAHAAEKAAAAAAAAAAAAAA==.',
As='Aspburgerz:BAAANQADCgQIBAABNQAECgoKQQADAIAcAA==.',
Ba='Badgrammer:BAAANQADCgYICwAAAA==.',
Bi='Bigweed:BAAANQADCgYICAAAAA==.Billidan:BAAANQADCggIGgAAAA==.',
Bl='Bloødÿ:BAABNQAECn8pAAIIAAoKmBFfVgAfAgAIAAoKmBFfVgAfAgAAAA==.',
Bo='Bosephis:BAAANQAECgUIEwAAAA==.',
Ch='Chowlin:BAAANQADCggIBgAAAA==.',
Co='Coldslab:BAAANQAECgMIBAAAAA==.',
Cr='Crustybob:BAAANQADCgMIAwABNQAECgkJLwAJAIcSAA==.',
De='Deathlyropes:BAAANQADCgYIDAAAAA==.',
Di='Diananight:BAABNQAECn8fAAIKAAYKhQNAHACFAAAKAAYKhQNAHACFAAAAAA==.Dinoreyto:BAAANQADCgMIAwAAAA==.Dinorèy:BAAANQADCgEIAQAAAA==.',
Dk='Dkaela:BAAANQADCgMIAwAAAA==.',
Dr='Drpuñetazos:BAAANQAECggIDwAAAA==.',
Du='Dustocky:BAABNQAECn8gAAILAAkKkw8t4ADIAQALAAkKkw8t4ADIAQAAAA==.Dustyggonar:BAAANQADCggIBgAAAA==.',
El='Elaina:BAAANQADCggIDAAAAA==.Element:BAAANQADCgEIAQABNQAECgEIAQAMAAAAAA==.',
Ez='Ezbake:BAABNQAECn8+AAINAAoKcB2zEQCKAgANAAoKcB2zEQCKAgAAAA==.',
Fl='Flintlock:BAAANQAECgIIAwAAAA==.Flokighoul:BAAANQADCgYIBgAAAA==.Flokizuul:BAAANQAECgYIBgAAAA==.Florescence:BAACNQAFFH8FAAIOAAIKrRlqGQChAAAOAAIKrRlqGQChAAA1AAQKf0YAAg4ACgo/I4IOAFYDAA4ACgo/I4IOAFYDAAAA.',
Fr='Fractalella:BAAANQAECgUIBgAAAA==.Frudoc:BAAANQABCgIIAgAAAA==.',
Ge='Gedd:BAAANQAECgMIAwAAAA==.',
Go='Goemon:BAAANQADCgYIHAAAAA==.Gorc:BAAANQAECgEIAQAAAA==.',
He='Hellion:BAAANQADCgMIAwAAAA==.',
Ho='Holymocha:BAAANQABCggIFAAAAA==.Hozz:BAAANQADCggIGAAAAA==.',
Id='Idiotbox:BAABNQAECn8fAAILAAYKvAISEQGYAAALAAYKvAISEQGYAAABNQAECgcIHwAPAD4DAA==.',
In='Incinerate:BAAANQADCgUJBQABNQAECgEIAQAMAAAAAA==.Inkyy:BAAANQAECgYIEgAAAA==.',
Ji='Jinx:BAABNQAECn8oAAMCAAoKUx7KBwCDAgACAAgKfxzKBwCDAgABAAkKlB5lNQADAgABNQAFFAkJQwABANolAA==.',
Ju='Julie:BAAANQADCgYIBgAAAA==.',
Ka='Kaela:BAAANQADCggIEQAAAA==.Kalicat:BAAANQADCggJDgABNQAECgoKPgANAHAdAA==.Kayde:BAAANQAECgUIBwAAAA==.',
Ke='Keepitscruby:BAAANQADCgUIBQABNQAECgkJLwAJAIcSAA==.Keisel:BAABNQAECn80AAIQAAkKRh2uKwB3AgAQAAkKRh2uKwB3AgAAAA==.',
Ki='Killingusall:BAAANQAECgEIAQAAAA==.',
Kn='Knøwn:BAAANQADCggIEAAAAA==.',
Ku='Kuf:BAAANQAECgEIAQABNQAFFAcIFgARAMANAA==.Kurzul:BAAANQADCggIIgAAAA==.',
Ky='Kyomi:BAAANQADCggIDgAAAA==.',
La='Landorath:BAAANQADCgYICAAAAA==.Lastthought:BAAANQADCgEIAgAAAA==.',
Li='Lightfall:BAAANQAECgEIAQAAAA==.Lilbigterd:BAABNQAECn8hAAIHAAkKMRxLTACwAgAHAAkKMRxLTACwAgAAAA==.Lippers:BAAANQADCggIHQAAAA==.',
Lu='Lukaga:BAABNQAECn8fAAIPAAcKPgPv5gCmAAAPAAcKPgPv5gCmAAAAAA==.Luxray:BAAANQAECgUICQAAAA==.',
Ma='Mafalda:BAAANQADCgYICAAAAA==.Magilou:BAAANQAECgMIAwAAAA==.Magyc:BAAANQADCgEIAQAAAA==.Mali:BAAANQADCggIGgAAAA==.Malomalo:BAAANQADCggIDAABNQAECgkJLwAJAIcSAA==.Maple:BAABNQAECn83AAIIAAkKMCOGFwA8AwAIAAkKMCOGFwA8AwAAAA==.Maxipriest:BAAANQAECgEIAQAAAA==.',
Md='Mdsnista:BAABNQAECn88AAISAAgKYBOhDADvAQASAAgKYBOhDADvAQAAAA==.',
Mi='Minatoo:BAAANQAECgQIBAAAAA==.Minatowarloc:BAAANQADCgIIAwABNQAECgQIBAAMAAAAAA==.Minouimu:BAABNQAECn83AAITAAoKmgV5KgBEAQATAAoKmgV5KgBEAQABNQAECgcIHwAPAD4DAA==.',
Mo='Molyporphs:BAAANQAECgQICwAAAA==.Montblanc:BAAANQAECgEIAQAAAA==.Mookz:BAAANQADCgQIBAAAAA==.',
My='Mythic:BAAANQAECgQIBwAAAA==.',
Na='Navi:BAAANQADCggIFAAAAA==.',
Ne='Nerox:BAAANQABCgMIAwAAAA==.Neryssa:BAAANQAECgUIEwAAAA==.',
Nu='Nubcakez:BAAANQAECgUIBgAAAA==.Nubslice:BAAANQADCgcIBwAAAA==.Nuggetman:BAAANQAECgMIAwAAAA==.',
Pa='Patience:BAAANQADCgYIEgAAAA==.Paulette:BAAANQADCgEIAQAAAA==.',
Pl='Plusultra:BAAANQAECgUIBgAAAA==.',
Py='Pyrenaeus:BAAANQADCgYICAAAAA==.',
Qm='Qmen:BAABNQAECn8kAAIHAAYKgRn20QB4AQAHAAYKgRn20QB4AQAAAA==.',
Qt='Qtora:BAACNQAFFH8FAAIUAAIKKAXhBgB+AAAUAAIKKAXhBgB+AAA1AAQKf0UAAxQACgpiGhUNAJ0CABQACgpiGhUNAJ0CAAkABQp7BtyYANYAAAAA.',
Qu='Queso:BAABNQAECn8dAAIFAAkK/B3ZQwBcAgAFAAkK/B3ZQwBcAgAAAA==.',
Ra='Raxxar:BAABNQAECn8rAAIIAAoKXCEoGwAsAwAIAAoKXCEoGwAsAwAAAA==.',
Ri='Righteous:BAAANQAECgEIAQAAAA==.',
Ro='Roldefoneer:BAAANQADCgMJAwAAAA==.Rothius:BAAANQADCggIDgAAAA==.',
Se='Sephîroth:BAAANQAECgUIBQAAAA==.Sevik:BAAANQAECgIIAgABNQAECgkJNwAIADAjAA==.',
Sh='Shalander:BAAANQADCggIGAAAAA==.Shaquiloheal:BAABNQAECn8vAAMJAAkKhxKGTQChAQAJAAkKhxKGTQChAQAQAAEKbwTzCgEjAAAAAA==.',
Si='Siaris:BAAANQADCggIKwAAAA==.Sinhfyre:BAABNQAECn8UAAIVAAYKAQS2GwCLAAAVAAYKAQS2GwCLAAAAAA==.',
Sn='Snerd:BAAANQABCgEIAQAAAA==.',
Sp='Spankadin:BAAANQAECgcIDwAAAA==.Spotter:BAAANQAECgMICAAAAA==.',
St='Stepsister:BAAANQADCggICAABNQAECgkJHQAFAPwdAA==.Stillscruby:BAAANQAECgQICwABNQAECgkJLwAJAIcSAA==.',
Su='Subslice:BAAANQADCgQICAAAAA==.Suf:BAACNQAFFH8WAAMRAAcKwA2tCwAwAQARAAYKwA2tCwAwAQAFAAIK8A3rJgCbAAA1AAQKfzwABBEACgrrG/oNAHoCABEACgrrG/oNAHoCAAUABwo/EjuTACABAAQAAwomFFQXALsAAAAA.Sumting:BAAANQADCggIGAAAAA==.',
['Sí']='Síntor:BAAANQADCgYIDAAAAA==.',
Ta='Tazer:BAAANQADCggICwAAAA==.',
Te='Terribad:BAAANQAECgUIBQABNQAECgoKPgANAHAdAA==.',
Th='Thighrabanks:BAAANQADCggIDQABNQAECgkJLwAJAIcSAA==.',
Ti='Tirria:BAAANQADCgUIBQAAAA==.',
To='Tombtier:BAAANQADCgUIBQABNQAECgkJJAAWACQWAA==.',
Tr='Traquility:BAAANQADCgQJBAABNQAECgEIAQAMAAAAAA==.Traumadealer:BAABNQAECn8ZAAMGAAkK0R3pGQDpAgAGAAkK0R3pGQDpAgAHAAcKewdS8QA6AQABNQAECgkJLwAJAIcSAA==.',
Tw='Twiks:BAAANQADCgEIAQAAAA==.',
Vo='Volker:BAABNQAECn8gAAIXAAoKDhZZDgBJAgAXAAoKDhZZDgBJAgAAAA==.',
Wa='Warrman:BAAANQAECgEIAQAAAA==.Waynekerr:BAAANQAECgMIAwABNQAECgkJLwAJAIcSAA==.',
Xa='Xandus:BAAANQAECgYIBgAAAA==.Xandûs:BAABNQAECn8lAAMBAAoKIBzSHgCjAgABAAoKIBzSHgCjAgATAAMK/AU2YgBjAAAAAA==.Xaxas:BAAANQAECggIBgAAAA==.',
Ya='Yatogami:BAABNQAECn8gAAITAAgK8xxCJQAcAgATAAgK8xxCJQAcAgAAAA==.',
Yo='Yogo:BAAANQADCgYIFwAAAA==.',
Za='Zahaara:BAAANQABCgYIDQAAAA==.',
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
