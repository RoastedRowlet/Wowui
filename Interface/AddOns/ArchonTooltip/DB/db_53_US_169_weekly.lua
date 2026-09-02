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
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aairidari:BAAANQAECgEIAQAAAA==.',
Ab='Abruno:BAAANQAECgcICwAAAA==.Abruto:BAAANQADCgIIAQABNQAECgcICwABAAAAAA==.',
Ae='Aeown:BAAANQADCgUIBwABNQAECgIIAgABAAAAAA==.Aerdis:BAAANQADCgUIBwABNQADCgcIBwABAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAAANQAECgIIAgAAAA==.Altera:BAAANQADCgcICwAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQADCggIDAAAAA==.Androonatorz:BAAANQAECgYICgAAAA==.Anfernay:BAAANQAECgEIAQAAAA==.',
Ar='Artemisled:BAAANQADCggICAAAAA==.Arveiturace:BAAANQADCgUICQAAAA==.',
As='Ashborrn:BAAANQADCgIIAgAAAA==.Ashtar:BAAANQAECgIIAgAAAA==.',
At='Attack:BAAANQAECgEIAQAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQIBAAAAA==.Bajablast:BAAANQADCgYIBgAAAA==.Barma:BAAANQADCgYIBgAAAA==.',
Be='Beltirra:BAAANQADCgMIBgAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Bigmobility:BAAANQAECgIIAgAAAA==.Bigwill:BAAANQAECgQIBAAAAA==.',
Bl='Blargy:BAAANQAECgQIBAAAAA==.Bleach:BAAANQADCgQIBAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.',
Br='Brimara:BAAANQADCgEIAQAAAA==.',
Bu='Bucketojoy:BAAANQAECgEIAQAAAA==.',
Ca='Caliburne:BAAANQAECgIIAgAAAA==.Capz:BAAANQAFFAIIAgAAAA==.',
Ce='Cedrin:BAAANQADCgMIAwAAAA==.Ceez:BAAANQADCgQIBgAAAA==.',
Ch='Chèn:BAAANQADCgUIBQAAAA==.',
Ci='Cindrella:BAAANQAECgQIBAAAAA==.',
Cl='Clayre:BAAANQAECgUIBwAAAA==.Clow:BAAANQADCggIEAAAAA==.',
Co='Colossus:BAAANQADCgQIBAAAAA==.Coolcrush:BAAANQADCgIIAwABNQAECgMIAwABAAAAAA==.Corven:BAAANQAECgcICwAAAA==.',
Cr='Critzwar:BAAANQAECgUICQAAAA==.',
Da='Daedyxes:BAAANQADCggIDwAAAA==.Daní:BAAANQADCgUIBgABNQADCgUICAABAAAAAA==.Darkensi:BAAANQABCgQIBAAAAA==.Dasherdeez:BAAANQADCgQIBQAAAA==.Daygath:BAAANQAECgEIAQAAAA==.',
De='Deadlyiris:BAAANQAECgQIBAAAAA==.Deadshot:BAAANQADCgMIAwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Demonbulio:BAAANQADCgYICwAAAA==.Demonisthicc:BAAANQAECgIIBAAAAA==.Demonslayeer:BAAANQADCgUIBQAAAA==.Devi:BAAANQADCggICAAAAA==.',
Di='Dithehealer:BAAANQADCggIDAAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQADCgcIDQAAAA==.',
Du='Dunbroch:BAAANQAECggIDgAAAA==.',
['Dé']='Démonicblood:BAAANQAECgEIAQAAAA==.',
Ek='Ekhart:BAAANQADCgYIBgAAAA==.',
El='Elfajah:BAAANQADCgUIBAAAAA==.Eliicia:BAAANQAECgcICgAAAA==.',
Em='Emmy:BAAANQAECgQICAAAAA==.Emofineshyt:BAAANQADCgUIBQAAAA==.Emogothbabe:BAAANQAECgQIBAAAAA==.Emowrecky:BAAANQADCggIDgAAAA==.',
En='Endo:BAAANQAECgcICwAAAA==.Enjoyer:BAAANQADCggICgAAAA==.',
Er='Ereitherla:BAAANQADCgYICgAAAA==.',
Es='Espressð:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ex='Excalibear:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.',
Fe='Feironor:BAAANQADCgQIBgAAAA==.Fenrys:BAAANQADCgMIBAAAAA==.',
Fl='Flayre:BAAANQAECgEIAQAAAA==.Fleredil:BAAANQAECgIIAgAAAA==.Flingernle:BAAANQAECgIIAgAAAA==.',
Fo='Forepray:BAAANQAECgYICQAAAA==.Forger:BAAANQADCggICAAAAA==.',
Fr='Fraun:BAAANQADCggIEQAAAA==.',
Fu='Fullyprotpal:BAAANQADCgEIAQAAAA==.Furioustotem:BAAANQADCgYICgAAAA==.Future:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Go='Golgotterath:BAAANQAECgcICwAAAA==.',
Ha='Halbruck:BAAANQAECgMIBQAAAA==.Haldane:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Havochunter:BAAANQADCgQIBwAAAA==.',
He='Heihei:BAAANQADCgYICwAAAA==.Helinndealin:BAAANQAECgcICQAAAA==.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQADCgIIAgAAAA==.Hephsdh:BAAANQAECgEIAQAAAA==.Heraois:BAAANQADCgYIBgAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holywráth:BAAANQADCgMIAwAAAA==.',
Hu='Hunterdh:BAAANQADCgYIBwAAAA==.',
Il='Illidope:BAAANQAECgMIAwAAAA==.',
In='Infinitevoid:BAAANQADCgEIAQAAAA==.Inteaus:BAAANQADCggIDgAAAA==.',
Ja='Jaekir:BAAANQADCgYICgAAAA==.Jakfrost:BAAANQAECgMIAwAAAA==.Jakie:BAAANQADCgQIBAABNQADCggIEAABAAAAAA==.Jarten:BAAANQAECgUICQAAAA==.Jayaah:BAAANQADCgMIBgAAAA==.Jaylebate:BAAANQADCgYIDAAAAA==.',
Je='Jesseatamer:BAAANQAECgUICQAAAA==.',
Jo='Joxor:BAAANQABCgIIAgAAAA==.',
Js='Jstrawr:BAAANQAECgQIBAAAAA==.',
Ka='Karen:BAAANQADCgcICwAAAA==.Kastia:BAAANQADCgQIBQAAAA==.Katrynwel:BAAANQADCgUICgAAAA==.Katsumi:BAAANQADCgUIBQAAAA==.',
Ke='Keliki:BAAANQAECgQIBAAAAA==.Kettama:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Kh='Khold:BAAANQAECgQIBAAAAA==.Khrogann:BAAANQADCgMIAwAAAA==.',
Ki='Killalltoday:BAAANQADCgcIDQAAAA==.Kirkk:BAAANQADCgUICAAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAAAAA==.',
Kn='Knixx:BAAANQAECgcICgAAAA==.Knuppelus:BAAANQADCgUICAAAAA==.',
Ko='Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQADCgEIAQAAAA==.Koveras:BAAANQADCgMIAwAAAA==.Koyaanis:BAAANQADCggICAAAAA==.Koyya:BAAANQAECgMIAwAAAA==.',
Kr='Krenmonk:BAAANQAECgEIAQAAAA==.Krunchee:BAAANQADCgUICAAAAA==.',
Ku='Kufoo:BAAANQADCggIDgAAAA==.Kurao:BAAANQADCgYIBgAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAAANQAECgcICwAAAA==.',
La='Lagøless:BAAANQAECgQIBAAAAA==.',
Le='Leo:BAAANQADCgYIBgAAAA==.',
Li='Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAAANQAECgQIBAAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQADCgQIBQAAAA==.',
Ly='Lyshkä:BAAANQAECgMIAwAAAA==.Lyzzardkng:BAAANQAECgMIAwAAAA==.',
Ma='Magerthat:BAAANQADCgIIAgAAAA==.Magicaltickl:BAAANQAECgEIAQAAAA==.Magiki:BAAANQADCgQIBAAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgEIAQAAAA==.Mamadeezy:BAAANQADCgYICgAAAA==.Mando:BAAANQADCgUICAABNQADCgYICgABAAAAAA==.Manical:BAAANQADCgUICAAAAA==.Marcel:BAAANQADCgMIBgAAAA==.Mashiach:BAAANQAECgYIBwAAAA==.',
Me='Megumin:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Melikefire:BAAANQAECgQIBgAAAA==.Memecompdall:BAAANQADCgMIAwAAAA==.Merek:BAAANQADCgcIDQAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQADCgQIAwABNQAECgQIBAABAAAAAA==.Mistyd:BAAANQAECgcICwAAAA==.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQADCggIDwAAAA==.Morgause:BAAANQADCgUICAAAAA==.Morllan:BAAANQAECgIIAgAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
Na='Naanomage:BAAANQADCgQIBwAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsever:BAAANQAECgEIAQAAAA==.Nirath:BAAANQADCgcIBwAAAA==.',
Od='Odysse:BAAANQADCgYICAAAAA==.',
Ok='Okami:BAAANQADCgYICwAAAA==.',
Oo='Ooyagoddess:BAAANQABCgQIBgAAAA==.',
Or='Orryck:BAAANQADCgIIAgAAAA==.',
Pa='Pacamonk:BAAANQAECgIIAgAAAA==.Pawthetic:BAAANQAECgcICwAAAA==.',
Pe='Peelforheals:BAAANQAECgYICgAAAA==.Penguindemic:BAAANQAECgMIAwAAAA==.Pep:BAAANQADCgYIDQAAAA==.Pepperoni:BAAANQADCgYICgAAAA==.Petruccius:BAAANQAECgQIBAAAAA==.Pewpewlepew:BAAANQAECgEIAQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUIBQAAAA==.Pinksparklez:BAAANQADCgUICAAAAA==.',
Po='Poptartsz:BAAANQADCggIEQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Precht:BAAANQADCgMIAwAAAA==.Prikarea:BAAANQADCgUIBwAAAA==.Prumper:BAAANQAECgEIAQAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQADCggIDgAAAA==.',
Ra='Rabid:BAAANQADCgMIAwAAAA==.Raghallov:BAAANQADCgQIBgAAAA==.Rampa:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.',
Re='Regena:BAAANQAECgIIAgAAAA==.Remorse:BAAANQAECgcICwAAAA==.Rendwick:BAAANQADCgQIBAAAAA==.',
Ri='Rim:BAAANQADCggIDwAAAA==.',
Ro='Ronard:BAAANQAECgEIAQAAAA==.Ronfar:BAAANQAECgcICwAAAA==.',
Ru='Ruttisðir:BAAANQADCgcIDAAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgIIAgAAAA==.Ryujin:BAAANQADCgYIBgAAAA==.Ryù:BAAANQADCggICAAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCgQIBAAAAA==.',
Sc='Scarlypop:BAAANQADCggICAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQADCgIIAgAAAA==.Seswatha:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Sh='Shanghaied:BAAANQADCgYIBgAAAA==.Shmongus:BAAANQADCgIIAgABNQADCggICgABAAAAAA==.Shortandold:BAAANQADCggICwAAAA==.Shådowfire:BAAANQADCgUICQAAAA==.Shìft:BAAANQAECgIIAgAAAA==.',
Si='Sintram:BAAANQABCgIIAgAAAA==.',
Sl='Slighted:BAAANQADCgUICQABNQADCgYICgABAAAAAA==.Slimydruid:BAAANQADCgQIBAAAAA==.Slow:BAAANQAECgYIDwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
So='Sockoh:BAAANQADCgYIBgAAAA==.Solera:BAEANQABCgIIAgAAAA==.Sonicberger:BAAANQADCgQICAABNQADCggIDgABAAAAAA==.Soniko:BAAANQADCgYICgAAAA==.Sonícberger:BAAANQADCggIDgAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQADCgIIAgAAAA==.Stonehenge:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Stonepalm:BAAANQADCgQIBAAAAA==.Stratan:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Strawk:BAAANQADCgUICAAAAA==.',
Su='Suffer:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Surf:BAAANQADCggIEAAAAA==.',
Sw='Swankydranky:BAAANQAECgcICwAAAA==.',
Sy='Syesc:BAAANQABCgQIBAAAAA==.',
Ta='Tabbz:BAAANQAECgEIAQAAAA==.Tallael:BAAANQAECgMIAgAAAA==.Tallyhochick:BAAANQAECgIIAgAAAA==.Taman:BAAANQAECgUIBwAAAA==.',
Th='Thebestname:BAAANQADCgYICQAAAA==.Thebigonion:BAAANQADCgUICAAAAA==.Theexile:BAAANQAECgIIAgAAAA==.',
Ti='Tinydeath:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAAANQAECgIIAgAAAA==.',
Tm='Tmakrist:BAAANQABCgEIAgAAAA==.',
To='Toko:BAAANQAECgYICQAAAA==.',
Tr='Treeheals:BAAANQADCggICAAAAA==.Truthsx:BAAANQADCggIDAAAAA==.Truthy:BAAANQADCgYICAABNQADCggIDAABAAAAAA==.',
Ty='Tyg:BAAANQADCgcIBwAAAA==.Tylaatape:BAAANQADCgYICAAAAA==.Tyraell:BAAANQADCgcIBwAAAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.',
Us='Usgasdanelv:BAAANQADCggICAAAAA==.',
Uz='Uzala:BAAANQADCgQIBQAAAA==.',
Va='Vazro:BAAANQAECgEIAQAAAA==.',
Ve='Venthyl:BAAANQAECgUIBQAAAA==.',
We='Wellby:BAAANQADCgIIAgAAAA==.Westerin:BAAANQADCgMIAwAAAA==.',
Wi='Windfury:BAAANQADCgcICgABNQAECgYIDwABAAAAAA==.Windigo:BAAANQADCggIDQAAAA==.',
Xa='Xaala:BAAANQAECgEIAQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQADCggIDgABNQADCggIEAABAAAAAA==.',
Ye='Yespaladin:BAAANQAECgUIBwAAAA==.',
Yo='Yogí:BAAANQAECgYICQAAAA==.Yozomoto:BAAANQAECgYIBgAAAA==.',
Za='Zalandria:BAAANQADCgUICgAAAA==.',
Ze='Zeltemis:BAAANQADCggIDgAAAA==.',
Zi='Zipsion:BAAANQAECgIIAgAAAA==.Zithen:BAAANQADCgEIAQAAAA==.Zivver:BAAANQAECgEIAQAAAA==.Zizka:BAAANQADCgQIBAAAAA==.',
Zo='Zolandir:BAAANQADCgQIBwAAAA==.',
['Üt']='Üther:BAAANQAECgIIAgAAAA==.',
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
