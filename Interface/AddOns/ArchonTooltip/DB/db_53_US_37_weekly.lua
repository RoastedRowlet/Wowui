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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Priest-Shadow','Warlock-Demonology','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Warrior-Fury','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Feral','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Evoker-Preservation',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn9FAAIBAAoKiiY1AACLAwABAAoKiiY1AACLAwAAAA==.',
Ae='Aezu:BAACNQAFFH8eAAMCAAcK/xg4CQCVAQACAAcK/xg4CQCVAQADAAIK9QkNEgCAAAA1AAQKfzsABAIACgpiI88JAAADAAIACgpiI88JAAADAAMABgqcHndXAKoAAAQAAQr9G5VdAFgAAAAA.',
Ai='Ailuria:BAABNQAECn8zAAIFAAoKeiRfBQBKAwAFAAoKeiRfBQBKAwAAAA==.Aitharen:BAAANQAECgYICgAAAA==.',
Al='Alikith:BAABNQAECn85AAIGAAoKBRVPGgCgAQAGAAoKBRVPGgCgAQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alun:BAAANQADCgYIBwAAAA==.Alyas:BAAANQAECgYICQAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn9NAAMHAAoKeQ8gbgDVAQAHAAoKuQwgbgDVAQAIAAMKfBbKKQCpAAAAAA==.Amelía:BAABNQAECn8tAAMJAAoKDhoUTgDaAQAJAAkKzRgUTgDaAQAKAAgKExTthwD+AAAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgoKLQAJAA4aAA==.',
An='Angando:BAABNQAECn8qAAMLAAoK/gtuJwDAAAAMAAkKPQlXyABnAQALAAQK5gxuJwDAAAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anneliesë:BAAANQABCgMIAwAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgYICQAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arihan:BAAANQAECgYIBgABNQAECgoKMwAMAJcjAA==.Arnarn:BAAANQAECggIDgAAAA==.Arrows:BAAANQADCgYIBgAAAA==.Artemidoros:BAABNQAECn9BAAINAAkK0iKZLgCJAgANAAkK0iKZLgCJAgAAAA==.',
As='Asuná:BAABNQAECn8gAAIOAAoKkRVbbgDTAQAOAAoKkRVbbgDTAQAAAA==.',
Au='Augtism:BAABNQAECn8uAAMPAAoKjgu0FwDOAQAPAAoKdwq0FwDOAQAQAAMKKQatHACBAAAAAA==.',
Av='Avataroffire:BAABNQAECn8hAAMHAAkKMxnEugAwAQAHAAgKdRnEugAwAQAIAAIKPRWnLwCCAAAAAA==.',
Aw='Awakened:BAAANQADCgcIAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Badhabit:BAAANQADCgIIAgAAAA==.Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8cAAIIAAcK/xa+AACHAQAIAAcK/xa+AACHAQA1AAQKfzIAAggACgrXH3wEAKUCAAgACgrXH3wEAKUCAAAA.',
Be='Beefbrownie:BAABNQAECn8wAAILAAoK1hnjCwB6AgALAAoK1hnjCwB6AgAAAA==.Bellezora:BAABNQAECn8nAAIOAAoKPhytOgB+AgAOAAoKPhytOgB+AgAAAA==.Bellwynn:BAABNQAECn8cAAICAAkKxxhANABFAgACAAkKxxhANABFAgAAAA==.Berzerked:BAABNQAECn9jAAIMAAoK9CVaBADUAwAMAAoK9CVaBADUAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.Bigjimslade:BAAANQAECgYIEAABNQAECgoKXgANAEokAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn89AAIRAAoKXx+DEACZAgARAAoKXx+DEACZAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIBwAAAA==.Brasa:BAAANQAECgMIBQAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh3gCwBJAgABAAgKHh3gCwBJAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCggIGQAAAA==.Bus:BAACNQAFFH8SAAIBAAYK6CaNAQDWAQABAAYK6CaNAQDWAQA1AAQKf08AAgEACgoBJwwAABgEAAEACgoBJwwAABgEAAE1AAUUCgo2AAYAYCIA.',
Ca='Calliope:BAAANQABCgIIAwAAAA==.Calnaultenjr:BAAANQADCgEIAQABNQAECgoKQwASANIcAA==.Camholy:BAABNQAECn8pAAMTAAkKhgj6NwBlAQATAAgKTAn6NwBlAQAOAAMKwwQ11QB2AAAAAA==.',
Ce='Celtykun:BAABNQAECn8lAAILAAgKvA0HHAAiAQALAAgKvA0HHAAiAQAAAA==.',
Ch='Chainmalejr:BAAANQADCgEIAQABNQAECgoKPAAHAEMeAA==.Chiron:BAAANQAECgEIAQABNQAECgoKIQAUAEcXAA==.Chiyukii:BAAANQAECggIBwAAAA==.',
Co='Combusted:BAAANQAECgQICwAAAA==.Connie:BAAANQAECgUIDgAAAA==.',
Cr='Crocia:BAAANQABCgYICgAAAA==.',
Cu='Culillo:BAAANQAECgUIBQABNQAFFAUIBwAVAPwaAA==.Cutieheals:BAAANQAECgIIAgAAAA==.',
Cy='Cynfulsqt:BAAANQADCgYIBgABNQAECgkJGgATAMMYAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAABNQAECn8sAAIWAAkKSxJ4LQCoAQAWAAkKSxJ4LQCoAQAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAABNQAECn8hAAMXAAgKyxcQBQCyAQAXAAgKyxcQBQCyAQAYAAEKZwxiLAA+AAAAAA==.Daydalus:BAAANQAECgIIAQAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Demonickills:BAAANQABCggIDAAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.Derik:BAAANQADCgEIAQABNQAECgoKQAAMABAZAA==.',
Dh='Dhing:BAABNQAECn8ZAAIZAAkK+gp/SQCWAQAZAAkK+gp/SQCWAQAAAA==.',
Di='Dillexis:BAABNQAECn9AAAMMAAoKEBmITwAQAgAMAAoKURiITwAQAgAaAAcKLRltGwDaAAAAAA==.Dismagey:BAAANQAECggIDAAAAA==.',
Do='Donald:BAABNQAECn8+AAICAAoKZBMLJgDMAQACAAoKZBMLJgDMAQAAAA==.Doomslash:BAABNQAECn9FAAMMAAoKRBP9UAALAgAMAAoKRBP9UAALAgAaAAMKNBgjMABGAAAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQAECgIIAgABNQAECgoKMwADAG0lAA==.Dragonchest:BAABNQAECn8vAAIXAAoKXiDEAQCTAgAXAAoKXiDEAQCTAgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECgoKLwAXAF4gAA==.Dragonswolf:BAAANQAECgcIDwABNQAECgoKLwAXAF4gAA==.Dragonwing:BAAANQAECgMIAwABNQAECgoKLwAXAF4gAA==.Drbubblesmd:BAAANQAECgYIDwAAAA==.Dregon:BAACNQAFFH8eAAIFAAcKKiVqAQCwAgAFAAcKKiVqAQCwAgA1AAQKfzUAAgUACgqlJukAANADAAUACgqlJukAANADAAAA.Dreinara:BAAANQAECgQICQAAAA==.',
Du='Dummysezwhut:BAAANQAECgUIDQAAAA==.',
Ea='Eastofeden:BAABNQAECn8dAAIUAAoKJBUpSAD8AQAUAAoKJBUpSAD8AQAAAA==.',
Ec='Echinopsis:BAAANQAECgQICgAAAA==.Eclipze:BAAANQAECgQIBAAAAA==.',
Ei='Eiduartkay:BAAANQAECgcICwABNQAFFAQICAANAGoXAA==.Eight:BAAANQAECgQIBQAAAA==.Eilyn:BAABNQAECn85AAIbAAoKxAxYnQCSAQAbAAoKxAxYnQCSAQAAAA==.',
El='Elffaba:BAAANQADCgIIBAABNQADCgYIEQAcAAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAABNQAECn8cAAINAAoKPgR79gDEAAANAAoKPgR79gDEAAAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Fazlain:BAABNQAECn8qAAIbAAoKCxo/TwA+AgAbAAoKCxo/TwA+AgAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgIIAwABNQAECgoKIQAUAEcXAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fi='Fighter:BAAANQADCgEIAQABNQAECgoKLQAJAPYdAA==.',
Fr='Friartuck:BAAANQAECgYICQABNQAECgoKXgANAEokAA==.Frosteez:BAAANQABCgIIAgABNQAECggIGwAaACEgAA==.',
Fu='Furryem:BAABNQAECn8zAAIDAAoKbSWBBQCSAwADAAoKbSWBBQCSAwAAAA==.',
['Fô']='Fôxx:BAAANQAECgcICgAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn9PAAMbAAoKGxVsawD5AQAbAAoKGxVsawD5AQASAAUKYg7lmADyAAAAAA==.Gatelinka:BAAANQAECgYIBgABNQAECgoKIQAJAGUeAA==.Gateto:BAABNQAECn8hAAMJAAoKZR5IOgB2AgAJAAoKZR5IOgB2AgAKAAQKEAht4wDQAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAcAAAAAA==.',
Gl='Glynistann:BAAANQAECgYICQAAAA==.',
Gr='Grngoblin:BAAANQADCggICAAAAA==.',
Gu='Gundox:BAAANQAECgYICQAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hanoa:BAAANQAECgUICQAAAA==.Hartley:BAAANQAECgUICQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAABNQAECn9AAAMXAAoK3A7sBgBrAQAUAAoK8wfhbQCPAQAXAAkK+w/sBgBrAQAAAA==.',
Ho='Holeshot:BAAANQABCgEIAQAAAA==.Holycow:BAAANQAECgUICAAAAA==.Holyspaunk:BAAANQADCgIIAgAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn9NAAINAAoKYRzEJwCgAgANAAoKYRzEJwCgAgAAAA==.',
Ik='Ikickgnômes:BAABNQAECn8aAAIKAAgKcgUeiAD9AAAKAAgKcgUeiAD9AAAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgoKPAAHAEMeAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECn8nAAQXAAoKniIjBQDKAgAXAAgKJiMjBQDKAgAUAAUKaR+powCOAQAYAAEK/xRfLgA5AAAAAA==.',
Is='Ishamael:BAAANQADCgIIAgAAAA==.',
Iv='Ivon:BAAANQAECgcIBgABNQAECgoKQAAMABAZAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.Jadedbabe:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8VAAMdAAUK8RoLDwD5AAAdAAMK8RoLDwD5AAAeAAMKfhkAAgDlAAA1AAQKfyUABB0ACgoWH1sdAJQCAB0ACQqpH1sdAJQCAB4ACQoXG74FAIcCAB8AAQr8H6zEAGMAAAAA.',
Ji='Jickle:BAAANQAECgEIAQAAAA==.',
Jo='Joppa:BAAANQADCgQIBAABNQAFFAkJGwATANMPAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgUIBwAAAA==.',
Ke='Kealli:BAAANQADCgUIBQAAAA==.Keý:BAACNQAFFH8eAAIMAAcKGB+dCgCtAQAMAAcKGB+dCgCtAQA1AAQKfzEAAgwACgqII74gAMECAAwACgqII74gAMECAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAABNQAECn8jAAINAAoK0BQeZAD9AQANAAoK0BQeZAD9AQAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIIAgAAAA==.Kim:BAAANQADCggIDAAAAA==.Kiy:BAABNQAECn8nAAIUAAoKbBGMjgDCAQAUAAoKbBGMjgDCAQAAAA==.',
Kn='Knockout:BAAANQADCggICAAAAA==.Knìghtmare:BAAANQAECgEIAQAAAA==.',
Kr='Krakenlock:BAABNQAECn9HAAIUAAoKfwcPegBwAQAUAAoKfwcPegBwAQAAAA==.Krenin:BAAANQADCgMIBAAAAA==.Kronas:BAAANQAECgIIAgAAAA==.',
Ku='Kumojoru:BAACNQAFFH8eAAIEAAcKXBz6AACNAQAEAAcKXBz6AACNAQA1AAQKfzgABAQACgowJZYDADQDAAQACgowJZYDADQDACAAAwp4HR0hAAwBAAIAAQrcA8O/ACIAAAAA.',
Ky='Kyranos:BAAANQAECgQIBQAAAA==.',
La='Lazyheal:BAAANQAECgIIAwABNQAECgoKLQAJAPYdAA==.',
Le='Leigor:BAACNQAFFH8dAAIOAAYKoRfhDAC+AQAOAAYKoRfhDAC+AQA1AAQKf0IAAg4ACgolImQgAO4CAA4ACgolImQgAO4CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Limbow:BAAANQAECggICAABNQAFFAgIEwAMAAUQAA==.Linthsong:BAABNQAECn8aAAIIAAgK7AkRHwDyAAAIAAgK7AkRHwDyAAABNQAECgoKKwAOAEkTAA==.Lionature:BAAANQAECgQIBAAAAA==.Lionknite:BAABNQAECn9DAAQhAAoK4RyoDgCSAgAhAAoK4RyoDgCSAgAZAAIKnQexsgAtAAARAAEK6QN4rwAjAAAAAA==.Liteshocklet:BAABNQAECn8tAAMJAAoK9h0TKQC/AgAJAAoK9h0TKQC/AgAKAAEKygn6/QA2AAAAAA==.Littledung:BAAANQAECgEIAQAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8oAAMDAAoKxA5ZLwCgAQADAAoKxA5ZLwCgAQACAAYKqAIlhwC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMFAAcKshwDHADEAQAFAAYKyBsDHADEAQAiAAIK8gDKZgBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQAECgQIBQABNQAECgoKTQAWAMMaAA==.Mauzii:BAAANQADCgMIBAABNQAECgoKTQAWAMMaAA==.Maylea:BAAANQAECgUIBwAAAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn81AAIhAAoKYyGcCgDOAgAhAAoKYyGcCgDOAgAAAA==.',
Me='Melliah:BAAANQAECgYICQAAAA==.Mes:BAABNQAECn8bAAIKAAcKHR0LSABWAgAKAAcKHR0LSABWAgAAAA==.Metatrøn:BAAANQADCggIHQAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgoKRQABAIomAA==.Mimmi:BAABNQAECn9DAAMJAAoKWxdBNQBGAgAJAAoKWxdBNQBGAgAKAAEKAABZJgEAAAABNQAECgoKTQAWAMMaAA==.Misaligned:BAABNQAECn8bAAIHAAkKgwVruwAvAQAHAAkKgwVruwAvAQAAAA==.Misidian:BAAANQADCgQIBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgoKKAAHANoWAA==.Moonsorrow:BAABNQAECn8wAAIDAAoK5x+5CABLAwADAAoK5x+5CABLAwAAAA==.Moritura:BAABNQAECn9NAAMWAAoKwxqXEwCGAgAWAAoKwxqXEwCGAgAjAAUKZhGmHQChAAAAAA==.',
My='Mywifesaidno:BAAANQAECgQIBAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAgIEgATAAcVAA==.Nemistrasza:BAAANQADCggICwABNQAECgoKMwAFAHokAA==.Nerfme:BAAANQADCgEIAQABNQAECgoKQwASANIcAA==.',
Ni='Nilanza:BAAANQAECgIIAgABNQAECgoKMwAMAJcjAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQAECgYICQAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAAcAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAdAEsVAA==.',
Ob='Obergefel:BAABNQAECn8bAAIkAAkKSBmzGADsAQAkAAkKSBmzGADsAQAAAA==.',
Ol='Ollie:BAAANQAECgEIAQAAAA==.',
Op='Ophiuchus:BAABNQAECn8hAAIUAAoKRxe0VQDTAQAUAAoKRxe0VQDTAQAAAA==.Oppsie:BAAANQAECgYIBgAAAA==.',
Or='Orcdung:BAAANQABCgUIDAAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAABNQAECn8aAAMSAAkKjRigPgAbAgASAAkKjRigPgAbAgAbAAEKJAdOmgE0AAAAAA==.Pallycow:BAAANQAECgQICgAAAA==.Pamelina:BAAANQABCgcICAAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgoKQAAMABAZAA==.Pandunkadunk:BAAANQAECgQICQAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8bAAMaAAgKISAxFgA5AQAMAAcKKBs+owDEAQAaAAUKGyIxFgA5AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggINQAAAA==.Pengulo:BAABNQAECn8zAAIMAAoKlyNoHQBCAwAMAAoKlyNoHQBCAwAAAA==.Pernicious:BAABNQAECn8fAAMXAAkKnQ8MHACNAQAXAAcKlw8MHACNAQAUAAcKNQ1wpAANAQAAAA==.',
Ph='Phade:BAAANQADCgMIAwAAAA==.Phillis:BAAANQAECgIIAgAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAAANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAABNQAECn8tAAIUAAkKgBHXcACIAQAUAAkKgBHXcACIAQAAAA==.Pinkiemena:BAAANQAFFAIIAgAAAA==.Piolin:BAAANQAECgcIDAAAAA==.',
Pu='Punchykicky:BAABNQAECn8nAAMFAAgKdB/QCQC1AgAFAAgKdB/QCQC1AgABAAcKGgl6FADeAAABNQAECgoKWAAGAFkeAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8kAAQOAAoKEwfUkQBhAQAOAAoKEwfUkQBhAQATAAgKHAeFSAD7AAAlAAEKVQGKNAANAAAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAABNQAECn9DAAMSAAoKFiGLBgC0AwASAAoKFiGLBgC0AwAbAAEKAABXsAEvAAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reliun:BAABNQAECn8YAAIhAAcK4gbTQAAMAQAhAAcK4gbTQAAMAQABNQAECgkJKQATAIYIAA==.Reniel:BAAANQADCgMIAwABNQAECgoKOQAGAAUVAA==.Reverendlion:BAABNQAECn8bAAMTAAkKExQEKQA9AQATAAgKUREEKQA9AQAOAAEKhwQA+QAvAAAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAABNQAECn8zAAIMAAkK+h7jHgDKAgAMAAkK+h7jHgDKAgAAAA==.Rosencrant:BAABNQAECn8hAAINAAgKcA1CeQDKAQANAAgKcA1CeQDKAQAAAA==.',
Ru='Rubberdukkie:BAAANQAECgcIDgAAAA==.Ruemor:BAAANQADCgcIBwAAAA==.Rule:BAAANQAECgYICQAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgoKQQAbABsbAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECn84AAIjAAoKjRvXBwAIAgAjAAoKjRvXBwAIAgAAAA==.Sampal:BAABNQAECn9YAAIGAAoKWR6FDQBUAgAGAAoKWR6FDQBUAgAAAA==.Samwield:BAABNQAECn9NAAMfAAoK3B+FCwC8AgAfAAoKxh+FCwC8AgAdAAMK6xRReADRAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgMIBAABNQAFFAUIBwAVAPwaAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn9GAAIJAAoKQhg/LAB0AgAJAAoKQhg/LAB0AgAAAA==.Selaheal:BAABNQAECn9OAAITAAoKsREfFgAAAgATAAoKsREfFgAAAgAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadowydream:BAAANQAECgUIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgoKNwAGAFogAA==.Shinobu:BAAANQADCgYICgABNQAECgkJHAACAMcYAA==.Shintó:BAAANQADCgEIAQAAAA==.Shnood:BAABNQAECn8WAAMXAAgKMxgzDQAlAgAXAAgKMxgzDQAlAgAUAAEKAABwOgFAAAAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCggIDwAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn9SAAMkAAoKmCFxCQBBAwAkAAoKmCFxCQBBAwAjAAgKTgbnGgC+AAAAAA==.',
Sk='Skies:BAAANQAECgMIAwABNQAFFAcIDgAfAEIOAA==.',
Sm='Smallshaq:BAAANQAECgEIAQAAAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECgoKMwADAG0lAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgoKJAAKAM4ZAA==.Sterïzard:BAAANQADCgEIAQABNQAECgoKJAAKAM4ZAA==.Stupid:BAACNQAFFH8JAAISAAQKyxW9EQAkAQASAAQKyxW9EQAkAQA1AAQKf0IAAhIACgp2IYQOAE4DABIACgp2IYQOAE4DAAAA.Stærk:BAABNQAECn8kAAIKAAoKzhkiOQCSAgAKAAoKzhkiOQCSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgoKPAAHAEMeAA==.Sunpally:BAABNQAECn8rAAISAAoKfRT8fwCaAQASAAoKfRT8fwCaAQAAAA==.Suvulaan:BAABNQAECn8lAAMmAAkKlQYVHwAYAQAmAAkKlQYVHwAYAQAQAAMKSAQ0GwBIAAAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tarinaa:BAAANQAECgIIAgAAAA==.Tatoo:BAABNQAECn9eAAINAAoKSiSgBgBYAwANAAoKSiSgBgBYAwAAAA==.',
Te='Teeice:BAABNQAECn80AAIdAAoKphnsCwAQAgAdAAoKphnsCwAQAgAAAA==.Teo:BAABNQAECn8oAAITAAoKNQ5PMAChAQATAAoKNQ5PMAChAQAAAA==.',
Th='Thariot:BAAANQADCgQIBAABNQAECgoKNwAGAFogAA==.Thekan:BAABNQAECn8mAAIWAAkKhRauNgD6AQAWAAkKhRauNgD6AQAAAA==.Theriot:BAABNQAECn83AAMGAAoKWiDLCAC3AgAGAAoKWiDLCAC3AgAbAAIKNhg8bgFwAAAAAA==.Thianá:BAAANQAECgUICwAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECgoKJwAOAD4cAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Tomoya:BAAANQAECgUIBQAAAA==.Toosus:BAACNQAFFH8eAAIRAAcK9RxDCQCPAQARAAcK9RxDCQCPAQA1AAQKfzcAAhEACgq0JNsGABkDABEACgq0JNsGABkDAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trethan:BAAANQADCgQIAwAAAA==.Trolldung:BAAANQAECgEIAQAAAA==.',
Tt='Tturtle:BAACNQAFFH8SAAIbAAYKNg3lDgBfAQAbAAYKNg3lDgBfAQA1AAQKfzIAAhsACgqjGjhmAGkCABsACgqjGjhmAGkCAAAA.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAABNQAECn8uAAQGAAoKfBclEAAoAgAGAAkK8BYlEAAoAgASAAcKzA/FrgAiAQAbAAQK+hOdFAHKAAAAAA==.',
Un='Unclebuck:BAAANQABCgYIDgAAAA==.Unholysam:BAAANQAECgEIAQABNQAECgoKTQAfANwfAA==.',
Va='Vampier:BAAANQAECgUIBAAAAA==.',
Ve='Velata:BAABNQAECn88AAIIAAoKsxQNCQBIAgAIAAoKsxQNCQBIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.Vezzena:BAAANQADCgMIAwABNQAECgoKGwAIAJcLAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Violencê:BAABNQAECn9KAAIaAAoKSSTlAABaAwAaAAoKSSTlAABaAwAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAABNQAECn8VAAIUAAgKjBKEdgB5AQAUAAgKjBKEdgB5AQAAAA==.Vyzeera:BAABNQAECn8bAAMIAAoKlwuyEACDAQAIAAoKYQuyEACDAQAHAAoKwAarlAB8AQAAAA==.',
Wa='Warriored:BAAANQADCgMIBAAAAA==.',
We='Wes:BAABNQAECn8oAAIdAAkKZRLiDwDKAQAdAAkKZRLiDwDKAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn8/AAINAAoKdhpuMwDSAgANAAoKdhpuMwDSAgAAAA==.Willybcastin:BAABNQAECn8sAAIHAAoK9CDJIAC9AgAHAAoK9CDJIAC9AgABNQAFFAYIEgAhAJ4gAA==.Willybwankin:BAACNQAFFH8SAAIhAAYKniBtAgAjAgAhAAYKniBtAgAjAgA1AAQKf1AAAiEACgraJmsAAJMDACEACgraJmsAAJMDAAAA.',
Wo='Wowgazm:BAABNQAECn8XAAIGAAkKAgj6PAAMAQAGAAkKAgj6PAAMAQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8uAAMUAAoK1A26WQDHAQAUAAoK1A26WQDHAQAYAAEKAADELgA5AAAAAA==.',
Xa='Xanstar:BAAANQADCgQIBAAAAA==.',
Xe='Xerath:BAAANQAECgQIBQAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgQICQAAAA==.Zalarian:BAABNQAECn9NAAMbAAoK9SPEFAARAwAbAAoK9SPEFAARAwAGAAkKYB4hCQCuAgAAAA==.Zaldrevan:BAAANQADCgUIBQAAAA==.',
Ze='Zeseroth:BAAANQAECgIIAgAAAA==.Zeserotho:BAACNQAFFH8dAAIiAAcK9BN+BQBmAQAiAAcK9BN+BQBmAQA1AAQKfzQAAiIACgr4IAoPAGwCACIACgr4IAoPAGwCAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn9EAAMGAAoKfRmSGQAoAgAGAAoKfRmSGQAoAgASAAoKfRj5RwD0AQABNQAECgoKUgAkAJghAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgQIBgAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8eAAMKAAgKrR2BNwCZAgAKAAgKrR2BNwCZAgAJAAIKACIBswC0AAAAAA==.',
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
