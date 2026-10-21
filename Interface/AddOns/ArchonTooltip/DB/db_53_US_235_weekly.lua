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

local lookup = {'DemonHunter-Devourer','Shaman-Restoration','Warlock-Demonology','Druid-Balance','Hunter-Marksmanship','Warlock-Destruction','Priest-Holy','Unknown-Unknown','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Guardian','DeathKnight-Unholy','Warrior-Arms','Mage-Fire','Paladin-Protection','Hunter-Survival','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Feral','Priest-Shadow','Priest-Discipline','Monk-Windwalker','DeathKnight-Blood','Monk-Mistweaver',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Addisyn:BAAANQAECgEIAQAAAA==.',
Ae='Aemetris:BAAANQAECggIDwAAAA==.Aendrel:BAABNQAECn8ZAAIBAAkKMR0iEQDmAgABAAkKMR0iEQDmAgAAAA==.',
Ai='Airaquafira:BAABNQAECn8hAAICAAkK/xxLKQC+AgACAAkK/xxLKQC+AgAAAA==.',
Aj='Ajheria:BAAANQADCgYIDQABNQAECgkJHwADAD4SAA==.',
Al='Alejandro:BAAANQAECggICQAAAA==.Alégria:BAAANQAECgYIDAAAAA==.',
Am='Amiragosa:BAAANQABCgYICAAAAA==.',
An='Anaire:BAAANQAECgEIAQAAAA==.Anaiya:BAAANQADCgEIAQAAAA==.Anaru:BAABNQAECn8iAAIEAAgKLQXsYQBHAQAEAAgKLQXsYQBHAQAAAA==.Angriff:BAAANQAECgEIAQAAAA==.Anraleth:BAABNQAECn8yAAIFAAkK+CPrAwCYAwAFAAkK+CPrAwCYAwAAAA==.Anxiqtt:BAAANQAECgEIAQAAAA==.',
Ar='Arckillion:BAAANQAECggIEQAAAA==.Arcángel:BAAANQAECgIIAgAAAA==.Arduous:BAAANQADCgcIBwAAAA==.Ariana:BAAANQADCgYIDAAAAA==.Arkadio:BAAANQABCgIIAgAAAA==.Armâgeddon:BAAANQADCgYIBgAAAA==.',
As='Asparagus:BAAANQAECgYIDAAAAA==.Asturoth:BAAANQADCggIDgAAAA==.',
Au='Aust:BAAANQADCgcIBwAAAA==.Authority:BAAANQAECggICAAAAA==.',
Av='Averlis:BAAANQAECgUIDgAAAA==.Avoiddance:BAAANQADCgYICgABNQAECgkJHwADAD4SAA==.',
Ay='Ayci:BAAANQAECgQIBgAAAA==.',
Az='Azmithrilim:BAAANQAECgYIDwAAAA==.Azurargentyr:BAAANQABCgEIAQAAAA==.',
Ba='Baconbo:BAAANQAECgUIDwAAAA==.Batistabomba:BAAANQADCgUIBQAAAA==.',
Be='Bended:BAABNQAECn8hAAMDAAkKFhLzKQBLAQADAAgKlQ/zKQBLAQAGAAQKfBZ+MQABAQAAAA==.',
Bi='Bighodgy:BAAANQADCgMIAwAAAA==.',
Bl='Blikey:BAAANQAECgcIBwAAAA==.Bloodyrott:BAAANQADCgIIAgAAAA==.Bluedrake:BAAANQAFFAEIAgABNQAFFAMIBgAEANcYAA==.Blueparrot:BAABNQAECn8hAAIHAAkK0goVcQDKAQAHAAkK0goVcQDKAQAAAA==.',
Bo='Bocantwo:BAAANQAECgEJAQAAAA==.Boggyboomer:BAAANQADCgMIAwAAAA==.Bombfaucet:BAAANQADCgEIAQAAAA==.',
Br='Brewteaful:BAAANQADCgEIAQAAAA==.Bringinlight:BAAANQAECgQIBwABNQAECgUICAAIAAAAAA==.',
Bu='Bubbleicious:BAAANQAECgEIAQAAAA==.Bubbleyum:BAAANQADCgQIBAAAAA==.Bulletz:BAAANQAECgQIBgAAAA==.',
Ca='Cahhwa:BAAANQADCgMIAwAAAA==.Camillie:BAAANQADCgIIAgAAAA==.Cassandria:BAABNQAECn8gAAMEAAgKFAkMXQBdAQAEAAcKFAkMXQBdAQAJAAUK2QmbHwDPAAAAAA==.Cassiradra:BAAANQADCgUIBQAAAA==.',
Ce='Cervixticklr:BAAANQADCggIHAAAAA==.',
Ch='Chathlia:BAAANQABCgIIAgAAAA==.Choglana:BAAANQADCgQIBAAAAA==.Chogric:BAABNQAECn8oAAIKAAoKSSG0CwBrAwAKAAoKSSG0CwBrAwABNQADCgQIBAAIAAAAAA==.Châos:BAABNQAECn8kAAILAAkKpQ5WPQBMAQALAAkKpQ5WPQBMAQAAAA==.',
Ci='Cif:BAAANQAECgQICQAAAA==.Civetta:BAABNQAECn8hAAIMAAkKJhbGUQB7AgAMAAkKJhbGUQB7AgAAAA==.',
Cr='Crazzywazzy:BAAANQAECgYIDgAAAA==.Crona:BAAANQAECgcIEQAAAA==.Crzyblnkrton:BAACNQAFFH8WAAINAAYK/A+OGAC0AQANAAYK/A+OGAC0AQA1AAQKfx8AAg0ACgpeHV11AJMCAA0ACgpeHV11AJMCAAAA.Crzzy:BAAANQAECgQIBAAAAA==.',
Cu='Cultera:BAABNQAECn8sAAIBAAoKHB7HBADMAQABAAoKHB7HBADMAQAAAA==.Cuzon:BAAANQAECgcIEQABNQAECgkJFAAEAAgYAA==.',
Cy='Cyhyraethia:BAABNQAECn8fAAIOAAgKlB0OAwDVAgAOAAgKlB0OAwDVAgABNQAFFAMICAABAHYSAA==.',
Da='Dagden:BAAANQAECgEIAQAAAA==.Daish:BAAANQADCgMIAwAAAA==.Danda:BAAANQADCggIFgAAAA==.Dare:BAAANQAFFAQIBAABNQAFFAQIBgAPAMoMAA==.Daricepicker:BAABNQAECn8uAAIMAAoK6x9WGwArAwAMAAoK6x9WGwArAwAAAA==.Darkyn:BAABNQAECn8fAAIDAAkKPhJ/awAbAgADAAkKPhJ/awAbAgAAAA==.',
Dd='Ddeonù:BAACNQAFFH8HAAIBAAIK8ANdBwBqAAABAAIK8ANdBwBqAAA1AAQKfycAAgEACgpKFFwhAEECAAEACgpKFFwhAEECAAAA.',
De='Deadlysins:BAAANQADCggICAABNQAECggICAAIAAAAAA==.Deadscar:BAECNQAFFH8HAAIQAAQKJxvbAAAgAQAQAAQKJxvbAAAgAQA1AAQKfyYAAhAACgpWI4YCAIIDABAACgpWI4YCAIIDAAAA.Deathmasterj:BAAANQADCggIDwAAAA==.Delphinium:BAAANQADCgQICAAAAA==.Dentheaded:BAACNQAFFH8lAAILAAcKESQ/AQCyAgALAAcKESQ/AQCyAgA1AAQKfywAAgsACgrpJSMMAKADAAsACgrpJSMMAKADAAAA.',
Di='Dithariaa:BAAANQAECgQIBAAAAA==.',
Do='Docryktor:BAABNQAECn8rAAIQAAgKuRZeCQBeAQAQAAgKuRZeCQBeAQAAAA==.Doomgears:BAAANQAECgMIAwAAAA==.',
Dr='Draculä:BAAANQAECgEIAQABNQAECgcJBwAIAAAAAA==.Drashta:BAAANQAECgYIDgAAAA==.Drhurtouch:BAAANQAECgMIBgAAAA==.Drogas:BAABNQAECn8zAAQRAAkKxhMUAgA4AgARAAkKxhMUAgA4AgASAAYKsQeYJAAbAQATAAUK3wsDFQDeAAAAAA==.Drtybear:BAAANQAECgQIBwAAAA==.Druithz:BAAANQAECgQIBAABNQAFFAIIBQAKAO8eAA==.',
['Dâ']='Dârrius:BAAANQADCggICQAAAA==.',
Eb='Ebonwings:BAAANQAECgYIBwAAAA==.',
Ed='Ediana:BAABNQAECn8jAAMNAAoK6AawgwC7AAANAAoK6AawgwC7AAAUAAIKcgNzQQBBAAAAAA==.Edisian:BAAANQABCgIIAgAAAA==.',
Ee='Eebz:BAAANQADCgQIBAAAAA==.Eebzy:BAAANQAECggIEQAAAA==.',
El='Elandrah:BAABNQAECn8VAAIHAAcKkgJBsAAGAQAHAAcKkgJBsAAGAQAAAA==.Elithsong:BAAANQABCgIIAgAAAA==.Elmô:BAABNQAECn8tAAIKAAgKfBn1DwDYAQAKAAgKfBn1DwDYAQAAAA==.',
Es='Essence:BAAANQADCgYIBgAAAA==.Estameling:BAABNQAECn8fAAIVAAcK8hK6DwASAQAVAAcK8hK6DwASAQAAAA==.',
Et='Etherah:BAAANQABCgEIAQAAAA==.',
Ex='Excizion:BAABNQAECn8YAAIWAAgKIQ8aZQB8AQAWAAgKIQ8aZQB8AQAAAA==.',
Fa='Fantabulouus:BAABNQAECn8aAAIXAAkKag2HNABBAQAXAAkKag2HNABBAQAAAA==.Fantym:BAAANQABCgYJBgAAAA==.Farorê:BAAANQABCgEIAQAAAA==.Fatherrahl:BAAANQAECggICAAAAA==.Fathertim:BAAANQAECgQIBAAAAA==.',
Fe='Feldrena:BAAANQADCggIEQAAAA==.',
Fl='Flangus:BAAANQADCgYICQAAAA==.',
Fo='Forgiven:BAABNQAECn8XAAIEAAgKLSOYLQBwAgAEAAgKLSOYLQBwAgAAAA==.Foxyhound:BAAANQAECggIBgAAAA==.',
Fr='Franksredhot:BAAANQAECgEIAQAAAA==.Frostii:BAAANQAECgYICwAAAA==.',
Fu='Fudestamp:BAAANQAECgUIBgAAAA==.Fugryktor:BAAANQAECgQIDQABNQAECggIKwAQALkWAA==.Fuu:BAAANQABCgMJAwAAAA==.Fuzzywuzzy:BAAANQADCgYIBgAAAA==.',
Fy='Fyre:BAAANQADCgQIBQAAAA==.',
Ga='Galandor:BAAANQAECgUIBwAAAA==.Galethia:BAAANQADCgMIAwAAAA==.Gandaalf:BAABNQAECn8fAAQYAAkKDh6TAACeAQAYAAcKvB6TAACeAQAUAAMKExjQJADIAAANAAEKAABCqwFqAAAAAA==.Gandelfzz:BAAANQADCgEIAQAAAA==.',
Ge='Geedorah:BAAANQADCgIIAgAAAA==.Gemhide:BAABNQAECn8WAAMGAAoKJQ6PFQDBAQAGAAoKJQ6PFQDBAQADAAMKvQPULgFfAAAAAA==.Gerbo:BAAANQABCgIIAwAAAA==.',
Gi='Gityadruid:BAAANQADCgYIIwABNQAECgUICAAIAAAAAA==.Gityahunter:BAAANQAECgQICAABNQAECgUICAAIAAAAAA==.',
Go='Gobanks:BAABNQAECn80AAIZAAoKwh4RAgBAAgAZAAoKwh4RAgBAAgAAAA==.',
Gr='Grayarms:BAAANQAECgQIBwAAAA==.Graygoat:BAAANQADCgYIBgABNQAFFAgIHAAaAOciAA==.Grayresto:BAAANQABCgQIBAAAAA==.Grayson:BAAANQAECgQIBwAAAA==.Graysurv:BAACNQAFFH8cAAIaAAgK5yIDAABjAwAaAAgK5yIDAABjAwA1AAQKfywAAhoACgr7JmIAAM8DABoACgr7JmIAAM8DAAAA.Grimik:BAABNQAECn8aAAMFAAoK1wmlNgCZAQAFAAkKHgelNgCZAQAMAAoKnwjGegC4AAAAAA==.Grimwali:BAAANQAECgUICgAAAA==.',
Ha='Hallêlujah:BAAANQABCgMIBAAAAA==.Hamelot:BAAANQAECgEIAQAAAA==.Hamremmi:BAAANQADCgIIAgABNQAECgcICwAIAAAAAA==.Hardrock:BAEANQADCgcIEAABNQAECgkJHgAbAC4IAA==.',
He='Healsforu:BAAANQAECgEIAQAAAA==.Healulater:BAAANQADCgUIBgABNQAECgcIDAAIAAAAAA==.',
Ho='Hobiscuits:BAEANQABCgcIEQABNQAECgYIDgAIAAAAAA==.',
Hu='Hurtfinger:BAAANQADCgYIBgAAAA==.',
Hy='Hydrobubble:BAAANQADCgYIBgAAAA==.',
Il='Illyy:BAAANQAECgQJBgAAAA==.',
Im='Imagine:BAABNQAECn8XAAMSAAoKZBuUAACXAgASAAkKZBuUAACXAgARAAgKBwx4IwCqAQAAAA==.',
In='Indagussy:BAAANQAECgcIEgABNQAFFAYIEwAcAN4dAA==.Indawhole:BAACNQAFFH8TAAIcAAYK3h3IAwA/AgAcAAYK3h3IAwA/AgA1AAQKfygABBwACgrmIgcVAPUCABwACAocJQcVAPUCAAEACArKIG0fAFQCAB0AAQoKE88VAEYAAAAA.',
Ir='Ironsparc:BAAANQADCggICAABNQAECgkJHwADAD4SAA==.',
Is='Isamna:BAAANQABCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAANQAECgQIBQAAAA==.',
Ja='Jasmean:BAAANQADCgQIBAAAAA==.Jassabella:BAAANQAECgEIAgAAAA==.Javaluminous:BAABNQAECn8gAAILAAgK3BMSLwBzAQALAAgK3BMSLwBzAQAAAA==.Jaytsukitori:BAABNQAECn8UAAQEAAkKCBh8YwBAAQAEAAYKFRN8YwBAAQAJAAYKDx34FgALAQAVAAEKAADeZAArAAAAAA==.',
Jd='Jdots:BAAANQADCggIEwAAAA==.',
Jh='Jhantherox:BAAANQABCgQIBAABNQAECgkJHwADAD4SAA==.Jheranton:BAAANQADCgYICgABNQAECgkJHwADAD4SAA==.',
Ji='Jiannae:BAAANQADCgIIAgABNQAECggIDwAIAAAAAA==.Jif:BAAANQAECgUIBQAAAA==.',
Jo='Joesepi:BAAANQAECgcICwAAAA==.Jonah:BAABNQAECn8iAAQOAAoKIiL1BACAAgAOAAgKhR71BACAAgADAAgK1h61LQA/AQAGAAQKmB08KQAxAQABNQAECgoKIQAWAPEhAA==.Joodee:BAAANQAECgYIEQAAAA==.Jordi:BAAANQADCgcIBwAAAA==.Joseon:BAAANQAECgQICQABNQAECgoKKgAJAPsjAA==.',
Ka='Kackarot:BAABNQAECn8nAAIbAAkK/RLGUQAyAgAbAAkK/RLGUQAyAgAAAA==.Kartelz:BAAANQAECgYIEQAAAA==.Katrine:BAABNQAECn8pAAIeAAgKNxdNKgBIAgAeAAgKNxdNKgBIAgAAAA==.',
Ke='Kendreth:BAAANQADCgQICAAAAA==.',
Ki='Kij:BAECNQAFFH8QAAMUAAQKlhjzAADoAAAUAAMKDRTzAADoAAANAAIKgBRCSQCWAAA1AAQKfyUAAw0ACgqtHy1RAN4CAA0ACgooHy1RAN4CABQAAgo5JaASAG0AAAAA.Kilrah:BAABNQAECn8mAAIcAAoKtwmqQgCtAQAcAAoKtwmqQgCtAQAAAA==.Kissmycrits:BAABNQAECn8fAAIMAAYKhhWyaQDYAAAMAAYKhhWyaQDYAAAAAA==.Kissmywrath:BAAANQAECgQIBgAAAA==.Kiyoine:BAABNQAECn8cAAIfAAcK+Q09BwA6AQAfAAcK+Q09BwA6AQAAAA==.',
Kn='Knocksteady:BAAANQAECgcIEAAAAA==.Knoxreaps:BAAANQADCgUIBQAAAA==.',
Ko='Kookie:BAAANQAECgUICQAAAA==.',
Kr='Kryyng:BAAANQADCgMIAwAAAA==.Krzyng:BAAANQADCgMIAwAAAA==.',
Ky='Kynbrookera:BAABNQAECn8jAAIJAAkKiBL6BgDYAQAJAAkKiBL6BgDYAQAAAA==.',
Kz='Kzmyng:BAAANQADCgcIBwAAAA==.',
['Kì']='Kìnky:BAAANQADCgcIBwAAAA==.',
La='Lacquerhead:BAAANQADCgQIBAABNQADCgYIBgAIAAAAAA==.Laetha:BAAANQADCggIDgABNQAECggIGAASAJcTAA==.Larriat:BAAANQADCgUIBgAAAA==.Layonscoob:BAAANQAECgEIAQAAAA==.',
Li='Lightweaver:BAAANQAECggICQAAAA==.Linai:BAABNQAECn82AAIPAAoK6gfRHQDkAQAPAAoK6gfRHQDkAQAAAA==.Linthe:BAABNQAECn8hAAMKAAoKzAwdOAAFAQAKAAoKzAwdOAAFAQALAAEKdwagrgEwAAAAAA==.Lit:BAAANQAECgYIDAAAAA==.Lites:BAAANQAECgYICwAAAA==.Littledog:BAABNQAECn8WAAQgAAkKpRDLPwAwAQAgAAYKYRHLPwAwAQAhAAYKSw6AEAAhAQAHAAMKuhFDbwCIAAAAAA==.',
Lo='Longshenks:BAAANQADCgIIAgAAAA==.Lotten:BAABNQAECn8nAAILAAgKARh/TAArAQALAAgKARh/TAArAQAAAA==.',
Lu='Luckevin:BAAANQAECgUIBwAAAA==.Lumi:BAAANQAECgIIAwAAAA==.Lurashtai:BAAANQAECgUICwAAAA==.Luvido:BAAANQABCgcICQAAAA==.',
Ma='Magicmann:BAAANQADCgQIBAAAAA==.Magicor:BAAANQADCggICAAAAA==.Malafang:BAAANQAECgIIBAAAAA==.Malanah:BAAANQAECgIIAwAAAA==.Malgaren:BAAANQABCggIEwAAAA==.Mangoo:BAAANQADCgYIBgAAAA==.Marandra:BAAANQADCgcIFgAAAA==.Maverick:BAACNQAFFH8GAAIPAAQKygz4CQBCAQAPAAQKygz4CQBCAQA1AAQKfysAAg8ACgr0H8EGABMDAA8ACgr0H8EGABMDAAAA.',
Me='Meregryn:BAAANQADCgUIBQAAAA==.Merunyaa:BAAANQAECgcIDQAAAA==.',
Mi='Michaella:BAAANQADCgYIEAAAAA==.Mil:BAAANQADCgQJBQAAAA==.Minipwn:BAAANQAECgYIDgAAAA==.',
Mk='Mk:BAEANQAECgUIBgABNQAECgkJJwAiABYcAA==.',
Mo='Mogar:BAABNQAECn8XAAIXAAgKLAzlyQBjAQAXAAgKLAzlyQBjAQAAAA==.Moonzhine:BAAANQADCggJEQAAAA==.Moosejaw:BAAANQAECgEIAQAAAA==.Mordread:BAAANQAECgIIAgAAAA==.Morgalruk:BAAANQADCgcIFgAAAA==.',
My='Mythx:BAACNQAFFH8MAAIMAAQK1RmmBQAFAQAMAAQK1RmmBQAFAQA1AAQKfyUAAwwACgrjIfMiAAsDAAwACgrjIfMiAAsDAAUACArsDig2AJ0BAAAA.',
['Mý']='Mýthh:BAAANQADCggIAQAAAA==.',
Na='Naturboy:BAAANQADCgYIBgAAAA==.',
Ne='Netherward:BAACNQAFFH8dAAMOAAcKex1aAAAjAgAOAAYKWCBaAAAjAgADAAUKYhniCgC9AQA1AAQKfzIAAw4ACgr7JPoAAGwDAA4ACQouJfoAAGwDAAMABQpmIPxUANkAAAE1AAQKBwgLAAgAAAAA.',
Ni='Nivmizzet:BAABNQAECn8qAAMDAAoKRBsxCAAkAgADAAkKvxoxCAAkAgAGAAIKGBtISwCeAAAAAA==.',
No='Nolakai:BAAANQAECgQIBAAAAA==.Nonliving:BAAANQADCgUIBQAAAA==.Novagosa:BAAANQAECgUICwABNQAECgoKKgACAH4kAA==.Novalea:BAABNQAECn8qAAMCAAoKfiTKCAB7AwACAAoKfiTKCAB7AwAbAAEKNwyEigA9AAAAAA==.Nozom:BAAANQADCgYIBgAAAA==.',
Np='Np:BAAANQAECgMJBQAAAA==.',
Nu='Nutcutter:BAAANQAECgQIBQABNQAECgcIFwAWANUOAA==.',
Ny='Nyvera:BAAANQADCgIIAgAAAA==.Nyxon:BAAANQADCgYIEQAAAA==.',
Os='Osirus:BAAANQAECgIIAgAAAA==.',
Ox='Oxxo:BAAANQAECgQIBAAAAA==.',
Pa='Palomar:BAAANQAECgQIBwAAAA==.Paraggonn:BAAANQAECgQICwAAAA==.',
Ph='Pherkle:BAAANQAECgQIBQABNQAECggIKwAQALkWAA==.Phuriosa:BAAANQAECgIIAgABNQAECgoKHgAJACkSAA==.Phury:BAABNQAECn8eAAIJAAoKKRJiKADdAQAJAAoKKRJiKADdAQAAAA==.Physinyx:BAABNQAECn8xAAMbAAoK6A0QFAB5AQAbAAoK6A0QFAB5AQACAAgKmwAn8gCGAAAAAA==.',
Pi='Pizza:BAAANQAECgQIBAAAAA==.',
Po='Pomomies:BAAANQABCgIIAgAAAA==.Pooseunpoose:BAABNQAECn8cAAIjAAoKdxafBAAOAgAjAAoKdxafBAAOAgAAAA==.',
Pu='Pumbaa:BAAANQAECgIIAgABNQAECgcJBwAIAAAAAA==.',
Qu='Quilby:BAAANQADCgUICgAAAA==.',
Ra='Raenyx:BAABNQAECn8sAAMDAAoKygznPwAOAQADAAoKygznPwAOAQAGAAEKAADNhwAeAAABNQAECgoKMQAbAOgNAA==.Ragnarrok:BAAANQADCgYIBgAAAA==.Raif:BAABNQAECn8aAAIYAAcKXg0fAQA4AQAYAAcKXg0fAQA4AQAAAA==.Randir:BAAANQADCgIIAgAAAA==.Raveneyes:BAEBNQAECn8UAAIDAAoKBAgRwgBHAQADAAoKBAgRwgBHAQAAAA==.',
Re='Reightous:BAAANQAECgQIBwAAAA==.Reylilyn:BAABNQAECn8XAAIkAAgKcw5iHwCWAQAkAAgKcw5iHwCWAQAAAA==.Reynarena:BAAANQADCgMIAwAAAA==.',
Rh='Rhaenfyre:BAABNQAECn8qAAMBAAoK9xpeHAByAgABAAkKVxteHAByAgAcAAMKzBXsMwCZAAAAAA==.',
Ri='Ripley:BAAANQAECgcIBwABNQAFFAQIBgAPAMoMAA==.Rivenel:BAACNQAFFH8JAAMGAAQKEg02AwCWAAAGAAIK1wo2AwCWAAADAAIKiRGsHABKAAA1AAQKfzIAAwYACgq4HtoFALQCAAYACAomH9oFALQCAAMACAqOG7xbAEQCAAAA.',
Ro='Robinvoid:BAABNQAECn8ZAAMBAAoKHhpBFgCwAgABAAoKHhpBFgCwAgAcAAEK3wsNkwA1AAAAAA==.Rodel:BAAANQAECgMIAgAAAA==.Rondrey:BAAANQADCgYIBgAAAA==.Roquan:BAABNQAECn8eAAIeAAcKnREIFgBaAQAeAAcKnREIFgBaAQAAAA==.Rosè:BAAANQAECgYIBgABNQAFFAQIBgAPAMoMAA==.',
Ru='Rubmyrott:BAAANQAECgEIAQAAAA==.Runawäy:BAAANQAECgcIDAAAAA==.Rundas:BAAANQAECgYIDAAAAA==.',
['Ré']='Rébél:BAAANQADCgYICAAAAA==.',
['Rê']='Rêdd:BAABNQAECn8ZAAIgAAgK3QwDMQCbAQAgAAgK3QwDMQCbAQAAAA==.',
['Rì']='Rìven:BAAANQADCgYICAAAAA==.',
Sa='Sabeion:BAAANQAECggIEQAAAA==.Saddie:BAAANQADCgYICwAAAA==.Saharaa:BAAANQAECgEIAwAAAA==.Salswarriah:BAAANQAECgUIBwAAAA==.Sanasath:BAAANQAECgYIEgABNQAECgcIFgAZAPIaAA==.',
Se='Sealgair:BAAANQADCgIIAgAAAA==.Segador:BAAANQAECgUICAAAAA==.Seonwoo:BAAANQAECgEIAQAAAA==.Seraphim:BAAANQADCggICAAAAA==.',
Sg='Sgtbonesnap:BAAANQADCgUIBQABNQAECgEIAQAIAAAAAA==.',
Sh='Shamanizim:BAACNQAFFH8HAAIbAAMK0RZIBgDuAAAbAAMK0RZIBgDuAAA1AAQKfzoAAhsACgq+IpoQAGgDABsACgq+IpoQAGgDAAAA.Shamanka:BAAANQADCgIIAgAAAA==.Sheetara:BAAANQAECgQIBAAAAA==.Shenzii:BAAANQAECgQICAAAAA==.Shikigami:BAAANQABCgcICAAAAA==.Shinoikari:BAAANQADCgYIEwABNQAECgkJLgAXAPgRAA==.Shinotenshi:BAAANQAECgQICgABNQAECgkJLgAXAPgRAA==.Shugarae:BAAANQAECgcIDwAAAA==.',
Si='Silvafist:BAAANQAECgEJAwAAAA==.',
Sk='Skreezy:BAAANQAECgYIDAAAAA==.Skuls:BAAANQADCgMIAwAAAA==.',
Sl='Slashemup:BAABNQAECn8UAAIcAAgKCBFVPQDOAQAcAAgKCBFVPQDOAQAAAA==.Slayter:BAABNQAECn8qAAIJAAoK+yOEAgCmAgAJAAoK+yOEAgCmAgAAAA==.',
Sm='Smaugor:BAAANQAECgYIEQABNQAECgcJBwAIAAAAAA==.',
So='Soju:BAAANQAECggICwABNQAECgoKLgAMAOsfAA==.Solder:BAAANQAECgEIAQAAAA==.Soliloquy:BAABNQAECn8lAAMgAAoKIhHcBACxAQAgAAoKIhHcBACxAQAhAAUKiBEzDwA4AQAAAA==.Solosith:BAAANQADCggIDwAAAA==.',
Sq='Squishyman:BAABNQAECn8nAAIDAAkKoR23GAAlAwADAAkKoR23GAAlAwAAAA==.Squishypal:BAAANQAECgQIBQABNQAECgkJJwADAKEdAA==.',
St='Stare:BAEANQAECgEIAQABNQAFFAQIBwAQACcbAA==.Stuperdrood:BAAANQAECggIAQABNQAECggIFgAIAAAAAA==.Stõrm:BAAANQADCgYIBgABNQAECgcJBwAIAAAAAA==.',
Su='Sunoô:BAAANQADCgcIBwAAAA==.Suzsette:BAAANQAECgQIBwAAAA==.',
Sw='Swïper:BAAANQABCgQIBAAAAA==.',
Sy='Sylris:BAAANQADCgIIAgAAAA==.Syrelyia:BAAANQAECgEIAQAAAA==.',
Ta='Tardovski:BAAANQAECgUIDAAAAA==.',
Te='Teneturadvos:BAAANQAECgIIAgABNQAECgYIBwAIAAAAAA==.Terrorwynd:BAAANQAECgMIBgAAAA==.',
Th='Thellaria:BAAANQAECgEIAQAAAA==.Thiccterror:BAAANQAECgQIBAAAAA==.Thumpér:BAAANQADCgQIBAAAAA==.Thunderkeg:BAAANQADCgUIBQAAAA==.',
Ti='Tirgo:BAAANQABCgQJBQAAAA==.',
Tr='Traevel:BAAANQADCgYIBgABNQADCgYIBgAIAAAAAA==.Travesti:BAAANQADCgQIBAAAAA==.Treala:BAAANQADCgQIBgABNQAECgIIAwAIAAAAAA==.Treme:BAAANQAECgUICgAAAA==.Troche:BAABNQAECn8WAAIZAAcK8hoBIADlAQAZAAcK8hoBIADlAQAAAA==.Truthfully:BAAANQAECggIEQAAAA==.',
Tt='Ttjpll:BAAANQAECgIIBQAAAA==.',
Tu='Tuckncloak:BAAANQAECgcIBwAAAA==.',
Un='Undeadtoast:BAABNQAECn8gAAIjAAkKkBZlNQA2AgAjAAkKkBZlNQA2AgABNQAFFAYIFgAZAIAcAA==.Unhappytoast:BAACNQAFFH8WAAIZAAYKgBzkAABxAQAZAAYKgBzkAABxAQA1AAQKfyQAAhkACgqIIWIJAAcDABkACgqIIWIJAAcDAAAA.Unstobubble:BAAANQAECgMIAwAAAA==.',
Ur='Uriania:BAAANQADCgIIAgAAAA==.',
Us='Ushioni:BAACNQAFFH8OAAIXAAQKDwuvHgAWAQAXAAQKDwuvHgAWAQA1AAQKfykAAhcACgqzFuFmAFsCABcACgqzFuFmAFsCAAAA.',
Va='Valeriya:BAAANQADCgQIBgABNQAECgMIAgAIAAAAAA==.Valisanna:BAAANQADCgQICgAAAA==.Valklemor:BAAANQAECgEIAwAAAA==.Vallorien:BAAANQAECgQIBwAAAA==.',
Ve='Velaryn:BAAANQAECgcJBwAAAA==.Vengeânce:BAAANQADCgYICwAAAA==.Verenoth:BAAANQAECgIIBAAAAA==.',
Vi='Viveca:BAABNQAECn8fAAIKAAcKXSS6AwC8AgAKAAcKXSS6AwC8AgAAAA==.Viztrix:BAAANQABCgIIAgAAAA==.',
Wh='Whiteparrot:BAAANQAECgIIAQAAAA==.Wholy:BAABNQAECn8mAAMKAAoKZBooKQDDAgAKAAoKZBooKQDDAgALAAQK0RFxNwHHAAAAAA==.',
Wo='Woden:BAAANQAFFAEIAgABNQAECgcICwAIAAAAAA==.',
Xa='Xaanii:BAAANQAECgQIBwAAAA==.Xarferrin:BAAANQAECgMIAwAAAA==.',
Xe='Xeeria:BAACNQAFFH8HAAMCAAMK1gd6CwDDAAACAAMK1gd6CwDDAAAbAAEKtgEaMwBDAAA1AAQKfyQAAwIACgpGHJgoAMECAAIACgpGHJgoAMECABsAAwpfFMviANEAAAAA.Xenzull:BAAANQAECgEIAQAAAA==.',
Xu='Xuecat:BAAANQADCggIEQAAAA==.Xuefeiyan:BAAANQAECgUIBwAAAA==.',
Yu='Yuni:BAAANQADCgEIAQAAAA==.',
Za='Zadee:BAAANQADCgUIBQAAAA==.Zaralina:BAAANQAECgYIDwAAAA==.Zarithra:BAAANQAECgEIAQAAAA==.Zarynth:BAAANQAECgQIBAAAAA==.Zaryssa:BAAANQAECgQIBwAAAA==.',
Ze='Zenagosa:BAAANQABCgIIAgAAAA==.Zenzhu:BAAANQAECgQIBQAAAA==.Zenzug:BAAANQADCgUIBQAAAA==.Zeronightt:BAAANQADCgMIAwAAAA==.',
Zh='Zharazi:BAAANQABCgQIBAABNQADCggJEQAIAAAAAA==.Zharfrost:BAAANQADCggIEQABNQAECgkJHwADAD4SAA==.Zhieri:BAAANQADCgUICAAAAA==.',
Zm='Zmaj:BAAANQABCgIIAgAAAA==.',
Zo='Zombiehunter:BAABNQAECn8jAAIMAAgKfxRLcAAxAgAMAAgKfxRLcAAxAgAAAA==.Zomboy:BAAANQADCgMIAwAAAA==.Zornqueff:BAAANQADCggICAAAAA==.Zortax:BAAANQAECgYICwAAAA==.',
Zu='Zu:BAAANQAECgQIAgAAAA==.Zug:BAABNQAECn8ZAAIMAAgKXRYbRAAtAQAMAAgKXRYbRAAtAQAAAA==.Zurgyn:BAAANQAECgIIAgAAAA==.',
['Âr']='Ârc:BAAANQAECgIIBAAAAA==.',
['Ðr']='Ðream:BAAANQAECggICAAAAA==.',
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
