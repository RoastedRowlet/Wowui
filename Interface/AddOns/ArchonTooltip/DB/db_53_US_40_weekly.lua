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

local lookup = {'Priest-Shadow','Paladin-Holy','Unknown-Unknown','Shaman-Enhancement','Warlock-Demonology','DemonHunter-Devourer','Mage-Arcane','Hunter-BeastMastery','Priest-Holy','Priest-Discipline','Paladin-Retribution',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Aberforthd:BAAANQADCgYIBgAAAA==.',
Ac='Acorn:BAAANQAECgYIEgAAAA==.',
Ad='Aditu:BAAANQAECgIIAwAAAA==.',
Ae='Aetheris:BAAANQAECgUICwAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgEIAQAAAA==.',
Ai='Airent:BAAANQADCggIEwAAAA==.',
Al='Alaestel:BAAANQAECgUICAAAAA==.Aletheia:BAAANQADCgYIBgAAAA==.Alt:BAAANQAECgIIAgAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgQIBgAAAA==.Annarcis:BAAANQADCggIEAAAAA==.Antiman:BAAANQADCgYICwAAAA==.Anäster:BAABNQAECoEZAAIBAAcJcRFQGQDUAQABAAcJcRFQGQDUAQAAAA==.',
Ap='Aplcyder:BAAANQAECgUICAAAAA==.Apocryphea:BAAANQADCgMIAwAAAA==.',
Ar='Arachnid:BAAANQAECgQICgAAAA==.Aradalon:BAABNQAECoEWAAICAAcJZiKYFAC7AgACAAcJZiKYFAC7AgAAAA==.Aratyn:BAAANQADCggICwAAAA==.',
As='Astranacht:BAAANQAECgUICQAAAA==.',
Au='Auntjemimma:BAAANQADCggICAABNQAECgUICgADAAAAAA==.',
Ba='Backhawk:BAAANQAECgEIAQAAAA==.Baerrn:BAAANQAECgIIAgAAAA==.Baricia:BAAANQAECgYIDgAAAA==.Barrin:BAAANQAECgMIBAAAAA==.Bawnchu:BAAANQADCgMIBQAAAA==.',
Be='Beardad:BAAANQADCgcIBwAAAA==.Beastmaster:BAAANQAECgYIDwAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQADCgUIBQAAAA==.Bentlymage:BAAANQAECgYICgAAAA==.',
Bi='Bissafiyah:BAACNQAFFIEJAAIEAAUJTRtWAADvAQAEAAUJTRtWAADvAQA1AAQKgSAAAgQACQnMJC4BAJgDAAQACQnMJC4BAJgDAAAA.Bittertea:BAAANQAECgEIAQAAAA==.',
Bl='Blakdeath:BAAANQAECgIIAgAAAA==.Bloodgon:BAAANQADCgYIBwAAAA==.',
Bo='Bobthedemon:BAAANQAECgEIAQAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQADCggIGgAAAA==.',
Br='Brayne:BAAANQADCgYIBgAAAA==.Brewsome:BAAANQAECgUICQAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAAANQAECgQIBwAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgQIBwADAAAAAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgQIBAAAAA==.',
Ca='Calbee:BAAANQADCgEIAQAAAA==.Candorite:BAAANQAECgIIAgAAAA==.Capita:BAAANQAECgMIAwAAAA==.Carsinegan:BAAANQADCggIFQAAAA==.Cassica:BAAANQAECgYIEAAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Chillylilly:BAAANQAECgQICQAAAA==.Chummie:BAAANQAECgUIBQAAAA==.',
Ci='Ciandoril:BAAANQADCgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIDQABNQADCgMIAwADAAAAAA==.',
Cr='Crimsondeath:BAAANQADCggIGgAAAA==.Crylecks:BAAANQADCgUICAAAAA==.',
Cy='Cylu:BAAANQADCggICwAAAA==.Cyprus:BAAANQADCggICwAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAAANQAECgYIDQAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAAANQAECgQIBgAAAA==.Dairydemon:BAAANQAECgYIDwAAAA==.Damageus:BAAANQAECgUIDAAAAA==.Damworg:BAAANQAECgEIAQAAAA==.Dar:BAAANQAECgYIDQAAAA==.Darcside:BAAANQADCggIGgAAAA==.Darkburtus:BAAANQAECgUICgAAAA==.Darkfeatherr:BAAANQADCggIFAAAAA==.Darkxwraith:BAAANQAECgUICgAAAA==.Datsombeech:BAAANQAECgQIBgAAAA==.',
De='Defhammer:BAAANQABCgUIBQAAAA==.Deàdly:BAAANQADCgUICgAAAA==.',
Dh='Dhaynk:BAAANQAECgYIEAAAAA==.',
Di='Dianoia:BAAANQADCggIDQABNQAECgkJHgAFAOQgAA==.',
Do='Docoo:BAAANQAECgQIBQAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAECgkJGgAGANAeAA==.Drewserk:BAAANQAECgQICgAAAA==.Driten:BAAANQAECgUIDAAAAA==.Drsaltyballz:BAAANQAECgIIAgAAAA==.Drspoon:BAAANQAECgQIBQAAAA==.Drugpala:BAAANQAECgEIAgAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgIIAgAAAA==.',
Du='Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAAANQADCggIDQAAAA==.Duffunha:BAAANQAECgQICAAAAA==.',
Dy='Dyre:BAAANQADCgYICwAAAA==.Dyslexic:BAAANQADCgUIBQABNQAFFAIIAgADAAAAAA==.Dyspepsia:BAAANQAFFAIIAgAAAA==.',
['Dõ']='Dõngus:BAAANQADCgYIBgAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgUICAAAAA==.',
El='Eleaornu:BAAANQAECgQICQAAAA==.Elimee:BAABNQAECoEgAAIHAAkJHiOzDQB3AwAHAAkJHiOzDQB3AwAAAA==.Elvenbane:BAAANQAECgEIAQAAAA==.',
Em='Emart:BAAANQADCgYICwAAAA==.',
Er='Erayna:BAAANQAECgEIAQAAAA==.',
Es='Essence:BAAANQADCgUIBQAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwADAAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQADCgYICwAAAA==.Fayedra:BAAANQAECgIIAgAAAA==.',
Fe='Feenii:BAAANQAECgQICAAAAA==.',
Fi='Fizzlelich:BAAANQADCgUICgAAAA==.',
Fo='Foxdeer:BAAANQADCggIFQAAAA==.Foxxmccloud:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.',
Fu='Fungies:BAAANQAECgUICwAAAA==.Furybest:BAAANQADCgUIBQAAAA==.Furyrage:BAAANQADCgMIAwAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgMIBAAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIAwAAAA==.Giramar:BAAANQADCggIDQAAAA==.',
Go='Gojo:BAAANQAECgEIAwAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCgUICgAAAA==.Grimrox:BAAANQAECgQIBQAAAA==.Grombo:BAAANQADCgYIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQADCgYICAAAAA==.Hardlyevoker:BAAANQADCgEIAQABNQAECggIFgACALcaAA==.',
He='Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUIBwAAAA==.Hexbox:BAAANQAECgQICAAAAA==.',
Hi='Himawarí:BAAANQAECgIIAgAAAA==.',
Ho='Hoffmin:BAAANQAECgYIEQAAAA==.Holemeister:BAAANQAECgUIDAAAAA==.Holyamin:BAAANQADCgYICwAAAA==.Holymann:BAAANQADCgcIFwAAAA==.Holyschnikey:BAAANQAECgUIBgAAAA==.Holyz:BAAANQAECgQIBQAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQADCgYIBgABNQAECgYIDQADAAAAAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBQAAAA==.',
['Hí']='Hílthaen:BAAANQAECgQIBgAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAAANQAECgUICQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Ja='Jahan:BAAANQAECgYIEAABNQADCgYIBgADAAAAAA==.Jamie:BAAANQAECgYICgABNQAFFAMIBQAFAL0gAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAAANQAECgYIDwAAAA==.Jerith:BAAANQAECgUIBwAAAA==.Jessilyn:BAAANQADCgMIBQAAAA==.',
Ji='Jigari:BAAANQADCgcICAAAAA==.',
Jo='Jord:BAAANQADCgUIBQAAAA==.',
Ju='Jubellina:BAAANQAECgUIDAAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.Jud:BAAANQAECgMIBQAAAA==.',
['Jà']='Jàzz:BAAANQADCgYIEAAAAA==.',
Ka='Kaelora:BAAANQADCgYIBgAAAA==.Kaerei:BAAANQADCgQIBAAAAA==.Kaleb:BAEANQAECggIEAAAAA==.Kalferno:BAAANQADCggIGgAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Kh='Khallock:BAAANQAECgQIBQAAAA==.',
Ki='Kiemen:BAAANQAECgUIBQAAAA==.Killko:BAAANQAECgYIDAAAAA==.Kirisen:BAAANQAECgEIAQAAAA==.',
Kn='Knardan:BAAANQAECgQIBgAAAA==.',
Ko='Kotanx:BAAANQADCgcIBwAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQAECgIIAgAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAAANQAECgYIDQAAAA==.Lasalghoul:BAAANQAECgEIAQAAAA==.Lassyn:BAAANQABCgMIBQAAAA==.',
Le='Legend:BAAANQAECggIDQAAAA==.Len:BAAANQAECgYIDQAAAA==.Leoñidas:BAAANQAECgEIAQAAAA==.',
Li='Lian:BAAANQADCggIDgAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAAANQAECgUICwAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQADCgcIEQAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lilmoo:BAAANQAECgEIAQAAAA==.Lilpump:BAAANQAECgMIBAABNQAECgQIBQADAAAAAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQADCgEIAQABNQAECgQICAADAAAAAA==.Linkmônk:BAAANQADCgcICgABNQAECgQICAADAAAAAA==.',
Lo='Lodise:BAAANQAECgMIBAAAAA==.Lorzz:BAAANQAECgYIEgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAAANQAECgQICAAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgUICQADAAAAAA==.Lurim:BAAANQAECgQIBwAAAA==.Lushy:BAAANQAECgQIBQAAAA==.',
Ly='Lylindara:BAAANQAECgIIAgAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAAANQAECgUICgABNQADCgMIAwADAAAAAA==.Mageskin:BAAANQAECgEIAQAAAA==.Maladaptive:BAAANQADCgUIBwAAAA==.Manerva:BAAANQADCgYICwAAAA==.Maximumhonk:BAAANQAECgMIBAAAAA==.Maxonoa:BAAANQADCggICwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAAANQADCgQIBAAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAAANQAECgIIAwAAAA==.Mercus:BAAANQAECgIIAwAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.',
Mi='Mindplague:BAAANQAECgQIBgAAAA==.Minipincin:BAAANQADCgUIDQAAAA==.Minmzey:BAAANQAECgIIAgAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQADCggICgABNQADCggICwADAAAAAA==.',
Mo='Moggle:BAAANQAECgEIAQAAAA==.Mondazi:BAAANQAECgUICgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgUIBQAAAA==.Mozarta:BAAANQABCggIBwAAAA==.',
Ms='Msmanalow:BAAANQADCgEIAQABNQADCggICwADAAAAAA==.',
My='Mycen:BAAANQAECgMIAwAAAA==.Myeyesburn:BAAANQAECgMIAwAAAA==.',
['Má']='Málaketh:BAAANQADCgcIDgAAAA==.',
Na='Nardena:BAAANQADCgYIEAAAAA==.Narz:BAAANQAECgQICwAAAA==.',
Ne='Necronomikon:BAAANQADCgUIBgAAAA==.Neromoo:BAAANQAECgUICQABNQADCgEIAQADAAAAAA==.Neruphuyt:BAAANQAECgQICAAAAA==.',
Ni='Niath:BAAANQADCgcIFQAAAA==.Nightheal:BAAANQABCgMIAwABNQAECgQIBQADAAAAAA==.Nightsniper:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgQICQAAAA==.Notpillows:BAAANQADCgcICQAAAA==.',
Ny='Nyxelle:BAAANQAECgEIAQAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgQIBQADAAAAAA==.',
Ok='Okioni:BAAANQAECgQIBAAAAA==.',
Ol='Olgon:BAAANQAECgYIEAAAAA==.',
Op='Oprhawinfury:BAAANQAECgQIBAAAAA==.',
Or='Orgodemir:BAAANQAECgIIAgAAAA==.Orhamin:BAAANQADCgYICwAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQADCgQIAgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAAANQAECgcIEgAAAA==.Parsie:BAAANQADCgcIBwAAAA==.Pathibas:BAAANQADCggIDQABNQAECgQICAADAAAAAA==.Pattycakes:BAAANQAECgQICQAAAA==.',
Ph='Pherocious:BAAANQADCgYIBwAAAA==.',
Pi='Pixeleen:BAABNQAECoEcAAIIAAkJMyNXBgBqAwAIAAkJMyNXBgBqAwAAAA==.',
Pl='Plexy:BAABNQAECoEaAAMJAAgJUCMEDQDqAgAJAAgJlCIEDQDqAgAKAAcJ8hk+BAARAgAAAA==.',
Po='Pokitz:BAAANQAECgEIAQAAAA==.',
Pr='Primordinor:BAAANQAECgUIBgAAAA==.Probnotalive:BAAANQAECgQIBQAAAA==.Probnoturmom:BAAANQAECgYIDAAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECgQIBwADAAAAAA==.',
Ra='Rakan:BAAANQAECgUIBwAAAA==.Rallick:BAAANQAECgYIDwAAAA==.Ranì:BAAANQAECgYIDQAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcICAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgIIAgAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAAANQAECgUICgAAAA==.Retiredaggro:BAAANQAECgEIAQAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQADCgcIDwAAAA==.',
Rh='Rhaella:BAAANQABCgIIAgAAAA==.',
Ri='Ricflairion:BAAANQAECgUIBQAAAA==.',
Ro='Rodcet:BAAANQAECgYIDQAAAA==.Roflbubble:BAAANQAECgQIBgAAAA==.Rognan:BAAANQADCgMIAwAAAA==.Roku:BAAANQADCgYICwAAAA==.Ronkin:BAAANQADCgYICwAAAA==.Rookgue:BAAANQAECgYIDwAAAA==.Rookoker:BAAANQAECgIIAgAAAA==.Rorygazer:BAAANQAECgEIAQAAAA==.Rosmerta:BAAANQADCgEIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQADCgYIDgABNQAECgQIBQADAAAAAA==.Rossperot:BAAANQAECgYIEQAAAA==.',
Ry='Ryk:BAAANQADCggICAAAAA==.',
Sa='Saelara:BAAANQAECgEIAQAAAA==.Sairal:BAAANQAECgQICAAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAABNQAECoEcAAILAAkJ/BpnHAC/AgALAAkJ/BpnHAC/AgAAAA==.Sawlty:BAAANQAECgQIBAAAAA==.Saynar:BAAANQAECgQICAAAAA==.',
Sc='Scattered:BAAANQAECgQIBAAAAA==.Schecter:BAAANQAECgUIDwAAAA==.Scooti:BAAANQADCggICAABNQAECgQICAADAAAAAA==.',
Se='Seba:BAAANQAECgYIDgAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQAECgIIAgAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQAECgMIAwAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQADCggIGgAAAA==.Shinma:BAAANQADCggIGgAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgQIBAAAAA==.Shrubbery:BAAANQAECgQIBAAAAA==.Shymary:BAAANQADCggIFwAAAA==.',
Si='Siete:BAAANQADCgEIAQAAAA==.Silëx:BAAANQAECgIIAwAAAA==.Sindiz:BAAANQAECgEIAQAAAA==.Siouxiesioux:BAAANQADCgQIBAAAAA==.',
Sk='Skoot:BAAANQAECgQICAAAAA==.',
Sl='Slugondeez:BAABNQAECoEWAAICAAgJtxo/GQCVAgACAAgJtxo/GQCVAgAAAA==.',
Sm='Smitefist:BAAANQADCgIIAgABNQADCgYIBgADAAAAAA==.',
Sn='Snkyturtle:BAAANQAECgcIDwAAAA==.Snuzzle:BAAANQAECgQIBAAAAA==.',
So='Sourmash:BAAANQABCgIIAgAAAA==.',
Sp='Spaghet:BAAANQAECgQIBgAAAA==.Spillthetea:BAAANQADCggICQABNQAECgEIAQADAAAAAA==.Sploot:BAAANQAECgMIAwAAAA==.',
Sr='Srasjet:BAAANQADCgYICwAAAA==.',
Ss='Ssarmandok:BAAANQADCgUIBQAAAA==.',
St='Stabytha:BAAANQADCggIEgAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECgYICgAAAA==.Stealthed:BAAANQADCggIEAAAAA==.Stormcall:BAAANQADCggIGAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAAANQAECgIIAgAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQADCgUICgAAAA==.',
Ta='Taliden:BAAANQADCgcIDAAAAA==.Taraylda:BAAANQAECgEIAQAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYIBgAAAA==.Teronfiggy:BAAANQAECgIIAgAAAA==.',
Tf='Tfirs:BAAANQAECgQIBwAAAA==.',
Th='Thehealczar:BAAANQADCgUIBQABNQAECgQIBQADAAAAAA==.Theokoles:BAAANQADCgIIAgABNQADCgYIBgADAAAAAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYIDQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQAECgIIAgAAAA==.Treecloud:BAAANQAECgQICAAAAA==.Treferimore:BAAANQADCggIGAAAAA==.Trevian:BAAANQAECgIIAgAAAA==.',
Tu='Tuluxxi:BAAANQAECgQICAAAAA==.Tutter:BAAANQADCgcIFAAAAA==.',
Tw='Twopumpchump:BAAANQAECgUIBgAAAA==.',
Ug='Uglymancer:BAAANQAECgIIAgAAAA==.',
Uj='Ujimas:BAAANQAECgIIAwAAAA==.',
Ut='Uthodne:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.',
Va='Vampireshade:BAAANQAECgQIBgAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAAANQAECgQICAAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgEIAQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQADCggIFQAAAA==.Venatra:BAAANQADCgQIBAAAAA==.Veritus:BAAANQAECgQICQAAAA==.',
Vi='Violette:BAAANQAECgMIAwAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAAANQAECgQICAAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgEIAQAAAA==.Wakancer:BAAANQAECgQIBwAAAA==.Wakataclysm:BAAANQAECgEIAwAAAA==.Walnut:BAAANQADCgEIAQABNQAECgYIEgADAAAAAA==.Warchylde:BAAANQABCggIEgAAAA==.Warolderoy:BAAANQAECgQICAAAAA==.',
Wo='Woker:BAAANQADCggIDQABNQAECgQICAADAAAAAA==.Woogie:BAAANQAECgQIBwAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgUIBQADAAAAAA==.',
Xe='Xenna:BAAANQAECgUICgAAAA==.Xeq:BAAANQADCggIGQAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgEIAgAAAA==.Yewko:BAAANQAECgYIDQAAAA==.',
Yg='Yggdralith:BAAANQAECgQIBwAAAQ==.',
Yu='Yunohealme:BAAANQAECgMIBQAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAAANQAECgcIEgAAAA==.Zandre:BAAANQAECgQIBQAAAA==.Zarkir:BAAANQAECgYIEgAAAA==.',
Ze='Zelily:BAAANQAECgQIBgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAAANQAECgQIBQABNQAECgYICwADAAAAAA==.Zhiana:BAAANQAECgIIAgAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgQIBwADAAAAAA==.',
Zu='Zulrich:BAAANQAECgQIBQAAAA==.',
Zv='Zvirax:BAAANQADCgYIEAAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYIDQAAAA==.',
['Ðo']='Ðolm:BAAANQADCgMIAwABNQAECgEIAQADAAAAAA==.',
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
