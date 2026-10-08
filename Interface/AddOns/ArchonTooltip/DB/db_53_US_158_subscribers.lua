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

local lookup = {'Druid-Feral','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Druid-Balance','Druid-Restoration','Evoker-Preservation','Warlock-Demonology','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Warrior-Arms','Rogue-Outlaw','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Holy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=53,date='2026-10-06',data={Ae='Aesinth:BAEANQADCgMIAwABNQAECggIJgABAIEbAA==.',
Ak='Akaeva:BAEANQAECgYIBgAAAA==.',
Al='Alcean:BAEANQAECgYIEAAAAA==.Algebra:BAECNQAFFIEGAAMCAAQKVRWaJAAgAQSODQAAAgBjAHUNAAABAAAAqQ0AAAIAVwAzDQAAAQAeAAIAAwpTHJokACABA44NAAACAGMAqQ0AAAIAVwAzDQAAAQAeAAMAAQpdAK8SADIAAXUNAAABAAAANQAECoEcAAMCAAkKwiLkOwABAwACAAkKgiDkOwABAwADAAMK5SJlHADiAAAAAA==.',
Ar='Araakki:BAEANQAECgQIDAAAAA==.Aradell:BAEBNQAECoE3AAIEAAkKEhl+KABhAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAEAAkKEhl+KABhAgmODQAACQBSAHUNAAAIAEQAfw0AAAgARwCpDQAACABDAFwNAAAFAEkAXQ0AAAUAOgBlDQAABAA6AKQNAAABAA8AMw0AAAcAUQAAAA==.Arceni:BAEANQAECggICAABNQAECgkJNwAEABIZAA==.Ariizi:BAEANQAECgQICAAAAA==.Artam:BAEANQADCggICQABNQAFFAcIHAAFALMYAA==.Arteron:BAEANQADCggICAABNQAFFAYIFgAGAI0jAA==.',
Au='Augstrasza:BAEANQAECgMIAwAAAA==.Aukanawe:BAECNQAFFIEVAAIHAAYKfh3VBAAoAgaODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAMw0AAAMAQQAHAAYKfh3VBAAoAgaODQAABgBhAHUNAAAEADIAfw0AAAIATACpDQAABABfAFwNAAACAEMAMw0AAAMAQQA1AAQKgUUAAwcACQr9JVgEALADAAcACQr9JVgEALADAAgABAqgD89BAOQAAAAA.',
Ay='Ayoade:BAECNQAFFIEgAAIJAAcK0BnUAgBJAgeODQAABgA3AHUNAAAFADoAfw0AAAUAWACpDQAABgBXAFwNAAADADEAXQ0AAAIAMgAzDQAABQBHAAkABwrQGdQCAEkCB44NAAAGADcAdQ0AAAUAOgB/DQAABQBYAKkNAAAGAFcAXA0AAAMAMQBdDQAAAgAyADMNAAAFAEcANQAECoEtAAIJAAkKASSjAgCOAwAJAAkKASSjAgCOAwAAAA==.',
Az='Azzurel:BAEBNQAECoEnAAIKAAkKkxXiOwCEAgmODQAABQAuAHUNAAAFAEUAfw0AAAQAJwCpDQAABQAqAFwNAAAFAEsAXQ0AAAQAMABlDQAAAwAqAKQNAAACAEAAMw0AAAYAQwAKAAkKkxXiOwCEAgmODQAABQAuAHUNAAAFAEUAfw0AAAQAJwCpDQAABQAqAFwNAAAFAEsAXQ0AAAQAMABlDQAAAwAqAKQNAAACAEAAMw0AAAYAQwAAAA==.',
Ba='Babaghanouj:BAEBNQAECoEgAAMLAAcKbxPIKAC7AQeODQAABgBBAHUNAAAEACsAfw0AAAQAKACpDQAABQA3AFwNAAAFADgAXQ0AAAMAKAAzDQAABQAuAAsABwpvE8goALsBB44NAAAFAEEAdQ0AAAQAKwB/DQAABAAoAKkNAAAFADcAXA0AAAIAOABdDQAAAgAoADMNAAADAC4ABQAEClogl40AMgEEjg0AAAEASQBcDQAAAwBUAF0NAAABAFsAMw0AAAIAUQAAAA==.Bayati:BAEBNQAECoEhAAIBAAkK/SLiAQCVAwmODQAABQBgAHUNAAAFAFoAfw0AAAQAWwCpDQAABQBcAFwNAAACAFwAXQ0AAAIAXQBlDQAABABSAKQNAAACAEcAMw0AAAQAXwABAAkK/SLiAQCVAwmODQAABQBgAHUNAAAFAFoAfw0AAAQAWwCpDQAABQBcAFwNAAACAFwAXQ0AAAIAXQBlDQAABABSAKQNAAACAEcAMw0AAAQAXwAAAA==.',
Be='Benghi:BAECNQAFFIEIAAMMAAUKxw1DCwD1AAWODQAAAwArAHUNAAABABwAfw0AAAEADwCpDQAAAQAbADMNAAACADwADAADCjoPQwsA9QADdQ0AAAEAHACpDQAAAQAbADMNAAABADwADQADCvAI2QoA7QADjg0AAAMAKwB/DQAAAQAPADMNAAABAAkANQAECoElAAMMAAkKJRwoLQD9AQAMAAcKrhkoLQD9AQANAAYKnhdWIgCjAQAAAA==.Bestcase:BAECNQAFFIESAAIOAAYKThJVBADHAQaODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AMw0AAAEAKgAOAAYKThJVBADHAQaODQAABQBIAHUNAAAEABIAfw0AAAMABQCpDQAABAA+AFwNAAABAE4AMw0AAAEAKgA1AAQKgSgAAw4ACQqXInAKABUDAA4ACQqXInAKABUDAA8AAQoQB8UwACEAAAAA.',
Bi='Birchmire:BAEANQAECgUIBQABNQAECggIJgABAIEbAA==.',
Br='Brigbala:BAEANQAECgQIBQAAAA==.',
Bu='Burnassus:BAEANQADCggICwABNQAECggIGwAFANEPAA==.',
Ch='Chunghús:BAEANQAECgQICAABNQAFFAEIAQAQAAAAAA==.',
Co='Coggettle:BAEANQADCggIIgABNQAECggIHwARAJ0hAA==.',
Cr='Crustage:BAEANQAECgYIDwAAAA==.',
Dc='Dcae:BAEANQADCgEIAQABNQAECgkJIgACALkiAA==.',
Du='Dumblefrost:BAEANQAECgcIEwAAAA==.',
Eh='Ehanee:BAEBNQAECoEXAAIGAAgKxSKtGQAYAwiODQAABABaAHUNAAADAF0Afw0AAAMAYQCpDQAAAwBWAFwNAAADAGAAXQ0AAAIASgBlDQAAAgBQADMNAAADAFsABgAICsUirRkAGAMIjg0AAAQAWgB1DQAAAwBdAH8NAAADAGEAqQ0AAAMAVgBcDQAAAwBgAF0NAAACAEoAZQ0AAAIAUAAzDQAAAwBbAAAA.',
Fa='Fappimeal:BAEANQAECgUICQAAAA==.Fappisham:BAEBNQAECoEeAAIGAAkKCB7wHgD2AgmODQAABQBTAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAAAwA/AKQNAAACAC8AMw0AAAQATQAGAAkKCB7wHgD2AgmODQAABQBTAHUNAAADAE0Afw0AAAMAVACpDQAABQBVAFwNAAADAF8AXQ0AAAIASwBlDQAAAwA/AKQNAAACAC8AMw0AAAQATQABNQAECgUICQAQAAAAAA==.',
Fs='Fshi:BAECNQAFFIEJAAMBAAYKCRN0AAASAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAMALwABAAYKCRN0AAASAgaODQAAAQBEAHUNAAACACgAfw0AAAEAEgCpDQAAAQBSAFwNAAABACMAMw0AAAIALwAHAAEKqQg2JQA4AAEzDQAAAQAWADUABAqBRQADAQAJCi8mWAAA+QMAAQAJCi8mWAAA+QMABwAGCmwcaToA9AEAAAA=.',
Gr='Greatanubis:BAEANQAECgcIDwAAAA==.Grumli:BAECNQAFFIEHAAISAAQKdSBxCgCGAQSODQAAAwBJAHUNAAABAF0Afw0AAAEARACpDQAAAgBhABIABAp1IHEKAIYBBI4NAAADAEkAdQ0AAAEAXQB/DQAAAQBEAKkNAAACAGEANQAECoEmAAMSAAkKeBxFIgDAAgASAAkKeBxFIgDAAgAGAAMKiBDS0wC6AAABNQADCgUIBQAQAAAAAA==.Grummel:BAEANQADCgUIBQAAAA==.Grunzi:BAEANQAECggIEAAAAA==.',
Ha='Halts:BAEANQAECgUICgABNQAFFAUIBwASADkNAA==.',
Il='Ilnarya:BAEANQADCgcICwABNQADCggIEwAQAAAAAA==.',
Im='Imei:BAEANQADCgIIAgABNQAFFAUIEgATACcfAA==.',
Ja='Jail:BAEBNQAECoEiAAICAAkKuSKPFAB7AwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAACAEMAMw0AAAQAXwACAAkKuSKPFAB7AwmODQAABwBXAHUNAAAEAGMAfw0AAAMAYgCpDQAABABgAFwNAAADAFcAXQ0AAAMAXABlDQAABABMAKQNAAACAEMAMw0AAAQAXwAAAA==.Jarco:BAEANQAECgQIBAABNQAFFAYICwAUALMVAA==.',
Jl='Jlycett:BAEBNQAECoEfAAISAAkKpSPsBgB8AwmODQAAAgBbAHUNAAAEAGEAfw0AAAMAYgCpDQAABABXAFwNAAADAGIAXQ0AAAYAYgBlDQAABABjAKQNAAAEAF4AMw0AAAEAOAASAAkKpSPsBgB8AwmODQAAAgBbAHUNAAAEAGEAfw0AAAMAYgCpDQAABABXAFwNAAADAGIAXQ0AAAYAYgBlDQAABABjAKQNAAAEAF4AMw0AAAEAOAABNQAFFAcIIAAJANAZAA==.',
Ka='Kanavi:BAECNQAFFIESAAITAAUKJx+ZCQDoAQWODQAABgBhAHUNAAADAGAAfw0AAAEAMgCpDQAABABGADMNAAAEAFQAEwAFCicfmQkA6AEFjg0AAAYAYQB1DQAAAwBgAH8NAAABADIAqQ0AAAQARgAzDQAABABUADUABAqBKgACEwAJCqQkkwoAmgMAEwAJCqQkkwoAmgMAAAA=.Kantai:BAEANQADCgYICQABNQAFFAUIEgATACcfAA==.',
Kn='Knackered:BAEANQAECgYIEQABNQABCgIIAgAQAAAAAA==.',
Kr='Kregazi:BAEBNQAECoEmAAIEAAgKASB0GQDLAgiODQAABgBRAHUNAAAGAF0Afw0AAAUATACpDQAABQBNAFwNAAAEAFUAXQ0AAAQAWwBlDQAAAwBHADMNAAAFAE0ABAAICgEgdBkAywIIjg0AAAYAUQB1DQAABgBdAH8NAAAFAEwAqQ0AAAUATQBcDQAABABVAF0NAAAEAFsAZQ0AAAMARwAzDQAABQBNAAAA.',
Ky='Kyssarra:BAECNQAFFIEYAAQVAAcKSSL8AAAwAQeODQAABABeAHUNAAAEAFgAfw0AAAQAUgCpDQAAAwBiAFwNAAADAE4AXQ0AAAEATAAzDQAABQBeABUAAwpDIvwAADABA3UNAAAEAFgAqQ0AAAMAYgBdDQAAAQBMAAoAAwpyITQWABEBA44NAAAEAF4Afw0AAAQAUgBcDQAAAgBOABYAAgr7HFUCAMgAAlwNAAABADUAMw0AAAUAXgA1AAQKgX8ABBUACQrpJg4AABAEABUACQrRJg4AABAEAAoABQo8Ju5eABkCABYABQoqJq4KAJ4BAAAA.',
Lo='Lobotomight:BAEANQAECgcIDQAAAA==.',
Ma='Maildaddy:BAEANQAFFAEIAQAAAA==.Maxxy:BAEANQAECgYIDwAAAA==.',
Mc='Mckellen:BAEANQAECgcIDwABNQAFFAcIIAAJANAZAA==.',
Me='Merarite:BAEBNQAECoEnAAIEAAgKfBU0OQABAgiODQAABgA1AHUNAAAGADkAfw0AAAUANACpDQAABgBCAFwNAAAFAEYAXQ0AAAQAIABlDQAAAwAsADMNAAAEAD0ABAAICnwVNDkAAQIIjg0AAAYANQB1DQAABgA5AH8NAAAFADQAqQ0AAAYAQgBcDQAABQBGAF0NAAAEACAAZQ0AAAMALAAzDQAABAA9AAAA.',
Mo='Monkguyy:BAEANQAECgYIBwABNQAECgcIEwAQAAAAAA==.',
Na='Nadasa:BAEBNQAECoFBAAIXAAkKHCLrDwB8AwmODQAADABdAHUNAAAJAF8Afw0AAAkAYQCpDQAACQBQAFwNAAAHAFwAXQ0AAAMARwBlDQAABwBYAKQNAAABAEsAMw0AAAgAWwAXAAkKHCLrDwB8AwmODQAADABdAHUNAAAJAF8Afw0AAAkAYQCpDQAACQBQAFwNAAAHAFwAXQ0AAAMARwBlDQAABwBYAKQNAAABAEsAMw0AAAgAWwAAAA==.',
Ni='Nixaanu:BAEANQADCgYICQAAAA==.',
No='Nomadicbear:BAEANQABCgQICAABNQABCgYICAAQAAAAAA==.Nomadichunt:BAEANQABCgYICAAAAA==.Nomadicmonk:BAEANQABCgQIBAABNQABCgYICAAQAAAAAA==.',
Ny='Nyriaa:BAEANQADCggICAAAAA==.',
Pa='Palashin:BAEANQAECgQIBQABNQAFFAUIBwASADkNAA==.',
Pe='Personnelkid:BAEANQADCggICAABNQAECggIGwAFANEPAA==.',
Po='Poortal:BAEANQAECgEIAQABNQAECgcIDQAQAAAAAA==.Potatogogue:BAECNQAFFIEMAAMGAAUKQhIMFgDmAAWODQAABAAuAHUNAAACAA4Afw0AAAEAMgCpDQAAAwAfAFwNAAACAFoABgADChQMDBYA5gADjg0AAAQALgB1DQAAAgAOAKkNAAADAB8AEgACCloUhhgAqQACfw0AAAEASwBcDQAAAgAcADUABAqBIQADBgAJCiMgDB8A9QIABgAJCiMgDB8A9QIAEgACClAfb9sAhwAAATUABRQBCAEAEAAAAAA=.',
Ri='Ritren:BAEANQAECgMIAwABNQAECgcIDgAQAAAAAA==.',
Ro='Roogies:BAECNQAFFIEHAAIMAAMKTiLZCAA2AQOODQAABABhAHUNAAABAFsAqQ0AAAIASgAMAAMKTiLZCAA2AQOODQAABABhAHUNAAABAFsAqQ0AAAIASgA1AAQKgTkAAgwACQpHJA0DAJoDAAwACQpHJA0DAJoDAAAA.',
Se='Senzarial:BAEANQAECgEIAQABNQAFFAYIFQAHAH4dAA==.Serynytee:BAEANQAECgYICwAAAA==.',
Sh='Shinseer:BAECNQAFFIEHAAISAAUKOQ0dCwB4AQWODQAAAQAvAHUNAAABAAsAfw0AAAIAIACpDQAAAQA5ADMNAAACABQAEgAFCjkNHQsAeAEFjg0AAAEALwB1DQAAAQALAH8NAAACACAAqQ0AAAEAOQAzDQAAAgAUADUABAqBKAACEgAJCmEfFQ8ANQMAEgAJCmEfFQ8ANQMAAAA=.Shinthyr:BAEANQAFFAEIAQABNQAFFAUIBwASADkNAA==.',
St='Starryangel:BAEANQAECgEIAQABNQAFFAUIDgAXAAENAA==.Stormbroken:BAEANQADCgUIBQABNQAECggIGwAFANEPAA==.',
Su='Sunwelljuice:BAEANQADCggIFQABNQAECggIGwAFANEPAA==.',
Sy='Syldrasi:BAEANQADCgQICAABNQAFFAMIBwAMAE4iAA==.',
Ta='Tahune:BAEBNQAECoEqAAMIAAgKjCLnCQAOAwiODQAABwBZAHUNAAAGAGIAfw0AAAUAQQCpDQAABgBYAFwNAAAFAFEAXQ0AAAQAYgBlDQAAAwBiADMNAAAGAFYACAAICowi5wkADgMIjg0AAAYAWQB1DQAABQBiAH8NAAAEAEEAqQ0AAAUAWABcDQAABABRAF0NAAAEAGIAZQ0AAAMAYgAzDQAABQBWAAcABgqHG+g6APEBBo4NAAABAFEAdQ0AAAEATQB/DQAAAQAvAKkNAAABADwAXA0AAAEATwAzDQAAAQBMAAAA.Talaandea:BAEANQADCggIEwAAAA==.',
Th='Thawd:BAECNQAFFIEWAAIPAAYKQxiBAQDkAQaODQAABQBZAHUNAAAEAEYAfw0AAAQAPACpDQAABQAwAFwNAAACACoAMw0AAAIAPAAPAAYKQxiBAQDkAQaODQAABQBZAHUNAAAEAEYAfw0AAAQAPACpDQAABQAwAFwNAAACACoAMw0AAAIAPAA1AAQKgSUAAg8ACQrDH1AFAPYCAA8ACQrDH1AFAPYCAAAA.Therapygap:BAEANQAECgIIAwABNQAECggIGwAFANEPAA==.',
Tr='Trèantdaddy:BAEANQAECgYIBgABNQAFFAEIAQAQAAAAAA==.',
Vc='Vcoren:BAEBNQAECoEbAAIYAAkKOSSCAwCyAwmODQAAAwBaAHUNAAAEAFwAfw0AAAQAVwCpDQAABABeAFwNAAAEAF8AXQ0AAAMAXwBlDQAAAgBgAKQNAAABAFMAMw0AAAIAYgAYAAkKOSSCAwCyAwmODQAAAwBaAHUNAAAEAFwAfw0AAAQAVwCpDQAABABeAFwNAAAEAF8AXQ0AAAMAXwBlDQAAAgBgAKQNAAABAFMAMw0AAAIAYgABNQAFFAcIIAAJANAZAA==.',
Za='Zatum:BAEANQAECgUICAAAAA==.',
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
