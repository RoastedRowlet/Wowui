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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Rogue-Subtlety','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Rogue-Assassination','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Unknown-Unknown',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Aceieus:BAAALgAECgEJAQAAAA==.',
Ad='Adiaera:BAAALgAECgEJAQAAAA==.',
Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8uAAIBAAkJQCH3AADXAgABAAkJQCH3AADXAgAAAA==.',
Ai='Airrows:BAACLgAFFH8EAAICAAMJahaQGAD0AAACAAMJahaQGAD0AAAuAAQKfzsAAwIACQl3JCEBACoDAAIACQl3JCEBACoDAAMABAkpGP8+AM4AAAAA.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDQAAAA==.Alurea:BAABLgAECn8xAAMEAAkJnA1WOwAkAQAEAAcJVg1WOwAkAQAFAAgJgAmGYgANAQAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxnAFwBLAgAHAAkJbxnAFwBLAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIIAAkJFSViAgBBAwAIAAkJFSViAgBBAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAIJAAkJPRD3WwDKAQAJAAkJPRD3WwDKAQAAAA==.Astragos:BAABLgAECn8lAAQKAAgJhRxtCQBRAgAKAAcJcx1tCQBRAgALAAcJwBubCAClAQAMAAcJyRI4OAAVAQAAAA==.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn8yAAMNAAkJBiSoAgAYAwANAAkJBiSoAgAYAwAOAAIJOxIDdgA2AAAAAA==.',
Be='Beastius:BAAALgAECgIJBQAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.Belladari:BAAALgAECgEJAQAAAA==.',
Bi='Billamong:BAABLgAECn82AAIPAAkJNRtpDwBUAgAPAAkJNRtpDwBUAgAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8oAAIQAAgJHw+3DACQAQAQAAgJHw+3DACQAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJCwAAAA==.Boney:BAAALgAECgYJCgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAIJAAkJCxsKLABpAgAJAAkJCxsKLABpAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8KAAIRAAQJtxJ4CQDPAAARAAQJtxJ4CQDPAAABLgAFFAgJGwAJAEUTAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAECgIJAwABLgAECgkJFgAHAI8XAA==.Catelaya:BAABLgAECn84AAISAAkJYyBwGACUAgASAAkJYyBwGACUAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAITAAkJ5Q8NRgC1AQATAAkJ5Q8NRgC1AQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAIUAAIJDiQffQC8AAAUAAIJDiQffQC8AAAuAAQKfxkAAhQACAl+GutDABgCABQACAl+GutDABgCAAAA.Chexk:BAACLgAFFH8JAAIVAAQJMBuWFgBYAQAVAAQJMBuWFgBYAQAuAAQKfzYAAhUACQkZIkUEAPkCABUACQkZIkUEAPkCAAAA.Chillfu:BAACLgAFFH8FAAIPAAQJ1hTRLgCMAAAPAAQJ1hTRLgCMAAAuAAQKfyEAAg8ACQnzFqsVAAsCAA8ACQnzFqsVAAsCAAAA.Chillycowpie:BAAALgAECgEJAQAAAA==.Chixnu:BAAALgAECggJEgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAABLgAECn8cAAIIAAgJ6gg8AQDwAAAIAAgJ6gg8AQDwAAAAAA==.Counsel:BAAALgAFFAMJBAAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAABLgAFFH8IAAMWAAMJgxFRTwBpAAAWAAIJhxBRTwBpAAAXAAIJGQL/TwBiAAABLgAFFAUJGgAEALEfAA==.Cryblood:BAABLgAECn8nAAIYAAkJVBLiHwDHAQAYAAkJVBLiHwDHAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIZAAkJGxtICABqAgAZAAkJGxtICABqAgAAAA==.',
Cy='Cynos:BAAALgAECgMJAwAAAA==.Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJEgAAAA==.Dalynn:BAABLgAECn8wAAIUAAgJng75gABtAQAUAAgJng75gABtAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAINAAgJfB+TCQCBAgANAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMaAAgJ/BSRHgBiAQAaAAgJ/BSRHgBiAQAbAAEJngMVngEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgMJAwAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8yAAITAAkJew8yTgCbAQATAAkJew8yTgCbAQAAAA==.Dryearlylth:BAAALgAECgMJAwAAAA==.',
Du='Dunkie:BAABLgAECn8UAAIcAAgJVQP8fQDmAAAcAAgJVQP8fQDmAAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJBAAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH8fAAIYAAkJphygAAAOAwAYAAkJphygAAAOAwAAAA==.Ellaryas:BAACLgAFFH8FAAMdAAMJewzQTQBgAAAdAAIJGgTQTQBgAAAcAAIJgwLFeQBLAAAuAAQKfx4AAxwACAneF2EjADoCABwACAneF2EjADoCAB0ABAmNDSZxAJcAAAAA.',
Em='Em:BAACLgAFFH8RAAIeAAUJfxPvHwBUAQAeAAUJfxPvHwBUAQAuAAQKfxcABB4ACQltHEMPAEkCAB4ACQltHEMPAEkCABgABAlQEVlGAMwAABEAAQk1DSaCAC8AAAAA.Emaeel:BAAALgADCggJCAABLgAECgkJHwAWAHwSAA==.',
Er='Eraline:BAABLgAECn9GAAIWAAkJrBlLEAChAgAWAAkJrBlLEAChAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8eAAIbAAcJwCK1SgDiAQAbAAcJwCK1SgDiAQAAAA==.',
Fi='Fizzlemonk:BAAALgAECgkJCQABLgAFFAQJDAAUAEARAQ==.Fizzlepriest:BAAALgAECggJEQABLgAFFAQJDAAUAEARAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Fresco:BAAALgAECgEJAQAAAA==.Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8tAAIXAAgJmhltAwB4AgAXAAgJmhltAwB4AgAuAAQKfyQAAhcACQnCI68EAPkCABcACQnCI68EAPkCAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAITAAYJNwGhFQE0AAATAAYJNwGhFQE0AAAAAA==.',
Gh='Ghost:BAABLgAECn8dAAIfAAgJXxa1BwDjAQAfAAgJXxa1BwDjAQAAAA==.',
Gi='Gilden:BAABLgAECn8cAAMcAAgJ8wd7ZAAuAQAcAAgJ8wd7ZAAuAQAdAAMJYgOaiwBZAAAAAA==.',
Gn='Gnot:BAAALgAECggJCQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMFAAgJVBq5HQBQAgAFAAgJVBq5HQBQAgAEAAUJXBOIPQAaAQAAAA==.',
Gy='Gyoza:BAABLgAECn8hAAMcAAkJpBpLEgC7AgAcAAkJpBpLEgC7AgAdAAUJHhlKQwAmAQABLgAECgkJKQAHAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8hAAIIAAgJqRcnFQDlAQAIAAgJqRcnFQDlAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMSAAkJfBOePwDjAQASAAkJfBOePwDjAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8WAAIFAAYJmQwWZQAFAQAFAAYJmQwWZQAFAQAAAA==.',
Im='Imperfect:BAAALgAECgEJAQAAAA==.',
In='Inafoxx:BAAALgAECgQJBAAAAA==.Inazuma:BAABLgAECn8/AAQKAAgJJxkJCgBDAgAKAAgJJxkJCgBDAgALAAQJkA9NFADIAAAMAAQJhAo9cACLAAAAAA==.Inazumaah:BAAALgAECgEJAQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAABLgAECn8VAAQFAAkJFxGyUwBBAQAFAAcJcA6yUwBBAQAZAAgJXgkQFgASAQAgAAEJ3xLDTwA5AAAAAA==.',
Is='Ishatani:BAABLgAECn8bAAQUAAgJrQzekABQAQAUAAgJdAzekABQAQAhAAQJawn1NwB/AAAHAAEJoQEuoQAdAAAAAA==.Isilod:BAAALgAECgcJDwAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMIAAkJeSQ2AwBSAwAIAAkJySM2AwBSAwAiAAkJ3yASAwC4AgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8fAAMgAAgJ+RJMEwCJAQAgAAcJXhVMEwCJAQAZAAcJyQbzQACjAAABLgAFFAQJFwAXAFEDAA==.Juuzau:BAABLgAECn8UAAIcAAcJIgl8cwACAQAcAAcJIgl8cwACAQAAAA==.',
['Jå']='Jåmes:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8RAAIeAAQJOBB5KAAIAQAeAAQJOBB5KAAIAQAuAAQKfzQAAh4ACAljFE4bAPQBAB4ACAljFE4bAPQBAAAA.Kaners:BAABLgAFFH8OAAIVAAQJ4h84EwBzAQAVAAQJ4h84EwBzAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIUAAcJDyEdQgAAAgAUAAcJDyEdQgAAAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAUAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJGwAFAHcfAA==.',
Ke='Kealey:BAABLgAECn8gAAIUAAcJ9gyJqwAmAQAUAAcJ9gyJqwAmAQAAAA==.Keine:BAAALgAECgcJCQAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhXoIgDcAQAGAAkJkxLoIgDcAQAOAAUJFRLsOADhAAAAAA==.',
Kh='Khaless:BAABLgAECn8cAAINAAgJYBGcHABRAQANAAgJYBGcHABRAQAAAA==.',
Ki='Kiamors:BAABLgAECn83AAMdAAkJsAK+XADOAAAdAAkJsAK+XADOAAAcAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJKQAHAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Kolaid:BAAALgAECgEJAQAAAA==.Koronus:BAAALgADCgUJBQAAAA==.Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCI0BQAOAwAGAAkJWCI0BQAOAwAOAAIJUQo0gwAnAAAAAA==.Kreleing:BAAALgAECgQJBQAAAA==.',
Ky='Kyndris:BAAALgAECgMJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAABLgAECn8WAAISAAgJxhOATAC8AQASAAgJxhOATAC8AQAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAACLgAFFH8GAAITAAIJLRlYdgCXAAATAAIJLRlYdgCXAAAuAAQKfyAAAxMACQnyG3ccAGkCABMACQnyG3ccAGkCAAgABQmOBbxMAIQAAAAA.',
Li='Liandra:BAABLgAECn8WAAMRAAcJJgeYTwD6AAARAAcJJgeYTwD6AAAYAAUJUgaWYgCQAAAAAA==.Lightfighter:BAABLgAECn8aAAMUAAgJJw1kkgBOAQAUAAgJPwxkkgBOAQAhAAQJlwrcOAB7AAABLgAECgkJIAAJAAsHAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJIAAJAAsHAA==.Lilkiwi:BAABLgAECn8bAAIJAAgJqAswjQBdAQAJAAgJqAswjQBdAQAAAA==.',
Lo='Loozer:BAAALgAFFAIJBAAAAA==.Louhfu:BAABLgAECn8YAAIUAAcJdBW+iABfAQAUAAcJdBW+iABfAQAAAA==.',
Lu='Lunchbox:BAABLgAECn81AAIDAAgJCQz8IACUAQADAAgJCQz8IACUAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB+2BwCiAgADAAkJwx62BwCiAgASAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAIJAAQJIg+HZQAYAQAJAAQJIg+HZQAYAQAuAAQKfzgAAgkACQkDGzI0AEgCAAkACQkDGzI0AEgCAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAABLgAFFH8FAAIUAAQJ1AswUQANAQAUAAQJ1AswUQANAQABLgAFFAgJGwAJAEUTAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8GAAIEAAQJUgkOKwDiAAAEAAQJUgkOKwDiAAAuAAQKfx8AAgQACQmmEdUeANEBAAQACQmmEdUeANEBAAAA.',
Me='Meatfoot:BAAALgADCgcJCAAAAA==.Medie:BAABLgAECn9BAAMRAAkJnSH5BgDdAgARAAkJnSH5BgDdAgAYAAUJsw1LVQC+AAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8uAAMUAAkJOB2THQCUAgAUAAkJOB2THQCUAgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAYJIQAUADcmAA==.Najinsky:BAACLgAFFH8hAAIUAAYJNybGDAAUAgAUAAYJNybGDAAUAgAuAAQKfzIAAhQACQlFJagDAJYDABQACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Nefeli:BAAALgAECgIJAgAAAA==.Neikko:BAAALgAECgUJBgAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgQJBQABLgAECggJHQAfAF8WAA==.Nellir:BAABLgAECn86AAMQAAkJWxWNCADfAQAQAAkJWxWNCADfAQAjAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Ninguem:BAAALgAFFAQJAgAAAA==.Nitefall:BAAALgAECgUJBQAAAA==.',
No='Nobudy:BAAALgADCgUJBQAAAA==.Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8cAAIFAAgJFBdmJwAVAgAFAAgJFBdmJwAVAgAAAA==.Nostariel:BAAALgADCgUJBQAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECggJEgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJHQAfAF8WAA==.',
Pu='Pulaski:BAAALgAECgUJBwAAAA==.Punchite:BAABLgAECn8dAAIPAAgJWh5sAADLAQAPAAgJWh5sAADLAQABLgAECgkJOgAkACImAA==.',
['Pè']='Pètitemort:BAAALgADCgYJCwAAAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAhAIAgAA==.Ravenkalyth:BAAALgAECgEJAgAAAA==.Raymane:BAAALgAECggJEAAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAgJGwAJAEUTAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAABLgAECn8UAAIPAAcJUw4AOgAZAQAPAAcJUw4AOgAZAQAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8UAAMHAAYJcBEWEwCXAQAHAAYJcBEWEwCXAQAUAAEJqwFNGAAnAAAuAAQKf04AAwcACQnDGwUJAPoCAAcACQnDGwUJAPoCABQABgnFCqtBAWoAAAAA.',
Rh='Rhau:BAABLgAECn8YAAIlAAYJvR9ZCQAqAgAlAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAHAOocAA==.',
Ro='Rombo:BAABLgAECn8XAAIgAAYJgRtrFAB7AQAgAAYJgRtrFAB7AQAAAA==.Rosastrasza:BAAALgAECgIJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAABLgAECn8UAAISAAUJKAiuCQBsAAASAAUJKAiuCQBsAAAAAA==.Ryokamatsu:BAAALgAECgEJAQABLgAFFAMJCAAcALQlAA==.Ryukie:BAAALgAECggJDAAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIUAAMJdR7pYgDpAAAUAAMJdR7pYgDpAAAuAAQKfx8AAhQACQm5IC8bAMYCABQACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Sallyacorn:BAAALgAECgEJAgAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAECgUJBwAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAECgYJDQAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAQJDAAUAEARAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgUJCAABLgAECgcJBwAmAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIKAAkJuR8WAwAhAwAKAAkJuR8WAwAhAwAAAA==.Sinistra:BAABLgAECn8cAAIjAAkJzhTTPgDhAQAjAAkJzhTTPgDhAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAABLgAECn8XAAMgAAcJWxtTEACyAQAgAAcJWxtTEACyAQAZAAUJ+wKFaQBCAAABLgAFFAQJEAAhAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9kAAIUAAkJ1iNJBQBLAwAUAAkJ1iNJBQBLAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgQJBAAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIbAAYJVRuNhAB5AQAbAAYJVRuNhAB5AQABLgAECgcJGgASAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Stewpedassol:BAAALgAECgEJAgAAAA==.Stormtusk:BAAALgAECgQJBAAAAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJqBWZTAAUAQAGAAYJsxSZTAAUAQANAAUJKRXZNQChAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Tootsniffa:BAAALgAECgEJAQAAAA==.Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8kAAIdAAgJxh4hEQBoAgAdAAgJxh4hEQBoAgAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Trashypotato:BAAALgAECgUJBQAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn84AAIdAAkJ8AxQMgB0AQAdAAkJ8AxQMgB0AQAAAA==.',
Va='Valcoree:BAAALgAECgQJBAABLgAECggJKwAYAHUSAA==.Valynor:BAAALgAECgEJAQAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAISAAgJByIrCQABAwASAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIHAAkJ6hx3EACUAgAHAAkJ6hx3EACUAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAACLgAFFH8GAAIWAAQJpgtrNgDPAAAWAAQJpgtrNgDPAAAuAAQKfxQAAhYABwndFM8hAKUBABYABwndFM8hAKUBAAAA.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAZABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDQAmAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJCwAVAPgZAA==.',
Xe='Xephi:BAABLgAECn8YAAQlAAgJKA3HFgDuAAAlAAgJKA3HFgDuAAAQAAMJiAbPMwBTAAAjAAEJhAdkUAEsAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIkAAkJIiYwAABhAwAkAAkJIiYwAABhAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJEwAAAA==.Zeldoris:BAABLgAECn9FAAIhAAkJgCA7BADAAgAhAAkJgCA7BADAAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJHQAfAF8WAA==.',
Zi='Zillika:BAABLgAFFH8HAAIUAAMJFhc7CQChAAAUAAMJFhc7CQChAAAAAA==.',
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
