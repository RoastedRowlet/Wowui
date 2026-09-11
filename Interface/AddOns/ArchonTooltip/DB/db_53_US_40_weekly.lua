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

local lookup = {'Shaman-Enhancement','Unknown-Unknown','Warlock-Demonology',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Aberforthd:BAAANQADCgYIBgAAAA==.',
Ac='Acorn:BAAANQAECgYIDAAAAA==.',
Ad='Aditu:BAAANQAECgEIAQAAAA==.',
Ae='Aetheris:BAAANQAECgUIBwAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQADCggIEAAAAA==.',
Ai='Airent:BAAANQADCgcIEgAAAA==.',
Al='Alaestel:BAAANQAECgIIAwAAAA==.Aletheia:BAAANQADCgYIBgAAAA==.Alt:BAAANQAECgIIAgAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgIIAgAAAA==.Annarcis:BAAANQADCgcIDAAAAA==.Antiman:BAAANQADCgYICQAAAA==.Anäster:BAAANQAECgYIEAAAAA==.',
Ap='Aplcyder:BAAANQAECgQIBAAAAA==.Apocryphea:BAAANQADCgMIAwAAAA==.',
Ar='Arachnid:BAAANQAECgQICAAAAA==.Aradalon:BAAANQAECgYIDgAAAA==.Aratyn:BAAANQADCggICwAAAA==.',
As='Astranacht:BAAANQAECgQIBAAAAA==.',
Ba='Backhawk:BAAANQADCgQIBAAAAA==.Baerrn:BAAANQADCgMIAwAAAA==.Baricia:BAAANQAECgUICAAAAA==.Barrin:BAAANQAECgEIAQAAAA==.Bawnchu:BAAANQADCgIIAgAAAA==.',
Be='Beastmaster:BAAANQAECgYICgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Bentlymage:BAAANQAECgMIBAAAAA==.',
Bi='Bissafiyah:BAABNQAECoEdAAIBAAkJxiR+AAC7AwABAAkJxiR+AAC7AwAAAA==.Bittertea:BAAANQADCgcIDwAAAA==.',
Bl='Blakdeath:BAAANQADCggICwAAAA==.Bloodgon:BAAANQADCgYIBwAAAA==.',
Bo='Bobthedemon:BAAANQAECgEIAQAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQADCgcIEgAAAA==.',
Br='Brayne:BAAANQADCgYIBgAAAA==.Brewsome:BAAANQAECgQIBAAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAAANQAECgIIAwAAAA==.',
Bu='Bubleherth:BAAANQADCgcIEAAAAA==.',
Ca='Calbee:BAAANQADCgEIAQAAAA==.Candorite:BAAANQADCggICwAAAA==.Capita:BAAANQADCggIEgAAAA==.Carsinegan:BAAANQADCggIDQAAAA==.Cassica:BAAANQAECgUICgAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Chillylilly:BAAANQAECgQIBQAAAA==.Chummie:BAAANQADCgMIAwABNQAECgMIAwACAAAAAA==.',
Ci='Ciandoril:BAAANQADCgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIDQABNQADCgMIAwACAAAAAA==.',
Cr='Crimsondeath:BAAANQADCgcIEgAAAA==.Crylecks:BAAANQADCgUICAAAAA==.',
Cy='Cylu:BAAANQADCgMIAwABNQADCgUICwACAAAAAA==.Cyprus:BAAANQADCggICwAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAAANQAECgUIBwAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAAANQAECgIIAgAAAA==.Dairydemon:BAAANQAECgYICQAAAA==.Damageus:BAAANQAECgQIBwAAAA==.Damworg:BAAANQADCggIEAAAAA==.Dar:BAAANQAECgUIBwAAAA==.Darcside:BAAANQADCgcIEgAAAA==.Darkburtus:BAAANQAECgQIBQAAAA==.Darkfeatherr:BAAANQADCgcIDAAAAA==.Darkxwraith:BAAANQAECgQIBQAAAA==.Datsombeech:BAAANQAECgIIAgAAAA==.',
De='Deàdly:BAAANQADCgUICgAAAA==.',
Dh='Dhaynk:BAAANQAECgQIBQAAAA==.',
Di='Dianoia:BAAANQADCggIDQABNQAECgkJFQADANQgAA==.',
Do='Docoo:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Dogmeat:BAAANQABCgQIBAAAAA==.Dominates:BAAANQADCgMIAwAAAA==.',
Dr='Dreu:BAAANQADCgMIAgAAAA==.Drewserk:BAAANQAECgQIBgAAAA==.Driten:BAAANQAECgMIBQAAAA==.Drsaltyballz:BAAANQAECgIIAgAAAA==.Drspoon:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Drugpala:BAAANQAECgEIAgAAAA==.Drumuss:BAAANQAECgMIBAAAAA==.',
Ds='Dsancho:BAAANQAECgEIAQAAAA==.',
Du='Dudley:BAAANQAECgEIAQAAAA==.Duffun:BAAANQADCgUIBQAAAA==.Duffunha:BAAANQAECgMIBAAAAA==.',
Dy='Dyre:BAAANQADCgYICQAAAA==.Dyslexic:BAAANQADCgUIAwABNQAECgcIDQACAAAAAA==.Dyspepsia:BAAANQAECgcIDQAAAA==.',
['Dõ']='Dõngus:BAAANQADCgYIBgAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgIIAwAAAA==.',
Ei='Eirenn:BAAANQADCggIAwAAAA==.',
El='Eleaornu:BAAANQAECgQIBQAAAA==.Elimee:BAAANQAECgcIEAAAAA==.Elvenbane:BAAANQADCggIEAAAAA==.',
Em='Emart:BAAANQADCgYICQAAAA==.',
Er='Erayna:BAAANQAECgEIAQAAAA==.',
Es='Essence:BAAANQABCgIIAgAAAA==.',
Et='Etherious:BAAANQADCgUICwAAAA==.',
Fa='Falconclaw:BAAANQADCggIGQAAAA==.Falkensnoman:BAAANQADCgYICQAAAA==.Fayedra:BAAANQADCggICwAAAA==.',
Fe='Feenii:BAAANQAECgMIBAAAAA==.',
Fi='Fizzlelich:BAAANQADCgQIBgAAAA==.',
Fo='Foxdeer:BAAANQADCggIFQAAAA==.Foxxmccloud:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.',
Fu='Fungies:BAAANQAECgQIBgAAAA==.Furyrage:BAAANQADCgMIAwAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgMIBAAAAA==.',
Gi='Gimiltockel:BAAANQABCgIIAwAAAA==.Giramar:BAAANQADCggIDQAAAA==.',
Go='Gojo:BAAANQAECgEIAwAAAA==.Goteem:BAAANQAECgIIAgAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCgUICgAAAA==.Grimrox:BAAANQAECgEIAQAAAA==.Grombo:BAAANQADCgYIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQADCgUIBwAAAA==.',
He='Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgQIBQAAAA==.Hexbox:BAAANQADCgUIBQAAAA==.',
Hi='Himawarí:BAAANQADCggICwAAAA==.',
Ho='Hoffmin:BAAANQAECgYICwAAAA==.Holemeister:BAAANQAECgQIBwAAAA==.Holyamin:BAAANQADCgYICQAAAA==.Holymann:BAAANQADCgcIEAAAAA==.Holyschnikey:BAAANQAECgEIAQAAAA==.Holyz:BAAANQAECgEIAQAAAA==.Horgable:BAAANQADCgEIAQAAAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.',
['Hè']='Hèimdall:BAAANQAECgMIAwAAAA==.',
['Hí']='Hílthaen:BAAANQAECgIIAgAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAAANQAECgQIBAAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Ja='Jahan:BAAANQAECgYICgABNQADCgYIBgACAAAAAA==.Jamie:BAAANQAECgYIBgABNQAFFAIIAwACAAAAAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAAANQAECgYICgAAAA==.Jerith:BAAANQAECgQIBgAAAA==.Jessilyn:BAAANQADCgIIAgAAAA==.',
Jo='Jord:BAAANQADCgUIBQAAAA==.',
Ju='Jubellina:BAAANQAECgUICAAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.Jud:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCgUICgAAAA==.',
Ka='Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAEANQAECggICQAAAA==.Kalferno:BAAANQADCgcIEgAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Kh='Khallock:BAAANQADCggIEQAAAA==.',
Ki='Killko:BAAANQAECgQIBgAAAA==.Kirisen:BAAANQAECgEIAQAAAA==.',
Kn='Knardan:BAAANQAECgIIAgAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQADCggICwAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAAANQAECgUIBwAAAA==.Lasalghoul:BAAANQAECgEIAQAAAA==.Lassyn:BAAANQABCgMIBQAAAA==.',
Le='Legend:BAAANQAECggIDAAAAA==.Len:BAAANQAECgUIBwAAAA==.Leoñidas:BAAANQADCgcIDQAAAA==.',
Li='Lian:BAAANQADCgYICQAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAAANQAECgQIBgAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQADCgYIDwAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lilmoo:BAAANQADCgYICwAAAA==.Lilpump:BAAANQAECgEIAQAAAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkmônk:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.',
Lo='Lodise:BAAANQAECgEIAQAAAA==.Lorzz:BAAANQAECgYIDAAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAAANQAECgMIBAAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.Lurim:BAAANQAECgIIAwAAAA==.Lushy:BAAANQAECgEIAQAAAA==.',
Ly='Lylindara:BAAANQADCgUIBQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Mageofdeath:BAAANQAECgQIBQABNQADCgMIAwACAAAAAA==.Maladaptive:BAAANQADCgIIAgAAAA==.Manerva:BAAANQADCgUIBQAAAA==.Maximumhonk:BAAANQAECgEIAQAAAA==.Maxonoa:BAAANQADCgcICgAAAA==.Maxximos:BAAANQADCgYIBgAAAA==.',
Me='Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAAANQAECgEIAQAAAA==.Mercus:BAAANQAECgEIAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.',
Mi='Mindplague:BAAANQAECgIIAgAAAA==.Minipincin:BAAANQADCgQICAAAAA==.Minmzey:BAAANQADCggIDQAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQADCggICgABNQADCggICwACAAAAAA==.',
Mo='Moggle:BAAANQADCggIDgAAAA==.Mondazi:BAAANQAECgQIBgAAAA==.Morfy:BAAANQABCgQIBAAAAA==.Morgzim:BAAANQADCgUIBQAAAA==.Mozarta:BAAANQABCgYIAgAAAA==.',
Ms='Msmanalow:BAAANQADCgEIAQABNQADCggICwACAAAAAA==.',
My='Myeyesburn:BAAANQADCgQIBAAAAA==.',
['Má']='Málaketh:BAAANQADCgYIBwAAAA==.',
Na='Nardena:BAAANQADCgUICgAAAA==.Narz:BAAANQAECgQIBgAAAA==.',
Ne='Necronomikon:BAAANQADCgUIBgAAAA==.Neromoo:BAAANQAECgMIBAAAAA==.Neruphuyt:BAAANQAECgMIBAAAAA==.',
Ni='Niath:BAAANQADCgYIDgAAAA==.Nightheal:BAAANQABCgMIAwABNQAECgEIAQACAAAAAA==.Nightsniper:BAAANQAECgEIAQAAAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgQIBQAAAA==.Notpillows:BAAANQADCgIIAgAAAA==.',
Ny='Nyxelle:BAAANQAECgEIAQAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.',
Ok='Okioni:BAAANQADCgMIAwAAAA==.',
Ol='Olgon:BAAANQAECgYICgAAAA==.',
Op='Oprhawinfury:BAAANQADCgcIDgAAAA==.',
Or='Orgodemir:BAAANQADCggICwAAAA==.Orhamin:BAAANQADCgUIBQAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Paigor:BAAANQABCgIIAgAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAAANQAECgcICwAAAA==.Pathibas:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Pattycakes:BAAANQAECgQIBQAAAA==.',
Ph='Pherocious:BAAANQADCgYIBwAAAA==.',
Pi='Pixeleen:BAAANQAECggIEAAAAA==.',
Pl='Plexy:BAAANQAECgcIEAAAAA==.',
Po='Pokitz:BAAANQADCggIDAAAAA==.',
Pr='Primordinor:BAAANQAECgEIAQAAAA==.Probnotalive:BAAANQAECgEIAQAAAA==.Probnoturmom:BAAANQAECgYIBgAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECgIIAwACAAAAAA==.',
Ra='Rakan:BAAANQAECgIIAgAAAA==.Rallick:BAAANQAECgUICQAAAA==.Ranì:BAAANQAECgUIBwAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgEIAQAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQADCggICgAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCgUIBQAAAA==.Rendwee:BAAANQAECgQIBQAAAA==.Retiredaggro:BAAANQADCgcIDQAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQADCgcIDwAAAA==.',
Rh='Rhaella:BAAANQABCgEIAQAAAA==.',
Ri='Ricflairion:BAAANQADCgcIEQAAAA==.',
Ro='Rodcet:BAAANQAECgUIBwAAAA==.Roflbubble:BAAANQAECgIIAgAAAA==.Rognan:BAAANQADCgIIAgAAAA==.Roku:BAAANQADCgUIBQAAAA==.Ronkin:BAAANQADCgUIBQAAAA==.Rookgue:BAAANQAECgYICQAAAA==.Rookoker:BAAANQAECgIIAgAAAA==.Rorygazer:BAAANQADCggIEAAAAA==.Rosmerta:BAAANQADCgEIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQADCgYICgAAAA==.Rossperot:BAAANQAECgYICwAAAA==.',
Sa='Saelara:BAAANQAECgEIAQAAAA==.Sairal:BAAANQAECgQIBAAAAA==.Saltytuesday:BAAANQADCgMIAwAAAA==.Samgee:BAAANQAFFAEIAQAAAA==.Sawlty:BAAANQADCgYIBgAAAA==.Saynar:BAAANQAECgMIBAAAAA==.',
Sc='Schecter:BAAANQAECgUICQAAAA==.',
Se='Seba:BAAANQAECgYICAAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQADCggICwAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQAECgEIAQAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQADCgcIEgAAAA==.Shinma:BAAANQADCgcIEgAAAA==.Shootermcgee:BAAANQADCgcIDwAAAA==.Showtootsies:BAAANQADCgQIBAAAAA==.Shrubbery:BAAANQADCgcIDAAAAA==.Shymary:BAAANQADCgcIDwAAAA==.',
Si='Siete:BAAANQADCgEIAQAAAA==.Silëx:BAAANQAECgEIAQAAAA==.Sindiz:BAAANQADCgcIEAAAAA==.Siouxiesioux:BAAANQADCgQIBAAAAA==.',
Sk='Skoot:BAAANQAECgQICAAAAA==.',
Sl='Slugondeez:BAAANQAECggIDgAAAA==.',
Sm='Smitefist:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.',
Sn='Snkyturtle:BAAANQAECgYICgAAAA==.Snuzzle:BAAANQADCggIDgAAAA==.',
So='Sourmash:BAAANQABCgIIAgAAAA==.',
Sp='Spaghet:BAAANQAECgIIAgAAAA==.Spillthetea:BAAANQADCggICQABNQADCgcIDwACAAAAAA==.Sploot:BAAANQAECgMIAwAAAA==.',
Sr='Srasjet:BAAANQADCgYICQAAAA==.',
Ss='Ssarmandok:BAAANQADCgUIBQAAAA==.',
St='Stabytha:BAAANQADCggICwAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECgQIBAAAAA==.Stealthed:BAAANQADCgcICAAAAA==.Stormcall:BAAANQADCgcIEAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.',
Sw='Swiss:BAAANQADCggICwAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQADCgUICAAAAA==.',
Ta='Taliden:BAAANQADCgYICwAAAA==.Taraylda:BAAANQADCggIEAAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYIBgAAAA==.Teronfiggy:BAAANQADCggIFAAAAA==.',
Tf='Tfirs:BAAANQAECgQIBwAAAA==.',
Th='Thehealczar:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Theokoles:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYICQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.',
To='Toospookie:BAAANQADCgYICwAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQADCggIEgAAAA==.Treecloud:BAAANQAECgMIBAAAAA==.Treferimore:BAAANQADCgcIEAAAAA==.Trevian:BAAANQADCggICwAAAA==.',
Tu='Tuluxxi:BAAANQAECgMIBAAAAA==.Tutter:BAAANQADCgYIDQAAAA==.',
Tw='Twopumpchump:BAAANQAECgEIAQAAAA==.',
Ug='Uglymancer:BAAANQADCggICwAAAA==.',
Uj='Ujimas:BAAANQAECgEIAQAAAA==.',
Ut='Uthodne:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.',
Va='Vampireshade:BAAANQAECgIIAgAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAAANQAECgQIBAAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQADCgYIBgAAAA==.',
Vb='Vbull:BAAANQADCgQIBAAAAA==.',
Ve='Velissari:BAAANQADCgcIDQAAAA==.Venatra:BAAANQADCgQIBAAAAA==.Veritus:BAAANQAECgQIBQAAAA==.',
Vi='Violette:BAAANQADCgcIEQAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAAANQAECgMIBAAAAA==.Voidstriker:BAAANQADCgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgEIAQAAAA==.Wakancer:BAAANQAECgMIAwAAAA==.Wakataclysm:BAAANQAECgEIAgAAAA==.Walnut:BAAANQADCgEIAQABNQAECgYIDAACAAAAAA==.Warchylde:BAAANQABCgYICgAAAA==.Warolderoy:BAAANQAECgMIBAAAAA==.',
Wo='Woker:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Woogie:BAAANQAECgQIBgAAAA==.',
Wu='Wummie:BAAANQAECgMIAwAAAA==.',
Xe='Xenna:BAAANQAECgIIAgAAAA==.Xeq:BAAANQADCggIFgAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgEIAQAAAA==.Yewko:BAAANQAECgUIBwAAAA==.',
Yg='Yggdralith:BAAANQAECgMIAwAAAQ==.',
Yu='Yunohealme:BAAANQAECgEIAgAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Za='Zaen:BAAANQAECgYIDAAAAA==.Zandre:BAAANQAECgEIAQAAAA==.Zarkir:BAAANQAECgYIDAAAAA==.',
Ze='Zelily:BAAANQAECgIIAgAAAA==.Zenarri:BAAANQADCgYIBgAAAA==.',
Zh='Zharvakko:BAAANQAECgIIAgABNQAECgYICgACAAAAAA==.Zhiana:BAAANQAECgIIAgAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgIIAwACAAAAAA==.',
Zu='Zulrich:BAAANQAECgQIBQAAAA==.',
Zv='Zvirax:BAAANQADCgUICgAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYICAAAAA==.',
['Ðo']='Ðolm:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.',
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
