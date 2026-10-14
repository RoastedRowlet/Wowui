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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Arcane','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Warlock-Affliction','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Rogue-Outlaw','Rogue-Subtlety','Hunter-Survival','Warlock-Destruction','Hunter-Marksmanship','Evoker-Devastation','Monk-Windwalker','Paladin-Holy','Warrior-Arms','Priest-Holy','Shaman-Elemental','Rogue-Assassination','Priest-Discipline','Warrior-Fury','Evoker-Augmentation','Monk-Mistweaver','Priest-Shadow','Warrior-Protection',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acemage:BAAANQAECgcIEwABNQAFFAYIGgABAFcbAA==.',
Ae='Aegon:BAABNQAECn8qAAQCAAkKniDVHgDQAgACAAkKniDVHgDQAgADAAcK8QrkbQA6AQAEAAEKEAdgrwAtAAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn8eAAMFAAcKLh+CugANAgAFAAYKNB6CugANAgAGAAIKKR/OJwCyAAAAAA==.',
Ah='Ahdonis:BAAANQAECgcICAAAAA==.Ahnerfays:BAAANQAECgUICAABNQAECggILQAHAEAgAA==.',
Ai='Aiara:BAAANQAECgEIAQAAAA==.Aiarra:BAABNQAECn8lAAMIAAgKjg+AQAD0AQAIAAgKjg+AQAD0AQAJAAQKxAb4WACfAAAAAA==.Aindriana:BAABNQAECn8aAAIKAAYKxgZkWwAQAQAKAAYKxgZkWwAQAQAAAA==.Aiondormi:BAAANQABCgQIBAAAAA==.Aitra:BAAANQAECgUIDQAAAA==.',
Aj='Ajx:BAAANQAECgIIAwABNQAECgUICwALAAAAAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAAANQAECgYIEgAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgkJIAAMAFEeAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alerothon:BAABNQAECn83AAIHAAkKVRV5ZABpAgAHAAkKVRV5ZABpAgAAAA==.Alestiana:BAABNQAECn8rAAINAAgKZBhCUQAdAgANAAgKZBhCUQAdAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAABNQAECn8gAAIOAAgKVBcGGwAUAgAOAAgKVBcGGwAUAgAAAA==.Amnadores:BAABNQAECn8bAAIFAAYK9gcaLAE/AQAFAAYK9gcaLAE/AQABNQAECggIHgAOAAgQAA==.',
An='Annati:BAACNQAFFH8JAAINAAUKcRibCwCOAQANAAUKcRibCwCOAQA1AAQKfyIAAg0ACQqXIhoVACMDAA0ACQqXIhoVACMDAAAA.Antarres:BAABNQAECn8cAAIPAAgKQweCqwB2AQAPAAgKQweCqwB2AQAAAA==.',
Ao='Aoba:BAABNQAECn8pAAIOAAgKMhxpFABeAgAOAAgKMhxpFABeAgAAAA==.',
Ap='Apila:BAAANQADCgEIAgABNQAECgYIGQALAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAAANQAECgQIBgAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAMIBgAEADEQAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECggILQAHAEAgAA==.Areaman:BAAANQADCgYICQABNQAECgYIDAALAAAAAA==.Aridam:BAAANQAECgQIBAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgALAAAAAA==.Artemisshade:BAABNQAECn8aAAMQAAcKOxh2CAAUAgAQAAcKOxh2CAAUAgARAAQKjBJ6NAARAQABNQADCgIIAgALAAAAAA==.Arthillius:BAAANQAECgIIAgAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Av='Aviana:BAAANQAECggIEgAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgQIBAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8mAAMBAAcKcg95lADcAQABAAcKdg55lADcAQASAAcK7An9CACyAQAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.Belle:BAAANQABCgUIBwAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECn8ZAAMPAAkKpQ7IiADMAQAPAAgKkg3IiADMAQATAAIKnhHrVwB2AAAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzy:BAABNQAECn8fAAIIAAkKIRzsHwDKAgAIAAkKIRzsHwDKAgAAAA==.',
Bo='Bobbette:BAAANQAECgYIEAABNQAECggIFwANAGsbAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Brenick:BAAANQAECgUICgAAAA==.Bringer:BAAANQAECgIIAgAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQADCgUIBQAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQIBAAAAA==.Burnie:BAAANQAECgUICgAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAAANQAECgcICgAAAA==.Camilah:BAAANQAECggIEwAAAA==.Capa:BAABNQAECn8gAAQMAAkKUR5jBACVAgAMAAcKHh9jBACVAgAPAAQKKRxgzAAsAQATAAMKOBdWOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAAANQAECgcIEwAAAA==.',
Ce='Celestiné:BAAANQAECgQIBAAAAA==.Cemeteri:BAAANQADCggIDwAAAA==.',
Ch='Chaingun:BAAANQAECgYIDwAAAA==.Chelseac:BAAANQAECgQIEwABNQAECgcIGQAFAJMNAA==.Chilblain:BAABNQAECn8pAAIGAAgKXBMeDAD3AQAGAAgKXBMeDAD3AQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECn8xAAIUAAkKmhl0HABsAgAUAAkKmhl0HABsAgAAAA==.',
Ci='Cibochevski:BAAANQADCggIDwABNQAECgUIDAALAAAAAA==.Ciratorynth:BAABNQAECn8hAAIVAAgKOxaUEwATAgAVAAgKOxaUEwATAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8kAAINAAkKhyIKDwBJAwANAAkKhyIKDwBJAwAAAA==.',
Cl='Clearlove:BAAANQAECgQIBAABNQAECgcIGQAFAJMNAA==.Clearlovec:BAAANQAECgcICAABNQAECgcIGQAFAJMNAA==.Closetfurry:BAAANQAECgUIEAAAAA==.',
Co='Condor:BAAANQAECgYICgAAAA==.Corrinne:BAABNQAECn8aAAIHAAgKZRsjZgBlAgAHAAgKZRsjZgBlAgAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Critmypänts:BAAANQAECgIIAwAAAA==.',
Cz='Czernobog:BAAANQAECggICQAAAA==.',
Da='Daeshan:BAABNQAECn8pAAIWAAgKyBc5HgA9AgAWAAgKyBc5HgA9AgAAAA==.Dafirstone:BAAANQAECgQIBQAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECn8sAAIXAAkKQh3RGAAUAwAXAAkKQh3RGAAUAwAAAA==.Daradevil:BAAANQADCgcJBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcJBwALAAAAAA==.Daralune:BAAANQAECgMIBQAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn8oAAMHAAgKVxikZwBgAgAHAAgKVxikZwBgAgAOAAEKxwSrfwAbAAAAAA==.Dasecondone:BAAANQAECgUIDAAAAA==.Dathirdone:BAAANQADCggIHwAAAA==.Dawg:BAAANQAECgQICQAAAA==.',
De='Deadlytankz:BAAANQADCgQIBAAAAA==.Deadval:BAAANQADCgYIDQAAAA==.Demonicfyre:BAECNQAFFH8HAAIFAAMKDBiuMQD8AAAFAAMKDBiuMQD8AAA1AAQKfyAAAgUACQoTHM5UANcCAAUACQoTHM5UANcCAAAA.Demonstein:BAEANQAECgUIBQABNQAFFAUIDQAHAI4gAA==.Deslarion:BAAANQADCgYICwAAAA==.Destros:BAAANQAECgQICwAAAA==.',
Di='Disdain:BAAANQAECgYICAABNQAFFAcIIgAPAAkdAA==.',
Do='Donchap:BAAANQAECggIBgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQADCgQIBAABNQADCgQJBAALAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgUIBwAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn8kAAMCAAkKZR1WLACBAgACAAcKSR9WLACBAgAEAAYKnhiNPwDEAQAAAA==.Drzip:BAAANQAECgYICwAAAA==.Drzippy:BAAANQAECgMIBQAAAA==.',
Du='Duane:BAAANQAECgcIDQAAAA==.Duskthrasher:BAAANQAECgUIDQAAAA==.Duyii:BAAANQADCgYICwABNQAECgYIGQALAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8lAAIBAAkKUxZHPgCtAgABAAkKUxZHPgCtAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgQICAAAAA==.',
Ea='Easterneon:BAAANQAECgUICgABNQAECgcIGQAFAJMNAA==.',
Ec='Ech:BAABNQAECn8pAAIYAAgKwxg+aQBRAgAYAAgKwxg+aQBRAgAAAA==.',
Ei='Eiraveta:BAABNQAECn8gAAIZAAcKag4KfwCXAQAZAAcKag4KfwCXAQAAAA==.',
El='Elemental:BAAANQAECgYIEAAAAA==.Elendirs:BAAANQABCgYIEwABNQABCgcIDgALAAAAAA==.Ellois:BAAANQAECgYIDgAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAAANQAECgYIBgABNQAECgcIDgALAAAAAA==.',
Ep='Epicnoname:BAACNQAFFH8GAAIEAAMKMRAHDwDkAAAEAAMKMRAHDwDkAAA1AAQKfx8AAgQACQplHOAfAIkCAAQACQplHOAfAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQAECgUIDAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgcICAAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIDAAcKoBmGSQDPAQADAAcKoBmGSQDPAQAAAA==.',
Fe='Feannesse:BAAANQAECgUICQAAAA==.Festival:BAAANQAECgcIBwABNQAECgcIGQADAKAZAA==.',
Fi='Firebolt:BAABNQAECn8cAAMNAAYKgRqKawDFAQANAAYKgRqKawDFAQAaAAMKvRCi8gCpAAAAAA==.Fitts:BAAANQAECgYIDAABNQAFFAMIBQAXANEbAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHQAbAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAAANQAECgYIEAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAAANQAECgcIEgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgUICwALAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Garekk:BAAANQAECgcIDgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9GAAMEAAkKMCOUBQCFAwAEAAkKMCOUBQCFAwACAAgKURZLSgDpAQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCggIDwAAAA==.Goneville:BAAANQAECggICAAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAAANQAECgYIEQAAAA==.',
Gt='Gtx:BAAANQAECgQICAAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggICAABNQAECgIIAwALAAAAAA==.Gutworthy:BAAANQAECgQIAwAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQADCgYIBgAAAA==.Hallzypal:BAAANQAECgUICAAAAA==.Hammerjane:BAAANQAECgUIDAAAAA==.Hamur:BAABNQAECn8XAAIcAAcKcBnqBgAPAgAcAAcKcBnqBgAPAgAAAA==.Hariyaki:BAAANQAECgUICgAAAA==.Havebandaids:BAAANQADCgEIAQAAAA==.',
He='Heavywinner:BAABNQAECn8zAAMIAAkKKBzfGAD/AgAIAAkKKBzfGAD/AgAJAAQKWAlBVgCqAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8cAAIZAAgKrCRmEQA7AwAZAAgKrCRmEQA7AwAAAA==.Hellmage:BAAANQADCgEIAQAAAA==.Hellsfury:BAAANQADCgYIEAAAAA==.Hellslayer:BAAANQAECgcIEwAAAA==.Hellwalker:BAAANQADCggIJAAAAA==.Hellzy:BAAANQADCggIEAAAAA==.',
Hn='Hnof:BAAANQADCgQIBAABNQAFFAQICQAZAMoRAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAAANQAECgUIDAAAAA==.',
['Hâ']='Hârlot:BAAANQAECgUIDAAAAA==.',
['Hè']='Hèathen:BAAANQADCggIDwAAAA==.',
In='Ingenii:BAAANQAECgQIBAABNQAECgkJIAAMAFEeAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8PAAIPAAUKrh0KEACGAQAPAAUKrh0KEACGAQA1AAQKfxYAAg8ACQpUGfhIAHUCAA8ACQpUGfhIAHUCAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgEIAQAAAA==.Jaestra:BAAANQADCgYIDwABNQAECgYIDAALAAAAAA==.Jaidah:BAAANQADCggIIQAAAA==.Jaith:BAAANQAECgEIAQAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICAALAAAAAA==.Jansôlo:BAABNQAECn8XAAMBAAgKAiImOAC/AgABAAgKAiImOAC/AgAUAAMKiBSgXgCnAAAAAA==.Jaratri:BAACNQAFFH8GAAISAAIKsw3GAQCgAAASAAIKsw3GAQCgAAA1AAQKfzsAAhIACQrEGB8DAOoCABIACQrEGB8DAOoCAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8bAAIFAAcKIQgODgFxAQAFAAcKIQgODgFxAQAAAA==.',
Ka='Kaatu:BAAANQADCgMIAwAAAA==.Kaerovia:BAABNQAECn8gAAIXAAgK4hWQTgAuAgAXAAgK4hWQTgAuAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8aAAIaAAkKzBSdOQCNAgAaAAkKzBSdOQCNAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICAAAAA==.Karg:BAABNQAECn8VAAIHAAgKQggQ0gBxAQAHAAgKQggQ0gBxAQAAAA==.Karmai:BAABNQAECn8pAAIQAAgKWCMvAgBBAwAQAAgKWCMvAgBBAwAAAA==.Kastigor:BAAANQAECgUIBQABNQAECgkJLgAKAHIaAA==.Kathine:BAAANQAECgQIBwAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgUICQAAAA==.',
Ke='Keaa:BAAANQAECgYIBQAAAA==.Kelvala:BAABNQAECn8pAAMYAAkKnCPvJQAfAwAYAAkK2SHvJQAfAwAdAAUKNCUHCwASAgAAAA==.Kelwynd:BAAANQAECgUIDAAAAA==.Keä:BAAANQAECggIEwAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn8pAAIOAAgKtRnIGAAuAgAOAAgKtRnIGAAuAgAAAA==.Kizzs:BAAANQAECggIBQAAAA==.',
Ko='Kobesama:BAABNQAECn8dAAIYAAgKXQ4imwDUAQAYAAgKXQ4imwDUAQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8aAAMeAAcKdBLLCwCcAQAeAAcKdBLLCwCcAQAVAAIKWgZ8NgBXAAAAAA==.Konata:BAAANQADCggIDwABNQAECggIKQAOADIcAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgYIGQALAAAAAQ==.Korigan:BAAANQAECgYICwAAAA==.',
Kr='Krom:BAAANQAECgEIAQABNQAECggIEwALAAAAAA==.Kryssie:BAABNQAECn8jAAIBAAgKMxcfbwAxAgABAAgKMxcfbwAxAgAAAA==.',
Ku='Kudrah:BAAANQADCgQIBAABNQAECgUICwALAAAAAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIfAAcKIwiwKQAfAQAfAAcKIwiwKQAfAQAAAA==.',
La='Lampard:BAAANQAECgYIBgABNQAECgkJJQADAIAiAA==.Lanaya:BAAANQAECgYIDwAAAA==.Laserheadten:BAABNQAECn8iAAIgAAkK9xt8FAC9AgAgAAkK9xt8FAC9AgAAAA==.Laudna:BAAANQADCgcIBwABNQAECgcICAALAAAAAA==.Lawrensce:BAAANQAECgQIBwAAAA==.',
Le='Leanore:BAAANQADCgUIBQABNQAECgcIKAAIACIJAA==.Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAAANQAECgQIBwAAAA==.Lenian:BAAANQAECgUIDAAAAA==.Leâfs:BAAANQAECgUIDgAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQAECgQIBwAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAALAAAAAA==.Lourom:BAAANQAECgcIEwAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAAANQAECgUICwAAAA==.',
Ly='Lyraae:BAABNQAECn8gAAINAAcKMxLPfACRAQANAAcKMxLPfACRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn83AAMBAAkKphnOOgC3AgABAAkKphnOOgC3AgAUAAEKswP+mQAkAAAAAA==.Maiganoss:BAAANQAECgUICAAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgALAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAAANQAECggIDwAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBQAAAA==.',
Me='Megid:BAABNQAECn8gAAIOAAcK8R6RFQBRAgAOAAcK8R6RFQBRAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8eAAIEAAkKKBnHJABoAgAEAAkKKBnHJABoAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAAANQAECgQICQABNQAECgcIKAAIACIJAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgIIAwAAAA==.Mimie:BAAANQAECgUIBAAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQAECgYICwAAAA==.Mizblumkin:BAAANQAECgYIBgAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moogyver:BAAANQAECggICAAAAA==.Moonfizzle:BAAANQADCgYIDAAAAA==.Moonnshine:BAABNQAECn8gAAMIAAgKogWFYgBAAQAIAAgKogWFYgBAAQAJAAYKXwIDVQCvAAAAAA==.Moonrend:BAAANQADCgYIDwAAAA==.Moonzire:BAAANQAECgEIAQAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECgYIGQALAAAAAQ==.',
Mu='Muradil:BAAANQADCgMIBAAAAA==.Murgrot:BAAANQADCgcIDwAAAA==.',
My='Mylittlepwni:BAAANQAECgEIAQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcJBwAAAA==.',
Na='Nainel:BAAANQADCgYIDwABNQAECgUIDAALAAAAAA==.Nakros:BAAANQAECgUIBwAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgYIDAALAAAAAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECgUIBQAAAA==.Nerik:BAAANQAECgEIAQAAAA==.Nerissa:BAEANQAECggIEQAAAA==.Netallia:BAAANQABCgcIEAAAAA==.',
Ng='Ngyue:BAAANQADCgYJJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAIBAAcKbxo6aQA/AgABAAcKbxo6aQA/AgAAAA==.Nickto:BAAANQAECgMIBQAAAA==.Nightshayed:BAAANQADCggIDwAAAA==.',
Nu='Nubin:BAAANQAECgIIAgAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgUICwALAAAAAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIEAALAAAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECgUICgALAAAAAA==.',
Or='Orceo:BAAANQADCggIGQAAAA==.Orcrest:BAAANQAECgIIAgAAAA==.Ororo:BAABNQAECn8mAAIaAAgK1hqNQwBkAgAaAAgK1hqNQwBkAgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgUICAALAAAAAA==.Paog:BAAANQADCgYIBgAAAA==.Paryah:BAAANQAECgUIDAAAAA==.Pauken:BAAANQAECgUICgABNQAECgkJIAAMAFEeAA==.',
Ph='Phanceester:BAAANQAECgIIAgAAAA==.Phindra:BAAANQAECgMIBAAAAA==.Phonut:BAAANQADCgYIBgAAAA==.Phréek:BAABNQAECn8jAAMXAAgKEh1ILQCvAgAXAAgKEh1ILQCvAgAHAAIKJhF8YAF8AAAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAABNQAFFH8LAAIDAAUKbwmeEQA3AQADAAUKbwmeEQA3AQAAAA==.',
Po='Poetea:BAAANQADCgEIAQAAAA==.Portalslag:BAAANQAECgcIBwAAAA==.',
Pr='Praze:BAAANQAECgIIAgAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgAAAA==.Rahis:BAABNQAECn8jAAMBAAgK5xdIYQBRAgABAAgK5xdIYQBRAgAUAAEKeAOLjwAuAAAAAA==.Raiu:BAAANQAECgUIDAAAAA==.Ramsis:BAABNQAECn8XAAINAAgKaxuRRQBIAgANAAgKaxuRRQBIAgAAAA==.Randir:BAABNQAECn8sAAIgAAkKABWQFgCkAgAgAAkKABWQFgCkAgAAAA==.Ranir:BAAANQAECgEIAQAAAA==.Rath:BAABNQAECn8VAAIWAAYKFRzIJAD6AQAWAAYKFRzIJAD6AQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgMIBwAAAA==.Remedivhs:BAAANQADCgEJAQABNQAECgYIGQALAAAAAQ==.Rettbull:BAAANQADCgYIDwAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAAANQAECgUIEgAAAA==.Rhyli:BAAANQADCgYIDwAAAA==.',
Ro='Robinhoodx:BAABNQAECn8oAAIBAAgKBR1fQACnAgABAAgKBR1fQACnAgAAAA==.Rockbottom:BAAANQADCgYIDAABNQAECgYIDAALAAAAAA==.Roenabur:BAAANQADCggIFQAAAA==.Romok:BAAANQAECgIIBAAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8XAAIHAAcKzQ1x0gBwAQAHAAcKzQ1x0gBwAQAAAA==.Samoot:BAABNQAECn8oAAIIAAcKIgkpWwBiAQAIAAcKIgkpWwBiAQAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQADCgYIDQABNQAECgYIGQALAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAAANQAECgUIDAAAAA==.Shamanstein:BAEANQADCggJDwABNQAFFAUIDQAHAI4gAA==.Shammbo:BAAANQAECgUIBgABNQAECgcIDwALAAAAAA==.Sharty:BAAANQAECggIDwAAAA==.Shazra:BAAANQAECgcIDQAAAA==.Sheriruth:BAAANQAECgYIBgABNQAECgkJIAAMAFEeAA==.Shortigen:BAAANQAECgIIAgAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.',
Si='Sicnus:BAAANQADCggICgAAAA==.Silveryl:BAAANQAECgUICgAAAA==.Sinadin:BAABNQAECn8sAAIHAAgKuxJJlgDyAQAHAAgKuxJJlgDyAQAAAA==.Sindoreisins:BAAANQAECgcIDQAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIHAAZACAKAA==.Skolmaster:BAAANQAECgYICwAAAA==.Skootter:BAAANQADCgYJBwAAAA==.Skyfury:BAAANQAECgQIDgABNQAECgYIHAANAIEaAA==.Skywalkr:BAAANQADCgUIBgAAAA==.',
Sm='Smarky:BAAANQAFFAIIBAAAAA==.Smâlls:BAEANQAECgUIDAAAAA==.',
Sn='Sneekie:BAAANQABCgQIBgAAAA==.Sneekiemage:BAAANQAECgQIBgAAAA==.Snugz:BAAANQAECgEIAQAAAA==.',
So='Sourdiesel:BAAANQAECgEIAQAAAA==.Southsound:BAABNQAECn8ZAAIFAAcKkw38/gCMAQAFAAcKkw38/gCMAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQALAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQAECgcIEgAAAA==.Stormoon:BAAANQAECgYIDQAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgMIAwAAAA==.',
Sy='Sybil:BAAANQAECgUICwAAAA==.',
Sz='Szer:BAAANQAECgUIBQAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAAANQAECgUICgAAAA==.Tahtiania:BAAANQAECgQIBgAAAA==.Talkurandis:BAAANQAECgYIBgABNQAECgYIGQALAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn8XAAICAAgKWB7LHgDQAgACAAgKWB7LHgDQAgAAAA==.Teo:BAABNQAECn8gAAIBAAcKeBDVlADbAQABAAcKeBDVlADbAQAAAA==.Terraria:BAAANQAECgEIAQABNQAECggIKQAQAFgjAA==.Teyamat:BAAANQAECgUICQABNQAECggIFwACAFgeAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8iAAMNAAkKoR1lHQD1AgANAAkKoR1lHQD1AgAaAAMKqhFB8QCsAAAAAA==.Thetree:BAABNQAECn8nAAMJAAkKrRucFAChAgAJAAkKrRucFAChAgAIAAcK+xuOPQAIAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIHAAZACAKAA==.Thoughtcrime:BAAANQAECgIIAgAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8bAAIcAAgKJBjVBQA+AgAcAAgKJBjVBQA+AgAAAA==.',
Ti='Timoris:BAAANQAECgQIBgABNQAECgkJIAAMAFEeAA==.',
To='Tobiume:BAAANQAECgUICgABNQAECggIHgAOAAgQAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Toggo:BAAANQADCgQIBQAAAA==.Tommytwotusk:BAAANQAECgYIEAAAAA==.Toodles:BAAANQADCggICAAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgMIBwAAAA==.Trildjr:BAAANQAECgUICwAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn8nAAIaAAgKuwmuhgCPAQAaAAgKuwmuhgCPAQAAAA==.',
Ty='Tyronda:BAAANQADCggIIwAAAA==.Tyrse:BAAANQAECgQIDAAAAA==.',
Tz='Tzerina:BAAANQAECgMICAAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECgYIGQAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8fAAIXAAgKlRCfbADPAQAXAAgKlRCfbADPAQAAAA==.Validan:BAAANQAECgQIBgAAAA==.Valkriss:BAAANQADCgYIDwAAAA==.Vallyrie:BAABNQAECn8nAAMDAAgKDxZqVwCSAQADAAcKfhNqVwCSAQACAAcKMRWVYgCCAQAAAA==.Valssharess:BAAANQAECgUIDgAAAA==.Valth:BAAANQAECgEIAQAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Vaporgriffin:BAAANQAECgQICQAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgMIAwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgIIAgAAAA==.Veleria:BAABNQAECn8nAAMXAAgKqBgySwA5AgAXAAgKqBgySwA5AgAOAAYK5RiRJwCdAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgIIAgAAAA==.',
Vi='Victra:BAAANQAECgYIEwAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgQIBQAAAA==.Vinaya:BAAANQAECgIIAgAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQALAAAAAA==.',
Vo='Volthemar:BAABNQAECn8nAAMYAAgKuiECOQDeAgAYAAgK0yACOQDeAgAhAAQK1hxNJAAfAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIIAgAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCggIDwABNQAECgUICgALAAAAAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn8iAAIHAAgKtQiEzAB8AQAHAAgKtQiEzAB8AQAAAA==.',
Wh='Whatevyr:BAAANQADCgYIDAAAAA==.Whitespot:BAAANQAECgEIAQAAAA==.',
Wi='Wilson:BAAANQADCgYIBwABNQAECgYIDAALAAAAAA==.Wisegurl:BAABNQAECn8aAAMHAAkK9BsRRQDCAgAHAAkK9BsRRQDCAgAOAAIKUBfuYABVAAAAAA==.',
Wo='Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn8fAAIIAAgK1w+6RgDOAQAIAAgK1w+6RgDOAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgMIBwAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wylecsham:BAAANQADCgUJBQAAAA==.Wylectra:BAABNQAECn8pAAIZAAgKSA9fbwDLAQAZAAgKSA9fbwDLAQAAAA==.',
Xe='Xethos:BAAANQAECggICAAAAA==.',
Xy='Xyleeha:BAAANQADCggIDwAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn8pAAMBAAgKfwxihgD7AQABAAgKfwxihgD7AQAUAAEKAACAoAAPAAAAAA==.Yerdedmatey:BAAANQAECgEIAQAAAA==.',
Yo='Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn8qAAINAAkK7xkxLwCiAgANAAkK7xkxLwCiAgAAAA==.Zahvaria:BAAANQAECgUICQAAAA==.Zalson:BAAANQABCgYJBgAAAA==.Zamari:BAAANQADCgYIDwABNQAECgUICQALAAAAAA==.Zaphiell:BAABNQAECn8aAAIgAAgKrRZVIgAeAgAgAAgKrRZVIgAeAgAAAA==.',
Ze='Zeid:BAABNQAECn8aAAIYAAkK/g7wggAQAgAYAAkK/g7wggAQAgAAAA==.Zev:BAAANQAECgIIAgAAAA==.',
Zi='Zillz:BAAANQAECgMIAwAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECgYIGQALAAAAAQ==.',
Zl='Zlightnin:BAAANQADCgcIEAAAAA==.',
Zo='Zoeystorm:BAABNQAECn8aAAMHAAYKOgcBAgEVAQAHAAYKOgcBAgEVAQAOAAEKAABGcQAsAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAICAAkKEBT0QgAMAgACAAkKEBT0QgAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAABNQAECn8lAAQBAAgKWBtkXgBYAgABAAgKWBtkXgBYAgAUAAIK8AacdwBbAAASAAEKKwXBFAAkAAAAAA==.',
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
