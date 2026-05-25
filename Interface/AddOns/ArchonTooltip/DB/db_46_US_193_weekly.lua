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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Brewmaster','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Druid-Restoration','Hunter-Survival','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection','Druid-Feral','DeathKnight-Frost','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgADCgYJBgAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMEAAkJkhMVJQB4AQAEAAkJkhMVJQB4AQAFAAcJcgsmMgAqAQAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIGAAkJgxUfEQDKAQAGAAkJgxUfEQDKAQAAAA==.Ahroo:BAAALgAECgkJGgAAAQ==.Ahrue:BAAALgAECgkJDQABLgAECgkJGgAHAAAAAQ==.',
Ai='Airc:BAAALgAECgYJEgAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIIAAkJNQcmXwBsAQAIAAkJNQcmXwBsAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alvar:BAABLgAECn8ZAAIIAAgJ/hLMUACSAQAIAAgJ/hLMUACSAQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAQJBQAJAKoOAA==.',
Ar='Arcadium:BAACLgAFFH8HAAIKAAMJ5hrsWgAHAQAKAAMJ5hrsWgAHAQAuAAQKfxUAAgoABQlYIpZvAPUBAAoABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arêos:BAABLgAECn8eAAIEAAkJYx2uCwCDAgAEAAkJYx2uCwCDAgAAAA==.',
As='Asunaish:BAABLgAECn8YAAILAAgJThtMPQDqAQALAAgJThtMPQDqAQAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8aAAIMAAgJMh8sAQB2AgAMAAgJMh8sAQB2AgAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJCQAAAA==.',
Az='Azarite:BAABLgAECn87AAIJAAkJ0hFySADOAQAJAAkJ0hFySADOAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJDQAAAA==.Badassbum:BAABLgAECn8WAAINAAYJdAXZNgCnAAANAAYJdAXZNgCnAAAAAA==.Bahoodies:BAAALgAECgcJBgAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8gAAIJAAkJRxkFKwAzAgAJAAkJRxkFKwAzAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8iAAIOAAcJUR+SBAD6AQAOAAcJUR+SBAD6AQAuAAQKfywAAg4ACQkvJfQDAFADAA4ACQkvJfQDAFADAAAA.Bignut:BAAALgAECgcJBgAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAEJAQAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAEJAQAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAPABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burney:BAABLgAECn8yAAMQAAkJ1yAmAgA6AwAQAAkJ1yAmAgA6AwARAAIJcAtGGQBkAAAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8IAAISAAMJ4iAHDgAbAQASAAMJ4iAHDgAbAQAuAAQKfy0AAhIACQl0ItoDANICABIACQl0ItoDANICAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8MAAITAAQJExI8HQAGAQATAAQJExI8HQAGAQAuAAQKfx8AAhMACAlsFL4mAPQBABMACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAIBAAkJahFmGwDaAQABAAkJahFmGwDaAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8XAAMUAAYJ+hBTOwArAQAUAAYJ+hBTOwArAQAVAAYJJRMgLgAnAQAAAA==.Chaosmage:BAAALgAECgQJBAAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMRAAcJqhQNFAClAQARAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJBQAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8NAAIIAAYJ6QumJwBiAQAIAAYJ6QumJwBiAQAuAAQKfygAAwgACAlFGvYoAG0CAAgACAkIGvYoAG0CABYABwlbFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAECggJGAALAE4bAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAILAAgJ3h/DNABkAgALAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIXAAkJPh+gCwCEAgAXAAkJPh+gCwCEAgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAAALgAECgYJCgAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECgcJEgAAAA==.Dipz:BAAALgAECgYJCQAAAA==.',
Do='Donyolerberz:BAAALgAECgcJBgAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIPAAgJEBR+YgBTAQAPAAgJEBR+YgBTAQAAAA==.Dragonflyy:BAAALgAECgMJBAAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAQAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8HAAIYAAUJ5RY2EACbAQAYAAUJ5RY2EACbAQAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8aAAITAAcJUhs+JQD8AQATAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn87AAIJAAkJPBecKgA1AgAJAAkJPBecKgA1AgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgARAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAcJFgAPAL0aAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8JAAMOAAIJ1CSjLQDSAAAOAAIJ1CSjLQDSAAAVAAEJswk8MABCAAAuAAQKfxgAAw4ABwkvJDYYAEMCAA4ABwkvJDYYAEMCABUABAnOEBdSAMoAAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIZAAkJdQxBTwB1AQAZAAkJdQxBTwB1AQAAAA==.Erona:BAAALgAECggJDAAAAA==.',
Es='Escorpiøn:BAACLgAFFH8SAAILAAQJhR9iLQBsAQALAAQJhR9iLQBsAQAuAAQKfygAAgsACAkeJFgVAKYCAAsACAkeJFgVAKYCAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAECgcJEwABLgAECggJGAALAE4bAA==.Fartcloud:BAAALgAECgUJBQAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAAALgAFFAIJAgABLgAFFAQJBQAJAKoOAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn8rAAIaAAgJGQw1DwAuAQAaAAgJGQw1DwAuAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgADCgkJEgAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8HAAIKAAIJuwZzjQCLAAAKAAIJuwZzjQCLAAAuAAQKfyQAAgoACQkXDvhSAMcBAAoACQkXDvhSAMcBAAAA.Flo:BAAALgADCgUJBgABLgAECgcJBgAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8hAAIKAAgJHRYoBAAvAgAKAAgJHRYoBAAvAgAuAAQKfxcAAgoACAlhHSRGAGUCAAoACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAgJIQAKAB0WAA==.Footloose:BAAALgAECgYJBwAAAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgQJDgAAAA==.',
Ga='Gadzookah:BAAALgAECgMJAwABLgAECgkJHQAZAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAbAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgAAAA==.Genosaur:BAAALgAECgEJAgABLgAECgEJAgAHAAAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8rAAILAAkJpRd9NQAFAgALAAkJpRd9NQAFAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8iAAIEAAgJQRjGEwAUAgAEAAgJQRjGEwAUAgAAAA==.Gimermonty:BAACLgAFFH8IAAIPAAMJ8xNmQQDoAAAPAAMJ8xNmQQDoAAAuAAQKfysAAg8ACQmXHScUAIgCAA8ACQmXHScUAIgCAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAAALgADCgUJCQAAAA==.Glorfindel:BAAALgAECggJDgAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIIAAgJTQqvbABLAQAIAAgJTQqvbABLAQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMWAAgJlRpCDgDjAQAWAAYJJxxCDgDjAQAIAAcJqBauRwCtAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAABLgAECn8sAAIcAAgJJRqYCwDvAQAcAAgJJRqYCwDvAQAAAA==.Halvor:BAAALgAECgQJCAAAAA==.Hangbladz:BAABLgAECn8UAAMZAAcJsRoVUQCzAQAZAAcJsRoVUQCzAQAaAAEJyw6kKwAwAAAAAA==.Hanita:BAAALgAECgMJAwAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgADCgYJBgABLgAECgcJEwAHAAAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIaAAkJiCMZAQARAwAaAAkJiCMZAQARAwAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAQAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQALAKsbAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8QAAMXAAQJ9Q+LGwAUAQAXAAQJ9Q+LGwAUAQAYAAMJfgkLQACyAAAuAAQKfyMAAxgACQkPF3MiABACABgACAmjFXMiABACABcABgmtFlAvAFYBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJAwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAQJBQAJAEMPAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedrelyn:BAAALgAECgEJAgAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIZAAcJaRsAQwCdAQAZAAcJaRsAQwCdAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIdAAgJvw7cOgCHAQAdAAgJvw7cOgCHAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAJAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAABLgAECn8eAAMPAAcJXxIzWABtAQAPAAcJXxIzWABtAQAMAAUJIg30GgC1AAAAAA==.',
Kl='Klickyy:BAAALgAECgIJAgABLgAFFAQJBQAJAKoOAA==.Kllcky:BAACLgAFFH8FAAIJAAQJqg7lMwAmAQAJAAQJqg7lMwAmAQAuAAQKfyQAAgkACAlZI8MMAOQCAAkACAlZI8MMAOQCAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJBQAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8oAAMeAAcJ7iHxCwATAgAeAAYJjCLxCwATAgAPAAMJsR45kgDnAAAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuwabara:BAAALgADCgUJBQAAAA==.',
Kv='Kvothè:BAAALgAECgcJDwAAAA==.',
Ky='Kyi:BAACLgAFFH8IAAIVAAMJrwqXHADAAAAVAAMJrwqXHADAAAAuAAQKfyAAAhUACQkfE9wbAKYBABUACQkfE9wbAKYBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAKAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammlock:BAAALgAECgIJAgAAAA==.Landar:BAABLgAECn9FAAIdAAkJ/RhPEgCaAgAdAAkJ/RhPEgCaAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAAALgAFFAIJAwABLgAFFAcJJwAXAAIjAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn8xAAMeAAkJMRErEAAVAgAeAAkJMRErEAAVAgAMAAEJAAAfPgAAAAAAAA==.Lireesa:BAABLgAECn8jAAIWAAgJmBBiCwBcAQAWAAgJmBBiCwBcAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAdADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Lunn:BAABLgAECn8YAAIMAAcJug8WFAD6AAAMAAcJug8WFAD6AAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAIJAAcJjBXgcABsAQAJAAcJjBXgcABsAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAJAA4UAA==.Mangreese:BAABLgAECn8mAAIfAAkJHRaoBwAgAgAfAAkJHRaoBwAgAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJDwAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8YAAMEAAcJOQtaRwAcAQAEAAYJgAlaRwAcAQAbAAYJLQnYOwDpAAAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgADCgcJBwAAAA==.Mixmasterg:BAABLgAECn8hAAIZAAkJagyPTQB6AQAZAAkJagyPTQB6AQAAAA==.',
Mo='Mograinez:BAACLgAFFH8fAAILAAgJVSVyAACEAgALAAgJVSVyAACEAgAuAAQKfxUAAgsACAl9JqUcANMCAAsACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAECgQJBAABLgAFFAUJBgAbAGoHAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
My='Mythunrus:BAABLgAECn8YAAINAAYJIhI+MgBDAQANAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIIAAkJoxTMNQDpAQAIAAkJoxTMNQDpAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAABLgAFFH8GAAMMAAIJPRbBGQCbAAAMAAIJPRbBGQCbAAAPAAEJrQeCeQBEAAAAAA==.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAAALgAFFAEJAQAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8LAAMgAAMJWhtZAwBfAAAIAAIJrxngdQCiAAAgAAEJrx5ZAwBfAAAuAAQKfzIABAgACQkAIAcmACwCAAgABwnyHwcmACwCABYABAkoF3IuAAIBACAAAwnQIDAWANEAAAEuAAUUBAkFAAkAqg4A.',
Ol='Oldshotz:BAAALgAECgcJEgAAAA==.',
Om='Omgsteak:BAAALgAECgYJEgAAAA==.',
On='Onapalehorse:BAAALgADCgcJEAAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJAwAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAJAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8gAAISAAUJNSZKBADFAQASAAUJNSZKBADFAQAuAAQKf1kAAxIACQllJmQAANADABIACQllJmQAANADAAMABQmGB2pvAPoAAAAA.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAgAAAA==.Prayforme:BAABLgAECn8iAAMbAAgJCx0YCwCTAgAbAAgJCx0YCwCTAgAFAAQJ4BP8PQDvAAAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prise:BAACLgAFFH8FAAMIAAMJVA/weQCcAAAIAAIJoBbweQCcAAAWAAEJvQDiIgAoAAAuAAQKfxYAAxYABwk5EQQbAHUBABYABwm+EAQbAHUBAAgABglHDgrCAKsAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMYAAkJdQmpSQBbAQAYAAkJdQmpSQBbAQAXAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAECgYJDwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8GAAIBAAIJWwc9QwB8AAABAAIJWwc9QwB8AAAuAAQKfx8AAwEACQlFGF4YAPMBAAEACQlFGF4YAPMBABEAAwn+BPUyAH4AAAAA.Ralthas:BAAALgAECgUJDAAAAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0w83TwBqAQASAAYJOxRDIwDtAAAAAA==.Ravenoth:BAAALgAECgEJAQAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgEJAQAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8jAAMJAAgJRAtbpAAPAQAJAAUJ2Q1bpAAPAQAhAAcJPgb8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8fAAILAAgJ7x2NJQBLAgALAAgJ7x2NJQBLAgAAAA==.Riftstalker:BAABLgAECn8XAAMeAAcJCBdwEAC9AQAeAAcJCBdwEAC9AQAPAAEJ+w0f0QA1AAAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIIAAMJ/BBnXgDbAAAIAAMJ/BBnXgDbAAAuAAQKfyYAAwgACQmmHlklAC8CAAgACQmmHlklAC8CABYAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.',
Ru='Rushem:BAABLgAECn8WAAIDAAkJMRRVHADmAQADAAkJMRRVHADmAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAILAAgJzxYbegCQAQALAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8WAAIiAAcJuAuqGwDzAAAiAAcJuAuqGwDzAAAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgARAAEJ+RJXPAA8AAAQAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAQJCgAbAJAVAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8oAAMjAAgJzwWnDgC5AAAjAAQJwwinDgC5AAALAAgJaQPO0QC3AAAAAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8hAAIbAAYJeyOSDQBpAgAbAAYJeyOSDQBpAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8IAAMTAAMJKg9kJwC8AAATAAMJKg9kJwC8AAAhAAIJIASkDwBSAAAuAAQKfywAAyEACQmQFeMSAG0BACEACAnpE+MSAG0BABMABQliFTc9ACkBAAAA.Sevinofnine:BAAALgAECgMJBQAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8bAAIkAAkJPBbkEwAMAgAkAAkJPBbkEwAMAgAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.',
Sl='Slaveman:BAAALgAECgIJAgAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIeAAgJaA1bEgCdAQAeAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgADCgcJDQAAAA==.Smogy:BAAALgAECgcJCgAAAA==.',
Sn='Snacksized:BAAALgADCgcJBwAAAA==.Snipyterror:BAAALgADCgEJAQAAAA==.Snoodly:BAABLgAECn8YAAIUAAkJvw9hIwC9AQAUAAkJvw9hIwC9AQAAAA==.',
So='Solarice:BAABLgAECn8gAAMKAAkJVx7aFgC2AgAKAAkJJB7aFgC2AgAlAAEJ5iBkGQBMAAAAAA==.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIIAAkJvQtpTQCcAQAIAAkJvQtpTQCcAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8HAAIZAAMJSQMhWQCpAAAZAAMJSQMhWQCpAAAuAAQKfxYAAhkACQkNEyZLAMgBABkACQkNEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAISAAQJzgsxFwC3AAASAAQJzgsxFwC3AAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQASAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8lAAILAAkJqxsYIwBXAgALAAkJqxsYIwBXAgAAAA==.Stinksauce:BAACLgAFFH8OAAIQAAQJTR7HEABOAQAQAAQJTR7HEABOAQAuAAQKfxoABBAACQkHGm4NAGACABAACQkHGm4NAGACAAEAAQl0BtRhADUAABEAAQmvB4A/ADIAAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.',
Su='Supabox:BAAALgAECgcJEgABLgAFFAYJFgAOAHojAA==.Superchunk:BAAALgAECgIJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIEAAkJLw14IACbAQAEAAkJLw14IACbAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8rAAMTAAgJsBpYGAAeAgATAAgJsBpYGAAeAgAJAAEJAADwiwEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIOAAcJkRlFHACkAQAOAAcJkRlFHACkAQAAAA==.',
Ta='Talgulen:BAABLgAECn8yAAIRAAkJrh3UAQCjAgARAAkJrh3UAQCjAgAAAA==.Tankytauren:BAABLgAECn8uAAMjAAkJrRbmBAAyAgAjAAkJrRbmBAAyAgALAAgJFRKoXACOAQAAAA==.Tarquinius:BAABLgAECn8oAAINAAkJUA+QGACGAQANAAkJUA+QGACGAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJNQADAIglAA==.Taylorswifft:BAAALgAECgcJBwAAAA==.',
Te='Telanastre:BAAALgAECgQJBwAAAA==.',
Th='Tharos:BAAALgAECgUJBQAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAMJCAAVAK8KAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAXAAoTAA==.',
Ti='Tifferny:BAAALgAECgYJDQAAAA==.Tiffèrny:BAAALgAECgYJDgAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMkAAgJIBRaLQCZAQAkAAcJkxNaLQCZAQAdAAgJ+Q8HRwBQAQAAAA==.Tonkatruck:BAAALgAECgYJBQAAAA==.Totemlycool:BAABLgAECn8gAAQXAAgJGxWwIAAKAgAXAAgJCRSwIAAKAgAfAAYJlRcEEgCWAQAYAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAAALgAECggJDQABLgAECgkJQwAdAAwcAA==.Treehuggër:BAABLgAECn8XAAIdAAkJchd8FQB6AgAdAAkJchd8FQB6AgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAWAJUaAA==.Tryrah:BAABLgAFFH8VAAIkAAcJbBYIBgDiAQAkAAcJbBYIBgDiAQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAABLgAECn8iAAIZAAkJYhIASACMAQAZAAkJYhIASACMAQAAAA==.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAABLgAECn8XAAMDAAgJsxhHPgCrAQADAAcJ4hhHPgCrAQACAAQJoRUVLQDmAAAAAA==.',
['Tö']='Töömis:BAABLgAECn8ZAAIJAAcJkxOFfACBAQAJAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAABLgAECn82AAIDAAkJByBCCQCvAgADAAkJByBCCQCvAgAAAA==.',
Ur='Urza:BAAALgADCgYJGQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAIiAAkJEQ5pDQCrAQAiAAkJEQ5pDQCrAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8YAAIJAAcJXgjssQAgAQAJAAcJXgjssQAgAQAAAA==.',
Vo='Volsunga:BAAALgAECgQJDgAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgADCggJCQAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8mAAIIAAgJvBazOADeAQAIAAgJvBazOADeAQAAAA==.',
Xy='Xylazel:BAABLgAECn8tAAILAAkJ2RqbHgBuAgALAAkJ2RqbHgBuAgAAAA==.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8eAAMTAAYJJByXIADZAQATAAYJJByXIADZAQAJAAMJjxbYyADYAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8fAAIkAAgJAyKfAADVAgAkAAgJAyKfAADVAgAuAAQKfx4AAiQACAnEJZcNAMECACQACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAgJHwAkAAMiAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAgJHwAkAAMiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIdAAgJORxkGABgAgAdAAgJORxkGABgAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECggJKQAdAIMRAA==.',
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
