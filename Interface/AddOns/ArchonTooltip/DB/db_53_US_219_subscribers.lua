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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Druid-Guardian','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Warrior-Arms','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Thrall',name='US',type='subscribers',zone=53,date='2026-09-15',data={Ae='Aerù:BAEANQADCggIDAAAAA==.',
Ai='Airork:BAEANQAECgEIAQAAAA==.',
An='Angré:BAEANQAFFAEIAQAAAA==.',
Ar='Arms:BAEANQAECggIAgABNQAECggICAABAAAAAA==.',
As='Astrocx:BAEANQADCgIIAgAAAA==.',
Au='Aurorapop:BAEANQADCgcIBwABNQAECggIDAABAAAAAA==.',
Ba='Battlebeefy:BAEANQAECgEIAQABNQAECgYIDgABAAAAAA==.',
Be='Beefynumnums:BAEANQAECgYIDgAAAA==.',
Bi='Biggaybird:BAEANQADCggICAABNQAECgkJIQACAAsmAA==.Bigmosaysno:BAEANQAECgQICQABNQAECggIFAADAAUcAA==.Biimo:BAEBNQAECoEhAAICAAkJCyZzAAD6AwmODQAABABjAHUNAAAEAGMAfw0AAAQAYwCpDQAABABhAFwNAAAEAGEAXQ0AAAQAYwBlDQAAAwBhAKQNAAADAFYAMw0AAAMAYwACAAkJCyZzAAD6AwmODQAABABjAHUNAAAEAGMAfw0AAAQAYwCpDQAABABhAFwNAAAEAGEAXQ0AAAQAYwBlDQAAAwBhAKQNAAADAFYAMw0AAAMAYwAAAA==.Biimoh:BAEANQAECgMIAwABNQAECgkJIQACAAsmAA==.',
Bl='Bluekek:BAECNQAFFIENAAIEAAYJ9B4TAAB/AgaODQAAAwBcAHUNAAACAGEAfw0AAAIAJwCpDQAAAwBkAFwNAAABAEQAMw0AAAIATQAEAAYJ9B4TAAB/AgaODQAAAwBcAHUNAAACAGEAfw0AAAIAJwCpDQAAAwBkAFwNAAABAEQAMw0AAAIATQA1AAQKgSsABAQACQnOJgIAABYEAAQACQnOJgIAABYEAAUABAlbIE8gAHQBAAYAAQlwJm59AGgAAAAA.',
Bo='Bobbyz:BAEANQAECgYIDgAAAA==.Borik:BAEBNQAECoEXAAMHAAkJpyT+BwAQAwmODQAABQBgAHUNAAAEAGIAfw0AAAMAYQCpDQAAAwBdAFwNAAACAGEAXQ0AAAEAXQBlDQAAAQBbAKQNAAABAE4AMw0AAAMAYQAHAAgJSyT+BwAQAwiODQAABQBgAHUNAAAEAGIAfw0AAAMAYQCpDQAAAwBdAFwNAAABAFcAXQ0AAAEAXQCkDQAAAQBOADMNAAADAGEACAACCeQklpgA2AACXA0AAAEAYQBlDQAAAQBbAAAA.',
Br='Braene:BAEANQAECgIIAgAAAA==.Bramblesox:BAEBNQAECoEdAAMJAAkJASN6CgA3AwmODQAABABbAHUNAAAEAF8Afw0AAAQAWQCpDQAABABgAFwNAAADAF0AXQ0AAAMAWQBlDQAAAgBTAKQNAAABAE0AMw0AAAQAWAAJAAgJmiN6CgA3AwiODQAAAwBbAHUNAAAEAF8Afw0AAAQAWQCpDQAABABgAFwNAAACAF0AXQ0AAAMAWQBlDQAAAgBTADMNAAADAFgACgAECf4XZCQACgEEjg0AAAEASwBcDQAAAQBAAKQNAAABADUAMw0AAAEANAAAAA==.Brobonic:BAEANQAECgIIAwAAAA==.Brocendance:BAEANQADCgYIBgABNQAECgIIAwABAAAAAA==.Bruhdean:BAEANQAECgcIEgAAAA==.',
['Bä']='Bärn:BAEANQAECgUIDgAAAA==.',
Ce='Cenarii:BAEBNQAECoEdAAIJAAkJySANCgA9AwmODQAABABYAHUNAAAEAFwAfw0AAAQAXQCpDQAABABVAFwNAAADAF4AXQ0AAAMAVgBlDQAAAgA9AKQNAAABAEQAMw0AAAQAUgAJAAkJySANCgA9AwmODQAABABYAHUNAAAEAFwAfw0AAAQAXQCpDQAABABVAFwNAAADAF4AXQ0AAAMAVgBlDQAAAgA9AKQNAAABAEQAMw0AAAQAUgAAAA==.Cenlock:BAEANQADCggICAABNQAECgkJHQAJAMkgAA==.',
Ch='Chakasbabaka:BAEANQAECgcIEgAAAA==.Chueeyy:BAEANQAECgcIDwAAAA==.Chÿrp:BAEANQAFFAEIAQAAAA==.',
Cl='Clanney:BAEANQAECgQIBQAAAA==.',
Co='Coffshock:BAEANQAECgQIBQABNQAFFAMIBgALAHYSAA==.Corbsols:BAECNQAFFIEGAAIMAAMJSx5ZCwAtAQOODQAAAwBgAHUNAAABAEIAqQ0AAAIARQAMAAMJSx5ZCwAtAQOODQAAAwBgAHUNAAABAEIAqQ0AAAIARQA1AAQKgSIAAgwACQmaJEQGAKwDAAwACQmaJEQGAKwDAAAA.',
Cr='Cranghoul:BAEANQAECgUIBQAAAA==.',
Cy='Cynanxmk:BAEANQAECgcIBQAAAA==.',
Da='Datnotamoose:BAEANQAECgcIEAAAAA==.Datsamoose:BAEANQADCgUIBQABNQAECgcIEAABAAAAAA==.',
Db='Dblrbl:BAEANQAECgMIAwAAAA==.',
De='Deathcen:BAEANQAECggIDwAAAA==.',
Dm='Dmnwatcher:BAEANQAECggIAwAAAA==.',
Do='Dobbi:BAEANQAECgQIBwAAAA==.Doneliving:BAEANQADCggIAgABNQAECgQIBQABAAAAAA==.',
El='Elil:BAEANQADCggICAABNQAECgcIEgABAAAAAA==.',
Er='Erasleigh:BAEANQAECgYIDwAAAA==.',
Et='Ethian:BAEANQAECgQIBgAAAA==.',
Fe='Feelberserk:BAEBNQAECoEeAAQNAAkJkxPpFwDEAQmODQAABABMAHUNAAAFADMAfw0AAAUASQCpDQAABQAwAFwNAAADADcAXQ0AAAMAIgBlDQAAAgAZAKQNAAABABgAMw0AAAIAPgANAAYJyBXpFwDEAQaODQAABABMAHUNAAADACoAfw0AAAQASQBcDQAAAwA3AGUNAAACABkAMw0AAAIAPgAOAAQJfw8OLAADAQR1DQAAAgAzAKkNAAAEADAAXQ0AAAMAIgCkDQAAAQAYAA8AAgn5BsYRAE0AAn8NAAABACAAqQ0AAAEAAgAAAA==.Felbate:BAEANQADCgUICAABNQABCgIIAgABAAAAAA==.Felsaïnt:BAEANQADCgcICwABNQABCgIIAgABAAAAAA==.',
Fl='Flëxørçïst:BAEBNQAECoEaAAIQAAkJ9iVcAADtAwmODQAABABjAHUNAAADAGEAfw0AAAMAYQCpDQAAAwBgAFwNAAADAF0AXQ0AAAIAYwBlDQAAAwBjAKQNAAACAF0AMw0AAAMAYgAQAAkJ9iVcAADtAwmODQAABABjAHUNAAADAGEAfw0AAAMAYQCpDQAAAwBgAFwNAAADAF0AXQ0AAAIAYwBlDQAAAwBjAKQNAAACAF0AMw0AAAMAYgAAAA==.',
Fo='Fonics:BAEANQAECgYIBgAAAA==.Foureleven:BAEANQAECgYIBgAAAA==.',
Fr='Fromengard:BAEANQAECgYIDQAAAA==.',
Ga='Galginoth:BAECNQAFFIEKAAILAAYJ4RxWAQBZAgaODQAAAQBIAHUNAAABAGEAfw0AAAIAWQCpDQAAAwBhAFwNAAACADgAXQ0AAAEAHgALAAYJ4RxWAQBZAgaODQAAAQBIAHUNAAABAGEAfw0AAAIAWQCpDQAAAwBhAFwNAAACADgAXQ0AAAEAHgA1AAQKgRsAAwsACQkCI9gMAGIDAAsACQnfItgMAGIDABEAAwkgJooKAEgBAAAA.Galgywalgy:BAEANQAECgUIBQABNQAFFAYICgALAOEcAA==.',
Gh='Ghirrney:BAEANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Gl='Glizzyßuns:BAEANQAECgEIAQAAAA==.',
Gn='Gnashes:BAEBNQAECoEfAAISAAkJiCaPAAD/AwmODQAABABjAHUNAAAEAGMAfw0AAAMAYQCpDQAABABjAFwNAAAEAGMAXQ0AAAMAYwBlDQAAAwBjAKQNAAACAF0AMw0AAAQAYwASAAkJiCaPAAD/AwmODQAABABjAHUNAAAEAGMAfw0AAAMAYQCpDQAABABjAFwNAAAEAGMAXQ0AAAMAYwBlDQAAAwBjAKQNAAACAF0AMw0AAAQAYwAAAA==.Gnostim:BAEANQAECgMIAwAAAA==.',
Gr='Grandsongor:BAEBNQAECoEgAAMHAAkJVyQUAgCjAwmODQAABABhAHUNAAAEAGMAfw0AAAQAYQCpDQAABQBhAFwNAAAEAGEAXQ0AAAQAXQBlDQAAAwBfAKQNAAACAEgAMw0AAAIAVQAHAAkJVyQUAgCjAwmODQAAAwBhAHUNAAADAGMAfw0AAAQAYQCpDQAABABhAFwNAAADAGEAXQ0AAAQAXQBlDQAAAwBfAKQNAAACAEgAMw0AAAIAVQAIAAQJNQx8lADnAASODQAAAQBIAHUNAAABABgAqQ0AAAEAFQBcDQAAAQAHAAAA.',
['Gä']='Gäwdzëërah:BAEANQADCgYIDQABNQAECgQIDQABAAAAAA==.',
Ha='Hamrato:BAEANQAFFAEIAQABNQAECgYIBQABAAAAAA==.Handegg:BAEANQAECgYICwAAAA==.Hannïbál:BAEANQADCgQICAABNQAECgIIBAABAAAAAA==.Harrek:BAEANQAECgEIAQABNQAFFAUICwATAD0RAA==.Haurato:BAEANQAECgYIBQAAAA==.',
He='Hearthorn:BAEANQADCgYIBgAAAA==.',
Ho='Hooked:BAEANQAECgUIBwABNQAECgYIBgABAAAAAA==.',
Hu='Hunglikebeef:BAEANQAECgEIAQABNQAECgYIDgABAAAAAA==.',
Ja='Ja:BAEANQAECgcIBAABNQAECggICAABAAAAAA==.Jakwasbored:BAEANQAECgUIDAAAAA==.Jayyco:BAEBNQAECoEeAAMGAAkJ4h9qDgDcAgmODQAABABgAHUNAAAEAEQAfw0AAAQAUwCpDQAABABMAFwNAAADAFAAXQ0AAAMAVgBlDQAAAgA7AKQNAAACAFsAMw0AAAQAWwAGAAkJXh5qDgDcAgmODQAAAwBgAHUNAAADAEQAfw0AAAMAUwCpDQAAAwBMAFwNAAADAFAAXQ0AAAMAVgBlDQAAAgA7AKQNAAACAFsAMw0AAAMAOAAEAAUJDxgKCQBIAQWODQAAAQBAAHUNAAABADMAfw0AAAEALgCpDQAAAQA1ADMNAAABAFsAAAA=.',
Je='Jeffirey:BAECNQAFFIEPAAIMAAYJHyK3AAB3AgaODQAABABkAHUNAAACAFoAfw0AAAIALwCpDQAAAwBiAFwNAAACAGMAMw0AAAIAWAAMAAYJHyK3AAB3AgaODQAABABkAHUNAAACAFoAfw0AAAIALwCpDQAAAwBiAFwNAAACAGMAMw0AAAIAWAA1AAQKgRkAAgwACQmoJXIJAJMDAAwACQmoJXIJAJMDAAAA.',
Ju='Ju:BAEANQAECggICAAAAA==.',
Ka='Kaelani:BAEANQAECgYIDAAAAQ==.Kaylèia:BAEANQAECgEIAQAAAA==.',
Kh='Kharns:BAEBNQAECoEXAAMLAAkJVCGMFAAkAwmODQAAAwBUAHUNAAADAF4Afw0AAAMAUACpDQAAAwBcAFwNAAACAFAAXQ0AAAIAUABlDQAAAwBTAKQNAAABAFUAMw0AAAMAVgALAAkJVCGMFAAkAwmODQAAAwBUAHUNAAADAF4Afw0AAAIAUACpDQAAAwBcAFwNAAACAFAAXQ0AAAIAUABlDQAAAwBTAKQNAAABAFUAMw0AAAMAVgARAAEJ7h5AGgBCAAF/DQAAAQBPAAAA.',
Ki='Kichenorfist:BAEANQADCgYIBwABNQAECgkJGwAUAJYSAA==.Kichenorpalm:BAEBNQAECoEbAAMUAAkJlhLtEQAUAgmODQAAAwBIAHUNAAADADgAfw0AAAMAMACpDQAAAwA3AFwNAAADAEAAXQ0AAAMABQBlDQAAAwAWAKQNAAADABwAMw0AAAMASQAUAAkJlhLtEQAUAgmODQAAAgBIAHUNAAACADgAfw0AAAIAMACpDQAAAgA3AFwNAAACAEAAXQ0AAAEABQBlDQAAAgAWAKQNAAACABwAMw0AAAMASQAVAAgJSg9pDgDgAQiODQAAAQBEAHUNAAABADMAfw0AAAEAJQCpDQAAAQAZAFwNAAABAC8AXQ0AAAIAFQBlDQAAAQAHAKQNAAABADUAAAA=.Kilateral:BAEANQAECgEIAQABNQAECgcIDwABAAAAAA==.Kilshank:BAEANQAECgcIDwAAAA==.',
Kr='Kryonyx:BAEANQAECgcIEgAAAA==.',
Ky='Kyyñ:BAEANQAECggIEQAAAA==.',
La='Lakonikos:BAEANQADCgUIBQABNQAECgcIDwABAAAAAA==.Lazytîtan:BAEBNQAECoElAAIWAAkJeiHnAACrAwmODQAABQBgAHUNAAAEAGEAfw0AAAUAYwCpDQAABQBjAFwNAAAFAFMAXQ0AAAMAWgBlDQAABABHAKQNAAACACIAMw0AAAQAYQAWAAkJeiHnAACrAwmODQAABQBgAHUNAAAEAGEAfw0AAAUAYwCpDQAABQBjAFwNAAAFAFMAXQ0AAAMAWgBlDQAABABHAKQNAAACACIAMw0AAAQAYQAAAA==.',
Li='Libzella:BAEANQAECgEIAQABNQAECgIIAgABAAAAAA==.Littletimmay:BAEANQAECgIIAgABNQAFFAUICAAHALwSAA==.',
Lo='Lofixo:BAEANQAECgEIAQABNQAFFAUICQATABcSAA==.Lousasoul:BAEBNQAECoEUAAMDAAgJBRwRBwAWAgiODQAABgBeAHUNAAADAF0Afw0AAAEAVACpDQAABABUAFwNAAABAD4AXQ0AAAIAIABlDQAAAQAvAKQNAAACAEoAAwAHCVUYEQcAFgIHjg0AAAIAVgB1DQAAAgBHAKkNAAADAFIAXA0AAAEAPgBdDQAAAgAgAGUNAAABAC8ApA0AAAEANQAJAAUJviEqKgDWAQWODQAABABeAHUNAAABAF0Afw0AAAEAVACpDQAAAQBUAKQNAAABAEoAAAA=.',
Lu='Luthenyos:BAECNQAFFIEJAAIXAAQJ9B81AACWAQSODQAAAwBbAHUNAAACAFQAfw0AAAIASgCpDQAAAgBMABcABAn0HzUAAJYBBI4NAAADAFsAdQ0AAAIAVAB/DQAAAgBKAKkNAAACAEwANQAECoEbAAIXAAkJ/SU2AADaAwAXAAkJ/SU2AADaAwAAAA==.',
Ly='Lyfa:BAEBNQAECoEZAAIYAAkJZBtvCgD1AgmODQAAAwBWAHUNAAADAFQAfw0AAAIASQCpDQAAAwBIAFwNAAADAEQAXQ0AAAMANABlDQAAAwAvAKQNAAABAEwAMw0AAAQARAAYAAkJZBtvCgD1AgmODQAAAwBWAHUNAAADAFQAfw0AAAIASQCpDQAAAwBIAFwNAAADAEQAXQ0AAAMANABlDQAAAwAvAKQNAAABAEwAMw0AAAQARAAAAA==.',
['Lí']='Líanhua:BAEANQAECgcIEgAAAA==.',
Ma='Mahall:BAEBNQAECoEfAAISAAkJDyWnAwC9AwmODQAABABhAHUNAAAEAF4Afw0AAAQAYQCpDQAABABhAFwNAAADAGMAXQ0AAAMAXgBlDQAAAwBZAKQNAAACAFMAMw0AAAQAYwASAAkJDyWnAwC9AwmODQAABABhAHUNAAAEAF4Afw0AAAQAYQCpDQAABABhAFwNAAADAGMAXQ0AAAMAXgBlDQAAAwBZAKQNAAACAFMAMw0AAAQAYwAAAA==.Malarki:BAECNQAFFIEJAAIOAAUJMh9eAAD/AQWODQAAAgBQAHUNAAACAEMAfw0AAAEAPwCpDQAAAgBfADMNAAACAFwADgAFCTIfXgAA/wEFjg0AAAIAUAB1DQAAAgBDAH8NAAABAD8AqQ0AAAIAXwAzDQAAAgBcADUABAqBGwACDgAJCVYmeQAA3gMADgAJCVYmeQAA3gMAAAA=.Malurki:BAEANQAECgQIBAABNQAFFAUICQAOADIfAA==.',
Me='Meatyklaws:BAEANQAECgYIDAAAAA==.Meatykneez:BAEANQADCggIDgABNQAECgYIDAABAAAAAA==.Merrccutio:BAEBNQAECoEYAAIGAAkJKyL1AwBpAwmODQAABABaAHUNAAADAGIAfw0AAAMAVACpDQAAAwBfAFwNAAACAGAAXQ0AAAIAXQBlDQAAAQBaAKQNAAACADEAMw0AAAQAWAAGAAkJKyL1AwBpAwmODQAABABaAHUNAAADAGIAfw0AAAMAVACpDQAAAwBfAFwNAAACAGAAXQ0AAAIAXQBlDQAAAQBaAKQNAAACADEAMw0AAAQAWAAAAA==.',
Na='Naelran:BAEANQAECgQICQAAAA==.Narcoleptik:BAEANQAECgcIEgAAAA==.',
Ne='Neptunebrew:BAEANQADCgYIBgABNQAECgkJFwALALQjAA==.Neptunedh:BAEANQADCgYIBwABNQAECgkJFwALALQjAA==.Neptunedk:BAEANQADCgEIAQABNQAECgkJFwALALQjAA==.Neptunesham:BAEANQAECgcICAABNQAECgkJFwALALQjAA==.Neptunewar:BAEBNQAECoEXAAILAAkJtCOyCwBsAwmODQAAAwBiAHUNAAADAFoAfw0AAAMAXwCpDQAAAgBZAFwNAAACAGEAXQ0AAAIAXABlDQAAAwBgAKQNAAACAEAAMw0AAAMAYwALAAkJtCOyCwBsAwmODQAAAwBiAHUNAAADAFoAfw0AAAMAXwCpDQAAAgBZAFwNAAACAGEAXQ0AAAIAXABlDQAAAwBgAKQNAAACAEAAMw0AAAMAYwAAAA==.',
Ny='Nyannyanx:BAEANQAECgIIAgABNQAECgkJIQACAAsmAA==.',
Od='Odhinnaesir:BAEANQADCgUIBQAAAA==.',
Oo='Ookrit:BAEANQADCgUIBQABNQAECgUIBQABAAAAAA==.',
Op='Opalshade:BAEANQADCggIBAAAAA==.',
Pa='Pakdk:BAEANQAECgQICAAAAA==.Pallyjuice:BAEANQAECgcIEgAAAA==.',
Ph='Phaizddk:BAEANQADCggIEAABNQAECgkJGwAZALUhAA==.Phaizdk:BAEBNQAECoEbAAMZAAkJtSGCAgCGAwmODQAAAwBYAHUNAAADAF4Afw0AAAMAUgCpDQAAAwBOAFwNAAADAF4AXQ0AAAMAWgBlDQAAAwBeAKQNAAADADwAMw0AAAMAWwAZAAkJtSGCAgCGAwmODQAAAgBYAHUNAAACAF4Afw0AAAIAUgCpDQAAAgBOAFwNAAACAF4AXQ0AAAIAWgBlDQAAAwBeAKQNAAADADwAMw0AAAEAWwAaAAcJMRS5LgDMAQeODQAAAQA+AHUNAAABADIAfw0AAAEALgCpDQAAAQA8AFwNAAABADgAXQ0AAAEAFAAzDQAAAgBAAAAA.Phaizdkk:BAEANQADCggIGAABNQAECgkJGwAZALUhAA==.',
Ra='Rabandk:BAEANQAECgMIBAAAAA==.',
Re='Respectble:BAEANQAECgQIBAABNQAFFAYIDgAJAAIjAA==.Rezpectable:BAECNQAFFIEOAAIJAAYJAiOSAACBAgaODQAAAwBjAHUNAAACAF0Afw0AAAIAOQCpDQAAAwBjAFwNAAABAFoAMw0AAAMAYgAJAAYJAiOSAACBAgaODQAAAwBjAHUNAAACAF0Afw0AAAIAOQCpDQAAAwBjAFwNAAABAFoAMw0AAAMAYgA1AAQKgRsAAgkACQmrJnkAAPgDAAkACQmrJnkAAPgDAAAA.',
Ri='Richards:BAEANQAECggIDQAAAA==.Riqou:BAEANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
Rt='Rtasx:BAEANQAECgUIBwABNQAFFAEIAQABAAAAAA==.',
Sa='Sabelas:BAEANQADCggIEAABNQAECgkJIAASAI0mAA==.Saelii:BAEANQADCggIAQAAAA==.Sarivi:BAEANQAECgQIBQAAAA==.',
Se='Sebinor:BAEANQAECgcICwAAAA==.',
Sh='Shamblers:BAEANQAECgIIAgAAAA==.Shrandil:BAEANQAECgIIBAAAAA==.Shämanistic:BAEANQADCgUIBQABNQAECgYIDgABAAAAAA==.',
Si='Sindulladh:BAEANQAFFAYIAQAAAA==.',
Sk='Skellyann:BAEBNQAECoEgAAIbAAkJMh8ZCQAmAwmODQAABABhAHUNAAAEAFEAfw0AAAQARwCpDQAABABXAFwNAAAEAFcAXQ0AAAQAWwBlDQAAAwAsAKQNAAACAEUAMw0AAAMAVwAbAAkJMh8ZCQAmAwmODQAABABhAHUNAAAEAFEAfw0AAAQARwCpDQAABABXAFwNAAAEAFcAXQ0AAAQAWwBlDQAAAwAsAKQNAAACAEUAMw0AAAMAVwAAAA==.',
So='Sofio:BAEANQAECggICAABNQADCgYIBgABAAAAAA==.Souldawg:BAEANQAECgcIDQABNQAECggIFAADAAUcAA==.',
St='Staverganzza:BAEANQADCggIDwABNQAECgIIBAABAAAAAA==.',
['Sá']='Sárévók:BAEANQAECgQIDQAAAA==.',
['Sä']='Sätansdemon:BAEANQAECgYIBgABNQAECgYIDgABAAAAAA==.',
['Sî']='Sîc:BAEANQADCgUICQAAAA==.',
Ta='Tarrogath:BAEANQAECgQIDAABNQAECgcICwABAAAAAA==.',
Th='Thõrmbra:BAEANQAECgYIDQAAAA==.',
Ti='Tibberslock:BAEBNQAFFIEHAAMcAAMJ/hg/BgAKAQOODQAAAwBHAKkNAAACADsAMw0AAAIAPQAcAAMJQRg/BgAKAQOODQAAAwBHAKkNAAABADUAMw0AAAIAPQAdAAEJJRcJCwBZAAGpDQAAAQA7AAAA.Timmaykc:BAECNQAFFIEIAAIHAAUJvBKEAwCOAQWODQAAAgAnAHUNAAACADUAfw0AAAEAGgCpDQAAAgBJADMNAAABAC4ABwAFCbwShAMAjgEFjg0AAAIAJwB1DQAAAgA1AH8NAAABABoAqQ0AAAIASQAzDQAAAQAuADUABAqBIAADBwAJCdEhOAYANAMABwAJCWkfOAYANAMACAACCYwlnJsAzQAAAAA=.',
To='Tonitrus:BAEANQAECgcIDQAAAA==.Tonstt:BAEANQADCggICAABNQADCgYIBgABAAAAAA==.Totemkurt:BAEANQAECgIIAQAAAA==.Toxishammy:BAEANQAFFAEIAQABNQAECgQIBQABAAAAAA==.',
Tr='Trogdorbrns:BAEANQAECgUICgAAAA==.',
Ty='Tygerrlily:BAEANQAECgQIBAAAAA==.',
Ui='Uihara:BAEANQAECgIIAwABNQAECgkJGQAYAGQbAA==.',
Un='Unole:BAEANQAECgUICgAAAA==.',
Va='Vaesen:BAEBNQAECoEcAAMGAAkJDyJfCgAIAwmODQAAAwBQAHUNAAADAFoAfw0AAAMATwCpDQAAAwBTAFwNAAADAFQAXQ0AAAMAXABlDQAAAwBfAKQNAAADAFwAMw0AAAQAVAAGAAkJDyJfCgAIAwmODQAAAgBQAHUNAAACAFoAfw0AAAIATwCpDQAAAgBTAFwNAAADAFQAXQ0AAAMAXABlDQAAAwBfAKQNAAADAFwAMw0AAAMAVAAEAAUJJw5MCwALAQWODQAAAQAgAHUNAAABADQAfw0AAAEAJgCpDQAAAQAMADMNAAABACwAAAA=.Varodoker:BAEANQADCgcIBwABNQAECgYIEAABAAAAAA==.Varolokur:BAEANQAECgYIEAAAAA==.',
Ve='Vegarayne:BAEANQAECgcIEAAAAA==.Versombre:BAEBNQAECoEfAAINAAkJ+SOOAQCZAwmODQAABABfAHUNAAAEAF8Afw0AAAQAXACpDQAABABgAFwNAAAEAFsAXQ0AAAMAWABlDQAAAwBQAKQNAAADAFoAMw0AAAIAYQANAAkJ+SOOAQCZAwmODQAABABfAHUNAAAEAF8Afw0AAAQAXACpDQAABABgAFwNAAAEAFsAXQ0AAAMAWABlDQAAAwBQAKQNAAADAFoAMw0AAAIAYQABNQAECgkJHwANAPkjAA==.',
Vl='Vlann:BAEANQAECgMIBQAAAA==.',
Vy='Vyedma:BAEBNQAECoEYAAMcAAgJxhY8OADwAQiODQAABABaAHUNAAAEAEsAfw0AAAMASwCpDQAAAwA1AFwNAAADAEMAXQ0AAAMAKwBlDQAAAQAKADMNAAADADEAHAAHCcwVPDgA8AEHjg0AAAMAWgB/DQAAAwBLAKkNAAABADUAXA0AAAIAQwBdDQAAAwArAGUNAAABAAoAMw0AAAMAMQAdAAQJyBPjJAATAQSODQAAAQAcAHUNAAAEAEsAqQ0AAAIALgBcDQAAAQA0AAAA.Vykacia:BAEANQAECggIAQABNQABCgQIBAABAAAAAA==.',
Xe='Xeler:BAEANQADCgEIAQABNQAECgYIDgABAAAAAA==.',
Ya='Yartdh:BAEANQADCgEIAQAAAA==.',
Za='Zaxanol:BAEANQADCggICAABNQAFFAQIBwAGAPkRAA==.',
Ze='Zehnny:BAEANQAECgIIAgABNQAECgUICgABAAAAAA==.Zenarii:BAEANQADCgIIAgABNQAECgkJHQAJAMkgAA==.',
Zh='Zhennie:BAEANQAECgUICgAAAA==.',
Zn='Zngetsu:BAEANQADCgYIBgAAAA==.',
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
