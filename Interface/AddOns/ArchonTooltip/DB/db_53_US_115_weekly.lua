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

local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Mage-Frost','Warrior-Arms','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Evoker-Preservation','Druid-Guardian','DemonHunter-Devourer','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aamion:BAAANQAECgQICgAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgABAAAAAA==.',
Al='Alykard:BAABNQAECoEcAAICAAgKXQdXxgCoAQACAAgKXQdXxgCoAQAAAA==.',
Am='Amateur:BAABNQAECoEfAAIDAAgKghwTFACTAgADAAgKghwTFACTAgAAAA==.',
An='Andronicas:BAAANQAECgEIAQAAAA==.Aneira:BAABNQAECoEfAAIEAAgK1Q8iCQDyAQAEAAgK1Q8iCQDyAQAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.',
Av='Avi:BAAANQADCgcJCQABNQAECggIQAAFAJwaAA==.',
Ba='Baesuzy:BAAANQAECgQICgAAAA==.Baragas:BAAANQAECgQIBgAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAAANQAECgUICQAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAAANQAECgYICQAAAA==.',
Bo='Bosammana:BAAANQADCgMJAwAAAA==.',
Bu='Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAAANQAECgQICgAAAA==.Capri:BAABNQAECoEZAAIGAAYKyQb8XQAEAQAGAAYKyQb8XQAEAQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAAANQAECgYIDgABNQAECgkJIwAHAJUQAA==.Chopstix:BAAANQADCgYIDAAAAA==.',
Cr='Crikey:BAABNQAECoEeAAIIAAgKEhsjPgBpAgAIAAgKEhsjPgBpAgAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
De='Definitely:BAABNQAECoElAAIEAAgKByPaAgD1AgAEAAgKByPaAgD1AgAAAA==.Desaix:BAABNQAECoEZAAIJAAcKeBXbGADwAQAJAAcKeBXbGADwAQAAAA==.Desariana:BAABNQAECoEbAAIKAAgKORMmZAAVAgAKAAgKORMmZAAVAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Do='Dormas:BAAANQAECgQIBQAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECggIQAAFAJwaAA==.Drizzts:BAAANQADCgQIBQAAAA==.',
Dw='Dwarfpally:BAAANQAECgIIAgAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECgIIAgAAAA==.Elisoly:BAABNQAECoEZAAILAAYKNxWyaACNAQALAAYKNxWyaACNAQAAAA==.',
Em='Emrald:BAAANQAECgEIAQAAAA==.',
En='Endlessly:BAAANQAECggIDQAAAA==.',
Er='Errimage:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECoEcAAIMAAgKnyG1BwD1AgAMAAgKnyG1BwD1AgAAAA==.',
Ev='Evelinar:BAAANQADCgcICAAAAA==.Evoslex:BAABNQAECoEfAAINAAkKzR/0AwBEAwANAAkKzR/0AwBEAwAAAA==.',
Ex='Exo:BAECNQAFFIELAAIOAAUK7RChCwA6AQAOAAUK7RChCwA6AQA1AAQKgS0AAg4ACQqDIocMACwDAA4ACQqDIocMACwDAAAA.',
Fa='Facerolleh:BAACNQAFFIEdAAIFAAYKTBhBBQAZAgAFAAYKTBhBBQAZAgA1AAQKgTMAAgUACQqzIwQOAHcDAAUACQqzIwQOAHcDAAAA.Fatedx:BAAANQAECgYICwAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAABNQAECoEqAAIFAAkKoRp9LwDRAgAFAAkKoRp9LwDRAgAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQADCgEJAQAAAA==.',
Gr='Grandpriest:BAAANQADCgMIAwABNQAECgcIDAABAAAAAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECoEpAAIPAAgK0yGFEQD5AgAPAAgK0yGFEQD5AgAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAABNQAECoEmAAIGAAkKFBhWHgCmAgAGAAkKFBhWHgCmAgAAAA==.',
He='Hellbourne:BAAANQAECgQJBQAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQADCgEIAQAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgQIBAABNQAECgkJHwANAM0fAA==.',
Il='Illidam:BAAANQAECgYICAAAAA==.',
It='Itskiohte:BAAANQAECgYJEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIDAAOADkZAA==.Jaedamend:BAAANQAECgYIBgABNQAFFAUIDAAOADkZAA==.',
Ka='Kalzaketh:BAABNQAECoEUAAIQAAUKyAWWEgCxAAAQAAUKyAWWEgCxAAAAAA==.Katali:BAAANQADCgIIAwAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAUIDAAIACwXAA==.Kazo:BAABNQAECoEgAAMRAAkKYyCaFQD3AgARAAkKYyCaFQD3AgASAAEKaCNRGQBnAAAAAA==.Kazuggar:BAACNQAFFIEQAAITAAUKAxMDBwCcAQATAAUKAxMDBwCcAQA1AAQKgTkAAxMACQqgIwQKAFEDABMACQqgIwQKAFEDABQAAgqVFC7VAHgAAAAA.Kazzn:BAAANQAECgIIBQAAAA==.',
Ke='Kell:BAAANQAECgYICAAAAA==.',
Ki='Kibbler:BAAANQAECgEJAQAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Ku='Kucabara:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAAANQAECgQIBAAAAA==.',
Ky='Kyndariae:BAAANQAECgUIDAAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECoEcAAICAAgKWx5pTADDAgACAAgKWx5pTADDAgAAAA==.',
Ma='Mahou:BAAANQAECgQIBQAAAA==.Malcador:BAAANQAECgUIBAAAAA==.Mantisar:BAAANQAECgQIDQAAAA==.Marmite:BAAANQADCgYIBgAAAA==.',
Mi='Mightyhunt:BAAANQAECgYJDQAAAA==.Mirrorimage:BAAANQAECgYICAABNQAECgkJJAAVAEccAA==.Mirrorx:BAABNQAECoEkAAMVAAkKRxxRDwDMAgAVAAkKRxxRDwDMAgARAAgKuw2UWAC6AQAAAA==.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgUICwAAAA==.',
Mu='Mudkrab:BAAANQAECgEIAQAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFIEFAAIWAAMKDxVHCwD/AAAWAAMKDxVHCwD/AAA1AAQKgRYAAxYACQpnH1wJAO4CABYACQpnH1wJAO4CABAAAwrqEv8RALoAAAE1AAUUBgglAAcAUSQA.Mystweaverr:BAACNQAFFIElAAIHAAYKUSRQAACCAgAHAAYKUSRQAACCAgA1AAQKgTAAAgcACQpvJqcAAM0DAAcACQpvJqcAAM0DAAAA.',
Na='Naddar:BAABNQAECoEdAAILAAYKRBZNYQCmAQALAAYKRBZNYQCmAQAAAA==.',
Ng='Nganga:BAABNQAECoEaAAMTAAgKgx/qLQBpAgATAAcKCyHqLQBpAgAUAAcKlRpoPAA7AgAAAA==.',
Ni='Nikonii:BAABNQAECoEYAAIJAAcKHhn1EgA1AgAJAAcKHhn1EgA1AgAAAA==.',
Pa='Paktam:BAAANQAECgQIBwAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECoEgAAILAAgKzAyxVgDNAQALAAgKzAyxVgDNAQAAAA==.Parse:BAABNQAECoExAAMDAAgKKhz2EwCTAgADAAgKWxv2EwCTAgAJAAUK6R1/IACiAQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgkJGwAXACseAA==.',
Pr='Prothero:BAABNQAECoEcAAICAAkKnCMvGgBaAwACAAkKnCMvGgBaAwAAAA==.Proyo:BAAANQAECgUIDQAAAA==.',
['På']='Påthor:BAABNQAECoEZAAIGAAYKZxjXPgCxAQAGAAYKZxjXPgCxAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAAANQAECgYIEwAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAABNQAECoE1AAICAAkKixdZXQCYAgACAAkKixdZXQCYAgAAAA==.Rawtoor:BAABNQAECoEaAAIYAAcKvBmXHgAiAgAYAAcKvBmXHgAiAgAAAA==.',
Ri='Ridgerock:BAAANQAECgcIEwAAAA==.Riggse:BAAANQAECgcIDQABNQAFFAcIFwAFAAYiAA==.Riggspal:BAAANQAECggICQABNQAFFAcIFwAFAAYiAA==.',
Ro='Roadkill:BAABNQAECoEeAAIOAAgKRiFpEwDmAgAOAAgKRiFpEwDmAgAAAA==.Rolltoor:BAABNQAECoEmAAIZAAkKLSFiBwA2AwAZAAkKLSFiBwA2AwAAAA==.',
Sa='Saiko:BAAANQAECggIEwAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFIELAAMEAAUKpRYyBAClAAACAAMKXBrFHwAIAQAEAAIKEhEyBAClAAA1AAQKgSwAAwIACQolI+4YAGADAAIACQolI+4YAGADAAQAAgpHIIggAKkAAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAUICwAEAKUWAA==.',
Se='Serbitar:BAAANQADCggJGAAAAA==.',
Sh='Shadow:BAABNQAECoEWAAIYAAgKwRZ/HwAXAgAYAAgKwRZ/HwAXAgAAAA==.Shandrilah:BAAANQAECgUIEwAAAA==.Shialebuff:BAAANQAECgQJBgAAAA==.',
Si='Silphy:BAAANQADCggIFwABNQAECggIHQAPAK0YAA==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECoFAAAIFAAgKnBpXTgBfAgAFAAgKnBpXTgBfAgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECoEYAAIFAAgKQBTUegDWAQAFAAgKQBTUegDWAQAAAA==.Sky:BAACNQAFFIEIAAMRAAQKdBLWGQCrAAARAAQKahDWGQCrAAASAAEKsBukAgBTAAA1AAQKgSsABBEACQrgI/sHAGQDABEACApjJfsHAGQDABIABAruHaYMADgBABUAAQqhG0FZAEgAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECoEZAAIFAAgK3hA9bwD4AQAFAAgK3hA9bwD4AQAAAA==.',
So='Sock:BAAANQAECggIAgAAAA==.Sonarius:BAABNQAECoEpAAMCAAkKoyNCDgCOAwACAAkKoyNCDgCOAwAEAAEKoh5uLwBNAAAAAA==.',
Sp='Sparkster:BAAANQAECgYJEQAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAABNQAECoEWAAIIAAgKeBJfVwAbAgAIAAgKeBJfVwAbAgAAAA==.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECoEcAAIaAAgK/hziFACLAgAaAAgK/hziFACLAgAAAA==.Tikiwoki:BAAANQAECgcIDAAAAA==.Tiramisu:BAAANQAECgcICQAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAAANQAECgYICwAAAA==.Tyrismaximus:BAAANQAECgMJBAAAAA==.',
Up='Up:BAABNQAECoEcAAINAAgKuRpuDQBUAgANAAgKuRpuDQBUAgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQADCggICAAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECoE8AAIIAAgK4BrIOwBxAgAIAAgK4BrIOwBxAgAAAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgQIBAAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQADCgYIEAAAAA==.Zoomer:BAABNQAECoEnAAIbAAgKtwhnDwBcAQAbAAgKtwhnDwBcAQABNQAECgkJJAAVAEccAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Zugg:BAAANQADCggIEQABNQAECgUIDAABAAAAAA==.Zupp:BAAANQAECgUIDAAAAA==.Zuqq:BAAANQADCggIGAABNQAECgUIDAABAAAAAA==.',
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
