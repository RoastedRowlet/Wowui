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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Demonology','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Mage-Arcane','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Warlock-Destruction','Druid-Balance','Monk-Windwalker','Priest-Discipline','Druid-Restoration','Druid-Feral','Paladin-Holy','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Shaman-Restoration','Priest-Shadow','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abednego:BAABNQAECn8tAAMBAAkKZRcnDgCTAgABAAkKZRcnDgCTAgACAAIKrguwjQBwAAAAAA==.',
Ac='Acidrain:BAABNQAECn8gAAIDAAgKghs8PgB6AgADAAgKghs8PgB6AgAAAA==.Acmiax:BAAANQAECgMIBgABNQAECgkJIgAEALAWAA==.',
Ad='Adar:BAAANQAECgUIDwAAAA==.Adonsinn:BAAANQAECgYIEQAAAA==.',
Ae='Aegos:BAAANQAECgQIBgAAAA==.Aep:BAAANQAECgMJBAABNQAECgMIBQAFAAAAAA==.',
Ah='Ahu:BAABNQAECn81AAMGAAkK3haRRwCTAgAGAAkK3haRRwCTAgAHAAEKKgY5kwArAAAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Alandramun:BAAANQAECgIIAgAAAA==.Aleroderp:BAAANQAECgYIDwABNQAECgkJNwAIAFUVAA==.Allaria:BAAANQAECgEIAwAAAA==.Alucard:BAAANQAECgIIAgAAAA==.',
Am='Amaging:BAABNQAECn8lAAIJAAkKqgoDwgD+AQAJAAkKqgoDwgD+AQAAAA==.Ambassador:BAAANQAECgUIBQAAAA==.Amoondai:BAABNQAECn82AAIKAAkKGiOYDQBVAwAKAAkKGiOYDQBVAwAAAA==.',
An='Analytics:BAAANQAECgcIDAAAAA==.Angusdei:BAAANQADCgIIAgAAAA==.Anyr:BAAANQADCgMIAwAAAA==.',
Ap='Apochryphal:BAABNQAECn8iAAILAAgKKx3FIQClAgALAAgKKx3FIQClAgAAAA==.',
Ar='Araylva:BAAANQADCgcIBwAAAA==.Arrtemiss:BAAANQADCgMIAwABNQAECgUIDgAFAAAAAA==.',
As='Ashogg:BAAANQAECgYIDQAAAA==.',
Au='Aurén:BAAANQADCggIEwAAAA==.',
Az='Azuree:BAAANQAECgIIBAAAAA==.',
Ba='Bacstabath:BAABNQAECn81AAMCAAkKQiK9DgAJAwACAAgKESK9DgAJAwABAAgKIBuaDwB/AgAAAA==.',
Be='Becca:BAABNQAECn8nAAIMAAkKHBtRDwClAgAMAAkKHBtRDwClAgAAAA==.Bequin:BAAANQADCgUIBQAAAA==.',
Bi='Bigdaddys:BAAANQAECgMIAgAAAA==.Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAABNQAECn8rAAMEAAkK8h7UGgAYAwAEAAkK8h7UGgAYAwANAAQK8A8gNgDoAAABNQAFFAUIFQAOADUXAA==.',
Bl='Blaizee:BAAANQADCgIIAgAAAA==.Blasphemar:BAAANQADCgYJBgAAAA==.Bloodios:BAABNQAECn8rAAILAAkKtxn/GwDNAgALAAkKtxn/GwDNAgAAAA==.Bluechewgold:BAABNQAECn8lAAILAAkKgCKmCgBeAwALAAkKgCKmCgBeAwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.Bobin:BAABNQAECn8cAAIPAAgKDhLSKADUAQAPAAgKDhLSKADUAQAAAA==.Bombadil:BAABNQAECn8bAAIQAAgKIgwvCwCOAQAQAAgKIgwvCwCOAQAAAA==.Boshek:BAAANQABCgUJCQAAAA==.',
Br='Bribage:BAACNQAFFH8VAAMOAAUKNRdwDwBtAQAOAAUKNRdwDwBtAQARAAEKowmfFABKAAA1AAQKfyEAAw4ACQriH3AcAOMCAA4ACQriH3AcAOMCABIAAQozH5Q3AFkAAAAA.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAFFAUIFAATAJkkAA==.Brolavski:BAABNQAFFH8UAAITAAUKmSTzBQANAgATAAUKmSTzBQANAgAAAA==.',
Bu='Budderwar:BAABNQAECn8qAAMUAAkKhiUGAQDLAwAUAAkKhiUGAQDLAwAVAAQK9RHS8gDzAAAAAA==.Buster:BAABNQAECn8aAAMWAAgKEAuEFQBPAQAWAAgKEAuEFQBPAQAXAAQKhQOdXwBpAAAAAA==.Buzkills:BAAANQABCgIIAwAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgcJBwAAAA==.',
Ce='Celerydk:BAABNQAECn8rAAIYAAkKuR2jFwDJAgAYAAkKuR2jFwDJAgAAAA==.',
Ch='Chaosgaara:BAAANQADCgEIAQAAAA==.Chikñ:BAAANQAECgQIAQAAAA==.',
Co='Colossus:BAABNQAECn8dAAMZAAgKpR4tJQCoAgAZAAgKpR4tJQCoAgALAAMKUgvEpwB+AAAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAABNQAECn8lAAIaAAgKNRGNOQDjAQAaAAgKNRGNOQDjAQAAAA==.',
Cr='Craszhin:BAABNQAECn8fAAIOAAgKqwu6SwCxAQAOAAgKqwu6SwCxAQAAAA==.Crime:BAAANQAECgEIAgAAAA==.',
['Cè']='Cèl:BAABNQAECn8lAAMbAAgKsA4pDgDHAQAbAAgKsA4pDgDHAQAJAAQKoQHpngF9AAAAAA==.',
Da='Daddio:BAEANQAECgQIBwAAAA==.Daenarea:BAAANQADCgYIBgAAAA==.Dangpup:BAABNQAECn8mAAIHAAkKoBarGACQAgAHAAkKoBarGACQAgAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAABNQAECn8yAAIGAAkK1xVbUAB8AgAGAAkK1xVbUAB8AgAAAA==.',
De='Deathlylazy:BAAANQAECgcICgAAAA==.Deets:BAABNQAECn8aAAIGAAcKayJyPgCtAgAGAAcKayJyPgCtAgAAAA==.Demona:BAABNQAECn8hAAMNAAgKlAmsFwCuAQANAAgKlAmsFwCuAQAEAAEKEwEyVgEcAAAAAA==.Derfhurnturr:BAAANQAECgUIBgAAAA==.Descalabrada:BAAANQAECgYICgAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dr='Draeamorjan:BAAANQADCgEIAQAAAA==.Driver:BAEANQAECgYIBgABNQAECggICAAFAAAAAA==.Drpeppers:BAABNQAECn8cAAIRAAgKSA+WLAC0AQARAAgKSA+WLAC0AQAAAA==.',
['Dé']='Déathsavage:BAAANQADCggIHwAAAA==.',
Ea='Eatmorchikin:BAAANQADCgMJAwAAAA==.',
Ec='Eclair:BAABNQAECn8iAAIcAAgKkR6SLwChAgAcAAgKkR6SLwChAgAAAA==.',
El='Elfkr:BAABNQAECn8eAAMcAAgKJiGJIgDbAgAcAAgKJiGJIgDbAgADAAIK+hh++ACbAAAAAA==.Elhayn:BAABNQAECn8gAAIdAAgKdSRWCABVAwAdAAgKdSRWCABVAwAAAA==.Elmos:BAABNQAECn8yAAIPAAkKSiHFBwBQAwAPAAkKSiHFBwBQAwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.Eris:BAAANQADCgYIBwAAAA==.',
Ev='Evilmonkeydr:BAEANQAECgQIBAABNQAECgkJGAAJAJYcAA==.Evilmonkeymg:BAEBNQAECn8YAAIJAAkKlhw7WgDLAgAJAAkKlhw7WgDLAgAAAA==.Evilmonkeysh:BAEANQADCgUIBQABNQAECgkJGAAJAJYcAA==.',
Ez='Ezaylia:BAABNQAECn8bAAIaAAgKEg8tOwDXAQAaAAgKEg8tOwDXAQAAAA==.',
Fa='Fatehunter:BAAANQAECgYIEQAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAABNQAECn8fAAMbAAgKGxkcDgDIAQAbAAYKSRocDgDIAQAJAAYKGxR0+QCWAQAAAA==.',
Fi='Firefox:BAABNQAECn8aAAILAAgKMBmrNQAzAgALAAgKMBmrNQAzAgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostybeary:BAAANQABCgYIBwAAAA==.Frostymonk:BAAANQAECggIEQAAAA==.Frostypally:BAAANQAECggIDwAAAA==.',
Fu='Fuel:BAAANQADCgYIBgABNQAECgQICAAFAAAAAA==.Furrybear:BAAANQAECgEIAgAAAA==.',
Ga='Gala:BAAANQAECggIDQAAAA==.',
Ge='Genorian:BAAANQAECgcIEwAAAA==.',
Gi='Gigem:BAABNQAECn8YAAIGAAYKmxwxiQD1AQAGAAYKmxwxiQD1AQAAAA==.Girlshoon:BAAANQAECgEIAQAAAA==.Githan:BAAANQAECgYIDAABNQAECgkJJwARAK0bAA==.',
Gl='Glarious:BAABNQAECn8nAAIBAAkKBBDAFAA/AgABAAkKBBDAFAA/AgAAAA==.',
Go='Gobbozap:BAAANQADCggIDgABNQAECgkJKAAQAOYeAA==.',
Gr='Gredan:BAAANQAECgYIDAAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQAECggICgAAAA==.',
Gu='Guldaniel:BAABNQAECn8iAAIEAAkKsBaxPACaAgAEAAkKsBaxPACaAgAAAA==.Guthuzad:BAAANQADCgUIBgAAAA==.Guthx:BAABNQAECn8bAAMOAAgKhRduQwDjAQAOAAcK7BduQwDjAQARAAMKKA+BVwClAAAAAA==.',
Ha='Halfaman:BAAANQAECgQIBgABNQAECgcICwAFAAAAAA==.Hantzel:BAAANQADCgUIBQAAAA==.',
He='Healyeah:BAAANQAECgEIAQAAAA==.Hellen:BAABNQAECn8XAAIEAAgKziHzKwDTAgAEAAgKziHzKwDTAgAAAA==.',
Ho='Hotburrito:BAAANQABCgMIAwAAAA==.',
Hw='Hwat:BAAANQAECgYIDwAAAA==.',
Ic='Ictus:BAABNQAECn8XAAIJAAgKtBzFbwCeAgAJAAgKtBzFbwCeAgAAAA==.',
In='Incredabull:BAAANQAECgIIAgAAAA==.',
Is='Isabelle:BAACNQAFFH8FAAIHAAIKHwrIHQCCAAAHAAIKHwrIHQCCAAA1AAQKfyYAAgcACAppFawmABMCAAcACAppFawmABMCAAAA.Isharded:BAABNQAECn8lAAIeAAkKHw4ZBwAvAgAeAAkKHw4ZBwAvAgAAAA==.Istayblunted:BAAANQAECgUIBwAAAA==.',
Ja='Jacqualyn:BAAANQAECgcICwAAAA==.Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCggIDwABNQAECgYIDAAFAAAAAA==.Jinkuzo:BAABNQAECn8eAAIfAAgKABuRCACfAgAfAAgKABuRCACfAgAAAA==.Jinmu:BAABNQAECn8iAAMBAAgKnBLmGAARAgABAAgKnBLmGAARAgACAAcKJwhPVQBfAQAAAA==.',
Ju='Juanaloopa:BAAANQAECgUICwAAAA==.Juggie:BAABNQAECn8WAAMKAAcKUwXMmwA9AQAKAAcKUwXMmwA9AQAdAAUKXwS3UwC7AAAAAA==.Julienned:BAABNQAECn8kAAICAAkKnw2eMQATAgACAAkKnw2eMQATAgAAAA==.',
['Jè']='Jèsse:BAAANQADCgcJBwAAAA==.',
Ka='Kainen:BAABNQAECn8iAAQIAAgK1RqfYgBuAgAIAAgK1RqfYgBuAgATAAQKGQMB7wCdAAAMAAQK4QNYWQBzAAAAAA==.',
Ki='Kinkybunny:BAAANQADCgYJBgAAAA==.',
Kl='Klodar:BAAANQAECgUIDAAAAA==.Klum:BAAANQABCgQIBgAAAA==.',
Kr='Krazee:BAAANQABCgMIBQAAAA==.',
La='Lafey:BAAANQADCgIJAgAAAA==.Lamedout:BAAANQADCgcIBwABNQAECgQICAAFAAAAAA==.Lanfear:BAAANQADCgQIBAAAAA==.Laurenya:BAAANQADCgMIAwABNQAECgUIDgAFAAAAAA==.',
Le='Leida:BAAANQADCgcICwAAAA==.Leinen:BAAANQADCgYIBwAAAA==.',
Lo='Logi:BAAANQAECgMIBQAAAA==.Lostrage:BAAANQADCgcICgAAAA==.',
Lu='Lumiyer:BAABNQAECn8YAAIKAAkKuBT4PgBrAgAKAAkKuBT4PgBrAgABNQAFFAYIEwAgAK8fAA==.',
Ly='Lygra:BAAANQAECgUICgAAAA==.Lykana:BAAANQAECgQIBQAAAA==.Lyrasong:BAAANQADCgMIAwAAAA==.Lytharielis:BAAANQABCgQIBAAAAA==.',
Ma='Majellan:BAABNQAECn8rAAMMAAkKdhc+EACXAgAMAAkKdhc+EACXAgAIAAgKzw3JtQCtAQAAAA==.Marsawn:BAABNQAECn8qAAMKAAkKnhfELgCqAgAKAAkKnhfELgCqAgAdAAIKbh83VAC4AAAAAA==.Mass:BAACNQAFFH8TAAIUAAcKGyUUAAD0AgAUAAcKGyUUAAD0AgA1AAQKfyMAAhQACQpsJQkCAJ4DABQACQpsJQkCAJ4DAAAA.',
Me='Meatbatticus:BAAANQAECgYICgAAAA==.Meqi:BAAANQAECgYIDAAAAA==.Metsys:BAAANQABCgQIBAAAAA==.',
Mi='Mindlessness:BAABNQAECn8jAAIVAAkKlB1vOgDZAgAVAAkKlB1vOgDZAgAAAA==.Mineralelf:BAABNQAECn8rAAIGAAkKKQuZhgD6AQAGAAkKKQuZhgD6AQAAAA==.Minichaos:BAABNQAECn8cAAMNAAcKDRZ1DAAuAgANAAcKyxV1DAAuAgAEAAUKmwhM7wDmAAAAAA==.Miriam:BAABNQAECn8wAAIJAAkKMwbr5AC8AQAJAAkKMwbr5AC8AQAAAA==.',
Mo='Mojosavage:BAAANQAECgYIEgAAAA==.Moonblade:BAAANQADCggICAAAAA==.',
My='Mylas:BAAANQADCgcIBwAAAA==.Mysticalfox:BAAANQADCgEIAQAAAA==.',
Na='Nalfilas:BAAANQAECgUIEQAAAA==.',
Ne='Necromm:BAAANQABCgQIBgAAAA==.Nephaleos:BAABNQAECn8jAAIhAAkKHB9vCwDrAgAhAAkKHB9vCwDrAgAAAA==.Nessie:BAAANQAECgIIAgAAAA==.',
Ni='Nihlus:BAAANQAECgYIBgAAAA==.',
Nu='Nurzul:BAAANQADCggICAABNQAECggICgAFAAAAAA==.',
Ny='Nyrvana:BAAANQAECgYICQAAAA==.',
['Nà']='Nàtureswrath:BAAANQAECgQICAAAAA==.',
Og='Ogre:BAAANQADCgcIFwAAAA==.',
Or='Orceo:BAABNQAECn8kAAIGAAgKsySWGQAyAwAGAAgKsySWGQAyAwAAAA==.Orkeo:BAAANQADCgcICwAAAA==.Orkreghar:BAABNQAECn8hAAIGAAgKBxuAPwCqAgAGAAgKBxuAPwCqAgAAAA==.',
Pa='Padawon:BAAANQAECgQIBAAAAA==.Pallon:BAAANQAECgcJCwAAAA==.',
Pe='Perkybites:BAAANQABCggICQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgMIBQAAAA==.',
Po='Pompompower:BAABNQAECn8qAAIDAAkKkQgzdgC7AQADAAkKkQgzdgC7AQAAAA==.Popashammy:BAAANQAECgIIAgAAAA==.Poplock:BAAANQADCgcIFgAAAA==.Popple:BAAANQAECgcIEwAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Pu='Puggsly:BAAANQADCggIDgABNQAECgkJIgAEALAWAA==.',
Qu='Quixotical:BAAANQADCgYIDAAAAA==.',
Ra='Radaghast:BAAANQAECgIIAgAAAA==.',
Re='Rectumraker:BAAANQAECgMIAwAAAA==.Reishirome:BAAANQADCggIFQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAABNQAECn8hAAIcAAkKOx3PHQDzAgAcAAkKOx3PHQDzAgAAAA==.Rhoke:BAABNQAECn8uAAIIAAgKIhDhqwDCAQAIAAgKIhDhqwDCAQAAAA==.',
Ro='Roguecow:BAAANQAECggICAAAAA==.Romeoz:BAAANQADCgMIAwABNQAECgcICwAFAAAAAA==.Rona:BAAANQAECgQIDAAAAA==.Roofhouse:BAAANQADCgMIAwAAAA==.Rosary:BAABNQAECn8cAAIKAAgKeR9+JADYAgAKAAgKeR9+JADYAgAAAA==.Rotiserychic:BAAANQAECgIIAgAAAA==.Roukia:BAAANQADCgEIAQAAAA==.',
Ru='Rusticfinger:BAABNQAECn8bAAIcAAgK0RcUUgAaAgAcAAgK0RcUUgAaAgAAAA==.',
Sa='Sacerdote:BAAANQAECgMIBAAAAA==.Sansa:BAAANQAECgYIDAAAAA==.Saruma:BAAANQADCggIDgABNQAECggICgAFAAAAAA==.',
Sc='Scalygrob:BAAANQAECgcIEwAAAA==.Scarytery:BAAANQAECgYIEAAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamfox:BAAANQAECgYIEQAAAA==.',
Sm='Smogcheck:BAABNQAECn8mAAMhAAkKFhdLEwB3AgAhAAkKFhdLEwB3AgAiAAIKUAtqNQBfAAAAAA==.',
Sn='Snowsz:BAAANQAECgcICAAAAA==.Snowws:BAABNQAECn8lAAIaAAkKgx8LEQAVAwAaAAkKgx8LEQAVAwAAAA==.Snowzz:BAAANQADCgQIBAAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAABNQAECn8iAAMJAAkKGRw2YgC6AgAJAAkKGRw2YgC6AgAbAAEK/wNXTwAnAAAAAA==.',
Sp='Spicebreff:BAAANQADCgYIBgABNQAECgYIGgAVAHQaAA==.',
St='Steck:BAAANQAECgUIEAAAAA==.Strigg:BAAANQADCgMIAwABNQADCggIEQAFAAAAAA==.Strigöi:BAAANQADCggIEQAAAA==.',
Su='Suprahunts:BAABNQAECn8ZAAMGAAcKcCJcUQB5AgAGAAcKcCJcUQB5AgAHAAQKeA32VADOAAAAAA==.',
['Sà']='Sàlís:BAAANQADCgUIDgAAAA==.',
Ta='Talander:BAAANQADCgUIBQABNQAECgcICwAFAAAAAA==.Talas:BAABNQAECn8yAAMGAAkKhRxPMADaAgAGAAkKhRxPMADaAgAHAAUKMBHBRAAtAQAAAA==.',
Te='Teaka:BAAANQAECgEIAQAAAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thaelink:BAAANQAECgEIAQABNQAECgkJIAAJAE8XAA==.Thickthighs:BAAANQAECgYICQABNQAECgcICwAFAAAAAA==.Thorss:BAAANQAECgIIAgABNQAECgYICgAFAAAAAA==.Thrann:BAABNQAECn8iAAIZAAkKfSJcDgBEAwAZAAkKfSJcDgBEAwAAAA==.',
Ti='Tirium:BAABNQAECn8aAAIVAAYKdBq7mgDVAQAVAAYKdBq7mgDVAQAAAA==.',
To='Tolkien:BAABNQAECn8WAAIYAAYK1A/YUwBYAQAYAAYK1A/YUwBYAQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Un='Unduril:BAAANQADCgYIBgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgUIBQAAAA==.',
Ve='Velarys:BAAANQABCgIIAgABNQAECgkJKAAQAOYeAA==.Velinlock:BAAANQABCgEIAQAAAA==.Velinthil:BAAANQADCgcIBwAAAA==.Verðandi:BAAANQADCgMJAwAAAA==.',
Vo='Volvox:BAAANQADCggICwAAAA==.',
Vy='Vyxenn:BAABNQAECn8rAAMcAAkKjRp+MgCUAgAcAAkKjRp+MgCUAgADAAIK1wYLFAFfAAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAAFAAAAAA==.Washim:BAAANQADCggICQAAAA==.',
Wu='Wurm:BAAANQADCgQIBAABNQAECggICgAFAAAAAA==.',
Ye='Yejena:BAAANQAECgEIAQAAAA==.',
Ym='Ymir:BAAANQADCgQIBAAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQAECgcIDwAAAA==.',
Zi='Zillaamiri:BAAANQAECgIIAgAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggJFgAAAA==.',
Zy='Zyrinx:BAAANQABCgIIAgAAAA==.Zywol:BAABNQAECn8rAAMOAAkKsxg0IgC7AgAOAAkKsxg0IgC7AgARAAMKDg3xVwCjAAAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEwABNQAECggIIQAGALQcAA==.',
['Ðe']='Ðespair:BAABNQAECn8ZAAMKAAkKVh02SwBAAgAKAAcKgRw2SwBAAgAdAAYKRBhiLQC3AQAAAA==.',
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
