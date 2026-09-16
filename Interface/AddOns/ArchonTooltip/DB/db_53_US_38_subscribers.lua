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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Unknown-Unknown','Mage-Arcane','Monk-Brewmaster','Priest-Holy','Monk-Mistweaver','Rogue-Outlaw','Rogue-Assassination','Evoker-Augmentation','Warlock-Demonology','Shaman-Elemental','Warlock-Destruction','Hunter-BeastMastery','Druid-Balance','Warrior-Arms','Warlock-Affliction','DeathKnight-Blood','Mage-Fire','Mage-Frost','DeathKnight-Unholy',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=53,date='2026-09-15',data={Ad='Addex:BAEBNQAECoEeAAQBAAkJ6BUcGwCIAgmODQAABgAyAHUNAAAEACIAfw0AAAQAJwCpDQAABAAyAFwNAAAEADEAXQ0AAAIASwBlDQAAAwBRAKQNAAABAFEAMw0AAAIAKQABAAkJ6BUcGwCIAgmODQAAAwAyAHUNAAABACIAfw0AAAEAJwCpDQAAAQAyAFwNAAABADEAXQ0AAAEASwBlDQAAAwBRAKQNAAABAFEAMw0AAAIAKQACAAYJaRpiRADmAQaODQAAAQA8AHUNAAABAFEAfw0AAAEANACpDQAAAQBUAFwNAAABAEUAXQ0AAAEAOQADAAUJ2Bq3FQB0AQWODQAAAgBRAHUNAAACAEwAfw0AAAIAMwCpDQAAAgBHAFwNAAACAD4AATUABRQHCBIABABFIAA=.',
Am='Ambient:BAECNQAFFIESAAIEAAcJRSA/AACoAgeODQAABABkAHUNAAADAFkAfw0AAAIARwCpDQAAAwBZAFwNAAACADsAXQ0AAAEARgAzDQAAAwBhAAQABwlFID8AAKgCB44NAAAEAGQAdQ0AAAMAWQB/DQAAAgBHAKkNAAADAFkAXA0AAAIAOwBdDQAAAQBGADMNAAADAGEANQAECoEYAAIEAAkJhCL7BQAAAwAEAAkJhCL7BQAAAwAAAA==.',
Av='Avarat:BAEBNQAECoEaAAIFAAkJEhqDAwDPAgmODQAABABTAHUNAAADAEEAfw0AAAQASwCpDQAABABSAFwNAAACAEkAXQ0AAAIAQABlDQAAAgA5AKQNAAACABwAMw0AAAMARQAFAAkJEhqDAwDPAgmODQAABABTAHUNAAADAEEAfw0AAAQASwCpDQAABABSAFwNAAACAEkAXQ0AAAIAQABlDQAAAgA5AKQNAAACABwAMw0AAAMARQABNQAECgcIDQAGAAAAAA==.',
Az='Azenia:BAEANQAECgYIEAAAAA==.',
Ba='Banddaid:BAEANQADCgcIFAABNQAECgkJGQAHAIsfAA==.',
Bi='Bigchubber:BAEANQAECgUIBwAAAA==.',
Br='Briéè:BAEANQADCgEIAQAAAA==.Bruwon:BAEBNQAFFIENAAIIAAYJ2Bs1AAAhAgaODQAAAwBJAHUNAAACAFEAfw0AAAIASQCpDQAAAwBbAFwNAAABABkAMw0AAAIAUwAIAAYJ2Bs1AAAhAgaODQAAAwBJAHUNAAACAFEAfw0AAAIASQCpDQAAAwBbAFwNAAABABkAMw0AAAIAUwAAAA==.',
Ch='Charzie:BAEANQAECgEIAQABNQAFFAYIDQAIANgbAA==.',
Da='Danitsia:BAEANQAECgIIAgAAAA==.',
De='Deathkleburg:BAEANQAECggIEQAAAA==.Delacoûr:BAEANQAECgIIBAABNQAFFAUICwAJAOoZAA==.',
Do='Doorstuck:BAEANQADCggICAABNQAECgcIDQAGAAAAAA==.',
Ea='Eatsrocks:BAEANQADCgcIBwABNQAECgYIEAAGAAAAAA==.',
Fe='Fentweaver:BAECNQAFFIEFAAIKAAMJ7QxyAgD5AAOODQAAAgAZAHUNAAABABgAqQ0AAAIAMgAKAAMJ7QxyAgD5AAOODQAAAgAZAHUNAAABABgAqQ0AAAIAMgA1AAQKgSEAAgoACQnbIToCAF8DAAoACQnbIToCAF8DAAAA.',
Fu='Fuddly:BAEANQAECgEIAQABNQAECgUIBwAGAAAAAA==.',
Gr='Gronknose:BAECNQAFFIEKAAILAAUJhhYxAADJAQWODQAAAwBcAHUNAAACAEcAfw0AAAIABgCpDQAAAgBAADMNAAABADQACwAFCYYWMQAAyQEFjg0AAAMAXAB1DQAAAgBHAH8NAAACAAYAqQ0AAAIAQAAzDQAAAQA0ADUABAqBIQADCwAJCbokBQEAXwMACwAICVElBQEAXwMADAABCQUgo0EAXQAAAAA=.',
Ha='Hakdh:BAEANQADCgMIAwABNQAFFAUICgADABAIAA==.Hakdk:BAEANQAECgMIAwABNQAFFAUICgADABAIAA==.',
Ho='Hobo:BAEANQADCgIIAgABNQAECgYIEAAGAAAAAA==.Hoboomkin:BAEANQAECgYIEAAAAA==.',
Ih='Ihateffxiv:BAEANQADCgcIDQAAAA==.',
In='Inaríus:BAEANQAECgQIBQAAAA==.',
Jw='Jwsmashfan:BAEANQAECggIDAABNQAFFAUICAANALwOAA==.',
Ka='Kalevias:BAECNQAFFIEKAAIDAAUJEAjEAQA3AQWODQAAAwAWAHUNAAACAAAAfw0AAAIAKwCpDQAAAgAfADMNAAABAAQAAwAFCRAIxAEANwEFjg0AAAMAFgB1DQAAAgAAAH8NAAACACsAqQ0AAAIAHwAzDQAAAQAEADUABAqBIQACAwAJCWIZ+wcAhAIAAwAJCWIZ+wcAhAIAAAA=.',
Le='Lewinskibidi:BAECNQAFFIEIAAINAAUJvA4MAQCfAQWODQAAAQBHAHUNAAABAB0Afw0AAAEAGgCpDQAAAwAKADMNAAACADIADQAFCbwODAEAnwEFjg0AAAEARwB1DQAAAQAdAH8NAAABABoAqQ0AAAMACgAzDQAAAgAyADUABAqBGwACDQAJCSIgmAEAFgMADQAJCSIgmAEAFgMAAAA=.',
Li='Lilsoup:BAEANQADCggIFwABNQAECgkJGQABABwRAA==.',
Ma='Madtheaug:BAEANQAECgcICAABNQAFFAcJEQAOAPAiAA==.Mangofart:BAEANQAECgYIEAAAAA==.Mattchstep:BAEANQAECggICAABNQAFFAUICAANALwOAA==.',
Mi='Minbä:BAEBNQAECoEaAAIPAAgJIyCsEQD2AgiODQAABABhAHUNAAAEAE0Afw0AAAMAYwCpDQAABABJAFwNAAADAEoAXQ0AAAIARwBlDQAAAgBPADMNAAAEAFQADwAICSMgrBEA9gIIjg0AAAQAYQB1DQAABABNAH8NAAADAGMAqQ0AAAQASQBcDQAAAwBKAF0NAAACAEcAZQ0AAAIATwAzDQAABABUAAE1AAUUBQgHAA4AoBAA.Miniss:BAECNQAFFIEHAAMOAAUJoBDNAwBNAQWODQAAAwBSAHUNAAABABAAfw0AAAEAJQCpDQAAAQAeADMNAAABAC0ADgAECTQTzQMATQEEjg0AAAIAUgB/DQAAAQAlAKkNAAABAB4AMw0AAAEALQAQAAIJkQnTBgCmAAKODQAAAQAgAHUNAAABABAANQAECoEhAAMOAAkJMSLuBwAxAwAOAAkJMSLuBwAxAwAQAAcJBhuyCgAjAgAAAA==.',
Mo='Mobes:BAEANQAECgUICgAAAA==.Moosclemommy:BAEBNQAFFIEGAAIIAAQJnxU+AQAwAQSODQAAAgAsAHUNAAABADQAqQ0AAAIARQAzDQAAAQA3AAgABAmfFT4BADABBI4NAAACACwAdQ0AAAEANACpDQAAAgBFADMNAAABADcAATUABAoHCA0ABgAAAAA=.Mowrii:BAEANQADCgYIBgABNQAECgcIDgAGAAAAAA==.',
Ni='Nimueh:BAEANQAFFAEIAgAAAA==.Niniane:BAEBNQAECoEeAAIRAAkJCiQzAwCjAwmODQAABABhAHUNAAAEAGMAfw0AAAQAWwCpDQAABABhAFwNAAADAFwAXQ0AAAMAWgBlDQAAAwBPAKQNAAACAFEAMw0AAAMAYwARAAkJCiQzAwCjAwmODQAABABhAHUNAAAEAGMAfw0AAAQAWwCpDQAABABhAFwNAAADAFwAXQ0AAAMAWgBlDQAAAwBPAKQNAAACAFEAMw0AAAMAYwAAAA==.',
No='Noradk:BAEANQADCggICAABNQAECggIGAADABchAA==.Noralisa:BAEBNQAECoEYAAIDAAgJFyGYBAD9AgiODQAABABaAHUNAAAEAF8Afw0AAAQAVwCpDQAAAwBVAFwNAAACAFAAXQ0AAAIAVwBlDQAAAgBEADMNAAADAFIAAwAICRchmAQA/QIIjg0AAAQAWgB1DQAABABfAH8NAAAEAFcAqQ0AAAMAVQBcDQAAAgBQAF0NAAACAFcAZQ0AAAIARAAzDQAAAwBSAAAA.Noreleasa:BAEANQADCgUIBQABNQAECggIGAADABchAA==.Notspidee:BAEANQADCgYIBgABNQAECgUIAgAGAAAAAA==.Novelus:BAEANQAECgYICgAAAA==.',
Ol='Oldbronze:BAEBNQAECoEXAAIFAAgJTyAiAwDnAgiODQAABABdAHUNAAAEAF0Afw0AAAMAUQCpDQAAAwBMAFwNAAADAFsAXQ0AAAIAUQBlDQAAAQBKADMNAAADAEUABQAICU8gIgMA5wIIjg0AAAQAXQB1DQAABABdAH8NAAADAFEAqQ0AAAMATABcDQAAAwBbAF0NAAACAFEAZQ0AAAEASgAzDQAAAwBFAAAA.',
Pa='Parkercannon:BAEANQAECgEIAQABNQAFFAUICAANALwOAA==.Patrennessy:BAEANQAECgEIAQABNQAFFAUICgALAIYWAA==.',
Ra='Ramsama:BAEANQADCggICAABNQAECgkJGgASADobAA==.Ramsw:BAECNQAFFIEHAAITAAUJlCGrAgD8AQWODQAAAgBPAHUNAAABAGIAfw0AAAEATgCpDQAAAgBaADMNAAABAFMAEwAFCZQhqwIA/AEFjg0AAAIATwB1DQAAAQBiAH8NAAABAE4AqQ0AAAIAWgAzDQAAAQBTADUABAqBHQACEwAJCTYlpgQAtwMAEwAJCTYlpgQAtwMAAAA=.',
Re='Recursively:BAECNQAFFIEMAAQQAAYJSRGZAQD4AAaODQAAAQAKAHUNAAADABcAfw0AAAIAKwCpDQAAAwA7AF0NAAABAD4AMw0AAAIAQgAOAAMJdREyBwD8AAN/DQAAAgArAKkNAAABABwAXQ0AAAEAPgAQAAMJIAyZAQD4AAOODQAAAQAKAHUNAAADABcAqQ0AAAIAOwAUAAEJ7BlFAwBWAAEzDQAAAgBCADUABAqBHgADDgAJCc4jsRIAygIADgAHCTAksRIAygIAEAAHCQUXOQsAGwIAAAA=.Resika:BAEBNQAECoEaAAISAAkJOhugEwDAAgmODQAAAwBZAHUNAAADADcAfw0AAAMAWQCpDQAAAwBdAFwNAAADAFkAXQ0AAAMAPwBlDQAAAgAiAKQNAAADACwAMw0AAAMARAASAAkJOhugEwDAAgmODQAAAwBZAHUNAAADADcAfw0AAAMAWQCpDQAAAwBdAFwNAAADAFkAXQ0AAAMAPwBlDQAAAgAiAKQNAAADACwAMw0AAAMARAAAAA==.Retaholics:BAEANQADCggIDgAAAA==.',
Ri='Riversong:BAEBNQAECoEYAAISAAkJqhTOFwCRAgmODQAAAwA/AHUNAAADAEoAfw0AAAMAOQCpDQAAAwA5AFwNAAADACMAXQ0AAAMANgBlDQAAAgAvAKQNAAABABIAMw0AAAMAQwASAAkJqhTOFwCRAgmODQAAAwA/AHUNAAADAEoAfw0AAAMAOQCpDQAAAwA5AFwNAAADACMAXQ0AAAMANgBlDQAAAgAvAKQNAAABABIAMw0AAAMAQwABNQAFFAEIAgAGAAAAAA==.',
Ro='Rolic:BAEANQADCggICgABNQAECgYIEAAGAAAAAA==.',
Ru='Ruwon:BAEANQADCgYIBgABNQAFFAYIDQAIANgbAA==.Ruwondk:BAEBNQAECoEYAAIVAAkJjx1/CQAfAwmODQAAAwBcAHUNAAADAFsAfw0AAAMAWQCpDQAAAwBcAFwNAAADAFwAXQ0AAAMAMABlDQAAAgA8AKQNAAABAB8AMw0AAAMAUAAVAAkJjx1/CQAfAwmODQAAAwBcAHUNAAADAFsAfw0AAAMAWQCpDQAAAwBcAFwNAAADAFwAXQ0AAAMAMABlDQAAAgA8AKQNAAABAB8AMw0AAAMAUAABNQAFFAYIDQAIANgbAA==.',
Sh='Sharrq:BAEBNQAECoEYAAQWAAgJix4TAQAyAgiODQAABABaAHUNAAAEAFcAfw0AAAMAWgCpDQAAAwBOAFwNAAADAF8AXQ0AAAIASABlDQAAAgAoADMNAAADAEYABwAICWwZLUUAgAIIjg0AAAEAWgB1DQAAAQBUAH8NAAABAE8AqQ0AAAEATgBcDQAAAQADAF0NAAABAEgAZQ0AAAEAKAAzDQAAAQBGABYABwmOGRMBADICB44NAAACAEcAdQ0AAAIAUgB/DQAAAQBJAKkNAAABACAAXA0AAAIAXwBlDQAAAQAmADMNAAACAD4AFwAFCeAYuQgAggEFjg0AAAEAVgB1DQAAAQBXAH8NAAABAFoAqQ0AAAEAJABdDQAAAQASAAAA.',
Si='Silversoph:BAEANQADCgQIAgAAAA==.',
Sl='Slimelight:BAEANQAECgQIBgAAAA==.',
St='Stuu:BAECNQAFFIEIAAIVAAUJxh0QAgDZAQWODQAAAgBaAHUNAAABADgAfw0AAAEALQCpDQAAAgBZADMNAAACAGMAFQAFCcYdEAIA2QEFjg0AAAIAWgB1DQAAAQA4AH8NAAABAC0AqQ0AAAIAWQAzDQAAAgBjADUABAqBGwADFQAJCcQkKgMAnAMAFQAJCcQkKgMAnAMAGAACCVwHunEAZwAAATUABAoHCAcABgAAAAA=.Stuwy:BAEANQAECgcIBwAAAA==.',
Te='Tendiarii:BAEANQADCgUIBQAAAA==.',
Th='Thanala:BAEANQAFFAIIAwAAAA==.',
Wo='Wormdropper:BAEANQAECgQICAAAAA==.',
Zd='Zdeath:BAEANQADCgYIBgABNQAECgYIEAAGAAAAAA==.',
Ze='Zemonn:BAEANQADCggICAABNQAECgYIEAAGAAAAAA==.',
['Çb']='Çbk:BAECNQAFFIEIAAQOAAUJxxr2AgBrAQWODQAAAQBjAHUNAAACADIAfw0AAAEALwCpDQAAAgA3ADMNAAACAFoADgAECWkW9gIAawEEjg0AAAEAYwB1DQAAAQAyAH8NAAABAC8AqQ0AAAEAIAAQAAIJBhDlBQCvAAJ1DQAAAQAaAKkNAAABADcAFAABCUEjygEAaAABMw0AAAIAWgA1AAQKgSAABA4ACQkFJZsKABQDAA4ACAnlJJsKABQDABAABglXGB4RAMgBABQABAneIqsFAJUBAAAA.',
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
