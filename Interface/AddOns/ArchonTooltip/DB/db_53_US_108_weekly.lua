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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Demonology','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Warlock-Affliction','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Paladin-Holy','Druid-Balance','Druid-Guardian','Druid-Restoration','Monk-Windwalker','Warlock-Destruction','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Monk-Mistweaver','DemonHunter-Havoc','Mage-Fire','Evoker-Preservation','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICQABNQAECgUJCwABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQAECgQIDgAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQAECgEIAgAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAABNQAECn8XAAMCAAYKURfhLgCHAAADAAUKrBa6FwFkAQACAAIKPxnhLgCHAAAAAA==.Angrybutch:BAAANQAECgYIDgAAAA==.Angrymurloc:BAAANQAECgEIAwAAAA==.Antilles:BAAANQADCgIIAgAAAA==.Antoer:BAAANQAECgYIDwAAAA==.',
Aq='Aquanox:BAAANQAECgEIAgAAAA==.',
Ar='Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQAECgcIBwAAAA==.Asonnari:BAAANQAECggICgAAAA==.',
At='Atreana:BAABNQAECn83AAIEAAoK1xYpKAATAgAEAAoK1xYpKAATAgAAAA==.Attykus:BAAANQAECgUICQAAAA==.',
Av='Avalerion:BAABNQAECn82AAIFAAoK7B36JAByAgAFAAoK7B36JAByAgAAAA==.Avij:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ay='Ayrlyn:BAAANQAECggIEwAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAABNQAECn8qAAMDAAoKshQMbQCkAgADAAoKaBMMbQCkAgACAAEKbCGSNgBiAAAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAABNQAECn8UAAMGAAYKNwWhTQDeAAAGAAYKNwWhTQDeAAAHAAQKhAZ5GgCWAAABNQAECgcIFAAIAMYQAA==.Beechni:BAAANQAECgYICQAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQAECgIIAgAAAA==.Biological:BAAANQAECgYICAAAAA==.Biomancer:BAAANQAECgEIAQAAAA==.Bismo:BAAANQAECgIIBAAAAA==.',
Bl='Blind:BAAANQAECgQIBwAAAA==.Bloodsharkds:BAAANQAECgEIAQAAAA==.Bluwhale:BAAANQAECgcIDQAAAA==.',
Bo='Bormor:BAAANQAECgUICAAAAA==.Bosambosia:BAAANQAECgEIAQAAAA==.Bowdacious:BAAANQADCgcIEAAAAA==.',
Br='Brainpath:BAAANQABCggICQAAAA==.Brasidias:BAAANQAECgIIBQAAAA==.Brickingkeys:BAABNQAECn8jAAMDAAoKah8RhgByAgADAAgKyx4RhgByAgACAAIKSSFgKACyAAAAAA==.Brumak:BAAANQAECgIIAwAAAA==.Bruno:BAABNQAECn8+AAMJAAoKTxgECwABAgAJAAoKTxgECwABAgAFAAEKAADbsgEuAAAAAA==.Brödìe:BAAANQADCgIIAgAAAA==.',
Bu='Budthespud:BAAANQADCgYIEAAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECn8ZAAQKAAkK8gv8GQAJAgAKAAkKqAr8GQAJAgALAAEKRxdQGgBAAAAMAAEKWwtboQA4AAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICgAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caedus:BAAANQAECgEIAwAAAA==.Caladin:BAABNQAECn8oAAIJAAoK9htvEACWAgAJAAoK9htvEACWAgAAAA==.Calemental:BAAANQAECgQIBAABNQAECgoKKAAJAPYbAA==.Callistos:BAAANQAECgEIAQABNQAECgoKKAAJAPYbAA==.Camelshammy:BAAANQADCgcIBwAAAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBwABNQAECgcIFAANAD8cAA==.Castianna:BAAANQAECgIIAwAAAA==.',
Ce='Ceforium:BAABNQAECn8ZAAMCAAoKdxL4BQDpAQACAAoKdxL4BQDpAQADAAEKAACPRwEAAAAAAA==.Century:BAABNQAECn8vAAQOAAgKUhNyJQBZAQAOAAgKUhNyJQBZAQAPAAcK4AgeKADPAAAQAAMKgAz8XACUAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECn8cAAIRAAkKEyCIFgCaAgARAAkKEyCIFgCaAgAAAA==.',
Ci='Circa:BAABNQAECn8iAAMDAAgKYQ7q3gDKAQADAAgKYQ7q3gDKAQACAAEKYwnARAA6AAAAAA==.Cithrel:BAABNQAECn8UAAMSAAkKdAcfJQBKAQASAAcKyAcfJQBKAQAEAAMKOAbOKwFmAAAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Clauadris:BAAANQADCggIEgAAAA==.Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBQAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Corban:BAAANQAECggIAgAAAA==.Coriko:BAABNQAECn8jAAITAAoK/Ad2GwCsAQATAAoK/Ad2GwCsAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQAECgEIAQAAAA==.Dallia:BAAANQAECgQICQAAAA==.Dalyrimple:BAAANQAECgEIAQAAAA==.Damnatio:BAABNQAECn8tAAIFAAoKgCXZBADTAwAFAAoKgCXZBADTAwAAAA==.Darkclement:BAABNQAECn8mAAIUAAoK8RqaIABmAgAUAAoK8RqaIABmAgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Darnala:BAAANQAECgEIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQADCgMIAwAAAA==.',
De='Deadchaos:BAAANQAECgEIAQAAAA==.Deathbybob:BAAANQAECgIIBAABNQAECgIIBQABAAAAAA==.Deckard:BAABNQAECn8hAAIUAAkK9CD3QQClAgAUAAkK9CD3QQClAgABNQAECgoKGQACAHcSAA==.Deeper:BAAANQAECgYIEwAAAA==.Demonofwar:BAAANQADCgUICwABNQAECgoKLgAVAFAmAA==.Derese:BAAANQAECgEIAgAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgUICgAAAA==.',
Di='Divineblood:BAAANQAECgMIAwAAAA==.',
Dm='Dmaan:BAABNQAECn8kAAIWAAoKDCQpBQCOAwAWAAoKDCQpBQCOAwAAAA==.',
Do='Doomflower:BAAANQAECgIIAwAAAA==.',
Dr='Drekzin:BAAANQAECgEIAQAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECn8fAAMWAAgK+x+aKABUAgAWAAgKkx2aKABUAgAXAAcKhR2zNwBHAgABNQAFFAYIEgAKAPQWAA==.',
Du='Dumparooski:BAAANQAECggICwABNQAECgkJHgAYAF8UAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Eb='Ebonlight:BAAANQADCggICgAAAA==.',
Ed='Edrin:BAAANQAECgEIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCggICwAAAA==.',
En='Ender:BAAANQAECgUICgAAAA==.',
Ep='Ephrael:BAAANQAECggICgAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAABNQAECn8iAAIUAAgKvR5FXgBbAgAUAAgKvR5FXgBbAgAAAA==.Euthanize:BAAANQAECgMIBwAAAA==.',
Ev='Evianda:BAAANQAECgEIAwAAAA==.Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIBQAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgUICgAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAABNQAECn8ZAAIUAAcKPQoSnwDxAAAUAAcKPQoSnwDxAAAAAA==.Feorio:BAAANQAECgYIEwABNQAECgoKIQANAP8dAA==.',
Fi='Finniessa:BAAANQADCgMIBQAAAA==.Fists:BAAANQAECgEIAQAAAA==.',
Fm='Fmzmage:BAAANQABCggIGAAAAA==.',
Fr='Freetorylanz:BAAANQAECgEIAQAAAA==.',
Ga='Garaylo:BAACNQAFFH8hAAIFAAcKYSI7AQC0AgAFAAcKYSI7AQC0AgA1AAQKfywAAgUACQpZJokWAGoDAAUACQpZJokWAGoDAAAA.',
Ge='Geoffreys:BAAANQAECgQICgAAAA==.Geroendor:BAAANQAECgEIAQAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECn8xAAQUAAoKiSKjEABgAwAUAAoK2SGjEABgAwAZAAQKvgyeXQCvAAAaAAMKkBgkCgCdAAAAAA==.',
Gn='Gnobull:BAAANQAECgEIAQAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgoKLwAbAJUkAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIBQAAAA==.',
Gr='Grimmel:BAAANQAECggIEQAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQAECgEIAQAAAA==.Guttris:BAAANQAECgUIDQAAAA==.',
Gw='Gwaineelock:BAAANQAECgEIAwAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQAECgYIBgAAAA==.Haikusen:BAAANQADCggIDAABNQAECgoKLgAVAFAmAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAAANQAECgQIBgAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQAECgUIBQAAAA==.Hesseth:BAAANQAECggIEwAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECn8XAAQTAAkKrxHmEgA7AgATAAkKrxHmEgA7AgAcAAMKFwho8ACKAAAYAAIKKgUwGwFZAAAAAA==.Holyzel:BAABNQAECn8cAAIFAAoK+RR1ewA0AgAFAAoK+RR1ewA0AgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgoKLwAbAJUkAA==.Hsimingjung:BAABNQAECn8vAAIbAAoKlSRUAwBgAwAbAAoKlSRUAwBgAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgoKLwAbAJUkAA==.',
Hu='Huaka:BAAANQAECgUIBgAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECn8ZAAIEAAgKyRLkgQDhAQAEAAgKyRLkgQDhAQAAAA==.Hymno:BAAANQADCgIIAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECn81AAMcAAoKfR6FLwCjAgAcAAoKfR6FLwCjAgAYAAgKHxKspQBJAQABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQAECgQIBAABNQAECgkJHgAYAF8UAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQAECgUICQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFH8SAAIKAAYK9BYBBwA4AQAKAAYK9BYBBwA4AQA1AAQKfyQAAwoACAqgIksKANACAAoACAqgIksKANACAAwAAQplFcmcAEMAAAAA.Isto:BAAANQADCgcIBwAAAA==.',
Iv='Ivanyr:BAACNQAFFH8YAAIJAAUKohlGAwDyAAAJAAUKohlGAwDyAAA1AAQKfzwAAgkACgpSHYEOALMCAAkACgpSHYEOALMCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgoKIwADAGofAA==.Jadebug:BAAANQAECggIDgAAAA==.Jaime:BAAANQADCgUIBwABNQAECgoKLgAVAFAmAA==.',
Je='Jenzö:BAAANQAECggIEwAAAA==.Jesta:BAAANQADCgYJDgAAAA==.Jeñzo:BAAANQADCgQIBAAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgUICwAAAA==.Johnnyretwar:BAABNQAECn8aAAMNAAoKGiO9CACCAwANAAoKGiO9CACCAwAFAAIKXR+2SQGqAAAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECn87AAIDAAoK6iFfGwBpAwADAAoK6iFfGwBpAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIEwABAAAAAA==.',
Ka='Kaikai:BAACNQAFFH8EAAMIAAEKygckCgBMAAAIAAEKygckCgBMAAAEAAEKVAF6SAA4AAA1AAQKfzAABAgACgqBGtYEAIYCAAgACgppGdYEAIYCAAQACQp3FBxeAD0CABIAAwrkCNRPAJAAAAAA.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECn87AAQYAAoKgBbwIwDhAQAYAAoKgBbwIwDhAQATAAcKLgmJHQCJAQAcAAMKHA3l7QCPAAAAAA==.Kalistus:BAAANQAECgYIDAAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgUJBwAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECn8lAAQRAAgKdBtrEADfAQARAAgKdBtrEADfAQAbAAEKGQsuMgAuAAAdAAEKMgoLUQAnAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelttoi:BAAANQAECgEIAQAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kendyll:BAAANQAECgEIAgAAAA==.Kenergy:BAABNQAECn8mAAIMAAoKcg07MwAQAgAMAAoKcg07MwAQAgAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kess:BAAANQAECgQIBAABNQAECgoKOwADAOohAA==.Kevonjuravis:BAABNQAECn8pAAMbAAoKpAymDAD7AAAbAAcKnQymDAD7AAARAAoK7wrJKADfAAAAAA==.',
Kh='Khalyl:BAABNQAECn8UAAIeAAYK3hAKOAD0AAAeAAYK3hAKOAD0AAAAAA==.',
Ki='Kiandra:BAAANQAECgUIBgAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kilrah:BAAANQADCgUIBQAAAA==.Kilriella:BAAANQABCgIIAgAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kl='Klewinsky:BAAANQADCggIFAAAAA==.',
Kr='Krixee:BAAANQAECgEIAQAAAA==.Krytus:BAAANQADCgIIAgAAAA==.',
Ku='Kungpaochik:BAABNQAECn8eAAMYAAkKXxRlNgCeAgAYAAkKXxRlNgCeAgAcAAEKAAAAAAAAAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgcIEQABNQAECgQICgABAAAAAA==.',
Lo='Lousanis:BAABNQAECn8gAAIXAAgKAgb0iwD0AAAXAAgKAgb0iwD0AAAAAA==.',
Lu='Lucinick:BAAANQAECgYIEwAAAA==.Lunascare:BAAANQAECgYIBgAAAA==.Lupercal:BAAANQAECggIBwAAAA==.',
Ma='Mactabilis:BAAANQAECgIIAwABNQAECgoKGQACAHcSAA==.Madmartegan:BAAANQABCgMIAwAAAA==.Maeven:BAAANQAECgEIAQAAAA==.Mariskama:BAAANQAECgEIAQAAAA==.Mariuswolff:BAAANQAECgEIAQAAAA==.Markusthered:BAAANQAECgQICQAAAA==.Massdestruct:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mayhemhoiyaa:BAAANQAECgEIAgAAAA==.Mazza:BAAANQAECgcIEAABNQAECgoKFAANAPwWAA==.',
Mh='Mhelora:BAABNQAECn8WAAIQAAUKzg8aMwDWAAAQAAUKzg8aMwDWAAAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAABNQAECn8UAAIDAAcK6RV27QCvAQADAAcK6RV27QCvAQAAAA==.Mindmuncher:BAAANQAECggIDgAAAA==.Minimini:BAABNQAECn8WAAIdAAUKNBHOLQD9AAAdAAUKNBHOLQD9AAAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgcIDAAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQAECgEIAQAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Mythuneran:BAABNQAECn8dAAIDAAoKuhJWWwCbAQADAAoKuhJWWwCbAQAAAA==.',
Na='Naheka:BAAANQAECgcIBwAAAA==.Narilka:BAAANQAECgMIBQAAAA==.Naron:BAAANQAECgEIAgAAAA==.Nazgrogrik:BAAANQADCgEIAQAAAA==.',
Ne='Nemini:BAAANQAECgIICQAAAA==.Nena:BAABNQAECn85AAMOAAkK6gxSIgByAQAOAAkK6gxSIgByAQAQAAIKIQbCcQA/AAAAAA==.Nenacurses:BAAANQAECgQIBwABNQAECgkJOQAOAOoMAA==.Nenafury:BAAANQADCgEIAQABNQAECgkJOQAOAOoMAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAAANQAECgQIEQAAAA==.Nity:BAAANQAECgIIBAAAAA==.',
No='Nobala:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggIAgAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFH8PAAIFAAYKgRC5CAC+AQAFAAYKgRC5CAC+AQA1AAQKfzkAAwUACgrUI6QkADIDAAUACgrUI6QkADIDAAkABgq6GkwQAJoBAAAA.',
Ny='Nyuxx:BAAANQAECgEIAwAAAA==.',
Ob='Obake:BAAANQAECgQIBwAAAA==.',
Od='Odphijor:BAABNQAECn8YAAIFAAkKxAWdCwELAQAFAAkKxAWdCwELAQAAAA==.',
Og='Ogsmallz:BAAANQAECgEIAQAAAA==.',
Ol='Olenza:BAAANQAECgEIAwAAAA==.',
Oo='Oops:BAAANQAECgEIAwAAAA==.',
Or='Orangewhale:BAABNQAECn8cAAIQAAoKVCR1CQAuAwAQAAoKVCR1CQAuAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUIEQAAAA==.',
Pa='Pallybob:BAAANQAECgIIBQAAAA==.Pavo:BAABNQAECn8fAAMQAAgKOQ9zLgCnAQAQAAgKOQ9zLgCnAQAOAAMKYAZ4lQCCAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBQABNQAECgoKKQADAMojAA==.Peycicle:BAABNQAECn8pAAIDAAoKyiO7FgB4AwADAAoKyiO7FgB4AwAAAA==.Peysecretion:BAAANQAECgMIAwABNQAECgoKKQADAMojAA==.Peystruction:BAAANQADCgYIDAABNQAECgoKKQADAMojAA==.Peytan:BAAANQAECgUIBQABNQAECgoKKQADAMojAA==.',
Ph='Phantasm:BAAANQAECgEIAgAAAA==.Phlox:BAABNQAECn8hAAMCAAgKGgSyHwDsAAACAAgK5wOyHwDsAAAfAAYKZgLtBwCuAAAAAA==.',
Pi='Pippa:BAABNQAECn8iAAIgAAgKwRYiDwB+AQAgAAgKwRYiDwB+AQAAAA==.',
Pl='Planett:BAABNQAECn8kAAMcAAoKzxaOVAAVAgAcAAoKzxaOVAAVAgAYAAYKogw7qABDAQAAAA==.',
Po='Poetuck:BAABNQAECn81AAMCAAoK5gzLDADqAQACAAkK7Q3LDADqAQADAAkKRAW+aAB3AQAAAA==.Pokeylight:BAAANQABCgUIBwAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proko:BAABNQAECn8eAAMYAAgKxwfOpwBEAQAYAAgKxwfOpwBEAQAcAAIKbAXlBgFaAAAAAA==.',
Qa='Qatka:BAAANQAECgEIAQAAAA==.',
Qu='Quiver:BAAANQAECgEIAgAAAA==.Quizmagic:BAAANQAECgEIAwAAAA==.',
Ra='Raein:BAABNQAECn8eAAIcAAcKUR+MPQBpAgAcAAcKUR+MPQBpAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.Rayforn:BAAANQADCgQIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgYICgABNQAECgoKIwADAGofAA==.Renarron:BAEANQAECgQIBAABNQAECgcIFAANAD8cAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.Reyas:BAAANQADCgMIAwAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBwAAAA==.Rossa:BAAANQAECgUIDQAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECn89AAMUAAoKpiXpAwDJAwAUAAoKpiXpAwDJAwAZAAQKTR7eIQDuAAAAAA==.',
Sa='Sadnapvuli:BAAANQAECgEIAQAAAA==.Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAABNQAECn8UAAIMAAkKyR40GAC7AgAMAAkKyR40GAC7AgAAAA==.Sarthrity:BAAANQAFFAEIAgAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Schweinstigr:BAAANQABCgIIAQAAAA==.Scootsy:BAABNQAECn8WAAIDAAkKpA/owgD+AQADAAkKpA/owgD+AQAAAA==.',
Se='Seather:BAAANQAECgEIAQAAAA==.Seirin:BAABNQAECn8eAAIhAAcKEBPUgwCMAQAhAAcKEBPUgwCMAQAAAA==.Seldiane:BAAANQADCggIGAAAAA==.Selendaa:BAABNQAECn8hAAIcAAYKVQt+cADsAAAcAAYKVQt+cADsAAAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQAECgMIBQAAAA==.Shamalamadd:BAABNQAECn8bAAMcAAkKQBCeggCEAQAcAAkKQBCeggCEAQAYAAEKmwQLygAvAAAAAA==.Shammology:BAAANQAECggIEwAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAACNQAFFH8HAAMKAAMKWgdVFAB+AAAKAAMKWgdVFAB+AAAMAAIKvgH8GQBvAAA1AAQKfywAAwwACgqvFFQ9ANoBAAwACQrFDFQ9ANoBAAoACgqbE7EfANIBAAAA.Sheri:BAABNQAECn8eAAIDAAoKIxM3PQD/AQADAAoKIxM3PQD/AQAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECn8mAAMCAAoK/hleDAD1AQACAAkKgBleDAD1AQADAAYKORHj9wCcAQAAAA==.Shockless:BAABNQAECn8aAAMYAAkKSA7rlgBrAQAYAAgKIQ3rlgBrAQAcAAEKnQElNQEbAAAAAA==.Shotowkhann:BAABNQAECn8iAAIhAAgKRhb1SwCBAQAhAAgKRhb1SwCBAQAAAA==.',
Si='Sigmaboss:BAAANQAECgQIBAAAAA==.Silentpebble:BAABNQAECn8nAAMKAAoKJhLGJQD3AQAKAAoKJhLGJQD3AQAMAAMKpwf+iQCJAAAAAA==.Sillygoose:BAACNQAFFH8LAAMDAAUKKAoOOADlAAADAAMKGA4OOADlAAACAAIKNwbCCwBQAAA1AAQKfyYAAwMACgqFGxd6AIoCAAMACgrJGhd6AIoCAAIAAgq4F3MvAIQAAAAA.Sinderella:BAAANQADCgYIBgAAAA==.',
Sk='Skalar:BAAANQAECgQIBQAAAA==.Skodah:BAAANQAECgUIDwABNQAECgoKIQANAP8dAA==.Skodoh:BAAANQADCgEIAQABNQAECgoKIQANAP8dAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQAECgcIGQAUAD0KAA==.',
Sq='Squarey:BAAANQAECgUICQAAAA==.',
St='Stell:BAAANQAECggICQAAAA==.Stinch:BAAANQAECgEIAgABNQAECgkJHgAYAF8UAA==.Stovik:BAACNQAFFH8HAAITAAMKyRmLBAD0AAATAAMKyRmLBAD0AAA1AAQKf0EAAxMACgpyI3ECAIUDABMACgpyI3ECAIUDABwAAgoEFHEFAV0AAAAA.',
Sv='Sventhebrave:BAAANQAECgQICgAAAA==.',
Sw='Sweeneytod:BAAANQABCgYIBgAAAA==.',
Sy='Sykill:BAAANQAECgEIAgAAAA==.Sylus:BAAANQAECgIIAQAAAA==.',
Ta='Tahuruk:BAAANQAECgEIAgAAAA==.Takamura:BAAANQAECgEIAwAAAA==.Talena:BAAANQAECgMIAgAAAA==.Talleral:BAABNQAECn8XAAIhAAcK2xXKbQDUAQAhAAcK2xXKbQDUAQAAAA==.Tamanan:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Tarkag:BAAANQAECgEIAQAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECn8sAAIIAAoKJxDzAgAIAgAIAAoKJxDzAgAIAgAAAA==.',
Te='Temaman:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.Temamañ:BAAANQAECgUIBgAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.',
Ti='Timaeus:BAABNQAECn8gAAICAAoKvBRcDAD2AQACAAoKvBRcDAD2AQAAAA==.Tinder:BAAANQADCgYIBQABNQAECgoKLgAVAFAmAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokhar:BAAANQAECgEIAQAAAA==.Tokën:BAAANQADCgEIAQAAAA==.Torrick:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAABNQAECn8ZAAIUAAUKHAWj1ACKAAAUAAUKHAWj1ACKAAAAAA==.',
Tw='Twirlwind:BAABNQAECn8dAAIiAAkK/CPuAwBVAwAiAAkK/CPuAwBVAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECn8mAAIDAAoK0BItUwCzAQADAAoK0BItUwCzAQAAAA==.',
Va='Valkyl:BAAANQADCgIIAwAAAA==.Valkyll:BAAANQADCgIIAwAAAA==.Valorash:BAABNQAECn9JAAMFAAkKyCGuGAC6AgAFAAkKyCGuGAC6AgAJAAgKKQ/aHAAVAQAAAA==.Valorious:BAAANQADCgQIBQAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgkJSQAFAMghAA==.Vampirilla:BAAANQADCgQIBQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velindris:BAAANQAECgMIBAAAAA==.Velinnari:BAABNQAECn8YAAIGAAcKWg6KIwDqAAAGAAcKWg6KIwDqAAAAAA==.Velintha:BAAANQAECgYICgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIBAAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voidshatter:BAAANQADCgUIBgAAAA==.Vonderick:BAAANQAECgEIAQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Vy='Vysa:BAAANQADCgQIBAAAAA==.',
Wa='Wargasm:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Warrstomp:BAAANQAECgIIAgAAAA==.',
Wh='Whitewhale:BAAANQAECgYICgAAAA==.',
Xa='Xandaer:BAAANQAECgUIDgAAAA==.Xandaera:BAAANQAECgEIAQAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIBAAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAABNQAECn8WAAIFAAgKUQdK9gAxAQAFAAgKUQdK9gAxAQAAAA==.',
Za='Zalectra:BAABNQAECn8mAAMUAAkKdiCPNgDHAgAUAAkKdiCPNgDHAgAZAAUKagpFUADrAAAAAA==.Zamasû:BAAANQAECgEIAQAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zelila:BAAANQAECgQIEgAAAA==.',
Zo='Zoioz:BAAANQAECgQIEAAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIBgABNQAECgoKKgADALIUAA==.',
['Ón']='Ónix:BAAANQAECgQIBAAAAA==.',
['Öd']='Ödínn:BAAANQAECgQICgAAAA==.',
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
