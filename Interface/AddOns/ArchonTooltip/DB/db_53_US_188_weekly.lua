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

local lookup = {'Warrior-Protection','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Mage-Arcane','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Enhancement','Evoker-Devastation','Priest-Holy','Paladin-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Frost','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAABNQAECoEZAAIBAAgKax8/BwDEAgABAAgKax8/BwDEAgAAAA==.',
Ae='Aedreline:BAAANQADCgYICgABNQAECgUIEAACAAAAAA==.Aevelee:BAAANQAECgQIBgAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.',
Am='Amaria:BAAANQAECgQIBQABNQAECgcIFQADAEoaAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgMIBgAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAABNQAECoElAAIEAAkKCRoSTACJAgAEAAkKCRoSTACJAgAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgEIAQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECgMIBAAAAA==.',
Au='Austenpally:BAAANQAECgQICwAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAAANQAECgcIEAAAAA==.Axegor:BAAANQAECgQIBwAAAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECgYIDAACAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.',
Bi='Biancadelrio:BAAANQAECgQIBwAAAA==.Bigguberment:BAAANQAECgQICAAAAA==.',
Bl='Blackbird:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Bladekrim:BAAANQADCgcICwAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgkJHQAFAFYSAA==.Botia:BAAANQAECgUIDQAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgUICQAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAAANQAECgYIDgAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAAANQAECgUIDwAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAECgkJKgAGANMkAA==.',
Ca='Caenji:BAAANQADCggIFQAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgYIDgACAAAAAA==.',
Ch='Chadgar:BAABNQAECoEdAAIFAAkKVhKTiABTAgAFAAkKVhKTiABTAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECoEoAAMHAAkKRiMdKQAYAgAHAAUKmSQdKQAYAgAIAAUKbSHNHADZAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAECgQIBwABNQAFFAMICAAJAMMRAA==.',
Cl='Close:BAAANQADCgUIBQABNQAECggICAACAAAAAA==.Clouds:BAAANQAECgEIAQABNQAECgQICQACAAAAAA==.',
Co='Conorix:BAAANQADCggIIgAAAA==.Corvo:BAAANQADCggICAABNQAECgYIDgACAAAAAA==.',
Cr='Crataxxis:BAABNQAECoEXAAMJAAgKlgzFNwC/AQAJAAgKlgzFNwC/AQAKAAEKTAOYZQAoAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQACAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECoEbAAILAAcKOx2lDABfAgALAAcKOx2lDABfAgAAAA==.Cythraul:BAAANQAECgYIDgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECggIEQACAAAAAA==.Darrwin:BAAANQAECgUIDQAAAA==.',
De='Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIFwAMAJQWAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgYIDAAAAA==.',
Df='Dfabness:BAABNQAECoEUAAIGAAcKhg55LgBwAQAGAAcKhg55LgBwAQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.',
Dr='Dracthayr:BAABNQAECoEkAAINAAgKhAp0GAChAQANAAgKhAp0GAChAQAAAA==.Dragonhammer:BAAANQAECgcIDAAAAA==.Dreaming:BAAANQAECggICAAAAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAAANQAECgQIBAAAAA==.Drx:BAAANQAECgUIEwAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
El='Elanore:BAABNQAECoEWAAIOAAgKvROASgAeAgAOAAgKvROASgAeAgABNQAECgIIAgACAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIFwAMAJQWAA==.Elison:BAAANQAECgQIBAABNQAECgYIDAACAAAAAA==.Ellaini:BAAANQAECgIIAwAAAA==.Elliana:BAAANQAECgIIAgAAAA==.Ellie:BAAANQAECgEIAgABNQAECggIJgADAL0gAA==.Elloise:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.Elsae:BAABNQAECoEiAAIPAAgK9hM0HQDVAQAPAAgK9hM0HQDVAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAABNQAFFIEFAAIHAAMKgQy3CwDsAAAHAAMKgQy3CwDsAAAAAA==.Everios:BAABNQAECoEgAAIBAAkKFR6tBgDYAgABAAkKFR6tBgDYAgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgIIAgACAAAAAA==.',
Ex='Exodous:BAAANQABCgYIBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgMICQACAAAAAA==.Faytadori:BAABNQAECoEiAAMQAAgKhRkvKQBrAgAQAAgKhRkvKQBrAgARAAMKjgloVgB8AAAAAA==.',
Fe='Felgrrl:BAAANQADCggIJgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAAANQAECgUIDgAAAA==.',
Fl='Fletch:BAAANQAECgYIDwAAAA==.',
Fo='Forever:BAAANQAECggIBwABNQAECggICAACAAAAAA==.',
Fr='Frique:BAAANQADCgYIGgAAAA==.Frozenyogert:BAAANQAECgMIAwAAAA==.',
Ga='Galbur:BAABNQAECoEdAAMSAAkK+BU4MQAuAgASAAkKAhM4MQAuAgATAAcKCRUaYgBiAQAAAA==.Galdrin:BAAANQAECgMICQAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECoEZAAIEAAgKpRZYjwDSAQAEAAgKpRZYjwDSAQAAAA==.',
Ge='Geers:BAAANQAECggIDwAAAA==.Geta:BAAANQAECgUIBgABNQAECgkJGgAUAPgZAA==.Getabrew:BAAANQAECgYICQABNQAECgkJGgAUAPgZAA==.Getacurse:BAAANQAECgUIBQABNQAECgkJGgAUAPgZAA==.Getagrip:BAAANQADCgIIAgABNQAECgkJGgAUAPgZAA==.Getarage:BAABNQAECoEaAAIUAAkK+BnfRQCfAgAUAAkK+BnfRQCfAgAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgkJGgAUAPgZAA==.Getastab:BAAANQAECgQIBAABNQAECgkJGgAUAPgZAA==.',
Gh='Ghil:BAAANQAECgYIEQAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBQAAAA==.Gilia:BAAANQAECgIIBAAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAAANQAECgIIAgAAAA==.',
Go='Goku:BAAANQAECgUIEwAAAA==.Goldiwarlock:BAAANQADCgQIBAAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQICQAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQAECgYIDwAAAA==.',
Gu='Gunderthirth:BAACNQAFFIEMAAIBAAUKMiDjAADkAQABAAUKMiDjAADkAQA1AAQKgR8AAgEACQroJDsCAIMDAAEACQroJDsCAIMDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAAANQAECgUIDQAAAA==.',
Ha='Haan:BAAANQADCgYIBgAAAA==.Haliran:BAAANQAECgEIAQAAAA==.Handsoap:BAAANQAECgYICwAAAA==.Harakhty:BAAANQAECgQIBAAAAA==.Hardhitter:BAABNQAECoEqAAMBAAgK1BbREADsAQABAAcKohjREADsAQAUAAgKewu4ngClAQAAAA==.',
He='Hellstorm:BAAANQABCgYIBgAAAA==.Hellumph:BAAANQAECgYIDQAAAA==.Hevensrath:BAAANQAECgcIEAAAAA==.Hevensreaper:BAAANQAECgQIBgAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggICgABNQAECggIIwAVALceAA==.',
Ho='Hokuden:BAABNQAECoEkAAIVAAgKQBToLwDtAQAVAAgKQBToLwDtAQAAAA==.Holphie:BAAANQAECgEIAQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Horsebananas:BAAANQADCgYIBgABNQAECgYIDwACAAAAAA==.',
Hu='Huddington:BAAANQAECgYICwAAAA==.',
Hy='Hyperion:BAAANQADCgcIGQABNQAECgYIDgACAAAAAA==.',
Ig='Igknight:BAAANQAECgIIAgABNQAECgkJIwADAEsQAA==.',
Il='Ilsi:BAAANQADCgYIBgAAAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwACAAAAAA==.',
In='Indecent:BAAANQAECgcIEQAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECoEgAAIFAAgKaBuHegByAgAFAAgKaBuHegByAgAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECoEcAAQWAAkKhhYpIQAIAgAWAAgKUBUpIQAIAgAXAAMKURWIFADFAAAOAAMKowsMvwClAAAAAA==.Jackieplays:BAABNQAECoElAAQXAAkKfh3YAgDHAgAXAAgKjR7YAgDHAgAOAAkKOhiqOgBbAgAWAAEKNgwubAA1AAAAAA==.Jaded:BAABNQAECoEbAAMYAAgKhBYbSAAWAgAYAAgKhBYbSAAWAgAZAAMKyQr55ACPAAAAAA==.',
Je='Jeses:BAAANQAECgcIDgAAAA==.',
Jo='Jollah:BAAANQAECgUIDQAAAA==.Jorawa:BAAANQADCggICAAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAABNQAECoEmAAIYAAkKzB9zDwAyAwAYAAkKzB9zDwAyAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQACAAAAAA==.Kardas:BAABNQAECoEYAAIaAAcKTwYZqgB+AQAaAAcKTwYZqgB+AQAAAA==.',
Kb='Kbilly:BAABNQAECoEdAAIYAAgKkh4tKwCTAgAYAAgKkh4tKwCTAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFIEFAAIIAAIK6Q6KDQCbAAAIAAIK6Q6KDQCbAAA1AAQKgSYAAggACQoLHOoGAAcDAAgACQoLHOoGAAcDAAAA.',
Ki='Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQADCggICAAAAA==.',
Kn='Knottes:BAAANQABCggIHAAAAA==.',
Kr='Krampus:BAABNQAECoEYAAIMAAgKeQlZFQDpAQAMAAgKeQlZFQDpAQAAAA==.Kranok:BAAANQAECgYIDgAAAA==.Krennthis:BAAANQADCggIDQAAAA==.Krimbruiser:BAAANQADCgYIBwABNQADCgcICwACAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgQIBAAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAAANQAECgYIDgAAAA==.',
Li='Lilguysci:BAAANQAECgMIBAAAAA==.Lizord:BAAANQADCgQIBAAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAABNQAECoEZAAMOAAcKlQQRkwAhAQAOAAcKlQQRkwAhAQAWAAEK2gKydgAmAAAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgcIGAAPAEweAA==.Maddeleine:BAAANQADCgYICQAAAA==.Magara:BAAANQAECgMIAwAAAA==.Magicdemon:BAABNQAECoEYAAIJAAgKBCWjCgBIAwAJAAgKBCWjCgBIAwAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECoEYAAIZAAcKRQwofQB8AQAZAAcKRQwofQB8AQAAAA==.Mansuno:BAABNQAECoEeAAIEAAcKJRvScAAfAgAEAAcKJRvScAAfAgAAAA==.Mapachote:BAAANQAECgUICwAAAA==.Marodin:BAAANQADCggIKwAAAA==.Maynor:BAAANQABCggIDgAAAA==.Mazboda:BAABNQAECoEaAAQbAAcKUxPXnABuAQAbAAYKvhHXnABuAQAcAAIKgBT9GgCHAAAdAAIKugj5XgBdAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECoEcAAIWAAcKcRkFIQAJAgAWAAcKcRkFIQAJAgAAAA==.Merewene:BAAANQAECgQIBAAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECoEaAAIQAAcKjhwuLQBOAgAQAAcKjhwuLQBOAgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUIBQACAAAAAA==.Morgnox:BAAANQAECgIIAgAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necronic:BAAANQAECgIIAwAAAA==.Necroreign:BAABNQAECoEhAAIJAAgKMBhAJgBCAgAJAAgKMBhAJgBCAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAAANQAECgYIDgAAAA==.Nervous:BAAANQAECggIAQABNQAECggICAACAAAAAA==.Nessee:BAAANQAECgQIDgAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIDgAAAA==.Nihowdy:BAABNQAECoEjAAIeAAgKkiHdAgAFAwAeAAgKkiHdAgAFAwAAAA==.',
No='Norrin:BAAANQABCggIDAAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgYIDgACAAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAAANQAECgYIEAAAAA==.Ortalbem:BAABNQAECoEnAAMFAAkKuBztYQCnAgAFAAgKuxztYQCnAgAfAAQKfRgDHwDOAAAAAA==.',
Ou='Oulli:BAAANQABCggIFwAAAA==.',
Ov='Ovi:BAAANQAECgIIBgAAAA==.',
Pa='Painthuffer:BAAANQAECgcIDQABNQAECgkJHQAFAFYSAA==.',
Pe='Peddles:BAAANQAECgMIBAAAAA==.',
Ph='Pherix:BAAANQAECggIEQAAAA==.Philipfry:BAABNQAECoEnAAIDAAgKBhfyQABDAgADAAgKBhfyQABDAgAAAA==.Phill:BAAANQADCgcIDQAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgQICQAAAA==.Potatopants:BAAANQADCgQIBQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAABNQAECoEXAAINAAgKIwyJFwCwAQANAAgKIwyJFwCwAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Raistlain:BAAANQAECgYIEwAAAA==.Ralli:BAABNQAECoEbAAIJAAgKiB1AFwDBAgAJAAgKiB1AFwDBAgAAAA==.Ralls:BAAANQADCgUIBQABNQAECgUICgACAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.Rallsodins:BAAANQAECgUICgAAAA==.Ranulf:BAAANQAECgMIAwAAAA==.Ratava:BAAANQAECgQIBgAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgYJDwAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reldarus:BAEBNQAECoEXAAQXAAgK3yCMAwCbAgAXAAcKkSCMAwCbAgAOAAgKzhmYOwBXAgAWAAEK9BWvZABHAAAAAA==.Rena:BAABNQAECoEbAAQNAAkKagywHwA9AQANAAcKyQawHwA9AQAgAAQKxQOLGQB6AAAhAAIKpgK4QwBWAAAAAA==.Revilation:BAAANQAECggIEwAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgcIGAAEAIkTAA==.Rezzyk:BAABNQAECoEYAAIEAAcKiRMclADHAQAEAAcKiRMclADHAQAAAA==.',
Rh='Rhyxali:BAAANQAECgQICgAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECoEXAAIWAAkKWxTzFwByAgAWAAkKWxTzFwByAgAAAA==.Sargis:BAABNQAECoEcAAMEAAgKGSALgwDwAQAEAAYKeR4LgwDwAQADAAYKzwzPjABNAQAAAA==.',
Sc='Schrödinger:BAAANQADCggIEgABNQAECgYIDgACAAAAAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serissa:BAAANQADCgEIAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECggIGgAWAP4eAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAAANQAECgUIDwAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECgUIBgACAAAAAA==.Shamunroe:BAABNQAECoEYAAMZAAgKVBhtSwAcAgAZAAcKKxltSwAcAgAYAAQKUAuTwAC9AAAAAA==.Shatterhoof:BAAANQAECgQICAAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAACNQAFFIEHAAIgAAMK/hDUBQDmAAAgAAMK/hDUBQDmAAA1AAQKgRwAAiAACQooFkIFAHQCACAACQooFkIFAHQCAAAA.Shylindra:BAAANQADCgYICwAAAA==.',
Si='Sigourney:BAAANQAECgYIDwAAAA==.Silversho:BAAANQADCggIDQAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAAANQAECgYIEQAAAA==.',
Sl='Slighttrash:BAAANQAECgQICQAAAA==.',
Sm='Smallcrow:BAABNQAECoEZAAMGAAkKGhwBEwChAgAGAAgKkh4BEwChAgAiAAQK0Q09LQDXAAAAAA==.',
So='Somdot:BAEBNQAECoEmAAIWAAgKLh5QEQDJAgAWAAgKLh5QEQDJAgAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAABNQAECoEUAAMhAAgKpBgKFQBLAgAhAAgKpBgKFQBLAgANAAEKCwgtPQAmAAABNQAFFAMIBQAHAIEMAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgQIBgAAAA==.Stepbro:BAAANQADCgYJBgAAAA==.Stoikk:BAAANQAECgUIDgAAAA==.Straven:BAAANQAECgYIDAAAAA==.Sturgeson:BAACNQAFFIEIAAIBAAMKLxhlAwDgAAABAAMKLxhlAwDgAAA1AAQKgSQAAgEACApqIKEHALoCAAEACApqIKEHALoCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAcIGAAdAEkiAA==.Sulwen:BAABNQAECoEYAAIOAAcKExY0YADPAQAOAAcKExY0YADPAQAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQADCggIDwAAAA==.',
Sw='Swiftfeet:BAABNQAECoEWAAIaAAcKrRKdfQDjAQAaAAcKrRKdfQDjAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQADCggIDgAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECggIJgAWAC4eAA==.',
Ta='Taeili:BAAANQAECgYIEQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAABNQAECoEkAAIRAAkKuwsYJQDMAQARAAkKuwsYJQDMAQAAAA==.',
Te='Techromancer:BAAANQAECgYICgABNQAECggIEQACAAAAAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgACAAAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQAECgEIAQAAAA==.Theakunda:BAAANQAECgYICwAAAA==.Theodis:BAAANQADCgYIEAAAAA==.Thokdar:BAAANQAECgEIAQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgQIBwAAAA==.Timothyjohn:BAAANQAECgQIBgAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Tituba:BAABNQAECoEhAAIbAAgKkhgCQgBwAgAbAAgKkhgCQgBwAgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trior:BAAANQAECgIJAgAAAA==.',
Ts='Tsuruga:BAABNQAECoEYAAIjAAgKqAOWGQAmAQAjAAgKqAOWGQAmAQAAAA==.',
Tu='Turkwise:BAABNQAECoEhAAMLAAcKJRFFHgBnAQALAAcKkQ9FHgBnAQAkAAUKiw3PGgAdAQAAAA==.',
Un='Unholydiddy:BAAANQABCggIEQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgQIDAAAAA==.',
Va='Vacalaca:BAAANQAECgUIBgAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAABNQAECoEiAAMMAAkKcRhSCwCmAgAMAAkKiBdSCwCmAgAZAAYK3xcjdwCMAQAAAA==.Valton:BAABNQAECoEqAAIGAAkK0ySsAgCnAwAGAAkK0ySsAgCnAwAAAA==.Vancede:BAAANQADCgMIAwABNQAECgUICwACAAAAAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAABNQAECoEYAAISAAgKHQoTWQBtAQASAAgKHQoTWQBtAQAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAABNQAECoEhAAIYAAkKVRq9MAB4AgAYAAkKVRq9MAB4AgAAAA==.Vex:BAAANQAECgIIAgAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.',
Vo='Voidleader:BAAANQAECgYIDgAAAA==.Vostok:BAABNQAECoEbAAIbAAcKZBEXfQDCAQAbAAcKZBEXfQDCAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgQIBAAAAA==.Warranni:BAABNQAECoEbAAIZAAgK1RzpLACmAgAZAAgK1RzpLACmAgAAAA==.',
We='Weekend:BAABNQAECoEZAAIZAAcK6wy9eQCFAQAZAAcK6wy9eQCFAQAAAA==.',
Wh='Whatafox:BAAANQAECgYIEQAAAA==.Whittail:BAAANQABCggIEQAAAA==.',
Wi='Wikket:BAABNQAECoEXAAIQAAgKhwv1RwCgAQAQAAgKhwv1RwCgAQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAAANQAECgQIDQAAAA==.',
Xa='Xade:BAABNQAECoEhAAIIAAgKGhgMEABqAgAIAAgKGhgMEABqAgAAAA==.Xandendon:BAAANQAECggIEwAAAA==.',
Xe='Xerond:BAAANQAECgMIBAAAAA==.Xevin:BAABNQAECoEYAAIZAAcKwxtvSAAoAgAZAAcKwxtvSAAoAgAAAA==.',
Ya='Yaákov:BAAANQAECggIEQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCggIDwAAAA==.',
Za='Zademedic:BAAANQAECgEIAQAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCgYIBgAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFIEFAAIDAAIKHxHhGgCWAAADAAIKHxHhGgCWAAA1AAQKgSYAAwMACQqgGnwkAMECAAMACQqgGnwkAMECAAQAAQr1AEqnARIAAAAA.Zarissena:BAAANQAECgYIDAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAAANQAECgcIEwAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBAAAAA==.Zoraji:BAABNQAECoEkAAIjAAgK5CIjBAAjAwAjAAgK5CIjBAAjAwAAAA==.',
['Ëd']='Ëdën:BAAANQAECgYICAAAAA==.',
['Ða']='Ðarkmoon:BAAANQABCgYICAAAAA==.',
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
