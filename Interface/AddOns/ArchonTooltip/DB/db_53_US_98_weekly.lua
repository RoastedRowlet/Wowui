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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Hunter-Marksmanship','Monk-Windwalker','Shaman-Elemental','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Restoration','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Mage-Frost','Paladin-Protection','Druid-Balance','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Frost','Hunter-BeastMastery','DemonHunter-Havoc','Warrior-Protection','Evoker-Augmentation','Monk-Mistweaver','Priest-Shadow','Priest-Discipline','Monk-Brewmaster',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abaz:BAAANQADCgYICQAAAA==.Aberdus:BAAANQAECgIIAwAAAA==.',
Ac='Accalon:BAAANQAECgEIAQAAAA==.',
Ad='Advacus:BAAANQAECgcIEQAAAA==.',
Ag='Agamar:BAAANQADCggIGwAAAA==.Ageina:BAAANQADCggICAABNQAECgkJHwABAA0lAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAAANQAECgIIAwAAAA==.',
Al='Alatáriel:BAAANQAECgEIAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQAECgQIBAAAAA==.',
An='Anruu:BAAANQAECgUICQAAAA==.',
Ar='Archolaoch:BAAANQAECgQICAAAAA==.Arconite:BAAANQADCgQIBQABNQAECgYICAACAAAAAA==.Arizonatea:BAAANQAECgEIAQAAAA==.Arkthurus:BAAANQAECgIIAgAAAA==.',
As='Ashenknight:BAAANQADCgEIAQAAAA==.Ashijin:BAABNQAECoEYAAMBAAkJGRYnJwB6AgABAAkJGRYnJwB6AgADAAEJAgGExQATAAAAAA==.',
At='Athelos:BAAANQADCgUICQAAAA==.Atroce:BAAANQAECgcIDAAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQADCggIEQAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECoEjAAIEAAgJjxW4FQAwAgAEAAgJjxW4FQAwAgAAAA==.',
Ba='Balethar:BAAANQADCggICAABNQAECgUIDwACAAAAAA==.Ballador:BAAANQAECgIIAgAAAA==.Balluh:BAAANQAECgMIBQAAAA==.Balzluzzak:BAAANQAECgUICAAAAA==.Baughter:BAAANQABCgcICQAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAAANQAECgQIBQAAAA==.Bestricer:BAACNQAFFIEWAAIFAAcJmRZ7AACIAgAFAAcJmRZ7AACIAgA1AAQKgSQAAgUACQlVJfkAAM0DAAUACQlVJfkAAM0DAAAA.Bevis:BAAANQAECgIIAgABNQAECgkJHgAGAOsgAA==.',
Bi='Bigmayex:BAAANQAECgUIDAAAAA==.Bilmuri:BAAANQAECgQIBAAAAA==.Bippot:BAABNQAECoEbAAIBAAgJbhx9JACKAgABAAgJbhx9JACKAgAAAA==.',
Bl='Blackbride:BAAANQADCggICQAAAA==.Bloodybill:BAAANQADCgUIBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAAANQAECgUICgAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Bossvega:BAAANQADCgcIFAAAAA==.',
Br='Bruhkakke:BAAANQAECggIAgABNQAFFAEIAQACAAAAAA==.',
Bu='Bugbear:BAAANQADCggIDQAAAA==.Bumbly:BAAANQAECgQIBAAAAA==.Bushybrowsy:BAAANQAECgcIEQAAAA==.Buttermeupz:BAAANQAECgQICAAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Caothand:BAAANQADCggIDgAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgcIEwACAAAAAA==.Chazzbadgurl:BAAANQADCgQIBAABNQAECgcIEwACAAAAAA==.Chexmix:BAAANQAECgUIDQAAAA==.Chicho:BAAANQADCgIIAgABNQAECggIFgAHANgaAA==.Chomboslice:BAAANQAECgUICQAAAA==.',
Ci='Cinnamon:BAAANQAECgcICwAAAA==.',
Cm='Cmil:BAABNQAECoEcAAIDAAkJVRz8CgAbAwADAAkJVRz8CgAbAwAAAA==.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQADCgYIBgAAAA==.Cruiddeath:BAAANQAECgEIAgABNQAECggIHAAIALsLAA==.',
Cu='Curserodlock:BAABNQAECoEcAAMIAAgJuwsWBwC6AQAIAAgJtwsWBwC6AQAJAAMJXgMBtQCSAAAAAA==.',
Cy='Cyanide:BAAANQADCggIDgAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDgAAAA==.Dads:BAACNQAFFIEGAAIGAAQJuxLpAwBXAQAGAAQJuxLpAwBXAQA1AAQKgRkAAwYACQn+IswNACEDAAYACAl+IswNACEDAAoAAwlKAZmYAHwAAAAA.Daedra:BAAANQAECgIIAgABNQAECgMIBAACAAAAAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAAANQAECgQIBQAAAA==.Darcdk:BAAANQAECgIIAgABNQAECgkJGgADAP0YAA==.Darcevoker:BAAANQADCgcIBwABNQAECgkJGgADAP0YAA==.Darcpaladin:BAABNQAECoEaAAIDAAkJ/RiSDwDpAgADAAkJ/RiSDwDpAgAAAA==.Darcpriest:BAAANQAECgEIAQABNQAECgkJGgADAP0YAA==.Darkrune:BAAANQAECgIIAgAAAA==.Darkschneide:BAAANQAECgQIBgAAAA==.Darthtemplar:BAAANQAECgcIDAAAAA==.',
De='Deckaye:BAAANQADCgYIDgABNQAECgIIAgACAAAAAA==.Deimoes:BAAANQADCgIIAgAAAA==.Demodorn:BAABNQAECoEfAAILAAkJawgtBwCeAQALAAkJawgtBwCeAQAAAA==.Demyst:BAABNQAECoEXAAMKAAkJCxp7EwC9AgAKAAkJCxp7EwC9AgAGAAEJ6wwCvAAxAAAAAA==.Demön:BAAANQADCgUIBQAAAA==.Dewwarrior:BAAANQAECgQIBAAAAA==.Dezeraz:BAEANQAECgYIBgABNQAECgkJHAAMAJ0bAA==.',
Dh='Dhecaye:BAAANQAECgIIAgAAAA==.',
Di='Disengage:BAAANQAECgUIBwABNQAECgkJHAANAGwjAA==.',
Do='Dohdan:BAAANQADCgUIBwAAAA==.Donkey:BAAANQAECgYICwAAAA==.Donmega:BAAANQADCggIFAAAAA==.Dougalleone:BAABNQAECoEWAAMOAAgJUSIrBQAXAwAOAAgJUSIrBQAXAwAPAAYJIBhNGQCzAQAAAA==.',
Dr='Drekkwarr:BAAANQADCgQICAABNQAECgcIDAACAAAAAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAAAAA==.Drezzakzz:BAAANQAECgEIAQABNQAECgYIDAACAAAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.',
Ek='Ekaterin:BAABNQAECoEYAAINAAgJZxvDNwCyAgANAAgJZxvDNwCyAgAAAA==.',
El='Elaidine:BAAANQAECgUICQAAAA==.Electraknub:BAAANQADCgEIAQAAAA==.Electroh:BAAANQAECgYIDgAAAA==.',
Ev='Evilnapkin:BAAANQADCgIIAgAAAA==.Evion:BAAANQAECgMIAwAAAA==.',
Fa='Falconsha:BAAANQADCggIGQAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgkJGwAQALIgAA==.Firefrost:BAABNQAECoEYAAMRAAkJtRw9AQATAwARAAkJtRw9AQATAwANAAEJgQYXMAE9AAAAAA==.Firescrotum:BAAANQAECgYIDQAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECgYIDwAAAA==.',
Fr='Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQADCgcIDAABNQAECgkJIQASAB0iAA==.',
['Fá']='Fáelen:BAAANQAECgcICgAAAA==.',
Ga='Galasmina:BAAANQADCggIFQAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgYICAACAAAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECgYIDgACAAAAAA==.Garm:BAAANQAECgQICAAAAA==.Gavinrad:BAAANQAECgMIAwAAAA==.',
Ge='Generaname:BAAANQADCgQIBQAAAA==.Gep:BAAANQADCggIDQABNQAECgMIBQACAAAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Girthfury:BAAANQAFFAEIAQAAAA==.',
Gl='Glaalinix:BAAANQADCgEIAQAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAAANQAECgQIBQAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAAANQAECgcIDAAAAA==.Goodman:BAAANQAECgIIAwAAAA==.Goom:BAAANQADCgIIAgABNQAECgkJGQAFADofAA==.Goomei:BAABNQAECoEZAAIFAAkJOh/lCQC3AgAFAAkJOh/lCQC3AgAAAA==.Goomkin:BAABNQAECoEYAAITAAkJ4xUzFwCXAgATAAkJ4xUzFwCXAgABNQAECgkJGQAFADofAA==.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQADCgYIBgAAAA==.',
Gr='Gravymonk:BAAANQAECgQICAAAAA==.Greatbooty:BAAANQAECgIIAgAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grombeefdal:BAAANQADCgYICwAAAA==.Grosgland:BAAANQADCgMIAwAAAA==.Groundbeéf:BAABNQAECoEaAAIUAAkJfCTFAAC3AwAUAAkJfCTFAAC3AwAAAA==.Grovoath:BAAANQADCgYIBgAAAA==.Grumpypally:BAAANQAECgEIAQAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQADCggIEwAAAA==.Hallowfear:BAAANQAECgUICQAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAAANQAECgQICgAAAA==.Harie:BAAANQAECgIIAgAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgEIAgAAAA==.Heiny:BAAANQAECggIEgAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECggIEgACAAAAAA==.',
Ho='Holeybeef:BAAANQAECgQIBQAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJGAARALUcAA==.Holynoodles:BAAANQAECgUICgAAAA==.Holytest:BAABNQAECoEaAAIMAAkJjR7ECAAeAwAMAAkJjR7ECAAeAwAAAA==.Hoofmetoo:BAAANQAECgEIAwAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAAANQAECgQIBAAAAA==.',
Hy='Hypernova:BAAANQADCgYIBgAAAA==.Hypocrisy:BAAANQAECggICAAAAA==.',
['Hô']='Hôlyblight:BAABNQAECoEZAAMDAAgJMBBJMgD3AQADAAgJMBBJMgD3AQABAAgJ4ArzWACWAQAAAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Il='Ilbryen:BAAANQADCgYIEAABNQAECgkJGQAJAEkdAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECgYICAAAAA==.',
Im='Immørtlzed:BAACNQAFFIEMAAIKAAYJkiJtAAB2AgAKAAYJkiJtAAB2AgA1AAQKgRYAAgoACQlrJYgCAJ0DAAoACQlrJYgCAJ0DAAAA.',
In='Inara:BAAANQADCgEIAQABNQAECgYIDgACAAAAAA==.Insurion:BAAANQAECgMIAwAAAA==.Invective:BAAANQADCgIIAgAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAABNQAECoEdAAMVAAkJ0hKiDQBPAgAVAAkJ0hKiDQBPAgAWAAEJ8wfhKAA1AAAAAA==.Jarrie:BAAANQADCgcIDQAAAA==.Jassar:BAAANQAECgEIAgAAAA==.Jaxek:BAAANQAECgcIDwAAAA==.Jaxs:BAABNQAECoEaAAIKAAkJERi7FwCYAgAKAAkJERi7FwCYAgAAAA==.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAAANQAECgQIBQAAAA==.',
Je='Jebke:BAAANQAECgIIAgAAAA==.',
Jo='Jopha:BAABNQAECoEZAAIJAAkJ9CO+BwCTAwAJAAkJ9CO+BwCTAwAAAA==.Jophr:BAAANQADCgYICgABNQAECgkJGQAJAPQjAA==.Jore:BAAANQAECgEIAQAAAA==.',
Jp='Jpbruiser:BAABNQAECoEbAAIBAAkJDxc+KAB0AgABAAkJDxc+KAB0AgAAAA==.',
Ju='Jumpndeath:BAABNQAECoEWAAIXAAkJ5R3/CAAoAwAXAAkJ5R3/CAAoAwAAAA==.Jumpnpray:BAAANQAECgYICgABNQAECgkJFgAXAOUdAA==.Justgetme:BAAANQAECgUIDwAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAABNQAECoEaAAIJAAkJuBiBIQDNAgAJAAkJuBiBIQDNAgAAAA==.Kagger:BAAANQAECgMIAwAAAA==.Kardoroth:BAAANQAECgYIDAAAAA==.Karîba:BAABNQAECoEeAAQQAAkJ9iSCAgC5AwAQAAkJ9iSCAgC5AwAXAAMJuxYCVwDSAAAYAAEJGBOASgBGAAAAAA==.',
Ke='Keld:BAEANQADCggICwAAAA==.Kellienna:BAAANQAECgMIBAAAAA==.Kelsaz:BAABNQAECoEcAAMZAAkJUiL/EgDfAgAZAAgJriT/EgDfAgAEAAYJ4w4iJABlAQAAAA==.Kelshock:BAAANQAECgEIAQAAAA==.Kelsi:BAAANQAECgYIDgAAAA==.Kerrìgàn:BAABNQAECoEYAAMaAAkJoR2aCQD4AgAaAAkJqhyaCQD4AgALAAMJbiAECwAaAQAAAA==.Kestral:BAAANQAECgcIEQAAAA==.',
Kh='Khalisi:BAAANQAECgEIAwAAAA==.',
Ki='Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Kookiie:BAABNQAECoEaAAIaAAkJjSTPAgCaAwAaAAkJjSTPAgCaAwAAAA==.Kosian:BAAANQAECgEIAgABNQAECggIGQANALUYAA==.Kosigan:BAAANQADCgUIBQABNQAECggIGAANAGcbAA==.',
Kr='Krepuscular:BAAANQAECgYICAAAAA==.Kryptiq:BAABNQAECoEdAAIbAAkJVyPxAACfAwAbAAkJVyPxAACfAwAAAA==.Kryptìq:BAAANQAECgQIBAABNQAECgkJHQAbAFcjAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAAANQAECggIEgAAAA==.',
Le='Lemondonut:BAAANQADCgUIBQAAAA==.Levitas:BAAANQAECgYIEAAAAA==.Leyron:BAAANQAECgEIAQABNQAECgMIBAACAAAAAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAAANQAECgcIEwAAAA==.Longsham:BAAANQADCgQIBAAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECoEdAAMcAAkJexO9AwA9AgAcAAkJexO9AwA9AgAWAAEJQQkpKgAwAAAAAA==.Lovespell:BAAANQAECgQICQAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAAANQAECgUIBwAAAA==.Lumafist:BAAANQAECgYIDgAAAA==.Lunär:BAAANQADCgUIBQAAAA==.',
['Lè']='Lènneth:BAAANQAECgUIDQAAAA==.',
Ma='Maddelyn:BAABNQAECoEXAAINAAkJ1CLxDQB1AwANAAkJ1CLxDQB1AwAAAA==.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAAANQAECgUICQAAAA==.Mashanu:BAAANQAECggIDgAAAA==.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgcIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAEANQAECgcIDwAAAA==.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAAANQAECgIIAwAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Misosalty:BAABNQAECoEYAAMdAAcJJBYoDwDSAQAdAAcJJBYoDwDSAQAFAAUJLwQNLAC2AAAAAA==.',
Mo='Mohjito:BAAANQAECgQICgAAAA==.Monica:BAAANQAECgEIAQAAAA==.Mooshanu:BAAANQABCgMIBAABNQAECggIDgACAAAAAA==.Morguth:BAAANQAECggIDQAAAA==.Moripriest:BAABNQAECoEaAAIeAAkJWCJAAwCHAwAeAAkJWCJAAwCHAwAAAA==.Moriwarrior:BAAANQAECggICgABNQAECgkJGgAeAFgiAA==.',
Mu='Murky:BAAANQAECgUIBgAAAA==.Musclewizard:BAAANQAECgUICQAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECgMIBAACAAAAAA==.',
['Mï']='Mïlo:BAAANQAECgQIBQAAAA==.',
Na='Nancybrew:BAAANQAECgYICwAAAA==.',
Ne='Nesqwik:BAAANQADCggIEwAAAA==.Nevan:BAAANQAECgcICwAAAA==.',
Ni='Nidalee:BAAANQAECgMIAwAAAA==.Nineball:BAAANQAECgUIBwAAAA==.Niyx:BAAANQAECgMIAwAAAA==.',
No='Noochallange:BAAANQAECgMIBAAAAA==.Norex:BAABNQAECoEXAAQYAAkJaxNNFAAKAgAYAAgJOBNNFAAKAgAQAAYJQQyeQABcAQAXAAEJABVlfgA8AAAAAA==.Notgood:BAAANQAECgEIAQAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.',
Ol='Oldmagic:BAAANQAECgQIBQAAAA==.',
Oo='Ooglaboogla:BAAANQAECgQICAAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgQIBAAAAA==.',
Ox='Oxyrotten:BAAANQAECgIIAgAAAA==.',
Pa='Palablort:BAAANQAECgUICwAAAA==.Panzeria:BAABNQAECoEZAAIeAAkJKyPHAwB4AwAeAAkJKyPHAwB4AwAAAA==.Pawsome:BAAANQAECgUICgAAAA==.',
Pi='Pixel:BAAANQAECgEIAwAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pr='Prlestest:BAAANQAECgEIAQAAAA==.Proowee:BAAANQAECggIDQAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAAANQAECgQIBgAAAA==.',
['Pä']='Pälii:BAAANQAECgIIAwAAAA==.',
Qi='Qizai:BAAANQADCgMIBAAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAAANQAECgMIBAAAAA==.Ravette:BAAANQAECgQIBQAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQADCgUIBwAAAA==.',
Ro='Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Sa='Safehaven:BAAANQADCggIGQAAAA==.Samwìse:BAABNQAECoEhAAMMAAkJgR07DgDdAgAMAAkJgR07DgDdAgAeAAYJAwqJJgAuAQAAAA==.Sarranidan:BAAANQAECgYICgABNQAECggIGQANALUYAA==.Sathelyn:BAAANQADCgcIBwABNQAECggIHAAIALsLAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgIIAgAAAA==.Scopenrage:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.',
Se='Sedontas:BAAANQAECgIIAgAAAA==.Senggolbacok:BAAANQADCgQIBAAAAA==.Serengenuity:BAABNQAECoEbAAQMAAkJVSGnDgDZAgAMAAkJMCGnDgDZAgAfAAUJnB6WBgCfAQAeAAQJ9B3fIwBLAQAAAA==.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJGAARALUcAA==.Shark:BAAANQAECgcIEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggICAABNQAFFAEIAQACAAAAAA==.Shiggyll:BAAANQAECgMIBAABNQAECgkJGgAMAI0eAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shockin:BAAANQAECgcIDgAAAA==.Shootin:BAAANQAECgIIBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.',
Si='Sifting:BAAANQAECgYIDQAAAA==.Sinswrath:BAABNQAECoEaAAIBAAkJAyX5BACnAwABAAkJAyX5BACnAwAAAA==.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skygnome:BAABNQAECoEaAAIVAAkJAhe5CAC5AgAVAAkJAhe5CAC5AgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAAANQAECgYICAAAAA==.',
Sm='Smores:BAAANQADCgEIAQABNQAECgkJHwAHAJsmAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAAANQAECgcIDwAAAA==.',
So='Songi:BAABNQAECoEbAAIQAAkJFiHoBQBxAwAQAAkJFiHoBQBxAwAAAA==.Soulwhisper:BAABNQAECoEYAAIQAAkJGR9FCwAZAwAQAAkJGR9FCwAZAwAAAA==.',
Sp='Spanda:BAABNQAECoEdAAIgAAgJqRg5BgBRAgAgAAgJqRg5BgBRAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splagzhul:BAAANQADCgYIBgAAAA==.Splendi:BAAANQAECgQIBAABNQAECggIHQAgAKkYAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECoEYAAIDAAcJMyGvFgCpAgADAAcJMyGvFgCpAgAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgcIGAADADMhAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stormsinger:BAAANQAECgYIDgAAAA==.',
Su='Sugarblast:BAABNQAECoEeAAIGAAkJTCIjBgCGAwAGAAkJTCIjBgCGAwAAAA==.Sukaii:BAAANQADCgQIBAAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAABNQAECoEZAAMJAAkJSR1xHADsAgAJAAkJSR1xHADsAgAIAAEJnCDZFgBiAAAAAA==.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECgYIDgACAAAAAA==.Tanthyr:BAAANQADCgEIAQAAAA==.',
Te='Testme:BAAANQADCgUIBgAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgUIBwAAAA==.Theodas:BAAANQAECgUICQAAAA==.Thiccgnome:BAAANQAECgIIAgAAAA==.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAAANQAECgUICgAAAA==.',
Ti='Tipsygypsy:BAAANQAECgYIBQAAAA==.Tirent:BAAANQAECgQIBQAAAA==.',
To='Tokenbeef:BAAANQAECgIIAwAAAA==.Tokenshaman:BAAANQAECgQICAAAAA==.Tokentrees:BAAANQADCgUIBQAAAA==.Toxicdk:BAAANQAECggIDAAAAA==.Toxicshamy:BAAANQADCggIDgABNQAECggIDAACAAAAAA==.',
Tr='Traylay:BAABNQAECoEWAAIBAAkJ/h8mEwAHAwABAAkJ/h8mEwAHAwAAAA==.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQADCgcIDQAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAABNQAECoEeAAIGAAkJ6yCiCQBVAwAGAAkJ6yCiCQBVAwAAAA==.',
Tu='Tujori:BAABNQAECoEZAAIMAAkJoxauHQBbAgAMAAkJoxauHQBbAgAAAA==.',
Tw='Twherk:BAAANQAECggIDgABNQAFFAEIAQACAAAAAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAAANQAECgUICgAAAA==.',
Um='Umokthra:BAAANQADCgIIAgAAAA==.',
Us='Ustoo:BAAANQAECgQIBgAAAA==.',
Va='Vae:BAAANQADCgEIAQAAAA==.Vaeros:BAAANQAECgMIBAAAAA==.Variana:BAAANQAECgQIBQAAAA==.',
Ve='Vekz:BAAANQAECgYIDQAAAA==.Veles:BAAANQADCggICAAAAA==.Velytia:BAAANQAECgQICgAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAAANQAECgIIAwAAAA==.',
Vo='Volcanicbird:BAAANQAECgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.',
Wh='Whîrly:BAAANQADCgIIAgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECgQICgABNQAFFAEIAQACAAAAAA==.',
Wu='Wumbology:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrrior:BAAANQADCgEIAQAAAA==.',
Ya='Yamashaman:BAAANQAECgQIBwABNQAECgYIEwACAAAAAA==.Yardgnome:BAAANQADCgMIAwAAAA==.',
Yu='Yuna:BAAANQAECgUICQAAAA==.',
Za='Zacheris:BAAANQAECgUIBQAAAA==.Zafod:BAAANQADCgUICAAAAA==.Zamasu:BAAANQAECgIIAgAAAA==.Zapped:BAAANQAECgEIAQAAAA==.Zaszadin:BAEANQAFFAEIAQAAAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zerax:BAAANQAECgIIAwAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAAANQAECgQIBgAAAA==.',
Zo='Zombidruid:BAAANQADCgUICAAAAA==.Zombiebubble:BAAANQAECgEIAQAAAA==.Zoìdberg:BAAANQAFFAEIBAAAAA==.',
Zs='Zshot:BAAANQAECgQIBQAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAABNQAECoEhAAINAAkJniJpEABmAwANAAkJniJpEABmAwAAAA==.',
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
