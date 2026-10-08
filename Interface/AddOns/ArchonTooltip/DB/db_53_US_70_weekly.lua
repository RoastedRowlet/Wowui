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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Mage-Arcane','Mage-Frost','Paladin-Retribution','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Warlock-Affliction','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Rogue-Outlaw','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Warlock-Destruction','Hunter-Marksmanship','Evoker-Devastation','Monk-Windwalker','Paladin-Holy','Warrior-Arms','Priest-Holy','Shaman-Elemental','Rogue-Assassination','Priest-Discipline','Warrior-Fury','Evoker-Augmentation','Monk-Mistweaver','Warrior-Protection',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acemage:BAAANQAECgcIDwABNQAFFAUIFAABAAAhAA==.',
Ae='Aegon:BAABNQAECoEiAAQCAAgKVSAqJwB+AgACAAgKVSAqJwB+AgADAAcKpQn9YwBAAQAEAAEKEAcUmAAtAAAAAA==.Aelivalor:BAAANQAECgEIAgAAAA==.Aendoran:BAAANQADCggICwAAAA==.Aeon:BAAANQADCgYIBgAAAA==.Aesthelyan:BAABNQAECoEXAAMFAAcKfB5etgD0AQAFAAYKoB1etgD0AQAGAAIKjBtxJQCiAAAAAA==.',
Ah='Ahdonis:BAAANQAECgQIBgAAAA==.Ahnerfays:BAAANQAECgUICQABNQAECggIJgAHALMfAA==.',
Ai='Aiara:BAAANQAECgEIAgAAAA==.Aiarra:BAABNQAECoEeAAMIAAgKbQzWQgC9AQAIAAgKbQzWQgC9AQAJAAQKxAb+TgCgAAAAAA==.Aindriana:BAABNQAECoEUAAIKAAYKYAWtVAACAQAKAAYKYAWtVAACAQAAAA==.Aiondormi:BAAANQAECgEIAQAAAA==.Aitra:BAAANQAECgQICwAAAA==.',
Aj='Ajx:BAAANQAECgIIAwABNQAECgQICgALAAAAAA==.',
Ak='Akame:BAAANQADCggIEgAAAA==.Akashajade:BAABNQAECoEVAAIBAAYK1BFTngCXAQABAAYK1BFTngCXAQAAAA==.Akzeriyuth:BAAANQADCgEIAQABNQAECgkJGgAMAFMfAA==.',
Al='Alerothon:BAABNQAECoEuAAIHAAkKqxXLVgBpAgAHAAkKqxXLVgBpAgAAAA==.Alestiana:BAABNQAECoEoAAINAAgKRBhYRAAlAgANAAgKRBhYRAAlAgAAAA==.Alevora:BAAANQADCgIIAgAAAA==.Aluminum:BAAANQADCgQJBAAAAA==.Alycya:BAAANQABCgYIBwAAAA==.',
Am='Amephyst:BAABNQAECoEZAAIOAAcK5hmRGwDmAQAOAAcK5hmRGwDmAQAAAA==.Amnadores:BAABNQAECoEVAAIFAAUKsgZRQwH6AAAFAAUKsgZRQwH6AAABNQAECgkJIwAPABIVAA==.',
An='Annati:BAACNQAFFIEJAAINAAUKcRj3CACgAQANAAUKcRj3CACgAQA1AAQKgSAAAg0ACQqXIhcQAC0DAA0ACQqXIhcQAC0DAAAA.Antarres:BAABNQAECoEUAAIPAAgKvgR1pwBUAQAPAAgKvwR1pwBUAQAAAA==.',
Ao='Aoba:BAABNQAECoEhAAIOAAgKaxwPEQBnAgAOAAgKaxwPEQBnAgAAAA==.',
Ap='Apila:BAAANQADCgEIAgABNQAECgYIFwALAAAAAQ==.Apox:BAAANQADCgEIAQAAAA==.',
Ar='Arathria:BAAANQADCgUIBQABNQAECgkJHAAEAH0bAA==.Arcaneisbad:BAAANQAECgMIAwABNQAECggIJgAHALMfAA==.Areaman:BAAANQADCgYICQABNQAECgQICQALAAAAAA==.Aridam:BAAANQADCgcIDQAAAA==.Armagedon:BAAANQADCgUIBQAAAA==.Arovon:BAAANQADCggIDwAAAA==.Artemisixion:BAAANQADCgIIAgAAAA==.Artemisomega:BAAANQADCgEIAgABNQADCgIIAgALAAAAAA==.Artemisshade:BAABNQAECoEUAAMQAAcKwxd6CAD+AQAQAAcKwxd6CAD+AQARAAQKXRJPMAAcAQABNQADCgIIAgALAAAAAA==.Arthillius:BAAANQADCggIGwAAAA==.',
As='Asharà:BAAANQAECgEIAQAAAA==.Astro:BAAANQADCggIEAAAAA==.',
Av='Aviana:BAABNQAECoEXAAISAAUKsAu3QQD7AAASAAUKsAu3QQD7AAAAAA==.',
Ay='Aylá:BAAANQADCgQICAAAAA==.',
Ba='Baldrr:BAAANQADCgUIBQAAAA==.',
Be='Beefypal:BAAANQAECgQIBQAAAA==.Beerntotems:BAAANQADCgQJBQAAAA==.Beldar:BAABNQAECoEfAAITAAcKvQrGBwC+AQATAAcKvQrGBwC+AQAAAA==.Bellaliel:BAAANQADCgYIBgAAAA==.Bevil:BAAANQADCggIDgAAAA==.',
Bi='Bigmacker:BAAANQADCgIIAgAAAA==.Bigmoney:BAAANQAECgEIAwAAAA==.Bip:BAABNQAECoEZAAMPAAkKsQ8LdADcAQAPAAgKBA8LdADcAQAUAAIKnhHBUwB4AAAAAA==.',
Bl='Blakely:BAAANQADCgYICgAAAA==.Blitzy:BAABNQAECoEcAAIIAAgK2x7zIgCZAgAIAAgK2x7zIgCZAgAAAA==.',
Bo='Bobbette:BAAANQAECgUIDQABNQAECggIFgANAGsbAA==.Bonejovi:BAAANQAECgEIAgAAAA==.',
Br='Brenick:BAAANQAECgMIBgAAAA==.Bringer:BAAANQADCgYIDAAAAA==.Bristlegonad:BAAANQADCgEIAQAAAA==.Briçk:BAAANQADCgUIBQAAAA==.Broseph:BAAANQAECgEIAQAAAA==.Bråyden:BAAANQADCgcIEQAAAA==.',
Bu='Bubbléoseven:BAAANQADCgYIBgAAAA==.Bullgrim:BAAANQAECgQICAAAAA==.Burnie:BAAANQAECgIIBwAAAA==.Buttars:BAAANQADCgQIBAAAAA==.',
['Bò']='Bònkers:BAAANQAECgIIAwAAAA==.',
Ca='Cahae:BAAANQAECgMIAwAAAA==.Camilah:BAABNQAECoEUAAICAAgK6RfNPAAHAgACAAgK6RfNPAAHAgAAAA==.Capa:BAABNQAECoEaAAQMAAkKUx/rBQA2AgAMAAYKoSDrBQA2AgAPAAQKGx2tswA4AQAUAAMKOBdEOgDNAAAAAA==.Carcine:BAAANQADCgUIBQAAAA==.Carion:BAABNQAECoEUAAIFAAgKjhpUggBhAgAFAAgKjhpUggBhAgAAAA==.',
Ce='Celestiné:BAAANQAECgQIBQAAAA==.Cemeteri:BAAANQADCggIDAAAAA==.',
Ch='Chaingun:BAAANQAECgUICQAAAA==.Chelseac:BAAANQAECgQIDwABNQAECgcIGQAFAOARAA==.Chilblain:BAABNQAECoEhAAIGAAgKAxAxCwDaAQAGAAgKAxAxCwDaAQAAAA==.Chilchizedek:BAAANQADCgYIDwAAAA==.Chobii:BAABNQAECoEpAAIVAAkKHBUJGwBiAgAVAAkKHBUJGwBiAgAAAA==.',
Ci='Cibochevski:BAAANQADCggIDAABNQAECgQICQALAAAAAA==.Ciratorynth:BAABNQAECoEhAAIWAAgKaxVkEQAgAgAWAAgKaxVkEQAgAgAAAA==.Circumschism:BAAANQADCgYIDwAAAA==.Citrus:BAABNQAECoEkAAINAAkKhyIcCwBTAwANAAkKhyIcCwBTAwAAAA==.',
Cl='Clearlove:BAAANQAECgQIBQABNQAECgcIGQAFAOARAA==.Clearlovec:BAAANQAECgcICQABNQAECgcIGQAFAOARAA==.Closetfurry:BAAANQAECgQIDwAAAA==.',
Co='Condor:BAAANQAECgYIDAAAAA==.Corrinne:BAAANQAECgcIEwAAAA==.Cosmicmage:BAAANQADCgUIBQAAAA==.',
Cr='Critmypänts:BAAANQAECgEIAQAAAA==.',
Cz='Czernobog:BAAANQAECgYIBgAAAA==.',
Da='Daeshan:BAABNQAECoEhAAIXAAgKgRd7HAApAgAXAAgKgRd7HAApAgAAAA==.Dafirstone:BAAANQADCggIEAAAAA==.Dahealamon:BAAANQAECgUICAAAAA==.Daldolarette:BAABNQAECoEkAAIYAAkKbRfBKgCjAgAYAAkKbRfBKgCjAgAAAA==.Daradevil:BAAANQADCgcJBwAAAA==.Daralicte:BAAANQADCgUIBQABNQADCgcJBwALAAAAAA==.Daralune:BAAANQAECgMIBQAAAA==.Darcnight:BAAANQADCgEIAQAAAA==.Darkenrahll:BAAANQADCgIIAgAAAA==.Darkvaela:BAAANQADCgcIDAAAAA==.Darner:BAABNQAECoEhAAMHAAgKnxoNVQBtAgAHAAgKnxoNVQBtAgAOAAEKxwSBcQAdAAAAAA==.Dasecondone:BAAANQAECgQICgAAAA==.Dathirdone:BAAANQADCggIFwAAAA==.Dawg:BAAANQAECgMIBwAAAA==.',
De='Deadlytankz:BAAANQAECgEIAQAAAA==.Deadval:BAAANQADCgQIBwAAAA==.Demonicfyre:BAEBNQAECoEdAAIFAAkKvxxMVgDDAgAFAAkKvxxMVgDDAgAAAA==.Demonstein:BAEANQAECgUIBgABNQAFFAUIDQAHAM8YAA==.Deslarion:BAAANQAECgEIAQAAAA==.Destros:BAAANQAECgQIDAAAAA==.',
Di='Disdain:BAAANQAECgYIBwABNQAFFAcIGwAPAH0dAA==.',
Do='Donchap:BAAANQAECggIBgAAAA==.Doomsteel:BAAANQADCgQIBAABNQADCgQJBAALAAAAAA==.',
Dr='Drauger:BAAANQADCgUIBQAAAA==.Drucyllå:BAAANQADCgUIBwAAAA==.Druidson:BAAANQABCgQIBAAAAA==.Drusti:BAAANQADCggICAAAAA==.Dryageribeye:BAABNQAECoEeAAMCAAkKkx0pJwB+AgACAAcKLCApJwB+AgAEAAYK8BeAOgCmAQAAAA==.Drzip:BAAANQAECgYIBwAAAA==.Drzippy:BAAANQAECgMIBwAAAA==.',
Du='Duane:BAAANQAECgQICgAAAA==.Duskthrasher:BAAANQAECgQIDAAAAA==.Duyii:BAAANQADCgYICwABNQAECgYIFwALAAAAAQ==.',
Dw='Dwarpheus:BAAANQADCgMIAwAAAA==.',
Dy='Dyanthus:BAABNQAECoEdAAIBAAgKqhPvXwAtAgABAAgKqhPvXwAtAgAAAA==.',
['Dà']='Dàrktress:BAAANQAECgQICAAAAA==.',
Ea='Easterneon:BAAANQAECgUIDAABNQAECgcIGQAFAOARAA==.',
Ec='Ech:BAABNQAECoEhAAIZAAgKwRaUZgA8AgAZAAgKwRaUZgA8AgAAAA==.',
Ei='Eiraveta:BAABNQAECoEZAAIaAAYKJQ3OhwBFAQAaAAYKJQ3OhwBFAQAAAA==.',
El='Elemental:BAAANQAECgYIDgAAAA==.Elendirs:BAAANQABCgYIEQABNQABCgcIDgALAAAAAA==.Ellois:BAAANQAECgYIDwAAAA==.Elronnd:BAAANQADCggIDwAAAA==.',
Ep='Epicnoname:BAABNQAECoEcAAIEAAkKfRvIGgCNAgAEAAkKfRvIGgCNAgAAAA==.',
Er='Erëdor:BAAANQAECgEIAQAAAA==.',
Es='Esmerèlda:BAAANQAECgQICgAAAA==.Estherwing:BAAANQADCgMIAwAAAA==.',
Ev='Evershine:BAAANQAECgcICAAAAA==.',
Fa='Fairlight:BAABNQAECoEZAAIDAAcKbBgHQQDaAQADAAcKbBgHQQDaAQAAAA==.',
Fe='Feannesse:BAAANQAECgQIBwAAAA==.Festival:BAAANQAECgYIBwABNQAECgcIGQADAGwYAA==.',
Fi='Firebolt:BAABNQAECoEXAAMNAAUKwx3magCcAQANAAUKwx3magCcAQAbAAMKQRJu2gCqAAAAAA==.Fitts:BAAANQAECgUIBwABNQAECgkJJwAYAAUfAA==.',
Fo='Foe:BAAANQADCgcIBwABNQAECgkJHQAcAHYVAA==.',
Fr='Frags:BAAANQADCgYIBgAAAA==.Fricorith:BAAANQAECgUICwAAAA==.Frostytoot:BAAANQADCgcICgAAAA==.',
Fu='Fuuz:BAAANQAECgcIEAAAAA==.',
['Fë']='Fëhirthane:BAAANQADCgYICwABNQAECgUICwALAAAAAA==.',
['Fù']='Fùzz:BAAANQAECgcIEQAAAA==.',
Ga='Garekk:BAAANQAECgcIDwAAAA==.',
Gi='Gilgamésh:BAABNQAECoFAAAMEAAkKOCNxBACLAwAEAAkKOCNxBACLAwACAAgKQBbgSwC+AQAAAA==.Gilmore:BAAANQADCgYIBwAAAA==.',
Gl='Glenix:BAAANQAECgEIAQAAAA==.',
Go='Golldehammer:BAAANQADCggIDAAAAA==.Goneville:BAAANQAECggICAAAAA==.',
Gr='Gretorix:BAAANQADCgcIBwAAAA==.Grizzabella:BAAANQAECgYIDgAAAA==.',
Gt='Gtx:BAAANQAECgQICwAAAA==.',
Gu='Guias:BAAANQADCgEIAQAAAA==.Gutrine:BAAANQADCggICAABNQAECgIIAwALAAAAAA==.Gutworthy:BAAANQAECgQIAgAAAA==.',
Ha='Hairykrishna:BAAANQAECgEIAQAAAA==.Haldevarik:BAAANQADCgYJCAAAAA==.Hallzofhell:BAAANQAECgUIEQAAAA==.Hallzy:BAAANQAECgEIAQAAAA==.Hallzypal:BAAANQAECgQIBAAAAA==.Hammerjane:BAAANQAECgQICQAAAA==.Hamur:BAABNQAECoEVAAIdAAcKzxctBwDyAQAdAAcKzxctBwDyAQAAAA==.Hariyaki:BAAANQAECgIIBwAAAA==.Havebandaids:BAAANQABCgYICAAAAA==.',
He='Heavywinner:BAABNQAECoEsAAMIAAkK3huLGQDhAgAIAAkK3huLGQDhAgAJAAQKWAmGTACrAAAAAA==.Hecûba:BAAANQABCgQICAAAAA==.Hedoniist:BAABNQAECoEZAAIaAAgKTCJ5FAAVAwAaAAgKTCJ5FAAVAwAAAA==.Hellsfury:BAAANQAECgEIAQAAAA==.Hellslayer:BAAANQAECgUIDwAAAA==.Hellwalker:BAAANQADCggIHAAAAA==.Hellzy:BAAANQADCggIEAAAAA==.',
Hu='Hubbabubbá:BAAANQADCgcIBwAAAA==.Hughmann:BAAANQAECgQICQAAAA==.',
['Hâ']='Hârlot:BAAANQAECgQICQAAAA==.',
['Hè']='Hèathen:BAAANQADCggIDAAAAA==.',
In='Ingenii:BAAANQAECgQIBAABNQAECgkJGgAMAFMfAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.Isllwyn:BAAANQADCgMIAwAAAA==.Isummonyou:BAACNQAFFIENAAIPAAUKtBSpCwCIAQAPAAUKtBSpCwCIAQA1AAQKgRYAAg8ACQpIGZ04AI8CAA8ACQpIGZ04AI8CAAAA.',
Ja='Jace:BAAANQABCgYICAAAAA==.Jadeth:BAAANQAECgEIAQAAAA==.Jaestra:BAAANQADCgYICQABNQAECgQICQALAAAAAA==.Jaidah:BAAANQADCggIIQAAAA==.Jaith:BAAANQAECgEIAwAAAA==.Jamaicann:BAAANQADCgYIBgABNQAECgQICwALAAAAAA==.Jansôlo:BAABNQAECoEXAAMBAAgKQCIJKADYAgABAAgKQCIJKADYAgAVAAMKGRWQVACsAAAAAA==.Jaratri:BAABNQAECoEzAAITAAkK3RphAgD/AgATAAkK3RphAgD/AgAAAA==.',
Je='Jeka:BAAANQADCgUIDAAAAA==.Jenton:BAABNQAECoEUAAIFAAYKBgciHQE1AQAFAAYKBgciHQE1AQAAAA==.',
Ka='Kaatu:BAAANQADCgMIAwAAAA==.Kaerovia:BAABNQAECoEaAAIYAAgKvxAbXQDeAQAYAAgKvxAbXQDeAQAAAA==.Kaisen:BAAANQADCgUICwAAAA==.Kalsidious:BAAANQADCgcICAAAAA==.Kamthesham:BAABNQAECoEUAAIbAAkKbRSnOABtAgAbAAkKbRSnOABtAgAAAA==.Kanchome:BAAANQADCgYIBgAAAA==.Kaneki:BAAANQAECgYICQAAAA==.Karg:BAABNQAECoEUAAIHAAcKlwcozQBHAQAHAAcKlwcozQBHAQAAAA==.Karmai:BAABNQAECoEiAAIQAAcKayIjBAC9AgAQAAcKayIjBAC9AgAAAA==.Kastigor:BAAANQAECgUIBQABNQAECgkJJgAKAK8WAA==.Kathine:BAAANQAECgQIBwAAAA==.Kaylee:BAAANQADCgcIBwAAAA==.Kayliey:BAAANQAECgYICwAAAA==.',
Ke='Keaa:BAAANQAECgYIBgAAAA==.Kelvala:BAABNQAECoEmAAMZAAkKxSN3IwAcAwAZAAkKzyF3IwAcAwAeAAUKUCU+CQAeAgAAAA==.Kelwynd:BAAANQAECgUIBwAAAA==.Keä:BAAANQAECgcIEQAAAA==.',
Kh='Khasaziel:BAAANQADCgcIBwAAAA==.',
Ki='Kirean:BAABNQAECoEhAAIOAAgKoBhAFwAYAgAOAAgKoBhAFwAYAgAAAA==.',
Ko='Kobesama:BAABNQAECoEdAAIZAAgKFA8EhQDqAQAZAAgKFA8EhQDqAQAAAA==.Kodask:BAAANQADCgYICwAAAA==.Kodera:BAABNQAECoEZAAMfAAcKshGaCgCZAQAfAAcKshGaCgCZAQAWAAIKWgZWMgBcAAAAAA==.Konata:BAAANQADCggIDwABNQAECggIIQAOAGscAA==.Korbenzoo:BAAANQADCgMIBAABNQAECgYIFwALAAAAAQ==.Korigan:BAAANQAECgUIBQAAAA==.',
Kr='Krom:BAAANQADCggIDwABNQAECggIEwALAAAAAA==.Kryssie:BAABNQAECoEcAAIBAAgKNRSwXwAuAgABAAgKNRSwXwAuAgAAAA==.',
Ku='Kuroku:BAAANQADCgUIBQAAAA==.',
Kw='Kwaili:BAABNQAECoEYAAIgAAcKIwhuJQAkAQAgAAcKIwhuJQAkAQAAAA==.',
La='Lanaya:BAAANQAECgUIDAAAAA==.Laserheadten:BAABNQAECoEgAAISAAkKBBt/EwCuAgASAAkKBBt/EwCuAgAAAA==.Laudna:BAAANQADCgcIBwABNQAECgQIBgALAAAAAA==.Lawrensce:BAAANQAECgQIDAAAAA==.',
Le='Leanore:BAAANQAECgEIAgABNQAECgcIIQAIAJoGAA==.Lencho:BAAANQAECgIIBgAAAA==.Lenchodude:BAAANQAECgQIBwAAAA==.Lenian:BAAANQAECgQICQAAAA==.Leâfs:BAAANQAECgUIDAAAAA==.',
Li='Lirrael:BAAANQADCgEIAQAAAA==.Litesout:BAAANQAECgMIBAAAAA==.',
Lo='Loghyn:BAAANQAECgIIAgAAAA==.Loreck:BAAANQAECgQIBwAAAA==.Lorlea:BAAANQADCgMIAwABNQADCgQJBAALAAAAAA==.Lourom:BAAANQAECgcIDwAAAA==.',
Lu='Luminaria:BAAANQAECgEIAQAAAA==.Lunarcateyes:BAAANQAECgEIAQAAAA==.Lunariel:BAAANQAECgQICgAAAA==.',
Ly='Lyraae:BAABNQAECoEZAAINAAYKvhILhABTAQANAAYKvhILhABTAQAAAA==.',
Ma='Mackas:BAAANQADCgYICAAAAA==.Magicbeer:BAAANQADCgYIEAAAAA==.Maidenofhate:BAABNQAECoEuAAIBAAkKPhkwMQC3AgABAAkKPhkwMQC3AgAAAA==.Maiganoss:BAAANQAECgUIAwAAAA==.Mardon:BAAANQABCgYICwABNQABCgcIDgALAAAAAA==.Marsiel:BAAANQADCgcIDgAAAA==.Maxxwell:BAAANQAECgYIDwAAAA==.',
Mc='Mcpunch:BAAANQAECgIIBAAAAA==.',
Me='Megid:BAABNQAECoEZAAIOAAYKMR77GgDtAQAOAAYKMR77GgDtAQAAAA==.Mestopheles:BAABNQAECoEYAAIEAAkKoBUQJgAzAgAEAAkKoBUQJgAzAgAAAA==.Mexicanpizza:BAAANQADCgQIBQAAAA==.Mezsiah:BAAANQAECgMICQABNQAECgcIIQAIAJoGAA==.',
Mi='Midianite:BAAANQADCgMIAwAAAA==.Mimey:BAAANQAECgEIAgAAAA==.Mimie:BAAANQAECgUIBAAAAA==.Mimiru:BAAANQADCgYIBgAAAA==.Minié:BAAANQAECgUIBgAAAA==.Mizblumkin:BAAANQAECgMIBQAAAA==.',
Mo='Monkies:BAAANQADCggIDQAAAA==.Montey:BAAANQADCgMIAwAAAA==.Moogyver:BAAANQAECgEIAQAAAA==.Moonfizzle:BAAANQAECgEIAgAAAA==.Moonnshine:BAABNQAECoEaAAMIAAgKIAWYXAA2AQAIAAgKIAWYXAA2AQAJAAYKXwINSwCyAAAAAA==.Moonrend:BAAANQAECgEIAgAAAA==.Moonzire:BAAANQAECgEIAwAAAA==.Moradil:BAAANQADCgMIBQAAAA==.',
Mu='Muradil:BAAANQAECgEIAQAAAA==.Murgrot:BAAANQADCgcICgAAAA==.',
My='Mylittlepwni:BAAANQADCgcIGAAAAA==.',
['Mä']='Mälcharion:BAAANQADCgcJBwAAAA==.',
Na='Nainel:BAAANQADCgYICQABNQAECgQICQALAAAAAA==.Nakros:BAAANQAECgUJBgAAAA==.Nathelezet:BAAANQADCgQJBAABNQAECgQICQALAAAAAA==.',
Ne='Neloria:BAAANQADCgEIAQAAAA==.Nemonas:BAAANQAECgUIBQAAAA==.Nerik:BAAANQADCgcIDQAAAA==.Nerissa:BAEANQAECggICgAAAA==.Netallia:BAAANQAECgEIAQAAAA==.',
Ng='Ngyue:BAAANQADCgYJJAAAAA==.',
Ni='Niala:BAAANQADCgUIBQAAAA==.Nianna:BAABNQAECoEWAAIBAAYK+xf9jgC6AQABAAYK+xf9jgC6AQAAAA==.Nickto:BAAANQAECgMICQAAAA==.Nightshayed:BAAANQADCggIDAAAAA==.Niëtz:BAAANQAECgEIBAAAAA==.',
Nr='Nrm:BAAANQAECgEIBAAAAA==.',
Nu='Nubin:BAAANQAECgEIAQAAAA==.Numbed:BAAANQADCggICAAAAA==.',
Ny='Nymbis:BAAANQADCgMIAwABNQAECgQICgALAAAAAA==.Nytwalker:BAAANQAECgMIAwAAAA==.Nyårlåthôtêp:BAAANQAECgEJAQAAAA==.',
Og='Ogbruced:BAAANQADCgYIBQABNQAECgUICwALAAAAAA==.',
Op='Opalla:BAAANQADCggIHAABNQAECgUIBQALAAAAAA==.',
Or='Orceo:BAAANQADCggIGQAAAA==.Orcrest:BAAANQADCggIGgAAAA==.Ororo:BAABNQAECoEkAAIbAAgKrRcjQwA+AgAbAAgKrRcjQwA+AgAAAA==.',
Pa='Palal:BAAANQADCgcIBwABNQAECgUIBwALAAAAAA==.Paog:BAAANQADCgYIBgAAAA==.Paryah:BAAANQAECgQICQAAAA==.Pauken:BAAANQAECgUIDAABNQAECgkJGgAMAFMfAA==.',
Ph='Phanceester:BAAANQADCggIFgAAAA==.Phindra:BAAANQAECgMIAwAAAA==.Phréek:BAABNQAECoEcAAMYAAgK/hxBJQC9AgAYAAgK/hxBJQC9AgAHAAIKFhRiOQGBAAAAAA==.',
Pl='Plants:BAAANQAECgMIAwAAAA==.Plethknight:BAAANQAFFAEIAQABNQAFFAQIFAAOABELAA==.',
Po='Poetea:BAAANQADCgEIAQAAAA==.',
Pr='Praze:BAAANQADCggIGwAAAA==.',
Pu='Puogh:BAAANQABCgIIAgAAAA==.Puoh:BAAANQABCgYIBwAAAA==.Pustülio:BAAANQADCggICAAAAA==.',
Pw='Pwough:BAAANQABCggICwAAAA==.',
Ra='Raeztharion:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYIBgAAAA==.Rahis:BAABNQAECoEcAAMBAAgK9hJ2XgAxAgABAAgK9hJ2XgAxAgAVAAEKeAMVfwAxAAAAAA==.Raiu:BAAANQAECgQICQAAAA==.Ramsis:BAABNQAECoEWAAINAAgKaxuwOABVAgANAAgKaxuwOABVAgAAAA==.Randir:BAABNQAECoElAAISAAkKYRVKGABuAgASAAkKYRVKGABuAgAAAA==.Ranir:BAAANQADCggIFQAAAA==.Rath:BAAANQAECgUIDwAAAA==.',
Re='Rebarka:BAAANQAECgEIAQAAAA==.Rebrewke:BAAANQAECgMIBwAAAA==.Remedivhs:BAAANQADCgEJAQABNQAECgYIFwALAAAAAQ==.Rettbull:BAAANQADCgYICQAAAA==.Revy:BAAANQAECgQIBAAAAA==.',
Rh='Rhiannonage:BAAANQAECgQIDwAAAA==.Rhyli:BAAANQADCgYICQAAAA==.',
Ro='Robinhoodx:BAABNQAECoEgAAIBAAgKbRyePQCNAgABAAgKbRyePQCNAgAAAA==.Rockbottom:BAAANQADCgYIBgABNQAECgQICQALAAAAAA==.Roenabur:BAAANQADCggIDAAAAA==.Romok:BAAANQAECgIIBAAAAA==.',
Ru='Rubysunday:BAAANQAECgEIAgAAAA==.',
Ry='Rykarranger:BAAANQADCgQIBAAAAA==.',
['Rì']='Rìseandemìse:BAAANQABCgEIAQAAAA==.',
Sa='Sacrìfice:BAABNQAECoEXAAIHAAcK3A3ttAB8AQAHAAcK3A3ttAB8AQAAAA==.Samoot:BAABNQAECoEhAAIIAAcKmgb4XQAwAQAIAAcKmgb4XQAwAQAAAA==.Sanöktevita:BAAANQADCgQIBAAAAA==.Sarreus:BAAANQADCgYIDQABNQAECgYIFwALAAAAAQ==.',
Se='Sepharim:BAAANQADCgQIBwAAAA==.',
Sh='Shael:BAAANQAECgQICQAAAA==.Shamanstein:BAEANQADCggJDwABNQAFFAUIDQAHAM8YAA==.Shammbo:BAAANQAECgUICAABNQAECgcIEAALAAAAAA==.Sharty:BAAANQAECggIDwAAAA==.Shazra:BAAANQAECgcICAAAAA==.Sheriruth:BAAANQADCggICAABNQAECgkJGgAMAFMfAA==.Shortigen:BAAANQAECgEIAQAAAA==.Shrilynda:BAAANQADCgUIBwAAAA==.Shupala:BAAANQAECggIDAAAAA==.',
Si='Sicnus:BAAANQADCgcICQAAAA==.Silveryl:BAAANQAECgUIBQAAAA==.Sinadin:BAABNQAECoEkAAIHAAgK7RGViQDgAQAHAAgK7RGViQDgAQAAAA==.Sindoreisins:BAAANQAECgYIBwAAAA==.',
Sk='Skiltroth:BAAANQADCgYIBgABNQAECggIGgAaANoJAA==.Skolmaster:BAAANQAECgQIBwAAAA==.Skootter:BAAANQAECgEIAgAAAA==.Skyfury:BAAANQAECgQIDgABNQAECgUIFwANAMMdAA==.',
Sm='Smarky:BAAANQAFFAEIAQAAAA==.Smâlls:BAEANQAECgQIDQAAAA==.',
Sn='Sneekie:BAAANQAECgEIAQAAAA==.Sneekiemage:BAAANQAECgQIBQAAAA==.Snugz:BAAANQADCggICAAAAA==.',
So='Sourdiesel:BAAANQAECgEIAQAAAA==.Southsound:BAABNQAECoEZAAIFAAcK4BF+4wCbAQAFAAcK4BF+4wCbAQAAAA==.',
Sp='Spewak:BAAANQAECgQIBAABNQAECgEIAQALAAAAAA==.',
St='Stallos:BAAANQADCgQIBAAAAA==.Stark:BAAANQADCggJDAAAAA==.Starmie:BAAANQADCgcIBwAAAA==.Steakknife:BAAANQAECgcIEwAAAA==.Stormoon:BAAANQAECgYIEQAAAA==.Sturma:BAAANQAECgQICQAAAA==.',
Su='Subwufer:BAAANQADCgEIAQAAAA==.Superrad:BAAANQAECgEIAQAAAA==.',
Sw='Swayla:BAAANQADCgUIBwAAAA==.Sweatyhog:BAAANQAECgMIBAAAAA==.',
Sy='Sybil:BAAANQAECgUICQAAAA==.Sylvarus:BAAANQAECgEIAQAAAA==.',
Sz='Szer:BAAANQAECgUIBgAAAA==.',
['Sà']='Sàlvage:BAAANQADCggICAAAAA==.',
['Sí']='Sínner:BAAANQADCgIIAgAAAA==.',
Ta='Tahfyn:BAAANQAECgIIBwAAAA==.Tahtiania:BAAANQAECgIIAwAAAA==.Tamarin:BAAANQADCgEIAQAAAA==.Tasdarazen:BAAANQADCgYIDAAAAA==.Tazedtilblue:BAAANQADCgYIFAAAAA==.',
Te='Ted:BAAANQAECggIAgAAAA==.Telysse:BAAANQAECgcIDwAAAA==.Teo:BAABNQAECoEZAAIBAAYKcg7qqQB+AQABAAYKcg7qqQB+AQAAAA==.Teyamat:BAAANQAECgUICwABNQAECgcIDwALAAAAAA==.',
Th='Thalumind:BAAANQADCgYICgAAAA==.Thelock:BAABNQAECoEfAAMNAAkKnRodJwCnAgANAAkKnRodJwCnAgAbAAMKbBCN2QCsAAAAAA==.Thetree:BAABNQAECoEnAAMJAAkKrRuGEAC0AgAJAAkKrRuGEAC0AgAIAAcKEhwlNgARAgAAAA==.Thien:BAAANQAECgEIAQAAAA==.Thoinus:BAAANQAECgEIAQABNQAECggIGgAaANoJAA==.Thoughtcrime:BAAANQAECgEIAQAAAA==.Thundertaco:BAAANQADCggICAAAAA==.Thundertwig:BAABNQAECoEUAAIdAAcKlBlPBgASAgAdAAcKlBlPBgASAgAAAA==.',
Ti='Timoris:BAAANQAECgIIAgABNQAECgkJGgAMAFMfAA==.',
To='Tobiume:BAAANQAECgMIBwABNQAECgkJIwAPABIVAA==.Tofulhundun:BAAANQAECgEIAgAAAA==.Toggo:BAAANQAECgEIAQAAAA==.Tommytwotusk:BAAANQAECgUICwAAAA==.',
Tr='Traladin:BAAANQAECgEIAQAAAA==.Trenon:BAAANQAECgEIBgAAAA==.Triannah:BAAANQAECgMICgAAAA==.Trildjr:BAAANQAECgMICAAAAA==.',
Tu='Tuchmi:BAAANQADCgYIBgAAAA==.Tuldag:BAABNQAECoEiAAIbAAgK5QXahQBlAQAbAAgK5QXahQBlAQAAAA==.',
Ty='Tyronda:BAAANQADCggIGwAAAA==.Tyrse:BAAANQAECgQICwAAAA==.',
Tz='Tzerina:BAAANQAECgMICAAAAA==.',
['Tâ']='Tânkyû:BAAANQADCgUIBQAAAA==.',
['Tï']='Tïmbits:BAAANQAECgIIAwAAAA==.',
Ut='Uthadravis:BAAANQAECgYIFwAAAQ==.',
Va='Vaelwyn:BAAANQADCggIDgAAAA==.Valegion:BAAANQADCgMJAwAAAA==.Valerina:BAAANQADCgQJBAAAAA==.Valford:BAABNQAECoEXAAIYAAcKWhGkbwChAQAYAAcKWhGkbwChAQAAAA==.Validan:BAAANQAECgIIAwAAAA==.Valkriss:BAAANQADCgYICQAAAA==.Vallyrie:BAABNQAECoEnAAMDAAgKqBQLTQCiAQADAAcKaRILTQCiAQACAAcK1xNFWQCEAQAAAA==.Valssharess:BAAANQAECgQIDQAAAA==.Valth:BAAANQADCggIGwAAAA==.Valzen:BAAANQADCgEIAQAAAA==.Vanae:BAAANQADCgUJBQAAAA==.Vanargandr:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Vaporgriffin:BAAANQAECgQIBQAAAA==.Vaporhunt:BAAANQADCgIIAgAAAA==.Varthric:BAAANQADCgMIAwAAAA==.',
Ve='Velaryia:BAAANQADCgQIBAAAAA==.Velendez:BAAANQADCggIFwAAAA==.Veleria:BAABNQAECoEgAAMYAAgKqBh3PwBJAgAYAAgKqBh3PwBJAgAOAAUKtBY2LQBJAQAAAA==.Vellysonna:BAAANQAECgEIAgAAAA==.Ventessa:BAAANQADCgYICgAAAA==.Versatina:BAAANQADCggIGQAAAA==.',
Vi='Victra:BAAANQAECgYIDwAAAA==.Viirnald:BAEANQADCgcIDQAAAA==.Vikingbeast:BAAANQABCgUJBgAAAA==.Viko:BAAANQAECgQIBgAAAA==.Vinaya:BAAANQADCggIGwAAAA==.Vindicta:BAAANQAECgEIAQABNQADCgEIAQALAAAAAA==.',
Vo='Volthemar:BAABNQAECoEjAAMZAAgK6iHCNADYAgAZAAgKRiDCNADYAgAhAAQK1hx3HwAoAQAAAA==.Voodoopunch:BAAANQABCgUIBwAAAA==.',
Vy='Vynll:BAAANQADCgIJAgAAAA==.',
Wa='Warrpath:BAAANQADCgEIAQAAAA==.Watsuki:BAAANQADCggIDAABNQAECgIIBwALAAAAAA==.',
We='Weoo:BAAANQAECgEIAQAAAA==.Werrick:BAABNQAECoEbAAIHAAcKvAfAzABIAQAHAAcKvAfAzABIAQAAAA==.',
Wh='Whatevyr:BAAANQADCgYIBgAAAA==.Whitespot:BAAANQAECgEIAQAAAA==.',
Wi='Wilson:BAAANQADCgYIBAABNQAECgQICQALAAAAAA==.Wisegurl:BAABNQAECoEUAAMHAAkKrBkSUQB5AgAHAAkKrBkSUQB5AgAOAAIKNRDaVQBZAAAAAA==.',
Wo='Wog:BAAANQADCgUIBQAAAA==.Woodpecker:BAABNQAECoEdAAIIAAgKThA5PwDVAQAIAAgKThA5PwDVAQAAAA==.',
Wr='Wraxilian:BAAANQADCgUIBQAAAA==.Wreckreation:BAAANQAECgMICgAAAA==.',
Wy='Wylecsham:BAAANQADCgUJBQAAAA==.Wylectra:BAABNQAECoEhAAIaAAgKMQ1raACxAQAaAAgKMQ1raACxAQAAAA==.',
Xe='Xethos:BAAANQADCgQIBAAAAA==.',
Xy='Xyleeha:BAAANQADCggIBgAAAA==.',
Ya='Yanikå:BAAANQADCgQICAAAAA==.',
Ye='Yeira:BAABNQAECoEiAAMBAAgKfg2JcgD+AQABAAgKfg2JcgD+AQAVAAEKWgDmjQAPAAAAAA==.Yerdedmatey:BAAANQAECgEIAgAAAA==.',
Yo='Yourdemon:BAAANQAECgIIAgAAAA==.',
Za='Zagasham:BAABNQAECoEiAAINAAgKqRuMOQBRAgANAAgKqRuMOQBRAgAAAA==.Zahvaria:BAAANQAECgIIBgAAAA==.Zalson:BAAANQAECgEIAQAAAA==.Zamari:BAAANQADCgYICQABNQAECgIIBgALAAAAAA==.Zaphiell:BAABNQAECoEYAAISAAgKWRQpIAASAgASAAgKWRQpIAASAgAAAA==.',
Ze='Zeid:BAABNQAECoEaAAIZAAkKCRA+bwAlAgAZAAkKCRA+bwAlAgAAAA==.Zev:BAAANQADCggIGgAAAA==.',
Zi='Zillz:BAAANQAECgEIAQAAAA==.Zinderalanot:BAAANQAECgYIFAABNQAECgYIFwALAAAAAQ==.',
Zl='Zlightnin:BAAANQAECgEIAQAAAA==.',
Zo='Zoeystorm:BAABNQAECoEWAAMHAAUKQwftCwHTAAAHAAUKQwftCwHTAAAOAAEKKgyyaQAmAAAAAA==.Zoeythunder:BAAANQABCgYICwAAAA==.',
Zu='Zuldrak:BAABNQAECoEbAAICAAkKpRNnOgAUAgACAAkKpRNnOgAUAgAAAA==.',
Zy='Zykie:BAAANQADCgcIBwAAAA==.',
['Ìn']='Ìnferior:BAAANQADCgYIBgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgYIBgAAAA==.',
['Öm']='Ömenjr:BAABNQAECoEfAAQBAAgKhReMUABWAgABAAgKhReMUABWAgAVAAIK8AZ+agBfAAATAAEKKwWkEgAmAAAAAA==.',
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
