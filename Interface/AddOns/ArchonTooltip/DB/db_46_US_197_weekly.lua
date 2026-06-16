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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Druid-Balance','DemonHunter-Vengeance','Warrior-Fury','Warlock-Demonology','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','Evoker-Augmentation','DeathKnight-Blood','Warrior-Protection','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Havoc','Shaman-Restoration','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Paladin-Protection','Shaman-Elemental','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Shaman-Enhancement','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aachooshaman:BAAALgAECgEJAwAAAA==.',
Al='Althenara:BAAALgAECgUJDAAAAA==.',
Am='Amaurine:BAAALgADCgEJAQAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECggJDwAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn9JAAMBAAkJ+BlODwCpAgABAAkJ+BlODwCpAgACAAgJJh+YDQBpAgAAAA==.Araycadia:BAAALgAECgkJBAAAAA==.Arcanita:BAABLgAFFH8IAAIDAAIJ1Ri6lQCiAAADAAIJ1Ri6lQCiAAAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJBAAAAA==.Arui:BAABLgAECn8iAAIEAAkJCCBJBwDgAgAEAAkJCCBJBwDgAgAAAA==.',
At='Athania:BAABLgAECn8hAAIFAAkJAhnVBQA+AgAFAAkJAhnVBQA+AgAAAA==.Athornia:BAAALgAECgEJAQAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAACLgAFFH8IAAIGAAMJEhDFNgDRAAAGAAMJEhDFNgDRAAAuAAQKfxYAAgYACQlqFTAhAOYBAAYACQlqFTAhAOYBAAAA.Azurite:BAABLgAECn8vAAIHAAgJVRSgSgC6AQAHAAgJVRSgSgC6AQAAAA==.Azzael:BAAALgADCgUJBQAAAA==.',
Ba='Baelthos:BAABLgAECn8fAAIIAAkJdBHwRgCuAQAIAAkJdBHwRgCuAQAAAA==.Balthamøs:BAABLgAECn8vAAIJAAkJ7hGCYQCrAQAJAAkJ7hGCYQCrAQAAAA==.Barebut:BAAALgAECgcJBwAAAA==.Baz:BAABLgAECn8WAAIKAAcJwR7KCABbAgAKAAcJwR7KCABbAgAAAA==.',
Be='Beautiful:BAABLgAFFH8HAAILAAQJrRL1LwDqAAALAAQJrRL1LwDqAAABLgAFFAYJGQAMAPMWAA==.Belak:BAAALgAECgEJAwAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAILAAgJhwqVUgBCAQALAAgJhwqVUgBCAQABLgAECgkJCgANAAAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAABLgAECn8eAAIEAAcJvBzfGgDxAQAEAAcJvBzfGgDxAQAAAA==.Bluebyyou:BAABLgAECn8rAAMOAAgJigvcMgBNAQAOAAgJigvcMgBNAQAPAAYJBQZUSQC6AAAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Boseph:BAAALgAECgEJBAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAIDAAYJ+gdN3ADcAAADAAYJ+gdN3ADcAAAAAA==.',
Ca='Caelion:BAACLgAFFH8IAAIQAAMJzxstKQDXAAAQAAMJzxstKQDXAAAuAAQKf1QAAhAACQlkJhwAAP8DABAACQlkJhwAAP8DAAAA.Callaf:BAABLgAECn8eAAMRAAkJWw6EDgBRAQARAAgJzA+EDgBRAQASAAMJ4QJINwBDAAAAAA==.Cannex:BAABLgAECn8jAAITAAkJuB2kHgCOAgATAAkJuB2kHgCOAgAAAA==.Cavell:BAAALgAECgYJCQAAAA==.',
Ce='Celas:BAABLgAECn8UAAILAAUJsQ85aQD2AAALAAUJsQ85aQD2AAAAAA==.Cemmos:BAAALgAECgkJCgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn88AAMMAAkJuQ1hEQCxAQAMAAkJuQ1hEQCxAQAUAAcJ5wJvZwCfAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.Clarinets:BAAALgAECgEJAQAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Cryomyst:BAAALgADCgMJAwAAAA==.Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgAECggJDgAAAA==.Deekon:BAABLgAECn8WAAMHAAcJHRhTZgBwAQAHAAcJHRhTZgBwAQASAAEJAAAPRwAAAAAAAA==.Deni:BAAALgAECgEJAgAAAA==.Derrick:BAAALgADCgEJAQAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgUJBgAAAA==.Dezrick:BAAALgAECgcJAQAAAA==.',
Do='Dovathresh:BAAALgAECgcJDAABLgAFFAgJHgAVAO0XAA==.',
Ec='Ectorius:BAAALgAECgEJAwAAAA==.',
Ed='Edwardkenway:BAAALgAECgYJBgAAAA==.',
Eg='Egud:BAABLgAECn88AAIWAAkJPRvcCABnAgAWAAkJPRvcCABnAgAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Elipsis:BAAALgADCgcJBwAAAA==.Eliri:BAACLgAFFH8WAAIBAAQJth5YIwBEAQABAAQJth5YIwBEAQAuAAQKfxgAAgEACAlhG50gAK4BAAEACAlhG50gAK4BAAAA.Ellenad:BAAALgAECgUJEQAAAA==.Elsadormu:BAAALgAECgIJAgAAAA==.Elsà:BAAALgAECgYJBgABLgAECgkJTwAXACciAA==.',
Ev='Evayn:BAABLgAECn8mAAIOAAkJhAafNgA5AQAOAAkJhAafNgA5AQAAAA==.Everflux:BAAALgAECgEJAQAAAA==.Everhunt:BAAALgAECggJCQAAAA==.Evo:BAABLgAECn8yAAIKAAkJRiDnAwD0AgAKAAkJRiDnAwD0AgAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAABLgAECn8YAAIEAAYJZQTiYACRAAAEAAYJZQTiYACRAAAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAACLgAFFH8FAAITAAUJ2gjffwAEAQATAAUJ2gjffwAEAQAuAAQKfxYAAxUACQmxGC8eAGMBABMACQlmEgtwAKgBABUABgmzGi8eAGMBAAAA.',
Fe='Feasting:BAAALgADCgEJAQABLgAECggJQwAYACMeAA==.Fendria:BAAALgAECgMJBAAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIIAAYJwRXqeAArAQAIAAYJwRXqeAArAQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAABLgAECn8aAAIXAAcJmQh1nQABAQAXAAcJmQh1nQABAQAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAQJFgABALYeAA==.',
Ga='Gaba:BAABLgAFFH8WAAIBAAYJ1BlYFADTAQABAAYJ1BlYFADTAQAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.',
Ge='Georish:BAABLgAECn8hAAIZAAkJSw+cHwDBAQAZAAkJSw+cHwDBAQAAAA==.',
Gi='Ginseng:BAABLgAECn8vAAIaAAkJNB2HDgDcAgAaAAkJNB2HDgDcAgAAAA==.Girthquake:BAABLgAECn8fAAIaAAkJnR8/BwA5AwAaAAkJnR8/BwA5AwAAAA==.',
Gl='Glucian:BAAALgAECgEJAQAAAA==.',
Go='Gorg:BAABLgAECn88AAMRAAkJbBTMBgDsAQARAAkJbBTMBgDsAQASAAIJrQanIgBnAAAAAA==.',
Gr='Grease:BAAALgAECgUJBgAAAA==.',
Gu='Gunkshot:BAACLgAFFH8FAAIKAAMJ9x7sFwAOAQAKAAMJ9x7sFwAOAQAuAAQKfxUAAhsABwnvJU4JAA0DABsABwnvJU4JAA0DAAAA.',
['Gé']='Gémini:BAAALgAECgIJAgAAAA==.',
Ha='Haavoc:BAABLgAECn8rAAIcAAkJmAjFHAAeAQAcAAkJmAjFHAAeAQAAAA==.Hagul:BAAALgAECggJCgAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.Harandoll:BAAALgADCgkJCQAAAA==.',
He='Hexadecimal:BAAALgAECgcJEAAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMBAAgJZxALIgCjAQABAAgJZxALIgCjAQACAAMJxRZrUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgcJDgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwAAAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAABLgAECn8ZAAITAAgJvgqyggBbAQATAAgJvgqyggBbAQAAAA==.Irore:BAAALgAECggJCAAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAABLgAECn8UAAMLAAcJAg3rWgAkAQALAAcJAg3rWgAkAQAEAAIJRwa+mQAlAAAAAA==.Jaxr:BAACLgAFFH8TAAIXAAQJ8gmRSwANAQAXAAQJ8gmRSwANAQAuAAQKf0EAAhcACQntGJQhAFsCABcACQntGJQhAFsCAAAA.',
Je='Jenjyandi:BAAALgAECgMJAwABLgAECgkJJAAaADgNAA==.Jetahnna:BAABLgAECn8eAAIXAAkJ+geEWACWAQAXAAkJ+geEWACWAQAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQMAAYJlAzbHwDzAAAMAAYJlAzbHwDzAAAUAAYJZRH1VgDRAAAdAAEJTgsuPgA2AAAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAgJEQADAOcUAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAABLgAECn8kAAIaAAkJOA2nQwCbAQAaAAkJOA2nQwCbAQAAAA==.Karatedonkey:BAABLgAECn8gAAIcAAkJgg74EQCVAQAcAAkJgg74EQCVAQAAAA==.Kardai:BAEBLgAECn8jAAIVAAkJvQoyIgA/AQAVAAkJvQoyIgA/AQAAAA==.Katamai:BAABLgAECn88AAIDAAkJTQhodwCHAQADAAkJTQhodwCHAQAAAA==.Katreia:BAAALgAECgMJAwABLgAFFAgJHgAVAO0XAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAABLgAECn8jAAIeAAkJxhPODgDTAQAeAAkJxhPODgDTAQAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittylock:BAAALgAECgEJAQAAAA==.Kittyshaman:BAABLgAECn87AAMfAAkJmRQ3HQD1AQAfAAkJmRQ3HQD1AQAaAAIJBQXG1wAsAAAAAA==.',
Ko='Kode:BAAALgAECgYJCQAAAA==.Kozalos:BAAALgADCgUJBQAAAA==.',
Ku='Kurono:BAAALgAECggJCAABLgAECgkJHAAJAFMGAA==.Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyko:BAAALgAECgMJAwAAAA==.Kyraltas:BAABLgAECn8cAAIJAAkJUwbpmgA9AQAJAAkJUwbpmgA9AQAAAA==.Kyrexis:BAAALgAECgEJAQAAAA==.',
La='Laermeluion:BAABLgAECn8WAAIYAAgJqxvsCwAeAgAYAAgJqxvsCwAeAgABLgAFFAgJHgAVAO0XAA==.Larra:BAABLgAECn9PAAIXAAkJJyJxDwDRAgAXAAkJJyJxDwDRAgAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn87AAIWAAkJTyM3AwAEAwAWAAkJTyM3AwAEAwAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.Lothorine:BAAALgAECgEJAQAAAA==.',
Lu='Lunakae:BAABLgAECn8ZAAILAAgJcw+0QQCHAQALAAgJcw+0QQCHAQAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgYJCQAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgUJBwAAAA==.Maranwae:BAABLgAECn8yAAMaAAkJPSA8CAAqAwAaAAkJPSA8CAAqAwAfAAEJHhurjwBPAAAAAA==.Maybemo:BAAALgAECgQJBAAAAA==.Maylata:BAAALgAECgYJBgAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn8uAAMWAAkJ9SIyAwAFAwAWAAkJ9SIyAwAFAwAgAAUJ4gSTKwCYAAAAAA==.Merlose:BAABLgAECn83AAIeAAkJtBp5BwBjAgAeAAkJtBp5BwBjAgAAAA==.',
Mi='Minidrake:BAABLgAECn8YAAMMAAgJ3woGGABNAQAMAAgJ3woGGABNAQAdAAMJQwVKMwB7AAAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMRAAcJShlpFwCOAQAHAAYJJRqVWAC+AQARAAYJlRVpFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgAECgEJAQAAAA==.Monrroe:BAABLgAECn8WAAMeAAYJSBJrIQAGAQAeAAYJSBJrIQAGAQAQAAYJ3gtxYQCtAAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgAECgIJAgABLgAFFAQJFgALAHsPAA==.Moonveil:BAAALgAECggJDQABLgAFFAQJFgALAHsPAA==.Moshamie:BAABLgAECn8rAAIfAAkJAQgRPwA0AQAfAAkJAQgRPwA0AQAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Naleana:BAAALgAECgMJBAAAAA==.Narzwaz:BAABLgAECn8mAAICAAkJpR+1BwDLAgACAAkJpR+1BwDLAgAAAA==.Natallia:BAAALgADCgUJBQABLgAECgkJTwAXACciAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn85AAIXAAkJGBSeMgANAgAXAAkJGBSeMgANAgAAAA==.',
Ni='Nivale:BAABLgAECn8WAAIDAAYJWhumigBeAQADAAYJWhumigBeAQAAAA==.',
No='Noc:BAAALgADCgIJAgAAAA==.Noel:BAACLgAFFH8RAAIDAAgJJw2lHAASAgADAAgJJw2lHAASAgAuAAQKfyAAAgMACAmyGZJYAC8CAAMACAmyGZJYAC8CAAAA.Nosotras:BAABLgAECn8jAAIHAAkJBxCzSAC/AQAHAAkJBxCzSAC/AQAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Ol='Olitas:BAAALgAECgUJCgAAAA==.',
Pa='Pahudesh:BAAALgADCgUJBQABLgAECgkJIwABALsgAA==.Patches:BAABLgAECn8dAAMhAAkJ6hEXFwDfAQAhAAkJ6hEXFwDfAQAiAAEJEgQ+LAAlAAAAAA==.',
Pe='Pelonia:BAAALgAECgYJBQAAAA==.Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phaera:BAAALgAECgIJAgABLgAECgYJFQAMAJQMAA==.Phau:BAABLgAECn8jAAIBAAkJuyBeBgA6AwABAAkJuyBeBgA6AwAAAA==.',
Pi='Pinklemonade:BAAALgAECgQJCgAAAA==.',
Pl='Plagos:BAAALgADCgYJCQAAAA==.Playmate:BAACLgAFFH8WAAILAAQJew+nMQDiAAALAAQJew+nMQDiAAAuAAQKfyMAAgsACAlXH6kbAGYCAAsACAlXH6kbAGYCAAAA.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prahumn:BAAALgAECgQJDAAAAA==.Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Py='Pymilocs:BAABLgAECn80AAIfAAkJwSFkBgDzAgAfAAkJwSFkBgDzAgAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.Quint:BAAALgADCggJCAAAAA==.Quleiry:BAAALgAFFAMJAwAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAACLgAFFH8HAAIGAAMJJgh/PACxAAAGAAMJJgh/PACxAAAuAAQKfycAAgYACAn5FQQmAMcBAAYACAn5FQQmAMcBAAAA.Raktal:BAAALgADCgUJBQAAAA==.Ralee:BAABLgAECn81AAITAAgJOxI3WQC4AQATAAgJOxI3WQC4AQAAAA==.Ranebowz:BAABLgAECn8qAAIJAAkJqxxGIQCAAgAJAAkJqxxGIQCAAgAAAA==.Ravenmohr:BAAALgADCgUJBQAAAA==.Razleaf:BAAALgAECgEJAQABLgAECgkJCgANAAAAAA==.',
Re='Rennai:BAAALgAECgcJDAAAAA==.',
Rh='Rhebeqa:BAAALgAECgUJBAABLgAECggJFgADAPAFAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8xAAIBAAkJVyLiBABcAwABAAkJVyLiBABcAwAAAA==.Rist:BAABLgAECn8gAAIWAAkJAxCBGgBiAQAWAAkJAxCBGgBiAQAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAAALgAFFAEJAgAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAABLgAECn8jAAIPAAkJTBMwHADhAQAPAAkJTBMwHADhAQAAAA==.',
Sc='Scarhide:BAABLgAECn8ZAAQgAAkJgRK8GACRAQAgAAkJuQ68GACRAQAWAAgJqRB9GQBsAQAGAAIJ9QkogwBqAAAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMdAAkJESP5BwBoAgAdAAYJBCX5BwBoAgAUAAUJZx7UKgCRAQABLgAECgYJCQANAAAAAA==.',
Sh='Shadaloo:BAAALgAFFAMJBAAAAA==.Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8eAAIdAAkJwRP7BgDTAQAdAAkJwRP7BgDTAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAYJGQAMAPMWAA==.',
Si='Silvanthos:BAAALgAECgQJBwAAAA==.Silvers:BAAALgAECgUJCwAAAA==.Silverthorn:BAAALgAECgEJAQAAAA==.',
Sk='Skrom:BAAALgAECggJCAAAAA==.',
Sl='Sliccie:BAABLgAECn8sAAIHAAgJIBKjXACIAQAHAAgJIBKjXACIAQAAAA==.',
Sm='Smitegoat:BAACLgAFFH8QAAMjAAUJCQmsIQA5AQAjAAUJ1wisIQA5AQAPAAEJ/gzqNwAvAAAuAAQKfygAAw8ACQleHJ8UADkCAA8ACAnzGZ8UADkCACMAAwmFHfVCAPwAAAAA.',
Sn='Sney:BAABLgAECn8lAAIfAAYJVQ34UwDlAAAfAAYJVQ34UwDlAAABLgAECggJNQATADsSAA==.',
So='Solaia:BAABLgAECn8UAAIWAAgJ8xQaEgDFAQAWAAgJ8xQaEgDFAQABLgAFFAgJHgAVAO0XAA==.Solar:BAAALgAECgkJAQAAAA==.Sorlzul:BAAALgAECgMJBwAAAA==.Sound:BAAALgAECgIJBQABLgAECgMJAwANAAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.Stranger:BAAALgAECgcJBwAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8eAAIXAAkJNQ2ATwCvAQAXAAkJNQ2ATwCvAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAgJHgAVAO0XAA==.Taiurag:BAAALgAECgUJEwAAAA==.Taken:BAABLgAECn8eAAIDAAkJXAXKlwBGAQADAAkJXAXKlwBGAQAAAA==.Tazra:BAACLgAFFH8HAAIJAAMJgh/0SAAWAQAJAAMJgh/0SAAWAQAuAAQKfzoAAgkACQlsH9clAGsCAAkACQlsH9clAGsCAAAA.Tazzy:BAAALgAECgMJAwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8pAAIGAAkJIxPEIQDiAQAGAAkJIxPEIQDiAQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tondri:BAAALgAECgYJBwAAAA==.Tonkatruck:BAABLgAECn8fAAIJAAkJsxbbNAAqAgAJAAkJsxbbNAAqAgAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMPAAgJYwj4OQALAQAjAAYJYwcJMQAYAQAPAAgJCwf4OQALAQAAAA==.Tuyenlotus:BAABLgAECn8nAAIkAAkJtxzyBwBFAgAkAAkJtxzyBwBFAgAAAA==.',
Un='Unholypriest:BAAALgAECgYJCwAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAABLgAECn8yAAIfAAkJhRv1DgB+AgAfAAkJhRv1DgB+AgAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8rAAMUAAgJEwt0OwA6AQAUAAgJyAp0OwA6AQAdAAEJgwiMJgAvAAAAAA==.Vesia:BAABLgAECn8YAAMPAAYJZRjEMABGAQAPAAYJZRjEMABGAQAOAAQJYBPZPwD4AAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.Vicarrion:BAAALgAECgcJDAAAAA==.Viscera:BAAALgADCgMJAwAAAA==.',
Vo='Voidrat:BAABLgAECn8UAAMBAAYJ3By+NQCWAQABAAUJoxy+NQCWAQACAAYJMRG6OQAXAQABLgAECgkJSQABAPgZAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
Vr='Vrat:BAAALgAECgEJAQABLgAECgkJSQABAPgZAA==.',
['Ví']='Ví:BAABLgAECn8yAAQlAAgJGgqzCwC+AAADAAgJvQYypwAsAQAlAAUJHAyzCwC+AAAmAAEJAABUGAAAAAAAAA==.',
Wa='Warfare:BAAALgAECgcJEwABLgAECgkJKwAcAJgIAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.Whitezi:BAAALgAECgYJBwAAAA==.',
Wi='Wildpally:BAABLgAECn8XAAIeAAUJYA37LQCuAAAeAAUJYA37LQCuAAAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn89AAMDAAkJGRqJPgAfAgADAAkJCxaJPgAfAgAlAAYJzhjsBACWAQAAAA==.',
Yu='Yulíana:BAAALgAECgYJCgAAAA==.',
Za='Zakýe:BAAALgAECgQJBAAAAA==.Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn88AAMXAAkJcxb0JgBAAgAXAAkJcxb0JgBAAgAbAAEJ4QFKmgAZAAAAAA==.',
Ze='Zelara:BAABLgAFFH8GAAIYAAIJUBFdLABiAAAYAAIJUBFdLABiAAAAAA==.Zertloc:BAABLgAECn8/AAIfAAkJFiJXBAAaAwAfAAkJFiJXBAAaAwAAAA==.',
Zh='Zhaan:BAAALgAECgUJBQAAAA==.',
Zi='Zieda:BAACLgAFFH8NAAIEAAQJNw+rIwADAQAEAAQJNw+rIwADAQAuAAQKfykAAgQACAnFGDcZAAACAAQACAnFGDcZAAACAAAA.Ziti:BAAALgADCgIJAgAAAA==.',
Zo='Zombini:BAAALgAECgQJBAAAAA==.',
Zu='Zubiria:BAAALgADCgcJCwAAAA==.Zulaaj:BAAALgAECgMJAwAAAA==.',
['Év']='Évania:BAAALgADCgYJBgAAAA==.Éver:BAAALgADCgUJBQAAAA==.',
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
