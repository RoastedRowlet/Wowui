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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Druid-Balance','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Rogue-Subtlety','Monk-Mistweaver','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','Monk-Brewmaster','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','DemonHunter-Vengeance','Druid-Feral','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Unknown-Unknown',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-05-30',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8rAAIBAAgJgSFUAQCIAgABAAgJgSFUAQCIAgAAAA==.',
Ai='Airrows:BAABLgAECn84AAMCAAkJdyQJAQAgAwACAAkJdyQJAQAgAwADAAQJKRiLOgDSAAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDAAAAA==.Alurea:BAABLgAECn8tAAMEAAgJgAnTWgAVAQAEAAgJgAnTWgAVAQAFAAYJWQsBRADgAAAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxnZFABQAgAHAAkJbxnZFABQAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIIAAkJFSWCAQBPAwAIAAkJFSWCAQBPAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAIJAAkJPRDpUADRAQAJAAkJPRDpUADRAQAAAA==.Astragos:BAABLgAECn8jAAQKAAgJaRzwCABKAgAKAAcJVB3wCABKAgALAAcJwBudBwCtAQAMAAcJwhA4OAAVAQAAAA==.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn8sAAMNAAgJHiTkBAC/AgANAAgJHiTkBAC/AgAOAAIJOxILZgA2AAAAAA==.',
Be='Beastius:BAAALgAECgIJBAAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8wAAIPAAgJJBvAEgAVAgAPAAgJJBvAEgAVAgAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8ZAAIQAAcJlwuiDgBHAQAQAAcJlwuiDgBHAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJBwAAAA==.Boney:BAAALgAECgQJBQAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAIJAAkJCxuBJgBrAgAJAAkJCxuBJgBrAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8JAAIRAAMJEBh4CQDPAAARAAMJEBh4CQDPAAABLgAFFAcJGQAJABgTAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAECgIJAgABLgAECgkJFgAHAI8XAA==.Catelaya:BAABLgAECn84AAISAAkJYyBTEwChAgASAAkJYyBTEwChAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAITAAkJ5Q/QPQC5AQATAAkJ5Q/QPQC5AQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAIUAAIJDiS0YgDIAAAUAAIJDiS0YgDIAAAuAAQKfxkAAhQACAl+GutDABgCABQACAl+GutDABgCAAAA.Chexk:BAABLgAECn8yAAIVAAkJbiDZBQDAAgAVAAkJbiDZBQDAAgAAAA==.Chillfu:BAABLgAECn8hAAIPAAkJ8xaSEgAXAgAPAAkJ8xaSEgAXAgAAAA==.Chixnu:BAAALgAECgcJDQAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAAALgAECgcJDQAAAA==.Counsel:BAAALgAFFAIJAgAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAABLgAFFH8GAAIWAAIJhxBAOwBxAAAWAAIJhxBAOwBxAAABLgAFFAQJDwAEAMceAA==.Cryblood:BAABLgAECn8kAAIXAAgJGxMFIwCQAQAXAAgJGxMFIwCQAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIYAAkJGxvlBgBuAgAYAAkJGxvlBgBuAgAAAA==.',
Cy='Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJCQAAAA==.Dalynn:BAABLgAECn8wAAIUAAgJng7vcAByAQAUAAgJng7vcAByAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAINAAgJfB+TCQCBAgANAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMZAAgJ/BTmGgBrAQAZAAgJ/BTmGgBrAQAaAAEJngOvcAEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgMJAwAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8yAAITAAkJew8ARgCdAQATAAkJew8ARgCdAQAAAA==.',
Du='Dunkie:BAAALgAECgcJEgAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH8GAAIXAAYJBRkDCAC1AQAXAAYJBRkDCAC1AQAAAA==.Ellaryas:BAAALgAECggJEQAAAA==.',
Em='Em:BAACLgAFFH8PAAIbAAUJfxMyGABqAQAbAAUJfxMyGABqAQAuAAQKfxcABBsACQltHEMPAEkCABsACQltHEMPAEkCABcABAlQEVlGAMwAABEAAQk1DSaCAC8AAAAA.',
Er='Eraline:BAABLgAECn9FAAIWAAkJCBlHDwCNAgAWAAkJCBlHDwCNAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8dAAIaAAcJwCKJQgDoAQAaAAcJwCKJQgDoAQAAAA==.',
Fi='Fizzlepriest:BAAALgAECgYJDwABLgAFFAMJBQAUALkMAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8iAAIcAAgJLRh1AwA3AgAcAAgJLRh1AwA3AgAuAAQKfyQAAhwACQnCI+4DAP8CABwACQnCI+4DAP8CAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAITAAYJNwEe/QAxAAATAAYJNwEe/QAxAAAAAA==.',
Gh='Ghost:BAABLgAECn8ZAAIdAAgJlBO1BwDjAQAdAAgJlBO1BwDjAQAAAA==.',
Gi='Gilden:BAABLgAECn8aAAMeAAcJEQjWYwARAQAeAAcJEQjWYwARAQAfAAMJYgO8egBdAAAAAA==.',
Gn='Gnot:BAAALgAECggJCQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMEAAgJVBq5HQBQAgAEAAgJVBq5HQBQAgAFAAUJXBO/NwAaAQAAAA==.',
Gy='Gyoza:BAABLgAECn8XAAMeAAkJpBpcDwDAAgAeAAkJpBpcDwDAAgAfAAUJXRV2QwAJAQABLgAECgkJKQAHAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8cAAIIAAgJnRasEwDUAQAIAAgJnRasEwDUAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMSAAkJfBMWNQDyAQASAAkJfBMWNQDyAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8VAAIEAAYJmQyEXwAFAQAEAAYJmQyEXwAFAQAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn8+AAQKAAgJ8xe2CQA4AgAKAAgJ8xe2CQA4AgALAAQJkA8vEgDTAAAMAAQJhAqrXwCTAAAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAABLgAECn8ZAAQUAAcJ3A0nmQAnAQAUAAcJmQ0nmQAnAQAgAAQJawmTMgCAAAAHAAEJoQEtlQAdAAAAAA==.Isilod:BAAALgAECgcJDgAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMIAAkJeSQ2AwBSAwAIAAkJySM2AwBSAwAhAAkJ3yCBAgDAAgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8ZAAMYAAgJ5AcfNgCnAAAiAAYJmAcyIQDTAAAYAAcJyQYfNgCnAAAAAA==.Juuzau:BAAALgAECgcJDgAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8OAAIbAAQJrw7wIQAJAQAbAAQJrw7wIQAJAQAuAAQKfy8AAhsACAljFNYXAPMBABsACAljFNYXAPMBAAAA.Kaners:BAABLgAFFH8GAAIVAAQJBxPAFgA+AQAVAAQJBxPAFgA+AQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIUAAcJDyHaOAAGAgAUAAcJDyHaOAAGAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAUAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJFAAEAAEbAA==.',
Ke='Kealey:BAAALgAECgYJEwAAAA==.Keine:BAAALgAECgQJBAAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhVHHgDoAQAGAAkJkxJHHgDoAQAOAAUJFRJbMgDiAAAAAA==.',
Kh='Khaless:BAABLgAECn8aAAINAAcJYRE5HgAnAQANAAcJYRE5HgAnAQAAAA==.',
Ki='Kiamors:BAABLgAECn8xAAMfAAgJMAJ6XACzAAAfAAgJMAJ6XACzAAAeAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJKQAHAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCLcAwAbAwAGAAkJWCLcAwAbAwAOAAIJUQpNcQAoAAAAAA==.Kreleing:BAAALgAECgQJBAAAAA==.',
Ky='Kyndris:BAAALgAECgMJAwAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAAALgAECggJEgAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAAALgAFFAIJAwAAAA==.',
Li='Liandra:BAABLgAECn8VAAMRAAYJ6wWYTwD6AAARAAYJ6wWYTwD6AAAXAAUJUgY7WgB+AAAAAA==.Lightfighter:BAABLgAECn8ZAAMUAAgJTgyjhwBGAQAUAAgJZgujhwBGAQAgAAQJlwrVMgB+AAABLgAECgkJFAAJAOkEAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJFAAJAOkEAA==.Lilkiwi:BAABLgAECn8aAAIJAAcJjwxpmwAoAQAJAAcJjwxpmwAoAQAAAA==.',
Lo='Loozer:BAAALgAECgEJAgAAAA==.Louhfu:BAABLgAECn8YAAIUAAcJdBXZeABiAQAUAAcJdBXZeABiAQAAAA==.',
Lu='Lunchbox:BAABLgAECn8rAAIDAAgJ2wqqIACJAQADAAgJ2wqqIACJAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB9uBgCvAgADAAkJwx5uBgCvAgASAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAIJAAQJIg+oUwArAQAJAAQJIg+oUwArAQAuAAQKfzgAAgkACQkDG8EtAEsCAAkACQkDG8EtAEsCAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgcJDQABLgAFFAcJGQAJABgTAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8GAAIFAAQJUglsIwDmAAAFAAQJUglsIwDmAAAuAAQKfx8AAgUACQmmEYQaAN0BAAUACQmmEYQaAN0BAAAA.',
Me='Meatfoot:BAAALgADCgcJBwAAAA==.Medie:BAABLgAECn9BAAMRAAkJnSGWBQAPAwARAAkJnSGWBQAPAwAXAAUJsw0QTgCwAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8rAAMUAAkJ+xzqHQB7AgAUAAkJ+xzqHQB7AgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAYJIAAUAEMjAA==.Najinsky:BAACLgAFFH8gAAIUAAYJQyO5BwALAgAUAAYJQyO5BwALAgAuAAQKfzIAAhQACQlFJagDAJYDABQACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Neikko:BAAALgAECgUJBQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgEJAQABLgAECggJGQAdAJQTAA==.Nellir:BAABLgAECn85AAMQAAkJWxXIBgDrAQAQAAkJWxXIBgDrAQAjAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Nitefall:BAAALgAECgUJBQAAAA==.',
No='Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8aAAIEAAcJFxdmLwDTAQAEAAcJFxdmLwDTAQAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECgYJDgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJGQAdAJQTAA==.',
Pu='Pulaski:BAAALgAECgUJBgAAAA==.Punchite:BAAALgAECggJDgABLgAECgkJOgAkACImAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAgAIAgAA==.Raymane:BAAALgAECggJEAAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAcJGQAJABgTAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgcJDgAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8RAAIHAAUJZhTnEwBwAQAHAAUJZhTnEwBwAQAuAAQKf0AAAwcACQlCG0sIAPICAAcACQlCG0sIAPICABQABgnUCf8nAWUAAAAA.',
Rh='Rhau:BAABLgAECn8YAAIlAAYJvR9ZCQAqAgAlAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAHAOocAA==.',
Ro='Rombo:BAABLgAECn8XAAIiAAYJgRt2EQB9AQAiAAYJgRt2EQB9AQAAAA==.Rosastrasza:BAAALgADCgMJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgUJCwAAAA==.Ryukie:BAAALgAECggJBgAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIUAAMJdR6vSgD8AAAUAAMJdR6vSgD8AAAuAAQKfx8AAhQACQm5IC8bAMYCABQACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAECgMJBAAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAECgQJBAAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAMJBQAUALkMAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgQJBwABLgAECgcJBwAmAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJAwAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIKAAkJuR/HAgAkAwAKAAkJuR/HAgAkAwAAAA==.Sinistra:BAABLgAECn8cAAIjAAkJzhTiNwDuAQAjAAkJzhTiNwDuAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAABLgAECn8UAAMiAAYJiBjhEgBrAQAiAAYJiBjhEgBrAQAYAAUJ+wKwVgBDAAABLgAFFAQJEAAgAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9RAAIUAAkJfCF5CAATAwAUAAkJfCF5CAATAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIaAAYJVRuNhAB5AQAaAAYJVRuNhAB5AQABLgAECgcJGgASAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Su='Suicidestyle:BAABLgAECn8YAAQlAAgJKA0pFADxAAAlAAgJKA0pFADxAAAQAAMJiAaJLABTAAAjAAEJhAcfNwEtAAAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJqBXFRAAaAQAGAAYJsxTFRAAaAQANAAUJKRXiMACjAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8kAAIfAAgJxh5aDgByAgAfAAgJxh5aDgByAgAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn84AAIfAAkJ8AwQLAB8AQAfAAkJ8AwQLAB8AQAAAA==.',
Va='Valcoree:BAAALgAECgMJAwABLgAECggJJwAXAJ4PAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAISAAgJByIrCQABAwASAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIHAAkJ6hxNDgCaAgAHAAkJ6hxNDgCaAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIWAAcJ3RTPIQClAQAWAAcJ3RTPIQClAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAYABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDAAmAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJBgAVADkWAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIkAAkJIiYcAABwAwAkAAkJIiYcAABwAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJDQAAAA==.Zeldoris:BAABLgAECn9FAAIgAAkJgCBpAwDIAgAgAAkJgCBpAwDIAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJGQAdAJQTAA==.',
Zi='Zillika:BAAALgAECgUJBwAAAA==.',
Zu='Zuk:BAAALgADCgYJBgAAAA==.Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJDAABLgAECggJHAAWAKkQAA==.',
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
