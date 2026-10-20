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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','DeathKnight-Blood','Paladin-Holy','Priest-Shadow','Warlock-Demonology','DeathKnight-Frost','Warrior-Fury','Warlock-Destruction','Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','Rogue-Assassination','Rogue-Outlaw','Druid-Feral','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Devourer',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn8xAAIBAAoKLyMKAQDHAwABAAoKLyMKAQDHAwAAAA==.',
Ae='Aezu:BAACNQAFFH8XAAICAAYKTBPuAwA/AQACAAYKTBPuAwA/AQA1AAQKfyoABAIACgoAIGgXAAwDAAIACgoAIGgXAAwDAAMAAwpfEXdXAKoAAAQAAQr9G+MrAF4AAAAA.',
Ai='Ailuria:BAABNQAECn8lAAIFAAkKqySCAQCvAgAFAAkKqySCAQCvAgAAAA==.Aitharen:BAAANQAECgQIBAAAAA==.',
Al='Alikith:BAABNQAECn8mAAIGAAkKxQ/YDAA1AQAGAAkKxQ/YDAA1AQAAAA==.Altheyra:BAAANQADCgYIEQAAAA==.Alun:BAAANQADCgYIBgAAAA==.Alyas:BAAANQAECgQICAAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn8sAAMHAAkK0g2vLABqAQAHAAkKrQqvLABqAQAIAAMKfBbKKQCpAAAAAA==.Amelía:BAABNQAECn8fAAMJAAoKoxmgJQBNAQAJAAkKVhigJQBNAQAKAAQKkRQG4ADWAAAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQADCgEIAQAAAA==.Amulet:BAAANQAECgEIAQAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgoKHwAJAKMZAA==.',
An='Angando:BAABNQAECn8gAAMLAAgKIgtXyABnAQALAAgKoAlXyABnAQAMAAEKywxOQwA0AAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgQICAAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arihan:BAAANQAECgYIBwAAAA==.Arnarn:BAAANQAECggIDgAAAA==.Arrows:BAAANQADCgEIAgAAAA==.Artemidoros:BAABNQAECn8lAAINAAcKQCRCFQDKAQANAAcKQCRCFQDKAQAAAA==.',
As='Asuná:BAAANQAECgcIEwAAAA==.',
Au='Augtism:BAABNQAECn8mAAMOAAoKwAq0FwDOAQAOAAoKqAm0FwDOAQAPAAMKKQatHACBAAAAAA==.',
Av='Avataroffire:BAABNQAECn8YAAMHAAcKcRiK/QCSAQAHAAYKpBiK/QCSAQAIAAIKPRWnLwCCAAAAAA==.Avva:BAAANQADCgEIAQAAAA==.',
Aw='Awakened:BAAANQADCgcJAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8VAAIIAAYKDBN0AAAeAQAIAAYKDBN0AAAeAQA1AAQKfycAAggACgrAGI4IAFYCAAgACgrAGI4IAFYCAAAA.',
Be='Beefbrownie:BAABNQAECn8jAAIMAAgK1xvvBQBjAQAMAAgK1xvvBQBjAQAAAA==.Beejthepally:BAAANQADCgEIAwAAAA==.Bellezora:BAABNQAECn8hAAIQAAgKEyGtOgB+AgAQAAgKEyGtOgB+AgAAAA==.Bellwynn:BAABNQAECn8cAAICAAkKxxhANABFAgACAAkKxxhANABFAgAAAA==.Berzerked:BAABNQAECn9HAAILAAoKJyRaBADUAwALAAoKJyRaBADUAwAAAA==.',
Bi='Biggmean:BAAANQADCggICQAAAA==.Bigjimslade:BAAANQAECgQIBwABNQAECgoKNwANAAUfAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn8vAAIRAAoKIBzUGQDfAgARAAoKIBzUGQDfAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIAwAAAA==.Brasa:BAAANQAECgEIAQAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh3gCwBJAgABAAgKHh3gCwBJAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCggIEgAAAA==.Bus:BAACNQAFFH8GAAIBAAYKLCYwAADRAQABAAYKLCYwAADRAQA1AAQKfxgAAgEACgqkJgwAABgEAAEACgqkJgwAABgEAAAA.',
Ca='Caishen:BAAANQADCgEIAQAAAA==.Calnaultenjr:BAAANQADCgEIAQABNQAECgoKNQASAOcZAA==.Camholy:BAABNQAECn8lAAITAAcKwQmiEwDuAAATAAcKwQmiEwDuAAAAAA==.Camogie:BAAANQADCgEIAQAAAA==.Castrial:BAAANQADCgIIAgAAAA==.',
Ce='Celtykun:BAAANQAECgUICwAAAA==.',
Ch='Chainmalejr:BAAANQADCgEIAQABNQAECgoKLgAHALMdAA==.Chiron:BAAANQADCggIFwABNQAECggIFQAUALoVAA==.Chiyukii:BAAANQAECggIBwAAAA==.',
Co='Connie:BAAANQAECgUIDQAAAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgQIBAAAAA==.Dapur:BAAANQADCgMIBQAAAA==.Darksteldt:BAAANQAECgUIDAAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBwAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Demonickills:BAAANQAECgEIAQAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.Derik:BAAANQADCgEIAQABNQAECgoKLwALAK0WAA==.',
Dh='Dhing:BAABNQAECn8ZAAIVAAkK+gp/SQCWAQAVAAkK+gp/SQCWAQAAAA==.',
Di='Dillexis:BAABNQAECn8vAAMLAAoKrRa8XAB2AgALAAoKORa8XAB2AgAWAAQKshgaGgACAQAAAA==.Dismagey:BAAANQAECggIDQAAAA==.',
Do='Donald:BAABNQAECn8pAAICAAoKRBJaBgDUAQACAAoKRBJaBgDUAQAAAA==.Doomslash:BAABNQAECn8pAAILAAoKuA4tDwDfAQALAAoKuA4tDwDfAQAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQADCggIGAABNQAECggIIwADAGolAA==.Dragonchest:BAABNQAECn8iAAIXAAkKdh5tAAA9AgAXAAkKdh5tAAA9AgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECgkJIgAXAHYeAA==.Dragonswolf:BAAANQAECgYIDQABNQAECgkJIgAXAHYeAA==.Dragonwing:BAAANQAECgMIAwABNQAECgkJIgAXAHYeAA==.Drbubblesmd:BAAANQAECgUIDQAAAA==.Dregon:BAACNQAFFH8XAAIFAAYKjCS0AAAJAgAFAAYKjCS0AAAJAgA1AAQKfyoAAgUACgqlJukAANADAAUACgqlJukAANADAAAA.Dreinara:BAAANQAECgMIBQAAAA==.',
Du='Dummysezwhut:BAAANQAECgUICQAAAA==.',
Ea='Eastofeden:BAABNQAECn8WAAIUAAgK+hLjFACjAQAUAAgK+hLjFACjAQAAAA==.',
Ec='Echinopsis:BAAANQAECgMIBwAAAA==.',
Ei='Eiduartkay:BAAANQAECgcIDAAAAA==.Eight:BAAANQAECgQIBQAAAA==.Eilyn:BAABNQAECn8iAAIYAAgKaQ39RQA5AQAYAAgKaQ39RQA5AQAAAA==.',
El='Elffaba:BAAANQADCgIIBAABNQADCgUIDwAZAAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQADCgEIAQAAAA==.',
Ep='Epicmystic:BAAANQADCgEIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAABNQAECn8WAAINAAgKhALWFQHYAAANAAgKhALWFQHYAAAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Faun:BAAANQADCgEIAQAAAA==.Fazlain:BAABNQAECn8UAAIYAAkKehS3QQBDAQAYAAkKehS3QQBDAQAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgEIAQABNQAECggIFQAUALoVAA==.Fenria:BAAANQADCgEIAQAAAA==.',
Fi='Fighter:BAAANQADCgEIAQABNQAECgkJIwAJAOYcAA==.',
Fr='Friartuck:BAAANQAECgQIBQABNQAECgoKNwANAAUfAA==.',
Fu='Furryem:BAABNQAECn8jAAIDAAgKaiXEAgCPAgADAAgKaiXEAgCPAgAAAA==.',
['Fô']='Fôxx:BAAANQAECgUICQAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn80AAMYAAkKwhXJnQDnAQAYAAkKwhXJnQDnAQASAAUKNQ19MgAZAQAAAA==.Gatelinka:BAAANQAECgUIBQABNQAECgkJGgAJAFogAA==.Gateto:BAABNQAECn8aAAMJAAkKWiBIOgB2AgAJAAkKWiBIOgB2AgAKAAQKEAht4wDQAAAAAA==.Gaulus:BAAANQADCgEIAgAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAZAAAAAA==.',
Gl='Glynistann:BAAANQAECgQICAAAAA==.',
Go='Gotyamind:BAAANQADCgEIAQABNQADCgUIBwAZAAAAAA==.',
Gu='Gundox:BAAANQAECgQICAAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hamishtok:BAAANQABCggIEAAAAA==.Hanoa:BAAANQAECgUICQAAAA==.Hartley:BAAANQADCgEIAQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAABNQAECn8eAAIXAAcKqgphIABtAQAXAAcKqgphIABtAQAAAA==.',
Ho='Holeshot:BAAANQADCgEIAQAAAA==.Holyspaunk:BAAANQADCgIIAgAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn8sAAINAAgKYxX8agA9AgANAAgKYxX8agA9AgAAAA==.',
Hy='Hyacaina:BAAANQABCgUICQAAAA==.',
Ik='Ikickgnômes:BAAANQAECgYIDwAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgoKLgAHALMdAA==.Ingrown:BAAANQADCgEIAQAAAA==.',
Ir='Irim:BAABNQAECn8nAAQXAAoKniIjBQDKAgAXAAgKJiMjBQDKAgAUAAUKaR+xPgARAQAaAAEK/xRfLgA5AAAAAA==.',
Is='Ishamael:BAAANQADCgIIAgAAAA==.',
Iv='Ivon:BAAANQADCgYIDAABNQAECgoKLwALAK0WAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8UAAMbAAUK8RoLDwD5AAAbAAMK8RoLDwD5AAAcAAMKfhkAAgDlAAA1AAQKfyMAAxsACgoIHlsdAJQCABsACQp0HlsdAJQCABwACQoXG74FAIcCAAAA.',
Ji='Jickle:BAAANQADCggJEwAAAA==.',
Jo='Joppa:BAAANQADCgQIBQABNQAFFAcIFwATABESAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgUICAAAAA==.',
Ke='Keithus:BAAANQADCgEIAQAAAA==.Keý:BAACNQAFFH8XAAILAAYKoxhkBQAuAQALAAYKoxhkBQAuAQA1AAQKfycAAgsACgqWIvQ2AOcCAAsACgqWIvQ2AOcCAAAA.',
Kh='Khadgarjr:BAAANQADCgYICgAAAA==.Khänvict:BAABNQAECn8VAAINAAYKMhuEPQA9AQANAAYKMhuEPQA9AQAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCggIDAAAAA==.Kiy:BAABNQAECn8eAAIUAAgK0xKMjgDCAQAUAAgK0xKMjgDCAQAAAA==.',
Kn='Knockout:BAAANQADCggICAAAAA==.Knìghtmare:BAAANQADCgYIDAAAAA==.',
Kr='Krakenlock:BAABNQAECn8mAAIUAAkK0gYrPgASAQAUAAkK0gYrPgASAQAAAA==.Krenin:BAAANQADCgEIAQAAAA==.Kronas:BAAANQADCggIGQAAAA==.',
Ku='Kumojoru:BAACNQAFFH8XAAIEAAYK5BypAAA3AQAEAAYK5BypAAA3AQA1AAQKfy0ABAQACgr7I7sDAHkDAAQACgr7I7sDAHkDAB0AAwp4HR0hAAwBAAIAAQrcA8O/ACIAAAAA.',
Ky='Kyranos:BAAANQADCggIFQAAAA==.',
La='Lazyheal:BAAANQAECgIIAgABNQAECgkJIwAJAOYcAA==.',
Le='Leigor:BAACNQAFFH8XAAIQAAYKXxayBgByAQAQAAYKXxayBgByAQA1AAQKfyoAAhAACgr5IWQgAO4CABAACgr5IWQgAO4CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Limbow:BAAANQAECggICQABNQAFFAcIEQALADIOAA==.Linthsong:BAAANQAECgUIDgABNQAECgkJJAAQAJ4RAA==.Lionknite:BAABNQAECn8nAAMeAAgKARtWQQAXAgAeAAgKARtWQQAXAgAVAAEKAACxsgAtAAAAAA==.Liteshocklet:BAABNQAECn8jAAIJAAkK5hwTKQC/AgAJAAkK5hwTKQC/AgAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgcIBwAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
Lu='Lumiann:BAABNQAECn8rAAILAAoKhCFoHQBCAwALAAoKhCFoHQBCAwAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8jAAMDAAgKYA9ZLwCgAQADAAgKYA9ZLwCgAQACAAYKqAIlhwC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malix:BAAANQADCgEIAQAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMFAAcKshwDHADEAQAFAAYKyBsDHADEAQAfAAIK8gDKZgBDAAAAAA==.Martinia:BAAANQADCgEIAQAAAA==.Mauzer:BAAANQAECgIIAQABNQAECgkJIQAgAGQTAA==.Mauzii:BAAANQADCgMIBAABNQAECgkJIQAgAGQTAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn8kAAIeAAoKISBoEgAkAwAeAAoKISBoEgAkAwAAAA==.',
Me='Melliah:BAAANQAECgQICAAAAA==.Mes:BAABNQAECn8bAAIKAAcKHR0LSABWAgAKAAcKHR0LSABWAgAAAA==.Metatrøn:BAAANQADCggIGQAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgoKMQABAC8jAA==.Mimmi:BAABNQAECn8cAAIJAAkKCxUXIwBZAQAJAAkKCxUXIwBZAQABNQAECgkJIQAgAGQTAA==.Misaligned:BAAANQAECgcIDgAAAA==.Misidian:BAAANQADCgQIBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgoKIQAHAHkWAA==.Moonsorrow:BAABNQAECn8ZAAIDAAoKShzeAQDiAgADAAoKShzeAQDiAgAAAA==.Moritura:BAABNQAECn8hAAMgAAkKZBMpFgA8AQAgAAkKZBMpFgA8AQAhAAIKsRApDwB6AAAAAA==.',
My='Mythicalpal:BAAANQADCgEIAQAAAA==.Mywifesaidno:BAAANQAECgQIBAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAcIEQATAH4TAA==.Nemistrasza:BAAANQADCggIDAABNQAECgkJJQAFAKskAA==.',
Ni='Nilanza:BAAANQAECgIIAgABNQAECgoKKwALAIQhAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQAECgYICAAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAAZAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAbAEsVAA==.',
Ob='Obergefel:BAAANQAECgcICwAAAA==.',
Ol='Ollie:BAAANQAECgEIAQAAAA==.',
Op='Ophiuchus:BAABNQAECn8VAAIUAAgKuhXsfgDpAQAUAAgKuhXsfgDpAQAAAA==.Oppsie:BAAANQADCgUIBQAAAA==.',
Or='Orcdung:BAAANQADCgEIAQAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAABNQAECn8UAAISAAcKuxvWDgDlAQASAAcKuxvWDgDlAQAAAA==.Pallycow:BAAANQAECgIIAgAAAA==.Pamelina:BAAANQABCgcICAAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgoKLwALAK0WAA==.Pandunkadunk:BAAANQAECgEIAQAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8WAAMWAAgKyhsxFgA5AQALAAcKjxg+owDEAQAWAAQKciMxFgA5AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggIJgAAAA==.Pernicious:BAABNQAECn8WAAMXAAgKSA4MHACNAQAXAAcKlw8MHACNAQAUAAYKiQohTgDpAAAAAA==.',
Ph='Phillis:BAAANQAECgEIAQAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAEANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAABNQAECn8bAAIUAAYKARhcSQD3AAAUAAYKARhcSQD3AAAAAA==.Pinkiemena:BAAANQAFFAEIAQAAAA==.Piolin:BAAANQAECgQIBAAAAA==.',
Po='Potent:BAAANQAECgEIAQAAAA==.',
Pr='Prometheus:BAAANQADCgEIAQABNQADCgMIAQAZAAAAAA==.',
Pu='Punchykicky:BAAANQAECgQICwABNQAECgkJNgAGAN4bAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8dAAQQAAkKVgbUkQBhAQAQAAgKOQbUkQBhAQATAAYKYAaFSAD7AAAiAAEKVQGKNAANAAAAAA==.',
Ra='Radiantfreya:BAAANQADCgEIAQAAAA==.Ralra:BAAANQADCgEIAQAAAA==.Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAABNQAECn8iAAMSAAgKZBtbFQCpAQASAAgKZBtbFQCpAQAYAAEKAABXsAEvAAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reniel:BAAANQADCgMIBAABNQAECgkJJgAGAMUPAA==.Reverendlion:BAAANQAECgYICwAAAA==.',
Rh='Rhattice:BAAANQADCgEIAQAAAA==.',
Ro='Rogosh:BAABNQAECn8YAAILAAcKWhnhVQDvAAALAAcKWhnhVQDvAAAAAA==.Rosencrant:BAABNQAECn8UAAINAAYKbwlHiQCZAAANAAYKbwlHiQCZAAAAAA==.',
Ru='Rubberdukkie:BAAANQAECgIIAgAAAA==.Rule:BAAANQAECgQICAAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgoKLQAYAAkXAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.Rèstø:BAAANQADCgEIAQAAAA==.',
Sa='Saiko:BAABNQAECn8qAAIhAAkKZBobCAB6AgAhAAkKZBobCAB6AgAAAA==.Sampal:BAABNQAECn82AAIGAAkK3htWBQCuAQAGAAkK3htWBQCuAQAAAA==.Samwield:BAEBNQAECn86AAMjAAoKOxyFCwC8AgAjAAoKJRyFCwC8AgAbAAMK6xRReADRAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgMIBQABNQAECgoKOAAkAJQlAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn8hAAIJAAkK2RXEVQARAgAJAAkK2RXEVQARAgAAAA==.Selaheal:BAABNQAECn8tAAITAAgKShC+DQAqAQATAAgKShC+DQAqAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgkJIgAGAMQdAA==.Shinobu:BAAANQADCgYICgABNQAECgkJHAACAMcYAA==.Shintó:BAAANQADCgEIAgAAAA==.Shnood:BAABNQAECn8UAAMXAAgKMxgzDQAlAgAXAAgKMxgzDQAlAgAUAAEKAABwOgFAAAAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQADCgEIAQAAAA==.Shwager:BAAANQADCggIDwAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn82AAMlAAoKBSFxCQBBAwAlAAoKBSFxCQBBAwAhAAMKewOWGgAqAAAAAA==.',
Sk='Skies:BAAANQAECgMIAwABNQAFFAUICAAcAPEMAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECggIIwADAGolAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgoKJAAKAM4ZAA==.Sterïzard:BAAANQADCgEIAQABNQAECgoKJAAKAM4ZAA==.Stormfuri:BAAANQADCgEIAQAAAA==.Stupid:BAACNQAFFH8FAAISAAIKEBlBDQCUAAASAAIKEBlBDQCUAAA1AAQKfzIAAhIACgpZH3QSADwDABIACgpZH3QSADwDAAAA.Stærk:BAABNQAECn8kAAIKAAoKzhkiOQCSAgAKAAoKzhkiOQCSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgoKLgAHALMdAA==.Sunpally:BAABNQAECn8iAAISAAgKHxVJQgDjAAASAAgKHxVJQgDjAAAAAA==.Suvulaan:BAAANQAECggIEgAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQADCgEIAQAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tatoo:BAABNQAECn83AAINAAoKBR94EABhAwANAAoKBR94EABhAwAAAA==.',
Te='Teeice:BAABNQAECn8qAAIbAAoKEBjkIAB7AgAbAAoKEBjkIAB7AgAAAA==.Teo:BAABNQAECn8hAAITAAgKrg5PMAChAQATAAgKrg5PMAChAQAAAA==.',
Th='Thekan:BAABNQAECn8bAAIgAAgKMheuNgD6AQAgAAgKMheuNgD6AQAAAA==.Theriot:BAABNQAECn8iAAMGAAkKxB0zDgC4AgAGAAkKxB0zDgC4AgAYAAIKNhg8bgFwAAAAAA==.Thianá:BAAANQAECgQIBwAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECggIIQAQABMhAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Tomoya:BAAANQAECgUIBQAAAA==.Toosus:BAACNQAFFH8XAAIRAAYKFx2HAwBCAQARAAYKFx2HAwBCAQA1AAQKfywAAhEACgqHI9MKAF0DABEACgqHI9MKAF0DAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trolldung:BAAANQAECgEIAQAAAA==.',
Tt='Tturtle:BAACNQAFFH8OAAIYAAUK0QzlDgBfAQAYAAUK0QzlDgBfAQA1AAQKfyoAAhgACgq5GDhmAGkCABgACgq5GDhmAGkCAAAA.',
Tu='Turnpike:BAAANQAECgEIAQAAAA==.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAAANQAECgUIBwAAAA==.',
Un='Unclebuck:BAAANQADCgEIAgAAAA==.Unholysam:BAEANQAECgEIAQABNQAECgoKOgAjADscAA==.',
Va='Vallo:BAAANQADCgEIAgAAAA==.Vampier:BAAANQAECgIIAgAAAA==.',
Ve='Velata:BAABNQAECn8vAAIIAAoKFhMNCQBIAgAIAAoKFhMNCQBIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.Vezzena:BAAANQADCgMIAwAAAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Violencê:BAABNQAECn8qAAIWAAkKMx6gAQDwAQAWAAkKMx6gAQDwAQAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAAANQAECgUIBwAAAA==.Vyzeera:BAAANQADCgIIAgAAAA==.',
We='Wes:BAABNQAECn8jAAIbAAcK9hClEAA/AQAbAAcK9hClEAA/AQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn8pAAINAAoKuRduMwDSAgANAAoKuRduMwDSAgAAAA==.Willybcastin:BAABNQAECn8VAAIHAAoKdBzNbwCeAgAHAAoKdBzNbwCeAgABNQAFFAYIEQAeAJ4gAA==.Willybwankin:BAACNQAFFH8RAAIeAAYKniBtAgAjAgAeAAYKniBtAgAjAgA1AAQKfzUAAh4ACQrjJqQDALoDAB4ACQrjJqQDALoDAAAA.',
Wo='Wowgazm:BAAANQAECgYIEQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8gAAMUAAgKwwwEKABRAQAUAAgKwwwEKABRAQAaAAEKAADELgA5AAAAAA==.',
Xa='Xanstar:BAAANQAECgEIAQAAAA==.',
Xe='Xerath:BAAANQAECgMIBAAAAA==.',
Yo='Yogami:BAAANQADCgEIAQAAAA==.',
Za='Zacarly:BAAANQAECgQIBgAAAA==.Zalarian:BAABNQAECn8wAAIYAAoKXCISCgA+AgAYAAoKXCISCgA+AgAAAA==.',
Ze='Zemos:BAAANQAECgEIAQAAAA==.Zeseroth:BAAANQAECgIIAgAAAA==.Zeserotho:BAACNQAFFH8XAAIfAAYKXBaQAgAdAQAfAAYKXBaQAgAdAQA1AAQKfykAAh8ACgqvH7YTALoCAB8ACgqvH7YTALoCAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn81AAMGAAoKLReSGQAoAgAGAAoKLReSGQAoAgASAAgKJhIdZADsAQABNQAECgoKNgAlAAUhAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgEIAQAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8cAAIKAAgKrR2BNwCZAgAKAAgKrR2BNwCZAgAAAA==.',
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
