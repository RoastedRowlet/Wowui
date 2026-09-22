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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Monk-Windwalker','Shaman-Elemental','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Paladin-Protection','Warrior-Fury','Warrior-Arms','Shaman-Restoration','DemonHunter-Vengeance','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Druid-Balance','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Hunter-BeastMastery','DemonHunter-Havoc','Warrior-Protection','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abaz:BAAANQADCgYICQAAAA==.Aberdus:BAAANQAECgYJCQAAAA==.',
Ac='Accalon:BAAANQAECgQJBQAAAA==.',
Ad='Advacus:BAAANQAFFAEJAQAAAA==.',
Ag='Agamar:BAAANQAECgEJAQAAAA==.Ageina:BAAANQADCggICAABNQAFFAMJBgABABgeAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAAANQAECgIJBQAAAA==.',
Al='Alatáriel:BAAANQAECgEJAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQAECgQICAAAAA==.',
An='Andalorian:BAAANQAECgMJAwAAAA==.Anruu:BAAANQAECgUICwAAAA==.',
Ar='Archolaoch:BAAANQAECgYJDgAAAA==.Arconite:BAAANQADCgQIBQABNQAECgcICgACAAAAAA==.Arizonatea:BAAANQAECgEJAQAAAA==.Arkthurus:BAAANQAECgIJAgAAAA==.',
As='Ashenknight:BAAANQADCgEJAQAAAA==.Ashijin:BAABNQAECoEbAAMBAAkK6xdHOgBrAgABAAkK6xdHOgBrAgADAAEKAgFM5wATAAAAAA==.',
At='Athelos:BAAANQADCgUICQAAAA==.Atroce:BAABNQAECoEXAAMEAAkK8R/xFwBOAgAEAAYKdiLxFwBOAgAFAAcKWxo4KQARAgAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQADCggIGQAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECoExAAIGAAgKWhgeFgBaAgAGAAgKWhgeFgBaAgAAAA==.',
Ba='Balethar:BAAANQAECgUIBwABNQAECgcJEQACAAAAAA==.Ballador:BAAANQAECgUJBgAAAA==.Balluh:BAAANQAECgUICgAAAA==.Balzluzzak:BAAANQAECgYJDgAAAA==.Baughter:BAAANQABCgcICQAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAAANQAECgUICgAAAA==.Belttoash:BAAANQADCgcICwAAAA==.Bestricer:BAACNQAFFIEdAAIHAAcKJBnXAAB2AgAHAAcKJBnXAAB2AgA1AAQKgSoAAgcACQp1JRsBANADAAcACQp1JRsBANADAAAA.Bevis:BAAANQAECgUICAABNQAECgkJJAAIANwiAA==.',
Bi='Bigmayex:BAAANQAECgcIEwAAAA==.Bilmuri:BAAANQAECgcICwAAAA==.Bippot:BAABNQAECoEkAAIBAAkKlh4KGQAVAwABAAkKlh4KGQAVAwAAAA==.',
Bl='Blackbride:BAAANQADCggICQAAAA==.Bloodybill:BAAANQADCgUJBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAAANQAECgYJEAAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Bossvega:BAAANQADCggIHAAAAA==.',
Br='Bruhkakke:BAAANQAECggIAgABNQAFFAEIAgACAAAAAA==.',
Bu='Bugbear:BAAANQADCggIFgAAAA==.Bumbly:BAAANQAECgQJBwAAAA==.Bushybrowsy:BAABNQAECoEdAAMJAAgKnA9DBQD8AQAJAAgKnA9DBQD8AQAKAAEK2gP6ZQA3AAAAAA==.Buttermeupz:BAAANQAECgYJDgAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Cactuss:BAAANQADCgUIBQABNQAECgUIDgACAAAAAA==.Caothand:BAAANQADCggJDwAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ce='Cerridwen:BAAANQABCgIJAgAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgkJHgALAA4TAA==.Chazzbadgurl:BAAANQAECgQIBQABNQAECgkJHgALAA4TAA==.Chexmix:BAAANQAECgUJEgAAAA==.Chicho:BAAANQADCgIIAgAAAA==.Chomboslice:BAAANQAECgYJDwAAAA==.',
Ci='Cinnamon:BAAANQAECgcJEQAAAA==.',
Cm='Cmil:BAABNQAECoElAAQDAAkKVRxhEAAIAwADAAkKVRxhEAAIAwABAAcKkw3JcQCoAQAMAAIKwRRCOwB7AAAAAA==.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQAECgEJAQAAAA==.Cruiddeath:BAAANQAECgEIAwABNQAECggJHgANAPILAA==.',
Cu='Curserodlock:BAABNQAECoEeAAMNAAgK8guPCQC1AQANAAgKtwuPCQC1AQAOAAQK7ARDyAC3AAAAAA==.',
Cy='Cyanide:BAAANQAECgUJBQAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDwAAAA==.Dads:BAACNQAFFIELAAIIAAYKexJgAgD7AQAIAAYKexJgAgD7AQA1AAQKgRwAAwgACQpuIXAMAFcDAAgACQpuIXAMAFcDAA8AAwpKAWi0AHoAAAAA.Daedra:BAAANQAECgYJCAAAAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAAANQAECgYICwAAAA==.Darcdk:BAAANQAECgUIBwABNQAFFAUJBwADAPEMAA==.Darcevoker:BAAANQADCgcIBwABNQAFFAUJBwADAPEMAA==.Darcpaladin:BAACNQAFFIEHAAIDAAUK8QzJBQCOAQADAAUK8QzJBQCOAQA1AAQKgR0AAgMACQp7GfQWANYCAAMACQp7GfQWANYCAAAA.Darcpriest:BAAANQAECgEIAQABNQAFFAUJBwADAPEMAA==.Darkrune:BAAANQAECgIIAwAAAA==.Darkschneide:BAAANQAECgQICgAAAA==.Darthtemplar:BAAANQAECgcIEwAAAA==.',
De='Deimoes:BAAANQADCgUJBwAAAA==.Demodorn:BAABNQAECoEjAAIQAAkK2Ag2CgCYAQAQAAkK2Ag2CgCYAQAAAA==.Demyst:BAABNQAECoEaAAMPAAkKaxqVHQCjAgAPAAkKaxqVHQCjAgAIAAEK6wyi4AAxAAAAAA==.Demön:BAAANQADCgUJBQAAAA==.Dewwarrior:BAAANQAECgQICQAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAUJCAARANkWAA==.',
Dh='Dhecaye:BAAANQAECgIJAgAAAA==.',
Di='Disengage:BAAANQAECgUIBwABNQAECgkJHAALAGwjAA==.',
Do='Dohdan:BAAANQADCgUIBwAAAA==.Donkey:BAAANQAECgcJEgAAAA==.Donmega:BAAANQADCggJGQAAAA==.Dougalleone:BAABNQAECoEZAAMSAAkKIiFcBQA+AwASAAkKIiFcBQA+AwATAAYKIBgJHgCgAQAAAA==.Dougallmaki:BAAANQADCggICAAAAA==.',
Dr='Drekkwarr:BAAANQAECgEIAQABNQAECgcJEwACAAAAAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAABNQAECgYIDQACAAAAAA==.Drezzakzz:BAAANQAECgYIDQAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.',
Ea='Eamil:BAAANQADCgcJBwAAAA==.',
Ek='Ekaterin:BAABNQAECoEgAAILAAgKaxxxSgCsAgALAAgKaxxxSgCsAgAAAA==.Ekewa:BAAANQADCgcJBwAAAA==.',
El='Elaidine:BAAANQAECgYJDwAAAA==.Electraknub:BAAANQADCgYJBwAAAA==.Electroh:BAAANQAECgYIDgAAAA==.Eliseda:BAAANQADCggIDAABNQAECggIGQAPANkWAA==.',
Ev='Evilnapkin:BAAANQADCgIIAgAAAA==.Evion:BAAANQAECgUJCAAAAA==.Evoke:BAAANQAECgQJBAAAAA==.',
Fa='Falconsha:BAAANQADCggJIQAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgkJIgAEAFsiAA==.Firefrost:BAABNQAECoEiAAMUAAkKxR13AQAzAwAUAAkKxR13AQAzAwALAAEKgQbJXgE8AAAAAA==.Firescrotum:BAABNQAECoEXAAIIAAgKXQuzSQDLAQAIAAgKXQuzSQDLAQAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECggIEQAAAA==.',
Fr='Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQADCgcIDAABNQAFFAUICAAMAMYSAA==.',
['Fá']='Fáelen:BAAANQAECggIDQAAAA==.',
Ga='Galasmina:BAAANQAECgQJBAAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgcICgACAAAAAA==.Ganda:BAAANQADCgEJAQAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECggIGQAHAK8kAA==.Garm:BAAANQAECgQIDAAAAA==.Gavinrad:BAAANQAECgUJBwAAAA==.',
Ge='Generaname:BAAANQADCgcJDQAAAA==.Generanancy:BAAANQADCgIJAgAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Girthfury:BAAANQAFFAEIAgAAAA==.',
Gl='Glaalinix:BAAANQADCgEIAQAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAAANQAECgUJCgAAAA==.',
Go='Goat:BAAANQAECgMJAwAAAA==.Goku:BAABNQAECoEWAAMPAAkKHx8oDwAPAwAPAAkKHx8oDwAPAwAIAAEKeAhq5wAtAAAAAA==.Goodman:BAAANQAECgIIBQAAAA==.Goom:BAAANQADCggICgABNQAFFAUICgAHAEcPAA==.Goomei:BAACNQAFFIEKAAIHAAUKRw9LAwCGAQAHAAUKRw9LAwCGAQA1AAQKgRsAAgcACQo6H4kNAKUCAAcACQo6H4kNAKUCAAAA.Goomkin:BAABNQAECoEbAAIVAAkKnRjkGwCUAgAVAAkKnRjkGwCUAgABNQAFFAUICgAHAEcPAA==.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQADCgYJBgAAAA==.',
Gr='Gravymonk:BAAANQAECgYJDgAAAA==.Greatbooty:BAAANQAECgIIAwAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grombeefdal:BAAANQADCgYICwAAAA==.Grosgland:BAAANQADCgMIAwAAAA==.Groundbeéf:BAACNQAFFIEHAAIWAAUK3BqbAADnAQAWAAUK3BqbAADnAQA1AAQKgR4AAhYACQrlJFEBAJoDABYACQrlJFEBAJoDAAAA.Grovoath:BAAANQADCgYIBgAAAA==.Grumpypally:BAAANQAECgIJAwAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQAECgQJBAAAAA==.Hallowfear:BAAANQAECgUJDgAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAAANQAECgYIEAAAAA==.Harie:BAAANQAECgIJBAAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgIIAwAAAA==.Heiny:BAABNQAECoEfAAQFAAkKqyRUAgC7AwAFAAkKqyRUAgC7AwAEAAcK6CBHEACqAgAXAAIKFyMYaQDNAAAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgkJHwAFAKskAA==.',
Ho='Holeybeef:BAAANQAECgQIBQAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJIgAUAMUdAA==.Holynoodles:BAAANQAECgYJCwAAAA==.Holytest:BAABNQAECoEjAAIRAAkKjR6dDAAdAwARAAkKjR6dDAAdAwAAAA==.Hoofmetoo:BAAANQAECgMJBgAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAAANQAECgYJCgAAAA==.',
Hy='Hypernova:BAAANQADCgYIBgAAAA==.Hypocrisy:BAAANQAECggJCAAAAA==.',
['Hô']='Hôlyblight:BAABNQAECoEhAAMBAAgKNxGjWgDwAQABAAgKNxGjWgDwAQADAAgKMBCFQgDqAQAAAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Il='Ilbryen:BAAANQAECgEIAQABNQAECgkJHQAOAKAdAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECggJCgAAAA==.',
Im='Immørtlzed:BAACNQAFFIETAAIPAAcKgSMmAADiAgAPAAcKgSMmAADiAgA1AAQKgRsAAg8ACQqNJZwDAJgDAA8ACQqNJZwDAJgDAAAA.',
In='Inara:BAAANQADCgEIAQABNQAECggJFwAHAKYRAA==.Insurion:BAAANQAECgQJBQAAAA==.Invective:BAAANQADCgIIAgAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAACNQAFFIEFAAIYAAMKigksCQDpAAAYAAMKigksCQDpAAA1AAQKgSAAAxgACQqxE+cQAEkCABgACQqxE+cQAEkCABkAAQrzB54uADUAAAAA.Jarrie:BAAANQADCggJDgAAAA==.Jassar:BAAANQAECgEJAgAAAA==.Jaxek:BAABNQAECoEbAAIaAAkKjCANAgBcAwAaAAkKjCANAgBcAwAAAA==.Jaxs:BAABNQAECoEeAAIPAAkKqBjWIQCKAgAPAAkKqBjWIQCKAgAAAA==.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAAANQAECgUICQAAAA==.',
Je='Jebke:BAAANQAECgUJBwAAAA==.',
Jo='Johnwick:BAAANQADCgQIBAAAAA==.Jopha:BAACNQAFFIEHAAIOAAUKehqEBgCxAQAOAAUKehqEBgCxAQA1AAQKgR0AAw4ACQr0I2gNAG8DAA4ACQr0I2gNAG8DAA0AAQrpHxQcAF8AAAAA.Jophr:BAAANQADCgYJDQABNQAFFAUIBwAOAHoaAA==.Jore:BAAANQAECgEIAQAAAA==.',
Jp='Jpbruiser:BAABNQAECoEgAAIBAAkKNBdZPABiAgABAAkKNBdZPABiAgAAAA==.',
Ju='Jumpndeath:BAABNQAECoEZAAIFAAkKeB5uDQAJAwAFAAkKeB5uDQAJAwAAAA==.Jumpnpray:BAAANQAECggICgABNQAECgkJGQAFAHgeAA==.Justgetme:BAAANQAECgcJEQAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAABNQAECoEeAAIOAAkKJRnbMgCdAgAOAAkKJRnbMgCdAgAAAA==.Kadela:BAAANQADCgQIBAAAAA==.Kagger:BAAANQAFFAEJAQAAAA==.Kardoroth:BAAANQAECgYIDAAAAA==.Karîba:BAABNQAECoElAAQXAAkKFSXoAgC7AwAXAAkKFSXoAgC7AwAFAAQK3BVqWwAGAQAEAAEKGBNBaABBAAAAAA==.',
Ke='Keld:BAEANQAECgYJBgAAAA==.Kellienna:BAAANQAECgMIBAABNQAECgQIBQACAAAAAA==.Kelsaz:BAABNQAECoEeAAMbAAkKUiJiIAC6AgAbAAgKriRiIAC6AgAGAAYKghKdKQB3AQAAAA==.Kelshock:BAAANQAECgEIAQAAAA==.Kelsi:BAABNQAECoEXAAIHAAgKphEPGQDwAQAHAAgKphEPGQDwAQAAAA==.Kerrìgàn:BAABNQAECoEfAAMcAAkKfSBCCgAeAwAcAAkKkx9CCgAeAwAQAAQK3By+DABTAQAAAA==.Kestral:BAABNQAECoEXAAIYAAkK8guCFQD4AQAYAAkK8guCFQD4AQAAAA==.',
Kh='Khalisi:BAAANQAECgEJAwAAAA==.',
Ki='Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Kookiie:BAACNQAFFIEHAAIcAAUKyBoWAwC2AQAcAAUKyBoWAwC2AQA1AAQKgR0AAhwACQqNJGMFAHEDABwACQqNJGMFAHEDAAAA.Koom:BAAANQAECgIIAgAAAA==.Kosian:BAAANQAECgEJAgABNQAECggJIQALAPEZAA==.Kosigan:BAAANQADCgUIBQABNQAECggJIAALAGscAA==.',
Kr='Krepuscular:BAAANQAECgcJEAAAAA==.Kryptiq:BAABNQAECoEfAAIdAAkKwiTfAACzAwAdAAkKwiTfAACzAwAAAA==.Kryptìq:BAAANQAECgUIBgABNQAECgkJHwAdAMIkAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAABNQAECoEYAAQeAAkKKhFRBAArAgAeAAkKXA9RBAArAgARAAMK3hKQhADMAAAfAAEK/Qx4WAAqAAAAAA==.',
Le='Leman:BAAANQAECgEJAQAAAA==.Lemondonut:BAAANQADCgUIBQAAAA==.Leomessi:BAAANQADCgQJAwABNQAECgYJEAACAAAAAA==.Levitas:BAABNQAECoEaAAIdAAcKlQ8pEQB7AQAdAAcKlQ8pEQB7AQAAAA==.Leyron:BAAANQAECgQIBQAAAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAABNQAECoEcAAMfAAgKlhsdEACdAgAfAAgKlhsdEACdAgARAAUKEQMshgDGAAAAAA==.Longsham:BAAANQADCgUIBgAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECoEfAAMgAAkKuBPeBAA1AgAgAAkKuBPeBAA1AgAZAAEKQQn6LwAwAAAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAAANQAECgYJDQAAAA==.Lumafist:BAABNQAECoEZAAIHAAgKryQHBgA7AwAHAAgKryQHBgA7AwAAAA==.Lunär:BAAANQADCgUIBQAAAA==.',
['Lè']='Lènneth:BAABNQAECoEYAAMfAAgK3As4IQCxAQAfAAgK3As4IQCxAQARAAMKORGmjQCoAAAAAA==.',
Ma='Maddelyn:BAABNQAECoEeAAILAAkK3yTcBgC0AwALAAkK3yTcBgC0AwAAAA==.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAAANQAECgYJDwAAAA==.Mashanu:BAAANQAFFAIJAgAAAA==.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgcIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAEBNQAECoEaAAIFAAgKeBNTLQD2AQAFAAgKeBNTLQD2AQAAAA==.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAAANQAECgQJBwAAAA==.Meldatonin:BAAANQAECgIJAgAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Mindleseye:BAAANQADCgMJAwAAAA==.Misosalty:BAABNQAECoEkAAQhAAgKLhgPDQBAAgAhAAgKLhgPDQBAAgAHAAUK8A+1KQAiAQAiAAEKPRXpIQA/AAAAAA==.',
Mo='Mohjito:BAAANQAECgYIEAAAAA==.Monica:BAAANQAECgEIAQAAAA==.Mooshanu:BAAANQABCgMIBAABNQAFFAIJAgACAAAAAA==.Morguth:BAAANQAFFAEIAQAAAA==.Moripally:BAAANQAECgcIBwABNQAECgkJIAAfALIiAA==.Moripriest:BAABNQAECoEgAAIfAAkKsiJ9BAB4AwAfAAkKsiJ9BAB4AwAAAA==.Moriwarrior:BAABNQAECoEUAAIOAAcKYRgQWgAGAgAOAAcKYRgQWgAGAgABNQAECgkJIAAfALIiAA==.',
Mu='Murky:BAAANQAECgUIBgAAAA==.Murnemerch:BAAANQADCgQJAgAAAA==.Musclewizard:BAAANQAECgUIDgAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECgYJCAACAAAAAA==.',
['Mï']='Mïlo:BAAANQAECgUJCgAAAA==.',
Na='Nancybrew:BAAANQAECgcJEgAAAA==.',
Ne='Nesqwik:BAAANQADCggJFQAAAA==.Nevan:BAAANQAECgcJEQAAAA==.',
Ni='Nidalee:BAAANQAECgUJBwAAAA==.Nineball:BAAANQAECgYJDQAAAA==.Niyx:BAAANQAECgYJCQAAAA==.',
No='Noochallange:BAAANQAECgMIBwAAAA==.Norex:BAABNQAECoEaAAQEAAkKnhaJGgAwAgAEAAgK0haJGgAwAgAXAAYKQQypTABRAQAFAAEKABWylAA6AAAAAA==.Notgood:BAAANQAECgEJAQAAAA==.',
Nu='Nuggie:BAAANQAECgIJAgAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.',
Ol='Oldmagic:BAAANQAECgQICQAAAA==.Olzpot:BAAANQADCgEJAQAAAA==.',
Oo='Ooglaboogla:BAAANQAECgYJDgAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgcIDAAAAA==.',
Ox='Oxyrotten:BAAANQAECgIJAgAAAA==.',
Pa='Palablort:BAAANQAECgcJDwAAAA==.Panzeria:BAABNQAECoEcAAIfAAkK3yPXBABwAwAfAAkK3yPXBABwAwAAAA==.Pawsome:BAAANQAECgYIEAAAAA==.',
Pi='Pixel:BAAANQAECgEIAwAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pr='Prlestest:BAAANQAECgUJBwAAAA==.Proowee:BAAANQAECggIDQAAAA==.Propayne:BAAANQAECggJAwAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAAANQAECggIEgAAAA==.',
['Pä']='Pälii:BAAANQAECgIJBQAAAA==.',
Qi='Qizai:BAAANQAECgEJAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAAANQAECgQJCAABNQAECgYJCAACAAAAAA==.Ravette:BAAANQAECgUICgAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQAECgEIAgAAAA==.',
Ro='Roidgnome:BAAANQAECgEIAQAAAA==.Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Ru='Runeka:BAAANQADCgcIBwABNQAECgUIBwACAAAAAA==.',
Sa='Safehaven:BAAANQAECgIJAgAAAA==.Samwìse:BAABNQAECoEmAAMRAAkKiR0tFgDPAgARAAkKiR0tFgDPAgAfAAYKWAudLgAnAQAAAA==.Sarranidan:BAAANQAECgYIDwABNQAECggJIQALAPEZAA==.Sathelyn:BAAANQADCgcIBwABNQAECggJHgANAPILAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgIIAgAAAA==.Scopenrage:BAAANQADCgYIBgABNQAECgcIEAAXAG0fAA==.',
Se='Sedontas:BAAANQAECgIIAgAAAA==.Senggolbacok:BAAANQADCgcICQAAAA==.Serengenuity:BAACNQAFFIEHAAMRAAUKkBIVCQBbAQARAAQKoRAVCQBbAQAeAAEKTxq7AQBhAAA1AAQKgR4ABBEACQqtIdIWAMsCABEACQowIdIWAMsCAB4ABgqhH8EEABcCAB8ABAr0HeMrAEABAAAA.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJIgAUAMUdAA==.Shark:BAAANQAECgcJEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggICAABNQAFFAEIAgACAAAAAA==.Shiggyll:BAAANQAECgMIBAABNQAECgkJIwARAI0eAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shmoople:BAAANQADCgYJBgAAAA==.Shockin:BAABNQAECoEWAAIWAAgKGw1XDgAMAgAWAAgKGw1XDgAMAgAAAA==.Shootin:BAAANQAECgIJBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.Shøstákovich:BAAANQAECgEIAQAAAA==.',
Si='Sifen:BAAANQAECgUIBQABNQAECgkJJAAIANwiAA==.Sifting:BAABNQAECoEaAAILAAgKphzFSACxAgALAAgKphzFSACxAgAAAA==.Sinsheretic:BAAANQAECgQIBAAAAA==.Sinswrath:BAACNQAFFIEHAAIBAAUK/BjDAgDJAQABAAUK/BjDAgDJAQA1AAQKgR0AAgEACQoDJUoKAIQDAAEACQoDJUoKAIQDAAAA.',
Sk='Skidxx:BAAANQADCgYJDQAAAA==.Skygnome:BAABNQAECoEeAAIYAAkKyRj3CgC0AgAYAAkKyRj3CgC0AgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAAANQAECgcICgAAAA==.',
Sm='Smores:BAAANQADCgEIAQABNQAFFAUJCgAjADQjAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAABNQAECoEZAAITAAgKKRVuDwBRAgATAAgKKRVuDwBRAgAAAA==.',
So='Songi:BAABNQAECoEfAAIXAAkK6SFzBwBrAwAXAAkK6SFzBwBrAwAAAA==.Soulwhisper:BAABNQAECoEfAAIXAAkKfCC7CABXAwAXAAkKfCC7CABXAwAAAA==.',
Sp='Spanda:BAABNQAECoEdAAIiAAgKqRjICAAvAgAiAAgKqRjICAAvAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splagzhul:BAAANQADCgYIBgAAAA==.Splendi:BAAANQAECgQIBAABNQAECggJHQAiAKkYAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECoEcAAIDAAgKiCKDDQAjAwADAAgKiCKDDQAjAwAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECggIHAADAIgiAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stepzlol:BAAANQADCgMIAwAAAA==.Stormsinger:BAABNQAECoEZAAMPAAgK2RaxNAAiAgAPAAgK2RaxNAAiAgAIAAUKPQm4hwAEAQAAAA==.',
Su='Sugarblast:BAABNQAECoEoAAIIAAkKeSNNBQCoAwAIAAkKeSNNBQCoAwAAAA==.Sukaii:BAAANQADCgQJBAAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAABNQAECoEdAAMOAAkKoB1mJADiAgAOAAkKoB1mJADiAgANAAEKnCAqHABeAAAAAA==.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECggIGQAPANkWAA==.Tandea:BAAANQAECgQIBAAAAA==.Tanthyr:BAAANQADCgEIAQAAAA==.',
Te='Testme:BAAANQADCgUIBgAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgUIBwAAAA==.Theodas:BAAANQAECgcIDAAAAA==.Thiccgnome:BAAANQAECggJCwAAAA==.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAAANQAECgcJEQAAAA==.',
Ti='Tikariia:BAAANQAECgQIBAAAAA==.Tipsygypsy:BAAANQAECgYICgAAAA==.Tirent:BAAANQAECgQIBQAAAA==.',
To='Tokenbeef:BAAANQAECgUJCAAAAA==.Tokenshaman:BAAANQAECgYJDgAAAA==.Tokentrees:BAAANQADCgUJBQAAAA==.Touchspell:BAAANQAECgUIDgAAAA==.Toxicdk:BAABNQAECoEWAAMEAAkK1x7zEwB9AgAEAAkKuxrzEwB9AgAFAAYKhx7PLAD5AQAAAA==.Toxicshamy:BAAANQADCggIDgABNQAECgkJFgAEANceAA==.',
Tr='Traylay:BAABNQAECoEZAAIBAAkKfCBkHAABAwABAAkKfCBkHAABAwAAAA==.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQADCggJDgAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAABNQAECoEkAAIIAAkK3CIQBwCRAwAIAAkK3CIQBwCRAwAAAA==.',
Tu='Tujori:BAACNQAFFIEHAAIRAAUKbApsBwCSAQARAAUKbApsBwCSAQA1AAQKgRwAAhEACQqrFtAoAF0CABEACQqrFtAoAF0CAAAA.',
Tw='Twherk:BAAANQAECggIEAABNQAFFAEIAgACAAAAAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAAANQAECgYJEAAAAA==.',
Um='Umokthra:BAAANQADCgUJBwAAAA==.',
Us='Ustoo:BAAANQAECgQICgAAAA==.',
Va='Vae:BAAANQAECgMJAwAAAA==.Vaeros:BAAANQAECgMJBgAAAA==.Varcina:BAAANQAECgYIBgABNQAECgkJJQAXABUlAA==.Variana:BAAANQAECgUIBwAAAA==.Vaylle:BAAANQADCgQJBAAAAA==.',
Ve='Vekz:BAABNQAECoEYAAIDAAgK/B1iGQDFAgADAAgK/B1iGQDFAgAAAA==.Veles:BAAANQAECgEIAQAAAA==.Velytia:BAAANQAECgYJEAAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAAANQAECgUJCAAAAA==.',
Vo='Volcanicbird:BAAANQAECgIIAgAAAA==.Vomax:BAAANQADCgEJAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.',
Wh='Whîrly:BAAANQADCgUIBgAAAA==.',
Wo='Wolf:BAAANQAECgIJAgAAAA==.',
Wt='Wtfheal:BAAANQAECggICwABNQAFFAEIAgACAAAAAA==.',
Wu='Wumbology:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrrior:BAAANQADCgUIBQAAAA==.',
Ya='Yamashaman:BAAANQAECgYIDQABNQAECggIHAAXAPsbAA==.Yardgnome:BAAANQADCgMIAwAAAA==.',
Yu='Yuna:BAAANQAECgUIDgAAAA==.',
Za='Zacheris:BAAANQAECgYJCwABNQAECgkJIQAFADgPAA==.Zafod:BAAANQADCgUICAAAAA==.Zamasu:BAAANQAECgIJAwAAAA==.Zapped:BAAANQAECgEIAQAAAA==.Zaszadin:BAEANQAFFAEJAQAAAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zerax:BAAANQAECgIIBQAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAAANQAECgYJDAAAAA==.',
Zo='Zombidruid:BAAANQADCgUJCAAAAA==.Zombiebubble:BAAANQAECgEIAQAAAA==.Zoìdberg:BAAANQAFFAEIBAAAAA==.',
Zs='Zselk:BAAANQADCgUIBQAAAA==.Zshot:BAAANQAECgQJBgAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAABNQAECoElAAILAAkK8yLqFABlAwALAAkK8yLqFABlAwAAAA==.',
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
