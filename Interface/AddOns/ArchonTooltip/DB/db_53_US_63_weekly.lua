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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Holy',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abdalhazred:BAAANQAECgcIEAAAAA==.Abilus:BAAANQAECgMIBAAAAA==.Abolis:BAAANQADCgIIBQAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgEIAgAAAA==.',
Am='Amoradis:BAAANQADCgIIAgAAAA==.',
An='Anarran:BAAANQADCgUIBwAAAA==.Animalfury:BAAANQADCgEIAQAAAA==.Anthestria:BAAANQADCgYIBgAAAA==.',
Aq='Aqurala:BAAANQAECgIIAgAAAA==.',
Ar='Aravenn:BAAANQAECgQIBgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Artison:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Av='Avatartele:BAAANQADCgYIBQAAAA==.Avatartouka:BAAANQAECgYIDAAAAA==.Avraria:BAAANQADCggIEAAAAA==.',
Az='Azshaxa:BAAANQAECgcIEQAAAA==.',
['Aí']='Aísling:BAAANQADCgcIDwAAAA==.',
Ba='Bagador:BAAANQAECgUIBgAAAA==.',
Be='Beautifulluv:BAAANQAECgIIAgAAAA==.Bekabeka:BAAANQAECgcIEQAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAAANQAECgYIBgAAAA==.',
Bo='Bonski:BAAANQADCgEIAQAAAA==.Boosterman:BAAANQADCggIEAAAAA==.',
Br='Brakkar:BAAANQADCgUIBgAAAA==.Braxxis:BAAANQADCggIDgABNQAECgcIEQABAAAAAA==.Breadstick:BAAANQAECgIIAgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgIIAgAAAA==.',
Ce='Celaian:BAAANQAECgQIBwAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQADCggIDgABAAAAAA==.Charybdia:BAAANQADCgcIDAAAAA==.Cheesecake:BAAANQAECgYIBwAAAA==.Chidõri:BAAANQAECgYIDAAAAA==.Chunni:BAAANQAECgIIAgAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.',
Cr='Crayonman:BAAANQAECgQIBgAAAA==.',
Da='Dahlynar:BAAANQADCggIDgAAAA==.Dalov:BAAANQAECgIIAgAAAA==.Dankley:BAAANQADCgcIDwAAAA==.Danystorm:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Dd='Ddream:BAAANQADCgEIAQAAAA==.',
De='Deaddude:BAAANQAECgYICgAAAA==.Deathboi:BAAANQADCggIFQAAAA==.Deathcuddles:BAAANQADCgcIDwAAAA==.',
Di='Diana:BAAANQAECgMIAwAAAA==.',
Do='Dontjudgemê:BAAANQADCgUIBQAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYICgAAAA==.Dragonwarrio:BAAANQAECgUICAAAAA==.Draltina:BAAANQADCggIFwAAAA==.Drazira:BAAANQADCgYIBgAAAA==.Dresstokill:BAAANQADCgcICQAAAA==.Drmonkborg:BAAANQAECgUICwAAAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCgUICQAAAA==.',
Du='Duskfu:BAAANQAECgIIAgAAAA==.Dustylock:BAAANQADCgcIDwAAAA==.',
Em='Emmel:BAAANQADCgYIBgAAAA==.',
Er='Eromir:BAAANQAECgMIAwAAAA==.Eryi:BAAANQADCgcIEQAAAA==.',
Ev='Eviserator:BAAANQADCgMIBAAAAA==.',
Fa='Fangytooth:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Faze:BAAANQADCgcIDwAAAA==.',
Fb='Fbiravebae:BAAANQADCggIDQABNQAECgYICgABAAAAAA==.',
Fe='Feydoria:BAAANQADCgQIBAAAAA==.',
Fr='Frontman:BAAANQAECgEIAgAAAA==.',
Fu='Funkycolors:BAAANQABCgEIAQABNQADCgcIDwABAAAAAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQADCgcIDwAAAA==.',
Gl='Gloçk:BAAANQAECgUICAAAAA==.',
Gr='Graeae:BAAANQADCgIIAgAAAA==.Grimaldi:BAAANQADCgYIBQAAAA==.',
Gu='Gunduin:BAAANQAECgQICQAAAA==.',
Gy='Gyda:BAAANQAECgYICQAAAA==.Gyuyuki:BAAANQAECgUIBgAAAA==.',
Ha='Hakeo:BAEANQAECgIIAgAAAA==.',
Ho='Homiekissér:BAAANQAECgIIAgAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
Im='Imakittycat:BAAANQAECgEIAQAAAA==.',
Ja='Jacenne:BAAANQAECgEIAQAAAA==.',
Je='Jenesis:BAAANQAECgQIBgAAAA==.',
Ju='Jugernaut:BAAANQABCgQIBAAAAA==.',
Ka='Kakuta:BAAANQAECgUIBwAAAA==.Kargar:BAAANQADCgYIBgAAAA==.Karot:BAAANQADCgYIEAAAAA==.Katharsis:BAAANQAECgYIBwAAAA==.',
Kh='Khalidisi:BAAANQAECgUIBQAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Ko='Korbulo:BAAANQAECgIIAgAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.',
Kr='Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQADCgcIDAAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kynsong:BAAANQAECgQIBQAAAA==.',
Le='Lerazal:BAAANQAECgEIAQAAAA==.Lexanteus:BAAANQADCgUIBQAAAA==.',
Li='Liir:BAAANQADCggICAAAAA==.Lilbilly:BAAANQADCgYIDgAAAA==.',
Lo='Loìsbethe:BAAANQADCgYIDgAAAA==.',
Lu='Luciferra:BAAANQAECgYIBwABNQAECgcIEAABAAAAAA==.',
Ly='Lytho:BAAANQAECgEIAQAAAA==.',
Ma='Magelock:BAAANQADCggIBwABNQAECgMIBQABAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgMIBQABAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.Maliboo:BAAANQAECgQIBgAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAAANQAECgYIBwAAAA==.',
Me='Medarisa:BAAANQADCggIDgAAAA==.Medívh:BAAANQADCgYIBgAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAAANQADCggIFgAAAA==.Merkshamalot:BAAANQABCgYIDAABNQADCggIFgABAAAAAA==.Merkur:BAAANQADCgUIBwABNQADCggIFgABAAAAAA==.Merkurry:BAAANQABCgYIBgABNQADCggIFgABAAAAAA==.',
Mo='Modifiedmix:BAAANQADCgUICgAAAA==.',
['Må']='Mågi:BAAANQADCgYIDAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAAANQAECgUIDQAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgEIAQAAAA==.',
Ne='Neptune:BAAANQAECgcIEAAAAA==.Nerfpaladins:BAAANQADCggIFgAAAA==.Nerfpriests:BAAANQAECgQIBgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.',
Ok='Oktobra:BAAANQADCgcIDwAAAA==.',
On='Onos:BAAANQADCggICAAAAA==.',
Or='Orillin:BAAANQAECgQIBwAAAA==.Orioan:BAAANQAECgEIAQAAAA==.',
Os='Osun:BAAANQADCgUIBwAAAA==.',
Pa='Paddy:BAAANQADCgcIDwAAAA==.Palantyr:BAAANQAECgYIDQAAAA==.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAAANQADCgcICwAAAA==.',
Pe='Pellidillion:BAAANQADCgQIBAAAAA==.',
Po='Polgára:BAAANQADCggIDwAAAA==.',
Pu='Purity:BAAANQADCgYICwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAAANQAECgEIAQAAAA==.Raddish:BAAANQADCgcIDwAAAA==.Raedl:BAAANQAECgEIAQAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Randay:BAAANQAECggIBwAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQIBQAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Revenge:BAAANQAECgMIBgAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQAAAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ro='Robolich:BAAANQADCgYICQAAAA==.Rosefist:BAEANQADCgQIBAABNQADCggICAABAAAAAA==.Rosemourne:BAEANQADCggICAAAAA==.Roshwyn:BAAANQADCgYICwAAAA==.Rottedmeat:BAAANQAECgEIAQAAAA==.',
Ru='Rubmytotems:BAAANQADCgcIDwAAAA==.Ruckus:BAAANQAECgQIBAAAAA==.',
Rx='Rxmblock:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQADCgcIBwABNQADCggIEAABAAAAAA==.Sareenastar:BAAANQAECgUICwAAAA==.',
Se='Serenitynow:BAAANQADCgIIAgAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgIIAQAAAA==.Shamrox:BAAANQADCgUIBQAAAA==.Sharar:BAAANQADCggIDwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sheraa:BAAANQADCgcIDwAAAA==.Shieldknight:BAAANQADCgQIAgAAAA==.Shiftystrike:BAAANQADCgYIDAAAAA==.Shifushield:BAAANQADCgcIEQAAAA==.',
Si='Silmarkthree:BAAANQAECgQICAAAAA==.Sinbåd:BAAANQADCgYIBwAAAA==.',
Sk='Skol:BAAANQAECgYICQAAAA==.',
Sl='Slipknoth:BAABNQAECoEWAAMCAAkJIxqVCgCQAgACAAcJUR6VCgCQAgADAAMJKAhFTwC7AAAAAA==.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAAANQAECgcIEQAAAA==.',
Sp='Specialmove:BAAANQABCgIIAgAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgEIAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCgYIDAAAAA==.Stormstream:BAAANQADCgMIBAAAAA==.',
Sy='Sykotyk:BAAANQAECgQIBQAAAA==.',
Ta='Tadagain:BAAANQADCgcIEQAAAA==.Talairn:BAAANQADCgIIAgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQADCggIFQAAAA==.Tankybears:BAAANQADCggIEAAAAA==.Tart:BAAANQADCgcIDwAAAA==.',
Te='Telekinesis:BAAANQAECgYIDAAAAA==.Tenara:BAAANQAECgQIBgABNQADCggIEAABAAAAAA==.Teos:BAAANQADCgYIBgAAAA==.',
Th='Thaliak:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIDgAAAA==.Thunderlily:BAAANQAECgMIAwAAAA==.',
Tr='Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgQIBQAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Ty='Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgQIBgAAAA==.',
Ul='Ullhr:BAAANQADCgMIBQAAAA==.',
Va='Valock:BAAANQADCgcIDQAAAA==.Vanshifty:BAAANQAECgUICAAAAA==.',
Ve='Venli:BAAANQADCgQIBAAAAA==.',
Vo='Voidentine:BAAANQABCgYIBAAAAA==.',
Vy='Vyx:BAAANQADCgcIDwAAAA==.',
Wa='Waffle:BAAANQADCgcIDQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.',
Wi='Wizzard:BAAANQADCggIDgAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQADCgcIDwABNQAECgQIBQABAAAAAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Zb='Zbm:BAAANQADCgcIDAAAAA==.',
Ze='Zeldy:BAAANQADCggIEQAAAA==.Zenthareal:BAAANQAECgQIBgAAAA==.Zenzi:BAAANQADCgQIBAAAAA==.',
Zm='Zmaster:BAAANQAECgQIBgAAAA==.',
Zu='Zunarri:BAAANQADCgYICAAAAA==.',
Zw='Zwar:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAAANQAECggIEAAAAA==.',
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
