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

local lookup = {'DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Shaman-Restoration','Rogue-Assassination','Warlock-Destruction','Druid-Feral','DeathKnight-Frost','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Druid-Balance','Paladin-Protection','DeathKnight-Blood','Shaman-Elemental','Rogue-Subtlety',}
local provider = {region='US',realm='Barthilas',name='US',type='subscribers',zone=53,date='2026-11-17',data={Al='Alithira:BAEANQAECgcICQABNQAFFAQIBgABAFgHAA==.Aluggo:BAEBNQAECn86AAMCAAoK1CQiBgCbAwqODQAACQBhAHUNAAAHAGAAfw0AAAcAYACpDQAABwBhAFwNAAAEAGMAXQ0AAAQAYgBlDQAACABdAKQNAAAEAFoAMw0AAAQATAC5DQAABABgAAIACgrUJCIGAJsDCo4NAAAHAGEAdQ0AAAcAYAB/DQAABwBgAKkNAAAGAGEAXA0AAAQAYwBdDQAABABiAGUNAAAHAF0ApA0AAAQAWgAzDQAABABMALkNAAAEAGAAAwADCsERoEMBtAADjg0AAAIAMwCpDQAAAQAzAGUNAAABACAAAAA=.',
Ca='Cakelynn:BAEBNQAECn8cAAIEAAcKGhiSGwCjAQeODQAABQBEAKkNAAACAD8AXA0AAAIAKgBlDQAABgBAAKQNAAAGADgAMw0AAAIADgC5DQAABQBLAAQABwoaGJIbAKMBB44NAAAFAEQAqQ0AAAIAPwBcDQAAAgAqAGUNAAAGAEAApA0AAAYAOAAzDQAAAgAOALkNAAAFAEsAATUABRQHCAoABQDzEwA=.',
Cu='Cutehunter:BAECNQAFFH8XAAMGAAcKLx6OAwAqAgeODQAABABfAHUNAAAEAF8Afw0AAAIASwCpDQAABQBjAFwNAAACABMAZQ0AAAEASwAzDQAABQBXAAYABgpRHo4DACoCBo4NAAADAF8AdQ0AAAIAXwB/DQAAAgBLAKkNAAACAGMAXA0AAAIAEwAzDQAAAQARAAQABQruEnwRACYBBY4NAAABACIAdQ0AAAIAFQCpDQAAAwA9AGUNAAABAEsAMw0AAAQAVwA1AAQKfzsABAQACgq6JWkQAOUCAAQACgo3H2kQAOUCAAYACQrzJo00AM4CAAcAAQpeEA4SAEcAAAAA.',
De='Deathseen:BAEANQADCgYIBgABNQAFFAEIAQAIAAAAAA==.',
Dr='Dragonrawrr:BAEBNQAECn8dAAICAAoKNBzNEQAuAwqODQAABgBdAHUNAAADAFAAfw0AAAMAXACpDQAAAwAxAFwNAAACABYAXQ0AAAIAUQBlDQAABABKAKQNAAACAFIAMw0AAAEALgC5DQAAAwBgAAIACgo0HM0RAC4DCo4NAAAGAF0AdQ0AAAMAUAB/DQAAAwBcAKkNAAADADEAXA0AAAIAFgBdDQAAAgBRAGUNAAAEAEoApA0AAAIAUgAzDQAAAQAuALkNAAADAGAAATUABAoKCjUACQDMJAA=.',
Fo='Forseen:BAEBNQAECn8aAAIKAAgKpg8zNgAAAgiODQAABwA2AHUNAAAFACkAfw0AAAMAMACpDQAAAwAbAFwNAAADADkAXQ0AAAEAHQBlDQAAAQAdADMNAAADADoACgAICqYPMzYAAAIIjg0AAAcANgB1DQAABQApAH8NAAADADAAqQ0AAAMAGwBcDQAAAwA5AF0NAAABAB0AZQ0AAAEAHQAzDQAAAwA6AAE1AAUUAQgBAAgAAAAA.',
Fy='Fyrre:BAECNQAFFH8WAAIGAAcKxR5aBAC+AQeODQAABQBbAHUNAAAEAFsAfw0AAAEAQACpDQAABgBGAFwNAAABAFYAXQ0AAAEANgAzDQAABABaAAYABwrFHloEAL4BB44NAAAFAFsAdQ0AAAQAWwB/DQAAAQBAAKkNAAAGAEYAXA0AAAEAVgBdDQAAAQA2ADMNAAAEAFoANQAECn9KAAIGAAoKYCWDCgA4AwAGAAoKYCWDCgA4AwAAAA==.',
['Fô']='Fôrseen:BAEANQADCgcIEwABNQAFFAEIAQAIAAAAAA==.',
Hu='Huegreen:BAEANQAECgEIAQABNQAFFAgIGgALAGcCAA==.',
Hv='Hverir:BAEANQAECgYICwABNQAECgoKNQAJAMwkAA==.',
Ji='Jingsho:BAEANQAECggIDwAAAA==.',
Kh='Khlp:BAEANQAECgEIAwABNQAECgQIBQAIAAAAAA==.',
['Kí']='Kíngkongkod:BAEANQAECggICwABNQAFFAYIFwAMAEAcAA==.',
Lo='Lotheril:BAEBNQAECn8+AAIDAAoKKRwOPwDYAgqODQAACABEAHUNAAAGAFUAfw0AAAYAQwCpDQAACABJAFwNAAAGAFcAXQ0AAAUAPgBlDQAABwBSAKQNAAAFAD4AMw0AAAkAUwC5DQAAAgA2AAMACgopHA4/ANgCCo4NAAAIAEQAdQ0AAAYAVQB/DQAABgBDAKkNAAAIAEkAXA0AAAYAVwBdDQAABQA+AGUNAAAHAFIApA0AAAUAPgAzDQAACQBTALkNAAACADYAATUABRQECAYAAQBYBwA=.',
Ma='Malpractis:BAEANQAECgQIBAABNQAFFAoKOwAFAJwiAA==.Manboo:BAEBNQAECn81AAIJAAoKzCSpCQB0AwqODQAABwBfAHUNAAAHAF0Afw0AAAYAXgCpDQAABwBgAFwNAAAEAFsAXQ0AAAQAXgBlDQAABgBjAKQNAAAGAF0AMw0AAAMAXAC5DQAAAwBbAAkACgrMJKkJAHQDCo4NAAAHAF8AdQ0AAAcAXQB/DQAABgBeAKkNAAAHAGAAXA0AAAQAWwBdDQAABABeAGUNAAAGAGMApA0AAAYAXQAzDQAAAwBcALkNAAADAFsAAAA=.Masamura:BAECNQAFFH8GAAIBAAQKWAeVCgCwAASODQAAAgAYAHUNAAABAAYAqQ0AAAIAGQAzDQAAAQAXAAEABApYB5UKALAABI4NAAACABgAdQ0AAAEABgCpDQAAAgAZADMNAAABABcANQAECn9iAAMBAAoK9x7wFgA2AgABAAkKcB/wFgA2AgANAAUKyxFsZQANAQAAAA==.Mathstutorli:BAECNQAFFH8XAAIMAAYKQBzTAADsAQaODQAABgBjAHUNAAAEAFoAfw0AAAIAOQCpDQAABgBaAFwNAAABAAkAMw0AAAQAVwAMAAYKQBzTAADsAQaODQAABgBjAHUNAAAEAFoAfw0AAAIAOQCpDQAABgBaAFwNAAABAAkAMw0AAAQAVwA1AAQKf1UAAgwACgrPJpsAAO0DAAwACgrPJpsAAO0DAAAA.',
Mi='Miidira:BAEBNQAECn81AAMBAAoKtRW/SAD0AQqODQAACAA5AHUNAAAFADgAfw0AAAcAQQCpDQAABgAuAFwNAAAEAFAAXQ0AAAMAMABlDQAABQA5AKQNAAAGADIAMw0AAAYANgC5DQAAAwAuAAEACQr3Fb9IAPQBCY4NAAAIADkAdQ0AAAQAOAB/DQAABwBBAKkNAAAGAC4AXA0AAAQAUABdDQAAAgAwAGUNAAAEADkAMw0AAAYANgC5DQAAAwAuAA0ABApsDAF4AMQABHUNAAABACwAXQ0AAAEACQBlDQAAAQAWAKQNAAAGADIAATUABRQECAYAAQBYBwA=.',
Mo='Mofugga:BAEBNQAECn8nAAIOAAoKiCL2AwBZAwqODQAABQBTAHUNAAAEAFwAfw0AAAUAVQCpDQAABQBgAFwNAAACAFoAXQ0AAAIAWABlDQAABgBQAKQNAAAFAE8AMw0AAAEAUgC5DQAABABeAA4ACgqIIvYDAFkDCo4NAAAFAFMAdQ0AAAQAXAB/DQAABQBVAKkNAAAFAGAAXA0AAAIAWgBdDQAAAgBYAGUNAAAGAFAApA0AAAUATwAzDQAAAQBSALkNAAAEAF4AATUABRQGCBcADABAHAA=.Mourningsage:BAECNQAFFH8ZAAQPAAgKKxVLBgAIAgiODQAABABYAHUNAAADADcAfw0AAAQANQCpDQAABQBTAFwNAAACADgAXQ0AAAEAEgBlDQAAAQAXADMNAAAFAFAADwAGChEYSwYACAIGjg0AAAQAWAB/DQAABAA1AKkNAAAFAFMAXA0AAAIAOABdDQAAAQASADMNAAAFAFAACwABCq8V3hsATgABdQ0AAAMANwAQAAEKDwmqFwBMAAFlDQAAAQAXADUABAp/TwAEDwAKCjklUg4A+gIADwAKChglUg4A+gIACwAGCuIYJhoAmwEAEAAEChghwRIAHgEAAAA=.',
Ni='Nickbatum:BAEANQAECggIEQAAAA==.',
Nu='Nutshocker:BAEANQAECggICQAAAA==.',
Pa='Pafupafu:BAEANQAECgYIBwABNQAECgkJKAAGAI4kAA==.',
Pe='Peterpikachu:BAEANQAECgMIAwABNQAECgoKGgAJAFQUAA==.',
Pr='Prophethic:BAEANQAFFAEIAQAAAA==.',
Ra='Randomno:BAECNQAFFH8aAAQLAAgKZwIqBwC4AAiODQAABQAPAHUNAAAEAAQAfw0AAAQAAgCpDQAABAAJAFwNAAACAAMAXQ0AAAEAAABlDQAAAQACADMNAAAFAA0ADwAGCp8CNhMAYgEGjg0AAAMADAB/DQAABAACAKkNAAABAAkAXA0AAAIAAwBdDQAAAQAAADMNAAAFAA0ACwADCjwDKgcAuAADjg0AAAIADwB1DQAABAAEAKkNAAADAAQAEAABCh0BMhoAQgABZQ0AAAEAAgA1AAQKf2AABAsACgqCEz4JAGYCAAsACQoqDz4JAGYCAA8ACgqPERJkAC0CABAAAQrwDFAvADQAAAAA.',
Ro='Roksta:BAEANQAECgcICwABNQAECggICwAIAAAAAA==.Rounnin:BAEANQADCgIIAgABNQAFFAQIBgABAFgHAA==.',
Sh='Sherkia:BAEANQADCgUIBgABNQAECgYIGAARAJQPAA==.Sherko:BAEBNQAECn8YAAQRAAYKlA8kKwCnAAaODQAABgA5AHUNAAAFADUAfw0AAAQAMQCpDQAABAAfAFwNAAACABEAMw0AAAMAMgASAAYK1Aq3yQDhAAaODQAABQAfAHUNAAACACoAfw0AAAIAKACpDQAAAgAUAFwNAAACABEAMw0AAAMAMgARAAQKLhIkKwCnAASODQAAAQA5AHUNAAABADUAfw0AAAEAMQCpDQAAAQAdABMAAwrpDVcqAGEAA3UNAAACACcAfw0AAAEAFgCpDQAAAQAfAAAA.Sherkocalyps:BAEANQAECgEIAQABNQAECgYIGAARAJQPAA==.Shruggo:BAEBNQAECn8bAAMUAAkKbBeNEAAJAgmODQAABABQAHUNAAAEAE4Afw0AAAQAQQCpDQAAAwBOAFwNAAADAEQAXQ0AAAMAJwBlDQAAAgBBADMNAAACACAAuQ0AAAIAHgAUAAkKbBeNEAAJAgmODQAABABQAHUNAAAEAE4Afw0AAAQAQQCpDQAAAwBOAFwNAAADAEQAXQ0AAAMAJwBlDQAAAgBBADMNAAABACAAuQ0AAAIAHgAVAAEKAACxcAAAAAEzDQAAAQAPAAE1AAQKCgo6AAIA1CQA.',
Sk='Skorpbear:BAEBNQAECn80AAQWAAoKuxdYGQDfAQqODQAACwBSAHUNAAAIAFgAfw0AAAcARgCpDQAABwAzAFwNAAACABAAXQ0AAAEABABlDQAABwBOAKQNAAACAFAAMw0AAAQASQC5DQAAAwBTABYACAqvHVgZAN8BCI4NAAABAFIAdQ0AAAEAWAB/DQAAAQBGAKkNAAABACoAZQ0AAAIATgCkDQAAAQBQADMNAAADAEkAuQ0AAAEAUwAXAAoKYw7lNgBbAQqODQAACAAzAHUNAAAFADoAfw0AAAQARACpDQAABAAzAFwNAAACABAAXQ0AAAEABABlDQAABQAhAKQNAAABABoAMw0AAAEAOgC5DQAAAgAzAAwABAo8DCIrALgABI4NAAACABUAdQ0AAAIAIwB/DQAAAgAOAKkNAAACACUAAAA=.Skorpionjr:BAEBNQAECn80AAMDAAoKgBkPcwBIAgqODQAACwBAAHUNAAAIAEIAfw0AAAgAPwCpDQAABQA4AFwNAAACAEYAXQ0AAAEAMgBlDQAABwBGAKQNAAAFADwAMw0AAAIANQC5DQAAAwBSAAMACgqAGQ9zAEgCCo4NAAAKAEAAdQ0AAAcAQgB/DQAACAA/AKkNAAAFADgAXA0AAAIARgBdDQAAAQAyAGUNAAAHAEYApA0AAAUAPAAzDQAAAgA1ALkNAAADAFIAGAACCq8LPmcALwACjg0AAAEAFAB1DQAAAQAnAAE1AAQKCgo0ABYAuxcA.Skorprunes:BAEBNQAECn8aAAIZAAcKWhOYTwD/AAeODQAABQAoAHUNAAAFADQAfw0AAAQAMwCpDQAABQBQAGUNAAAEACoApA0AAAEAHwAzDQAAAgAeABkABwpaE5hPAP8AB44NAAAFACgAdQ0AAAUANAB/DQAABAAzAKkNAAAFAFAAZQ0AAAQAKgCkDQAAAQAfADMNAAACAB4AATUABAoKCjQAFgC7FwA=.',
Sp='Sparkmac:BAEBNQAECn8ZAAMaAAkK5hJFWQB7AQmODQAABAAwAHUNAAAEAEQAfw0AAAQALgCpDQAABAA8AFwNAAADADYAXQ0AAAIAGwBlDQAAAQAeAKQNAAABADEAMw0AAAIAKQAaAAgKCxRFWQB7AQiODQAAAgAwAHUNAAADAEQAfw0AAAMALgCpDQAAAgA8AFwNAAACADYAXQ0AAAIAGwCkDQAAAQAxADMNAAABACkACQAHCrgOU4cAeAEHjg0AAAIANwB1DQAAAQAqAH8NAAABADAAqQ0AAAIAUQBcDQAAAQANAGUNAAABAAgAMw0AAAEADQABNQAFFAgIGQAPACsVAA==.',
Wa='Wafuwafu:BAEANQAECgYICAABNQAECgkJKAAGAI4kAA==.Waterheart:BAEBNQAECn8aAAMJAAoKVBS7dgCnAQqODQAAAgAtAHUNAAACAEIAfw0AAAIAKgCpDQAAAgAiAFwNAAAEABsAXQ0AAAYAQABlDQAAAgAgAKQNAAAEADQAMw0AAAEAWAC5DQAAAQBCAAkACQq+Ert2AKcBCY4NAAACAC0AdQ0AAAIAQgB/DQAAAgAqAKkNAAABACIAXA0AAAMAGwBdDQAABgBAAGUNAAACACAApA0AAAMANAC5DQAAAQBCABoABAquExivAKkABKkNAAABAEYAXA0AAAEALQCkDQAAAQAiADMNAAABABsAAAA=.',
Wi='Wijon:BAEBNQAECn85AAIVAAoKiR6MCwAdAwqODQAABgBVAHUNAAAHAFAAfw0AAAkAXACpDQAABwBaAFwNAAAGAEwAXQ0AAAMASwBlDQAABgBQAKQNAAAGAEkAMw0AAAQAXwC5DQAAAwA+ABUACgqJHowLAB0DCo4NAAAGAFUAdQ0AAAcAUAB/DQAACQBcAKkNAAAHAFoAXA0AAAYATABdDQAAAwBLAGUNAAAGAFAApA0AAAYASQAzDQAABABfALkNAAADAD4AAAA=.',
Xu='Xugi:BAEBNQAECn8fAAIPAAgK+hjRTgDnAQiODQAABQBCAHUNAAAFAFAAfw0AAAUAXACpDQAABQBDAFwNAAAFAD0AXQ0AAAQARwBlDQAAAQA6AKQNAAABACkADwAICvoY0U4A5wEIjg0AAAUAQgB1DQAABQBQAH8NAAAFAFwAqQ0AAAUAQwBcDQAABQA9AF0NAAAEAEcAZQ0AAAEAOgCkDQAAAQApAAE1AAQKCgo6AAIA1CQA.',
Xx='Xxlanaconda:BAEBNQAECn8ZAAIbAAkK8xuHHAChAgmODQAAAwBKAHUNAAADAFAAfw0AAAMAUACpDQAAAwBQAFwNAAACAC0AXQ0AAAIARABlDQAABABNAKQNAAAEAE0AuQ0AAAEAQwAbAAkK8xuHHAChAgmODQAAAwBKAHUNAAADAFAAfw0AAAMAUACpDQAAAwBQAFwNAAACAC0AXQ0AAAIARABlDQAABABNAKQNAAAEAE0AuQ0AAAEAQwABNQAFFAYIFwAMAEAcAA==.',
Zy='Zygote:BAEBNQAECn8oAAIGAAkKjiQiFgDwAgmODQAABgBgAHUNAAAGAFsAfw0AAAQAVQCpDQAABQBcAFwNAAADAF0AXQ0AAAQAYgBlDQAABQBVAKQNAAAEAGEAuQ0AAAMAXQAGAAkKjiQiFgDwAgmODQAABgBgAHUNAAAGAFsAfw0AAAQAVQCpDQAABQBcAFwNAAADAF0AXQ0AAAQAYgBlDQAABQBVAKQNAAAEAGEAuQ0AAAMAXQAAAA==.',
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
