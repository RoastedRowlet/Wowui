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

local lookup = {'Unknown-Unknown','Shaman-Enhancement','DeathKnight-Blood',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAAANQAECgQIBAAAAA==.',
Ab='Abracastabya:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAAANQAECggIEAAAAA==.Aeturnas:BAAANQAECgQICAAAAA==.',
Ai='Aire:BAAANQAECgEIAQAAAA==.',
Al='Alanima:BAAANQADCgYIBwAAAA==.Alauradona:BAAANQADCgMIBAAAAA==.Aliana:BAAANQAECgIIAgAAAA==.Allesta:BAAANQADCgIIAwAAAA==.Allypally:BAAANQADCgcIBwAAAA==.Alphamage:BAAANQADCgYIBgAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAAANQAECgQIBAAAAA==.',
Ar='Arcstream:BAAANQAECgEIAQAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQADCgcIEgAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECgEIAQAAAA==.Asterica:BAAANQAECgUICQAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAAANQAECgEIAQAAAA==.',
Ay='Ayano:BAAANQAECgUICgAAAA==.Ayulur:BAAANQAECgEIAQAAAA==.',
Az='Azraél:BAAANQADCggIAQAAAA==.Azurefalls:BAAANQAECgUICQAAAA==.',
Ba='Badfiremage:BAAANQAECgYIBgAAAA==.Balthïer:BAAANQAECgEIAwAAAA==.Bark:BAAANQAECgUICQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAAANQADCgcIBwABNQAECgYIBwABAAAAAA==.Beeb:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Beefisting:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.Beezz:BAAANQAECgYIBwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQADCgYIDAAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQADCgYICwAAAA==.Bionarra:BAAANQAECgQIBQAAAA==.Bishopwr:BAAANQAECgIIAgAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBgAAAA==.Bohica:BAAANQADCgYICwAAAA==.',
Br='Brem:BAAANQAECgYIDAAAAA==.Briara:BAAANQADCgcICAAAAA==.Broknüs:BAAANQADCgYIBgAAAA==.Broníx:BAAANQADCgYICwAAAA==.Bropeep:BAAANQAECgQIBgAAAA==.',
Bu='Bullshott:BAAANQADCggIDAAAAA==.',
By='Bylun:BAAANQADCggIBAAAAA==.',
Ca='Calyen:BAAANQAECgMIAwAAAA==.Carartha:BAAANQADCggIDQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.Carrots:BAAANQADCgcIEgAAAA==.Cashmoolah:BAAANQAECgMIAwAAAA==.Catfight:BAAANQADCgYIEQAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAAANQAECgcIDAAAAA==.Charcoal:BAAANQAECgQIBAAAAA==.Chasebakes:BAAANQAECgUICQAAAA==.Cheesecake:BAAANQADCgcIEgAAAA==.Choks:BAAANQADCgYIEQAAAA==.Chumbawamba:BAAANQADCgQIBAAAAA==.Chéfboyrlee:BAAANQAECgMIBAABNQAECgkJFwACAOQcAA==.',
Ci='Cindiyoohoo:BAAANQAECgQIBQAAAA==.Cizmac:BAAANQADCgIIAgAAAA==.',
Co='Corruptdata:BAAANQADCgIIAgAAAA==.Cownado:BAAANQADCgYIEQABNQAECgMIAwABAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgIIAgAAAA==.Cut:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Cy='Cyfelen:BAAANQAECgQIBQAAAA==.Cynleel:BAAANQADCgYIDAABNQADCgcIDQABAAAAAA==.',
Da='Darthmall:BAAANQADCgcIDQABNQAECgYIDQABAAAAAA==.Dawntyrant:BAAANQADCgEIAQAAAA==.',
De='Demidru:BAAANQAECgEIAQAAAA==.',
Di='Dibbydab:BAAANQAECgQIBQAAAA==.',
Dj='Django:BAAANQAECgIIAgAAAA==.Djehrtey:BAAANQADCgUIBQAAAA==.Djinni:BAAANQAECgYIDQAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAAANQAECgIIAgAAAA==.',
Dr='Dracnahr:BAAANQAECgIIAgAAAA==.Drenlee:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Du='Dumblegear:BAAANQAECgQIBAAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAAANQAECgEIAwABNQAECgIIAgABAAAAAA==.',
Dy='Dysdayne:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.',
Ed='Edinna:BAAANQAECgEIAQAAAA==.',
Ei='Eileamaid:BAAANQADCgUICAAAAA==.',
El='Elessedil:BAAANQADCgYIBwAAAA==.Ellemystic:BAAANQADCgUICAAAAA==.',
Em='Emila:BAEANQADCgYIDAABNQAECgYIBgABAAAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgEIAQAAAA==.Emriq:BAAANQADCgQIBwAAAA==.',
En='Enrique:BAAANQAECgcIEAAAAA==.',
Es='Estanna:BAAANQAECgYIBgAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQADCgYIBgAAAA==.',
Fe='Fearlesfreep:BAAANQAECgQIBAAAAA==.Febz:BAAANQADCggIEAAAAA==.Felatonin:BAAANQAECgYICAAAAA==.Felfüry:BAAANQAECgIIBQAAAA==.Fenixshaw:BAAANQADCgYIEAAAAA==.Festyr:BAAANQADCgMIAwAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finneas:BAAANQADCgcIDwAAAA==.',
Fo='Foggpy:BAAANQAECgQIBQAAAA==.',
Fr='Frostey:BAAANQAECgUICAAAAA==.Fröstmöurne:BAAANQAECgIIAwAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCgUIBQAAAA==.',
Ge='Geluria:BAAANQAECgIIAgAAAA==.Genghiskhan:BAAANQAECgYICQAAAA==.Geren:BAAANQAECggICAAAAA==.Geret:BAAANQAECgUIBQAAAA==.',
Gh='Ghanaria:BAAANQADCgQIBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYIBgAAAA==.',
Gl='Glitchy:BAAANQAECgQIBQAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAAANQAECgQIBQAAAA==.Goldglazeher:BAAANQAECgYIBwAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Golgotha:BAAANQABCgUIBQAAAA==.',
Gr='Graddy:BAAANQADCgMIAwAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgQIBAAAAA==.Greganir:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Gregdapro:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgIIAgAAAA==.',
Gu='Gunnyal:BAAANQADCgYIEQAAAA==.',
Gy='Gyathew:BAAANQAECgYIBwAAAA==.',
Ha='Hagunn:BAAANQAECgcIEQAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hevy:BAAANQAECgIIAgAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAAANQAECgQIBQAAAA==.Howlinnbrews:BAAANQADCgYIBgAAAA==.',
Ig='Ignore:BAAANQADCgcIDgABNQAECgYIBgABAAAAAA==.',
In='Invariable:BAAANQAECgIIAgAAAA==.',
Io='Iobo:BAAANQADCgYIEAAAAA==.',
Ir='Ironhidez:BAAANQAECgMIAwAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
Iz='Izerol:BAAANQAECggIDwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jebopally:BAAANQAECgYIBwAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAAANQAECgQIBAAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgIIAgAAAA==.',
Jo='Joehex:BAAANQAECgEIAQAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQADCgcIBwAAAA==.',
Ka='Kaleesh:BAAANQAECgcIEQAAAA==.Kallux:BAAANQAECgQIBAAAAA==.Kalma:BAAANQAECgEIAQAAAA==.Kananga:BAAANQADCgYIEQAAAA==.Kasca:BAAANQADCggIEwAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khalyraa:BAAANQADCggIEwAAAA==.',
Ki='Kiragrande:BAAANQAECgUIBgAAAA==.Kiriku:BAAANQAECgEIAQAAAA==.',
Ko='Korbinf:BAAANQADCggIDQAAAA==.Kotok:BAAANQADCgcIDgAAAA==.',
Kr='Krelein:BAAANQADCgcIEgAAAA==.',
Ku='Kurth:BAAANQADCgMIBAAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAAANQAECgQIBwAAAA==.Levin:BAAANQAECgIIAgAAAA==.',
Li='Lilpwny:BAAANQAECgMIBAAAAA==.Linissa:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.',
Ll='Llght:BAAANQAECgEIAQAAAA==.',
Lo='Logankord:BAAANQAECgEIAQAAAA==.Lokeira:BAAANQAECgYIBgAAAA==.Loonnah:BAAANQADCgMIAwAAAA==.',
Lu='Luuniren:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Luvbug:BAAANQAECgUIBwAAAA==.',
Ly='Lyara:BAAANQAECgcIDgAAAA==.Lythos:BAAANQAECgYIBgAAAA==.',
['Lø']='Lørdøfßud:BAAANQAECgQIBQAAAA==.',
Ma='Machomans:BAAANQAECgQIBAAAAA==.Magdann:BAAANQABCgIIAgAAAA==.Mahasamatman:BAAANQADCgUICQAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAAANQAECgQIBAAAAA==.Mastamojo:BAAANQAECgQIBQAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQADCgcIEgAAAA==.Melendaren:BAAANQADCgQIBgAAAA==.Meltara:BAAANQADCgMIAwAAAA==.Messìah:BAAANQAECgEIAQAAAA==.Metamonster:BAAANQADCgMIBQAAAA==.',
Mi='Mickie:BAAANQADCggICAAAAA==.Miniav:BAAANQADCgUICAAAAA==.Mirko:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.',
Ml='Mladjo:BAAANQADCgYICgAAAA==.',
Mo='Mockery:BAAANQAECgQIBAAAAA==.Mokokniki:BAAANQAECgQIBQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQADCggICgABNQADCggIEwABAAAAAA==.Morticiá:BAAANQADCgUICQAAAA==.Mourningstar:BAAANQAECgQICAABNQAECgkJFwADAAskAA==.Mozaic:BAAANQAECgQIBAAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgUICAAAAA==.Naek:BAAANQADCgUICAAAAA==.',
Ne='Necromus:BAAANQADCgYIEQAAAA==.Nekra:BAAANQADCgcIEgAAAA==.',
Ni='Nibbi:BAAANQADCgYIBgAAAA==.Nicehair:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
No='Nocturnum:BAAANQAECgQIBAAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgMIAwAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCgQIBAAAAA==.Oltiyet:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.',
On='Onepuffman:BAABNQAECoEXAAICAAkJ5Bx6AQBTAwACAAkJ5Bx6AQBTAwAAAA==.Onetwocowpow:BAAANQAECgQIBQAAAA==.',
Or='Ordanith:BAAANQAECgUICAAAAA==.Orionn:BAAANQAFFAEIAQAAAA==.',
Os='Osø:BAAANQAECgIIAgAAAA==.',
Ov='Oven:BAAANQAECgQIBAAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.',
Ph='Phyras:BAAANQABCgQIBAAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgIIAwAAAA==.',
Pr='Praystation:BAAANQADCggIEwAAAA==.',
Ra='Raelone:BAAANQAECgEIAQAAAA==.Rageofmommy:BAAANQADCgEIAQAAAA==.Raidoe:BAAANQAECgIIAgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rangérz:BAAANQAECgQIBQAAAA==.Ranoa:BAAANQAECgUICQABNQAECgcIDwABAAAAAA==.Ravencraw:BAAANQADCgMIBAAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Regress:BAAANQAECgEIAQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAAANQAECgQIBAAAAA==.',
Ri='Rinche:BAAANQAECgQIBQAAAA==.Rishir:BAAANQADCgYIBgAAAA==.',
Ro='Rolland:BAAANQADCggIFQAAAA==.Rootbeamxo:BAAANQADCgUIBQAAAA==.Rosefyre:BAAANQAECgYIBgAAAA==.',
Ru='Rudo:BAAANQADCgcIDAABNQAECgYIBgABAAAAAA==.Rumproblem:BAAANQAECgQIBAAAAA==.Ruri:BAAANQADCggICAABNQAECgYIBgABAAAAAA==.',
Ry='Ryeger:BAAANQAECgQIBAAAAA==.Ryuaoi:BAAANQAECgEIAgAAAA==.',
['Ró']='Róótbear:BAAANQADCggIDgAAAA==.',
Sa='Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAAANQAECgEIAQAAAA==.Sandwiches:BAAANQAECgcICgAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAAANQAECgQIBAAAAA==.',
Se='Seo:BAAANQADCgMIAwAAAA==.Setresh:BAAANQAECgUICQAAAA==.',
Sh='Shamwowhex:BAAANQAECgUIBQAAAA==.Shangöh:BAAANQADCgQIBQABNQAECgEIAwABAAAAAA==.Sharatira:BAAANQADCgQIBgAAAA==.Shivyn:BAAANQAECgQIBgAAAA==.',
Si='Sibadeekay:BAAANQAECgUICQAAAA==.Sickkid:BAAANQADCggIEgAAAA==.Silkiegirl:BAAANQAECgEIAgAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sindrya:BAAANQADCgYIBgAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQAECgIIAgAAAA==.',
Sp='Spellforge:BAAANQADCgQIBAAAAA==.Spinach:BAAANQADCgYIBgAAAA==.',
St='Staretra:BAAANQAECgQIBQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgMIAwAAAA==.',
Ta='Taadra:BAAANQAECgQIBAAAAA==.Talerah:BAAANQAECgEIAQAAAA==.Talilyia:BAAANQADCgUIBwAAAA==.Talohae:BAAANQAECgcIDwAAAA==.Tanjent:BAAANQADCgYICgAAAA==.Tatsuma:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Tavv:BAAANQAECgYICgAAAA==.',
Te='Terp:BAAANQABCgYIBgAAAA==.',
Th='Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Thorrs:BAAANQAECgUICAAAAA==.Thuglifé:BAAANQAECgQIBAAAAA==.Thundacat:BAAANQAECgQIBQAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Tidemaiden:BAAANQADCggIFAAAAA==.Tipsymancer:BAAANQAECgQIBQAAAA==.',
Tr='Treesus:BAAANQAECgYICAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgQIBAAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgYICgABAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQADCgYIEQAAAA==.',
Ve='Velashis:BAAANQADCgcIDAAAAA==.Vermin:BAAANQAECgQICAAAAA==.',
Vi='Vicvega:BAAANQAECgYIBgAAAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAAANQAECgQIBwAAAA==.',
Vo='Void:BAAANQADCgYICgAAAA==.Volstak:BAAANQADCgMIBAAAAA==.',
Vr='Vresim:BAAANQAECgcIDQAAAA==.',
Vu='Vugnus:BAAANQADCgYIDQAAAA==.',
['Vé']='Véxx:BAAANQADCgcIEgAAAA==.',
Wa='Waycaps:BAAANQAECgIIAwAAAA==.',
We='Westrin:BAAANQAECgYIDAAAAA==.',
Wi='Wife:BAAANQAECgcIEAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wo='Worgendork:BAAANQAECggIAQAAAA==.',
Wr='Wrathe:BAAANQAECgQIBAAAAA==.',
Ya='Yacob:BAAANQAECgIIAgAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.',
Ye='Yenneferr:BAAANQADCgYIBgAAAA==.',
Ym='Ymir:BAAANQAECgYICgAAAA==.',
Za='Zaft:BAAANQAECgQIBAAAAA==.Zaha:BAAANQAECgcIDQAAAA==.Zappsz:BAAANQADCgcIEQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgQIBwAAAA==.Zem:BAAANQADCgIIAgAAAA==.Zenithyr:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Zennish:BAAANQADCgUICAAAAA==.Zeplen:BAAANQAECgUICQAAAA==.Zeroultra:BAAANQADCgcIEgAAAA==.Zeusmos:BAAANQAECgQIBAAAAA==.',
Zi='Zithenex:BAAANQADCgYIEQAAAA==.',
Zu='Zugleesh:BAAANQADCgEIAQAAAA==.',
Zw='Zwar:BAAANQADCgMIAwAAAA==.',
['Ál']='Álister:BAAANQADCgYIDQAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQADCgYIBgAAAA==.',
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
