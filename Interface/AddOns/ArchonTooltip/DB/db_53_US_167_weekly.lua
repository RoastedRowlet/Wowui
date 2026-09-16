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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Warrior-Arms','Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Rogue-Subtlety','Warlock-Demonology','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Mage-Arcane','Mage-Frost','Druid-Feral','Monk-Brewmaster','DeathKnight-Blood','Monk-Mistweaver','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Havoc','Druid-Balance',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abeblinken:BAAANQABCgIIAgAAAA==.Abrigo:BAAANQAECgQICAAAAA==.',
Ae='Aesbop:BAAANQAECgQICAAAAA==.Aetherlight:BAACNQAFFIEFAAIBAAMJYxFjCAD6AAABAAMJYxFjCAD6AAA1AAQKgSEABAEACQm8It0QAMICAAEACQlYIt0QAMICAAIACAmBFx8PAHkCAAMAAgmJIx0PAK0AAAAA.',
Ai='Ais:BAAANQADCgYIBgAAAA==.',
Al='Alaanz:BAAANQADCgYIEAAAAA==.Alpharatz:BAAANQAECgYICgAAAA==.',
Am='Amonamarth:BAABNQAECoEZAAIEAAgJthVDPwA4AgAEAAgJthVDPwA4AgAAAA==.Amunwrath:BAAANQAECgUICQAAAA==.',
An='Anatharion:BAAANQAECgcIEAAAAA==.Angrybao:BAAANQABCgYICAAAAA==.Annari:BAAANQAECgYIDgAAAA==.Anéantir:BAAANQAECgUICAAAAA==.',
Ao='Aozeraa:BAAANQAECgYIDQAAAA==.',
Ap='Apostate:BAAANQAECgIIAwABNQAECgYIDQAFAAAAAA==.',
Aq='Aquadond:BAAANQADCgcICwABNQAECgcIEwAFAAAAAQ==.',
Ar='Arakh:BAAANQADCgYIBgAAAA==.Arakhe:BAAANQADCgYIBgAAAA==.Arbaal:BAAANQAECgQICwAAAA==.Artemais:BAABNQAECoEdAAMGAAkJPRp0FwAWAgAGAAgJrBV0FwAWAgAHAAYJyBcwUQC1AQAAAA==.',
As='Asaki:BAAANQADCgIIAgAAAA==.Asarmaul:BAAANQADCggIFgAAAA==.',
At='Atalanthya:BAAANQADCggICAABNQAECgcIFwACAEoSAA==.',
Av='Avanoria:BAAANQADCgQIBAAAAA==.Avein:BAAANQADCgQIBgAAAA==.',
Aw='Awesomeaf:BAAANQAECgEIAQABNQAECgkJGQAHAN4jAA==.',
Az='Azernaut:BAAANQADCgYIBgAAAA==.Azgarth:BAAANQAECgIIAgABNQAECgQIBgAFAAAAAA==.Azureky:BAAANQAECgIIBAAAAA==.Azuresham:BAAANQADCgYIBgAAAA==.Azuric:BAAANQAECgMIAwAAAA==.',
Ba='Babytear:BAAANQAECgQICAAAAA==.Badfelix:BAABNQAECoEaAAMIAAkJ8hGfLQAHAgAIAAkJ8hGfLQAHAgAJAAYJggWuaAATAQAAAA==.Baldrsonn:BAAANQAECgEIAQAAAA==.Balenciaga:BAAANQADCgcICQAAAA==.Bambuzzo:BAAANQAECgYIEQAAAA==.Barbrawr:BAAANQAECgIIBAAAAA==.Bawr:BAAANQADCggICAAAAA==.',
Bd='Bdft:BAAANQADCgcIBwAAAA==.',
Be='Bearlee:BAAANQADCgIIAgAAAA==.Beautyboy:BAAANQAECgQIBwAAAA==.Beefdip:BAAANQAECgQIBAAAAA==.Benbear:BAAANQADCgQIBQAAAA==.',
Bg='Bgneedwork:BAAANQAECgUICAAAAA==.',
Bi='Billidari:BAAANQAECgUIBwABNQAECgkJIQAKALgcAA==.Bixby:BAAANQAECgQIBAAAAA==.',
Bl='Blachdeath:BAAANQAECgEIAQAAAA==.Blazedin:BAAANQAECgYIEAAAAA==.Bleumachine:BAAANQADCgEIAQAAAA==.',
Bo='Boeds:BAAANQAECgQIBQAAAA==.Bokrim:BAAANQAECgQICgAAAA==.',
Br='Brawns:BAAANQABCgYIDAABNQAECgkJGwALAEgiAA==.Braér:BAAANQADCgcIBwAAAA==.Brisktwo:BAAANQAECgEIAQAAAA==.Brujo:BAAANQAECgQIBAABNQAECgkJHQAGAD0aAA==.Brutalious:BAABNQAECoEcAAMMAAkJmiIcBABRAwAMAAkJXCAcBABRAwANAAgJXSOdDAAHAwAAAA==.Bryxie:BAAANQADCgYIBgABNQADCgYIBgAFAAAAAA==.',
Bu='Bubbes:BAAANQAECgMIAwAAAA==.Bubblebeåm:BAABNQAECoEYAAIOAAgJJRwqFQC2AgAOAAgJJRwqFQC2AgAAAA==.Buddy:BAAANQADCgcIBwAAAA==.Buggäsm:BAAANQADCgcIFQAAAA==.Bullterra:BAAANQADCggICAABNQAECgYIDwAFAAAAAA==.Bumkin:BAAANQAECgIIAgABNQADCggIDwAFAAAAAA==.Bunnyjuice:BAAANQAECgIIAwAAAA==.',
By='Byakuya:BAAANQAECgQICQAAAA==.',
Ca='Calcub:BAAANQAECgUIBwAAAA==.Calykay:BAAANQADCgEIAQAAAA==.Calystalyn:BAEBNQAECoEdAAMBAAkJqB8qCgAKAwABAAkJMh8qCgAKAwADAAcJFhh7BQDPAQAAAA==.Captaïnjazz:BAAANQAECgEIAQAAAA==.Carelyda:BAAANQADCgYIBgAAAA==.Carneasada:BAAANQABCgEIAQAAAA==.Cartier:BAAANQAECgEIAQABNQAECgkJGgAPAJofAA==.Catheriana:BAAANQAECgMIAwAAAA==.',
Ch='Chach:BAAANQADCgUIBAAAAA==.Chris:BAABNQAECoEYAAIIAAgJ5g1uOwDAAQAIAAgJ5g1uOwDAAQAAAA==.Christmass:BAABNQAECoETAAINAAgJvBusFQCdAgANAAgJvBusFQCdAgAAAA==.Chupas:BAAANQAECgQIDgAAAA==.',
Ci='Cincy:BAAANQADCgYIBgAAAA==.',
Cl='Clorinde:BAAANQADCgQIBAABNQAECgYIDgAFAAAAAA==.',
Co='Colauris:BAAANQAECgcIEAAAAA==.Coolweiner:BAABNQAECoEWAAMQAAkJlhxLFAC/AgAQAAkJlhxLFAC/AgAKAAEJ5AHnYAAwAAAAAA==.Courserlul:BAAANQAECggIDgABNQAFFAcIFAAKAGwiAA==.',
Cr='Craodin:BAAANQAECgQIBQAAAA==.Craydaughter:BAAANQAECgIIAwAAAA==.Crayson:BAAANQADCgYICQABNQAECgIIAwAFAAAAAA==.',
Cu='Cult:BAAANQADCggICAABNQAECgYIDQAFAAAAAA==.',
Da='Daddyops:BAAANQAECgUICQAAAA==.Dan:BAAANQADCgIIAgAAAA==.Dandylion:BAAANQAECgUICAAAAA==.Dannamoth:BAAANQAECgYIDgAAAA==.Darkmayhm:BAAANQADCgUIAwABNQAECgQICAAFAAAAAA==.Darkmiahm:BAAANQADCgMIAwABNQAECgQICAAFAAAAAA==.Darknss:BAAANQAECgQIBgAAAA==.Dathrustae:BAAANQADCgYIBgAAAA==.',
De='Deathaxza:BAAANQADCgEIAQAAAA==.Deatherselfs:BAAANQAECgQIBgAAAA==.Deathessence:BAAANQADCgEIAQAAAA==.Demondy:BAAANQAECggIEAAAAA==.Depaynes:BAAANQADCggIFAAAAA==.Derekthegood:BAAANQAECgQIBAAAAA==.Dereliction:BAAANQAECgQIBgAAAA==.Derpindot:BAAANQAECgQIAwAAAA==.',
Dh='Dheid:BAAANQADCgYIBgAAAA==.',
Di='Dihruid:BAAANQADCgIIAgABNQAECgQIDAAFAAAAAA==.Dihscipline:BAAANQAECgIIAgABNQAECgQIDAAFAAAAAA==.Dinkdonk:BAAANQAECgQICwAAAA==.Dipsnchip:BAAANQAFFAEIAQABNQAECgYIDQAFAAAAAA==.Divinatrix:BAAANQADCgUIBQAAAA==.Divine:BAAANQAECgQICgAAAA==.Dizzynight:BAAANQAECggIAQAAAA==.',
Dk='Dklulz:BAABNQAECoEcAAINAAkJEyG/BgBiAwANAAkJEyG/BgBiAwAAAA==.',
Do='Dojoe:BAAANQADCgYIBgAAAA==.',
Dr='Draac:BAAANQAECgEIAQAAAA==.Drachun:BAAANQAECgUICAAAAA==.Drakelm:BAABNQAECoEbAAMRAAkJYxY0CACUAgARAAkJYxY0CACUAgASAAMJXxd3JADNAAAAAA==.Dranzdervish:BAAANQAECgQICAAAAA==.Draykos:BAAANQAECgMIAwAAAA==.Droes:BAAANQAECgQIBAAAAA==.Dropaganda:BAAANQAECgYICwAAAA==.Drrdead:BAAANQAECgMIAwAAAA==.Dryeth:BAAANQADCgEIAQAAAA==.',
Du='Duckpond:BAAANQADCgYIBgAAAA==.Durrtybao:BAAANQAECgQICAAAAA==.',
Dy='Dylanharp:BAAANQADCgUICwAAAA==.',
Ea='Easynuh:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.',
Ec='Ectheliön:BAAANQADCgMIAwABNQAECgUIDwAFAAAAAA==.',
Eh='Ehkoe:BAAANQADCgQIBAAAAA==.',
Ek='Ekkõ:BAAANQADCgUIBQABNQAECgQIBAAFAAAAAA==.',
El='Elated:BAAANQAECgEIAQABNQAECgYIDgAFAAAAAA==.Eldanor:BAAANQAECgQIBQAAAA==.Elitexrobert:BAAANQADCgQIBAAAAA==.Elitextony:BAAANQADCgIIAgAAAA==.Elryth:BAAANQADCgYIBgAAAA==.',
Em='Ember:BAABNQAECoEZAAIHAAkJ3iP3BACBAwAHAAkJ3iP3BACBAwAAAA==.Emberz:BAAANQAECgMIBQAAAA==.Emiris:BAAANQADCgUIBQAAAA==.Emobuzz:BAABNQAECoESAAIQAAYJ2RwkOwDiAQAQAAYJ2RwkOwDiAQAAAA==.',
En='Enialis:BAAANQAECgYICwAAAA==.Enyaspace:BAAANQADCgYIBgAAAA==.',
Es='Esperranza:BAAANQAECgMIAwAAAA==.Espurr:BAABNQAECoEcAAITAAkJOSKvAgBcAwATAAkJOSKvAgBcAwAAAA==.',
Ev='Eveid:BAAANQAECgUICAAAAA==.Evodny:BAAANQADCgYIEAAAAA==.',
Ex='Exodiaa:BAAANQADCgcIDgAAAA==.',
Fa='Fact:BAAANQAECgYIDwAAAA==.Faeris:BAAANQAECgMIAwAAAA==.Fahcup:BAAANQABCgYIBwAAAA==.Faroreswind:BAAANQAECgEIAgAAAA==.Fatchance:BAAANQADCgIIAQAAAA==.Fatherdots:BAAANQAECgIIAgABNQAECgYIDQAFAAAAAA==.',
Fe='Felbladekid:BAAANQADCgEIAQAAAA==.',
Fi='Fikkle:BAAANQAECgUIBwAAAA==.',
Fl='Flúffy:BAAANQAECgMIAwAAAA==.',
Fo='Foodang:BAAANQADCgQIBAAAAA==.Fortyskols:BAAANQADCgQIBQAAAA==.Foxxee:BAAANQADCgQIBAAAAA==.',
Fr='Friarpuck:BAAANQAECgQICwAAAA==.Frostchi:BAAANQADCgcICQABNQAECgcIDwAFAAAAAA==.Frostdawn:BAAANQAECgQIBAABNQAECgcIDwAFAAAAAA==.Frosteye:BAAANQAECgcIDwAAAA==.Frozensalt:BAABNQAECoEYAAMUAAgJ2iMAGQA3AwAUAAgJ2iMAGQA3AwAVAAEJ8iBmHQBeAAAAAA==.Fryerpuck:BAAANQADCgUIBgAAAA==.Fryssa:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.',
Fu='Furrbuddy:BAAANQAECgQICAAAAA==.Furrsparta:BAAANQAECgMIBAAAAA==.',
Ga='Galiphe:BAAANQAECgYIDQAAAA==.Garidan:BAAANQAECgUICQAAAA==.',
Ge='Geeyyanni:BAAANQAECgYIDQAAAA==.Geopetal:BAABNQAECoEYAAIWAAgJthWqBQBGAgAWAAgJthWqBQBGAgAAAA==.',
Gh='Ghasdros:BAAANQAECgcIDAAAAA==.Ghostwin:BAAANQADCgYIBgAAAA==.',
Gi='Gingy:BAAANQADCgQIBAABNQAECgQICAAFAAAAAA==.',
Gl='Gladefresh:BAAANQAECgQICAAAAA==.Glowytwinkie:BAAANQADCgYIBgAAAA==.',
Go='Goldenice:BAAANQAECgIIBAAAAA==.Gooseriver:BAABNQAECoEXAAIXAAgJpyE6AwDwAgAXAAgJpyE6AwDwAgABNQADCgYIBgAFAAAAAA==.Goyboi:BAAANQADCgYIBgAAAA==.',
Gr='Greylan:BAAANQADCgYIDAAAAA==.Greysha:BAAANQAECgcIBwAAAA==.Grinzler:BAAANQAECgQIBQAAAA==.Grym:BAAANQAECgUICAAAAA==.',
Gu='Guappo:BAAANQAECgQIBQAAAA==.',
Ha='Hafwyn:BAAANQADCgYIDAABNQAECgcIDgAFAAAAAA==.Hanor:BAAANQAECgQIBAAAAA==.Harløt:BAAANQAECgMIBAAAAA==.Hauntedblac:BAAANQAECgQICAAAAA==.Hayley:BAAANQADCgMIAwAAAA==.',
He='Heavenascend:BAAANQADCgcIBgAAAA==.Heraborn:BAAANQADCgMIAgAAAA==.',
Ho='Hojitalaurel:BAAANQADCgUIDAAAAA==.Holymacaroli:BAAANQAECgIIAwAAAA==.Holysmiter:BAAANQAECgQIBQAAAA==.Holystrikér:BAAANQADCggICAAAAA==.Hoodfabulous:BAAANQAECgcIEQAAAA==.',
Hu='Huberto:BAAANQADCgYIDAAAAA==.Huntn:BAAANQAECgQIDAAAAA==.Hupyaptelyot:BAAANQAECgUICAAAAA==.',
Hy='Hytierea:BAAANQAECgUICAAAAA==.',
Ia='Iammudkip:BAAANQAECgEIAQAAAA==.',
Il='Ilocku:BAAANQAECgcIEwAAAQ==.',
Im='Imrac:BAAANQADCgYIBgABNQAECggIGQAUALUYAA==.Imshamazing:BAAANQADCgQIBAAAAA==.',
In='Incubus:BAAANQAECgYIDQAAAA==.',
Io='Ionigvaah:BAABNQAECoEVAAIOAAgJ/haSIABiAgAOAAgJ/haSIABiAgAAAA==.',
Ir='Iriemon:BAAANQAECgQIBAAAAA==.',
Is='Isabeau:BAAANQADCgEIAQAAAA==.Issowimonk:BAAANQADCgQIBAAAAA==.',
It='Italiaa:BAAANQAECgUIBwAAAA==.',
Ix='Ixtel:BAAANQAECgUIBwAAAA==.',
Ja='Jawesome:BAAANQAECgUIBgAAAA==.Jayron:BAAANQABCgYIBQAAAA==.',
Je='Jedakye:BAAANQAECgUICAAAAA==.Jeepers:BAAANQADCgcIFgAAAA==.Jenzypoo:BAAANQADCggIFwAAAA==.Jetson:BAAANQAECgQICgAAAA==.',
Ji='Jiblits:BAAANQAECgEIAQABNQAECgUIDQAFAAAAAA==.Jinkies:BAAANQADCgcIBwAAAA==.',
Jo='Jojo:BAAANQAECgcIDgAAAA==.',
Jp='Jpow:BAAANQAECgEIAQAAAA==.',
Ju='Junnarma:BAAANQAECgMIAQAAAA==.',
['Já']='Járnviðr:BAAANQAECgUIDwAAAA==.',
Ka='Kaalias:BAAANQADCgcIFAAAAA==.Kabrax:BAAANQADCggIBgAAAA==.Kai:BAAANQADCgYIBwABNQAECggIEgAFAAAAAA==.Kaiula:BAABNQAECoEZAAIOAAgJ1w9yMgD2AQAOAAgJ1w9yMgD2AQAAAA==.Kalabar:BAAANQAECgQICAAAAA==.Kaldrys:BAABNQAECoEXAAICAAcJShKOGADeAQACAAcJShKOGADeAQAAAA==.Kalnath:BAAANQAECgcIEQAAAA==.Kalynnah:BAAANQADCgcIBwAAAA==.Kamî:BAAANQAECgEIAgABNQAECgIIAgAFAAAAAA==.Kanabo:BAAANQADCgMIAwABNQADCgYIBgAFAAAAAA==.Kanarra:BAAANQADCggIEAAAAA==.Kanatoo:BAAANQAECgcIDgAAAA==.Kanekisenpai:BAABNQAECoEfAAMQAAkJ9CA+CQAhAwAQAAkJ6B0+CQAhAwAKAAYJLBrZDwDZAQAAAA==.Kanjam:BAAANQAECgQICgAAAA==.Kaylina:BAAANQADCgQIBAAAAA==.Kazrar:BAAANQADCggIDwAAAA==.',
Ke='Keepupheals:BAAANQADCgEIAQAAAA==.Keid:BAAANQAECgUICAAAAA==.Kelai:BAABNQAECoEbAAIYAAkJPxvHEAC5AgAYAAkJPxvHEAC5AgAAAA==.Kellion:BAAANQADCggICAAAAA==.Kenobi:BAAANQADCgYIBgAAAA==.',
Ki='Kikks:BAAANQADCgEIAQAAAA==.Kilusuka:BAAANQADCggIDQABNQAECgUIBwAFAAAAAA==.',
Ko='Kobarr:BAAANQAECgUICwAAAA==.Konbo:BAAANQAECgYIDQAAAA==.Koro:BAAANQAFFAEIAgAAAA==.Korvarith:BAAANQADCgQIBAAAAA==.',
Kr='Krapshoot:BAAANQADCgYICgABNQAECgQICQAFAAAAAA==.Krolghoul:BAAANQAECgQIBAABNQAFFAUICQAPAIcZAA==.Krolgor:BAAANQAECgEIAQABNQAFFAUICQAPAIcZAA==.Krump:BAAANQAECgUICgAAAA==.',
Ku='Kuramá:BAAANQAECgQICAAAAA==.Kuyà:BAAANQADCggICAAAAA==.Kuzé:BAAANQAECgQIBQAAAA==.',
Kw='Kwyj:BAAANQAFFAIIAgAAAA==.Kwyjibo:BAAANQAECgcIEwAAAA==.',
Ky='Kylebroflov:BAAANQAECgUICwAAAA==.Kyyguy:BAAANQADCgYICAAAAA==.',
['Kí']='Kítkatz:BAAANQADCgUIBQAAAA==.',
['Kï']='Kïllerfrost:BAAANQAECgUICAAAAA==.',
La='Lafizz:BAAANQADCgYIBgAAAA==.Lambofgods:BAAANQAECgYIDwAAAA==.Lanana:BAAANQADCgEIAQAAAA==.',
Le='Lencel:BAAANQAECgEIAQAAAA==.Leonidas:BAAANQAECgQIBAAAAA==.Letmo:BAAANQADCgcICwAAAA==.Letmu:BAAANQADCgUICAABNQADCgcICwAFAAAAAA==.Levelfour:BAAANQADCgIIAgAAAA==.',
Li='Liannia:BAAANQADCgUIBwABNQAECgQIBAAFAAAAAA==.Lightningki:BAAANQAECgQIBgAAAA==.Lightofdawn:BAAANQADCgMIAwAAAA==.Lightscream:BAAANQAECgcIDwAAAA==.Lilshoobs:BAAANQAECgMIAwAAAA==.Lindariel:BAAANQADCgMIAwAAAA==.Lindir:BAABNQAECoEWAAIJAAgJVCGrDwALAwAJAAgJVCGrDwALAwAAAA==.Liparoonie:BAAANQAECgQICAAAAA==.Liyt:BAAANQADCgIIAgABNQAECgQIBgAFAAAAAA==.',
Lo='Lockedupfoo:BAABNQAECoEhAAMQAAkJzCKqDAD+AgAQAAgJwCGqDAD+AgAKAAQJ9hl3HwA+AQAAAA==.Locktorty:BAAANQADCgIIAgAAAA==.Lolmindflay:BAAANQADCgYIBgAAAA==.',
Lu='Ludd:BAAANQADCgQIAQAAAA==.Lunah:BAAANQAECgUIDwAAAA==.Lupozz:BAAANQAECgYIDQAAAA==.',
['Lå']='Låb:BAAANQAECgMIAwAAAA==.',
Ma='Machahunt:BAAANQAECgUIBwAAAA==.Machico:BAAANQAECgQICAAAAA==.Magicdeadly:BAAANQAECgQICAAAAA==.Magicol:BAAANQAECgQIBQABNQAECgcIEAAFAAAAAA==.Magosika:BAAANQAECgYICQAAAA==.Maledizione:BAAANQAECgEIAQAAAA==.Manaburner:BAAANQAECgEIAQAAAA==.',
Me='Meerahs:BAAANQAECgQIBAAAAA==.Megahorn:BAAANQAECgcIEgAAAA==.Megthpallion:BAAANQADCgcICwAAAA==.',
Mf='Mfhambone:BAAANQADCgIIAwAAAA==.',
Mi='Midliyt:BAAANQAECgQIBgAAAA==.Midniyt:BAAANQADCgQIBAABNQAECgQIBgAFAAAAAA==.Mikaylla:BAAANQADCgQICAAAAA==.Mikkilina:BAAANQAECgEIAQAAAA==.Mitric:BAAANQAECgQIBAAAAA==.',
Mm='Mmeow:BAAANQAECgQIBAAAAA==.',
Mo='Moowarrior:BAAANQAECgIIBAAAAA==.Mosswyn:BAAANQADCggIDQAAAA==.',
Mu='Murmaiderr:BAAANQAECgEIAQAAAA==.Murman:BAAANQADCgIIAgAAAA==.',
Na='Nalla:BAAANQADCgYIBgAAAA==.Naravia:BAAANQAECgEIAQAAAA==.Narunî:BAAANQADCgYICQAAAA==.Nater:BAAANQAECgQICAAAAA==.',
Ne='Necrovyn:BAAANQADCgEIAQAAAA==.Nekkrosys:BAAANQAECgYICwAAAA==.Nekrron:BAAANQADCggICgAAAA==.Neona:BAAANQAECgEIAQAAAA==.Nevets:BAAANQABCggIDwAAAA==.',
Ni='Nicessus:BAAANQAECgcIDgAAAA==.Nicksys:BAAANQAECgUIDAAAAA==.Nikkanika:BAAANQAECgQIBgABNQAECgcIEgAFAAAAAA==.Niuzao:BAAANQADCgEIAQAAAA==.',
No='Nork:BAAANQAECgUIBwAAAA==.Norko:BAAANQADCgQIBAAAAA==.Norks:BAAANQADCggIDgAAAA==.Novembër:BAAANQAECgQIBQAAAA==.',
['Nÿ']='Nÿkon:BAAANQAECgIIAgAAAA==.',
Od='Oderrus:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.',
Ok='Okishama:BAABNQAECoEfAAIIAAkJ7hj2FACvAgAIAAkJ7hj2FACvAgAAAA==.',
On='Onkrack:BAAANQADCgcIDgABNQAECgUIBwAFAAAAAA==.',
Op='Ophelastra:BAAANQAECgQIBQAAAA==.',
Oz='Ozfiz:BAAANQADCgYIBgABNQAECgUICgAFAAAAAA==.Ozwiz:BAAANQADCgMIAwABNQAECgUICgAFAAAAAA==.',
Pa='Pandatastic:BAABNQAECoEoAAMIAAkJoSOyAgCZAwAIAAkJoSOyAgCZAwAJAAcJNRgkLwAJAgAAAA==.Pastrami:BAAANQAFFAEIAQAAAA==.Patbee:BAAANQADCgIIBAABNQADCgQIAQAFAAAAAA==.Pawn:BAAANQADCgcICAAAAA==.',
Pe='Pearlsham:BAAANQAECgUICQAAAA==.Peekaaboo:BAAANQAECgEIAQAAAA==.',
Ph='Phikkle:BAAANQADCgUIBgAAAA==.Phâtè:BAAANQAECgIIBAAAAA==.',
Pi='Picesty:BAABNQAECoEXAAMUAAgJfBIJZgAVAgAUAAgJfBIJZgAVAgAVAAEJzwyMKgAxAAABNQABCgYIBwAFAAAAAA==.Pilikiä:BAAANQADCgcIBwAAAA==.',
Pk='Pkflash:BAAANQAECgMIAwAAAA==.',
Pl='Platinumbull:BAAANQAECgcIEwAAAA==.Pleabsham:BAAANQAECgIIAwAAAA==.Plikka:BAAANQADCgQIBAABNQAECgcIEgAFAAAAAA==.',
Po='Pokentotem:BAAANQAECgQICAAAAA==.Potlogic:BAAANQAECgQIBQABNQAECgkJIAAVAFQXAA==.',
Pr='Prandel:BAAANQABCgMIAwABNQAECgQIBQAFAAAAAA==.Prosciutto:BAAANQABCgQIBgAAAA==.',
Pu='Puddl:BAAANQAECgQIBgAAAA==.Punkii:BAAANQAECggIEwAAAA==.Punnisher:BAAANQADCgYIBgAAAA==.',
Qp='Qpawnz:BAAANQAECgIIAgABNQAECgkJGgAQAAkgAA==.',
Qu='Quidamtyra:BAAANQAECgMIAwAAAA==.Quigonjin:BAAANQAECgEIAgAAAA==.',
Ra='Rabbifrost:BAAANQADCggICAAAAA==.Rackem:BAAANQADCgEIAQAAAA==.Rackham:BAABNQAECoEYAAIZAAgJlxPSDAAGAgAZAAgJlxPSDAAGAgAAAA==.Radiana:BAAANQAECgUICQAAAA==.Raeknor:BAAANQAECgQICAAAAA==.Raizén:BAAANQABCgQIBAAAAA==.Ramaran:BAAANQADCgIIAgABNQAECgQIBAAFAAAAAA==.Ramrocket:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.Randomaction:BAAANQAECgQICAAAAA==.Rastabution:BAAANQAECggIAQAAAA==.Rathvyr:BAABNQAECoEiAAIEAAkJNiLXCwBrAwAEAAkJNiLXCwBrAwAAAA==.Ravenskeet:BAAANQADCggICAABNQAECgMIAwAFAAAAAA==.Razuriell:BAAANQAECgYIDQAAAA==.',
Re='Reagan:BAAANQABCgIIAgAAAA==.Rebeakah:BAAANQAECgQIBgAAAA==.Reggs:BAAANQAECgIIAwAAAQ==.Renko:BAAANQAECgYIDgAAAA==.',
Ri='Ribitey:BAABNQAECoEYAAIBAAkJhSYpAAD4AwABAAkJhSYpAAD4AwAAAA==.Riggs:BAAANQADCgYIEAAAAA==.Riggster:BAAANQAECgcIEAAAAA==.Rilakuma:BAAANQAECgQICAAAAA==.',
Ro='Rockyballz:BAAANQADCgEIAQAAAA==.Rolando:BAABNQAECoEiAAIEAAgJ3xP9QwAkAgAEAAgJ3xP9QwAkAgAAAA==.Rosybel:BAAANQADCgQIBAAAAA==.Rotimus:BAAANQADCgIIAgAAAA==.Rozewyn:BAAANQAECgYICwAAAA==.',
Ru='Rukator:BAAANQAECgEIAQAAAA==.',
Ry='Ryawhitefang:BAABNQAECoEXAAMHAAgJZyOrDQAOAwAHAAgJZyOrDQAOAwAGAAMJ6hriMQDNAAAAAA==.Ryvoon:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràgé:BAAANQAECgIIAgAAAA==.',
['Rê']='Rêddit:BAAANQADCggICAAAAA==.',
Sa='Salael:BAABNQAECoEaAAIWAAgJSBeQBACAAgAWAAgJSBeQBACAAgAAAA==.Saphi:BAAANQADCggICAAAAA==.Saphirin:BAABNQAECoEhAAIYAAkJjBnJFgB0AgAYAAkJjBnJFgB0AgAAAA==.Sariphi:BAAANQADCgQIBAAAAA==.Sauron:BAAANQADCggIEgAAAA==.Savagebrain:BAAANQADCgUIBwABNQAECgkJFwAUAOIdAA==.Savagelung:BAABNQAECoEXAAIUAAkJ4h2lIQAOAwAUAAkJ4h2lIQAOAwAAAA==.Saya:BAAANQADCgYIBgAAAA==.',
Sc='Schoonie:BAAANQADCgYIDAAAAA==.Schutzengel:BAABNQAECoEYAAIIAAkJ9RrODgDoAgAIAAkJ9RrODgDoAgAAAA==.Scribbl:BAAANQAECgcIEwAAAA==.Scylon:BAAANQAECgYIBgAAAA==.Scythen:BAAANQADCgYIBgAAAA==.',
Se='Selinda:BAAANQADCgUIBQAAAA==.Sencerity:BAAANQADCgEIAQAAAA==.Serana:BAAANQAECgIIBAAAAA==.',
Sh='Shadowbanned:BAAANQADCgUIBQAAAA==.Shallowgrave:BAAANQAECgYIDgAAAA==.Shamanhands:BAAANQAECgIIAwAAAA==.Shammyhaggar:BAAANQAECgUICQAAAA==.Shamram:BAAANQAECgQIBAAAAA==.Shamywamy:BAAANQAECggIEAAAAA==.Shamywamydk:BAAANQAECgEIAQAAAA==.Shaodh:BAAANQADCgUIBQAAAA==.Shaodk:BAAANQAECggIDwAAAA==.Sharkeesha:BAAANQADCgQIBAAAAA==.Shawdi:BAAANQABCgIIAgAAAA==.Shibs:BAAANQADCgQIBAAAAA==.Shiffty:BAAANQAECgQIBQAAAA==.Shiggadin:BAAANQAECggIDQAAAA==.Shiggalaw:BAAANQAECgQIBQABNQAECggIDQAFAAAAAA==.Shikki:BAAANQAECgQICAAAAA==.Shinys:BAAANQAECgQICAABNQAECgUICwAFAAAAAA==.Shuki:BAAANQADCgEIAQAAAA==.Shámtastic:BAAANQADCggIDgAAAA==.Shäde:BAABNQAECoEbAAIPAAkJmhbNCACzAgAPAAkJmhbNCACzAgAAAA==.',
Si='Simpai:BAAANQAECgIIBAAAAA==.',
Sk='Skiethx:BAABNQAECoEaAAMPAAkJmh8XCQCtAgAPAAcJoh8XCQCtAgAaAAMJESCVKwAGAQAAAA==.Skipii:BAAANQAECgIIAgAAAA==.Skullderzix:BAAANQAECgUICAAAAA==.Skullderzxx:BAAANQAECgQIBAABNQAECgUICAAFAAAAAA==.',
Sl='Slopersafari:BAAANQAECgQIBgAAAA==.Slowqt:BAABNQAECoEfAAINAAkJliLbBACGAwANAAkJliLbBACGAwAAAA==.',
Sm='Smashyz:BAAANQADCgYIBgABNQADCgYIBgAFAAAAAA==.',
Sn='Sneakytwinky:BAAANQADCgcIBwAAAA==.',
So='Somaria:BAAANQAECgMIAwAAAA==.Sonabrie:BAAANQADCgEIAQAAAA==.',
Sp='Spankybottom:BAAANQAECgIIBAAAAA==.Sparykz:BAAANQADCggIEAABNQAECgMIBQAFAAAAAA==.Spiyt:BAAANQADCgQIBgABNQAECgQIBgAFAAAAAA==.Spnkynvrsoft:BAAANQAECgcIEwAAAA==.',
Sq='Squeaky:BAAANQAECgQIBwAAAA==.Squee:BAAANQAECgUICAAAAA==.',
Sr='Srmonkey:BAAANQADCggIDQAAAA==.',
St='Stabachacha:BAABNQAECoEcAAMaAAkJhRxtDwBGAgAaAAcJUxptDwBGAgAPAAcJcBzoDwAvAgAAAA==.Steamicyhott:BAAANQADCggIEgAAAA==.Steveandkink:BAAANQABCgcIBwAAAA==.Stinkie:BAAANQAFFAEIAQAAAA==.Stonebeard:BAAANQADCgYICgAAAA==.Stormcore:BAAANQAECgMIAwAAAA==.',
Su='Sunny:BAAANQADCgYIEAAAAA==.Supernóva:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.',
Sy='Sylvanass:BAAANQADCgYICAAAAA==.Sylverarrow:BAAANQAECgMIAwAAAA==.Syreith:BAAANQADCgQIBQAAAA==.',
Ta='Tacabell:BAAANQAFFAEIAQAAAA==.Taken:BAABNQAECoEaAAMJAAkJiRigIwBXAgAJAAkJiRigIwBXAgAbAAEJoAdLHwBCAAAAAA==.Tarkarram:BAAANQAECgIIAgAAAA==.Tarnfair:BAAANQADCgUIDAAAAA==.Taurìel:BAAANQAECgMIAgAAAA==.Taven:BAAANQAECgQIBQAAAA==.',
Te='Technique:BAAANQAECgEIAQAAAA==.Tekka:BAAANQAECgIIBAAAAA==.Telegram:BAAANQADCgIIAgAAAA==.Telvor:BAAANQAECgQIBQAAAA==.Teminar:BAAANQADCggICAAAAA==.Terakore:BAAANQADCgEIAQABNQAECgYICgAFAAAAAA==.Terrukk:BAAANQAECgQIBgAAAA==.Tessalie:BAAANQADCgMIAwAAAA==.Teufelsnudel:BAAANQAECgMIBQAAAA==.',
Th='Theliver:BAAANQADCggICQAAAA==.Thelysong:BAAANQAECgEIAgAAAA==.Therena:BAAANQADCggICAAAAA==.Therran:BAAANQAECgcIEgAAAA==.Theuss:BAAANQAECgEIAQAAAA==.Thexador:BAAANQAECgIIAgAAAA==.Thorraden:BAAANQADCgMIAwABNQAECgMIBQAFAAAAAA==.Thranduill:BAAANQAECgQIBQAAAA==.',
Ti='Tidefury:BAAANQAECgIIAwAAAA==.Tidepod:BAAANQAECgYIBgABNQAECgkJHAAcAB0mAA==.Tigerclaw:BAAANQAECgIIAwAAAA==.Tilley:BAAANQADCgYICwAAAA==.Timber:BAAANQABCgQIBwAAAA==.Tingaling:BAAANQAECgUICgAAAA==.',
Tl='Tlock:BAAANQAECgUIBwAAAA==.',
To='Tool:BAAANQABCgIIAgAAAA==.Toothdh:BAAANQADCgYIBgABNQADCggIDwAFAAAAAA==.Toothlss:BAAANQADCgYIDgABNQADCggIDwAFAAAAAA==.Toragza:BAAANQAECgEIAQAAAA==.Totums:BAAANQAECgMIAwAAAA==.',
Tr='Trashyz:BAAANQAECgQIBQABNQADCgYIBgAFAAAAAA==.Treseme:BAAANQABCgIIAgAAAA==.Triaradea:BAAANQADCgUIBwABNQADCgYIBgAFAAAAAA==.Tribalz:BAAANQAECgYIDQAAAA==.Trunddle:BAAANQAECgQICgAAAA==.',
Tu='Tuchmydemons:BAAANQAECgQIBQAAAA==.',
Ty='Tygrelilly:BAAANQAECgQIBAAAAA==.Tyrieal:BAAANQAECgMIAwAAAA==.',
['Tø']='Tøøthlss:BAAANQADCggIDwAAAA==.',
Ul='Ulidan:BAAANQADCgIIAgAAAA==.',
Un='Ungoloth:BAAANQADCgMIAwABNQAECgYICgAFAAAAAA==.',
Va='Vamp:BAAANQADCggIDwAAAA==.Vanêssa:BAAANQAECgEIAgAAAA==.Varner:BAABNQAECoEVAAIdAAkJCCCFCQBEAwAdAAkJCCCFCQBEAwAAAA==.',
Vi='Vindict:BAAANQADCgEIAQAAAA==.',
Vl='Vlakshift:BAAANQAECgQICgAAAA==.',
Vo='Voltedarrow:BAAANQAECggIBwAAAA==.Voltedrage:BAAANQAECggIBgAAAA==.Vongalas:BAAANQAECgMIAwAAAA==.Vongimi:BAAANQAECgMIBAAAAA==.Vongimiv:BAAANQADCgYIDAABNQAECgMIBAAFAAAAAA==.Voucher:BAABNQAECoEaAAMQAAkJCSDOHgB2AgAQAAcJ/h/OHgB2AgAKAAIJLiCUNQC0AAAAAA==.',
Vy='Vyn:BAAANQAECgYICgAAAA==.Vynstarcyon:BAAANQAECgQIBAAAAA==.Vysérå:BAAANQAECgQIBgAAAA==.',
Wa='Wai:BAAANQAECgcIEwAAAA==.Warglaíve:BAAANQAECgcIEwAAAA==.Wasted:BAAANQAECgQICQAAAA==.',
We='Weg:BAAANQADCgQIBAAAAA==.',
Wh='Whilsohn:BAAANQADCgcICQAAAA==.Whilson:BAAANQADCggIFQAAAA==.Whilsonh:BAAANQADCggIDgABNQADCggIFQAFAAAAAA==.',
Wi='Wildbillee:BAAANQAECgMIAwABNQAECgkJIQAKALgcAA==.Wildbilly:BAAANQAECgUIDAABNQAECgkJIQAKALgcAA==.Wildbily:BAAANQADCgYIBgABNQAECgkJIQAKALgcAA==.Wilhson:BAAANQADCgMIBAABNQADCggIFQAFAAAAAA==.Wilsuhn:BAAANQADCgYICAABNQADCggIFQAFAAAAAA==.Winterveil:BAAANQADCgEIAQAAAA==.Witchblade:BAAANQADCgYICwABNQAECgQIBAAFAAAAAA==.',
Wo='Woolworm:BAAANQABCgIIAgAAAA==.Worldwaker:BAAANQAECgcIEwAAAA==.Wornn:BAAANQADCgYICQAAAA==.',
Wr='Wretched:BAABNQAECoEbAAILAAkJSCI9AACYAwALAAkJSCI9AACYAwAAAA==.',
Wu='Wukard:BAAANQAECgUICQAAAA==.',
Wy='Wylblly:BAAANQADCggIEAABNQAECgkJIQAKALgcAA==.Wyldbill:BAABNQAECoEhAAQKAAkJuBz1CgAfAgAKAAYJ4B71CgAfAgAQAAQJmA/FdQAMAQALAAEJeCS2EwBiAAAAAA==.',
Xa='Xarxzez:BAAANQAECgUICgAAAA==.',
Xe='Xer:BAAANQABCgQIBAAAAA==.',
Xf='Xfaeble:BAABNQAECoEWAAIBAAkJXhg+FACkAgABAAkJXhg+FACkAgABNQAECgkJHAASAJwPAA==.',
Xg='Xgambit:BAAANQAECgQICwAAAA==.',
Xp='Xprtdemon:BAAANQAECgIIAgAAAA==.',
Xy='Xylar:BAAANQADCgUIBQAAAA==.Xyno:BAAANQAECgYIDAAAAA==.',
['Xû']='Xûrû:BAAANQADCggICAAAAA==.',
Ya='Yandora:BAAANQADCgIIAgAAAA==.',
Yo='Yoggibear:BAAANQAECgQIBAAAAA==.Yoreick:BAAANQADCgUIBQAAAA==.',
Yu='Yuckmouth:BAABNQAECoEgAAMVAAkJVBeoAgCOAgAVAAkJVBeoAgCOAgAUAAEJrwvIOAE1AAAAAA==.Yuli:BAAANQAECgMIAwABNQAECgQICgAFAAAAAA==.',
Za='Zadaen:BAAANQAECgMIBQAAAA==.Zaladren:BAAANQAECgEIAQAAAA==.Zave:BAAANQAECggIAgAAAA==.',
Ze='Zenshot:BAAANQAECgUIBgAAAA==.Zerazenazath:BAAANQAECgUIBQAAAA==.',
Zi='Ziegevolk:BAAANQADCgQIBAABNQADCgYIBgAFAAAAAA==.',
Zo='Zoobra:BAAANQADCggIFAAAAA==.Zorkky:BAAANQADCgUIBQAAAA==.',
Zu='Zubinator:BAAANQAECgQIBwAAAA==.Zulteld:BAAANQADCgMIAwABNQAECgQIBQAFAAAAAA==.',
['Ác']='Áchu:BAAANQAECggIDQAAAA==.',
['Âr']='Ârrgh:BAAANQAECgQICgAAAA==.',
['Än']='Änh:BAAANQAECgQIBAAAAA==.',
['Ðe']='Ðestroyer:BAAANQADCggIEAAAAA==.',
['Ðj']='Ðjinzen:BAAANQADCgYICQAAAA==.',
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
