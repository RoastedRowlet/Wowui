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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Druid-Balance','DemonHunter-Vengeance','Warrior-Fury','Warlock-Demonology','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Druid-Restoration','Evoker-Preservation','Unknown-Unknown','Priest-Shadow','Priest-Holy','Mage-Frost','Paladin-Holy','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','DeathKnight-Blood','Warrior-Protection','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Havoc','Shaman-Restoration','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Paladin-Protection','Shaman-Elemental','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Shaman-Enhancement','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-05-23',data={Al='Althenara:BAAALgAECgUJBQAAAA==.',
Am='Amaurine:BAAALgADCgEJAQAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECggJDwAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn8vAAMBAAgJMBv0FQAuAgABAAcJYRv0FQAuAgACAAcJhRv2IgC/AQAAAA==.Araycadia:BAAALgADCgYJCQAAAA==.Arcanita:BAAALgAFFAIJAgAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJAgAAAA==.Arui:BAABLgAECn8aAAIDAAgJGhwjDwBDAgADAAgJGhwjDwBDAgAAAA==.',
At='Athania:BAABLgAECn8VAAIEAAYJRRhXDQBPAQAEAAYJRRhXDQBPAQAAAA==.Athornia:BAAALgADCgQJBwAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAACLgAFFH8IAAIFAAMJEhC2JwDcAAAFAAMJEhC2JwDcAAAuAAQKfxYAAgUACQlqFXEaAPYBAAUACQlqFXEaAPYBAAAA.Azurite:BAABLgAECn8fAAIGAAcJeBIRYgBlAQAGAAcJeBIRYgBlAQAAAA==.',
Ba='Baelthos:BAABLgAECn8XAAIHAAgJ4w86UgBsAQAHAAgJ4w86UgBsAQAAAA==.Balthamøs:BAABLgAECn8uAAIIAAkJ7hG4SwDFAQAIAAkJ7hG4SwDFAQAAAA==.Barebut:BAAALgAECgcJBwAAAA==.Baz:BAABLgAECn8WAAIJAAcJwR7KCABbAgAJAAcJwR7KCABbAgAAAA==.',
Be='Beautiful:BAABLgAFFH8HAAIKAAQJrRKRIgAWAQAKAAQJrRKRIgAWAQABLgAFFAUJEgALAFcZAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAIKAAgJhwoNSQBHAQAKAAgJhwoNSQBHAQABLgAECgkJCgAMAAAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAABLgAECn8VAAIDAAYJghgzKgBRAQADAAYJghgzKgBRAQAAAA==.Bluebyyou:BAABLgAECn8bAAMNAAYJHwgpQADkAAANAAYJHwgpQADkAAAOAAYJBQbKPgDPAAAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAIPAAYJ+gcOwQDqAAAPAAYJ+gcOwQDqAAAAAA==.',
Ca='Caelion:BAACLgAFFH8IAAIQAAMJzxvgIADrAAAQAAMJzxvgIADrAAAuAAQKfzoAAhAACQmRIjEBAHwDABAACQmRIjEBAHwDAAAA.Callaf:BAABLgAECn8bAAIRAAgJzA94CwBaAQARAAgJzA94CwBaAQAAAA==.Cannex:BAABLgAECn8bAAISAAgJXxv8MAAYAgASAAgJXxv8MAAYAgAAAA==.Cavell:BAAALgADCgcJBwAAAA==.',
Ce='Celas:BAAALgAECgUJDAAAAA==.Cemmos:BAAALgAECgkJCgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn81AAMLAAkJuQ2aDgDAAQALAAkJuQ2aDgDAAQATAAcJ5wL0VgCrAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgAECgEJAgAAAA==.Deekon:BAABLgAECn8VAAMGAAYJOxqBcQBBAQAGAAYJOxqBcQBBAQAUAAEJAABWNwAAAAAAAA==.Deni:BAAALgAECgEJAgAAAA==.Derrick:BAAALgADCgEJAQAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgUJBgAAAA==.',
Do='Dovathresh:BAAALgAECgcJDAABLgAFFAgJHgAVAO0XAA==.',
Ec='Ectorius:BAAALgAECgEJAwAAAA==.',
Eg='Egud:BAABLgAECn8sAAIWAAgJhhm0DgDUAQAWAAgJhhm0DgDUAQAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Elipsis:BAAALgADCgMJAwAAAA==.Eliri:BAACLgAFFH8WAAIBAAQJth50FQBYAQABAAQJth50FQBYAQAuAAQKfxgAAgEACAlhG50gAK4BAAEACAlhG50gAK4BAAAA.Ellenad:BAAALgAECgUJEQAAAA==.Elsadormu:BAAALgAECgIJAgAAAA==.Elsà:BAAALgAECgYJBgABLgAECggJTQAXAEojAA==.',
Ev='Evayn:BAABLgAECn8UAAINAAcJfQRQRgDJAAANAAcJfQRQRgDJAAAAAA==.Everhunt:BAAALgAECgYJBwAAAA==.Evo:BAABLgAECn8dAAIJAAcJ3hxMEgD8AQAJAAcJ3hxMEgD8AQAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAAALgAECgYJCgAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAABLgAECn8WAAMVAAkJsRiRGABtAQASAAkJZhILcACoAQAVAAYJsxqRGABtAQAAAA==.',
Fe='Feasting:BAAALgADCgEJAQABLgAECggJPgAYANMdAA==.Fendria:BAAALgADCgkJBQAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIHAAYJwRXbaQArAQAHAAYJwRXbaQArAQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAABLgAECn8YAAIXAAcJmQgmgwAIAQAXAAcJmQgmgwAIAQAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAQJFgABALYeAA==.',
Ga='Gaba:BAABLgAFFH8PAAIBAAQJJBWcHQAHAQABAAQJJBWcHQAHAQAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.',
Ge='Georish:BAABLgAECn8hAAIZAAkJSw+cHwDBAQAZAAkJSw+cHwDBAQAAAA==.',
Gi='Ginseng:BAABLgAECn8bAAIaAAcJwR2uGwBAAgAaAAcJwR2uGwBAAgAAAA==.Girthquake:BAAALgAECggJEAAAAA==.',
Gl='Glucian:BAAALgAECgEJAQAAAA==.',
Go='Gorg:BAABLgAECn8iAAMRAAcJ6AwREAAVAQARAAcJ6AwREAAVAQAUAAIJrQanIgBnAAAAAA==.',
Gr='Grease:BAAALgAECgUJBgAAAA==.',
Gu='Gunkshot:BAACLgAFFH8FAAIJAAMJ9x45EQAmAQAJAAMJ9x45EQAmAQAuAAQKfxUAAhsABwnvJU4JAA0DABsABwnvJU4JAA0DAAAA.',
['Gé']='Gémini:BAAALgAECgEJAQAAAA==.',
Ha='Haavoc:BAABLgAECn8lAAIcAAkJiQf7FQAvAQAcAAkJiQf7FQAvAQAAAA==.Hagul:BAAALgADCgQJAwAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.Harandoll:BAAALgADCgkJCQAAAA==.',
He='Hexadecimal:BAAALgAECgcJEAAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMBAAgJZxALIgCjAQABAAgJZxALIgCjAQACAAMJxRZrUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgcJDgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwABLgAFFAQJFgABALYeAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAAALgAECgYJDwAAAA==.Irore:BAAALgAECgUJBQAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAAALgAECgcJEwAAAA==.Jaxr:BAACLgAFFH8LAAIXAAMJEgh9SgDPAAAXAAMJEgh9SgDPAAAuAAQKfy4AAhcACQm4FuEgADkCABcACQm4FuEgADkCAAAA.',
Je='Jetahnna:BAABLgAECn8WAAIXAAcJxgebcwAqAQAXAAcJxgebcwAqAQAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQLAAYJlAwnHAD5AAALAAYJlAwnHAD5AAATAAYJZRFaSwDUAAAdAAEJTgsuPgA2AAAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAgJDwAPAOcUAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAABLgAECn8bAAIaAAgJogtoSQBVAQAaAAgJogtoSQBVAQAAAA==.Karatedonkey:BAABLgAECn8ZAAIcAAgJ3AyGEgBaAQAcAAgJ3AyGEgBaAQAAAA==.Kardai:BAEBLgAECn8bAAIVAAgJ5Qc1JwDrAAAVAAgJ5Qc1JwDrAAAAAA==.Katamai:BAABLgAECn8iAAIPAAcJ/QT9yADeAAAPAAcJ/QT9yADeAAAAAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAABLgAECn8bAAIeAAgJPBIZEQCGAQAeAAgJPBIZEQCGAQAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittylock:BAAALgAECgEJAQAAAA==.Kittyshaman:BAABLgAECn80AAMfAAkJQBIPHQDMAQAfAAkJQBIPHQDMAQAaAAIJBQV0tAAsAAAAAA==.',
Ko='Kode:BAAALgAECgYJCQAAAA==.Kozalos:BAAALgADCgUJBQAAAA==.',
Ku='Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyraltas:BAABLgAECn8YAAIIAAgJNwYlmAAjAQAIAAgJNwYlmAAjAQAAAA==.Kyrexis:BAAALgAECgEJAQAAAA==.',
La='Laermeluion:BAABLgAECn8WAAIYAAgJqxvMCAAmAgAYAAgJqxvMCAAmAgABLgAFFAgJHgAVAO0XAA==.Larra:BAABLgAECn9NAAIXAAgJSiNuEgCVAgAXAAgJSiNuEgCVAgAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn87AAIWAAkJTyPhAQAgAwAWAAkJTyPhAQAgAwAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.',
Lu='Lunakae:BAAALgAECgYJDAAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgYJCQAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgUJBwAAAA==.Maranwae:BAABLgAECn8nAAIaAAkJVB8xCAAGAwAaAAkJVB8xCAAGAwAAAA==.Maybemo:BAAALgADCgkJFwAAAA==.Maylata:BAAALgAECgYJBgAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn8qAAMWAAkJQCJXAgANAwAWAAkJQCJXAgANAwAgAAUJ4gSTKwCYAAAAAA==.Merlose:BAABLgAECn8nAAIeAAgJjxZfDgCvAQAeAAgJjxZfDgCvAQAAAA==.',
Mi='Minidrake:BAABLgAECn8WAAMLAAcJLgyxFgA+AQALAAcJLgyxFgA+AQAdAAMJQwVKMwB7AAAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMRAAcJShlpFwCOAQAGAAYJJRqVWAC+AQARAAYJlRVpFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgADCgMJAwAAAA==.Monrroe:BAAALgAECgYJDAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgADCgYJBgABLgAFFAQJDgAKAMQOAA==.Moonveil:BAAALgAECggJDQABLgAFFAQJDgAKAMQOAA==.Moshamie:BAABLgAECn8aAAIfAAcJwQURTADUAAAfAAcJwQURTADUAAAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Naleana:BAAALgADCgkJBQAAAA==.Narzwaz:BAABLgAECn8eAAICAAgJQhzvDgAzAgACAAgJQhzvDgAzAgAAAA==.Natallia:BAAALgADCgUJBQABLgAECggJTQAXAEojAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn8pAAIXAAgJoBINPwC6AQAXAAgJoBINPwC6AQAAAA==.',
Ni='Nivale:BAABLgAECn8WAAIPAAYJWhvCeQBoAQAPAAYJWhvCeQBoAQAAAA==.',
No='Noel:BAACLgAFFH8NAAIPAAgJ5wodDAAoAgAPAAgJ5wodDAAoAgAuAAQKfyAAAg8ACAmyGZJYAC8CAA8ACAmyGZJYAC8CAAAA.Nosotras:BAABLgAECn8bAAIGAAgJNQ8PVQCGAQAGAAgJNQ8PVQCGAQAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Ol='Olitas:BAAALgAECgQJCQAAAA==.',
Pa='Patches:BAABLgAECn8aAAMhAAcJpxBJIgBUAQAhAAcJpxBJIgBUAQAiAAEJEgSkJQAmAAAAAA==.',
Pe='Pelonia:BAAALgAECgEJAQAAAA==.Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phaera:BAAALgADCgYJBgABLgAECgYJFQALAJQMAA==.Phau:BAABLgAECn8bAAIBAAgJVyAMCQDWAgABAAgJVyAMCQDWAgAAAA==.',
Pi='Pinklemonade:BAAALgAECgQJCAAAAA==.',
Pl='Plagos:BAAALgADCgMJAwAAAA==.Playmate:BAACLgAFFH8OAAIKAAQJxA52JgADAQAKAAQJxA52JgADAQAuAAQKfyMAAgoACAlXH4QXAGgCAAoACAlXH4QXAGgCAAAA.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Py='Pymilocs:BAABLgAECn8gAAIfAAcJQyHhEwAgAgAfAAcJQyHhEwAgAgAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAABLgAECn8mAAIFAAcJFRaAKACTAQAFAAcJFRaAKACTAQAAAA==.Ralee:BAABLgAECn8eAAISAAYJuw3dmgANAQASAAYJuw3dmgANAQAAAA==.Ranebowz:BAABLgAECn8qAAIIAAkJqxzUFwCWAgAIAAkJqxzUFwCWAgAAAA==.Ravenmohr:BAAALgADCgUJBQAAAA==.',
Re='Rennai:BAAALgADCggJCAAAAA==.',
Rh='Rhebeqa:BAAALgADCgkJEAABLgAECgUJDQAMAAAAAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8jAAIBAAgJNSEGCgDFAgABAAgJNSEGCgDFAgAAAA==.Rist:BAABLgAECn8gAAIWAAkJAxAbFQB6AQAWAAkJAxAbFQB6AQAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAAALgAECgQJBAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAABLgAECn8bAAIOAAgJThJNHgCuAQAOAAgJThJNHgCuAQAAAA==.',
Sc='Scarhide:BAAALgAECgYJBgAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMdAAkJESP5BwBoAgAdAAYJBCX5BwBoAgATAAUJZx5iJACYAQABLgAECgYJCQAMAAAAAA==.',
Sh='Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8bAAIdAAcJThTKCQBjAQAdAAcJThTKCQBjAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAUJEgALAFcZAA==.',
Si='Silvanthos:BAAALgAECgQJBwAAAA==.Silvers:BAAALgAECgUJCwAAAA==.',
Sl='Sliccie:BAABLgAECn8sAAIGAAgJIBJtTgCZAQAGAAgJIBJtTgCZAQAAAA==.',
Sm='Smitegoat:BAACLgAFFH8JAAMjAAQJSwj0HgARAQAjAAQJDQj0HgARAQAOAAEJ/gxJLQA3AAAuAAQKfygAAw4ACQleHJ8UADkCAA4ACAnzGZ8UADkCACMAAwmFHZA4AP0AAAAA.',
Sn='Sney:BAABLgAECn8cAAIfAAYJBQizUADEAAAfAAYJBQizUADEAAABLgAECgYJHgASALsNAA==.',
So='Solar:BAAALgAECgkJAQAAAA==.Sorlzul:BAAALgAECgMJBwAAAA==.Sound:BAAALgAECgEJAgABLgAECgMJAwAMAAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8bAAIXAAcJWA6PZQBLAQAXAAcJWA6PZQBLAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAgJHgAVAO0XAA==.Taiurag:BAAALgAECgUJEwAAAA==.Taken:BAABLgAECn8ZAAIPAAYJvQXszADXAAAPAAYJvQXszADXAAAAAA==.Tazra:BAABLgAECn8xAAIIAAkJ9h62IwBWAgAIAAkJ9h62IwBWAgAAAA==.Tazzy:BAAALgAECgMJAwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8pAAIFAAkJIxMRGwDxAQAFAAkJIxMRGwDxAQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tonkatruck:BAABLgAECn8bAAIIAAgJORSQSgDIAQAIAAgJORSQSgDIAQAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMOAAgJYwjxMAAkAQAOAAgJCwfxMAAkAQAjAAYJYwcJMQAYAQAAAA==.Tuyenlotus:BAABLgAECn8nAAIkAAkJtxzaBQBTAgAkAAkJtxzaBQBTAgAAAA==.',
Un='Unholypriest:BAAALgAECgYJCwAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAABLgAECn8YAAIfAAYJyhHNPwAEAQAfAAYJyhHNPwAEAQAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8hAAITAAcJ+QlZPgAJAQATAAcJ+QlZPgAJAQAAAA==.Vesia:BAABLgAECn8YAAMOAAYJZRhVKgBSAQAOAAYJZRhVKgBSAQANAAQJYBPZPwD4AAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.Viscera:BAAALgADCgEJAQAAAA==.',
Vo='Voidrat:BAAALgAECgEJBAABLgAECggJLwABADAbAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
['Ví']='Ví:BAABLgAECn8hAAQlAAcJcwizCQC/AAAPAAcJvgSAvwDtAAAlAAUJXQqzCQC/AAAmAAEJAADaEQAAAAAAAA==.',
Wa='Warfare:BAAALgAECgYJCwABLgAECgkJJQAcAIkHAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.Whitezi:BAAALgADCgYJBgAAAA==.',
Wi='Wildpally:BAAALgAECgUJEwAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn8sAAMPAAkJGRbMQQD7AQAPAAkJJxPMQQD7AQAlAAQJmheVCwAcAQAAAA==.',
Yu='Yulíana:BAAALgAECgUJCQAAAA==.',
Za='Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn8iAAMXAAcJhRK0VwBvAQAXAAcJhRK0VwBvAQAbAAEJ4QFKmgAZAAAAAA==.',
Ze='Zelara:BAABLgAFFH8GAAIYAAIJUBEwGQBzAAAYAAIJUBEwGQBzAAAAAA==.Zertloc:BAABLgAECn8tAAIfAAgJMRyPFQAPAgAfAAgJMRyPFQAPAgAAAA==.',
Zh='Zhaan:BAAALgAECgMJAwAAAA==.',
Zi='Zieda:BAABLgAECn8oAAIDAAgJXhiYFQD7AQADAAgJXhiYFQD7AQAAAA==.Ziti:BAAALgADCgIJAgAAAA==.',
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
