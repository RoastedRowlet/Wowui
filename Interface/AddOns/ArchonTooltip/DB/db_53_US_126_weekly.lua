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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Arcane','Paladin-Protection','Paladin-Holy','Druid-Restoration','Druid-Balance','Evoker-Devastation','Unknown-Unknown','Shaman-Enhancement','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Druid-Guardian','Rogue-Assassination',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abnee:BAAANQAECgIIAgAAAA==.',
Ac='Acacia:BAAANQAECgYIEgAAAA==.',
Ad='Adowyrm:BAACNQAFFH8UAAMBAAgKlxELBwDhAQABAAgKlxELBwDhAQACAAEKAAD8DwAAAAA1AAQKfyoAAgEACgohIWwIAB0DAAEACgohIWwIAB0DAAAA.Adrielle:BAAANQAECgYICQAAAA==.',
Ai='Airali:BAABNQAECn80AAIDAAoKLhBPjAANAgADAAoKLhBPjAANAgAAAA==.Airedale:BAABNQAECn8wAAIEAAoKxRKASgAnAgAEAAoKxRKASgAnAgAAAA==.',
Ak='Akairo:BAACNQAFFH8cAAIFAAcKhBxXBgAzAgAFAAcKhBxXBgAzAgA1AAQKf0MABAUACgohJCIHAIwDAAUACgohJCIHAIwDAAYABwq4EugtAAABAAcAAQo1AQYzABoAAAAA.Akelia:BAABNQAECn8UAAIIAAgKIhTPeQCmAQAIAAgKIhTPeQCmAQAAAA==.',
Al='Alexanderlx:BAABNQAECn8sAAMJAAkKexwnFgBNAgAJAAgKKSEnFgBNAgADAAYKGA/s7ADyAAAAAA==.Aleybobwa:BAABNQAECn86AAMKAAoKnCCTEwANAwAKAAoKnCCTEwANAwADAAUKLxWGAQEdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn8/AAMLAAoK0h+kDgDpAgALAAoK0h+kDgDpAgAMAAgKsxAOOAA/AQAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn87AAMCAAoKBx3EAgAlAwACAAoKZBzEAgAlAwANAAMKLRPsKwDFAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgQIBQAOAAAAAA==.',
Ao='Aolus:BAABNQAECn87AAIMAAoKKRxMGQD9AgAMAAoKKRxMGQD9AgAAAA==.',
Ap='Apoliis:BAABNQAECn8WAAIPAAYK/AjPIAADAQAPAAYK/AjPIAADAQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQAECggICAAAAA==.Archis:BAABNQAECn8oAAMQAAoKgxVpZABhAgAQAAoKgxVpZABhAgARAAYKIgjeJgAKAQAAAA==.Arcidaes:BAEBNQAECn8yAAISAAkKaQ8mNQBkAQASAAkKaQ8mNQBkAQAAAA==.Arez:BAAANQAECggIDgABNQAECgoKIgAIAFYJAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAABNQAECn8gAAIPAAoKNhX5DQAhAgAPAAoKNhX5DQAhAgAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Av='Avaline:BAAANQABCgQIBQAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8PAAMTAAYKWhbHCgBIAQATAAYKWhbHCgBIAQAUAAIK6wvDAgCQAAA1AAQKfycAAxQACgqLI/oBAFADABQACQpHIvoBAFADABMABgo+I4weAN0BAAAA.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUIBwABNQAECgoKNAAVANcfAA==.Baeli:BAAANQAECgQIBQAAAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAABNQAECn8oAAMNAAoKyByQCgCtAQANAAgKGRuQCgCtAQABAAYKeBNbFwBmAQAAAA==.Baliw:BAABNQAECn8lAAIMAAkK/Q0dPAAUAgAMAAkK/Q0dPAAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAABNQAECn8lAAIEAAkKBhc5XQD2AQAEAAkKBhc5XQD2AQAAAA==.Banugg:BAAANQADCgMIAwAAAA==.Barcode:BAAANQADCgMIBwAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8JAAIWAAYKpQpdDwB5AQAWAAYKpQpdDwB5AQA1AAQKfzkAAhYACgqIIB8WAK0CABYACgqIIB8WAK0CAAAA.',
Bc='Bchung:BAABNQAECn9LAAMXAAoKyR06BQDDAgAXAAoKJx06BQDDAgAIAAoKDRmDNgBfAgAAAA==.',
Be='Bean:BAAANQAECgYIAwAAAA==.Bela:BAAANQAECgYIDAAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgoKIAAPADYVAA==.Belthor:BAAANQAECgEIAQAAAA==.Bertus:BAECNQAFFH8dAAMYAAcKaiWUAQBaAgAYAAcKaiWUAQBaAgAZAAQK8yE3CgBuAQA1AAQKfy0AAxkACgoHJrcUABMDABkACQpGJbcUABMDABgACAqVJM4gAIcCAAAA.Bettybop:BAAANQAECgIIAgAAAA==.',
Bh='Bhain:BAABNQAECn8fAAIWAAkKYRw6LADNAgAWAAkKYRw6LADNAgABNQAECgoKHAAaAMsbAA==.',
Bi='Bieorne:BAABNQAECn8pAAIZAAkKPBfoHwDOAQAZAAkKPBfoHwDOAQAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAwAAAA==.Boku:BAAANQAECgYIDwAAAA==.Boodidy:BAAANQADCgUICQAAAA==.Boondocks:BAABNQAECn9BAAQaAAoK2RRlOgAZAgAaAAkKeRNlOgAZAgAbAAQKpRQQFwDZAAAcAAEKlAWlgQAqAAAAAA==.Bottomx:BAABNQAECn8vAAMNAAoKugudDAB2AQANAAoKugudDAB2AQABAAEKxwIsPgAbAAAAAA==.',
Br='Braca:BAABNQAECn8rAAMdAAkKqxkbFwALAgAdAAkKqxkbFwALAgAeAAQKpRCvRQB9AAAAAA==.Bread:BAAANQADCggIEwAAAA==.Brielle:BAABNQAECn81AAIEAAoKdhG2XwDvAQAEAAoKdhG2XwDvAQAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgYIDwAAAA==.Brudene:BAABNQAECn8oAAIQAAgKDgwCoAAoAQAQAAgKDgwCoAAoAQABNQAECggIRAAIAMETAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIBQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwAOAAAAAA==.Bullymaguire:BAAANQAECgYIBgAAAA==.',
Ca='Carbonara:BAAANQADCgYIBgAAAA==.Carpe:BAABNQAECn8bAAMDAAcK9BQ7ngB7AQADAAcKtxM7ngB7AQAJAAUKRBNrLwDsAAAAAA==.Carreth:BAAANQAECggICAAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn9AAAIQAAoK+xh5RAAkAgAQAAoK+xh5RAAkAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEIAQAAAA==.Charge:BAACNQAFFH8fAAIQAAcKZCI/BwBLAgAQAAcKZCI/BwBLAgA1AAQKfzgAAhAACgq0JgIHALsDABAACgq0JgIHALsDAAAA.Checkurback:BAABNQAECn8XAAISAAoKjB0PJACYAgASAAoKjB0PJACYAgAAAA==.Cheefdh:BAAANQAECggICAAAAA==.Chewtum:BAAANQAECgYICwAAAA==.Chimo:BAABNQAECn8iAAIfAAkKfAoRawBcAQAfAAkKfAoRawBcAQAAAA==.Chüdd:BAAANQADCgQIBAAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgoKQwAIAL0dAA==.',
Cl='Cleavatron:BAAANQAECgIIAwABNQADCgcIBwAOAAAAAA==.',
Co='Conn:BAAANQADCgMIAwAAAA==.Cops:BAABNQAECn8tAAIKAAkKpR8lKQDEAgAKAAkKpR8lKQDEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Crusherk:BAAANQAECggIAgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAABNQAECn8XAAIdAAcKcx7QEADpAQAdAAcKcx7QEADpAQAAAA==.',
Da='Daimur:BAAANQAECgMIAwABNQAECgoKIgAIAFYJAA==.Danaconda:BAAANQABCgQIBgABNQAECgoKIAAQAGcYAA==.Darkenergy:BAABNQAECn9BAAIgAAoKCiHkDQC6AgAgAAoKCiHkDQC6AgAAAA==.Darà:BAAANQADCgcIBwABNQAECggILQALANAUAA==.Dashyll:BAAANQAECggIDgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAABNQAECn8wAAIEAAoKBxwyNQBjAgAEAAoKBxwyNQBjAgAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgoKNAAVANcfAA==.Demacus:BAABNQAECn8pAAMIAAgKywSbzgD7AAAIAAgKRgSbzgD7AAAXAAIK3QbOOQBXAAABNQAECgoKPgAfANkKAA==.Demeter:BAABNQAECn8oAAIJAAkKzhDNHQBrAQAJAAkKzhDNHQBrAQAAAA==.Denalli:BAABNQAECn8iAAIXAAgK5QmbFAAwAQAXAAgK5QmbFAAwAQAAAA==.Devouress:BAAANQAECgEIAgAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAABNQAECn8rAAIhAAgKJBSlDgDEAQAhAAgKJBSlDgDEAQAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAABNQAECn8YAAIGAAgKxAUELgD/AAAGAAgKxAUELgD/AAAAAA==.Dogslobber:BAAANQAECgEIAQAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Dorkma:BAAANQABCgMIAwAAAA==.Doublenickel:BAABNQAECn8aAAIKAAoKhhDGggCSAQAKAAoKhhDGggCSAQAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAgAOAAAAAA==.Drat:BAABNQAECn8cAAMEAAkKtwl1gACeAQAEAAkK2Ah1gACeAQAiAAUKvginDAAIAQAAAA==.Dreamsicle:BAAANQADCggIDQAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgoKKgAjAIclAA==.',
Du='Duridon:BAAANQAECgIIBAAAAA==.',
Dy='Dyorna:BAAANQADCgcIDAAAAA==.',
Eb='Ebojager:BAABNQAECn83AAIkAAoKhhgwFAAPAgAkAAoKhhgwFAAPAgAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFH8KAAIZAAYKkhA/BADtAQAZAAYKkhA/BADtAQA1AAQKfyAAAhkACgoGIW4uAHcCABkACgoGIW4uAHcCAAAA.Eisengel:BAAANQAECgIIAgAAAA==.',
El='Eldric:BAABNQAECn9EAAIIAAgKwRMhdQCxAQAIAAgKwRMhdQCxAQAAAA==.Elvispriesty:BAAANQAECgUICAAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwADABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.Entrapment:BAAANQAECggICgABNQADCgcIBwAOAAAAAA==.Entropathy:BAAANQAECgQIBgABNQAECgEIAgAOAAAAAA==.',
Er='Ere:BAABNQAECn8iAAMIAAoKVgm9sAAxAQAIAAoKVgm9sAAxAQAXAAEKAAChQQBBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAABNQAECn8kAAMaAAcK1BjPiAA3AQAaAAcK1BjPiAA3AQAbAAEKqRxfKQBHAAABNQAECgoKOAAIAE8aAA==.Essential:BAABNQAECn8mAAIDAAoK3xHkfQAuAgADAAoK3xHkfQAuAgAAAA==.',
Ev='Evavaria:BAABNQAECn8iAAIKAAkKvBmwUwAfAgAKAAkKvBmwUwAfAgABNQADCgQIBAAOAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.',
Ex='Exterminate:BAAANQAECgMICQAAAA==.',
Fa='Fatalism:BAAANQADCggIDgAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEBNQAECn8eAAIaAAoK2ww8UADQAQAaAAoK2ww8UADQAQABNQAECgoKMgAFAKYUAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwAOAAAAAA==.Ferrara:BAACNQAFFH8UAAMlAAgK1h/aAwBGAgAlAAgK1h/aAwBGAgAEAAEKAABFLgBlAAA1AAQKfykAAiUACgpEI9UPAOsCACUACgpEI9UPAOsCAAAA.',
Fi='Filthi:BAABNQAECn8YAAIWAAgK6ReWUwB2AQAWAAgK6ReWUwB2AQAAAA==.Fiz:BAAANQADCgYIBgABNQAECggIDwAOAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAOAAAAAA==.',
Fl='Flandri:BAACNQAFFH8SAAIFAAgK2A7OEQCBAQAFAAgK2A7OEQCBAQA1AAQKfycAAgUACgoQJFMRAD0DAAUACgoQJFMRAD0DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgkJIgAfAHwKAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQADCgQIBAAOAAAAAA==.Friedá:BAAANQAECggIDgAAAA==.Frostednip:BAABNQAECn88AAMYAAoKSh7oFADlAgAYAAoKSh7oFADlAgAZAAIKYQWFzwBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAgAAAA==.Gabiru:BAABNQAECn80AAIBAAoKDRx0CQALAwABAAoKDRx0CQALAwAAAA==.Gadreeste:BAAANQAECgcICAAAAA==.Galhamon:BAAANQADCgMIAwAAAA==.Galnarn:BAACNQAFFH8UAAImAAcK9yGSAQAEAgAmAAcK9yGSAQAEAgA1AAQKfzMAAiYACgp+JXcCAIIDACYACgp+JXcCAIIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFH8dAAMmAAcKYxsXAwCdAQAmAAYKKxwXAwCdAQAeAAEKQhipEABXAAA1AAQKfzEAAyYACgqlIQoHANICACYACgo4HgoHANICAB4ACgrpHzIZAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgoKKAANAMgcAA==.Garlicbae:BAAANQAECgQIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECn87AAIRAAoKqBlGCABJAgARAAoKqBlGCABJAgAAAA==.Geran:BAAANQAECgIIAQAAAA==.',
Gl='Glyd:BAAANQAECgYIDgABNQAECgoKPgAfANkKAA==.',
Go='Goldenred:BAAANQAECgUIEQAAAA==.Goregrim:BAAANQAFFAEIAQAAAA==.',
Gr='Graybrew:BAAANQAECgMIAwAAAA==.Graye:BAAANQADCgYIBwABNQAECgMIAwAOAAAAAA==.Grayes:BAABNQAECn8aAAInAAcK0AjNOwC+AAAnAAcK0AjNOwC+AAABNQAECgMIAwAOAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgMIAwAOAAAAAA==.Grelin:BAABNQAECn8WAAIoAAgK6RP7KgDfAAAoAAgK6RP7KgDfAAAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggICQAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAQICAAoAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAOAAAAAA==.Harmôny:BAAANQAECgEIAQAAAA==.Hatredno:BAAANQAECgQIBAAAAA==.Hatredyes:BAABNQAECn9LAAInAAoKqxi/DwAnAgAnAAoKqxi/DwAnAgAAAA==.',
He='Helare:BAABNQAECn85AAIMAAoKkRikFwBDAgAMAAoKkRikFwBDAgAAAA==.Helaro:BAAANQAECgUIBQAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Henrymorgan:BAAANQAECggIBAAAAA==.Hexenbane:BAABNQAECn8jAAIVAAgKVwrCHAADAQAVAAgKVwrCHAADAQAAAA==.',
Ho='Holyghosst:BAAANQADCgEIAQAAAA==.',
Hu='Huffmetoes:BAEANQADCgMIBQABNQAECgoKMgAFAKYUAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgAOAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgYIGQAMAAYIAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAABNQAECn8ZAAMIAAgKwg5euAAiAQAIAAcKNg9euAAiAQAXAAIKYQ5uLABtAAAAAA==.Ikrys:BAABNQAECn8ZAAIcAAgKShWmDgAQAgAcAAgKShWmDgAQAgAAAA==.',
Il='Ilandrea:BAAANQABCgYIDgAAAA==.Ilarion:BAABNQAECn8hAAIDAAoKiw8DcQDZAQADAAoKiw8DcQDZAQAAAA==.Illiae:BAABNQAECn8sAAIWAAoKJySLFgBBAwAWAAoKJySLFgBBAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Incrdblestan:BAAANQAECgYIBgAAAA==.Insecure:BAAANQAECgQICgAAAA==.',
Io='Ionic:BAAANQAECggIEAAAAA==.',
Is='Issidora:BAABNQAECn8gAAIlAAcKMQUuNADFAAAlAAcKMQUuNADFAAAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8gAAIaAAoKFwpBjQDGAQAaAAoKFwpBjQDGAQAAAA==.Janeleonoc:BAAANQABCgEIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgoKQwAIAL0dAA==.Jascob:BAAANQAECgQIBgAAAA==.Jaynne:BAAANQAECgQIBQAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECn8hAAIeAAkKuBU9JQD6AQAeAAkKuBU9JQD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBgAAAA==.Kaashaa:BAABNQAECn9cAAIEAAoKeSI9EQBdAwAEAAoKeSI9EQBdAwAAAA==.Kaelsgf:BAABNQAECn81AAIFAAoKKB9HIADuAgAFAAoKKB9HIADuAgAAAA==.Kahllan:BAABNQAECn8tAAMLAAgK0BR9LABuAQALAAcK4RJ9LABuAQAMAAIKswWAjwAhAAAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCggIEwAAAA==.Kataltoholic:BAAANQAECgUIDgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kayser:BAAANQAECgQICAAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Keheo:BAAANQAECgYICAAAAA==.Kelfin:BAAANQAECgUIBQAAAA==.Kelinïsha:BAABNQAECn8dAAIXAAkKVAijFAAwAQAXAAkKVAijFAAwAQAAAA==.Kenf:BAAANQAECgEIAwAAAA==.Kensshaman:BAAANQAECgEIAgAAAA==.Kevinbacon:BAAANQAECgIIAQAAAA==.',
Kh='Khelina:BAAANQAECgcIDAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgcIDAAOAAAAAA==.',
Ki='Kiiras:BAAANQAECgcIDQAAAA==.Kimbodh:BAACNQAFFH8VAAIkAAYKpCHkAwBJAQAkAAYKpCHkAwBJAQA1AAQKfzoAAiQACgowJYAFAHoDACQACgowJYAFAHoDAAAA.Kimbubbles:BAAANQAECgUIBQAAAA==.Kimoora:BAAANQAECgQIBAABNQAECgUIBQAOAAAAAA==.Kimshady:BAAANQADCgcICAABNQAECgUIBQAOAAAAAA==.Kirathein:BAAANQAECgMIBgAAAA==.',
Kl='Klefthoof:BAABNQAECn8+AAMfAAoK2Qo2eAAzAQAfAAkKngk2eAAzAQAWAAgK0gixbgAlAQAAAA==.',
Ko='Kodey:BAABNQAECn8aAAIcAAkKpgqCCAAwAQAcAAkKpgqCCAAwAQAAAA==.',
Kr='Krelon:BAAANQADCggIFAAAAA==.Krimboz:BAAANQAECgYIDgAAAA==.Krystallight:BAABNQAECn84AAIiAAoKDCGfAgCTAgAiAAoKDCGfAgCTAgAAAA==.',
La='Laanda:BAAANQABCgIIAQABNQAECgUIDQAOAAAAAA==.Lanwulf:BAAANQAECgQIBAAAAA==.Lava:BAAANQAECgcIBwABNQAECgoKOQAgAKgeAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn9GAAIEAAoKDSBUHQC/AgAEAAoKDSBUHQC/AgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgYICwAOAAAAAA==.Leondero:BAABNQAECn8iAAIEAAkKCRs1MADcAgAEAAkKCRs1MADcAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAABNQAECn8cAAMoAAoKixF7HwAlAQATAAoKbA8yQwDZAQAoAAcKpw17HwAlAQABNQAECgEIAgAOAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAABNQAECn8vAAIDAAoKxA7tmQCDAQADAAoKxA7tmQCDAQAAAA==.',
Lo='Lofi:BAABNQAECn8fAAIfAAoKSAiEjwBiAQAfAAoKSAiEjwBiAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgcIEQAAAA==.',
Lu='Lubricated:BAAANQAECgcICgAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUICgAAAA==.',
Ly='Lycenia:BAAANQADCggICAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8wAAMEAAoKpiCuEQBaAwAEAAoKpiCuEQBaAwAlAAEKAADpmgAlAAAAAA==.',
Ma='Magicdreams:BAABNQAECn8lAAIMAAkKkQYGQwAGAQAMAAkKkQYGQwAGAQAAAA==.Mahll:BAAANQAECgIIAgABNQAECgoKNgAaAJgfAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8uAAIWAAkKIRktOgCOAgAWAAkKIRktOgCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Marihuano:BAAANQAECgEIAQAAAA==.Materia:BAABNQAECn8hAAIFAAoK3B0HHADnAgAFAAoK3B0HHADnAgAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAABNQAECn8gAAIQAAoKZxhJRgAeAgAQAAoKZxhJRgAeAgAAAA==.Meerchi:BAABNQAECn8aAAIIAAoKAAowfQCeAQAIAAoKAAowfQCeAQAAAA==.Meknin:BAABNQAECn80AAIIAAoKyAUMlABqAQAIAAoKyAUMlABqAQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgIIAQABNQAECggIBAAOAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgoKKgAjAIclAA==.',
Mi='Mickieta:BAABNQAECn9BAAIDAAoK1xxeNwB5AgADAAoK1xxeNwB5AgAAAA==.Mikalau:BAABNQAECn9DAAIEAAoKsBg2RQA1AgAEAAoKsBg2RQA1AgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAaAFceAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgoKKAANAMgcAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn9FAAMFAAoKaxqrMQChAgAFAAoKaxqrMQChAgAGAAgKGBlKIQAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgkJIgAfAHwKAA==.Mognel:BAABNQAECn8bAAIaAAoKgA5DWAC4AQAaAAoKgA5DWAC4AQAAAA==.Monklee:BAAANQADCgYIBgAAAA==.Moomootus:BAABNQAECn8rAAIDAAoKDh/eOADtAgADAAoKDh/eOADtAgAAAA==.Mordenkainen:BAAANQABCgYICgAAAA==.Motoraxe:BAABNQAECn8gAAIQAAoKhxG8igABAgAQAAoKhxG8igABAgAAAA==.Mozzie:BAAANQAECggICAAAAA==.',
My='Mystynight:BAAANQAECgQIBAAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Nekrautik:BAAANQAECggIEAAAAA==.Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8yAAMFAAoKphRHQABqAgAFAAoKphRHQABqAgAGAAkK7wzUKgDRAQAAAA==.Nightcrest:BAAANQAECgcIDAAAAA==.Nightrocks:BAAANQAECggIEAAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.Niyyx:BAAANQAECgYIEgAAAA==.',
No='Nomusa:BAAANQAECgQIBAAAAA==.Nordrydsh:BAAANQAECgQIBgABNQAFFAcIDgABALYJAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8TAAIQAAgKtxXBCwD2AQAQAAgKtxXBCwD2AQA1AAQKfzUAAhAACgpLIzkiAK8CABAACgpLIzkiAK8CAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
['Nô']='Nôva:BAAANQABCgUIBgAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFH8PAAIfAAgK6xvVBQANAgAfAAgK6xvVBQANAgA1AAQKfy0AAh8ACgp4I1oFALkDAB8ACgp4I1oFALkDAAAA.',
Oo='Oopositive:BAAANQAECgEIAQAAAA==.',
Or='Oraion:BAABNQAECn84AAMIAAoKTxp5NwBbAgAIAAoKTxp5NwBbAgAXAAEKthEQQQBCAAAAAA==.Orgarrot:BAAANQAECgYIBwABNQAECgoKSwAnAKsYAA==.',
Ot='Otimion:BAAANQAECgYIBgAAAA==.',
Ov='Ovarb:BAAANQAECgcICwAAAA==.',
Pa='Padwendyn:BAAANQAECgIIAgAAAA==.Pallydan:BAABNQAECn8dAAIJAAoKSRwWEAATAgAJAAoKSRwWEAATAgABNQAECgoKOAAIAE8aAA==.Pan:BAAANQAECgIIAgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECggIBwAAAA==.',
Ph='Phinix:BAAANQAECgYICQAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIAwAAAA==.',
Pr='Prisman:BAAANQAECgUIBQAAAA==.Proserpìne:BAABNQAECn8VAAIkAAcKQQjvPABhAQAkAAcKQQjvPABhAQAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Py='Pyramid:BAAANQAECggICAAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAACNQAFFH8JAAIIAAQKRAXnOACAAAAIAAQKRAXnOACAAAA1AAQKfycAAggACgrkF3+AAH0CAAgACgrkF3+AAH0CAAAA.',
Ra='Rabies:BAAANQADCgIIAgAAAA==.Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIBAAAAA==.Rainstormin:BAABNQAECn8iAAMMAAoKhwyqLACGAQAMAAoKdgyqLACGAQAnAAQK8QajVQBeAAAAAA==.Raitan:BAABNQAECn8aAAMRAAkKZR8qEQAUAgARAAkKZR8qEQAUAgAhAAUKQA/LGADeAAAAAA==.Raivoker:BAABNQAECn8XAAIBAAkKzhb8CgBnAgABAAkKzhb8CgBnAgABNQAECgkJGgARAGUfAA==.Rakarra:BAAANQAECggICAAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECn8tAAISAAoKXAxNMQB5AQASAAoKXAxNMQB5AQABNQADCgcIBwAOAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAABNQAECn8VAAIWAAkKsR5RFQC0AgAWAAkKsR5RFQC0AgAAAA==.Remsham:BAABNQAECn8cAAIPAAgK3QTtIQD1AAAPAAgK3QTtIQD1AAAAAA==.Renwyck:BAABNQAECn8qAAIjAAoKhyXFAADHAwAjAAoKhyXFAADHAwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECn86AAIDAAoK4B7oLQAQAwADAAoK4B7oLQAQAwAAAA==.',
Ro='Robane:BAABNQAECn8VAAIDAAQK6QcnLwGRAAADAAQK6QcnLwGRAAAAAA==.Rouen:BAABNQAECn8fAAQPAAkKfxn4FACsAQAPAAgKFhj4FACsAQAfAAUKLh1mnAA/AQAWAAEKhwY+OgExAAAAAA==.Roueyn:BAAANQAECgUICgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEBNQAECn8ZAAIMAAYKBgheXQCbAAAMAAYKBgheXQCbAAAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgoKSwAnAKsYAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQAECgQIBAABNQAECgoKOQAFALkZAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Santalight:BAAANQAECgEIAwABNQAFFAYIDgAeAKEXAA==.Santamoe:BAACNQAFFH8OAAIeAAYKoRdWBAB4AQAeAAYKoRdWBAB4AQA1AAQKf0cAAh4ACQrmIzwOAPsCAB4ACQrmIzwOAPsCAAAA.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECn81AAIEAAoK/iGRGAA3AwAEAAoK/iGRGAA3AwAAAA==.Sarwyn:BAAANQADCgcIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAoANoUAA==.',
Sc='Scratchs:BAAANQAECggIEQABNQADCgcIBwAOAAAAAA==.',
Se='Sedak:BAAANQADCggIIgAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAABNQAECn8iAAIgAAgKswTgSgDlAAAgAAgKswTgSgDlAAAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shelaan:BAABNQAECn8dAAIWAAcKewcShgDrAAAWAAcKewcShgDrAAAAAA==.Shiftey:BAABNQAECn8cAAIEAAgKRh4CTACKAgAEAAgKRh4CTACKAgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECggIHAAEAEYeAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAOAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICQAOAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn8zAAQbAAoKsxOqCgDJAQAbAAgKxBSqCgDJAQAaAAgK0Q22kwAeAQAcAAEKzgWFgQAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn88AAISAAoKByA3DgCuAgASAAoKByA3DgCuAgAAAA==.',
Sk='Skelmir:BAAANQADCgYICgAAAA==.',
Sn='Snicklfritz:BAAANQADCggICAAAAA==.Sniffum:BAAANQADCgMIAwAAAA==.Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn86AAMZAAoKHCYOBgAOAwAZAAoKDiYOBgAOAwAYAAgK9yC9EQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgYIBgAAAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAgAOAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAABNQAECn82AAIKAAoKohcSJwCAAgAKAAoKohcSJwCAAgAAAA==.',
St='Stanil:BAABNQAECn8hAAIEAAgKKwXSvwAYAQAEAAgKKwXSvwAYAQAAAA==.Steampunkz:BAAANQAECgIIAQAAAA==.Stellare:BAAANQAECggICQAAAA==.Strangetame:BAAANQADCgMIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgIIAgAAAA==.',
Su='Suelly:BAABNQAECn9DAAMIAAoKvR2pMgBsAgAIAAoKaBypMgBsAgAXAAQK9xrlHAAHAQAAAA==.Suguru:BAAANQAECggIEAAAAA==.Sularma:BAAANQAECggICgAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwAOAAAAAA==.Surasaurus:BAAANQAECgIIAgABNQAECgoKPAAmAP4VAA==.Suraschi:BAABNQAECn88AAImAAoK/hVmCAC9AQAmAAoK/hVmCAC9AQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQABNQAECgIIAgAOAAAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgYIEQAAAA==.Sylain:BAAANQADCggICQABNQAECgQIBwAOAAAAAA==.Synwav:BAABNQAECn8vAAMfAAoK/xrAMACeAgAfAAoK/xrAMACeAgAWAAEKAABxHAEAAAAAAA==.',
['Sá']='Sáilormoon:BAAANQAECgQIAwABNQAECgoKLAAWACckAA==.',
Ta='Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgUICQAAAA==.Tannatax:BAABNQAECn8lAAIfAAkK6RRqUgCxAQAfAAkK6RRqUgCxAQAAAA==.Tashah:BAAANQADCgYICwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAAOAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thauyia:BAAANQABCgYIBgABNQAECgUIDQAOAAAAAA==.Thewhitness:BAAANQAECgcICwAAAA==.Thewretch:BAABNQAECn8lAAIaAAkKcxnDSgDiAQAaAAkKcxnDSgDiAQAAAA==.Thumpthump:BAABNQAECn8gAAIlAAoKcxt1GgCBAgAlAAoKcxt1GgCBAgAAAA==.Thunderkiss:BAEANQADCggIFwABNQAECgYIGQAMAAYIAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.',
Tr='Tradewarrior:BAABNQAECn8xAAMQAAkKuSCBJwCXAgAQAAkKuSCBJwCXAgAhAAEKTR5OKQBVAAAAAA==.Trayth:BAAANQAECggIBwAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECn80AAMVAAoK1x/jBgB7AgAVAAoKzx7jBgB7AgAnAAQKiB/WMAAWAQAAAA==.Tsura:BAABNQAECn8hAAIKAAoK3BGYZgDkAQAKAAoK3BGYZgDkAQAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBwAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn88AAMdAAoKRSF2BgAxAwAdAAkK1yB2BgAxAwAeAAoKHSEqCADbAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgUIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgoKSwAnAKsYAA==.',
Va='Vaeryn:BAAANQAECgcIDgABNQAECgoKYwAFANEeAA==.Valhen:BAABNQAECn9jAAQFAAoK0R5XEwAtAwAFAAoKWB5XEwAtAwAHAAcKgRZ4CADeAQAGAAYK/w5DMQDrAAAAAA==.Valryn:BAAANQAECgQIBAABNQAECgoKYwAFANEeAA==.Valrys:BAAANQADCgUIBQABNQAECgoKYwAFANEeAA==.Valtar:BAABNQAECn8zAAIfAAoK8iH6BwCCAwAfAAoK8iH6BwCCAwAAAA==.',
Ve='Velryn:BAAANQADCggIFAABNQAECgoKYwAFANEeAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQAECgcICAAAAA==.Vilevixon:BAABNQAECn9BAAMGAAoKXhoZFgCsAgAGAAoKXhoZFgCsAgAHAAEKvAjrLQApAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAAOAAAAAA==.Wanlok:BAABNQAECn8eAAMbAAkKWhU/DABhAQAbAAkKmBQ/DABhAQAaAAUKkgpR/ADTAAAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQAECgIIAgAAAA==.Warriorlobo:BAABNQAECn8pAAQQAAkK6RUjkAD0AQAQAAkK6RUjkAD0AQARAAMKmA1wNQBbAAAhAAEKdAqaNQAvAAABNQAECgoKQwAIAL0dAA==.Watts:BAABNQAECn88AAIEAAoKgx/WHgC4AgAEAAoKgx/WHgC4AgABNQAFFAQICQAIAEQFAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.Werebeer:BAAANQAECgEIAQAAAA==.',
Wi='Wildfang:BAABNQAECn82AAMEAAoKihBxYgDoAQAEAAoKihBxYgDoAQAlAAIK/gF5cAAmAAAAAA==.Wildside:BAABNQAECn8bAAIEAAoKHRaeTQCFAgAEAAoKHRaeTQCFAgAAAA==.',
Xa='Xandronys:BAABNQAECn8vAAQbAAoKlBURBwAyAgAbAAoKlBURBwAyAgAaAAYKwxC41wAaAQAcAAEKvgnMeQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgQIBgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAAOAAAAAA==.Yalla:BAAANQAECgYICwAAAA==.',
Ye='Yeet:BAAANQAECggIDwAAAA==.',
Yu='Yuridak:BAAANQAECgcIBwABNQAECgkJJgAdADYVAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalckar:BAAANQAECggIEgAAAA==.Zanos:BAAANQAECgEIAQAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAABNQAECn81AAIcAAoK5hxTAQCvAgAcAAoK5hxTAQCvAgAAAA==.Zendead:BAAANQAECggIEAAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgcIDQAAAA==.Zurii:BAAANQADCgEIAQAAAA==.Zurokhan:BAABNQAECn9OAAIKAAoKXx+hEwANAwAKAAoKXx+hEwANAwAAAA==.',
['Zø']='Zønda:BAABNQAECn9EAAMhAAkKUCUBBwA1AgAhAAYKUiYBBwA1AgAQAAYKCiTvbwCcAQAAAA==.',
['Ða']='Ðagon:BAAANQAECggIDQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAABNQAECn8aAAIGAAkKDAZjKgAZAQAGAAkKDAZjKgAZAQAAAA==.',
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
