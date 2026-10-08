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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','Mage-Frost','DemonHunter-Vengeance','Paladin-Retribution','Monk-Brewmaster','Evoker-Devastation','Warrior-Arms','DeathKnight-Frost','Hunter-BeastMastery','Paladin-Protection','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Unholy','Warlock-Affliction','Hunter-Marksmanship','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Druid-Balance','Druid-Restoration','Warrior-Fury','Evoker-Preservation','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abcdeath:BAAANQABCgcICAAAAA==.',
Ad='Adanac:BAAANQAECgUIDAABNQAECgYIBwABAAAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgIIAgABNQAECgYIEAABAAAAAA==.',
Ae='Aered:BAAANQAECgIIAgAAAA==.',
Ah='Ahira:BAABNQAECoEiAAICAAgKJxggQgAtAgACAAgKJxggQgAtAgAAAA==.',
Ai='Airro:BAAANQADCgIIAgAAAA==.Aishe:BAAANQADCggIGAAAAA==.',
Ak='Akashã:BAABNQAECoEoAAIDAAkKdx7GPAD/AgADAAkKdx7GPAD/AgAAAA==.Akuria:BAABNQAECoEjAAIEAAgKSxj4GgBOAgAEAAgKSxj4GgBOAgAAAA==.',
Al='Alacía:BAAANQAECgIIAgAAAA==.Alahna:BAAANQAECgcICwAAAA==.Allmightx:BAAANQAECgQIBAAAAA==.',
Am='Amaarth:BAAANQADCgcIBwABNQAECgkJKAAFAKohAA==.',
An='Anies:BAAANQAECgcIDgAAAA==.',
Aq='Aquarian:BAAANQAECgQIBQAAAA==.',
Ar='Arthaz:BAAANQAECgEIAQAAAA==.Artëmîs:BAAANQAECgUICwAAAA==.',
As='Asherrylie:BAAANQADCgQIBgAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Aurna:BAAANQAECgYICgAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAABNQAECoE2AAMDAAkKnyP8GABqAwADAAkKXyP8GABqAwAGAAMKdR8gGQAGAQAAAA==.Beltryne:BAAANQAECgUIBQABNQAECgkJNgADAJ8jAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAAANQAECgUICAAAAA==.Beroldin:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Bevar:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Bevell:BAAANQADCgQIAwABNQAECgEIAQABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECoEWAAIHAAgKfxJ1DQC3AQAHAAgKfxJ1DQC3AQAAAA==.Blkrend:BAAANQADCggICAABNQAECgkJMAADAPskAA==.',
Bo='Bonney:BAAANQAECgMIBgAAAA==.Bonzai:BAAANQAECgUICAAAAA==.',
Br='Bradycam:BAABNQAECoEdAAIIAAgKGh7rRACgAgAIAAgKGh7rRACgAgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.Busterblader:BAAANQADCgcICQAAAA==.',
Ca='Cantpalyhard:BAAANQAECgUICQABNQAECggIIAACAKgWAA==.Casella:BAABNQAECoEmAAIJAAgKIiSYAwA8AwAJAAgKIiSYAwA8AwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQADCgUIBQABNQAECggIHwAIAGolAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDAAAAA==.',
Ci='Cierdwyn:BAAANQADCgEIAQAAAA==.Cinthara:BAAANQAECgEIAQAAAA==.',
Cl='Cleth:BAABNQAECoEcAAIIAAgKThpGXgBSAgAIAAgKThpGXgBSAgAAAA==.Clouzot:BAAANQADCgQIBgAAAA==.',
Co='Corax:BAABNQAECoEeAAIKAAgKOQ55FQDTAQAKAAgKOQ55FQDTAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAMIBQALAG4NAA==.',
Cu='Cunumi:BAAANQAECgYICAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dainichi:BAAANQABCgQIBQAAAA==.Damachi:BAABNQAECoEYAAIMAAgKZBSNLAADAgAMAAgKZBSNLAADAgAAAA==.Danji:BAAANQAECgYICwAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAAANQAECgYIDQAAAA==.Dashii:BAAANQAECggICQABNQAECggIEgABAAAAAA==.Datewoo:BAAANQAECgYICAAAAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Deef:BAAANQADCgQIBAAAAA==.Demonish:BAABNQAECoEXAAILAAkKEg3QegAFAgALAAkKEg3QegAFAgAAAA==.Demontotem:BAAANQAECgYICwAAAA==.Desadeness:BAAANQADCgMIAwABNQADCgUIDgABAAAAAA==.',
Di='Dillinquent:BAAANQAECgMIAwAAAA==.',
Dr='Dracdemonica:BAAANQADCgUIBQABNQAECggIKAANAG8SAA==.Dracfu:BAAANQAECgQIBwABNQAECggIKAANAG8SAA==.Dracklock:BAAANQAECgEIAQABNQAECggICQABAAAAAA==.Drackpally:BAAANQAECggICQAAAA==.Dracserion:BAAANQADCgYIBgABNQAECgkJNgADAJ8jAA==.Dracshot:BAABNQAECoEoAAINAAgKbxI+YQAqAgANAAgKbxI+YQAqAgAAAA==.Dracslock:BAAANQAECgQICQABNQAECggIKAANAG8SAA==.Draffel:BAAANQAECgcIEAAAAA==.Dreamfire:BAAANQADCgYIDQAAAA==.Drestla:BAAANQAECgUIBQAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICQABAAAAAA==.Dräc:BAAANQAECgMIAwABNQAECggIKAANAG8SAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.Dunzer:BAABNQAECoEgAAMOAAgKJxIiLQBJAQAOAAYK0RIiLQBJAQAIAAQK1AxJAAHmAAAAAA==.Dunzerblaze:BAAANQAECgUICAAAAA==.',
Ed='Edithpoothe:BAAANQAECgYIDgAAAA==.',
El='Electricks:BAABNQAECoEfAAMPAAkKZxd9DwBYAgAPAAgKeBZ9DwBYAgAQAAYKUhaodQCQAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgUICwAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECoEXAAIDAAYKLgt1EwFFAQADAAYKLgt1EwFFAQABNQAECggIEgABAAAAAA==.',
Er='Eradoria:BAAANQADCggIHwAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAABNQAECoEXAAMCAAgK/w68gwBUAQACAAcKxwu8gwBUAQAQAAYKAwSMuwDsAAAAAA==.Evagrius:BAAANQABCgIIAgAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJGQARAAcWAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQAECgEIAgAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.',
Fo='Foxyboo:BAABNQAECoEgAAMCAAgKqBb/SwAGAgACAAgKqBb/SwAGAgAQAAQKYAgK0wC8AAAAAA==.',
Fr='Freak:BAAANQAECgYIBwAAAA==.Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECoEhAAINAAgK/SHsGgAUAwANAAgK/SHsGgAUAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECoEfAAICAAgKBiLGGwDjAgACAAgKBiLGGwDjAgAAAA==.Gostewpid:BAAANQADCggIDwAAAA==.',
Gr='Gromiir:BAABNQAECoEdAAINAAgKxiL1GwAOAwANAAgKxiL1GwAOAwAAAA==.Gromyr:BAAANQADCgcIBwABNQAECggIHQANAMYiAA==.',
['Gä']='Gärrus:BAAANQAECgQIBgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgMIAwAAAA==.Hellkat:BAAANQAECgIIAgAAAA==.',
Hi='Higarosa:BAAANQADCgQIBAAAAA==.Highbull:BAAANQAECggICgABNQAECggIEgABAAAAAA==.',
Ho='Holiblade:BAAANQAECgUIEAAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holywhiskers:BAAANQADCggIFwABNQAECggIKQAIADgaAA==.Hooligun:BAAANQAECgQIBwAAAA==.Hoppered:BAAANQAECgUIBQABNQAECggIGgASAD4dAA==.',
Hy='Hypérian:BAAANQAECgUIBQAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQADCgUJBQAAAA==.',
Ic='Icesikle:BAAANQAECgQJCAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECoEcAAMNAAgKjA01dAD6AQANAAgKjA01dAD6AQATAAIK9AisaABlAAAAAA==.',
Il='Illusiongun:BAAANQAECgIIAwABNQAECgkKKQAUAO4dAA==.',
In='Indistera:BAAANQABCgcIBwAAAA==.Insaniac:BAAANQADCggIFAAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgMIAwAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQADCggIFgAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECoEnAAIOAAgKjCD1CQDeAgAOAAgKjCD1CQDeAgAAAA==.',
Jn='Jnymango:BAAANQAECgYIDgAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgYIDgABAAAAAA==.Jollakeratu:BAABNQAECoEeAAIVAAgK5hLwFQDGAQAVAAgK5hLwFQDGAQAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQADCgcIFAAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAAANQAECgcIEwAAAA==.',
['Jø']='Jønty:BAAANQADCgQIBgAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECoEnAAICAAkKHQthYwC0AQACAAkKHQthYwC0AQAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAcIEgAPANsJAA==.Kerubiel:BAAANQAECgQICgABNQAECgUIBQABAAAAAA==.Kessarah:BAAANQAECgcIEwAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEANQAECggIEwAAAA==.Kintssiralop:BAAANQAECgEIAQAAAA==.Kirio:BAAANQADCgUICwAAAA==.Kitsunenohi:BAABNQAECoEdAAIUAAgKuwMzTgApAQAUAAgKuwMzTgApAQAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgUICQAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAUIDAANADQVAA==.',
Ks='Ksandra:BAAANQAECgQICgAAAA==.Ksares:BAABNQAECoEmAAMWAAkK3xs7BgDiAgAWAAkK3xs7BgDiAgAXAAMKlgmDiwByAAAAAA==.',
Kw='Kwazii:BAAANQAECggIDQABNQAECggIEgABAAAAAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQIBAAAAA==.',
['Kë']='Këvîn:BAAANQAECgUIDAAAAA==.',
La='Laeflockxo:BAAANQAECgQIBgAAAA==.Laefnia:BAABNQAECoEiAAMXAAgK5xdJNAAeAgAXAAgK5xdJNAAeAgAYAAMKJxYvRwDGAAAAAA==.Laraydra:BAAANQAECgMIBgABNQAECgYICgABAAAAAA==.Lastofgoobs:BAAANQAECgUIBQAAAA==.',
Le='Leard:BAAANQAECgEIAQABNQAECggIFgAZAEgcAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgUICAAAAA==.Lilis:BAAANQAECgMIBAAAAA==.Lilithe:BAAANQAECgUIBQABNQAECggIGgASAD4dAA==.Liten:BAAANQADCgIIAwAAAA==.Littlebev:BAAANQAECgEIAQAAAA==.Liz:BAAANQADCgQIBgAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Macncheeze:BAAANQABCgQIBAAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgEIAQAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQAECgcICwABNQADCgEIAQABAAAAAA==.Maluin:BAAANQADCgYIEwAAAA==.Mawea:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAAANQAECgYIEAAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECoEhAAIDAAcK7xeaogAcAgADAAcK7xeaogAcAgAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.Meuria:BAAANQABCgYICAAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgYIDgABAAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgEIAQABNQAECggIIgAJAEUgAA==.',
Mo='Moobáca:BAAANQAECggIEgAAAA==.Moostradamas:BAAANQAECgQICQAAAA==.Morcilla:BAAANQAECgYIDgAAAA==.',
My='Myssts:BAAANQADCgQIBAAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAAAAA==.Naturegoob:BAABNQAECoEgAAMYAAgKiyCaDADnAgAYAAgKiyCaDADnAgAXAAIKWQ8JiACAAAAAAA==.Naughtynurse:BAABNQAECoEdAAIYAAgKHwb9MgBNAQAYAAgKHwb9MgBNAQAAAA==.',
Ne='Neuma:BAAANQAECgUIDQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECoEiAAIGAAgKJgmJDwCFAQAGAAgKJgmJDwCFAQAAAA==.',
No='Nostromo:BAABNQAECoEiAAIaAAgKJRTUGQAJAgAaAAgKJRTUGQAJAgAAAA==.',
Ny='Nyxserion:BAAANQADCggICQABNQAECgkJNgADAJ8jAA==.',
Ob='Obiejuan:BAABNQAECoEqAAIIAAkKAh+3JQAUAwAIAAkKAh+3JQAUAwAAAA==.',
Od='Odbc:BAABNQAECoEkAAIXAAkK1RdQIgCdAgAXAAkK1RdQIgCdAgAAAA==.Oddball:BAABNQAECoEgAAIQAAgK0B3MKQC2AgAQAAgK0B3MKQC2AgAAAA==.',
Op='Ophiron:BAAANQADCgcICAAAAA==.',
Or='Orthiaa:BAAANQAECgQIBwAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECggIAgABNQAECggIEgABAAAAAA==.Pez:BAABNQAECoEoAAICAAkKnhsWIwC8AgACAAkKnhsWIwC8AgAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAAANQAECgMIAwABNQAECggIAQABAAAAAA==.Polyhedroll:BAABNQAECoEhAAIbAAkKsx83CQDeAgAbAAkKsx83CQDeAgABNQADCgYIBgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEJAgAAAA==.',
Ps='Psychoman:BAAANQAECgYIBgAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAAANQAECgUIBwAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgIIAgAAAA==.',
Ra='Raakoth:BAAANQAECgUIBQAAAA==.Raathe:BAAANQADCgQIBgAAAA==.Radge:BAABNQAECoEiAAILAAkKDSXWAwDWAwALAAkKDSXWAwDWAwAAAA==.Rainjar:BAAANQAECgIIBAABNQAECgkJKAADABsgAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAAANQAECgQIEQABNQAECgYICgABAAAAAA==.Raljah:BAABNQAECoEaAAQSAAgKPh1aBAB1AgASAAgKixtaBAB1AgAcAAcKFBvZWgAlAgAdAAUK6BjAHgBwAQAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECoEoAAIFAAkKqiFZCQBgAwAFAAkKqiFZCQBgAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQAECgUICwAAAA==.',
Ro='Royalchaos:BAAANQADCgMIAwABNQAECggIKAAeAKodAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAABNQAECoEhAAINAAgKfxbHTwBYAgANAAgKfxbHTwBYAgAAAA==.Ryptyde:BAAANQADCggICAAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECoEqAAMSAAkKlB8OAgD0AgASAAgKHyEOAgD0AgAcAAcKpBfPcADkAQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAAANQAECgYIBwAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECggIFwADAHAfAA==.Serdav:BAAANQADCgYICAAAAA==.',
Sh='Shak:BAAANQADCgYICgAAAA==.Shalai:BAABNQAECoEaAAIUAAkKGR6kEAADAwAUAAkKGR6kEAADAwAAAA==.Shellingtun:BAAANQAECggICgABNQAECggIEgABAAAAAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIIAAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Sksteve:BAAANQAECgMIAwAAAA==.Skychades:BAAANQAECgYIEgAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsrequiem:BAAANQABCgIIAgAAAA==.',
Sp='Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAAANQAECgYIDwAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAAANQAECgUIEQAAAA==.',
St='Stileto:BAAANQAECgcIDgABNQAECggIEgABAAAAAA==.Stoneydracco:BAABNQAECoEcAAMGAAgKZQ2rDQCmAQAGAAgKZQ2rDQCmAQADAAYKjAOtSAHyAAAAAA==.',
Su='Sumtinwng:BAAANQAECgcIDAAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Supervicious:BAAANQAECgcIEwAAAA==.',
Sy='Sylenne:BAAANQADCgcIBwABNQAECgkJKAACAJ4bAA==.Sylur:BAABNQAECoEZAAMRAAkKBxZ6OAAeAgARAAkKBxZ6OAAeAgAFAAIKpw/rpQBhAAAAAA==.',
Ta='Tahren:BAACNQAFFIELAAMeAAUK3hCTDQCQAQAeAAUK3hCTDQCQAQAfAAIKLwHHAgBhAAA1AAQKgS4AAx4ACQrXIksSACMDAB4ACQrXIksSACMDAB8AAwoZIJYPABkBAAAA.Tahshock:BAAANQADCgYICwABNQAFFAUICwAeAN4QAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAAANQAECgUIEAAAAA==.',
Te='Temporalize:BAAANQADCggIDQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgMIAwABAAAAAA==.Thistelbear:BAAANQAECgcIEAAAAA==.Thorinn:BAAANQADCgIIAgAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBAAAAA==.Thunderdin:BAABNQAECoEdAAMOAAgKqxgHEwBNAgAOAAgKqxgHEwBNAgAIAAcKZgz6wgBdAQAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUIBAABNQAECggIEgABAAAAAA==.',
To='Toki:BAAANQAECgMIBAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgMIBAABAAAAAA==.',
Tu='Turnip:BAAANQAECgcIDgABNQAECggIEgABAAAAAA==.',
Tw='Twamsack:BAAANQABCgQIBAAAAA==.Tweak:BAAANQAECgYICgABNQAECggIEgABAAAAAA==.Tweis:BAAANQADCgQIBgAAAA==.',
Um='Umbrarogue:BAAANQAECgcIEQAAAA==.',
Uw='Uwumental:BAAANQABCgcIDQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAAANQAECgQIDAAAAA==.',
Ve='Velien:BAABNQAECoEkAAIIAAkK1Q/vdQASAgAIAAkK1Q/vdQASAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgQIBQAAAA==.Viscerai:BAABNQAECoEYAAIeAAgKbBqrNgBrAgAeAAgKbBqrNgBrAgAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgEIAQAAAA==.',
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
