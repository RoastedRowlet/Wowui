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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Survival','DeathKnight-Blood','Priest-Holy','Priest-Discipline','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Mage-Arcane','Hunter-Marksmanship','Druid-Restoration','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abdalhazred:BAABNQAECoEmAAMBAAkKNSHkAABRAwABAAkKNSHkAABRAwACAAIKoRgkSACSAAAAAA==.Abilus:BAAANQAECgMICQAAAA==.Abolis:BAAANQAECgQICAAAAA==.',
Ae='Aelianna:BAAANQADCggIDwAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgUIDAAAAA==.',
An='Anarran:BAAANQADCgUIBwAAAA==.Animalfury:BAAANQAECgUICwAAAA==.Anthestria:BAAANQADCgcIDwAAAA==.',
Aq='Aqurala:BAAANQAECgYIEQAAAA==.',
Ar='Arasham:BAAANQADCgQIBAABNQAECggIFwADACkUAA==.Aravenn:BAABNQAECoEXAAIDAAgKKRQLTwAzAgADAAgKKRQLTwAzAgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgMIAwABNQAECgkJJQAEADwgAA==.Artison:BAAANQADCgYIBgABNQAECgUICwAFAAAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAFAAAAAA==.Athenos:BAAANQADCgQIBgAAAA==.',
Au='Aurum:BAAANQAECgIIAgAAAA==.',
Av='Avatartele:BAAANQAECgcICwAAAA==.Avatartouka:BAABNQAECoEhAAMEAAgKDCO1JACZAgAEAAcKiyK1JACZAgAGAAUKTBrkdgBnAQAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECgYICQAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAABNQAECoEiAAIHAAkK1BzWEQCMAgAHAAkK1BzWEQCMAgAAAA==.',
['Aí']='Aísling:BAAANQADCggIJgAAAA==.',
Ba='Bagador:BAAANQAECgcIDQAAAA==.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Beautifulluv:BAAANQAECgYICwAAAA==.Bekabeka:BAABNQAECoEpAAMIAAkKPR7cEgAUAwAIAAkKPR7cEgAUAwAJAAEKiQ05QgE6AAAAAA==.Bekabekabeka:BAAANQABCggJAQABNQAECgkJKQAIAD0eAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAAANQAECgYIEwAAAA==.',
Bo='Bonski:BAAANQADCgMIAwAAAA==.Boosterman:BAAANQAECgQICAAAAA==.',
Br='Brakkar:BAAANQADCggIFgAAAA==.Braxxis:BAAANQAECgQIBAABNQAFFAQIBwAKADwQAA==.Breadstick:BAAANQAECgIIAgAAAA==.Bress:BAAANQADCgYIBgABNQAECgYIEQAFAAAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQADCggIEQAAAA==.Bryndel:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggJCAAAAA==.Canoodles:BAAANQAECgYICQAAAA==.',
Ce='Celaian:BAAANQAECgQICAABNQAECgQICAAFAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECgMIAwAFAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAAANQAECgcIEgAAAA==.Chidõri:BAAANQAECggIEgAAAA==.Chunni:BAAANQAECgYICwAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.',
Cr='Crayonman:BAAANQAECgYJEAAAAA==.Cronus:BAAANQAECgIIAwAAAA==.Cruelkitty:BAAANQAECgQIBAAAAA==.',
Da='Dahlynar:BAAANQAECgQJBAAAAA==.Dalov:BAAANQAECgYIDgAAAA==.Dankley:BAAANQADCggIJQAAAA==.Danystorm:BAAANQADCgcIBwABNQAECgkJJQAEADwgAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQADCgIIBgAFAAAAAA==.',
De='Deaddude:BAABNQAECoEhAAILAAgKshw7HgCKAgALAAgKshw7HgCKAgAAAA==.Deathboi:BAAANQAECgQICwAAAA==.Deathcuddles:BAAANQAECgQICAAAAA==.Dedcow:BAAANQADCgUIBQAAAA==.',
Di='Diana:BAAANQAECgYIEQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYIFwAAAA==.Dragonwarrio:BAABNQAECoEeAAIHAAkKCx5ADQDTAgAHAAkKCx5ADQDTAgAAAA==.Draltina:BAAANQAECgYICQAAAA==.Drazira:BAAANQADCgcJDgAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgcIDAAFAAAAAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUICAAAAA==.Dubaltrok:BAAANQADCgQIBwAAAA==.Dudde:BAAANQAECgQIBAABNQAECggIIQALALIcAA==.Dulapin:BAAANQADCgIJAgAAAA==.Duskfu:BAAANQAECgUIDAAAAA==.Dustylock:BAAANQAECgQIDQAAAA==.',
Ea='Earthele:BAAANQAECgQIBAAAAA==.',
El='Elfowl:BAAANQADCgYIBwABNQAECgYIEwAFAAAAAA==.',
Em='Emanonsahi:BAAANQABCgQIBAAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIAwAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAFAAAAAA==.Eryi:BAAANQADCggIJwAAAA==.',
Ev='Eviserator:BAAANQADCgMIBAAAAA==.',
Fa='Fable:BAAANQAECggIBwAAAA==.Faegen:BAAANQADCgMJAwAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgYJEAAFAAAAAA==.Faze:BAAANQAECgMJBQAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUIBQAAAA==.',
Fe='Feydoria:BAAANQADCgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgEIAQAAAA==.',
Fr='Frontman:BAAANQAECgUICQAAAA==.Frostscythe:BAAANQABCgQIAgAAAA==.',
Fu='Funkycolors:BAAANQADCgYIBgABNQAECgQIDQAFAAAAAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAFAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQADCggIJgAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQADCgcIDAAAAA==.',
Gl='Gloçk:BAAANQAECgcIDwAAAA==.',
Go='Goofy:BAAANQAECgYIBgAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAAANQAECgQIBAAAAA==.Grimvaka:BAAANQABCggICwAAAA==.',
Gu='Gunduin:BAABNQAECoEZAAIDAAYK6RbueQC8AQADAAYK6RbueQC8AQAAAA==.',
Gy='Gyda:BAABNQAECoElAAMMAAkKsBO+OwAzAgAMAAkKsBO+OwAzAgANAAIKCgwCGQBqAAAAAA==.Gyuyuki:BAABNQAECoEZAAIGAAcKswvUbACFAQAGAAcKswvUbACFAQAAAA==.',
Ha='Hakeo:BAEANQAECgcIEgAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQAECgEIAQAAAA==.',
Hi='Hikomosil:BAAANQAECgcICgAAAA==.',
Ho='Holdmybeerz:BAAANQADCgQIBAAAAA==.Homiekissér:BAAANQAECgYICAAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAQAAAA==.',
Im='Imakittycat:BAAANQAECgUIEAAAAA==.Impared:BAAANQAECgYIBgABNQAECggIBwAFAAAAAA==.',
Iv='Ivey:BAAANQADCggICwAAAA==.',
Ja='Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAAANQAECgUICwAAAA==.',
Jo='Josephyn:BAAANQAECgUICQABNQAECgkJJQAEADwgAA==.',
Ju='Juggernåut:BAAANQADCgMJAwAAAA==.',
Ka='Kaale:BAAANQABCgUIBwABNQAECgMICAAFAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECoEfAAIIAAgK0R0vIAC+AgAIAAgK0R0vIAC+AgAAAA==.Kalypsso:BAAANQADCgMIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgEIAQAAAA==.Katharsis:BAABNQAECoEZAAIJAAkKqBK0XAAsAgAJAAkKqBK0XAAsAgAAAA==.',
Ke='Keit:BAEANQADCgUIBQABNQAECgkJJAAOAGYiAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECoEbAAIIAAgK3BxVHADVAgAIAAgK3BxVHADVAgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIJAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECggIFwADACkUAA==.',
Kr='Kronar:BAAANQADCgYICQAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQADCggIEAAAAA==.Kynsong:BAABNQAECoEXAAMMAAcKORBlYACbAQAMAAcKORBlYACbAQANAAEKJAF2KQAHAAAAAA==.Kysia:BAAANQAECgUICQABNQAECgkJHQAJAHMdAA==.',
['Kî']='Kîrah:BAAANQAECgQIBAAAAA==.',
Le='Lerazal:BAAANQAECgQJCAAAAA==.Lexanteus:BAAANQADCgUJBQAAAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQADCgYIEAAAAA==.Lildh:BAAANQAECgYICgAAAA==.',
Lo='Lorastyrell:BAAANQABCgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgYIEQAFAAAAAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECoEgAAIMAAkKWRbeKwB6AgAMAAkKWRbeKwB6AgABNQAECgkJJQAEADwgAA==.Luu:BAAANQAECgEIAQABNQAECgQIBAAFAAAAAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Magelock:BAAANQAECgIIAgABNQAECgQIBwAFAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAFAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgYIGQADAOkWAA==.Maliboo:BAAANQAECgYIEAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECoEYAAIPAAgKLxshQQCNAgAPAAgKLxshQQCNAgAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgQJBgAAAA==.Medívh:BAAANQAECgIJAgAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAAANQAECgUIDgAAAA==.Merkshamalot:BAAANQADCgYIBgABNQAECgUIDgAFAAAAAA==.Merkur:BAAANQADCggIGwABNQAECgUIDgAFAAAAAA==.Merkurry:BAAANQADCgQIBAABNQAECgUIDgAFAAAAAA==.',
Mo='Modifiedmix:BAAANQADCgUICwAAAA==.Monatazumaa:BAAANQADCgcIBwAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECgkJIwAPABojAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECoEqAAMIAAgKyRL+RgAIAgAIAAgKyRL+RgAIAgAJAAQKhgoI+wC1AAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgQIBQABNQAECgcIDwAFAAAAAA==.',
Ne='Neptune:BAABNQAECoElAAIEAAkKPCB5FAD8AgAEAAkKPCB5FAD8AgAAAA==.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAAANQAECgYIEAAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nightwingqt:BAAANQAECgIIAgAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.',
['Nè']='Nèo:BAAANQADCgUIBgAAAA==.',
Ok='Oktobra:BAAANQAECgQICAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECoEWAAMQAAcKChsVJgAHAgAQAAcKChsVJgAHAgARAAIKbAs2nQBZAAAAAA==.Orioan:BAAANQAECgYIEQAAAA==.',
Os='Osun:BAAANQADCgYJDQAAAA==.Osÿrus:BAAANQADCgQIBAAAAA==.',
Pa='Paddy:BAAANQADCggIJgAAAA==.Palantyr:BAABNQAECoEyAAIGAAkKwxLFMwBlAgAGAAkKwxLFMwBlAgAAAA==.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAAANQAECgcIDwAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggICAAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAAANQAECgUIDAAAAA==.Raddish:BAAANQAECgQICAAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECgYIEwAFAAAAAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQICQAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Restofolyfe:BAAANQAECgEJAQAAAA==.Revenge:BAABNQAECoEbAAIJAAgKEyP9IQALAwAJAAgKEyP9IQALAwAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECggIGQALAOYKAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQADCggICAABNQAECggIGgAGAHwPAA==.Rika:BAAANQADCggIFQAAAA==.',
Ro='Robolich:BAAANQAECgYIBgAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAFAAAAAA==.Roshwyn:BAAANQAECgIIBAAAAA==.Rottedmeat:BAAANQAECgcICwAAAA==.',
Ru='Rubmytotems:BAAANQAECgUICgAAAA==.Ruckus:BAABNQAECoEbAAIJAAgKwBctVQBEAgAJAAgKwBctVQBEAgAAAA==.',
Rx='Rxmblock:BAAANQADCgcIFgAAAA==.',
Sa='Saelin:BAAANQADCgcIBwABNQAECgMICAAFAAAAAA==.Sareenastar:BAABNQAECoEXAAIMAAcKICXrFwDpAgAMAAcKICXrFwDpAgAAAA==.',
Se='Seafood:BAAANQAECgYIBgAAAA==.Sennara:BAAANQAECgQIBAAAAA==.Serenitynow:BAAANQADCgIIAgAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgIIAQAAAA==.Shamrox:BAAANQAECgEJAQAAAA==.Sharar:BAAANQAECgUJBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Shieldknight:BAAANQADCgQIAgAAAA==.Shiftystrike:BAAANQAECgQIBQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shrike:BAAANQADCgIIAgABNQAFFAYIEAASAM8RAA==.',
Si='Silentwindy:BAAANQADCgYJCQAAAA==.Silmarkthree:BAABNQAECoEbAAITAAcKZRKgrwDYAQATAAcKZRKgrwDYAQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECoEZAAILAAgK5go9UgBmAQALAAgK5go9UgBmAQAAAA==.',
Sl='Slipknoth:BAACNQAFFIELAAMSAAUKmRtaBgBhAQASAAQKUBpaBgBhAQAMAAEKJwufJABRAAA1AAQKgSQABBIACQodIt4HAD4DABIACQodIt4HAD4DAAwAAwoTC16kALMAAA0AAQrQGX0cAE4AAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFIEHAAIKAAQKPBB9AABjAQAKAAQKPBB9AABjAQA1AAQKgSMAAwoACQqvHioCAPgCAAoACQqvHioCAPgCABQAAQpjDWJqADgAAAAA.Sorrel:BAAANQADCggICQAAAA==.',
Sp='Specialmove:BAAANQAECgQIBAAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgUIDQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMIBAAAAA==.',
Su='Suelustra:BAAANQAECgUIBAAAAA==.',
Sy='Sykotyk:BAABNQAECoEbAAIEAAgKEho/NABKAgAEAAgKEho/NABKAgAAAA==.',
Ta='Tadagain:BAAANQAECgQICAAAAA==.Talairn:BAAANQADCgIIAgAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgMICAAAAA==.Tart:BAAANQADCgcJHQAAAA==.',
Te='Telekinesis:BAAANQAECgYIDwAAAA==.Tenara:BAABNQAECoEWAAMEAAgKsBkfNQBGAgAEAAgKsBkfNQBGAgAGAAMKRAuAxwCgAAABNQAECgMICAAFAAAAAA==.Teos:BAAANQADCgYIBgABNQAECggIGQALAOYKAA==.',
Th='Thalanor:BAAANQABCgYIEAAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwAFAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAAANQAECgYIDAAAAA==.',
Ti='Tirra:BAAANQADCggICAAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgYJDwAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgYJEAAAAA==.',
Ul='Ulfrir:BAAANQADCgYIBgAAAA==.Ullhr:BAAANQADCgYICwAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
Va='Valock:BAAANQADCgcJFQAAAA==.Vanshifty:BAABNQAECoEcAAIVAAgKnRr9FABXAgAVAAgKnRr9FABXAgAAAA==.',
Ve='Venli:BAAANQADCgQJBAAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQADCggIJgAAAA==.',
Wa='Waffle:BAAANQAECgQIBwAAAA==.Wardaelos:BAAANQADCgUIBQAAAA==.Wargue:BAAANQAECgUJBQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQADCgcIEQAFAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgIIAwAAAA==.',
Wi='Winrodan:BAAANQAECgcIEQABNQAECgYIEQAFAAAAAA==.Wizzard:BAAANQAECgMIAwAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQAECgQICAABNQAECgcIFwAMADkQAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAAANQAECgYIDwAAAA==.Zenthareal:BAABNQAECoEUAAIWAAYKQRXfLQCRAQAWAAYKQRXfLQCRAQAAAA==.Zenzi:BAAANQADCgYIDwAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYJCAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAFAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECoEmAAIDAAkK3h+8DgBHAwADAAkK3h+8DgBHAwAAAA==.',
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
