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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Druid-Balance','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Rogue-Subtlety','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','Monk-Mistweaver','Monk-Brewmaster','Rogue-Assassination','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Mage-Arcane','Paladin-Protection','Warlock-Destruction','Druid-Feral',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-05-16',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8hAAIBAAgJgyD1AAB9AgABAAgJgyD1AAB9AgAAAA==.',
Ai='Airrows:BAABLgAECn8vAAMCAAkJfiS8AADCAgACAAkJfiS8AADCAgADAAQJKRhrLgDcAAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgUJBwAAAA==.Alurea:BAABLgAECn8lAAMEAAgJYQmeTQASAQAEAAgJYQmeTQASAQAFAAUJZApuQQCyAAAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkBLQLAABAgAGAAgJkBLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxmYDgBkAgAHAAkJbxmYDgBkAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAQAAAA==.Argonäut:BAABLgAECn8wAAIIAAkJDiXqAABQAwAIAAkJDiXqAABQAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8sAAIJAAgJIBCBXACKAQAJAAgJIBCBXACKAQAAAA==.Astragos:BAABLgAECn8iAAQKAAgJaRzQBgBQAgAKAAcJVB3QBgBQAgALAAcJwBtsBQDBAQAMAAcJwhA4OAAVAQAAAA==.',
Az='Azagorod:BAAALgAECgEJAQAAAA==.',
Ba='Baern:BAABLgAECn8kAAMNAAgJRCADBgBtAgANAAgJRCADBgBtAgAOAAIJOxJZTQA2AAAAAA==.',
Be='Beaconstrips:BAACLgAFFH8LAAIHAAQJxRRMEwBAAQAHAAQJxRRMEwBAAQAuAAQKfzkAAwcACQk3FsQPAFUCAAcACQk3FsQPAFUCAA8ABgnUCWf1AGcAAAAA.Beastius:BAAALgAECgEJAQAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8lAAIQAAgJSBfREwDPAQAQAAgJSBfREwDPAQAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8ZAAIRAAcJlwuiDgBHAQARAAcJlwuiDgBHAQAAAA==.',
Bo='Boney:BAAALgAECgEJAgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn8sAAIJAAkJGBqDJgBBAgAJAAkJGBqDJgBBAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8JAAISAAMJEBh4CQDPAAASAAMJEBh4CQDPAAABLgAFFAYJFwAJAI0VAA==.',
Ca='Caiki:BAAALgAECggJEgAAAA==.Catelaya:BAABLgAECn84AAITAAkJZCBBCgDEAgATAAkJZCBBCgDEAgAAAA==.Cathulu:BAAALgADCgYJBgAAAA==.',
Ce='Celithatha:BAABLgAECn8WAAIUAAkJfwmBSwBWAQAUAAkJfwmBSwBWAQAAAA==.',
Ch='Chaness:BAABLgAECn8ZAAIPAAgJfRrrQwAYAgAPAAgJfRrrQwAYAgAAAA==.Chexk:BAABLgAECn8wAAIVAAkJhSBAAwDZAgAVAAkJhSBAAwDZAgAAAA==.Chillfu:BAABLgAECn8fAAIQAAgJJBYIFQDAAQAQAAgJJBYIFQDAAQAAAA==.Chixnu:BAAALgAECgYJBgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAAALgAFFAIJAwAAAA==.Cryblood:BAABLgAECn8gAAIWAAcJQRP2IgBbAQAWAAcJQRP2IgBbAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn8tAAIXAAkJVBdLCAAHAgAXAAkJVBdLCAAHAgAAAA==.',
Cy='Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Dalynn:BAABLgAECn8dAAIPAAgJSQfFgQAiAQAPAAgJSQfFgQAiAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAgAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAINAAgJex9sCAAtAgANAAgJex9sCAAtAgAAAA==.Djiink:BAABLgAECn8aAAMYAAgJ+xTaFgCpAQAYAAgJ+xTaFgCpAQAZAAEJngOiLwEhAAAAAA==.',
Do='Doomlocke:BAAALgADCgEJAQAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8tAAIUAAkJUw3xQAB6AQAUAAkJUw3xQAB6AQAAAA==.',
Du='Dunkie:BAAALgAECgUJCwAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgADCgQJBAAAAA==.',
El='Ellaryas:BAAALgAECgEJAQAAAA==.',
Em='Em:BAACLgAFFH8IAAIaAAQJyxWEFQA3AQAaAAQJyxWEFQA3AQAuAAQKfxcABBoACQltHEMPAEkCABoACQltHEMPAEkCABYABAlQEVlGAMwAABIAAQk1DSaCAC8AAAAA.',
Er='Eraline:BAABLgAECn81AAIbAAgJ8heKEgAgAgAbAAgJ8heKEgAgAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8YAAIZAAcJwCIfNQDlAQAZAAcJwCIfNQDlAQAAAA==.',
Fi='Fizzlepriest:BAAALgAECgQJBAABLgAECgcJLgAPAM0fAQ==.',
Fl='Flaciddream:BAAALgAECgQJBAAAAA==.',
Fr='Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJBwAAAA==.Froststorm:BAAALgAECgEJAQAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8aAAIcAAcJzhiMAgDGAQAcAAcJzhiMAgDGAQAuAAQKfyQAAhwACQnCI4ECAAsDABwACQnCI4ECAAsDAAAA.',
Ge='Genivan:BAAALgADCgMJAwAAAA==.Genocya:BAAALgAECgYJEAAAAA==.',
Gh='Ghost:BAABLgAECn8YAAIdAAgJXxK1BwDjAQAdAAgJXxK1BwDjAQAAAA==.',
Gi='Gilden:BAAALgAECgYJEwAAAA==.',
Gn='Gnot:BAAALgAECgIJAgAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8rAAMEAAgJlBy5HQBQAgAEAAcJlhy5HQBQAgAFAAUJXBONKwAfAQAAAA==.',
Gy='Gyoza:BAAALgAECgkJDAABLgAECgkJKQAHAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8WAAIIAAgJ1BLCEwCSAQAIAAgJ1BLCEwCSAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMTAAkJexPDJAAAAgATAAkJexPDJAAAAgACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8VAAIEAAYJmQy2UQADAQAEAAYJmQy2UQADAQAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn88AAQKAAgJqRY4CAApAgAKAAgJqRY4CAApAgALAAQJkA+RDgDfAAAMAAQJhApMVACGAAAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAAALgAECgYJEgAAAA==.Isilod:BAAALgAECgYJBgAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMIAAkJeSQ2AwBSAwAIAAkJySM2AwBSAwAeAAkJ3iB7AQDWAgAAAA==.',
Iy='Iyotanka:BAAALgAECgEJAgAAAA==.',
Ju='Juicebox:BAAALgAECgYJEQABLgAECgkJEgAfAAAAAA==.Juuzau:BAAALgAECgcJDQAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8GAAIaAAMJyQl/IADMAAAaAAMJyQl/IADMAAAuAAQKfyoAAhoACAn8Ev4UAN0BABoACAn8Ev4UAN0BAAAA.Kaners:BAAALgAFFAMJAwAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Katheryn:BAABLgAECn8jAAIPAAcJDyGrKAAYAgAPAAcJDyGrKAAYAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJIwAPAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAgJIgAgAA8hAA==.',
Ke='Kealey:BAAALgAECgYJDQAAAA==.Keine:BAAALgAECgQJBAAAAA==.Kessik:BAABLgAECn8eAAMGAAkJhRM8KwBbAQAGAAkJRRA8KwBbAQAOAAUJ5xGgIwDrAAAAAA==.',
Kh='Khaless:BAAALgAECgYJEwAAAA==.',
Ki='Kiamors:BAABLgAECn8mAAMhAAgJ2AEDUAChAAAhAAgJ2AEDUAChAAAgAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJCQABLgAECgkJKQAHAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8dAAMGAAgJhB/cCgBzAgAGAAgJhB/cCgBzAgAOAAIJUQpEVQAqAAAAAA==.Kreleing:BAAALgAECgQJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAAALgAECgEJAgAAAA==.',
Le='Leda:BAAALgAECgEJAgAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAAALgAECgUJBQAAAA==.',
Li='Liandra:BAABLgAECn8VAAMSAAYJ6wWYTwD6AAASAAYJ6wWYTwD6AAAWAAUJUgapRQCeAAAAAA==.Lightfighter:BAAALgAECggJEgABLgAECgkJEwAfAAAAAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJEwAfAAAAAA==.Lilkiwi:BAAALgAECgYJEwAAAA==.',
Lo='Louhfu:BAABLgAECn8YAAIPAAcJcxVOXwBqAQAPAAcJcxVOXwBqAQAAAA==.',
Lu='Lunchbox:BAABLgAECn8hAAIDAAcJYQmVIQBCAQADAAcJYQmVIQBCAQAAAA==.Lunecy:BAABLgAECn8pAAQDAAkJIh4zBQCgAgADAAkJwR0zBQCgAgATAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8LAAIJAAMJ4Q9UWQDyAAAJAAMJ4Q9UWQDyAAAuAAQKfzUAAgkACAntGwY9AOYBAAkACAntGwY9AOYBAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgYJCAABLgAFFAYJFwAJAI0VAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAAALgAECggJEwAAAA==.',
Me='Medie:BAABLgAECn8tAAMSAAkJYx/5BgDdAgASAAkJYx/5BgDdAgAWAAQJ4wsFSACSAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8rAAMPAAkJ+xwHEwCWAgAPAAkJ+xwHEwCWAgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAUJGQAPAO0kAA==.Najinsky:BAACLgAFFH8ZAAIPAAUJ7SRPCAC2AQAPAAUJ7SRPCAC2AQAuAAQKfzIAAg8ACQlEJc0CAE0DAA8ACQlEJc0CAE0DAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgEJAQABLgAECgkJJgAWAJQYAA==.Neikko:BAAALgAECgUJBQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nellir:BAABLgAECn8yAAMRAAgJ9BX8BQC5AQARAAgJ9BX8BQC5AQAiAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Nitefall:BAAALgADCgEJAQAAAA==.',
No='Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAAALgAECgYJEwAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECgYJCQAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJGAAdAF8SAA==.',
Pu='Pulaski:BAAALgAECgUJBQAAAA==.Punchite:BAAALgAECgYJBgABLgAECggJOQAjADImAA==.',
Ra='Ramarl:BAAALgADCgkJCgABLgAECgkJNQAkAFggAA==.Raymane:BAAALgAECgIJAgAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAYJFwAJAI0VAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgMJBAAAAA==.Retkrag:BAAALgADCgMJAwABLgAECggJHQAGAIQfAA==.Revenger:BAAALgADCgYJBgAAAA==.',
Rh='Rhau:BAABLgAECn8YAAIlAAYJvR9ZCQAqAgAlAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgAAAA==.',
Ro='Rombo:BAABLgAECn8XAAImAAYJgRsODQCHAQAmAAYJgRsODQCHAQAAAA==.Rosastrasza:BAAALgADCgMJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgUJCAAAAA==.Ryukie:BAAALgAECgUJBgAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIPAAMJdR6pLwAbAQAPAAMJdR6pLwAbAQAuAAQKfx8AAg8ACQm5IC8bAMYCAA8ACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgQJBwAAAA==.',
Se='Serenna:BAAALgAECgIJAwAAAA==.Serios:BAAALgAECgIJAwAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAECgcJLgAPAM0fAQ==.Sharun:BAAALgAECgYJBgAAAA==.Sharundito:BAAALgAECgQJBwABLgAECgYJBgAfAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAECgQJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8tAAIKAAkJvR/aAQAzAwAKAAkJvR/aAQAzAwAAAA==.Sinistra:BAABLgAECn8cAAIiAAkJzRRdKQD5AQAiAAkJzRRdKQD5AQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAAALgAECgYJEAAAAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9DAAIPAAkJpx5GEQCjAgAPAAkJpx5GEQCjAgAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIZAAYJVRuNhAB5AQAZAAYJVRuNhAB5AQABLgAECgcJGgATAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.',
Su='Suicidestyle:BAABLgAECn8YAAQlAAgJJw07EADyAAAlAAgJJw07EADyAAARAAMJiAZRHwBUAAAiAAEJhAdACgEuAAAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgMJBAAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJpxVaNAAqAQAGAAYJsxRaNAAqAQANAAUJKBUHKQClAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJCwAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgAECgEJAQAAAA==.Touraine:BAABLgAECn8YAAIhAAcJKxzxGADJAQAhAAcJKxzxGADJAQAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn8wAAIhAAkJCQscJwBdAQAhAAkJCQscJwBdAQAAAA==.',
Va='Valcoree:BAAALgAECgMJAwAAAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAITAAgJByIrCQABAwATAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vibenout:BAAALgADCgMJAwAAAA==.Vinil:BAAALgAECgEJAgAAAA==.',
Vo='Vorastrix:BAAALgAECgEJAgAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJEgAAAA==.',
Wa='Waivern:BAABLgAECn8fAAIHAAkJXRzQCgCYAgAHAAkJXRzQCgCYAgAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIbAAcJ3RTPIQClAQAbAAcJ3RTPIQClAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJLQAXAFQXAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgEJAQAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgUJBwAfAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAIJBAAfAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn85AAIjAAgJMiZfAABQAwAjAAgJMiZfAABQAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgYJBwAAAA==.Zeldoris:BAABLgAECn81AAIkAAkJWCCzAgCyAgAkAAkJWCCzAgCyAgAAAA==.Zenelf:BAAALgAECgUJBgABLgAECggJGAAdAF8SAA==.',
Zi='Zillika:BAAALgAECgUJBgAAAA==.',
Zu='Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJBwABLgAECggJEAAfAAAAAA==.',
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
