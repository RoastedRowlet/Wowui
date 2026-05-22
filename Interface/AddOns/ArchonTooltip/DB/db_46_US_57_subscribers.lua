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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Unholy','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-21',data={Ad='Adansso:BAEBLgAECn80AAIBAAkJExIxFwDMAQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgABAAkJExIxFwDMAQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJLwACALsZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJEAADACAOAA==.',
As='Ashko:BAEBLgAECn8rAAMEAAgJDBsqKgAzAghoDAAACABLAGkMAAAHAFcAawwAAAYAUQBqDAAABgBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbKioAMwIIaAwAAAgASwBpDAAABwBXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUAAQmpCtZ/ACsAAeoMAAABABsAAAA=.',
Ay='Ayodele:BAEBLgAECn8iAAIGAAkJiRfOKABVAgloDAAABQBLAGkMAAADADcAawwAAAMAPgBqDAAABQBFAGwMAAAEAEkAbQwAAAIAPwDqDAAABgBIAG4MAAAEACgAbwwAAAIAJwAGAAkJiRfOKABVAgloDAAABQBLAGkMAAADADcAawwAAAMAPgBqDAAABQBFAGwMAAAEAEkAbQwAAAIAPwDqDAAABgBIAG4MAAAEACgAbwwAAAIAJwAAAA==.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgcJCgABLgAFFAMJBgAHAL4gAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH8kAAMJAAgJARt5AgA8AghoDAAABgBBAGkMAAAHAGAAawwAAAYAWQBqDAAABQBOAGwMAAABAAQAbQwAAAEAJADqDAAACQBdAG4MAAABAGEACQAHCU4eeQIAPAIHaAwAAAYAQQBpDAAABgBSAGsMAAAFAFkAagwAAAUATgBtDAAAAQAkAOoMAAAJAF0AbgwAAAEAYQAKAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzgAAwkACQlwJOkFADMDAAkACQnwIukFADMDAAoABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8IAAILAAIJJhiaIACjAAJoDAAABQBNAGkMAAADAC0ACwACCSYYmiAAowACaAwAAAUATQBpDAAAAwAtAC4ABAp/OAACCwAJCRwgtAUA2QIACwAJCRwgtAUA2QIAAAA=.Bestiavera:BAEBLgAECn8rAAIMAAgJtg4RGABoAQhoDAAACABFAGkMAAAHADEAawwAAAcAJABqDAAABgA4AGwMAAAFACAAbQwAAAEAEADqDAAABgAjAG4MAAADABgADAAICbYOERgAaAEIaAwAAAgARQBpDAAABwAxAGsMAAAHACQAagwAAAYAOABsDAAABQAgAG0MAAABABAA6gwAAAYAIwBuDAAAAwAYAAAA.',
Br='Briggoker:BAEALgAECgMJAwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgMJAwAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8tAAINAAgJ7BgGGgDxAQhoDAAACQBbAGkMAAAIAEAAawwAAAgAUgBqDAAABgBUAGwMAAAGAEgAbQwAAAEAKwDqDAAABgBDAG4MAAABABgADQAICewYBhoA8QEIaAwAAAkAWwBpDAAACABAAGsMAAAIAFIAagwAAAYAVABsDAAABgBIAG0MAAABACsA6gwAAAYAQwBuDAAAAQAYAAAA.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJOgAOAPEjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8jAAMBAAgJCR44AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABgBfAGwMAAADAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAYAYgBpDAAABgBgAGsMAAAFAEoAagwAAAYAXwBtDAAAAQAlAOoMAAAHAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/KgACAQAICXAmCQIAhAMAAQAICXAmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8GAAIGAAMJHAVfbQDTAANoDAAAAgATAGkMAAACAA8A6gwAAAIABAAGAAMJHAVfbQDTAANoDAAAAgATAGkMAAACAA8A6gwAAAIABAABLgAFFAYJIwALAPocAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECgkJSAAEAOscAA==.Destrom:BAEBLgAECn8UAAIPAAkJuBH7ZgBvAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAPAAkJuBH7ZgBvAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8MAAIEAAQJxB3eHABWAQRoDAAABABCAGkMAAADAFUAawwAAAIASwDqDAAAAwBNAAQABAnEHd4cAFYBBGgMAAAEAEIAaQwAAAMAVQBrDAAAAgBLAOoMAAADAE0ALgAECn88AAIEAAkJ6yIHEQDBAgAEAAkJ6yIHEQDBAgAAAA==.',
Et='Ethalon:BAECLgAFFH8MAAMFAAQJxg69GQAfAQRoDAAABABIAGkMAAADABwAawwAAAIADwDqDAAAAwAiAAUABAnGDr0ZAB8BBGgMAAADAEgAaQwAAAMAHABrDAAAAgAPAOoMAAADACIABAABCbcCr4wAPgABaAwAAAEABgAuAAQKfyMAAwUACQkdGicYAFECAAUACQkdGicYAFECAAQAAgmUEzVGATgAAAAA.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAgJFgAFALUUAA==.Fallill:BAEALgAECgIJAgABLgAFFAgJFgAFALUUAA==.Falosso:BAECLgAFFH8WAAIFAAgJtRTiAQCHAghoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAG4MAAABACIABQAICbUU4gEAhwIIaAwAAAMANQBpDAAAAwBHAGsMAAADAEAAagwAAAMASwBsDAAAAwANAG0MAAABAB8A6gwAAAUAUABuDAAAAQAiAC4ABAp/MwADBQAJCY8gkwkAxwIABQAJCY8gkwkAxwIABAACCRMOZw0BawAAAAA=.',
Ga='Garlooth:BAEBLgAECn8hAAIQAAgJqh7SAQBAAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoAEAAICaoe0gEAQAIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJDAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9IAAMEAAkJ6xwdFgCeAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAJAFkAbQwAAAYASwDqDAAACwBSAG4MAAAEACoAbwwAAAEAMgAEAAkJ6xwdFgCeAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAIAFkAbQwAAAYASwDqDAAACgBSAG4MAAAEACoAbwwAAAEAMgARAAUJzwrpMwBfAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEALgAECgYJBgABLgAECgkJKwAEAAwbAA==.Grunsy:BAEALgAECgcJBQABLgAECgkJKwAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIRAAkJ8hEqEACMAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwARAAkJ8hEqEACMAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJEAADACAOAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8qAAISAAgJ+CYIAAAJAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQAEgAICfgmCAAACQMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAkAZABuDAAAAQBkAAEuAAQKBgkGAAgAAAAA.',
Ka='Kautheros:BAEBLgAECn8eAAQTAAkJ+AwhDgDBAQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwATAAkJ+AwhDgDBAQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABABDAG4MAAACAB0AbwwAAAEAHwAUAAYJUgkMSgDRAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAVAAMJmgamGgBTAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Ke='Kelo:BAEALgAECgkJAQABLgAECgkJKwAEAAwbAA==.',
Kr='Kroxychi:BAEALgAECgcJDQAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDQAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8QAAIDAAQJIA5kHgDyAARoDAAABQAqAGkMAAAFACUAawwAAAMAJgDqDAAAAwAaAAMABAkgDmQeAPIABGgMAAAFACoAaQwAAAUAJQBrDAAAAwAmAOoMAAADABoALgAECn9YAAMDAAkJfx3ACgClAgADAAkJfx3ACgClAgABAAgJrBVvGAC/AQAAAA==.',
Le='Leenfiey:BAECLgAFFH8KAAMWAAMJXCOrGAArAQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQAWAAMJXCOrGAArAQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA3wHgCeAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxYABglMJd0UAGUCABYABgkrJd0UAGUCAAEAAQkdJYJdAGkAAAAA.Lennather:BAEBLgAECn83AAIBAAkJRCXJAQBGAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAHAGAAbQwAAAYAXgDqDAAACABdAG4MAAAGAGMAbwwAAAIAWgABAAkJRCXJAQBGAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAHAGAAbQwAAAYAXgDqDAAACABdAG4MAAAGAGMAbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABYABAkWFAxAANcABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABRQDCQcAEwAcCgA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIXAAcJSRLhIABuAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABcABwlJEuEgAG4BB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8aAAMYAAYJXg78XwBIAQZoDAAABQA9AGkMAAAFACUAawwAAAYAGgBqDAAABAA1AGwMAAACABQA6gwAAAQAJQAYAAYJXg78XwBIAQZoDAAABQA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwA1AGwMAAACABQA6gwAAAMAJQAZAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEBLgAECn8aAAQBAAgJXxSAKwCCAQhoDAAABABAAGkMAAAEADQAawwAAAQAJQBqDAAAAwA9AGwMAAADAEEAbQwAAAEAFgDqDAAABgBOAG4MAAABACwAAQAHCZUTgCsAggEHaAwAAAMAJQBpDAAAAwA0AGsMAAADACUAagwAAAEAMgBsDAAAAwBBAOoMAAADAD8AbgwAAAEALAAWAAUJghbzMgARAQVoDAAAAQBAAGkMAAABADIAawwAAAEAJQBqDAAAAQA9AOoMAAACAE4AAwADCfQOYF0AkAADagwAAAEAKwBtDAAAAQAdAOoMAAABACkAAAA=.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJIwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgYJBgAAAA==.',
No='Noeyednuck:BAEALgAECgYJEAABLgAECgkJMgAYANUfAA==.',
Nu='Nuckshott:BAEBLgAECn8yAAIYAAkJ1R+EDwCmAgloDAAABwBdAGkMAAAHAFgAawwAAAcATgBqDAAABgBaAGwMAAAGAFgAbQwAAAUATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAYAAkJ1R+EDwCmAgloDAAABwBdAGkMAAAHAFgAawwAAAcATgBqDAAABgBaAGwMAAAGAFgAbQwAAAUATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJCQABLgAECgkJKwAEAAwbAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJLwAaAKwgAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJKwAEAAwbAA==.',
Qu='Quindrox:BAEALgAFFAIJAwAAAA==.Quinet:BAEBLgAECn8vAAMaAAkJrCDLCwDVAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABgBRAGwMAAAFAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAaAAkJrCDLCwDVAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAADAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAbAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAFAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQXAAkJRBouDwAaAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAXAAkJixcuDwAaAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAZAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABgAAQkVGKnlAD4AAWgMAAABAD0AAS4ABRQCCQMACAAAAAA=.Quinmanbear:BAEALgAECgcJBwABLgAFFAIJAwAIAAAAAA==.Quinroxx:BAEBLgAECn8gAAIGAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAgkDAAgAAAAA.Quinvinvin:BAEALgAECgcJDQABLgAFFAIJAwAIAAAAAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8LAAIcAAMJSAr7EQDHAANoDAAABgA2AGkMAAAEABMA6gwAAAEABAAcAAMJSAr7EQDHAANoDAAABgA2AGkMAAAEABMA6gwAAAEABAAuAAQKfx8AAhwACAnpG/YLAKECABwACAnpG/YLAKECAAAA.',
Ry='Rytiou:BAECLgAFFH8SAAIUAAUJKx1XBQCuAQVoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAgBHAOoMAAADAFIAFAAFCSsdVwUArgEFaAwAAAQAUgBpDAAABQBWAGsMAAAEAC4AagwAAAIARwDqDAAAAwBSAC4ABAp/MgACFAAJCeckWQIAjAMAFAAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMVAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFQAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABMABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAdAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmHJrcDAGADAAsACAmHJrcDAGADAB0ABQkLHz4gAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAIAAAAAA==.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJLwACALsZAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJDAAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8eAAIGAAcJoBmvAQCMAgdoDAAABgBaAGkMAAAGAFQAawwAAAUALwBqDAAABAAaAGwMAAABABAAbQwAAAEARgDqDAAABwBTAAYABwmgGa8BAIwCB2gMAAAGAFoAaQwAAAYAVABrDAAABQAvAGoMAAAEABoAbAwAAAEAEABtDAAAAQBGAOoMAAAHAFMALgAECn8dAAIGAAkJySTjCgBtAwAGAAkJySTjCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJHgAGAKAZAA==.',
Su='Sunjo:BAEALgAECgkJBwABLgAECgkJKwAEAAwbAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECgkJHgATAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwAUAEAJAA==.Tayvok:BAECLgAFFH8HAAIUAAQJQAlSJwD7AARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABQABAlACVInAPsABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8vAAIUAAkJkBwaDAB2AgAUAAkJkBwaDAB2AgAAAA==.',
Te='Tentickles:BAECLgAFFH8MAAILAAQJlx+dCgBwAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAsABAmXH50KAHABBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAILAAgJeiJyCAD9AgALAAgJeiJyCAD9AgABLgAFFAgJIwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgAWAFwjAA==.',
Th='Thecheatt:BAEBLgAECn86AAMOAAkJ8SO2BACyAgloDAAACQBjAGkMAAAJAGEAawwAAAoAYwBqDAAACABhAGwMAAAIAF0AbQwAAAIAWgDqDAAACABfAG4MAAACAEcAbwwAAAIAWQAOAAkJ3iO2BACyAgloDAAABwBhAGkMAAAGAGEAawwAAAgAYwBqDAAABgBhAGwMAAAFAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAIAWQANAAYJCB7qSQB9AQZoDAAAAgBjAGkMAAADAFEAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAQARQAAAA==.',
Ty='Tyära:BAEBLgAECn8dAAMPAAgJSwsYkwAWAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADwAHCUEJGJMAFgEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAeAAcJtQrEKADYAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAQKCQkxAAYAvxoA.',
Vi='Vigiz:BAEALgAECgcJBwAAAA==.Vilexie:BAEALgAECggJEQAAAA==.',
['Vì']='Vìgïz:BAEALgAECgEJAQABLgAECgcJBwAIAAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAXAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJCQABLgAECgkJLwACALsZAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHgATAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAUJGgALACIgAA==.',
Zi='Zibbz:BAEBLgAECn88AAMUAAkJgSWFAQBkAwloDAAABwBgAGkMAAAHAGMAawwAAAcAYgBqDAAABgBfAGwMAAAIAF8AbQwAAAcAXwDqDAAABwBbAG4MAAAIAGEAbwwAAAMAXQAUAAkJgSWFAQBkAwloDAAABgBgAGkMAAAGAGMAawwAAAYAYgBqDAAABQBfAGwMAAAHAF8AbQwAAAcAXwDqDAAABgBbAG4MAAAHAGEAbwwAAAMAXQAVAAcJyxrcBQDMAQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAAA.Zinia:BAEBLgAECn8vAAICAAkJuxkdBQBhAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJuxkdBQBhAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJPAAUAIElAA==.Zubbrael:BAEBLgAECn8lAAMLAAgJpRoaGgDHAQhoDAAACABUAGkMAAAGAEMAawwAAAUARQBqDAAABABCAGwMAAAFADoAbQwAAAEAUgDqDAAABwBHAG4MAAABACoACwAHCbYZGhoAxwEHaAwAAAYAVABpDAAABABDAGsMAAADAEUAagwAAAIAQgBsDAAAAwA6AOoMAAAFAEcAbgwAAAEAKgAdAAcJgwnhKQBLAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQk8ABQAgSUA.Zubbz:BAEBLgAECn8tAAMfAAgJLB6THgCaAghoDAAABwBeAGkMAAAIAFgAawwAAAgAUwBqDAAABQA9AGwMAAAFAFcAbQwAAAIAJQDqDAAACABYAG4MAAACADoAHwAICSwekx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6ABwABgkhHK0XAI0BBmgMAAABAEoAaQwAAAEAUABrDAAAAQBQAGoMAAABADoAbAwAAAEAOwDqDAAAAQBBAAEuAAQKCQk8ABQAgSUA.',
Zz='Zzertz:BAECLgAFFH8aAAILAAUJIiB8CQB/AQVoDAAABwBhAGkMAAAGAFMAawwAAAUAVABqDAAAAgBaAOoMAAAGAEAACwAFCSIgfAkAfwEFaAwAAAcAYQBpDAAABgBTAGsMAAAFAFQAagwAAAIAWgDqDAAABgBAAC4ABAp/KwACCwAICf8iOgYAKQMACwAICf8iOgYAKQMAAAA=.',
['Àb']='Àbeel:BAEALgAECgUJBgABLgAECggJOQAKAAYeAA==.Àbel:BAEBLgAECn85AAMKAAgJBh5jBgASAghoDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAACwBZAG4MAAADAFkACgAHCUYdYwYAEgIHaAwAAAgAVwBpDAAACQBUAGsMAAAFAFoAagwAAAUAXgBsDAAABQA9AOoMAAAJAFkAbgwAAAEAJAAJAAcJDhtNHACHAQdoDAAAAgBJAGkMAAACAE8AawwAAAMATgBqDAAAAgBdAG0MAAACACMA6gwAAAIAOwBuDAAAAgBZAAAA.Àble:BAEALgAECgQJBgABLgAECggJOQAKAAYeAA==.',
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
