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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Paladin-Retribution','Mage-Arcane','Mage-Frost','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Hunter-BeastMastery','Druid-Balance','Druid-Guardian','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Mage-Fire','Evoker-Preservation','Priest-Holy','Warrior-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=53,date='2026-10-13',data={Ae='Aecch:BAAANQADCgQIBAAAAA==.',
Ai='Ailira:BAAANQAECgYICAABNQAECgUJCQABAAAAAA==.',
Ak='Akasha:BAAANQADCgQIBQAAAA==.',
Al='Alexzandrite:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Alliethra:BAAANQAECgQIBAAAAA==.',
Am='Amaryllis:BAAANQADCgMJAwAAAA==.Aminall:BAAANQADCgMIAwAAAA==.',
An='Anaboloholic:BAAANQABCgYIDAAAAA==.Anauthaho:BAAANQADCgUIBQAAAA==.Andore:BAAANQAECgUICAAAAA==.Angrybutch:BAAANQAECgYIDQAAAA==.Angrymurloc:BAAANQAECgEIAQAAAA==.Antilles:BAAANQADCgIIAgAAAA==.Antoer:BAAANQAECgYIDQAAAA==.',
Aq='Aquanox:BAAANQADCgYIBgAAAA==.',
Ar='Arbor:BAAANQABCgUIBQAAAA==.Arthaz:BAAANQADCgEIAQAAAA==.',
As='Ashamael:BAAANQADCggICQAAAA==.Asonnari:BAAANQADCgUJCgAAAA==.',
At='Atreana:BAABNQAECn8mAAICAAgKQhcqbwANAgACAAgKQhcqbwANAgAAAA==.Attykus:BAAANQAECgUIBAAAAA==.',
Av='Avalerion:BAABNQAECn8kAAIDAAkKXBmSRwC7AgADAAkKXBmSRwC7AgAAAA==.Avij:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ay='Ayrlyn:BAAANQAECgUICQAAAA==.',
['Añ']='Añathema:BAAANQAECgEJAQAAAA==.',
Ba='Baldd:BAABNQAECn8hAAMEAAkKKhZyawCnAgAEAAkKsBRyawCnAgAFAAEKbCHjNQBiAAAAAA==.Balthor:BAAANQAECgUIBgAAAA==.',
Be='Bearlyhealz:BAAANQAECgUIEQABNQAECgYIEQABAAAAAA==.Beechni:BAAANQAECgYJBgAAAA==.Belgarde:BAAANQADCgUIBQAAAA==.',
Bi='Bigpoppapump:BAAANQADCggICAAAAA==.Biological:BAAANQAECgQIBQAAAA==.Bismo:BAAANQAECgIIAQAAAA==.',
Bl='Blind:BAAANQAECgQIBQAAAA==.Bluwhale:BAAANQAECgYICQAAAA==.',
Bo='Bormor:BAAANQAECgMIAwAAAA==.Bosambosia:BAAANQADCgYIBwABNQADCgYIDAABAAAAAA==.Bowdacious:BAAANQADCgcIDAAAAA==.',
Br='Brainpath:BAAANQABCgcICAAAAA==.Brasidias:BAAANQABCgMIAwAAAA==.Brickingkeys:BAABNQAECn8gAAMEAAkKFB8ThQBzAgAEAAcKMh4ThQBzAgAFAAIKSSHWJwCyAAAAAA==.Brumak:BAAANQADCgYICwAAAA==.Bruno:BAABNQAECn8tAAMGAAkKYBkdEgB9AgAGAAkKYBkdEgB9AgADAAEKAACWrAEuAAAAAA==.',
Bu='Budthespud:BAAANQADCgYICwAAAA==.Bunnynoodle:BAAANQADCgIIAgAAAA==.Burland:BAABNQAECn8ZAAQHAAkK8gu5GQAJAgAHAAkKqAq5GQAJAgAIAAEKRxcXGgA/AAAJAAEKWwuznQA4AAAAAA==.',
Bw='Bwonshogdi:BAAANQAECgYICQAAAA==.',
['Bá']='Báthory:BAAANQAECgEIAQAAAA==.',
Ca='Caedus:BAAANQABCgUIBQAAAA==.Caladin:BAABNQAECn8fAAIGAAkK3hk8EACXAgAGAAkK3hk8EACXAgAAAA==.Calemental:BAAANQADCgIJAQABNQAECgkJHwAGAN4ZAA==.Callistos:BAAANQAECgEIAQABNQAECgkJHwAGAN4ZAA==.Caris:BAAANQADCgUICAAAAA==.Carnar:BAEANQAECgQIBQABNQAECgYIEQABAAAAAA==.Castianna:BAAANQAECgIIAgAAAA==.',
Ce='Ceforium:BAAANQAECgYIBgABNQAECggIFwAKABoiAA==.Century:BAABNQAECn8gAAQLAAcKTxO2SQC9AQALAAcKTxO2SQC9AQAMAAUKqgl6PgC7AAANAAMKgAymWwCUAAAAAA==.',
Ch='Chewbaulk:BAAANQADCgEIAQAAAA==.Chubbysnackz:BAAANQADCggIFQAAAA==.Chug:BAABNQAECn8bAAIOAAgKQCA5FgCbAgAOAAgKQCA5FgCbAgAAAA==.',
Ci='Circa:BAABNQAECn8cAAMEAAcKeQ9s3ADMAQAEAAcKeQ9s3ADMAQAFAAEKYwnxQwA6AAAAAA==.Cithrel:BAAANQAECgcIEgAAAA==.Cizin:BAAANQADCgcIBwAAAA==.',
Cl='Clauadris:BAAANQADCgQIBwAAAA==.Claylemian:BAAANQADCgQIBAAAAA==.Cloak:BAAANQAECgQIBAAAAA==.Cloudninelol:BAAANQADCgUIBQAAAA==.',
Co='Coriko:BAABNQAECn8cAAIPAAgKeAgtGwCsAQAPAAgKeAgtGwCsAQAAAA==.',
Cr='Crocklock:BAAANQAECgIJBAAAAA==.',
Cu='Cured:BAAANQADCgMIAwAAAA==.',
Da='Dakkenz:BAAANQADCgUIBQAAAA==.Dallia:BAAANQAECgIIAwAAAA==.Dalyrimple:BAAANQADCggIHQAAAA==.Damnatio:BAABNQAECn8lAAIDAAkKOCW5BADTAwADAAkKOCW5BADTAwAAAA==.Darkclement:BAAANQAECgUIEwAAAA==.Darksworn:BAAANQADCgMIAQAAAA==.Daskapital:BAAANQAECgIIAgAAAA==.Davrimbasher:BAAANQADCgMIAwAAAA==.',
De='Deadchaos:BAAANQADCggICAAAAA==.Deathbybob:BAAANQADCggIHwAAAA==.Deckard:BAABNQAECn8XAAIKAAcKGiLmQACmAgAKAAcKGiLmQACmAgAAAA==.Deeper:BAAANQAECgQICQAAAA==.Demonofwar:BAAANQADCgUICwABNQAECgkJJAAQAOglAA==.Derese:BAAANQADCggICAAAAA==.Detroll:BAAANQADCgMJAwAAAA==.Dezzii:BAAANQAECgUIAgAAAA==.',
Di='Divineblood:BAAANQAECgIIAgAAAA==.',
Dm='Dmaan:BAABNQAECn8dAAIRAAkKXST0BACPAwARAAkKXST0BACPAwAAAA==.',
Do='Doomflower:BAAANQAECgIIAgAAAA==.',
Dr='Drekzin:BAAANQABCgMIAwAAAA==.Drhealalot:BAAANQAECgMIBAAAAA==.Drugar:BAABNQAECn8fAAMRAAgK+x++JwBVAgARAAgKkx2+JwBVAgASAAcKhR0pNwBHAgABNQAFFAUIDQAHAN8bAA==.',
Du='Dumparooski:BAAANQAECggICgABNQAECgkJHgATAF8UAA==.Durabull:BAAANQADCggJGwAAAA==.',
Ea='Earthvoodoo:BAAANQAECgIIAgAAAA==.',
Eb='Ebonlight:BAAANQADCggICAAAAA==.',
Ed='Edrin:BAAANQABCgIIAgAAAA==.',
Ei='Eithelis:BAAANQADCgUIBQAAAA==.',
El='Eladar:BAAANQADCggICAAAAA==.Elezel:BAAANQADCgIIAwAAAA==.',
En='Ender:BAAANQAECgUIBwAAAA==.',
Ep='Ephrael:BAAANQAECggICAAAAA==.',
Er='Erniethemonk:BAAANQAECgUICQAAAA==.Ernietheorc:BAAANQAECgUICAAAAA==.',
Eu='Eurytos:BAABNQAECn8aAAIKAAcKnh6oXABcAgAKAAcKnh6oXABcAgAAAA==.Euthanize:BAAANQAECgMIBQAAAA==.',
Ev='Evianda:BAAANQADCgYIEAAAAA==.Evilissereni:BAAANQABCgUIBgAAAA==.',
Ez='Ezéé:BAAANQAECgEIAgAAAA==.',
Fa='Falsetto:BAAANQADCgEIAQAAAA==.Faramír:BAAANQAECgUIAgAAAA==.Farrago:BAAANQADCgYIDQAAAA==.',
Fe='Fennek:BAAANQAECgYIDQAAAA==.Feorio:BAAANQAECgUIEQABNQAECgYIDgABAAAAAA==.',
Fi='Finniessa:BAAANQADCgMIAwAAAA==.Fists:BAAANQABCgYICQAAAA==.',
Fm='Fmzmage:BAAANQABCggIEgAAAA==.',
Ga='Garaylo:BAACNQAFFH8bAAIDAAcKXyAcAQC6AgADAAcKXyAcAQC6AgA1AAQKfyoAAgMACApjJhIWAGsDAAMACApjJhIWAGsDAAAA.',
Ge='Geoffreys:BAAANQAECgQIBwAAAA==.Geroendor:BAAANQAECgEIAQAAAA==.',
Gh='Ghorianha:BAAANQADCgQICAAAAA==.Ghosst:BAABNQAECn8pAAQKAAkK6SJREABhAwAKAAkK7SFREABhAwAUAAQKvgyUXACvAAAVAAEK6R7rEABeAAAAAA==.',
Gn='Gnobull:BAAANQADCggICAAAAA==.Gnudgnimish:BAAANQADCgYIDAABNQAECggIKAAWAPwkAA==.',
Go='Goldenknight:BAAANQADCggIDgAAAA==.Gorilon:BAAANQAECggIBAAAAA==.',
Gr='Grimmel:BAAANQAECggIDwAAAA==.Grimmrot:BAAANQADCgQIBAAAAA==.',
Gu='Guildan:BAAANQABCgcIEAAAAA==.Guttris:BAAANQAECgUICQAAAA==.',
Gw='Gwaineelock:BAAANQADCgYIDAAAAA==.Gwyndolyn:BAAANQAECgEJAQAAAA==.',
Ha='Hahalu:BAAANQADCgcIEQAAAA==.Haikusen:BAAANQADCggIDAABNQAECgkJJAAQAOglAA==.Hassan:BAAANQADCgMIBQAAAA==.Haupaa:BAAANQAECgEIAQAAAA==.',
He='Heisenberger:BAAANQABCgEIAQAAAA==.Heliòs:BAAANQADCgMIBAAAAA==.Hemolele:BAAANQADCggIEAAAAA==.Hesseth:BAAANQAECgQIBQAAAA==.',
Ho='Hoake:BAAANQADCgYICAAAAA==.Hogshock:BAABNQAECn8XAAQPAAkKrxGsEgA8AgAPAAkKrxGsEgA8AgAXAAMKFwi47QCKAAATAAIKKgUsFwFZAAAAAA==.Holyzel:BAAANQAECgcIEAAAAA==.',
Hs='Hsimingeung:BAAANQADCgUIBQABNQAECggIKAAWAPwkAA==.Hsimingjung:BAABNQAECn8oAAIWAAgK/CRLAwBgAwAWAAgK/CRLAwBgAwAAAA==.Hsimingkung:BAAANQAECgIIAgABNQAECggIKAAWAPwkAA==.',
Hu='Huaka:BAAANQADCggIGgAAAA==.Huh:BAAANQADCgYIBgAAAA==.Humanic:BAAANQADCggIDAAAAA==.Huntari:BAAANQADCgEIAQAAAA==.',
Hy='Hylie:BAABNQAECn8ZAAICAAgKyRIdgADhAQACAAgKyRIdgADhAQAAAA==.',
['Hè']='Hèlla:BAAANQABCgQIBAAAAA==.',
Ic='Icolann:BAABNQAECn8rAAMXAAgK0h7lLgCkAgAXAAgK0h7lLgCkAgATAAUKdxKwowBJAQABNQAECgIIAgABAAAAAA==.',
Il='Illidarie:BAAANQADCgEIAQAAAA==.',
Im='Imadragon:BAAANQAECgQIBAABNQAECgkJHgATAF8UAA==.',
In='Invisibull:BAAANQADCgEIAQAAAA==.Inzi:BAAANQAECgIIAgAAAA==.',
Is='Isparian:BAAANQADCgYIDgAAAA==.Istabthings:BAACNQAFFH8NAAIHAAUK3xt7BQDEAQAHAAUK3xt7BQDEAQA1AAQKfxsAAwcACApoITYKANACAAcACApoITYKANACAAkAAQplFXGZAEIAAAAA.',
Iv='Ivanyr:BAACNQAFFH8SAAIGAAUKShMMBQBgAQAGAAUKShMMBQBgAQA1AAQKfy0AAgYACQofH0sOALQCAAYACQofH0sOALQCAAAA.Ivy:BAAANQABCgIIAgAAAA==.',
Ja='Jackleecher:BAAANQAECgQIBAABNQAECgkJIAAEABQfAA==.Jadebug:BAAANQAECgcIBwAAAA==.Jaime:BAAANQADCgUIBwABNQAECgkJJAAQAOglAA==.',
Je='Jenzö:BAAANQAECggIDAAAAA==.Jesta:BAAANQADCgYJDgAAAA==.',
Ji='Jikiniinki:BAAANQAECgQIBgAAAA==.',
Jo='Joeviben:BAAANQAECgYICQAAAA==.Johnnyretwar:BAAANQAECggIEgAAAA==.Jovian:BAAANQADCgUIDQAAAA==.',
Ju='Jugsy:BAABNQAECn8xAAIEAAkKVyHmGgBqAwAEAAkKVyHmGgBqAwAAAA==.',
['Jë']='Jënzo:BAAANQADCgQIBAABNQAECggIDAABAAAAAA==.',
Ka='Kaikai:BAABNQAECn8iAAQYAAkK8xjKBACGAgAYAAgKFBvKBACGAgACAAkKeBOcXAA+AgAZAAMK5AhmTwCQAAAAAA==.Kaldread:BAAANQAECgIIBQAAAA==.Kaligo:BAABNQAECn8tAAQTAAkKHBbmPgB3AgATAAkKHBbmPgB3AgAPAAcKLgk4HQCJAQAXAAMKHA0z6wCPAAAAAA==.Karshtonson:BAAANQAECggICAAAAA==.Kastiron:BAAANQAECgUJBgAAAA==.Kazrime:BAAANQAECgIIAgAAAA==.',
Ke='Kebsy:BAABNQAECn8dAAQOAAcKWBq2HgA4AgAOAAcKWBq2HgA4AgAWAAEKGQuWMQAuAAAaAAEKMgriTwAnAAAAAA==.Kelaia:BAAANQADCgYJBgAAAA==.Kelements:BAAANQADCgIIAgAAAA==.Kelyessada:BAAANQADCgYIBgAAAA==.Kenergy:BAABNQAECn8eAAIJAAkKVA0+MgAQAgAJAAkKVA0+MgAQAgAAAA==.Kerit:BAAANQABCgIIAgAAAA==.Kess:BAAANQAECgQIBAABNQAECgkJMQAEAFchAA==.Kevonjuravis:BAABNQAECn8aAAMOAAYKvQylQgD9AAAOAAYKPAylQgD9AAAWAAUKbgsiIQDSAAAAAA==.',
Kh='Khalyl:BAAANQAECgQICQAAAA==.',
Ki='Kiandra:BAAANQADCgcIFwAAAA==.Killpain:BAAANQAECgUIDAAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQABCgIIAgAAAA==.Kirå:BAAANQADCgYIDgAAAA==.',
Kl='Klewinsky:BAAANQADCgYICgAAAA==.',
Kr='Krytus:BAAANQADCgIJAgAAAA==.',
Ku='Kungpaochik:BAABNQAECn8eAAMTAAkKXxSENQCeAgATAAkKXxSENQCeAgAXAAEKAAAAAAAAAAAAAA==.',
Ky='Kyarax:BAAANQADCggICQAAAA==.',
Kz='Kzmo:BAAANQAECgEIAgAAAA==.',
Le='Lena:BAAANQADCgYIBgAAAA==.',
Li='Lizzybordan:BAAANQADCgYIDQABNQAECgQIBQABAAAAAA==.',
Lo='Lousanis:BAABNQAECn8aAAISAAYKdwWqigD0AAASAAYKdwWqigD0AAAAAA==.',
Lu='Lucinick:BAAANQAECgQICgAAAA==.Lupercal:BAAANQAECggJBwAAAA==.',
Ma='Mactabilis:BAAANQAECgIIAQABNQAECggIFwAKABoiAA==.Madmartegan:BAAANQABCgMIAwAAAA==.Mariskama:BAAANQADCggIJAAAAA==.Markusthered:BAAANQAECgQIBAAAAA==.Massdestruct:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Maybecolin:BAAANQADCgEJAQAAAA==.Mazza:BAAANQAECgcIDAABNQAECgcIDwABAAAAAA==.',
Mh='Mhelora:BAAANQAECgQIEQAAAA==.',
Mi='Mikenolan:BAAANQADCgcIBwAAAA==.Mimacho:BAAANQAECgUICAAAAA==.Mindmuncher:BAAANQAECgYIDQAAAA==.Minimini:BAAANQAECgQIEgAAAA==.Minnow:BAAANQADCgYIBgAAAA==.',
Mo='Moolin:BAAANQAECgYICQAAAA==.',
Mu='Munder:BAAANQAECgEJAQAAAA==.Murph:BAAANQADCgcJBwAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Mythuneran:BAAANQAECgcIEAAAAA==.',
Na='Naheka:BAAANQADCggIFgAAAA==.Narilka:BAAANQAECgIIAgAAAA==.Naron:BAAANQADCgIIAgAAAA==.',
Ne='Nemini:BAAANQADCggILAAAAA==.Nena:BAABNQAECn8cAAMLAAUKzQvIbQAPAQALAAUKzQvIbQAPAQANAAIKIQbsbwA/AAAAAA==.Nenacurses:BAAANQADCgYIBgABNQAECgUIHAALAM0LAA==.Newfy:BAAANQAECgYICQAAAA==.',
Ni='Nightmoves:BAAANQADCgYIBgAAAA==.Ninjamage:BAAANQADCggIDgAAAA==.Nithendroz:BAAANQAECgQICQAAAA==.Nity:BAAANQAECgEIAQAAAA==.',
No='Nobala:BAAANQADCgQIBAABNQADCgYIDAABAAAAAA==.Noctaurus:BAAANQADCgQJBAAAAA==.Nogini:BAAANQADCgcJBwAAAA==.Nomadhew:BAAANQAECggJCAAAAA==.Noraice:BAAANQABCgQIBwAAAA==.Notagain:BAACNQAFFH8PAAIDAAYKgRBFCADEAQADAAYKgRBFCADEAQA1AAQKfysAAgMACQqRI9UjADMDAAMACQqRI9UjADMDAAAA.',
Ny='Nyuxx:BAAANQAECgEIAgAAAA==.',
Ob='Obake:BAAANQAECgQIBgAAAA==.',
Od='Odphijor:BAABNQAECn8YAAIDAAkKxAX6BwELAQADAAkKxAX6BwELAQAAAA==.',
Og='Ogsmallz:BAAANQADCgcICwAAAA==.',
Ol='Olenza:BAAANQADCgYIDAAAAA==.',
Or='Orangewhale:BAAANQAFFAIIAwAAAA==.Orondrus:BAAANQADCgMIAwAAAA==.',
Ox='Oxidation:BAAANQADCgQIBQAAAA==.',
Oz='Ozsome:BAAANQAECgUIDQAAAA==.',
Pa='Pallybob:BAAANQADCgcICwABNQADCggIHwABAAAAAA==.Pavo:BAABNQAECn8dAAMNAAgKOQ8GLgCnAQANAAgKOQ8GLgCnAQALAAMKYAbakwCCAAAAAA==.',
Pe='Pebbleshifts:BAAANQADCgcICAAAAA==.Peejean:BAAANQAECgEIAQAAAA==.Pey:BAAANQAECgQIBAABNQAECgkJJAAEAKcjAA==.Peycicle:BAABNQAECn8kAAIEAAkKpyMkFgB7AwAEAAkKpyMkFgB7AwAAAA==.Peystruction:BAAANQADCgYIDAABNQAECgkJJAAEAKcjAA==.Peytan:BAAANQAECgUIBQABNQAECgkJJAAEAKcjAA==.',
Ph='Phantasm:BAAANQABCgIIAgAAAA==.Phlox:BAABNQAECn8bAAMFAAcKuQNQHwDsAAAFAAcKewNQHwDsAAAbAAYKZgLTBwCuAAAAAA==.',
Pi='Pippa:BAABNQAECn8cAAIcAAcKBBd/HQD0AQAcAAcKBBd/HQD0AQAAAA==.',
Pl='Planett:BAABNQAECn8dAAMXAAgKRxeDUwAVAgAXAAgKRxeDUwAVAgATAAYKogwrpgBEAQAAAA==.',
Po='Poetuck:BAABNQAECn8kAAIFAAgK6A2hDADqAQAFAAgK6A2hDADqAQAAAA==.Pokeyruler:BAAANQADCgEIAQAAAA==.',
Pr='Pravin:BAAANQADCgIIAgAAAA==.Proko:BAABNQAECn8YAAMTAAcK/Ae+pQBFAQATAAcK/Ae+pQBFAQAXAAIKbAXrAwFaAAAAAA==.',
Qa='Qatka:BAAANQADCgYICAAAAA==.',
Qu='Quiver:BAAANQAECgEIAQAAAA==.Quizmagic:BAAANQADCgMJAwAAAA==.',
Ra='Raein:BAABNQAECn8aAAIXAAcKIR/OPABqAgAXAAcKIR/OPABqAgAAAA==.Rainn:BAAANQAECgQICgAAAA==.Rainnsoul:BAAANQADCgEIAQAAAA==.Ralofurius:BAAANQADCgYIDAAAAA==.Rasril:BAAANQADCgIIAgAAAA==.',
Re='Redrighthand:BAAANQADCgMIAwAAAA==.Relwind:BAAANQADCgQIBAAAAA==.Rename:BAAANQAECgYICgABNQAECgkJIAAEABQfAA==.Reshtargorr:BAAANQABCgEIAQAAAA==.',
Ro='Roskolnikov:BAAANQAECgMIBQAAAA==.Rossa:BAAANQAECgQIBwAAAA==.',
Ru='Ruele:BAAANQAECgIIAgAAAA==.Ruenan:BAABNQAECn8xAAMKAAkK3SXTAwDKAwAKAAkK3SXTAwDKAwAUAAMKDh/VTQD0AAAAAA==.',
Sa='Sanbas:BAAANQAECgQIBQAAAA==.Sapthat:BAAANQAECgcIDAAAAA==.Sarthrity:BAAANQAFFAEIAQAAAA==.Satyrs:BAAANQADCgIIAgAAAA==.Savepebble:BAAANQAECgIIAgAAAA==.',
Sc='Scootsy:BAAANQAECgcIEwAAAA==.',
Se='Seather:BAAANQADCgEIAQAAAA==.Seirin:BAABNQAECn8aAAIdAAcKvg1SggCMAQAdAAcKvg1SggCMAQAAAA==.Seldiane:BAAANQADCggIGAAAAA==.Selendaa:BAAANQAECgUIDwAAAA==.Senadarra:BAAANQADCgYIBgAAAA==.Senastera:BAAANQADCgUIDAAAAA==.Sephandtotem:BAAANQAECgEJAQAAAA==.Sephron:BAAANQAECgIIBQAAAA==.Sethen:BAAANQAECgUIBwAAAA==.',
Sh='Shadowyhog:BAAANQAECgMIAwAAAA==.Shadöwmist:BAAANQADCgQIBAAAAA==.Shamalamadd:BAAANQAECgYIEAAAAA==.Shammology:BAAANQAECgcIDAAAAA==.Shaollyn:BAAANQADCgYICQAAAA==.Shendralar:BAABNQAECn8kAAMJAAkK7RVqPADZAQAJAAkKxQxqPADZAQAHAAcKWRZOHwDSAQAAAA==.Sheri:BAAANQAECgcIEQAAAA==.Shizam:BAAANQADCgYIBgAAAA==.Shlexie:BAABNQAECn8eAAMFAAgKzBk0DAD2AQAFAAcKJBk0DAD2AQAEAAYKORHO9QCdAQAAAA==.Shockless:BAABNQAECn8ZAAMTAAgK3Q3xlABsAQATAAcKZgzxlABsAQAXAAEKnQGvMQEbAAAAAA==.Shotowkhann:BAABNQAECn8bAAIdAAcKNhiaXgABAgAdAAcKNhiaXgABAgAAAA==.',
Si='Sigmaboss:BAAANQADCgQIBAAAAA==.Silentpebble:BAAANQAECgcIEwAAAA==.Sillygoose:BAACNQAFFH8KAAMEAAQKxwv8NgDkAAAEAAMKGA78NgDkAAAFAAEKJQdzFQA/AAA1AAQKfyQAAwQACQoMHSJ5AIwCAAQACQo2HCJ5AIwCAAUAAgq4F+suAIQAAAAA.Sinderella:BAAANQADCgYIBgAAAA==.',
Sk='Skalar:BAAANQAECgMIAwAAAA==.Skodah:BAAANQAECgMIBAABNQAECgYIDgABAAAAAA==.',
So='Somnambula:BAAANQADCgUICgAAAA==.',
Sp='Sprocket:BAAANQADCgIIAgABNQAECgYIDQABAAAAAA==.',
Sq='Squarey:BAAANQAECgUIBQAAAA==.',
St='Stell:BAAANQADCggJJAAAAA==.Stinch:BAAANQADCgcIDAABNQAECgkJHgATAF8UAA==.Stovik:BAACNQAFFH8HAAIPAAMKyRl2BAD4AAAPAAMKyRl2BAD4AAA1AAQKfzUAAw8ACQr9I18CAIYDAA8ACQr9I18CAIYDABcAAgoEFIMCAV0AAAAA.',
Sv='Sventhebrave:BAAANQAECgMIBQAAAA==.',
Sw='Sweeneytod:BAAANQABCgMIAwAAAA==.',
Sy='Sykill:BAAANQAECgEIAQAAAA==.',
Ta='Tahuruk:BAAANQABCgQIBAAAAA==.Takamura:BAAANQADCgUIBQAAAA==.Talena:BAAANQAECgIIAgAAAA==.Talleral:BAAANQAECgYIEgAAAA==.Tamanan:BAAANQADCggIEAABNQADCggIEgABAAAAAA==.Taurgrim:BAAANQADCgQIAwAAAA==.Tavin:BAABNQAECn8fAAIYAAkKGQ6xBgA7AgAYAAkKGQ6xBgA7AgAAAA==.',
Te='Temaman:BAAANQADCggIEgAAAA==.Temamañ:BAAANQADCggIDAABNQADCggIEgABAAAAAA==.Terasha:BAAANQAECgYIBgAAAA==.',
Th='Thealtman:BAAANQADCgUIBQAAAA==.Thegreatmoo:BAAANQADCgQIBAAAAA==.',
Ti='Timaeus:BAABNQAECn8aAAIFAAgKJRUyDAD2AQAFAAgKJRUyDAD2AQAAAA==.Tinder:BAAANQADCgYIBQABNQAECgkJJAAQAOglAA==.',
Tm='Tmbeesknees:BAAANQABCgQIBAAAAA==.',
To='Tokhar:BAAANQADCgYIBgAAAA==.Tokën:BAAANQADCgEIAQAAAA==.',
Tr='Trishi:BAAANQAECgQICwAAAA==.',
Tw='Twirlwind:BAABNQAECn8cAAIeAAgKhyXeAwBVAwAeAAgKhyXeAwBVAwAAAA==.',
Ty='Tydrinor:BAAANQAECgEIAQAAAA==.',
Un='Unoblasto:BAABNQAECn8cAAIEAAgK/hNrrQAmAgAEAAgK/hNrrQAmAgAAAA==.',
Va='Valkyll:BAAANQADCgIIAgAAAA==.Valorash:BAABNQAECn8zAAMDAAgKxx/0OADqAgADAAgKxx/0OADqAgAGAAYKVxFANQA4AQAAAA==.Valorious:BAAANQADCgQIBQAAAA==.Valshadow:BAAANQADCgcIBwABNQAECggIMwADAMcfAA==.Vampirilla:BAAANQADCgEIAQAAAA==.Vatahlia:BAAANQADCggIEQAAAA==.',
Ve='Veleyna:BAAANQAECgIIBAAAAA==.Velinnari:BAAANQAECgUICQAAAA==.Velintha:BAAANQAECgQJBgAAAA==.Ventise:BAAANQADCggIDQAAAA==.',
Vi='Violee:BAAANQAECgMIAwAAAA==.Vision:BAAANQADCgcIBwAAAA==.',
Vo='Vonderick:BAAANQABCgYIBwAAAA==.Voodoodog:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Vy='Vysa:BAAANQADCgQIBAAAAA==.',
Wa='Wargasm:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Warrstomp:BAAANQAECgIIAgAAAA==.',
Wh='Whitewhale:BAAANQAECgYICAAAAA==.',
Xa='Xandaer:BAAANQAECgIIAgAAAA==.Xandaera:BAAANQABCgcICQAAAA==.Xandarion:BAAANQADCggIFAAAAA==.',
Xc='Xcïte:BAAANQAECgEIAwAAAA==.',
Xd='Xd:BAAANQADCgQJBAAAAA==.',
Yo='Yogeta:BAAANQADCgQIBAAAAA==.Yosh:BAAANQADCgIIAgAAAA==.',
Yu='Yuji:BAAANQAECgYIDgAAAA==.',
Za='Zalectra:BAABNQAECn8cAAMKAAgKOSFwNQDIAgAKAAgKOSFwNQDIAgAUAAUKagpkTwDrAAAAAA==.Zamasû:BAAANQADCgUIBwAAAA==.Zarnie:BAAANQABCgEIAQAAAA==.',
Ze='Zedraikis:BAAANQADCgIIAgAAAA==.Zelila:BAAANQAECgQICgAAAA==.',
Zo='Zoioz:BAAANQAECgQIBAAAAA==.Zoras:BAAANQADCggICAAAAA==.',
['Ål']='Ålloria:BAAANQAECgIIAgABNQAECgkJIQAEACoWAA==.',
['Ón']='Ónix:BAAANQAECgQIAgAAAA==.',
['Öd']='Ödínn:BAAANQAECgQIBQAAAA==.',
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
