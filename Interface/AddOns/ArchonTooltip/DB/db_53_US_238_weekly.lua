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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Mage-Arcane','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Arms','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Priest-Discipline','DemonHunter-Vengeance','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Mage-Fire','DeathKnight-Unholy','Druid-Guardian','Paladin-Protection','Druid-Feral','Monk-Mistweaver','Monk-Windwalker',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aayrawn:BAABNQAECn86AAMBAAoKGCDaDACgAgABAAoKGCDaDACgAgACAAIKqg7pzQBpAAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgoKFgADALkcAA==.Acesdruid:BAAANQAECgYIDQABNQAECgoKFgADALkcAA==.Aceshaman:BAABNQAECn8WAAMDAAoKuRxITQBBAgADAAgKNRxITQBBAgABAAkKtxc2FwD1AQAAAA==.',
Ai='Airone:BAAANQAECgUICAAAAA==.',
Ak='Akadion:BAAANQAECgEIAgAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgoKMAAEACohAA==.Alluriel:BAAANQADCgIIAgAAAA==.Alucard:BAABNQAECn8iAAIFAAoKqB0aQQBnAgAFAAoKqB0aQQBnAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8pAAIGAAgKJQ+otgCxAQAGAAgKJQ+otgCxAQAAAA==.',
An='Antijastran:BAABNQAECn8vAAIHAAkKZAqcSwCLAQAHAAkKZAqcSwCLAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMIAAkKth47EADnAgAIAAkKnB47EADnAgAJAAEK/CBARQFUAAAAAA==.Aquda:BAAANQAECgEIAQAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgMIAwAAAA==.',
As='Ashbringer:BAABNQAECn9GAAIGAAoKIya+BADTAwAGAAoKIya+BADTAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAABNQAECn8sAAMFAAoKiw9vTgDpAQAFAAoKiw9vTgDpAQAKAAEKEA4xWQA9AAAAAA==.',
Ba='Baladoria:BAABNQAECn8pAAIFAAoKYBW4ZADyAQAFAAoKYBW4ZADyAQAAAA==.Baldkrank:BAABNQAECn8cAAILAAkKEgwA4wDDAQALAAkKEgwA4wDDAQAAAA==.Bama:BAAANQAECggIDAAAAA==.Bananabowman:BAABNQAECn8eAAIJAAoKXB5OHgAeAwAJAAoKXB5OHgAeAwAAAA==.Banditos:BAAANQAECgcIDwAAAA==.Bartab:BAABNQAECn8zAAICAAkKCh9GKwC2AgACAAkKCh9GKwC2AgABNQAECgkJKAAMAO8RAA==.',
Be='Bearemy:BAAANQAECgEIAgABNQAECgoKLQANAC0aAA==.Beastling:BAABNQAECn8ZAAIJAAgKiQ1SiQCJAQAJAAgKiQ1SiQCJAQAAAA==.Beau:BAACNQAFFH8JAAIOAAQKKBTFEQDZAAAOAAQKKBTFEQDZAAA1AAQKf1AAAg4ACgo1I4UKAFwDAA4ACgo1I4UKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAQICQAOACgUAA==.Bestia:BAAANQAFFAMIAwABNQAFFAMIBgAPAJAQAA==.Bettyßrisco:BAABNQAECn83AAIJAAoKPSBOHADEAgAJAAoKPSBOHADEAgAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIBAAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCggIDwAAAA==.',
Bo='Bombur:BAABNQAECn8nAAIQAAkKzA/ifABUAQAQAAkKzA/ifABUAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECgkJHAARAP4eAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAcIFgASAPgXAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAIALYeAA==.Brëtski:BAAANQAECggIEAAAAA==.',
Bu='Bubagony:BAABNQAECn8zAAQTAAoK3yC5AQDmAgATAAoKAR+5AQDmAgAQAAoKTBX4RQDxAQAUAAIKpBw3GACTAAABNQAFFAYIEwAMAKYQAA==.Buca:BAAANQAFFAEIAQABNQAFFAYIEwAMAKYQAA==.Burakku:BAAANQAECgEIAQABNQAFFAUIDgADAFsVAA==.Buzza:BAABNQAECn8VAAIRAAYK+wa29wDuAAARAAYK+wa29wDuAAAAAA==.Buzzkill:BAABNQAECn8oAAIQAAoKgRddMAA+AgAQAAoKgRddMAA+AgAAAA==.',
Ca='Calinash:BAABNQAECn83AAILAAoKcRoqSQAkAgALAAoKcRoqSQAkAgAAAA==.Calzraxx:BAABNQAECn8aAAIRAAcK8hZGkwDsAQARAAcK8hZGkwDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECgkJHAARAP4eAA==.',
Cc='Ccaan:BAABNQAECn8UAAQCAAkKXwZ9mwDVAAACAAgKOQV9mwDVAAADAAMKbgUsFQFjAAABAAEKFAKLNwAeAAAAAA==.',
Ce='Celinn:BAABNQAECn8tAAIFAAoKExi3TwA1AgAFAAoKExi3TwA1AgAAAA==.',
Ch='Charliek:BAABNQAECn8XAAIRAAgK1A4aqAC5AQARAAgK1A4aqAC5AQAAAA==.Cheebah:BAAANQAECgMIBAAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhxaIgDeAgACAAkKXhxaIgDeAgADAAUKdxq5tQAnAQAAAA==.Chingoblingo:BAAANQADCggIGgAAAA==.Chorr:BAAANQAECgIIAgABNQAECggIEAAVAAAAAA==.',
Ck='Ckaan:BAAANQAECgEIAQAAAA==.',
Co='Cobygo:BAAANQAECgEIAQAAAA==.Coffins:BAAANQADCgYIBgABNQAECgkJHAARAP4eAA==.',
Cr='Crates:BAABNQAECn8cAAIRAAkK/h5JMgBoAgARAAkK/h5JMgBoAgAAAA==.Cringely:BAABNQAECn8mAAQFAAoKtSELCwBqAwAFAAoKtSELCwBqAwAWAAIK9BoVGgCaAAAKAAEKAABWlwAJAAAAAA==.Crispratadin:BAAANQAECgQIBAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAXACghAA==.Crosswalkk:BAAANQAECgIIBAAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAAVAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYIDAAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAwAAAA==.',
Da='Daktok:BAAANQAECgUIBwAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIKAABNQAECgUICQAVAAAAAA==.',
De='Deathfortres:BAABNQAECn85AAMYAAoKExJaFwBDAgAYAAoKExJaFwBDAgAMAAYKCwWpewDdAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAACNQAFFH8GAAMPAAMKkBD2DAB8AAAPAAMKXgv2DAB8AAAOAAEKPRgPHQBEAAA1AAQKfzcAAw4ACgr6IuMOAC0DAA4ACgr6IuMOAC0DAA8ACArsFCAmABUCAAAA.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8IAAIPAAQKaRTzCADLAAAPAAQKaRTzCADLAAA1AAQKfxkAAg8ACQpSGh8XAKYCAA8ACQpSGh8XAKYCAAAA.Denaric:BAAANQADCggICgAAAA==.Detainus:BAAANQAECgEIAQAAAA==.Dethsoul:BAAANQAECgMIAwAAAA==.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQAECgEIAQAAAA==.Disarray:BAABNQAECn8nAAIPAAoKsB6oDAAYAwAPAAoKsB6oDAAYAwAAAA==.',
Do='Donjin:BAAANQAECgEIAQAAAA==.Dontar:BAAANQAECgUIBwAAAA==.Donvald:BAAANQAECgIIBAAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAABNQAECn8YAAIBAAgK+RYKEgDeAQABAAgK+RYKEgDeAQABNQABCgQIBAAVAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8WAAISAAcK+BelBQAgAgASAAcK+BelBQAgAgA1AAQKf0oABBIACgrCGZ0XAEACABIACgrCGZ0XAEACABkACArFEwAHAMYBABoACQr/FJsKAKwBAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Drâx:BAAANQAECgcIBwAAAA==.Dríppy:BAAANQAECgQIDQAAAA==.',
Ed='Edrian:BAAANQADCgcIBwAAAA==.',
Ei='Eilerra:BAABNQAECn8mAAMbAAoKrxiQEgB+AQALAAgKSxIr/wCPAQAbAAgK6xiQEgB+AQAAAA==.',
Er='Erre:BAABNQAECn83AAIQAAoKcR8LJgBqAgAQAAoKcR8LJgBqAgAAAA==.',
Et='Etari:BAAANQAECgEIAQABNQAECgEIAQAVAAAAAA==.',
Ex='Exxitwound:BAAANQADCggIGAAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgMIBAAAAA==.Firesson:BAABNQAECn8aAAILAAkKPQJxCAGWAAALAAkKPQJxCAGWAAAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgQIDAAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgUIBwABNQAECgoKJgAFALUhAA==.',
Fr='Fritark:BAABNQAECn8vAAMHAAkKmhj7NQABAgAHAAkKBxf7NQABAgAcAAQKNBegfQADAQAAAA==.Fritzyp:BAAANQAECggICwABNQAECgkJLwAHAJoYAA==.Frostyburn:BAAANQAECgIIBQAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQAECgMIBAAAAA==.Geörge:BAACNQAFFH8MAAIKAAUKER5sBwCgAQAKAAUKER5sBwCgAQA1AAQKf04AAgoACgqvJAEFAIgDAAoACgqvJAEFAIgDAAAA.',
Go='Goated:BAABNQAECn8uAAMdAAoK9SRyBgCHAgAdAAgKvyVyBgCHAgARAAoKSSG3RgAcAgAAAA==.',
Gr='Gremfrost:BAABNQAECn8rAAIbAAoKSxXYCAAHAgAbAAoKSxXYCAAHAgAAAA==.Grotelek:BAABNQAECn8uAAICAAoKHhV3YADtAQACAAoKHhV3YADtAQAAAA==.Grumpywaltz:BAABNQAECn8yAAIdAAoK4xRHFQDTAQAdAAoK4xRHFQDTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECggIEAABNQAECgoKJgAbAK8YAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn87AAIQAAoKHg2rVQC/AQAQAAoKHg2rVQC/AQAAAA==.Halcozigan:BAAANQADCgYIBgAAAA==.Halleko:BAABNQAECn8xAAIGAAoKqiEhIgDPAgAGAAoKqiEhIgDPAgABNQAFFAcIFAAeAIEXAA==.Hammerfoot:BAAANQAECgYIDQAAAA==.Hark:BAAANQAECgQIDAAAAA==.Harkknight:BAABNQAECn8ZAAIcAAkKsha2OwBEAQAcAAkKsha2OwBEAQAAAA==.Haurtrue:BAABNQAECn8iAAIMAAgKnRt2KgCFAgAMAAgKnRt2KgCFAgAAAA==.Hawgbawl:BAABNQAECn9CAAIfAAoKcRp0BgBHAgAfAAoKcRp0BgBHAgAAAA==.Hawgdream:BAABNQAECn8UAAIUAAUKbQrgMAAEAQAUAAUKbQrgMAAEAQAAAA==.',
He='Heliah:BAAANQAECgEIAQAAAA==.Hellequin:BAACNQAFFH8UAAMeAAcKgRc1BAAHAgAeAAYKBxs1BAAHAgAgAAIKUQV6IgBTAAA1AAQKf04AAx4ACgoNJmkEAJADAB4ACgoNJmkEAJADACAACAqLGklKAL0BAAAA.Heyyitzrichh:BAABNQAECn8eAAMUAAkKzCBWJABPAQAQAAcK3h+/ggDfAQAUAAQKLSJWJABPAQAAAA==.',
Ho='Hollinar:BAABNQAECn8WAAILAAkKRwpUzwDnAQALAAkKRwpUzwDnAQAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIBAAAAA==.',
Ic='Icyhõt:BAAANQAECgQIBAAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICwAAAA==.',
In='Invaled:BAAANQAECgUICwAAAA==.',
Io='Ioveless:BAAANQAECgQIBAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQIDAAAAA==.',
It='Itzrich:BAAANQAECgQICAAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAFFAQICgAGAEEeAA==.Jasmirangel:BAABNQAECn8pAAIYAAkKpCRAAgCrAwAYAAkKpCRAAgCrAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDwAAAA==.Jermajesty:BAABNQAECn8tAAINAAoKLRoaQAACAgANAAoKLRoaQAACAgAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgoKFQAJADQTAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8fAAIhAAgKCAwLBACCAQAhAAgKCAwLBACCAQABNQAFFAIIBgAHAPoVAA==.Kankaladin:BAACNQAFFH8KAAIGAAQKQR7NDwD1AAAGAAQKQR7NDwD1AAA1AAQKfywAAgYACgqZIicoACUDAAYACgqZIicoACUDAAAA.Kanky:BAAANQAECgUIBQABNQAFFAQICgAGAEEeAA==.Kano:BAABNQAECn8pAAMIAAoKEhg2NQCkAQAIAAkKVwk2NQCkAQAJAAkK7xcJpwBJAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8eAAIUAAgKNAxOHQCDAQAUAAgKNAxOHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8rAAMiAAoKsx3fHwDMAgAiAAgKhSHfHwDMAgAHAAkKQBLLXwAmAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8wAAICAAoKdxieIQCeAgACAAoKdxieIQCeAgAAAA==.',
Kh='Khory:BAAANQAECggIEAAAAA==.',
Ki='Kichirõ:BAABNQAECn8rAAIEAAoK1AgbGABiAQAEAAoK1AgbGABiAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQADCgMIBAAAAA==.Kimuri:BAAANQAECgEIAQAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICwAVAAAAAA==.',
Ko='Koffee:BAAANQAECggIDgABNQAFFAQICgAGAEEeAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICwAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgoKOAAPAE0SAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggIDAABNQAECgoKLAAFAIsPAA==.Lattemocha:BAABNQAECn8kAAQYAAoKCw/qOQBPAQAYAAcKPAzqOQBPAQAMAAgKOAiEcAAIAQAjAAUKlQbLSACIAAAAAA==.',
Le='Leprechaun:BAABNQAECn8UAAMMAAYKngvccQADAQAMAAYKngvccQADAQAjAAQKeQZIVQBfAAABNQAECggIFAADANYNAA==.Leprechauñ:BAAANQAECgQIDAABNQAECggIFAADANYNAA==.Leprecháun:BAAANQAECgIIAwABNQAECggIFAADANYNAA==.Lepréchaun:BAABNQAECn8UAAMDAAgK1g0LhADwAAADAAcKVg4LhADwAAACAAQKQQ4FmgDZAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAFFAMIBgAPAJAQAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQAECgEIAQAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQABNQAECgoKRQALAGoiAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgUICgAAAA==.Lunatonne:BAABNQAECn8uAAIJAAoKlxvyQACoAgAJAAoKlxvyQACoAgAAAA==.Lunezta:BAAANQADCggICQABNQAECgUIFQAiAGgjAA==.Luneztoprime:BAABNQAECn8VAAIiAAUKaCN2UADSAQAiAAUKaCN2UADSAQAAAA==.Luvlybella:BAAANQAECgQICQAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQAECgEIAQAAAA==.',
Ma='Mafi:BAAANQAECgcIEQAAAA==.Malady:BAAANQADCgcIDwAAAA==.Mallypally:BAAANQAECgMIBAABNQAECgUIEAAVAAAAAA==.Matt:BAACNQAFFH8WAAIYAAYKwxM2BwBjAQAYAAYKwxM2BwBjAQA1AAQKfzYAAhgACgorHLoOAOgCABgACgorHLoOAOgCAAAA.Matte:BAACNQAFFH8IAAICAAQKixf/FgDeAAACAAQKixf/FgDeAAA1AAQKfyoAAwIACgr2GjU2AIYCAAIACgr2GjU2AIYCAAMAAQoAAPVHASoAAAE1AAUUBggWABgAwxMA.Mazza:BAABNQAECn8iAAINAAoKDBvfJACNAgANAAoKDBvfJACNAgAAAA==.',
Me='Meddicus:BAAANQAECgcIDAAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECggIEgAAAA==.',
Mi='Miedillø:BAAANQAFFAEIAQABNQAFFAgINgAIAJQjAA==.Mikeoxmall:BAACNQAFFH8KAAIJAAQKzBoUEAD5AAAJAAQKzBoUEAD5AAA1AAQKfzEAAwkACgoMHs8wANoCAAkACQo5Is8wANoCAAgABgoNDOlOAPMAAAAA.',
Mo='Monstermime:BAABNQAECn8xAAQTAAoKnRUbCQD1AQATAAoKeBQbCQD1AQAQAAcK/w9kxgA+AQAUAAQKmQ4+MQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8pAAIcAAoKRw0AVgCcAQAcAAoKRw0AVgCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgoKMQATAJ0VAA==.',
My='Myserie:BAABNQAECn8fAAIKAAkKKQ7JKgDRAQAKAAkKKQ7JKgDRAQAAAA==.Mystikah:BAAANQADCgMIAwAAAA==.',
Na='Napshade:BAAANQAECgIIAQABNQAECgYIBQAVAAAAAA==.Natsuu:BAAANQAECgUIBgAAAA==.Nazara:BAACNQAFFH8SAAMaAAcKfxY+AQBUAQAaAAcKfxY+AQBUAQASAAMKgwG9EwCYAAA1AAQKfzoAAxoACgpqIA4DAMoCABoACgpqIA4DAMoCABIAAgr1C6xIAF0AAAE1AAQKCAgQABUAAAAA.',
Ne='Neuro:BAABNQAECn9AAAILAAoKdRrDQAA9AgALAAoKdRrDQAA9AgAAAA==.Neyvin:BAAANQADCgIIBQABNQADCggIEAAVAAAAAA==.',
Ni='Nightchaos:BAAANQADCggICAAAAA==.Nightfiress:BAAANQAECgEIBAAAAA==.Nikodemos:BAAANQAFFAcIEgAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICQAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgMIAwAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pa='Pandastyle:BAAANQAECgUIBgAAAA==.',
Pe='Persimmon:BAAANQAECgYICwAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Ph='Philip:BAAANQADCgcIBwAAAA==.Phyona:BAAANQAECgMIAwAAAA==.',
Pi='Piecemaker:BAACNQAFFH8OAAIJAAcKHRpQDQB+AQAJAAcKHRpQDQB+AQA1AAQKf3oAAgkACgr9I3wJADkDAAkACgr9I3wJADkDAAAA.',
Pl='Plaguepapi:BAAANQAECgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proslicer:BAAANQADCggIHgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIEAAAAA==.',
Py='Pyrrah:BAABNQAECn8vAAMNAAkKzCLkHwDwAgANAAkKzCLkHwDwAgAGAAcKhhZlrwDAAQAAAA==.Pyrri:BAAANQAECgQICQABNQAECgkJLwANAMwiAA==.Pyrris:BAAANQAECgEIAQABNQAECgkJLwANAMwiAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn84AAIPAAoKTRK/IABHAgAPAAoKTRK/IABHAgAAAA==.',
Ra='Rabuf:BAABNQAECn8mAAMNAAkK8Bd5UAAqAgANAAkK8Bd5UAAqAgAGAAMKNgioXgFZAAAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8gAAIRAAoKfx0GPQDUAgARAAoKfx0GPQDUAgABNQAFFAYIEwAMAKYQAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAABNQAECn8cAAIeAAoKtxHnDgDLAQAeAAoKtxHnDgDLAQABNQAECgoKOAAPAE0SAA==.Redizle:BAAANQADCggICAABNQAFFAcIFQANAJ8WAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBQAAAA==.',
Rh='Rhaenyr:BAAANQAECgQIDAAAAA==.',
Ri='Ridizle:BAACNQAFFH8VAAINAAcKnxbsBgD7AQANAAcKnxbsBgD7AQA1AAQKf0YAAg0ACgoYIjQLAGcDAA0ACgoYIjQLAGcDAAAA.',
Ro='Rohdoog:BAABNQAECn8dAAIZAAoKRxOzCQDhAQAZAAoKRxOzCQDhAQAAAA==.',
Ru='Runedyu:BAABNQAECn82AAIiAAoKdxmkDwB3AgAiAAoKdxmkDwB3AgAAAA==.',
Ry='Ryanno:BAABNQAECn86AAMJAAoKZCXQBABkAwAJAAoKZCXQBABkAwAIAAcK3QwPQABTAQAAAA==.Ryannoo:BAAANQAECggIDAAAAA==.Ryunosuke:BAAANQAECggIDQABNQAFFAMIBgAPAJAQAA==.',
Sa='Sahomi:BAACNQAFFH8IAAIFAAMKLQrOIgDKAAAFAAMKLQrOIgDKAAA1AAQKfysAAwUACgqtESlSAC0CAAUACgqtESlSAC0CABYABAqYAmAcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIDQAAAA==.Sarcini:BAABNQAECn8pAAIkAAoKjBzRDQA6AgAkAAoKjBzRDQA6AgAAAA==.Sarcisse:BAAANQAECgcIDwAAAA==.Satrina:BAABNQAECn8xAAMiAAoKJx5BDwB+AgAiAAoKJx5BDwB+AgAHAAIKAACklQBqAAAAAA==.Savvy:BAABNQAECn8yAAICAAoKDRuDSQA8AgACAAoKDRuDSQA8AgAAAA==.',
Se='Senaren:BAAANQAECggIAgAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECggICQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAAVAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwAVAAAAAA==.Shameonyou:BAAANQAECgQIBgAAAA==.Shocka:BAAANQADCgYIBgAAAA==.Shockling:BAAANQADCgcICQAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8JAAICAAQKKgf/GgDCAAACAAQKKgf/GgDCAAA1AAQKfywAAgIACgo1Gm8/AAECAAIACgo1Gm8/AAECAAAA.Souchong:BAAANQADCgMIAwABNQAECgoKLAAFAIsPAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn84AAIJAAoKRhjDSgAmAgAJAAoKRhjDSgAmAgAAAA==.',
St='Stanleyy:BAAANQAFFAIIAgAAAA==.Steroidrage:BAAANQAECgEIAQAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggICQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAABNQAECn8cAAIGAAkKqBhRUQAnAgAGAAkKqBhRUQAnAgAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIXAAMKKCFmAgAdAQAXAAMKKCFmAgAdAQA1AAQKfx8AAxcACQrwIhYDAD0DABcACQrwIhYDAD0DAA4AAQr5B++WAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAwABNQAECggIEAAVAAAAAA==.',
Th='Thedarkduke:BAABNQAECn8eAAIXAAkKvxJFDgBMAQAXAAkKvxJFDgBMAQAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECgkJHgAXAL8SAA==.Thefallen:BAAANQAECgEIAQAAAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQAECgEIAQAAAA==.Thorin:BAAANQAECggIDwABNQAFFAIIAgAVAAAAAA==.Thud:BAAANQAECggICwAAAA==.',
Ti='Tidalwave:BAABNQAECn8gAAICAAgKDCBKIgDeAgACAAgKDCBKIgDeAgAAAA==.Timmeh:BAAANQAECgcIDAAAAA==.Tindra:BAAANQAECggIEwAAAA==.Tissue:BAABNQAECn9FAAIOAAoKtw+NJgDCAQAOAAoKtw+NJgDCAQAAAA==.Titanius:BAABNQAECn8dAAIGAAoKkhvHOQBwAgAGAAoKkhvHOQBwAgABNQAECggIEAAVAAAAAA==.',
To='Tobibi:BAABNQAECn8iAAISAAoK8yEvBQBZAwASAAoK8yEvBQBZAwABNQAFFAIIAgAVAAAAAA==.Tolip:BAABNQAECn8bAAQlAAkKBw9QGwBNAQAlAAYKSxBQGwBNAQAYAAYKDgghUQCgAAAMAAEK7ALxwwAeAAAAAA==.Tolipally:BAAANQADCgYICwABNQAECgkJGwAlAAcPAA==.Tolipicious:BAAANQADCgYIBgABNQAECgkJGwAlAAcPAA==.Tollock:BAAANQADCggIFAABNQAECgkJGwAlAAcPAA==.Topsykret:BAAANQADCgcICQAAAA==.Topsyy:BAAANQADCggIEQAAAA==.Torpse:BAAANQAECgcJDgABNQAFFAQICAAMAAUYAA==.Torrick:BAAANQADCgQIBAAAAA==.',
Tr='Trevórg:BAAANQAECgUJDwAAAA==.',
Ts='Tsarrubus:BAABNQAECn8tAAIOAAoKnAh5RwCNAQAOAAoKnAh5RwCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMIDwAAAA==.',
Ul='Ulg:BAABNQAECn82AAMRAAoKMiKLJAAmAwARAAoKLiGLJAAmAwAfAAYK0RyKDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgoKNgARADIiAA==.',
Uw='Uwantmebad:BAAANQADCgQIBAAAAA==.',
Va='Valkyl:BAAANQADCgQIBwAAAA==.Valkyll:BAAANQADCgQIBAAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgUIBgAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn80AAMXAAoKwBkQCAB7AgAXAAoKwBkQCAB7AgAPAAQKZg/TMgDuAAAAAA==.',
We='Weave:BAABNQAECn8XAAImAAoKrg3WEQDUAQAmAAoKrg3WEQDUAQABNQAFFAYIFgAYAMMTAA==.Wellerman:BAAANQAECgcIEAAAAA==.Wercsmage:BAAANQAECgEIAQAAAA==.',
Wh='Whet:BAAANQADCgYIBgABNQADCgMIAwAVAAAAAA==.Whohaveaggro:BAAANQAECgEIAQAAAA==.',
Wi='Willpew:BAAANQAECgYIBwAAAA==.Wino:BAAANQAECgcIDgAAAA==.Wiqui:BAABNQAECn8lAAIJAAoKwBgsbADPAQAJAAoKwBgsbADPAQAAAA==.',
Wo='Wolfonk:BAABNQAECn8uAAInAAoKswpKMACVAQAnAAoKswpKMACVAQAAAA==.',
Wt='Wtfiainamonk:BAAANQAECgMIAwAAAA==.',
Wu='Wuhshake:BAABNQAECn8xAAICAAkK9CP/DABYAwACAAkK9CP/DABYAwAAAA==.Wuhshank:BAAANQAECgUICgAAAA==.',
['Wë']='Wërrcs:BAABNQAECn8dAAIDAAoKhgi8aAA1AQADAAoKhgi8aAA1AQAAAA==.',
Xe='Xemo:BAABNQAECn88AAIGAAkKpBORgQC1AQAGAAkKpBORgQC1AQAAAA==.Xenophics:BAACNQAFFH8KAAIGAAcKmAi2EABCAQAGAAcKmAi2EABCAQA1AAQKf0AAAgYACgrHJBgtABQDAAYACgrHJBgtABQDAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAABNQAECn8XAAINAAYKEhz+aADcAQANAAYKEhz+aADcAQAAAA==.Zall:BAACNQAFFH8WAAInAAcKUBnYAwCQAQAnAAcKUBnYAwCQAQA1AAQKfy4AAycACgqDH4EPAFACACcACgqDH4EPAFACACYAAgqLE6dDAGAAAAAA.Zamos:BAAANQAECgUIEwAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zenshin:BAAANQAECgEIAQAAAA==.Zentaur:BAABNQAECn8xAAIEAAoKJA64FACYAQAEAAoKJA64FACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8uAAMfAAoKDhduEwBpAQARAAoKEBWPegAoAgAfAAYKmhJuEwBpAQABNQAFFAIIBgAHAPoVAA==.',
Zo='Zontar:BAAANQAECgQICwAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
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
