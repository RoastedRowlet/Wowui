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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Priest-Shadow','Mage-Arcane','Unknown-Unknown','Warrior-Protection','DemonHunter-Havoc','Evoker-Devastation','Druid-Balance','Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Hunter-Survival','Paladin-Holy','Mage-Frost','Monk-Brewmaster','Druid-Restoration','Rogue-Assassination','Warrior-Fury','Priest-Discipline',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aamix:BAACNQAFFIEIAAQBAAUKOgZMGgC3AAABAAMKBgZMGgC3AAACAAEKVwybCgBJAAADAAEKuACPHAA/AAA1AAQKgTMAAwEACQpnGS04AG8CAAEACAoUGC04AG8CAAMABgoXD74cAHgBAAAA.Aarom:BAACNQAFFIEUAAIEAAYK9h1UAgAYAgAEAAYK9h1UAgAYAgA1AAQKgSAAAgQACQqfIxIJABgDAAQACQqfIxIJABgDAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQAECgYICwAAAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aequitas:BAAANQADCgUIBQAAAA==.Aerius:BAAANQAECgIIBAAAAA==.',
Af='Affliclock:BAACNQAFFIELAAICAAUKMRRVAAC/AQACAAUKMRRVAAC/AQA1AAQKgRsAAgIACQrRH3QBABIDAAIACQrRH3QBABIDAAAA.',
Ai='Aingerfal:BAAANQAECgEIAQAAAA==.',
Aj='Aj:BAAANQAECgMIAwAAAA==.',
Ak='Akasori:BAABNQAECoEqAAIFAAkK9yC3AgBWAwAFAAkK9yC3AgBWAwAAAA==.Akosori:BAAANQADCgYIDAABNQAECgkJKgAFAPcgAA==.',
Al='Alterboyy:BAAANQAECgUIBwAAAA==.Alîsonshammy:BAACNQAFFIEHAAIGAAMKKCNcCwA2AQAGAAMKKCNcCwA2AQA1AAQKgRwAAwYACQqEInQJAFYDAAYACQqEInQJAFYDAAcACAo8F2NAACkCAAAA.',
Am='Ambersulfr:BAAANQAECgUIDAAAAA==.Amrazz:BAABNQAECoEYAAMIAAkKbhkNGADoAgAIAAkKbhkNGADoAgAJAAIKzwsnUwBhAAAAAA==.Amzey:BAEBNQAECoElAAIKAAkKMR4FKAAqAwAKAAkKMR4FKAAqAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwALAAAAAA==.Andromeda:BAABNQAECoEeAAIMAAgKSRe0DAAUAgAMAAgKSRe0DAAUAgAAAA==.Anneaux:BAAANQAECgIJAgAAAA==.Antimortem:BAAANQADCgUIDwAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgUJCgAAAA==.Astralus:BAAANQAECgQICQAAAA==.Astramis:BAAANQAECgUICAAAAA==.',
At='Atomicbarbie:BAAANQAECgcIDwABNQAFFAMIBwAGACgjAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECoEfAAIHAAgKOBaAPQA1AgAHAAgKOBaAPQA1AgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgQICQABNQABCgIIAwALAAAAAA==.',
Ba='Backlash:BAAANQAECgYIDgAAAA==.Balzhac:BAAANQAECgYIDAAAAA==.Bam:BAAANQADCggICAABNQAFFAUIDAANAKQaAA==.Bamplify:BAABNQAECoEVAAIKAAkKnx1JLwATAwAKAAkKnx1JLwATAwABNQAFFAUIDAANAKQaAA==.Barrierbobo:BAAANQAECgQICAAAAA==.Barthold:BAAANQADCggIHAAAAA==.',
Be='Beleaf:BAAANQAECgYIBgAAAA==.Bellmonte:BAAANQADCgYIDwABNQAECgcIGQAOAMYcAA==.Belmonk:BAAANQAECgEIAQAAAA==.Berdron:BAABNQAECoEjAAIDAAgKsxHqCwAlAgADAAgKsxHqCwAlAgAAAA==.',
Bi='Biden:BAAANQAECgEIAQAAAA==.',
Bl='Bladeliger:BAABNQAECoEeAAIPAAgKNhg0KABWAgAPAAgKNhg0KABWAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECoEhAAIQAAkKyyThDQB4AwAQAAkKyyThDQB4AwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAAANQAECgUIDQAAAA==.Bonemair:BAACNQAFFIERAAIRAAUK2w0eDAAuAQARAAUK2w0eDAAuAQA1AAQKgSkAAhEACQqrIK8OABUDABEACQqrIK8OABUDAAAA.Boredasf:BAAANQADCgYIBgAAAA==.Boricuazo:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIEAAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQADCgMJAwALAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIJAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAQICgAIAH8YAA==.Bullteesta:BAAANQAECgIIAgAAAA==.Burkhard:BAAANQADCggIBwAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBQAAAA==.',
Ca='Caldec:BAACNQAFFIEQAAISAAUKFSHEAQDgAQASAAUKFSHEAQDgAQA1AAQKgSoAAhIACQqpJecDAIoDABIACQqpJecDAIoDAAAA.',
Ch='Chainizard:BAAANQAECgcIDAAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECgcIDAALAAAAAA==.Chaosofelune:BAAANQAECgIIAgAAAA==.Chaosoflife:BAAANQAECgIJAgAAAA==.Chaosoflight:BAAANQAECgUIBQAAAA==.Cheeno:BAABNQAECoEeAAMTAAcKZiQaDwDYAgATAAcKZiQaDwDYAgAUAAEKPSLYHwBfAAAAAA==.Chihiro:BAAANQAECgQIBAAAAA==.Chillyblinks:BAAANQAECgIIAgABNQAECgYIDAALAAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chloris:BAAANQADCgMIAwABNQAECgQIBQALAAAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Ci='Cinderheart:BAAANQABCgYIBgAAAA==.Ciymi:BAAANQAECgcICAABNQAECgkJHgAKAM8hAA==.',
Cl='Clarabelle:BAABNQAECoEeAAIKAAkKzyEeFQBvAwAKAAkKzyEeFQBvAwAAAA==.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwAAAA==.Computer:BAABNQAECoEjAAMDAAkK/yDPAwDlAgADAAgK/yLPAwDlAgABAAgKvB1CMQCJAgAAAA==.Cootin:BAAANQAECggICAAAAA==.',
Cp='Cpteddie:BAABNQAECoEeAAMVAAkKKx3CCQDEAgAVAAkKKx3CCQDEAgAWAAMKahGPAgGmAAABNQAFFAYIEgARAFoaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQALAAAAAA==.Crelam:BAACNQAFFIERAAIXAAUKDQieAQCHAQAXAAUKDQieAQCHAQA1AAQKgSkAAhcACQrYFoAKAJUCABcACQrYFoAKAJUCAAAA.Critherine:BAAANQAECgQIBQAAAA==.Cronatherus:BAAANQAECgEIAQAAAA==.Cruentis:BAABNQAECoEaAAIYAAgKgBWjBgA0AgAYAAgKgBWjBgA0AgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDwALAAAAAA==.Crysus:BAAANQAECgcIDwAAAA==.',
Da='Dabo:BAABNQAECoEYAAIPAAgKuB2IIQCLAgAPAAgKuB2IIQCLAgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJIQAQAMskAA==.Darwin:BAAANQAECgUICQAAAA==.Dasmoodhayn:BAAANQAECgIJAgAAAA==.Davalanch:BAABNQAECoEfAAIHAAkKWxl7KwCTAgAHAAkKWxl7KwCTAgAAAA==.Dazizejr:BAABNQAECoEoAAIRAAkKJCVCAwCtAwARAAkKJCVCAwCtAwAAAA==.',
De='Deathisbrew:BAAANQAECggICAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Denïed:BAAANQADCgYICgAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCgYICQAAAA==.',
Di='Dibstrum:BAAANQAECgQIBgAAAA==.Digduug:BAAANQAECgQICQAAAA==.Dixqt:BAAANQAECgQICwAAAA==.',
Do='Dogfight:BAACNQAFFIERAAQZAAYKsxGnBAB9AQAZAAUKSRKnBAB9AQASAAEKYQC1FwAuAAARAAEKxA6QJwAqAAA1AAQKgSUABBkACQoFHpwdAJQCABkACQp0HJwdAJQCABIAAgpHC9Z1AFkAABEAAQqND7GtAC8AAAAA.Doilookfatou:BAABNQAECoEVAAMaAAgKBR+xBgDAAgAaAAgKBR+xBgDAAgAPAAIKcATmhQBWAAAAAA==.',
Dr='Draxus:BAAANQAECgQICgAAAA==.Dresel:BAABNQAECoEXAAIbAAkKFxcULwCfAgAbAAkKFxcULwCfAgAAAA==.Drewpeebahlz:BAAANQAECgYICwABNQABCgIIAgALAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQADCggIDgAAAA==.Durto:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAABNQAECoEYAAMbAAgKnCG9LgChAgAbAAcKxCK9LgChAgAcAAQKWhiTOgAVAQAAAA==.Dynas:BAAANQAECgUICQAAAA==.',
Ea='Earthcake:BAABNQAECoEiAAMHAAkKoyA0EQBEAwAHAAkKoyA0EQBEAwAGAAMKIwfnywB6AAAAAA==.',
Ed='Eddielich:BAACNQAFFIESAAIRAAYKWhpJAwAXAgARAAYKWhpJAwAXAgA1AAQKgSQAAhEACQrZJPAFAIADABEACQrZJPAFAIADAAAA.',
Eh='Ehlo:BAAANQADCgEIAQAAAA==.',
El='Elasmon:BAAANQAECgcIEwAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQADCgcICgAAAA==.Ellan:BAAANQAECgcIBwAAAA==.',
Em='Emongalkar:BAAANQADCgQIBAAAAA==.',
Er='Erragal:BAAANQADCgcICgAAAA==.',
Es='Escanõr:BAAANQAECggIDwAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.Faustyne:BAAANQAECgcICwABNQAECgkJLwAbAB4kAA==.',
Fe='Felurián:BAAANQAECgMIBAABNQADCgYIEgALAAAAAA==.Fexli:BAAANQADCgcICgAAAA==.',
Fi='Fireteeth:BAAANQADCggIEwAAAA==.Fiverunner:BAAANQADCgQIBAAAAA==.',
Fl='Flurtty:BAAANQADCgYIDwAAAA==.',
Fo='Folklore:BAAANQAECgUIBgAAAA==.Forklift:BAAANQAECgIIAgABNQAECggIHQAdANcgAA==.',
Fr='Frigomortis:BAAANQAECgIIAgABNQAECgIIBAALAAAAAA==.Frozown:BAAANQAECgYIEwAAAA==.Fruits:BAAANQAECgUICgAAAA==.Fruitsack:BAAANQADCgcIBwABNQAECgUICgALAAAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgIJAgAAAA==.Furrylife:BAAANQAECgIIAgAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQALAAAAAA==.Fuzzychin:BAAANQAECgYIDAAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAABNQAECoEaAAIeAAgK1xJnBABTAgAeAAgK1xJnBABTAgABNQAFFAUIEQAXAA0IAA==.Gardettos:BAABNQAECoEdAAIdAAgK1yAACwDQAgAdAAgK1yAACwDQAgAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgQICAAAAA==.Ghostthunter:BAAANQADCgQJBAABNQAECggIEAALAAAAAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAAANQAECgYIDwABNQAFFAUIEQARANsNAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAEANQADCgIIAgABNQAECgkJHgAEAN4jAA==.Gnxrr:BAEBNQAECoEeAAIEAAkK3iNiBAB1AwAEAAkK3iNiBAB1AwAAAA==.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgUJCgAAAA==.',
Gr='Gregorz:BAAANQADCgcICgAAAA==.Greyanna:BAAANQAECgUIBgAAAA==.Gridon:BAAANQABCgUIBQAAAA==.Gripguy:BAAANQADCggICAABNQAECgQICAALAAAAAA==.Gromthrall:BAAANQAECgYICwAAAA==.',
Gw='Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQADCgcICgABNQAECgcIFwAbAJ8XAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFIEPAAIdAAUKQBjoBQC0AQAdAAUKQBjoBQC0AQA1AAQKgTEAAx0ACQq/IWoFAD0DAB0ACQq/IWoFAD0DAA4AAgrnEIQrAHcAAAAA.',
He='Hellhore:BAAANQAECgMICgAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECggIEAAAAA==.',
Ho='Holdenc:BAAANQAECgMIBQABNQAECgkJIwAGAJwbAA==.Hoodz:BAABNQAECoEeAAIQAAgKISPJIgAIAwAQAAgKISPJIgAIAwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgQIBgAAAA==.',
Hu='Huatli:BAAANQADCggJEgAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Ic='Icerod:BAAANQADCgUJBQABNQAECgUICgALAAAAAA==.',
Id='Idtrapdat:BAABNQAECoEjAAMbAAkKZyMBCwBkAwAbAAkKZyMBCwBkAwAcAAEKJQTKbQA0AAAAAA==.',
Il='Illyana:BAAANQAECggICgAAAA==.Ilse:BAABNQAECoEcAAIfAAkKSRoHGgDjAgAfAAkKSRoHGgDjAgAAAA==.',
Im='Imagined:BAACNQAFFIERAAMKAAUK4xBqEgCTAQAKAAUKvBBqEgCTAQAgAAIK/QcmBQCMAAA1AAQKgScAAgoACQpbHY9KAMgCAAoACQpbHY9KAMgCAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIDAAAAA==.Infidelic:BAAANQADCgYICwABNQAECgQIBgALAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAAANQAECgcIDgAAAA==.Ivannalot:BAAANQADCgYIEgAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgYICgAAAA==.Jarsham:BAAANQAECgIIBAAAAA==.Jaràdan:BAAANQAECgcJCAABNQAECgkJHgAKAPsTAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAABNQAECoEjAAIQAAkKXhs1OQCqAgAQAAkKXhs1OQCqAgAAAA==.',
Jo='Joran:BAAANQAECgIIBAAAAA==.Jordie:BAAANQADCgIIAgAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Jw='Jwrs:BAAANQAECgUICAAAAA==.',
['Jï']='Jïbril:BAABNQAECoEXAAIRAAgKpRj1LQAgAgARAAgKpRj1LQAgAgAAAA==.',
Ka='Kabbala:BAAANQAECgYIDgABNQAFFAUIEQAKAOMQAA==.Kahlani:BAABNQAECoEeAAIGAAgKFA+5WwCoAQAGAAgKFA+5WwCoAQAAAA==.Kahlua:BAAANQAECgMIAwAAAA==.Kailan:BAAANQAECgQICgABNQAECggIIQAJAAwgAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBQALAAAAAA==.Kaldro:BAAANQAECgUIBwAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAABNQAECoEYAAIhAAgKFg30EACUAQAhAAgKFg30EACUAQAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAABNQAECoEfAAMHAAgK1w58VADXAQAHAAgK1w58VADXAQAGAAgKyQSMgAA0AQAAAA==.Kathry:BAAANQADCgYIEgAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAABNQAECoEYAAIiAAgKxxIiHAD/AQAiAAgKxxIiHAD/AQAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keybricker:BAAANQAECgYIBgABNQAFFAQICgAIAH8YAA==.Keymebrah:BAABNQAECoEbAAMKAAkKvRGLkQAaAgAKAAkKWxGLkQAaAgAgAAMKnRHvIQCcAAAAAA==.',
Ki='Killeh:BAAANQADCggIDgAAAA==.',
Ko='Korda:BAAANQAECgEIAQAAAA==.Korinä:BAABNQAECoEaAAIjAAgKkQvxJwDnAQAjAAgKkQvxJwDnAQAAAA==.Kosh:BAAANQADCgcICgAAAA==.Koyra:BAACNQAFFIEMAAIOAAUKTSUjAQAdAgAOAAUKTSUjAQAdAgA1AAQKgScAAg4ACQofJSACAIQDAA4ACQofJSACAIQDAAAA.',
Kr='Kreyden:BAAANQADCgcICwAAAA==.Krump:BAAANQAECgEJAQAAAA==.',
Ku='Kubbles:BAAANQADCggICAAAAA==.Kubs:BAAANQADCgYIBgAAAA==.Kubwa:BAAANQABCgcIDwAAAA==.Kungfugimp:BAAANQAECgYIDgAAAA==.Kurral:BAACNQAFFIEQAAMPAAUKvxVvDQAqAQAPAAQKPRNvDQAqAQAiAAQK/ADeCADLAAA1AAQKgSUAAw8ACQrjHFMbAL4CAA8ACQrjHFMbAL4CACIABArrBOhDAKkAAAAA.Kurralium:BAAANQAECgcIEQABNQAFFAUIEAAPAL8VAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAAANQAECggIAgAAAA==.',
Ky='Kyramus:BAAANQAECgUICAAAAA==.',
La='Laconia:BAABNQAECoEZAAIOAAcKxhwkDgBEAgAOAAcKxhwkDgBEAgAAAA==.Lashstorm:BAAANQAECgEIAQAAAA==.Lattsatnar:BAAANQAECgQIBwAAAA==.',
Le='Lebron:BAAANQAECgYICgAAAA==.Lelesobi:BAAANQABCgQIBwAAAA==.Lennel:BAAANQAECgIIAwAAAA==.Lewd:BAAANQAECggIAgAAAA==.',
Lg='Lga:BAAANQADCgYIEAAAAA==.',
Li='Lilsnick:BAAANQAECgIIBAABNQAECgQIBgALAAAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.',
Ll='Llanthyl:BAAANQAECgUICQAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lucía:BAAANQAFFAEIAQABNQAECgkJJAAVAOIkAA==.Luecien:BAAANQADCgUJBQAAAA==.Lunafalia:BAABNQAECoEfAAIgAAgK9RgfBgBaAgAgAAgK9RgfBgBaAgAAAA==.Lupon:BAAANQAECggICAAAAA==.Lurosa:BAABNQAECoEmAAIiAAkKDyY3AAD1AwAiAAkKDyY3AAD1AwAAAA==.Luxeria:BAAANQAECgcIDQAAAA==.Luxray:BAAANQABCggIFQAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgYICwAAAA==.',
Ma='Macready:BAABNQAECoEmAAIMAAkKJiWeBwCWAgAMAAkKJiWeBwCWAgAAAA==.Magenin:BAAANQAECgIIAgAAAA==.Maggotgut:BAAANQAECgMIBAAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairbear:BAAANQAECgcIBwABNQAFFAUIEQARANsNAA==.Mairiachi:BAAANQAECgEIAQABNQAFFAUIEQARANsNAA==.Maltessa:BAAANQADCgUICgABNQAECggIIQAJAAwgAA==.Marload:BAACNQAFFIEIAAMbAAUKUAn/CgAkAQAbAAQKTgv/CgAkAQAcAAEKWQFAHgA0AAA1AAQKgSgAAxwACQpzGpceAB8CABsACApJHVNRAC0CABwACQpREZceAB8CAAAA.Mathy:BAAANQAECgcIDgAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgcIHgATAGYkAA==.',
Mi='Midletons:BAAANQAECgIIBAAAAA==.Minikub:BAAANQAECgUIEAAAAA==.Mixxy:BAAANQAECgQIBQABNQAFFAYIEQAEAKkXAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moobubble:BAAANQAECgYIBgABNQAECgkJIgAHAKMgAA==.Moodroo:BAAANQAECgIIAgAAAA==.Moonanoke:BAAANQAECgUJCwAAAA==.Moovoker:BAABNQAECoEfAAIdAAgKyyIUBwAYAwAdAAgKyyIUBwAYAwAAAA==.Morseques:BAABNQAECoEeAAMZAAgKniDpGgCpAgAZAAgKniDpGgCpAgARAAEKaCK8lwBjAAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAACNQAFFIEJAAMZAAUKfRtzBQBkAQAZAAQKTxtzBQBkAQARAAEKNRw7HgBTAAA1AAQKgSsAAxkACQpxJpEBANYDABkACQpxJpEBANYDABIAAwp5F3JYAMYAAAAA.',
Mx='Mxkebfistin:BAACNQAFFIERAAIEAAYKqReBAgAFAgAEAAYKqReBAgAFAgA1AAQKgSIAAgQACQppIaAKAP0CAAQACQppIaAKAP0CAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAYIEQAEAKkXAA==.',
Na='Narama:BAACNQAFFIENAAMBAAUK9QPIEQAAAQABAAQKCATIEQAAAQADAAIKngJ6DgCHAAA1AAQKgScABAEACQrUEz5IADcCAAEACQrGEj5IADcCAAMABgqODJggAFcBAAIAAQoADb4qACoAAAAA.',
Ne='Nekka:BAAANQAECgUICwAAAA==.Nethanos:BAAANQAECgMIBQABNQAECgUIBQALAAAAAA==.Neverrmore:BAAANQADCgUIBQAAAA==.',
Ni='Ninæ:BAACNQAFFIEIAAIdAAUKWg+fBwB/AQAdAAUKWg+fBwB/AQA1AAQKgR8AAh0ACQqlHQEHABoDAB0ACQqlHQEHABoDAAAA.Nitewïng:BAAANQAECgUICwABNQADCggIDQALAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgIIAwALAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAAANQAECgQIEgAAAA==.',
Ny='Nyoz:BAAANQAECgEIAQAAAA==.Nyxxadra:BAABNQAECoEdAAIBAAgK8AyvZQDWAQABAAgK8AyvZQDWAQAAAA==.',
Oa='Oakshion:BAAANQADCgcIBwAAAA==.',
Om='Omegadeed:BAABNQAECoEdAAIBAAgKjBSwSwArAgABAAgKjBSwSwArAgAAAA==.',
On='Onne:BAAANQADCgcIEgAAAA==.',
Or='Orcinus:BAABNQAECoEZAAIdAAkKEwf3HQCrAQAdAAkKEwf3HQCrAQAAAA==.Orcishfist:BAAANQAECgcIBwAAAA==.Orvar:BAAANQAECgQIBQABNQABCgIIAgALAAAAAA==.',
Pa='Pakaru:BAABNQAECoEVAAIWAAgKHxiOYQAdAgAWAAgKHxiOYQAdAgAAAA==.Pam:BAACNQAFFIEMAAINAAUKpBrJBAC2AQANAAUKpBrJBAC2AQA1AAQKgSQAAw0ACQr/JDQIAFMDAA0ACQr/JDQIAFMDABMAAgrTIetGALkAAAAA.Parathin:BAAANQADCggIFAAAAA==.',
Pe='Peorä:BAABNQAECoEaAAMIAAgKgAhGYwCQAQAIAAgKgAhGYwCQAQAJAAcK6AOfOgD8AAAAAA==.Perfectdark:BAACNQAFFIERAAITAAUKNCBqAwDoAQATAAUKNCBqAwDoAQA1AAQKgSkAAhMACQrcJPoDAIkDABMACQrcJPoDAIkDAAAA.Perse:BAAANQAECgQIBQAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgIIBAALAAAAAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCgMIAwABNQAECgIIAgALAAAAAA==.',
Pi='Pieper:BAABNQAECoEXAAIbAAcKnxdyXAAMAgAbAAcKnxdyXAAMAgAAAA==.Pipa:BAABNQAECoEjAAIGAAgKciQKDAA+AwAGAAgKciQKDAA+AwAAAA==.Pippit:BAAANQAECgcIEAABNQAECggIIwAGAHIkAA==.',
Pl='Plokane:BAABNQAECoEcAAMBAAcKoCFRagDIAQABAAUKHiFRagDIAQADAAIK5yIiOwDAAAAAAA==.',
Po='Poacher:BAAANQADCgMIBAAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgABNQAECgYICgALAAAAAA==.Powar:BAAANQAECgcIDAAAAA==.',
Pr='Provence:BAAANQADCgYICAAAAA==.',
Py='Pyreynna:BAAANQAECgQICAAAAA==.',
['Pè']='Pèppèr:BAAANQAECgcIEgABNQAECggIHgAMAEkXAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEIAQABNQAECgkJIwAGAJwbAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAAANQAECgQICgAAAA==.Rapsodia:BAAANQAECgQIBwABNQAECgkJHgAKAM8hAA==.Raschild:BAAANQAECgQIBwAAAA==.',
Re='Realfrojd:BAABNQAECoEkAAIRAAgKxAhVVgBUAQARAAgKxAhVVgBUAQAAAA==.Regginunchuk:BAABNQAECoEfAAIEAAgKiR4cDwC2AgAEAAgKiR4cDwC2AgAAAA==.Releronastus:BAAANQAECgEIAgAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECoEoAAMVAAkKRB1tCgC2AgAVAAgKxh5tCgC2AgAWAAgKcRT7fwDFAQAAAA==.Reyson:BAABNQAECoEeAAIKAAgKIgvzsQDTAQAKAAgKIgvzsQDTAQAAAA==.',
Rh='Rhunon:BAABNQAECoEtAAIRAAkKoBrJHgCGAgARAAkKoBrJHgCGAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rinchi:BAAANQADCgYIDAAAAA==.Rinthia:BAABNQAECoEhAAIJAAgKDCCQDQDlAgAJAAgKDCCQDQDlAgAAAA==.Ripyeet:BAABNQAECoEcAAIWAAgKFxogUQBRAgAWAAgKFxogUQBRAgAAAA==.',
Ro='Rol:BAAANQAECgMIBAAAAA==.Rolden:BAAANQADCggIHgAAAA==.',
Ru='Rukaji:BAAANQAECgUIDgAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIFQABNQADCgQIBQALAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAABNQAECoEYAAIQAAgKNRIobAABAgAQAAgKNRIobAABAgAAAA==.Samayel:BAAANQADCgYICAAAAA==.Sarkang:BAABNQAECoEbAAMZAAcKQBP2SgCDAQAZAAcKyA/2SgCDAQARAAMKIx6fZwAJAQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECggIHgAMAEkXAA==.',
Sc='Schmeebie:BAAANQAECgIJAgABNQAECgYICwALAAAAAA==.Schutze:BAABNQAECoEaAAIeAAkKhyQnAQBVAwAeAAkKhyQnAQBVAwAAAA==.',
Sd='Sdadfeg:BAABNQAECoEeAAIXAAgKviVBAgB7AwAXAAgKviVBAgB7AwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECggIGAAbAMEaAA==.Senco:BAAANQAECgIIAwAAAA==.Sephroth:BAAANQAECgEIAQABNQAECgIIAgALAAAAAA==.',
Sh='Shabobado:BAABNQAECoEZAAIKAAgKVBjxbABxAgAKAAgKVBjxbABxAgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAECgYJBgAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shuten:BAAANQAECgIIAgAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQADCggIDAAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Silverie:BAAANQAECgQIBAABNQAECggIIwAGAHIkAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinill:BAAANQADCgcIBwAAAA==.Sinterklaas:BAAANQAECgcIEQAAAA==.',
Sk='Skjald:BAAANQAECgMJAwABNQAFFAQICgAIAH8YAA==.Skylee:BAAANQAECgYJEAAAAA==.',
Sl='Slark:BAAANQAECgYIEgAAAA==.Slawth:BAAANQAECgYIEQAAAA==.Slayermonde:BAAANQADCgcIBwAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAAANQAECgcIEwAAAA==.Smeyplus:BAACNQAFFIENAAMWAAUKeyRuBgCTAQAWAAQKEiRuBgCTAQAVAAEKHybYCABvAAA1AAQKgSQAAxYACQrSJuMBAOsDABYACQqtJuMBAOsDABUAAQrVJmRHAHEAAAAA.',
Sn='Snaccident:BAAANQAECgYIBgAAAA==.Snickeris:BAAANQAECgQIBgAAAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgUICAAAAA==.Snurchbasher:BAAANQAECgUICwAAAA==.',
Sp='Sparrowhawk:BAAANQABCgQIBAAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECoEjAAIGAAkKnBuSIgClAgAGAAkKnBuSIgClAgAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMIBAAAAA==.',
St='Stars:BAAANQAECggIDwABNQAECgkJIwAbAGcjAA==.Stinkiepete:BAAANQAECgIIAgAAAA==.',
Su='Sureno:BAAANQAECgYIDgAAAA==.',
Sw='Swaglordxtqt:BAAANQAECgMIAgAAAA==.',
Sx='Sxyhealz:BAAANQAECgQIBAAAAA==.Sxyheålz:BAABNQAECoEnAAIIAAkKjxfbIAC0AgAIAAkKjxfbIAC0AgAAAA==.',
Ta='Taliä:BAAANQADCgUJBQAAAA==.Tanndari:BAAANQADCgcIFwAAAA==.Tartare:BAAANQAECgYICgAAAA==.Tashaman:BAACNQAFFIEJAAMGAAUKowxkCAB6AQAGAAUKowxkCAB6AQAHAAEKBwFBJwAzAAA1AAQKgTIAAwYACQqgFAI/ABkCAAYACQqgFAI/ABkCAAcABQqaBR2oAO0AAAAA.',
Te='Teajuan:BAAANQADCgcIBwAAAA==.Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggIDwAAAA==.Teriheals:BAAANQAECgIJAwAAAA==.',
Th='Thejorlane:BAAANQADCgYIEgAAAA==.Thiccholy:BAACNQAFFIEHAAMfAAQKGQy5CwA2AQAfAAQKGQy5CwA2AQAVAAIKfwJUCgBTAAA1AAQKgSQABB8ACQqyFls8ADMCAB8ACAqQFVs8ADMCABUACQqcDfIcAKgBABYABAohDE/2AL4AAAAA.Thiccshields:BAAANQADCgQIBAABNQAFFAQIBwAfABkMAA==.Thicctotemz:BAAANQAECgUICwABNQAFFAQIBwAfABkMAA==.Thogo:BAABNQAECoEfAAIkAAgK0h6fAwDNAgAkAAgK0h6fAwDNAgAAAA==.',
Ti='Tikaa:BAAANQAECgEIAQAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECoEkAAIVAAkK4iQiAwBzAwAVAAkK4iQiAwBzAwAAAA==.Tomerto:BAABNQAECoEdAAMfAAgKwhbcPAAxAgAfAAgKwhbcPAAxAgAWAAUKogob2gDzAAAAAA==.Toobeastly:BAABNQAECoEbAAQHAAkK9xweKACmAgAHAAcKbiEeKACmAgAXAAIKVw0QJACSAAAGAAEKRhUd7QAyAAAAAA==.Toonerdin:BAAANQAECgUICQAAAA==.Toymonkey:BAAANQADCggICAAAAA==.',
Tr='Tril:BAAANQAECgIJAwAAAA==.Trolazo:BAAANQADCgIIAgAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAAANQAECgYIDAABNQAECggIBwALAAAAAA==.Tryingmybest:BAACNQAFFIEKAAIIAAQKfxijDABmAQAIAAQKfxijDABmAQA1AAQKgSQABAgACQqNJJgEAI4DAAgACQqNJJgEAI4DACUABwpeGlAFAB0CAAkAAQrVCJ5pACYAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCgIIAgABNQAECgIIAgALAAAAAA==.',
Ty='Tydrodh:BAAANQAECggIBwAAAQ==.Tydroshaman:BAAANQADCgUIBQAAAA==.Tyestaumin:BAAANQADCgcIBwABNQAECgEIAgALAAAAAA==.Tyralen:BAABNQAECoEfAAIbAAgKrhckPgBpAgAbAAgKrhckPgBpAgAAAA==.Tyrandras:BAABNQAECoEYAAIaAAgKRRF3EgC1AQAaAAgKRRF3EgC1AQABNQAECggIHwAbAK4XAA==.Tyronnius:BAAANQAECgMJBAAAAA==.Tyrïon:BAABNQAECoEnAAIQAAgK+SPyHgAaAwAQAAgK+SPyHgAaAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBQAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAQICgAIAH8YAA==.',
Va='Vaero:BAAANQAECgcIEQAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgEIAQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAFFAUICAAOAN0KAA==.Velyssa:BAAANQAECgUICQAAAA==.',
Vi='Vibin:BAABNQAECoEdAAIdAAgKExwdDwCKAgAdAAgKExwdDwCKAgAAAA==.Vineeshewah:BAAANQAECgUICQAAAA==.',
Vo='Voidguy:BAAANQAECgQICAAAAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQAECgUICAABNQAECgkJIwAGAJwbAA==.',
Wh='Whalend:BAAANQADCgYIBgAAAA==.Whatapal:BAAANQAECgIIBAAAAA==.',
Wi='Wilbo:BAABNQAECoEVAAIHAAkK9BNtPAA7AgAHAAkK9BNtPAA7AgABNQAFFAYIEQAZALMRAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAAANQAECgQICgAAAA==.',
Wo='Wolfdrudu:BAAANQAECgUICQAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgIIAwAAAA==.Wormszer:BAAANQAECgEIAgAAAA==.Wotan:BAAANQADCgIJAgAAAA==.Woth:BAAANQADCggIDgAAAA==.',
Wr='Wrâîth:BAAANQADCgYICwABNQAECgIIBAALAAAAAA==.',
Wy='Wynds:BAACNQAFFIEOAAIdAAUK6SXeAgAwAgAdAAUK6SXeAgAwAgA1AAQKgS4AAh0ACQr4JgcAABcEAB0ACQr4JgcAABcEAAAA.Wyngs:BAAANQAECgYIDAABNQAFFAUIDgAdAOklAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAABNQAECoEYAAIdAAgKmg3pGwDIAQAdAAgKmg3pGwDIAQAAAA==.Xiaozhi:BAEANQAECgUICQAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgQIBwAAAA==.',
Yo='Yoirr:BAAANQAECgMIBgAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECgYICwALAAAAAA==.Zanori:BAABNQAECoEbAAQSAAgKzw31MwChAQASAAgKzw31MwChAQAZAAUKLga8eADJAAARAAEKbhFgrQAwAAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECggIGwASAM8NAA==.',
Ze='Zellyne:BAAANQAECgQJBAABNQAFFAUICAAdAFoPAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAABNQAECoEvAAIbAAkKHiSBDABYAwAbAAkKHiSBDABYAwAAAA==.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQAECgIIAgAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Êv']='Êvelyn:BAAANQADCggIFAAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQALAAAAAA==.',
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
