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

local lookup = {'Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Mage-Arcane','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Assassination','Druid-Guardian',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abnee:BAAANQAECgIIAgAAAA==.',
Ac='Acacia:BAABNQAECn8bAAMBAAcKFQxEQQAdAQABAAYKwQxEQQAdAQACAAYKlg09cgABAQAAAA==.',
Ad='Adowyrm:BAACNQAFFH8SAAIDAAcK0hMLBwDhAQADAAcK0hMLBwDhAQA1AAQKfygAAgMACgpEIGwIAB0DAAMACgpEIGwIAB0DAAAA.Adrielle:BAAANQAECgYICwAAAA==.',
Ai='Airali:BAABNQAECn8wAAIEAAoK+Q9PjAANAgAEAAoK+Q9PjAANAgAAAA==.Airedale:BAABNQAECn8gAAIFAAgKXw8FVwCYAQAFAAgKXw8FVwCYAQAAAA==.',
Ak='Akairo:BAACNQAFFH8cAAIGAAcKhBxOBAARAgAGAAcKhBxOBAARAgA1AAQKf0IABAYACgoGJCIHAIwDAAYACgoGJCIHAIwDAAcABwq4EiggAAcBAAgAAQo1AQYzABoAAAAA.Akelia:BAAANQAECgUIBQAAAA==.',
Al='Aleebobwa:BAAANQAECgEIAQABNQAECgoKJwAJAKQdAA==.Alexanderlx:BAABNQAECn8pAAMKAAkKexwiDADoAQAKAAgKKSEiDADoAQAEAAUKzgyI2gC0AAAAAA==.Aleybobwa:BAABNQAECn8nAAMJAAoKpB2qHAABAwAJAAoKpB2qHAABAwAEAAUKWhOGAQEdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQAECgEIAQAAAA==.Althalas:BAAANQAECgIIAgAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn8uAAMBAAoKgR+kDgDpAgABAAoKgR+kDgDpAgACAAIKpwQXtwAqAAAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn87AAMLAAoKBx3EAgAlAwALAAoKZBzEAgAlAwAMAAMKLRPsKwDFAAAAAA==.Antithanatos:BAAANQAECgIIBAABNQAECgQIBwANAAAAAA==.',
Ao='Aolus:BAABNQAECn8zAAICAAoKERxMGQD9AgACAAoKERxMGQD9AgAAAA==.',
Ap='Apoliis:BAAANQAECgYIEAAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQAECggICAAAAA==.Archis:BAABNQAECn8oAAMOAAoKgxVpZABhAgAOAAoKgxVpZABhAgAPAAYKIgjeJgAKAQAAAA==.Arcidaes:BAEBNQAECn8oAAIQAAgK5Q4ILgA3AQAQAAgK5Q4ILgA3AQAAAA==.Arez:BAAANQADCgEJAQABNQAECgoKHAARAB0JAA==.',
As='Astryd:BAAANQAECgIIBAAAAA==.Asurna:BAABNQAECn8dAAISAAkKrBRXCwDrAQASAAkKrBRXCwDrAQAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQAECgEIAQAAAA==.',
Av='Avaline:BAAANQAECgEIAQAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8MAAMTAAUKZBvdCgD3AAATAAUKZBvdCgD3AAAUAAIK6wvDAgCQAAA1AAQKfyYAAxQACQo1JPoBAFADABQACQpHIvoBAFADABMABQodJIweAN0BAAAA.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azaelleonoc:BAAANQAECgEIBAAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUIBwABNQAECgoKMwAVANcfAA==.Baeli:BAAANQAECgMIBAAAAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAABNQAECn8aAAMMAAkKkxqAEwAXAgAMAAgKtBiAEwAXAgADAAMKYAs/IgCJAAAAAA==.Baliw:BAABNQAECn8lAAICAAkK/Q0dPAAUAgACAAkK/Q0dPAAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAABNQAECn8bAAIFAAgKahVjUQCoAQAFAAgKahVjUQCoAQAAAA==.Banugg:BAAANQADCgMIAwAAAA==.Barcode:BAAANQADCgMIBAAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8JAAIWAAYKpQpdDwB5AQAWAAYKpQpdDwB5AQA1AAQKfzUAAhYACgqIIC4MAMgCABYACgqIIC4MAMgCAAAA.',
Bc='Bchung:BAABNQAECn8xAAMXAAoKJx06BQDDAgAXAAoKJx06BQDDAgARAAgKMxYzswAdAgAAAA==.',
Be='Bean:BAAANQAECgYIAwAAAA==.Bela:BAAANQAECgQIBgAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgkJHQASAKwUAA==.Belthor:BAAANQAECgEIAQAAAA==.Bertus:BAACNQAFFH8dAAMYAAcKaiX/AAASAgAYAAcKaiX/AAASAgAZAAQK8yE3CgBuAQA1AAQKfykAAxkACgqbJbcUABMDABkACQpGJbcUABMDABgACAoZJM4gAIcCAAAA.Bettybop:BAAANQAECgEIAQABNQAECgEIBAANAAAAAA==.',
Bh='Bhain:BAABNQAECn8fAAIWAAkKYRw6LADNAgAWAAkKYRw6LADNAgABNQAFFAQIBAANAAAAAA==.',
Bi='Bieorne:BAABNQAECn8gAAIZAAgKYxeWGgChAQAZAAgKYxeWGgChAQAAAA==.',
Bl='Blikefire:BAAANQAECgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAwAAAA==.Boku:BAAANQAECgQIBAAAAA==.Boodidy:BAAANQADCgUIBQAAAA==.Boondocks:BAABNQAECn8vAAQaAAoKihJJNgDRAQAaAAkKEhJJNgDRAQAbAAQKPBAQFwDZAAAcAAEKlAWlgQAqAAAAAA==.Bottomx:BAABNQAECn8oAAIMAAoKtgrDCgA+AQAMAAoKtgrDCgA+AQAAAA==.',
Br='Braca:BAABNQAECn8jAAMdAAgKCRkbFwALAgAdAAgKCRkbFwALAgAeAAEKAADhaQA4AAAAAA==.Bread:BAAANQADCggIEwAAAA==.Brielle:BAABNQAECn8zAAIFAAkKdRP3QgDYAQAFAAkKdRP3QgDYAQAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgYIDQAAAA==.Brudene:BAABNQAECn8iAAIOAAgKfQuifgAXAQAOAAgKfQuifgAXAQABNQAECggIOQARAMETAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIBQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwANAAAAAA==.Bullymaguire:BAAANQAECgYIBgABNQAFFAcIEAAWAJEdAA==.',
Ca='Carpe:BAAANQAECgYIEAAAAA==.Carreth:BAAANQAECggICAAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn8/AAIOAAoK/hbRLwAZAgAOAAoK/hbRLwAZAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFH8fAAIOAAcKZCJiAwDQAQAOAAcKZCJiAwDQAQA1AAQKfzYAAg4ACgqbJgIHALsDAA4ACgqbJgIHALsDAAAA.Checkurback:BAABNQAECn8VAAIQAAkKKxwPJACYAgAQAAkKKxwPJACYAgAAAA==.Chewtum:BAAANQAECgYICQAAAA==.Chimo:BAABNQAECn8gAAIfAAcKjAtZYQAaAQAfAAcKjAtZYQAaAQAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgoKMQARALQdAA==.',
Cl='Cleavatron:BAAANQAECgIIAwABNQADCgcIBwANAAAAAA==.',
Co='Cobellex:BAAANQAECgEIBQAAAA==.Cops:BAABNQAECn8rAAIJAAgKrB8lKQDEAgAJAAgKrB8lKQDEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Crusherk:BAAANQAECggIAwAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgUIEQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgkJGQAOAJ4XAA==.Darkenergy:BAABNQAECn8vAAIgAAoKCiFEDQB5AgAgAAoKCiFEDQB5AgAAAA==.Darà:BAAANQADCgcIBwABNQAECgcIJAABAFARAA==.Dashyll:BAAANQAECgcIDAAAAA==.Dazzled:BAAANQAECgEIAQAAAA==.',
De='Deadlegslul:BAABNQAECn8lAAIFAAcKCh3ORgDKAQAFAAcKCh3ORgDKAQAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIBAAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgoKMwAVANcfAA==.Demacus:BAABNQAECn8aAAMRAAcK0AMk0wCqAAARAAcKMAMk0wCqAAAXAAIK3QbOOQBXAAABNQAECgkJMAAfAHsKAA==.Demeter:BAABNQAECn8jAAIKAAcKfRIZHAAcAQAKAAcKfRIZHAAcAQAAAA==.Denalli:BAABNQAECn8UAAIXAAcKCgZ1HAAMAQAXAAcKCgZ1HAAMAQAAAA==.Devouress:BAAANQAECgEIAwAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQAECgEIAQAAAA==.Dirgen:BAABNQAECn8jAAIhAAcKDxWlDgDEAQAhAAcKDxWlDgDEAQAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAAANQAECgQICwAAAA==.Dogslobber:BAAANQAECgEIAQAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Dorkma:BAAANQAECgEIAgAAAA==.Doublenickel:BAABNQAECn8WAAIJAAkKABHGggCSAQAJAAkKABHGggCSAQAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQICAABNQAECgEIAwANAAAAAA==.Drat:BAABNQAECn8aAAMFAAcK1QmlfwAzAQAFAAcKrAilfwAzAQAiAAUKvginDAAIAQAAAA==.Dreamsicle:BAAANQABCgcIBQAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drizztbane:BAAANQAECgEIAQAAAA==.Drustan:BAAANQADCgIIAgABNQAECgoKIgAjANAkAA==.',
Du='Duridon:BAAANQAECgIIAgAAAA==.',
Dy='Dyorna:BAAANQADCgcIDAAAAA==.',
Eb='Ebojager:BAABNQAECn8sAAIkAAkKGxiTEQDRAQAkAAkKGxiTEQDRAQAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFH8JAAIZAAYKkhA/BADtAQAZAAYKkhA/BADtAQA1AAQKfx0AAhkACgqoIG4uAHcCABkACgqoIG4uAHcCAAAA.',
El='Eldric:BAABNQAECn85AAIRAAgKwROxtQAYAgARAAgKwROxtQAYAgAAAA==.Elvispriesty:BAAANQAECgQICAAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwAEABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.Entropathy:BAAANQAECgIIAgABNQAECgEIAwANAAAAAA==.',
Er='Ere:BAABNQAECn8cAAMRAAoKHQkKvwDKAAARAAoKHQkKvwDKAAAXAAEKAAChQQBBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Escalope:BAAANQAECgEIAgAAAA==.Eskath:BAABNQAECn8gAAMaAAcK1BiWcwATAQAaAAcK1BiWcwATAQAbAAEKqRz8FwBJAAABNQAECgkJKwARABQYAA==.Essential:BAABNQAECn8mAAIEAAoK3xHkfQAuAgAEAAoK3xHkfQAuAgAAAA==.',
Ev='Evavaria:BAABNQAECn8bAAIJAAgKDBiwUwAfAgAJAAgKDBiwUwAfAgABNQADCgQIBAANAAAAAA==.Evdoggy:BAAANQAECgYIEAAAAA==.Eveleonoc:BAAANQAECgIIBAAAAA==.',
Ex='Exterminate:BAAANQAECgMICQAAAA==.',
Fa='Fatalism:BAAANQADCggIDQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQAECgcIDgABNQAECgoKLgAGAKYUAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwANAAAAAA==.Ferrara:BAACNQAFFH8SAAMlAAcKBCDaAwBGAgAlAAcKBCDaAwBGAgAFAAEKAABFLgBlAAA1AAQKfygAAiUACgpEI9UPAOsCACUACgpEI9UPAOsCAAAA.',
Fi='Filthi:BAAANQAFFAEIAQAAAA==.Fiz:BAAANQADCgYIBgABNQAECggIDAANAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwANAAAAAA==.',
Fl='Flandri:BAACNQAFFH8QAAIGAAYKQBDOEQCBAQAGAAYKQBDOEQCBAQA1AAQKfyQAAgYACgrzIlMRAD0DAAYACgrzIlMRAD0DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgcIIAAfAIwLAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQADCgQIBAANAAAAAA==.Friedá:BAAANQAECggICgAAAA==.Frostednip:BAABNQAECn84AAMYAAoKBB3oFADlAgAYAAoKBB3oFADlAgAZAAIKYQWFzwBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAgAAAA==.Gabiru:BAABNQAECn8sAAIDAAoKNBt0CQALAwADAAoKNBt0CQALAwAAAA==.Gadreeste:BAAANQAECgcICQAAAA==.Galnarn:BAACNQAFFH8SAAImAAYK6yGSAQAEAgAmAAYK6yGSAQAEAgA1AAQKfzEAAiYACgo5JXQBAPQCACYACgo5JXQBAPQCAAAA.Gambagood:BAAANQAECgIICAAAAA==.Gank:BAECNQAFFH8cAAImAAYKKxxSAQBNAQAmAAYKKxxSAQBNAQA1AAQKfzAAAyYACgqlIQoHANICACYACgo4HgoHANICAB4ACQppHzIZAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgkJGgAMAJMaAA==.Garlicbae:BAAANQAECgMIBAAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUICgAAAA==.',
Ge='Gefaustet:BAABNQAECn8vAAIPAAoKcBXECADEAQAPAAoKcBXECADEAQAAAA==.Gewch:BAAANQAECgEIAgAAAA==.',
Gl='Glorp:BAAANQAECgEIAQAAAA==.Glyd:BAAANQAECgYICgABNQAECgkJMAAfAHsKAA==.',
Go='Goldenred:BAAANQAECgUIEQAAAA==.',
Gr='Graybrew:BAAANQAECgQIBgAAAA==.Graye:BAAANQADCgYIBgABNQAECgQIBgANAAAAAA==.Grayes:BAAANQAECgYIEwABNQAECgQIBgANAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgQIBgANAAAAAA==.Grelin:BAABNQAECn8UAAInAAgKvxFNKQDMAAAnAAgKvxFNKQDMAAAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggIDAAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAQICAAnAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwANAAAAAA==.Harmôny:BAAANQAECgEIAQAAAA==.Hatredno:BAAANQAECgQIBQAAAA==.Hatredyes:BAABNQAECn85AAIoAAoKWBfECgATAgAoAAoKWBfECgATAgAAAA==.',
He='Helare:BAABNQAECn8xAAICAAoKZRRKFAAKAgACAAoKZRRKFAAKAgAAAA==.Helaro:BAAANQAECgUIBgAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAABNQAECn8aAAIVAAcKxQmLGADAAAAVAAcKxQmLGADAAAAAAA==.',
Ho='Holybattler:BAAANQAECgEIAwAAAA==.Holyghosst:BAAANQADCgEIAQAAAA==.',
Hu='Huffmetoes:BAEANQADCgMIAwABNQAECgoKLgAGAKYUAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQAECgIIBAAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAwANAAAAAA==.',
Id='Idlewild:BAEANQAECgEIAQABNQAECgYIGQACAAYIAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAwAAAA==.Ikor:BAABNQAECn8ZAAMRAAgKwg5xiQAwAQARAAcKNg9xiQAwAQAXAAIKYQ6UHwBxAAAAAA==.Ikrys:BAAANQAECgcIEwAAAA==.',
Il='Ilandrea:BAAANQAECgEIAQAAAA==.Ilarion:BAAANQAECggIEQAAAA==.Illiae:BAABNQAECn8oAAIWAAoKKSOLFgBBAwAWAAoKKSOLFgBBAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgQIDgAAAA==.',
Io='Ionic:BAAANQAECggIEQAAAA==.',
Is='Issidora:BAABNQAECn8ZAAIlAAcKBAUDKADDAAAlAAcKBAUDKADDAAAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ix='Ix:BAAANQAECgEIAQAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8gAAIaAAoKFwpBjQDGAQAaAAoKFwpBjQDGAQAAAA==.Janeleonoc:BAAANQAECgIIBQAAAA==.Janja:BAAANQABCgIIAgABNQAECgoKMQARALQdAA==.Jascob:BAAANQAECgUICAAAAA==.Jaynne:BAAANQAECgQIBwAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQAECgEIAwAAAA==.',
Ju='Judokeg:BAABNQAECn8hAAIeAAkKuBU9JQD6AQAeAAkKuBU9JQD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBgAAAA==.Kaashaa:BAABNQAECn9BAAIFAAoKdSA9EQBdAwAFAAoKdSA9EQBdAwAAAA==.Kaelsgf:BAABNQAECn8xAAIGAAoKcR5HIADuAgAGAAoKcR5HIADuAgAAAA==.Kahllan:BAABNQAECn8kAAIBAAcKUBHBHgBqAQABAAcKUBHBHgBqAQAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCggIEwAAAA==.Kataltoholic:BAAANQAECgUIDwAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kayser:BAAANQAECgQICAAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Keheo:BAAANQADCggICgAAAA==.Kelfin:BAAANQAECgUIBQAAAA==.Kelinïsha:BAABNQAECn8dAAIXAAkKVAjGDAA8AQAXAAkKVAjGDAA8AQAAAA==.Kenf:BAAANQAECgEIBgAAAA==.Kensshaman:BAAANQAECgEIBAAAAA==.Kevinbacon:BAAANQAECgIIAwAAAA==.',
Kh='Khelina:BAAANQAECgcIDAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgcIDAANAAAAAA==.',
Ki='Kiiras:BAAANQAECggIDgAAAA==.Kimbodh:BAACNQAFFH8VAAIkAAYKpCEAAgBnAQAkAAYKpCEAAgBnAQA1AAQKfzIAAiQACgo3JIAFAHoDACQACgo3JIAFAHoDAAAA.Kimbubbles:BAAANQAECgUIBQAAAA==.Kimoora:BAAANQAECgQIBAABNQAECgUIBQANAAAAAA==.Kimshady:BAAANQAECgEIAQABNQAECgUIBQANAAAAAA==.Kirathein:BAAANQAECgIIAwAAAA==.',
Kl='Klefthoof:BAABNQAECn8wAAMfAAkKewq8eQDTAAAfAAgK7gm8eQDTAAAWAAcKNwdWawDNAAAAAA==.',
Ko='Kodey:BAABNQAECn8aAAIcAAkKpgpUBQA9AQAcAAkKpgpUBQA9AQAAAA==.',
Kr='Krelon:BAAANQADCggIFAAAAA==.Krimboz:BAAANQAECgYIEAAAAA==.Krystallight:BAABNQAECn8vAAIiAAkK/yEMAwDtAgAiAAkK/yEMAwDtAgAAAA==.',
La='Lanwulf:BAAANQAECgQIBAAAAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn89AAIFAAoKWh5+LgDiAgAFAAoKWh5+LgDiAgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgYICQANAAAAAA==.Leondero:BAABNQAECn8iAAIFAAkKCRs1MADcAgAFAAkKCRs1MADcAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAABNQAECn8ZAAMnAAkKlhFOFwBBAQATAAkKKg8sNQCXAQAnAAcKpw1OFwBBAQABNQAECgEIAwANAAAAAA==.',
Li='Lintilla:BAAANQAECgEIAQAAAA==.',
Ll='Llevanya:BAABNQAECn8qAAIEAAoKuQ1trwDAAQAEAAoKuQ1trwDAAQAAAA==.',
Lo='Lofi:BAABNQAECn8dAAIfAAoKRAiEjwBiAQAfAAoKRAiEjwBiAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgYIEAAAAA==.',
Lu='Lubricated:BAAANQAECgYICgAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUIDAAAAA==.',
Ly='Lycenia:BAAANQADCggICAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8wAAMFAAoKpiCuEQBaAwAFAAoKpiCuEQBaAwAlAAEKAADpmgAlAAAAAA==.',
Ma='Magicdreams:BAABNQAECn8cAAICAAgKKwZuOgDdAAACAAgKKwZuOgDdAAAAAA==.Mahll:BAAANQAECgIIAgABNQAECgoKLAAaAOMdAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8uAAIWAAkKIRktOgCOAgAWAAkKIRktOgCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Marihuano:BAAANQAECgEIAQAAAA==.Materia:BAABNQAECn8eAAIGAAoKxBsDEQDkAgAGAAoKxBsDEQDkAgAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAABNQAECn8ZAAIOAAkKnhfxPADdAQAOAAkKnhfxPADdAQAAAA==.Meerchi:BAABNQAECn8ZAAIRAAkKoApAaAB4AQARAAkKoApAaAB4AQAAAA==.Meknin:BAABNQAECn8uAAIRAAoKOgVEcQBjAQARAAoKOgVEcQBjAQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgEIBQABNQAECggIBQANAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgoKIgAjANAkAA==.',
Mi='Mickieta:BAABNQAECn8vAAIEAAoKmRrrMgAuAgAEAAoKmRrrMgAuAgAAAA==.Mikalau:BAABNQAECn84AAIFAAoKExirKQA6AgAFAAoKExirKQA6AgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAaAFceAA==.Minishields:BAAANQAECgMIBQAAAA==.Missteek:BAAANQAECgIIBwABNQAECgkJGgAMAJMaAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn8zAAMGAAoKvhmrMQChAgAGAAoKvhmrMQChAgAHAAgKrRdKIQAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgcIIAAfAIwLAA==.Mognel:BAABNQAECn8YAAIaAAkKqA7eSgCEAQAaAAkKqA7eSgCEAQAAAA==.Moomootus:BAABNQAECn8rAAIEAAoKDh/eOADtAgAEAAoKDh/eOADtAgAAAA==.Mordenkainen:BAAANQAECgEIAQAAAA==.Motoraxe:BAABNQAECn8fAAIOAAoKhxG8igABAgAOAAoKhxG8igABAgAAAA==.Mozzie:BAAANQAECggICAAAAA==.',
My='Mystynight:BAAANQAECgEIAgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQAECgEIAQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8uAAMGAAoKphRHQABqAgAGAAoKphRHQABqAgAHAAkK7wzUKgDRAQAAAA==.Nightcrest:BAAANQAECgYICQAAAA==.Nightreign:BAAANQAECgEIAQAAAA==.Nightrocks:BAAANQAECggIEQAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQAECgEIAQAAAA==.Niyyx:BAAANQAECgcIDgAAAA==.',
No='Nomusa:BAAANQAECgEIAQAAAA==.Nordrydsh:BAAANQAECgMIAwABNQAFFAcIDgADALYJAA==.Noslock:BAAANQAECgEIAQAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8RAAIOAAcK/BbBCwD2AQAOAAcK/BbBCwD2AQA1AAQKfzMAAg4ACgpLI60RANgCAA4ACgpLI60RANgCAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
['Nô']='Nôva:BAAANQAECgEIAQAAAA==.',
Oc='Occultfish:BAAANQAECgIIAwAAAA==.',
Ol='Olimdar:BAACNQAFFH8NAAIfAAcK4RrVBQANAgAfAAcK4RrVBQANAgA1AAQKfysAAh8ACgoxIZYEAJIDAB8ACgoxIZYEAJIDAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAABNQAECn8rAAMRAAkKFBjdXgCRAQARAAgKJBndXgCRAQAXAAEKthEQQQBCAAAAAA==.Orgarrot:BAAANQAECgEIAQABNQAECgoKOQAoAFgXAA==.',
Ot='Otimion:BAAANQAECgcIBwAAAA==.',
Ov='Ovarb:BAAANQAECgcICwAAAA==.',
Pa='Padwendyn:BAAANQAECgIIAgAAAA==.Pallydan:BAABNQAECn8aAAIKAAkKjxuZDQDIAQAKAAkKjxuZDQDIAQABNQAECgkJKwARABQYAA==.Pan:BAAANQAECgIIAgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECggIBwAAAA==.',
Ph='Phinix:BAAANQAECgMIBQAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgMIAwAAAA==.',
Pr='Prisman:BAAANQAECgUIBgAAAA==.Proserpìne:BAABNQAECn8VAAIkAAcKQQjvPABhAQAkAAcKQQjvPABhAQAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAACNQAFFH8JAAIRAAQKRAUhKgCIAAARAAQKRAUhKgCIAAA1AAQKfycAAhEACgrkF3+AAH0CABEACgrkF3+AAH0CAAAA.',
Ra='Rabies:BAAANQADCgIIAgAAAA==.Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIBwAAAA==.Rainstormin:BAABNQAECn8fAAMCAAoKdgzHHQCcAQACAAoKdgzHHQCcAQAoAAMKmAUlXQA7AAAAAA==.Raitan:BAAANQAECgcIEQABNQAECgkJFwADAM4WAA==.Raivoker:BAABNQAECn8XAAIDAAkKzhbeBgB1AgADAAkKzhbeBgB1AgAAAA==.Rakarra:BAAANQAECggICAAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECn8kAAIQAAoKIQnrKABUAQAQAAoKIQnrKABUAQABNQADCgcIBwANAAAAAA==.Razgrize:BAAANQAECgMIBAAAAA==.',
Re='Reilin:BAAANQAECggIEgAAAA==.Remsham:BAAANQAECgYIEwAAAA==.Renwyck:BAABNQAECn8iAAIjAAoK0CTFAADHAwAjAAoK0CTFAADHAwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECn8yAAIEAAoKHx7oLQAQAwAEAAoKHx7oLQAQAwAAAA==.',
Ro='Robane:BAAANQAECgQIDQAAAA==.Rouen:BAABNQAECn8XAAQSAAcKdhhoEgBeAQASAAcKdhhoEgBeAQAfAAQKahtmnAA/AQAWAAEKhwY+OgExAAAAAA==.Roueyn:BAAANQAECgUIBQAAAA==.',
Ru='Rubidea:BAAANQAECgMIBgAAAA==.Ruckus:BAEBNQAECn8ZAAICAAYKBgjDRwCmAAACAAYKBgjDRwCmAAAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgoKOQAoAFgXAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQAECgQIBAABNQAECgoKMQAGAEgZAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Santalight:BAAANQAECgEICAABNQAFFAUIDQAeAAQZAA==.Santamoe:BAACNQAFFH8NAAIeAAUKBBmWAwAyAQAeAAUKBBmWAwAyAQA1AAQKfzsAAh4ACQp9IzwOAPsCAB4ACQp9IzwOAPsCAAAA.Saraelin:BAAANQAECgMIBAAAAA==.Saray:BAABNQAECn8vAAIFAAoK/iH9EQC/AgAFAAoK/iH9EQC/AgAAAA==.Sarwyn:BAAANQADCgcIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAnANoUAA==.',
Sc='Scratchs:BAAANQAECgQIBAABNQADCgcIBwANAAAAAA==.',
Se='Sedak:BAAANQAECgEIAQAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAABNQAECn8WAAIgAAcKwQN1SAClAAAgAAcKwQN1SAClAAAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shelaan:BAAANQAECgYIEAAAAA==.Shiftey:BAABNQAECn8YAAIFAAgKoR0CTACKAgAFAAgKoR0CTACKAgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECggIGAAFAKEdAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgANAAAAAA==.Shockzstuff:BAAANQAECgEIBAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICwANAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn8uAAQbAAoKUBKqCgDJAQAbAAgKdhOqCgDJAQAaAAgKxQxbbgAhAQAcAAEKzgWFgQAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn8rAAIQAAoK0x1KHQDGAgAQAAoK0x1KHQDGAgAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snicklfritz:BAAANQADCggICAAAAA==.Sniffum:BAAANQADCgMIAwAAAA==.Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn86AAMZAAoKHCbBAgAzAwAZAAoKDibBAgAzAwAYAAgK9yC9EQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgYIBwAAAA==.Sophialeonoc:BAAANQAECgEIAgAAAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAwANAAAAAA==.Sprintd:BAAANQAECgEIAQAAAA==.Sprodage:BAABNQAECn8kAAIJAAkKHhh9LgDtAQAJAAkKHhh9LgDtAQAAAA==.',
St='Stanil:BAABNQAECn8bAAIFAAgKywSdmgD7AAAFAAgKywSdmgD7AAAAAA==.Steampunkz:BAAANQAECgIIBAAAAA==.Stellare:BAAANQAECgYIBwAAAA==.Strangetame:BAAANQAECgEIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgIICAAAAA==.',
Su='Suelly:BAABNQAECn8xAAMRAAoKtB1NKgBKAgARAAoKMhxNKgBKAgAXAAQK9xrlHAAHAQAAAA==.Suguru:BAABNQAECn8VAAMGAAkK+gihdwC0AQAGAAkK+gihdwC0AQAHAAMKFwbgYAB+AAAAAA==.Sularma:BAAANQAECgcICwAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwANAAAAAA==.Suraschi:BAABNQAECn8sAAImAAkKXhUsDwD+AQAmAAkKXhUsDwD+AQAAAA==.',
Sw='Swisscake:BAAANQAECgEIBAAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgcIEgAAAA==.Sylain:BAAANQADCggICQABNQAECgUICAANAAAAAA==.Synwav:BAABNQAECn8sAAMfAAoK/xrAMACeAgAfAAoK/xrAMACeAgAWAAEKAADu5QAAAAAAAA==.',
['Sá']='Sáilormoon:BAAANQAECgQIBAABNQAECgoKKAAWACkjAA==.',
Ta='Taiani:BAAANQAECgEIAQAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgUICgAAAA==.Tannatax:BAABNQAECn8iAAIfAAgKYBX7RACCAQAfAAgKYBX7RACCAQAAAA==.Tarishababy:BAAANQAECgEIAQAAAA==.Tashah:BAAANQADCgYICwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Tekvet:BAAANQAECggIBQAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thauyia:BAAANQAECgEIAQABNQAECgUICwANAAAAAA==.Thewhitness:BAAANQAECgcICwAAAA==.Thewretch:BAABNQAECn8iAAIaAAgKwxlVPwCsAQAaAAgKwxlVPwCsAQAAAA==.Thumpthump:BAABNQAECn8ZAAIlAAkKtRt1GgCBAgAlAAkKtRt1GgCBAgAAAA==.Thunderkiss:BAEANQAECgEIAwABNQAECgYIGQACAAYIAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Torcamada:BAAANQAECgEIAgABNQAECgEIBAANAAAAAA==.Toscus:BAAANQADCgMIAwAAAA==.Totemii:BAAANQAECgEIAgAAAA==.',
Tr='Tradewarrior:BAABNQAECn8qAAMOAAkKnB5GHQCFAgAOAAkKnB5GHQCFAgAhAAEKTR4qHABbAAAAAA==.Trayth:BAAANQAECggIDgAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDgAAAA==.',
Ts='Tshark:BAABNQAECn8zAAMVAAoK1x8wAwCuAgAVAAoKzx4wAwCuAgAoAAMKpCDWMAAWAQAAAA==.Tsura:BAABNQAECn8cAAIJAAkK5hCYZgDkAQAJAAkK5hCYZgDkAQAAAA==.',
Tu='Tutatotao:BAAANQAECgEIBAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn8uAAMdAAoKRSF2BgAxAwAdAAkK1yB2BgAxAwAeAAoKchw8FQCqAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgUIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgoKOQAoAFgXAA==.',
Va='Vaeryn:BAAANQAECgYIDwABNQAECgoKVQAGANEeAA==.Valhen:BAABNQAECn9VAAQGAAoK0R4FCQBMAwAGAAoKWB4FCQBMAwAIAAcKgRZ4CADeAQAHAAQKbwicYQB6AAAAAA==.Valryn:BAAANQAECgUIBQABNQAECgoKVQAGANEeAA==.Valtar:BAABNQAECn8rAAIfAAoK3yH6BwCCAwAfAAoK3yH6BwCCAwAAAA==.',
Ve='Veliraleonoc:BAAANQAECgEIAQAAAA==.Velryn:BAAANQADCggIFAABNQAECgoKVQAGANEeAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQAECgcICQAAAA==.Vilevixon:BAABNQAECn8vAAMHAAoKKRoZFgCsAgAHAAoKKRoZFgCsAgAIAAEKvAjrLQApAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAANAAAAAA==.Wanlok:BAABNQAECn8cAAMbAAgK4BOMBwA4AQAbAAgK+RKMBwA4AQAaAAUKkgpR/ADTAAAAAA==.Wantoo:BAAANQAECgEIAgAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQAECgEIAgAAAA==.Warriorlobo:BAABNQAECn8lAAQOAAkKWhUjkAD0AQAOAAkKWhUjkAD0AQAPAAMKmA3sJgBhAAAhAAEKdAqaNQAvAAABNQAECgoKMQARALQdAA==.Watts:BAABNQAECn8yAAIFAAoK5hpQJABTAgAFAAoK5hpQJABTAgABNQAFFAQICQARAEQFAA==.',
We='Weez:BAAANQAECgEIAQAAAA==.',
Wi='Wildfang:BAABNQAECn8vAAMFAAoKkQ/+QwDUAQAFAAoKkQ/+QwDUAQAlAAEKAADfoQAUAAAAAA==.Wildside:BAAANQAECggIEwAAAA==.',
Xa='Xandronys:BAABNQAECn8oAAQbAAoKXBQRBwAyAgAbAAkKnRURBwAyAgAaAAYKwxC41wAaAQAcAAEKvgnMeQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgMIBAAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAANAAAAAA==.Yalla:BAAANQAECgYICQAAAA==.',
Ye='Yeet:BAAANQAECggIDAAAAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalckar:BAABNQAECn8VAAIJAAkK3xNQWwAHAgAJAAkK3xNQWwAHAgAAAA==.Zanos:BAAANQAECgEIAQAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAABNQAECn8jAAIcAAoKSxokAQBkAgAcAAoKSxokAQBkAgAAAA==.Zendead:BAAANQAECggIEQAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDwAAAA==.',
Zu='Zugzugpriest:BAAANQAECgcIDQAAAA==.Zurii:BAAANQAECgEIAQAAAA==.Zurokhan:BAABNQAECn9DAAIJAAoKXx9iCQAyAwAJAAoKXx9iCQAyAwAAAA==.',
['Zø']='Zønda:BAABNQAECn82AAMhAAkKGSRkBwCyAQAhAAUKaCVkBwCyAQAOAAYKNSP1eQAiAQAAAA==.',
['Ða']='Ðagon:BAAANQAECgQIBQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAABNQAECn8UAAIHAAgKcwWOIgDzAAAHAAgKcwWOIgDzAAAAAA==.',
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
