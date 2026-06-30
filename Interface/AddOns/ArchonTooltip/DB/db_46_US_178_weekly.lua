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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Warrior-Fury','Paladin-Holy','Shaman-Restoration','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Rogue-Subtlety','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Elemental','Priest-Discipline','Rogue-Assassination','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Warlock-Destruction',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-06-27',data={Ac='Aceieus:BAAALgAECgEJAQAAAA==.',
Ad='Adiaera:BAAALgAECgEJAQAAAA==.',
Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8uAAIBAAkJQCH3AADXAgABAAkJQCH3AADXAgAAAA==.',
Ai='Airrows:BAACLgAFFH8EAAICAAMJahZ+GAD0AAACAAMJahZ+GAD0AAAuAAQKfzsAAwIACQl3JCEBACoDAAIACQl3JCEBACoDAAMABAkpGAA/AM4AAAAA.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDQAAAA==.Alurea:BAABLgAECn8yAAMEAAkJjw5aOwAkAQAEAAcJVg1aOwAkAQAFAAgJeguCYgANAQAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxm9FwBLAgAHAAkJbxm9FwBLAgABLgAECgkJIQAIAKQaAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIJAAkJFSVgAgBBAwAJAAkJFSVgAgBBAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAIKAAkJPRD2WwDKAQAKAAkJPRD2WwDKAQAAAA==.Astragos:BAACLgAFFH8GAAILAAMJVxYiCQB5AAALAAMJVxYiCQB5AAAuAAQKfyUABAsACAmFHG0JAFECAAsABwlzHW0JAFECAAwABwnAG5sIAKUBAA0ABwnJEjg4ABUBAAAA.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn8zAAMOAAkJBiSoAgAYAwAOAAkJBiSoAgAYAwAPAAIJOxIBdgA2AAAAAA==.',
Be='Beastius:BAAALgAECgIJBQAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.Belladari:BAAALgAECgEJAQAAAA==.',
Bi='Billamong:BAABLgAECn83AAIQAAkJNRtpDwBUAgAQAAkJNRtpDwBUAgAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8oAAIRAAgJHw+3DACQAQARAAgJHw+3DACQAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJCwAAAA==.Boney:BAAALgAECgYJDQAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAIKAAkJCxsHLABpAgAKAAkJCxsHLABpAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8KAAISAAQJtxJ4CQDPAAASAAQJtxJ4CQDPAAABLgAFFAgJGwAKAEUTAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAFFAEJAQAAAA==.Catelaya:BAABLgAECn84AAITAAkJYyBuGACUAgATAAkJYyBuGACUAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAIUAAkJ5Q8NRgC1AQAUAAkJ5Q8NRgC1AQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAIVAAIJDiQWfQC8AAAVAAIJDiQWfQC8AAAuAAQKfxkAAhUACAl+GutDABgCABUACAl+GutDABgCAAAA.Chexk:BAACLgAFFH8MAAIWAAQJ4RyPFgBYAQAWAAQJ4RyPFgBYAQAuAAQKfzYAAhYACQkZIkUEAPkCABYACQkZIkUEAPkCAAAA.Chillfu:BAACLgAFFH8GAAIQAAQJ7BihBwCxAAAQAAQJ7BihBwCxAAAuAAQKfyEAAhAACQnzFqsVAAsCABAACQnzFqsVAAsCAAAA.Chillycowpie:BAAALgAECgEJAQAAAA==.Chixnu:BAAALgAECgkJEwAAAA==.',
Ci='Cillina:BAAALgAECgEJAgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAABLgAECn8eAAIJAAkJxwiqAgA1AQAJAAkJxwiqAgA1AQAAAA==.Counsel:BAAALgAFFAMJBAAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAABLgAFFH8LAAMXAAMJmxJuFgCTAAAXAAMJmxJuFgCTAAAYAAIJGQL3TwBiAAABLgAFFAUJGgAEALEfAA==.Cryblood:BAABLgAECn8oAAIZAAkJVBLjHwDHAQAZAAkJVBLjHwDHAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIaAAkJGxtICABqAgAaAAkJGxtICABqAgAAAA==.',
Cy='Cynos:BAAALgAECgMJAwAAAA==.Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJEgAAAA==.Dalynn:BAABLgAECn8wAAIVAAgJng73gABtAQAVAAgJng73gABtAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Di='Dirtyd:BAAALgAECgYJEwAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAIOAAgJfB+TCQCBAgAOAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMbAAgJ/BSSHgBiAQAbAAgJ/BSSHgBiAQAcAAEJngMcngEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgMJAwAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8yAAIUAAkJew8tTgCbAQAUAAkJew8tTgCbAQAAAA==.Dryearlylth:BAAALgAECgMJAwAAAA==.',
Du='Dunkie:BAABLgAECn8VAAIIAAkJsgMCfgDmAAAIAAkJsgMCfgDmAAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJBAAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH8nAAIZAAkJrCCgAAAOAwAZAAkJrCCgAAAOAwAAAA==.Ellaryas:BAACLgAFFH8FAAMdAAMJewzOTQBgAAAdAAIJGgTOTQBgAAAIAAIJgwLKeQBLAAAuAAQKfx4AAwgACAneF2MjADoCAAgACAneF2MjADoCAB0ABAmNDSpxAJcAAAAA.',
Em='Em:BAACLgAFFH8RAAIeAAUJfxPkHwBUAQAeAAUJfxPkHwBUAQAuAAQKfxcABB4ACQltHEMPAEkCAB4ACQltHEMPAEkCABkABAlQEVlGAMwAABIAAQk1DSaCAC8AAAAA.Emaeel:BAAALgADCggJCAABLgAECgkJHwAXAHwSAA==.',
Er='Eraline:BAABLgAECn9GAAIXAAkJrBlIEAChAgAXAAkJrBlIEAChAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8eAAIcAAcJwCK6SgDiAQAcAAcJwCK6SgDiAQAAAA==.',
Fi='Fizzlemonk:BAAALgAECgkJDAABLgAFFAQJDAAVAEARAQ==.Fizzlepriest:BAAALgAECggJEQABLgAFFAQJDAAVAEARAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Fresco:BAAALgAECgEJAQAAAA==.Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8yAAIYAAkJERhqAwB4AgAYAAkJERhqAwB4AgAuAAQKfyQAAhgACQnCI68EAPkCABgACQnCI68EAPkCAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAIUAAYJNwGlFQE0AAAUAAYJNwGlFQE0AAAAAA==.',
Gh='Ghost:BAABLgAECn8fAAIfAAgJGRhSAADJAQAfAAgJGRhSAADJAQAAAA==.',
Gi='Gilden:BAABLgAECn8dAAMIAAkJ0wiAZAAuAQAIAAkJ0wiAZAAuAQAdAAMJYgOZiwBZAAAAAA==.',
Gn='Gnot:BAAALgAECgkJDAAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMFAAgJVBq5HQBQAgAFAAgJVBq5HQBQAgAEAAUJXBONPQAaAQAAAA==.',
Gy='Gyoza:BAABLgAECn8hAAMIAAkJpBpKEgC7AgAIAAkJpBpKEgC7AgAdAAUJHhlMQwAmAQAAAA==.',
['Gò']='Gòddess:BAABLgAECn8iAAIJAAgJqRcmFQDlAQAJAAgJqRcmFQDlAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMTAAkJfBOcPwDjAQATAAkJfBOcPwDjAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8WAAIFAAYJmQwTZQAFAQAFAAYJmQwTZQAFAQAAAA==.',
Im='Imperfect:BAAALgAECgEJAQAAAA==.',
In='Inafoxx:BAAALgAECgQJBAAAAA==.Inazuma:BAABLgAECn8/AAQLAAgJJxkJCgBDAgALAAgJJxkJCgBDAgAMAAQJkA9MFADIAAANAAQJhAo/cACLAAAAAA==.Inazumaah:BAAALgAECgEJAQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAABLgAECn8VAAQFAAkJFxGuUwBBAQAFAAcJcA6uUwBBAQAaAAgJXgkQFgASAQAgAAEJ3xLCTwA5AAAAAA==.',
Is='Ishatani:BAABLgAECn8cAAQVAAkJDAzdkABQAQAVAAkJ2gvdkABQAQAhAAQJawn3NwB/AAAHAAEJoQEqoQAdAAAAAA==.Isilod:BAAALgAECgcJEAAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMJAAkJeSQ2AwBSAwAJAAkJySM2AwBSAwAiAAkJ3yASAwC4AgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jh='Jhovathicnas:BAAALgAECgEJAQAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8fAAMgAAgJ+RJQEwCJAQAgAAcJXhVQEwCJAQAaAAcJyQbzQACjAAABLgAFFAEJAQAjAAAAAA==.Juuzau:BAABLgAECn8UAAIIAAcJIgmFcwACAQAIAAcJIgmFcwACAQAAAA==.',
['Jå']='Jåmes:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8RAAIeAAQJOBB1KAAIAQAeAAQJOBB1KAAIAQAuAAQKfzQAAh4ACAljFE8bAPQBAB4ACAljFE8bAPQBAAAA.Kaners:BAABLgAFFH8OAAIWAAQJ4h8uEwBzAQAWAAQJ4h8uEwBzAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIVAAcJDyEaQgAAAgAVAAcJDyEaQgAAAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAVAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJIQAFAG0hAA==.',
Ke='Kealey:BAABLgAECn8gAAIVAAcJ9gyIqwAmAQAVAAcJ9gyIqwAmAQAAAA==.Keine:BAAALgAECgcJCQAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhXpIgDcAQAGAAkJkxLpIgDcAQAPAAUJFRLwOADhAAAAAA==.',
Kh='Khaless:BAABLgAECn8dAAIOAAkJlBCcHABRAQAOAAkJlBCcHABRAQAAAA==.',
Ki='Kiamors:BAABLgAECn83AAMdAAkJsALCXADOAAAdAAkJsALCXADOAAAIAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJIQAIAKQaAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Kolaid:BAAALgAECgEJAQAAAA==.Koronus:BAAALgADCgUJCgAAAA==.Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCI1BQAOAwAGAAkJWCI1BQAOAwAPAAIJUQo0gwAnAAAAAA==.Kreleing:BAAALgAECgQJBQAAAA==.',
Ky='Kyndris:BAAALgAECgMJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAABLgAECn8WAAITAAgJxhOBTAC8AQATAAgJxhOBTAC8AQAAAA==.',
Ld='Ldx:BAAALgAECgEJAQAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAACLgAFFH8GAAIUAAIJLRlLdgCXAAAUAAIJLRlLdgCXAAAuAAQKfyIAAxQACQnyG3UcAGkCABQACQnyG3UcAGkCAAkABQmOBb1MAIQAAAAA.',
Li='Liandra:BAABLgAECn8WAAMSAAcJJgeYTwD6AAASAAcJJgeYTwD6AAAZAAUJUgagYgCQAAAAAA==.Lightfighter:BAABLgAECn8aAAMVAAgJJw1lkgBOAQAVAAgJPwxlkgBOAQAhAAQJlwreOAB7AAABLgAECgkJIAAKAAsHAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJIAAKAAsHAA==.Lilkiwi:BAABLgAECn8cAAIKAAkJpgsyjQBdAQAKAAkJpgsyjQBdAQAAAA==.',
Lo='Loozer:BAAALgAFFAIJBAAAAA==.Louhfu:BAABLgAECn8YAAIVAAcJdBW7iABfAQAVAAcJdBW7iABfAQAAAA==.',
Lu='Lunchbox:BAABLgAECn81AAIDAAgJCQz8IACUAQADAAgJCQz8IACUAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB+1BwCiAgADAAkJwx61BwCiAgATAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAIKAAQJIg9qZQAYAQAKAAQJIg9qZQAYAQAuAAQKfzgAAgoACQkDGy80AEgCAAoACQkDGy80AEgCAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAABLgAFFH8FAAIVAAQJ1AshUQANAQAVAAQJ1AshUQANAQABLgAFFAgJGwAKAEUTAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8HAAIEAAQJUgkLKwDiAAAEAAQJUgkLKwDiAAAuAAQKfx8AAgQACQmmEdoeANEBAAQACQmmEdoeANEBAAAA.',
Me='Meatfoot:BAAALgADCgcJCAAAAA==.Medie:BAABLgAECn9BAAMSAAkJnSH5BgDdAgASAAkJnSH5BgDdAgAZAAUJsw1PVQC+AAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8uAAMVAAkJOB2UHQCUAgAVAAkJOB2UHQCUAgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAcJIgAVACcmAA==.Najinsky:BAACLgAFFH8iAAIVAAcJJya1DAAUAgAVAAcJJya1DAAUAgAuAAQKfzIAAhUACQlFJagDAJYDABUACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Nefeli:BAAALgAECgIJAgAAAA==.Neikko:BAAALgAECgUJCgAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgQJBQABLgAECggJHwAfABkYAA==.Nellir:BAABLgAECn86AAMRAAkJWxWNCADfAQARAAkJWxWNCADfAQAkAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Ninguem:BAAALgAFFAQJAgAAAA==.Nitefall:BAAALgAECgUJBQAAAA==.',
No='Nobudy:BAAALgADCgUJBQAAAA==.Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8dAAIFAAkJ6xZkJwAVAgAFAAkJ6xZkJwAVAgAAAA==.Nostariel:BAAALgADCgYJBgAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECggJEgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJHwAfABkYAA==.',
Pu='Pulaski:BAAALgAECgUJBwAAAA==.Punchite:BAABLgAECn8dAAIQAAgJWh4QAQDLAQAQAAgJWh4QAQDLAQABLgAECgkJOgAlACImAA==.',
['Pè']='Pètitemort:BAAALgADCgYJEQAAAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAhAIAgAA==.Ravenkalyth:BAAALgAECgEJAwAAAA==.Raymane:BAAALgAECggJEwAAAA==.',
Re='Redemption:BAAALgADCgEJAQAAAA==.Reggie:BAAALgAECgQJBAABLgAFFAgJGwAKAEUTAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAABLgAECn8UAAIQAAcJUw4AOgAZAQAQAAcJUw4AOgAZAQAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8UAAMHAAYJcBENEwCXAQAHAAYJcBENEwCXAQAVAAEJqwG7TAAkAAAuAAQKf04AAwcACQnDGwUJAPoCAAcACQnDGwUJAPoCABUABgnFCrVBAWoAAAAA.',
Rh='Rhau:BAABLgAECn8YAAImAAYJvR9ZCQAqAgAmAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAHAOocAA==.',
Ro='Rombo:BAABLgAECn8XAAIgAAYJgRttFAB7AQAgAAYJgRttFAB7AQAAAA==.Rosastrasza:BAAALgAECgIJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAABLgAECn8aAAITAAYJbAnJCwD9AAATAAYJbAnJCwD9AAAAAA==.Ryokamatsu:BAAALgAECgEJAQABLgAFFAMJCAAIALQlAA==.Ryukie:BAAALgAECggJDAAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIVAAMJdR7fYgDpAAAVAAMJdR7fYgDpAAAuAAQKfx8AAhUACQm5IC8bAMYCABUACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Sallyacorn:BAAALgAECgEJAgAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAECgUJBwAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAECgYJDQAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAQJDAAVAEARAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgYJCQABLgAECgcJBwAjAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAILAAkJuR8WAwAhAwALAAkJuR8WAwAhAwAAAA==.Sinistra:BAABLgAECn8cAAIkAAkJzhTVPgDhAQAkAAkJzhTVPgDhAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soelene:BAAALgAECgEJAQAAAA==.Soldjin:BAABLgAECn8XAAMgAAcJWxtVEACyAQAgAAcJWxtVEACyAQAaAAUJ+wKHaQBCAAABLgAFFAQJEAAhAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9kAAIVAAkJ1iNKBQBLAwAVAAkJ1iNKBQBLAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgQJBAAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIcAAYJVRuNhAB5AQAcAAYJVRuNhAB5AQABLgAECgcJGgATAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Stewpedassol:BAAALgAECgEJAgAAAA==.Stormtusk:BAAALgAECgUJCAABLgAECggJHwAfABkYAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJqBWcTAAUAQAGAAYJsxScTAAUAQAOAAUJKRXbNQChAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Tootsniffa:BAAALgAECgEJAQAAAA==.Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8qAAIdAAkJph9jAQDpAQAdAAkJph9jAQDpAQAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Trashypotato:BAAALgAECgUJBQAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Uk='Ukagon:BAAALgADCgcJBwABLgAECgkJJwAFANoPAA==.',
Un='Unmei:BAABLgAECn84AAIdAAkJ8AxSMgB0AQAdAAkJ8AxSMgB0AQAAAA==.',
Va='Valcoree:BAAALgAECgQJBAABLgAECggJKwAZAHUSAA==.Valkrynd:BAAALgAECgEJAQAAAA==.Valynor:BAAALgAECgEJAQAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAITAAgJByIrCQABAwATAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIHAAkJ6hx3EACUAgAHAAkJ6hx3EACUAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAACLgAFFH8GAAIXAAQJpgtuNgDPAAAXAAQJpgtuNgDPAAAuAAQKfxQAAhcABwndFM8hAKUBABcABwndFM8hAKUBAAAA.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAaABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDQAjAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJDAAWAPgZAA==.',
Xe='Xephi:BAABLgAECn8YAAQmAAgJKA3JFgDuAAAmAAgJKA3JFgDuAAARAAMJiAbPMwBTAAAkAAEJhAdmUAEsAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIlAAkJIiYwAABhAwAlAAkJIiYwAABhAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJEwAAAA==.Zeldoris:BAABLgAECn9FAAIhAAkJgCA7BADAAgAhAAkJgCA7BADAAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJHwAfABkYAA==.',
Zi='Zillika:BAABLgAFFH8HAAIVAAMJFhfWIACeAAAVAAMJFhfWIACeAAAAAA==.',
Zu='Zuk:BAAALgADCgYJBgAAAA==.Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJDAABLgAECgkJHwAXAHwSAA==.',
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
