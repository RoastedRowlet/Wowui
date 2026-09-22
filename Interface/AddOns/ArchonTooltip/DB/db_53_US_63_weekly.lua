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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Survival','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Warrior-Arms','Priest-Shadow','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abdalhazred:BAABNQAECoEiAAMBAAkKzx/UAAA7AwABAAkKzx/UAAA7AwACAAIKoRifQgCWAAAAAA==.Abilus:BAAANQAECgMJBgAAAA==.Abolis:BAAANQAECgQIBAAAAA==.',
Ae='Aelianna:BAAANQADCgcIBwAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUJCwAAAA==.',
Am='Amoradis:BAAANQADCgUJCgAAAA==.',
An='Anarran:BAAANQADCgUIBwAAAA==.Animalfury:BAAANQAECgUIBQAAAA==.Anthestria:BAAANQADCgcIDwAAAA==.',
Aq='Aqurala:BAAANQAECgYICwAAAA==.',
Ar='Arasham:BAAANQADCgQIBAABNQAECgcJEgADAAAAAA==.Aravenn:BAAANQAECgcJEgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgMIAwABNQAECgkJIgAEAH4dAA==.Artison:BAAANQADCgYIBgABNQAECgMJBwADAAAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUJCwADAAAAAA==.',
Av='Avatartele:BAAANQAECgYIBgAAAA==.Avatartouka:BAABNQAECoEbAAMEAAcKTCGoIQCLAgAEAAcKTCGoIQCLAgAFAAMKah2imADbAAAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECgYICQAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAABNQAECoEfAAIGAAkKrRynDAC1AgAGAAkKrRynDAC1AgAAAA==.',
['Aí']='Aísling:BAAANQADCggJHgAAAA==.',
Ba='Bagador:BAAANQAECgcIDQAAAA==.Barby:BAAANQADCgcICAAAAA==.',
Be='Beautifulluv:BAAANQAECgUIBQAAAA==.Bekabeka:BAABNQAECoElAAMHAAkKPR4SDgAeAwAHAAkKPR4SDgAeAwAIAAEKiQ1iFAE8AAAAAA==.Bekabekabeka:BAAANQABCggJAQABNQAECgkJJQAHAD0eAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAAANQAECgYJEgAAAA==.',
Bo='Bonski:BAAANQADCgMJAwAAAA==.Boosterman:BAAANQAECgQIBgAAAA==.',
Br='Brakkar:BAAANQADCgcIDgAAAA==.Braxxis:BAAANQADCggIDgABNQAECgkJIQAJAHodAA==.Breadstick:BAAANQAECgIIAgAAAA==.Bress:BAAANQADCgYIBgABNQAECgYIDwADAAAAAA==.Britotems:BAAANQAECgEJAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQADCgcICQAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggJCAAAAA==.Canoodles:BAAANQAECgYICQAAAA==.',
Ce='Celaian:BAAANQAECgQICAABNQAECgQICAADAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECgIIAgADAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAAANQAECgcIDAAAAA==.Chidõri:BAAANQAECggIEgAAAA==.Chunni:BAAANQAECgUJBQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.',
Cr='Crayonman:BAAANQAECgYJEAAAAA==.Cruelkitty:BAAANQADCgcIBwAAAA==.',
Da='Dahlynar:BAAANQAECgQJBAAAAA==.Dalov:BAAANQAECgQICwAAAA==.Dankley:BAAANQADCggJHgAAAA==.Danystorm:BAAANQADCgcIBwABNQAECgkJIgAEAH4dAA==.',
Dd='Ddream:BAAANQADCgEIAQAAAA==.',
De='Deaddude:BAABNQAECoEaAAIKAAgKGxulHgBhAgAKAAgKGxulHgBhAgAAAA==.Deathboi:BAAANQAECgQJCAAAAA==.Deathcuddles:BAAANQAECgQJBgAAAA==.',
Di='Diana:BAAANQAECgUIDAAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYJEwAAAA==.Dragonwarrio:BAAANQAECggJEwAAAA==.Draltina:BAAANQAECgMIAwAAAA==.Drazira:BAAANQADCgcJDgAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwAAAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubaltrok:BAAANQADCgQJBAAAAA==.Dulapin:BAAANQADCgIJAgAAAA==.Duskfu:BAAANQAECgMJBwAAAA==.Dustylock:BAAANQAECgQICwAAAA==.',
Ea='Earthele:BAAANQADCggJCAAAAA==.',
El='Elfowl:BAAANQADCgUJBQABNQAECgUIDQADAAAAAA==.',
Em='Emanonsahi:BAAANQABCgQIBAAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggJAgAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUJCwADAAAAAA==.Eryi:BAAANQADCgcIHwAAAA==.',
Ev='Eviserator:BAAANQADCgMIBAAAAA==.',
Fa='Faegen:BAAANQADCgMJAwAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgYJEAADAAAAAA==.Faze:BAAANQAECgMJBQAAAA==.',
Fb='Fbitortamilf:BAAANQADCggJGgAAAA==.',
Fe='Feydoria:BAAANQADCgQIBAAAAA==.',
Fr='Frontman:BAAANQAECgMJBAAAAA==.Frostscythe:BAAANQABCgIIAgAAAA==.',
Fu='Funkycolors:BAAANQADCgYIBgABNQAECgQICwADAAAAAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQADCggJHgAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQADCgcJBwAAAA==.',
Gl='Gloçk:BAAANQAECgUJCAAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAAANQADCgcIBgAAAA==.',
Gu='Gunduin:BAAANQAECgYIEwAAAA==.',
Gy='Gyda:BAABNQAECoEbAAMLAAgKdxK8QQDeAQALAAgKaxK8QQDeAQAMAAIKCgwbFQBsAAAAAA==.Gyuyuki:BAAANQAECgYIEgAAAA==.',
Ha='Hakeo:BAEANQAECgcJDAAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQADCggJDwAAAA==.',
Hi='Hikomosil:BAAANQAECgMIAwAAAA==.',
Ho='Homiekissér:BAAANQAECgYICAAAAA==.',
['Hë']='Hëllen:BAAANQADCgIJAgAAAA==.',
['Hú']='Húñtrèss:BAAANQADCggJDwAAAA==.',
Im='Imakittycat:BAAANQAECgUICgAAAA==.Impared:BAAANQAECgYIBgAAAA==.',
Iv='Ivey:BAAANQADCgMIAwAAAA==.',
Ja='Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAAANQAECgUICQAAAA==.',
Jo='Josephyn:BAAANQAECgQIBAABNQAECgkJIgAEAH4dAA==.',
Ju='Jugernaut:BAAANQABCgQIBAAAAA==.Juggernåut:BAAANQADCgMJAwAAAA==.',
Ka='Kaale:BAAANQABCgUIBwABNQAECgMIBQADAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAAANQAECgYJEwAAAA==.Kalypsso:BAAANQADCgIIAgAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQADCgYJEAAAAA==.Katharsis:BAABNQAECoEWAAIIAAgKNBFIWAD4AQAIAAgKNBFIWAD4AQAAAA==.',
Ke='Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAAANQAECgcIEwAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIJAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korbulo:BAAANQAECgQJBQAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgcJEgADAAAAAA==.',
Kr='Kronar:BAAANQADCgUICAAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgIIAgAAAA==.',
Ku='Kungfuuy:BAAANQADCgQJBgAAAA==.',
Ky='Kylogos:BAAANQADCggJCAAAAA==.Kynsong:BAAANQAECgUIDgAAAA==.Kysia:BAAANQAECgUIBQABNQAECgkJHAAIAHMdAA==.',
['Kî']='Kîrah:BAAANQAECgEIAQAAAA==.',
Le='Lerazal:BAAANQAECgQJCAAAAA==.Lexanteus:BAAANQADCgUJBQAAAA==.',
Li='Liir:BAAANQAECgQJBAAAAA==.Lilbilly:BAAANQADCgYIEAAAAA==.Lildh:BAAANQAECgMIBAAAAA==.',
Lo='Lorastyrell:BAAANQABCgEJAQAAAA==.Loìsbethe:BAAANQAECgQJBAAAAA==.',
Lu='Luciferra:BAABNQAECoEXAAILAAgK6xKkOAAKAgALAAgK6xKkOAAKAgABNQAECgkJIgAEAH4dAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Magelock:BAAANQAECgIIAgABNQAECgQIBwADAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwADAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgYIEwADAAAAAA==.Maliboo:BAAANQAECgYIEAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAAANQAECgcIEAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgQJBgAAAA==.Medívh:BAAANQAECgIJAgAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAAANQAECgUJCQAAAA==.Merkshamalot:BAAANQADCgYIBgABNQAECgUJCQADAAAAAA==.Merkur:BAAANQADCgYJEwABNQAECgUJCQADAAAAAA==.Merkurry:BAAANQADCgQIBAABNQAECgUJCQADAAAAAA==.',
Mo='Modifiedmix:BAAANQADCgUICgAAAA==.',
Mu='Murdette:BAAANQAECgEIAQABNQAECgkJHQANAEUiAA==.',
['Må']='Mågi:BAAANQAECgQJBAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECoEiAAMHAAgKyRLCOQARAgAHAAgKyRLCOQARAgAIAAMKEwZk8QB1AAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgEIAQABNQAECgUJCAADAAAAAA==.',
Ne='Neptune:BAABNQAECoEiAAIEAAkKfh1mFADjAgAEAAkKfh1mFADjAgAAAA==.Nerfpaladins:BAAANQAECgUJBgAAAA==.Nerfpriests:BAAANQAECgUJCwAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.',
['Nè']='Nèo:BAAANQADCgUIBQAAAA==.',
Ok='Oktobra:BAAANQAECgQJBgAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAAANQAECgYIDwAAAA==.Orioan:BAAANQAECgYICwAAAA==.',
Os='Osun:BAAANQADCgYJDQAAAA==.',
Pa='Paddy:BAAANQADCggJHgAAAA==.Palantyr:BAABNQAECoEpAAIFAAkKEwuRPwD5AQAFAAkKEwuRPwD5AQAAAA==.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAAANQAECgcICQAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAAANQAECgQIBwAAAA==.Raddish:BAAANQAECgQIBgAAAA==.Raedl:BAAANQAECgYJCwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgEIAgABNQAECgYJEgADAAAAAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQICQAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Restofolyfe:BAAANQAECgEJAQAAAA==.Revenge:BAAANQAECggIEwAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECgcJFgAKAOwKAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCgcJBwAAAA==.Rifle:BAAANQADCggICAABNQAECgcIEAADAAAAAA==.Rika:BAAANQADCgcIDQAAAA==.',
Ro='Robolich:BAAANQADCggIGwAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQADAAAAAA==.Roshwyn:BAAANQAECgIIAgAAAA==.Rottedmeat:BAAANQAECgcICwAAAA==.',
Ru='Rubmytotems:BAAANQAECgQJBgAAAA==.Ruckus:BAAANQAECgcJEQAAAA==.',
Rx='Rxmblock:BAAANQADCgcJDwAAAA==.',
Sa='Saelin:BAAANQADCgcIBwABNQAECgMIBQADAAAAAA==.Sareenastar:BAABNQAECoEXAAILAAcKICWcEQDyAgALAAcKICWcEQDyAgAAAA==.',
Se='Serenitynow:BAAANQADCgIIAgAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgIIAQAAAA==.Shamrox:BAAANQAECgEJAQAAAA==.Sharar:BAAANQAECgUJBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sheraa:BAAANQADCggIFwAAAA==.Shieldknight:BAAANQADCgQIAgAAAA==.Shiftystrike:BAAANQAECgQJBAAAAA==.Shifushield:BAAANQADCggIEQAAAA==.',
Si='Silentwindy:BAAANQADCgYJCQAAAA==.Silmarkthree:BAAANQAECgYJEwAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECoEWAAIKAAcK7ApRTQBJAQAKAAcK7ApRTQBJAQAAAA==.',
Sl='Slipknoth:BAACNQAFFIEHAAMOAAQKLRpUBgAUAQAOAAMK/hdUBgAUAQALAAEKJws1HABRAAA1AAQKgSEAAw4ACQqtH8YGAEgDAA4ACQqtH8YGAEgDAAsAAwoTC9OKALQAAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAABNQAECoEhAAMJAAkKeh2vAQD3AgAJAAkKeh2vAQD3AgAPAAEKYw3NWAA9AAAAAA==.Sorrel:BAAANQADCggICQAAAA==.',
Sp='Specialmove:BAAANQAECgQIBAAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgQJCgAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggJHAAAAA==.Stormstream:BAAANQADCgMIBAAAAA==.',
Su='Suelustra:BAAANQADCgIJAwABNQADCgcJFwADAAAAAA==.',
Sy='Sykotyk:BAAANQAECgYJEQAAAA==.',
Ta='Tadagain:BAAANQAECgQJBgAAAA==.Talairn:BAAANQADCgIJAgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgMIBQAAAA==.Tart:BAAANQADCgcJHQAAAA==.',
Te='Telekinesis:BAAANQAECgYIDwAAAA==.Tenara:BAAANQAECgcJEQABNQAECgMIBQADAAAAAA==.Teos:BAAANQADCgYIBgABNQAECgcJFgAKAOwKAA==.',
Th='Thalanor:BAAANQABCgYJDAAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwADAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAAANQAECgQJBgAAAA==.',
Tr='Tracther:BAAANQADCgYJDgAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgYJDwAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgYJEAAAAA==.',
Ul='Ullhr:BAAANQADCgYICwAAAA==.',
Va='Valock:BAAANQADCgcJFQAAAA==.Vanshifty:BAAANQAECgYJEwAAAA==.',
Ve='Venli:BAAANQADCgQJBAAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQADCggJHgAAAA==.',
Wa='Waffle:BAAANQAECgQIBgAAAA==.Wardaelos:BAAANQADCgUIBQAAAA==.Wargue:BAAANQAECgUJBQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQADCgcIEQADAAAAAA==.',
Wh='Whofurmoover:BAAANQADCgQJBQAAAA==.',
Wi='Winrodan:BAAANQAECgYJDwABNQAECgYIDwADAAAAAA==.Wizzard:BAAANQAECgIIAgAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQAECgQIBAABNQAECgUIDgADAAAAAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAAANQAECgYICQAAAA==.Zenthareal:BAAANQAECgYJDgAAAA==.Zenzi:BAAANQADCgUJCQAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYJCAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAADAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECoEfAAIQAAkK7B1gDwAoAwAQAAkK7B1gDwAoAwAAAA==.',
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
