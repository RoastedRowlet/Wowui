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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Priest-Holy','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Priest-Discipline','Warrior-Fury','Evoker-Devastation','Shaman-Elemental','Hunter-Marksmanship','Warrior-Protection','Monk-Windwalker','Rogue-Assassination','Evoker-Augmentation','Monk-Mistweaver','Shaman-Enhancement','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acehigh:BAAANQABCgYICgABNQAFFAgIIwABAEcaAA==.Acemage:BAABNQAECn8lAAICAAoKDhGgsgAeAgACAAoKDhGgsgAeAgABNQAFFAgIIwABAEcaAA==.',
Ae='Aegon:BAABNQAECn9GAAQDAAoKeyMTHwDRAgADAAoKeyMTHwDRAgAEAAoK9wnEbgA6AQAFAAMKyg8ioQBFAAAAAA==.Aelivalor:BAAANQAECgEIAgAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn9BAAMGAAoK4R8PCgDpAQAGAAYKWx8PCgDpAQACAAgKqR4lZQDaAQAAAA==.',
Ah='Ahdonis:BAAANQAECggIEQAAAA==.Ahnerfays:BAAANQAECgYICwABNQAECgoKPQAHAHEgAA==.',
Ai='Aiara:BAAANQAECgIIAgAAAA==.Aiarra:BAABNQAECn8+AAMIAAoKVRUSQQD0AQAIAAoKVRUSQQD0AQAJAAcKEw86NAA3AQAAAA==.Aindriana:BAABNQAECn82AAIKAAkKSwtwLACXAQAKAAkKSwtwLACXAQAAAA==.Aiondormi:BAAANQAECgUIBgABNQAECggIAgALAAAAAA==.Aitra:BAABNQAECn8nAAQMAAgK8wIAFgDFAAAMAAgK8wIAFgDFAAANAAUK6AFGIwF7AAAOAAEKUQKfiQAVAAAAAA==.',
Aj='Ajx:BAAANQAECgYICQABNQAECggIHQAPAPALAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECn8bAAIBAAgKLxXOkwDhAQABAAgKLxXOkwDhAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgoKOwAMAAYgAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alaeryth:BAAANQAECgYIDQABNQAECggIAgALAAAAAA==.Alerothon:BAABNQAECn9SAAIHAAoKWxcvZgBpAgAHAAoKWxcvZgBpAgAAAA==.Alestiana:BAABNQAECn9QAAIQAAoKmheLLgBSAgAQAAoKmheLLgBSAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgcICAAAAA==.',
Am='Amephyst:BAABNQAECn9AAAIRAAoKnhazFgCwAQARAAoKnhazFgCwAQAAAA==.Amnadores:BAABNQAECn8bAAICAAYK9geCLgE/AQACAAYK9geCLgE/AQABNQAECgoKOAANAE0XAA==.',
An='Andii:BAAANQAECgcICgAAAA==.Annati:BAACNQAFFH8LAAIQAAcKDhnoCwCOAQAQAAcKDhnoCwCOAQA1AAQKfysAAhAACgqTIXoVACMDABAACgqTIXoVACMDAAAA.Antarres:BAABNQAECn8sAAINAAoKiQnNrQB2AQANAAoKiQnNrQB2AQAAAA==.',
Ao='Aoba:BAABNQAECn85AAMRAAoKrh68FABdAgARAAgKMhy8FABdAgASAAgKZggVcABRAQAAAA==.',
Ap='Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAABNQAECn8rAAITAAoKZxo/GgD0AgATAAoKZxo/GgD0AgAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAQICgAFAJ4RAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECgoKPQAHAHEgAA==.Areaman:BAAANQAECgEIAQABNQAECggIKgACAAEiAA==.Aridam:BAAANQAECgQIBQAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisdrake:BAAANQAECggICQABNQADCgIIAgALAAAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgALAAAAAA==.Artemisshade:BAABNQAECn8uAAMUAAkKYxv7AQAsAgAUAAkKYxv7AQAsAgAVAAQKjBIcNQARAQABNQADCgIIAgALAAAAAA==.Arthillius:BAAANQAECgUIDgAAAA==.',
As='Asharà:BAAANQAECgEIAQAAAA==.Astro:BAAANQADCggIEAAAAA==.',
Au='Aurica:BAAANQAECgcICwAAAA==.Aurélìa:BAAANQAECgIIAgAAAA==.',
Av='Aviana:BAABNQAECn8aAAIWAAYKZAmlSQD0AAAWAAYKZAmlSQD0AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgUICQAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8yAAMBAAoKYxGvlgDbAQABAAoKphCvlgDbAQAXAAcK7AkNCQCyAQAAAA==.Bellaliel:BAAANQAECgQICQAAAA==.Belle:BAABNQAECn8cAAIHAAgK1Abs2QASAQAHAAgK1Abs2QASAQAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bigmoney:BAAANQAECgEIAwAAAA==.Bip:BAABNQAECn8ZAAMNAAkKpQ68igDMAQANAAgKkg28igDMAQAOAAIKnhFbWAB2AAAAAA==.Biscuitbob:BAAANQADCggICAABNQAECgYIFQABAMEHAA==.',
Bj='Bjornmodi:BAAANQAECgYIDgAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzlock:BAAANQAECgIIAgABNQAECgoKIQAIAIgZAA==.Blitzy:BAABNQAECn8hAAIIAAoKiBlNIADKAgAIAAoKiBlNIADKAgAAAA==.',
Bo='Bobbette:BAABNQAECn8YAAQTAAcK1Q8ikQBjAQATAAcK1Q8ikQBjAQAWAAMKlwb7YAB9AAAYAAEKnwPMMAAjAAABNQAECgoKIQAQALccAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Braegen:BAAANQAECgEIAQAAAA==.Breakwinds:BAAANQAECgcIEgAAAA==.Brenick:BAABNQAECn8ZAAIZAAgKxwtsFAAaAQAZAAgKxwtsFAAaAQAAAA==.Brewtalize:BAAANQABCgcICQAAAA==.Bringer:BAAANQAECgMIAwAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQAECgIIAgAAAA==.Broseph:BAAANQAECgEIAQAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQICAAAAA==.Burnie:BAABNQAECn8oAAIaAAgKkBX1CgCjAQAaAAgKkBX1CgCjAQAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAABNQAECn8eAAIbAAkKnRknJwA1AgAbAAkKnRknJwA1AgAAAA==.Camilah:BAABNQAECn8tAAIDAAoKyx0uEABxAgADAAoKyx0uEABxAgAAAA==.Capa:BAABNQAECn87AAQMAAoKBiBxBACUAgAMAAgKLyBxBACUAgANAAUKVxzrzgAsAQAOAAMKSBeiOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECn8cAAICAAoKkhtTmwBKAgACAAoKkhtTmwBKAgAAAA==.',
Ce='Celestiné:BAAANQAECgUICQAAAA==.Cemeteri:BAAANQAECgEIAQAAAA==.',
Ch='Chaingun:BAABNQAECn8kAAICAAoK4gnykABxAQACAAoK4gnykABxAQAAAA==.Chaps:BAAANQAECgMIAgAAAA==.Chelseac:BAABNQAECn8UAAQSAAUKKBC/0QDYAAASAAQKbg6/0QDYAAARAAUKAA53RwDQAAAHAAEK/wVAtgEtAAABNQAECgcIGQACAJMNAA==.Chilblain:BAABNQAECn9IAAIGAAoKohFHDAD3AQAGAAoKohFHDAD3AQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECn9dAAIcAAoKAR/xBgDRAgAcAAoKAR/xBgDRAgAAAA==.',
Ci='Cibochevski:BAAANQAECgEIAQABNQAECggIKQAdACsbAA==.Ciratorynth:BAABNQAECn8oAAIaAAoKHRO/EwATAgAaAAoKHRO/EwATAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8nAAIQAAoKESNZDwBIAwAQAAoKESNZDwBIAwAAAA==.',
Cl='Claferi:BAAANQADCgMIAwAAAA==.Clearlove:BAAANQAECgYIBgABNQAECgcIGQACAJMNAA==.Clearlovec:BAAANQAECgcICQABNQAECgcIGQACAJMNAA==.Closetfurry:BAABNQAECn8pAAIHAAcKpw854gBXAQAHAAcKpw854gBXAQAAAA==.',
Co='Codenheimer:BAAANQAECgUIDwAAAA==.Condor:BAAANQAECggIDQAAAA==.Corrinne:BAABNQAECn8yAAIHAAoKZholaABjAgAHAAoKZholaABjAgAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Crankk:BAAANQAECgEIAQAAAA==.Critmypänts:BAAANQAECgUIEQAAAA==.',
Cz='Czernobog:BAABNQAECn8eAAIRAAkK3hvODwAXAgARAAkK3hvODwAXAgAAAA==.',
Da='Daeshan:BAABNQAECn9FAAIeAAoKrRkCDwBYAgAeAAoKrRkCDwBYAgAAAA==.Dafirstone:BAAANQAECggIEwAAAA==.Dahealamon:BAAANQAECgUICAAAAA==.Daldolarette:BAABNQAECn81AAISAAoKWh9WGQATAwASAAoKWh9WGQATAwAAAA==.Daradevil:BAAANQADCgcIBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcIBwALAAAAAA==.Daralune:BAAANQAECgQIBwAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn9AAAMHAAoK9RpaRQBKAgAHAAoK9RpaRQBKAgARAAEKxwQWgQAbAAAAAA==.Dasecondone:BAABNQAECn8WAAMZAAYKrgprGwDAAAAPAAUKbged+wDlAAAZAAUKLgprGwDAAAAAAA==.Dathirdone:BAAANQADCggIIQAAAA==.Dawg:BAABNQAECn8WAAIGAAYK5xncEgB6AQAGAAYK5xncEgB6AQAAAA==.Days:BAAANQAECggICAABNQAECgoKFQAdACgcAA==.',
De='Deadlytankz:BAAANQAECgEIAQAAAA==.Deadval:BAAANQADCgcIEQAAAA==.Demonicfyre:BAECNQAFFH8RAAICAAUKDBkrIgDmAAACAAUKDBkrIgDmAAA1AAQKfygAAwIACgqoHpdVANUCAAIACgqaHZdVANUCAAYAAgpzJOscANgAAAAA.Demonstein:BAAANQAECgUIBgABNQAFFAUIDQAHAI4gAA==.Deslarion:BAAANQAECgEIAQAAAA==.Destros:BAABNQAECn8kAAIJAAgKwgdsNwAjAQAJAAgKwgdsNwAjAQAAAA==.',
Di='Dillon:BAAANQAECgQIBQAAAA==.Disdain:BAAANQAECgYICQABNQAFFAkJJgANAG0XAA==.',
Do='Donchap:BAAANQAECggIDgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQAECgIIAgABNQADCgQJBAALAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Dreadstar:BAAANQAECgEIAQAAAA==.Drucyllå:BAAANQADCgcIDgAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn84AAMDAAoKTB3OLACBAgADAAgKrB7OLACBAgAFAAgK+xjJQADEAQAAAA==.Drzip:BAABNQAECn8fAAICAAgKHg+z0gDhAQACAAgKHg+z0gDhAQAAAA==.Drzippy:BAAANQAECgcIDgAAAA==.',
Du='Duane:BAABNQAECn8VAAIBAAkKshLImQDUAQABAAkKshLImQDUAQAAAA==.Duskthrasher:BAABNQAECn8jAAIDAAgK1wXZQgDwAAADAAgK1wXZQgDwAAAAAA==.Duyii:BAAANQAECgIIAgABNQAECggIOgALAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8vAAIBAAoKSRZwPwCsAgABAAoKSRZwPwCsAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgUIDgAAAA==.',
['Dè']='Dèathknìght:BAAANQAECgEIAQAAAA==.',
Ea='Easterneon:BAAANQAECgUIDAABNQAECgcIGQACAJMNAA==.',
Ec='Ech:BAABNQAECn88AAIPAAoK2RpzOwBEAgAPAAoK2RpzOwBEAgAAAA==.',
Ei='Eiraveta:BAABNQAECn8jAAITAAkKSA1vgACXAQATAAkKSA1vgACXAQAAAA==.',
El='Eldrinn:BAAANQABCggIFQAAAA==.Elemental:BAABNQAECn8vAAICAAkKVgQfwQATAQACAAkKVgQfwQATAQAAAA==.Elendirs:BAAANQABCgYIGwAAAA==.Elisabeta:BAAANQAECgQIBwAAAA==.Ellois:BAAANQAECgYIDwAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAABNQAECn8aAAIbAAgK7QcgeAANAQAbAAgK7QcgeAANAQABNQAECgoKGQABAB8SAA==.',
Ep='Epicnoname:BAACNQAFFH8KAAIFAAQKnhGSDwDkAAAFAAQKnhGSDwDkAAA1AAQKfyQAAgUACgrOHIUgAIkCAAUACgrOHIUgAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAABNQAECn8bAAMMAAgKZQywDABYAQAMAAgKZQywDABYAQANAAUK0QIxHgGJAAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECggIDAAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIEAAcKoBlCSgDOAQAEAAcKoBlCSgDOAQABNQAECgoKFQAdACgcAA==.Fave:BAAANQADCgYIBgABNQAECgoKMQAQALQcAA==.',
Fe='Feannesse:BAAANQAECgcIEwAAAA==.Festival:BAABNQAECn8VAAIdAAoKKBz/BgBzAgAdAAoKKBz/BgBzAgAAAA==.',
Fi='Firebolt:BAABNQAECn8xAAMQAAoKtBzaIgCVAgAQAAoKtBzaIgCVAgAbAAUK1RAG9gCoAAAAAA==.Fitts:BAAANQAECgcIDQABNQAFFAYICQAJADUOAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHgAfAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAABNQAECn8cAAMSAAkKhw8ykAD2AAASAAYKBgcykAD2AAAHAAYKSQYwGgHzAAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAABNQAECn8VAAIBAAgKChxkWwBjAgABAAgKChxkWwBjAgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgYIDgALAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIEQAAAA==.',
Ga='Gaia:BAAANQAECgEIAQAAAA==.Garekk:BAABNQAECn8ZAAIBAAoKHxIiggAIAgABAAoKHxIiggAIAgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9eAAMFAAoKWCLLBQCEAwAFAAoKWCLLBQCEAwADAAgKmx1AIwCyAQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQAECgEIAgAAAA==.',
Go='Golldehammer:BAAANQAECgEIAQAAAA==.Goneville:BAABNQAECn8UAAIHAAoKghpIcgBKAgAHAAoKghpIcgBKAgAAAA==.Gornix:BAAANQADCgEIAQAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAABNQAECn8rAAMQAAoKHQSJdAA/AQAQAAoKHQSJdAA/AQAbAAEKZwE2BgEeAAAAAA==.Gruts:BAAANQAECgMIAwAAAA==.',
Gt='Gtx:BAABNQAECn8VAAIHAAYKjh0h1gBvAQAHAAYKjh0h1gBvAQAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggIDgABNQAECgIIAwALAAAAAA==.Gutworthy:BAAANQAECggIDgAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIEQAAAA==.Hallzy:BAAANQAECgMIBwAAAA==.Hallzypal:BAAANQAECgcIDgAAAA==.Hammerjane:BAABNQAECn8qAAISAAgKVBWKSgDXAQASAAgKVBWKSgDXAQAAAA==.Hamur:BAABNQAECn8jAAMYAAkKfxgsBAD4AQAYAAgK3hosBAD4AQATAAIKSQh11wBdAAAAAA==.Hargrim:BAAANQAECgYICwAAAA==.Hariyaki:BAABNQAECn8oAAIeAAgKkwmWLAAdAQAeAAgKkwmWLAAdAQAAAA==.Havebandaids:BAAANQAECgEIAQAAAA==.',
He='Heavywinner:BAABNQAECn8+AAMIAAoKVxssGQD+AgAIAAoKVxssGQD+AgAJAAYKww2QTgCsAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8rAAITAAoKJSXDEQA7AwATAAoKJSXDEQA7AwAAAA==.Hellmage:BAAANQADCgYIBwAAAA==.Hellsfury:BAAANQAECgQIBQAAAA==.Hellslayer:BAABNQAECn8bAAMdAAgKaRfdEQAJAgAdAAgKaRfdEQAJAgAPAAIK8AiGOAFjAAAAAA==.Hellwalker:BAAANQADCggILAAAAA==.Hellzy:BAAANQAECgEIAQAAAA==.',
Hi='Hickery:BAAANQAECgMIAwAAAA==.',
Hn='Hnof:BAAANQAECgEIAQABNQAFFAQICQATAMoRAA==.',
Ho='Holyfire:BAAANQADCgcIBwABNQAECgoKMQAQALQcAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAABNQAECn8qAAMPAAgKsgk5mQA3AQAPAAgKRQk5mQA3AQAdAAEKrgsaQAA0AAAAAA==.',
Hy='Hycini:BAAANQAECgUIBQABNQAECgoKUQADAHYWAA==.',
['Hâ']='Hârlot:BAABNQAECn8qAAIKAAgKgQ4INwBTAQAKAAgKgQ4INwBTAQAAAA==.',
['Hè']='Hèathen:BAAANQAECgEIAQAAAA==.',
Id='Idamage:BAAANQAECgEIAQABNQAECgoKKQAPAA8dAA==.',
Ig='Igetmoney:BAAANQABCgEIAQAAAA==.',
In='Ingenii:BAAANQAECgYIBQABNQAECgoKOwAMAAYgAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8UAAINAAYK9hgtDQA3AQANAAYK9hgtDQA3AQA1AAQKfyEAAg0ACgogIPYQAN8CAA0ACgogIPYQAN8CAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgMIAwAAAA==.Jaestra:BAAANQAECgEIAQABNQAECggIKgATAOIWAA==.Jaidah:BAAANQAECgMIAwAAAA==.Jaith:BAAANQAECgEIAwABNQAECgoKHAATAN0SAA==.Jamaicann:BAAANQADCgYIBgABNQAECggICAALAAAAAA==.Jansôlo:BAABNQAECn8XAAMBAAgKAiJLOQC+AgABAAgKAiJLOQC+AgAcAAMKiBS8XwCnAAAAAA==.Jaratri:BAACNQAFFH8KAAIXAAMKWA7NAQCgAAAXAAMKWA7NAQCgAAA1AAQKf1YAAhcACgrZHYUCAJkCABcACgrZHYUCAJkCAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8jAAICAAkKigiuEAFxAQACAAkKigiuEAFxAQAAAA==.',
Ka='Kaatu:BAAANQADCgMIAwAAAA==.Kaerovia:BAABNQAECn8hAAISAAkKHRWITwAtAgASAAkKHRWITwAtAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8nAAIbAAoKVBVoOgCMAgAbAAoKVBVoOgCMAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICQAAAA==.Karg:BAABNQAECn8YAAIHAAgK9whN1QBxAQAHAAgK9whN1QBxAQAAAA==.Karmai:BAABNQAECn9FAAMUAAoKMiE4AgBBAwAUAAkKYiA4AgBBAwAVAAoKmRidHwCAAgAAAA==.Karriane:BAAANQAECgMIAwABNQAECgoKRgARAN0WAA==.Kastigor:BAAANQAECgcIEwABNQAFFAQICwAKAPcSAA==.Katerina:BAAANQADCggIDwAAAA==.Kathine:BAABNQAECn8aAAIGAAYKVAfdGwDhAAAGAAYKVAfdGwDhAAAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgcIEAAAAA==.Kazue:BAAANQAECgYICwABNQAECgoKMgAHAGYaAA==.',
Ke='Keaa:BAABNQAECn8eAAMQAAoKKAwiYQB9AQAQAAoKKAwiYQB9AQAbAAYKEwifgwDxAAAAAA==.Kelvala:BAABNQAECn82AAMPAAoKwyO5JgAeAwAPAAoKFh+5JgAeAwAZAAcKLSQoCwASAgAAAA==.Kelwynd:BAABNQAECn8cAAIcAAgK8xpMEQAbAgAcAAgK8xpMEQAbAgAAAA==.Kesle:BAAANQADCgUIBQAAAA==.Keä:BAABNQAECn8oAAMSAAoKFgw5cADHAQASAAoKFgw5cADHAQAHAAkKQA6gzQAmAQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn9GAAIRAAoK3RZJFADQAQARAAoK3RZJFADQAQAAAA==.Kizzs:BAABNQAECn8hAAMFAAoKchpUIAA4AgAFAAoKeBlUIAA4AgADAAMKQh7FVwCaAAAAAA==.',
Ko='Kobesama:BAABNQAECn8rAAIPAAoKmA4dZwC1AQAPAAoKmA4dZwC1AQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8dAAMgAAgKCxHsCwCcAQAgAAgKCxHsCwCcAQAaAAIKWgb+NgBXAAAAAA==.Konata:BAAANQADCggIDwABNQAECgoKOQARAK4eAA==.Korbenzoo:BAAANQAECgUIBQABNQAECggIOgALAAAAAQ==.Korigan:BAAANQAECgcIDwAAAA==.',
Kr='Krom:BAAANQAECgEIAgABNQAECgoKKgAQAKoGAA==.Kryssie:BAABNQAECn86AAIBAAoK2xMZYgDpAQABAAoK2xMZYgDpAQAAAA==.',
Ku='Kudrah:BAAANQAECgEIAQABNQAECgkJHAAIAI0UAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIhAAcKIwgkKgAfAQAhAAcKIwgkKgAfAQAAAA==.',
['Ká']='Kárg:BAAANQAECgUICQABNQAECggIGAAHAPcIAA==.',
La='Lahee:BAAANQAECgQIBAAAAA==.Lampard:BAAANQAECgcICwABNQAECgoKJgAEADAhAA==.Lanaya:BAABNQAECn8mAAIHAAkKaxC7rQBeAQAHAAkKaxC7rQBeAQAAAA==.Laserheadten:BAACNQAFFH8GAAIWAAMKcA+PDAC1AAAWAAMKcA+PDAC1AAA1AAQKfykAAhYACgpIHLQUAL0CABYACgpIHLQUAL0CAAAA.Laudna:BAAANQAECgcIBwABNQAECggIEQALAAAAAA==.Lawrensce:BAAANQAECgQIEQAAAA==.',
Le='Leanore:BAAANQAECgEIAgABNQAECgkJOgAIAKoKAA==.Lencho:BAAANQAECgIIBgAAAA==.Lenchodude:BAABNQAECn8eAAIFAAgKxQ2iSABeAQAFAAgKxQ2iSABeAQAAAA==.Lenian:BAABNQAECn8pAAIdAAgKKxvzDADXAQAdAAgKKxvzDADXAQAAAA==.Leâfs:BAABNQAECn8UAAMDAAYKiRMUbwBYAQADAAYKiRMUbwBYAQAFAAUKrQcpfwCuAAAAAA==.',
Li='Lichekinky:BAAANQAECgUICgAAAA==.Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIBAAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAABNQAECn8aAAMRAAYKjRNqLgDxAAARAAUKtBZqLgDxAAAHAAYKkgM/KwGWAAAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAALAAAAAA==.Lostangell:BAAANQABCgMIAwAAAA==.Lourom:BAABNQAECn8lAAMBAAoKVRB8WAACAgABAAoKThB8WAACAgAcAAYKxgx0SwAIAQAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQAECgEIAQAAAA==.Lunariel:BAABNQAECn8dAAIPAAgK8AtVkQBJAQAPAAgK8AtVkQBJAQAAAA==.',
Ly='Lyraae:BAABNQAECn8iAAIQAAkKtREufgCRAQAQAAkKtREufgCRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Madtankage:BAAANQADCgMIAwAAAA==.Maegh:BAAANQADCgIIAgAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn9lAAMBAAoKTB06JACgAgABAAoKTB06JACgAgAcAAMK6wlxTwBbAAAAAA==.Maiganoss:BAABNQAECn8YAAMEAAgK/RZaIQDgAQAEAAgK/RZaIQDgAQADAAEKpQJ1AAEXAAAAAA==.Mardon:BAAANQABCgYICwABNQABCgYIGwALAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAABNQAECn8aAAICAAoKdwqExgD3AQACAAoKdwqExgD3AQAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBgAAAA==.',
Me='Megid:BAABNQAECn8jAAIRAAkKdR7YFQBQAgARAAkKdR7YFQBQAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8tAAIFAAoK0xmFJQBoAgAFAAoK0xmFJQBoAgAAAA==.Methalos:BAAANQABCgIIAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAABNQAECn8XAAIiAAgKjwUTIQAAAQAiAAgKjwUTIQAAAQABNQAECgkJOgAIAKoKAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgcIEAAAAA==.Mimie:BAAANQAECggIBQAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAABNQAECn8gAAICAAoKyQs2agDNAQACAAoKyQs2agDNAQAAAA==.Mizblumkin:BAABNQAECn8UAAIGAAkKYxENEgCFAQAGAAkKYxENEgCFAQAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moodoom:BAAANQAECgQIBAAAAA==.Moogyver:BAAANQAECggIAgAAAA==.Moomoom:BAAANQAECgYIEgAAAA==.Moonbeard:BAAANQADCgMIAwAAAA==.Moonfizzle:BAAANQAECgQIBwAAAA==.Moonnshine:BAABNQAECn8hAAMIAAkKEwV0YwBAAQAIAAkKEwV0YwBAAQAJAAYKXwIjVgCvAAAAAA==.Moonrend:BAAANQAECgYIDgAAAA==.Moonzire:BAAANQAECgYICgAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECggIOgALAAAAAQ==.',
Mu='Muradil:BAAANQAECgEIAQAAAA==.Murgrot:BAAANQADCgcIEQAAAA==.',
My='Mylittlepwni:BAAANQAECgQICQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcIBwAAAA==.',
['Mû']='Mûffin:BAAANQAECgcICAAAAA==.',
Na='Nainel:BAAANQAECgEIAQABNQAECggIKQAdACsbAA==.Nakros:BAAANQAECgYICAAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECggIKgACAAEiAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECggIEQAAAA==.Nerik:BAAANQAECgQICAAAAA==.Nerissa:BAEANQAECggIEgAAAA==.Netallia:BAAANQAECgEIAgAAAA==.',
Ng='Ngyue:BAAANQADCgYIJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAIBAAcKbxq9agA+AgABAAcKbxq9agA+AgAAAA==.Nickto:BAABNQAECn8YAAIHAAYKuQIYTwFrAAAHAAYKuQIYTwFrAAAAAA==.Nightshayed:BAAANQAECgEIAQAAAA==.Niishaa:BAAANQAECgYIBQABNQAECggIIwADANcFAA==.Niëtz:BAAANQAECgEIBAAAAA==.',
Nr='Nrm:BAAANQAECgEIBAAAAA==.',
Nu='Nubin:BAAANQAECgMIAwAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECggIHQAPAPALAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Oa='Oaknsheild:BAAANQADCgUIBQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIFQABAMEHAA==.',
On='Onsight:BAAANQAECgEIAQAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECggIGgAeADIUAA==.Ophnakyel:BAAANQADCgEIAQAAAA==.',
Or='Orceo:BAAANQAECgEIAQAAAA==.Orcrest:BAAANQAECgUIDgAAAA==.Ororo:BAABNQAECn8qAAIbAAkK1BlyRABkAgAbAAkK1BlyRABkAgAAAA==.',
Pa='Painmender:BAAANQAECgQIBAAAAA==.Palal:BAAANQAECgEIAQABNQAECgcIFAAHAOEiAA==.Paog:BAAANQADCggIEAAAAA==.Paryah:BAABNQAECn8qAAIVAAgKBAizdAAqAQAVAAgKBAizdAAqAQAAAA==.Pauken:BAAANQAECgcIDAABNQAECgoKOwAMAAYgAA==.',
Ph='Phanceester:BAAANQAECgUICgAAAA==.Phindra:BAAANQAECgQIBgAAAA==.Phonut:BAAANQADCgcIDQAAAA==.Phréek:BAABNQAECn9HAAMSAAoK3BwkFwDuAgASAAoK3BwkFwDuAgAHAAkKnxWfcADaAQAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAACNQAFFH8UAAIEAAYKYAwDEgA3AQAEAAYKYAwDEgA3AQA1AAQKf1cAAgQACgq8HqcLANECAAQACgq8HqcLANECAAAA.',
Po='Poetea:BAAANQAECggICwAAAA==.Portalslag:BAAANQAECggIDAAAAA==.',
Pr='Praze:BAAANQAECgUIDgAAAA==.',
Pu='Punyboy:BAAANQAECgQIBQAAAA==.Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.Rahis:BAABNQAECn8+AAMBAAoKxBbFSAArAgABAAoKxBbFSAArAgAcAAEKeAOJkQAuAAAAAA==.Raiu:BAABNQAECn8qAAIQAAgKmhmkOgAXAgAQAAgKmhmkOgAXAgAAAA==.Ramsis:BAABNQAECn8hAAIQAAoKtxx2RgBHAgAQAAoKtxx2RgBHAgAAAA==.Randir:BAABNQAECn9KAAIWAAoKvBn7DgBWAgAWAAoKvBn7DgBWAgAAAA==.Ranir:BAAANQAECgMICAAAAA==.Rath:BAABNQAECn8gAAIeAAkKwRpIJQD5AQAeAAkKwRpIJQD5AQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgYIEgAAAA==.Remedivhs:BAAANQAECgQIBAABNQAECggIOgALAAAAAQ==.Rettbull:BAAANQAECgEIAQAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAABNQAECn8ZAAICAAYKwAfCNwEwAQACAAYKwAfCNwEwAQABNQAECggIIwAEALISAA==.Rhyli:BAAANQAECgEIAQAAAA==.',
Ro='Robinhoodx:BAABNQAECn9EAAIBAAoKixuGPABOAgABAAoKixuGPABOAgAAAA==.Rockbottom:BAAANQAECgEIAQABNQAECggIKgAEAIkWAA==.Roenabur:BAAANQAECgEIAgAAAA==.Romok:BAAANQAECgUIEgAAAA==.Rosaline:BAAANQAECgQICAAAAA==.',
Ru='Rubysunday:BAAANQAECgEIAgAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rà']='Ràyne:BAAANQADCggIGwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8pAAIHAAgKFg2v1QBwAQAHAAgKFg2v1QBwAQAAAA==.Saintandrew:BAAANQAECgQIBAAAAA==.Samoot:BAABNQAECn86AAIIAAkKqgooMwBbAQAIAAkKqgooMwBbAQAAAA==.Sanguina:BAAANQADCgYIBgAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQADCgYIFwABNQAECggIOgALAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAABNQAECn8qAAINAAgKtwrIhwA5AQANAAgKtwrIhwA5AQAAAA==.Shamanstein:BAAANQADCggJDwABNQAFFAUIDQAHAI4gAA==.Shammbo:BAAANQAECggIEgAAAA==.Sharty:BAAANQAECggIEwAAAA==.Shazra:BAABNQAECn8YAAIJAAoKEggcLgBiAQAJAAoKEggcLgBiAQAAAA==.Sheriruth:BAAANQAECggIEAABNQAECgoKOwAMAAYgAA==.Shifthappenz:BAAANQAECgYIBwAAAA==.Shortigen:BAAANQAECgUIDgAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.Shuub:BAABNQAECn8XAAIdAAoKCiU+AQBcAwAdAAoKCiU+AQBcAwAAAA==.',
Si='Sicnus:BAAANQADCggIEAAAAA==.Silveryl:BAABNQAECn8aAAMeAAgKMhRQGwC1AQAeAAgKMhRQGwC1AQAhAAQKgQytKQCjAAAAAA==.Sinadin:BAABNQAECn9HAAIHAAoK4BVNVAAfAgAHAAoK4BVNVAAfAgAAAA==.Sindoreisins:BAABNQAECn8eAAITAAoKkxAKXgCxAQATAAoKkxAKXgCxAQAAAA==.Sizzlinghots:BAABNQAECn8/AAIJAAoKshJBFgBSAgAJAAoKshJBFgBSAgAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIIgATAO4LAA==.Skolmaster:BAABNQAECn8mAAICAAoKSxMlTgAWAgACAAoKSxMlTgAWAgAAAA==.Skootter:BAAANQAECgEIAgAAAA==.Skyfury:BAABNQAECn8oAAMQAAkKbhSWUwCtAQAQAAkKbhSWUwCtAQAbAAcKwBIIlgBtAQABNQAECgoKMQAQALQcAA==.Skywalkr:BAAANQAECgEIAQAAAA==.',
Sm='Smarky:BAACNQAFFH8IAAIWAAUKNw1tCwDLAAAWAAUKNw1tCwDLAAA1AAQKfxkAAhYACgouHiwOAAsDABYACgouHiwOAAsDAAAA.Smâlls:BAEBNQAECn8pAAIjAAgKeRlbCQChAQAjAAgKeRlbCQChAQAAAA==.',
Sn='Sneekie:BAAANQAECgEIAQAAAA==.Sneekiemage:BAAANQAECgQIDwAAAA==.Snugz:BAAANQAECgEIAgAAAA==.',
So='Sourdiesel:BAABNQAECn8fAAIBAAkKmQdClwBqAQABAAkKmQdClwBqAQAAAA==.Southsound:BAABNQAECn8ZAAICAAcKkw3JAQGLAQACAAcKkw3JAQGLAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQALAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQAECgUIDQAAAA==.Steakknife:BAABNQAECn8VAAMfAAgKZhHkMQAXAgAfAAgKZhHkMQAXAgAVAAYK2AViMgApAQAAAA==.Stikybandage:BAAANQADCgcIBwAAAA==.Stormoon:BAABNQAECn8nAAMbAAkKkA35aQAyAQAbAAgKRwz5aQAyAQAQAAcKxQv+qwAZAQAAAA==.Streigar:BAAANQAECgMIAwAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.Superrad:BAAANQAECgEIAgAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgQIBAAAAA==.',
Sy='Sybil:BAABNQAECn8cAAIIAAkKjRSLJwCsAQAIAAkKjRSLJwCsAQAAAA==.Sylvarus:BAAANQAECgEIAgAAAA==.',
Sz='Szer:BAAANQAECgUIBgAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAABNQAECn8mAAIBAAgK2wSluAAlAQABAAgK2wSluAAlAQAAAA==.Tahtiania:BAABNQAECn8eAAICAAkK2AUorAA5AQACAAkK2AUorAA5AQAAAA==.Talkurandis:BAAANQAECgcIGQABNQAECggIOgALAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Tc='Tchamen:BAAANQAECgEIAQAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn8vAAIDAAoKGiHJCgC9AgADAAoKGiHJCgC9AgAAAA==.Tenma:BAAANQAECgUIBQABNQAECgoKOQARAK4eAA==.Teo:BAABNQAECn8jAAIBAAkKkRAYlwDaAQABAAkKkRAYlwDaAQAAAA==.Terraria:BAAANQAECgEIAgABNQAECgoKRQAUADIhAA==.Teyamat:BAAANQAECgcIDQABNQAECgoKLwADABohAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8mAAMQAAoK7BzXHQD1AgAQAAoK7BzXHQD1AgAbAAMKqhGc9ACsAAAAAA==.Theory:BAAANQAECgUIBQAAAA==.Thetree:BAABNQAECn8nAAMJAAkKrRviFAChAgAJAAkKrRviFAChAgAIAAcK+xsvPgAHAgAAAA==.Thien:BAAANQAECgEIAQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIIgATAO4LAA==.Thoughtcrime:BAAANQAECgcIDAAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8yAAIYAAoKKxs0AgCsAgAYAAoKKxs0AgCsAgAAAA==.',
Ti='Timoris:BAAANQAECgUIBwABNQAECgoKOwAMAAYgAA==.',
To='Tobiume:BAAANQAECgYIDQABNQAECgoKOAANAE0XAA==.Tofulhundun:BAAANQAECgEIAgAAAA==.Toggo:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAABNQAECn8VAAIBAAYKwQdy0QBeAQABAAYKwQdy0QBeAQAAAA==.Toodles:BAAANQADCggIHgAAAA==.Totempoe:BAAANQAECgEIAQABNQAECggICwALAAAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIBwAAAA==.Triannah:BAAANQAECgQICwAAAA==.Trildjr:BAABNQAECn8bAAIBAAgKNBCugwCWAQABAAgKNBCugwCWAQAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn8vAAIbAAkK7wlsiACPAQAbAAkK7wlsiACPAQAAAA==.',
Ty='Tyronda:BAAANQADCggIJAAAAA==.Tyrse:BAABNQAECn8aAAIXAAcKJgcTCwD4AAAXAAcKJgcTCwD4AAAAAA==.',
Tz='Tzerina:BAABNQAECn8fAAIKAAcKfA/QPgAmAQAKAAcKfA/QPgAmAQAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECggIOgAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8nAAISAAoKcRCGbQDPAQASAAoKcRCGbQDPAQAAAA==.Validan:BAAANQAECgUIDQAAAA==.Valkriss:BAAANQAECgEIAQAAAA==.Vallyrie:BAABNQAECn8uAAMEAAoKxRoUJADLAQAEAAkKfxoUJADLAQADAAcKMRWVYwCCAQAAAA==.Valssharess:BAABNQAECn8sAAIkAAgKeh3WEwDnAQAkAAgKeh3WEwDnAQAAAA==.Valth:BAAANQAECgQIBwAAAA==.Valweyna:BAAANQADCgIIAgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Vaporgriffin:BAAANQAECgcIEwAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgYIBwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgUIDgAAAA==.Veleria:BAABNQAECn8vAAMSAAkKehj0SwA5AgASAAkKehj0SwA5AgARAAYK5RgZKACdAQAAAA==.Vellysonna:BAAANQAECgEIAgAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgUIDQAAAA==.',
Vi='Victra:BAABNQAECn8fAAITAAoK2xCxUwDVAQATAAoK2xCxUwDVAQAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgcIEQAAAA==.Vinaya:BAAANQAECgUIDgAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQALAAAAAA==.',
Vo='Volthemar:BAABNQAECn9CAAQPAAoKNiKYJgCbAgAPAAoK4CCYJgCbAgAdAAQK1hzaJAAfAQAZAAMKAR8WHAC4AAAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQAECgEIAQAAAA==.',
Wa='Wanabe:BAAANQADCgUIBQAAAA==.Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQAECgEIAQABNQAECggIKAAaAJAVAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn85AAIHAAoKmwnWoAB2AQAHAAoKmwnWoAB2AQAAAA==.',
Wh='Whatevyr:BAAANQAECgEIAQAAAA==.Whitespot:BAAANQAECgQIAwAAAA==.',
Wi='Wilson:BAAANQAECgEIAQABNQAECggIKgACAAEiAA==.Wisegurl:BAABNQAECn8rAAMHAAoKoiJkNgB8AgAHAAoKLSJkNgB8AgARAAUKBBbkSABwAAAAAA==.',
Wo='Woblatus:BAAANQAECgIIAgABNQAECggIOgALAAAAAQ==.Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn8xAAIIAAoK6RETJADHAQAIAAoK6RETJADHAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgQICwAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wylecsham:BAAANQAECgUIBgAAAA==.Wylectra:BAABNQAECn8/AAITAAoKLRSxPAAzAgATAAoKLRSxPAAzAgAAAA==.',
Xe='Xethos:BAAANQAECggICAAAAA==.',
Xy='Xyleeha:BAAANQADCggIGwAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn9FAAMBAAoKgA6kWQD/AQABAAoKgA6kWQD/AQAcAAEKAADjogAPAAAAAA==.Yerdedmatey:BAAANQAECgIIAgAAAA==.',
Yo='Yomiko:BAAANQABCgYICgABNQAECgoKOQARAK4eAA==.Yoshikatsu:BAAANQADCggICAAAAA==.Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn9KAAIQAAoKVBzJIQCdAgAQAAoKVBzJIQCdAgAAAA==.Zahvaria:BAABNQAECn8dAAIVAAcKTgbKjADdAAAVAAcKTgbKjADdAAAAAA==.Zalson:BAAANQAECgEIAQAAAA==.Zamari:BAAANQAECgEIAQABNQAECgcIHQAVAE4GAA==.Zaphiell:BAABNQAECn8eAAIWAAkK2hWqIgAeAgAWAAkK2hWqIgAeAgAAAA==.Zazzy:BAEANQAECgUIBwABNQAFFAQIEgAcAL0QAA==.',
Ze='Zeid:BAABNQAECn8bAAIPAAoK2g2jhAAQAgAPAAoK2g2jhAAQAgAAAA==.Zev:BAAANQAECgYIDwAAAA==.',
Zi='Zillz:BAABNQAECn8gAAISAAoK5w2zQAD/AQASAAoK5w2zQAD/AQAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECggIOgALAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgIIBAAAAA==.',
Zo='Zoeystorm:BAABNQAECn8yAAMRAAkKTQgzPACoAAAHAAgK/wfk5wD7AAARAAcKIAUzPACoAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAIDAAkKEBSYQwAMAgADAAkKEBSYQwAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAACNQAFFH8HAAQBAAQKyAjNIwCCAAABAAIKKwnNIwCCAAAcAAMK1gWhFwB0AAAXAAEKrAmAAgBEAAA1AAQKfzgABAEACgpEG69fAFgCAAEACgpEG69fAFgCABwABwo4DHAiAEMBABcAAgpjCFwQAFMAAAAA.',
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
