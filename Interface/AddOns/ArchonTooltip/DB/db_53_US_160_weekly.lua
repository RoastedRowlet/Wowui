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

local lookup = {'Druid-Restoration','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Paladin-Holy','Druid-Balance','Warrior-Arms','Shaman-Enhancement','Unknown-Unknown','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Priest-Discipline','Warlock-Destruction','Paladin-Protection','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Druid-Feral','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Warrior-Protection','Hunter-Survival','DemonHunter-Havoc','Evoker-Augmentation','Warrior-Fury','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adjust:BAAANQAECgcIEgABNQAFFAYIFwABABYcAA==.Admirlakbar:BAAANQADCgIIAgAAAA==.',
Ae='Aedrenis:BAAANQADCgUIDgAAAA==.Aegrisomnia:BAAANQABCgMIAwABNQAECgkJIgACAGkfAA==.Aejra:BAAANQAECgQIBAABNQAECgkJIgACAGkfAA==.Aenstus:BAAANQADCgMJAwAAAA==.Aeropunk:BAAANQADCgIJAgAAAA==.Aerys:BAAANQAECgcIEwAAAA==.Aerøs:BAAANQAECgcIDwAAAA==.',
Ag='Aggiz:BAAANQAECgQIBAABNQAECggIIgADAFUfAA==.',
Aj='Ajaxprime:BAABNQAECoEjAAMEAAgK/CVdFAD/AgAEAAgK/CVdFAD/AgAFAAEK6whQlgAwAAAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alfabika:BAAANQAECgUIBgAAAA==.Alzim:BAAANQAECgcIEgAAAA==.',
Am='Amoriara:BAAANQADCgUIDAAAAA==.',
An='Angry:BAAANQAECgUIDAAAAA==.Ankelbiter:BAAANQAECggIEwAAAA==.Anûbis:BAAANQAECgYIEAAAAA==.',
Ar='Aragos:BAAANQAECgYIDAAAAA==.Arcelon:BAAANQAECgEIAgAAAA==.Arwenatak:BAABNQAECoEjAAMGAAgKbB99OgDDAgAGAAgKbB99OgDDAgAHAAQK/w2ZsgDuAAAAAA==.',
As='Asgardian:BAAANQAECgMIBQAAAA==.Asmoon:BAABNQAFFIERAAIIAAUKKx8sCADNAQAIAAUKKx8sCADNAQAAAA==.',
At='Athren:BAAANQAECgYIEAAAAA==.Athrogate:BAABNQAECoEcAAIJAAcKmxewegAGAgAJAAcKmxewegAGAgAAAA==.',
Au='Auraloxious:BAAANQAECgMIAwAAAA==.',
Az='Azmun:BAAANQAECgQIBAABNQAFFAUIEQAIACsfAA==.Azmunn:BAAANQAECgMIAwABNQAFFAUIEQAIACsfAA==.',
Ba='Baelzadru:BAAANQAECgUICQAAAA==.Baelzheron:BAAANQAECgQIBgAAAA==.Baksylyk:BAAANQAECgMIBAABNQAECggIGgAGAL4gAA==.Ballador:BAAANQAECgYICgAAAA==.Barakas:BAAANQADCgUIBQAAAA==.Barakoshamma:BAABNQAECoEnAAIKAAgKCiUNBABPAwAKAAgKCiUNBABPAwAAAA==.Barazudar:BAABNQAECoEeAAIHAAcKpRJSbACsAQAHAAcKpRJSbACsAQAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECgYIDwALAAAAAA==.Barrageobama:BAAANQADCgUIBQAAAA==.Barreta:BAABNQAECoEXAAIDAAgK7gwQhwDNAQADAAgK7gwQhwDNAQAAAA==.',
Be='Beck:BAABNQAECoEfAAMCAAgKDQTQkQAtAQACAAgKDQTQkQAtAQAMAAYKIAKP0gC9AAAAAA==.Beefykin:BAAANQAECgYIDgAAAA==.Bellamuerté:BAAANQAECgQIBAABNQAECgcIHAANACgYAA==.Bellámuerté:BAABNQAECoEcAAINAAcKKBirZgACAgANAAcKKBirZgACAgAAAA==.Bemmy:BAAANQAECgQICAABNQAECgkJIgACAGkfAA==.',
Bi='Bigdrandyy:BAABNQAECoEWAAMCAAYKsiFGPwA5AgACAAYKsiFGPwA5AgAMAAUK4wn4rwAEAQAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAABNQAECoEkAAIOAAkKyCGqBQBxAwAOAAkKyCGqBQBxAwAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgYIEwAAAA==.Bloodreina:BAAANQAECgYIEAABNQAECggIDwALAAAAAA==.',
Bo='Bob:BAAANQAECgUIDAAAAA==.Bobtheknob:BAAANQADCggIGwAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.Bootyhunting:BAAANQAECgIIAgAAAA==.',
Br='Brahm:BAAANQAECgQIBwABNQAECggIIQAMABUaAA==.Brdua:BAAANQADCgYIBgAAAA==.Breadnbudda:BAAANQADCgcIHAAAAA==.Brideofloco:BAAANQABCgEIAQAAAA==.Brogar:BAAANQADCgcJGAAAAA==.',
Bu='Bubblekush:BAAANQAECgcIDgABNQAFFAYIEAAPAAsaAA==.Buffknight:BAAANQAECgMIAwABNQAECggIIQAMABUaAA==.Bulkam:BAAANQAECgYIEAAAAA==.Bulkazarr:BAABNQAECoEZAAICAAcK4x00QAA1AgACAAcK4x00QAA1AgAAAA==.Burbuja:BAAANQADCggJCAABNQAECggIIgAQAGIkAA==.',
['Bí']='Bíssell:BAAANQAECgcIBwAAAA==.',
['Bù']='Bùllrùsh:BAAANQABCgEIAQAAAA==.',
Ca='Callabash:BAABNQAECoElAAMCAAkKyxsRIwC8AgACAAkKyxsRIwC8AgAMAAUK/wfluQDwAAAAAA==.',
Ce='Celarena:BAAANQAECgYIEQAAAA==.Cermit:BAAANQAECgEIAQAAAA==.',
Ch='Cheefkdavi:BAAANQAECgEIAgABNQAECgkJFwARAF4iAA==.Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYJBwAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAABNQAECoEXAAIGAAYKnhvIlQDDAQAGAAYKnhvIlQDDAQAAAA==.Chzpriest:BAABNQAECoEaAAQPAAgKByAmEwCzAgAPAAcKCSAmEwCzAgAQAAgKrhQlSAAnAgASAAEK8gqIJQA0AAAAAA==.',
Ci='Cichorì:BAACNQAFFIEQAAMNAAQKuhsEEwAzAQANAAMKsCMEEwAzAQATAAIKMhHVDACfAAA1AAQKgScAAxMACQojJJcGAJgCAA0ABwonJXYmANICABMACQqyG5cGAJgCAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQAECgEIAQAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cp='Cptvoker:BAAANQADCgIIAgAAAA==.',
Cr='Creckko:BAAANQADCgMIBAAAAA==.Crockito:BAACNQAFFIEdAAIMAAcKLiNjAAD+AgAMAAcKLiNjAAD+AgA1AAQKgSMAAwwACQrxJokAAAAEAAwACQrxJokAAAAEAAIAAQpXDvwKASkAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQIBAAAAA==.Danto:BAAANQAECgYICQABNQAECggIIQAMABUaAA==.Darc:BAAANQADCggIGQAAAA==.Darktroll:BAABNQAECoElAAIDAAkK0xPMRQB0AgADAAkK0xPMRQB0AgAAAA==.',
De='Depoprovera:BAABNQAECoEmAAIUAAkKaxMGGQACAgAUAAkKaxMGGQACAgAAAA==.Deqz:BAABNQAECoEfAAMVAAkKjBnoHgA7AgAVAAgK4BjoHgA7AgADAAEK7h47IwFbAAAAAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECgYICQALAAAAAA==.Dilox:BAAANQAECgMIAwAAAA==.Dinosaur:BAABNQAECoEjAAMWAAgKZBrpFgAyAgAWAAgKZBrpFgAyAgAXAAYKgBirFwCuAQABNQAECgkJHwAHAN4dAA==.Dirtydee:BAABNQAECoEjAAIRAAgK3gquVgB2AQARAAgK3gquVgB2AQAAAA==.Disaaya:BAABNQAECoEeAAIDAAgK2g74bAAMAgADAAgK2g74bAAMAgAAAA==.Divinecheeks:BAAANQAECgIIBgAAAA==.',
Dj='Djangó:BAAANQAECgMIBAAAAA==.',
Do='Donto:BAAANQAECgUICAABNQAECggIIQAMABUaAA==.Dontos:BAAANQAECgQICgABNQAECggIIQAMABUaAA==.Doodlebug:BAACNQAFFIENAAIRAAUKnBRQCwB0AQARAAUKnBRQCwB0AQA1AAQKgSsAAhEACQryHWoTAPsCABEACQryHWoTAPsCAAAA.Dooshrocket:BAAANQAECgQIBgAAAA==.Dotsntaxes:BAACNQAFFIEPAAQNAAUKwAlDHgDYAAANAAMKIQ5DHgDYAAATAAIK3gILEQBvAAAYAAEK8wDaEAAoAAA1AAQKgSUABBMACQo/Gu0jAEgBAA0ACAp0F35YACwCABMABQrHEu0jAEgBABgAAQqNFSskAEkAAAAA.',
Dr='Dracom:BAAANQAECgIIAwAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAYIFQAQACQaAA==.Dralioli:BAABNQAECoEWAAIHAAcKHRLLaQCzAQAHAAcKHRLLaQCzAQAAAA==.Dreanil:BAABNQAECoEbAAICAAgK6Q4FcACMAQACAAgK6Q4FcACMAQAAAA==.Droho:BAABNQAECoEgAAIXAAgKVCSIBABBAwAXAAgKVCSIBABBAwABNQAFFAcIGAAMAFgbAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQALAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAYIFwABABYcAA==.',
Dz='Dzievana:BAAANQAECgEIAQAAAA==.',
['Dâ']='Dârn:BAABNQAECoEjAAMNAAgKtCA/LAC7AgANAAgKtCA/LAC7AgATAAEKASBCZQBMAAAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgYIDwALAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQAECgYICgAAAA==.',
Eo='Eostre:BAABNQAECoEiAAMQAAgKYiTuDwAyAwAQAAgKCCTuDwAyAwASAAMKfR4zEAAPAQAAAA==.',
Eu='Eupherine:BAABNQAECoEfAAIQAAgKnSKgFgAIAwAQAAgKnSKgFgAIAwAAAA==.',
Ev='Evillarry:BAAANQADCgYIDAAAAA==.Evilpaladin:BAABNQAECoEpAAIUAAkKjBmdDwB9AgAUAAkKjBmdDwB9AgAAAA==.Evilrico:BAAANQAECgEIAQAAAA==.',
Ez='Ezluz:BAABNQAECoEYAAMRAAcKnhpgOQAAAgARAAcKnhpgOQAAAgAEAAEKXhK1xgA7AAAAAA==.',
Fa='Facsimile:BAABNQAECoEjAAIPAAgKHxdzGwBIAgAPAAgKHxdzGwBIAgAAAA==.',
Fe='Festers:BAABNQAECoEXAAMZAAkKlRbWJAA1AgAZAAgKIxfWJAA1AgAaAAQKpRByMQAQAQAAAA==.',
Fi='Fingerwalk:BAABNQAECoEhAAIbAAcKkRQXEADHAQAbAAcKkRQXEADHAQAAAA==.',
Fl='Flappi:BAABNQAECoEiAAIPAAgKhh9wEADWAgAPAAgKhh9wEADWAgAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAABNQAECoEdAAIIAAgKshcELgBJAgAIAAgKshcELgBJAgAAAA==.',
Fo='Fosho:BAACNQAFFIEYAAIMAAcKWBtIAQCqAgAMAAcKWBtIAQCqAgA1AAQKgR0AAgwACQowJAQQAFsDAAwACQowJAQQAFsDAAAA.',
Fr='Franch:BAAANQAECgYIEQAAAA==.Frank:BAAANQAECgEIAQABNQAECgYIDQALAAAAAA==.Fraud:BAAANQAECgcIDgABNQAECggIDwALAAAAAA==.Freelvlsvnty:BAAANQADCgYIBwAAAA==.Froddy:BAAANQAECgYIDgAAAA==.Frostybox:BAAANQAECgQIBAAAAA==.Frylockk:BAABNQAECoEjAAQYAAkKXSKmAACEAwAYAAkKXSKmAACEAwANAAYKlBx+hACtAQATAAEKQB15ZQBMAAAAAA==.',
Fu='Furrykane:BAEBNQAECoEcAAQIAAgKDhlfNQAWAgAIAAgK+hdfNQAWAgAcAAEKyRfnMABKAAABAAEKHgjhZAA8AAAAAA==.Future:BAABNQAECoEmAAIKAAgKfhROEABIAgAKAAgKfhROEABIAgAAAA==.',
Ga='Gaara:BAAANQAECgYIDwAAAA==.Gamepunisher:BAABNQAECoEgAAMdAAgKRx0oCgD4AQAeAAgKOBb/kgA+AgAdAAcKMh8oCgD4AQAAAA==.Gares:BAAANQAECgcIDQAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgMIAwABNQAECgMIAwALAAAAAA==.Goham:BAABNQAECoEiAAICAAkKaR98FAAPAwACAAkKaR98FAAPAwAAAA==.Goobe:BAAANQAECgQIBAABNQAECggIIgADAFUfAA==.Goontotem:BAAANQAECgEIAQABNQAECgUIBgALAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grimkai:BAAANQABCgMIAwAAAA==.Grogon:BAAANQAECgUICwAAAA==.Gromlo:BAABNQAECoEdAAIBAAgK2iH4CwDxAgABAAgK2iH4CwDxAgAAAA==.Grulog:BAAANQAECgQICgAAAA==.',
Gu='Guldav:BAAANQADCgMIAwAAAA==.Gunny:BAABNQAECoEjAAMDAAgKRiKMHgACAwADAAgKRiKMHgACAwAVAAIKKRLRZABxAAAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
['Gö']='Göld:BAAANQAECgUIBQAAAA==.',
Ha='Haeliman:BAAANQADCggICwAAAA==.Haileigh:BAAANQAECgMIBgAAAA==.Harleigh:BAAANQABCgMIAgAAAA==.Havöc:BAABNQAECoEhAAIJAAgKVhy+XQBWAgAJAAgKVhy+XQBWAgAAAA==.',
He='Herpenderper:BAAANQAECgMIAwAAAA==.',
Hi='Hikawa:BAABNQAECoEtAAIeAAgKeyX8GgBiAwAeAAgKeyX8GgBiAwAAAA==.Hippocratic:BAABNQAECoEZAAMCAAgKsRP6SwAHAgACAAgKsRP6SwAHAgAMAAcK0xgRVQD4AQAAAA==.',
Ho='Homunculous:BAAANQAECgIIAgAAAA==.Honortheox:BAAANQADCgEIAQABNQAECgMIAwALAAAAAA==.',
Hu='Huntemall:BAAANQAECgYIEAAAAA==.',
Hy='Hysteriix:BAEBNQAECoE1AAIfAAkKOSX1AADBAwAfAAkKOSX1AADBAwAAAA==.',
Ic='Iceborn:BAAANQAECggIAQAAAA==.Iceshards:BAABNQAECoEgAAIdAAcKZRMSDQCvAQAdAAcKZRMSDQCvAQAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQAECgQIBgAAAA==.',
Il='Illidankior:BAACNQAFFIEGAAIgAAMKaRddAwDjAAAgAAMKaRddAwDjAAA1AAQKgR0AAiAACQpPHm0GAN4CACAACQpPHm0GAN4CAAAA.Illirothas:BAAANQAECgUIBQABNQAECgkJIwADAHkZAA==.',
Im='Imen:BAAANQAECgcIEAAAAA==.Imsassy:BAAANQAECgUICQAAAA==.',
In='Infect:BAAANQADCgIIAgABNQAECgYICAALAAAAAA==.Infectedbøb:BAAANQAECgQICgAAAA==.Inmortuae:BAAANQAECgQIBAABNQAECgkJIwADAHkZAA==.Instågram:BAAANQAECgMIBQAAAA==.',
Io='Iornbane:BAAANQAECgUIDQAAAA==.',
Ir='Irissela:BAAANQAECgYICwAAAA==.',
Is='Ispitmagic:BAAANQAECgYIBwAAAA==.',
Iv='Ivalice:BAABNQAECoEYAAQDAAkKyxciYAAtAgADAAcKLxoiYAAtAgAVAAUKYwc9SADoAAAhAAIK3BfgDQCTAAAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECggIGgAGAL4gAA==.',
Ja='Jafbe:BAAANQAECgUIDgAAAA==.Jaghatai:BAAANQAECgUIBwAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jigsaw:BAAANQADCgIIAgAAAA==.Jimcarrey:BAAANQAECgIIAwABNQAECggIGwADAN4IAA==.Jimmyc:BAAANQAECgUICgABNQAECggIGwADAN4IAA==.Jimmysi:BAABNQAECoEbAAIDAAgK3gjtiwDBAQADAAgK3gjtiwDBAQAAAA==.',
Jo='Joemauma:BAABNQAECoEaAAIdAAcK6RmkCAAkAgAdAAcK6RmkCAAkAgAAAA==.',
Jp='Jpam:BAACNQAFFIEGAAMdAAMKIw9jBgCYAAAdAAIK4g5jBgCYAAAeAAEKpQ+DTQBRAAA1AAQKgR8AAh4ACQpiGg1vAIoCAB4ACQpiGg1vAIoCAAAA.',
Ju='Judges:BAAANQAECggICAAAAA==.Jumbosize:BAACNQAFFIEXAAIBAAYKFhxdAgAXAgABAAYKFhxdAgAXAgA1AAQKgSoAAgEACQqPJSICAKQDAAEACQqPJSICAKQDAAAA.Jupîter:BAAANQAECgEIAQABNQAECgEIAgALAAAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgALAAAAAA==.',
Ka='Kaerlif:BAAANQAECgcIDAABNQAFFAQICAAiAD0SAA==.Kaiyley:BAAANQAECgcIDAAAAA==.Kalastrian:BAABNQAECoEZAAIOAAcKVySxDwDkAgAOAAcKVySxDwDkAgAAAA==.Karatepally:BAAANQADCgIIAgAAAA==.Karateshock:BAABNQAECoEfAAMCAAgKpRJpWwDPAQACAAgKpRJpWwDPAQAMAAEKmgWkGgEwAAAAAA==.Kargo:BAAANQAECgYICwAAAA==.Karlmarks:BAAANQABCggIDAAAAA==.Kazuren:BAABNQAECoEeAAIXAAgKbwtJFwC1AQAXAAgKbwtJFwC1AQAAAA==.',
Ke='Keano:BAABNQAECoEaAAMHAAcKVw8LjQBMAQAHAAYKRwwLjQBMAQAGAAQK6xki7QAIAQAAAA==.Keeldemall:BAAANQAECgYICwAAAA==.Kelia:BAAANQADCgMIAwABNQAECgkJIwADAHkZAA==.Kelinna:BAAANQAECgcIEAAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kilron:BAAANQABCgMIAgAAAA==.Kirin:BAAANQAECgYIEwAAAA==.',
Kl='Klaye:BAAANQAECgYICgABNQAECggIIQAMABUaAA==.',
Kn='Knatknom:BAAANQAECgIIAgAAAA==.',
Ko='Kodabonk:BAABNQAECoEjAAIbAAgKbB6xBwCgAgAbAAgKbB6xBwCgAgAAAA==.Kodanorth:BAAANQAECgEJAQABNQAECggIIwAbAGweAA==.Korthos:BAAANQAECgYIEQAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAABNQAECoEjAAIDAAkKeRlZLADHAgADAAkKeRlZLADHAgAAAA==.',
['Kì']='Kìngpin:BAABNQAECoEfAAIDAAkKcxWwVABKAgADAAkKcxWwVABKAgAAAA==.',
La='Laarry:BAAANQADCgUIBQABNQAECgkJHgAHAIIZAA==.Lammp:BAABNQAECoEjAAMCAAkKqBvuNwBYAgACAAcKhh3uNwBYAgAMAAgKVBaQTAAYAgAAAA==.Lamppally:BAAANQADCgQIBAABNQAECgkJIwACAKgbAA==.Lampshade:BAAANQADCggICAABNQAECgkJIwACAKgbAA==.Laws:BAABNQAECoEnAAIFAAkKWRFvNADNAQAFAAkKWRFvNADNAQAAAA==.Lazydragon:BAABNQAECoEbAAMjAAcKSw4iDQBRAQAjAAcKIg0iDQBRAQAXAAYKcAg9IgAZAQAAAA==.',
Li='Liaeda:BAABNQAECoEkAAMhAAgKcA6SBgAAAgAhAAgKcA6SBgAAAgADAAQKEQtr8wDoAAAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgQICQAAAA==.Lingbane:BAAANQAECgEIAQABNQAECgkJIwAYAF0iAA==.Litchslapped:BAAANQADCgcIBwAAAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAcIGAAMAFgbAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECgkJJwAFAFkRAA==.Lovely:BAAANQAECgUIDAAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECoEeAAIEAAgKsSJ5JQCJAgAEAAgKsSJ5JQCJAgABNQAFFAIIAwALAAAAAA==.',
Lw='Lwaxana:BAAANQAECgIIAwAAAA==.',
Ma='Maceon:BAAANQADCgcIBwAAAA==.Makloy:BAAANQABCgYICAAAAA==.Makuahwe:BAAANQADCggICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECggIIwAPAB8XAA==.Malgrendin:BAABNQAECoEfAAIDAAgKFSR8FgApAwADAAgKFSR8FgApAwAAAA==.Malty:BAABNQAECoEaAAIJAAgK2Rw4XgBVAgAJAAgK2Rw4XgBVAgAAAA==.Malédictias:BAAANQAECgQIBgAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manatreat:BAAANQAECgEIAQABNQAECgkJIwADAHkZAA==.Manuall:BAAANQAECgQICQAAAA==.Marbas:BAABNQAECoEeAAIEAAgK5xuALwBPAgAEAAgK5xuALwBPAgAAAA==.Maxidk:BAABNQAECoEoAAIRAAgK2CP/DQAvAwARAAgK2CP/DQAvAwAAAA==.Maximage:BAAANQAECgQICAABNQAECggIKAARANgjAA==.Maximonk:BAAANQADCgQIBgABNQAECggIKAARANgjAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Meditare:BAAANQABCgIIAgAAAA==.Medîvh:BAAANQAECgYIDwAAAA==.',
Mi='Midgemaisel:BAAANQAECgQICAAAAA==.Mik:BAAANQABCgMIAgABNQADCgYJBgALAAAAAA==.Mikhael:BAAANQADCgEIAQABNQADCgYJBgALAAAAAA==.Mirado:BAABNQAECoEdAAIkAAgKxx5RBQClAgAkAAgKxx5RBQClAgAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAABNQAECoEdAAITAAgKmgndGwCGAQATAAgKmgndGwCGAQAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAABNQAECoEfAAMEAAgKyRQaegAJAQAEAAUKtA8aegAJAQARAAgKyRQidAAAAQAAAA==.Monkragga:BAAANQAECgYIDwAAAA==.Mooseleroy:BAAANQAECgUIEAAAAA==.Mortarien:BAABNQAECoEYAAMEAAcKhRy5SgDDAQAEAAYK+Bu5SgDDAQAFAAUKpBomQwBxAQAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAAGAMMfAA==.',
Mu='Mugged:BAABNQAECoEXAAIeAAgKqgv+ywDJAQAeAAgKqgv+ywDJAQAAAA==.',
My='Myrtle:BAABNQAECoEeAAIlAAcKrBFkDwCPAQAlAAcKrBFkDwCPAQAAAA==.',
['Má']='Másóchist:BAABNQAECoEgAAMNAAkKhh5ZNACeAgANAAgKfh1ZNACeAgATAAIKxSDMPwC5AAAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.Nevernude:BAAANQAECgQIBAABNQAECgkJIgACAGkfAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Nikna:BAAANQADCgIIAgAAAA==.Niwatori:BAABNQAECoEcAAIIAAgK6R9ZGQDiAgAIAAgK6R9ZGQDiAgAAAA==.',
No='Noah:BAACNQAFFIEcAAMhAAcKlhwfAABrAgAhAAYKRh4fAABrAgAVAAQK+A4jDwAfAQA1AAQKgSMAAyEACQodJgQBAHMDACEACQodJgQBAHMDABUAAgrJFAthAHwAAAAA.Nol:BAAANQAECggICgABNQAFFAcIHgAZAPEhAA==.Nolarz:BAACNQAFFIEeAAIZAAcK8SGOAADKAgAZAAcK8SGOAADKAgA1AAQKgSgAAhkACQpNJqsCAKQDABkACQpNJqsCAKQDAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAABNQAECoEgAAIPAAgKthwuFgCIAgAPAAgKthwuFgCIAgAAAA==.Nyst:BAABNQAECoEdAAIeAAgKexIFqQAPAgAeAAgKexIFqQAPAgAAAA==.',
Ob='Objekt:BAAANQAECgYICAAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAABNQAECoEZAAMNAAkKjyD9JwDMAgANAAgKpSD9JwDMAgATAAMKnh6RMQD1AAABNQADCgMIAwALAAAAAA==.Ojpyroblast:BAAANQADCgMIAwAAAA==.',
Ol='Olga:BAAANQAECgIIBQAAAA==.Olma:BAABNQAECoEWAAIJAAYKBg+zuwBWAQAJAAYKBg+zuwBWAQABNQAFFAYIFQAQACQaAA==.',
Om='Omghunter:BAAANQADCgYIBgAAAA==.',
On='Onisprite:BAAANQAECgMIBAAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAABNQAECoEaAAMGAAgKviBNMgDiAgAGAAgKviBNMgDiAgAUAAEK1RYgXgA/AAAAAA==.',
Os='Osanna:BAAANQADCggJFQAAAA==.',
Pa='Paladout:BAABNQAECoEjAAIGAAgKmB+MSgCOAgAGAAgKmB+MSgCOAgAAAA==.Palagouge:BAAANQAECgEIAQAAAA==.Palletjack:BAABNQAECoEnAAIRAAgKOCbNBwBxAwARAAgKOCbNBwBxAwAAAA==.Palli:BAAANQADCgcIFAAAAA==.Paona:BAABNQAECoEcAAIIAAgKyQhjTgB8AQAIAAgKyQhjTgB8AQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paperpuppy:BAAANQADCgEIAQABNQAECgYIEwALAAAAAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.Pewpewkuchoo:BAAANQADCgEIAQAAAA==.',
Ph='Phenphen:BAABNQAECoElAAMZAAkK1iHpBwBBAwAZAAgKniPpBwBBAwAaAAUK2BL8LAA8AQAAAA==.Physicyan:BAAANQAECgYIDgAAAA==.',
Pi='Pipez:BAAANQAECgYIDgAAAA==.',
Pl='Planetdru:BAABNQAECoEgAAIIAAgKYx8BIACvAgAIAAgKYx8BIACvAgAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAABNQAECoEaAAIEAAcKcgjgbAA7AQAEAAcKcgjgbAA7AQAAAA==.Popshampain:BAAANQAECgUIEwAAAA==.',
Ps='Psychonight:BAABNQAECoEkAAISAAkKpBq/AgDOAgASAAkKpBq/AgDOAgAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
['Pì']='Pìp:BAAANQADCgYJBgAAAA==.',
Ra='Raenlling:BAAANQAFFAIIAwAAAA==.Ratscum:BAEANQADCggIGAAAAA==.Rayssa:BAABNQAECoEoAAMSAAgKpSMZAQBEAwASAAgKpSMZAQBEAwAQAAEKVRuX1gBSAAAAAA==.',
Re='Redeker:BAABNQAECoEaAAIZAAgKgxLMKAAaAgAZAAgKgxLMKAAaAgAAAA==.Redlossa:BAAANQADCgIIAgAAAA==.Renneth:BAAANQADCgUICgAAAA==.Rentahunter:BAAANQAECgEIAQAAAA==.Revax:BAAANQAECgQIBAABNQAECgkJIwADAHkZAA==.Reyna:BAAANQADCgQIBAABNQADCggICAALAAAAAA==.',
Rh='Rholand:BAAANQAECgUIBgAAAA==.',
Ri='Ricopsu:BAABNQAECoEbAAMcAAgKcBzNCACQAgAcAAgKcBzNCACQAgAIAAEKygbGpgAoAAAAAA==.',
Rn='Rngnar:BAAANQAECggIDgAAAA==.',
Ro='Roakar:BAAANQADCgYIDAAAAA==.Rocklii:BAAANQADCggIEQAAAA==.Roguewolf:BAABNQAECoEnAAIIAAgKMhE3PgDbAQAIAAgKMhE3PgDbAQAAAA==.Rokdomaa:BAAANQAFFAEIAQAAAA==.Roki:BAABNQAECoEYAAIWAAcKiw4+IwCLAQAWAAcKiw4+IwCLAQAAAA==.Rolow:BAABNQAECoEmAAIeAAgK8xxYZACiAgAeAAgK8xxYZACiAgAAAA==.Roony:BAACNQAFFIEZAAIBAAcKTx+rAACRAgABAAcKTx+rAACRAgA1AAQKgSQAAgEACQrZIj8JABkDAAEACQrZIj8JABkDAAAA.Roper:BAAANQAECggIBAAAAA==.Roritai:BAAANQABCgQIBAABNQAECgQICgALAAAAAA==.Rot:BAABNQAECoEhAAMFAAkK7CWXCgAxAwAFAAgKdyWXCgAxAwAEAAgK2SH8HwCsAgAAAA==.Royle:BAAANQAECgcIEQAAAA==.',
Ru='Runes:BAABNQAECoEkAAIEAAkKjxjwLABdAgAEAAkKjxjwLABdAgAAAA==.Runnerjay:BAAANQAECgUIDAABNQAECgkJJgAUAGsTAA==.Rush:BAAANQADCgIIAgABNQAECggIHwACAMgYAA==.Ruuf:BAABNQAECoEXAAMUAAcKwCE1DwCEAgAUAAcKwCE1DwCEAgAGAAYKRgctAAHmAAAAAA==.',
Ry='Rygik:BAAANQAECgQICAABNQAECgcIFgAVAAsgAA==.Rysxn:BAABNQAECoEWAAIVAAcKCyAzGgBqAgAVAAcKCyAzGgBqAgAAAA==.Ryuujins:BAACNQAFFIEVAAIQAAYKJBq6BQAZAgAQAAYKJBq6BQAZAgA1AAQKgSAAAxAACQrzJOATABkDABAACQqoJOATABkDABIABQq/JEYIAMsBAAAA.',
['Rá']='Ráhu:BAAANQAECgQIBAABNQAECgkJJQAOAAYZAA==.',
Sa='Sago:BAABNQAECoEaAAMJAAcK+B/WagAxAgAJAAcKph3WagAxAgAgAAUK+xosGQBwAQAAAA==.Sandman:BAAANQAECgQIDgAAAA==.',
Sc='Scumball:BAEANQADCgcIEgABNQADCggIGAALAAAAAA==.Scyon:BAACNQAFFIEGAAIeAAMK4A6lLgDhAAAeAAMK4A6lLgDhAAA1AAQKgTYAAh4ACQqEHwAzABkDAB4ACQqEHwAzABkDAAAA.',
Se='Selinie:BAAANQABCggIEAAAAA==.Senari:BAABNQAECoEgAAMUAAgKURlwGAAKAgAUAAcKRBtwGAAKAgAGAAgKGRNPgwDvAQAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgYIDQAAAA==.Senseiwacks:BAAANQABCgIIAwAAAA==.',
Sh='Shadowblazer:BAABNQAECoEdAAINAAgKxhtoQAB1AgANAAgKxhtoQAB1AgAAAA==.Shalizar:BAAANQADCgUICAAAAA==.Shanda:BAACNQAFFIEHAAICAAQKehInDgA7AQACAAQKehInDgA7AQA1AAQKgSEAAwIACQpqIHQXAP0CAAIACQpqIHQXAP0CAAwAAwotHRq9AOkAAAAA.Shanto:BAABNQAECoEhAAIMAAgKFRrJOgBjAgAMAAgKFRrJOgBjAgAAAA==.Shatrauzg:BAAANQAECgEIAQAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAABNQAECoElAAMCAAkKRxoMLwCAAgACAAcKMSEMLwCAAgAKAAgKnwHJIwDjAAAAAA==.Shiftinmojo:BAAANQAECgQIBQAAAA==.Shoumei:BAABNQAECoEhAAMmAAgKPxiXHQAcAgAmAAgKPxiXHQAcAgAfAAYKAArOJwAKAQAAAA==.Shugz:BAAANQADCgMIAwABNQAECgkJGgAaAP8dAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQIDAAAAA==.Sinfull:BAAANQADCggICAAAAA==.Sintharia:BAAANQADCgUJBQAAAA==.',
Sk='Skolaid:BAACNQAFFIEHAAMHAAMKLwmiFADeAAAHAAMKLwmiFADeAAAGAAIKwA8hHgCQAAA1AAQKgSMAAwcACQqfIMYQADYDAAcACQqfIMYQADYDAAYABQqgIKKTAMgBAAAA.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwALAAAAAA==.Smoopoodoop:BAAANQAECgUIBQAAAA==.',
Sn='Snagglepuss:BAAANQADCggICAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgYIEQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIDAAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQAECgYIDQAAAA==.Stonatroll:BAAANQAECgEIAQABNQAECgkJIwADAHkZAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAABNQAECoEXAAIJAAcKfhdtgAD3AQAJAAcKfhdtgAD3AQAAAA==.Stormspellz:BAABNQAECoEZAAICAAgKuRWJTQABAgACAAgKuRWJTQABAgAAAA==.',
Su='Supay:BAAANQAECgQICAAAAA==.',
Sw='Swinginsista:BAABNQAECoEYAAIHAAYKsBjpWQDpAQAHAAYKsBjpWQDpAQAAAA==.',
Ta='Taldath:BAAANQADCggJDwAAAA==.Talicso:BAACNQAFFIEGAAMeAAMKTgo4PgCZAAAeAAIKlg04PgCZAAAdAAEKvAMGEABHAAA1AAQKgSAAAh4ACQpbGtNvAIgCAB4ACQpbGtNvAIgCAAAA.Talos:BAAANQAECggIDwAAAA==.Talzinn:BAAANQADCgYIBgABNQAECggIDwALAAAAAA==.Tardalian:BAAANQADCgYICAAAAA==.Tarkinal:BAABNQAECoEXAAICAAcKbSEWLwCAAgACAAcKbSEWLwCAAgAAAA==.Taurito:BAAANQAECgUIDgAAAA==.',
Te='Teezee:BAABNQAECoEkAAMGAAgKth7SQQCqAgAGAAgKth7SQQCqAgAHAAMKKBPbwwDLAAAAAA==.Teitterdrud:BAABNQAECoEdAAMIAAgKpA60SQCVAQAIAAgKPwq0SQCVAQAcAAMKNxT3IwC+AAAAAA==.Telina:BAAANQAECggIBgAAAA==.Telira:BAAANQAECgYIDwAAAA==.Tenderhoof:BAABNQAECoEsAAMIAAkK0R8pDwA+AwAIAAkK0R8pDwA+AwABAAUKBxGQOAAjAQAAAA==.',
Th='Thanatus:BAAANQADCgQJBAAAAA==.Thath:BAAANQADCggIJwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAABNQAECoEXAAIRAAkKXiKiCwBHAwARAAkKXiKiCwBHAwAAAA==.Thruumm:BAAANQAECgYIBgAAAA==.Thunderclapz:BAAANQAECgcJCAAAAA==.Thunsibution:BAAANQADCggICQABNQAFFAMIBgAgAGkXAA==.',
Ti='Tickz:BAABNQAECoEkAAQNAAgKMyHPHQD4AgANAAgKkx/PHQD4AgAYAAYK2h2QBwD8AQATAAIKwBXZTgCHAAAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAABNQAECoEmAAIIAAgK5gdSTwB3AQAIAAgK5gdSTwB3AQAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAABNQAECoEhAAMUAAgKsR+nDwB9AgAUAAgKsR+nDwB9AgAGAAQKXw1bGwG5AAAAAA==.Tokémon:BAAANQAECgcICgAAAA==.Toxren:BAABNQAECoEeAAMHAAkKghnRIwDFAgAHAAkKghnRIwDFAgAGAAIKEgWUYAFEAAAAAA==.',
Tr='Traelin:BAACNQAFFIEGAAIHAAMKKh7RDwAmAQAHAAMKKh7RDwAmAQA1AAQKgSEAAgcACQqQJG8EAKQDAAcACQqQJG8EAKQDAAAA.Tread:BAAANQAECgMIAwAAAA==.Trickee:BAAANQAECgYICwABNQAECgYIEQALAAAAAA==.',
Ts='Tskaha:BAAANQAECgUIDQAAAA==.',
Ty='Tyria:BAAANQAECgQICQAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAAANQAECgYIDgAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIBgAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAABNQAECoEfAAIHAAkK3h3kGAACAwAHAAkK3h3kGAACAwAAAA==.Vargath:BAAANQADCgMIAwAAAA==.Vashstampede:BAAANQAECgIIAgAAAA==.',
Ve='Vei:BAAANQADCgYIGgABNQADCgIIAgALAAAAAA==.Velrik:BAAANQAECgQICgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vercy:BAAANQADCgYIBwABNQADCggIHAALAAAAAA==.Vezkin:BAACNQAFFIEGAAIIAAMKpxgREwD5AAAIAAMKpxgREwD5AAA1AAQKgSAAAggACQo5JVQJAHcDAAgACQo5JVQJAHcDAAAA.',
Vh='Vhexx:BAAANQAECgQIBAAAAA==.',
Vi='Vintagejeans:BAAANQAECgYIEQAAAA==.Virtus:BAABNQAECoEhAAIDAAgK5RZISQBrAgADAAgK5RZISQBrAgAAAA==.Vitrixz:BAAANQADCgUICwAAAA==.Vizaimor:BAABNQAECoEZAAIDAAkKChFwbgAIAgADAAkKChFwbgAIAgAAAA==.',
Vo='Voi:BAAANQABCgIIAwABNQAECgEIAQALAAAAAA==.Vostok:BAACNQAFFIEFAAIJAAMKZw5dHgDZAAAJAAMKZw5dHgDZAAA1AAQKgR0AAwkACQpqFhJcAFsCAAkACQpqFhJcAFsCACAAAQoxE9w5ADcAAAAA.',
Vu='Vulcãnus:BAAANQAECgEIAgAAAA==.',
Wa='Wallyoak:BAAANQADCgEIAQAAAA==.Warcry:BAAANQAECgEJAQAAAA==.',
We='Wealthyscaly:BAAANQAECgMIBwAAAA==.Weedzzar:BAAANQADCgQIBgAAAA==.Werse:BAABNQAECoEjAAIQAAgKtR+oKACpAgAQAAgKtR+oKACpAgAAAA==.Wetloginyou:BAABNQAECoEWAAICAAcK0CAxLwCAAgACAAcK0CAxLwCAAgAAAA==.',
Wh='Whodi:BAAANQAECgYIEwAAAA==.',
Wi='Witt:BAAANQAECgcIEAAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAABNQAECoEfAAMCAAgKyBhrRQAhAgACAAgKyBhrRQAhAgAKAAIKbQVmKwBiAAAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wubble:BAAANQAECgQIBAAAAA==.Wushoolay:BAAANQAECgQJCgAAAA==.',
Xn='Xnatem:BAABNQAECoEhAAIgAAgK6h+uBgDXAgAgAAgK6h+uBgDXAgAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAABNQAECoEhAAMHAAgKVgthagCyAQAHAAgKVgthagCyAQAGAAEKVgFunwEbAAAAAA==.',
Ye='Yeraleth:BAABNQAECoEiAAIBAAkKgRxZDgDQAgABAAkKgRxZDgDQAgAAAA==.',
Yi='Yisiwang:BAAANQADCgcIBwABNQADCggIHAALAAAAAA==.',
Yo='Yorick:BAAANQADCggIFQAAAA==.Yorkj:BAAANQAECgYIDwAAAA==.',
Za='Zalthorax:BAAANQAECgUIBgABNQAECgkJIwADAHkZAA==.Zatilion:BAABNQAECoEZAAIGAAgK0g6pmgC2AQAGAAgK0g6pmgC2AQAAAA==.Zavage:BAAANQADCgYICgABNQAECgcIGwANAGQRAA==.Zayn:BAAANQAECgUIDAAAAA==.',
Ze='Zenki:BAAANQADCgQIAwAAAA==.Zenkî:BAAANQADCgEIAQAAAA==.Zenrune:BAAANQAECgcICgABNQAECgkJGAAMABAZAA==.Zephiday:BAAANQAECgMIAwAAAA==.',
Zi='Ziggashot:BAABNQAECoEiAAIDAAgKVR+AJADnAgADAAgKVR+AJADnAgAAAA==.Zinsus:BAAANQADCggIEwABNQAECgkJIwADAHkZAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.',
Zu='Zurahahsha:BAABNQAECoEgAAIKAAcKvAYFGwCAAQAKAAcKvAYFGwCAAQAAAA==.',
['Ðr']='Ðrow:BAABNQAECoEXAAIVAAgKCQ8LLADHAQAVAAgKCQ8LLADHAQAAAA==.',
['Óx']='Óxy:BAAANQAECgYIEwAAAA==.',
['Ör']='Örc:BAAANQADCgUIBQABNQAECggIGgAGAL4gAA==.',
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
