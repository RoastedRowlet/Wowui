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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Priest-Holy','Priest-Discipline','Evoker-Devastation','Hunter-Marksmanship','Warrior-Protection','Monk-Windwalker','Warrior-Arms','Shaman-Elemental','Rogue-Assassination','Warrior-Fury','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acemage:BAABNQAECn8dAAIBAAoKmQ84OQBLAQABAAoKmQ84OQBLAQABNQAFFAcIIQACAHkdAA==.',
Ae='Aegon:BAABNQAECn8wAAQDAAoKdh0THwDRAgADAAkKniATHwDRAgAEAAkK9wlvMgCsAAAFAAEKEAfusgAtAAAAAA==.Aelivalor:BAAANQADCggIFAAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECn8lAAMGAAgK9B8/AgDFAQABAAcKVB41vAAMAgAGAAUKXh8/AgDFAQAAAA==.',
Ah='Ahdonis:BAAANQAECggICwAAAA==.Ahnerfays:BAAANQAECgYICQABNQAECgoKNgAHAHweAA==.',
Ai='Aiara:BAAANQAECgIIAQAAAA==.Aiarra:BAABNQAECn8pAAMIAAkKHRISQQD0AQAIAAkKHRISQQD0AQAJAAQKxAYvWgCfAAAAAA==.Aindriana:BAABNQAECn8gAAIKAAYKNgioJQDbAAAKAAYKNgioJQDbAAAAAA==.Aitra:BAABNQAECn8WAAQLAAYKUwImCgB/AAALAAYK2AEmCgB/AAAMAAUK6AFGIwF7AAANAAEKUQKfiQAVAAAAAA==.',
Aj='Ajx:BAAANQAECgUICQABNQAECgUICwAOAAAAAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECn8ZAAICAAcKUBPOkwDhAQACAAcKUBPOkwDhAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgoKJgALAIwdAA==.',
Al='Aladaris:BAAANQAECgEIAQAAAA==.Alaeryth:BAAANQAECgMIBAAAAA==.Alerothon:BAABNQAECn9AAAIHAAoKpxUeDwADAgAHAAoKpxUeDwADAgAAAA==.Alestiana:BAABNQAECn8vAAIPAAoKXRRBUgAdAgAPAAoKXRRBUgAdAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAABNQAECn8oAAIQAAkKvBRjGwATAgAQAAkKvBRjGwATAgAAAA==.Amnadores:BAABNQAECn8bAAIBAAYK9geCLgE/AQABAAYK9geCLgE/AQABNQAECgkJKQAMAHAWAA==.',
An='Andii:BAAANQAECgMIAwAAAA==.Annati:BAACNQAFFH8KAAIPAAYKgBfoCwCOAQAPAAYKgBfoCwCOAQA1AAQKfyUAAg8ACgqTIXoVACMDAA8ACgqTIXoVACMDAAAA.Antarres:BAABNQAECn8hAAIMAAkKMwcBYADCAAAMAAkKMwcBYADCAAAAAA==.',
Ao='Aoba:BAABNQAECn8tAAMQAAkKiB28FABdAgAQAAgKMhy8FABdAgARAAQKRQMgYQCTAAAAAA==.',
Ap='Apila:BAAANQADCgEIAgABNQAECgYIIAAOAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arasha:BAAANQAECggIDwAAAA==.Arathria:BAAANQADCgUIBQABNQAFFAMICQAFAJ4RAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECgoKNgAHAHweAA==.Areaman:BAAANQADCgcIEAABNQAECgcIFgABAD8fAA==.Aridam:BAAANQAECgQIBAAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisdrake:BAAANQABCgQIBAABNQADCgIIAgAOAAAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgAOAAAAAA==.Artemisshade:BAABNQAECn8hAAMSAAgKfxnUAADAAQASAAgKfxnUAADAAQATAAQKjBIcNQARAQABNQADCgIIAgAOAAAAAA==.Arthillius:BAAANQAECgIIAwAAAA==.',
As='Astro:BAAANQADCggIEAAAAA==.',
Au='Aurica:BAAANQAECgQIBAAAAA==.',
Av='Aviana:BAABNQAECn8ZAAIUAAYKEgilSQD0AAAUAAYKEgilSQD0AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Az='Azerana:BAAANQAECgEIAQAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.Barenel:BAAANQADCgEIAQAAAA==.',
Be='Beefypal:BAAANQAECgUICAAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECn8oAAMCAAcKcg+vlgDbAQACAAcKdg6vlgDbAQAVAAcK7AkNCQCyAQAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.Belle:BAAANQAECgYIBwAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bip:BAABNQAECn8ZAAMMAAkKpQ68igDMAQAMAAgKkg28igDMAQANAAIKnhFbWAB2AAAAAA==.',
Bj='Bjornmodi:BAAANQAECgIIAgAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzlock:BAAANQAECgIIAgABNQAECgoKIQAIAIgZAA==.Blitzy:BAABNQAECn8hAAIIAAoKiBlNIADKAgAIAAoKiBlNIADKAgAAAA==.',
Bo='Bobbette:BAABNQAECn8YAAQWAAcK1Q8FNAAvAQAWAAcK1Q8FNAAvAQAUAAMKlwb7YAB9AAAXAAEKnwPMMAAjAAABNQAECgoKGgAPAA4bAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Brenick:BAAANQAECgUIEAAAAA==.Brewtalize:BAAANQABCgcICQAAAA==.Bringer:BAAANQAECgQIBAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQADCgYICAAAAA==.Broseph:BAAANQABCgIIAgAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgUIBAAAAA==.Burnie:BAABNQAECn8UAAIYAAcKoxPrBABEAQAYAAcKoxPrBABEAQAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAAANQAECgcIEgAAAA==.Camilah:BAABNQAECn8cAAIDAAkK0hy6CgCQAQADAAkK0hy6CgCQAQAAAA==.Capa:BAABNQAECn8mAAQLAAoKjB1xBACUAgALAAgK9R1xBACUAgAMAAUKxhrrzgAsAQANAAMKOBeiOwDTAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECn8WAAIBAAoKkxlTmwBKAgABAAoKkxlTmwBKAgAAAA==.',
Ce='Celestiné:BAAANQAECgUICAAAAA==.Cemeteri:BAAANQADCggIDwAAAA==.',
Ch='Chaingun:BAAANQAECgYIEAAAAA==.Chaps:BAAANQAECgMIAwAAAA==.Chelseac:BAAANQAECgUIEwABNQAECgcIGQABAJMNAA==.Chilblain:BAABNQAECn8wAAIGAAgKXBNHDAD3AQAGAAgKXBNHDAD3AQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECn86AAIZAAoKsBY7CABgAQAZAAoKsBY7CABgAQAAAA==.',
Ci='Cibochevski:BAAANQADCggIDwABNQAECgcIFgAaAP0WAA==.Ciratorynth:BAABNQAECn8jAAIYAAoKHRO/EwATAgAYAAoKHRO/EwATAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECn8kAAIPAAkKhyJZDwBIAwAPAAkKhyJZDwBIAwAAAA==.',
Cl='Clearlove:BAAANQAECgQIBAABNQAECgcIGQABAJMNAA==.Clearlovec:BAAANQAECgcICAABNQAECgcIGQABAJMNAA==.Closetfurry:BAABNQAECn8bAAIHAAYK8g8BeQDWAAAHAAYK8g8BeQDWAAAAAA==.',
Co='Codenheimer:BAAANQAECgUIBgAAAA==.Condor:BAAANQAECggICwAAAA==.Corrinne:BAABNQAECn8gAAIHAAoKBBd4MABvAQAHAAoKBBd4MABvAQAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Crankk:BAAANQAECgEIAQAAAA==.Critmypänts:BAAANQAECgUIBwAAAA==.',
Cz='Czernobog:BAAANQAECggIEAAAAA==.',
Da='Daeshan:BAABNQAECn8tAAIbAAkKDBeOHgA9AgAbAAkKDBeOHgA9AgAAAA==.Dafirstone:BAAANQAECgQIBQAAAA==.Dahealamon:BAAANQAECgUIBwAAAA==.Daldolarette:BAABNQAECn8wAAIRAAoKWxxWGQATAwARAAoKWxxWGQATAwAAAA==.Daradevil:BAAANQADCgcJBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcJBwAOAAAAAA==.Daralune:BAAANQAECgMIBQAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECn8sAAMHAAkK9hZzaQBgAgAHAAkK9hZzaQBgAgAQAAEKxwQWgQAbAAAAAA==.Dasecondone:BAAANQAECgUIDAAAAA==.Dathirdone:BAAANQADCggIHwAAAA==.Dawg:BAAANQAECgYICwAAAA==.',
De='Deadlytankz:BAAANQADCgQIBAAAAA==.Deadval:BAAANQADCgYIDQAAAA==.Demonicfyre:BAECNQAFFH8KAAIBAAMKDBkgDQDyAAABAAMKDBkgDQDyAAA1AAQKfyEAAgEACgr9G5dVANUCAAEACgr9G5dVANUCAAAA.Demonstein:BAEANQAECgUIBQABNQAFFAUIDQAHAI4gAA==.Destros:BAAANQAECgUIDQAAAA==.',
Di='Disdain:BAAANQAECgYICQABNQAFFAcIIgAMAAkdAA==.',
Do='Donchap:BAAANQAECggIDgAAAA==.Donchapper:BAAANQAECggICAAAAA==.Doomsteel:BAAANQAECgIIAgABNQADCgQJBAAOAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drendak:BAAANQAECgIIAwAAAA==.Drucyllå:BAAANQADCgUIBwAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECn8rAAMDAAoKLB3OLACBAgADAAgKrB7OLACBAgAFAAcKnhjJQADEAQAAAA==.Drzip:BAAANQAECggIEAAAAA==.Drzippy:BAAANQAECgMIBQAAAA==.',
Du='Duane:BAAANQAECggIEAAAAA==.Duskthrasher:BAABNQAECn8XAAIDAAYKwQTwMACaAAADAAYKwQTwMACaAAAAAA==.Duyii:BAAANQADCgYIEAABNQAECgYIIAAOAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECn8lAAICAAkKUxZwPwCsAgACAAkKUxZwPwCsAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgUIDAAAAA==.',
Ea='Easterneon:BAAANQAECgUICgABNQAECgcIGQABAJMNAA==.',
Ec='Ech:BAABNQAECn8tAAIcAAkKthfQagBRAgAcAAkKthfQagBRAgAAAA==.',
Ei='Eiraveta:BAABNQAECn8hAAIWAAgKyg1vgACXAQAWAAgKyg1vgACXAQAAAA==.',
El='Elemental:BAABNQAECn8aAAIBAAgKsAIzPwEkAQABAAgKsAIzPwEkAQAAAA==.Elendirs:BAAANQABCgYIFQABNQABCgcIDgAOAAAAAA==.Ellois:BAAANQAECgYIDgAAAA==.Elronnd:BAAANQADCggIDwAAAA==.Elysabel:BAAANQAECgYIBgABNQAECgkJFAACACMOAA==.',
Ep='Epicnoname:BAACNQAFFH8JAAIFAAMKnhFoBgDPAAAFAAMKnhFoBgDPAAA1AAQKfyMAAgUACgrOHIUgAIkCAAUACgrOHIUgAIkCAAAA.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQAECgUIEAAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgcICAABNQAECggICAAOAAAAAA==.',
Fa='Fairlight:BAABNQAECn8ZAAIEAAcKoBlCSgDOAQAEAAcKoBlCSgDOAQABNQAECggICgAOAAAAAA==.Fave:BAAANQADCgYIBgABNQAECgcIIQAPAKMZAA==.',
Fe='Feannesse:BAAANQAECgcIEAAAAA==.Festival:BAAANQAECggICgAAAA==.',
Fi='Firebolt:BAABNQAECn8hAAMPAAcKoxnCIwBWAQAPAAcKoxnCIwBWAQAdAAMKvRAG9gCoAAAAAA==.Fitts:BAAANQAECgcIDAABNQAFFAMIBQARANEbAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHgAeAK8UAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAABNQAECn8XAAMHAAcKBgcwGgHzAAAHAAYKSQYwGgHzAAARAAQK3ASeWACoAAAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAABNQAECn8VAAICAAgKChxkWwBjAgACAAgKChxkWwBjAgAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgYIDAAOAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIDwAAAA==.',
Ga='Garekk:BAABNQAECn8UAAICAAkKIw4iggAIAgACAAkKIw4iggAIAgAAAA==.',
Gi='Gilgamésh:BAABNQAECn9KAAMFAAoKWCLLBQCEAwAFAAoKWCLLBQCEAwADAAgKURYXSwDpAQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQADCggICgAAAA==.',
Go='Golldehammer:BAAANQADCggIDwAAAA==.Goneville:BAAANQAECggICgAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAABNQAECn8YAAIPAAkKrQKgvgDsAAAPAAkKrQKgvgDsAAAAAA==.',
Gt='Gtx:BAAANQAECgUIDAAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggICAABNQAECgIIAwAOAAAAAA==.Gutworthy:BAAANQAECgUIBAAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIDgAAAA==.Hallzy:BAAANQAECgIIAwAAAA==.Hallzypal:BAAANQAECgYICAAAAA==.Hammerjane:BAAANQAECgcIEwAAAA==.Hamur:BAABNQAECn8XAAIXAAcKcBn/BgAQAgAXAAcKcBn/BgAQAgAAAA==.Hariyaki:BAABNQAECn8UAAIbAAcKqAfYHADCAAAbAAcKqAfYHADCAAAAAA==.Havebandaids:BAAANQADCgEIAQAAAA==.',
He='Heavywinner:BAABNQAECn83AAMIAAoKVxssGQD+AgAIAAoKVxssGQD+AgAJAAQKWAlsVwCqAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECn8fAAIWAAkK0STDEQA7AwAWAAkK0STDEQA7AwAAAA==.Hellmage:BAAANQADCgYIBwAAAA==.Hellsfury:BAAANQADCgYIEAAAAA==.Hellslayer:BAABNQAECn8bAAMaAAgKaRfdEQAJAgAaAAgKaRfdEQAJAgAcAAIK8AiGOAFjAAAAAA==.Hellwalker:BAAANQADCggILAAAAA==.Hellzy:BAAANQADCggIEAAAAA==.',
Hn='Hnof:BAAANQAECgEIAQABNQAFFAQICQAWAMoRAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAABNQAECn8WAAIcAAcKnQdtWADpAAAcAAcKnQdtWADpAAAAAA==.',
['Hâ']='Hârlot:BAABNQAECn8WAAIKAAcKAgwAHwADAQAKAAcKAgwAHwADAQAAAA==.',
['Hè']='Hèathen:BAAANQADCggIDwAAAA==.',
Id='Idamage:BAAANQAECgEIAQABNQAECgoKHwAcAJYbAA==.',
Ig='Igetmoney:BAAANQABCgEIAQAAAA==.',
In='Ingenii:BAAANQAECgUIBAABNQAECgoKJgALAIwdAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFH8UAAIMAAYK9hgbAwBTAQAMAAYK9hgbAwBTAQA1AAQKfxcAAgwACgqLGkVKAHQCAAwACgqLGkVKAHQCAAAA.',
It='Ithil:BAAANQADCgMIAwAAAA==.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgMIAwAAAA==.Jaestra:BAAANQADCgcIFgABNQAECgcIEwAOAAAAAA==.Jaidah:BAAANQADCggIIwAAAA==.Jaith:BAAANQAECgEIAQAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICAAOAAAAAA==.Jansôlo:BAABNQAECn8XAAMCAAgKAiJLOQC+AgACAAgKAiJLOQC+AgAZAAMKiBS8XwCnAAAAAA==.Jaratri:BAACNQAFFH8IAAIVAAMKsw3NAQCgAAAVAAMKsw3NAQCgAAA1AAQKf0IAAhUACgoHFjIBAN0BABUACgoHFjIBAN0BAAAA.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECn8dAAIBAAgKcweuEAFxAQABAAgKcweuEAFxAQAAAA==.',
Ka='Kaatu:BAAANQADCgMIAwAAAA==.Kaerovia:BAABNQAECn8hAAIRAAkKHRWITwAtAgARAAkKHRWITwAtAgAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECn8hAAIdAAoKVBW2GABdAQAdAAoKVBW2GABdAQAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICAAAAA==.Karg:BAABNQAECn8XAAIHAAgK4whN1QBxAQAHAAgK4whN1QBxAQAAAA==.Karmai:BAABNQAECn8xAAMSAAoK5h+dAADoAQASAAkKYiCdAADoAQATAAEKfhwoQwBVAAAAAA==.Kastigor:BAAANQAECgYICwABNQAFFAIIBQAKAAQSAA==.Kathine:BAAANQAECgQICwAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgcIDwAAAA==.Kazue:BAAANQAECgQIBAABNQAECgoKIAAHAAQXAA==.',
Ke='Keaa:BAAANQAECgYICgAAAA==.Kelvala:BAABNQAECn8tAAMcAAoKZyK5JgAeAwAcAAkK2SG5JgAeAwAfAAYK9iIoCwASAgAAAA==.Kelwynd:BAAANQAECgUIEAAAAA==.Kesle:BAAANQADCgUIBQAAAA==.Keä:BAABNQAECn8aAAMRAAoKgwuANAASAQARAAoKgwuANAASAQAHAAYKEQyXDQEIAQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECn8tAAIQAAkK1xchGQAtAgAQAAkK1xchGQAtAgAAAA==.Kizzs:BAAANQAECggIDgAAAA==.',
Ko='Kobesama:BAABNQAECn8hAAIcAAkKow0InQDUAQAcAAkKow0InQDUAQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECn8dAAMgAAgKCxHsCwCcAQAgAAgKCxHsCwCcAQAYAAIKWgb+NgBXAAAAAA==.Konata:BAAANQADCggIDwABNQAECgkJLQAQAIgdAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgYIIAAOAAAAAQ==.Korigan:BAAANQAECgYICwAAAA==.',
Kr='Krom:BAAANQAECgEIAQABNQAECggIGQAdANcMAA==.Kryssie:BAABNQAECn8rAAICAAkK6hQ/IACWAQACAAkK6hQ/IACWAQAAAA==.',
Ku='Kudrah:BAAANQADCgQIBAABNQAECggIEAAOAAAAAA==.Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECn8YAAIhAAcKIwgkKgAfAQAhAAcKIwgkKgAfAQAAAA==.',
['Ká']='Kárg:BAAANQADCggIBAABNQAECggIFwAHAOMIAA==.',
La='Lampard:BAAANQAECgYIBgABNQAECgkJJQAEAIAiAA==.Lanaya:BAABNQAECn8bAAIHAAgKtQ4SYAAFAQAHAAgKtQ4SYAAFAQAAAA==.Laserheadten:BAABNQAECn8lAAIUAAoKeRu0FAC9AgAUAAoKeRu0FAC9AgAAAA==.Laudna:BAAANQADCgcIBwABNQAECggICwAOAAAAAA==.Lawrensce:BAAANQAECgQIBwAAAA==.',
Le='Leanore:BAAANQADCgUIBQABNQAECgcILgAIAPUJAA==.Lencho:BAAANQAECgIIBAAAAA==.Lenchodude:BAAANQAECgUIDQAAAA==.Lenian:BAABNQAECn8WAAIaAAcK/RYBCQAkAQAaAAcK/RYBCQAkAQAAAA==.Leâfs:BAAANQAECgUIDwAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIAwAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQAECgQICwAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAAOAAAAAA==.Lourom:BAABNQAECn8ZAAMCAAkKKg0BjADyAQACAAkKFgoBjADyAQAZAAYKxgx0SwAIAQAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQADCgYIBgAAAA==.Lunariel:BAAANQAECgUICwAAAA==.',
Ly='Lyraae:BAABNQAECn8gAAIPAAcKMxIufgCRAQAPAAcKMxIufgCRAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYIFgAAAA==.Maidenofhate:BAABNQAECn86AAMCAAoKxxjJOwC3AgACAAoKxxjJOwC3AgAZAAEKswM7nAAkAAAAAA==.Maiganoss:BAAANQAECgUIDAAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgAOAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAAANQAECggIEQAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBQAAAA==.',
Me='Megid:BAABNQAECn8hAAIQAAgK7RzYFQBQAgAQAAgK7RzYFQBQAgAAAA==.Merethil:BAAANQADCgMIAwAAAA==.Mestopheles:BAABNQAECn8kAAIFAAkKKBmFJQBoAgAFAAkKKBmFJQBoAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAAANQAECgQICQABNQAECgcILgAIAPUJAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgUIBQAAAA==.Mimie:BAAANQAECggIBgAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQAECggIEgAAAA==.Mizblumkin:BAAANQAECgYIBgAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moonfizzle:BAAANQADCggIDwAAAA==.Moonnshine:BAABNQAECn8hAAMIAAkKEwV0YwBAAQAIAAkKEwV0YwBAAQAJAAYKXwIjVgCvAAAAAA==.Moonrend:BAAANQAECgUIBQAAAA==.Moonzire:BAAANQAECgUIBgAAAA==.Moradil:BAAANQADCgMIBQAAAA==.Morcathord:BAAANQADCgYIBgABNQAECgYIIAAOAAAAAQ==.',
Mu='Muradil:BAAANQADCgMIBAAAAA==.Murgrot:BAAANQADCgcIEQAAAA==.',
My='Mylittlepwni:BAAANQAECgIIAwAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcJBwAAAA==.',
Na='Nainel:BAAANQADCgcIFgABNQAECgcIFgAaAP0WAA==.Nakros:BAAANQAECgYIBwAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgcIFgABAD8fAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECgUICQAAAA==.Nerik:BAAANQAECgIIAgAAAA==.Nerissa:BAEANQAECggIEgAAAA==.Netallia:BAAANQAECgEIAQAAAA==.',
Ng='Ngyue:BAAANQADCgYIJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECn8dAAICAAcKbxq9agA+AgACAAcKbxq9agA+AgAAAA==.Nickto:BAAANQAECgUICgAAAA==.Nightshayed:BAAANQADCggIDwAAAA==.Niëtz:BAAANQAECgEIAQAAAA==.',
Nu='Nubin:BAAANQAECgMIAgAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgUICwAOAAAAAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Oa='Oaknsheild:BAAANQADCgUIBQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBwABNQAECgYIFQACAMEHAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECgUIDgAOAAAAAA==.',
Or='Orceo:BAAANQADCggIGQAAAA==.Orcrest:BAAANQAECgIIAwAAAA==.Ororo:BAABNQAECn8nAAIdAAgK1hpyRABkAgAdAAgK1hpyRABkAgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgYICgAOAAAAAA==.Paog:BAAANQADCgcIDQAAAA==.Paryah:BAABNQAECn8WAAITAAcKQwQ5KADBAAATAAcKQwQ5KADBAAAAAA==.Pauken:BAAANQAECgYICgABNQAECgoKJgALAIwdAA==.',
Ph='Phanceester:BAAANQAECgIIAwAAAA==.Phindra:BAAANQAECgMIBQAAAA==.Phonut:BAAANQADCgcIDAAAAA==.Phréek:BAABNQAECn8qAAMRAAgKzR0PFwCdAQARAAgKzR0PFwCdAQAHAAMK+xQlqACRAAAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAACNQAFFH8SAAIEAAUK1goDEgA3AQAEAAUK1goDEgA3AQA1AAQKfxsAAgQACQqDExYaAB0BAAQACQqDExYaAB0BAAAA.',
Po='Poetea:BAAANQAECgUIBgAAAA==.Portalslag:BAAANQAECgcIBwAAAA==.',
Pr='Praze:BAAANQAECgIIAwAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgAAAA==.Rahis:BAABNQAECn8rAAMCAAkKDRbnDQACAgACAAkKDRbnDQACAgAZAAEKeAOJkQAuAAAAAA==.Raiu:BAAANQAECgcIEwAAAA==.Ramsis:BAABNQAECn8aAAIPAAoKDht2RgBHAgAPAAoKDht2RgBHAgAAAA==.Randir:BAABNQAECn8yAAIUAAoKFxTLFgCkAgAUAAoKFxTLFgCkAgAAAA==.Ranir:BAAANQAECgEIAQAAAA==.Rath:BAABNQAECn8XAAIbAAcKrBlIJQD5AQAbAAcKrBlIJQD5AQAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgcIDwAAAA==.Remedivhs:BAAANQAECgEIAQABNQAECgYIIAAOAAAAAQ==.Rettbull:BAAANQADCgcIFgAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAABNQAECn8VAAIBAAYKwAfCNwEwAQABAAYKwAfCNwEwAQAAAA==.Rhyli:BAAANQADCgcIFgAAAA==.',
Ro='Robinhoodx:BAABNQAECn8sAAICAAkKYBp5QQCmAgACAAkKYBp5QQCmAgAAAA==.Rockbottom:BAAANQADCgcIEwABNQAECgcIFgAEAKsWAA==.Roenabur:BAAANQADCggIHAAAAA==.Romok:BAAANQAECgIIBQAAAA==.',
Ru='Rubysunday:BAAANQADCggIGQAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rà']='Ràyne:BAAANQADCggIGwAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECn8bAAIHAAcKzQ2v1QBwAQAHAAcKzQ2v1QBwAQAAAA==.Samoot:BAABNQAECn8uAAIIAAcK9Ql1JwDGAAAIAAcK9Ql1JwDGAAAAAA==.Sanöktevita:BAAANQADCggIDAAAAA==.Sarreus:BAAANQADCgYIDQABNQAECgYIIAAOAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAABNQAECn8WAAIMAAcKxgnEVQDXAAAMAAcKxgnEVQDXAAAAAA==.Shamanstein:BAEANQADCggJDwABNQAFFAUIDQAHAI4gAA==.Shammbo:BAAANQAECgcICQAAAA==.Sharty:BAAANQAECggIDwAAAA==.Shazra:BAAANQAECgcIDQAAAA==.Sheriruth:BAAANQAECgYIDAABNQAECgoKJgALAIwdAA==.Shortigen:BAAANQAECgIIAwAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDwAAAA==.Shuub:BAAANQAECggIBAAAAA==.',
Si='Sicnus:BAAANQADCggIEAAAAA==.Silveryl:BAAANQAECgUIDgAAAA==.Sinadin:BAABNQAECn8wAAIHAAkKyhHRmADyAQAHAAkKyhHRmADyAQAAAA==.Sindoreisins:BAAANQAECggIEQAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIIQAWAOgLAA==.Skolmaster:BAABNQAECn8VAAIBAAoKUwrmZwDtAAABAAoKUwrmZwDtAAAAAA==.Skootter:BAAANQADCgYJBwAAAA==.Skyfury:BAABNQAECn8XAAMdAAYKhxUIlgBtAQAdAAUKGREIlgBtAQAPAAYKkBUJNQAQAQABNQAECgcIIQAPAKMZAA==.Skywalkr:BAAANQADCgYICwAAAA==.',
Sm='Smarky:BAACNQAFFH8HAAIUAAQKNw3ZBADhAAAUAAQKNw3ZBADhAAA1AAQKfxQAAhQACgo4HCwOAAsDABQACgo4HCwOAAsDAAAA.Smâlls:BAEBNQAECn8WAAIiAAYKExsCBgAZAQAiAAYKExsCBgAZAQAAAA==.',
Sn='Sneekie:BAAANQABCgQIBgAAAA==.Sneekiemage:BAAANQAECgUICwAAAA==.Snugz:BAAANQAECgEIAgAAAA==.',
So='Sourdiesel:BAAANQAECgYIBwAAAA==.Southsound:BAABNQAECn8ZAAIBAAcKkw3JAQGLAQABAAcKkw3JAQGLAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQAOAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQAECgUIBQAAAA==.Steakknife:BAABNQAECn8VAAMeAAgKZhHkMQAXAgAeAAgKZhHkMQAXAgATAAYK2AViMgApAQAAAA==.Stikybandage:BAAANQADCgcIBwAAAA==.Stormoon:BAABNQAECn8bAAMPAAgKLg7+qwAZAQAPAAYKHw3+qwAZAQAdAAcKMwZRPgDPAAAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgMIAwAAAA==.',
Sy='Sybil:BAAANQAECggIEAAAAA==.',
Sz='Szer:BAAANQAECgUIBQAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAAANQAECgYIDwAAAA==.Tahtiania:BAAANQAECgYIDAAAAA==.Talkurandis:BAAANQAECgYICwABNQAECgYIIAAOAAAAAQ==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAABNQAECn8bAAIDAAkKfh0kHwDQAgADAAkKfh0kHwDQAgAAAA==.Teo:BAABNQAECn8hAAICAAgKsw8YlwDaAQACAAgKsw8YlwDaAQAAAA==.Terraria:BAAANQAECgEIAgABNQAECgoKMQASAOYfAA==.Teyamat:BAAANQAECgUICQABNQAECgkJGwADAH4dAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECn8mAAMPAAoK7BzXHQD1AgAPAAoK7BzXHQD1AgAdAAMKqhGc9ACsAAAAAA==.Thetree:BAABNQAECn8nAAMJAAkKrRviFAChAgAJAAkKrRviFAChAgAIAAcK+xsvPgAHAgAAAA==.Thien:BAAANQADCgUIBQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIIQAWAOgLAA==.Thoughtcrime:BAAANQAECgUIBwAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECn8jAAIXAAkKaBepAAAZAgAXAAkKaBepAAAZAgAAAA==.',
Ti='Timoris:BAAANQAECgQICAABNQAECgoKJgALAIwdAA==.',
To='Tobiume:BAAANQAECgYICgABNQAECgkJKQAMAHAWAA==.Tofulhundun:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAABNQAECn8VAAICAAYKwQfVaADZAAACAAYKwQfVaADZAAAAAA==.Toodles:BAAANQADCggICAAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIAQAAAA==.Triannah:BAAANQAECgMIBwAAAA==.Trildjr:BAAANQAECgYIDwAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECn8oAAIdAAgKuwlsiACPAQAdAAgKuwlsiACPAQAAAA==.',
Ty='Tyronda:BAAANQADCggIIwAAAA==.Tyrse:BAAANQAECgYIEQAAAA==.',
Tz='Tzerina:BAAANQAECgUIDAAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECgYIIAAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgYIBgAAAA==.Valford:BAABNQAECn8hAAIRAAgKlRCGbQDPAQARAAgKlRCGbQDPAQAAAA==.Validan:BAAANQAECgUIBwAAAA==.Valkriss:BAAANQADCgcIFgAAAA==.Vallyrie:BAABNQAECn8pAAMEAAoKdxgwWACSAQAEAAkKixYwWACSAQADAAcKMRWVYwCCAQAAAA==.Valssharess:BAABNQAECn8YAAIjAAYK5x5LDAA6AQAjAAYK5x5LDAA6AQAAAA==.Valth:BAAANQAECgEIAgAAAA==.Valweyna:BAAANQADCgIIAgAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQAECgEIAQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgAOAAAAAA==.Vaporgriffin:BAAANQAECgUIDgAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgMIAwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBQAAAA==.Velendez:BAAANQAECgIIAwAAAA==.Veleria:BAABNQAECn8vAAMRAAkKehj0SwA5AgARAAkKehj0SwA5AgAQAAYK5Rh4DgAiAQAAAA==.Vellysonna:BAAANQAECgEIAQAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQAECgIIAwAAAA==.',
Vi='Victra:BAABNQAECn8XAAIWAAgKyQaFnQA9AQAWAAgKyQaFnQA9AQAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgQIBQAAAA==.Vinaya:BAAANQAECgIIAwAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQAOAAAAAA==.',
Vo='Volthemar:BAABNQAECn8tAAMcAAgKKSJsEgDFAQAcAAgKQiFsEgDFAQAaAAQK1hzaJAAfAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIIAgAAAA==.',
Wa='Wanabe:BAAANQADCgIIAgAAAA==.Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCggIDwABNQAECgcIFAAYAKMTAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECn8qAAIHAAkKSAhzUAAkAQAHAAkKSAhzUAAkAQAAAA==.',
Wh='Whatevyr:BAAANQADCgYIDAAAAA==.Whitespot:BAAANQAECgMIAwAAAA==.',
Wi='Wilson:BAAANQADCgYIBwABNQAECgcIFgABAD8fAA==.Wisegurl:BAABNQAECn8gAAMHAAoKEB2CRgDBAgAHAAoKEB2CRgDBAgAQAAMK7hEpYgBVAAAAAA==.',
Wo='Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECn8iAAIIAAgK1w9yRwDOAQAIAAgK1w9yRwDOAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgQIBwAAAA==.Wrev:BAAANQADCgMIAwAAAA==.',
Wy='Wylecsham:BAAANQADCgUJBQAAAA==.Wylectra:BAABNQAECn8tAAIWAAkKDA/FcADLAQAWAAkKDA/FcADLAQAAAA==.',
Xe='Xethos:BAAANQAECggICAAAAA==.',
Xy='Xyleeha:BAAANQADCggIFgAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECn8tAAMCAAkKPQxriAD6AQACAAkKPQxriAD6AQAZAAEKAADjogAPAAAAAA==.Yerdedmatey:BAAANQAECgIIAQAAAA==.',
Yo='Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECn8wAAIPAAoKHxrSLwCiAgAPAAoKHxrSLwCiAgAAAA==.Zahvaria:BAAANQAECgYIDgAAAA==.Zamari:BAAANQADCgcIFgABNQAECgYIDgAOAAAAAA==.Zaphiell:BAABNQAECn8eAAIUAAkK2hWqIgAeAgAUAAkK2hWqIgAeAgAAAA==.Zazzy:BAEANQAECgIIAgABNQAFFAQIDgAZALELAA==.',
Ze='Zeid:BAABNQAECn8bAAIcAAoK2g2jhAAQAgAcAAoK2g2jhAAQAgAAAA==.Zev:BAAANQAECgIIAwAAAA==.',
Zi='Zillz:BAAANQAECgYICAAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECgYIIAAOAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgIIAgAAAA==.',
Zo='Zoeystorm:BAABNQAECn8gAAMHAAYKXAjVBQEVAQAHAAYKtgfVBQEVAQAQAAQKCgbRLQBSAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECn8bAAIDAAkKEBSYQwAMAgADAAkKEBSYQwAMAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAABNQAECn8sAAQCAAkKsxevXwBYAgACAAgKWBuvXwBYAgAZAAQKKAX3IwCBAAAVAAIKgQOSCgAhAAAAAA==.',
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
