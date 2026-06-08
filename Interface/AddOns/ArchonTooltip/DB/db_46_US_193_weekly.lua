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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Havoc','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Rogue-Subtlety','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection','Druid-Feral','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgAECggJCAAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMEAAkJkhMaKQBwAQAEAAkJkhMaKQBwAQAFAAcJcgsVOgAiAQAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIGAAkJgxVzFADBAQAGAAkJgxVzFADBAQAAAA==.Ahroo:BAAALgAECgkJGwABLgAFFAQJBAAHAAAAAQ==.Ahrue:BAAALgAFFAQJBAAAAQ==.',
Ai='Airc:BAABLgAECn8VAAIIAAgJSgu/wwD3AAAIAAgJSgu/wwD3AAAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIJAAkJNQcFawBhAQAJAAkJNQcFawBhAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alpacalypse:BAAALgAECgcJCgAAAA==.Alvar:BAABLgAECn8ZAAIJAAgJ/hKkXACEAQAJAAgJ/hKkXACEAQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAUJDAAIAN0XAA==.',
Ar='Arcadium:BAACLgAFFH8IAAIKAAMJ5hpTbQD7AAAKAAMJ5hpTbQD7AAAuAAQKfxUAAgoABQlYIpZvAPUBAAoABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgcJCAAAAA==.Arêos:BAABLgAECn8eAAIEAAkJYx1iDgByAgAEAAkJYx1iDgByAgAAAA==.',
As='Asunaish:BAABLgAECn8ZAAMLAAgJThsyRwDlAQALAAgJThsyRwDlAQAMAAEJPBWXMgA+AAABLgAFFAEJAQAHAAAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8cAAQNAAgJiB9JAwBGAgANAAgJMh9JAwBGAgAOAAEJrCP2hgBmAAAPAAEJ7h7IKwBZAAAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJDQAAAA==.',
Az='Azarite:BAABLgAECn87AAIIAAkJ0hG2WQC1AQAIAAkJ0hG2WQC1AQAAAA==.',
Ba='Babybilly:BAAALgAECgYJEQAAAA==.Badassbum:BAABLgAECn8WAAIQAAYJdAWOQAChAAAQAAYJdAWOQAChAAAAAA==.Bahoodies:BAAALgAECggJBwAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Ballsofury:BAAALgAECgIJAgAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8hAAIIAAkJshlLNAAlAgAIAAkJshlLNAAlAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8mAAIRAAgJUB9MAgB7AgARAAgJUB9MAgB7AgAuAAQKfywAAhEACQkvJfQDAFADABEACQkvJfQDAFADAAAA.Bignut:BAAALgAECgcJBgAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAIJAwAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAOABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burlapt:BAAALgAECgEJAQAAAA==.Burney:BAABLgAECn82AAMSAAkJ1yCfAgA1AwASAAkJ1yCfAgA1AwATAAIJcAs0HABiAAAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8QAAIUAAQJ9x99CwBeAQAUAAQJ9x99CwBeAQAuAAQKfy8AAhQACQkFIzkEANoCABQACQkFIzkEANoCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8OAAIVAAUJUhZmFgBmAQAVAAUJUhZmFgBmAQAuAAQKfx8AAhUACAlsFL4mAPQBABUACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAIBAAkJahFWHwDVAQABAAkJahFWHwDVAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8cAAMWAAgJlxHSMACfAQAWAAgJlxHSMACfAQAXAAYJJRM4NQAiAQAAAA==.Chaosmage:BAABLgAECn8UAAIKAAYJ8xM2lQBIAQAKAAYJ8xM2lQBIAQAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickenblil:BAAALgAECgEJAQAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMTAAcJqhQNFAClAQATAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8UAAMJAAcJ6Q79HQC0AQAJAAcJ6Q79HQC0AQAYAAEJLwoyJABIAAAuAAQKfygAAwkACAlFGvYoAG0CAAkACAkIGvYoAG0CABgABwlbFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAEJAQAHAAAAAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAILAAgJ3h/DNABkAgALAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIZAAkJPh9dDgB7AgAZAAkJPh9dDgB7AgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAABLgAECn8aAAIaAAcJsA6hJQBZAQAaAAcJsA6hJQBZAQAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAECgYJCQAAAA==.',
Do='Donyolerberz:BAAALgAECgcJBgAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIOAAgJEBSDcQBRAQAOAAgJEBSDcQBRAQAAAA==.Dragonflyy:BAAALgAECgUJCwAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAgAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8MAAIbAAYJ+RmiCwD1AQAbAAYJ+RmiCwD1AQAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIVAAcJUhs+JQD8AQAVAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8+AAIIAAkJSxljKQBSAgAIAAkJSxljKQBSAgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgATAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAcJFgAOAL0aAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8KAAMRAAIJ1CRENADJAAARAAIJ1CRENADJAAAXAAEJKxdENwBLAAAuAAQKfxkAAxEABwkvJDYYAEMCABEABwkvJDYYAEMCABcABQkQE59TAK8AAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIcAAkJdQxAXQBlAQAcAAkJdQxAXQBlAQAAAA==.Erona:BAABLgAECn8aAAIbAAkJ1B/CBQBLAwAbAAkJ1B/CBQBLAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8XAAILAAUJhR9iQQBgAQALAAUJhR9iQQBgAQAuAAQKfygAAgsACAkfJJAaAJ8CAAsACAkfJJAaAJ8CAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAFFAEJAQAAAA==.Fartcloud:BAAALgAECgYJBgAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAABLgAECn8bAAIbAAgJ9BtMFQCUAgAbAAgJ9BtMFQCUAgABLgAFFAUJDAAIAN0XAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn8zAAIdAAkJmAuaDgBXAQAdAAkJmAuaDgBXAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8QAAIKAAQJ4wZGZwAPAQAKAAQJ4wZGZwAPAQAuAAQKfyYAAgoACQkCET9TANwBAAoACQkCET9TANwBAAAA.Flo:BAAALgADCgUJBgABLgAECggJBwAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8mAAIKAAgJTRYoBAAvAgAKAAgJTRYoBAAvAgAuAAQKfxcAAgoACAlhHSRGAGUCAAoACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAgJJgAKAE0WAA==.Footloose:BAABLgAECn8UAAIKAAgJeBHQcQCQAQAKAAgJeBHQcQCQAQAAAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgYJEAAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBQABLgAECgkJHQAcAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAeAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJBAAHAAAAAA==.Genosaur:BAAALgAECgEJBAAAAA==.Gethsemane:BAAALgAECgEJAgAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAILAAkJpRdzOwALAgALAAkJpRdzOwALAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8mAAIEAAgJvxh3FQAaAgAEAAgJvxh3FQAaAgAAAA==.Gimermonty:BAACLgAFFH8QAAIOAAQJkBI0OQAwAQAOAAQJkBI0OQAwAQAuAAQKfy0AAg4ACQmXHcsYAIUCAA4ACQmXHcsYAIUCAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAAALgAECgYJBgAAAA==.Glorfindel:BAAALgAECgkJEAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIJAAgJTQpqegA/AQAJAAgJTQpqegA/AQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMYAAgJlRpCDgDjAQAYAAYJJxxCDgDjAQAJAAcJqBYaUgCgAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8KAAIfAAIJpxMGIwB4AAAfAAIJpxMGIwB4AAAuAAQKfzcAAh8ACQmIGYkKACoCAB8ACQmIGYkKACoCAAAA.Halvor:BAAALgAECgQJCAAAAA==.Hangbladz:BAABLgAECn8VAAMcAAgJ4xoyVAB+AQAcAAgJ4xoyVAB+AQAdAAEJyw5/MwArAAAAAA==.Hanita:BAAALgAECgMJAwAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgkJLQAQADEdAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIdAAkJiCOYAQACAwAdAAkJiCOYAQACAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQALAKsbAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8TAAMZAAQJ9Q+oJAD8AAAZAAQJ9Q+oJAD8AAAbAAMJTQoXUwCYAAAuAAQKfyMAAxsACQkPF3MiABACABsACAmjFXMiABACABkABgmtFsY1AFMBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJBwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAYJBwAIAG4KAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAAALgAECgcJDQAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIcAAcJaRteSgCbAQAcAAcJaRteSgCbAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIgAAgJvw5NQQCDAQAgAAgJvw5NQQCDAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAIAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAABLgAECn8mAAQOAAcJ7RIEZQBtAQAOAAcJ7RIEZQBtAQAPAAUJsguMOADuAAANAAUJIg3KHgCtAAAAAA==.',
Kl='Klickyy:BAAALgAECgQJBQABLgAFFAUJDAAIAN0XAA==.Kllcky:BAACLgAFFH8MAAIIAAUJ3Rc1EwCsAQAIAAUJ3Rc1EwCsAQAuAAQKfyoAAggACAmSIx4PAOMCAAgACAmSIx4PAOMCAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJCQAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8vAAMPAAgJDh/xCwATAgAPAAcJGB/xCwATAgAOAAQJ4xuuhAAoAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kurkota:BAAALgADCgIJAQAAAA==.Kuwabara:BAAALgADCgYJCwAAAA==.',
Kv='Kvothè:BAAALgAECgcJDwAAAA==.',
Ky='Kyi:BAACLgAFFH8QAAIXAAQJEREVFgAKAQAXAAQJEREVFgAKAQAuAAQKfyIAAhcACQmIFe8aAMwBABcACQmIFe8aAMwBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAKAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammlock:BAAALgAECgIJAgAAAA==.Landar:BAABLgAECn9KAAIgAAkJNxlTFACfAgAgAAkJNxlTFACfAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8GAAILAAIJgxVlvgCUAAALAAIJgxVlvgCUAAABLgAFFAgJLgAZAEwhAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn80AAMPAAkJjxIyEAApAgAPAAkJjxIyEAApAgANAAEJAABjRQAAAAAAAA==.Lireesa:BAABLgAECn8jAAIYAAgJmBCADQBWAQAYAAgJmBCADQBWAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAgADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Lunn:BAABLgAECn8YAAINAAcJug/UFgDzAAANAAcJug/UFgDzAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAIIAAcJjBXBggBeAQAIAAcJjBXBggBeAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAIAA4UAA==.Mangreese:BAABLgAECn8tAAIhAAkJqRYACQAkAgAhAAkJqRYACQAkAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMeAAgJQg1eNQAzAQAeAAcJywteNQAzAQAEAAYJgAlaRwAcAQAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAgAAAA==.Mithrandir:BAAALgAECgYJBgAAAA==.Mixmasterg:BAABLgAECn8hAAIcAAkJagwEWQBwAQAcAAkJagwEWQBwAQAAAA==.',
Mo='Mograinez:BAACLgAFFH8fAAILAAgJVSVyAACEAgALAAgJVSVyAACEAgAuAAQKfxUAAgsACAl9JqUcANMCAAsACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAECgQJBAABLgAFFAYJCQAeAFYIAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgEJAQAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIQAAYJIhI+MgBDAQAQAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIJAAkJoxQxPgDdAQAJAAkJoxQxPgDdAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAACLgAFFH8KAAMNAAQJHBYEEwAhAQANAAQJOxQEEwAhAQAOAAIJxBDYdgCUAAAuAAQKfxUABA0ACQmPHXoOAGcBAA0ABwmXH3oOAGcBAA8AAwmoFSE9ANAAAA4AAQlyGYH8AFAAAAAA.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAABLgAFFH8FAAMXAAMJ0hFDKwCNAAAXAAIJyhFDKwCNAAARAAEJ4xFxVAA7AAAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8SAAMiAAMJWhtZAwBfAAAJAAIJrxlyigCbAAAiAAEJrx5ZAwBfAAAuAAQKf0EABAkACQnfIK4jAEsCAAkABwnwIK4jAEsCABgABAkoF3IuAAIBACIAAwnQIDAWANEAAAEuAAUUBQkMAAgA3RcA.',
Ol='Oldshotz:BAABLgAECn8ZAAIOAAcJ/hHSZABuAQAOAAcJ/hHSZABuAQAAAA==.',
Om='Omgsteak:BAABLgAECn8cAAMUAAYJGALnPQBrAAAUAAYJUwHnPQBrAAACAAMJZwJtaABAAAAAAA==.',
On='Onapalehorse:BAAALgAECgQJBAAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAIAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8qAAIUAAUJdiZ4BgC+AQAUAAUJdiZ4BgC+AQAuAAQKf4oABBQACQnIJisAAIwDABQACQnIJisAAIwDAAMACQn1IhsDADYDAAIACQmuIv8BACoDAAAA.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAgAAAA==.Prayforme:BAABLgAECn8sAAMeAAkJuR6iBQAkAwAeAAkJuR6iBQAkAwAFAAUJ3RSTNQA4AQAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAAALgADCgEJAQAAAA==.Prise:BAACLgAFFH8LAAMJAAQJ7BHjTwAaAQAJAAQJ7BHjTwAaAQAYAAEJvQAYKgAmAAAuAAQKfxgAAxgACQlDDgQbAHUBABgABwm+EAQbAHUBAAkACAm8C5moAOsAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMbAAkJdQmpSQBbAQAbAAkJdQmpSQBbAQAZAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAECgYJDwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8GAAIBAAIJWwdFUgBxAAABAAIJWwdFUgBxAAAuAAQKfx8AAwEACQlFGCQcAO0BAAEACQlFGCQcAO0BABMAAwn+BPUyAH4AAAAA.Ralthas:BAABLgAECn8UAAMfAAUJRw1JPgCYAAAfAAQJIhFJPgCYAAAgAAEJwQPk6wAeAAABLgAECgkJLgASAKcVAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0w83TwBqAQAUAAYJOxTYKADgAAAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgIJAgAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8kAAMIAAgJRAvhvwD8AAAIAAUJIQ7hvwD8AAAjAAcJPgb8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8kAAILAAgJGR4gKABZAgALAAgJGR4gKABZAgAAAA==.Riftstalker:BAABLgAECn8XAAMPAAcJCBdwEAC9AQAPAAcJCBdwEAC9AQAOAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgQJBQABLgAECgUJCQAHAAAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIJAAMJ/BCVcQDQAAAJAAMJ/BCVcQDQAAAuAAQKfycAAwkACQmmHosrACUCAAkACQmmHosrACUCABgAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.Roosevelt:BAAALgAECgEJAQAAAA==.',
Ru='Rushem:BAABLgAECn8WAAIDAAkJMRQ+IgDZAQADAAkJMRQ+IgDZAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAILAAgJzxYbegCQAQALAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8YAAIkAAgJUw0DFwBJAQAkAAgJUw0DFwBJAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgATAAEJ+RJXPAA8AAASAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAQJDgAeAGYWAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8pAAMMAAgJ3wWnDgC5AAAMAAQJ3ginDgC5AAALAAgJaQOY7AC3AAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgcJGAAZAFIKAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8nAAIeAAYJeyMJEABjAgAeAAYJeyMJEABjAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8PAAMVAAQJ8QxpJQDrAAAVAAQJ8QxpJQDrAAAjAAIJIAQLFABNAAAuAAQKfy4AAyMACQmQFboSAJ8BACMACAnpE7oSAJ8BABUABQliFUVEACQBAAAA.Sevinofnine:BAAALgAECgUJCwAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8bAAIlAAkJPBaCFwAFAgAlAAkJPBaCFwAFAgAAAA==.Shi:BAAALgAECgMJAwAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.Shinnylock:BAAALgADCgMJAwAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIPAAgJaA1bEgCdAQAPAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAECgcJDgAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAABLgAFFH8GAAIOAAUJORzaDQDMAQAOAAUJORzaDQDMAQAAAA==.Snipymagus:BAABLgAFFH8FAAIKAAUJMA+3XAAmAQAKAAUJMA+3XAAmAQAAAA==.Snipyterror:BAAALgADCgEJAQAAAA==.Snoodly:BAABLgAECn8YAAIWAAkJvw8KKwC/AQAWAAkJvw8KKwC/AQAAAA==.Snuu:BAAALgAECgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8LAAIKAAQJUBkpQwBWAQAKAAQJUBkpQwBWAQAuAAQKfyAAAwoACQlXHh4cAKwCAAoACQkkHh4cAKwCACYAAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIJAAkJvQvkWACOAQAJAAkJvQvkWACOAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8LAAIcAAQJNwm9TgDwAAAcAAQJNwm9TgDwAAAuAAQKfxgAAhwACQnaEyZLAMgBABwACQnaEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIUAAQJzguhHQCYAAAUAAQJzguhHQCYAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAUAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8lAAILAAkJqxudKQBSAgALAAkJqxudKQBSAgAAAA==.Stinksauce:BAACLgAFFH8WAAMSAAQJNR9WEgBWAQASAAQJNR9WEgBWAQABAAQJ4xLqJgAbAQAuAAQKfxwABBIACQkHGm4NAGACABIACQkHGm4NAGACABMAAgn3FeAaAGsAAAEAAgnKD3p/AE8AAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.',
Su='Supabox:BAAALgAFFAEJAQABLgAFFAYJFgARAHojAA==.Superchunk:BAAALgAECgIJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIEAAkJLw0bJgCGAQAEAAkJLw0bJgCGAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8yAAMVAAkJaBjEFgBJAgAVAAkJaBjEFgBJAgAIAAEJAAAZwAEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIRAAcJkRn8HwCeAQARAAcJkRn8HwCeAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAITAAkJrh1yAgCQAgATAAkJrh1yAgCQAgAAAA==.Tankytauren:BAABLgAECn82AAMMAAkJrRZqBgAuAgAMAAkJrRZqBgAuAgALAAgJFRJ+aQCLAQAAAA==.Tarquinius:BAABLgAECn80AAIQAAkJbRLsFADVAQAQAAkJbRLsFADVAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJQwADAJclAA==.Taylorswifft:BAAALgAECgcJDwAAAA==.Taynte:BAAALgAFFAIJAgAAAA==.',
Te='Telanastre:BAAALgAECgQJBwABLgAECgYJBgAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAQJEAAXABERAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAZAAoTAA==.',
Ti='Tifferny:BAABLgAECn8UAAIIAAcJexA6kgBCAQAIAAcJexA6kgBCAQAAAA==.Tiffèrny:BAAALgAFFAEJAQAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMlAAgJIBRaLQCZAQAlAAcJkxNaLQCZAQAgAAgJ+Q8lTQBQAQAAAA==.Tonkatruck:BAAALgAECgcJBgAAAA==.Totemlycool:BAABLgAECn8hAAQZAAgJGxWwIAAKAgAZAAgJCRSwIAAKAgAhAAYJlRcEEgCWAQAbAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAABLgAECn8WAAIOAAgJthk2JgA8AgAOAAgJthk2JgA8AgABLgAECgkJRwAgAGocAA==.Treehuggër:BAABLgAECn8ZAAIgAAkJgBehGAB4AgAgAAkJgBehGAB4AgAAAA==.Trisection:BAAALgAECgYJBgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAYAJUaAA==.Tryrah:BAABLgAFFH8VAAIlAAcJbBZOCwDBAQAlAAcJbBZOCwDBAQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8LAAIcAAQJMQYGUwDjAAAcAAQJMQYGUwDjAAAuAAQKfyIAAhwACQliEgRSAIQBABwACQliEgRSAIQBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAACLgAFFH8IAAIDAAQJ2Q6xIQAeAQADAAQJ2Q6xIQAeAQAuAAQKfxcAAwMACAmzGEc+AKsBAAMABwniGEc+AKsBAAIABAmhFfE2AN0AAAAA.',
['Tö']='Töömis:BAABLgAECn8ZAAIIAAcJkxOFfACBAQAIAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIDAAIJeRJ3PQCTAAADAAIJeRJ3PQCTAAAuAAQKfzkAAgMACQkHIEQMAJ4CAAMACQkHIEQMAJ4CAAAA.',
Ur='Urza:BAAALgADCgYJJQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAIkAAkJEQ4NEQCWAQAkAAkJEQ4NEQCWAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8fAAIIAAgJeA2ilgA7AQAIAAgJeA2ilgA7AQAAAA==.',
Vo='Volsunga:BAAALgAECgYJEwAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgAECgMJAwAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Wu='Wurly:BAAALgAECgEJAQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8tAAIJAAkJTxgfIQBYAgAJAAkJTxgfIQBYAgAAAA==.',
Xy='Xylazel:BAACLgAFFH8FAAILAAMJSBSPigDiAAALAAMJSBSPigDiAAAuAAQKfzcAAgsACQmnG30eAIkCAAsACQmnG30eAIkCAAAA.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8kAAMVAAYJJx1RIQDuAQAVAAYJJx1RIQDuAQAIAAMJjxa04ADQAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicùszùl:BAAALgADCgMJAwAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.Zugszy:BAAALgADCgkJCQAAAA==.Zultal:BAAALgAECgUJEAAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8oAAIlAAgJAyLGAQC1AgAlAAgJAyLGAQC1AgAuAAQKfx8AAiUACAnEJZcNAMECACUACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAgJKAAlAAMiAA==.Zzephyrfury:BAAALgAFFAEJAQAAAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAgJKAAlAAMiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIgAAgJORyrGwBfAgAgAAgJORyrGwBfAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECggJMQAgAD4SAA==.',
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
