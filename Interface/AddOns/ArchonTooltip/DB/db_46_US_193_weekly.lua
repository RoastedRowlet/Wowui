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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Priest-Discipline','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Warlock-Affliction','Druid-Feral','Paladin-Protection',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgAECggJCAAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8dAAMEAAkJkhNAKwBuAQAEAAkJkhNAKwBuAQAFAAcJcgsKPwAVAQAAAA==.',
Ah='Ahminous:BAABLgAECn8dAAIGAAkJgxVKFgC3AQAGAAkJgxVKFgC3AQAAAA==.Ahroo:BAAALgAECgkJGwABLgAFFAQJBgAHAAAAAQ==.Ahrue:BAAALgAFFAQJBgAAAQ==.',
Ai='Airc:BAABLgAECn8XAAIIAAgJ9wseygD7AAAIAAgJ9wseygD7AAAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIJAAkJNQcrcQBYAQAJAAkJNQcrcQBYAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alpacalypse:BAAALgAECgcJCwAAAA==.Alvar:BAABLgAECn8ZAAIJAAgJ/hJLYwB4AQAJAAgJ/hJLYwB4AQAAAA==.',
An='Anathemã:BAAALgADCgIJAgABLgAFFAUJDQAIAN0XAA==.',
Ar='Arcadium:BAACLgAFFH8IAAIKAAMJ5hr7dwDqAAAKAAMJ5hr7dwDqAAAuAAQKfxUAAgoABQlYIpZvAPUBAAoABQlYIpZvAPUBAAAA.Arkhan:BAAALgAECgUJCAAAAA==.Arynna:BAAALgAECgcJCAAAAA==.Arêos:BAABLgAECn8eAAIEAAkJYx2fDwBvAgAEAAkJYx2fDwBvAgAAAA==.',
As='Asiloas:BAAALgAFFAEJAQAAAA==.Asunaish:BAABLgAECn8ZAAMLAAgJThvuSgDhAQALAAgJThvuSgDhAQAMAAEJPBXaNwA9AAABLgAFFAMJAwAHAAAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8gAAQNAAgJiB/7AgAlAgANAAgJMh/7AgAlAgAOAAMJiBSiGwD0AAAPAAIJ9xr0dgCsAAAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJDQAAAA==.',
Az='Azarite:BAABLgAECn87AAIIAAkJ0hGTYACvAQAIAAkJ0hGTYACvAQAAAA==.',
Ba='Babybilly:BAAALgAECgYJEQAAAA==.Badassbum:BAABLgAECn8WAAIQAAYJdAXQRQCfAAAQAAYJdAXQRQCfAAAAAA==.Bahoodies:BAAALgAECggJCQAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Ballsofury:BAAALgAFFAMJAwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8hAAIIAAkJshnhNwAiAgAIAAkJshnhNwAiAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8mAAIRAAgJUB+WAwByAgARAAgJUB+WAwByAgAuAAQKfywAAhEACQkvJfQDAFADABEACQkvJfQDAFADAAAA.Bignut:BAAALgAECggJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Bortikus:BAAALgAECgQJBwABLgAFFAIJAwAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJDQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAPABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBgAAAA==.Burgi:BAAALgAECgQJBgAAAA==.Burlapt:BAAALgAECgEJAQAAAA==.Burney:BAABLgAECn9GAAMSAAkJPiFzAgBGAwASAAkJPiFzAgBGAwATAAIJcAs9HgBdAAAAAA==.',
['Bá']='Bánhammer:BAAALgADCgEJAQAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8TAAIUAAQJ9x+0DQBTAQAUAAQJ9x+0DQBTAQAuAAQKfy8AAhQACQkFI8UEANMCABQACQkFI8UEANMCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Calidon:BAAALgADCgQJAgAAAA==.Cannaboss:BAAALgAECgQJDQAAAA==.Carll:BAACLgAFFH8SAAIVAAUJUhaFGQBWAQAVAAUJUhaFGQBWAQAuAAQKfx8AAhUACAlsFL4mAPQBABUACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8gAAIBAAkJahFlIQDOAQABAAkJahFlIQDOAQAAAA==.',
Ce='Celenath:BAAALgADCgYJBgABLgAECgYJCAAHAAAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAABLgAECn8eAAMWAAgJ2xPkKwDRAQAWAAgJ2xPkKwDRAQAXAAYJJRMUOAAiAQAAAA==.Chaosmage:BAABLgAECn8YAAIKAAYJ4RZqhQBsAQAKAAYJ4RZqhQBsAQAAAA==.Charizard:BAAALgAECgIJBAAAAA==.Chickenblil:BAAALgAECgQJBQAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAgAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clevergirl:BAAALgAECgEJAQAAAA==.Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgcJCgAAAA==.Coconutz:BAAALgADCgEJAQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMTAAcJqhQNFAClAQATAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Colisto:BAAALgADCgUJBQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJCAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8YAAMJAAgJ8wySGwDrAQAJAAgJ8wySGwDrAQAYAAEJLwrJKABCAAAuAAQKfyoAAwkACQkRHSImAEUCAAkACQncHCImAEUCABgABwlbFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAFFAMJAwAHAAAAAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAILAAgJ3h/DNABkAgALAAgJ3h/DNABkAgAAAA==.Decimez:BAABLgAECn8dAAIZAAkJPh+dDwB4AgAZAAkJPh+dDwB4AgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJDAAAAA==.Dellinsane:BAABLgAECn8eAAMaAAcJsw+PJgBiAQAaAAcJsw+PJgBiAQAbAAEJ/AGvLgAYAAAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dillydaley:BAAALgAECgMJAwAAAA==.Dingiswayo:BAAALgAECggJEwAAAA==.Dipz:BAAALgAFFAMJAwAAAA==.',
Do='Donyolerberz:BAAALgAECggJBwAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIPAAgJEBSeeQBMAQAPAAgJEBSeeQBMAQAAAA==.Dragonflyy:BAAALgAECgUJCwAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Draks:BAAALgAECgEJAwAAAA==.Drbonedaddy:BAAALgAECgYJBgAAAA==.Drinkyds:BAABLgAFFH8PAAIcAAcJ+BqHBwBPAgAcAAcJ+BqHBwBPAgAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8dAAIVAAcJUhs+JQD8AQAVAAcJUhs+JQD8AQAAAA==.Durly:BAAALgAECgEJAQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8+AAIIAAkJSxnQLABNAgAIAAkJSxnQLABNAgAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgATAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAcJFgAPAL0aAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8KAAMRAAIJ1CQmOADGAAARAAIJ1CQmOADGAAAXAAEJKxcGPgBFAAAuAAQKfxkAAxEABwkvJDYYAEMCABEABwkvJDYYAEMCABcABQkQEzlYAK8AAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8dAAIdAAkJdQzqYQBlAQAdAAkJdQzqYQBlAQAAAA==.Erona:BAABLgAECn8aAAIcAAkJ1B97BgBJAwAcAAkJ1B97BgBJAwAAAA==.',
Es='Escorpiøn:BAACLgAFFH8YAAILAAYJSx/NKwC5AQALAAYJSx/NKwC5AQAuAAQKfyoAAgsACQmOIisMAAsDAAsACQmOIisMAAsDAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAFFAMJAwAAAA==.Fartcloud:BAAALgAECgcJCgAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAABLgAECn8bAAIcAAgJ9BvqFgCSAgAcAAgJ9BvqFgCSAgABLgAFFAUJDQAIAN0XAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn84AAIeAAkJmwt3DwBXAQAeAAkJmwt3DwBXAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgAECgMJAwAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8TAAIKAAQJLBFlYAAgAQAKAAQJLBFlYAAgAQAuAAQKfyYAAgoACQkCESVaAM8BAAoACQkCESVaAM8BAAAA.Flo:BAAALgAECgMJBAABLgAECggJCQAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8vAAIKAAgJsBcoBAAvAgAKAAgJsBcoBAAvAgAuAAQKfxcAAgoACAlhHSRGAGUCAAoACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAgJLwAKALAXAA==.Footloose:BAABLgAECn8hAAMKAAgJeBR1AwAZAQAKAAgJeBR1AwAZAQAfAAEJyA5zFwAzAAAAAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgYJEwAAAA==.Fumìn:BAAALgAECgEJAQAAAA==.',
Ga='Gadzookah:BAAALgAECgMJBQABLgAECgkJHQAdAHUMAA==.Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAgAJUIAA==.Gemblie:BAAALgADCgEJAgAAAA==.Genohbreaker:BAAALgAECgEJAgABLgAECgEJBAAHAAAAAA==.Genosaur:BAAALgAECgEJBAAAAA==.Gethsemane:BAAALgAECgEJAgAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8wAAILAAkJpRcAQQAAAgALAAkJpRcAQQAAAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8tAAIEAAkJuxhWDwBzAgAEAAkJuxhWDwBzAgAAAA==.Gimermonty:BAACLgAFFH8TAAIPAAQJkBKtQAAsAQAPAAQJkBKtQAAsAQAuAAQKfy0AAg8ACQmXHcYbAH4CAA8ACQmXHcYbAH4CAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Gladrielle:BAAALgAECgYJBgAAAA==.Glorfindel:BAAALgAECgkJEAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIJAAgJTQr2gQA1AQAJAAgJTQr2gQA1AQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMYAAgJlRpCDgDjAQAYAAYJJxxCDgDjAQAJAAcJqBZiVgCZAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Habusakix:BAAALgAECgYJCgAAAA==.Hakal:BAACLgAFFH8MAAIhAAIJ3hPhKAB4AAAhAAIJ3hPhKAB4AAAuAAQKfzgAAiEACQmIGZELACkCACEACQmIGZELACkCAAAA.Halvor:BAAALgAECgQJCQAAAA==.Hangbladz:BAABLgAECn8XAAMdAAkJ5RvINwDnAQAdAAkJ5RvINwDnAQAeAAEJyw7uNgArAAAAAA==.Hanita:BAAALgAFFAEJAQAAAA==.Happyz:BAAALgADCgYJBgAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgAECgEJAQABLgAECgkJLQAQADEdAA==.Hellz:BAAALgAECgkJCQAAAA==.',
Hu='Hukdemon:BAABLgAECn8dAAIeAAkJiCPLAQAAAwAeAAkJiCPLAQAAAwAAAA==.Humpday:BAAALgAECgEJAQAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAgAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJJQALAKsbAA==.',
Iw='Iwillsaverap:BAAALgAFFAEJAQAAAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8UAAMZAAUJLxITKgDtAAAZAAQJ9Q8TKgDtAAAcAAQJkQkcQwDbAAAuAAQKfyMAAxwACQkPF3MiABACABwACAmjFXMiABACABkABgmtFiQ5AFIBAAAA.',
Ji='Jiveturkey:BAAALgAECgQJBwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAYJBwAIAG4KAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedra:BAAALgADCgEJAQAAAA==.Kaedrelyn:BAABLgAECn8ZAAMiAAcJQBqYJwAUAgAiAAcJQBqYJwAUAgAjAAMJagXmdgBYAAAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJBAAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIdAAcJaRvjTQCcAQAdAAcJaRvjTQCcAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIiAAgJvw4vRACAAQAiAAgJvw4vRACAAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAIAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kickalot:BAAALgAECgEJAgAAAA==.Kindinos:BAACLgAFFH8GAAIOAAIJcQTAKwCEAAAOAAIJcQTAKwCEAAAuAAQKfykABA8ABwn5Eo5tAGYBAA8ABwntEo5tAGYBAA4ABQk1D7o3APoAAA0ABQkiDXEgAK0AAAAA.',
Kl='Klickyy:BAAALgAFFAEJAQABLgAFFAUJDQAIAN0XAA==.Kllcky:BAACLgAFFH8NAAIIAAUJ3RcKGgCjAQAIAAUJ3RcKGgCjAQAuAAQKfzAAAggACAmuI9kOAO8CAAgACAmuI9kOAO8CAAAA.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgUJCwAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8vAAMOAAgJDh/xCwATAgAOAAcJGB/xCwATAgAPAAQJ4xvdjQAjAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuriboh:BAAALgAECgMJBgAAAA==.Kurkota:BAAALgADCgIJAQAAAA==.Kuwabara:BAAALgADCgYJCwAAAA==.',
Kv='Kvothè:BAABLgAECn8WAAIWAAgJJBF1PwBxAQAWAAgJJBF1PwBxAQAAAA==.',
Ky='Kyi:BAACLgAFFH8TAAIXAAQJqhSyFQARAQAXAAQJqhSyFQARAQAuAAQKfyMAAhcACQmIFbscAMkBABcACQmIFbscAMkBAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAKAGQeAA==.',
La='Lactosetwo:BAAALgAECgQJCQABLgAECgcJCgAHAAAAAA==.Lammlock:BAAALgAECgMJAwAAAA==.Landar:BAABLgAECn9KAAIiAAkJNxmaFQCcAgAiAAkJNxmaFQCcAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.Lazurin:BAAALgAECgEJAQAAAA==.',
Le='Lefordini:BAAALgAECgQJCAAAAA==.Leggomyâggro:BAABLgAFFH8HAAILAAIJIhl7xQCgAAALAAIJIhl7xQCgAAABLgAFFAkJOQAZAMwgAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn80AAMOAAkJjxLPEQAbAgAOAAkJjxLPEQAbAgANAAEJAABvSQAAAAAAAA==.Lireesa:BAABLgAECn8jAAIYAAgJmBCoDgBTAQAYAAgJmBCoDgBTAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAiADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Luckycharmen:BAAALgAFFAMJAwABLgAFFAUJEAAVAAgdAA==.Lunn:BAABLgAECn8YAAINAAcJug9TGADvAAANAAcJug9TGADvAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8XAAIIAAcJjBUCigBcAQAIAAcJjBUCigBcAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAIAA4UAA==.Mangreese:BAABLgAECn8tAAIkAAkJqRbvCQAcAgAkAAkJqRbvCQAcAgAAAA==.Matelk:BAAALgAECgQJBgAAAA==.',
Me='Meekseek:BAAALgAECgUJEgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8ZAAMgAAgJQg3nOQApAQAgAAcJywvnOQApAQAEAAYJgAlaRwAcAQAAAA==.Mightypeen:BAAALgAECgIJAQAAAA==.Mikiela:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJDQAAAA==.Misano:BAAALgAECgUJBQABLgAFFAEJAQAHAAAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgAECgIJAwAAAA==.Mithrandir:BAAALgAECgYJCAAAAA==.Mixmasterg:BAABLgAECn8hAAIdAAkJagwZXQBxAQAdAAkJagwZXQBxAQAAAA==.',
Mo='Moglaivez:BAAALgAFFAMJBAAAAA==.Mograinez:BAACLgAFFH8fAAILAAgJVSVyAACEAgALAAgJVSVyAACEAgAuAAQKfxUAAgsACAl9JqUcANMCAAsACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAFFAEJAQABLgAFFAgJEQAgAKYMAA==.',
Mu='Murderer:BAAALgAECgMJCQAAAA==.',
Mv='Mvpthepally:BAAALgAECgIJAwAAAA==.',
My='Mylo:BAAALgADCgUJBQAAAA==.Mythunrus:BAABLgAECn8YAAIQAAYJIhI+MgBDAQAQAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBgAAAA==.',
No='Norolock:BAABLgAECn8dAAIJAAkJoxR8QQDYAQAJAAkJoxR8QQDYAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCQAAAA==.',
Nu='Nuero:BAACLgAFFH8OAAQNAAQJ2hewFAAhAQANAAQJ+RWwFAAhAQAPAAIJxBAtgwCUAAAOAAEJJwfwMgBHAAAuAAQKfxUABA0ACQmPHXEPAGUBAA0ABwmXH3EPAGUBAA4AAwmoFfg/AMgAAA8AAQlyGeAMAVAAAAAA.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAABLgAFFH8HAAMXAAMJrBKFJADBAAAXAAMJrBKFJADBAAARAAEJ4xEDWQA7AAAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8TAAMlAAMJWhtZAwBfAAAJAAIJrxnalgCVAAAlAAEJrx5ZAwBfAAAuAAQKf0YABAkACQljIvkkAEsCAAkABwkaIfkkAEsCABgABAnUGnIuAAIBACUAAwnQIDAWANEAAAEuAAUUBQkNAAgA3RcA.',
Ol='Oldshotz:BAABLgAECn8hAAIPAAcJ3hflSQDEAQAPAAcJ3hflSQDEAQAAAA==.',
Om='Omgsteak:BAABLgAECn8iAAMUAAYJJgIfQQBrAAAUAAYJYQEfQQBrAAACAAMJZwIGcgA9AAAAAA==.',
On='Onapalehorse:BAAALgAECgQJBAAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJBAAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAIAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8qAAIUAAUJdiY5CAC0AQAUAAUJdiY5CAC0AQAuAAQKf5MABBQACQnRJj4AAIkDABQACQnIJj4AAIkDAAMACQlpJO4BAFsDAAIACQmuImgCACUDAAAA.Parsnip:BAAALgAFFAIJAwAAAA==.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAwAAAA==.Prayforme:BAABLgAECn8sAAMgAAkJuR4nBgAgAwAgAAkJuR4nBgAgAwAFAAUJ3RTKOQAsAQAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prilas:BAAALgADCgEJAQAAAA==.Prise:BAACLgAFFH8QAAQJAAQJ7BEtWAAXAQAJAAQJ7BEtWAAXAQAlAAEJfgoEJwBIAAAYAAEJvQCMLQAlAAAuAAQKfxgAAxgACQlDDgQbAHUBABgABwm+EAQbAHUBAAkACAm8C9+yAOAAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMcAAkJdQmpSQBbAQAcAAkJdQmpSQBbAQAZAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAFFAIJAwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8GAAIBAAIJWwftWgBmAAABAAIJWwftWgBmAAAuAAQKfx8AAwEACQlFGKEdAOoBAAEACQlFGKEdAOoBABMAAwn+BPUyAH4AAAAA.Ralthas:BAABLgAECn8cAAQhAAgJjBGbMQDkAAAhAAQJWhqbMQDkAAAmAAMJ+wxANACNAAAiAAIJhQPCzAA4AAABLgAECgkJMAASAKcVAA==.Ramenshaman:BAAALgAFFAEJAgAAAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0w83TwBqAQAUAAYJOxQ4KwDdAAAAAA==.Ravenoth:BAAALgAECgIJAwAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgQJBgAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8kAAMIAAgJRAvPygD6AAAIAAUJIQ7PygD6AAAnAAcJPgb8JADgAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8lAAILAAgJGR5WKwBTAgALAAgJGR5WKwBTAgAAAA==.Riftstalker:BAABLgAECn8XAAMOAAcJCBdwEAC9AQAOAAcJCBdwEAC9AQAPAAEJ+w0f0QA1AAAAAA==.Rimreaper:BAAALgAECgQJBQABLgAECgUJCQAHAAAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIJAAMJ/BBJewDNAAAJAAMJ/BBJewDNAAAuAAQKfycAAwkACQmmHgkuACACAAkACQmmHgkuACACABgAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJDQAAAA==.Roosevelt:BAAALgAECgEJAQAAAA==.',
Ru='Rushem:BAABLgAECn8WAAIDAAkJMRTOJADPAQADAAkJMRTOJADPAQAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAILAAgJzxYbegCQAQALAAgJzxYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8YAAImAAgJUw2OGQBCAQAmAAgJUw2OGQBCAQAAAA==.Samitsu:BAAALgAECgEJAgAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgATAAEJ+RJXPAA8AAASAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgMJAwABLgAFFAUJEQAgAIgWAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJBAAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8pAAMMAAgJ3wWnDgC5AAAMAAQJ3ginDgC5AAALAAgJaQNw+gCzAAAAAA==.Seliona:BAAALgADCgEJAQABLgAECgcJGAAZAFIKAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8oAAIgAAYJeyMxEQBgAgAgAAYJeyMxEQBgAgAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8SAAMVAAQJWxFiJAD+AAAVAAQJWxFiJAD+AAAnAAIJIAT/FQBLAAAuAAQKfy4AAycACQmQFboSAJ8BACcACAnpE7oSAJ8BABUABQliFdxGACQBAAAA.Sevinofnine:BAAALgAECgUJDwAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shamanigans:BAAALgADCgYJBwAAAA==.Shamantics:BAAALgADCgcJBwABLgAECggJCwAHAAAAAA==.Shanic:BAABLgAECn8bAAIjAAkJPBZQGQACAgAjAAkJPBZQGQACAgAAAA==.Sharlan:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.Shi:BAAALgAECgUJCAAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.Shinnylock:BAAALgADCgMJAwAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAwAAAA==.Siheal:BAAALgAECgYJBgAAAA==.',
Sl='Slaveman:BAAALgAECgMJBAAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIOAAgJaA1bEgCdAQAOAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgAECgEJAQAAAA==.Smogy:BAAALgAFFAEJAQAAAA==.',
Sn='Snacksized:BAAALgADCgkJDAAAAA==.Snipycholo:BAABLgAFFH8HAAIPAAUJORxkFADAAQAPAAUJORxkFADAAQAAAA==.Snipymagus:BAABLgAFFH8FAAIKAAUJMA8kZgAXAQAKAAUJMA8kZgAXAQAAAA==.Snipyterror:BAAALgAFFAEJAQAAAA==.Snoodly:BAABLgAECn8YAAIWAAkJvw+qLgDCAQAWAAkJvw+qLgDCAQAAAA==.Snuu:BAAALgAECgEJAQAAAA==.',
So='Solarice:BAACLgAFFH8OAAIKAAQJKB/nPgBzAQAKAAQJKB/nPgBzAQAuAAQKfyEAAwoACQlXHoweAKYCAAoACQkkHoweAKYCAB8AAQnmIGQZAEwAAAAA.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIJAAkJvQu0XgCDAQAJAAkJvQu0XgCDAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8OAAIdAAQJeguTUwDzAAAdAAQJeguTUwDzAAAuAAQKfxkAAh0ACQnaEyZLAMgBAB0ACQnaEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIUAAQJzgsZIQCPAAAUAAQJzgsZIQCPAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAUAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8lAAILAAkJqxvHLQBIAgALAAkJqxvHLQBIAgAAAA==.Stinksauce:BAACLgAFFH8WAAMSAAQJNR9KFABRAQASAAQJNR9KFABRAQABAAQJ4xISLQAQAQAuAAQKfxwABBIACQkHGm4NAGACABIACQkHGm4NAGACABMAAgn3FSocAGsAAAEAAgnKD8iGAE8AAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.Strokntotem:BAAALgAECgMJBgAAAA==.',
Su='Supabox:BAAALgAFFAEJAQABLgAFFAYJFgARAHojAA==.Superchunk:BAAALgAECgIJAwAAAA==.Supergotenks:BAAALgADCgIJAgAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8gAAIEAAkJLw1JKACEAQAEAAkJLw1JKACEAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8yAAMVAAkJaBgpGABHAgAVAAkJaBgpGABHAgAIAAEJAADt2QEAAAAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIRAAcJkRlpIQCdAQARAAcJkRlpIQCdAQAAAA==.',
Ta='Talgulen:BAABLgAECn81AAITAAkJrh2sAgCNAgATAAkJrh2sAgCNAgAAAA==.Tankytauren:BAABLgAECn82AAMMAAkJrRYrBwAoAgAMAAkJrRYrBwAoAgALAAgJFRI6cgB/AQAAAA==.Tarquinius:BAABLgAECn80AAIQAAkJbRK7FgDRAQAQAAkJbRK7FgDRAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJQwADAJclAA==.Taylorswifft:BAAALgAECgcJDwAAAA==.Taynte:BAABLgAFFH8HAAIlAAMJLREwCQDmAAAlAAMJLREwCQDmAAAAAA==.',
Te='Telanastre:BAAALgAECgQJCwABLgAECgYJCAAHAAAAAA==.',
Th='Tharos:BAAALgAECgUJBgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAQJEwAXAKoUAA==.Thibbledor:BAAALgADCgkJFAABLgAECggJGwAZAAoTAA==.',
Ti='Tifferny:BAABLgAECn8VAAIIAAcJexA1mgBBAQAIAAcJexA1mgBBAQAAAA==.Tiffèrny:BAAALgAFFAIJAwAAAA==.Tinydrunk:BAAALgAECgMJAwAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMjAAgJIBRaLQCZAQAjAAcJkxNaLQCZAQAiAAgJ+Q9/TwBRAQAAAA==.Tonkatruck:BAAALgAECggJCgAAAA==.Totemlycool:BAABLgAECn8hAAQZAAgJGxWwIAAKAgAZAAgJCRSwIAAKAgAkAAYJlRcEEgCWAQAcAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAABLgAECn8aAAIPAAgJthkOKgA2AgAPAAgJthkOKgA2AgABLgAECgkJTAAiAGocAA==.Treehuggër:BAACLgAFFH8FAAIiAAIJkA/WVwBqAAAiAAIJkA/WVwBqAAAuAAQKfxsAAiIACQnhGBYWAJgCACIACQnhGBYWAJgCAAAA.Trisection:BAAALgAECgYJBgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQAYAJUaAA==.Tryael:BAAALgAECgMJAwAAAA==.Tryrah:BAABLgAFFH8VAAIjAAcJbBZ5DgC4AQAjAAcJbBZ5DgC4AQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAACLgAFFH8LAAIdAAQJMQbqWwDcAAAdAAQJMQbqWwDcAAAuAAQKfyIAAh0ACQliEvxVAIUBAB0ACQliEvxVAIUBAAAA.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAACLgAFFH8KAAIDAAQJ2Q7NJQAdAQADAAQJ2Q7NJQAdAQAuAAQKfxcAAwMACAmzGEc+AKsBAAMABwniGEc+AKsBAAIABAmhFYg6ANsAAAAA.',
['Tö']='Töömis:BAABLgAECn8ZAAIIAAcJkxOFfACBAQAIAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAACLgAFFH8FAAIDAAIJeRKRQwCTAAADAAIJeRKRQwCTAAAuAAQKfzkAAgMACQkHINANAJICAAMACQkHINANAJICAAAA.',
Um='Umbreon:BAAALgAECgcJCQAAAA==.',
Ur='Urza:BAAALgADCgYJJQAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAImAAkJEQ5gEgCVAQAmAAkJEQ5gEgCVAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8kAAIIAAgJGg4YnQA8AQAIAAgJGg4YnQA8AQAAAA==.',
Vo='Volsunga:BAABLgAECn8WAAIiAAYJBQSojgCYAAAiAAYJBQSojgCYAAAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgAECgMJAwAAAA==.',
Wo='Wow:BAAALgAECgUJCAAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Wu='Wurly:BAAALgAECgEJAQAAAA==.',
Xa='Xam:BAAALgAECgcJEwAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8xAAIJAAkJaRggIwBUAgAJAAkJaRggIwBUAgAAAA==.',
Xy='Xylazel:BAACLgAFFH8IAAILAAMJSBQPmwDaAAALAAMJSBQPmwDaAAAuAAQKf0IAAgsACQmnG3seAJECAAsACQmnG3seAJECAAAA.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8lAAMVAAYJJx0XIwDsAQAVAAYJJx0XIwDsAQAIAAMJjxb86wDPAAAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicùszùl:BAAALgADCgMJAwAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.Zugszy:BAAALgAECgEJAQAAAA==.Zultal:BAABLgAECn8WAAILAAcJORAGhQBaAQALAAcJORAGhQBaAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8sAAIjAAgJAyLQAABMAgAjAAgJAyLQAABMAgAuAAQKfx8AAiMACAnEJZcNAMECACMACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAgJLAAjAAMiAA==.Zzephyrfury:BAABLgAFFH8GAAIDAAQJsxdjGABSAQADAAQJsxdjGABSAQABLgAFFAgJLAAjAAMiAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAgJLAAjAAMiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIiAAgJORztHABfAgAiAAgJORztHABfAgAAAA==.',
['Ôä']='Ôäk:BAAALgAECgMJAwABLgAECgkJOgAiAO8QAA==.',
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
