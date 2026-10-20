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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Mage-Arcane','Mage-Frost','Priest-Shadow','Priest-Discipline','Warlock-Affliction','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Paladin-Holy','Hunter-BeastMastery','Druid-Guardian','Druid-Balance','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Warlock-Destruction','Monk-Mistweaver','Mage-Fire','Evoker-Preservation','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-10-20',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICQABNQAECgUJCwABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQAECgQICQAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQAECgEIAQAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQAECgYIEQAAAA==.Angrybutch:BAAANQAECgYIDgAAAA==.Angrymurloc:BAAANQAECgEIAgAAAA==.Antilles:BAAANQADCgIIAgAAAA==.Antoer:BAAANQAECgcIDgAAAA==.',
Aq='Aquanox:BAAANQAECgEIAgAAAA==.',
Ar='Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQADCggICQAAAA==.Asonnari:BAAANQAECgMIBQAAAA==.',
At='Atreana:BAABNQAECn8uAAICAAkKmxelDQDbAQACAAkKmxelDQDbAQAAAA==.Attykus:BAAANQAECgQICAAAAA==.',
Av='Avalerion:BAABNQAECn8rAAIDAAkKPxvNSAC6AgADAAkKPxvNSAC6AgAAAA==.Avij:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ay='Ayrlyn:BAAANQAECgYICwAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAABNQAECn8nAAMEAAoKnBMMbQCkAgAEAAoKUhIMbQCkAgAFAAEKbCGSNgBiAAAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAABNQAECn8UAAMGAAYKNwWhTQDeAAAGAAYKNwWhTQDeAAAHAAQKhAZ5GgCWAAABNQAECgcIFAAIAMYQAA==.Beechni:BAAANQAECgYJBwAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQAECgEIAQAAAA==.Biological:BAAANQAECgYICAAAAA==.Bismo:BAAANQAECgIIBAAAAA==.',
Bl='Blind:BAAANQAECgQIBwAAAA==.Bluwhale:BAAANQAECgcICgAAAA==.',
Bo='Bormor:BAAANQAECgMIAwAAAA==.Bosambosia:BAAANQAECgEIAQAAAA==.Bowdacious:BAAANQADCggIEAAAAA==.',
Br='Brasidias:BAAANQAECgEIAgAAAA==.Brickingkeys:BAABNQAECn8iAAMEAAoKgx0RhgByAgAEAAgKQBwRhgByAgAFAAIKSSFgKACyAAAAAA==.Brumak:BAAANQAECgIIAgAAAA==.Bruno:BAABNQAECn82AAMJAAoKLhduBADFAQAJAAoKLhduBADFAQADAAEKAADbsgEuAAAAAA==.',
Bu='Budthespud:BAAANQADCgYIEAAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECn8ZAAQKAAkK8gv8GQAJAgAKAAkKqAr8GQAJAgALAAEKRxdQGgBAAAAMAAEKWwtboQA4AAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICgAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caedus:BAAANQAECgEIAgAAAA==.Caladin:BAABNQAECn8jAAIJAAkK3hlvEACWAgAJAAkK3hlvEACWAgAAAA==.Calemental:BAAANQADCgIJAQABNQAECgkJIwAJAN4ZAA==.Callistos:BAAANQAECgEIAQABNQAECgkJIwAJAN4ZAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBwABNQAECgcIFAANAD8cAA==.Castianna:BAAANQAECgIIAwAAAA==.',
Ce='Ceforium:BAAANQAECggIEAABNQAECggIGwAOAGQhAA==.Century:BAABNQAECn8nAAQPAAcKTxOGFADgAAAQAAcKTxN2SgC9AQAPAAcK4AiGFADgAAARAAMKgAz8XACUAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECn8cAAISAAkKEyCIFgCaAgASAAkKEyCIFgCaAgAAAA==.',
Ci='Circa:BAABNQAECn8iAAMEAAgKYQ5kRQAxAQAEAAgKYQ5kRQAxAQAFAAEKYwnARAA6AAAAAA==.Cithrel:BAAANQAECggIEwAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Clauadris:BAAANQADCggIEgAAAA==.Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBQAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Corban:BAAANQAECggIAgAAAA==.Coriko:BAABNQAECn8fAAITAAkK+Ad2GwCsAQATAAkK+Ad2GwCsAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQAECgEIAQAAAA==.Dallia:BAAANQAECgQIBwAAAA==.Dalyrimple:BAAANQADCggIKwAAAA==.Damnatio:BAABNQAECn8pAAIDAAoKPiXZBADTAwADAAoKPiXZBADTAwAAAA==.Darkclement:BAABNQAECn8dAAIOAAoKyRooBACZAgAOAAoKyRooBACZAgAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Darnala:BAAANQAECgEIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQADCgMIAwAAAA==.',
De='Deadchaos:BAAANQAECgEIAQAAAA==.Deathbybob:BAAANQAECgEIAgABNQAECgMIAwABAAAAAA==.Deckard:BAABNQAECn8bAAIOAAgKZCH3QQClAgAOAAgKZCH3QQClAgAAAA==.Deeper:BAAANQAECgQIDQAAAA==.Demonofwar:BAAANQADCgUICwABNQAECgoKKgAUAL8lAA==.Derese:BAAANQAECgEIAgAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgYICAAAAA==.',
Di='Divineblood:BAAANQAECgMIAwAAAA==.',
Dm='Dmaan:BAABNQAECn8gAAIVAAoKKyMpBQCOAwAVAAoKKyMpBQCOAwAAAA==.',
Do='Doomflower:BAAANQAECgIIAwAAAA==.',
Dr='Drekzin:BAAANQAECgEIAQAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECn8fAAMVAAgK+x+aKABUAgAVAAgKkx2aKABUAgAWAAcKhR2zNwBHAgABNQAFFAYIEQAKAPQWAA==.',
Du='Dumparooski:BAAANQAECggICwABNQAECgkJHgAXAF8UAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Eb='Ebonlight:BAAANQADCggICgAAAA==.',
Ed='Edrin:BAAANQAECgEIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCgIIAwAAAA==.',
En='Ender:BAAANQAECgUICgAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAABNQAECn8cAAIOAAgKMxxFXgBbAgAOAAgKMxxFXgBbAgAAAA==.Euthanize:BAAANQAECgMIBwAAAA==.',
Ev='Evianda:BAAANQAECgEIAwAAAA==.Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIBQAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgYICAAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAAANQAECgYIEQAAAA==.Feorio:BAAANQAECgYIEgABNQAECgoKGQANAIYZAA==.',
Fi='Finniessa:BAAANQADCgMIBQAAAA==.Fists:BAAANQAECgEIAQAAAA==.',
Fm='Fmzmage:BAAANQABCggIFgAAAA==.',
Fr='Freetorylanz:BAAANQAECgEIAQAAAA==.',
Ga='Garaylo:BAACNQAFFH8hAAIDAAcKYSI7AQC0AgADAAcKYSI7AQC0AgA1AAQKfysAAgMACQpCI4kWAGoDAAMACQpCI4kWAGoDAAAA.',
Ge='Geoffreys:BAAANQAECgQICgAAAA==.Geroendor:BAAANQAECgEIAQAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECn8tAAQOAAoKiSKjEABgAwAOAAoK2SGjEABgAwAYAAQKvgyeXQCvAAAZAAMKkBjPBgCrAAAAAA==.',
Gn='Gnobull:BAAANQAECgEIAQAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECgkJKwAaAK8kAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIBQAAAA==.',
Gr='Grimmel:BAAANQAECggIEQAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUIDQAAAA==.',
Gw='Gwaineelock:BAAANQAECgEIAgAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQADCgcIGAAAAA==.Haikusen:BAAANQADCggIDAABNQAECgoKKgAUAL8lAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAAANQAECgIIAgAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQADCggIEgAAAA==.Hesseth:BAAANQAECggIDQAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECn8XAAQTAAkKrxHmEgA7AgATAAkKrxHmEgA7AgAbAAMKFwho8ACKAAAXAAIKKgUwGwFZAAAAAA==.Holyzel:BAABNQAECn8ZAAIDAAoK+RR1ewA0AgADAAoK+RR1ewA0AgAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECgkJKwAaAK8kAA==.Hsimingjung:BAABNQAECn8rAAIaAAkKryRUAwBgAwAaAAkKryRUAwBgAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECgkJKwAaAK8kAA==.',
Hu='Huaka:BAAANQAECgEIAQAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECn8ZAAICAAgKyRLkgQDhAQACAAgKyRLkgQDhAQAAAA==.Hymno:BAAANQADCgIIAgAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECn8xAAMbAAkKfx2FLwCjAgAbAAkKfx2FLwCjAgAXAAgKHxLSPQDRAAABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQAECgQIBAABNQAECgkJHgAXAF8UAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQAECgQIBAAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFH8RAAIKAAYK9BbcAgBOAQAKAAYK9BbcAgBOAQA1AAQKfyIAAwoACAqbIrwCAEoCAAoACAqbIrwCAEoCAAwAAQplFcmcAEMAAAAA.',
Iv='Ivanyr:BAACNQAFFH8YAAIJAAUKohniAQAEAQAJAAUKohniAQAEAQA1AAQKfzUAAgkACgpSHYEOALMCAAkACgpSHYEOALMCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgoKIgAEAIMdAA==.Jadebug:BAAANQAECgcICAAAAA==.Jaime:BAAANQADCgUIBwABNQAECgoKKgAUAL8lAA==.',
Je='Jenzö:BAAANQAECggIDQAAAA==.Jesta:BAAANQADCgYJDgAAAA==.Jeñzo:BAAANQADCgQIBAAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgUICwAAAA==.Johnnyretwar:BAABNQAECn8aAAMNAAoKGiO9CACCAwANAAoKGiO9CACCAwADAAIKXR+2SQGqAAAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECn81AAIEAAkKVyFfGwBpAwAEAAkKVyFfGwBpAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIDQABAAAAAA==.',
Ka='Kaikai:BAABNQAECn8pAAQIAAoKtBciAQDKAQACAAkKeBMcXgA9AgAIAAoKexciAQDKAQAcAAMK5AjUTwCQAAAAAA==.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECn8xAAQXAAkKhhfBPwB2AgAXAAkKhhfBPwB2AgATAAcKLgmJHQCJAQAbAAMKHA3l7QCPAAAAAA==.Kalistus:BAAANQAECgYIBgAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgUJBwAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECn8kAAQSAAcKXxsZBQDCAQASAAcKXxsZBQDCAQAaAAEKGQsuMgAuAAAdAAEKMgoLUQAnAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelttoi:BAAANQAECgEIAQAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kendyll:BAAANQAECgEIAQAAAA==.Kenergy:BAABNQAECn8iAAIMAAoK2ww7MwAQAgAMAAoK2ww7MwAQAgAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kess:BAAANQAECgQIBAABNQAECgkJNQAEAFchAA==.Kevonjuravis:BAABNQAECn8dAAMSAAgKtwt0QwD9AAASAAgKYAt0QwD9AAAaAAUKbguCIQDRAAAAAA==.',
Kh='Khalyl:BAAANQAECgYIDAAAAA==.',
Ki='Kiandra:BAAANQAECgQIBAAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kilrah:BAAANQADCgUIBQAAAA==.Kilriella:BAAANQABCgIIAgAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kl='Klewinsky:BAAANQADCggIEQAAAA==.',
Kr='Krixee:BAAANQAECgEIAQAAAA==.Krytus:BAAANQADCgIIAgAAAA==.',
Ku='Kungpaochik:BAABNQAECn8eAAMXAAkKXxRlNgCeAgAXAAkKXxRlNgCeAgAbAAEKAAAAAAAAAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgYIEAABNQAECgQICQABAAAAAA==.',
Lo='Lousanis:BAABNQAECn8dAAIWAAcKtgX0iwD0AAAWAAcKtgX0iwD0AAAAAA==.',
Lu='Lucinick:BAAANQAECgUIDAAAAA==.Lunascare:BAAANQAECgYIBgAAAA==.Lupercal:BAAANQAECggIBwAAAA==.',
Ma='Mactabilis:BAAANQAECgIIAwABNQAECggIGwAOAGQhAA==.Madmartegan:BAAANQABCgMIAwAAAA==.Maeven:BAAANQAECgEIAQAAAA==.Mariskama:BAAANQAECgEIAQAAAA==.Markusthered:BAAANQAECgQIBQAAAA==.Massdestruct:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mazza:BAAANQAECggIDwABNQAECgcIEAABAAAAAA==.',
Mh='Mhelora:BAABNQAECn8WAAIRAAUKzg/VGwDnAAARAAUKzg/VGwDnAAAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgcIEQAAAA==.Mindmuncher:BAAANQAECgcIDQAAAA==.Minimini:BAABNQAECn8WAAIdAAUKNBHOLQD9AAAdAAUKNBHOLQD9AAAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgcICwAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQAECgEIAQAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Mythuneran:BAABNQAECn8UAAIEAAoKWwuA2QDUAQAEAAoKWwuA2QDUAQAAAA==.',
Na='Naheka:BAAANQADCggIGgAAAA==.Narilka:BAAANQAECgMIAwAAAA==.Naron:BAAANQAECgEIAQAAAA==.Nazgrogrik:BAAANQADCgEIAQAAAA==.',
Ne='Nemini:BAAANQAECgMIBQAAAA==.Nena:BAABNQAECn8rAAMQAAgKWwxTFAA4AQAQAAgKWwxTFAA4AQARAAIKIQbCcQA/AAAAAA==.Nenacurses:BAAANQAECgEIAgABNQAECggIKwAQAFsMAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAAANQAECgQIDQAAAA==.Nity:BAAANQAECgEIAQAAAA==.',
No='Nobala:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggIAgAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFH8PAAIDAAYKgRC5CAC+AQADAAYKgRC5CAC+AQA1AAQKfy8AAgMACgrOIqQkADIDAAMACgrOIqQkADIDAAAA.',
Ny='Nyuxx:BAAANQAECgEIAwAAAA==.',
Ob='Obake:BAAANQAECgQIBwAAAA==.',
Od='Odphijor:BAABNQAECn8YAAIDAAkKxAWdCwELAQADAAkKxAWdCwELAQAAAA==.',
Og='Ogsmallz:BAAANQAECgEIAQAAAA==.',
Ol='Olenza:BAAANQAECgEIAgAAAA==.',
Oo='Oops:BAAANQAECgEIAwAAAA==.',
Or='Orangewhale:BAABNQAECn8VAAIRAAkKWiR1CQAuAwARAAkKWiR1CQAuAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUIEQAAAA==.',
Pa='Pallybob:BAAANQAECgMIAwAAAA==.Pavo:BAABNQAECn8fAAMRAAgKOQ9zLgCnAQARAAgKOQ9zLgCnAQAQAAMKYAZ4lQCCAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBQABNQAECgoKJwAEAO8hAA==.Peycicle:BAABNQAECn8nAAIEAAoK7yG7FgB4AwAEAAoK7yG7FgB4AwAAAA==.Peysecretion:BAAANQADCgQIBAABNQAECgoKJwAEAO8hAA==.Peystruction:BAAANQADCgYIDAABNQAECgoKJwAEAO8hAA==.Peytan:BAAANQAECgUIBQABNQAECgoKJwAEAO8hAA==.',
Ph='Phlox:BAABNQAECn8hAAMFAAgKGgSyHwDsAAAFAAgK5wOyHwDsAAAeAAYKZgLtBwCuAAAAAA==.',
Pi='Pippa:BAABNQAECn8iAAIfAAgKwRZkBACmAQAfAAgKwRZkBACmAQAAAA==.',
Pl='Planett:BAABNQAECn8fAAMbAAgKjRiOVAAVAgAbAAgKjRiOVAAVAgAXAAYKogw7qABDAQAAAA==.',
Po='Poetuck:BAABNQAECn8sAAIFAAkK7Q2TAwCKAQAFAAkK7Q2TAwCKAQAAAA==.Pokeylight:BAAANQABCgUIBwAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proko:BAABNQAECn8eAAMXAAgKxweJQADJAAAXAAgKxweJQADJAAAbAAIKbAXlBgFaAAAAAA==.',
Qa='Qatka:BAAANQAECgEIAQAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQAECgEIAwAAAA==.',
Ra='Raein:BAABNQAECn8eAAIbAAcKUR+MPQBpAgAbAAcKUR+MPQBpAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.Rayforn:BAAANQADCgQIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgYICgABNQAECgoKIgAEAIMdAA==.Renarron:BAEANQAECgQIAwABNQAECgcIFAANAD8cAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBwAAAA==.Rossa:BAAANQAECgUIBwAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECn83AAMOAAoKdSXpAwDJAwAOAAoKdSXpAwDJAwAYAAQKTR4DEQAAAQAAAA==.',
Sa='Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAAANQAECggIDwAAAA==.Sarthrity:BAAANQAFFAEIAgAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Schweinstigr:BAAANQABCgIIAQAAAA==.Scootsy:BAABNQAECn8VAAIEAAgKARDowgD+AQAEAAgKARDowgD+AQAAAA==.',
Se='Seather:BAAANQADCgEIAQAAAA==.Seirin:BAABNQAECn8eAAIgAAcKEBPhQgD/AAAgAAcKEBPhQgD/AAAAAA==.Seldiane:BAAANQADCggIGAAAAA==.Selendaa:BAABNQAECn8bAAIbAAYKJwlVUwC2AAAbAAYKJwlVUwC2AAAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQAECgMIBQAAAA==.Shamalamadd:BAABNQAECn8VAAMbAAgK4BCeggCEAQAbAAgK4BCeggCEAQAXAAEKmwSflgAyAAAAAA==.Shammology:BAAANQAECggIEgAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAABNQAECn8oAAMMAAoKRhRUPQDaAQAMAAkKxQxUPQDaAQAKAAkKoBOxHwDSAQAAAA==.Sheri:BAABNQAECn8UAAIEAAgKzhMs5gC9AQAEAAgKzhMs5gC9AQAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECn8iAAMFAAoK2hheDAD1AQAFAAkKXBheDAD1AQAEAAYKORHj9wCcAQAAAA==.Shockless:BAABNQAECn8aAAMXAAkKSA7rlgBrAQAXAAgKIQ3rlgBrAQAbAAEKnQElNQEbAAAAAA==.Shotowkhann:BAABNQAECn8bAAIgAAcKNhjZXwABAgAgAAcKNhjZXwABAgAAAA==.',
Si='Sigmaboss:BAAANQAECgIIAgAAAA==.Silentpebble:BAABNQAECn8eAAMKAAoKwxAwBgDTAQAKAAoKShAwBgDTAQAMAAMKpwf+iQCJAAAAAA==.Sillygoose:BAACNQAFFH8LAAMEAAUKKAoOOADlAAAEAAMKGA4OOADlAAAFAAIKNwZzBwBVAAA1AAQKfyUAAwQACgoZGhd6AIoCAAQACgpdGRd6AIoCAAUAAgq4F3MvAIQAAAAA.Sinderella:BAAANQADCgYIBgAAAA==.',
Sk='Skalar:BAAANQAECgQIBQAAAA==.Skodah:BAAANQAECgUICAABNQAECgoKGQANAIYZAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQAECgYIEQABAAAAAA==.',
Sq='Squarey:BAAANQAECgUICQAAAA==.',
St='Stell:BAAANQADCggIJAAAAA==.Stinch:BAAANQAECgEIAgABNQAECgkJHgAXAF8UAA==.Stovik:BAACNQAFFH8HAAITAAMKyRmLBAD0AAATAAMKyRmLBAD0AAA1AAQKfzoAAxMACgprI3ECAIUDABMACgprI3ECAIUDABsAAgoEFHEFAV0AAAAA.',
Sv='Sventhebrave:BAAANQAECgQICgAAAA==.',
Sw='Sweeneytod:BAAANQABCgYIBgAAAA==.',
Sy='Sykill:BAAANQAECgEIAgAAAA==.Sylus:BAAANQAECgIIAQAAAA==.',
Ta='Tahuruk:BAAANQAECgEIAgAAAA==.Takamura:BAAANQAECgEIAgAAAA==.Talena:BAAANQAECgMIAgAAAA==.Talleral:BAABNQAECn8XAAIgAAcK2xXKbQDUAQAgAAcK2xXKbQDUAQAAAA==.Tamanan:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Tarkag:BAAANQAECgEIAQAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECn8jAAIIAAoK3g3CBgA7AgAIAAoK3g3CBgA7AgAAAA==.',
Te='Temaman:BAAANQADCggIEgABNQAECgEIAQABAAAAAA==.Temamañ:BAAANQAECgEIAQAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.',
Ti='Timaeus:BAABNQAECn8cAAIFAAoKvBRcDAD2AQAFAAoKvBRcDAD2AQAAAA==.Tinder:BAAANQADCgYIBQABNQAECgoKKgAUAL8lAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokhar:BAAANQADCggIEAAAAA==.Tokën:BAAANQADCgEIAQAAAA==.Torrick:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAABNQAECn8WAAIOAAUKHAXoiwCVAAAOAAUKHAXoiwCVAAAAAA==.',
Tw='Twirlwind:BAABNQAECn8dAAIhAAkK/CPuAwBVAwAhAAkK/CPuAwBVAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECn8iAAIEAAkKIBNvMQBeAQAEAAkKIBNvMQBeAQAAAA==.',
Va='Valkyl:BAAANQADCgIIAgAAAA==.Valkyll:BAAANQADCgIIAwAAAA==.Valorash:BAABNQAECn9AAAMDAAkKaSGvAgD4AgADAAkKaSGvAgD4AgAJAAYKVxECNgA3AQAAAA==.Valorious:BAAANQADCgUIBQAAAA==.Valshadow:BAAANQADCgcIBwABNQAECgkJQAADAGkhAA==.Vampirilla:BAAANQADCgQIBQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velinnari:BAAANQAECgYIDwAAAA==.Velintha:BAAANQAECgQJCQAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIBAAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Voidshatter:BAAANQADCgUIBQAAAA==.Vonderick:BAAANQAECgEIAQAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Vy='Vysa:BAAANQADCgQIBAAAAA==.',
Wa='Wargasm:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Warrstomp:BAAANQAECgIIAgAAAA==.',
Wh='Whitewhale:BAAANQAECgYICgAAAA==.',
Xa='Xandaer:BAAANQAECgUICQAAAA==.Xandaera:BAAANQABCgcICQAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIBAAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgYIEwAAAA==.',
Za='Zalectra:BAABNQAECn8gAAMOAAgKOSGPNgDHAgAOAAgKOSGPNgDHAgAYAAUKagpFUADrAAAAAA==.Zamasû:BAAANQADCgUIBwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zelila:BAAANQAECgQIDQAAAA==.',
Zo='Zoioz:BAAANQAECgYICQAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIBAABNQAECgoKJwAEAJwTAA==.',
['Ón']='Ónix:BAAANQAECgQIBAAAAA==.',
['Öd']='Ödínn:BAAANQAECgQICQAAAA==.',
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
