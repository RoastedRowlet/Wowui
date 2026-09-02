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
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abrocklock:BAAANQADCgQIBAAAAA==.',
Ad='Adorabull:BAAANQADCgcIDQAAAA==.',
Ae='Aedreline:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Aevelee:BAAANQADCgUIBwAAAA==.',
Al='Allucard:BAAANQADCgcIDQAAAA==.',
An='Anduîiîn:BAAANQADCggICAAAAA==.Antarias:BAAANQADCggIFAAAAA==.',
Ar='Arckenon:BAAANQAECgEIAQAAAA==.Arranix:BAAANQADCgMIAwAAAA==.',
As='Ashog:BAAANQADCgUIBQAAAA==.',
At='Atillis:BAAANQADCgUIBQAAAA==.',
Au='Austenpally:BAAANQADCggICgAAAA==.',
Av='Aveycado:BAAANQADCgYIDQAAAA==.',
Ax='Axeflack:BAAANQAECgMIAwAAAA==.',
Az='Azaral:BAAANQADCgQIBAAAAA==.Azmarija:BAAANQADCgEIAQAAAA==.',
Bi='Biancadelrio:BAAANQADCgMIAwAAAA==.Bigguberment:BAAANQADCgUICAAAAA==.',
Bl='Bladekrim:BAAANQADCgQIBAAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boredgored:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Botia:BAAANQADCgUIBAAAAA==.Bourdeaux:BAAANQADCgcIDQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brizik:BAAANQABCgMIAwAAAA==.Bruised:BAAANQADCggIDgAAAA==.Brunae:BAAANQADCgcICwAAAA==.Brunnera:BAAANQADCgQIBQAAAA==.Bruul:BAAANQADCgYIDAAAAA==.',
Ca='Carcharoth:BAAANQADCgMIAwAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.',
Ch='Chadgar:BAAANQAECgIIAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAAANQAECgQIBQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chíef:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.',
Cr='Crataxxis:BAAANQADCggIDgAAAA==.',
Cu='Cudara:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAAANQAECgIIAgAAAA==.Cythraul:BAAANQADCgcIDQAAAA==.',
Da='Daerith:BAAANQADCgYIBgAAAA==.Daerrith:BAAANQADCgMIAwAAAA==.Dagni:BAAANQADCggICQAAAA==.Darrwin:BAAANQADCgUIBwAAAA==.',
Df='Dfabness:BAAANQADCgcIDQAAAA==.',
Di='Diizmyster:BAAANQADCggICAAAAA==.',
Dr='Dracthayr:BAAANQAECgEIAQAAAA==.Dragonhammer:BAAANQADCgcIBwAAAA==.Drimclaw:BAAANQADCgcICwAAAA==.Drubo:BAAANQADCgYICwAAAA==.Drx:BAAANQAECgEIAQAAAA==.',
Du='Dukkelemon:BAAANQAECgMIAwAAAA==.',
El='Elanore:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Elison:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Elliana:BAAANQAECgEIAQAAAA==.Ellie:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Elloise:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Elsae:BAAANQAECgEIAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Everios:BAAANQAECgQIBgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Evánder:BAAANQADCggICAAAAA==.',
Fa='Faeleader:BAAANQADCggIDAAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Faytadori:BAAANQAECgEIAQAAAA==.',
Fe='Felgrrl:BAAANQADCgQIBAAAAA==.Feyreh:BAAANQADCgUIBQAAAA==.',
Fi='Fidget:BAAANQADCgcICwAAAA==.',
Fl='Fletch:BAAANQADCggICgAAAA==.',
Fo='Forever:BAAANQADCgUIDgAAAA==.',
Fr='Frique:BAAANQADCgMIBgAAAA==.Frozenyogert:BAAANQADCgQIBAAAAA==.',
Ga='Galbur:BAAANQAECgQIBwAAAA==.Galdrin:BAAANQAECgIIAwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAAANQAECgcICQAAAA==.',
Ge='Geers:BAAANQADCgcICwAAAA==.Getarage:BAAANQAECgIIAgAAAA==.Getasoar:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Gh='Ghil:BAAANQADCgYICgAAAA==.',
Gi='Gilia:BAAANQADCgUICQAAAA==.',
Gl='Glynix:BAAANQADCgEIAQAAAA==.',
Go='Goku:BAAANQADCgcICQAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQADCggIDgAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQADCgcIDAAAAA==.',
Gu='Gunderthirth:BAAANQAECgcICwAAAA==.',
Gw='Gwaeniiha:BAAANQADCgUICQAAAA==.',
Ha='Haliran:BAAANQADCgIIAgAAAA==.Handsoap:BAAANQADCgcIDQAAAA==.Harakhty:BAAANQADCgQIBAAAAA==.Hardhitter:BAAANQAECgQIBAAAAA==.',
He='Hellumph:BAAANQADCggIDgAAAA==.Hevensrath:BAAANQADCgEIAQAAAA==.',
Ho='Hokuden:BAAANQAECgEIAQAAAA==.',
Hu='Huddington:BAAANQADCgcIDgAAAA==.',
In='Indecent:BAAANQADCgcIDAAAAA==.Inibble:BAAANQABCgQIBAAAAA==.',
Is='Ishy:BAAANQADCggIDQAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAAANQAECgQIBAAAAA==.Jackieplays:BAAANQAECgQIBwAAAA==.Jaded:BAAANQADCggIDAAAAA==.',
Ju='Jutic:BAAANQAECgEIAQAAAA==.',
Ka='Kardas:BAAANQADCggIDQAAAA==.',
Kb='Kbilly:BAAANQADCggIDgAAAA==.',
Ke='Kentarou:BAAANQABCgMIAwAAAA==.Keylerin:BAAANQAECgYIBwAAAA==.',
Ki='Kitsunami:BAAANQABCgMIAwAAAA==.',
Kn='Knottes:BAAANQABCgQIBAAAAA==.',
Kr='Krampus:BAAANQADCgcIDgAAAA==.Kranok:BAAANQADCgcICwAAAA==.Krennthis:BAAANQADCgQIBQAAAA==.Krimbruiser:BAAANQADCgYIBwAAAA==.',
Ku='Kunac:BAAANQADCgUIBQAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.',
Lh='Lhani:BAAANQADCgcIBwAAAA==.',
Li='Lilguysci:BAAANQADCgYIBgAAAA==.',
Ll='Llyrael:BAAANQADCgIIAgAAAA==.',
Lu='Lugosi:BAAANQADCgYIBgAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Maddeleine:BAAANQADCgEIAQAAAA==.Magara:BAAANQADCgcICgAAAA==.Magicdemon:BAAANQADCgcIDQAAAA==.Malaah:BAAANQADCggIDAAAAA==.Mansuno:BAAANQAECgQIBgAAAA==.Mapachote:BAAANQADCgYICwAAAA==.Marodin:BAAANQADCgUICQAAAA==.Mazboda:BAAANQAECgIIAgAAAA==.',
Me='Meatbaal:BAAANQAECgIIAgAAAA==.Melinaria:BAAANQADCggIDgAAAA==.',
Mi='Mileta:BAAANQADCggIDgAAAA==.Minuette:BAAANQADCgYIBgAAAA==.',
Na='Nazgul:BAAANQADCgYIBgAAAA==.',
Ne='Necroreign:BAAANQAECgEIAQAAAA==.Need:BAAANQADCggIDgAAAA==.Neherenia:BAAANQADCgcIDQAAAA==.Nessee:BAAANQADCgcIBwAAAA==.',
Ni='Niall:BAAANQAECgEIAQAAAA==.Nihowdy:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAAANQADCgYICgAAAA==.Ortalbem:BAAANQAECgEIAQAAAA==.',
Ov='Ovi:BAAANQADCgUIBQAAAA==.',
Ph='Philipfry:BAAANQAECgMIAwAAAA==.',
Po='Poomacha:BAAANQADCgQIBgAAAA==.Potatopants:BAAANQADCgQIBAAAAA==.',
Pr='Prinlina:BAAANQADCgUIBQAAAA==.',
Py='Pyree:BAAANQADCgcIDgAAAA==.',
Qu='Qu:BAAANQADCggICAAAAQ==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raistlain:BAAANQADCggIDgAAAA==.Ralli:BAAANQADCgQIBAAAAA==.Rallsodins:BAAANQAECgMIAwAAAA==.Ranulf:BAAANQADCgMIAwAAAA==.Ratava:BAAANQADCgUICQAAAA==.Ratrot:BAAANQADCgEIAQAAAA==.',
Re='Reddemon:BAAANQAECgEIAQAAAA==.Reldarus:BAEANQADCgcIDgAAAA==.Rena:BAAANQAECgIIAgAAAA==.Revilation:BAAANQADCgcIBwAAAA==.Rezzyk:BAAANQADCgcIDQAAAA==.',
Rh='Rhyxali:BAAANQADCgYICgAAAA==.',
Ri='Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQIBgAAAA==.',
Sa='Sacredscales:BAAANQADCgMIAwAAAA==.Samvimes:BAAANQADCgYICgAAAA==.Sangreene:BAAANQAECgIIAgAAAA==.Sargis:BAAANQAECgEIAQAAAA==.',
Sc='Scott:BAAANQAECgQIBAAAAA==.',
Se='Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgQIBgABNQAECgIIAgABAAAAAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgYICQAAAA==.Shagol:BAAANQADCgUIBQAAAA==.Shamemoon:BAAANQADCgcIBwAAAA==.Shamunroe:BAAANQADCgcICgAAAA==.Shatterhoof:BAAANQADCgYICQAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAAANQAECgUIBQAAAA==.Shylindra:BAAANQADCgQIBQAAAA==.',
Si='Sigourney:BAAANQADCgYICwAAAA==.Silversho:BAAANQADCgQIBQAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sl='Slighttrash:BAAANQADCgYICwAAAA==.',
Sm='Smallcrow:BAAANQAECgMIAwAAAA==.',
So='Somedeekay:BAAANQADCgYIBgAAAA==.',
Sp='Spirit:BAAANQAECgQIBAAAAA==.',
St='Starga:BAAANQADCgMIAwAAAA==.Starge:BAAANQADCgUIBQAAAA==.Steffey:BAAANQADCgYICAAAAA==.Straven:BAAANQADCgcICQAAAA==.Sturgeson:BAAANQAECgYIBwAAAA==.',
Su='Sulwen:BAAANQADCggIDgAAAA==.',
Sw='Swiftfeet:BAAANQADCggIDQAAAA==.',
['Sö']='Söranin:BAAANQADCgYIBgAAAA==.',
['Sø']='Sømdøt:BAAANQAECggICQAAAA==.',
Ta='Taeili:BAAANQADCgcIDAAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAAANQAECgQIBwAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQADCgQIBAAAAA==.Theodis:BAAANQADCgIIBAAAAA==.',
Ti='Tillago:BAAANQADCgUIBQAAAA==.Timothy:BAAANQADCgYIBgAAAA==.Timothyjohn:BAAANQADCgUICQAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
To='Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgUICAAAAA==.',
Ts='Tsuruga:BAAANQADCgcIDgAAAA==.',
Tu='Turkwise:BAAANQADCgYIBwAAAA==.',
Ur='Urobolos:BAAANQAECgEIAQAAAA==.',
Uv='Uvari:BAAANQADCgYICwAAAA==.',
Va='Valkira:BAAANQAECgQIBwAAAA==.Valton:BAAANQAECgQIBwAAAA==.Vanillanice:BAAANQADCgIIAgAAAA==.Vaxaldan:BAAANQADCgcIDgAAAA==.',
Ve='Venj:BAAANQADCgYICQAAAA==.Ventosa:BAAANQAECgQIBwAAAA==.Vex:BAAANQADCgUICwAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgUIBQAAAA==.',
Vo='Vostok:BAAANQADCggIDgAAAA==.',
Wa='Warranni:BAAANQAECgEIAQAAAA==.',
We='Weekend:BAAANQADCggIDgAAAA==.',
Wh='Whatafox:BAAANQADCggIDAAAAA==.',
Wi='Wikket:BAAANQADCgIIAgAAAA==.',
Wy='Wyelie:BAAANQADCgYICwAAAA==.',
Xa='Xade:BAAANQAECgEIAQAAAA==.Xandendon:BAAANQAECgEIAQAAAA==.',
Xe='Xevin:BAAANQAECgEIAQAAAA==.',
Ya='Yaákov:BAAANQADCgcIDQAAAA==.',
Yi='Yinosai:BAAANQADCgIIAwAAAA==.',
Yo='Yougot:BAAANQADCgUIBQAAAA==.',
Za='Zanarkin:BAAANQADCgQIBAAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAAANQAECgYIBwAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.',
Ze='Zerdah:BAAANQADCgYIDAAAAA==.Zerogasm:BAAANQADCgQIBgAAAA==.Zevvo:BAAANQADCgcIDgAAAA==.',
Zo='Zoraji:BAAANQAECgEIAQAAAA==.',
['Ëd']='Ëdën:BAAANQADCgQIBAAAAA==.',
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
