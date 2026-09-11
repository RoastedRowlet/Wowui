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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Fire','Mage-Frost',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-09-08',data={Ae='Aeliena:BAAANQADCgQIBwAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAAANQAECgIIAgAAAA==.',
Am='Amal:BAAANQAECgYICwAAAA==.Amaneeda:BAAANQADCgcIEgAAAA==.Amazonia:BAAANQADCgUIDQAAAA==.',
An='Antagonis:BAAANQADCgcIDwAAAA==.',
Ar='Arashe:BAAANQADCgYIDAAAAA==.Arganos:BAAANQAECgIIAgAAAA==.Arkburn:BAAANQADCgYICgAAAA==.',
As='Ashiond:BAAANQABCgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAAANQAECgUICQAAAA==.Atsuni:BAAANQAECgMIAwAAAA==.',
Au='Aurite:BAAANQAFFAEIAQAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Az='Azrand:BAAANQADCgcIDwAAAA==.',
Ba='Baelanoth:BAAANQADCggIEgAAAA==.Balkazaar:BAAANQAECgcICwAAAA==.Bammbamm:BAAANQADCggIEgAAAA==.Banewreak:BAAANQAECgUIBQAAAA==.Banu:BAAANQADCgIIAgAAAA==.',
Be='Belanklin:BAAANQADCggIFAAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQADCgUIBQAAAA==.',
Bo='Boogie:BAAANQAECgQIBQAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.',
Br='Breakstuff:BAAANQADCgUICgAAAA==.',
Bu='Buckshot:BAAANQABCgIIAgAAAA==.Buddro:BAAANQADCgUIBwAAAA==.',
['Bú']='Búbblés:BAAANQAECgQIBAAAAA==.',
Ca='Caatia:BAAANQAECgMIBgAAAA==.Capzeil:BAAANQADCgYIFAAAAA==.Carthel:BAAANQAECgUIBQAAAA==.',
Ce='Cerrydwyn:BAAANQADCggIEgAAAA==.',
Ch='Charley:BAAANQADCgYIBwAAAA==.Chasseresse:BAAANQADCgUIDQAAAA==.Cherry:BAAANQAECgUICwAAAA==.Chiryoshi:BAAANQADCgYICQAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAAANQAECgUICwAAAA==.Cronoz:BAAANQAECgQIBgAAAA==.',
Cu='Cursess:BAAANQAECgYICwAAAA==.',
Da='Dace:BAAANQABCgQIBQAAAA==.Daliela:BAAANQAECgIIAgAAAA==.Dalya:BAAANQAECgIIAwAAAA==.Dani:BAAANQABCgEIAQABNQADCgUICAABAAAAAA==.Dayel:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.',
De='Deathratell:BAAANQABCgIIAgAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Destinÿ:BAAANQAECgEIAQAAAA==.Devourer:BAAANQADCggIEgAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgQIBAAAAA==.Dreathhammer:BAAANQAECgUIBwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dunhallow:BAAANQAECgEIAQAAAA==.',
El='Elememetal:BAAANQADCgYIDAAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAAANQAECgEIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Fo='Foldyholds:BAAANQAECgYICgAAAA==.Foulbert:BAAANQAECgIIAgAAAA==.',
Fu='Furyofdawn:BAAANQADCgYIBgAAAA==.',
['Fá']='Fálísta:BAAANQADCgUIBQABNQABCgUIBQABAAAAAA==.',
Ga='Gamblex:BAAANQADCgYIDwAAAA==.Garviel:BAAANQADCggIDgAAAA==.',
Ge='Geethatlock:BAAANQADCgMIAwAAAA==.',
Gh='Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQADCgcIEgAAAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Gr='Greensoul:BAAANQAECgEIAQAAAA==.',
Gu='Gundyr:BAAANQADCgYIBgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Halammela:BAAANQADCgYICAABNQAECgYICgABAAAAAA==.Harmen:BAAANQABCgIIAgAAAA==.',
He='Heavenlyfïre:BAAANQADCggICAAAAA==.Helleer:BAAANQADCgIIAwAAAA==.',
Hi='Hikdh:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Hikwar:BAAANQAECgMIAwAAAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAAANQADCggICAABNQAECgMIBgABAAAAAA==.',
Ju='Juglight:BAAANQADCgYIBgAAAA==.',
Ka='Karrah:BAAANQADCgcIDwAAAA==.Kaz:BAAANQAECgUICwAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.',
Kh='Khaiv:BAAANQAECgcIEAAAAA==.',
Ki='Kielann:BAAANQADCggIEgAAAA==.Kimmi:BAAANQADCgQIBwAAAA==.',
Ko='Korihor:BAAANQADCggIEgAAAA==.',
La='Lasadin:BAAANQABCgYICgAAAA==.',
Le='Lechwe:BAAANQAECgMIAwAAAA==.Lenry:BAABNQAECoEWAAMCAAkJPiFMEgAsAwACAAkJPiFMEgAsAwADAAMJ0w7WAgDVAAAAAA==.',
Li='Lichmajor:BAAANQAECgUIBwAAAA==.Lightfeet:BAAANQADCggIFQABNQAECgcIEgABAAAAAA==.',
Lo='Lostdelta:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Lostrage:BAAANQAECgQIBAAAAA==.Lovepet:BAAANQAECgcIEgAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Lunal:BAAANQAECgYICwAAAA==.',
Ly='Lyda:BAAANQADCggIEgAAAA==.',
['Lû']='Lûnitari:BAAANQADCgcIDwAAAA==.',
Ma='Magice:BAAANQADCgYIDwAAAA==.Malibubarbie:BAAANQADCggIEgAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCgQIBAAAAA==.Materesa:BAAANQAECgEIAQAAAA==.Maysty:BAAANQAECgEIAQAAAA==.',
Me='Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAAANQAECggIEwAAAA==.Meriel:BAAANQABCgIIAwAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgUIBQAAAA==.',
Mo='Moonbayne:BAAANQAECgQIBgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgQIBwAAAA==.Motomoto:BAAANQAECggICgAAAA==.',
Ms='Ms:BAAANQAECgcIDgAAAA==.',
Na='Nasta:BAAANQAECgcICwAAAA==.',
Ne='Nepharim:BAAANQAECgIIAgAAAA==.Nephlim:BAAANQAECggIEgAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQADCgUIBwAAAA==.',
Oo='Oorlian:BAAANQADCgYIDwAAAA==.',
Pa='Pantoprazole:BAAANQADCgUIAgAAAA==.Pastor:BAAANQADCgYIBwABNQADCgUIBQABAAAAAA==.Pawtyanimal:BAAANQADCggIEgAAAA==.',
Po='Pocketbible:BAAANQADCggIDgAAAA==.Pogo:BAAANQADCggIFQAAAA==.Pongmo:BAAANQAECgQIBAAAAA==.',
Py='Pyylot:BAAANQADCgMIAwAAAA==.',
Ra='Ramuel:BAAANQAECgIIAgAAAA==.Rastapopulos:BAAANQAECgMIAwAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQIBwAAAA==.',
Ri='Rikaku:BAAANQADCgYIDwAAAA==.',
Ro='Rosemery:BAAANQADCgUICAAAAA==.',
Ru='Ru:BAAANQADCggIDgAAAA==.',
['Râ']='Râpodac:BAAANQAECgUIBwAAAA==.',
Sa='Sangwin:BAAANQADCgEIAQAAAQ==.',
Sc='Schizo:BAAANQADCgcIDgABNQAECgcIDgABAAAAAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAAANQAECgEIAQAAAA==.Sephywrath:BAAANQAECgMIBgAAAA==.Serabignite:BAAANQADCgIIAgABNQAECgUICwABAAAAAA==.Seralith:BAAANQAECgUICgAAAA==.Seranight:BAAANQAECgUICwAAAA==.Seven:BAAANQADCgcIDwABNQABCgIIAgABAAAAAA==.Sevenpaws:BAAANQADCgYIDgABNQAECgUICQABAAAAAA==.',
Sh='Shadowchi:BAAANQADCgUIDQAAAA==.Shirohige:BAAANQADCgYIDwAAAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIIAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
Sp='Spybro:BAAANQADCgYIDgAAAA==.',
St='Stalkingwolf:BAAANQADCgcIDwAAAA==.',
Su='Suzuya:BAAANQADCgEIAQAAAA==.',
Sy='Sylailia:BAAANQAECgQIBQAAAA==.Synistir:BAAANQADCgIIAwAAAA==.Syrø:BAAANQADCggIDwAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQADCgYICQAAAA==.',
Tc='Tcalin:BAAANQADCgEIAQAAAA==.',
Th='Thammer:BAAANQADCggIEwAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCgYIBgAAAA==.',
Ti='Tiarcis:BAAANQAECgEIAQAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treesummoner:BAAANQAECgEIAQAAAA==.Triton:BAAANQAECgUICwAAAA==.Trizuke:BAAANQADCgEIAgAAAA==.',
Tu='Tutsee:BAAANQADCgUIBQAAAA==.',
Va='Valeyka:BAAANQADCgcICwAAAA==.Vali:BAAANQABCgQIBwAAAA==.Valle:BAAANQADCggIDwAAAA==.Vasilia:BAAANQADCggIEgAAAA==.',
Ve='Velanna:BAAANQADCgEIAQAAAA==.Veliatt:BAAANQAECgMIBAAAAA==.Vexaris:BAABNQAECoEVAAIEAAcJfxmCAgBEAgAEAAcJfxmCAgBEAgAAAA==.',
Vi='Viradi:BAAANQADCgYICgAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.Wuwindtang:BAAANQAECgMIBAAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAQAAAA==.',
Xi='Xianfei:BAAANQAECgUIBgAAAA==.',
Za='Zachxd:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Zanthe:BAAANQADCgYIBwAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.',
Zh='Zhanblood:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Zhanbrew:BAAANQAECgMIAwAAAA==.',
Zi='Zipit:BAAANQAECgUIBwAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
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
