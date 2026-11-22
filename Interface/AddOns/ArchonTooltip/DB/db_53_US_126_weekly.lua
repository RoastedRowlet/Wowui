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
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abnee:BAAANQAECgIIAgAAAA==.',
Ac='Acacia:BAAANQAECgYIEgAAAA==.',
Ad='Adowyrm:BAACNQAFFH8UAAMBAAgKlxELBwDhAQABAAgKlxELBwDhAQACAAEKAACFEQAAAAA1AAQKfyoAAgEACgohIWwIAB0DAAEACgohIWwIAB0DAAAA.Adrielle:BAAANQAECgYICQAAAA==.',
Ai='Airali:BAABNQAECn80AAIDAAoKLhBPjAANAgADAAoKLhBPjAANAgAAAA==.Airedale:BAABNQAECn8xAAIEAAoKMRMlUgAoAgAEAAoKMRMlUgAoAgAAAA==.',
Ak='Akairo:BAACNQAFFH8cAAIFAAcKhBxXBgAzAgAFAAcKhBxXBgAzAgA1AAQKf0QABAUACgohJCIHAIwDAAUACgohJCIHAIwDAAYABwq4EngxAAABAAcAAQo1AQYzABoAAAAA.Akelia:BAABNQAECn8WAAIIAAkKtBLJbQDWAQAIAAkKtBLJbQDWAQAAAA==.',
Al='Alexanderlx:BAABNQAECn8tAAMJAAkKexwnFgBNAgAJAAgKKSEnFgBNAgADAAYKpg+b+AD1AAAAAA==.Aleybobwa:BAABNQAECn86AAMKAAoKnCBfFgAFAwAKAAoKnCBfFgAFAwADAAUKLxWGAQEdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn9DAAMLAAoK0h+kDgDpAgALAAoK0h+kDgDpAgAMAAgKsxAfPAA+AQAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn87AAMCAAoKBx3EAgAlAwACAAoKZBzEAgAlAwANAAMKLRPsKwDFAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgQIBQAOAAAAAA==.',
Ao='Aolus:BAABNQAECn87AAIMAAoKKRxMGQD9AgAMAAoKKRxMGQD9AgAAAA==.',
Ap='Apoliis:BAABNQAECn8WAAIPAAYK/AgsIwACAQAPAAYK/AgsIwACAQAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQAECggICAAAAA==.Archis:BAABNQAECn8oAAMQAAoKgxVpZABhAgAQAAoKgxVpZABhAgARAAYKIgjeJgAKAQAAAA==.Arcidaes:BAEBNQAECn83AAISAAkKoRDnNAB0AQASAAkKoRDnNAB0AQAAAA==.Arez:BAAANQAECggIEwABNQAECgoKIgAIAFYJAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAABNQAECn8gAAIPAAoKNhVoDwAeAgAPAAoKNhVoDwAeAgAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Av='Avaline:BAAANQABCgQIBQAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8RAAMTAAYKWhZ3DABIAQATAAYKWhZ3DABIAQAUAAIK6wvDAgCQAAA1AAQKfycAAxQACgqLI/oBAFADABQACQpHIvoBAFADABMABgo+I4weAN0BAAAA.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUIBwABNQAECgoKNwAVANcfAA==.Baeli:BAAANQAECgQIBQAAAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAABNQAECn8xAAMNAAoKYh0ECgDRAQANAAgK5xsECgDRAQABAAcKlhMiFQClAQAAAA==.Baliw:BAABNQAECn8lAAIMAAkK/Q0dPAAUAgAMAAkK/Q0dPAAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAABNQAECn8qAAIEAAkKQxckZgD5AQAEAAkKQxckZgD5AQAAAA==.Banugg:BAAANQAECgQIBgAAAA==.Barcode:BAAANQADCgMIBQAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8KAAIWAAcKrwpdDwB5AQAWAAcKrwpdDwB5AQA1AAQKfzsAAhYACgrBIDgWALkCABYACgrBIDgWALkCAAAA.',
Bc='Bchung:BAABNQAECn9LAAMXAAoKyR06BQDDAgAXAAoKJx06BQDDAgAIAAoKDRmQOwBbAgAAAA==.',
Be='Bean:BAAANQAECgYIAwAAAA==.Bela:BAAANQAECgYIDQAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgoKIAAPADYVAA==.Belthor:BAAANQAECgEIAQAAAA==.Bertus:BAECNQAFFH8eAAMYAAgKgCWUAQBaAgAYAAgKgCWUAQBaAgAZAAQK8yE3CgBuAQA1AAQKfy0AAxkACgoHJrcUABMDABkACQpGJbcUABMDABgACAqVJM4gAIcCAAAA.Bettybop:BAAANQAECgIIAgAAAA==.',
Bh='Bhain:BAABNQAECn8fAAIWAAkKYRw6LADNAgAWAAkKYRw6LADNAgABNQAFFAUICQAaAOAIAA==.',
Bi='Bieorne:BAABNQAECn8tAAIZAAkKFBnkHQDzAQAZAAkKFBnkHQDzAQAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAwAAAA==.Boku:BAAANQAECgYIDwAAAA==.Boodidy:BAAANQADCgUICQAAAA==.Boondocks:BAABNQAECn9FAAQaAAoKXxWWPwAXAgAaAAkK/hOWPwAXAgAbAAQKpRQQFwDZAAAcAAEKlAWlgQAqAAAAAA==.Bottomx:BAABNQAECn8vAAMNAAoKugt5DQB1AQANAAoKugt5DQB1AQABAAEKxwL6QAAbAAAAAA==.',
Br='Braca:BAABNQAECn8rAAMdAAkKqxkbFwALAgAdAAkKqxkbFwALAgAeAAQKpRDcSQB9AAAAAA==.Bread:BAAANQADCggIEwAAAA==.Brielle:BAABNQAECn81AAIEAAoKdhHmagDtAQAEAAoKdhHmagDtAQAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgYIEQAAAA==.Brudene:BAABNQAECn8oAAIQAAgKDgzcqQAnAQAQAAgKDgzcqQAnAQABNQAECggIRAAIAMETAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIBQAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwAOAAAAAA==.Bullymaguire:BAAANQAECgYIBgABNQAFFAgIEgAWAJgbAA==.',
Ca='Carbonara:BAAANQADCgYIBgAAAA==.Carpe:BAABNQAECn8hAAMDAAcKxBVBoACNAQADAAcKhxRBoACNAQAJAAUKRBM7MwDpAAAAAA==.Carreth:BAAANQAECggICAAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn9EAAIQAAoKqhl6SgAgAgAQAAoKqhl6SgAgAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEIAQAAAA==.Charge:BAACNQAFFH8hAAIQAAgKPSE/BwBLAgAQAAgKPSE/BwBLAgA1AAQKfzgAAhAACgq0JgIHALsDABAACgq0JgIHALsDAAAA.Checkurback:BAABNQAECn8XAAISAAoKjB0PJACYAgASAAoKjB0PJACYAgAAAA==.Cheefdh:BAAANQAECggICAAAAA==.Chewtum:BAAANQAECgYIDQAAAA==.Chimo:BAABNQAECn8iAAIfAAkKfAqRcwBYAQAfAAkKfAqRcwBYAQAAAA==.Chüdd:BAAANQADCgQIBAAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgoKRAAIAL0dAA==.',
Cl='Cleavatron:BAAANQAECgIIAwABNQADCgcIBwAOAAAAAA==.',
Co='Conn:BAAANQAECgQIBAAAAA==.Cops:BAABNQAECn8tAAIKAAkKpR8lKQDEAgAKAAkKpR8lKQDEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAABNQAECn8YAAIdAAgKWR40DgA9AgAdAAgKWR40DgA9AgAAAA==.',
Da='Daimur:BAAANQAECgYICQABNQAECgoKIgAIAFYJAA==.Danaconda:BAAANQABCgQIBgABNQAECgoKIAAQAGcYAA==.Darkenergy:BAABNQAECn9FAAIgAAoKCiE0DgDFAgAgAAoKCiE0DgDFAgAAAA==.Darà:BAAANQADCgcIBwABNQAECgkJNAALAHQVAA==.Dashyll:BAAANQAECggIEQAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAABNQAECn8wAAIEAAoKBxw9PABfAgAEAAoKBxw9PABfAgAAAA==.Deathhelix:BAAANQADCgEIAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgoKNwAVANcfAA==.Demacus:BAABNQAECn8tAAMIAAgKywSD1wD8AAAIAAgKRgSD1wD8AAAXAAIK3QbOOQBXAAABNQAECgoKQgAWAEAKAA==.Demeter:BAABNQAECn8oAAIJAAkKzhCdIABqAQAJAAkKzhCdIABqAQAAAA==.Denalli:BAABNQAECn8iAAIXAAgK5QkPFwAuAQAXAAgK5QkPFwAuAQAAAA==.Devouress:BAAANQAECgEIAgAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAABNQAECn8yAAIhAAkKVRNNDgCdAQAhAAkKVRNNDgCdAQAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAABNQAECn8ZAAIGAAgKxAWYMQD/AAAGAAgKxAWYMQD/AAAAAA==.Dogslobber:BAAANQAECgEIAQAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Dorkma:BAAANQABCgMIAwAAAA==.Doublenickel:BAABNQAECn8aAAIKAAoKhhDGggCSAQAKAAoKhhDGggCSAQAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAgAOAAAAAA==.Drat:BAABNQAECn8cAAMEAAkKtwlSjQCcAQAEAAkK2AhSjQCcAQAiAAUKvginDAAIAQAAAA==.Dreamsicle:BAAANQADCggIDAAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECgoKKgAjAIclAA==.',
Du='Duridon:BAAANQAECgMIBQAAAA==.',
Dy='Dyorna:BAAANQADCgcIDAAAAA==.',
Eb='Ebojager:BAABNQAECn88AAIkAAoKyxqnEgA1AgAkAAoKyxqnEgA1AgAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFH8KAAIZAAYKkhA/BADtAQAZAAYKkhA/BADtAQA1AAQKfyAAAhkACgoGIW4uAHcCABkACgoGIW4uAHcCAAAA.Eisengel:BAAANQAECgIIAgAAAA==.',
El='Eldric:BAABNQAECn9EAAIIAAgKwRMgfQCxAQAIAAgKwRMgfQCxAQAAAA==.Elvispriesty:BAAANQAECgQICwAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwADABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.Enden:BAAANQADCggICAAAAA==.Entrapment:BAAANQAECggIEgABNQADCgcIBwAOAAAAAA==.Entropathy:BAAANQAECgQIBgABNQAECgEIAgAOAAAAAA==.',
Er='Ere:BAABNQAECn8iAAMIAAoKVgl9ugAwAQAIAAoKVgl9ugAwAQAXAAEKAAChQQBBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAABNQAECn8kAAMaAAcK1BjfoQCSAQAaAAcK1BjfoQCSAQAbAAEKqRxfKQBHAAABNQAECgoKOAAIAE8aAA==.Essential:BAABNQAECn8mAAIDAAoK3xHkfQAuAgADAAoK3xHkfQAuAgAAAA==.',
Ev='Evavaria:BAABNQAECn8mAAIKAAoK9RewUwAfAgAKAAoK9RewUwAfAgABNQADCgQIBAAOAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.',
Ex='Exterminate:BAAANQAECgMICQAAAA==.',
Fa='Fatalism:BAAANQADCggIDQAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEBNQAECn8fAAIaAAoK2wyCVwDNAQAaAAoK2wyCVwDNAQABNQAECgoKMgAFAKYUAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwAOAAAAAA==.Ferrara:BAACNQAFFH8UAAMlAAgK1h/aAwBGAgAlAAgK1h/aAwBGAgAEAAEKAABFLgBlAAA1AAQKfykAAiUACgpEI9UPAOsCACUACgpEI9UPAOsCAAAA.',
Fi='Filthi:BAABNQAECn8YAAIWAAgK6RdFXAByAQAWAAgK6RdFXAByAQAAAA==.Fiz:BAAANQADCgYIBgABNQAECggIDwAOAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAOAAAAAA==.',
Fl='Flandri:BAACNQAFFH8SAAIFAAgK2A7OEQCBAQAFAAgK2A7OEQCBAQA1AAQKfycAAgUACgoQJFMRAD0DAAUACgoQJFMRAD0DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgkJIgAfAHwKAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQADCgQIBAAOAAAAAA==.Friedá:BAAANQAECggIDgABNQAECgoKGwADAKgZAA==.Frostednip:BAABNQAECn88AAMYAAoKSh7oFADlAgAYAAoKSh7oFADlAgAZAAIKYQWFzwBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAgAAAA==.Gabiru:BAABNQAECn80AAIBAAoKDRx0CQALAwABAAoKDRx0CQALAwAAAA==.Gadreeste:BAAANQAECgcICAAAAA==.Galhamon:BAAANQADCgUICAAAAA==.Galnarn:BAACNQAFFH8UAAImAAcK9yGSAQAEAgAmAAcK9yGSAQAEAgA1AAQKfzMAAiYACgp+JXcCAIIDACYACgp+JXcCAIIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFH8dAAMmAAcKYxsXAwCdAQAmAAYKKxwXAwCdAQAeAAEKQhj1EQBXAAA1AAQKfzEAAyYACgqlIQoHANICACYACgo4HgoHANICAB4ACgrpHzIZAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgoKMQANAGIdAA==.Garlicbae:BAAANQAECgQIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECn8/AAIRAAoK+RkGCQBLAgARAAoK+RkGCQBLAgAAAA==.Geran:BAAANQAECgIIAQAAAA==.',
Gl='Glyd:BAAANQAECgYIDwABNQAECgoKQgAWAEAKAA==.',
Go='Goldenred:BAAANQAECgUIEQAAAA==.',
Gr='Graybrew:BAAANQAECgMIAwAAAA==.Graye:BAAANQADCgYIBgABNQAECgMIAwAOAAAAAA==.Grayes:BAABNQAECn8bAAInAAgKlgk4OADkAAAnAAgKlgk4OADkAAABNQAECgMIAwAOAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgMIAwAOAAAAAA==.Grelin:BAABNQAECn8WAAIoAAgK6RPLLADcAAAoAAgK6RPLLADcAAAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggICQAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAQICAAoAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAOAAAAAA==.Harmôny:BAAANQAECgEIAgAAAA==.Hatredno:BAAANQAECgQIBAAAAA==.Hatredyes:BAABNQAECn9UAAInAAoKIRnrDwA4AgAnAAoKIRnrDwA4AgAAAA==.',
He='Helare:BAABNQAECn85AAIMAAoKkRh8GQBBAgAMAAoKkRh8GQBBAgAAAA==.Helaro:BAAANQAECgUIBQAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Henrymorgan:BAAANQAECggIBAAAAA==.Hexenbane:BAABNQAECn8mAAIVAAkK3goAHAAsAQAVAAkK3goAHAAsAQAAAA==.',
Ho='Holybattler:BAAANQAECgIIAgAAAA==.Holyghosst:BAAANQADCgEIAQAAAA==.',
Hu='Huffmetoes:BAEANQADCgMIAwABNQAECgoKMgAFAKYUAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgAOAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgYIHQAMAAYIAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAABNQAECn8ZAAMIAAgKwg5XwgAiAQAIAAcKNg9XwgAiAQAXAAIKYQ5BMABrAAAAAA==.Ikrys:BAABNQAECn8ZAAIcAAgKShWmDgAQAgAcAAgKShWmDgAQAgAAAA==.',
Il='Ilandrea:BAAANQABCgYIDgAAAA==.Ilarion:BAABNQAECn8jAAIDAAoKZhBIdgDiAQADAAoKZhBIdgDiAQAAAA==.Illiae:BAABNQAECn8sAAIWAAoKJySLFgBBAwAWAAoKJySLFgBBAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Incrdblestan:BAAANQAECgYIBwAAAA==.Insecure:BAAANQAECgQICgAAAA==.',
Io='Ionic:BAAANQAECggIEAAAAA==.',
Is='Issidora:BAABNQAECn8jAAIlAAkKNwWuKQAcAQAlAAkKNwWuKQAcAQAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8gAAIaAAoKFwpBjQDGAQAaAAoKFwpBjQDGAQAAAA==.Janeleonoc:BAAANQABCgEIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgoKRAAIAL0dAA==.Jascob:BAAANQAECgYIDAAAAA==.Jaynne:BAAANQAECgQIBQAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECn8hAAIeAAkKuBU9JQD6AQAeAAkKuBU9JQD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBgAAAA==.Kaashaa:BAABNQAECn9cAAIEAAoKeSI9EQBdAwAEAAoKeSI9EQBdAwAAAA==.Kaelsgf:BAABNQAECn81AAIFAAoKKB9HIADuAgAFAAoKKB9HIADuAgAAAA==.Kahllan:BAABNQAECn80AAMLAAkKdBWNMABsAQALAAcK4RKNMABsAQAMAAgK/QchTQDsAAAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCggIEwAAAA==.Kataltoholic:BAAANQAECgUIDgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kayser:BAAANQAECgQICAAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Keheo:BAAANQAECgYICAAAAA==.Kelfin:BAAANQAECgUIBQAAAA==.Kelinïsha:BAABNQAECn8dAAIXAAkKVAgTFwAuAQAXAAkKVAgTFwAuAQAAAA==.Kenf:BAAANQAECgEIAwAAAA==.Kensshaman:BAAANQAECgEIAgAAAA==.Kevinbacon:BAAANQAECgIIAQAAAA==.',
Kh='Khelina:BAAANQAECgcIDAAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgcIDAAOAAAAAA==.',
Ki='Kiiras:BAAANQAECgcIDQAAAA==.Kimbodh:BAACNQAFFH8VAAIkAAYKpCGZBAA9AQAkAAYKpCGZBAA9AQA1AAQKf0AAAiQACgowJYAFAHoDACQACgowJYAFAHoDAAAA.Kimbubbles:BAAANQAECgUIBQAAAA==.Kimoora:BAAANQAECgQIBAABNQAECgUIBQAOAAAAAA==.Kimshady:BAAANQADCgcICAABNQAECgUIBQAOAAAAAA==.Kirathein:BAAANQAECgMIBgAAAA==.',
Kl='Klefthoof:BAABNQAECn9CAAMWAAoKQAp9YgBfAQAWAAkKfgl9YgBfAQAfAAkKZwqGeABJAQAAAA==.',
Ko='Kodey:BAABNQAECn8aAAIcAAkKpgqxCQAsAQAcAAkKpgqxCQAsAQAAAA==.',
Kr='Krelon:BAAANQADCggIFAAAAA==.Krimboz:BAAANQAECgYIDgAAAA==.Krystallight:BAABNQAECn89AAIiAAoKaSGIAgCoAgAiAAoKaSGIAgCoAgAAAA==.',
La='Laanda:BAAANQABCgIIAQABNQAECgUIDQAOAAAAAA==.Lanwulf:BAAANQAECgQIBAAAAA==.Lava:BAAANQAECgcIBwABNQAECgoKOQAgAKgeAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn9KAAIEAAoKDSCsHgDFAgAEAAoKDSCsHgDFAgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgYIDQAOAAAAAA==.Leondero:BAABNQAECn8iAAIEAAkKCRs1MADcAgAEAAkKCRs1MADcAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAABNQAECn8cAAMoAAoKixEOIQAiAQATAAoKbA9mSgDXAQAoAAcKpw0OIQAiAQABNQAECgEIAgAOAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAABNQAECn8vAAIDAAoKxA4spwCAAQADAAoKxA4spwCAAQAAAA==.',
Lo='Lofi:BAABNQAECn8fAAIfAAoKSAiEjwBiAQAfAAoKSAiEjwBiAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgcIEQAAAA==.',
Lu='Lubricated:BAAANQAECgcICgAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUICgAAAA==.',
Ly='Lycenia:BAAANQADCggICAAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8wAAMEAAoKpiCuEQBaAwAEAAoKpiCuEQBaAwAlAAEKAADpmgAlAAAAAA==.',
Ma='Magicdreams:BAABNQAECn8oAAIMAAkKlgZbRwAGAQAMAAkKlgZbRwAGAQAAAA==.Mahll:BAAANQAECgIIAgABNQAECgoKNgAaAJgfAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8uAAIWAAkKIRktOgCOAgAWAAkKIRktOgCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Marihuano:BAAANQAECgEIAQAAAA==.Materia:BAABNQAECn8hAAIFAAoK3B0oIADeAgAFAAoK3B0oIADeAgAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAABNQAECn8gAAIQAAoKZxjHTQAVAgAQAAoKZxjHTQAVAgAAAA==.Meerchi:BAABNQAECn8aAAIIAAoKAAqfhQCdAQAIAAoKAAqfhQCdAQAAAA==.Meknin:BAABNQAECn89AAIIAAoK/QWqlQB6AQAIAAoK/QWqlQB6AQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgIIAQABNQAECggIBAAOAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECgoKKgAjAIclAA==.',
Mi='Mickieta:BAABNQAECn9BAAIDAAoK1xxCPgBwAgADAAoK1xxCPgBwAgAAAA==.Mikalau:BAABNQAECn9DAAIEAAoKsBh5TgAxAgAEAAoKsBh5TgAxAgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAaAFceAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgoKMQANAGIdAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn9FAAMFAAoKaxqrMQChAgAFAAoKaxqrMQChAgAGAAgKGBlKIQAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgkJIgAfAHwKAA==.Mognel:BAABNQAECn8bAAIaAAoKgA4rYAC1AQAaAAoKgA4rYAC1AQAAAA==.Monklee:BAAANQADCgYIBgAAAA==.Moomootus:BAABNQAECn8rAAIDAAoKDh/eOADtAgADAAoKDh/eOADtAgAAAA==.Mordenkainen:BAAANQABCgYICgAAAA==.Motoraxe:BAABNQAECn8gAAIQAAoKhxG8igABAgAQAAoKhxG8igABAgAAAA==.Mozzie:BAAANQAECggICAAAAA==.',
My='Mystynight:BAAANQAECgQICAAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Naasha:BAAANQADCgQIBAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Nekrautik:BAAANQAECggIEAAAAA==.Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8yAAMFAAoKphRHQABqAgAFAAoKphRHQABqAgAGAAkK7wzUKgDRAQAAAA==.Nightcrest:BAAANQAECgcIDAAAAA==.Nightrocks:BAAANQAECggIEAAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.Niyyx:BAAANQAECgYIEgAAAA==.',
No='Nomusa:BAAANQAECgQIBAAAAA==.Nordrydsh:BAAANQAECgQIBgABNQAFFAgIDwABAP8IAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8TAAIQAAgKtxXBCwD2AQAQAAgKtxXBCwD2AQA1AAQKfzUAAhAACgpLI0MmAKcCABAACgpLI0MmAKcCAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
['Nô']='Nôva:BAAANQABCgUIBgAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFH8PAAIfAAgK6xvVBQANAgAfAAgK6xvVBQANAgA1AAQKfy0AAh8ACgp4I0UGALUDAB8ACgp4I0UGALUDAAAA.',
Oo='Oopositive:BAAANQAECgEIAQAAAA==.',
Or='Oraion:BAABNQAECn84AAMIAAoKTxrIPABXAgAIAAoKTxrIPABXAgAXAAEKthEQQQBCAAAAAA==.Orgarrot:BAAANQAECgYIBwABNQAECgoKVAAnACEZAA==.',
Ot='Otimion:BAAANQAECgYIBgAAAA==.',
Ov='Ovarb:BAAANQAECgcICwAAAA==.',
Pa='Padwendyn:BAAANQAECgIIAgAAAA==.Pallydan:BAABNQAECn8dAAIJAAoKSRzwEQANAgAJAAoKSRzwEQANAgABNQAECgoKOAAIAE8aAA==.Pan:BAAANQAECgIIAgAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECggIBwAAAA==.',
Ph='Phinix:BAAANQAECgYICQAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIAwAAAA==.',
Pr='Prisman:BAAANQAECgUIBQAAAA==.Proserpìne:BAABNQAECn8ZAAIkAAoKkAfvPABhAQAkAAoKkAfvPABhAQAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Py='Pyramid:BAAANQAECggICAAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAACNQAFFH8JAAIIAAQKRAVcPgB7AAAIAAQKRAVcPgB7AAA1AAQKfycAAggACgrkF3+AAH0CAAgACgrkF3+AAH0CAAAA.',
Ra='Rabies:BAAANQADCgIIAgAAAA==.Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIBAAAAA==.Rainstormin:BAABNQAECn8iAAMMAAoKhww9MACFAQAMAAoKdgw9MACFAQAnAAQK8QZCWwBdAAAAAA==.Raitan:BAABNQAECn8aAAMRAAkKZR8qEQAUAgARAAkKZR8qEQAUAgAhAAUKQA9oGwDaAAAAAA==.Raivoker:BAABNQAECn8XAAIBAAkKzhbtCwBnAgABAAkKzhbtCwBnAgABNQAECgkJGgARAGUfAA==.Rakarra:BAAANQAECggICAAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECn8tAAISAAoKXAxdNQBxAQASAAoKXAxdNQBxAQABNQADCgcIBwAOAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAABNQAECn8VAAIWAAkKsR6QFwCuAgAWAAkKsR6QFwCuAgAAAA==.Remsham:BAABNQAECn8fAAIPAAkKHQVpIAAgAQAPAAkKHQVpIAAgAQAAAA==.Renwyck:BAABNQAECn8qAAIjAAoKhyXFAADHAwAjAAoKhyXFAADHAwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECn86AAIDAAoK4B7oLQAQAwADAAoK4B7oLQAQAwAAAA==.',
Ro='Robane:BAABNQAECn8aAAIDAAUKDgcqJgGxAAADAAUKDgcqJgGxAAAAAA==.Rouen:BAABNQAECn8iAAQPAAoK4xfrEgDoAQAPAAkKcxbrEgDoAQAfAAUKLh1mnAA/AQAWAAEKhwY+OgExAAAAAA==.Roueyn:BAAANQAECgUICgAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEBNQAECn8dAAIMAAYKBgjoYQCcAAAMAAYKBgjoYQCcAAAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgoKVAAnACEZAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQAECgQIBAABNQAECgoKOQAFALkZAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Santalight:BAAANQAECgEIAwABNQAFFAYIDgAeAKEXAA==.Santamoe:BAACNQAFFH8OAAIeAAYKoRdMBQBwAQAeAAYKoRdMBQBwAQA1AAQKf0cAAh4ACQrmIzwOAPsCAB4ACQrmIzwOAPsCAAAA.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECn81AAIEAAoK/iGRGAA3AwAEAAoK/iGRGAA3AwAAAA==.Sarwyn:BAAANQADCgcIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAoANoUAA==.',
Sc='Scratchs:BAABNQAECn8XAAInAAkKaxoODQBnAgAnAAkKaxoODQBnAgABNQADCgcIBwAOAAAAAA==.',
Se='Sedak:BAAANQADCggIIQAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAABNQAECn8rAAIgAAoKuwUfQgAtAQAgAAoKuwUfQgAtAQAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shelaan:BAABNQAECn8jAAIWAAgKTwj8dwAkAQAWAAgKTwj8dwAkAQAAAA==.Shiftey:BAABNQAECn8cAAIEAAgKRh4CTACKAgAEAAgKRh4CTACKAgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECggIHAAEAEYeAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAOAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICQAOAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn80AAQbAAoKxBOqCgDJAQAbAAgKxBSqCgDJAQAaAAgK6A2vmwAhAQAcAAEKzgWFgQAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn8/AAISAAoKRyDTDgCvAgASAAoKRyDTDgCvAgAAAA==.',
Sk='Skelmir:BAAANQADCgYICgAAAA==.',
Sn='Snicklfritz:BAAANQADCggICAAAAA==.Sniffum:BAAANQADCgMIAwAAAA==.Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn86AAMZAAoKHCaDCgBoAwAZAAoKDiaDCgBoAwAYAAgK9yC9EQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgYIBgAAAA==.Sonnabear:BAAANQAECggIBAABNQAECgoKQgAWAEAKAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAgAOAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAABNQAECn8/AAIKAAoK4xdXKQCEAgAKAAoK4xdXKQCEAgAAAA==.',
St='Stanil:BAABNQAECn8hAAIEAAgKKwWtzQAXAQAEAAgKKwWtzQAXAQAAAA==.Steampunkz:BAAANQAECgIIAQAAAA==.Stellare:BAAANQAECggICQAAAA==.Strangetame:BAAANQADCgMIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgIIAgAAAA==.',
Su='Suelly:BAABNQAECn9EAAMIAAoKvR0pNgBrAgAIAAoKaBwpNgBrAgAXAAQK9xrlHAAHAQAAAA==.Suguru:BAAANQAECggIEAAAAA==.Sularma:BAAANQAECggIEgAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwAOAAAAAA==.Surasaurus:BAAANQAECgIIAgABNQAECgoKQAAmAJgWAA==.Suraschi:BAABNQAECn9AAAImAAoKmBbWCADFAQAmAAoKmBbWCADFAQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQABNQAECgIIAgAOAAAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgYIEQAAAA==.Sylain:BAAANQADCggICQABNQAECgQIBwAOAAAAAA==.Synwav:BAABNQAECn8vAAMfAAoK/xrAMACeAgAfAAoK/xrAMACeAgAWAAEKAAANKQEAAAAAAA==.Sypria:BAAANQAECgEIAQAAAA==.',
['Sá']='Sáilormoon:BAAANQAECgQIAwABNQAECgoKLAAWACckAA==.',
Ta='Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgUICQAAAA==.Tannatax:BAABNQAECn8qAAIfAAkK9BU7WACzAQAfAAkK9BU7WACzAQAAAA==.Tashah:BAAANQADCgYICwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAAOAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thauyia:BAAANQAECgIIAgABNQAECgUIDQAOAAAAAA==.Thewhitness:BAAANQAECgcICwAAAA==.Thewretch:BAABNQAECn8nAAIaAAkKIBukRgABAgAaAAkKIBukRgABAgAAAA==.Thumpthump:BAABNQAECn8gAAIlAAoKcxt1GgCBAgAlAAoKcxt1GgCBAgAAAA==.Thunderkiss:BAEANQADCggIFwABNQAECgYIHQAMAAYIAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.',
Tr='Tradewarrior:BAABNQAECn8yAAMQAAkKuSAnLACOAgAQAAkKuSAnLACOAgAhAAEKTR5CLQBTAAAAAA==.Trayth:BAAANQAECggIBwAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECn83AAMVAAoK1x+IBgAEAwAVAAoKzx6IBgAEAwAnAAUKUx2LJwBKAQAAAA==.Tsura:BAABNQAECn8hAAIKAAoK3BGYZgDkAQAKAAoK3BGYZgDkAQAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBwAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn88AAMdAAoKRSF2BgAxAwAdAAkK1yB2BgAxAwAeAAoKHSH2CADZAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgUIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgoKVAAnACEZAA==.',
Va='Vadge:BAAANQAECgQIBAABNQADCgcIBwAOAAAAAA==.Vaeryn:BAABNQAECn8XAAIEAAcKHgeTxQB3AQAEAAcKHgeTxQB3AQABNQAECgoKawAFAMIfAA==.Valhen:BAABNQAECn9rAAQFAAoKwh8lFAA3AwAFAAoKSR8lFAA3AwAHAAcKgRZ4CADeAQAGAAYK/w7zNADrAAAAAA==.Valryn:BAAANQAECgQIBAABNQAECgoKawAFAMIfAA==.Valrys:BAAANQADCgUIBQABNQAECgoKawAFAMIfAA==.Valtar:BAABNQAECn8zAAIfAAoK8iH6BwCCAwAfAAoK8iH6BwCCAwAAAA==.',
Ve='Velryn:BAAANQADCggIFAABNQAECgoKawAFAMIfAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQAECgcICAAAAA==.Vilevixon:BAABNQAECn9BAAMGAAoKXhoZFgCsAgAGAAoKXhoZFgCsAgAHAAEKvAjrLQApAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAAOAAAAAA==.Wanlok:BAABNQAECn8eAAMbAAkKWhXMDQBcAQAbAAkKmBTMDQBcAQAaAAUKkgpR/ADTAAAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQAECgIIAgAAAA==.Warriorlobo:BAABNQAECn8tAAQQAAkK6RUjkAD0AQAQAAkK6RUjkAD0AQARAAMKmA0hOQBbAAAhAAEKdAqaNQAvAAABNQAECgoKRAAIAL0dAA==.Watts:BAABNQAECn88AAIEAAoKgx9RJACuAgAEAAoKgx9RJACuAgABNQAFFAQICQAIAEQFAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.Werebeer:BAAANQAECgEIAQAAAA==.',
Wi='Wildfang:BAABNQAECn83AAMEAAoKihC4bQDmAQAEAAoKihC4bQDmAQAlAAIK/gEtdQAmAAAAAA==.Wildside:BAABNQAECn8bAAIEAAoKHRaeTQCFAgAEAAoKHRaeTQCFAgAAAA==.',
Xa='Xandronys:BAABNQAECn8wAAQbAAoKwRURBwAyAgAbAAoKwRURBwAyAgAaAAYKwxC41wAaAQAcAAEKvgnMeQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgQIBgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAAOAAAAAA==.Yalla:BAAANQAECgYIDQAAAA==.',
Ye='Yeet:BAAANQAECggIDwAAAA==.',
Yu='Yuridak:BAAANQAECgcIBwABNQAECgkJJgAdADYVAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalckar:BAAANQAECggIEgAAAA==.Zanos:BAAANQAECgEIAQAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAABNQAECn85AAIcAAoK2B1XAQC/AgAcAAoK2B1XAQC/AgAAAA==.Zendead:BAAANQAECggIEAAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgcIDQAAAA==.Zurokhan:BAABNQAECn9OAAIKAAoKXx+fFgADAwAKAAoKXx+fFgADAwAAAA==.Zuzill:BAAANQAECgUIBQABNQAECgoKOQAcANgdAA==.',
['Zø']='Zønda:BAABNQAECn9HAAMhAAkKUCXNBwAyAgAhAAYKUibNBwAyAgAQAAYKCiRJeQCZAQAAAA==.',
['Ða']='Ðagon:BAAANQAECggIDQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAABNQAECn8aAAIGAAkKDAaxLQAZAQAGAAkKDAaxLQAZAQAAAA==.',
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
