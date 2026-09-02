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
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaminae:BAAANQADCggIDgAAAA==.',
Ab='Abracastabya:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ae='Aedar:BAAANQAECgcICAAAAA==.Aeturnas:BAAANQAECgMIBAAAAA==.',
Ai='Aire:BAAANQADCgcIBwAAAA==.',
Al='Alauradona:BAAANQADCgEIAQAAAA==.Aliana:BAAANQAECgIIAgAAAA==.Allesta:BAAANQADCgIIAgAAAA==.Allypally:BAAANQADCgcIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAAANQADCggIDwAAAA==.',
Ar='Arcstream:BAAANQADCgcIBwAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQADCgYICwAAAA==.',
As='Astarii:BAAANQADCggIEgAAAA==.Asterica:BAAANQAECgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAAANQADCgcICAAAAA==.',
Ay='Ayano:BAAANQAECgQIBQAAAA==.Ayulur:BAAANQADCgUIBQAAAA==.',
Az='Azurefalls:BAAANQAECgQIBAAAAA==.',
Ba='Balthïer:BAAANQAECgEIAgAAAA==.Bark:BAAANQAECgQIBAAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Beezz:BAAANQAECgEIAQAAAA==.Beliara:BAAANQADCgYIBgAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQADCgYICwAAAA==.Bionarra:BAAANQAECgEIAQAAAA==.Bishopwr:BAAANQAECgEIAQAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bohica:BAAANQADCgYIBgAAAA==.',
Br='Brem:BAAANQAECgQIBgAAAA==.Briara:BAAANQADCgUIBQAAAA==.Broknüs:BAAANQADCgYIBgAAAA==.Broníx:BAAANQADCgYICwAAAA==.Bropeep:BAAANQAECgEIAgAAAA==.',
Bu='Bullshott:BAAANQADCgQIBAAAAA==.',
By='Bylun:BAAANQADCggIBAAAAA==.',
Ca='Caliice:BAAANQAECgQIBAAAAA==.Calyen:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Carartha:BAAANQADCgMIAwAAAA==.Carnitine:BAAANQADCgYIBgABNQADCgcIDgABAAAAAA==.Carrots:BAAANQADCgYICwAAAA==.Cashmoolah:BAAANQADCggIDwAAAA==.Catfight:BAAANQADCgYICwAAAA==.',
Ch='Chadilton:BAAANQADCgYIDQAAAA==.Chadsmon:BAAANQAECgUIBQAAAA==.Charcoal:BAAANQADCggIDgAAAA==.Chasebakes:BAAANQAECgMIBAAAAA==.Cheesecake:BAAANQADCgYICwAAAA==.Choks:BAAANQADCgYICwAAAA==.Chumbawamba:BAAANQADCgQIBAAAAA==.Chéfboyrlee:BAAANQAECgMIBAABNQAECggIDgABAAAAAA==.',
Ci='Cindiyoohoo:BAAANQAECgEIAQAAAA==.Cizmac:BAAANQADCgEIAQAAAA==.',
Co='Corruptdata:BAAANQADCgIIAgAAAA==.Cownado:BAAANQADCgYICwAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgIIAgAAAA==.Cut:BAAANQADCgYICwABNQADCgcIBwABAAAAAA==.',
Cy='Cyfelen:BAAANQAECgEIAQAAAA==.Cynleel:BAAANQADCgYIBgABNQADCgcICwABAAAAAA==.',
Da='Darthmall:BAAANQADCgYICgABNQAECgUIBwABAAAAAA==.',
De='Demidru:BAAANQADCgcIDAAAAA==.',
Di='Dibbydab:BAAANQAECgEIAQAAAA==.',
Dj='Djehrtey:BAAANQADCgQIBAAAAA==.Djinni:BAAANQAECgUIBwAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYICwAAAA==.',
Do='Doodle:BAAANQADCggIDgAAAA==.',
Dr='Dracnahr:BAAANQADCgMIAwAAAA==.Drenlee:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
Du='Dumblegear:BAAANQAECgEIAQAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Dy='Dysdayne:BAAANQADCggICAAAAA==.',
Ed='Edinna:BAAANQADCggIDQAAAA==.',
Ei='Eileamaid:BAAANQADCgQIBwAAAA==.',
El='Elessedil:BAAANQADCgYIBwAAAA==.Ellemystic:BAAANQADCgQIBwAAAA==.',
Em='Emila:BAEANQADCgYIBgABNQADCgcICwABAAAAAA==.Emokilla:BAAANQADCgYICAAAAA==.Emriq:BAAANQADCgQIBAAAAA==.',
En='Enrique:BAAANQAECgUICQAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.',
Fe='Fearlesfreep:BAAANQADCggIDgAAAA==.Febz:BAAANQADCggICAAAAA==.Felatonin:BAAANQAECgEIAQAAAA==.Felfüry:BAAANQAECgIIAwAAAA==.Fenixshaw:BAAANQADCgYICwAAAA==.Festyr:BAAANQADCgMIAwAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finneas:BAAANQADCgYICgAAAA==.',
Fo='Foggpy:BAAANQAECgEIAQAAAA==.',
Fr='Frostey:BAAANQAECgMIAwAAAA==.Fröstmöurne:BAAANQAECgEIAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCgQIBAAAAA==.',
Ge='Geluria:BAAANQADCggIDwAAAA==.Genghiskhan:BAAANQAECgMIAwAAAA==.Geret:BAAANQAECgEIAQAAAA==.',
Gh='Ghanaria:BAAANQADCgQIBAAAAA==.',
Gi='Gingervex:BAAANQADCggICAAAAA==.',
Gl='Glitchy:BAAANQAECgEIAQAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAAANQAECgEIAQAAAA==.Goldglazeher:BAAANQAECgEIAQAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Gr='Graddy:BAAANQADCgMIAwAAAA==.Greeley:BAAANQADCggIDAAAAA==.Greganir:BAAANQADCgcICAABNQADCggIDwABAAAAAA==.Gregdapro:BAAANQADCggIDwAAAA==.Gritty:BAAANQABCgIIAgAAAA==.',
Gu='Gunnyal:BAAANQADCgYICwAAAA==.',
Gy='Gyathew:BAAANQAECgEIAQAAAA==.',
Ha='Hagunn:BAAANQAECgcICgAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hevy:BAAANQADCgYICwAAAA==.',
Hi='Hildzap:BAAANQADCgUIBQAAAA==.',
Ho='Holyshots:BAAANQAECgEIAQAAAA==.',
Ig='Ignore:BAAANQADCgcIDgAAAA==.',
In='Invariable:BAAANQADCgYICwAAAA==.',
Io='Iobo:BAAANQADCgUICgAAAA==.',
Ir='Ironhidez:BAAANQAECgEIAQAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
Iz='Izerol:BAAANQAECgQIBAAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jebopally:BAAANQAECgEIAQAAAA==.Jetblack:BAAANQADCggIDwAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.',
Jo='Joehex:BAAANQADCgcICAAAAA==.Joulez:BAAANQADCgYIBgAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.',
Ka='Kaleesh:BAAANQAECgYICgAAAA==.Kallux:BAAANQADCggIDwAAAA==.Kalma:BAAANQADCggIDwAAAA==.Kananga:BAAANQADCgYICwAAAA==.Kasca:BAAANQADCgcICwAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khalyraa:BAAANQADCgcICwAAAA==.',
Ki='Kiragrande:BAAANQAECgEIAQAAAA==.Kiriku:BAAANQADCgYICwAAAA==.',
Ko='Kotok:BAAANQADCgUICAAAAA==.',
Kr='Krelein:BAAANQADCgYICwAAAA==.',
Ku='Kurth:BAAANQADCgEIAQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAAANQAECgQIBAAAAA==.',
Li='Lilpwny:BAAANQAECgEIAQAAAA==.',
Ll='Llght:BAAANQADCgYIBgAAAA==.',
Lo='Logankord:BAAANQADCgcICAAAAA==.Lokeira:BAAANQADCgcIBwAAAA==.Loonnah:BAAANQADCgMIAwAAAA==.',
Lu='Luuniren:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Luvbug:BAAANQAECgIIAgAAAA==.',
Ly='Lyara:BAAANQAECgUIBwAAAA==.Lythos:BAAANQADCgcIBwAAAA==.',
['Lø']='Lørdøfßud:BAAANQAECgEIAQAAAA==.',
Ma='Machomans:BAAANQAECgEIAQAAAA==.Magdann:BAAANQABCgIIAgAAAA==.Mahasamatman:BAAANQADCgQIBAAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAAANQAECgIIAgAAAA==.Mastamojo:BAAANQAECgEIAQAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQADCgYICwAAAA==.Melendaren:BAAANQADCgQIBgAAAA==.Meltara:BAAANQADCgMIAwAAAA==.Messìah:BAAANQADCgYIDAAAAA==.Metamonster:BAAANQADCgIIAgAAAA==.',
Mi='Miniav:BAAANQADCgQIBwAAAA==.Mirko:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ml='Mladjo:BAAANQADCgYIBgAAAA==.',
Mo='Mockery:BAAANQADCggICAAAAA==.Mokokniki:BAAANQAECgEIAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQADCggICAAAAA==.Morticiá:BAAANQADCgQIBAAAAA==.Mourningstar:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Mozaic:BAAANQADCggIDwAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgQIBwAAAA==.Naek:BAAANQADCgQIBwAAAA==.',
Ne='Necromus:BAAANQADCgYICwAAAA==.Nekra:BAAANQADCgYICwAAAA==.',
Ni='Nibbi:BAAANQADCgYIBgAAAA==.Nicehair:BAAANQADCggICAAAAA==.',
No='Nocturnum:BAAANQADCggIDgAAAA==.Notoriouschu:BAAANQADCgIIAgAAAA==.',
Ny='Nyctea:BAAANQADCgMIAwAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCgQIBAAAAA==.Oltiyet:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.',
On='Onepuffman:BAAANQAECggIDgAAAA==.Onetwocowpow:BAAANQAECgEIAQAAAA==.',
Or='Ordanith:BAAANQAECgMIAwAAAA==.Orionn:BAAANQAECgcICwAAAA==.',
Ov='Oven:BAAANQADCggIDwAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Pi='Pinesoul:BAAANQABCgQIAgAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQADCgcIDwAAAA==.',
Pr='Praystation:BAAANQADCgcICwABNQADCggICAABAAAAAA==.',
Ra='Raelone:BAAANQADCgcIDAAAAA==.Rageofmommy:BAAANQADCgEIAQAAAA==.Raidoe:BAAANQADCggIDwAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rangérz:BAAANQAECgEIAQAAAA==.Ranoa:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.Ravencraw:BAAANQADCgMIBAAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Regress:BAAANQAECgEIAQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAAANQADCgYICwAAAA==.',
Ri='Rinche:BAAANQAECgEIAQAAAA==.',
Ro='Rolland:BAAANQADCgcIDQAAAA==.Rosefyre:BAAANQADCggIDAAAAA==.',
Ru='Rudo:BAAANQADCgcIBwABNQADCgcIDgABAAAAAA==.Rumproblem:BAAANQADCgcIBwAAAA==.',
Ry='Ryeger:BAAANQADCgUIBQAAAA==.Ryuaoi:BAAANQAECgEIAQAAAA==.',
['Ró']='Róótbear:BAAANQADCgYIBgAAAA==.',
Sa='Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAAANQADCggIDgAAAA==.Sandwiches:BAAANQAECgQIBAAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAAANQADCggIEAAAAA==.',
Se='Seo:BAAANQADCgMIAwAAAA==.Setresh:BAAANQAECgQIBAAAAA==.',
Sh='Shamwowhex:BAAANQADCgIIAgAAAA==.Shangöh:BAAANQADCgQIBQABNQAECgEIAgABAAAAAA==.Sharatira:BAAANQADCgQIBgAAAA==.Shivyn:BAAANQAECgIIAgAAAA==.',
Si='Sibadeekay:BAAANQAECgMIBAAAAA==.Sickkid:BAAANQADCgcICgAAAA==.Silkiegirl:BAAANQAECgEIAQAAAA==.Silverwulf:BAAANQADCgQIBgAAAA==.Sindrya:BAAANQADCgYIBgAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQADCgYIEQAAAA==.',
Sp='Spellforge:BAAANQADCgQIBAAAAA==.',
St='Staretra:BAAANQAECgEIAQAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.',
Ta='Taadra:BAAANQADCggIDwAAAA==.Talerah:BAAANQADCggIDQAAAA==.Talilyia:BAAANQADCgQIBgAAAA==.Talohae:BAAANQAECgYICAAAAA==.Tanjent:BAAANQADCgUICQAAAA==.Tavv:BAAANQAECgQIBAAAAA==.',
Te='Terp:BAAANQABCgIIAgAAAA==.',
Th='Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Thorrs:BAAANQAECgMIAwAAAA==.Thuglifé:BAAANQADCgIIAgAAAA==.Thundacat:BAAANQAECgEIAQAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Tidemaiden:BAAANQADCgYIDAAAAA==.Tipsymancer:BAAANQAECgEIAQAAAA==.',
Tr='Treesus:BAAANQAECgIIAgAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgEIAQAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQADCgYICwAAAA==.',
Ve='Velashis:BAAANQADCgcIDAAAAA==.Vermin:BAAANQAECgQIBAAAAA==.',
Vi='Vicvega:BAAANQADCgcIDgAAAA==.Visandar:BAAANQAECgYIBQAAAA==.Vivif:BAAANQAECgEIAwAAAA==.',
Vo='Void:BAAANQADCgQIBAAAAA==.Volstak:BAAANQADCgEIAQAAAA==.',
Vr='Vresim:BAAANQAECgUIBwAAAA==.',
Vu='Vugnus:BAAANQADCgYICwAAAA==.',
['Vé']='Véxx:BAAANQADCgYICwAAAA==.',
Wa='Waycaps:BAAANQAECgIIAgAAAA==.',
We='Westrin:BAAANQAECgQIBgAAAA==.',
Wi='Wife:BAAANQAECgYICQAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wo='Worgendork:BAAANQAECgYIAQAAAA==.',
Wr='Wrathe:BAAANQADCgYIBgAAAA==.',
Ya='Yacob:BAAANQADCgcICwAAAA==.',
Ye='Yenneferr:BAAANQADCgYIBgAAAA==.',
Ym='Ymir:BAAANQAECgQIBAAAAA==.',
Za='Zaft:BAAANQAECgEIAQAAAA==.Zaha:BAAANQAECgUIBgAAAA==.Zappsz:BAAANQADCgYICgAAAA==.',
Ze='Zedfrey:BAAANQAECgMIAwAAAA==.Zem:BAAANQADCgIIAgAAAA==.Zennish:BAAANQADCgQIBwAAAA==.Zeplen:BAAANQAECgQIBAAAAA==.Zeroultra:BAAANQADCgYICwAAAA==.Zeusmos:BAAANQADCggICAAAAA==.',
Zi='Zithenex:BAAANQADCgYICwAAAA==.',
Zu='Zugleesh:BAAANQADCgEIAQAAAA==.',
['Ál']='Álister:BAAANQADCgQIBwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
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
