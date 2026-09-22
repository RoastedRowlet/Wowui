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

local lookup = {'Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Frost','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Warrior-Arms','Paladin-Holy','Shaman-Restoration','Evoker-Preservation','Priest-Holy','Shaman-Enhancement','Priest-Discipline','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Druid-Restoration','Hunter-Survival','DeathKnight-Unholy',}
local provider = {region='US',realm='Proudmoore',name='US',type='subscribers',zone=53,date='2026-09-22',data={Ae='Aegisyr:BAEBNQAECoEaAAMBAAgKhhn+DgBAAQiODQAABABSAHUNAAAEAFYAfw0AAAQASQCpDQAABAA+AFwNAAADAEoAXQ0AAAIANwCkDQAAAQAFADMNAAAEAFMAAgAICgIW438AGAIIjg0AAAMAQAB1DQAAAwBWAH8NAAAEAEkAqQ0AAAQAPgBcDQAAAwBKAF0NAAABAAsApA0AAAEABQAzDQAAAwBIAAEABAr6Gv4OAEABBI4NAAABAFIAdQ0AAAEANwBdDQAAAQA3ADMNAAABAFMAAAA=.',
Al='Alaskannatif:BAEBNQAECoEhAAMDAAkKSRyKHQDKAgmODQAABQBcAHUNAAAEAFAAfw0AAAUASACpDQAABQBSAFwNAAAFAFYAXQ0AAAIALQBlDQAAAgBbAKQNAAABABQAMw0AAAQATwADAAgKzR6KHQDKAgiODQAABQBcAHUNAAAEAFAAfw0AAAQASACpDQAABQBSAFwNAAAFAFYAXQ0AAAEALQBlDQAAAgBbADMNAAAEAE8ABAADCqEIgEEAqAADfw0AAAEAFgBdDQAAAQAWAKQNAAABABQAAAA=.Allthatjazz:BAECNQAFFIEHAAIFAAQKZA6cAgAMAQSODQAAAwAlAHUNAAABABAAqQ0AAAIAJQAzDQAAAQA3AAUABApkDpwCAAwBBI4NAAADACUAdQ0AAAEAEACpDQAAAgAlADMNAAABADcANQAECoEuAAMFAAkK1xq7BQCbAgAFAAkKUhq7BQCbAgAGAAcK/BDLHAC9AQAAAA==.',
Am='Amysala:BAEANQAECgQIBgAAAA==.',
An='Anakinxd:BAEANQADCggIFwAAAA==.',
As='Ashla:BAEANQAECgUICAAAAA==.Aspir:BAEANQAECgEIAQABNQAECggIHgAHALkfAA==.',
Ax='Axofa:BAECNQAFFIEaAAIGAAcKyCJFAADoAgeODQAABQBjAHUNAAAEAFkAfw0AAAMAYACpDQAABQBiAFwNAAADAGAAXQ0AAAIAPAAzDQAABABSAAYABwrIIkUAAOgCB44NAAAFAGMAdQ0AAAQAWQB/DQAAAwBgAKkNAAAFAGIAXA0AAAMAYABdDQAAAgA8ADMNAAAEAFIANQAECoEdAAIGAAkKuCZCAQDKAwAGAAkKuCZCAQDKAwAAAA==.',
Az='Azlith:BAEANQAECgQIBAAAAA==.',
Ba='Balto:BAEBNQAECoEgAAIIAAkK0xuuGADmAgmODQAABwBbAHUNAAAFAFUAfw0AAAQARQCpDQAABABeAFwNAAADAEUAXQ0AAAIARABlDQAAAwAZAKQNAAACADwAMw0AAAIASwAIAAkK0xuuGADmAgmODQAABwBbAHUNAAAFAFUAfw0AAAQARQCpDQAABABeAFwNAAADAEUAXQ0AAAIARABlDQAAAwAZAKQNAAACADwAMw0AAAIASwAAAA==.',
Bi='Bigfoxenergy:BAEANQAECgQIBAABNQAECgkJJwABAAgeAA==.',
Bl='Blacksesame:BAEANQAECgUIBQABNQAFFAMIBQABAPQbAA==.Blisskiller:BAEANQADCgYIBgAAAA==.',
Bo='Boomdoom:BAEBNQAECoEkAAIJAAkKpyC1DAA3AwmODQAABQBbAHUNAAADAE4Afw0AAAQAWACpDQAABABZAFwNAAACAEcAXQ0AAAQASwBlDQAABgBOAKQNAAADAFIAMw0AAAUAYQAJAAkKpyC1DAA3AwmODQAABQBbAHUNAAADAE4Afw0AAAQAWACpDQAABABZAFwNAAACAEcAXQ0AAAQASwBlDQAABgBOAKQNAAADAFIAMw0AAAUAYQABNQAECgQIBAAKAAAAAA==.',
Br='Briarhaven:BAEANQAECgQJBAABNQAECgUJCQAKAAAAAA==.Brickedupbb:BAEANQAECgYJCgABNQAFFAYIDwAGAJEYAA==.',
Bu='Bussybolt:BAEBNQAECoEhAAQLAAkKBSD1FwCUAQmODQAABQBbAHUNAAAEAF8Afw0AAAMAUACpDQAABQBeAFwNAAADAEsAXQ0AAAMATgBlDQAAAwBVAKQNAAAEADQAMw0AAAMAVAAMAAcKlB7qNwA+AgeODQAABABbAH8NAAADAFAAXA0AAAMASwBdDQAAAgBOAGUNAAABAFUApA0AAAQANAAzDQAAAgBUAAsABQq1GvUXAJQBBY4NAAABADIAdQ0AAAQAXwCpDQAABQBeAF0NAAABAEEAMw0AAAEAIwANAAEKDiBfGABgAAFlDQAAAgBSAAAA.',
Ca='Caamm:BAEBNQAECoEjAAIOAAkK4CWVAADoAwmODQAABQBgAHUNAAAFAGIAfw0AAAQAYACpDQAABQBiAFwNAAAEAFsAXQ0AAAQAYgBlDQAAAwBiAKQNAAACAF8AMw0AAAMAYwAOAAkK4CWVAADoAwmODQAABQBgAHUNAAAFAGIAfw0AAAQAYACpDQAABQBiAFwNAAAEAFsAXQ0AAAQAYgBlDQAAAwBiAKQNAAACAF8AMw0AAAMAYwAAAA==.',
Cl='Cloudsire:BAEANQAECggIEAABNQAECggIDQAKAAAAAA==.',
Co='Coralirodeth:BAEANQAECgcIEgAAAA==.',
Cr='Crabpeople:BAEANQABCgMJAQABNQAFFAYIDQALADojAA==.',
Dd='Ddawz:BAEANQAFFAEJAQAAAA==.',
De='Decototem:BAEANQAECgYJDgAAAA==.Deprecated:BAEBNQAECoEZAAMLAAgKAhEIJgAeAQiODQAABAAjAHUNAAAEADwAfw0AAAQANACpDQAAAwAYAFwNAAADABwAZQ0AAAEACQCkDQAAAQAtADMNAAAFAFoADAAICrEN9lcAxAEIjg0AAAMAIwB1DQAAAQABAH8NAAAEADQAqQ0AAAIAEgBcDQAAAgAaAGUNAAABAAkApA0AAAEALQAzDQAAAwBaAAsABQqDDAgmAB4BBY4NAAABABQAdQ0AAAMAPACpDQAAAQAYAFwNAAABABwAMw0AAAIAGQABNQAFFAYJDQALAEkRAA==.',
Di='Dihkay:BAEANQAECgcIDgABNQAFFAcIGgAGAMgiAA==.Dinonuggiez:BAEANQAECgYIEQAAAA==.',
Dr='Draytonn:BAEANQAECgUIBQAAAA==.',
['Dã']='Dãy:BAEANQAECgYJDwAAAA==.',
Ec='Ecksreaper:BAEANQAECgEIAQABNQAFFAcIFgAPAHAjAA==.Ecksripper:BAEANQAECgMIBQABNQAFFAcIFgAPAHAjAA==.',
Ef='Effe:BAEANQAECggIDQAAAA==.',
El='Elejelly:BAEANQADCgYJBgABNQAECgEIBAAKAAAAAA==.',
Et='Ethaldra:BAEANQAECgUICgABNQAECggIGgAQADAfAA==.',
Fb='Fbiagent:BAEANQADCgEIAQABNQAECgcIEQAKAAAAAA==.',
Fe='Fearthedark:BAEANQADCgcJGQAAAA==.Fenrisyr:BAEANQAECggIAgABNQAECggIGgABAIYZAA==.',
Ga='Gadlyn:BAEANQAECgEJAQAAAA==.Gathardin:BAEANQAECgQIBAAAAA==.',
Ge='Genxwar:BAEANQAECgYIEQAAAA==.',
Gi='Girthfreedom:BAEANQAECgcIEQAAAA==.',
Go='Goodbearry:BAEANQADCggJCQABNQAECgkJIwAHAFEeAA==.',
Gu='Gutterbaby:BAEANQADCgcIEQABNQAECgQJBgAKAAAAAA==.Gutterboi:BAEANQAECgQJBgAAAA==.',
Ha='Handgonhand:BAEANQAECggIDwAAAA==.',
He='Heimdaller:BAEANQADCgUIBgAAAA==.Heimermagic:BAEBNQAECoEnAAMBAAkKCB4PAgD4AgmODQAABQBcAHUNAAAFAFoAfw0AAAUAXQCpDQAABQBaAFwNAAAEAFQAXQ0AAAQAPABlDQAABABAAKQNAAACABgAMw0AAAUAWgABAAkKCB4PAgD4AgmODQAABQBcAHUNAAAFAFoAfw0AAAQAXQCpDQAAAwBaAFwNAAADAFQAXQ0AAAQAPABlDQAABABAAKQNAAACABgAMw0AAAQAWgACAAQKPQe5JwHCAAR/DQAAAQAfAKkNAAACABQAXA0AAAEABQAzDQAAAQAQAAAA.Heka:BAEANQAECgUIEAABNQAFFAMIBgARAIoVAA==.Hewikan:BAEANQAECgUIDQAAAA==.',
Ho='Holyslanger:BAEANQADCgYIBgABNQAFFAMIBgARAIoVAA==.Hotogo:BAEANQAECgYJDQABNQAECgQICQAKAAAAAA==.',
Hu='Huddie:BAEANQAECgcJCQAAAA==.',
In='Inerstellar:BAEANQAECgUJBAABNQAECggJGgACAHQlAA==.',
Ja='Jadavoker:BAEANQAECggIEgAAAA==.Jadeiana:BAEANQAECgIIAgAAAA==.',
Ju='Justdecay:BAEANQAECggIDAABNQAECggICwAKAAAAAA==.Justhunt:BAEANQAECggICwAAAA==.',
Ka='Kaenrael:BAEBNQAECoEaAAMCAAkKdRZLTACmAgmODQAABQBKAHUNAAAEAEsAfw0AAAMATgCpDQAABABTAFwNAAACAEsAXQ0AAAEAFQBlDQAAAwAyAKQNAAACABAAMw0AAAIAKAACAAkKdRZLTACmAgmODQAABABKAHUNAAADAEsAfw0AAAMATgCpDQAABABTAFwNAAACAEsAXQ0AAAEAFQBlDQAAAwAyAKQNAAACABAAMw0AAAIAKAABAAIKjAxBIgBrAAKODQAAAQAeAHUNAAABACEAAAA=.',
La='Landinoo:BAEANQAECgEJAQABNQAFFAEJAQAKAAAAAA==.',
Le='Lenorlée:BAEANQAECgUJEQAAAA==.',
Li='Libx:BAEANQAECgcJBgABNQAECggJEAAKAAAAAA==.',
Lo='Lofreak:BAEANQAFFAIIAwABNQAFFAUICQASABcSAA==.',
Ly='Lyntara:BAEANQAECgMJBAAAAA==.',
Me='Meddah:BAEANQAECgcIDgAAAA==.',
Mf='Mfivecomp:BAEBNQAECoEaAAICAAgKdCXnHQA/AwiODQAABQBeAHUNAAAFAGIAfw0AAAQAWwCpDQAAAwBfAFwNAAACAGIAXQ0AAAIAXwBlDQAAAwBiADMNAAACAF4AAgAICnQl5x0APwMIjg0AAAUAXgB1DQAABQBiAH8NAAAEAFsAqQ0AAAMAXwBcDQAAAgBiAF0NAAACAF8AZQ0AAAMAYgAzDQAAAgBeAAAA.',
Mo='Moistbean:BAEANQAECgYIDAABNQAFFAcJGQATABUXAA==.Moltremix:BAEANQAECgYIBgABNQAFFAUICwAHANMPAA==.Moltøn:BAECNQAFFIELAAIHAAUK0w9WAgCGAQWODQAAAwBFAHUNAAACABQAfw0AAAEAEgCpDQAAAwBRADMNAAACAAwABwAFCtMPVgIAhgEFjg0AAAMARQB1DQAAAgAUAH8NAAABABIAqQ0AAAMAUQAzDQAAAgAMADUABAqBHQACBwAJCqAjqAkADQMABwAJCqAjqAkADQMAAAA=.',
Mu='Murglestraza:BAEANQAECgMIAwABNQAECgUIDQAKAAAAAA==.',
Ni='Niphie:BAEANQABCggJGAABNQAFFAYJDAASAMcGAA==.Nistral:BAEANQAECggIAgAAAA==.',
No='Nofatherpls:BAEANQAECgQICQAAAA==.',
Ny='Nyrae:BAEANQAECgQIBAAAAA==.Nyzenia:BAEANQADCgEIAQABNQAECgQIBAAKAAAAAA==.',
Om='Omghammer:BAEANQABCgQIBAABNQAFFAIJBgAUAMoEAA==.Omgtotem:BAECNQAFFIEGAAIUAAIKygRmAwCPAAKODQAAAwAVAKkNAAADAAIAFAACCsoEZgMAjwACjg0AAAMAFQCpDQAAAwACADUABAqBGgACFAAJCoETIQkAkAIAFAAJCoETIQkAkAIAAAA=.',
Ov='Overload:BAEANQAECgEIAQAAAA==.',
Pa='Pachirisu:BAECNQAFFIEZAAMTAAcKFRcZAQBqAgeODQAABQBFAHUNAAAEAEMAfw0AAAQAUACpDQAAAwA7AFwNAAADACcAXQ0AAAIADQAzDQAABABUABMABwoVFxkBAGoCB44NAAAEAEUAdQ0AAAQAQwB/DQAABABQAKkNAAADADsAXA0AAAMAJwBdDQAAAgANADMNAAAEAFQAFQABCqMBwgIAQAABjg0AAAEABAA1AAQKgRwAAxMACQq+GVYpAFoCABMACQq+GVYpAFoCABUAAgojCgUXAFkAAAAA.Patycakes:BAEBNQAECoEfAAIWAAgKLBK7FADRAQiODQAABQA3AHUNAAAEADwAfw0AAAQAQACpDQAABAAeAFwNAAAEADsAXQ0AAAMAFABlDQAAAwAsADMNAAAEACUAFgAICiwSuxQA0QEIjg0AAAUANwB1DQAABAA8AH8NAAAEAEAAqQ0AAAQAHgBcDQAABAA7AF0NAAADABQAZQ0AAAMALAAzDQAABAAlAAAA.',
Ph='Phed:BAEANQAECgYICAABNQAFFAUJCAAXACcTAA==.Phédre:BAECNQAFFIEIAAMXAAUKJxOJCQDqAAWODQAAAgBEAHUNAAABABQAfw0AAAEAUwCpDQAAAwAqADMNAAABAB8AFwADCgERiQkA6gADjg0AAAIARAB1DQAAAQAUAKkNAAADACoAEAACCk8BsxMAeQACfw0AAAEABQAzDQAAAQAAADUABAqBHAADFwAJCq0fQR8A8AIAFwAJCq0fQR8A8AIAEAAICv4TEjUAJwIAAAA=.',
Po='Pocketadin:BAEBNQAECoElAAMQAAkKBhtTFwDUAgmODQAABQBHAHUNAAAEAF4Afw0AAAQAPwCpDQAABAAhAFwNAAAEAFQAXQ0AAAQAUABlDQAABAAuAKQNAAADAD8AMw0AAAUAUwAQAAkKBhtTFwDUAgmODQAAAwBHAHUNAAADAF4Afw0AAAMAPwCpDQAAAwAhAFwNAAADAFQAXQ0AAAQAUABlDQAABAAuAKQNAAADAD8AMw0AAAMAUwAXAAYKGB+xVwD6AQaODQAAAgBSAHUNAAABAFcAfw0AAAEAUQCpDQAAAQBIAFwNAAABAEAAMw0AAAIAWAAAAA==.Pocketzzbad:BAEANQAECgcICwABNQAECgkJJQAQAAYbAA==.Powergoblin:BAEBNQAECoEbAAIYAAkK5yHZAQCEAwmODQAABABhAHUNAAAEAGIAfw0AAAMAYwCpDQAAAwBiAFwNAAADAGEAXQ0AAAMAVwBlDQAAAgAwAKQNAAABAD8AMw0AAAQAWgAYAAkK5yHZAQCEAwmODQAABABhAHUNAAAEAGIAfw0AAAMAYwCpDQAAAwBiAFwNAAADAGEAXQ0AAAMAVwBlDQAAAgAwAKQNAAABAD8AMw0AAAQAWgABNQAFFAUJCwASAEgMAA==.',
Pr='Priest:BAEANQAECgUJCQAAAA==.',
Ps='Psyhunter:BAEANQADCgIIAgABNQAFFAUIDAATAP4KAA==.Psypriest:BAECNQAFFIEMAAITAAUK/gqlBwCMAQWODQAABAAUAHUNAAABAAkAfw0AAAEACwCpDQAAAwAaADMNAAADAEkAEwAFCv4KpQcAjAEFjg0AAAQAFAB1DQAAAQAJAH8NAAABAAsAqQ0AAAMAGgAzDQAAAwBJADUABAqBHwACEwAJCuMc9RoAsAIAEwAJCuMc9RoAsAIAAAA=.Psytank:BAEANQAECgQICAABNQAFFAUIDAATAP4KAA==.',
Ra='Ragingjazzy:BAEANQADCggIFwABNQAFFAQIBwAFAGQOAA==.Rakella:BAEANQAECgcICAAAAA==.Razska:BAEANQADCgQIBAAAAA==.',
Re='Resaltt:BAEANQAECgcJEQAAAA==.Restab:BAEANQADCgcIBwABNQAECgcJEQAKAAAAAA==.Restarted:BAEANQAECgMJBQABNQAFFAcIGAAMAOEeAA==.',
Se='Senapim:BAECNQAFFIEPAAICAAYKKRXIBAAYAgaODQAAAwBfAHUNAAADACQAfw0AAAIAPACpDQAABABTAFwNAAABABIAMw0AAAIAHgACAAYKKRXIBAAYAgaODQAAAwBfAHUNAAADACQAfw0AAAIAPACpDQAABABTAFwNAAABABIAMw0AAAIAHgA1AAQKgSgAAgIACQrZJJcKAJwDAAIACQrZJJcKAJwDAAAA.',
Sh='Shadoslinger:BAEANQAECggIDAABNQAFFAMIBgARAIoVAA==.Shelannigans:BAEANQAECggIEgAAAA==.Shiëlds:BAECNQAFFIELAAMTAAUKQRWfBQC8AQWODQAAAwA6AHUNAAACAE4Afw0AAAIAJwCpDQAAAwAxAFwNAAABAC0AEwAFCkEVnwUAvAEFjg0AAAIAOgB1DQAAAgBOAH8NAAACACcAqQ0AAAMAMQBcDQAAAQAtABUAAQq4DlYCAE4AAY4NAAABACUANQAECoEjAAMTAAkKVyBKDgANAwATAAkKxRxKDgANAwAVAAgKqB1aAwBoAgAAAA==.',
Si='Silphie:BAECNQAFFIEMAAISAAYKxwbZAwDDAQaODQAAAwAJAHUNAAABAA0Afw0AAAIABgCpDQAAAwAbAFwNAAABAAoAMw0AAAIAJAASAAYKxwbZAwDDAQaODQAAAwAJAHUNAAABAA0Afw0AAAIABgCpDQAAAwAbAFwNAAABAAoAMw0AAAIAJAA1AAQKgSAAAhIACQrpGdkKALcCABIACQrpGdkKALcCAAAA.',
Sl='Slimmy:BAEANQAECgcIDQABNQAFFAYIDwAGAJEYAA==.Slimrodeo:BAECNQAFFIEPAAIGAAYKkRhpAQAqAgaODQAAAwBiAHUNAAADAD4Afw0AAAMAQACpDQAAAwBTAFwNAAABABoAMw0AAAIAKgAGAAYKkRhpAQAqAgaODQAAAwBiAHUNAAADAD4Afw0AAAMAQACpDQAAAwBTAFwNAAABABoAMw0AAAIAKgA1AAQKgRwAAgYACQrBI+IEAFcDAAYACQrBI+IEAFcDAAAA.Slimthiq:BAEANQAECgcICQABNQAFFAYIDwAGAJEYAA==.',
Sm='Smallpal:BAEBNQAECoEfAAMQAAkKSxkqGgC/AgmODQAABABRAHUNAAAEADMAfw0AAAQARACpDQAABABTAFwNAAAEADwAXQ0AAAQASQBlDQAAAwA8AKQNAAABACUAMw0AAAMAQAAQAAkKSxkqGgC/AgmODQAAAwBRAHUNAAADADMAfw0AAAQARACpDQAAAwBTAFwNAAAEADwAXQ0AAAQASQBlDQAAAwA8AKQNAAABACUAMw0AAAMAQAAXAAMKbgqu5wCKAAOODQAAAQAZAHUNAAABAAsAqQ0AAAEAKwAAAA==.',
Sp='Splãsh:BAEANQAECgQJBgABNQAFFAUICwATAEEVAA==.',
St='Stebdruid:BAEANQAECgUIBgABNQAFFAUICAAIANUVAA==.Stebmage:BAEANQAECgEIAQABNQAFFAUICAAIANUVAA==.Stebshaman:BAECNQAFFIEIAAIIAAUK1RW+BACbAQWODQAAAgAzAHUNAAACACkAfw0AAAEASgCpDQAAAQA0ADMNAAACADsACAAFCtUVvgQAmwEFjg0AAAIAMwB1DQAAAgApAH8NAAABAEoAqQ0AAAEANAAzDQAAAgA7ADUABAqBHAACCAAJChQkTgcAjgMACAAJChQkTgcAjgMAAAA=.',
Sy='Sylyphe:BAEANQADCgYIDAABNQAFFAYJDAASAMcGAA==.Synfal:BAEANQABCgYIBgABNQAFFAIIBgAEALMOAA==.',
Ta='Tayluor:BAEBNQAECoEhAAIXAAkKvCXeAgDXAwmODQAABQBiAHUNAAADAGAAfw0AAAQAYgCpDQAABABiAFwNAAAEAGMAXQ0AAAQAYgBlDQAAAwBfAKQNAAABAFQAMw0AAAUAYgAXAAkKvCXeAgDXAwmODQAABQBiAHUNAAADAGAAfw0AAAQAYgCpDQAABABiAFwNAAAEAGMAXQ0AAAQAYgBlDQAAAwBfAKQNAAABAFQAMw0AAAUAYgAAAA==.Tayvoix:BAEANQADCgUIBQABNQAECgkJIQAXALwlAA==.',
Th='Tharavol:BAEANQABCgEIAQAAAA==.Thottpatrol:BAEBNQAFFIETAAIZAAcKOCIKAADWAgeODQAAAwBUAHUNAAAEAGIAfw0AAAMAYgCpDQAAAwBYAFwNAAACAGQAXQ0AAAEAOAAzDQAAAwBXABkABwo4IgoAANYCB44NAAADAFQAdQ0AAAQAYgB/DQAAAwBiAKkNAAADAFgAXA0AAAIAZABdDQAAAQA4ADMNAAADAFcAAAA=.Thottpattrol:BAEANQAECgUIBQABNQAFFAcIEwAZADgiAA==.Thottyp:BAEANQAFFAIIBAABNQAFFAcIEwAZADgiAA==.Thottypal:BAEANQAFFAEIAQABNQAFFAcIEwAZADgiAA==.Thottysquirt:BAEANQAECgEIAQABNQAFFAcIEwAZADgiAA==.',
Ti='Tierán:BAEBNQAECoEbAAQDAAgK6CW5CABoAwiODQAABQBjAHUNAAAEAGIAfw0AAAQAYQCpDQAABABhAFwNAAADAF0AXQ0AAAMAYwBlDQAAAQBcADMNAAADAGEAAwAICugluQgAaAMIjg0AAAMAYwB1DQAAAgBiAH8NAAACAGEAqQ0AAAIAYQBcDQAAAgBdAF0NAAADAGMAZQ0AAAEAXAAzDQAAAQBhABoABgo1INQEAP4BBo4NAAABAFwAdQ0AAAEAWAB/DQAAAQBUAKkNAAACAFQAXA0AAAEAPwAzDQAAAQBQAAQABArmGdcxACEBBI4NAAABAD4AdQ0AAAEANgB/DQAAAQBAADMNAAABAFMAAAA=.',
To='Totsuzenshi:BAEBNQAECoEYAAIbAAgKfBNYKQAdAgiODQAABAA8AHUNAAAEAEcAfw0AAAQAPACpDQAAAwAYAFwNAAADAFAAXQ0AAAEAIwBlDQAAAQAUADMNAAAEAC0AGwAICnwTWCkAHQIIjg0AAAQAPAB1DQAABABHAH8NAAAEADwAqQ0AAAMAGABcDQAAAwBQAF0NAAABACMAZQ0AAAEAFAAzDQAABAAtAAAA.',
Tr='Trem:BAEANQAECgIIAgABNQAFFAcIGAAMAOEeAA==.Tremens:BAECNQAFFIEYAAQMAAcK4R48AACaAgeODQAAAwBjAHUNAAAEAEUAfw0AAAQASQCpDQAABABiAFwNAAADAEYAXQ0AAAIAPgAzDQAABABPAAwABwqPGzwAAJoCB44NAAADAGMAdQ0AAAEAIgB/DQAABABJAKkNAAAEAGIAXA0AAAMARgBdDQAAAgA+ADMNAAABADYACwABCh4bpg0AXgABdQ0AAAMARQANAAEKFB+LBABYAAEzDQAAAwBPADUABAqBJAADDAAJCi8ljxEAAQMADAAHCgImjxEAAQMACwAICmAZHwgAYgIAAAA=.',
Tw='Twelvedread:BAEANQAECgYIBgABNQAECggIHgAXAJEWAA==.Twlvepeers:BAEBNQAECoEeAAMXAAgKkRalVQACAgiODQAABQBCAHUNAAAEAE4Afw0AAAQATQCpDQAABAAzAFwNAAADACIAXQ0AAAIAPABlDQAAAwAcADMNAAAFAEAAFwAICpEWpVUAAgIIjg0AAAUAQgB1DQAABABOAH8NAAAEAE0AqQ0AAAQAMwBcDQAAAwAiAF0NAAACADwAZQ0AAAMAHAAzDQAAAwBAABAAAQpyDxTQADkAATMNAAACACcAAAA=.',
Ty='Typhoidbeary:BAEBNQAECoEjAAMHAAkKUR4qEgCUAgmODQAABQBUAHUNAAAFAFQAfw0AAAUAVQCpDQAABQBfAFwNAAAFAFoAXQ0AAAIAQABlDQAAAgBJAKQNAAABACgAMw0AAAUATwAHAAkKexgqEgCUAgmODQAAAQAwAHUNAAABAE4Afw0AAAEAPACpDQAAAQBBAFwNAAABAE8AXQ0AAAIAQABlDQAAAQA1AKQNAAABACgAMw0AAAEASQAbAAcKHCHxHQB1AgeODQAABABUAHUNAAAEAFQAfw0AAAQAVQCpDQAABABfAFwNAAAEAFoAZQ0AAAEASQAzDQAABABPAAAA.',
['Tè']='Tèren:BAEANQAECgYJCAAAAA==.',
Va='Valenaar:BAEANQADCgYICQAAAA==.',
Vi='Virtuel:BAEANQADCggIEQAAAA==.',
Wo='Worldboss:BAEANQADCgEIAQABNQAECgkJIwAOAOAlAA==.',
['Wì']='Wìzardlìzard:BAEANQAFFAEIAQAAAA==.',
Za='Zaxdk:BAEANQADCggJCAABNQAFFAYIDQATAO0OAA==.Zaxpally:BAEANQAECgcIBwABNQAFFAYIDQATAO0OAA==.Zayvointh:BAEANQAECgUIBgABNQAECgcIEgAKAAAAAA==.',
Zo='Zosima:BAEANQAECgUIDgAAAA==.',
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
