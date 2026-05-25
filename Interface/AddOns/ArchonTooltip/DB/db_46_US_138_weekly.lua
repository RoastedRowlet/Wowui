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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Devastation','Priest-Discipline','Paladin-Protection','Paladin-Holy','Rogue-Outlaw','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','Shaman-Enhancement','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aarix:BAAALgAECggJEAAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMBAAcJrxAbRwBeAQABAAcJrxAbRwBeAQACAAMJTQGHgABFAAAAAA==.Aendillan:BAAALgAECgYJDwAAAA==.Aewrynn:BAAALgADCgkJCQAAAA==.',
Af='Affonasei:BAABLgAECn8iAAIDAAgJZwnadABUAQADAAgJZwnadABUAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJBwAAAA==.Aileen:BAAALgAECgYJBgAAAA==.',
Ak='Akashi:BAAALgAECgUJCwABLgAFFAMJDgAEAO0hAA==.',
Al='Alacrodie:BAAALgADCgUJCQAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAFAAAAAA==.',
An='Anahla:BAAALgADCgQJBAABLgAECggJLgAGANAZAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgEJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8cAAIHAAgJLh1lFQCRAQAHAAgJLh1lFQCRAQAAAA==.',
Ar='Aragorno:BAABLgAECn8jAAMIAAkJhxJ5NgDZAQAIAAkJhxJ5NgDZAQAJAAQJRAbSOADFAAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn8jAAIIAAgJ1hfMLgD4AQAIAAgJ1hfMLgD4AQAAAA==.Arenthal:BAAALgAECgUJCQAAAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECggJIQAKAL0aAA==.Ashiera:BAABLgAECn8pAAMLAAgJogNgrgAJAQALAAgJogNgrgAJAQAMAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgUJDAAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgUJBQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAEAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJGAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJNQANAOQbAA==.Bahaana:BAAALgADCgYJDAAAAA==.Balentine:BAABLgAECn8aAAMKAAcJjRPHSQASAQAKAAYJZRPHSQASAQAOAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJNgAPADAjAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn81AAINAAkJ5BsyDAB6AgANAAkJ5BsyDAB6AgAAAA==.Baspir:BAABLgAECn8pAAIQAAkJNxYZHQCyAQAQAAkJNxYZHQCyAQAAAA==.',
Be='Belly:BAAALgAECgIJAgABLgAECgkJLQAEAJ8fAA==.Belrae:BAABLgAECn8tAAIRAAkJUBQBJgAXAgARAAkJUBQBJgAXAgAAAA==.Belrinthe:BAAALgAECgcJBwAAAA==.Bezieck:BAABLgAECn8rAAIOAAgJpBMZHAC+AQAOAAgJpBMZHAC+AQAAAA==.',
Bi='Bigdawg:BAAALgAECggJDAAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8lAAILAAgJmQ3yawCGAQALAAgJmQ3yawCGAQAAAA==.Biru:BAAALgAECgIJAwABLgAECggJGQAKABgbAA==.',
Bl='Bloodarrow:BAAALgAECgQJCwAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMSAAYJ5Rc5KwCGAQASAAYJ5Rc5KwCGAQATAAEJaRX7eAA7AAAAAA==.Bonegavel:BAAALgAECgQJBgAAAA==.Bookhuntress:BAABLgAECn8jAAQUAAcJ3RtAJgAfAgAUAAcJ3RtAJgAfAgAQAAYJ5xePKwBJAQAVAAEJnAzTXAAeAAAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgcJCgABLgAECgkJBwAFAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAABLgAECn80AAIWAAkJLR+TBgCzAgAWAAkJLR+TBgCzAgAAAA==.Brewzer:BAACLgAFFH8PAAISAAQJkgQeKQCvAAASAAQJkgQeKQCvAAAuAAQKfyUAAxIACAmEExApAJUBABIACAmEExApAJUBABMABQmtDKxHALcAAAAA.Brint:BAABLgAECn8WAAIPAAgJJQxsbABMAQAPAAgJJQxsbABMAQAAAA==.Brok:BAAALgADCgEJAQAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8qAAILAAYJDyReDQAdAgALAAYJDyReDQAdAgAuAAQKfyIAAgsACAkXJdEjAOMCAAsACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAQABLgAECggJJwACADAYAA==.Broomhandle:BAABLgAECn8YAAIXAAgJHCNcEgC6AgAXAAgJHCNcEgC6AgAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8XAAIYAAUJXx4HDABuAQAYAAUJXx4HDABuAQAuAAQKfxkAAxgABwl/IyskADUCABgABwl/IyskADUCABkAAgnfGNcrAJUAAAAA.Burinn:BAAALgAECgYJBwABLgAECgkJMwAKAO4NAA==.',
Ca='Caeus:BAABLgAECn8kAAIDAAgJEiM/FgCgAgADAAgJEiM/FgCgAgAAAA==.Cam:BAABLgAECn8xAAILAAkJlCXoBwAqAwALAAkJlCXoBwAqAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgUJDgAFAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAcJFQAaANYYAA==.Care:BAABLgAECn8ZAAILAAkJjAwciADBAQALAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAAALgAECgQJDwAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgAECgUJBQAAAA==.Cheesús:BAAALgAECggJCAAAAA==.Chelan:BAABLgAECn8zAAMKAAkJ7g0DJQB4AQAKAAgJ0Q4DJQB4AQAOAAkJ8QMsNQAbAQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAgJHwALAIceAA==.Cinnabunz:BAABLgAECn8ZAAIPAAcJ5QdtiQASAQAPAAcJ5QdtiQASAQAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAAALgAFFAQJBAAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDAABLgAECgkJJgAXAOodAA==.',
Co='Codythedead:BAABLgAFFH8FAAIDAAIJ7RSUnQCZAAADAAIJ7RSUnQCZAAAAAA==.Compadre:BAABLgAECn8XAAQTAAgJPh7NHQDrAQATAAcJ0RrNHQDrAQAWAAQJUiAiRAAyAQASAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8bAAMUAAcJwRGyXAAAAQAUAAYJqxCyXAAAAQAQAAcJxAYjSQC1AAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8jAAIBAAYJ7SApAwBPAgABAAYJ7SApAwBPAgAuAAQKfzgAAgEACQkAJMABAHQDAAEACQkAJMABAHQDAAAA.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgEJAQAAAA==.Cruoris:BAABLgAECn8bAAIbAAcJww0KDQA4AQAbAAcJww0KDQA4AQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8bAAIbAAYJjARwEwDKAAAbAAYJjARwEwDKAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQPAAkJayPjCgDjAgAPAAkJ5iHjCgDjAgAcAAYJWSICBwDQAQAdAAEJAAA+SAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIDAAkJGxtlJQBMAgADAAkJGxtlJQBMAgAAAA==.Dalareas:BAAALgADCgMJAwAAAA==.Danak:BAAALgADCgQJBAAAAA==.Dannika:BAAALgAECgYJBgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8fAAMbAAgJHwcQFADBAAAEAAcJXQZsLwDyAAAbAAUJNAcQFADBAAAAAA==.',
De='Deadlyfrosty:BAAALgAECgQJCwAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.Debixie:BAACLgAFFH8RAAIbAAQJ1BwVAgCEAQAbAAQJ1BwVAgCEAQAuAAQKfyUAAhsACQlLI3EBANQCABsACQlLI3EBANQCAAAA.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8cAAIRAAgJFyIZFACFAgARAAgJFyIZFACFAgAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJNgAPADAjAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIIAAkJ5h9NDgDKAgAIAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAIPAAkJqhROMgD3AQAPAAkJqhROMgD3AQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8dAAIPAAYJWxiwFACuAQAPAAYJWxiwFACuAQAuAAQKfzUAAw8ACQnvH28LAN4CAA8ACQnvH28LAN4CAB0AAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECgcJDgAFAAAAAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8XAAIPAAYJYxPkeQAwAQAPAAYJYxPkeQAwAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgADCgEJAQAAAA==.Dryan:BAAALgAECgQJCwAAAA==.Dryon:BAABLgAECn8nAAIeAAgJKxsmCwAYAgAeAAgJKxsmCwAYAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIIAAkJXBOWNgDYAQAIAAkJXBOWNgDYAQAAAA==.Duragon:BAABLgAECn8yAAQNAAkJ7RakFAAWAgANAAkJ7RakFAAWAgAfAAgJPwXBEgC8AAAGAAYJPwd5IgC1AAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAIRAAYJ6RBJeAA+AQARAAYJ6RBJeAA+AQABLgAFFAMJBQAIAFsaAA==.',
Em='Emilia:BAABLgAECn8UAAIKAAgJnwlELQA9AQAKAAgJnwlELQA9AQAAAA==.',
En='Endressa:BAABLgAECn8pAAMgAAkJAQlAIACcAQAgAAkJAQlAIACcAQAOAAIJ6An1WgBrAAAAAA==.English:BAABLgAECn8zAAILAAkJdBuxLABJAgALAAkJdBuxLABJAgAAAA==.',
Er='Erelios:BAABLgAECn8iAAIhAAgJmh2CCAAeAgAhAAgJmh2CCAAeAgAAAA==.',
Es='Eski:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAEALgADCgIJAgABLgAECgkJMQAiACYmAA==.',
Ev='Evangelina:BAACLgAFFH8gAAMNAAgJoBtOAwCNAgANAAgJoBtOAwCNAgAfAAEJygr9CQBTAAAuAAQKfygAAw0ACQmjJW4BAGoDAA0ACQmjJW4BAGoDAB8ABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECggJIwAVAM8TAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIIAAkJSxafKwAFAgAIAAkJSxafKwAFAgAAAA==.Fastbeefball:BAAALgADCgYJBgAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAgJIAANAKAbAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgEJAQAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAgJHwALAIceAA==.Fish:BAACLgAFFH8fAAIOAAYJ9iYBAgBJAgAOAAYJ9iYBAgBJAgAuAAQKfzcAAg4ACAmOJlYCAIwDAA4ACAmOJlYCAIwDAAEuAAUUCAklAA4AbiYA.',
Fl='Flight:BAACLgAFFH8OAAMEAAMJ7SG+GQAVAQAEAAMJ7SG+GQAVAQAjAAIJFRS/CACfAAAuAAQKfx0AAwQACAkRHHcUAG8CAAQACAljG3cUAG8CABsAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMBAAkJmghiRwBdAQABAAkJmghiRwBdAQACAAYJCQVHVgCyAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAABLgAFFH8HAAIIAAQJ+Rd+IQBDAQAIAAQJ+Rd+IQBDAQABLgAFFAUJFwAYAF8eAA==.Forsynth:BAABLgAECn8cAAMMAAkJ9h4mAQCQAgAMAAkJ9h4mAQCQAgALAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMBAAkJgh5+EACiAgABAAkJgh5+EACiAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAAALgAECgcJEQAAAA==.',
Gl='Glinda:BAAALgADCgQJCAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8jAAILAAYJqB9pDgAUAgALAAYJqB9pDgAUAgAuAAQKf1kAAgsACQkmJqwCAG4DAAsACQkmJqwCAG4DAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJNgAPADAjAA==.Grazienne:BAAALgADCgUJCQAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIVAAkJhx8cBACuAgAVAAkJhx8cBACuAgAAAA==.Grimbaine:BAABLgAECn8jAAIXAAgJASIRGQCPAgAXAAgJASIRGQCPAgAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimmshady:BAAALgADCgIJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAABLgAECn8ZAAMKAAgJGBujDwBIAgAKAAgJGBujDwBIAgAOAAEJ1AOXZwAqAAAAAA==.Gurney:BAABLgAECn8pAAMiAAkJ/hbrGAAYAgAiAAkJ/hbrGAAYAgAhAAEJggQzSgAdAAAAAA==.Guzfu:BAABLgAECn8UAAITAAcJgg15PADhAAATAAcJgg15PADhAAAAAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn8uAAMWAAgJOBtYDwAnAgAWAAgJOBtYDwAnAgATAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgADCgUJCQAAAA==.Happyelf:BAAALgAECgIJAgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8YAAIBAAgJFw5+SQBVAQABAAgJFw5+SQBVAQAAAA==.Hexxiz:BAAALgAECgIJAwABLgAECgYJCwAFAAAAAA==.',
Hi='Hiphopinator:BAABLgAECn8rAAMYAAgJHCWFCgCbAgAYAAgJ2SKFCgCbAgAeAAYJ/SRRDAAAAgAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEwAAAA==.Holyterror:BAAALgADCgUJCQAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCAAAAA==.',
Ia='Iamcro:BAAALgAECgQJBAAAAA==.Ianthe:BAABLgAECn8hAAIMAAgJgAbWBgAdAQAMAAgJgAbWBgAdAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn8vAAQdAAcJJCM5CgByAQAcAAYJURkWCwB2AQAdAAUJSyM5CgByAQAPAAQJjB11bgBHAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAgJIAANAKAbAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgQJBwAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJBwAFAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAABLgAECn8yAAMKAAkJSh+8BQD+AgAKAAkJSh+8BQD+AgAgAAMJlgx+QwCZAAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8NAAMcAAQJxhhxAgBPAQAcAAQJxhhxAgBPAQAPAAEJlA0spABFAAAuAAQKfzEABBwACQn3IDUEACgCABwACQn3IDUEACgCAA8ABgkyGC9DALoBAB0AAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJCQABLgAECgcJDgAFAAAAAA==.Jaylinn:BAABLgAECn8uAAIIAAkJ4Q2UQQCxAQAIAAkJ4Q2UQQCxAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8ZAAIgAAgJDyMqDwBQAgAgAAgJDyMqDwBQAgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8kAAIiAAgJ/xuTEABuAgAiAAgJ/xuTEABuAgAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8jAAMCAAgJjRRAIgCmAQACAAgJjRRAIgCmAQABAAIJPweQpgBDAAAAAA==.Kaleberry:BAABLgAECn8UAAMUAAgJcxClhgDJAAAUAAYJYAmlhgDJAAAQAAUJjwcZYAChAAAAAA==.Kalyandra:BAAALgAECgYJEgAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgAECgYJDwABLgAECggJHQAiAA8XAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8cAAIYAAkJAh0tEQBKAgAYAAkJAh0tEQBKAgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8WAAIRAAgJyBSZNgDLAQARAAgJyBSZNgDLAQAAAA==.Karumie:BAABLgAECn8nAAIBAAkJZhxrGABaAgABAAkJZhxrGABaAgAAAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgADCgUJBgAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAAALgAECgYJDAABLgAECgkJLAARAEEiAA==.Kels:BAABLgAECn8sAAIRAAkJQSJ/CQDoAgARAAkJQSJ/CQDoAgAAAA==.',
Kh='Kheyra:BAABLgAECn8jAAIVAAgJzxNdEgCNAQAVAAgJzxNdEgCNAQAAAA==.',
Ki='Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJNgAPADAjAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgADCgUJBQAAAA==.Kopi:BAAALgAECgEJAQABLgAECggJHAAHAC4dAA==.Korlatt:BAABLgAECn8rAAQRAAgJoBciSACLAQARAAgJ+hMiSACLAQAkAAMJDRxdEwDsAAAlAAEJUwsYcwAyAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgAHAAQJPwpmPwBhAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAALADgXAA==.',
Kt='Kthanid:BAAALgAECgQJDwAAAA==.',
Ku='Kurston:BAABLgAECn8yAAIUAAkJ8hl6EgCYAgAUAAkJ8hl6EgCYAgAAAA==.',
Ky='Kymakazie:BAAALgAECgcJDgAAAA==.',
['Kã']='Kãtniss:BAAALgADCgUJCQAAAA==.',
La='Laih:BAABLgAECn8bAAIbAAkJNA9LBwDCAQAbAAkJNA9LBwDCAQAAAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAWAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAABLgAECn8qAAIBAAgJVhK6MADCAQABAAgJVhK6MADCAQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgADCgMJBgAAAA==.Linora:BAAALgAECgIJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMTAAYJZBofNABRAQATAAUJkxYfNABRAQAWAAQJ+xkLRgAqAQABLgAECggJGAAHAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8hAAIRAAgJ2xYXMwDZAQARAAgJ2xYXMwDZAQAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8YAAMOAAgJwwYgMwAlAQAOAAgJwwYgMwAlAQAKAAMJfwN4WwBDAAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8bAAIXAAgJOQ6dggBJAQAXAAgJOQ6dggBJAQAAAA==.Lynniebee:BAABLgAECn8nAAIMAAgJaAwaBQBlAQAMAAgJaAwaBQBlAQAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8bAAMnAAkJdw22DQCeAQAnAAkJdw22DQCeAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAABLgAECn8cAAIiAAkJrSCwAwBIAwAiAAkJrSCwAwBIAwAAAA==.Matthad:BAABLgAECn8iAAIBAAgJtBVBJwD1AQABAAgJtBVBJwD1AQAAAA==.Mazìkene:BAACLgAFFH8RAAIPAAQJ0gftTgABAQAPAAQJ0gftTgABAQAuAAQKfyYAAw8ACQkuF+9AAMEBAA8ACQk2Fu9AAMEBABwABQlSHOUMAFcBAAAA.',
Mc='Mccone:BAAALgAECgQJCwAAAA==.Mcsluts:BAAALgAECgQJDgAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAgJIAANAKAbAA==.Melmirict:BAACLgAFFH8OAAIEAAQJWBKYFgAyAQAEAAQJWBKYFgAyAQAuAAQKfyAAAwQACQlQGfsXALIBAAQACQlQGfsXALIBABsAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn8yAAIVAAkJIBFwFAB1AQAVAAkJIBFwFAB1AQAAAA==.',
Mi='Milyyanna:BAAALgADCgUJCAAAAA==.Minaby:BAAALgAECgYJEAABLgAECggJGAAXABwjAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8qAAQPAAcJGRhZXAB0AQAPAAcJGRhZXAB0AQAcAAIJkg7FLQA8AAAdAAEJAADORgAAAAAAAA==.Mohawk:BAAALgADCgIJAgABLgAECgYJCgAFAAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgADCgIJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8gAAMJAAgJBh2dDgAmAgAJAAgJmBmdDgAmAgAIAAYJKR0CKwAJAgAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAgJIAANAKAbAA==.Monkle:BAABLgAECn88AAITAAkJeSSvAQBNAwATAAkJeSSvAQBNAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAMJBwAEAEIeAA==.Moonsii:BAABLgAECn8YAAIUAAkJ9Q0xNgCeAQAUAAkJ9Q0xNgCeAQAAAA==.Mooroth:BAABLgAECn8yAAIeAAgJyBo6CwAWAgAeAAgJyBo6CwAWAgABLgAFFAIJAgAFAAAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAAALgAFFAIJAgAAAA==.',
Mu='Muddler:BAABLgAECn8yAAIdAAgJlgITHQCdAAAdAAgJlgITHQCdAAAAAA==.Murgut:BAAALgAECgMJAwAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAABLgAECn8VAAIIAAYJ5gdGiwD2AAAIAAYJ5gdGiwD2AAAAAA==.Naledi:BAABLgAECn8cAAIQAAgJ5Q/rKgBNAQAQAAgJ5Q/rKgBNAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn8pAAILAAcJhR7GSgDfAQALAAcJhR7GSgDfAQAAAA==.Narella:BAABLgAECn8lAAILAAgJ5xGJYgCdAQALAAgJ5xGJYgCdAQAAAA==.',
Ne='Negotiable:BAAALgADCgQJCAAAAA==.Negrido:BAABLgAECn8zAAQPAAkJ+yXYCgDjAgAPAAgJwSLYCgDjAgAdAAMJNiWJJAA3AQAcAAEJvx8mJQBeAAAAAA==.Nei:BAABLgAECn8oAAIXAAcJdRYYWQCiAQAXAAcJdRYYWQCiAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn8yAAMQAAgJMBh3FwDnAQAQAAgJMBh3FwDnAQAVAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Noraelyn:BAABLgAECn8uAAMiAAgJwh3JGQAQAgAiAAYJSiHJGQAQAgAXAAQJkAMEHwFgAAAAAA==.Norelei:BAAALgAECgQJBAABLgAECggJIwAVAM8TAA==.Noriyuki:BAABLgAECn8iAAITAAYJqwGddgA/AAATAAYJqwGddgA/AAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAgJHwALAIceAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8HAAMJAAQJFhXmDgA6AQAJAAQJFhXmDgA6AQAaAAEJwAHUKwA0AAAuAAQKfxcAAwkACAlSI34HAI0CAAkACAlSI34HAI0CABoAAwnADI9pAJgAAAEuAAQKCAkOAAUAAAAA.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgADCgQJBAABLgAECggJKQAUAIMRAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8rAAIlAAgJXRAYGwBrAQAlAAgJXRAYGwBrAQAAAA==.Oluja:BAAALgAECgMJAwAAAA==.',
Om='Omegâ:BAAALgAECgYJCQAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Oppcookies:BAAALgAECgYJCwABLgAECgkJFQAIAGQVAA==.Oppressin:BAAALgADCggJDAABLgAECgkJFQAIAGQVAA==.Oppshot:BAABLgAECn8VAAIIAAkJZBVCKgAKAgAIAAkJZBVCKgAKAgAAAA==.',
Or='Orin:BAAALgADCgEJAQAAAA==.',
Os='Oshìe:BAABLgAECn8pAAIiAAkJ2yFQDAC4AgAiAAkJ2yFQDAC4AgAAAA==.',
Ov='Overdoom:BAABLgAECn82AAMDAAkJYx6YIQBfAgADAAkJYx6YIQBfAgAHAAUJHAYtOACFAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCgUJCwAAAA==.Paladinjohn:BAACLgAFFH8gAAIXAAYJOhspCwC7AQAXAAYJOhspCwC7AQAuAAQKfysAAhcACQkbJWMBANEDABcACQkbJWMBANEDAAAA.Palykat:BAABLgAECn8fAAIXAAgJ1AeAjwAyAQAXAAgJ1AeAjwAyAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECgYJBwAAAA==.Pennywisé:BAABLgAECn8rAAIDAAkJUyA6FACuAgADAAkJUyA6FACuAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgADAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMVAAkJiBdCDgDDAQAVAAkJ4hZCDgDDAQAQAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8XAAMDAAkJFQwmYgCAAQADAAgJAQ0mYgCAAQAHAAEJowVcTQAxAAABLgAECggJLgAWADgbAA==.Ploofee:BAAALgAECgYJDQAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Progresz:BAABLgAECn8UAAILAAgJ5hH7ZgCSAQALAAgJ5hH7ZgCSAQAAAA==.',
Ps='Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIQAAkJ2Qm3LgA2AQAQAAkJ2Qm3LgA2AQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAQABLgAECgUJCgAFAAAAAA==.',
Qa='Qaren:BAAALgAECgQJDwAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgADCgYJBgAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSCZBACMAgAoAAkJFB+ZBACMAgAVAAEJQh3FRABSAAAQAAIJ6wdEawBIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAABLgAECn8UAAILAAgJ5BKuVwC5AQALAAgJ5BKuVwC5AQABLgAFFAQJDQAcAMYYAA==.Ratabi:BAAALgADCgIJAgAAAA==.Rawrski:BAAALgADCgEJAgABLgAECggJJwACAPkLAA==.',
Re='Reeven:BAAALgAECgkJLQAAAQ==.Ressurectjin:BAAALgAECgUJDAAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAILAAQJUSJIJwCGAQALAAQJUSJIJwCGAQAuAAQKfxwAAgsACQmKIR4QAOMCAAsACQmKIR4QAOMCAAAA.Rhetegast:BAABLgAECn8oAAIhAAkJrRPHDwDIAQAhAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECgcJDgAFAAAAAA==.',
Ri='Rike:BAEBLgAECn8rAAMXAAgJuyFhPQAvAgAXAAgJySBhPQAvAgAhAAYJPxpFEgB1AQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAFAAAAAA==.Roflhazotime:BAABLgAECn8nAAIRAAkJVyPdBgAJAwARAAkJVyPdBgAJAwAAAA==.Roland:BAABLgAECn8mAAMUAAgJ5g/4RQBUAQAUAAgJ5g/4RQBUAQAQAAMJywY2XABvAAAAAA==.Rolandin:BAABLgAECn8rAAIiAAgJ9xbzFgArAgAiAAgJ9xbzFgArAgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgQJCwAAAA==.Rook:BAAALgAFFAIJAgABLgAFFAYJIwABAO0gAA==.Roscjou:BAABLgAECn8UAAICAAYJsASXWQCnAAACAAYJsASXWQCnAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgcJKgAPABkYAA==.',
Ry='Rylagosa:BAABLgAECn8uAAMGAAgJ0BnSEACYAQAGAAYJYhnSEACYAQANAAQJxA+uYwB9AAAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8XAAILAAkJGRHBSADlAQALAAkJGRHBSADlAQAAAA==.',
['Rê']='Rêdrum:BAAALgAFFAMJAwABLgAFFAQJEQAPANIHAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn8pAAIUAAgJgxFUNQCiAQAUAAgJgxFUNQCiAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJJgABAFcbAA==.Sarvinblue:BAABLgAECn8mAAMBAAkJVxuPFQBpAgABAAkJVxuPFQBpAgACAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8ZAAIbAAcJkAakEAD5AAAbAAcJkAakEAD5AAAAAA==.Shazlulu:BAABLgAECn8fAAIBAAcJmBuCJAAFAgABAAcJmBuCJAAFAgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8ZAAIMAAgJwgmfCgAyAQAMAAgJwgmfCgAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIEAAkJnx8KCwBRAgAEAAkJnx8KCwBRAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8gAAIiAAgJ5hkcGAAgAgAiAAgJ5hkcGAAgAgAAAA==.Sloe:BAABLgAECn8hAAIKAAgJvRq9GgAGAgAKAAgJvRq9GgAGAgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBAAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedmeat:BAAALgAECggJEgAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAABLgAECn8qAAMIAAgJiQ8OYQBWAQAIAAgJiQ8OYQBWAQAaAAEJFwELPQARAAAAAA==.',
Sq='Squal:BAABLgAECn8mAAMXAAkJ6h3TJABQAgAXAAkJPB3TJABQAgAhAAUJ/BhUFgBCAQAAAA==.Squiggle:BAABLgAECn8tAAIhAAgJlB1NCAAjAgAhAAgJlB1NCAAjAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBwAAAA==.Stickybunz:BAABLgAECn8YAAIYAAgJURVLHgDYAQAYAAgJURVLHgDYAQABLgAFFAMJBQAKAFAOAA==.Striker:BAEALgAECgQJDwABLgAECggJKwAXALshAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAFAAAAAA==.Stunseed:BAABLgAECn8rAAIVAAkJ1hgcCAA2AgAVAAkJ1hgcCAA2AgAAAA==.',
Su='Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgUJBQAAAA==.Sunshíne:BAABLgAECn8WAAMXAAcJlAfLxADeAAAXAAYJwgbLxADeAAAhAAEJsgssRAAtAAAAAA==.Surf:BAAALgAECgYJCQAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8FAAMKAAMJUA6oIQB7AAAKAAIJtQeoIQB7AAAOAAEJbQKVMAA9AAAuAAQKfzQAAw4ACQnGFSMYAOEBAA4ACAkiGCMYAOEBAAoACAlYDmMoAF8BAAAA.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8nAAIDAAgJGxuZOgDzAQADAAgJGxuZOgDzAQAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgUJDgAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgUJDgAFAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJBwAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgcJKgAPABkYAA==.Taniss:BAABLgAECn8nAAIjAAgJWgjJCwAtAQAjAAgJWgjJCwAtAQAAAA==.Tanner:BAABLgAECn8bAAMaAAgJDgnESgAnAQAaAAgJwQfESgAnAQAIAAIJoBF5ogCHAAAAAA==.',
Te='Tedman:BAABLgAECn8fAAMCAAcJ8Q+aPAASAQACAAcJ8Q+aPAASAQABAAIJDAdWjwBaAAAAAA==.Temel:BAABLgAECn8nAAMCAAgJ+QuxNQAzAQACAAgJ+QuxNQAzAQABAAYJUwk2aADqAAAAAA==.Tenelum:BAAALgAECgEJAgABLgAECggJJwACAPkLAA==.Testoecles:BAAALgAECgMJBQAAAA==.',
Th='Thadrack:BAABLgAECn8lAAILAAgJeAWFnAAmAQALAAgJeAWFnAAmAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAFAAAAAA==.Thalonstin:BAAALgAECgEJAQAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQAFAAAAAA==.Theodrid:BAACLgAFFH8OAAIXAAUJbBG4GADnAAAXAAUJbBG4GADnAAAuAAQKfyIAAhcACAmQHzAkAJcCABcACAmQHzAkAJcCAAAA.Thoreum:BAAALgAECgEJAQAAAA==.Thraxia:BAABLgAECn8XAAIPAAgJWAUGlgAsAQAPAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.Thutpithyuth:BAABLgAFFH8FAAIIAAMJWxpDOQACAQAIAAMJWxpDOQACAQAAAA==.',
Ti='Tinkíe:BAABLgAECn8iAAQTAAkJ9Rx0FADvAQATAAgJ0Bx0FADvAQAWAAQJQRmWTgAJAQASAAUJ2QxXTQDZAAAAAA==.Tirzahdozier:BAAALgAECgcJDgAAAA==.Tiwohnne:BAAALgAECgIJAwAAAA==.',
Tl='Tla:BAAALgADCgQJBAAAAA==.',
Tr='Treat:BAABLgAECn8yAAIOAAkJhyBwBAD7AgAOAAkJhyBwBAD7AgAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8MAAICAAQJlxyGDwBjAQACAAQJlxyGDwBjAQABLgAFFAkJNgAPADAjAA==.Tristitia:BAABLgAECn8kAAIDAAgJORaIRADSAQADAAgJORaIRADSAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIDAAkJAxyxIgBZAgADAAkJAxyxIgBZAgAAAA==.Turkeltin:BAAALgAECgYJEAAAAA==.',
Tw='Twiggle:BAAALgAECgEJAQABLgAECgcJDgAFAAAAAA==.',
Ty='Tyche:BAAALgAECgQJDwAAAA==.Tysbich:BAAALgAECgQJBAABLgAECgkJHAAiAK0gAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIUAAkJWSQUAgCfAwAUAAkJWSQUAgCfAwAAAA==.',
Um='Umakkel:BAAALgAECgUJCgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ9BDHSADFAQADAAkJ9BDHSADFAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMdAAYJJhD1HgBZAQAdAAYJJhD1HgBZAQAPAAIJ4gHuLwEhAAAAAA==.Vains:BAACLgAFFH8MAAIXAAQJkRxzIQBRAQAXAAQJkRxzIQBRAQAuAAQKfyIAAhcACQkzIQ8cAH8CABcACQkzIQ8cAH8CAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAAALgAECgUJCAAAAA==.Vardis:BAABLgAECn8uAAILAAkJMh8wIQB+AgALAAkJMh8wIQB+AgAAAA==.',
Ve='Velinami:BAAALgAECgEJAQAAAA==.Venato:BAAALgADCgEJBAABLgAECggJJwACAPkLAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAAALgAECgEJAQAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8rAAILAAgJBRrJQgD4AQALAAgJBRrJQgD4AQAAAA==.Verren:BAABLgAECn8cAAIVAAkJzxYMCwD4AQAVAAkJzxYMCwD4AQAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgQJBwAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vyerith:BAABLgAECn8kAAIPAAkJjhzgHwBNAgAPAAkJjhzgHwBNAgAAAA==.',
We='Weltamus:BAABLgAECn8gAAIDAAgJyg/pXgCIAQADAAgJyg/pXgCIAQAAAA==.Weltasaur:BAAALgAECgQJDwAAAA==.Weltazar:BAABLgAECn8oAAICAAcJ1RUYPAAVAQACAAcJ1RUYPAAVAQAAAA==.Westside:BAACLgAFFH8fAAMLAAgJhx7fAgC7AgALAAgJhx7fAgC7AgAMAAEJqAmaAwBJAAAuAAQKfyMAAgsACQnVJoIAAJcDAAsACQnVJoIAAJcDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAAPAGsjAA==.Wildtiger:BAABLgAECn8rAAIoAAgJ9BEEDwCPAQAoAAgJ9BEEDwCPAQAAAA==.',
Wo='Wolfslied:BAAALgAECgYJBwAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8wAAQbAAkJ8B6rAQDDAgAbAAkJ8B6rAQDDAgAEAAMJoAfkUACkAAAjAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAgABLgAECggJJwACAPkLAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAFAAAAAA==.Xalreth:BAABLgAECn8RAAIRAAkJLQ3jmADFAAARAAkJLQ3jmADFAAAAAA==.Xaviana:BAAALgAECggJKAAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMOAAkJOQjkLgA7AQAOAAgJOAfkLgA7AQAKAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIRAAkJ0BjaMwDXAQARAAkJ0BjaMwDXAQAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIiAAkJJiahBQAYAwAiAAkJJiahBQAYAwAAAA==.Yushi:BAABLgAECn8tAAIEAAkJlx91BwCPAgAEAAkJlx91BwCPAgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJDwAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8aAAMDAAgJ2hIjTgC1AQADAAgJ2hIjTgC1AQAmAAYJKQWkHgCGAAAAAA==.Zenweaver:BAACLgAFFH8NAAIWAAMJTiHRGwAhAQAWAAMJTiHRGwAhAQAuAAQKfx8AAhYACQlqIlUEAEcDABYACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8eAAIDAAgJViEmHgBxAgADAAgJViEmHgBxAgAAAA==.',
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
