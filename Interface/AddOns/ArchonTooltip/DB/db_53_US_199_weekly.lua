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

local lookup = {'Unknown-Unknown','Shaman-Restoration','DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Holy','Monk-Brewmaster','Hunter-BeastMastery',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ad='Adalaidê:BAAANQADCgQIBAAAAA==.',
Ae='Aerynne:BAAANQADCgMIBAAAAA==.',
Ai='Airie:BAAANQADCgYIBwAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQADCggIEAAAAA==.Alert:BAAANQADCgYICQAAAA==.Aloris:BAAANQAECgQICAAAAA==.',
Am='Amednato:BAAANQAECgEIAQAAAA==.',
An='Anaeli:BAAANQAECgQIBwAAAA==.Anastarian:BAAANQADCgYIDAAAAA==.Ancalagonn:BAAANQAECgIIAgAAAA==.Angita:BAAANQADCgYIDwAAAA==.Annaris:BAAANQAFFAEIAQAAAA==.Antipæn:BAEANQAFFAEIAQAAAA==.',
Ap='Apologia:BAAANQAECgIIAgAAAA==.',
Aq='Aquaphobic:BAAANQAECgEIAQAAAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Archaeolight:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Ares:BAAANQAFFAEIAQAAAA==.Armorgorden:BAAANQAECgQIBQAAAA==.Aroviaa:BAAANQAECgQIBQAAAA==.Arpmek:BAAANQAECgQIBAAAAA==.',
As='Asharienne:BAAANQAECgEIAQAAAA==.Ashlynne:BAAANQAECgUICAAAAA==.',
Au='Audiobully:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Auralynn:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Aurtt:BAAANQAECgEIAgAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAAANQAECgEIAQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQAECgEIAQAAAA==.Balora:BAAANQADCgEIAQAAAA==.Barnette:BAAANQAECgYICwAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgEIAQAAAA==.Berristan:BAAANQAECgYIEAAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQADCgYICwAAAA==.Bittytigs:BAABNQAECoEZAAICAAkJMBhRFABtAgACAAkJMBhRFABtAgAAAA==.',
Bl='Bluewitchpa:BAAANQADCgQICAAAAA==.Blumangood:BAAANQAECgUIBgAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgIIAgAAAA==.Boudiicca:BAAANQADCgMIBAAAAA==.Boxmasterr:BAAANQAECgQIBQAAAA==.',
Br='Brasmir:BAAANQAECgUIBgAAAA==.Brianzero:BAAANQABCgQIBgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.Buik:BAAANQADCgYIBgAAAA==.Bulgogi:BAAANQAECgcIEAAAAA==.',
['Bö']='Börk:BAAANQADCgYIDwAAAA==.',
Ca='Capy:BAAANQADCgEIAQABNQAECgcICQABAAAAAA==.Cayda:BAAANQADCgEIAQAAAA==.Caylara:BAAANQADCgcIEQAAAA==.Cayssaber:BAAANQADCgQIBAAAAA==.',
Ce='Celrythis:BAAANQADCgcIEAAAAA==.',
Ch='Chai:BAAANQADCgYICgAAAA==.Chaintrain:BAAANQAECgMIAwAAAA==.Chellyy:BAAANQADCgcIEAAAAA==.',
Co='Coralorchid:BAAANQADCggIFQAAAA==.Coralrages:BAAANQAECgMIAwAAAA==.',
Cu='Curissan:BAAANQADCgYICQAAAA==.',
Da='Dalir:BAAANQADCgcIEAAAAA==.Dalspin:BAAANQADCgYIDAABNQAFFAEIAQABAAAAAA==.Dalthepal:BAAANQAFFAEIAQAAAA==.Damné:BAAANQAECgUICQAAAA==.',
De='Deadish:BAAANQAECgMIAwAAAA==.Deathsaberss:BAAANQAECgcICwAAAA==.Deathvex:BAAANQADCggIFAAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dendahn:BAAANQAECgUIBgAAAA==.Destinee:BAAANQADCgYIDwAAAA==.',
Di='Diladrin:BAAANQAECgYICwAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQADCggIFQAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dottmatrix:BAAANQADCgcIDgAAAA==.Doubt:BAAANQAECgcIDQABNQAECggICgABAAAAAA==.',
Dr='Dreadwing:BAAANQADCgMIBAAAAA==.Druromu:BAAANQADCgcIEAAAAA==.',
Du='Dufs:BAAANQAECgcIDAAAAA==.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAAANQAECgQIBAAAAA==.',
Dw='Dwagon:BAAANQAECgQIBgAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUICAAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAAANQAECgYIDAABNQAECgcICwABAAAAAA==.Dûna:BAAANQAECgcICwAAAA==.',
El='Elaatia:BAAANQAECgQIBQAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgABAAAAAA==.Ellysprocket:BAAANQADCgQIBAAAAA==.Elrric:BAAANQADCgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
Er='Erakron:BAAANQAECgQIBAAAAA==.Erine:BAAANQADCgQIBwAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Eroviaa:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.',
Ez='Ezothen:BAAANQAECgEIAQAAAA==.',
Fa='Facelessman:BAAANQABCgYIBgAAAA==.Faedoria:BAAANQADCgUICgAAAA==.Faeryln:BAAANQAECgUICQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQADCgYIDwAAAA==.Fisticuffs:BAAANQADCgQIBgAAAA==.Fizcrankshot:BAAANQAECgUICAAAAA==.',
Fl='Flamewhisker:BAAANQADCgYIDwAAAQ==.',
Fr='Fraublucher:BAAANQAECgIIAgAAAA==.Frewyn:BAAANQADCgcIDQAAAA==.Frostimoth:BAAANQAECgEIAQAAAA==.Frozty:BAAANQAECgEIAQAAAA==.',
Ga='Galandel:BAAANQADCgQICAAAAA==.Galial:BAABNQAECoEYAAIDAAgJhRWuAgAuAgADAAgJhRWuAgAuAgAAAA==.Gantar:BAAANQABCgMIAwABNQAECgUICQABAAAAAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIFAAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ge='Gelasera:BAAANQADCgYIDwAAAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAAANQAECgUICgAAAA==.',
Gl='Glaivethras:BAAANQAECgUICQAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAAANQAECgcIBwABNQAECgkJGQAEAGkhAA==.Groot:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQADCggIGgABAAAAAA==.Hannebal:BAAANQAECgUICQAAAA==.',
He='Heynow:BAAANQADCgUIBQAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAAANQAECgUICQAAAA==.',
Hu='Huasca:BAAANQADCgUIBQAAAA==.Huthuel:BAAANQABCgYIDgAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
['Hà']='Hàney:BAEANQABCgMIBgAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAAANQAECgYICgAAAA==.',
Id='Idontsuck:BAAANQADCgQIBAAAAA==.',
Il='Ilieau:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQABCgQIBgAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAECggICgAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAEANQAECgcIDgAAAA==.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAAANQAECgQIBQAAAA==.',
Ja='Janderick:BAAANQADCggICwAAAA==.',
Je='Jellacee:BAAANQADCgMIBAAAAA==.',
Ji='Jimboberjim:BAAANQAECgcIEAAAAA==.Jiminie:BAAANQAECgEIAQAAAA==.',
Jo='Jolio:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Joltraxi:BAAANQABCgMIAwABNQAECgMIAwABAAAAAA==.Joshie:BAAANQAECgUICQAAAA==.Joshy:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAAANQAECgQIBQAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQADCgcIBwAAAA==.',
Ka='Kadaan:BAAANQAECgEIAQAAAA==.Kagemaro:BAAANQAECgIIAwAAAA==.Kalimathath:BAAANQADCgUIBwAAAA==.Kalzod:BAAANQAECgYICwAAAA==.Katia:BAAANQADCgcIEAAAAA==.Kativeria:BAAANQADCgYIDwAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQADCggIEAAAAA==.',
Ke='Kebab:BAAANQAECgQIBAAAAA==.Kelsifer:BAAANQAECgQICAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIIAgAAAA==.',
Ki='Killmora:BAAANQADCgQICAAAAA==.Kippars:BAAANQADCggIFgAAAA==.',
Ko='Kodazoff:BAAANQAECgEIAgAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAAANQAECgQICAAAAA==.',
Kr='Krissylu:BAAANQADCgcIEAAAAA==.Krothix:BAAANQAECgMIBAAAAA==.Kryrande:BAAANQADCgQIBAAAAA==.Kryshym:BAAANQADCgcIDAAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kurorø:BAAANQADCgcIEAAAAA==.',
Ky='Kyrayna:BAAANQADCgEIAQAAAA==.',
La='Ladara:BAAANQAECgQIBgAAAA==.Laima:BAAANQADCgEIAQAAAA==.Lavitz:BAAANQADCgIIAgAAAA==.',
Le='Leheo:BAAANQADCgEIAQAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgQIBQAAAA==.Lemook:BAAANQADCggIEgAAAA==.',
Li='Licker:BAAANQAECgUICQAAAA==.Lightbulb:BAAANQADCgQICAAAAA==.Lightstormer:BAAANQADCgQICAAAAA==.Lilamae:BAAANQADCgYIDQAAAA==.Lilarielle:BAAANQAECgQIBQAAAA==.Lildookie:BAAANQADCggICwAAAA==.Liliela:BAAANQAECgEIAQAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQAAAA==.Liø:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Ll='Lluniez:BAAANQAECgMIAwAAAA==.',
Lo='Lockroknroll:BAAANQADCggIGgAAAA==.Losoli:BAAANQAECgUIBgAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQADCgYICgAAAA==.',
Lu='Lutherion:BAAANQAECgIIAwAAAA==.',
Ly='Lycemmas:BAAANQAECgMIAwAAAA==.',
Ma='Macoun:BAAANQAECgIIAgAAAA==.Magicshowers:BAAANQAECgQIBQAAAA==.Manseed:BAAANQABCgQIBAAAAA==.Maple:BAAANQADCgMIAwAAAA==.Martei:BAAANQAECgcIDAAAAA==.Maríneth:BAAANQADCgcIDwAAAA==.Mascara:BAAANQAECgEIAQAAAA==.',
Mi='Midway:BAAANQAECgIIAgAAAA==.Minizee:BAAANQADCgYIBgAAAA==.Mirokushan:BAAANQADCgMIBAAAAA==.Missfire:BAAANQADCgQIBAAAAA==.Misticlady:BAAANQAECgIIAgAAAA==.Mistrariel:BAAANQADCgMIAwABNQAECgIIBAABAAAAAA==.',
Mo='Moluubar:BAAANQABCgQIBAAAAA==.Moradin:BAAANQADCgEIAQAAAA==.Mordemour:BAAANQADCgcIFAAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQAECgYIBgAAAA==.',
Na='Nalik:BAAANQADCgcIEAAAAA==.Nanou:BAAANQADCgQIBAAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.',
Ne='Nerzheul:BAAANQADCgYICgAAAA==.',
Ni='Nimravidae:BAAANQAECgEIAQAAAA==.Ninelives:BAAANQAECgEIAQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.',
No='Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgEIAQAAAA==.',
Nr='Nreaf:BAAANQAECgYIDQAAAA==.',
Oi='Oili:BAAANQAECgcIEAAAAA==.',
Ol='Olarrick:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.',
Oo='Oops:BAAANQAECgcIDwAAAA==.',
Or='Ornstein:BAAANQADCgYIAwAAAA==.',
Ot='Ottuk:BAAANQAECgcIEAAAAA==.',
Pa='Padpaw:BAAANQAECgIIAwAAAA==.Pakraxes:BAAANQAECgQIBQAAAA==.Paksenarrion:BAAANQAECgEIAQAAAA==.Palehoof:BAAANQADCgIIAgAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Parts:BAAANQABCgEIAQAAAA==.Patchington:BAAANQADCgcIEAAAAA==.Pañdemönium:BAAANQAECgQIBgAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQADCgYIBgAAAA==.',
Ph='Philia:BAAANQAECgcIDQAAAA==.',
Pi='Pixelme:BAAANQAECgMIBAAAAA==.',
Pl='Pleggster:BAAANQADCgMIAwAAAA==.',
Po='Pochula:BAAANQAECgEIAQAAAA==.',
Pr='Primo:BAABNQAECoEYAAIFAAgJqA4cJQDvAQAFAAgJqA4cJQDvAQAAAA==.Protricity:BAAANQAECgQIBAAAAA==.',
Ps='Psychoprowla:BAAANQAECgQIBQAAAA==.Psychozdrood:BAAANQADCgYIBgAAAA==.',
['Pæ']='Pæn:BAEANQADCgcIDQABNQAFFAEIAQABAAAAAA==.',
Ra='Ragana:BAAANQADCggICgAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQADCggICAAAAA==.Rancooll:BAAANQADCgQIBwAAAA==.Rasniir:BAAANQAECgMIBQAAAA==.',
Re='Regna:BAAANQAECgcIEQAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAABNQAECoEYAAIGAAkJfhwKAwCxAgAGAAkJfhwKAwCxAgAAAA==.Requinix:BAAANQAECgUIBgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAAANQAECgEIAQAAAA==.Ritzo:BAAANQAECgEIAQAAAA==.',
Ro='Rocksanne:BAAANQADCggICQAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAAANQAECgIIAwAAAA==.Rukâ:BAAANQADCgEIAQAAAA==.Rumi:BAAANQAECgYICwAAAA==.Rumm:BAAANQADCgEIAQAAAA==.',
Ry='Ryeekan:BAAANQAECgEIAQAAAA==.Ryuma:BAAANQAECgQIBAAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQAECgEIAQAAAA==.Sathari:BAAANQAECgEIAQAAAA==.',
Sc='Schaden:BAAANQAECgQIBQAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEIAQAAAA==.Sekk:BAAANQAECgUIBgAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgIIAgAAAA==.Sera:BAAANQADCgQIBAAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIBAABNQAECgUIBwABAAAAAA==.Shalasyr:BAAANQAECgEIAQAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgQICAAAAA==.Shamzee:BAAANQAECgYICgAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQADCgYICAAAAA==.Shuddarun:BAABNQAECoEYAAIHAAkJ4yO2AQCfAwAHAAkJ4yO2AQCfAwAAAA==.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgEIAQAAAA==.Sindraesong:BAAANQAECgIIAgAAAA==.',
Sk='Skithiryx:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.Skuldd:BAAANQABCgMIBQAAAA==.',
Sl='Slayvylora:BAAANQADCgcIBwABNQADCggIFAABAAAAAA==.',
Sm='Smarte:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Snookums:BAAANQADCggIEAAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAAANQAECgIIAQAAAA==.',
St='Steelheart:BAAANQABCgIIAwAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQADCggIDgAAAA==.Stumper:BAAANQAECgIIAwAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAAANQAECgIIAgAAAA==.Sylvia:BAAANQAECgQIBQAAAA==.Syngeance:BAAANQADCggIEAAAAA==.Synèsterwolf:BAAANQAECgcIAgAAAA==.',
['Sí']='Síf:BAAANQADCgUICAAAAA==.',
Ta='Tadeusz:BAAANQAECgMIAwAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanleros:BAAANQAECgEIAQAAAA==.Taquítos:BAAANQADCgIIAgAAAA==.',
Te='Telana:BAAANQADCgQICAAAAA==.Tequitos:BAAANQAECgEIAQAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAAANQAECgMIAwAAAA==.Theduke:BAAANQADCgIIAwAAAA==.Thorias:BAAANQAECgYICAAAAA==.Thtime:BAAANQAECgQICAAAAA==.',
To='Tomoko:BAAANQADCgYICQAAAA==.Torment:BAAANQAECgUIBgAAAA==.',
Tr='Tristén:BAAANQAECgIIAgAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgEIAQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQADCggIEAAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAAANQAECgUIBgAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgMIAgAAAA==.',
Va='Vadka:BAAANQADCgcIDAAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQADCgYIDQAAAA==.Valkree:BAAANQADCgcIEwAAAA==.Valsavis:BAAANQAECgQIBQAAAA==.',
Ve='Veaolop:BAAANQABCgYICgAAAA==.Vellagosa:BAAANQADCgYIDwAAAA==.Verulan:BAAANQADCgUICAABNQADCgYIBgABAAAAAA==.Vexidari:BAAANQADCgYIBgAAAA==.Vexomous:BAAANQAECgcIEAAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAAANQAECgQIBQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQADCgEIAQAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYIBgAAAA==.',
We='Weiand:BAAANQAECgIIAgAAAA==.Wevark:BAAANQAECgEIAQAAAA==.',
Wh='Whatami:BAAANQAECgQIBAAAAA==.Wholemilk:BAAANQADCgcIEQAAAA==.Whîspers:BAAANQADCgYICwAAAA==.',
Wi='Wilhellena:BAAANQAECgQIBQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQADCgYICwABNQAECgIIBAABAAAAAA==.',
Wr='Wroughtsoul:BAAANQABCgEIAQAAAA==.Wrysoul:BAAANQAECgEIAQAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Xaldred:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.Xandir:BAAANQAECgIIBAAAAA==.Xarhunt:BAAANQADCgQIBAAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAAANQAECgUICQAAAA==.',
Xy='Xyal:BAAANQAECgIIAgAAAA==.Xyp:BAAANQADCgYIBgAAAA==.',
Yi='Yiago:BAAANQADCgQIBAAAAA==.',
Yo='Youknow:BAAANQADCgQIBAAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhpal:BAEANQAECgIIAwAAAA==.',
Zi='Zid:BAAANQAECgEIAQAAAA==.',
Zo='Zoenova:BAAANQADCggICAAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgQIBQAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAANQAECgQIBAAAAA==.',
['Üb']='Übernasus:BAAANQADCgQIBgAAAA==.',
['ßy']='ßyrøßløøð:BAAANQABCgIIAgAAAA==.',
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
