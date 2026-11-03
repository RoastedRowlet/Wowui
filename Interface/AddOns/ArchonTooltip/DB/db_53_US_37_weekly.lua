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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Warrior-Fury','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Feral','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Evoker-Preservation',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn9FAAIBAAoKiiYkAACQAwABAAoKiiYkAACQAwAAAA==.',
Ae='Aezu:BAACNQAFFH8dAAMCAAYKIBgSCABLAQACAAYKIBgSCABLAQADAAIK9QmgDgCEAAA1AAQKfzkABAIACgomI2QIAPsCAAIACgomI2QIAPsCAAMABgqcHndXAKoAAAQAAQr9G6lPAFkAAAAA.',
Ai='Ailuria:BAABNQAECn8yAAIFAAkKPSVfBQBKAwAFAAkKPSVfBQBKAwAAAA==.Aitharen:BAAANQAECgYICwAAAA==.',
Al='Alikith:BAABNQAECn80AAIGAAkKpBL/JQCwAQAGAAkKpBL/JQCwAQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alun:BAAANQADCgYIBwAAAA==.Alyas:BAAANQAECgUICAAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn88AAMHAAkKqQ6/dgCQAQAHAAkKgwu/dgCQAQAIAAMKfBbKKQCpAAAAAA==.Amelía:BAABNQAECn8tAAMJAAoKDhp9PQDvAQAJAAkKzRh9PQDvAQAKAAgKExQebgAEAQAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amulet:BAAANQAECgEIAgAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgoKLQAJAA4aAA==.',
An='Angando:BAABNQAECn8mAAMLAAgKKwtXyABnAQALAAgKoAlXyABnAQAMAAEKAg0uOQA2AAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anneliesë:BAAANQABCgMIAwAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgUICAAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arihan:BAAANQAECgYIBwABNQAECgoKMwALAJcjAA==.Arnarn:BAAANQAECggIDgAAAA==.Artemidoros:BAABNQAECn8yAAINAAgKECPSMwDQAgANAAgKECPSMwDQAgAAAA==.',
As='Asuná:BAABNQAECn8bAAIOAAoK1BNbbgDTAQAOAAoK1BNbbgDTAQAAAA==.',
Au='Augtism:BAABNQAECn8uAAMPAAoKjgu0FwDOAQAPAAoKdwq0FwDOAQAQAAMKKQatHACBAAAAAA==.',
Av='Avataroffire:BAABNQAECn8bAAMHAAgKahaK/QCSAQAHAAcKKxaK/QCSAQAIAAIKPRWnLwCCAAAAAA==.',
Aw='Awakened:BAAANQADCgcIAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Badhabit:BAAANQADCgIIAgAAAA==.Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8bAAIIAAYKqRnPAABBAQAIAAYKqRnPAABBAQA1AAQKfzEAAggACgrXH+YCALcCAAgACgrXH+YCALcCAAAA.',
Be='Beefbrownie:BAABNQAECn8rAAIMAAgKIxzjCwB6AgAMAAgKIxzjCwB6AgAAAA==.Bellezora:BAABNQAECn8jAAIOAAgKEyGtOgB+AgAOAAgKEyGtOgB+AgAAAA==.Bellwynn:BAABNQAECn8cAAICAAkKxxhANABFAgACAAkKxxhANABFAgAAAA==.Berzerked:BAABNQAECn9bAAILAAoKkSVaBADUAwALAAoKkSVaBADUAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.Bigjimslade:BAAANQAECgYIEgABNQAECgoKSwANABYiAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn89AAIRAAoKXx85DQCoAgARAAoKXx85DQCoAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIBgAAAA==.Brasa:BAAANQAECgEIBAAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh3gCwBJAgABAAgKHh3gCwBJAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQAECgEIAQAAAA==.Bus:BAACNQAFFH8GAAIBAAYKLCbUAADJAQABAAYKLCbUAADJAQA1AAQKfzQAAgEACgoBJwwAABgEAAEACgoBJwwAABgEAAE1AAUUCAgmAAYA+CYA.',
Ca='Calliope:BAAANQABCgIIAwAAAA==.Calnaultenjr:BAAANQADCgEIAQABNQAECgoKQAASALAcAA==.Camholy:BAABNQAECn8oAAMTAAgKTAn6NwBlAQATAAgKTAn6NwBlAQAOAAIK4wTM0QBMAAAAAA==.Castrial:BAAANQAECgEIAQAAAA==.',
Ce='Celtykun:BAABNQAECn8YAAIMAAcKrQp7HADkAAAMAAcKrQp7HADkAAAAAA==.',
Ch='Chainmalejr:BAAANQADCgEIAQABNQAECgoKPAAHAEMeAA==.Chiron:BAAANQAECgEIAQABNQAECgkJHAAUAC4VAA==.Chiyukii:BAAANQAECggIBwAAAA==.',
Co='Combusted:BAAANQAECgQIBAAAAA==.Connie:BAAANQAECgUIDgAAAA==.',
Cy='Cynfulsqt:BAAANQADCgYIBgABNQAECgkJFwATAP4WAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgYIEAAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAABNQAECn8VAAMVAAcK0hLbCQD7AAAVAAYKbBTbCQD7AAAWAAEKZwxiLAA+AAAAAA==.Daydalus:BAAANQAECgIIAQAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deepmydk:BAAANQAECgEIAgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Demonickills:BAAANQAECgEIAwAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.Derik:BAAANQADCgEIAQABNQAECgoKQAALABAZAA==.',
Dh='Dhing:BAABNQAECn8ZAAIXAAkK+gp/SQCWAQAXAAkK+gp/SQCWAQAAAA==.',
Di='Dillexis:BAABNQAECn9AAAMLAAoKEBnIPwAWAgALAAoKURjIPwAWAgAYAAcKLRlKFQDhAAAAAA==.Dismagey:BAAANQAECggIDQAAAA==.',
Do='Donald:BAABNQAECn89AAICAAoKZBNmHwDPAQACAAoKZBNmHwDPAQAAAA==.Doomslash:BAABNQAECn87AAMLAAoKjxLyQwAGAgALAAoKjxLyQwAGAgAYAAMKNBhUJgBJAAAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQAECgIIAgABNQAECggIKgADAGolAA==.Dragonchest:BAABNQAECn8sAAIVAAoK4x+AAQB+AgAVAAoK4x+AAQB+AgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECgoKLAAVAOMfAA==.Dragonswolf:BAAANQAECgcIEQABNQAECgoKLAAVAOMfAA==.Dragonwing:BAAANQAECgMIBAABNQAECgoKLAAVAOMfAA==.Drbubblesmd:BAAANQAECgYIEAAAAA==.Dregon:BAACNQAFFH8dAAIFAAYK8SQ6AQBOAgAFAAYK8SQ6AQBOAgA1AAQKfzQAAgUACgqlJukAANADAAUACgqlJukAANADAAAA.Dreinara:BAAANQAECgQICQAAAA==.',
Du='Dummysezwhut:BAAANQAECgUIDwAAAA==.',
Ea='Eastofeden:BAABNQAECn8aAAIUAAkKHxT2TgCvAQAUAAkKHxT2TgCvAQAAAA==.',
Ec='Echinopsis:BAAANQAECgQICwAAAA==.Eclipze:BAAANQAECgQIBAAAAA==.',
Ei='Eiduartkay:BAAANQAECgcIDAABNQAFFAQICAANAGoXAA==.Eight:BAAANQAECgQIBQAAAA==.Eilyn:BAABNQAECn8xAAIZAAkKhg2snQBRAQAZAAkKhg2snQBRAQAAAA==.',
El='Elffaba:BAAANQADCgIIBAAAAA==.Elystraeya:BAAANQAECggICQAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAABNQAECn8YAAINAAgKLgPWFQHYAAANAAgKLgPWFQHYAAAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Fazlain:BAABNQAECn8fAAIZAAkKUBWpdgChAQAZAAkKUBWpdgChAQAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgIIAwABNQAECgkJHAAUAC4VAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fi='Fighter:BAAANQADCgEIAQABNQAECgoKLQAJAPYdAA==.',
Fr='Friartuck:BAAANQAECgYIDAABNQAECgoKSwANABYiAA==.Frosteez:BAAANQAECgEIAgABNQAECggIGwAYACEgAA==.',
Fu='Furryem:BAABNQAECn8qAAIDAAgKaiXaBgBVAwADAAgKaiXaBgBVAwAAAA==.',
['Fô']='Fôxx:BAAANQAECgcICQAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn8+AAMZAAkKGRbUfACTAQAZAAkKGRbUfACTAQASAAUKNQ3kgQAAAQAAAA==.Gatelinka:BAAANQAECgUIBQABNQAECgoKIAAJAGUeAA==.Gateto:BAABNQAECn8gAAMJAAoKZR5IOgB2AgAJAAoKZR5IOgB2AgAKAAQKEAht4wDQAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAaAAAAAA==.',
Gl='Glynistann:BAAANQAECgUICAAAAA==.',
Gu='Gundox:BAAANQAECgUICAAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hanoa:BAAANQAECgUICQAAAA==.Hartley:BAAANQAECgUICQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAABNQAECn8wAAIVAAkK+w8DBQB4AQAVAAkK+w8DBQB4AQAAAA==.',
Ho='Holeshot:BAAANQABCgEIAQAAAA==.Holycow:BAAANQAECgUIBwAAAA==.Holyspaunk:BAAANQADCgIIAgAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn88AAINAAkKZhuXOwAsAgANAAkKZhuXOwAsAgAAAA==.',
Hy='Hyacaina:BAAANQAECgEIAgAAAA==.',
Ik='Ikickgnômes:BAABNQAECn8aAAIKAAgKcgXWcAD9AAAKAAgKcgXWcAD9AAAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgoKPAAHAEMeAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECn8nAAQVAAoKniIjBQDKAgAVAAgKJiMjBQDKAgAUAAUKaR+powCOAQAWAAEK/xRfLgA5AAAAAA==.',
Is='Ishamael:BAAANQADCgIIAgAAAA==.',
Iv='Ivon:BAAANQADCgYIDAABNQAECgoKQAALABAZAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.Jadedbabe:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8VAAMbAAUK8RoLDwD5AAAbAAMK8RoLDwD5AAAcAAMKfhkAAgDlAAA1AAQKfyUABBsACgoWH1sdAJQCABsACQqpH1sdAJQCABwACQoXG74FAIcCAB0AAQr8H9KmAGAAAAAA.',
Ji='Jickle:BAAANQAECgEIAQAAAA==.',
Jo='Joppa:BAAANQADCgQIBAABNQAFFAgIGQATALoQAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgUICAAAAA==.',
Ke='Kealli:BAAANQADCgUIBQAAAA==.Keý:BAACNQAFFH8dAAILAAYK3SFDCQBuAQALAAYK3SFDCQBuAQA1AAQKfzAAAgsACgqIIwcZAM4CAAsACgqIIwcZAM4CAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAABNQAECn8jAAINAAoK0BSNRgAJAgANAAoK0BSNRgAJAgAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQAECgEIAQAAAA==.Kiy:BAABNQAECn8kAAIUAAoKSRGMjgDCAQAUAAoKSRGMjgDCAQAAAA==.',
Kn='Knockout:BAAANQADCggICAAAAA==.Knìghtmare:BAAANQAECgEIAQAAAA==.',
Kr='Krakenlock:BAABNQAECn82AAIUAAkKQQeNewA0AQAUAAkKQQeNewA0AQAAAA==.Krenin:BAAANQADCgMIBAAAAA==.Kronas:BAAANQAECgIIBAAAAA==.',
Ku='Kumojoru:BAACNQAFFH8dAAIEAAYKgh06AQBCAQAEAAYKgh06AQBCAQA1AAQKfzcABAQACgomJdgCADcDAAQACgomJdgCADcDAB4AAwp4HR0hAAwBAAIAAQrcA8O/ACIAAAAA.',
Ky='Kyranos:BAAANQAECgEIAQAAAA==.',
La='Lazyheal:BAAANQAECgIIAwABNQAECgoKLQAJAPYdAA==.',
Le='Leigor:BAACNQAFFH8dAAIOAAYKoRf3CADcAQAOAAYKoRf3CADcAQA1AAQKfzkAAg4ACgr5IWQgAO4CAA4ACgr5IWQgAO4CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Limbow:BAAANQAECggICgABNQAFFAcIEQALADIOAA==.Linthsong:BAABNQAECn8aAAIIAAgK7AkqFwDtAAAIAAgK7AkqFwDtAAAAAA==.Lionature:BAAANQAECgEIAgAAAA==.Lionknite:BAABNQAECn84AAQfAAoKuxqIFQAXAgAfAAoKuxqIFQAXAgAXAAIKnQexsgAtAAARAAEK6QNUngAkAAAAAA==.Liteshocklet:BAABNQAECn8tAAMJAAoK9h0TKQC/AgAJAAoK9h0TKQC/AgAKAAEKygkV4QA2AAAAAA==.Littledung:BAAANQAECgIIAgAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYICAAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8oAAMDAAoKxA5ZLwCgAQADAAoKxA5ZLwCgAQACAAYKqAIlhwC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMFAAcKshwDHADEAQAFAAYKyBsDHADEAQAgAAIK8gDKZgBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQAECgYICAABNQAECgoKNAAhAHwVAA==.Mauzii:BAAANQADCgMIBAABNQAECgoKNAAhAHwVAA==.Maylea:BAAANQADCggICAAAAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn81AAIfAAoKYyG6BwDgAgAfAAoKYyG6BwDgAgAAAA==.',
Me='Melliah:BAAANQAECgUICAAAAA==.Mes:BAABNQAECn8bAAIKAAcKHR0LSABWAgAKAAcKHR0LSABWAgAAAA==.Metatrøn:BAAANQADCggIHQAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgoKRQABAIomAA==.Mimmi:BAABNQAECn8wAAIJAAoK6hbkKgBLAgAJAAoK6hbkKgBLAgABNQAECgoKNAAhAHwVAA==.Misaligned:BAABNQAECn8YAAIHAAgKnwWdtgAOAQAHAAgKnwWdtgAOAQAAAA==.Misidian:BAAANQADCgQIBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgoKJAAHAHwWAA==.Moonsorrow:BAABNQAECn8lAAIDAAoKDh99BwAxAwADAAoKDh99BwAxAwAAAA==.Moritura:BAABNQAECn80AAMhAAoKfBUVIgC+AQAhAAoKfBUVIgC+AQAiAAUKZhGTGQCbAAAAAA==.',
My='Mythicalpal:BAAANQAECgEIAQAAAA==.Mywifesaidno:BAAANQAECgQIBAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAcIEQATAH4TAA==.Nemistrasza:BAAANQADCggICwABNQAECgkJMgAFAD0lAA==.Nerfme:BAAANQADCgEIAQABNQAECgoKQAASALAcAA==.',
Ni='Nilanza:BAAANQAECgIIAgABNQAECgoKMwALAJcjAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQAECgYICQAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAAaAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAbAEsVAA==.',
Ob='Obergefel:BAABNQAECn8ZAAIjAAkK9xh9FADrAQAjAAkK9xh9FADrAQAAAA==.',
Ol='Ollie:BAAANQAECgEIAgAAAA==.',
Op='Ophiuchus:BAABNQAECn8cAAIUAAkKLhXsfgDpAQAUAAkKLhXsfgDpAQAAAA==.Oppsie:BAAANQAECgYIBwAAAA==.',
Or='Orcdung:BAAANQAECgEIAQAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAABNQAECn8WAAMSAAcKuxuqSAC+AQASAAcKuxuqSAC+AQAZAAEKWgWVbwEyAAAAAA==.Pallycow:BAAANQAECgIIAgAAAA==.Pamelina:BAAANQABCgcICAAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgoKQAALABAZAA==.Pandunkadunk:BAAANQAECgIIBAAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8bAAMYAAgKISAxFgA5AQALAAcKKBs+owDEAQAYAAUKGyIxFgA5AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggIMwAAAA==.Pengulo:BAABNQAECn8zAAILAAoKlyNoHQBCAwALAAoKlyNoHQBCAwAAAA==.Pernicious:BAABNQAECn8eAAMVAAkKkQ8MHACNAQAVAAcKlw8MHACNAQAUAAcKJA0HigASAQAAAA==.',
Ph='Phade:BAAANQADCgMIAwAAAA==.Phillis:BAAANQAECgIIAgAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAAANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAABNQAECn8oAAIUAAgK1RJPbgBUAQAUAAgK1RJPbgBUAQAAAA==.Pinkiemena:BAAANQAFFAIIAgAAAA==.Piolin:BAAANQAECgcIDgAAAA==.',
Po='Potent:BAAANQAECgEIAgAAAA==.',
Pu='Punchykicky:BAABNQAECn8aAAMFAAcKzBobDgD7AQAFAAcKzBobDgD7AQABAAYK+AXIFgCWAAABNQAECgkJRgAGAMscAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8eAAQOAAoKPQbUkQBhAQAOAAkKIQbUkQBhAQATAAYKYAaFSAD7AAAkAAEKVQGKNAANAAAAAA==.',
Ra='Radiantfreya:BAAANQAECgEIAQAAAA==.Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAABNQAECn8tAAMSAAkKOR4zFgDaAgASAAkKOR4zFgDaAgAZAAEKAABXsAEvAAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reliun:BAAANQAECgYICgABNQAECggIKAATAEwJAA==.Reniel:BAAANQADCgMIAwABNQAECgkJNAAGAKQSAA==.Reverendlion:BAAANQAECgcIDgAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAABNQAECn8pAAILAAkKYxxjIQCfAgALAAkKYxxjIQCfAgAAAA==.Rosencrant:BAABNQAECn8cAAINAAgKeQv5ZgCuAQANAAgKeQv5ZgCuAQAAAA==.',
Ru='Rubberdukkie:BAAANQAECgUICwAAAA==.Ruemor:BAAANQADCgcIBwAAAA==.Rule:BAAANQAECgUICAAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgoKNAAZABsbAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECn84AAIiAAoKjRvnBQAXAgAiAAoKjRvnBQAXAgAAAA==.Sampal:BAABNQAECn9GAAIGAAkKyxx5DwClAgAGAAkKyxx5DwClAgAAAA==.Samwield:BAEBNQAECn9CAAMdAAoK3B+FCwC8AgAdAAoKxh+FCwC8AgAbAAMK6xRReADRAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgMIBQAAAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn8xAAIJAAkK2RXEVQARAgAJAAkK2RXEVQARAgAAAA==.Selaheal:BAABNQAECn89AAITAAkKlBAeGACmAQATAAkKlBAeGACmAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadowydream:BAAANQAECgUIBwAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgoKMwAGACseAA==.Shinobu:BAAANQADCgYICgABNQAECgkJHAACAMcYAA==.Shintó:BAAANQADCgEIAQAAAA==.Shnood:BAABNQAECn8WAAMVAAgKMxgzDQAlAgAVAAgKMxgzDQAlAgAUAAEKAABwOgFAAAAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCggIDwAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn9IAAMjAAoKdCFxCQBBAwAjAAoKdCFxCQBBAwAiAAMKewO/LQAjAAAAAA==.',
Sk='Skies:BAAANQAECgMIAwABNQAFFAYIDQAdACYQAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECggIKgADAGolAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgoKJAAKAM4ZAA==.Sterïzard:BAAANQADCgEIAQABNQAECgoKJAAKAM4ZAA==.Stupid:BAACNQAFFH8JAAISAAQKyxW0DQAuAQASAAQKyxW0DQAuAQA1AAQKf0AAAhIACgp2IXMJAGwDABIACgp2IXMJAGwDAAAA.Stærk:BAABNQAECn8kAAIKAAoKzhkiOQCSAgAKAAoKzhkiOQCSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgoKPAAHAEMeAA==.Sunpally:BAABNQAECn8pAAISAAoKfRT8fwCaAQASAAoKfRT8fwCaAQAAAA==.Suvulaan:BAABNQAECn8dAAMlAAgKCgbIHQDsAAAlAAgKCgbIHQDsAAAQAAIKxQEcHAAeAAAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tarinaa:BAAANQAECgIIAwAAAA==.Tatoo:BAABNQAECn9LAAINAAoKFiJmDgADAwANAAoKFiJmDgADAwAAAA==.',
Te='Teeice:BAABNQAECn80AAIbAAoKphl2CQAdAgAbAAoKphl2CQAdAgAAAA==.Teo:BAABNQAECn8kAAITAAkK+g1PMAChAQATAAkK+g1PMAChAQAAAA==.',
Th='Thariot:BAAANQADCgQIBAABNQAECgoKMwAGACseAA==.Thekan:BAABNQAECn8lAAIhAAgKMheuNgD6AQAhAAgKMheuNgD6AQAAAA==.Theriot:BAABNQAECn8zAAMGAAoKKx6ACACQAgAGAAoKKx6ACACQAgAZAAIKNhg8bgFwAAAAAA==.Thianá:BAAANQAECgUIDgAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECggIIwAOABMhAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Tomoya:BAAANQAECgUIBQAAAA==.Toosus:BAACNQAFFH8dAAIRAAYKhB+cBwBTAQARAAYKhB+cBwBTAQA1AAQKfzYAAhEACgo6JGoGABIDABEACgo6JGoGABIDAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trethan:BAAANQADCgQIAwAAAA==.Trolldung:BAAANQAECgEIAwAAAA==.',
Tt='Tturtle:BAACNQAFFH8SAAIZAAYKNg3lDgBfAQAZAAYKNg3lDgBfAQA1AAQKfy8AAhkACgqjGjhmAGkCABkACgqjGjhmAGkCAAAA.',
Tu='Turnpike:BAAANQAECgEIAgAAAA==.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAABNQAECn8WAAQSAAgK3w7FrgAiAQASAAUK2RDFrgAiAQAGAAQKjhMcKgDwAAAZAAEKAADpjwFEAAAAAA==.',
Un='Unclebuck:BAAANQAECgEIAQAAAA==.Unholysam:BAEANQAECgEIAQABNQAECgoKQgAdANwfAA==.',
Va='Vallo:BAAANQAECgEIAgAAAA==.Vampier:BAAANQAECgUIBAAAAA==.',
Ve='Velata:BAABNQAECn87AAIIAAoKsxQNCQBIAgAIAAoKsxQNCQBIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.Vezzena:BAAANQADCgMIAwABNQAECgoKFAAIAGELAA==.',
Vi='Victory:BAAANQAECgIIAgAAAA==.Violencê:BAABNQAECn85AAIYAAkKeCKjAwCdAgAYAAkKeCKjAwCdAgAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAAANQAECgYIEAAAAA==.Vyzeera:BAABNQAECn8UAAMIAAoKYQt2DACJAQAIAAoKYQt2DACJAQAHAAoKtQXWhwBpAQAAAA==.',
We='Wes:BAABNQAECn8lAAIbAAkKcRHREQCPAQAbAAkKcRHREQCPAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn89AAINAAoKdhpuMwDSAgANAAoKdhpuMwDSAgAAAA==.Willybcastin:BAABNQAECn8mAAIHAAoK9CDTHQCwAgAHAAoK9CDTHQCwAgABNQAFFAYIEgAfAJ4gAA==.Willybwankin:BAACNQAFFH8SAAIfAAYKniBtAgAjAgAfAAYKniBtAgAjAgA1AAQKf0YAAh8ACgrSJrIAAIMDAB8ACgrSJrIAAIMDAAAA.',
Wo='Wowgazm:BAABNQAECn8WAAIGAAgKDwj6PAAMAQAGAAgKDwj6PAAMAQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8pAAMUAAgKVA3acgBIAQAUAAgKVA3acgBIAQAWAAEKAADELgA5AAAAAA==.',
Xa='Xanstar:BAAANQAECgEIAgAAAA==.',
Xe='Xerath:BAAANQAECgMIBgAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgQICQAAAA==.Zalarian:BAABNQAECn9EAAMZAAoK7CPIEgAFAwAZAAoK7CPIEgAFAwAGAAkKYB7jBgC/AgAAAA==.Zaldrevan:BAAANQADCgUIBQAAAA==.',
Ze='Zemos:BAAANQAECgEIAwAAAA==.Zeseroth:BAAANQAECgIIAgAAAA==.Zeserotho:BAACNQAFFH8cAAIgAAYK/hfVBAAtAQAgAAYK/hfVBAAtAQA1AAQKfzQAAiAACgr4ICkMAHICACAACgr4ICkMAHICAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn8+AAMGAAoKfRmSGQAoAgAGAAoKfRmSGQAoAgASAAkKQRYdZADsAQABNQAECgoKSAAjAHQhAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgQIBgAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8eAAMKAAgKrR2BNwCZAgAKAAgKrR2BNwCZAgAJAAIKACKMmwC8AAAAAA==.',
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
