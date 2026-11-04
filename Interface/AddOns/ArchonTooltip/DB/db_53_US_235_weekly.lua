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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Paladin-Retribution','Warlock-Destruction','Evoker-Devastation','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Druid-Restoration','Paladin-Holy','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Warrior-Protection','Warrior-Arms','Druid-Guardian','DeathKnight-Unholy','Mage-Fire','Paladin-Protection','Hunter-Survival','Priest-Shadow','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Feral','Priest-Discipline','Monk-Windwalker','DeathKnight-Blood','Monk-Mistweaver',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAABNQAECn8WAAIBAAkK2hG6WAB/AQABAAkK2hG6WAB/AQAAAA==.Aendrel:BAABNQAECn8qAAICAAoKIB0iEQDmAgACAAoKIB0iEQDmAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8nAAIBAAkKCB9LKQC+AgABAAkKCB9LKQC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECgoKIgADACMVAA==.',
Al='Alejandro:BAAANQAECggICgAAAA==.Alégria:BAAANQAECgcIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8vAAIEAAoKqwVoNQAsAQAEAAoKqwVoNQAsAQAAAA==.Andalaine:BAAANQADCggIFwAAAA==.Angriff:BAAANQAECgEIAQAAAA==.Anraleth:BAABNQAECn87AAIFAAoKKyTrAwCYAwAFAAoKKyTrAwCYAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAABNQAECn8ZAAIGAAoKkBYBswC5AQAGAAoKkBYBswC5AQAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECggIDgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICAAAAA==.',
Av='Averlis:BAABNQAECn8XAAIEAAcKhhASXQBdAQAEAAcKhhASXQBdAQAAAA==.Avoiddance:BAAANQADCgYICgABNQAECgoKIgADACMVAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAABNQAECn8YAAIFAAgKygOwLQDKAAAFAAgKygOwLQDKAAAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bellyroll:BAAANQAECgEIAQAAAA==.Bended:BAABNQAECn81AAMDAAoKzxSfOgD3AQADAAoK3hKfOgD3AQAHAAQKfBZ+MQABAQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAACNQAFFH8FAAIIAAMKTxc8AgDtAAAIAAMKTxc8AgDtAAA1AAQKfx0AAggACgriGnAGABMCAAgACgriGnAGABMCAAE1AAUUBQgJAAQA1xgA.Blueparrot:BAABNQAECn8zAAIJAAoKMQzzTADLAQAJAAoKMQzzTADLAQAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.Bombfaucet:BAAANQADCgEIAQAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQAECgUIEAABNQAECgYIDwAKAAAAAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbletea:BAAANQAECgMIAwABNQAECgoKOwALAEYhAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgYICgAAAA==.Buzzsha:BAAANQAECgMIAQAAAA==.',
Ca='Cahhwa:BAAANQADCgMIAwAAAA==.Camillie:BAAANQADCgIIAgAAAA==.Cassandria:BAABNQAECn8yAAMEAAkKkwq2NQArAQAEAAkKkwq2NQArAQAMAAYKag0jMAAoAQAAAA==.Cassiradra:BAAANQAECgEIAQAAAA==.',
Ce='Cervixticklr:BAAANQAECgcIBwAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8sAAINAAoKQyO0CwBrAwANAAoKQyO0CwBrAwABNQADCgQIBAAKAAAAAA==.Châos:BAABNQAECn8qAAIGAAkKVxFOfwCOAQAGAAkKVxFOfwCOAQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAABNQAECn8nAAILAAkKoxbGUQB7AgALAAkKoxbGUQB7AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFH8XAAIOAAcKHQ2OGAC0AQAOAAcKHQ2OGAC0AQA1AAQKfysAAg4ACgrKHnNBACQCAA4ACgrKHnNBACQCAAAA.Crzzy:BAAANQAECgQIBAAAAA==.Crzzyystabby:BAAANQAECggICgAAAA==.',
Cu='Cultera:BAABNQAECn80AAICAAoKmB8hDAAfAwACAAoKmB8hDAAfAwAAAA==.Cuzon:BAAANQAECgcIEQABNQAFFAIIBgAMAKwYAA==.',
Cy='Cyhyraethia:BAABNQAECn8uAAIPAAkKthsOAwDVAgAPAAkKthsOAwDVAgABNQAFFAQIDwACAGAZAA==.',
Da='Dagden:BAAANQAECgUIBQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAQIBgAQAMoMAA==.Daricepicker:BAABNQAECn87AAILAAoKRiFWGwArAwALAAoKRiFWGwArAwAAAA==.Darkyn:BAABNQAECn8iAAIDAAoKIxV/awAbAgADAAoKIxV/awAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8LAAICAAQKJAMRCgCaAAACAAQKJAMRCgCaAAA1AAQKfyoAAgIACgrtFFwhAEECAAIACgrtFFwhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICQAKAAAAAA==.Deadscar:BAECNQAFFH8QAAIRAAUK3yDeAQAcAQARAAUK3yDeAQAcAQA1AAQKfzwAAhEACgozJeEBADoDABEACgozJeEBADoDAAAA.Deathmasterj:BAAANQADCggIDwAAAA==.Deaths:BAAANQADCgEIAQAAAA==.Delphinium:BAAANQADCgYIDAAAAA==.Dentheaded:BAACNQAFFH8oAAIGAAcKaiQ/AQCyAgAGAAcKaiQ/AQCyAgA1AAQKfzsAAgYACgprJhkIAEsDAAYACgprJhkIAEsDAAAA.',
Di='Diablosucio:BAAANQADCgMIAwAAAA==.Dithariaa:BAAANQAECgQIBAAAAA==.',
Do='Docryktor:BAABNQAECn82AAIRAAkKYBaHEABhAgARAAkKYBaHEABhAgAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAKAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgQIDQAAAA==.Drogas:BAABNQAECn88AAQSAAkK3BT1CwApAgASAAkK3BT1CwApAgAIAAYKsQeYJAAbAQATAAUK3wsDFQDeAAAAAA==.Drtybear:BAAANQAECgQIDwAAAA==.Druithz:BAAANQAECgQIBAABNQAFFAQIBwANACkXAA==.Drussila:BAAANQADCgQIBAABNQAECgcIDAAKAAAAAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECggIBwAAAA==.',
Ed='Ediana:BAABNQAECn8nAAMOAAoKCgfT/wCOAQAOAAoKCgfT/wCOAQAUAAIKcgNzQQBBAAAAAA==.Edisian:BAAANQABCgQIBAAAAA==.',
Ee='Eebz:BAAANQADCggIDAAAAA==.Eebzy:BAABNQAECn8YAAMVAAoK5g+UHQBqAQAVAAkKHRGUHQBqAQAWAAIKZAdeHAEhAAAAAA==.',
El='Elandrah:BAABNQAECn8VAAIJAAcKkgJBsAAGAQAJAAcKkgJBsAAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn9AAAINAAoKLBzPFQDdAgANAAoKLBzPFQDdAgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn8vAAIXAAgKCRLMHQBaAQAXAAgKCRLMHQBaAQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAABNQAECn8cAAIYAAkKbw8aZQB8AQAYAAkKbw8aZQB8AQAAAA==.',
Fa='Fantabulouus:BAABNQAECn8pAAIWAAoKLxEOSgDxAQAWAAoKLxEOSgDxAQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgQIBAAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSOYLQBwAgAEAAgKLSOYLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAABNQAECn8YAAIGAAoKOgmknwBNAQAGAAoKOgmknwBNAQAAAA==.Fugryktor:BAABNQAECn8eAAIPAAcK7BD8CgBIAQAPAAcK7BD8CgBIAQABNQAECgkJNgARAGAWAA==.Fuu:BAAANQABCgMJAwAAAA==.Fuzzywuzzy:BAAANQADCgYIBgAAAA==.',
Fy='Fyre:BAAANQADCgQIBQAAAA==.',
Ga='Gagarazzi:BAAANQADCgMIAwAAAA==.Galandor:BAAANQAECgUIDwAAAA==.Galethia:BAAANQADCgMIAwAAAA==.Gandaalf:BAABNQAECn8uAAQZAAoKsx+MAQAMAgAZAAgK+x+MAQAMAgAUAAQKmxjUGgDNAAAOAAEKAABCqwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAABNQAECn8YAAMHAAoKJQ6PFQDBAQAHAAoKJQ6PFQDBAQADAAMKvQPULgFfAAAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgcILwABNQAECgYIDwAKAAAAAA==.Gityahunter:BAAANQAECgUIEgABNQAECgYIDwAKAAAAAA==.',
Go='Gobanks:BAABNQAECn80AAIaAAoKwh58CAAWAwAaAAoKwh58CAAWAwAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAgIHAAbAOciAA==.Grayresto:BAAANQAECgMIBgAAAA==.Grayson:BAAANQAECgQIDwAAAA==.Graysurv:BAACNQAFFH8cAAIbAAgK5yIDAABjAwAbAAgK5yIDAABjAwA1AAQKfzMAAhsACgr7JmIAAM8DABsACgr7JmIAAM8DAAAA.Grimik:BAABNQAECn8aAAMFAAoK1wmlNgCZAQAFAAkKHgelNgCZAQALAAoKnwgmzQBnAQAAAA==.Grimwali:BAAANQAECgUICgAAAA==.',
Ha='Hallêlujah:BAAANQABCgMIBAAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgkJGAAcAGkhAA==.Hardrock:BAEANQADCgcIEAABNQAECgoKMQAdAEEJAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBwABNQAECgcIDgAKAAAAAA==.',
Hi='Highbrittz:BAAANQADCggICAAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgkJFQADAA4YAA==.Hodgy:BAAANQADCgQIBAAAAA==.',
Hu='Hurtfinger:BAAANQADCgYIEwAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAABNQAECn8gAAMIAAoKQh2/AwCJAgAIAAkKQh2/AwCJAgASAAgKBwx4IwCqAQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAcIFAAeAMIcAA==.Indawhole:BAACNQAFFH8UAAMeAAcKwhzIAwA/AgAeAAYK3h3IAwA/AgACAAEKUBhdDQBZAAA1AAQKfzMABB4ACgpIJQcVAPUCAB4ACQoYJQcVAPUCAAIACgr6HggTAP4BAB8AAQoKE6YmAD8AAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECgoKIgADACMVAA==.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iv='Ivi:BAAANQADCgQIBAAAAA==.',
Iz='Izumiwitabow:BAAANQAECgQIDQAAAA==.',
Ja='Jasmean:BAAANQADCgUIBwAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAABNQAECn8yAAIGAAkKGhTybgCyAQAGAAkKGhTybgCyAQAAAA==.Jaytsukitori:BAACNQAFFH8GAAIMAAIKrBhtDQCYAAAMAAIKrBhtDQCYAAA1AAQKfxoABAwACQrTIA80AHoBAAwABgrlHg80AHoBAAQABgoVE3xjAEABABcAAQoAAN5kACsAAAAA.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECgoKIgADACMVAA==.Jheranton:BAAANQAECgEIAQABNQAECgoKIgADACMVAA==.',
Ji='Jiannae:BAAANQADCgIIAgABNQAECgkJFgABANoRAA==.Jif:BAAANQAECggICwAAAA==.',
Jo='Joesepi:BAABNQAECn8eAAIYAAoKrxg/EQBJAgAYAAoKrxg/EQBJAgAAAA==.Jonah:BAABNQAECn8qAAQHAAoKGSNDAwDWAQAPAAkKrx71BACAAgADAAgK1h5xUwBbAgAHAAgKaSBDAwDWAQABNQAECgoKKAAYAFUkAA==.Joodee:BAABNQAECn8eAAIBAAcKShF2ZgBPAQABAAcKShF2ZgBPAQAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgoKMQAMAAAlAA==.',
Ka='Kackarot:BAABNQAECn8nAAIdAAkK/RLGUQAyAgAdAAkK/RLGUQAyAgAAAA==.Kartelz:BAABNQAECn8bAAIeAAgKNgbkUwBBAQAeAAgKNgbkUwBBAQAAAA==.Katrine:BAABNQAECn8yAAIgAAoKQxdNKgBIAgAgAAoKQxdNKgBIAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8TAAMUAAYKbRzgAAA7AQAUAAQK7hfgAAA7AQAOAAMKpRrvNwBdAAA1AAQKfzUAAxQACgodI3cGACQCAA4ACgpQIC1RAN4CABQABwreHncGACQCAAAA.Kilrah:BAABNQAECn8qAAIeAAoK9AmqQgCtAQAeAAoK9AmqQgCtAQAAAA==.Kissmycrits:BAABNQAECn8mAAILAAYKhhUIqwAYAQALAAYKhhUIqwAYAQAAAA==.Kissmywrath:BAAANQAECgUIDgAAAA==.Kiyoine:BAABNQAECn8mAAIhAAgKIg+/EgBPAQAhAAgKIg+/EgBPAQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgYICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8uAAIMAAkKkBMwGwDhAQAMAAkKkBMwGwDhAQAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAKAAAAAA==.Laetha:BAAANQADCggIDgABNQAECggIHwAIAKETAA==.Larriat:BAAANQADCgcICAAAAA==.Layonscoob:BAAANQAECgYIBwAAAA==.',
Le='Leefs:BAAANQAECgYIBQABNQAECgcIDgAKAAAAAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn9BAAIQAAoKxQnRHQDkAQAQAAoKxQnRHQDkAQAAAA==.Linthe:BAABNQAECn8kAAMNAAoKMg6sagDXAQANAAoKMg6sagDXAQAGAAEKdwagrgEwAAAAAA==.Lit:BAABNQAECn8eAAMNAAkKSQpVaQBIAQANAAkKSQpVaQBIAQAGAAEKAAAaqwEyAAAAAA==.Lites:BAAANQAECgcIDgAAAA==.Lithica:BAAANQAECgEIAQAAAA==.Littledog:BAACNQAFFH8GAAIJAAUKrgy8EABeAQAJAAUKrgy8EABeAQA1AAQKfx8ABBwACQqlEMs/ADABABwABgphEcs/ADABACIABgpdEIAQACEBAAkABAqaFEmKAAEBAAAA.',
Lo='Lockdout:BAAANQADCgIIAgABNQAECgcIDgAKAAAAAA==.Lokiantonio:BAAANQADCgQIBAAAAA==.Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8pAAIGAAgKJRhPiAAWAgAGAAgKJRhPiAAWAgAAAA==.',
Lu='Luckevin:BAAANQAECggICAAAAA==.Lumi:BAAANQAECgIIBAAAAA==.Lurashtai:BAAANQAECggIDAAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Magicmann:BAAANQADCgUIBwAAAA==.Magicor:BAAANQADCggICAAAAA==.Malafang:BAAANQAECgMIBgAAAA==.Malanah:BAAANQAECgQICwAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Maverick:BAACNQAFFH8GAAIQAAQKygz4CQBCAQAQAAQKygz4CQBCAQA1AAQKfywAAhAACgpFIMEGABMDABAACgpFIMEGABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAABNQAECn8YAAIUAAkKcQ10EwBxAQAUAAkKcQ10EwBxAQAAAA==.',
Mk='Mk:BAEANQAECgUIBgABNQAECgoKNAAjACEfAA==.',
Mo='Mogar:BAABNQAECn8YAAIWAAkKIQvlyQBjAQAWAAkKIQvlyQBjAQAAAA==.Moogician:BAAANQAECgUIBAAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgEIAgAAAA==.Mordread:BAAANQAECgQIBQAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8OAAILAAYKhBVmAwCjAQALAAYKhBVmAwCjAQA1AAQKfykAAwsACgpgIvMiAAsDAAsACgpgIvMiAAsDAAUACArsDig2AJ0BAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFH8fAAMPAAgKHx1aAAAjAgAPAAcKVx9aAAAjAgADAAYKYhniCgC9AQA1AAQKfz4AAw8ACgphJfoAAGwDAA8ACgqoJPoAAGwDAAMACAp6I1ceAHcCAAE1AAQKCQkYABwAaSEA.',
Ni='Nivmizzet:BAABNQAECn9HAAMDAAoKGh6JFQCsAgADAAoK1x2JFQCsAgAHAAIKGBtISwCeAAAAAA==.',
No='Nolakai:BAAANQAECgQIBAAAAA==.Nonliving:BAAANQADCgYIBgAAAA==.Novagosa:BAAANQAECgUICwABNQAECgoKOQABADMlAA==.Novalea:BAABNQAECn85AAMBAAoKMyUVBQCyAwABAAoKMyUVBQCyAwAdAAMKMw3bsQBzAAAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBQABNQAECgcIIwAYAD4PAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQAECgQIBAAAAA==.',
Pa='Palomar:BAAANQAECgQICgAAAA==.Paraggonn:BAABNQAECn8bAAILAAcK8xJ/gwBpAQALAAcK8xJ/gwBpAQAAAA==.',
Ph='Pherkle:BAAANQAECgQICgABNQAECgkJNgARAGAWAA==.Phuriosa:BAAANQAECgIIAgABNQAECgoKHgAMACkSAA==.Phury:BAABNQAECn8eAAIMAAoKKRJiKADdAQAMAAoKKRJiKADdAQAAAA==.Physinyx:BAABNQAECn89AAMdAAoKOROYNQDGAQAdAAoKOROYNQDGAQABAAgKmwAn8gCGAAAAAA==.',
Pi='Pizza:BAAANQAECgQIBAAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAABNQAECn8dAAIkAAoKzRZgIADLAQAkAAoKzRZgIADLAQAAAA==.',
Pr='Preparedrice:BAAANQAECgQIBQABNQAECgoKOwALAEYhAA==.',
Pu='Pumbaa:BAAANQAECgIIAgABNQAECgcJBwAKAAAAAA==.Purpleparrot:BAAANQADCggICAAAAA==.',
Qu='Quilby:BAAANQADCgUICgAAAA==.',
Ra='Raenyx:BAABNQAECn8sAAMDAAoKygwgowCPAQADAAoKygwgowCPAQAHAAEKAADNhwAeAAABNQAECgoKPQAdADkTAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAABNQAECn8mAAIZAAcKXxB1AwA1AQAZAAcKXxB1AwA1AQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEBNQAECn8aAAIDAAoK/wkRwgBHAQADAAoK/wkRwgBHAQAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8eAAIlAAkKfg8dFQBxAQAlAAkKfg8dFQBxAQAAAA==.Reynarena:BAAANQAECgEIAgAAAA==.',
Rh='Rhaenfyre:BAACNQAFFH8HAAMCAAQKyQ7ABwDRAAACAAQKyQ7ABwDRAAAeAAEKkA1PFwBCAAA1AAQKfzcAAwIACgoDHxcLAIECAAIACgoDHxcLAIECAB4AAwrMFSxZAIsAAAAA.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAQIBgAQAMoMAA==.Rivenel:BAACNQAFFH8QAAMHAAUKORGRAwClAAAHAAIKIRWRAwClAAADAAMKUA1DIACTAAA1AAQKfzYAAwcACgqGH9oFALQCAAcACAomH9oFALQCAAMACAqhHLxbAEQCAAAA.',
Ro='Robinvoid:BAABNQAECn8aAAMCAAoKThtBFgCwAgACAAoKThtBFgCwAgAeAAEK3wsNkwA1AAAAAA==.Rodel:BAAANQAECgMIBwAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn8oAAIgAAgKchFqOACBAQAgAAgKchFqOACBAQAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAQIBgAQAMoMAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgcIDgAAAA==.Rundas:BAAANQAECgcIDAAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAABNQAECn8rAAIcAAkKVg//GwB2AQAcAAkKVg//GwB2AQAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEQAAAA==.Saddie:BAAANQADCgYICwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQAECgQIDwAAAA==.Sanasath:BAABNQAECn8XAAMSAAgKvw4NLgAxAQASAAcKTw4NLgAxAQAIAAYKkQ56FQCyAAAAAA==.',
Sc='Scrumbles:BAAANQAECgUIBQAAAA==.',
Se='Sealgair:BAAANQADCgYIBgAAAA==.Segador:BAAANQAECgYICAAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAKAAAAAA==.',
Sh='Shamanizim:BAACNQAFFH8OAAIdAAQKohszDADxAAAdAAQKohszDADxAAA1AAQKf0gAAh0ACgptI5oQAGgDAB0ACgptI5oQAGgDAAAA.Shamanka:BAAANQADCgIIAgAAAA==.Sheetara:BAAANQAECgQIBAAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEwABNQAECgoKOgAWAPEQAA==.Shinotenshi:BAAANQAECgUIDQABNQAECgoKOgAWAPEQAA==.Shugarae:BAABNQAECn8fAAIEAAgK7wTxPAAFAQAEAAgK7wTxPAAFAQAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgQIBAAAAA==.',
Sl='Slashemup:BAABNQAECn8UAAIeAAgKCBFVPQDOAQAeAAgKCBFVPQDOAQAAAA==.Slayter:BAABNQAECn8xAAIMAAoKACX6BQBjAwAMAAoKACX6BQBjAwAAAA==.',
Sm='Smaugor:BAAANQAECgYIEQABNQAECgcJBwAKAAAAAA==.',
So='Soju:BAAANQAECggIDAABNQAECgoKOwALAEYhAA==.Solder:BAAANQAECgEIAQAAAA==.Soliloquy:BAABNQAECn8xAAMcAAoK6xN/FADbAQAcAAoK6xN/FADbAQAiAAUKiBEzDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn88AAIDAAoKix+ZDgDdAgADAAoKix+ZDgDdAgAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgoKPAADAIsfAA==.',
St='Stare:BAEANQAECgEIAQABNQAFFAUIEAARAN8gAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIFgAKAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAKAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAAANQAECgQIDwAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgIIAQAAAA==.',
Ta='Tardovski:BAAANQAECgYIDAAAAA==.Taze:BAABNQAECn8VAAQGAAoKghimQgAvAgAGAAkKghimQgAvAgANAAQK4xUW9gCTAAAaAAEKAACEagA9AAAAAA==.',
Te='Teneturadvos:BAAANQAECgIIAgABNQAECggIBwAKAAAAAA==.Terrorwynd:BAAANQAECgUICgAAAA==.Tezan:BAAANQADCgUIBQAAAA==.',
Th='Thellaria:BAAANQAECgEIAQAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQIBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAKAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Trañsformer:BAAANQAECgEIAgAAAA==.Treala:BAAANQADCgUICQABNQAECgQICwAKAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECn8cAAIaAAcK8hoBIADlAQAaAAcK8hoBIADlAQABNQAECggIFwASAL8OAA==.Truthfully:BAABNQAECn8cAAIGAAkKBQoV3gBfAQAGAAkKBQoV3gBfAQAAAA==.',
Tt='Ttjpll:BAAANQAECgUICQAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8mAAIkAAkKLhdlNQA2AgAkAAkKLhdlNQA2AgABNQAFFAcIFwAaAPYcAA==.Unhappytoast:BAACNQAFFH8XAAIaAAcK9hxlAQCqAQAaAAcK9hxlAQCqAQA1AAQKfycAAhoACgqWI2IJAAcDABoACgqWI2IJAAcDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8OAAIWAAQKDwuvHgAWAQAWAAQKDwuvHgAWAQA1AAQKfykAAhYACgqzFuFmAFsCABYACgqzFuFmAFsCAAAA.',
Va='Valeriya:BAAANQADCgYICgABNQAECgMIBwAKAAAAAA==.Valisanna:BAAANQADCgYIDgAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQAECgUIDwAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn8vAAINAAgKtyPLDQAxAwANAAgKtyPLDQAxAwAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQAECgEIAQAAAA==.',
Wh='Whiteparrot:BAAANQAECgQIBAAAAA==.Wholy:BAABNQAECn8zAAMNAAoKsB58FwDPAgANAAoKsB58FwDPAgAGAAQK5hJxNwHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgkJGAAcAGkhAA==.',
Wr='Wreckxneffec:BAAANQAECggICQAAAA==.',
Xa='Xaanii:BAAANQAECgQIDgAAAA==.Xarferrin:BAAANQAECgMIAwAAAA==.',
Xe='Xeeria:BAACNQAFFH8KAAMBAAUK0hAYDABWAQABAAUK0hAYDABWAQAdAAEKtgEaMwBDAAA1AAQKfy0AAwEACgpGHJgoAMECAAEACgpGHJgoAMECAB0AAwpfFMviANEAAAAA.Xenzull:BAAANQAECgEIAQAAAA==.',
Xh='Xhardcore:BAAANQADCgYIBQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Yu='Yuni:BAAANQADCgEIAQAAAA==.',
Za='Zadee:BAAANQADCgUIBQAAAA==.Zaralina:BAABNQAECn8aAAIcAAoK8QryJAAgAQAcAAoK8QryJAAgAQAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgUIBQAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenagosa:BAAANQABCgIIAgAAAA==.Zenzhu:BAAANQAECgQIBwAAAA==.Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAKAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECgoKIgADACMVAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8rAAILAAgKshRLcAAxAgALAAgKshRLcAAxAgAAAA==.Zomboy:BAAANQAECgEIAQAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgcICwAAAA==.',
Zu='Zu:BAAANQAECgUIBgAAAA==.Zug:BAABNQAECn8hAAILAAoKixgVZwCuAQALAAoKixgVZwCuAQAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgMIBAAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAABNQAECggICQAKAAAAAA==.',
['ßl']='ßlue:BAAANQAECgUIDQAAAA==.',
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
