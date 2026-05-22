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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Warrior-Fury','Warrior-Protection','Priest-Discipline','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-21',data={Ad='Advvy:BAEALgAECgUJDgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn84AAICAAkJgCKMBAADAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQACAAkJgCKMBAADAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAFAFUAbQwAAAQATQDqDAAACQBVAG4MAAAEAFoAbwwAAAMAXQAAAA==.Algebra:BAECLgAFFH8VAAIDAAUJ6ST3GQC2AQVoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCekk9xkAtgEFaAwAAAYAWwBpDAAABQBhAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCaEkuwYANAMAAwAJCaEkuwYANAMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgYJDgAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJHQAEACcdAA==.',
Ay='Ayoade:BAECLgAFFH8UAAIFAAQJohTwCgA8AQRoDAAABQAzAGkMAAAFAD0AawwAAAUANADqDAAABQAtAAUABAmiFPAKADwBBGgMAAAFADMAaQwAAAUAPQBrDAAABQA0AOoMAAAFAC0ALgAECn8YAAMFAAgJaRydCgCMAgAFAAgJaRydCgCMAgAGAAIJERXjMQCHAAABLgAFFAgJKgAHAH0gAA==.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJMBEVZwBTAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICTARFWcAUwEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEALgAFFAQJBAABLgAFFAUJEQAKACAVAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAILAAgJnhhyAgAvAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgACwAICZ4YcgIALwIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LAACCwAJCWMgmAoA4AIACwAJCWMgmAoA4AIAAAA=.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.Crustorc:BAEALgAECgYJBgABLgAECgYJEgABAAAAAA==.',
De='Deathhunterz:BAEALgAECgQJBwAAAA==.Demagogué:BAECLgAFFH8KAAMMAAYJfhNsIwDYAAZoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAQAKgAMAAQJ5gtsIwDYAARrDAAAAQAJAGoMAAABACUAbQwAAAEAJwDqDAAABAAqAAcAAglvDwFGAIoAAmgMAAABABwAbAwAAAIAMgAuAAQKfx4AAwwACAnvI/cHALYCAAwACAnvI/cHALYCAAcABwnaGaQzAKsBAAEuAAUUBwkQAAUAsw4A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8LAAINAAYJUiBMBQBCAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQANAAYJUiBMBQBCAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAuAAQKfxcAAw0ACAmLIZwGAPMCAA0ACAmLIZwGAPMCAA4AAQl/JrtbAG4AAAEuAAUUCAkqAAcAfSAA.Dubsy:BAECLgAFFH8qAAIHAAgJfSB/AAA2AghoDAAACQBQAGkMAAAJAF8AawwAAAYAWwBqDAAABwBjAGwMAAABAEMAbQwAAAEALADqDAAACABWAG4MAAABAGQABwAICX0gfwAANgIIaAwAAAkAUABpDAAACQBfAGsMAAAGAFsAagwAAAcAYwBsDAAAAQBDAG0MAAABACwA6gwAAAgAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMADAADCfQiFDkAGgEAAAA=.',
Eh='Ehanee:BAEALgAFFAEJAQAAAA==.',
Er='Ereshin:BAEALgAECggJDwAAAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJBQAPAEofAA==.Evierari:BAEBLgAFFH8FAAMPAAIJSh/1GwCiAAJoDAAAAwBQAGkMAAACAE8ADwACCUof9RsAogACaAwAAAIAUABpDAAAAgBPAAQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8bAAMQAAUJkiTPCgB8AQVoDAAABwBiAGkMAAAHAGEAawwAAAUATgBqDAAAAgA3AOoMAAAGAGMAEAAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABEABQndD3MHACoBBWgMAAABACoAaQwAAAEAOgBrDAAAAQArAGoMAAABACQA6gwAAAEAEQAuAAQKfzkAAxAACQkhJncCALQDABAACQkhJncCALQDABEAAgnNFQodAIgAAAAA.',
Fo='Fofer:BAEBLgAECn8iAAILAAcJkiWnCACHAgdoDAAABwBhAGkMAAAHAF4AawwAAAcAYwBqDAAABABhAGwMAAAEAGIAbQwAAAEAWQDqDAAABABgAAsABwmSJacIAIcCB2gMAAAHAGEAaQwAAAcAXgBrDAAABwBjAGoMAAAEAGEAbAwAAAQAYgBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AEgBCHwA=.Foil:BAEALgADCgkJCQABLgAECgkJOwATAOgkAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECggJDwABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMKAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAFAAFCZkOPDkACwEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAoAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwoACQmfIMQBAPwCAAoACAmzIsQBAPwCABQABgl+FkJEAJMBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8KAAIVAAMJACI2FgArAQNoDAAABgBbAGkMAAACAE8A6gwAAAIAWgAVAAMJACI2FgArAQNoDAAABgBbAGkMAAACAE8A6gwAAAIAWgAuAAQKfycAAxUACQk8IH8JAPkCABUACQk8IH8JAPkCABYAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAITAAMJSxSMKQDoAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgATAAMJSxSMKQDoAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJKgAHAH0gAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJGwAQAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIXAAkJWhY7CgAWAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAXAAkJWhY7CgAWAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIUAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAFAAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACFAAHCaElOhkAWwIAFAAHCaElOhkAWwIAAS4ABRQHCRAABQCzDgA=.',
Ke='Kelandrea:BAECLgAFFH8GAAIYAAIJwAtFaQCUAAJoDAAAAwAWAOoMAAADACUAGAACCcALRWkAlAACaAwAAAMAFgDqDAAAAwAlAC4ABAp/HAAEGAAJCaEa2CIAngIAGAAJCaEa2CIAngIAGQACCdIQ94EAcAAAGgACCTMXNTwAQQAAAAA=.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJFgAbAKocAA==.',
Kr='Kregazi:BAECLgAFFH8IAAISAAMJaBRmGwDAAANoDAAAAwA7AGkMAAADAEMA6gwAAAIAHQASAAMJaBRmGwDAAANoDAAAAwA7AGkMAAADAEMA6gwAAAIAHQAuAAQKfy4AAhIACQmUItgDANgCABIACQmUItgDANgCAAAA.',
Ky='Kyriste:BAEBLgAECn8XAAIPAAcJZiH8CgCIAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAgBVAGwMAAACAEAA6gwAAAMAWwBuDAAAAgBXAA8ABwlmIfwKAIgCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAACAFUAbAwAAAIAQADqDAAAAwBbAG4MAAACAFcAAS4ABRQECRcAFQBgIQA=.',
La='Larissaqt:BAECLgAFFH8cAAIEAAYJ0xLfBwCWAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAEAAYJ0xLfBwCWAQZoDAAABgBKAGkMAAAFADoAawwAAAYAHQBqDAAABQAgAGwMAAACADEA6gwAAAQAGwAuAAQKfyAAAgQACAnUILITAAYCAAQACAnUILITAAYCAAAA.',
Li='Lilylock:BAEALgAECgEJAQABLgAECggJFgAcAHgeAA==.Lilyweave:BAEBLgAECn8WAAQcAAgJeB6sFQCgAghoDAAAAwBLAGkMAAADAFcAawwAAAMAVwBqDAAABABcAGwMAAADAFEAbQwAAAIAPQDqDAAAAgBaAG4MAAACAD4AHAAICXgerBUAoAIIaAwAAAIASwBpDAAAAgBXAGsMAAADAFcAagwAAAQAXABsDAAAAgBRAG0MAAACAD0A6gwAAAIAWgBuDAAAAgA+AB0AAgkNDzw9AGMAAmgMAAABABgAaQwAAAEANAAXAAEJNwzCQgAzAAFsDAAAAQAfAAAA.Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8QAAIFAAcJsw5zCADYAQdoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoAbQwAAAEACADqDAAABAAxAAUABwmzDnMIANgBB2gMAAADADAAaQwAAAMAQwBrDAAAAwAtAGoMAAABACIAbAwAAAEACgBtDAAAAQAIAOoMAAAEADEALgAECn8kAAQFAAgJiRwaCABHAgAFAAcJJSAaCABHAgACAAUJKBEqNwAbAQAGAAMJHBzfJwDiAAAAAA==.Maxxy:BAEBLgAECn8cAAITAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAATAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMPAAQJ+A30EgD3AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUAA8ABAldDfQSAPcABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AHgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADHgAICc4ZmQwAbgIAHgAICc4ZmQwAbgIADwAECSYMg1wAwQAAAS4ABRQICSoABwB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgQJBwABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgALADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.Minidruid:BAECLgAFFH8NAAIbAAUJcRgsFAA4AQVoDAAAAwBDAGkMAAADAEMAawwAAAMAMwBqDAAAAQAsAOoMAAADAD4AGwAFCXEYLBQAOAEFaAwAAAMAQwBpDAAAAwBDAGsMAAADADMAagwAAAEALADqDAAAAwA+AC4ABAp/HgACGwAHCY8i4w0ATQIAGwAHCY8i4w0ATQIAAS4ABRQDCQcAAwC2EwA=.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8RAAIYAAUJ6BPMJwA4AQVoDAAABQAzAGkMAAAEAD4AawwAAAMAOgBqDAAAAQAxAOoMAAAEAB8AGAAFCegTzCcAOAEFaAwAAAUAMwBpDAAABAA+AGsMAAADADoAagwAAAEAMQDqDAAABAAfAC4ABAp/OgACGAAJCe0gvhEAvAIAGAAJCe0gvhEAvAIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEALgAECgkJAgABLgAFFAIJBgAYAMALAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAMAH8aAA==.Nixei:BAEBLgAECn8UAAIMAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYADAAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIPAAkJvSMEAwBHAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAPAAkJvSMEAwBHAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCAABLgAECggJDwABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJOAAPAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJBgABLgAFFAcJEAAFALMOAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMLAAkJNhDoGwChAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwALAAkJ8Q7oGwChAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAOAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQAKACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8XAAIVAAQJYCGXCgB7AQRoDAAACABcAGkMAAAIAFUAawwAAAQARADqDAAAAwBeABUABAlgIZcKAHsBBGgMAAAIAFwAaQwAAAgAVQBrDAAABABEAOoMAAADAF4ALgAECn87AAMVAAkJiCVuAwDyAgAVAAkJWSVuAwDyAgAWAAIJnRghFQCoAAAAAA==.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCgAVAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAADAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAAuAAQKfxkAAgMACAkUHK5DAG0CAAMACAkUHK5DAG0CAAAA.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJDwABAAAAAA==.Shinthyr:BAEBLgAECn8VAAIPAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6AA8ABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICQ8AAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
Ta='Tahune:BAEBLgAECn87AAMTAAkJ6CRNAQC5AwloDAAACQBdAGkMAAAIAGIAawwAAAgAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAIAWAATAAkJ6CRNAQC5AwloDAAABwBdAGkMAAAIAGIAawwAAAYAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAIAWAAbAAIJhiETTwCYAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAILAAgJVhEIJwBSAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYACwAICVYRCCcAUgEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBAkQABIAiyAA.',
Th='Therapygap:BAEBLgAECn8nAAQPAAgJgBK0IQCLAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABAAdAGwMAAAIADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgADwAHCaYUtCEAiwEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAMAHQBsDAAABgA0AG0MAAABACMA6gwAAAUAPAAEAAYJKwpwSgCtAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAeAAEJfAPGagAiAAFuDAAAAQAIAAEuAAQKCQk4AA8AgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwANAHYbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAcJEAAFALMOAA==.',
Us='Usurah:BAECLgAFFH8YAAIYAAYJDBl2DwCTAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAYAAYJDBl2DwCTAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAuAAQKfysAAxgACQmAIsQJAEMDABgACQmAIsQJAEMDABoABQlYHBoWAD0BAAAA.',
Vi='Vindh:BAECLgAFFH8OAAMUAAQJugc/QADzAARoDAAABQAXAGkMAAADABUAawwAAAIACADqDAAABAAYABQABAm6Bz9AAPMABGgMAAAFABcAaQwAAAMAFQBrDAAAAgAIAOoMAAADABgACgABCQ4GYw0AKwAB6gwAAAEADwAuAAQKfygABBQACQm3FV09AP8BABQACQm3FV09AP8BAAoAAgk6A28nAD0AAB8AAQkAABFnAAAAAAAA.',
Ya='Yaav:BAEBLgAECn8XAAIQAAkJxhA/RgDIAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAQAAkJxhA/RgDIAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8WAAIbAAcJqhxkGwC6AQdoDAAABABKAGkMAAAEAFYAawwAAAMATwBqDAAAAgA7AGwMAAAEAEgA6gwAAAQAVABuDAAAAQAqABsABwmqHGQbALoBB2gMAAAEAEoAaQwAAAQAVgBrDAAAAwBPAGoMAAACADsAbAwAAAQASADqDAAABABUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnho1PABLAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGjU8AEsBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx99QgDzAQADAAkJlx99QgDzAQAAAA==.',
Zo='Zomb:BAECLgAFFH8QAAISAAQJiyAeCwBfAQRoDAAABgBYAGkMAAAFAEQAawwAAAIAXQDqDAAAAwBSABIABAmLIB4LAF8BBGgMAAAGAFgAaQwAAAUARABrDAAAAgBdAOoMAAADAFIALgAECn8lAAISAAgJjiFpBAAFAwASAAgJjiFpBAAFAwAAAA==.',
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
