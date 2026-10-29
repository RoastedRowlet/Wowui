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

local lookup = {'DeathKnight-Unholy','Mage-Arcane','Warlock-Demonology','Paladin-Holy','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','Warrior-Arms','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Hunter-Survival','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Druid-Guardian','Druid-Feral','Druid-Balance','Shaman-Elemental','Priest-Discipline','Unknown-Unknown','Shaman-Restoration','Evoker-Preservation','Mage-Fire','Druid-Restoration','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absolute:BAABNQAECn8VAAIBAAkK0gV/fgAjAQABAAkK0gV/fgAjAQAAAA==.Abzclap:BAAANQAECgcIBwABNQAECgoKMwACAGojAA==.Abzdh:BAAANQAECgMIAwABNQAECgoKMwACAGojAA==.Abzlock:BAAANQAECgUICAABNQAECgoKMwACAGojAA==.Abzmage:BAABNQAECn8zAAICAAoKaiOLEACQAwACAAoKaiOLEACQAwAAAA==.Abzp:BAAANQAECgYIDgABNQAECgoKMwACAGojAA==.Abzrogue:BAAANQAECgYIDgABNQAECgoKMwACAGojAA==.Abzsh:BAAANQAECgQICgAAAA==.',
Ac='Acoreüs:BAEBNQAECn8iAAIDAAcKXQ3XngCZAQADAAcKXQ3XngCZAQAAAA==.',
Ad='Adramelk:BAAANQAECgIIBAABNQAECgoKHAAEADEZAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAABNQAECn8YAAIFAAYKgAkQfAAJAQAFAAYKgAkQfAAJAQAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQAECgUICgAAAA==.Allmighto:BAECNQAFFH8bAAMEAAcKLR2VAgCBAgAEAAcKLR2VAgCBAgAGAAEKAAAUMABNAAA1AAQKfzgAAgQACgpHI+MFAJ4DAAQACgpHI+MFAJ4DAAAA.Alyssaxoo:BAACNQAFFH8KAAIEAAUKEgsHDQADAQAEAAUKEgsHDQADAQA1AAQKfyQAAwQACgrqE7dLADoCAAQACgrqE7dLADoCAAYAAQoAALOzAS4AAAAA.',
Am='Amorsith:BAAANQADCggIEAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgYIEgAAAA==.Anoobyss:BAABNQAECn8VAAIHAAUKiQ5wSwD9AAAHAAUKiQ5wSwD9AAAAAA==.Anorxorcist:BAAANQAECgIIAgABNQAFFAIICwAFAOcNAA==.Anorxxorcist:BAACNQAFFH8LAAMFAAIK5w3BJABqAAAFAAIK5w3BJABqAAABAAEKPgP0DgA6AAA1AAQKfyIAAgUACgp/FlssAEABAAUACgp/FlssAEABAAAA.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggIFQABNQAECgkJIgACAKwQAA==.Anyone:BAAANQAECgUICgABNQAECgcIFwAIAMYQAA==.',
Ap='Apollouismal:BAAANQAECggICQAAAA==.Aporkchop:BAAANQAECgYICAAAAA==.Applebottom:BAABNQAECn84AAIJAAoKXh0DIgAPAwAJAAoKXh0DIgAPAwAAAA==.',
Ar='Archenemyy:BAABNQAECn8dAAMKAAgKXhslUwAqAgAKAAgKXhslUwAqAgALAAIKUwJZcgBCAAAAAA==.Arda:BAABNQAECn83AAIJAAkKhyE0KAD3AgAJAAkKhyE0KAD3AgAAAA==.Arelina:BAAANQAECgQICgAAAA==.Arune:BAAANQAECgYICgAAAA==.',
As='Aspyrx:BAABNQAECn85AAIFAAkKGRNxIwB4AQAFAAkKGRNxIwB4AQAAAA==.Assol:BAAANQAECgEIAQAAAA==.Astelan:BAEBNQAECn8oAAILAAkKUyB+CQBHAwALAAkKUyB+CQBHAwAAAA==.Astärea:BAABNQAECn8ZAAMMAAcK7QtAFQBYAQAMAAcK7QtAFQBYAQANAAYKggZEXAASAQAAAA==.',
At='Atumsphinx:BAAANQADCgMIAwAAAA==.',
Au='Aurorä:BAAANQAECgcIEAAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgUICAABNQAECgoKPAACAFMXAA==.Badhealz:BAAANQAECgMIAgAAAA==.Baeldaeg:BAABNQAECn8kAAMHAAoKmRlrFwCjAgAHAAoKmRlrFwCjAgAMAAIK1wyPKwBYAAAAAA==.Bahahahamut:BAABNQAECn8sAAIKAAoKCR0VHAACAwAKAAoKCR0VHAACAwABNQAECgoKJAAHAJkZAA==.Bannett:BAAANQAECgUIBwAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bashing:BAAANQAECgcICgABNQAECgoKOQAFABUgAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgcIEQAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCggIEgABNQAECggIFgAOAKQRAA==.Bella:BAABNQAECn8dAAIPAAgKbArjGQA2AQAPAAgKbArjGQA2AQAAAA==.',
Bi='Bianchi:BAAANQAECggIDwAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bienfrosty:BAAANQAECgUIBQAAAA==.Bigbowlp:BAEANQAECgYICgABNQAFFAgIGgAQAO8jAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigmonk:BAAANQADCgIIAgAAAA==.Bigpumpa:BAAANQAECgUICAAAAA==.Billygoatgrf:BAABNQAECn8sAAIRAAoK9xlHBAAvAgARAAoK9xlHBAAvAgAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAACNQAFFH8GAAISAAIK2AyXBQCuAAASAAIK2AyXBQCuAAA1AAQKfysAAhIACgpIH5cIAO4CABIACgpIH5cIAO4CAAAA.Blazefort:BAACNQAFFH8FAAIOAAQK6gvUDQAAAQAOAAQK6gvUDQAAAQA1AAQKfx4AAg4ACgpCIEQGAAUDAA4ACgpCIEQGAAUDAAAA.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECn81AAITAAoKTRWuAgA0AgATAAoKTRWuAgA0AgAAAA==.Bludskal:BAAANQADCgYIBgABNQAECgoKOQAFABUgAA==.Bløod:BAAANQABCgUIBQAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boomerstout:BAAANQABCgEIAQAAAA==.Boosteddots:BAAANQAECgYIDAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAABNQAECn8VAAQQAAYKiBMTFQBNAQAQAAYKLBETFQBNAQAUAAUKJxCkKgDkAAAIAAQKYxR5BAHUAAABNQAECgoKJAAHAJkZAA==.Breemonic:BAABNQAECn8eAAINAAoKLQiLQgCtAQANAAoKLQiLQgCtAQAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Britannican:BAAANQAECgEIAQAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAACNQAFFH8PAAQQAAYKqxuBAADlAQAQAAYKqxuBAADlAQAUAAIK8giGBwBqAAAIAAIK+A0lPABJAAA1AAQKfzUABBAACgqrIp0AAEcDABAACgppIp0AAEcDABQACQoWGA0MAHYCAAgACQpUGm5nAFkCAAAA.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQAECgQIBAAAAA==.Bullshoc:BAAANQADCgUIBgAAAA==.Bullwrinkle:BAAANQAECgYIBQAAAA==.Burgleslight:BAAANQABCgEIAQAAAA==.Butturz:BAABNQAECn8VAAILAAcKWR+WHQBUAgALAAcKWR+WHQBUAgAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQAECgIIAgAAAA==.Cailleach:BAAANQAECgIIBAAAAA==.Cainz:BAABNQAECn8dAAMVAAkKDQ7XIgDwAAAWAAgKkQpoTQAnAQAVAAgKZQ3XIgDwAAAAAA==.Caraxes:BAAANQAECgUIBgABNQAECgoKRQATAJQfAA==.Carson:BAAANQAECgUIBQAAAA==.',
Ce='Celeryman:BAABNQAECn8YAAQGAAgKdRrqfgAsAgAGAAgKdRrqfgAsAgAEAAMKWQWW+wCGAAAXAAIKPQs2ZQBMAAAAAA==.Centuro:BAAANQAECgIIAQAAAA==.',
Ch='Chillywillie:BAAANQAECgUIBAABNQAECgkJLgACADUaAA==.Chobi:BAABNQAECn8aAAMYAAkKnCQCAgC1AwAYAAkKnCQCAgC1AwAZAAEKAACmOQBVAAABNQAECgoKMgAFAOMfAA==.',
Ci='Cinnamen:BAABNQAECn8qAAIWAAoKsh4DBwANAwAWAAoKsh4DBwANAwAAAA==.',
Cl='Claudine:BAAANQAECgUIDwABNQAECgkJHwACAAcEAA==.Clearstoned:BAAANQADCgUIBQABNQAFFAMIBwACAJkfAA==.',
Co='Coaa:BAABNQAECn8fAAIJAAcKDRUciQD4AQAJAAcKDRUciQD4AQAAAA==.Colossus:BAABNQAECn8UAAIGAAcK1gT8FAH8AAAGAAcK1gT8FAH8AAAAAA==.Contrap:BAABNQAECn8nAAIJAAoKNRcPWgBmAgAJAAoKNRcPWgBmAgAAAA==.Coolbreeze:BAABNQAECn8cAAIYAAcKvhqqEwApAgAYAAcKvhqqEwApAgAAAA==.Corpsgrinder:BAACNQAFFH8FAAIVAAIKwAvhFQCcAAAVAAIKwAvhFQCcAAA1AAQKfxoAAhUACgprG70bAKACABUACgprG70bAKACAAAA.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQABCgQIBAAAAA==.Crõwfather:BAAANQAECgIIAgAAAA==.',
Cu='Curtland:BAAANQAFFAEIAQAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQAECgQIBwAAAA==.Damagenpayne:BAAANQABCgEIAQAAAA==.Darkmeadow:BAABNQAECn8XAAIaAAYKfg3EYgBDAQAaAAYKfg3EYgBDAQAAAA==.Dastard:BAABNQAECn8pAAIbAAoKChr6MQCyAgAbAAoKChr6MQCyAgAAAA==.',
De='Deadlock:BAAANQAECgEIAgAAAA==.Deadplank:BAABNQAECn8gAAIFAAkKDBV/IgCAAQAFAAkKDBV/IgCAAQAAAA==.Deathlyfrost:BAAANQADCggICAAAAA==.Deftonia:BAABNQAECn8oAAIGAAoK/QXSigA8AQAGAAoK/QXSigA8AQAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAABNQAECn81AAMJAAoKdR/sFACrAgAJAAoKdR/sFACrAgAPAAEKsAE9nQAiAAAAAA==.Demonbläde:BAAANQAECgcICwAAAA==.Dethany:BAABNQAECn8XAAIbAAYK4QXkwQAOAQAbAAYK4QXkwQAOAQABNQAECgkJHwACAAcEAA==.Devondric:BAACNQAFFH8HAAIKAAQKBRgeFADuAAAKAAQKBRgeFADuAAA1AAQKf0kAAwoACgpLInAFAJ0DAAoACgpLInAFAJ0DABwAAQp5Bt0tACkAAAAA.Devotion:BAAANQADCgUIBQABNQAFFAQIFQAEAL4SAA==.Devotional:BAACNQAFFH8VAAMEAAQKvhJMEgA8AQAEAAQKvhJMEgA8AQAGAAIKkQGRLABsAAA1AAQKfz8AAwQACgpQHeMYABUDAAQACgpQHeMYABUDAAYAAwqDEbpDAbQAAAAA.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQAECgQIBAABNQAECgoKLAAGAFoaAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dirgenz:BAAANQAFFAIIAgAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcICgAAAA==.',
Dm='Dmatch:BAAANQAECgYIDAAAAA==.',
Do='Docholigay:BAAANQAECgMIBgAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgAdAAAAAA==.Dommymilkies:BAAANQAECgEIAQABNQAECggIHwANAAAXAA==.Doozpal:BAABNQAECn8wAAIEAAkKhheRMwCWAgAEAAkKhheRMwCWAgAAAA==.Doppelarcane:BAAANQAECggIBQAAAA==.Dorinspins:BAEBNQAECn8eAAIIAAkKZRk9WACDAgAIAAkKZRk9WACDAgAAAA==.Downset:BAAANQAECgMIAwABNQAECgoKPAACAFMXAA==.',
Dr='Drago:BAAANQAECgIIAgAAAA==.Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAABNQAECn8tAAMSAAkKUSOuAgB8AwASAAkKUSOuAgB8AwAeAAIKShBf8gCFAAABNQAFFAQICAAfAGEXAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgUICgAAAA==.Drezd:BAABNQAECn9AAAIPAAoKgg++EQCnAQAPAAoKgg++EQCnAQAAAA==.',
Du='Duck:BAAANQAECgEIAQABNQAECgUIDQAdAAAAAA==.Dulcïnea:BAAANQAECggICAABNQAECgoKNQAJAHUfAA==.Dumpymilk:BAAANQAECgEIAQABNQAECgoKJAAHAJkZAA==.',
Ea='Eao:BAABNQAECn87AAIJAAoKVQzJSADEAQAJAAoKVQzJSADEAQAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgAdAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgkJGQADAO0RAA==.',
El='Elblaize:BAAANQABCgUIBQAAAA==.Elitistjerk:BAAANQADCgIIAwAAAA==.Eliza:BAAANQAECgYIBgAAAA==.Ellisis:BAABNQAECn8fAAIXAAgK1RyMEwBqAgAXAAgK1RyMEwBqAgAAAA==.',
Em='Emriq:BAABNQAECn8kAAIGAAgKbBmwdgA/AgAGAAgKbBmwdgA/AgAAAA==.',
En='Enmai:BAABNQAECn8oAAIDAAgKVwsSaQAtAQADAAgKVwsSaQAtAQAAAA==.',
Ep='Epiphany:BAABNQAECn8fAAICAAkKBwTnuwDQAAACAAkKBwTnuwDQAAAAAA==.',
Er='Eraylina:BAABNQAECn8iAAICAAkKrBDITwC/AQACAAkKrBDITwC/AQAAAA==.Ertivoker:BAAANQADCggICAABNQAECgoKLAARAPcZAA==.',
Eu='Eulogy:BAABNQAECn87AAMLAAoKCBqaCgBFAgALAAoKCBqaCgBFAgAKAAUK9hy+fACjAQAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQABCgIIAgAAAA==.',
Ex='Exxitus:BAAANQAECgUIBwAAAA==.',
Fa='Faerielana:BAEBNQAECn8cAAQCAAkKLwuS2gDSAQACAAkKLwuS2gDSAQAgAAEKdAJPBwAdAAARAAEKAADhMQAAAAABNQAECggIHAAhAAoXAA==.Faith:BAAANQAECgMIBgAAAA==.Falsoqt:BAABNQAECn8VAAIiAAkKOhorBwCUAgAiAAkKOhorBwCUAgAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAcIGwAEAC0dAA==.',
Fe='Fecalmatters:BAAANQAECgEIAQAAAA==.Felachio:BAABNQAECn84AAIJAAkKBxjvOgD1AQAJAAkKBxjvOgD1AQAAAA==.',
Fi='First:BAAANQAECgQIBQAAAA==.',
Fj='Fjörgyn:BAACNQAFFH8cAAIbAAcKOyBJAQDKAgAbAAcKOyBJAQDKAgA1AAQKfy4AAhsACgrJJD0OAHcDABsACgrJJD0OAHcDAAAA.',
Fl='Flankster:BAAANQAECgMICAAAAA==.Flanksterr:BAAANQAECgYIEAAAAA==.',
Fo='Fork:BAABNQAECn8/AAIOAAoKkSV4AQDbAwAOAAoKkSV4AQDbAwAAAA==.Forsetí:BAAANQAECgEIAQAAAA==.Fortress:BAAANQAECgMIAwAAAA==.Fozziedaburr:BAABNQAECn8wAAMhAAoKJR8/DAAIAwAhAAoKJR8/DAAIAwAaAAgK3RbwKAA/AQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAABNQAECn8tAAICAAoK2R0/HgCDAgACAAoK2R0/HgCDAgAAAA==.',
Ft='Ftfk:BAAANQAECgUIBQABNQAECgoKNQAfAKIjAA==.',
Ga='Galie:BAACNQAFFH8GAAIaAAIKewMQJABlAAAaAAIKewMQJABlAAA1AAQKfykAAxoACgplEVQzAEsCABoACgplEVQzAEsCABgABQohDd08AMwAAAAA.Galiè:BAAANQAECgcIBwAAAA==.Garrahoth:BAABNQAECn8WAAMOAAgKpBF/JQCkAQAOAAgKog9/JQCkAQABAAYK7QxpewAuAQAAAA==.',
Ge='Gekk:BAABNQAECn85AAMfAAkKkxEACwDsAQAfAAkKkxEACwDsAQAjAAUKIwrKJwD0AAAAAA==.',
Gi='Giaus:BAABNQAECn8iAAICAAoKFxxLfwCAAgACAAoKFxxLfwCAAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Gleipnir:BAAANQAECgMIAwAAAA==.Glimmerwisp:BAABNQAECn8hAAICAAkKNAwdxwD2AQACAAkKNAwdxwD2AQAAAA==.',
Go='Gobzilla:BAABNQAECn8cAAMeAAkKKBFjdACuAQAeAAkKKBFjdACuAQAbAAIK6gt6oQBhAAAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Gorillamind:BAAANQADCgYIBgABNQAECgMIAwAdAAAAAA==.Goub:BAAANQAECgYIEQAAAA==.',
Gr='Grapefantuh:BAAANQAECgQIBgAAAA==.Grapefroot:BAAANQAECgQIBAAAAA==.Grapeinator:BAABNQAECn8cAAIGAAoKAxISmgDvAQAGAAoKAxISmgDvAQAAAA==.Grasseater:BAAANQADCgYIBgABNQAFFAQIDwAEABIbAA==.Grimreapr:BAAANQAECgIIAwAAAA==.Grimrieber:BAABNQAECn8gAAMUAAkKCxzrDwArAgAUAAgKZBvrDwArAgAIAAEK9B8a3ABaAAAAAA==.Gromn:BAABNQAECn9FAAQTAAoKlB/hAQA8AwATAAoKlB/hAQA8AwAJAAMKlQZ4KwGZAAAPAAEKegV2lwApAAAAAA==.',
Ha='Happywoodz:BAAANQAECgEIAgABNQAECgoKLQAeAFkhAA==.Hashed:BAABNQAECn8eAAIGAAoKwh5IOADvAgAGAAoKwh5IOADvAgAAAA==.Hays:BAAANQAECggIEwAAAA==.Haysevoker:BAACNQAFFH8eAAQkAAcK/RqzAgBUAQAkAAUKQhezAgBUAQAfAAIKmw4eFACOAAAjAAIKcRbeCwCLAAA1AAQKfyUABCQACgooH7AEALQCACQACgonH7AEALQCACMACApnDroZAK0BAB8AAwrEDVo9ALEAAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.',
Hi='Highs:BAAANQAECggICAAAAA==.Himsmart:BAAANQADCgYICgABNQAECgoKJAAHAJkZAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECn8XAAMKAAgKqyIjFwAcAwAKAAgKqyIjFwAcAwAcAAEKOQ9/KAA0AAAAAA==.Hoodler:BAECNQAFFH8WAAIhAAcKEBxlAgDeAQAhAAcKEBxlAgDeAQA1AAQKfzsAAyEACgpzJJACAKQDACEACgpzJJACAKQDABkAAQp0FT4+AEAAAAAA.Hoodlery:BAECNQAFFH8LAAIlAAYK+CBKAgANAgAlAAYK+CBKAgANAgA1AAQKfx0AAiUACQpTHvYJAOkCACUACQpTHvYJAOkCAAE1AAUUBwgWACEAEBwA.Hoofjob:BAACNQAFFH8WAAImAAcKPBDyAgBXAQAmAAcKPBDyAgBXAQA1AAQKfzQAAiYACgobH4gGAL0CACYACgobH4gGAL0CAAAA.',
Hu='Huskydots:BAACNQAFFH8KAAMDAAMKyBIHGACbAAADAAIK2BIHGACbAAAiAAEKqhLaCwBRAAA1AAQKfywAAwMACgqMFw9sABkCAAMACQrIFw9sABkCACIAAworDt9IAKUAAAAA.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQAECgIIAwABNQAECgkJOAAJAAcYAA==.',
Ib='Iblastpants:BAABNQAECn8bAAImAAcKJwi4KQDYAAAmAAcKJwi4KQDYAAAAAA==.',
Id='Idd:BAAANQAECgIIAgAAAA==.',
Ig='Iggyy:BAABNQAECn8dAAIDAAkKqgu9UQBuAQADAAkKqgu9UQBuAQAAAA==.',
Im='Imshaman:BAAANQAECgUIBQAAAA==.',
In='Inflammo:BAAANQABCgIIAgAAAA==.Insaneisbad:BAAANQADCggICQAAAA==.Insaneness:BAABNQAECn8eAAIBAAoKwA3wGQCnAQABAAoKwA3wGQCnAQAAAA==.',
Ir='Irila:BAAANQAECgMIBAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgUIDQABNQAECgcIFwAIAMYQAA==.',
Iz='Izumî:BAAANQADCggIEwAAAA==.',
Ja='Jackdáripper:BAAANQABCgYIBgAAAA==.Jakè:BAAANQAECgIIAgAAAA==.Jangosan:BAAANQAECgIIAgABNQAECgoKLwAWAGkUAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgYICgAAAA==.Jaspy:BAABNQAECn88AAIYAAoK9BxNCABXAgAYAAoK9BxNCABXAgAAAA==.',
Je='Jeffdennis:BAABNQAECn8hAAIIAAoKchShdAA3AgAIAAoKchShdAA3AgAAAA==.',
Ji='Jimmybuffler:BAABNQAECn8XAAIEAAgKBRtsOwB3AgAEAAgKBRtsOwB3AgAAAA==.',
Jo='Jomgpallie:BAABNQAECn8uAAIGAAoK7w7IVwCvAQAGAAoK7w7IVwCvAQAAAA==.Jonji:BAAANQADCgMIAwABNQAECgkJKQAXAB8fAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgQIBgAAAA==.',
Ju='Judykiki:BAAANQAECgUIBgABNQAECgYIGAAFANYUAA==.Juecy:BAAANQAECgcIBwAAAA==.Juju:BAAANQAECgcIDwAAAA==.Juktal:BAABNQAECn8eAAITAAgK+hGpBgAmAgATAAgK+hGpBgAmAgAAAA==.Justyn:BAABNQAECn8lAAMIAAcKphLAcQA1AQAIAAcKphLAcQA1AQAUAAEKAAC/TgARAAAAAA==.',
Jv='Jva:BAAANQAECgYIBQAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcICQAAAA==.Kainamahs:BAAANQAECgQIBAAAAA==.Kainz:BAAANQAECgIIAwAAAA==.Kanokoa:BAAANQAECgEIAQAAAA==.Kaonazor:BAAANQADCgYIBgAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Karbondin:BAAANQADCgIIAgAAAA==.Karbonette:BAAANQADCgYIBgAAAA==.Kattakuri:BAAANQAECgYIDwAAAA==.Kazaju:BAABNQAECn8ZAAMiAAkKuh51LQAWAQADAAYKdhx1iADRAQAiAAMKYSR1LQAWAQAAAA==.',
Ki='Kialorstus:BAABNQAECn8iAAQOAAoKDRUCKwBEAgAOAAoKDRUCKwBEAgABAAQKIgs0pQCvAAAFAAEK5gSD0wAqAAAAAA==.Kinzington:BAABNQAECn8UAAMJAAgK5RC7XQCFAQAJAAYKIxe7XQCFAQAPAAUKgAiZUgDeAAABNQAECgoKPAACAFMXAA==.Kirbo:BAAANQAECgcICwAAAA==.Kitagawa:BAABNQAECn85AAIFAAoKFSCBFgD5AgAFAAoKFSCBFgD5AgAAAA==.Kitten:BAABNQAECn8VAAIJAAcK+QX6sgDJAAAJAAcK+QX6sgDJAAAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Kookiemonsta:BAAANQAECgQIBAAAAA==.Korianth:BAAANQAECgUIBwAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAACNQAFFH8FAAIGAAIK7gdOGgB8AAAGAAIK7gdOGgB8AAA1AAQKfx4AAgYACgprDlqcAOoBAAYACgprDlqcAOoBAAAA.',
Kr='Kradyn:BAAANQAECgYIDAAAAA==.Kragfoerend:BAABNQAECn8dAAIIAAcK5gMG9gDyAAAIAAcK5gMG9gDyAAAAAA==.Kramx:BAAANQAECgMIAwAAAA==.Krankenstein:BAABNQAECn85AAIFAAkKrRhTMQBKAgAFAAkKrRhTMQBKAgAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAABNQAECn8nAAIVAAkK9SP+AQAXAwAVAAkK9SP+AQAXAwAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgYIBwAAAA==.',
Ku='Kuhtta:BAAANQAECgUIEQAAAA==.Kumdobeast:BAAANQAECgQIDQAAAA==.Kuothe:BAAANQAECgUIDwAAAA==.',
Ky='Kyina:BAAANQADCgcIBwAAAA==.Kyoterd:BAAANQAECgUIBQAAAA==.Kyotili:BAAANQABCgMIAQAAAA==.Kyotpal:BAAANQADCgYIDAAAAA==.Kyotsas:BAAANQAECggIBQAAAA==.',
La='Lazyriver:BAABNQAECn8hAAIOAAgK1As1WQBGAQAOAAgK1As1WQBGAQABNQAECggKIQAOANQLAA==.',
Le='Legoland:BAAANQAECggIAwAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAABNQAECn8hAAIaAAkKLBACQwDpAQAaAAkKLBACQwDpAQAAAA==.Lewakex:BAAANQAECggIEQAAAA==.Leyninade:BAABNQAECn8gAAIaAAgKrRSXOwAYAgAaAAgKrRSXOwAYAgAAAA==.',
Li='Lightbrngr:BAABNQAECn82AAIGAAoKvRzmPgDYAgAGAAoKvRzmPgDYAgAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggICwAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIGAABNQAECgoKJAAHAJkZAA==.Lildump:BAAANQAECgYIEAAAAA==.Limitlessone:BAABNQAECn8aAAICAAcKCh79mABOAgACAAcKCh79mABOAgAAAA==.Lionescanor:BAAANQAECgMIBQAAAA==.Liptonaysti:BAAANQAECgQICQAAAA==.Lissandine:BAEBNQAECn8pAAMMAAoKShRQCwAbAgAMAAoKShRQCwAbAgANAAUKHgTqbgC9AAAAAA==.Liya:BAAANQAECgEIAwABNQAFFAYIDgAFAC8hAA==.Lizzywizzy:BAAANQADCgYIBgABNQAECgoKJAAHAJkZAA==.',
Lo='Locrian:BAAANQABCgQIBAAAAA==.Lokikillz:BAAANQAECgYIEAAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAACNQAFFH8HAAIIAAMK8wVpJwDEAAAIAAMK8wVpJwDEAAA1AAQKfy4AAwgACgr3EyFyAD4CAAgACgo7EyFyAD4CABAAAgp4GDEmAHwAAAAA.',
Lu='Luulk:BAABNQAECn8YAAMFAAYK1hSfYQBrAQAFAAYK1hSfYQBrAQAOAAEKAADSnQAAAAAAAA==.',
Ly='Lych:BAAANQAECgcIEAAAAA==.Lyclaw:BAAANQADCgQIBgAAAA==.Lycross:BAAANQADCgIIAgAAAA==.',
['Lì']='Lìllith:BAAANQAECgcIDwAAAA==.Lìvíd:BAAANQADCgIIAgAAAA==.',
Ma='Madoris:BAABNQAECn8aAAMhAAYKUw17LQD3AAAhAAYKUw17LQD3AAAaAAQKAgi2jQCfAAAAAA==.Madscience:BAAANQADCggIEAAAAA==.Magemagerson:BAABNQAECn8oAAICAAoK9yCIJgBGAwACAAoK9yCIJgBGAwAAAA==.Magnuss:BAABNQAECn8cAAMCAAoKLgj45gC7AQACAAoKLgj45gC7AQARAAIKJQMyPABPAAAAAA==.Mahini:BAAANQAECggICAAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAABNQAECn8kAAIOAAcK1A91SACbAQAOAAcK1A91SACbAQAAAA==.Mammutos:BAABNQAECn8pAAIhAAgKAxoBDgBNAgAhAAgKAxoBDgBNAgAAAA==.Manifred:BAAANQAECgMIAwAAAA==.Manion:BAABNQAECn80AAMeAAoK6B0PIQDlAgAeAAoK6B0PIQDlAgAbAAgKSxdzNgB8AQAAAA==.Manipepper:BAABNQAECn8cAAMDAAgKBAelegACAQADAAgKBAelegACAQAiAAIK6gRkZwBUAAAAAA==.Manippiez:BAAANQAECgMIBAAAAA==.Manipulating:BAAANQADCgYICgAAAA==.Manipulation:BAAANQAECgQICAAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQAECgIIAgAAAA==.Maplemaga:BAAANQAECggIDAAAAA==.Margot:BAAANQADCgYIDAABNQAECgUICgAdAAAAAA==.Masochista:BAACNQAFFH8OAAIFAAYKLyFwDQB8AQAFAAYKLyFwDQB8AQA1AAQKfx0AAgUACgoFJmcIAHgDAAUACgoFJmcIAHgDAAAA.Mastric:BAEBNQAECn86AAIDAAoKUAdiWwBRAQADAAoKUAdiWwBRAQAAAA==.',
Mc='Mccaffrey:BAABNQAECn85AAMQAAkKkBmMBAAsAgAQAAkKXxmMBAAsAgAIAAkKkRQ3XgBnAQAAAA==.',
Me='Meetch:BAACNQAFFH8IAAIBAAMKzxgyBAAAAQABAAMKzxgyBAAAAQA1AAQKfy4AAgEACAodHm0mAKMCAAEACAodHm0mAKMCAAAA.Megdar:BAABNQAECn8WAAImAAcKwwwDNgBlAQAmAAcKwwwDNgBlAQAAAA==.Melledreu:BAACNQAFFH8IAAIRAAIKLwTRBQB6AAARAAIKLwTRBQB6AAA1AAQKf2gAAxEACgquC/gOALsBABEACgpJC/gOALsBAAIACgo0Ban+AJABAAAA.Mellessan:BAAANQADCggICAAAAA==.Merix:BAABNQAECn8nAAMVAAkKtx8HRwCpAQAVAAUK8h8HRwCpAQAWAAUKtx2IJwCKAQAAAA==.Mestea:BAABNQAECn8jAAMeAAcKgQtRZgALAQAeAAcKgQtRZgALAQAbAAYK0gdWjgCBAAAAAA==.Mewing:BAAANQAECgQIBAABNQAECgoKMAAGADEkAA==.',
Mi='Miraclemill:BAAANQADCgcIFQAAAA==.Mirra:BAABNQAECn8mAAIKAAkKkhTVQgCnAQAKAAkKkhTVQgCnAQAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momoshirow:BAAANQADCgQIBwAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAACNQAFFH8FAAMCAAIKvgr2NwBKAAACAAEKbQv2NwBKAAARAAEKDwqNDgBEAAA1AAQKfyYAAgIACgoWExOSAFsCAAIACgoWExOSAFsCAAAA.Mortelinnos:BAABNQAECn87AAINAAoKHiUWBAAmAwANAAoKHiUWBAAmAwAAAA==.',
Mu='Mufas:BAAANQADCgIIAgAAAA==.Murto:BAAANQAECgEIAQAAAA==.',
My='Mysticguru:BAABNQAECn8cAAIeAAYKVh1WbwC9AQAeAAYKVh1WbwC9AQAAAA==.Mythrax:BAABNQAECn8hAAMTAAkKcxvRAgD8AgATAAkKcxvRAgD8AgAPAAIKpwZ5dgBjAAAAAA==.',
Na='Naisu:BAAANQAECggICQAAAA==.Naradrae:BAAANQAECgQICwAAAA==.Narodaran:BAAANQAECggICQAAAA==.Naughtyrawr:BAAANQAECgUIDAAAAA==.',
Ne='Necropete:BAAANQAECgIIAgABNQAFFAEIAQAdAAAAAA==.Neondemon:BAAANQAECgMIBQAAAA==.Nevets:BAABNQAECn82AAIPAAoKHyDOCwAcAwAPAAoKHyDOCwAcAwAAAA==.Nevrs:BAABNQAECn8YAAMZAAcK1hbOEgAEAQAZAAYK1hbOEgAEAQAaAAIK6AGpsgAyAAAAAA==.Newworld:BAAANQADCgUIEAAAAA==.',
Ni='Nikolajokic:BAAANQAECgIIAwAAAA==.Nimit:BAABNQAECn8uAAIJAAkKXxrESgCNAgAJAAkKXxrESgCNAgAAAA==.',
No='Noughtsee:BAABNQAECn8jAAICAAgKaQrvfQBHAQACAAgKaQrvfQBHAQAAAA==.Novic:BAABNQAECn8qAAIKAAoKPxHcZADxAQAKAAoKPxHcZADxAQAAAA==.Noxinox:BAAANQADCgYIBwAAAA==.Nozom:BAAANQADCgEIAQABNQAECggIFgAOAKQRAA==.',
Nu='Nualia:BAABNQAECn8mAAIGAAoKsh0QQQDRAgAGAAoKsh0QQQDRAgAAAA==.',
['Né']='Némésis:BAAANQAECgQIDwAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAABNQAECn8VAAISAAgKCBQFFgAIAgASAAgKCBQFFgAIAgAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAACNQAFFH8OAAIQAAQKGxqiAAD2AAAQAAQKGxqiAAD2AAA1AAQKfyEAAxAACgq0IA0EAEECABAACQq0IA0EAEECABQAAQoAAIo8AFMAAAAA.',
Os='Oscassey:BAABNQAECn82AAIVAAkKnQooEQB5AQAVAAkKnQooEQB5AQAAAA==.',
Ox='Oxley:BAABNQAECn8sAAIZAAkKDhkjBwDwAQAZAAkKDhkjBwDwAQAAAA==.',
Pa='Paladingus:BAABNQAECn8pAAMXAAkKHx/AEACUAQAGAAkKiRzmeQA4AgAXAAYK0R7AEACUAQAAAA==.Pandidin:BAABNQAECn8kAAMlAAgKlxYMGAD+AQAlAAgKlxYMGAD+AQAmAAIKuQ0CYABgAAAAAA==.Parrythìs:BAAANQABCgIIAgABNQAECgMIAwAdAAAAAA==.Pauldrons:BAACNQAFFH8GAAMBAAIKzgmVGgCGAAABAAIKzgmVGgCGAAAOAAEKowLxIQA1AAA1AAQKf04AAwEACgpiEVdDAA0CAAEACgpZEVdDAA0CAA4ABwrPBohgACMBAAAA.',
Pe='Peenar:BAABNQAECn8cAAQPAAkKsyFxDwDxAgAPAAgKsyFxDwDxAgAJAAIK8iMXIQG5AAATAAIKJhzRDgCvAAAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAABNQAECn8kAAIDAAcKTxeLbQAWAgADAAcKTxeLbQAWAgAAAA==.Pharlòck:BAAANQADCgUIBgABNQAECgcIJAADAE8XAA==.Phobia:BAAANQADCggICAABNQAECgoKOwALAAgaAA==.',
Pi='Picklelips:BAAANQADCgQICQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankmedaddy:BAAANQADCgYIBgAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAgAAAA==.Plankz:BAAANQADCggIEwAAAA==.',
Po='Pooterdiddle:BAAANQAECgUIBgAAAA==.',
Pr='Priesttess:BAAANQADCgcICgAAAA==.Prohealin:BAABNQAECn8qAAIKAAoKuAo0iQB7AQAKAAoKuAo0iQB7AQAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.Psychosís:BAAANQADCgQIBAAAAA==.',
Pt='Ptiteagacee:BAABNQAECn8gAAQLAAkKoBlNJwDxAQALAAYK4RpNJwDxAQAKAAcKjxrfaADkAQAcAAUKGhrsCwB+AQAAAA==.',
Pu='Pufdaddy:BAAANQAECgcIEwAAAA==.Puffpuffy:BAAANQADCgYIBgAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECggIKwAJAIAcAA==.Pumpkinq:BAABNQAECn9TAAMWAAoKaSMpAwBzAwAWAAoKaSMpAwBzAwAVAAQKvBrnZwATAQAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAABNQAECn87AAMCAAoKARv8TwDhAgACAAoKARv8TwDhAgARAAMK7xglJQDGAAAAAA==.',
Ra='Raby:BAAANQADCgYIBgAAAA==.Ragemommie:BAAANQAECgMIBAABNQAECgUIBgAdAAAAAA==.Rainer:BAAANQAECgEIAQAAAA==.Rasmus:BAABNQAECn8vAAIXAAoKJxXPDADYAQAXAAoKJxXPDADYAQAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAABNQAECn81AAIfAAoKoiPsAADNAwAfAAoKoiPsAADNAwAAAA==.Razzahola:BAAANQADCgIIAgABNQAECgQIBAAdAAAAAA==.Razzmatazz:BAABNQAECn81AAICAAkKdhjURQDiAQACAAkKdhjURQDiAQAAAA==.',
Re='Reddeyes:BAABNQAECn8nAAIjAAcKfAhdEADMAAAjAAcKfAhdEADMAAAAAA==.Regulüs:BAABNQAECn8XAAIXAAkKcxe2HQD8AQAXAAkKcxe2HQD8AQAAAA==.Rescue:BAABNQAECn88AAICAAoKUxcKNQAeAgACAAoKUxcKNQAeAgAAAA==.Reva:BAEANQAECgcICAABNQAECgkJKAALAFMgAA==.',
Ri='Riddlebox:BAAANQADCgEIAQAAAA==.Rinedara:BAAANQADCgMIAwAAAA==.Rising:BAAANQADCggIDgAAAA==.',
Ro='Roamin:BAAANQADCggICAAAAA==.Roasted:BAABNQAECn8xAAICAAoKqxlCXwDBAgACAAoKqxlCXwDBAgAAAA==.Rockma:BAAANQAECggIDAAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Romantacykmc:BAAANQADCgcIIQABNQADCgYICwAdAAAAAA==.Roxymigurdia:BAABNQAECn8oAAIJAAoK0CUxBADGAwAJAAoK0CUxBADGAwAAAA==.',
Ru='Rufföaddy:BAABNQAECn87AAIEAAoK1iIMAwC9AwAEAAoK1iIMAwC9AwAAAA==.Rumproast:BAAANQAECggIDAABNQAECggIFgAOAKQRAA==.Runeesa:BAABNQAECn8fAAIJAAcKiBCJeABEAQAJAAcKiBCJeABEAQAAAA==.',
Ry='Rylena:BAABNQAECn8iAAMJAAgKcCDsTQCFAgAJAAgKcCDsTQCFAgAPAAUK3BCzTQD6AAAAAA==.Ryuke:BAAANQAECgYIEgAAAA==.Ryvalry:BAAANQABCgIIAgAAAA==.',
['Rà']='Ràvenn:BAAANQABCgIIAgABNQAECgcIFQAUAGEIAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
['Rã']='Rãmbõ:BAAANQADCgMIBAAAAA==.',
Sa='Sagikos:BAEBNQAECn8cAAMhAAgKChdRIgAUAgAhAAgKChdRIgAUAgAaAAIKmQ3jUgB8AAAAAA==.Sandrid:BAAANQABCgMIAwAAAA==.Sardras:BAABNQAECn82AAIhAAoKmiTGAAAOBAAhAAoKmiTGAAAOBAAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICgAAAA==.Sauccyy:BAAANQAECgQIBQAAAA==.Saucecity:BAAANQAECgQIBAAAAA==.Saucyjenkins:BAAANQAECgcIDQAAAA==.',
Sc='Scranton:BAAANQADCgcICQAAAA==.',
Se='Sean:BAAANQADCgYICwAAAA==.Selest:BAAANQADCgEIAQAAAA==.Sellout:BAAANQAECgEIAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQAECggICAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICwABNQAECggIHAAhAAoXAA==.Shamerific:BAAANQADCgcIBwAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgYIEgAdAAAAAA==.Shammooz:BAACNQAFFH8IAAISAAIK7R2QAwCiAAASAAIK7R2QAwCiAAA1AAQKf24AAhIACgolH90GABQDABIACgolH90GABQDAAAA.Shinier:BAABNQAECn84AAIEAAoKEiTxBACoAwAEAAoKEiTxBACoAwAAAA==.Shockwoods:BAABNQAECn8tAAMeAAoKWSE+BQCAAwAeAAoKWSE+BQCAAwAbAAIK7A4DDAFzAAAAAA==.Shondo:BAAANQAECgYIBgAAAA==.',
Si='Silversmage:BAAANQAECgUIBwAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAABNQAECn8bAAICAAYKNx2mywDuAQACAAYKNx2mywDuAQAAAA==.',
Sm='Smorcin:BAABNQAECn8jAAIIAAoKFBurUwCPAgAIAAoKFBurUwCPAgAAAA==.',
Sn='Sneekybeef:BAAANQAECgYICQAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.Sosoh:BAAANQAECgQIBAABNQAECgYIGAAFANYUAA==.',
Sp='Spellnchill:BAABNQAECn8dAAICAAgKjgpg2QDVAQACAAgKjgpg2QDVAQAAAA==.Spintor:BAABNQAECn8iAAILAAcKsBV4KQDcAQALAAcKsBV4KQDcAQAAAA==.Spookyy:BAAANQAECgIIBAAAAA==.',
Sq='Squidseye:BAAANQAECgYICgAAAA==.',
St='Stainn:BAAANQAECgMIAwAAAA==.Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAQAAAA==.Stevelock:BAAANQADCgMIAwABNQADCgcIBwAdAAAAAA==.Stoade:BAAANQADCgQIBAAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stormrise:BAAANQAECgYICgAAAA==.Stricker:BAABNQAECn8tAAMhAAkKRiEYBwBRAwAhAAkKRiEYBwBRAwAaAAcKthUJKQA/AQAAAA==.',
Su='Sui:BAAANQAECgEIAQAAAA==.Sukuta:BAAANQAECgIIAgAAAA==.Sunamue:BAAANQADCgYIBgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgAdAAAAAA==.',
Sw='Sweettooth:BAAANQAECgMIBwAAAA==.',
Sy='Syphian:BAAANQADCgcIEQAAAA==.Syrenda:BAAANQADCgUIBQAAAA==.',
Ta='Taasdingo:BAAANQADCggIGQABNQAECgoKJAAHAJkZAA==.Tacoboat:BAABNQAECn9OAAIIAAoKZxPkLAAoAgAIAAoKZxPkLAAoAgAAAA==.Tacopizza:BAAANQAECgQICAAAAA==.Taishigi:BAABNQAECn8vAAIDAAoKTBWGIAA7AgADAAoKTBWGIAA7AgAAAA==.Tapewyrm:BAABNQAECn8yAAIDAAkKAxhdMADsAQADAAkKAxhdMADsAQAAAA==.Tathfak:BAAANQADCgUIBQAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECn8lAAMFAAoKAwrQWACPAQAFAAoKAwrQWACPAQABAAEKAACq5wAtAAAAAA==.Teedge:BAACNQAFFH8LAAMjAAUKgQ/5BgAlAQAjAAQKlRH5BgAlAQAkAAEKSAkdCQBLAAA1AAQKf0EAAyMACgrDHmcJANwCACMACgqfHGcJANwCACQABwrZGWUGAG8BAAAA.Teefz:BAAANQAECgUICgAAAA==.Terraphy:BAAANQADCgcIEAABNQAECgYIEgAdAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAABNQAECn8mAAISAAoKoRb9DQCNAgASAAoKoRb9DQCNAgAAAA==.Thepaintrain:BAABNQAECn8XAAMIAAcKxhAPswCdAQAIAAcKxhAPswCdAQAQAAEKAAAENAAzAAAAAA==.Theporkchop:BAAANQADCgUIBQAAAA==.Thomasa:BAAANQADCgQIBAAAAA==.Thorodron:BAAANQAECgUIBwAAAA==.Thundera:BAAANQAECgQIDgAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAABNQAECn8YAAMbAAgKKAsfVQANAQAbAAgKKAsfVQANAQAeAAUKzAFm6wCUAAAAAA==.Timmehh:BAAANQAECgcIDAABNQAFFAUICwAjAIEPAA==.Tindril:BAABNQAECn8nAAQhAAkKySHJBwBHAwAhAAgKFyXJBwBHAwAYAAUKtgqkRwCSAAAaAAEKAACBugAmAAAAAA==.Tini:BAAANQABCgYIDwAAAA==.',
To='Tolan:BAABNQAECn8cAAIEAAoKMRmAQgBbAgAEAAoKMRmAQgBbAgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAACNQAFFH8GAAIeAAIKpAiaJwBnAAAeAAIKpAiaJwBnAAA1AAQKfzYAAh4ACgpzHXcqALkCAB4ACgpzHXcqALkCAAAA.Toxcyurifeet:BAAANQAECgMIAwABNQAFFAQIDgAQABsaAA==.Toxicai:BAABNQAECn8oAAIlAAkKuRNvDgCdAQAlAAkKuRNvDgCdAQAAAA==.Toxicvoid:BAAANQAECgcIBwABNQAECgkJKAAlALkTAA==.',
Tr='Trakeus:BAABNQAECn8fAAMNAAgKABdYHAC4AQANAAgKABdYHAC4AQAHAAEKXwF/eQATAAAAAA==.Treespriest:BAAANQAECgcICwAAAA==.Treyman:BAABNQAECn8jAAIGAAkKFBTGZgBnAgAGAAkKFBTGZgBnAgAAAA==.Tribune:BAABNQAECn8yAAIFAAoK4x8EFQD+AQAFAAoK4x8EFQD+AQAAAA==.Trinitree:BAAANQAECgQIBQAAAA==.Trinkler:BAABNQAECn8WAAICAAgKpBWe0gDhAQACAAgKpBWe0gDhAQAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAABNQAECn8nAAIRAAcKkBZVCwANAgARAAcKkBZVCwANAgAAAA==.',
Ty='Tychondris:BAABNQAECn87AAIJAAoKzAn+bgBZAQAJAAoKzAn+bgBZAQAAAA==.Tyzonelfalas:BAABNQAECn8YAAIYAAgKdyKeBgCHAgAYAAgKdyKeBgCHAgAAAA==.',
Ul='Ulsoga:BAABNQAECn8zAAInAAkKaw9eBAC3AQAnAAkKaw9eBAC3AQAAAA==.',
Un='Unbórn:BAAANQAECgQIBgAAAA==.Undeadbeast:BAAANQADCgcICwAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Valkyries:BAAANQAECggIBQAAAA==.Varibash:BAAANQAECgQIBAABNQAECgoKOwALAAgaAA==.Vaspara:BAACNQAFFH8PAAIEAAQKEhtxCQBUAQAEAAQKEhtxCQBUAQA1AAQKfyQAAgQACgrZHLYfAPECAAQACgrZHLYfAPECAAAA.',
Ve='Vergalis:BAAANQAECgEIAQAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQAECgQIBAAAAA==.',
Vo='Voidlìlíth:BAABNQAECn8uAAICAAkKNRobowA7AgACAAkKNRobowA7AgAAAA==.Voidwak:BAABNQAECn8UAAIHAAcKhgIZNACMAAAHAAcKhgIZNACMAAAAAA==.Vorronni:BAABNQAECn8vAAMKAAkKvyFvDwD3AgAKAAkKvyFvDwD3AgAcAAEKFRsnIwBPAAAAAA==.',
Wa='Wardo:BAACNQAFFH8gAAMDAAcK2xmLCgDBAQADAAYKMRiLCgDBAQAiAAEKhiD2CABYAAA1AAQKf0cABAMACgqsJWMIAPMCAAMACQqZJWMIAPMCACIABwqbG5INACACACcAAQrUG0UwADUAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Warlok:BAAANQADCgcICAAAAA==.Wastedraider:BAAANQAECgUIDAAAAA==.Wastedtank:BAAANQAECgEIAQAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAABNQAECn8bAAIBAAcK1Q6fZwBzAQABAAcK1Q6fZwBzAQAAAA==.',
Wh='Whitemist:BAAANQAECgUIDQAAAA==.Whitepikmin:BAABNQAECn8qAAMYAAoK2R+UCQDbAgAYAAkK2R+UCQDbAgAZAAMKAhlLHACeAAAAAA==.',
Wi='Wilmer:BAACNQAFFH8FAAIJAAIKPQt4GACQAAAJAAIKPQt4GACQAAA1AAQKfyoAAgkACgoKH+IlAP8CAAkACgoKH+IlAP8CAAAA.Wily:BAAANQADCggIDgAAAA==.Windowsvista:BAAANQAECgYIEgAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgcICQAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQAIADwXAA==.',
Wr='Wravc:BAAANQAECgQICAAAAQ==.',
Xa='Xaspen:BAAANQAECgcICwAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.Xoyan:BAAANQAECggIEAAAAA==.',
Ya='Yargonz:BAAANQAECgcIEgAAAA==.Yargz:BAABNQAECn8XAAIXAAgKrgzoLAB1AQAXAAgKrgzoLAB1AQABNQAFFAYIHwAFAD0IAA==.Yargzdk:BAACNQAFFH8fAAIFAAYKPQiVEABOAQAFAAYKPQiVEABOAQA1AAQKfy0AAgUACgpnFq8UAAICAAUACgpnFq8UAAICAAAA.',
Ye='Yeyol:BAABNQAECn83AAMVAAoKehtHCwDMAQAVAAoK6RhHCwDMAQAWAAEKbxnKjgBMAAAAAA==.',
Yo='Yolius:BAAANQAECgQIEgAAAA==.Yoogi:BAAANQAECgEIAQABNQAECggIFgAOAKQRAA==.Youngbullet:BAAANQAECgQIBAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAABNQAECn9CAAQGAAoKZyDzIwA1AwAGAAoKZyDzIwA1AwAEAAcKwg/NgACXAQAXAAcKoBRoKwCCAQABNQAECgoKJAAHAJkZAA==.',
Za='Zabala:BAAANQABCgQIBAABNQAECggIJAAGAGwZAA==.Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zell:BAAANQAECgYIEAABNQAECgYIEgAdAAAAAA==.Zelluss:BAAANQAECgYIEgAAAA==.Zelrin:BAAANQAECgEIAgAAAA==.Zeltari:BAAANQAECgEIAQAAAA==.Zeothule:BAAANQAECggIAgAAAA==.Zephyrex:BAAANQAECgEIAQAAAA==.Zerkerpete:BAAANQAFFAEIAQAAAA==.',
Zh='Zhaphiria:BAACNQAFFH8IAAMfAAQKYRdzDABTAQAfAAQKYRdzDABTAQAkAAIKog6RCQCJAAA1AAQKfz4AAyQACgoIIZwBAN0CACQACgoIIZwBAN0CAB8ACgpxEbAPAHIBAAAA.Zhul:BAABNQAECn8mAAMJAAkKbxZWPADwAQAJAAkKbxZWPADwAQATAAEKAAB/DwAAAAABNQAECgkJKQAXAB8fAA==.',
Zi='Zimmy:BAAANQADCgYIBgAAAA==.',
Zo='Zoomies:BAAANQAECgcICwAAAA==.Zorath:BAAANQAECgIIBAAAAA==.',
Zu='Zuldahn:BAAANQADCgYIBgAAAA==.',
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
