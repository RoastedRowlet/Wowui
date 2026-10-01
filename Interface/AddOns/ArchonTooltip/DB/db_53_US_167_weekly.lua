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

local lookup = {'Warrior-Arms','Paladin-Holy','Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Arcane','Mage-Frost','Shaman-Restoration','Druid-Balance','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Monk-Windwalker','DeathKnight-Frost','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver','Rogue-Assassination','Druid-Guardian','Monk-Brewmaster','Warrior-Protection','Evoker-Augmentation','Druid-Feral','Warrior-Fury','Paladin-Retribution','Hunter-Survival','DeathKnight-Blood','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abeblinken:BAAANQABCgIIAgAAAA==.Abrigo:BAABNQAECoEUAAIBAAYK+giWrwA6AQABAAYK+giWrwA6AQAAAA==.',
Ae='Aesbop:BAABNQAECoEVAAICAAcKeyEbIQC5AgACAAcKeyEbIQC5AgAAAA==.Aetherlight:BAACNQAFFIEMAAIDAAUKRhiyBwDHAQADAAUKRhiyBwDHAQA1AAQKgSgABAMACQoiIwMWAPQCAAMACQq+IgMWAPQCAAQACAqBF84aACoCAAUAAgqJIz4UAKgAAAAA.',
Ai='Ais:BAAANQADCgYIBgAAAA==.',
Al='Alaanz:BAAANQAECgMIBgAAAA==.Alpharatz:BAABNQAECoEcAAMGAAgK5RqWZQCDAgAGAAgK5RqWZQCDAgAHAAQKnBSvGADpAAAAAA==.',
Am='Amonamarth:BAABNQAECoEdAAIBAAgKWhliYQAhAgABAAgKWhliYQAhAgAAAA==.Amunwrath:BAABNQAECoEaAAIIAAgK8xo5LAByAgAIAAgK8xo5LAByAgAAAA==.',
An='Anatharion:BAABNQAECoEeAAIJAAgKyBu0IACSAgAJAAgKyBu0IACSAgAAAA==.Angel:BAAANQAECgQICAAAAA==.Angrybao:BAAANQABCgYICAAAAA==.Annari:BAABNQAECoEfAAIKAAkKyhxlCgAaAwAKAAkKyhxlCgAaAwAAAA==.Anéantir:BAABNQAECoEXAAQLAAgKuB3xKwCeAgALAAgKuB3xKwCeAgAMAAIKmRAgUQB2AAANAAEKag4sJgA5AAAAAA==.',
Ao='Aozeraa:BAABNQAECoEbAAMMAAgKsiKsCABhAgAMAAYKhCOsCABhAgALAAUKuR8rcwCtAQAAAA==.',
Ap='Apostate:BAAANQAECgIIAwABNQAECggIIAAOAF8gAA==.',
Aq='Aquadond:BAAANQADCgcICwABNQAFFAIIAgAPAAAAAQ==.',
Ar='Arakh:BAAANQADCgYIBgAAAA==.Arakhe:BAAANQADCgcIDAAAAA==.Arbaal:BAABNQAECoEYAAIQAAYKHwY+NwDWAAAQAAYKHwY+NwDWAAAAAA==.Arkania:BAAANQADCgQJBAAAAA==.Artemais:BAACNQAFFIEJAAMRAAQK6QT7DgDpAAARAAQK6QT7DgDpAAASAAEK3gaoKQBGAAA1AAQKgSQAAxEACQqRHBAYAGcCABEACQr0FxAYAGcCABIABgrIF/yPAIQBAAAA.',
As='Asaki:BAAANQADCgIJAgAAAA==.Asarmaul:BAAANQADCggIJwAAAA==.',
At='Atalanthya:BAAANQADCggIEwABNQAECggILwAEABwVAA==.Atalkragu:BAAANQADCgYIBgAAAA==.Atiesh:BAAANQAECgQIBQAAAA==.',
Av='Avanoria:BAAANQADCgQIBAAAAA==.Avein:BAAANQADCgQIBgAAAA==.',
Aw='Awesomeaf:BAAANQAECgUICgABNQAFFAUIDAASAJ8QAA==.',
Az='Azernaut:BAAANQADCgYIBgAAAA==.Azgarth:BAAANQAECgIIAgABNQAECgQIDAAPAAAAAA==.Azureky:BAAANQAECgYIDgAAAA==.Azuresham:BAAANQADCgYIBgAAAA==.Azuric:BAAANQAECgUICQAAAA==.',
Ba='Babytear:BAAANQAECgYJDgAAAA==.Badfelix:BAABNQAECoEgAAMIAAkKchiqMgBSAgAIAAkKchiqMgBSAgATAAYKggVXngADAQAAAA==.Baldrsonn:BAAANQAECgEIAQAAAA==.Balenciaga:BAAANQADCgcICQAAAA==.Bambuzzo:BAABNQAECoEmAAIUAAkKABtADwC0AgAUAAkKABtADwC0AgAAAA==.Barbrawr:BAAANQAECgUICwAAAA==.Bawr:BAAANQADCggICAAAAA==.',
Bd='Bdft:BAAANQAECgYICAAAAA==.',
Be='Beararms:BAAANQADCggICAAAAA==.Bearlee:BAAANQADCgIIAgAAAA==.Beautyboy:BAAANQAECgUIDwABNQAECgYIDAAPAAAAAA==.Beefdip:BAAANQAECgQIBAAAAA==.Benbear:BAAANQADCgQJBQAAAA==.',
Bg='Bgneedwork:BAABNQAECoEXAAMMAAcKMhKHKwANAQALAAUKsw+qmwA8AQAMAAQKdRSHKwANAQAAAA==.',
Bi='Billidari:BAAANQAECgYIEQABNQAECgkJMgAMADsfAA==.Bixby:BAAANQAECgQIBAAAAA==.',
Bl='Blachdeath:BAAANQAECggICgAAAA==.Blazedin:BAABNQAECoEcAAIQAAkKiSB1BwD7AgAQAAkKiSB1BwD7AgAAAA==.Bleumachine:BAAANQADCgEIAQAAAA==.',
Bo='Boeds:BAAANQAECgUIDwAAAA==.Bokrim:BAAANQAECgcIEgAAAA==.',
Br='Brawns:BAAANQABCgYIDAABNQAECgkJHQANAOQjAA==.Braér:BAAANQADCgcJBwAAAA==.Brisktwo:BAAANQAECgQIBQAAAA==.Brujo:BAAANQAECgQIBAABNQAFFAQICQARAOkEAA==.Brutalious:BAABNQAECoErAAMVAAkKdyVOAgCxAwAVAAkK6iROAgCxAwAWAAgKXSMRHQCYAgAAAA==.Bryxie:BAAANQADCgYIBgABNQADCgYIBgAPAAAAAA==.',
Bu='Bubbes:BAAANQAECgUIDAAAAA==.Bubblebeåm:BAABNQAECoEoAAICAAkKTh6NEAAkAwACAAkKTh6NEAAkAwAAAA==.Bubblebuddy:BAAANQADCgYIBgAAAA==.Buddy:BAAANQADCgcIBwAAAA==.Buggäsm:BAAANQADCgcIGwAAAA==.Bullterra:BAAANQADCggICAABNQAECggIIgAXAPglAA==.Bumkin:BAAANQAECgIIAwABNQADCggIDwAPAAAAAA==.Bunnyjuice:BAAANQAECgIJAwAAAA==.',
By='Byakuya:BAAANQAECgYIDwAAAA==.',
Ca='Calcub:BAAANQAECgYIEwAAAA==.Calykay:BAAANQAECgMIAwAAAA==.Calystalyn:BAECNQAFFIEIAAIDAAQKKxWVDABnAQADAAQKKxWVDABnAQA1AAQKgSEAAwMACQqoH8wYAOMCAAMACQoyH8wYAOMCAAUABwoWGCQIALEBAAAA.Captaïnjazz:BAAANQAECgYICwAAAA==.Carelyda:BAAANQADCgYIBgABNQAECgIIAgAPAAAAAA==.Carneasada:BAAANQABCgEIAQAAAA==.Cartier:BAAANQAECgIIAgABNQAFFAUICAAYACMWAA==.Catheriana:BAAANQAECgUIDAAAAA==.',
Ch='Chach:BAAANQAECgYICgAAAA==.Chris:BAABNQAECoEpAAIIAAkK9BHkQAARAgAIAAkK9BHkQAARAgAAAA==.Christmass:BAABNQAECoEcAAIWAAkKlBxVGgCtAgAWAAkKlBxVGgCtAgAAAA==.Chupas:BAABNQAECoEfAAMTAAYKOA/8jQApAQATAAUK3xH8jQApAQAIAAYKowKOqADIAAAAAA==.',
Ci='Cincy:BAAANQADCgcICQAAAA==.',
Cl='Clem:BAAANQAECgcIDQAAAA==.Clorinde:BAAANQADCgQIBAABNQAECgkJGgADAEcjAA==.',
Co='Colauris:BAABNQAECoEYAAIYAAgKcgrbGwDRAQAYAAgKcgrbGwDRAQAAAA==.Coolweiner:BAABNQAECoEiAAMLAAkK/B1TGgDuAgALAAkK/B1TGgDuAgAMAAEK5AHqdAArAAAAAA==.Courserlul:BAAANQAECggIDgABNQAFFAkJHgALAAcdAA==.',
Cr='Craodin:BAAANQAECgQIBQAAAA==.Craydaughter:BAAANQAECgUICgAAAA==.Crayson:BAAANQADCgYICQABNQAECgUICgAPAAAAAA==.Crozzo:BAAANQADCgYIBgAAAA==.',
Cu='Cult:BAAANQADCggIDgABNQAECggIIAAOAF8gAA==.',
Da='Daddyops:BAAANQAECgUJDQAAAA==.Dan:BAAANQADCgIIAgAAAA==.Dandylion:BAAANQAECgUICAAAAA==.Dannamoth:BAABNQAECoEgAAIGAAgKHxy8WgCeAgAGAAgKHxy8WgCeAgAAAA==.Darkmayhm:BAAANQADCgUIAwABNQAECgQICAAPAAAAAA==.Darkmiahm:BAAANQADCgMIAwABNQAECgQICAAPAAAAAA==.Darknss:BAAANQAECgQIDAAAAA==.Dathrustae:BAAANQAECgUICAAAAA==.',
De='Deacondag:BAAANQAECgIIAgAAAA==.Deagles:BAAANQAECgQIBAABNQAECgkJGgATALgWAA==.Deathaxza:BAAANQADCgEIAQAAAA==.Deatherselfs:BAAANQAECgYIEAAAAA==.Deathessence:BAAANQADCgEIAQAAAA==.Deftones:BAAANQADCgMIAwAAAA==.Demondy:BAABNQAECoEWAAIKAAkKvxX9FwBsAgAKAAkKvxX9FwBsAgAAAA==.Depaynes:BAAANQAECgEJAQAAAA==.Derekthegood:BAAANQAECgQJBgAAAA==.Dereliction:BAAANQAECgYIDwAAAA==.Derpindot:BAAANQAECgQIAwAAAA==.',
Dh='Dheid:BAAANQADCgYJBgAAAA==.',
Di='Diabolically:BAAANQABCggIDAABNQAECgcICwAPAAAAAA==.Dihruid:BAAANQADCgIIAgABNQAECgcIFgAOANwNAA==.Dihscipline:BAAANQAECgUICwABNQAECgcIFgAOANwNAA==.Dinkdonk:BAAANQAECgQICwAAAA==.Dipsnchip:BAACNQAFFIEHAAMWAAMKAiJRCAAUAQAWAAMKAiJRCAAUAQAVAAEKtx9pEgBSAAA1AAQKgSMAAxYACQqsJt8AAO0DABYACQqsJt8AAO0DABUAAQpLGLh7AEYAAAE1AAQKCQkaAAkA5hYA.Divinatrix:BAAANQAECgQIBAAAAA==.Divine:BAAANQAECgUIDwAAAA==.Dizzynight:BAAANQAECggIAQAAAA==.',
Dk='Dklulz:BAABNQAECoEmAAIWAAkK8SJKDQAnAwAWAAkK8SJKDQAnAwAAAA==.',
Do='Doink:BAAANQAECgEIAQAAAA==.Dojoe:BAAANQADCgYIBgAAAA==.',
Dr='Draac:BAAANQAECgEIAQAAAA==.Drachun:BAAANQAECgYIDQAAAA==.Drakelm:BAABNQAECoEvAAMZAAkKEhzmBgDxAgAZAAkKEhzmBgDxAgAaAAMKpheJMQDEAAAAAA==.Dranzdervish:BAAANQAECgUICQAAAA==.Draykos:BAAANQAECgMIBQAAAA==.Droes:BAAANQAECgUICQAAAA==.Dropaganda:BAAANQAECgcIEgAAAA==.Drrdead:BAAANQAECgQICwAAAA==.Drumac:BAAANQADCgMIAwAAAA==.Dryeth:BAAANQADCgYJBwAAAA==.',
Du='Duckpond:BAAANQADCgYJBgAAAA==.Durrtybao:BAABNQAECoEXAAMTAAcKjR3NMQBvAgATAAcKjR3NMQBvAgAIAAYKVxVqZACJAQAAAA==.',
Dy='Dylanharp:BAAANQADCgUJDwAAAA==.',
Ea='Easynuh:BAAANQADCgYIBgABNQAECgcIEQAPAAAAAA==.',
Ec='Ectheliön:BAAANQADCgMIAwABNQAECggIGwASALQSAA==.',
Eh='Ehkoe:BAAANQADCgQIBAAAAA==.',
Ek='Ekkõ:BAAANQADCgUICQABNQAECggIDwAPAAAAAA==.',
El='Elated:BAAANQAECgEIAQABNQAECggIGQAGANEUAA==.Eldanor:BAAANQAECgQICQAAAA==.Elitexrobert:BAAANQADCgQJBAAAAA==.Elitextony:BAAANQADCgIIAgAAAA==.Elryth:BAAANQADCgYIBgAAAA==.',
Em='Ember:BAACNQAFFIEMAAISAAUKnxB1BgCJAQASAAUKnxB1BgCJAQA1AAQKgR4AAhIACQqyJBAOAEwDABIACQqyJBAOAEwDAAAA.Emberz:BAAANQAECgQICQAAAA==.Emiris:BAAANQADCgUIBQAAAA==.Emobuzz:BAABNQAECoEgAAILAAgKdhv5LgCSAgALAAgKdhv5LgCSAgAAAA==.',
En='Enialis:BAAANQAECgcIEwAAAA==.Enyaspace:BAAANQADCgYIBgAAAA==.',
Es='Esperranza:BAAANQAECgUIDAAAAA==.Espira:BAAANQAECgQIBwAAAA==.Espurr:BAABNQAECoEjAAIXAAkK5SKNBABfAwAXAAkK5SKNBABfAwAAAA==.',
Ev='Eveid:BAAANQAECgUIDgAAAA==.Evodny:BAAANQAECgMIBgAAAA==.',
Ex='Exodiaa:BAAANQADCgcIDgAAAA==.',
Fa='Fact:BAABNQAECoEgAAIbAAgK0hA4FQDRAQAbAAgK0hA4FQDRAQAAAA==.Faeris:BAAANQAECgMIAwAAAA==.Fahcup:BAAANQABCgYICAAAAA==.Faroreswind:BAAANQAECgQIBwAAAA==.Fatchance:BAAANQAECgIIAgAAAA==.Fatherdots:BAAANQAECgIIAgABNQAECggIGwASACUiAA==.',
Fe='Felbladekid:BAAANQADCgEIAQAAAA==.',
Fi='Fikkle:BAAANQAECgYIEwAAAA==.',
Fl='Flappyz:BAAANQADCgUIBQABNQADCgYJBgAPAAAAAA==.Flúffy:BAAANQAECgYIDwAAAA==.',
Fo='Foodang:BAAANQADCgQJBAAAAA==.Fortyskols:BAAANQADCgQIBQAAAA==.Foxxee:BAAANQADCgQIBAAAAA==.',
Fr='Freesamples:BAAANQAECgQIBwABNQAFFAUICgAcAEcUAA==.Friarpuck:BAABNQAECoEcAAMXAAYK0BqzIQC9AQAXAAYK0BqzIQC9AQAdAAUKGgMSLwCSAAAAAA==.Frostchi:BAAANQADCgcICQABNQAECgkJHwAHAIAfAA==.Frostdawn:BAAANQAECgQIBAABNQAECgkJHwAHAIAfAA==.Frosteye:BAABNQAECoEfAAIHAAkKgB+tAgABAwAHAAkKgB+tAgABAwAAAA==.Frozensalt:BAABNQAECoEjAAMGAAkKSyLHFgBoAwAGAAkKSyLHFgBoAwAHAAEK8iC2LQBUAAAAAA==.Fryerpuck:BAAANQAECgQIBAAAAA==.Fryssa:BAAANQAECgQIBgABNQAECgYIBgAPAAAAAA==.',
Fu='Furrbuddy:BAABNQAECoEUAAIeAAYKTBmbDgDEAQAeAAYKTBmbDgDEAQAAAA==.Furrsparta:BAAANQAECgUIDgAAAA==.',
Ga='Galiphe:BAABNQAECoEgAAIfAAgKhRMEDwDeAQAfAAgKhRMEDwDeAQAAAA==.Garidan:BAAANQAECgUICQAAAA==.',
Ge='Geeyyanni:BAABNQAECoEgAAIgAAgKYg9cCACzAQAgAAgKYg9cCACzAQAAAA==.Gentleeman:BAAANQADCgQIBAAAAA==.Geopetal:BAABNQAECoEhAAIhAAkKGhqiBgCkAgAhAAkKGhqiBgCkAgAAAA==.',
Gh='Ghasdros:BAABNQAECoEbAAIDAAkKYRhLKgCCAgADAAkKYRhLKgCCAgAAAA==.Ghostwin:BAAANQADCggIEAAAAA==.',
Gi='Gingy:BAAANQADCgQIBAABNQAECgQICAAPAAAAAA==.',
Gl='Gladefresh:BAAANQAECgYIDgAAAA==.Glowytwinkie:BAAANQAECgMIAwAAAA==.',
Go='Goldenice:BAAANQAECgYIDgAAAA==.Gooseriver:BAABNQAECoEhAAIeAAkKbCKjAgBWAwAeAAkKbCKjAgBWAwABNQADCgYJBgAPAAAAAA==.Gotthmog:BAAANQAECgEIAQAAAA==.Goyboi:BAAANQAECgQIBAAAAA==.',
Gr='Greylan:BAAANQADCgYIDAAAAA==.Greysha:BAAANQAECggIDwAAAA==.Grinzler:BAAANQAECgQIBQAAAA==.Grym:BAAANQAECgUJCQAAAA==.',
Gu='Guappo:BAAANQAECgQIDQAAAA==.',
Ha='Hafwyn:BAAANQADCgYIDAABNQAECgkJHAAIABISAA==.Hanor:BAAANQAECgYIBgAAAA==.Harløt:BAAANQAECgYIDgAAAA==.Hauntedblac:BAAANQAECgYIDgAAAA==.Hayley:BAAANQADCggJCQAAAA==.',
He='Heavenascend:BAAANQADCgcIBgAAAA==.Heraborn:BAAANQADCgMIAgAAAA==.',
Ho='Hojitalaurel:BAAANQADCgUIDAAAAA==.Holymacaroli:BAAANQAECgQICAAAAA==.Holysmiter:BAAANQAECgQIDQAAAA==.Holystrikér:BAAANQAECggICAAAAA==.Hoodfabulous:BAABNQAECoEXAAIiAAgKHBmOBgBLAgAiAAgKHBmOBgBLAgAAAA==.',
Hu='Huberto:BAAANQAECgEIAgAAAA==.Huntn:BAABNQAECoEWAAIOAAcK3A1UDwBeAQAOAAcK3A1UDwBeAQAAAA==.Hupyaptelyot:BAABNQAECoEYAAIGAAkKJh1tMwAHAwAGAAkKJh1tMwAHAwAAAA==.',
Hy='Hytierea:BAABNQAECoEYAAIjAAcKpRjodQDiAQAjAAcKpRjodQDiAQAAAA==.',
Ia='Iammudkip:BAAANQAECgUIBgAAAA==.',
Ih='Ihp:BAAANQAECgEIAQAAAA==.',
Il='Ilocku:BAAANQAFFAIIAgAAAQ==.',
Im='Imrac:BAAANQAECgIIAgABNQAECgkJKQAGAPkZAA==.Imshamazing:BAAANQADCgQIBAAAAA==.',
In='Incubus:BAABNQAECoEgAAIOAAgKXyA0AwDtAgAOAAgKXyA0AwDtAgAAAA==.',
Ir='Iriemon:BAAANQAECgcIEQAAAA==.',
Is='Isabeau:BAAANQADCgEIAQAAAA==.Issowimonk:BAAANQADCggIEQAAAA==.',
It='Italiaa:BAAANQAECgYIDQAAAA==.',
Ix='Ixtel:BAAANQAECgYIEwAAAA==.',
Ja='Jawesome:BAAANQAECgYIDAAAAA==.Jayron:BAAANQABCgYIBQAAAA==.',
Je='Jedakye:BAAANQAECgYIEQAAAA==.Jeepers:BAAANQAECgEIAgAAAA==.Jenzypoo:BAAANQAECgUIBwAAAA==.Jetson:BAABNQAECoEbAAIaAAcKWyKBDQCmAgAaAAcKWyKBDQCmAgAAAA==.',
Ji='Jiblits:BAAANQAECgEIAQABNQAECgkJIAAGAE0WAA==.Jinkies:BAAANQADCggIDAAAAA==.',
Jm='Jmama:BAAANQAECgQIBAAAAA==.',
Jo='Jojo:BAABNQAECoEcAAMLAAkKdhQmVgAIAgALAAgKXBUmVgAIAgAMAAEKQw1nawA4AAAAAA==.',
Jp='Jpow:BAAANQAECgYICwAAAA==.',
Ju='Junnarma:BAAANQAECgcICQAAAA==.',
['Já']='Járnviðr:BAABNQAECoEbAAMSAAgKtBL3XwADAgASAAgKtBL3XwADAgAkAAMK7RYcCwDbAAAAAA==.',
Ka='Kaalias:BAAANQAECgQIBAAAAA==.Kabrax:BAAANQADCggIBgAAAA==.Kai:BAAANQADCgYIBwABNQAECgkJHwAdAAkaAA==.Kaiula:BAABNQAECoEjAAICAAkKCxL+OQA+AgACAAkKCxL+OQA+AgAAAA==.Kalabar:BAABNQAECoEUAAILAAYKuRq9XgDsAQALAAYKuRq9XgDsAQAAAA==.Kaldrys:BAABNQAECoEvAAIEAAgKHBVNHAAYAgAEAAgKHBVNHAAYAgAAAA==.Kalnath:BAABNQAECoEjAAIOAAgK1R2uBACoAgAOAAgK1R2uBACoAgAAAA==.Kalynnah:BAAANQAECgQIBAAAAA==.Kamî:BAAANQAECgcICQAAAA==.Kanabo:BAAANQADCgMIAwABNQAECgIIAgAPAAAAAA==.Kanarra:BAAANQADCggIEAAAAA==.Kanatoo:BAAANQAECggIEgAAAA==.Kanekisenpai:BAACNQAFFIEHAAMMAAQKzgotDQCbAAAMAAIKNwgtDQCbAAALAAIKZg0mIwCUAAA1AAQKgS0AAwsACQrtIiAVAAoDAAsACQpTHyAVAAoDAAwABgqhHdANAAoCAAAA.Kanjam:BAABNQAECoEbAAIGAAgK5R9DSADOAgAGAAgK5R9DSADOAgAAAA==.Kaylina:BAAANQADCgQIBAAAAA==.Kazrar:BAAANQAECgMIAwAAAA==.',
Ke='Keepupheals:BAAANQADCgEIAQAAAA==.Keid:BAAANQAECgcIDwAAAA==.Kelai:BAABNQAECoEdAAIlAAkKiRy0GwCeAgAlAAkKiRy0GwCeAgAAAA==.Kellion:BAAANQAECgEIAgAAAA==.Kenobi:BAAANQADCgYIBgAAAA==.',
Ki='Kikks:BAAANQADCgEIAQAAAA==.Kilusuka:BAAANQADCggIDQABNQAECgYIEwAPAAAAAA==.',
Ko='Kobarr:BAAANQAECgYIEQAAAA==.Konbo:BAABNQAECoEgAAMcAAgKGyLzCgD/AgAcAAgKGyLzCgD/AgAYAAMKCB5aMwDiAAAAAA==.Koro:BAAANQAFFAEIBAAAAA==.Korvarith:BAAANQADCgQIBAAAAA==.',
Kr='Krapshoot:BAAANQAECgQJBAABNQAECggIGgAeAFsYAA==.Krolghoul:BAAANQAECgQIBAABNQAFFAYIFAAYACAfAA==.Krolgor:BAAANQAECgEIAQABNQAFFAYIFAAYACAfAA==.Krump:BAABNQAECoEbAAIjAAcK7yHzPACXAgAjAAcK7yHzPACXAgAAAA==.',
Ku='Kuramá:BAABNQAECoEUAAISAAYKgh6YUwAmAgASAAYKgh6YUwAmAgAAAA==.Kuyà:BAAANQADCggICAAAAA==.Kuzé:BAABNQAECoEUAAIkAAcKJw60BgDMAQAkAAcKJw60BgDMAQAAAA==.',
Kw='Kwyj:BAABNQAFFIEKAAIJAAQKCxi3CwBOAQAJAAQKCxi3CwBOAQAAAA==.Kwyjibo:BAABNQAECoEYAAIWAAkKWh0KIgByAgAWAAkKWh0KIgByAgAAAA==.',
Ky='Kylebroflov:BAABNQAECoEXAAIGAAgKmBBWngD+AQAGAAgKmBBWngD+AQAAAA==.Kyyguy:BAAANQADCgYICAAAAA==.',
['Kí']='Kíllermoon:BAAANQADCgQIBAABNQAECggIGgAVAPwTAA==.Kítkatz:BAAANQADCgUIBQAAAA==.',
['Kï']='Kïllerfrost:BAABNQAECoEaAAMVAAgK/BOEKAD0AQAVAAgK/BOEKAD0AQAlAAQKQAaIfgCzAAAAAA==.',
La='Labprotek:BAAANQAECgMIAwABNQAECgkJHwACAAUYAA==.Labülòus:BAABNQAECoEfAAICAAkKBRhFJQCiAgACAAkKBRhFJQCiAgAAAA==.Lafizz:BAAANQADCgYIBgAAAA==.Lambofgods:BAABNQAECoEgAAIlAAgKcQ6gQwCqAQAlAAgKcQ6gQwCqAQAAAA==.Lanana:BAAANQADCgEIAQAAAA==.',
Le='Lencel:BAAANQAECgEIAQAAAA==.Leonidas:BAAANQAECgYJCgAAAA==.Letmo:BAAANQADCgcICwAAAA==.Letmu:BAAANQADCgUICAABNQADCgcICwAPAAAAAA==.Levelfour:BAAANQADCgQIBgAAAA==.',
Li='Liannia:BAAANQADCgUIBwABNQAECgYIBgAPAAAAAA==.Lightningki:BAAANQAECgUIDAAAAA==.Lightofdawn:BAAANQADCgMIAwAAAA==.Lightscream:BAABNQAECoEdAAMCAAkKECDIDABCAwACAAkKECDIDABCAwAjAAEKdSAWOQFEAAAAAA==.Lilpanda:BAAANQADCgQIBAABNQAECgkJFgAKAL8VAA==.Lilshoobs:BAAANQAECgYIDQAAAA==.Lindariel:BAAANQADCgMIAwAAAA==.Lindir:BAABNQAECoEiAAITAAkK5iLMCwBxAwATAAkK5iLMCwBxAwAAAA==.Liparoonie:BAAANQAECgYIEAAAAA==.Liyt:BAAANQADCgIIAgABNQAECgQIBgAPAAAAAA==.',
Lo='Lockedupfoo:BAACNQAFFIEIAAMMAAQK7BijCgCoAAALAAMKYxWsFwDTAAAMAAIK5xGjCgCoAAA1AAQKgSUAAwsACQoIJAAaAO8CAAsACAojIwAaAO8CAAwABAr2GQwmAC8BAAAA.Lockfour:BAAANQAECgIIAgAAAA==.Locktorty:BAAANQADCgIIAgAAAA==.Lolmindflay:BAAANQADCgYIBgAAAA==.',
Lu='Ludd:BAAANQADCgQIAQAAAA==.Lunah:BAABNQAECoEeAAIDAAgKiR2lIgCqAgADAAgKiR2lIgCqAgAAAA==.Lupozz:BAABNQAECoEYAAIDAAgKJQkHYQCZAQADAAgKJQkHYQCZAQAAAA==.',
['Lå']='Låb:BAAANQAECgMIAwABNQAECgkJHwACAAUYAA==.',
Ma='Machahunt:BAAANQAECgYIDgAAAA==.Machico:BAAANQAECgcIEgAAAA==.Maetha:BAAANQAECgUICQAAAA==.Maggo:BAAANQAECgIIAgAAAA==.Magicdeadly:BAABNQAECoEUAAIGAAYK3g4j0wCPAQAGAAYK3g4j0wCPAQAAAA==.Magicol:BAAANQAECgQJBwABNQAECggIGAAYAHIKAA==.Magicá:BAAANQADCgYJBgABNQAECgQIDQAPAAAAAA==.Magosika:BAAANQAECgcIEQAAAA==.Maledizione:BAAANQAECgIIBAAAAA==.Manaburner:BAAANQAECgIJAgAAAA==.',
Me='Meerahs:BAAANQAECgcICwAAAA==.Megahorn:BAABNQAECoEcAAImAAkKvxi/GwB1AgAmAAkKvxi/GwB1AgAAAA==.Megthpallion:BAAANQAECgIIAgAAAA==.',
Mf='Mfhambone:BAAANQADCgIIAwAAAA==.',
Mi='Midliyt:BAAANQAECgQIBgAAAA==.Midniyt:BAAANQADCgQIBAABNQAECgQIBgAPAAAAAA==.Mikaylla:BAAANQADCgQICgAAAA==.Mikkilina:BAAANQAECgEJAQAAAA==.Mitric:BAAANQAECgcICwAAAA==.',
Mm='Mmeow:BAAANQAECgYICgAAAA==.',
Mo='Moowarrior:BAAANQAECgQJCAAAAA==.Mosswyn:BAAANQAECgIIAgAAAA==.',
Mu='Murmaiderr:BAAANQAECgQICQAAAA==.Murman:BAAANQADCggIEgAAAA==.',
Na='Nalla:BAAANQADCgYIBgAAAA==.Naravia:BAAANQAECgUIBgAAAA==.Narunî:BAAANQADCgYJDQAAAA==.Nater:BAAANQAECgYIDwAAAA==.',
Ne='Necrovyn:BAAANQADCgEIAQAAAA==.Nekkrosys:BAABNQAECoEeAAIWAAgK1AyLRQCcAQAWAAgK1AyLRQCcAQAAAA==.Nekrron:BAAANQADCggICgAAAA==.Neona:BAAANQAECgQIBQAAAA==.Nevets:BAAANQABCggIEQAAAA==.',
Ni='Nicessus:BAABNQAECoEcAAIIAAkKEhLoPwAWAgAIAAkKEhLoPwAWAgAAAA==.Nicksys:BAABNQAECoEWAAIjAAgKORobTQBeAgAjAAgKORobTQBeAgAAAA==.Nikkanika:BAAANQAECgQIBgABNQAECggIHQAjAEkWAA==.Niuzao:BAAANQADCgEIAQAAAA==.',
No='Noggenus:BAAANQABCgYIBwAAAA==.Norania:BAAANQAECgYICwAAAA==.Nork:BAAANQAECgYIEwAAAA==.Norko:BAAANQADCgQIBAAAAA==.Norks:BAAANQADCggIDgAAAA==.Normalname:BAAANQAECgEIAQAAAA==.Novembër:BAAANQAECgYIEQAAAA==.',
['Nÿ']='Nÿkon:BAAANQAECgIJAgABNQAECgcICQAPAAAAAA==.',
Od='Oderrus:BAAANQADCgUIBQABNQAECgQICQAPAAAAAA==.',
Ok='Okishama:BAACNQAFFIEHAAMTAAQKIxNoDwD8AAATAAMKxBVoDwD8AAAIAAIK2gozGACTAAA1AAQKgSwAAggACQpVIDkPACIDAAgACQpVIDkPACIDAAAA.',
On='Oneinchash:BAAANQAFFAEIAQABNQAFFAgIGgAmAFcfAA==.Onkrack:BAAANQAECgEIAQABNQAECgYIEwAPAAAAAA==.Onlyfanzz:BAAANQADCgYJBgAAAA==.',
Op='Ophelastra:BAAANQAECgQIBQAAAA==.',
Oz='Ozfiz:BAAANQADCgYIBgABNQAECgYIFgAeAJAjAA==.Ozwiz:BAAANQADCgMIAwABNQAECgYIFgAeAJAjAA==.',
Pa='Pandatastic:BAACNQAFFIEIAAIIAAMKoRO6DQABAQAIAAMKoRO6DQABAQA1AAQKgS4AAwgACQr0JakCAKsDAAgACQr0JakCAKsDABMABwpCGO1QAOQBAAAA.Papishadow:BAAANQAECgUIBQAAAA==.Pastrami:BAABNQAECoEkAAIWAAgKmR33HwCCAgAWAAgKmR33HwCCAgAAAA==.Patbee:BAAANQADCgIIBAABNQADCgQIAQAPAAAAAA==.Pawn:BAAANQADCgcICAAAAA==.',
Pe='Pearlsham:BAABNQAECoEYAAIIAAcKySBFKACGAgAIAAcKySBFKACGAgAAAA==.Peekaaboo:BAAANQAECgIIAgAAAA==.',
Ph='Phikkle:BAAANQADCgUIBgAAAA==.Phâtè:BAAANQAECgIIBAAAAA==.',
Pi='Picesty:BAABNQAECoEgAAMGAAkKTBR1dQBdAgAGAAkKTBR1dQBdAgAHAAEKzwzmPAAvAAABNQABCgYIBwAPAAAAAA==.Pikkle:BAAANQAECgIIAgAAAA==.Pilikiä:BAAANQADCgcIBwAAAA==.Pipsqueekx:BAAANQAECgEIAQABNQAECggJAQAPAAAAAA==.',
Pk='Pkflash:BAAANQAECgQICwAAAA==.',
Pl='Platinumbull:BAABNQAECoEfAAIBAAgKzhHqcADzAQABAAgKzhHqcADzAQAAAA==.Pleabsham:BAAANQAECgUICgAAAA==.Plikka:BAAANQAECgQICAABNQAECggIHQAjAEkWAA==.',
Po='Pokentotem:BAAANQAECgQICAAAAA==.Potlogic:BAAANQAECgUIDwABNQAECgkJLwAHAOMcAA==.',
Pr='Prandel:BAAANQABCgMJAwABNQAECgQICQAPAAAAAA==.Prosciutto:BAAANQABCgQIBgAAAA==.',
Pu='Puddl:BAAANQAECgYIDAAAAA==.Punkii:BAABNQAECoEeAAISAAkKaiMHEQA3AwASAAkKaiMHEQA3AwAAAA==.Punnisher:BAAANQADCgYIBgAAAA==.',
Qp='Qpawnz:BAAANQAECgUIBwABNQAFFAUIDAALAFQVAA==.',
Qu='Quidamtyra:BAAANQAECgUIDAAAAA==.Quigonjin:BAAANQAECgMIAgAAAA==.',
Ra='Rabbifrost:BAAANQADCggICAAAAA==.Rackem:BAAANQADCgEIAQAAAA==.Rackham:BAABNQAECoEdAAIbAAkKlhQGDwBIAgAbAAkKlhQGDwBIAgAAAA==.Radiana:BAAANQAECgUICQAAAA==.Raeknor:BAAANQAECgYJDgAAAA==.Ragequake:BAAANQABCgMIAwAAAA==.Ramaran:BAAANQADCgIJAgABNQAECgQICAAPAAAAAA==.Ramrocket:BAAANQADCgYIBgABNQAECgUIBQAPAAAAAA==.Randomaction:BAABNQAECoEUAAIhAAYKaRWiDwCgAQAhAAYKaRWiDwCgAQAAAA==.Rankors:BAAANQADCgEIAQAAAA==.Rastabution:BAAANQAECggIAQABNQAECgkKGAAdAMEPAA==.Rathvyr:BAACNQAFFIEHAAIBAAQK2BeFDwBLAQABAAQK2BeFDwBLAQA1AAQKgTUAAgEACQqzJWsDANMDAAEACQqzJWsDANMDAAAA.Ravenskeet:BAAANQADCggIDwABNQAECgUICAAPAAAAAA==.Raymon:BAAANQAECgEIAQAAAA==.Razuriell:BAABNQAECoEcAAIKAAgKJiL6CgASAwAKAAgKJiL6CgASAwAAAA==.',
Re='Reagan:BAAANQABCgIIAgAAAA==.Rebeakah:BAAANQAECgcIDwAAAA==.Redbash:BAAANQAECgUIBQAAAA==.Reggs:BAAANQAECgUICAAAAQ==.Renko:BAABNQAECoEgAAIUAAgKIiRUCAAmAwAUAAgKIiRUCAAmAwAAAA==.',
Ri='Ribitey:BAACNQAFFIEPAAIDAAUKKSImBQAGAgADAAUKKSImBQAGAgA1AAQKgSAAAgMACQq1JjAAAAMEAAMACQq1JjAAAAMEAAAA.Riggs:BAAANQADCgcIEQAAAA==.Riggster:BAABNQAECoEiAAIWAAgKkx85FgDRAgAWAAgKkx85FgDRAgAAAA==.Rilakuma:BAAANQAECgYIEAAAAA==.',
Ro='Robzombíe:BAAANQADCgUIBgABNQAECggIGgAeAFsYAA==.Rockyballz:BAAANQADCgEIAQAAAA==.Rolando:BAABNQAECoEmAAIBAAgK3xOQdADoAQABAAgK3xOQdADoAQAAAA==.Rosybel:BAAANQADCgQIBAAAAA==.Rotimus:BAAANQADCgIIAgAAAA==.Row:BAAANQABCgMIAwAAAA==.Royaumm:BAAANQAECgIIAgAAAA==.Rozewyn:BAABNQAECoEeAAIDAAgKOwggYgCUAQADAAgKOwggYgCUAQAAAA==.',
Ru='Rukator:BAAANQAECgMIBAAAAA==.',
Ry='Ryawhitefang:BAABNQAECoEgAAMSAAkKtyWPAwC6AwASAAkKtyWPAwC6AwARAAMK6hpQRwC9AAAAAA==.Ryvoon:BAAANQADCgUJBQAAAA==.',
['Rà']='Ràgé:BAAANQAECgMIBQAAAA==.',
['Rê']='Rêddit:BAAANQADCggICAAAAA==.',
Sa='Salael:BAABNQAECoEkAAIhAAkKdxjZBgCbAgAhAAkKdxjZBgCbAgAAAA==.Saphi:BAAANQADCggICAAAAA==.Saphinia:BAAANQAECgUIBQAAAA==.Saphirin:BAACNQAFFIEHAAIlAAQKbhKHDQAVAQAlAAQKbhKHDQAVAQA1AAQKgSkAAiUACQqPG3AeAIkCACUACQqPG3AeAIkCAAAA.Sarapallyn:BAAANQABCgEIAQAAAA==.Sariphi:BAAANQADCgQIBAAAAA==.Sauron:BAAANQADCggIEgAAAA==.Savagebrain:BAAANQADCgUIBwABNQAECgkJIwAGALMiAA==.Savagelung:BAABNQAECoEjAAIGAAkKsyKIGQBdAwAGAAkKsyKIGQBdAwAAAA==.Saya:BAAANQADCgYIBgAAAA==.',
Sc='Schoonie:BAAANQADCgYIDAAAAA==.Schutzengel:BAACNQAFFIEIAAIIAAQKSgfADAAVAQAIAAQKSgfADAAVAQA1AAQKgR0AAggACQrLG9EgAK8CAAgACQrLG9EgAK8CAAAA.Scribbl:BAABNQAECoElAAMMAAkKHSVXAADXAwAMAAkKHSVXAADXAwALAAMKmBojzgDJAAAAAA==.Scylon:BAABNQAECoEXAAMjAAgKmR3LOQCjAgAjAAgKmR3LOQCjAgAQAAEKYRTsVAA5AAAAAA==.Scythen:BAAANQADCgYIBgAAAA==.',
Se='Selinda:BAAANQAECgQICAAAAA==.Sencerity:BAAANQADCgEIAQAAAA==.Serana:BAAANQAECgYIDgAAAA==.',
Sh='Shadowbanned:BAAANQADCgUIBQAAAA==.Shallowgrave:BAABNQAECoEXAAMWAAgKBhS/NwDmAQAWAAgKABO/NwDmAQAVAAMKiggaZwCNAAAAAA==.Shamanhands:BAAANQAECgUJCAAAAA==.Shammyhaggar:BAAANQAECgUIEQAAAA==.Shamram:BAAANQAECgQICAAAAA==.Shamywamy:BAAANQAECggIEwAAAA==.Shamywamydk:BAAANQAECgEIAQAAAA==.Shaodh:BAAANQADCgUIBQAAAA==.Shaodk:BAABNQAECoEYAAMVAAgKsBfeOAB/AQAVAAcKFBPeOAB/AQAWAAYKTBS6TgBxAQAAAA==.Sharkeesha:BAAANQADCgQIBAAAAA==.Shawdi:BAAANQABCgIIAgAAAA==.Shibs:BAAANQADCgQIBAAAAA==.Shiffty:BAAANQAECgQIDQAAAA==.Shiggadin:BAABNQAECoEcAAICAAgKNRloMABpAgACAAgKNRloMABpAgAAAA==.Shiggadow:BAAANQADCggICAABNQAECggIHAACADUZAA==.Shiggalaw:BAABNQAECoEVAAIcAAgK2BBKIgATAgAcAAgK2BBKIgATAgABNQAECggIHAACADUZAA==.Shikki:BAAANQAECgQICAAAAA==.Shinys:BAABNQAECoEZAAIGAAkKKhi4VQCrAgAGAAkKKhi4VQCrAgAAAA==.Shockadelica:BAAANQADCggICQABNQAECgcIEQAPAAAAAA==.Shuki:BAAANQADCgEIAQAAAA==.Shámtastic:BAAANQAECgIIAgAAAA==.Shäde:BAACNQAFFIEIAAIYAAQKRwqGBwA0AQAYAAQKRwqGBwA0AQA1AAQKgR8AAhgACQp5GnIKALQCABgACQp5GnIKALQCAAAA.',
Si='Simpai:BAAANQAFFAEIAQAAAA==.Sinzspirits:BAAANQAECggIAgAAAA==.',
Sk='Skadi:BAAANQAECgcIBwAAAA==.Skaman:BAAANQABCgcIBgAAAA==.Skiethx:BAACNQAFFIEIAAMYAAUKIxZjBgBkAQAYAAQKrhNjBgBkAQAcAAEK9x9/EABbAAA1AAQKgR4AAxgACQqaH4wNAIECABgABwqiH4wNAIECABwABAqQGP5HABIBAAAA.Skipii:BAAANQAECgQJBgAAAA==.Skullderzix:BAAANQAECgUICAABNQAECgYICgAPAAAAAA==.Skullderzxx:BAAANQAECgYICgAAAA==.',
Sl='Slamshazam:BAAANQABCgYIBgABNQADCgUIBQAPAAAAAA==.Sleeptoken:BAAANQAECggIEAABNQAECggIHQABAFoZAA==.Slopersafari:BAABNQAECoEWAAMHAAgKlg2FFQATAQAGAAgKGglJugDAAQAHAAUKaxGFFQATAQAAAA==.Slowqt:BAABNQAECoEqAAIWAAkKCSTACABYAwAWAAkKCSTACABYAwAAAA==.',
Sm='Smashyz:BAAANQAECgQIBAABNQADCgYJBgAPAAAAAA==.',
Sn='Sneakytwinky:BAAANQADCgcIBwAAAA==.',
So='Somaria:BAAANQAECgYIDwAAAA==.Sonabrie:BAAANQADCggIEQAAAA==.',
Sp='Spankybottom:BAAANQAECgYIDgAAAA==.Sparykz:BAAANQADCggIEAABNQAECgQICQAPAAAAAA==.Spiyt:BAAANQADCgQIBgABNQAECgQIBgAPAAAAAA==.Spnkynvrsoft:BAABNQAECoEgAAMEAAkKIhLyGQA1AgAEAAkKIhLyGQA1AgADAAgKcxFdUADcAQAAAA==.',
Sq='Squeaky:BAAANQAECgYIDQAAAA==.Squee:BAAANQAECgYIEwAAAA==.',
Sr='Srmonkey:BAAANQADCggIFQAAAA==.',
St='Stabachacha:BAACNQAFFIEKAAMcAAUKRxRCAwCsAQAcAAUKRxRCAwCsAQAYAAEKwgO4EQBDAAA1AAQKgSMAAxwACQpEHmEUAI8CABwACAqfHGEUAI8CABgABwpwHI4WAAkCAAAA.Steamicyhott:BAAANQAECgUICQAAAA==.Steveandkink:BAAANQABCgcIBwAAAA==.Stgmavrick:BAAANQAECggIAQAAAA==.Stinkie:BAAANQAFFAEIAQAAAA==.Stonebeard:BAAANQADCgYJCgAAAA==.Stormcore:BAAANQAECgQIBwAAAA==.Stubbystaber:BAAANQAECgYIBgABNQAECgcICQAPAAAAAA==.',
Su='Sunny:BAAANQAECgMIBgAAAA==.Supernóva:BAAANQADCgQIBAABNQAECgYJCgAPAAAAAA==.',
Sw='Swampybutt:BAAANQAECgQIBAAAAA==.',
Sy='Sylvanass:BAAANQADCgYICAAAAA==.Sylverarrow:BAAANQAECgQIBwAAAA==.Syreith:BAAANQADCgQIBQAAAA==.',
Ta='Tacabell:BAABNQAECoEeAAIGAAkK4BNMawB1AgAGAAkK4BNMawB1AgAAAA==.Taken:BAABNQAECoEpAAMTAAkKGRx8HADwAgATAAkKGRx8HADwAgAnAAEKoAfgKQBAAAAAAA==.Tamayinna:BAAANQAECgEIAQAAAA==.Tankhealsdps:BAAANQAECgEIAQAAAA==.Tarkarram:BAAANQAECgYIDAAAAA==.Tarnfair:BAAANQAECgIIAgAAAA==.Taurìel:BAAANQAECgMIAgAAAA==.Taven:BAAANQAFFAIIAwAAAA==.',
Te='Technique:BAAANQAECgEIAQAAAA==.Tekka:BAAANQAECgYIDgAAAA==.Telegram:BAAANQADCgMIBAAAAA==.Telvor:BAAANQAECgQIDQAAAA==.Teminar:BAAANQADCggJCAAAAA==.Terakore:BAAANQADCgEIAQABNQAECgcIGAAiAHwiAA==.Terrukk:BAAANQAECgUIDAAAAA==.Tessalie:BAAANQADCggICwAAAA==.Teufelsnudel:BAAANQAECgcIEwAAAA==.',
Th='Thelysong:BAAANQAECgIJBAAAAA==.Therena:BAAANQADCggICAAAAA==.Therran:BAABNQAECoEdAAIjAAgKSRZdaAAIAgAjAAgKSRZdaAAIAgAAAA==.Theuss:BAAANQAECgUICwAAAA==.Thewonderkid:BAAANQADCgYICQAAAA==.Thexador:BAAANQAECgIIAgAAAA==.Thormin:BAAANQAECggICQAAAA==.Thorraden:BAAANQADCgMIAwABNQAECgQICQAPAAAAAA==.Thranduill:BAAANQAECgUICgAAAA==.Thras:BAAANQADCggICAAAAA==.',
Ti='Tidefury:BAAANQAECgYIDgAAAA==.Tidepod:BAAANQAECgYIBgABNQAECgkJIgAmAB8mAA==.Tigerclaw:BAAANQAECgIIAwAAAA==.Tilley:BAAANQADCgYICwAAAA==.Timber:BAAANQABCgYIDQAAAA==.Tingaling:BAABNQAECoEWAAIeAAYKkCNlCABpAgAeAAYKkCNlCABpAgAAAA==.',
Tl='Tlock:BAAANQAECgYIEwAAAA==.',
To='Tool:BAAANQABCgIJAgAAAA==.Toothdh:BAAANQADCggJDgABNQADCggIDwAPAAAAAA==.Toothlss:BAAANQAECgIIAgABNQADCggIDwAPAAAAAA==.Toragza:BAAANQAECgIJAwAAAA==.Totums:BAAANQAECgYIDgAAAA==.Toyletpaypah:BAAANQAECgYIAwABNQAECgkJGAAGACYdAA==.Toyletwahtah:BAAANQAECgYIAgABNQAECgkJGAAGACYdAA==.',
Tr='Trashyz:BAAANQAECgYIBwABNQADCgYJBgAPAAAAAA==.Treseme:BAAANQABCgIIAgAAAA==.Triaradea:BAAANQAECgEIAQABNQAECgIIAgAPAAAAAA==.Tribalz:BAABNQAECoEgAAIJAAgKMQ59OADcAQAJAAgKMQ59OADcAQAAAA==.Trunddle:BAABNQAECoEUAAMdAAQKKAfVLwCMAAAdAAQKwAXVLwCMAAAhAAIKBglTJQBoAAAAAA==.',
Tu='Tuchmydemons:BAAANQAECgYIDwAAAA==.Tugmahog:BAAANQAECgIIAgAAAA==.',
Ty='Tygrelilly:BAAANQAECgQIBAAAAA==.Tyrieal:BAAANQAECgYIDQAAAA==.',
['Të']='Tën:BAAANQADCgMIAwAAAA==.',
['Tø']='Tøøthlss:BAAANQADCggIDwAAAA==.',
Ul='Ulidan:BAAANQADCgIIAgAAAA==.',
Un='Ungoloth:BAAANQADCgMIAwABNQAECgcIGAAiAHwiAA==.',
Va='Vamp:BAAANQAECgcIDQAAAA==.Vanêssa:BAAANQAECgEIAgAAAA==.Varner:BAABNQAECoEhAAIJAAkKniJ+CAB3AwAJAAkKniJ+CAB3AwAAAA==.',
Ve='Velaria:BAAANQAECgQIBAAAAA==.',
Vi='Vindict:BAAANQAECgEJAQAAAA==.',
Vl='Vlakshift:BAABNQAECoEbAAUJAAgKjhwrHwCfAgAJAAgKjhwrHwCfAgAhAAEKrxIGKQBHAAAdAAEKxxZxPAA+AAAXAAEKbwTMXAAuAAAAAA==.Vlaksneaks:BAAANQADCggICAABNQAECggIGwAJAI4cAA==.',
Vo='Voltedarrow:BAAANQAECggJBwAAAA==.Voltedpriest:BAAANQAECggIBAAAAA==.Voltedrage:BAAANQAECggIBgAAAA==.Vongalas:BAAANQAECgUIDAAAAA==.Vongimi:BAAANQAECgUIDQAAAA==.Vongimiv:BAAANQADCgYIDAABNQAECgUIDQAPAAAAAA==.Vork:BAAANQAECgIIAgAAAA==.Voucher:BAACNQAFFIEMAAMLAAUKVBX/DAA7AQALAAQKvBL/DAA7AQAMAAEKth/MEABgAAA1AAQKgSAAAwsACQoQIaw6AGYCAAsABwpQIaw6AGYCAAwAAgouIC9BAKkAAAAA.',
Vy='Vyn:BAAANQAECgYICgAAAA==.Vynstarcyon:BAAANQAECgQIBAAAAA==.Vysérå:BAAANQAECgYIDwAAAA==.',
Wa='Wai:BAABNQAECoEhAAMjAAkKGyBWJAD/AgAjAAkKGyBWJAD/AgACAAEKOQb5+QAoAAAAAA==.Warglaíve:BAABNQAECoEnAAImAAkKvx6fDAAXAwAmAAkKvx6fDAAXAwAAAA==.Wasted:BAABNQAECoEaAAMeAAgKWxiSCgAsAgAeAAgKWxiSCgAsAgAUAAUKtQiyPQC6AAAAAA==.',
We='Weg:BAAANQADCgQIBAAAAA==.',
Wh='Whilsohn:BAAANQADCgcJCgAAAA==.Whilson:BAAANQADCggIFgAAAA==.Whilsonh:BAAANQADCggIFAABNQADCggIFgAPAAAAAA==.Whisky:BAAANQABCgEIAQAAAA==.',
Wi='Wildbillee:BAAANQAECgUIDAABNQAECgkJMgAMADsfAA==.Wildbilly:BAABNQAECoEdAAMcAAkKUhHcHwAoAgAcAAgKNhPcHwAoAgAYAAUKiwuGLQAbAQABNQAECgkJMgAMADsfAA==.Wildbily:BAAANQADCggIEAABNQAECgkJMgAMADsfAA==.Wilhson:BAAANQADCgcIDAABNQADCggIFgAPAAAAAA==.Wilsuhn:BAAANQADCgYICAABNQADCggIFgAPAAAAAA==.Winterveil:BAAANQADCgYIBwAAAA==.Witchblade:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.',
Wo='Woolworm:BAAANQABCgIIAgAAAA==.Worldwaker:BAABNQAECoEkAAMUAAkK2Bd9GAAvAgAUAAgKpRh9GAAvAgAbAAkKrg5lFADgAQAAAA==.Wornn:BAAANQADCgYICQAAAA==.',
Wr='Wretched:BAABNQAECoEdAAINAAkK5COFAACCAwANAAkK5COFAACCAwAAAA==.',
Wu='Wukard:BAAANQAECgYIEgAAAA==.',
Wy='Wylblly:BAAANQAECgUICAABNQAECgkJMgAMADsfAA==.Wyldbill:BAABNQAECoEyAAQMAAkKOx/bCABeAgAMAAYKpCLbCABeAgALAAUK2Q7QngA0AQANAAEKeCT8HABeAAAAAA==.',
['Wó']='Wóoglin:BAAANQAECgQIBAAAAA==.',
Xa='Xaltier:BAAANQADCgYIBgAAAA==.Xanthrid:BAAANQAECgUIBQAAAA==.Xarxzez:BAABNQAECoEWAAMGAAYK5iFArQDdAQAGAAUKDyJArQDdAQAHAAIKgB7WHwCuAAAAAA==.',
Xe='Xenius:BAAANQADCgMJAwAAAA==.Xer:BAAANQABCgQIBAAAAA==.',
Xf='Xfaeble:BAABNQAECoEZAAIDAAkKRxrkIwCjAgADAAkKRxrkIwCjAgABNQAECgkJHAAaAJwPAA==.',
Xg='Xgambit:BAABNQAECoEVAAMfAAQKHBiHHwDvAAABAAQKGxQryQDyAAAfAAQKPxSHHwDvAAAAAA==.',
Xp='Xprtdemon:BAAANQAECgUICQAAAA==.',
Xy='Xylar:BAAANQADCgUIBQAAAA==.Xyno:BAAANQAECgcIEwAAAA==.',
['Xû']='Xûrû:BAAANQADCggICAAAAA==.',
Ya='Yandora:BAAANQADCgIIAgAAAA==.',
Yo='Yoggibear:BAAANQAECgUIBQAAAA==.Yoreick:BAAANQADCgUIBQAAAA==.',
Yu='Yuckmouth:BAABNQAECoEvAAMHAAkK4xwZAwDkAgAHAAkK4xwZAwDkAgAGAAIKchAPawF1AAAAAA==.Yuli:BAAANQAECgMIAwABNQAECgUIDwAPAAAAAA==.',
Za='Zadaen:BAAANQAECgYIEAAAAA==.Zaladren:BAAANQAECgEIAQAAAA==.Zave:BAAANQAECggICgAAAA==.',
Ze='Zendarus:BAAANQAECgYIDAAAAA==.Zenshot:BAAANQAECgcIEQAAAA==.Zerazenazath:BAAANQAECgUIBQAAAA==.',
Zi='Ziegevolk:BAAANQAECgIIAgAAAA==.',
Zo='Zoobra:BAAANQADCggIFAAAAA==.Zorkky:BAAANQAECgEIAQAAAA==.',
Zu='Zubinator:BAAANQAECgUIDAAAAA==.Zulteld:BAAANQADCgMIAwABNQAECgQICQAPAAAAAA==.',
['Ác']='Áchu:BAABNQAECoEZAAMIAAkKGxZEKgB8AgAIAAkKGxZEKgB8AgATAAUKTwf0twDJAAAAAA==.',
['Âr']='Ârrgh:BAABNQAECoEYAAITAAYKLhBBdgBpAQATAAYKLhBBdgBpAQAAAA==.',
['Än']='Änh:BAAANQAECgQJCAAAAA==.',
['Êk']='Êkkô:BAAANQAECgEIAQABNQAECggIDwAPAAAAAA==.',
['Ðe']='Ðestroyer:BAAANQAECgQIBwAAAA==.',
['Ðj']='Ðjinzen:BAAANQAECgEIAQAAAA==.',
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
