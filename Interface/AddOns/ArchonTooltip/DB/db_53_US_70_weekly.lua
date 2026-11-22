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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Priest-Holy','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Priest-Discipline','Shaman-Elemental','Warrior-Fury','Evoker-Devastation','Hunter-Marksmanship','Monk-Windwalker','Warrior-Protection','Rogue-Assassination','Shaman-Enhancement','Evoker-Augmentation','Monk-Mistweaver','Druid-Guardian','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acehigh:BAAANQABCgYICgABNQAFFAgIIwABAEcaAA==.Acemage:BAABNQAECn8lAAICAAoKDhGgsgAeAgACAAoKDhGgsgAeAgABNQAFFAgIIwABAEcaAA==.',
Ae='Aegon:BAABNQAECn9GAAQDAAoKeyMTHwDRAgADAAoKeyMTHwDRAgAEAAoK9wnEbgA6AQAFAAMKyg/DqQBFAAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn9LAAMGAAoKGiA2CwDtAQACAAkKkB6LPgBSAgAGAAYKqB82CwDtAQAAAA==.',
Ah='Ahdonis:BAAANQAECggIEAAAAA==.Ahnerfays:BAAANQAECgcICgABNQAECgoKPQAHAHEgAA==.',
Ai='Aiara:BAAANQAECgIIAQAAAA==.Aiarra:BAABNQAECn9DAAMIAAoKVRUSQQD0AQAIAAoKVRUSQQD0AQAJAAcKEw+kOAA2AQAAAA==.Aindriana:BAABNQAECn86AAIKAAkK+AuaLgCgAQAKAAkK+AuaLgCgAQAAAA==.Aiondormi:BAAANQAECgUIBQABNQAECggIAgALAAAAAA==.Aitra:BAABNQAECn8oAAQMAAkKFQPgFQDcAAAMAAkKFQPgFQDcAAANAAUK6AFGIwF7AAAOAAEKUQKfiQAVAAAAAA==.',
Aj='Ajx:BAAANQAECgYICAABNQAECgkJHgAPAKMMAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECn8cAAIBAAkKpRLOkwDhAQABAAkKpRLOkwDhAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgoKOwAMAAYgAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alaeryth:BAAANQAECgYIDQABNQAECggIAgALAAAAAA==.Alerothon:BAABNQAECn9TAAIHAAoKWhgHYwAMAgAHAAoKWhgHYwAMAgAAAA==.Alestiana:BAABNQAECn9XAAIQAAoK9hqoHQDNAgAQAAoK9hqoHQDNAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgcICAAAAA==.',
Am='Amephyst:BAABNQAECn9HAAIRAAoKEBehGACxAQARAAoKEBehGACxAQAAAA==.Amnadores:BAABNQAECn8bAAICAAYK9geCLgE/AQACAAYK9geCLgE/AQABNQAECgoKQQANAFUZAA==.',
An='Andii:BAAANQAECgcICgAAAA==.Annati:BAACNQAFFH8LAAIQAAcKDhnoCwCOAQAQAAcKDhnoCwCOAQA1AAQKfysAAhAACgqTIXoVACMDABAACgqTIXoVACMDAAAA.Antarres:BAABNQAECn8sAAINAAoKiQnNrQB2AQANAAoKiQnNrQB2AQAAAA==.',
Ao='Aoba:BAABNQAECn87AAMRAAoKrh68FABdAgARAAgKMhy8FABdAgASAAgKZgh+dwBOAQAAAA==.',
Ap='Apila:BAAANQAECgEIAQABNQAECggIPQALAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAABNQAECn8rAAITAAoKZxobHgDrAgATAAoKZxobHgDrAgAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAQICgAFAJ4RAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECgoKPQAHAHEgAA==.Areaman:BAAANQAECgEIAQABNQAECgkJMgACAHUgAA==.Aridam:BAAANQAECgQIBAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisdrake:BAAANQAECggIEQABNQADCgIIAgALAAAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgALAAAAAA==.Artemisshade:BAABNQAECn8uAAMUAAkKYxspAgAoAgAUAAkKYxspAgAoAgAVAAQKjBIcNQARAQABNQADCgIIAgALAAAAAA==.Arthillius:BAAANQAECgUIDQAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Au='Aurica:BAAANQAECggIDAAAAA==.Aurélìa:BAAANQAECgIIAgAAAA==.',
Av='Aviana:BAABNQAECn8aAAIWAAYKZAmlSQD0AAAWAAYKZAmlSQD0AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgUICAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8yAAMBAAoKYxGvlgDbAQABAAoKphCvlgDbAQAXAAcK7AkNCQCyAQAAAA==.Bellaliel:BAAANQAECgQICQAAAA==.Belle:BAABNQAECn8hAAMHAAgKRAi94AAcAQAHAAgKdQe94AAcAQARAAMK1AyUZQAxAAAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECn8ZAAMNAAkKpQ68igDMAQANAAgKkg28igDMAQAOAAIKnhFbWAB2AAAAAA==.Biscuitbob:BAAANQADCggICAABNQAECgYIFQABAMEHAA==.',
Bj='Bjornmodi:BAAANQAECgYIDgAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzlock:BAAANQAECgIIAgABNQAECgoKIQAIAIgZAA==.Blitzy:BAABNQAECn8hAAIIAAoKiBlNIADKAgAIAAoKiBlNIADKAgAAAA==.',
Bo='Bobbette:BAABNQAECn8YAAQTAAcK1Q8ikQBjAQATAAcK1Q8ikQBjAQAWAAMKlwb7YAB9AAAYAAEKnwPMMAAjAAABNQAECgoKIQAQALccAA==.Bonejovi:BAAANQAECgEIAgAAAA==.Boomchaka:BAAANQAECgQIBwAAAA==.',
Br='Braegen:BAAANQAECgEIAQAAAA==.Breakwinds:BAABNQAECn8bAAMQAAcKGwUPmQDvAAAQAAcKGwUPmQDvAAAZAAQK3QGA3wBYAAAAAA==.Brenick:BAABNQAECn8ZAAIaAAgKxwttFgAXAQAaAAgKxwttFgAXAQAAAA==.Brewtalize:BAAANQAECgMIAwAAAA==.Brewzlee:BAAANQAECgYIBgAAAA==.Bringer:BAAANQAECgMIAwAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQAECgIIAgAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQIBAAAAA==.Burnie:BAABNQAECn8wAAIbAAkKmxX1CADvAQAbAAkKmxX1CADvAQAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAABNQAECn8eAAIZAAkKnRlgKwAwAgAZAAkKnRlgKwAwAgAAAA==.Camilah:BAABNQAECn8tAAIDAAoKyx2yEQBsAgADAAoKyx2yEQBsAgAAAA==.Capa:BAABNQAECn87AAQMAAoKBiBxBACUAgAMAAgKLyBxBACUAgANAAUKVxzrzgAsAQAOAAMKSBeiOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECn8cAAICAAoKkhtTmwBKAgACAAoKkhtTmwBKAgAAAA==.',
Ce='Celestiné:BAAANQAECgUICAAAAA==.',
Ch='Chaingun:BAABNQAECn8lAAICAAoK4gkcmgBwAQACAAoK4gkcmgBwAQAAAA==.Chaps:BAAANQAECgMIAgAAAA==.Chelseac:BAAANQAECgUIEwABNQAECgcIGQACAJMNAA==.Chilblain:BAABNQAECn9RAAIGAAoK3BFHDAD3AQAGAAoK3BFHDAD3AQAAAA==.Chobii:BAABNQAECn9kAAIcAAoKAR+4BwDLAgAcAAoKAR+4BwDLAgAAAA==.',
Ci='Ciratorynth:BAABNQAECn8oAAIbAAoKHRO/EwATAgAbAAoKHRO/EwATAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8nAAIQAAoKESNZDwBIAwAQAAoKESNZDwBIAwAAAA==.',
Cl='Claferi:BAAANQADCgMIAwAAAA==.Clearlove:BAAANQAECgYIBAABNQAECgcIGQACAJMNAA==.Clearlovec:BAAANQAECgcICAABNQAECgcIGQACAJMNAA==.Closetfurry:BAABNQAECn8sAAIHAAkKrw1vtABoAQAHAAkKrw1vtABoAQAAAA==.',
Co='Codenheimer:BAAANQAECgYIDwAAAA==.Condor:BAAANQAECggICwAAAA==.Corrinne:BAABNQAECn84AAIHAAoKtRslaABjAgAHAAoKtRslaABjAgAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Crankk:BAAANQAECgEIAQAAAA==.Critmypänts:BAAANQAECgUIEAAAAA==.',
Cz='Czernobog:BAABNQAECn8eAAIRAAkK3huMEQATAgARAAkK3huMEQATAgAAAA==.',
Da='Daeshan:BAABNQAECn9OAAIdAAoK9Bz7CgCxAgAdAAoK9Bz7CgCxAgAAAA==.Dafirstone:BAAANQAECggIEwAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECn81AAISAAoKWh9WGQATAwASAAoKWh9WGQATAwAAAA==.Daradevil:BAAANQADCgcIBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcIBwALAAAAAA==.Daralune:BAAANQAECgQIBwAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn9FAAMHAAoKixsARwBVAgAHAAoKixsARwBVAgARAAEKxwQWgQAbAAAAAA==.Dasecondone:BAABNQAECn8WAAMaAAYKrgpiHgC8AAAPAAUKbged+wDlAAAaAAUKLgpiHgC8AAAAAA==.Dathirdone:BAAANQADCggIIQAAAA==.Dawg:BAABNQAECn8XAAIGAAYK5xncEgB6AQAGAAYK5xncEgB6AQAAAA==.Days:BAAANQAECggICAABNQAECgoKFQAeACgcAA==.',
De='Deadval:BAAANQADCggIEQAAAA==.Demonicfyre:BAECNQAFFH8RAAICAAUKDBkJJwDcAAACAAUKDBkJJwDcAAA1AAQKfygAAwIACgqoHpdVANUCAAIACgqaHZdVANUCAAYAAgpzJIMfANgAAAAA.Demonstein:BAAANQAECgUIBQABNQAFFAUIDQAHAI4gAA==.Deslarion:BAAANQADCgYICwAAAA==.Destros:BAABNQAECn8lAAIJAAkKnAdnNQBJAQAJAAkKnAdnNQBJAQAAAA==.',
Di='Dillon:BAAANQAECgQIBQAAAA==.Disdain:BAAANQAECgYICQABNQAFFAkJLgANAH4aAA==.',
Do='Donchap:BAAANQAECggIDgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQAECgIIAgABNQADCgQJBAALAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Dreadstar:BAAANQAECgUIBQAAAA==.Drendak:BAAANQAECgMIAwAAAA==.Drucyllå:BAAANQADCgcIDgAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn84AAMDAAoKTB3OLACBAgADAAgKrB7OLACBAgAFAAgK+xjJQADEAQAAAA==.Drzip:BAABNQAECn8kAAICAAoKxg7WeAC8AQACAAoKxg7WeAC8AQAAAA==.Drzippy:BAAANQAECgcIDQAAAA==.',
Du='Duane:BAABNQAECn8VAAIBAAkKshLImQDUAQABAAkKshLImQDUAQAAAA==.Duskthrasher:BAABNQAECn8kAAIDAAkKsgZDPgAZAQADAAkKsgZDPgAZAQAAAA==.Duyii:BAAANQAECgMIAwABNQAECggIPQALAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8vAAIBAAoKSRZwPwCsAgABAAoKSRZwPwCsAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgYIDwAAAA==.',
['Dè']='Dèathknìght:BAAANQAECgEIAQAAAA==.',
Ea='Easterneon:BAAANQAECgUICgABNQAECgcIGQACAJMNAA==.',
Ec='Ech:BAABNQAECn88AAIPAAoK2RoQQQA/AgAPAAoK2RoQQQA/AgAAAA==.',
Ei='Eiraveta:BAABNQAECn8jAAITAAkKSA1vgACXAQATAAkKSA1vgACXAQAAAA==.',
El='Eldrinn:BAAANQABCggIFQAAAA==.Elemental:BAABNQAECn82AAICAAoK9gQBpQBaAQACAAoK9gQBpQBaAQAAAA==.Elendirs:BAAANQABCgYIGwAAAA==.Elisabeta:BAAANQAECgcIEAAAAA==.Ellois:BAAANQAECgYIDgAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAABNQAECn8gAAIZAAgKLAlWegAeAQAZAAgKLAlWegAeAQABNQAECgoKHAABAIkTAA==.',
Ep='Epicnoname:BAACNQAFFH8KAAIFAAQKnhGSDwDkAAAFAAQKnhGSDwDkAAA1AAQKfyQAAgUACgrOHIUgAIkCAAUACgrOHIUgAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAABNQAECn8bAAMMAAgKZQwjDgBUAQAMAAgKZQwjDgBUAQANAAUK0QIxHgGJAAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECggIDAAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIEAAcKoBlCSgDOAQAEAAcKoBlCSgDOAQABNQAECgoKFQAeACgcAA==.Fave:BAAANQADCgYIBgABNQAECgoKOQAQALQcAA==.',
Fe='Feannesse:BAAANQAECggIEgAAAA==.Festival:BAABNQAECn8VAAIeAAoKKBzrBwBuAgAeAAoKKBzrBwBuAgAAAA==.',
Fi='Firebolt:BAABNQAECn85AAMQAAoKtByEJwCOAgAQAAoKtByEJwCOAgAZAAUK1RAG9gCoAAAAAA==.Fitts:BAAANQAECgcIDAABNQAFFAYICQAJADUOAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHgAfAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAABNQAECn8fAAMSAAkKqBKYigAYAQASAAYKuAuYigAYAQAHAAYKSQYwGgHzAAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAABNQAECn8VAAIBAAgKChxkWwBjAgABAAgKChxkWwBjAgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgYIDgALAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Gaia:BAAANQAECgEIAQAAAA==.Garekk:BAABNQAECn8cAAIBAAoKiRMiggAIAgABAAoKiRMiggAIAgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9kAAMFAAoKWCLLBQCEAwAFAAoKWCLLBQCEAwADAAgKmx1pJgCtAQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCggIDwAAAA==.Goneville:BAABNQAECn8UAAIHAAoKghpIcgBKAgAHAAoKghpIcgBKAgAAAA==.Gornix:BAAANQADCgEIAQAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAABNQAECn80AAMQAAoKkwQXdwBNAQAQAAoKkwQXdwBNAQAZAAEKZwFQEgEeAAAAAA==.Gruts:BAAANQAECgMIAwAAAA==.',
Gt='Gtx:BAABNQAECn8VAAIHAAYKjh0h1gBvAQAHAAYKjh0h1gBvAQAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggIDgABNQAECgIIAwALAAAAAA==.Gutworthy:BAAANQAECggIDgAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQAECgMIBgAAAA==.Hallzypal:BAAANQAECgcIDAAAAA==.Hammerjane:BAABNQAECn8yAAISAAkKNhSmQwAGAgASAAkKNhSmQwAGAgAAAA==.Hamur:BAABNQAECn8jAAMYAAkKfxj/BgAQAgAYAAgK3hr/BgAQAgATAAIKSQgW4gBZAAAAAA==.Hargrim:BAAANQAECgcIDAAAAA==.Hariyaki:BAABNQAECn8wAAIdAAkKMwqeKABVAQAdAAkKMwqeKABVAQAAAA==.',
He='Heavywinner:BAABNQAECn8+AAMIAAoKVxssGQD+AgAIAAoKVxssGQD+AgAJAAYKww2fUwCrAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8xAAITAAoKJSXdDQBvAwATAAoKJSXdDQBvAwAAAA==.Hellmage:BAAANQADCgYIBwAAAA==.Hellsfury:BAAANQAECgQIBAAAAA==.Hellslayer:BAABNQAECn8bAAMeAAgKaRfdEQAJAgAeAAgKaRfdEQAJAgAPAAIK8AiGOAFjAAAAAA==.Hellwalker:BAAANQADCggILAAAAA==.Hellzy:BAAANQAECgEIAQAAAA==.',
Hi='Hickery:BAAANQAECgMIAwAAAA==.',
Hn='Hnof:BAAANQAECgEIAQABNQAFFAQICQATAMoRAA==.',
Ho='Holyfire:BAAANQADCgcIBwABNQAECgoKOQAQALQcAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAABNQAECn8yAAMPAAkKBQoJjABqAQAPAAkKpwkJjABqAQAeAAEKrgtfRAA0AAAAAA==.',
Hy='Hycini:BAAANQAECgQICAABNQAFFAIIBQADANwHAA==.',
['Hâ']='Hârlot:BAABNQAECn8yAAIKAAkKNQ7pMwB+AQAKAAkKNQ7pMwB+AQAAAA==.',
Id='Idamage:BAAANQAECgEIAQABNQAECgoKKQAPAA8dAA==.',
Ig='Igetmoney:BAAANQABCgEIAQAAAA==.',
In='Ingenii:BAAANQAECgYIBAABNQAECgoKOwAMAAYgAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8VAAINAAcKlBZACgCDAQANAAcKlBZACgCDAQA1AAQKfyYAAg0ACgqhIcsJAB0DAA0ACgqhIcsJAB0DAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgMIAwAAAA==.Jaestra:BAAANQAECgEIAQABNQAECgkJMgATACQXAA==.Jaidah:BAAANQAECgQIBwAAAA==.Jaith:BAAANQAECgEIAQABNQAECgoKHAATAN0SAA==.Jamaicann:BAAANQADCgYIBgABNQAECggIDAALAAAAAA==.Jansôlo:BAABNQAECn8XAAMBAAgKAiJLOQC+AgABAAgKAiJLOQC+AgAcAAMKiBS8XwCnAAAAAA==.Jaratri:BAACNQAFFH8KAAIXAAMKWA7NAQCgAAAXAAMKWA7NAQCgAAA1AAQKf1wAAhcACgq/HjYCALsCABcACgq/HjYCALsCAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8jAAICAAkKigiuEAFxAQACAAkKigiuEAFxAQAAAA==.',
Ka='Kaerovia:BAABNQAECn8hAAISAAkKHRWITwAtAgASAAkKHRWITwAtAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8nAAIZAAoKVBVoOgCMAgAZAAoKVBVoOgCMAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgUICAAAAA==.Karg:BAABNQAECn8YAAIHAAgK9whN1QBxAQAHAAgK9whN1QBxAQAAAA==.Karmai:BAABNQAECn9FAAMUAAoKMiE4AgBBAwAUAAkKYiA4AgBBAwAVAAoKmRiZIgB/AgAAAA==.Karriane:BAAANQAECgMIAwABNQAECgoKTwARAMMYAA==.Kastigor:BAABNQAECn8ZAAQQAAoKcxzIOAA2AgAQAAgKmBrIOAA2AgAZAAkKCQ0WVACLAQAgAAIKsQUwNwA4AAABNQAFFAUIDAAKAEoPAA==.Katerina:BAAANQADCggIDwAAAA==.Kathine:BAABNQAECn8gAAIGAAgKjAhmFABLAQAGAAgKjAhmFABLAQAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgcIDgAAAA==.Kazue:BAAANQAECgYICwABNQAECgoKOAAHALUbAA==.',
Ke='Keaa:BAABNQAECn8jAAMQAAoKwwwWZgCEAQAQAAoKwwwWZgCEAQAZAAcKUg6EYwBcAQAAAA==.Kelvala:BAABNQAECn82AAMPAAoKwyO5JgAeAwAPAAoKFh+5JgAeAwAaAAcKLSQoCwASAgAAAA==.Kelwynd:BAABNQAECn8gAAIcAAgK8xrPEgAVAgAcAAgK8xrPEgAVAgAAAA==.Kesle:BAAANQADCgUIBQAAAA==.Keä:BAABNQAECn8zAAMHAAoKDhLabAD2AQAHAAoKDhLabAD2AQASAAoKDQ45cADHAQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn9PAAIRAAoKwxgIEgAMAgARAAoKwxgIEgAMAgAAAA==.Kizzs:BAABNQAECn8nAAMFAAoK2xs4GACJAgAFAAoK2xs4GACJAgADAAMKQh7jWwCZAAAAAA==.',
Ko='Kobesama:BAABNQAECn8rAAIPAAoKmA7ZbwCzAQAPAAoKmA7ZbwCzAQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8dAAMhAAgKCxHsCwCcAQAhAAgKCxHsCwCcAQAbAAIKWgb+NgBXAAAAAA==.Korbenzoo:BAAANQAECgUIBQABNQAECggIPQALAAAAAQ==.Korigan:BAAANQAECgcIDwAAAA==.',
Kr='Krom:BAAANQAECgEIAgABNQAECgoKKgAQAKoGAA==.Kryssie:BAABNQAECn86AAIBAAoK2xPVcAAwAgABAAoK2xPVcAAwAgAAAA==.',
Ku='Kudrah:BAAANQAECgEIAQABNQAECgkJHwAIAJ4UAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIiAAcKIwgkKgAfAQAiAAcKIwgkKgAfAQAAAA==.',
['Ká']='Kárg:BAAANQAECggIEAABNQAECggIGAAHAPcIAA==.',
La='Lahee:BAAANQAECgQICAAAAA==.Lampard:BAAANQAECgcICwABNQAECgoKJgAEADAhAA==.Lanaya:BAABNQAECn8vAAIHAAoKZxHPcwDnAQAHAAoKZxHPcwDnAQAAAA==.Laserheadten:BAACNQAFFH8GAAIWAAMKcA/4DQC1AAAWAAMKcA/4DQC1AAA1AAQKfykAAhYACgpIHLQUAL0CABYACgpIHLQUAL0CAAAA.Laudna:BAAANQAECgcIBwABNQAECggIEAALAAAAAA==.Laulon:BAAANQAECgQIAwABNQAECggIPQALAAAAAQ==.Lawrensce:BAAANQAECgQIDAAAAA==.',
Le='Leanore:BAAANQADCgUIBQABNQAECgoKQAAIADgKAA==.Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAABNQAECn8fAAIFAAkKvA3kQgCOAQAFAAkKvA3kQgCOAQAAAA==.Lenian:BAABNQAECn8xAAIeAAkKxRlwCwAPAgAeAAkKxRlwCwAPAgAAAA==.Leâfs:BAABNQAECn8UAAMDAAYKiRMUbwBYAQADAAYKiRMUbwBYAQAFAAUKrQcpfwCuAAAAAA==.',
Li='Lichekinky:BAAANQAECgYIDgAAAA==.Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAABNQAECn8gAAMRAAgKhRISIwBWAQARAAcKchQSIwBWAQAHAAgKcAVT+QD0AAAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAALAAAAAA==.Lostangell:BAAANQABCgMIAwAAAA==.Lourom:BAABNQAECn8mAAMBAAoKGBHmXwAIAgABAAoKEhHmXwAIAgAcAAYKxgx0SwAIAQAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAABNQAECn8eAAIPAAkKowz1ggCAAQAPAAkKowz1ggCAAQAAAA==.',
Ly='Lyraae:BAABNQAECn8iAAIQAAkKtREufgCRAQAQAAkKtREufgCRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Madtankage:BAAANQADCgMIAwAAAA==.Maegh:BAAANQADCgIIAgAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn9mAAMBAAoKTB2yKgCWAgABAAoKTB2yKgCWAgAcAAMK6wl4UwBbAAAAAA==.Maiganoss:BAABNQAECn8cAAMEAAgK/RaOIwDeAQAEAAgK/RaOIwDeAQADAAEKpQJ1AAEXAAAAAA==.Mardon:BAAANQABCgYICwABNQABCgYIGwALAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAABNQAECn8aAAICAAoKdwqExgD3AQACAAoKdwqExgD3AQAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBQAAAA==.',
Me='Megid:BAABNQAECn8jAAIRAAkKdR7YFQBQAgARAAkKdR7YFQBQAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8xAAIFAAoKTRspIwA4AgAFAAoKTRspIwA4AgAAAA==.Methalos:BAAANQABCgIIAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAABNQAECn8XAAIgAAgKjwVnIwD/AAAgAAgKjwVnIwD/AAABNQAECgoKQAAIADgKAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgcIEAAAAA==.Mimie:BAAANQAECgcICQAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAABNQAECn8nAAICAAoKRA2maADjAQACAAoKRA2maADjAQAAAA==.Misao:BAAANQAECgIIAgABNQAECgoKOwARAK4eAA==.Mizblumkin:BAABNQAECn8bAAIGAAoKERINEgCFAQAGAAoKERINEgCFAQAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moodoom:BAAANQAECgUICQAAAA==.Moomoom:BAABNQAECn8ZAAMaAAYKqgSWIgCWAAAaAAYKqgSWIgCWAAAPAAEK6AIMPQEaAAAAAA==.Moonbeard:BAAANQADCgMIAwAAAA==.Moonfizzle:BAAANQAECgQIBAAAAA==.Moonnshine:BAABNQAECn8hAAMIAAkKEwV0YwBAAQAIAAkKEwV0YwBAAQAJAAYKXwIjVgCvAAAAAA==.Moonrend:BAAANQAECgYIDAAAAA==.Moonzire:BAAANQAECgYIBwAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECggIPQALAAAAAQ==.',
Mu='Muradil:BAAANQADCgMIBAAAAA==.Murgrot:BAAANQADCgcIEQAAAA==.',
My='Mylittlepwni:BAAANQAECgQICQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcIBwAAAA==.',
['Mû']='Mûffin:BAAANQAECgcICAAAAA==.',
Na='Nainel:BAAANQAECgEIAQABNQAECgkJMQAeAMUZAA==.Nakros:BAAANQAECgYICAAAAA==.Narrondiian:BAAANQADCgYIBgABNQAECggIPQALAAAAAQ==.Nathelezet:BAAANQADCgQJBAABNQAECgkJMgACAHUgAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECggIEQAAAA==.Nerik:BAAANQAECgQICAAAAA==.Nerissa:BAEBNQAECn8WAAISAAoK9wbB2gBhAAASAAoK9wbB2gBhAAAAAA==.Netallia:BAAANQAECgQIAwAAAA==.',
Ng='Ngyue:BAAANQADCgYIJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAIBAAcKbxq9agA+AgABAAcKbxq9agA+AgAAAA==.Nickto:BAABNQAECn8YAAIHAAYKuQJJXwFrAAAHAAYKuQJJXwFrAAAAAA==.Niishaa:BAAANQAECgYIBQABNQAECgkJJAADALIGAA==.',
Nu='Nubin:BAAANQAECgMIAgAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgkJHgAPAKMMAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Oa='Oaknsheild:BAAANQADCgUIBQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIFQABAMEHAA==.',
On='Onsight:BAAANQAECgEIAQAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECggIHQAdADIUAA==.Ophnakyel:BAAANQADCgEIAQAAAA==.',
Or='Orceo:BAAANQAECgEIAQABNQAECgoKSQABADYkAA==.Orcrest:BAAANQAECgUIDQAAAA==.Ororo:BAABNQAECn8qAAIZAAkK1BlyRABkAgAZAAkK1BlyRABkAgAAAA==.',
Pa='Painmender:BAAANQAECgcICwAAAA==.Palal:BAAANQAECgEIAQABNQAECgcIFAAHAOEiAA==.Paog:BAAANQADCggIEAAAAA==.Paryah:BAABNQAECn8yAAIVAAkK2gjFbQBhAQAVAAkK2gjFbQBhAQAAAA==.Pauken:BAAANQAECgcICgABNQAECgoKOwAMAAYgAA==.',
Ph='Phanceester:BAAANQAECgUICQAAAA==.Phindra:BAAANQAECgQIBgAAAA==.Phonut:BAAANQADCgcIDQAAAA==.Phréek:BAABNQAECn9HAAMSAAoK3BxmGgDlAgASAAoK3BxmGgDlAgAHAAkKnxXsfQDRAQAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAACNQAFFH8UAAIEAAYKYAwDEgA3AQAEAAYKYAwDEgA3AQA1AAQKf2sAAgQACgqLIFwJAPgCAAQACgqLIFwJAPgCAAAA.',
Po='Poetea:BAAANQAECggICwAAAA==.Portalslag:BAAANQAECggICwAAAA==.',
Pr='Praze:BAAANQAECgUIDQAAAA==.',
Pu='Punyboy:BAAANQAECgQIBQAAAA==.Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.Rahis:BAABNQAECn9EAAMBAAoKKRevPgBZAgABAAoKKRevPgBZAgAcAAEKeAOJkQAuAAAAAA==.Raiu:BAABNQAECn8yAAIQAAkKbxeFNwA8AgAQAAkKbxeFNwA8AgAAAA==.Ramsis:BAABNQAECn8hAAIQAAoKtxx2RgBHAgAQAAoKtxx2RgBHAgAAAA==.Randir:BAABNQAECn9NAAIWAAoK4BnoDwBaAgAWAAoK4BnoDwBaAgAAAA==.Ranir:BAAANQAECgMIBwAAAA==.Rath:BAABNQAECn8gAAIdAAkKwRpIJQD5AQAdAAkKwRpIJQD5AQAAAA==.Rathmon:BAAANQAECgEIAQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAABNQAECn8ZAAMSAAgKtxUMYQCXAQASAAYKLxYMYQCXAQAHAAUKUgsVPgGRAAAAAA==.Remedivhs:BAAANQAECgUIBQABNQAECggIPQALAAAAAQ==.Rettbull:BAAANQAECgEIAQAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAABNQAECn8ZAAICAAYKwAfCNwEwAQACAAYKwAfCNwEwAQABNQAECggIIwAEALISAA==.Rhyli:BAAANQAECgEIAQAAAA==.',
Ri='Ricki:BAAANQADCgYIBgAAAA==.',
Rn='Rngeezuss:BAAANQAECggICAAAAA==.',
Ro='Robinhoodx:BAABNQAECn9HAAIBAAoK9Bt5QQCmAgABAAoK9Bt5QQCmAgAAAA==.Rockbottom:BAAANQAECgEIAQABNQAECgkJMgAEAKUWAA==.Roenabur:BAAANQAECgEIAQAAAA==.Romok:BAAANQAECgYIDwAAAA==.Rosaline:BAAANQAECgQIDAAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rà']='Ràyne:BAAANQADCggIGwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8qAAIHAAgKFg2v1QBwAQAHAAgKFg2v1QBwAQAAAA==.Saintandrew:BAAANQAECgQIBAAAAA==.Samoot:BAABNQAECn9AAAMIAAoKOAoxMQB/AQAIAAoKOAoxMQB/AQAjAAUK/wGGZQBHAAAAAA==.Sanguina:BAAANQADCgYIBgAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQAECgEIAQABNQAECggIPQALAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.Sephirother:BAAANQAECggIBwAAAA==.',
Sh='Shael:BAABNQAECn8yAAINAAkK2wzpbQCPAQANAAkK2wzpbQCPAQAAAA==.Shamanstein:BAAANQADCggIDwABNQAFFAUIDQAHAI4gAA==.Shammbo:BAAANQAECggIEwAAAA==.Sharty:BAAANQAECggIEgAAAA==.Shazra:BAABNQAECn8ZAAIJAAoKEgjwMQBhAQAJAAoKEgjwMQBhAQAAAA==.Sheriruth:BAAANQAECggIEAABNQAECgoKOwAMAAYgAA==.Shifthappenz:BAAANQAECgYIBwAAAA==.Shortigen:BAAANQAECgUICwAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.Shuub:BAABNQAECn8gAAIeAAoKFyaDAACFAwAeAAoKFyaDAACFAwAAAA==.',
Si='Sicnus:BAAANQADCggIEAAAAA==.Silveryl:BAABNQAECn8dAAMdAAgKMhTGHQC0AQAdAAgKMhTGHQC0AQAiAAQKgQwWLACjAAAAAA==.Sinadin:BAABNQAECn9MAAIHAAoK1ha1UQA3AgAHAAoK1ha1UQA3AgAAAA==.Sindoreisins:BAABNQAECn8eAAITAAoKkxAZZgCtAQATAAoKkxAZZgCtAQAAAA==.Sindrinker:BAAANQAECgQIBAAAAA==.Sizzlinghots:BAABNQAECn8/AAIJAAoKshLFGABOAgAJAAoKshLFGABOAgAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIIgATAO4LAA==.Skolmaster:BAABNQAECn8mAAICAAoKSxPQVAAUAgACAAoKSxPQVAAUAgAAAA==.Skootter:BAAANQADCgYIBwAAAA==.Skyfury:BAABNQAECn8pAAMQAAkKbhTeWgCqAQAQAAkKbhTeWgCqAQAZAAcKKhQIlgBtAQABNQAECgoKOQAQALQcAA==.Skywalkr:BAAANQADCgYICwAAAA==.',
Sm='Smarky:BAACNQAFFH8IAAIWAAUKNw3LDADLAAAWAAUKNw3LDADLAAA1AAQKfxkAAhYACgouHiwOAAsDABYACgouHiwOAAsDAAAA.Smâlls:BAEBNQAECn8qAAIkAAkKcxglCADZAQAkAAkKcxglCADZAQAAAA==.',
Sn='Sneekiemage:BAAANQAECgUIDQAAAA==.Snugz:BAAANQAECgEIAgAAAA==.',
So='Sourdiesel:BAABNQAECn8qAAIBAAoKiQ2QXAAPAgABAAoKiQ2QXAAPAgAAAA==.Southsound:BAABNQAECn8ZAAICAAcKkw3JAQGLAQACAAcKkw3JAQGLAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQALAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQAECgUIDQAAAA==.Steakknife:BAABNQAECn8VAAMfAAgKZhHkMQAXAgAfAAgKZhHkMQAXAgAVAAYK2AViMgApAQAAAA==.Stikybandage:BAAANQADCgcIBwAAAA==.Stormoon:BAABNQAECn8rAAMZAAoKCQyFUACWAQAZAAoKCQyFUACWAQAQAAcKxQv+qwAZAQAAAA==.Streigar:BAAANQAECgMIAwAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgQIAwAAAA==.',
Sy='Sybil:BAABNQAECn8fAAIIAAkKnhQKKgCvAQAIAAkKnhQKKgCvAQAAAA==.',
Sz='Szer:BAAANQAECgUIBQAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAABNQAECn8tAAIBAAgK/QQdwwArAQABAAgK/QQdwwArAQAAAA==.Tahtiania:BAABNQAECn8lAAICAAkK6gWVsQBBAQACAAkK6gWVsQBBAQAAAA==.Talkurandis:BAAANQAECgcIGQABNQAECggIPQALAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn80AAIDAAoKNCL6BQAYAwADAAoKNCL6BQAYAwAAAA==.Tenma:BAAANQAECgUIBQABNQAECgoKOwARAK4eAA==.Teo:BAABNQAECn8jAAIBAAkKkRAYlwDaAQABAAkKkRAYlwDaAQAAAA==.Terraria:BAAANQAECgEIAgABNQAECgoKRQAUADIhAA==.Teyamat:BAABNQAECn8WAAIbAAoKvBBGDQB5AQAbAAoKvBBGDQB5AQABNQAECgoKNAADADQiAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8mAAMQAAoK7BzXHQD1AgAQAAoK7BzXHQD1AgAZAAMKqhGc9ACsAAAAAA==.Theory:BAAANQAECgUIBQAAAA==.Thetree:BAABNQAECn8nAAMJAAkKrRviFAChAgAJAAkKrRviFAChAgAIAAcK+xsvPgAHAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIIgATAO4LAA==.Thoughtcrime:BAAANQAECgcICgAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8yAAIYAAoKKxtjAgCoAgAYAAoKKxtjAgCoAgAAAA==.',
Ti='Timoris:BAAANQAECgUIBwABNQAECgoKOwAMAAYgAA==.',
To='Tobiume:BAAANQAECgYICgABNQAECgoKQQANAFUZAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAABNQAECn8VAAIBAAYKwQdy0QBeAQABAAYKwQdy0QBeAQAAAA==.Toodles:BAAANQADCggIJgAAAA==.Totempoe:BAAANQAECgEIAQABNQAECggICwALAAAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgQICAAAAA==.Trildjr:BAABNQAECn8bAAIBAAgKNBCAkACVAQABAAgKNBCAkACVAQAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn81AAIZAAkKbwqccAA3AQAZAAkKbwqccAA3AQAAAA==.',
Ty='Tyronda:BAAANQADCggIJAAAAA==.Tyrse:BAABNQAECn8hAAIXAAcKkAeOCwABAQAXAAcKkAeOCwABAQAAAA==.',
Tz='Tzerina:BAABNQAECn8fAAIKAAcKfA/tQwAjAQAKAAcKfA/tQwAjAQAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECggIPQAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMIAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8nAAISAAoKcRCGbQDPAQASAAoKcRCGbQDPAQAAAA==.Validan:BAAANQAECgYICwAAAA==.Valkriss:BAAANQAECgEIAQAAAA==.Vallyrie:BAABNQAECn8uAAMEAAoKxRoSJwDFAQAEAAkKfxoSJwDFAQADAAcKMRWVYwCCAQAAAA==.Valssharess:BAABNQAECn8tAAIjAAkKwR2BDwA+AgAjAAkKwR2BDwA+AgAAAA==.Valth:BAAANQAECgQIBwAAAA==.Valweyna:BAAANQADCgIIAgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Vaporgriffin:BAABNQAECn8VAAIlAAcKqxiYEgCfAQAlAAcKqxiYEgCfAQAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgYIBwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgUIDQAAAA==.Veleria:BAABNQAECn8vAAMSAAkKehj0SwA5AgASAAkKehj0SwA5AgARAAYK5RgZKACdAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgUIDAAAAA==.',
Vi='Victra:BAABNQAECn8fAAITAAoK2xDiXADMAQATAAoK2xDiXADMAQAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECggIEQAAAA==.Vinaya:BAAANQAECgUIDQAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQALAAAAAA==.',
Vo='Volthemar:BAABNQAECn9CAAQPAAoKNiIWKwCTAgAPAAoK4CAWKwCTAgAeAAQK1hzaJAAfAQAaAAMKAR/nHgC3AAAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Wa='Wanabe:BAAANQADCgUIBQAAAA==.Warrpath:BAAANQADCgEIAQAAAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn85AAIHAAoKmwntrgByAQAHAAoKmwntrgByAQAAAA==.',
Wh='Whatevyr:BAAANQAECgEIAQAAAA==.Whitespot:BAAANQAECgMIAwAAAA==.',
Wi='Wilson:BAAANQADCgYIBwABNQAECgkJMgACAHUgAA==.Wisegurl:BAABNQAECn8rAAMHAAoKoiLOPAB0AgAHAAoKLSLOPAB0AgARAAUKBBavTQBvAAAAAA==.',
Wo='Woblatus:BAAANQAECgIIAgABNQAECggIPQALAAAAAQ==.Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn85AAIIAAoK/BIZIwDkAQAIAAoK/BIZIwDkAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgQICAAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wybpally:BAAANQAECgMIAgAAAA==.Wylecsham:BAAANQAECgUIBgAAAA==.Wylectra:BAABNQAECn9GAAITAAoKQhUmQQA1AgATAAoKQhUmQQA1AgAAAA==.',
Xe='Xethos:BAAANQAECggICAAAAA==.',
Xy='Xyleeha:BAAANQADCggIGwAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn9FAAMBAAoKgA5XZAD9AQABAAoKgA5XZAD9AQAcAAEKAADjogAPAAAAAA==.Yerdedmatey:BAAANQAECgIIAQAAAA==.',
Yo='Yomiko:BAAANQAECggICAABNQAECgoKOwARAK4eAA==.Yoshikatsu:BAAANQADCggICAAAAA==.Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn9KAAIQAAoKVBwgJgCXAgAQAAoKVBwgJgCXAgAAAA==.Zahvaria:BAABNQAECn8dAAIVAAcKTgbBNgADAQAVAAcKTgbBNgADAQAAAA==.Zamari:BAAANQAECgEIAQABNQAECgcIHQAVAE4GAA==.Zaphiell:BAABNQAECn8eAAIWAAkK2hWqIgAeAgAWAAkK2hWqIgAeAgAAAA==.Zazzy:BAEANQAECgYICgABNQAFFAUIFwABAEEPAA==.',
Ze='Zeid:BAABNQAECn8bAAIPAAoK2g2jhAAQAgAPAAoK2g2jhAAQAgAAAA==.Zev:BAAANQAECggIEQAAAA==.',
Zi='Zilli:BAAANQAECggIBwAAAA==.Zillz:BAABNQAECn8jAAISAAoKEQ/OQwAFAgASAAoKEQ/OQwAFAgAAAA==.Zinderalanot:BAAANQAECgcIFAABNQAECggIPQALAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgMIAwAAAA==.',
Zo='Zoeystorm:BAABNQAECn83AAMHAAkKCAkW3AAjAQAHAAgK2QgW3AAjAQARAAcKIAVVQACoAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAIDAAkKEBSYQwAMAgADAAkKEBSYQwAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAACNQAFFH8IAAQBAAUKyAgrJwB/AAABAAIKKwkrJwB/AAAcAAQK1gVCGwB0AAAXAAEKrAmgAgBDAAA1AAQKfzsABAEACgpEG69fAFgCAAEACgpEG69fAFgCABwABwo4DMckAEMBABcAAgpjCKQRAFMAAAAA.',
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
