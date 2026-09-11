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

local lookup = {'Rogue-Assassination','Monk-Windwalker','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Mage-Arcane','Paladin-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Evoker-Preservation','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Devourer','Monk-Brewmaster','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Druid-Restoration','Druid-Balance','DemonHunter-Havoc',}
local provider = {region='US',realm='Frostmourne',name='US',type='subscribers',zone=53,date='2026-09-08',data={Ab='Abstinate:BAECNQAFFIEGAAIBAAUJ0RcgAADnAQWODQAAAgA7AHUNAAABAD8Afw0AAAEAMQCpDQAAAQAnADMNAAABAF0AAQAFCdEXIAAA5wEFjg0AAAIAOwB1DQAAAQA/AH8NAAABADEAqQ0AAAEAJwAzDQAAAQBdADUABAqBGQACAQAJCfwkkAAAtgMAAQAJCfwkkAAAtgMAAAA=.',
Ae='Aenospin:BAEBNQAECoEZAAICAAkJ1SDpAgBOAwmODQAAAwBZAHUNAAADAEYAfw0AAAMAVQCpDQAAAwBNAFwNAAADAGAAXQ0AAAMAVQBlDQAAAgBOAKQNAAACAE8AMw0AAAMAXAACAAkJ1SDpAgBOAwmODQAAAwBZAHUNAAADAEYAfw0AAAMAVQCpDQAAAwBNAFwNAAADAGAAXQ0AAAMAVQBlDQAAAgBOAKQNAAACAE8AMw0AAAMAXAAAAA==.',
Af='Afflictweave:BAEANQAECgYICgAAAA==.',
As='Assbringger:BAEANQADCgUIBQABNQAECgQIDAADAAAAAA==.Asukakira:BAEANQAECggIEgAAAA==.',
Au='Augtisim:BAEBNQAECoEZAAMEAAkJYSLWAABOAwmODQAAAwBhAHUNAAADAF4Afw0AAAMAYgCpDQAAAwBgAFwNAAADAFgAXQ0AAAMAXABlDQAAAgBRAKQNAAACAC8AMw0AAAMAXgAEAAkJYSLWAABOAwmODQAAAwBhAHUNAAACAF4Afw0AAAIAYgCpDQAAAwBgAFwNAAACAFgAXQ0AAAIAXABlDQAAAgBRAKQNAAABAC8AMw0AAAEAXgAFAAYJsBTGDgCuAQZ1DQAAAQBIAH8NAAABAEgAXA0AAAEAJABdDQAAAQAvAKQNAAABABMAMw0AAAIARgAAAA==.',
Av='Avaelyne:BAEANQAECgcIDQAAAA==.',
Az='Azzarage:BAEANQADCggIDgABNQAECgkJFwAGAFggAA==.Azzaraze:BAEBNQAECoEXAAIGAAkJWCATDwBEAwmODQAAAwA/AHUNAAADAFsAfw0AAAMAXgCpDQAAAwBAAFwNAAADAF4AXQ0AAAIATgBlDQAAAgBWAKQNAAABAEkAMw0AAAMAYwAGAAkJWCATDwBEAwmODQAAAwA/AHUNAAADAFsAfw0AAAMAXgCpDQAAAwBAAFwNAAADAF4AXQ0AAAIATgBlDQAAAgBWAKQNAAABAEkAMw0AAAMAYwAAAA==.',
Ba='Barakoshama:BAEANQAECgEIAgABNQAFFAUIBgAHADAeAA==.',
Be='Bertism:BAEANQAFFAIIAgAAAA==.',
Bl='Blupakhet:BAEBNQAECoEWAAMIAAkJoxvUDwBSAgmODQAAAwBAAHUNAAADAEwAfw0AAAMAOgCpDQAAAwBQAFwNAAADAFwAXQ0AAAIASQBlDQAAAgBEAKQNAAABADgAMw0AAAIAQgAIAAgJ9xfUDwBSAgiODQAAAQBAAHUNAAABAEQAfw0AAAEAKQCpDQAAAQA3AF0NAAACAEkAZQ0AAAEAQACkDQAAAQA4ADMNAAACAEIACQAGCX0ZmTQAvQEGjg0AAAIADwB1DQAAAgBMAH8NAAACADoAqQ0AAAIAUABcDQAAAwBcAGUNAAABAEQAATUAAQoDCAMAAwAAAAA=.',
Ca='Calonclaw:BAEANQADCgYICwABNQAECgkJHgAJAGEmAA==.Calzurv:BAEBNQAECoEeAAQJAAkJYSZVAADtAwmODQAABABjAHUNAAAEAGMAfw0AAAQAZACpDQAABABhAFwNAAAEAGMAXQ0AAAMAYgBlDQAAAgBjAKQNAAABAFgAMw0AAAQAYwAJAAkJYSZVAADtAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAZACpDQAAAwBhAFwNAAAEAGMAXQ0AAAEAYgBlDQAAAgBjAKQNAAABAFgAMw0AAAMAYwAKAAUJvB2QAwCYAQV1DQAAAQBjAH8NAAABAGAAqQ0AAAEAYQBdDQAAAQAEADMNAAABAFIACAACCf8hBS0AmwACjg0AAAEAUgBdDQAAAQBbAAAA.Capzíen:BAEANQAECgcIDQAAAA==.',
Ce='Ceruuledge:BAEANQAECgUIDQABNQAECgkJFwAGAIAfAA==.',
Cr='Craftyp:BAEANQAECggIAQAAAA==.Crowblast:BAEANQADCgUIDQABNQAECgQIBQADAAAAAA==.Crowburst:BAEANQADCgYICQABNQAECgQIBQADAAAAAA==.Crowchaos:BAEANQADCgMIAQABNQAECgQIBQADAAAAAA==.Crowshot:BAEANQAECgQIBQAAAA==.Crowshott:BAEANQAECgQIAQABNQAECgQIBQADAAAAAA==.Crunchforce:BAEANQAECgUICQAAAA==.',
Di='Digitaldj:BAEANQADCggIDgAAAA==.',
Du='Dubsx:BAEANQAECgYICAABNQAFFAUICQALAPQTAA==.',
Dw='Dwak:BAEANQAECggICwABNQAECgkJHAAFAK4fAA==.Dwakakiwi:BAEBNQAECoEcAAIFAAkJrh+8AgBBAwmODQAABQBhAHUNAAADAFsAfw0AAAEAVwCpDQAABQBhAFwNAAACACUAXQ0AAAEAWABlDQAAAwA6AKQNAAAEAEkAMw0AAAQAYQAFAAkJrh+8AgBBAwmODQAABQBhAHUNAAADAFsAfw0AAAEAVwCpDQAABQBhAFwNAAACACUAXQ0AAAEAWABlDQAAAwA6AKQNAAAEAEkAMw0AAAQAYQAAAA==.Dwarfhands:BAEANQAECgcIEgAAAA==.',
Ea='Eatsrats:BAEBNQAECoEcAAMFAAgJzR1gCABbAgiODQAABABDAHUNAAAEAFQAfw0AAAQAVwCpDQAABABEAFwNAAACAF8AXQ0AAAQAUwBlDQAAAwA8ADMNAAADAD0ABQAHCbMcYAgAWwIHjg0AAAQAQwB1DQAAAwBUAH8NAAADAFcAqQ0AAAMARABdDQAAAwBTAGUNAAADADwAMw0AAAEAPQAMAAYJGQOKGgD4AAZ1DQAAAQAOAH8NAAABAAYAqQ0AAAEACQBcDQAAAgADAF0NAAABAAEAMw0AAAIACgAAAA==.',
Ep='Epidestro:BAEANQAFFAMIAgAAAA==.',
Fa='Faelaelae:BAECNQAFFIEFAAINAAQJ3grJAQA3AQSODQAAAgBEAHUNAAABAB8Afw0AAAEACQCpDQAAAQAAAA0ABAneCskBADcBBI4NAAACAEQAdQ0AAAEAHwB/DQAAAQAJAKkNAAABAAAANQAECoEZAAMNAAkJFCI+AgCMAwANAAkJFCI+AgCMAwAOAAEJZwbtYgBHAAAAAA==.',
Fj='Fj:BAEANQADCggIFwABNQAFFAIIAgADAAAAAA==.Fjz:BAEANQAFFAIIAgAAAA==.',
Fl='Flapzien:BAEANQADCgYICQABNQAECgcIDQADAAAAAA==.Flayorius:BAEANQAECgUIBgAAAA==.Floorqt:BAEANQAECggIDgABNQAFFAYIDAAEAEccAA==.Flowito:BAEBNQAECoEZAAMPAAkJPiWuDQAnAgmODQAAAwBiAHUNAAADAF8Afw0AAAMAYwCpDQAAAwBiAFwNAAADAF4AXQ0AAAMAYQBlDQAAAgBaAKQNAAACAFUAMw0AAAMAYwAPAAUJ+CWuDQAnAgWODQAAAwBiAHUNAAADAF8Afw0AAAMAYwBcDQAAAwBeADMNAAADAGMAAQAECVUkkQ8AowEEqQ0AAAMAYgBdDQAAAwBhAGUNAAACAFoApA0AAAIAVQAAAA==.Fluffyst:BAEANQAECgcIDQABNQAECgkJGAAQAMccAA==.Fluffyswl:BAEBNQAECoEYAAQQAAkJxxy/BQCEAgmODQAAAwBcAHUNAAACAF4Afw0AAAMATwCpDQAAAwBWAFwNAAADAF4AXQ0AAAMAVwBlDQAAAgAYAKQNAAACABoAMw0AAAMATAAQAAgJUhm/BQCEAgiODQAAAQA3AHUNAAACAF4Afw0AAAEAPgCpDQAAAwBWAFwNAAABADYAXQ0AAAMAVwCkDQAAAgAaADMNAAABADIAEQAFCS0bZC4ApwEFjg0AAAEAVgB/DQAAAgBPAFwNAAACAF4AZQ0AAAIAGAAzDQAAAQA+ABIAAgkWIVAKAKsAAo4NAAABAFwAMw0AAAEATAAAAA==.',
Ga='Gardevoiir:BAEBNQAECoEXAAIGAAkJgB+/FQAVAwmODQAABABXAHUNAAADAFkAfw0AAAMAWACpDQAAAwBdAFwNAAACAFgAXQ0AAAIAUwBlDQAAAgA9AKQNAAABACQAMw0AAAMAXwAGAAkJgB+/FQAVAwmODQAABABXAHUNAAADAFkAfw0AAAMAWACpDQAAAwBdAFwNAAACAFgAXQ0AAAIAUwBlDQAAAgA9AKQNAAABACQAMw0AAAMAXwAAAA==.Garrydrood:BAEANQAECgMIBAABNQAECgYICwADAAAAAA==.Garrylock:BAEANQADCgYIBgABNQAECgYICwADAAAAAA==.Gayvraeladin:BAEANQAECggICAABNQAFFAYICgATAM8QAA==.',
Gd='Gdubs:BAECNQAFFIEJAAILAAUJ9BNNAAC6AQWODQAAAgAlAHUNAAACACMAfw0AAAEAPwCpDQAAAgBGADMNAAACADAACwAFCfQTTQAAugEFjg0AAAIAJQB1DQAAAgAjAH8NAAABAD8AqQ0AAAIARgAzDQAAAgAwADUABAqBFQADCwAJCfEiPwUAWwMACwAJCfEiPwUAWwMAFAABCV0gOyoAYQAAAAA=.',
Gh='Ghostwolf:BAEANQADCgcIDgAAAA==.',
Go='Gowrymage:BAEANQAECgYICwAAAA==.',
Gr='Grimfleur:BAEANQAECgUIBQAAAA==.',
Ha='Hatedspec:BAECNQAFFIEMAAMEAAYJRxw4AAASAgaODQAAAwBiAHUNAAACAF8Afw0AAAIARQCpDQAAAgBXAFwNAAACAFIAXQ0AAAEAAQAEAAUJhhw4AAASAgWODQAAAQBiAHUNAAABAF8AqQ0AAAEAVwBcDQAAAgBSAF0NAAABAAEABQAECYgVHwEAYAEEjg0AAAIASwB1DQAAAQA9AH8NAAACAEUAqQ0AAAEADQA1AAQKgRoAAwQACQnMJT4AALQDAAQACQnEJT4AALQDAAUACAkeH80FAL0CAAAA.',
He='Herb:BAEANQAECgcIDgAAAQ==.Heymandude:BAEBNQAECoEXAAIVAAkJICJcAwBwAwmODQAAAwBgAHUNAAADAF0Afw0AAAMAYQCpDQAAAwBKAFwNAAADAGEAXQ0AAAMASgBlDQAAAgBVAKQNAAACAFIAMw0AAAEAVAAVAAkJICJcAwBwAwmODQAAAwBgAHUNAAADAF0Afw0AAAMAYQCpDQAAAwBKAFwNAAADAGEAXQ0AAAMASgBlDQAAAgBVAKQNAAACAFIAMw0AAAEAVAAAAA==.',
Il='Ilikefeet:BAEANQADCgYIBgAAAA==.Illusionqaq:BAEANQAFFAEIAQAAAA==.',
Ja='Jackowin:BAEANQAECgcIDQABNQAFFAQIBQANAN4KAA==.Jackpotjimmy:BAEBNQAECoEsAAIWAAkJ4AcRCADBAQmODQAABgARAHUNAAAGABQAfw0AAAYADwCpDQAABwAPAFwNAAAGABQAXQ0AAAQAIgBlDQAAAgAOAKQNAAACAAcAMw0AAAUAIgAWAAkJ4AcRCADBAQmODQAABgARAHUNAAAGABQAfw0AAAYADwCpDQAABwAPAFwNAAAGABQAXQ0AAAQAIgBlDQAAAgAOAKQNAAACAAcAMw0AAAUAIgAAAA==.Jaysplosion:BAEBNQAECoEXAAMGAAgJGiNHEwAmAwiODQAAAwBhAHUNAAADAGEAfw0AAAMAWgCpDQAAAwBbAFwNAAADAGAAXQ0AAAMAXABlDQAAAgA6ADMNAAADAF0ABgAICf0iRxMAJgMIjg0AAAMAYQB1DQAAAQBfAH8NAAADAFoAqQ0AAAMAWwBcDQAAAwBgAF0NAAACAFwAZQ0AAAIAOgAzDQAAAwBdABcAAgm5I4wOALYAAnUNAAACAGEAXQ0AAAEAVQAAAA==.',
Je='Jeffm:BAEANQAFFAEIAgAAAA==.',
Ju='Jujuza:BAEANQAFFAEIAQAAAA==.',
Ka='Karmafuge:BAEANQADCgUIBQABNQAECgcIDQADAAAAAA==.Kaòri:BAEANQAECgMIBAABNQAFFAYIDAAEAEccAA==.',
Ki='Killchain:BAEBNQAECoEcAAIGAAkJtB5WDgBKAwmODQAABABZAHUNAAAEAF0Afw0AAAQAYgCpDQAABABfAFwNAAAEADwAXQ0AAAIAQwBlDQAAAgA6AKQNAAABAC8AMw0AAAMAXwAGAAkJtB5WDgBKAwmODQAABABZAHUNAAAEAF0Afw0AAAQAYgCpDQAABABfAFwNAAAEADwAXQ0AAAIAQwBlDQAAAgA6AKQNAAABAC8AMw0AAAMAXwABNQAECgkJHAAGALQeAA==.Killchainwar:BAEANQADCgUIBQABNQAECgkJHAAGALQeAA==.',
['Kì']='Kìnetyk:BAECNQAFFIEIAAIYAAUJNA0jAQCfAQWODQAAAwAzAHUNAAABADwAfw0AAAEAHACpDQAAAgAJADMNAAABABIAGAAFCTQNIwEAnwEFjg0AAAMAMwB1DQAAAQA8AH8NAAABABwAqQ0AAAIACQAzDQAAAQASADUABAqBGgACGAAJCcYfbAQAewMAGAAJCcYfbAQAewMAAAA=.',
La='Lambourne:BAEANQAECgcIEAAAAA==.Lambsohot:BAEANQAECgIIAgABNQAECgcIEAADAAAAAA==.',
Li='Lionyr:BAEANQAFFAEIAwABNQAFFAYICgATAM8QAA==.Lisael:BAEANQAFFAIIBAABNQAFFAYICgATAM8QAA==.',
Ll='Llöcklesnar:BAEANQAECgIIAgAAAA==.',
Lo='Loquewl:BAEANQAECgcIDAAAAA==.',
Lu='Luxmalli:BAECNQAFFIEGAAIHAAUJMB7RAAD2AQWODQAAAgBbAHUNAAABAE0Afw0AAAEARgCpDQAAAQBfADMNAAABADQABwAFCTAe0QAA9gEFjg0AAAIAWwB1DQAAAQBNAH8NAAABAEYAqQ0AAAEAXwAzDQAAAQA0ADUABAqBFwACBwAJCTklZAAA3gMABwAJCTklZAAA3gMAAAA=.',
Ma='Madorimage:BAEBNQAECoEbAAIGAAkJVyDVDgBGAwmODQAAAwBdAHUNAAADAFcAfw0AAAMAWwCpDQAAAwBiAFwNAAADAFUAXQ0AAAMAWQBlDQAABAA5AKQNAAACACwAMw0AAAMAYAAGAAkJVyDVDgBGAwmODQAAAwBdAHUNAAADAFcAfw0AAAMAWwCpDQAAAwBiAFwNAAADAFUAXQ0AAAMAWQBlDQAABAA5AKQNAAACACwAMw0AAAMAYAAAAA==.Madorimagi:BAEANQAECgIIAgABNQAECgkJGwAGAFcgAA==.Malpractis:BAEBNQAFFIENAAINAAYJ2hkkAABmAgaODQAAAwBfAHUNAAACADEAfw0AAAIAPACpDQAAAwBbAFwNAAABABUAMw0AAAIATgANAAYJ2hkkAABmAgaODQAAAwBfAHUNAAACADEAfw0AAAIAPACpDQAAAwBbAFwNAAABABUAMw0AAAIATgAAAA==.Malzhuul:BAEBNQAECoEUAAMYAAgJKBd5GgBCAgiODQAAAwBHAHUNAAADAFkAfw0AAAIASgCpDQAAAwBdAFwNAAADADwAXQ0AAAIACwBlDQAAAwA2AKQNAAABABIAGAAHCdMZeRoAQgIHjg0AAAMARwB1DQAAAwBZAH8NAAACAEoAqQ0AAAMAXQBcDQAAAgA8AGUNAAADADYApA0AAAEAEgAZAAIJLwjteABxAAJcDQAAAQAlAF0NAAACAAQAATUABRQGCA0ADQDaGQA=.',
Mi='Minglock:BAEANQAECgQICAAAAA==.Mingmonk:BAEANQAECgMIBQABNQAECgQICAADAAAAAA==.Mingshaman:BAEANQADCgYIBgABNQAECgQICAADAAAAAA==.',
Mu='Multurion:BAEANQADCgcIDQABNQAECgYIDAADAAAAAA==.',
My='Mybrokenmage:BAEANQADCgQIBAABNQAECgcIEAADAAAAAA==.',
Ni='Niph:BAEANQABCgMIAgAAAQ==.',
Pa='Parobola:BAEANQAECgcIDgAAAA==.Paroböla:BAEANQADCggIDQABNQAECgcIDgADAAAAAA==.',
Pe='Peacuc:BAEANQADCgQIBgABNQAECgIIAgADAAAAAA==.',
Pi='Piyoz:BAEANQAECgQIBAABNQAECggIEgADAAAAAA==.',
Ra='Raellyn:BAECNQAFFIELAAIaAAYJChoeAAA5AgaODQAAAgBLAHUNAAACAEcAfw0AAAIAUgCpDQAAAgBFAFwNAAABACkAMw0AAAIAOwAaAAYJChoeAAA5AgaODQAAAgBLAHUNAAACAEcAfw0AAAIAUgCpDQAAAgBFAFwNAAABACkAMw0AAAIAOwA1AAQKgRgAAxsACQlZG3YSAHsCABsACAnLGnYSAHsCABoACQniETQLACUCAAAA.Raevoke:BAEANQADCggICAABNQAFFAYICwAaAAoaAA==.Rainons:BAEANQAECgYIBgABNQAFFAYICQAHACceAA==.Rainonsh:BAEANQAECgYICgABNQAFFAYICQAHACceAA==.Rainonsz:BAEANQAFFAIIAgABNQAFFAYICQAHACceAA==.Ramm:BAECNQAFFIEJAAMRAAYJVyG+AACgAQaODQAAAgBYAHUNAAACAFwAfw0AAAEAWgCpDQAAAgBiAFwNAAABAC0AMw0AAAEAYAARAAQJVh++AACgAQSODQAAAgBYAH8NAAABAFoAXA0AAAEALQAzDQAAAQBgABAAAglZJTsBAOMAAnUNAAACAFwAqQ0AAAIAYgA1AAQKgRsABBEACQkjJsYBAG8DABEACAnkJcYBAG8DABAACAn4H5ACAAADABIAAQn3Jb8NAG8AAAAA.Rammtwo:BAEANQAECgcIDAABNQAFFAYICQARAFchAA==.',
Rh='Rhaynen:BAECNQAFFIEJAAIHAAYJJx5OAABcAgaODQAAAgA9AHUNAAACAFAAfw0AAAEAXgCpDQAAAgAzAFwNAAABAGIAMw0AAAEATAAHAAYJJx5OAABcAgaODQAAAgA9AHUNAAACAFAAfw0AAAEAXgCpDQAAAgAzAFwNAAABAGIAMw0AAAEATAA1AAQKgRsAAgcACQmKJW0AANsDAAcACQmKJW0AANsDAAAA.',
Ri='Riyria:BAEANQAECgcIEQAAAA==.',
Ro='Rosaura:BAEBNQAECoEiAAMBAAkJUSV9AAC/AwmODQAABABiAHUNAAAEAGMAfw0AAAQAYQCpDQAABABhAFwNAAAEAGIAXQ0AAAQAXABlDQAAAwBfAKQNAAABAFQAMw0AAAYAXwABAAkJUSV9AAC/AwmODQAAAwBiAHUNAAADAGMAfw0AAAQAYQCpDQAABABhAFwNAAAEAGIAXQ0AAAQAXABlDQAAAwBfAKQNAAABAFQAMw0AAAQAXwAPAAMJaxYqJQDPAAOODQAAAQA4AHUNAAABAEUAMw0AAAIALgAAAA==.',
Sa='Saburac:BAEANQAECgEIAwABNQAECgcIDQADAAAAAA==.',
Sc='Screampies:BAECNQAFFIEFAAMOAAIJGg9vBwCXAAKODQAABAAvAKkNAAABAB4ADgACCRoPbwcAlwACjg0AAAMALwCpDQAAAQAeAA0AAQmOARwHAEMAAY4NAAABAAMANQAECoEZAAMOAAkJIBzBCADlAgAOAAkJIBzBCADlAgANAAEJ0gXsMgBNAAABNQAFFAYICwAaAAoaAA==.',
Si='Sileighty:BAEANQAECgEIAQABNQAECgcIEAADAAAAAA==.',
So='Sorryrennon:BAEANQAECgcIEAAAAA==.',
Sp='Speedaddict:BAEANQAECgcIEAAAAA==.',
St='Stmz:BAEANQAECgYIBwABNQAFFAMIBAADAAAAAA==.Stmzeh:BAEANQAECgEIAQABNQAFFAMIBAADAAAAAA==.Straxeh:BAEANQAFFAMIBAAAAA==.',
Su='Suprised:BAEANQAECggIAQAAAA==.',
To='Tonkotsu:BAEBNQAFFIEKAAITAAYJzxD4AADeAQaODQAAAgBTAHUNAAABABkAfw0AAAIAMQCpDQAAAgAaAFwNAAABAA8AMw0AAAIAOAATAAYJzxD4AADeAQaODQAAAgBTAHUNAAABABkAfw0AAAIAMQCpDQAAAgAaAFwNAAABAA8AMw0AAAIAOAAAAA==.Toxiyks:BAEANQAECgQIDAAAAA==.',
Tr='Treedubs:BAEANQAECgIIAQABNQAFFAUICQALAPQTAA==.',
Um='Umbrreon:BAEANQADCgYIBgABNQAECgkJFwAGAIAfAA==.',
Va='Vaath:BAEBNQAECoEWAAIcAAkJAhaWCACmAgmODQAAAwBQAHUNAAADAE8Afw0AAAMATwCpDQAAAwA6AFwNAAACADYAXQ0AAAMAPgBlDQAAAgAVAKQNAAABAB8AMw0AAAIAJwAcAAkJAhaWCACmAgmODQAAAwBQAHUNAAADAE8Afw0AAAMATwCpDQAAAwA6AFwNAAACADYAXQ0AAAMAPgBlDQAAAgAVAKQNAAABAB8AMw0AAAIAJwAAAA==.Vailario:BAEANQAECgIIAgABNQAECgkJFwAGAIAfAA==.',
Wa='Wakakyrri:BAEANQAECgQICAABNQAECgkJHAAFAK4fAA==.Warknatty:BAEANQAECggIAQAAAA==.',
We='Weewees:BAEANQAECgYIDAABNQAECgkJFwAVACAiAA==.',
Xh='Xheroleaker:BAEANQAECgQIBwAAAA==.',
Xi='Xiaotèézy:BAEANQADCgYIBgABNQAECgkJGQAPAEQeAA==.Xiaotéezy:BAEANQAECgUIBQABNQAECgkJGQAPAEQeAA==.Xiaotëëzy:BAEBNQAECoEZAAMPAAkJRB6hBQDgAgmODQAAAwBbAHUNAAADAF8Afw0AAAMAWQCpDQAAAwBVAFwNAAADAD0AXQ0AAAMAQwBlDQAAAgBLAKQNAAABADAAMw0AAAQAUwAPAAgJsR+hBQDgAgiODQAAAwBbAHUNAAADAF8Afw0AAAMAWQCpDQAAAwBVAFwNAAADAD0AXQ0AAAMAQwBlDQAAAgBLADMNAAAEAFMAAQABCdsSAAAAAAABpA0AAAEAMAAAAA==.',
Yi='Yinmaester:BAEANQAECgMIAwAAAA==.',
Za='Zayge:BAEBNQAECoEYAAIGAAkJcCLzCAB4AwmODQAAAwBjAHUNAAADAFsAfw0AAAMAYwCpDQAAAwBhAFwNAAADAFsAXQ0AAAMAUQBlDQAAAgBWAKQNAAABADMAMw0AAAMAYAAGAAkJcCLzCAB4AwmODQAAAwBjAHUNAAADAFsAfw0AAAMAYwCpDQAAAwBhAFwNAAADAFsAXQ0AAAMAUQBlDQAAAgBWAKQNAAABADMAMw0AAAMAYAAAAA==.',
Zo='Zorthargirl:BAEANQAECggIAgAAAA==.',
['Öv']='Överdösë:BAEANQAECgMIAwABNQAECgcIEAADAAAAAA==.',
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
