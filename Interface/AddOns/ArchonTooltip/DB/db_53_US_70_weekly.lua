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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Unknown-Unknown','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Priest-Holy','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Priest-Discipline','Warrior-Fury','Evoker-Devastation','Shaman-Elemental','Hunter-Marksmanship','Warrior-Protection','Monk-Windwalker','Rogue-Assassination','Evoker-Augmentation','Monk-Mistweaver','Shaman-Enhancement','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acehigh:BAAANQABCgYICgABNQAFFAcIIQABAHkdAA==.Acemage:BAABNQAECn8lAAICAAoKDhFifwB8AQACAAoKDhFifwB8AQABNQAFFAcIIQABAHkdAA==.',
Ae='Aegon:BAABNQAECn9AAAQDAAoKUCMTHwDRAgADAAoKUCMTHwDRAgAEAAoK9wnEbgA6AQAFAAMKyg+pkwBGAAAAAA==.Aeja:BAAANQAECgEIAQAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn83AAMGAAkK3B9VCADvAQAGAAYKWx9VCADvAQACAAcKZB5tegCHAQAAAA==.',
Ah='Ahdonis:BAAANQAECggIEwAAAA==.Ahnerfays:BAAANQAECgYIDAABNQAECgoKPAAHAHEgAA==.',
Ai='Aiara:BAAANQAECgIIAQAAAA==.Aiarra:BAABNQAECn85AAMIAAoKixQSQQD0AQAIAAoKixQSQQD0AQAJAAcKEw+lLQA5AQAAAA==.Aindriana:BAABNQAECn8vAAIKAAgKiQo/MABXAQAKAAgKiQo/MABXAQAAAA==.Aitra:BAABNQAECn8gAAQLAAcKgQKoFgCRAAALAAcKgQKoFgCRAAAMAAUK6AFGIwF7AAANAAEKUQKfiQAVAAAAAA==.',
Aj='Ajx:BAAANQAECgYICgABNQAECgcIGgAOAH4MAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECn8aAAIBAAcKUBPOkwDhAQABAAcKUBPOkwDhAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgoKNQALAM4eAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alaeryth:BAAANQAECgYIEAABNQAECggIAgAPAAAAAA==.Alerothon:BAABNQAECn9SAAIHAAoKWxcZWADvAQAHAAoKWxcZWADvAQAAAA==.Alestiana:BAABNQAECn9KAAIQAAoKmheNJgBjAgAQAAoKmheNJgBjAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgcICAAAAA==.',
Am='Amephyst:BAABNQAECn84AAIRAAoKnhRjGwATAgARAAoKnhRjGwATAgAAAA==.Amnadores:BAABNQAECn8bAAICAAYK9geCLgE/AQACAAYK9geCLgE/AQABNQAECggIHgARAAgQAA==.',
An='Andii:BAAANQAECgcICgAAAA==.Annati:BAACNQAFFH8LAAIQAAcKDhnoCwCOAQAQAAcKDhnoCwCOAQA1AAQKfysAAhAACgqTIXoVACMDABAACgqTIXoVACMDAAAA.Antarres:BAABNQAECn8sAAIMAAoKiQnNrQB2AQAMAAoKiQnNrQB2AQAAAA==.',
Ao='Aoba:BAABNQAECn83AAMRAAoKrh68FABdAgARAAgKMhy8FABdAgASAAgK7gcdZQBVAQAAAA==.',
Ap='Apila:BAAANQAECgEIAQABNQAECggIMAAPAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAABNQAECn8jAAITAAoKcBcCHQDCAgATAAoKcBcCHQDCAgAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAQICgAFAJ4RAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECgoKPAAHAHEgAA==.Areaman:BAAANQAECgEIAQABNQAECggIIwACAAEiAA==.Aridam:BAAANQAECgQIBAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisdrake:BAAANQAECgIIAgABNQADCgIIAgAPAAAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgAPAAAAAA==.Artemisshade:BAABNQAECn8uAAMUAAkKYxu+AQAwAgAUAAkKYxu+AQAwAgAVAAQKjBIcNQARAQABNQADCgIIAgAPAAAAAA==.Arthillius:BAAANQAECgUICQAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Au='Aurica:BAAANQAECgcIDAAAAA==.Aurélìa:BAAANQAECgIIAgAAAA==.',
Av='Aviana:BAABNQAECn8aAAIWAAYKZAmlSQD0AAAWAAYKZAmlSQD0AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgUICAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8vAAMBAAkKvBKvlgDbAQABAAkK5BGvlgDbAQAXAAcK7AkNCQCyAQAAAA==.Bellaliel:BAAANQAECgQIBAAAAA==.Belle:BAABNQAECn8VAAIHAAgK0wZgwQASAQAHAAgK0wZgwQASAQAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECn8ZAAMMAAkKpQ68igDMAQAMAAgKkg28igDMAQANAAIKnhFbWAB2AAAAAA==.Biscuitbob:BAAANQADCggICAABNQAECgYIFQABAMEHAA==.',
Bj='Bjornmodi:BAAANQAECgUIDQAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzlock:BAAANQAECgIIAgABNQAECgoKIQAIAIgZAA==.Blitzy:BAABNQAECn8hAAIIAAoKiBlNIADKAgAIAAoKiBlNIADKAgAAAA==.',
Bo='Bobbette:BAABNQAECn8YAAQTAAcK1Q8ikQBjAQATAAcK1Q8ikQBjAQAWAAMKlwb7YAB9AAAYAAEKnwPMMAAjAAABNQAECgoKIAAQAA4bAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Braegen:BAAANQAECgEIAQAAAA==.Breakwinds:BAAANQAECgcIBwAAAA==.Brenick:BAABNQAECn8YAAIZAAcKhAvsFADmAAAZAAcKhAvsFADmAAAAAA==.Brewtalize:BAAANQAECgEIAQAAAA==.Bringer:BAAANQAECgMIBAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQAECgMIAwAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQIBwAAAA==.Burnie:BAABNQAECn8hAAIaAAgKPBVSCgCQAQAaAAgKPBVSCgCQAQAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAABNQAECn8dAAIbAAgK4hgHMADiAQAbAAgK4hgHMADiAQAAAA==.Camilah:BAABNQAECn8rAAIDAAoKkx07DgBxAgADAAoKkx07DgBxAgAAAA==.Capa:BAABNQAECn81AAQLAAoKzh5xBACUAgALAAgKPh9xBACUAgAMAAUKUBvrzgAsAQANAAMKSBeiOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECn8cAAICAAoKkhtMawCtAQACAAoKkhtMawCtAQAAAA==.',
Ce='Celestiné:BAAANQAECgUICAAAAA==.Cemeteri:BAAANQADCggIDwAAAA==.',
Ch='Chaingun:BAABNQAECn8eAAICAAoK0Qm6bQCmAQACAAoK0Qm6bQCmAQAAAA==.Chaps:BAAANQAECgMIAwAAAA==.Chelseac:BAAANQAECgUIEwABNQAECgcIGQACAJMNAA==.Chilblain:BAABNQAECn8/AAIGAAoKeBFHDAD3AQAGAAoKeBFHDAD3AQAAAA==.Chilchizedek:BAAANQAECgEIAQAAAA==.Chobii:BAABNQAECn9PAAIcAAoKdhudCgBvAgAcAAoKdhudCgBvAgAAAA==.',
Ci='Cibochevski:BAAANQADCggIDwABNQAECggIIgAdAIsZAA==.Ciratorynth:BAABNQAECn8oAAIaAAoKHRO/EwATAgAaAAoKHRO/EwATAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8nAAIQAAoKESNZDwBIAwAQAAoKESNZDwBIAwAAAA==.',
Cl='Claferi:BAAANQADCgMIAwAAAA==.Clearlove:BAAANQAECgYIBAABNQAECgcIGQACAJMNAA==.Clearlovec:BAAANQAECgcICAABNQAECgcIGQACAJMNAA==.Closetfurry:BAABNQAECn8pAAIHAAcKpw+lvgAXAQAHAAcKpw+lvgAXAQAAAA==.',
Co='Codenheimer:BAAANQAECgUIEAAAAA==.Condor:BAAANQAECggICwAAAA==.Corrinne:BAABNQAECn8sAAIHAAoKTxklaABjAgAHAAoKTxklaABjAgAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Crankk:BAAANQAECgEIAQAAAA==.Critmypänts:BAAANQAECgUIEAAAAA==.',
Cz='Czernobog:BAABNQAECn8eAAIRAAkK3hs0DQAkAgARAAkK3hs0DQAkAgAAAA==.',
Da='Daeshan:BAABNQAECn88AAIeAAoKrBfAEAAgAgAeAAoKrBfAEAAgAgAAAA==.Dafirstone:BAAANQAECggIEwAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECn81AAISAAoKWh9WGQATAwASAAoKWh9WGQATAwAAAA==.Daradevil:BAAANQADCgcIBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcIBwAPAAAAAA==.Daralune:BAAANQAECgQIBwAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn87AAMHAAoKLhkQTQAPAgAHAAoKLhkQTQAPAgARAAEKxwQWgQAbAAAAAA==.Dasecondone:BAAANQAECgUIEQAAAA==.Dathirdone:BAAANQADCggIIQAAAA==.Dawg:BAAANQAECgQIEQAAAA==.Days:BAAANQAECggICQABNQAECgoKFQAdACgcAA==.',
De='Deadlytankz:BAAANQADCgQIBAAAAA==.Deadval:BAAANQADCgcIEQAAAA==.Demonicfyre:BAECNQAFFH8RAAICAAUKDBkvHADuAAACAAUKDBkvHADuAAA1AAQKfyYAAgIACgqaHZdVANUCAAIACgqaHZdVANUCAAAA.Demonstein:BAAANQAECgUIBQABNQAFFAUIDQAHAI4gAA==.Destros:BAABNQAECn8dAAIJAAcK6AeQNwD6AAAJAAcK6AeQNwD6AAAAAA==.',
Di='Dillon:BAAANQAECgIIAgAAAA==.Disdain:BAAANQAECgYICQABNQAFFAgIJAAMAEwZAA==.',
Do='Donchap:BAAANQAECggIDgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQAECgIIAgABNQADCgQJBAAPAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drendak:BAAANQAECgIIBwAAAA==.Drucyllå:BAAANQADCgcICwAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn84AAMDAAoKTB3OLACBAgADAAgKrB7OLACBAgAFAAgK+xjJQADEAQAAAA==.Drzip:BAABNQAECn8fAAICAAgKJg+z0gDhAQACAAgKJg+z0gDhAQAAAA==.Drzippy:BAAANQAECgMIBQAAAA==.',
Du='Duane:BAABNQAECn8VAAIBAAkKshLImQDUAQABAAkKshLImQDUAQAAAA==.Duskthrasher:BAABNQAECn8cAAIDAAcKlQRQTACvAAADAAcKlQRQTACvAAAAAA==.Duyii:BAAANQAECgEIAQABNQAECggIMAAPAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8rAAIBAAoKBhVwPwCsAgABAAoKBhVwPwCsAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgUIDwAAAA==.',
Ea='Easterneon:BAAANQAECgUICgABNQAECgcIGQACAJMNAA==.',
Ec='Ech:BAABNQAECn88AAIOAAoK2RrZMQBQAgAOAAoK2RrZMQBQAgAAAA==.',
Ei='Eiraveta:BAABNQAECn8jAAITAAkKSA1vgACXAQATAAkKSA1vgACXAQAAAA==.',
El='Eldrinn:BAAANQAECgEIAQAAAA==.Elemental:BAABNQAECn8mAAICAAgKiwMc1ADXAAACAAgKiwMc1ADXAAAAAA==.Elendirs:BAAANQABCgYIGwABNQABCgcIDgAPAAAAAA==.Elisabeta:BAAANQAECgQIBgAAAA==.Ellois:BAAANQAECgYIDgAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAAANQAECggIEgABNQAECgoKFwABAJ4PAA==.',
Ep='Epicnoname:BAACNQAFFH8KAAIFAAQKnhEUDgDAAAAFAAQKnhEUDgDAAAA1AAQKfyQAAgUACgrOHIUgAIkCAAUACgrOHIUgAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAABNQAECn8UAAMLAAYKnA7YEABAAQALAAYKnA7YEABAAQAMAAUK0QIxHgGJAAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECggIDQAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIEAAcKoBlCSgDOAQAEAAcKoBlCSgDOAQABNQAECgoKFQAdACgcAA==.Fave:BAAANQADCgYIBgABNQAECgkJKwAQACceAA==.',
Fe='Feannesse:BAAANQAECgcIEgAAAA==.Festival:BAABNQAECn8VAAIdAAoKKByxBQB/AgAdAAoKKByxBQB/AgAAAA==.',
Fi='Firebolt:BAABNQAECn8rAAMQAAkKJx7wJABtAgAQAAkKJx7wJABtAgAbAAMKvRAG9gCoAAAAAA==.Fitts:BAAANQAECgcIDAABNQAFFAUIBwAJAJcNAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHgAfAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAABNQAECn8aAAMHAAgKDAcwGgHzAAAHAAYKSQYwGgHzAAASAAUKEwaXmQDEAAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAABNQAECn8VAAIBAAgKChxkWwBjAgABAAgKChxkWwBjAgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgYIDgAPAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Garekk:BAABNQAECn8XAAIBAAoKng8iggAIAgABAAoKng8iggAIAgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9YAAMFAAoKWCLLBQCEAwAFAAoKWCLLBQCEAwADAAgKmx26HgC5AQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCggIDwAAAA==.Goneville:BAAANQAECggIEgAAAA==.Gornix:BAAANQADCgEIAQAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAABNQAECn8iAAMQAAoKYgOZewAOAQAQAAoKYgOZewAOAQAbAAEKZwHi8wAeAAAAAA==.Gruts:BAAANQAECgMIBAAAAA==.',
Gt='Gtx:BAABNQAECn8VAAIHAAYKjh0h1gBvAQAHAAYKjh0h1gBvAQAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggIDgABNQAECgIIAwAPAAAAAA==.Gutworthy:BAAANQAECgYICAAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQAECgQICAAAAA==.Hallzypal:BAAANQAECgcIDgAAAA==.Hammerjane:BAABNQAECn8jAAISAAgKVBVVPwDlAQASAAgKVBVVPwDlAQAAAA==.Hamur:BAABNQAECn8fAAMYAAgK3hqeAwD3AQAYAAgK3hqeAwD3AQATAAEKCQtw5gAqAAAAAA==.Hargrim:BAAANQAECgUIBQAAAA==.Hariyaki:BAABNQAECn8hAAIeAAgKQAnkKQASAQAeAAgKQAnkKQASAQAAAA==.Havebandaids:BAAANQAECgEIAQAAAA==.',
He='Heavywinner:BAABNQAECn89AAMIAAoKVxssGQD+AgAIAAoKVxssGQD+AgAJAAYKww1uRgCsAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8qAAITAAoKJSXDEQA7AwATAAoKJSXDEQA7AwAAAA==.Hellmage:BAAANQADCgYIBwAAAA==.Hellsfury:BAAANQAECgQIBAAAAA==.Hellslayer:BAABNQAECn8bAAMdAAgKaRfdEQAJAgAdAAgKaRfdEQAJAgAOAAIK8AiGOAFjAAAAAA==.Hellwalker:BAAANQADCggILAAAAA==.Hellzy:BAAANQAECgEIAgAAAA==.',
Hi='Hickery:BAAANQAECgMIBQAAAA==.',
Hn='Hnof:BAAANQAECgEIAQABNQAFFAQICQATAMoRAA==.',
Ho='Holyfire:BAAANQADCgcIBwABNQAECgkJKwAQACceAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAABNQAECn8jAAMOAAgKfglhjgAuAQAOAAgKEQlhjgAuAQAdAAEKrgsROgA0AAAAAA==.',
Hy='Hycini:BAAANQAECgIIAgABNQAECgoKSwADAC0WAA==.',
['Hâ']='Hârlot:BAABNQAECn8jAAIKAAgKqA3IMwBAAQAKAAgKqA3IMwBAAQAAAA==.',
['Hè']='Hèathen:BAAANQADCggIDwAAAA==.',
Id='Idamage:BAAANQAECgEIAQABNQAECggIDgAPAAAAAA==.',
Ig='Igetmoney:BAAANQABCgEIAQAAAA==.',
In='Ingenii:BAAANQAECgYIBgABNQAECgoKNQALAM4eAA==.',
Io='Iorell:BAAANQAECgEIAQABNQAECggIIwACAAEiAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8UAAIMAAYK9hgECgA+AQAMAAYK9hgECgA+AQA1AAQKfx8AAgwACgogIN0MAOoCAAwACgogIN0MAOoCAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgMIAwAAAA==.Jaestra:BAAANQAECgEIAQABNQAECggIIwATAOIWAA==.Jaidah:BAAANQAECgMIAwAAAA==.Jaith:BAAANQAECgEIAQABNQAECgoKFAATAPoPAA==.Jamaicann:BAAANQADCgYIBgABNQAECgcICwAPAAAAAA==.Jansôlo:BAABNQAECn8XAAMBAAgKAiJLOQC+AgABAAgKAiJLOQC+AgAcAAMKiBS8XwCnAAAAAA==.Jaratri:BAACNQAFFH8KAAIXAAMKWA7NAQCgAAAXAAMKWA7NAQCgAAA1AAQKf1IAAhcACgrZHRICAKYCABcACgrZHRICAKYCAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8hAAICAAkKigiuEAFxAQACAAkKigiuEAFxAQAAAA==.',
Ka='Kaatu:BAAANQAECgEIAQAAAA==.Kaerovia:BAABNQAECn8hAAISAAkKHRWITwAtAgASAAkKHRWITwAtAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8nAAIbAAoKVBVoOgCMAgAbAAoKVBVoOgCMAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICAAAAA==.Karg:BAABNQAECn8YAAIHAAgK9whN1QBxAQAHAAgK9whN1QBxAQAAAA==.Karmai:BAABNQAECn9EAAMUAAoKzSA4AgBBAwAUAAkKYiA4AgBBAwAVAAoKMxgxHgBqAgAAAA==.Karriane:BAAANQAECgIIAgABNQAECgoKPQARAN0WAA==.Kastigor:BAAANQAECgcIDQABNQAFFAMICgAKAPcSAA==.Katerina:BAAANQADCggICAAAAA==.Kathine:BAABNQAECn8UAAIGAAUKRgdAIAClAAAGAAUKRgdAIAClAAAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgcIEAAAAA==.Kazue:BAAANQAECgYIDQABNQAECgoKLAAHAE8ZAA==.',
Ke='Keaa:BAABNQAECn8XAAMQAAkK2AngdAAhAQAQAAkK2AngdAAhAQAbAAYKEwhDdQDxAAAAAA==.Kelvala:BAABNQAECn8zAAMOAAoKwyO5JgAeAwAOAAoKFh+5JgAeAwAZAAcKLSQoCwASAgAAAA==.Kelwynd:BAABNQAECn8aAAIcAAYK2htnGACKAQAcAAYK2htnGACKAQAAAA==.Kesle:BAAANQADCgUIBQAAAA==.Keä:BAABNQAECn8kAAMSAAoKFgw5cADHAQASAAoKFgw5cADHAQAHAAcKqguXDQEIAQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn89AAIRAAoK3RZqEwC3AQARAAoK3RZqEwC3AQAAAA==.Kizzs:BAABNQAECn8dAAMFAAoK/Bd+IwD9AQAFAAoKAhd+IwD9AQADAAMKQh7KUACeAAAAAA==.',
Ko='Kobesama:BAABNQAECn8rAAIOAAoKmA6BWgC4AQAOAAoKmA6BWgC4AQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8dAAMgAAgKCxHsCwCcAQAgAAgKCxHsCwCcAQAaAAIKWgb+NgBXAAAAAA==.Konata:BAAANQADCggIDwABNQAECgoKNwARAK4eAA==.Korbenzoo:BAAANQADCgMIBAABNQAECggIMAAPAAAAAQ==.Korigan:BAAANQAECgcIDwAAAA==.',
Kr='Krom:BAAANQAECgEIAgABNQAECgoKJgAbAG8LAA==.Kryssie:BAABNQAECn86AAIBAAoK2xMlVADiAQABAAoK2xMlVADiAQAAAA==.',
Ku='Kudrah:BAAANQAECgEIAgABNQAECgkJGQAIACUUAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIhAAcKIwgkKgAfAQAhAAcKIwgkKgAfAQAAAA==.',
['Ká']='Kárg:BAAANQAECgUIBwABNQAECggIGAAHAPcIAA==.',
La='Lampard:BAAANQAECgcIDAABNQAECgoKJgAEADAhAA==.Lanaya:BAABNQAECn8jAAIHAAkKaxDRngBPAQAHAAkKaxDRngBPAQAAAA==.Laserheadten:BAACNQAFFH8GAAIWAAMKcA/YCgC5AAAWAAMKcA/YCgC5AAA1AAQKfykAAhYACgpIHLQUAL0CABYACgpIHLQUAL0CAAAA.Laudna:BAAANQAECgcIBwABNQAECggIEwAPAAAAAA==.Lawrensce:BAAANQAECgUICAAAAA==.',
Le='Leanore:BAAANQADCgUIBQABNQAECgkJOgAIAKoKAA==.Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAABNQAECn8XAAIFAAcKzwvLVgD9AAAFAAcKzwvLVgD9AAAAAA==.Lenian:BAABNQAECn8iAAIdAAgKixktDQCsAQAdAAgKixktDQCsAQAAAA==.Leâfs:BAABNQAECn8UAAMDAAYKiRMUbwBYAQADAAYKiRMUbwBYAQAFAAUKrQcpfwCuAAAAAA==.',
Li='Lichekinky:BAAANQAECgIIAgAAAA==.Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAABNQAECn8UAAIRAAUKtBb0KAD3AAARAAUKtBb0KAD3AAAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAAPAAAAAA==.Lostangell:BAAANQABCgMIAwAAAA==.Lourom:BAABNQAECn8iAAMBAAkKOBB9YwC3AQABAAkKMBB9YwC3AQAcAAYKxgx0SwAIAQAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAABNQAECn8aAAIOAAcKfgz4mgASAQAOAAcKfgz4mgASAQAAAA==.',
Ly='Lyraae:BAABNQAECn8iAAIQAAkKtREufgCRAQAQAAkKtREufgCRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Madtankage:BAAANQADCgMIAwAAAA==.Maegh:BAAANQADCgIIAgAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn9cAAMBAAoKTB3pGwCuAgABAAoKTB3pGwCuAgAcAAMK6wntRwBeAAAAAA==.Maiganoss:BAABNQAECn8WAAMEAAYKjxdhMABiAQAEAAYKjxdhMABiAQADAAEKpQJ1AAEXAAAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgAPAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAABNQAECn8aAAICAAoKdwqExgD3AQACAAoKdwqExgD3AQAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBQAAAA==.',
Me='Megid:BAABNQAECn8jAAIRAAkKdR7YFQBQAgARAAkKdR7YFQBQAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8qAAIFAAoKpxiFJQBoAgAFAAoKpxiFJQBoAgAAAA==.Methalos:BAAANQABCgIIAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAABNQAECn8XAAIiAAgKjwXyHQAAAQAiAAgKjwXyHQAAAQABNQAECgkJOgAIAKoKAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mildsteel:BAAANQAECggIAQAAAA==.Mimey:BAAANQAECgcICAAAAA==.Mimie:BAAANQAECggIBgAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAABNQAECn8cAAICAAoKdQshYQDJAQACAAoKdQshYQDJAQAAAA==.Misao:BAAANQAECgIIBAABNQAECgoKNwARAK4eAA==.Mizblumkin:BAAANQAECgcIEAAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moomoom:BAAANQAECgMIBQAAAA==.Moonbeard:BAAANQADCgMIAwAAAA==.Moonfizzle:BAAANQAECgQIBAAAAA==.Moonnshine:BAABNQAECn8hAAMIAAkKEwV0YwBAAQAIAAkKEwV0YwBAAQAJAAYKXwIjVgCvAAAAAA==.Moonrend:BAAANQAECgYIDAAAAA==.Moonzire:BAAANQAECgUIBwAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECggIMAAPAAAAAQ==.',
Mu='Muradil:BAAANQADCgMIBAAAAA==.Murgrot:BAAANQADCgcIEQAAAA==.',
My='Mylittlepwni:BAAANQAECgMIBQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcIBwAAAA==.',
['Mû']='Mûffin:BAAANQAECgcICQAAAA==.',
Na='Nainel:BAAANQAECgEIAQABNQAECggIIgAdAIsZAA==.Nakros:BAAANQAECggICAAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECggIIwACAAEiAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECgYIDwAAAA==.Nerik:BAAANQAECgMIBAAAAA==.Nerissa:BAEBNQAECn8VAAISAAoK9wZKwwBjAAASAAoK9wZKwwBjAAAAAA==.Netallia:BAAANQAECgEIAwAAAA==.',
Ng='Ngyue:BAAANQADCgYIJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAIBAAcKbxq9agA+AgABAAcKbxq9agA+AgAAAA==.Nickto:BAABNQAECn8UAAIHAAYKeAJtQwFZAAAHAAYKeAJtQwFZAAAAAA==.Nightshayed:BAAANQADCggIDwAAAA==.Niishaa:BAAANQAECgYIBgABNQAECgcIHAADAJUEAA==.Niëtz:BAAANQAECgEIAgAAAA==.',
Nu='Nubin:BAAANQAECgMIAgAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgcIGgAOAH4MAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Oa='Oaknsheild:BAAANQADCgUIBQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIFQABAMEHAA==.',
On='Onsight:BAAANQAECgEIAQAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECgYIGAAeAA0WAA==.Ophnakyel:BAAANQADCgEIAQAAAA==.',
Or='Orceo:BAAANQAECgEIAQAAAA==.Orcrest:BAAANQAECgUICQAAAA==.Ororo:BAABNQAECn8qAAIbAAkK1BlyRABkAgAbAAkK1BlyRABkAgAAAA==.',
Pa='Palal:BAAANQAECgEIAQABNQAECgcIFAAHAOEiAA==.Paog:BAAANQADCggIEAAAAA==.Paryah:BAABNQAECn8jAAIVAAgKrgfCaAAcAQAVAAgKrgfCaAAcAQAAAA==.Pauken:BAAANQAECgcIDAABNQAECgoKNQALAM4eAA==.',
Ph='Phanceester:BAAANQAECgUIBwAAAA==.Phindra:BAAANQAECgQIBgAAAA==.Phonut:BAAANQADCgcIDQAAAA==.Phréek:BAABNQAECn9BAAMSAAoKIhyYFQDfAgASAAoKIhyYFQDfAgAHAAkKtxSlaQC/AQAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAACNQAFFH8UAAIEAAYKYAysDQDmAAAEAAYKYAysDQDmAAA1AAQKf0UAAgQACgozHSgOAJsCAAQACgozHSgOAJsCAAAA.',
Po='Poetea:BAAANQAECgYIDAAAAA==.Portalslag:BAAANQAECggIDAAAAA==.',
Pr='Praze:BAAANQAECgUICQAAAA==.',
Pu='Punyboy:BAAANQAECgQIBAAAAA==.Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgABNQAECgEIAQAPAAAAAA==.Rahis:BAABNQAECn88AAMBAAoKZhbEPgAiAgABAAoKZhbEPgAiAgAcAAEKeAOJkQAuAAAAAA==.Raiu:BAABNQAECn8jAAIQAAgKmhmNMQAnAgAQAAgKmhmNMQAnAgAAAA==.Ramsis:BAABNQAECn8gAAIQAAoKDht2RgBHAgAQAAoKDht2RgBHAgAAAA==.Randir:BAABNQAECn9BAAIWAAoKUxbLFgCkAgAWAAoKUxbLFgCkAgAAAA==.Ranir:BAAANQAECgMIBQAAAA==.Rath:BAABNQAECn8cAAIeAAgK2BlIJQD5AQAeAAgK2BlIJQD5AQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAABNQAECn8WAAMSAAcKoRLahgDyAAASAAQK7RPahgDyAAAHAAUKUgtmEwGVAAAAAA==.Remedivhs:BAAANQAECgIIAwABNQAECggIMAAPAAAAAQ==.Rettbull:BAAANQAECgEIAQAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAABNQAECn8ZAAICAAYKwAfCNwEwAQACAAYKwAfCNwEwAQAAAA==.Rhyli:BAAANQAECgEIAQAAAA==.',
Ro='Robinhoodx:BAABNQAECn87AAIBAAoKTBp5QQCmAgABAAoKTBp5QQCmAgAAAA==.Rockbottom:BAAANQAECgEIAQABNQAECggIIwAEAIkWAA==.Roenabur:BAAANQAECgEIAQAAAA==.Romok:BAAANQAECgUIDAAAAA==.Rosaline:BAAANQAECgQIBgAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rà']='Ràyne:BAAANQADCggIGwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8pAAIHAAgKFg2v1QBwAQAHAAgKFg2v1QBwAQAAAA==.Samoot:BAABNQAECn86AAIIAAkKqgrFLQBcAQAIAAkKqgrFLQBcAQAAAA==.Sanguina:BAAANQADCgYIBgAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQADCgYIEQABNQAECggIMAAPAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAABNQAECn8jAAIMAAgKgArLfAAxAQAMAAgKgArLfAAxAQAAAA==.Shamanstein:BAAANQADCggJDwABNQAFFAUIDQAHAI4gAA==.Shammbo:BAAANQAECggIEQAAAA==.Sharty:BAAANQAECggIEwAAAA==.Shazra:BAABNQAECn8YAAIJAAoKEgjcKABeAQAJAAoKEgjcKABeAQAAAA==.Sheriruth:BAAANQAECggIEgABNQAECgoKNQALAM4eAA==.Shortigen:BAAANQAECgUIBwAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.Shuub:BAAANQAECggIEwAAAA==.',
Si='Sicnus:BAAANQADCggIEAAAAA==.Silveryl:BAABNQAECn8YAAMeAAYKDRbfIwBDAQAeAAYKDRbfIwBDAQAhAAQKgQzgJQCqAAAAAA==.Sinadin:BAABNQAECn8/AAIHAAoKHxT9XwDYAQAHAAoKHxT9XwDYAQAAAA==.Sindoreisins:BAABNQAECn8eAAITAAoKkxDAUQC5AQATAAoKkxDAUQC5AQAAAA==.Sizzlinghots:BAABNQAECn83AAIJAAoKzBExFAA+AgAJAAoKzBExFAA+AgAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIIgATAO4LAA==.Skolmaster:BAABNQAECn8dAAICAAoKxg4fdQCUAQACAAoKxg4fdQCUAQAAAA==.Skootter:BAAANQADCgYIBwAAAA==.Skyfury:BAABNQAECn8kAAMQAAkKbhRrSgC3AQAQAAkKbhRrSgC3AQAbAAUKKRIIlgBtAQABNQAECgkJKwAQACceAA==.Skywalkr:BAAANQADCgYICwAAAA==.',
Sm='Smarky:BAACNQAFFH8IAAIWAAUKNw3aCQDQAAAWAAUKNw3aCQDQAAA1AAQKfxkAAhYACgouHiwOAAsDABYACgouHiwOAAsDAAAA.Smâlls:BAEBNQAECn8iAAIjAAcKFhsLCwBVAQAjAAcKFhsLCwBVAQAAAA==.',
Sn='Sneekie:BAAANQAECgEIAQAAAA==.Sneekiemage:BAAANQAECgQIDwAAAA==.Snugz:BAAANQAECgEIAgAAAA==.',
So='Sourdiesel:BAABNQAECn8WAAIBAAgK8wZ8pQAiAQABAAgK8wZ8pQAiAQAAAA==.Southsound:BAABNQAECn8ZAAICAAcKkw3JAQGLAQACAAcKkw3JAQGLAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQAPAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQAECgUIDgAAAA==.Steakknife:BAABNQAECn8VAAMfAAgKZhHkMQAXAgAfAAgKZhHkMQAXAgAVAAYK2AViMgApAQAAAA==.Stikybandage:BAAANQADCgcIBwAAAA==.Stormoon:BAABNQAECn8mAAMbAAkKhA2+XQAyAQAbAAgKOQy+XQAyAQAQAAcKxQv+qwAZAQAAAA==.Streigar:BAAANQAECgMIAwAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgQIAwAAAA==.',
Sy='Sybil:BAABNQAECn8ZAAIIAAkKJRRbJACjAQAIAAkKJRRbJACjAQAAAA==.',
Sz='Szer:BAAANQAECgUIBQAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAABNQAECn8fAAIBAAgKCQQUwwDnAAABAAgKCQQUwwDnAAAAAA==.Tahtiania:BAABNQAECn8VAAICAAcK9gQp+gCYAAACAAcK9gQp+gCYAAAAAA==.Talkurandis:BAAANQAECgcIGQABNQAECggIMAAPAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn8pAAIDAAoK4R+FCwCcAgADAAoK4R+FCwCcAgAAAA==.Teo:BAABNQAECn8jAAIBAAkKkRAYlwDaAQABAAkKkRAYlwDaAQAAAA==.Terraria:BAAANQAECgEIAgABNQAECgoKRAAUAM0gAA==.Teyamat:BAAANQAECggICwABNQAECgoKKQADAOEfAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8mAAMQAAoK7BzXHQD1AgAQAAoK7BzXHQD1AgAbAAMKqhGc9ACsAAAAAA==.Theory:BAAANQAECgUIBQAAAA==.Thetree:BAABNQAECn8nAAMJAAkKrRviFAChAgAJAAkKrRviFAChAgAIAAcK+xsvPgAHAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIIgATAO4LAA==.Thoughtcrime:BAAANQAECgcIDQAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8uAAIYAAkKdRq2AgBGAgAYAAkKdRq2AgBGAgAAAA==.',
Ti='Timoris:BAAANQAECgYICgABNQAECgoKNQALAM4eAA==.',
To='Tobiume:BAAANQAECgYICgABNQAECggIHgARAAgQAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAABNQAECn8VAAIBAAYKwQdy0QBeAQABAAYKwQdy0QBeAQAAAA==.Toodles:BAAANQADCggIFgAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgMIBwAAAA==.Trildjr:BAABNQAECn8UAAIBAAcKRw/RvQCIAQABAAcKRw/RvQCIAQAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn8vAAIbAAkK7wlsiACPAQAbAAkK7wlsiACPAQAAAA==.',
Ty='Tyronda:BAAANQADCggIJAAAAA==.Tyrse:BAABNQAECn8ZAAIXAAcKJgekCQABAQAXAAcKJgekCQABAQAAAA==.',
Tz='Tzerina:BAABNQAECn8ZAAIKAAYKEgweSQDMAAAKAAYKEgweSQDMAAAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECggIMAAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8kAAISAAkKJRGGbQDPAQASAAkKJRGGbQDPAQAAAA==.Validan:BAAANQAECgUIDAAAAA==.Valkriss:BAAANQAECgEIAQAAAA==.Vallyrie:BAABNQAECn8uAAMEAAoKxRqqHwDRAQAEAAkKfxqqHwDRAQADAAcKMRWVYwCCAQAAAA==.Valssharess:BAABNQAECn8lAAIkAAcK9x0LFQAWAgAkAAcK9x0LFQAWAgAAAA==.Valth:BAAANQAECgMIBQAAAA==.Valweyna:BAAANQADCgIIAgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgAPAAAAAA==.Vaporgriffin:BAAANQAECgYIEQAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgYIBwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgUICQAAAA==.Veleria:BAABNQAECn8vAAMSAAkKehj0SwA5AgASAAkKehj0SwA5AgARAAYK5RgZKACdAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgMICAAAAA==.',
Vi='Victra:BAABNQAECn8fAAITAAoK2xDfRwDgAQATAAoK2xDfRwDgAQAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgYICwAAAA==.Vinaya:BAAANQAECgUICQAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQAPAAAAAA==.',
Vo='Volthemar:BAABNQAECn88AAMOAAoK3CCkIwCUAgAOAAoKfSCkIwCUAgAdAAQK1hzaJAAfAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Wa='Wanabe:BAAANQADCgUIBQAAAA==.Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCggIDwABNQAECggIIQAaADwVAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn81AAIHAAkK6Ag4tQAmAQAHAAkK6Ag4tQAmAQAAAA==.',
Wh='Whatevyr:BAAANQAECgEIAQAAAA==.Whitespot:BAAANQAECgQIBQAAAA==.',
Wi='Wilson:BAAANQADCgYIBwABNQAECggIIwACAAEiAA==.Wisegurl:BAABNQAECn8qAAMHAAoKoiLXLQCAAgAHAAoKLSLXLQCAAgARAAUKBBYLQgBzAAAAAA==.',
Wo='Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn8tAAIIAAoK6RGdIADEAQAIAAoK6RGdIADEAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgQIBwAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wybpally:BAAANQAECgEIAQAAAA==.Wylecsham:BAAANQAECgIIBAAAAA==.Wylectra:BAABNQAECn86AAITAAoKchOvNQAxAgATAAoKchOvNQAxAgAAAA==.',
Xe='Xethos:BAAANQAECggICQAAAA==.',
Xy='Xyleeha:BAAANQADCggIGwAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn9BAAMBAAoKSw4eUQDrAQABAAoKSw4eUQDrAQAcAAEKAADjogAPAAAAAA==.Yerdedmatey:BAAANQAECgIIAQAAAA==.',
Yo='Yomiko:BAAANQAECgIIBQABNQAECgoKNwARAK4eAA==.Yoshikatsu:BAAANQADCggICAAAAA==.Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn9EAAIQAAoKCxzSLwCiAgAQAAoKCxzSLwCiAgAAAA==.Zahvaria:BAABNQAECn8dAAIVAAcKTgYCewDdAAAVAAcKTgYCewDdAAAAAA==.Zamari:BAAANQAECgEIAQABNQAECgcIHQAVAE4GAA==.Zaphiell:BAABNQAECn8eAAIWAAkK2hWqIgAeAgAWAAkK2hWqIgAeAgAAAA==.Zazzy:BAEANQAECgMIBgABNQAFFAQIDgAcALELAA==.',
Ze='Zeid:BAABNQAECn8bAAIOAAoK2g2jhAAQAgAOAAoK2g2jhAAQAgAAAA==.Zev:BAAANQAECgUICQAAAA==.',
Zi='Zillz:BAABNQAECn8WAAISAAcKjQxjZgBRAQASAAcKjQxjZgBRAQAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECggIMAAPAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgIIBAAAAA==.',
Zo='Zoeystorm:BAABNQAECn8pAAMHAAcK+AfVBQEVAQAHAAcKcwfVBQEVAQARAAQKCgaWUABHAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAIDAAkKEBSYQwAMAgADAAkKEBSYQwAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAACNQAFFH8GAAQBAAMKyAjUHwCFAAABAAIKKwnUHwCFAAAcAAIK1gVXEwB2AAAXAAEKrAk6AgBEAAA1AAQKfzYABAEACgoVF69fAFgCAAEACApYG69fAFgCABwABwo4DPgdAEcBABcAAgpjCH8OAFcAAAAA.',
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
