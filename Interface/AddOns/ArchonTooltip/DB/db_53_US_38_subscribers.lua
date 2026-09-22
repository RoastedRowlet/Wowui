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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Unknown-Unknown','Evoker-Augmentation','Mage-Arcane','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Monk-Mistweaver','Hunter-BeastMastery','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Balance','Mage-Fire','Mage-Frost',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=53,date='2026-09-22',data={Ad='Addex:BAEBNQAECoEgAAQBAAkK6BVkJAB+AgmODQAABwAyAHUNAAAEACIAfw0AAAQAJwCpDQAABAAyAFwNAAAEADEAXQ0AAAIASwBlDQAABABRAKQNAAABAFEAMw0AAAIAKQABAAkK6BVkJAB+AgmODQAAAwAyAHUNAAABACIAfw0AAAEAJwCpDQAAAQAyAFwNAAABADEAXQ0AAAEASwBlDQAAAwBRAKQNAAABAFEAMw0AAAIAKQACAAcK0hj4UAASAgeODQAAAgA8AHUNAAABAFEAfw0AAAEANACpDQAAAQBUAFwNAAABAEUAXQ0AAAEAOQBlDQAAAQAmAAMABQrYGsgeAF8BBY4NAAACAFEAdQ0AAAIATAB/DQAAAgAzAKkNAAACAEcAXA0AAAIAPgABNQAFFAcIGQAEAN0jAA==.',
Am='Ambient:BAECNQAFFIEZAAIEAAcK3SN4AAC1AgeODQAABQBkAHUNAAAEAFkAfw0AAAMAVQCpDQAABABZAFwNAAADAFUAXQ0AAAIAXgAzDQAABABhAAQABwrdI3gAALUCB44NAAAFAGQAdQ0AAAQAWQB/DQAAAwBVAKkNAAAEAFkAXA0AAAMAVQBdDQAAAgBeADMNAAAEAGEANQAECoEbAAIEAAkKhCJYCADrAgAEAAkKhCJYCADrAgAAAA==.',
Av='Avarat:BAECNQAFFIEGAAIFAAQKSxNGAQArAQSODQAAAgA/AHUNAAABABgAqQ0AAAIAQQAzDQAAAQAsAAUABApLE0YBACsBBI4NAAACAD8AdQ0AAAEAGACpDQAAAgBBADMNAAABACwANQAECoEaAAIFAAkKEho0BQC1AgAFAAkKEho0BQC1AgABNQAECggJEQAGAAAAAA==.Avtrene:BAEANQADCgIJAgAAAA==.',
Az='Azenia:BAEBNQAECoEXAAMEAAcKEgyZHgBrAQeODQAABQAMAHUNAAAEAD8Afw0AAAQABACpDQAABABNAFwNAAADAAcAXQ0AAAIAJwAzDQAAAQALAAQABwoSDJkeAGsBB44NAAACAAwAdQ0AAAEAPwB/DQAAAQAEAKkNAAABAE0AXA0AAAEABwBdDQAAAQAnADMNAAABAAsABwAGCqcPHQoAPgEGjg0AAAMAOQB1DQAAAwA9AH8NAAADACgAqQ0AAAMAIgBcDQAAAgAqAF0NAAABAAIAAAA=.',
Ba='Banddaid:BAEANQAECgEIAQABNQAECgkJGwAIAM8fAA==.',
Bi='Bigchubber:BAEANQAECgYJDQAAAA==.',
Br='Briéè:BAEANQADCgEIAQAAAA==.Bruwon:BAECNQAFFIETAAIJAAYKlh1oAAAdAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAMAUwAJAAYKlh1oAAAdAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAMAUwA1AAQKgRkAAgkACQpZJWcBAJADAAkACQpZJWcBAJADAAAA.',
Ch='Charzie:BAEANQAFFAEIAQABNQAFFAYIEwAJAJYdAA==.',
Da='Danitsia:BAEANQAECgQIBgAAAA==.',
De='Deathkleburg:BAEBNQAECoEcAAQKAAkKHRlcGQA+AgmODQAABABAAHUNAAAEAEcAfw0AAAQATgCpDQAABABHAFwNAAACABIAXQ0AAAIARABlDQAAAgBSAKQNAAACADIAMw0AAAQASAAKAAgK/hZcGQA+AgiODQAAAgA9AHUNAAABAEcAfw0AAAEAOwCpDQAAAgBHAFwNAAABABIAXQ0AAAEARACkDQAAAgAyADMNAAADAEQACwAHCm0XrjUAzgEHjg0AAAIAQAB1DQAAAQA6AH8NAAABAEcAqQ0AAAIAQQBcDQAAAQAEAGUNAAACAFIAMw0AAAEASAAMAAMK3hmAZgDVAAN1DQAAAgA4AH8NAAACAE4AXQ0AAAEAQAAAAA==.Delacoûr:BAEANQAECgQIBgABNQAFFAYIDgANADAYAA==.',
Do='Doorstuck:BAEANQADCggICAABNQAECggJEQAGAAAAAA==.',
El='Elfylicious:BAEANQADCgMIAwABNQAECgYICQAGAAAAAA==.',
Fe='Fentweaver:BAECNQAFFIEKAAIOAAUKGxV5AQC8AQWODQAAAwAZAHUNAAACABgAfw0AAAEARQCpDQAAAwA3ADMNAAABAF8ADgAFChsVeQEAvAEFjg0AAAMAGQB1DQAAAgAYAH8NAAABAEUAqQ0AAAMANwAzDQAAAQBfADUABAqBJAACDgAJCtshTwMASgMADgAJCtshTwMASgMAAAA=.',
Fu='Fuddly:BAEANQAECgEJAQABNQAECgYJDQAGAAAAAA==.',
Gi='Ginebra:BAEANQADCggIFgAAAA==.',
Gj='Gjlo:BAEANQADCggJCAABNQAECgkJJgAPANkgAA==.',
Gr='Gronknose:BAECNQAFFIEPAAIQAAUKghpEAADYAQWODQAABABcAHUNAAADAEcAfw0AAAMAJQCpDQAAAwBVADMNAAACADQAEAAFCoIaRAAA2AEFjg0AAAQAXAB1DQAAAwBHAH8NAAADACUAqQ0AAAMAVQAzDQAAAgA0ADUABAqBJAADEAAJCtckUAEAXQMAEAAICnElUAEAXQMAEQABCgUgplYAWwAAAAA=.',
Ha='Hakdh:BAEANQADCgMJAwABNQAFFAUJDwADAK0IAA==.Hakdk:BAEANQAECgMJAwABNQAFFAUJDwADAK0IAA==.',
Ho='Hobo:BAEANQADCgIIAgABNQAECggICAAGAAAAAA==.Hoboomkin:BAEANQAECgYIEAABNQAECggICAAGAAAAAA==.Hoborc:BAEANQAECggICAAAAA==.',
Ih='Ihateffxiv:BAEANQADCgcIDQAAAA==.',
In='Inaríus:BAEANQAECgUICgAAAA==.',
Jw='Jwsmashfan:BAEBNQAECoEVAAISAAkKzhd7OQCAAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABABGAKQNAAACACIAMw0AAAEAQQASAAkKzhd7OQCAAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABABGAKQNAAACACIAMw0AAAEAQQABNQAFFAYIDAAHAC4UAA==.',
Ka='Kalevias:BAECNQAFFIEPAAIDAAUKrQjpAgAxAQWODQAABAAWAHUNAAADAAAAfw0AAAMALwCpDQAAAwAfADMNAAACAAkAAwAFCq0I6QIAMQEFjg0AAAQAFgB1DQAAAwAAAH8NAAADAC8AqQ0AAAMAHwAzDQAAAgAJADUABAqBJAACAwAJCmIZBgwAZAIAAwAJCmIZBgwAZAIAAAA=.',
Le='Lewinskibidi:BAECNQAFFIEMAAIHAAYKLhTzAAARAgaODQAAAgBbAHUNAAABAB0Afw0AAAIAGgCpDQAABAAvAFwNAAABAEAAMw0AAAIAMgAHAAYKLhTzAAARAgaODQAAAgBbAHUNAAABAB0Afw0AAAIAGgCpDQAABAAvAFwNAAABAEAAMw0AAAIAMgA1AAQKgR0AAgcACQr9I7kBADcDAAcACQr9I7kBADcDAAAA.',
Li='Lilsoup:BAEANQAFFAEIAQABNQAECgkJHAABABwRAA==.',
Ma='Madtheaug:BAEANQAECgcICAABNQAFFAgKGQATAEUiAA==.Mangofart:BAEBNQAECoEbAAIUAAgKqRoeCQCQAgiODQAABQBPAHUNAAADAEsAfw0AAAQAUACpDQAABABQAFwNAAADADwAXQ0AAAMAOwBlDQAAAQAtADMNAAAEAEEAFAAICqkaHgkAkAIIjg0AAAUATwB1DQAAAwBLAH8NAAAEAFAAqQ0AAAQAUABcDQAAAwA8AF0NAAADADsAZQ0AAAEALQAzDQAABABBAAAA.Mattchstep:BAEANQAECggICAABNQAFFAYIDAAHAC4UAA==.',
Mi='Minbä:BAEBNQAECoEhAAIVAAkKjB+bDgBAAwmODQAABgBhAHUNAAAFAFQAfw0AAAQAYwCpDQAABABJAFwNAAADAEoAXQ0AAAIARwBlDQAAAwBPAKQNAAABADUAMw0AAAUAXAAVAAkKjB+bDgBAAwmODQAABgBhAHUNAAAFAFQAfw0AAAQAYwCpDQAABABJAFwNAAADAEoAXQ0AAAIARwBlDQAAAwBPAKQNAAABADUAMw0AAAUAXAABNQAFFAYJCwAWAA0QAA==.Miniss:BAECNQAFFIELAAMWAAYKDRArBACYAQaODQAAAwBSAHUNAAACABAAfw0AAAIAJQCpDQAAAQAeAFwNAAABACEAMw0AAAIALQAWAAUKABIrBACYAQWODQAAAgBSAH8NAAACACUAqQ0AAAEAHgBcDQAAAQAhADMNAAACAC0AFwACCpEJLAoAoQACjg0AAAEAIAB1DQAAAgAQADUABAqBKgADFgAJCvAiawkARQMAFgAJCvAiawkARQMAFwAHCjccdgoAMQIAAAA=.',
Mo='Mobes:BAEANQAECggJEQAAAA==.Moosclemommy:BAEBNQAFFIELAAIJAAUKahhOAQCKAQWODQAAAwA8AHUNAAACADQAfw0AAAEAQgCpDQAAAwBKADMNAAACADoACQAFCmoYTgEAigEFjg0AAAMAPAB1DQAAAgA0AH8NAAABAEIAqQ0AAAMASgAzDQAAAgA6AAE1AAQKCAkRAAYAAAAA.Mowrii:BAEANQADCgYIBgABNQAECggIGAAYAPMgAA==.',
Ni='Nimueh:BAECNQAFFIEJAAINAAUKSwOICABtAQWODQAAAQADAHUNAAABAAIAfw0AAAMABgCpDQAAAQAMADMNAAADAA8ADQAFCksDiAgAbQEFjg0AAAEAAwB1DQAAAQACAH8NAAADAAYAqQ0AAAEADAAzDQAAAwAPADUABAqBHAACDQAJCjIOLDYAFwIADQAJCjIOLDYAFwIAAAA=.Niniane:BAECNQAFFIEKAAMPAAUKWxbzBABpAQWODQAAAgBLAHUNAAACAD8Afw0AAAEAEwCpDQAAAwBCADMNAAACADwADwAECgoa8wQAaQEEjg0AAAEASwB1DQAAAQA/AKkNAAADAEIAMw0AAAIAPAAZAAMKHQQGDQDPAAOODQAAAQAIAHUNAAABAAMAfw0AAAEAEwA1AAQKgSEAAw8ACQpWJIYFAI8DAA8ACQpWJIYFAI8DABkAAgrvDpVJAH0AAAAA.',
No='Noradk:BAEANQAECgIIAgABNQAECgkJHQADAFsgAA==.Noralisa:BAEBNQAECoEdAAIDAAkKWyAtBABCAwmODQAABQBdAHUNAAAFAF8Afw0AAAUAVwCpDQAAAwBVAFwNAAACAFAAXQ0AAAIAVwBlDQAAAwBJAKQNAAABADsAMw0AAAMAUgADAAkKWyAtBABCAwmODQAABQBdAHUNAAAFAF8Afw0AAAUAVwCpDQAAAwBVAFwNAAACAFAAXQ0AAAIAVwBlDQAAAwBJAKQNAAABADsAMw0AAAMAUgAAAA==.Noreleasa:BAEANQADCgUIBQABNQAECgkJHQADAFsgAA==.Notspidee:BAEANQADCgYIBgABNQAECgUIAgAGAAAAAA==.Novelus:BAEANQAFFAIJAgAAAA==.',
Ol='Oldbronze:BAEBNQAECoEfAAIFAAgKbyOpAgAwAwiODQAABQBfAHUNAAAFAF0Afw0AAAQAUQCpDQAABABaAFwNAAAEAF4AXQ0AAAMAWABlDQAAAgBUADMNAAAEAGEABQAICm8jqQIAMAMIjg0AAAUAXwB1DQAABQBdAH8NAAAEAFEAqQ0AAAQAWgBcDQAABABeAF0NAAADAFgAZQ0AAAIAVAAzDQAABABhAAAA.',
Pa='Parkercannon:BAEANQAECgEIAQABNQAFFAYIDAAHAC4UAA==.Patrennessy:BAEANQAECgEJAQABNQAFFAUIDwAQAIIaAA==.',
Ra='Ramsama:BAEANQADCggICAABNQAECgkJIwAaALMcAA==.Ramsw:BAECNQAFFIEMAAISAAUKpiP5AwACAgWODQAAAwBPAHUNAAACAGIAfw0AAAIAUgCpDQAAAwBhADMNAAACAGEAEgAFCqYj+QMAAgIFjg0AAAMATwB1DQAAAgBiAH8NAAACAFIAqQ0AAAMAYQAzDQAAAgBhADUABAqBHwACEgAJCk0lIAgAmgMAEgAJCk0lIAgAmgMAAAA=.',
Re='Recursively:BAECNQAFFIENAAQXAAYKSRHxAQDwAAaODQAAAQAKAHUNAAADABcAfw0AAAIAKwCpDQAAAwA7AF0NAAABAD4AMw0AAAMAQgAWAAMKdRF/DQDyAAN/DQAAAgArAKkNAAABABwAXQ0AAAEAPgAXAAMKIAzxAQDwAAOODQAAAQAKAHUNAAADABcAqQ0AAAIAOwATAAEK7BlGBQBVAAEzDQAAAwBCADUABAqBJQADFgAJCjkkmBYA4QIAFgAHCrkkmBYA4QIAFwAHCgUXHA0ABgIAAAA=.Resika:BAEBNQAECoEjAAIaAAkKsxxbEwDqAgmODQAABABZAHUNAAAEAFIAfw0AAAQAWQCpDQAABABdAFwNAAAEAFkAXQ0AAAQAPwBlDQAAAgAiAKQNAAAFACwAMw0AAAQASgAaAAkKsxxbEwDqAgmODQAABABZAHUNAAAEAFIAfw0AAAQAWQCpDQAABABdAFwNAAAEAFkAXQ0AAAQAPwBlDQAAAgAiAKQNAAAFACwAMw0AAAQASgAAAA==.Retaholics:BAEANQADCggIDgAAAA==.',
Ri='Riversong:BAEBNQAECoEaAAIaAAkKAhUTHgB/AgmODQAABABAAHUNAAADAEoAfw0AAAMAOQCpDQAAAwA5AFwNAAADACMAXQ0AAAMANgBlDQAAAgAvAKQNAAABABIAMw0AAAQASgAaAAkKAhUTHgB/AgmODQAABABAAHUNAAADAEoAfw0AAAMAOQCpDQAAAwA5AFwNAAADACMAXQ0AAAMANgBlDQAAAgAvAKQNAAABABIAMw0AAAQASgABNQAFFAUJCQANAEsDAA==.',
Ro='Rolic:BAEANQADCggICgABNQAECgcJFwAEABIMAA==.',
Ru='Ruwon:BAEANQAECgIIAgABNQAFFAYIEwAJAJYdAA==.Ruwondk:BAEBNQAECoEfAAIMAAkKMCG3BgBmAwmODQAABABfAHUNAAAEAF8Afw0AAAQAWQCpDQAABABeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAMAUAAMAAkKMCG3BgBmAwmODQAABABfAHUNAAAEAF8Afw0AAAQAWQCpDQAABABeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAMAUAABNQAFFAYIEwAJAJYdAA==.',
Sh='Shadythicc:BAEANQAECgQIBAABNQAECggICAAGAAAAAA==.Sharrq:BAEBNQAECoEgAAQIAAkKAB7wIwAoAwmODQAABABaAHUNAAAFAFcAfw0AAAQAWgCpDQAABABcAFwNAAAEAF8AXQ0AAAMASABlDQAAAwArAKQNAAABACEAMw0AAAQAVQAIAAkK9xzwIwAoAwmODQAAAQBaAHUNAAACAFQAfw0AAAIAVwCpDQAAAgBcAFwNAAACAE0AXQ0AAAIASABlDQAAAgArAKQNAAABACEAMw0AAAIAVQAbAAcKjhmHAQAiAgeODQAAAgBHAHUNAAACAFIAfw0AAAEASQCpDQAAAQAgAFwNAAACAF8AZQ0AAAEAJgAzDQAAAgA+ABwABQrgGEwMAHEBBY4NAAABAFYAdQ0AAAEAVwB/DQAAAQBaAKkNAAABACQAXQ0AAAEAEgAAAA==.',
Si='Silversoph:BAEANQADCgQJAgAAAA==.',
Sl='Slimelight:BAEANQAECgQIBgAAAA==.',
St='Stuu:BAECNQAFFIENAAIMAAYK5SB1AQA+AgaODQAAAwBaAHUNAAACAEgAfw0AAAIASwCpDQAAAwBZAFwNAAABAE0AMw0AAAIAYwAMAAYK5SB1AQA+AgaODQAAAwBaAHUNAAACAEgAfw0AAAIASwCpDQAAAwBZAFwNAAABAE0AMw0AAAIAYwA1AAQKgR0AAwwACQoCJTsEAJADAAwACQoCJTsEAJADAAsAAgpcB0mCAGEAAAE1AAQKBwgHAAYAAAAA.Stuwy:BAEANQAECgcIBwAAAA==.',
Te='Tendiarii:BAEANQADCgcIDAAAAA==.',
Th='Thanala:BAEANQAFFAMIBAAAAA==.',
Wo='Wormdropper:BAEANQAECgUIDwAAAA==.',
Zd='Zdeath:BAEANQADCgYIBgABNQAECggIGwAUAKkaAA==.',
Ze='Zemonn:BAEANQADCggICAABNQAECggIGwAUAKkaAA==.',
['Çb']='Çbk:BAECNQAFFIENAAQWAAYK8R99AgDYAQaODQAAAQBjAHUNAAADADUAfw0AAAIAUgCpDQAAAwBKAFwNAAABAFMAMw0AAAMAYQAWAAUKch59AgDYAQWODQAAAQBjAHUNAAABADIAfw0AAAIAUgCpDQAAAgBKAFwNAAABAFMAFwACCicVXwcAsQACdQ0AAAIANQCpDQAAAQA3ABMAAQovJkcCAHMAATMNAAADAGEANQAECoEnAAQWAAkKiSVeCgA7AwAWAAgKhiVeCgA7AwATAAUKpCM+BQD9AQAXAAYKdxjWEgDDAQAAAA==.',
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
