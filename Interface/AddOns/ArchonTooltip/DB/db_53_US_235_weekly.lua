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

local lookup = {'DemonHunter-Devourer','Shaman-Restoration','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Priest-Holy','Unknown-Unknown','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Guardian','Mage-Fire','Paladin-Protection','Hunter-Survival','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Monk-Windwalker','Warrior-Arms','Monk-Mistweaver','Priest-Shadow','Priest-Discipline','DeathKnight-Blood',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAAANQAECggICwAAAA==.Aendrel:BAABNQAECn8WAAIBAAgKWCDWEADnAgABAAgKWCDWEADnAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8eAAICAAgKlx7CKAC+AgACAAgKlx7CKAC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECggIHAADAJQSAA==.',
Al='Alejandro:BAAANQAECgcIBwAAAA==.Alégria:BAAANQAECgYIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8gAAIEAAgKLQX+YABHAQAEAAgKLQX+YABHAQAAAA==.Andalaine:BAAANQADCgcIEwAAAA==.Anraleth:BAABNQAECn8sAAIFAAkK+CPUAwCZAwAFAAkK+CPUAwCZAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAAANQAECgcIDwAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECgUICwAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICAAAAA==.',
Av='Averlis:BAAANQAECgUIDgAAAA==.Avoiddance:BAAANQADCgYIBgABNQAECggIHAADAJQSAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAAANQAECgYIDwAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAABNQAECn8cAAMGAAgKBRJMMQABAQADAAYKBg6fsQBnAQAGAAQKfBZMMQABAQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQAFFAEIAQABNQAECgkJJwAEAB0hAA==.Blueparrot:BAABNQAECn8cAAIHAAkKEArCbwDKAQAHAAkKEArCbwDKAQAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQAECgMIAwABNQAECgQIBAAIAAAAAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgQIBAAAAA==.',
Ca='Cassandria:BAABNQAECn8ZAAMEAAgKeQgpXABdAQAEAAcKeQgpXABdAQAJAAEKTwFshQAPAAAAAA==.Cassiradra:BAAANQADCgUIBQAAAA==.',
Ce='Cervixticklr:BAAANQADCggIGgAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8kAAIKAAkKaCKJCwBrAwAKAAkKaCKJCwBrAwABNQADCgQIBAAIAAAAAA==.Châos:BAABNQAECn8eAAILAAkKvg11lAD2AQALAAkKvg11lAD2AQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAABNQAECn8eAAIMAAgKShZFUAB8AgAMAAgKShZFUAB8AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFH8UAAINAAYK/A/xFwCzAQANAAYK/A/xFwCzAQA1AAQKfx4AAg0ACQpdHSB0AJUCAA0ACQpdHSB0AJUCAAAA.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAABNQAECn8kAAIBAAkKfR/+CwAeAwABAAkKfR/+CwAeAwAAAA==.Cuzon:BAAANQAECgcIEQABNQAFFAEIAQAIAAAAAA==.',
Cy='Cyhyraethia:BAABNQAECn8ZAAIOAAgKoBwDAwDWAgAOAAgKoBwDAwDWAgABNQAFFAIIBQABAHAWAA==.',
Da='Dagden:BAAANQAECgEIAQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAQIBgAPAMoMAA==.Daricepicker:BAABNQAECn8qAAIMAAkKnSDMGgAsAwAMAAkKnSDMGgAsAwAAAA==.Darkyn:BAABNQAECn8cAAIDAAgKlBLcaQAbAgADAAgKlBLcaQAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8FAAIBAAIK3ALlEgBjAAABAAIK3ALlEgBjAAA1AAQKfyMAAgEACQqlFCEhAEECAAEACQqlFCEhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICAAIAAAAAA==.Deadscar:BAEBNQAECn8iAAIQAAkKbCNuAgCEAwAQAAkKbCNuAgCEAwAAAA==.Deathmasterj:BAAANQADCggIDwAAAA==.Delphinium:BAAANQADCgQICAAAAA==.Dentheaded:BAACNQAFFH8fAAILAAcKESQfAQC5AgALAAcKESQfAQC5AgA1AAQKfygAAgsACQr6JcQLAKEDAAsACQr6JcQLAKEDAAAA.',
Di='Dithariaa:BAAANQAECgQIBAAAAA==.',
Do='Docryktor:BAABNQAECn8kAAIQAAgKuRZZEABiAgAQAAgKuRZZEABiAgAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAIAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgMIBAAAAA==.Drogas:BAABNQAECn8qAAQRAAgKLBFhHwDcAQARAAgKLBFhHwDcAQASAAYKsQdYJAAbAQATAAUK3wvLFADeAAAAAA==.Drtybear:BAAANQAECgIIAwAAAA==.Druithz:BAAANQAECgQIBAABNQAECgkJLQAKAD0dAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECgYIBwAAAA==.',
Ed='Ediana:BAABNQAECn8fAAMNAAgKPgh7/QCPAQANAAgKPgh7/QCPAQAUAAIKcgOfQABBAAAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECgYIDwAAAA==.',
El='Elandrah:BAABNQAECn8VAAIHAAcKkgJHrgAGAQAHAAcKkgJHrgAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn8lAAIKAAcKZxpfTQAyAgAKAAcKZxpfTQAyAgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn8YAAIVAAcK8hJ/HgClAQAVAAcK8hJ/HgClAQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAAANQAECgYIEQAAAA==.',
Fa='Fantabulouus:BAAANQAECgcIEQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgQIBAAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSMlLQBwAgAEAAgKLSMlLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAAANQAECgMIBAAAAA==.Fugryktor:BAAANQAECgQICQABNQAECggIJAAQALkWAA==.Fuu:BAAANQABCgMJAwAAAA==.',
Fy='Fyre:BAAANQADCgQIBQAAAA==.',
Ga='Galandor:BAAANQAECgIIAwAAAA==.Gandaalf:BAABNQAECn8XAAQWAAgKkh44AgA6AgAWAAYKfR84AgA6AgAUAAMKWRdOJADIAAANAAEKAABUpwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAAANQAECgcIDQAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIIwABNQAECgQIBAAIAAAAAA==.Gityahunter:BAAANQAECgQIBAAAAA==.',
Go='Gobanks:BAABNQAECn8rAAIXAAkKfh5mCAAWAwAXAAkKfh5mCAAWAwAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAgIHAAYAOciAA==.Grayson:BAAANQAECgIIAwAAAA==.Graysurv:BAACNQAFFH8cAAIYAAgK5yIDAABjAwAYAAgK5yIDAABjAwA1AAQKfygAAhgACQoHJ14AAM8DABgACQoHJ14AAM8DAAAA.Grimik:BAAANQAECggIEwAAAA==.Grimwali:BAAANQAECgMIBwAAAA==.',
Ha='Hallêlujah:BAAANQABCgEIAQAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgcICgAIAAAAAA==.Hardrock:BAEANQADCgcIEAABNQAECgkJGQAZAD0HAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBgABNQAECgUIBgAIAAAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgUIDQAIAAAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAAANQAECgcIDQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAYIEwAaAN4dAA==.Indawhole:BAACNQAFFH8TAAIaAAYK3h2hAwA/AgAaAAYK3h2hAwA/AgA1AAQKfyQAAxoACQoqJZ8UAPUCABoACAocJZ8UAPUCAAEACArKIA0fAFQCAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECggIHAADAJQSAA==.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQAECgIIAwAAAA==.',
Ja='Jasmean:BAAANQADCgQIBAAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAABNQAECn8ZAAILAAgKRBNnkAD/AQALAAgKRBNnkAD/AQAAAA==.Jaytsukitori:BAAANQAFFAEIAQAAAA==.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECggIHAADAJQSAA==.Jheranton:BAAANQADCgYICgABNQAECggIHAADAJQSAA==.',
Ji='Jif:BAAANQAECgUIBQAAAA==.',
Jo='Joesepi:BAAANQAECgcICQAAAA==.Jonah:BAABNQAECn8bAAQOAAkK7SHrBACAAgAOAAcKih/rBACAAgADAAcKchsQUgBcAgAGAAQKmB3/KAAxAQABNQAECgkJHQAbAF4jAA==.Joodee:BAAANQAECgUICwAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgkJIQAJAPYjAA==.',
Ka='Kackarot:BAABNQAECn8nAAIZAAkK/RLCUAAyAgAZAAkK/RLCUAAyAgAAAA==.Katrine:BAABNQAECn8nAAIcAAgKNxd4KQBJAgAcAAgKNxd4KQBJAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8NAAMUAAQK6hR5AwDjAAAUAAMKYRB5AwDjAAANAAIKgBQnSACVAAA1AAQKfyAAAw0ACQqcHjlQAOACAA0ACQpnHjlQAOACABQAAQqMJbAyAG0AAAAA.Kilrah:BAABNQAECn8iAAIaAAgKWgvkQQCtAQAaAAgKWgvkQQCtAQAAAA==.Kissmycrits:BAABNQAECn8aAAIMAAUKshnt0QBXAQAMAAUKshnt0QBXAQAAAA==.Kissmywrath:BAAANQAECgQIBQAAAA==.Kiyana:BAAANQAECgYIDQAAAA==.Kiyoine:BAABNQAECn8VAAIdAAYKfw5SGgBWAQAdAAYKfw5SGgBWAQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8bAAIJAAgKgQ0WMQCOAQAJAAgKgQ0WMQCOAQAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAIAAAAAA==.Laetha:BAAANQADCggIDgABNQAECgcIFwASAOAUAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn8uAAIPAAkKOAd0HQDkAQAPAAkKOAd0HQDkAQAAAA==.Linthe:BAABNQAECn8cAAMKAAkK9gpmaQDYAQAKAAkK9gpmaQDYAQALAAEKdwZjqAEwAAAAAA==.Lit:BAAANQAECgIIBwAAAA==.Lites:BAAANQAECgYICwAAAA==.Littledog:BAAANQAFFAEIAQAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8jAAILAAgKkhc0hgAWAgALAAgKkhc0hgAWAgAAAA==.',
Lu='Luckevin:BAAANQAECgUIBwAAAA==.Lumi:BAAANQAECgIIAgAAAA==.Lurashtai:BAAANQAECgUICwAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Magicmann:BAAANQADCgQIBAAAAA==.Magicor:BAAANQADCggICAAAAA==.Malafang:BAAANQAECgIIBAAAAA==.Malanah:BAAANQAECgEIAQAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Mattu:BAAANQADCgQICAAAAA==.Maverick:BAACNQAFFH8GAAIPAAQKygzHCQBCAQAPAAQKygzHCQBCAQA1AAQKfyYAAg8ACQqEIK0GABMDAA8ACQqEIK0GABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgYIDgAAAA==.',
Mk='Mk:BAEANQAECgQIBAABNQAECggIJQAeAOIdAA==.',
Mo='Mogar:BAABNQAECn8XAAIfAAgKLAzXxwBiAQAfAAgKLAzXxwBiAQAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgEIAQAAAA==.Mordread:BAAANQADCggIGQAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8IAAIMAAQKyhhbDgBpAQAMAAQKyhhbDgBpAQA1AAQKfyEAAwwACQqUIl0iAAwDAAwACQqUIl0iAAwDAAUACArsDp41AJ0BAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFH8dAAMOAAcKex1aAAAjAgAOAAYKWCBaAAAjAgADAAUKYhmRCgDEAQA1AAQKfy4AAw4ACQouJfUAAG0DAA4ACQouJfUAAG0DAAMAAwpXH3bbAA0BAAE1AAQKBwgKAAgAAAAA.',
Ni='Nivmizzet:BAABNQAECn8gAAMDAAkKzhhnWQBHAgADAAgKyhdnWQBHAgAGAAIKGBvISgCeAAAAAA==.',
No='Nolakai:BAAANQAECgQIBAAAAA==.Novagosa:BAAANQAECgUICwABNQAECgkJIgACAIMjAA==.Novalea:BAABNQAECn8iAAICAAkKgyOUCAB7AwACAAkKgyOUCAB7AwAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBAABNQAECgYICQAIAAAAAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQAECgQIBAAAAA==.',
Pa='Palomar:BAAANQAECgIIAwAAAA==.Paraggonn:BAAANQAECgQIBwAAAA==.',
Ph='Pherkle:BAAANQAECgIIAwABNQAECggIJAAQALkWAA==.Phuriosa:BAAANQAECgEIAQABNQAECggIGgAJAPISAA==.Phury:BAABNQAECn8aAAIJAAgK8hIIKADcAQAJAAgK8hIIKADcAQAAAA==.Physinyx:BAABNQAECn8qAAMZAAkKsguecgDFAQAZAAkKsguecgDFAQACAAgKmwBw7wCGAAAAAA==.',
Pi='Pizza:BAAANQAECgQIBAAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAAANQAECgcIEQAAAA==.',
Pu='Pumbaa:BAAANQAECgEJAQABNQAECgcJBwAIAAAAAA==.',
Qu='Quilby:BAAANQADCgUIBQAAAA==.',
Ra='Raenyx:BAABNQAECn8iAAMDAAkKswzUoACPAQADAAkKswzUoACPAQAGAAEKAAAXhwAeAAABNQAECgkJKgAZALILAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAAANQAECgUIEQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEANQAECgcIDgAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8XAAIgAAgKcw4MHwCWAQAgAAgKcw4MHwCWAQAAAA==.',
Rh='Rhaenfyre:BAABNQAECn8jAAMBAAkKEB0SHAByAgABAAgK2R0SHAByAgAaAAEKWRhNiwBCAAAAAA==.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAQIBgAPAMoMAA==.Rivenel:BAACNQAFFH8FAAMGAAIKoQ5uHwBKAAADAAEKiRE/PgBNAAAGAAEKuAtuHwBKAAA1AAQKfy8AAwYACQp3HtQFALUCAAYACAq0G9QFALUCAAMABwpMG29aAEQCAAAA.',
Ro='Robinvoid:BAAANQAECggIEgAAAA==.Rodel:BAAANQADCgQIBAAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn8XAAIcAAcKnRGJRgCfAQAcAAcKnRGJRgCfAQAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAQIBgAPAMoMAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgUIBgAAAA==.Rundas:BAAANQAECgUICwAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAAANQAECgYIEAAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEQAAAA==.Saddie:BAAANQADCgYICwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQAECgIIAwAAAA==.Sanasath:BAAANQAECgUIEQABNQAECgcIFgAXAPIaAA==.',
Se='Segador:BAAANQAECgQIBwAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAIAAAAAA==.',
Sh='Shamanizim:BAABNQAECn81AAIZAAkKziNLEABpAwAZAAkKziNLEABpAwAAAA==.Shamanka:BAAANQADCgIIAgAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEgABNQAECgkJKgAfAPgRAA==.Shinotenshi:BAAANQAECgMIBgABNQAECgkJKgAfAPgRAA==.Shugarae:BAAANQAECgYICAAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgMIAwAAAA==.',
Sl='Slashemup:BAAANQAECgcIEgAAAA==.Slayter:BAABNQAECn8hAAIJAAkK9iPXBQBjAwAJAAkK9iPXBQBjAwAAAA==.',
Sm='Smaugor:BAAANQAECgYJEQABNQAECgcJBwAIAAAAAA==.',
So='Soju:BAAANQAECgQIBgABNQAECgkJKgAMAJ0gAA==.Solder:BAAANQADCggICAAAAA==.Soliloquy:BAABNQAECn8dAAMhAAgKfBJlKgDRAQAhAAcKdRRlKgDRAQAiAAUKiBEcDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn8mAAIDAAkKoR0vGAAmAwADAAkKoR0vGAAmAwAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgkJJgADAKEdAA==.',
St='Stare:BAEANQADCggIEgABNQAECgkJIgAQAGwjAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIDgAIAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAIAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAAANQAECgIIAwAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgYICwAAAA==.',
Te='Telda:BAAANQADCgYIEQAAAA==.Teneturadvos:BAAANQAECgIIAgABNQAECgYIBwAIAAAAAA==.Terrorwynd:BAAANQAECgMIAwAAAA==.',
Th='Thellaria:BAAANQAECgEIAQAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAIAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Treala:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECn8WAAIXAAcK8hqAHwDmAQAXAAcK8hqAHwDmAQAAAA==.Truthfully:BAAANQAECgYIDwAAAA==.',
Tt='Ttjpll:BAAANQAECgIIAwAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8dAAIjAAgKFBfPNAA3AgAjAAgKFBfPNAA3AgABNQAFFAUIEQAXAPkdAA==.Unhappytoast:BAACNQAFFH8RAAIXAAUK+R3kAwCoAQAXAAUK+R3kAwCoAQA1AAQKfyIAAhcACQovIzkJAAgDABcACQovIzkJAAgDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8NAAIfAAQKDwv7HQAWAQAfAAQKDwv7HQAWAQA1AAQKfyUAAh8ACQr0F9dlAFoCAB8ACQr0F9dlAFoCAAAA.',
Va='Valeriya:BAAANQADCgQIBAABNQADCgQIBAAIAAAAAA==.Valisanna:BAAANQADCgQICAAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQAECgIIAwAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn8YAAIKAAcK9SLGJwDHAgAKAAcK9SLGJwDHAgAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQADCgcIEwAAAA==.',
Wh='Whiteparrot:BAAANQAECgEIAQAAAA==.Wholy:BAABNQAECn8iAAMKAAkK5RqsKADEAgAKAAkK5RqsKADEAgALAAMKJBKSMgHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgcICgAIAAAAAA==.',
Xa='Xaanii:BAAANQAECgIIAwAAAA==.Xarferrin:BAAANQAECgMIAwAAAA==.',
Xe='Xeeria:BAABNQAECn8gAAMCAAkKkhwNKADCAgACAAkKkhwNKADCAgAZAAMKXxTv3wDSAAAAAA==.Xenzull:BAAANQAECgEIAQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Za='Zadee:BAAANQADCgUIBQAAAA==.Zaralina:BAAANQAECgYIDwAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgQIBAAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAIAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECggIHAADAJQSAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8hAAIMAAgKfxS0bgAyAgAMAAgKfxS0bgAyAgAAAA==.Zomboy:BAAANQADCgMIAwAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgUICgAAAA==.',
Zu='Zu:BAAANQAECgIIAgAAAA==.Zug:BAAANQAECgYIEgAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgIIBAAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAAAAA==.',
['ßl']='ßlue:BAAANQABCgMIBAAAAA==.',
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
