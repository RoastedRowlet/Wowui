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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Havoc','Priest-Holy','Druid-Balance','DemonHunter-Devourer','Shaman-Elemental','Warrior-Fury','Evoker-Devastation','Paladin-Protection','Warrior-Protection','Hunter-Survival','Shaman-Enhancement','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abracadavr:BAAANQADCgUJCQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECoE9AAIBAAkK8SHhCAB4AwABAAkK8SHhCAB4AwAAAA==.',
Ad='Addison:BAAANQAECgQICAAAAA==.Adeleas:BAAANQADCggIFgABNQAECgQIBAACAAAAAA==.Adêrna:BAABNQAECoEdAAIDAAcKOhu4RAABAgADAAcKOhu4RAABAgAAAA==.',
Ag='Agba:BAABNQAECoEbAAMEAAcKqxSbQQCwAQAEAAcKqxSbQQCwAQAFAAEKqAmWiQArAAAAAA==.',
Ai='Aibrean:BAAANQAECgIIAgAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksel:BAAANQADCgQIBAAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgUIBwAAAA==.Alanus:BAAANQAECgYIEgAAAA==.Alarion:BAAANQAECgQIBAAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQADCggIHAAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQADCgUICAAAAA==.Annahe:BAAANQAECgYIEwAAAA==.Annale:BAAANQADCgYIBgABNQAECgYIEwACAAAAAA==.Anub:BAAANQAECgcIEwAAAA==.Anzala:BAAANQAECgMIAwAAAA==.',
Ar='Armsmaster:BAABNQAECoEjAAIEAAgKxCDTFwDDAgAEAAgKxCDTFwDDAgAAAA==.Arrann:BAAANQADCggIFwAAAA==.Artemistha:BAAANQAECgUICAAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
['Aø']='Aøi:BAACNQAFFIEJAAIGAAYKbRs6AgAfAgAGAAYKbRs6AgAfAgA1AAQKgRkAAgYACQqEJE8DAI4DAAYACQqEJE8DAI4DAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAAANQADCggICQAAAA==.Barelycastin:BAAANQAECgYIEwAAAA==.',
Be='Beautiful:BAAANQADCgUIBQAAAA==.Beleriand:BAAANQAECgUIBwAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.',
Bl='Blacat:BAAANQAECggIEgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.Blitzcomets:BAAANQADCgcICwAAAA==.Bloodshunter:BAABNQAECoEbAAMBAAkKYh4HHQDvAgABAAgKRiAHHQDvAgAHAAUKYRHHNgA3AQAAAA==.Blutauren:BAAANQADCgMIAwAAAA==.',
Bo='Borda:BAAANQAECgUJCQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
Ca='Carini:BAAANQAECgYIEAAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECggIEwACAAAAAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgQIBAAAAA==.',
Cl='Clûtch:BAAANQAECgYIEgAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAAANQAECgUIDwAAAA==.',
Cr='Crickie:BAAANQAECgEIAQAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAAANQAECgYIEwAAAA==.',
Da='Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQADCggIAwAAAA==.Darktalyn:BAAANQAECgYIEwAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECoEcAAIIAAgKNxpBNwByAgAIAAgKNxpBNwByAgAAAA==.Deekura:BAAANQAECgQIBwAAAA==.Delusion:BAAANQADCgEIAQAAAA==.Dezireth:BAABNQAECoEhAAIBAAgKoQnoaADqAQABAAgKoQnoaADqAQAAAA==.',
Dh='Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIEwAAAA==.Dionan:BAAANQAECgYIEwAAAA==.',
Do='Docs:BAAANQAECgYICQAAAA==.Doks:BAAANQAECggIEAAAAA==.',
Dr='Dragana:BAAANQADCgYIEwAAAA==.Dragster:BAAANQADCgcIBwAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAYIFAAJALMBAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Es='Espe:BAAANQAECgYIEwAAAA==.',
Ev='Everayn:BAABNQAECoEuAAMJAAcKWxP4VgDMAQAJAAcKWxP4VgDMAQAKAAUKRgtK2QD0AAABNQAECgkJPQABAPEhAA==.',
Ex='Exhalo:BAABNQAECoEZAAILAAcKyRGShwCwAQALAAcKyRGShwCwAQAAAA==.',
Fa='Fallen:BAAANQAECgcIDgAAAA==.Fasebreaker:BAAANQABCgYIBQAAAA==.Faynor:BAAANQAECgUIDwAAAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.',
Fi='Finalycalm:BAAANQAECgQIBAAAAA==.Finimus:BAAANQAECgIJAgAAAA==.',
Fl='Flingpooh:BAAANQADCggICAAAAA==.Flloran:BAAANQAECgQIBgAAAA==.',
Fr='Fraggle:BAECNQAFFIEHAAIJAAMKCRM1DgD8AAAJAAMKCRM1DgD8AAA1AAQKgSYAAwkACQrZHMkUAAYDAAkACQrZHMkUAAYDAAoAAQpKDehCAToAAAAA.Frogchi:BAAANQAECgIIAwAAAA==.Frostbité:BAAANQADCggIGgAAAA==.Fruit:BAAANQAECgIIAgAAAA==.',
Fu='Fubarut:BAAANQABCggIDgAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAACAAAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQADCggIEAAAAA==.',
Gl='Glaistiguain:BAABNQAECoEdAAQMAAcKMiKzAgC0AgAMAAcKCyKzAgC0AgANAAMKeSGqKAAeAQAIAAEKSBW9/ABIAAABNQAECggIIwAEAMQgAA==.Glifin:BAAANQAECgEIAgAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgIIBgABNQAECgcIGwAOAN8QAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Gr='Gr:BAAANQAECgYIEQAAAA==.Gryffs:BAAANQAECgYIDQAAAA==.',
Gu='Gutts:BAAANQADCggIDgABNQAECgYIEwACAAAAAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgMJBAAAAA==.',
Ha='Halartion:BAAANQAECggIEwAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAYIEwAPAGwbAA==.',
He='Helridden:BAAANQADCggIDgAAAA==.Hesmydaddy:BAABNQAECoEaAAIQAAcKpAV9eABCAQAQAAcKpAV9eABCAQAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAABNQAECoEbAAIOAAcK3xBLTQB8AQAOAAcK3xBLTQB8AQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgMIBAACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJAwAAAA==.Jarrack:BAAANQAECgUIDwAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAAANQAECgYIEwAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAACAAAAAA==.',
Ji='Jivederpy:BAAANQAECgYICwAAAA==.',
Ju='Juicybooty:BAAANQADCgUIBgAAAA==.Junazeena:BAAANQAECgYIBwAAAA==.',
Ka='Kayfabe:BAAANQAECgcIEAAAAA==.',
Ke='Keirasti:BAAANQAECgQIBAAAAA==.Keishilda:BAAANQADCgYIDAAAAA==.Keladria:BAAANQAECgQIBAAAAA==.Kelirra:BAAANQADCgYIDgAAAA==.Kenel:BAABNQAECoEbAAIRAAcKTg7tQACkAQARAAcKTg7tQACkAQAAAA==.Kerea:BAAANQAECgUIDwAAAA==.Kermitt:BAAANQABCggJDAAAAA==.Keyarga:BAAANQADCgYICgABNQAECgQIBgACAAAAAA==.',
Kh='Khazadoom:BAAANQAECgQIBAAAAA==.Khazargon:BAAANQADCggIFQAAAA==.',
Ki='Kicken:BAAANQAECgQICQAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECggIDAAAAA==.',
Ko='Korthelan:BAABNQAECoEbAAISAAcKZxSKJADnAQASAAcKZxSKJADnAQAAAA==.Kothara:BAAANQAECgUIDgAAAA==.',
Kr='Krimzin:BAACNQAFFIEJAAIBAAQKuxbPCABUAQABAAQKuxbPCABUAQA1AAQKgSQAAgEACQo+JbQOAEcDAAEACQo+JbQOAEcDAAAA.Krystine:BAAANQAECgIIAgAAAA==.',
Ks='Kserasera:BAAANQAECgcIEgAAAA==.',
Ku='Kuball:BAAANQAECgYIEwAAAA==.Kumari:BAAANQADCgcICgAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAAANQAECgcIEwAAAA==.Letheos:BAABNQAECoEtAAIOAAgKQyI/EgDyAgAOAAgKQyI/EgDyAgAAAA==.',
Li='Librarte:BAAANQAECgcIEAAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAAANQAECgQICwAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBAABNQAFFAIIBQATADASAA==.Lox:BAAANQAECgUIDgAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIAQACAAAAAA==.',
Ly='Lydirn:BAAANQADCgUIBgAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAAANQAECgUIDwAAAA==.Mahariel:BAAANQAECgUICgAAAA==.Mahdy:BAABNQAECoEjAAIKAAgKwRRcaQAFAgAKAAgKwRRcaQAFAgAAAA==.Mahoe:BAAANQADCgEIAQAAAA==.Malva:BAAANQAECgYICwAAAA==.Marcie:BAAANQAECgUIDwAAAA==.Marracopa:BAAANQABCgYIBwAAAA==.Martinriggz:BAAANQAECgEIAgAAAA==.',
Mc='Mchammer:BAAANQADCgIIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQIBwAAAA==.Medsedation:BAABNQAECoEdAAIQAAcKlQ5IZQCIAQAQAAcKlQ5IZQCIAQAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECgcICAAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.',
Mi='Mirei:BAAANQAECgQICQAAAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgUICQAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUJBQABNQAECgcIFwAUAOYYAA==.',
My='Mythantherox:BAAANQADCgcIDQABNQAECgkJIgAVACkjAA==.',
Na='Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAAANQAECgQIBgAAAA==.Netherstörm:BAAANQAECgMIAwAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.Niraani:BAAANQADCggICwAAAA==.',
No='Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECoEbAAIWAAcKzxnsEwAWAgAWAAcKzxnsEwAWAgAAAA==.',
Ny='Nymneria:BAAANQAECgQIBwAAAA==.Nyxiera:BAABNQAECoEdAAIXAAgKQhBfEQCzAQAXAAgKQhBfEQCzAQABNQAECggIIQAXALoXAA==.Nyxstonia:BAABNQAECoEhAAQXAAgKuhdsDAAbAgAXAAgKuhdsDAAbAgAUAAIK7gY2IQBbAAALAAEK2AETKQEhAAAAAA==.',
['Nä']='Nämi:BAAANQAECgEIAgAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgMIAwAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAAANQAECgUIDgAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECggIGAAYAA0VAA==.',
Pe='Persephoneia:BAAANQAECgYIEwAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Po='Poraichu:BAAANQABCgYIBgAAAA==.',
Pr='Preacherman:BAAANQAECgMIAwAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Purplevane:BAAANQAECgMIAwAAAA==.',
Ra='Rabies:BAAANQABCgcIBwAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMJAwABNQAECgUIDAACAAAAAA==.Ravenloare:BAAANQADCgYICwAAAA==.',
Re='Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAAANQAECgYIEwAAAA==.',
Ro='Rockasham:BAAANQAECgYIEgAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAAANQAECgUIDAAAAA==.',
Sa='Safmen:BAAANQAECggICAAAAA==.Saintdivine:BAAANQADCgEIAQAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAAANQAECgYIEwAAAA==.Saravase:BAAANQADCgcICAAAAA==.Saurot:BAAANQADCgcICQAAAA==.',
Se='Sev:BAAANQADCgUIBwAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECoEYAAMOAAcKSBa2PQDJAQAOAAcKSBa2PQDJAQAFAAIKAAAomwAAAAAAAA==.Shadowstorm:BAABNQAECoEbAAIZAAcKvhfbEAATAgAZAAcKvhfbEAATAgAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECgQICQACAAAAAA==.Shinoto:BAAANQADCgYIDQABNQAECgUIBwACAAAAAA==.',
Si='Silvein:BAABNQAECoEYAAMJAAkKtSAKDABIAwAJAAgKbyMKDABIAwAWAAEKvgliYAAjAAAAAA==.Silverpower:BAAANQADCgIIAgAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Sn='Snowynn:BAAANQADCgEIAQAAAA==.',
Sp='Spycatcher:BAAANQADCgMIBAAAAA==.Spyro:BAAANQAECgcIEgAAAA==.Spyroo:BAAANQAECgYIBgAAAA==.',
Sr='Sron:BAAANQAECggIEwAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Sw='Swooze:BAABNQAECoEZAAMaAAgKJxa1jwAeAgAaAAgKBhW1jwAeAgAbAAEKgBLqNAA/AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgUIDAACAAAAAA==.',
Sz='Szuzette:BAAANQAECgMIBQABNQAECgQICAACAAAAAA==.',
Ta='Tankcontrols:BAAANQADCggIEgAAAA==.Tarlyn:BAAANQAECgQIBwABNQAECgYIDAACAAAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQADCgcICQABNQAECgQIBgACAAAAAA==.Thunderkatze:BAABNQAECoEYAAIZAAgKHQqqEgDtAQAZAAgKHQqqEgDtAQAAAA==.Thánátós:BAAANQADCggJDQAAAA==.',
To='Topu:BAAANQAECgUICwAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Un='Unacceptable:BAAANQAECgUIDgAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgkJHwAHAKEjAA==.',
Us='Usdaprime:BAAANQAECgcIEwAAAA==.',
Va='Valhalia:BAAANQAECgYIBwAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.',
Ve='Velinariae:BAAANQADCgMIBAAAAA==.Vengful:BAAANQAECgYIDgAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgQIBAAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAAANQAECgYIEAAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAAANQADCggIHQABNQAECggIEAACAAAAAA==.',
Wy='Wyleriya:BAAANQAECgYIDgAAAA==.',
Xc='Xcella:BAAANQADCggIIQAAAA==.',
Xu='Xurael:BAAANQAECgUIBwAAAA==.',
Ye='Yelhsa:BAAANQAECgEIAgAAAA==.Yelizaveta:BAAANQAECgEIBQAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgIIAgAAAA==.',
Za='Zalarah:BAAANQAECgQIBAAAAA==.Zardan:BAAANQAECgIIAwAAAA==.',
Ze='Zeppik:BAAANQADCgQIBAAAAA==.',
Zu='Zuggerker:BAAANQAECgUIDwAAAA==.',
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
