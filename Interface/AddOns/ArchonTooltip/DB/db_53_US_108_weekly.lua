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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Druid-Balance','Druid-Guardian','Druid-Restoration','Monk-Windwalker','Warlock-Destruction','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Mage-Fire','Evoker-Preservation','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQAECgQIDAAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQADCgMIAwAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAABNQAECn8mAAMCAAcKJRbhLgCHAAADAAYKgRPL1gD9AAACAAMKWRXhLgCHAAAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQAECgYIDQAAAA==.Antilles:BAAANQADCgIIAgAAAA==.Antoer:BAAANQAECgYIDQAAAA==.',
Ap='Aposthmighty:BAAANQADCgIIAgABNQAECgIIBQABAAAAAA==.',
Aq='Aquanox:BAAANQADCgYIBgAAAA==.',
Ar='Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQAECgcIBwAAAA==.Asonnari:BAAANQAECgYIDwAAAA==.',
At='Atreana:BAABNQAECn9FAAMEAAoKIBoUMQBLAgAEAAoK4xkUMQBLAgAFAAIK7RADHwB9AAAAAA==.Attykus:BAAANQAECgUIBAAAAA==.',
Av='Avalerion:BAABNQAECn87AAIGAAoK7h5nRABdAgAGAAoK7h5nRABdAgAAAA==.Avij:BAAANQADCgYIBgABNQAECgIIAQABAAAAAA==.',
Ay='Ayrlyn:BAABNQAECn8gAAIHAAoKJRX4NAABAgAHAAoKJRX4NAABAgAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAABNQAECn8wAAMDAAoKbxcMbQCkAgADAAoKNBcMbQCkAgACAAEKbCGSNgBiAAAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAABNQAECn8UAAMIAAYKNwWhTQDeAAAIAAYKNwWhTQDeAAAJAAQKhAZ5GgCWAAABNQAECgoKIwAKADUSAA==.Beechni:BAAANQAECgYIBwAAAA==.Belgarde:BAAANQADCgcICgAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.Biological:BAAANQAECgYIBwAAAA==.Biomancer:BAAANQAECgQIBQAAAA==.Bismo:BAAANQAECgIIAQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bloodsharkds:BAAANQAECgEIAQAAAA==.Bluwhale:BAAANQAECgcIDQAAAA==.',
Bo='Bormor:BAAANQAECgcIDwAAAA==.Bosambosia:BAAANQAECgIIAQAAAA==.Bowdacious:BAAANQADCgcIHQAAAA==.',
Br='Brainpath:BAAANQABCggICQAAAA==.Brasidias:BAAANQAECgQIDgAAAA==.Brickingkeys:BAABNQAECn8mAAMDAAoKah8RhgByAgADAAgKyx4RhgByAgACAAIKSSFgKACyAAAAAA==.Brumak:BAAANQADCgYICwAAAA==.Bruno:BAABNQAECn9FAAMLAAoKHBlWEgB8AgALAAoKHBlWEgB8AgAGAAEKAADbsgEuAAAAAA==.Brödìe:BAAANQADCgIIAgAAAA==.',
Bu='Budthespud:BAAANQADCgYIEAAAAA==.Bunnydad:BAAANQAECgEIAQAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECn8ZAAQMAAkK8gv8GQAJAgAMAAkKqAr8GQAJAgANAAEKRxdQGgBAAAAOAAEKWwtboQA4AAAAAA==.Burundi:BAAANQADCgUIBQAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caladin:BAABNQAECn8uAAILAAoKmRxvEACWAgALAAoKmRxvEACWAgAAAA==.Calemental:BAAANQAECgQIAwABNQAECgoKLgALAJkcAA==.Callistos:BAAANQAECgEIAQABNQAECgoKLgALAJkcAA==.Camelshammy:BAAANQAECgEIAQAAAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBQABNQAECgYIEQABAAAAAA==.Castianna:BAAANQAECgIIAgAAAA==.',
Ce='Cebastian:BAAANQADCgcIBwABNQAFFAIIBgAFAGEEAA==.Ceforium:BAABNQAECn8tAAMCAAoKthOaCQAOAgACAAoKthOaCQAOAgADAAEKAACUfAEAAAAAAA==.Century:BAABNQAECn9KAAQPAAoKVhVkHgAOAgAPAAoKfhRkHgAOAgAQAAkKPBDUIQB0AQARAAMKgAz8XACUAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECn8cAAISAAkKEyCIFgCaAgASAAkKEyCIFgCaAgAAAA==.',
Ci='Circa:BAABNQAECn8kAAMDAAoKqwzq3gDKAQADAAkKOw3q3gDKAQACAAIKEAnARAA6AAAAAA==.Cithrel:BAABNQAECn8UAAMTAAkKdAcfJQBKAQATAAcKyAcfJQBKAQAEAAMKOAbOKwFmAAAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Clauadris:BAAANQADCggIFQAAAA==.Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAABNQAECn8mAAIUAAoK/Ad2GwCsAQAUAAoK/Ad2GwCsAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQADCgUIBQAAAA==.Dallia:BAABNQAECn8XAAIGAAYK5QM8NQGdAAAGAAYK5QM8NQGdAAAAAA==.Dalyrimple:BAAANQAECgEIAQAAAA==.Damnatio:BAABNQAECn80AAIGAAoKgCXZBADTAwAGAAoKgCXZBADTAwAAAA==.Darkclement:BAABNQAECn88AAIVAAoKWyJaEwD/AgAVAAoKWyJaEwD/AgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQAECgQICAAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQAECgUIBAAAAA==.Deckard:BAABNQAECn8wAAIVAAkKFCL3QQClAgAVAAkKFCL3QQClAgABNQAECgoKLQACALYTAA==.Deeper:BAABNQAECn8fAAIPAAYKiQXAXACuAAAPAAYKiQXAXACuAAAAAA==.Dementos:BAAANQAECgYICgAAAA==.Demonofwar:BAAANQADCgUICwABNQAECgoKMwAWAHQmAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgUIBgAAAA==.',
Di='Divineblood:BAAANQAECgMIAwAAAA==.',
Dm='Dmaan:BAABNQAECn8kAAIXAAoKDCQpBQCOAwAXAAoKDCQpBQCOAwAAAA==.',
Do='Doomflower:BAAANQAECgIIAgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECn8nAAMXAAoKEB+aKABUAgAXAAoKyh6aKABUAgAYAAcKhR2zNwBHAgABNQAFFAcIEwAMADQUAA==.',
Du='Dumparooski:BAAANQAECggIDAABNQAECgoKKgAHAJ8ZAA==.Durabull:BAAANQADCggIGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Eb='Ebonlight:BAAANQADCggIEAAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCggICwAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAABNQAECn80AAIVAAgKvR5FXgBbAgAVAAgKvR5FXgBbAgAAAA==.Euthanize:BAAANQAECgMIBQAAAA==.',
Ev='Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgUIBgAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAABNQAECn8hAAIVAAkKZgofpwBkAQAVAAkKZgofpwBkAQAAAA==.Feorio:BAAANQAECgYIEQABNQAECgoKNgAKAHQgAA==.',
Fi='Finniessa:BAAANQADCgMIBQAAAA==.Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIGAAAAA==.',
Fr='Freetorylanz:BAAANQABCgcICgAAAA==.',
Ga='Garaylo:BAACNQAFFH8iAAIGAAgKciA7AQC0AgAGAAgKciA7AQC0AgA1AAQKfzUAAgYACQpaJlMKAEwDAAYACQpaJlMKAEwDAAAA.',
Ge='Geoffreys:BAAANQAECgQIBwAAAA==.Geroendor:BAAANQAECgEIAgAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECn8xAAQVAAoKiSKjEABgAwAVAAoK2SGjEABgAwAZAAQKvgyeXQCvAAAaAAMKkBjvDgCaAAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgoKLwAbAJUkAA==.',
Go='Goenitz:BAAANQADCggIDAAAAA==.Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIDAAAAA==.',
Gr='Grimmel:BAAANQAECggIDwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQAECgUIBAAAAA==.Guttris:BAAANQAECgYICQAAAA==.',
Gw='Gwaineelock:BAAANQADCgYIDAAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAABNQAECn8ZAAISAAkKDw0pJAB6AQASAAkKDw0pJAB6AQAAAA==.Haikusen:BAAANQADCggIDAABNQAECgoKMwAWAHQmAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAABNQAECn8aAAIDAAoKcwmSeAC8AQADAAoKcwmSeAC8AQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQAECgYIEgAAAA==.Hesseth:BAABNQAECn8mAAIGAAoK8hjuTgA/AgAGAAoK8hjuTgA/AgAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECn8XAAQUAAkKrxHmEgA7AgAUAAkKrxHmEgA7AgAcAAMKFwho8ACKAAAHAAIKKgUwGwFZAAAAAA==.Holyzel:BAABNQAECn8cAAIGAAoK+RR1ewA0AgAGAAoK+RR1ewA0AgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgoKLwAbAJUkAA==.Hsimingjung:BAABNQAECn8vAAIbAAoKlSRUAwBgAwAbAAoKlSRUAwBgAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgoKLwAbAJUkAA==.',
Hu='Huaka:BAAANQAECgYIEwAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECn8ZAAIEAAgKyRLkgQDhAQAEAAgKyRLkgQDhAQAAAA==.Hymno:BAAANQADCgIIAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Iceeveins:BAAANQADCgUIBQAAAA==.Icolann:BAABNQAECn81AAMcAAoKfR6FLwCjAgAcAAoKfR6FLwCjAgAHAAgKHxKspQBJAQABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQAECgUIBQABNQAECgoKKgAHAJ8ZAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQAECgQIBgAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFH8TAAIMAAcKNBReCQCJAQAMAAcKNBReCQCJAQA1AAQKfzEAAwwACQrYISwZALcCAAwACQrYISwZALcCAA4AAQplFcmcAEMAAAAA.Isto:BAAANQADCgcIBwAAAA==.',
Iv='Ivanyr:BAACNQAFFH8cAAILAAcKmRMgAwBgAQALAAcKmRMgAwBgAQA1AAQKfz8AAgsACgqAH4EOALMCAAsACgqAH4EOALMCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgoKJgADAGofAA==.Jadebug:BAAANQAECggIDQAAAA==.Jaime:BAAANQADCgUIBwABNQAECgoKMwAWAHQmAA==.',
Je='Jenzö:BAAANQAECggIEAAAAA==.Jesta:BAAANQADCgYJDgAAAA==.Jeñzo:BAAANQADCgQIBAAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgcICgAAAA==.Johnnyretwar:BAABNQAECn8aAAMKAAoKGiO9CACCAwAKAAoKGiO9CACCAwAGAAIKXR+2SQGqAAAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECn9CAAIDAAoKUyNfGwBpAwADAAoKUyNfGwBpAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIEAABAAAAAA==.',
Ka='Kaikai:BAACNQAFFH8GAAMFAAIKYQR2CABwAAAFAAIKYQR2CABwAAAEAAEKVAHoPAAvAAA1AAQKfzsABAUACgqBGtYEAIYCAAUACgqLGdYEAIYCAAQACQp3FBxeAD0CABMABArdCtRPAJAAAAAA.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECn8/AAQHAAoK3BbBPwB2AgAHAAoK3BbBPwB2AgAUAAcKLgmJHQCJAQAcAAMKHA3l7QCPAAAAAA==.Kalistus:BAABNQAECn8bAAMdAAkKQRQ5CwClAQAdAAkKQRQ5CwClAQAeAAYKPghtPQC3AAAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgUICAAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECn8qAAQSAAkKJhrgFQAPAgASAAkKJhrgFQAPAgAfAAQKZQeGMwBsAAAbAAEKGQsuMgAuAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kendyll:BAAANQABCgcIBwAAAA==.Kenergy:BAABNQAECn8qAAIOAAoKrw07MwAQAgAOAAoKrw07MwAQAgAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kess:BAAANQAECgQIBAABNQAECgoKQgADAFMjAA==.Kevonjuravis:BAABNQAECn88AAMSAAoKfRCRIACaAQASAAoKbA+RIACaAQAbAAcKnQzBEwDpAAAAAA==.',
Kh='Khalyl:BAABNQAECn8mAAIgAAgK2QtYTQDyAAAgAAgK2QtYTQDyAAAAAA==.',
Ki='Kiandra:BAAANQAECgUIBQAAAA==.Killerfrost:BAAANQADCgQICQAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kilrah:BAAANQADCgUIBQAAAA==.Kilriella:BAAANQABCgIIAgABNQADCggIEAABAAAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kl='Klewinsky:BAAANQADCggIFAAAAA==.',
Kr='Krytus:BAAANQADCgIIAgAAAA==.',
Ku='Kungpaochik:BAABNQAECn8qAAMHAAoKnxllNgCeAgAHAAoKnxllNgCeAgAcAAEKAAAAAAAAAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCggIGgABNQAECgQIDQABAAAAAA==.',
Lo='Lousanis:BAABNQAECn8hAAIYAAkKjgb0iwD0AAAYAAkKjgb0iwD0AAAAAA==.',
Lu='Lucinick:BAABNQAECn8eAAIMAAkKog+QYACKAQAMAAkKog+QYACKAQAAAA==.Lunascare:BAAANQAECgYIBgAAAA==.Lupercal:BAAANQAECggIBwAAAA==.',
Ma='Mactabilis:BAAANQAECgQIAwABNQAECgoKLQACALYTAA==.Madmartegan:BAAANQABCgMIAwAAAA==.Markusthered:BAAANQAECgQICAAAAA==.Massdestruct:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mayhemhoiyaa:BAAANQAECgQIAwAAAA==.Mazza:BAABNQAECn8XAAIaAAkKAxUJBQAhAgAaAAkKAxUJBQAhAgABNQAECgoKIgAKAAwbAA==.',
Mh='Mhelora:BAABNQAECn8XAAIRAAYKdw4ERAD1AAARAAYKdw4ERAD1AAAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAABNQAECn8cAAIDAAcKPRp27QCvAQADAAcKPRp27QCvAQAAAA==.Mindmuncher:BAAANQAECgcIDQAAAA==.Minimini:BAABNQAECn8eAAIfAAgKHw/OLQD9AAAfAAgKHw/OLQD9AAAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgYICQAAAA==.',
Mu='Muggni:BAAANQAECggICAAAAA==.Munder:BAAANQAECgEIAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Mythuneran:BAABNQAECn8rAAIDAAoKzRRwewC1AQADAAoKzRRwewC1AQAAAA==.',
Na='Naheka:BAABNQAECn8XAAIVAAkKhA/8VwAbAgAVAAkKhA/8VwAbAgAAAA==.Narilka:BAAANQAECgIIAgAAAA==.Nazgrogrik:BAAANQADCgQIBQAAAA==.',
Ne='Nemini:BAAANQAECgUICAAAAA==.Nena:BAABNQAECn9VAAMPAAoKZg6oKAC6AQAPAAoKZg6oKAC6AQARAAIKIQbCcQA/AAAAAA==.Nenacurses:BAAANQAECgQIBgABNQAECgoKVQAPAGYOAA==.Nenafury:BAAANQAECgEIAQABNQAECgoKVQAPAGYOAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAABNQAECn8VAAIhAAYKwglJGAC2AAAhAAYKwglJGAC2AAAAAA==.Nity:BAAANQAECgIIAwAAAA==.',
No='Nobala:BAAANQADCgQIBAABNQAECgIIAQABAAAAAA==.Noctaurus:BAAANQADCgcIEAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggIAgAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFH8QAAIGAAcKlhC5CAC+AQAGAAcKlhC5CAC+AQA1AAQKf0UAAwYACgoHJKQkADIDAAYACgoHJKQkADIDAAsABgq6GmkdAIUBAAAA.',
Ny='Nyuxx:BAAANQAECgEIAgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAABNQAECn8aAAIGAAoK+wWdCwELAQAGAAoK+wWdCwELAQAAAA==.',
Og='Ogsmallz:BAAANQADCggICwAAAA==.',
Ol='Olenza:BAAANQADCgcIEwAAAA==.',
Or='Orangewhale:BAABNQAECn8lAAIRAAoKVCR1CQAuAwARAAoKVCR1CQAuAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAABNQAECn8UAAIiAAgKkgmu2gA4AQAiAAgKkgmu2gA4AQAAAA==.',
Pa='Pallybob:BAAANQAECgMIBAABNQAECgUIBAABAAAAAA==.Pavo:BAABNQAECn8fAAMRAAgKOQ9zLgCnAQARAAgKOQ9zLgCnAQAPAAMKYAZ4lQCCAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBAABNQAECgoKKQADAMojAA==.Peycicle:BAABNQAECn8pAAIDAAoKyiO7FgB4AwADAAoKyiO7FgB4AwAAAA==.Peysecretion:BAAANQAECggICQABNQAECgoKKQADAMojAA==.Peystruction:BAAANQADCgYIDAABNQAECgoKKQADAMojAA==.Peytan:BAAANQAECgUIBQABNQAECgoKKQADAMojAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAABNQAECn8mAAMCAAoKBASyHwDsAAACAAoK3QOyHwDsAAAjAAYKZgLtBwCuAAAAAA==.',
Pi='Pippa:BAABNQAECn8iAAIkAAgKwRadHQD1AQAkAAgKwRadHQD1AQAAAA==.',
Pl='Planett:BAABNQAECn8wAAMcAAoKpBeOVAAVAgAcAAoKpBeOVAAVAgAHAAkK9Qy0hQADAQAAAA==.',
Po='Poetuck:BAABNQAECn9KAAMCAAoK8w3LDADqAQACAAkK7Q3LDADqAQADAAkKZgqSdADGAQAAAA==.Pokeylight:BAAANQABCgUIBwAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proko:BAABNQAECn8jAAMHAAoKyAhkeQAhAQAHAAoKyAhkeQAhAQAcAAIKbAXlBgFaAAAAAA==.',
Qa='Qatka:BAAANQADCgcIDwAAAA==.',
Qu='Quiver:BAAANQAECgEIAgAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAABNQAECn8pAAIcAAgK7iERLgBqAgAcAAgK7iERLgBqAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgcIDgABNQAECgIIAQABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.Rayforn:BAAANQAECggICAAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgYICgABNQAECgoKJgADAGofAA==.Renarron:BAEANQAECgMIAwABNQAECgYIEQABAAAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.Reyas:BAAANQAECgYIDAAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBgAAAA==.Rossa:BAAANQAECgcIDgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECn9BAAMVAAoKCibpAwDJAwAVAAoKCibpAwDJAwAZAAQKUx6gMADsAAAAAA==.',
Sa='Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAABNQAECn8XAAIOAAkK5x40GAC7AgAOAAkK5x40GAC7AgAAAA==.Sarthrity:BAAANQAFFAEIAgAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Schweinstigr:BAAANQABCgIIAQAAAA==.Scootsy:BAABNQAECn8WAAIDAAkKpA/owgD+AQADAAkKpA/owgD+AQAAAA==.',
Se='Seirin:BAABNQAECn8pAAIlAAgKSxdBSwALAgAlAAgKSxdBSwALAgAAAA==.Seldiane:BAAANQADCggIGAAAAA==.Selendaa:BAABNQAECn8nAAIcAAYKwgz1nQDjAAAcAAYKwgz1nQDjAAAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQAECgMIBQAAAA==.Shamalamadd:BAABNQAECn8uAAMcAAoKiRNtPwAXAgAcAAoKiRNtPwAXAgAHAAEKmwSTBQEvAAAAAA==.Shammology:BAABNQAECn8bAAMcAAoKGBexNgA/AgAcAAoKGBexNgA/AgAHAAEKAAAWXwEaAAAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAACNQAFFH8JAAMMAAQK9QhGFwDMAAAMAAQK9QhGFwDMAAAOAAIKvgH8GQBvAAA1AAQKfzAAAw4ACgrKFVQ9ANoBAA4ACQrFDFQ9ANoBAAwACgoQFbEfANIBAAAA.Sheri:BAABNQAECn8vAAIDAAoKQxx5JQCpAgADAAoKQxx5JQCpAgAAAA==.Shiroro:BAAANQAECgUIBQAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECn8xAAMCAAoKhhteDAD1AQACAAkKCBteDAD1AQADAAYKORHj9wCcAQAAAA==.Shockless:BAABNQAECn8aAAMHAAkKSA7rlgBrAQAHAAgKIQ3rlgBrAQAcAAEKnQElNQEbAAAAAA==.Shotowkhaan:BAAANQAECgUICQAAAA==.Shotowkhann:BAABNQAECn8wAAIlAAkKGBa0SQARAgAlAAkKGBa0SQARAgAAAA==.',
Si='Sigmaboss:BAAANQAECgQIAgAAAA==.Silentpebble:BAABNQAECn8vAAMMAAoKahL/PwD9AQAMAAoKahL/PwD9AQAOAAMKpwf+iQCJAAAAAA==.Sillygoose:BAACNQAFFH8LAAMDAAUKKAoOOADlAAADAAMKGA4OOADlAAACAAIKNwbnFABJAAA1AAQKfyYAAwMACgqFGxd6AIoCAAMACgrJGhd6AIoCAAIAAgq4F3MvAIQAAAAA.Sinderella:BAAANQADCgYIBgAAAA==.Sinïster:BAAANQAECgUIBQABNQAECgoKNgAKAHQgAA==.',
Sk='Skalar:BAAANQAECgQIBAAAAA==.Skodah:BAABNQAECn8aAAMRAAgKExdKIQDvAQARAAgKExdKIQDvAQAPAAEKaQc2jAAxAAABNQAECgoKNgAKAHQgAA==.Skodoh:BAAANQADCgEIAQABNQAECgoKNgAKAHQgAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQAECgkJIQAVAGYKAA==.',
Sq='Squarey:BAAANQAECgUIDgAAAA==.',
St='Stell:BAAANQAECggIDAAAAA==.Stinch:BAAANQAECgUIBgABNQAECgoKKgAHAJ8ZAA==.Stovik:BAACNQAFFH8HAAIUAAMKyRmLBAD0AAAUAAMKyRmLBAD0AAA1AAQKf0oAAxQACgqjJHECAIUDABQACgqjJHECAIUDABwAAwqMEnEFAV0AAAAA.',
Sv='Sventhebrave:BAAANQAECgQICwAAAA==.',
Sw='Sweeneytod:BAAANQABCgYIBgAAAA==.',
Sy='Sykill:BAAANQAECgEIAQAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Talena:BAAANQAECgMIAgAAAA==.Talleral:BAABNQAECn8XAAIlAAcK2xXKbQDUAQAlAAcK2xXKbQDUAQAAAA==.Tarkag:BAAANQABCggICgAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECn89AAIFAAoKuRR7BQApAgAFAAoKuRR7BQApAgAAAA==.',
Te='Temaman:BAAANQAECgIIAgABNQAECggIFAAJAIwKAA==.Temamañ:BAAANQAECgYIBQABNQAECggIFAAJAIwKAA==.Terasha:BAAANQAECgcIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.Thicctail:BAAANQADCgQIBAAAAA==.Thraedon:BAAANQADCgcIBwAAAA==.',
Ti='Timaeus:BAABNQAECn8gAAICAAoKvBRcDAD2AQACAAoKvBRcDAD2AQAAAA==.Tinder:BAAANQADCgYIBQABNQAECgoKMwAWAHQmAA==.',
Tm='Tmb:BAAANQADCgMIAwAAAA==.Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokhar:BAAANQAECgUIBQAAAA==.Tokën:BAAANQADCgEIAQAAAA==.Torrick:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAABNQAECn8hAAIVAAYKhgWY8wDJAAAVAAYKhgWY8wDJAAAAAA==.',
Tw='Twirlwind:BAABNQAECn8dAAImAAkK/CPuAwBVAwAmAAkK/CPuAwBVAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECn83AAIDAAoKABYQVAAWAgADAAoKABYQVAAWAgAAAA==.',
Va='Valkyl:BAAANQADCgIIAwAAAA==.Valkyll:BAAANQADCgIIAwAAAA==.Valorash:BAABNQAECn9PAAMGAAkKyCEFOgDpAgAGAAkKyCEFOgDpAgALAAkKoQ+CJABKAQAAAA==.Valorious:BAAANQADCgQIBgAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgkJTwAGAMghAA==.Vampirilla:BAAANQADCgQIBQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velindris:BAAANQAECgMIAwAAAA==.Velinnari:BAABNQAECn8jAAIIAAgKsA+MKQA4AQAIAAgKsA+MKQA4AQAAAA==.Velintha:BAAANQAECgQIBgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIAwAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voidshatter:BAAANQADCgUICgAAAA==.Vonderick:BAAANQABCgcICQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Vy='Vysa:BAAANQADCgQIBAAAAA==.',
Wa='Wargasm:BAAANQADCgYIBgABNQAECgQIDQABAAAAAA==.Warrstomp:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAABNQAECn8aAAIGAAYKXxCI+AD1AAAGAAYKXxCI+AD1AAAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCggIEwAAAA==.',
Yr='Yrelya:BAAANQABCgEIAQAAAA==.',
Yu='Yuji:BAABNQAECn8bAAIGAAgKQghK9gAxAQAGAAgKQghK9gAxAQAAAA==.Yumyum:BAAANQADCgYIBgAAAA==.',
Za='Zalectra:BAABNQAECn8wAAMVAAoK2SDsIgCzAgAVAAoK2SDsIgCzAgAZAAUKagpFUADrAAAAAA==.Zamasû:BAAANQADCgcIDgAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zelila:BAAANQAECgQIDgAAAA==.',
Zo='Zoioz:BAABNQAECn8iAAIKAAkKKQvOYwCNAQAKAAkKKQvOYwCNAQAAAA==.Zomber:BAAANQADCgQIBAAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIAgABNQAECgoKMAADAG8XAA==.',
['Ðø']='Ðøpeßøii:BAAANQABCggIEwAAAA==.',
['Ón']='Ónix:BAAANQAECgQIAgAAAA==.',
['Öd']='Ödínn:BAAANQAECgQIDQAAAA==.',
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
