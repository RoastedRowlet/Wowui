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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Evoker-Devastation','Priest-Holy','Shaman-Enhancement','Paladin-Holy','Paladin-Protection','Warrior-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Rogue-Outlaw','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Warlock-Destruction','Warlock-Demonology','Druid-Guardian','Druid-Feral','Shaman-Elemental','Monk-Brewmaster',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAAANQAECgcIEwAAAA==.',
Ae='Aedreline:BAAANQADCgMIAwABNQAECgUIDwABAAAAAA==.Aevelee:BAAANQAECgIIAgAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBAAAAA==.',
Am='Amaria:BAAANQAECgQIBQABNQAECgUIDgABAAAAAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgMIBgAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAABNQAECoEdAAICAAgK3BmbVQBCAgACAAgK3BmbVQBCAgAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgEIAQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQADCgYJCwAAAA==.',
Au='Austenpally:BAAANQAECgQICQAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIDgAAAA==.',
Ax='Axeflack:BAAANQAECgYICQAAAA==.Axegor:BAAANQAECgQIBwAAAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECgYIBwABAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgQIBAAAAA==.',
Bi='Biancadelrio:BAAANQAECgMIBgAAAA==.Bigguberment:BAAANQAECgIIBAAAAA==.',
Bl='Blackbird:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Bladekrim:BAAANQADCgcICwAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgkJGQADAI0RAA==.Botia:BAAANQAECgUICAAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgQIBAAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAAANQAECgUICAAAAA==.Brunnera:BAAANQADCgcIDAAAAA==.Bruuenor:BAAANQAECgEIAQAAAA==.Bruul:BAAANQAECgQICgAAAA==.',
By='Bytour:BAAANQAECgQIBAABNQAECggIIQAEAMokAA==.',
Ca='Caenji:BAAANQADCggIDwAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.',
Ch='Chadgar:BAABNQAECoEZAAIDAAkKjRF8eQBTAgADAAkKjRF8eQBTAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECoEgAAMFAAkKfyDbGQDmAQAFAAUKbSHbGQDmAQAGAAQKVh/EOABwAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAECgMIAwABNQAFFAIIBQAHALEWAA==.',
Cl='Close:BAAANQADCgUIBQABNQAECggICAABAAAAAA==.',
Co='Conorix:BAAANQADCgcIGgAAAA==.Corvo:BAAANQADCggICAABNQAECgUICAABAAAAAA==.',
Cr='Crataxxis:BAAANQAECgYIDQAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Cy='Cydon:BAAANQAECgQIEQAAAA==.Cythraul:BAAANQAECgUICAAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQADCgUIBgABAAAAAA==.Darrwin:BAAANQAECgUICAAAAA==.',
De='Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgYIBgAAAA==.',
Df='Dfabness:BAAANQAECgYIDgAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.',
Dr='Dracthayr:BAABNQAECoEdAAIIAAgKYgjBFwCNAQAIAAgKYgjBFwCNAQAAAA==.Dragonhammer:BAAANQAECgYIBgAAAA==.Dreaming:BAAANQAECggICAAAAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAAANQAECgEIAQAAAA==.Drx:BAAANQAECgQIDgAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
El='Elanore:BAABNQAECoEVAAIJAAcKfRVtTADsAQAJAAcKfRVtTADsAQABNQAECgEIAQABAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIFwAKAJQWAA==.Elison:BAAANQAECgQIBAABNQAECgYIBwABAAAAAA==.Ellaini:BAAANQAECgEIAQAAAA==.Elliana:BAAANQAECgEIAQAAAA==.Ellie:BAAANQAECgEIAgABNQAECggIJAALAPQeAA==.Elloise:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Elsae:BAABNQAECoEbAAIMAAgKOxKQGwC4AQAMAAgKOxKQGwC4AQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAABNQAFFIEFAAIGAAMKgQzjBwD1AAAGAAMKgQzjBwD1AAAAAA==.Everios:BAABNQAECoEdAAINAAgKqB5IBwCgAgANAAgKqB5IBwCgAgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgEIAQABAAAAAA==.',
Ex='Exodous:BAAANQABCgYJBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgIIBwABAAAAAA==.Faytadori:BAABNQAECoEaAAMOAAgKfhKiMwD/AQAOAAgKfhKiMwD/AQAPAAMKjgkhSgCHAAAAAA==.',
Fe='Felgrrl:BAAANQADCgcIHgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAAANQAECgQICQAAAA==.',
Fl='Fletch:BAAANQAECgYICwAAAA==.',
Fo='Forever:BAAANQAECggIBwABNQAECggICAABAAAAAA==.',
Fr='Frique:BAAANQADCgYIGgAAAA==.Frozenyogert:BAAANQAECgEIAQAAAA==.',
Ga='Galbur:BAABNQAECoEXAAMQAAgKSxRjTgByAQARAAgKLQyHTQB7AQAQAAcKCRVjTgByAQAAAA==.Galdrin:BAAANQAECgIIBwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECoEZAAICAAgKpRbXdQDiAQACAAgKpRbXdQDiAQAAAA==.',
Ge='Geers:BAAANQAECgcICAAAAA==.Geta:BAAANQAECgQIBAABNQAECgkJFwASAPUYAA==.Getabrew:BAAANQAECgYIBgABNQAECgkJFwASAPUYAA==.Getacurse:BAAANQAECgUIBQABNQAECgkJFwASAPUYAA==.Getagrip:BAAANQADCgIIAgABNQAECgkJFwASAPUYAA==.Getarage:BAABNQAECoEXAAISAAkK9RirQQCLAgASAAkK9RirQQCLAgAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgkJFwASAPUYAA==.',
Gh='Ghil:BAAANQAECgUIDAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUIBQAAAA==.Gilia:BAAANQAECgIIBAAAAA==.',
Gl='Glynix:BAAANQAECgIIBAAAAA==.',
Gn='Gnosher:BAAANQADCggIDwAAAA==.',
Go='Goku:BAAANQAECgUIEwAAAA==.Goloron:BAAANQADCgIJAgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQICQAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQAECgUICQAAAA==.',
Gu='Gunderthirth:BAACNQAFFIEJAAINAAUK2x+dAADrAQANAAUK2x+dAADrAQA1AAQKgR4AAg0ACQrNJI8BAJQDAA0ACQrNJI8BAJQDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAAANQAECgQICAAAAA==.',
Ha='Haan:BAAANQADCgYIBgAAAA==.Haliran:BAAANQADCgYIDgAAAA==.Handsoap:BAAANQAECgIIBQAAAA==.Harakhty:BAAANQADCgQIBAAAAA==.Hardhitter:BAABNQAECoEiAAMNAAgK3BOfDwDRAQANAAcKrBWfDwDRAQASAAgK9QkmlACMAQAAAA==.',
He='Hellstorm:BAAANQABCgYIBgAAAA==.Hellumph:BAAANQAECgYICQAAAA==.Hevensrath:BAAANQAECgQICQAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggICgABNQAECggIGwATAIAeAA==.',
Ho='Hokuden:BAABNQAECoEdAAITAAgK1xP6KADxAQATAAgK1xP6KADxAQAAAA==.Holphie:BAAANQAECgEIAQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.',
Hu='Huddington:BAAANQAECgYICwAAAA==.',
Hy='Hyperion:BAAANQADCgcIFgABNQAECgUICAABAAAAAA==.',
Ig='Igknight:BAAANQAECgIIAgABNQAECgkJHAALAK4LAA==.',
Il='Ilsi:BAAANQADCgYIBgAAAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwABAAAAAA==.',
In='Indecent:BAAANQAECgYIDAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECoEYAAIDAAgKKRngewBOAgADAAgKKRngewBOAgAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECoEcAAQUAAkKhhZBHAAYAgAUAAgKUBVBHAAYAgAVAAMKURVcEgDIAAAJAAMKowt3pwCoAAAAAA==.Jackieplays:BAABNQAECoEfAAMVAAgKLh91AgDGAgAVAAgKCx51AgDGAgAJAAgKVhk9RQAKAgAAAA==.Jaded:BAAANQAECgYIEAAAAA==.',
Je='Jeses:BAAANQAECgYIBwAAAA==.',
Jo='Jollah:BAAANQAECgUICQAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAABNQAECoEeAAIWAAkKPx3pEQANAwAWAAkKPx3pEQANAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQABAAAAAA==.Kardas:BAAANQAECgYIDwAAAA==.',
Kb='Kbilly:BAAANQAECgYIEwAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFIEFAAIFAAIK6Q69CwCcAAAFAAIK6Q69CwCcAAA1AAQKgSIAAgUACQojG7MHAOoCAAUACQojG7MHAOoCAAAA.',
Ki='Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQADCggICAAAAA==.',
Kn='Knottes:BAAANQABCggIFgAAAA==.',
Kr='Krampus:BAAANQAECgYIDgAAAA==.Kranok:BAAANQAECgUICAAAAA==.Krennthis:BAAANQADCgYICwAAAA==.Krimbruiser:BAAANQADCgYIBwABNQADCgcICwABAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQADCgIJAgAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAAANQAECgUICAAAAA==.',
Li='Lilguysci:BAAANQAECgIJAgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAAANQAECgYIEAAAAA==.',
Lu='Lugosi:BAAANQAECgEIAQAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgYIDwABAAAAAA==.Maddeleine:BAAANQADCgEIAQAAAA==.Magara:BAAANQADCggIEAAAAA==.Magicdemon:BAAANQAECgYIDgAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAAANQAECgYIDwAAAA==.Mansuno:BAABNQAECoEdAAICAAcKJRuKWQA2AgACAAcKJRuKWQA2AgAAAA==.Mapachote:BAAANQAECgUIBgAAAA==.Marodin:BAAANQADCgcIIwAAAA==.Maynor:BAAANQABCggICgAAAA==.Mazboda:BAAANQAECgQIEQAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAAANQAECgYIDwAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAAANQAECgYIEgAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQADCgcIDQABAAAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necronic:BAAANQAECgEIAQAAAA==.Necroreign:BAABNQAECoEaAAIHAAcK5hdqKQAAAgAHAAcK5hdqKQAAAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAAANQAECgUICAAAAA==.Nervous:BAAANQAECggIAQABNQAECggICAABAAAAAA==.Nessee:BAAANQAECgQICgAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIDAAAAA==.Nihowdy:BAABNQAECoEcAAIXAAgKeyDgAgDwAgAXAAgKeyDgAgDwAgAAAA==.',
No='Norrin:BAAANQABCggIDAAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAAANQAECgUICgAAAA==.Ortalbem:BAABNQAECoEdAAMDAAgKjRz9XgCUAgADAAgK1hv9XgCUAgAYAAIKRBjfIwCMAAAAAA==.',
Ou='Oulli:BAAANQABCggIEwAAAA==.',
Ov='Ovi:BAAANQAECgIIBgAAAA==.',
Pa='Painthuffer:BAAANQAECgYIBgABNQAECgkJGQADAI0RAA==.',
Pe='Peddles:BAAANQAECgIJAwAAAA==.',
Ph='Pherix:BAAANQADCgUIBgAAAA==.Philipfry:BAABNQAECoEfAAILAAgKZRYhOABHAgALAAgKZRYhOABHAgAAAA==.Phill:BAAANQADCgcIBwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgQIBgAAAA==.Potatopants:BAAANQADCgQIBQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAAANQAECgYIDQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Raistlain:BAAANQAECgYIDwAAAA==.Ralli:BAAANQAECgcIEgAAAA==.Ralls:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Rallsodins:BAAANQAECgUICAAAAA==.Ranulf:BAAANQAECgMIAwAAAA==.Ratava:BAAANQAECgIIAgAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgYJDwAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reldarus:BAEANQAECgYIDQAAAA==.Rena:BAABNQAECoEXAAQIAAgKlgfEHABBAQAIAAcKnAbEHABBAQAZAAQKxQMxFgB7AAAaAAEKgAGBRgAjAAAAAA==.Revilation:BAAANQAECgcIDQAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.Rezzyk:BAAANQAECgcIDgAAAA==.',
Rh='Rhyxali:BAAANQAECgIIBgAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAAANQAECggIEgAAAA==.Sargis:BAABNQAECoEaAAMCAAgKayIZgQDBAQACAAUKyCAZgQDBAQALAAYKzwzXewBSAQAAAA==.',
Sc='Schrödinger:BAAANQADCggIEgABNQAECgUICAABAAAAAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serissa:BAAANQADCgEJAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECggIGgAUAP4eAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAAANQAECgUICwAAAA==.Shamemoon:BAAANQAECgEJAQABNQAECgUIBgABAAAAAA==.Shamunroe:BAAANQAECgYIDgAAAA==.Shatterhoof:BAAANQAECgQIBQAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAABNQAECoEWAAIZAAkKdxUnBQBTAgAZAAkKdxUnBQBTAgAAAA==.Shylindra:BAAANQADCgYICwAAAA==.',
Si='Sigourney:BAAANQAECgUICQAAAA==.Silversho:BAAANQADCgYICwAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAAANQAECgYICwAAAA==.',
Sl='Slighttrash:BAAANQAECgMICAAAAA==.',
Sm='Smallcrow:BAABNQAECoEZAAMEAAkKGhypDgC9AgAEAAgKkh6pDgC9AgAbAAQK0Q2KKADZAAAAAA==.',
So='Somdot:BAEBNQAECoEgAAIUAAgKLh1xDwDKAgAUAAgKLh1xDwDKAgAAAA==.Somedeekay:BAAANQAECgYIDgAAAA==.',
Sp='Spirit:BAAANQAECggIEwABNQAFFAMIBQAGAIEMAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgMIAwAAAA==.Stepbro:BAAANQADCgYJBgAAAA==.Stoikk:BAAANQAECgUICgAAAA==.Straven:BAAANQAECgUICQAAAA==.Sturgeson:BAACNQAFFIEFAAINAAIKFBY4BACBAAANAAIKFBY4BACBAAA1AAQKgSEAAg0ACAo2IDgGAMQCAA0ACAo2IDgGAMQCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAcIFwAcAEkiAA==.Sulwen:BAAANQAECgYIDwAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQADCggIDwAAAA==.',
Sw='Swiftfeet:BAAANQAECgUIDgAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQADCggIDgAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDAABNQAECggIIAAUAC4dAA==.',
Ta='Taeili:BAAANQAECgYICwAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAABNQAECoEeAAIPAAgKIgohJgCNAQAPAAgKIgohJgCNAQAAAA==.',
Te='Techromancer:BAAANQADCgEJAQABNQADCgUIBgABAAAAAA==.Tem:BAAANQABCgQIBAABNQADCgcIDgABAAAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQAECgEIAQAAAA==.Theakunda:BAAANQAECgYICwAAAA==.Theodis:BAAANQADCgYIEAAAAA==.Thokdar:BAAANQABCgEIAQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgQIBwAAAA==.Timothyjohn:BAAANQAECgIIAgAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Tituba:BAABNQAECoEaAAIdAAgKDxLsUwAPAgAdAAgKDxLsUwAPAgAAAA==.',
To='Toklore:BAAANQADCgcIDgAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trior:BAAANQAECgIJAgAAAA==.',
Ts='Tsuruga:BAAANQAECgYIDgAAAA==.',
Tu='Turkwise:BAABNQAECoEZAAMeAAcKLw8VGABnAQAeAAcKlw4VGABnAQAfAAQKJgoRHQDMAAAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgQICwAAAA==.',
Va='Vacalaca:BAAANQAECgUIBgAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAABNQAECoEeAAMKAAgKGhm9DABmAgAKAAgKFBi9DABmAgAgAAYK3xfrYwChAQAAAA==.Valton:BAABNQAECoEhAAIEAAgKyiSwCAAfAwAEAAgKyiSwCAAfAwAAAA==.Vancede:BAAANQADCgMIAwABNQAECgQICAABAAAAAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAAANQAECgYIDgAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAABNQAECoEeAAIWAAgKMxw9NABKAgAWAAgKMxw9NABKAgAAAA==.Vex:BAAANQAECgIIAgAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgQIBAAAAA==.',
Vo='Voidleader:BAAANQAECgYICgAAAA==.Vostok:BAAANQAECgYIEAAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgQIBAAAAA==.Warranni:BAAANQAECgcIEwAAAA==.',
We='Weekend:BAAANQAECgUIDgAAAA==.',
Wh='Whatafox:BAAANQAECgYIDQAAAA==.Whittail:BAAANQABCggIDwAAAA==.',
Wi='Wikket:BAAANQAECgYIDQAAAA==.',
Wy='Wyelie:BAAANQAECgQIDAAAAA==.',
Xa='Xade:BAABNQAECoEZAAIFAAgKcROfEwArAgAFAAgKcROfEwArAgAAAA==.Xandendon:BAAANQAECgcIDwAAAA==.',
Xe='Xerond:BAAANQAECgEIAQAAAA==.Xevin:BAAANQAECgUIEgAAAA==.',
Ya='Yaákov:BAAANQAECggIEQAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCgUICAAAAA==.',
Za='Zademedic:BAAANQAECgEIAQAAAA==.Zanarkin:BAAANQAECgEIAQAAAA==.Zanedore:BAAANQABCgQIBAAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFIEFAAILAAIKHxEVFgCZAAALAAIKHxEVFgCZAAA1AAQKgSMAAwsACQqgGrkdAMwCAAsACQqgGrkdAMwCAAIAAQr1ACd4ARIAAAAA.Zarissena:BAAANQAECgYIBwAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQADCgQIBgAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAAANQAECgYIDAAAAA==.',
Zo='Zoeybear:BAAANQAECgIJAgAAAA==.Zoraji:BAABNQAECoEdAAIhAAgKSiH+BADhAgAhAAgKSiH+BADhAgAAAA==.',
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
