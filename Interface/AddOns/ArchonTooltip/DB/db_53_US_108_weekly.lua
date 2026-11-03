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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Demonology','Paladin-Retribution','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warlock-Affliction','Druid-Balance','Druid-Guardian','Druid-Restoration','Monk-Windwalker','Warlock-Destruction','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Monk-Mistweaver','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Mage-Fire','Evoker-Preservation','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQAECgQIDQAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQAECgEIAQAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAABNQAECn8cAAMCAAYKURfhLgCHAAADAAUKrBa6FwFkAQACAAIKPxnhLgCHAAAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQAECgIIAwAAAA==.Antilles:BAAANQADCgIIAgAAAA==.Antoer:BAAANQAECgYIDgAAAA==.',
Ap='Aposthmighty:BAAANQADCgIIAgABNQAECgIIBQABAAAAAA==.',
Aq='Aquanox:BAAANQADCgYIBgAAAA==.',
Ar='Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQAECgcIBwAAAA==.Asonnari:BAAANQAECgYIEQAAAA==.',
At='Atreana:BAABNQAECn84AAIEAAoKrBj/MQAZAgAEAAoKrBj/MQAZAgAAAA==.Attykus:BAAANQAECgUIBQAAAA==.',
Av='Avalerion:BAABNQAECn84AAIFAAoK7B3OOABUAgAFAAoK7B3OOABUAgAAAA==.Avij:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
Ay='Ayrlyn:BAABNQAECn8aAAIGAAoK2hTdNgDAAQAGAAoK2hTdNgDAAQAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAABNQAECn8wAAMDAAoKbxcMbQCkAgADAAoKNBcMbQCkAgACAAEKbCGSNgBiAAAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAABNQAECn8UAAMHAAYKNwWhTQDeAAAHAAYKNwWhTQDeAAAIAAQKhAZ5GgCWAAABNQAECgkJHgAJALUQAA==.Beechni:BAAANQAECgYICgAAAA==.Belgarde:BAAANQADCgcICgAAAA==.',
Bi='Bigpoppapump:BAAANQAECgEIAgAAAA==.Biological:BAAANQAECgYIBwAAAA==.Biomancer:BAAANQAECgEIAgAAAA==.Bismo:BAAANQAECgIIAQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bloodsharkds:BAAANQAECgEIAQAAAA==.Bluwhale:BAAANQAECggIDgAAAA==.',
Bo='Bormor:BAAANQAECgUIDAAAAA==.Bowdacious:BAAANQADCgcIFAAAAA==.',
Br='Brainpath:BAAANQABCggICQAAAA==.Brasidias:BAAANQAECgQIBwAAAA==.Brickingkeys:BAABNQAECn8mAAMDAAoKah8RhgByAgADAAgKyx4RhgByAgACAAIKSSFgKACyAAAAAA==.Brumak:BAAANQAECgEIAQAAAA==.Bruno:BAABNQAECn9CAAMKAAoKHBmTDQAdAgAKAAoKHBmTDQAdAgAFAAEKAADbsgEuAAAAAA==.Brödìe:BAAANQAECgEIAQAAAA==.',
Bu='Budthespud:BAAANQADCgYIEAAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECn8ZAAQLAAkK8gv8GQAJAgALAAkKqAr8GQAJAgAMAAEKRxdQGgBAAAANAAEKWwtboQA4AAAAAA==.Burundi:BAAANQADCgUIBQAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caedus:BAAANQAECgEIAQAAAA==.Caladin:BAABNQAECn8qAAIKAAoK9htvEACWAgAKAAoK9htvEACWAgAAAA==.Calemental:BAAANQAECgQIBAABNQAECgoKKgAKAPYbAA==.Callistos:BAAANQAECgEIAQABNQAECgoKKgAKAPYbAA==.Camelshammy:BAAANQAECgEIAgAAAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBQABNQAECgYIEQABAAAAAA==.Castianna:BAAANQAECgIIAgAAAA==.',
Ce='Cebastian:BAAANQADCgcIBwABNQAFFAIIBgAOAGEEAA==.Ceforium:BAABNQAECn8gAAMCAAoKwBIDCAD5AQACAAoKwBIDCAD5AQADAAEKAABCYwEAAAAAAA==.Century:BAABNQAECn84AAQPAAkKzBMWLQBhAQAPAAgKZhMWLQBhAQAQAAgKGQuuKAALAQARAAMKgAz8XACUAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECn8cAAISAAkKEyCIFgCaAgASAAkKEyCIFgCaAgAAAA==.',
Ci='Circa:BAABNQAECn8iAAMDAAgKYQ7q3gDKAQADAAgKYQ7q3gDKAQACAAEKYwnARAA6AAAAAA==.Cithrel:BAABNQAECn8UAAMTAAkKdAcfJQBKAQATAAcKyAcfJQBKAQAEAAMKOAbOKwFmAAAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Clauadris:BAAANQADCggIEgAAAA==.Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAABNQAECn8jAAIUAAoK/Ad2GwCsAQAUAAoK/Ad2GwCsAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQADCgUIBQAAAA==.Dallia:BAAANQAECgQIDgAAAA==.Dalyrimple:BAAANQAECgEIAQAAAA==.Damnatio:BAABNQAECn8vAAIFAAoKgCXZBADTAwAFAAoKgCXZBADTAwAAAA==.Darkclement:BAABNQAECn8uAAIVAAoKfCHhEwDdAgAVAAoKfCHhEwDdAgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQAECgQICAAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQAECgIIAgABNQAECgIIBQABAAAAAA==.Deckard:BAABNQAECn8mAAIVAAkKYiH3QQClAgAVAAkKYiH3QQClAgABNQAECgoKIAACAMASAA==.Deeper:BAABNQAECn8WAAIPAAYK9gI3XwB8AAAPAAYK9gI3XwB8AAAAAA==.Dementos:BAAANQAECgUIBQAAAA==.Demonofwar:BAAANQADCgUICwABNQAECgoKLwAWAGQmAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgUICAAAAA==.',
Di='Divineblood:BAAANQAECgMIAwAAAA==.',
Dm='Dmaan:BAABNQAECn8kAAIXAAoKDCQpBQCOAwAXAAoKDCQpBQCOAwAAAA==.',
Do='Doomflower:BAAANQAECgIIAgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECn8kAAMXAAoKJR6aKABUAgAXAAoKfx2aKABUAgAYAAcKhR2zNwBHAgABNQAFFAYIEgALAPQWAA==.',
Du='Dumparooski:BAAANQAECggIDAABNQAECgoKJAAGANAUAA==.Durabull:BAAANQADCggIGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Eb='Ebonlight:BAAANQADCggIEAAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCggICwAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICgAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAABNQAECn8oAAIVAAgKvR5FXgBbAgAVAAgKvR5FXgBbAgAAAA==.Euthanize:BAAANQAECgMIBQAAAA==.',
Ev='Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgUICAAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAABNQAECn8eAAIVAAcKPQrA2ABPAQAVAAcKPQrA2ABPAQAAAA==.Feorio:BAAANQAECgYIEgABNQAECgoKKgAJAHsfAA==.',
Fi='Finniessa:BAAANQADCgMIBQAAAA==.Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIGAAAAA==.',
Fr='Freetorylanz:BAAANQABCgcICgAAAA==.',
Ga='Garaylo:BAACNQAFFH8hAAIFAAcKYSI7AQC0AgAFAAcKYSI7AQC0AgA1AAQKfzUAAgUACQpaJnwGAFYDAAUACQpaJnwGAFYDAAAA.',
Ge='Geoffreys:BAAANQAECgQIBwAAAA==.Geroendor:BAAANQAECgEIAQAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECn8xAAQVAAoKiSKjEABgAwAVAAoK2SGjEABgAwAZAAQKvgyeXQCvAAAaAAMKkBh5DACaAAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgoKLwAbAJUkAA==.',
Go='Goenitz:BAAANQADCgYIBgAAAA==.Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIDAAAAA==.',
Gr='Grimmel:BAAANQAECggIDwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQAECgEIAgAAAA==.Guttris:BAAANQAECgYICQAAAA==.',
Gw='Gwaineelock:BAAANQAECgEIAgAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQAECgcIDQAAAA==.Haikusen:BAAANQADCggIDAABNQAECgoKLwAWAGQmAA==.Hassan:BAAANQAECgEIAQAAAA==.Haupaa:BAAANQAECgYICQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQAECgUICAAAAA==.Hesseth:BAABNQAECn8aAAIFAAoKNBi7TgAKAgAFAAoKNBi7TgAKAgAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECn8XAAQUAAkKrxHmEgA7AgAUAAkKrxHmEgA7AgAcAAMKFwho8ACKAAAGAAIKKgUwGwFZAAAAAA==.Holyzel:BAABNQAECn8cAAIFAAoK+RR1ewA0AgAFAAoK+RR1ewA0AgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgoKLwAbAJUkAA==.Hsimingjung:BAABNQAECn8vAAIbAAoKlSRUAwBgAwAbAAoKlSRUAwBgAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgoKLwAbAJUkAA==.',
Hu='Huaka:BAAANQAECgUICQAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECn8ZAAIEAAgKyRLkgQDhAQAEAAgKyRLkgQDhAQAAAA==.Hymno:BAAANQADCgIIAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECn81AAMcAAoKfR6FLwCjAgAcAAoKfR6FLwCjAgAGAAgKHxKspQBJAQABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQAECgQIBAABNQAECgoKJAAGANAUAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQAECgQICQAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFH8SAAILAAYK9BanBQDEAQALAAYK9BanBQDEAQA1AAQKfyoAAwsACQp9IXoVAKwCAAsACQp9IXoVAKwCAA0AAQplFcmcAEMAAAAA.Isto:BAAANQADCgcIBwAAAA==.',
Iv='Ivanyr:BAACNQAFFH8aAAIKAAYKtBMzAwAeAQAKAAYKtBMzAwAeAQA1AAQKfz0AAgoACgqAH4EOALMCAAoACgqAH4EOALMCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgoKJgADAGofAA==.Jadebug:BAAANQAECggIDwAAAA==.Jaime:BAAANQAECgEIAQABNQAECgoKLwAWAGQmAA==.',
Je='Jenzö:BAAANQAECggIEgAAAA==.Jesta:BAAANQADCgYJDgAAAA==.Jeñzo:BAAANQADCgQIBAAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgcICgAAAA==.Johnnyretwar:BAABNQAECn8aAAMJAAoKGiO9CACCAwAJAAoKGiO9CACCAwAFAAIKXR+2SQGqAAAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECn9BAAIDAAoKUyNfGwBpAwADAAoKUyNfGwBpAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIEgABAAAAAA==.',
Ka='Kaikai:BAACNQAFFH8GAAMOAAIKYQSdBAByAAAOAAIKYQSdBAByAAAEAAEKVAGSMwAwAAA1AAQKfzcABA4ACgqBGtYEAIYCAA4ACgqLGdYEAIYCAAQACQp3FBxeAD0CABMABArdCtRPAJAAAAAA.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECn8/AAQGAAoK3BbBPwB2AgAGAAoK3BbBPwB2AgAUAAcKLgmJHQCJAQAcAAMKHA3l7QCPAAAAAA==.Kalistus:BAAANQAECgcIDAAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgYICAAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECn8nAAQSAAkKJhp5EQAVAgASAAkKJhp5EQAVAgAbAAEKGQsuMgAuAAAdAAEKMgoLUQAnAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kendyll:BAAANQAECgEIAQAAAA==.Kenergy:BAABNQAECn8qAAINAAoKrw07MwAQAgANAAoKrw07MwAQAgAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kess:BAAANQAECgQIBAABNQAECgoKQQADAFMjAA==.Kevonjuravis:BAABNQAECn8xAAMSAAoKpAxRJABAAQASAAoK7wpRJABAAQAbAAcKnQw7EADvAAAAAA==.',
Kh='Khabriel:BAAANQAECgEIAQAAAA==.Khalyl:BAABNQAECn8aAAIeAAYK3hAUQwDpAAAeAAYK3hAUQwDpAAAAAA==.',
Ki='Kiandra:BAAANQAECgUIBQAAAA==.Killerfrost:BAAANQADCgMIAwAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kilrah:BAAANQADCgUIBQAAAA==.Kilriella:BAAANQABCgIIAgABNQADCggIEAABAAAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kl='Klewinsky:BAAANQADCggIFAAAAA==.',
Kr='Krytus:BAAANQADCgIIAgAAAA==.',
Ku='Kungpaochik:BAABNQAECn8kAAMGAAoK0BRlNgCeAgAGAAoK0BRlNgCeAgAcAAEKAAAAAAAAAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgcIEQABNQAECgUICwABAAAAAA==.',
Lo='Lousanis:BAABNQAECn8gAAIYAAgKAgb0iwD0AAAYAAgKAgb0iwD0AAAAAA==.',
Lu='Lucinick:BAABNQAECn8VAAILAAgK8w6mYAA3AQALAAgK8w6mYAA3AQAAAA==.Lunascare:BAAANQAECgYIBgAAAA==.Lupercal:BAAANQAECggIBwAAAA==.',
Ma='Mactabilis:BAAANQAECgMIAwABNQAECgoKIAACAMASAA==.Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCggIPQAAAA==.Mariuswolff:BAAANQAECgEIAQAAAA==.Markusthered:BAAANQAECgQICAAAAA==.Massdestruct:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mayhemhoiyaa:BAAANQAECgIIBQAAAA==.Mazza:BAABNQAECn8XAAIaAAkKAxWzAwAyAgAaAAkKAxWzAwAyAgABNQAECgoKGwAJAAwbAA==.',
Mh='Mhelora:BAABNQAECn8WAAIRAAUKzg9YPwDOAAARAAUKzg9YPwDOAAAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAABNQAECn8YAAIDAAcK7hd27QCvAQADAAcK7hd27QCvAQAAAA==.Mindmuncher:BAAANQAECgcIDwAAAA==.Minimini:BAAANQAECgUIEwAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgYICgAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Mythuneran:BAABNQAECn8mAAIDAAoKRhMVbQCoAQADAAoKRhMVbQCoAQAAAA==.',
Na='Naheka:BAAANQAECgcIDAAAAA==.Narilka:BAAANQAECgIIBQAAAA==.Naron:BAAANQAECgEIAQAAAA==.Nazgrogrik:BAAANQADCgQIBQAAAA==.',
Ne='Nemini:BAAANQAECgIIBgAAAA==.Nena:BAABNQAECn9DAAMPAAoK4QyNJAChAQAPAAoK4QyNJAChAQARAAIKIQbCcQA/AAAAAA==.Nenacurses:BAAANQAECgQIBwABNQAECgoKQwAPAOEMAA==.Nenafury:BAAANQADCgEIAQABNQAECgoKQwAPAOEMAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAABNQAECn8VAAIfAAYKwgnuFAC5AAAfAAYKwgnuFAC5AAAAAA==.Nity:BAAANQAECgIIBAAAAA==.',
No='Nobala:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Noctaurus:BAAANQADCgYICgAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggIAgAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFH8PAAIFAAYKgRC5CAC+AQAFAAYKgRC5CAC+AQA1AAQKf0IAAwUACgoHJL0bANcCAAUACgoHJL0bANcCAAoABgq6Gr8WAI8BAAAA.',
Ny='Nyuxx:BAAANQAECgEIAgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAABNQAECn8ZAAIFAAoK9wWdCwELAQAFAAoK9wWdCwELAQAAAA==.',
Og='Ogsmallz:BAAANQADCggICwAAAA==.',
Ol='Olenza:BAAANQAECgEIAgAAAA==.',
Or='Orangewhale:BAABNQAECn8lAAIRAAoKVCTkBwAmAwARAAoKVCTkBwAmAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAABNQAECn8UAAIgAAgKkgmu2gA4AQAgAAgKkgmu2gA4AQAAAA==.',
Pa='Pallybob:BAAANQAECgIIBQAAAA==.Pavo:BAABNQAECn8fAAMRAAgKOQ9zLgCnAQARAAgKOQ9zLgCnAQAPAAMKYAZ4lQCCAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBAABNQAECgoKKQADAMojAA==.Peycicle:BAABNQAECn8pAAIDAAoKyiO7FgB4AwADAAoKyiO7FgB4AwAAAA==.Peysecretion:BAAANQAECgMIAwABNQAECgoKKQADAMojAA==.Peystruction:BAAANQADCgYIDAABNQAECgoKKQADAMojAA==.Peytan:BAAANQAECgUIBQABNQAECgoKKQADAMojAA==.',
Ph='Phantasm:BAAANQAECgEIAwAAAA==.Phlox:BAABNQAECn8hAAMCAAgKGgSyHwDsAAACAAgK5wOyHwDsAAAhAAYKZgLtBwCuAAAAAA==.',
Pi='Pippa:BAABNQAECn8iAAIiAAgKwRbAEwB5AQAiAAgKwRbAEwB5AQAAAA==.',
Pl='Planett:BAABNQAECn8nAAMcAAoKpBeOVAAVAgAcAAoKpBeOVAAVAgAGAAYKogw7qABDAQAAAA==.',
Po='Poetuck:BAABNQAECn89AAMCAAoKVg3LDADqAQACAAkK7Q3LDADqAQADAAkKBQmmagCvAQAAAA==.Pokeylight:BAAANQABCgUIBwAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proko:BAABNQAECn8eAAMGAAgKxwfOpwBEAQAGAAgKxwfOpwBEAQAcAAIKbAXlBgFaAAAAAA==.',
Qa='Qatka:BAAANQAECgEIAQAAAA==.',
Qu='Quiver:BAAANQAECgEIAgAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAABNQAECn8lAAIcAAgKCh+MPQBpAgAcAAgKCh+MPQBpAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQAECgEIAgAAAA==.Rasril:BAAANQADCgIIAgAAAA==.Rayforn:BAAANQADCgQIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgYICgABNQAECgoKJgADAGofAA==.Renarron:BAEANQAECgQIBAABNQAECgYIEQABAAAAAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.Reyas:BAAANQAECgUIBwAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBgAAAA==.Rossa:BAAANQAECgUIEgAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECn8/AAMVAAoKCibpAwDJAwAVAAoKCibpAwDJAwAZAAQKUx7tKQDjAAAAAA==.',
Sa='Sadnapvuli:BAAANQAECgEIAQAAAA==.Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAABNQAECn8XAAINAAkK5x40GAC7AgANAAkK5x40GAC7AgAAAA==.Sarthrity:BAAANQAFFAEIAgAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Schweinstigr:BAAANQABCgIIAQAAAA==.Scootsy:BAABNQAECn8WAAIDAAkKpA/owgD+AQADAAkKpA/owgD+AQAAAA==.',
Se='Seather:BAAANQAECgEIAQAAAA==.Seirin:BAABNQAECn8lAAIjAAgKHxLqXgCJAQAjAAgKHxLqXgCJAQAAAA==.Seldiane:BAAANQADCggIGAAAAA==.Selendaa:BAABNQAECn8nAAIcAAYKwgy9hAD0AAAcAAYKwgy9hAD0AAAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQAECgMIBQAAAA==.Shamalamadd:BAABNQAECn8fAAMcAAkKYREwXQBvAQAcAAkKYREwXQBvAQAGAAEKmwRU6AAvAAAAAA==.Shammology:BAABNQAECn8bAAMcAAoKGBdvKQBTAgAcAAoKGBdvKQBTAgAGAAEKAAAWXwEaAAAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAACNQAFFH8JAAMLAAQK9QiBEgDNAAALAAQK9QiBEgDNAAANAAIKvgH8GQBvAAA1AAQKfzAAAw0ACgrKFVQ9ANoBAA0ACQrFDFQ9ANoBAAsACgoQFbEfANIBAAAA.Sheri:BAABNQAECn8gAAIDAAoK8RO1UAD2AQADAAoK8RO1UAD2AQAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECn8tAAMCAAoKUxpeDAD1AQACAAkK1RleDAD1AQADAAYKORHj9wCcAQAAAA==.Shockless:BAABNQAECn8aAAMGAAkKSA7rlgBrAQAGAAgKIQ3rlgBrAQAcAAEKnQElNQEbAAAAAA==.Shotowkhaan:BAAANQAECgQIBAAAAA==.Shotowkhann:BAABNQAECn8oAAIjAAkK7BTPTwDBAQAjAAkK7BTPTwDBAQAAAA==.',
Si='Sigmaboss:BAAANQAECgQIBAAAAA==.Silentpebble:BAABNQAECn8qAAMLAAoKahJNMwDxAQALAAoKahJNMwDxAQANAAMKpwf+iQCJAAAAAA==.Sillygoose:BAACNQAFFH8LAAMDAAUKKAoOOADlAAADAAMKGA4OOADlAAACAAIKNwZgDwBQAAA1AAQKfyYAAwMACgqFGxd6AIoCAAMACgrJGhd6AIoCAAIAAgq4F3MvAIQAAAAA.Sinderella:BAAANQADCgYIBgAAAA==.',
Sk='Skalar:BAAANQAECgQIBAAAAA==.Skodah:BAAANQAECgUIDwABNQAECgoKKgAJAHsfAA==.Skodoh:BAAANQADCgEIAQABNQAECgoKKgAJAHsfAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQAECgcIHgAVAD0KAA==.',
Sq='Squarey:BAAANQAECgUIDQAAAA==.',
St='Stell:BAAANQAECggIDAAAAA==.Stinch:BAAANQAECgQIBAABNQAECgoKJAAGANAUAA==.Stovik:BAACNQAFFH8HAAIUAAMKyRmLBAD0AAAUAAMKyRmLBAD0AAA1AAQKf0oAAxQACgqjJHECAIUDABQACgqjJHECAIUDABwAAwqMEnEFAV0AAAAA.',
Sv='Sventhebrave:BAAANQAECgQICwAAAA==.',
Sw='Sweeneytod:BAAANQABCgYIBgAAAA==.',
Sy='Sykill:BAAANQAECgEIAQAAAA==.Syliste:BAAANQAECgEIAQAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQAECgIIAwAAAA==.Talena:BAAANQAECgMIAgAAAA==.Talleral:BAABNQAECn8XAAIjAAcK2xXKbQDUAQAjAAcK2xXKbQDUAQAAAA==.Tamanan:BAAANQAECgEIAQABNQAECgYIBQABAAAAAA==.Tarkag:BAAANQABCggICgAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECn81AAIOAAoKQROFBAASAgAOAAoKQROFBAASAgAAAA==.',
Te='Temaman:BAAANQAECgIIAgABNQAECgYIBQABAAAAAA==.Temamañ:BAAANQAECgYIBQAAAA==.Terasha:BAAANQAECgcIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.Thicctail:BAAANQAECgEIAQAAAA==.Thraedon:BAAANQADCgcIBwAAAA==.',
Ti='Timaeus:BAABNQAECn8gAAICAAoKvBRcDAD2AQACAAoKvBRcDAD2AQAAAA==.Tinder:BAAANQADCgYIBQABNQAECgoKLwAWAGQmAA==.',
Tm='Tmb:BAAANQADCgMIAwAAAA==.Tmbeesknees:BAAANQAECgEIAQAAAA==.',
To='Tokhar:BAAANQAECgUIBgAAAA==.Tokën:BAAANQADCgEIAQAAAA==.Torrick:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAABNQAECn8dAAIVAAUKHAUWEAHlAAAVAAUKHAUWEAHlAAAAAA==.',
Tw='Twirlwind:BAABNQAECn8dAAIkAAkK/CPuAwBVAwAkAAkK/CPuAwBVAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECn8vAAIDAAoK0xXSSwAFAgADAAoK0xXSSwAFAgAAAA==.',
Va='Valkyl:BAAANQADCgIIAwAAAA==.Valkyll:BAAANQADCgIIAwAAAA==.Valorash:BAABNQAECn9PAAMFAAkKyCGVKQCTAgAFAAkKyCGVKQCTAgAKAAkKoQ9gHABXAQAAAA==.Valorious:BAAANQADCgQIBgAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgkJTwAFAMghAA==.Vampirilla:BAAANQADCgQIBQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velindris:BAAANQAECgMIBAAAAA==.Velinnari:BAABNQAECn8dAAIHAAcKsw6vKwDuAAAHAAcKsw6vKwDuAAAAAA==.Velintha:BAAANQAECgYICAAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIAwAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voidshatter:BAAANQADCgUICgAAAA==.Vonderick:BAAANQABCgcICQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Vy='Vysa:BAAANQADCgQIBAAAAA==.',
Wa='Wargasm:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Warrstomp:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQAECgUIEAAAAA==.Xandaera:BAAANQAECgEIAQAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQAECgEIAQAAAA==.',
Yu='Yuji:BAABNQAECn8aAAIFAAgKQghK9gAxAQAFAAgKQghK9gAxAQAAAA==.',
Za='Zalectra:BAABNQAECn8uAAMVAAoKVCDNHACpAgAVAAoKVCDNHACpAgAZAAUKagpFUADrAAAAAA==.Zamasû:BAAANQAECgEIAQAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zelila:BAAANQAECgQIEAAAAA==.',
Zo='Zoioz:BAABNQAECn8WAAIJAAcKYwdSfQANAQAJAAcKYwdSfQANAQAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIBAABNQAECgoKMAADAG8XAA==.',
['Ón']='Ónix:BAAANQAECgQIAgAAAA==.',
['Öd']='Ödínn:BAAANQAECgUICwAAAA==.',
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
