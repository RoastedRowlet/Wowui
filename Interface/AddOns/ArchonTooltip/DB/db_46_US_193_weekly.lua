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

local lookup = {'DemonHunter-Havoc','Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Feral','Monk-Brewmaster','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Priest-Discipline','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aantu:BAAALgAECgMJAwAAAA==.',
Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAABLgAECn8VAAIBAAkJ9gt+CAAZAQABAAkJ9gt+CAAZAQAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQACAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMDAAQJkws1BAD3AAADAAQJkws1BAD3AAAEAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMFAAkJkhNIKwBuAQAFAAkJkhNIKwBuAQAGAAcJcgsOPwAVAQAAAA==.',
Ag='Agntclappers:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIIAAkJgxVLFgC3AQAIAAkJgxVLFgC3AQAAAA==.Ahroo:BAAALgAECgkJGwABLgAFFAQJCgAHAAAAAQ==.Ahrue:BAAALgAFFAQJCgAAAQ==.',
Ai='Airc:BAABLgAECn8lAAIJAAkJhQ7YEwAzAQAJAAkJhQ7YEwAzAQAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIKAAkJNQcrcQBYAQAKAAkJNQcrcQBYAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alpacalypse:BAAALgAECgcJCwAAAA==.Alvar:BAABLgAECn8ZAAIKAAgJ/hJLYwB4AQAKAAgJ/hJLYwB4AQAAAA==.',
An='Anathemã:BAAALgAFFAIJAgABLgAFFAUJFwAJAEwYAA==.',
Ar='Arcadium:BAACLgAFFH8IAAILAAMJ5hrddwDqAAALAAMJ5hrddwDqAAAuAAQKfxUAAgsABQlYIpZvAPUBAAsABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgcJCAAAAA==.Arêos:BAABLgAECn8eAAIFAAkJYx2fDwBvAgAFAAkJYx2fDwBvAgAAAA==.',
As='Asiloas:BAAALgAFFAEJAQAAAA==.Asunaish:BAABLgAECn8ZAAMMAAgJThvzSgDhAQAMAAgJThvzSgDhAQANAAEJPBXcNwA9AAABLgAFFAMJBQAOAGYRAA==.',
At='Atiko:BAAALgAECgEJAQABLgAFFAcJHAAPAHwQAA==.Atomicrednax:BAABLgAFFH8wAAQQAAkJaSP7AgAlAgAQAAgJiCL7AgAlAgARAAUJqSAmBABxAQASAAMJtx5dVQBpAAAAAA==.Atomix:BAAALgAECgYJEQAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Au='Augtoberfest:BAAALgAECgYJCgABLgAECgkJFwAJAFAbAA==.',
Ay='Ayisen:BAAALgAECgQJDgAAAA==.',
Az='Azarite:BAABLgAECn87AAIJAAkJ0hGRYACvAQAJAAkJ0hGRYACvAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJEQAAAA==.Badassbum:BAABLgAECn8jAAIBAAgJMw0mCQAJAQABAAgJMw0mCQAJAQAAAA==.Bahoodies:BAAALgAECggJCQAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balin:BAAALgAECgYJCAAAAA==.Ballsofury:BAABLgAFFH8HAAITAAMJpxDFCwBqAAATAAMJpxDFCwBqAAAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8jAAIJAAkJixvfNwAiAgAJAAkJixvfNwAiAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8mAAIUAAgJUB+WAwByAgAUAAgJUB+WAwByAgAuAAQKfywAAhQACQkvJfQDAFADABQACQkvJfQDAFADAAAA.Bignut:BAAALgAECggJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAIJAwAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAASABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burlapt:BAAALgAECgEJAQAAAA==.Burney:BAABLgAECn9GAAMOAAkJPiFzAgBGAwAOAAkJPiFzAgBGAwAVAAIJcAs+HgBdAAAAAA==.Burnnotice:BAAALgAECgMJAwAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8VAAIWAAQJ9x+yDQBTAQAWAAQJ9x+yDQBTAQAuAAQKfy8AAhYACQkFI8MEANMCABYACQkFI8MEANMCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8TAAIXAAYJMBd+GQBWAQAXAAYJMBd+GQBWAQAuAAQKfx8AAhcACAlsFL4mAPQBABcACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAICAAkJahFnIQDOAQACAAkJahFnIQDOAQAAAA==.',
Ce='Celebate:BAAALgAECgEJAQABLgAECgkJPwALAEYkAA==.Celenath:BAAALgADCgYJBgABLgAECgYJDQAHAAAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8rAAQYAAgJ2xPnKwDRAQAYAAgJ2xPnKwDRAQAUAAcJuBXsAgCHAQAZAAYJJRMTOAAiAQAAAA==.Chaosmage:BAABLgAECn8YAAILAAYJ4RZthQBsAQALAAYJ4RZthQBsAQAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickenblil:BAAALgAECgQJBwAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgMJBgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clevergirl:BAAALgAECgYJDAAAAA==.Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMVAAcJqhQNFAClAQAVAAcJDRINFAClAQACAAYJWBE/LgBQAQAAAA==.Colisto:BAAALgAECgYJCQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8ZAAMKAAgJIQ52GwDrAQAKAAgJIQ52GwDrAQAaAAEJLwrGKABCAAAuAAQKfywAAwoACQlRHSImAEUCAAoACQncHCImAEUCABoABwk7F5sYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAMJBQAOAGYRAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAIMAAgJ3h/DNABkAgAMAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIPAAkJPh+cDwB4AgAPAAkJPh+cDwB4AgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAABLgAECn8eAAMbAAcJsw+PJgBhAQAbAAcJsw+PJgBhAQAcAAEJ/AGxLgAYAAAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAFFAMJAwAAAA==.Disterb:BAAALgAECgcJCAAAAA==.',
Do='Donyolerberz:BAAALgAECggJBwAAAA==.',
Dr='Draeno:BAABLgAECn8UAAISAAgJEBSdeQBMAQASAAgJEBSdeQBMAQAAAA==.Dragonflyy:BAABLgAECn8UAAISAAYJowaYKgCfAAASAAYJowaYKgCfAAAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAwAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8QAAIdAAgJ/Bl7BwBQAgAdAAgJ/Bl7BwBQAgAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIXAAcJUhs+JQD8AQAXAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8+AAIJAAkJSxnNLABNAgAJAAkJSxnNLABNAgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCgAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgAVAKoUAA==.',
El='Ellio:BAAALgADCgcJBwABLgAFFAgJFwASAAUYAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8KAAMUAAIJ1CQVOADGAAAUAAIJ1CQVOADGAAAZAAEJKxcDPgBFAAAuAAQKfxkAAxQABwkvJDYYAEMCABQABwkvJDYYAEMCABkABQkQEzlYAK8AAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIeAAkJdQzpYQBlAQAeAAkJdQzpYQBlAQAAAA==.Erona:BAABLgAECn8aAAIdAAkJ1B95BgBJAwAdAAkJ1B95BgBJAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8ZAAIMAAcJPRu8KwC5AQAMAAcJPRu8KwC5AQAuAAQKfzIAAgwACQmZIiwMAAsDAAwACQmZIiwMAAsDAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAABLgAFFH8FAAMOAAMJZhFYEgB7AAAOAAMJZhFYEgB7AAAVAAEJdAyVDgBEAAAAAA==.Fartcloud:BAAALgAECgcJCgAAAA==.Farven:BAAALgAFFAEJAQABLgAFFAUJFwAJAEwYAA==.Fatigued:BAAALgAECggJDQAAAA==.Faultydecay:BAAALgAECgQJBAAAAA==.',
Fe='Feech:BAACLgAFFH8GAAIdAAQJWhHdHQDfAAAdAAQJWhHdHQDfAAAuAAQKfx4AAh0ACAnGHeoWAJICAB0ACAnGHeoWAJICAAEuAAUUBQkXAAkATBgA.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn84AAIfAAkJmwt3DwBXAQAfAAkJmwt3DwBXAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8VAAILAAQJLBFMYAAgAQALAAQJLBFMYAAgAQAuAAQKfyYAAgsACQkCESRaAM8BAAsACQkCESRaAM8BAAAA.Flo:BAAALgAECgMJBAABLgAECggJCQAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH9KAAILAAkJ9BwoBAAvAgALAAkJ9BwoBAAvAgAuAAQKfxcAAgsACAlhHSRGAGUCAAsACAlhHSRGAGUCAAAA.Foopsadin:BAABLgAFFH8OAAIJAAUJFhp5FgBDAQAJAAUJFhp5FgBDAQABLgAFFAkJSgALAPQcAA==.Footloose:BAABLgAECn8xAAMLAAgJChhOCwCiAQALAAgJChhOCwCiAQAgAAEJyA5zFwAzAAABLgAECggJIwAJANwXAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgYJEwAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBQABLgAECgkJHQAeAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.Gassommelier:BAAALgAFFAEJAQAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAhAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJBAAHAAAAAA==.Genosaur:BAAALgAECgEJBAAAAA==.Gethsemane:BAAALgAECgEJAgAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAIMAAkJpRcFQQAAAgAMAAkJpRcFQQAAAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8uAAIFAAkJ0RlWDwBzAgAFAAkJ0RlWDwBzAgAAAA==.Gimermonty:BAACLgAFFH8UAAISAAQJkBKoQAAsAQASAAQJkBKoQAAsAQAuAAQKfy0AAhIACQmXHcQbAH4CABIACQmXHcQbAH4CAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAABLgAECn8VAAILAAgJ/wOqKQCmAAALAAgJ/wOqKQCmAAAAAA==.Glorfindel:BAAALgAECgkJEAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIKAAgJTQr6gQA1AQAKAAgJTQr6gQA1AQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMaAAgJlRpCDgDjAQAaAAYJJxxCDgDjAQAKAAcJqBZiVgCZAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8XAAIiAAMJwxaQDwCqAAAiAAMJwxaQDwCqAAAuAAQKfzkAAiIACQmIGZELACkCACIACQmIGZELACkCAAAA.Halvor:BAAALgAECgUJCgAAAA==.Hangbladz:BAABLgAECn8XAAMeAAkJ5RvKNwDnAQAeAAkJ5RvKNwDnAQAfAAEJyw7xNgArAAAAAA==.Hanita:BAAALgAFFAIJBAAAAA==.Happyz:BAAALgADCgYJBgAAAA==.Hardwarë:BAAALgAECgkJEgAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgkJLQABADEdAA==.Hellz:BAAALgAECgkJEQAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIfAAkJiCPKAQAAAwAfAAkJiCPKAQAAAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQAMAKsbAA==.',
Iw='Iwillsaverap:BAAALgAFFAEJAQAAAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8cAAMPAAcJfBD6DgA/AQAPAAcJfBD6DgA/AQAdAAQJkQkcQwDbAAAuAAQKfyMAAx0ACQkPF3MiABACAB0ACAmjFXMiABACAA8ABgmtFio5AFIBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJBwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAgJCAAJAAcMAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAABLgAECn8tAAMjAAkJARljAgBmAgAjAAkJARljAgBmAgAkAAQJJwbodgBYAAAAAA==.Kageyuki:BAEALgAECgYJBgABLgAFFAkJJgARAHgYAA==.Kai:BAAALgAECgYJBwAAAA==.Kaitaro:BAAALgAECgIJAgAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIeAAcJaRvfTQCcAQAeAAcJaRvfTQCcAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIjAAgJvw4tRACAAQAjAAgJvw4tRACAAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAJAA4UAA==.Ketheric:BAAALgAFFAEJAQAAAA==.',
Ki='Kickalot:BAAALgAECgEJAgAAAA==.Kindinos:BAACLgAFFH8SAAIRAAQJOg3RBwAZAQARAAQJOg3RBwAZAQAuAAQKfy0ABBIACQmnE4ltAGYBABIACAmGEYltAGYBABEACAlZEZYHAMMAABAABQkiDXIgAK0AAAAA.',
Kl='Klickyy:BAABLgAFFH8RAAIBAAQJ1yN2BACjAQABAAQJ1yN2BACjAQABLgAFFAUJFwAJAEwYAA==.Kliiden:BAAALgAFFAIJAwABLgAFFAUJFwAJAEwYAA==.Kllcky:BAACLgAFFH8XAAIJAAUJTBi1EAB3AQAJAAUJTBi1EAB3AQAuAAQKfzUAAgkACAlnJtwOAO8CAAkACAlnJtwOAO8CAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJCwAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8vAAMRAAgJDh/xCwATAgARAAcJGB/xCwATAgASAAQJ4xvajQAjAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQACAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuriboh:BAAALgAECgMJBgAAAA==.Kurkota:BAAALgADCgIJAQAAAA==.Kuwabara:BAAALgADCgYJCwAAAA==.',
Kv='Kvothè:BAABLgAECn8XAAIYAAgJvxF3PwBxAQAYAAgJvxF3PwBxAQAAAA==.',
Ky='Kyi:BAACLgAFFH8UAAIZAAQJqhSwFQARAQAZAAQJqhSwFQARAQAuAAQKfyMAAhkACQmIFbscAMkBABkACQmIFbscAMkBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAALAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammh:BAAALgAECgMJAwAAAA==.Lammlock:BAAALgAECgMJAwAAAA==.Landar:BAABLgAECn9KAAIjAAkJNxmaFQCcAgAjAAkJNxmaFQCcAgAAAA==.Laracroftt:BAAALgADCgEJAQAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.Lazurin:BAAALgAECgYJCgAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8HAAIMAAIJIhl4xQCgAAAMAAIJIhl4xQCgAAABLgAFFAkJWgAPABIjAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn80AAMRAAkJjxLNEQAbAgARAAkJjxLNEQAbAgAQAAEJAABuSQAAAAAAAA==.Lirastiria:BAAALgADCgMJAwAAAA==.Lireesa:BAABLgAECn8jAAIaAAgJmBCoDgBTAQAaAAgJmBCoDgBTAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAjADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Luckycharmen:BAAALgAFFAMJAwABLgAFFAYJEQAXALEZAA==.Lunn:BAABLgAECn8YAAIQAAcJug9UGADvAAAQAAcJug9UGADvAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
['Lí']='Líght:BAAALgAECgEJAQAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8jAAIJAAgJ3Be9CwCcAQAJAAgJ3Be9CwCcAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAJAA4UAA==.Mangreese:BAABLgAECn85AAIlAAkJYhuEAQAMAgAlAAkJYhuEAQAMAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMhAAgJQg3lOQApAQAhAAcJywvlOQApAQAFAAYJgAlaRwAcAQAAAA==.Miasma:BAAALgAECgkJDQAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Misano:BAAALgAECgUJBQABLgAFFAEJAQAHAAAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAwAAAA==.Mithrandir:BAAALgAECgYJDQAAAA==.Mixmasterg:BAABLgAECn8hAAIeAAkJagwYXQBxAQAeAAkJagwYXQBxAQAAAA==.',
Mk='Mk:BAAALgAECgEJAQAAAA==.',
Mo='Moglaivez:BAABLgAFFH8MAAMBAAUJBB4DBgBsAQABAAUJBB4DBgBsAQAfAAEJwRd5CgBFAAAAAA==.Mograinez:BAACLgAFFH86AAIMAAkJmCZTAACGAwAMAAkJmCZTAACGAwAuAAQKfxUAAgwACAl9JqUcANMCAAwACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAFFAEJAQABLgAFFAgJEwAhABYPAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgIJAwAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIBAAYJIhI+MgBDAQABAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAFFAEJAwAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIKAAkJoxR9QQDYAQAKAAkJoxR9QQDYAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAACLgAFFH8OAAQQAAQJ2hegFAAhAQAQAAQJ+RWgFAAhAQASAAIJxBAtgwCUAAARAAEJJwfzMgBHAAAuAAQKfxUABBAACQmPHXIPAGUBABAABwmXH3IPAGUBABEAAwmoFfk/AMgAABIAAQlyGeMMAVAAAAAA.Nukashine:BAAALgADCgYJCAAAAA==.Nuovis:BAAALgAECgIJAgAAAA==.Nuuro:BAABLgAFFH8HAAMZAAMJrBKFJADBAAAZAAMJrBKFJADBAAAUAAEJ4xH8WAA7AAAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8aAAMmAAMJYh5ZAwBfAAAKAAIJOx59NQC4AAAmAAEJrx5ZAwBfAAAuAAQKf0oABAoACQljIvgkAEsCAAoABwkaIfgkAEsCABoABAnUGnIuAAIBACYAAwnQIDAWANEAAAEuAAUUBQkXAAkATBgA.',
Ol='Oldshotz:BAABLgAECn8yAAISAAcJpRoACwCzAQASAAcJpRoACwCzAQAAAA==.',
Om='Omgsteak:BAABLgAECn8tAAMWAAcJzQKkCgCUAAAWAAcJXwKkCgCUAAADAAMJZwIFcgA9AAAAAA==.Omoba:BAAALgAECgMJBAAAAA==.',
On='Onapalehorse:BAAALgAECgQJBgAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAJAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerkuh:BAEALgAFFAMJAwABLgAFFAUJMAAWAHYmAA==.Panzerwolf:BAECLgAFFH8wAAIWAAUJdiY0CAC0AQAWAAUJdiY0CAC0AQAuAAQKf5sABBYACQnRJj4AAIkDABYACQnKJj4AAIkDAAQACQlpJO4BAFsDAAMACQmuImgCACUDAAAA.Parsnip:BAABLgAFFH8GAAILAAIJ3gYZtABpAAALAAIJ3gYZtABpAAAAAA==.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAgAAAA==.',
Pr='Pray:BAAALgAECgIJAwAAAA==.Prayforme:BAABLgAECn87AAMhAAkJOCKuAAByAwAhAAkJOCKuAAByAwAGAAUJ3RTNOQAsAQAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAEALgADCgEJAQAAAA==.Prinky:BAAALgADCgMJAwAAAA==.Prise:BAACLgAFFH8QAAQKAAQJ7BEWWAAXAQAKAAQJ7BEWWAAXAQAmAAEJfgoGJwBIAAAaAAEJvQCLLQAlAAAuAAQKfxgAAxoACQlDDgQbAHUBABoABwm+EAQbAHUBAAoACAm8C96yAOAAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMdAAkJdQmpSQBbAQAdAAkJdQmpSQBbAQAPAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAFFAMJBAAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8MAAICAAYJqAvRGQDUAAACAAYJqAvRGQDUAAAuAAQKfyAAAwIACQnRGZ8dAOoBAAIACQnRGZ8dAOoBABUAAwn+BPUyAH4AAAAA.Ralthas:BAACLgAFFH8OAAMkAAQJpBOhDwAXAQAkAAQJpBOhDwAXAQAiAAMJew8UFACFAAAuAAQKfyoABSIACQnFEGIJAOoAACIABAlNHGIJAOoAABMAAwk5DT40AI0AACMAAgmFA8HMADgAACQAAQm/BGoqABkAAAEuAAQKBgkOAAcAAAAA.Ramenshaman:BAAALgAFFAEJAwAAAA==.Randark:BAABLgAECn8nAAQDAAgJhRr5CgD0AQADAAYJCx35CgD0AQAEAAcJ0w83TwBqAQAWAAYJOxQ4KwDdAAAAAA==.Rangol:BAAALgAECgYJBgAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAFFAQJBAAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgQJBgAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8vAAMJAAkJ3BGyEABVAQAJAAgJLhSyEABVAQAnAAcJ7Af8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8mAAIMAAkJhBxZKwBTAgAMAAkJhBxZKwBTAgAAAA==.Riftstalker:BAABLgAECn8YAAMRAAcJCBdwEAC9AQARAAcJCBdwEAC9AQASAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgQJBQABLgAECgUJCQAHAAAAAA==.',
Rn='Rngesus:BAACLgAFFH8KAAIKAAMJ/BA3ewDNAAAKAAMJ/BA3ewDNAAAuAAQKfycAAwoACQmmHgkuACACAAoACQmmHgkuACACABoAAgliBsNWAGoAAAEuAAUUBwkcAA8AfBAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.',
Ru='Runie:BAEALgAFFAEJAQABLgAFFAkJLgADAAgfAA==.Rushem:BAABLgAECn8WAAIEAAkJMRTPJADPAQAEAAkJMRTPJADPAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.Ruyn:BAAALgAECgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAIMAAgJzxYbegCQAQAMAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8YAAITAAgJUw2QGQBCAQATAAgJUw2QGQBCAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQCAAgJVhc7EQBlAgACAAgJPxc7EQBlAgAVAAEJ+RJXPAA8AAAOAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAUJEwAhALAXAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8pAAMNAAgJ3wWnDgC5AAANAAQJ3ginDgC5AAAMAAgJaQN7+gCzAAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgcJGQAPAFIKAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8oAAIhAAYJeyMyEQBgAgAhAAYJeyMyEQBgAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8UAAMXAAQJDhJdJAD+AAAXAAQJDhJdJAD+AAAnAAIJIAQAFgBLAAAuAAQKfy4AAycACQmQFboSAJ8BACcACAnpE7oSAJ8BABcABQliFd5GACQBAAAA.Sevinofnine:BAABLgAECn8VAAIPAAUJagm9FwB1AAAPAAUJagm9FwB1AAAAAA==.',
Sh='Shadowsong:BAAALgAECgYJBgAAAA==.Shalamar:BAAALgAECgEJBAAAAA==.Shamanigans:BAAALgAECgQJBQAAAA==.Shamantics:BAAALgAECgUJDwABLgAECggJCwAHAAAAAA==.Shanic:BAABLgAECn8bAAIkAAkJPBZSGQACAgAkAAkJPBZSGQACAgAAAA==.Sharlan:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.Shi:BAAALgAECgUJCAAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.Shinnylock:BAAALgADCgMJAwAAAA==.Shàr:BAAALgAECgUJBQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.Siheal:BAAALgAECgcJBwAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIRAAgJaA1bEgCdAQARAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAFFAEJAQAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAABLgAFFH8MAAMSAAgJDhlhFADAAQASAAYJSRphFADAAQAQAAIJXhVbDQCrAAAAAA==.Snipymagus:BAABLgAFFH8FAAILAAUJMA8HZgAXAQALAAUJMA8HZgAXAQAAAA==.Snipyterror:BAAALgAFFAQJBAAAAA==.Snoodly:BAABLgAECn8YAAIYAAkJvw+uLgDCAQAYAAkJvw+uLgDCAQAAAA==.Snuu:BAAALgAECgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8PAAILAAQJKB/EPgBzAQALAAQJKB/EPgBzAQAuAAQKfyEAAwsACQlXHooeAKYCAAsACQkkHooeAKYCACAAAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIKAAkJvQuzXgCDAQAKAAkJvQuzXgCDAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Specimenb:BAAALgAECgUJCAAAAA==.Spirallidan:BAACLgAFFH8QAAIeAAQJeguHUwDzAAAeAAQJeguHUwDzAAAuAAQKfxkAAh4ACQnaEyZLAMgBAB4ACQnaEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIWAAQJzgseIQCPAAAWAAQJzgseIQCPAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAWAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stayk:BAAALgADCgEJAgAAAA==.Stepbro:BAABLgAECn8lAAIMAAkJqxvILQBIAgAMAAkJqxvILQBIAgAAAA==.Stinksauce:BAACLgAFFH8WAAMOAAQJNR9GFABRAQAOAAQJNR9GFABRAQACAAQJ4xIcLQAQAQAuAAQKfxwABA4ACQkHGm4NAGACAA4ACQkHGm4NAGACABUAAgn3FSocAGsAAAIAAgnKD8uGAE8AAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.Strokntotem:BAAALgAECgMJBgAAAA==.',
Su='Supabox:BAAALgAFFAEJAQABLgAFFAYJFgAUAHojAA==.Superchunk:BAAALgAECgYJCAAAAA==.Supergotenks:BAAALgADCgMJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIFAAkJLw1NKACEAQAFAAkJLw1NKACEAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8yAAMXAAkJaBgoGABHAgAXAAkJaBgoGABHAgAJAAEJAADw2QEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIUAAcJkRlrIQCdAQAUAAcJkRlrIQCdAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAIVAAkJrh2sAgCNAgAVAAkJrh2sAgCNAgAAAA==.Tankytauren:BAACLgAFFH8NAAINAAUJmBGfCAARAQANAAUJmBGfCAARAQAuAAQKfzYAAw0ACQmtFisHACgCAA0ACQmtFisHACgCAAwACAkVEjlyAH8BAAAA.Targe:BAAALgAECgEJAwAAAA==.Tarquinius:BAABLgAECn84AAIBAAkJIRS6FgDRAQABAAkJIRS6FgDRAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJQwAEAJclAA==.Taylorswifft:BAAALgAECgcJDwAAAA==.Taynte:BAABLgAFFH8PAAImAAMJFhboBADlAAAmAAMJFhboBADlAAAAAA==.',
Te='Telanastre:BAAALgAECgUJDAABLgAECgYJDQAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAFFAEJAQABLgAFFAQJFAAZAKoUAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAPAAoTAA==.',
Ti='Tifferny:BAACLgAFFH8NAAIJAAIJAgeITwB0AAAJAAIJAgeITwB0AAAuAAQKfxUAAgkABwl7EDOaAEEBAAkABwl7EDOaAEEBAAAA.Tiffèrny:BAABLgAFFH8LAAISAAIJ0gdiTgCBAAASAAIJ0gdiTgCBAAAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMkAAgJIBRaLQCZAQAkAAcJkxNaLQCZAQAjAAgJ+Q99TwBRAQAAAA==.Tonkatruck:BAAALgAECggJCgAAAA==.Toroshin:BAAALgAECgkJDwAAAA==.Totemlycool:BAABLgAECn8hAAQPAAgJGxWwIAAKAgAPAAgJCRSwIAAKAgAlAAYJlRcEEgCWAQAdAAIJhAGWkwBNAAABLgAECggJIQACAFYXAA==.',
Tr='Trappress:BAABLgAECn8aAAISAAgJthkMKgA2AgASAAgJthkMKgA2AgABLgAFFAQJBgAjAHgTAA==.Treehuggër:BAACLgAFFH8JAAIjAAIJkA+vJgBTAAAjAAIJkA+vJgBTAAAuAAQKfx0AAiMACQlbGRYWAJgCACMACQlbGRYWAJgCAAAA.Trisection:BAAALgAECgYJBgAAAA==.Trogkin:BAAALgAFFAQJBAABLgAFFAkJWgAPABIjAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAaAJUaAA==.Tryael:BAAALgAECgMJAwAAAA==.Tryrah:BAABLgAFFH8VAAIkAAcJbBZsDgC5AQAkAAcJbBZsDgC5AQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8LAAIeAAQJMQbeWwDcAAAeAAQJMQbeWwDcAAAuAAQKfyIAAh4ACQliEv1VAIUBAB4ACQliEv1VAIUBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAACLgAFFH8KAAIEAAQJ2Q7JJQAdAQAEAAQJ2Q7JJQAdAQAuAAQKfxcAAwQACAmzGEc+AKsBAAQABwniGEc+AKsBAAMABAmhFYk6ANsAAAAA.',
['Tö']='Töömis:BAABLgAECn8ZAAIJAAcJkxOFfACBAQAJAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIEAAIJeRKNQwCTAAAEAAIJeRKNQwCTAAAuAAQKfzkAAgQACQkHININAJICAAQACQkHININAJICAAAA.',
Um='Umbreon:BAAALgAECgcJCQAAAA==.',
Ur='Urza:BAAALgADCgYJJQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAITAAkJEQ5iEgCVAQATAAkJEQ5iEgCVAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8mAAIJAAgJGQ8XnQA8AQAJAAgJGQ8XnQA8AQAAAA==.',
Vo='Voidmister:BAAALgAECgYJBgAAAA==.Volsunga:BAABLgAECn8WAAIjAAYJBQSpjgCYAAAjAAYJBQSpjgCYAAAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wa='Watlas:BAAALgAFFAEJAQABLgAFFAQJCQAMAEUdAA==.',
Wi='Wildling:BAAALgADCgcJBwAAAA==.Winda:BAAALgAECgMJAwAAAA==.',
Wo='Wolf:BAAALgADCgIJAgAAAA==.Wow:BAAALgAECgUJCAAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Wu='Wurly:BAAALgAECgEJAQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn84AAIKAAkJqRmCAwBRAgAKAAkJqRmCAwBRAgAAAA==.',
Xy='Xylazel:BAACLgAFFH8RAAIMAAQJNhR7LgAVAQAMAAQJNhR7LgAVAQAuAAQKf04AAgwACQm1HZMGAPcBAAwACQm1HZMGAPcBAAAA.',
Ya='Yaboyfresh:BAAALgADCgIJAgAAAA==.Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8lAAMXAAYJJx0ZIwDsAQAXAAYJJx0ZIwDsAQAJAAMJjxYA7ADPAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicùszùl:BAAALgADCgMJAwAAAA==.Zephyrpriest:BAABLgAFFH8KAAIGAAUJ+hUfDAAmAQAGAAUJ+hUfDAAmAQABLgAFFAkJSwAkAA0lAA==.',
Zi='Ziggles:BAAALgAECgQJBAAAAA==.Zinzert:BAAALgADCgMJAwABLgAECgYJDgAHAAAAAQ==.',
Zu='Zugmaster:BAAALgAFFAEJAQAAAA==.Zugszy:BAAALgAECgYJBwAAAA==.Zultal:BAABLgAECn8WAAIMAAcJORAJhQBaAQAMAAcJORAJhQBaAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH9LAAMkAAkJDSWZAABCAwAkAAkJDSWZAABCAwAjAAEJrAuoLQA+AAAuAAQKfx8AAiQACAnEJZcNAMECACQACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAkJSwAkAA0lAA==.Zzephyrfury:BAABLgAFFH8KAAIEAAQJQx/YCwBRAQAEAAQJQx/YCwBRAQABLgAFFAkJSwAkAA0lAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAkJSwAkAA0lAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIjAAgJORzrHABfAgAjAAgJORzrHABfAgAAAA==.',
['Ôä']='Ôäk:BAAALgAECgMJBAABLgAECgkJOgAjAO8QAA==.',
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
