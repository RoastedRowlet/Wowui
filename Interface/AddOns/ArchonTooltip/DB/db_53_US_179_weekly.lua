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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','Mage-Frost','Monk-Brewmaster','Paladin-Retribution','Hunter-BeastMastery','Paladin-Protection','Shaman-Enhancement','Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Druid-Restoration','Evoker-Preservation','Monk-Mistweaver','Warrior-Arms','Priest-Holy','Warlock-Affliction','Warlock-Demonology',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abcdeath:BAAANQABCgcICAAAAA==.',
Ad='Adanac:BAAANQAECgUICwAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgIIAgABNQAECgYIDAABAAAAAA==.',
Ae='Aered:BAAANQADCggIDQAAAA==.',
Ah='Ahira:BAABNQAECoEaAAICAAgK7BHFUgDJAQACAAgK7BHFUgDJAQAAAA==.',
Ai='Airro:BAAANQADCgIIAgAAAA==.Aishe:BAAANQADCggIGAAAAA==.',
Ak='Akashã:BAABNQAECoEgAAIDAAgKrR6NUwCxAgADAAgKrR6NUwCxAgAAAA==.Akuria:BAABNQAECoEbAAIEAAcKQxVhIgDTAQAEAAcKQxVhIgDTAQAAAA==.',
Al='Alacía:BAAANQAECgEIAQAAAA==.Alahna:BAAANQAECgQIBgAAAA==.',
Am='Amaarth:BAAANQADCgcIBwABNQAECggIIAAFADEiAA==.',
An='Anies:BAAANQAECgYIDAAAAA==.',
Aq='Aquarian:BAAANQAECgQIBAAAAA==.',
Ar='Arthaz:BAAANQAECgEIAQAAAA==.Artëmîs:BAAANQAECgQIBwAAAA==.',
As='Asherrylie:BAAANQADCgIJAgAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Aurna:BAAANQAECgUICQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgMIBAABNQADCgYICwABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAABNQAECoEtAAMDAAkKACN3FgBqAwADAAkKwCJ3FgBqAwAGAAIK5x5HHwCyAAAAAA==.Beltryne:BAAANQAECgUJBQABNQAECgkJLQADAAAjAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAAANQAECgMIAwAAAA==.Beroldin:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Bevar:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.Bevell:BAAANQADCgQIAwABNQADCgYICwABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAAANQAECgcIEgAAAA==.Blkrend:BAAANQADCggICAABNQAECgkJKgADAN8kAA==.',
Bo='Bonney:BAAANQAECgMIBgAAAA==.Bonzai:BAAANQAECgUICAAAAA==.',
Br='Bradycam:BAAANQAECgYIEwAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.Busterblader:BAAANQADCgYIBgAAAA==.',
Ca='Cantpalyhard:BAAANQAECgQIBAABNQAECgYIGAACAMoRAA==.Casella:BAABNQAECoEfAAIHAAgKIiQGAwBDAwAHAAgKIiQGAwBDAwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQADCgUIBQABNQAECgcIGAAIAJElAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDAAAAA==.',
Cl='Cleth:BAAANQAECgYIEQAAAA==.Clouzot:BAAANQADCgIJAgAAAA==.',
Co='Corax:BAAANQAECgYIEQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.',
Cu='Cunumi:BAAANQAECgQIAwAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dainichi:BAAANQABCgQIBQAAAA==.Damachi:BAAANQAECgcIDgAAAA==.Danji:BAAANQAECgQIBQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAAANQAECgYIDAAAAA==.Dashii:BAAANQAECgcICAABNQAECggIDAABAAAAAA==.Datewoo:BAAANQAECgIJAgAAAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Demonish:BAAANQAECgcIEQAAAA==.Demontotem:BAAANQAECgMJBQAAAA==.Desadeness:BAAANQADCgMIAwABNQADCgUIDgABAAAAAA==.',
Di='Dillinquent:BAAANQADCggIDQAAAA==.',
Dr='Dracdemonica:BAAANQADCgUIBQABNQAECggIIgAJAG8SAA==.Dracfu:BAAANQAECgMIAwABNQAECggIIgAJAG8SAA==.Dracklock:BAAANQAECgEIAQABNQAECggICAABAAAAAA==.Drackpally:BAAANQAECggICAAAAA==.Dracshot:BAABNQAECoEiAAIJAAgKbxJTTwAzAgAJAAgKbxJTTwAzAgAAAA==.Dracslock:BAAANQAECgQIBQABNQAECggIIgAJAG8SAA==.Draffel:BAAANQAECgUICQAAAA==.Dreamfire:BAAANQADCgYICAAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICAABAAAAAA==.Dräc:BAAANQADCggIFAABNQAECggIIgAJAG8SAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Dunzer:BAABNQAECoEYAAMKAAYKZQ8HLQAbAQAKAAYKZQ8HLQAbAQAIAAIKfQldIgFqAAAAAA==.Dunzerblaze:BAAANQAECgMIAwAAAA==.',
Ed='Edithpoothe:BAAANQAECgYIDQAAAA==.',
El='Electricks:BAABNQAECoEYAAMLAAkKHBNPEQAIAgALAAgK0hJPEQAIAgAMAAYKMxLqdgBnAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgUICAAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECoEVAAIDAAYKhwpNAQE5AQADAAYKhwpNAQE5AQABNQAECggIDAABAAAAAA==.',
Er='Eradoria:BAAANQADCggIHwAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAAANQAECgYIDgAAAA==.Evagrius:BAAANQABCgIIAgAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgYIEQABAAAAAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQAECgEIAQAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.',
Fo='Foxyboo:BAABNQAECoEYAAMCAAYKyhG6eQBHAQACAAYKyhG6eQBHAQAMAAQKYAgIuwDCAAAAAA==.',
Fr='Freak:BAAANQAECgYIBwAAAA==.Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECoEZAAIJAAgKgCH2GgD6AgAJAAgKgCH2GgD6AgAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECoEZAAICAAgKBiLFFgDsAgACAAgKBiLFFgDsAgAAAA==.Gostewpid:BAAANQADCggIDwAAAA==.',
Gr='Gromiir:BAAANQAECgYIEwAAAA==.',
['Gä']='Gärrus:BAAANQAECgQJBgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgMIAwAAAA==.Hellkat:BAAANQADCgMJAwAAAA==.',
Hi='Higarosa:BAAANQADCgQIBAAAAA==.Highbull:BAAANQAECggIBgABNQAECggIDAABAAAAAA==.',
Ho='Holiblade:BAAANQAECgUIEAAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holywhiskers:BAAANQADCggIDwABNQAECgYIHAAIADcbAA==.Hooligun:BAAANQAECgIIAwAAAA==.Hoppered:BAAANQAECgUIBQABNQAECgcIDwABAAAAAA==.',
Hy='Hypérian:BAAANQAECgMIAwAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQADCgUJBQAAAA==.',
Ic='Icesikle:BAAANQAECgQJCAAAAA==.',
Ig='Igglybuff:BAAANQAECgMIBQAAAA==.',
Ij='Ijustshotyou:BAABNQAECoEWAAMJAAYKZQ6TmABvAQAJAAYKZQ6TmABvAQANAAIK9AibeQAgAAABNQAECgkJHwAKAPgaAA==.',
Il='Illusiongun:BAAANQAECgEIAQABNQAECgkKJAAOAFsdAA==.',
In='Indistera:BAAANQABCgcIBwAAAA==.Insaniac:BAAANQADCggIEQAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQADCgcIBwAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQADCggIEwAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECoEhAAIKAAgKxR5eCgC3AgAKAAgKxR5eCgC3AgAAAA==.',
Jn='Jnymango:BAAANQAECgYIDgAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgYIDgABAAAAAA==.Jollakeratu:BAAANQAECgYIEQAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQADCgcIFAAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAAANQAECgcIEwAAAA==.',
['Jø']='Jønty:BAAANQADCgIJAgAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECoEfAAICAAgKwQlLbgBpAQACAAgKwQlLbgBpAQAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAYIDgALADsKAA==.Kerubiel:BAAANQAECgQICQAAAA==.Kessarah:BAAANQAECgcIDAAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEANQAECggIEQAAAA==.Kintssiralop:BAAANQADCgYIBwAAAA==.Kirio:BAAANQADCgUICwAAAA==.Kitsunenohi:BAAANQAECgUIEAAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgUICQAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAQICQAJALsWAA==.',
Ks='Ksandra:BAAANQAECgQIBQAAAA==.Ksares:BAABNQAECoEgAAMPAAgKRRuUBwCCAgAPAAgKRRuUBwCCAgAQAAMKlgkdfQB6AAAAAA==.',
Kw='Kwazii:BAAANQAECggIBgABNQAECggIDAABAAAAAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQIBAAAAA==.',
['Kë']='Këvîn:BAAANQAECgQIBwAAAA==.',
La='Laeflockxo:BAAANQAECgQIBAAAAA==.Laefnia:BAABNQAECoEeAAMQAAgKZhZTMQARAgAQAAgKZhZTMQARAgARAAMKJxZUPgDIAAAAAA==.Laraydra:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Lastofgoobs:BAAANQADCgYIBwAAAA==.',
Le='Leard:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgUICAAAAA==.Lilis:BAAANQAECgMIBAAAAA==.Lilithe:BAAANQAECgUIBQABNQAECgcIDwABAAAAAA==.Liten:BAAANQADCgIJAgAAAA==.Littlebev:BAAANQADCgYICwAAAA==.Liz:BAAANQADCgIJAgAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
Ma='Maachen:BAAANQADCgUIBQAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgEIAQAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQAECgUJBQABNQADCgEIAQABAAAAAA==.Maluin:BAAANQADCgYIDwABNQAECgUIDAABAAAAAA==.Mawea:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAAANQAECgYIDAAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECoEcAAIDAAcKTxWOpQDuAQADAAcKTxWOpQDuAQAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgYIDQABAAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgEIAQABNQAECgcIGgAHABwfAA==.',
Mo='Moobáca:BAAANQAECggIDAAAAA==.Moostradamas:BAAANQAECgMIBQAAAA==.Morcilla:BAAANQAECgYICQAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAAAAA==.Naturegoob:BAABNQAECoEeAAMRAAgKTh/ICwDZAgARAAgKTh/ICwDZAgAQAAEK3RPTiQBJAAAAAA==.Naughtynurse:BAAANQAECgYIEwAAAA==.',
Ne='Neuma:BAAANQAECgUICAAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECoEbAAIGAAgKHAgDDQCYAQAGAAgKHAgDDQCYAQAAAA==.',
No='Nostromo:BAABNQAECoEgAAISAAgK3RMaFwARAgASAAgK3RMaFwARAgAAAA==.',
Ny='Nyxserion:BAAANQADCggICQABNQAECgkJLQADAAAjAA==.',
Ob='Obiejuan:BAABNQAECoEkAAIIAAgKXh4cOACqAgAIAAgKXh4cOACqAgAAAA==.',
Od='Odbc:BAABNQAECoEcAAIQAAgKFhizKABSAgAQAAgKFhizKABSAgAAAA==.Oddball:BAABNQAECoEaAAIMAAgKvxxrKwCTAgAMAAgKvxxrKwCTAgAAAA==.',
Op='Ophiron:BAAANQADCgcICAAAAA==.',
Or='Orthiaa:BAAANQAECgIIAwAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUJCAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECggIAQABNQAECggIDAABAAAAAA==.Pez:BAABNQAECoEgAAICAAgK2xsILABzAgACAAgK2xsILABzAgAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAAANQAECgMIAwAAAA==.Polyhedroll:BAABNQAECoEhAAITAAkKsx8zBwD1AgATAAkKsx8zBwD1AgABNQADCgYIBgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEJAgAAAA==.',
Ps='Psychoman:BAAANQABCgQIBAAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAAANQAECgIIAgAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgEIAQAAAA==.',
Ra='Raathe:BAAANQADCgIJAgAAAA==.Radge:BAABNQAECoEZAAIUAAgKniITHgAeAwAUAAgKniITHgAeAwAAAA==.Rainjar:BAAANQAECgIIAgABNQAECgkJJAADAIEeAA==.Rainne:BAAANQADCgQJBAAAAA==.Ralanar:BAAANQAECgQJDQABNQAECgUICQABAAAAAA==.Raljah:BAAANQAECgcIDwAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECoEgAAIFAAgKMSJ3DgAXAwAFAAgKMSJ3DgAXAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQAECgUIBQAAAA==.',
Ro='Royalchaos:BAAANQADCgMIAwABNQAECggIIQAVAKodAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAABNQAECoEZAAIJAAgKbRTISQBEAgAJAAgKbRTISQBEAgAAAA==.Ryptyde:BAAANQADCggICAAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECoEkAAMWAAgKBSKUAQAGAwAWAAgKHyGUAQAGAwAXAAYKkxkybQC/AQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAAANQAECgIIAgABNQAECgUICwABAAAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECgYIDQABAAAAAA==.Serdav:BAAANQADCgYIBgAAAA==.',
Sh='Shak:BAAANQADCgYICgAAAA==.Shalai:BAAANQAECggIEwAAAA==.Shellingtun:BAAANQAECggIBwABNQAECggIDAABAAAAAA==.Shilóh:BAAANQADCgYIBgAAAA==.Shyandrial:BAAANQADCgYIGgAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Sksteve:BAAANQADCgcIBwAAAA==.Skychades:BAAANQAECgUIDAAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgMIBQAAAA==.',
Sp='Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAAANQAECgYIDwAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAAANQAECgUIDAAAAA==.',
St='Stileto:BAAANQAECgcICgABNQAECggIDAABAAAAAA==.Stoneydracco:BAAANQAECgYIEAAAAA==.',
Su='Sumtinwng:BAAANQAECgYICgAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Supervicious:BAAANQAECgcIEwAAAA==.',
Sy='Sylenne:BAAANQADCgcIBwABNQAECggIIAACANsbAA==.Sylur:BAAANQAECgYIEQAAAA==.',
Ta='Tahren:BAACNQAFFIEGAAIVAAQKyxNFDQBaAQAVAAQKyxNFDQBaAQA1AAQKgSUAAhUACQrXIuUNAC0DABUACQrXIuUNAC0DAAAA.Tahshock:BAAANQADCgYICwABNQAFFAQIBgAVAMsTAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAAANQAECgUIEAAAAA==.',
Te='Temporalize:BAAANQADCggIDQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQADCgcIBwABAAAAAA==.Thereaben:BAAANQADCgEIAQAAAA==.Thistelbear:BAAANQAECgYICQAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIJAwAAAA==.Thunderdin:BAAANQAECggIDgAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.',
To='Toki:BAAANQAECgEIAQAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.',
Tu='Turnip:BAAANQAECgcIDgABNQAECggIDAABAAAAAA==.',
Tw='Twamsack:BAAANQABCgQIBAAAAA==.Tweak:BAAANQAECgYICAABNQAECggIDAABAAAAAA==.Tweis:BAAANQADCgIJAgAAAA==.',
Um='Umbrarogue:BAAANQAECgcIEQAAAA==.',
Uw='Uwumental:BAAANQABCgcIDQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAAANQAECgQICAAAAA==.',
Ve='Velien:BAABNQAECoEcAAIIAAgKTgwcgwC8AQAIAAgKTgwcgwC8AQAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgEJAQAAAA==.Viscerai:BAAANQAECgYIDgAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQADCgYICwAAAA==.',
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
