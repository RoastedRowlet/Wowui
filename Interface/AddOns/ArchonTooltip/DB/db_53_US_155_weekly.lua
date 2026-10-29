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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Priest-Discipline','DeathKnight-Blood','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Paladin-Holy','Mage-Frost','Mage-Arcane','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Druid-Guardian','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Priest-Holy','Priest-Shadow','Warlock-Demonology','Druid-Balance','Hunter-BeastMastery','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Warlock-Affliction','Mage-Fire','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Vengeance','Evoker-Augmentation','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abashai:BAABNQAECn8cAAMBAAoK6RkrKwDTAQABAAoK6RkrKwDTAQACAAIKOAIUlABkAAAAAA==.',
Ae='Aellyria:BAAANQAECgYIBgAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgkJHQADAB4ZAA==.',
Ai='Ainsworth:BAEANQAECgMIAwABNQAECgcIJgAEALoPAA==.',
Ak='Akaili:BAAANQAECggIEgAAAA==.',
Al='Alexiya:BAABNQAECn8gAAIFAAgKHBK6EQDlAQAFAAgKHBK6EQDlAQAAAA==.Allacari:BAABNQAECn8eAAIGAAcK6RWkBACfAQAGAAcK6RWkBACfAQAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQAECgcIBQAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAwAAAA==.',
Am='Amanda:BAABNQAECn8uAAIHAAkK5A/2AgDRAQAHAAkK5A/2AgDRAQAAAA==.Amonamarth:BAABNQAECn8XAAIIAAkKZgnqewAJAQAIAAkKZgnqewAJAQAAAA==.',
An='Anabelleigh:BAAANQABCggIEwAAAA==.Andrise:BAABNQAECn8mAAQJAAcKdBxTXgD0AQAJAAcKdBxTXgD0AQAKAAcKRBdTGwCvAQALAAUKyRgoigCLAQAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAABNQAECn8gAAMDAAkKiRTIRgD9AQADAAkKiRTIRgD9AQAIAAQKihGhnQCeAAAAAA==.',
Ap='Apol:BAABNQAECn8oAAIMAAkKvxCYOgCwAQAMAAkKvxCYOgCwAQAAAA==.',
Ar='Arachne:BAABNQAECn8vAAMNAAoKWxefBADdAgANAAkK1xmfBADdAgAOAAgKbwserwDoAAAAAA==.Arafina:BAAANQABCgUICQABNQAECgoKMgAMAOwQAA==.Arakar:BAABNQAECn8yAAIMAAoK7BA2IwAwAgAMAAoK7BA2IwAwAgAAAA==.Aralynne:BAAANQAECgcIDwAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAAANQAECgQIDQAAAA==.Ardori:BAAANQAECgYICgABNQAECgoKKAAPAHkbAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwAQAAAAAA==.Armorya:BAABNQAECn84AAIRAAoKPR33JwBiAgARAAoKPR33JwBiAgAAAA==.Armyofone:BAAANQAECgQICAAAAA==.Artaius:BAABNQAECn8gAAISAAoKcyWQCADyAgASAAoKcyWQCADyAgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggIDgABNQAECggIFQATAOoLAA==.Astarog:BAABNQAECn8XAAMUAAcKUgwTEQBYAQAUAAcKUgwTEQBYAQAVAAIKDgXqOABHAAAAAA==.',
At='Atafloosy:BAEBNQAECn8gAAIJAAkK4R9KOwByAgAJAAkK4R9KOwByAgAAAA==.Athelf:BAABNQAECn8rAAIRAAoKwB0tIQCGAgARAAoKwB0tIQCGAgAAAA==.Athelfstein:BAAANQAECggICAAAAA==.Attina:BAAANQADCggICAAAAA==.',
Au='Aubriell:BAAANQAECgYIDgAAAA==.',
Ay='Ayrnerdam:BAAANQAECgYIDQAAAA==.',
Az='Azureas:BAAANQAECgEIAQAAAA==.',
Ba='Babelfish:BAABNQAECn8dAAIWAAgKORakHgDzAQAWAAgKORakHgDzAQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAABNQAECn8fAAIBAAcK+wqYKQB4AQABAAcK+wqYKQB4AQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECn8xAAISAAoKLQpZIgCEAQASAAoKLQpZIgCEAQAAAA==.Beastkael:BAAANQAECgUICwAAAA==.Beg:BAABNQAECn8hAAIXAAkKBBCyXwACAgAXAAkKBBCyXwACAgAAAA==.Belfalas:BAAANQABCgQICAAAAA==.Beliir:BAAANQADCggICAABNQAECgcIKQAWAIQeAA==.Berghain:BAAANQADCgQIAgAAAA==.Berick:BAAANQAECgIIAgAAAA==.Betzalel:BAABNQAECn8dAAIXAAkKvBKKXQAJAgAXAAkKvBKKXQAJAgAAAA==.Beytryx:BAAANQAECgIIAwAAAA==.',
Bi='Bittycakes:BAAANQAECgIIAgAAAA==.',
Bl='Blackstar:BAAANQAECgIIAgAAAA==.Bladeoftruth:BAABNQAECn8hAAIIAAoK7R+lFwDwAgAIAAoK7R+lFwDwAgAAAA==.Blaize:BAAANQADCgYICQAAAA==.Blitzwing:BAAANQAECgUIBgAAAA==.Bloodyaggro:BAAANQAECgYICgAAAA==.',
Bo='Bobapstab:BAAANQADCgIIAgAAAA==.Bodin:BAAANQADCgcIBwAAAA==.Bonnabelle:BAACNQAFFH8IAAIXAAQKxgSREwD3AAAXAAQKxgSREwD3AAA1AAQKfzAAAhcACgqXCItQAG8BABcACgqXCItQAG8BAAAA.Boombawks:BAAANQAECgcICAAAAA==.Bor:BAAANQAECgYICgABNQAECgoKIAASAHMlAA==.Bos:BAABNQAECn8eAAIYAAgKtxqmGgB2AgAYAAgKtxqmGgB2AgAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgcIGAAZAIIXAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECggIGgAPAHgZAA==.Briest:BAAANQAECgQIBAABNQAECggIGgAPAHgZAA==.Bristra:BAAANQADCgYIBgABNQAECgYICQAQAAAAAA==.Brownbar:BAAANQAECgYICQAAAA==.Bruid:BAABNQAECn8aAAMPAAgKeBnhJgDqAQAPAAcKzBfhJgDqAQAaAAcKvhI4TwCiAQAAAA==.Bruneigin:BAAANQAECgcIEAAAAA==.',
Ca='Cailey:BAAANQAECgQICAAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwAQAAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgQIAwAAAA==.Carrin:BAABNQAECn9NAAIRAAkKzSLkEgDiAgARAAkKzSLkEgDiAgAAAA==.Castanza:BAAANQADCggICAAAAA==.Catalyia:BAABNQAECn8tAAIbAAoKrxfVTQCFAgAbAAoKrxfVTQCFAgAAAA==.Catris:BAABNQAECn8UAAIYAAYKygaDLQCkAAAYAAYKygaDLQCkAAAAAA==.Catset:BAABNQAECn8cAAIaAAgK9wdnWwBlAQAaAAgK9wdnWwBlAQAAAA==.',
Ce='Cecea:BAAANQADCgEIAgAAAA==.',
Ch='Chaahk:BAAANQAECgQICAABNQAECgoKIAASAHMlAA==.Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECggIDQABNQAECgoKHwAVAKcSAA==.Chazzo:BAABNQAECn8gAAIcAAoKcBKQfgAeAgAcAAoKcBKQfgAeAgAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECgcIEgAAAA==.',
Co='Commy:BAABNQAECn8dAAMOAAgKXxAjzQDsAQAOAAgKXxAjzQDsAQANAAEKng3nQgA+AAAAAA==.Concorde:BAAANQAECgUICgAAAA==.Copiousconns:BAABNQAECn8pAAITAAcKPQ5tJQBIAQATAAcKPQ5tJQBIAQAAAA==.Corinne:BAAANQADCggICAAAAA==.Corlock:BAAANQADCgYIDAAAAA==.Cornholy:BAAANQADCgMIAwAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAAANQAECgYIDgAAAA==.',
Cu='Cubos:BAABNQAECn80AAMZAAoKxyVLAgDVAwAZAAoKxyVLAgDVAwATAAEKGCFfGwBeAAAAAA==.Cutlash:BAAANQAECgUICwAAAA==.Cutslash:BAAANQAECgIIAgABNQAECgUICwAQAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECgoKHwAVAKcSAA==.',
Da='Daemona:BAABNQAECn8oAAMdAAoKXhNUMwARAgAdAAoKXhNUMwARAgAeAAEKAAAJUAAAAAAAAA==.Daieniceis:BAABNQAECn8XAAIbAAcK7QOJ2gBLAQAbAAcK7QOJ2gBLAQAAAA==.Dalkurn:BAACNQAFFH8RAAIPAAYKOiLoAQBXAgAPAAYKOiLoAQBXAgA1AAQKfysAAg8ACQrrI/wHAEQDAA8ACQrrI/wHAEQDAAAA.',
De='Decayy:BAACNQAFFH8LAAIIAAUKlRiMDgBrAQAIAAUKlRiMDgBrAQA1AAQKfyMAAggACQqIImAWAPoCAAgACQqIImAWAPoCAAAA.Deceptakahn:BAABNQAECn8pAAISAAgK8gUzNgD0AAASAAgK8gUzNgD0AAAAAA==.Derailedbeef:BAACNQAFFH8JAAMcAAMKZBRLEgDRAAAcAAMKLw9LEgDRAAAfAAEKzh/nAgBKAAA1AAQKfzcAAxwACgpNHbwbAI8CABwACgoyHbwbAI8CAB8ABArDGhQXAC0BAAAA.Deydoralia:BAABNQAECn9DAAIMAAoKwSBJDgBYAwAMAAoKwSBJDgBYAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.Diô:BAAANQADCggICAAAAA==.',
Dl='Dlwlrma:BAABNQAECn8UAAMFAAkKyw84DQBbAQAFAAcKBRI4DQBbAQAaAAYKVgWAhgC4AAAAAA==.',
Dn='Dnme:BAABNQAECn8mAAIeAAoKkhHMKQD1AQAeAAoKkhHMKQD1AQAAAA==.',
Do='Doieha:BAAANQADCggIDwABNQAECgoKKAAPAHkbAA==.Doneldus:BAAANQAECgUIDQAAAA==.Dool:BAABNQAECn8UAAIeAAYK0wq9LgCzAAAeAAYK0wq9LgCzAAAAAA==.Dorfdragon:BAABNQAECn8jAAIVAAcK4gu2IABNAQAVAAcK4gu2IABNAQAAAA==.Dorfe:BAABNQAECn83AAICAAoKIROOCAAGAgACAAoKIROOCAAGAgAAAA==.Dorflock:BAAANQADCggIHwAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgcIGQAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Dreamfyre:BAAANQADCgYIBgAAAA==.Drewgarymore:BAABNQAECn8xAAMaAAoK7xK6GQDDAQAaAAoKxBC6GQDDAQASAAcKDhcLHwCmAQAAAA==.Drough:BAAANQAECgQICgABNQAECgkJKQAgABQTAA==.Drzeal:BAAANQADCggIDgAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Dumblêdorê:BAAANQADCgMIAwABNQAFFAYIDwARAPEPAA==.Durandall:BAACNQAFFH8PAAIRAAYK8Q92CADDAQARAAYK8Q92CADDAQA1AAQKfy0AAhEACgqSHc0mAGgCABEACgqSHc0mAGgCAAAA.Durleap:BAAANQAECgYIDgAAAA==.Durthmaul:BAABNQAECn8XAAILAAcKNwZ/WQAAAQALAAcKNwZ/WQAAAQABNQAFFAYIDwARAPEPAA==.',
Dw='Dwarflock:BAABNQAECn8bAAIZAAgKGhW5ZwAkAgAZAAgKGhW5ZwAkAgAAAA==.',
Dy='Dylpickl:BAABNQAECn8VAAIeAAkKUx3KCwAiAwAeAAkKUx3KCwAiAwAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAABNQAECn8WAAIhAAcK8wWeYQAeAQAhAAcK8wWeYQAeAQAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgEIAQABNQAECgoKMgAMAMscAA==.Elow:BAAANQADCgIIAgAAAA==.Elyiet:BAAANQAECgUICQAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.Erkenbrand:BAAANQAECgEIAQABNQAECggIHAAcAEQcAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQAECgYIEQAAAA==.Ess:BAAANQAECgUIDgAAAA==.',
Et='Etabagodeeks:BAAANQAECgUIBQAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgYICQAQAAAAAA==.Evvie:BAABNQAECn8VAAITAAcKXQRcEgCHAAATAAcKXQRcEgCHAAAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAABNQAECn8dAAIRAAcKsxvefgAsAgARAAcKsxvefgAsAgAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fallin:BAAANQAECgUIBQAAAA==.Fantarius:BAACNQAFFH8PAAIXAAYKuhRvEACPAQAXAAYKuhRvEACPAQA1AAQKfzgAAxcACgo4IbYUAMACABcACgo4IbYUAMACAAcAAQqIBYouACgAAAAA.Fantazee:BAAANQADCgUIBQABNQAFFAYIDwAXALoUAA==.Fatdono:BAAANQAECggIEgAAAA==.',
Fi='Fibbs:BAABNQAECn8fAAISAAcK7hxGEgA+AgASAAcK7hxGEgA+AgAAAA==.Fikti:BAABNQAECn8xAAMiAAoK+BfqBACDAgAiAAgKuxvqBACDAgAZAAcKEhSnqgB9AQAAAA==.Firetongue:BAAANQADCgUIBQAAAA==.Firocios:BAABNQAECn8iAAIMAAcKBRNZWwAwAQAMAAcKBRNZWwAwAQAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.Flatiron:BAAANQADCgYIBwABNQAECgUIDQAQAAAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAABNQAECn8fAAIGAAYKwhHGBQBgAQAGAAYKwhHGBQBgAQABNQAECgkJJwAGAGsTAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQAECgUIDQAAAA==.Frostyfella:BAACNQAFFH8RAAIOAAYKyRqSDQAoAQAOAAYKyRqSDQAoAQA1AAQKfzwAAg4ACgpsInMaAGwDAA4ACgpsInMaAGwDAAE1AAEKAggCABAAAAAA.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAABNQAECn8WAAIFAAYKKw1sHwAeAQAFAAYKKw1sHwAeAQAAAA==.',
Ga='Garypotter:BAABNQAECn8uAAIeAAoKxCHiBwCKAgAeAAoKxCHiBwCKAgAAAA==.Gazooks:BAAANQADCgYIEwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECn8yAAIbAAoKUyIiHgAfAwAbAAoKUyIiHgAfAwAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAAANQAECgcIDgAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgMIBgAAAA==.Grindelbald:BAABNQAECn8bAAMOAAkK0hL6kwBYAgAOAAkK0hL6kwBYAgAjAAIK4ghxCQByAAAAAA==.',
Gt='Gtfofupá:BAAANQAECgQIDgAAAA==.',
Gu='Gulraan:BAAANQAECgcICgAAAA==.Gushee:BAABNQAECn8jAAIfAAkK2RkgCgBmAQAfAAkK2RkgCgBmAQAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgQIAwAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgIIAgAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgUIDAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Haldor:BAAANQABCgEIAQABNQAECgoKHwAVAKcSAA==.Hanamari:BAACNQAFFH8OAAIkAAYKRAa8BwB0AQAkAAYKRAa8BwB0AQA1AAQKfyIAAyQACQrgFmkhACACACQACQrgFmkhACACACUAAQrrAR5WAB0AAAAA.Hanoe:BAAANQADCggICAAAAA==.Harakrron:BAAANQAECgIIAQAAAA==.Harleyquìnn:BAAANQAECgIIAQAAAA==.Harydresden:BAABNQAECn8fAAIOAAgKOAQVsQDlAAAOAAgKOAQVsQDlAAAAAA==.Hawkesmage:BAAANQAECgIIAgAAAA==.Hawkslayer:BAABNQAECn8UAAIRAAYK3gUD5ACmAAARAAYK3gUD5ACmAAAAAA==.Hazule:BAAANQAECgIIAwABNQAECggIHQAJAPcYAA==.',
He='Healadín:BAAANQAECgEIAQAAAA==.Hedgelord:BAACNQAFFH8PAAIaAAUKaxK2EQBQAQAaAAUKaxK2EQBQAQA1AAQKfysAAhoACgqRHHUMAIMCABoACgqRHHUMAIMCAAAA.Heyboyy:BAABNQAECn8WAAIPAAgKVBfWEAAZAgAPAAgKVBfWEAAZAgABNQAFFAQIBQAbAEsYAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAABNQAECn8YAAIZAAcKsh/AXABBAgAZAAcKsh/AXABBAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJHQAZADMVAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQAECgUIDgAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgoKJQAZAL4hAA==.',
Ic='Icyblades:BAABNQAECn8cAAIDAAgKZwqmZwBzAQADAAgKZwqmZwBzAQAAAA==.',
Il='Ilidania:BAAANQAECgYICQAAAA==.Ilyna:BAABNQAECn8eAAIZAAcKgQpcsgBrAQAZAAcKgQpcsgBrAQAAAA==.',
Im='Immortalnut:BAABNQAECn8UAAIVAAcKjwhYIABSAQAVAAcKjwhYIABSAQAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQADCgcIBwAAAA==.',
Ja='Jackypan:BAAANQADCgUIBQAAAA==.Jaedis:BAAANQAECgYIDQAAAA==.Jaktar:BAABNQAECn8VAAIbAAkKXwjHjwDqAQAbAAkKXwjHjwDqAQAAAA==.Jane:BAAANQAECgMIAwAAAA==.Janet:BAABNQAECn8bAAIgAAkKrhA8FADiAQAgAAkKrhA8FADiAQAAAA==.Jani:BAAANQADCgQIBAABNQAECgkJGwAgAK4QAA==.Janiina:BAAANQADCgYIDQAAAA==.Japheth:BAAANQAECgEIAQAAAA==.',
Je='Jezak:BAAANQAECgUIBAABNQAECgcIBQAQAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgYIEAAAAA==.Joobs:BAABNQAECn8VAAITAAgK6gveFADHAQATAAgK6gveFADHAQAAAA==.Joosh:BAAANQAECgYIBgAAAA==.',
Js='Jslice:BAACNQAFFH8LAAIcAAUKmg/gFQB5AQAcAAUKmg/gFQB5AQA1AAQKfyEAAhwACQrHIOtGALUCABwACQrHIOtGALUCAAAA.',
Ju='Juda:BAAANQAECgUICAAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgQIBQAAAA==.',
Ka='Kaelys:BAABNQAECn8hAAMMAAYK3xGfXwAjAQAMAAYK3xGfXwAjAQARAAEKAAAV0wEdAAAAAA==.Kahliea:BAAANQAECgUIDgAAAA==.Kaidance:BAAANQAECggICgAAAA==.Kaisaze:BAABNQAECn8gAAIhAAoKFQpvKwCAAQAhAAoKFQpvKwCAAQAAAA==.Kamiga:BAAANQAECgYIBgABNQAECgoKKAAPAHkbAA==.Kapachka:BAAANQAECgYIDwAAAA==.Karbide:BAAANQAECgIIAgAAAA==.Kateri:BAAANQAECgQIBQAAAA==.Katmarie:BAAANQAECgMIBgAAAA==.Kazothor:BAABNQAECn8UAAIIAAYKghs1MQAnAQAIAAYKghs1MQAnAQAAAA==.',
Ke='Kelborne:BAAANQAECgUIBwAAAA==.Keria:BAACNQAFFH8VAAIdAAgKYh0jAgCMAgAdAAgKYh0jAgCMAgA1AAQKf0IAAh0ACgr9JegBAFwDAB0ACgr9JegBAFwDAAAA.Keyz:BAAANQAECgYICwAAAA==.',
Ki='Kibbwarrior:BAAANQAECggIDAAAAA==.Kiretsu:BAABNQAECn8cAAMNAAkK0BBpGAA1AQAOAAgKlw7w4gDDAQANAAUK/w9pGAA1AQAAAA==.',
Kn='Knowén:BAAANQADCggIDgAAAA==.',
Ko='Koder:BAAANQADCgYIDAAAAA==.Kovus:BAABNQAECn8VAAISAAcKOAhjLQCyAAASAAcKOAhjLQCyAAAAAA==.',
Kr='Kragami:BAAANQAECgYIEAAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAABNQAECn8UAAIRAAgKvgce1ABzAQARAAgKvgce1ABzAQAAAA==.Kristanya:BAABNQAECn82AAIUAAkKTQjHEABeAQAUAAkKTQjHEABeAQAAAA==.Kristina:BAEANQAECggIDgAAAA==.',
Ks='Ks:BAAANQAECgQIBAAAAA==.',
Ku='Kulaidmage:BAABNQAECn8fAAIOAAgKGRaHsgAeAgAOAAgKGRaHsgAeAgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAUIDAALAOoDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECn89AAImAAoKqSN6AQCSAwAmAAoKqSN6AQCSAwAAAA==.Lamashtu:BAABNQAECn8hAAIYAAgKpBX3HgBFAgAYAAgKpBX3HgBFAgAAAA==.Lasciel:BAAANQADCgcIBwAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layli:BAAANQADCgIIAgABNQAECgEIAQAQAAAAAA==.',
Le='Leddy:BAABNQAECn8vAAMHAAoKzBbEBQBFAgAHAAkKAhfEBQBFAgAYAAgKJRS3DwDUAQAAAA==.Leiman:BAAANQABCgQIBQAAAA==.Lemmy:BAAANQAECgcIBwAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAABNQAECn8aAAIJAAcKLBVJbgDAAQAJAAcKLBVJbgDAAQAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAABNQAECn8kAAIlAAcKiiHJDgCWAgAlAAcKiiHJDgCWAgAAAA==.Lilillidari:BAABNQAECn8eAAIdAAkKPByhHQCsAgAdAAkKPByhHQCsAgABNQAFFAcIGwADAHUZAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFH8bAAQDAAcKdRn6BgCsAQADAAUKABn6BgCsAQAhAAQKmBhjBgAKAQAIAAEKAAAJOQAgAAA1AAQKf0YAAyEACgpMJaUKAEUDACEACgq8I6UKAEUDAAMACQpAJDcSACYDAAAA.Lilunholy:BAABNQAECn8UAAIDAAgK4xrNNQBRAgADAAgK4xrNNQBRAgABNQAFFAcIGwADAHUZAA==.Linali:BAAANQAECgYIBwAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Lisey:BAAANQAECgEIAgAAAA==.Listari:BAAANQADCgQIBAAAAA==.Lisyao:BAABNQAECn8YAAMJAAgKAQvbTABiAQAJAAgKAQvbTABiAQALAAEKDAbn0QAjAAAAAA==.Littany:BAABNQAECn8nAAMMAAoKBA8+aQDbAQAMAAoKBA8+aQDbAQARAAcKXg8eygCHAQAAAA==.Livane:BAAANQAECgQICAAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Looneytoones:BAAANQAECgUIBQAAAA==.Loralia:BAAANQADCggIEAAAAA==.Lowground:BAAANQAECgEIAQAAAA==.',
Lu='Lucïna:BAABNQAECn8eAAIdAAcKYA3tSQB9AQAdAAcKYA3tSQB9AQAAAA==.Ludk:BAABNQAECn83AAIIAAkKlCGlFAAHAwAIAAkKlCGlFAAHAwAAAA==.Luk:BAABNQAECn9AAAMeAAoKaxX9FACfAQAeAAoKaxX9FACfAQAmAAUKqxKZGQAaAQABNQAECgoKJAARAD0VAA==.Lumiela:BAABNQAECn8ZAAIRAAgKQgSUzgDFAAARAAgKQgSUzgDFAAAAAA==.Luminah:BAAANQAECgMIAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgEIAQAAAA==.Lunì:BAAANQADCgQIBAABNQAECgEIAQAQAAAAAA==.Luxmortic:BAAANQAECgcIBwAAAA==.Luxshot:BAAANQADCggIEAAAAA==.',
['Lê']='Lêxie:BAAANQADCgcIDQAAAA==.',
['Ló']='Lóner:BAABNQAECn8yAAMCAAoK5w+NLAA1AgACAAoKxg2NLAA1AgABAAcKrxEvOgB9AQAAAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgEIAQAQAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECn8pAAIcAAoKnxIXkwDsAQAcAAoKnxIXkwDsAQAAAA==.Magicg:BAACNQAFFH8HAAIYAAYK9AWwCgBLAQAYAAYK9AWwCgBLAQA1AAQKfygAAxgACgquG5MVALMCABgACgquG5MVALMCABcAAQqmCqD4ADwAAAAA.Magordito:BAABNQAECn8bAAIOAAgK3gfD8gClAQAOAAgK3gfD8gClAQABNQAECgoKMgACAOcPAA==.Mairek:BAACNQAFFH8MAAIOAAUK3g/0GwDQAAAOAAUK3g/0GwDQAAA1AAQKf0AAAg4ACgoiHW8gAHgCAA4ACgoiHW8gAHgCAAAA.Maleigoron:BAABNQAECn8aAAIZAAkK1QnMjgDCAQAZAAkK1QnMjgDCAQAAAA==.Malkuri:BAABNQAECn8sAAMEAAoKlhewKgD2AQAbAAkKSRfkgAALAgAEAAgKlxGwKgD2AQAAAA==.Malorysera:BAACNQAFFH8OAAMVAAQKliH5BABcAAAnAAMK5xSDBgCNAAAVAAIK7SH5BABcAAA1AAQKfzUABCcACgpFIVYBAPUCACcACgplH1YBAPUCABUACQp2Hc4IAOkCABQABgpZF6AkAJ0BAAAA.Marolt:BAAANQADCgMIAwABNQAECgoKKAAPAHkbAA==.Martrion:BAAANQABCgUIBQAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAABNQAECn8WAAITAAcKOQdvJgBCAQATAAcKOQdvJgBCAQAAAA==.Menirva:BAABNQAECn8UAAIOAAgKYwrq5QC+AQAOAAgKYwrq5QC+AQABNQAECgoKLAAEAJYXAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAABNQAECn8VAAIWAAgK+BJyKgCJAQAWAAgK+BJyKgCJAQABNQAFFAUIDAALAOoDAA==.Metasham:BAACNQAFFH8MAAILAAUK6gPcEgBDAQALAAUK6gPcEgBDAQA1AAQKfzIAAgsACgptGp8mAOkCAAsACgptGp8mAOkCAAAA.',
Mi='Miiaa:BAABNQAECn8XAAMRAAgK7xy+dwA9AgARAAcK5R++dwA9AgAWAAEKIw5ZbgA1AAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQAECgIIAwAAAA==.',
Mo='Moirasha:BAABNQAECn8bAAQZAAkKVAl8sABvAQAZAAkKVAl8sABvAQATAAIKRgLkeAA1AAAiAAEKAAB8MQAyAAAAAA==.Monkeydluffy:BAAANQAECgEIAQAAAA==.Monran:BAABNQAECn8eAAIKAAcKyAxUHACeAQAKAAcKyAxUHACeAQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQIBgABNQAECgcIBQAQAAAAAA==.Morphingtime:BAABNQAECn8eAAQFAAcKWBmvGABxAQAaAAcKoBX6UQCUAQAFAAUKDBuvGABxAQAPAAUKwhXfPAA7AQAAAA==.Mortivus:BAABNQAECn8VAAMDAAcKABTbMQD/AAADAAYKmhXbMQD/AAAhAAUK9AyncgDVAAAAAA==.',
Mu='Mudsworn:BAAANQAECgIIAgAAAA==.Muggs:BAAANQADCggIDgAAAA==.Mulvane:BAABNQAECn8VAAIXAAcKfRcRVABiAQAXAAcKfRcRVABiAQAAAA==.Mustachio:BAABNQAECn8eAAIOAAgKURlbrAApAgAOAAgKURlbrAApAgAAAA==.',
Mw='Mwc:BAACNQAFFH8MAAMBAAYKQhbhBgCjAQABAAUK5hHhBgCjAQACAAIKVCPVFQCcAAA1AAQKfxYAAwEACQqDJEkFADYDAAEACQqDJEkFADYDAAIABAp3FshpAAoBAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nashia:BAAANQADCgUIBQAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQAQAAAAAA==.',
Ne='Neall:BAABNQAECn8bAAIgAAkKPgpWIgA4AQAgAAkKPgpWIgA4AQAAAA==.Negaryu:BAAANQAECgYIDQAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAABNQAECn8aAAIBAAgKpAdqKwBnAQABAAgKpAdqKwBnAQAAAA==.',
Ni='Nightbird:BAAANQAECgcIBwAAAA==.Nightheals:BAAANQADCggIDQABNQAECgcIJgAJAHQcAA==.',
No='Nonna:BAABNQAECn83AAILAAkKWwl3SwArAQALAAkKWwl3SwArAQAAAA==.Noslrac:BAAANQAECgYIDgAAAA==.Notamonk:BAAANQAECggIDQAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIPgAAAQ==.',
Nu='Nuina:BAAANQADCgMIAwAAAA==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECn87AAIOAAoKNCQ4CwCpAwAOAAoKNCQ4CwCpAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAABNQAECn8ZAAIhAAgKlA+aTACFAQAhAAgKlA+aTACFAQAAAA==.',
Om='Omneg:BAAANQAECgQIBAAAAA==.',
On='Oneshotdeath:BAAANQAECgQIBAABNQAECgUICgAQAAAAAA==.Onlydks:BAABNQAECn8aAAQhAAkK3g2sRwCfAQAhAAkK3g2sRwCfAQADAAMKjAtktACHAAAIAAEKAAA83QAhAAABNQAFFAQICgAfANwMAA==.Onlyslams:BAACNQAFFH8KAAMfAAQK3AxiAQAyAQAfAAQK3AxiAQAyAQAcAAIKggWOOABaAAA1AAQKfykAAx8ACQpMHyoFANUCAB8ACQqWHSoFANUCABwABwpiGDOqALMBAAAA.Onlytrolling:BAAANQAECggICwAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orbaz:BAAANQADCgcIBgABNQAECgoKGQAkABsMAA==.Orter:BAABNQAECn8dAAIDAAkKHhmnPAAuAgADAAkKHhmnPAAuAgAAAA==.',
Ot='Ottan:BAAANQAECgEIAQAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAABNQAECn8YAAIZAAcKghdBfgDrAQAZAAcKghdBfgDrAQAAAA==.Parceh:BAABNQAECn8wAAMLAAkKaiKdEQCEAgALAAkKaiKdEQCEAgAJAAgKGx/kOgBzAgAAAA==.',
Ph='Phydaux:BAAANQAECgUIDAAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgYIDQAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQAQAAAAAA==.Prosciutto:BAABNQAECn8zAAMYAAoKZhksCgBQAgAYAAoKZhksCgBQAgAHAAEKbwd9EgAuAAAAAA==.Proxima:BAAANQAECgUIBQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFH8KAAIXAAQK7wMdGwASAQAXAAQK7wMdGwASAQA1AAQKfykAAxcACQp3DXByAMUBABcACQp3DXByAMUBAAcAAQq8AS4xACIAAAAA.Punn:BAAANQAECgcIDAABNQAECgoKJQAZAL4hAA==.Punnisher:BAABNQAECn8lAAMZAAoKviGOGgAcAwAZAAoKviGOGgAcAwATAAEKvhunbQBDAAAAAA==.Pureflow:BAABNQAECn8YAAIOAAkK1xuDhQBzAgAOAAkK1xuDhQBzAgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAABNQAECn8ZAAIcAAkKUhIOpgC+AQAcAAkKUhIOpgC+AQAAAA==.Quicks:BAABNQAECn8qAAIRAAoKHRtFUQChAgARAAoKHRtFUQChAgAAAA==.Quáckys:BAAANQAECggICwAAAA==.',
Ra='Radünz:BAAANQABCgQIBwABNQAECgkJNwAFANocAA==.Raelianna:BAAANQAECgQIDAABNQAECgoKOgAOAJglAA==.Raewyna:BAABNQAECn8ZAAIbAAgK+AkgvQCJAQAbAAgK+AkgvQCJAQAAAA==.Rahruhai:BAABNQAECn8oAAQPAAoKeRuXBQAcAwAPAAoKeRuXBQAcAwAFAAkK5h3iBwDeAgAaAAYKyhVDWwBlAQAAAA==.Rain:BAAANQAECgQIBwAAAA==.Raine:BAABNQAECn8ZAAMLAAoKEhebbQDXAQALAAgKdRSbbQDXAQAJAAcKgh1EZwDXAQAAAA==.Rainingblood:BAABNQAECn8fAAIRAAgKygYGqgADAQARAAgKygYGqgADAQAAAA==.Rainjar:BAABNQAECn8ZAAIlAAgKiiJ/DAC7AgAlAAgKiiJ/DAC7AgAAAA==.Rancîd:BAABNQAECn8eAAQDAAgKYRKHWwChAQADAAgKYRKHWwChAQAIAAUKtwishgDjAAAhAAMKtAdRjwB7AAABNQAECgkJKQAgABQTAA==.Raneeh:BAAANQABCgQIBAAAAA==.Ranron:BAABNQAECn8pAAMgAAkKFBOoDgBMAQAgAAkKJhKoDgBMAQAcAAgKAgy+gQAQAQAAAA==.Raphael:BAABNQAECn8jAAMDAAkKQhQPXgCXAQADAAgKJRIPXgCXAQAIAAYKphVnXQB8AQAAAA==.Rasik:BAABNQAECn83AAIcAAkK2BsNRwC1AgAcAAkK2BsNRwC1AgAAAA==.Ravenblood:BAAANQAECgUICQAAAA==.Rayel:BAABNQAECn8bAAIXAAgKZhyCKgAdAgAXAAgKZhyCKgAdAgAAAA==.Raylyn:BAAANQAECgMIBwAAAA==.Raymotgus:BAAANQADCgEIAQAAAA==.Razzak:BAAANQAECgIIAgABNQAECgcIBQAQAAAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQAECgIIAwAAAA==.Rhodrage:BAAANQADCgEIAQAAAA==.Rhome:BAABNQAECn8vAAMXAAoK4SM2BQCfAwAXAAoK4SM2BQCfAwAHAAEKABgfDwBGAAAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECn8rAAIXAAoKkA+nbgDSAQAXAAoKkA+nbgDSAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECn8zAAMhAAkKhSPtDwARAwAhAAgKTSHtDwARAwADAAgKRiD/KACVAgAAAA==.Risandra:BAAANQAECgcICQABNQAECgoKKAAPAHkbAA==.',
Ro='Roid:BAACNQAFFH8FAAIMAAMKvBB2GQDWAAAMAAMKvBB2GQDWAAA1AAQKfyAAAwwACQovDppcAAICAAwACQovDppcAAICABEAAgprApmWAT0AAAAA.Rolph:BAAANQAECgYIBgABNQAECgkJJgAcACEPAA==.Rotcorpse:BAAANQAECggIDwAAAA==.',
Ru='Ruddam:BAAANQAECgUIDQAAAA==.',
['Rä']='Räveñz:BAABNQAECn8vAAISAAkKBBKNGwDHAQASAAkKBBKNGwDHAQAAAA==.',
Sa='Saintabes:BAACNQAFFH8TAAIXAAYK7xiaCQCTAQAXAAYK7xiaCQCTAQA1AAQKfyUAAhcACgqcIPI8AHYCABcACgqcIPI8AHYCAAAA.Saioya:BAAANQAECgQIBAABNQAECgoKKAAPAHkbAA==.Saitame:BAAANQADCggICAAAAA==.Sakurah:BAABNQAECn8lAAMJAAoKhBqLVAAVAgAJAAoKhBqLVAAVAgALAAIKnQLB0gAhAAAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanerinn:BAAANQAECgQIBAAAAA==.Sanicor:BAAANQAECgQIBAAAAA==.Sanrinn:BAABNQAECn8kAAIbAAkK2xyfEwC0AgAbAAkK2xyfEwC0AgAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFH8TAAIOAAYK/Ak9IwBtAQAOAAYK/Ak9IwBtAQA1AAQKfzIAAg4ACgp8F8FNAMYBAA4ACgp8F8FNAMYBAAAA.Sarahjupiter:BAAANQAECgcIDQABNQAFFAYIEwAOAPwJAA==.Sargarach:BAAANQADCgEIAQAAAA==.Sarrin:BAAANQADCgQIBAABNQAECgkJNgAdAHgaAA==.Savaant:BAAANQADCgIIAgAAAA==.',
Sc='Scapegoat:BAEANQAECgcILQAAAQ==.Scraime:BAAANQAFFAEIAQAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seger:BAAANQAECgYICQAAAA==.Seilah:BAABNQAECn8cAAIPAAcKRCT5EADNAgAPAAcKRCT5EADNAgAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senpai:BAAANQADCgUIBQAAAA==.Senuya:BAAANQADCggICAABNQAECgkJJgAcACEPAA==.Seräph:BAABNQAECn8VAAILAAYKBBPgogBQAQALAAYKBBPgogBQAQABNQAECggICwAQAAAAAA==.',
Sh='Shadowglade:BAABNQAECn88AAIaAAoKHRXmFAACAgAaAAoKHRXmFAACAgAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAABNQAECn8UAAIeAAYKiQKiNgB7AAAeAAYKiQKiNgB7AAAAAA==.Shamizzle:BAABNQAECn8bAAILAAkKjxIkYAABAgALAAkKjxIkYAABAgAAAA==.Shammydavis:BAABNQAECn8nAAIJAAkKESBzEgC5AgAJAAkKESBzEgC5AgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shiroikami:BAAANQAECgYIBwABNQADCgIIAgAQAAAAAA==.Shocknorris:BAAANQADCgYIBgAAAA==.Shrapnel:BAABNQAECn8dAAIbAAcK7QTs7AAoAQAbAAcK7QTs7AAoAQAAAA==.Shuna:BAEANQADCgYIBgABNQAECgcIJgAEALoPAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAABNQAECn8gAAIdAAgKJA02PwDCAQAdAAgKJA02PwDCAQAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sk='Skullchopper:BAAANQAECgMIAwABNQAECgcIKgAeAL4QAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAABNQAECn8sAAQTAAkKAxzkEACUAAAZAAUKvRxCjADIAQAiAAMKaxcQDADQAAATAAIKNCHkEACUAAAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAABNQAECn83AAIoAAkKiwRFBQDeAAAoAAkKiwRFBQDeAAAAAA==.',
So='Solarica:BAAANQAECgQIBwAAAA==.Solciopath:BAAANQADCggIDwABNQAECgcIJAAlAIohAA==.Solómon:BAAANQAECgQIBQAAAA==.Sorabjr:BAAANQAECgUIDgAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwAQAAAAAA==.Soulbreaker:BAABNQAECn8qAAMeAAcKvhB3NACfAQAeAAcKvhB3NACfAQAdAAEK6wfVbQAqAAAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQAECgUICQAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQAECgIIAgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgUICAAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgAQAAAAAA==.Stylemonk:BAACNQAFFH8ZAAIkAAcKuiUEAgB7AgAkAAcKuiUEAgB7AgA1AAQKf0AAAiQACgqrJpMAAHsDACQACgqrJpMAAHsDAAAA.',
Su='Sulfalloway:BAAANQAECggIEwAAAA==.Sumawfulot:BAABNQAECn8cAAIcAAgKRBw+ZABiAgAcAAgKRBw+ZABiAgAAAA==.Sunsparrow:BAAANQAECgUIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcICQAAAA==.Sweetheal:BAAANQAECgQIBAAAAA==.Swiftysarah:BAAANQADCggICAABNQAFFAYIEwAOAPwJAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECn80AAQGAAoKeR/5AgDxAgAGAAkKxB/5AgDxAgAEAAUKWQjTTwDtAAAbAAEKah0uRAFXAAAAAA==.',
['Sî']='Sîpher:BAAANQAECggICwAAAA==.',
Ta='Taeveren:BAAANQAECgYIDAAAAA==.Tamesßond:BAAANQAECgYIDgAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQAECgUIBQAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAABNQAECn8pAAIWAAcKhB6QFQBUAgAWAAcKhB6QFQBUAgAAAA==.',
Te='Teacher:BAAANQAECggIDgAAAA==.Teagan:BAAANQADCgYIEwAAAA==.Teagn:BAAANQABCgUIBgAAAA==.Teloran:BAAANQAECgIIAgAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEBNQAECn8mAAMEAAcKug/KOQCCAQAEAAcKug/KOQCCAQAGAAEKBgy9EwAyAAAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thelionheart:BAAANQAECgQIBgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAgIFQAdAGIdAA==.Thewhitelion:BAAANQAECgYIDAAAAA==.Thundermoo:BAAANQAECgIIAgAAAA==.',
Ti='Tigg:BAACNQAFFH8OAAMhAAYKTBDvBADEAQAhAAYKTBDvBADEAQAIAAEKAAAXPwAVAAA1AAQKfysAAyEACgoZIVsYAMcCACEACgoZIVsYAMcCAAMAAQoAAOTYAD0AAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgkJKQAgABQTAA==.Toshidot:BAACNQAFFH8QAAIZAAYKLxIMCgDJAQAZAAYKLxIMCgDJAQA1AAQKfyoAAhkACQqFIWEfAAcDABkACQqFIWEfAAcDAAAA.Totemtila:BAAANQAECgQIBgABNQAECgoKJwAZAFkkAA==.Totendead:BAAANQABCgMIBQAAAA==.',
Tr='Translucent:BAABNQAECn84AAIJAAkKVhCqPQChAQAJAAkKVhCqPQChAQAAAA==.Trazatra:BAABNQAECn8fAAMVAAoKpxIdIwAtAQAVAAYKLQ8dIwAtAQAUAAkK0Q27GADpAAAAAA==.Truckah:BAABNQAECn8mAAIcAAkKIQ97TACfAQAcAAkKIQ97TACfAQAAAA==.Tràvdog:BAABNQAECn8WAAIcAAgKTRDsmQDbAQAcAAgKTRDsmQDbAQAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAABNQAECgYICQAQAAAAAA==.Tuonadari:BAAANQADCgUIDQAAAA==.Tuonai:BAABNQAECn8gAAMkAAcKaQ0pIQAcAQAkAAcKaQ0pIQAcAQApAAMK/AH1LABWAAAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.Tustone:BAAANQAECgQIBQAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQAECgIIAgAAAA==.',
Ul='Ularin:BAAANQAECgUIBAAAAA==.Ultimatum:BAAANQAECgUIDwAAAA==.',
Un='Uncledaddy:BAAANQAECgUIBQAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwAQAAAAAA==.Vaelena:BAAANQADCgUIBQAAAA==.Vahla:BAAANQAECgEIAQABNQAECgkJNgAdAHgaAA==.Vailyt:BAAANQAECgUICQAAAA==.Valkuridk:BAACNQAFFH8eAAMhAAcKeybMAAAoAgAhAAcKYibMAAAoAgADAAUKJSYKAwARAgA1AAQKfzUAAyEACgrSJmQBAGsDACEACgrDJmQBAGsDAAMACArtJRglAKsCAAAA.Valorlight:BAAANQADCggICAAAAA==.Vandellor:BAAANQADCgQIBAABNQAECgoKIAASAHMlAA==.Vandy:BAABNQAECn8gAAMXAAkK4xYFSwBEAgAXAAkKARUFSwBEAgAHAAQKqRbGEgD7AAAAAA==.',
Ve='Vedo:BAACNQAFFH8PAAMEAAYKkhOfCQDQAAAEAAUKRxGfCQDQAAAbAAEKdRqoHQBkAAA1AAQKfycAAgQACgqYHhUFAMACAAQACgqYHhUFAMACAAAA.Vedora:BAABNQAECn8bAAIYAAgKmBBpLADDAQAYAAgKmBBpLADDAQAAAA==.Velf:BAAANQADCgEIAQAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.Vetro:BAAANQAECgIIAgAAAA==.Vexy:BAAANQAECgQIBAAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virelith:BAAANQAECgEIAgAAAA==.Virulent:BAAANQAECgEIAQABNQAECggIHgAYALcaAA==.Visell:BAAANQAECgEIAQAAAA==.Vissarion:BAAANQAECgIIAgAAAA==.',
Vl='Vladak:BAAANQAECgcIDgAAAA==.',
Vo='Voc:BAAANQAECggIEgAAAA==.Voz:BAAANQAECgIIAgABNQAECggIHgAYALcaAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECn8zAAIbAAoK5SBXEgBXAwAbAAoK5SBXEgBXAwAAAA==.',
Vy='Vyridiondk:BAAANQAECgUIDAAAAA==.Vyx:BAAANQAECgUICgAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Wallbeef:BAAANQAECgIIAgAAAA==.Waymán:BAAANQAECgIIAgAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wh='Whuh:BAAANQAECgUIBQAAAA==.',
Wu='Wumply:BAACNQAFFH8OAAIYAAUKyQpYCQBuAQAYAAUKyQpYCQBuAQA1AAQKfyMAAhgACQqAFCohAC4CABgACQqAFCohAC4CAAAA.',
['Wà']='Wàyman:BAAANQAECgMIBQAAAA==.',
['Wä']='Wäyman:BAABNQAECn80AAIKAAgK7BXDEgA9AgAKAAgK7BXDEgA9AgAAAA==.',
Xa='Xaranthia:BAABNQAECn8UAAIdAAkKOAmhQQCzAQAdAAkKOAmhQQCzAQAAAA==.',
Xe='Xenra:BAAANQAECgEIAQAAAA==.',
Xm='Xmcdizzle:BAABNQAECn8fAAIOAAkK7hXMxgD3AQAOAAkK7hXMxgD3AQAAAA==.',
Xy='Xylarra:BAABNQAECn82AAMdAAkKeBqmFgD0AQAdAAkKeBqmFgD0AQAeAAIK/BcdXwB1AAAAAA==.',
Ya='Yautja:BAABNQAECn8uAAIEAAkKFBViLADoAQAEAAkKFBViLADoAQAAAA==.Yazule:BAABNQAECn8dAAIJAAgK9xjYVgANAgAJAAgK9xjYVgANAgAAAA==.',
Yo='Yodawg:BAABNQAECn8fAAIIAAgKiRhNPgAIAgAIAAgKiRhNPgAIAgAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgcIFwAUAFIMAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECgoKKAAPAHkbAA==.',
Za='Zairroth:BAAANQADCgYIBwAAAA==.Zamali:BAABNQAECn8hAAIIAAgKLAueYgBnAQAIAAgKLAueYgBnAQAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQAQAAAAAA==.Zartella:BAAANQAECgUICAABNQAECgYICwAQAAAAAA==.Zaxon:BAAANQAECgQIBQAAAA==.',
Ze='Zendraza:BAABNQAECn8iAAIVAAkKmAQSDQAKAQAVAAkKmAQSDQAKAQAAAA==.Zephyrion:BAACNQAFFH8QAAIIAAQKJRBcFgD7AAAIAAQKJRBcFgD7AAA1AAQKfzMAAggACgp+G4IhAKgCAAgACgp+G4IhAKgCAAE1AAQKCgoeABYA0wwA.Zepplin:BAABNQAECn8eAAIGAAkKWBGoAwDgAQAGAAkKWBGoAwDgAQAAAA==.Zerenity:BAAANQAECgUIBwAAAA==.Zetro:BAABNQAECn84AAIWAAoKLAzmFgBLAQAWAAoKLAzmFgBLAQAAAA==.',
Zr='Zreydyn:BAAANQADCgcIFQAAAA==.',
Zu='Zuma:BAABNQAECn8wAAINAAkK+hZTCQBBAgANAAkK+hZTCQBBAgAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
