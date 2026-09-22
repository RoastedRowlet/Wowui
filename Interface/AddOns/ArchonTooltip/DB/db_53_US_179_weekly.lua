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

local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Blood','Mage-Frost','Monk-Brewmaster','Hunter-BeastMastery','Shaman-Restoration','DemonHunter-Havoc','Paladin-Protection','Druid-Feral','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Monk-Mistweaver','Warrior-Arms','Priest-Holy','Warlock-Affliction','Warlock-Demonology',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abcdeath:BAAANQABCgYJBgAAAA==.',
Ad='Adanac:BAAANQAECgQJBgAAAA==.Adhenar:BAAANQAECgMJAwAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgIIAgABNQAECgQJBgABAAAAAA==.',
Ae='Aered:BAAANQADCgcJDAAAAA==.',
Ah='Ahira:BAAANQAECgYIDwAAAA==.',
Ai='Airro:BAAANQADCgIIAgAAAA==.Aishe:BAAANQADCggJFwAAAA==.',
Ak='Akashã:BAABNQAECoEZAAICAAgK7R1xRwC1AgACAAgK7R1xRwC1AgAAAA==.Akuria:BAAANQAECgUIEAAAAA==.',
Al='Alacía:BAAANQADCggJDAAAAA==.Alahna:BAAANQAECgIJAgAAAA==.',
Am='Amaarth:BAAANQADCgcIBwABNQAECggJGQADAGUhAA==.',
An='Anies:BAAANQAECgQIBgAAAA==.',
Aq='Aquarian:BAAANQADCgcIDQAAAA==.',
Ar='Arthaz:BAAANQADCgUICgAAAA==.Artëmîs:BAAANQAECgQIBQAAAA==.',
As='Asherrylie:BAAANQADCgIJAgAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Aurna:BAAANQAECgUICQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBAAAAA==.Badbev:BAAANQADCgMIBAABNQADCgYICwABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAABNQAECoEkAAMCAAkKwCLLEAB5AwACAAkKwCLLEAB5AwAEAAEKEByfJgBTAAAAAA==.Beltryne:BAAANQAECgUJBQABNQAECgkJJAACAMAiAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAAANQAECgMIAwAAAA==.Beroldin:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Bevar:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.Bevell:BAAANQADCgQIAwABNQADCgYICwABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAAANQAECgUICwAAAA==.Blkrend:BAAANQADCggICAABNQAECggIHQACAIslAA==.',
Bo='Bonney:BAAANQAECgMIBQAAAA==.Bonzai:BAAANQAECgUJBgAAAA==.',
Br='Bradycam:BAAANQAECgUJDQAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.',
Ca='Cantpalyhard:BAAANQADCgMJBgABNQAECgUJDwABAAAAAA==.Casella:BAABNQAECoEXAAIFAAgKKSMQAwApAwAFAAgKKSMQAwApAwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQADCgUJBQABNQAECgYIEAABAAAAAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDAAAAA==.',
Cl='Cleth:BAAANQAECgUICwAAAA==.Clouzot:BAAANQADCgIJAgAAAA==.',
Co='Corax:BAAANQAECgUICwAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.',
Cu='Cunumi:BAAANQADCgEIAQAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Damachi:BAAANQAECgYIBwAAAA==.Danji:BAAANQAECgQIBQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAAANQAECgQIBgAAAA==.Dashii:BAAANQAECgIJAgABNQAECggICgABAAAAAA==.Datewoo:BAAANQAECgIJAgAAAA==.',
De='Deathlock:BAAANQAECggJAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Demonish:BAAANQAECgUICgAAAA==.Demontotem:BAAANQAECgMJBQAAAA==.',
Di='Dillinquent:BAAANQADCgcJDAAAAA==.',
Dr='Dracdemonica:BAAANQADCgUIBQABNQAECggIGwAGAMwRAA==.Dracfu:BAAANQAECgMJAwABNQAECggIGwAGAMwRAA==.Dracklock:BAAANQAECgEIAQAAAA==.Dracshot:BAABNQAECoEbAAIGAAgKzBHoPwA4AgAGAAgKzBHoPwA4AgAAAA==.Dracslock:BAAANQAECgEIAQABNQAECggIGwAGAMwRAA==.Draffel:BAAANQAECgMIBAAAAA==.Dreamfire:BAAANQADCgYIBgAAAA==.Dräc:BAAANQADCggIFAABNQAECggIGwAGAMwRAA==.',
Du='Dukstorm:BAAANQADCggICAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Dunzer:BAAANQAECgUJDwAAAA==.',
Ed='Edithpoothe:BAAANQAECgQIBgAAAA==.',
El='Electricks:BAAANQAECgUJDQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgIIAwAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAAANQAECgYIDgABNQAECggICgABAAAAAA==.',
Er='Eradoria:BAAANQADCggIHQAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAAANQAECgYJCQAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgQJCwABAAAAAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECgMJBgABAAAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQAECgEIAQAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.',
Fo='Foxyboo:BAAANQAECgUJDwAAAA==.',
Fr='Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAAANQAECgYJDgAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECoEZAAIHAAgKBiL3EAAAAwAHAAgKBiL3EAAAAwAAAA==.Gostewpid:BAAANQADCgcIBwAAAA==.',
Gr='Gromiir:BAAANQAECgUJDQAAAA==.',
['Gä']='Gärrus:BAAANQAECgQJBgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Hellkat:BAAANQADCgMJAwAAAA==.',
Hi='Higarosa:BAAANQADCgQJBAAAAA==.Highbull:BAAANQAECggIBAABNQAECggICgABAAAAAA==.',
Ho='Holiblade:BAAANQAECgQICwAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holywhiskers:BAAANQADCgYJBgABNQAECgUJDwABAAAAAA==.Hooligun:BAAANQAECgIIAgAAAA==.',
Hy='Hypérian:BAAANQAECgIIAgAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQADCgUJBQAAAA==.',
Ic='Icesikle:BAAANQAECgQJCAAAAA==.',
Ig='Igglybuff:BAAANQAECgIJAgAAAA==.',
Ij='Ijustshotyou:BAAANQAECgUIEwABNQAECgcIEgABAAAAAA==.',
Il='Illusiongun:BAAANQADCgYJBwABNQAECgkKHwAIADMdAA==.',
In='Indistera:BAAANQABCgcIBwAAAA==.Insaniac:BAAANQADCggICwAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQADCgYJBgAAAA==.',
Ir='Ironlotss:BAAANQADCgMIAwAAAA==.',
Iz='Izumo:BAAANQADCggJDQAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECoEbAAIJAAgKgR0TCQCrAgAJAAgKgR0TCQCrAgAAAA==.',
Jn='Jnymango:BAAANQAECgUJCQAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgUJCQABAAAAAA==.Jollakeratu:BAAANQAECgUICwAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQADCgYIDQAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAAANQAECgYIDAAAAA==.',
['Jø']='Jønty:BAAANQADCgIJAgAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECoEYAAIHAAgKwQkGVwCOAQAHAAgKwQkGVwCOAQAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kerubiel:BAAANQAECgQIBQAAAA==.Kessarah:BAAANQAECgUIBQAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEANQAECgYIDAAAAA==.Kintssiralop:BAAANQADCgUJBgAAAA==.Kirio:BAAANQADCgUIBwAAAA==.Kitsunenohi:BAAANQAECgUICwAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgUJBwAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAMIBQAGAEUVAA==.',
Ks='Ksandra:BAAANQAECgEJAQAAAA==.Ksares:BAABNQAECoEZAAMKAAgKexn7BQB/AgAKAAgKexn7BQB/AgALAAMKlgk6bQCDAAAAAA==.',
Kw='Kwazii:BAAANQAECggJBgABNQAECggICgABAAAAAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQJBAAAAA==.',
['Kë']='Këvîn:BAAANQAECgMIAwAAAA==.',
La='Laeflockxo:BAAANQAECgQIBAAAAA==.Laefnia:BAAANQAECgYIEgAAAA==.Laraydra:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Lastofgoobs:BAAANQADCgYJBwAAAA==.',
Le='Leard:BAAANQAECgEJAQABNQAECgMICAABAAAAAA==.',
Li='Lichnephilim:BAAANQADCgUJBQAAAA==.Lildarleena:BAAANQADCgUICAAAAA==.Lilis:BAAANQAECgEJAQAAAA==.Lilithe:BAAANQAECgMIAwABNQAECgYJDQABAAAAAA==.Liten:BAAANQADCgIJAgAAAA==.Littlebev:BAAANQADCgYICwAAAA==.Liz:BAAANQADCgIJAgAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
Ma='Maachen:BAAANQADCgUJBQAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQAECgUJBQABNQADCgEIAQABAAAAAA==.Maluin:BAAANQADCgUICQABNQAECgQIBwABAAAAAA==.Mawea:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAAANQAECgQJBgAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECoEZAAICAAcKZxNrkgDqAQACAAcKZxNrkgDqAQAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.',
Mo='Moobáca:BAAANQAECggICgAAAA==.Moostradamas:BAAANQAECgIIAgAAAA==.Morcilla:BAAANQAECgMIAwAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Naturegoob:BAAANQAECgYIEQAAAA==.Naughtynurse:BAAANQAECgUJDQAAAA==.',
Ne='Neuma:BAAANQAECgMJAwAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAAANQAECgYIEAAAAA==.',
No='Nostromo:BAABNQAECoEZAAIMAAgKERMxFQD+AQAMAAgKERMxFQD+AQAAAA==.',
Ob='Obiejuan:BAABNQAECoEdAAINAAgKxB2KKQC4AgANAAgKxB2KKQC4AgAAAA==.',
Od='Odbc:BAAANQAECgcJEwAAAA==.Oddball:BAAANQAECgYIDwAAAA==.',
Op='Ophiron:BAAANQADCgMIAwAAAA==.',
Or='Orthiaa:BAAANQAECgIJAgAAAA==.',
Os='Osalot:BAAANQADCggICAAAAA==.',
Pa='Paintrain:BAAANQAECgUJCAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECgMJAQABNQAECggICgABAAAAAA==.Pez:BAABNQAECoEZAAIHAAgKshjtLQBFAgAHAAgKshjtLQBFAgAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Polyhedroll:BAABNQAECoEhAAIOAAkKsx/tBAAVAwAOAAkKsx/tBAAVAwABNQADCgYIBgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEJAgAAAA==.',
Ps='Psychoman:BAAANQABCgQIBAAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAAANQAECgIIAgAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Ra='Raathe:BAAANQADCgIJAgAAAA==.Radge:BAABNQAECoEWAAIPAAcKTCEiLwCuAgAPAAcKTCEiLwCuAgAAAA==.Rainne:BAAANQADCgQJBAAAAA==.Ralanar:BAAANQAECgQJDQABNQAECgUICQABAAAAAA==.Raljah:BAAANQAECgYJDQAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECoEZAAIDAAgKZSEvDQAMAwADAAgKZSEvDQAMAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQADCgQIBgAAAA==.',
Ro='Royalchaos:BAAANQADCgMIAwABNQAECggIGwAQAKodAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAAANQAECgYIDgAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECoEdAAMRAAgK7CEkAQAZAwARAAgKBiEkAQAZAwASAAUKVRj2dQBhAQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAAANQADCgYIBgABNQAECgQJBgABAAAAAA==.Serdav:BAAANQADCgYIBgAAAA==.',
Sh='Shak:BAAANQADCgYIBgAAAA==.Shalai:BAAANQAECgcIDgAAAA==.Shilóh:BAAANQADCgYIBgAAAA==.Shyandrial:BAAANQADCgYIGAAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Sksteve:BAAANQADCgYIBgAAAA==.Skychades:BAAANQAECgQIBwAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgIJAgAAAA==.',
Sp='Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAAANQAECgYIDgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAAANQAECgQJBwAAAA==.',
St='Stileto:BAAANQAECgQIBAABNQAECggICgABAAAAAA==.Stoneydracco:BAAANQAECgUJCgAAAA==.',
Su='Sumtinwng:BAAANQAECgUJBQAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Supervicious:BAAANQAECgYIDAAAAA==.',
Sy='Sylenne:BAAANQADCgcJBwABNQAECggIGQAHALIYAA==.Sylur:BAAANQAECgQJCwAAAA==.',
Ta='Tahren:BAABNQAECoEjAAIQAAkK1yJNCQA/AwAQAAkK1yJNCQA/AwAAAA==.Tahshock:BAAANQADCgYICwABNQAECgkJIwAQANciAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAAANQAECgUJCwAAAA==.',
Te='Temporalize:BAAANQADCggIDQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQADCgYJBgABAAAAAA==.Thistelbear:BAAANQAECgUICAAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIJAwAAAA==.Thunderdin:BAAANQAECgcICAAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.',
To='Toki:BAAANQADCgcIDQAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQADCgcIDQABAAAAAA==.',
Tu='Turnip:BAAANQAECgUJCAABNQAECggICgABAAAAAA==.',
Tw='Twamsack:BAAANQABCgQIBAAAAA==.Tweak:BAAANQAECgYIBQABNQAECggICgABAAAAAA==.Tweis:BAAANQADCgIJAgAAAA==.',
Um='Umbrarogue:BAAANQAECgYJCgAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAAANQAECgQICAAAAA==.',
Ve='Velien:BAAANQAECgcJEgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgEJAQAAAA==.Viscerai:BAAANQAECgYJCQAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQADCgYIBgAAAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Yu='Yurie:BAAANQADCggJCAAAAA==.',
Zi='Zipp:BAAANQABCgEIAQAAAA==.',
['Õs']='Õso:BAAANQABCgMIAwAAAA==.',
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
