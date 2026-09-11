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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Holy','DeathKnight-Frost','Druid-Restoration','Priest-Shadow','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Monk-Mistweaver','Evoker-Preservation','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Mage-Fire','Paladin-Protection',}
local provider = {region='US',realm='Sargeras',name='US',type='subscribers',zone=53,date='2026-09-08',data={Ad='Aderak:BAEANQAECgIIAwAAAA==.Adventures:BAEANQAECgcIDgAAAA==.Advntr:BAEANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Ai='Aiferian:BAEANQADCgEIAQABNQAECgkJFwACAJ8eAA==.',
Ak='Akand:BAEANQAFFAEIAQAAAA==.',
Al='Alarius:BAEBNQAECoEYAAIDAAkJGiTWAwCTAwmODQAAAwBfAHUNAAADAGAAfw0AAAMAYgCpDQAAAwBhAFwNAAADAF0AXQ0AAAMAVgBlDQAAAgBPAKQNAAABAFYAMw0AAAMAYQADAAkJGiTWAwCTAwmODQAAAwBfAHUNAAADAGAAfw0AAAMAYgCpDQAAAwBhAFwNAAADAF0AXQ0AAAMAVgBlDQAAAgBPAKQNAAABAFYAMw0AAAMAYQAAAA==.',
An='Antho:BAEANQAECgIIAgAAAA==.Anthodk:BAEANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Ar='Archimtiros:BAECNQAFFIEFAAIEAAQJTRfQAgB7AQR1DQAAAQAWAH8NAAABAD0AqQ0AAAIAUgAzDQAAAQBIAAQABAlNF9ACAHsBBHUNAAABABYAfw0AAAEAPQCpDQAAAgBSADMNAAABAEgANQAECoEXAAIEAAkJkiX1AgC7AwAEAAkJkiX1AgC7AwAAAA==.',
Au='Auratic:BAEANQAECgEIAQABNQAFFAUIBgAFAA4ZAA==.',
Aw='Awesumpawsum:BAEANQADCgcICwABNQAECgcIDwABAAAAAA==.',
Be='Beccastarr:BAEANQAECgcIDgAAAA==.Bestdead:BAEANQAECgQIBAABNQAFFAIIAgABAAAAAA==.',
Bi='Bidussybean:BAEBNQAECoEXAAIGAAgJdR5IBgCjAgiODQAAAwBbAHUNAAADAFMAfw0AAAMAXgCpDQAAAwBAAFwNAAADAFEAXQ0AAAMAQwBlDQAAAgA2ADMNAAADAFQABgAICXUeSAYAowIIjg0AAAMAWwB1DQAAAwBTAH8NAAADAF4AqQ0AAAMAQABcDQAAAwBRAF0NAAADAEMAZQ0AAAIANgAzDQAAAwBUAAAA.Bigmoos:BAEBNQAECoEYAAIHAAkJ7yGYAQBbAwmODQAAAwBcAHUNAAADAF0Afw0AAAMAUwCpDQAAAwBgAFwNAAADAF8AXQ0AAAMAXQBlDQAAAgBRAKQNAAABAFIAMw0AAAMAPwAHAAkJ7yGYAQBbAwmODQAAAwBcAHUNAAADAF0Afw0AAAMAUwCpDQAAAwBgAFwNAAADAF8AXQ0AAAMAXQBlDQAAAgBRAKQNAAABAFIAMw0AAAMAPwAAAA==.Bigpptotem:BAEANQAECgMIAwAAAA==.Bigsax:BAEANQAECgEIAQABNQAECgkJGAAHAO8hAA==.Biörnjr:BAEANQAECgcICgABNQAECgkJFgADAJMgAA==.',
Bj='Bjornsr:BAEBNQAECoEWAAIDAAkJkyAqBwBOAwmODQAAAwBSAHUNAAADAGIAfw0AAAMAXQCpDQAAAwBcAFwNAAACADwAXQ0AAAIATABlDQAAAgBaAKQNAAACAD4AMw0AAAIAXgADAAkJkyAqBwBOAwmODQAAAwBSAHUNAAADAGIAfw0AAAMAXQCpDQAAAwBcAFwNAAACADwAXQ0AAAIATABlDQAAAgBaAKQNAAACAD4AMw0AAAIAXgAAAA==.',
Bl='Blizidan:BAEANQADCggICQABNQAFFAIIAgABAAAAAA==.Blizinator:BAEANQAFFAIIAgAAAA==.',
Bo='Boidotatchi:BAEANQAECgEIAQABNQAFFAIIAgABAAAAAA==.Bokkiepi:BAECNQAFFIEMAAIIAAcJABcNAADAAgeODQAAAgBhAHUNAAACAFUAfw0AAAIAFwCpDQAAAgBaAFwNAAABAAUAXQ0AAAEAHgAzDQAAAgBQAAgABwkAFw0AAMACB44NAAACAGEAdQ0AAAIAVQB/DQAAAgAXAKkNAAACAFoAXA0AAAEABQBdDQAAAQAeADMNAAACAFAANQAECoEYAAMIAAkJHSTGAADMAwAIAAkJHSTGAADMAwAFAAEJchXgYQBMAAAAAA==.Bokkievoker:BAEANQAECgYIBgABNQAFFAcIDAAIAAAXAA==.Boldion:BAEANQAECgcICgABNQAFFAEIAQABAAAAAA==.',
Bu='Bubleohseven:BAEANQAECgQIBQAAAA==.',
Ca='Caraxxys:BAEBNQAECoEfAAIJAAgJZB0PHgDiAgiODQAABwBNAHUNAAAEAFoAfw0AAAQAYQCpDQAABwBYAFwNAAADAEkAXQ0AAAIASABlDQAAAQAkADMNAAADAEEACQAICWQdDx4A4gIIjg0AAAcATQB1DQAABABaAH8NAAAEAGEAqQ0AAAcAWABcDQAAAwBJAF0NAAACAEgAZQ0AAAEAJAAzDQAAAwBBAAAA.Castn:BAEANQAECgQIBgABNQAECggIBgABAAAAAA==.',
Ch='Chancelbrew:BAEANQAECgQIBgAAAA==.Chaotixbolt:BAEBNQAFFIEKAAMKAAYJGR7fAACJAQaODQAAAgBgAHUNAAACAF0Afw0AAAIARgCpDQAAAgBNAFwNAAABABsAMw0AAAEAYQAKAAQJexzfAACJAQSODQAAAgBgAH8NAAACAEYAXA0AAAEAGwAzDQAAAQBhAAsAAglVIbMBAMwAAnUNAAACAF0AqQ0AAAIATQABNQAECgYICAABAAAAAA==.Chaotixdh:BAEANQAECgYIDAABNQAECgYICAABAAAAAA==.Chyrus:BAEANQAECgUICQABNQAECgcIEQABAAAAAA==.',
Ci='Ciaoticks:BAEANQAECgYICAAAAA==.',
Co='Coleblast:BAEANQAECgMIAgAAAA==.',
Da='Dalailarma:BAEANQAECgMIAwAAAA==.Daraceae:BAEANQAECgcIDwAAAA==.',
De='Deaddari:BAEANQAECgcIDgAAAA==.Dedbrew:BAEANQADCgQIBQABNQAECgUICAABAAAAAA==.Deddh:BAEANQAECgIIAwABNQAECgUICAABAAAAAA==.Deddk:BAEANQAECgUICAAAAA==.Defected:BAEANQAECgcIEQAAAA==.Devroguemetz:BAEBNQAECoEZAAMMAAkJhiPyCgBaAgmODQAAAwBeAHUNAAADAGEAfw0AAAMAXwCpDQAAAwBfAFwNAAADAFQAXQ0AAAMAVwBlDQAAAgBYAKQNAAACAFgAMw0AAAMAVgAMAAYJkyPyCgBaAgaODQAAAwBeAHUNAAADAGEAfw0AAAMAXwBcDQAAAwBUAGUNAAABAFgAMw0AAAMAVgANAAQJEyH4EACMAQSpDQAAAwBfAF0NAAADAFcAZQ0AAAEAQgCkDQAAAgBYAAAA.',
Di='Disörder:BAEANQAECggIDAABNQAFFAEIAQABAAAAAA==.Divinebo:BAEANQADCggIDQABNQAECggIEwABAAAAAA==.Divinelightx:BAEANQADCggICAABNQAECggIEgABAAAAAA==.',
Dk='Dkpoc:BAEANQAECgcIDgAAAA==.',
Do='Dokanalha:BAEANQADCgUIBQABNQADCgcIBgABAAAAAA==.Doubledime:BAEANQAECgEIAQAAAA==.',
Dr='Drakdeez:BAEANQADCgIIAgABNQAECgIIAgABAAAAAA==.Drdwagon:BAEBNQAECoEZAAMOAAkJQSIJAQApAwmODQAAAwBhAHUNAAADAGEAfw0AAAMAYQCpDQAAAwBSAFwNAAADAGAAXQ0AAAMANwBlDQAAAgBbAKQNAAACAEgAMw0AAAMAYAAOAAgJ0yMJAQApAwiODQAAAgBhAHUNAAABAGEAfw0AAAEAYQCpDQAAAgBSAFwNAAABAGAAZQ0AAAIAWwCkDQAAAgBIADMNAAABAGAADwAHCYcU8A0AwAEHjg0AAAEAHAB1DQAAAgBPAH8NAAACADsAqQ0AAAEAAwBcDQAAAgBNAF0NAAADADcAMw0AAAIAPwAAAA==.Drinkzonme:BAEANQAECgQIBgABNQADCgcIBwABAAAAAA==.Dräka:BAEANQADCgYIDQAAAA==.',
['Dä']='Däddysips:BAEANQAECgMIBAABNQAECggIFwAGAHUeAA==.',
['Dì']='Dìsorder:BAEANQAFFAEIAQAAAA==.',
Ec='Ecobrew:BAEANQAECggICQABNQAECgkJFgAQANYQAA==.Ecospally:BAEANQADCgYIBgABNQAECggIDwABAAAAAA==.',
Ed='Edgelordxd:BAEANQADCgIIAgABNQADCgcIBwABAAAAAA==.',
Ei='Eightpuppies:BAEBNQAECoEZAAIJAAkJBiJ1CQByAwmODQAAAwBgAHUNAAADAGEAfw0AAAMAXACpDQAAAwBiAFwNAAADAF8AXQ0AAAMAVABlDQAAAgBcAKQNAAACAB8AMw0AAAMAXgAJAAkJBiJ1CQByAwmODQAAAwBgAHUNAAADAGEAfw0AAAMAXACpDQAAAwBiAFwNAAADAF8AXQ0AAAMAVABlDQAAAgBcAKQNAAACAB8AMw0AAAMAXgAAAA==.',
El='Eldan:BAEANQAECgcIEAAAAA==.Eldist:BAEANQAECgYICAABNQAECgcIEAABAAAAAA==.',
Em='Embulance:BAEANQAECgIIAgABNQAECgUICwABAAAAAA==.Emchii:BAEANQADCggICAABNQAECgUICwABAAAAAA==.Emluminate:BAEANQAECgUICwAAAA==.',
Ev='Evokur:BAEANQAECgMIBAAAAA==.',
Ex='Executiexd:BAEANQADCgYICQABNQADCgcIBwABAAAAAA==.',
Ey='Eyrae:BAEANQAECgEIAQABNQAECgYIDQABAAAAAA==.',
Fa='Fatdari:BAEANQAECgEIAQABNQAECgcIDgABAAAAAA==.Fatescurse:BAEANQAECgQICQAAAA==.',
Fl='Fláminis:BAEANQAFFAIIAgAAAA==.',
Fo='Fofer:BAEANQAECgcIBwABNQAECgkJGQARAFolAA==.',
Fu='Furymike:BAEANQAECgYICgAAAA==.',
Fy='Fystpriest:BAEANQAECgEIAgAAAA==.',
Ga='Gahdania:BAEANQADCgYICgAAAA==.',
Ge='Genshii:BAEBNQAECoEYAAISAAkJ6CALAQBZAwmODQAAAwBfAHUNAAADAFcAfw0AAAMAVQCpDQAAAwBfAFwNAAADAEoAXQ0AAAMAQQBlDQAAAgBWAKQNAAACAFUAMw0AAAIAUwASAAkJ6CALAQBZAwmODQAAAwBfAHUNAAADAFcAfw0AAAMAVQCpDQAAAwBfAFwNAAADAEoAXQ0AAAMAQQBlDQAAAgBWAKQNAAACAFUAMw0AAAIAUwABNQAECgkJGAASAOggAA==.',
Gi='Ginjao:BAEANQADCgcIBwABNQAECgkJHAATAGskAA==.Ginjaoo:BAEBNQAECoEcAAITAAkJayTAAACWAwmODQAABABbAHUNAAADAFwAfw0AAAMARgCpDQAAAwBcAFwNAAADAGEAXQ0AAAMAYQBlDQAABABjAKQNAAACAGQAMw0AAAMAYQATAAkJayTAAACWAwmODQAABABbAHUNAAADAFwAfw0AAAMARgCpDQAAAwBcAFwNAAADAGEAXQ0AAAMAYQBlDQAABABjAKQNAAACAGQAMw0AAAMAYQAAAA==.',
Gr='Greatllama:BAEANQAECgcIDgAAAA==.Groovii:BAEBNQAFFIEIAAIUAAcJOCIHAADrAgeODQAAAQBVAHUNAAABAGIAfw0AAAEAWwCpDQAAAQBSAFwNAAABADsAXQ0AAAEAZAAzDQAAAgBfABQABwk4IgcAAOsCB44NAAABAFUAdQ0AAAEAYgB/DQAAAQBbAKkNAAABAFIAXA0AAAEAOwBdDQAAAQBkADMNAAACAF8AAAA=.',
Gu='Gunimal:BAEANQADCgQIBAABNQAECggIEAABAAAAAA==.Gunrunner:BAEANQAECggIEAAAAA==.',
['Gä']='Gättsu:BAEANQABCgIIAgAAAA==.',
Ha='Hazëy:BAEANQAECgMIBQABNQAECggIIAAVAPQlAA==.',
He='Henzillxlock:BAEANQAECggIEAAAAA==.',
Ho='Holysele:BAEANQAECgcIEQABNQAECgkJGAAVAI4kAA==.',
Hy='Hydrohunter:BAEANQADCgEIAQABNQAECgcICwABAAAAAA==.Hydrosplash:BAEANQAECgcICwAAAA==.',
['Hâ']='Hâzêy:BAEANQAECgEIAQABNQAECggIIAAVAPQlAA==.',
['Hä']='Häzey:BAEBNQAECoEgAAIVAAgJ9CUjBABWAwiODQAABABiAHUNAAAFAGIAfw0AAAUAYACpDQAABABiAFwNAAADAGIAXQ0AAAUAXwBlDQAAAQBcADMNAAAFAGMAFQAICfQlIwQAVgMIjg0AAAQAYgB1DQAABQBiAH8NAAAFAGAAqQ0AAAQAYgBcDQAAAwBiAF0NAAAFAF8AZQ0AAAEAXAAzDQAABQBjAAAA.',
Ib='Ibdapopo:BAEANQAFFAEIAQAAAA==.',
Im='Imsíght:BAEANQADCggICAAAAA==.',
Jo='Johncxvii:BAEANQAECggIEgAAAA==.Johnnymonk:BAEANQADCgcIBwAAAA==.',
Ka='Kajse:BAEANQAFFAMIBAAAAQ==.',
Ke='Keveighnne:BAEANQAECgMIAwAAAA==.Keylana:BAEANQAECgYIDQAAAA==.',
Ku='Kuweeph:BAEANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
La='Lardorable:BAEANQADCgIIAgABNQAECgMIAwABAAAAAA==.Larkiron:BAEANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Le='Lets:BAEANQADCggICAABNQAECggIEAABAAAAAA==.',
Li='Lilzappy:BAEANQAECgMIAwABNQAECgkJFwAWAAoeAA==.',
Ll='Llamwar:BAEANQAECgMIAwABNQAECgcIDgABAAAAAA==.',
Lo='Lookaway:BAEANQADCgQIBAAAAA==.',
Ma='Machfive:BAEANQAECggIDgAAAA==.Malthor:BAEANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Maredithe:BAEANQAECgcIEAAAAA==.Maritt:BAECNQAFFIEGAAIFAAUJDhkMAQDgAQWODQAAAgBbAHUNAAABACwAfw0AAAEATQCpDQAAAQAgADMNAAABAEoABQAFCQ4ZDAEA4AEFjg0AAAIAWwB1DQAAAQAsAH8NAAABAE0AqQ0AAAEAIAAzDQAAAQBKADUABAqBGgADBQAJCckj9AEAgAMABQAJCckj9AEAgAMAFwAECRsP9woA1AAAAAA=.',
Mc='Mchimba:BAEANQAECggIBwAAAA==.',
Me='Meatrub:BAEANQAECgEIAQABNQAECgkJFQAOAIEgAA==.Mec:BAEANQAECggIDwAAAA==.',
Mo='Molecyl:BAEANQADCggICAABNQAECgcIEQABAAAAAA==.Mowre:BAEANQAECgcIDgAAAA==.Mowridan:BAEANQADCgcIBwABNQAECgcIDgABAAAAAA==.',
Mu='Murderbêard:BAEANQAECgYICQAAAA==.Murtag:BAECNQAFFIEMAAIEAAcJ/xkvAADNAgeODQAAAgBVAHUNAAACAD4Afw0AAAIAWQCpDQAAAgBgAFwNAAABABQAXQ0AAAEADgAzDQAAAgBgAAQABwn/GS8AAM0CB44NAAACAFUAdQ0AAAIAPgB/DQAAAgBZAKkNAAACAGAAXA0AAAEAFABdDQAAAQAOADMNAAACAGAANQAECoEYAAIEAAkJ+CUdAQDlAwAEAAkJ+CUdAQDlAwAAAA==.Murtmonk:BAEANQABCgQIBQABNQAFFAcIDAAEAP8ZAA==.Murtwarr:BAEBNQAECoEXAAIEAAkJqSIdCgBTAwmODQAAAwBfAHUNAAADAFUAfw0AAAMAWQCpDQAAAwBjAFwNAAADAFIAXQ0AAAMAXQBlDQAAAgBSAKQNAAABAEsAMw0AAAIAXgAEAAkJqSIdCgBTAwmODQAAAwBfAHUNAAADAFUAfw0AAAMAWQCpDQAAAwBjAFwNAAADAFIAXQ0AAAMAXQBlDQAAAgBSAKQNAAABAEsAMw0AAAIAXgABNQAFFAcIDAAEAP8ZAA==.',
My='Mycropht:BAEANQAECgQIBQAAAA==.',
['Mä']='Mäxemas:BAEBNQAECoEaAAQIAAkJySJ5AwBiAwmODQAAAwBeAHUNAAADAGMAfw0AAAMAYQCpDQAAAwBjAFwNAAADAGIAXQ0AAAMAYQBlDQAAAwBaAKQNAAACABgAMw0AAAMAYwAIAAgJ6yV5AwBiAwiODQAAAwBeAHUNAAADAGMAfw0AAAIAYQCpDQAAAwBjAFwNAAACAGIAXQ0AAAIAYQBlDQAAAwBaADMNAAACAGMAFwAECbwZRggAKgEEfw0AAAEASABcDQAAAQA4AF0NAAABAEoAMw0AAAEAOwAFAAEJ9iN/XABoAAGkDQAAAgBcAAAA.',
['Må']='Måxemäs:BAEANQADCggIEAABNQAECgkJGgAIAMkiAA==.',
Na='Nateg:BAEANQADCgMIAwABNQAFFAEIAgABAAAAAA==.Nattygee:BAEANQAFFAEIAgAAAA==.',
No='Notoriousrip:BAEANQAECgMIAwABNQAFFAIIBAABAAAAAA==.Nozdd:BAEANQAFFAIIAgAAAA==.Nozfarkia:BAEANQAECgUIBgAAAA==.',
Ot='Otwind:BAEANQAECgcIDQABNQAFFAEIAQABAAAAAA==.',
Pl='Ploog:BAEANQAECgYIBgAAAA==.Ploogyw:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.',
Pr='Prec:BAEANQAECgYICwAAAA==.',
Pu='Punanilani:BAEANQAFFAEIAQABNQAECgMIAwABAAAAAA==.',
Ra='Raerlynn:BAEANQADCgcIEwAAAA==.Ragebo:BAEANQAECggIEwAAAA==.',
Re='Remilia:BAEANQAECgIIAwAAAA==.',
Ri='Ribroast:BAEANQADCggIEAABNQAECgkJFQAOAIEgAA==.',
Ro='Rolykins:BAEANQAECgYICAABNQAECgkJGQADACElAA==.Rolym:BAEANQADCgYIBgABNQAECgkJGQADACElAA==.Roubow:BAEANQADCggICAABNQAECgQIBgABAAAAAA==.Roullaeu:BAEANQAECgQIBgAAAA==.Rozeybear:BAEBNQAECoEXAAIYAAkJvRd8DwDAAgmODQAAAwBQAHUNAAADAFIAfw0AAAMAQgCpDQAAAwA4AFwNAAADADQAXQ0AAAIAIQBlDQAAAgBBAKQNAAABABEAMw0AAAMAWwAYAAkJvRd8DwDAAgmODQAAAwBQAHUNAAADAFIAfw0AAAMAQgCpDQAAAwA4AFwNAAADADQAXQ0AAAIAIQBlDQAAAgBBAKQNAAABABEAMw0AAAMAWwAAAA==.',
Ru='Ruossaeu:BAEANQAECgMIBAABNQAECgQIBgABAAAAAA==.Ruxs:BAEANQADCggIDgAAAA==.',
Sa='Sagoriken:BAEBNQAECoEXAAICAAkJnx7fBQAuAwmODQAAAwBWAHUNAAADAFcAfw0AAAMAUwCpDQAAAwBcAFwNAAADAE0AXQ0AAAIAUwBlDQAAAgBHAKQNAAABADMAMw0AAAMARgACAAkJnx7fBQAuAwmODQAAAwBWAHUNAAADAFcAfw0AAAMAUwCpDQAAAwBcAFwNAAADAE0AXQ0AAAIAUwBlDQAAAgBHAKQNAAABADMAMw0AAAMARgAAAA==.Saphacan:BAEANQADCgUIBQABNQAECgIIAgABAAAAAA==.Saphigon:BAEANQAECgIIAgAAAA==.',
Sc='Schooty:BAEANQAFFAEIAQAAAA==.',
Se='Selenium:BAEANQAECgIIAwAAAA==.',
Sh='Shotslawl:BAEBNQAECoEXAAMWAAkJCh74BQAdAwmODQAAAwBQAHUNAAADAFEAfw0AAAMAYQCpDQAAAwBWAFwNAAADAFoAXQ0AAAIAWgBlDQAAAgAlAKQNAAABACoAMw0AAAMAVQAWAAkJCh74BQAdAwmODQAAAgBQAHUNAAACAFEAfw0AAAIAYQCpDQAAAwBWAFwNAAACAFoAXQ0AAAIAWgBlDQAAAgAlAKQNAAABACoAMw0AAAMAVQAVAAQJgRfOXQARAQSODQAAAQAIAHUNAAABAE8Afw0AAAEARQBcDQAAAQBTAAAA.Shämydavisjr:BAEANQAECgEIAgABNQAECgQIBQABAAAAAA==.',
Sl='Slammystabby:BAEANQAECgcIDgABNQAECgcIDQABAAAAAA==.Slammywhammy:BAEANQAECgcIDQAAAA==.',
Sm='Smackthelip:BAEBNQAECoEVAAQOAAkJgSCFAgBNAgmODQAAAwBbAHUNAAADAGEAfw0AAAMAYgCpDQAAAgBPAFwNAAADAGIAXQ0AAAMAWQBlDQAAAgBOAKQNAAABAEEAMw0AAAEAMgAOAAYJYSKFAgBNAgZ1DQAAAgBhAH8NAAABAGIAXA0AAAEAYgBdDQAAAQBZAGUNAAABAE4ApA0AAAEAQQAPAAcJXh3rCABHAgeODQAAAgBbAHUNAAABADsAfw0AAAIATgCpDQAAAgBPAFwNAAACAE0AXQ0AAAIATgBlDQAAAQA9ABQAAgneDjsjAHAAAo4NAAABAAgAMw0AAAEAQwAAAA==.Smashn:BAEANQAECggIBgAAAA==.',
Sn='Snuggless:BAEANQAFFAIIBAAAAA==.',
So='Solex:BAEANQAECgcIDwAAAA==.',
Ss='Ssoth:BAEANQAECgYIDQAAAA==.',
Sw='Switching:BAEANQAECggIDwAAAA==.',
Ta='Tanczak:BAEANQAECgYICwAAAA==.',
Th='Theokar:BAEANQAECgUIBwABNQAECgcIDwABAAAAAA==.Theomag:BAEANQAECgcIDwAAAA==.Theorior:BAEANQADCgYICgABNQAECgcIDwABAAAAAA==.Thiaslock:BAEANQAECgQIBAABNQAFFAUIBwAFABweAA==.Thiasmonk:BAEANQAECgEIAQABNQAFFAUIBwAFABweAA==.Thiaspriest:BAECNQAFFIEHAAMFAAUJHB4HAQDiAQWODQAAAgA3AHUNAAABAE8Afw0AAAEATACpDQAAAgBVADMNAAABAFgABQAFCRweBwEA4gEFjg0AAAEANwB1DQAAAQBPAH8NAAABAEwAqQ0AAAIAVQAzDQAAAQBYABcAAQkWDT8BAFAAAY4NAAABACEANQAECoEaAAIFAAkJriVOAADcAwAFAAkJriVOAADcAwAAAA==.',
Tr='Traumadh:BAEANQADCggICQAAAA==.Traumaxd:BAEANQADCgYIBgABNQADCggICQABAAAAAA==.',
Un='Unclightx:BAEANQAECggIEgAAAA==.',
Us='Usonja:BAEANQAECgQIBAABNQAECgkJHAATAGskAA==.',
Wa='Waffietv:BAEANQAECgYIBAABNQAECggIBwABAAAAAA==.Warminis:BAEANQAECgIIAwABNQAFFAIIAgABAAAAAA==.',
Wi='Wildery:BAEANQAFFAIIAgAAAA==.Wildthyr:BAEANQAECgYIBgABNQAFFAIIAgABAAAAAA==.',
Wo='Wolfsmage:BAEBNQAECoEUAAMJAAkJKh3VFwAJAwmODQAAAgBXAHUNAAADAFAAfw0AAAMAVwCpDQAAAwBUAFwNAAACAGIAXQ0AAAIAVABlDQAAAgAeAKQNAAABACgAMw0AAAIATQAJAAkJKh3VFwAJAwmODQAAAgBXAHUNAAACAFAAfw0AAAMAVwCpDQAAAwBUAFwNAAACAGIAXQ0AAAIAVABlDQAAAgAeAKQNAAABACgAMw0AAAIATQAZAAEJhA2WBABKAAF1DQAAAQAiAAAA.Wolfspriest:BAEANQAECgEIAQABNQAECgkJFAAJACodAA==.Worldboss:BAEANQAECggIEAAAAA==.',
Xh='Xhurnyra:BAEANQAECgYIDgAAAA==.',
Xy='Xydeco:BAEANQAECgYIEAAAAA==.',
Ya='Yakoß:BAEANQAECgcIDgAAAA==.',
Za='Zandikar:BAEANQADCgQIBAABNQAECgcIDwABAAAAAA==.',
Zh='Zhaobo:BAEANQAECgMIAwABNQAECgkJGQAaAH0lAA==.',
Zu='Zuzusu:BAEANQADCggIDgABNQADCggIDgABAAAAAA==.',
['Ða']='Ðaybreak:BAEANQAECggIDgAAAA==.Ðaywraith:BAEANQAECggIDQABNQAECggIDgABAAAAAA==.',
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
