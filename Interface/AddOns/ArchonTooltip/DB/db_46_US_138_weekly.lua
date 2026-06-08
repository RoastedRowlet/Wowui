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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Paladin-Holy','Evoker-Devastation','Priest-Discipline','Paladin-Protection','Rogue-Outlaw','DemonHunter-Vengeance','DeathKnight-Frost','Shaman-Enhancement','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarix:BAAALgAECgkJEwAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMBAAcJrxAqUgBcAQABAAcJrxAqUgBcAQACAAMJTQGHgABFAAAAAA==.Aendillan:BAAALgAECgYJEAAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn8uAAIDAAkJpAqFXwCiAQADAAkJpAqFXwCiAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJBwAAAA==.Aileen:BAAALgAFFAEJAQAAAA==.',
Ak='Akashi:BAAALgAECgUJCwABLgAFFAMJEQAEAO0hAA==.',
Al='Alacrodie:BAAALgAECgEJAQAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAFAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECggJNwAGAKwYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8nAAIHAAkJxh9YBQDMAgAHAAkJxh9YBQDMAgAAAA==.',
Ar='Aragorno:BAABLgAECn8rAAMIAAkJjRY/JQBBAgAIAAkJjRY/JQBBAgAJAAQJRAZTPwDBAAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn8rAAIIAAgJDxp4LgAXAgAIAAgJDxp4LgAXAgAAAA==.Arenthal:BAAALgAECgUJCgAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgkJMwAKAIQbAA==.Ashiera:BAABLgAECn8yAAMLAAkJ+gMEogAzAQALAAkJ+gMEogAzAQAMAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgcJDgAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAEAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgQJBAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJRQANAGMdAA==.Bahaana:BAAALgAECgUJBQAAAA==.Balentine:BAABLgAECn8cAAMKAAcJjRPHSQASAQAKAAYJZRPHSQASAQAOAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJQwAPAKUjAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9FAAINAAkJYx15CQC6AgANAAkJYx15CQC6AgAAAA==.Baspir:BAABLgAECn8pAAIQAAkJNxZHIgCqAQAQAAkJNxZHIgCqAQAAAA==.',
Be='Beeboop:BAAALgADCggJDAAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAEAJ8fAA==.Belrae:BAACLgAFFH8GAAIRAAIJ0QZufQB1AAARAAIJ0QZufQB1AAAuAAQKfzUAAhEACQl0FrIjADYCABEACQl0FrIjADYCAAAA.Belrinthe:BAAALgAECgcJBwAAAA==.Bezieck:BAABLgAECn80AAIOAAgJPxXzHADWAQAOAAgJPxXzHADWAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAILAAkJ8w3HWQDKAQALAAkJ8w3HWQDKAQAAAA==.Birdbrain:BAAALgAFFAIJAgAAAA==.Biru:BAAALgAECgIJBAABLgAECggJIQAKACUcAA==.',
Bl='Bloodarrow:BAAALgAECgYJEQAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMSAAYJ5RdHNQCIAQASAAYJ5RdHNQCIAQATAAEJaRXNiwA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQUAAcJ3RtAJgAfAgAUAAcJ3RtAJgAfAgAQAAYJ5xduMQBIAQAVAAEJnAwKdwAcAAAAAA==.Bordrann:BAAALgAECgIJAgAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgcJCwABLgAECgkJBwAFAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAITAAUJbAmQGwDqAAATAAUJbAmQGwDqAAAuAAQKfzQAAhYACQktHw8IAKsCABYACQktHw8IAKsCAAAA.Brewzer:BAACLgAFFH8PAAISAAQJkgRzOQCdAAASAAQJkgRzOQCdAAAuAAQKfyUAAxIACAmEE6wyAJUBABIACAmEE6wyAJUBABMABQmtDLRSALIAAAAA.Brint:BAABLgAECn8ZAAIPAAgJfwzWdgBHAQAPAAgJfwzWdgBHAQAAAA==.Brok:BAAALgAECgYJBwAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8vAAILAAYJTCTtGQAHAgALAAYJTCTtGQAHAgAuAAQKfyIAAgsACAkXJdEjAOMCAAsACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECggJKQACADAYAA==.Broomhandle:BAABLgAECn8fAAIXAAkJbCPfBwAlAwAXAAkJbCPfBwAlAwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8eAAIYAAYJZh/uBwDAAQAYAAYJZh/uBwDAAQAuAAQKfxkAAxgABwl/IyskADUCABgABwl/IyskADUCABkAAgnfGNcrAJUAAAAA.Burinn:BAAALgAECgYJBwABLgAECgkJRwAKAAEPAA==.',
Ca='Caeus:BAABLgAECn8wAAIDAAkJnyRXBgBBAwADAAkJnyRXBgBBAwAAAA==.Cam:BAABLgAECn8xAAILAAkJlCWiCgAfAwALAAkJlCWiCgAfAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJDwAFAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAgJFgAaABgZAA==.Care:BAABLgAECn8ZAAILAAkJjAwciADBAQALAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAABLgAECn8bAAIbAAYJwBIgJQD7AAAbAAYJwBIgJQD7AAAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJCgAAAA==.Chelan:BAABLgAECn9HAAMKAAkJAQ/wJgCAAQAKAAgJBRDwJgCAAQAOAAkJjgXwNQA2AQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJBgAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAgJHwALAIceAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8eAAIPAAcJBwjelgAKAQAPAAcJBwjelgAKAQAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8LAAIHAAQJgBAqGwD4AAAHAAQJgBAqGwD4AAAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJLAAXAAggAA==.',
Co='Codythedead:BAABLgAFFH8FAAIDAAIJ7RTRxACPAAADAAIJ7RTRxACPAAAAAA==.Compadre:BAABLgAECn8XAAQTAAgJPh7NHQDrAQATAAcJ0RrNHQDrAQAWAAQJUiAiRAAyAQASAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8gAAMUAAcJxBH3YwD/AAAUAAYJrhD3YwD/AAAQAAcJxAb1UgC0AAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8mAAIBAAcJ5SChAgCWAgABAAcJ5SChAgCWAgAuAAQKfzgAAgEACQkAJMABAHQDAAEACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIcAAcJww3dDgAtAQAcAAcJww3dDgAtAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIcAAcJMQWEEgDyAAAcAAcJMQWEEgDyAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQPAAkJayPvDQDXAgAPAAkJ5iHvDQDXAgAdAAYJWSIrCQDCAQAeAAEJAABpUAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIDAAkJGxuHLABFAgADAAkJGxuHLABFAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgEJAQAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgADCgEJAQAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8iAAMEAAgJJwpFKgA2AQAEAAgJ0AlFKgA2AQAcAAUJNAeRFgC5AAAAAA==.',
De='Deadlyfrosty:BAABLgAECn8XAAIDAAYJ/QIeDAGMAAADAAYJ/QIeDAGMAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgUJBwAFAAAAAA==.Debixie:BAACLgAFFH8SAAIcAAQJyB1kAgCHAQAcAAQJyB1kAgCHAQAuAAQKfyUAAhwACQlLI04BACUDABwACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMRAAkJQSI7FACXAgARAAgJZCI7FACXAgAfAAEJTCG3UABhAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgAMAOYgAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJQwAPAKUjAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIIAAkJ5h9NDgDKAgAIAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAIPAAkJqhTMOQDuAQAPAAkJqhTMOQDuAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8gAAMPAAcJMRVeJACXAQAPAAYJWxheJACXAQAeAAEJXQXAIABPAAAuAAQKfzUAAw8ACQnvH40OANMCAA8ACQnvH40OANMCAB4AAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECggJFgAgAMASAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAIPAAYJUhYPdQBKAQAPAAYJUhYPdQBKAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgAECgEJAQAAAA==.Dryan:BAAALgAECgYJEQAAAA==.Dryon:BAABLgAECn8uAAIbAAgJIRyCDAAYAgAbAAgJIRyCDAAYAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIIAAkJXBMfQQDTAQAIAAkJXBMfQQDTAQAAAA==.Duragon:BAABLgAECn8yAAQNAAkJ7RaSFwATAgANAAkJ7RaSFwATAgAhAAgJPwXfFAC2AAAGAAYJPweoJQC0AAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIRAAYJ6RBJeAA+AQARAAYJ6RBJeAA+AQABLgAFFAMJBQAIAFsaAA==.',
Eg='Eggwho:BAAALgAFFAMJAwAAAA==.',
Em='Emilia:BAABLgAECn8cAAIKAAkJ+wrWKQBrAQAKAAkJ+wrWKQBrAQAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8xAAMiAAkJPw87GQD5AQAiAAkJPw87GQD5AQAOAAIJ6AlnaABoAAAAAA==.English:BAABLgAECn8zAAILAAkJdBuPNAA/AgALAAkJdBuPNAA/AgAAAA==.',
Er='Erelios:BAABLgAECn8uAAIjAAkJgx7hBACeAgAjAAkJgx7hBACeAgAAAA==.',
Es='Eski:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAEALgAECgMJAwABLgAECgkJMQAgACYmAA==.',
Ev='Evangelina:BAACLgAFFH8gAAMNAAgJoBsrBwBmAgANAAgJoBsrBwBmAgAhAAEJygr9CQBTAAAuAAQKfygAAw0ACQmjJdABAGUDAA0ACQmjJdABAGUDACEABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECgkJJgAVAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Ez='Ezrì:BAAALgAECgEJAQAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIIAAkJSxZ0NgD4AQAIAAkJSxZ0NgD4AQAAAA==.Fastbeefball:BAAALgADCggJDAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAgJIAANAKAbAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgEJAQAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAgJHwALAIceAA==.Fish:BAACLgAFFH8lAAIOAAcJ8iY3AQCvAgAOAAcJ8iY3AQCvAgAuAAQKfzcAAg4ACAmOJlYCAIwDAA4ACAmOJlYCAIwDAAEuAAUUCAkuAA4AbiYA.',
Fl='Flight:BAACLgAFFH8RAAMEAAMJ7SEGIQAEAQAEAAMJ7SEGIQAEAQAkAAIJFRRLCwCYAAAuAAQKfx0AAwQACAkRHHcUAG8CAAQACAljG3cUAG8CABwAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMBAAkJmgiiUgBaAQABAAkJmgiiUgBaAQACAAYJCQWjYgCtAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAABLgAFFH8MAAIIAAQJrhzKJABeAQAIAAQJrhzKJABeAQAAAA==.Forsynth:BAABLgAECn8mAAMMAAkJ5iDFAADkAgAMAAkJ5iDFAADkAgALAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMBAAkJgh6NFACbAgABAAkJgh6NFACbAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8WAAIRAAcJjRLUXABmAQARAAcJjRLUXABmAQAAAA==.',
Gl='Glinda:BAAALgAECgEJAgAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8lAAILAAcJJh6/DgBaAgALAAcJJh6/DgBaAgAuAAQKf1kAAgsACQkmJlIDAMoDAAsACQkmJlIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJQwAPAKUjAA==.Grazienne:BAAALgAECgEJAgAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIVAAkJhx9aBQCoAgAVAAkJhx9aBQCoAgAAAA==.Grimbaine:BAABLgAECn8vAAIXAAkJSCJTCQAWAwAXAAkJSCJTCQAWAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimmshady:BAAALgAECgEJAQAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAABLgAECn8hAAMKAAgJJRzYEQBFAgAKAAgJJRzYEQBFAgAOAAEJ1AOXZwAqAAAAAA==.Gurney:BAABLgAECn8qAAMgAAkJ/hbcGwAaAgAgAAkJ/hbcGwAaAgAjAAEJggSCVAAdAAAAAA==.Guzfu:BAABLgAECn8UAAITAAcJgg3lRQDaAAATAAcJgg3lRQDaAAAAAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn82AAMWAAgJoR5SDABoAgAWAAgJoR5SDABoAgATAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgEJAgAAAA==.Happyelf:BAAALgAECgYJCgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8YAAIBAAgJFw6CVABTAQABAAgJFw6CVABTAQAAAA==.Hexxiz:BAAALgAECgIJBAABLgAECgkJMQAUAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8sAAMYAAgJHCWdDACaAgAYAAgJViOdDACaAgAbAAYJ/SSPDgDzAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEwAAAA==.Holyterror:BAAALgAECgEJAgAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCgAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn8pAAIMAAgJwAg6BwAuAQAMAAgJwAg6BwAuAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn8wAAQeAAcJryMvCwB/AQAeAAUJHCQvCwB/AQAdAAYJURnVDQBrAQAPAAQJjB3UeABCAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgADCgcJBwAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAgJIAANAKAbAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgYJCwAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAFAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMKAAkJHSAxBQAhAwAKAAkJHSAxBQAhAwAiAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgADCgQJBAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8OAAMdAAQJxhhWBABAAQAdAAQJxhhWBABAAQAPAAEJlA0xuABFAAAuAAQKfzQABB0ACQmXISUEAFMCAB0ACQmXISUEAFMCAA8ABgkyGDhMALEBAB4AAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJDgABLgAECggJFgAgAMASAA==.Jaylinn:BAABLgAECn8uAAIIAAkJ4Q3YTQCsAQAIAAkJ4Q3YTQCsAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.',
Ji='Jimsonweed:BAAALgAECgQJBAAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8nAAIiAAgJuCT4BwDuAgAiAAgJuCT4BwDuAgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8nAAIgAAgJNR1FEQCBAgAgAAgJNR1FEQCBAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBgAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8rAAMCAAgJzRTGJQCtAQACAAgJzRTGJQCtAQABAAUJfAmWgQDLAAAAAA==.Kaleberry:BAABLgAECn8bAAMQAAkJDQyeLABkAQAQAAcJYw2eLABkAQAUAAYJYAmlhgDJAAAAAA==.Kalyandra:BAABLgAECn8gAAITAAcJ2w6tNAAkAQATAAcJ2w6tNAAkAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAAALgAECgYJEQABLgAECgkJKAAjAEAiAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIYAAkJAh1aFQA+AgAYAAkJAh1aFQA+AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8iAAIRAAgJsBePLwD9AQARAAgJsBePLwD9AQAAAA==.Karumie:BAABLgAECn8nAAIBAAkJZhydHQBTAgABAAkJZhydHQBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJNgAPAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgEJAQAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8WAAIZAAgJXSEKBQC0AgAZAAgJXSEKBQC0AgABLgAECgkJLAARAEEiAA==.Kels:BAABLgAECn8sAAIRAAkJQSIPDADeAgARAAkJQSIPDADeAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIVAAkJzRMBEQDJAQAVAAkJzRMBEQDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJQwAPAKUjAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgEJAQAAAA==.Kopi:BAAALgAECgMJAwABLgAECgkJJwAHAMYfAA==.Korlatt:BAABLgAECn84AAQRAAgJ5x2RIQBCAgARAAgJTRyRIQBCAgAlAAMJDRzdFQDqAAAfAAMJOhYFUQBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgAHAAQJPwrvSABfAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAALADgXAA==.',
Kt='Kthanid:BAABLgAECn8VAAIiAAYJoQ9YPwD/AAAiAAYJoQ9YPwD/AAAAAA==.',
Ku='Kurston:BAABLgAECn9CAAIUAAkJxxqkEgCuAgAUAAkJxxqkEgCuAgAAAA==.',
Ky='Kymakazie:BAAALgAECggJEwAAAA==.',
['Kã']='Kãtniss:BAAALgAECgEJAQAAAA==.',
La='Laih:BAABLgAECn8iAAIcAAkJgA9JCAC/AQAcAAkJgA9JCAC/AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJIwASAAMZAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Lauraenital:BAAALgADCgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAWAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn82AAIBAAkJiREuLQD2AQABAAkJiREuLQD2AQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgEJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMTAAYJZBofNABRAQATAAUJkxYfNABRAQAWAAQJ+xkLRgAqAQABLgAECggJGAAHAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAIRAAkJtheaIwA2AgARAAkJtheaIwA2AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8bAAMOAAgJwwb7OgAeAQAOAAgJwwb7OgAeAQAKAAMJfwMSZgA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgYJBwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8iAAIXAAkJoQ5mXgCqAQAXAAkJoQ5mXgCqAQAAAA==.Lynniebee:BAABLgAECn8pAAIMAAkJjAyrBACYAQAMAAkJjAyrBACYAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPgAlANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8eAAMnAAkJTg7NDwCnAQAnAAkJTg7NDwCnAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAABLgAECn8tAAIgAAkJ4yH5AgBuAwAgAAkJ4yH5AgBuAwAAAA==.Matthad:BAABLgAECn8uAAIBAAkJhRQLJQAjAgABAAkJhRQLJQAjAgAAAA==.Mazìkene:BAACLgAFFH8WAAMdAAUJ8ww4CADrAAAPAAQJ0gdRYAD2AAAdAAQJUQ84CADrAAAuAAQKfyYAAw8ACQkuF7ZLALIBAA8ACQk2FrZLALIBAB0ABQlSHAIQAE0BAAAA.',
Mc='Mccone:BAABLgAECn8XAAIIAAYJZgklsQDQAAAIAAYJZgklsQDQAAAAAA==.Mcsluts:BAABLgAECn8aAAMXAAYJXQlg3gDTAAAXAAYJ0Qdg3gDTAAAjAAEJaBB2TwApAAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAgJIAANAKAbAA==.Melmirict:BAACLgAFFH8SAAIEAAUJWBLnHAAoAQAEAAUJWBLnHAAoAQAuAAQKfyUAAwQACQlQGWkSAAcCAAQACQlQGWkSAAcCABwAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9CAAIVAAkJDhJnFgCMAQAVAAkJDhJnFgCMAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgEJAgAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJHwAXAGwjAA==.Missmurder:BAAALgAECgEJAQAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn82AAQPAAkJmRo9KQAwAgAPAAgJSxw9KQAwAgAdAAIJkg7NNwA5AAAeAAIJuw5VOwAzAAAAAA==.Mohawk:BAAALgAECgUJBgABLgAECgYJCgAFAAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMIAAkJrh+LMwADAgAJAAgJmBl7EQAbAgAIAAgJIB6LMwADAgAAAA==.Molen:BAAALgAECgUJBwAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAgJIAANAKAbAA==.Monkle:BAABLgAECn9LAAITAAkJ/CSIAQBcAwATAAkJ/CSIAQBcAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAQJDQAEAHcbAA==.Moonsii:BAABLgAECn8aAAIUAAkJ9Q2SOwCdAQAUAAkJ9Q2SOwCdAQAAAA==.Mooroth:BAABLgAECn9AAAIbAAgJ3h9qBwCAAgAbAAgJ3h9qBwCAAgABLgAFFAIJAgAFAAAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAABLgAECn8cAAImAAcJExyMCgDCAQAmAAcJExyMCgDCAQAAAA==.',
Mu='Muddler:BAABLgAECn9AAAIeAAgJYgNmHQCzAAAeAAgJYgNmHQCzAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgADCgcJBwAAAA==.',
Na='Nadd:BAABLgAECn8eAAIIAAcJtgpkeQA/AQAIAAcJtgpkeQA/AQAAAA==.Naledi:BAABLgAECn8cAAIQAAgJ5Q/6MABLAQAQAAgJ5Q/6MABLAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn81AAILAAkJtyAnEwDhAgALAAkJtyAnEwDhAgAAAA==.Narella:BAABLgAECn8tAAILAAgJjRS7XwC6AQALAAgJjRS7XwC6AQAAAA==.',
Ne='Negotiable:BAAALgADCgQJCAAAAA==.Negrido:BAABLgAECn8zAAQPAAkJ+yWvDQDZAgAPAAgJwSKvDQDZAgAeAAMJNiWJJAA3AQAdAAEJvx9BLQBbAAAAAA==.Nei:BAABLgAECn8xAAIXAAgJuBgWOgAQAgAXAAgJuBgWOgAQAgAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn82AAMQAAkJ6BnhDwBXAgAQAAkJ6BnhDwBXAgAVAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8xAAMgAAgJBh0nEQCCAgAgAAgJBh0nEQCCAgAXAAQJewTyPQFgAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgAVAM0TAA==.Noriyuki:BAABLgAECn8uAAITAAcJDgJ3fQBOAAATAAcJDgJ3fQBOAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAgJHwALAIceAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8HAAMJAAQJFhV+FAAcAQAJAAQJFhV+FAAcAQAaAAEJwAG6NgAtAAAuAAQKfxcAAwkACAlSI5wJAIACAAkACAlSI5wJAIACABoAAwnADI9pAJgAAAEuAAQKCAkOAAUAAAAA.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgADCgQJBAABLgAECggJMQAUAD4SAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn83AAIfAAkJiBBAGACxAQAfAAkJiBBAGACxAQAAAA==.Oluja:BAAALgAECgYJCQAAAA==.',
Om='Omegâ:BAAALgAECgYJCQABLgAECggJEAAFAAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIAAIAHQXAA==.Oppressin:BAAALgADCggJDAABLgAECgkJIAAIAHQXAA==.Oppshot:BAABLgAECn8gAAMIAAkJdBeXJgA6AgAIAAkJdBeXJgA6AgAaAAEJUAnGOwAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIgAAMJFxE8LgCxAAAgAAMJFxE8LgCxAAAuAAQKfykAAiAACQnbIVAMALgCACAACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMDAAkJYx5EKABYAgADAAkJYx5EKABYAgAHAAUJHAYsQACEAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8jAAIXAAcJKRs0CwD5AQAXAAcJKRs0CwD5AQAuAAQKfysAAhcACQkbJWMBANEDABcACQkbJWMBANEDAAAA.Palykat:BAABLgAECn8nAAIXAAgJGwjlpgAhAQAXAAgJGwjlpgAhAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIDAAkJUyAsGQCoAgADAAkJUyAsGQCoAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgADAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMVAAkJiBfqEQC9AQAVAAkJ4hbqEQC9AQAQAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8dAAMDAAkJqQ5NYACgAQADAAgJ8w9NYACgAQAHAAEJowVcWAAxAAABLgAECggJNgAWAKEeAA==.Ploofee:BAAALgAECggJDwAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8UAAILAAgJ5hFVdQCIAQALAAgJ5hFVdQCIAQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIQAAkJ2QnrNQAwAQAQAAkJ2QnrNQAwAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAFAAAAAA==.',
Qa='Qaren:BAABLgAECn8VAAIXAAYJ9AXfHQGFAAAXAAYJ9AXfHQGFAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgADCgYJBgAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSD1BQB/AgAoAAkJFB/1BQB/AgAVAAEJQh3lVgBQAAAQAAIJ6wczeQBIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAILAAMJyApGgwDKAAALAAMJyApGgwDKAAAuAAQKfxUAAgsACAkiFJ5ZAMoBAAsACAkiFJ5ZAMoBAAEuAAUUBAkOAB0AxhgA.Ratabi:BAAALgADCgIJAgAAAA==.Ravna:BAAALgAECgMJAwABLgAECgkJOAAQAI8aAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJMgABAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNQAAAQ==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAQAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAILAAQJUSK8PABpAQALAAQJUSK8PABpAQAuAAQKfxwAAgsACQmKIWQUANoCAAsACQmKIWQUANoCAAAA.Rhetegast:BAABLgAECn8oAAIjAAkJrRPHDwDIAQAjAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECggJFgAgAMASAA==.',
Ri='Rike:BAEBLgAECn83AAMXAAkJbSFtIgByAgAXAAkJlSBtIgByAgAjAAYJMR5xEACvAQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAFAAAAAA==.Roflhazotime:BAABLgAECn8nAAIRAAkJVyPICAAAAwARAAkJVyPICAAAAwAAAA==.Roland:BAABLgAECn8vAAMUAAgJ0xLCPwCKAQAUAAgJ0xLCPwCKAQAQAAYJOwuQZwBvAAAAAA==.Rolandin:BAABLgAECn83AAIgAAkJ0xeoEQB9AgAgAAkJ0xeoEQB9AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgQJCwAAAA==.Rook:BAABLgAFFH8JAAIEAAQJfxTrFwBEAQAEAAQJfxTrFwBEAQABLgAFFAcJJgABAOUgAA==.Roscjou:BAABLgAECn8UAAICAAYJtwRwZQCmAAACAAYJtwRwZQCmAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJNgAPAJkaAA==.',
Ry='Rylagosa:BAABLgAECn83AAMGAAgJrBgADwDTAQAGAAcJNxgADwDTAQANAAgJ+REzMQBnAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8XAAILAAkJGRG0UwDbAQALAAkJGRG0UwDbAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8GAAIDAAMJrgu6mQDQAAADAAMJrgu6mQDQAAABLgAFFAUJFgAdAPMMAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn8xAAIUAAgJPhKQOACrAQAUAAgJPhKQOACrAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwABAEscAA==.Sarvinblue:BAABLgAECn8rAAMBAAkJSxydFACaAgABAAkJSxydFACaAgACAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanaynay:BAAALgADCgUJBgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIcAAcJkAaPEgDxAAAcAAcJkAaPEgDxAAAAAA==.Shazlulu:BAABLgAECn8gAAIBAAcJmBsCKwAAAgABAAcJmBsCKwAAAgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8hAAIMAAgJzwojBwAyAQAMAAgJzwojBwAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIEAAkJnx/aDQA+AgAEAAkJnx/aDQA+AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIgAAkJtxl/FABfAgAgAAkJtxl/FABfAgAAAA==.Sloe:BAABLgAECn8zAAIKAAkJhBueDwBgAgAKAAkJhBueDwBgAgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgADCgQJBAAAAA==.Speedkweef:BAAALgAECggJDgAAAA==.Speedmeat:BAABLgAECn8bAAMBAAkJAghDZAAfAQABAAgJtgdDZAAfAQACAAIJmAOykwA+AAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAABLgAECn8vAAMIAAgJfxOWRADIAQAIAAgJfxOWRADIAQAaAAEJFwEqRAAQAAAAAA==.',
Sq='Squal:BAABLgAECn8sAAMXAAkJCCCZFwCsAgAXAAkJCCCZFwCsAgAjAAUJ/BjQGQA+AQAAAA==.Squiggle:BAABLgAECn87AAIjAAgJMSE3BQCUAgAjAAgJMSE3BQCUAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBwAAAA==.Stickybunz:BAABLgAECn8ZAAIYAAgJURW/IwDQAQAYAAgJURW/IwDQAQABLgAFFAQJCwAKAAAJAA==.Striker:BAEALgAECgQJDwABLgAECgkJNwAXAG0hAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAFAAAAAA==.Stunseed:BAABLgAECn8rAAIVAAkJ1hhICgAvAgAVAAkJ1hhICgAvAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgUJBQAAAA==.Sunshíne:BAABLgAECn8ZAAMXAAgJoQjipQAiAQAXAAgJQQfipQAiAQAjAAIJ4QzhPABeAAAAAA==.Surf:BAAALgAECgcJEwAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8LAAMKAAQJAAnrGgDPAAAKAAQJAAnrGgDPAAAOAAEJbQJFOwA0AAAuAAQKfzoAAw4ACQnHFncVABgCAA4ACQnHFncVABgCAAoACAlYDuAuAEgBAAAA.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMDAAkJ2BmHQwDwAQADAAgJGxuHQwDwAQAHAAEJCRFCUwA/AAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgYJDwAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgYJDwAFAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJBwAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJNgAPAJkaAA==.Taniss:BAABLgAECn8pAAIkAAkJlQgNCwBgAQAkAAkJlQgNCwBgAQAAAA==.Tanner:BAABLgAECn8cAAMaAAgJDgnESgAnAQAaAAgJwQfESgAnAQAIAAIJoBF5ogCHAAAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8tAAMCAAgJ0hniGAAOAgACAAgJ0hniGAAOAgABAAMJmgdWjwBaAAAAAA==.Temel:BAABLgAECn8yAAMBAAkJfQ6XSQB7AQABAAgJtwyXSQB7AQACAAkJUw0EMQBsAQAAAA==.Tenelum:BAAALgAECgIJBQABLgAECgkJMgABAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAFAAAAAA==.',
Th='Thadrack:BAABLgAECn8wAAILAAgJtAZ1oQA0AQALAAgJtAZ1oQA0AQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAFAAAAAA==.Thalonstin:BAAALgAECgIJBAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAFFAMJAwABLgAECgcJDQAFAAAAAA==.Theodrid:BAACLgAFFH8QAAIXAAYJwBQbNwAuAQAXAAYJwBQbNwAuAQAuAAQKfyMAAhcACQmhHjAkAJcCABcACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAIPAAgJWAUGlgAsAQAPAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.Thutpithyuth:BAACLgAFFH8FAAIIAAMJWxq9TgD3AAAIAAMJWxq9TgD3AAAuAAQKfxcAAggACQkgHxQPAM8CAAgACQkgHxQPAM8CAAAA.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQTAAkJ9RwGGADmAQATAAgJ0BwGGADmAQAWAAQJQRmWTgAJAQASAAUJ2QwvYADZAAAAAA==.Tirzahdozier:BAABLgAECn8WAAMgAAgJwBJwJADYAQAgAAgJwBJwJADYAQAXAAEJXwLqtwEYAAAAAA==.Tiwohnne:BAAALgAECgYJCAAAAA==.',
Tl='Tla:BAAALgAECgEJAgAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9CAAIOAAkJByECBAAYAwAOAAkJByECBAAYAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8OAAICAAQJlxxVFwBKAQACAAQJlxxVFwBKAQABLgAFFAkJQwAPAKUjAA==.Tristitia:BAABLgAECn8qAAIDAAkJzBVmNAAlAgADAAkJzBVmNAAlAgAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIDAAkJAxy/KQBSAgADAAkJAxy/KQBSAgAAAA==.Turkeltin:BAAALgAECgYJEAAAAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAECggJFgAgAMASAA==.',
Ty='Tyche:BAABLgAECn8XAAMBAAYJcg25agALAQABAAYJcg25agALAQACAAEJ2gHztgAYAAAAAA==.Tysbich:BAAALgAECgQJBAABLgAECgkJLQAgAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIUAAkJWSSlAgCbAwAUAAkJWSSlAgCbAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ9BCzUwDBAQADAAkJ9BCzUwDBAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMeAAYJJhD1HgBZAQAeAAYJJhD1HgBZAQAPAAIJ4gHuLwEhAAAAAA==.Vaelrieth:BAAALgAECggJEgAAAA==.Vains:BAACLgAFFH8RAAIXAAUJkRxfMQA7AQAXAAUJkRxfMQA7AQAuAAQKfyIAAhcACQkzIZ8jAGwCABcACQkzIZ8jAGwCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Vardis:BAABLgAECn8uAAILAAkJMh/FJwB1AgALAAkJMh/FJwB1AgAAAA==.',
Ve='Velinami:BAAALgAECgIJAgAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJMgABAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAAALgAFFAIJAgAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8zAAILAAkJUR6/FgDKAgALAAkJUR6/FgDKAgAAAA==.Verren:BAABLgAECn8rAAIVAAkJFBr9CABLAgAVAAkJFBr9CABLAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAIPAAkJjhwxJgA/AgAPAAkJjhwxJgA/AgAAAA==.',
We='Weltamus:BAABLgAECn8lAAMDAAkJPhZHbACEAQADAAgJyg9HbACEAQAHAAQJdR3yHgBRAQAAAA==.Weltasaur:BAABLgAECn8bAAIVAAYJAxhDJAAcAQAVAAYJAxhDJAAcAQAAAA==.Weltazar:BAABLgAECn8vAAICAAgJ4hMSOQBDAQACAAgJ4hMSOQBDAQAAAA==.Westside:BAACLgAFFH8fAAMLAAgJhx7JBwCeAgALAAgJhx7JBwCeAgAMAAEJqAkQBgA+AAAuAAQKfyMAAgsACQnVJhABAJADAAsACQnVJhABAJADAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAAPAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hh3BwBRAgAoAAkJ5hh3BwBRAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQcAAkJ8B42AgC3AgAcAAkJ8B42AgC3AgAEAAMJoAfkUACkAAAkAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAgABLgAECgkJMgABAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAFAAAAAA==.Xalreth:BAABLgAECn8gAAIRAAkJPg5AWAByAQARAAkJPg5AWAByAQAAAA==.Xaviana:BAAALgAECggJKAAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMOAAkJOQh3NgA0AQAOAAgJOAd3NgA0AQAKAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIRAAkJ0BgPLwBAAgARAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIgAAkJJiYaBwASAwAgAAkJJiYaBwASAwAAAA==.Yushi:BAABLgAECn8tAAIEAAkJlx8BCgB5AgAEAAkJlx8BCgB5AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJEgAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8mAAQDAAkJURTlMwAnAgADAAkJURTlMwAnAgAmAAYJKQWxJQCMAAAHAAQJYQPIRgBmAAAAAA==.Zenweaver:BAACLgAFFH8RAAIWAAMJVSRzGwA7AQAWAAMJVSRzGwA7AQAuAAQKfx8AAhYACQlqIlUEAEcDABYACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIDAAkJRiHrEQDWAgADAAkJRiHrEQDWAgAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
['Øt']='Øtherside:BAAALgAECgEJAQAAAA==.',
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
