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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Mage-Arcane','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Priest-Shadow','Warlock-Demonology','DeathKnight-Frost','Warrior-Fury','Warlock-Destruction','Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Feral','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline','Hunter-Marksmanship','DemonHunter-Devourer','Evoker-Preservation',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQAECgQIBAAAAA==.Adrianmonk:BAABNQAECn87AAIBAAoK6SUKAQDHAwABAAoK6SUKAQDHAwAAAA==.',
Ae='Aezu:BAACNQAFFH8dAAMCAAYKIBidBQBUAQACAAYKIBidBQBUAQADAAIK9QlzCwCJAAA1AAQKfzMABAIACgomIxkFABMDAAIACgomIxkFABMDAAMAAwpfEXdXAKoAAAQAAQr9G2VCAFoAAAAA.',
Ai='Ailuria:BAABNQAECn8rAAIFAAkK5CRfBQBKAwAFAAkK5CRfBQBKAwAAAA==.Aitharen:BAAANQAECgQIBgAAAA==.',
Al='Alikith:BAABNQAECn8sAAIGAAkKFRKZGQAyAQAGAAkKFRKZGQAyAQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alun:BAAANQADCgYIBwAAAA==.Alyas:BAAANQAECgQIBwAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECn80AAMHAAkKUw7fYACLAQAHAAkKLgvfYACLAQAIAAMKfBbKKQCpAAAAAA==.Amelía:BAABNQAECn8pAAMJAAoKDhoQLAD4AQAJAAkKzRgQLAD4AQAKAAgKExSUVQAMAQAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amulet:BAAANQABCgUICQAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgoKKQAJAA4aAA==.',
An='Angando:BAABNQAECn8jAAMLAAgKIgtXyABnAQALAAgKoAlXyABnAQAMAAEKywxOQwA0AAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anneliesë:BAAANQABCgMIAwAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgQIBwAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arihan:BAAANQAECgYIBgABNQAECgoKLwALAJcjAA==.Arnarn:BAAANQAECggIDgAAAA==.Artemidoros:BAABNQAECn8rAAINAAcKQCTSMwDQAgANAAcKQCTSMwDQAgAAAA==.',
As='Asuná:BAABNQAECn8ZAAIOAAoK5BBbbgDTAQAOAAoK5BBbbgDTAQAAAA==.',
Au='Augtism:BAABNQAECn8uAAMPAAoKjgu0FwDOAQAPAAoKdwq0FwDOAQAQAAMKKQatHACBAAAAAA==.',
Av='Avataroffire:BAABNQAECn8ZAAMHAAcKcRiK/QCSAQAHAAYKpBiK/QCSAQAIAAIKPRWnLwCCAAAAAA==.',
Aw='Awakened:BAAANQADCgcIAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Badhabit:BAAANQADCgIIAgAAAA==.Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFH8bAAIIAAYKqRlrAABSAQAIAAYKqRlrAABSAQA1AAQKfzAAAggACgrXH6YBANACAAgACgrXH6YBANACAAAA.',
Be='Beefbrownie:BAABNQAECn8pAAIMAAgKIxzjCwB6AgAMAAgKIxzjCwB6AgAAAA==.Bellezora:BAABNQAECn8hAAIOAAgKEyGtOgB+AgAOAAgKEyGtOgB+AgAAAA==.Bellwynn:BAABNQAECn8cAAICAAkKxxhANABFAgACAAkKxxhANABFAgAAAA==.Berzerked:BAABNQAECn9RAAILAAoKZSVaBADUAwALAAoKZSVaBADUAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.Bigjimslade:BAAANQAECgQIDAABNQAECgoKQQANACIhAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECn85AAIRAAoKuh6ZCgChAgARAAoKuh6ZCgChAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECggIBQAAAA==.Brasa:BAAANQAECgIIAQAAAA==.Brick:BAABNQAECn8gAAIBAAgKHh3gCwBJAgABAAgKHh3gCwBJAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCggIGQAAAA==.Bus:BAACNQAFFH8GAAIBAAYKLCZ8AADNAQABAAYKLCZ8AADNAQA1AAQKfygAAgEACgrwJgwAABgEAAEACgrwJgwAABgEAAE1AAUUCAgfAAYA0yYA.',
Ca='Calliope:BAAANQABCgIIAwAAAA==.Calnaultenjr:BAAANQADCgEIAQABNQAECgoKOwASAIAaAA==.Camholy:BAABNQAECn8nAAMTAAcKwQn6NwBlAQATAAcKwQn6NwBlAQAOAAIK4wQDuABRAAAAAA==.Castrial:BAAANQADCgIIAgAAAA==.',
Ce='Celtykun:BAAANQAECgUIDwAAAA==.',
Ch='Chainmalejr:BAAANQADCgEIAQABNQAECgoKOAAHAEMeAA==.Chiron:BAAANQADCggIFwABNQAECgkJFwAUABMUAA==.Chiyukii:BAAANQAECggIBwAAAA==.',
Co='Combusted:BAAANQAECgQIBAAAAA==.Connie:BAAANQAECgUIDgAAAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgUICQAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAAANQAECgUIEQAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Demonickills:BAAANQABCggIDAAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.Derik:BAAANQADCgEIAQABNQAECgoKOQALAMUYAA==.',
Dh='Dhing:BAABNQAECn8ZAAIVAAkK+gp/SQCWAQAVAAkK+gp/SQCWAQAAAA==.',
Di='Dillexis:BAABNQAECn85AAMLAAoKxRiWMQARAgALAAoKURiWMQARAgAWAAQKshgaGgACAQAAAA==.Dismagey:BAAANQAECggIDAAAAA==.',
Do='Donald:BAABNQAECn8zAAICAAoK2hIEGADZAQACAAoK2hIEGADZAQAAAA==.Doomslash:BAABNQAECn8xAAILAAoKbg/vPQDYAQALAAoKbg/vPQDYAQAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQAECgIIAgABNQAECggIKAADAGolAA==.Dragonchest:BAABNQAECn8pAAIXAAoK4x/rAACIAgAXAAoK4x/rAACIAgAAAA==.Dragonsfury:BAAANQABCgEIAQABNQAECgoKKQAXAOMfAA==.Dragonswolf:BAAANQAECgYIDAABNQAECgoKKQAXAOMfAA==.Dragonwing:BAAANQAECgMIAwABNQAECgoKKQAXAOMfAA==.Drbubblesmd:BAAANQAECgYIDgAAAA==.Dregon:BAACNQAFFH8dAAIFAAYK8SS4AABiAgAFAAYK8SS4AABiAgA1AAQKfzMAAgUACgqlJukAANADAAUACgqlJukAANADAAAA.Dreinara:BAAANQAECgQICAAAAA==.',
Du='Dummysezwhut:BAAANQAECgUIDQAAAA==.',
Ea='Eastofeden:BAABNQAECn8XAAIUAAgKlBSVTAB/AQAUAAgKlBSVTAB/AQAAAA==.',
Ec='Echinopsis:BAAANQAECgMIBwAAAA==.',
Ei='Eiduartkay:BAAANQAECgYICwAAAA==.Eight:BAAANQAECgQIBQAAAA==.Eilyn:BAABNQAECn8pAAIYAAgKaQ2hjQA2AQAYAAgKaQ2hjQA2AQAAAA==.',
El='Elffaba:BAAANQADCgIIBAABNQADCgUIDwAZAAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Ev='Evilgoatlady:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAABNQAECn8WAAINAAgKhALWFQHYAAANAAgKhALWFQHYAAAAAA==.Fangmage:BAAANQADCgUIBwAAAA==.Fazlain:BAABNQAECn8ZAAIYAAkKUBXgeABgAQAYAAkKUBXgeABgAQAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgIIAwABNQAECgkJFwAUABMUAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fi='Fighter:BAAANQADCgEIAQABNQAECgoKLQAJAPYdAA==.',
Fr='Friartuck:BAAANQAECgQICQABNQAECgoKQQANACIhAA==.Frosteez:BAAANQABCgIIAgABNQAECggIGgAWACEgAA==.',
Fu='Furryem:BAABNQAECn8oAAIDAAgKaiXaBgBVAwADAAgKaiXaBgBVAwAAAA==.',
['Fô']='Fôxx:BAAANQAECgUICAAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECn88AAMYAAkKwhX/YQCVAQAYAAkKwhX/YQCVAQASAAUKNQ1jaAAJAQAAAA==.Gatelinka:BAAANQAECgUIBQABNQAECgoKGwAJAHwdAA==.Gateto:BAABNQAECn8bAAMJAAoKfB1IOgB2AgAJAAoKfB1IOgB2AgAKAAQKEAht4wDQAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAZAAAAAA==.',
Gl='Glynistann:BAAANQAECgQIBwAAAA==.',
Gu='Gundox:BAAANQAECgQIBwAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hanoa:BAAANQAECgUICQAAAA==.Hartley:BAAANQAECgQIBAAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAABNQAECn8nAAIXAAkKbw4sBABoAQAXAAkKbw4sBABoAQAAAA==.',
Ho='Holeshot:BAAANQABCgEIAQAAAA==.Holycow:BAAANQAECgQIBAAAAA==.Holyspaunk:BAAANQADCgIIAgAAAA==.',
Hu='Hughstin:BAAANQAECgQIBAAAAA==.Huntinbub:BAABNQAECn80AAINAAkKzBR3OQD7AQANAAkKzBR3OQD7AQAAAA==.',
Hy='Hyacaina:BAAANQABCgUICQAAAA==.',
Ik='Ikickgnômes:BAAANQAECggIEQAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgoKOAAHAEMeAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECn8nAAQXAAoKniIjBQDKAgAXAAgKJiMjBQDKAgAUAAUKaR+powCOAQAaAAEK/xRfLgA5AAAAAA==.',
Is='Ishamael:BAAANQADCgIIAgAAAA==.',
Iv='Ivon:BAAANQADCgYIDAABNQAECgoKOQALAMUYAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFH8VAAMbAAUK8RoLDwD5AAAbAAMK8RoLDwD5AAAcAAMKfhkAAgDlAAA1AAQKfyUABBsACgoWH1sdAJQCABsACQqpH1sdAJQCABwACQoXG74FAIcCAB0AAQr8H9iGAGEAAAAA.',
Ji='Jickle:BAAANQAECgEIAQAAAA==.',
Jo='Joppa:BAAANQADCgQIBAABNQAFFAcIFwATABESAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgUIBwAAAA==.',
Ke='Keý:BAACNQAFFH8dAAILAAYK3SHnBQCAAQALAAYK3SHnBQCAAQA1AAQKfzAAAgsACgqII7cQAN8CAAsACgqII7cQAN8CAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAABNQAECn8fAAINAAoK+xEPSADGAQANAAoK+xEPSADGAQAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCggIDAAAAA==.Kiy:BAABNQAECn8hAAIUAAkKZBKMjgDCAQAUAAkKZBKMjgDCAQAAAA==.',
Kn='Knockout:BAAANQADCggICAAAAA==.Knìghtmare:BAAANQAECgEIAQAAAA==.',
Kr='Krakenlock:BAABNQAECn8uAAIUAAkK5wZqcAAbAQAUAAkK5wZqcAAbAQAAAA==.Krenin:BAAANQADCgEIAQAAAA==.Kronas:BAAANQAECgEIAQAAAA==.',
Ku='Kumojoru:BAACNQAFFH8dAAIEAAYKgh3UAABLAQAEAAYKgh3UAABLAQA1AAQKfzYABAQACgomJckBAEUDAAQACgomJckBAEUDAB4AAwp4HR0hAAwBAAIAAQrcA8O/ACIAAAAA.',
Ky='Kyranos:BAAANQADCggIHgAAAA==.',
La='Lazyheal:BAAANQAECgIIAwABNQAECgoKLQAJAPYdAA==.',
Le='Leigor:BAACNQAFFH8dAAIOAAYKoRflBQDjAQAOAAYKoRflBQDjAQA1AAQKfzMAAg4ACgr5IekWAK0CAA4ACgr5IekWAK0CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Limbow:BAAANQAECggICAABNQAFFAcIEQALADIOAA==.Linthsong:BAABNQAECn8YAAIIAAgK0gn4EQDtAAAIAAgK0gn4EQDtAAAAAA==.Lionknite:BAABNQAECn8xAAQfAAoKPxdWQQAXAgAfAAkKAxpWQQAXAgAVAAIKnQexsgAtAAARAAEK6QPhjAAkAAAAAA==.Liteshocklet:BAABNQAECn8tAAMJAAoK9h0TKQC/AgAJAAoK9h0TKQC/AgAKAAEKyglIwwA2AAAAAA==.Littledung:BAAANQAECgEIAQAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
['Lã']='Lãdyrift:BAABNQAECn8nAAMDAAkKZg9ZLwCgAQADAAkKZg9ZLwCgAQACAAYKqAIlhwC2AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECn8WAAMFAAcKshwDHADEAQAFAAYKyBsDHADEAQAgAAIK8gDKZgBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQAECgUIBQABNQAECgoKLAAhAFYSAA==.Mauzii:BAAANQADCgMIBAABNQAECgoKLAAhAFYSAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECn8uAAIfAAoKICHnBgDEAgAfAAoKICHnBgDEAgAAAA==.',
Me='Melliah:BAAANQAECgQIBwAAAA==.Mes:BAABNQAECn8bAAIKAAcKHR0LSABWAgAKAAcKHR0LSABWAgAAAA==.Metatrøn:BAAANQADCggIFwAAAA==.',
Mi='Mielyn:BAAANQADCgYIBgABNQAECgoKOwABAOklAA==.Mimmi:BAABNQAECn8mAAIJAAoK6hb8HwBFAgAJAAoK6hb8HwBFAgABNQAECgoKLAAhAFYSAA==.Misaligned:BAAANQAECgcIDgAAAA==.Misidian:BAAANQADCgQIBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgoKJAAHAHwWAA==.Moonsorrow:BAABNQAECn8iAAIDAAoKhh50BQAgAwADAAoKhh50BQAgAwAAAA==.Moritura:BAABNQAECn8sAAMhAAoKVhL3HgCfAQAhAAoKVhL3HgCfAQAiAAUKZhEhFACgAAAAAA==.',
My='Mywifesaidno:BAAANQAECgQIBAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Negatively:BAAANQAECgcIBwABNQAFFAcIEQATAH4TAA==.Nemistrasza:BAAANQADCggICwABNQAECgkJKwAFAOQkAA==.',
Ni='Nilanza:BAAANQAECgIIAgABNQAECgoKLwALAJcjAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQAECgYICQAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQIBAAZAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECgkJHgAbAEsVAA==.',
Ob='Obergefel:BAAANQAECgcIDwAAAA==.',
Ol='Ollie:BAAANQAECgEIAQAAAA==.',
Op='Ophiuchus:BAABNQAECn8XAAIUAAkKExTsfgDpAQAUAAkKExTsfgDpAQAAAA==.Oppsie:BAAANQAECgUIBQAAAA==.',
Or='Orcdung:BAAANQABCgUIDAAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAABNQAECn8UAAISAAcKuxvoNADMAQASAAcKuxvoNADMAQAAAA==.Pallycow:BAAANQAECgIIAgAAAA==.Pamelina:BAAANQABCgcICAAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgoKOQALAMUYAA==.Pandunkadunk:BAAANQAECgEIAQAAAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAABNQAECn8aAAMWAAgKISAxFgA5AQALAAcKKBtobwA6AQAWAAUKGyIxFgA5AQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggILAAAAA==.Pengulo:BAABNQAECn8vAAILAAoKlyNoHQBCAwALAAoKlyNoHQBCAwAAAA==.Pernicious:BAABNQAECn8aAAMXAAkKvw4MHACNAQAXAAcKlw8MHACNAQAUAAcK/gsLdAASAQAAAA==.',
Ph='Phillis:BAAANQAECgIIAgAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAEANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAABNQAECn8iAAIUAAcKmBRubgAgAQAUAAcKmBRubgAgAQAAAA==.Pinkiemena:BAAANQAFFAEIAQAAAA==.Piolin:BAAANQAECgUICQAAAA==.',
Pu='Punchykicky:BAAANQAECgUIDwABNQAECgkJPgAGAJEcAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAABNQAECn8eAAQOAAoKPQbUkQBhAQAOAAkKIQbUkQBhAQATAAYKYAaFSAD7AAAjAAEKVQGKNAANAAAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAABNQAECn8iAAMSAAgKZBu0QwBWAgASAAgKZBu0QwBWAgAYAAEKAABXsAEvAAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reliun:BAAANQAECgQIBAABNQAECgcIJwATAMEJAA==.Reniel:BAAANQADCgMIAwABNQAECgkJLAAGABUSAA==.Reverendlion:BAAANQAECgUICgAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAABNQAECn8gAAILAAkK8RjGLQAjAgALAAkK8RjGLQAjAgAAAA==.Rosencrant:BAABNQAECn8VAAINAAYKmQl88AAhAQANAAYKmQl88AAhAQAAAA==.',
Ru='Rubberdukkie:BAAANQAECgIIBAAAAA==.Rule:BAAANQAECgQIBwAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgoKMQAYAG0ZAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECn80AAIiAAoKOxsQBAAnAgAiAAoKOxsQBAAnAgAAAA==.Sampal:BAABNQAECn8+AAIGAAkKkRx5DwClAgAGAAkKkRx5DwClAgAAAA==.Samwield:BAEBNQAECn89AAMdAAoK3B+FCwC8AgAdAAoKxh+FCwC8AgAbAAMK6xRReADRAAAAAA==.Sanjana:BAAANQADCgQIBAAAAA==.Santities:BAAANQAECgMIBAABNQAECgoKQgAkALIlAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAABNQAECn8pAAIJAAkK2RXEVQARAgAJAAkK2RXEVQARAgAAAA==.Selaheal:BAABNQAECn81AAITAAkKJBABEwCZAQATAAkKJBABEwCZAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadowydream:BAAANQAECgQIBAAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shamriot:BAAANQADCggICAABNQAECgoKKgAGAIgdAA==.Shinobu:BAAANQADCgYICgABNQAECgkJHAACAMcYAA==.Shintó:BAAANQADCgEIAQAAAA==.Shnood:BAABNQAECn8VAAMXAAgKMxgzDQAlAgAXAAgKMxgzDQAlAgAUAAEKAABwOgFAAAAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCggIDwAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECn8+AAMlAAoKBSFxCQBBAwAlAAoKBSFxCQBBAwAiAAMKewPAJgAjAAAAAA==.',
Sk='Skies:BAAANQAECgMIAwABNQAFFAYIDAAdACYQAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECggIKAADAGolAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgoKJAAKAM4ZAA==.Sterïzard:BAAANQADCgEIAQABNQAECgoKJAAKAM4ZAA==.Stupid:BAACNQAFFH8IAAISAAMKrBQfDgDoAAASAAMKrBQfDgDoAAA1AAQKfzYAAhIACgqrH3QSADwDABIACgqrH3QSADwDAAAA.Stærk:BAABNQAECn8kAAIKAAoKzhkiOQCSAgAKAAoKzhkiOQCSAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgoKOAAHAEMeAA==.Sunpally:BAABNQAECn8nAAISAAoKfRRiUgBPAQASAAoKfRRiUgBPAQAAAA==.Suvulaan:BAABNQAECn8ZAAMmAAgK4ANHNgDiAAAmAAgK4ANHNgDiAAAQAAIKxQFZFwAfAAAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tarinaa:BAAANQAECgEIAQAAAA==.Tatoo:BAABNQAECn9BAAINAAoKIiHQCwDzAgANAAoKIiHQCwDzAgAAAA==.',
Te='Teeice:BAABNQAECn80AAIbAAoKphmRBgA9AgAbAAoKphmRBgA9AgAAAA==.Teo:BAABNQAECn8iAAITAAkK0Q1PMAChAQATAAkK0Q1PMAChAQAAAA==.',
Th='Thariot:BAAANQADCgQIBAABNQAECgoKKgAGAIgdAA==.Thekan:BAABNQAECn8fAAIhAAgKMheuNgD6AQAhAAgKMheuNgD6AQAAAA==.Theriot:BAABNQAECn8qAAMGAAoKiB1WBgCKAgAGAAoKiB1WBgCKAgAYAAIKNhg8bgFwAAAAAA==.Thianá:BAAANQAECgQICQAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECggIIQAOABMhAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Tomoya:BAAANQAECgUIBQAAAA==.Toosus:BAACNQAFFH8dAAIRAAYKhB/wBABeAQARAAYKhB/wBABeAQA1AAQKfzUAAhEACgo6JOADACUDABEACgo6JOADACUDAAAA.Totemsnhoes:BAAANQAECggICwAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trolldung:BAAANQAECgEIAQAAAA==.',
Tt='Tturtle:BAACNQAFFH8SAAIYAAYKNg3lDgBfAQAYAAYKNg3lDgBfAQA1AAQKfysAAhgACgq5GDhmAGkCABgACgq5GDhmAGkCAAAA.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAAANQAECgUICwAAAA==.',
Un='Unholysam:BAEANQAECgEIAQABNQAECgoKPQAdANwfAA==.',
Va='Vallo:BAAANQADCgEIAQAAAA==.Vampier:BAAANQAECgMIAwAAAA==.',
Ve='Velata:BAABNQAECn8yAAIIAAoKShMNCQBIAgAIAAoKShMNCQBIAgAAAA==.Vesselette:BAAANQADCggICAAAAA==.Vezzena:BAAANQADCgMIAwAAAA==.',
Vi='Victory:BAAANQAECgEIAgAAAA==.Violencê:BAABNQAECn8xAAIWAAkKqCHWAgCOAgAWAAkKqCHWAgCOAgAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAAANQAECgUICQAAAA==.Vyzeera:BAAANQAECggICAAAAA==.',
We='Wes:BAABNQAECn8jAAIbAAcK9hDcGQAtAQAbAAcK9hDcGQAtAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECn8zAAINAAoKHRluMwDSAgANAAoKHRluMwDSAgAAAA==.Willybcastin:BAABNQAECn8fAAIHAAoKMCBzKwBFAgAHAAoKMCBzKwBFAgABNQAFFAYIEgAfAJ4gAA==.Willybwankin:BAACNQAFFH8SAAIfAAYKniBtAgAjAgAfAAYKniBtAgAjAgA1AAQKfz0AAh8ACgreJLIBAFcDAB8ACgreJLIBAFcDAAAA.',
Wo='Wowgazm:BAABNQAECn8WAAIGAAgKDwj6PAAMAQAGAAgKDwj6PAAMAQAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAABNQAECn8nAAMUAAgKRw13WABZAQAUAAgKRw13WABZAQAaAAEKAADELgA5AAAAAA==.',
Xa='Xanstar:BAAANQADCgQIBAAAAA==.',
Xe='Xerath:BAAANQAECgMIBAAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgUIBwAAAA==.Zalarian:BAABNQAECn87AAIYAAoK7CO0CQAqAwAYAAoK7CO0CQAqAwAAAA==.',
Ze='Zemos:BAAANQADCgYIDQAAAA==.Zeseroth:BAAANQAECgIIAgAAAA==.Zeserotho:BAACNQAFFH8cAAIgAAYK/hd5AwA4AQAgAAYK/hd5AwA4AQA1AAQKfzIAAiAACgr4IL0IAIICACAACgr4IL0IAIICAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECn84AAMGAAoKRBeSGQAoAgAGAAoKRBeSGQAoAgASAAgKJhIdZADsAQABNQAECgoKPgAlAAUhAA==.',
Zy='Zyn:BAAANQAECgYIBgAAAA==.',
['Éi']='Éireann:BAAANQAECgMIBAAAAA==.',
['Ðu']='Ðumpy:BAABNQAECn8eAAMKAAgKrR2BNwCZAgAKAAgKrR2BNwCZAgAJAAIKACJGgQDAAAAAAA==.',
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
