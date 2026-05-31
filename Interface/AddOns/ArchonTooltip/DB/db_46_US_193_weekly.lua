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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Druid-Restoration','Hunter-Survival','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection','Druid-Feral','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgADCgYJBgAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMEAAkJkhOgJwBzAQAEAAkJkhOgJwBzAQAFAAcJcgvmOAANAQAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIGAAkJgxUDEwDFAQAGAAkJgxUDEwDFAQAAAA==.Ahroo:BAAALgAECgkJGwAAAQ==.Ahrue:BAAALgAECgkJDQABLgAECgkJGwAHAAAAAQ==.',
Ai='Airc:BAAALgAECgYJEgAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIIAAkJNQc5ZgBnAQAIAAkJNQc5ZgBnAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alvar:BAABLgAECn8ZAAIIAAgJ/hLUVwCKAQAIAAgJ/hLUVwCKAQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAUJCAAJAN0XAA==.',
Ar='Arcadium:BAACLgAFFH8IAAIKAAMJ5hrLZAD/AAAKAAMJ5hrLZAD/AAAuAAQKfxUAAgoABQlYIpZvAPUBAAoABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgYJBgAAAA==.Arêos:BAABLgAECn8eAAIEAAkJYx1HDQB5AgAEAAkJYx1HDQB5AgAAAA==.',
As='Asunaish:BAABLgAECn8ZAAMLAAgJThv5QgDnAQALAAgJThv5QgDnAQAMAAEJPBU4LQA/AAABLgAFFAEJAQAHAAAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8bAAMNAAgJiB8oAgBSAgANAAgJMh8oAgBSAgAOAAEJrCPKeQBpAAAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJDQAAAA==.',
Az='Azarite:BAABLgAECn87AAIJAAkJ0hHdVgCuAQAJAAkJ0hHdVgCuAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJDQAAAA==.Badassbum:BAABLgAECn8WAAIPAAYJdAUoPACjAAAPAAYJdAUoPACjAAAAAA==.Bahoodies:BAAALgAECggJBwAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8hAAIJAAkJshlmMAAmAgAJAAkJshlmMAAmAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8jAAIQAAgJtB7/AgBGAgAQAAgJtB7/AgBGAgAuAAQKfywAAhAACQkvJfQDAFADABAACQkvJfQDAFADAAAA.Bignut:BAAALgAECgcJBgAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAECgcJKgAQABQaAA==.Bortikus:BAAALgAECgQJBwABLgAECgcJKgAQABQaAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAOABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burney:BAABLgAECn82AAMRAAkJ1yB/AgA1AwARAAkJ1yB/AgA1AwASAAIJcAv2GgBkAAAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8MAAITAAQJ9x9jCQBxAQATAAQJ9x9jCQBxAQAuAAQKfy0AAhMACQl0IqoEAMQCABMACQl0IqoEAMQCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8OAAIUAAUJUhZcEwB2AQAUAAUJUhZcEwB2AQAuAAQKfx8AAhQACAlsFL4mAPQBABQACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAIBAAkJahGhHQDRAQABAAkJahGhHQDRAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8aAAMVAAcJKhBlOQBaAQAVAAcJKhBlOQBaAQAWAAYJJRMfMgAmAQAAAA==.Chaosmage:BAAALgAECgUJCgAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMSAAcJqhQNFAClAQASAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8PAAIIAAcJ3QrJGwCmAQAIAAcJ3QrJGwCmAQAuAAQKfygAAwgACAlFGvYoAG0CAAgACAkIGvYoAG0CABcABwlbFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAEJAQAHAAAAAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAILAAgJ3h/DNABkAgALAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIYAAkJPh8nDQCAAgAYAAkJPh8nDQCAAgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAAALgAECgYJEQAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAECgYJCQAAAA==.',
Do='Donyolerberz:BAAALgAECgcJBgAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIOAAgJEBSSawBTAQAOAAgJEBSSawBTAQAAAA==.Dragonflyy:BAAALgAECgQJCgAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAQAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8IAAIZAAYJyxdSCwDjAQAZAAYJyxdSCwDjAQAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIUAAcJUhs+JQD8AQAUAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn88AAIJAAkJ4hfpLAA0AgAJAAkJ4hfpLAA0AgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgASAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAcJFgAOAL0aAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8JAAMQAAIJ1CQzMQDNAAAQAAIJ1CQzMQDNAAAWAAEJswl0NwA+AAAuAAQKfxkAAxAABwkvJDYYAEMCABAABwkvJDYYAEMCABYABQkQE5ZPALEAAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIaAAkJdQzMWABkAQAaAAkJdQzMWABkAQAAAA==.Erona:BAABLgAECn8aAAIZAAkJ1B9JBQBKAwAZAAkJ1B9JBQBKAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8WAAILAAUJhR8ENwBlAQALAAUJhR8ENwBlAQAuAAQKfygAAgsACAkeJDQYAKECAAsACAkeJDQYAKECAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAFFAEJAQAAAA==.Fartcloud:BAAALgAECgYJBgAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAABLgAECn8bAAIZAAgJ9Bt+EwCXAgAZAAgJ9Bt+EwCXAgABLgAFFAUJCAAJAN0XAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn8sAAIbAAgJGQyQEAApAQAbAAgJGQyQEAApAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8MAAIKAAQJPAagYAANAQAKAAQJPAagYAANAQAuAAQKfyQAAgoACQkXDn5dAK4BAAoACQkXDn5dAK4BAAAA.Flo:BAAALgADCgUJBgABLgAECggJBwAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8mAAIKAAgJTRYoBAAvAgAKAAgJTRYoBAAvAgAuAAQKfxcAAgoACAlhHSRGAGUCAAoACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAgJJgAKAE0WAA==.Footloose:BAAALgAECggJDwAAAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgQJDgAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBAABLgAECgkJHQAaAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAcAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJAwAHAAAAAA==.Genosaur:BAAALgAECgEJAwAAAA==.Gethsemane:BAAALgAECgEJAQAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAILAAkJpRcJOAAMAgALAAkJpRcJOAAMAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8lAAIEAAgJvxjgEwAiAgAEAAgJvxjgEwAiAgAAAA==.Gimermonty:BAACLgAFFH8MAAIOAAQJxRAeQgAFAQAOAAQJxRAeQgAFAQAuAAQKfysAAg4ACQmXHeUXAIACAA4ACQmXHeUXAIACAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAAALgADCgUJDQAAAA==.Glorfindel:BAAALgAECggJDwAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIIAAgJTQqidABFAQAIAAgJTQqidABFAQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMXAAgJlRpCDgDjAQAXAAYJJxxCDgDjAQAIAAcJqBaGTQCnAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8GAAIdAAIJ6Q7JIABtAAAdAAIJ6Q7JIABtAAAuAAQKfzIAAh0ACAn+Gk0MAPwBAB0ACAn+Gk0MAPwBAAAA.Halvor:BAAALgAECgQJCAAAAA==.Hangbladz:BAABLgAECn8VAAMaAAgJ4xrtTwB+AQAaAAgJ4xrtTwB+AQAbAAEJyw5qMAAsAAAAAA==.Hanita:BAAALgAECgMJAwAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgcJEwAHAAAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIbAAkJiCNlAQAJAwAbAAkJiCNlAQAJAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQALAKsbAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8TAAMYAAQJ9Q95IAACAQAYAAQJ9Q95IAACAQAZAAMJTQrySACuAAAuAAQKfyMAAxkACQkPF3MiABACABkACAmjFXMiABACABgABgmtFjUzAFQBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJAwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAQJBQAJAEMPAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAAALgAECgUJBwAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIaAAcJaRunRwCYAQAaAAcJaRunRwCYAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIeAAgJvw5PPgCHAQAeAAgJvw5PPgCHAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAJAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAABLgAECn8hAAMOAAcJ7RLmXQBzAQAOAAcJ7RLmXQBzAQANAAUJIg3eHACzAAAAAA==.',
Kl='Klickyy:BAAALgAECgQJBQABLgAFFAUJCAAJAN0XAA==.Kllcky:BAACLgAFFH8IAAIJAAUJ3ReFDgC1AQAJAAUJ3ReFDgC1AQAuAAQKfygAAgkACAmSI6YNAOICAAkACAmSI6YNAOICAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJBQAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8pAAMfAAcJ7iHxCwATAgAfAAYJjSLxCwATAgAOAAMJsR4+nwDlAAAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuwabara:BAAALgADCgUJBQAAAA==.',
Kv='Kvothè:BAAALgAECgcJDwAAAA==.',
Ky='Kyi:BAACLgAFFH8MAAIWAAQJihC7EwAPAQAWAAQJihC7EwAPAQAuAAQKfyAAAhYACQkfEwEfAJ8BABYACQkfEwEfAJ8BAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAKAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammlock:BAAALgAECgIJAgAAAA==.Landar:BAABLgAECn9KAAIeAAkJNxk6EwCgAgAeAAkJNxk6EwCgAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8GAAILAAIJgxVXrQCVAAALAAIJgxVXrQCVAAABLgAFFAgJKwAYAEwhAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn8yAAMfAAkJ0xF6DwAoAgAfAAkJ0xF6DwAoAgANAAEJAAAXQgAAAAAAAA==.Lireesa:BAABLgAECn8jAAIXAAgJmBC1DABWAQAXAAgJmBC1DABWAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAeADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Lunn:BAABLgAECn8YAAINAAcJug91FQD4AAANAAcJug91FQD4AAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAIJAAcJjBV3egBeAQAJAAcJjBV3egBeAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAJAA4UAA==.Mangreese:BAABLgAECn8tAAIgAAkJqRY9CAApAgAgAAkJqRY9CAApAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMcAAgJQg3rMwAjAQAcAAcJywvrMwAjAQAEAAYJgAlaRwAcAQAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAgAAAA==.Mithrandir:BAAALgAECgYJBgAAAA==.Mixmasterg:BAABLgAECn8hAAIaAAkJagyvUwBzAQAaAAkJagyvUwBzAQAAAA==.',
Mo='Mograinez:BAACLgAFFH8fAAILAAgJVSVyAACEAgALAAgJVSVyAACEAgAuAAQKfxUAAgsACAl9JqUcANMCAAsACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAECgQJBAABLgAFFAUJBwAcAGoHAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgEJAQAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIPAAYJIhI+MgBDAQAPAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIIAAkJoxRLOgDkAQAIAAkJoxRLOgDkAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAABLgAFFH8IAAMNAAQJHBYVFgDcAAANAAMJ3BQVFgDcAAAOAAIJxBB3bACUAAAAAA==.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAAALgAFFAMJAwAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8OAAMhAAMJWhtZAwBfAAAIAAIJrxk1gwCeAAAhAAEJrx5ZAwBfAAAuAAQKfzkABAgACQnfIH8hAE8CAAgABwnwIH8hAE8CABcABAkoF3IuAAIBACEAAwnQIDAWANEAAAEuAAUUBQkIAAkA3RcA.',
Ol='Oldshotz:BAAALgAECgcJEgAAAA==.',
Om='Omgsteak:BAABLgAECn8XAAMTAAYJ8gGiPABmAAATAAYJIgGiPABmAAACAAMJZwIoYQBBAAAAAA==.',
On='Onapalehorse:BAAALgADCgcJEwAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAJAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8lAAITAAUJUSZ/BQDCAQATAAUJUSZ/BQDCAQAuAAQKf34ABBMACQm8Jh8AAI8DABMACQm8Jh8AAI8DAAIACQmJItkBACoDAAMACQnpIcEDAB0DAAAA.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAgAAAA==.Prayforme:BAABLgAECn8qAAMcAAkJuR4EBQAkAwAcAAkJuR4EBQAkAwAFAAQJ4BMXQwDdAAAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAAALgADCgEJAQAAAA==.Prise:BAACLgAFFH8IAAMIAAQJIQ4CZgDeAAAIAAMJmBICZgDeAAAXAAEJvQDeJgAoAAAuAAQKfxgAAxcACQlDDgQbAHUBABcABwm+EAQbAHUBAAgACAm8C8OiAO8AAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMZAAkJdQmpSQBbAQAZAAkJdQmpSQBbAQAYAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAECgYJDwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8GAAIBAAIJWwcNSwB1AAABAAIJWwcNSwB1AAAuAAQKfx8AAwEACQlFGHgaAOkBAAEACQlFGHgaAOkBABIAAwn+BPUyAH4AAAAA.Ralthas:BAAALgAECgUJDwABLgAECggJLQARAEsVAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0w83TwBqAQATAAYJOxQ6JgDmAAAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgIJAgAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8jAAMJAAgJRAumuwDxAAAJAAUJ2Q2muwDxAAAiAAcJPgb8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8fAAILAAgJ7x2iKQBHAgALAAgJ7x2iKQBHAgAAAA==.Riftstalker:BAABLgAECn8XAAMfAAcJCBdwEAC9AQAfAAcJCBdwEAC9AQAOAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgEJAQAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIIAAMJ/BC0aADZAAAIAAMJ/BC0aADZAAAuAAQKfycAAwgACQmmHgEpACkCAAgACQmmHgEpACkCABcAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.',
Ru='Rushem:BAABLgAECn8WAAIDAAkJMRQuIADaAQADAAkJMRQuIADaAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAILAAgJzxYbegCQAQALAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8XAAIjAAgJxAvxGQAZAQAjAAgJxAvxGQAZAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgASAAEJ+RJXPAA8AAARAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwAAAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8oAAMMAAgJzwWnDgC5AAAMAAQJwwinDgC5AAALAAgJaQNS4QC3AAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgYJEQAHAAAAAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8lAAIcAAYJeyMlDwBeAgAcAAYJeyMlDwBeAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8LAAMUAAQJZQwFIwDyAAAUAAQJZQwFIwDyAAAiAAIJIATTEQBRAAAuAAQKfywAAyIACQmQFboSAJ8BACIACAnpE7oSAJ8BABQABQliFYRBACUBAAAA.Sevinofnine:BAAALgAECgQJBgAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8bAAIkAAkJPBblFQAKAgAkAAkJPBblFQAKAgAAAA==.Shi:BAAALgAECgEJAQAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIfAAgJaA1bEgCdAQAfAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAECgcJDgAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAAALgAFFAIJAgAAAA==.Snipyterror:BAAALgADCgEJAQAAAA==.Snoodly:BAABLgAECn8YAAIVAAkJvw+CJwC+AQAVAAkJvw+CJwC+AQAAAA==.Snuu:BAAALgADCgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8IAAIKAAQJRxiSOwBYAQAKAAQJRxiSOwBYAQAuAAQKfyAAAwoACQlXHsUZAKkCAAoACQkkHsUZAKkCACUAAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIIAAkJvQv8UwCUAQAIAAkJvQv8UwCUAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8HAAIaAAMJSQNGYwChAAAaAAMJSQNGYwChAAAuAAQKfxYAAhoACQkNEyZLAMgBABoACQkNEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAITAAQJzguGGgCpAAATAAQJzguGGgCpAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQATAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8lAAILAAkJqxvAJgBUAgALAAkJqxvAJgBUAgAAAA==.Stinksauce:BAACLgAFFH8SAAIRAAQJNR8ZEQBgAQARAAQJNR8ZEQBgAQAuAAQKfxoABBEACQkHGm4NAGACABEACQkHGm4NAGACAAEAAQl0BtRhADUAABIAAQmvB4A/ADIAAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.',
Su='Supabox:BAAALgAECgcJEgABLgAFFAYJFgAQAHojAA==.Superchunk:BAAALgAECgIJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIEAAkJLw1JIwCTAQAEAAkJLw1JIwCTAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8wAAMUAAgJsBphGgAbAgAUAAgJsBphGgAbAgAJAAEJAAA/qgEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIQAAcJkRmDHgCgAQAQAAcJkRmDHgCgAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAISAAkJrh04AgCVAgASAAkJrh04AgCVAgAAAA==.Tankytauren:BAABLgAECn8uAAMMAAkJrRa/BQAqAgAMAAkJrRa/BQAqAgALAAgJFRJ4ZACLAQAAAA==.Tarquinius:BAABLgAECn8tAAIPAAkJUA8iGwCDAQAPAAkJUA8iGwCDAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJPgADAJclAA==.Taylorswifft:BAAALgAECgcJDgAAAA==.',
Te='Telanastre:BAAALgAECgQJBwABLgAECgYJBgAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAQJDAAWAIoQAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAYAAoTAA==.',
Ti='Tifferny:BAABLgAECn8UAAIJAAcJexACigBBAQAJAAcJexACigBBAQAAAA==.Tiffèrny:BAAALgAECgYJDwAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMkAAgJIBRaLQCZAQAkAAcJkxNaLQCZAQAeAAgJ+Q++SgBRAQAAAA==.Tonkatruck:BAAALgAECgcJBgAAAA==.Totemlycool:BAABLgAECn8hAAQYAAgJGxWwIAAKAgAYAAgJCRSwIAAKAgAgAAYJlRcEEgCWAQAZAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAAALgAECggJDQABLgAECgkJRgAeAAwcAA==.Treehuggër:BAABLgAECn8YAAIeAAkJgBdHFwB5AgAeAAkJgBdHFwB5AgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAXAJUaAA==.Tryrah:BAABLgAFFH8VAAIkAAcJbBbRCADHAQAkAAcJbBbRCADHAQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8HAAIaAAQJxwXwSwDoAAAaAAQJxwXwSwDoAAAuAAQKfyIAAhoACQliEmlNAIYBABoACQliEmlNAIYBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAABLgAECn8XAAMDAAgJsxhHPgCrAQADAAcJ4hhHPgCrAQACAAQJoRVyMwDdAAAAAA==.',
['Tö']='Töömis:BAABLgAECn8ZAAIJAAcJkxOFfACBAQAJAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIDAAIJeRJFOACXAAADAAIJeRJFOACXAAAuAAQKfzkAAgMACQkHIPoKAKICAAMACQkHIPoKAKICAAAA.',
Ur='Urza:BAAALgADCgYJHwAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAIjAAkJEQ6/DwCXAQAjAAkJEQ6/DwCXAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8ZAAIJAAgJ5QhrwADqAAAJAAgJ5QhrwADqAAAAAA==.',
Vo='Volsunga:BAAALgAECgQJDgAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgADCggJCQAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8rAAIIAAgJTBniLAAZAgAIAAgJTBniLAAZAgAAAA==.',
Xy='Xylazel:BAABLgAECn8wAAILAAkJ2RpGIgBqAgALAAkJ2RpGIgBqAgAAAA==.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8iAAMUAAYJJBwbIgDdAQAUAAYJJBwbIgDdAQAJAAMJjxbB0wDPAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.Zugszy:BAAALgADCgkJCQAAAA==.Zultal:BAAALgAECgQJBQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8kAAIkAAgJAyIgAQDDAgAkAAgJAyIgAQDDAgAuAAQKfx8AAiQACAnEJZcNAMECACQACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAgJJAAkAAMiAA==.Zzephyrfury:BAAALgAECgEJAQAAAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAgJJAAkAAMiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIeAAgJORxPGgBgAgAeAAgJORxPGgBgAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECggJLQAeAD4SAA==.',
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
