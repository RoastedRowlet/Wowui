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

local lookup = {'Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','Rogue-Subtlety','Unknown-Unknown','Paladin-Protection','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Priest-Holy','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Warlock-Affliction','Paladin-Retribution','Hunter-Marksmanship','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','DemonHunter-Havoc','Paladin-Holy','Evoker-Devastation','Priest-Discipline','Rogue-Outlaw','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Frost','Shaman-Enhancement','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarix:BAABLgAECn8UAAIBAAkJQREsKACpAQABAAkJQREsKACpAQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJDQAAAA==.Aegia:BAABLgAECn8ZAAMCAAcJrxA3VQBcAQACAAcJrxA3VQBcAQABAAMJTQGHgABFAAAAAA==.Aendillan:BAAALgAECgYJEwAAAA==.Aewrynn:BAAALgAECgIJAgAAAA==.',
Af='Affonasei:BAABLgAECn8zAAIDAAkJQQuPXQCtAQADAAkJQQuPXQCtAQAAAA==.',
Ai='Aicaramba:BAAALgAECgYJBwAAAA==.Aileen:BAAALgAFFAEJAQAAAA==.',
Ak='Akashi:BAAALgAFFAIJAwABLgAFFAMJEQAEAO0hAA==.',
Al='Alacrodie:BAAALgAECgIJAwAAAA==.Alladorn:BAAALgADCgEJAQAAAA==.Allarii:BAAALgAECgUJBQABLgAECgUJBQAFAAAAAA==.Allynoon:BAAALgADCgMJAwAAAA==.Alurynath:BAAALgADCgcJBwABLgAECgkJLgAGAIMeAA==.',
An='Anahla:BAAALgAECgUJBQABLgAECgkJOQAHAIIYAA==.Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgUJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8rAAIIAAkJ9yHXAwD9AgAIAAkJ9yHXAwD9AgAAAA==.',
Ar='Aragorno:BAABLgAECn8sAAMJAAkJrBdPJgBDAgAJAAkJrBdPJgBDAgAKAAQJRAZuQQC9AAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAABLgAECn8uAAIJAAgJZBoLMQAUAgAJAAgJZBoLMQAUAgAAAA==.Arenthal:BAAALgAECgUJCgABLgAFFAQJBwALAEgUAA==.Arkulas:BAAALgAECgYJBwAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgkJNwAMAAMcAA==.Ashiera:BAABLgAECn8yAAMLAAkJ+gPkpwArAQALAAkJ+gPkpwArAQANAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgcJDwAAAA==.',
Au='Aurorée:BAAALgAECgEJAQAAAA==.Ausuna:BAAALgAECgYJBwAAAA==.',
Av='Avelai:BAAALgADCgkJCQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJLQAEAJ8fAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgAECgYJCAAAAA==.Badonka:BAAALgAECgQJBAABLgAECgkJRgAOAMgdAA==.Bahaana:BAAALgAECgUJBQAAAA==.Balentine:BAABLgAECn8dAAMMAAgJMRPzOQALAQAMAAcJAhPzOQALAQAPAAUJxwP7RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJSQAQANMjAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn9GAAIOAAkJyB2dCQC9AgAOAAkJyB2dCQC9AgAAAA==.Baspir:BAABLgAECn8pAAIRAAkJNxbDIwCpAQARAAkJNxbDIwCpAQAAAA==.',
Be='Beeboop:BAAALgADCggJDAAAAA==.Belly:BAAALgAECgIJAgABLgAECgkJLQAEAJ8fAA==.Belrae:BAACLgAFFH8IAAISAAIJ0QY1hQBxAAASAAIJ0QY1hQBxAAAuAAQKfzUAAhIACQl0FjYlADYCABIACQl0FjYlADYCAAAA.Belrinthe:BAAALgAFFAIJAgAAAA==.Bezieck:BAABLgAECn80AAIPAAgJPxVoHgDQAQAPAAgJPxVoHgDQAQAAAA==.',
Bi='Bigdawg:BAAALgAECggJEAAAAA==.Bigdeborah:BAAALgAECgUJBQAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8oAAILAAkJ8w1bXwC/AQALAAkJ8w1bXwC/AQAAAA==.Birdbrain:BAAALgAFFAIJAgAAAA==.Biru:BAAALgAECgIJBQABLgAECggJJwAMABwdAA==.',
Bl='Bloodarrow:BAAALgAECgYJEQAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAABLgAECn8YAAMTAAYJ5ReTOACJAQATAAYJ5ReTOACJAQAUAAEJaRVFkgA7AAAAAA==.Bonegavel:BAAALgAECgUJBwAAAA==.Bookhuntress:BAABLgAECn8jAAQVAAcJ3RtAJgAfAgAVAAcJ3RtAJgAfAgARAAYJ5xdvMwBHAQAWAAEJnAwCgAAcAAAAAA==.Bordrann:BAAALgAECgIJAwAAAA==.Bosyoh:BAAALgAECgIJAgAAAA==.',
Br='Branaxe:BAAALgAECggJDQABLgAECgkJBwAFAAAAAA==.Brandisheer:BAAALgAECgYJCAAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAACLgAFFH8JAAIUAAUJbAm4HgDaAAAUAAUJbAm4HgDaAAAuAAQKfzQAAhcACQktH4sIAKgCABcACQktH4sIAKgCAAAA.Brewzer:BAACLgAFFH8SAAITAAQJuAsfNQDKAAATAAQJuAsfNQDKAAAuAAQKfyUAAxMACAmEE8g1AJYBABMACAmEE8g1AJYBABQABQmtDAlWALIAAAAA.Brint:BAABLgAECn8fAAMQAAgJNg+eagBmAQAQAAgJMw+eagBmAQAYAAEJshPkNwBCAAAAAA==.Brok:BAAALgAFFAMJAwAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8vAAILAAYJTCTvHwD/AQALAAYJTCTvHwD/AQAuAAQKfyIAAgsACAkXJdEjAOMCAAsACAkXJdEjAOMCAAAA.Bronst:BAAALgAECgEJAwABLgAECgkJMQABAOYYAA==.Broomhandle:BAABLgAECn8jAAIZAAkJQSQPBgBAAwAZAAkJQSQPBgBAAwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Burinn:BAAALgAECgcJCgABLgAECgkJSAAMAFkPAA==.',
Ca='Caeus:BAABLgAECn8wAAIDAAkJnyQOBwA9AwADAAkJnyQOBwA9AwAAAA==.Cam:BAABLgAECn8xAAILAAkJlCWKCwAbAwALAAkJlCWKCwAbAwAAAA==.Capriestson:BAAALgADCgkJCQABLgAECgYJDwAFAAAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAgJFgAaABgZAA==.Care:BAABLgAECn8ZAAILAAkJjAwciADBAQALAAkJjAwciADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAABLgAECn8bAAIbAAYJuxJdIwARAQAbAAYJuxJdIwARAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Chacruna:BAAALgAECgQJBAAAAA==.Charmed:BAAALgAECgUJBgAAAA==.Cheesús:BAAALgAECggJCgAAAA==.Chelan:BAABLgAECn9IAAMMAAkJWQ9dIgCrAQAMAAkJWQ9dIgCrAQAPAAkJjgX+OAAtAQAAAA==.Chiji:BAAALgAECgYJBQAAAA==.Chilljaeden:BAAALgAECgUJDQAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.Chuntspeed:BAAALgADCgYJBgAAAA==.Chuye:BAAALgAECgEJAQABLgAECggJJwAMABwdAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAgJHwALAIceAA==.Cindyloowhoo:BAAALgADCgMJAwAAAA==.Cinnabunz:BAABLgAECn8eAAIQAAcJBwgemwAHAQAQAAcJBwgemwAHAQAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cleurisse:BAABLgAFFH8RAAIIAAUJaBeaFwAmAQAIAAUJaBeaFwAmAQAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgUJDgABLgAECgkJNAAZAAggAA==.',
Co='Codythedead:BAABLgAFFH8FAAIDAAIJ7RT71ACLAAADAAIJ7RT71ACLAAAAAA==.Compadre:BAABLgAECn8XAAQUAAgJPh7NHQDrAQAUAAcJ0RrNHQDrAQAXAAQJUiAiRAAyAQATAAYJWxE4RADMAAAAAA==.Contekst:BAABLgAECn8hAAMVAAcJ5w8WWAAuAQAVAAcJ5w8WWAAuAQARAAcJxAYwVgCzAAAAAA==.Coolsbeans:BAAALgAECgYJCwAAAA==.Coraf:BAACLgAFFH8qAAICAAcJ9iBYAwCYAgACAAcJ9iBYAwCYAgAuAAQKfzgAAgIACQkAJMABAHQDAAIACQkAJMABAHQDAAAA.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgYJBgAAAA==.Cruoris:BAABLgAECn8bAAIcAAcJww1rDwArAQAcAAcJww1rDwArAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAABLgAECn8hAAIcAAcJMQU0EwDxAAAcAAcJMQU0EwDxAAAAAA==.',
Da='Daddle:BAABLgAECn8gAAQQAAkJayP3DgDTAgAQAAkJ5iH3DgDTAgAYAAYJWSLgCQC/AQAdAAEJAABkUwAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgMJBQAAAA==.Daeththane:BAAALgAECgEJAQAAAA==.Dahaxors:BAABLgAECn8lAAIDAAkJGxvrLgBBAgADAAkJGxvrLgBBAgAAAA==.Dalareas:BAAALgAECgMJAwAAAA==.Danak:BAAALgAECgIJAwAAAA==.Dannika:BAAALgAECgYJBwAAAA==.Dantelous:BAAALgAECgEJAQAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAABLgAECn8lAAMEAAgJvQuEJABtAQAEAAgJZguEJABtAQAcAAUJNAdrFwC4AAAAAA==.',
De='Deadlyfrosty:BAABLgAECn8XAAIDAAYJAAMhCwGZAAADAAYJAAMhCwGZAAAAAA==.Deathsfather:BAAALgADCgYJBgABLgAECgUJBwAFAAAAAA==.Debixie:BAACLgAFFH8SAAIcAAQJyB3JAgB/AQAcAAQJyB3JAgB/AQAuAAQKfyUAAhwACQlLI04BACUDABwACQlLI04BACUDAAAA.Dejection:BAAALgAECgEJAQAAAA==.Delron:BAAALgADCgEJAQAAAA==.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8iAAMSAAkJQSJLFQCWAgASAAgJZCJLFQCWAgAeAAEJTCGGVQBgAAAAAA==.Demsynth:BAAALgAECgQJBAABLgAECgkJJgANAOYgAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJSQAQANMjAA==.Destorr:BAAALgADCgQJBAAAAA==.Dextero:BAAALgADCgMJAwAAAA==.',
Di='Diasundra:BAABLgAECn8sAAIJAAkJ5h9NDgDKAgAJAAkJ5h9NDgDKAgAAAA==.Digiornos:BAABLgAECn8jAAIQAAkJqhSzPADoAQAQAAkJqhSzPADoAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8kAAMQAAcJrBYpJACuAQAQAAYJIhopJACuAQAdAAEJXQX5IgBOAAAuAAQKfzUAAxAACQnvH5oPAM4CABAACQnvH5oPAM4CAB0AAwlMHzYsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECggJFgAfAMASAA==.Dragonpo:BAAALgAECgEJAQAAAA==.Drakkonde:BAABLgAECn8bAAIQAAYJUhb3dwBIAQAQAAYJUhb3dwBIAQAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dreamon:BAAALgAFFAEJAQAAAA==.Drransom:BAAALgAECgEJAQAAAA==.Dryan:BAAALgAECgYJEQAAAA==.Dryon:BAABLgAECn8zAAIbAAkJPB8xBQDGAgAbAAkJPB8xBQDGAgAAAA==.',
Du='Duergan:BAAALgADCgEJAQAAAA==.Duo:BAABLgAECn8xAAIJAAkJXBPQRQDMAQAJAAkJXBPQRQDMAQAAAA==.Duragon:BAABLgAECn8yAAQOAAkJ7RaQGAARAgAOAAkJ7RaQGAARAgAgAAgJPwXSFQCyAAAHAAYJPwe+JgCxAAAAAA==.',
['Dí']='Díznutz:BAABLgAECn8OAAISAAYJ6RBJeAA+AQASAAYJ6RBJeAA+AQABLgAFFAMJBQAJAFsaAA==.',
El='Eldumir:BAAALgADCgIJAgABLgAECgkJLgAGAIMeAA==.Elyleath:BAAALgAECgYJBgAAAA==.',
Em='Emilia:BAABLgAECn8cAAIMAAkJ+wppKwBpAQAMAAkJ+wppKwBpAQAAAA==.Empanada:BAAALgADCgEJAQAAAA==.',
En='Endressa:BAABLgAECn8xAAMhAAkJPw+lGgD4AQAhAAkJPw+lGgD4AQAPAAIJ6AlJbABoAAAAAA==.English:BAABLgAECn8zAAILAAkJdBvNNgA7AgALAAkJdBvNNgA7AgAAAA==.',
Er='Erelios:BAABLgAECn8uAAIGAAkJgx5BBQCcAgAGAAkJgx5BBQCcAgAAAA==.',
Es='Eski:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAEALgAECgMJBwABLgAECgkJMQAfACYmAA==.',
Ev='Evangelina:BAACLgAFFH8gAAMOAAgJoBtuCQBXAgAOAAgJoBtuCQBXAgAgAAEJygr9CQBTAAAuAAQKfygAAw4ACQmjJe8BAGMDAA4ACQmjJe8BAGMDACAABgmRI78PAN8BAAAA.Everlight:BAAALgAECgQJBQABLgAECgkJJgAWAM0TAA==.Evileyes:BAAALgADCgMJAgAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Ez='Ezrì:BAAALgAECgIJAwAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIJAAkJSxYIOgDyAQAJAAkJSxYIOgDyAQAAAA==.Fastbeefball:BAAALgADCggJDAAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAgJIAAOAKAbAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgAECgYJCwAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAgJHwALAIceAA==.Fish:BAACLgAFFH8lAAIPAAcJ8iaOAQCpAgAPAAcJ8iaOAQCpAgAuAAQKfzcAAg8ACAmOJlYCAIwDAA8ACAmOJlYCAIwDAAEuAAUUCAk3AA8AfCYA.',
Fl='Flight:BAACLgAFFH8RAAMEAAMJ7SGsIwD+AAAEAAMJ7SGsIwD+AAAiAAIJFRQaDACXAAAuAAQKfx0AAwQACAkRHHcUAG8CAAQACAljG3cUAG8CABwAAQkBDiweADwAAAAA.Fluxyouup:BAABLgAECn8gAAMCAAkJmgj4VQBZAQACAAkJmgj4VQBZAQABAAYJCQX/ZgCtAAAAAA==.Fløki:BAAALgAECgIJAgAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAABLgAECn8mAAMNAAkJ5iDSAADhAgANAAkJ5iDSAADhAgALAAEJAABIdQEwAAAAAA==.',
Fr='Frrostitute:BAAALgADCgEJAQAAAA==.',
Ge='Gewitt:BAABLgAECn8tAAMCAAkJgh6rFQCZAgACAAkJgh6rFQCZAgABAAgJ2hnYKADNAQAAAA==.',
Gg='Ggiven:BAABLgAECn8XAAISAAcJjRLkXwBmAQASAAcJjRLkXwBmAQAAAA==.',
Gl='Glinda:BAAALgAECgEJAgABLgAECgIJAgAFAAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8lAAILAAcJJh4bEwBSAgALAAcJJh4bEwBSAgAuAAQKf1kAAgsACQkmJlIDAMoDAAsACQkmJlIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJSQAQANMjAA==.Grazienne:BAAALgAECgEJAgAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8tAAIWAAkJhx+4BQCnAgAWAAkJhx+4BQCnAgAAAA==.Grimbaine:BAABLgAECn80AAIZAAkJ/yLdBwArAwAZAAkJ/yLdBwArAwAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Grimmshady:BAAALgAECgEJAQAAAA==.Grizzlegrimm:BAAALgAECgEJAgAAAA==.Groot:BAAALgAECgkJAQAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAABLgAECn8nAAQMAAgJHB0UEQBXAgAMAAgJHB0UEQBXAgAhAAIJSQdQagBTAAAPAAEJ1AOXZwAqAAAAAA==.Gurney:BAABLgAECn8qAAMfAAkJ/hYGHQAZAgAfAAkJ/hYGHQAZAgAGAAEJggTTVwAdAAAAAA==.Guzfu:BAABLgAECn8UAAIUAAcJgg3LSADaAAAUAAcJgg3LSADaAAAAAA==.',
Gw='Gwenory:BAAALgAECgEJAQAAAA==.',
Gy='Gying:BAABLgAECn85AAMXAAgJoR7pDABmAgAXAAgJoR7pDABmAgAUAAUJcg8FQAAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgYJDgAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgAECgEJAgAAAA==.Happyelf:BAAALgAECgYJDgAAAA==.Hartephinar:BAAALgAECgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8YAAICAAgJFw7IVwBSAQACAAgJFw7IVwBSAQAAAA==.Hexxiz:BAAALgAECggJDAABLgAECgkJOQAVAB4kAA==.',
Hi='Hiphopinator:BAABLgAECn8uAAMjAAkJliRZBgD4AgAjAAkJCSNZBgD4AgAbAAYJ/SRFDwDxAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgcJEwAAAA==.Holyterror:BAAALgAECgEJAgAAAA==.Honeysweety:BAAALgADCgMJAwAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgAECgQJCwAAAA==.',
Ia='Iamcro:BAAALgAECgUJBgAAAA==.Ianthe:BAABLgAECn8sAAINAAgJwAi7BwAoAQANAAgJwAi7BwAoAQAAAA==.',
Ib='Iboga:BAAALgAECgUJBwAAAA==.Ibrahimovic:BAABLgAECn80AAQdAAcJryOPCwCCAQAdAAUJHCSPCwCCAQAYAAYJURnoDgBpAQAQAAQJjB1kewBBAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.Igram:BAAALgADCggJCAAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Il='Illidoonger:BAAALgAECgYJDwAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAgJIAAOAKAbAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgYJDAAAAA==.Infoxicated:BAAALgAECgUJCgABLgAECgYJCAAFAAAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgQJBwAAAA==.',
Io='Iowastyle:BAABLgAECn84AAMMAAkJHSCRBQAeAwAMAAkJHSCRBQAeAwAhAAMJlgx+QwCZAAAAAA==.',
It='Ithruyn:BAAALgADCgQJBAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8SAAMYAAQJxhiSBAA9AQAYAAQJxhiSBAA9AQAQAAEJlA31wwBCAAAuAAQKfzcABBgACQmmIYwEAFACABgACQmXIYwEAFACABAABgnGGVFBANcBAB0AAgm6EoBTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgQJBQAAAA==.Jamurra:BAAALgAECgQJDgABLgAECggJFgAfAMASAA==.Jaylinn:BAABLgAECn8uAAIJAAkJ4Q0jUwClAQAJAAkJ4Q0jUwClAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Je='Jeanne:BAAALgAECgYJBwAAAA==.',
Ji='Jimsonweed:BAAALgAECgUJDAAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8pAAIhAAkJFiQ4BABSAwAhAAkJFiQ4BABSAwAAAA==.',
Ju='Judgekoopa:BAABLgAECn8pAAIfAAkJcx34CgDbAgAfAAkJcx34CgDbAgAAAA==.',
Ka='Kaadore:BAAALgAECgYJBwAAAA==.Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAABLgAECn8uAAMBAAgJzRSaJwCsAQABAAgJzRSaJwCsAQACAAUJ0QxsfgDfAAAAAA==.Kaleberry:BAABLgAECn8fAAMRAAkJBA56JQCcAQARAAgJBA56JQCcAQAVAAcJEgmlhgDJAAAAAA==.Kalyandra:BAABLgAECn8mAAIUAAcJdxBzMwAyAQAUAAcJdxBzMwAyAQAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanhang:BAAALgADCgcJDAAAAA==.Kanra:BAABLgAECn8XAAQWAAYJ6Rz0FgCVAQAWAAYJ6Rz0FgCVAQAVAAYJLgxiaAD4AAARAAEJvBI/hwA4AAABLgAECgkJKwAGAFQiAA==.Karkevon:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8eAAIjAAkJAh1fFgA6AgAjAAkJAh1fFgA6AgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAABLgAECn8oAAISAAkJLho8GQB7AgASAAkJLho8GQB7AgAAAA==.Karumie:BAABLgAECn8nAAICAAkJZhz/HgBTAgACAAkJZhz/HgBTAgAAAA==.Kashyyk:BAAALgAECgMJAwABLgAECgkJOwAQAJkaAA==.Kateera:BAAALgAECgUJCwAAAA==.',
Ke='Keden:BAAALgAECgIJAwAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAABLgAECn8XAAIkAAkJjiAbAwADAwAkAAkJjiAbAwADAwABLgAECgkJLAASAEEiAA==.Kels:BAABLgAECn8sAAISAAkJQSK/DADdAgASAAkJQSK/DADdAgAAAA==.',
Kh='Kheyra:BAABLgAECn8mAAIWAAkJzRMQEgDJAQAWAAkJzRMQEgDJAQAAAA==.',
Ki='Kiaona:BAAALgADCgMJAwAAAA==.Kidashia:BAAALgAECgQJBAAAAA==.Kiwisloth:BAAALgAFFAEJAQABLgAFFAkJSQAQANMjAA==.',
Ko='Koggs:BAAALgAFFAIJAgAAAA==.Kohnor:BAAALgAECgIJAwAAAA==.Kopi:BAAALgAECgMJAwABLgAECgkJKwAIAPchAA==.Korlatt:BAABLgAECn86AAQSAAkJqR6SEgCrAgASAAkJQh2SEgCrAgAlAAMJDRzoFgDqAAAeAAMJOhaRVQBgAAAAAA==.Kowalabear:BAABLgAECn8rAAMmAAkJtCExAQD+AgAmAAkJtCExAQD+AgAIAAQJPwq2SwBeAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAALADgXAA==.',
Kt='Kthanid:BAABLgAECn8VAAIhAAYJog8yMgBPAQAhAAYJog8yMgBPAQAAAA==.',
Ku='Kurston:BAABLgAECn9DAAIVAAkJMRsiEwCwAgAVAAkJMRsiEwCwAgAAAA==.',
Ky='Kymakazie:BAABLgAECn8YAAIJAAkJjQMWlgAOAQAJAAkJjQMWlgAOAQAAAA==.',
['Kã']='Kãtniss:BAAALgAECgEJAQAAAA==.',
La='Laih:BAABLgAECn8iAAIcAAkJgA+PCAC+AQAcAAkJgA+PCAC+AQAAAA==.Lasturus:BAAALgAECgUJBQABLgAFFAgJIwATAAMZAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Lauraenital:BAAALgAECgQJBAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQABLgAECggJFgAXAHsYAA==.Letmeout:BAAALgAECgEJAQAAAA==.Lexx:BAAALgAECgIJAgAAAA==.Leyote:BAABLgAECn87AAICAAkJDBPbKwAGAgACAAkJDBPbKwAGAgAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Liirah:BAAALgAECgEJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.Listriesa:BAAALgADCgEJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMUAAYJZBofNABRAQAUAAUJkxYfNABRAQAXAAQJ+xkLRgAqAQABLgAECggJGAAIAOIiAA==.Lorianne:BAAALgAECgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8tAAISAAkJthcSJQA3AgASAAkJthcSJQA3AgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAABLgAECn8dAAMPAAkJ3AYVMwBLAQAPAAkJ3AYVMwBLAQAMAAMJfwNTaQA9AAAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luthein:BAAALgAECgYJDwAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8iAAIZAAkJoQ48YwCnAQAZAAkJoQ48YwCnAQAAAA==.Lynniebee:BAABLgAECn8pAAINAAkJjAwEBQCRAQANAAkJjAwEBQCRAQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJDAAAAA==.Magicpie:BAAALgAECgcJBwABLgAECgkJPgAlANIkAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAABLgAECn8eAAMnAAkJTg7cEACgAQAnAAkJTg7cEACgAQABAAEJ7QFmlQAgAAAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Maneke:BAAALgADCgkJCQABLgAECgkJLgACAIUUAA==.Marovingian:BAABLgAECn8tAAIfAAkJ4yE6AwBtAwAfAAkJ4yE6AwBtAwAAAA==.Matthad:BAABLgAECn8uAAICAAkJhRTDJgAiAgACAAkJhRTDJgAiAgAAAA==.Mazìkene:BAACLgAFFH8ZAAMYAAUJWQ30CADmAAAQAAQJ0geJZgDzAAAYAAQJ2g/0CADmAAAuAAQKfyYAAxAACQkuFzJQAKoBABAACQk2FjJQAKoBABgABQlSHCoRAEsBAAAA.',
Mc='Mccone:BAABLgAECn8XAAIJAAYJYwlPrADlAAAJAAYJYwlPrADlAAAAAA==.Mcsluts:BAABLgAECn8gAAMZAAYJDhA/vgAIAQAZAAYJkw4/vgAIAQAGAAEJaBCgUgApAAAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAgJIAAOAKAbAA==.Melmirict:BAACLgAFFH8SAAIEAAUJWBJXHwAiAQAEAAUJWBJXHwAiAQAuAAQKfyUAAwQACQlQGWQTAAYCAAQACQlQGWQTAAYCABwAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn9DAAIWAAkJdRJAFwCSAQAWAAkJdRJAFwCSAQAAAA==.',
Mi='Milyva:BAAALgADCgMJAwAAAA==.Milyyanna:BAAALgAECgIJBAAAAA==.Minaby:BAAALgAECgYJEAABLgAECgkJIwAZAEEkAA==.Missmurder:BAAALgAECgEJAgAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn87AAQQAAkJmRrOKgAtAgAQAAgJSxzOKgAtAgAYAAIJkg4OOwA5AAAdAAIJuw6yPQAyAAAAAA==.Mohawk:BAAALgAECgcJDAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgAECgEJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8jAAMJAAkJrh8UNwD9AQAKAAgJmBlUEgAXAgAJAAgJIB4UNwD9AQAAAA==.Molen:BAAALgAECgUJBwAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAgJIAAOAKAbAA==.Monkeeh:BAAALgADCgUJCAAAAA==.Monkle:BAABLgAECn9LAAIUAAkJ/CS1AQBZAwAUAAkJ/CS1AQBZAwAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAUJDgAEAHcbAA==.Moonsii:BAABLgAECn8aAAIVAAkJ9Q0PPQCcAQAVAAkJ9Q0PPQCcAQAAAA==.Mooroth:BAABLgAECn9CAAIbAAkJPSBBBADiAgAbAAkJPSBBBADiAgABLgAFFAIJAgAFAAAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAABLgAECn8eAAImAAgJShpRCAAIAgAmAAgJShpRCAAIAgAAAA==.',
Mu='Muddler:BAABLgAECn9CAAIdAAkJlAMUHADCAAAdAAkJlAMUHADCAAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgAECgQJBAAAAA==.',
['Mà']='Màggles:BAAALgADCggJCAAAAA==.',
Na='Nadd:BAABLgAECn8fAAIJAAcJtQqqgAA4AQAJAAcJtQqqgAA4AQAAAA==.Naledi:BAABLgAECn8cAAIRAAgJ5Q/8MgBKAQARAAgJ5Q/8MgBKAQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn86AAMLAAkJjSGOEgDoAgALAAkJ1yCOEgDoAgANAAIJ2R45DAC1AAAAAA==.Narella:BAABLgAECn8tAAILAAgJjRTVYwCzAQALAAgJjRTVYwCzAQAAAA==.',
Ne='Negotiable:BAAALgAECgUJCAAAAA==.Negrido:BAABLgAECn8zAAQQAAkJ+yW0DgDVAgAQAAgJwSK0DgDVAgAdAAMJNiWJJAA3AQAYAAEJvx8SMABaAAAAAA==.Nei:BAABLgAECn84AAIZAAgJ+BkpNgAmAgAZAAgJ+BkpNgAmAgAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn82AAMRAAkJ6BmqEABWAgARAAkJ6BmqEABWAgAWAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCQAAAA==.Nor:BAAALgAECgUJCgAAAA==.Noraelyn:BAABLgAECn8zAAMfAAkJ7xsNDQC+AgAfAAkJ7xsNDQC+AgAZAAQJewRrSwFeAAAAAA==.Norelei:BAAALgAECgUJBwABLgAECgkJJgAWAM0TAA==.Noriyuki:BAABLgAECn8uAAIUAAcJDgLygwBNAAAUAAcJDgLygwBNAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAgJHwALAIceAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAACLgAFFH8IAAQKAAQJFhUjFgAbAQAKAAQJFhUjFgAbAQAJAAEJFwYhpABDAAAaAAEJwAHyOgAtAAAuAAQKfxcAAwoACAlSIyAKAHsCAAoACAlSIyAKAHsCABoAAwnADI9pAJgAAAEuAAQKCAkXAA8AkRoA.Nuudles:BAAALgAECgEJAQAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Oa='Oakenia:BAAALgADCgQJBAABLgAECgkJOQAVAO8QAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn88AAIeAAkJLBIsFwDIAQAeAAkJLBIsFwDIAQAAAA==.Oluja:BAAALgAECgYJDwAAAA==.',
Om='Omegâ:BAAALgAFFAEJAQAAAA==.Omens:BAAALgAECgUJBQABLgAFFAUJDgAEAHcbAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.Onuris:BAAALgAECgEJAQAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECggJEAAAAA==.Oppcookies:BAAALgAECgYJDwABLgAECgkJIAAJAHQXAA==.Oppressin:BAAALgADCggJDAABLgAECgkJIAAJAHQXAA==.Oppshot:BAABLgAECn8gAAMJAAkJdBd/KQA0AgAJAAkJdBd/KQA0AgAaAAEJUAnnPQAsAAAAAA==.',
Or='Orin:BAAALgAECgEJAQAAAA==.',
Os='Oshìe:BAACLgAFFH8FAAIfAAMJFxEGMgCkAAAfAAMJFxEGMgCkAAAuAAQKfykAAh8ACQnbIVAMALgCAB8ACQnbIVAMALgCAAAA.',
Ov='Overdoom:BAABLgAECn82AAMDAAkJYx4rKgBVAgADAAkJYx4rKgBVAgAIAAUJHAaGQgCCAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCggJEgAAAA==.Paladinjohn:BAACLgAFFH8nAAIZAAcJgh09CQAyAgAZAAcJgh09CQAyAgAuAAQKfysAAhkACQkbJWMBANEDABkACQkbJWMBANEDAAAA.Palykat:BAABLgAECn8qAAIZAAgJNAgFrgAfAQAZAAgJNAgFrgAfAQAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pelagos:BAAALgAECggJCgAAAA==.Pennywisé:BAABLgAECn8rAAIDAAkJUyDFGgCkAgADAAkJUyDFGgCkAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJIgADAEMfAA==.',
Ph='Phillygg:BAAALgAECgQJBAAAAA==.Phoeniix:BAABLgAECn8mAAMWAAkJiBcXEwC9AQAWAAkJ4hYXEwC9AQARAAQJvRe1UgDcAAAAAA==.',
Pl='Plaguegying:BAABLgAECn8eAAMDAAkJnA/GZACbAQADAAgJ8w/GZACbAQAIAAEJOQ1DWAA7AAABLgAECggJOQAXAKEeAA==.Ploofee:BAAALgAECggJDwAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Prog:BAAALgAECgEJAQAAAA==.Progresz:BAABLgAECn8WAAILAAkJwRDGXgDAAQALAAkJwRDGXgDAAQAAAA==.',
Ps='Psichosa:BAAALgAECggJDgAAAA==.Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8nAAIRAAkJ2QkzOAAvAQARAAkJ2QkzOAAvAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.Pyrivia:BAAALgAECgEJAgABLgAECgUJCgAFAAAAAA==.',
Qa='Qaren:BAABLgAECn8VAAIZAAYJ9QXeBgGsAAAZAAYJ9QXeBgGsAAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raethe:BAAALgAECgQJBAAAAA==.Raishun:BAAALgAECgMJAwAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rajak:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn80AAQoAAkJVSByBgB7AgAoAAkJFB9yBgB7AgAWAAEJQh1bXQBQAAARAAIJ6wfgfQBIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAACLgAFFH8GAAILAAMJyApeigDJAAALAAMJyApeigDJAAAuAAQKfxUAAgsACAkiFGVdAMMBAAsACAkiFGVdAMMBAAEuAAUUBAkSABgAxhgA.Ratabi:BAAALgADCgIJAgAAAA==.Ravna:BAAALgAECggJEAABLgAECgkJOAARAI8aAA==.Rawrski:BAAALgADCgEJAgABLgAECgkJNgACAH0OAA==.',
Re='Reavert:BAAALgADCgYJBgAAAA==.Reeven:BAAALgAECgkJNQAAAQ==.Ressurectjin:BAAALgAECgUJDgAAAA==.Rexmortis:BAAALgAECgkJAgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAACLgAFFH8NAAILAAQJUSLCQwBlAQALAAQJUSLCQwBlAQAuAAQKfxwAAgsACQmKIdQVANQCAAsACQmKIdQVANQCAAAA.Rhetegast:BAABLgAECn8oAAIGAAkJrRPHDwDIAQAGAAkJrRPHDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECggJFgAfAMASAA==.',
Ri='Rike:BAEBLgAECn88AAMZAAkJ+iKrHgCMAgAZAAkJ5SGrHgCMAgAGAAYJlB68EAC0AQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAFAAAAAA==.Roflhazotime:BAABLgAECn8nAAISAAkJVyNiCQD/AgASAAkJVyNiCQD/AgAAAA==.Roland:BAABLgAECn8xAAMVAAkJlxMOMADgAQAVAAkJlxMOMADgAQARAAYJQQs/TADWAAAAAA==.Rolandin:BAABLgAECn88AAIfAAkJ1ReLEgB7AgAfAAkJ1ReLEgB7AgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rollan:BAAALgAECgQJCwAAAA==.Rook:BAABLgAFFH8JAAIEAAQJfxRsGgA+AQAEAAQJfxRsGgA+AQABLgAFFAcJKgACAPYgAA==.Roscjou:BAABLgAECn8YAAIBAAcJsQREXwDDAAABAAcJsQREXwDDAAAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.Ruh:BAAALgAECgMJBgABLgAECgkJOwAQAJkaAA==.',
Ry='Rylagosa:BAABLgAECn85AAMHAAkJghhbDwDSAQAHAAcJNxhbDwDSAQAOAAkJZRIoJQCzAQAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8XAAILAAkJGRFqWADRAQALAAkJGRFqWADRAQAAAA==.',
['Rê']='Rêdrum:BAABLgAFFH8GAAIDAAMJrgvfpQDMAAADAAMJrgvfpQDMAAABLgAFFAUJGQAYAFkNAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Sahathiel:BAAALgAFFAEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn85AAIVAAkJ7xBZMgDUAQAVAAkJ7xBZMgDUAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECgkJKwACAEscAA==.Sarvinblue:BAABLgAECn8rAAMCAAkJSxzIFQCYAgACAAkJSxzIFQCYAgABAAMJLQ8SagCbAAAAAA==.Saucestash:BAAALgAECgIJAgAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Searchlights:BAAALgAECgYJBgAAAA==.Seshu:BAAALgAECgEJAQAAAA==.Sevrin:BAAALgADCgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanaynay:BAAALgADCgUJBgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8bAAIcAAcJkAZLEwDwAAAcAAcJkAZLEwDwAAAAAA==.Shazlulu:BAABLgAECn8gAAICAAcJmBvxLAAAAgACAAcJmBvxLAAAAgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8iAAINAAkJkAozBgBgAQANAAkJkAozBgBgAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8tAAIEAAkJnx+hDgA9AgAEAAkJnx+hDgA9AgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8jAAIfAAkJtxl6FQBeAgAfAAkJtxl6FQBeAgAAAA==.Sloe:BAABLgAECn83AAIMAAkJAxxcDQCNAgAMAAkJAxxcDQCNAgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBQAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgQJBQAAAA==.',
Sp='Speedbeefbal:BAAALgADCgQJBAAAAA==.Speedkweef:BAAALgAECggJDgAAAA==.Speedmeat:BAABLgAECn8bAAMCAAkJAgjzZwAeAQACAAgJtgfzZwAeAQABAAIJmAOxmgA+AAAAAA==.Spinny:BAAALgAECgYJBgAAAA==.Sporkulous:BAABLgAECn8vAAMJAAgJfxOOSADDAQAJAAgJfxOOSADDAQAaAAEJFwHkRgAQAAAAAA==.',
Sq='Squal:BAABLgAECn80AAMZAAkJCCAjEADjAgAZAAkJCCAjEADjAgAGAAUJ/BjlGgA9AQAAAA==.Squiggle:BAABLgAECn89AAIGAAkJjSIxAgATAwAGAAkJjSIxAgATAwAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBwAAAA==.Stickybunz:BAABLgAECn8ZAAIjAAgJURV+JQDKAQAjAAgJURV+JQDKAQABLgAFFAQJDwAPAHAFAA==.Stinkyrafiki:BAACLgAFFH8eAAIjAAYJZh/2CQC4AQAjAAYJZh/2CQC4AQAuAAQKfxkAAyMABwl/IyskADUCACMABwl/IyskADUCACQAAgnfGNcrAJUAAAEuAAUUBgkeACMAZh8A.Striker:BAEALgAECgQJDwABLgAECgkJPAAZAPoiAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAFAAAAAA==.Stunseed:BAABLgAECn8rAAIWAAkJ1hgOCwAuAgAWAAkJ1hgOCwAuAgAAAA==.',
Su='Sumo:BAAALgAECgEJAQAAAA==.Sungjinwu:BAAALgAECgUJBQAAAA==.Sunnmage:BAAALgAECgUJBQAAAA==.Sunshíne:BAABLgAECn8aAAMZAAkJQggorQAhAQAZAAgJQQcorQAhAQAGAAMJeArLNQCGAAAAAA==.Surf:BAABLgAECn8XAAISAAcJWBy1NwDkAQASAAcJWBy1NwDkAQAAAA==.',
Sw='Sweetbunz:BAACLgAFFH8PAAMPAAQJcAWnJADLAAAPAAQJcAWnJADLAAAMAAQJAAkiHQDKAAAuAAQKfzoAAw8ACQnHFtQWABICAA8ACQnHFtQWABICAAwACAlYDm4wAEgBAAAA.Swegin:BAAALgAECgIJAgAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8pAAMDAAkJ2Bk+RgDtAQADAAgJGxs+RgDtAQAIAAEJCREiVwA9AAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgYJDwAAAA==.',
['Sí']='Sírlancealot:BAAALgADCgYJBgABLgAECgYJDwAFAAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Takers:BAAALgAECgYJBwAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgkJOwAQAJkaAA==.Taniss:BAABLgAECn8pAAIiAAkJlQhyCwBgAQAiAAkJlQhyCwBgAQAAAA==.Tanner:BAABLgAECn8cAAMaAAgJDgnESgAnAQAaAAgJwQfESgAnAQAJAAIJoBF5ogCHAAAAAA==.',
Te='Teboe:BAAALgAECgYJBwAAAA==.Tedman:BAABLgAECn8vAAMBAAkJjRn4EgBUAgABAAkJjRn4EgBUAgACAAMJmgdWjwBaAAAAAA==.Temel:BAABLgAECn82AAMCAAkJfQ4KTQB4AQACAAgJtwwKTQB4AQABAAkJUw0hMwBsAQAAAA==.Tenelum:BAAALgAECgMJBwABLgAECgkJNgACAH0OAA==.Testoecles:BAAALgAECgMJBQABLgAECgYJBwAFAAAAAA==.',
Th='Thadrack:BAABLgAECn81AAILAAgJvgjbmABEAQALAAgJvgjbmABEAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAFAAAAAA==.Thalonstin:BAAALgAECgMJBwAAAA==.Thanee:BAABLgAFFH8GAAIMAAUJDQ+VEwAkAQAMAAUJDQ+VEwAkAQAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Theodrid:BAACLgAFFH8SAAIZAAcJiRK2IwByAQAZAAcJiRK2IwByAQAuAAQKfyMAAhkACQmhHjAkAJcCABkACQmhHjAkAJcCAAAA.Thoreum:BAAALgAECgEJAgAAAA==.Thraxia:BAABLgAECn8XAAIQAAgJWAUGlgAsAQAQAAgJWAUGlgAsAQAAAA==.Thrombin:BAAALgAECgMJAwAAAA==.Thutpithyuth:BAACLgAFFH8FAAIJAAMJWxqAVgDxAAAJAAMJWxqAVgDxAAAuAAQKfxcAAgkACQkgH6AQAMgCAAkACQkgH6AQAMgCAAAA.',
Ti='Tigertigress:BAAALgAECgQJBAAAAA==.Tinkíe:BAABLgAECn8iAAQUAAkJ9Rw3GQDkAQAUAAgJ0Bw3GQDkAQAXAAQJQRmWTgAJAQATAAUJ2QyLZgDaAAAAAA==.Tirzahdozier:BAABLgAECn8WAAMfAAgJwBKrJQDYAQAfAAgJwBKrJQDYAQAZAAEJXwJGyAEYAAAAAA==.Tiwohnne:BAAALgAECgYJCgAAAA==.',
Tl='Tla:BAAALgAECgEJAgAAAA==.',
To='Tooey:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAABLgAECn9DAAIPAAkJfyR2AgBDAwAPAAkJfyR2AgBDAwAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAABLgAFFH8QAAIBAAQJlxzGGQBEAQABAAQJlxzGGQBEAQABLgAFFAkJSQAQANMjAA==.Tristitia:BAABLgAECn8uAAMDAAkJ+BZCMAA7AgADAAkJ+BZCMAA7AgAIAAEJ+gOIZQAcAAAAAA==.Trolidan:BAAALgAECgEJAQAAAA==.',
Tu='Tubbs:BAABLgAECn8ZAAIDAAkJAxxqLABMAgADAAkJAxxqLABMAgAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAQJCgALAF0ZAA==.',
Tw='Twiggle:BAAALgAECgQJBAABLgAECggJFgAfAMASAA==.',
Ty='Tyche:BAABLgAECn8XAAMCAAYJcw22ZAAoAQACAAYJcw22ZAAoAQABAAEJ2gHPvwAYAAAAAA==.Tyrdrin:BAAALgAECgEJAQAAAA==.Tysbich:BAAALgAECgQJBAABLgAECgkJLQAfAOMhAA==.',
Ui='Uiewedaoez:BAABLgAECn80AAIVAAkJWSTiAgCaAwAVAAkJWSTiAgCaAwAAAA==.',
Um='Umakkel:BAAALgAECgYJDgAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ9BBCWAC6AQADAAkJ9BBCWAC6AQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMdAAYJJhD1HgBZAQAdAAYJJhD1HgBZAQAQAAIJ4gHuLwEhAAAAAA==.Vaelrieth:BAABLgAECn8YAAIZAAcJIwcaywD2AAAZAAcJIwcaywD2AAAAAA==.Vains:BAACLgAFFH8RAAIZAAUJkRwlNwA5AQAZAAUJkRwlNwA5AQAuAAQKfyIAAhkACQkzIRUmAGoCABkACQkzIRUmAGoCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Vardis:BAABLgAECn8uAAILAAkJMh/jKQBwAgALAAkJMh/jKQBwAgAAAA==.',
Ve='Velinami:BAAALgAECgIJAgAAAA==.Venato:BAAALgADCgEJBAABLgAECgkJNgACAH0OAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verazene:BAABLgAFFH8FAAIYAAMJsheFBwD/AAAYAAMJsheFBwD/AAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn84AAILAAkJ6h5zFQDWAgALAAkJ6h5zFQDWAgAAAA==.Verren:BAABLgAECn8rAAIWAAkJFBqmCQBLAgAWAAkJFBqmCQBLAgAAAA==.Versutia:BAAALgAECgIJAgAAAA==.',
Vi='Virse:BAAALgAECgUJCQAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.Vixie:BAAALgAECgcJBwAAAA==.',
Vy='Vye:BAAALgAECgEJAQAAAA==.Vyerith:BAABLgAECn8kAAIQAAkJjhyQJwA8AgAQAAkJjhyQJwA8AgAAAA==.',
We='Weltamus:BAABLgAECn8nAAMIAAkJABjxGwB5AQADAAgJyg+BcgB8AQAIAAQJ9yDxGwB5AQAAAA==.Weltasaur:BAABLgAECn8bAAIWAAYJBhgGHgBXAQAWAAYJBhgGHgBXAQAAAA==.Weltazar:BAABLgAECn80AAIBAAkJrxd9IwDGAQABAAkJrxd9IwDGAQAAAA==.Westside:BAACLgAFFH8fAAMLAAgJhx71BAAbAgALAAgJhx71BAAbAgANAAEJqAlVBwA5AAAuAAQKfyMAAgsACQnVJkoBAIwDAAsACQnVJkoBAIwDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJIAAQAGsjAA==.Wildtiger:BAABLgAECn8zAAIoAAkJ5hgBCABOAgAoAAkJ5hgBCABOAgAAAA==.',
Wo='Wolfslied:BAAALgAECgYJCAAAAA==.',
Wr='Wrecken:BAAALgADCgUJBQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8zAAQcAAkJ8B5fAgC1AgAcAAkJ8B5fAgC1AgAEAAMJoAfkUACkAAAiAAEJeAVgDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAwABLgAECgkJNgACAH0OAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgMJBQAFAAAAAA==.Xalreth:BAABLgAECn8gAAISAAkJPg5GWwByAQASAAkJPg5GWwByAQAAAA==.Xaviana:BAAALgAECgkJKgAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMPAAkJOQgFOQAtAQAPAAgJOAcFOQAtAQAMAAMJXwWBcQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8eAAISAAkJ0BgPLwBAAgASAAkJ0BgPLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8xAAIfAAkJJiaeBwAQAwAfAAkJJiaeBwAQAwAAAA==.Yushi:BAABLgAECn8tAAIEAAkJlx+wCgB2AgAEAAkJlx+wCgB2AgAAAA==.',
Yv='Yväinne:BAAALgAECgIJAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJEgAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAABLgAECn8mAAQDAAkJURT5NQAkAgADAAkJURT5NQAkAgAmAAYJKQVbKACKAAAIAAQJYQPtSQBjAAAAAA==.Zenweaver:BAACLgAFFH8RAAIXAAMJVSSZHQA3AQAXAAMJVSSZHQA3AQAuAAQKfx8AAhcACQlqIlUEAEcDABcACQlqIlUEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgAECgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8hAAIDAAkJRiFEEwDTAgADAAkJRiFEEwDTAgAAAA==.',
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
