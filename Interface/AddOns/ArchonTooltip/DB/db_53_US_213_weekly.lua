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

local lookup = {'Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Rogue-Assassination','DemonHunter-Devourer','Paladin-Holy','Evoker-Preservation','Warrior-Arms','Unknown-Unknown','Mage-Arcane','Druid-Balance','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Shaman-Restoration','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Marksmanship','Priest-Shadow','Rogue-Outlaw',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarg:BAAANQAECggICAAAAA==.',
Ac='Achillguy:BAAANQADCgUIBQAAAA==.',
Ag='Agnostic:BAABNQAECoEZAAIBAAkJzhyoBwAVAwABAAkJzhyoBwAVAwAAAA==.Agonybehold:BAAANQADCgUICgAAAA==.',
Ai='Aisa:BAACNQAFFIEIAAQCAAUJ2xt2AQDVAAACAAIJASJ2AQDVAAADAAIJdBm5BAC8AAAEAAEJWhTaAQBaAAA1AAQKgRsABAIACQlJJAUHAGECAAIABgkoIwUHAGECAAMABglYIvwXAD0CAAQAAQldJPsNAGwAAAAA.Aish:BAABNQAFFIEJAAIFAAUJZhKMAACxAQAFAAUJZhKMAACxAQAAAA==.Aiso:BAAANQABCgYICgAAAA==.',
Ak='Akali:BAABNQAECoEUAAIGAAgJZCY8AQB7AwAGAAgJZCY8AQB7AwAAAA==.',
Al='Aldofio:BAAANQAECgMIAwAAAA==.Alhttabe:BAAANQAECgIIAgAAAA==.Alvln:BAABNQAECoEXAAIHAAkJbxzBBQAyAwAHAAkJbxzBBQAyAwAAAA==.',
An='Andyrios:BAAANQADCgYICwAAAA==.',
Ap='Apoplectic:BAAANQAECgEIAQAAAA==.',
Ar='Aradinya:BAAANQADCggICAAAAA==.Arahat:BAAANQAECgEIAQAAAA==.Aralinya:BAAANQAECggIEwAAAA==.Aratus:BAAANQADCggIDwAAAA==.Ardentflame:BAAANQAECgIIAwAAAA==.Arsoul:BAAANQADCgIIAgAAAA==.',
As='Asperonia:BAACNQAFFIEIAAIIAAUJmwfGAQCUAQAIAAUJmwfGAQCUAQA1AAQKgRsAAggACQloGeAJAO8CAAgACQloGeAJAO8CAAAA.Astinous:BAAANQADCggICAAAAA==.Astlyr:BAAANQADCgIIAgAAAA==.Astrid:BAABNQAECoEZAAIJAAkJSSHTAQBjAwAJAAkJSSHTAQBjAwAAAA==.',
At='Athera:BAAANQADCgYIBgAAAA==.Atiermonk:BAAANQAECgEIAQAAAA==.',
Au='Auroral:BAAANQAFFAIIAgAAAA==.Ausdemonic:BAAANQAECgEIAQAAAA==.',
Av='Avell:BAAANQAECgYICwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azriox:BAAANQADCgUIBQAAAA==.Azsharia:BAAANQADCgYIBgAAAA==.Azzielliea:BAAANQAECgUICwAAAA==.',
Ba='Barleybrew:BAAANQADCgIIAgAAAA==.Battletank:BAAANQAECgMIAwABNQAECgkJFwAHAG8cAA==.',
Be='Beefchar:BAAANQAECgEIAQAAAA==.Beefquake:BAAANQAECgYIDgAAAA==.Betray:BAAANQAECgIIAgAAAA==.Beàr:BAAANQADCgYIDAAAAA==.',
Bi='Bigbadbaka:BAACNQAFFIEIAAIKAAUJ9xe0AQDTAQAKAAUJ9xe0AQDTAQA1AAQKgRsAAgoACQnHJPECALsDAAoACQnHJPECALsDAAAA.Bigdecay:BAAANQAECgUICwAAAA==.',
Bl='Blasez:BAAANQADCggIDgAAAA==.Blazez:BAAANQAECggIEwAAAA==.Blazpew:BAAANQADCggICAAAAA==.Blood:BAEANQADCggIFAAAAA==.',
Bo='Bogart:BAAANQAECggIEwAAAA==.Bomohomo:BAAANQAECggIEgAAAA==.Boogeymayne:BAAANQADCgIIAgAAAA==.Bootycallz:BAAANQAECgEIAQAAAA==.',
Br='Brainlag:BAAANQAECgIIAgAAAA==.Brawny:BAAANQAECgEIAQAAAA==.Brevrin:BAAANQAECgYICAAAAA==.',
Bu='Bubbix:BAAANQADCggIEAAAAA==.Buddhatime:BAAANQADCgYIBgABNQAECggICwALAAAAAA==.Bui:BAAANQAFFAQIBAAAAA==.Buikia:BAAANQAFFAIIAgABNQAFFAQIBAALAAAAAA==.Bunnyhop:BAAANQAECgIIAgAAAA==.Buysfeetpics:BAABNQAECoEaAAIMAAkJhSAEDABcAwAMAAkJhSAEDABcAwAAAA==.',
['Bâ']='Bânê:BAAANQAECgYICwAAAA==.',
Ca='Calx:BAAANQAECgIIAgABNQAECgkJFwAJAMYVAA==.Cannicus:BAABNQAECoEbAAIMAAkJuiPjBgCMAwAMAAkJuiPjBgCMAwAAAA==.Cantheal:BAAANQADCgQICQAAAA==.Cardinal:BAAANQAECgYICAABNQAECggICwALAAAAAA==.',
Ce='Celavii:BAAANQAECgYICgAAAA==.Celeena:BAAANQADCggIFgAAAA==.',
Ch='Chamane:BAAANQAECgIIAwAAAA==.Chanengtotem:BAAANQADCgYIAgAAAA==.Chappell:BAAANQAECgEIAQAAAA==.Chii:BAAANQADCgEIAQAAAA==.Chillicheese:BAAANQADCgUIBwAAAA==.Chinnomojo:BAAANQAECgQICAAAAA==.',
Ci='Cindermoon:BAAANQADCgQIBQAAAA==.',
Cl='Cloudhorn:BAAANQAECgEIAgAAAA==.',
Co='Colena:BAEANQAECgYIDAAAAA==.Conquest:BAAANQADCggICAAAAA==.Conzy:BAAANQAECgMIAwAAAA==.Coopsfire:BAAANQADCgQIBQAAAA==.Corbulus:BAAANQAECgQICAAAAA==.',
Cr='Create:BAAANQADCgcIBwABNQADCggIDQALAAAAAA==.Crispyarrowz:BAAANQAECgEIAQABNQAECgYIDQALAAAAAA==.Crispymage:BAAANQAECgYIDQAAAA==.',
Ct='Ctierwarlock:BAAANQAECgQIBAABNQAFFAUICAANAFoiAA==.',
Cy='Cyndi:BAAANQAECgIIAgAAAA==.Cynxs:BAAANQAECgIIAwABNQAECgcIDgALAAAAAA==.',
Da='Dannoh:BAAANQAECgEIAQAAAA==.Darcious:BAAANQAECgIIAgABNQAECgYICgALAAAAAA==.Darkcinders:BAAANQAECgYICgAAAA==.',
De='Deadjkcocoon:BAAANQADCgMIBAAAAA==.Deadlly:BAAANQAECgQIBQAAAA==.Deathbybelf:BAAANQADCggICAAAAA==.Deathrocks:BAAANQAECgcIEAAAAA==.Demöníc:BAAANQAECgcIDwAAAA==.Deplock:BAAANQAECgUIBgAAAA==.Destcrypt:BAAANQADCggICAABNQAECgYIDgALAAAAAA==.Destinyisall:BAAANQADCgYIBgAAAA==.Destria:BAAANQADCgQICAAAAA==.Destwind:BAAANQAECgYIDgAAAA==.',
Di='Dilo:BAAANQADCggIBwAAAA==.Disbelief:BAAANQADCgEIAQAAAA==.Divinfinity:BAAANQAECgQIBQAAAA==.',
Do='Dotdotseckz:BAAANQAECgYIDAAAAA==.',
Dr='Dracdoy:BAAANQAECgQIBAABNQAECgQICAALAAAAAA==.Drethalis:BAAANQADCgQIEAAAAA==.Drewstormio:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.Dryene:BAAANQAECgIIAgAAAA==.',
Ds='Dsdh:BAABNQAFFIEHAAIHAAUJyRMBAQDMAQAHAAUJyRMBAQDMAQAAAA==.',
Du='Dulang:BAAANQAECgcIDQAAAA==.',
Ec='Ectruby:BAAANQAECgcIEgAAAA==.',
El='Elammental:BAAANQADCgYIBgAAAA==.Elertricsoup:BAAANQAECgIIAgAAAA==.Elwarlocko:BAAANQAECgQIBQAAAA==.Elyndre:BAABNQAECoEaAAQOAAkJtBocBAACAwAOAAkJOhgcBAACAwAJAAMJgB0BGgADAQAPAAEJXSBPDABdAAAAAA==.',
Em='Emberis:BAAANQADCgUIBQAAAA==.',
En='Endari:BAAANQAECgUIBQAAAA==.Endlockz:BAAANQAECgUICQAAAA==.',
Er='Erikk:BAACNQAFFIEIAAIHAAUJrw4iAQC1AQAHAAUJrw4iAQC1AQA1AAQKgRsAAgcACQmHIHUDAG0DAAcACQmHIHUDAG0DAAAA.',
Es='Escher:BAAANQADCgMIBgAAAA==.Esprit:BAAANQAECgQIBgABNQAFFAQIBgAMAOwQAA==.',
Fa='Faeia:BAABNQAECoEdAAIQAAcJtxjEDgDXAQAQAAcJtxjEDgDXAQABNQAECgkJFwARAC8kAA==.Faenirel:BAAANQAECgQIBgABNQAECgQICQALAAAAAA==.Faeya:BAABNQAECoEXAAIRAAkJLyTbAAC+AwARAAkJLyTbAAC+AwAAAA==.Fairyen:BAAANQAECgUICQAAAA==.Faithful:BAAANQAECgMIAwAAAA==.Famine:BAAANQADCgUIBQABNQAECgUIBgALAAAAAA==.Farapanda:BAAANQADCgYICQAAAA==.Fastcharge:BAAANQAECgIIAgABNQAECgkJFwAHAG8cAA==.',
Fe='Feidutdut:BAAANQAECgYICAAAAA==.Feldown:BAAANQAFFAEIAQAAAA==.',
Ff='Ffen:BAAANQAECgYIBgAAAA==.',
Fi='Fibanocci:BAAANQAECgYIEAAAAA==.Fierce:BAAANQAECgcIDwAAAA==.Fixated:BAAANQAECgQICwAAAA==.',
Fr='Frankadelic:BAAANQAECgMIAwAAAA==.Frodolol:BAACNQAFFIEGAAIMAAUJlhKbAgC+AQAMAAUJlhKbAgC+AQA1AAQKgRkAAgwACQmMIqsIAHoDAAwACQmMIqsIAHoDAAAA.Frostik:BAAANQAECgEIAQAAAA==.Frostyfruit:BAAANQAECgQIBQAAAA==.',
Fu='Fufamace:BAAANQADCgIIAwAAAA==.Fufina:BAAANQADCgcIDwAAAA==.',
Fw='Fwoopie:BAAANQAECgYICAAAAA==.Fwooplin:BAAANQAECgEIAQABNQAECgYICAALAAAAAA==.',
Ga='Gannina:BAAANQAECgYICwAAAA==.Garage:BAAANQADCgEIAQAAAA==.',
Gi='Gillemon:BAAANQADCgQIBQAAAA==.Givre:BAAANQADCgIIAgAAAA==.Gizzy:BAAANQAECgQIBAAAAA==.',
Go='Goodra:BAAANQADCgYIBgABNQAECgkJFwAHAG8cAA==.Goodwill:BAAANQAECgcIBwABNQAFFAEIAQALAAAAAA==.',
Gr='Greybeards:BAAANQADCgcICQAAAA==.Gritt:BAAANQADCgcIDQAAAA==.Gryffin:BAAANQAECgQIBQAAAA==.',
Gu='Gugudan:BAAANQAECgMIBgAAAA==.Gunnina:BAAANQADCggICgAAAA==.Gutsc:BAAANQAECgcIDgAAAA==.Guyhulikatit:BAAANQADCggICAABNQAECgkJGwAGAHMgAA==.Guzzan:BAAANQAECgEIAQAAAA==.',
Ha='Hatewatching:BAAANQAECgcIDQAAAA==.',
He='Healbòt:BAAANQAECgIIAgAAAA==.Hemorrhage:BAAANQAFFAEIAgAAAA==.Hermighty:BAAANQAECgUIBQAAAA==.Hershéy:BAAANQAECgQIBQAAAA==.Hert:BAAANQADCgcIBwAAAA==.',
Hi='Hiradaira:BAAANQAECgIIAgAAAA==.',
Ho='Holasimón:BAAANQAECgMIBgAAAA==.Hothotseckz:BAAANQADCggIDgABNQAECgYIDAALAAAAAA==.',
Hu='Hukk:BAAANQAECgYICQAAAA==.',
Hy='Hypervoltage:BAAANQADCgMIAwAAAA==.Hypnos:BAAANQADCgcIEwAAAA==.',
['Hà']='Hà:BAAANQAECgMIBQAAAA==.',
Ia='Iamundecided:BAAANQADCggIDQAAAA==.Iamzzr:BAAANQAECgEIAQAAAA==.',
Ic='Icysun:BAAANQAECgIIAwAAAA==.',
Ig='Igneous:BAAANQADCgcIDQAAAA==.',
Im='Image:BAAANQADCgcIBwABNQADCggIDQALAAAAAA==.Imnotamage:BAAANQADCgMIBgAAAA==.',
Is='Ish:BAAANQAECggIBgAAAA==.Isopod:BAAANQADCgIIAgAAAA==.',
Ja='Jabbah:BAAANQAECgIIBAAAAA==.Jackee:BAAANQAECgMIBQABNQAECgUIBgALAAAAAA==.Jasmean:BAAANQAECggIEwAAAA==.',
Je='Jellybeanss:BAAANQAECgUIBwAAAA==.Jereu:BAAANQADCgYIBwAAAA==.',
Jo='Jodix:BAAANQADCgIIAgAAAA==.Johnevoker:BAAANQAECgYIBAABNQAECggIDwALAAAAAA==.Johnpaladin:BAAANQAECgQIBAABNQAECggIDwALAAAAAA==.Jombii:BAAANQAECgIIAwABNQAECgcIEgALAAAAAA==.Jordoom:BAAANQAECgEIAQAAAA==.',
Ju='Judicas:BAAANQADCgcICAAAAA==.',
Ka='Kafra:BAAANQADCgYIBgABNQAECgQIBQALAAAAAA==.Kamazi:BAABNQAECoEPAAIPAAgJ6RdKAgBoAgAPAAgJ6RdKAgBoAgAAAA==.Kannina:BAAANQAECgEIAQAAAA==.Kariiyon:BAAANQAECgIIAgAAAA==.Katalen:BAAANQADCgQIBQAAAA==.Kayapau:BAAANQAECgcIDAAAAA==.',
Ke='Kevd:BAAANQAECgYICgABNQAFFAUICwARAOwfAA==.Kevin:BAACNQAFFIELAAIRAAUJ7B+eAAAJAgARAAUJ7B+eAAAJAgA1AAQKgRkAAhEACQkcJaEAAMwDABEACQkcJaEAAMwDAAAA.Kevp:BAAANQAECgYIBgABNQAFFAUICwARAOwfAA==.',
Kh='Khaii:BAAANQAECggIEwAAAA==.',
Ki='Kidevil:BAAANQADCgYICwAAAA==.Kimmiereed:BAAANQAECgYIEgABNQAECggIFgAEAEUUAA==.',
Ko='Komai:BAAANQAECgYIDAAAAA==.Kopikia:BAAANQAECgUIBwAAAA==.',
Kr='Krucify:BAAANQADCggIGAAAAA==.',
Kt='Ktl:BAAANQADCgcIBwABNQAECgYICwALAAAAAA==.Ktx:BAAANQAECgYICwAAAA==.',
Ku='Kulak:BAAANQADCgUIBwAAAA==.',
Ky='Kyall:BAAANQAECgYICgAAAA==.',
La='Ladiesman:BAAANQAECggIBgAAAA==.Lafret:BAAANQADCggICAAAAA==.Lamerzz:BAAANQADCgYIDwAAAA==.',
Le='Lebronyames:BAAANQAECgEIAQAAAA==.Lelith:BAAANQAECgYICgAAAA==.Lerazar:BAAANQAECgEIAQAAAA==.Lettuce:BAAANQAECgIIAwAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Liquidvoid:BAAANQAECgYICQAAAA==.Littleannie:BAAANQADCgQIBAAAAA==.',
Lu='Luurch:BAABNQAECoEXAAMSAAkJWSMMAgBnAwASAAgJjiQMAgBnAwAGAAEJtBkAAAAAAAAAAA==.',
Ly='Lynnae:BAAANQADCgUIBgABNQADCgUIBwALAAAAAA==.Lythillen:BAAANQADCgMIAwAAAA==.Lythium:BAAANQADCgMIAwAAAA==.',
['Lî']='Lîght:BAAANQAECgQIBAABNQAECgUIBgALAAAAAA==.',
Ma='Maceson:BAAANQADCggIDAAAAA==.Magikcreepz:BAAANQAECggIBAAAAA==.Magnamund:BAAANQABCgYIBwAAAA==.Marvik:BAAANQADCgIIAgAAAA==.Masquerapet:BAACNQAFFIEIAAITAAUJjBPxAQB2AQATAAUJjBPxAQB2AQA1AAQKgRsAAhMACQnBGNUKAMsCABMACQnBGNUKAMsCAAAA.',
Me='Megadeath:BAAANQAECggIDgAAAA==.Mentalas:BAAANQAECgQIBQAAAA==.Mepuzzible:BAAANQAECgUIBQAAAA==.Meulah:BAAANQAECgQIBQAAAA==.',
Mi='Miah:BAAANQAECggICwAAAA==.Miao:BAABNQAECoEXAAIRAAkJ0SKZAgB7AwARAAkJ0SKZAgB7AwABNQAFFAUICAAQAMwQAA==.Miaomiaomiao:BAACNQAFFIEIAAIQAAUJzBCGAACuAQAQAAUJzBCGAACuAQA1AAQKgRkAAhAACQmcHvACAB0DABAACQmcHvACAB0DAAAA.Minamai:BAAANQAECgMIBgABNQAECgYICQALAAAAAA==.Misdirecting:BAAANQADCgYICgABNQADCggIDQALAAAAAA==.',
Mo='Monggoloid:BAAANQADCgMIAwAAAA==.Monsieurstun:BAAANQADCgEIAQAAAA==.Moongrass:BAAANQAECgEIAQAAAA==.Mousemarâ:BAAANQAECgQIBQAAAA==.',
Mu='Mungomania:BAAANQAECgEIAgAAAA==.Mutedz:BAAANQAECggIEgAAAA==.',
Na='Nagaridar:BAAANQADCgUIBQAAAA==.Nargorr:BAAANQADCgYIDAAAAA==.Naruwa:BAAANQADCgMIAwAAAA==.',
Ne='Necroticlol:BAABNQAECoEaAAMUAAkJSCEuBABzAwAUAAkJSCEuBABzAwAVAAEJlR5XKwBZAAAAAA==.Necroticlòl:BAAANQAECgUIBgABNQAECgkJGgAUAEghAA==.Neeyana:BAAANQADCgcICQAAAA==.Nefpore:BAAANQAECgEIAQAAAA==.Nenepok:BAAANQADCgYIBgAAAA==.',
Ni='Niij:BAAANQAECgEIAQAAAA==.Nitox:BAAANQAECgIIAgAAAA==.',
No='Norielia:BAAANQADCgMIAwAAAA==.Nosivire:BAAANQADCgYIAQAAAA==.Nosok:BAAANQAECgIIBAABNQAECggIDgALAAAAAA==.Notwiththema:BAAANQAECgQIBQAAAA==.Noughtawolf:BAAANQAECgQIBgAAAA==.',
Nt='Nthope:BAAANQAFFAUIBgAAAQ==.',
Od='Odîn:BAAANQADCgcIBwAAAA==.',
On='Onlyfire:BAAANQAECgUIBQAAAA==.Onlylight:BAAANQAECgIIAgAAAA==.',
Pa='Palabean:BAAANQADCgUIBgAAAA==.',
Pe='Peach:BAAANQADCgYIBgABNQAECgkJGgASAKQdAA==.Peeta:BAAANQADCgIIAgAAAA==.Pepperino:BAAANQADCgMIAwAAAA==.',
Ph='Phoebe:BAAANQADCgYIBgAAAA==.',
Pi='Piyona:BAAANQAECgQIBAAAAA==.',
Po='Poros:BAAANQADCgYIBgABNQAECgcIDgALAAAAAA==.Porosdk:BAAANQAECgcIDgAAAA==.Poteb:BAAANQADCgUIBwAAAA==.Powerangers:BAAANQADCgIIAgAAAA==.',
Pr='Prevailor:BAAANQADCgQIAQAAAA==.Prodigal:BAAANQAECggIEwAAAA==.',
Pt='Pterion:BAAANQAECgMIAwAAAA==.',
Pu='Pumbz:BAAANQAECgEIAgAAAA==.Punprepared:BAEANQAECggIBQAAAA==.',
Qe='Qeb:BAABNQAECoEbAAMGAAkJcyB+AQBrAwAGAAkJcyB+AQBrAwASAAUJLhE6GwBVAQAAAA==.',
Qi='Qio:BAAANQABCgUIBQAAAA==.Qisz:BAAANQAECgQIBAAAAA==.',
['Qí']='Qíqi:BAAANQAECgYIDAAAAA==.',
Ra='Rashes:BAAANQADCgEIAQAAAA==.Ratix:BAAANQADCgUIBQAAAA==.Ravenn:BAAANQAECgEIAQAAAA==.Razoxaynne:BAAANQAECgEIAQAAAA==.',
Rh='Rhyker:BAAANQAECgMIBAAAAA==.',
Ri='Rimreaper:BAAANQADCgcICgAAAA==.',
Ru='Ruptured:BAAANQAECgYIDgAAAA==.',
['Rä']='Räzoxane:BAAANQADCgIIAgAAAA==.',
Sa='Satria:BAAANQADCgcIBwAAAA==.',
Sc='Screamin:BAAANQADCgEIAQAAAA==.',
Sh='Shadowboiz:BAAANQAECgYICwAAAA==.Shamdoy:BAAANQAECgQICAAAAA==.Shapeshiift:BAAANQADCgYIBgAAAA==.Shidann:BAACNQAFFIEIAAINAAUJWiKhAAAgAgANAAUJWiKhAAAgAgA1AAQKgRsAAg0ACQnrJgwAABYEAA0ACQnrJgwAABYEAAAA.Shiifty:BAAANQADCgIIBAAAAA==.Shintopal:BAAANQAECgQIBAAAAA==.Shintoslash:BAAANQADCggIEgAAAA==.Shopgirl:BAAANQADCgYIBgAAAA==.',
Si='Silverdeath:BAAANQAECgUIBwAAAA==.Silvermaiden:BAAANQABCgIIAgAAAA==.Sinorph:BAAANQAECgYIDAAAAA==.',
Sl='Slappuccino:BAAANQAECgEIAwAAAA==.Sleeptime:BAAANQAECggICwAAAA==.',
Sn='Sneakyitch:BAAANQAECgUICQAAAA==.Snipez:BAAANQADCgQIBAABNQAECgcIDAALAAAAAA==.',
So='Soil:BAABNQAECoEXAAMJAAkJxhVCCQBqAgAJAAkJxhVCCQBqAgAOAAIJ5QneHQBmAAAAAA==.Solanaz:BAAANQADCgYICwAAAA==.Somepally:BAAANQAECgYICQABNQAECgQICQALAAAAAA==.Sorahal:BAAANQADCgEIAQAAAA==.',
Sp='Spagalnero:BAAANQAECgEIAQAAAA==.',
St='Stampedê:BAAANQADCgYIBgAAAA==.Stan:BAABNQAECoEbAAMWAAkJyB8XCwCuAgAWAAgJ6RwXCwCuAgABAAYJpCNuIgAgAgAAAA==.Stier:BAAANQADCgQIBAABNQADCggIDQALAAAAAA==.Stiggyy:BAAANQADCgYIBgAAAA==.Stiria:BAAANQAECgQIBgAAAA==.Stormscythe:BAAANQAECgIIAgAAAA==.',
Su='Supercleave:BAAANQADCggICAAAAA==.Superdope:BAAANQADCgcIDgAAAA==.Superfly:BAAANQAECgEIAgAAAA==.Supermayhem:BAAANQADCgQIBQAAAA==.Sutiao:BAAANQAFFAEIAQAAAA==.',
Sw='Swissarmy:BAAANQADCgYIBgAAAA==.Switchknife:BAAANQAECgUIBwAAAA==.',
Sy='Sylasiana:BAAANQAECgEIAQAAAA==.Synasta:BAAANQAECggIEwAAAA==.Syrent:BAAANQAECgQIBQAAAA==.',
Ta='Taano:BAAANQADCgUIBgAAAA==.Tallia:BAAANQADCggIDgABNQAECgQIEAALAAAAAA==.Talons:BAAANQAECgIIAgAAAA==.Tancs:BAAANQADCggIDgAAAA==.Tarocakes:BAAANQAECgYICQAAAA==.Taurium:BAAANQAECgYIDAAAAA==.',
Te='Teaki:BAAANQAECgUIBwAAAA==.Telsh:BAAANQAECgYICAAAAA==.Temsik:BAAANQAECgUICgAAAA==.Temsikdab:BAAANQADCgEIAQAAAA==.',
Th='Thoth:BAAANQAECgcIEAAAAA==.Thrallish:BAAANQADCgcIBwAAAA==.Thrux:BAAANQAECgUIBgAAAA==.',
Ti='Tidal:BAAANQAECgEIAQABNQAECgUIBgALAAAAAA==.Tiddlyniblit:BAAANQADCgcIEwAAAA==.',
To='Tommyh:BAACNQAFFIEHAAIXAAUJNRSuAADIAQAXAAUJNRSuAADIAQA1AAQKgRsAAhcACQnvJM8AAMkDABcACQnvJM8AAMkDAAAA.Topuzzible:BAAANQAECgEIAQABNQAECgUIBQALAAAAAA==.Torress:BAAANQADCggIEgAAAA==.Totemistyk:BAAANQAECggICgAAAA==.Toufz:BAAANQAECgcIDAAAAA==.',
Tr='Trianth:BAAANQAECgUICQAAAA==.Tribbie:BAABNQAECoEXAAQUAAkJlh4yDADeAgAUAAgJ1h8yDADeAgAVAAEJlBS7LQBJAAATAAEJgRHQZAA1AAAAAA==.Tribbier:BAAANQAECgMIAwAAAA==.',
Tw='Twidger:BAAANQAECgEIAQAAAA==.',
Ty='Tyranadia:BAABNQAECoEaAAIUAAkJZRQ/EQCVAgAUAAkJZRQ/EQCVAgAAAA==.Tystus:BAAANQADCgYIDAAAAA==.',
Up='Upstairs:BAAANQAECggIDwAAAA==.',
Ur='Uruga:BAAANQADCgcIEQAAAA==.',
Va='Varnoxx:BAAANQAECggIEwAAAA==.',
Vi='Vicioûs:BAAANQAECgQIBgAAAA==.Vinwink:BAAANQADCgYIBgAAAA==.Vishnar:BAAANQAECgcIDgAAAA==.',
Vo='Vollic:BAAANQADCggICAAAAA==.',
Vv='Vvoo:BAAANQAECgEIAQAAAA==.',
Vy='Vyndish:BAAANQADCgEIAQAAAA==.',
Wa='Wander:BAAANQAECgQIBwAAAA==.Wardz:BAAANQADCgUIBQAAAA==.Watever:BAAANQAECggIBgAAAA==.Wavedash:BAAANQAECgEIAQAAAA==.Wazaldin:BAAANQADCgUICAAAAA==.',
Wh='Whispess:BAAANQAECgIIAgAAAA==.',
Wi='Winnievoid:BAAANQAECgYIBgAAAA==.',
Wo='Woodro:BAAANQAECgYIDAAAAA==.Woz:BAAANQADCgcIDAABNQAECgEIAQALAAAAAA==.',
Xl='Xln:BAAANQAECgIIAgABNQAECgYICQALAAAAAA==.',
Xt='Xtion:BAAANQAECggIEwAAAA==.',
Ya='Yagnatia:BAAANQAECgUIBgAAAA==.',
Yo='Yongbok:BAAANQAECgEIAQAAAA==.',
Yr='Yrano:BAAANQAECgEIAQAAAA==.',
Yv='Yva:BAAANQADCggIBAAAAA==.',
Za='Zapu:BAAANQADCgQIBAAAAA==.Zaraxes:BAAANQADCgMIBQAAAA==.',
Ze='Zelgaira:BAAANQAECggIEgABNQAECggIEwALAAAAAA==.Zelind:BAAANQADCgUIBwABNQAECgQIBgALAAAAAA==.Zelvaris:BAACNQAFFIEHAAIYAAUJsiAMAAAHAgAYAAUJsiAMAAAHAgA1AAQKgR8AAhgACQkDInYAAIgDABgACQkDInYAAIgDAAAA.Zenõ:BAAANQAECgcICQAAAA==.Zerine:BAAANQAECgEIAQAAAA==.Zerkerman:BAAANQADCgcIBwAAAA==.',
Zi='Zirka:BAAANQAECgQIEAAAAA==.Zivayhr:BAAANQADCgEIAQAAAA==.',
Zu='Zucchini:BAAANQADCgYICAAAAA==.',
Zy='Zylexo:BAAANQABCgIIAgAAAA==.',
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
