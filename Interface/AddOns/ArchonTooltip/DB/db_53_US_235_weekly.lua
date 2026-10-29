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

local lookup = {'DemonHunter-Devourer','Shaman-Restoration','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Paladin-Retribution','Warlock-Destruction','Evoker-Devastation','Priest-Holy','Unknown-Unknown','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Druid-Guardian','DeathKnight-Unholy','Warrior-Arms','Mage-Fire','Paladin-Protection','Hunter-Survival','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Feral','Priest-Shadow','Priest-Discipline','Monk-Windwalker','DeathKnight-Blood','Monk-Mistweaver',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAAANQAECggIEwAAAA==.Aendrel:BAABNQAECn8iAAIBAAoKZhwiEQDmAgABAAoKZhwiEQDmAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8kAAICAAkKCB9LKQC+AgACAAkKCB9LKQC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECgoKIgADACMVAA==.',
Al='Alejandro:BAAANQAECgcICgAAAA==.Alégria:BAAANQAECgcIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8lAAIEAAgKNwXsYQBHAQAEAAgKNwXsYQBHAQAAAA==.Andalaine:BAAANQADCggIFwAAAA==.Angriff:BAAANQAECgEIAQAAAA==.Anraleth:BAABNQAECn83AAIFAAoKyCPrAwCYAwAFAAoKyCPrAwCYAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAABNQAECn8WAAIGAAkKehUBswC5AQAGAAkKehUBswC5AQAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECggIDgAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICAAAAA==.',
Av='Averlis:BAAANQAECgUIDgAAAA==.Avoiddance:BAAANQADCgYICgABNQAECgoKIgADACMVAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAABNQAECn8YAAIFAAgKygOuJADZAAAFAAgKygOuJADZAAAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAABNQAECn8xAAMDAAoKohThKAAQAgADAAoKsRLhKAAQAgAHAAQKfBZ+MQABAQAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAABNQAECn8WAAIIAAkKVBoMDgB/AgAIAAkKVBoMDgB/AgABNQAFFAUICQAEANcYAA==.Blueparrot:BAABNQAECn8rAAIJAAoKGQwdOwDKAQAJAAoKGQwdOwDKAQAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.Bombfaucet:BAAANQADCgEIAQAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQAECgQICwABNQAECgUICgAKAAAAAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgYICgAAAA==.',
Ca='Cahhwa:BAAANQADCgMIAwAAAA==.Camillie:BAAANQADCgIIAgAAAA==.Cassandria:BAABNQAECn8pAAMLAAkK1BErJQA0AQALAAYKag0rJQA0AQAEAAgKpAkvNwDtAAAAAA==.Cassiradra:BAAANQADCgUIBQAAAA==.',
Ce='Cervixticklr:BAAANQADCggIHAAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8sAAIMAAoKQyO0CwBrAwAMAAoKQyO0CwBrAwABNQADCgQIBAAKAAAAAA==.Châos:BAABNQAECn8nAAIGAAkK/g9gawB/AQAGAAkK/g9gawB/AQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAABNQAECn8kAAINAAkKoxbGUQB7AgANAAkKoxbGUQB7AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFH8XAAIOAAcKHQ2OGAC0AQAOAAcKHQ2OGAC0AQA1AAQKfycAAg4ACgpzHpc0AB8CAA4ACgpzHpc0AB8CAAAA.Crzzy:BAAANQAECgQIBAAAAA==.Crzzyystabby:BAAANQAECggIAgAAAA==.',
Cu='Cultera:BAABNQAECn8wAAIBAAoKdh8hDAAfAwABAAoKdh8hDAAfAwAAAA==.Cuzon:BAAANQAECgcIEQABNQAECgkJFwALANMgAA==.',
Cy='Cyhyraethia:BAABNQAECn8nAAIPAAkK0hoOAwDVAgAPAAkK0hoOAwDVAgABNQAFFAQIDAABAB8UAA==.',
Da='Dagden:BAAANQAECgEIAQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAQIBgAQAMoMAA==.Daricepicker:BAABNQAECn8yAAINAAoKWSBWGwArAwANAAoKWSBWGwArAwAAAA==.Darkyn:BAABNQAECn8iAAIDAAoKIxV/awAbAgADAAoKIxV/awAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8KAAIBAAMK8AN+CgBnAAABAAMK8AN+CgBnAAA1AAQKfyoAAgEACgrtFFwhAEECAAEACgrtFFwhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICQAKAAAAAA==.Deadscar:BAECNQAFFH8MAAIRAAUK3yA4AQAmAQARAAUK3yA4AQAmAQA1AAQKfzgAAhEACgoXJIUBAC4DABEACgoXJIUBAC4DAAAA.Deathmasterj:BAAANQADCggIDwAAAA==.Deaths:BAAANQADCgEIAQAAAA==.Delphinium:BAAANQADCgUICwAAAA==.Dentheaded:BAACNQAFFH8oAAIGAAcKaiQ/AQCyAgAGAAcKaiQ/AQCyAgA1AAQKfzYAAgYACgprJnQEAF4DAAYACgprJnQEAF4DAAAA.',
Di='Diablosucio:BAAANQADCgMIAwAAAA==.Dithariaa:BAAANQAECgQIBAAAAA==.',
Do='Docryktor:BAABNQAECn8zAAIRAAkKYBaHEABhAgARAAkKYBaHEABhAgAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAKAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgQICQAAAA==.Drogas:BAABNQAECn85AAQSAAkK3BTLCAAxAgASAAkK3BTLCAAxAgAIAAYKsQeYJAAbAQATAAUK3wsDFQDeAAAAAA==.Drtybear:BAAANQAECgUICwAAAA==.Druithz:BAAANQAECgQIBAABNQAFFAQIBwAMACkXAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECggIBwAAAA==.',
Ed='Ediana:BAABNQAECn8jAAMOAAoK6AbT/wCOAQAOAAoK6AbT/wCOAQAUAAIKcgNzQQBBAAAAAA==.Edisian:BAAANQABCgQIBAAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECggIEgAAAA==.',
El='Elandrah:BAABNQAECn8VAAIJAAcKkgJBsAAGAQAJAAcKkgJBsAAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn82AAIMAAkKJxw2FQCbAgAMAAkKJxw2FQCbAgAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn8nAAIVAAgKvBGqGQA+AQAVAAgKvBGqGQA+AQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAABNQAECn8aAAIWAAgKdg8aZQB8AQAWAAgKdg8aZQB8AQAAAA==.',
Fa='Fantabulouus:BAABNQAECn8iAAIXAAoK+w+FPQDaAQAXAAoK+w+FPQDaAQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgQIBAAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSOYLQBwAgAEAAgKLSOYLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAAANQAECggIDAAAAA==.Fugryktor:BAAANQAECgUIEgABNQAECgkJMwARAGAWAA==.Fuu:BAAANQABCgMJAwAAAA==.Fuzzywuzzy:BAAANQADCgYIBgAAAA==.',
Fy='Fyre:BAAANQADCgQIBQAAAA==.',
Ga='Gagarazzi:BAAANQADCgMIAwAAAA==.Galandor:BAAANQAECgQICwAAAA==.Galethia:BAAANQADCgMIAwAAAA==.Gandaalf:BAABNQAECn8mAAQYAAoKNxwIAQAAAgAYAAgKKx4IAQAAAgAUAAQK0BTQJADIAAAOAAEKAABCqwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAABNQAECn8WAAMHAAoKJQ6PFQDBAQAHAAoKJQ6PFQDBAQADAAMKvQPULgFfAAAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIKQABNQAECgUICgAKAAAAAA==.Gityahunter:BAAANQAECgQIDQABNQAECgUICgAKAAAAAA==.',
Go='Gobanks:BAABNQAECn80AAIZAAoKwh58CAAWAwAZAAoKwh58CAAWAwAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAgIHAAaAOciAA==.Grayresto:BAAANQABCgQIBAAAAA==.Grayson:BAAANQAECgUICwAAAA==.Graysurv:BAACNQAFFH8cAAIaAAgK5yIDAABjAwAaAAgK5yIDAABjAwA1AAQKfzAAAhoACgr7JmIAAM8DABoACgr7JmIAAM8DAAAA.Grimik:BAABNQAECn8aAAMFAAoK1wmlNgCZAQAFAAkKHgelNgCZAQANAAoKnwgmzQBnAQAAAA==.Grimwali:BAAANQAECgUICgAAAA==.',
Ha='Hallêlujah:BAAANQABCgMIBAAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgcIEAAKAAAAAA==.Hardrock:BAEANQADCgcIEAABNQAECgoKKgAbAEEJAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBgABNQAECgYIDQAKAAAAAA==.',
Hi='Highbrittz:BAAANQADCggICAAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgYIEAAKAAAAAA==.Hodgy:BAAANQADCgQIBAAAAA==.',
Hu='Hurtfinger:BAAANQADCgYICgAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAABNQAECn8fAAMIAAoK8By8AgCRAgAIAAkK8By8AgCRAgASAAgKBwx4IwCqAQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAcIFAAcAMIcAA==.Indawhole:BAACNQAFFH8UAAMcAAcKwhzIAwA/AgAcAAYK3h3IAwA/AgABAAEKUBgHCwBeAAA1AAQKfzAABBwACgokJQcVAPUCABwACQoYJQcVAPUCAAEACArXIG0fAFQCAB0AAQoKExYgAEIAAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECgoKIgADACMVAA==.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQAECgUICQAAAA==.',
Ja='Jasmean:BAAANQADCgUIBwAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAABNQAECn8pAAIGAAkKphNqWQCrAQAGAAkKphNqWQCrAQAAAA==.Jaytsukitori:BAABNQAECn8XAAQLAAkK0yAPNAB6AQALAAYK5R4PNAB6AQAEAAYKFRN8YwBAAQAVAAEKAADeZAArAAAAAA==.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECgoKIgADACMVAA==.Jheranton:BAAANQADCgYICgABNQAECgoKIgADACMVAA==.',
Ji='Jiannae:BAAANQADCgIIAgABNQAECggIEwAKAAAAAA==.Jif:BAAANQAECgUIBQAAAA==.',
Jo='Joesepi:BAABNQAECn8WAAIWAAoK/xVOEAAcAgAWAAoK/xVOEAAcAgAAAA==.Jonah:BAABNQAECn8oAAQPAAoKjyL1BACAAgAPAAkKrx71BACAAgADAAgK1h5xUwBbAgAHAAYKBh/ZBgAQAQABNQAECgoKJQAWAE0kAA==.Joodee:BAABNQAECn8YAAICAAcKHxE/TwBZAQACAAcKHxE/TwBZAQAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgoKMAALAAAlAA==.',
Ka='Kackarot:BAABNQAECn8nAAIbAAkK/RLGUQAyAgAbAAkK/RLGUQAyAgAAAA==.Kartelz:BAABNQAECn8ZAAIcAAgKMwbkUwBBAQAcAAgKMwbkUwBBAQAAAA==.Katrine:BAABNQAECn8sAAIeAAoKdRZNKgBIAgAeAAoKdRZNKgBIAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8SAAMUAAUKoxr3AQDcAAAUAAMKDRT3AQDcAAAOAAMKpRoaLgBjAAA1AAQKfy0AAw4ACgptIC1RAN4CAA4ACgooHy1RAN4CABQABwpGGkIJAIMBAAAA.Kilrah:BAABNQAECn8qAAIcAAoK9AmqQgCtAQAcAAoK9AmqQgCtAQAAAA==.Kissmycrits:BAABNQAECn8iAAINAAYKhhV91ABXAQANAAYKhhV91ABXAQAAAA==.Kissmywrath:BAAANQAECgUICwAAAA==.Kiyoine:BAABNQAECn8kAAIfAAgK4w6qDABnAQAfAAgK4w6qDABnAQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8sAAILAAkKkBPtEgD4AQALAAkKkBPtEgD4AQAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAKAAAAAA==.Laetha:BAAANQADCggIDgABNQAECggIHwAIAKETAA==.Larriat:BAAANQADCgcICAAAAA==.Layonscoob:BAAANQAECgIIAgAAAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn85AAIQAAoK8wjRHQDkAQAQAAoK8wjRHQDkAQAAAA==.Linthe:BAABNQAECn8kAAMMAAoKMg6sagDXAQAMAAoKMg6sagDXAQAGAAEKdwagrgEwAAAAAA==.Lit:BAAANQAECgYIDwAAAA==.Lites:BAAANQAECgYIDAAAAA==.Lithica:BAAANQAECgEIAQAAAA==.Littledog:BAACNQAFFH8GAAIJAAUKrgyKDABjAQAJAAUKrgyKDABjAQA1AAQKfxoABCAACQqlEMs/ADABACAABgphEcs/ADABACEABgpLDoAQACEBAAkABAqaFMRvAAcBAAAA.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8nAAIGAAgKARhPiAAWAgAGAAgKARhPiAAWAgAAAA==.',
Lu='Luckevin:BAAANQAECgUIBwAAAA==.Lumi:BAAANQAECgIIBAAAAA==.Lurashtai:BAAANQAECgUICwAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Magicmann:BAAANQADCgUIBwAAAA==.Magicor:BAAANQADCggICAAAAA==.Malafang:BAAANQAECgMIBgAAAA==.Malanah:BAAANQAECgUIBwAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Maverick:BAACNQAFFH8GAAIQAAQKygz4CQBCAQAQAAQKygz4CQBCAQA1AAQKfywAAhAACgpFIMEGABMDABAACgpFIMEGABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgcIDwAAAA==.',
Mk='Mk:BAEANQAECgUIBgABNQAECgkJMAAiAFYeAA==.',
Mo='Mogar:BAABNQAECn8XAAIXAAgKLAzlyQBjAQAXAAgKLAzlyQBjAQAAAA==.Moogician:BAAANQAECgUIBAAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgEIAgAAAA==.Mordread:BAAANQAECgIIAwAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8NAAINAAUKBxmiBABZAQANAAUKBxmiBABZAQA1AAQKfykAAw0ACgpgIvMiAAsDAA0ACgpgIvMiAAsDAAUACArsDig2AJ0BAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFH8fAAMPAAgKHx1aAAAjAgAPAAcKVx9aAAAjAgADAAYKYhniCgC9AQA1AAQKfzoAAw8ACgoHJfoAAGwDAA8ACgqoJPoAAGwDAAMACAoTI4kVAH8CAAE1AAQKBwgQAAoAAAAA.',
Ni='Nivmizzet:BAABNQAECn88AAMDAAoKWB1uDwCuAgADAAoKFh1uDwCuAgAHAAIKGBtISwCeAAAAAA==.',
No='Nolakai:BAAANQAECgQIBAAAAA==.Nonliving:BAAANQADCgYIBgAAAA==.Novagosa:BAAANQAECgUICwABNQAECgoKMgACAPMkAA==.Novalea:BAABNQAECn8yAAMCAAoK8yRkAwC0AwACAAoK8yRkAwC0AwAbAAEKNwx8vAA7AAAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBQABNQAECgcIGwAWANUOAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ou='Outforarip:BAAANQADCgIIAgAAAA==.',
Ox='Oxxo:BAAANQAECgQIBAAAAA==.',
Pa='Palomar:BAAANQAECgQICAAAAA==.Paraggonn:BAAANQAECgUIEAAAAA==.',
Ph='Pherkle:BAAANQAECgQICAABNQAECgkJMwARAGAWAA==.Phuriosa:BAAANQAECgIIAgABNQAECgoKHgALACkSAA==.Phury:BAABNQAECn8eAAILAAoKKRJiKADdAQALAAoKKRJiKADdAQAAAA==.Physinyx:BAABNQAECn84AAMbAAoKxRIQKADFAQAbAAoKxRIQKADFAQACAAgKmwAn8gCGAAAAAA==.',
Pi='Pizza:BAAANQAECgQIBAAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAABNQAECn8cAAIjAAoKdxZEGADYAQAjAAoKdxZEGADYAQAAAA==.',
Pr='Preparedrice:BAAANQAECgEIAQABNQAECgoKMgANAFkgAA==.',
Pu='Pumbaa:BAAANQAECgIIAgABNQAECgcJBwAKAAAAAA==.',
Qu='Quilby:BAAANQADCgUICgAAAA==.',
Ra='Raenyx:BAABNQAECn8sAAMDAAoKygwgowCPAQADAAoKygwgowCPAQAHAAEKAADNhwAeAAABNQAECgoKOAAbAMUSAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAABNQAECn8gAAIYAAcKag5dBABoAQAYAAcKag5dBABoAQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEBNQAECn8XAAIDAAoKsAgRwgBHAQADAAoKsAgRwgBHAQAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8XAAIkAAgKcw5iHwCWAQAkAAgKcw5iHwCWAQAAAA==.Reynarena:BAAANQADCggICwAAAA==.',
Rh='Rhaenfyre:BAACNQAFFH8GAAMBAAMKyQ4jBgDYAAABAAMKyQ4jBgDYAAAcAAEKkA1lEwBCAAA1AAQKfzMAAwEACgq1HIcJAGQCAAEACgq1HIcJAGQCABwAAwrMFQ1NAJIAAAAA.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAQIBgAQAMoMAA==.Rivenel:BAACNQAFFH8LAAMHAAQKYg6CBACVAAAHAAIKzgyCBACVAAADAAIKiRGvKABHAAA1AAQKfzUAAwcACgrrHtoFALQCAAcACAomH9oFALQCAAMACArTG7xbAEQCAAAA.',
Ro='Robinvoid:BAABNQAECn8aAAMBAAoKThtBFgCwAgABAAoKThtBFgCwAgAcAAEK3wsNkwA1AAAAAA==.Rodel:BAAANQAECgQIBQAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn8mAAIeAAgKchE6KQCMAQAeAAgKchE6KQCMAQAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAQIBgAQAMoMAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgYIDQAAAA==.Rundas:BAAANQAECgYIDAAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAABNQAECn8lAAIgAAkKVg8fFQB8AQAgAAkKVg8fFQB8AQAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEQAAAA==.Saddie:BAAANQADCgYICwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQAECgUICwAAAA==.Sanasath:BAABNQAECn8VAAMSAAcKTw4NLgAxAQASAAcKTw4NLgAxAQAIAAQKahCPKQDeAAABNQAECgcIFgAZAPIaAA==.',
Se='Sealgair:BAAANQADCgUIBQAAAA==.Segador:BAAANQAECgUICAAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAKAAAAAA==.',
Sh='Shamanizim:BAACNQAFFH8LAAIbAAQKZxg1CgDlAAAbAAQKZxg1CgDlAAA1AAQKf0MAAhsACgptIwQIAAEDABsACgptIwQIAAEDAAAA.Shamanka:BAAANQADCgIIAgAAAA==.Sheetara:BAAANQAECgQIBAAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEwABNQAECgoKNwAXADMQAA==.Shinotenshi:BAAANQAECgQICwABNQAECgoKNwAXADMQAA==.Shugarae:BAABNQAECn8XAAIEAAgKjQRaMwACAQAEAAgKjQRaMwACAQAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgQIBAAAAA==.',
Sl='Slashemup:BAABNQAECn8UAAIcAAgKCBFVPQDOAQAcAAgKCBFVPQDOAQAAAA==.Slayter:BAABNQAECn8wAAILAAoKACVCAwB4AwALAAoKACVCAwB4AwAAAA==.',
Sm='Smaugor:BAAANQAECgYIEQABNQAECgcJBwAKAAAAAA==.',
So='Soju:BAAANQAECgcIDAABNQAECgoKMgANAFkgAA==.Solder:BAAANQAECgEIAQAAAA==.Soliloquy:BAABNQAECn8rAAMgAAoKjRLgEAC/AQAgAAoKjRLgEAC/AQAhAAUKiBEzDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn8zAAIDAAoK0hu3GAAlAwADAAoK0hu3GAAlAwAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgoKMwADANIbAA==.',
St='Stare:BAEANQAECgEIAQABNQAFFAUIDAARAN8gAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIFgAKAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAKAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAAANQAECgUICwAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgUIDAAAAA==.Taze:BAAANQAECggIDAAAAA==.',
Te='Teneturadvos:BAAANQAECgIIAgABNQAECggIBwAKAAAAAA==.Terrorwynd:BAAANQAECgUICgAAAA==.',
Th='Thellaria:BAAANQAECgEIAQAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAKAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Treala:BAAANQADCgUICQABNQAECgUIBwAKAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECn8WAAIZAAcK8hoBIADlAQAZAAcK8hoBIADlAQAAAA==.Truthfully:BAABNQAECn8VAAIGAAkKwwkV3gBfAQAGAAkKwwkV3gBfAQAAAA==.',
Tt='Ttjpll:BAAANQAECgUICQAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8jAAIjAAkK1BZlNQA2AgAjAAkK1BZlNQA2AgABNQAFFAYIFgAZAIAcAA==.Unhappytoast:BAACNQAFFH8WAAIZAAYKgByaAQBbAQAZAAYKgByaAQBbAQA1AAQKfyYAAhkACgqWI2IJAAcDABkACgqWI2IJAAcDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8OAAIXAAQKDwuvHgAWAQAXAAQKDwuvHgAWAQA1AAQKfykAAhcACgqzFuFmAFsCABcACgqzFuFmAFsCAAAA.',
Va='Valeriya:BAAANQADCgUICQABNQAECgQIBQAKAAAAAA==.Valisanna:BAAANQADCgUIDQAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQAECgUICwAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn8nAAIMAAgKtyOlCAA/AwAMAAgKtyOlCAA/AwAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
['Và']='Vàli:BAAANQADCggIFwAAAA==.',
Wh='Whiteparrot:BAAANQAECgQIBAAAAA==.Wholy:BAABNQAECn8sAAMMAAoKTh4oKQDDAgAMAAoKTh4oKQDDAgAGAAQK5hJxNwHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgcIEAAKAAAAAA==.',
Wr='Wreckxneffec:BAAANQAECggICQAAAA==.',
Xa='Xaanii:BAAANQAECgUICgAAAA==.Xarferrin:BAAANQAECgMIAwAAAA==.',
Xe='Xeeria:BAACNQAFFH8KAAMCAAUK0hDYCABiAQACAAUK0hDYCABiAQAbAAEKtgEaMwBDAAA1AAQKfygAAwIACgpGHJgoAMECAAIACgpGHJgoAMECABsAAwpfFMviANEAAAAA.Xenzull:BAAANQAECgEIAQAAAA==.',
Xh='Xhardcore:BAAANQADCgYIBQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Yu='Yuni:BAAANQADCgEIAQAAAA==.',
Za='Zadee:BAAANQADCgUIBQAAAA==.Zaralina:BAAANQAECgYIDwAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgUIBQAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenagosa:BAAANQABCgIIAgAAAA==.Zenzhu:BAAANQAECgQIBwAAAA==.Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAKAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECgoKIgADACMVAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8pAAINAAgKshQHWACVAQANAAgKshQHWACVAQAAAA==.Zomboy:BAAANQAECgEIAQAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgYICwAAAA==.',
Zu='Zu:BAAANQAECgUIBgAAAA==.Zug:BAABNQAECn8dAAINAAoKFha8TgCwAQANAAoKFha8TgCwAQAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgMIBAAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAABNQAECggICQAKAAAAAA==.',
['ßl']='ßlue:BAAANQAECgQIBAAAAA==.',
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
