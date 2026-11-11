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
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn9FAAIBAAoKiiYuAACMAwABAAoKiiYuAACMAwAAAA==.',
Ae='Aezu:BAACNQAFFH8eAAMCAAcK/xhRBwCaAQACAAcK/xhRBwCaAQADAAIK9Ql/EACAAAA1AAQKfzoABAIACgpiIxgJAAEDAAIACgpiIxgJAAEDAAMABgqcHndXAKoAAAQAAQr9Gy9YAFgAAAAA.',
Ai='Ailuria:BAABNQAECn8zAAIFAAoKeiRfBQBKAwAFAAoKeiRfBQBKAwAAAA==.Aitharen:BAAANQAECgYICgAAAA==.',
Al='Alikith:BAABNQAECn84AAIGAAoKshSFGACcAQAGAAoKshSFGACcAQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alun:BAAANQADCgYIBwAAAA==.Alyas:BAAANQAECgUICAAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn9EAAMHAAoK6A1xbwDAAQAHAAoKJwtxbwDAAQAIAAMKfBbKKQCpAAAAAA==.Amelía:BAABNQAECn8tAAMJAAoKDhp0RwDeAQAJAAkKzRh0RwDeAQAKAAgKExSofQAAAQAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgoKLQAJAA4aAA==.',
An='Angando:BAABNQAECn8qAAMLAAoK/gtsJADAAAAMAAkKPQlXyABnAQALAAQK5gxsJADAAAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anneliesë:BAAANQABCgMIAwAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgUICAAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arihan:BAAANQAECgYIBgABNQAECgoKMwAMAJcjAA==.Arnarn:BAAANQAECggIDgAAAA==.Arrows:BAAANQADCgQIBAAAAA==.Artemidoros:BAABNQAECn85AAINAAgKECPSMwDQAgANAAgKECPSMwDQAgAAAA==.',
As='Asuná:BAABNQAECn8eAAIOAAoK1BNbbgDTAQAOAAoK1BNbbgDTAQAAAA==.',
Au='Augtism:BAABNQAECn8uAAMPAAoKjgu0FwDOAQAPAAoKdwq0FwDOAQAQAAMKKQatHACBAAAAAA==.',
Av='Avataroffire:BAABNQAECn8eAAMHAAkKBBeK/QCSAQAHAAgK6RaK/QCSAQAIAAIKPRWnLwCCAAAAAA==.',
Aw='Awakened:BAAANQADCgcIAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Badhabit:BAAANQADCgIIAgAAAA==.Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8cAAIIAAcK/xaQAACHAQAIAAcK/xaQAACHAQA1AAQKfzIAAggACgrXH80DAKwCAAgACgrXH80DAKwCAAAA.',
Be='Beefbrownie:BAABNQAECn8uAAILAAkKAxvjCwB6AgALAAkKAxvjCwB6AgAAAA==.Bellezora:BAABNQAECn8nAAIOAAoKPhytOgB+AgAOAAoKPhytOgB+AgAAAA==.Bellwynn:BAABNQAECn8cAAICAAkKxxhANABFAgACAAkKxxhANABFAgAAAA==.Berzerked:BAABNQAECn9gAAIMAAoKkSVaBADUAwAMAAoKkSVaBADUAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.Bigjimslade:BAAANQAECgYIEAABNQAECgoKVAANAEcjAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn89AAIRAAoKXx9kDwCfAgARAAoKXx9kDwCfAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIBgAAAA==.Brasa:BAAANQAECgMIBQAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh3gCwBJAgABAAgKHh3gCwBJAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCggIGQAAAA==.Bus:BAACNQAFFH8MAAIBAAYKtSYLAQDXAQABAAYKtSYLAQDXAQA1AAQKf0QAAgEACgoBJwwAABgEAAEACgoBJwwAABgEAAE1AAUUCAgsAAYA+CYA.',
Ca='Calliope:BAAANQABCgIIAwAAAA==.Calnaultenjr:BAAANQADCgEIAQABNQAECgoKQwASANIcAA==.Camholy:BAABNQAECn8oAAMTAAgKTAn6NwBlAQATAAgKTAn6NwBlAQAOAAIK4wR83gBMAAAAAA==.',
Ce='Celtykun:BAABNQAECn8fAAILAAgKFAx2GwASAQALAAgKFAx2GwASAQAAAA==.',
Ch='Chainmalejr:BAAANQADCgEIAQABNQAECgoKPAAHAEMeAA==.Chiron:BAAANQAECgEIAQABNQAECgkJHQAUAMEWAA==.Chiyukii:BAAANQAECggIBwAAAA==.',
Co='Combusted:BAAANQAECgQICwAAAA==.Connie:BAAANQAECgUIDgAAAA==.',
Cr='Crocia:BAAANQABCgYICgAAAA==.',
Cu='Culillo:BAAANQAECgUIBQABNQAFFAUIBwAVAPwaAA==.',
Cy='Cynfulsqt:BAAANQADCgYIBgABNQAECgkJGAATAP4WAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAABNQAECn8dAAIWAAkKwA4ZLwCFAQAWAAkKwA4ZLwCFAQAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAABNQAECn8cAAMXAAgKJRb8BACdAQAXAAgKJRb8BACdAQAYAAEKZwxiLAA+AAAAAA==.Daydalus:BAAANQAECgIIAQAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.Derik:BAAANQADCgEIAQABNQAECgoKQAAMABAZAA==.',
Dh='Dhing:BAABNQAECn8ZAAIZAAkK+gp/SQCWAQAZAAkK+gp/SQCWAQAAAA==.',
Di='Dillexis:BAABNQAECn9AAAMMAAoKEBlGSQATAgAMAAoKURhGSQATAgAaAAcKLRnFGADeAAAAAA==.Dismagey:BAAANQAECggIDAAAAA==.',
Do='Donald:BAABNQAECn8+AAICAAoKZBNXIwDNAQACAAoKZBNXIwDNAQAAAA==.Doomslash:BAABNQAECn9FAAMMAAoKRBNUSgAPAgAMAAoKRBNUSgAPAgAaAAMKNBgTLABHAAAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQAECgIIAgABNQAECgkJMQADAGglAA==.Dragonchest:BAABNQAECn8vAAIXAAoKXiCUAQCUAgAXAAoKXiCUAQCUAgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECgoKLwAXAF4gAA==.Dragonswolf:BAAANQAECgcIDwABNQAECgoKLwAXAF4gAA==.Dragonwing:BAAANQAECgMIAwABNQAECgoKLwAXAF4gAA==.Drbubblesmd:BAAANQAECgYIDwAAAA==.Dregon:BAACNQAFFH8eAAIFAAcKKiUMAQC+AgAFAAcKKiUMAQC+AgA1AAQKfzUAAgUACgqlJukAANADAAUACgqlJukAANADAAAA.Dreinara:BAAANQAECgQICQAAAA==.',
Du='Dummysezwhut:BAAANQAECgUIDQAAAA==.',
Ea='Eastofeden:BAABNQAECn8aAAIUAAkKHxR4WQC0AQAUAAkKHxR4WQC0AQAAAA==.',
Ec='Echinopsis:BAAANQAECgQICgAAAA==.Eclipze:BAAANQAECgQIBAAAAA==.',
Ei='Eiduartkay:BAAANQAECgcICwABNQAFFAQICAANAGoXAA==.Eight:BAAANQAECgQIBQAAAA==.Eilyn:BAABNQAECn84AAIbAAkKhg3/qQBkAQAbAAkKhg3/qQBkAQAAAA==.',
El='Elffaba:BAAANQADCgIIBAABNQADCgYIEQAcAAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAABNQAECn8cAAINAAoKPgTn6ADEAAANAAoKPgTn6ADEAAAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Fazlain:BAABNQAECn8lAAIbAAkKBhjscADZAQAbAAkKBhjscADZAQAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgIIAwABNQAECgkJHQAUAMEWAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fi='Fighter:BAAANQADCgEIAQABNQAECgoKLQAJAPYdAA==.',
Fr='Friartuck:BAAANQAECgYICQABNQAECgoKVAANAEcjAA==.Frosteez:BAAANQABCgIIAgABNQAECggIGwAaACEgAA==.',
Fu='Furryem:BAABNQAECn8xAAIDAAkKaCXaBgBVAwADAAkKaCXaBgBVAwAAAA==.',
['Fô']='Fôxx:BAAANQAECgYICQAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn9IAAMbAAoKZhS3bgDfAQAbAAoKZhS3bgDfAQASAAUKYg4qkAD2AAAAAA==.Gatelinka:BAAANQAECgYIBgABNQAECgoKIQAJAGUeAA==.Gateto:BAABNQAECn8hAAMJAAoKZR5IOgB2AgAJAAoKZR5IOgB2AgAKAAQKEAht4wDQAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAcAAAAAA==.',
Gl='Glynistann:BAAANQAECgUICAAAAA==.',
Gu='Gundox:BAAANQAECgUICAAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hanoa:BAAANQAECgUICQAAAA==.Hartley:BAAANQAECgUICQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAABNQAECn86AAMXAAoK1A4ABgBxAQAUAAoKgAfCaACJAQAXAAkK+w8ABgBxAQAAAA==.',
Ho='Holeshot:BAAANQABCgEIAQAAAA==.Holycow:BAAANQAECgUICAAAAA==.Holyspaunk:BAAANQADCgIIAgAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn9EAAINAAoKIRt/JwCTAgANAAoKIRt/JwCTAgAAAA==.',
Ik='Ikickgnômes:BAABNQAECn8aAAIKAAgKcgXOfgD9AAAKAAgKcgXOfgD9AAAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgoKPAAHAEMeAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECn8nAAQXAAoKniIjBQDKAgAXAAgKJiMjBQDKAgAUAAUKaR+powCOAQAYAAEK/xRfLgA5AAAAAA==.',
Is='Ishamael:BAAANQADCgIIAgAAAA==.',
Iv='Ivon:BAAANQAECgcIBgABNQAECgoKQAAMABAZAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.Jadedbabe:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8VAAMdAAUK8RoLDwD5AAAdAAMK8RoLDwD5AAAeAAMKfhkAAgDlAAA1AAQKfyUABB0ACgoWH1sdAJQCAB0ACQqpH1sdAJQCAB4ACQoXG74FAIcCAB8AAQr8H5+4AGMAAAAA.',
Ji='Jickle:BAAANQAECgEIAQAAAA==.',
Jo='Joppa:BAAANQADCgQIBAABNQAFFAgIGQATALoQAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgUIBwAAAA==.',
Ke='Kealli:BAAANQADCgUIBQAAAA==.Keý:BAACNQAFFH8eAAIMAAcKGB8ACAC+AQAMAAcKGB8ACAC+AQA1AAQKfzEAAgwACgqII58dAMcCAAwACgqII58dAMcCAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAABNQAECn8jAAINAAoK0BR6WAACAgANAAoK0BR6WAACAgAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCggIDAAAAA==.Kiy:BAABNQAECn8nAAIUAAoKbBGMjgDCAQAUAAoKbBGMjgDCAQAAAA==.',
Kn='Knockout:BAAANQADCggICAAAAA==.Knìghtmare:BAAANQAECgEIAQAAAA==.',
Kr='Krakenlock:BAABNQAECn8+AAIUAAoKVQcKdwBiAQAUAAoKVQcKdwBiAQAAAA==.Krenin:BAAANQADCgMIBAAAAA==.Kronas:BAAANQAECgIIAgAAAA==.',
Ku='Kumojoru:BAACNQAFFH8eAAIEAAcKXBzIAACTAQAEAAcKXBzIAACTAQA1AAQKfzgABAQACgowJUEDADcDAAQACgowJUEDADcDACAAAwp4HR0hAAwBAAIAAQrcA8O/ACIAAAAA.',
Ky='Kyranos:BAAANQADCggIKAAAAA==.',
La='Lazyheal:BAAANQAECgIIAwABNQAECgoKLQAJAPYdAA==.',
Le='Leigor:BAACNQAFFH8dAAIOAAYKoRfECwDQAQAOAAYKoRfECwDQAQA1AAQKf0IAAg4ACgolImQgAO4CAA4ACgolImQgAO4CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Limbow:BAAANQAECggICAABNQAFFAgIEwAMAAUQAA==.Linthsong:BAABNQAECn8aAAIIAAgK7AkRHwDyAAAIAAgK7AkRHwDyAAAAAA==.Lionknite:BAABNQAECn86AAQhAAoKuxrSGAAQAgAhAAoKuxrSGAAQAgAZAAIKnQexsgAtAAARAAEK6QPJqAAkAAAAAA==.Liteshocklet:BAABNQAECn8tAAMJAAoK9h0TKQC/AgAJAAoK9h0TKQC/AgAKAAEKygmQ8gA2AAAAAA==.Littledung:BAAANQAECgIIAQAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8oAAMDAAoKxA5ZLwCgAQADAAoKxA5ZLwCgAQACAAYKqAIlhwC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMFAAcKshwDHADEAQAFAAYKyBsDHADEAQAiAAIK8gDKZgBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQAECgYIBQABNQAECgoKRAAWAEQYAA==.Mauzii:BAAANQADCgMIBAABNQAECgoKRAAWAEQYAA==.Maylea:BAAANQAECgEIAQAAAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn81AAIhAAoKYyFzCQDVAgAhAAoKYyFzCQDVAgAAAA==.',
Me='Melliah:BAAANQAECgUICAAAAA==.Mes:BAABNQAECn8bAAIKAAcKHR0LSABWAgAKAAcKHR0LSABWAgAAAA==.Metatrøn:BAAANQADCggIHQAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgoKRQABAIomAA==.Mimmi:BAABNQAECn86AAMJAAoK6hZDMwA6AgAJAAoK6hZDMwA6AgAKAAEKAAC4GQEAAAABNQAECgoKRAAWAEQYAA==.Misaligned:BAABNQAECn8bAAIHAAkKgwXesQAvAQAHAAkKgwXesQAvAQAAAA==.Misidian:BAAANQADCgQIBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgoKJAAHAHwWAA==.Moonsorrow:BAABNQAECn8wAAIDAAoK5x+rBwBQAwADAAoK5x+rBwBQAwAAAA==.Moritura:BAABNQAECn9EAAMWAAoKRBjEFQBcAgAWAAoKRBjEFQBcAgAjAAUKZhE0HACaAAAAAA==.',
My='Mywifesaidno:BAAANQAECgQIBAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAcIEQATAH4TAA==.Nemistrasza:BAAANQADCggICwABNQAECgoKMwAFAHokAA==.Nerfme:BAAANQADCgEIAQABNQAECgoKQwASANIcAA==.',
Ni='Nilanza:BAAANQAECgIIAgABNQAECgoKMwAMAJcjAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQAECgYICQAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAAcAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAdAEsVAA==.',
Ob='Obergefel:BAABNQAECn8bAAIkAAkKSBmlFgDxAQAkAAkKSBmlFgDxAQAAAA==.',
Ol='Ollie:BAAANQAECgEIAQAAAA==.',
Op='Ophiuchus:BAABNQAECn8dAAIUAAkKwRbsfgDpAQAUAAkKwRbsfgDpAQAAAA==.Oppsie:BAAANQAECgYIBgAAAA==.',
Or='Orcdung:BAAANQABCgUIDAAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAABNQAECn8aAAMSAAkKjRi5OAAkAgASAAkKjRi5OAAkAgAbAAEKJAdJiAE1AAAAAA==.Pallycow:BAAANQAECgQIBgAAAA==.Pamelina:BAAANQABCgcICAAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgoKQAAMABAZAA==.Pandunkadunk:BAAANQAECgQIBQAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8bAAMaAAgKISAxFgA5AQAMAAcKKBs+owDEAQAaAAUKGyIxFgA5AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggINQAAAA==.Pengulo:BAABNQAECn8zAAIMAAoKlyNoHQBCAwAMAAoKlyNoHQBCAwAAAA==.Pernicious:BAABNQAECn8fAAMXAAkKnQ8MHACNAQAXAAcKlw8MHACNAQAUAAcKNQ2KmgAPAQAAAA==.',
Ph='Phade:BAAANQADCgMIAwAAAA==.Phillis:BAAANQAECgIIAgAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAAANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAABNQAECn8oAAIUAAgK1RL3eQBbAQAUAAgK1RL3eQBbAQAAAA==.Pinkiemena:BAAANQAFFAIIAgAAAA==.Piolin:BAAANQAECgcIDAAAAA==.',
Pu='Punchykicky:BAABNQAECn8hAAMFAAgKdB/yCAC6AgAFAAgKdB/yCAC6AgABAAYK+AVTGQCSAAABNQAECgoKTgAGAI0cAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8jAAQOAAoKEwfUkQBhAQAOAAoKEwfUkQBhAQATAAcKMweFSAD7AAAlAAEKVQGKNAANAAAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAABNQAECn83AAMSAAoKbB9NCQCAAwASAAoKbB9NCQCAAwAbAAEKAABXsAEvAAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reliun:BAAANQAECgcIEQABNQAECggIKAATAEwJAA==.Reniel:BAAANQADCgMIAwABNQAECgoKOAAGALIUAA==.Reverendlion:BAABNQAECn8VAAMTAAgKUBTJMQCUAQATAAcKDhHJMQCUAQAOAAEKhwRh8AAvAAAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAABNQAECn8sAAIMAAkKaBz0JwCVAgAMAAkKaBz0JwCVAgAAAA==.Rosencrant:BAABNQAECn8hAAINAAgKcA2PbQDLAQANAAgKcA2PbQDLAQAAAA==.',
Ru='Rubberdukkie:BAAANQAECgcIDgAAAA==.Ruemor:BAAANQADCgcIBwAAAA==.Rule:BAAANQAECgUICAAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgoKOAAbABsbAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECn84AAIjAAoKjRslBwAJAgAjAAoKjRslBwAJAgAAAA==.Sampal:BAABNQAECn9OAAIGAAoKjRwhDQBHAgAGAAoKjRwhDQBHAgAAAA==.Samwield:BAABNQAECn9JAAMfAAoK3B+FCwC8AgAfAAoKxh+FCwC8AgAdAAMK6xRReADRAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgMIBAABNQAFFAUIBwAVAPwaAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn85AAIJAAoK/RTEVQARAgAJAAoK/RTEVQARAgAAAA==.Selaheal:BAABNQAECn9FAAITAAoKPxCgFgDiAQATAAoKPxCgFgDiAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadowydream:BAAANQAECgUIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgoKNwAGAFogAA==.Shinobu:BAAANQADCgYICgABNQAECgkJHAACAMcYAA==.Shintó:BAAANQADCgEIAQAAAA==.Shnood:BAABNQAECn8WAAMXAAgKMxgzDQAlAgAXAAgKMxgzDQAlAgAUAAEKAABwOgFAAAAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCggIDwAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn9OAAMkAAoKdCFxCQBBAwAkAAoKdCFxCQBBAwAjAAcK/QUJHQCSAAAAAA==.',
Sk='Skies:BAAANQAECgMIAwABNQAFFAcIDgAfAEIOAA==.',
Sm='Smallshaq:BAAANQAECgEIAQAAAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECgkJMQADAGglAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgoKJAAKAM4ZAA==.Sterïzard:BAAANQADCgEIAQABNQAECgoKJAAKAM4ZAA==.Stupid:BAACNQAFFH8JAAISAAQKyxXiDwArAQASAAQKyxXiDwArAQA1AAQKf0IAAhIACgp2IQMMAF4DABIACgp2IQMMAF4DAAAA.Stærk:BAABNQAECn8kAAIKAAoKzhkiOQCSAgAKAAoKzhkiOQCSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgoKPAAHAEMeAA==.Sunpally:BAABNQAECn8rAAISAAoKfRT8fwCaAQASAAoKfRT8fwCaAQAAAA==.Suvulaan:BAABNQAECn8iAAMmAAgKlwaLIADwAAAmAAgKlwaLIADwAAAQAAIKZAJpHgAfAAAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tarinaa:BAAANQAECgIIAgAAAA==.Tatoo:BAABNQAECn9UAAINAAoKRyM7DAAjAwANAAoKRyM7DAAjAwAAAA==.',
Te='Teeice:BAABNQAECn80AAIdAAoKphn2CgAVAgAdAAoKphn2CgAVAgAAAA==.Teo:BAABNQAECn8oAAITAAoKNQ5PMAChAQATAAoKNQ5PMAChAQAAAA==.',
Th='Thariot:BAAANQADCgQIBAABNQAECgoKNwAGAFogAA==.Thekan:BAABNQAECn8mAAIWAAkKhRauNgD6AQAWAAkKhRauNgD6AQAAAA==.Theriot:BAABNQAECn83AAMGAAoKWiDsBwC8AgAGAAoKWiDsBwC8AgAbAAIKNhg8bgFwAAAAAA==.Thianá:BAAANQAECgUICwAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECgoKJwAOAD4cAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Tomoya:BAAANQAECgUIBQAAAA==.Toosus:BAACNQAFFH8eAAIRAAcK9RwQBwCcAQARAAcK9RwQBwCcAQA1AAQKfzcAAhEACgq0JC4GAB8DABEACgq0JC4GAB8DAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trethan:BAAANQADCgQIAwAAAA==.Trolldung:BAAANQAECgIIAQAAAA==.',
Tt='Tturtle:BAACNQAFFH8SAAIbAAYKNg3lDgBfAQAbAAYKNg3lDgBfAQA1AAQKfzIAAhsACgqjGjhmAGkCABsACgqjGjhmAGkCAAAA.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAABNQAECn8cAAQSAAgKbhHFrgAiAQASAAUK2RDFrgAiAQAGAAQKjhNvLwDsAAAbAAQK+hOzAwHOAAAAAA==.',
Un='Unholysam:BAAANQAECgEIAQABNQAECgoKSQAfANwfAA==.',
Va='Vampier:BAAANQAECgUIBAAAAA==.',
Ve='Velata:BAABNQAECn88AAIIAAoKsxQNCQBIAgAIAAoKsxQNCQBIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.Vezzena:BAAANQADCgMIAwABNQAECgoKGwAIAJcLAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Violencê:BAABNQAECn9BAAIaAAoKwyMwAQBCAwAaAAoKwyMwAQBCAwAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAABNQAECn8VAAIUAAgKjBICbQB9AQAUAAgKjBICbQB9AQAAAA==.Vyzeera:BAABNQAECn8bAAMIAAoKlwvlDgCFAQAIAAoKYQvlDgCFAQAHAAoKwAaaiwB9AQAAAA==.',
Wa='Warriored:BAAANQADCgIIAgAAAA==.',
We='Wes:BAABNQAECn8oAAIdAAkKZRK+DgDOAQAdAAkKZRK+DgDOAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn8/AAINAAoKdhpuMwDSAgANAAoKdhpuMwDSAgAAAA==.Willybcastin:BAABNQAECn8sAAIHAAoK9CAfHQDEAgAHAAoK9CAfHQDEAgABNQAFFAYIEgAhAJ4gAA==.Willybwankin:BAACNQAFFH8SAAIhAAYKniBtAgAjAgAhAAYKniBtAgAjAgA1AAQKf08AAiEACgrSJl8AAJQDACEACgrSJl8AAJQDAAAA.',
Wo='Wowgazm:BAABNQAECn8WAAIGAAgKDwj6PAAMAQAGAAgKDwj6PAAMAQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8sAAMUAAkK2A7xYwCWAQAUAAkK2A7xYwCWAQAYAAEKAADELgA5AAAAAA==.',
Xa='Xanstar:BAAANQADCgQIBAAAAA==.',
Xe='Xerath:BAAANQAECgQIBQAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgQICQAAAA==.Zalarian:BAABNQAECn9EAAMbAAoK7COqGAD4AgAbAAoK7COqGAD4AgAGAAkKYB4+CACzAgAAAA==.Zaldrevan:BAAANQADCgUIBQAAAA==.',
Ze='Zemos:BAAANQADCgYIDQAAAA==.Zeseroth:BAAANQAECgIIAgAAAA==.Zeserotho:BAACNQAFFH8dAAIiAAcK9BOLBABuAQAiAAcK9BOLBABuAQA1AAQKfzQAAiIACgr4IMsNAG4CACIACgr4IMsNAG4CAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn9EAAMGAAoKfRmSGQAoAgAGAAoKfRmSGQAoAgASAAoKfRjzQQD5AQABNQAECgoKTgAkAHQhAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgQIBgAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8eAAMKAAgKrR2BNwCZAgAKAAgKrR2BNwCZAgAJAAIKACLXqAC3AAAAAA==.',
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
