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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Warlock-Affliction','Druid-Feral','Paladin-Protection','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgAECggJCAAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMEAAkJkhOgKgBuAQAEAAkJkhOgKgBuAQAFAAcJcgvnPQAXAQAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIGAAkJgxXaFQC6AQAGAAkJgxXaFQC6AQAAAA==.Ahroo:BAAALgAECgkJGwABLgAFFAQJBgAHAAAAAQ==.Ahrue:BAAALgAFFAQJBgAAAQ==.',
Ai='Airc:BAABLgAECn8XAAIIAAgJ9wsLxgD9AAAIAAgJ9wsLxgD9AAAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIJAAkJNQdmbwBbAQAJAAkJNQdmbwBbAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alpacalypse:BAAALgAECgcJCgAAAA==.Alvar:BAABLgAECn8ZAAIJAAgJ/hIRYQB9AQAJAAgJ/hIRYQB9AQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAUJDQAIAN0XAA==.',
Ar='Arcadium:BAACLgAFFH8IAAIKAAMJ5hqWdAD4AAAKAAMJ5hqWdAD4AAAuAAQKfxUAAgoABQlYIpZvAPUBAAoABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgcJCAAAAA==.Arêos:BAABLgAECn8eAAIEAAkJYx1YDwBvAgAEAAkJYx1YDwBvAgAAAA==.',
As='Asiloas:BAAALgAFFAEJAQAAAA==.Asunaish:BAABLgAECn8ZAAMLAAgJThvmSQDiAQALAAgJThvmSQDiAQAMAAEJPBU7NgA+AAABLgAFFAMJAwAHAAAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8gAAQNAAgJiB/7AgAlAgANAAgJMh/7AgAlAgAOAAMJiBTMGgD1AAAPAAIJ9xoCcgCtAAAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJDQAAAA==.',
Az='Azarite:BAABLgAECn87AAIIAAkJ0hEYXgCzAQAIAAkJ0hEYXgCzAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJEQAAAA==.Badassbum:BAABLgAECn8WAAIQAAYJdAUhRAChAAAQAAYJdAUhRAChAAAAAA==.Bahoodies:BAAALgAECggJCAAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Ballsofury:BAAALgAFFAMJAwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8hAAIIAAkJshn9NgAjAgAIAAkJshn9NgAjAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8mAAIRAAgJUB8pAwB0AgARAAgJUB8pAwB0AgAuAAQKfywAAhEACQkvJfQDAFADABEACQkvJfQDAFADAAAA.Bignut:BAAALgAECgcJBwAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAIJAwAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAPABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burlapt:BAAALgAECgEJAQAAAA==.Burney:BAABLgAECn9CAAMSAAkJPiFrAgBGAwASAAkJPiFrAgBGAwATAAIJcAvBHQBdAAAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8TAAIUAAQJ9x/HDABXAQAUAAQJ9x/HDABXAQAuAAQKfy8AAhQACQkFI6oEANUCABQACQkFI6oEANUCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8OAAIVAAUJUhajGABXAQAVAAUJUhajGABXAQAuAAQKfx8AAhUACAlsFL4mAPQBABUACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAIBAAkJahG/IADRAQABAAkJahG/IADRAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8eAAMWAAgJ2xMDKwDPAQAWAAgJ2xMDKwDPAQAXAAYJJRMmNwAiAQAAAA==.Chaosmage:BAABLgAECn8UAAIKAAYJ8xO7mABEAQAKAAYJ8xO7mABEAQAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickenblil:BAAALgAECgQJBQAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMTAAcJqhQNFAClAQATAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Colisto:BAAALgADCgUJBQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8VAAMJAAgJ8ww3GQDrAQAJAAgJ8ww3GQDrAQAYAAEJLwokJgBIAAAuAAQKfyoAAwkACQkRHWAlAEcCAAkACQncHGAlAEcCABgABwlbFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAMJAwAHAAAAAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAILAAgJ3h/DNABkAgALAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIZAAkJPh9WDwB5AgAZAAkJPh9WDwB5AgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAABLgAECn8dAAMaAAcJsw8DJgBhAQAaAAcJsw8DJgBhAQAbAAEJ/AHsLQAYAAAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAFFAMJAwAAAA==.',
Do='Donyolerberz:BAAALgAECggJBwAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIPAAgJEBROdwBMAQAPAAgJEBROdwBMAQAAAA==.Dragonflyy:BAAALgAECgUJCwAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAwAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8PAAIcAAcJ+BqXBgBRAgAcAAcJ+BqXBgBRAgAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIVAAcJUhs+JQD8AQAVAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8+AAIIAAkJSxn6KwBPAgAIAAkJSxn6KwBPAgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgATAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAcJFgAPAL0aAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8KAAMRAAIJ1CTNNgDHAAARAAIJ1CTNNgDHAAAXAAEJKxcDPABFAAAuAAQKfxkAAxEABwkvJDYYAEMCABEABwkvJDYYAEMCABcABQkQEwtXAK8AAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIdAAkJdQxvYABlAQAdAAkJdQxvYABlAQAAAA==.Erona:BAABLgAECn8aAAIcAAkJ1B9NBgBJAwAcAAkJ1B9NBgBJAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8YAAILAAYJSx+AKAC7AQALAAYJSx+AKAC7AQAuAAQKfyoAAgsACQmOItILAA0DAAsACQmOItILAA0DAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAFFAMJAwAAAA==.Fartcloud:BAAALgAECgYJCAAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAABLgAECn8bAAIcAAgJ9Bt0FgCTAgAcAAgJ9Bt0FgCTAgABLgAFFAUJDQAIAN0XAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn84AAIeAAkJmws2DwBXAQAeAAkJmws2DwBXAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8TAAIKAAQJLBFTXQAwAQAKAAQJLBFTXQAwAQAuAAQKfyYAAgoACQkCEbJYANABAAoACQkCEbJYANABAAAA.Flo:BAAALgAECgIJAgABLgAECggJCAAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8vAAIKAAgJsBcoBAAvAgAKAAgJsBcoBAAvAgAuAAQKfxcAAgoACAlhHSRGAGUCAAoACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAgJLwAKALAXAA==.Footloose:BAABLgAECn8bAAIKAAgJ1BIYYgC3AQAKAAgJ1BIYYgC3AQAAAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgYJEwAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBQABLgAECgkJHQAdAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAfAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJBAAHAAAAAA==.Genosaur:BAAALgAECgEJBAAAAA==.Gethsemane:BAAALgAECgEJAgAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAILAAkJpRdxPwADAgALAAkJpRdxPwADAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8tAAIEAAkJuxgODwB0AgAEAAkJuxgODwB0AgAAAA==.Gimermonty:BAACLgAFFH8TAAIPAAQJkBKLPQAsAQAPAAQJkBKLPQAsAQAuAAQKfy0AAg8ACQmXHdkaAH8CAA8ACQmXHdkaAH8CAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAAALgAECgYJBgAAAA==.Glorfindel:BAAALgAECgkJEAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIJAAgJTQqxfwA5AQAJAAgJTQqxfwA5AQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMYAAgJlRpCDgDjAQAYAAYJJxxCDgDjAQAJAAcJqBbOVQCaAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8MAAIgAAIJ3hNcJwB4AAAgAAIJ3hNcJwB4AAAuAAQKfzcAAiAACQmIGVsLACkCACAACQmIGVsLACkCAAAA.Halvor:BAAALgAECgQJCQAAAA==.Hangbladz:BAABLgAECn8XAAMdAAkJ5RsWNwDmAQAdAAkJ5RsWNwDmAQAeAAEJyw7pNQArAAAAAA==.Hanita:BAAALgAECgUJCAAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgkJLQAQADEdAA==.Hellz:BAAALgAECgkJCQAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIeAAkJiCPCAQAAAwAeAAkJiCPCAQAAAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQALAKsbAA==.',
Iw='Iwillsaverap:BAAALgAFFAEJAQAAAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8UAAMZAAUJLxKSKADtAAAZAAQJ9Q+SKADtAAAcAAQJkQkkQQDbAAAuAAQKfyMAAxwACQkPF3MiABACABwACAmjFXMiABACABkABgmtFks4AFIBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJBwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAYJBwAIAG4KAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAAALgAECgcJEwAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIdAAcJaRvoTACbAQAdAAcJaRvoTACbAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIhAAgJvw5KQwCBAQAhAAgJvw5KQwCBAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAIAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAABLgAECn8pAAQPAAcJ+RJLawBmAQAPAAcJ7RJLawBmAQAOAAUJNQ/ZNgD/AAANAAUJIg30HwCtAAAAAA==.',
Kl='Klickyy:BAAALgAECgYJBwABLgAFFAUJDQAIAN0XAA==.Kllcky:BAACLgAFFH8NAAIIAAUJ3RfVFwCkAQAIAAUJ3RfVFwCkAQAuAAQKfzAAAggACAmuI2MOAPACAAgACAmuI2MOAPACAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJCwAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8vAAMOAAgJDh/xCwATAgAOAAcJGB/xCwATAgAPAAQJ4xv1igAkAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuriboh:BAAALgADCggJCAAAAA==.Kurkota:BAAALgADCgIJAQAAAA==.Kuwabara:BAAALgADCgYJCwAAAA==.',
Kv='Kvothè:BAABLgAECn8VAAIWAAgJnBCWQABkAQAWAAgJnBCWQABkAQAAAA==.',
Ky='Kyi:BAACLgAFFH8TAAIXAAQJqhTgFAARAQAXAAQJqhTgFAARAQAuAAQKfyMAAhcACQmIFS0cAMkBABcACQmIFS0cAMkBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAKAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammlock:BAAALgAECgMJAwAAAA==.Landar:BAABLgAECn9KAAIhAAkJNxktFQCdAgAhAAkJNxktFQCdAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8GAAILAAIJgxXhzgCPAAALAAIJgxXhzgCPAAABLgAFFAkJMAAZAOceAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn80AAMOAAkJjxJWEQAhAgAOAAkJjxJWEQAhAgANAAEJAAArSAAAAAAAAA==.Lireesa:BAABLgAECn8jAAIYAAgJmBBkDgBTAQAYAAgJmBBkDgBTAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAhADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Luckycharmen:BAAALgAECgUJCQABLgAFFAUJEAAVAAgdAA==.Lunn:BAABLgAECn8YAAINAAcJug/sFwDvAAANAAcJug/sFwDvAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAIIAAcJjBUciABdAQAIAAcJjBUciABdAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAIAA4UAA==.Mangreese:BAABLgAECn8tAAIiAAkJqRa4CQAdAgAiAAkJqRa4CQAdAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMfAAgJQg0+OAAwAQAfAAcJyws+OAAwAQAEAAYJgAlaRwAcAQAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Misano:BAAALgAECgUJBQABLgAFFAEJAQAHAAAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAwAAAA==.Mithrandir:BAAALgAECgYJBgAAAA==.Mixmasterg:BAABLgAECn8hAAIdAAkJagzcWwBxAQAdAAkJagzcWwBxAQAAAA==.',
Mo='Moglaivez:BAAALgAFFAMJBAAAAA==.Mograinez:BAACLgAFFH8fAAILAAgJVSVyAACEAgALAAgJVSVyAACEAgAuAAQKfxUAAgsACAl9JqUcANMCAAsACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAFFAEJAQABLgAFFAYJCQAfAFYIAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgIJAwAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIQAAYJIhI+MgBDAQAQAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIJAAkJoxTMQADZAQAJAAkJoxTMQADZAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAACLgAFFH8NAAQNAAQJ2hfDEwAoAQANAAQJ+RXDEwAoAQAPAAIJxBDsfQCUAAAOAAEJJwe8MQBHAAAuAAQKfxUABA0ACQmPHSUPAGUBAA0ABwmXHyUPAGUBAA4AAwmoFec+AM0AAA8AAQlyGUUHAVAAAAAA.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAABLgAFFH8HAAMXAAMJrBIqIwDCAAAXAAMJrBIqIwDCAAARAAEJ4xGFVwA7AAAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8TAAMjAAMJWhtZAwBfAAAJAAIJrxknkwCWAAAjAAEJrx5ZAwBfAAAuAAQKf0QABAkACQkDIUEkAE0CAAkABwkaIUEkAE0CABgABAkoF3IuAAIBACMAAwnQIDAWANEAAAEuAAUUBQkNAAgA3RcA.',
Ol='Oldshotz:BAABLgAECn8fAAIPAAcJHxbqTwCuAQAPAAcJHxbqTwCuAQAAAA==.',
Om='Omgsteak:BAABLgAECn8dAAMUAAYJGAJzQABqAAAUAAYJUwFzQABqAAACAAMJZwJXbwA9AAAAAA==.',
On='Onapalehorse:BAAALgAECgQJBAAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAIAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8qAAIUAAUJdia6BwC2AQAUAAUJdia6BwC2AQAuAAQKf5MABBQACQnRJjcAAIoDABQACQnIJjcAAIoDAAMACQlpJNcBAF4DAAIACQmuIkwCACYDAAAA.Parsnip:BAAALgAFFAEJAQAAAA==.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAwAAAA==.Prayforme:BAABLgAECn8sAAMfAAkJuR76BQAjAwAfAAkJuR76BQAjAwAFAAUJ3RSxOAAvAQAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAAALgADCgEJAQAAAA==.Prise:BAACLgAFFH8PAAQJAAQJ7BHfVQAXAQAJAAQJ7BHfVQAXAQAjAAEJfgr2JQBIAAAYAAEJvQCCLAAmAAAuAAQKfxgAAxgACQlDDgQbAHUBABgABwm+EAQbAHUBAAkACAm8CxqwAOQAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMcAAkJdQmpSQBbAQAcAAkJdQmpSQBbAQAZAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAFFAIJAwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8GAAIBAAIJWwctWABpAAABAAIJWwctWABpAAAuAAQKfx8AAwEACQlFGAwdAOwBAAEACQlFGAwdAOwBABMAAwn+BPUyAH4AAAAA.Ralthas:BAABLgAECn8bAAQgAAgJjBFsMADjAAAgAAQJWhpsMADjAAAkAAMJ+wztMgCNAAAhAAIJhQPayQA5AAABLgAECgkJMAASAKcVAA==.Ramenshaman:BAAALgAFFAEJAgAAAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0w83TwBqAQAUAAYJOxSaKgDdAAAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgMJBAAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8kAAMIAAgJRAvFyAD6AAAIAAUJIQ7FyAD6AAAlAAcJPgb8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8lAAILAAgJGR5jKgBUAgALAAgJGR5jKgBUAgAAAA==.Riftstalker:BAABLgAECn8XAAMOAAcJCBdwEAC9AQAOAAcJCBdwEAC9AQAPAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgQJBQABLgAECgUJCQAHAAAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIJAAMJ/BCgeADNAAAJAAMJ/BCgeADNAAAuAAQKfycAAwkACQmmHkItACICAAkACQmmHkItACICABgAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.Roosevelt:BAAALgAECgEJAQAAAA==.',
Ru='Rushem:BAABLgAECn8WAAIDAAkJMRQHJADTAQADAAkJMRQHJADTAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAILAAgJzxYbegCQAQALAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8YAAIkAAgJUw0OGQBBAQAkAAgJUw0OGQBBAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgATAAEJ+RJXPAA8AAASAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAUJEAAfAIgWAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8pAAMMAAgJ3wWnDgC5AAAMAAQJ3ginDgC5AAALAAgJaQPj9QC1AAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgcJGAAZAFIKAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8nAAIfAAYJeyPKEABiAgAfAAYJeyPKEABiAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8SAAMVAAQJWxFtIwD/AAAVAAQJWxFtIwD/AAAlAAIJIAQmFQBMAAAuAAQKfy4AAyUACQmQFboSAJ8BACUACAnpE7oSAJ8BABUABQliFTZGACQBAAAA.Sevinofnine:BAAALgAECgUJDwAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8bAAImAAkJPBafGAAEAgAmAAkJPBafGAAEAgAAAA==.Shi:BAAALgAECgQJBgAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.Shinnylock:BAAALgADCgMJAwAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.Siheal:BAAALgAECgMJAwAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIOAAgJaA1bEgCdAQAOAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAFFAEJAQAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAABLgAFFH8HAAIPAAUJORxREgDCAQAPAAUJORxREgDCAQAAAA==.Snipymagus:BAABLgAFFH8FAAIKAAUJMA8/YwAmAQAKAAUJMA8/YwAmAQAAAA==.Snipyterror:BAAALgAFFAEJAQAAAA==.Snoodly:BAABLgAECn8YAAIWAAkJvw+gLQDAAQAWAAkJvw+gLQDAAQAAAA==.Snuu:BAAALgAECgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8OAAIKAAQJKB8rPQB7AQAKAAQJKB8rPQB7AQAuAAQKfyEAAwoACQlXHuUdAKcCAAoACQkkHuUdAKcCACcAAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIJAAkJvQvbXACHAQAJAAkJvQvbXACHAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8OAAIdAAQJegs3UQDzAAAdAAQJegs3UQDzAAAuAAQKfxkAAh0ACQnaEyZLAMgBAB0ACQnaEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIUAAQJzgv9HwCPAAAUAAQJzgv9HwCPAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAUAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8lAAILAAkJqxt/LABMAgALAAkJqxt/LABMAgAAAA==.Stinksauce:BAACLgAFFH8WAAMSAAQJNR+YEwBSAQASAAQJNR+YEwBSAQABAAQJ4xLXKgAXAQAuAAQKfxwABBIACQkHGm4NAGACABIACQkHGm4NAGACABMAAgn3FbYbAGsAAAEAAgnKD3eEAE8AAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.Strokntotem:BAAALgADCgcJBwAAAA==.',
Su='Supabox:BAAALgAFFAEJAQABLgAFFAYJFgARAHojAA==.Superchunk:BAAALgAECgIJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIEAAkJLw2zJwCEAQAEAAkJLw2zJwCEAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8yAAMVAAkJaBjXFwBHAgAVAAkJaBjXFwBHAgAIAAEJAABD0QEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIRAAcJkRkDIQCdAQARAAcJkRkDIQCdAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAITAAkJrh2dAgCNAgATAAkJrh2dAgCNAgAAAA==.Tankytauren:BAABLgAECn82AAMMAAkJrRb/BgAqAgAMAAkJrRb/BgAqAgALAAgJFRKJbwCDAQAAAA==.Tarquinius:BAABLgAECn80AAIQAAkJbRInFgDUAQAQAAkJbRInFgDUAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJQwADAJclAA==.Taylorswifft:BAAALgAECgcJDwAAAA==.Taynte:BAAALgAFFAIJBAAAAA==.',
Te='Telanastre:BAAALgAECgQJBwABLgAECgYJBgAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAQJEwAXAKoUAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAZAAoTAA==.',
Ti='Tifferny:BAABLgAECn8UAAIIAAcJexAYmABBAQAIAAcJexAYmABBAQAAAA==.Tiffèrny:BAAALgAFFAEJAQAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMmAAgJIBRaLQCZAQAmAAcJkxNaLQCZAQAhAAgJ+Q/nTgBRAQAAAA==.Tonkatruck:BAAALgAECgcJCAAAAA==.Totemlycool:BAABLgAECn8hAAQZAAgJGxWwIAAKAgAZAAgJCRSwIAAKAgAiAAYJlRcEEgCWAQAcAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAABLgAECn8WAAIPAAgJthnxKAA3AgAPAAgJthnxKAA3AgABLgAECgkJTAAhAGocAA==.Treehuggër:BAACLgAFFH8FAAIhAAIJjg/7VQBqAAAhAAIJjg/7VQBqAAAuAAQKfxsAAiEACQnhGLEVAJgCACEACQnhGLEVAJgCAAAA.Trisection:BAAALgAECgYJBgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAYAJUaAA==.Tryael:BAAALgAECgMJAwAAAA==.Tryrah:BAABLgAFFH8VAAImAAcJbBZkDQC7AQAmAAcJbBZkDQC7AQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8LAAIdAAQJMQZaWQDcAAAdAAQJMQZaWQDcAAAuAAQKfyIAAh0ACQliEtxUAIQBAB0ACQliEtxUAIQBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAACLgAFFH8JAAIDAAQJ2Q6HJAAdAQADAAQJ2Q6HJAAdAQAuAAQKfxcAAwMACAmzGEc+AKsBAAMABwniGEc+AKsBAAIABAmhFUk5ANsAAAAA.',
['Tö']='Töömis:BAABLgAECn8ZAAIIAAcJkxOFfACBAQAIAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIDAAIJeRKnQQCTAAADAAIJeRKnQQCTAAAuAAQKfzkAAgMACQkHIGoNAJUCAAMACQkHIGoNAJUCAAAA.',
Ur='Urza:BAAALgADCgYJJQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAIkAAkJEQ4GEgCUAQAkAAkJEQ4GEgCUAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8kAAIIAAgJGg5nmQA/AQAIAAgJGg5nmQA/AQAAAA==.',
Vo='Volsunga:BAABLgAECn8WAAIhAAYJBQRZjQCYAAAhAAYJBQRZjQCYAAAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgAECgMJAwAAAA==.',
Wo='Wow:BAAALgAECgUJCAAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Wu='Wurly:BAAALgAECgEJAQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8tAAIJAAkJTxiLIgBVAgAJAAkJTxiLIgBVAgAAAA==.',
Xy='Xylazel:BAACLgAFFH8IAAILAAMJSBQvlgDeAAALAAMJSBQvlgDeAAAuAAQKfzwAAgsACQmnG/MdAJICAAsACQmnG/MdAJICAAAA.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8kAAMVAAYJJx2gIgDtAQAVAAYJJx2gIgDtAQAIAAMJjxYv6QDPAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicùszùl:BAAALgADCgMJAwAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.Zugszy:BAAALgADCgkJCQAAAA==.Zultal:BAABLgAECn8WAAILAAcJORDqgQBdAQALAAcJORDqgQBdAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8sAAImAAgJAyLQAABMAgAmAAgJAyLQAABMAgAuAAQKfx8AAiYACAnEJZcNAMECACYACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAgJLAAmAAMiAA==.Zzephyrfury:BAABLgAFFH8GAAIDAAQJsxcxFwBTAQADAAQJsxcxFwBTAQABLgAFFAgJLAAmAAMiAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAgJLAAmAAMiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIhAAgJORyJHABfAgAhAAgJORyJHABfAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECgkJOQAhAO8QAA==.',
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
