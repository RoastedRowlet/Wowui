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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Unknown-Unknown','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Blood','Priest-Holy','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Druid-Balance','DeathKnight-Unholy','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Priest-Shadow','Druid-Restoration','Warrior-Protection','Hunter-Survival','Priest-Discipline',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aamix:BAABNQAECoEkAAMBAAkKmRWiNQBIAgABAAgKrhSiNQBIAgACAAYK6A0sHQBkAQAAAA==.Aarom:BAACNQAFFIEOAAIDAAYK9BqfAQATAgADAAYK9BqfAQATAgA1AAQKgR0AAgMACQqfIw4GADoDAAMACQqfIw4GADoDAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQAECgQJBwAAAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aequitas:BAAANQADCgUJBQAAAA==.Aerius:BAAANQAECgIJAgAAAA==.',
Af='Affliclock:BAACNQAFFIEGAAIEAAQKexVSAABuAQAEAAQKexVSAABuAQA1AAQKgRkAAgQACQpTHk0BAAcDAAQACQpTHk0BAAcDAAAA.',
Ai='Aingerfal:BAAANQADCggIEgAAAA==.',
Ak='Akasori:BAABNQAECoEiAAIFAAkKSRvCAwDwAgAFAAkKSRvCAwDwAgAAAA==.Akosori:BAAANQADCgYIDAABNQAECgkJIgAFAEkbAA==.',
Al='Alterboyy:BAAANQAECgMIAwAAAA==.Alîsonshammy:BAACNQAFFIEGAAIGAAIK6yPRCwDVAAAGAAIK6yPRCwDVAAA1AAQKgRwAAwYACQqEIj4GAG0DAAYACQqEIj4GAG0DAAcACAo8FzIyAD0CAAAA.',
Am='Ambersulfr:BAAANQAECgMJBwAAAA==.Amrazz:BAAANQAECggIEAAAAA==.Amzey:BAEBNQAECoEeAAIIAAkK5x2kJAAmAwAIAAkK5x2kJAAmAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcJCwAJAAAAAA==.Andromeda:BAAANQAECgcIEwAAAA==.Anneaux:BAAANQAECgIJAgAAAA==.Antimortem:BAAANQADCgUJDAAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgUJCgAAAA==.Astralus:BAAANQAECgMJBwAAAA==.Astramis:BAAANQAECgMJAwAAAA==.',
At='Atomicbarbie:BAAANQAECgQJCAABNQAFFAIIBgAGAOsjAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECoEYAAIHAAgKhRQvNAAyAgAHAAgKhRQvNAAyAgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgQJBwABNQABCgIIAwAJAAAAAA==.',
Ba='Backlash:BAAANQAECgUICQAAAA==.Balzhac:BAAANQAECgYIBgAAAA==.Bam:BAAANQADCggICAABNQAFFAQIBwAKAPYUAA==.Bamplify:BAAANQAFFAIIAgABNQAFFAQIBwAKAPYUAA==.Barrierbobo:BAAANQAECgMJBAAAAA==.Barthold:BAAANQADCgcIFAAAAA==.',
Be='Bellmonte:BAAANQADCgYIDwABNQAECgQIEAAJAAAAAA==.Belmonk:BAAANQAECgEIAQAAAA==.Berdron:BAABNQAECoEcAAICAAgKbQ9QDgD2AQACAAgKbQ9QDgD2AQAAAA==.',
Bl='Bladeliger:BAAANQAECgcIEwAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECoEfAAILAAkKyyT0BwCbAwALAAkKyyT0BwCbAwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAAANQAECgUJCAAAAA==.Bonemair:BAACNQAFFIEMAAIMAAUK2w1rCAAvAQAMAAUK2w1rCAAvAQA1AAQKgSYAAgwACQqhIPoKACkDAAwACQqhIPoKACkDAAAA.Boredasf:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIDAAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQADCgMJAwAJAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIJAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAIIBgANAGEjAA==.Bullteesta:BAAANQADCggJDAAAAA==.Burkhard:BAAANQABCgYIBgAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBQAAAA==.',
Ca='Caldec:BAACNQAFFIELAAIOAAUKbB4lAQDYAQAOAAUKbB4lAQDYAQA1AAQKgScAAg4ACQqpJVkCAKoDAA4ACQqpJVkCAKoDAAAA.',
Ch='Chainizard:BAAANQAECgcIDAAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECgcIDAAJAAAAAA==.Chaosofelune:BAAANQAECgEIAQAAAA==.Chaosoflife:BAAANQAECgIJAgAAAA==.Cheeno:BAABNQAECoEYAAMPAAcK7iMXDQDjAgAPAAcK7iMXDQDjAgAQAAEKPSKJGQBhAAAAAA==.Chihiro:BAAANQADCggJHgAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Cl='Clarabelle:BAAANQAECggIEQAAAA==.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwAAAA==.Computer:BAABNQAECoEjAAMCAAkK/yAhAwDzAgACAAgK/yIhAwDzAgABAAgKvB09IACpAgAAAA==.Cootin:BAAANQAECggIBgAAAA==.',
Cp='Cpteddie:BAABNQAECoEeAAMRAAkKKx30BQAFAwARAAkKKx30BQAFAwASAAMKahHR1wCxAAABNQAFFAYIEgAMAFoaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQAJAAAAAA==.Crelam:BAACNQAFFIEMAAITAAUKQAcHAQCUAQATAAUKQAcHAQCUAQA1AAQKgSYAAhMACQr5FRcIAKsCABMACQr5FRcIAKsCAAAA.Critherine:BAAANQAECgEIAQAAAA==.Cronatherus:BAAANQADCgUICgAAAA==.Cruentis:BAAANQAECgYJDgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDwAJAAAAAA==.Crysus:BAAANQAECgcIDwAAAA==.',
Da='Dabo:BAABNQAECoEWAAIUAAgKuB0sGgClAgAUAAgKuB0sGgClAgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJHwALAMskAA==.Darwin:BAAANQAECgMJBAAAAA==.Dasmoodhayn:BAAANQAECgIJAgAAAA==.Davalanch:BAABNQAECoEfAAIHAAkKWxkgIACvAgAHAAkKWxkgIACvAgAAAA==.Dazizejr:BAABNQAECoEgAAIMAAgKayVCCABOAwAMAAgKayVCCABOAwAAAA==.',
De='Deathisbrew:BAAANQAECggICAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Denïed:BAAANQADCgQIBAAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCgYICQAAAA==.',
Di='Dibstrum:BAAANQAECgQIBgAAAA==.Digduug:BAAANQAECgQJBwAAAA==.Dixqt:BAAANQAECgQICAAAAA==.',
Do='Dogfight:BAACNQAFFIELAAQVAAUKXwsaBABEAQAVAAQKhgoaBABEAQAOAAEKYQACEgAvAAAMAAEKxA5lHwArAAA1AAQKgSMABBUACQoZHaMTANQCABUACQqHG6MTANQCAA4AAgpHC5hfAGEAAAwAAQqND7CZAC8AAAAA.Doilookfatou:BAAANQAECgcJEQAAAA==.',
Dr='Draxus:BAAANQAECgQJBgAAAA==.Dresel:BAAANQAECggIEQAAAA==.Drewpeebahlz:BAAANQAECgQIBAABNQABCgIIAgAJAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQADCggIDgAAAA==.Durto:BAAANQADCgYIBgAAAA==.',
Dy='Dyami:BAAANQAECgUIDQAAAA==.Dynas:BAAANQAECgQJBAAAAA==.',
Ea='Earthcake:BAABNQAECoEeAAMHAAgK1yFsEwATAwAHAAgK1yFsEwATAwAGAAMKIwdaswB+AAAAAA==.',
Ed='Eddielich:BAACNQAFFIESAAIMAAYKWhrLAQAmAgAMAAYKWhrLAQAmAgA1AAQKgSIAAgwACQrEJBMEAJQDAAwACQrEJBMEAJQDAAAA.',
Eh='Ehlo:BAAANQADCgEIAQAAAA==.',
El='Elasmon:BAAANQAECgYIDAAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQADCgMIAwAAAA==.',
Er='Erragal:BAAANQADCgMIAwAAAA==.',
Es='Escanõr:BAAANQAECgYIBwAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.Faustyne:BAAANQAECgQJBAABNQAECgkJLAAWAA8kAA==.',
Fe='Felurián:BAAANQAECgEIAQABNQADCgUIDAAJAAAAAA==.Fexli:BAAANQADCgMIAwAAAA==.',
Fi='Fireteeth:BAAANQADCggJEwAAAA==.',
Fl='Flurtty:BAAANQADCgQICQAAAA==.',
Fo='Folklore:BAAANQAECgEJAQAAAA==.Forklift:BAAANQAECgIIAgABNQAECgcJEQAJAAAAAA==.',
Fr='Frigomortis:BAAANQAECgIIAgABNQAECgIJAgAJAAAAAA==.Frozown:BAAANQAECgYIDwAAAA==.Fruits:BAAANQAECgMJBQAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgIJAgAAAA==.Furrylife:BAAANQADCggIEwAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQAJAAAAAA==.Fuzzychin:BAAANQAECgIIBgAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAAANQAECgYJEAABNQAFFAUJDAATAEAHAA==.Gardettos:BAAANQAECgcJEQAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgIJBAAAAA==.Ghostthunter:BAAANQADCgQJBAABNQAECgYICQAJAAAAAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAAANQAECgYIDwABNQAFFAUIDAAMANsNAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAAANQADCgIIAgAAAA==.Gnxrr:BAEBNQAECoEaAAIDAAkKGiPxAgCPAwADAAkKGiPxAgCPAwAAAA==.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgUJCgAAAA==.',
Gr='Gregorz:BAAANQADCgMIAwAAAA==.Greyanna:BAAANQAECgEIAQAAAA==.Gridon:BAAANQABCgUIBQAAAA==.Gromthrall:BAAANQAECgQJBgAAAA==.',
Gw='Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQADCgMIAwABNQAECgYJDwAJAAAAAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFIEKAAIXAAUKBBZfBACsAQAXAAUKBBZfBACsAQA1AAQKgS0AAxcACQpCIeIEADgDABcACQpCIeIEADgDABgAAgrnELomAH0AAAAA.',
He='Hellhore:BAAANQAECgMIBgAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECgcICAAAAA==.',
Ho='Holdenc:BAAANQAECgIIAgABNQAECgkJGgAGAGgbAA==.Hoodz:BAAANQAECgcJEwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgIJAgAAAA==.',
Hu='Huatli:BAAANQADCggJEgAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Ic='Icerod:BAAANQADCgUJBQABNQAECgMJBQAJAAAAAA==.',
Id='Idtrapdat:BAABNQAECoEgAAMWAAkK6yIPCQBkAwAWAAkK6yIPCQBkAwAZAAEKJQTVXgA0AAAAAA==.',
Il='Illyana:BAAANQAECgIJAgAAAA==.Ilse:BAABNQAECoEWAAIaAAkKPho/FADqAgAaAAkKPho/FADqAgAAAA==.',
Im='Imagined:BAACNQAFFIEMAAMIAAUKIQ/uCwChAQAIAAUKIQ/uCwChAQAbAAEKZAAACgA8AAA1AAQKgSQAAggACQpbHWQ1AO0CAAgACQpbHWQ1AO0CAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIBwAAAA==.Infidelic:BAAANQADCgUIBQABNQAECgIJAgAJAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAAANQAECgQICQAAAA==.Ivannalot:BAAANQADCgUIDAAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgQIBAAAAA==.Jarsham:BAAANQAECgIJAgAAAA==.Jaràdan:BAAANQAECgcJCAABNQAECgcJEwAJAAAAAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAABNQAECoEcAAILAAkKPRteKgDEAgALAAkKPRteKgDEAgAAAA==.',
Jo='Joran:BAAANQAECgIIAgAAAA==.Jordie:BAAANQADCgIIAgAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Jw='Jwrs:BAAANQAECgQIBQAAAA==.',
['Jï']='Jïbril:BAABNQAECoEXAAIMAAgKpRjqIwA3AgAMAAgKpRjqIwA3AgAAAA==.',
Ka='Kabbala:BAAANQAECgYIDgABNQAFFAUIDAAIACEPAA==.Kahlani:BAAANQAECgcIEgAAAA==.Kahlua:BAAANQAECgIJAgAAAA==.Kailan:BAAANQAECgQJBgABNQAECggJGQAcAC8cAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBQAJAAAAAA==.Kaldro:BAAANQAECgEIAgAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAAANQAECgUIDQAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAABNQAECoEXAAMHAAgK3xIlYAB3AQAHAAYKmRAlYAB3AQAGAAgKyQTsaABPAQAAAA==.Kathry:BAAANQADCgUIDAAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAAANQAECgUIDQAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keybricker:BAAANQADCgUIBQABNQAFFAIIBgANAGEjAA==.Keymebrah:BAABNQAECoEZAAMIAAkKvRGEdQAzAgAIAAkKWxGEdQAzAgAbAAMKnRF5GwCkAAAAAA==.',
Ki='Killeh:BAAANQADCggICAAAAA==.',
Ko='Korda:BAAANQADCggJDgAAAA==.Korinä:BAAANQAECgYJEAAAAA==.Kosh:BAAANQADCgMIAwAAAA==.Koyra:BAACNQAFFIEHAAIYAAUK/CEJAQD6AQAYAAUK/CEJAQD6AQA1AAQKgSQAAhgACQofJYABAJ0DABgACQofJYABAJ0DAAAA.',
Kr='Kreyden:BAAANQADCgYIBgAAAA==.Krump:BAAANQAECgEJAQAAAA==.',
Ku='Kubs:BAAANQADCgYIBgAAAA==.Kubwa:BAAANQABCgYIDAAAAA==.Kungfugimp:BAAANQAECgQICAAAAA==.Kurral:BAACNQAFFIELAAMUAAUK+hNpCQA9AQAUAAQKPRNpCQA9AQAdAAEKdwDLDAAtAAA1AAQKgSIAAxQACQrjHDQVANYCABQACQrjHDQVANYCAB0AAQpWATFWABwAAAAA.Kurralium:BAAANQAECgYICgABNQAFFAUJCwAUAPoTAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAAANQAECgIIAgAAAA==.',
Ky='Kyramus:BAAANQAECgMIAwAAAA==.',
La='Laconia:BAAANQAECgQIEAAAAA==.Lashstorm:BAAANQAECgEIAQAAAA==.Lattsatnar:BAAANQAECgQIBwAAAA==.',
Le='Lebron:BAAANQAECgQIBAABNQAECgQIBgAJAAAAAA==.Lelesobi:BAAANQABCgQIBwAAAA==.Lennel:BAAANQAECgIJAwAAAA==.',
Lg='Lga:BAAANQADCgYJCwAAAA==.',
Li='Lilsnick:BAAANQAECgIJAgAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQAJAAAAAA==.',
Ll='Llanthyl:BAAANQAECgMIBAAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQAJAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lucía:BAAANQAECgYIBgABNQAECgkJIQARAJIjAA==.Luecien:BAAANQADCgUJBQAAAA==.Lunafalia:BAAANQAECgcJEwAAAA==.Lurosa:BAABNQAECoEcAAIdAAkKLSObAwBhAwAdAAkKLSObAwBhAwAAAA==.Luxeria:BAAANQAECgYIBgAAAA==.Luxray:BAAANQABCggIDQAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBQAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgUJCQAAAA==.',
Ma='Macready:BAABNQAECoEdAAIeAAkKZiTtAACwAwAeAAkKZiTtAACwAwAAAA==.Magenin:BAAANQAECgIIAgAAAA==.Maggotgut:BAAANQAECgEIAQAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairiachi:BAAANQAECgEIAQABNQAFFAUIDAAMANsNAA==.Maltessa:BAAANQADCgUICgABNQAECggJGQAcAC8cAA==.Marload:BAABNQAECoEfAAMWAAkKXxqDPABEAgAWAAgKSR2DPABEAgAZAAgKvAu4IwC4AQAAAA==.Mathy:BAAANQAECgcJDgAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgcIGAAPAO4jAA==.',
Mi='Midletons:BAAANQAECgIIAgAAAA==.Minikub:BAAANQAECgUJCwAAAA==.Mixxy:BAAANQAECgIJAgABNQAFFAYICwADAEAMAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moodroo:BAAANQADCggJIAAAAA==.Moonanoke:BAAANQAECgUJCwAAAA==.Moovoker:BAABNQAECoEXAAIXAAgKyyK6BQAlAwAXAAgKyyK6BQAlAwAAAA==.Morseques:BAAANQAECgcJEwAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMJAwAAAA==.',
Mu='Muggy:BAACNQAFFIEFAAIVAAQK2BkEAwB3AQAVAAQK2BkEAwB3AQA1AAQKgSUAAxUACQoyJr8AAPUDABUACQoyJr8AAPUDAA4AAwp5FyJHANMAAAAA.',
Mx='Mxkebfistin:BAACNQAFFIELAAIDAAYKQAxbAgDJAQADAAYKQAxbAgDJAQA1AAQKgSAAAgMACQqnIJUHABgDAAMACQqnIJUHABgDAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAYICwADAEAMAA==.',
Na='Narama:BAACNQAFFIEIAAMBAAUKHgOaCwAEAQABAAQKzgOaCwAEAQACAAEKWwAvFwA8AAA1AAQKgSQABAEACQrUE9g0AEsCAAEACQrGEtg0AEsCAAIABgqODNUdAF8BAAQAAQoADXklACoAAAAA.',
Ne='Nekka:BAAANQAECgQJBQAAAA==.Nethanos:BAAANQAECgIIAgAAAA==.Neverrmore:BAAANQADCgUIBQAAAA==.',
Ni='Ninæ:BAABNQAECoEcAAIXAAkKpR2yBQAlAwAXAAkKpR2yBQAlAwAAAA==.Nitewïng:BAAANQAECgQJBQABNQADCggIDQAJAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgIJAwAJAAAAAA==.Nohomoh:BAAANQADCgUJBgAAAA==.Nootau:BAAANQAECgQJEgAAAA==.',
Ny='Nyoz:BAAANQADCgYJGgAAAA==.Nyxxadra:BAAANQAECgcJEgAAAA==.',
Om='Omegadeed:BAAANQAECgcJEQAAAA==.',
On='Onne:BAAANQADCgUICwAAAA==.',
Or='Orcinus:BAAANQAFFAEIAQAAAA==.Orcishfist:BAAANQAECgcJBwAAAA==.Orvar:BAAANQAECgQIBQABNQABCgIIAgAJAAAAAA==.',
Pa='Pakaru:BAABNQAECoEVAAISAAgKHxi6RgA4AgASAAgKHxi6RgA4AgAAAA==.Pam:BAACNQAFFIEHAAIKAAQK9hSHBQBJAQAKAAQK9hSHBQBJAQA1AAQKgSIAAwoACQrjJDcFAHUDAAoACQrjJDcFAHUDAA8AAgrTITFBAMIAAAAA.Parathin:BAAANQADCggJEAAAAA==.',
Pe='Peorä:BAAANQAECgYJEAAAAA==.Perfectdark:BAACNQAFFIEMAAIPAAUK5h2WAgDhAQAPAAUK5h2WAgDhAQA1AAQKgSYAAg8ACQpaJFcDAJQDAA8ACQpaJFcDAJQDAAAA.Perse:BAAANQAECgEJAQAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgIJAgAJAAAAAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCgEIAQABNQAECgIIAgAJAAAAAA==.',
Pi='Pieper:BAAANQAECgYJDwAAAA==.Pipa:BAABNQAECoEbAAIGAAgKMCRCCQBIAwAGAAgKMCRCCQBIAwAAAA==.Pippit:BAAANQAECgYIDgABNQAECggIGwAGADAkAA==.',
Pl='Plokane:BAAANQAECgYIEQAAAA==.',
Po='Poacher:BAAANQADCgMIAwAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgAAAA==.Powar:BAAANQAECgYICAAAAA==.',
Pr='Provence:BAAANQADCgYICAAAAA==.',
Py='Pyreynna:BAAANQAECgMJBwAAAA==.',
['Pè']='Pèppèr:BAAANQAECgYIDQABNQAECgcIEwAJAAAAAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEJAQABNQAECgkJGgAGAGgbAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAAANQAECgQJBgAAAA==.Rapsodia:BAAANQAECgIIAgABNQAECggIEQAJAAAAAA==.Raschild:BAAANQAECgMIBQAAAA==.',
Re='Realfrojd:BAABNQAECoEXAAIMAAgK5AapTgBEAQAMAAgK5AapTgBEAQAAAA==.Regginunchuk:BAABNQAECoEXAAIDAAgKWxyfDgCRAgADAAgKWxyfDgCRAgAAAA==.Releronastus:BAAANQAECgEIAgAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECoEgAAMRAAkKQhciEQAJAgARAAgKFBYiEQAJAgASAAgKcRS5YADcAQAAAA==.Reyson:BAAANQAECgcIEwAAAA==.',
Rh='Rhunon:BAABNQAECoEkAAIMAAkKbhnaHQBnAgAMAAkKbhnaHQBnAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rinchi:BAAANQADCgYIBgAAAA==.Rinthia:BAABNQAECoEZAAIcAAgKLxx8DgC3AgAcAAgKLxx8DgC3AgAAAA==.Ripyeet:BAAANQAECgYJEgAAAA==.',
Ro='Rol:BAAANQAECgEIAQAAAA==.Rolden:BAAANQADCggJFwAAAA==.',
Ru='Rukaji:BAAANQAECgMJCQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYJFAABNQADCgQIBQAJAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAAANQAECgUIDQAAAA==.Samayel:BAAANQADCgUJBQAAAA==.Sarkang:BAAANQAECgUIDQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgcIEwAJAAAAAA==.',
Sc='Schmeebie:BAAANQAECgIJAgABNQAECgUJCQAJAAAAAA==.Schutze:BAABNQAECoEZAAIfAAkKhySwAAB2AwAfAAkKhySwAAB2AwAAAA==.',
Sd='Sdadfeg:BAAANQAECgcJEwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgYIDgAJAAAAAA==.Senco:BAAANQAECgIIAwAAAA==.',
Sh='Shabobado:BAAANQAECgYIDwAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAECgYJBgAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQADCggIDAAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinterklaas:BAAANQAECgcJDwAAAA==.',
Sk='Skjald:BAAANQAECgMJAwABNQAFFAIIBgANAGEjAA==.Skylee:BAAANQAECgYJEAAAAA==.',
Sl='Slark:BAAANQAECgQIDAAAAA==.Slawth:BAAANQAECgYJCwAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAAANQAECgcIDAAAAA==.Smeyplus:BAACNQAFFIELAAMSAAUKdCSdAwClAQASAAQKEiSdAwClAQARAAEK+SXVBgBsAAA1AAQKgSEAAxIACQq+JiIBAPUDABIACQqZJiIBAPUDABEAAQrVJkw8AHIAAAAA.',
Sn='Snickeris:BAAANQAECgIIAgABNQAECgIJAgAJAAAAAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgIJAwAAAA==.Snurchbasher:BAAANQAECgMJBgAAAA==.',
Sp='Sparrowhawk:BAAANQABCgQIBAAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECoEaAAIGAAkKaBt4GgC4AgAGAAkKaBt4GgC4AgAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMJAwAAAA==.',
St='Stars:BAAANQAECggIDQABNQAECgkJIAAWAOsiAA==.Stinkiepete:BAAANQADCggJDwAAAA==.',
Su='Sureno:BAAANQAECgQICgAAAA==.',
Sx='Sxyhealz:BAAANQAECgQIBAAAAA==.Sxyheålz:BAABNQAECoEfAAINAAkKfBE0KABgAgANAAkKfBE0KABgAgAAAA==.',
Ta='Taliä:BAAANQADCgUJBQAAAA==.Tanndari:BAAANQADCgcJFwAAAA==.Tartare:BAAANQAECgQIBAAAAA==.Tashaman:BAABNQAECoEvAAMGAAkKohBLNwAVAgAGAAkKohBLNwAVAgAHAAUKmgX9jQD1AAAAAA==.',
Te='Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggJDwAAAA==.Teriheals:BAAANQAECgIJAwAAAA==.',
Th='Thejorlane:BAAANQADCgUIDAAAAA==.Thiccholy:BAABNQAECoEhAAQaAAkKMxY3MwAvAgAaAAgKARU3MwAvAgARAAkKnA2AFADVAQASAAQKIQzlygDOAAAAAA==.Thiccshields:BAAANQADCgQIBAABNQAECgkJIQAaADMWAA==.Thicctotemz:BAAANQAECgUIBgABNQAECgkJIQAaADMWAA==.Thogo:BAAANQAECgcJEwAAAA==.',
Ti='Tikaa:BAAANQADCgYIGgAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECoEhAAIRAAkKkiObAgB8AwARAAkKkiObAgB8AwAAAA==.Tomerto:BAAANQAECgcIEwAAAA==.Toobeastly:BAAANQAECgQJEAAAAA==.Toonerdin:BAAANQAECgMIBAAAAA==.',
Tr='Tril:BAAANQAECgIJAwAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAAANQAECgQJBwABNQAECggJBAAJAAAAAA==.Tryingmybest:BAACNQAFFIEGAAINAAIKYSOODwDYAAANAAIKYSOODwDYAAA1AAQKgSEABA0ACQqNJNwCAJwDAA0ACQqNJNwCAJwDACAABgp7GYgGAMMBABwAAQrVCMdaACcAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.',
Ty='Tydrodh:BAAANQAECggJBAAAAQ==.Tyestaumin:BAAANQADCgcIBwABNQAECgEIAgAJAAAAAA==.Tyralen:BAABNQAECoEXAAIWAAgKeBayMgBoAgAWAAgKeBayMgBoAgAAAA==.Tyrandras:BAAANQAECgUIDQABNQAECggIFwAWAHgWAA==.Tyronnius:BAAANQAECgMJBAAAAA==.Tyrïon:BAABNQAECoEgAAILAAgK+SO8FwAqAwALAAgK+SO8FwAqAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBQAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAIIBgANAGEjAA==.',
Va='Vaero:BAAANQAECgUICgAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgEIAQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAECgkJHgAYAOIUAA==.Velyssa:BAAANQAECgMJBAAAAA==.',
Vi='Vibin:BAABNQAECoEaAAIXAAgKSxuKDQCDAgAXAAgKSxuKDQCDAgAAAA==.Vineeshewah:BAAANQAECgMJBAAAAA==.',
Vo='Voidguy:BAAANQAECgMJBAAAAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQAECgQIBQABNQAECgkJGgAGAGgbAA==.',
Wh='Whatapal:BAAANQAECgIJAgAAAA==.',
Wi='Wilbo:BAAANQAECgcIEwABNQAFFAUICwAVAF8LAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAAANQAECgQJBgAAAA==.',
Wo='Wolfdrudu:BAAANQAECgMJBAAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgEJAQAAAA==.Wormszer:BAAANQAECgEIAQAAAA==.Wotan:BAAANQADCgIJAgAAAA==.Woth:BAAANQADCgcIBwAAAA==.',
Wr='Wrâîth:BAAANQADCgUIBQABNQAECgIJAgAJAAAAAA==.',
Wy='Wynds:BAACNQAFFIEMAAIXAAUK6SXFAQA4AgAXAAUK6SXFAQA4AgA1AAQKgSYAAhcACQr1JhQAAP8DABcACQr1JhQAAP8DAAAA.Wyngs:BAAANQAECgYIDAABNQAFFAUIDAAXAOklAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAAANQAECgUIDQAAAA==.Xiaozhi:BAEANQAECgMJBAAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgMIBgAAAA==.',
Yo='Yoirr:BAAANQAECgMIBgAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECgQJBwAJAAAAAA==.Zanori:BAABNQAECoEbAAQOAAgKzw1CJgDCAQAOAAgKzw1CJgDCAQAVAAUKLgZYYQDvAAAMAAEKbhFgmQAwAAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECggIGwAOAM8NAA==.',
Ze='Zellyne:BAAANQAECgQJBAABNQAECgkJHAAXAKUdAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAABNQAECoEsAAIWAAkKDyRLBwB4AwAWAAkKDyRLBwB4AwAAAA==.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQADCggIFAAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Êv']='Êvelyn:BAAANQADCggJEQAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQAJAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQAJAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgYIDgAAAA==.',
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
