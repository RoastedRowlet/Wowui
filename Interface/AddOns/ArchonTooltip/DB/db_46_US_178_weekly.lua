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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Warrior-Fury','Rogue-Assassination','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Paladin-Retribution','Rogue-Subtlety','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','Shaman-Elemental','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Warlock-Destruction',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-07-19',data={Ac='Aceieus:BAAALgAECgEJAQAAAA==.',
Ad='Adiaera:BAAALgAECgEJAQAAAA==.',
Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8uAAIBAAkJQCH3AADXAgABAAkJQCH3AADXAgAAAA==.',
Ai='Airrows:BAACLgAFFH8GAAICAAMJahZ+GAD0AAACAAMJahZ+GAD0AAAuAAQKfzsAAwIACQl3JCEBACoDAAIACQl3JCEBACoDAAMABAkpGAA/AM4AAAAA.',
Ak='Akon:BAAALgADCgkJEgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDgAAAA==.Alurea:BAABLgAECn8yAAMEAAkJog5aOwAkAQAEAAcJbw1aOwAkAQAFAAgJeguCYgANAQAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Animorph:BAAALgAECgMJBAABLgAECggJHwAHABkYAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anthredis:BAABLgAFFH8NAAIIAAcJogezFQBRAQAIAAcJogezFQBRAQABLgAFFAkJMQAJAPsjAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIKAAkJbxm9FwBLAgAKAAkJbxm9FwBLAgABLgAECgkJIQALAKQaAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIKAAcJLyJ1GABPAgAKAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIMAAkJFSVgAgBBAwAMAAkJFSVgAgBBAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAINAAkJPRD2WwDKAQANAAkJPRD2WwDKAQAAAA==.Astragos:BAACLgAFFH8PAAIOAAQJqhlECgDfAAAOAAQJqhlECgDfAAAuAAQKfyUABA4ACAmFHG0JAFECAA4ABwlzHW0JAFECAA8ABwnAG5sIAKUBABAABwnJEjg4ABUBAAAA.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn80AAMRAAkJBiSoAgAYAwARAAkJBiSoAgAYAwASAAIJOxIBdgA2AAAAAA==.',
Be='Bearricade:BAAALgAECgUJDgABLgAECgkJIQALAKQaAA==.Beastius:BAAALgAECgIJBgAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.Belladari:BAAALgAECgEJAQAAAA==.',
Bi='Billamong:BAABLgAECn84AAITAAkJNxtpDwBUAgATAAkJNxtpDwBUAgAAAA==.Biren:BAAALgAECgYJCwAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgcJCAAAAA==.Blitzer:BAABLgAECn8oAAIUAAgJHw+3DACQAQAUAAgJHw+3DACQAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJCwAAAA==.Boney:BAAALgAECgYJDQAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAINAAkJCxsHLABpAgANAAkJCxsHLABpAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8KAAIVAAQJtxJ4CQDPAAAVAAQJtxJ4CQDPAAABLgAFFAgJGwANABsTAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAFFAEJAgAAAA==.Catelaya:BAABLgAECn84AAIJAAkJYyBuGACUAgAJAAkJYyBuGACUAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAIIAAkJ5Q8NRgC1AQAIAAkJ5Q8NRgC1AQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAIWAAIJDiQWfQC8AAAWAAIJDiQWfQC8AAAuAAQKfxkAAhYACAl+GutDABgCABYACAl+GutDABgCAAAA.Chexk:BAACLgAFFH8TAAIXAAQJWiEuDAAqAQAXAAQJWiEuDAAqAQAuAAQKfzYAAhcACQkZIkUEAPkCABcACQkZIkUEAPkCAAAA.Chillfu:BAACLgAFFH8JAAITAAQJiBn6DQCzAAATAAQJiBn6DQCzAAAuAAQKfyEAAhMACQnzFqsVAAsCABMACQnzFqsVAAsCAAAA.Chillycowpie:BAAALgAECgEJAQAAAA==.Chixnu:BAAALgAECgkJEwAAAA==.',
Ci='Cillina:BAAALgAECgEJAgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAABLgAECn8eAAIMAAkJ0Ag+BgAsAQAMAAkJ0Ag+BgAsAQAAAA==.Counsel:BAAALgAFFAMJBAAAAA==.',
Cr='Cratos:BAAALgAECgEJAgAAAA==.Crush:BAABLgAFFH8LAAMYAAMJmxKUJQCIAAAYAAMJmxKUJQCIAAAZAAIJGQL3TwBiAAABLgAFFAcJHAAEAGceAA==.Cryblood:BAABLgAECn8pAAIaAAkJVBLjHwDHAQAaAAkJVBLjHwDHAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIbAAkJGxtICABqAgAbAAkJGxtICABqAgAAAA==.',
Cy='Cynos:BAAALgAECgMJAwAAAA==.Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJEgAAAA==.Dalynn:BAABLgAECn8wAAIWAAgJng73gABtAQAWAAgJng73gABtAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Di='Dirtyd:BAAALgAECgYJEwAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAIRAAgJfB+TCQCBAgARAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMcAAgJ/BSSHgBiAQAcAAgJ/BSSHgBiAQAdAAEJngMcngEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgQJBwAAAA==.',
Dr='Drakatoa:BAAALgAECgQJBAAAAA==.Drottningu:BAABLgAECn8yAAIIAAkJew8tTgCbAQAIAAkJew8tTgCbAQAAAA==.Dryearlylth:BAAALgAECgMJAwAAAA==.',
Du='Dunkie:BAABLgAECn8VAAILAAkJsgMCfgDmAAALAAkJsgMCfgDmAAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJBAAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH87AAMaAAkJRSKgAAAOAwAaAAkJRSKgAAAOAwAeAAEJkwMaKQBBAAAAAA==.Ellaryas:BAACLgAFFH8GAAMfAAMJewzOTQBgAAAfAAIJGgTOTQBgAAALAAIJ/wXKeQBLAAAuAAQKfx8AAwsACAneF2MjADoCAAsACAneF2MjADoCAB8ABAmNDSpxAJcAAAAA.',
Em='Em:BAACLgAFFH8RAAIeAAUJfxPkHwBUAQAeAAUJfxPkHwBUAQAuAAQKfxgABB4ACQnCHEMPAEkCAB4ACQnCHEMPAEkCABoABAlQEVlGAMwAABUAAQk1DSaCAC8AAAAA.Emaeel:BAAALgADCggJCAABLgAECgkJHwAYAHwSAA==.',
Er='Eraline:BAABLgAECn9HAAIYAAkJOBpIEAChAgAYAAkJOBpIEAChAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fc='Fcawf:BAAALgADCgMJAwAAAA==.',
Fe='Fearless:BAABLgAECn8fAAIdAAcJwCK6SgDiAQAdAAcJwCK6SgDiAQAAAA==.',
Fi='Fizzlemonk:BAAALgAECgkJDAABLgAFFAQJDQAWAEARAQ==.Fizzlepriest:BAAALgAECggJEQABLgAFFAQJDQAWAEARAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Fresco:BAAALgAECgEJAQAAAA==.Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH86AAIZAAkJoSBgAAAYAwAZAAkJoSBgAAAYAwAuAAQKfyQAAhkACQnCI68EAPkCABkACQnCI68EAPkCAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAIIAAYJNwGlFQE0AAAIAAYJNwGlFQE0AAAAAA==.',
Gh='Ghost:BAABLgAECn8fAAIHAAgJGRjWAADDAQAHAAgJGRjWAADDAQAAAA==.',
Gi='Gilden:BAABLgAECn8dAAMLAAkJ1giAZAAuAQALAAkJ1giAZAAuAQAfAAMJYgOZiwBZAAAAAA==.',
Gn='Gnot:BAAALgAECgkJDAAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMFAAgJVBq5HQBQAgAFAAgJVBq5HQBQAgAEAAUJXBONPQAaAQAAAA==.',
Gy='Gyoza:BAABLgAECn8hAAMLAAkJpBpKEgC7AgALAAkJpBpKEgC7AgAfAAUJHhlMQwAmAQAAAA==.',
['Gò']='Gòddess:BAABLgAECn8iAAIMAAgJqRcmFQDlAQAMAAgJqRcmFQDlAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgAECgUJBgAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMJAAkJfBOcPwDjAQAJAAkJfBOcPwDjAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8ZAAIFAAYJSw4TZQAFAQAFAAYJSw4TZQAFAQAAAA==.',
Im='Imperfect:BAAALgAECgEJAQAAAA==.',
In='Inafoxx:BAAALgAECgQJBAAAAA==.Inazuma:BAABLgAECn8/AAQOAAgJJxkJCgBDAgAOAAgJJxkJCgBDAgAPAAQJkA9MFADIAAAQAAQJhAo/cACLAAAAAA==.Inazumaah:BAAALgAECgEJAQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAABLgAECn8VAAQFAAkJFxGuUwBBAQAFAAcJcA6uUwBBAQAbAAgJXgkQFgASAQAgAAEJ3xLCTwA5AAAAAA==.Invictum:BAAALgAECgYJBgAAAA==.',
Ir='Iridian:BAAALgADCgQJBAAAAA==.',
Is='Ishatani:BAABLgAECn8cAAQWAAkJDAzdkABQAQAWAAkJ2gvdkABQAQAhAAQJawn3NwB/AAAKAAEJoQEqoQAdAAAAAA==.Isilod:BAAALgAECgcJEwAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMMAAkJeSQ2AwBSAwAMAAkJySM2AwBSAwAiAAkJ3yASAwC4AgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jh='Jhovathicnas:BAAALgAECgEJAQAAAA==.',
Ji='Jig:BAAALgADCgYJBgAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8fAAMgAAgJ+RJQEwCJAQAgAAcJXhVQEwCJAQAbAAcJyQbzQACjAAABLgAFFAYJJgAZAEgDAA==.Juuzau:BAABLgAECn8cAAILAAkJewlpDgAJAQALAAkJewlpDgAJAQAAAA==.',
['Jå']='Jåmes:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8RAAIeAAQJOBB1KAAIAQAeAAQJOBB1KAAIAQAuAAQKfzQAAh4ACAljFE8bAPQBAB4ACAljFE8bAPQBAAAA.Kaners:BAABLgAFFH8OAAIXAAQJ4h8uEwBzAQAXAAQJ4h8uEwBzAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIWAAcJDyEaQgAAAgAWAAcJDyEaQgAAAgAAAA==.Kathoran:BAAALgADCgcJBwAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAWAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJIQAFAHghAA==.',
Ke='Kealey:BAABLgAECn8gAAIWAAcJ9gyIqwAmAQAWAAcJ9gyIqwAmAQAAAA==.Keine:BAAALgAECgcJCQAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhXpIgDcAQAGAAkJkxLpIgDcAQASAAUJFRLwOADhAAAAAA==.',
Kh='Khaless:BAABLgAECn8dAAIRAAkJkRCcHABRAQARAAkJkRCcHABRAQAAAA==.',
Ki='Kiamors:BAABLgAECn83AAMfAAkJsALCXADOAAAfAAkJsALCXADOAAALAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJIQALAKQaAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Kolaid:BAAALgAECgEJAQAAAA==.Koronus:BAAALgADCgUJCgAAAA==.Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCI1BQAOAwAGAAkJWCI1BQAOAwASAAIJUQo0gwAnAAAAAA==.Kreleing:BAAALgAECgQJBQAAAA==.',
Ky='Kyndris:BAAALgAECgMJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAABLgAECn8aAAIJAAgJwhWBTAC8AQAJAAgJwhWBTAC8AQAAAA==.',
Ld='Ldx:BAAALgAECgEJAQAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAACLgAFFH8JAAIIAAMJyBBLdgCXAAAIAAMJyBBLdgCXAAAuAAQKfyIAAwgACQnyG3UcAGkCAAgACQnyG3UcAGkCAAwABQmOBb1MAIQAAAAA.',
Li='Liandra:BAABLgAECn8WAAMVAAcJJgeYTwD6AAAVAAcJJgeYTwD6AAAaAAUJUgagYgCQAAAAAA==.Lightfighter:BAABLgAECn8aAAMWAAgJJw1lkgBOAQAWAAgJPwxlkgBOAQAhAAQJlwreOAB7AAABLgAECgkJIAANAAsHAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJIAANAAsHAA==.Lilkiwi:BAABLgAECn8cAAINAAkJpwsyjQBdAQANAAkJpwsyjQBdAQAAAA==.',
Lo='Loozer:BAAALgAFFAIJBAAAAA==.Louhfu:BAABLgAECn8YAAIWAAcJdBW7iABfAQAWAAcJdBW7iABfAQAAAA==.',
Lu='Lunchbox:BAABLgAECn84AAIDAAkJwwz8IACUAQADAAkJwwz8IACUAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB+1BwCiAgADAAkJwx61BwCiAgAJAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAINAAQJIg9qZQAYAQANAAQJIg9qZQAYAQAuAAQKfzgAAg0ACQkDGy80AEgCAA0ACQkDGy80AEgCAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAABLgAFFH8MAAIWAAQJxBEjKgDPAAAWAAQJxBEjKgDPAAABLgAFFAgJGwANABsTAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8HAAIEAAQJUgkLKwDiAAAEAAQJUgkLKwDiAAAuAAQKfx8AAgQACQmmEdoeANEBAAQACQmmEdoeANEBAAAA.',
Me='Meadow:BAAALgAECgEJAQAAAA==.Meatfoot:BAAALgADCgcJCAAAAA==.Medie:BAABLgAECn9BAAMVAAkJnSH5BgDdAgAVAAkJnSH5BgDdAgAaAAUJsw1PVQC+AAAAAA==.Melody:BAAALgAECgEJAQAAAA==.',
Mi='Michelle:BAABLgAECn8uAAMWAAkJOB2UHQCUAgAWAAkJOB2UHQCUAgAKAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.Morello:BAAALgAECgEJAgABLgAECggJHwAHABkYAA==.',
My='Mystikan:BAAALgADCgQJBAABLgAECgUJBgAjAAAAAA==.',
['Mä']='Mäenard:BAAALgADCgUJBQAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAgJIwAWAH8lAA==.Najinsky:BAACLgAFFH8jAAIWAAgJfyW1DAAUAgAWAAgJfyW1DAAUAgAuAAQKfzIAAhYACQlFJagDAJYDABYACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Nefeli:BAAALgAECgIJAgAAAA==.Neikko:BAAALgAECgUJDQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgQJBQABLgAECggJHwAHABkYAA==.Nelior:BAAALgAECgEJAQAAAA==.Nellir:BAABLgAECn86AAMUAAkJWxWNCADfAQAUAAkJWxWNCADfAQAkAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Ninguem:BAAALgAFFAQJAwAAAA==.Nitefall:BAAALgAECgUJBQAAAA==.',
No='Nobudy:BAAALgAECgEJAQAAAA==.Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8dAAIFAAkJ7xZkJwAVAgAFAAkJ7xZkJwAVAgAAAA==.Nostariel:BAAALgADCgYJBgAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.Poughkeepsie:BAAALgAECgcJBwABLgAFFAMJBQAXAOQZAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJHwAHABkYAA==.',
Pu='Pulaski:BAAALgAECgUJBwAAAA==.Punchite:BAABLgAECn8dAAITAAgJWh5pAgDGAQATAAgJWh5pAgDGAQABLgAECgkJOgAlACImAA==.',
['Pè']='Pètitemort:BAAALgADCgYJEQAAAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAhAIAgAA==.Ravenkalyth:BAAALgAECgEJAwAAAA==.Raymane:BAAALgAECggJEwAAAA==.',
Re='Redemption:BAAALgADCgEJAQAAAA==.Reggie:BAAALgAECgQJBAABLgAFFAgJGwANABsTAA==.Reginato:BAAALgADCgYJBgAAAA==.Renamer:BAAALgAECgIJAgAAAA==.Rengokuu:BAABLgAECn8UAAITAAcJUw4AOgAZAQATAAcJUw4AOgAZAQAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8VAAMKAAYJcBENEwCXAQAKAAYJcBENEwCXAQAWAAEJqwERewAjAAAuAAQKf1MAAwoACQnDGwUJAPoCAAoACQnDGwUJAPoCABYABgnFCrVBAWoAAAAA.',
Rh='Rhau:BAABLgAECn8YAAImAAYJvR9ZCQAqAgAmAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAKAOocAA==.',
Ri='Ripplypickly:BAABLgAECn8XAAINAAgJ8Q1uGQDfAAANAAgJ8Q1uGQDfAAAAAA==.Rivanon:BAAALgADCgcJBwAAAA==.',
Ro='Rombo:BAABLgAECn8XAAIgAAYJgRttFAB7AQAgAAYJgRttFAB7AQAAAA==.Rosastrasza:BAAALgAECgIJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAABLgAECn8fAAIJAAYJ8Qo3GQDqAAAJAAYJ8Qo3GQDqAAAAAA==.Ryokamatsu:BAAALgAECgEJAQABLgAFFAMJCAALALQlAA==.Ryukie:BAAALgAECggJDAAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIWAAMJdR7fYgDpAAAWAAMJdR7fYgDpAAAuAAQKfx8AAhYACQm5IC8bAMYCABYACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Sallyacorn:BAAALgAECgEJAgAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAFFAEJAQAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAFFAMJAwAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAQJDQAWAEARAQ==.Shambulance:BAAALgAECgcJBwABLgAFFAQJDQAWAEARAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgYJCQABLgAECgcJBwAjAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIOAAkJuR8WAwAhAwAOAAkJuR8WAwAhAwAAAA==.Sinistra:BAABLgAECn8cAAIkAAkJzhTVPgDhAQAkAAkJzhTVPgDhAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAgAAAA==.',
So='Soelene:BAAALgAECgEJAQAAAA==.Soldjin:BAABLgAECn8XAAMgAAcJZBtVEACyAQAgAAcJZBtVEACyAQAbAAUJ+wKHaQBCAAABLgAFFAQJEAAhAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9kAAIWAAkJ1iNKBQBLAwAWAAkJ1iNKBQBLAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgQJBAAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIdAAYJVRuNhAB5AQAdAAYJVRuNhAB5AQABLgAECgcJGgAJAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Stewpedassol:BAAALgAECgEJAgAAAA==.Stormtusk:BAAALgAECgYJCQABLgAECggJHwAHABkYAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Ta='Talyea:BAAALgAECgEJAQAAAA==.',
Th='Thorfine:BAABLgAECn8jAAMGAAgJPBacTAAUAQAGAAYJghWcTAAUAQARAAUJKRXbNQChAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Tootsniffa:BAAALgAECgEJAQAAAA==.Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8qAAIfAAkJqB8zAwDcAQAfAAkJqB8zAwDcAQAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Trashypotato:BAAALgAECgUJBQAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Uk='Ukagon:BAAALgADCgcJBwABLgAECgkJMQAFANoPAA==.',
Un='Unmei:BAABLgAECn84AAIfAAkJ8AxSMgB0AQAfAAkJ8AxSMgB0AQAAAA==.',
Va='Valcoree:BAAALgAECgQJBAABLgAECggJKwAaAHUSAA==.Valkrynd:BAAALgAECgEJAQAAAA==.Valynor:BAAALgAECgEJAgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAIJAAgJByIrCQABAwAJAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIKAAkJ6hx3EACUAgAKAAkJ6hx3EACUAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAACLgAFFH8GAAIYAAQJpgtuNgDPAAAYAAQJpgtuNgDPAAAuAAQKfxQAAhgABwndFM8hAKUBABgABwndFM8hAKUBAAAA.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAbABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDgAjAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJDAAXAPgZAA==.',
Xe='Xephi:BAABLgAECn8YAAQmAAgJKA3JFgDuAAAmAAgJKA3JFgDuAAAUAAMJiAbPMwBTAAAkAAEJhAdmUAEsAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIlAAkJIiYwAABhAwAlAAkJIiYwAABhAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJEwAAAA==.Zeldoris:BAABLgAECn9FAAIhAAkJgCA7BADAAgAhAAkJgCA7BADAAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJHwAHABkYAA==.',
Zi='Zillika:BAABLgAFFH8HAAIWAAMJFhdaYADuAAAWAAMJFhdaYADuAAAAAA==.',
Zu='Zuk:BAAALgADCgYJBgAAAA==.Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJDAABLgAECgkJHwAYAHwSAA==.',
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
