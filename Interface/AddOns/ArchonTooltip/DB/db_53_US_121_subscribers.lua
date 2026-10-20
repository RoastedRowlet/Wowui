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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Druid-Balance','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=53,date='2026-10-20',data={As='Astaren:BAEANQAECgYIDgAAAA==.',
Br='Bryl:BAECNQAFFH8UAAIBAAYKLhtjCADaAQaODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AMw0AAAIANAABAAYKLhtjCADaAQaODQAABQA7AHUNAAAEAFAAfw0AAAMAQgCpDQAABQBKAFwNAAABAD8AMw0AAAIANAA1AAQKfx4AAgEACgpzHMoUAD4BAAEACgpzHMoUAD4BAAAA.Brylic:BAECNQAFFH8OAAICAAQKVR8VAQAbAQSODQAABQBSAHUNAAAEAE0Afw0AAAEAOgCpDQAABABQAAIABApVHxUBABsBBI4NAAAFAFIAdQ0AAAQATQB/DQAAAQA6AKkNAAAEAFAANQAECn8vAAMCAAoKNCIwBAA6AwACAAoKNCIwBAA6AwADAAEKWxqNLgBaAAABNQAFFAYIFAABAC4bAA==.Brylicet:BAEANQADCgQIBAABNQAFFAYIFAABAC4bAA==.',
Co='Coolshirtbra:BAEANQAECgQIBAABNQAECgoKMwAEAHcdAA==.',
Da='Dantius:BAEANQADCggICAABNQAECgoKNwAFAEEWAA==.Darkorin:BAEBNQAECn8wAAMGAAoKzSJlBgDGAwqODQAACABjAHUNAAAFAGMAfw0AAAUAXwCpDQAABgBjAFwNAAAEAFwAXQ0AAAQAYwBlDQAABwBjAKQNAAAEAGMAMw0AAAQAYwC5DQAAAQAYAAYACgrNImUGAMYDCo4NAAAIAGMAdQ0AAAUAYwB/DQAABABfAKkNAAAGAGMAXA0AAAQAXABdDQAABABjAGUNAAAHAGMApA0AAAQAYwAzDQAAAwBjALkNAAABABgABwACCtoXZv0AgQACfw0AAAEAQwAzDQAAAQA2AAAA.',
Dr='Dragore:BAECNQAFFH8IAAIDAAMKwBDbBADGAAOODQAABABJAHUNAAABACcAqQ0AAAMADwADAAMKwBDbBADGAAOODQAABABJAHUNAAABACcAqQ0AAAMADwA1AAQKfy0AAgMACgr7IKgEAIgDAAMACgr7IKgEAIgDAAAA.',
Fo='Foxorcism:BAEANQADCgcIDgABNQAECgQIBgAIAAAAAA==.Foxrocket:BAEANQADCgIIAgABNQAECgQIBgAIAAAAAA==.Foxwu:BAEANQAECgQIBgAAAA==.',
Fr='Fries:BAECNQAFFH8cAAMJAAcKohtvAwApAgeODQAABgBGAHUNAAAFAFsAfw0AAAQAJACpDQAABgBcAFwNAAACAFsAXQ0AAAEABwAzDQAABAA0AAkABwqiG28DACkCB44NAAADAEYAdQ0AAAQAWwB/DQAAAwAkAKkNAAAGAFwAXA0AAAIAWwBdDQAAAQAHADMNAAADADQACgAECksUWgoANQEEjg0AAAMAJwB1DQAAAQBAAH8NAAABAAQAMw0AAAEADwA1AAQKfycAAwkACgr2I8UIAEwDAAkACgr2I8UIAEwDAAoAAQrkHSZMAFkAAAE1AAQKCAgRAAgAAAAA.',
Ga='Gardenweed:BAEANQAECgIIAwABNQAECgUIEAAIAAAAAA==.',
Gu='Guthynn:BAEBNQAECn8iAAMLAAoKVSVdAADSAwqODQAABABhAHUNAAAEAGIAfw0AAAUAYQCpDQAABgBeAFwNAAAEAGEAXQ0AAAIAXABlDQAAAgBaAKQNAAAFAGMAMw0AAAEAXAC5DQAAAQBeAAsACgpVJV0AANIDCo4NAAAEAGEAdQ0AAAQAYgB/DQAABQBhAKkNAAAGAF4AXA0AAAQAYQBdDQAAAgBcAGUNAAACAFoApA0AAAMAYwAzDQAAAQBcALkNAAABAF4ACQABCqIYV5oASgABpA0AAAIAPwAAAA==.',
Ha='Havècks:BAEANQAECgUIBQAAAA==.',
Ir='Irrogenia:BAEBNQAECn8iAAIMAAgKlR6oLACvAgiODQAABgBZAHUNAAAFAFkAfw0AAAUAVACpDQAABABZAFwNAAAFAFUAXQ0AAAQAPgBlDQAAAgA3ADMNAAADAEQADAAICpUeqCwArwIIjg0AAAYAWQB1DQAABQBZAH8NAAAFAFQAqQ0AAAQAWQBcDQAABQBVAF0NAAAEAD4AZQ0AAAIANwAzDQAAAwBEAAAA.',
Kc='Kcmndr:BAEANQAECgYICgABNQAFFAkJJwAFAJceAA==.',
La='Lariàs:BAECNQAFFH8bAAINAAcK0h8iAAC+AQeODQAABQBgAHUNAAAFAFEAfw0AAAQATQCpDQAABABdAFwNAAACAFQAXQ0AAAEAMwAzDQAABgBhAA0ABwrSHyIAAL4BB44NAAAFAGAAdQ0AAAUAUQB/DQAABABNAKkNAAAEAF0AXA0AAAIAVABdDQAAAQAzADMNAAAGAGEANQAECn88AAMNAAoKbiMqAwBxAwANAAoKbiMqAwBxAwAOAAUKgARsLgF3AAAAAA==.',
Li='Lidariel:BAEANQAECgYIBwABNQAECgoKHwAPAOUSAA==.Lidathra:BAEBNQAECn8fAAMPAAoK5RKgBgBlAQqODQAABABCAHUNAAACAA4Afw0AAAIAJQCpDQAABABKAFwNAAADADYAXQ0AAAQALgBlDQAABQBEAKQNAAADACEAMw0AAAMAJwC5DQAAAQAvAA8ACgrlEqAGAGUBCo4NAAADAEIAdQ0AAAIADgB/DQAAAgAlAKkNAAADAEoAXA0AAAMANgBdDQAABAAuAGUNAAAFAEQApA0AAAMAIQAzDQAAAgAnALkNAAABAC8AEAADClsVGy4ArgADjg0AAAEAMACpDQAAAQA8ADMNAAABACQAAAA=.Lidishi:BAEANQAECgQIBgABNQAECgoKHwAPAOUSAA==.Lilgup:BAECNQAFFH8JAAQPAAUKFxLRDgAXAQWODQAAAgASAHUNAAABABMAfw0AAAIAHwCpDQAAAgBWADMNAAACAEsADwAECikO0Q4AFwEEjg0AAAEAEgB1DQAAAQATAH8NAAACAB8AMw0AAAIASwAQAAIK3Q3mDAB9AAKODQAAAQA0AKkNAAABABIAEQABCmYWGw0APwABqQ0AAAEAOQA1AAQKfyIABA8ACQobGyMPALYCAA8ACQobGyMPALYCABAABArvHyskACABABEAAwq+I3ISAAsBAAAA.',
Lo='Lochru:BAEBNQAECn8iAAISAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgASAAkK+hkGCQC9AgmODQAABABNAHUNAAAFAFQAfw0AAAUAVwCpDQAABQBXAFwNAAAEAE0AXQ0AAAMAPABlDQAAAwApAKQNAAABACQAMw0AAAQAWgAAAA==.Lotide:BAEBNQAFFH8NAAMMAAcKbw4XBgAGAgeODQAAAgAEAHUNAAACACoAfw0AAAIAMwCpDQAAAgAZAFwNAAACADMAXQ0AAAEATgAzDQAAAgAEAAwABwpvDhcGAAYCB44NAAABAAQAdQ0AAAIAKgB/DQAAAgAzAKkNAAABABkAXA0AAAIAMwBdDQAAAQBOADMNAAABAAQAEwADCkcQZRsA5gADjg0AAAEAEwCpDQAAAQA/ADMNAAABADoAATUABRQFCAkADwAXEgA=.',
Mi='Migwangomage:BAECNQAFFH8GAAIFAAQKUxuqJwBLAQSODQAAAgBfAHUNAAABADMAfw0AAAEAAgCpDQAAAgA+AAUABApTG6onAEsBBI4NAAACAF8AdQ0AAAEAMwB/DQAAAQACAKkNAAACAD4ANQAECn8wAAIFAAoKgyJUAAALBAAFAAoKgyJUAAALBAABNQAFFAgIBQAEAI8bAA==.Mikmilk:BAEANQAECgYIEwABNQAECgoKMwAEAHcdAA==.Mikronos:BAECNQAFFH8NAAMUAAQKrRObAQDuAASODQAABQAuAHUNAAADACAAfw0AAAEAHgCpDQAABABIABMAAwqOE2EZAPcAA44NAAADAC0AdQ0AAAIAIACpDQAAAgBIABQABAoYEZsBAO4ABI4NAAACAC4AdQ0AAAEAHQB/DQAAAQAeAKkNAAACADcANQAECn8lAAMTAAkKUh5GKwDSAgATAAkKARxGKwDSAgAUAAUKBRaEHgB4AQABNQAECgoKMwAEAHcdAA==.',
['Mà']='Màsterofhunt:BAEANQAECgYIEgAAAA==.Màsterofwar:BAEANQAECgMIAwABNQAECgYIEgAIAAAAAA==.',
Ne='Neodefender:BAECNQAFFH8OAAIHAAUKlyGsBwDsAQWODQAABABDAHUNAAADAFkAfw0AAAIAYwCpDQAABABVADMNAAABAFgABwAFCpchrAcA7AEFjg0AAAQAQwB1DQAAAwBZAH8NAAACAGMAqQ0AAAQAVQAzDQAAAQBYADUABAp/LQACBwAKCmElnwAAtwMABwAKCmElnwAAtwMAAAA=.',
No='Nosram:BAEBNQAECn8xAAIVAAoKwx1GAQClAgqODQAACABYAHUNAAAHAGEAfw0AAAcAYwCpDQAABwBcAFwNAAAGAE4AXQ0AAAYAYQBlDQAABABJAKQNAAABAB0AMw0AAAIAXwC5DQAAAQA0ABUACgrDHUYBAKUCCo4NAAAIAFgAdQ0AAAcAYQB/DQAABwBjAKkNAAAHAFwAXA0AAAYATgBdDQAABgBhAGUNAAAEAEkApA0AAAEAHQAzDQAAAgBfALkNAAABADQAAAA=.',
Nu='Nubbz:BAECNQAFFH8QAAIUAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAAUAAYKAh1FAQAYAgaODQAAAwBKAHUNAAADAFoAfw0AAAIAGQCpDQAAAgBFAFwNAAABAD4AMw0AAAUAQAA1AAQKfz0AAxQACgoCJP0BAJMDABQACgoCJP0BAJMDABMAAQo/C/o2ATMAAAAA.',
Ny='Nyfaria:BAEBNQAECn84AAICAAoKxBAxBABSAQqODQAACQA1AHUNAAAIADgAfw0AAAcANwCpDQAACQAxAFwNAAAGADcAXQ0AAAQAGgBlDQAABgAvAKQNAAADACEAMw0AAAMAFQC5DQAAAQAVAAIACgrEEDEEAFIBCo4NAAAJADUAdQ0AAAgAOAB/DQAABwA3AKkNAAAJADEAXA0AAAYANwBdDQAABAAaAGUNAAAGAC8ApA0AAAMAIQAzDQAAAwAVALkNAAABABUAAAA=.',
Or='Orsp:BAECNQAFFH8ZAAMWAAYKeBYBCACQAQaODQAABgA+AHUNAAADADwAfw0AAAQAPgCpDQAABABFAFwNAAABACUAMw0AAAcAIgAWAAUKeBYBCACQAQWODQAABQA+AHUNAAACADwAqQ0AAAIARQBcDQAAAQAlADMNAAAEACIAFwAFCroMmBQAYQEFjg0AAAEALQB1DQAAAQACAH8NAAAEAEkAqQ0AAAIAGAAzDQAAAwAQADUABAp/OQADFgAKCuMiWAQAkwMAFgAKCuMiWAQAkwMAFwAJCkoTkWcA6AEAAAA=.Orspp:BAEBNQAECn8kAAMWAAkKuh6kGQCBAgmODQAABwBhAHUNAAAGAGEAfw0AAAYAXQCpDQAABQBdAFwNAAADAFUAXQ0AAAIAJQBlDQAAAgBJAKQNAAAEAEEAMw0AAAEAIwAWAAcKkR+kGQCBAgeODQAABwBhAHUNAAAEAGEAfw0AAAUAXQCpDQAAAwBdAFwNAAACAFUAXQ0AAAEAJQBlDQAAAgBJABcABwo+D7+JAHkBB3UNAAACAFIAfw0AAAEAKwCpDQAAAgAeAFwNAAABAAoAXQ0AAAEALQCkDQAABAAqADMNAAABABEAATUABRQGCBkAFgB4FgA=.',
Pa='Pakk:BAEBNQAECn8iAAIBAAcKVBqTNgAwAgeODQAABwBJAHUNAAAHAEoAfw0AAAYATACpDQAABQBGAFwNAAADAFMAXQ0AAAEAIgAzDQAABQBSAAEABwpUGpM2ADACB44NAAAHAEkAdQ0AAAcASgB/DQAABgBMAKkNAAAFAEYAXA0AAAMAUwBdDQAAAQAiADMNAAAFAFIAAAA=.Pandotides:BAEANQAECggIEQABNQABCgIIAgAIAAAAAA==.Papadefensve:BAEANQAECgIIAgAAAA==.',
Ra='Razamon:BAEBNQAECn8jAAMMAAoKpRYfMQCcAgqODQAABgBPAHUNAAAEADsAfw0AAAQAWwCpDQAABABiAFwNAAADAEEAXQ0AAAIAOQBlDQAABAAdAKQNAAADAA4AMw0AAAQARgC5DQAAAQANAAwACgqlFh8xAJwCCo4NAAAFAE8AdQ0AAAQAOwB/DQAABABbAKkNAAAEAGIAXA0AAAMAQQBdDQAAAgA5AGUNAAAEAB0ApA0AAAMADgAzDQAAAwBGALkNAAABAA0AEwACCuAH1JAAOAACjg0AAAEAFAAzDQAAAQAYAAAA.',
Re='Recurse:BAEANQADCggICAABNQAFFAcIDwAYAI0OAA==.',
Ru='Runehaven:BAEANQADCggICAABNQAECgkJHwAZAHogAA==.',
Sa='Sairal:BAEANQAECgQICQABNQAFFAcIGwANANIfAA==.Sargala:BAEANQAECgQIBgAAAA==.',
Sc='Scootybooty:BAEANQAECgQICwABNQAECgkJFAAWAN4QAA==.Scootypriest:BAEBNQAECn8UAAIWAAkK3hB/JgD6AQmODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvADMNAAADADUAuQ0AAAEAGAAWAAkK3hB/JgD6AQmODQAABABBAHUNAAADAC8Afw0AAAMAUQCpDQAAAwBCAFwNAAABACsAXQ0AAAEABwBlDQAAAQAvADMNAAADADUAuQ0AAAEAGAAAAA==.',
Sm='Smitehaven:BAEBNQAECn8fAAIZAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAZAAkKeiD0DADMAgmODQAABgBTAHUNAAAEAFkAfw0AAAQAXgCpDQAABABbAFwNAAAEAFwAXQ0AAAMAVABlDQAAAgBQADMNAAADAEsAuQ0AAAEAOwAAAA==.',
Tc='Tchoff:BAEANQADCgUIBQABNQAFFAcIHQAOAPQgAA==.',
Th='Thez:BAEANQAECgUICwABNQAECgkJKgANAFMiAA==.Thezadin:BAEANQAECgQIBAABNQAECgkJKgANAFMiAA==.Thezdin:BAEBNQAECn8qAAINAAkKUyJIAwBsAwmODQAABwBXAHUNAAAEAF8Afw0AAAQAXgCpDQAABQBiAFwNAAAEAFwAXQ0AAAUAWgBlDQAABQBRAKQNAAADAEUAMw0AAAUAUQANAAkKUyJIAwBsAwmODQAABwBXAHUNAAAEAF8Afw0AAAQAXgCpDQAABQBiAFwNAAAEAFwAXQ0AAAUAWgBlDQAABQBRAKQNAAADAEUAMw0AAAUAUQAAAA==.',
Ve='Velohm:BAEANQAECgMIBgAAAA==.',
Wi='Wildbless:BAECNQAFFH8ZAAIZAAcKggkPBACiAQeODQAABgBCAHUNAAAEAAsAfw0AAAQAHgCpDQAABAAjAFwNAAACAAQAXQ0AAAEAAgAzDQAABAAWABkABwqCCQ8EAKIBB44NAAAGAEIAdQ0AAAQACwB/DQAABAAeAKkNAAAEACMAXA0AAAIABABdDQAAAQACADMNAAAEABYANQAECn8tAAIZAAoKnxyZDwCjAgAZAAoKnxyZDwCjAgABNQAECgQICgAIAAAAAA==.Wildform:BAEANQAECgIIAwABNQAECgQICgAIAAAAAA==.Wildkill:BAEBNQAECn8WAAIaAAcKjiMyUwB3AgeODQAABABjAHUNAAADAF4Afw0AAAMAOwCpDQAAAwBTAFwNAAACAEwAZQ0AAAMAYwCkDQAABABcABoABwqOIzJTAHcCB44NAAAEAGMAdQ0AAAMAXgB/DQAAAwA7AKkNAAADAFMAXA0AAAIATABlDQAAAwBjAKQNAAAEAFwAATUABAoECAoACAAAAAA=.Wildshield:BAEANQAECgQICgAAAA==.',
Wr='Wrècks:BAEANQAECgYICAABNQAECgUIBQAIAAAAAA==.Wrèckstorm:BAEBNQAECn80AAMUAAoKHyFJBgAhAwqODQAACQBbAHUNAAAGAFkAfw0AAAYAWQCpDQAABwBFAFwNAAAFAE4AXQ0AAAUATwBlDQAABQBcAKQNAAADAFIAMw0AAAUASAC5DQAAAQBfABQACgofIUkGACEDCo4NAAAJAFsAdQ0AAAUAWQB/DQAABQBZAKkNAAAGAEUAXA0AAAMATgBdDQAABQBPAGUNAAAFAFwApA0AAAMAUgAzDQAABQBIALkNAAABAF8AEwAECg8aB7UAKAEEdQ0AAAEAPAB/DQAAAQBHAKkNAAABAD4AXA0AAAIATAABNQAECgUIBQAIAAAAAA==.',
Zo='Zoe:BAEANQAECgQICgAAAA==.Zogle:BAECNQAFFH8WAAIBAAcKRhadBAA0AgeODQAABQBOAHUNAAADAB0Afw0AAAMAOwCpDQAABQBPAFwNAAACADwAXQ0AAAEAJAAzDQAAAwBYAAEABwpGFp0EADQCB44NAAAFAE4AdQ0AAAMAHQB/DQAAAwA7AKkNAAAFAE8AXA0AAAIAPABdDQAAAQAkADMNAAADAFgANQAECn8pAAIBAAoKXCM3CwBZAwABAAoKXCM3CwBZAwABNQAECgQICgAIAAAAAA==.',
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
