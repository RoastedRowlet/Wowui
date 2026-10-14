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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','DeathKnight-Blood','Priest-Shadow','Unknown-Unknown','Warrior-Fury','Warlock-Destruction','Paladin-Retribution','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Rogue-Outlaw','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Vengeance','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Devourer',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn8qAAIBAAkKMiUEAQDHAwABAAkKMiUEAQDHAwAAAA==.',
Ae='Aezu:BAACNQAFFH8SAAICAAUKexY/CwC3AQACAAUKexY/CwC3AQA1AAQKfycAAwIACQrDICUXAAwDAAIACQrDICUXAAwDAAMAAwpfEU9WAKoAAAAA.',
Ai='Ailuria:BAABNQAECn8eAAIEAAgKwiRJBQBLAwAEAAgKwiRJBQBLAwAAAA==.Aitharen:BAAANQAECgIIAwAAAA==.',
Al='Alikith:BAABNQAECn8eAAIFAAgKgRCAJQCwAQAFAAgKgRCAJQCwAQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alun:BAAANQADCgYIBgAAAA==.Alyas:BAAANQAECgUIBgAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn8kAAMGAAgKRQ1G4QDDAQAGAAgKmQlG4QDDAQAHAAMKfBZNKQCpAAAAAA==.Amelía:BAABNQAECn8bAAMIAAkK/BZsYgDjAQAIAAgKMRVsYgDjAQAJAAQKkRR73QDWAAAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amulet:BAAANQABCgUICQAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgkJGwAIAPwWAA==.',
An='Angando:BAABNQAECn8eAAMKAAcKsAsWxgBnAQAKAAcK4QkWxgBnAQALAAEKywxZQgA0AAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgUIBgAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arnarn:BAAANQAECgYICgAAAA==.Artemidoros:BAABNQAECn8fAAIMAAcKQCTKMgDSAgAMAAcKQCTKMgDSAgAAAA==.',
As='Asuná:BAAANQAECgYIEAAAAA==.',
Au='Augtism:BAABNQAECn8iAAMNAAkKdAuMFwDOAQANAAkKNQqMFwDOAQAOAAMKKQZVHACBAAAAAA==.',
Av='Avataroffire:BAAANQAECgYIEwAAAA==.',
Aw='Awakened:BAAANQADCgcJAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8QAAIHAAUKohErAQB3AQAHAAUKohErAQB3AQA1AAQKfyQAAgcACQpiGW8IAFYCAAcACQpiGW8IAFYCAAAA.',
Be='Beefbrownie:BAABNQAECn8cAAILAAgK1xvFCwB6AgALAAgK1xvFCwB6AgAAAA==.Bellezora:BAABNQAECn8fAAIPAAcKNyGsOQB/AgAPAAcKNiGsOQB/AgAAAA==.Bellwynn:BAABNQAECn8ZAAICAAgKGxq4MwBFAgACAAgKGxq4MwBFAgAAAA==.Berzerked:BAABNQAECn9CAAIKAAkKzSUrBADVAwAKAAkKzSUrBADVAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.Bigjimslade:BAAANQAECgQIBAABNQAECgkJMgAMAF0fAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn8rAAIQAAkKEh2JGQDfAgAQAAkKEh2JGQDfAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIAgAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh27CwBKAgABAAgKHh27CwBKAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCggICwAAAA==.Bus:BAABNQAECn8XAAIBAAkK5SYLAAAZBAABAAkK5SYLAAAZBAABNQAFFAcIFQAQABkhAA==.',
Ca='Camholy:BAABNQAECn8fAAIRAAcKuAl3NwBlAQARAAcKuAl3NwBlAQAAAA==.Castrial:BAAANQADCgIIAgAAAA==.',
Ce='Celtykun:BAAANQAECgUIBwAAAA==.',
Ch='Chiron:BAAANQADCggIFwABNQAECgYIEQASAAAAAA==.',
Co='Connie:BAAANQAECgUIDAAAAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgQIBAAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAAANQAECgUICQAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.',
Dh='Dhing:BAAANQAECgcIEwAAAA==.',
Di='Dillexis:BAABNQAECn8rAAMKAAkKgRjKWwB2AgAKAAkK/RfKWwB2AgATAAQKshjdGQACAQAAAA==.Dismagey:BAAANQAECgcICwAAAA==.',
Do='Donald:BAABNQAECn8gAAICAAgK3hT1PwD4AQACAAgK3hT1PwD4AQAAAA==.Doomslash:BAABNQAECn8fAAIKAAgKQA5wnADRAQAKAAgKQA5wnADRAQAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQADCggIGAABNQAECggIHAADAGolAA==.Dragonchest:BAABNQAECn8aAAIUAAgKbR84BADqAgAUAAgKbR84BADqAgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECggIGgAUAG0fAA==.Dragonswolf:BAAANQAECgYIDAABNQAECggIGgAUAG0fAA==.Dragonwing:BAAANQAECgMIAwABNQAECggIGgAUAG0fAA==.Drbubblesmd:BAAANQAECgQICAAAAA==.Dregon:BAACNQAFFH8SAAIEAAUKdyXtAQAhAgAEAAUKdyXtAQAhAgA1AAQKfycAAgQACQq2JuAAANADAAQACQq2JuAAANADAAAA.Dreinara:BAAANQAECgMIBAAAAA==.',
Du='Dummysezwhut:BAAANQAECgUIBwAAAA==.',
Ea='Eastofeden:BAAANQAECgUIDQAAAA==.',
Ec='Echinopsis:BAAANQAECgMIBwAAAA==.',
Ei='Eiduartkay:BAAANQAECgYICwAAAA==.Eight:BAAANQAECgQIBAAAAA==.Eilyn:BAABNQAECn8aAAIVAAcKBQ2m0QByAQAVAAcKBQ2m0QByAQAAAA==.',
El='Elffaba:BAAANQADCgIIBAABNQADCgUIDwASAAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAAANQAECgYIEwAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Fazlain:BAAANQAECgUIDQAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgEIAQABNQAECgYIEQASAAAAAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fr='Friartuck:BAAANQAECgMIAwABNQAECgkJMgAMAF0fAA==.',
Fu='Furryem:BAABNQAECn8cAAIDAAgKaiW4BgBWAwADAAgKaiW4BgBWAwAAAA==.',
['Fô']='Fôxx:BAAANQAECgYIBwAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn8sAAMVAAgK5RWAmwDnAQAVAAgK5RWAmwDnAQAWAAIKbQMGDAFYAAAAAA==.Gatelinka:BAAANQAECgQIBAABNQAECgcIGAAIABchAA==.Gateto:BAABNQAECn8YAAMIAAcKFyF+OQB2AgAIAAcKFyF+OQB2AgAJAAQKEAjB4ADQAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwASAAAAAA==.',
Gl='Glynistann:BAAANQAECgQIBgAAAA==.',
Gu='Gundox:BAAANQAECgUIBgAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hamishtok:BAAANQABCggIEAAAAA==.Hanoa:BAAANQAECgUICAAAAA==.Hartley:BAAANQADCgEIAQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAAANQAECgYIEwAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn8mAAIMAAgK2RSxaQA+AgAMAAgK2RSxaQA+AgAAAA==.',
Hy='Hyacaina:BAAANQABCgUICQAAAA==.',
Ik='Ikickgnômes:BAAANQAECgYICwAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgkJKgAGACweAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECn8hAAQUAAkKyiIcBQDLAgAUAAcK+CMcBQDLAgAXAAUKoB5JoQCOAQAYAAEK/xTtLQA5AAAAAA==.',
Iv='Ivon:BAAANQADCgYIDAABNQAECgkJKwAKAIEYAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8PAAMZAAUKXxmlDgD5AAAZAAMKXxmlDgD5AAAaAAMKTBX6AQDlAAA1AAQKfyIAAxkACQqgHuQcAJMCABkACAo3H+QcAJMCABoACQoXG7cFAIYCAAAA.',
Ji='Jickle:BAAANQADCggJEwAAAA==.',
Jo='Joppa:BAAANQADCgMIBAABNQAFFAcIFwARABESAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgQIBQAAAA==.',
Ke='Keý:BAACNQAFFH8SAAIKAAUKpx+qDQDSAQAKAAUKpx+qDQDSAQA1AAQKfyQAAgoACQr5Ies1AOgCAAoACQr5Ies1AOgCAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAAANQAECgUIDAAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCggIDAAAAA==.Kiy:BAABNQAECn8bAAIXAAcKvhRjjADDAQAXAAcKvhRjjADDAQAAAA==.',
Kn='Knìghtmare:BAAANQADCgYIDAAAAA==.',
Kr='Krakenlock:BAABNQAECn8eAAIXAAgKAQeDtABhAQAXAAgKAQeDtABhAQAAAA==.Krenin:BAAANQADCgEIAQAAAA==.Kronas:BAAANQADCgcIFQAAAA==.',
Ku='Kumojoru:BAACNQAFFH8SAAIbAAUK9BvbAQCWAQAbAAUK9BvbAQCWAQA1AAQKfysABBsACQraI68DAHgDABsACQraI68DAHgDABwAAwp4HbkgAAsBAAIAAQrcA5S9ACIAAAAA.',
Ky='Kyranos:BAAANQADCggIFQAAAA==.',
La='Lazyheal:BAAANQAECgIIAgABNQAECgkJIwAIAOYcAA==.',
Le='Leigor:BAACNQAFFH8SAAIPAAUKWRp7DAC+AQAPAAUKWRp7DAC+AQA1AAQKfycAAg8ACQpWIckfAO4CAA8ACQpWIckfAO4CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Linthsong:BAAANQAECgUICQABNQAECggIHgAPAN0OAA==.Lionature:BAAANQADCgcIFQAAAA==.Lionknite:BAABNQAECn8mAAMdAAgKARulQAAXAgAdAAgKARulQAAXAgAeAAEKAAAhrwAtAAAAAA==.Liteshocklet:BAABNQAECn8jAAIIAAkK5hyYKAC/AgAIAAkK5hyYKAC/AgAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
Lu='Lumiann:BAABNQAECn8nAAIKAAkKTiIAHQBCAwAKAAkKTiIAHQBCAwAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8hAAMDAAgKJA/vLgCfAQADAAgKJA/vLgCfAQACAAYKqALFhQC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMEAAcKshy1GwDEAQAEAAYKyBu1GwDEAQAfAAIK8wAhZQBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQAECgEIAQABNQAECggIGQAgAEwUAA==.Mauzii:BAAANQADCgMIBAABNQAECggIGQAgAEwUAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn8gAAIdAAkKCSE8EgAkAwAdAAkKCSE8EgAkAwAAAA==.',
Me='Melliah:BAAANQAECgUIBgAAAA==.Mes:BAABNQAECn8bAAIJAAcKHR0ARwBXAgAJAAcKHR0ARwBXAgAAAA==.Metatrøn:BAAANQADCggIDwAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgkJKgABADIlAA==.Mimmi:BAAANQAECgUIEAABNQAECggIGQAgAEwUAA==.Misaligned:BAAANQAECgYIDgAAAA==.Misidian:BAAANQADCgQJBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgkJHwAGAJ0WAA==.Moonsorrow:BAAANQAECggIDwAAAA==.Moritura:BAABNQAECn8ZAAIgAAgKTBQZNwDzAQAgAAgKTBQZNwDzAQAAAA==.',
My='Mywifesaidno:BAAANQADCgYIDQAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAYIEAARAPYVAA==.Nemistrasza:BAAANQADCggICwABNQAECggIHgAEAMIkAA==.',
Ni='Nilanza:BAAANQADCgcIBwABNQAECgkJJwAKAE4iAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQADCggIDAAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAASAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAZAEsVAA==.',
Ob='Obergefel:BAAANQAECgQIBQAAAA==.',
Ol='Ollie:BAAANQABCgYIDAAAAA==.',
Op='Ophiuchus:BAAANQAECgYIEQAAAA==.',
Or='Orcdung:BAAANQABCgUIDAAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAAANQAECgYIDQAAAA==.Pamelina:BAAANQABCgEIAQAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgkJKwAKAIEYAA==.Pandunkadunk:BAAANQADCgYIBgAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8UAAMTAAYKJx36FQA4AQAKAAYKRxk1oQDFAQATAAMKciP6FQA4AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggIHAAAAA==.Pernicious:BAAANQAECgYIDQAAAA==.',
Ph='Phillis:BAAANQADCgUIBQAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAEANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAAANQAECgYIEAAAAA==.Pinkiemena:BAAANQAFFAEIAQAAAA==.Piolin:BAAANQAECgQIBAAAAA==.',
Po='Potent:BAAANQABCgMIAwAAAA==.',
Pu='Punchykicky:BAAANQAECgQIBwABNQAECggILgAFAGsdAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8bAAQPAAkKSAY5kABhAQAPAAgKKQY5kABhAQARAAYKtgXCRwD7AAAhAAEKVQHjMwANAAAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAAANQAECgYIEwAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reniel:BAAANQADCgMIAwABNQAECggIHgAFAIEQAA==.Reverendlion:BAAANQAECgUICgAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAABNQAECn8UAAIKAAYK2BnAoQDEAQAKAAYK2BnAoQDEAQAAAA==.Rosencrant:BAAANQAECgUIEAAAAA==.',
Ru='Rule:BAAANQAECgQIBgAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgkJJAAVACMZAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECn8mAAIiAAgKkRwACAB6AgAiAAgKkRwACAB6AgAAAA==.Sainthealz:BAAANQABCgQIBgAAAA==.Sampal:BAABNQAECn8uAAIFAAgKax1CDwCmAgAFAAgKax1CDwCmAgAAAA==.Samwield:BAEBNQAECn80AAMjAAkK4R1nCwC9AgAjAAgKQh9nCwC9AgAZAAMK6xQ6dgDQAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgEIAQABNQAECgkJNAAkAJ8lAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn8gAAIIAAgKQBe8VAARAgAIAAgKQBe8VAARAgAAAA==.Selaheal:BAABNQAECn8mAAIRAAgKug+LKADhAQARAAgKug+LKADhAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgkJIQAFAMQdAA==.Shinobu:BAAANQADCgYICgABNQAECggIGQACABsaAA==.Shintó:BAAANQADCgEIAQAAAA==.Shnood:BAAANQAECgYIDgAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCgcICQAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn8wAAMlAAkKyyBXCQBBAwAlAAkKyyBXCQBBAwAiAAEKAgEdOgAUAAAAAA==.',
Sk='Skies:BAAANQADCgYIBgABNQAFFAMIBQAaAPEMAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECggIHAADAGolAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgkJIwAJAGQaAA==.Sterïzard:BAAANQADCgEIAQABNQAECgkJIwAJAGQaAA==.Stupid:BAABNQAECn8tAAIWAAkKfSAvEgA8AwAWAAkKfSAvEgA8AwAAAA==.Stærk:BAABNQAECn8jAAIJAAkKZBpMOACSAgAJAAkKZBpMOACSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgkJKgAGACweAA==.Sunpally:BAABNQAECn8fAAIWAAcKBhLHfgCaAQAWAAcKBhLHfgCaAQAAAA==.Suvulaan:BAAANQAECgUIEAAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tatoo:BAABNQAECn8yAAIMAAkKXR8TEABjAwAMAAkKXR8TEABjAwAAAA==.',
Te='Teeice:BAABNQAECn8nAAIZAAkKSxlSIAB7AgAZAAkKSxlSIAB7AgAAAA==.Teo:BAABNQAECn8fAAIRAAcKEhDSLwChAQARAAcKEhDSLwChAQAAAA==.',
Th='Thekan:BAAANQAECgYIEwAAAA==.Theriot:BAABNQAECn8hAAMFAAkKxB0CDgC4AgAFAAkKxB0CDgC4AgAVAAIKNhjZaAFwAAAAAA==.Thianá:BAAANQAECgQIBQAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECgcIHwAPADchAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Toosus:BAACNQAFFH8SAAIQAAUK1B+UCgCpAQAQAAUK1B+UCgCpAQA1AAQKfykAAhAACQqXJKoKAF4DABAACQqXJKoKAF4DAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trolldung:BAAANQADCgQIBwAAAA==.',
Tt='Tturtle:BAACNQAFFH8LAAIVAAUKywx7DgBfAQAVAAUKywx7DgBfAQA1AAQKfycAAhUACQrVGqJkAGkCABUACQrVGqJkAGkCAAAA.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAAANQAECgUIBwAAAA==.',
Un='Unclebuck:BAAANQABCgYIDgAAAA==.Unholysam:BAEANQAECgEIAQABNQAECgkJNAAjAOEdAA==.',
Va='Vallo:BAAANQADCgEIAQAAAA==.Vampier:BAAANQAECgEIAQAAAA==.',
Ve='Velata:BAABNQAECn8pAAIHAAkK9BDqCABIAgAHAAkK9BDqCABIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Violencê:BAABNQAECn8iAAITAAgKHR72BQCzAgATAAgKHR72BQCzAgAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAAANQAECgIIAwAAAA==.',
We='Wes:BAABNQAECn8dAAIZAAcKwBBEQQDAAQAZAAcKwBBEQQDAAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn8lAAIMAAkKmRozMgDTAgAMAAkKmRozMgDTAgAAAA==.Willybcastin:BAAANQAECggIEgABNQAFFAYIEAAdALEcAA==.Willybwankin:BAACNQAFFH8QAAIdAAYKsRxXAgAjAgAdAAYKsRxXAgAjAgA1AAQKfy8AAh0ACQrjJpQDALoDAB0ACQrjJpQDALoDAAAA.',
Wo='Wowgazm:BAAANQAECgYIEQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8ZAAMXAAgKkgsnoQCOAQAXAAgKkgsnoQCOAQAYAAEKAABPLgA5AAAAAA==.',
Xa='Xanstar:BAAANQADCgQIBAAAAA==.',
Xe='Xerath:BAAANQAECgEIAQAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgQIBQAAAA==.Zalarian:BAABNQAECn8qAAIVAAkK4iEHGwBWAwAVAAkK4iEHGwBWAwAAAA==.',
Ze='Zemos:BAAANQADCgYIDQAAAA==.Zeseroth:BAAANQAECgEIAQAAAA==.Zeserotho:BAACNQAFFH8SAAIfAAUK4xrgBQCxAQAfAAUK4xrgBQCxAQA1AAQKfyYAAh8ACQotIXITALoCAB8ACQotIXITALoCAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn8uAAMFAAkKAxk3GQApAgAFAAgKihk3GQApAgAWAAgKeBD4YgDsAQABNQAECgkJMAAlAMsgAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgEIAQAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8YAAIJAAgKPx2sNgCZAgAJAAgKPx2sNgCZAgAAAA==.',
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
