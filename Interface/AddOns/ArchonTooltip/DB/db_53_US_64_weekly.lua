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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','DeathKnight-Blood','Priest-Holy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Protection','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aamix:BAABNQAECoEcAAMBAAkJ7hKXMwAGAgABAAgJrRGXMwAGAgACAAYJ6A1QGgBtAQAAAA==.Aarom:BAACNQAFFIEIAAIDAAUJWRi7AQC9AQADAAUJWRi7AQC9AQA1AAQKgRsAAgMACQl3I2YEAEgDAAMACQl3I2YEAEgDAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQAECgMIBAAAAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aerius:BAAANQADCggIGAAAAA==.',
Af='Affliclock:BAABNQAECoEXAAIEAAkJYBzvAAAGAwAEAAkJYBzvAAAGAwAAAA==.',
Ai='Aingerfal:BAAANQADCggIEgAAAA==.',
Ak='Akasori:BAAANQAECgYIEwAAAA==.Akosori:BAAANQADCgYIDAABNQAECgYIEwAFAAAAAA==.',
Al='Alterboyy:BAAANQAECgEIAQAAAA==.Alîsonshammy:BAABNQAECoEZAAMGAAkJaiCRBABvAwAGAAkJaiCRBABvAwAHAAgJPBeuIwBXAgAAAA==.',
Am='Ambersulfr:BAAANQAECgMIBAAAAA==.Amrazz:BAAANQAECgQICAAAAA==.Amzey:BAEANQAECgcIEwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwAFAAAAAA==.Andromeda:BAAANQAECgYIDAAAAA==.Anneaux:BAAANQADCggIEwAAAA==.Antimortem:BAAANQADCgQICAAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgQIBQAAAA==.Astralus:BAAANQAECgMIBAAAAA==.Astramis:BAAANQADCggIFwAAAA==.',
At='Atomicbarbie:BAAANQAECgQIBAABNQAECgkJGQAGAGogAA==.Atriøx:BAAANQAECgIIAgAAAA==.Atziri:BAAANQAECgYIDgAAAA==.',
Az='Azamia:BAAANQAECgQIBgABNQABCgIIAwAFAAAAAA==.',
Ba='Backlash:BAAANQAECgMIBQAAAA==.Balzhac:BAAANQAECgYIBgAAAA==.Bam:BAAANQADCggICAABNQAFFAIIAgAFAAAAAA==.Bamplify:BAAANQAFFAIIAgAAAA==.Barrierbobo:BAAANQAECgEIAQAAAA==.Barthold:BAAANQADCgcICwAAAA==.',
Be='Bellmonte:BAAANQADCgYIDAABNQAECgQIDAAFAAAAAA==.Belmonk:BAAANQAECgEIAQAAAA==.Berdron:BAAANQAECgYIEgAAAA==.',
Bl='Bladeliger:BAAANQAECgYIDAAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECoEdAAIIAAkJyySwAwDDAwAIAAkJyySwAwDDAwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAAANQAECgMIAwAAAA==.Bonemair:BAACNQAFFIEHAAIJAAQJFAoxBwDrAAAJAAQJFAoxBwDrAAA1AAQKgSIAAgkACQmaH8MIACwDAAkACQmaH8MIACwDAAAA.Boredasf:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIDAAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQADCgYIGAAFAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIIAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAECgkJHgAKAIgjAA==.Bullteesta:BAAANQADCgQIBAAAAA==.Burkhard:BAAANQABCgYIBgAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgIIAgAAAA==.',
Ca='Caldec:BAACNQAFFIEGAAILAAQJsg7DAQA8AQALAAQJsg7DAQA8AQA1AAQKgSMAAgsACQn9JJEBAKwDAAsACQn9JJEBAKwDAAAA.',
Ch='Chainizard:BAAANQAECgcICwAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECgcICwAFAAAAAA==.Cheeno:BAAANQAECgUIDwAAAA==.Chihiro:BAAANQADCggIGAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Cl='Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMIAwABNQADCgYIGAAFAAAAAA==.Computer:BAABNQAECoEfAAMCAAkJyiCmAgAEAwACAAgJ/yKmAgAEAwABAAgJAh0CFQC6AgAAAA==.Cootin:BAAANQAECggIBgAAAA==.',
Cp='Cpteddie:BAABNQAECoEWAAMMAAkJMBozBwCbAgAMAAkJgxkzBwCbAgANAAMJahFDqQC2AAABNQAFFAQIDAAJAAEeAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.Crelam:BAACNQAFFIEHAAIOAAQJ4wPaAAA9AQAOAAQJ4wPaAAA9AQA1AAQKgSIAAg4ACQkpFHEGAKgCAA4ACQkpFHEGAKgCAAAA.Critherine:BAAANQADCggIDgAAAA==.Cronatherus:BAAANQADCgUICgAAAA==.Cruentis:BAAANQAECgQICAAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDgAFAAAAAA==.Crysus:BAAANQAECgcIDgAAAA==.',
Da='Dabo:BAAANQAECgYIDQAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJHQAIAMskAA==.Darwin:BAAANQAECgEIAQAAAA==.Dasmoodhayn:BAAANQADCggIFgAAAA==.Davalanch:BAABNQAECoEfAAIHAAkJWxm5FQDNAgAHAAkJWxm5FQDNAgAAAA==.Dazizejr:BAABNQAECoEYAAIJAAgJ/ySyBgBQAwAJAAgJ/ySyBgBQAwAAAA==.',
De='Deathisbrew:BAAANQAECggICAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Denïed:BAAANQADCgQIBAAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCgYICQAAAA==.',
Di='Dibstrum:BAAANQADCgcIEAAAAA==.Digduug:BAAANQAECgQIBQAAAA==.Dixqt:BAAANQAECgQICAAAAA==.',
Do='Dogfight:BAABNQAECoEeAAMPAAkJ1BqZEADTAgAPAAkJ1BqZEADTAgALAAIJQANcTABAAAAAAA==.Doilookfatou:BAAANQAECgUICgAAAA==.',
Dr='Draxus:BAAANQAECgIIAgAAAA==.Dresel:BAAANQAECggIDgAAAA==.Drewpeebahlz:BAAANQADCgYICgABNQABCgIIAgAFAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQADCggIDgAAAA==.Durto:BAAANQADCgYIBgAAAA==.',
Dy='Dyami:BAAANQAECgUICAAAAA==.Dynas:BAAANQADCgcIDgAAAA==.',
Ea='Earthcake:BAAANQAECgcIEwAAAA==.',
Ed='Eddielich:BAACNQAFFIEMAAIJAAQJAR4KBABuAQAJAAQJAR4KBABuAQA1AAQKgSAAAgkACQnEJJUCAK4DAAkACQnEJJUCAK4DAAAA.',
Eg='Eggfumonk:BAAANQADCgYIGAAAAA==.',
Eh='Ehlo:BAAANQADCgEIAQAAAA==.',
El='Elasmon:BAAANQAECgUIBgAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQADCgMIAwAAAA==.',
Er='Erragal:BAAANQADCgMIAwAAAA==.',
Es='Escanõr:BAAANQADCggICAAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.',
Fe='Felurián:BAAANQADCggICwABNQADCgUIDAAFAAAAAA==.Fexli:BAAANQADCgMIAwAAAA==.',
Fi='Fireteeth:BAAANQADCggIDAAAAA==.',
Fl='Flurtty:BAAANQADCgQICAAAAA==.',
Fo='Folklore:BAAANQADCggIGgAAAA==.',
Fr='Frighrish:BAAANQADCggICAAAAA==.Frigomortis:BAAANQADCgYIFgABNQADCggIGQAFAAAAAA==.Frozown:BAAANQAECgYIDAAAAA==.Fruits:BAAANQAECgEIAgAAAA==.',
Ft='Ftfw:BAAANQAECgUICAAAAA==.',
Fu='Funfanfare:BAAANQADCgQIBAAAAA==.Furrylife:BAAANQADCggIEwAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQAFAAAAAA==.Fuzzychin:BAAANQAECgIIBAAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAAANQAECgYIDAABNQAFFAQIBwAOAOMDAA==.Gardettos:BAAANQAECgYIDAAAAA==.Gargingoyles:BAAANQADCgIIAgAAAA==.',
Gh='Gharghael:BAAANQAECgIIAgAAAA==.Ghostthunter:BAAANQADCgQIBAABNQAECgYIBwAFAAAAAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAAANQAECgYICwABNQAFFAQIBwAJABQKAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAAANQADCgIIAgAAAA==.Gnxrr:BAEANQAECggIEgAAAA==.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgQIBQAAAA==.',
Gr='Gregorz:BAAANQADCgMIAwAAAA==.Greyanna:BAAANQAECgEIAQAAAA==.Gridon:BAAANQABCgUIBQAAAA==.Gromthrall:BAAANQAECgMIAwAAAA==.',
Gw='Gworp:BAAANQAECgIIAgAAAA==.Gwynhwyfar:BAAANQADCgMIAwABNQAECgUICQAFAAAAAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFIEHAAIQAAQJqxjyAwBmAQAQAAQJqxjyAwBmAQA1AAQKgSUAAxAACQmqIC4EADEDABAACQmqIC4EADEDABEAAQksGpQlAEwAAAAA.',
He='Hellhore:BAAANQAECgIIAwAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECgEIAQAAAA==.',
Ho='Holdenc:BAAANQAECgIIAgABNQAECggIDwAFAAAAAA==.Hoodz:BAAANQAECgYIDAAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQADCgcIEAAAAA==.',
Hu='Huatli:BAAANQADCgcIBwAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Id='Idtrapdat:BAABNQAECoEcAAMSAAkJViAnCABQAwASAAkJViAnCABQAwATAAEJJQSQTAA3AAAAAA==.',
Il='Illyana:BAAANQAECgIIAgAAAA==.Ilse:BAAANQAECgcIDgAAAA==.',
Im='Imagined:BAACNQAFFIEHAAMUAAQJig5PDgAFAQAUAAMJQRNPDgAFAQAVAAEJZAC2BQBAAAA1AAQKgSAAAhQACQl5G/0vANECABQACQl5G/0vANECAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIBwAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAAANQAECgQIBQAAAA==.Ivannalot:BAAANQADCgUIDAAAAA==.Ivracha:BAAANQAECgEIAQAAAA==.',
Ja='Jage:BAAANQADCggIEQAAAA==.Jarsham:BAAANQADCggIGQAAAA==.Jaràdan:BAAANQAECgEIAQABNQAECgcIEwAFAAAAAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAAANQAECggIEAAAAA==.',
Jo='Joran:BAAANQADCggIDwAAAA==.Jordie:BAAANQADCgIIAgAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Jw='Jwrs:BAAANQAECgQIBQAAAA==.',
['Jï']='Jïbril:BAAANQAECgYIDgAAAA==.',
Ka='Kabbala:BAAANQAECgYIDgABNQAFFAQIBwAUAIoOAA==.Kahlani:BAAANQAECgYICwAAAA==.Kahlua:BAAANQAECgIIAgAAAA==.Kailan:BAAANQAECgIIAgABNQAECgYIDQAFAAAAAA==.Kalathios:BAAANQABCgIIAgABNQAECgIIAgAFAAAAAA==.Kaldro:BAAANQAECgEIAQAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAAANQAECgUICAAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAAANQAECgYIDQAAAA==.Kathry:BAAANQADCgUIDAAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAAANQAECgUICAAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keybricker:BAAANQADCgUIBQABNQAECgkJHgAKAIgjAA==.Keymebrah:BAABNQAECoEWAAMUAAkJsxEzWABBAgAUAAkJUREzWABBAgAVAAMJnRGWFQClAAAAAA==.',
Ko='Korda:BAAANQADCggIDgAAAA==.Korinä:BAAANQAECgYIDAAAAA==.Kosh:BAAANQADCgMIAwAAAA==.Koyra:BAABNQAECoEgAAIRAAkJDCUaAQClAwARAAkJDCUaAQClAwAAAA==.',
Kr='Krump:BAAANQADCgcIDQAAAA==.',
Ku='Kubs:BAAANQADCgYIBgAAAA==.Kubwa:BAAANQABCgYICwAAAA==.Kungfugimp:BAAANQAECgQIBAAAAA==.Kurral:BAACNQAFFIEHAAIWAAQJdxJ4BQBOAQAWAAQJdxJ4BQBOAQA1AAQKgSIAAxYACQnjHNoOAP0CABYACQnjHNoOAP0CABcAAQlWAftGABwAAAAA.Kurralium:BAAANQAECgYIBgABNQAFFAQIBwAWAHcSAA==.Kurstina:BAAANQADCgYICQAAAA==.',
Ky='Kyramus:BAAANQADCggIGgAAAA==.',
La='Laconia:BAAANQAECgQIDAAAAA==.Lashstorm:BAAANQAECgEIAQAAAA==.Lattsatnar:BAAANQAECgQIBQAAAA==.',
Le='Lebron:BAAANQADCgYIDAABNQAECgIIAgAFAAAAAA==.Lelesobi:BAAANQABCgQIBwAAAA==.Lennel:BAAANQAECgEIAQAAAA==.',
Lg='Lga:BAAANQADCgYIBgAAAA==.',
Li='Lilsnick:BAAANQADCggIDwABNQADCggIGAAFAAAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.',
Ll='Llanthyl:BAAANQAECgEIAQAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lunafalia:BAAANQAECgYIDAAAAA==.Lurosa:BAAANQAFFAEIAQAAAA==.Luxeria:BAAANQAECgYIBgAAAA==.Luxray:BAAANQABCggIDQAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBQAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgUIBQAAAA==.',
Ma='Macready:BAABNQAECoEaAAIYAAgJyCPZAQBGAwAYAAgJyCPZAQBGAwAAAA==.Magenin:BAAANQADCggIGAAAAA==.Maggotgut:BAAANQADCgQIBQAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairiachi:BAAANQAECgEIAQABNQAFFAQIBwAJABQKAA==.Maltessa:BAAANQADCgUICgABNQAECgYIDQAFAAAAAA==.Marload:BAABNQAECoEZAAMSAAkJPxqQJwBiAgASAAgJSR2QJwBiAgATAAgJjQYUJQBaAQAAAA==.Mathy:BAAANQAECgcIBwAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.',
Mi='Midletons:BAAANQADCggIFgAAAA==.Minikub:BAAANQAECgQIBgAAAA==.Mixxy:BAAANQADCgIIAgABNQAECgkJHAADACwgAA==.',
Mn='Mnzn:BAAANQADCggIEgAAAA==.',
Mo='Moodroo:BAAANQADCggIGAAAAA==.Moonanoke:BAAANQAECgQIBQAAAA==.Moovoker:BAAANQAECgYIDQAAAA==.Morseques:BAAANQAECgYIDAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAABNQAECoEcAAMPAAkJACSvBgBjAwAPAAkJACSvBgBjAwALAAMJeReBMADeAAAAAA==.',
Mx='Mxkebfistin:BAABNQAECoEcAAIDAAkJLCBkBgANAwADAAkJLCBkBgANAwAAAA==.Mxkebspinnin:BAAANQADCggICAABNQAECgkJHAADACwgAA==.',
Na='Narama:BAACNQAFFIEEAAMBAAQJfAEkDQCoAAABAAMJ3AEkDQCoAAACAAEJWwB+EAA9AAA1AAQKgSAABAEACQn+EtYuAB4CAAEACQmaENYuAB4CAAIABgmODJwaAGoBAAQAAQkADbgfACsAAAAA.',
Ne='Nekka:BAAANQAECgQIBAAAAA==.Nethanos:BAAANQADCgQIBAAAAA==.Neverrmore:BAAANQADCgUIBQAAAA==.',
Ni='Ninæ:BAABNQAECoEZAAIQAAkJfBvkBAAcAwAQAAkJfBvkBAAcAwAAAA==.Nitewïng:BAAANQADCggIFgABNQADCggIDQAFAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgEIAQAFAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAAANQAECgQIEAAAAA==.',
Ny='Nyoz:BAAANQADCgYIFAAAAA==.Nyxxadra:BAAANQAECgYICwAAAA==.',
Om='Omegadeed:BAAANQAECgYIDAAAAA==.',
On='Onne:BAAANQADCgMIBgAAAA==.',
Or='Orcinus:BAAANQAFFAEIAQAAAA==.Orcishfist:BAAANQADCggICAAAAA==.Orvar:BAAANQAECgQIBAABNQABCgIIAgAFAAAAAA==.',
Pa='Pakaru:BAAANQAECgYICwAAAA==.Pam:BAABNQAECoEgAAMZAAkJEiQXBAB0AwAZAAkJEiQXBAB0AwAaAAIJ0yEEOwDIAAABNQAFFAIIAgAFAAAAAA==.Parathin:BAAANQADCggICAAAAA==.',
Pe='Peorä:BAAANQAECgYIDAAAAA==.Perfectdark:BAACNQAFFIEHAAIaAAQJJxc2AwBnAQAaAAQJJxc2AwBnAQA1AAQKgSIAAhoACQneI74CAJoDABoACQneI74CAJoDAAAA.Perse:BAAANQAECgEIAQAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQADCggIGQAFAAAAAA==.Pheadas:BAAANQADCgUIBQAAAA==.Phleez:BAAANQADCgEIAQABNQAECgEIAQAFAAAAAA==.',
Pi='Pieper:BAAANQAECgUICQAAAA==.Pipa:BAAANQAECgYIEQAAAA==.Pippit:BAAANQAECgUIDAABNQAECgYIEQAFAAAAAA==.',
Pl='Plokane:BAAANQAECgYIDAAAAA==.',
Po='Poacher:BAAANQADCgMIAwAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgIIAgAAAA==.Powar:BAAANQADCgUIAwAAAA==.',
Pr='Provence:BAAANQADCgYICAAAAA==.',
Py='Pyreynna:BAAANQAECgMIBAAAAA==.',
['Pè']='Pèppèr:BAAANQAECgUICwABNQAECgYIDAAFAAAAAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAAANQAECgIIAgAAAA==.Raschild:BAAANQAECgMIBAAAAA==.',
Re='Realfrojd:BAAANQAECgUICwAAAA==.Regginunchuk:BAAANQAECgYIDQAAAA==.Releronastus:BAAANQAECgEIAQAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECoEXAAMMAAgJjxfVDAAJAgAMAAgJeBTVDAAJAgANAAcJSBWQUgCtAQAAAA==.Reyson:BAAANQAECgYIDAAAAA==.',
Rh='Rhunon:BAABNQAECoEbAAIJAAgJ9xWCIgAHAgAJAAgJ9xWCIgAHAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rinthia:BAAANQAECgYIDQAAAA==.Ripyeet:BAAANQAECgQIDAAAAA==.',
Ro='Rol:BAAANQADCgQIBAAAAA==.Rolden:BAAANQADCgcIEAAAAA==.',
Ru='Rukaji:BAAANQAECgMIBgAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIEwABNQADCgQIBQAFAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAAANQAECgUICAAAAA==.Sarkang:BAAANQAECgUIBgAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgYIDAAFAAAAAA==.',
Sc='Schutze:BAABNQAECoEWAAIbAAkJhyRxAACRAwAbAAkJhyRxAACRAwAAAA==.',
Sd='Sdadfeg:BAAANQAECgYIDAAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgUICAAFAAAAAA==.Senco:BAAANQAECgEIAQAAAA==.',
Sh='Shabobado:BAAANQAECgYICwAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shxdow:BAAANQADCgEIAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQADCggIDAAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinterklaas:BAAANQAECgUICAAAAA==.',
Sk='Skylee:BAAANQAECgUICgAAAA==.',
Sl='Slark:BAAANQAECgQICAAAAA==.Slawth:BAAANQAECgUICgAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAAANQAECgcIDAAAAA==.Smeyplus:BAACNQAFFIEHAAMNAAQJfyRvAwA9AQANAAMJASRvAwA9AQAMAAEJ+SWwBABvAAA1AAQKgR0AAw0ACQmmJt8AAPYDAA0ACQlvJt8AAPYDAAwAAQnVJpMwAHMAAAAA.',
Sn='Snickeris:BAAANQADCggIGAAAAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgIIAgAAAA==.Snurchbasher:BAAANQAECgMIAwAAAA==.',
Sp='Sparrowhawk:BAAANQABCgQIBAAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAAANQAECggIDwAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMIAwAAAA==.',
St='Stars:BAAANQAECgUIBQABNQAECgkJHAASAFYgAA==.Stinkiepete:BAAANQADCgcICQAAAA==.',
Su='Sureno:BAAANQAECgQICQAAAA==.',
Sx='Sxyhealz:BAAANQADCggICAAAAA==.Sxyheålz:BAABNQAECoEZAAIKAAkJrwy6MQDdAQAKAAkJrwy6MQDdAQAAAA==.',
Ta='Taliä:BAAANQADCgUIBQAAAA==.Tanndari:BAAANQADCgUIEAAAAA==.Tartare:BAAANQAECgQIBAAAAA==.Tashaman:BAABNQAECoErAAMGAAkJJQ6DLQAIAgAGAAkJJQ6DLQAIAgAHAAUJmgUxcQD7AAAAAA==.',
Te='Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggICAAAAA==.Teriheals:BAAANQAECgEIAQAAAA==.',
Th='Thejorlane:BAAANQADCgUIDAAAAA==.Thiccholy:BAABNQAECoEeAAQMAAkJzg0UDgDwAQAMAAkJnA0UDgDwAQAcAAcJWxasMwDvAQANAAQJIQywngDQAAAAAA==.Thiccshields:BAAANQADCgQIBAABNQAECgkJHgAMAM4NAA==.Thicctotemz:BAAANQAECgEIAQABNQAECgkJHgAMAM4NAA==.Thogo:BAAANQAECgYIDAAAAA==.',
Ti='Tikaa:BAAANQADCgYIFAAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECoEeAAIMAAkJMiO7AQCIAwAMAAkJMiO7AQCIAwAAAA==.Tomerto:BAAANQAECgYIDAAAAA==.Toobeastly:BAAANQAECgQIDAAAAA==.Toonerdin:BAAANQAECgEIAQAAAA==.',
Tr='Tril:BAAANQAECgEIAQAAAA==.Trox:BAAANQADCgcIEgAAAA==.Tryingmybest:BAABNQAECoEeAAQKAAkJiCPTAQCfAwAKAAkJiCPTAQCfAwAdAAYJexmQBQDMAQAeAAEJ1QivSwArAAAAAA==.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Ty='Tyestaumin:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Tyralen:BAAANQAECgYIDQAAAA==.Tyrandras:BAAANQAECgUICAABNQAECgYIDQAFAAAAAA==.Tyronnius:BAAANQAECgEIAQAAAA==.Tyrïon:BAABNQAECoEYAAIIAAgJUyBMGQABAwAIAAgJUyBMGQABAwAAAA==.',
Un='Unlyfe:BAAANQAECgIIAgAAAA==.Unnamed:BAAANQADCgYIBgABNQAECgkJHgAKAIgjAA==.',
Va='Vaero:BAAANQAECgUIBQAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgEIAQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAECgkJHAARACUTAA==.Velyssa:BAAANQAECgEIAQAAAA==.',
Vi='Vibin:BAAANQAECgYIDQAAAA==.Vineeshewah:BAAANQAECgEIAQAAAA==.',
Vo='Voidguy:BAAANQAECgEIAQAAAA==.',
Vu='Vulsted:BAAANQADCggIFQAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQADCggIDAABNQAECggIDwAFAAAAAA==.',
Wh='Whatapal:BAAANQADCggIFQAAAA==.',
Wi='Wilbo:BAAANQAECgYIEQABNQAECgkJHgAPANQaAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAAANQAECgIIAgAAAA==.',
Wo='Wolfdrudu:BAAANQAECgEIAQAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQADCggIHQAAAA==.Wormszer:BAAANQADCggIGQAAAA==.Wotan:BAAANQADCgIIAgAAAA==.Woth:BAAANQADCgcIBwAAAA==.',
Wy='Wynds:BAACNQAFFIEHAAIQAAQJByVrAgDBAQAQAAQJByVrAgDBAQA1AAQKgSIAAhAACQnoJhEAAAMEABAACQnoJhEAAAMEAAAA.Wyngs:BAAANQAECgYIDAABNQAFFAQIBwAQAAclAA==.',
Xe='Xeres:BAAANQABCgIIBAAAAA==.',
Xi='Xi:BAAANQAECgUICAAAAA==.Xiaozhi:BAEANQAECgEIAQAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgMIBAAAAA==.',
Yo='Yoirr:BAAANQAECgIIAwAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECgMIBAAFAAAAAA==.Zanori:BAAANQAECgYIDwAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgYIDwAFAAAAAA==.',
Ze='Zellyne:BAAANQADCggICAABNQAECgkJGQAQAHwbAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAABNQAECoEoAAISAAkJ3CNcBACLAwASAAkJ3CNcBACLAwAAAA==.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQADCggIEQAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Êv']='Êvelyn:BAAANQADCgYICQAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQAFAAAAAA==.',
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
