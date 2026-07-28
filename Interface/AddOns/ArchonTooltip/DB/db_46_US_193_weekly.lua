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

local lookup = {'DemonHunter-Havoc','Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Druid-Feral','Monk-Brewmaster','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Priest-Discipline','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aantu:BAAALgAECgMJAwAAAA==.',
Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAABLgAECn8VAAIBAAkJ9gvcBwAYAQABAAkJ9gvcBwAYAQAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQACAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMDAAQJkws1BAD3AAADAAQJkws1BAD3AAAEAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMFAAkJkhNIKwBuAQAFAAkJkhNIKwBuAQAGAAcJcgsOPwAVAQAAAA==.',
Ag='Agntclappers:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIIAAkJgxVLFgC3AQAIAAkJgxVLFgC3AQAAAA==.Ahroo:BAAALgAECgkJGwABLgAFFAQJCgAHAAAAAQ==.Ahrue:BAAALgAFFAQJCgAAAQ==.',
Ai='Airc:BAABLgAECn8hAAIJAAkJhQ6QEQA5AQAJAAkJhQ6QEQA5AQAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIKAAkJNQcrcQBYAQAKAAkJNQcrcQBYAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alpacalypse:BAAALgAECgcJCwAAAA==.Alvar:BAABLgAECn8ZAAIKAAgJ/hJLYwB4AQAKAAgJ/hJLYwB4AQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAUJFQAJAEcYAA==.',
Ar='Arcadium:BAACLgAFFH8IAAILAAMJ5hrddwDqAAALAAMJ5hrddwDqAAAuAAQKfxUAAgsABQlYIpZvAPUBAAsABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgcJCAAAAA==.Arêos:BAABLgAECn8eAAIFAAkJYx2fDwBvAgAFAAkJYx2fDwBvAgAAAA==.',
As='Asiloas:BAAALgAFFAEJAQAAAA==.Asunaish:BAABLgAECn8ZAAMMAAgJThvzSgDhAQAMAAgJThvzSgDhAQANAAEJPBXcNwA9AAABLgAFFAMJBQAOAGYRAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8sAAQPAAkJkSH7AgAlAgAPAAgJbSD7AgAlAgAQAAQJrSLdBgAkAQARAAMJtx5cUgBqAAAAAA==.Atomix:BAAALgAECgYJEQAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Au='Augtoberfest:BAAALgAECgYJCgABLgAECgkJFwAJAFAbAA==.',
Ay='Ayisen:BAAALgAECgQJDQAAAA==.',
Az='Azarite:BAABLgAECn87AAIJAAkJ0hGRYACvAQAJAAkJ0hGRYACvAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJEQAAAA==.Badassbum:BAABLgAECn8gAAIBAAYJWQwYDQCqAAABAAYJWQwYDQCqAAAAAA==.Bahoodies:BAAALgAECggJCQAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balin:BAAALgAECgYJCAAAAA==.Ballsofury:BAABLgAFFH8GAAISAAMJpxBaCwBrAAASAAMJpxBaCwBrAAAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8iAAIJAAkJLhrfNwAiAgAJAAkJLhrfNwAiAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8mAAITAAgJUB+WAwByAgATAAgJUB+WAwByAgAuAAQKfywAAhMACQkvJfQDAFADABMACQkvJfQDAFADAAAA.Bignut:BAAALgAECggJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAIJAwAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAARABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burlapt:BAAALgAECgEJAQAAAA==.Burney:BAABLgAECn9GAAMOAAkJPiFzAgBGAwAOAAkJPiFzAgBGAwAUAAIJcAs+HgBdAAAAAA==.Burnnotice:BAAALgAECgMJAwAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8VAAIVAAQJ9x+yDQBTAQAVAAQJ9x+yDQBTAQAuAAQKfy8AAhUACQkFI8MEANMCABUACQkFI8MEANMCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8SAAIWAAUJUhZ+GQBWAQAWAAUJUhZ+GQBWAQAuAAQKfx8AAhYACAlsFL4mAPQBABYACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAICAAkJahFnIQDOAQACAAkJahFnIQDOAQAAAA==.',
Ce='Celebate:BAAALgAECgEJAQABLgAECgkJPwALAEYkAA==.Celenath:BAAALgADCgYJBgABLgAECgYJDQAHAAAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8rAAQXAAgJ2xPnKwDRAQAXAAgJ2xPnKwDRAQATAAcJuBW2AgCJAQAYAAYJJRMTOAAiAQAAAA==.Chaosmage:BAABLgAECn8YAAILAAYJ4RZthQBsAQALAAYJ4RZthQBsAQAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickenblil:BAAALgAECgQJBwAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgMJBgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clevergirl:BAAALgAECgYJDAAAAA==.Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMUAAcJqhQNFAClAQAUAAcJDRINFAClAQACAAYJWBE/LgBQAQAAAA==.Colisto:BAAALgAECgMJAwAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8ZAAMKAAgJIQ52GwDrAQAKAAgJIQ52GwDrAQAZAAEJLwrGKABCAAAuAAQKfywAAwoACQlRHSImAEUCAAoACQncHCImAEUCABkABwk7F5sYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAMJBQAOAGYRAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAIMAAgJ3h/DNABkAgAMAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIaAAkJPh+cDwB4AgAaAAkJPh+cDwB4AgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAABLgAECn8eAAMbAAcJsw+PJgBhAQAbAAcJsw+PJgBhAQAcAAEJ/AGxLgAYAAAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAFFAMJAwAAAA==.Disterb:BAAALgAECgcJCAAAAA==.',
Do='Donyolerberz:BAAALgAECggJBwAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIRAAgJEBSdeQBMAQARAAgJEBSdeQBMAQAAAA==.Dragonflyy:BAABLgAECn8UAAIRAAYJowajJwCgAAARAAYJowajJwCgAAAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAwAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8QAAIdAAgJ/Bl7BwBQAgAdAAgJ/Bl7BwBQAgAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIWAAcJUhs+JQD8AQAWAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8+AAIJAAkJSxnNLABNAgAJAAkJSxnNLABNAgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCgAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgAUAKoUAA==.',
El='Ellio:BAAALgADCgcJBwABLgAFFAgJFwARAAUYAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8KAAMTAAIJ1CQVOADGAAATAAIJ1CQVOADGAAAYAAEJKxcDPgBFAAAuAAQKfxkAAxMABwkvJDYYAEMCABMABwkvJDYYAEMCABgABQkQEzlYAK8AAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIeAAkJdQzpYQBlAQAeAAkJdQzpYQBlAQAAAA==.Erona:BAABLgAECn8aAAIdAAkJ1B95BgBJAwAdAAkJ1B95BgBJAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8ZAAIMAAcJPRu8KwC5AQAMAAcJPRu8KwC5AQAuAAQKfyoAAgwACQmOIiwMAAsDAAwACQmOIiwMAAsDAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAABLgAFFH8FAAMOAAMJZhGwEQB8AAAOAAMJZhGwEQB8AAAUAAEJdAyVDgBEAAAAAA==.Fartcloud:BAAALgAECgcJCgAAAA==.Fatigued:BAAALgAECggJDQAAAA==.Faultydecay:BAAALgAECgQJBAAAAA==.',
Fe='Feech:BAACLgAFFH8GAAIdAAQJWhGkHADhAAAdAAQJWhGkHADhAAAuAAQKfx4AAh0ACAnGHeoWAJICAB0ACAnGHeoWAJICAAEuAAUUBQkVAAkARxgA.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn84AAIfAAkJmwt3DwBXAQAfAAkJmwt3DwBXAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8VAAILAAQJLBFMYAAgAQALAAQJLBFMYAAgAQAuAAQKfyYAAgsACQkCESRaAM8BAAsACQkCESRaAM8BAAAA.Flo:BAAALgAECgMJBAABLgAECggJCQAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH9IAAILAAkJ9BwoBAAvAgALAAkJ9BwoBAAvAgAuAAQKfxcAAgsACAlhHSRGAGUCAAsACAlhHSRGAGUCAAAA.Foopsadin:BAABLgAFFH8JAAIJAAUJ3RMIGgAlAQAJAAUJ3RMIGgAlAQABLgAFFAkJSAALAPQcAA==.Footloose:BAABLgAECn8uAAMLAAgJqBctCwCTAQALAAgJqBctCwCTAQAgAAEJyA5zFwAzAAABLgAECggJIwAJANwXAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgYJEwAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBQABLgAECgkJHQAeAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.Gassommelier:BAAALgAFFAEJAQAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAhAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJBAAHAAAAAA==.Genosaur:BAAALgAECgEJBAAAAA==.Gethsemane:BAAALgAECgEJAgAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAIMAAkJpRcFQQAAAgAMAAkJpRcFQQAAAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8uAAIFAAkJ0RlWDwBzAgAFAAkJ0RlWDwBzAgAAAA==.Gimermonty:BAACLgAFFH8UAAIRAAQJkBKoQAAsAQARAAQJkBKoQAAsAQAuAAQKfy0AAhEACQmXHcQbAH4CABEACQmXHcQbAH4CAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAABLgAECn8VAAILAAgJ/wO9JgCmAAALAAgJ/wO9JgCmAAAAAA==.Glorfindel:BAAALgAECgkJEAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIKAAgJTQr6gQA1AQAKAAgJTQr6gQA1AQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMZAAgJlRpCDgDjAQAZAAYJJxxCDgDjAQAKAAcJqBZiVgCZAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8XAAIiAAMJwxacDgCvAAAiAAMJwxacDgCvAAAuAAQKfzkAAiIACQmIGZELACkCACIACQmIGZELACkCAAAA.Halvor:BAAALgAECgUJCgAAAA==.Hangbladz:BAABLgAECn8XAAMeAAkJ5RvKNwDnAQAeAAkJ5RvKNwDnAQAfAAEJyw7xNgArAAAAAA==.Hanita:BAAALgAFFAIJBAAAAA==.Happyz:BAAALgADCgYJBgAAAA==.Hardwarë:BAAALgAECggJCQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgkJLQABADEdAA==.Hellz:BAAALgAECgkJCQAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIfAAkJiCPKAQAAAwAfAAkJiCPKAQAAAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQAMAKsbAA==.',
Iw='Iwillsaverap:BAAALgAFFAEJAQAAAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8cAAMaAAcJfBDqDQBDAQAaAAcJfBDqDQBDAQAdAAQJkQkcQwDbAAAuAAQKfyMAAx0ACQkPF3MiABACAB0ACAmjFXMiABACABoABgmtFio5AFIBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJBwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAgJCAAJAAcMAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAABLgAECn8tAAMjAAkJARkzAgBpAgAjAAkJARkzAgBpAgAkAAQJJwbodgBYAAAAAA==.Kageyuki:BAEALgAECgYJBgABLgAFFAkJIwAQAGcWAA==.Kai:BAAALgAECgYJBwAAAA==.Kaitaro:BAAALgAECgIJAgAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIeAAcJaRvfTQCcAQAeAAcJaRvfTQCcAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIjAAgJvw4tRACAAQAjAAgJvw4tRACAAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAJAA4UAA==.Ketheric:BAAALgAFFAEJAQAAAA==.',
Ki='Kickalot:BAAALgAECgEJAgAAAA==.Kindinos:BAACLgAFFH8SAAIQAAQJOg1tBwAZAQAQAAQJOg1tBwAZAQAuAAQKfy0ABBEACQmnE4ltAGYBABEACAmGEYltAGYBABAACAlZERAHAMMAAA8ABQkiDXIgAK0AAAAA.',
Kl='Klickyy:BAABLgAFFH8QAAIBAAQJ1yMoBACmAQABAAQJ1yMoBACmAQABLgAFFAUJFQAJAEcYAA==.Kliiden:BAAALgAFFAIJAwABLgAFFAUJFQAJAEcYAA==.Kllcky:BAACLgAFFH8VAAIJAAUJRxj2GQCjAQAJAAUJRxj2GQCjAQAuAAQKfzUAAgkACAlnJtwOAO8CAAkACAlnJtwOAO8CAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJCwAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8vAAMQAAgJDh/xCwATAgAQAAcJGB/xCwATAgARAAQJ4xvajQAjAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQACAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuriboh:BAAALgAECgMJBgAAAA==.Kurkota:BAAALgADCgIJAQAAAA==.Kuwabara:BAAALgADCgYJCwAAAA==.',
Kv='Kvothè:BAABLgAECn8WAAIXAAgJJBF3PwBxAQAXAAgJJBF3PwBxAQAAAA==.',
Ky='Kyi:BAACLgAFFH8UAAIYAAQJqhSwFQARAQAYAAQJqhSwFQARAQAuAAQKfyMAAhgACQmIFbscAMkBABgACQmIFbscAMkBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAALAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammh:BAAALgAECgMJAwAAAA==.Lammlock:BAAALgAECgMJAwAAAA==.Landar:BAABLgAECn9KAAIjAAkJNxmaFQCcAgAjAAkJNxmaFQCcAgAAAA==.Laracroftt:BAAALgADCgEJAQAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.Lazurin:BAAALgAECgIJAgAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8HAAIMAAIJIhl4xQCgAAAMAAIJIhl4xQCgAAABLgAFFAkJWAAaABIjAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn80AAMQAAkJjxLNEQAbAgAQAAkJjxLNEQAbAgAPAAEJAABuSQAAAAAAAA==.Lirastiria:BAAALgADCgMJAwAAAA==.Lireesa:BAABLgAECn8jAAIZAAgJmBCoDgBTAQAZAAgJmBCoDgBTAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAjADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Luckycharmen:BAAALgAFFAMJAwABLgAFFAYJEQAWALEZAA==.Lunn:BAABLgAECn8YAAIPAAcJug9UGADvAAAPAAcJug9UGADvAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
['Lí']='Líght:BAAALgAECgEJAQAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8jAAIJAAgJ3BeCCgCgAQAJAAgJ3BeCCgCgAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAJAA4UAA==.Mangreese:BAABLgAECn8yAAIlAAkJpRhcAwBZAQAlAAkJpRhcAwBZAQAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMhAAgJQg3lOQApAQAhAAcJywvlOQApAQAFAAYJgAlaRwAcAQAAAA==.Miasma:BAAALgAECgQJBAAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Misano:BAAALgAECgUJBQABLgAFFAEJAQAHAAAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAwAAAA==.Mithrandir:BAAALgAECgYJDQAAAA==.Mixmasterg:BAABLgAECn8hAAIeAAkJagwYXQBxAQAeAAkJagwYXQBxAQAAAA==.',
Mk='Mk:BAAALgAECgEJAQAAAA==.',
Mo='Moglaivez:BAABLgAFFH8MAAMBAAUJBB6fBQBvAQABAAUJBB6fBQBvAQAfAAEJwRf/CQBGAAAAAA==.Mograinez:BAACLgAFFH82AAIMAAkJliZIAACGAwAMAAkJliZIAACGAwAuAAQKfxUAAgwACAl9JqUcANMCAAwACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAFFAEJAQABLgAFFAgJEwAhABYPAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgIJAwAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIBAAYJIhI+MgBDAQABAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAFFAEJAwAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIKAAkJoxR9QQDYAQAKAAkJoxR9QQDYAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAACLgAFFH8OAAQPAAQJ2hegFAAhAQAPAAQJ+RWgFAAhAQARAAIJxBAtgwCUAAAQAAEJJwfzMgBHAAAuAAQKfxUABA8ACQmPHXIPAGUBAA8ABwmXH3IPAGUBABAAAwmoFfk/AMgAABEAAQlyGeMMAVAAAAAA.Nukashine:BAAALgADCgYJCAAAAA==.Nuovis:BAAALgAECgIJAgAAAA==.Nuuro:BAABLgAFFH8HAAMYAAMJrBKFJADBAAAYAAMJrBKFJADBAAATAAEJ4xH8WAA7AAAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8aAAMmAAMJYh5ZAwBfAAAKAAIJOx5WMwC5AAAmAAEJrx5ZAwBfAAAuAAQKf0oABAoACQljIvgkAEsCAAoABwkaIfgkAEsCABkABAnUGnIuAAIBACYAAwnQIDAWANEAAAEuAAUUBQkVAAkARxgA.',
Ol='Oldshotz:BAABLgAECn8xAAIRAAcJpRoACgC0AQARAAcJpRoACgC0AQAAAA==.',
Om='Omgsteak:BAABLgAECn8sAAMVAAcJzQLTCQCUAAAVAAcJXwLTCQCUAAADAAMJZwIFcgA9AAAAAA==.Omoba:BAAALgAECgMJBAAAAA==.',
On='Onapalehorse:BAAALgAECgQJBgAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAJAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerkuh:BAEALgAFFAEJAQABLgAFFAUJMAAVAHYmAA==.Panzerwolf:BAECLgAFFH8wAAIVAAUJdiY0CAC0AQAVAAUJdiY0CAC0AQAuAAQKf5sABBUACQnRJj4AAIkDABUACQnKJj4AAIkDAAQACQlpJO4BAFsDAAMACQmuImgCACUDAAAA.Parsnip:BAABLgAFFH8GAAILAAIJ3gYZtABpAAALAAIJ3gYZtABpAAAAAA==.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAgAAAA==.',
Pr='Pray:BAAALgAECgIJAwAAAA==.Prayforme:BAABLgAECn87AAMhAAkJOCKiAAByAwAhAAkJOCKiAAByAwAGAAUJ3RTNOQAsAQAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAEALgADCgEJAQAAAA==.Prinky:BAAALgADCgMJAwAAAA==.Prise:BAACLgAFFH8QAAQKAAQJ7BEWWAAXAQAKAAQJ7BEWWAAXAQAmAAEJfgoGJwBIAAAZAAEJvQCLLQAlAAAuAAQKfxgAAxkACQlDDgQbAHUBABkABwm+EAQbAHUBAAoACAm8C96yAOAAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMdAAkJdQmpSQBbAQAdAAkJdQmpSQBbAQAaAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAFFAMJBAAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8MAAICAAYJqAuUFwDmAAACAAYJqAuUFwDmAAAuAAQKfyAAAwIACQnRGZ8dAOoBAAIACQnRGZ8dAOoBABQAAwn+BPUyAH4AAAAA.Ralthas:BAACLgAFFH8OAAMkAAQJpBN4DgAZAQAkAAQJpBN4DgAZAQAiAAMJew/3EgCKAAAuAAQKfyYABSIACQnFEPsIAOYAACIABAlNHPsIAOYAABIAAwk5DT40AI0AACMAAgmFA8HMADgAACQAAQm/BF8mABkAAAEuAAQKBgkOAAcAAAAA.Ramenshaman:BAAALgAFFAEJAwAAAA==.Randark:BAABLgAECn8nAAQDAAgJhRr5CgD0AQADAAYJCx35CgD0AQAEAAcJ0w83TwBqAQAVAAYJOxQ4KwDdAAAAAA==.Rangol:BAAALgAECgYJBgAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAFFAQJBAAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgQJBgAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8pAAMJAAgJrg5vIADFAAAnAAcJhQf8JADgAAAJAAYJHxNvIADFAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8mAAIMAAkJhBxZKwBTAgAMAAkJhBxZKwBTAgAAAA==.Riftstalker:BAABLgAECn8YAAMQAAcJCBdwEAC9AQAQAAcJCBdwEAC9AQARAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgQJBQABLgAECgUJCQAHAAAAAA==.',
Rn='Rngesus:BAACLgAFFH8KAAIKAAMJ/BA3ewDNAAAKAAMJ/BA3ewDNAAAuAAQKfycAAwoACQmmHgkuACACAAoACQmmHgkuACACABkAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.',
Ru='Runie:BAEALgAFFAEJAQABLgAFFAkJLAADAAgfAA==.Rushem:BAABLgAECn8WAAIEAAkJMRTPJADPAQAEAAkJMRTPJADPAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.Ruyn:BAAALgAECgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAIMAAgJzxYbegCQAQAMAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8YAAISAAgJUw2QGQBCAQASAAgJUw2QGQBCAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQCAAgJVhc7EQBlAgACAAgJPxc7EQBlAgAUAAEJ+RJXPAA8AAAOAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAUJEwAhALAXAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8pAAMNAAgJ3wWnDgC5AAANAAQJ3ginDgC5AAAMAAgJaQN7+gCzAAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgcJGQAaAFIKAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8oAAIhAAYJeyMyEQBgAgAhAAYJeyMyEQBgAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8UAAMWAAQJDhJdJAD+AAAWAAQJDhJdJAD+AAAnAAIJIAQAFgBLAAAuAAQKfy4AAycACQmQFboSAJ8BACcACAnpE7oSAJ8BABYABQliFd5GACQBAAAA.Sevinofnine:BAABLgAECn8VAAIaAAUJagmwFQB3AAAaAAUJagmwFQB3AAAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shamanigans:BAAALgAECgQJBQAAAA==.Shamantics:BAAALgAECgUJDwABLgAECggJCwAHAAAAAA==.Shanic:BAABLgAECn8bAAIkAAkJPBZSGQACAgAkAAkJPBZSGQACAgAAAA==.Sharlan:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.Shi:BAAALgAECgUJCAAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.Shinnylock:BAAALgADCgMJAwAAAA==.Shàr:BAAALgAECgUJBQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.Siheal:BAAALgAECgcJBwAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIQAAgJaA1bEgCdAQAQAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAFFAEJAQAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAABLgAFFH8LAAMRAAgJDhlhFADAAQARAAYJSRphFADAAQAPAAIJXhXrDACtAAAAAA==.Snipymagus:BAABLgAFFH8FAAILAAUJMA8HZgAXAQALAAUJMA8HZgAXAQAAAA==.Snipyterror:BAAALgAFFAEJAQAAAA==.Snoodly:BAABLgAECn8YAAIXAAkJvw+uLgDCAQAXAAkJvw+uLgDCAQAAAA==.Snuu:BAAALgAECgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8PAAILAAQJKB/EPgBzAQALAAQJKB/EPgBzAQAuAAQKfyEAAwsACQlXHooeAKYCAAsACQkkHooeAKYCACAAAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIKAAkJvQuzXgCDAQAKAAkJvQuzXgCDAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Specimenb:BAAALgAECgUJCAAAAA==.Spirallidan:BAACLgAFFH8QAAIeAAQJeguHUwDzAAAeAAQJeguHUwDzAAAuAAQKfxkAAh4ACQnaEyZLAMgBAB4ACQnaEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIVAAQJzgseIQCPAAAVAAQJzgseIQCPAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAVAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stayk:BAAALgADCgEJAgAAAA==.Stepbro:BAABLgAECn8lAAIMAAkJqxvILQBIAgAMAAkJqxvILQBIAgAAAA==.Stinksauce:BAACLgAFFH8WAAMOAAQJNR9GFABRAQAOAAQJNR9GFABRAQACAAQJ4xIcLQAQAQAuAAQKfxwABA4ACQkHGm4NAGACAA4ACQkHGm4NAGACABQAAgn3FSocAGsAAAIAAgnKD8uGAE8AAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.Strokntotem:BAAALgAECgMJBgAAAA==.',
Su='Supabox:BAAALgAFFAEJAQABLgAFFAYJFgATAHojAA==.Superchunk:BAAALgAECgYJCAAAAA==.Supergotenks:BAAALgADCgMJAwAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIFAAkJLw1NKACEAQAFAAkJLw1NKACEAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8yAAMWAAkJaBgoGABHAgAWAAkJaBgoGABHAgAJAAEJAADw2QEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAITAAcJkRlrIQCdAQATAAcJkRlrIQCdAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAIUAAkJrh2sAgCNAgAUAAkJrh2sAgCNAgAAAA==.Tankytauren:BAACLgAFFH8NAAINAAUJmBElCAARAQANAAUJmBElCAARAQAuAAQKfzYAAw0ACQmtFisHACgCAA0ACQmtFisHACgCAAwACAkVEjlyAH8BAAAA.Targe:BAAALgAECgEJAwAAAA==.Tarquinius:BAABLgAECn84AAIBAAkJIRS6FgDRAQABAAkJIRS6FgDRAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJQwAEAJclAA==.Taylorswifft:BAAALgAECgcJDwAAAA==.Taynte:BAABLgAFFH8PAAImAAMJFhaNBADnAAAmAAMJFhaNBADnAAAAAA==.',
Te='Telanastre:BAAALgAECgUJDAABLgAECgYJDQAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAFFAEJAQABLgAFFAQJFAAYAKoUAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAaAAoTAA==.',
Ti='Tifferny:BAACLgAFFH8MAAIJAAIJAgf5TAB0AAAJAAIJAgf5TAB0AAAuAAQKfxUAAgkABwl7EDOaAEEBAAkABwl7EDOaAEEBAAAA.Tiffèrny:BAABLgAFFH8JAAIRAAIJlgM4UABwAAARAAIJlgM4UABwAAAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMkAAgJIBRaLQCZAQAkAAcJkxNaLQCZAQAjAAgJ+Q99TwBRAQAAAA==.Tonkatruck:BAAALgAECggJCgAAAA==.Toroshin:BAAALgAECgkJDwAAAA==.Totemlycool:BAABLgAECn8hAAQaAAgJGxWwIAAKAgAaAAgJCRSwIAAKAgAlAAYJlRcEEgCWAQAdAAIJhAGWkwBNAAABLgAECggJIQACAFYXAA==.',
Tr='Trappress:BAABLgAECn8aAAIRAAgJthkMKgA2AgARAAgJthkMKgA2AgABLgAFFAQJBgAjAHgTAA==.Treehuggër:BAACLgAFFH8JAAIjAAIJkA+cJQBTAAAjAAIJkA+cJQBTAAAuAAQKfx0AAiMACQlbGRYWAJgCACMACQlbGRYWAJgCAAAA.Trisection:BAAALgAECgYJBgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAZAJUaAA==.Tryael:BAAALgAECgMJAwAAAA==.Tryrah:BAABLgAFFH8VAAIkAAcJbBZsDgC5AQAkAAcJbBZsDgC5AQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8LAAIeAAQJMQbeWwDcAAAeAAQJMQbeWwDcAAAuAAQKfyIAAh4ACQliEv1VAIUBAB4ACQliEv1VAIUBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAACLgAFFH8KAAIEAAQJ2Q7JJQAdAQAEAAQJ2Q7JJQAdAQAuAAQKfxcAAwQACAmzGEc+AKsBAAQABwniGEc+AKsBAAMABAmhFYk6ANsAAAAA.',
['Tö']='Töömis:BAABLgAECn8ZAAIJAAcJkxOFfACBAQAJAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIEAAIJeRKNQwCTAAAEAAIJeRKNQwCTAAAuAAQKfzkAAgQACQkHININAJICAAQACQkHININAJICAAAA.',
Um='Umbreon:BAAALgAECgcJCQAAAA==.',
Ur='Urza:BAAALgADCgYJJQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAISAAkJEQ5iEgCVAQASAAkJEQ5iEgCVAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8mAAIJAAgJGQ8XnQA8AQAJAAgJGQ8XnQA8AQAAAA==.',
Vo='Voidmister:BAAALgAECgYJBgAAAA==.Volsunga:BAABLgAECn8WAAIjAAYJBQSpjgCYAAAjAAYJBQSpjgCYAAAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wa='Watlas:BAAALgAECggJCAABLgAFFAQJCQAMAEUdAA==.',
Wi='Wildling:BAAALgADCgcJBwAAAA==.Winda:BAAALgAECgMJAwAAAA==.',
Wo='Wolf:BAAALgADCgIJAgAAAA==.Wow:BAAALgAECgUJCAAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Wu='Wurly:BAAALgAECgEJAQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn84AAIKAAkJqRk9AwBTAgAKAAkJqRk9AwBTAgAAAA==.',
Xy='Xylazel:BAACLgAFFH8RAAIMAAQJNhQMLAAZAQAMAAQJNhQMLAAZAQAuAAQKf04AAgwACQm1HegFAPsBAAwACQm1HegFAPsBAAAA.',
Ya='Yaboyfresh:BAAALgADCgIJAgAAAA==.Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8lAAMWAAYJJx0ZIwDsAQAWAAYJJx0ZIwDsAQAJAAMJjxYA7ADPAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicùszùl:BAAALgADCgMJAwAAAA==.Zephyrpriest:BAABLgAFFH8FAAIGAAUJ6QkTDwD2AAAGAAUJ6QkTDwD2AAABLgAFFAkJRwAkAA0lAA==.',
Zi='Zinzert:BAAALgADCgMJAwABLgAECgYJDgAHAAAAAQ==.',
Zu='Zugmaster:BAAALgAFFAEJAQAAAA==.Zugszy:BAAALgAECgYJBwAAAA==.Zultal:BAABLgAECn8WAAIMAAcJORAJhQBaAQAMAAcJORAJhQBaAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH9HAAMkAAkJDSV+AABIAwAkAAkJDSV+AABIAwAjAAEJrAu1LAA+AAAuAAQKfx8AAiQACAnEJZcNAMECACQACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAkJRwAkAA0lAA==.Zzephyrfury:BAABLgAFFH8KAAIEAAQJQx/sCgBUAQAEAAQJQx/sCgBUAQABLgAFFAkJRwAkAA0lAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAkJRwAkAA0lAA==.',
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
