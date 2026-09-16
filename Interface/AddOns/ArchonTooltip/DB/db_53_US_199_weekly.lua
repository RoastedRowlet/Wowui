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

local lookup = {'Warrior-Arms','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','DeathKnight-Unholy','DemonHunter-Vengeance','Warrior-Protection','Warlock-Destruction','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Warrior-Fury','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ad='Adalaidê:BAAANQADCgQIBQAAAA==.',
Ae='Aerynne:BAAANQADCgQIBQAAAA==.',
Ai='Airie:BAAANQAECgQIBAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAAANQABCgcIBwABNQAECggIFwABAJkXAA==.Aluhx:BAAANQADCgYIBgABNQAECgYIDwACAAAAAA==.',
Am='Amednato:BAAANQAECgQIBQAAAA==.',
An='Anaeli:BAAANQAECgQIBwAAAA==.Anastarian:BAAANQADCgYIDwAAAA==.Ancalagonn:BAAANQAECgQIBgAAAA==.Angita:BAAANQADCgYIFQAAAA==.Annaris:BAABNQAECoEfAAMDAAkJMiRLAgC7AwADAAkJMiRLAgC7AwAEAAgJ7hhBGAAJAgAAAA==.Antipæn:BAEBNQAECoEeAAMFAAkJOSFRBAB8AwAFAAkJOSFRBAB8AwAGAAYJJCb+IgCTAgAAAA==.',
Ap='Apologia:BAAANQAECgQIBgAAAA==.',
Aq='Aquaphobic:BAAANQAECgEIAQAAAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Archaeolight:BAAANQADCgQIBAABNQAECgYIBgACAAAAAA==.Ares:BAABNQAECoEXAAIBAAkJhCS4BQCrAwABAAkJhCS4BQCrAwAAAA==.Armorgorden:BAAANQAECgUICgAAAA==.Aroviaa:BAAANQAECgQICQAAAA==.Arpmek:BAAANQAECgYICgAAAA==.',
As='Asharienne:BAAANQAECgIIAgAAAA==.Ashlynne:BAAANQAECgYICQAAAA==.',
Au='Audiobully:BAAANQADCgUIBgABNQAECgMIBgACAAAAAA==.Auralynn:BAAANQADCgYICAABNQAECgYICQACAAAAAA==.Aurtt:BAAANQAECgQIBgAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAAANQAECgQIBQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQAECgMIAwAAAA==.Balora:BAAANQADCgQIBQAAAA==.Barnette:BAAANQAECgYIEAAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgQIBQAAAA==.Berristan:BAABNQAECoEXAAIFAAgJwA3QMwDuAQAFAAgJwA3QMwDuAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgQIBAAAAA==.Bittytigs:BAABNQAECoEjAAIHAAkJTBqVFACyAgAHAAkJTBqVFACyAgAAAA==.',
Bl='Bluewitchpa:BAAANQADCgUIDQAAAA==.Blumangood:BAAANQAECgUICwAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgQIBgAAAA==.Boudiicca:BAAANQADCgQIBQAAAA==.Boxmasterr:BAAANQAECgQICQAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAAANQAECgUICwAAAA==.Brianzero:BAAANQABCgQIBgAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgQIBQACAAAAAA==.Buik:BAAANQADCgYICQAAAA==.Bulge:BAAANQAECgQIBQABNQAECggIGwAIABIYAA==.Bulgogi:BAABNQAECoEbAAIIAAgJEhgWHABdAgAIAAgJEhgWHABdAgAAAA==.',
['Bö']='Börk:BAAANQADCgYIFQAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAECggIEgACAAAAAA==.Cardran:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.Cayda:BAAANQADCgQIBAAAAA==.Caylara:BAAANQADCgcIEwAAAA==.Cayssaber:BAAANQADCggIDAAAAA==.',
Ce='Celrythis:BAAANQADCgcIEgAAAA==.',
Ch='Chai:BAAANQAECgQIBAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgMIBgACAAAAAA==.Chellyy:BAAANQADCggIGAABNQADCggIGQACAAAAAA==.',
Co='Coralorchid:BAAANQADCggIFQAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAAANQAECgYIBgAAAA==.',
Cu='Curissan:BAAANQAECgEIAQAAAA==.',
Da='Dalgon:BAAANQAECgQIBgABNQAFFAQIBQAFAGgNAA==.Dalir:BAAANQADCgcIEAAAAA==.Dalspin:BAAANQADCgYIDAABNQAFFAQIBQAFAGgNAA==.Dalthepal:BAACNQAFFIEFAAIFAAQJaA2/BABFAQAFAAQJaA2/BABFAQA1AAQKgRsAAgUACQlWFkkaAI4CAAUACQlWFkkaAI4CAAAA.Damné:BAAANQAECgUICQABNQAECgcIEAACAAAAAA==.Davidline:BAAANQAECgQIBAAAAA==.',
De='Deadish:BAAANQAECgQIBwAAAA==.Deathsaberss:BAAANQAECgcIEwAAAA==.Deathvex:BAAANQAECgIIAgAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgUIBQAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQIBwAAAA==.',
Di='Diladrin:BAAANQAECgcIEgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgEIAQAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dottmatrix:BAAANQADCgcIFQAAAA==.Doubledowns:BAAANQADCgMIAwAAAA==.',
Dr='Dreadwing:BAAANQADCgQIBQAAAA==.Druromu:BAAANQADCgcIEAAAAA==.',
Du='Dufs:BAAANQAECgcIEwAAAA==.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAAANQAECgUICQAAAA==.',
Dw='Dwagon:BAAANQAECgYIDAAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUICAAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAAANQAECgcIEgAAAA==.Dûna:BAAANQAECgcIDgABNQAECgcIEgACAAAAAA==.',
El='Elaatia:BAAANQAECgQICQAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgACAAAAAA==.Ellysprocket:BAAANQADCgUIBgAAAA==.Elrric:BAAANQADCgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQADCgYIBgAAAA==.',
Er='Erakron:BAAANQAECgQICAAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgQICQACAAAAAA==.Eroviaa:BAAANQADCgEIAQABNQAECgQICQACAAAAAA==.',
Ez='Ezothen:BAAANQAECgEIAQAAAA==.',
Fa='Facelessman:BAAANQABCggIDQAAAA==.Faedoria:BAAANQADCgcIEQAAAA==.Faeryln:BAAANQAECgYIDwAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQADCgMIAwABNQAECgQICwACAAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQADCgYIFQAAAA==.Fisticuffs:BAAANQADCgUICwAAAA==.Fizcrankshot:BAAANQAECgYIDgAAAA==.',
Fl='Flamewhisker:BAAANQADCgYIFQAAAQ==.',
Fr='Fraublucher:BAAANQAECgQIBgAAAA==.Frewyn:BAAANQADCgcIDQAAAA==.Frostimoth:BAAANQAECgQIBQAAAA==.Frozty:BAAANQAECgEIAQAAAA==.',
Ga='Galandel:BAAANQADCgUIDQAAAA==.Galial:BAABNQAECoEiAAIJAAgJaRoFAwB5AgAJAAgJaRoFAwB5AgAAAA==.Gantar:BAAANQADCgcIBwABNQAECgYIDwACAAAAAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIFgAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.',
Ge='Gelasera:BAAANQADCgYIFQAAAA==.Gemitra:BAAANQADCgcIBwABNQADCggIFQACAAAAAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAAANQAFFAEIAQAAAA==.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.Ghrol:BAAANQABCgYIBgABNQAECgYIDAACAAAAAA==.',
Gl='Glaivethras:BAAANQAECgYIDwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAAANQAECggIDAABNQAECgkJGQAIAGkhAA==.Groot:BAAANQADCgYIDQABNQAECgIIAwACAAAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECgcICQACAAAAAA==.Hannebal:BAAANQAECgYIDwAAAA==.',
He='Heynow:BAAANQADCgUICAAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAAANQAECgYIDwAAAA==.',
Ho='Hobs:BAAANQABCgMIAwAAAA==.Hoosier:BAAANQADCgUIBQAAAA==.',
Hu='Huasca:BAAANQADCgUIBQAAAA==.Huthuel:BAAANQABCggIEgAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.Hyve:BAAANQADCgcIBwAAAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAAANQAECgcIEQAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ilieau:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQABCgQIBgAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAECggIEQAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAEBNQAECoEYAAIKAAgJBCMRAgA1AwAKAAgJBCMRAgA1AwAAAA==.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAAANQAECgQICQAAAA==.',
Ja='Janderick:BAAANQAECgMIAwAAAA==.',
Je='Jellacee:BAAANQADCgQIBQAAAA==.',
Ji='Jimboberjim:BAABNQAECoEcAAILAAkJOCLfAACJAwALAAkJOCLfAACJAwAAAA==.Jiminie:BAAANQAECgUIBgAAAA==.',
Jo='Jolio:BAAANQAECgMIBgAAAA==.Joltraxi:BAAANQABCgMIAwABNQAECgMIBgACAAAAAA==.Joshie:BAAANQAECgYIDwAAAA==.Joshy:BAAANQADCgcIBwABNQAECgYIDwACAAAAAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAAANQAECgUICgAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQADCgcIBwAAAA==.',
Ka='Kadaan:BAAANQAECgEIAQAAAA==.Kagemaro:BAAANQAECgMIBgABNQAECgQIBAACAAAAAA==.Kalimathath:BAAANQADCgYICAAAAA==.Kalzod:BAAANQAECggIEgAAAA==.Kataki:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.Katia:BAAANQADCgcIEgAAAA==.Kativeria:BAAANQADCgcIFQAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQADCggIGAAAAA==.',
Ke='Kebab:BAAANQAECgQIBAAAAA==.Kelsifer:BAAANQAECgQICwAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIIAgAAAA==.',
Ki='Killmora:BAAANQADCgUIDQAAAA==.Kippars:BAAANQADCggIFgAAAA==.',
Ko='Kodazoff:BAAANQAECgEIAgAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAAANQAECgYIDAAAAA==.',
Kr='Krissylu:BAAANQADCgcIEAAAAA==.Krothix:BAAANQAECgQICAAAAA==.Kryrande:BAAANQADCgQICAAAAA==.Kryshym:BAAANQADCggIEAAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kuilei:BAAANQADCgUIBQABNQADCgcIDwACAAAAAA==.Kurorø:BAAANQADCgcIEgAAAA==.',
Ky='Kyrayna:BAAANQADCgIIAgAAAA==.',
La='Ladara:BAAANQAECgUICwAAAA==.Laima:BAAANQADCgEIAQAAAA==.Lavitz:BAAANQADCgIIAgAAAA==.',
Le='Leheo:BAAANQADCgIIAgAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgQICQAAAA==.Lemook:BAAANQAECgEIAQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAECgYIBgACAAAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightstormer:BAAANQADCgUIDQAAAA==.Lilamae:BAAANQADCgYIDQAAAA==.Lilarielle:BAAANQAECgQICwAAAA==.Lildookie:BAAANQADCggICwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.Liliela:BAAANQAECgQIBQAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgYIBgACAAAAAA==.Lite:BAAANQAECgEIAQAAAA==.Liø:BAAANQAECgYIBgAAAA==.',
Ll='Lluniez:BAAANQAECgQIBwAAAA==.',
Lo='Lockroknroll:BAAANQAECgcICQAAAA==.Losoli:BAAANQAECgUICwAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQADCgYICgAAAA==.',
Lu='Lutherion:BAAANQAECgQIBwAAAA==.',
Ly='Lycemmas:BAAANQAECgQIBgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgYIBgACAAAAAA==.',
Ma='Macoun:BAAANQAECgQIBgAAAA==.Magicshowers:BAAANQAECgQICQAAAA==.Manseed:BAAANQABCgQIBAAAAA==.Maple:BAAANQADCgQIBAAAAA==.Martei:BAAANQAECgcIEwAAAA==.Maríneth:BAAANQADCgcIEQAAAA==.Mascara:BAAANQAECgEIAQAAAA==.',
Mi='Midway:BAAANQAECgIIAgAAAA==.Minizee:BAAANQADCgYIBgAAAA==.Mirokushan:BAAANQADCgQIBQAAAA==.Missfire:BAAANQADCgUICQAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCgMIAwABNQAECgMIBwACAAAAAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAAANQAECgEIAQAAAA==.Moradin:BAAANQADCgEIAQAAAA==.Mordemour:BAAANQADCggIFQAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mushù:BAAANQADCgcIBwABNQAECgYICgACAAAAAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQADCgcIEAAAAA==.Nanou:BAAANQAECgIIAgAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.',
Ne='Nerzheul:BAAANQAECgIIAgAAAA==.',
Ni='Nimravidae:BAAANQAECgQIBQAAAA==.Ninelives:BAAANQAECgEIAQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgUICgACAAAAAA==.Niteryu:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.',
No='Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgMIBAAAAA==.',
Nr='Nreaf:BAABNQAECoEXAAIGAAgJvxIIPgADAgAGAAgJvxIIPgADAgAAAA==.',
Oi='Oili:BAABNQAECoEdAAMMAAgJgxhWAwBfAgAMAAgJgxhWAwBfAgANAAQJ1gul5gDwAAAAAA==.',
Ol='Olarrick:BAAANQADCgYICwABNQAFFAEIAQACAAAAAA==.',
Oo='Oops:BAABNQAECoEbAAIOAAkJax2tCwD+AgAOAAkJax2tCwD+AgAAAA==.',
Or='Ornstein:BAAANQADCgcIAwAAAA==.',
Ot='Ottuk:BAABNQAECoEbAAIIAAgJQhgAHABeAgAIAAgJQhgAHABeAgAAAA==.',
Pa='Padpaw:BAAANQAECgUICAAAAA==.Pakraxes:BAAANQAECgQICQAAAA==.Paksenarrion:BAAANQAECgQIBQAAAA==.Palehoof:BAAANQADCgUIBwAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECgQICgACAAAAAA==.Pandemönium:BAAANQAECgQIBAABNQAECgQICgACAAAAAA==.Parts:BAAANQABCgMIAwAAAA==.Patchington:BAAANQADCgcIEgAAAA==.Pañdemönium:BAAANQAECgQICgAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQAECgIIAgAAAA==.',
Ph='Philia:BAABNQAECoEXAAMBAAgJmRdHRAAjAgABAAgJ2RJHRAAjAgAKAAMJwBwqFAACAQAAAA==.',
Pi='Pixelme:BAAANQAFFAEIAQAAAA==.',
Pl='Pleggster:BAAANQADCgMIAwAAAA==.',
Po='Pochula:BAAANQAECgIIAwAAAA==.',
Pr='Primo:BAABNQAECoEnAAIFAAgJmw+/MwDvAQAFAAgJmw+/MwDvAQAAAA==.Protricity:BAAANQAECgQIBAAAAA==.',
Ps='Psychoprowla:BAAANQAECgYICwAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pæ']='Pæn:BAEANQADCgcIEAABNQAECgkJHgAFADkhAA==.',
Ra='Ragana:BAAANQAECgMIAwAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQADCggICAAAAA==.Rancooll:BAAANQADCgUICAAAAA==.Rasniir:BAAANQAECgYICwAAAA==.',
Re='Regna:BAABNQAECoEcAAMBAAgJDyY/EwAtAwABAAgJ9iM/EwAtAwAPAAQJCibnBgDAAQAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFIEFAAIQAAMJdA4QAgDIAAAQAAMJdA4QAgDIAAA1AAQKgSEAAhAACQmmHLoEAJgCABAACQmmHLoEAJgCAAAA.Requinix:BAAANQAECgUICwAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQIBAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAAANQAECgQIBQAAAA==.Ritzo:BAAANQAECgQIBQAAAA==.',
Ro='Rocksanne:BAAANQADCggICQAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAAANQAECgQIBwAAAA==.Rukâ:BAAANQADCgIIAgAAAA==.Rumi:BAAANQAECggIEAAAAA==.Rumm:BAAANQADCgEIAQAAAA==.',
Ry='Ryeekan:BAAANQAECgQIBQAAAA==.Ryuma:BAAANQAECgQIBAAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQAECgIIAwAAAA==.Salsinor:BAAANQADCgUIBQAAAA==.Sathari:BAAANQAECgQIBQAAAA==.',
Sc='Schaden:BAAANQAECgQIBQAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEIAQAAAA==.Sekk:BAAANQAECgUICwAAAA==.Selecta:BAAANQADCgcIBwAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgIIBAAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQICgABNQAECgYIDQACAAAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgUIDQAAAA==.Shamzee:BAAANQAECgcIEQAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgEIAQAAAA==.Shuddarun:BAACNQAFFIEFAAIDAAQJ5R2NAQCNAQADAAQJ5R2NAQCNAQA1AAQKgSEAAgMACQlRJKsCALEDAAMACQlRJKsCALEDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgQIBQAAAA==.Sindraesong:BAAANQAECgUIBwAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAAAAA==.Skuldd:BAAANQABCgMIBQAAAA==.',
Sl='Slayvylora:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Sm='Smarte:BAAANQADCgEIAQABNQAECgYIBgACAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Snookums:BAAANQADCggIGAAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAAANQAECgUIBgAAAA==.',
St='Steelheart:BAAANQABCgMIAwAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQADCggIFgAAAA==.Stumper:BAAANQAECgMIBgAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAAANQAECgQIBgAAAA==.Sylvia:BAAANQAECgQICQAAAA==.Syngeance:BAAANQADCggIGAAAAA==.Synèsterwolf:BAAANQAECgcIAgAAAA==.',
['Sí']='Síf:BAAANQADCgUICAAAAA==.',
Ta='Tadeusz:BAAANQAECgMIAwAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanleros:BAAANQAECgQIBQAAAA==.Taquítos:BAAANQADCgIIAgAAAA==.',
Te='Telana:BAAANQADCgUIDQAAAA==.Tequitos:BAAANQAECgQIBQAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAAANQAECgMIBAAAAA==.Theduke:BAAANQADCgIIAwAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAAANQAECgYIDQAAAA==.Thtime:BAAANQAECgYIDgAAAA==.',
To='Tomoko:BAAANQADCgYICQAAAA==.Torment:BAAANQAECgUICwAAAA==.',
Tr='Tristén:BAAANQAECgIIBAAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgQIBQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQADCggIGAAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAAANQAECgYIDAAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAAANQAECggICQAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQIBgAAAA==.',
Va='Vadka:BAAANQADCgcIDgAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQADCgcIDwAAAA==.Valkree:BAAANQADCggIFAAAAA==.Valsavis:BAAANQAECgQICQAAAA==.',
Ve='Veaolop:BAAANQABCggIDgAAAA==.Vellagosa:BAAANQADCgYIFQAAAA==.Vernice:BAAANQADCgYIBgABNQADCggIFQACAAAAAA==.Verulan:BAAANQADCgUICAABNQADCgYIBgACAAAAAA==.Vexidari:BAAANQADCgYIDAAAAA==.Vexomous:BAABNQAECoEbAAMRAAgJLBymAQDDAgARAAgJLBymAQDDAgAEAAIJ2QIORABTAAAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAAANQAECgQICQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQADCgEIAQAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
We='Weiand:BAAANQAECgMIBQAAAA==.Wevark:BAAANQAECgQIBQAAAA==.',
Wh='Whatami:BAAANQAECgYICgAAAA==.Wholemilk:BAAANQADCggIGQAAAA==.Whîspers:BAAANQADCgYIEQAAAA==.',
Wi='Wilhellena:BAAANQAECgQICQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQADCgYICwABNQAECgMIBwACAAAAAA==.',
Wr='Wroughtsoul:BAAANQABCgEIAQAAAA==.Wrysoul:BAAANQAECgQIBQAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECgQICgACAAAAAA==.Xaldred:BAAANQAECgQIBQABNQAECgcIEAACAAAAAA==.Xandir:BAAANQAECgMIBwAAAA==.Xarhunt:BAAANQADCgYIBAAAAA==.Xataryl:BAAANQADCgYIBgAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAAANQAECgYIDwAAAA==.',
Xy='Xyal:BAAANQAECgQIBgAAAA==.Xyp:BAAANQADCgYIBgAAAA==.',
Ya='Yamaya:BAAANQADCgMIAwAAAA==.',
Yi='Yiago:BAAANQADCgQIBAAAAA==.',
Yo='Youknow:BAAANQADCgYICAAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgMIBgACAAAAAA==.Zaxhpal:BAEANQAECgMIBgAAAA==.',
Zi='Zid:BAAANQAECgIIAgAAAA==.Ziparoo:BAAANQAECgQIBAAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUICgAAAA==.',
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
