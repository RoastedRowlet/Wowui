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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Priest-Discipline','Unknown-Unknown','Druid-Balance','Shaman-Restoration','DeathKnight-Unholy','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DeathKnight-Frost','DemonHunter-Devourer','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Hunter-Survival','Priest-Shadow','DemonHunter-Havoc','Warlock-Affliction','Rogue-Subtlety','Shaman-Elemental','Monk-Mistweaver','Druid-Restoration','Evoker-Preservation','Monk-Brewmaster','Mage-Frost','Paladin-Holy',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aarazi:BAABNQAECoEeAAIBAAgKSx2jWAC9AgABAAgKSx2jWAC9AgAAAA==.',
Ab='Abbinormal:BAAANQADCgUIEQAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIDgAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aezili:BAAANQADCgcICQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAAANQAECgYIEwAAAA==.',
Ah='Ahaego:BAAANQAECgUICAAAAA==.Ahnari:BAAANQAECgEIAQAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAABNQAECoEbAAICAAgKgRo/NgClAgACAAgKgRo/NgClAgAAAA==.',
Al='Alacardias:BAABNQAECoEbAAIDAAgK5honTwB/AgADAAgK5honTwB/AgAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAAANQAECgcIBwAAAA==.Allthesnacks:BAAANQADCgUIBQAAAA==.Aloe:BAAANQADCgYIBgAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFIEGAAIEAAIK1yI/HADPAAAEAAIK1yI/HADPAAA1AAQKgRYAAwQACAoiJI0ZAPcCAAQACAoQJI0ZAPcCAAUABArUGEwPAB8BAAAA.',
An='Anassand:BAAANQAECgcICQABNQAECgcIEgAGAAAAAA==.Anatomic:BAAANQADCgIIAgABNQAECgUICwAGAAAAAA==.Andimorph:BAABNQAECoEbAAIHAAgKaBgsLABVAgAHAAgKaBgsLABVAgAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAABNQAECoEeAAICAAgKxw/iZQAeAgACAAgKxw/iZQAeAgAAAA==.',
Aq='Aqualight:BAAANQAECgIIAgABNQAECgkJIwAIAAMhAA==.Aquashade:BAAANQAECgUIBQABNQAECgkJIwAIAAMhAA==.Aquaterra:BAABNQAECoEjAAIIAAkKAyHhCgBVAwAIAAkKAyHhCgBVAwAAAA==.Aquina:BAAANQAECgYIDAABNQAECgkJIwAIAAMhAA==.',
Ar='Arakadia:BAABNQAECoEoAAIJAAgKgxH2SwC+AQAJAAgKgxH2SwC+AQAAAA==.Arcaina:BAAANQADCggICAAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAAANQAECgYIEQAAAA==.',
As='Aseanna:BAAANQAECgIIBQAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgkJJgAKAN4lAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgAGAAAAAA==.',
Av='Avarous:BAAANQAECgYIEwAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECgcIEgAGAAAAAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAABNQAFFIEKAAIDAAMKkh9BDgArAQADAAMKkh9BDgArAQAAAA==.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECoEYAAILAAkKNBZGDQB/AgALAAkKNBZGDQB/AgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgYIEAAAAA==.Barbedwire:BAAANQAECgIIAgAAAA==.',
Be='Bearmao:BAABNQAECoEiAAICAAgK2RyeNACrAgACAAgK2RyeNACrAgAAAA==.Beknight:BAABNQAECoEfAAIMAAgKeh20HQCqAgAMAAgKeh20HQCqAgAAAA==.Belfas:BAAANQAECgIIAwAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgUICAAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECgcIBwAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAABNQAECoEiAAIMAAgKORzDKwBNAgAMAAgKORzDKwBNAgAAAA==.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcICAAAAA==.Bruute:BAABNQAECoEoAAINAAkKzSILFABiAwANAAkKzSILFABiAwAAAA==.',
Bu='Budplatinum:BAAANQAECgQIBQAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQADCgcIBwAAAA==.',
Ca='Cairo:BAABNQAECoEkAAMOAAgKfCE7CQCOAgAOAAcKVyI7CQCOAgANAAgK1BxcTACKAgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECoEmAAIPAAcK6xhmCQAaAgAPAAcK6xhmCQAaAgABNQAECgkJKAABAKAQAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECoEoAAIBAAkKoBAglQA5AgABAAkKoBAglQA5AgAAAA==.',
Ce='Cell:BAABNQAECoEoAAIQAAkKcR/IAgAoAwAQAAkKcR/IAgAoAwAAAA==.Ceviche:BAAANQAECgYJCAAAAA==.Ceàrrdòrn:BAAANQAECgUICwAAAA==.',
Ch='Chibí:BAAANQADCggIFgAAAA==.Chillzmatic:BAAANQAECgIIBAAAAA==.Chudbucket:BAABNQAECoEXAAMCAAcKoRo9eADwAQACAAYKQB09eADwAQARAAMKJQ71WgCTAAAAAA==.',
Ci='Cirillø:BAAANQABCggICAABNQAECgkJJAASAGYlAA==.',
Cl='Clovergold:BAABNQAECoEeAAIDAAkKLRyNPwCxAgADAAkKLRyNPwCxAgAAAA==.Clyde:BAABNQAECoEXAAMTAAcKqQogJQAmAQATAAcKqQogJQAmAQAUAAMKQATzKwBvAAAAAA==.',
Co='Corbis:BAABNQAECoEWAAMJAAcKYQtrdAAeAQAJAAYKoAtrdAAeAQAVAAUKJwYUYgDPAAAAAA==.',
Cr='Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQAECgMIAwAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQAECgMIAwAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIJBAAAAA==.Dan:BAAANQAECgUICQAAAA==.Danthrax:BAAANQAECgMIAwAAAA==.Darkdemon:BAAANQAECgUIEAAAAA==.Darlord:BAAANQAECgMIAwAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgkJJgAKAN4lAA==.Deandrya:BAAANQAECggIAQAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgMIAwAAAA==.Demônlock:BAAANQAECgMIAwAAAA==.Desideria:BAAANQAECgYIDgAAAA==.Despondence:BAABNQAECoEiAAIWAAgKER5eEgDDAgAWAAgKER5eEgDDAgAAAA==.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQAECgMIAwAAAA==.Djtaki:BAABNQAECoEoAAIXAAgKvRmjHQBoAgAXAAgKvRmjHQBoAgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAYIEgAUAHohAA==.Doncarlos:BAABNQAECoEpAAICAAkKxR6yHQAGAwACAAkKxR6yHQAGAwAAAA==.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFIEVAAMYAAYKFBN7AgDrAAAZAAQKGxdAEQBEAQAYAAMKOhB7AgDrAAA1AAQKgSQAAxkACQq/IVglANYCABkACAq2IVglANYCABgABAomGocqAB0BAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgQIBAAAAA==.Dròòid:BAAANQADCgQJBAABNQAECggIIgAMADkcAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIEQAAAA==.',
Dw='Dwín:BAAANQAECgcIEwAAAA==.',
['Dê']='Dêals:BAAANQAECgYIEwAAAA==.',
Ed='Edgelordxx:BAAANQADCgcICAAAAA==.',
El='Elasper:BAAANQADCgcICQAAAA==.Eliselyia:BAAANQADCgYIFwAAAA==.Ellierose:BAAANQAECgcIEgAAAA==.',
Em='Emelianas:BAAANQAECgQIBAABNQAECggIKAAJAIMRAA==.Ems:BAAANQAECgEIAQAAAA==.',
En='Enjin:BAABNQAECoEnAAMCAAgK7iE/FwAmAwACAAgK1iE/FwAmAwAaAAMK2xv8DADAAAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAECggIKwAbADoZAA==.Entheogen:BAAANQAECgUIDgAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgEIAQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAAANQAECggIBwAAAA==.',
Et='Ethereall:BAABNQAECoEXAAMWAAkKlxlRFgCXAgAWAAkKlxlRFgCXAgAcAAMKOQFKgQA4AAAAAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAABNQAECoEgAAIDAAcKhw8HpgCcAQADAAcKhw8HpgCcAQAAAA==.Evoka:BAAANQAECgEIAgAAAA==.',
Fa='Faavibear:BAAANQAECggJAQAAAA==.Fallendevout:BAAANQAECgQICAAAAA==.Fallentroll:BAABNQAECoEdAAMJAAkKzRmQNAA0AgAJAAkKPBmQNAA0AgAMAAMK4RrFfgDYAAAAAA==.Fatdoinkers:BAAANQAECgUICAABNQAECggIEQAGAAAAAA==.Fatman:BAAANQADCgUIBQABNQADCgIIAwAGAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggICAAAAA==.Fayye:BAAANQAECgUIBwAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgIIBgAGAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgIIBgAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAABNQAECoEmAAIBAAkK1h67LwAiAwABAAkK1h67LwAiAwAAAA==.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQADCgcJAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAAANQAECgcJDgAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAECggIIgAMADkcAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECoEdAAQZAAgK2xGtZwD/AQAZAAgK2xGtZwD/AQAYAAIKzQ99VgBxAAAdAAIK5wpuIABeAAAAAA==.Galorfax:BAAANQAECgYIEwAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECoEgAAICAAkKqCC0EwA5AwACAAkKqCC0EwA5AwABNQAECgkJKAANAM0iAA==.',
Ge='Gelinea:BAAANQADCgMICQAAAA==.Genovese:BAAANQADCgYJDAABNQAECgcIFgAJAGELAA==.',
Gi='Gilgaroth:BAABNQAECoEaAAMXAAgKUxqgJwAhAgAXAAcKshegJwAhAgAeAAgKfBMRFgAgAgAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAYIEgAUAHohAA==.',
Go='Gobo:BAAANQAECgYIDQAAAA==.',
Gr='Graysonn:BAAANQADCggIFQAAAA==.Greafox:BAAANQAECggIEwAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECgYIBgABNQAFFAYIEgAUAHohAA==.Gundrakk:BAAANQAECgUICwAAAA==.Gunnr:BAAANQAECgQICQABNQAECgcIDAAGAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
Ha='Handsomemonk:BAAANQADCgMIAwABNQAECggIEQAGAAAAAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgcIDQAGAAAAAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQADCgcICQAAAA==.',
Hi='Higanbana:BAACNQAFFIEWAAIWAAYK6hkrAwAXAgAWAAYK6hkrAwAXAgA1AAQKgSwAAhYACQraI+gEAH4DABYACQraI+gEAH4DAAAA.Himawari:BAABNQAECoEYAAIDAAgKayBhPQC4AgADAAgKayBhPQC4AgABNQAFFAYIFgAWAOoZAA==.Himejoshi:BAACNQAFFIESAAIUAAYKeiE9AABfAgAUAAYKeiE9AABfAgA1AAQKgTAAAhQACQqiJs4AANcDABQACQqiJs4AANcDAAAA.Hippocampus:BAAANQAECgQICwAAAA==.Hirys:BAABNQAECoEXAAIeAAgKIxLEFwAOAgAeAAgKIxLEFwAOAgAAAA==.',
Ho='Holybeks:BAAANQAECgEIAgABNQAECggIHwAMAHodAA==.Holydaddy:BAAANQAECgQIBAAAAA==.Holysmite:BAAANQAECgQIBAABNQAECgcICQAGAAAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECggIEQAGAAAAAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAK4fAA==.',
Hu='Huntfosho:BAAANQADCggICAAAAA==.Huntsmedown:BAAANQADCgYIBgAAAA==.',
['Há']='Háldrin:BAACNQAFFIEFAAIRAAMKXxhEEQD1AAARAAMKXxhEEQD1AAA1AAQKgSYAAxEACQr7IAIOAPACABEACQpkIAIOAPACAAIAAQo0Ju0hAV8AAAAA.',
['Hö']='Hölybeary:BAAANQAECgYIBgAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icybacon:BAAANQADCggICQAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQAECgQICQAAAA==.',
Im='Imbue:BAABNQAECoEXAAIQAAgKXh3FBQCjAgAQAAgKXh3FBQCjAgAAAA==.Imbuer:BAAANQAECgQIBAAAAA==.',
In='Innil:BAABNQAECoEXAAIEAAkKXSPDAgC1AwAEAAkKXSPDAgC1AwAAAA==.',
Je='Jessix:BAAANQAECgcICwAAAA==.Jezebel:BAAANQAECgcIEQAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAAANQAECgUJBgABNQAECgkJFgAIAIEUAA==.Jomas:BAABNQAECoEWAAIIAAkKgRQGSQATAgAIAAkKgRQGSQATAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECoEbAAIDAAYKbBp/nwCrAQADAAYKbBp/nwCrAQABNQAECggICAAGAAAAAA==.Juditis:BAAANQABCgUJBQAAAA==.',
Ka='Kagura:BAAANQABCgcICQAAAA==.Kaing:BAAANQAECgUICAAAAA==.Kaladen:BAAANQAECggIEAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECgYIDAAAAQ==.Kaoticnature:BAAANQADCgQIBwAAAA==.Karolg:BAAANQAECgYIDAAAAA==.Katostrafic:BAABNQAECoEbAAMFAAgK7xPwBwDXAQAFAAcKcBXwBwDXAQAEAAUKBQgamwAIAQAAAA==.Katrynna:BAAANQADCgUIDQAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAABNQAECoEoAAMQAAkK2SC1AgAvAwAQAAkK2SC1AgAvAwAWAAcKgA71LgCnAQAAAA==.',
Ki='Killidan:BAABNQAECoEfAAIWAAgKSh3/EwCxAgAWAAgKSh3/EwCxAgAAAA==.Kirklees:BAAANQAECgMIAwAAAA==.Kitsuchan:BAAANQAECgcIDQABNQAECggIGgAcALAkAA==.',
Ko='Kodama:BAABNQAECoEbAAIfAAcKAQlxhABoAQAfAAcKAQlxhABoAQAAAA==.Koi:BAAANQADCgcIEgABNQAECggIIQAQAKMeAA==.Kookiemon:BAAANQAECgMIAQAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECggIGwAFAO8TAA==.',
Ky='Kyanna:BAAANQAECgMIAwAAAA==.',
La='Lader:BAAANQAECggICAAAAA==.Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAAANQAECgUIEQAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQAECgMIAwAAAA==.Lenlaar:BAAANQAECgMIAwAAAA==.Levande:BAAANQAFFAEIAQAAAA==.',
Li='Lifeblume:BAAANQADCggIDQAAAA==.Lildevil:BAAANQABCggIBwAAAA==.Lilithandria:BAAANQAECgcIDAAAAA==.Linamar:BAAANQADCggILwAAAA==.',
Lo='Loaq:BAABNQAECoEoAAMEAAkK9RQbOgBdAgAEAAkK9RQbOgBdAgAFAAMK4gh+GQCFAAAAAA==.Longbottom:BAAANQAECgUJBQABNQAECggIEQAGAAAAAA==.Lorbert:BAAANQADCgQIAwABNQAECggIHgANAPQUAA==.Lostalot:BAABNQAECoEaAAICAAgK8BJHbAAOAgACAAgK8BJHbAAOAgAAAA==.',
Lu='Luxæterna:BAABNQAECoEnAAIDAAkK4hoxQgCpAgADAAkK4hoxQgCpAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECggIIQAgAOYgAA==.',
Ma='Malice:BAABNQAECoEVAAMdAAgK0xNaCADiAQAdAAgK0xNaCADiAQAYAAIKZAV4YwBRAAAAAA==.Mandwandos:BAAANQAECgcIDwAAAA==.Maraliss:BAAANQAECgIIBQAAAA==.',
Me='Melaunis:BAAANQADCgYIDwAAAA==.Meowzer:BAAANQAECgQICgABNQAECggIKwAbADoZAA==.Meteora:BAACNQAFFIEHAAIOAAMKMRK4AwDKAAAOAAMKMRK4AwDKAAA1AAQKgRoAAg4ACQoJGg4LAGECAA4ACQoJGg4LAGECAAAA.',
Mi='Mideel:BAAANQAECgMIAwAAAA==.Migolbearcow:BAABNQAECoEiAAITAAgKYhueCwBzAgATAAgKYhueCwBzAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwAGAAAAAA==.Missrae:BAAANQADCggIEgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Mooniè:BAAANQAECgIIBQAAAA==.Moosenuts:BAAANQAECgYICQAAAA==.Moriavus:BAABNQAECoEkAAIdAAgK9BuxAwCaAgAdAAgK9BuxAwCaAgAAAA==.Morocha:BAAANQAECgUIEgAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQAECgIIBQAAAA==.',
My='Mychropien:BAABNQAECoEWAAIJAAgKFCChHQC8AgAJAAgKFCChHQC8AgAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECoEoAAIYAAkKkCI3AQB+AwAYAAkKkCI3AQB+AwAAAA==.',
Na='Nadroj:BAAANQADCgUIEgAAAA==.Nancydru:BAAANQAECgEIAQAAAA==.Naosu:BAAANQADCgEJAQAAAA==.Nax:BAAANQAECgQIBwAAAA==.Nazzersaurus:BAABNQAECoEaAAIhAAcKYxlgIAD7AQAhAAcKYxlgIAD7AQAAAA==.',
Ne='Nec:BAAANQAECgEIAQAAAA==.Necrøtic:BAAANQAECgcIEwAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQADCggILwAAAA==.Nevermiss:BAABNQAECoEdAAIgAAcKkBiDFQD1AQAgAAcKkBiDFQD1AQAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Noggs:BAAANQADCggIEQAAAA==.Notmewasyou:BAAANQAECgUIEwAAAA==.',
Nu='Nuali:BAAANQAECgcIEgAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggJDQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECoEpAAIfAAkKtxsDJwDGAgAfAAkKtxsDJwDGAgAAAA==.',
Os='Oslatem:BAAANQADCgcICQAAAA==.',
Ox='Oxosorrel:BAAANQABCggIEAAAAA==.',
Oz='Ozzmodious:BAAANQADCgUIEAAAAA==.',
Pa='Paladan:BAABNQAECoEgAAISAAgKIiIpCAADAwASAAgKIiIpCAADAwAAAA==.Palagi:BAAANQAECgQICgAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAAANQAECgYIEAAAAA==.Pallymcbeall:BAAANQAECgEIAQAAAA==.Paprikaman:BAAANQAECgMIAwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Pariahrain:BAAANQAECgQICgABNQAECggIHAABAAYPAA==.Parishealton:BAABNQAECoEbAAMhAAkKfh/aBwAwAwAhAAkKfh/aBwAwAwAHAAMKxgE5lgBNAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Pe='Perprotrus:BAAANQADCgQIBAABNQAECggIIgAMADkcAA==.',
Po='Poulsbo:BAAANQADCgcIBgAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAAANQAECgUIDwAAAA==.Promisques:BAAANQAECgEIAQAAAA==.Prozak:BAABNQAECoEbAAIIAAgK0xIaXQDJAQAIAAgK0xIaXQDJAQAAAA==.',
Pw='Pwomf:BAAANQAECgYIBgAAAA==.',
Py='Pyrolily:BAAANQAECgQICQAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYIBgAAAA==.Raha:BAAANQAECgEIAQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECoEYAAMgAAgKLhJbFwDXAQAgAAgKLhJbFwDXAQAKAAcKKBPVKQCcAQAAAA==.Rastakan:BAAANQAECgUIBgABNQAECgkJKAANAM0iAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJCwAAAA==.Rellidana:BAAANQAECgIIAgAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgUIBQAAAA==.Retradormi:BAAANQADCggIFQAAAA==.Rexi:BAABNQAECoEhAAIbAAkK/w5OIgD7AQAbAAkK/w5OIgD7AQAAAA==.',
Ri='Rickcando:BAAANQAECgUIDAAAAA==.Ricshard:BAABNQAECoEVAAMYAAYKsRU3PgC/AAAZAAQKjxaMwQAaAQAYAAMK0hQ3PgC/AAAAAA==.Ridjeckgron:BAAANQADCgcICQAAAA==.',
Rm='Rmft:BAAANQADCgUIDwABNQAECgYIEwAGAAAAAA==.',
Ro='Roomnboard:BAAANQAECgEIAQAAAA==.Rotter:BAAANQADCgMIAwAAAA==.Roughluver:BAAANQADCgYIBgABNQAECggIKwAbADoZAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgIIAwAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQADCgcICQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQAECgEIAQAAAA==.',
['Rà']='Ràein:BAAANQAECgUIEQAAAA==.',
['Ró']='Ród:BAABNQAECoEjAAIDAAgKrh8YVQBtAgADAAgKrh8YVQBtAgAAAA==.',
['Rø']='Røth:BAAANQADCgYIDAAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAABNQAECoEWAAIDAAcKKgY03gAlAQADAAcKKgY03gAlAQAAAA==.Sakonna:BAABNQAECoEfAAIbAAkKCxXjGwBDAgAbAAkKCxXjGwBDAgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgcIEgAGAAAAAA==.Sandymaw:BAAANQADCgIIAgABNQAECggIKwAbADoZAA==.Sarlius:BAABNQAECoEoAAICAAkKqyXDAgDSAwACAAkKqyXDAgDSAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgcIDQAAAA==.Savin:BAAANQAECgIIAwAAAA==.',
Sc='Scavenger:BAAANQAECgUICgAAAA==.Scorchin:BAAANQAECggIAQAAAA==.Scrumptiøus:BAAANQADCggICgABNQAECggIGwAFAO8TAA==.',
Se='Selkamonk:BAABNQAECoEhAAIgAAgK5iCrCADoAgAgAAgK5iCrCADoAgAAAA==.Seniorbold:BAAANQAECgcIDwAAAA==.Sentrina:BAABNQAECoEpAAIiAAkKHB2LCwDcAgAiAAkKHB2LCwDcAgAAAA==.Seraph:BAAANQAECgEIAgAAAA==.Seshy:BAABNQAECoErAAMbAAgKOhlyGwBIAgAbAAgKOhlyGwBIAgAEAAEKwAhf3gA7AAAAAA==.Seshymutedme:BAAANQAECggIEAABNQAECggIKwAbADoZAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgUIBwAGAAAAAA==.Shannoon:BAAANQAECgUICAAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECoEmAAQKAAkK3iXBAADmAwAKAAkK3iXBAADmAwAgAAYK0hwrFwDaAQAjAAIKCSOHHwDDAAAAAA==.Shiverr:BAAANQAECgUIEgAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgcIEgAGAAAAAA==.',
Si='Siatraz:BAAANQADCggIDwABNQAECgIIBgAGAAAAAA==.Siegatrox:BAAANQADCgIIAQAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQABCgcIDwAAAA==.Skott:BAAANQADCggIKwAAAA==.',
Sl='Sleepadin:BAAANQAECgcIDQAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgcIDAAGAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAABNQAECoEcAAIIAAgKSBeWRAAkAgAIAAgKSBeWRAAkAgAAAA==.Solignis:BAACNQAFFIEVAAMPAAYK8yQRAACgAgAPAAYKwCQRAACgAgANAAQKgyAVDwCTAQA1AAQKgTUAAw8ACQr/JgQAACQEAA8ACQr/JgQAACQEAA0ACQp8JroEAMwDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECoEeAAINAAkKhR+TGgBBAwANAAkKhR+TGgBBAwAAAA==.Soohots:BAAANQAECgcIDAAAAA==.',
Sp='Sparklehappy:BAAANQAECgUIDgAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Stormcreek:BAAANQAECgQICQAAAA==.Storri:BAABNQAECoEqAAMEAAgKlRepRAA0AgAEAAgKlRepRAA0AgAbAAUKngbJSgDEAAAAAA==.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAECgkJKAAQANkgAA==.Suzuya:BAAANQADCgcJEQAAAA==.',
Sw='Swiftly:BAAANQAECgQIBQAAAA==.Swiftmage:BAACNQAFFIEVAAMkAAYK+iBOAAD8AQAkAAUK3iFOAAD8AQABAAUKdhsIEwC2AQA1AAQKgTcAAyQACQqjJhAAAP8DACQACQqjJhAAAP8DAAEACQoLJf8QAIoDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgcIDQAGAAAAAA==.Syndragonkin:BAABNQAECoEaAAICAAcKDhKsfwDeAQACAAcKDhKsfwDeAQAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFIEbAAIRAAcKMyGWAQCRAgARAAcKMyGWAQCRAgA1AAQKgScAAhEACQqwIwMGAGcDABEACQqwIwMGAGcDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCgcICwAAAA==.Taze:BAAANQAECgUJBwABNQAECggIIgAMADkcAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAAANQAECgYIEQAAAA==.Tetshajeh:BAABNQAECoEuAAMNAAkKAiCKIgAfAwANAAkKAiCKIgAfAwAOAAMKCxtVJgDdAAAAAA==.Teyliana:BAAANQAECgMIAwAAAA==.',
Th='Thillarick:BAAANQAECgYIEwAAAA==.Thromanor:BAAANQADCgEIAQAAAA==.Thwip:BAABNQAECoEjAAMCAAgKayGtKADWAgACAAgKRB+tKADWAgARAAcKtQy6NgBsAQAAAA==.',
Ti='Tikwid:BAAANQAECgYIEwAAAA==.Tiranmyashol:BAABNQAECoEeAAINAAgK9BRSdwAOAgANAAgK9BRSdwAOAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgQICAAAAA==.Tormmentor:BAAANQAECgIIAwAAAA==.',
Tr='Treebreak:BAAANQAECgQICwAAAA==.',
Ty='Tyrandrea:BAAANQADCgcICQAAAA==.',
Ud='Udari:BAAANQAECgYJBgAAAA==.Udarii:BAAANQAECgMIAwAAAA==.',
Um='Umàdbrah:BAABNQAECoEVAAICAAYKayPpTQBdAgACAAYKayPpTQBdAgAAAA==.',
Un='Unbelievable:BAAANQAECgUICAAAAA==.Unprovoked:BAABNQAECoEfAAIBAAgKiSDXZQCeAgABAAgKiSDXZQCeAgAAAA==.',
Va='Valamor:BAABNQAECoEVAAMSAAYK3A5+MwAdAQASAAYK3A5+MwAdAQAlAAUK4Ae7twDjAAAAAA==.Varia:BAAANQAECgEIAQABNQAECgcIEgAGAAAAAA==.',
Ve='Veefib:BAABNQAECoEeAAIfAAgKZxqdOwBfAgAfAAgKZxqdOwBfAgAAAA==.Velvettwitch:BAABNQAECoEdAAIYAAcK5hExFQC8AQAYAAcK5hExFQC8AQAAAA==.Vendler:BAAANQAECgYIDwAAAA==.Verahla:BAAANQADCgUIEQAAAA==.Vermis:BAABNQAECoEYAAIVAAYKKg2kTAA6AQAVAAYKKg2kTAA6AQAAAA==.Veryaverage:BAAANQAECgYICwAAAA==.Vexation:BAAANQAECgEIAQAAAA==.',
Vi='Vicarious:BAAANQAFFAEIAQAAAA==.Vidreaux:BAABNQAECoEhAAMBAAgKZQst5QCYAQABAAcKxgst5QCYAQAkAAEKvggZPgA4AAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQADCggICAAAAA==.',
Vo='Voidofvoids:BAAANQAECgIIAgAAAA==.Votingromney:BAAANQAECgIIAwABNQAECgkJJgAKAN4lAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECoEkAAICAAgKnBrwRwBuAgACAAgKnBrwRwBuAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECgcICQAAAA==.',
Wa='Waldorf:BAAANQAECgMIAwAAAA==.Wallegator:BAAANQADCgIIBAABNQAECgUIBQAGAAAAAA==.Walleroot:BAAANQAECgUIBQAAAA==.',
We='Weinersoup:BAAANQAECgMIAwAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgEIAQAAAA==.',
Wo='Wolfpup:BAAANQAECggICAAAAA==.Worstelf:BAABNQAECoEXAAMbAAcK8SEdHQA1AgAbAAYKgyEdHQA1AgAEAAEKehVH2gBHAAAAAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAABNQAECoEhAAIIAAgKAhaUPwA3AgAIAAgKAhaUPwA3AgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIIBgAEANciAA==.Yvonnél:BAAANQADCggIGgAAAA==.',
Za='Zanebusby:BAABNQAECoEfAAIYAAkKKxwpAwAJAwAYAAkKKxwpAwAJAwAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDQABNQAECgkJJgAKAN4lAA==.Zartash:BAAANQAECgUJCwAAAA==.Zatharis:BAAANQAECgIIBQAAAA==.',
Ze='Zelik:BAAANQAECgEIAQABNQAECgkJKAACAKslAA==.Zenezin:BAAANQABCgUIBQABNQAECgcIEgAGAAAAAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQAGAAAAAA==.',
Zm='Zmona:BAAANQAECgcIEgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgcIDQAGAAAAAA==.',
['Ðr']='Ðragonshaft:BAABNQAECoEiAAICAAgKaxHMZgAbAgACAAgKaxHMZgAbAgAAAA==.Ðreadlokz:BAAANQADCgQIBAAAAA==.',
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
