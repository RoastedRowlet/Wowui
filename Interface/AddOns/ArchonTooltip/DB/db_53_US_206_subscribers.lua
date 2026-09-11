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

local lookup = {'Unknown-Unknown','Priest-Holy','Warlock-Destruction','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Paladin-Retribution','Shaman-Restoration','Warlock-Demonology','DeathKnight-Frost','Warlock-Affliction','DeathKnight-Blood','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Outlaw',}
local provider = {region='US',realm='Stormrage',name='US',type='subscribers',zone=53,date='2026-09-08',data={Ag='Agamo:BAEANQAECgUICAAAAA==.Agramon:BAEANQADCgYIBgABNQAECgUIBQABAAAAAA==.',
Ai='Aisllin:BAECNQAFFIEHAAICAAUJMxVpAQC9AQWODQAAAgBNAHUNAAABABUAfw0AAAEALQCpDQAAAgA+ADMNAAABAEAAAgAFCTMVaQEAvQEFjg0AAAIATQB1DQAAAQAVAH8NAAABAC0AqQ0AAAIAPgAzDQAAAQBAADUABAqBHQACAgAJCdwhnQUAIAMAAgAJCdwhnQUAIAMAAAA=.',
Al='Alahno:BAEANQAECgUIDAAAAA==.Alascene:BAEANQAECgYIDwABNQAFFAUIBgADAEkdAA==.Aldrimord:BAEANQADCggICAAAAA==.Alvanys:BAEANQAECgUICAABNQAECgYIBgABAAAAAA==.',
Am='Amarindre:BAEBNQAECoEYAAIEAAkJVSANBABdAwmODQAAAwBTAHUNAAADAGIAfw0AAAMAWwCpDQAAAwBeAFwNAAADAEUAXQ0AAAIAXQBlDQAAAgBaAKQNAAACACIAMw0AAAMAWAAEAAkJVSANBABdAwmODQAAAwBTAHUNAAADAGIAfw0AAAMAWwCpDQAAAwBeAFwNAAADAEUAXQ0AAAIAXQBlDQAAAgBaAKQNAAACACIAMw0AAAMAWAAAAA==.',
An='Anniestraza:BAEANQAECgcIEAAAAA==.',
Ar='Archítecture:BAEANQAECgYICQAAAA==.Artemisdeath:BAEANQADCgQIBAABNQAECgIIAgABAAAAAA==.Artemisshock:BAEANQAECgIIAgAAAA==.',
As='Ashjik:BAEANQAECgcIEQAAAA==.Askaori:BAEANQAECgEIAQABNQAFFAYIDQAFACAVAA==.Asrei:BAEANQAECgEIAgABNQAFFAYIDQAFACAVAA==.',
At='Atemae:BAEANQAECgUIBgAAAA==.Atemea:BAEANQADCggIEgABNQAECgUIBgABAAAAAA==.',
Ay='Ayrriiss:BAEANQAECgMIBAABNQABCgEIAQABAAAAAA==.',
Az='Azraelis:BAEANQADCggICAABNQAECgkJGAAGAN8WAA==.Azraelisa:BAEBNQAECoEYAAMGAAkJ3xapBgCcAgmODQAAAwBDAHUNAAADAD8Afw0AAAMAQACpDQAAAwA5AFwNAAADAE4AXQ0AAAMADwBlDQAAAgBOAKQNAAABAA8AMw0AAAMAVAAGAAkJNhSpBgCcAgmODQAAAwBDAHUNAAADAD8Afw0AAAMAQACpDQAAAwA5AFwNAAADAE4AXQ0AAAMADwBlDQAAAgBOAKQNAAABAA8AMw0AAAIAFwAHAAEJECEtDABhAAEzDQAAAQBUAAAA.',
Bi='Bignumbyguy:BAEBNQAECoEXAAMIAAkJZCVnAADdAwmODQAAAwBgAHUNAAADAGMAfw0AAAMAXgCpDQAAAwBgAFwNAAADAF4AXQ0AAAMAYABlDQAAAgBhAKQNAAACAFYAMw0AAAEAYwAIAAkJZCVnAADdAwmODQAAAwBgAHUNAAADAGMAfw0AAAMAXgCpDQAAAwBgAFwNAAADAF4AXQ0AAAIAYABlDQAAAgBhAKQNAAACAFYAMw0AAAEAYwAJAAEJ1BJ7LQBMAAFdDQAAAQAwAAAA.',
Bl='Blunch:BAEANQAECggIEAAAAA==.Bluncle:BAEANQADCggICAABNQAECggIEAABAAAAAA==.',
Bo='Boodybear:BAEANQADCgcIDQAAAA==.Bopboopbonk:BAEBNQAECoEbAAIKAAkJ/iFTBAB+AwmODQAAAwBjAHUNAAADAGMAfw0AAAMAUgCpDQAAAwBjAFwNAAADAE8AXQ0AAAMAYwBlDQAABABUAKQNAAACADUAMw0AAAMAVQAKAAkJ/iFTBAB+AwmODQAAAwBjAHUNAAADAGMAfw0AAAMAUgCpDQAAAwBjAFwNAAADAE8AXQ0AAAMAYwBlDQAABABUAKQNAAACADUAMw0AAAMAVQABNQAECgMIAwABAAAAAA==.Bottlepops:BAEANQAECgcIEQAAAA==.',
Br='Brandanawitz:BAEANQADCgQIAwABNQAECgQICQABAAAAAA==.Breezyxd:BAEANQAECggIDgAAAA==.',
Bu='Bungiegrips:BAEANQAECgYICAAAAA==.Burstinsider:BAEANQAECggIEAAAAA==.Butterballed:BAEANQAECgcICwABNQAECgcICwABAAAAAA==.Butterloc:BAEANQAECgcIDgABNQAECgcICwABAAAAAA==.',
['Bá']='Bádderdragon:BAEANQAECgYIDQAAAA==.',
['Bô']='Bônëbrëàkèr:BAEANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Ca='Calypsix:BAEANQAECgYICwAAAA==.Caräntyr:BAEANQAECgYICgAAAA==.',
Ce='Celanlor:BAEANQADCgYIBgABNQAECgkJGAAEAFUgAA==.Cerulegos:BAEANQAECgIIAgAAAA==.',
Ch='Chainsnight:BAEANQAECgUICAAAAA==.Cherle:BAEANQAECggIDwAAAA==.Chipotlea:BAEANQAECgcIDAAAAA==.Chipotlei:BAEANQADCgYIBgABNQAECgcIDAABAAAAAA==.Chubbwing:BAEANQADCgEIAQABNQAECgcICwABAAAAAA==.',
Co='Corpulence:BAEANQAECgcICwAAAA==.',
Cr='Crocop:BAEANQAECgEIAQAAAA==.Cryomuffin:BAEANQAECgYICAAAAA==.',
Cy='Cynderryke:BAEANQAECgcIEQAAAA==.',
Da='Danowarr:BAEANQAECgQIBgAAAA==.Darkknive:BAEANQADCgcIEgAAAA==.',
De='Deadjak:BAEANQADCgYIBgABNQAECgQIBwABAAAAAA==.Defarus:BAEBNQAECoEZAAIEAAkJNyBlAwBvAwmODQAAAwBfAHUNAAADAF0Afw0AAAMAWACpDQAAAwBPAFwNAAADAFYAXQ0AAAMAWABlDQAAAgBAAKQNAAACADUAMw0AAAMAXAAEAAkJNyBlAwBvAwmODQAAAwBfAHUNAAADAF0Afw0AAAMAWACpDQAAAwBPAFwNAAADAFYAXQ0AAAMAWABlDQAAAgBAAKQNAAACADUAMw0AAAMAXAAAAA==.Delusionol:BAEBNQAECoEaAAMCAAkJ6xshEACCAgmODQAABABfAHUNAAADAEwAfw0AAAMARQCpDQAABABNAFwNAAADADIAXQ0AAAMAQwBlDQAAAgBCAKQNAAABAFQAMw0AAAMANgACAAkJ6xshEACCAgmODQAAAwBfAHUNAAADAEwAfw0AAAMARQCpDQAABABNAFwNAAADADIAXQ0AAAMAQwBlDQAAAgBCAKQNAAABAFQAMw0AAAIANgALAAIJvxk3KwCTAAKODQAAAQBHADMNAAABADwAAAA=.Destoresto:BAEANQADCggIEAABNQAECgkJGQAMAEkNAA==.Destoshot:BAEBNQAECoEZAAMMAAkJSQ2zLADkAQmODQAAAwAyAHUNAAADACgAfw0AAAMAPACpDQAAAwA6AFwNAAADAAQAXQ0AAAMAHgBlDQAAAgARAKQNAAACAAQAMw0AAAMAJwANAAkJIAtIEgAkAgmODQAAAQAyAHUNAAABACgAfw0AAAEANgCpDQAAAQAbAFwNAAABAAQAXQ0AAAEAHgBlDQAAAQAEAKQNAAACAAQAMw0AAAEAJwAMAAgJJgyzLADkAQiODQAAAgAfAHUNAAACACAAfw0AAAIAPACpDQAAAgA6AFwNAAACAAMAXQ0AAAIAEgBlDQAAAQARADMNAAACABoAAAA=.',
Di='Diamondclaw:BAEANQAECgMIAwAAAA==.',
Dr='Draggionn:BAEANQAECgcICgAAAA==.Drik:BAEANQADCggIFAAAAA==.',
Dt='Dtdpreacher:BAEANQAECggIDgAAAA==.',
Du='Dudly:BAEANQAECgQIBAABNQAECgYIBgABAAAAAA==.',
Dw='Dwarfdotname:BAEANQADCgIIAgABNQAFFAQIBAABAAAAAA==.',
['Dâ']='Dâenys:BAEANQAECgUICAAAAA==.',
['Dì']='Dìssar:BAEANQAFFAIIAgAAAA==.',
Ec='Eclip:BAEANQAECgEIAQAAAA==.',
Ed='Ediot:BAEBNQAECoEYAAIOAAkJXyIMDgBMAwmODQAAAwBdAHUNAAADAGEAfw0AAAMAQwCpDQAAAwBhAFwNAAADAGEAXQ0AAAIAVQBlDQAAAgBNAKQNAAACAFAAMw0AAAMAXwAOAAkJXyIMDgBMAwmODQAAAwBdAHUNAAADAGEAfw0AAAMAQwCpDQAAAwBhAFwNAAADAGEAXQ0AAAIAVQBlDQAAAgBNAKQNAAACAFAAMw0AAAMAXwAAAA==.Edwardehlrik:BAEANQAECgQIBgABNQAECgkJGQAPAAogAA==.',
El='Elathial:BAEANQADCgEIAQAAAA==.',
Eo='Eolianna:BAEANQAECgQICAAAAA==.',
Er='Eritiya:BAEBNQAECoEXAAIQAAkJpiYOAAAKBAmODQAAAwBjAHUNAAADAGMAfw0AAAQAYwCpDQAAAwBjAFwNAAADAGMAXQ0AAAIAYwBlDQAAAQBhAKQNAAABAF8AMw0AAAMAYwAQAAkJpiYOAAAKBAmODQAAAwBjAHUNAAADAGMAfw0AAAQAYwCpDQAAAwBjAFwNAAADAGMAXQ0AAAIAYwBlDQAAAQBhAKQNAAABAF8AMw0AAAMAYwAAAA==.',
Ev='Evynne:BAEANQADCggIDgAAAA==.',
Ex='Exeuro:BAEANQABCgQIBAAAAA==.Exezen:BAEANQADCggIDAABNQAECgQICAABAAAAAA==.',
Fi='Fieslock:BAEBNQAECoEXAAMRAAkJZyVNDwCNAgmODQAAAwBiAHUNAAADAFoAfw0AAAMAWwCpDQAAAwBiAFwNAAADAGIAXQ0AAAMAYgBlDQAAAgBhAKQNAAACAGMAMw0AAAEAWQARAAYJbiVNDwCNAgaODQAAAgBiAH8NAAADAFsAXA0AAAIAYgBlDQAAAgBhAKQNAAACAGMAMw0AAAEAWQADAAUJcSFPDQDsAQWODQAAAQA1AHUNAAADAFoAqQ0AAAMAYgBcDQAAAQBXAF0NAAADAGIAAAA=.Fiessham:BAEANQADCggIDgABNQAECgkJFwARAGclAA==.Finäljüry:BAEBNQAECoETAAISAAkJDh/jBADUAgmODQAAAgBdAHUNAAADAFwAfw0AAAMAVgCpDQAAAgBaAFwNAAACAE8AXQ0AAAMASgBlDQAAAQA7AKQNAAABADUAMw0AAAIAVQASAAkJDh/jBADUAgmODQAAAgBdAHUNAAADAFwAfw0AAAMAVgCpDQAAAgBaAFwNAAACAE8AXQ0AAAMASgBlDQAAAQA7AKQNAAABADUAMw0AAAIAVQAAAA==.Fizil:BAEANQAECgIIAgAAAA==.',
Fo='Foxiez:BAEANQAECgMIAwAAAA==.',
Fr='Fridayo:BAEANQADCgYIBgABNQAECgkJIgAMAJMjAA==.Fridayoclock:BAEANQADCggICAABNQAECgkJIgAMAJMjAA==.Fridayoglock:BAEBNQAECoEiAAIMAAkJkyOVAQCmAwmODQAABABVAHUNAAAEAGEAfw0AAAQAYgCpDQAABABYAFwNAAAFAEwAXQ0AAAMAWwBlDQAAAwBgAKQNAAACAFgAMw0AAAUAYQAMAAkJkyOVAQCmAwmODQAABABVAHUNAAAEAGEAfw0AAAQAYgCpDQAABABYAFwNAAAFAEwAXQ0AAAMAWwBlDQAAAwBgAKQNAAACAFgAMw0AAAUAYQAAAA==.Fridayojock:BAEANQAECgIIAgABNQAECgkJIgAMAJMjAA==.Frohmark:BAEANQAECgYICwAAAA==.Frozenwing:BAEANQAECgMIAwAAAA==.',
['Fê']='Fêrôz:BAEANQAECgQIBgAAAA==.',
Ga='Gabbi:BAEANQAECgQIBQABNQAECgYICQABAAAAAA==.Gabriellá:BAEANQAECgQIBQABNQAECgYICQABAAAAAA==.Galeaim:BAEANQAECgUICAAAAA==.Garahn:BAEANQAECgEIAQAAAA==.',
Ge='Genericdrud:BAEANQAECggIDAAAAA==.Genericwar:BAEANQADCgcIBwABNQAECggIDAABAAAAAA==.Gerosdrk:BAEANQAECgcIEQAAAA==.Gesen:BAEANQAECgcIEwAAAA==.',
Gi='Gillihanh:BAEANQAECgEIAQABNQAECgkJHAARABAhAA==.Gillihanp:BAEANQADCggIDQABNQAECgkJHAARABAhAA==.Gillihanwl:BAEBNQAECoEcAAQRAAkJECGvFwBAAgmODQAABABfAHUNAAAEAGEAfw0AAAQAXACpDQAAAwBbAFwNAAADAFYAXQ0AAAMAVQBlDQAAAgA1AKQNAAACAEkAMw0AAAMAVQARAAcJwBqvFwBAAgeODQAAAgBfAH8NAAADAFwAXA0AAAEACQBdDQAAAQBVAGUNAAACADUApA0AAAIASQAzDQAAAQBFAAMABgmzGmYPANABBo4NAAACAEgAdQ0AAAQAYQB/DQAAAQAPAKkNAAADAFsAXA0AAAEARABdDQAAAgBBABMAAgmaIdAKAKEAAlwNAAABAFYAMw0AAAIAVQAAAA==.Gilo:BAEANQAECggIEQAAAA==.Gingybear:BAEANQADCgYIBgABNQAECgIIAgABAAAAAA==.Gingysmalls:BAEANQAECgIIAgAAAA==.',
Gl='Gloomrift:BAEANQADCgUIBQABNQAECgQIBQABAAAAAA==.Gloomwick:BAEANQAECgQIBQAAAA==.',
Go='Goonrat:BAEANQAECgYIBgAAAA==.Gorelguul:BAEANQADCggIDQAAAA==.',
Gr='Greenbeansgo:BAEANQAECgYICQAAAA==.Gregmâge:BAEBNQAECoEYAAIOAAkJ5h2wEQAxAwmODQAAAwBgAHUNAAADAGEAfw0AAAMAUQCpDQAAAwBaAFwNAAADAFkAXQ0AAAMATABlDQAAAgA3AKQNAAABABMAMw0AAAMAUgAOAAkJ5h2wEQAxAwmODQAAAwBgAHUNAAADAGEAfw0AAAMAUQCpDQAAAwBaAFwNAAADAFkAXQ0AAAMATABlDQAAAgA3AKQNAAABABMAMw0AAAMAUgAAAA==.Grisdele:BAEANQADCgYIDQAAAA==.',
Gu='Guildmaster:BAEBNQAFFIEJAAIUAAYJqhBkAQCuAQaODQAAAgA3AHUNAAACAEIAfw0AAAEAFwCpDQAAAgA4AFwNAAABAC0AMw0AAAEACQAUAAYJqhBkAQCuAQaODQAAAgA3AHUNAAACAEIAfw0AAAEAFwCpDQAAAgA4AFwNAAABAC0AMw0AAAEACQAAAA==.',
Ha='Hastedtome:BAEANQADCgYICAAAAA==.Hazmina:BAEANQADCgcIDwABNQADCggICAABAAAAAA==.',
He='Heartshine:BAEANQAECgUIBwAAAA==.Hekid:BAEANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Hu='Hughjanius:BAEANQAECgQIDQAAAA==.Hugron:BAEANQAECgUIBQAAAA==.Humf:BAEANQAECgQIBAAAAA==.Huuky:BAEBNQAECoEYAAMMAAkJOh2FEwCKAgmODQAAAwBWAHUNAAADAF4Afw0AAAMAXgCpDQAAAwBBAFwNAAADAB8AXQ0AAAMASwBlDQAAAgBIAKQNAAABADYAMw0AAAMAYgAMAAgJTxuFEwCKAgiODQAAAgBRAHUNAAACAF4Afw0AAAMAXgCpDQAAAgBBAFwNAAADAB8AXQ0AAAIASABlDQAAAQAVADMNAAADAGIADQAGCVEcJBUA7QEGjg0AAAEAVgB1DQAAAQBRAKkNAAABAEAAXQ0AAAEASwBlDQAAAQBIAKQNAAABADYAAAA=.',
['Hë']='Hëxster:BAEANQAECgcIDgAAAA==.',
Ic='Icemonkey:BAEANQAECgUICAABNQAECgYICwABAAAAAA==.',
Im='Imhopeless:BAEBNQAECoEYAAIOAAkJtyPtBgCMAwmODQAABABaAHUNAAADAFsAfw0AAAMAYQCpDQAAAwBSAFwNAAACAFcAXQ0AAAIAXABlDQAAAgBZAKQNAAACAFwAMw0AAAMAYQAOAAkJtyPtBgCMAwmODQAABABaAHUNAAADAFsAfw0AAAMAYQCpDQAAAwBSAFwNAAACAFcAXQ0AAAIAXABlDQAAAgBZAKQNAAACAFwAMw0AAAMAYQAAAA==.Immortalíty:BAEANQAECgYICgAAAA==.',
Is='Ishanna:BAEANQAECgYIBgABNQAFFAYIDAACABUXAA==.',
Je='Jerstadh:BAEANQAECgYICwAAAA==.',
Ji='Jinarcana:BAEANQAECggIEAAAAA==.Jirste:BAEANQAECgUIBwABNQAECgYICwABAAAAAA==.',
Jj='Jjuussttiinn:BAEANQAECgMIBAABNQABCgEIAQABAAAAAA==.',
Ka='Kalondk:BAEANQAECgMIAwAAAA==.Kayemk:BAEANQAECgUIBwABNQAFFAEIAQABAAAAAA==.Kazereth:BAEANQAFFAIIAgABNQAECgYIBgABAAAAAA==.Kaíyo:BAEANQAECgQIBQAAAA==.',
Ki='Killadeathjr:BAEANQADCgIIAQABNQADCggIDQABAAAAAA==.Kiví:BAEBNQAECoEVAAIVAAkJKhsoCAAKAwmODQAAAwA/AHUNAAACAEkAfw0AAAIATgCpDQAAAwBHAFwNAAADAFoAXQ0AAAMAVQBlDQAAAgBOAKQNAAACABgAMw0AAAEAOwAVAAkJKhsoCAAKAwmODQAAAwA/AHUNAAACAEkAfw0AAAIATgCpDQAAAwBHAFwNAAADAFoAXQ0AAAMAVQBlDQAAAgBOAKQNAAACABgAMw0AAAEAOwAAAA==.',
Ky='Kylealtlock:BAEANQAECgIIAgABNQAFFAUIBwATAJgKAA==.Kyleblinks:BAEANQAECgcIDQABNQAFFAUIBwATAJgKAA==.Kylewl:BAECNQAFFIEHAAQTAAUJmApdAACxAAWODQAAAgAiAHUNAAABAAQAfw0AAAEAGACpDQAAAgA0ADMNAAABABIAEwACCf0NXQAAsQACqQ0AAAEANAAzDQAAAQASAAMAAgkhB+cDAKYAAnUNAAABAAQAqQ0AAAEAHwARAAIJkQuUBwCdAAKODQAAAgAiAH8NAAABABgANQAECoEcAAQTAAkJIyM6AgAFAgADAAYJ9hvpCQAgAgATAAYJtRs6AgAFAgARAAQJ0B6UPgBVAQAAAA==.Kyntarlus:BAEANQADCgYIBgAAAA==.Kysarra:BAEANQAECgQIBAABNQAFFAUIBgADAEkdAA==.Kyssandra:BAECNQAFFIEGAAQDAAUJSR3cAQDHAAWODQAAAQBIAHUNAAABAEoAfw0AAAEAPwCpDQAAAgBUADMNAAABAFAAAwACCfYe3AEAxwACdQ0AAAEASgCpDQAAAgBUABEAAgmLGnMFALMAAo4NAAABAEgAfw0AAAEAPwATAAEJbR8bAQBjAAEzDQAAAQBQADUABAqBQwAEAwAJCZsmBAAAHAQAAwAJCYkmBAAAHAQAEQAFCdokBBwAHgIAEwAECSclMQMAtgEAAAA=.',
Le='Levence:BAEANQAECgQIBAAAAA==.',
Li='Libx:BAEANQAFFAEIAgABNQAECgcIDwABAAAAAA==.Libzvoker:BAEANQAECgMIAwAAAA==.Lilyythe:BAEANQAECgEIAQABNQAECgQIBQABAAAAAA==.Listhuh:BAEANQADCgYIBwABNQAFFAQIBAABAAAAAA==.',
Lo='Lokrot:BAEANQADCggICAABNQAECgQICgABAAAAAA==.',
Lu='Luneli:BAEANQADCggIFwABNQAECgkJFQAVACobAA==.Lunilocks:BAEANQAECggIDgABNQAECgkJFQAVACobAA==.Luycant:BAEANQADCggICQABNQAECgQICQABAAAAAA==.',
['Lø']='Løäding:BAEANQAECgYIDgAAAA==.',
Ma='Maqluba:BAEANQAECgcIAQABNQAFFAEIAQABAAAAAA==.Maybeary:BAEANQADCgMIAwABNQAECgEIAQABAAAAAA==.Mazn:BAEANQADCgUIBwABNQAECgIIAgABAAAAAA==.',
Me='Me:BAEANQAECgYICQABNQAFFAYICQAUAKoQAA==.Mecönium:BAEANQAECgQIBQAAAA==.Menaray:BAEANQAECgQIBAABNQAECgYIDQABAAAAAA==.Meppi:BAEBNQAECoEWAAMVAAkJZx+zAwBgAwmODQAAAwBbAHUNAAADAGEAfw0AAAMAUwCpDQAAAwBgAFwNAAACAFQAXQ0AAAMAWgBlDQAAAgA8AKQNAAABAC0AMw0AAAIASgAVAAkJZx+zAwBgAwmODQAAAgBbAHUNAAACAGEAfw0AAAIAUwCpDQAAAwBgAFwNAAABAFQAXQ0AAAIAWgBlDQAAAgA8AKQNAAABAC0AMw0AAAEASgAPAAYJEB2/JwANAgaODQAAAQBOAHUNAAABAEsAfw0AAAEAUwBcDQAAAQA/AF0NAAABADkAMw0AAAEAVwAAAA==.',
Mi='Mikethepure:BAEANQAECgQIDQAAAA==.',
Mo='Momodh:BAEANQAECggIBwABNQAFFAEIAQABAAAAAA==.Momussie:BAEANQAFFAEIAQAAAA==.Monsternos:BAEANQAECgcIAgAAAA==.Moonblase:BAEANQAECgYICwAAAA==.Morchies:BAEANQADCgcIDQABNQAECgYICQABAAAAAA==.Mossberg:BAEBNQAECoEXAAIMAAkJUSX2AADEAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYQCpDQAAAwBhAFwNAAADAGMAXQ0AAAIAWQBlDQAAAgBgAKQNAAABAE8AMw0AAAMAYwAMAAkJUSX2AADEAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYQCpDQAAAwBhAFwNAAADAGMAXQ0AAAIAWQBlDQAAAgBgAKQNAAABAE8AMw0AAAMAYwAAAA==.Mousehopium:BAEANQADCgcIBgAAAA==.',
My='Mynïel:BAEANQADCgUIBQAAAA==.',
['Mú']='Múrdërhôbô:BAEANQAECgEIAQAAAA==.',
Na='Nahuall:BAEANQADCgcIEQAAAA==.Natralana:BAEANQADCgUIBQABNQADCggIDQABAAAAAA==.',
Ne='Necromalt:BAEANQADCgYIBgABNQAECgQICQABAAAAAA==.Nelfling:BAEANQAECgQICQAAAA==.',
No='Norxxonx:BAEANQADCgQIBwABNQAECgUICwABAAAAAA==.Notrogtuah:BAEANQAECgIIAwAAAA==.Noxxiq:BAEANQAECggIBwAAAA==.',
Ny='Nynaevy:BAEANQAECgMIAwABNQAECgQICAABAAAAAA==.',
Oh='Ohmspacedk:BAEANQAECgIIAwAAAA==.',
Om='Omnidor:BAEANQAECgUICwAAAA==.',
Or='Orphanmakr:BAEANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Ot='Otint:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Pa='Painkus:BAEANQAECgEIAQABNQAECggICwABAAAAAA==.Pawtection:BAEANQADCgcIBwABNQAECgQIDQABAAAAAA==.',
Pe='Pengadin:BAEANQAFFAIIAgAAAA==.Pensly:BAEANQAECgYIBgAAAA==.Petrsykora:BAEANQADCggICQABNQAECgkJGgADAPMjAA==.',
Po='Pocketdealz:BAEANQAECgYIDAAAAA==.Pocketzzmeat:BAEANQAECgQIBAABNQAECgkJGAAVAIoYAA==.Pocketzzmonk:BAEANQAECgUICQABNQAECgkJGAAVAIoYAA==.Pocketzzsham:BAEANQAECgQICAABNQAECgkJGAAVAIoYAA==.Pontíf:BAEANQAECgEIAQAAAA==.',
Pr='Praxicide:BAEANQADCgMIAwABNQADCgYIEQABAAAAAA==.Praxivoker:BAEANQADCgYIEQAAAA==.Prinkkus:BAEANQAECggICwAAAA==.',
Pu='Purpleflurp:BAEANQAECgQIBAABNQAFFAEIAQABAAAAAA==.',
Qu='Quietplease:BAEANQAECgIIAgAAAA==.',
Re='Redryder:BAEANQAECgMIBAABNQABCgEIAQABAAAAAA==.Rehobooam:BAEANQAECgIIAgABNQAECgQICAABAAAAAA==.Relreaux:BAEANQAECggIEQAAAA==.Revthnksimai:BAEANQAECgUIBQABNQAECgYICwABAAAAAA==.',
Ro='Robvryn:BAEANQADCgQIBAABNQAECgkJFwAMAFElAA==.Roidington:BAEANQAECgcICwAAAA==.Rolyon:BAEBNQAECoEZAAIPAAkJISVlAQDWAwmODQAAAwBiAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAwBjAKQNAAACAEEAMw0AAAIAXwAPAAkJISVlAQDWAwmODQAAAwBiAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBjAFwNAAADAGMAXQ0AAAMAYwBlDQAAAwBjAKQNAAACAEEAMw0AAAIAXwAAAA==.Rortimag:BAEANQAECgMIBAAAAA==.Rortimis:BAEANQADCggIDQABNQAECgMIBAABAAAAAA==.Rowlond:BAEANQADCgYIDgAAAA==.',
Ru='Rubmyhots:BAEANQAECggIEAAAAA==.',
Ry='Ryecoke:BAEANQAECgUIBQAAAA==.Rykala:BAEANQAECgUIBQABNQAECgcIEQABAAAAAA==.Rykemage:BAEANQAECgEIAQABNQAECgcIEQABAAAAAA==.',
Sa='Sahjurn:BAEANQADCgIIAgABNQAECgYICwABAAAAAA==.Savory:BAEANQAECgQIBQAAAA==.',
Sc='Scooty:BAEANQAECgcIDAABNQAFFAEIAQABAAAAAA==.',
Se='Senndh:BAEBNQAECoEbAAQWAAkJdCPgAQB9AgmODQAABABgAHUNAAAEAGIAfw0AAAQAWgCpDQAABABfAFwNAAADAFEAXQ0AAAMAVQBlDQAAAgBXAKQNAAABAFUAMw0AAAIAXwAWAAcJph7gAQB9AgeODQAAAgBTAHUNAAACAFkAfw0AAAMARwCpDQAAAgBSAFwNAAADAFEAXQ0AAAMAVQBlDQAAAQA2ABcABQl0JHUOACACBY4NAAABAGAAdQ0AAAEAYgB/DQAAAQBaAKkNAAABAF8ApA0AAAEAVQAEAAUJyiNLHQC7AQWODQAAAQBZAHUNAAABAF4AqQ0AAAEAWgBlDQAAAQBXADMNAAACAF8AAAA=.Settek:BAEANQAFFAEIAQAAAA==.',
Sh='Shadizar:BAEANQAECgcIEQAAAA==.Shambith:BAEANQAECgUICwAAAA==.Shikiryougi:BAEANQAECggIDAAAAA==.Shingrip:BAEANQADCgcIEgAAAA==.Shyviolet:BAEANQAECgIIAgAAAA==.',
Si='Sioken:BAEANQAECgYIDAAAAA==.',
Sm='Smouke:BAEANQAECgQIBAABNQAECgYIBgABAAAAAA==.',
So='Sokosage:BAEANQADCgIIAgABNQAECgYICQABAAAAAA==.Somegal:BAEANQAECgEIAQABNQAECgQICgABAAAAAA==.',
Sp='Sparkyboomm:BAEANQAECgEIAQABNQAECgcICgABAAAAAA==.Splather:BAEANQAECgIIAwAAAA==.',
Sq='Squirtamus:BAEANQAECgQICAABNQAECggIDgABAAAAAA==.Squirtamussy:BAEANQAECggIDgAAAA==.Squrlshamz:BAEANQAECgQIBQAAAA==.Sqz:BAEANQAECgUIBwAAAA==.',
St='Staskyfel:BAEANQADCggICQABNQAFFAEIAQABAAAAAA==.Staskylock:BAEANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Staskym:BAEANQAFFAEIAQAAAA==.Stebhunter:BAEANQADCgUIBQABNQAECgkJGAAKAHAjAA==.Stonetides:BAEANQAECgQICAAAAA==.Stormdoc:BAEANQADCgMIAwABNQAECgMIAwABAAAAAA==.Strongpal:BAEANQAECgcICwABNQAECggIDwABAAAAAA==.',
Su='Sudac:BAEANQADCgcIDAABNQAECgEIAQABAAAAAA==.',
Sy='Sykora:BAEBNQAECoEaAAMDAAkJ8yNsAAC6AwmODQAABABiAHUNAAAEAGAAfw0AAAMAYQCpDQAABABhAFwNAAADAF8AXQ0AAAIAWgBlDQAAAgBgAKQNAAABADsAMw0AAAMAXwADAAkJ8yNsAAC6AwmODQAABABiAHUNAAAEAGAAfw0AAAIAYQCpDQAABABhAFwNAAADAF8AXQ0AAAIAWgBlDQAAAgBgAKQNAAABADsAMw0AAAMAXwARAAEJ8xVPjwA1AAF/DQAAAQA4AAAA.Sylrisia:BAEANQAFFAEIAQAAAA==.',
['Sö']='Sömegüy:BAEANQAECgYICgABNQAECgQICgABAAAAAA==.',
Ta='Taliendra:BAEANQAECgEIAQAAAA==.',
Te='Tegualbrew:BAEANQADCgYIBgABNQAECgYICwABAAAAAA==.Tegualdruid:BAEANQAECgYICwAAAA==.Tegualmage:BAEANQADCgYIBgABNQAECgYICwABAAAAAA==.Temuula:BAEANQADCggIDAABNQAFFAEIAQABAAAAAA==.Tequíla:BAEANQADCggIEQAAAA==.',
Th='Thefonzo:BAEANQAECgcIEQAAAA==.Theldrassen:BAEANQAECgQIBgAAAA==.Thrazad:BAEANQADCgEIAQABNQAECgQICQABAAAAAA==.',
To='Torjack:BAEANQAECgQICAAAAA==.Toströng:BAEANQAECggIDwAAAA==.',
Tr='Triillaiin:BAEANQADCgYIBgAAAA==.Trovyria:BAEANQAECggIEQAAAA==.',
Tw='Twînkerbell:BAEANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ty='Tyromezz:BAEANQAFFAQIBAAAAA==.',
['Tá']='Tálõn:BAEANQADCggICAAAAA==.',
['Tâ']='Tâhra:BAEANQADCgYIBQABNQADCgYIDQABAAAAAA==.',
['Tý']='Týýr:BAEANQAECgQIBQAAAA==.',
Va='Valkdk:BAEANQADCggIDwAAAA==.Valkhunter:BAEANQAECgEIAQABNQADCggIDwABAAAAAA==.Valksham:BAEANQAECgQICQABNQADCggIDwABAAAAAA==.Vamprinkus:BAEBNQAFFIEHAAIUAAUJKhPGAQCLAQWODQAAAgA8AHUNAAABABsAfw0AAAEAJgCpDQAAAgAjADMNAAABAFMAFAAFCSoTxgEAiwEFjg0AAAIAPAB1DQAAAQAbAH8NAAABACYAqQ0AAAIAIwAzDQAAAQBTAAE1AAQKCAgLAAEAAAAA.Vayeatee:BAEBNQAECoEZAAIPAAkJCiCABgBaAwmODQAAAwBfAHUNAAADAGAAfw0AAAMASwCpDQAAAwBZAFwNAAADAFsAXQ0AAAMATwBlDQAAAgA8AKQNAAACADUAMw0AAAMAYQAPAAkJCiCABgBaAwmODQAAAwBfAHUNAAADAGAAfw0AAAMASwCpDQAAAwBZAFwNAAADAFsAXQ0AAAMATwBlDQAAAgA8AKQNAAACADUAMw0AAAMAYQAAAA==.',
Ve='Vehqq:BAEANQAECgMIAwABNQAECgkJHwADAMcgAA==.Vehqqdk:BAEANQAECgEIAQABNQAECgkJHwADAMcgAA==.Vehqqw:BAEBNQAECoEfAAQDAAkJxyAgAgAVAwmODQAABgBhAHUNAAAEAGIAfw0AAAMAVACpDQAABABPAFwNAAADAGEAXQ0AAAQAYQBlDQAAAgA+AKQNAAACACsAMw0AAAMAXQADAAkJHRsgAgAVAwmODQAAAQA0AHUNAAAEAGIAfw0AAAEATACpDQAABABPAFwNAAABAGEAXQ0AAAMAQQBlDQAAAQAQAKQNAAACACsAMw0AAAIAXQARAAUJRBtELQCuAQWODQAABQBhAH8NAAACAFQAXA0AAAEABwBdDQAAAQBhAGUNAAABAD4AEwACCUoVVAwAhQACXA0AAAEALAAzDQAAAQBAAAAA.Vengmaxxing:BAEANQAECgQIBAAAAA==.Verekoo:BAEANQAECgcIDwAAAA==.',
Vi='Viveus:BAEANQAECgQICQAAAA==.Viveush:BAEANQADCgQIBwABNQAECgQICQABAAAAAA==.',
Vo='Vonsnuffles:BAEBNQAECoEWAAIMAAkJiiTPAQCcAwmODQAAAwBaAHUNAAADAF4Afw0AAAMAYACpDQAAAwBhAFwNAAACAFwAXQ0AAAIAYQBlDQAAAgBjAKQNAAACAFUAMw0AAAIAVwAMAAkJiiTPAQCcAwmODQAAAwBaAHUNAAADAF4Afw0AAAMAYACpDQAAAwBhAFwNAAACAFwAXQ0AAAIAYQBlDQAAAgBjAKQNAAACAFUAMw0AAAIAVwABNQAECgkJFgAMAIokAA==.',
Wa='Wagovinci:BAEANQAECggIDgAAAA==.Waterrblastr:BAEANQADCgYIBgABNQABCgEIAQABAAAAAA==.',
We='Wetbox:BAEBNQAECoEYAAIQAAkJUxxEDADGAgmODQAAAwBDAHUNAAADAF0Afw0AAAMAVgCpDQAAAwBVAFwNAAADAFQAXQ0AAAMARQBlDQAAAgAlAKQNAAABADgAMw0AAAMASQAQAAkJUxxEDADGAgmODQAAAwBDAHUNAAADAF0Afw0AAAMAVgCpDQAAAwBVAFwNAAADAFQAXQ0AAAMARQBlDQAAAgAlAKQNAAABADgAMw0AAAMASQAAAA==.',
Wi='Wildeclaw:BAEANQAECgMIAwAAAA==.Windowblight:BAEANQAECgMIBAAAAA==.Windwärd:BAEANQAECggIDgABNQADCggIEQABAAAAAA==.',
Wo='Wokowage:BAEANQAECgYICQAAAA==.',
['Wé']='Wébs:BAEANQADCggIEgAAAA==.',
Xa='Xalthura:BAEANQADCgUIBgABNQAECgQICQABAAAAAA==.',
Xe='Xernwar:BAEANQABCgIIAgABNQAECgkJGgAUAO0jAA==.',
Yv='Yvairel:BAEBNQAECoEXAAIKAAkJEh0fCAAyAwmODQAAAwBaAHUNAAADAEsAfw0AAAMASwCpDQAAAwBXAFwNAAADAFMAXQ0AAAIAVABlDQAAAgA+AKQNAAABACQAMw0AAAMASQAKAAkJEh0fCAAyAwmODQAAAwBaAHUNAAADAEsAfw0AAAMASwCpDQAAAwBXAFwNAAADAFMAXQ0AAAIAVABlDQAAAgA+AKQNAAABACQAMw0AAAMASQABNQAFFAIIAgABAAAAAA==.',
Za='Zaffia:BAEBNQAECoEXAAIYAAkJ1iFwAACQAwmODQAAAwBcAHUNAAADAGMAfw0AAAMAUQCpDQAAAwBgAFwNAAACAGEAXQ0AAAIAUABlDQAAAgBKAKQNAAACAEEAMw0AAAMAXAAYAAkJ1iFwAACQAwmODQAAAwBcAHUNAAADAGMAfw0AAAMAUQCpDQAAAwBgAFwNAAACAGEAXQ0AAAIAUABlDQAAAgBKAKQNAAACAEEAMw0AAAMAXAAAAA==.Zatheor:BAEANQAECgUIBwABNQAECgkJFwAYANYhAA==.',
Ze='Zedj:BAEANQAECgYICAAAAA==.',
Zi='Zilthorn:BAEANQAECgMIBAABNQABCgEIAQABAAAAAA==.Zimbzy:BAEANQAECgYIDAAAAA==.Zirleficent:BAEANQADCgcIEgAAAA==.',
['Åd']='Ådaptive:BAEANQAECgIIAwAAAA==.',
['Ír']='Íranem:BAEANQAECgYIDQAAAA==.',
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
