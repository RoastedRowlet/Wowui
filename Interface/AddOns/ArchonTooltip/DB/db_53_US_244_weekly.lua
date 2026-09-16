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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Monk-Brewmaster','Paladin-Retribution','Monk-Windwalker','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAAANQAECgUICQAAAA==.',
Ab='Abracastabya:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECoEYAAICAAgJSxlXGQBaAgACAAgJSxlXGQBaAgAAAA==.Aenledron:BAAANQAECgEIAQAAAA==.Aeturnas:BAAANQAECgUIDQAAAA==.',
Ai='Aire:BAAANQAECgMIBAAAAA==.',
Al='Alanima:BAAANQADCgYIDAAAAA==.Alauradona:BAAANQADCgMIBQAAAA==.Aliana:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Alittlegeeky:BAAANQADCgIIAgABNQAECgYIDQABAAAAAA==.Allesta:BAAANQADCgIIAwAAAA==.Allypally:BAAANQADCgcIBwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQADCggIDQAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAAANQAECgYICgAAAA==.',
Ar='Arcstream:BAAANQAECgEIAQAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQADCgcIGQAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAAANQAECgYIDgAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAAANQAECgQIBQAAAA==.',
Ay='Ayano:BAAANQAECgcIEgAAAA==.Ayulur:BAAANQAECgEIAgAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAAANQAECgYIDgAAAA==.',
Ba='Badfiremage:BAAANQAECgcIDQAAAA==.Balthïer:BAAANQAECgUICAAAAA==.Bark:BAAANQAECgYIDgAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAAANQAECgYIBgABNQAECggIDwABAAAAAA==.Beeb:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.Beefisting:BAAANQADCgIIAgABNQAECggIDwABAAAAAA==.Beezz:BAAANQAECggIDwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQADCggIEwAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQADCgYIEQAAAA==.Bionarra:BAAANQAECgQICQAAAA==.Bishopwr:BAAANQAECgQIBgAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBgAAAA==.Bohica:BAAANQADCggIEgAAAA==.',
Br='Brem:BAABNQAECoEUAAIDAAgJxRrXQwCFAgADAAgJxRrXQwCFAgAAAA==.Briara:BAAANQADCgcIDwAAAA==.Broknüs:BAAANQADCgYIBgAAAA==.Broníx:BAAANQADCgYICwAAAA==.Bropeep:BAAANQAECgQICgAAAA==.',
Bu='Bullshott:BAAANQAECgEIAQAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggIBAAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Calyen:BAAANQAECgMIAwAAAA==.Carartha:BAAANQAECgEIAQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Carrots:BAAANQADCgcIGQAAAA==.Cashmoolah:BAAANQAECgQIBwAAAA==.Catfight:BAAANQADCgYIFwAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAABNQAECoEVAAIEAAkJ4A5sKQAvAgAEAAkJ4A5sKQAvAgAAAA==.Charcoal:BAAANQAECgYICgAAAA==.Chasebakes:BAAANQAECgcIEAAAAA==.Cheesecake:BAAANQADCgcIEgAAAA==.Choks:BAAANQADCgYIFwAAAA==.Chumbawamba:BAAANQADCgQIBAAAAA==.Chéfboyrlee:BAAANQAECgQIBwABNQAFFAQIBgAFANARAA==.',
Ci='Cindiyoohoo:BAAANQAECgUICgAAAA==.Cizmac:BAAANQADCgIIAgAAAA==.',
Co='Corruptdata:BAAANQADCgIIAgAAAA==.Cownado:BAAANQADCgcIGQABNQAECgMIAwABAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgcIEQABNQAECgMIBAABAAAAAA==.',
Cy='Cyfelen:BAAANQAECgUICgAAAA==.Cynleel:BAAANQADCggIEwABNQAECgEIAQABAAAAAA==.',
Da='Dahrena:BAAANQADCgYIBgAAAA==.Darthmall:BAAANQAECgQIBAABNQAECggIFQAGAO0ZAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAAANQAECgIIAwAAAA==.Derat:BAAANQADCggICAAAAA==.',
Di='Dibbydab:BAAANQAECgQIBQAAAA==.',
Dj='Django:BAAANQAECgYICAAAAA==.Djehrtey:BAAANQADCgcIDAAAAA==.Djinni:BAABNQAECoEVAAIGAAgJ7RnbBQBiAgAGAAgJ7RnbBQBiAgAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAAANQAECgIIBAAAAA==.',
Dr='Dracnahr:BAAANQAECgMIBAAAAA==.Drenleah:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Drenlee:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Du='Dumblegear:BAAANQAECgQIBQAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAAANQAECgQIBwAAAA==.',
Dy='Dysdayne:BAAANQADCggIFwABNQAECgIIAwABAAAAAA==.',
Ed='Edinna:BAAANQAECgEIAQAAAA==.',
Ei='Eileamaid:BAAANQADCgYIDQAAAA==.',
El='Elessedil:BAAANQADCggIDgAAAA==.Ellemystic:BAAANQADCgcIDgAAAA==.Elspeth:BAAANQADCgIIAQABNQAECgIIAgABAAAAAA==.',
Em='Emila:BAEANQADCgYIDAABNQAECgYIDAABAAAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgIIAgAAAA==.Emriq:BAAANQADCgYIDQAAAA==.',
En='Enrique:BAABNQAECoEaAAIHAAgJbSGWFgDsAgAHAAgJbSGWFgDsAgAAAA==.',
Er='Erazath:BAAANQADCgYIDAABNQAECgcIDQABAAAAAA==.',
Es='Estanna:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgEIAQAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQADCggIBwAAAA==.',
Fe='Fearlesfreep:BAAANQAECgYICgAAAA==.Febz:BAAANQAECgIIAgAAAA==.Felatonin:BAAANQAECgcIDgAAAA==.Felfüry:BAAANQAECgQICQAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgMIAwAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finneas:BAAANQAECgEIAQAAAA==.',
Fo='Foggpy:BAAANQAECgQICQAAAA==.',
Fr='Frostey:BAAANQAECgUICgAAAA==.Fröstmöurne:BAAANQAECgIIBQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCgYICwAAAA==.',
Ge='Geluria:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Genghiskhan:BAAANQAECgcIEAAAAA==.Geren:BAAANQAECggICAAAAA==.Geret:BAAANQAECgUICQAAAA==.',
Gh='Ghanaria:BAAANQADCgQIBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAAANQAECgUICgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAAANQAECgQICQAAAA==.Goldglazeher:BAAANQAECgcIDgAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgMIAwAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgUICAAAAA==.Greganir:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Gregdapro:BAAANQAECgIIAgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQADCgYIFwAAAA==.',
Gy='Gyathew:BAAANQAECgcIDgAAAA==.',
Ha='Hagunn:BAAANQAECgcIEgAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hevy:BAAANQAECgQIBQAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAAANQAECgUICgAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Ig='Ignore:BAAANQADCgcIDgABNQAECgcIDQABAAAAAA==.',
In='Invariable:BAAANQAECgQIBQAAAA==.',
Io='Iobo:BAAANQADCgYIFgAAAA==.',
Ir='Ironhidez:BAAANQAECgUICAAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
Iz='Izerol:BAABNQAECoEdAAIIAAkJvh/3AwBVAwAIAAkJvh/3AwBVAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECgcIDgABAAAAAA==.Jebopally:BAAANQAECgcIDgAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAAANQAECgQICAAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgQIBgAAAA==.',
Jo='Joehex:BAAANQAECgQIBQAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQADCgcIBwAAAA==.',
Ka='Kaidoe:BAAANQADCgMIAwAAAA==.Kaleesh:BAAANQAECgcIEQAAAA==.Kallux:BAAANQAECgYICgAAAA==.Kalma:BAAANQAECgMIBAAAAA==.Kananga:BAAANQADCgYIFwAAAA==.Kasca:BAAANQAECgEIAQAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khalyraa:BAAANQAECgEIAQAAAA==.',
Ki='Kiragrande:BAAANQAECgYIBwAAAA==.Kiriku:BAAANQAECgIIAwAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQADCggIDgAAAA==.Kotok:BAAANQADCgcIFQAAAA==.',
Kr='Krelein:BAAANQADCgcIGQAAAA==.',
Ku='Kurth:BAAANQADCgMIBAAAAA==.',
Ky='Kyu:BAAANQADCgYIBgAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAAANQAECgYIEAAAAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgIIAgABNQAECggIFQAGAO0ZAA==.',
Ll='Llght:BAAANQAECgIIAwAAAA==.',
Lo='Logankord:BAAANQAECgQIBQAAAA==.Lokeira:BAAANQAECgcIDQAAAA==.Loonnah:BAAANQADCgQIBAAAAA==.',
Lu='Luuniren:BAAANQADCggIDgABNQAECgIIAwABAAAAAA==.Luvbug:BAAANQAECgYIDQAAAA==.',
Ly='Lyara:BAABNQAECoEZAAMJAAgJQB3mFgCfAgAJAAgJQB3mFgCfAgAEAAIJ4hEVkgCQAAAAAA==.Lythos:BAAANQAECgcIDQAAAA==.',
['Lø']='Lørdøfßud:BAAANQAECgUICgAAAA==.',
Ma='Machomans:BAAANQAECgQIBQAAAA==.Magdann:BAAANQABCgIIAgAAAA==.Mahasamatman:BAAANQADCgYIDwAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAAANQAECgUIBwAAAA==.Mastamojo:BAAANQAECgQICQAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQADCgcIGQAAAA==.Melendaren:BAAANQADCgcIDAAAAA==.Meltara:BAAANQADCgMIAwAAAA==.Messìah:BAAANQAECgIIAwAAAA==.Metamonster:BAAANQADCgUIBwAAAA==.',
Mi='Mickie:BAAANQAECgIIAgAAAA==.Miniav:BAAANQADCgYIDQAAAA==.Mirko:BAAANQADCgYICQABNQAECgQIBQABAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAAANQAECgYICgAAAA==.Mokokniki:BAAANQAECgQICQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Morticiá:BAAANQADCgYIDwAAAA==.Mourningstar:BAAANQAECgQIDAABNQAECgkJIAACADMmAA==.Mozaic:BAAANQAECgYICgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgcIDgAAAA==.Naek:BAAANQADCgYIDgAAAA==.',
Ne='Necromus:BAAANQADCgYIFwAAAA==.Nekra:BAAANQADCgcIGQAAAA==.',
Ni='Nibbi:BAAANQADCgYIBgAAAA==.Nicehair:BAAANQAECgUIBQAAAA==.',
No='Nocturnum:BAAANQAECgUICQAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgMIAwAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCgQIBAAAAA==.Oltiyet:BAAANQADCgUIBwABNQAECgIIAwABAAAAAA==.',
On='Onepuffman:BAACNQAFFIEGAAIFAAQJ0BGrAABzAQAFAAQJ0BGrAABzAQA1AAQKgR8AAgUACQkfIPUBAGUDAAUACQkfIPUBAGUDAAAA.Onetwocowpow:BAAANQAECgUICgAAAA==.',
Or='Ordanith:BAAANQAECgYIDQAAAA==.Orionn:BAABNQAECoEgAAIKAAkJoSSxAQDMAwAKAAkJoSSxAQDMAwAAAA==.',
Os='Osø:BAAANQAECgQIBgAAAA==.',
Ov='Oven:BAAANQAECgYICgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgMICAAAAA==.',
Pr='Praystation:BAAANQAECgEIAQAAAA==.',
Ra='Raelone:BAAANQAECgMIAwAAAA==.Rageofmommy:BAAANQADCgEIAgAAAA==.Raidoe:BAAANQAECgIIAgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAAANQAECgQICQAAAA==.Ranoa:BAAANQAECgcIEAAAAA==.Ravencraw:BAAANQADCgMIBAAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Regress:BAAANQAECgEIAQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAAANQAECgQICAAAAA==.',
Ri='Rinche:BAAANQAECgQIBQAAAA==.Rishir:BAAANQAECgEIAQAAAA==.',
Ro='Rolland:BAAANQAECgIIAgAAAA==.Rootbeamxo:BAAANQADCgUIBQAAAA==.Rosefyre:BAAANQAECgYIDAAAAA==.',
Ru='Rudo:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Rumproblem:BAAANQAECgQIBgAAAA==.Ruri:BAAANQADCggIDgABNQAECgYIDAABAAAAAA==.',
Ry='Ryeger:BAAANQAECgYICgAAAA==.Ryuaoi:BAAANQAECgEIAwAAAA==.',
['Ró']='Róótbear:BAAANQAECgEIAQAAAA==.',
Sa='Safety:BAAANQAECgMIAwAAAA==.Salaine:BAAANQADCgIIAQAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAAANQAECgYIBwAAAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAAANQAECgYICgAAAA==.Schism:BAAANQAECgIIAgAAAA==.',
Se='Sentren:BAAANQADCgQIBAAAAA==.Seo:BAAANQADCgMIAwAAAA==.Setresh:BAAANQAECgYIDgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgUIBQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgUICAABAAAAAA==.Sharatira:BAAANQADCgcIDAAAAA==.Shivyn:BAAANQAECgQICgAAAA==.',
Si='Sibadeekay:BAAANQAECgYIDwAAAA==.Sickkid:BAAANQAECgEIAQAAAA==.Silkiegirl:BAAANQAECgUIBwAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sindrya:BAAANQADCgYIBgAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQAECgQIBgAAAA==.',
So='Solára:BAAANQAECgUICQAAAA==.',
Sp='Spellforge:BAAANQADCgcICwAAAA==.Spinach:BAAANQADCgYIBgAAAA==.Sprath:BAAANQADCgYIBgAAAA==.',
St='Staretra:BAAANQAECgUICgAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAAANQAECgYICgAAAA==.Talerah:BAAANQAECgUIBgAAAA==.Talilyia:BAAANQADCgcIDQAAAA==.Talohae:BAABNQAECoEXAAILAAgJ0yS+AgBaAwALAAgJ0yS+AgBaAwAAAA==.Tanjent:BAAANQAECgEIAQAAAA==.Tatsuma:BAAANQADCgYIDAABNQAECgIIAwABAAAAAA==.Tavv:BAAANQAECgcIEQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Thorrs:BAAANQAECgUIDAAAAA==.Thuglifé:BAAANQAECgYICgAAAA==.Thundacat:BAAANQAECgUICgAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Tidemaiden:BAAANQAECgQIBAAAAA==.Tipsymancer:BAAANQAECgUICgAAAA==.',
Tr='Treesus:BAAANQAECgYIDgAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgUIBgAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQABCgUIBQABAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQADCgYIFAAAAA==.',
Ve='Velashis:BAAANQAECgIIAgAAAA==.Vermin:BAAANQAECgcIDwAAAA==.',
Vi='Vicvega:BAAANQAECgYIDAAAAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAAANQAECgYIDQAAAA==.Vivila:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Vo='Void:BAAANQADCgYIDAAAAA==.Volstak:BAAANQADCgMIBQAAAA==.',
Vr='Vresim:BAABNQAECoEXAAMMAAgJDhpFDQAJAgAMAAcJRxhFDQAJAgANAAcJ+RKFFADIAQAAAA==.',
Vu='Vugnus:BAAANQADCgYIDQAAAA==.',
['Vé']='Véxx:BAAANQADCgcIGAAAAA==.',
Wa='Waycaps:BAAANQAECgMIBQAAAA==.',
We='Westrin:BAAANQAECgcIDQAAAA==.',
Wi='Wiegraf:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Wife:BAAANQAECggIEgAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wo='Worgendork:BAAANQAECggIAQAAAA==.',
Wr='Wrathe:BAAANQAECgQIBAAAAA==.',
Ya='Yacob:BAAANQAECgQIBgAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.',
Ye='Yenneferr:BAAANQAECgIIAgAAAA==.',
Ym='Ymir:BAAANQAECggIEQABNQABCgUIBQABAAAAAA==.',
Yo='Yosaf:BAAANQADCgcIBwAAAA==.',
Za='Zaft:BAAANQAECgUICQAAAA==.Zaha:BAAANQAECgcIEwAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgUIDAAAAA==.Zem:BAAANQADCgcICQAAAA==.Zenithyr:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAAANQAECgcIDwAAAA==.Zeroultra:BAAANQADCgcIGQAAAA==.Zeusmos:BAAANQAECgQIBgAAAA==.',
Zi='Zithenex:BAAANQADCgYIFwAAAA==.',
Zu='Zugleesh:BAAANQADCgEIAQAAAA==.',
Zw='Zwar:BAAANQADCgYICQAAAA==.',
['Ál']='Álister:BAAANQADCgYIEwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
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
