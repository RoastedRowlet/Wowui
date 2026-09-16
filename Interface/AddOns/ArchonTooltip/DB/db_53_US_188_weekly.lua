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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Paladin-Retribution','Warrior-Protection','Paladin-Holy','Warlock-Affliction',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAAANQAECgUIBwAAAA==.',
Ae='Aedreline:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Aevelee:BAAANQADCgcIFAAAAA==.',
Al='Aleeta:BAAANQAECgQIBAAAAA==.Allucard:BAAANQADCggIFwAAAA==.',
Am='Amaria:BAAANQAECgQIBAAAAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgMIBQAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAAANQAECgYICwAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgEIAQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQADCgcICgAAAA==.',
At='Atillis:BAAANQADCgYICwAAAA==.',
Au='Austenpally:BAAANQAECgEIAQAAAA==.',
Av='Aveycado:BAAANQAECgQIBQAAAA==.',
Ax='Axeflack:BAAANQAECgQIBwAAAA==.Axegor:BAAANQAECgMIBAAAAA==.',
Az='Azaral:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQADCgcICwAAAA==.',
Bi='Biancadelrio:BAAANQAECgEIAQAAAA==.Bigguberment:BAAANQADCggIEAAAAA==.',
Bl='Bladekrim:BAAANQADCgcICwAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgYIDQABAAAAAA==.Botia:BAAANQAECgEIAQAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAAANQAECgEIAQAAAA==.Brunnera:BAAANQADCgcIDAAAAA==.Bruuenor:BAAANQABCgMIAgAAAA==.Bruul:BAAANQAECgQIBwAAAA==.',
Ca='Caenji:BAAANQADCggIDwAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.',
Ch='Chadgar:BAAANQAECgYIDQAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECoESAAMCAAgJnxt9GAC+AQACAAUJJR59GAC+AQADAAMJahebLwDnAAAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQADCgUIBQABNQAECgkJGAAEAPQYAA==.',
Cl='Close:BAAANQADCgUIBQABNQAECggIBwABAAAAAA==.',
Co='Conorix:BAAANQADCgYIDAAAAA==.Corvo:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Cr='Crataxxis:BAAANQAECgIIAgAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQADCgcICwABAAAAAA==.',
Cy='Cydon:BAAANQAECgQICQAAAA==.Cythraul:BAAANQAECgEIAQAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgMIAwAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQAAAA==.Darrwin:BAAANQAECgEIAQAAAA==.',
De='Derrith:BAAANQADCgUIBgAAAA==.',
Df='Dfabness:BAAANQAECgUIBwAAAA==.',
Di='Diizmyster:BAAANQADCggICAAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.',
Dr='Dracthayr:BAAANQAECgYICgAAAA==.Dragonhammer:BAAANQADCgcIBwAAAA==.Drimclaw:BAAANQAECgEIAQAAAA==.Drubo:BAAANQAECgEIAQAAAA==.Drx:BAAANQAECgQIBwAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
El='Elanore:BAAANQAECgUICQABNQAECgEIAQABAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECgYIEgABAAAAAA==.Elison:BAAANQADCgcIDQAAAA==.Ellaini:BAAANQADCggIDwAAAA==.Elliana:BAAANQAECgEIAQAAAA==.Ellie:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.Elloise:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Elsae:BAAANQAECgUICgAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAAANQAECgUIBQABNQAECgcICAABAAAAAA==.Everios:BAAANQAECgYIEgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Evánder:BAAANQADCggIEAAAAA==.',
Ex='Exodous:BAAANQABCgQIAgAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Faytadori:BAAANQAECgUICQAAAA==.',
Fe='Felgrrl:BAAANQADCgYIEAAAAA==.Feyreh:BAAANQAECgEIAQAAAA==.',
Fi='Fidget:BAAANQAECgIIAgAAAA==.',
Fl='Fletch:BAAANQAECgMIAwAAAA==.',
Fo='Forever:BAAANQAECggIBwAAAA==.',
Fr='Frique:BAAANQADCgUIDwAAAA==.Frozenyogert:BAAANQADCgUICQAAAA==.',
Ga='Galbur:BAAANQAECgUIDAAAAA==.Galdrin:BAAANQAECgIIAwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECoEZAAIFAAgJpRa2PAAJAgAFAAgJpRa2PAAJAgAAAA==.',
Ge='Geers:BAAANQAECgEIAQAAAA==.Getarage:BAAANQAECgYIDQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgYIDQABAAAAAA==.',
Gh='Ghil:BAAANQAECgIIAgAAAA==.',
Gi='Gilia:BAAANQAECgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIAwAAAA==.',
Gn='Gnosher:BAAANQADCgYIBgAAAA==.',
Go='Goku:BAAANQAECgUIBwAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgEIAQAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQAECgIIAgAAAA==.',
Gu='Gunderthirth:BAABNQAECoEZAAIGAAkJYCTjAACmAwAGAAkJYCTjAACmAwAAAA==.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAAANQAECgEIAQAAAA==.',
Ha='Haliran:BAAANQADCgUICwAAAA==.Handsoap:BAAANQAECgEIAQAAAA==.Harakhty:BAAANQADCgQIBAAAAA==.Hardhitter:BAAANQAECgYIEAAAAA==.',
He='Hellumph:BAAANQAECgIIAgAAAA==.Hevensrath:BAAANQAECgEIAQAAAA==.Hextermorgan:BAAANQABCggICAABNQAECgcIEAABAAAAAA==.',
Ho='Hokuden:BAAANQAECgYICgAAAA==.Holphie:BAAANQAECgEIAQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.',
Hu='Huddington:BAAANQAECgEIAQAAAA==.',
Hy='Hyperion:BAAANQADCgYIDgAAAA==.',
Ig='Igknight:BAAANQADCggIEgABNQAECgkJFgAHAIQKAA==.',
In='Indecent:BAAANQAECgEIAgAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAAANQAECgUICAAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAAANQAECgYIDwAAAA==.Jackieplays:BAAANQAECgYIEwAAAA==.Jaded:BAAANQAECgIIBAAAAA==.',
Je='Jeses:BAAANQADCgUIBQAAAA==.',
Ju='Jutic:BAAANQAECgYICgAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYIEQABAAAAAA==.Kardas:BAAANQAECgIIBAAAAA==.',
Kb='Kbilly:BAAANQAECgQICAAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAABNQAECoEXAAICAAkJOhaiCAC3AgACAAkJOhaiCAC3AgAAAA==.',
Ki='Kitsunami:BAAANQABCgMIAwAAAA==.Kitto:BAAANQADCgYIBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kn='Knottes:BAAANQABCggICwAAAA==.',
Kr='Krampus:BAAANQAECgEIAgAAAA==.Kranok:BAAANQAECgEIAQAAAA==.Krennthis:BAAANQADCgUICgAAAA==.Krimbruiser:BAAANQADCgYIBwAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAAANQAECgEIAQAAAA==.',
Li='Lilguysci:BAAANQADCggIDgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAAANQAECgMIBQAAAA==.',
Lu='Lugosi:BAAANQADCggIDgAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgIIBAABAAAAAA==.Maddeleine:BAAANQADCgEIAQAAAA==.Magara:BAAANQADCggIEAAAAA==.Magicdemon:BAAANQAECgEIAgAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAAANQAECgQIBQAAAA==.Mansuno:BAAANQAECgQIDgAAAA==.Mapachote:BAAANQADCggIGwAAAA==.Marodin:BAAANQADCgYIFQAAAA==.Maynor:BAAANQABCgQIBAAAAA==.Mazboda:BAAANQAECgQICQAAAA==.',
Me='Meatbaal:BAAANQAECgQICAAAAA==.Melinaria:BAAANQAECgIIBAAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAAANQAECgMIBQAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necroreign:BAAANQAECgYICwAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAAANQAECgEIAQAAAA==.Nessee:BAAANQADCggIDAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIBwAAAA==.Nihowdy:BAAANQAECgYICgAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAAANQAECgEIAQAAAA==.Ortalbem:BAAANQAECgYICgAAAA==.',
Ou='Oulli:BAAANQABCgYIDgAAAA==.',
Ov='Ovi:BAAANQAECgIIAgAAAA==.',
Pe='Peddles:BAAANQAECgIIAgAAAA==.',
Ph='Philipfry:BAAANQAECgUIDAAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQADCgUICwAAAA==.Potatopants:BAAANQADCgQIBQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAAANQAECgEIAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Raistlain:BAAANQAECgIIBAAAAA==.Ralli:BAAANQAECgUIBwAAAA==.Rallsodins:BAAANQAECgUICAAAAA==.Ranulf:BAAANQADCgUIDQAAAA==.Ratava:BAAANQADCgcIFgAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgUICgAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reldarus:BAEANQAECgEIAQAAAA==.Rena:BAAANQAECgYIDQAAAA==.Revilation:BAAANQAECgUIBQAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Rezzyk:BAAANQAECgEIAQAAAA==.',
Rh='Rhyxali:BAAANQAECgIIAgAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sacredscales:BAAANQADCgMIAwAAAA==.Samvimes:BAAANQAECgEIAQAAAA==.Sangreene:BAAANQAECgUIBwAAAA==.Sargis:BAAANQAECgYICAAAAA==.',
Sc='Schrödinger:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgcIDgABAAAAAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAAANQADCgUIBQAAAA==.Shamemoon:BAAANQAECgEIAQAAAA==.Shamunroe:BAAANQAECgEIAgAAAA==.Shatterhoof:BAAANQADCggIGAAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAAANQAFFAEIAQAAAA==.Shylindra:BAAANQADCgUICgAAAA==.',
Si='Sigourney:BAAANQAECgQIBAAAAA==.Silversho:BAAANQADCgUICgAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAAANQADCgIIAgAAAA==.',
Sl='Slighttrash:BAAANQAECgMIAwAAAA==.',
Sm='Smallcrow:BAAANQAECggIDQAAAA==.',
So='Somdot:BAAANQAECgcIDAAAAA==.Somedeekay:BAAANQAECgIIBAAAAA==.',
Sp='Spirit:BAAANQAECgcICAAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQADCggIFwAAAA==.Stoikk:BAAANQAECgEIAQAAAA==.Straven:BAAANQADCgcICQAAAA==.Sturgeson:BAABNQAECoEWAAIGAAgJ2hvaBACJAgAGAAgJ2hvaBACJAgAAAA==.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAYIDAAIAHggAA==.Sulwen:BAAANQAECgQIBQAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQADCgcICAAAAA==.',
Sw='Swiftfeet:BAAANQAECgIIBAAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQADCggIDgAAAA==.',
['Sø']='Sømdøt:BAAANQAECggIDAABNQAECgcIDAABAAAAAA==.',
Ta='Taeili:BAAANQADCggIGgAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAAANQAECgYIEwAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQADCggIDwAAAA==.Theodis:BAAANQADCgUIDQAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgIIAgAAAA==.Timothyjohn:BAAANQADCgYIFQAAAA==.Tinkphooey:BAAANQAECgMIAwAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Tituba:BAAANQAECgYICAAAAA==.',
To='Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trior:BAAANQADCgQIBAAAAA==.',
Ts='Tsuruga:BAAANQAECgEIAgAAAA==.',
Tu='Turkwise:BAAANQAECgQIBgAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgMIBgAAAA==.',
Va='Valany:BAAANQADCgIIAgAAAA==.Valkira:BAAANQAECgYIEwAAAA==.Valton:BAAANQAECgYIEwAAAA==.Vanillanice:BAAANQADCgMIBAAAAA==.Vaxaldan:BAAANQAECgEIAgAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAAANQAECgYIEwAAAA==.Vex:BAAANQADCgYICwAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQADCgUIBQAAAA==.',
Vo='Voidleader:BAAANQADCggIDgAAAA==.Vostok:BAAANQAECgQIBwAAAA==.',
Wa='Warramag:BAAANQADCggIFAAAAA==.Warranni:BAAANQAECgUIBwAAAA==.',
We='Weekend:BAAANQAECgQIBQAAAA==.',
Wh='Whatafox:BAAANQAECgIIBAAAAA==.Whittail:BAAANQABCgYIDAAAAA==.',
Wi='Wikket:BAAANQAECgEIAQAAAA==.',
Wy='Wyelie:BAAANQAECgQIBwAAAA==.',
Xa='Xade:BAAANQAECgUICQAAAA==.Xandendon:BAAANQAECgYIDAAAAA==.',
Xe='Xevin:BAAANQAECgUIBwAAAA==.',
Ya='Yaákov:BAAANQAECgcICQAAAA==.',
Yi='Yinosai:BAAANQADCgUICAAAAA==.',
Yo='Yougot:BAAANQADCgUICAAAAA==.',
Za='Zademedic:BAAANQAECgEIAQAAAA==.Zanarkin:BAAANQADCggIFQAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAABNQAECoEXAAMHAAkJvhOIJgA7AgAHAAgJ8BWIJgA7AgAFAAEJ9QCpBgEUAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQADCgQIBgAAAA==.Zerolicious:BAAANQADCggICAAAAA==.Zeroprophecy:BAAANQAECgEIAQAAAA==.Zevvo:BAAANQAECgEIAgAAAA==.',
Zo='Zoraji:BAAANQAECgYICgAAAA==.',
['Ëd']='Ëdën:BAAANQADCgYICQAAAA==.',
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
