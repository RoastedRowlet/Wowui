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

local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Mage-Frost','Warrior-Arms','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Hunter-BeastMastery','Rogue-Subtlety','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Guardian','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Havoc','Mage-Fire','Hunter-Marksmanship','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aamion:BAAANQAECgUIEAAAAA==.',
Ab='Abo:BAAANQAECggICQAAAA==.',
Ae='Aeonfire:BAAANQAECgEIAQABNQAECggICgABAAAAAA==.',
Ak='Akame:BAAANQAFFAIIAgAAAA==.',
Al='Alykard:BAABNQAECoEcAAICAAgKXQdm3wCjAQACAAgKXQdm3wCjAQAAAA==.',
Am='Amateur:BAABNQAECoEhAAIDAAkK/hpnFAC1AgADAAkK/hpnFAC1AgAAAA==.Amazing:BAAANQAECgYIBgABNQAECgkJIQADAP4aAA==.',
An='Andronicas:BAAANQAECgYIBwAAAA==.Aneira:BAABNQAECoEqAAIEAAgKKxJdCgDxAQAEAAgKKxJdCgDxAQAAAA==.',
As='Asaki:BAAANQADCggICAAAAA==.Aspect:BAAANQAECgQIBAABNQAECggICgABAAAAAA==.',
Av='Avi:BAAANQADCgcJCQABNQAECgkJUgAFAMUbAA==.',
Ba='Baesuzy:BAAANQAECgUIDwAAAA==.Baragas:BAAANQAECgQICgAAAA==.',
Be='Belle:BAAANQADCgcICAAAAA==.Benkei:BAAANQAECgUICgAAAA==.',
Bg='Bgc:BAAANQABCgYICQAAAA==.',
Bl='Blackds:BAAANQABCgQIBAAAAA==.Blain:BAAANQAECgcICgAAAA==.',
Bo='Bosammana:BAAANQADCgMJAwAAAA==.',
Bu='Budin:BAAANQADCgIIAgAAAA==.',
Ca='Cannibal:BAAANQAECgcIDAAAAA==.Capri:BAABNQAECoEgAAIGAAYKcwp2XgAtAQAGAAYKcwp2XgAtAQAAAA==.Casiopia:BAAANQADCgQIBQAAAA==.',
Ch='Choomoo:BAABNQAECoEWAAIHAAcKrx6/FgBnAgAHAAcKrx6/FgBnAgABNQAECgkJLAAIAEoXAA==.Chopstix:BAAANQADCgYIDAAAAA==.Chromie:BAAANQAECggIAQAAAA==.',
Cr='Crikey:BAABNQAECoEnAAIJAAkKPhsPLgDBAgAJAAkKPhsPLgDBAgAAAA==.',
Cv='Cvdruid:BAAANQADCgUIBQAAAA==.',
Da='Daga:BAAANQAECgcICAAAAA==.',
De='Definitely:BAABNQAECoEvAAIEAAkK8CLdAQBLAwAEAAkK8CLdAQBLAwAAAA==.Desaix:BAABNQAECoEZAAIKAAcKeBWYGwDlAQAKAAcKeBWYGwDlAQAAAA==.Desariana:BAABNQAECoEdAAILAAkKIhLNbQAnAgALAAkKIhLNbQAnAgAAAA==.Devimon:BAAANQAECgQIBAAAAA==.Dewasixseven:BAAANQADCgQIBAAAAA==.',
Dh='Dhunt:BAAANQABCgMIAQAAAA==.',
Do='Dormas:BAAANQAECgUICgAAAA==.Doug:BAAANQADCgcIBwAAAA==.',
Dr='Drakeon:BAAANQADCgcJBwABNQAECgkJUgAFAMUbAA==.Drizzts:BAAANQADCgQIBQAAAA==.',
Dw='Dwarfpally:BAAANQAECgIIAwAAAA==.',
El='Eldh:BAAANQADCgEIAQAAAA==.Eldk:BAAANQAECgYICAAAAA==.Elisoly:BAABNQAECoEbAAIMAAcK5RKCaAC3AQAMAAcK5RKCaAC3AQAAAA==.',
Em='Emrald:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAAANQAFFAIIAgAAAA==.',
Er='Errimage:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Erritwo:BAAANQAECgQIBAAAAA==.',
Et='Etro:BAABNQAECoEjAAINAAgKcCI7CAABAwANAAgKcCI7CAABAwAAAA==.',
Ev='Evelinar:BAAANQADCggIDgAAAA==.Evoslex:BAABNQAECoEoAAIOAAkKaSIrAwBqAwAOAAkKaSIrAwBqAwAAAA==.',
Ex='Exo:BAECNQAFFIEPAAIPAAUKlhMUDgBBAQAPAAUKlhMUDgBBAQA1AAQKgT0AAg8ACQrvIk0KAFUDAA8ACQrvIk0KAFUDAAAA.',
Fa='Facerolleh:BAACNQAFFIEZAAIFAAcK7BqxCQDmAQAFAAcK7BqxCQDmAQA1AAQKgTEAAgUACQrbI8oQAHQDAAUACQrbI8oQAHQDAAAA.Fatedx:BAAANQAECgcIDwAAAA==.',
Fe='Feelgoodinc:BAAANQAECgMIAwAAAA==.',
Fi='Fistdaddy:BAAANQAECgUIBQAAAA==.Fiz:BAABNQAECoEtAAIFAAkKgRv7NgDRAgAFAAkKgRv7NgDRAgAAAA==.',
Fu='Fuknazum:BAAANQAECgIIAgAAAA==.',
Ga='Galara:BAAANQAECgEIAQAAAA==.',
Gr='Grandpriest:BAAANQAECgYIBwABNQAECgcIDQABAAAAAA==.Grimoirsingh:BAAANQAECgEIAQAAAA==.Grimveil:BAABNQAECoErAAIQAAgKGSKnGQDYAgAQAAgKGSKnGQDYAgAAAA==.',
['Gô']='Gôku:BAAANQADCgYIBgAAAA==.',
Ha='Harafar:BAACNQAFFIEGAAIGAAMKzwddFwDCAAAGAAMKzwddFwDCAAA1AAQKgSkAAgYACQoYGFEkAI4CAAYACQoYGFEkAI4CAAAA.',
He='Hellbourne:BAAANQAECgUICgAAAA==.',
Hi='Hibiki:BAAANQADCgIIAgAAAA==.',
Ho='Hogreveal:BAAANQADCgEIAQAAAA==.Hollykibbler:BAAANQADCgUIBgAAAA==.Holyclstrfuk:BAAANQADCgYIBgAAAA==.Horsé:BAAANQADCggIEgAAAA==.',
Hu='Huntslex:BAAANQAECgQIBgABNQAECgkJKAAOAGkiAA==.',
Il='Illidam:BAAANQAECgYICAAAAA==.',
It='Itskiohte:BAAANQAECgYJEAAAAA==.',
Ja='Jaedaa:BAAANQAECgcJBwABNQAFFAUIEQAPADwZAA==.Jaedamend:BAAANQAECggIDQABNQAFFAUIEQAPADwZAA==.',
Je='Jertbirt:BAAANQAECgEIAQAAAA==.',
Ka='Kalzaketh:BAABNQAECoEiAAIRAAcKZghRDgA0AQARAAcKZghRDgA0AQAAAA==.Katali:BAAANQAECgEIAQAAAA==.Kaypop:BAAANQADCgQIBwABNQAFFAUIEAAJAKgZAA==.Kazo:BAABNQAECoEkAAQSAAkKYyAjHQDkAgASAAkKYyAjHQDkAgATAAEKaCN9HABmAAAUAAEKUBPPZwA+AAAAAA==.Kazuggar:BAACNQAFFIEXAAIVAAUKIxk6CACuAQAVAAUKIxk6CACuAQA1AAQKgT0AAxUACQqgI2oNAEEDABUACQqgI2oNAEEDABYAAgqVFC7vAHMAAAAA.Kazzn:BAAANQAECgQICAAAAA==.',
Ke='Kell:BAAANQAECgYICAAAAA==.',
Ki='Kibbler:BAAANQAECgEIAQAAAA==.Killerman:BAAANQAECgUIBQAAAA==.',
Ku='Kucabara:BAAANQAECgQIBQABNQAECgQICgABAAAAAA==.Kungpew:BAAANQAECgIIAgAAAA==.',
Kw='Kwichang:BAAANQAECgQIBAAAAA==.',
Ky='Kyndariae:BAAANQAECgYIEQAAAA==.',
La='Lagman:BAAANQADCgEIAQAAAA==.',
Li='Lickynose:BAABNQAECoEjAAICAAgKdx8ZVwDBAgACAAgKdx8ZVwDBAgAAAA==.',
Ma='Mahou:BAAANQAECgQIBQAAAA==.Malcador:BAAANQAECgUIBQAAAA==.Mantisar:BAAANQAECgYIEgAAAA==.Marmite:BAAANQAECgYIBgAAAA==.',
Mi='Mightyhunt:BAAANQAECgcIDgAAAA==.Mirrorimage:BAAANQAECgYIDgABNQAFFAMIBgAUALkXAA==.Mirrorx:BAACNQAFFIEGAAIUAAMKuRf/CgABAQAUAAMKuRf/CgABAQA1AAQKgScAAxQACQp4HVEQANgCABQACQp4HVEQANgCABIACAq7Df1oAK4BAAAA.',
Mo='Moosfel:BAAANQAECgQJBgAAAA==.',
Mt='Mtzz:BAAANQAECgUIDwAAAA==.',
Mu='Mudkrab:BAAANQAECgEIAQAAAA==.',
My='Mylie:BAAANQADCgIIAgAAAA==.Mystdragon:BAACNQAFFIEJAAIXAAQKAxOWCwA1AQAXAAQKAxOWCwA1AQA1AAQKgRkAAxcACQpnHyULAOICABcACQpnHyULAOICABEABArFGGsOADIBAAE1AAUUBggqAAgA8SQA.Mystweaverr:BAACNQAFFIEqAAIIAAYK8SR7AACVAgAIAAYK8SR7AACVAgA1AAQKgTQAAggACQpvJgcBAL4DAAgACQpvJgcBAL4DAAAA.',
Na='Naddar:BAABNQAECoEhAAIMAAgKwRSQRgAtAgAMAAgKwRSQRgAtAgAAAA==.Narp:BAAANQADCgQIBAAAAA==.',
Ng='Nganga:BAABNQAECoEdAAMVAAgKgx8CNwBcAgAVAAcKCyECNwBcAgAWAAcK1BuQRQA0AgAAAA==.',
Ni='Nikonii:BAABNQAECoEZAAIKAAcKGhrkFAAtAgAKAAcKGhrkFAAtAgAAAA==.',
Pa='Paktam:BAAANQAECgUICwAAAA==.Palakudaliaq:BAAANQADCggICAAAAA==.Palaynslea:BAABNQAECoEjAAIMAAgKdw7SYADRAQAMAAgKdw7SYADRAQAAAA==.Parse:BAABNQAECoE4AAMDAAgK1x6DFQCrAgADAAgKzh2DFQCrAgAKAAUKhx7XIQCoAQAAAA==.',
Pe='Perceptor:BAAANQAECgIIAgABNQAECgkJIQAYAD4eAA==.',
Pr='Prothero:BAACNQAFFIEHAAICAAMKQgoRMwDFAAACAAMKQgoRMwDFAAA1AAQKgR8AAgIACQqcI8MiAEgDAAIACQqcI8MiAEgDAAAA.Proyo:BAAANQAECgUIDgAAAA==.',
['På']='Påthor:BAABNQAECoEbAAIGAAcKeRfOOwDrAQAGAAcKeRfOOwDrAQAAAA==.',
Ql='Ql:BAAANQADCgYIBgAAAA==.',
Ra='Raijinn:BAABNQAECoEbAAMVAAgK2iEzJQCxAgAVAAcKniIzJQCxAgAWAAYK+hqvXwDTAQAAAA==.Raizex:BAAANQADCggJDwAAAA==.Ratbarstard:BAABNQAECoE+AAICAAkKEhiiaACYAgACAAkKEhiiaACYAgAAAA==.Rawtoor:BAABNQAECoEiAAIZAAgKAB4rEQDTAgAZAAgKAB4rEQDTAgAAAA==.',
Ri='Ridgelock:BAAANQAECgIIAgAAAA==.Ridgerock:BAABNQAECoEXAAMPAAgK/x85GgDFAgAPAAgK/x85GgDFAgAQAAEKPgN73AAlAAAAAA==.Riggse:BAAANQAECggIEAABNQAFFAcIHQAFALklAA==.Riggspal:BAAANQAECggICQABNQAFFAcIHQAFALklAA==.',
Ro='Roadkill:BAABNQAECoEgAAIPAAgKZSHsFwDXAgAPAAgKZSHsFwDXAgAAAA==.Rolltoor:BAACNQAFFIEIAAIaAAUKnw6pBgBiAQAaAAUKnw6pBgBiAQA1AAQKgSkAAhoACQotIbYJACEDABoACQotIbYJACEDAAAA.',
Ru='Ruínation:BAAANQAECgQIBAABNQAECggIHQAVAIMfAA==.',
Sa='Saiko:BAABNQAECoEaAAMbAAkKIRKYMQDsAQAbAAkKphCYMQDsAQAZAAQKMhDNSADYAAAAAA==.Sansa:BAAANQAECgcIDgAAAA==.Saso:BAACNQAFFIEQAAMEAAUKlxnBBQCgAAACAAQKyRlGHQBdAQAEAAIKjxLBBQCgAAA1AAQKgTAAAwIACQrEJJATAH8DAAIACQrEJJATAH8DAAQAAgqNIo0iALYAAAAA.Sastroll:BAAANQAECgMIAwABNQAFFAUIEAAEAJcZAA==.',
Sc='Scroll:BAAANQAECgYIBgAAAA==.',
Se='Serbitar:BAAANQADCggJGAAAAA==.',
Sh='Shadow:BAABNQAECoEWAAIZAAgKwRbOIwAKAgAZAAgKwRbOIwAKAgAAAA==.Shandrilah:BAAANQAECgUIEwAAAA==.Shialebuff:BAAANQAECgcICAAAAA==.',
Si='Silphy:BAAANQADCggIGwABNQAECggIKQAQAEgaAA==.Sindar:BAAANQAECgIIAgAAAA==.Siphon:BAAANQADCgcIEAAAAA==.Siscomp:BAABNQAECoFSAAIFAAkKxRtGPAC/AgAFAAkKxRtGPAC/AgAAAA==.Sixth:BAAANQADCggIEAAAAA==.',
Sk='Skoog:BAABNQAECoEZAAIFAAgKQBQadgASAgAFAAgKQBQadgASAgAAAA==.Sky:BAACNQAFFIEJAAMSAAQKlxJrHwCpAAASAAQKjRBrHwCpAAATAAEKsBthAwBJAAA1AAQKgSwABBIACQrgI54KAFsDABIACApjJZ4KAFsDABMABAruHUUOADUBABQAAQqhG79lAEQAAAAA.',
Sn='Snarkshot:BAAANQADCgEIAQAAAA==.Snugglepuff:BAABNQAECoEdAAIFAAgKvREQfwD6AQAFAAgKvREQfwD6AQAAAA==.',
So='Sock:BAAANQAECggIAgAAAA==.Sonarius:BAABNQAECoEsAAQCAAkK8yOvEgCDAwACAAkK8yOvEgCDAwAcAAEK/R/aCABfAAAEAAEKoh4vNwBIAAAAAA==.',
Sp='Sparkster:BAABNQAECoEaAAIFAAgK/huqTgCDAgAFAAgK/huqTgCDAgAAAA==.',
Su='Sundae:BAAANQAECgYIEAAAAA==.',
Sy='Sylvie:BAABNQAECoEaAAIJAAkKsxNtTABhAgAJAAkKsxNtTABhAgAAAA==.Syreith:BAAANQADCgYIBgAAAA==.',
['Så']='Sådistic:BAAANQAECgQIBQAAAA==.',
['Sý']='Sýlvanas:BAAANQABCgYIBgAAAA==.',
Ti='Tidders:BAABNQAECoEjAAIdAAgK/hxDGQB0AgAdAAgK/hxDGQB0AgAAAA==.Tikiwoki:BAAANQAECgcIDwAAAA==.Tiramisu:BAAANQAECggIDAAAAA==.',
Tr='Trilldi:BAAANQADCggJEAAAAA==.Tritone:BAAANQAECgEIAQAAAA==.',
Ty='Tyladrhas:BAAANQAECgcIDwAAAA==.Tyrismaximus:BAAANQAECgMIBAAAAA==.',
Up='Up:BAABNQAECoEjAAIOAAgKdx70CQC4AgAOAAgKdx70CQC4AgAAAA==.',
Va='Vaelus:BAAANQABCgIIAgAAAA==.Varina:BAAANQAECgIJAgAAAA==.',
Ve='Velorah:BAAANQAECgQIBAAAAA==.Velsaert:BAAANQADCgUJBAAAAA==.',
Vo='Volatilegas:BAAANQAECgYIDQAAAA==.',
Vu='Vulken:BAABNQAECoFOAAIJAAkKBRqCOACeAgAJAAkKBRqCOACeAgAAAA==.',
Wi='Winnìng:BAAANQAECgQICAAAAA==.',
Ya='Yamazaki:BAAANQAECgYIBgAAAA==.',
Ye='Yessuh:BAAANQAECgEIAgAAAA==.',
Zi='Zihon:BAAANQAECgUIBQAAAA==.',
Zo='Zombi:BAAANQAECgEIAQAAAA==.Zombiepanda:BAAANQADCgYIFgAAAA==.Zoomer:BAABNQAECoEnAAIeAAgKtwjxEgBMAQAeAAgKtwjxEgBMAQABNQAFFAMIBgAUALkXAA==.',
Zu='Zubb:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Zugg:BAAANQAECgQIBAABNQAECgYIEgABAAAAAA==.Zupp:BAAANQAECgYIEgAAAA==.Zuqq:BAAANQAECgYIBwABNQAECgYIEgABAAAAAA==.',
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
