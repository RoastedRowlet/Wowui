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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Priest-Holy','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Priest-Discipline','Warrior-Fury','Evoker-Devastation','Shaman-Elemental','Hunter-Marksmanship','Warrior-Protection','Monk-Windwalker','Rogue-Assassination','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acehigh:BAAANQABCgYICgABNQAFFAcIIQABAHkdAA==.Acemage:BAABNQAECn8eAAICAAoKmQ+gsgAeAgACAAoKmQ+gsgAeAgABNQAFFAcIIQABAHkdAA==.',
Ae='Aegon:BAABNQAECn83AAQDAAoKGyITHwDRAgADAAoKGyITHwDRAgAEAAoK9wnEbgA6AQAFAAEKEAfusgAtAAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn8tAAMGAAkKfR85BgDfAQAGAAYK7R45BgDfAQACAAcKZB4ObABvAQAAAA==.',
Ah='Ahdonis:BAAANQAECggIDwAAAA==.Ahnerfays:BAAANQAECggICgAAAA==.',
Ai='Aiara:BAAANQAECgIIAQAAAA==.Aiarra:BAABNQAECn8vAAMHAAoKABMSQQD0AQAHAAoKABMSQQD0AQAIAAQKxgwvWgCfAAAAAA==.Aindriana:BAABNQAECn8nAAIJAAcKrQguMQAeAQAJAAcKrQguMQAeAQAAAA==.Aitra:BAABNQAECn8aAAQKAAcKeALXDgCgAAAKAAcKYALXDgCgAAALAAUK6AFGIwF7AAAMAAEKUQKfiQAVAAAAAA==.',
Aj='Ajx:BAAANQAECgUICAABNQAECgcIFQANANkLAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECn8ZAAIBAAcKUBPOkwDhAQABAAcKUBPOkwDhAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgoKLAAKAOwdAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alaeryth:BAAANQAECgcICQABNQAECggIAgAOAAAAAA==.Alerothon:BAABNQAECn9JAAIPAAoKWxfZOwALAgAPAAoKWxfZOwALAgAAAA==.Alestiana:BAABNQAECn88AAIQAAoKgRebHQBWAgAQAAoKgRebHQBWAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAABNQAECn8uAAIRAAoKNBRjGwATAgARAAoKNBRjGwATAgAAAA==.Amnadores:BAABNQAECn8bAAICAAYK9geCLgE/AQACAAYK9geCLgE/AQABNQAECgkJKQALAHAWAA==.',
An='Andii:BAAANQAECgcICgAAAA==.Annati:BAACNQAFFH8LAAIQAAcKDhnoCwCOAQAQAAcKDhnoCwCOAQA1AAQKfyoAAhAACgqTIXoVACMDABAACgqTIXoVACMDAAAA.Antarres:BAABNQAECn8nAAILAAoKAAlgegADAQALAAoKAAlgegADAQAAAA==.',
Ao='Aoba:BAABNQAECn8zAAMRAAoKrh68FABdAgARAAgKMhy8FABdAgASAAgKFAYPVABJAQAAAA==.',
Ap='Apila:BAAANQADCgEIAgABNQAECgcIJgAOAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAABNQAECn8YAAITAAoKIxQmGQCYAgATAAoKIxQmGQCYAgAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAQICgAFAJ4RAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECggICgAOAAAAAA==.Areaman:BAAANQADCgcIEAABNQAECgcIHAACAFQhAA==.Aridam:BAAANQAECgQIBAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisdrake:BAAANQADCgIIAQABNQADCgIIAgAOAAAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgAOAAAAAA==.Artemisshade:BAABNQAECn8oAAMUAAkK1RqqAQAEAgAUAAkK1RqqAQAEAgAVAAQKjBIcNQARAQABNQADCgIIAgAOAAAAAA==.Arthillius:BAAANQAECgIIBAAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Au='Aurica:BAAANQAECgYICgAAAA==.',
Av='Aviana:BAABNQAECn8aAAIWAAYKZAmlSQD0AAAWAAYKZAmlSQD0AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgUICAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8vAAMBAAkKvBKvlgDbAQABAAkK5BGvlgDbAQAXAAcK7AkNCQCyAQAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.Belle:BAAANQAECgYICAAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECn8ZAAMLAAkKpQ68igDMAQALAAgKkg28igDMAQAMAAIKnhFbWAB2AAAAAA==.',
Bj='Bjornmodi:BAAANQAECgcIBgAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzlock:BAAANQAECgIIAgABNQAECgoKIQAHAIgZAA==.Blitzy:BAABNQAECn8hAAIHAAoKiBlNIADKAgAHAAoKiBlNIADKAgAAAA==.',
Bo='Bobbette:BAABNQAECn8YAAQTAAcK1Q8GbgAMAQATAAcK1Q8GbgAMAQAWAAMKlwb7YAB9AAAYAAEKnwPMMAAjAAABNQAECgoKHQAQAA4bAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Brenick:BAABNQAECn8XAAIZAAcKhAv0DwDtAAAZAAcKhAv0DwDtAAAAAA==.Brewtalize:BAAANQABCgcICQAAAA==.Bringer:BAAANQAECgMIAwAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQAECgEIAQAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQIBAAAAA==.Burnie:BAABNQAECn8aAAIaAAcKehROCgBKAQAaAAcKehROCgBKAQAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAABNQAECn8aAAIbAAgKlhi6IwDjAQAbAAgKlhi6IwDjAQAAAA==.Camilah:BAABNQAECn8mAAIDAAoKkx2qCQCHAgADAAoKkx2qCQCHAgAAAA==.Capa:BAABNQAECn8sAAQKAAoK7B1xBACUAgAKAAgKdR5xBACUAgALAAUKxhrrzgAsAQAMAAMKOBeiOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECn8cAAICAAoKkhtaUQC6AQACAAoKkhtaUQC6AQAAAA==.',
Ce='Celestiné:BAAANQAECgUICAAAAA==.Cemeteri:BAAANQADCggIDwAAAA==.',
Ch='Chaingun:BAABNQAECn8VAAICAAgKpQrPGQFhAQACAAgKpQrPGQFhAQAAAA==.Chaps:BAAANQAECgMIAgAAAA==.Chelseac:BAAANQAECgUIEwABNQAECgcIGQACAJMNAA==.Chilblain:BAABNQAECn86AAIGAAoKsxBMBwC6AQAGAAoKsxBMBwC6AQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECn9FAAIcAAoKahqdCwAeAgAcAAoKahqdCwAeAgAAAA==.',
Ci='Cibochevski:BAAANQADCggIDwABNQAECgcIGwAdABwYAA==.Ciratorynth:BAABNQAECn8oAAIaAAoKHRPgCQBUAQAaAAoKHRPgCQBUAQAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8nAAIQAAoKESNZDwBIAwAQAAoKESNZDwBIAwAAAA==.',
Cl='Claferi:BAAANQADCgMIAwAAAA==.Clearlove:BAAANQAECgYIBAABNQAECgcIGQACAJMNAA==.Clearlovec:BAAANQAECgcICAABNQAECgcIGQACAJMNAA==.Closetfurry:BAABNQAECn8iAAIPAAcKAQ+FowAOAQAPAAcKAQ+FowAOAQAAAA==.',
Co='Codenheimer:BAAANQAECgUICgAAAA==.Condor:BAAANQAECggICwAAAA==.Corrinne:BAABNQAECn8mAAIPAAoKBRglaABjAgAPAAoKBRglaABjAgAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Crankk:BAAANQAECgEIAQAAAA==.Critmypänts:BAAANQAECgUIDAAAAA==.',
Cz='Czernobog:BAABNQAECn8YAAIRAAkKYRkcDwCsAQARAAkKYRkcDwCsAQAAAA==.',
Da='Daeshan:BAABNQAECn83AAIeAAoKJxc6DgAJAgAeAAoKJxc6DgAJAgAAAA==.Dafirstone:BAAANQAECgcIDAAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECn81AAISAAoKWh9WGQATAwASAAoKWh9WGQATAwAAAA==.Daradevil:BAAANQADCgcIBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcIBwAOAAAAAA==.Daralune:BAAANQAECgMIBQAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn8yAAMPAAoKJRdzaQBgAgAPAAoKJRdzaQBgAgARAAEKxwQWgQAbAAAAAA==.Dasecondone:BAAANQAECgUIEAAAAA==.Dathirdone:BAAANQADCggIIQAAAA==.Dawg:BAAANQAECgQIDQAAAA==.',
De='Deadlytankz:BAAANQADCgQIBAAAAA==.Deadval:BAAANQADCgcIDwAAAA==.Demonicfyre:BAECNQAFFH8PAAICAAUKDBmNFAD4AAACAAUKDBmNFAD4AAA1AAQKfyQAAgIACgpyHZdVANUCAAIACgpyHZdVANUCAAAA.Demonstein:BAAANQAECgUIBQABNQAFFAUIDQAPAI4gAA==.Destros:BAAANQAECgYIEgAAAA==.',
Di='Dillon:BAAANQAECgIIAgAAAA==.Disdain:BAAANQAECgYICQABNQAFFAgIJAALAEwZAA==.',
Do='Donchap:BAAANQAECggIDgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQAECgIIAgABNQADCgQJBAAOAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgUIBwAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn8xAAMDAAoKLB3OLACBAgADAAgKrB7OLACBAgAFAAgKPBfJQADEAQAAAA==.Drzip:BAABNQAECn8YAAICAAgKFQ8giwAsAQACAAgKFQ8giwAsAQAAAA==.Drzippy:BAAANQAECgMIBQAAAA==.',
Du='Duane:BAAANQAECggIEgAAAA==.Duskthrasher:BAABNQAECn8cAAIDAAcKlQQNQQC1AAADAAcKlQQNQQC1AAAAAA==.Duyii:BAAANQADCgYIEAABNQAECgcIJgAOAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8oAAIBAAoKfxRwPwCsAgABAAoKfxRwPwCsAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgUIDgAAAA==.',
Ea='Easterneon:BAAANQAECgUICgABNQAECgcIGQACAJMNAA==.',
Ec='Ech:BAABNQAECn83AAINAAoKuxkFKwAyAgANAAoKuxkFKwAyAgAAAA==.',
Ei='Eiraveta:BAABNQAECn8iAAITAAkKSA1vgACXAQATAAkKSA1vgACXAQAAAA==.',
El='Eldrinn:BAAANQABCggIFQAAAA==.Elemental:BAABNQAECn8fAAICAAgKcgNgvQDNAAACAAgKcgNgvQDNAAAAAA==.Elendirs:BAAANQABCgYIGwABNQABCgcIDgAOAAAAAA==.Ellois:BAAANQAECgYIDgAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAAANQAECgcIDQABNQAECgoKFgABAJ4PAA==.',
Ep='Epicnoname:BAACNQAFFH8KAAIFAAQKnhGFCgDLAAAFAAQKnhGFCgDLAAA1AAQKfyQAAgUACgrOHIUgAIkCAAUACgrOHIUgAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQAECgUIDwAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgcICAABNQAECggICAAOAAAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIEAAcKoBlCSgDOAQAEAAcKoBlCSgDOAQABNQAECgoKFQAdACgcAA==.Fave:BAAANQADCgYIBgABNQAECgkJIQAQAAsTAA==.',
Fe='Feannesse:BAAANQAECgYIEAAAAA==.Festival:BAABNQAECn8VAAIdAAoKKByxAwCYAgAdAAoKKByxAwCYAgAAAA==.',
Fi='Firebolt:BAABNQAECn8nAAMQAAcKfhsdRQCBAQAQAAcKfhsdRQCBAQAbAAMKvRAG9gCoAAABNQAECgkJIQAQAAsTAA==.Fitts:BAAANQAECgcIDAABNQAFFAQIBgAIABkOAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHgAfAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAABNQAECn8YAAMPAAgKDAcwGgHzAAAPAAYKSQYwGgHzAAASAAUK3ASEgADGAAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAABNQAECn8VAAIBAAgKChxkWwBjAgABAAgKChxkWwBjAgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgYIDQAOAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Garekk:BAABNQAECn8WAAIBAAoKng8iggAIAgABAAoKng8iggAIAgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9TAAMFAAoKWCLLBQCEAwAFAAoKWCLLBQCEAwADAAgKmx2MFgDLAQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCggIDwAAAA==.Goneville:BAAANQAECggICgAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAABNQAECn8dAAMQAAoKFwPmdgDaAAAQAAoKFwPmdgDaAAAbAAEKZwG20wAeAAAAAA==.',
Gt='Gtx:BAAANQAECgUIDAAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggIDgABNQAECgIIAwAOAAAAAA==.Gutworthy:BAAANQAECgYICAAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQAECgQIBAAAAA==.Hallzypal:BAAANQAECgcICQAAAA==.Hammerjane:BAABNQAECn8cAAISAAcKahbcNgDDAQASAAcKahbcNgDDAQAAAA==.Hamur:BAABNQAECn8eAAMYAAcKQBv/BgAQAgAYAAcKQBv/BgAQAgATAAEKCQvWzgAqAAAAAA==.Hariyaki:BAABNQAECn8aAAIeAAcKvAkZJwDsAAAeAAcKvAkZJwDsAAAAAA==.Havebandaids:BAAANQADCgEIAQAAAA==.',
He='Heavywinner:BAABNQAECn88AAMHAAoKVxssGQD+AgAHAAoKVxssGQD+AgAIAAYKww32OAC4AAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8oAAITAAoKJSXACwAmAwATAAoKJSXACwAmAwAAAA==.Hellmage:BAAANQADCgYIBwAAAA==.Hellsfury:BAAANQAECgQIBAAAAA==.Hellslayer:BAABNQAECn8bAAMdAAgKaRfdEQAJAgAdAAgKaRfdEQAJAgANAAIK8AiGOAFjAAAAAA==.Hellwalker:BAAANQADCggILAAAAA==.Hellzy:BAAANQADCggIEAAAAA==.',
Hn='Hnof:BAAANQAECgEIAQABNQAFFAQICQATAMoRAA==.',
Ho='Holyfire:BAAANQADCgcIBwABNQAECgkJIQAQAAsTAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAABNQAECn8cAAMNAAcKxQmejwDvAAANAAcK/QiejwDvAAAdAAEKrgsGLwA4AAAAAA==.',
['Hâ']='Hârlot:BAABNQAECn8cAAIJAAcKcQ0AMwASAQAJAAcKcQ0AMwASAQAAAA==.',
['Hè']='Hèathen:BAAANQADCggIDwAAAA==.',
Id='Idamage:BAAANQAECgEIAQABNQAECggICAAOAAAAAA==.',
Ig='Igetmoney:BAAANQABCgEIAQAAAA==.',
In='Ingenii:BAAANQAECgUIBAABNQAECgoKLAAKAOwdAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8UAAILAAYK9hjXBgBBAQALAAYK9hjXBgBBAQA1AAQKfx8AAgsACgogIMIGAAUDAAsACgogIMIGAAUDAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgMIAwAAAA==.Jaestra:BAAANQADCggIGQABNQAECgcIHAATAFwWAA==.Jaidah:BAAANQADCggIJgAAAA==.Jaith:BAAANQAECgEIAQAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICAAOAAAAAA==.Jansôlo:BAABNQAECn8XAAMBAAgKAiJLOQC+AgABAAgKAiJLOQC+AgAcAAMKiBS8XwCnAAAAAA==.Jaratri:BAACNQAFFH8IAAIXAAMKsw3NAQCgAAAXAAMKsw3NAQCgAAA1AAQKf0sAAhcACgpnGyYDAOkCABcACgpnGyYDAOkCAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8eAAICAAgKhgiuEAFxAQACAAgKhgiuEAFxAQAAAA==.',
Ka='Kaatu:BAAANQADCgMIAwAAAA==.Kaerovia:BAABNQAECn8hAAISAAkKHRWITwAtAgASAAkKHRWITwAtAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8nAAIbAAoKVBVoOgCMAgAbAAoKVBVoOgCMAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICAAAAA==.Karg:BAABNQAECn8YAAIPAAgK9whN1QBxAQAPAAgK9whN1QBxAQAAAA==.Karmai:BAABNQAECn87AAMUAAoKzSA4AgBBAwAUAAkKYiA4AgBBAwAVAAoKMxhPFwBjAgAAAA==.Kastigor:BAAANQAECgcIDAABNQAFFAIIBwAJAIYSAA==.Kathine:BAAANQAECgUIEAAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgcIDgAAAA==.Kazue:BAAANQAECgQIBwABNQAECgoKJgAPAAUYAA==.',
Ke='Keaa:BAAANQAECgYIDgAAAA==.Kelvala:BAABNQAECn8yAAMNAAoKwyO5JgAeAwANAAkKiCK5JgAeAwAZAAcKLSQoCwASAgAAAA==.Kelwynd:BAABNQAECn8WAAIcAAYK2hsXEgChAQAcAAYK2hsXEgChAQAAAA==.Kesle:BAAANQADCgUIBQAAAA==.Keä:BAABNQAECn8eAAMSAAoKCAw5cADHAQASAAoKCAw5cADHAQAPAAcKKAuXDQEIAQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn83AAIRAAoKrhZHDwCqAQARAAoKrhZHDwCqAQAAAA==.Kizzs:BAABNQAECn8YAAMFAAoKeBEXJACuAQAFAAoKfhAXJACuAQADAAMKQh5LRQCjAAAAAA==.',
Ko='Kobesama:BAABNQAECn8rAAINAAoKmA78QwC/AQANAAoKmA78QwC/AQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8dAAMgAAgKCxHsCwCcAQAgAAgKCxHsCwCcAQAaAAIKWgb+NgBXAAAAAA==.Konata:BAAANQADCggIDwABNQAECgoKMwARAK4eAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgcIJgAOAAAAAQ==.Korigan:BAAANQAECgYIDQAAAA==.',
Kr='Krom:BAAANQAECgEIAgABNQAECgoKIQAbANIJAA==.Kryssie:BAABNQAECn8xAAIBAAkK6hQyUQCpAQABAAkK6hQyUQCpAQAAAA==.',
Ku='Kudrah:BAAANQADCgQICAABNQAECgkJFgAHAKsRAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIhAAcKIwgkKgAfAQAhAAcKIwgkKgAfAQAAAA==.',
['Ká']='Kárg:BAAANQAECgUIBQABNQAECggIGAAPAPcIAA==.',
La='Lampard:BAAANQAECggICQAAAA==.Lanaya:BAABNQAECn8cAAIPAAgK/A7KvgCfAQAPAAgK/A7KvgCfAQAAAA==.Laserheadten:BAACNQAFFH8FAAIWAAIKURD7CwB1AAAWAAIKURD7CwB1AAA1AAQKfygAAhYACgpIHLQUAL0CABYACgpIHLQUAL0CAAAA.Laudna:BAAANQAECgcIBwABNQAECggIDwAOAAAAAA==.Lawrensce:BAAANQAECgQIBwAAAA==.',
Le='Leanore:BAAANQADCgUIBQABNQAECgkJMgAHAJQIAA==.Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAABNQAECn8WAAIFAAcKzwsxRAAGAQAFAAcKzwsxRAAGAQAAAA==.Lenian:BAABNQAECn8bAAIdAAcKHBjMDgBJAQAdAAcKHBjMDgBJAQAAAA==.Leâfs:BAABNQAECn8UAAMDAAYKiRMUbwBYAQADAAYKiRMUbwBYAQAFAAUKrQcpfwCuAAAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQAECgUIEAAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAAOAAAAAA==.Lourom:BAABNQAECn8hAAMBAAkKmg8vSADGAQABAAkKkw8vSADGAQAcAAYKxgx0SwAIAQAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAABNQAECn8VAAINAAcK2QtmgwAMAQANAAcK2QtmgwAMAQAAAA==.',
Ly='Lyraae:BAABNQAECn8hAAIQAAgKFRIufgCRAQAQAAgKFRIufgCRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn9NAAMBAAoKERxzHAB9AgABAAoKERxzHAB9AgAcAAMK6wmtPABkAAAAAA==.Maiganoss:BAAANQAECgYIEgAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgAOAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAABNQAECn8WAAICAAoKewmExgD3AQACAAoKewmExgD3AQAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBQAAAA==.',
Me='Megid:BAABNQAECn8iAAIRAAkKdR3YFQBQAgARAAkKdR3YFQBQAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8nAAIFAAkKKBmFJQBoAgAFAAkKKBmFJQBoAgAAAA==.Methalos:BAAANQABCgIIAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAAANQAECgQICQABNQAECgkJMgAHAJQIAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgUIBQAAAA==.Mimie:BAAANQAECggIBQAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAABNQAECn8VAAICAAgK+AqKegBOAQACAAgK+AqKegBOAQAAAA==.Mizblumkin:BAAANQAECgYICAAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moonbeard:BAAANQADCgMIAwAAAA==.Moonfizzle:BAAANQAECgQIBAAAAA==.Moonnshine:BAABNQAECn8hAAMHAAkKEwV0YwBAAQAHAAkKEwV0YwBAAQAIAAYKXwIjVgCvAAAAAA==.Moonrend:BAAANQAECgQIBAAAAA==.Moonzire:BAAANQAECgUIBQAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECgcIJgAOAAAAAQ==.',
Mu='Muradil:BAAANQADCgMIBAAAAA==.Murgrot:BAAANQADCgcIEQAAAA==.',
My='Mylittlepwni:BAAANQAECgMIBQAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcIBwAAAA==.',
['Mû']='Mûffin:BAAANQAECgcIBwAAAA==.',
Na='Nainel:BAAANQADCggIGQABNQAECgcIGwAdABwYAA==.Nakros:BAAANQAECgYIBwAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgcIHAACAFQhAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECgYIDwAAAA==.Nerik:BAAANQAECgMIBAAAAA==.Nerissa:BAEANQAECggIEQAAAA==.',
Ng='Ngyue:BAAANQADCgYIJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAIBAAcKbxq9agA+AgABAAcKbxq9agA+AgAAAA==.Nickto:BAAANQAECgUICwAAAA==.Nightshayed:BAAANQADCggIDwAAAA==.',
Nu='Nubin:BAAANQAECgMIAgAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgcIFQANANkLAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Oa='Oaknsheild:BAAANQADCgUIBQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIFQABAMEHAA==.',
On='Onsight:BAAANQAECgEIAQAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECgYIFAAeAA0WAA==.',
Or='Orceo:BAAANQAECgEIAQAAAA==.Orcrest:BAAANQAECgIIBAAAAA==.Ororo:BAABNQAECn8qAAIbAAkK1BlyRABkAgAbAAkK1BlyRABkAgAAAA==.',
Pa='Palal:BAAANQAECgEIAQABNQAECgYIDwAOAAAAAA==.Paog:BAAANQADCggIEAAAAA==.Paryah:BAABNQAECn8cAAIVAAcK5wY7XADrAAAVAAcK5wY7XADrAAAAAA==.Pauken:BAAANQAECgcICgABNQAECgoKLAAKAOwdAA==.',
Ph='Phanceester:BAAANQAECgIIBAAAAA==.Phindra:BAAANQAECgQIBgAAAA==.Phonut:BAAANQADCgcIDQAAAA==.Phréek:BAABNQAECn82AAMSAAoK2x1RGACBAgASAAkKMR5RGACBAgAPAAYKzhSZhwBCAQAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAACNQAFFH8UAAIEAAYKYAwYCgDvAAAEAAYKYAwYCgDvAAA1AAQKfzEAAgQACgpqGiEOAGQCAAQACgpqGiEOAGQCAAAA.',
Po='Poetea:BAAANQAECgYICQAAAA==.Portalslag:BAAANQAECgcIBwAAAA==.',
Pr='Praze:BAAANQAECgIIBAAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgAAAA==.Rahis:BAABNQAECn8zAAMBAAkKdxeNPwDlAQABAAkKdxeNPwDlAQAcAAEKeAOJkQAuAAAAAA==.Raiu:BAABNQAECn8cAAIQAAcKQhjHOQCzAQAQAAcKQhjHOQCzAQAAAA==.Ramsis:BAABNQAECn8dAAIQAAoKDht2RgBHAgAQAAoKDht2RgBHAgAAAA==.Randir:BAABNQAECn85AAIWAAoKMRTLFgCkAgAWAAoKMRTLFgCkAgAAAA==.Ranir:BAAANQAECgIIAgAAAA==.Rath:BAABNQAECn8ZAAIeAAgKJxlIJQD5AQAeAAgKJxlIJQD5AQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgYIEAAAAA==.Remedivhs:BAAANQAECgIIAwABNQAECgcIJgAOAAAAAQ==.Rettbull:BAAANQADCggIGQAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAABNQAECn8ZAAICAAYKwAfCNwEwAQACAAYKwAfCNwEwAQABNQAECgcIHgAEAI4SAA==.Rhyli:BAAANQADCggIGQAAAA==.',
Ro='Robinhoodx:BAABNQAECn82AAIBAAoKfhlcLAAvAgABAAoKfhlcLAAvAgAAAA==.Rockbottom:BAAANQADCggIFgABNQAECgcIHAAEAOAWAA==.Roenabur:BAAANQADCggIHwAAAA==.Romok:BAAANQAECgMIBgAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rà']='Ràyne:BAAANQADCggIGwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8fAAIPAAgKFg2v1QBwAQAPAAgKFg2v1QBwAQAAAA==.Samoot:BAABNQAECn8yAAIHAAkKlAhNLAArAQAHAAkKlAhNLAArAQAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQADCgYIEQABNQAECgcIJgAOAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAABNQAECn8cAAILAAcKtwoEewABAQALAAcKtwoEewABAQAAAA==.Shamanstein:BAAANQADCggJDwABNQAFFAUIDQAPAI4gAA==.Shammbo:BAAANQAECggIEAAAAA==.Sharty:BAAANQAECggIEgAAAA==.Shazra:BAABNQAECn8YAAIIAAoKEgguHgBvAQAIAAoKEgguHgBvAQAAAA==.Sheriruth:BAAANQAECgYIEAABNQAECgoKLAAKAOwdAA==.Shortigen:BAAANQAECgIIAgAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.Shuub:BAAANQAECggICgAAAA==.',
Si='Sicnus:BAAANQADCggIEAAAAA==.Silveryl:BAABNQAECn8UAAIeAAYKDRZVHABKAQAeAAYKDRZVHABKAQAAAA==.Sinadin:BAABNQAECn86AAIPAAoKpxNYRgDlAQAPAAoKpxNYRgDlAQAAAA==.Sindoreisins:BAABNQAECn8ZAAITAAoKcg2ZUABvAQATAAoKcg2ZUABvAQAAAA==.Sizzlinghots:BAABNQAECn8rAAIIAAoKeA8FEQAWAgAIAAoKeA8FEQAWAgAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIIgATAO4LAA==.Skolmaster:BAABNQAECn8cAAICAAoKYQ7AWQCfAQACAAoKYQ7AWQCfAQAAAA==.Skootter:BAAANQADCgYIBwAAAA==.Skyfury:BAABNQAECn8hAAMQAAkKCxOePACmAQAQAAkKCxOePACmAQAbAAUKKRIIlgBtAQAAAA==.Skywalkr:BAAANQADCgYICwAAAA==.',
Sm='Smarky:BAACNQAFFH8IAAIWAAUKNw28BwDbAAAWAAUKNw28BwDbAAA1AAQKfxkAAhYACgouHiwOAAsDABYACgouHiwOAAsDAAAA.Smâlls:BAEBNQAECn8dAAIiAAcKFhtRCABiAQAiAAcKFhtRCABiAQAAAA==.',
Sn='Sneekiemage:BAAANQAECgQIDAAAAA==.Snugz:BAAANQAECgEIAgAAAA==.',
So='Sourdiesel:BAAANQAECgUICwAAAA==.Southsound:BAABNQAECn8ZAAICAAcKkw3JAQGLAQACAAcKkw3JAQGLAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQAOAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQAECgUICAAAAA==.Steakknife:BAABNQAECn8VAAMfAAgKZhHkMQAXAgAfAAgKZhHkMQAXAgAVAAYK2AViMgApAQAAAA==.Stikybandage:BAAANQADCgcIBwAAAA==.Stormoon:BAABNQAECn8jAAMbAAgKOQywSAA1AQAbAAgKOQywSAA1AQAQAAYKHw3+qwAZAQAAAA==.Streigar:BAAANQAECgMIAwAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgMIAwAAAA==.',
Sy='Sybil:BAABNQAECn8WAAIHAAkKqxGbHQCdAQAHAAkKqxGbHQCdAQAAAA==.',
Sz='Szer:BAAANQAECgUIBQAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAABNQAECn8YAAIBAAcKaANUtQDEAAABAAcKaANUtQDEAAAAAA==.Tahtiania:BAAANQAECgYIEAAAAA==.Talkurandis:BAAANQAECgcIEgABNQAECgcIJgAOAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn8lAAIDAAoK4R9YCQCOAgADAAoK4R9YCQCOAgAAAA==.Teo:BAABNQAECn8iAAIBAAkK7w8YlwDaAQABAAkK7w8YlwDaAQAAAA==.Terraria:BAAANQAECgEIAgABNQAECgoKOwAUAM0gAA==.Teyamat:BAAANQAECgUICQABNQAECgoKJQADAOEfAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8mAAMQAAoK7BzXHQD1AgAQAAoK7BzXHQD1AgAbAAMKqhGc9ACsAAAAAA==.Theory:BAAANQAECgUIBQAAAA==.Thetree:BAABNQAECn8nAAMIAAkKrRviFAChAgAIAAkKrRviFAChAgAHAAcK+xsvPgAHAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIIgATAO4LAA==.Thoughtcrime:BAAANQAECgcICgAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8rAAIYAAkKdRriAQBFAgAYAAkKdRriAQBFAgAAAA==.',
Ti='Timoris:BAAANQAECgYIBgABNQAECgoKLAAKAOwdAA==.',
To='Tobiume:BAAANQAECgYICgABNQAECgkJKQALAHAWAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAABNQAECn8VAAIBAAYKwQdy0QBeAQABAAYKwQdy0QBeAQAAAA==.Toodles:BAAANQADCggIEAAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgMIBwAAAA==.Trildjr:BAAANQAECgYIEAAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn8rAAIbAAgKywlsiACPAQAbAAgKywlsiACPAQAAAA==.',
Ty='Tyronda:BAAANQADCggIIwAAAA==.Tyrse:BAABNQAECn8ZAAIXAAcKJgeoBwAGAQAXAAcKJgeoBwAGAQAAAA==.',
Tz='Tzerina:BAAANQAECgUIEQAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECgcIJgAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8kAAISAAkKJRGGbQDPAQASAAkKJRGGbQDPAQAAAA==.Validan:BAAANQAECgUIBwAAAA==.Valkriss:BAAANQADCggIGQAAAA==.Vallyrie:BAABNQAECn8uAAMEAAoKxRo6FwDkAQAEAAkKfxo6FwDkAQADAAcKMRWVYwCCAQAAAA==.Valssharess:BAABNQAECn8fAAIjAAcK9x35EQCRAQAjAAcK9x35EQCRAQAAAA==.Valth:BAAANQAECgIIAwAAAA==.Valweyna:BAAANQADCgIIAgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgAOAAAAAA==.Vaporgriffin:BAAANQAECgUIDwAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgYIBwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgIIBAAAAA==.Veleria:BAABNQAECn8vAAMSAAkKehj0SwA5AgASAAkKehj0SwA5AgARAAYK5RgZKACdAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgIIBAAAAA==.',
Vi='Victra:BAABNQAECn8bAAITAAoK2wqjdQD2AAATAAoK2wqjdQD2AAAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgUIBgAAAA==.Vinaya:BAAANQAECgIIBAAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQAOAAAAAA==.',
Vo='Volthemar:BAABNQAECn8zAAMNAAkKkiFMOgDcAgANAAkKJSFMOgDcAgAdAAQK1hzaJAAfAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIIAgAAAA==.',
Wa='Wanabe:BAAANQADCgIIAgAAAA==.Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCggIDwABNQAECgcIGgAaAHoUAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn8yAAIPAAkKgggxkAAxAQAPAAkKgggxkAAxAQAAAA==.',
Wh='Whatevyr:BAAANQADCggIDwAAAA==.Whitespot:BAAANQAECgQIAwAAAA==.',
Wi='Wilson:BAAANQADCgYIBwABNQAECgcIHAACAFQhAA==.Wisegurl:BAABNQAECn8pAAMPAAoKECLJIACJAgAPAAoKmyHJIACJAgARAAUKBBYbNgB3AAAAAA==.',
Wo='Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn8oAAIHAAoK/xDnIgBtAQAHAAoK/xDnIgBtAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgQIBwAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wylecsham:BAAANQADCgUIBQAAAA==.Wylectra:BAABNQAECn83AAITAAoKchMgJABHAgATAAoKchMgJABHAgAAAA==.',
Xe='Xethos:BAAANQAECggICAAAAA==.',
Xy='Xyleeha:BAAANQADCggIGQAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn83AAMBAAoKUw2RTQC0AQABAAoKUw2RTQC0AQAcAAEKAADjogAPAAAAAA==.Yerdedmatey:BAAANQAECgIIAQAAAA==.',
Yo='Yoshikatsu:BAAANQADCggICAAAAA==.Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn86AAIQAAoKIRvSHgBNAgAQAAoKIRvSHgBNAgAAAA==.Zahvaria:BAABNQAECn8XAAIVAAcKNwbwYwDPAAAVAAcKNwbwYwDPAAAAAA==.Zamari:BAAANQADCggIGQABNQAECgcIFwAVADcGAA==.Zaphiell:BAABNQAECn8eAAIWAAkK2hWqIgAeAgAWAAkK2hWqIgAeAgAAAA==.Zazzy:BAEANQAECgIIAgABNQAFFAQIDgAcALELAA==.',
Ze='Zeid:BAABNQAECn8bAAINAAoK2g2jhAAQAgANAAoK2g2jhAAQAgAAAA==.Zev:BAAANQAECgIIBAAAAA==.',
Zi='Zillz:BAAANQAECgcIDQAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECgcIJgAOAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgEIAQAAAA==.',
Zo='Zoeystorm:BAABNQAECn8lAAMPAAYKXAjVBQEVAQAPAAYKtgfVBQEVAQARAAQKCgYBRABIAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAIDAAkKEBSYQwAMAgADAAkKEBSYQwAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAABNQAECn8vAAQBAAoKlRWvXwBYAgABAAgKWBuvXwBYAgAcAAUKjwUpMACbAAAXAAIKYwjTCwBZAAAAAA==.',
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
