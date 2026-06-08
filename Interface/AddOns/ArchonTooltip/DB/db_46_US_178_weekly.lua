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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Rogue-Subtlety','Monk-Mistweaver','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','Monk-Brewmaster','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','DemonHunter-Vengeance','Druid-Feral','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Unknown-Unknown',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Aceieus:BAAALgAECgEJAQAAAA==.',
Ad='Adiaera:BAAALgAECgEJAQAAAA==.',
Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8uAAIBAAkJQCHIAADeAgABAAkJQCHIAADeAgAAAA==.',
Ai='Airrows:BAABLgAECn85AAMCAAkJdyQeAQAeAwACAAkJdyQeAQAeAwADAAQJKRgCPQDQAAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDAAAAA==.Alurea:BAABLgAECn8vAAMEAAkJXA1rNwApAQAEAAcJAQ1rNwApAQAFAAgJgAnFXgAQAQAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxlsFgBMAgAHAAkJbxlsFgBMAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIIAAkJFSXsAQBIAwAIAAkJFSXsAQBIAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAIJAAkJPRDFVQDVAQAJAAkJPRDFVQDVAQAAAA==.Astragos:BAABLgAECn8jAAQKAAgJaRxdCQBKAgAKAAcJVB1dCQBKAgALAAcJwBsXCACnAQAMAAcJwhA4OAAVAQAAAA==.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn8uAAMNAAkJBiREAgAfAwANAAkJBiREAgAfAwAOAAIJOxKgbQA2AAAAAA==.',
Be='Beastius:BAAALgAECgIJBAAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8yAAIPAAkJjRpnDgBWAgAPAAkJjRpnDgBWAgAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8hAAIQAAgJdAuADgBhAQAQAAgJdAuADgBhAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJCgAAAA==.Boney:BAAALgAECgQJBQAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAIJAAkJCxtKKQBuAgAJAAkJCxtKKQBuAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8JAAIRAAMJEBh4CQDPAAARAAMJEBh4CQDPAAABLgAFFAgJGgAJAKkSAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAECgIJAwABLgAECgkJFgAHAI8XAA==.Catelaya:BAABLgAECn84AAISAAkJYyDAFQCbAgASAAkJYyDAFQCbAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAITAAkJ5Q/fQgCzAQATAAkJ5Q/fQgCzAQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAIUAAIJDiQbbgDCAAAUAAIJDiQbbgDCAAAuAAQKfxkAAhQACAl+GutDABgCABQACAl+GutDABgCAAAA.Chexk:BAACLgAFFH8GAAIVAAMJdRvFIAAHAQAVAAMJdRvFIAAHAQAuAAQKfzQAAhUACQnsIB4FANoCABUACQnsIB4FANoCAAAA.Chillfu:BAABLgAECn8hAAIPAAkJ8xYCFAARAgAPAAkJ8xYCFAARAgAAAA==.Chixnu:BAAALgAECggJDgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAABLgAECn8VAAIIAAgJWghzKgAXAQAIAAgJWghzKgAXAQAAAA==.Counsel:BAAALgAFFAMJAwAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAABLgAFFH8GAAIWAAIJhxDMQwBvAAAWAAIJhxDMQwBvAAABLgAFFAQJFQAFAMceAA==.Cryblood:BAABLgAECn8lAAIXAAkJKBJ8HADaAQAXAAkJKBJ8HADaAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIYAAkJGxugBwBrAgAYAAkJGxugBwBrAgAAAA==.',
Cy='Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJEgAAAA==.Dalynn:BAABLgAECn8wAAIUAAgJng6YeQBwAQAUAAgJng6YeQBwAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAINAAgJfB+TCQCBAgANAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMZAAgJ/BSxHABoAQAZAAgJ/BSxHABoAQAaAAEJngOehAEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgMJAwAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8yAAITAAkJew+gSgCaAQATAAkJew+gSgCaAQAAAA==.',
Du='Dunkie:BAAALgAECggJEwAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH8OAAIXAAgJEBuPAQCYAgAXAAgJEBuPAQCYAgAAAA==.Ellaryas:BAAALgAFFAEJAQAAAA==.',
Em='Em:BAACLgAFFH8PAAIbAAUJfxP2GwBYAQAbAAUJfxP2GwBYAQAuAAQKfxcABBsACQltHEMPAEkCABsACQltHEMPAEkCABcABAlQEVlGAMwAABEAAQk1DSaCAC8AAAAA.Emaeel:BAAALgADCggJCAABLgAECgkJHwAWAHwSAA==.',
Er='Eraline:BAABLgAECn9GAAIWAAkJrBkDDwCfAgAWAAkJrBkDDwCfAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8eAAIaAAcJwCLoRgDmAQAaAAcJwCLoRgDmAQAAAA==.',
Fi='Fizzlemonk:BAAALgAECgkJCQABLgAFFAQJDAAUAEARAQ==.Fizzlepriest:BAAALgAECggJEQABLgAFFAQJDAAUAEARAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8nAAIcAAgJMxm8AgBqAgAcAAgJMxm8AgBqAgAuAAQKfyQAAhwACQnCI0gEAPwCABwACQnCI0gEAPwCAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAITAAYJNwGgBgE0AAATAAYJNwGgBgE0AAAAAA==.',
Gh='Ghost:BAABLgAECn8ZAAIdAAgJlBO1BwDjAQAdAAgJlBO1BwDjAQAAAA==.',
Gi='Gilden:BAABLgAECn8bAAMeAAgJzQcIXwAvAQAeAAgJzQcIXwAvAQAfAAMJYgPpggBaAAAAAA==.',
Gn='Gnot:BAAALgAECggJCQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMFAAgJVBq5HQBQAgAFAAgJVBq5HQBQAgAEAAUJXBN3OgAZAQAAAA==.',
Gy='Gyoza:BAABLgAECn8XAAMeAAkJpBrUEAC9AgAeAAkJpBrUEAC9AgAfAAUJXRUgRwAHAQABLgAECgkJKQAHAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8cAAIIAAgJnRZaFQDQAQAIAAgJnRZaFQDQAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMSAAkJfBPtOQDsAQASAAkJfBPtOQDsAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8VAAIFAAYJmQxMYgAEAQAFAAYJmQxMYgAEAQAAAA==.',
Im='Imperfect:BAAALgAECgEJAQAAAA==.',
In='Inazuma:BAABLgAECn8+AAQKAAgJ8xcnCgA5AgAKAAgJ8xcnCgA5AgALAAQJkA8TEwDNAAAMAAQJhAp4aQCQAAAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJDQAAAA==.',
Is='Ishatani:BAABLgAECn8aAAQUAAgJqwymiABTAQAUAAgJcgymiABTAQAgAAQJawkcNQB/AAAHAAEJoQG7mgAdAAAAAA==.Isilod:BAAALgAECgcJDwAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMIAAkJeSQ2AwBSAwAIAAkJySM2AwBSAwAhAAkJ3yDFAgC6AgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8ZAAMYAAgJ5Ad7OwCkAAAiAAYJmAcyIQDTAAAYAAcJyQZ7OwCkAAABLgAFFAQJEwAcAKICAA==.Juuzau:BAAALgAECgcJDgAAAA==.',
['Jå']='Jåmes:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8RAAIbAAQJOBDCIwAOAQAbAAQJOBDCIwAOAQAuAAQKfzQAAhsACAljFFEZAPkBABsACAljFFEZAPkBAAAA.Kaners:BAABLgAFFH8JAAIVAAQJzBmvEwBcAQAVAAQJzBmvEwBcAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIUAAcJDyFOPQAEAgAUAAcJDyFOPQAEAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAUAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJGwAFAHcfAA==.',
Ke='Kealey:BAABLgAECn8aAAIUAAcJfAzVowAmAQAUAAcJfAzVowAmAQAAAA==.Keine:BAAALgAECgQJBAAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhVGIADnAQAGAAkJkxJGIADnAQAOAAUJFRLJNQDiAAAAAA==.',
Kh='Khaless:BAABLgAECn8bAAINAAgJbw+VHABFAQANAAgJbw+VHABFAQAAAA==.',
Ki='Kiamors:BAABLgAECn83AAMfAAkJsAIhVwDPAAAfAAkJsAIhVwDPAAAeAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJKQAHAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCKFBAAWAwAGAAkJWCKFBAAWAwAOAAIJUQqLeAAoAAAAAA==.Kreleing:BAAALgAECgQJBAAAAA==.',
Ky='Kyndris:BAAALgAECgMJAwAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAAALgAECggJEwAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAAALgAFFAIJBAAAAA==.',
Li='Liandra:BAABLgAECn8VAAMRAAYJ6wWYTwD6AAARAAYJ6wWYTwD6AAAXAAUJUgZgXACXAAAAAA==.Lightfighter:BAABLgAECn8aAAMUAAgJJw3giABTAQAUAAgJPwzgiABTAQAgAAQJlwr9NQB7AAABLgAECgkJHwAJAAsHAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJHwAJAAsHAA==.Lilkiwi:BAABLgAECn8bAAIJAAgJqAv5hABnAQAJAAgJqAv5hABnAQAAAA==.',
Lo='Loozer:BAAALgAFFAEJAQAAAA==.Louhfu:BAABLgAECn8YAAIUAAcJdBVZgQBhAQAUAAcJdBVZgQBhAQAAAA==.',
Lu='Lunchbox:BAABLgAECn8zAAIDAAgJCQwiHwCeAQADAAgJCQwiHwCeAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB8cBwCpAgADAAkJwx4cBwCpAgASAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAIJAAQJIg8/XAAnAQAJAAQJIg8/XAAnAQAuAAQKfzgAAgkACQkDGxkxAE4CAAkACQkDGxkxAE4CAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAFFAIJAgABLgAFFAgJGgAJAKkSAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8GAAIEAAQJUgkNJwDkAAAEAAQJUgkNJwDkAAAuAAQKfx8AAgQACQmmEZQcANcBAAQACQmmEZQcANcBAAAA.',
Me='Meatfoot:BAAALgADCgcJCAAAAA==.Medie:BAABLgAECn9BAAMRAAkJnSH5BgDdAgARAAkJnSH5BgDdAgAXAAUJsw3rTwDGAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8uAAMUAAkJOB3xGgCZAgAUAAkJOB3xGgCZAgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAYJIQAUADcmAA==.Najinsky:BAACLgAFFH8hAAIUAAYJNyagCAAeAgAUAAYJNyagCAAeAgAuAAQKfzIAAhQACQlFJagDAJYDABQACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Neikko:BAAALgAECgUJBQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgQJBAABLgAECggJGQAdAJQTAA==.Nellir:BAABLgAECn86AAMQAAkJWxWwBwDiAQAQAAkJWxWwBwDiAQAjAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Nitefall:BAAALgAECgUJBQAAAA==.',
No='Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8bAAIFAAgJFBf1JQAVAgAFAAgJFBf1JQAVAgAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECggJEgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJGQAdAJQTAA==.',
Pu='Pulaski:BAAALgAECgUJBgAAAA==.Punchite:BAAALgAECggJDwABLgAECgkJOgAkACImAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAgAIAgAA==.Raymane:BAAALgAECggJEAAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAgJGgAJAKkSAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgcJEAAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8SAAIHAAUJZhTRFgBiAQAHAAUJZhTRFgBiAQAuAAQKf00AAwcACQnDGzgIAP0CAAcACQnDGzgIAP0CABQABgnUCcA2AWYAAAAA.',
Rh='Rhau:BAABLgAECn8YAAIlAAYJvR9ZCQAqAgAlAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAHAOocAA==.',
Ro='Rombo:BAABLgAECn8XAAIiAAYJgRv2EgB8AQAiAAYJgRv2EgB8AQAAAA==.Rosastrasza:BAAALgADCgMJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgUJDgAAAA==.Ryukie:BAAALgAECggJDAAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIUAAMJdR4xVgDwAAAUAAMJdR4xVgDwAAAuAAQKfx8AAhQACQm5IC8bAMYCABQACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAECgUJBgAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAECgYJCwAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAQJDAAUAEARAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgQJBwABLgAECgcJBwAmAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIKAAkJuR/sAgAjAwAKAAkJuR/sAgAjAwAAAA==.Sinistra:BAABLgAECn8cAAIjAAkJzhReOwDoAQAjAAkJzhReOwDoAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAABLgAECn8UAAMiAAYJiBh9FABpAQAiAAYJiBh9FABpAQAYAAUJ+wJ+XwBCAAABLgAFFAQJEAAgAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9aAAIUAAkJzyG+BwAnAwAUAAkJzyG+BwAnAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgQJBAAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIaAAYJVRuNhAB5AQAaAAYJVRuNhAB5AQABLgAECgcJGgASAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Stewpedassol:BAAALgAECgEJAgAAAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Su='Suicidestyle:BAABLgAECn8YAAQlAAgJKA1fFQDwAAAlAAgJKA1fFQDwAAAQAAMJiAa1LwBTAAAjAAEJhAfvQgEsAAAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJqBVwSAAaAQAGAAYJsxRwSAAaAQANAAUJKRUbMwCiAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Tootsniffa:BAAALgAECgEJAQAAAA==.Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8kAAIfAAgJxh7ZDwBrAgAfAAgJxh7ZDwBrAgAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn84AAIfAAkJ8AxpLwB0AQAfAAkJ8AxpLwB0AQAAAA==.',
Va='Valcoree:BAAALgAECgQJBAABLgAECggJKQAXACwQAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAISAAgJByIrCQABAwASAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIHAAkJ6hxvDwCWAgAHAAkJ6hxvDwCWAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAACLgAFFH8FAAIWAAMJ1AvmOwCTAAAWAAMJ1AvmOwCTAAAuAAQKfxQAAhYABwndFM8hAKUBABYABwndFM8hAKUBAAAA.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAYABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDAAmAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJCQAVADkWAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIkAAkJIiYoAABoAwAkAAkJIiYoAABoAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJDQAAAA==.Zeldoris:BAABLgAECn9FAAIgAAkJgCDPAwDDAgAgAAkJgCDPAwDDAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJGQAdAJQTAA==.',
Zi='Zillika:BAAALgAFFAEJAQAAAA==.',
Zu='Zuk:BAAALgADCgYJBgAAAA==.Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJDAABLgAECgkJHwAWAHwSAA==.',
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
