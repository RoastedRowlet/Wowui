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

local lookup = {'Unknown-Unknown','Mage-Arcane','Monk-Mistweaver','Priest-Holy',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abcdeath:BAAANQABCgYIBgAAAA==.',
Ad='Adanac:BAAANQAECgIIAgAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Ae='Aered:BAAANQADCgUIBgAAAA==.',
Ah='Ahira:BAAANQAECgUICQAAAA==.',
Ai='Airro:BAAANQADCgIIAgAAAA==.Aishe:BAAANQADCggIFwAAAA==.',
Ak='Akashã:BAAANQAECgYIDwAAAA==.Akuria:BAAANQAECgUICwAAAA==.',
Al='Alacía:BAAANQADCgMIBAAAAA==.Alahna:BAAANQADCgcIFgAAAA==.',
Am='Amaarth:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.',
An='Anies:BAAANQAECgQIBgAAAA==.',
Aq='Aquarian:BAAANQADCgcIDQAAAA==.',
Ar='Arthaz:BAAANQADCgUIBQAAAA==.Artëmîs:BAAANQAECgIIAwAAAA==.',
As='Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Aurna:BAAANQAECgUICQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babysneeze:BAAANQADCgYIBQAAAA==.Badbev:BAAANQADCgMIBAABNQADCgYICwABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAABNQAECoEbAAICAAkJrx4sJQD9AgACAAkJrx4sJQD9AgAAAA==.Beltryne:BAAANQADCggIDQABNQAECgkJGwACAK8eAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAAANQAECgMIAwAAAA==.Beroldin:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bevar:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.Bevell:BAAANQADCgQIAwABNQADCgYICwABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAAANQAECgUIBwAAAA==.Blkrend:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.',
Bo='Bonney:BAAANQAECgMIBAAAAA==.Bonzai:BAAANQAECgQIBAAAAA==.',
Br='Bradycam:BAAANQAECgQICAAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.',
Ca='Cantpalyhard:BAAANQADCgMIBQABNQAECgQICAABAAAAAA==.Casella:BAAANQAECgYIDgAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDAAAAA==.',
Cl='Cleth:BAAANQAECgQIBgAAAA==.',
Co='Corax:BAAANQAECgQIBgAAAA==.',
Cu='Cunumi:BAAANQADCgEIAQAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Damachi:BAAANQAECgEIAQAAAA==.Danji:BAAANQAECgQIBAAAAA==.Darkasuna:BAAANQADCgcICgAAAA==.Darmorae:BAAANQAECgIIAgAAAA==.Dashii:BAAANQAECgEIAQABNQAECggIBgABAAAAAA==.Datewoo:BAAANQAECgIIAgAAAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQIBAAAAA==.Demonish:BAAANQAECgUICQAAAA==.Demontotem:BAAANQAECgMIAwAAAA==.',
Di='Dillinquent:BAAANQADCgUIBgAAAA==.',
Dr='Dracdemonica:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Dracfu:BAAANQAECgMIAwABNQAECgcIEAABAAAAAA==.Dracklock:BAAANQADCggICAABNQADCggICQABAAAAAA==.Drackpally:BAAANQADCggICQAAAA==.Dracshot:BAAANQAECgcIEAAAAA==.Draffel:BAAANQAECgEIAQAAAA==.Dreamfire:BAAANQADCgYIBgAAAA==.Dräc:BAAANQADCggIEAABNQAECgcIEAABAAAAAA==.',
Du='Dukstorm:BAAANQADCggICAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Dunzer:BAAANQAECgQICAAAAA==.',
Ed='Edithpoothe:BAAANQAECgQIBAAAAA==.',
El='Electricks:BAAANQAECgQICAAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgEIAQAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAAANQAECgYICwABNQAECggIBgABAAAAAA==.',
Er='Eradoria:BAAANQADCggIFgAAAA==.Ermgoob:BAAANQAECgIIAgAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAAANQAECgMIAwAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgQIBQABAAAAAA==.',
Fa='Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQABCgIIAwAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.',
Fo='Foxyboo:BAAANQAECgQICAAAAA==.',
Fr='Freakpeachh:BAAANQAECgQIBQAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAAANQAECgUICAAAAA==.Gope:BAAANQAECgcIDgAAAA==.',
Gr='Gromiir:BAAANQAECgQICAAAAA==.',
['Gä']='Gärrus:BAAANQAECgIIAgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Hellkat:BAAANQADCgIIAgAAAA==.',
Hi='Higarosa:BAAANQADCgQIBAAAAA==.Highbull:BAAANQAECggIAQABNQAECggIBgABAAAAAA==.',
Ho='Holiblade:BAAANQAECgQIBwAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Hooligun:BAAANQADCggIEwAAAA==.',
Hy='Hypérian:BAAANQAECgIIAgAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQADCgUIBQAAAA==.',
Ic='Icesikle:BAAANQAECgQICAAAAA==.',
Ig='Igglybuff:BAAANQADCgcIBwAAAA==.',
Ij='Ijustshotyou:BAAANQAECgUIDwAAAA==.',
Il='Illusiongun:BAAANQADCgYIBgABNQAECggIEgABAAAAAA==.',
In='Indistera:BAAANQABCgcIBwAAAA==.Insaniac:BAAANQADCggICwAAAA==.Intervention:BAAANQABCgIIBAAAAA==.',
Iz='Izumo:BAAANQADCggIDQAAAA==.',
Ja='Jatswamdi:BAAANQAECgcIEAAAAA==.',
Jn='Jnymango:BAAANQAECgQIBwAAAA==.',
Jo='Johnnysham:BAAANQADCggICgABNQAECgQIBwABAAAAAA==.Jollakeratu:BAAANQAECgQIBgAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQADCgUICAAAAA==.Jusmissiner:BAAANQAECgUIBQAAAA==.Juut:BAAANQAECgYIBgAAAA==.',
Ke='Keelhorn:BAAANQAECgYIDwAAAA==.Kerubiel:BAAANQAECgQIBAAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEANQAECgYICQAAAA==.Kintssiralop:BAAANQADCgUIBgAAAA==.Kirio:BAAANQADCgUIBwAAAA==.Kitsunenohi:BAAANQAECgQIBgAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgQIBQAAAA==.',
Ks='Ksandra:BAAANQADCgcIFgAAAA==.Ksares:BAAANQAECggIEAAAAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQIBAAAAA==.',
La='Laeflockxo:BAAANQAECgQIBAAAAA==.Laefnia:BAAANQAECgYIEQAAAA==.Laraydra:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Lastofgoobs:BAAANQADCgIIAgAAAA==.',
Li='Lildarleena:BAAANQADCgUICAAAAA==.Lilis:BAAANQADCgcIFQAAAA==.Lilithe:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Littlebev:BAAANQADCgYICwAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
Ma='Maachen:BAAANQADCgUIBQAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQADCggIDgABNQADCgEIAQABAAAAAA==.Maluin:BAAANQADCgUICQABNQAECgQIBwABAAAAAA==.Mawea:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAAANQAECgIIAgAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECoEVAAICAAcJ2RG0gQDGAQACAAcJ2RG0gQDGAQAAAA==.Mesohungry:BAAANQAECgQIBwAAAA==.',
Mi='Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.',
Mo='Moobáca:BAAANQAECggIBgAAAA==.Moostradamas:BAAANQADCggIGgAAAA==.Morcilla:BAAANQAECgIIAgAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Naturegoob:BAAANQAECgUICwAAAA==.Naughtynurse:BAAANQAECgQICAAAAA==.',
Ne='Neuma:BAAANQADCgcIDQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAAANQAECgUICgAAAA==.',
No='Nostromo:BAAANQAECgcIDwAAAA==.',
Ob='Obiejuan:BAAANQAECgcIEwAAAA==.',
Od='Odbc:BAAANQAECgYIDAAAAA==.Oddball:BAAANQAECgYIDgAAAA==.',
Or='Orthiaa:BAAANQADCgcIFAAAAA==.',
Pa='Paintrain:BAAANQAECgUICAAAAA==.',
Pe='Peso:BAAANQAECgMIAQABNQAECggIBgABAAAAAA==.Pez:BAAANQAECgYIDwAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Polyhedroll:BAABNQAECoEeAAIDAAkJsx9ZAwArAwADAAkJsx9ZAwArAwABNQADCgYIBgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEIAgAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Ra='Radge:BAAANQAECgcIDQAAAA==.Rainne:BAAANQADCgMIAwAAAA==.Ralanar:BAAANQAECgQIDQABNQAECgUICQABAAAAAA==.Raljah:BAAANQAECgQIBwAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAAANQAECgYIDwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQADCgQIBgAAAA==.',
Ro='Royalchaos:BAAANQADCgMIAwABNQAECgcIEAABAAAAAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAAANQAECgYICAAAAA==.',
Sa='Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAAANQAECgcIEwAAAA==.Saric:BAAANQAECgQICAAAAA==.',
Se='Selinedion:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Serdav:BAAANQADCgYIBgAAAA==.',
Sh='Shak:BAAANQADCgYIBgAAAA==.Shalai:BAAANQAECgQIBwAAAA==.Shilóh:BAAANQADCgYIBgAAAA==.Shyandrial:BAAANQADCgYIEgAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Skychades:BAAANQAECgMIAwAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQADCgcIBwAAAA==.',
Sp='Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAAANQAECgUICgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAAANQAECgQIBQAAAA==.',
St='Stileto:BAAANQAECgQIAwABNQAECggIBgABAAAAAA==.Stoneydracco:BAAANQAECgQICQAAAA==.',
Su='Sumtinwng:BAAANQAECgEIAQAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Supervicious:BAAANQAECgYIBgAAAA==.',
Sy='Sylenne:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Sylur:BAAANQAECgQIBQAAAA==.',
Ta='Tahren:BAABNQAECoEfAAIEAAkJYCJABwAyAwAEAAkJYCJABwAyAwAAAA==.Tahshock:BAAANQADCgYICwABNQAECgkJHwAEAGAiAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAAANQAECgMIBgAAAA==.',
Te='Temporalize:BAAANQADCggICgAAAA==.',
Th='Thatonemonk:BAAANQADCgQIBAAAAA==.Thistelbear:BAAANQAECgIIAwAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYIBwAAAA==.Thraun:BAAANQAECgEIAgAAAA==.Thunderdin:BAAANQAECgQIAwABNQAECgcICwABAAAAAA==.',
Ti='Tirrian:BAAANQADCggICAAAAA==.',
To='Toki:BAAANQADCgcIBwAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQADCgcIBwABAAAAAA==.',
Tw='Twamsack:BAAANQABCgQIBAAAAA==.Tweak:BAAANQAECgYIBAABNQAECggIBgABAAAAAA==.',
Um='Umbrarogue:BAAANQAECgUIBQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAAANQAECgQICAAAAA==.',
Ve='Velien:BAAANQAECgYICwAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQADCgcIFQAAAA==.Viscerai:BAAANQAECgMIAwAAAA==.Vite:BAAANQAECgIIAgAAAA==.',
Vo='Vonmiller:BAAANQAECgMIBgAAAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Yu='Yurie:BAAANQADCggICAAAAA==.',
Zi='Zipp:BAAANQABCgEIAQAAAA==.',
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
