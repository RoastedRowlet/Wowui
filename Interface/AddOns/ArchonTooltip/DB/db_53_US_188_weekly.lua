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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAAANQAECgIIAgAAAA==.',
Ae='Aedreline:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Aevelee:BAAANQADCgYIDQAAAA==.',
Al='Aleeta:BAAANQAECgQIBAAAAA==.Allucard:BAAANQADCggIEQAAAA==.',
Am='Amaria:BAAANQAECgQIBAAAAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgEIAQAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAAANQAECgQIBQAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQADCgcIBwAAAA==.',
At='Atillis:BAAANQADCgYICwAAAA==.',
Au='Austenpally:BAAANQAECgEIAQAAAA==.',
Av='Aveycado:BAAANQAECgEIAQAAAA==.',
Ax='Axeflack:BAAANQAECgQIBwAAAA==.Axegor:BAAANQAECgEIAQAAAA==.',
Az='Azaral:BAAANQADCgQIBAABNQADCgQIBgABAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQADCgYIBgAAAA==.',
Bi='Biancadelrio:BAAANQADCgUIBQAAAA==.Bigguberment:BAAANQADCgYIDgAAAA==.',
Bl='Bladekrim:BAAANQADCgQIBAAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.Botia:BAAANQADCggIDAAAAA==.Bourdeaux:BAAANQADCgcIEQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAAANQAECgEIAQAAAA==.Brunnera:BAAANQADCgcIDAAAAA==.Bruuenor:BAAANQABCgMIAgAAAA==.Bruul:BAAANQAECgEIAQAAAA==.',
Ca='Caenji:BAAANQADCgcIBwAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.',
Ch='Chadgar:BAAANQAECgUIBwAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAAANQAECgQICQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQADCgUIBQABNQAECgcIDgABAAAAAA==.',
Cl='Close:BAAANQADCgUIBQABNQAECggIBwABAAAAAA==.',
Co='Conorix:BAAANQADCgYIBgAAAA==.Corvo:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Cr='Crataxxis:BAAANQAECgIIAgAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Cy='Cydon:BAAANQAECgQIBgAAAA==.Cythraul:BAAANQAECgEIAQAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgMIAwAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Darrwin:BAAANQADCggIDwAAAA==.',
De='Derrith:BAAANQADCgMIAwAAAA==.',
Df='Dfabness:BAAANQAECgIIAgAAAA==.',
Di='Diizmyster:BAAANQADCggICAAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.',
Dr='Dracthayr:BAAANQAECgMIBAAAAA==.Dragonhammer:BAAANQADCgcIBwAAAA==.Drimclaw:BAAANQADCggIEwAAAA==.Drubo:BAAANQADCgYIEQAAAA==.Drx:BAAANQAECgQIBQAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
El='Elanore:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.Elison:BAAANQADCgQIBgAAAA==.Ellaini:BAAANQADCgcIBwAAAA==.Elliana:BAAANQAECgEIAQAAAA==.Ellie:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.Elloise:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Elsae:BAAANQAECgQIBQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Everios:BAAANQAECgYIDAAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Evánder:BAAANQADCggICAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Faytadori:BAAANQAECgMIBAAAAA==.',
Fe='Felgrrl:BAAANQADCgYICgAAAA==.Feyreh:BAAANQADCgUIBQAAAA==.',
Fi='Fidget:BAAANQADCggIDQAAAA==.',
Fl='Fletch:BAAANQAECgIIAgAAAA==.',
Fo='Forever:BAAANQAECggIBwAAAA==.',
Fr='Frique:BAAANQADCgQICgAAAA==.Frozenyogert:BAAANQADCgUICQAAAA==.',
Ga='Galbur:BAAANQAECgUIDAAAAA==.Galdrin:BAAANQAECgIIAwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAAANQAECgcIEAAAAA==.',
Ge='Geers:BAAANQAECgEIAQAAAA==.Getarage:BAAANQAECgUIBwAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgUIBwABAAAAAA==.',
Gh='Ghil:BAAANQADCggIEgAAAA==.',
Gi='Gilia:BAAANQADCgUICQAAAA==.',
Gl='Glynix:BAAANQADCgYIBgAAAA==.',
Gn='Gnosher:BAAANQABCgQIBgAAAA==.',
Go='Goku:BAAANQAECgIIAgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgEIAQAAAA==.Grekk:BAAANQADCgUIBQAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQAECgEIAQAAAA==.',
Gu='Gunderthirth:BAAANQAECggIEwAAAA==.',
Gw='Gwaeniiha:BAAANQADCggIEQAAAA==.',
Ha='Haliran:BAAANQADCgQIBgAAAA==.Handsoap:BAAANQAECgEIAQAAAA==.Harakhty:BAAANQADCgQIBAAAAA==.Hardhitter:BAAANQAECgYICwAAAA==.',
He='Hellumph:BAAANQAECgIIAgAAAA==.Hevensrath:BAAANQAECgEIAQAAAA==.',
Ho='Hokuden:BAAANQAECgMIBAAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.',
Hu='Huddington:BAAANQADCgcIFAAAAA==.',
Hy='Hyperion:BAAANQADCgQICAAAAA==.',
Ig='Igknight:BAAANQADCggICgABNQAECgQIBAABAAAAAA==.',
In='Indecent:BAAANQAECgEIAQAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgQIBAAAAA==.',
Is='Ishy:BAAANQAECgMIAwAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAAANQAECgUICQAAAA==.Jackieplays:BAAANQAECgYIDQAAAA==.Jaded:BAAANQAECgIIAgAAAA==.',
Ju='Jutic:BAAANQAECgMIBAAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Kardas:BAAANQAECgIIAgAAAA==.',
Kb='Kbilly:BAAANQAECgQIBAAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAAANQAECgcIDgAAAA==.',
Ki='Kitsunami:BAAANQABCgMIAwAAAA==.Kitto:BAAANQADCgYIBgAAAA==.Kittvulpy:BAAANQADCgYIBgAAAA==.',
Kn='Knottes:BAAANQABCgUIBgAAAA==.',
Kr='Krampus:BAAANQAECgEIAQAAAA==.Kranok:BAAANQAECgEIAQAAAA==.Krennthis:BAAANQADCgUICgAAAA==.Krimbruiser:BAAANQADCgYIBwAAAA==.',
Ku='Kunac:BAAANQADCgYICwAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.',
Lh='Lhani:BAAANQAECgEIAQAAAA==.',
Li='Lilguysci:BAAANQADCgYIBgAAAA==.',
Ll='Llyrael:BAAANQAECgIIAgAAAA==.',
Lu='Lugosi:BAAANQADCggIDgAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Maddeleine:BAAANQADCgEIAQAAAA==.Magara:BAAANQADCggIDAAAAA==.Magicdemon:BAAANQAECgEIAQAAAA==.Makall:BAAANQABCgIIAgAAAA==.Malaah:BAAANQAECgEIAQAAAA==.Mansuno:BAAANQAECgQICgAAAA==.Mapachote:BAAANQADCggIEwAAAA==.Marodin:BAAANQADCgYIDwAAAA==.Mazboda:BAAANQAECgQIBgAAAA==.',
Me='Meatbaal:BAAANQAECgIIBAAAAA==.Melinaria:BAAANQAECgIIAgAAAA==.',
Mi='Mileta:BAAANQAECgIIAgAAAA==.Minuette:BAAANQADCgYICwAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necroreign:BAAANQAECgQIBQAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAAANQAECgEIAQAAAA==.Nessee:BAAANQADCggIDAAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nihowdy:BAAANQAECgMIBAAAAA==.',
Or='Orci:BAAANQADCgcIEQAAAA==.Ortalbem:BAAANQAECgMIBAAAAA==.',
Ou='Oulli:BAAANQABCgYICAAAAA==.',
Ov='Ovi:BAAANQADCgYICwAAAA==.',
Pe='Peddles:BAAANQADCgEIAQAAAA==.',
Ph='Philipfry:BAAANQAECgQIBwAAAA==.',
Po='Poomacha:BAAANQADCgUICwAAAA==.Potatopants:BAAANQADCgQIBAAAAA==.',
Pr='Prinlina:BAAANQADCgYICgAAAA==.',
Py='Pyree:BAAANQAECgEIAQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Raistlain:BAAANQAECgIIAgAAAA==.Ralli:BAAANQAECgIIAgAAAA==.Rallsodins:BAAANQAECgUICAAAAA==.Ranulf:BAAANQADCgUICAAAAA==.Ratava:BAAANQADCgYIDwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgQIBQAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reldarus:BAEANQAECgEIAQAAAA==.Rena:BAAANQAECgUIBwAAAA==.Revilation:BAAANQADCgcIDQAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Rezzyk:BAAANQAECgEIAQAAAA==.',
Rh='Rhyxali:BAAANQADCgYIEAAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sacredscales:BAAANQADCgMIAwAAAA==.Samvimes:BAAANQADCggIGQAAAA==.Sangreene:BAAANQAECgUIBwAAAA==.Sargis:BAAANQAECgMIBAAAAA==.',
Sc='Schrödinger:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECgUIBwABAAAAAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAAANQADCgUIBQAAAA==.Shamemoon:BAAANQAECgEIAQAAAA==.Shamunroe:BAAANQAECgEIAQAAAA==.Shatterhoof:BAAANQADCgcIEAAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAAANQAECgcICgAAAA==.Shylindra:BAAANQADCgUICgAAAA==.',
Si='Sigourney:BAAANQAECgEIAQAAAA==.Silversho:BAAANQADCgUICgAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sl='Slighttrash:BAAANQADCggIDgAAAA==.',
Sm='Smallcrow:BAAANQAECggICwAAAA==.',
So='Somdot:BAAANQAECgYIBgABNQAECggIDAABAAAAAA==.Somedeekay:BAAANQAECgIIAgAAAA==.',
Sp='Spirit:BAAANQAECgQIBAAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQADCgcIDwAAAA==.Straven:BAAANQADCgcICQAAAA==.Sturgeson:BAAANQAECgcIDgAAAA==.',
Su='Sulwen:BAAANQAECgEIAQAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQADCgUIBQAAAA==.',
Sw='Swiftfeet:BAAANQAECgIIAgAAAA==.',
['Sé']='Sésho:BAAANQADCgIIAgAAAA==.',
['Sö']='Söranin:BAAANQADCgYIBgAAAA==.',
['Sø']='Sømdøt:BAAANQAECggIDAAAAA==.',
Ta='Taeili:BAAANQADCggIFAAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAAANQAECgYIDQAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQADCggIDAAAAA==.Theodis:BAAANQADCgQICAAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgIIAgAAAA==.Timothyjohn:BAAANQADCgYIDwAAAA==.Tinkphooey:BAAANQADCgEIAQAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Tituba:BAAANQAECgIIAgAAAA==.',
To='Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.',
Ts='Tsuruga:BAAANQAECgEIAQAAAA==.',
Tu='Turkwise:BAAANQADCgYIBwAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgEIAQAAAA==.',
Va='Valany:BAAANQADCgIIAgAAAA==.Valkira:BAAANQAECgYIDQAAAA==.Valton:BAAANQAECgYIDQAAAA==.Vanillanice:BAAANQADCgMIBAAAAA==.Vaxaldan:BAAANQAECgEIAQAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAAANQAECgYIDQAAAA==.Vex:BAAANQADCgYICwAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.',
Vo='Voidleader:BAAANQADCgYIBgAAAA==.Vostok:BAAANQAECgIIAgAAAA==.',
Wa='Warramag:BAAANQADCggIFAAAAA==.Warranni:BAAANQAECgIIAgAAAA==.',
We='Weekend:BAAANQAECgEIAQAAAA==.',
Wh='Whatafox:BAAANQAECgIIAgAAAA==.',
Wi='Wikket:BAAANQAECgEIAQAAAA==.',
Wy='Wyelie:BAAANQAECgEIAQAAAA==.',
Xa='Xade:BAAANQAECgMIBAAAAA==.Xandendon:BAAANQAECgUIBgAAAA==.',
Xe='Xevin:BAAANQAECgIIAgAAAA==.',
Ya='Yaákov:BAAANQAECgYIBAAAAA==.',
Yi='Yinosai:BAAANQADCgUICAAAAA==.',
Yo='Yougot:BAAANQADCgYICAAAAA==.',
Za='Zanarkin:BAAANQADCgYICAAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAAANQAECgcIDgAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQADCgQIBgAAAA==.Zerolicious:BAAANQADCggICAAAAA==.Zeroprophecy:BAAANQADCgIIAgAAAA==.Zevvo:BAAANQAECgEIAQAAAA==.',
Zo='Zoraji:BAAANQAECgMIBAAAAA==.',
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
