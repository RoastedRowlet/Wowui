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

local lookup = {'Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Shaman-Enhancement','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Mage-Arcane','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Druid-Guardian','Rogue-Assassination',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abnee:BAAANQAECgIIAgAAAA==.',
Ac='Acacia:BAABNQAECn8bAAMBAAcKFQxEQQAdAQABAAYKwQxEQQAdAQACAAYKlg09cgABAQAAAA==.',
Ad='Adowyrm:BAACNQAFFH8SAAIDAAcK0hMLBwDhAQADAAcK0hMLBwDhAQA1AAQKfykAAgMACgohIWwIAB0DAAMACgohIWwIAB0DAAAA.Adrielle:BAAANQAECgYICgAAAA==.',
Ai='Airali:BAABNQAECn80AAIEAAoKLhBPjAANAgAEAAoKLhBPjAANAgAAAA==.Airedale:BAABNQAECn8oAAIFAAgKWhInaACrAQAFAAgKWhInaACrAQAAAA==.',
Ak='Akairo:BAACNQAFFH8cAAIGAAcKhBxXBgAzAgAGAAcKhBxXBgAzAgA1AAQKf0IABAYACgoGJCIHAIwDAAYACgoGJCIHAIwDAAcABwq4EtYoAAEBAAgAAQo1AQYzABoAAAAA.Akelia:BAAANQAECgcIDgAAAA==.',
Al='Aleebobwa:BAAANQAECgEIAQABNQAECgoKOAAJAJwgAA==.Alexanderlx:BAABNQAECn8rAAMKAAkKexxOEQDYAQAKAAgKKSFOEQDYAQAEAAYKGA9R0gD2AAAAAA==.Aleybobwa:BAABNQAECn84AAMJAAoKnCDSDwAZAwAJAAoKnCDSDwAZAwAEAAUKLxWGAQEdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQAECgIIAwAAAA==.Alyméré:BAAANQADCgEIAgAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn82AAMBAAoKtx+kDgDpAgABAAoKtx+kDgDpAgACAAIKpwQXtwAqAAAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn87AAMLAAoKBx3EAgAlAwALAAoKZBzEAgAlAwAMAAMKLRPsKwDFAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgQIBQANAAAAAA==.',
Ao='Aolus:BAABNQAECn87AAICAAoKKRxMGQD9AgACAAoKKRxMGQD9AgAAAA==.',
Ap='Apoliis:BAABNQAECn8WAAIOAAYK/Ai+HQADAQAOAAYK/Ai+HQADAQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQAECggICAAAAA==.Archis:BAABNQAECn8oAAMPAAoKgxVpZABhAgAPAAoKgxVpZABhAgAQAAYKIgjeJgAKAQAAAA==.Arcidaes:BAEBNQAECn8vAAIRAAgK5Q4UOgAxAQARAAgK5Q4UOgAxAQAAAA==.Arez:BAAANQAECgcIBwABNQAECgoKIQASAFYJAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAABNQAECn8gAAIOAAoKNhURDAAkAgAOAAoKNhURDAAkAgAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Av='Avaline:BAAANQAECgEIAQAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8OAAMTAAUKZBsWDgD1AAATAAUKZBsWDgD1AAAUAAIK6wvDAgCQAAA1AAQKfyYAAxQACQo1JPoBAFADABQACQpHIvoBAFADABMABQodJIweAN0BAAAA.',
Ax='Axes:BAAANQADCgEIAQAAAA==.',
Az='Azaekho:BAAANQADCgUIBgAAAA==.Azaelleonoc:BAAANQAECgEIAQAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUIBwABNQAECgoKNAAVANcfAA==.Baeli:BAAANQAECgUIBgAAAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAABNQAECn8iAAMMAAkKoRxxCQCsAQAMAAgKGRtxCQCsAQADAAMKQw1yJwCTAAAAAA==.Baliw:BAABNQAECn8lAAICAAkK/Q0dPAAUAgACAAkK/Q0dPAAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAABNQAECn8iAAIFAAgKBxccaACrAQAFAAgKBxccaACrAQAAAA==.Banugg:BAAANQADCgMIAwAAAA==.Barcode:BAAANQADCgMIBQAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8JAAIWAAYKpQpdDwB5AQAWAAYKpQpdDwB5AQA1AAQKfzkAAhYACgqIIOUSALMCABYACgqIIOUSALMCAAAA.',
Bc='Bchung:BAABNQAECn9DAAMXAAoKdR06BQDDAgAXAAoKJx06BQDDAgASAAoKjRW+SwAFAgAAAA==.',
Be='Bean:BAAANQAECgYIAwAAAA==.Bela:BAAANQAECgQIBgAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgoKIAAOADYVAA==.Belthor:BAAANQAECgEIAQAAAA==.Bertus:BAACNQAFFH8dAAMYAAcKaiWUAQBaAgAYAAcKaiWUAQBaAgAZAAQK8yE3CgBuAQA1AAQKfywAAxkACgoHJrcUABMDABkACQpGJbcUABMDABgACAqVJM4gAIcCAAAA.Bettybop:BAAANQAECgEIAQABNQAECgEIAQANAAAAAA==.',
Bh='Bhain:BAABNQAECn8fAAIWAAkKYRw6LADNAgAWAAkKYRw6LADNAgAAAA==.',
Bi='Bieorne:BAABNQAECn8mAAIZAAgKYxfQIwCQAQAZAAgKYxfQIwCQAQAAAA==.Bierme:BAAANQADCgEIAQAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICwAAAA==.',
Bo='Bog:BAAANQADCgIIAwAAAA==.Boku:BAAANQAECgYICwAAAA==.Boodidy:BAAANQADCgUICQAAAA==.Boondocks:BAABNQAECn84AAQaAAoKNxP+OgD2AQAaAAkKvxL+OgD2AQAbAAQKPBAQFwDZAAAcAAEKlAWlgQAqAAAAAA==.Boozewomen:BAAANQADCgEIAgAAAA==.Bottomx:BAABNQAECn8uAAMMAAoKjwsVCwB5AQAMAAoKjwsVCwB5AQADAAEKxwLVOQAbAAAAAA==.',
Br='Braca:BAABNQAECn8pAAMdAAkKqxkbFwALAgAdAAkKqxkbFwALAgAeAAQKpRDsPwB/AAAAAA==.Bread:BAAANQADCggIEwAAAA==.Brielle:BAABNQAECn80AAIFAAoKdhFEUwDlAQAFAAoKdhFEUwDlAQAAAA==.Brimmnin:BAAANQADCgQIBQAAAA==.Brokenbranch:BAAANQAECgYIDQAAAA==.Brudene:BAABNQAECn8mAAIPAAgKDgzNkAApAQAPAAgKDgzNkAApAQABNQAECggIQQASAMETAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBgAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIBQAAAA==.Buddylock:BAAANQADCgEIAgAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwANAAAAAA==.Bullymaguire:BAAANQAECgYIBgABNQAFFAcIEAAWAJEdAA==.',
Ca='Carbonara:BAAANQADCgYIBgAAAA==.Carpe:BAABNQAECn8WAAMEAAcKPRQDjwBuAQAEAAcKtxMDjwBuAQAKAAUKBxGsLwDNAAAAAA==.Carreth:BAAANQAECggICAAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn9AAAIPAAoK+xgJOwAqAgAPAAoK+xgJOwAqAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFH8fAAIPAAcKZCKrBQC+AQAPAAcKZCKrBQC+AQA1AAQKfzgAAg8ACgq0JgIHALsDAA8ACgq0JgIHALsDAAAA.Charizord:BAAANQADCgEIAQAAAA==.Checkurback:BAABNQAECn8WAAIRAAkKQB0PJACYAgARAAkKQB0PJACYAgAAAA==.Cheefdh:BAAANQAECggICAAAAA==.Chewtum:BAAANQAECgYICQAAAA==.Chimo:BAABNQAECn8iAAIfAAkKfApbXAByAQAfAAkKfApbXAByAQAAAA==.',
Ci='Cillah:BAAANQADCgEIAQABNQAECgoKOgASAL0dAA==.',
Cl='Cleavatron:BAAANQAECgIIAwABNQADCgcIBwANAAAAAA==.',
Co='Cobellex:BAAANQAECgEIAwAAAA==.Codeblue:BAAANQADCgEIAQAAAA==.Cops:BAABNQAECn8tAAIJAAkKpR8lKQDEAgAJAAkKpR8lKQDEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Crusherk:BAAANQAECggIAwAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgUIEwAAAA==.',
Da='Danaconda:BAAANQADCgEIAQABNQAECgoKIAAPAGcYAA==.Danth:BAAANQADCgEIAQAAAA==.Darkenergy:BAABNQAECn84AAIgAAoKCiFNDgCcAgAgAAoKCiFNDgCcAgAAAA==.Darà:BAAANQADCgcICAABNQAECgcIKwABAOESAA==.Dashyll:BAAANQAECggIDwAAAA==.Dazzled:BAAANQADCgcICAAAAA==.',
De='Deadlegslul:BAABNQAECn8nAAIFAAkK9RqQTgDyAQAFAAkK9RqQTgDyAQAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgoKNAAVANcfAA==.Demacus:BAABNQAECn8jAAMSAAgKqQRPvgAAAQASAAgKJARPvgAAAQAXAAIK3QbOOQBXAAABNQAECgkJNwAfAKkLAA==.Demeter:BAABNQAECn8lAAIKAAkKBxB/GgBnAQAKAAkKBxB/GgBnAQAAAA==.Denalli:BAABNQAECn8bAAIXAAgK0Qh1HAAMAQAXAAgK0Qh1HAAMAQAAAA==.Devouress:BAAANQAECgEIAgAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIGAAAAA==.Dimeniare:BAAANQADCggIHgAAAA==.Dirgen:BAABNQAECn8qAAIhAAcKXBWlDgDEAQAhAAcKXBWlDgDEAQAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAAANQAECggIEQAAAA==.Dogslobber:BAAANQAECgEIAQAAAA==.Dookiee:BAAANQADCggIDwAAAA==.Dorkma:BAAANQAECgEIAQAAAA==.Doublenickel:BAABNQAECn8WAAIJAAkKABHGggCSAQAJAAkKABHGggCSAQAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAgANAAAAAA==.Drat:BAABNQAECn8cAAMFAAkKtwkrbwCaAQAFAAkK2AgrbwCaAQAiAAUKvginDAAIAQAAAA==.Dreamsicle:BAAANQADCggIDAAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAwABNQAECgoKKgAjAIclAA==.',
Du='Duridon:BAAANQAECgIIBAAAAA==.',
Dy='Dyorna:BAAANQADCgcIDQAAAA==.',
Eb='Ebojager:BAABNQAECn8zAAIkAAkKnRh3FgDTAQAkAAkKnRh3FgDTAQAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBQAAAA==.',
Ei='Eibon:BAACNQAFFH8JAAIZAAYKkhA/BADtAQAZAAYKkhA/BADtAQA1AAQKfx8AAhkACgrSIG4uAHcCABkACgrSIG4uAHcCAAAA.Eisengel:BAAANQAECgIIAgAAAA==.',
El='Eldric:BAABNQAECn9BAAISAAgKwRPyaQCwAQASAAgKwRPyaQCwAQAAAA==.Elthion:BAAANQADCgEIAQAAAA==.Elvispriesty:BAAANQAECgQICQAAAA==.Elvymir:BAAANQADCgEIAQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwAEABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.Entrapment:BAAANQAECgMIAwABNQADCgcIBwANAAAAAA==.Entropathy:BAAANQAECgQIBgABNQAECgEIAgANAAAAAA==.',
Er='Ere:BAABNQAECn8hAAMSAAoKVgl4owAxAQASAAoKVgl4owAxAQAXAAEKAAChQQBBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Escalope:BAAANQAECgEIAgAAAA==.Eshe:BAAANQADCgEIAwAAAA==.Eskath:BAABNQAECn8kAAMaAAcK1BhaeAA7AQAaAAcK1BhaeAA7AQAbAAEKqRxfKQBHAAABNQAECgoKNgASAHkYAA==.Essential:BAABNQAECn8mAAIEAAoK3xHkfQAuAgAEAAoK3xHkfQAuAgAAAA==.',
Ev='Evavaria:BAABNQAECn8hAAIJAAkKwRiwUwAfAgAJAAkKwRiwUwAfAgABNQADCgQIBQANAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQAECgIIAQAAAA==.',
Ex='Exterminate:BAAANQAECgMICQAAAA==.',
Fa='Fatalism:BAAANQADCggIDQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEBNQAECn8aAAIaAAoKcgtLSwC8AQAaAAoKcgtLSwC8AQABNQAECgoKMQAGAKYUAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwANAAAAAA==.Ferrara:BAACNQAFFH8SAAMlAAcKBCDaAwBGAgAlAAcKBCDaAwBGAgAFAAEKAABFLgBlAAA1AAQKfykAAiUACgpEI9UPAOsCACUACgpEI9UPAOsCAAAA.',
Fi='Filthi:BAABNQAECn8VAAIWAAgKQxYTjQCDAQAWAAgKQxYTjQCDAQAAAA==.Fiz:BAAANQADCgYIBwABNQAECggIEgANAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwANAAAAAA==.',
Fl='Flandri:BAACNQAFFH8QAAIGAAYKQBDOEQCBAQAGAAYKQBDOEQCBAQA1AAQKfyYAAgYACgoQJFMRAD0DAAYACgoQJFMRAD0DAAAA.Floopy:BAAANQAECgEIAQAAAA==.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgkJIgAfAHwKAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQADCgQIBQANAAAAAA==.Friedá:BAAANQAECggIEAABNQAECgoKFwAEAFgXAA==.Frostednip:BAABNQAECn88AAMYAAoKSh7oFADlAgAYAAoKSh7oFADlAgAZAAIKYQWFzwBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAgAAAA==.Gabiru:BAABNQAECn80AAIDAAoKDRx0CQALAwADAAoKDRx0CQALAwAAAA==.Gadreeste:BAAANQAECgcICgAAAA==.Galnarn:BAACNQAFFH8SAAImAAYK6yGSAQAEAgAmAAYK6yGSAQAEAgA1AAQKfzIAAiYACgp+JXcCAIIDACYACgp+JXcCAIIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFH8dAAMmAAcKYxsiAgBHAQAmAAYKKxwiAgBHAQAeAAEKQhjXDgBXAAA1AAQKfzEAAyYACgqlIQoHANICACYACgo4HgoHANICAB4ACgrpHzIZAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgkJIgAMAKEcAA==.Garlicbae:BAAANQAECgMIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECn84AAIQAAoK/hfuBwAtAgAQAAoK/hfuBwAtAgAAAA==.Geran:BAAANQAECgIIAgAAAA==.Gerolan:BAAANQADCgEIAQAAAA==.Gewch:BAAANQAECgEIAgAAAA==.',
Gh='Ghuen:BAAANQAECgEIAQAAAA==.',
Gl='Glorp:BAAANQAECgEIAQAAAA==.Glyd:BAAANQAECggIDgABNQAECgkJNwAfAKkLAA==.',
Go='Goldenred:BAAANQAECgUIEQAAAA==.',
Gr='Graybrew:BAAANQAECgQIBAAAAA==.Graye:BAAANQADCgYIBgABNQAECgQIBAANAAAAAA==.Grayes:BAABNQAECn8aAAInAAcK0Ai6NADBAAAnAAcK0Ai6NADBAAABNQAECgQIBAANAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgQIBAANAAAAAA==.Grelin:BAABNQAECn8WAAIoAAgK6RPbKADfAAAoAAgK6RPbKADfAAAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggICQAAAA==.Grute:BAAANQADCgEIAQAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAQICAAoAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwANAAAAAA==.Harmôny:BAAANQAECgEIAQAAAA==.Hatredno:BAAANQAECgQIBAAAAA==.Hatredyes:BAABNQAECn9CAAInAAoKlRe+DgAQAgAnAAoKlRe+DgAQAgAAAA==.',
He='Helare:BAABNQAECn85AAICAAoKkRiYFABIAgACAAoKkRiYFABIAgAAAA==.Helaro:BAAANQAECgUIBgAAAA==.Helowyn:BAAANQADCggIDQAAAA==.Henrymorgan:BAAANQAECggIBAAAAA==.Hexenbane:BAABNQAECn8hAAIVAAgKVwrhGAAAAQAVAAgKVwrhGAAAAQAAAA==.',
Ho='Holybattler:BAAANQAECgIIBQAAAA==.Holyghosst:BAAANQADCgEIAQAAAA==.',
Hu='Huffmetoes:BAEANQADCgMIAwABNQAECgoKMQAGAKYUAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQAECgIIBAAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgANAAAAAA==.',
Id='Idlewild:BAEANQADCgYICgABNQAECgYIGQACAAYIAA==.',
Ig='Ignazio:BAAANQADCgEIAgAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAABNQAECn8ZAAMSAAgKwg6QpQAtAQASAAcKNg+QpQAtAQAXAAIKYQ6FJwBvAAAAAA==.Ikrys:BAABNQAECn8XAAIcAAcKpBWmDgAQAgAcAAcKpBWmDgAQAgAAAA==.',
Il='Ilandrea:BAAANQAECgEIAQAAAA==.Ilarion:BAABNQAECn8ZAAIEAAoKZQ1fcACvAQAEAAoKZQ1fcACvAQAAAA==.Iliachenvaar:BAAANQAECgEIAQAAAA==.Illiae:BAABNQAECn8rAAIWAAoKJySLFgBBAwAWAAoKJySLFgBBAwAAAA==.',
Im='Impactr:BAAANQADCgYIBwAAAA==.',
In='Insecure:BAAANQAECgQIDAAAAA==.',
Io='Ionic:BAAANQAECggIEAAAAA==.',
Is='Issidora:BAABNQAECn8gAAIlAAcKMQUXLgDJAAAlAAcKMQUXLgDJAAAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8gAAIaAAoKFwpBjQDGAQAaAAoKFwpBjQDGAQAAAA==.Janeleonoc:BAAANQAECgIIBQAAAA==.Janja:BAAANQADCgEIAgABNQAECgoKOgASAL0dAA==.Jascob:BAAANQAECgQICQAAAA==.Jaynne:BAAANQAECgQIBQAAAA==.',
Je='Jeramiah:BAAANQADCgEIAgAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICwAAAA==.',
Ju='Judokeg:BAABNQAECn8hAAIeAAkKuBU9JQD6AQAeAAkKuBU9JQD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBwAAAA==.Kaashaa:BAABNQAECn9KAAIFAAoKeSI9EQBdAwAFAAoKeSI9EQBdAwAAAA==.Kaelsgf:BAABNQAECn81AAIGAAoKKB9HIADuAgAGAAoKKB9HIADuAgAAAA==.Kahllan:BAABNQAECn8rAAIBAAcK4RKRJgBxAQABAAcK4RKRJgBxAQAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCggIFAAAAA==.Kataltoholic:BAAANQAECgUIDwAAAA==.Kayhas:BAAANQADCgIIBQAAAA==.Kayser:BAAANQAECgQICAAAAA==.Kazarel:BAAANQADCggIDQAAAA==.',
Ke='Keheo:BAAANQADCggIDgAAAA==.Kelfin:BAAANQAECgUIBQAAAA==.Kelinïsha:BAABNQAECn8dAAIXAAkKVAihEQAzAQAXAAkKVAihEQAzAQAAAA==.Kenf:BAAANQAECgEIAwAAAA==.Kensshaman:BAAANQAECgEIAgAAAA==.Kevinbacon:BAAANQAECgIIAQAAAA==.',
Kh='Khelina:BAAANQAECgcIDAAAAA==.Khelldyr:BAAANQADCggIHAABNQAECgcIDAANAAAAAA==.',
Ki='Kiiras:BAAANQAECgcIDgAAAA==.Kimbodh:BAACNQAFFH8VAAIkAAYKpCEPAwBPAQAkAAYKpCEPAwBPAQA1AAQKfzkAAiQACgowJYAFAHoDACQACgowJYAFAHoDAAAA.Kimbubbles:BAAANQAECgUIBQAAAA==.Kimoora:BAAANQAECgQIBAABNQAECgUIBQANAAAAAA==.Kimshady:BAAANQADCgcICAABNQAECgUIBQANAAAAAA==.Kirathein:BAAANQAECgMIBgAAAA==.Kirenlen:BAAANQAECgEIAQAAAA==.',
Kl='Klefthoof:BAABNQAECn83AAMfAAkKqQvIdAAhAQAfAAgKYArIdAAhAQAWAAgKDAioZAAeAQAAAA==.',
Ko='Kodey:BAABNQAECn8aAAIcAAkKpgoNBwA3AQAcAAkKpgoNBwA3AQAAAA==.',
Kr='Krelon:BAAANQADCggIFAAAAA==.Krimboz:BAAANQAECgYIDgAAAA==.Krystallight:BAABNQAECn84AAIiAAoKDCEQAgCmAgAiAAoKDCEQAgCmAgAAAA==.',
La='Laanda:BAAANQAECgEIAQABNQAECgUIEAANAAAAAA==.Lanwulf:BAAANQAECgQIBAAAAA==.Lazreki:BAAANQADCgEIAQAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn9EAAIFAAoK7R9cGADCAgAFAAoK7R9cGADCAgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgYICQANAAAAAA==.Leondero:BAABNQAECn8iAAIFAAkKCRs1MADcAgAFAAkKCRs1MADcAgAAAA==.Leroyjenkins:BAAANQADCggIFQAAAA==.Leuthil:BAABNQAECn8cAAMoAAoKixEIHQAqAQATAAoKbA9+OgDPAQAoAAcKpw0IHQAqAQABNQAECgEIAgANAAAAAA==.',
Li='Lintilla:BAAANQADCgcICgAAAA==.',
Ll='Llevanya:BAABNQAECn8vAAIEAAoKxA7MigB2AQAEAAoKxA7MigB2AQAAAA==.',
Lo='Lofi:BAABNQAECn8fAAIfAAoKSAiEjwBiAQAfAAoKSAiEjwBiAQAAAA==.Loisa:BAAANQADCgEIAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgcIEQAAAA==.',
Lu='Lubricated:BAAANQAECgcICgAAAA==.Lucíewilde:BAAANQADCgQIBQAAAA==.Luxon:BAAANQAECgUICgAAAA==.',
Ly='Lycenia:BAAANQADCggICAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8wAAMFAAoKpiCuEQBaAwAFAAoKpiCuEQBaAwAlAAEKAADpmgAlAAAAAA==.',
Ma='Magicdreams:BAABNQAECn8iAAICAAgKKwZaRgDYAAACAAgKKwZaRgDYAAAAAA==.Mahll:BAAANQAECgIIAgABNQAECgoKMAAaAKIeAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8uAAIWAAkKIRktOgCOAgAWAAkKIRktOgCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Marihuano:BAAANQAECgEIAQAAAA==.Materia:BAABNQAECn8hAAIGAAoK3B1MFgD4AgAGAAoK3B1MFgD4AgAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAABNQAECn8gAAIPAAoKZxhGOwApAgAPAAoKZxhGOwApAgAAAA==.Meerchi:BAABNQAECn8aAAISAAoKAApkcACfAQASAAoKAApkcACfAQAAAA==.Meknin:BAABNQAECn8yAAISAAoKxAW8hQBuAQASAAoKxAW8hQBuAQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merithyn:BAAANQAECgIIAgAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgEIAQABNQAECggIBAANAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgoKKgAjAIclAA==.',
Mi='Mickieta:BAABNQAECn84AAIEAAoKwBvCNwBXAgAEAAoKwBvCNwBXAgAAAA==.Mikalau:BAABNQAECn8/AAIFAAoKsBikNwA5AgAFAAoKsBikNwA5AgAAAA==.Mikaluu:BAAANQADCggIFwAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAaAFceAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgkJIgAMAKEcAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn9EAAMGAAoKKhqrMQChAgAGAAoKKhqrMQChAgAHAAgKGBlKIQAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgkJIgAfAHwKAA==.Mognel:BAABNQAECn8bAAIaAAoKgA4GTgCyAQAaAAoKgA4GTgCyAQAAAA==.Moisten:BAAANQAECgEIAQAAAA==.Monklee:BAAANQADCgYIBgAAAA==.Moomootus:BAABNQAECn8rAAIEAAoKDh/eOADtAgAEAAoKDh/eOADtAgAAAA==.Mordenkainen:BAAANQABCgYICgAAAA==.Motoraxe:BAABNQAECn8gAAIPAAoKhxG8igABAgAPAAoKhxG8igABAgAAAA==.Mozzie:BAAANQAECggICAAAAA==.',
My='Mystynight:BAAANQAECgQIBAAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQADCgEIAQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8xAAMGAAoKphRHQABqAgAGAAoKphRHQABqAgAHAAkK7wzUKgDRAQAAAA==.Nightcrest:BAAANQAECgYICgAAAA==.Nightrocks:BAAANQAECggIEgAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQAECgEIAQAAAA==.Niyyx:BAAANQAECgYIEwAAAA==.',
No='Nomusa:BAAANQAECgQIBQAAAA==.Nordrydsh:BAAANQAECgIIBQABNQAFFAcIDgADALYJAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQADCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8RAAIPAAcK/BbBCwD2AQAPAAcK/BbBCwD2AQA1AAQKfzQAAg8ACgpLIxAcALwCAA8ACgpLIxAcALwCAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
['Nô']='Nôva:BAAANQAECgEIAQAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Od='Odelay:BAAANQADCgEIAQAAAA==.',
Ol='Olimdar:BAACNQAFFH8NAAIfAAcK4RrVBQANAgAfAAcK4RrVBQANAgA1AAQKfywAAh8ACgp4I0sEAMQDAB8ACgp4I0sEAMQDAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAABNQAECn82AAMSAAoKeRirNwBFAgASAAoKeRirNwBFAgAXAAEKthEQQQBCAAAAAA==.Orgarrot:BAAANQAECgYICAABNQAECgoKQgAnAJUXAA==.',
Ot='Otimion:BAAANQAECgYICAAAAA==.',
Ov='Ovarb:BAAANQAECgcICwAAAA==.',
Pa='Padwendyn:BAAANQAECgIIAgAAAA==.Pallydan:BAABNQAECn8cAAIKAAkKLRxgEgDHAQAKAAkKLRxgEgDHAQABNQAECgoKNgASAHkYAA==.Pan:BAAANQAECgIIAgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECggIBwAAAA==.',
Ph='Phinix:BAAANQAECgYIDwAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAgAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIBQAAAA==.',
Pr='Prisman:BAAANQAECgUIBQAAAA==.Proserpìne:BAABNQAECn8VAAIkAAcKQQjvPABhAQAkAAcKQQjvPABhAQAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYIDAAAAA==.',
Py='Pyramid:BAAANQAECggICAAAAA==.',
['Pè']='Pèrsephone:BAAANQADCgEIAQAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAACNQAFFH8JAAISAAQKRAVNMgCFAAASAAQKRAVNMgCFAAA1AAQKfycAAhIACgrkF3+AAH0CABIACgrkF3+AAH0CAAAA.',
Ra='Rabies:BAAANQADCgIIAgAAAA==.Radiyra:BAAANQADCgEIAQAAAA==.Ragnahr:BAAANQAECggIBAAAAA==.Rainstormin:BAABNQAECn8iAAMCAAoKhwy9JwCHAQACAAoKdgy9JwCHAQAnAAQK8QZYTQBfAAAAAA==.Raitan:BAAANQAECggIEwABNQAECgkJFwADAM4WAA==.Raivoker:BAABNQAECn8XAAIDAAkKzhajCQBqAgADAAkKzhajCQBqAgAAAA==.Rakarra:BAAANQAECggICAAAAA==.Rantah:BAAANQADCgQIBQAAAA==.Rawrstance:BAABNQAECn8pAAIRAAoKwgsjLQB1AQARAAoKwgsjLQB1AQABNQADCgcIBwANAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAABNQAECn8UAAIWAAkKKR7MEwCqAgAWAAkKKR7MEwCqAgAAAA==.Remsham:BAABNQAECn8aAAIOAAgK3QTiHgD0AAAOAAgK3QTiHgD0AAAAAA==.Renwyck:BAABNQAECn8qAAIjAAoKhyXFAADHAwAjAAoKhyXFAADHAwAAAA==.Reovar:BAAANQADCgEIAQAAAA==.Reovarr:BAAANQADCgIIAwAAAA==.Revengemoon:BAABNQAECn86AAIEAAoK4B7oLQAQAwAEAAoK4B7oLQAQAwAAAA==.',
Ro='Robane:BAAANQAECgQIEQAAAA==.Rouen:BAABNQAECn8dAAQOAAgKCxpEFwBaAQAOAAcKdhhEFwBaAQAfAAUKLh1mnAA/AQAWAAEKhwY+OgExAAAAAA==.Roueyn:BAAANQAECgUICgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEBNQAECn8ZAAICAAYKBggWVgCcAAACAAYKBggWVgCcAAAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgoKQgAnAJUXAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBgAAAA==.',
['Ró']='Róshi:BAAANQADCgEIAQAAAA==.',
Sa='Safetwo:BAAANQAECgQIBQABNQAECgoKOQAGALkZAA==.Sahranna:BAAANQADCgEIAQAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Santalight:BAAANQAECgEIAwABNQAFFAUIDQAeAAQZAA==.Santamoe:BAACNQAFFH8NAAIeAAUKBBnyBAApAQAeAAUKBBnyBAApAQA1AAQKf0QAAh4ACQqwIzwOAPsCAB4ACQqwIzwOAPsCAAAA.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECn81AAIFAAoK/iGRGAA3AwAFAAoK/iGRGAA3AwAAAA==.Sarwyn:BAAANQADCgcIBwAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAoANoUAA==.',
Sc='Scratchs:BAAANQAECggICwABNQADCgcIBwANAAAAAA==.',
Se='Sedak:BAAANQADCggIIQAAAA==.Seitana:BAAANQADCgEIAQAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAABNQAECn8dAAIgAAgKswRLQwDoAAAgAAgKswRLQwDoAAAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIEAAAAA==.Shelaan:BAABNQAECn8WAAIWAAYK6gVIwwALAQAWAAYK6gVIwwALAQAAAA==.Shiftey:BAABNQAECn8cAAIFAAgKRh4CTACKAgAFAAgKRh4CTACKAgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECggIHAAFAEYeAA==.Shirtles:BAAANQADCgcIDgAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgANAAAAAA==.Shockzstuff:BAAANQAECgEIAQABNQAECgcIBwANAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICQANAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn8zAAQbAAoKsxOqCgDJAQAbAAgKxBSqCgDJAQAaAAgK0Q0YgwAiAQAcAAEKzgWFgQAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn8zAAIRAAoKtR96FABFAgARAAoKtR96FABFAgAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snicklfritz:BAAANQADCggICAAAAA==.Sniffum:BAAANQADCgMIAwAAAA==.Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn86AAMZAAoKHCbgBAAZAwAZAAoKDibgBAAZAwAYAAgK9yC9EQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgYIBgAAAA==.Sophialeonoc:BAAANQAECgIIAwAAAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAgANAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAABNQAECn8sAAIJAAkKHhg9NgAPAgAJAAkKHhg9NgAPAgAAAA==.',
St='Stanil:BAABNQAECn8hAAIFAAgKKwWeqQAaAQAFAAgKKwWeqQAaAQAAAA==.Steampunkz:BAAANQAECgIIAQAAAA==.Stellare:BAAANQAECggICgAAAA==.Strangetame:BAAANQAECgEIAQAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgIIBAAAAA==.',
Su='Suelly:BAABNQAECn86AAMSAAoKvR0aKgB5AgASAAoKaBwaKgB5AgAXAAQK9xrlHAAHAQAAAA==.Suguru:BAAANQAECggIEQAAAA==.Sularma:BAAANQAECgcICAAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwANAAAAAA==.Suraschi:BAABNQAECn82AAImAAoK/hWTBwC3AQAmAAoK/hWTBwC3AQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgYIEwAAAA==.Sylain:BAAANQADCggICgABNQAECgQIBwANAAAAAA==.Synwav:BAABNQAECn8uAAMfAAoK/xrAMACeAgAfAAoK/xrAMACeAgAWAAEKAADmCAEAAAAAAA==.',
['Sá']='Sáilormoon:BAAANQAECgQIBAABNQAECgoKKwAWACckAA==.',
Ta='Taiani:BAAANQAECgEIAQAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgUICQAAAA==.Tannatax:BAABNQAECn8iAAIfAAgKYBXiWgB3AQAfAAgKYBXiWgB3AQAAAA==.Tashah:BAAANQADCgYIDAAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thauyia:BAAANQAECgEIAgABNQAECgUIEAANAAAAAA==.Thewhitness:BAAANQAECgcICwAAAA==.Thewretch:BAABNQAECn8iAAIaAAgKwxkCVQCcAQAaAAgKwxkCVQCcAQAAAA==.Thumpthump:BAABNQAECn8aAAIlAAkKiRx1GgCBAgAlAAkKiRx1GgCBAgAAAA==.Thunderkiss:BAEANQADCggIHAABNQAECgYIGQACAAYIAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Torcamada:BAAANQAECgEIAgAAAA==.Toscus:BAAANQADCgMIAwAAAA==.',
Tr='Tradewarrior:BAABNQAECn8uAAMPAAkKuSBdIAClAgAPAAkKuSBdIAClAgAhAAEKTR7qIwBXAAAAAA==.Trayth:BAAANQAECggICAAAAA==.Trevor:BAAANQADCgMIBAAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECn80AAMVAAoK1x95BQCHAgAVAAoKzx55BQCHAgAnAAQKiB/WMAAWAQAAAA==.Tsura:BAABNQAECn8hAAIJAAoK3BGYZgDkAQAJAAoK3BGYZgDkAQAAAA==.',
Tu='Tutatotao:BAAANQAECgEIAQABNQAECgEIAgANAAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn88AAMdAAoKRSF2BgAxAwAdAAkK1yB2BgAxAwAeAAoKHSEEBwDhAgAAAA==.Underpowered:BAAANQADCgcIEQAAAA==.Unearthed:BAAANQADCgUIBQAAAA==.',
Ur='Urlän:BAAANQADCgYIBwAAAA==.',
Us='Usirina:BAAANQADCgUIBgABNQAECgoKQgAnAJUXAA==.',
Va='Vaeryn:BAAANQAECgcIEAABNQAECgoKXgAGANEeAA==.Valhen:BAABNQAECn9eAAQGAAoK0R7YDgA9AwAGAAoKWB7YDgA9AwAIAAcKgRZ4CADeAQAHAAQKwg6DNwCmAAAAAA==.Valryn:BAAANQAECgUIBQABNQAECgoKXgAGANEeAA==.Valrys:BAAANQADCgUIBQABNQAECgoKXgAGANEeAA==.Valtar:BAABNQAECn8zAAIfAAoK8iH6BwCCAwAfAAoK8iH6BwCCAwAAAA==.',
Ve='Veliraleonoc:BAAANQAECgEIAQAAAA==.Velryn:BAAANQADCggIFQABNQAECgoKXgAGANEeAA==.',
Vi='Vicsen:BAAANQADCgUIBgAAAA==.Vikaya:BAAANQAECgcICwAAAA==.Vilevixon:BAABNQAECn84AAMHAAoKKRoZFgCsAgAHAAoKKRoZFgCsAgAIAAEKvAjrLQApAAAAAA==.',
Wa='Wagu:BAAANQADCgEIAgAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAANAAAAAA==.Wanlok:BAABNQAECn8eAAMbAAkKWhXBCQBmAQAbAAkKmBTBCQBmAQAaAAUKkgpR/ADTAAAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQAECgEIAQAAAA==.Warriorlobo:BAABNQAECn8mAAQPAAkKWhUjkAD0AQAPAAkKWhUjkAD0AQAQAAMKmA1SLwBgAAAhAAEKdAqaNQAvAAABNQAECgoKOgASAL0dAA==.Watts:BAABNQAECn85AAIFAAoKYBubLgDhAgAFAAoKYBubLgDhAgABNQAFFAQICQASAEQFAA==.',
We='Weez:BAAANQADCgUIBgAAAA==.Werebeer:BAAANQAECgEIAQAAAA==.',
Wi='Wildfang:BAABNQAECn81AAMFAAoKKRDRVwDYAQAFAAoKKRDRVwDYAQAlAAIK/gGBaQAmAAAAAA==.Wildside:BAABNQAECn8bAAIFAAoKHRaeTQCFAgAFAAoKHRaeTQCFAgAAAA==.',
Xa='Xandronys:BAABNQAECn8tAAQbAAoKnxQRBwAyAgAbAAoKnxQRBwAyAgAaAAYKwxC41wAaAQAcAAEKvgnMeQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgQIBgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Yalla:BAAANQAECgYICQAAAA==.',
Ye='Yeet:BAAANQAECggIEgAAAA==.',
Yu='Yuridak:BAAANQAECgcIBwABNQAECgkJJgAdADYVAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalandra:BAAANQADCgIIAgAAAA==.Zalckar:BAAANQAECgcIEwAAAA==.Zanos:BAAANQAECgEIAQAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAABNQAECn8sAAIcAAoKJhuvAQBoAgAcAAoKJhuvAQBoAgAAAA==.Zendead:BAAANQAECgcIEQAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgcIDQAAAA==.Zurii:BAAANQAECgEIAgAAAA==.Zurokhan:BAABNQAECn9MAAIJAAoKXx+kDwAbAwAJAAoKXx+kDwAbAwAAAA==.',
['Zø']='Zønda:BAABNQAECn9AAAMhAAkK7CTcCQC1AQAhAAUKziXcCQC1AQAPAAYKCiTPYQCgAQAAAA==.',
['Ða']='Ðagon:BAAANQAECggIDgAAAA==.',
['Ñå']='Ñårçîssîstîç:BAABNQAECn8ZAAIHAAkK1gWaJgASAQAHAAkK1gWaJgASAQAAAA==.',
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
