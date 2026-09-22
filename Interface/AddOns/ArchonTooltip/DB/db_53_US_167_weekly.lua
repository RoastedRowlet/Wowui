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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Warrior-Arms','Druid-Balance','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Paladin-Protection','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Rogue-Subtlety','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver','Rogue-Assassination','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Druid-Feral','Monk-Brewmaster','Warrior-Fury','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abeblinken:BAAANQABCgIIAgAAAA==.Abrigo:BAAANQAECgYJDgAAAA==.',
Ae='Aesbop:BAAANQAECgYIDgAAAA==.Aetherlight:BAACNQAFFIEKAAIBAAUK+RfbBADOAQABAAUK+RfbBADOAQA1AAQKgSQABAEACQryIowTAOQCAAEACQqOIowTAOQCAAIACAqBFyQUAF8CAAMAAgqJIywRAKsAAAAA.',
Ai='Ais:BAAANQADCgYIBgAAAA==.',
Al='Alaanz:BAAANQAECgMJAwAAAA==.Alpharatz:BAAANQAECgcJEQAAAA==.',
Am='Amonamarth:BAABNQAECoEZAAIEAAgKthWUVwAPAgAEAAgKthWUVwAPAgAAAA==.Amunwrath:BAAANQAECgYJDwAAAA==.',
An='Anatharion:BAABNQAECoEaAAIFAAgKchurGwCWAgAFAAgKchurGwCWAgAAAA==.Angel:BAAANQAECgQIBAAAAA==.Angrybao:BAAANQABCgYICAAAAA==.Annari:BAAANQAECgYIEgAAAA==.Anéantir:BAAANQAECgcIDwAAAA==.',
Ao='Aozeraa:BAABNQAECoEYAAMGAAgKWiLeBwBnAgAGAAYKayPeBwBnAgAHAAUKTB9HXgCuAQAAAA==.',
Ap='Apostate:BAAANQAECgIIAwABNQAECggJGAAIAJoeAA==.',
Aq='Aquadond:BAAANQADCgcICwABNQAECggIGwAJAAAAAQ==.',
Ar='Arakh:BAAANQADCgYIBgAAAA==.Arakhe:BAAANQADCgYIBgAAAA==.Arbaal:BAAANQAECgUJEAAAAA==.Arkania:BAAANQADCgQJBAAAAA==.Artemais:BAABNQAECoEgAAMKAAkK4RqoFQBgAgAKAAkKRBaoFQBgAgALAAYKyBd/cQCZAQAAAA==.',
As='Asaki:BAAANQADCgIJAgAAAA==.Asarmaul:BAAANQADCggIHwAAAA==.',
At='Atalanthya:BAAANQADCggJEAABNQAECggJJQACABQTAA==.Atiesh:BAAANQAECgEIAQAAAA==.',
Av='Avanoria:BAAANQADCgQIBAAAAA==.Avein:BAAANQADCgQIBgAAAA==.',
Aw='Awesomeaf:BAAANQAECgUIBgABNQAFFAUJBwALAI4QAA==.',
Az='Azernaut:BAAANQADCgYIBgAAAA==.Azgarth:BAAANQAECgIIAgABNQAECgQJCgAJAAAAAA==.Azureky:BAAANQAECgQJCAAAAA==.Azuresham:BAAANQADCgYIBgAAAA==.Azuric:BAAANQAECgQIBAAAAA==.',
Ba='Babytear:BAAANQAECgYJDgAAAA==.Badfelix:BAABNQAECoEdAAMMAAkK4xI3PQD6AQAMAAkK4xI3PQD6AQANAAYKggWkhAAMAQAAAA==.Baldrsonn:BAAANQAECgEIAQAAAA==.Balenciaga:BAAANQADCgcICQAAAA==.Bambuzzo:BAABNQAECoEcAAIOAAkKtxITEwBGAgAOAAkKtxITEwBGAgAAAA==.Barbrawr:BAAANQAECgIIBgAAAA==.Bawr:BAAANQADCggICAAAAA==.',
Bd='Bdft:BAAANQAECgUIBQAAAA==.',
Be='Beararms:BAAANQADCggICAAAAA==.Bearlee:BAAANQADCgIIAgAAAA==.Beautyboy:BAAANQAECgUICwABNQAECgYJBgAJAAAAAA==.Beefdip:BAAANQAECgQIBAAAAA==.Benbear:BAAANQADCgQJBQAAAA==.',
Bg='Bgneedwork:BAAANQAECgYIDgAAAA==.',
Bi='Billidari:BAAANQAECgUIDAABNQAECgkJKQAGABseAA==.Bixby:BAAANQAECgQIBAAAAA==.',
Bl='Blachdeath:BAAANQAECgEIAQAAAA==.Blazedin:BAABNQAECoEaAAIPAAkK7h5jBQAZAwAPAAkK7h5jBQAZAwAAAA==.Bleumachine:BAAANQADCgEIAQAAAA==.',
Bo='Boeds:BAAANQAECgUJCgAAAA==.Bokrim:BAAANQAECgYIEAAAAA==.',
Br='Brawns:BAAANQABCgYIDAABNQAECgkJHAAQAOQjAA==.Braér:BAAANQADCgcJBwAAAA==.Brisktwo:BAAANQAECgEIAQAAAA==.Brujo:BAAANQAECgQIBAABNQAECgkJIAAKAOEaAA==.Brutalious:BAABNQAECoEnAAMRAAkKESPKBABpAwARAAkKkiLKBABpAwASAAgKXSNEEQDuAgAAAA==.Bryxie:BAAANQADCgYIBgABNQADCgYIBgAJAAAAAA==.',
Bu='Bubbes:BAAANQAECgQIBwAAAA==.Bubblebeåm:BAABNQAECoEgAAITAAgKpx1pHACwAgATAAgKpx1pHACwAgAAAA==.Buddy:BAAANQADCgcIBwAAAA==.Buggäsm:BAAANQADCgcIFgAAAA==.Bullterra:BAAANQADCggICAABNQAECggJGgAUAPwiAA==.Bumkin:BAAANQAECgIIAwABNQADCggIDwAJAAAAAA==.Bunnyjuice:BAAANQAECgIJAwAAAA==.',
By='Byakuya:BAAANQAECgYIDwAAAA==.',
Ca='Calcub:BAAANQAECgYJDQAAAA==.Calykay:BAAANQADCgEIAQAAAA==.Calystalyn:BAEBNQAECoEfAAMBAAkKqB+gEAD4AgABAAkKMh+gEAD4AgADAAcKFhisBgC+AQAAAA==.Captaïnjazz:BAAANQAECgQJBwAAAA==.Carelyda:BAAANQADCgYIBgABNQADCgcIDAAJAAAAAA==.Carneasada:BAAANQABCgEIAQAAAA==.Cartier:BAAANQAECgEIAQABNQAECgkJHQAVAJofAA==.Catheriana:BAAANQAECgQJBwAAAA==.',
Ch='Chach:BAAANQAECgYIBgAAAA==.Chris:BAABNQAECoEgAAIMAAgKehCZSQDDAQAMAAgKehCZSQDDAQAAAA==.Christmass:BAABNQAECoEZAAISAAkKMxsmEwDZAgASAAkKMxsmEwDZAgAAAA==.Chupas:BAABNQAECoEZAAMNAAUKGg0GfwAaAQANAAUKGg0GfwAaAQAMAAUKzgIBngCxAAAAAA==.',
Ci='Cincy:BAAANQADCgcJBgAAAA==.',
Cl='Clem:BAAANQAECgYIBgAAAA==.Clorinde:BAAANQADCgQIBAABNQAFFAEIAgAJAAAAAA==.',
Co='Colauris:BAABNQAECoEYAAIVAAgKcgoRGADiAQAVAAgKcgoRGADiAQAAAA==.Coolweiner:BAABNQAECoEfAAMHAAkK/B0yEAALAwAHAAkK/B0yEAALAwAGAAEK5AHpawAtAAAAAA==.Courserlul:BAAANQAECggJDgABNQAFFAgIHAAGAJwgAA==.',
Cr='Craodin:BAAANQAECgQIBQAAAA==.Craydaughter:BAAANQAECgIJBQAAAA==.Crayson:BAAANQADCgYICQABNQAECgIJBQAJAAAAAA==.Crozzo:BAAANQADCgYJBgAAAA==.',
Cu='Cult:BAAANQADCggICwABNQAECggJGAAIAJoeAA==.',
Da='Daddyops:BAAANQAECgUJDQAAAA==.Dan:BAAANQADCgIIAgAAAA==.Dandylion:BAAANQAECgUICAAAAA==.Dannamoth:BAABNQAECoEZAAIWAAgK5xiYYABtAgAWAAgK5xiYYABtAgAAAA==.Darkmayhm:BAAANQADCgUJAwABNQAECgQJCAAJAAAAAA==.Darkmiahm:BAAANQADCgMIAwABNQAECgQJCAAJAAAAAA==.Darknss:BAAANQAECgQJCgAAAA==.Dathrustae:BAAANQAECgMJAwAAAA==.',
De='Deacondag:BAAANQADCgQJBAAAAA==.Deagles:BAAANQAECgQJBAAAAA==.Deathaxza:BAAANQADCgEIAQAAAA==.Deatherselfs:BAAANQAECgUIDAAAAA==.Deathessence:BAAANQADCgEIAQAAAA==.Demondy:BAAANQAFFAQIBAAAAA==.Depaynes:BAAANQAECgEJAQAAAA==.Derekthegood:BAAANQAECgQJBgAAAA==.Dereliction:BAAANQAECgUJCgAAAA==.Derpindot:BAAANQAECgQIAwAAAA==.',
Dh='Dheid:BAAANQADCgYJBgAAAA==.',
Di='Diabolically:BAAANQABCggJDAABNQAECgcICwAJAAAAAA==.Dihruid:BAAANQADCgIIAgABNQAECgYJEgAJAAAAAA==.Dihscipline:BAAANQAECgIIAgABNQAECgYJEgAJAAAAAA==.Dinkdonk:BAAANQAECgQICwAAAA==.Dipsnchip:BAABNQAECoEcAAMSAAkKqiXnAADxAwASAAkKqiXnAADxAwARAAEKSxgpZQBLAAABNQAECgkJGQAFAB0WAA==.Divinatrix:BAAANQADCgUIBQAAAA==.Divine:BAAANQAECgUJDAAAAA==.Dizzynight:BAAANQAECggIAQAAAA==.',
Dk='Dklulz:BAABNQAECoEjAAISAAkKbyL4BgBzAwASAAkKbyL4BgBzAwAAAA==.',
Do='Dojoe:BAAANQADCgYIBgAAAA==.',
Dr='Draac:BAAANQAECgEIAQAAAA==.Drachun:BAAANQAECgUIDAAAAA==.Drakelm:BAABNQAECoEgAAMXAAkKhxatCgB8AgAXAAkKhxatCgB8AgAYAAMKphdRKwDJAAAAAA==.Dranzdervish:BAAANQAECgUICQAAAA==.Draykos:BAAANQAECgMJBQAAAA==.Droes:BAAANQAECgQJBAAAAA==.Dropaganda:BAAANQAECgcJEgAAAA==.Drrdead:BAAANQAECgQIBwAAAA==.Dryeth:BAAANQADCgYJBwAAAA==.',
Du='Duckpond:BAAANQADCgYJBgAAAA==.Durrtybao:BAAANQAECgYIDgAAAA==.',
Dy='Dylanharp:BAAANQADCgUJDwAAAA==.',
Ea='Easynuh:BAAANQADCgYIBgABNQAECgYJCgAJAAAAAA==.',
Ec='Ectheliön:BAAANQADCgMIAwABNQAECggIGQALAGYSAA==.',
Eh='Ehkoe:BAAANQADCgQIBAAAAA==.',
Ek='Ekkõ:BAAANQADCgUIBQABNQAECgQIBgAJAAAAAA==.',
El='Elated:BAAANQAECgEIAQABNQAECgYIDwAJAAAAAA==.Eldanor:BAAANQAECgQICAAAAA==.Elitexrobert:BAAANQADCgQJBAAAAA==.Elitextony:BAAANQADCgIIAgAAAA==.Elryth:BAAANQADCgYIBgAAAA==.',
Em='Ember:BAACNQAFFIEHAAILAAUKjhBpAwCcAQALAAUKjhBpAwCcAQA1AAQKgRwAAgsACQreIyMKAFkDAAsACQreIyMKAFkDAAAA.Emberz:BAAANQAECgQICQAAAA==.Emiris:BAAANQADCgUIBQAAAA==.Emobuzz:BAABNQAECoEZAAIHAAgKyRgVLABwAgAHAAgKyRgVLABwAgAAAA==.',
En='Enialis:BAAANQAECgcIEQAAAA==.Enyaspace:BAAANQADCgYIBgAAAA==.',
Es='Esperranza:BAAANQAECgQJBwAAAA==.Espira:BAAANQAECgMIAwAAAA==.Espurr:BAABNQAECoEeAAIUAAkKOSLGBABBAwAUAAkKOSLGBABBAwAAAA==.',
Ev='Eveid:BAAANQAECgUJDAAAAA==.Evodny:BAAANQAECgMJAwAAAA==.',
Ex='Exodiaa:BAAANQADCgcIDgAAAA==.',
Fa='Fact:BAABNQAECoEZAAIZAAgKEw8gEwDEAQAZAAgKEw8gEwDEAQAAAA==.Faeris:BAAANQAECgMIAwAAAA==.Fahcup:BAAANQABCgYIBwAAAA==.Faroreswind:BAAANQAECgQJBgAAAA==.Fatchance:BAAANQAECgEIAQAAAA==.Fatherdots:BAAANQAECgIJAgABNQAECgYJEgAJAAAAAA==.',
Fe='Felbladekid:BAAANQADCgEIAQAAAA==.',
Fi='Fikkle:BAAANQAECgYJDQAAAA==.',
Fl='Flúffy:BAAANQAECgYJCQAAAA==.',
Fo='Foodang:BAAANQADCgQJBAAAAA==.Fortyskols:BAAANQADCgQIBQAAAA==.Foxxee:BAAANQADCgQIBAAAAA==.',
Fr='Freesamples:BAAANQAECgMIAwABNQAECgkJIQAaALcdAA==.Friarpuck:BAAANQAECgQIEAAAAA==.Frostchi:BAAANQADCgcICQABNQAECggIGQAbADAhAA==.Frostdawn:BAAANQAECgQIBAABNQAECggIGQAbADAhAA==.Frosteye:BAABNQAECoEZAAIbAAgKMCGbAgDUAgAbAAgKMCGbAgDUAgAAAA==.Frozensalt:BAABNQAECoEcAAMWAAgK+iNDJAAnAwAWAAgK+iNDJAAnAwAbAAEK8iBuJQBaAAAAAA==.Fryerpuck:BAAANQADCgUIBgAAAA==.Fryssa:BAAANQAECgIJAgABNQAECgUJBQAJAAAAAA==.',
Fu='Furrbuddy:BAAANQAECgYIDgAAAA==.Furrsparta:BAAANQAECgUJCQAAAA==.',
Ga='Galiphe:BAABNQAECoEYAAIcAAgKdxIzDADhAQAcAAgKdxIzDADhAQAAAA==.Garidan:BAAANQAECgUICQAAAA==.',
Ge='Geeyyanni:BAABNQAECoEYAAIdAAgKRwvZBwCWAQAdAAgKRwvZBwCWAQAAAA==.Geopetal:BAABNQAECoEfAAIeAAgKRhonBgB4AgAeAAgKRhonBgB4AgAAAA==.',
Gh='Ghasdros:BAABNQAECoEVAAIBAAkKxBQsJgBqAgABAAkKxBQsJgBqAgAAAA==.Ghostwin:BAAANQADCgYICAAAAA==.',
Gi='Gingy:BAAANQADCgQIBAABNQAECgQICAAJAAAAAA==.',
Gl='Gladefresh:BAAANQAECgYJDgAAAA==.Glowytwinkie:BAAANQADCgYIBgAAAA==.',
Go='Goldenice:BAAANQAECgQJCAAAAA==.Gooseriver:BAABNQAECoEfAAIfAAkKOiIOAgBjAwAfAAkKOiIOAgBjAwABNQADCgYJBgAJAAAAAA==.Gotthmog:BAAANQAECgEIAQAAAA==.Goyboi:BAAANQAECgQIBAAAAA==.',
Gr='Greylan:BAAANQADCgYIDAAAAA==.Greysha:BAAANQAECgcJCwAAAA==.Grinzler:BAAANQAECgQIBQAAAA==.Grym:BAAANQAECgUJCQAAAA==.',
Gu='Guappo:BAAANQAECgQICQAAAA==.',
Ha='Hafwyn:BAAANQADCgYJDAABNQAECgkJGQAMABISAA==.Hanor:BAAANQAECgUJBQAAAA==.Harløt:BAAANQAECgQJCAAAAA==.Hauntedblac:BAAANQAECgQICAAAAA==.Hayley:BAAANQADCggJCQAAAA==.',
He='Heavenascend:BAAANQADCgcIBgAAAA==.Heraborn:BAAANQADCgMIAgAAAA==.',
Ho='Hojitalaurel:BAAANQADCgUIDAAAAA==.Holymacaroli:BAAANQAECgQJBQAAAA==.Holysmiter:BAAANQAECgQICQAAAA==.Holystrikér:BAAANQAECggICAAAAA==.Hoodfabulous:BAABNQAECoEXAAIgAAgKHBmdBABmAgAgAAgKHBmdBABmAgAAAA==.',
Hu='Huberto:BAAANQAECgEIAQAAAA==.Huntn:BAAANQAECgYJEgAAAA==.Hupyaptelyot:BAAANQAECgYJDQAAAA==.',
Hy='Hytierea:BAAANQAECgYIDgAAAA==.',
Ia='Iammudkip:BAAANQAECgUIBgAAAA==.',
Il='Ilocku:BAAANQAECggIGwAAAQ==.',
Im='Imrac:BAAANQADCgcJDQABNQAECggJIQAWAPEZAA==.Imshamazing:BAAANQADCgQIBAAAAA==.',
In='Incubus:BAABNQAECoEYAAIIAAgKmh7QAgDWAgAIAAgKmh7QAgDWAgAAAA==.',
Io='Ionigvaah:BAABNQAECoEdAAITAAkKzRaKHgCiAgATAAkKzRaKHgCiAgAAAA==.',
Ir='Iriemon:BAAANQAECgYJCgAAAA==.',
Is='Isabeau:BAAANQADCgEIAQAAAA==.Issowimonk:BAAANQADCgYJCQAAAA==.',
It='Italiaa:BAAANQAECgUJBwAAAA==.',
Ix='Ixtel:BAAANQAECgYJDQAAAA==.',
Ja='Jawesome:BAAANQAECgUICQAAAA==.Jayron:BAAANQABCgYIBQAAAA==.',
Je='Jedakye:BAAANQAECgUIDAAAAA==.Jeepers:BAAANQAECgEIAgAAAA==.Jenzypoo:BAAANQAECgIIAgAAAA==.Jetson:BAAANQAECgUIEgAAAA==.',
Ji='Jiblits:BAAANQAECgEIAQABNQAECgkJGAAWAPcUAA==.Jinkies:BAAANQADCgcIBwAAAA==.',
Jo='Jojo:BAABNQAECoEZAAMHAAkKoBMtQgAVAgAHAAgKbBQtQgAVAgAGAAEKQw0LYgA9AAAAAA==.',
Jp='Jpow:BAAANQAECgQIBQAAAA==.',
Ju='Junnarma:BAAANQAECgUIBAAAAA==.',
['Já']='Járnviðr:BAABNQAECoEZAAMLAAgKZhJfUQD9AQALAAgKZhJfUQD9AQAhAAMK7RZzCQDlAAAAAA==.',
Ka='Kaalias:BAAANQAECgQIBAAAAA==.Kabrax:BAAANQADCggIBgAAAA==.Kai:BAAANQADCgYIBwABNQAECgkJFwAUAHQTAA==.Kaiula:BAABNQAECoEgAAITAAgKiRJSPQACAgATAAgKiRJSPQACAgAAAA==.Kalabar:BAAANQAECgYIDgAAAA==.Kaldrys:BAABNQAECoElAAICAAgKFBMuFgBAAgACAAgKFBMuFgBAAgAAAA==.Kalnath:BAABNQAECoEbAAIIAAgK7hsIBACMAgAIAAgK7hsIBACMAgAAAA==.Kalynnah:BAAANQAECgIIAgAAAA==.Kamî:BAAANQAECgcICQAAAA==.Kanabo:BAAANQADCgMIAwABNQADCgcIDAAJAAAAAA==.Kanarra:BAAANQADCggIEAAAAA==.Kanatoo:BAAANQAECggJEAAAAA==.Kanekisenpai:BAABNQAECoEkAAMHAAkK9CACEQAFAwAHAAkK6B0CEQAFAwAGAAYKLBoxEgDKAQAAAA==.Kanjam:BAAANQAECgcIEQAAAA==.Kaylina:BAAANQADCgQIBAAAAA==.Kazrar:BAAANQAECgMIAwAAAA==.',
Ke='Keepupheals:BAAANQADCgEIAQAAAA==.Keid:BAAANQAECgYJDQAAAA==.Kelai:BAABNQAECoEbAAIiAAkKPxuyGACTAgAiAAkKPxuyGACTAgAAAA==.Kellion:BAAANQAECgEIAQAAAA==.Kenobi:BAAANQADCgYIBgAAAA==.',
Ki='Kikks:BAAANQADCgEIAQAAAA==.Kilusuka:BAAANQADCggIDQABNQAECgYJDQAJAAAAAA==.',
Ko='Kobarr:BAAANQAECgUICwAAAA==.Konbo:BAABNQAECoEYAAMaAAgK+iDtCAD8AgAaAAgK+iDtCAD8AgAVAAMKCB7SLgDjAAAAAA==.Koro:BAAANQAFFAEIAwAAAA==.Korvarith:BAAANQADCgQIBAAAAA==.',
Kr='Krapshoot:BAAANQAECgQJBAABNQAECgcIEAAJAAAAAA==.Krolghoul:BAAANQAECgQIBAABNQAFFAUJDgAVAG0bAA==.Krolgor:BAAANQAECgEIAQABNQAFFAUJDgAVAG0bAA==.Krump:BAAANQAECgYIEAAAAA==.',
Ku='Kuramá:BAAANQAECgYIDgAAAA==.Kuyà:BAAANQADCggICAAAAA==.Kuzé:BAAANQAECgUICwAAAA==.',
Kw='Kwyj:BAABNQAFFIEGAAIFAAQK4RNkCABXAQAFAAQK4RNkCABXAQAAAA==.Kwyjibo:BAABNQAECoEYAAISAAkKWh02FQDFAgASAAkKWh02FQDFAgAAAA==.',
Ky='Kylebroflov:BAAANQAECgYJDwAAAA==.Kyyguy:BAAANQADCgYICAAAAA==.',
['Kí']='Kíllermoon:BAAANQADCgQIBAAAAA==.Kítkatz:BAAANQADCgUIBQAAAA==.',
['Kï']='Kïllerfrost:BAAANQAECgYIDgAAAA==.',
La='Labprotek:BAAANQADCgIJAgABNQAECgMIAwAJAAAAAA==.Lafizz:BAAANQADCgYIBgAAAA==.Lambofgods:BAABNQAECoEZAAIiAAgKFArXQwB5AQAiAAgKFArXQwB5AQAAAA==.Lanana:BAAANQADCgEIAQAAAA==.',
Le='Lencel:BAAANQAECgEIAQAAAA==.Leonidas:BAAANQAECgYJCgAAAA==.Letmo:BAAANQADCgcICwAAAA==.Letmu:BAAANQADCgUICAABNQADCgcICwAJAAAAAA==.Levelfour:BAAANQADCgQIBgAAAA==.',
Li='Liannia:BAAANQADCgUIBwABNQAECgUJBQAJAAAAAA==.Lightningki:BAAANQAECgQIBgAAAA==.Lightofdawn:BAAANQADCgMIAwAAAA==.Lightscream:BAABNQAECoEXAAMTAAkKoB2GDwAQAwATAAkKoB2GDwAQAwAjAAEKdSBPCgFGAAAAAA==.Lilshoobs:BAAANQAECgQIBwAAAA==.Lindariel:BAAANQADCgMIAwAAAA==.Lindir:BAABNQAECoEcAAINAAgK7yGjFAAJAwANAAgK7yGjFAAJAwAAAA==.Liparoonie:BAAANQAECgYIDgAAAA==.Liyt:BAAANQADCgIIAgABNQAECgQIBgAJAAAAAA==.',
Lo='Lockedupfoo:BAABNQAECoEjAAMHAAkKeSN3EwD1AgAHAAgKgyJ3EwD1AgAGAAQK9hnsIgA1AQAAAA==.Locktorty:BAAANQADCgIIAgAAAA==.Lolmindflay:BAAANQADCgYIBgAAAA==.',
Lu='Ludd:BAAANQADCgQJAQAAAA==.Lunah:BAABNQAECoEYAAIBAAgKPB3GGQC4AgABAAgKPB3GGQC4AgAAAA==.Lupozz:BAAANQAECgYIDQAAAA==.',
['Lå']='Låb:BAAANQAECgMIAwAAAA==.',
Ma='Machahunt:BAAANQAECgUJCAAAAA==.Machico:BAAANQAECgcIDwAAAA==.Maetha:BAAANQAECgUIBQAAAA==.Magicdeadly:BAAANQAECgYIDgAAAA==.Magicol:BAAANQAECgQJBwABNQAECggIGAAVAHIKAA==.Magicá:BAAANQADCgYJBgABNQAECgQICQAJAAAAAA==.Magosika:BAAANQAECgYJDAAAAA==.Maledizione:BAAANQAECgEJAgAAAA==.Manaburner:BAAANQAECgIJAgAAAA==.',
Me='Meerahs:BAAANQAECgUICAAAAA==.Megahorn:BAABNQAECoEZAAIkAAgKaBacHgApAgAkAAgKaBacHgApAgAAAA==.Megthpallion:BAAANQADCgcJCwAAAA==.',
Mf='Mfhambone:BAAANQADCgIIAwAAAA==.',
Mi='Midliyt:BAAANQAECgQIBgAAAA==.Midniyt:BAAANQADCgQIBAABNQAECgQIBgAJAAAAAA==.Mikaylla:BAAANQADCgQICAAAAA==.Mikkilina:BAAANQAECgEJAQAAAA==.Mitric:BAAANQAECgcICwAAAA==.',
Mm='Mmeow:BAAANQAECgUICAAAAA==.',
Mo='Moowarrior:BAAANQAECgQJCAAAAA==.Mosswyn:BAAANQADCggIFAAAAA==.',
Mu='Murmaiderr:BAAANQAECgQIBQAAAA==.Murman:BAAANQADCgcICQAAAA==.',
Na='Nalla:BAAANQADCgYIBgAAAA==.Naravia:BAAANQAECgIIAwAAAA==.Narunî:BAAANQADCgYJDQAAAA==.Nater:BAAANQAECgYJDgAAAA==.',
Ne='Necrovyn:BAAANQADCgEIAQAAAA==.Nekkrosys:BAAANQAECgcJEgAAAA==.Nekrron:BAAANQADCggICgAAAA==.Neona:BAAANQAECgQIBQAAAA==.Nevets:BAAANQABCggJDwAAAA==.',
Ni='Nicessus:BAABNQAECoEZAAIMAAkKEhIeMAA5AgAMAAkKEhIeMAA5AgAAAA==.Nicksys:BAAANQAECgYIEgAAAA==.Nikkanika:BAAANQAECgQIBgABNQAECggJGwAjAEkWAA==.Niuzao:BAAANQADCgEIAQAAAA==.',
No='Noggenus:BAAANQABCgYIBwAAAA==.Norania:BAAANQAECgYIBgAAAA==.Nork:BAAANQAECgYJDQAAAA==.Norko:BAAANQADCgQIBAAAAA==.Norks:BAAANQADCggIDgAAAA==.Normalname:BAAANQAECgEJAQAAAA==.Novembër:BAAANQAECgYJCwAAAA==.',
['Nÿ']='Nÿkon:BAAANQAECgIJAgABNQAECgcICQAJAAAAAA==.',
Od='Oderrus:BAAANQADCgUIBQABNQAECgQIBQAJAAAAAA==.',
Ok='Okishama:BAABNQAECoEjAAIMAAkKkR6bDgAUAwAMAAkKkR6bDgAUAwAAAA==.',
On='Oneinchash:BAAANQAECggJCAABNQAFFAcIGAAkAKUgAA==.Onkrack:BAAANQADCggJFgABNQAECgYJDQAJAAAAAA==.Onlyfanzz:BAAANQADCgYJBgAAAA==.',
Op='Ophelastra:BAAANQAECgQIBQAAAA==.',
Oz='Ozfiz:BAAANQADCgYIBgABNQAECgYJEAAJAAAAAA==.Ozwiz:BAAANQADCgMIAwABNQAECgYJEAAJAAAAAA==.',
Pa='Pandatastic:BAACNQAFFIEGAAIMAAMKdwm/CgDrAAAMAAMKdwm/CgDrAAA1AAQKgSsAAwwACQqhI+EEAIIDAAwACQqhI+EEAIIDAA0ABwpCGD0/APsBAAAA.Pastrami:BAABNQAECoEdAAISAAcK3RlRKgAWAgASAAcK3RlRKgAWAgAAAA==.Patbee:BAAANQADCgIIBAABNQADCgQJAQAJAAAAAA==.Pawn:BAAANQADCgcICAAAAA==.',
Pe='Pearlsham:BAAANQAECgYJDwAAAA==.Peekaaboo:BAAANQAECgIIAgAAAA==.',
Ph='Phikkle:BAAANQADCgUIBgAAAA==.Phâtè:BAAANQAECgIIBAAAAA==.',
Pi='Picesty:BAABNQAECoEeAAMWAAgKoRUncQBAAgAWAAgKoRUncQBAAgAbAAEKzwx4MwAxAAABNQABCgYIBwAJAAAAAA==.Pikkle:BAAANQADCgcJBwAAAA==.Pilikiä:BAAANQADCgcIBwAAAA==.Pipsqueekx:BAAANQAECgEIAQABNQAECggJAQAJAAAAAA==.',
Pk='Pkflash:BAAANQAECgQJBwAAAA==.',
Pl='Platinumbull:BAABNQAECoEeAAIEAAgKEhBnXwD0AQAEAAgKEhBnXwD0AQAAAA==.Pleabsham:BAAANQAECgIJBQAAAA==.Plikka:BAAANQAECgQIBAABNQAECggJGwAjAEkWAA==.',
Po='Pokentotem:BAAANQAECgQICAAAAA==.Potlogic:BAAANQAECgUICwABNQAECgkJKAAbAAUbAA==.',
Pr='Prandel:BAAANQABCgMJAwABNQAECgQICAAJAAAAAA==.Prosciutto:BAAANQABCgQIBgAAAA==.',
Pu='Puddl:BAAANQAECgQIBgAAAA==.Punkii:BAABNQAECoEcAAILAAgK+CETGwDYAgALAAgK+CETGwDYAgAAAA==.Punnisher:BAAANQADCgYIBgAAAA==.',
Qp='Qpawnz:BAAANQAECgUIBwABNQAFFAUJBwAHAFQVAA==.',
Qu='Quidamtyra:BAAANQAECgQJBwAAAA==.Quigonjin:BAAANQAECgIJAgAAAA==.',
Ra='Rabbifrost:BAAANQADCggICAAAAA==.Rackem:BAAANQADCgEIAQAAAA==.Rackham:BAABNQAECoEaAAIZAAkKthJeDQA5AgAZAAkKthJeDQA5AgAAAA==.Radiana:BAAANQAECgUICQAAAA==.Raeknor:BAAANQAECgYJDgAAAA==.Ragequake:BAAANQABCgEIAQAAAA==.Raizén:BAAANQABCgQIBAAAAA==.Ramaran:BAAANQADCgIJAgABNQAECgQIBAAJAAAAAA==.Ramrocket:BAAANQADCgYIBgABNQAECgUJBQAJAAAAAA==.Randomaction:BAAANQAECgYIDgAAAA==.Rankors:BAAANQADCgEIAQAAAA==.Rastabution:BAAANQAECggIAQAAAA==.Rathvyr:BAABNQAECoEsAAIEAAkKHSW7AwDIAwAEAAkKHSW7AwDIAwAAAA==.Ravenskeet:BAAANQADCggIDAABNQAECgUICAAJAAAAAA==.Razuriell:BAAANQAECgYJEgAAAA==.',
Re='Reagan:BAAANQABCgIIAgAAAA==.Rebeakah:BAAANQAECgUICAAAAA==.Reggs:BAAANQAECgIIAwAAAQ==.Renko:BAABNQAECoEZAAIOAAgK0CPlBQA+AwAOAAgK0CPlBQA+AwAAAA==.',
Ri='Ribitey:BAACNQAFFIEKAAIBAAUKFyIlAwALAgABAAUKFyIlAwALAgA1AAQKgR0AAgEACQqzJh4AAAkEAAEACQqzJh4AAAkEAAAA.Riggs:BAAANQADCgYIEAAAAA==.Riggster:BAABNQAECoEaAAISAAgK7xn8GwCHAgASAAgK7xn8GwCHAgAAAA==.Rilakuma:BAAANQAECgYIDgAAAA==.',
Ro='Robzombíe:BAAANQADCgIIAQABNQAECgcIEAAJAAAAAA==.Rockyballz:BAAANQADCgEIAQAAAA==.Rolando:BAABNQAECoEmAAIEAAgK3xMAXgD4AQAEAAgK3xMAXgD4AQAAAA==.Rosybel:BAAANQADCgQIBAAAAA==.Rotimus:BAAANQADCgIIAgAAAA==.Row:BAAANQABCgMIAwAAAA==.Rozewyn:BAAANQAECgcJEgAAAA==.',
Ru='Rukator:BAAANQAECgEJAQAAAA==.',
Ry='Ryawhitefang:BAABNQAECoEeAAMLAAkKPyScAwCtAwALAAkKPyScAwCtAwAKAAMK6hqDPADHAAAAAA==.Ryvoon:BAAANQADCgUJBQAAAA==.',
['Rà']='Ràgé:BAAANQAECgIJAwAAAA==.',
['Rê']='Rêddit:BAAANQADCggICAAAAA==.',
Sa='Salael:BAABNQAECoEhAAIeAAgKdBkGBgB+AgAeAAgKdBkGBgB+AgAAAA==.Saphi:BAAANQADCggICAAAAA==.Saphirin:BAABNQAECoElAAIiAAkKLhrxHgBeAgAiAAkKLhrxHgBeAgAAAA==.Sariphi:BAAANQADCgQIBAAAAA==.Sauron:BAAANQADCggIEgAAAA==.Savagebrain:BAAANQADCgUIBwABNQAECgkJIAAWALMiAA==.Savagelung:BAABNQAECoEgAAIWAAkKsyLjDwB+AwAWAAkKsyLjDwB+AwAAAA==.Saya:BAAANQADCgYIBgAAAA==.',
Sc='Schoonie:BAAANQADCgYIDAAAAA==.Schutzengel:BAABNQAECoEbAAIMAAkKyxvsFgDQAgAMAAkKyxvsFgDQAgAAAA==.Scribbl:BAABNQAECoEcAAMGAAgKkSPqAQA6AwAGAAgK1SLqAQA6AwAHAAMKmBohrwDLAAAAAA==.Scylon:BAAANQAECgcIDQAAAA==.Scythen:BAAANQADCgYIBgAAAA==.',
Se='Selinda:BAAANQAECgQJBAAAAA==.Sencerity:BAAANQADCgEIAQAAAA==.Serana:BAAANQAECgQJCAAAAA==.',
Sh='Shadowbanned:BAAANQADCgUIBQAAAA==.Shallowgrave:BAAANQAECgYIDgAAAA==.Shamanhands:BAAANQAECgUJCAAAAA==.Shammyhaggar:BAAANQAECgUIDQAAAA==.Shamram:BAAANQAECgQIBAAAAA==.Shamywamy:BAAANQAECggIEgAAAA==.Shamywamydk:BAAANQAECgEIAQAAAA==.Shaodh:BAAANQADCgUIBQAAAA==.Shaodk:BAAANQAECggIEwAAAA==.Sharkeesha:BAAANQADCgQIBAAAAA==.Shawdi:BAAANQABCgIIAgAAAA==.Shibs:BAAANQADCgQIBAAAAA==.Shiffty:BAAANQAECgQICQAAAA==.Shiggadin:BAABNQAECoEVAAITAAgKuhg5JwBuAgATAAgKuhg5JwBuAgAAAA==.Shiggalaw:BAAANQAECgcIDAABNQAECggIFQATALoYAA==.Shikki:BAAANQAECgQJCAAAAA==.Shinys:BAAANQAECgYIDgABNQAECgcJEgAJAAAAAA==.Shockadelica:BAAANQADCgEJAQABNQAECgYJCgAJAAAAAA==.Shuki:BAAANQADCgEIAQAAAA==.Shámtastic:BAAANQADCggJFgAAAA==.Shäde:BAABNQAECoEdAAIVAAkK1BjaCQCxAgAVAAkK1BjaCQCxAgAAAA==.',
Si='Simpai:BAAANQAFFAEJAQAAAA==.Sinzspirits:BAAANQAECggIAgAAAA==.',
Sk='Skaman:BAAANQABCgYIBgAAAA==.Skiethx:BAABNQAECoEdAAMVAAkKmh86CwCWAgAVAAcKoh86CwCWAgAaAAQKkBgROAAcAQAAAA==.Skipii:BAAANQAECgQJBgAAAA==.Skullderzix:BAAANQAECgUJCAABNQAECgYICgAJAAAAAA==.Skullderzxx:BAAANQAECgYICgAAAA==.',
Sl='Slamshazam:BAAANQABCgYIBgABNQADCgUIBQAJAAAAAA==.Sleeptoken:BAAANQAECgYIBwABNQAECggIGQAEALYVAA==.Slopersafari:BAAANQAECgcIDQAAAA==.Slowqt:BAABNQAECoEnAAISAAkKFyMiBQCRAwASAAkKFyMiBQCRAwAAAA==.',
Sm='Smashyz:BAAANQADCgYJBgABNQADCgYJBgAJAAAAAA==.',
Sn='Sneakytwinky:BAAANQADCgcIBwAAAA==.',
So='Somaria:BAAANQAECgUICQAAAA==.Sonabrie:BAAANQADCgUJBgAAAA==.',
Sp='Spankybottom:BAAANQAECgQJCAAAAA==.Sparykz:BAAANQADCggIEAABNQAECgQICQAJAAAAAA==.Spiyt:BAAANQADCgQIBgABNQAECgQIBgAJAAAAAA==.Spnkynvrsoft:BAABNQAECoEeAAMCAAgKthUdHADwAQACAAcK5RMdHADwAQABAAgKcxH6PgDsAQAAAA==.',
Sq='Squeaky:BAAANQAECgQICAAAAA==.Squee:BAAANQAECgUJDQAAAA==.',
Sr='Srmonkey:BAAANQADCggIDQAAAA==.',
St='Stabachacha:BAABNQAECoEhAAMaAAkKtx2zDgCiAgAaAAgKAByzDgCiAgAVAAcKcByZEwAWAgAAAA==.Steamicyhott:BAAANQAECgQJBAAAAA==.Steveandkink:BAAANQABCgcIBwAAAA==.Stgmavrick:BAAANQAECggIAQAAAA==.Stinkie:BAAANQAFFAEIAQAAAA==.Stonebeard:BAAANQADCgYJCgAAAA==.Stormcore:BAAANQAECgQIBwAAAA==.',
Su='Sunny:BAAANQAECgMJAwAAAA==.Supernóva:BAAANQADCgQIBAABNQAECgYJCgAJAAAAAA==.',
Sw='Swampybutt:BAAANQAECgQJAQAAAA==.',
Sy='Sylvanass:BAAANQADCgYICAAAAA==.Sylverarrow:BAAANQAECgMIAwAAAA==.Syreith:BAAANQADCgQIBQAAAA==.',
Ta='Tacabell:BAAANQAFFAEJAQAAAA==.Taken:BAABNQAECoEjAAMNAAkKtBtgFwDxAgANAAkKtBtgFwDxAgAlAAEKoAfeJABCAAAAAA==.Tarkarram:BAAANQAECgQJBgAAAA==.Tarnfair:BAAANQADCgUJDAAAAA==.Taurìel:BAAANQAECgMIAgAAAA==.Taven:BAAANQAFFAEIAQAAAA==.',
Te='Technique:BAAANQAECgEIAQAAAA==.Tekka:BAAANQAECgQJCAAAAA==.Telegram:BAAANQADCgMIBAAAAA==.Telvor:BAAANQAECgQICQAAAA==.Teminar:BAAANQADCggJCAAAAA==.Terakore:BAAANQADCgEIAQABNQAECgcIEQAJAAAAAA==.Terrukk:BAAANQAECgQICQAAAA==.Tessalie:BAAANQADCgMIAwAAAA==.Teufelsnudel:BAAANQAECgcJDAAAAA==.',
Th='Thelysong:BAAANQAECgIJBAAAAA==.Therena:BAAANQADCggICAAAAA==.Therran:BAABNQAECoEbAAIjAAgKSRYATAAkAgAjAAgKSRYATAAkAgAAAA==.Theuss:BAAANQAECgUIBgAAAA==.Thexador:BAAANQAECgIIAgAAAA==.Thormin:BAAANQAECggJBQAAAA==.Thorraden:BAAANQADCgMIAwABNQAECgQICQAJAAAAAA==.Thranduill:BAAANQAECgQICQAAAA==.Thras:BAAANQADCggICAAAAA==.',
Ti='Tidefury:BAAANQAECgUJCAAAAA==.Tidepod:BAAANQAECgYIBgABNQAECgkJFwAHAPIhAA==.Tigerclaw:BAAANQAECgIIAwAAAA==.Tilley:BAAANQADCgYICwAAAA==.Timber:BAAANQABCgQJBwAAAA==.Tingaling:BAAANQAECgYJEAAAAA==.',
Tl='Tlock:BAAANQAECgYJDQAAAA==.',
To='Tool:BAAANQABCgIJAgAAAA==.Toothdh:BAAANQADCggJDgABNQADCggIDwAJAAAAAA==.Toothlss:BAAANQAECgIIAgABNQADCggIDwAJAAAAAA==.Toragza:BAAANQAECgIJAwAAAA==.Totums:BAAANQAECgUJCAAAAA==.Toyletpaypah:BAAANQAECgYIAQABNQAECgYJDQAJAAAAAA==.Toyletwahtah:BAAANQAECgYJAQABNQAECgYJDQAJAAAAAA==.',
Tr='Trashyz:BAAANQAECgQJBQABNQADCgYJBgAJAAAAAA==.Treseme:BAAANQABCgIIAgAAAA==.Triaradea:BAAANQADCgUIBwABNQADCgcIDAAJAAAAAA==.Tribalz:BAABNQAECoEYAAIFAAgK2AypMgDTAQAFAAgK2AypMgDTAQAAAA==.Trunddle:BAAANQAECgQJDAAAAA==.',
Tu='Tuchmydemons:BAAANQAECgQJCQAAAA==.',
Ty='Tygrelilly:BAAANQAECgQIBAAAAA==.Tyrieal:BAAANQAECgQIBwAAAA==.',
['Të']='Tën:BAAANQADCgMIAwAAAA==.',
['Tø']='Tøøthlss:BAAANQADCggIDwAAAA==.',
Ul='Ulidan:BAAANQADCgIIAgAAAA==.',
Un='Ungoloth:BAAANQADCgMIAwABNQAECgcIEQAJAAAAAA==.',
Va='Vamp:BAAANQAECgcIBwAAAA==.Vanêssa:BAAANQAECgEJAgAAAA==.Varner:BAABNQAECoEeAAIFAAkKiSLZBgB+AwAFAAkKiSLZBgB+AwAAAA==.',
Vi='Vindict:BAAANQAECgEJAQAAAA==.',
Vl='Vlakshift:BAAANQAECgcIEQAAAA==.',
Vo='Voltedarrow:BAAANQAECggJBwAAAA==.Voltedrage:BAAANQAECggJBgAAAA==.Vongalas:BAAANQAECgQJBwAAAA==.Vongimi:BAAANQAECgQJCAAAAA==.Vongimiv:BAAANQADCgYIDAABNQAECgQJCAAJAAAAAA==.Vork:BAAANQADCggJCAAAAA==.Voucher:BAACNQAFFIEHAAMHAAUKVBUiBwBMAQAHAAQKvBIiBwBMAQAGAAEKth+6DABhAAA1AAQKgR0AAwcACQr/INstAGkCAAcABwo7IdstAGkCAAYAAgouILo7AK8AAAAA.',
Vy='Vyn:BAAANQAECgYICgAAAA==.Vynstarcyon:BAAANQAECgQIBAAAAA==.Vysérå:BAAANQAECgQICQAAAA==.',
Wa='Wai:BAABNQAECoEdAAIjAAgKah7EMACUAgAjAAgKah7EMACUAgAAAA==.Warglaíve:BAABNQAECoEeAAIkAAgK0R1+FwB1AgAkAAgK0R1+FwB1AgAAAA==.Wasted:BAAANQAECgcIEAAAAA==.',
We='Weg:BAAANQADCgQIBAAAAA==.',
Wh='Whilsohn:BAAANQADCgcJCgAAAA==.Whilson:BAAANQADCggIFgAAAA==.Whilsonh:BAAANQADCggJEwABNQADCggIFgAJAAAAAA==.',
Wi='Wildbillee:BAAANQAECgQJBwABNQAECgkJKQAGABseAA==.Wildbilly:BAABNQAECoEVAAMaAAkKvw9jGQAiAgAaAAgKwRBjGQAiAgAVAAUKiwvgKAAjAQABNQAECgkJKQAGABseAA==.Wildbily:BAAANQADCggJCgABNQAECgkJKQAGABseAA==.Wilhson:BAAANQADCgcJCQABNQADCggIFgAJAAAAAA==.Wilsuhn:BAAANQADCgYICAABNQADCggIFgAJAAAAAA==.Winterveil:BAAANQADCgYJBwAAAA==.Witchblade:BAAANQADCgYIEQABNQAECgYJCgAJAAAAAA==.',
Wo='Woolworm:BAAANQABCgIIAgAAAA==.Worldwaker:BAABNQAECoEfAAMOAAgK0RVEFQAlAgAOAAgK0RVEFQAlAgAZAAgKdQ4EFAC1AQAAAA==.Wornn:BAAANQADCgYICQAAAA==.',
Wr='Wretched:BAABNQAECoEcAAIQAAkK5CNRAACaAwAQAAkK5CNRAACaAwAAAA==.',
Wu='Wukard:BAAANQAECgUIDQAAAA==.',
Wy='Wylblly:BAAANQAECgMIAwABNQAECgkJKQAGABseAA==.Wyldbill:BAABNQAECoEpAAQGAAkKGx6JCQBDAgAGAAYK9CCJCQBDAgAHAAQKmA99mgD9AAAQAAEKeCRnGABgAAAAAA==.',
['Wó']='Wóoglin:BAAANQAECgQIBAAAAA==.',
Xa='Xarxzez:BAAANQAECgUIDwAAAA==.',
Xe='Xenius:BAAANQADCgMJAwAAAA==.Xer:BAAANQABCgQIBAAAAA==.',
Xf='Xfaeble:BAABNQAECoEXAAIBAAkKXhgMHwCUAgABAAkKXhgMHwCUAgABNQAECgkJHAAYAJwPAA==.',
Xg='Xgambit:BAAANQAECgQJDQAAAA==.',
Xp='Xprtdemon:BAAANQAECgIJBAAAAA==.',
Xy='Xylar:BAAANQADCgUIBQAAAA==.Xyno:BAAANQAECgYJEgAAAA==.',
['Xû']='Xûrû:BAAANQADCggICAAAAA==.',
Ya='Yandora:BAAANQADCgIIAgAAAA==.',
Yo='Yoggibear:BAAANQAECgUJBQAAAA==.Yoreick:BAAANQADCgUIBQAAAA==.',
Yu='Yuckmouth:BAABNQAECoEoAAMbAAkKBRuMAgDZAgAbAAkKBRuMAgDZAgAWAAEKrwukaAEzAAAAAA==.Yuli:BAAANQAECgMIAwABNQAECgUJDAAJAAAAAA==.',
Za='Zadaen:BAAANQAECgUJCgAAAA==.Zaladren:BAAANQAECgEIAQAAAA==.Zave:BAAANQAECggICgAAAA==.',
Ze='Zendarus:BAAANQAECgYJBgAAAA==.Zenshot:BAAANQAECgcIDQAAAA==.Zerazenazath:BAAANQAECgUIBQAAAA==.',
Zi='Ziegevolk:BAAANQADCgcIDAAAAA==.',
Zo='Zoobra:BAAANQADCggIFAAAAA==.Zorkky:BAAANQADCgUJBQAAAA==.',
Zu='Zubinator:BAAANQAECgQJCQAAAA==.Zulteld:BAAANQADCgMJAwABNQAECgQICAAJAAAAAA==.',
['Ác']='Áchu:BAAANQAECggJEgAAAA==.',
['Âr']='Ârrgh:BAAANQAECgUJDwAAAA==.',
['Än']='Änh:BAAANQAECgQJCAAAAA==.',
['Ðe']='Ðestroyer:BAAANQAECgQJBAAAAA==.',
['Ðj']='Ðjinzen:BAAANQADCgYJDAAAAA==.',
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
