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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Warlock-Affliction','Monk-Windwalker','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Blood','Shaman-Elemental','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abracadavr:BAAANQADCgUJCQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECoEuAAIBAAkKVh/CDQA3AwABAAkKVh/CDQA3AwAAAA==.',
Ad='Addison:BAAANQAECgQIBwAAAA==.Adeleas:BAAANQADCggIFgAAAA==.Adêrna:BAAANQAECgYIEQAAAA==.',
Ag='Agba:BAABNQAECoEUAAMCAAcKtRDgNgDHAQACAAcKtRDgNgDHAQADAAEKqAmBcQAtAAAAAA==.',
Ai='Aibrean:BAAANQADCggIGwAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksel:BAAANQADCgMIAQAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgQIBgAAAA==.Alanus:BAAANQAECgUIDAAAAA==.Alarion:BAAANQADCgcIFQAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAAEAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQADCggJEgAAAA==.Angrymanjibs:BAAANQAECgEIAQAAAA==.Anitasummon:BAAANQADCgUIBwAAAA==.Annahe:BAAANQAECgUIDQAAAA==.Annale:BAAANQADCgYIBgABNQAECgUIDQAEAAAAAA==.Anub:BAAANQAECgcIEwAAAA==.Anzala:BAAANQADCgUIBQAAAA==.',
Ar='Armsmaster:BAAANQAECgUIDgABNQAECgcJFwAFACEhAA==.Arrann:BAAANQADCggJDwAAAA==.Artemistha:BAAANQAECgIIAwAAAA==.',
Av='Avengharambe:BAAANQADCgcJBwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
['Aø']='Aøi:BAABNQAFFIEHAAIGAAUKAhpcAgDIAQAGAAUKAhpcAgDIAQAAAA==.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAAANQADCggICQAAAA==.Barelycastin:BAAANQAECgUIDQAAAA==.',
Be='Beleriand:BAAANQAECgIIAgAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.',
Bl='Blacat:BAAANQAECgcIEAAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgEJAQAEAAAAAA==.Blitzcomets:BAAANQADCgcICwAAAA==.Bloodshunter:BAAANQAECggIEAAAAA==.',
Bo='Borda:BAAANQAECgUJCQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgIIAgAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgIIAgAEAAAAAA==.',
Ca='Carini:BAAANQAECgUICgAAAA==.',
Ch='Chelsgrin:BAAANQAECgUIBwABNQAECgcICwAEAAAAAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQADCggJDgAAAA==.',
Cl='Clûtch:BAAANQAECgYIDAAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAAANQAECgUICgAAAA==.',
Cr='Crickie:BAAANQADCggIFwAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAAANQAECgUIDQAAAA==.',
Da='Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQADCggIAwAAAA==.Darktalyn:BAAANQAECgUIDQAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECoEUAAIHAAcKTBsFPAAtAgAHAAcKTBsFPAAtAgAAAA==.Deekura:BAAANQAECgMJBQAAAA==.Dezireth:BAABNQAECoEZAAIBAAgKMwjmWQDhAQABAAgKMwjmWQDhAQAAAA==.',
Di='Dinak:BAAANQADCgcIDgAAAA==.Dionan:BAAANQAECgUIDQAAAA==.',
Do='Docs:BAAANQAECgQJBAAAAA==.Doks:BAAANQAECgYICwAAAA==.',
Dr='Dragana:BAAANQADCgYIEwAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAYIDgAIALMBAA==.',
El='Elondrin:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQADCggIDQAEAAAAAA==.',
Es='Espe:BAAANQAECgUIDQAAAA==.',
Ev='Everayn:BAABNQAECoEiAAMIAAcKyRLMSADPAQAIAAcKyRLMSADPAQAJAAUKRguNrwAHAQABNQAECgkJLgABAFYfAA==.',
Ex='Exhalo:BAABNQAECoEYAAIKAAcKyREvcAC7AQAKAAcKyREvcAC7AQAAAA==.',
Fa='Fallen:BAAANQAECgYJDAAAAA==.Fasebreaker:BAAANQABCgMIAQAAAA==.Faynor:BAAANQAECgUICgAAAA==.',
Fi='Finalycalm:BAAANQAECgQIBAAAAA==.Finimus:BAAANQAECgIJAgAAAA==.',
Fr='Fraggle:BAECNQAFFIEFAAIIAAMKrgszCwDuAAAIAAMKrgszCwDuAAA1AAQKgSIAAwgACQpFHNkQAAQDAAgACQpFHNkQAAQDAAkAAQpKDR8ZATkAAAAA.Frogchi:BAAANQAECgEJAQAAAA==.Frostbité:BAAANQADCggJEgAAAA==.Fruit:BAAANQADCggJHgAAAA==.',
Fu='Fubarut:BAAANQABCgYIDAAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAAEAAAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAAEAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQADCggIEAAAAA==.',
Gl='Glaistiguain:BAABNQAECoEXAAQFAAcKISGEAgCUAgAFAAcKqB+EAgCUAgALAAMKeSFGJQAkAQAHAAEKSBXw2QBIAAAAAA==.Glifin:BAAANQAECgEJAQAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgIIBQABNQAECgYIEQAEAAAAAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Gr='Gr:BAAANQAECgUICwAAAA==.Gryffs:BAAANQAECgUICwAAAA==.',
Gu='Gutts:BAAANQADCggIDQABNQAECgUIDQAEAAAAAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgMJBAAAAA==.',
Ha='Halartion:BAAANQAECgcICwAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAYIDgAMAFYaAA==.Haruun:BAAANQADCgcIEgAAAA==.',
He='Hesmydaddy:BAAANQAECgYIEQAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAAANQAECgYIEQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgEIAQAEAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJAwAAAA==.Jarrack:BAAANQAECgUICgAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAAANQAECgUIDQAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAAEAAAAAA==.',
Ji='Jivederpy:BAAANQAECgQIBQAAAA==.',
Ju='Juicybooty:BAAANQADCgMJAwAAAA==.Junazeena:BAAANQAECgUJBQAAAA==.',
Ka='Kahlisto:BAAANQAECggIBgAAAA==.Kayfabe:BAAANQAECgYJDwAAAA==.',
Ke='Keirasti:BAAANQADCggJDgABNQADCggIFgAEAAAAAA==.Keishilda:BAAANQADCgUJCwAAAA==.Keladria:BAAANQADCggJDgAAAA==.Kelirra:BAAANQADCgUJDQAAAA==.Kenel:BAAANQAECgYIEQAAAA==.Kerea:BAAANQAECgUICgAAAA==.Kermitt:BAAANQABCggJDAAAAA==.Keyarga:BAAANQADCgUIBgABNQAECgEIAgAEAAAAAA==.',
Kh='Khazadoom:BAAANQADCggJDgAAAA==.Khazargon:BAAANQADCggIFQAAAA==.',
Ki='Kicken:BAAANQAECgMJBQAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECgQJBAAAAA==.',
Ko='Korthelan:BAAANQAECgYIEQAAAA==.Kothara:BAAANQAECgUICQAAAA==.',
Kr='Krimzin:BAACNQAFFIEFAAIBAAMKRRXVBwARAQABAAMKRRXVBwARAQA1AAQKgSEAAgEACQobI7kPACUDAAEACQobI7kPACUDAAAA.Krystine:BAAANQADCggJHgAAAA==.',
Ks='Kserasera:BAAANQAECgUJCwAAAA==.',
Ku='Kuball:BAAANQAECgUIDQAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAAANQAECgcIDAAAAA==.Letheos:BAABNQAECoElAAINAAgKNyJNDgD/AgANAAgKNyJNDgD/AgAAAA==.',
Li='Librarte:BAAANQAECgcIDgAAAA==.Litty:BAAANQAECgQICAAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBAABNQAFFAIIBQAOADASAA==.Lox:BAAANQAECgUICQAAAA==.',
Ly='Lydirn:BAAANQADCgUIBgAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQABCgIIAgAAAA==.Magicguy:BAAANQAECgUJCwAAAA==.Mahariel:BAAANQAECgUICgAAAA==.Mahdy:BAABNQAECoEbAAIJAAcKfBFHegCPAQAJAAcKfBFHegCPAQAAAA==.Malva:BAAANQAECgUIBQAAAA==.Marcie:BAAANQAECgUICgAAAA==.Marracopa:BAAANQABCgYJBQAAAA==.Martinriggz:BAAANQAECgEIAQAAAA==.',
Me='Meatyloaf:BAAANQAECgQJBwAAAA==.Medsedation:BAAANQAECgYJEwAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECgcICAAAAA==.',
Mi='Mirei:BAAANQAECgMJBQAAAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgIIBAAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUJBQABNQAECgUJDwAEAAAAAA==.',
My='Mythantherox:BAAANQADCgcIDQABNQAECgkJIAAPACkjAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAAANQAECgIJAgAAAA==.Netherstörm:BAAANQAECgMJAwAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.Niraani:BAAANQADCggJCwAAAA==.',
No='Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAAANQAECgYIEQAAAA==.',
Ny='Nymneria:BAAANQAECgQJBwAAAA==.Nyxiera:BAAANQAECgcIEwABNQAECggIGgAQANsUAA==.Nyxstonia:BAABNQAECoEaAAQQAAgK2xRMCwD5AQAQAAgK2xRMCwD5AQARAAIK7gYAHABfAAAKAAEK2AE9CQEhAAAAAA==.',
['Nä']='Nämi:BAAANQAECgEIAQAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgEJAQAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAAANQAECgUICQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Pampoovy:BAEANQADCgYJBgABNQAECgUIDQAEAAAAAA==.',
Pe='Persephoneia:BAAANQAECgUIDQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Pr='Preacherman:BAAANQADCggJDgAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Purplevane:BAAANQAECgMIAwAAAA==.',
Ra='Rabies:BAAANQABCgcIBwAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMJAwABNQAECgUIBwAEAAAAAA==.Ravenloare:BAAANQADCgUIBQAAAA==.',
Re='Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAAANQAECgUIDQAAAA==.',
Ro='Rockasham:BAAANQAECgYJDAAAAA==.Rottn:BAAANQAECgUIBwAAAA==.',
Sa='Safmen:BAAANQADCggIEgAAAA==.Saintdivine:BAAANQADCgEIAQAAAA==.Sanikoa:BAAANQADCggJDgAAAA==.Saraid:BAAANQAECgUIDQAAAA==.Saravase:BAAANQADCgUIBQAAAA==.Saurot:BAAANQADCgcJCQAAAA==.',
Se='Sev:BAAANQADCgUIBwAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEANQAECggIDwAAAA==.Shadowstorm:BAAANQAECgYIEQAAAA==.Shiki:BAAANQADCgcJBwABNQAECgMJBQAEAAAAAA==.Shinoto:BAAANQADCgYIDQABNQAECgIIAgAEAAAAAA==.',
Si='Silvein:BAAANQAFFAIIAgAAAA==.Silverpower:BAAANQADCgIIAgAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAAEAAAAAA==.',
Sp='Spycatcher:BAAANQADCgEIAQAAAA==.Spyro:BAAANQAECgUICwAAAA==.',
Sr='Sron:BAAANQAECgcIDQAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Sw='Swooze:BAABNQAECoEZAAMSAAgKJxaGdAA2AgASAAgKBhWGdAA2AgATAAEKgBJALABBAAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgUICAAEAAAAAA==.',
Sz='Szuzette:BAAANQAECgIJAgABNQAECgUICAAEAAAAAA==.',
Ta='Tankcontrols:BAAANQADCgYJDAAAAA==.Tarlyn:BAAANQAECgQIBwABNQAECgUIBgAEAAAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQADCgYICAABNQAECgEIAgAEAAAAAA==.Thunderkatze:BAAANQAECgcIDgAAAA==.Thánátós:BAAANQADCggJDQAAAA==.',
To='Topu:BAAANQAECgMJBgAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Un='Unacceptable:BAAANQAECgUICAAAAA==.',
Us='Usdaprime:BAAANQAECgYJDAAAAA==.',
Va='Valhalia:BAAANQAECgEIAQAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.',
Ve='Velinariae:BAAANQADCgMIBAAAAA==.Vengful:BAAANQAECgUICAAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQADCgcJDQAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgQIBgAAAA==.',
Wa='Wali:BAAANQAECgUICgAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAAANQADCggIFwABNQAECgYICwAEAAAAAA==.',
Wy='Wyleriya:BAAANQAECgYIDgAAAA==.',
Xc='Xcella:BAAANQADCgcJGQAAAA==.',
Xu='Xurael:BAAANQAECgIIAgAAAA==.',
Ye='Yelhsa:BAAANQAECgEIAQAAAA==.Yelizaveta:BAAANQAECgEIAwAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgIJAgAAAA==.',
Za='Zalarah:BAAANQADCggJFgAAAA==.Zardan:BAAANQAECgEIAQAAAA==.',
Ze='Zeppik:BAAANQADCgQIBAAAAA==.',
Zu='Zuggerker:BAAANQAECgUICgAAAA==.',
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
