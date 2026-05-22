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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Fury','Warlock-Demonology','Paladin-Retribution','Hunter-Survival','Druid-Restoration','Druid-Balance','Priest-Shadow','Priest-Holy','Mage-Frost','Paladin-Holy','Warlock-Destruction','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','DeathKnight-Blood','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Shaman-Elemental','Warrior-Arms','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-05-16',data={Al='Althenara:BAAALgAECgEJAQAAAA==.',
Am='Amaurine:BAAALgADCgEJAQAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECgUJDgAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn8pAAMBAAgJARnwHwBcAQABAAcJhRvwHwBcAQACAAYJQxI5MwAXAQAAAA==.Araycadia:BAAALgADCgYJCQAAAA==.Arcanita:BAAALgAECgEJAQAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJAgAAAA==.Arui:BAAALgAECgYJEgAAAA==.',
At='Athania:BAABLgAECn8VAAIDAAYJRRgcCwBWAQADAAYJRRgcCwBWAQAAAA==.Athornia:BAAALgADCgQJBgAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAABLgAECn8UAAIEAAgJYhc3GwDHAQAEAAgJYhc3GwDHAQAAAA==.Azurite:BAABLgAECn8WAAIFAAYJ1hExcgAcAQAFAAYJ1hExcgAcAQAAAA==.',
Ba='Baelthos:BAAALgAECgYJEwAAAA==.Balthamøs:BAABLgAECn8sAAIGAAkJ7hFjPwDCAQAGAAkJ7hFjPwDCAQAAAA==.Barebut:BAAALgAECgcJBwAAAA==.Baz:BAABLgAECn8WAAIHAAcJwR7KCABbAgAHAAcJwR7KCABbAgAAAA==.',
Be='Beautiful:BAAALgAFFAMJAwAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAIIAAgJhwr2QABGAQAIAAgJhwr2QABGAQAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAABLgAECn8UAAIJAAYJghjDIgBZAQAJAAYJghjDIgBZAQAAAA==.Bluebyyou:BAABLgAECn8WAAMKAAYJRQd1OgDWAAAKAAYJRQd1OgDWAAALAAYJBQbiNwDTAAAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAIMAAYJ+gfmqADzAAAMAAYJ+gfmqADzAAAAAA==.',
Ca='Caelion:BAACLgAFFH8FAAINAAMJzxtNHADzAAANAAMJzxtNHADzAAAuAAQKfzQAAg0ACQmPIjEBAHwDAA0ACQmPIjEBAHwDAAAA.Callaf:BAABLgAECn8bAAIOAAgJzA+aCQBdAQAOAAgJzA+aCQBdAQAAAA==.Cannex:BAAALgAECgYJEwAAAA==.',
Ce='Celas:BAAALgAECgUJCAAAAA==.Cemmos:BAAALgAECggJCQABLgAECggJFgAIAIcKAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn8vAAMPAAkJuQ16DADEAQAPAAkJuQ16DADEAQAQAAYJGwNjUQCSAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgADCgMJBAAAAA==.Deekon:BAABLgAECn8VAAMFAAYJOxptXgBIAQAFAAYJOxptXgBIAQARAAEJAAAfLAAAAAAAAA==.Deni:BAAALgAECgEJAgAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgIJAgAAAA==.',
Do='Dovathresh:BAAALgAECgcJDAABLgAFFAgJHQASAOgXAA==.',
Ec='Ectorius:BAAALgAECgEJAQAAAA==.',
Eg='Egud:BAABLgAECn8kAAITAAgJHhiWDQDDAQATAAgJHhiWDQDDAQAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Eliri:BAACLgAFFH8SAAICAAQJNhxfEgBEAQACAAQJNhxfEgBEAQAuAAQKfxgAAgIACAliG50gAK4BAAIACAliG50gAK4BAAAA.Ellenad:BAAALgAECgUJCgAAAA==.Elsadormu:BAAALgAECgIJAgABLgAECgQJDAAUAAAAAA==.Elsà:BAAALgAECgYJBgABLgAECggJRgAVAEkjAA==.',
Ev='Evayn:BAABLgAECn8UAAIKAAcJfQTQPQDEAAAKAAcJfQTQPQDEAAAAAA==.Everhunt:BAAALgAECgUJBQAAAA==.Evo:BAABLgAECn8XAAIHAAcJARyvEgDPAQAHAAcJARyvEgDPAQAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAAALgAECgQJBAAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAABLgAECn8UAAMSAAgJjxmWEQB6AQAWAAgJXxILcACoAQASAAYJsxqWEQB6AQAAAA==.',
Fe='Feasting:BAAALgADCgEJAQABLgAECggJPAAXACQdAA==.Fendria:BAAALgADCgkJBQAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIYAAYJwRU5WAAvAQAYAAYJwRU5WAAvAQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAABLgAECn8VAAIVAAUJ2Qq8jwC4AAAVAAUJ2Qq8jwC4AAAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAQJEgACADYcAA==.',
Ga='Gaba:BAABLgAFFH8MAAICAAQJNxMIFwAQAQACAAQJNxMIFwAQAQAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.',
Ge='Georish:BAABLgAECn8hAAIZAAkJSw+cHwDBAQAZAAkJSw+cHwDBAQAAAA==.',
Gi='Ginseng:BAABLgAECn8bAAIaAAcJwB0pFgBGAgAaAAcJwB0pFgBGAgAAAA==.Girthquake:BAAALgAECgcJCAAAAA==.',
Go='Gorg:BAABLgAECn8cAAMOAAcJXgyvDgAJAQAOAAcJXgyvDgAJAQARAAIJrQanIgBnAAAAAA==.',
Gr='Grease:BAAALgAECgUJBgAAAA==.',
Gu='Gunkshot:BAABLgAECn8VAAIbAAcJ7yVOCQANAwAbAAcJ7yVOCQANAwAAAA==.',
['Gé']='Gémini:BAAALgAECgEJAQAAAA==.',
Ha='Haavoc:BAABLgAECn8lAAIcAAkJgwfyEQA3AQAcAAkJgwfyEQA3AQAAAA==.Hagul:BAAALgADCgQJAwAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.',
He='Hexadecimal:BAAALgAECgIJAwAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMCAAgJZxALIgCjAQACAAgJZxALIgCjAQABAAMJxRZrUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgcJDgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwABLgAFFAQJEgACADYcAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAAALgAECgYJCQAAAA==.Irore:BAAALgAECgUJBQAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAAALgAECgYJEQAAAA==.Jaxr:BAACLgAFFH8JAAIVAAMJEghAOwDbAAAVAAMJEghAOwDbAAAuAAQKfycAAhUACQncE4YmACACABUACQncE4YmACACAAAA.',
Je='Jetahnna:BAAALgAECgYJDwAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQPAAYJlAzAGAD/AAAPAAYJlAzAGAD/AAAQAAYJZREEQADWAAAdAAEJTgsuPgA2AAAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAgJDwAMAOYUAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAAALgAECgYJEwAAAA==.Karatedonkey:BAAALgAECgYJEQAAAA==.Kardai:BAEALgAECgYJEwAAAA==.Katamai:BAABLgAECn8cAAIMAAcJqAQetgDcAAAMAAcJqAQetgDcAAAAAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAAALgAECgYJEwAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittylock:BAAALgAECgEJAQAAAA==.Kittyshaman:BAABLgAECn8uAAMeAAkJvBHtGQDAAQAeAAkJvBHtGQDAAQAaAAIJBQUqnQAsAAAAAA==.',
Ko='Kode:BAAALgAECgMJAwAAAA==.',
Ku='Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyraltas:BAAALgAECgYJEAAAAA==.Kyrexis:BAAALgADCgIJAgAAAA==.',
La='Laermeluion:BAABLgAECn8WAAIXAAgJrRsgBwAmAgAXAAgJrRsgBwAmAgABLgAFFAgJHQASAOgXAA==.Larra:BAABLgAECn9GAAIVAAgJSSOdDACqAgAVAAgJSSOdDACqAgAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn80AAITAAgJWyPHAwC2AgATAAgJWyPHAwC2AgAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.',
Lu='Lunakae:BAAALgAECgYJDAAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgYJCQAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgMJBQAAAA==.Maranwae:BAABLgAECn8kAAIaAAgJkyDbCQDNAgAaAAgJkyDbCQDNAgAAAA==.Maybemo:BAAALgADCgkJFwAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn8hAAMTAAgJkyEYBQCIAgATAAgJkyEYBQCIAgAfAAUJ4gSTKwCYAAAAAA==.Merlose:BAABLgAECn8fAAIgAAgJLhY8DACsAQAgAAgJLhY8DACsAQAAAA==.',
Mi='Minidrake:BAAALgAECgUJEwAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMOAAcJShlpFwCOAQAFAAYJJRqVWAC+AQAOAAYJlRVpFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgADCgMJAwAAAA==.Monrroe:BAAALgAECgYJDAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgADCgYJBgABLgAFFAMJCgAIAI4SAA==.Moonveil:BAAALgAECggJDQABLgAFFAMJCgAIAI4SAA==.Moshamie:BAAALgAECgcJEgAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Naleana:BAAALgADCgkJBQAAAA==.Narzwaz:BAABLgAECn8WAAIBAAYJbB3YGwCBAQABAAYJbB3YGwCBAQAAAA==.Natallia:BAAALgADCgUJBQABLgAECggJRgAVAEkjAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn8hAAIVAAgJPw+IPACaAQAVAAgJPw+IPACaAQAAAA==.',
Ni='Nivale:BAABLgAECn8WAAIMAAYJWhuvZQB0AQAMAAYJWhuvZQB0AQAAAA==.',
No='Noel:BAACLgAFFH8FAAIMAAUJ/AUgUgABAQAMAAUJ/AUgUgABAQAuAAQKfyAAAgwACAmyGZJYAC8CAAwACAmyGZJYAC8CAAAA.Nosotras:BAAALgAECgYJEwAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Ol='Olitas:BAAALgAECgQJCQAAAA==.',
Pa='Patches:BAABLgAECn8aAAMhAAcJpxCwGwBeAQAhAAcJpxCwGwBeAQAiAAEJEgRjIgAmAAAAAA==.',
Pe='Pelonia:BAAALgAECgEJAQAAAA==.Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phau:BAAALgAECgYJEwAAAA==.',
Pi='Pinklemonade:BAAALgAECgMJAwAAAA==.',
Pl='Playmate:BAACLgAFFH8KAAIIAAMJjhKVKQDQAAAIAAMJjhKVKQDQAAAuAAQKfyMAAggACAlXH9gTAGkCAAgACAlXH9gTAGkCAAAA.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Py='Pymilocs:BAABLgAECn8aAAIeAAcJQiGoDwApAgAeAAcJQiGoDwApAgAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAABLgAECn8bAAIEAAcJQBQPJgB6AQAEAAcJQBQPJgB6AQAAAA==.Ralee:BAAALgAECgUJEQABLgAECgYJFQAeAH8GAA==.Ranebowz:BAABLgAECn8jAAIGAAkJ0Bv+FACJAgAGAAkJ0Bv+FACJAgAAAA==.Ravenmohr:BAAALgADCgUJBQAAAA==.',
Re='Rennai:BAAALgADCggJCAAAAA==.',
Rh='Rhebeqa:BAAALgADCgkJEAABLgAECgQJDAAUAAAAAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8jAAICAAgJNSGtBwDIAgACAAgJNSGtBwDIAgAAAA==.Rist:BAABLgAECn8gAAITAAkJARAEEQCJAQATAAkJARAEEQCJAQAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAAALgAECgQJBAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAAALgAECgYJEwAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMdAAkJESP5BwBoAgAdAAYJBCX5BwBoAgAQAAUJZx4hHwCQAQABLgAECgYJCQAUAAAAAA==.',
Sh='Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8bAAIdAAcJThQMCABuAQAdAAcJThQMCABuAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAMJAwAUAAAAAA==.',
Si='Silvanthos:BAAALgAECgQJBAAAAA==.Silvers:BAAALgAECgUJCwAAAA==.',
Sl='Sliccie:BAABLgAECn8mAAIFAAgJwhEVSACFAQAFAAgJwhEVSACFAQAAAA==.',
Sm='Smitegoat:BAACLgAFFH8FAAMjAAIJdgkfKACKAAAjAAIJTAgfKACKAAALAAEJ/gwoJwA5AAAuAAQKfygAAwsACQleHJ8UADkCAAsACAnzGZ8UADkCACMAAwmFHakvAAEBAAAA.',
Sn='Sney:BAABLgAECn8VAAIeAAYJfwbXSAC6AAAeAAYJfwbXSAC6AAAAAA==.',
So='Solar:BAAALgAECgkJAQAAAA==.Sorlzul:BAAALgAECgMJBwAAAA==.Sound:BAAALgAECgEJAQABLgAECgMJAwAUAAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8bAAIVAAcJWA6aUwBPAQAVAAcJWA6aUwBPAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAgJHQASAOgXAA==.Taiurag:BAAALgAECgUJEwAAAA==.Taken:BAAALgAECgYJEwAAAA==.Tazra:BAABLgAECn8tAAIGAAkJ5h6JGwBgAgAGAAkJ5h6JGwBgAgAAAA==.Tazzy:BAAALgADCgkJDwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8fAAIEAAkJhBAlHAC/AQAEAAkJhBAlHAC/AQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tonkatruck:BAAALgAECgYJEwAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMLAAgJYwjPKgArAQALAAgJCgfPKgArAQAjAAYJYwcJMQAYAQAAAA==.Tuyenlotus:BAABLgAECn8nAAIkAAkJtxwjBABnAgAkAAkJtxwjBABnAgAAAA==.',
Un='Unholypriest:BAAALgAECgYJCwAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAAALgAECgYJEwAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8eAAIQAAcJsAfpOQDxAAAQAAcJsAfpOQDxAAAAAA==.Vesia:BAABLgAECn8YAAMLAAYJZRh5JABaAQALAAYJZRh5JABaAQAKAAQJYBPZPwD4AAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.',
Vo='Voidrat:BAAALgAECgEJBAABLgAECggJKQABAAEZAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
['Ví']='Ví:BAABLgAECn8aAAMlAAcJ4werCADEAAAMAAcJLgThrADsAAAlAAUJXQqrCADEAAAAAA==.',
Wa='Warfare:BAAALgAECgEJAQABLgAECgkJJQAcAIMHAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.',
Wi='Wildpally:BAAALgAECgUJEgAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn8sAAMMAAkJGRYbNQAEAgAMAAkJJxMbNQAEAgAlAAQJmheVCwAcAQAAAA==.',
Yu='Yulíana:BAAALgAECgUJCQAAAA==.',
Za='Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn8cAAMVAAcJjhHSTABjAQAVAAcJjhHSTABjAQAbAAEJ4QFKmgAZAAAAAA==.',
Ze='Zelara:BAABLgAFFH8FAAIXAAIJUBHMEAB5AAAXAAIJUBHMEAB5AAAAAA==.Zertloc:BAABLgAECn8lAAIeAAgJ+hvOEQASAgAeAAgJ+hvOEQASAgAAAA==.',
Zh='Zhaan:BAAALgAECgIJAgAAAA==.',
Zi='Zieda:BAABLgAECn8gAAIJAAcJBw+BLgAOAQAJAAcJBw+BLgAOAQAAAA==.Ziti:BAAALgADCgIJAgAAAA==.',
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
