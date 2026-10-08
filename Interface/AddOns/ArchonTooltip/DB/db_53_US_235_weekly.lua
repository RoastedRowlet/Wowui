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

local lookup = {'Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Priest-Holy','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Mage-Arcane','DemonHunter-Devourer','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Paladin-Protection','Hunter-Survival','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','DeathKnight-Frost','Warrior-Arms','Warlock-Affliction','Shaman-Restoration',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAAANQAECggICQAAAA==.Aendrel:BAAANQAFFAEIAQAAAA==.',
Ai='Airaquafira:BAAANQAECgYIEwAAAA==.',
Aj='Ajheria:BAAANQADCgYICQABNQAECggIGwABAMISAA==.',
Al='Alégria:BAAANQAECgYIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECoEYAAICAAcKBgN8awDyAAACAAcKBgN8awDyAAAAAA==.Andalaine:BAAANQADCgYIDAAAAA==.Anraleth:BAABNQAECoEmAAIDAAkKsCMCBgBnAwADAAkKsCMCBgBnAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAAANQAECgcIDQAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECgUICwAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQADCgQIBAAAAA==.',
Av='Averlis:BAAANQAECgUICQAAAA==.Avoiddance:BAAANQADCgYIBgABNQAECggIGwABAMISAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAAANQAECgYICQAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAABNQAECoEbAAMEAAcKNxO9LgAEAQABAAUKfxC6sgA6AQAEAAQKWBS9LgAEAQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQAECgUICQABNQAECgkJHwACAEsgAA==.Blueparrot:BAABNQAECoEXAAIFAAgK1wq3bgCZAQAFAAgK1wq3bgCZAQAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQADCgcIHQABNQADCggIIQAGAAAAAA==.',
Bu='Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQADCggIDQAAAA==.',
Ca='Cassandria:BAAANQAECgYIEQAAAA==.Cassiradra:BAAANQADCgUIBQAAAA==.',
Ce='Cervixticklr:BAAANQADCggIFgAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECoEhAAIHAAgKQiM0FAAfAwAHAAgKQiM0FAAfAwABNQADCgQIBAAGAAAAAA==.Châos:BAABNQAECoEcAAIIAAgKIxBMlwC/AQAIAAgKIxBMlwC/AQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAAANQAECgYIEwAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYICwAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFIERAAIJAAUKPQtPHQBdAQAJAAUKPQtPHQBdAQA1AAQKgR4AAgkACQpcHUpeAK8CAAkACQpcHUpeAK8CAAAA.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAABNQAECoEfAAIKAAgKuh2TEQDNAgAKAAgKuh2TEQDNAgAAAA==.Cuzon:BAAANQAECgcIEQAAAA==.',
Cy='Cyhyraethia:BAAANQAECgUIDwABNQAECgkJJgAKAIkbAA==.',
Da='Dagden:BAAANQAECgEIAQAAAA==.Daish:BAAANQADCgEIAQAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAECgcIBwABNQAFFAQIBgALAHoSAA==.Daricepicker:BAABNQAECoEnAAIMAAkKtiB1EwA6AwAMAAkKtiB1EwA6AwAAAA==.Darkyn:BAABNQAECoEbAAIBAAgKwhJuXAAgAgABAAgKwhJuXAAgAgAAAA==.',
Dd='Ddeonù:BAABNQAECoEhAAIKAAkKlRPCGwBbAgAKAAkKlRPCGwBbAgAAAA==.',
De='Deadlysins:BAAANQADCggICAAAAA==.Deadscar:BAEBNQAECoEdAAINAAgKryW4AwBYAwANAAgKryW4AwBYAwAAAA==.Deathmasterj:BAAANQADCgcIDQAAAA==.Delphinium:BAAANQADCgQIBAAAAA==.Dentheaded:BAACNQAFFIEZAAIIAAcKlCDCAAC2AgAIAAcKlCDCAAC2AgA1AAQKgSUAAggACQoDJkoHALcDAAgACQoDJkoHALcDAAAA.',
Di='Dithariaa:BAAANQADCgEIAQAAAA==.',
Do='Docryktor:BAABNQAECoEdAAINAAcKMRe7EgAaAgANAAcKMRe7EgAaAgAAAA==.Doomgears:BAAANQADCgEIAQAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAGAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgIIAgAAAA==.Drogas:BAABNQAECoEiAAQOAAgKNxA4HQDbAQAOAAgKNxA4HQDbAQAPAAYKrAfFIQAgAQAQAAUKJw0vEgDgAAAAAA==.Drtybear:BAAANQAECgEIAQAAAA==.Druithz:BAAANQAECgQIBAABNQAECgkJKgAHAD0dAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECgYIBwAAAA==.',
Ed='Ediana:BAABNQAECoEdAAMJAAgKjQVF8ACEAQAJAAgKjAVF8ACEAQARAAIKcgMZOgBBAAAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECgYIDQAAAA==.',
El='Elandrah:BAAANQAECgYIDgAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECoEeAAIHAAcKORqiQwA5AgAHAAcKORqiQwA5AgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAAANQAECgYIEQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAAANQAECgUIEAAAAA==.',
Fa='Fantabulouus:BAAANQAECgcIDAAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fathertim:BAAANQADCgEIAQAAAA==.',
Fe='Feldrena:BAAANQADCgYIDAAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECoEXAAICAAgK8yJPJgB/AgACAAgK8yJPJgB/AgAAAA==.Foxyhound:BAAANQAECggIDQAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAAANQAECgMIBAAAAA==.Fugryktor:BAAANQAECgQICQABNQAECgcIHQANADEXAA==.Fuu:BAAANQABCgMJAwAAAA==.',
Fy='Fyre:BAAANQADCgQIBQAAAA==.',
Ga='Galandor:BAAANQAECgEIAQAAAA==.Gandaalf:BAAANQAECgcIDQAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAAANQAECgcIDQAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIHQABNQADCggIIQAGAAAAAA==.Gityahunter:BAAANQADCggIIQAAAA==.',
Go='Gobanks:BAABNQAECoEjAAISAAgK8h4NDAC4AgASAAgK8h4NDAC4AgAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAcIGgATAH8jAA==.Grayson:BAAANQAECgEIAQAAAA==.Graysurv:BAACNQAFFIEaAAITAAcKfyMGAAD3AgATAAcKfyMGAAD3AgA1AAQKgSUAAhMACQoEJz0AAN0DABMACQoEJz0AAN0DAAAA.Grimik:BAAANQAECgcIEQAAAA==.Grimwali:BAAANQAECgMIBAAAAA==.',
Ha='Hallêlujah:BAAANQABCgEIAQAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgYIBwAGAAAAAA==.Hardrock:BAEANQADCgcIEAABNQAECggIEAAGAAAAAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBgABNQAECgUIBgAGAAAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgQICAAGAAAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAAANQAECgcIDAAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAUIDgAUAOIiAA==.Indawhole:BAACNQAFFIEOAAIUAAUK4iLiBADmAQAUAAUK4iLiBADmAQA1AAQKgSIAAxQACQqgJCwQAAcDABQACAqqJCwQAAcDAAoACAqwIFsZAHUCAAAA.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQAECgEIAQAAAA==.',
Ja='Jasmean:BAAANQADCgQIBAAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAAANQAECgYIEQAAAA==.Jaytsukitori:BAAANQAECgYICgABNQAECgcIEQAGAAAAAA==.',
Jd='Jdots:BAAANQADCgcIDAAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECggIGwABAMISAA==.Jheranton:BAAANQADCgYICgABNQAECggIGwABAMISAA==.',
Ji='Jif:BAAANQAECgUIBQAAAA==.',
Jo='Joesepi:BAAANQAECgIIAgAAAA==.Jonah:BAAANQAECgcICwABNQAECggIEwAGAAAAAA==.Joodee:BAAANQAECgUICwAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgkJHwAVANcjAA==.',
Ka='Kackarot:BAABNQAECoEkAAIWAAkKBRPbQwA7AgAWAAkKBRPbQwA7AgAAAA==.Katrine:BAABNQAECoEgAAIXAAgKrRVHKQAbAgAXAAgKrRVHKQAbAgAAAA==.',
Ke='Kendreth:BAAANQADCgQIBAAAAA==.',
Ki='Kij:BAECNQAFFIELAAMRAAQKdhAgBQCnAAARAAIKHxUgBQCnAAAJAAIKzQsqOwCfAAA1AAQKgSAAAwkACQr4H2pAAPYCAAkACQrPH2pAAPYCABEAAQqMJYAsAHAAAAAA.Kilrah:BAABNQAECoEaAAIUAAgKGAptPQCYAQAUAAgKGAptPQCYAQAAAA==.Kissmycrits:BAAANQAECgQIEwAAAA==.Kissmywrath:BAAANQAECgEIAQAAAA==.Kiyana:BAAANQAECgUIBwAAAA==.Kiyoine:BAAANQAECgYIEQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUICQAAAA==.',
Kr='Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECoEZAAIVAAcKgA2SMQBaAQAVAAcKgA2SMQBaAQAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAGAAAAAA==.Laetha:BAAANQADCggIDgABNQAECgYIDwAGAAAAAA==.',
Li='Lightweaver:BAAANQAECggIAQAAAA==.Linai:BAABNQAECoEoAAILAAgKKAntHgDEAQALAAgKKAntHgDEAQAAAA==.Linthe:BAABNQAECoEVAAMHAAgK7QnubwCgAQAHAAgK7QnubwCgAQAIAAEKdwZTfAEwAAAAAA==.Lit:BAAANQAECgIIBgAAAA==.Lites:BAAANQAECgYICwAAAA==.Littledog:BAAANQAECgcIEAAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECoEhAAIIAAgKTRfeeAALAgAIAAgKTRfeeAALAgAAAA==.',
Lu='Luckevin:BAAANQAECgQIBgAAAA==.Lumi:BAAANQADCggICAAAAA==.Lurashtai:BAAANQAECgQIBgAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Malafang:BAAANQAECgEIAgAAAA==.Malanah:BAAANQAECgEIAQAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Mattu:BAAANQADCgQIBAAAAA==.Maverick:BAACNQAFFIEGAAILAAQKehIdCABaAQALAAQKehIdCABaAQA1AAQKgSUAAgsACQr+IKQFACUDAAsACQr+IKQFACUDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgQICQAAAA==.',
Mk='Mk:BAEANQADCggIDgABNQAECgQIBAAGAAAAAA==.',
Mo='Mogar:BAABNQAECoEVAAIYAAgK1AmExgA3AQAYAAgK1AmExgA3AQAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgEIAQAAAA==.Mordread:BAAANQADCggIFgAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFIEFAAIMAAMKjRdKEgABAQAMAAMKjRdKEgABAQA1AAQKgRsAAwwACQoTIvogAPYCAAwACQoTIvogAPYCAAMACAppECgvAKwBAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFIEXAAMZAAcKOBo6AAAtAgAZAAYKlRs6AAAtAgABAAUKXhbVCACvAQA1AAQKgSwAAxkACQreI6wAAH8DABkACQreI6wAAH8DAAEAAwpjHoXKAAcBAAE1AAQKBggHAAYAAAAA.',
Ni='Nivmizzet:BAABNQAECoEXAAMBAAcK0hoOcwDeAQABAAYKkRsOcwDeAQAEAAIKzxZfTgCIAAAAAA==.',
No='Nolakai:BAAANQADCgcIGQAAAA==.Novagosa:BAAANQAECgUICwABNQAECgkJHgAaAIMjAA==.Novalea:BAABNQAECoEeAAIaAAkKgyOyBgB+AwAaAAkKgyOyBgB+AwAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQADCgcIKgABNQADCggILQAGAAAAAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQADCgEIAQAAAA==.',
Pa='Palomar:BAAANQAECgEIAQAAAA==.Paraggonn:BAAANQAECgQIBwAAAA==.',
Ph='Pherkle:BAAANQAECgEIAQABNQAECgcIHQANADEXAA==.Phuriosa:BAAANQAECgEIAQABNQAECggIGAAVAPISAA==.Phury:BAABNQAECoEYAAIVAAgK8hJUIgDnAQAVAAgK8hJUIgDnAQAAAA==.Physinyx:BAABNQAECoEcAAMWAAkKygrskwBCAQAWAAcKig3skwBCAQAaAAgKmwBh3ACFAAAAAA==.',
Pi='Pizza:BAAANQADCgEIAQAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAAANQAECgcIDwAAAA==.',
Pu='Pumbaa:BAAANQAECgEJAQABNQAECgcJBwAGAAAAAA==.',
Ra='Raenyx:BAABNQAECoEaAAMBAAkKyA5xigCeAQABAAkKyA5xigCeAQAEAAEKHAHNgAAeAAABNQAECgkJHAAWAMoKAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAAANQAECgUIDAAAAA==.Raveneyes:BAEANQAECgYIDAAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAAANQAECgYIEgAAAA==.',
Rh='Rhaenfyre:BAABNQAECoEhAAMKAAgKBB2rHgA9AgAKAAcKrx2rHgA9AgAUAAEKWRi8fABDAAAAAA==.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAQIBgALAHoSAA==.Rivenel:BAACNQAFFIEFAAMEAAIKoQ4AHABMAAABAAEKiRGRNQBNAAAEAAEKuAsAHABMAAA1AAQKgScAAwQACQpCHYoFALQCAAQACArhHIoFALQCAAEABwoMGWZfABcCAAAA.',
Ro='Robinvoid:BAAANQAECggIEgAAAA==.Rodel:BAAANQADCgQIBAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAAANQAECgYIEAAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAQIBgALAHoSAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgUIBgAAAA==.Rundas:BAAANQAECgUICwAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAAANQAECgUICwAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIDQAAAA==.Saddie:BAAANQADCgYICwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQAECgEIAQAAAA==.Sanasath:BAAANQAECgUIDQABNQAECgcIFgASAH8bAA==.',
Se='Segador:BAAANQAECgQIBwAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAGAAAAAA==.',
Sh='Shamanizim:BAABNQAECoErAAIWAAkK+iBvEQBQAwAWAAkK+iBvEQBQAwAAAA==.Shamanka:BAAANQADCgIIAgAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEgABNQAECggIJwAYALwTAA==.Shinotenshi:BAAANQAECgMIBgABNQAECggIJwAYALwTAA==.Shugarae:BAAANQAECgYICAAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgMIAwAAAA==.',
Sl='Slashemup:BAAANQAECgcIEgAAAA==.Slayter:BAABNQAECoEfAAIVAAkK1yM/BQBeAwAVAAkK1yM/BQBeAwAAAA==.',
Sm='Smaugor:BAAANQAECgYJEQABNQAECgcJBwAGAAAAAA==.',
So='Soju:BAAANQAECgEIAgABNQAECgkJJwAMALYgAA==.Solder:BAAANQADCggICAAAAA==.Soliloquy:BAAANQAECgYIEwAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECoEeAAIBAAkK+hzkGwAAAwABAAkK+hzkGwAAAwAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgkJHgABAPocAA==.',
St='Stare:BAEANQADCggIDQABNQAECggIHQANAK8lAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIDAAGAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAGAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAAANQAECgEIAQAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgUICwAAAA==.',
Te='Telda:BAAANQADCgYICwAAAA==.Teneturadvos:BAAANQAECgIIAgABNQAECgYIBwAGAAAAAA==.Terrorwynd:BAAANQAECgMIAwAAAA==.',
Th='Thellaria:BAAANQAECgEIAQAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAGAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Treala:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECoEWAAISAAcKfxtuGQD9AQASAAcKfxtuGQD9AQAAAA==.Truthfully:BAAANQAECgUICgAAAA==.',
Tt='Ttjpll:BAAANQAECgEIAQAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAAANQAECgYIEwABNQAFFAUIDQASAKUZAA==.Unhappytoast:BAACNQAFFIENAAISAAUKpRkrAwCiAQASAAUKpRkrAwCiAQA1AAQKgSEAAhIACQpYIzMHABcDABIACQpYIzMHABcDAAAA.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFIEJAAIYAAQKQwMfGwDxAAAYAAQKQwMfGwDxAAA1AAQKgSIAAhgACQq4FLxlAD8CABgACQq4FLxlAD8CAAAA.',
Va='Valisanna:BAAANQADCgQIBAAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQAECgEIAQAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAAANQAECgYIEQAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQADCgYIDAAAAA==.',
Wh='Whiteparrot:BAAANQADCgQIBgAAAA==.Wholy:BAABNQAECoEdAAMHAAkKchhLKgClAgAHAAkKchhLKgClAgAIAAMKxxT3DAHSAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAQABNQAECgYIBwAGAAAAAA==.',
Xa='Xaanii:BAAANQAECgEIAQAAAA==.Xarferrin:BAAANQADCgEIAQAAAA==.',
Xe='Xeeria:BAABNQAECoEdAAMaAAkKkhwuIQDFAgAaAAkKkhwuIQDFAgAWAAMKgxjTxgDWAAAAAA==.Xenzull:BAAANQAECgEIAQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Za='Zadee:BAAANQADCgUIBQAAAA==.Zaralina:BAAANQAECgYIDwAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgQIBAAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAGAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECggIGwABAMISAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECoEaAAIMAAcK0RI5fgDiAQAMAAcK0RI5fgDiAQAAAA==.Zomboy:BAAANQADCgMIAwAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgUICgAAAA==.',
Zu='Zu:BAAANQAECgEIAQAAAA==.Zug:BAAANQAECgYIEgAAAA==.',
['Âr']='Ârc:BAAANQAECgIIBAAAAA==.',
['ßl']='ßlue:BAAANQABCgIIAgAAAA==.',
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
