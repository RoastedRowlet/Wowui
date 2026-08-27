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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Warrior-Fury','Rogue-Assassination','DemonHunter-Devourer','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Paladin-Retribution','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','Rogue-Subtlety','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Priest-Discipline','Shaman-Elemental','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Warlock-Destruction',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-08-25',data={Ac='Aceieus:BAAALgAECgEJAQAAAA==.',
Ad='Adiaera:BAAALgAECgEJAQAAAA==.',
Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8uAAIBAAkJQCH3AADXAgABAAkJQCH3AADXAgAAAA==.',
Ai='Airrows:BAACLgAFFH8GAAICAAMJahZ+GAD0AAACAAMJahZ+GAD0AAAuAAQKfzsAAwIACQl3JCEBACoDAAIACQl3JCEBACoDAAMABAkpGAA/AM4AAAAA.',
Ak='Akon:BAAALgAECgUJDAAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDgAAAA==.Alphaomega:BAAALgAECgEJAQAAAA==.Alurea:BAABLgAECn8yAAMEAAkJog5aOwAkAQAEAAcJbw1aOwAkAQAFAAgJeguCYgANAQAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anigavnimuc:BAAALgAECgcJBwAAAA==.Animorph:BAAALgAECgMJBAABLgAECggJHwAHABkYAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anthredis:BAABLgAFFH8VAAIIAAkJhAtHDQDnAQAIAAkJhAtHDQDnAQAAAA==.Anvi:BAAALgAECgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIJAAkJbxm9FwBLAgAJAAkJbxm9FwBLAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIJAAcJLyJ1GABPAgAJAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn9AAAIKAAkJFSVgAgBBAwAKAAkJFSVgAgBBAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAILAAkJPRD2WwDKAQALAAkJPRD2WwDKAQAAAA==.Astragos:BAACLgAFFH8QAAIMAAUJ2BWbCgAIAQAMAAUJ2BWbCgAIAQAuAAQKfyUABAwACAmFHG0JAFECAAwABwlzHW0JAFECAA0ABwnAG5sIAKUBAA4ABwnJEjg4ABUBAAAA.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn80AAMPAAkJBiSoAgAYAwAPAAkJBiSoAgAYAwAQAAIJOxIBdgA2AAAAAA==.',
Be='Bearricade:BAAALgAECgUJDwABLgAECgkJKQAJAG8ZAA==.Beastius:BAAALgAECgIJBwAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.Belladari:BAAALgAECgEJAQAAAA==.',
Bi='Billamong:BAABLgAECn84AAIRAAkJNxtpDwBUAgARAAkJNxtpDwBUAgAAAA==.Biren:BAABLgAECn8bAAISAAcJphL3FAA2AQASAAcJphL3FAA2AQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgcJCAAAAA==.Blitzer:BAABLgAECn8oAAITAAgJHw+3DACQAQATAAgJHw+3DACQAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJCwAAAA==.Boney:BAAALgAECgYJDQAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn88AAILAAkJCxsHLABpAgALAAkJCxsHLABpAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8KAAIUAAQJtxJ4CQDPAAAUAAQJtxJ4CQDPAAABLgAFFAkJHAALANUSAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Candeth:BAAALgAECgEJAgAAAA==.Cassilune:BAAALgAFFAEJAgAAAA==.Catelaya:BAABLgAECn84AAIVAAkJYyBuGACUAgAVAAkJYyBuGACUAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8jAAIIAAkJ5Q8NRgC1AQAIAAkJ5Q8NRgC1AQAAAA==.',
Ch='Chaness:BAACLgAFFH8HAAISAAIJDiQWfQC8AAASAAIJDiQWfQC8AAAuAAQKfxkAAhIACAl+GutDABgCABIACAl+GutDABgCAAAA.Chexk:BAACLgAFFH8UAAIWAAUJWiHKDgAeAQAWAAUJWiHKDgAeAQAuAAQKfzYAAhYACQkZIkUEAPkCABYACQkZIkUEAPkCAAAA.Chillfu:BAACLgAFFH8KAAIRAAQJiBkXEQCuAAARAAQJiBkXEQCuAAAuAAQKfyEAAhEACQnzFqsVAAsCABEACQnzFqsVAAsCAAAA.Chillycowpie:BAAALgAECgEJAQAAAA==.Chixnu:BAAALgAECgkJEwAAAA==.Chushing:BAAALgAECgYJBgAAAA==.',
Ci='Cillina:BAAALgAECgEJAgAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAABLgAECn8eAAIKAAkJ0Ai3CAAkAQAKAAkJ0Ai3CAAkAQAAAA==.Counsel:BAAALgAFFAMJBAAAAA==.',
Cr='Cratos:BAAALgAECgEJAgAAAA==.Crush:BAABLgAFFH8LAAMXAAMJmxJ7KQCHAAAXAAMJmxJ7KQCHAAAYAAIJGQL3TwBiAAABLgAFFAgJHQAEAIcbAA==.Cryblood:BAABLgAECn8pAAIZAAkJVBLjHwDHAQAZAAkJVBLjHwDHAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn8+AAMaAAkJGxtICABqAgAaAAkJGxtICABqAgAEAAIJBxoAFACYAAAAAA==.',
Cy='Cynos:BAAALgAECgMJAwAAAA==.Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Daelynn:BAAALgADCgkJEgAAAA==.Dalynn:BAABLgAECn8wAAISAAgJng73gABtAQASAAgJng73gABtAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Di='Dirtyd:BAAALgAECgYJEwAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAIPAAgJfB+TCQCBAgAPAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMbAAgJ/BSSHgBiAQAbAAgJ/BSSHgBiAQAcAAEJngMcngEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgcJCgAAAA==.',
Dr='Drakatoa:BAAALgAECgQJBAAAAA==.Drottningu:BAABLgAECn8yAAIIAAkJew8tTgCbAQAIAAkJew8tTgCbAQAAAA==.Dryearlylth:BAAALgAECgMJAwAAAA==.',
Du='Dunkie:BAABLgAECn8VAAIdAAkJsgMCfgDmAAAdAAkJsgMCfgDmAAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJBAAAAA==.',
Ef='Effohsix:BAAALgAECgEJAQABLgAECgkJbAAcAD0iAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAABLgAFFH89AAMZAAkJtiKgAAAOAwAZAAkJtiKgAAAOAwAeAAEJkwOqLgBBAAAAAA==.Ellaryas:BAACLgAFFH8GAAMfAAMJewzOTQBgAAAfAAIJGgTOTQBgAAAdAAIJ/wXKeQBLAAAuAAQKfyAAAx0ACAkJGGMjADoCAB0ACAkJGGMjADoCAB8ABAmNDSpxAJcAAAAA.',
Em='Em:BAACLgAFFH8RAAIeAAUJfxPkHwBUAQAeAAUJfxPkHwBUAQAuAAQKfxgABB4ACQnCHEMPAEkCAB4ACQnCHEMPAEkCABkABAlQEVlGAMwAABQAAQk1DSaCAC8AAAAA.Emaeel:BAAALgADCggJCAABLgAECgkJHwAXAHwSAA==.Emulmored:BAAALgAECgEJAQAAAA==.',
Er='Eraline:BAABLgAECn9HAAIXAAkJOBpIEAChAgAXAAkJOBpIEAChAgAAAA==.Eridium:BAAALgADCgMJAwAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fc='Fcawf:BAAALgADCgQJBAAAAA==.',
Fe='Fearless:BAABLgAECn8fAAIcAAcJwCK6SgDiAQAcAAcJwCK6SgDiAQAAAA==.',
Fi='Fizzlemonk:BAAALgAECgkJDAABLgAFFAQJDQASAEARAQ==.Fizzlepriest:BAAALgAECggJEQABLgAFFAQJDQASAEARAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Fresco:BAAALgAECgEJAQAAAA==.Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8+AAIYAAkJoSCeAAADAwAYAAkJoSCeAAADAwAuAAQKfyQAAhgACQnCI68EAPkCABgACQnCI68EAPkCAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAABLgAECn8WAAIIAAYJNwGlFQE0AAAIAAYJNwGlFQE0AAAAAA==.',
Gh='Ghost:BAABLgAECn8fAAIHAAgJGRgqAQC+AQAHAAgJGRgqAQC+AQAAAA==.Ghostfang:BAAALgAECgQJBAABLgAFFAYJGgAJAHARAA==.',
Gi='Gilden:BAABLgAECn8dAAMdAAkJ1giAZAAuAQAdAAkJ1giAZAAuAQAfAAMJYgOZiwBZAAAAAA==.',
Gn='Gnot:BAAALgAECgkJDAAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMFAAgJVBq5HQBQAgAFAAgJVBq5HQBQAgAEAAUJXBONPQAaAQAAAA==.',
Gy='Gyoza:BAABLgAECn8hAAMdAAkJpBpKEgC7AgAdAAkJpBpKEgC7AgAfAAUJHhlMQwAmAQABLgAECgkJKQAJAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8kAAIKAAgJbRkmFQDlAQAKAAgJbRkmFQDlAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgAECgYJDAAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMVAAkJfBOcPwDjAQAVAAkJfBOcPwDjAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8ZAAIFAAYJSw4TZQAFAQAFAAYJSw4TZQAFAQAAAA==.',
Im='Imperfect:BAAALgAECgEJAQAAAA==.',
In='Inafoxx:BAAALgAECgQJBAAAAA==.Inazuma:BAABLgAECn9GAAQMAAgJzxtKAQAnAgAMAAgJzxtKAQAnAgANAAQJkA9MFADIAAAOAAQJhAo/cACLAAAAAA==.Inazumaah:BAAALgAECgEJAQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAABLgAECn8VAAQFAAkJFxGuUwBBAQAFAAcJcA6uUwBBAQAaAAgJXgkQFgASAQAgAAEJ3xLCTwA5AAAAAA==.Invictum:BAAALgAECgYJBgAAAA==.',
Ir='Iridian:BAAALgADCgYJBAAAAA==.',
Is='Ishatani:BAABLgAECn8cAAQSAAkJDAzdkABQAQASAAkJ2gvdkABQAQAhAAQJawn3NwB/AAAJAAEJoQEqoQAdAAAAAA==.Isilod:BAAALgAECgcJEwAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMKAAkJeSQ2AwBSAwAKAAkJySM2AwBSAwAiAAkJ3yASAwC4AgAAAA==.',
Iy='Iyotanka:BAAALgAECgIJAwAAAA==.',
Jh='Jhovathicnas:BAAALgAECgEJAQAAAA==.',
Ji='Jig:BAAALgADCgYJBgABLgAECggJGgASACcNAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8fAAMgAAgJ+RJQEwCJAQAgAAcJXhVQEwCJAQAaAAcJyQbzQACjAAABLgAFFAcJJwAYABEDAA==.Juuzau:BAABLgAECn8cAAIdAAkJewluEwAFAQAdAAkJewluEwAFAQAAAA==.',
['Jå']='Jåmes:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8RAAIeAAQJOBB1KAAIAQAeAAQJOBB1KAAIAQAuAAQKfzQAAh4ACAljFE8bAPQBAB4ACAljFE8bAPQBAAAA.Kaners:BAABLgAFFH8OAAIWAAQJ4h8uEwBzAQAWAAQJ4h8uEwBzAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAISAAcJDyEaQgAAAgASAAcJDyEaQgAAAgAAAA==.Kathoran:BAAALgAECgEJAQAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgASAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAkJJwAFAEQiAA==.',
Ke='Kealey:BAABLgAECn8mAAISAAgJag/HIADeAAASAAgJag/HIADeAAAAAA==.Keine:BAAALgAECgcJCQAAAA==.Kessik:BAABLgAECn8lAAMGAAkJUhXpIgDcAQAGAAkJkxLpIgDcAQAQAAUJFRLwOADhAAAAAA==.',
Kh='Khaless:BAABLgAECn8dAAIPAAkJkRCcHABRAQAPAAkJkRCcHABRAQAAAA==.',
Ki='Kiamors:BAABLgAECn83AAMfAAkJsALCXADOAAAfAAkJsALCXADOAAAdAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJKQAJAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Kolaid:BAAALgAECgEJAQAAAA==.Koronus:BAAALgADCgUJCgAAAA==.Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCI1BQAOAwAGAAkJWCI1BQAOAwAQAAIJUQo0gwAnAAAAAA==.Kreleing:BAAALgAECgQJBQAAAA==.',
Ky='Kyndris:BAAALgAECgMJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAABLgAECn8aAAIVAAgJwhWBTAC8AQAVAAgJwhWBTAC8AQAAAA==.',
Ld='Ldx:BAAALgAECgEJAQAAAA==.',
Le='Leda:BAAALgAECgIJAwAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAACLgAFFH8JAAIIAAMJyBBLdgCXAAAIAAMJyBBLdgCXAAAuAAQKfyIAAwgACQnyG3UcAGkCAAgACQnyG3UcAGkCAAoABQmOBb1MAIQAAAAA.',
Li='Liandra:BAABLgAECn8WAAMUAAcJJgeYTwD6AAAUAAcJJgeYTwD6AAAZAAUJUgagYgCQAAAAAA==.Lightfighter:BAABLgAECn8aAAMSAAgJJw1lkgBOAQASAAgJPwxlkgBOAQAhAAQJlwreOAB7AAAAAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECggJGgASACcNAA==.Lilkiwi:BAABLgAECn8cAAILAAkJpwsyjQBdAQALAAkJpwsyjQBdAQAAAA==.Linley:BAAALgADCgUJBQAAAA==.',
Lo='Loozer:BAAALgAFFAIJBAAAAA==.Louhfu:BAABLgAECn8YAAISAAcJdBW7iABfAQASAAcJdBW7iABfAQAAAA==.',
Lu='Lunchbox:BAABLgAECn84AAIDAAkJwwz8IACUAQADAAkJwwz8IACUAQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB+1BwCiAgADAAkJwx61BwCiAgAVAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8PAAILAAQJIg9qZQAYAQALAAQJIg9qZQAYAQAuAAQKfzgAAgsACQkDGy80AEgCAAsACQkDGy80AEgCAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAABLgAFFH8MAAISAAQJxBGSMwDDAAASAAQJxBGSMwDDAAABLgAFFAkJHAALANUSAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAACLgAFFH8HAAIEAAQJUgkLKwDiAAAEAAQJUgkLKwDiAAAuAAQKfx8AAgQACQmmEdoeANEBAAQACQmmEdoeANEBAAAA.',
Me='Meadow:BAAALgAECgEJAQAAAA==.Meatfoot:BAAALgADCgcJCAAAAA==.Medie:BAABLgAECn9BAAMUAAkJnSH5BgDdAgAUAAkJnSH5BgDdAgAZAAUJsw1PVQC+AAAAAA==.Melody:BAAALgAECgEJAQAAAA==.',
Mi='Michelle:BAABLgAECn8xAAMSAAkJOB2UHQCUAgASAAkJOB2UHQCUAgAJAAgJEhTgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Monstrosity:BAAALgAECgMJAwABLgAFFAMJBQAVANUMAA==.Mordolm:BAAALgADCgMJBAAAAA==.Morello:BAAALgAECgEJAgABLgAECggJHwAHABkYAA==.',
My='Mystikan:BAAALgADCgcJDgABLgAECgYJDAAjAAAAAA==.',
['Mä']='Mäenard:BAAALgADCgUJBQAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAgJJQASAH8lAA==.Najinsky:BAACLgAFFH8lAAISAAgJfyW1DAAUAgASAAgJfyW1DAAUAgAuAAQKfzcAAhIACQmvJqgDAJYDABIACQmvJqgDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgkJEQAAAA==.Nefeli:BAAALgAECgIJAgAAAA==.Neikko:BAAALgAECgYJDgAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nelfury:BAAALgAECgQJBgABLgAECggJHwAHABkYAA==.Nelior:BAAALgAECgEJAQAAAA==.Nellir:BAABLgAECn86AAMTAAkJWxWNCADfAQATAAkJWxWNCADfAQAkAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Ninguem:BAAALgAFFAQJAwAAAA==.Nitefall:BAAALgAECgUJBQAAAA==.',
No='Nobudy:BAAALgAECgEJAQAAAA==.Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8dAAIFAAkJ7xZkJwAVAgAFAAkJ7xZkJwAVAgAAAA==.Nostariel:BAAALgADCgYJBgAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.Poughkeepsie:BAAALgAECgcJBwABLgAFFAQJCwAWACccAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJHwAHABkYAA==.',
Pu='Pulaski:BAAALgAECgUJBwAAAA==.Punchite:BAABLgAECn8dAAIRAAgJWh5wAwC7AQARAAgJWh5wAwC7AQABLgAECgkJOgAlACImAA==.',
Py='Pyrofanity:BAAALgADCgMJAwABLgAFFAYJGgAJAHARAA==.',
['Pè']='Pètitemort:BAAALgADCgYJEQAAAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJRQAhAIAgAA==.Ravenkalyth:BAAALgAECgEJAwAAAA==.Raymane:BAABLgAECn8YAAMfAAgJxQQTVQDmAAAfAAgJxQQTVQDmAAAdAAYJfgfIHQCiAAAAAA==.Rayvash:BAAALgADCgIJAgAAAA==.',
Re='Redemption:BAAALgADCgEJAQAAAA==.Reggie:BAAALgAECgQJBAABLgAFFAkJHAALANUSAA==.Reginato:BAAALgADCgYJBgAAAA==.Renamer:BAAALgAECgIJAgAAAA==.Rengokuu:BAABLgAECn8UAAIRAAcJUw4AOgAZAQARAAcJUw4AOgAZAQAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8aAAMJAAYJcBENEwCXAQAJAAYJcBENEwCXAQASAAEJqwENigAfAAAuAAQKf2oAAwkACQm4IYcAAFsDAAkACQm4IYcAAFsDABIABgnFCrVBAWoAAAAA.',
Rh='Rhau:BAABLgAECn8YAAImAAYJvR9ZCQAqAgAmAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAJAOocAA==.',
Ri='Ripplypickly:BAABLgAECn8aAAILAAgJWRE1DwB0AQALAAgJWRE1DwB0AQAAAA==.Rivanon:BAAALgADCgcJBwAAAA==.',
Ro='Rombo:BAABLgAECn8XAAIgAAYJgRttFAB7AQAgAAYJgRttFAB7AQAAAA==.Rosastrasza:BAAALgAECgIJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAABLgAECn8jAAIVAAgJlAojFQA6AQAVAAgJlAojFQA6AQAAAA==.Ryokamatsu:BAAALgAECgEJAQABLgAFFAMJCAAdALQlAA==.Ryukie:BAAALgAECggJDAAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAISAAMJdR7fYgDpAAASAAMJdR7fYgDpAAAuAAQKfx8AAhIACQm5IC8bAMYCABIACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Sallyacorn:BAAALgAECgEJAgAAAA==.Savall:BAAALgAECgcJEAAAAA==.',
Se='Serenna:BAAALgAFFAEJAQAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAABLgAFFH8IAAIkAAMJRgf1QwCJAAAkAAMJRgf1QwCJAAAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAFFAQJDQASAEARAQ==.Shambulance:BAAALgAECgcJBwABLgAFFAQJDQASAEARAQ==.Sharun:BAAALgAECgcJBwAAAA==.Sharundito:BAAALgAECgYJCQABLgAECgcJBwAjAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIMAAkJuR8WAwAhAwAMAAkJuR8WAwAhAwAAAA==.Sinistra:BAABLgAECn8cAAIkAAkJzhTVPgDhAQAkAAkJzhTVPgDhAQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAgAAAA==.',
So='Soelene:BAAALgAECgEJAQAAAA==.Soldjin:BAABLgAECn8XAAMgAAcJZBtVEACyAQAgAAcJZBtVEACyAQAaAAUJ+wKHaQBCAAABLgAFFAQJEAAhAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9kAAISAAkJ1iNKBQBLAwASAAkJ1iNKBQBLAwAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgQJBAAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIcAAYJVRuNhAB5AQAcAAYJVRuNhAB5AQABLgAECgcJGgAVAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.Stewpedassol:BAAALgAECgEJAgAAAA==.Stormtusk:BAAALgAECgcJCgABLgAECggJHwAHABkYAA==.Styxx:BAAALgADCgYJBwAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Sylindrah:BAAALgADCgkJCQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBQAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Ta='Talyea:BAAALgAECgYJBwAAAA==.',
Th='Thorfine:BAABLgAECn8kAAMGAAkJ9RWcTAAUAQAGAAcJQhWcTAAUAQAPAAUJKRXbNQChAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Tootsniffa:BAAALgAECgEJAQAAAA==.Toryn:BAAALgAECgIJAgAAAA==.Touraine:BAABLgAECn8qAAIfAAkJqB+TBADXAQAfAAkJqB+TBADXAQAAAA==.',
Tr='Trajann:BAAALgAECgEJAQAAAA==.Trashydps:BAAALgADCgIJAgAAAA==.Trashypotato:BAAALgAECgUJBQAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turbogranny:BAAALgAECgUJBQAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Ty='Tyrondius:BAAALgADCgMJAwAAAA==.',
Uk='Ukagon:BAAALgADCgcJBwABLgAECgkJMwAFANoPAA==.',
Un='Unmei:BAABLgAECn84AAIfAAkJ8AxSMgB0AQAfAAkJ8AxSMgB0AQAAAA==.',
Va='Valcoree:BAAALgAECgQJBAABLgAECggJKwAZAHUSAA==.Valkrynd:BAAALgAECgEJAQAAAA==.Valynor:BAAALgAECgEJAgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAIVAAgJByIrCQABAwAVAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgIJAwAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIJAAkJ6hx3EACUAgAJAAkJ6hx3EACUAgAAAA==.Walbras:BAAALgAECgYJBgAAAA==.',
Wh='Whirrlytusk:BAACLgAFFH8GAAIXAAQJpgtuNgDPAAAXAAQJpgtuNgDPAAAuAAQKfxQAAhcABwndFM8hAKUBABcABwndFM8hAKUBAAAA.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPgAaABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDgAjAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAMJDAAWAPgZAA==.',
Xe='Xephi:BAABLgAECn8YAAQmAAgJKA3JFgDuAAAmAAgJKA3JFgDuAAATAAMJiAbPMwBTAAAkAAEJhAdmUAEsAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIlAAkJIiYwAABhAwAlAAkJIiYwAABhAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJEwAAAA==.Zeldoris:BAABLgAECn9FAAIhAAkJgCA7BADAAgAhAAkJgCA7BADAAgAAAA==.Zenelf:BAAALgAECgUJCAABLgAECggJHwAHABkYAA==.',
Zi='Zillika:BAABLgAFFH8HAAISAAMJFhdaYADuAAASAAMJFhdaYADuAAAAAA==.',
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
