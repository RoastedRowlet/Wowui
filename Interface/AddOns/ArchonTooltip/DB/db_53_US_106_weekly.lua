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

local lookup = {'DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Monk-Brewmaster','Unknown-Unknown','DemonHunter-Vengeance','Rogue-Assassination','Shaman-Enhancement','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Unholy','Priest-Holy','Warrior-Arms','Warrior-Fury','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Evoker-Devastation','Mage-Arcane','Monk-Mistweaver','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adobo:BAAANQADCgIJAgAAAA==.',
Af='Aft:BAACNQAFFIEFAAIBAAMKohF3DADSAAABAAMKohF3DADSAAA1AAQKgR4AAgEACQpgJHcDAKQDAAEACQpgJHcDAKQDAAAA.',
Ai='Aislin:BAAANQAECgMJAwAAAQ==.',
Ak='Akumu:BAAANQAECgYIDwAAAA==.',
Al='Alarkin:BAACNQAFFIEFAAMCAAMKug37CAAAAQACAAMKug37CAAAAQADAAIKTwRnEgB9AAA1AAQKgSgAAwMACQoVH90NAMkCAAMACQocG90NAMkCAAIABwphIHc0AGICAAAA.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAABNQAECoEXAAIEAAgKUhSeBQAyAgAEAAgKUhSeBQAyAgAAAA==.Aldoan:BAAANQADCggIGgAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQADCgIJAgAAAA==.Alistiri:BAAANQAECgUICwAAAA==.Alix:BAAANQAECgEJAQAAAA==.Allforge:BAAANQAECgIJBgAAAA==.Almina:BAAANQAECgQIBQAAAA==.Alpal:BAACNQAFFIEFAAIFAAMKUA7ZCgD1AAAFAAMKUA7ZCgD1AAA1AAQKgSkAAgUACQrkHV4NACQDAAUACQrkHV4NACQDAAAA.',
Am='Ambs:BAAANQAECgQJCgAAAA==.',
An='Analyse:BAAANQABCgIIAgAAAA==.Andalya:BAAANQAECgUIBwAAAA==.Andaria:BAAANQADCggJBQAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIDgAAAA==.',
Ap='Aprix:BAAANQAECgYJDAAAAA==.',
Ar='Aralyn:BAAANQADCgYIBgAAAA==.Arejay:BAAANQAECgEJAgAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAAANQAECgUJDgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgUJCQAAAA==.Arthurleywin:BAAANQAECgUJDwAAAA==.Arvis:BAAANQADCggJGwAAAA==.',
As='Asamia:BAACNQAFFIEKAAIGAAUKJg3dAQBMAQAGAAUKJg3dAQBMAQA1AAQKgR4AAgYACQoRIsoCADYDAAYACQoRIsoCADYDAAAA.Ashaki:BAAANQAECgYJCwAAAA==.Astå:BAAANQADCggICAAAAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auralius:BAAANQADCgMJAwAAAA==.Auroramoon:BAAANQAECgEJAgAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.',
Aw='Awake:BAAANQAECgcJEwAAAA==.',
Ax='Axionar:BAAANQAECgcJCwAAAA==.',
Az='Azshauria:BAAANQABCgYICQAAAA==.Azurend:BAAANQAECgQIBwAAAA==.Azázél:BAAANQAECgMIBAAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCggIGQABNQAECgcJEgAHAAAAAA==.Bahula:BAAANQAECgUICwAAAA==.Bainehuln:BAAANQAECgQIBAAAAA==.Bastianos:BAAANQAECgUICgAAAA==.Batsom:BAAANQABCgEIAQAAAA==.Battlecheeks:BAAANQADCgQIBAAAAA==.',
Be='Bellapearl:BAAANQAECgQIBQAAAA==.Bellmont:BAAANQAECgEJAQAAAA==.Belron:BAAANQAECgIIAwABNQAECggJGQAIAGYKAA==.Bernes:BAAANQAECgcIEwAAAA==.',
Bi='Bigteef:BAAANQADCgUICQAAAA==.Birdhouse:BAAANQAECgQICAAAAA==.',
Bl='Blackthornn:BAACNQAFFIEFAAIJAAMKgRg0BAAUAQAJAAMKgRg0BAAUAQA1AAQKgSkAAgkACQqaIGQFAD0DAAkACQqaIGQFAD0DAAAA.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECggJGwAKAO4YAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Blottros:BAAANQAECgQJBAAAAA==.Blottzilla:BAACNQAFFIEFAAILAAMKlgWVCQDbAAALAAMKlgWVCQDbAAA1AAQKgSkAAgsACQoHGj0KAMMCAAsACQoHGj0KAMMCAAAA.Bluestreak:BAAANQADCgcJEQAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAABNQAECoEZAAIFAAgKrhsNIACZAgAFAAgKrhsNIACZAgAAAA==.Bowbuttkick:BAACNQAFFIEFAAMCAAQK3hl1BgAuAQACAAMK/yF1BgAuAQADAAEKeQGJGAA2AAA1AAQKgRoAAwIACQoWIyoLAE8DAAIACQoWIyoLAE8DAAMAAgoHFBpMAHQAAAAA.Bowjangles:BAEANQAECgQJBAABNQAECgQICAAHAAAAAA==.Boxiebrown:BAABNQAECoEfAAICAAkKpBQrMABzAgACAAkKpBQrMABzAgAAAA==.',
Br='Bralae:BAAANQAECgMIBgAAAA==.Breaya:BAAANQADCgQJBgAAAA==.Brewskiez:BAAANQADCgkJDQAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAACNQAFFIEIAAMMAAQKdh6PAgB7AQAMAAQKdh6PAgB7AQANAAIKRgllCgCYAAA1AAQKgSEAAw0ACQoaJYMKADwDAA0ACQrGI4MKADwDAAwACAqdIIcKAP8CAAAA.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAAANQAECgYIDwAAAA==.',
Bu='Bubbawoodkin:BAAANQAECgQIBAAAAA==.Buffpres:BAAANQADCgUIBQABNQAECgQIBgAHAAAAAA==.Buzzlez:BAACNQAFFIEFAAIOAAMKZA0bDgD4AAAOAAMKZA0bDgD4AAA1AAQKgSkAAg4ACQo9HQcMACIDAA4ACQo9HQcMACIDAAAA.',
Ca='Camspally:BAAANQAECgMJAwAAAA==.Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQJBAAHAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBwAAAA==.Chahae:BAACNQAFFIEFAAMNAAMKZBbkBAAdAQANAAMKZBbkBAAdAQAMAAEKQQefEABAAAA1AAQKgSwAAw0ACQqYJrUAAPYDAA0ACQqYJrUAAPYDAAwAAQrWJVJcAG4AAAAA.Channintotem:BAEANQAECgEIAQABNQAECgYJEAAHAAAAAA==.Cheerwine:BAAANQAECgYJEQAAAA==.Cheezits:BAAANQADCgUIBQAAAA==.',
Cl='Clapdo:BAECNQAFFIEIAAIPAAQKEBvACQBmAQAPAAQKEBvACQBmAQA1AAQKgSEAAw8ACQqhJMALAHwDAA8ACQqhJMALAHwDABAAAQo1G9IeAEYAAAAA.Clinician:BAAANQAECgcIBwAAAA==.',
Co='Commandor:BAAANQADCgEJAQAAAA==.Congolense:BAAANQAECgYICwAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cougrogue:BAAANQAECgQIBAAAAA==.Cowacusrex:BAAANQAECgEIAQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAAANQAECgcIDAAAAA==.Creamer:BAAANQAECgYJEAAAAA==.Crunchin:BAABNQAECoEmAAMRAAkKcRXVUgALAgARAAgKSRTVUgALAgAFAAkKCAQ4TwC1AQAAAA==.',
Cu='Cutedwarfxd:BAACNQAFFIEIAAIBAAQK5h75BQB7AQABAAQK5h75BQB7AQA1AAQKgSEAAgEACQrhJQcCAMIDAAEACQrhJQcCAMIDAAAA.',
Da='Dakkadakka:BAAANQAECgMIAgAAAA==.Damane:BAAANQADCgUJBQABNQAECgQIBAAHAAAAAA==.Danìel:BAACNQAFFIEFAAISAAMKbBdUBwD4AAASAAMKbBdUBwD4AAA1AAQKgSkAAxIACQrJIUkFAHMDABIACQqZIUkFAHMDABMACAq9FZIdABECAAAA.Darkarts:BAAANQADCgIIAgAAAA==.Dartwo:BAAANQAECgEJAQAAAA==.',
De='Deathspoons:BAACNQAFFIELAAIBAAUKuhhpBQCRAQABAAUKuhhpBQCRAQA1AAQKgSQAAgEACQqrId0HAFQDAAEACQqrId0HAFQDAAAA.Delecto:BAAANQAECgQJBwAAAA==.Delmônico:BAAANQADCgYIBgAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAACNQAFFIEFAAMUAAMKVB7+BwC3AAAUAAIKfxr+BwC3AAAJAAEK/SUaCgBwAAA1AAQKgSYAAxQACQrHJSYJAL8CABQABwrzIyYJAL8CAAkABAomJQklALABAAAA.Derkamental:BAAANQAECgIIAgAAAA==.',
Di='Digallo:BAAANQADCggJFwAAAA==.Dimsumbun:BAAANQAECgQJBwAAAA==.Dingledorf:BAAANQAECgYIEAAAAA==.Dinklebahmp:BAAANQAECgEIAQABNQAFFAMJBQAVANcaAA==.Dinoxeye:BAAANQAECgQIBwAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Dragonpandas:BAAANQADCggJCAABNQAECgkJJAANAPofAA==.Dramonk:BAACNQAFFIEGAAIWAAQKCAghBQAJAQAWAAQKCAghBQAJAQA1AAQKgSAAAhYACQpKIuEFAD4DABYACQpKIuEFAD4DAAAA.Dro:BAAANQABCgIIAgAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggJBQAAAA==.',
Ei='Eir:BAAANQAECgcJDwAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.Eltariel:BAAANQADCgQIBAABNQAECgQJBAAHAAAAAA==.',
Em='Emeraldjin:BAAANQAECgYJDQAAAA==.',
En='Ensera:BAAANQAECgMIAwAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgUJCQAAAA==.Ernet:BAAANQAECgUIDgAAAA==.',
Ex='Extraho:BAAANQAECgYIEAAAAA==.',
Fa='Fabled:BAACNQAFFIEIAAMXAAQKqRjiBAC9AAAYAAMKOhYTDQD2AAAXAAIK7h3iBAC9AAA1AAQKgSEAAxcACQr5IlADAOwCABcACAp8IFADAOwCABgABAp4Iz5pAIkBAAAA.Faeyice:BAAANQAECgUICgAAAA==.',
Fe='Fearmachine:BAAANQADCggJFAABNQAECgcJCwAHAAAAAA==.Feyden:BAAANQAECgQICAAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAFFAQJCAABAOYeAA==.',
Fi='Fielton:BAAANQADCgEIAQABNQAECgcJDwAHAAAAAA==.Fiiryazell:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAAANQAECgUJCQAAAA==.Fijaswitcher:BAAANQAECgUJBwAAAA==.Fimbulvargr:BAAANQAECgUICgAAAA==.Finiith:BAAANQAECgUJBgABNQAFFAMJBQACALoNAA==.Firedragön:BAAANQAECgEIAQAAAA==.',
Fl='Flogdanoggin:BAAANQADCgUIBQAAAA==.Flogurnoggin:BAAANQADCggIAQAAAA==.Fluffyokami:BAAANQAECgYJDQAAAA==.Flyingrodent:BAABNQAECoEZAAIZAAYKph6eDgAeAgAZAAYKph6eDgAeAgAAAA==.',
Fo='Foneer:BAAANQAECgYIDgAAAA==.Forestsky:BAAANQAECgQIBgAAAA==.',
Fr='Freezepop:BAABNQAECoEVAAIaAAgK7hoEVgCKAgAaAAgK7hoEVgCKAgAAAA==.Frenchieboi:BAAANQADCgcIDQABNQAECgYJDwAHAAAAAA==.Frenchielock:BAAANQAECgYJDwAAAA==.Frenchthyr:BAAANQAECgUICAABNQAECgYJDwAHAAAAAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Gaden:BAAANQAECgIJAgAAAA==.Galdiian:BAAANQAECgEIAQAAAA==.Gatebtch:BAAANQAECgQJBAAAAA==.Gawdspet:BAABNQAECoElAAMYAAkKrB1uNwBAAgAYAAcKyBxuNwBAAgAXAAQKGRdYJAAqAQAAAA==.',
Gh='Ghosi:BAAANQAECgcJEgAAAA==.',
Gl='Glaivier:BAAANQAECgMIBgAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAAANQAECgcIEwAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCggJFwAAAA==.',
Gr='Grampman:BAAANQADCgMIAwAAAA==.Gremory:BAAANQAECgQIBwAAAA==.Grimholt:BAAANQADCgIIAgAAAA==.',
Gu='Guldank:BAAANQAECgMJBQAAAA==.Guretta:BAAANQAECgUICgAAAA==.',
Gw='Gwynhwyvar:BAAANQAECgMJBQAAAA==.',
Ha='Haeneros:BAAANQAECgcIDAAAAA==.Handmemytank:BAAANQAECgIJAwABNQAECgkJGwACANIjAA==.Harumi:BAAANQAECgUJDgAAAA==.',
He='Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQAECgIJAgAAAA==.Hedgehog:BAABNQAECoEZAAIbAAgKrwmWFgCJAQAbAAgKrwmWFgCJAQAAAA==.Heightning:BAAANQAECgQIBgAAAA==.Heisenberf:BAABNQAECoEoAAIaAAkKyh0DNgDrAgAaAAkKyh0DNgDrAgAAAA==.Hextrathicc:BAABNQAECoEeAAIYAAgKFhe/LgBlAgAYAAgKFhe/LgBlAgAAAA==.',
Ho='Hofnarr:BAAANQAECggICAAAAA==.Holybuttkick:BAAANQAECgYJDwABNQAFFAQJBQACAN4ZAA==.Hoozurdaddy:BAAANQAECgYJEAAAAA==.',
Ia='Iamdownhere:BAAANQABCgYICgAAAA==.',
Ic='Icê:BAAANQAECgYICwAAAA==.',
Ig='Igamm:BAAANQADCgYJCQAAAA==.Ignatius:BAAANQAECgIJAwAAAA==.Igniting:BAABNQAECoEcAAIaAAgKqRQnbABNAgAaAAgKqRQnbABNAgABNQAECgMIBgAHAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgUJCgAAAA==.Ikki:BAAANQAECggJCgAAAA==.',
Im='Impenetrable:BAAANQADCgcIBwAAAA==.Impression:BAACNQAFFIEIAAIFAAQKaB0qBQCgAQAFAAQKaB0qBQCgAQA1AAQKgRkAAgUACQqTJkgAAPUDAAUACQqTJkgAAPUDAAAA.Imprison:BAAANQAECgEIAQABNQAFFAQJCAAFAGgdAA==.',
In='Incarnated:BAAANQAECgcJDgAAAA==.Incursion:BAAANQAECgcIEAAAAA==.Insayn:BAAANQADCgIIAgABNQAECgcIDwAHAAAAAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Ir='Ironwolf:BAABNQAECoEZAAIVAAgKtAhoEgBmAQAVAAgKtAhoEgBmAQAAAA==.',
Ja='Jademoot:BAAANQAECgUICgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIJAgAAAA==.Jaylaah:BAAANQAECgMJAwAAAA==.Jayvlyn:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.',
Jj='Jjman:BAAANQAECgYIBwABNQAECgcJDwAHAAAAAA==.Jjuicyfruit:BAAANQADCgYJEgAAAA==.',
Jo='Joftokal:BAAANQAECgYJCwAAAA==.Jokesonme:BAAANQAECgEJAQAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAAANQAECgcJEwAAAA==.',
Ka='Kakiso:BAAANQAECgUIDQAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAABNQAECoEkAAIKAAkKMiPrAQB8AwAKAAkKMiPrAQB8AwAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQADCgYICQAAAA==.',
Kh='Khailyn:BAAANQADCgIJAgAAAA==.',
Ki='Kikuu:BAAANQAECgYJDAAAAA==.Kin:BAAANQADCgYJBgAAAA==.Kincaid:BAAANQABCgIIAgAAAA==.Kiradanna:BAABNQAECoEcAAITAAgKtxeuFwBWAgATAAgKtxeuFwBWAgAAAA==.Kiroa:BAAANQAECgIIBAAAAA==.Kitå:BAEANQAECgQICAAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAAANQAECgYIDwAAAA==.',
Ko='Koff:BAACNQAFFIEGAAIbAAQKgCSTAQCzAQAbAAQKgCSTAQCzAQA1AAQKgRcAAhsACQojJSEBAKsDABsACQojJSEBAKsDAAAA.Koino:BAAANQADCggICAAAAA==.Koreshei:BAAANQAECgMIAwAAAA==.',
Kr='Krixxus:BAAANQAECgQJBwAAAA==.',
Ku='Kuni:BAAANQAECgUICgAAAQ==.Kurius:BAAANQABCgIIAgAAAA==.Kuzan:BAAANQAECgMJAwAAAA==.',
Ky='Kylian:BAAANQAECgQIBAABNQAECggIHAATALcXAA==.',
La='Lamynx:BAAANQAECgUIDQAAAA==.Lazydragon:BAAANQAECgQJCQAAAA==.',
Le='Lelouch:BAAANQAECgMIAwAAAA==.Leone:BAAANQAECgQIBAABNQAECgYIDwAHAAAAAA==.',
Li='Liberation:BAAANQAECgYJEgAAAA==.Lilgirlblue:BAAANQAECgYICwAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECoEkAAMXAAkKdAkwHABuAQAXAAcKQQgwHABuAQAYAAYKVQiGgABCAQAAAA==.Lineste:BAAANQAECgQIBwAAAA==.Lion:BAAANQAECgYJDgAAAA==.',
Ll='Llyolis:BAAANQADCgcJCQABNQAECgQJBwAHAAAAAA==.',
Lo='Loldie:BAAANQAECgUJBgAAAA==.Lonepanda:BAACNQAFFIEFAAIVAAMK1xqKAQABAQAVAAMK1xqKAQABAQA1AAQKgSkAAhUACQoNJEgBAJcDABUACQoNJEgBAJcDAAAA.Lorwynx:BAABNQAECoEhAAIaAAkK+x4kIgAvAwAaAAkK+x4kIgAvAwAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgcIDwAHAAAAAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQADCggJGgAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Maalk:BAAANQADCgQJBAAAAA==.Mabellah:BAAANQADCggJMgAAAA==.Maemikyu:BAABNQAECoEkAAIOAAgKmx+aGwCsAgAOAAgKmx+aGwCsAgAAAA==.Magusultimis:BAAANQAECgUJBgAAAA==.Mahöshöjo:BAAANQADCgcIEQAAAA==.Maintank:BAAANQAECgUIDgAAAA==.Makepoop:BAAANQAECgcJEwAAAA==.Maloa:BAAANQADCgYIBgAAAA==.Manbomanbo:BAAANQAECgQIBAABNQAECggIBAAHAAAAAA==.Marianita:BAAANQAECggIEAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQAECgEJAQAAAA==.Melfist:BAAANQAECgMIAwAAAA==.Melysse:BAAANQAECgUJDQAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.Mereo:BAAANQAECgQJBgAAAA==.',
Mi='Mikiko:BAAANQAECgYJEQAAAA==.Mikto:BAAANQADCgEJAQAAAA==.Millcreek:BAAANQAECgQIBwAAAA==.Milliananeko:BAAANQADCgUICQABNQAECgMJBAAHAAAAAA==.Miracat:BAAANQAECgMJBQAAAA==.Missindragon:BAAANQAECgYJCwAAAA==.',
Mo='Moomoohead:BAAANQADCgMJBAABNQADCgQIBAAHAAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAAANQAECgUICgAAAA==.Morticus:BAAANQAECgQJBAAAAA==.',
Ms='Msthea:BAAANQAECgEJAgAAAA==.',
['Mä']='Mälina:BAAANQADCgcIEQAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narru:BAABNQAECoEnAAQCAAkKryTqAgC5AwACAAkKryTqAgC5AwADAAUK6grINQD9AAAcAAQK4Qr9CQDGAAAAAA==.',
Ne='Nebyula:BAAANQAECgQJBAAAAA==.',
Ni='Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAAANQAECgEIAgAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQADCgYIBgABNQAECgkJKAAaAModAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQADCgUIBgABNQAECgcJEwAHAAAAAA==.',
Ny='Nykoleus:BAAANQAECgYICQAAAA==.Nylokar:BAAANQADCgQIBAAAAA==.',
Oa='Oatbreaker:BAAANQADCgQJBAAAAA==.',
Og='Oggoat:BAAANQAECgIIAgAAAA==.',
Oz='Ozyy:BAAANQADCgYIBgAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Pallygranny:BAEANQAECgYJEAAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgEIAQAAAA==.',
Pi='Pibbs:BAABNQAECoEfAAIaAAkK8CDqJwAbAwAaAAkK8CDqJwAbAwAAAA==.',
Pl='Plaguepanda:BAABNQAECoEkAAQNAAkK+h80DgARAwANAAgKLCI0DgARAwAMAAUKgBQKPgAKAQABAAEKFRrolAA6AAAAAA==.Platinumcas:BAAANQADCgcJDwAAAA==.Pluribus:BAAANQADCgcJBwAAAA==.',
Po='Poohonroids:BAAANQAECgQJCgAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Protagoras:BAAANQAECgEIAgAAAA==.',
['Pä']='Pänz:BAAANQAECgUJBgAAAA==.',
Ra='Rafig:BAACNQAFFIEFAAIaAAMKxxwoFQAZAQAaAAMKxxwoFQAZAQA1AAQKgSkAAhoACQruJVEDANIDABoACQruJVEDANIDAAAA.Ragefyre:BAAANQAECgIJAgAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgcJDQABNQADCgUIBQAHAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAACNQAFFIEFAAIdAAMKSgRTDQDSAAAdAAMKSgRTDQDSAAA1AAQKgSgAAx0ACQpaFNs1ACkCAB0ACApnFNs1ACkCAB4ACQqLD5U7AAICAAAA.Ratbasterd:BAAANQADCgQIBAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayy:BAAANQAECgYIDQAAAA==.',
Re='Reeji:BAAANQADCgcJBwAAAA==.Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAAANQAECgYJDgAAAA==.Rexx:BAAANQADCgMIAwAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAABNQAECoEiAAMeAAgKlhwbIACTAgAeAAgKlhwbIACTAgAdAAEKYgh85wAtAAAAAA==.Riteaid:BAAANQAECgMJBQAAAA==.',
Ro='Robe:BAAANQAECgIJAwABNQAECgMJBAAHAAAAAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAAANQAECgYICwAAAA==.Rorthach:BAAANQAECgEJAQAAAA==.Roru:BAABNQAECoEfAAMYAAgKfRFERwABAgAYAAgKfRFERwABAgAXAAQK6wIORQCNAAAAAA==.Roseire:BAAANQAECgQIBwAAAA==.Rosethebrute:BAABNQAECoEeAAIPAAgK1RxZNACXAgAPAAgK1RxZNACXAgAAAA==.Rosetheholy:BAAANQAECgcJEQABNQAECggIHgAPANUcAA==.Rougeloving:BAABNQAECoEYAAIUAAkKSBk2CgCqAgAUAAkKSBk2CgCqAgAAAA==.',
Ru='Ruler:BAAANQAECgUIBgAAAA==.Ruli:BAABNQAECoEfAAICAAgKuh2gHwC+AgACAAgKuh2gHwC+AgAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECggJFgAdAMkcAA==.',
Ry='Ryshin:BAABNQAECoEiAAMJAAkKRBU1EwBmAgAJAAkKRBU1EwBmAgAUAAUK7wdjKAAoAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAAANQAECgcJDwAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQAECgEIAQABNQAECgQICAAHAAAAAA==.Sanctano:BAAANQAECgUJCAAAAA==.Saneras:BAAANQADCgYJCQAAAA==.Sarshia:BAAANQADCgYJCAAAAA==.Sayn:BAAANQAECgcIDwAAAA==.',
Sc='Schultzies:BAAANQAECgUICQAAAA==.',
Sd='Sdog:BAAANQAECgIIAQAAAA==.',
Se='Seanboyymage:BAABNQAECoEhAAIaAAkKYhvaMQD4AgAaAAkKYhvaMQD4AgAAAA==.Seina:BAAANQAECgUICgAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgQIBwAAAA==.Seulrene:BAAANQAECgYJEQAAAA==.',
Sh='Shamlaw:BAAANQAECgYJCwAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQAECgIIAgAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAAANQAECgUICQAAAA==.Shhuffle:BAAANQAECgcJEgAAAA==.Shiv:BAAANQAECgUJBQAAAA==.Shockuse:BAAANQADCgUJBQAAAA==.Shorukin:BAAANQADCgMJAwAAAA==.Shupasins:BAABNQAECoEbAAMeAAgKaB95JQBzAgAeAAcKVR95JQBzAgAdAAgKSxT1OgAPAgAAAA==.Shyamablue:BAAANQAECgUJBgAAAA==.',
Si='Silvercas:BAAANQAECgUIDAAAAA==.Simpleyfire:BAABNQAECoEWAAMdAAgKyRxkHgC7AgAdAAgKyRxkHgC7AgAeAAEKegV8zwA5AAAAAA==.',
Sk='Skullet:BAAANQAECgUJCwAAAA==.Skurmpls:BAAANQADCgcIBwABNQAECgQJBwAHAAAAAA==.',
Sl='Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAAANQAECgUJDQAAAA==.',
Sm='Smooth:BAABNQAECoEZAAMaAAgKJhOKggARAgAaAAgKERKKggARAgAEAAQKNhI+FADqAAAAAA==.',
Sn='Snaphance:BAAANQAECgUIBgAAAA==.Sneekypete:BAAANQADCgYJBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Snipercat:BAAANQAECgYJDgAAAA==.Snuffles:BAAANQAECgUJCQAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solange:BAAANQADCgYIBgAAAA==.Sorscha:BAAANQADCggIDwAAAA==.',
Sp='Spammy:BAABNQAECoEYAAIFAAkKwhQZJwBvAgAFAAkKwhQZJwBvAgAAAA==.Sparlyy:BAACNQAFFIEFAAIfAAMKCiOMBQA7AQAfAAMKCiOMBQA7AQA1AAQKgSkAAx8ACQonJmgAAPIDAB8ACQonJmgAAPIDAA4AAQpdC1OrADIAAAAA.Spectrality:BAAANQAECgEIAQABNQAECgMJBAAHAAAAAA==.',
Ss='Sswordy:BAACNQAFFIEFAAICAAMKxxIOCAAOAQACAAMKxxIOCAAOAQA1AAQKgTAAAgIACQoPIEcLAE4DAAIACQoPIEcLAE4DAAAA.Sswordyvani:BAAANQADCgYIDAABNQAFFAMJBQACAMcSAA==.',
St='Stimulus:BAAANQAECgYJCwAAAA==.Stinkynuuts:BAAANQADCggJHAAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgMJBAAAAA==.',
Su='Sunkist:BAAANQAECgUJCAAAAA==.Sunwing:BAAANQADCgUJBQAAAA==.Surlym:BAAANQAECgYIEQAAAA==.',
Sw='Switchglaive:BAABNQAECoEZAAMIAAgKZgokDgAyAQASAAYKkAt9NgBJAQAIAAcKvAgkDgAyAQAAAA==.',
Sy='Sylphie:BAAANQAECgIJAgAAAA==.Symphemon:BAABNQAECoEnAAMTAAkKyw5AGwAqAgATAAkKkw5AGwAqAgASAAgKPArpKwCoAQAAAA==.Symphoid:BAAANQAECgMJBAAAAA==.Syseloris:BAAANQAECgcIEQAAAA==.Sythion:BAABNQAECoEcAAMZAAkKNRNSCwBtAgAZAAkKNRNSCwBtAgALAAcKlBBJGgCpAQAAAA==.',
['Sâ']='Sâlisbury:BAAANQADCgUIBAAAAA==.',
['Së']='Sëphy:BAAANQADCgcJDwAAAA==.',
Ta='Taediris:BAAANQADCgUJBQAAAA==.Taliiha:BAAANQAECgUIBgAAAA==.Tanao:BAAANQADCggIJgAAAA==.',
Te='Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECggJDgAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thopegor:BAAANQAECgIJAgAAAA==.Thundergunt:BAAANQAECgEIAQABNQAECggIGQAFAK4bAA==.',
Ti='Tianjin:BAAANQAECgEIAQAAAA==.Tintaglia:BAAANQAECgQIBwAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgUIBwAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAAANQAECgYJCwAAAA==.',
Tu='Tunawhale:BAAANQAECgEJAQAAAA==.',
Ty='Tyloriavis:BAAANQAECgIIAgAAAA==.',
Ul='Ulfberht:BAAANQADCggJCgAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgMIBgAHAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Unaware:BAAANQADCgcJBgAAAA==.Uncletouchie:BAAANQADCgIIAgAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.Valára:BAAANQABCgQIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Violentjudge:BAAANQAECgYJCwAAAA==.Violla:BAAANQAECgIIAwAAAA==.Virgocelest:BAAANQAECgMJBAAAAA==.Viridion:BAAANQAECgQIBgAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vorlos:BAAANQAECgcIDAABNQAECgcIEwAHAAAAAA==.',
Vr='Vreeg:BAAANQAECgQIBwAAAA==.',
Wh='Whiteflag:BAABNQAECoEnAAIRAAkKdCavAgDbAwARAAkKdCavAgDbAwAAAA==.Whoopington:BAAANQAECgEIAQAAAA==.Whyamialive:BAABNQAECoEoAAIBAAkKxyZcAAD6AwABAAkKxyZcAAD6AwAAAA==.',
Wi='Wickedwolfin:BAAANQABCgMIAwAAAA==.Willowes:BAEANQADCggICAABNQAFFAMIBQAOAH0JAA==.Willowest:BAEANQADCgYIBgABNQAFFAMIBQAOAH0JAA==.Willowing:BAEANQAECgcIDwABNQAFFAMIBQAOAH0JAA==.Willowish:BAECNQAFFIEFAAIOAAMKfQmPDgDwAAAOAAMKfQmPDgDwAAA1AAQKgSgAAw4ACQoQIjAFAHQDAA4ACQoQIjAFAHQDAB8AAQoGCChTADcAAAAA.Winterz:BAAANQAECgQIEgAAAA==.Wiskii:BAAANQAECgQIBwAAAA==.',
Wo='Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgUJBgABNQAFFAMJBQAWAM0JAA==.Wytnarthom:BAAANQADCggJCQABNQAFFAMJBQAWAM0JAA==.Wytohne:BAACNQAFFIEFAAMWAAMKzQmICACRAAAWAAIKdQ2ICACRAAAGAAEKfQJ5BgBAAAA1AAQKgSgAAxYACQpgGwkMAMECABYACQpgGwkMAMECAAYAAQq+FDMiADwAAAAA.',
Xa='Xaree:BAAANQAECgQIBwAAAA==.Xariá:BAAANQADCgYJCQABNQAECgMIAwAHAAAAAA==.',
Xc='Xcat:BAABNQAECoEdAAIRAAkKnxMTTgAcAgARAAkKnxMTTgAcAgAAAA==.',
Xy='Xydros:BAAANQABCggJDwAAAA==.Xymer:BAAANQAECgEJAQAAAA==.',
Yi='Yim:BAAANQAECggJEAAAAA==.Yismypetdead:BAAANQADCggJDQABNQAECgQJBwAHAAAAAA==.',
Yo='Yorshka:BAABNQAECoEbAAIOAAgKQBV+MQAvAgAOAAgKQBV+MQAvAgAAAA==.',
Yw='Ywach:BAAANQAECgIIAgAAAA==.',
['Yú']='Yúno:BAAANQAECggIEwAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAHAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAAHAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgQIBwAHAAAAAA==.Zalliea:BAAANQAECgEIAQAAAA==.',
Ze='Zeff:BAAANQAECgEJAQAAAA==.',
Zo='Zompt:BAAANQAECgEJAgAAAA==.Zorndk:BAAANQAECgUJCgAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQAECgEJAQAHAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Ön']='Öni:BAABNQAECoEiAAIVAAkKriMzAQCcAwAVAAkKriMzAQCcAwAAAA==.',
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
