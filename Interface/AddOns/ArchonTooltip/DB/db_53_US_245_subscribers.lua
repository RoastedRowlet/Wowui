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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Warlock-Destruction','DeathKnight-Unholy','Warlock-Demonology','Shaman-Elemental','Mage-Arcane','Mage-Frost','Mage-Fire','Warrior-Arms','Paladin-Protection','Druid-Restoration','Druid-Balance','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','DeathKnight-Blood','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Priest-Discipline','Priest-Holy','Monk-Brewmaster','Shaman-Restoration',}
local provider = {region='US',realm="Zul'jin",name='US',type='subscribers',zone=53,date='2026-09-08',data={Ae='Aerostatics:BAEANQAECgIIAgAAAA==.',
Al='Alekdk:BAEANQAFFAIIAgAAAA==.Alekwar:BAEANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Aloro:BAEBNQAECoEXAAICAAkJXBsLBAD8AgmODQAAAwBUAHUNAAADAFoAfw0AAAMAPwCpDQAAAwBPAFwNAAACAF4AXQ0AAAIALQBlDQAAAwA8AKQNAAABABoAMw0AAAMAVQACAAkJXBsLBAD8AgmODQAAAwBUAHUNAAADAFoAfw0AAAMAPwCpDQAAAwBPAFwNAAACAF4AXQ0AAAIALQBlDQAAAwA8AKQNAAABABoAMw0AAAMAVQAAAA==.Altar:BAEBNQAECoEaAAIDAAkJMiJrAAC6AwmODQAAAwBiAHUNAAADAGEAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGEAXQ0AAAMATgBlDQAAAwBhAKQNAAACABgAMw0AAAMAXwADAAkJMiJrAAC6AwmODQAAAwBiAHUNAAADAGEAfw0AAAMAYwCpDQAAAwBjAFwNAAADAGEAXQ0AAAMATgBlDQAAAwBhAKQNAAACABgAMw0AAAMAXwAAAA==.',
An='Ancestor:BAEANQADCggICAABNQAFFAIIAgABAAAAAA==.Andrilla:BAEANQAECgcIEAAAAA==.Angelstars:BAEANQAECgEIAQABNQAECggIEgABAAAAAA==.Antarys:BAEANQAECgMIAwABNQAECgkJFwACAFwbAA==.Antpala:BAEANQAECgMIBwAAAA==.Antsjamaan:BAEANQADCgcIFgABNQAECgMIBwABAAAAAA==.Anzay:BAEANQAECgcIBwABNQAECgkJGQAEAD4kAA==.',
Ar='Arbiter:BAEANQAECgcIEAAAAA==.Arklos:BAEBNQAECoEZAAMDAAkJthgpDgDhAQmODQAAAwBbAHUNAAADAFgAfw0AAAMARQCpDQAAAwAvAFwNAAADADwAXQ0AAAMAUwBlDQAAAgAVAKQNAAACABsAMw0AAAMAUAADAAcJ3hMpDgDhAQeODQAAAQA4AHUNAAADAFgAfw0AAAEAFgCpDQAAAwAvAFwNAAABAAgAXQ0AAAMAUwAzDQAAAQAxAAUABgnQFvMkAOABBo4NAAACAFsAfw0AAAIARQBcDQAAAgA8AGUNAAACABUApA0AAAIAGwAzDQAAAgBQAAAA.',
As='Aspir:BAEANQAECgcIDwAAAA==.',
Ba='Bangkook:BAEANQAECgcIDAAAAA==.Bayazi:BAEBNQAFFIEPAAIGAAcJhSMKAADvAgeODQAAAwBcAHUNAAACAGAAfw0AAAIAYACpDQAAAwBiAFwNAAACAEsAXQ0AAAEAZAAzDQAAAgBMAAYABwmFIwoAAO8CB44NAAADAFwAdQ0AAAIAYAB/DQAAAgBgAKkNAAADAGIAXA0AAAIASwBdDQAAAQBkADMNAAACAEwAAAA=.',
Be='Bearemanalow:BAEANQAECgMIBgABNQAECgQIBAABAAAAAA==.Belthion:BAEBNQAECoEYAAIGAAkJ7CRbAQDLAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBhAFwNAAACAGEAXQ0AAAIAWABlDQAAAwBjAKQNAAACAEUAMw0AAAMAYwAGAAkJ7CRbAQDLAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYgCpDQAAAwBhAFwNAAACAGEAXQ0AAAIAWABlDQAAAwBjAKQNAAACAEUAMw0AAAMAYwAAAA==.',
Bi='Bigswordswin:BAEANQAECgQIBQAAAA==.',
Bl='Bluntywaifu:BAEANQAECgUIDAAAAA==.',
Bo='Bobboatraces:BAEANQAECgYIDQABNQAFFAMIBAABAAAAAA==.Boomgheera:BAEANQAECgcIDgABNQAFFAIIAgABAAAAAA==.',
Br='Brunidk:BAEANQAECgUIBwAAAA==.',
Bu='Burningfex:BAEANQADCggIDQAAAA==.',
By='Byce:BAEANQAECgYIBgAAAA==.',
Ca='Cappm:BAEANQAECggIEgAAAA==.Carriedegirl:BAEANQAECgQIBAABNQAECgUIBQABAAAAAA==.',
Ch='Chabdormu:BAEANQAECgMIAwABNQAECgUICAABAAAAAA==.Chabu:BAEANQAECgUICAAAAA==.',
Co='Cohrentouch:BAEANQAECgMIBwAAAA==.Comboslice:BAEANQAECgYICwAAAA==.Condemdznuts:BAEANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Ct='Cta:BAEANQAECggIAQAAAA==.',
Da='Daeroth:BAEANQADCggIDQABNQAECgYICQABAAAAAA==.Darkcam:BAECNQAFFIEIAAIHAAYJgBjfAAA1AgaODQAAAwAxAHUNAAABAEwAfw0AAAEAIgCpDQAAAQAuAFwNAAABAFQAMw0AAAEAVAAHAAYJgBjfAAA1AgaODQAAAwAxAHUNAAABAEwAfw0AAAEAIgCpDQAAAQAuAFwNAAABAFQAMw0AAAEAVAA1AAQKgSIABAcACQnIJYwBANgDAAcACQm1JYwBANgDAAgABAlnHewGAHEBAAkAAQlUGkMEAFMAAAAA.',
De='Demoncam:BAEANQAECgcICwABNQAFFAYICAAHAIAYAA==.',
Di='Dirtymikee:BAEANQAECgYIBgAAAA==.',
Do='Doloco:BAEANQADCgYIBgABNQAECgYIBwABAAAAAA==.',
Dr='Dragheera:BAEANQAFFAIIAgAAAA==.Draloc:BAEANQAECgYIBwAAAA==.Drexen:BAEANQAECgEIAQAAAA==.',
Dy='Dyanna:BAEANQAECgYIBgABNQAECgkJGQAKAM8hAA==.',
['Dó']='Dóubleamp:BAEANQADCgEIAgABNQAFFAcIDQADAA8UAA==.',
El='Elkaurif:BAEANQAECgEIAQAAAA==.',
En='Enraeged:BAEANQAECgEIAQABNQAECgcICAABAAAAAA==.',
Ev='Evimonk:BAEANQAECgYIBgABNQAFFAYICQALAPEMAA==.Evipaladin:BAEBNQAFFIEJAAILAAYJ8QxdAADTAQaODQAAAwA0AHUNAAABABEAfw0AAAEAMQCpDQAAAgAoAFwNAAABAAoAMw0AAAEAHQALAAYJ8QxdAADTAQaODQAAAwA0AHUNAAABABEAfw0AAAEAMQCpDQAAAgAoAFwNAAABAAoAMw0AAAEAHQAAAA==.',
Ex='Exwarlock:BAEANQADCgQIBAABNQAECgYIBgABAAAAAA==.',
Fa='Fatalpink:BAEANQAECgUIBAAAAA==.',
Fe='Felendruid:BAEBNQAECoEXAAMMAAkJmhyeBADdAgmODQAAAwBLAHUNAAADAE0Afw0AAAMAWwCpDQAAAwA3AFwNAAADAEwAXQ0AAAMAPgBlDQAAAgBSAKQNAAABACgAMw0AAAIAYAAMAAkJmhyeBADdAgmODQAAAwBLAHUNAAADAE0Afw0AAAMAWwCpDQAAAwA3AFwNAAADAEwAXQ0AAAMAPgBlDQAAAgBSAKQNAAABACgAMw0AAAEAYAANAAEJKh1dUQBUAAEzDQAAAQBKAAAA.Felenpal:BAEANQAECgQIBAABNQAECgkJFwAMAJocAA==.Felenvoker:BAECNQAFFIEMAAIOAAcJPRNGAAB4AgeODQAAAgAVAHUNAAACAFQAfw0AAAIANwCpDQAAAgAOAFwNAAABADsAXQ0AAAEAGQAzDQAAAgBTAA4ABwk9E0YAAHgCB44NAAACABUAdQ0AAAIAVAB/DQAAAgA3AKkNAAACAA4AXA0AAAEAOwBdDQAAAQAZADMNAAACAFMANQAECoEaAAQOAAkJuhv3BgCtAgAOAAkJuhv3BgCtAgAPAAMJEiJYBgAoAQAQAAEJIh3PHgBVAAABNQAECgkJFwAMAJocAA==.Felzero:BAEANQAECgcICwAAAA==.',
Fi='Fieldbritish:BAEBNQAECoEYAAQRAAkJKCROAABOAwmODQAAAwBhAHUNAAADAGMAfw0AAAMAXgCpDQAAAwBiAFwNAAADAFcAXQ0AAAMAXQBlDQAAAgBXAKQNAAABAEsAMw0AAAMAYwARAAgJACVOAABOAwiODQAAAwBhAHUNAAACAGMAfw0AAAIAXgCpDQAAAgBiAFwNAAACAFcAXQ0AAAEAXQBlDQAAAQBXADMNAAADAGMAAwAGCTAbKQ0A7QEGdQ0AAAEAEQCpDQAAAQBgAFwNAAABAEkAXQ0AAAIAWQBlDQAAAQBAAKQNAAABAEsABQABCW0V2o8ANAABfw0AAAEANgAAAA==.Firstfield:BAEANQAECgIIAwABNQAECgkJGAARACgkAA==.',
Fo='Fofer:BAEBNQAECoEZAAISAAkJWiUwAQDJAwmODQAAAwBiAHUNAAADAGAAfw0AAAMAXwCpDQAAAwBhAFwNAAADAF0AXQ0AAAMAWQBlDQAAAwBeAKQNAAACAF8AMw0AAAIAYQASAAkJWiUwAQDJAwmODQAAAwBiAHUNAAADAGAAfw0AAAMAXwCpDQAAAwBhAFwNAAADAF0AXQ0AAAMAWQBlDQAAAwBeAKQNAAACAF8AMw0AAAIAYQAAAA==.',
Fr='Fro:BAEBNQAECoEZAAMHAAkJxyFbEQAzAwmODQAABABgAHUNAAAEAF4Afw0AAAMAWgCpDQAABABiAFwNAAADAGIAXQ0AAAIAYABlDQAAAgBdAKQNAAABAB8AMw0AAAIATwAHAAkJyx5bEQAzAwmODQAAAwBgAHUNAAACAEoAfw0AAAMAWgCpDQAAAgBdAFwNAAACADUAXQ0AAAIAYABlDQAAAgBdAKQNAAABAB8AMw0AAAEATwAIAAUJ2xmSDQDHAAWODQAAAQATAHUNAAACAF4AqQ0AAAIAYgBcDQAAAQBiADMNAAABABQAAAA=.Frozenwater:BAEANQAECgIIAgAAAA==.',
Go='Gothgock:BAEANQAECgYIBwABNQAECgYICAABAAAAAA==.',
Gr='Grayparson:BAEANQAECgYIBgAAAA==.Greenbuge:BAEANQAECgMIAgABNQAECgkJGAATAN0mAA==.',
In='Inabeninging:BAEBNQAECoEZAAMEAAkJPiT8BQBMAwmODQAAAwBhAHUNAAADAGEAfw0AAAMAYgCpDQAAAwBgAFwNAAADAGEAXQ0AAAMAVABlDQAAAwBUAKQNAAACAFEAMw0AAAIAYQAEAAkJTiP8BQBMAwmODQAAAgBhAHUNAAACAGEAfw0AAAIAXwCpDQAAAgBdAFwNAAACAFwAXQ0AAAEASQBlDQAAAgBUAKQNAAABAFEAMw0AAAIAYQACAAgJSyJwAwAWAwiODQAAAQBgAHUNAAABAGEAfw0AAAEAYgCpDQAAAQBgAFwNAAABAGEAXQ0AAAIAVABlDQAAAQBSAKQNAAABADAAAAA=.',
Ip='Ipposaur:BAEANQAECgMIAwAAAA==.',
Ir='Irishthree:BAEANQAECgcIEQAAAA==.',
Iu='Iunarx:BAEANQAECgYICQABNQAFFAUIBQALAHAGAA==.',
Ja='Jaye:BAEANQAECgUICAAAAA==.',
Ji='Jimmi:BAEBNQAECoEYAAICAAkJMRuSBQC5AgmODQAAAwBZAHUNAAADAEoAfw0AAAMAWgCpDQAAAwBOAFwNAAADAFUAXQ0AAAMAKABlDQAAAgA/AKQNAAABABMAMw0AAAMAUwACAAkJMRuSBQC5AgmODQAAAwBZAHUNAAADAEoAfw0AAAMAWgCpDQAAAwBOAFwNAAADAFUAXQ0AAAMAKABlDQAAAgA/AKQNAAABABMAMw0AAAMAUwAAAA==.',
Ju='Jupitermage:BAEANQAFFAMIAwAAAA==.',
Ka='Kaurif:BAEANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Ke='Kellwaterboy:BAEANQADCgcICwABNQAECgkJGQAOAFwbAA==.Kelnutdragin:BAEBNQAECoEZAAIOAAkJXBsYBgDHAgmODQAAAwBBAHUNAAADAEgAfw0AAAMASwCpDQAAAwBXAFwNAAADAFAAXQ0AAAMAQwBlDQAAAgBOAKQNAAACACYAMw0AAAMAQAAOAAkJXBsYBgDHAgmODQAAAwBBAHUNAAADAEgAfw0AAAMASwCpDQAAAwBXAFwNAAADAFAAXQ0AAAMAQwBlDQAAAgBOAKQNAAACACYAMw0AAAMAQAAAAA==.',
Kh='Khazak:BAEBNQAECoEXAAMCAAkJdiI9BQDHAgmODQAAAgBfAHUNAAACAFYAfw0AAAMAXACpDQAAAwBbAFwNAAADAFUAXQ0AAAMAXgBlDQAAAwBMAKQNAAACAFYAMw0AAAIAVQACAAgJjiI9BQDHAgiODQAAAQBfAH8NAAACAFwAqQ0AAAIAWwBcDQAAAQBVAF0NAAACAF4AZQ0AAAEATACkDQAAAgBWADMNAAABAFUABAAICYMblRoALAIIjg0AAAEAWwB1DQAAAgBWAH8NAAABAFMAqQ0AAAEAUABcDQAAAgAHAF0NAAABAFgAZQ0AAAIAPwAzDQAAAQA9AAAA.',
Ki='Kimiqt:BAEANQAECgYICAAAAA==.',
Ko='Koaladh:BAEBNQAECoEYAAMUAAkJXh6cBgAgAwmODQAAAwBcAHUNAAADAFYAfw0AAAMAUACpDQAAAwBUAFwNAAADAEEAXQ0AAAMAQwBlDQAAAgBGAKQNAAABADsAMw0AAAMAWgAUAAkJXh6cBgAgAwmODQAAAwBcAHUNAAADAFYAfw0AAAMAUACpDQAAAwBUAFwNAAADAEEAXQ0AAAIAQwBlDQAAAgBGAKQNAAABADsAMw0AAAMAWgAVAAEJHQKJEAA2AAFdDQAAAQAFAAAA.Koalaremixsh:BAEANQAECgEIAQABNQAECgkJGAAUAF4eAA==.Koàra:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.',
Kr='Kramix:BAEANQAECgcIEQAAAA==.Kramon:BAEANQAECgQICwABNQAECgcIEQABAAAAAA==.Krypticshado:BAEANQADCggIEAABNQAFFAUIBwAWAKoNAA==.Krypticstab:BAEBNQAFFIEHAAMWAAUJqg3ZAQBTAQWODQAAAwBVAHUNAAABAAAAfw0AAAEADgCpDQAAAQBEADMNAAABAAQAFgAECWEK2QEAUwEEjg0AAAMAVQB1DQAAAQAAAH8NAAABAA4AMw0AAAEABAAXAAEJ0BpUAwBjAAGpDQAAAQBEAAAA.',
Ky='Kylier:BAEANQAECgcIDQABNQAFFAMIBAABAAAAAA==.Kymmie:BAEANQAECgIIAgABNQAECgcIDgABAAAAAA==.',
['Kó']='Kóara:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.',
La='Lapinlock:BAEANQADCgYIDAABNQAECgcIEwABAAAAAA==.Lapinpal:BAEANQAECgEIAQABNQAECgcIEwABAAAAAA==.Lapinw:BAEANQAECgcIEwAAAA==.Layria:BAEBNQAFFIEIAAIMAAUJxwmhAACUAQWODQAAAwAfAHUNAAABAAgAfw0AAAEAEgCpDQAAAgAUADMNAAABAC4ADAAFCccJoQAAlAEFjg0AAAMAHwB1DQAAAQAIAH8NAAABABIAqQ0AAAIAFAAzDQAAAQAuAAAA.',
Le='Lenbar:BAEANQAECgcICwAAAA==.',
Li='Likp:BAEANQAECgQIBAAAAA==.Lilsym:BAEANQAECgYIBwABNQAFFAYIDQANABMjAA==.',
Lo='Login:BAEANQAECgcIDAAAAA==.Louss:BAEANQAECgcIDQAAAA==.Louzer:BAEANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Lu='Luñar:BAEANQAFFAQIBAABNQAFFAUIBQALAHAGAA==.',
['Lâ']='Lâra:BAEBNQAFFIELAAIHAAYJ2hE1AQARAgaODQAAAgAgAHUNAAACADwAfw0AAAIAPwCpDQAAAgA+AFwNAAABACQAMw0AAAIAEQAHAAYJ2hE1AQARAgaODQAAAgAgAHUNAAACADwAfw0AAAIAPwCpDQAAAgA+AFwNAAABACQAMw0AAAIAEQAAAA==.',
Ma='Madthelock:BAEBNQAFFIELAAQFAAcJ6x9JAAD6AQeODQAAAQBiAHUNAAABAEgAfw0AAAEAUACpDQAAAwBfAFwNAAACAGEAXQ0AAAEAKAAzDQAAAgBWAAUABQmDH0kAAPoBBY4NAAABAGIAfw0AAAEAUACpDQAAAQBWAFwNAAACAGEAXQ0AAAEAKAADAAIJziB0AQDVAAJ1DQAAAQBIAKkNAAACAF8AEQABCesh8gAAZgABMw0AAAIAVgABNQAFFAcJCwAFAOsfAA==.Madthepally:BAEANQAECggIDAABNQAFFAcJCwAFAOsfAA==.Mangoslurpee:BAEANQAECgcIDQAAAA==.Mattukii:BAEANQAECggIEgAAAA==.Mattyliight:BAEBNQAECoEZAAMYAAkJfxsZBwC3AgmODQAAAwBcAHUNAAADAFAAfw0AAAMAVQCpDQAAAwBEAFwNAAADACoAXQ0AAAMAVQBlDQAAAwBKAKQNAAACACcAMw0AAAIAPwAYAAkJfxsZBwC3AgmODQAAAwBcAHUNAAADAFAAfw0AAAMAVQCpDQAAAwBEAFwNAAADACoAXQ0AAAMAVQBlDQAAAwBKAKQNAAABACcAMw0AAAIAPwATAAEJIQLFJAA7AAGkDQAAAQAFAAAA.Mauxn:BAEANQADCgUIBQABNQAECgQIBQABAAAAAA==.Mauxuam:BAEANQAECgQIBQAAAA==.',
Me='Megabloks:BAEANQAECgIIAgAAAA==.',
Mi='Mirainikky:BAEANQAECgQIBAABNQAFFAQIBQAXAN4RAA==.',
Mt='Mts:BAEBNQAECoEZAAMZAAkJCR//IgAdAgmODQAABABjAHUNAAADAGMAfw0AAAMAWwCpDQAABQBPAFwNAAADAGMAXQ0AAAIAVgBlDQAAAgAnAKQNAAABAC4AMw0AAAIASQAaAAcJlxuRDwBXAgeODQAAAgBYAH8NAAACAFAAqQ0AAAQATwBdDQAAAgBWAGUNAAACACcApA0AAAEALgAzDQAAAQBJABkABgkKIv8iAB0CBo4NAAACAGMAdQ0AAAMAYwB/DQAAAQBbAKkNAAABAEYAXA0AAAMAYwAzDQAAAQA+AAAA.',
Mu='Mudkìp:BAEANQAECgUIBQABNQAFFAYICwAbAPwWAA==.',
Ne='Nexed:BAEANQAECggIEwABNQAECgEIAQABAAAAAA==.Nexxed:BAEANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Ni='Nidhildr:BAEANQADCgcIDgAAAA==.',
Pa='Pallyzilla:BAEANQAECgYIDAABNQAECgkJHAAcAKgcAA==.Pawnshopkell:BAEANQADCgUIBQABNQAECgkJGQAOAFwbAA==.',
Pe='Pessimistick:BAEANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Po='Pocadots:BAEANQAECgcIDAAAAA==.Portalingus:BAEANQAECgEIAQAAAA==.Powerscaling:BAEANQAFFAEIAQABNQAFFAIIAgABAAAAAA==.',
Pr='Priestzilla:BAEBNQAECoEcAAMcAAkJqBwjAQDmAgmODQAABABeAHUNAAAEAFoAfw0AAAMAUACpDQAABABPAFwNAAADAFMAXQ0AAAMAUwBlDQAAAgBEAKQNAAABAAYAMw0AAAQASQAcAAgJ6h8jAQDmAgiODQAABABeAHUNAAAEAFoAfw0AAAMAUACpDQAABABPAFwNAAADAFMAXQ0AAAMAUwBlDQAAAgBEADMNAAAEAEkAHQABCZYCHmQAQgABpA0AAAEABgAAAA==.',
Qu='Queasy:BAEANQADCgUIBQABNQAECgcIDAABAAAAAA==.',
Ra='Rammorage:BAEANQAECgEIAQAAAA==.',
Re='Reversedmilk:BAEANQAECgQIBgABNQAECgkJFwANAMcgAA==.Reversemilk:BAEBNQAECoEXAAINAAkJxyAgBgBMAwmODQAAAgBgAHUNAAADAGAAfw0AAAMAXgCpDQAAAwBbAFwNAAADAFsAXQ0AAAMAWQBlDQAAAgBKAKQNAAACAC0AMw0AAAIASwANAAkJxyAgBgBMAwmODQAAAgBgAHUNAAADAGAAfw0AAAMAXgCpDQAAAwBbAFwNAAADAFsAXQ0AAAMAWQBlDQAAAgBKAKQNAAACAC0AMw0AAAIASwAAAA==.',
Ri='Rinmage:BAEANQADCgIIAgABNQAECgMIBQABAAAAAA==.Rinruid:BAEANQAECgMIBQAAAA==.Rispir:BAEBNQAECoEeAAMaAAkJHyWNAgCCAwmODQAABgBjAHUNAAAEAGAAfw0AAAQAYQCpDQAABABgAFwNAAADAGMAXQ0AAAIAYQBlDQAAAgBdAKQNAAACAFAAMw0AAAMAXwAaAAkJPCGNAgCCAwmODQAABQBjAHUNAAAEAGAAfw0AAAQAYQCpDQAABABgAFwNAAABAAkAXQ0AAAIAYQBlDQAAAgBdAKQNAAACAFAAMw0AAAMAXwAZAAIJVRymcgC1AAKODQAAAQAtAFwNAAACAGMAAAA=.',
Ro='Robert:BAEBNQAECoEZAAIeAAkJ6CEDAQBxAwmODQAAAwBcAHUNAAADAF8Afw0AAAMAVwCpDQAAAwBgAFwNAAADAFIAXQ0AAAMASwBlDQAAAwBQAKQNAAABAEcAMw0AAAMAYgAeAAkJ6CEDAQBxAwmODQAAAwBcAHUNAAADAF8Afw0AAAMAVwCpDQAAAwBgAFwNAAADAFIAXQ0AAAMASwBlDQAAAwBQAKQNAAABAEcAMw0AAAMAYgAAAA==.Roloco:BAEANQAECgQIBQABNQAECgYIBwABAAAAAA==.',
Sa='Saebyeok:BAEANQADCgUIBQABNQAECgcIDAABAAAAAA==.',
Sc='Scalier:BAEANQAFFAMIBAAAAA==.Scewb:BAEANQADCgYIBgABNQAFFAQIBQAXAN4RAA==.',
Se='Seansevoker:BAEANQAECgYICwABNQAFFAUICAAfAOQhAA==.Seansshaman:BAECNQAFFIEIAAIfAAUJ5CGTAAAVAgWODQAAAgBfAHUNAAACAFgAfw0AAAEAOQCpDQAAAgBfADMNAAABAGEAHwAFCeQhkwAAFQIFjg0AAAIAXwB1DQAAAgBYAH8NAAABADkAqQ0AAAIAXwAzDQAAAQBhADUABAqBGgACHwAJCZ0lYAAA2gMAHwAJCZ0lYAAA2gMAAAA=.Seear:BAEANQAECgQIBAAAAA==.Seeargaming:BAEANQADCgEIAQABNQAECgQIBAABAAAAAA==.Seeartotems:BAEANQAECgIIAgABNQAECgQIBAABAAAAAA==.Sensian:BAEANQAECgcICAAAAA==.Serinos:BAEANQAECgcIDwAAAA==.',
Sh='Shamanapaks:BAEANQAECgIIAwAAAA==.Shiko:BAEANQADCggIFAABNQAECgcIDQABAAAAAA==.',
Sm='Smashshammy:BAEANQAECgcICwAAAA==.',
So='Solelock:BAEANQAECgUICAAAAA==.',
St='Stompers:BAEANQADCgYIBgABNQAECggIEgABAAAAAA==.',
Su='Sunnadin:BAEANQADCgMIAwABNQAFFAMIAwABAAAAAA==.Sunscaled:BAEANQAFFAMIAwAAAA==.',
Sw='Swaggybolt:BAEANQAECgcIEAAAAA==.',
Sy='Sym:BAEBNQAFFIENAAINAAYJEyNMAAB0AgaODQAAAwBYAHUNAAACAEcAfw0AAAIAXACpDQAAAwBjAF0NAAABAFYAMw0AAAIAZAANAAYJEyNMAAB0AgaODQAAAwBYAHUNAAACAEcAfw0AAAIAXACpDQAAAwBjAF0NAAABAFYAMw0AAAIAZAAAAA==.',
Ta='Talonflame:BAEANQAECgcIBAAAAA==.Tankurthunt:BAEBNQAECoEYAAIZAAkJJyWdAADaAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAYQBlDQAAAgBjAKQNAAACAEAAMw0AAAMAYwAZAAkJJyWdAADaAwmODQAAAwBjAHUNAAADAGMAfw0AAAMAYQCpDQAAAwBiAFwNAAADAGMAXQ0AAAIAYQBlDQAAAgBjAKQNAAACAEAAMw0AAAMAYwAAAA==.',
Te='Terrazic:BAEANQAECgQIBwABNQAECgcIDwABAAAAAA==.',
Th='Theemen:BAEANQAECgUIBQAAAA==.Thiaspala:BAEANQAECgMIAwABNQAFFAUIBwAdABweAA==.Thyruslock:BAEANQADCgcIBwABNQAECgkJGAAKAMUjAA==.',
To='Toseji:BAEANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Ur='Ursaluna:BAECNQAFFIELAAIbAAYJ/BYRAAAmAgaODQAAAgBgAHUNAAACAC8Afw0AAAIAJgCpDQAAAgBOAFwNAAABACcAMw0AAAIANAAbAAYJ/BYRAAAmAgaODQAAAgBgAHUNAAACAC8Afw0AAAIAJgCpDQAAAgBOAFwNAAABACcAMw0AAAIANAA1AAQKgRsAAhsACQmqJEcAANEDABsACQmqJEcAANEDAAAA.',
Ve='Velèus:BAEANQAECgQIBwAAAA==.',
Vo='Vollêy:BAEANQADCgYIBgAAAA==.',
Wa='Waurynn:BAEANQADCgYIBgAAAA==.',
Xa='Xaenne:BAEBNQAECoEZAAIKAAkJzyG2BgB+AwmODQAAAwBiAHUNAAADAF4Afw0AAAMAWwCpDQAAAwBTAFwNAAADAFsAXQ0AAAMAXwBlDQAAAwBYAKQNAAACAC0AMw0AAAIAWAAKAAkJzyG2BgB+AwmODQAAAwBiAHUNAAADAF4Afw0AAAMAWwCpDQAAAwBTAFwNAAADAFsAXQ0AAAMAXwBlDQAAAwBYAKQNAAACAC0AMw0AAAIAWAAAAA==.',
Xe='Xeab:BAEANQAECggIEAABNQAFFAYICwAdAOIZAA==.Xeav:BAECNQAFFIELAAIdAAYJ4hmDAAArAgaODQAAAgA5AHUNAAACAFcAfw0AAAIAWQCpDQAAAgBEAFwNAAABADgAMw0AAAIAJwAdAAYJ4hmDAAArAgaODQAAAgA5AHUNAAACAFcAfw0AAAIAWQCpDQAAAgBEAFwNAAABADgAMw0AAAIAJwA1AAQKgRsAAx0ACQnqHVMIAO4CAB0ACQnqHVMIAO4CABwABAn4DggKAPIAAAAA.',
Za='Zaljiri:BAEANQAECgYICQAAAA==.Zashi:BAEANQAECgYIDAAAAA==.Zaxholydrago:BAEBNQAECoEZAAMdAAkJHyKaAgBqAwmODQAAAwBcAHUNAAADAEYAfw0AAAMASwCpDQAAAwBhAFwNAAADAFkAXQ0AAAMAXABlDQAAAgBTAKQNAAACAFwAMw0AAAMAWwAdAAkJCSKaAgBqAwmODQAAAgBcAHUNAAACAEYAfw0AAAIASwCpDQAAAgBfAFwNAAACAFkAXQ0AAAIAXABlDQAAAgBTAKQNAAACAFwAMw0AAAIAWwAcAAcJLRefAwAFAgeODQAAAQBZAHUNAAABACMAfw0AAAEAJwCpDQAAAQBhAFwNAAABADEAXQ0AAAEATAAzDQAAAQAaAAAA.',
['Äm']='Ämy:BAEANQADCgUIBQABNQAECgUICQABAAAAAA==.',
['Ñÿ']='Ñÿü:BAECNQAFFIEFAAIXAAQJ3hFwAABvAQSODQAAAgA8AHUNAAABAD0Afw0AAAEAGQCpDQAAAQAkABcABAneEXAAAG8BBI4NAAACADwAdQ0AAAEAPQB/DQAAAQAZAKkNAAABACQANQAECoEYAAMXAAkJYSV4AADBAwAXAAkJYSV4AADBAwAWAAEJMwyvMQA5AAAAAA==.',
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
