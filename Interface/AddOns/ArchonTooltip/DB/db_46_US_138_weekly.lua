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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Devastation','Priest-Discipline','Paladin-Protection','Paladin-Holy','Rogue-Outlaw','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','Shaman-Enhancement','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarix:BAAALgAECggJDAAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMBAAcJrxAPOwBhAQABAAcJrxAPOwBhAQACAAMJTQGHgABFAAAAAA==.Aendillan:BAAALgAECgYJDwAAAA==.',
Af='Affonasei:BAABLgAECn8aAAIDAAcJkQhXfwAbAQADAAcJkQhXfwAbAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJBgAAAA==.',
Ak='Akashi:BAAALgAECgMJBAABLgAFFAMJCgAEAKscAA==.',
Al='Alacrodie:BAAALgADCgUJCAAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAFAAAAAA==.',
An='Anahla:BAAALgADCgQJBAABLgAECggJKgAGAKEYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgEJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8aAAIHAAcJ6xtFGACXAQAHAAcJ6xtFGACXAQAAAA==.',
Ar='Aragorno:BAABLgAECn8jAAMIAAkJhxJUKgDjAQAIAAkJhxJUKgDjAQAJAAQJRAZAMADKAAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn8bAAIIAAcJGBV4RwByAQAIAAcJGBV4RwByAQAAAA==.Arenthal:BAAALgAECgQJBQAAAA==.Arkulas:BAAALgAECgYJBgAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgcJIAAKAFsdAA==.Ashiera:BAABLgAECn8iAAMLAAgJMgNppwD0AAALAAgJMgNppwD0AAAMAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgUJCwAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgUJBQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAEAJcfAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJEwAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJMgANAE4bAA==.Bahaana:BAAALgADCgYJCAAAAA==.Balentine:BAABLgAECn8ZAAMKAAcJXxO9NADmAAAKAAYJLxO9NADmAAAOAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJLwAPAEchAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn8yAAINAAkJThtxCgBuAgANAAkJThtxCgBuAgAAAA==.Baspir:BAABLgAECn8oAAIQAAkJNhaHGACvAQAQAAkJNhaHGACvAQAAAA==.',
Be='Belly:BAAALgAECgIJAgABLgAECgkJLQAEAJcfAA==.Belrae:BAABLgAECn8pAAIRAAkJTxScHwASAgARAAkJTxScHwASAgAAAA==.Belrinthe:BAAALgAECgcJBwAAAA==.Bezieck:BAABLgAECn8lAAIOAAcJjQ95JgBCAQAOAAcJjQ95JgBCAQAAAA==.',
Bi='Bigdawg:BAAALgAECgcJDAAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8dAAILAAgJxAmBeQBHAQALAAgJxAmBeQBHAQAAAA==.',
Bl='Bloodarrow:BAAALgAECgMJBwAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAAALgAECgYJEgAAAA==.Bonegavel:BAAALgAECgQJBgAAAA==.Bookhuntress:BAABLgAECn8iAAQSAAcJ3RtAJgAfAgASAAcJ3RtAJgAfAgAQAAUJqRlQKwAeAQATAAEJnAweRwAhAAAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECgcJCQABLgAECgkJBQAFAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAABLgAECn8wAAIUAAkJzB6FBQCyAgAUAAkJzB6FBQCyAgAAAA==.Brewzer:BAACLgAFFH8PAAIVAAQJkgSIHwC7AAAVAAQJkgSIHwC7AAAuAAQKfyUAAxUACAmEExwhAJEBABUACAmEExwhAJEBABYABQmtDKo7AMIAAAAA.Brint:BAAALgAECggJEwAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8fAAILAAUJCyMwHwCDAQALAAUJCyMwHwCDAQAuAAQKfyIAAgsACAkXJdEjAOMCAAsACAkXJdEjAOMCAAAA.Bronst:BAAALgADCgYJBgABLgAECggJJQACANUXAA==.Broomhandle:BAABLgAECn8WAAIXAAgJ1CGUEACoAgAXAAgJ1CGUEACoAgAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8SAAIYAAUJXx4fBwCBAQAYAAUJXx4fBwCBAQAuAAQKfxkAAxgABwl/IyskADUCABgABwl/IyskADUCABkAAgnfGNcrAJUAAAAA.Burinn:BAAALgAECgEJAQABLgAECgkJLQAKANoNAA==.',
Ca='Caeus:BAABLgAECn8fAAIDAAgJtiKoEwCSAgADAAgJtiKoEwCSAgAAAA==.Cam:BAABLgAECn8xAAILAAkJkiVJBQA4AwALAAkJkiVJBQA4AwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgUJDQAFAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAYJEwAaAAgdAA==.Care:BAABLgAECn8ZAAILAAkJjAwciADBAQALAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAAALgAECgMJBwAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgAECgUJBQAAAA==.Cheesús:BAAALgAECgcJBwAAAA==.Chelan:BAABLgAECn8tAAMKAAkJ2g2jHwB+AQAKAAgJuQ6jHwB+AQAOAAkJuAPLLgARAQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAcJGQALAGUdAA==.Cinnabunz:BAAALgAECgcJEgAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAAALgAECgUJBQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJCQABLgAECgkJJQAXAOsdAA==.',
Co='Codythedead:BAAALgAFFAIJBAAAAA==.Compadre:BAABLgAECn8WAAQWAAgJsR3NHQDrAQAWAAcJLRrNHQDrAQAUAAQJUiAiRAAyAQAVAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8bAAMSAAcJwBEJVgDyAAASAAYJqhAJVgDyAAAQAAcJwwb+PwC2AAAAAA==.Coolsbeans:BAAALgAECgQJBQAAAA==.Coraf:BAACLgAFFH8dAAIBAAUJ7SJTBQD3AQABAAUJ7SJTBQD3AQAuAAQKfzcAAgEACQkAJMABAHQDAAEACQkAJMABAHQDAAAA.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgEJAQAAAA==.Cruoris:BAABLgAECn8bAAIbAAcJww3LCgBCAQAbAAcJww3LCgBCAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8VAAIbAAYJRARzEQDIAAAbAAYJRARzEQDIAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQPAAkJbiNeBwDxAgAPAAkJ5SFeBwDxAgAcAAYJXSK9BADhAQAdAAEJAAB0QAAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgIJAgAAAA==.Dahaxors:BAABLgAECn8lAAIDAAkJGhvLHQBRAgADAAkJGhvLHQBRAgAAAA==.Danak:BAAALgADCgQJBAAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8YAAMbAAYJjgitEQDEAAAbAAQJNAetEQDEAAAEAAUJqAUTTgC7AAAAAA==.',
De='Deadlyfrosty:BAAALgAECgMJBwAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.Debixie:BAACLgAFFH8OAAIbAAMJsR8zBAAQAQAbAAMJsR8zBAAQAQAuAAQKfyAAAhsACQnGIk4BACUDABsACQnGIk4BACUDAAAA.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8ZAAIRAAgJRCHQEQBzAgARAAgJRCHQEQBzAgAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJLwAPAEchAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8rAAIIAAkJ5h9NDgDKAgAIAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8ZAAIPAAgJehaEXQCwAQAPAAgJehaEXQCwAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8YAAIPAAUJDRdcEgBTAQAPAAUJDRdcEgBTAQAuAAQKfzEAAw8ACQnvHygJANwCAA8ACQnvHygJANwCAB0AAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECgUJCgAFAAAAAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAAALgAECgYJEAAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgADCgEJAQAAAA==.Dryan:BAAALgAECgMJBwAAAA==.Dryon:BAABLgAECn8fAAIeAAcJuhaZEgBxAQAeAAcJuhaZEgBxAQAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIIAAkJXBMuKwDgAQAIAAkJXBMuKwDgAQAAAA==.Duragon:BAABLgAECn8uAAQNAAkJpxX6EQAGAgANAAkJpxX6EQAGAgAfAAgJPwVyEAC9AAAGAAYJPweXHgC5AAAAAA==.',
['Dí']='Díznutz:BAAALgAECggJEwABLgAFFAIJAgAFAAAAAA==.',
Em='Emilia:BAABLgAECn8UAAIKAAgJoAknJwBDAQAKAAgJoAknJwBDAQAAAA==.',
En='Endressa:BAABLgAECn8gAAMgAAkJ+wd4HACPAQAgAAkJ+wd4HACPAQAOAAEJFAznYwAxAAAAAA==.English:BAABLgAECn8vAAILAAkJdBt9JQBFAgALAAkJdBt9JQBFAgAAAA==.',
Er='Erelios:BAABLgAECn8dAAIhAAgJFh0YBwAaAgAhAAgJFh0YBwAaAgAAAA==.',
Es='Eski:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAEALgADCgIJAgABLgAECgkJLQAiACYmAA==.',
Ev='Evangelina:BAACLgAFFH8aAAMNAAcJ4xk4BgAEAgANAAcJ4xk4BgAEAgAfAAEJygr9CQBTAAAuAAQKfygAAw0ACQmiJRMBAGoDAA0ACQmiJRMBAGoDAB8ABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECggJHQATAB4SAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIIAAkJQxYBIQASAgAIAAkJQxYBIQASAgAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAcJGgANAOMZAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgEJAQAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAcJGQALAGUdAA==.Fish:BAACLgAFFH8YAAIOAAUJwyaIAgDUAQAOAAUJwyaIAgDUAQAuAAQKfzcAAg4ACAmOJlYCAIwDAA4ACAmOJlYCAIwDAAEuAAUUCAkkAA4AayYA.',
Fl='Flight:BAACLgAFFH8KAAMEAAMJqxysHADGAAAEAAMJqxysHADGAAAjAAIJWg1rCACHAAAuAAQKfxoAAwQACAkRHHcUAG8CAAQACAljG3cUAG8CABsAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMBAAkJmghVOwBgAQABAAkJmghVOwBgAQACAAYJCQWDSQC1AAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAAALgAFFAMJAwABLgAFFAUJEgAYAF8eAA==.Forsynth:BAABLgAECn8ZAAMMAAgJfx9/AQBKAgAMAAgJfx9/AQBKAgALAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMBAAkJgh5fDACqAgABAAkJgh5fDACqAgACAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAAALgAECgYJCwAAAA==.',
Gl='Glinda:BAAALgADCgQJBwAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8dAAILAAUJAyaUFgCsAQALAAUJAyaUFgCsAQAuAAQKf1kAAgsACQkmJsMBAHUDAAsACQkmJsMBAHUDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJLwAPAEchAA==.Grazienne:BAAALgADCgUJCAAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAITAAkJhx8sAwCvAgATAAkJhx8sAwCvAgAAAA==.Grimbaine:BAABLgAECn8bAAIXAAcJLiKYIgA1AgAXAAcJLiKYIgA1AgAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAABLgAECn8VAAMKAAYJbB+KEwDzAQAKAAYJbB+KEwDzAQAOAAEJ1AOXZwAqAAAAAA==.Gurney:BAABLgAECn8iAAIiAAgJExRbJwCCAQAiAAgJExRbJwCCAQAAAA==.Guzfu:BAABLgAECn8UAAIWAAcJgg3cMQDuAAAWAAcJgg3cMQDuAAAAAA==.',
Gw='Gwenory:BAAALgADCgEJAQAAAA==.',
Gy='Gying:BAABLgAECn8mAAMUAAcJCRrUGACiAQAUAAcJCRrUGACiAQAWAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDQAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgADCgUJCAAAAA==.Happyelf:BAAALgAECgIJAgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8YAAIBAAgJFw4wPQBXAQABAAgJFw4wPQBXAQAAAA==.Hexxiz:BAAALgAECgEJAQABLgAECgkJJgASAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8nAAMYAAcJEiPtEAAmAgAYAAcJPSHtEAAmAgAeAAUJsiVVDwCkAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEgAAAA==.Holyterror:BAAALgADCgUJCAAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCAAAAA==.',
Ia='Iamcro:BAAALgAECgQJBAAAAA==.Ianthe:BAABLgAECn8aAAIMAAcJ/wbGBwDhAAAMAAcJ/wbGBwDhAAAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn8pAAQdAAcJJCMpCAB7AQAdAAUJSyMpCAB7AQAPAAQJjB2DWwBNAQAcAAUJuBgPDQAbAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgUJCQAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAcJGgANAOMZAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgEJAwAAAA==.Infoxicated:BAAALgAECgUJCgAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAABLgAECn8qAAMKAAkJLx2wBgDFAgAKAAkJLx2wBgDFAgAgAAMJlgx+QwCZAAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8KAAMcAAQJxhheAQBaAQAcAAQJxhheAQBaAQAPAAEJlA0LjgBJAAAuAAQKfywABBwACQn3INsCADMCABwACQn3INsCADMCAA8ABgk2FUmZACYBAB0AAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJCAABLgAECgUJCgAFAAAAAA==.Jaylinn:BAABLgAECn8qAAIIAAkJuA2+NAC3AQAIAAkJuA2+NAC3AQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBgAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8XAAIgAAgJDiP3CwBZAgAgAAgJDiP3CwBZAgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8hAAIiAAYJMCBBFgAMAgAiAAYJMCBBFgAMAgAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8bAAMCAAcJkhWsJwBZAQACAAcJkhWsJwBZAQABAAIJPwcOjwBFAAAAAA==.Kaleberry:BAAALgAECgcJEwAAAA==.Kalyandra:BAAALgAECgYJEgAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgAECgYJCQABLgAECggJGwAiAAsXAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8cAAIYAAkJAh23CwBmAgAYAAkJAh23CwBmAgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAAALgAECgYJDQAAAA==.Karumie:BAABLgAECn8nAAIBAAkJZhzvEgBiAgABAAkJZhzvEgBiAgAAAA==.Kateera:BAAALgAECgUJCgAAAA==.',
Ke='Keden:BAAALgADCgQJBQAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAAALgAECgYJDAABLgAECgkJKAARAEAiAA==.Kels:BAABLgAECn8oAAIRAAkJQCLMBgDuAgARAAkJQCLMBgDuAgAAAA==.',
Kh='Kheyra:BAABLgAECn8dAAITAAgJHhIZFQAzAQATAAgJHhIZFQAzAQAAAA==.',
Ki='Kidashia:BAAALgAECgQJBAAAAA==.',
Ko='Kohnor:BAAALgADCgQJBAAAAA==.Kopi:BAAALgAECgEJAQABLgAECgcJGgAHAOsbAA==.Korlatt:BAABLgAECn8jAAQRAAgJ7BVSPQCFAQARAAgJnBNSPQCFAQAkAAIJdhnNGACKAAAlAAEJUwsYcwAyAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgAHAAQJPwq4NgBnAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAALADgXAA==.',
Kt='Kthanid:BAAALgAECgMJBwAAAA==.',
Ku='Kurston:BAABLgAECn8uAAISAAkJaBnKEACHAgASAAkJaBnKEACHAgAAAA==.',
Ky='Kymakazie:BAAALgAECgYJBwAAAA==.',
['Kã']='Kãtniss:BAAALgADCgUJCAAAAA==.',
La='Laih:BAABLgAECn8ZAAIbAAgJlBCGBwCTAQAbAAgJlBCGBwCTAQAAAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQAAAA==.Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAABLgAECn8iAAIBAAcJWQ/6RQAyAQABAAcJWQ/6RQAyAQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgADCgMJBQAAAA==.Linora:BAAALgAECgIJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMWAAYJZBofNABRAQAWAAUJkxYfNABRAQAUAAQJ+xkLRgAqAQABLgAECggJGAAHAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8cAAIRAAgJ/xWGMQC2AQARAAgJ/xWGMQC2AQAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8VAAMOAAYJ3gXcOwDMAAAOAAYJ3gXcOwDMAAAKAAMJfwPwUgBDAAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8UAAIXAAcJ9wkRpADkAAAXAAcJ9wkRpADkAAAAAA==.Lynniebee:BAABLgAECn8mAAIMAAgJaQxSBAB0AQAMAAgJaQxSBAB0AQAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJBQAAAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8ZAAMnAAgJeg5uDQBqAQAnAAgJeg5uDQBqAQACAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAABLgAECn8ZAAIiAAgJ6iDABQD0AgAiAAgJ6iDABQD0AgAAAA==.Matthad:BAABLgAECn8dAAIBAAgJiBSCIwDiAQABAAgJiBSCIwDiAQAAAA==.Mazìkene:BAACLgAFFH8QAAIPAAQJtwfpQQAEAQAPAAQJtwfpQQAEAQAuAAQKfyEAAg8ACQkyFtc3ALoBAA8ACQkyFtc3ALoBAAAA.',
Mc='Mccone:BAAALgAECgMJBwAAAA==.Mcsluts:BAAALgAECgQJDgAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAcJGgANAOMZAA==.Melmirict:BAACLgAFFH8NAAIEAAQJWBKcEQA8AQAEAAQJWBKcEQA8AQAuAAQKfyAAAwQACQlCGQ8UAK0BAAQACQlCGQ8UAK0BABsAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn8uAAITAAkJaRAYEABzAQATAAkJaRAYEABzAQAAAA==.',
Mi='Milyyanna:BAAALgADCgUJBwAAAA==.Minaby:BAAALgAECgYJEAABLgAECggJFgAXANQhAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8iAAQPAAcJGRiKUQBoAQAPAAcJGRiKUQBoAQAcAAIJRQd2KAAqAAAdAAEJAACmPwAAAAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgADCgIJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8YAAMIAAgJSRwCKwAJAgAIAAYJKR0CKwAJAgAJAAgJqhNQEwDFAQAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAcJGgANAOMZAA==.Monkle:BAABLgAECn8zAAIWAAkJhSMKAgArAwAWAAkJhSMKAgArAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAMJBwAEAEIeAA==.Moonsii:BAABLgAECn8WAAISAAcJKxDfQABFAQASAAcJKxDfQABFAQAAAA==.Mooroth:BAABLgAECn8qAAIeAAgJvxgIDADeAQAeAAgJvxgIDADeAQAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAAALgAECgUJDAAAAA==.',
Mu='Muddler:BAABLgAECn8qAAIdAAgJlgI5GQChAAAdAAgJlgI5GQChAAAAAA==.Murgut:BAAALgAECgMJAwAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAAALgAECgYJDQAAAA==.Naledi:BAABLgAECn8cAAIQAAgJ4w/dJABIAQAQAAgJ4w/dJABIAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn8iAAILAAcJwx33QwDNAQALAAcJwx33QwDNAQAAAA==.Narella:BAABLgAECn8gAAILAAgJexGTVwCUAQALAAgJexGTVwCUAQAAAA==.',
Ne='Negrido:BAABLgAECn8vAAMPAAkJ8CU0CADnAgAPAAgJtyI0CADnAgAdAAMJNiWJJAA3AQAAAA==.Nei:BAABLgAECn8eAAIXAAcJJhXBVwB6AQAXAAcJJhXBVwB6AQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn8qAAMQAAgJoBU1FgDGAQAQAAgJoBU1FgDGAQATAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Noraelyn:BAABLgAECn8oAAMiAAgJLx2jJQD6AQAiAAYJhyCjJQD6AQAXAAQJjwMBAgFZAAAAAA==.Norelei:BAAALgAECgQJBAABLgAECggJHQATAB4SAA==.Noriyuki:BAABLgAECn8cAAIWAAYJqwGHZQBCAAAWAAYJqwGHZQBCAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAcJGQALAGUdAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8FAAMJAAMJfhs1EQAGAQAJAAMJfhs1EQAGAQAaAAEJwAEeJQA0AAAuAAQKfxYAAwkACAlSIx4FAKECAAkACAlSIx4FAKECABoAAwnADI9pAJgAAAEuAAQKCAkOAAUAAAAA.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8jAAIlAAcJyw8NGwA9AQAlAAcJyw8NGwA9AQAAAA==.',
Om='Omegâ:BAAALgAECgUJBQAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJCQAAAA==.Oppcookies:BAAALgAECgYJCwABLgAECggJEgAFAAAAAA==.Oppressin:BAAALgADCggJDAABLgAECggJEgAFAAAAAA==.Oppshot:BAAALgAECggJEgAAAA==.',
Or='Orin:BAAALgADCgEJAQAAAA==.',
Os='Oshìe:BAABLgAECn8pAAIiAAkJ2yFQDAC4AgAiAAkJ2yFQDAC4AgAAAA==.',
Ov='Overdoom:BAABLgAECn8yAAMDAAkJUR18HABZAgADAAkJUR18HABZAgAHAAUJHAY7MACNAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCgUJCwAAAA==.Paladinjohn:BAACLgAFFH8aAAIXAAUJKB++BwB3AQAXAAUJKB++BwB3AQAuAAQKfysAAhcACQkbJWMBANEDABcACQkbJWMBANEDAAAA.Palykat:BAABLgAECn8XAAIXAAcJvweXoQDoAAAXAAcJvweXoQDoAAAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pennywisé:BAABLgAECn8nAAIDAAkJUiAyDgC/AgADAAkJUiAyDgC/AgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJHwADAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8lAAMTAAkJhhdqCwDAAQATAAkJ4BZqCwDAAQAQAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAAALgAECgkJEwABLgAECgcJJgAUAAkaAA==.Ploofee:BAAALgAECgYJDQAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Progresz:BAABLgAECn8UAAILAAgJ5hHsWACRAQALAAgJ5hHsWACRAQAAAA==.',
Ps='Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8mAAIQAAkJjwnYKAAuAQAQAAkJjwnYKAAuAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.',
Qa='Qaren:BAAALgAECgMJBwAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raishun:BAAALgADCgYJBgAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn8wAAMoAAkJyx5NBABsAgAoAAkJiR1NBABsAgATAAEJQh18NQBSAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAAALgAFFAEJAQABLgAFFAQJCgAcAMYYAA==.Ratabi:BAAALgADCgIJAgAAAA==.Rawrski:BAAALgADCgEJAgABLgAECggJJgACAPkLAA==.',
Re='Reeven:BAAALgAECgkJJAAAAQ==.Ressurectjin:BAAALgAECgUJDAAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAABLgAFFH8JAAILAAQJVCC+HwCBAQALAAQJVCC+HwCBAQAAAA==.Rhetegast:BAABLgAECn8nAAIhAAkJrRPHDwDIAQAhAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECgUJCgAFAAAAAA==.',
Ri='Rike:BAEBLgAECn8jAAMXAAcJLyFhPQAvAgAXAAcJtSBhPQAvAgAhAAMJUiC1FwANAQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAFAAAAAA==.Roflhazotime:BAABLgAECn8kAAIRAAkJFyOOBQADAwARAAkJFyOOBQADAwAAAA==.Roland:BAABLgAECn8jAAMSAAYJMxNaTgAOAQASAAYJMxNaTgAOAQAQAAMJywYVTwB3AAAAAA==.Rolandin:BAABLgAECn8jAAIiAAcJ7xKXKgBsAQAiAAcJ7xKXKgBsAQAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgMJAwAAAA==.Rook:BAAALgAECgcJCQABLgAFFAUJHQABAO0iAA==.Roscjou:BAAALgAECgYJDgAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgADCgIJAgABLgAECgcJIgAPABkYAA==.',
Ry='Rylagosa:BAABLgAECn8qAAMGAAgJoRhQDgCcAQAGAAYJYhlQDgCcAQANAAQJpw4pWAB0AAAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8UAAILAAgJ6BEfWACTAQALAAgJ6BEfWACTAQAAAA==.',
['Rê']='Rêdrum:BAAALgAECgUJBQABLgAFFAQJEAAPALcHAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn8hAAISAAcJNhDhRgArAQASAAcJNhDhRgArAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJJQABAEMaAA==.Sarvinblue:BAABLgAECn8lAAMBAAkJQxqPFQBpAgABAAkJQxqPFQBpAgACAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgEJAQAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8ZAAIbAAcJkAYxDgABAQAbAAcJkAYxDgABAQAAAA==.Shazlulu:BAABLgAECn8ZAAIBAAcJmBsVHQAMAgABAAcJmBsVHQAMAgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8VAAIMAAcJTAqfCgAyAQAMAAcJTAqfCgAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIEAAkJlx8kCABcAgAEAAkJlx8kCABcAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8YAAIiAAgJNxn8EwAkAgAiAAgJNxn8EwAkAgAAAA==.Sloe:BAABLgAECn8gAAIKAAcJWx29GgAGAgAKAAcJWx29GgAGAgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBAAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedmeat:BAAALgAECgYJCgAAAA==.Sporkulous:BAABLgAECn8qAAMIAAgJig90TwBZAQAIAAgJig90TwBZAQAaAAEJFwHUNgASAAAAAA==.',
Sq='Squal:BAABLgAECn8lAAMXAAkJ6x1yGwBfAgAXAAkJPR1yGwBfAgAhAAUJghfQGgDrAAAAAA==.Squiggle:BAABLgAECn8nAAIhAAgJfBw1BwAYAgAhAAgJfBw1BwAYAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBwAAAA==.Stickybunz:BAABLgAECn8XAAIYAAcJnBcpHQC2AQAYAAcJnBcpHQC2AQABLgAECgkJMwAOAMYVAA==.Striker:BAEALgAECgMJBwABLgAECgcJIwAXAC8hAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAFAAAAAA==.Stunseed:BAABLgAECn8nAAITAAkJOBjdBgArAgATAAkJOBjdBgArAgAAAA==.',
Su='Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgUJBQAAAA==.Sunshíne:BAAALgAECgQJEAAAAA==.Surf:BAAALgAECgYJCAAAAA==.',
Sw='Sweetbunz:BAABLgAECn8zAAMOAAkJxhWOEgDuAQAOAAgJIhiOEgDuAQAKAAgJWQ6DIgBnAQAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8mAAIDAAgJGhtxLQACAgADAAgJGhtxLQACAgAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgUJDQAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJBgAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgcJIgAPABkYAA==.Taniss:BAABLgAECn8mAAIjAAgJxQfSCQAsAQAjAAgJxQfSCQAsAQAAAA==.Tanner:BAABLgAECn8bAAMaAAgJDgnESgAnAQAaAAgJwQfESgAnAQAIAAIJoBF5ogCHAAAAAA==.',
Te='Tedman:BAABLgAECn8ZAAMCAAcJMg/hNQAIAQACAAcJMQ/hNQAIAQABAAIJDAdWjwBaAAAAAA==.Temel:BAABLgAECn8mAAMCAAgJ+QvLLAA3AQACAAgJ+QvLLAA3AQABAAYJUwnrVwDtAAAAAA==.Tenelum:BAAALgAECgEJAQABLgAECggJJgACAPkLAA==.Testoecles:BAAALgAECgMJBQAAAA==.',
Th='Thadrack:BAABLgAECn8dAAILAAgJuwTIlQATAQALAAgJuwTIlQATAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAFAAAAAA==.Thalonstin:BAAALgADCgUJCAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQAFAAAAAA==.Theodrid:BAACLgAFFH8OAAIXAAUJbBG4GADnAAAXAAUJbBG4GADnAAAuAAQKfyIAAhcACAmPHzAkAJcCABcACAmPHzAkAJcCAAAA.Thraxia:BAABLgAECn8XAAIPAAgJWAUGlgAsAQAPAAgJWAUGlgAsAQAAAA==.Thutpithyuth:BAAALgAFFAIJAgAAAA==.',
Ti='Tinkíe:BAABLgAECn8eAAQWAAkJwxtsFQC5AQAWAAgJmBpsFQC5AQAUAAQJQRmWTgAJAQAVAAUJ2QxHPgDYAAAAAA==.Tirzahdozier:BAAALgAECgUJCgAAAA==.Tiwohnne:BAAALgADCgEJAQAAAA==.',
Tl='Tla:BAAALgADCgQJBAAAAA==.',
Tr='Treat:BAABLgAECn8uAAIOAAkJSCC1AwDzAgAOAAkJSCC1AwDzAgAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8IAAICAAQJRBb+DQBRAQACAAQJRBb+DQBRAQABLgAFFAkJLwAPAEchAA==.Tristitia:BAABLgAECn8aAAIDAAgJvRT5RQCpAQADAAgJvRT5RQCpAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIDAAkJAxzXGgBiAgADAAkJAxzXGgBiAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJBgALAE8TAA==.',
Ty='Tyche:BAAALgAECgMJBwAAAA==.Tysbich:BAAALgAECgQJBAABLgAECggJGQAiAOogAA==.',
Ui='Uiewedaoez:BAABLgAECn8wAAISAAkJOySuAQCgAwASAAkJOySuAQCgAwAAAA==.',
Um='Umakkel:BAAALgAECgUJBgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ7xATPADLAQADAAkJ7xATPADLAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMdAAYJJhD1HgBZAQAdAAYJJhD1HgBZAQAPAAIJ4gHuLwEhAAAAAA==.Vains:BAACLgAFFH8MAAIXAAQJkRz4FgBhAQAXAAQJkRz4FgBhAQAuAAQKfyIAAhcACQkvIaQTAJECABcACQkvIaQTAJECAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAAALgAECgQJBAAAAA==.Vardis:BAABLgAECn8sAAILAAkJMh8dHAB4AgALAAkJMh8dHAB4AgAAAA==.',
Ve='Velinami:BAAALgAECgEJAQAAAA==.Venato:BAAALgADCgEJBAABLgAECggJJgACAPkLAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAAALgAECgEJAQAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8jAAILAAcJoxhcXwCBAQALAAcJoxhcXwCBAQAAAA==.Verren:BAABLgAECn8ZAAITAAgJjxfqCwC3AQATAAgJjxfqCwC3AQAAAA==.Versutia:BAAALgADCgkJCQAAAA==.',
Vi='Virse:BAAALgAECgQJBwAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vyerith:BAABLgAECn8kAAIPAAkJjhxgGABYAgAPAAkJjhxgGABYAgAAAA==.',
We='Weltamus:BAABLgAECn8dAAIDAAYJKw+aggAVAQADAAYJKw+aggAVAQAAAA==.Weltasaur:BAAALgAECgMJBwAAAA==.Weltazar:BAABLgAECn8hAAICAAcJqBSWMwATAQACAAcJqBSWMwATAQAAAA==.Westside:BAACLgAFFH8ZAAMLAAcJZR3sBwAmAgALAAcJZR3sBwAmAgAMAAEJqAnrAgBJAAAuAAQKfyMAAgsACQnUJkEAAJkDAAsACQnUJkEAAJkDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAAPAG4jAA==.Wildtiger:BAABLgAECn8lAAIoAAgJ4w+SDQB9AQAoAAgJ4w+SDQB9AQAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8qAAQbAAkJch5/AQC1AgAbAAkJch5/AQC1AgAEAAMJoAfkUACkAAAjAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAgABLgAECggJJgACAPkLAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Xalreth:BAAALgAECggJEwAAAA==.Xaviana:BAAALgAECggJJAAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMOAAkJOgicJwA6AQAOAAgJOAecJwA6AQAKAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAIRAAkJzhg6KgDYAQARAAkJzhg6KgDYAQAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8tAAIiAAkJJiYtBAAfAwAiAAkJJiYtBAAfAwAAAA==.Yushi:BAABLgAECn8pAAIEAAkJXx8nBgCJAgAEAAkJXx8nBgCJAgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJDwAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8UAAMDAAgJrAlLcwA0AQADAAgJYghLcwA0AQAmAAYJKQUEFwCSAAAAAA==.Zenweaver:BAACLgAFFH8NAAIUAAMJTiELFgAoAQAUAAMJTiELFgAoAQAuAAQKfx4AAhQACQkhIlUEAEcDABQACQkhIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8bAAIDAAgJISHaFwB1AgADAAgJISHaFwB1AgAAAA==.',
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
