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

local lookup = {'Evoker-Preservation','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Paladin-Holy','Druid-Restoration','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Mage-Frost','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Arcane','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Assassination','Druid-Guardian',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abnee:BAAANQAECgEIAQAAAA==.',
Ad='Adowyrm:BAACNQAFFH8SAAIBAAcK0hMLBwDhAQABAAcK0hMLBwDhAQA1AAQKfycAAgEACgrVH2wIAB0DAAEACgrVH2wIAB0DAAAA.Adrielle:BAAANQAECgYICgAAAA==.',
Ai='Airali:BAABNQAECn8sAAICAAoKQQ9PjAANAgACAAoKQQ9PjAANAgAAAA==.Airedale:BAABNQAECn8YAAIDAAYKHQ5vuwCNAQADAAYKHQ5vuwCNAQAAAA==.',
Ak='Akairo:BAACNQAFFH8bAAIEAAYKBSBXBgAzAgAEAAYKBSBXBgAzAgA1AAQKfzkABAQACgr1IyIHAIwDAAQACgr1IyIHAIwDAAUABAqKGFNGAAcBAAYAAQo1AQYzABoAAAAA.',
Al='Alexanderlx:BAABNQAECn8hAAMHAAcKiRsnFgBNAgAHAAYKUiInFgBNAgACAAQKPwtfswCCAAAAAA==.Aleybobwa:BAABNQAECn8nAAMIAAoKpB2qHAABAwAIAAoKpB2qHAABAwACAAUKWhOGAQEdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn8rAAMJAAkKWB/iAwBGAgAJAAkKWB/iAwBGAgAKAAEKpwQXtwAqAAAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn87AAMLAAoKBx1yAAB4AgALAAoKZBxyAAB4AgAMAAMKLRPsKwDFAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgQIBQANAAAAAA==.',
Ao='Aolus:BAABNQAECn8zAAIKAAoKERxMGQD9AgAKAAoKERxMGQD9AgAAAA==.',
Ap='Apoliis:BAAANQAECgUICgAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQADCgcIAgAAAA==.Archis:BAABNQAECn8mAAMOAAoKgxVpZABhAgAOAAoKgxVpZABhAgAPAAYKIgjeJgAKAQAAAA==.Arcidaes:BAEBNQAECn8hAAIQAAgK0QzOFQA4AQAQAAgK0QzOFQA4AQAAAA==.Arez:BAAANQADCgEJAQABNQAECggIGAARAOEIAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAABNQAECn8UAAISAAgKahJ6BADBAQASAAgKahJ6BADBAQAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Av='Avaline:BAAANQAECgEIAQAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8KAAMTAAUKZBvLBAAHAQATAAUKZBvLBAAHAQAUAAIK6wvDAgCQAAA1AAQKfyQAAxQACQp/I/oBAFADABQACQpHIvoBAFADABMABQpSImgXACIBAAAA.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azaelleonoc:BAAANQABCgQIBAAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUIBQABNQAECgoKLwAVAA0eAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgYIEAAAAA==.Baliw:BAABNQAECn8lAAIKAAkK/Q0dPAAUAgAKAAkK/Q0dPAAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgcIEQAAAA==.Banugg:BAAANQADCgMIAwAAAA==.Barcode:BAAANQADCgIIAgAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8JAAIWAAYKpQpdDwB5AQAWAAYKpQpdDwB5AQA1AAQKfysAAhYACgo3G9ghAAIDABYACgo3G9ghAAIDAAAA.',
Bc='Bchung:BAABNQAECn8xAAMRAAoKJx06BQDDAgARAAoKJx06BQDDAgAXAAgKMxYzswAdAgAAAA==.',
Be='Bela:BAAANQAECgIIAgAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECggIFAASAGoSAA==.Bertus:BAACNQAFFH8YAAMYAAYKVyWUAQBaAgAYAAYKVyWUAQBaAgAZAAQK8yE3CgBuAQA1AAQKfyYAAxkACgqWJbcUABMDABkACQpGJbcUABMDABgACAoUJM4gAIcCAAAA.',
Bh='Bhain:BAABNQAECn8fAAIWAAkKYRw6LADNAgAWAAkKYRw6LADNAgABNQAFFAMIAwANAAAAAA==.',
Bi='Bieorne:BAABNQAECn8ZAAIZAAgKjRbbCQCaAQAZAAgKjRbbCQCaAQAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAgAAAA==.Boku:BAAANQAECgQIBAAAAA==.Boodidy:BAAANQADCgUIBQAAAA==.Boondocks:BAABNQAECn8tAAQaAAkKdROvEAC+AQAaAAgKdROvEAC+AQAbAAMKoREQFwDZAAAcAAEKlAWlgQAqAAAAAA==.Bottomx:BAABNQAECn8gAAIMAAkKDQnYFwDMAQAMAAkKDQnYFwDMAQAAAA==.',
Br='Braca:BAABNQAECn8dAAMdAAgKoRgbFwALAgAdAAgKoRgbFwALAgAeAAEKAADhaQA4AAAAAA==.Bread:BAAANQADCggIEwAAAA==.Brielle:BAABNQAECn8pAAIDAAkKIBDrMQBbAQADAAkKIBDrMQBbAQAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgUIDAAAAA==.Brudene:BAABNQAECn8eAAIOAAgKfQoUPgAoAQAOAAgKfQoUPgAoAQABNQAECggIMQAXAG4SAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIBQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwANAAAAAA==.Bullymaguire:BAAANQAECgYIBgABNQAFFAcIEAAWAJEdAA==.',
Ca='Carpe:BAAANQAECgUICgAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn85AAIOAAoKqhXACwAGAgAOAAoKqhXACwAGAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFH8eAAIOAAcKZCJ6AQDgAQAOAAcKZCJ6AQDgAQA1AAQKfzEAAg4ACgqbJgIHALsDAA4ACgqbJgIHALsDAAAA.Checkurback:BAAANQAECggIDwAAAA==.Chewtum:BAAANQAECgUICAAAAA==.Chimo:BAABNQAECn8gAAIfAAcKjAv9LgAnAQAfAAcKjAv9LgAnAQAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgoKLwAXALQdAA==.',
Cl='Cleavatron:BAAANQAECgIIAwABNQADCgcIBwANAAAAAA==.',
Co='Cobellex:BAAANQAECgEIAQAAAA==.Cops:BAABNQAECn8pAAIIAAgKYR4lKQDEAgAIAAgKYR4lKQDEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgQIDQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgcIEQANAAAAAA==.Darkenergy:BAABNQAECn8tAAIgAAkKRx5YBAAnAgAgAAkKRx5YBAAnAgAAAA==.Darà:BAAANQADCgcIBwABNQAECgcIHQAJANEPAA==.Dashyll:BAAANQAECgUICgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAABNQAECn8eAAIDAAcKCh1GPwA4AQADAAcKCh1GPwA4AQAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgoKLwAVAA0eAA==.Demacus:BAAANQAECggIDwAAAA==.Demeter:BAABNQAECn8jAAIHAAcKfRJtDAA6AQAHAAcKfRJtDAA6AQAAAA==.Denalli:BAAANQAECgcIDAAAAA==.Devouress:BAAANQAECgEIAgAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAABNQAECn8cAAIhAAcKDxWcBABoAQAhAAcKDxWcBABoAQAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAAANQAECgQIBQAAAA==.Dogslobber:BAAANQAECgEIAQAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Dorkma:BAAANQAECgEIAQAAAA==.Doublenickel:BAAANQAECgYIEwAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAgANAAAAAA==.Drat:BAABNQAECn8aAAMDAAcK1QmLNwBMAQADAAcKrAiLNwBMAQAiAAUKvginDAAIAQAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgkJGAAjAColAA==.',
Du='Duridon:BAAANQAECgIIAgAAAA==.',
Dy='Dyorna:BAAANQADCgcIDAAAAA==.',
Eb='Ebojager:BAABNQAECn8kAAIkAAkK0xazBADPAQAkAAkK0xazBADPAQAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFH8JAAIZAAYKkhA/BADtAQAZAAYKkhA/BADtAQA1AAQKfxoAAhkACgqoIG4uAHcCABkACgqoIG4uAHcCAAAA.',
El='Eldric:BAABNQAECn8xAAIXAAgKbhIjQAA8AQAXAAgKbhIjQAA8AQAAAA==.Elvispriesty:BAAANQAECgQIBAAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwACABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.Entropathy:BAAANQADCgQIBAABNQAECgEIAgANAAAAAA==.',
Er='Ere:BAABNQAECn8YAAMRAAgK4QihQQBBAAAXAAgK4QhArAFoAAARAAEKAAChQQBBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Escalope:BAAANQAECgEIAQAAAA==.Eskath:BAABNQAECn8aAAMaAAYKSBdCVwDUAAAaAAYKSBdCVwDUAAAbAAEKqRxUDgBWAAABNQAECgkJJgAXALMUAA==.Essential:BAABNQAECn8mAAICAAoK3xHkfQAuAgACAAoK3xHkfQAuAgAAAA==.',
Ev='Evavaria:BAABNQAECn8aAAIIAAcKxhmwUwAfAgAIAAcKxhmwUwAfAgABNQADCgQIBAANAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQAECgMICQAAAA==.',
Fa='Fatalism:BAAANQADCggICQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQAECgUIBgABNQAECgoKKAAEALATAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwANAAAAAA==.Ferrara:BAACNQAFFH8SAAMlAAcKBCDaAwBGAgAlAAcKBCDaAwBGAgADAAEKAABFLgBlAAA1AAQKfycAAiUACgqxINUPAOsCACUACgqxINUPAOsCAAAA.',
Fi='Filthi:BAAANQAFFAEIAQAAAA==.Fiz:BAAANQADCgYIBgABNQAECggICAANAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwANAAAAAA==.',
Fl='Flandri:BAACNQAFFH8QAAIEAAYKQBDOEQCBAQAEAAYKQBDOEQCBAQA1AAQKfyMAAgQACgrzIlMRAD0DAAQACgrzIlMRAD0DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgcIIAAfAIwLAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQADCgQIBAANAAAAAA==.Frostednip:BAABNQAECn80AAMYAAoKvRroFADlAgAYAAoKvRroFADlAgAZAAIKYQWFzwBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQADCgQIBwAAAA==.Gabiru:BAABNQAECn8sAAIBAAoKNBt0CQALAwABAAoKNBt0CQALAwAAAA==.Gadreeste:BAAANQAECgYIBgAAAA==.Galnarn:BAACNQAFFH8SAAImAAYK6yGSAQAEAgAmAAYK6yGSAQAEAgA1AAQKfygAAiYACgrDJHcCAIIDACYACgrDJHcCAIIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFH8XAAImAAUK5xoXAwCdAQAmAAUK5xoXAwCdAQA1AAQKfy8AAyYACgrWIAoHANICACYACgpqHQoHANICAB4ACQppHzIZAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgYIEAANAAAAAA==.Garlicbae:BAAANQAECgMIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECn8tAAIPAAkKmBPnBACAAQAPAAkKmBPnBACAAQAAAA==.Gewch:BAAANQADCgEIAQAAAA==.',
Gl='Glorp:BAAANQAECgEIAQAAAA==.Glyd:BAAANQAECgMIAwABNQAECggIDwANAAAAAA==.',
Go='Goldenred:BAAANQAECgQIDAAAAA==.',
Gr='Graybrew:BAAANQAECgQIAwAAAA==.Graye:BAAANQADCgYIBgABNQAECgQIAwANAAAAAA==.Grayes:BAAANQAECgUIDwABNQAECgQIAwANAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgQIAwANAAAAAA==.Grelin:BAAANQAECgUIDgAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggICQAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAQICAAnAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwANAAAAAA==.Harmôny:BAAANQADCgYICQAAAA==.Hatredno:BAAANQADCgQIBAAAAA==.Hatredyes:BAABNQAECn8wAAIoAAoKehXqAwDjAQAoAAoKehXqAwDjAQAAAA==.',
He='Helare:BAABNQAECn8nAAIKAAoKeBFbCgCXAQAKAAoKeBFbCgCXAQAAAA==.Helaro:BAAANQAECgUIBgAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAABNQAECn8UAAIVAAYKJQkNIAAXAQAVAAYKJQkNIAAXAQAAAA==.',
Ho='Holybattler:BAAANQAECgEIAgAAAA==.Holyghosst:BAAANQADCgEIAQAAAA==.',
Hu='Huffmetoes:BAEANQADCgMIAwABNQAECgoKKAAEALATAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgANAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgQICQANAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAAANQAECgYIEwAAAA==.Ikrys:BAAANQAECgYICwAAAA==.',
Il='Ilarion:BAAANQAECgYIBwAAAA==.Illiae:BAABNQAECn8nAAIWAAoKFiKLFgBBAwAWAAoKFiKLFgBBAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgQICQAAAA==.',
Io='Ionic:BAAANQAECggIEAAAAA==.',
Is='Issidora:BAAANQAECgcIDwAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ix='Ix:BAAANQADCgQJBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8gAAIaAAoKFwpBjQDGAQAaAAoKFwpBjQDGAQAAAA==.Janeleonoc:BAAANQAECgIIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgoKLwAXALQdAA==.Jascob:BAAANQAECgQIBQAAAA==.Jaynne:BAAANQAECgEIAQAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECn8hAAIeAAkKuBU9JQD6AQAeAAkKuBU9JQD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBgAAAA==.Kaashaa:BAABNQAECn84AAIDAAoKYx7UBACIAgADAAoKYx7UBACIAgAAAA==.Kaelsgf:BAABNQAECn8tAAIEAAoKcR5HIADuAgAEAAoKcR5HIADuAgAAAA==.Kahllan:BAABNQAECn8dAAIJAAcK0Q/HDQBhAQAJAAcK0Q/HDQBhAQAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCgYICwAAAA==.Kataltoholic:BAAANQAECgQIDgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kayser:BAAANQAECgMIBAAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Keheo:BAAANQADCggICgAAAA==.Kelfin:BAAANQAECgQIBAAAAA==.Kelinïsha:BAABNQAECn8UAAIRAAgKRggUBwAnAQARAAgKRggUBwAnAQAAAA==.Kenf:BAAANQAECgEIAwAAAA==.Kensshaman:BAAANQAECgEIAgAAAA==.Kevinbacon:BAAANQAECgEIAQAAAA==.',
Kh='Khelina:BAAANQAECgcICwAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgcICwANAAAAAA==.',
Ki='Kiiras:BAAANQAECggICwAAAA==.Kimbodh:BAACNQAFFH8VAAIkAAYKpCEAAQB6AQAkAAYKpCEAAQB6AQA1AAQKfzAAAiQACgo3JIAFAHoDACQACgo3JIAFAHoDAAAA.Kimbubbles:BAAANQAECgUIBQAAAA==.Kimoora:BAAANQAECgQIBAABNQAECgUIBQANAAAAAA==.Kimshady:BAAANQADCgcICAABNQAECgUIBQANAAAAAA==.Kirathein:BAAANQAECgIIAwAAAA==.',
Kl='Klefthoof:BAABNQAECn8mAAMWAAcKMAfetAAoAQAWAAcKMAfetAAoAQAfAAUKKQupwADoAAABNQAECggIDwANAAAAAA==.',
Ko='Kodey:BAAANQAECgUIDgABNQAECgkJJQAcALkQAA==.',
Kr='Krelon:BAAANQADCggIEQAAAA==.Krimboz:BAAANQAECgcICwAAAA==.Krystallight:BAABNQAECn8pAAIiAAkKySDQAAAVAgAiAAkKySDQAAAVAgAAAA==.',
La='Lanwulf:BAAANQADCggIEAAAAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn80AAIDAAoKqxt+LgDiAgADAAoKqxt+LgDiAgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgUICAANAAAAAA==.Leondero:BAABNQAECn8iAAIDAAkKCRs1MADcAgADAAkKCRs1MADcAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAAANQAECgcIDgABNQAECgEIAgANAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAABNQAECn8pAAICAAkKig1trwDAAQACAAkKig1trwDAAQAAAA==.',
Lo='Lofi:BAABNQAECn8bAAIfAAgKXAmEjwBiAQAfAAgKXAmEjwBiAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgYIEAAAAA==.',
Lu='Lubricated:BAAANQAECgYICQAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUICgAAAA==.',
Ly='Lycenia:BAAANQADCggICAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8wAAMDAAoKpiCuEQBaAwADAAoKpiCuEQBaAwAlAAEKAADpmgAlAAAAAA==.',
Ma='Magicdreams:BAABNQAECn8bAAIKAAgKGAZOHwDxAAAKAAgKGAZOHwDxAAAAAA==.Mahll:BAAANQAECgIIAgABNQAECgoKIQAaAIwbAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8uAAIWAAkKIRktOgCOAgAWAAkKIRktOgCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQAECgcIEAAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQAECgcIEQAAAA==.Meerchi:BAAANQAECggIDQAAAA==.Meknin:BAABNQAECn8kAAIXAAgKzgT+DwFyAQAXAAgKzgT+DwFyAQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgEIAQABNQAECggIBAANAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgkJGAAjAColAA==.',
Mi='Mickieta:BAABNQAECn8tAAICAAkKZxsYCwAvAgACAAkKZxsYCwAvAgAAAA==.Mikalau:BAABNQAECn8uAAIDAAoK8xfkBgBaAgADAAoK8xfkBgBaAgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAaAFceAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgYIEAANAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn8zAAMEAAoKvhmrMQChAgAEAAoKvhmrMQChAgAFAAgKrRdKIQAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgcIIAAfAIwLAA==.Mognel:BAAANQAECgcIDwAAAA==.Moomootus:BAABNQAECn8rAAICAAoKDh/eOADtAgACAAoKDh/eOADtAgAAAA==.Mordenkainen:BAAANQABCgYICgAAAA==.Motoraxe:BAABNQAECn8eAAIOAAoKhxG8igABAgAOAAoKhxG8igABAgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8oAAMEAAoKsBNHQABqAgAEAAoKsBNHQABqAgAFAAgKgg3UKgDRAQAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQAECgcIEAAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.Niyyx:BAAANQAECgYICAAAAA==.',
No='Nordrydsh:BAAANQAECgEIAQABNQAECgcICwANAAAAAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8RAAIOAAcK/BbBCwD2AQAOAAcK/BbBCwD2AQA1AAQKfycAAg4ACgrYIsA5AN4CAA4ACgrYIsA5AN4CAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
['Nô']='Nôva:BAAANQAECgEIAQAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFH8NAAIfAAcK4RrVBQANAgAfAAcK4RrVBQANAgA1AAQKfyIAAh8ACgpkIOAMAFkDAB8ACgpkIOAMAFkDAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAABNQAECn8mAAMXAAkKsxQkPgBAAQAXAAgKMxUkPgBAAQARAAEKthEQQQBCAAAAAA==.',
Ot='Otimion:BAAANQADCgMIAwAAAA==.',
Ov='Ovarb:BAAANQAECgcICgAAAA==.',
Pa='Pallydan:BAABNQAECn8XAAIHAAgKihtwFgBKAgAHAAgKihtwFgBKAgABNQAECgkJJgAXALMUAA==.Pan:BAAANQAECgIIAgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECgYIBwAAAA==.',
Ph='Phinix:BAAANQAECgEIAgAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIAgAAAA==.',
Pr='Prisman:BAAANQAECgUIBQAAAA==.Proserpìne:BAABNQAECn8VAAIkAAcKQQjvPABhAQAkAAcKQQjvPABhAQAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quicktrik:BAAANQAECgEIAQABNQAFFAYICQAXAAYTAA==.Quoril:BAACNQAFFH8GAAIXAAMKAAQkHgB5AAAXAAMKAAQkHgB5AAA1AAQKfycAAhcACgrkF3+AAH0CABcACgrkF3+AAH0CAAAA.',
Ra='Rabies:BAAANQADCgIIAgAAAA==.Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIBAAAAA==.Rainstormin:BAABNQAECn8VAAMKAAgKnwrEGwAIAQAKAAgKnwrEGwAIAQAoAAMKmAUlXQA7AAAAAA==.Raitan:BAAANQAECgYIEAABNQAECgcIDgANAAAAAA==.Raivoker:BAAANQAECgcIDgAAAA==.Rakarra:BAAANQADCgIIAgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECn8gAAIQAAkKZwiwFgAyAQAQAAkKZwiwFgAyAQABNQADCgcIBwANAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgYICQAAAA==.Remsham:BAAANQAECgYIEQAAAA==.Renwyck:BAABNQAECn8YAAIjAAkKKiXFAADHAwAjAAkKKiXFAADHAwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECn8yAAICAAoKHx7oLQAQAwACAAoKHx7oLQAQAwAAAA==.',
Ro='Robane:BAAANQAECgQIBwAAAA==.Rouen:BAAANQAECgYIDwAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgQICQAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgoKMAAoAHoVAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQAECgQIBAABNQAECgoKKgAEAOQYAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Santalight:BAAANQAECgEIAwABNQAFFAQIDAAeABsaAA==.Santamoe:BAACNQAFFH8MAAIeAAQKGxrJAwDlAAAeAAQKGxrJAwDlAAA1AAQKfzUAAh4ACQorHzwOAPsCAB4ACQorHzwOAPsCAAAA.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECn8lAAIDAAoKyh6RGAA3AwADAAoKyh6RGAA3AwAAAA==.Sarwyn:BAAANQADCgcIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAnANoUAA==.',
Se='Sedak:BAAANQADCggIIQAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAAANQAECggIDgAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shelaan:BAAANQAECgYICwAAAA==.Shiftey:BAABNQAECn8WAAIDAAgKnx0CTACKAgADAAgKnx0CTACKAgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECggIFgADAJ8dAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgANAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAANAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn8nAAQbAAoKExBrBAAPAQAbAAgKWBJrBAAPAQAaAAcKyAiXaACyAAAcAAEKzgWFgQAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn8pAAIQAAkKjR3wBQDkAQAQAAkKjR3wBQDkAQAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Sniffum:BAAANQADCgMIAwAAAA==.Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn8xAAMZAAoKiiVnAAA+AwAZAAoKciVnAAA+AwAYAAgK9yC9EQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgYIBgAAAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAgANAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAABNQAECn8bAAIIAAgK6BehSgA+AgAIAAgK6BehSgA+AgAAAA==.',
St='Stanil:BAABNQAECn8aAAIDAAcKOwV7XwDsAAADAAcKOwV7XwDsAAAAAA==.Steampunkz:BAAANQAECgIIAQAAAA==.Stellare:BAAANQAECgYIBgAAAA==.Strangetame:BAAANQAECgEIAQAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgIIAwAAAA==.',
Su='Suelly:BAABNQAECn8vAAMXAAoKtB3PBQB3AgAXAAoKMhzPBQB3AgARAAQK9xrlHAAHAQAAAA==.Suguru:BAAANQAECggIEQAAAA==.Sularma:BAAANQAECgYIBwAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwANAAAAAA==.Suraschi:BAABNQAECn8mAAImAAkKLBUsDwD+AQAmAAkKLBUsDwD+AQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgYICAAAAA==.Sylain:BAAANQADCggICQABNQAECgUIBwANAAAAAA==.Synwav:BAABNQAECn8hAAIfAAoK+hfAMACeAgAfAAoK+hfAMACeAgAAAA==.',
['Sá']='Sáilormoon:BAAANQAECgMIBAABNQAECgoKJwAWABYiAA==.',
Ta='Taiani:BAAANQAECgEIAQAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAABNQAECn8hAAIfAAgK7xRyGACVAQAfAAgK7xRyGACVAQAAAA==.Tashah:BAAANQADCgYICwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thewhitness:BAAANQAECgcICgAAAA==.Thewretch:BAABNQAECn8bAAIaAAgKxRjeEQC1AQAaAAgKxRjeEQC1AQAAAA==.Thumpthump:BAAANQAECggIDwAAAA==.Thunderkiss:BAEANQADCggIFwABNQAECgQICQANAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Torcamada:BAAANQAECgEIAQAAAA==.Toscus:BAAANQADCgMIAwAAAA==.',
Tr='Tradewarrior:BAABNQAECn8fAAIOAAkKAh39TgCdAgAOAAkKAh39TgCdAgAAAA==.Trayth:BAAANQAECggICAAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECn8vAAMVAAoKDR79AABWAgAVAAoKBR39AABWAgAoAAMKpCDWMAAWAQAAAA==.Tsura:BAABNQAECn8ZAAIIAAgKGxKYZgDkAQAIAAgKGxKYZgDkAQAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn8uAAMdAAoKRSF2BgAxAwAdAAkK1yB2BgAxAwAeAAoKchw8FQCqAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgUIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgoKMAAoAHoVAA==.',
Va='Vaeryn:BAAANQAECgYIDAABNQAECgoKRgAEANoZAA==.Valhen:BAABNQAECn9GAAQEAAoK2hmvBADJAgAEAAoKYRmvBADJAgAGAAcKgRZ4CADeAQAFAAMKGwicYQB6AAAAAA==.Valryn:BAAANQADCggICwABNQAECgoKRgAEANoZAA==.Valtar:BAABNQAECn8rAAIfAAoK3yH6BwCCAwAfAAoK3yH6BwCCAwAAAA==.',
Ve='Velryn:BAAANQADCgYIDAABNQAECgoKRgAEANoZAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQAECgYIBgAAAA==.Vilevixon:BAABNQAECn8tAAMFAAkKZBqLAwDcAQAFAAkKZBqLAwDcAQAGAAEKvAjrLQApAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAANAAAAAA==.Wanlok:BAABNQAECn8XAAMbAAcKMhP2DQB2AQAbAAYK0BT2DQB2AQAaAAUKkgpR/ADTAAAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAABNQAECn8hAAQOAAkKyREjkAD0AQAOAAkKyREjkAD0AQAPAAMKmA2aGQBlAAAhAAEKdAqaNQAvAAABNQAECgoKLwAXALQdAA==.Watts:BAABNQAECn8rAAIDAAoKkRqvBgBeAgADAAoKkRqvBgBeAgABNQAFFAMIBgAXAAAEAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAABNQAECn8kAAMDAAkK8QwWgQAKAgADAAkK8QwWgQAKAgAlAAEKAADfoQAUAAAAAA==.Wildside:BAAANQAECggIDwAAAA==.',
Xa='Xandronys:BAABNQAECn8mAAQbAAoKBxQrAgB1AQAbAAkKnRUrAgB1AQAaAAYKGRC41wAaAQAcAAEKvgnMeQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgMIAgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Yalla:BAAANQAECgUICAAAAA==.',
Ye='Yeet:BAAANQAECggICAAAAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalckar:BAAANQAECggIDwAAAA==.Zanos:BAAANQADCgcICgAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAABNQAECn8ZAAIcAAoKLhhsAAA+AgAcAAoKLhhsAAA+AgAAAA==.Zendead:BAAANQAECggIDQAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgcIDAAAAA==.Zurokhan:BAABNQAECn86AAIIAAoKlx4GAgAdAwAIAAoKlx4GAgAdAwAAAA==.',
['Zø']='Zønda:BAABNQAECn8uAAMhAAkKkyOJAgC2AQAhAAUKyCSJAgC2AQAOAAYK7SKsQQAgAQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAANQAECggICAAAAA==.',
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
