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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Mage-Arcane','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Arms','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Priest-Discipline','DemonHunter-Vengeance','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Mage-Fire','DeathKnight-Unholy','Druid-Guardian','Paladin-Protection','Druid-Feral','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aayrawn:BAABNQAECn8zAAMBAAoKtRvaDACgAgABAAoKtRvaDACgAgACAAIKqg5RvgBuAAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgoKFgADALkcAA==.Acesdruid:BAAANQAECgYICwABNQAECgoKFgADALkcAA==.Aceshaman:BAABNQAECn8WAAMDAAoKuRxITQBBAgADAAgKNRxITQBBAgABAAkKtxc2FwD1AQAAAA==.',
Ai='Airone:BAAANQAECgUIBwAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgoKMAAEACohAA==.Alluriel:BAAANQADCgIIAgAAAA==.Alucard:BAABNQAECn8gAAIFAAoKqB0aQQBnAgAFAAoKqB0aQQBnAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8pAAIGAAgKJQ+otgCxAQAGAAgKJQ+otgCxAQAAAA==.',
An='Antijastran:BAABNQAECn8vAAIHAAkKZAreQwBKAQAHAAkKZAreQwBKAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMIAAkKth47EADnAgAIAAkKnB47EADnAgAJAAEK/CBARQFUAAAAAA==.Aquda:BAAANQAECgEIAQAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgMIAwAAAA==.',
As='Ashbringer:BAABNQAECn9GAAIGAAoKIya+BADTAwAGAAoKIya+BADTAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAABNQAECn8nAAMFAAoKwQ4HSgDXAQAFAAoKwQ4HSgDXAQAKAAEKEA4eUQA9AAAAAA==.',
Ba='Baladoria:BAABNQAECn8pAAIFAAoKYBW4ZADyAQAFAAoKYBW4ZADyAQAAAA==.Baldkrank:BAABNQAECn8bAAILAAkKEgwA4wDDAQALAAkKEgwA4wDDAQAAAA==.Bama:BAAANQAECggICwAAAA==.Bananabowman:BAABNQAECn8dAAIJAAoKXB5OHgAeAwAJAAoKXB5OHgAeAwAAAA==.Banditos:BAAANQAECgcIDQAAAA==.Bartab:BAABNQAECn8xAAICAAkKCh9GKwC2AgACAAkKCh9GKwC2AgABNQAECggIIQAMAHwQAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECgkJKQANAHUaAA==.Beastling:BAAANQAECgQIEAAAAA==.Beau:BAACNQAFFH8JAAIOAAQKKBTFEQDZAAAOAAQKKBTFEQDZAAA1AAQKf0sAAg4ACgqJIoUKAFwDAA4ACgqJIoUKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAQICQAOACgUAA==.Bestia:BAAANQAFFAMIAwABNQAFFAMIBgAPAJAQAA==.Bettyßrisco:BAABNQAECn8vAAIJAAoKPx/qGwCuAgAJAAoKPx/qGwCuAgAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCggIDwAAAA==.',
Bo='Bombur:BAABNQAECn8mAAIQAAgK0g/omwChAQAQAAgK0g/omwChAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECgkJGwARAP4eAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAcIFQASAPgXAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAIALYeAA==.Brëtski:BAAANQAECgcIDgAAAA==.',
Bu='Bubagony:BAABNQAECn8iAAQTAAoKTh4lAwBTAgATAAcK0iElAwBTAgAQAAoKTBVRPADwAQAUAAIKpByWFQCUAAABNQAFFAYIEwAMAKYQAA==.Burakku:BAAANQAECgEIAQABNQAFFAUIDAADAFsVAA==.Buzza:BAABNQAECn8VAAIRAAYK+wa29wDuAAARAAYK+wa29wDuAAAAAA==.Buzzkill:BAABNQAECn8mAAIQAAoKphYiKwA3AgAQAAoKphYiKwA3AgAAAA==.',
Ca='Calinash:BAABNQAECn8wAAILAAoKgBnuUAD2AQALAAoKgBnuUAD2AQAAAA==.Calzraxx:BAABNQAECn8aAAIRAAcK8hZGkwDsAQARAAcK8hZGkwDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECgkJGwARAP4eAA==.',
Cc='Ccaan:BAAANQAECggIEwAAAA==.',
Ce='Celinn:BAABNQAECn8tAAIFAAoKExi3TwA1AgAFAAoKExi3TwA1AgAAAA==.',
Ch='Charliek:BAABNQAECn8XAAIRAAgK1A4aqAC5AQARAAgK1A4aqAC5AQAAAA==.Cheebah:BAAANQAECgMIBAAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhxaIgDeAgACAAkKXhxaIgDeAgADAAUKdxq5tQAnAQAAAA==.Chingoblingo:BAAANQADCggIGgAAAA==.Chorr:BAAANQAECgIIAgABNQAECggIDQAVAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECgkJGwARAP4eAA==.',
Cr='Crates:BAABNQAECn8bAAIRAAkK/h7tKwBqAgARAAkK/h7tKwBqAgAAAA==.Cringely:BAABNQAECn8mAAQFAAoKtSELCwBqAwAFAAoKtSELCwBqAwAWAAIK9BoVGgCaAAAKAAEKAABWlwAJAAAAAA==.Crispratadin:BAAANQAECgQIBAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAXACghAA==.Crosswalkk:BAAANQAECgIIAwAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAAVAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAwAAAA==.',
Da='Daktok:BAAANQAECgUIBgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIKAABNQAECgUICQAVAAAAAA==.',
De='Deathfortres:BAABNQAECn8wAAMYAAoKKxHBFAA2AgAYAAoKKxHBFAA2AgAMAAYKCwWpewDdAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAACNQAFFH8GAAMPAAMKkBCOCwCAAAAPAAMKXguOCwCAAAAOAAEKPRgPHQBEAAA1AAQKfzcAAw4ACgr6IuMOAC0DAA4ACgr6IuMOAC0DAA8ACArsFCAmABUCAAAA.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8IAAIPAAQKaRTpBwDPAAAPAAQKaRTpBwDPAAA1AAQKfxkAAg8ACQpSGh8XAKYCAA8ACQpSGh8XAKYCAAAA.Denaric:BAAANQADCgQIBAAAAA==.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAABNQAECn8kAAIPAAkKaB+oDAAYAwAPAAkKaB+oDAAYAwAAAA==.',
Do='Dontar:BAAANQAECgUIBgAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAABNQAECn8YAAIBAAgK+RaSDwDhAQABAAgK+RaSDwDhAQABNQABCgQIBAAVAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8VAAISAAcK+BdBBAAlAgASAAcK+BdBBAAlAgA1AAQKf0EABBIACgrCGZ0XAEACABIACgrCGZ0XAEACABkACAoyEqIGALQBABoACQr/FGEJAK8BAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Drâx:BAAANQAECgcIBwAAAA==.Dríppy:BAAANQAECgQICwAAAA==.',
Ed='Edrian:BAAANQADCgcIBwAAAA==.',
Ei='Eilerra:BAABNQAECn8jAAMbAAkKIhmQEgB+AQALAAgKSxIr/wCPAQAbAAYKKxuQEgB+AQAAAA==.',
Er='Erre:BAABNQAECn81AAIQAAoK+x2ALwDJAgAQAAoK+x2ALwDJAgAAAA==.',
Ex='Exxitwound:BAAANQADCggIGAAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgMIBAAAAA==.Firesson:BAABNQAECn8aAAILAAkKPQL/+QCYAAALAAkKPQL/+QCYAAAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgMICgAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgUIBwABNQAECgoKJgAFALUhAA==.',
Fr='Fritark:BAABNQAECn8tAAMHAAkK3xX7NQABAgAHAAkKTBT7NQABAgAcAAQKNBegfQADAQAAAA==.Fritzyp:BAAANQAECggICwABNQAECgkJLQAHAN8VAA==.Frostyburn:BAAANQAECgIIBAAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQAECgMIBAAAAA==.Geörge:BAACNQAFFH8MAAIKAAUKER5sBwCgAQAKAAUKER5sBwCgAQA1AAQKf0kAAgoACgqvJAEFAIgDAAoACgqvJAEFAIgDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAABNQAECn8rAAMdAAoKuSMUCQANAgARAAoKSSHTOwAnAgAdAAcKgiUUCQANAgAAAA==.',
Gr='Gremfrost:BAABNQAECn8nAAIbAAoKrhR4BwAHAgAbAAoKrhR4BwAHAgAAAA==.Grotelek:BAABNQAECn8uAAICAAoKHhV3YADtAQACAAoKHhV3YADtAQAAAA==.Grumpywaltz:BAABNQAECn8uAAIdAAkKRBRHFQDTAQAdAAkKRBRHFQDTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECgcICwABNQAECgkJIwAbACIZAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn87AAIQAAoKHg0GTAC5AQAQAAoKHg0GTAC5AQAAAA==.Halcozigan:BAAANQADCgYIBgAAAA==.Halleko:BAABNQAECn8pAAIGAAoKwiDgIwCuAgAGAAoKwiDgIwCuAgABNQAFFAYIEwAeAAcbAA==.Hammerfoot:BAAANQAECgYIDQAAAA==.Hark:BAAANQAECgQICAAAAA==.Harkknight:BAABNQAECn8ZAAIcAAkKshY+NQBIAQAcAAkKshY+NQBIAQAAAA==.Haurtrue:BAABNQAECn8iAAIMAAgKnRt2KgCFAgAMAAgKnRt2KgCFAgAAAA==.Hawgbawl:BAABNQAECn88AAIfAAoK8BkzBgAqAgAfAAoK8BkzBgAqAgAAAA==.Hawgdream:BAABNQAECn8UAAIUAAUKbQrgMAAEAQAUAAUKbQrgMAAEAQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFH8TAAMeAAYKBxs1BAAHAgAeAAYKBxs1BAAHAgAgAAEKOQE6FwA0AAA1AAQKf00AAx4ACgpUJWkEAJADAB4ACgpUJWkEAJADACAACAqLGvg+ALsBAAAA.Heyyitzrichh:BAABNQAECn8eAAMUAAkKzCBWJABPAQAQAAcK3h+/ggDfAQAUAAQKLSJWJABPAQAAAA==.',
Ho='Hollinar:BAABNQAECn8WAAILAAkKRwpUzwDnAQALAAkKRwpUzwDnAQAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ic='Icyhõt:BAAANQADCgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICwAAAA==.',
In='Invaled:BAAANQAECgUICAAAAA==.',
Io='Ioveless:BAAANQAECgQIBAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQICwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAFFAQICgAGAEEeAA==.Jasmirangel:BAABNQAECn8pAAIYAAkKpCRAAgCrAwAYAAkKpCRAAgCrAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECn8pAAINAAkKdRpqRwDDAQANAAkKdRpqRwDDAQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECggIEAAVAAAAAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8fAAIhAAgKCAwLBACCAQAhAAgKCAwLBACCAQABNQAFFAIIBgAHAPoVAA==.Kankaladin:BAACNQAFFH8KAAIGAAQKQR5mDAD7AAAGAAQKQR5mDAD7AAA1AAQKfywAAgYACgqZIicoACUDAAYACgqZIicoACUDAAAA.Kanky:BAAANQAECgUIBQABNQAFFAQICgAGAEEeAA==.Kano:BAABNQAECn8pAAMIAAoKEhg2NQCkAQAIAAkKVwk2NQCkAQAJAAkK7xfEkQBKAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8cAAIUAAgKNAxOHQCDAQAUAAgKNAxOHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8nAAMiAAkKjB/fHwDMAgAiAAgKhSHfHwDMAgAHAAcKfBLLXwAmAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8tAAICAAkKeRgfJgBlAgACAAkKeRgfJgBlAgAAAA==.',
Kh='Khory:BAAANQAECggIDQAAAA==.',
Ki='Kichirõ:BAABNQAECn8rAAIEAAoK1AgbGABiAQAEAAoK1AgbGABiAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQADCgMIBAAAAA==.Kimuri:BAAANQAECgEIAQAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICwAVAAAAAA==.',
Ko='Koffee:BAAANQAECggIDQABNQAFFAQICgAGAEEeAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICwAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgoKOAAPAE0SAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggICgABNQAECgoKJwAFAMEOAA==.Lattemocha:BAABNQAECn8kAAQYAAoKCw/qOQBPAQAYAAcKPAzqOQBPAQAMAAgKOAiEcAAIAQAjAAUKlQZAQQCIAAAAAA==.',
Le='Leprechaun:BAABNQAECn8UAAMMAAYKngvccQADAQAMAAYKngvccQADAQAjAAQKeQb3TABgAAABNQAECggIFAADANYNAA==.Leprechauñ:BAAANQAECgQICgABNQAECggIFAADANYNAA==.Leprecháun:BAAANQAECgIIAwABNQAECggIFAADANYNAA==.Lepréchaun:BAABNQAECn8UAAMDAAgK1g2gdQDwAAADAAcKVg6gdQDwAAACAAQKQQ5njgDaAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAFFAMIBgAPAJAQAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQABNQAECgoKPAALAF8fAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgUIBgAAAA==.Lunatonne:BAABNQAECn8nAAIJAAoKhxfyQACoAgAJAAoKhxfyQACoAgAAAA==.Lunezta:BAAANQADCggICQABNQAECgUIFQAiAGgjAA==.Luneztoprime:BAABNQAECn8VAAIiAAUKaCN2UADSAQAiAAUKaCN2UADSAQAAAA==.Luvlybella:BAAANQAECgQICAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgcIEQAAAA==.Malady:BAAANQADCgYIDwAAAA==.Mallypally:BAAANQAECgMIAwABNQAECgUIDQAVAAAAAA==.Matt:BAACNQAFFH8WAAIYAAYKwxPFBQB5AQAYAAYKwxPFBQB5AQA1AAQKfzYAAhgACgorHLoOAOgCABgACgorHLoOAOgCAAAA.Matte:BAACNQAFFH8IAAICAAQKixfVEwDfAAACAAQKixfVEwDfAAA1AAQKfyoAAwIACgr2GjU2AIYCAAIACgr2GjU2AIYCAAMAAQoAAPVHASoAAAE1AAUUBggWABgAwxMA.Mazza:BAABNQAECn8bAAINAAoKDBvcIACJAgANAAoKDBvcIACJAgAAAA==.',
Me='Meddicus:BAAANQAECgcICgAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECggIEAAAAA==.',
Mi='Miedillø:BAAANQAFFAIIAQABNQAFFAgIMAAIAAEjAA==.Mikeoxmall:BAACNQAFFH8KAAIJAAQKzBpPDQD/AAAJAAQKzBpPDQD/AAA1AAQKfzEAAwkACgoMHs8wANoCAAkACQo5Is8wANoCAAgABgoNDOlOAPMAAAAA.',
Mo='Monstermime:BAABNQAECn8tAAQTAAkK+BUbCQD1AQATAAkKKBQbCQD1AQAQAAYK/xBkxgA+AQAUAAQKmQ4+MQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8pAAIcAAoKRw0AVgCcAQAcAAoKRw0AVgCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgkJLQATAPgVAA==.',
My='Myserie:BAABNQAECn8fAAIKAAkKKQ7JKgDRAQAKAAkKKQ7JKgDRAQAAAA==.Mystikah:BAAANQADCgMIAwAAAA==.',
Na='Napshade:BAAANQAECgIIAQABNQAECgYIBQAVAAAAAA==.Natsuu:BAAANQAECgQIBQAAAA==.Nazara:BAACNQAFFH8RAAMaAAYKAxnGAQAOAQAaAAYKAxnGAQAOAQASAAMKgwG9EwCYAAA1AAQKfzgAAxoACgplIMwCAMYCABoACgplIMwCAMYCABIAAgr1C6xIAF0AAAE1AAQKCAgNABUAAAAA.',
Ne='Neuro:BAABNQAECn9AAAILAAoKdRrLNgBJAgALAAoKdRrLNgBJAgAAAA==.Neyvin:BAAANQADCgIIBQABNQADCggIEAAVAAAAAA==.',
Ni='Nightfiress:BAAANQAECgIIAgAAAA==.Nikodemos:BAAANQAFFAYIEgAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgMIAgAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pa='Pandastyle:BAAANQAECgUIBQAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Ph='Philip:BAAANQADCgcIBwAAAA==.',
Pi='Piecemaker:BAACNQAFFH8NAAIJAAYK6BlQDQB+AQAJAAYK6BlQDQB+AQA1AAQKf2kAAgkACgoeI1sNAAsDAAkACgoeI1sNAAsDAAAA.',
Pl='Plaguepapi:BAAANQAECgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proslicer:BAAANQADCggIHgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIDwAAAA==.',
Py='Pyrrah:BAABNQAECn8uAAMNAAkKzCLkHwDwAgANAAkKzCLkHwDwAgAGAAcKhhZlrwDAAQAAAA==.Pyrri:BAAANQAECgQIBgABNQAECgkJLgANAMwiAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn84AAIPAAoKTRK/IABHAgAPAAoKTRK/IABHAgAAAA==.',
Ra='Rabuf:BAABNQAECn8jAAINAAkK8BfaPADwAQANAAkK8BfaPADwAQAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8gAAIRAAoKfx21LABnAgARAAoKfx21LABnAgABNQAFFAYIEwAMAKYQAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAABNQAECn8cAAIeAAoKtxFkDQDPAQAeAAoKtxFkDQDPAQABNQAECgoKOAAPAE0SAA==.Redizle:BAAANQADCggICAABNQAFFAcIFQANAJ8WAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgMICgAAAA==.',
Ri='Ridizle:BAACNQAFFH8VAAINAAcKnxbsBgD7AQANAAcKnxbsBgD7AQA1AAQKf0YAAg0ACgoYIgUJAHEDAA0ACgoYIgUJAHEDAAAA.',
Ro='Rohdoog:BAABNQAECn8dAAIZAAoKRxOzCQDhAQAZAAoKRxOzCQDhAQAAAA==.',
Ru='Runedyu:BAABNQAECn8rAAIiAAoKmBTUFAAfAgAiAAoKmBTUFAAfAgAAAA==.',
Ry='Ryanno:BAABNQAECn8zAAMJAAoKBCVxDAASAwAJAAoKBCVxDAASAwAIAAcK3QwPQABTAQAAAA==.Ryannoo:BAAANQAECggICAAAAA==.Ryunosuke:BAAANQAECggIDAABNQAFFAMIBgAPAJAQAA==.',
Sa='Sahomi:BAACNQAFFH8IAAIFAAMKLQrOIgDKAAAFAAMKLQrOIgDKAAA1AAQKfyYAAwUACgoCESlSAC0CAAUACgoCESlSAC0CABYABAqYAmAcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggICgAAAA==.Sarcini:BAABNQAECn8nAAIkAAgKIR+HEgB6AgAkAAgKIR+HEgB6AgAAAA==.Sarcisse:BAAANQAECgcIDgAAAA==.Satrina:BAABNQAECn8xAAMiAAoKJx7TDACHAgAiAAoKJx7TDACHAgAHAAIKAACklQBqAAAAAA==.Savvy:BAABNQAECn8uAAICAAkKehqDSQA8AgACAAkKehqDSQA8AgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAAVAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwAVAAAAAA==.Shameonyou:BAAANQAECgQIBAAAAA==.Shocka:BAAANQADCgYIBgAAAA==.Shockling:BAAANQADCgUIBQAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8JAAICAAQKKgf/GgDCAAACAAQKKgf/GgDCAAA1AAQKfywAAgIACgo1GuI3AAkCAAIACgo1GuI3AAkCAAAA.Souchong:BAAANQADCgMIAwABNQAECgoKJwAFAMEOAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn8wAAIJAAoKPRgLWgBmAgAJAAoKPRgLWgBmAgAAAA==.',
St='Stanleyy:BAAANQAFFAEIAQAAAA==.Steroidrage:BAAANQAECgEIAQAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggICQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAABNQAECn8cAAIGAAkKqBhVRAAqAgAGAAkKqBhVRAAqAgAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIXAAMKKCFmAgAdAQAXAAMKKCFmAgAdAQA1AAQKfx8AAxcACQrwIhYDAD0DABcACQrwIhYDAD0DAA4AAQr5B++WAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECggIDQAVAAAAAA==.',
Th='Thedarkduke:BAABNQAECn8bAAIXAAgKvBIWEQCfAQAXAAgKvBIWEQCfAQAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECggIGwAXALwSAA==.Thefallen:BAAANQAECgEIAQAAAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECggIDAABNQAFFAEIAQAVAAAAAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECn8gAAICAAgKDCBKIgDeAgACAAgKDCBKIgDeAgAAAA==.Timmeh:BAAANQAECgcICQAAAA==.Tindra:BAAANQAECggIDwAAAA==.Tissue:BAABNQAECn9FAAIOAAoKtw/nIQC/AQAOAAoKtw/nIQC/AQAAAA==.Titanius:BAABNQAECn8bAAIGAAoKkhubLgB9AgAGAAoKkhubLgB9AgABNQAECggIDQAVAAAAAA==.',
To='Tobibi:BAABNQAECn8iAAISAAoK8yEvBQBZAwASAAoK8yEvBQBZAwABNQAFFAEIAQAVAAAAAA==.Tolip:BAABNQAECn8bAAQlAAkKBw9QGwBNAQAlAAYKSxBQGwBNAQAYAAYKDggISQCgAAAMAAEK7ALxwwAeAAAAAA==.Tolipally:BAAANQADCgYICwABNQAECgkJGwAlAAcPAA==.Tolipicious:BAAANQADCgYIBgABNQAECgkJGwAlAAcPAA==.Tollock:BAAANQADCggIFAABNQAECgkJGwAlAAcPAA==.Topsykret:BAAANQADCgcICQAAAA==.Topsyy:BAAANQADCggIEQAAAA==.Torpse:BAAANQAECgcJDAABNQAFFAQICAAMAAUYAA==.Torrick:BAAANQADCgQIBAAAAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECn8tAAIOAAoKnAh5RwCNAQAOAAoKnAh5RwCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMICwAAAA==.',
Ul='Ulg:BAABNQAECn82AAMRAAoKMiKLJAAmAwARAAoKLiGLJAAmAwAfAAYK0RyKDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgoKNgARADIiAA==.',
Uw='Uwantmebad:BAAANQADCgQIBAAAAA==.',
Va='Valkyl:BAAANQADCgQIBwAAAA==.Valkyll:BAAANQADCgQIBAAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn8wAAMXAAoKwBkQCAB7AgAXAAoKwBkQCAB7AgAPAAIKtAuvQQBsAAAAAA==.',
We='Weave:BAAANQAECggIDQABNQAFFAYIFgAYAMMTAA==.Wellerman:BAAANQAECgcIDAAAAA==.Wercsmage:BAAANQAECgEIAQAAAA==.',
Wh='Whet:BAAANQADCgYIBgABNQADCgMIAwAVAAAAAA==.Whohaveaggro:BAAANQAECgEIAQAAAA==.',
Wi='Willpew:BAAANQAECgYIBgAAAA==.Wino:BAAANQAECgcIDQAAAA==.Wiqui:BAABNQAECn8jAAIJAAoKKhigYQC8AQAJAAoKKhigYQC8AQAAAA==.',
Wo='Wolfonk:BAABNQAECn8uAAImAAoKswpKMACVAQAmAAoKswpKMACVAQAAAA==.',
Wu='Wuhshake:BAABNQAECn8uAAICAAkK8CP/DABYAwACAAkK8CP/DABYAwAAAA==.Wuhshank:BAAANQAECgUICgAAAA==.',
['Wë']='Wërrcs:BAABNQAECn8cAAIDAAoKhgiZXAA1AQADAAoKhgiZXAA1AQAAAA==.',
Xe='Xemo:BAABNQAECn84AAIGAAkKzBLDdQCjAQAGAAkKzBLDdQCjAQAAAA==.Xenophics:BAACNQAFFH8KAAIGAAcKmAi2EABCAQAGAAcKmAi2EABCAQA1AAQKfz0AAgYACgrHJEQmAKICAAYACgrHJEQmAKICAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFH8VAAImAAYKcxl8BAA7AQAmAAYKcxl8BAA7AQA1AAQKfy0AAyYACgqDHzsOAEsCACYACgqDHzsOAEsCACcAAgqLE6dDAGAAAAAA.Zamos:BAAANQAECgUICgAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zenshin:BAAANQADCggIEQAAAA==.Zentaur:BAABNQAECn8tAAIEAAkKdgy4FACYAQAEAAkKdgy4FACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8sAAMfAAoKDhduEwBpAQARAAoKEBWPegAoAgAfAAYKmhJuEwBpAQABNQAFFAIIBgAHAPoVAA==.',
Zo='Zontar:BAAANQAECgQICAAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
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
