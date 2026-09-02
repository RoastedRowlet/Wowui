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
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ad='Adalaidê:BAAANQADCgMIAwAAAA==.',
Ae='Aerynne:BAAANQADCgEIAQAAAA==.',
Ai='Airie:BAAANQADCgYIBwAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQADCggIDQAAAA==.Alert:BAAANQADCgYIBgAAAA==.Aloris:BAAANQAECgQIBAAAAA==.',
Am='Amednato:BAAANQADCggIDgAAAA==.',
An='Anaeli:BAAANQAECgIIAgAAAA==.Ancalagonn:BAAANQADCgQIBAAAAA==.Angita:BAAANQADCgYICQAAAA==.Annaris:BAAANQAECgcICwAAAA==.Antipæn:BAAANQAECgYICgAAAA==.',
Ap='Apologia:BAAANQADCggICQAAAA==.',
Aq='Aquaphobic:BAAANQAECgEIAQAAAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ares:BAAANQAECgcICgAAAA==.Armorgorden:BAAANQAECgEIAQAAAA==.Aroviaa:BAAANQAECgEIAQAAAA==.Arpmek:BAAANQADCggICAAAAA==.',
As='Asharienne:BAAANQADCggIEAAAAA==.Ashlynne:BAAANQAECgMIAwAAAA==.',
Au='Aurtt:BAAANQAECgEIAQAAAA==.',
['Aö']='Aöb:BAAANQADCgIIAgAAAA==.',
Ba='Bahahaknight:BAAANQADCggIDgAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQADCgcICQAAAA==.Balora:BAAANQADCgEIAQAAAA==.Barnette:BAAANQAECgQIBQAAAA==.Basyleus:BAAANQABCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgEIAQAAAA==.Berristan:BAAANQAECgYIBwAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQADCgYICwAAAA==.Bittytigs:BAAANQAECggIDQAAAA==.',
Bl='Bluewitchpa:BAAANQADCgIIBAAAAA==.Blumangood:BAAANQAECgEIAQAAAA==.',
Bo='Bollux:BAAANQAECgEIAQAAAA==.Bosc:BAAANQADCggIDgAAAA==.Boudiicca:BAAANQADCgEIAQAAAA==.Boxmasterr:BAAANQAECgEIAQAAAA==.',
Br='Brasmir:BAAANQAECgEIAQAAAA==.Brianzero:BAAANQABCgQIBAAAAA==.',
Bu='Bubblement:BAAANQADCgIIAgAAAQ==.Bubblemoth:BAAANQADCgMIAwABNQADCggIDAABAAAAAA==.Bulge:BAAANQADCggIEAABNQAECgYICQABAAAAAA==.Bulgogi:BAAANQAECgYICQAAAA==.',
['Bö']='Börk:BAAANQADCgYICQAAAA==.',
Ca='Cayda:BAAANQADCgEIAQAAAA==.Caylara:BAAANQADCgYICgAAAA==.',
Ce='Celrythis:BAAANQADCgUICQAAAA==.',
Ch='Chai:BAAANQADCgQIBAAAAA==.Chaintrain:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.',
Co='Coralorchid:BAAANQADCgcIDQAAAA==.Coralrages:BAAANQADCgcICwAAAA==.',
Cu='Curissan:BAAANQADCgYICQAAAA==.',
Da='Dalir:BAAANQADCgYICQAAAA==.Dalspin:BAAANQADCgYIBgABNQAECggICAABAAAAAA==.Dalthepal:BAAANQAECggICAAAAA==.Damné:BAAANQAECgQIBAAAAA==.',
De='Deathsaberss:BAAANQAECgQIBAAAAA==.Deathvex:BAAANQADCggIDAAAAA==.Dendahn:BAAANQAECgQIBQAAAA==.Destinee:BAAANQADCgYICQAAAA==.',
Di='Diladrin:BAAANQAECgQIBQAAAA==.',
Do='Doileag:BAAANQADCgYIDQAAAA==.Doongorn:BAAANQADCgEIAQAAAA==.Dottmatrix:BAAANQADCgUIBwAAAA==.Doubt:BAAANQAECgYIBgAAAA==.',
Dr='Dreadwing:BAAANQADCgEIAQAAAA==.Druromu:BAAANQADCgUICQAAAA==.',
Du='Dufs:BAAANQAECgUIBQAAAA==.Dunkan:BAAANQADCgUIBQAAAA==.Dustbunny:BAAANQAECgEIAQAAAA==.',
Dw='Dwagon:BAAANQAECgIIAgAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUIBQAAAA==.',
['Dû']='Dûn:BAAANQAECgQIBQAAAA==.Dûna:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
El='Elaatia:BAAANQAECgEIAQAAAA==.Elidria:BAAANQABCgIIAgAAAA==.Ellysprocket:BAAANQADCgMIAwAAAA==.Elrric:BAAANQADCgMIAwAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
Er='Erakron:BAAANQADCgYICQAAAA==.Erine:BAAANQADCgQIBAAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Eroviaa:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ez='Ezothen:BAAANQADCgcIBwAAAA==.',
Fa='Faedoria:BAAANQADCgQIBQAAAA==.Faeryln:BAAANQAECgQIBAAAAA==.',
Fi='Firebrande:BAAANQADCgYICQAAAA==.Fisticuffs:BAAANQADCgIIAgAAAA==.Fizcrankshot:BAAANQAECgMIAwAAAA==.',
Fl='Flamewhisker:BAAANQADCgYICQAAAQ==.',
Fr='Fraublucher:BAAANQADCggIDgAAAA==.Frewyn:BAAANQADCgYIBgAAAA==.Frostimoth:BAAANQADCggIDAAAAA==.Frozty:BAAANQADCgYICwAAAA==.',
Ga='Galandel:BAAANQADCgIIBAAAAA==.Galial:BAAANQAECgUICQAAAA==.Garrunter:BAAANQADCggIDwAAAA==.Gaznol:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Ge='Gelasera:BAAANQADCgYICQAAAA==.George:BAAANQAECgQIBwAAAA==.',
Gl='Glaivethras:BAAANQAECgQIBAAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Groot:BAAANQADCgYIBgABNQADCgcICQABAAAAAA==.',
Gu='Guava:BAAANQADCgUICQABNQADCgYICgABAAAAAA==.',
Ha='Hannebal:BAAANQAECgQIBAAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAAANQAECgQIBAAAAA==.',
Hu='Huasca:BAAANQADCgEIAQAAAA==.',
Hy='Hydra:BAAANQADCgYIBgAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAAANQAECgQIBQAAAA==.',
Il='Ilieau:BAAANQAECgEIAQAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQABCgQIBAAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAECgMIAwABNQAECgYIBgABAAAAAQ==.',
Ir='Irkenfox:BAEANQAECgQIBwAAAA==.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgUIBQAAAA==.',
Ix='Ixitt:BAAANQAECgEIAQAAAA==.',
Ja='Janderick:BAAANQADCgMIAwAAAA==.',
Je='Jellacee:BAAANQADCgEIAQAAAA==.',
Ji='Jimboberjim:BAAANQAECgYICQAAAA==.Jiminie:BAAANQAECgEIAQAAAA==.',
Jo='Jolio:BAAANQADCgcIDQAAAA==.Joshie:BAAANQAECgQIBAAAAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAAANQAECgEIAQAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Ka='Kadaan:BAAANQADCgYICAAAAA==.Kagemaro:BAAANQAECgEIAQAAAA==.Kalimathath:BAAANQADCgIIAgAAAA==.Kalzod:BAAANQAECgQIBQAAAA==.Katia:BAAANQADCgUICQAAAA==.Kativeria:BAAANQADCgYICQAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQADCgcIDQAAAA==.',
Ke='Kebab:BAAANQADCgUIBQAAAA==.Kelsifer:BAAANQAECgQIBQAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kendralust:BAAANQAECgMIAwAAAA==.Kerfufle:BAAANQABCgIIAgAAAA==.',
Ki='Killmora:BAAANQADCgIIBAAAAA==.Kippars:BAAANQADCggIDgAAAA==.',
Ko='Kodazoff:BAAANQAECgEIAQAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAAANQAECgQIBAAAAA==.',
Kr='Krissylu:BAAANQADCgYICQAAAA==.Krothix:BAAANQAECgEIAQAAAA==.Kryshym:BAAANQADCgUIBQAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kurorø:BAAANQADCgUICQAAAA==.',
Ky='Kyrayna:BAAANQADCgEIAQAAAA==.',
La='Ladara:BAAANQAECgIIAgAAAA==.Laima:BAAANQADCgEIAQAAAA==.Lavitz:BAAANQADCgEIAQAAAA==.',
Le='Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgEIAQAAAA==.Lemook:BAAANQADCgYICgAAAA==.',
Li='Licker:BAAANQAECgQIBAAAAA==.Lightbulb:BAAANQADCgQIBAAAAA==.Lightstormer:BAAANQADCgIIBAAAAA==.Lilamae:BAAANQADCgQIBwAAAA==.Lilarielle:BAAANQAECgEIAQAAAA==.Lildookie:BAAANQADCggICgAAAA==.Liliela:BAAANQADCggIDgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQAAAA==.',
Ll='Lluniez:BAAANQADCggIDgAAAA==.',
Lo='Lockroknroll:BAAANQADCggIEwAAAA==.Losoli:BAAANQAECgEIAQAAAA==.Lowchin:BAAANQADCgUIBgAAAA==.',
Lu='Lutherion:BAAANQAECgEIAQAAAA==.',
Ly='Lycemmas:BAAANQADCggIDwAAAA==.',
Ma='Macoun:BAAANQADCggIDgAAAA==.Magicshowers:BAAANQAECgEIAQAAAA==.Maple:BAAANQADCgMIAwAAAA==.Martei:BAAANQAECgUIBQAAAA==.Maríneth:BAAANQADCgUICAAAAA==.Mascara:BAAANQAECgEIAQAAAA==.',
Mi='Midway:BAAANQAECgIIAgAAAA==.Mirokushan:BAAANQADCgEIAQAAAA==.Misticlady:BAAANQADCgYIBgAAAA==.',
Mo='Mordemour:BAAANQADCgYIDgAAAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQADCgUIBQAAAA==.',
Na='Nalik:BAAANQADCgYICQAAAA==.Nanou:BAAANQADCgQIBAAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ne='Nerzheul:BAAANQADCgYICgAAAA==.',
Ni='Nimravidae:BAAANQADCggIDgAAAA==.Ninelives:BAAANQAECgEIAQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.',
No='Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQADCgcIDQAAAA==.',
Nr='Nreaf:BAAANQAECgQIBwAAAA==.',
Oi='Oili:BAAANQAECgYICQAAAA==.',
Oo='Oops:BAAANQAECgYICAAAAA==.',
Or='Ornstein:BAAANQADCgUIAwAAAA==.',
Ot='Ottuk:BAAANQAECgUICQAAAA==.',
Pa='Padpaw:BAAANQAECgIIAgAAAA==.Pakraxes:BAAANQAECgEIAQAAAA==.Paksenarrion:BAAANQADCggIDgAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Patchington:BAAANQADCgUICQAAAA==.Pañdemönium:BAAANQAECgIIAgAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQADCgYIBgAAAA==.',
Ph='Philia:BAAANQAECgYIBgAAAA==.',
Pi='Pixelme:BAAANQAECgMIBAAAAA==.',
Pl='Pleggster:BAAANQADCgMIAwAAAA==.',
Po='Pochula:BAAANQADCgYICwAAAA==.',
Pr='Primo:BAAANQAECgYICQAAAA==.Protricity:BAAANQADCgcIDAAAAA==.',
Ps='Psychoprowla:BAAANQAECgEIAQAAAA==.Psychozdrood:BAAANQADCgYIBgAAAA==.',
['Pæ']='Pæn:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.',
Ra='Ragana:BAAANQADCgIIAgAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQADCggICAAAAA==.Rancooll:BAAANQADCgIIAwAAAA==.Rasniir:BAAANQAECgIIAgAAAA==.',
Re='Regna:BAAANQAECgcICgAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAAANQAECgcIDQAAAA==.Requinix:BAAANQAECgEIAQAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAAANQADCggIDgAAAA==.Ritzo:BAAANQADCggIDQAAAA==.',
Ro='Rocksanne:BAAANQADCgcIBwAAAA==.Rooguee:BAAANQAECgIIAgAAAA==.',
Ru='Rukkis:BAAANQAECgEIAQAAAA==.Rukâ:BAAANQADCgEIAQAAAA==.Rumi:BAAANQAECgQIBQAAAA==.Rumm:BAAANQADCgEIAQAAAA==.',
Ry='Ryeekan:BAAANQADCgYIBgAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQADCgcICQAAAA==.Sathari:BAAANQADCggIDgAAAA==.',
Sc='Schaden:BAAANQAECgQIBAAAAA==.',
Se='Sekk:BAAANQAECgEIAQAAAA==.Selithira:BAAANQADCgcIDQAAAA==.Sera:BAAANQADCgQIBAAAAA==.',
Sh='Shabagnarang:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Shalasyr:BAAANQADCggIDgAAAA==.Shaletaz:BAAANQABCgQIBQAAAA==.Shamwowee:BAAANQADCgIIBAAAAA==.Shamzee:BAAANQAECgQIBAAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBAAAAA==.Shintok:BAAANQADCgUIBwAAAA==.Shuddarun:BAAANQAECgcIDQAAAA==.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQADCgYIDAAAAA==.Sindraesong:BAAANQADCggIDQAAAA==.',
Sl='Slayvylora:BAAANQADCgcIBwABNQADCggIDAABAAAAAA==.',
Sm='Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Snookums:BAAANQADCgcIDQAAAA==.',
Sp='Spicymaker:BAAANQADCgYICAAAAA==.',
St='Strifewood:BAAANQADCggIDgAAAA==.Stumper:BAAANQAECgEIAQAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAAANQADCgcICwAAAA==.Syngeance:BAAANQADCgcIDQAAAA==.Synèsterwolf:BAAANQAECgcIAQAAAA==.',
['Sí']='Síf:BAAANQADCgUICAAAAA==.',
Ta='Tadeusz:BAAANQAECgEIAQAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanleros:BAAANQADCgQIBAAAAA==.',
Te='Telana:BAAANQADCgIIBAAAAA==.Tequitos:BAAANQADCggICQAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAAANQADCggIEgAAAA==.Theduke:BAAANQADCgIIAgAAAA==.Thorias:BAAANQAECgEIAgAAAA==.Thtime:BAAANQAECgQIBAAAAA==.',
To='Tomoko:BAAANQADCgYICQAAAA==.Torment:BAAANQAECgEIAQAAAA==.',
Tr='Tristén:BAAANQAECgIIAgAAAA==.',
Tu='Tumbled:BAAANQADCgYIDAAAAA==.Tumbles:BAAANQADCgQIBAAAAA==.Tumni:BAAANQADCgcIDQAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAAANQAECgEIAQAAAA==.',
Va='Vadka:BAAANQADCgUIBQAAAA==.Vaeldrin:BAAANQAECgEIAQAAAA==.Vaha:BAAANQADCgYIBwAAAA==.Valkree:BAAANQADCgUIDQAAAA==.Valsavis:BAAANQAECgEIAQAAAA==.',
Ve='Vellagosa:BAAANQADCgYICQAAAA==.Verulan:BAAANQADCgUICAAAAA==.Vexidari:BAAANQADCgYIBgAAAA==.Vexomous:BAAANQAECgYICQAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAAANQAECgEIAQAAAA==.Vongogh:BAAANQADCgMIAwAAAA==.',
We='Weiand:BAAANQADCgYIBgAAAA==.Wevark:BAAANQADCggIDgAAAA==.',
Wh='Whatami:BAAANQAECgEIAQAAAA==.Wholemilk:BAAANQADCgYICgAAAA==.Whîspers:BAAANQADCgUIBQAAAA==.',
Wi='Wilhellena:BAAANQAECgEIAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
Wr='Wrysoul:BAAANQADCgMIAwAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Xaldred:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Xandir:BAAANQAECgIIAgAAAA==.Xarhunt:BAAANQADCgQIBAAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICQAAAA==.',
Xo='Xoric:BAAANQAECgQIBAAAAA==.',
Xy='Xyal:BAAANQADCgcIDQAAAA==.',
Yi='Yiago:BAAANQADCgQIBAAAAA==.',
Za='Zary:BAAANQAECgIIAgAAAA==.Zaxhpal:BAEANQAECgEIAQAAAA==.',
Zi='Zid:BAAANQAECgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgEIAQAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAANQAECgEIAQAAAA==.',
['Üb']='Übernasus:BAAANQADCgIIAgAAAA==.',
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
