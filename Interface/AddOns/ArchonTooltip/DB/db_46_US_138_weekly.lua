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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Evoker-Devastation','Priest-Discipline','Paladin-Protection','Paladin-Holy','Rogue-Outlaw','DemonHunter-Vengeance','DeathKnight-Frost','Shaman-Enhancement','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aarix:BAAALgAECgkJEwAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMBAAcJrxBuTQBdAQABAAcJrxBuTQBdAQACAAMJTQGHgABFAAAAAA==.Aendillan:BAAALgAECgYJEAAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn8oAAIDAAgJRgpJeQBbAQADAAgJRgpJeQBbAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJBwAAAA==.Aileen:BAAALgAECgYJCAAAAA==.',
Ak='Akashi:BAAALgAECgUJCwABLgAFFAMJDgAEAO0hAA==.',
Al='Alacrodie:BAAALgADCggJDQAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAFAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.',
An='Anahla:BAAALgADCgQJBAABLgAECggJNQAGANAZAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgEJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8hAAIHAAgJSB/ZDQARAgAHAAgJSB/ZDQARAgAAAA==.',
Ar='Aragorno:BAABLgAECn8pAAMIAAkJjRaMIQBIAgAIAAkJjRaMIQBIAgAJAAQJRAbdPADCAAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn8kAAIIAAgJ1hf4MwD2AQAIAAgJ1hf4MwD2AQAAAA==.Arenthal:BAAALgAECgUJCgAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECggJLQAKAAgcAA==.Ashiera:BAABLgAECn8yAAMLAAkJ+gPBoQAdAQALAAkJ+gPBoQAdAQAMAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgYJDAAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAEAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJHAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJOwANAGMdAA==.Bahaana:BAAALgAECgUJBQAAAA==.Balentine:BAABLgAECn8bAAMKAAcJjRPHSQASAQAKAAYJZRPHSQASAQAOAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJPgAPAKUjAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn87AAINAAkJYx3kCACyAgANAAkJYx3kCACyAgAAAA==.Baspir:BAABLgAECn8pAAIQAAkJNxbsHwCvAQAQAAkJNxbsHwCvAQAAAA==.',
Be='Beeboop:BAAALgADCgYJCgAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAEAJ8fAA==.Belrae:BAABLgAECn80AAIRAAkJdBblIAA8AgARAAkJdBblIAA8AgAAAA==.Belrinthe:BAAALgAECgcJBwAAAA==.Bezieck:BAABLgAECn8wAAIOAAgJKBRHHQC9AQAOAAgJKBRHHQC9AQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8lAAILAAgJmQ22ewBmAQALAAgJmQ22ewBmAQAAAA==.Birdbrain:BAAALgAFFAEJAQAAAA==.Biru:BAAALgAECgIJBAABLgAECggJGQAKABgbAA==.',
Bl='Bloodarrow:BAAALgAECgQJCwAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMSAAYJ5RfcMACHAQASAAYJ5RfcMACHAQATAAEJaRUBhAA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQUAAcJ3RtAJgAfAgAUAAcJ3RtAJgAfAgAQAAYJ5xchLwBJAQAVAAEJnAwHbAAeAAAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgcJCgABLgAECgkJBwAFAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAITAAUJbAmFGADvAAATAAUJbAmFGADvAAAuAAQKfzQAAhYACQktH2kHAK4CABYACQktH2kHAK4CAAAA.Brewzer:BAACLgAFFH8PAAISAAQJkgT4MQChAAASAAQJkgT4MQChAAAuAAQKfyUAAxIACAmEE18uAJYBABIACAmEE18uAJYBABMABQmtDCBOALUAAAAA.Brint:BAABLgAECn8ZAAIPAAgJfwxQcQBNAQAPAAgJfwxQcQBNAQAAAA==.Brok:BAAALgAECgYJBgAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8qAAILAAYJDyQgFAALAgALAAYJDyQgFAALAgAuAAQKfyIAAgsACAkXJdEjAOMCAAsACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECggJJwACADAYAA==.Broomhandle:BAABLgAECn8ZAAIXAAgJHCPrFACwAgAXAAgJHCPrFACwAgAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8dAAIYAAYJZh92BQDRAQAYAAYJZh92BQDRAQAuAAQKfxkAAxgABwl/IyskADUCABgABwl/IyskADUCABkAAgnfGNcrAJUAAAAA.Burinn:BAAALgAECgYJBwABLgAECgkJOgAKAO4NAA==.',
Ca='Caeus:BAABLgAECn8nAAIDAAkJkSRgBwAsAwADAAkJkSRgBwAsAwAAAA==.Cam:BAABLgAECn8xAAILAAkJlCVFCQAdAwALAAkJlCVFCQAdAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJDgAFAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAcJFQAaANYYAA==.Care:BAABLgAECn8ZAAILAAkJjAwciADBAQALAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAABLgAECn8VAAIbAAYJBhFaNwCAAAAbAAYJBhFaNwCAAAAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgAECgUJBQAAAA==.Cheesús:BAAALgAECggJCQAAAA==.Chelan:BAABLgAECn86AAMKAAkJ7g1AKABvAQAKAAgJ0Q5AKABvAQAOAAkJYgRJOgAHAQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJBgAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAgJHwALAIceAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8ZAAIPAAcJ5Qd9kQAOAQAPAAcJ5Qd9kQAOAQAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8IAAIHAAQJcw1iGwDiAAAHAAQJcw1iGwDiAAAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJKAAXAOodAA==.',
Co='Codythedead:BAABLgAFFH8FAAIDAAIJ7RRbswCRAAADAAIJ7RRbswCRAAAAAA==.Compadre:BAABLgAECn8XAAQTAAgJPh7NHQDrAQATAAcJ0RrNHQDrAQAWAAQJUiAiRAAyAQASAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8eAAMUAAcJxBFJYAADAQAUAAYJrhBJYAADAQAQAAcJxAbaTgC1AAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8kAAIBAAYJ7SAEBQA/AgABAAYJ7SAEBQA/AgAuAAQKfzgAAgEACQkAJMABAHQDAAEACQkAJMABAHQDAAAA.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIcAAcJww0LDgAzAQAcAAcJww0LDgAzAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8bAAIcAAYJjATYFADHAAAcAAYJjATYFADHAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQPAAkJayOZDADcAgAPAAkJ5iGZDADcAgAdAAYJWSI1CADIAQAeAAEJAADdTAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIDAAkJGxurKQBHAgADAAkJGxurKQBHAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgADCgQJBAAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8fAAMcAAgJHweBFQC9AAAEAAcJXQa/MwDsAAAcAAUJNAeBFQC9AAAAAA==.',
De='Deadlyfrosty:BAAALgAECgYJEQAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgQJBgAFAAAAAA==.Debixie:BAACLgAFFH8SAAIcAAQJyB39AQCNAQAcAAQJyB39AQCNAQAuAAQKfyUAAhwACQlLI04BACUDABwACQlLI04BACUDAAAA.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMRAAkJQSLwEgCXAgARAAgJZCLwEgCXAgAfAAEJTCEySwBiAAAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJPgAPAKUjAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIIAAkJ5h9NDgDKAgAIAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAIPAAkJqhTONgDxAQAPAAkJqhTONgDxAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8eAAIPAAYJWxgbHACkAQAPAAYJWxgbHACkAQAuAAQKfzUAAw8ACQnvHxYNANcCAA8ACQnvHxYNANcCAB4AAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECgcJEgAFAAAAAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAIPAAYJUhZccABPAQAPAAYJUhZccABPAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgADCgEJAQAAAA==.Dryan:BAAALgAECgQJCwAAAA==.Dryon:BAABLgAECn8tAAIbAAgJKxubDAALAgAbAAgJKxubDAALAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIIAAkJXBMnPADYAQAIAAkJXBMnPADYAQAAAA==.Duragon:BAABLgAECn8yAAQNAAkJ7RZnFgANAgANAAkJ7RZnFgANAgAgAAgJPwXYEwC7AAAGAAYJPwc/JAC1AAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIRAAYJ6RBJeAA+AQARAAYJ6RBJeAA+AQABLgAFFAMJBQAIAFsaAA==.',
Em='Emilia:BAABLgAECn8cAAIKAAkJ+wreJgB4AQAKAAkJ+wreJgB4AQAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8xAAMhAAkJPw83FwD6AQAhAAkJPw83FwD6AQAOAAIJ6AnDXwBqAAAAAA==.English:BAABLgAECn8zAAILAAkJdBs1MQA8AgALAAkJdBs1MQA8AgAAAA==.',
Er='Erelios:BAABLgAECn8lAAIiAAkJWR0pBgBwAgAiAAkJWR0pBgBwAgAAAA==.',
Es='Eski:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAEALgADCgIJAgABLgAECgkJMQAjACYmAA==.',
Ev='Evangelina:BAACLgAFFH8gAAMNAAgJoBv7BAB+AgANAAgJoBv7BAB+AgAgAAEJygr9CQBTAAAuAAQKfygAAw0ACQmjJZoBAF0DAA0ACQmjJZoBAF0DACAABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECggJJAAVAPcTAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIIAAkJSxbAMQD+AQAIAAkJSxbAMQD+AQAAAA==.Fastbeefball:BAAALgADCggJDAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAgJIAANAKAbAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgEJAQAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAgJHwALAIceAA==.Fish:BAACLgAFFH8fAAIOAAYJ9ibLAgBBAgAOAAYJ9ibLAgBBAgAuAAQKfzcAAg4ACAmOJlYCAIwDAA4ACAmOJlYCAIwDAAEuAAUUCAkqAA4AbiYA.',
Fl='Flight:BAACLgAFFH8OAAMEAAMJ7SEeHgAHAQAEAAMJ7SEeHgAHAQAkAAIJFRQwCgCYAAAuAAQKfx0AAwQACAkRHHcUAG8CAAQACAljG3cUAG8CABwAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMBAAkJmgjMTQBcAQABAAkJmgjMTQBcAQACAAYJCQXhXACyAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAABLgAFFH8IAAIIAAQJ8xm5JwBIAQAIAAQJ8xm5JwBIAQABLgAFFAYJHQAYAGYfAA==.Forsynth:BAABLgAECn8jAAMMAAkJyR/NAADWAgAMAAkJyR/NAADWAgALAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMBAAkJgh7SEgCdAgABAAkJgh7SEgCdAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8UAAIRAAcJXAsCgAAEAQARAAcJXAsCgAAEAQAAAA==.',
Gl='Glinda:BAAALgADCggJDAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8jAAILAAYJqB/eFAAGAgALAAYJqB/eFAAGAgAuAAQKf1kAAgsACQkmJlIDAMoDAAsACQkmJlIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJPgAPAKUjAA==.Grazienne:BAAALgADCgYJCgAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIVAAkJhx/HBACsAgAVAAkJhx/HBACsAgAAAA==.Grimbaine:BAABLgAECn8pAAIXAAgJhCI5FgCnAgAXAAgJhCI5FgCnAgAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimmshady:BAAALgAECgEJAQAAAA==.Grizzlegrimm:BAAALgAECgEJAQAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAABLgAECn8ZAAMKAAgJGBtfEQA/AgAKAAgJGBtfEQA/AgAOAAEJ1AOXZwAqAAAAAA==.Gurney:BAABLgAECn8qAAMjAAkJ/hZYGgAcAgAjAAkJ/hZYGgAcAgAiAAEJggQ7UAAdAAAAAA==.Guzfu:BAABLgAECn8UAAITAAcJgg25QQDfAAATAAcJgg25QQDfAAAAAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn8vAAMWAAgJkhyEDgA/AgAWAAgJkhyEDgA/AgATAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgADCgYJCgAAAA==.Happyelf:BAAALgAECgYJBgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8YAAIBAAgJFw7rTwBUAQABAAgJFw7rTwBUAQAAAA==.Hexxiz:BAAALgAECgIJBAABLgAECgkJLgAUAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8rAAMYAAgJHCUtDACSAgAYAAgJ2SItDACSAgAbAAYJ/SSfDQD4AQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEwAAAA==.Holyterror:BAAALgADCgYJCgAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCgAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn8iAAIMAAgJgAaNBwAVAQAMAAgJgAaNBwAVAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn8wAAQeAAcJryNMCgCBAQAeAAUJHCRMCgCBAQAdAAYJURmaDABvAQAPAAQJjB3sdABEAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgADCgMJAwAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAgJIAANAKAbAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgUJCQAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAFAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMKAAkJHSCcBAAoAwAKAAkJHSCcBAAoAwAhAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgADCgEJAQAAAA==.',
Ix='Ixtabay:BAACLgAFFH8NAAMdAAQJxhh4AwBFAQAdAAQJxhh4AwBFAQAPAAEJlA0YsgBFAAAuAAQKfzEABB0ACQn3IPMEACECAB0ACQn3IPMEACECAA8ABgkyGCNJALMBAB4AAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJCQABLgAECgcJEgAFAAAAAA==.Jaylinn:BAABLgAECn8uAAIIAAkJ4Q1KSACxAQAIAAkJ4Q1KSACxAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8gAAIhAAgJliOPCQC8AgAhAAgJliOPCQC8AgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8mAAIjAAgJlhxcEQB1AgAjAAgJlhxcEQB1AgAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8kAAMCAAgJjBRwJQCkAQACAAgJjBRwJQCkAQABAAIJPweNtABDAAAAAA==.Kaleberry:BAABLgAECn8WAAMUAAgJcxClhgDJAAAUAAYJYAmlhgDJAAAQAAUJjwcZYAChAAAAAA==.Kalyandra:BAABLgAECn8aAAITAAcJTgwPNgATAQATAAcJTgwPNgATAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgAECgYJEQABLgAECggJJAAiAH8gAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8cAAIYAAkJAh2nEwBBAgAYAAkJAh2nEwBBAgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8cAAIRAAgJExcIMADwAQARAAgJExcIMADwAQAAAA==.Karumie:BAABLgAECn8nAAIBAAkJZhxpGwBWAgABAAkJZhxpGwBWAgAAAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgADCgYJBwAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8WAAIZAAgJZCGjBAC3AgAZAAgJZCGjBAC3AgABLgAECgkJLAARAEEiAA==.Kels:BAABLgAECn8sAAIRAAkJQSILCwDfAgARAAkJQSILCwDfAgAAAA==.',
Kh='Kheyra:BAABLgAECn8kAAIVAAgJ9xPwFACLAQAVAAgJ9xPwFACLAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJPgAPAKUjAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgADCgUJBQAAAA==.Kopi:BAAALgAECgMJAwABLgAECggJIQAHAEgfAA==.Korlatt:BAABLgAECn8yAAQRAAgJmxxAIwAuAgARAAgJXxtAIwAuAgAlAAMJDRzSFADrAAAfAAEJUwsYcwAyAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgAHAAQJPwrkRABgAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAALADgXAA==.',
Kt='Kthanid:BAAALgAECgQJDwAAAA==.',
Ku='Kurston:BAABLgAECn84AAIUAAkJxxqqEQCvAgAUAAkJxxqqEQCvAgAAAA==.',
Ky='Kymakazie:BAAALgAECgcJDgAAAA==.',
['Kã']='Kãtniss:BAAALgADCggJDQAAAA==.',
La='Laih:BAABLgAECn8cAAIcAAkJPA8DCAC7AQAcAAkJPA8DCAC7AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJIwASAAMZAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Lauraenital:BAAALgADCgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAWAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAABLgAECn8wAAIBAAgJ7hKrMgDNAQABAAgJ7hKrMgDNAQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgADCgcJCgAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMTAAYJZBofNABRAQATAAUJkxYfNABRAQAWAAQJ+xkLRgAqAQABLgAECggJGAAHAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8kAAIRAAkJIRZNKAAUAgARAAkJIRZNKAAUAgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8aAAMOAAgJwwaWOgAGAQAOAAgJwwaWOgAGAQAKAAMJfwMsYQBBAAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgEJAQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8iAAIXAAkJoQ5MWACqAQAXAAkJoQ5MWACqAQAAAA==.Lynniebee:BAABLgAECn8pAAIMAAkJjAw0BACkAQAMAAkJjAw0BACkAQAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPgAlANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8bAAMnAAkJdw09DwCeAQAnAAkJdw09DwCeAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAABLgAECn8mAAIjAAkJOyGlAwBWAwAjAAkJOyGlAwBWAwAAAA==.Matthad:BAABLgAECn8lAAIBAAkJhRS+IgAkAgABAAkJhRS+IgAkAgAAAA==.Mazìkene:BAACLgAFFH8RAAIPAAQJ0gcBWAAAAQAPAAQJ0gcBWAAAAQAuAAQKfyYAAw8ACQkuFypHALkBAA8ACQk2FipHALkBAB0ABQlSHLgOAE8BAAAA.',
Mc='Mccone:BAAALgAECgYJEQAAAA==.Mcsluts:BAAALgAECgQJEgAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAgJIAANAKAbAA==.Melmirict:BAACLgAFFH8OAAIEAAQJWBJcGgAoAQAEAAQJWBJcGgAoAQAuAAQKfyAAAwQACQlQGdQaAKgBAAQACQlQGdQaAKgBABwAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn84AAIVAAkJDhJHFACSAQAVAAkJDhJHFACSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgADCgYJCQAAAA==.Minaby:BAAALgAECgYJEAABLgAECggJGQAXABwjAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8wAAQPAAgJwhZ/XAB+AQAPAAcJGRh/XAB+AQAdAAIJkg5wNAA5AAAeAAIJuw5JOAAzAAAAAA==.Mohawk:BAAALgAECgQJBQABLgAECgYJCgAFAAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgADCgIJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8gAAMJAAgJBh15EAAeAgAJAAgJmBl5EAAeAgAIAAYJKR0CKwAJAgAAAA==.Molen:BAAALgAECgEJAQAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAgJIAANAKAbAA==.Monkle:BAABLgAECn9EAAITAAkJ/CRSAQBiAwATAAkJ/CRSAQBiAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAQJDAAEAHcbAA==.Moonsii:BAABLgAECn8YAAIUAAkJ9Q2WOQCdAQAUAAkJ9Q2WOQCdAQAAAA==.Mooroth:BAABLgAECn85AAIbAAgJLx2zCQBEAgAbAAgJLx2zCQBEAgABLgAFFAIJAgAFAAAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAABLgAECn8VAAImAAcJZRq+DAB8AQAmAAcJZRq+DAB8AQAAAA==.',
Mu='Muddler:BAABLgAECn85AAIeAAgJMgNjHACwAAAeAAgJMgNjHACwAAAAAA==.Murgut:BAAALgAECgUJBgAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAABLgAECn8YAAIIAAcJXQkTeAA2AQAIAAcJXQkTeAA2AQAAAA==.Naledi:BAABLgAECn8cAAIQAAgJ5Q90LgBMAQAQAAgJ5Q90LgBMAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn8vAAILAAgJbB9rLQBNAgALAAgJbB9rLQBNAgAAAA==.Narella:BAABLgAECn8qAAILAAgJjRSTWwCzAQALAAgJjRSTWwCzAQAAAA==.',
Ne='Negotiable:BAAALgADCgQJCAAAAA==.Negrido:BAABLgAECn8zAAQPAAkJ+yVqDADeAgAPAAgJwSJqDADeAgAeAAMJNiWJJAA3AQAdAAEJvx8LKgBcAAAAAA==.Nei:BAABLgAECn8sAAIXAAcJfxc6VgCwAQAXAAcJfxc6VgCwAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn81AAMQAAkJ6BncDgBZAgAQAAkJ6BncDgBZAgAVAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJBQAAAA==.Noraelyn:BAABLgAECn8wAAMjAAgJwR31FQBFAgAjAAcJIR71FQBFAgAXAAQJewTnKwFhAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECggJJAAVAPcTAA==.Noriyuki:BAABLgAECn8oAAITAAcJ5QFUegBJAAATAAcJ5QFUegBJAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAgJHwALAIceAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8HAAMJAAQJFhUFEgAwAQAJAAQJFhUFEgAwAQAaAAEJwAGJMQAtAAAuAAQKfxcAAwkACAlSI8sIAIUCAAkACAlSI8sIAIUCABoAAwnADI9pAJgAAAEuAAQKCAkOAAUAAAAA.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgADCgQJBAABLgAECggJLQAUAD4SAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8xAAIfAAgJdRATHgBlAQAfAAgJdRATHgBlAQAAAA==.Oluja:BAAALgAECgYJCAAAAA==.',
Om='Omegâ:BAAALgAECgYJCQAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Oppcookies:BAAALgAECgYJCwABLgAECgkJHQAIAPcWAA==.Oppressin:BAAALgADCggJDAABLgAECgkJHQAIAPcWAA==.Oppshot:BAABLgAECn8dAAIIAAkJ9xYaJAA7AgAIAAkJ9xYaJAA7AgAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIjAAMJFxHPKgC7AAAjAAMJFxHPKgC7AAAuAAQKfykAAiMACQnbIVAMALgCACMACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMDAAkJYx5hJQBaAgADAAkJYx5hJQBaAgAHAAUJHAbFPACFAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8hAAIXAAYJOhsyEACpAQAXAAYJOhsyEACpAQAuAAQKfysAAhcACQkbJWMBANEDABcACQkbJWMBANEDAAAA.Palykat:BAABLgAECn8gAAIXAAgJ2wdeowAXAQAXAAgJ2wdeowAXAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIDAAkJUyD1FgCqAgADAAkJUyD1FgCqAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgADAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMVAAkJiBddEADBAQAVAAkJ4hZdEADBAQAQAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8dAAMDAAkJqQ5lWwChAQADAAgJ8w9lWwChAQAHAAEJowXKUwAxAAABLgAECggJLwAWAJIcAA==.Ploofee:BAAALgAECggJDwAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Progresz:BAABLgAECn8UAAILAAgJ5hHHcgB6AQALAAgJ5hHHcgB6AQAAAA==.',
Ps='Psichosa:BAAALgAECggJCAAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIQAAkJ2QmvMgA1AQAQAAkJ2QmvMgA1AQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAFAAAAAA==.',
Qa='Qaren:BAAALgAECgQJDwAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgADCgYJBgAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSBSBQCCAgAoAAkJFB9SBQCCAgAVAAEJQh17TwBRAAAQAAIJ6wdocwBIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAABLgAECn8VAAILAAgJIhRsVADHAQALAAgJIhRsVADHAQABLgAFFAQJDQAdAMYYAA==.Ratabi:BAAALgADCgIJAgAAAA==.Ravna:BAAALgAECgMJAwAAAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJLQACAN8LAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNQAAAQ==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAQAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAILAAQJUSKhMgB0AQALAAQJUSKhMgB0AQAuAAQKfxwAAgsACQmKIbUSANUCAAsACQmKIbUSANUCAAAA.Rhetegast:BAABLgAECn8oAAIiAAkJrRPHDwDIAQAiAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECgcJEgAFAAAAAA==.',
Ri='Rike:BAEBLgAECn8xAAMXAAgJCyLfOAAGAgAXAAgJGSHfOAAGAgAiAAYJ6Rq2EgCDAQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAFAAAAAA==.Roflhazotime:BAABLgAECn8nAAIRAAkJVyPxBwAAAwARAAkJVyPxBwAAAwAAAA==.Roland:BAABLgAECn8oAAMUAAgJ0xLUPACOAQAUAAgJ0xLUPACOAQAQAAMJywbkYgBvAAAAAA==.Rolandin:BAABLgAECn8xAAIjAAgJQxfkGAApAgAjAAgJQxfkGAApAgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgQJCwAAAA==.Rook:BAABLgAFFH8FAAIEAAQJfxTvFABHAQAEAAQJfxTvFABHAQABLgAFFAYJJAABAO0gAA==.Roscjou:BAABLgAECn8UAAICAAYJtwQ+XwCrAAACAAYJtwQ+XwCrAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECggJMAAPAMIWAA==.',
Ry='Rylagosa:BAABLgAECn81AAMGAAgJ0BnSEQCYAQAGAAYJYhnSEQCYAQANAAgJ+RFOLgBjAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8XAAILAAkJGRHLUADSAQALAAkJGRHLUADSAQAAAA==.',
['Rê']='Rêdrum:BAAALgAFFAMJAwABLgAFFAQJEQAPANIHAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn8tAAIUAAgJPhKmNgCrAQAUAAgJPhKmNgCrAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwABAEscAA==.Sarvinblue:BAABLgAECn8rAAMBAAkJSxzmEgCdAgABAAkJSxzmEgCdAgACAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanaynay:BAAALgADCgUJBgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIcAAcJkAa6EQD2AAAcAAcJkAa6EQD2AAAAAA==.Shazlulu:BAABLgAECn8gAAIBAAcJmBttKAACAgABAAcJmBttKAACAgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8ZAAIMAAgJwgmfCgAyAQAMAAgJwgmfCgAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIEAAkJnx+iDABEAgAEAAkJnx+iDABEAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8gAAIjAAgJ5hlfGgAbAgAjAAgJ5hlfGgAbAgAAAA==.Sloe:BAABLgAECn8tAAIKAAgJCBy9GgAGAgAKAAgJCBy9GgAGAgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgADCgEJAQAAAA==.Speedkweef:BAAALgAECgUJBQAAAA==.Speedmeat:BAABLgAECn8bAAMBAAkJAghOXwAgAQABAAgJtgdOXwAgAQACAAIJmAObiwA+AAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAABLgAECn8qAAMIAAgJiQ8iagBWAQAIAAgJiQ8iagBWAQAaAAEJFwHsQAAQAAAAAA==.',
Sq='Squal:BAABLgAECn8oAAMXAAkJ6h3OKQBCAgAXAAkJPB3OKQBCAgAiAAUJ/BhOGABAAQAAAA==.Squiggle:BAABLgAECn80AAIiAAgJwSAeBQCMAgAiAAgJwSAeBQCMAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBwAAAA==.Stickybunz:BAABLgAECn8YAAIYAAgJURVkIQDSAQAYAAgJURVkIQDSAQABLgAFFAMJBQAKAFAOAA==.Striker:BAEALgAECgQJDwABLgAECggJMQAXAAsiAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAFAAAAAA==.Stunseed:BAABLgAECn8rAAIVAAkJ1hhsCQAyAgAVAAkJ1hhsCQAyAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgUJBQAAAA==.Sunshíne:BAABLgAECn8XAAMXAAgJjQcTvADwAAAXAAcJ3AYTvADwAAAiAAEJsgvySQAsAAAAAA==.Surf:BAAALgAECgYJCgAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8FAAMKAAMJUA6MJQBsAAAKAAIJtQeMJQBsAAAOAAEJbQLONQA4AAAuAAQKfzoAAw4ACQnHFkAUABACAA4ACQnHFkAUABACAAoACAlYDpIrAFYBAAAA.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMDAAkJ2BmXPwDyAQADAAgJGxuXPwDyAQAHAAEJCREYTwA/AAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgYJDgAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgYJDgAFAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJBwAAAA==.Tanagra:BAAALgAECgEJAQABLgAECggJMAAPAMIWAA==.Taniss:BAABLgAECn8pAAIkAAkJlQh5CgBiAQAkAAkJlQh5CgBiAQAAAA==.Tanner:BAABLgAECn8cAAMaAAgJDgnESgAnAQAaAAgJwQfESgAnAQAIAAIJoBF5ogCHAAAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8mAAMCAAgJ9xegGgD1AQACAAgJ9xegGgD1AQABAAIJDAdWjwBaAAAAAA==.Temel:BAABLgAECn8tAAMCAAkJ3wvALwBnAQACAAkJ3wvALwBnAQABAAYJUwnUcADpAAAAAA==.Tenelum:BAAALgAECgEJAwABLgAECgkJLQACAN8LAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAFAAAAAA==.',
Th='Thadrack:BAABLgAECn8rAAILAAgJEgbHpgAVAQALAAgJEgbHpgAVAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAFAAAAAA==.Thalonstin:BAAALgAECgEJAgAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQAFAAAAAA==.Theodrid:BAACLgAFFH8QAAIXAAYJwBTULQA5AQAXAAYJwBTULQA5AQAuAAQKfyIAAhcACAmQHzAkAJcCABcACAmQHzAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAIPAAgJWAUGlgAsAQAPAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.Thutpithyuth:BAACLgAFFH8FAAIIAAMJWxpeRQD7AAAIAAMJWxpeRQD7AAAuAAQKfxcAAggACQkgH0QNANQCAAgACQkgH0QNANQCAAAA.',
Ti='Tinkíe:BAABLgAECn8iAAQTAAkJ9RydFgDpAQATAAgJ0BydFgDpAQAWAAQJQRmWTgAJAQASAAUJ2QwbWADYAAAAAA==.Tirzahdozier:BAAALgAECgcJEgAAAA==.Tiwohnne:BAAALgAECgIJAwAAAA==.',
Tl='Tla:BAAALgADCgcJCAAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn84AAIOAAkJByH1AwAJAwAOAAkJByH1AwAJAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8MAAICAAQJlxyiEwBSAQACAAQJlxyiEwBSAQABLgAFFAkJPgAPAKUjAA==.Tristitia:BAABLgAECn8nAAIDAAkJpBXoMwAbAgADAAkJpBXoMwAbAgAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIDAAkJAxzdJgBTAgADAAkJAxzdJgBTAgAAAA==.Turkeltin:BAAALgAECgYJEAAAAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAECgcJEgAFAAAAAA==.',
Ty='Tyche:BAAALgAECgYJEQAAAA==.Tysbich:BAAALgAECgQJBAABLgAECgkJJgAjADshAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIUAAkJWSRyAgCdAwAUAAkJWSRyAgCdAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ9BBYTwDCAQADAAkJ9BBYTwDCAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMeAAYJJhD1HgBZAQAeAAYJJhD1HgBZAQAPAAIJ4gHuLwEhAAAAAA==.Vaelrieth:BAAALgAECgYJDAAAAA==.Vains:BAACLgAFFH8MAAIXAAQJkRzsKQBDAQAXAAQJkRzsKQBDAQAuAAQKfyIAAhcACQkzIWUgAG8CABcACQkzIWUgAG8CAAAA.Valoras:BAAALgADCgEJAQAAAA==.Vardis:BAABLgAECn8uAAILAAkJMh/tJAByAgALAAkJMh/tJAByAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAgAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJLQACAN8LAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAAALgAECgEJAQAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8tAAILAAgJBRpqSADrAQALAAgJBRpqSADrAQAAAA==.Verren:BAABLgAECn8kAAIVAAkJaRhqCQAyAgAVAAkJaRhqCQAyAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAIPAAkJjhzoIwBDAgAPAAkJjhzoIwBDAgAAAA==.',
We='Weltamus:BAABLgAECn8iAAMDAAgJIBMRZwCEAQADAAgJyg8RZwCEAQAHAAIJjB/vMwCxAAAAAA==.Weltasaur:BAABLgAECn8VAAIVAAYJrhMtOACdAAAVAAYJrhMtOACdAAAAAA==.Weltazar:BAABLgAECn8uAAICAAgJ4hMdNQBLAQACAAgJ4hMdNQBLAQAAAA==.Westside:BAACLgAFFH8fAAMLAAgJhx7yBACpAgALAAgJhx7yBACpAgAMAAEJqAmsBABFAAAuAAQKfyMAAgsACQnVJtIAAIoDAAsACQnVJtIAAIoDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAAPAGsjAA==.Wildtiger:BAABLgAECn8xAAIoAAkJ5hjUBgBTAgAoAAkJ5hjUBgBTAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQcAAkJ8B78AQC7AgAcAAkJ8B78AQC7AgAEAAMJoAfkUACkAAAkAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAgABLgAECgkJLQACAN8LAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAFAAAAAA==.Xalreth:BAABLgAECn8ZAAIRAAkJhA3LVgBqAQARAAkJhA3LVgBqAQAAAA==.Xaviana:BAAALgAECggJKAAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMOAAkJOQjWNQAdAQAOAAgJOAfWNQAdAQAKAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIRAAkJ0BgsOADPAQARAAkJ0BgsOADPAQAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIjAAkJJiZ1BgAVAwAjAAkJJiZ1BgAVAwAAAA==.Yushi:BAABLgAECn8tAAIEAAkJlx/oCACBAgAEAAkJlx/oCACBAgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJDwAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8gAAMDAAkJURSQMAAoAgADAAkJURSQMAAoAgAmAAYJKQUUJABzAAAAAA==.Zenweaver:BAACLgAFFH8RAAIWAAMJVSR/GAA/AQAWAAMJVSR/GAA/AQAuAAQKfx8AAhYACQlqIlUEAEcDABYACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIDAAkJRiE8EADZAgADAAkJRiE8EADZAgAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
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
