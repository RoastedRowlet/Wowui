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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Holy','Paladin-Retribution','Evoker-Preservation','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Druid-Feral','Shaman-Elemental','Warlock-Affliction','Priest-Discipline','Evoker-Devastation','Monk-Brewmaster','Mage-Frost','Shaman-Enhancement','Evoker-Augmentation','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Warrior-Fury','Monk-Windwalker',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECoEbAAIBAAgKKRWlhgA0AgABAAgKKRWlhgA0AgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAABNQAECoEbAAICAAkKExn7MwCNAgACAAkKExn7MwCNAgAAAA==.',
Ae='Aedx:BAABNQAECoEcAAIDAAgKkBF0FwD/AQADAAgKkBF0FwD/AQAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECoEZAAIEAAgKqx/dOgCkAgAEAAgKqx/dOgCkAgABNQAECgIIAgAFAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAFAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAAANQAECgYICgAAAA==.Alvera:BAACNQAFFIEFAAIGAAMKSxXTCQDqAAAGAAMKSxXTCQDqAAA1AAQKgSMAAgYACQoJI0YMADADAAYACQoJI0YMADADAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
An='Ancestor:BAABNQAECoEZAAIHAAgKKA5tXAClAQAHAAgKKA5tXAClAQAAAA==.Angechi:BAEANQADCgIJAgABNQAECggIHQAIAN4HAA==.Angrydk:BAAANQADCggIJgAAAA==.Antisocial:BAABNQAECoEeAAIGAAkK9h/lDQAgAwAGAAkK9h/lDQAgAwABNQAECgkKHgAGAPYfAA==.',
Ar='Arm:BAABNQAECoEoAAQJAAkKsg2LHAD5AQAJAAkKsg2LHAD5AQAKAAUKVAl6ZgDdAAALAAIKuBKDNQBeAAAAAA==.Armee:BAABNQAECoEXAAIMAAgK7Bc3RQAKAgAMAAgK7Bc3RQAKAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAAANQAECgYIDAAAAA==.Aszea:BAAANQADCggIJgAAAA==.',
Ax='Axra:BAAANQAECgYIEgAAAA==.',
Az='Azairius:BAAANQADCggICAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgYIEAAAAA==.',
Ba='Balsin:BAABNQAECoEZAAINAAgKxyMFHwAZAwANAAgKxyMFHwAZAwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAcIFAAOAB0XAA==.Barlaf:BAABNQAECoEhAAICAAgKNB15MACaAgACAAgKNB15MACaAgABNQADCggIEgAFAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgQJCgAAAA==.Beeto:BAABNQAECoEmAAINAAkKrBW3lACPAQANAAkKrBW3lACPAQAAAA==.Belyndris:BAAANQAECgcIDgAAAA==.Benlian:BAEBNQAECoEdAAIIAAgK3gfOUwBfAQAIAAgK3gfOUwBfAQAAAA==.',
Bl='Blighty:BAAANQADCgYIBgAAAA==.Blâze:BAACNQAFFIEHAAIBAAQKwRmiFQBsAQABAAQKwRmiFQBsAQA1AAQKgR4AAgEACQpvGmpSALMCAAEACQpvGmpSALMCAAAA.',
Bo='Bonknsmash:BAABNQAECoEcAAIEAAgKORIQcQDyAQAEAAgKORIQcQDyAQAAAA==.Boof:BAABNQAECoEdAAIPAAgK1haZGQA5AgAPAAgK1haZGQA5AgAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECoEcAAIQAAgKXhIKIwDyAQAQAAgKXhIKIwDyAQAAAA==.',
Bu='Bubbleoshift:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAFAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgcIEQAFAAAAAA==.',
['Bó']='Bóba:BAACNQAFFIEXAAIOAAcKSB/+AACgAgAOAAcKSB/+AACgAgA1AAQKgSUAAg4ACQrCIxYEAF4DAA4ACQrCIxYEAF4DAAAA.',
['Bö']='Böba:BAAANQAFFAEIAgABNQAFFAcIFwAOAEgfAA==.',
Ca='Cadiva:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Cadroyd:BAAANQAECgYIBQAAAA==.Caelin:BAABNQAECoEgAAMRAAkK+g9cKAAJAgARAAgKyhFcKAAJAgASAAEKegH4XwAgAAAAAA==.Cailand:BAAANQAECgUIDQAAAA==.Caishana:BAABNQAECoEgAAIHAAgKfCKCEwACAwAHAAgKfCKCEwACAwAAAA==.Cambium:BAAANQAECgUIEAAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Catdude:BAAANQAECgQJBQAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECgcJBwAAAA==.Chopadk:BAABNQAECoEgAAIIAAkK6Q7NPwC9AQAIAAkK6Q7NPwC9AQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAAANQAECgYIDgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAAANQAECgUIDQAAAA==.Collateral:BAAANQADCgcIBwAAAA==.Colomel:BAAANQAECgUICAAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYJBgABNQAECgYIEAAFAAAAAA==.Conqbine:BAAANQADCgcIEwAAAA==.Corg:BAAANQADCgcIDAAAAA==.Countchocula:BAAANQAECgQIDAAAAA==.',
Cr='Crimmi:BAAANQAECgUICQAAAA==.Critzilla:BAAANQAECgQIBAAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgkJGQABAP4aAA==.Cyndle:BAABNQAECoEjAAIHAAkKbApcWAC0AQAHAAkKbApcWAC0AQAAAA==.',
Da='Daddythicc:BAABNQAECoEgAAIBAAgK9QuosgDRAQABAAgK9QuosgDRAQAAAA==.Darnwrath:BAAANQADCgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgIIAgAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgQIBAAFAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAAANQAECgYIEAAAAA==.',
Di='Diante:BAAANQADCggIEAAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAAANQAECgYIDAAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECoEeAAMTAAkKoA1XYQDkAQATAAkKOAtXYQDkAQAUAAMKJg1hPgC0AAAAAA==.',
Dr='Dracara:BAAANQAECggIEQAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAABNQAECoEbAAMSAAcKBREzKQC7AQASAAcKuhAzKQC7AQAVAAIKuwsYHwBmAAAAAA==.Drewish:BAABNQAECoEgAAIWAAgK/h8HBQDkAgAWAAgK/h8HBQDkAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAFAAAAAA==.Drizzle:BAABNQAECoEdAAISAAgKayLaCgATAwASAAgKayLaCgATAwAAAA==.Drktotem:BAAANQAECgcIEwAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFIEVAAIJAAYKsiDtAABMAgAJAAYKsiDtAABMAgA1AAQKgScAAgkACQq3IsgFAEMDAAkACQq3IsgFAEMDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAAANQAECgYIEgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgEIAQAAAA==.',
Ec='Echeyaket:BAAANQAECgUIEQAAAA==.',
Ed='Edonsian:BAABNQAECoEiAAIEAAgKrxaXXgAqAgAEAAgKrxaXXgAqAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgUIDwAFAAAAAA==.Elelusion:BAAANQAECgQIBAAAAA==.Elliekins:BAAANQAECgQIBAAAAA==.Ellunaris:BAEANQAECgcIBwABNQAECggIHQAIAN4HAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Endlessly:BAAANQADCggICAAAAA==.Enoka:BAABNQAECoEdAAIBAAgKhxgHhAA6AgABAAgKhxgHhAA6AgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAAANQAECgYIDwAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAABNQAECoEaAAIIAAgKhA2JSgCJAQAIAAgKhA2JSgCJAQAAAA==.',
Ex='Excessive:BAAANQADCggICwAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAAANQAECgUIBwAAAA==.Fariebubbles:BAAANQADCggIHwAAAA==.',
Fe='Felene:BAABNQAECoEXAAMXAAkKNhoaJAC9AgAXAAkKNhoaJAC9AgAHAAIK7A7D1ABkAAAAAA==.',
Fi='Firitako:BAAANQAECgMIBQAAAA==.',
Fr='Frailey:BAAANQAECgYIDwAAAA==.Frankiejr:BAAANQADCggIHQABNQAECgUICwAFAAAAAA==.Fraubles:BAAANQAECgIIAgAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQICAAAAA==.Frostpoptart:BAAANQAECgcIEgAAAA==.Frozenblade:BAABNQAECoEYAAIIAAgK1BYfNgDxAQAIAAgK1BYfNgDxAQAAAA==.',
Fu='Furball:BAAANQADCgYIBgABNQAECgkJHgATAFYgAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAAANQAFFAIIAwAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Gazze:BAAANQAECgYIEgAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAABNQAECoEdAAMTAAgK3xo7NwByAgATAAgK3xo7NwByAgAYAAQKoxdjDQA0AQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.',
Gl='Glassdance:BAAANQADCgcIBwAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Goonielama:BAABNQAECoEgAAIIAAkKdiCbCwA0AwAIAAkKdiCbCwA0AwABNQAFFAIIAwAFAAAAAA==.Goonietai:BAAANQAECgUICQABNQAECgkJKAABAF0eAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgEIAQABNQAECgkJLQATABkjAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAABNQAECoErAAIBAAkKIyFZKQAmAwABAAkKIyFZKQAmAwAAAA==.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFIETAAMGAAYKdR9lAwCmAQAGAAUKSB9lAwCmAQAIAAEKVSBLHQBaAAA1AAQKgSMAAgYACQpvJfEFAH8DAAYACQpvJfEFAH8DAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIDgAAAA==.Hanyuu:BAAANQAECgcIDwAAAA==.',
He='Heiter:BAABNQAECoEiAAIMAAgKKhrPNwBEAgAMAAgKKhrPNwBEAgAAAA==.Hellbound:BAABNQAECoEbAAMTAAgK5xV4UAAaAgATAAgKjxR4UAAaAgAUAAIKcBM+TQCBAAAAAA==.Hellinhunt:BAAANQAFFAEIAQAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECgcIEQAFAAAAAA==.Hornivore:BAAANQADCgcIDgAAAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECggIEQAFAAAAAA==.',
Ic='Icefrosting:BAAANQAECgYIDgAAAA==.',
Id='Idistroya:BAAANQAECgQJBgABNQAECgYIEwAFAAAAAA==.',
Ig='Iggnogg:BAAANQADCggIHwAAAA==.',
Ik='Ikura:BAABNQAECoEhAAQZAAkKMRP5CQB7AQAMAAkKgw8DRwACAgAZAAcKMg35CQB7AQAPAAEKbwh7agAlAAAAAA==.',
Il='Ilithiya:BAABNQAECoEZAAISAAgKHSSkBwBEAwASAAgKHSSkBwBEAwAAAA==.Ilk:BAAANQAECgUICgAAAA==.',
Im='Imangry:BAAANQADCgEJAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgYIEAAAAA==.Ishton:BAAANQAECggIEgAAAA==.Istompgnomes:BAAANQAECgYIEwAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jasøn:BAAANQADCgcIDgABNQAECgYIDgAFAAAAAA==.',
Je='Jecthyr:BAABNQAECoEXAAMOAAgKsRSuHgCiAQAOAAcKPBKuHgCiAQAaAAMKjw9dJgC7AAAAAA==.Jefeson:BAAANQAECgMIAwAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQADCggIDgAAAA==.',
Js='Jsdruid:BAAANQAECgQIBAAAAA==.',
Ka='Kaelosu:BAABNQAECoEpAAITAAkKDRwYIADRAgATAAkKDRwYIADRAgAAAA==.Kakum:BAAANQAECgEIAQAAAA==.Kaldrogo:BAAANQADCggIEQAAAA==.Kalnuggets:BAAANQAECgEIAQAAAA==.Kalrathen:BAABNQAECoEoAAMMAAkKyhb9JgCTAgAMAAkKyhb9JgCTAgAPAAEKewF4cwAZAAAAAA==.Kanda:BAABNQAECoEjAAICAAgKLBZvRQBRAgACAAgKLBZvRQBRAgAAAA==.Karsh:BAAANQAECgUIEQAAAA==.Kazadax:BAAANQAECgYIDQAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAAANQAECgYIEwAAAA==.',
Ki='Kienne:BAAANQAECgUIEAAAAA==.Kiljaedra:BAAANQADCgQIBAAAAA==.Kinomi:BAAANQADCgYJBgABNQAECgYIEAAFAAAAAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQAECgYIEQAAAA==.Korogar:BAAANQAECgIIAgAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgUICgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAQICAAGAIomAA==.Kronknar:BAAANQABCgQJBAABNQAECggIHgAXAIcYAA==.',
Ky='Kymira:BAABNQAECoEiAAIbAAgKgxr6CABYAgAbAAgKgxr6CABYAgAAAA==.',
La='Lace:BAABNQAECoEtAAMTAAkKGSMzCABoAwATAAkKEyIzCABoAwAUAAIKUyFRPAC8AAAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECoEfAAICAAgKBRgVQwBYAgACAAgKBRgVQwBYAgAAAA==.Lazarou:BAAANQADCgYIDgAAAA==.',
Le='Legsday:BAAANQADCgQJBQAAAA==.Lementz:BAACNQAFFIEOAAIXAAQK8BSlCgBNAQAXAAQK8BSlCgBNAQA1AAQKgSAAAhcACQrLH1sUACwDABcACQrLH1sUACwDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcJEgABNQADCggIEAAFAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAAANQAECgYIEgAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQAECggICAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECggJGQANAIscAA==.',
Lu='Lumpia:BAABNQAECoEVAAMGAAgK4hfjLwAVAgAGAAgK4hfjLwAVAgAIAAIKuwV0ngBSAAAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAABNQAECoEjAAMBAAgKHBaaiwAoAgABAAgKgROaiwAoAgAcAAEKASG7LABZAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECoEeAAMXAAgKhxhlXwCxAQAXAAgKhxhlXwCxAQAdAAEK/AghKQBFAAAAAA==.Malpractice:BAAANQABCgQIBAABNQAECgYIEAAFAAAAAA==.Maybesinged:BAABNQAECoEeAAIBAAgK5hU/iAAwAgABAAgK5hU/iAAwAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECoEjAAIaAAgKRiD9BgDvAgAaAAgKRiD9BgDvAgAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Miltank:BAABNQAECoEhAAINAAgKIx3yRAB6AgANAAgKIx3yRAB6AgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECoEZAAISAAkK9hYYFwB2AgASAAkK9hYYFwB2AgAAAA==.Mionn:BAAANQAECgUIDwAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAAANQAECgYIEgAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCgYJCwABNQAECgYICgAFAAAAAA==.Mooncake:BAABNQAECoEdAAMaAAgKKAkVGACIAQAaAAgKKAkVGACIAQAeAAIK1QJpGgBCAAAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Motoko:BAABNQAECoEXAAMbAAgKqBqiCQBGAgAbAAgKqBqiCQBGAgAfAAEKQAIJRQAhAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQADCggICQABNQAECgYIDgAFAAAAAA==.Møøfi:BAAANQAECgYICgAAAA==.',
Na='Naianasha:BAAANQAECgYICAAAAA==.Nameless:BAABNQAECoEiAAIBAAgK/w/blwAMAgABAAgK/w/blwAMAgAAAA==.Narc:BAAANQAECgQIBQAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQAECgQICgAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
No='Nokzash:BAAANQAECgcIDwAAAA==.Noova:BAABNQAECoEhAAIBAAkKShyRRgDTAgABAAkKShyRRgDTAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECggIEQAFAAAAAA==.',
Ob='Obliverat:BAAANQAECggIEAAAAA==.',
Od='Odysseus:BAAANQADCgIIAgAAAA==.',
Ok='Okiedokie:BAAANQADCgQIBAABNQAECgYIDwAFAAAAAA==.',
Oo='Oongaboonga:BAABNQAECoEaAAIEAAcK2xNdfwDIAQAEAAcK2xNdfwDIAQAAAA==.',
Or='Orcaneblast:BAABNQAECoEoAAIBAAkKXR76NAADAwABAAkKXR76NAADAwAAAA==.Orcsoup:BAAANQAECgYJEAABNQAECggIEgAFAAAAAA==.',
Pa='Paddord:BAAANQABCgUIBQAAAA==.Pandemnik:BAAANQADCgcIBwAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.Percible:BAAANQADCgYIBgAAAA==.',
Pi='Pivnert:BAAANQAECgYIEAAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgQIBQAAAA==.',
['Pü']='Pünish:BAACNQAFFIEDAAIGAAIKsRq4DQCeAAAGAAIKsRq4DQCeAAA1AAQKgUEABAYACQr4JIIDAKcDAAYACQr4JIIDAKcDACAAAwpxFctYAMUAAAgAAQpfBeSuAC4AAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgYIEAAFAAAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECoEiAAMBAAkKPCCpLwASAwABAAkK0h6pLwASAwAcAAIKoCJvHADJAAABNQAFFAcIGAAcAC8XAA==.Ragingiscool:BAAANQADCggIDQAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECoEbAAIhAAgKDBAfUADlAQAhAAgKDBAfUADlAQAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Ratsrepus:BAAANQADCgQIBAAAAA==.Raza:BAAANQAECgQICQABNQAFFAIIAwAGALEaAA==.',
Re='Read:BAAANQAECgMIAwAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAAANQAECgMIAwAAAA==.',
Ri='Riken:BAAANQAECgYIEwAAAA==.',
Ro='Roadi:BAAANQAECgMJAwABNQAECggIIAATAO8eAA==.Roxer:BAAANQAFFAEIAQAAAA==.',
Ru='Rummyy:BAAANQAECggIBgAAAA==.',
Ry='Rycken:BAAANQAECgYIEQAAAA==.',
Sa='Saeylva:BAAANQAECgMIAwAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgMIBAAAAA==.Sculper:BAAANQAECgUIEAAAAA==.',
Se='Senica:BAAANQAECgYIBgAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECoEbAAIgAAgKkwwwNACgAQAgAAgKkwwwNACgAQAAAA==.Shadetotem:BAAANQAECgUIDAAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCgUICgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgcIEwAAAA==.Shradehn:BAAANQAECgcIEgAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sisterswede:BAABNQAECoEdAAIPAAkKIx0kDAD6AgAPAAkKIx0kDAD6AgAAAA==.Sizzle:BAAANQAECgcIEQAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIBQAAAA==.Smokindots:BAAANQAECgUIBQABNQAECgkJIwAHAMoiAA==.Smokingreen:BAAANQADCggJCAABNQAECgkJIwAHAMoiAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAECgkJIwAHAMoiAA==.Smokinpsalm:BAAANQAECgIIAwABNQAECgkJIwAHAMoiAA==.Smokintotem:BAABNQAECoEjAAMHAAkKyiJTBwBuAwAHAAkKyiJTBwBuAwAXAAUKrRRRgwBEAQAAAA==.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgIIBAABNQAFFAQIBwAEAFYWAA==.Sparklnmagic:BAAANQADCgcIBwAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgcJEAAAAA==.Stemi:BAAANQADCgcJBwAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQADCgYJBgABNQAECgYIEAAFAAAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAAANQAECgUICAAAAA==.Stormz:BAABNQAECoEZAAIKAAgK+Q7ZOADZAQAKAAgK+Q7ZOADZAQAAAA==.',
Su='Sunblade:BAAANQAECgMIBgABNQAECggIIgABAP8PAA==.Sundowning:BAAANQAECgUIBQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAAANQAECgYIEAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECggIGwABACkVAA==.Tackyh:BAAANQAECgUIEwAAAA==.Takamatsu:BAABNQAECoEaAAMMAAcKdCM0IAC3AgAMAAcKdCM0IAC3AgAZAAMKDA6iFACiAAAAAA==.Taku:BAAANQAECgIIBAAAAA==.Tar:BAAANQAECgYIDgAAAA==.Taxii:BAABNQAECoEbAAMEAAkKnyGBFQBKAwAEAAkKhyCBFQBKAwAiAAQKZx8bDwBmAQAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBgAAAA==.Teapots:BAAANQAECgIIAgAAAA==.Tempi:BAAANQABCgMIAwABNQAECgYIBgAFAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAAANQAECgUICQABNQAECggJGQANAIscAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECoEeAAIdAAkKgBX5CQCgAgAdAAkKgBX5CQCgAgAAAA==.Threebeans:BAAANQAECggIEgAAAA==.Thromir:BAABNQAECoEXAAMhAAkKBCCqDQA7AwAhAAkKBCCqDQA7AwANAAUKJSOpdQDiAQAAAA==.Thyrn:BAABNQAECoEbAAIIAAcKkR1aKQA9AgAIAAcKkR1aKQA9AgAAAA==.',
Ti='Tirare:BAAANQAECgYIEAAAAA==.',
Tr='Tri:BAAANQAECgUICwAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAAANQAECgQICgAAAA==.Turdferguson:BAAANQADCgcIBwABNQAFFAIIAwAFAAAAAA==.Turgrok:BAAANQAECgYIEAAAAA==.',
Tw='Twothang:BAAANQAECgUIEQAAAA==.',
Ty='Tyllan:BAABNQAECoEZAAMBAAkK/hosjQAlAgABAAcKthosjQAlAgAcAAIK9xvnIACmAAAAAA==.',
['Tâ']='Tâku:BAAANQADCggIGQAAAA==.',
Va='Vainhellsing:BAAANQAECgQIBAAAAA==.Vanzier:BAAANQAECgQICQAAAA==.Vaxis:BAABNQAECoEZAAICAAgKqg1ZXQAKAgACAAgKqg1ZXQAKAgAAAA==.',
Vi='Vid:BAACNQAFFIEHAAIfAAUKjBTjAgCSAQAfAAUKjBTjAgCSAQA1AAQKgSAAAh8ACQofIPIFABIDAB8ACQofIPIFABIDAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgQIBAAFAAAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgkJLQATABkjAA==.Wernov:BAABNQAECoEeAAMXAAgKihqoLQCGAgAXAAgKihqoLQCGAgAHAAUK6gy8lQD5AAABNQAECggIIgAMACoaAA==.',
Wh='Whitetail:BAAANQADCgEJAQAAAA==.',
Wi='Wichan:BAAANQAECgcIEQAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECggIFwAbAKgaAA==.Wiziviji:BAAANQAECgYICQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgUICgAFAAAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECgUIBwAAAA==.',
Xr='Xray:BAAANQAECgUIEQAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAAANQAECgUIBgABNQAECggIFQAGAOIXAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAAANQAECgMIBQAAAA==.',
Yu='Yunsky:BAAANQADCggIIwAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECoEfAAMHAAgKSRkINABLAgAHAAgKSRkINABLAgAXAAEKPQUBDAEqAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAAANQAECgUIEAAAAA==.Zaryor:BAABNQAECoEWAAMjAAcKIhX9JACaAQAjAAcKhBP9JACaAQAbAAQK4RTHGQDwAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQADCgQIBAAAAA==.Zerika:BAABNQAECoEcAAIMAAkKER6dEQARAwAMAAkKER6dEQARAwAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBAAAAA==.Zionna:BAAANQAECgYIEAABNQAECgYIEAAFAAAAAA==.',
Zo='Zomgqq:BAAANQAECgcIDQAAAA==.',
Zy='Zydis:BAAANQAECgUIBQAAAA==.Zyggy:BAAANQADCggIEgAAAA==.Zynfanatic:BAAANQAECgQIBAAAAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
['És']='Éstéla:BAABNQAECoEZAAICAAgKDBI0ZgDxAQACAAgKDBI0ZgDxAQAAAA==.',
['Ío']='Ío:BAAANQAECgEIAQAAAA==.',
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
