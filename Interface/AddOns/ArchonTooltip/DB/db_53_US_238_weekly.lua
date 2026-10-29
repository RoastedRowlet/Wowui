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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Arcane','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Warlock-Demonology','Warrior-Arms','Evoker-Preservation','Warlock-Destruction','Unknown-Unknown','Priest-Discipline','Priest-Shadow','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Devourer','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Mage-Fire','DeathKnight-Unholy','Druid-Guardian','Warlock-Affliction','Evoker-Augmentation','Paladin-Protection','Druid-Feral','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aayrawn:BAABNQAECn8uAAMBAAoKtRvaDACgAgABAAoKtRvaDACgAgACAAIKPAbhrgBdAAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgkJFQADADkcAA==.Acesdruid:BAAANQAECgYICwABNQAECgkJFQADADkcAA==.Aceshaman:BAABNQAECn8VAAMDAAkKORxITQBBAgADAAgKNRxITQBBAgABAAgKgBY2FwD1AQAAAA==.',
Ai='Airone:BAAANQAECgQIBwAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgoKLgAEAEMgAA==.Alluriel:BAAANQADCgIIAgAAAA==.Alucard:BAABNQAECn8eAAIFAAgKRB4aQQBnAgAFAAgKRB4aQQBnAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8nAAIGAAgKJQ92hgBEAQAGAAgKJQ92hgBEAQAAAA==.',
An='Antijastran:BAABNQAECn8nAAIHAAgKyQqcSwCLAQAHAAgKyQqcSwCLAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMIAAkKth47EADnAgAIAAkKnB47EADnAgAJAAEK/CBARQFUAAAAAA==.Aquda:BAAANQAECgEIAQAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgMIAwAAAA==.',
As='Ashbringer:BAABNQAECn9DAAIGAAoKIya+BADTAwAGAAoKIya+BADTAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAABNQAECn8cAAIFAAoKhw7lSgCFAQAFAAoKhw7lSgCFAQAAAA==.',
Ba='Baladoria:BAABNQAECn8mAAIFAAoKhhS4ZADyAQAFAAoKhhS4ZADyAQAAAA==.Baldkrank:BAABNQAECn8YAAIKAAkK6AsA4wDDAQAKAAkK6AsA4wDDAQAAAA==.Bama:BAAANQAECggICgAAAA==.Bananabowman:BAABNQAECn8dAAIJAAoKXB5OHgAeAwAJAAoKXB5OHgAeAwAAAA==.Banditos:BAAANQAECgcIDQAAAA==.Bartab:BAABNQAECn8uAAICAAkKCh9GKwC2AgACAAkKCh9GKwC2AgABNQAECgcIGgALAPEOAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECgkJJgAMAHUaAA==.Beastling:BAAANQAECgQIDQAAAA==.Beau:BAACNQAFFH8JAAINAAQKKBTFEQDZAAANAAQKKBTFEQDZAAA1AAQKf0MAAg0ACgpIIoUKAFwDAA0ACgpIIoUKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAQICQANACgUAA==.Bestia:BAAANQAFFAMIAwAAAA==.Bettyßrisco:BAABNQAECn8lAAIJAAoKPxjeQgDYAQAJAAoKPxjeQgDYAQAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCgcIDAAAAA==.',
Bo='Bombur:BAABNQAECn8kAAIOAAcKyhDomwChAQAOAAcKyhDomwChAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECgkJGgAPAP4eAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAcIFQAQAPgXAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAIALYeAA==.Brëtski:BAAANQAECgcIDgAAAA==.',
Bu='Bubagony:BAABNQAECn8bAAMOAAoKbBa8KQAMAgAOAAoKTBW8KQAMAgARAAIKpBxQEACaAAABNQAFFAYIEwALAKYQAA==.Burakku:BAAANQADCgcICwABNQAFFAQICwADAFsVAA==.Buzza:BAAANQAECgUIDwAAAA==.Buzzkill:BAABNQAECn8fAAIOAAoKoRW2JQAgAgAOAAoKoRW2JQAgAgAAAA==.',
Ca='Calinash:BAABNQAECn8wAAIKAAoKgBmPOgAJAgAKAAoKgBmPOgAJAgAAAA==.Calzraxx:BAABNQAECn8aAAIPAAcK8hZGkwDsAQAPAAcK8hZGkwDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECgkJGgAPAP4eAA==.',
Cc='Ccaan:BAAANQAECggIEwAAAA==.',
Ce='Celinn:BAABNQAECn8nAAIFAAoKexe3TwA1AgAFAAoKexe3TwA1AgAAAA==.',
Ch='Charliek:BAABNQAECn8XAAIPAAgK1A4aqAC5AQAPAAgK1A4aqAC5AQAAAA==.Cheebah:BAAANQAECgEIAQAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhxaIgDeAgACAAkKXhxaIgDeAgADAAUKdxq5tQAnAQAAAA==.Chingoblingo:BAAANQADCggIGQAAAA==.Chorr:BAAANQAECgIIAgABNQAECgcICwASAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECgkJGgAPAP4eAA==.',
Cr='Crates:BAABNQAECn8aAAIPAAkK/h5rHgB+AgAPAAkK/h5rHgB+AgAAAA==.Cringely:BAABNQAECn8kAAQFAAkKOiILCwBqAwAFAAkKOiILCwBqAwATAAIK9BoVGgCaAAAUAAEKAABWlwAJAAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAVACghAA==.Crosswalkk:BAAANQAECgIIAwAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAASAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAwAAAA==.',
Da='Daktok:BAAANQAECgMIBgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIKAABNQAECgUICQASAAAAAA==.',
De='Deathfortres:BAABNQAECn8mAAMWAAkKFA8CHACFAQAWAAgK8Q8CHACFAQALAAYKCwWpewDdAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAACNQAFFH8FAAMXAAIKkBCOCQCCAAAXAAIKXguOCQCCAAANAAEKPRgPHQBEAAA1AAQKfzYAAw0ACgr6IuMOAC0DAA0ACgr6IuMOAC0DABcACArsFCAmABUCAAE1AAUUAwgDABIAAAAA.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8IAAIXAAQKaRRLBgDVAAAXAAQKaRRLBgDVAAA1AAQKfxkAAhcACQpSGh8XAKYCABcACQpSGh8XAKYCAAAA.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAABNQAECn8kAAIXAAkKaB+oDAAYAwAXAAkKaB+oDAAYAwAAAA==.',
Do='Dontar:BAAANQAECgUIBgAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAABNQAECn8YAAIBAAgK+RbICgD4AQABAAgK+RbICgD4AQABNQABCgQIBAASAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8VAAIQAAcK+BfLAgAsAgAQAAcK+BfLAgAsAgA1AAQKfzgAAxAACgrCGZ0XAEACABAACgrCGZ0XAEACABgACQr/FNMGALwBAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Drâx:BAAANQAECgcIBwAAAA==.Dríppy:BAAANQAECgQICwAAAA==.',
Ed='Edrian:BAAANQADCgcIBwAAAA==.',
Ei='Eilerra:BAABNQAECn8fAAMZAAcKKxuQEgB+AQAKAAYKxRAr/wCPAQAZAAYKKxuQEgB+AQAAAA==.',
Er='Erre:BAABNQAECn80AAIOAAoK+x08GABtAgAOAAoK+x08GABtAgAAAA==.',
Ex='Exxitwound:BAAANQADCggIEQAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgMIBAAAAA==.Firesson:BAABNQAECn8aAAIKAAkKPQJF2gCeAAAKAAkKPQJF2gCeAAAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgMICgAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgUIBQABNQAECgkJJAAFADoiAA==.',
Fr='Fritark:BAABNQAECn8qAAMHAAgKdRf7NQABAgAHAAgKnxX7NQABAgAaAAQKNBegfQADAQAAAA==.Fritzyp:BAAANQAECggICgABNQAECggIKgAHAHUXAA==.Frostyburn:BAAANQAECgIIBAAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQAECgEIAQAAAA==.Geörge:BAACNQAFFH8MAAIUAAUKER5sBwCgAQAUAAUKER5sBwCgAQA1AAQKf0UAAhQACgp9JAEFAIgDABQACgp9JAEFAIgDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAABNQAECn8pAAMbAAoKryNHBgAXAgAPAAoKPyGQKQA6AgAbAAcKgiVHBgAXAgAAAA==.',
Gr='Gremfrost:BAABNQAECn8eAAIZAAkK9RK+DQDTAQAZAAkK9RK+DQDTAQAAAA==.Grotelek:BAABNQAECn8uAAICAAoKHhV3YADtAQACAAoKHhV3YADtAQAAAA==.Grumpywaltz:BAABNQAECn8qAAIbAAkKCxJHFQDTAQAbAAkKCxJHFQDTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECgcICwABNQAECgcIHwAZACsbAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn8wAAIOAAoKpQvdQACmAQAOAAoKpQvdQACmAQAAAA==.Halleko:BAABNQAECn8mAAIGAAoKJx6oHAChAgAGAAoKJx6oHAChAgABNQAFFAYIEwAcAAcbAA==.Hammerfoot:BAAANQAECgYIDQAAAA==.Hark:BAAANQAECgQIBAAAAA==.Harkknight:BAABNQAECn8YAAIaAAgKzBj/MAAoAQAaAAgKzBj/MAAoAQAAAA==.Haurtrue:BAABNQAECn8iAAILAAgKnRt2KgCFAgALAAgKnRt2KgCFAgAAAA==.Hawgbawl:BAABNQAECn84AAIdAAoKsBjHBAAkAgAdAAoKsBjHBAAkAgAAAA==.Hawgdream:BAABNQAECn8UAAIRAAUKbQrgMAAEAQARAAUKbQrgMAAEAQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFH8TAAMcAAYKBxs1BAAHAgAcAAYKBxs1BAAHAgAeAAEKOQE6FwA0AAA1AAQKf0gAAxwACgpUJZ4BAC0DABwACgpUJZ4BAC0DAB4ABwoKHOAhAL0BAAAA.Heyyitzrichh:BAABNQAECn8eAAMRAAkKzCBWJABPAQAOAAcK3h+/ggDfAQARAAQKLSJWJABPAQAAAA==.',
Ho='Hollinar:BAABNQAECn8WAAIKAAkKRwpUzwDnAQAKAAkKRwpUzwDnAQAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICwAAAA==.',
In='Invaled:BAAANQAECgUICAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQICwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAFFAMICQAGAEEeAA==.Jasmirangel:BAABNQAECn8pAAIWAAkKpCRAAgCrAwAWAAkKpCRAAgCrAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECn8mAAIMAAkKdRokNADQAQAMAAkKdRokNADQAQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgcIDwASAAAAAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8fAAIfAAgKCAwLBACCAQAfAAgKCAwLBACCAQABNQAFFAIIBQAHAOoOAA==.Kankaladin:BAACNQAFFH8JAAIGAAMKQR5xCAAJAQAGAAMKQR5xCAAJAQA1AAQKfysAAgYACgqZIicoACUDAAYACgqZIicoACUDAAAA.Kanky:BAAANQAECgUIBQABNQAFFAMICQAGAEEeAA==.Kano:BAABNQAECn8pAAMIAAoKEhg2NQCkAQAIAAkKVwk2NQCkAQAJAAkK7xfJbgBZAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8ZAAIRAAgKkAtOHQCDAQARAAgKkAtOHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8jAAMgAAkKjB/fHwDMAgAgAAgKhSHfHwDMAgAHAAYKsBLLXwAmAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8tAAICAAkKeRitGQB0AgACAAkKeRitGQB0AgAAAA==.',
Kh='Khory:BAAANQAECgcICwAAAA==.',
Ki='Kichirõ:BAABNQAECn8nAAIEAAoK1AgbGABiAQAEAAoK1AgbGABiAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQADCgMIBAAAAA==.Kimuri:BAAANQAECgEIAQAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICwASAAAAAA==.',
Ko='Koffee:BAAANQAECggIDAABNQAFFAMICQAGAEEeAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICwAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgoKOAAXAE0SAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggICgABNQAECgoKHAAFAIcOAA==.Lattemocha:BAABNQAECn8eAAQWAAgKTw7qOQBPAQAWAAcKPAzqOQBPAQALAAYKlwmEcAAIAQAhAAEKJgxSVwAnAAAAAA==.',
Le='Leprechaun:BAABNQAECn8UAAMLAAYKngvccQADAQALAAYKngvccQADAQAhAAQKeQZXPwBiAAABNQAECggIDgASAAAAAA==.Leprechauñ:BAAANQAECgQICgABNQAECggIDgASAAAAAA==.Leprecháun:BAAANQAECgIIAwABNQAECggIDgASAAAAAA==.Lepréchaun:BAAANQAECggIDgAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAFFAMIAwASAAAAAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQAAAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgQIBgAAAA==.Lunatonne:BAABNQAECn8kAAIJAAoK5RbyQACoAgAJAAoK5RbyQACoAgAAAA==.Luneztoprime:BAABNQAECn8VAAIgAAUKaCN2UADSAQAgAAUKaCN2UADSAQAAAA==.Luvlybella:BAAANQAECgQICAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgcIEQAAAA==.Malady:BAAANQADCgYIDAAAAA==.Mallypally:BAAANQAECgMIAwABNQAECgUIDQASAAAAAA==.Matt:BAACNQAFFH8RAAIWAAYKwxM4BAB8AQAWAAYKwxM4BAB8AQA1AAQKfzYAAhYACgorHLoOAOgCABYACgorHLoOAOgCAAAA.Matte:BAACNQAFFH8IAAICAAQKixd2DwDnAAACAAQKixd2DwDnAAA1AAQKfygAAwIACgr2GjU2AIYCAAIACgr2GjU2AIYCAAMAAQoAAPVHASoAAAE1AAUUBggRABYAwxMA.Mazza:BAAANQAECggIEgAAAA==.',
Me='Meddicus:BAAANQAECgcICgAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECggIEAAAAA==.',
Mi='Miedillø:BAAANQAFFAEIAQABNQAFFAcIKQAJADcfAA==.Mikeoxmall:BAACNQAFFH8JAAIJAAMKzBpFCQAJAQAJAAMKzBpFCQAJAQA1AAQKfy8AAwkACgoGHs8wANoCAAkACQoyIs8wANoCAAgABgoNDOlOAPMAAAAA.',
Mo='Monstermime:BAABNQAECn8qAAQiAAkK+BUbCQD1AQAiAAgK8xYbCQD1AQAOAAYK/xBkxgA+AQARAAQKmQ4+MQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8pAAIaAAoKRw0AVgCcAQAaAAoKRw0AVgCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgkJKgAiAPgVAA==.',
My='Myserie:BAABNQAECn8fAAIUAAkKKQ7JKgDRAQAUAAkKKQ7JKgDRAQAAAA==.Mystikah:BAAANQADCgMIAwAAAA==.',
Na='Napshade:BAAANQAECgEIAQABNQAECgYIBQASAAAAAA==.Natsuu:BAAANQAECgQIBQAAAA==.Nazara:BAACNQAFFH8RAAMYAAYKAxlJAQATAQAYAAYKAxlJAQATAQAQAAMKgwG9EwCYAAA1AAQKfzcAAxgACgplINUBANcCABgACgplINUBANcCABAAAgr1C6xIAF0AAAE1AAQKBwgLABIAAAAA.',
Ne='Neuro:BAABNQAECn83AAIKAAoKYhmugAB9AgAKAAoKYhmugAB9AgAAAA==.Neyvin:BAAANQADCgIIBAAAAA==.',
Ni='Nightfiress:BAAANQAECgEIAgAAAA==.Nikodemos:BAAANQAFFAYIEgAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgMIAgAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pa='Pandastyle:BAAANQAECgQIBAAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Pi='Piecemaker:BAACNQAFFH8NAAIJAAYK6BlQDQB+AQAJAAYK6BlQDQB+AQA1AAQKf10AAgkACgpkIr8JAAcDAAkACgpkIr8JAAcDAAAA.',
Pl='Plaguepapi:BAAANQADCgIJAgAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proslicer:BAAANQADCggIHAAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIDwAAAA==.',
Py='Pyrrah:BAABNQAECn8uAAMMAAkK0CLkHwDwAgAMAAkK0CLkHwDwAgAGAAcKhhZlrwDAAQAAAA==.Pyrri:BAAANQAECgQIBQABNQAECgkJLgAMANAiAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn84AAIXAAoKTRK/IABHAgAXAAoKTRK/IABHAgAAAA==.',
Ra='Rabuf:BAABNQAECn8dAAIMAAcKPxx5UAAqAgAMAAcKPxx5UAAqAgAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8fAAIPAAoKfx07HgB/AgAPAAoKfx07HgB/AgABNQAFFAYIEwALAKYQAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAABNQAECn8XAAIcAAgK0Q6YFgBFAQAcAAgK0Q6YFgBFAQABNQAECgoKOAAXAE0SAA==.Redizle:BAAANQADCggICAABNQAFFAcIFQAMAJ8WAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgIIBgAAAA==.',
Ri='Ridizle:BAACNQAFFH8VAAIMAAcKnxbsBgD7AQAMAAcKnxbsBgD7AQA1AAQKfz0AAgwACgpZIeoJACkDAAwACgpZIeoJACkDAAAA.',
Ro='Rohdoog:BAABNQAECn8ZAAIjAAoKIBOzCQDhAQAjAAoKIBOzCQDhAQAAAA==.',
Ru='Runedyu:BAABNQAECn8lAAIgAAkKrRNpFADlAQAgAAkKrRNpFADlAQAAAA==.',
Ry='Ryanno:BAABNQAECn8qAAMJAAoKISEwHwAbAwAJAAoKISEwHwAbAwAIAAcK3QwPQABTAQAAAA==.Ryannoo:BAAANQAECggICAAAAA==.Ryunosuke:BAAANQAECggIDAABNQAFFAMIAwASAAAAAA==.',
Sa='Sahomi:BAACNQAFFH8IAAIFAAMKLQrOIgDKAAAFAAMKLQrOIgDKAAA1AAQKfyYAAwUACgoCESlSAC0CAAUACgoCESlSAC0CABMABAqYAmAcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIBwAAAA==.Sarcini:BAABNQAECn8mAAIkAAgKIR+HEgB6AgAkAAgKIR+HEgB6AgAAAA==.Sarcisse:BAAANQAECgcIDQAAAA==.Satrina:BAABNQAECn8xAAMgAAoKJx5+CAChAgAgAAoKJx5+CAChAgAHAAIKAACklQBqAAAAAA==.Savvy:BAABNQAECn8rAAICAAkKjhmDSQA8AgACAAkKjhmDSQA8AgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAASAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwASAAAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.Shocka:BAAANQADCgYIBgAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8JAAICAAQKKgcqEgC+AAACAAQKKgcqEgC+AAA1AAQKfygAAgIACgo1GlknABQCAAIACgo1GlknABQCAAAA.Souchong:BAAANQABCgEIAQABNQAECgoKHAAFAIcOAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn8sAAIJAAoK6BQLWgBmAgAJAAoK6BQLWgBmAgAAAA==.',
St='Stanleyy:BAAANQAFFAEIAQAAAA==.Steroidrage:BAAANQAECgEIAQAAAA==.Stormtwist:BAAANQADCgYIBgAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggICQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAABNQAECn8cAAIGAAkKtBjbOQASAgAGAAkKtBjbOQASAgAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIVAAMKKCFmAgAdAQAVAAMKKCFmAgAdAQA1AAQKfx8AAxUACQrwIhYDAD0DABUACQrwIhYDAD0DAA0AAQr5B++WAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECgcICwASAAAAAA==.',
Th='Thedarkduke:BAABNQAECn8bAAIVAAgKvBIWEQCfAQAVAAgKvBIWEQCfAQAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECggIGwAVALwSAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECggIDAABNQAFFAEIAQASAAAAAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECn8gAAICAAgKDCBKIgDeAgACAAgKDCBKIgDeAgAAAA==.Timmeh:BAAANQAECgcICQAAAA==.Tindra:BAAANQAECgcIDwAAAA==.Tissue:BAABNQAECn88AAINAAoKcgwuIACUAQANAAoKcgwuIACUAQAAAA==.Titanius:BAABNQAECn8aAAIGAAoKnBukHgCVAgAGAAoKnBukHgCVAgABNQAECgcICwASAAAAAA==.',
To='Tobibi:BAABNQAECn8iAAIQAAoK8yEvBQBZAwAQAAoK8yEvBQBZAwABNQAFFAEIAQASAAAAAA==.Tolip:BAABNQAECn8XAAQlAAkK5A5QGwBNAQAlAAYKDhBQGwBNAQAWAAMKsQYKawBZAAALAAEK7ALxwwAeAAAAAA==.Tolipally:BAAANQADCgYICwABNQAECgkJFwAlAOQOAA==.Tolipicious:BAAANQADCgYIBgABNQAECgkJFwAlAOQOAA==.Tollock:BAAANQADCggIFAABNQAECgkJFwAlAOQOAA==.Topsykret:BAAANQADCgcICQAAAA==.Topsyy:BAAANQADCggIEAAAAA==.Torpse:BAAANQAECgcJDAABNQAFFAQICAALAAUYAA==.Torrick:BAAANQADCgQIBAAAAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECn8tAAINAAoKnAh5RwCNAQANAAoKnAh5RwCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMICwAAAA==.',
Ul='Ulg:BAABNQAECn81AAMPAAoK9yGLJAAmAwAPAAoK9CCLJAAmAwAdAAYK0RyKDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgoKNQAPAPchAA==.',
Uw='Uwantmebad:BAAANQADCgMIAwAAAA==.',
Va='Valkyl:BAAANQADCgQIBwAAAA==.Valkyll:BAAANQADCgQIBAAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn8uAAIVAAoKwBkQCAB7AgAVAAoKwBkQCAB7AgAAAA==.',
We='Weave:BAAANQAECgUICgABNQAFFAYIEQAWAMMTAA==.Wellerman:BAAANQAECgcIDAAAAA==.',
Wh='Whet:BAAANQADCgYIBgABNQADCgMIAwASAAAAAA==.Whohaveaggro:BAAANQAECgEIAQAAAA==.',
Wi='Willpew:BAAANQAECgYIBgAAAA==.Wino:BAAANQAECgYIDAAAAA==.Wiqui:BAABNQAECn8cAAIJAAoKzBQRVACgAQAJAAoKzBQRVACgAQAAAA==.',
Wo='Wolfonk:BAABNQAECn8uAAImAAoKswpKMACVAQAmAAoKswpKMACVAQAAAA==.',
Wu='Wuhshake:BAABNQAECn8rAAICAAgK5CX/DABYAwACAAgK5CX/DABYAwAAAA==.Wuhshank:BAAANQAECgUIBQAAAA==.',
['Wë']='Wërrcs:BAABNQAECn8WAAIDAAoKwwcIUgAXAQADAAoKwwcIUgAXAQAAAA==.',
Xe='Xemo:BAABNQAECn8vAAIGAAkKRREmYACaAQAGAAkKRREmYACaAQAAAA==.Xenophics:BAACNQAFFH8JAAIGAAYKQwq2EABCAQAGAAYKQwq2EABCAQA1AAQKfzYAAgYACgotJBgtABQDAAYACgotJBgtABQDAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFH8VAAImAAYKcxkjAwBIAQAmAAYKcxkjAwBIAQA1AAQKfykAAyYACgpSH6kKAFMCACYACgpSH6kKAFMCACcAAgqLE6dDAGAAAAAA.Zamos:BAAANQAECgcICgAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zenshin:BAAANQADCggIEQAAAA==.Zentaur:BAABNQAECn8qAAIEAAkKngu4FACYAQAEAAkKngu4FACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8oAAMdAAoKXRRuEwBpAQAPAAoKXhKPegAoAgAdAAYKmhJuEwBpAQABNQAFFAIIBQAHAOoOAA==.',
Zo='Zontar:BAAANQAECgYICAAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
Zy='Zylaz:BAAANQADCggICAAAAA==.',
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
