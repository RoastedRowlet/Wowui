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

local lookup = {'Druid-Feral','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Evoker-Preservation','Warlock-Demonology','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Warrior-Arms','Rogue-Outlaw','Paladin-Retribution',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-09-29',data={Ae='Aesinth:BAEANQADCgMIAwABNQAECggIGgABAMIWAA==.',
Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEANQAECgYIEAAAAA==.Algebra:BAEBNQAECoEZAAMCAAkKriLrMQALAwmODQAABQBiAHUNAAADAFYAfw0AAAIAXACpDQAAAwBdAFwNAAACAFMAXQ0AAAIAWABlDQAAAwBeAKQNAAACAEYAMw0AAAMAXAACAAkKbiDrMQALAwmODQAABQBiAHUNAAACAE4Afw0AAAIAXACpDQAAAgBXAFwNAAACAFMAXQ0AAAEAMgBlDQAAAwBeAKQNAAACAEYAMw0AAAMAXAADAAMK5SItGADwAAN1DQAAAQBWAKkNAAABAF0AXQ0AAAEAWAAAAA==.',
Ar='Araakki:BAEANQAECgIIBQAAAA==.Aradell:BAEBNQAECoEvAAIEAAkKzhUWUABvAQmODQAACABSAHUNAAAHAEQAfw0AAAcARwCpDQAABwA4AFwNAAAEAEIAXQ0AAAQAOgBlDQAAAwABAKQNAAABAA8AMw0AAAYAUQAEAAkKzhUWUABvAQmODQAACABSAHUNAAAHAEQAfw0AAAcARwCpDQAABwA4AFwNAAAEAEIAXQ0AAAQAOgBlDQAAAwABAKQNAAABAA8AMw0AAAYAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJLwAEAM4VAA==.Ariizi:BAEANQAECgMIBAAAAA==.Artam:BAEANQADCggICQABNQAFFAYIFQAFAN8ZAA==.Arteron:BAEANQADCggICAABNQAFFAYIEAAGAHciAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFIEQAAIHAAYKxhsbBAASAgaODQAABQBbAHUNAAADADEAfw0AAAEAPQCpDQAAAwBfAFwNAAACAEMAMw0AAAIAPAAHAAYKxhsbBAASAgaODQAABQBbAHUNAAADADEAfw0AAAEAPQCpDQAAAwBfAFwNAAACAEMAMw0AAAIAPAA1AAQKgUIAAwcACQq9JX4DALgDAAcACQq9JX4DALgDAAgABAqgD/Y4AOsAAAAA.',
Ay='Ayoade:BAECNQAFFIEZAAIJAAcKEhcoAgBVAgeODQAABQA3AHUNAAAEADcAfw0AAAQAWACpDQAABQBXAFwNAAACAC4AXQ0AAAEACAAzDQAABABHAAkABwoSFygCAFUCB44NAAAFADcAdQ0AAAQANwB/DQAABABYAKkNAAAFAFcAXA0AAAIALgBdDQAAAQAIADMNAAAEAEcANQAECoEqAAIJAAkKtyMqAgCVAwAJAAkKtyMqAgCVAwAAAA==.',
Az='Azzurel:BAEBNQAECoEeAAIKAAkK5xGEQgBKAgmODQAABAAuAHUNAAAEAEUAfw0AAAMAJwCpDQAABAAqAFwNAAAEADMAXQ0AAAMAMABlDQAAAgATAKQNAAABACsAMw0AAAUAMgAKAAkK5xGEQgBKAgmODQAABAAuAHUNAAAEAEUAfw0AAAMAJwCpDQAABAAqAFwNAAAEADMAXQ0AAAMAMABlDQAAAgATAKQNAAABACsAMw0AAAUAMgAAAA==.',
Ba='Babaghanouj:BAEBNQAECoEaAAMLAAcKFhLFJAC4AQeODQAABQBBAHUNAAADACsAfw0AAAMAIwCpDQAABAApAFwNAAAEADgAXQ0AAAIAIwAzDQAABQAuAAsABwoWEsUkALgBB44NAAAEAEEAdQ0AAAMAKwB/DQAAAwAjAKkNAAAEACkAXA0AAAEAOABdDQAAAQAjADMNAAADAC4ABQAEClog6noAOAEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Bayati:BAEBNQAECoEYAAIBAAgKPyCXBAD1AgiODQAABABgAHUNAAAEAFoAfw0AAAQAWwCpDQAABABcAFwNAAABAEkAXQ0AAAEAQABlDQAAAwA4ADMNAAADAF8AAQAICj8glwQA9QIIjg0AAAQAYAB1DQAABABaAH8NAAAEAFsAqQ0AAAQAXABcDQAAAQBJAF0NAAABAEAAZQ0AAAMAOAAzDQAAAwBfAAAA.',
Be='Benghi:BAEBNQAECoEiAAMMAAkK6Bs9IwALAgmODQAABgBaAHUNAAAEAEsAfw0AAAQAMwCpDQAABABaAFwNAAADAEwAXQ0AAAMAVgBlDQAABAA5AKQNAAACACEAMw0AAAQAUQAMAAcKYBk9IwALAgd1DQAAAQA+AH8NAAABAC8AqQ0AAAMAWgBcDQAAAgBMAF0NAAADAFYAZQ0AAAQAOQCkDQAAAgAhAA0ABgqeFyYgAKUBBo4NAAAGAFoAdQ0AAAMASwB/DQAAAwAzAKkNAAABAA0AXA0AAAEAMwAzDQAABABRAAAA.Bestcase:BAECNQAFFIENAAIOAAUK1g8ZBQB1AQWODQAABABIAHUNAAADABIAfw0AAAIABQCpDQAAAwA+ADMNAAABACoADgAFCtYPGQUAdQEFjg0AAAQASAB1DQAAAwASAH8NAAACAAUAqQ0AAAMAPgAzDQAAAQAqADUABAqBJgADDgAJCs4hAgkAGgMADgAJCs4hAgkAGgMADwABChAHqysAIQAAAAA=.',
Br='Brigbala:BAEANQAECgEIAQAAAA==.',
Bu='Burnassus:BAEANQADCggICAABNQAECgUIDQAQAAAAAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQAQAAAAAA==.',
Co='Coggettle:BAEANQADCggIIgABNQAECggIHQARAJghAA==.',
Cr='Crustage:BAEANQAECgUICQAAAA==.',
Du='Dumblefrost:BAEANQAECgYIDAAAAA==.',
Eh='Ehanee:BAEANQAECgcIDQAAAA==.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECoEeAAIGAAkKCB4eGAAPAwmODQAABQBTAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAAAwA/AKQNAAACAC8AMw0AAAQATQAGAAkKCB4eGAAPAwmODQAABQBTAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAAAwA/AKQNAAACAC8AMw0AAAQATQABNQAECgUICQAQAAAAAA==.',
Fs='Fshi:BAECNQAFFIEIAAIBAAYKCRNEAAAcAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAIALwABAAYKCRNEAAAcAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAIALwA1AAQKgTsAAwEACQoXJkkAAPgDAAEACQoXJkkAAPgDAAcABApvGlRTADsBAAAA.',
Gr='Greatanubis:BAEANQAECgcIDQAAAA==.Grumli:BAEBNQAECoEjAAMSAAkKchsWIAC0AgmODQAABgBNAHUNAAAFAFcAfw0AAAQAWwCpDQAABABLAFwNAAAEAFsAXQ0AAAMASQBlDQAABAA6AKQNAAACAEoAMw0AAAMAAgASAAkKchsWIAC0AgmODQAABgBNAHUNAAAFAFcAfw0AAAQAWwCpDQAABABLAFwNAAAEAFsAXQ0AAAIASQBlDQAAAwA6AKQNAAACAEoAMw0AAAIAAgAGAAMKiBA6uwDBAANdDQAAAQA2AGUNAAABAAkAMw0AAAEAPwABNQADCgUIBQAQAAAAAA==.Grummel:BAEANQADCgUIBQAAAA==.Grunzi:BAEANQAECggICAAAAA==.',
Ha='Halts:BAEANQAECgUICgABNQAECgkJJAASAHkeAA==.',
Il='Ilnarya:BAEANQADCgcICAABNQADCggIEwAQAAAAAA==.',
Im='Imei:BAEANQADCgIIAgABNQAFFAUIDgATAIgeAA==.',
Ja='Jail:BAEBNQAECoEZAAICAAkKwCFZGwBWAwmODQAABgBXAHUNAAADAF8Afw0AAAIAYgCpDQAAAwBgAFwNAAACAFUAXQ0AAAIATwBlDQAAAwBHAKQNAAABAEMAMw0AAAMAXwACAAkKwCFZGwBWAwmODQAABgBXAHUNAAADAF8Afw0AAAIAYgCpDQAAAwBgAFwNAAACAFUAXQ0AAAIATwBlDQAAAwBHAKQNAAABAEMAMw0AAAMAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAYICwAUALMVAA==.',
Jl='Jlycett:BAEBNQAECoEZAAISAAkK9iEICgBRAwmODQAAAgBbAHUNAAADAGEAfw0AAAMAYgCpDQAAAwBXAFwNAAACAFIAXQ0AAAUAYgBlDQAAAwBjAKQNAAADAEYAMw0AAAEAOAASAAkK9iEICgBRAwmODQAAAgBbAHUNAAADAGEAfw0AAAMAYgCpDQAAAwBXAFwNAAACAFIAXQ0AAAUAYgBlDQAAAwBjAKQNAAADAEYAMw0AAAEAOAABNQAFFAcIGQAJABIXAA==.',
Ka='Kanavi:BAECNQAFFIEOAAITAAUKiB5bBwDjAQWODQAABQBhAHUNAAACAFkAfw0AAAEAMgCpDQAAAwBFADMNAAADAFQAEwAFCogeWwcA4wEFjg0AAAUAYQB1DQAAAgBZAH8NAAABADIAqQ0AAAMARQAzDQAAAwBUADUABAqBIAACEwAJCpQkWA0AfAMAEwAJCpQkWA0AfAMAAAA=.Kantai:BAEANQADCgYICQABNQAFFAUIDgATAIgeAA==.',
Kn='Knackered:BAEANQAECgUICwABNQABCgIIAgAQAAAAAA==.',
Kr='Kregazi:BAEBNQAECoEfAAIEAAgKnR2wHQCPAgiODQAABQBEAHUNAAAFAFAAfw0AAAQATACpDQAABABNAFwNAAADAFUAXQ0AAAMAWgBlDQAAAgAxADMNAAAFAE0ABAAICp0dsB0AjwIIjg0AAAUARAB1DQAABQBQAH8NAAAEAEwAqQ0AAAQATQBcDQAAAwBVAF0NAAADAFoAZQ0AAAIAMQAzDQAABQBNAAAA.',
Lo='Lobotomight:BAEANQAECgcIDQABNQAFFAIIAgAQAAAAAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgYIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIDwABNQAFFAcIGQAJABIXAA==.',
Me='Merarite:BAEBNQAECoEgAAIEAAgKfBVEMAARAgiODQAABQA1AHUNAAAFADkAfw0AAAQANACpDQAABQBCAFwNAAAEAEYAXQ0AAAMAIABlDQAAAgAsADMNAAAEAD0ABAAICnwVRDAAEQIIjg0AAAUANQB1DQAABQA5AH8NAAAEADQAqQ0AAAUAQgBcDQAABABGAF0NAAADACAAZQ0AAAIALAAzDQAABAA9AAAA.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECgYIDAAQAAAAAA==.',
Na='Nadasa:BAEBNQAECoEuAAIVAAgKFiJTHgAcAwiODQAACABaAHUNAAAGAF0Afw0AAAYAYQCpDQAABgBQAFwNAAAFAFkAXQ0AAAMARwBlDQAABQBTADMNAAAHAFsAFQAIChYiUx4AHAMIjg0AAAgAWgB1DQAABgBdAH8NAAAGAGEAqQ0AAAYAUABcDQAABQBZAF0NAAADAEcAZQ0AAAUAUwAzDQAABwBbAAAA.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAAQAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgQIBAABNQABCgYICAAQAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Palashin:BAEANQAECgMIAwABNQAECgkJJAASAHkeAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECgUIDQAQAAAAAA==.',
Po='Potatogogue:BAECNQAFFIEIAAMGAAUKVBEoEQDpAAWODQAAAwAuAHUNAAABAA4Afw0AAAEAMgCpDQAAAgAcAFwNAAABAFEABgADCqsLKBEA6QADjg0AAAMALgB1DQAAAQAOAKkNAAACABwAEgACCloUXRMArgACfw0AAAEASwBcDQAAAQAcADUABAqBHgADBgAJCiMgjhgADAMABgAJCiMgjhgADAMAEgACClAfVcQAiwAAATUABRQBCAEAEAAAAAA=.',
Ri='Ritren:BAEANQAECgMIAwABNQAECgcIDgAQAAAAAA==.',
Ro='Roogies:BAEBNQAECoExAAIMAAkKLSQ4AwCEAwmODQAACQBdAHUNAAAHAGEAfw0AAAcAYACpDQAABgBbAFwNAAAEAF0AXQ0AAAUAYwBlDQAABABWAKQNAAAEAFYAMw0AAAMAVwAMAAkKLSQ4AwCEAwmODQAACQBdAHUNAAAHAGEAfw0AAAcAYACpDQAABgBbAFwNAAAEAF0AXQ0AAAUAYwBlDQAABABWAKQNAAAEAFYAMw0AAAMAVwAAAA==.',
Ru='Runoka:BAEBNQAECoEaAAIBAAgKwhbbCABVAgiODQAABQAwAHUNAAAFAEsAfw0AAAQAUACpDQAAAwBEAFwNAAAEAEMAXQ0AAAIAHgBlDQAAAQAbADMNAAACAEQAAQAICsIW2wgAVQIIjg0AAAUAMAB1DQAABQBLAH8NAAAEAFAAqQ0AAAMARABcDQAABABDAF0NAAACAB4AZQ0AAAEAGwAzDQAAAgBEAAAA.',
Se='Senzarial:BAEANQAECgEIAQABNQAFFAYIEAAHAMYbAA==.Serynytee:BAEANQAECgYICwAAAA==.',
Sh='Shinseer:BAEBNQAECoEkAAISAAkKeR5zDgAoAwmODQAABwBjAHUNAAAGAGIAfw0AAAYAYgCpDQAABABgAFwNAAACAEEAXQ0AAAIALwBlDQAAAwBJAKQNAAACABcAMw0AAAQAYwASAAkKeR5zDgAoAwmODQAABwBjAHUNAAAGAGIAfw0AAAYAYgCpDQAABABgAFwNAAACAEEAXQ0AAAIALwBlDQAAAwBJAKQNAAACABcAMw0AAAQAYwAAAA==.Shinthyr:BAEANQAECgYIDAABNQAECgkJJAASAHkeAA==.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAQICQAVAEYPAA==.',
Su='Sunwelljuice:BAEANQADCggIDgABNQAECgUIDQAQAAAAAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAECgkJMQAMAC0kAA==.',
Ta='Tahune:BAEBNQAECoEiAAIIAAgKYSIdCAAVAwiODQAABgBZAHUNAAAFAGIAfw0AAAQAQQCpDQAABQBYAFwNAAAEAFEAXQ0AAAMAYgBlDQAAAgBfADMNAAAFAFYACAAICmEiHQgAFQMIjg0AAAYAWQB1DQAABQBiAH8NAAAEAEEAqQ0AAAUAWABcDQAABABRAF0NAAADAGIAZQ0AAAIAXwAzDQAABQBWAAAA.Talaandea:BAEANQADCggIEwAAAA==.',
Th='Thawd:BAECNQAFFIEQAAIPAAYKPRY/AQDPAQaODQAABAA5AHUNAAADAEYAfw0AAAMAPACpDQAABAAwAFwNAAABACoAMw0AAAEAPAAPAAYKPRY/AQDPAQaODQAABAA5AHUNAAADAEYAfw0AAAMAPACpDQAABAAwAFwNAAABACoAMw0AAAEAPAA1AAQKgSIAAg8ACQrDH0MEAAcDAA8ACQrDH0MEAAcDAAAA.Therapygap:BAEANQAECgIIAwABNQAECgUIDQAQAAAAAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQAQAAAAAA==.',
Vc='Vcoren:BAEANQAFFAIIAgABNQAFFAcIGQAJABIXAA==.',
Za='Zatum:BAEANQAECgIIAwAAAA==.',
Zo='Zomb:BAEANQAECgYIBgAAAA==.',
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
