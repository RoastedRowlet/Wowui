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
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Aberforthd:BAAANQADCgYIBgAAAA==.',
Ac='Acorn:BAAANQAECgQIBgAAAA==.',
Ad='Aditu:BAAANQADCgcIDAAAAA==.',
Ae='Aetheris:BAAANQAECgIIAgAAAA==.',
Ag='Agasonex:BAAANQADCgQIAgAAAA==.',
Ah='Ahziz:BAAANQADCgYICAAAAA==.',
Ai='Airent:BAAANQADCgYICwAAAA==.',
Al='Alaestel:BAAANQAECgIIAgAAAA==.Aletheia:BAAANQADCgUIBQAAAA==.Alt:BAAANQADCgYIBgAAAA==.',
An='Angina:BAAANQADCgIIAgAAAA==.Annarcis:BAAANQADCgUIBQAAAA==.Antiman:BAAANQADCgUIAwAAAA==.Anäster:BAAANQAECgYICgAAAA==.',
Ap='Aplcyder:BAAANQADCggIDwAAAA==.',
Ar='Arachnid:BAAANQAECgQIBAAAAA==.Aradalon:BAAANQAECgUICAAAAA==.Aratyn:BAAANQADCgYIBgAAAA==.',
As='Astranacht:BAAANQADCggIDwAAAA==.',
Ba='Backhawk:BAAANQADCgMIAwAAAA==.Baerrn:BAAANQADCgMIAwAAAA==.Baricia:BAAANQAECgMIAwAAAA==.Barrin:BAAANQADCgYICgAAAA==.Bawnchu:BAAANQABCgQIBAAAAA==.',
Be='Beastmaster:BAAANQAECgQIBAAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Bentlymage:BAAANQAECgIIAwAAAA==.',
Bi='Bissafiyah:BAAANQAFFAEIAQAAAA==.Bittertea:BAAANQADCgYICAAAAA==.',
Bl='Blakdeath:BAAANQADCgYIBgAAAA==.',
Bo='Bobthedemon:BAAANQADCgYIBgAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQADCgYICwAAAA==.',
Br='Brayne:BAAANQADCgEIAQAAAA==.Brewsome:BAAANQADCggIDwAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAAANQAECgEIAQAAAA==.',
Bu='Bubleherth:BAAANQADCgYICQAAAA==.',
Ca='Calbee:BAAANQADCgEIAQAAAA==.Candorite:BAAANQADCgYIBgAAAA==.Capita:BAAANQADCgYICwAAAA==.Carsinegan:BAAANQADCgYICwAAAA==.Cassica:BAAANQAECgQIBQAAAA==.Catskin:BAAANQADCgMIAwAAAA==.Causticminx:BAAANQABCgEIAQAAAA==.',
Ch='Chillylilly:BAAANQAECgEIAQAAAA==.',
Ci='Ciandoril:BAAANQADCgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCgUIBQABNQADCgMIAwABAAAAAA==.',
Cr='Crimsondeath:BAAANQADCgYICwAAAA==.Crylecks:BAAANQADCgUICAAAAA==.',
Cy='Cylu:BAAANQADCgMIAwABNQADCgUIBgABAAAAAA==.Cyprus:BAAANQADCggICAABNQADCggICAABAAAAAA==.',
Da='Daender:BAAANQAECgIIAgAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Dairydemon:BAAANQAECgMIAwAAAA==.Damageus:BAAANQAECgMIAwAAAA==.Damworg:BAAANQADCgYICAAAAA==.Dar:BAAANQAECgIIAgAAAA==.Darcside:BAAANQADCgYICwAAAA==.Darkburtus:BAAANQADCgUICAAAAA==.Darkfeatherr:BAAANQADCgUIBQAAAA==.Darkxwraith:BAAANQADCgUICAAAAA==.Datsombeech:BAAANQADCggICAAAAA==.',
De='Deàdly:BAAANQADCgUICAAAAA==.',
Dh='Dhaynk:BAAANQAECgQIBAAAAA==.',
Di='Dianoia:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.',
Do='Docoo:BAAANQADCgcIDQAAAA==.',
Dr='Drewserk:BAAANQAECgEIAgAAAA==.Driten:BAAANQAECgIIAgAAAA==.Drsaltyballz:BAAANQADCgcIDQAAAA==.Drspoon:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Drugpala:BAAANQAECgEIAgAAAA==.Drumuss:BAAANQAECgIIAgAAAA==.',
Ds='Dsancho:BAAANQADCgYIBgAAAA==.',
Du='Dudley:BAAANQADCgcIDQAAAA==.Duffunha:BAAANQAECgEIAQAAAA==.',
Dy='Dyre:BAAANQADCgUIAwAAAA==.Dyslexic:BAAANQADCgUIAwABNQAECgcIBgABAAAAAA==.Dyspepsia:BAAANQAECgcIBgAAAA==.',
['Dõ']='Dõngus:BAAANQADCgYIBgAAAA==.',
Ed='Edelgard:BAAANQABCgIIAgAAAA==.Edie:BAAANQADCgIIAwAAAA==.',
El='Eleaornu:BAAANQAECgEIAQAAAA==.Elimee:BAAANQAECgQICAAAAA==.Elvenbane:BAAANQADCgYICAAAAA==.',
Em='Emart:BAAANQADCgUIAwAAAA==.',
Er='Erayna:BAAANQAECgEIAQAAAA==.',
Et='Etherious:BAAANQADCgUIBgAAAA==.',
Fa='Falconclaw:BAAANQADCggIEAAAAA==.Falkensnoman:BAAANQADCgUIAwAAAA==.Fayedra:BAAANQADCgYIBgAAAA==.',
Fe='Feenii:BAAANQAECgEIAQAAAA==.',
Fi='Fizzlelich:BAAANQADCgQIBAAAAA==.',
Fo='Foxdeer:BAAANQADCggIDgAAAA==.Foxxmccloud:BAAANQADCgIIAgABNQADCggIDQABAAAAAA==.',
Fu='Fungies:BAAANQAECgIIAgAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgMIAwAAAA==.',
Gi='Giramar:BAAANQADCgUIBQAAAA==.',
Go='Gojo:BAAANQAECgEIAQAAAA==.Goteem:BAAANQADCggICAAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grantaire:BAAANQADCgUICAAAAA==.Grimrox:BAAANQADCggICAAAAA==.Grombo:BAAANQADCgYIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQADCgUIBwAAAA==.',
He='Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgEIAQAAAA==.',
Hi='Himawarí:BAAANQADCgYIBgAAAA==.',
Ho='Hoffmin:BAAANQAECgUIBQAAAA==.Holemeister:BAAANQAECgMIAwAAAA==.Holyamin:BAAANQADCgUIAwAAAA==.Holymann:BAAANQADCgYICQAAAA==.Holyschnikey:BAAANQADCgYICwAAAA==.Holyz:BAAANQADCggIDgAAAA==.Horgable:BAAANQADCgEIAQAAAA==.',
Hu='Hugginz:BAAANQADCgYIDAAAAA==.',
['Hè']='Hèimdall:BAAANQADCgcIBwAAAA==.',
['Hí']='Hílthaen:BAAANQADCggIDgAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.',
Il='Illy:BAAANQADCggIDwAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Ja='Jahan:BAAANQAECgQIBAABNQADCgUIBQABAAAAAA==.Jamie:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Je='Jegra:BAAANQAECgQIBAAAAA==.Jerith:BAAANQAECgMIAwAAAA==.',
Ju='Jubellina:BAAANQAECgMIAwAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCgQIBQAAAA==.',
Ka='Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAAANQAECgEIAQAAAA==.Kalferno:BAAANQADCgYICwAAAA==.Kayotica:BAAANQADCgYICwAAAA==.',
Kh='Khallock:BAAANQADCgYICQAAAA==.',
Ki='Killko:BAAANQAECgIIAgAAAA==.Kirisen:BAAANQADCgcIDAAAAA==.',
Kn='Knardan:BAAANQADCgEIAQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQADCgYIBgAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQADCgMIAwAAAA==.Lanadiel:BAAANQAECgIIAgAAAA==.Lasalghoul:BAAANQADCgcIDAAAAA==.',
Le='Legend:BAAANQAECggIBwAAAA==.Len:BAAANQAECgEIAgAAAA==.Leoñidas:BAAANQADCgcIBwAAAA==.',
Li='Lian:BAAANQADCgQIBgAAAA==.Lianse:BAAANQADCgYIBgAAAA==.Liliara:BAAANQAECgIIAgAAAA==.Lillymae:BAAANQADCgYIDAAAAA==.Lillytae:BAAANQADCgEIAQAAAA==.Lilmoo:BAAANQADCgUIBQAAAA==.Lilpump:BAAANQAECgEIAQAAAA==.',
Lo='Lodise:BAAANQADCgYICwAAAA==.Lorzz:BAAANQAECgQIBgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAAANQAECgEIAQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Lurim:BAAANQAECgEIAQAAAA==.Lushy:BAAANQADCgYICQAAAA==.',
Ly='Lylinette:BAAANQADCgcIBwAAAA==.',
Ma='Maladaptive:BAAANQADCgIIAgAAAA==.Manerva:BAAANQADCgQIBAAAAA==.Maximumhonk:BAAANQADCgYICwAAAA==.Maxonoa:BAAANQADCgYICQAAAA==.',
Me='Mendelia:BAAANQADCgcIDAAAAA==.Mercus:BAAANQADCgcIDAAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.',
Mi='Mindplague:BAAANQADCgYIBwAAAA==.Minipincin:BAAANQADCgIIBAAAAA==.Minmzey:BAAANQADCgUIBQAAAA==.Missfire:BAAANQADCggICAAAAA==.',
Mo='Moggle:BAAANQADCgYIBgAAAA==.Mondazi:BAAANQAECgIIAgAAAA==.Morfy:BAAANQABCgQIBAAAAA==.',
My='Myeyesburn:BAAANQADCgQIBAAAAA==.',
['Má']='Málaketh:BAAANQADCgEIAQAAAA==.',
Na='Nardena:BAAANQADCgQIBQAAAA==.Narz:BAAANQAECgIIAgAAAA==.',
Ne='Neromoo:BAAANQAECgEIAQAAAA==.Neruphuyt:BAAANQAECgEIAQAAAA==.',
Ni='Niath:BAAANQADCgYICAAAAA==.Nightsniper:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgEIAQAAAA==.Notpillows:BAAANQADCgIIAgAAAA==.',
Ok='Okioni:BAAANQADCgMIAwAAAA==.',
Ol='Olgon:BAAANQAECgQIBAAAAA==.',
Op='Oprhawinfury:BAAANQADCgcIDgAAAA==.',
Or='Orgodemir:BAAANQADCgYIBgAAAA==.',
Pa='Paigor:BAAANQABCgIIAgAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAAANQAECgQIBAAAAA==.Pattycakes:BAAANQAECgEIAQAAAA==.',
Pi='Pixeleen:BAAANQAECgUICAAAAA==.',
Pl='Plexy:BAAANQAECgYICQAAAA==.',
Po='Pokitz:BAAANQADCgQIBAAAAA==.',
Pr='Primordinor:BAAANQADCgYICwAAAA==.Probnotalive:BAAANQADCgYIBgAAAA==.Probnoturmom:BAAANQADCgUICAAAAA==.',
Ra='Rakan:BAAANQAECgIIAgAAAA==.Rallick:BAAANQAECgQIBAAAAA==.Ranì:BAAANQAECgIIAgAAAA==.Rathger:BAAANQADCgUIBwAAAA==.Ratmilk:BAAANQADCggIEAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQADCgIIAgAAAA==.',
Re='Redek:BAAANQADCgQIBAAAAA==.Rendwee:BAAANQAECgEIAQAAAA==.Retiredaggro:BAAANQADCgcIBwAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Rewolf:BAAANQADCgYICAAAAA==.',
Ri='Ricflairion:BAAANQADCgYICwAAAA==.',
Ro='Rodcet:BAAANQAECgIIAgAAAA==.Roflbubble:BAAANQADCggIDgAAAA==.Rognan:BAAANQADCgIIAgAAAA==.Ronkin:BAAANQADCgQIBAAAAA==.Rookgue:BAAANQAECgMIAwAAAA==.Rookoker:BAAANQAECgIIAgAAAA==.Rorygazer:BAAANQADCgYICAAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQADCgUIBQABNQADCgcICAABAAAAAA==.Rossperot:BAAANQAECgQIBQAAAA==.',
Sa='Saelara:BAAANQADCgUIBQAAAA==.Sairal:BAAANQADCggIDgAAAA==.Saltytuesday:BAAANQADCgMIAwAAAA==.Samgee:BAAANQAFFAEIAQAAAA==.Saynar:BAAANQAECgEIAQAAAA==.',
Sc='Schecter:BAAANQAECgQIBAAAAA==.',
Se='Seba:BAAANQAECgIIAgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQADCgYIBgAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQADCgYIDQAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQADCgYICwAAAA==.Shinma:BAAANQADCgYICwAAAA==.Shootermcgee:BAAANQADCgYICAAAAA==.Showtootsies:BAAANQADCgMIAwAAAA==.Shrubbery:BAAANQADCgcIDAAAAA==.Shymary:BAAANQADCgYICwAAAA==.',
Si='Silëx:BAAANQADCgcIDAAAAA==.Sindiz:BAAANQADCgYICQAAAA==.Siouxiesioux:BAAANQADCgMIAwAAAA==.',
Sk='Skoot:BAAANQAECgQIBAAAAA==.',
Sl='Slugondeez:BAAANQAECgYICAAAAA==.',
Sm='Smitefist:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Sn='Snkyturtle:BAAANQAECgQIBAAAAA==.Snuzzle:BAAANQADCggIDgAAAA==.',
Sp='Spaghet:BAAANQADCgcIDQAAAA==.Spillthetea:BAAANQADCggICAABNQADCgYICAABAAAAAA==.Sploot:BAAANQADCgQIAwAAAA==.',
Sr='Srasjet:BAAANQADCgUIAwAAAA==.',
Ss='Ssarmandok:BAAANQADCgQIBAAAAA==.',
St='Stabytha:BAAANQADCgMIAwAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQADCgcIDQAAAA==.Stealthed:BAAANQADCgEIAQAAAA==.Stormcall:BAAANQADCgUICQAAAA==.',
Sw='Swiss:BAAANQADCgYIBgAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQADCgUIAwAAAA==.',
Ta='Taliden:BAAANQADCgUIBQAAAA==.Taraylda:BAAANQADCgYICAAAAA==.',
Te='Teronfiggy:BAAANQADCgcIDAAAAA==.',
Tf='Tfirs:BAAANQAECgMIAwAAAA==.',
Th='Thehealczar:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Theokoles:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Thorly:BAAANQADCgUIBQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.',
To='Toospookie:BAAANQADCgUIBQAAAA==.Totem:BAAANQADCgMIAwAAAA==.',
Tr='Tramplip:BAAANQADCgYICgAAAA==.Treecloud:BAAANQAECgEIAQAAAA==.Treferimore:BAAANQADCgYICQAAAA==.Trevian:BAAANQADCgYIBgAAAA==.',
Tu='Tuluxxi:BAAANQAECgEIAQAAAA==.Tutter:BAAANQADCgUIBwAAAA==.',
Tw='Twopumpchump:BAAANQADCgYICwAAAA==.',
Ug='Uglymancer:BAAANQADCgYIBgAAAA==.',
Uj='Ujimas:BAAANQADCgcIDAAAAA==.',
Ut='Uthodne:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Va='Vampireshade:BAAANQADCggIDgAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQADCgYIBgAAAA==.',
Vb='Vbull:BAAANQADCgMIAwAAAA==.',
Ve='Velissari:BAAANQADCgYIBgAAAA==.Venatra:BAAANQADCgMIAwAAAA==.Veritus:BAAANQAECgEIAQAAAA==.',
Vi='Violette:BAAANQADCgYICgAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQADCgcIDQAAAA==.Wakataclysm:BAAANQAECgEIAgAAAA==.Warolderoy:BAAANQAECgEIAQAAAA==.',
Wo='Woogie:BAAANQAECgIIAgAAAA==.',
Wu='Wummie:BAAANQAECgMIAwAAAA==.',
Xe='Xenna:BAAANQADCgUIBQAAAA==.Xeq:BAAANQADCggIDgAAAA==.',
Ye='Yeoman:BAAANQADCgYICQAAAA==.Yewko:BAAANQAECgIIAgAAAA==.',
Yg='Yggdralith:BAAANQADCggIDgAAAQ==.',
Yu='Yunohealme:BAAANQAECgEIAQAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
Za='Zaen:BAAANQAECgQIBgAAAA==.Zandre:BAAANQADCgcIDQAAAA==.Zarkir:BAAANQAECgQIBgAAAA==.',
Ze='Zelily:BAAANQADCggICAAAAA==.',
Zh='Zharvakko:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Zhiana:BAAANQADCgcICQAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Zu='Zulrich:BAAANQAECgEIAQAAAA==.',
Zv='Zvirax:BAAANQADCgQIBQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgEIAQAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðolm:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
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
