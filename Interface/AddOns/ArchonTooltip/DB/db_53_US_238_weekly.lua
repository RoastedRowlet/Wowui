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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Mage-Arcane','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Arms','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Priest-Discipline','DemonHunter-Vengeance','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','DeathKnight-Unholy','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Mage-Fire','Druid-Guardian','Paladin-Protection','Monk-Mistweaver','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aayrawn:BAABNQAECn87AAMBAAoKGCDaDACgAgABAAoKGCDaDACgAgACAAMK/AtpwQCWAAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgoKFgADALkcAA==.Acesdruid:BAAANQAECgYICwABNQAECgoKFgADALkcAA==.Aceshaman:BAABNQAECn8WAAMDAAoKuRxITQBBAgADAAgKNRxITQBBAgABAAkKtxc2FwD1AQAAAA==.',
Ai='Airone:BAAANQAECgUIBwAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgoKMAAEACohAA==.Alluriel:BAAANQADCgIIAgAAAA==.Alucard:BAABNQAECn8iAAIFAAoKqB0aQQBnAgAFAAoKqB0aQQBnAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8pAAIGAAgKJQ+otgCxAQAGAAgKJQ+otgCxAQAAAA==.',
An='Antijastran:BAABNQAECn8vAAIHAAkKZAqcSwCLAQAHAAkKZAqcSwCLAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMIAAkKth47EADnAgAIAAkKnB47EADnAgAJAAEK/CBARQFUAAAAAA==.Aquda:BAAANQAECgEIAQAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgMIAwAAAA==.',
As='Ashbringer:BAABNQAECn9GAAIGAAoKIya+BADTAwAGAAoKIya+BADTAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAABNQAECn8sAAMFAAoKiw/kVgDhAQAFAAoKiw/kVgDhAQAKAAEKEA7UXgA9AAAAAA==.',
Ba='Baladoria:BAABNQAECn8pAAIFAAoKYBW4ZADyAQAFAAoKYBW4ZADyAQAAAA==.Baldkrank:BAABNQAECn8cAAILAAkKEgwA4wDDAQALAAkKEgwA4wDDAQAAAA==.Bama:BAAANQAECggIDAAAAA==.Bananabowman:BAABNQAECn8eAAIJAAoKXB5OHgAeAwAJAAoKXB5OHgAeAwAAAA==.Banditos:BAAANQAECgcIDQAAAA==.Bartab:BAABNQAECn81AAICAAoKgR9GKwC2AgACAAoKgR9GKwC2AgABNQAECgoKKgAMAEwRAA==.',
Be='Bearemy:BAAANQAECgQIBQABNQAECgoKLQANAC0aAA==.Beastling:BAABNQAECn8dAAIJAAkKBA/zdADVAQAJAAkKBA/zdADVAQAAAA==.Beau:BAACNQAFFH8KAAIOAAUK/xIuDwDUAAAOAAUK/xIuDwDUAAA1AAQKf1AAAg4ACgo1I4UKAFwDAA4ACgo1I4UKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAUICgAOAP8SAA==.Bestia:BAAANQAFFAMIAwABNQAFFAMIBgAPAJAQAA==.Bettyßrisco:BAABNQAECn88AAIJAAoKPSDxIAC7AgAJAAoKPSDxIAC7AgAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCggIDwAAAA==.',
Bo='Bombur:BAABNQAECn8nAAIQAAkKzA82hgBSAQAQAAkKzA82hgBSAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECgkJHAARAP4eAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAcIFgASAPgXAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAIALYeAA==.Brëtski:BAAANQAECggIDwAAAA==.',
Bu='Bubagony:BAABNQAECn8zAAQTAAoK3yDsAQDgAgATAAoKAR/sAQDgAgAQAAoKTBUTTQDtAQAUAAIKpBwEGgCTAAABNQAFFAYIEwAMAKYQAA==.Buca:BAAANQAFFAEIAQABNQAFFAYIEwAMAKYQAA==.Burakku:BAAANQAECgEIAQABNQAFFAUIDgADAFsVAA==.Buzza:BAABNQAECn8VAAIRAAYK+wa29wDuAAARAAYK+wa29wDuAAAAAA==.Buzzkill:BAABNQAECn8pAAIQAAoKmhiHMABNAgAQAAoKmhiHMABNAgAAAA==.',
Ca='Calinash:BAABNQAECn88AAILAAoKcRphTwAiAgALAAoKcRphTwAiAgAAAA==.Calzraxx:BAABNQAECn8aAAIRAAcK8hZGkwDsAQARAAcK8hZGkwDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECgkJHAARAP4eAA==.',
Cc='Ccaan:BAAANQAECggIEwAAAA==.',
Ce='Celinn:BAABNQAECn8tAAIFAAoKExi3TwA1AgAFAAoKExi3TwA1AgAAAA==.',
Ch='Charliek:BAABNQAECn8XAAIRAAgK1A4aqAC5AQARAAgK1A4aqAC5AQAAAA==.Cheebah:BAAANQAECgMIBAAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhxaIgDeAgACAAkKXhxaIgDeAgADAAUKdxq5tQAnAQAAAA==.Chingoblingo:BAAANQADCggIGgAAAA==.Chorr:BAAANQAECgIIAgABNQAECggIEAAVAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECgkJHAARAP4eAA==.',
Cr='Crates:BAABNQAECn8cAAIRAAkK/h4lNwBjAgARAAkK/h4lNwBjAgAAAA==.Cringely:BAABNQAECn8mAAQFAAoKtSELCwBqAwAFAAoKtSELCwBqAwAWAAIK9BoVGgCaAAAKAAEKAABWlwAJAAAAAA==.Crispratadin:BAAANQAECgQIBAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAXACghAA==.Crosswalkk:BAAANQAECgIIAwAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAAVAAAAAA==.',
Cu='Curonconagua:BAAANQAECgEIAQAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAwAAAA==.',
Da='Daktok:BAAANQAECgUIBgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIKAABNQAECgUICQAVAAAAAA==.',
De='Deathfortres:BAABNQAECn87AAMYAAoKQRQrFwBiAgAYAAoKQRQrFwBiAgAMAAYKCwWpewDdAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAACNQAFFH8GAAMPAAMKkBAmDgB6AAAPAAMKXgsmDgB6AAAOAAEKPRgPHQBEAAA1AAQKfzcAAw4ACgr6IuMOAC0DAA4ACgr6IuMOAC0DAA8ACArsFCAmABUCAAAA.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8IAAIPAAQKaRSXCgApAQAPAAQKaRSXCgApAQA1AAQKfxkAAg8ACQpSGh8XAKYCAA8ACQpSGh8XAKYCAAAA.Denaric:BAAANQADCggICgAAAA==.Dethsoul:BAAANQAECgMIAwAAAA==.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAABNQAECn8nAAIPAAoKsB6oDAAYAwAPAAoKsB6oDAAYAwAAAA==.',
Do='Dontar:BAAANQAECgUIBgAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAABNQAECn8YAAIBAAgK+RbAEwDbAQABAAgK+RbAEwDbAQABNQABCgQIBAAVAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8WAAISAAcK+BfqBgAZAgASAAcK+BfqBgAZAgA1AAQKf04ABBIACgrCGZ0XAEACABIACgrCGZ0XAEACABkACArFE3YHAMcBABoACQr/FG4LAKsBAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Drâx:BAAANQAECgcIBwAAAA==.Dríppy:BAAANQAECgQICwAAAA==.',
Ed='Edrian:BAAANQADCgcIBwAAAA==.',
Ei='Eilerra:BAABNQAECn8tAAMbAAoK7RyPCQAPAgAbAAkK7RyPCQAPAgALAAgKSxIr/wCPAQAAAA==.',
Er='Erre:BAABNQAECn83AAIQAAoKcR+ALwDJAgAQAAoKcR+ALwDJAgAAAA==.',
Ex='Exxitwound:BAAANQADCggIGAAAAA==.',
Fa='Falc:BAAANQAFFAMIAwABNQAFFAoKGwADAC8fAA==.Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgMIBAAAAA==.Firesson:BAABNQAECn8aAAILAAkKPQJKEgGWAAALAAkKPQJKEgGWAAAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgUIDAAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgUIBwABNQAECgoKJgAFALUhAA==.',
Fr='Fritark:BAABNQAECn8vAAMHAAkKmhj7NQABAgAHAAkKBxf7NQABAgAcAAQKNBegfQADAQAAAA==.Fritzyp:BAAANQAECggICwABNQAECgkJLwAHAJoYAA==.Frostyburn:BAAANQAECgIIBAAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQAECgMIBAAAAA==.Geörge:BAACNQAFFH8PAAIKAAYKhxdsBwCgAQAKAAYKhxdsBwCgAQA1AAQKf04AAgoACgqvJAEFAIgDAAoACgqvJAEFAIgDAAAA.',
Go='Goated:BAABNQAECn8vAAMdAAoKaSU2BwCDAgAdAAgKvyU2BwCDAgARAAoKvSEWRgAuAgAAAA==.',
Gr='Gremfrost:BAABNQAECn8rAAIbAAoKSxUNCgAEAgAbAAoKSxUNCgAEAgAAAA==.Grotelek:BAABNQAECn8uAAICAAoKHhV3YADtAQACAAoKHhV3YADtAQAAAA==.Grumpywaltz:BAABNQAECn8yAAIdAAoK4xRHFQDTAQAdAAoK4xRHFQDTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAABNQAECn8aAAIeAAoK+BIENABSAQAeAAoK+BIENABSAQABNQAECgoKLQAbAO0cAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn87AAIQAAoKHg05XQC9AQAQAAoKHg05XQC9AQAAAA==.Halcozigan:BAAANQADCgYIBgAAAA==.Halleko:BAABNQAECn8xAAIGAAoKqiFTJwDEAgAGAAoKqiFTJwDEAgABNQAFFAcIFAAfAIEXAA==.Hammerfoot:BAAANQAECgYIDQAAAA==.Hark:BAAANQAECgQIDAAAAA==.Harkknight:BAABNQAECn8ZAAIcAAkKshZQTADFAQAcAAkKshZQTADFAQAAAA==.Haurtrue:BAABNQAECn8iAAIMAAgKnRt2KgCFAgAMAAgKnRt2KgCFAgAAAA==.Hawgbawl:BAABNQAECn9HAAIgAAoKaxstBgBnAgAgAAoKaxstBgBnAgAAAA==.Hawgdream:BAABNQAECn8UAAIUAAUKbQrgMAAEAQAUAAUKbQrgMAAEAQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFH8UAAMfAAcKgRc1BAAHAgAfAAYKBxs1BAAHAgAhAAIKUQV/JQBTAAA1AAQKf1cAAx8ACgoxJvUBAEYDAB8ACgoxJvUBAEYDACEACAqLGnJSALsBAAAA.Heyyitzrichh:BAABNQAECn8eAAMUAAkKzCBWJABPAQAQAAcK3h+/ggDfAQAUAAQKLSJWJABPAQAAAA==.',
Ho='Hollinar:BAABNQAECn8WAAILAAkKRwpUzwDnAQALAAkKRwpUzwDnAQAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ic='Icyhõt:BAAANQAECgQIBAAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICwAAAA==.',
In='Invaled:BAAANQAECgUICAAAAA==.',
Io='Ioveless:BAAANQAECgQIBAAAAA==.',
Ip='Ipeggoodboys:BAAANQADCgEIAQAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQICwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAFFAQICgAGAEEeAA==.Jasmirangel:BAABNQAECn8zAAIYAAoKmyRAAgCrAwAYAAoKmyRAAgCrAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECn8tAAINAAoKLRrQRQD8AQANAAoKLRrQRQD8AQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgoKFQAJADQTAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8fAAIiAAgKCAwLBACCAQAiAAgKCAwLBACCAQABNQAFFAIIBgAHAPoVAA==.Kankaladin:BAACNQAFFH8KAAIGAAQKQR6LEgDwAAAGAAQKQR6LEgDwAAA1AAQKfywAAgYACgqZIicoACUDAAYACgqZIicoACUDAAAA.Kanky:BAAANQAECgUIBQABNQAFFAQICgAGAEEeAA==.Kano:BAABNQAECn8pAAMIAAoKEhg2NQCkAQAIAAkKVwk2NQCkAQAJAAkK7xcPtQCaAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8eAAIUAAgKNAxOHQCDAQAUAAgKNAxOHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8rAAMeAAoKsx3fHwDMAgAeAAgKhSHfHwDMAgAHAAkKQBLLXwAmAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8wAAICAAoKdxgiJgCXAgACAAoKdxgiJgCXAgAAAA==.',
Kh='Khory:BAAANQAECggIEAAAAA==.',
Ki='Kichirõ:BAABNQAECn8rAAIEAAoK1AgbGABiAQAEAAoK1AgbGABiAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQADCgMIBAAAAA==.Kimuri:BAAANQAECgEIAQAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICwAVAAAAAA==.',
Ko='Koffee:BAAANQAECggIDQABNQAFFAQICgAGAEEeAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICwAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgoKOAAPAE0SAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggIDQABNQAECgoKLAAFAIsPAA==.Lattemocha:BAABNQAECn8kAAQYAAoKCw/qOQBPAQAYAAcKPAzqOQBPAQAMAAgKOAiEcAAIAQAjAAUKlQaNTQCIAAAAAA==.',
Le='Leprechaun:BAABNQAECn8UAAMMAAYKngvccQADAQAMAAYKngvccQADAQAjAAQKeQZeWgBfAAABNQAECggIFAADANYNAA==.Leprechauñ:BAAANQAECgQICgABNQAECggIFAADANYNAA==.Leprecháun:BAAANQAECgIIAwABNQAECggIFAADANYNAA==.Lepréchaun:BAABNQAECn8UAAMDAAgK1g3IjQDwAAADAAcKVg7IjQDwAAACAAQKQQ55ogDZAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAFFAMIBgAPAJAQAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQABNQAECgoKSwALAC8kAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgUIBgAAAA==.Lunatonne:BAABNQAECn8zAAIJAAoK7hxPJQCqAgAJAAoK7hxPJQCqAgAAAA==.Lunezta:BAAANQADCggICQABNQAECgUIFQAeAGgjAA==.Luneztoprime:BAABNQAECn8VAAIeAAUKaCN2UADSAQAeAAUKaCN2UADSAQAAAA==.Luvlybella:BAAANQAECgQICAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgcIEQAAAA==.Malady:BAAANQADCggIEQAAAA==.Maleficence:BAAANQADCgUIBgAAAA==.Mallypally:BAAANQAECgMIAwABNQAECgUIDQAVAAAAAA==.Matt:BAACNQAFFH8XAAIYAAcK4BEKBgCtAQAYAAcK4BEKBgCtAQA1AAQKfzYAAhgACgorHLoOAOgCABgACgorHLoOAOgCAAAA.Matte:BAACNQAFFH8IAAICAAQKixe6GQDcAAACAAQKixe6GQDcAAA1AAQKfyoAAwIACgr2GjU2AIYCAAIACgr2GjU2AIYCAAMAAQoAAPVHASoAAAE1AAUUBwgXABgA4BEA.Mazza:BAABNQAECn8iAAINAAoKDBsdKQCFAgANAAoKDBsdKQCFAgAAAA==.',
Me='Meddicus:BAAANQAECgcICgAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECggIEAAAAA==.',
Mi='Miedillø:BAAANQAFFAEIAQABNQAFFAgIOAAIAJQjAA==.Mikeoxmall:BAACNQAFFH8KAAIJAAQKzBq/EgD1AAAJAAQKzBq/EgD1AAA1AAQKfzEAAwkACgoMHs8wANoCAAkACQo5Is8wANoCAAgABgoNDOlOAPMAAAAA.',
Mo='Monstermime:BAABNQAECn8xAAQTAAoKnRUbCQD1AQATAAoKeBQbCQD1AQAQAAcK/w9kxgA+AQAUAAQKmQ4+MQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8pAAIcAAoKRw0AVgCcAQAcAAoKRw0AVgCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgoKMQATAJ0VAA==.',
My='Myserie:BAABNQAECn8fAAIKAAkKKQ7JKgDRAQAKAAkKKQ7JKgDRAQAAAA==.Mystikah:BAAANQADCgMIAwAAAA==.',
Na='Napshade:BAAANQAECgEIAQABNQAECgYIBQAVAAAAAA==.Natsuu:BAAANQAECgQIBQAAAA==.Nazara:BAACNQAFFH8SAAMaAAcKfxaHAQBGAQAaAAcKfxaHAQBGAQASAAMKgwG9EwCYAAA1AAQKfzoAAxoACgpqIFcDAMgCABoACgpqIFcDAMgCABIAAgr1C6xIAF0AAAE1AAQKCAgQABUAAAAA.',
Ne='Neuro:BAABNQAECn9AAAILAAoKdRp2RgA6AgALAAoKdRp2RgA6AgAAAA==.Neyvin:BAAANQADCgIIBQABNQADCggIEAAVAAAAAA==.',
Ni='Nightchaos:BAAANQADCggICgAAAA==.Nightfiress:BAAANQAECgEIAwAAAA==.Nikodemos:BAAANQAFFAcIFAAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgMIAgAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pa='Pandastyle:BAAANQAECgUIBQAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Ph='Philip:BAAANQADCgcIBwAAAA==.Phyona:BAAANQAECgMIAwAAAA==.',
Pi='Piecemaker:BAACNQAFFH8OAAIJAAcKHRpQDQB+AQAJAAcKHRpQDQB+AQA1AAQKf3oAAgkACgr9I1kLADIDAAkACgr9I1kLADIDAAAA.',
Pl='Plaguepapi:BAAANQAECgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proslicer:BAAANQADCggIHgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIDwAAAA==.',
Py='Pyrrah:BAABNQAECn8vAAMNAAkKzCLkHwDwAgANAAkKzCLkHwDwAgAGAAcKhhZlrwDAAQAAAA==.Pyrri:BAAANQAECgQICQABNQAECgkJLwANAMwiAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn84AAIPAAoKTRK/IABHAgAPAAoKTRK/IABHAgAAAA==.',
Ra='Rabuf:BAABNQAECn8mAAMNAAkK8Bd5UAAqAgANAAkK8Bd5UAAqAgAGAAMKNgi/bgFZAAAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8gAAIRAAoKfx0GPQDUAgARAAoKfx0GPQDUAgABNQAFFAYIEwAMAKYQAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAABNQAECn8cAAIfAAoKtxETEADGAQAfAAoKtxETEADGAQABNQAECgoKOAAPAE0SAA==.Redizle:BAAANQADCggICAABNQAFFAcIFQANAJ8WAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgQIDAAAAA==.',
Ri='Ridizle:BAACNQAFFH8VAAINAAcKnxbsBgD7AQANAAcKnxbsBgD7AQA1AAQKf0cAAg0ACgoeIg0MAGkDAA0ACgoeIg0MAGkDAAAA.',
Ro='Rohdoog:BAABNQAECn8gAAIZAAoKRxOzCQDhAQAZAAoKRxOzCQDhAQAAAA==.',
Ru='Runedyu:BAABNQAECn87AAIeAAoKbxwKDQCpAgAeAAoKbxwKDQCpAgAAAA==.',
Ry='Ryanno:BAABNQAECn9AAAMJAAoKZCWTBQBhAwAJAAoKZCWTBQBhAwAIAAcK3QwPQABTAQAAAA==.Ryannoo:BAAANQAECggICgAAAA==.Ryunosuke:BAAANQAECggIDAABNQAFFAMIBgAPAJAQAA==.',
Sa='Sahomi:BAACNQAFFH8JAAIFAAQK3wfOIgDKAAAFAAQK3wfOIgDKAAA1AAQKfysAAwUACgqtESlSAC0CAAUACgqtESlSAC0CABYABAqYAmAcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggICgAAAA==.Sarcini:BAABNQAECn8pAAIkAAoKjBxJDwA1AgAkAAoKjBxJDwA1AgAAAA==.Sarcisse:BAAANQAECgcIDgAAAA==.Satrina:BAABNQAECn8xAAMeAAoKJx7AEAB5AgAeAAoKJx7AEAB5AgAHAAIKAACklQBqAAAAAA==.Savvy:BAABNQAECn8zAAICAAoKDRuDSQA8AgACAAoKDRuDSQA8AgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECggICQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAAVAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwAVAAAAAA==.Shameonyou:BAAANQAECgQIBAAAAA==.Shocka:BAAANQADCgYIBgAAAA==.Shockling:BAAANQAECggICAAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8KAAICAAUKXQbjFwDyAAACAAUKXQbjFwDyAAA1AAQKfywAAgIACgo1Gq5FAP0BAAIACgo1Gq5FAP0BAAAA.Souchong:BAAANQADCgMIAwABNQAECgoKLAAFAIsPAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn84AAIJAAoKRhjVUwAkAgAJAAoKRhjVUwAkAgAAAA==.',
St='Stanleyy:BAABNQAECn8ZAAIlAAoK+hz/BQA0AwAlAAoK+hz/BQA0AwAAAA==.Steroidrage:BAAANQAECgEIAQAAAA==.Stormtwist:BAAANQADCgYIBgAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggICQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAABNQAECn8cAAIGAAkKqBgrWgAhAgAGAAkKqBgrWgAhAgAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIXAAMKKCFmAgAdAQAXAAMKKCFmAgAdAQA1AAQKfx8AAxcACQrwIhYDAD0DABcACQrwIhYDAD0DAA4AAQr5B++WAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECggIEAAVAAAAAA==.',
Th='Thedarkduke:BAABNQAECn8eAAIXAAkKvxKXDwBNAQAXAAkKvxKXDwBNAQAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECgkJHgAXAL8SAA==.Thefallen:BAAANQAECgEIAQAAAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECggIDAABNQAECgoKGQAlAPocAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECn8gAAICAAgKDCBKIgDeAgACAAgKDCBKIgDeAgAAAA==.Timmeh:BAAANQAECggICgAAAA==.Tindra:BAAANQAECggIDwAAAA==.Tissue:BAABNQAECn9FAAIOAAoKtw8cKgC+AQAOAAoKtw8cKgC+AQAAAA==.Titanius:BAABNQAECn8hAAIGAAoKwR18NgCLAgAGAAoKwR18NgCLAgABNQAECggIEAAVAAAAAA==.',
To='Tobibi:BAABNQAECn8iAAISAAoK8yEvBQBZAwASAAoK8yEvBQBZAwABNQAECgoKGQAlAPocAA==.Tolip:BAABNQAECn8bAAQmAAkKBw9QGwBNAQAmAAYKSxBQGwBNAQAYAAYKDghAVgCgAAAMAAEK7ALxwwAeAAAAAA==.Tolipally:BAAANQADCgYICwABNQAECgkJGwAmAAcPAA==.Tolipicious:BAAANQADCgYIBgABNQAECgkJGwAmAAcPAA==.Tollock:BAAANQADCggIFAABNQAECgkJGwAmAAcPAA==.Topsykret:BAAANQADCgcICQAAAA==.Topsyy:BAAANQADCggIEQAAAA==.Torpse:BAAANQAECgcIDAABNQAFFAQICAAMAAUYAA==.Torrick:BAAANQADCgQIBAAAAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECn8tAAIOAAoKnAh5RwCNAQAOAAoKnAh5RwCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMICwAAAA==.',
Ul='Ulg:BAABNQAECn82AAMRAAoKMiKLJAAmAwARAAoKLiGLJAAmAwAgAAYK0RyKDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgoKNgARADIiAA==.',
Uw='Uwantmebad:BAAANQADCgQIBAAAAA==.',
Va='Valkyl:BAAANQADCgQIBwAAAA==.Valkyll:BAAANQADCgQIBAAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgUIBgAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn80AAMXAAoKwBkQCAB7AgAXAAoKwBkQCAB7AgAPAAQKZg8bNgDqAAAAAA==.',
We='Weave:BAABNQAECn8XAAIlAAoKrg2pEwDMAQAlAAoKrg2pEwDMAQABNQAFFAcIFwAYAOARAA==.Wellerman:BAAANQAECgcIDAAAAA==.Wercsmage:BAAANQAECgEIAQAAAA==.',
Wh='Whet:BAAANQADCgYIBgABNQADCgMIAwAVAAAAAA==.Whohaveaggro:BAAANQAECgYIBwAAAA==.',
Wi='Willpew:BAAANQAECgYIBgAAAA==.Wino:BAAANQAECggIDgAAAA==.Wiqui:BAABNQAECn8nAAIJAAoKwBgYewAYAgAJAAoKwBgYewAYAgAAAA==.',
Wo='Wolfonk:BAABNQAECn8uAAInAAoKswpKMACVAQAnAAoKswpKMACVAQAAAA==.',
Wt='Wtfiainamonk:BAAANQAECgMIAwAAAA==.',
Wu='Wuhshake:BAABNQAECn8xAAICAAkK9CP/DABYAwACAAkK9CP/DABYAwAAAA==.Wuhshank:BAAANQAECgUICgAAAA==.',
['Wë']='Wërrcs:BAABNQAECn8dAAIDAAoKhgh7cQA0AQADAAoKhgh7cQA0AQAAAA==.',
Xe='Xemo:BAABNQAECn9GAAIGAAkKSBS4hADDAQAGAAkKSBS4hADDAQAAAA==.Xenophics:BAACNQAFFH8KAAIGAAcKmAi2EABCAQAGAAcKmAi2EABCAQA1AAQKf0IAAgYACgrHJBgtABQDAAYACgrHJBgtABQDAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFH8WAAInAAcKUBnSBACJAQAnAAcKUBnSBACJAQA1AAQKfzEAAycACgqxH0IQAFgCACcACgqxH0IQAFgCACUAAgqLE6dDAGAAAAAA.Zamos:BAAANQAECgUIDgAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zenshin:BAAANQAECgIIAgAAAA==.Zentaur:BAABNQAECn8xAAIEAAoKJA64FACYAQAEAAoKJA64FACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8vAAMgAAoKDhduEwBpAQARAAoKEBWPegAoAgAgAAYKmhJuEwBpAQABNQAFFAIIBgAHAPoVAA==.',
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
