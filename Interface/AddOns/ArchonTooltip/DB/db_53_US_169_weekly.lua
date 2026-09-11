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

local lookup = {'Unknown-Unknown','Warrior-Arms','Hunter-Marksmanship','Mage-Arcane',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aairidari:BAAANQAECgQIBQAAAA==.',
Ab='Abruna:BAAANQADCggICAABNQAECggIEwABAAAAAA==.Abruno:BAAANQAECggIEwAAAA==.Abruto:BAAANQADCgIIAQABNQAECggIEwABAAAAAA==.',
Ae='Aeown:BAAANQADCgYIDQABNQAECgUIBwABAAAAAA==.Aerdis:BAAANQADCgYIDQABNQAECgIIAgABAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAAANQAECgQIBgAAAA==.Altera:BAAANQAECgEIAQAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgQIBAAAAA==.Androonatorz:BAAANQAECggIEgAAAA==.Anfernay:BAAANQAECgMIBAAAAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQADCggICAABNQAECggIEwABAAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Artemisled:BAAANQAECgQICAAAAA==.Arveiturace:BAAANQADCgYIDwAAAA==.',
As='Ashborrn:BAAANQADCgIIAgAAAA==.Ashtar:BAAANQAECgQIBgAAAA==.',
At='Attack:BAAANQAECgEIAgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQADCggIDgAAAA==.',
Be='Beltirra:BAAANQADCgYIDAAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Bigmobility:BAAANQAECgUIBwAAAA==.Bigwill:BAAANQAECgUICQAAAA==.',
Bl='Blargy:BAAANQAECgUICQAAAA==.Bleach:BAAANQADCgQIBAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.',
Br='Brimara:BAAANQAECgQIBAAAAA==.',
Bu='Bucketojoy:BAAANQAECgIIAwAAAA==.',
Ca='Caliburne:BAAANQAECgUIBwAAAA==.Capz:BAABNQAFFIEHAAICAAUJlhMTAgC6AQACAAUJlhMTAgC6AQAAAA==.',
Ce='Cedrin:BAAANQADCgMIAwAAAA==.Ceez:BAAANQADCgUICwAAAA==.',
Ch='Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgIIAgAAAA==.',
Ci='Cindrella:BAAANQAECgUICQAAAA==.',
Cl='Clayre:BAAANQAECgYIDgAAAA==.Clow:BAAANQAECgIIAgAAAA==.',
Co='Colossus:BAAANQADCgQIBAAAAA==.Coolcrush:BAAANQADCgIIAwABNQAECgMIBgABAAAAAA==.Corven:BAAANQAECggIEwAAAA==.',
Cr='Critzwar:BAAANQAECgcIEAAAAA==.Crönus:BAAANQADCgYIBwAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAAANQAECgEIAQAAAA==.Daní:BAAANQADCgUIBgABNQADCgUICAABAAAAAA==.Darkensi:BAAANQABCgYIBwAAAA==.Dasherdeez:BAAANQADCgQIBQAAAA==.Daygath:BAAANQAECgEIAQAAAA==.',
De='Deadlyiris:BAAANQAECgUICQAAAA==.Deadshot:BAAANQADCgMIAwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Demonbulio:BAAANQADCgcIDgAAAA==.Demonisthicc:BAAANQAECgUICQAAAA==.Demonslayeer:BAAANQADCgUIBQAAAA==.Devi:BAAANQAECgEIAQAAAA==.',
Di='Dithehealer:BAAANQAECgIIAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggICAAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQADCggIFQAAAA==.',
Du='Duhmptruhk:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Dunbroch:BAABNQAECoEZAAIDAAkJKxdqCgC7AgADAAkJKxdqCgC7AgAAAA==.',
['Dé']='Démonicblood:BAAANQAECgcICQAAAA==.',
Eg='Eggplantgodx:BAAANQAECgUIBQAAAA==.',
Ek='Ekhart:BAAANQADCggIEgAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAAANQAECggIEgAAAA==.',
Em='Emmy:BAAANQAECgQIDAAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAAANQAECgYICQAAAA==.Emowrecky:BAAANQAECgQIBAAAAA==.',
En='Endo:BAAANQAECggIEwAAAA==.Endorush:BAAANQADCgYIBgABNQAECggIEwABAAAAAA==.Eneldenes:BAAANQAECgEIAQAAAA==.Enjoyer:BAAANQAECgMIAwAAAA==.',
Er='Ereitherla:BAAANQADCggIEgAAAA==.',
Es='Espressð:BAAANQADCggIDgABNQAECgYICQABAAAAAA==.',
Ex='Excalibear:BAAANQAECgMIAwABNQAFFAIIAgABAAAAAA==.',
Fe='Feironor:BAAANQADCgQIBgAAAA==.Fenrys:BAAANQADCgYICgAAAA==.',
Fl='Flayre:BAAANQAECgQIBQAAAA==.Fleredil:BAAANQAECgUIBwAAAA==.Flingernle:BAAANQAECgUIBwAAAA==.',
Fo='Forepray:BAAANQAECggIEQAAAA==.Forger:BAAANQAECgQIBAAAAA==.Forsakey:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Fr='Fraun:BAAANQADCggIEQAAAA==.',
Fu='Fullyprotpal:BAAANQADCgcICAAAAA==.Furioustotem:BAAANQADCggIEgAAAA==.Future:BAAANQADCgQIBAABNQAECgkJFwAEALofAA==.',
Ga='Galten:BAAANQABCgQIBAAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.',
Gh='Ghettox:BAAANQADCgIIAgAAAA==.Ghostw:BAAANQAECgEIAQAAAA==.',
Go='Golgotterath:BAAANQAFFAIIAgAAAA==.',
Ha='Halbruck:BAAANQAECgYICwAAAA==.Haldane:BAAANQAECgUICQABNQAECgUICQABAAAAAA==.Havochunter:BAAANQADCgYICwAAAA==.',
He='Heidegger:BAAANQADCgQIBAAAAA==.Heihei:BAAANQADCgYICwAAAA==.Helinndealin:BAAANQAECggIEQAAAA==.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQAECgEIAQAAAA==.Hephsdh:BAAANQAECgEIAgAAAA==.Heraois:BAAANQADCggIDgAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holywráth:BAAANQADCgQIBgAAAA==.',
Hu='Hunterdh:BAAANQADCggIDwAAAA==.',
Il='Illidope:BAAANQAECgMIBQAAAA==.',
In='Infinitevoid:BAAANQADCgYIBwAAAA==.Inteaus:BAAANQADCggIDgAAAA==.',
Ja='Jaekir:BAAANQAECgEIAQAAAA==.Jakfrost:BAAANQAECgUICAAAAA==.Jakie:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Jarten:BAAANQAECgcIEAAAAA==.Jayaah:BAAANQADCgYIDAAAAA==.Jaylebate:BAAANQADCggIFAAAAA==.',
Je='Jesseatamer:BAAANQAECgcIEAAAAA==.',
Jo='Jox:BAAANQABCgEIAQAAAA==.Joxor:BAAANQABCgMIAwAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Jstrawr:BAAANQAECgYICgAAAA==.',
Ka='Karen:BAAANQADCggIEgAAAA==.Kastia:BAAANQADCgUICQAAAA==.Katrynwel:BAAANQADCgUICgAAAA==.Katsumi:BAAANQADCgYICwAAAA==.',
Ke='Keliki:BAAANQAECgUICQAAAA==.Kettama:BAAANQADCgYICAABNQAECgYICQABAAAAAA==.',
Kh='Khold:BAAANQAECgQIBgAAAA==.Khrogann:BAAANQAECgMIAwAAAA==.',
Ki='Killalltoday:BAAANQAECgEIAQAAAA==.Kirkk:BAAANQADCgUIDQAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAAAAA==.',
Kn='Knixx:BAAANQAECggIEgAAAA==.Knuppelus:BAAANQADCgYICQAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAAANQAECgQIBwAAAA==.',
Kr='Krenmonk:BAAANQAECgEIAQAAAA==.Krunchee:BAAANQADCgUICAAAAA==.',
Ku='Kufoo:BAAANQAECgEIAQAAAA==.Kurao:BAAANQAECgEIAQAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAAANQAFFAEIAQAAAA==.',
La='Lagøless:BAAANQAECgUICAAAAA==.',
Le='Leo:BAAANQADCgYIBgAAAA==.',
Li='Likestoflash:BAEANQADCgYIBgABNQAECgYICAABAAAAAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAAANQAECgQICAAAAA==.Lohmi:BAAANQAECgIIAgAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQADCgUICQAAAA==.',
Ly='Lyshkä:BAAANQAECgQIBwAAAA==.Lyzzardkng:BAAANQAECgUICAAAAA==.',
Ma='Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgIIAgAAAA==.Magicaltickl:BAAANQAECgIIAwAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgEIAQAAAA==.Mamadeezy:BAAANQADCgYICgAAAA==.Mando:BAAANQADCgcIDwABNQADCggIEgABAAAAAA==.Manical:BAAANQADCgUIDQAAAA==.Marcel:BAAANQADCgYIDAAAAA==.Mashiach:BAAANQAECggIDwAAAA==.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQADCgYIBwABNQAECgUIBwABAAAAAA==.Melikefire:BAAANQAECgQICgAAAA==.Memecompdall:BAAANQADCgMIAwAAAA==.Merek:BAAANQAECgEIAQAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQADCgQIAwABNQAECgUICQABAAAAAA==.Mistyd:BAAANQAFFAEIAQAAAA==.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQADCggIDwAAAA==.Morgause:BAAANQADCgcIDwAAAA==.Morllan:BAAANQAECgMIAwAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQADCgcIBwAAAA==.',
Na='Naanomage:BAAANQADCgYICwAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsever:BAAANQAECgYIBwAAAA==.Nirath:BAAANQAECgEIAQAAAA==.',
No='Noiire:BAAANQADCgUIBQABNQAECggIEgABAAAAAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAAANQAECgIIAgAAAA==.',
Ok='Okami:BAAANQADCgcIEgAAAA==.',
Oo='Ooyagoddess:BAAANQABCgQIBgAAAA==.',
Or='Orryck:BAAANQADCgQIBQAAAA==.',
Pa='Pacamonk:BAAANQAECgQIBgAAAA==.Papatiny:BAAANQADCgIIAgAAAA==.Pawsa:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Pawthetic:BAAANQAECggIEwAAAA==.',
Pe='Peelforheals:BAAANQAECggIEgAAAA==.Penguindemic:BAAANQAECgMIBgAAAA==.Pep:BAAANQADCggIHQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Petruccius:BAAANQAECgcIDAAAAA==.Pewpewlepew:BAAANQAECgMIAwAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAAAAA==.',
Po='Poptartsz:BAAANQAECgIIAgAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Precht:BAAANQADCgYICQAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prumper:BAAANQAECgQIBAAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgIIAgAAAA==.',
Ra='Rabid:BAAANQADCgMIAwAAAA==.Raghallov:BAAANQAECgEIAgAAAA==.Rampa:BAAANQADCgYIEQABNQAECgYICQABAAAAAA==.',
Re='Regena:BAAANQAECgUIBwAAAA==.Remorse:BAAANQAECggIEwAAAA==.Rendwick:BAAANQADCgYICQAAAA==.',
Ri='Rim:BAAANQAECgMIAwAAAA==.',
Ro='Ronard:BAAANQAECgcICAAAAA==.Ronfar:BAAANQAECgcIEgAAAA==.',
Ru='Rustyglass:BAAANQABCgQIBAAAAA==.Ruttisðir:BAAANQAECgEIAQAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgIIAgAAAA==.Ryujin:BAAANQAECgIIAgAAAA==.Ryù:BAAANQADCggIEAAAAA==.',
Sa='Saladman:BAAANQADCgQIBAAAAA==.Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCggIDAAAAA==.',
Sc='Scarlypop:BAAANQAECgQIBwAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQADCgIIAgAAAA==.Seswatha:BAAANQADCgYIBgABNQAFFAIIAgABAAAAAA==.',
Sh='Shamandroo:BAAANQADCggICAABNQAECggIEgABAAAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Shortandold:BAAANQAECgIIAgAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAAANQAECgQIBgAAAA==.',
Si='Sintram:BAAANQABCgIIAgAAAA==.',
Sl='Slighted:BAAANQADCgYIDwABNQAECgIIAgABAAAAAA==.Slimydruid:BAAANQADCgQIBAAAAA==.Slow:BAABNQAECoEXAAIEAAkJuh+hFwAKAwAEAAkJuh+hFwAKAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgYICQABAAAAAA==.',
So='Sockoh:BAAANQAECgQIBAAAAA==.Solera:BAEANQABCgQIBgAAAA==.Sonicberger:BAAANQADCgQICAABNQADCggIFgABAAAAAA==.Soniko:BAAANQAECgIIAgAAAA==.Sonícberger:BAAANQADCggIFgAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQADCgIIAgAAAA==.Stealth:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Stonehenge:BAAANQAECgMIBAABNQAECgUICQABAAAAAA==.Stonepalm:BAAANQADCgQIBAAAAA==.Stratan:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Strawk:BAAANQADCgUICAAAAA==.',
Su='Suffer:BAAANQADCgEIAQABNQAECgkJFwAEALofAA==.Supercat:BAAANQADCgEIAQAAAA==.Surf:BAAANQAECgIIAgAAAA==.',
Sw='Swankydranky:BAAANQAECggIEwAAAA==.Swankypally:BAAANQADCggICAABNQAECggIEwABAAAAAA==.',
Sy='Syesc:BAAANQABCgQIBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
Ta='Tabbz:BAAANQAECgQIBQAAAA==.Tallael:BAAANQAECgQIBgAAAA==.Tallyhochick:BAAANQAECgQIBgAAAA==.Taman:BAAANQAECgcIDQAAAA==.Taylerswift:BAAANQADCgEIAQAAAA==.',
Th='Thebestname:BAAANQAECgIIAgAAAA==.Thebigonion:BAAANQADCgUIDQAAAA==.Theexile:BAAANQAECgUIBwAAAA==.',
Ti='Tinydeath:BAAANQAECgUIBwABNQAECgYICQABAAAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAAANQAECgYICQAAAA==.',
Tm='Tmakrist:BAAANQADCgEIAQAAAA==.',
To='Toko:BAAANQAFFAEIAQAAAA==.',
Tr='Trailblazah:BAAANQAECgIIAgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Truths:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Truthsx:BAAANQAECgEIAQAAAA==.Truthy:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.',
Ty='Tyg:BAAANQADCgcIBwAAAA==.Tylaatape:BAAANQAECgQIBgAAAA==.Tyraell:BAAANQAECgMIAwAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Us='Usgasdanelv:BAAANQAECgEIAQAAAA==.',
Uz='Uzala:BAAANQADCgYICwAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAAANQAECgQIBQAAAA==.',
Ve='Venthyl:BAAANQAECggIDQAAAA==.',
We='Wellby:BAAANQADCgQICQAAAA==.Westerin:BAAANQADCgMIAwAAAA==.',
Wi='Wimateeka:BAAANQAECgMIAwAAAA==.Windfury:BAAANQAECgQIBgABNQAECgkJFwAEALofAA==.Windigo:BAAANQAECgIIAgAAAA==.',
Xa='Xaala:BAAANQAECgEIAQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Ye='Yespaladin:BAAANQAECgYIDQAAAA==.',
Yo='Yogí:BAAANQAECggIEQAAAA==.Yozomoto:BAAANQAECgcIDQAAAA==.',
Za='Zalandria:BAAANQADCggIEgAAAA==.',
Ze='Zeltemis:BAAANQAECgMIAwAAAA==.',
Zi='Zipsion:BAAANQAECgQIBgAAAA==.Zithen:BAAANQADCgEIAQAAAA==.Zivver:BAAANQAECgQIBQAAAA==.Zizka:BAAANQAECgIIAgAAAA==.',
Zo='Zolandir:BAAANQADCgYICQAAAA==.',
['Üt']='Üther:BAAANQAECgUIBwAAAA==.',
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
