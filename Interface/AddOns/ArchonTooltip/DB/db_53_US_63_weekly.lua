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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','Unknown-Unknown','Monk-Windwalker','Paladin-Holy','Hunter-Survival','Paladin-Retribution','Shaman-Elemental','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abdalhazred:BAABNQAECoEaAAMBAAgJ9CAZAQDrAgABAAgJ6CAZAQDrAgACAAIJoRhVPQCUAAAAAA==.Abilus:BAAANQAECgMIBQAAAA==.Abolis:BAAANQADCgIIBQAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUIBwAAAA==.',
Am='Amoradis:BAAANQADCgIIAgAAAA==.',
An='Anarran:BAAANQADCgUIBwAAAA==.Animalfury:BAAANQADCgEIAQAAAA==.Anthestria:BAAANQADCgcICwAAAA==.',
Aq='Aqurala:BAAANQAECgUIBQAAAA==.',
Ar='Aravenn:BAAANQAECgUICwAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgMIAwABNQAECgkJHAADAGYdAA==.Artison:BAAANQADCgYIBgABNQAECgIIBAAEAAAAAA==.',
At='Ateup:BAAANQADCgQIBAABNQAECgUIBwAEAAAAAA==.',
Av='Avatartele:BAAANQADCggIDQAAAA==.Avatartouka:BAAANQAECgYIDwAAAA==.Avraria:BAAANQAECgMIAwAAAA==.',
Az='Azshaxa:BAABNQAECoEcAAIFAAkJNxnACwCPAgAFAAkJNxnACwCPAgAAAA==.',
['Aí']='Aísling:BAAANQADCgcIFgAAAA==.',
Ba='Bagador:BAAANQAECgYIDAAAAA==.',
Be='Beautifulluv:BAAANQAECgUIBQAAAA==.Bekabeka:BAABNQAECoEcAAIGAAgJEB5ZEwDGAgAGAAgJEB5ZEwDGAgAAAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAAANQAECgYIDAAAAA==.',
Bo='Bonski:BAAANQADCgMIAwAAAA==.Boosterman:BAAANQAECgIIAgAAAA==.',
Br='Brakkar:BAAANQADCgYICAAAAA==.Braxxis:BAAANQADCggIDgABNQAECgkJHQAHAKMbAA==.Breadstick:BAAANQAECgIIAgAAAA==.Bress:BAAANQADCgYIBgABNQAECgYIDwAEAAAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Bruutaal:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgIIAwAAAA==.',
Ce='Celaian:BAAANQAECgQIBwABNQAECgQIBAAEAAAAAA==.Celpanda:BAAANQAECgQIBAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Charybdia:BAAANQADCgcIEwAAAA==.Cheesecake:BAAANQAECgYICwAAAA==.Chidõri:BAAANQAECggIEQAAAA==.Chunni:BAAANQAECgUIBQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.',
Cr='Crayonman:BAAANQAECgQICgAAAA==.',
Da='Dahlynar:BAAANQAECgIIAgAAAA==.Dalov:BAAANQAECgIIAwAAAA==.Dankley:BAAANQADCgcIFgAAAA==.Danystorm:BAAANQADCgcIBwABNQAECgkJHAADAGYdAA==.',
Dd='Ddream:BAAANQADCgEIAQAAAA==.',
De='Deaddude:BAAANQAECgYIEAAAAA==.Deathboi:BAAANQAECgQIBAAAAA==.Deathcuddles:BAAANQAECgIIAgAAAA==.',
Di='Diana:BAAANQAECgUICAAAAA==.',
Do='Dontjudgemê:BAAANQADCgYICgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYIDwAAAA==.Dragonwarrio:BAAANQAECgcIDwAAAA==.Draltina:BAAANQAECgMIAwAAAA==.Drazira:BAAANQADCgYIBwAAAA==.Dresstokill:BAAANQADCggIEQAAAA==.Drmonkborg:BAAANQAECgUICwAAAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCgUICQAAAA==.',
Du='Dubaltrok:BAAANQADCgQIBAAAAA==.Dulapin:BAAANQADCgEIAQAAAA==.Duskfu:BAAANQAECgIIBAAAAA==.Dustylock:BAAANQAECgMIBwAAAA==.',
Em='Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIAQAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUIBwAEAAAAAA==.Eryi:BAAANQADCgcIGAAAAA==.',
Ev='Eviserator:BAAANQADCgMIBAAAAA==.',
Fa='Fangytooth:BAAANQADCgYIBgABNQAECgQICgAEAAAAAA==.Faze:BAAANQAECgIIAgAAAA==.',
Fb='Fbiravebae:BAAANQADCggIFAABNQAECgYIDwAEAAAAAA==.',
Fe='Feydoria:BAAANQADCgQIBAAAAA==.',
Fr='Frontman:BAAANQAECgEIAwAAAA==.Frostscythe:BAAANQABCgIIAgAAAA==.',
Fu='Funkycolors:BAAANQADCgYIBgABNQAECgMIBwAEAAAAAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQADCgcIFgAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gl='Gloçk:BAAANQAECgUICAAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAAANQADCgcIBgAAAA==.',
Gu='Gunduin:BAAANQAECgQIDQABNQAECgUICgAEAAAAAA==.',
Gy='Gyda:BAAANQAECgcIEAAAAA==.Gyuyuki:BAAANQAECgYIDAAAAA==.',
Ha='Hakeo:BAEANQAECgUIBgAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQADCgYIBwAAAA==.',
Ho='Homiekissér:BAAANQAECgIIAgAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQADCgYIBwAAAA==.',
Im='Imakittycat:BAAANQAECgQIBQAAAA==.Impared:BAAANQAECgYIBgAAAA==.',
Ja='Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAAANQAECgQIBgAAAA==.',
Jo='Josephyn:BAAANQAECgQIBAABNQAECgkJHAADAGYdAA==.',
Ju='Jugernaut:BAAANQABCgQIBAAAAA==.',
Ka='Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAAANQAECgYIDQAAAA==.Kalypsso:BAAANQADCgIIAgAAAA==.Kargar:BAAANQAECgEIAQAAAA==.Karot:BAAANQADCgYIEAAAAA==.Katharsis:BAAANQAECgYIDQAAAA==.',
Kh='Khalidisi:BAAANQAECgcIDAAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgEIAQAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Ko='Korbulo:BAAANQAECgIIAgAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgUICwAEAAAAAA==.',
Kr='Kronar:BAAANQADCgMIAwAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQADCgcIDAAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kynsong:BAAANQAECgQICQAAAA==.',
Le='Lerazal:BAAANQAECgQIBAAAAA==.Lexanteus:BAAANQADCgUIBQAAAA==.',
Li='Liir:BAAANQAECgIIAgAAAA==.Lilbilly:BAAANQADCgYIDgAAAA==.Lildh:BAAANQADCgEIAQAAAA==.',
Lo='Lorastyrell:BAAANQABCgEIAQAAAA==.Loìsbethe:BAAANQADCggIEgAAAA==.',
Lu='Luciferra:BAAANQAECgcIDQABNQAECgkJHAADAGYdAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Magelock:BAAANQAECgIIAgABNQAECgQIBwAEAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAEAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgUICgAAAA==.Maliboo:BAAANQAECgQICgAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAAANQAECgcIDgAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgIIAgAAAA==.Medívh:BAAANQADCgYIBgAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAAANQAECgQIBAAAAA==.Merkshamalot:BAAANQABCgYIDAABNQAECgQIBAAEAAAAAA==.Merkur:BAAANQADCgYIDQABNQAECgQIBAAEAAAAAA==.Merkurry:BAAANQABCgYICgABNQAECgQIBAAEAAAAAA==.',
Mo='Modifiedmix:BAAANQADCgUICgAAAA==.',
['Må']='Mågi:BAAANQADCgYIDAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECoEeAAMGAAcJgxGiOgDMAQAGAAcJgxGiOgDMAQAIAAMJEwZowQB2AAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIIAwAAAA==.',
Ne='Neptune:BAABNQAECoEcAAIDAAkJZh0kDgDvAgADAAkJZh0kDgDvAgAAAA==.Nerfpaladins:BAAANQAECgEIAQAAAA==.Nerfpriests:BAAANQAECgQICgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.',
Ok='Oktobra:BAAANQAECgIIAgAAAA==.',
On='Onos:BAAANQADCggICAAAAA==.',
Or='Orillin:BAAANQAECgYIDQAAAA==.Orioan:BAAANQAECgUIBgAAAA==.',
Os='Osun:BAAANQADCgUIBwAAAA==.',
Pa='Paddy:BAAANQADCgcIFgAAAA==.Palantyr:BAABNQAECoEfAAIJAAgJmgNVUABnAQAJAAgJmgNVUABnAQAAAA==.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAAANQAECgIIAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAAANQAECgIIAwAAAA==.Raddish:BAAANQAECgIIAgAAAA==.Raedl:BAAANQAECgQIBQAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramranch:BAAANQADCgQIBAABNQAECgYIDAAEAAAAAA==.Randay:BAAANQAECggIBwAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQICQAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Revenge:BAAANQAECgQICgAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQAAAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Rika:BAAANQADCgYIBgAAAA==.',
Ro='Robolich:BAAANQADCggIEwAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAEAAAAAA==.Roshwyn:BAAANQADCgcIEgAAAA==.Rottedmeat:BAAANQAECgYIBQAAAA==.',
Ru='Rubmytotems:BAAANQAECgIIAgAAAA==.Ruckus:BAAANQAECgYICgAAAA==.',
Rx='Rxmblock:BAAANQADCgUICAAAAA==.',
Sa='Saelin:BAAANQADCgcIBwABNQAECgIIAgAEAAAAAA==.Sareenastar:BAAANQAECgYIEAAAAA==.',
Se='Serenitynow:BAAANQADCgIIAgAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgIIAQAAAA==.Shamrox:BAAANQADCgUIBQAAAA==.Sharar:BAAANQAECgUIBQAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sheraa:BAAANQADCgcIDwAAAA==.Shieldknight:BAAANQADCgQIAgAAAA==.Shiftystrike:BAAANQADCgYIDAAAAA==.Shifushield:BAAANQADCggIEQAAAA==.',
Si='Silentwindy:BAAANQADCgYIBgAAAA==.Silmarkthree:BAAANQAECgUIDQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAAANQAECgYIDwAAAA==.',
Sl='Slipknoth:BAABNQAECoEeAAMKAAkJhSHVBwAWAwAKAAgJbSHVBwAWAwALAAMJEwtJbgC1AAAAAA==.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAABNQAECoEdAAMHAAkJoxs7AQD5AgAHAAkJoxs7AQD5AgAMAAEJYw2MSAA/AAAAAA==.Sorrel:BAAANQADCgYIBgAAAA==.',
Sp='Specialmove:BAAANQAECgQIBAAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgMIBgAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCgcIEwAAAA==.Stormstream:BAAANQADCgMIBAAAAA==.',
Su='Suelustra:BAAANQADCgIIAgABNQADCgcIEQAEAAAAAA==.',
Sy='Sykotyk:BAAANQAECgUICwAAAA==.',
Ta='Tadagain:BAAANQAECgIIAgAAAA==.Talairn:BAAANQADCgIIAgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgIIAgAAAA==.Tankybears:BAAANQAECgIIAgAAAA==.Tart:BAAANQADCgcIFgAAAA==.',
Te='Telekinesis:BAAANQAECgYIDwAAAA==.Tenara:BAAANQAECgQICgABNQAECgIIAgAEAAAAAA==.Teos:BAAANQADCgYIBgAAAA==.',
Th='Thaliak:BAAANQADCgYIBwABNQAECgQIBwAEAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAAANQAECgMIBQAAAA==.',
Tr='Tracther:BAAANQADCgYICAAAAA==.Trapps:BAAANQADCgYIBgAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgQICQAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgQICgAAAA==.',
Ul='Ullhr:BAAANQADCgMIBQAAAA==.',
Va='Valock:BAAANQADCgcIDgAAAA==.Vanshifty:BAAANQAECgUIDQAAAA==.',
Ve='Venli:BAAANQADCgQIBAAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQADCgcIFgAAAA==.',
Wa='Waffle:BAAANQAECgIIAgAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.',
Wi='Wizzard:BAAANQAECgIIAgAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQADCggIFwABNQAECgQICQAEAAAAAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Zb='Zbm:BAAANQAECgIIAgAAAA==.',
Ze='Zeldy:BAAANQAECgMIAwAAAA==.Zenthareal:BAAANQAECgQICAAAAA==.Zenzi:BAAANQADCgQIBAAAAA==.',
Zm='Zmaster:BAAANQAECgUICwAAAA==.',
Zu='Zunarri:BAAANQADCgYICAAAAA==.',
Zw='Zwar:BAAANQADCgMIAwABNQAECgUICwAEAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECoEZAAINAAkJ0BqDEwDbAgANAAkJ0BqDEwDbAgAAAA==.',
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
