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

local lookup = {'Mage-Arcane','Warlock-Demonology','Paladin-Holy','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Unholy','Warrior-Arms','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Hunter-Survival','Warrior-Protection','Rogue-Assassination','Paladin-Protection','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Druid-Balance','Shaman-Elemental','Priest-Discipline','Unknown-Unknown','Shaman-Restoration','Evoker-Preservation','Druid-Restoration','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absolute:BAAANQAECggIEwAAAA==.Abzclap:BAAANQAECgcIBwABNQAECgoKLwABAGojAA==.Abzdh:BAAANQAECgMIBQABNQAECgoKLwABAGojAA==.Abzlock:BAAANQAECgUICAABNQAECgoKLwABAGojAA==.Abzmage:BAABNQAECn8vAAIBAAoKaiOLEACQAwABAAoKaiOLEACQAwAAAA==.Abzp:BAAANQAECgcIEQABNQAECgoKLwABAGojAA==.Abzrogue:BAAANQAECgcIDQABNQAECgoKLwABAGojAA==.Abzsh:BAAANQAECgUICgAAAA==.',
Ac='Acoreüs:BAEBNQAECn8iAAICAAcKXQ3XngCZAQACAAcKXQ3XngCZAQAAAA==.',
Ad='Adramelk:BAAANQAECgIIBQABNQAECggIGQADALwaAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAABNQAECn8YAAIEAAYKgAmsMwCoAAAEAAYKgAmsMwCoAAAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQAECgUICwAAAA==.Allmighto:BAECNQAFFH8bAAMDAAcKLR2VAgCBAgADAAcKLR2VAgCBAgAFAAEKAAAUMABNAAA1AAQKfy4AAgMACgr7IeMFAJ4DAAMACgr7IeMFAJ4DAAAA.Alyssaxoo:BAACNQAFFH8JAAIDAAQKbQ3ZCQDTAAADAAQKbQ3ZCQDTAAA1AAQKfyMAAwMACgrqE7dLADoCAAMACgrqE7dLADoCAAUAAQoAALOzAS4AAAAA.',
Am='Amorsith:BAAANQADCggICAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQAECgEIAQAAAA==.Anniesthesia:BAAANQAECgUIDgAAAA==.Anoobyss:BAABNQAECn8VAAIGAAUKiQ5wSwD9AAAGAAUKiQ5wSwD9AAAAAA==.Anorxorcist:BAAANQAECgIIAgABNQAFFAIICwAEAOcNAA==.Anorxxorcist:BAACNQAFFH8LAAMEAAIK5w3BJABqAAAEAAIK5w3BJABqAAAHAAEKPgMtCgA8AAA1AAQKfyIAAgQACgp/Fk4RAFcBAAQACgp/Fk4RAFcBAAAA.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggIFQABNQAECgkJIAABAH8PAA==.Anyone:BAAANQAECgUIDQABNQAECgcIFwAIAMYQAA==.',
Ap='Apollouismal:BAAANQADCgIIAgAAAA==.Aporkchop:BAAANQAECgIIBQAAAA==.Applebottom:BAABNQAECn8vAAIJAAoKIR0DIgAPAwAJAAoKIR0DIgAPAwAAAA==.',
Ar='Archenemyy:BAABNQAECn8dAAMKAAgKXhtYLwBAAQAKAAgKXhtYLwBAAQALAAIKUwJZcgBCAAAAAA==.Arda:BAABNQAECn8uAAIJAAkKhyE0KAD3AgAJAAkKhyE0KAD3AgAAAA==.Arelina:BAAANQAECgIIBgAAAA==.Arune:BAAANQAECgYICgAAAA==.',
As='Aspyrx:BAABNQAECn8wAAIEAAkKGRPGCgCWAQAEAAkKGRPGCgCWAQAAAA==.Assol:BAAANQAECgEIAQAAAA==.Astelan:BAEBNQAECn8oAAILAAkKUyB+CQBHAwALAAkKUyB+CQBHAwAAAA==.Astärea:BAABNQAECn8ZAAMMAAcK7QtAFQBYAQAMAAcK7QtAFQBYAQANAAYKggZEXAASAQAAAA==.',
At='Atumsphinx:BAAANQADCgMIAwAAAA==.',
Au='Aurorä:BAAANQAECgcIDwAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgUIBwABNQAECgkJMwABAOcXAA==.Baeldaeg:BAABNQAECn8eAAMGAAoKZBeyBwCUAQAGAAoKZBeyBwCUAQAMAAIK1wyPKwBYAAAAAA==.Bahahahamut:BAABNQAECn8kAAIKAAoK4xoVHAACAwAKAAoK4xoVHAACAwABNQAECgoKHgAGAGQXAA==.Bannett:BAAANQAECgUICAAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bashing:BAAANQAECgcICgABNQAECgoKNAAEADgeAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgcIEQAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCggIDQABNQAECggIFgAOAKQRAA==.Bella:BAABNQAECn8WAAIPAAgKQwqHPgBeAQAPAAgKQwqHPgBeAQAAAA==.',
Bi='Bianchi:BAAANQAECggIEAAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bienfrosty:BAAANQAECgUIBQAAAA==.Bigbowlp:BAEANQAECgYICgABNQAFFAcIGAAQADMmAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigmonk:BAAANQADCgIIAgAAAA==.Bigpumpa:BAAANQAECgUICwAAAA==.Billygoatgrf:BAABNQAECn8iAAIRAAoKTBivAgCtAQARAAoKTBivAgCtAQAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAACNQAFFH8GAAISAAIK2AyXBQCuAAASAAIK2AyXBQCuAAA1AAQKfysAAhIACgpIH5cIAO4CABIACgpIH5cIAO4CAAAA.Blazefort:BAACNQAFFH8FAAIOAAQK6gvUDQAAAQAOAAQK6gvUDQAAAQA1AAQKfxUAAg4ACAo+FKAkAA8BAA4ACAo+FKAkAA8BAAAA.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECn8rAAITAAkKZRRXBQBsAgATAAkKZRRXBQBsAgAAAA==.Bludskal:BAAANQADCgYIBgABNQAECgoKNAAEADgeAA==.Bløod:BAAANQAECgEIAQAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boosteddots:BAAANQAECgcICQAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAABNQAECn8VAAQQAAYKiBMTFQBNAQAQAAYKLBETFQBNAQAUAAUKJxCkKgDkAAAIAAQKYxR5BAHUAAABNQAECgoKHgAGAGQXAA==.Breemonic:BAABNQAECn8bAAINAAoKKwiLQgCtAQANAAoKKwiLQgCtAQAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Britannican:BAAANQAECgEIAQAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAACNQAFFH8MAAQQAAUKrhuBAADlAQAQAAUKrhuBAADlAQAUAAIK8giGBwBqAAAIAAEK/RklPABJAAA1AAQKfyYABBAACgrMIIQDAI4BABQACQoWGA0MAHYCAAgACQpUGm5nAFkCABAABQqiJIQDAI4BAAAA.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQAECgQIBgAAAA==.Bullshoc:BAAANQADCgIIAgAAAA==.Bullwrinkle:BAAANQADCggICAAAAA==.Burgleslight:BAAANQAECgEIAQAAAA==.Butturz:BAABNQAECn8UAAILAAYKJiGWHQBUAgALAAYKJiGWHQBUAgAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQAECgIIAwAAAA==.Cailleach:BAAANQAECgIIAwAAAA==.Cainz:BAABNQAECn8VAAIVAAgKZQ1MGQD/AAAVAAgKZQ1MGQD/AAAAAA==.Caraxes:BAAANQAECgQIBQABNQAECgoKOwATAJQfAA==.Carson:BAAANQAECgUIBQAAAA==.',
Ce='Celeryman:BAABNQAECn8YAAQFAAgKdRrqfgAsAgAFAAgKdRrqfgAsAgADAAMKWQWW+wCGAAAWAAIKPQs2ZQBMAAAAAA==.Celian:BAAANQAECgEIAQAAAA==.Centuro:BAAANQAECgIIBAAAAA==.',
Ch='Chillywillie:BAAANQAECgUIBQABNQAECgkJKAABAA8XAA==.Chobi:BAABNQAECn8aAAMXAAkKnCQCAgC1AwAXAAkKnCQCAgC1AwAYAAEKAACmOQBVAAABNQAECgkJKQAEAIsgAA==.',
Ci='Cinnamen:BAABNQAECn8lAAIZAAoKJx4DBwANAwAZAAoKJx4DBwANAwAAAA==.',
Cl='Claudine:BAAANQAECgUIEAABNQAECggIGQABANcDAA==.Clearstoned:BAAANQADCgUIBQABNQAFFAMIBQABABEOAA==.',
Co='Coaa:BAABNQAECn8cAAIJAAcK3hQciQD4AQAJAAcK3hQciQD4AQAAAA==.Colossus:BAABNQAECn8UAAIFAAcK1gT8FAH8AAAFAAcK1gT8FAH8AAAAAA==.Contrap:BAABNQAECn8nAAIJAAoKNRcPWgBmAgAJAAoKNRcPWgBmAgAAAA==.Coolbreeze:BAABNQAECn8cAAIXAAcKvhpaCgBVAQAXAAcKvhpaCgBVAQAAAA==.Corpsgrinder:BAACNQAFFH8FAAIVAAIKwAvhFQCcAAAVAAIKwAvhFQCcAAA1AAQKfxoAAhUACgprG70bAKACABUACgprG70bAKACAAAA.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQAECgEIAQAAAA==.Crõwfather:BAAANQAECgIIAgAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQAECgQIBwAAAA==.Damagenpayne:BAAANQABCgEIAQAAAA==.Darkmeadow:BAABNQAECn8XAAIaAAYKfg2VJwDGAAAaAAYKfg2VJwDGAAAAAA==.Dastard:BAABNQAECn8lAAIbAAoKahj6MQCyAgAbAAoKahj6MQCyAgAAAA==.',
De='Deadlock:BAAANQAECgEIAgAAAA==.Deadplank:BAABNQAECn8eAAIEAAgKJRbaDQB2AQAEAAgKJRbaDQB2AQAAAA==.Deathlyfrost:BAAANQAECgEIAQAAAA==.Deathstouch:BAAANQAECgEIAgAAAA==.Deftonia:BAABNQAECn8eAAIFAAoK4gTvcgDhAAAFAAoK4gTvcgDhAAAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAABNQAECn8rAAMJAAoKSx4ZDwD4AQAJAAoKSx4ZDwD4AQAPAAEKsAE9nQAiAAAAAA==.Demonbläde:BAAANQAECgcICAAAAA==.Dethany:BAABNQAECn8XAAIbAAYK4QXkwQAOAQAbAAYK4QXkwQAOAQABNQAECggIGQABANcDAA==.Devondric:BAABNQAECn9DAAMKAAoKaSFwBQCdAwAKAAoKaSFwBQCdAwAcAAEKeQbdLQApAAAAAA==.Devotion:BAAANQAECgEIAQABNQAFFAQIFQADAL4SAA==.Devotional:BAACNQAFFH8VAAMDAAQKvhJMEgA8AQADAAQKvhJMEgA8AQAFAAIKkQGRLABsAAA1AAQKfz8AAwMACgpQHeMYABUDAAMACgpQHeMYABUDAAUAAwqDEbpDAbQAAAAA.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQADCggICAABNQAECgkJKgAFAO0aAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcICgAAAA==.',
Dm='Dmatch:BAAANQAECgYIDgAAAA==.',
Do='Docholigay:BAAANQAECgMIBgAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgAdAAAAAA==.Dommymilkies:BAAANQAECgEIAQABNQAECggIFgANAA8WAA==.Doozpal:BAABNQAECn8wAAIDAAkKhheRMwCWAgADAAkKhheRMwCWAgAAAA==.Dorinspins:BAEBNQAECn8eAAIIAAkKZRk9WACDAgAIAAkKZRk9WACDAgAAAA==.Downset:BAAANQAECgMIAwABNQAECgkJMwABAOcXAA==.',
Dr='Drakonman:BAAANQAECgIIAwAAAA==.Draynen:BAABNQAECn8tAAMSAAkKUSOuAgB8AwASAAkKUSOuAgB8AwAeAAIKShBf8gCFAAABNQAFFAQICAAfAGEXAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgUICgAAAA==.Drezd:BAABNQAECn81AAIPAAoKRw6wKAAFAgAPAAoKRw6wKAAFAgAAAA==.',
Du='Duck:BAAANQAECgEIAwABNQAECgcIDAAdAAAAAA==.Duckduck:BAAANQAECgEIAQABNQAECgcIDAAdAAAAAA==.Dulcïnea:BAAANQAECggICgABNQAECgoKKwAJAEseAA==.Dumpymilk:BAAANQAECgEIAQABNQAECgoKHgAGAGQXAA==.',
Ea='Eao:BAABNQAECn8xAAIJAAoK7AtbNgBPAQAJAAoK7AtbNgBPAQAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgAdAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgYIEAAdAAAAAA==.',
El='Elblaize:BAAANQAECgEIAgAAAA==.Elitistjerk:BAAANQADCgEIAQAAAA==.Eliza:BAAANQADCggICAAAAA==.Ellisis:BAABNQAECn8fAAIWAAgK1RyMEwBqAgAWAAgK1RyMEwBqAgAAAA==.',
Em='Emriq:BAABNQAECn8kAAIFAAgKbBmwdgA/AgAFAAgKbBmwdgA/AgAAAA==.',
En='Enmai:BAABNQAECn8iAAICAAgKVwsiUwDdAAACAAgKVwsiUwDdAAAAAA==.',
Ep='Epiphany:BAABNQAECn8ZAAIBAAgK1wPMIwFQAQABAAgK1wPMIwFQAQAAAA==.',
Er='Eraylina:BAABNQAECn8gAAIBAAkKfw9KEQDcAQABAAkKfw9KEQDcAQAAAA==.Ertivoker:BAAANQADCggICAABNQAECgoKIgARAEwYAA==.',
Eu='Eugima:BAAANQAECgEIAQAAAA==.Eulogy:BAABNQAECn8xAAMKAAoKkRi+fACjAQAKAAUK9hy+fACjAQALAAoKNBbvBgCIAQAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQAECgEIAwAAAA==.',
Ex='Exxitus:BAAANQAECgUICQAAAA==.',
Fa='Faerielana:BAEBNQAECn8WAAIBAAgKxAuS2gDSAQABAAgKxAuS2gDSAQABNQAECggIGgAgAAoXAA==.Faith:BAAANQAECgMIBwAAAA==.Falsoqt:BAABNQAECn8VAAIhAAkKOhorBwCUAgAhAAkKOhorBwCUAgAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAcIGwADAC0dAA==.',
Fe='Fecalmatters:BAAANQAECgEIBAAAAA==.Felachio:BAABNQAECn8vAAIJAAkK3he8DAAMAgAJAAkK3he8DAAMAgAAAA==.',
Fi='First:BAAANQAECgEIAQAAAA==.',
Fj='Fjörgyn:BAACNQAFFH8cAAIbAAcKOyBJAQDKAgAbAAcKOyBJAQDKAgA1AAQKfyoAAhsACgqTIj0OAHcDABsACgqTIj0OAHcDAAAA.',
Fl='Flankster:BAAANQAECgMIBwAAAA==.Flanksterr:BAAANQAECgQICgAAAA==.',
Fo='Fork:BAABNQAECn83AAIOAAoKiSV4AQDbAwAOAAoKiSV4AQDbAwAAAA==.Forsetí:BAAANQAECgEIAQAAAA==.Fozziedaburr:BAABNQAECn8mAAMgAAoKyRw/DAAIAwAgAAoKyRw/DAAIAwAaAAUKBxU1YgBGAQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAABNQAECn8jAAIBAAoKMxsAFwC1AQABAAoKMxsAFwC1AQAAAA==.',
Ft='Ftfk:BAAANQADCggIFgABNQAECgoKKwAfABwjAA==.',
Ga='Galie:BAACNQAFFH8GAAIaAAIKewMQJABlAAAaAAIKewMQJABlAAA1AAQKfykAAxoACgplEVQzAEsCABoACgplEVQzAEsCABcABQohDd08AMwAAAAA.Galiè:BAAANQADCgUICwAAAA==.Garrahoth:BAABNQAECn8WAAMOAAgKpBHNCADMAQAOAAgKog/NCADMAQAHAAYK7QxpewAuAQAAAA==.',
Ge='Gekk:BAABNQAECn8wAAMfAAkKbhFkAgAaAgAfAAkKbhFkAgAaAgAiAAUKIwrKJwD0AAAAAA==.',
Gi='Giaus:BAABNQAECn8iAAIBAAoKFxxLfwCAAgABAAoKFxxLfwCAAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Gleipnir:BAAANQAECgMIAwAAAA==.Glimmerwisp:BAABNQAECn8gAAIBAAkKNAwdxwD2AQABAAkKNAwdxwD2AQAAAA==.',
Go='Gobzilla:BAABNQAECn8cAAMeAAkKKBFjdACuAQAeAAkKKBFjdACuAQAbAAIK6gt6ZABwAAAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgcIEwAAAA==.',
Gr='Grapefantuh:BAAANQAECgQICAAAAA==.Grapefroot:BAAANQADCgcICQAAAA==.Grapeinator:BAABNQAECn8aAAIFAAkKTRASmgDvAQAFAAkKTRASmgDvAQAAAA==.Grasseater:BAAANQADCgYIBgABNQAFFAMICwADAPobAA==.Grimreapr:BAAANQAECgIIBAAAAA==.Grimrieber:BAABNQAECn8gAAMUAAkKCxzrDwArAgAUAAgKZBvrDwArAgAIAAEK9B+gpgBeAAAAAA==.Gromn:BAABNQAECn87AAQTAAoKlB/hAQA8AwATAAoKlB/hAQA8AwAJAAMKlQZ4KwGZAAAPAAEKegV2lwApAAAAAA==.',
Ha='Happywoodz:BAAANQAECgEIAQABNQAECgoKKAAeALogAA==.Hashed:BAABNQAECn8bAAIFAAoKoh5IOADvAgAFAAoKoh5IOADvAgAAAA==.Hays:BAAANQAECgcICwAAAA==.Haysevoker:BAACNQAFFH8eAAQjAAcK/RpKAQBqAQAjAAUKQhdKAQBqAQAfAAIKmw4eFACOAAAiAAIKcRbeCwCLAAA1AAQKfyQABCMACgooH7AEALQCACMACgonH7AEALQCACIACApnDroZAK0BAB8AAwrEDVo9ALEAAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.Herself:BAAANQAECgEIAQABNQAECgcIFwAIAMYQAA==.',
Hi='Highs:BAAANQAECggICAAAAA==.Himself:BAAANQAECgEIAgAAAA==.Himsmart:BAAANQADCgYICgABNQAECgoKHgAGAGQXAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECn8XAAMKAAgKqyIjFwAcAwAKAAgKqyIjFwAcAwAcAAEKOQ9/KAA0AAAAAA==.Hoodler:BAECNQAFFH8WAAIgAAcKEBwPAQD1AQAgAAcKEBwPAQD1AQA1AAQKfzEAAyAACgo9JJACAKQDACAACgo9JJACAKQDABgAAQp0FT4+AEAAAAAA.Hoodlery:BAECNQAFFH8LAAIkAAYK+CBKAgANAgAkAAYK+CBKAgANAgA1AAQKfx0AAiQACQpTHvYJAOkCACQACQpTHvYJAOkCAAE1AAUUBwgWACAAEBwA.Hoofjob:BAACNQAFFH8WAAIlAAcKPBCcAQBqAQAlAAcKPBCcAQBqAQA1AAQKfyoAAiUACgoCH2kYAIQCACUACgoCH2kYAIQCAAAA.',
Hu='Huskydots:BAACNQAFFH8KAAMCAAMKyBIGDwCgAAACAAIK2BIGDwCgAAAhAAEKqhLKBwBYAAA1AAQKfyoAAwIACgpmFykxADUBAAIACQqdFykxADUBACEAAworDt9IAKUAAAAA.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQAECgIIAwABNQAECgkJLwAJAN4XAA==.',
Ib='Iblastpants:BAABNQAECn8UAAIlAAYKPghuQAATAQAlAAYKPghuQAATAQAAAA==.',
Id='Idd:BAAANQAECgIIBQAAAA==.',
Ig='Iggyy:BAABNQAECn8VAAICAAcKog2QaACyAAACAAcKog2QaACyAAAAAA==.',
Im='Imshaman:BAAANQAECgUIBQAAAA==.',
In='Inflammo:BAAANQAECgEIAgAAAA==.Insaneisbad:BAAANQADCggICQAAAA==.Insaneness:BAABNQAECn8eAAIHAAoKwA2uBgDDAQAHAAoKwA2uBgDDAQAAAA==.',
Ir='Irila:BAAANQAECgQICAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgUIEgABNQAECgcIFwAIAMYQAA==.',
Iz='Izumî:BAAANQADCggIEwAAAA==.',
Ja='Jackdáripper:BAAANQABCgYIBgAAAA==.Jakè:BAAANQAECgIIAgAAAA==.Jangosan:BAAANQAECgIIAgABNQAECgoKLAAZACkUAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgYICgAAAA==.Jaspy:BAABNQAECn8yAAIXAAoKthnABgCYAQAXAAoKthnABgCYAQAAAA==.',
Je='Jeffdennis:BAABNQAECn8eAAIIAAoKwhChdAA3AgAIAAoKwhChdAA3AgAAAA==.',
Ji='Jimmybuffler:BAABNQAECn8XAAIDAAgKBRtsOwB3AgADAAgKBRtsOwB3AgAAAA==.',
Jo='Jomgpallie:BAABNQAECn8kAAIFAAoKzw7eJACRAQAFAAoKzw7eJACRAQAAAA==.Jonra:BAAANQAECgEIAQAAAA==.Josefbugman:BAAANQAECgQIBwAAAA==.',
Ju='Judykiki:BAAANQAECgUICwABNQAECgYIGAAEANYUAA==.Juecy:BAAANQAECgcIBwAAAA==.Juju:BAAANQAECgcIEwAAAA==.Juktal:BAABNQAECn8eAAITAAgK+hGpBgAmAgATAAgK+hGpBgAmAgAAAA==.Justyn:BAABNQAECn8fAAMIAAcKphIkRAAaAQAIAAcKphIkRAAaAQAUAAEKAAC/TgARAAAAAA==.',
Jv='Jva:BAAANQAECgUIBAAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcICQAAAA==.Kainamahs:BAAANQAECgQIBAAAAA==.Kainz:BAAANQAECgIIBAAAAA==.Kanokoa:BAAANQAECgEIAQAAAA==.Kaonazor:BAAANQADCgYIBgAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Karbonette:BAAANQADCgYIBgAAAA==.Kattakuri:BAAANQAECgQICAAAAA==.Kazaju:BAABNQAECn8ZAAMhAAkKuh51LQAWAQACAAYKdhx1iADRAQAhAAMKYSR1LQAWAQAAAA==.',
Ki='Kialorstus:BAABNQAECn8iAAQOAAoKDRUCKwBEAgAOAAoKDRUCKwBEAgAHAAQKIgs0pQCvAAAEAAEK5gSD0wAqAAAAAA==.Kinzington:BAAANQAECgcIEQABNQAECgkJMwABAOcXAA==.Kirbo:BAAANQAECgcIDQAAAA==.Kitagawa:BAABNQAECn80AAIEAAoKOB6BFgD5AgAEAAoKOB6BFgD5AgAAAA==.Kitten:BAAANQAECgYIDwAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUICgAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAABNQAECn8aAAIFAAoKIw5anADqAQAFAAoKIw5anADqAQAAAA==.',
Kr='Kradyn:BAAANQAECgYIDAAAAA==.Kragfoerend:BAABNQAECn8dAAIIAAcK5gP/fwCeAAAIAAcK5gP/fwCeAAAAAA==.Kramx:BAAANQAECgMIBAAAAA==.Krankenstein:BAABNQAECn8wAAIEAAkKrRhSCQCmAQAEAAkKrRhSCQCmAQAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAABNQAECn8iAAIVAAkKfCLJAAD+AgAVAAkKfCLJAAD+AgAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgYIBwAAAA==.',
Ku='Kuhtta:BAAANQAECgUIEwAAAA==.Kumdobeast:BAAANQAECgQIEAAAAA==.Kuothe:BAAANQAECgUIEgAAAA==.',
Ky='Kyina:BAAANQAECgEIAQAAAA==.Kyotpal:BAAANQADCgYIDAAAAA==.Kyotsas:BAAANQAECggIBwAAAA==.',
La='Lazyriver:BAABNQAECn8fAAIOAAcKLgyCMgDTAAAOAAcKLgyCMgDTAAABNQAECgcKHwAOAC4MAA==.',
Le='Legoland:BAAANQAECggIBAAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAABNQAECn8dAAIaAAkK4g4CQwDpAQAaAAkK4g4CQwDpAQAAAA==.Lewakex:BAAANQAECggIEgAAAA==.Leyninade:BAABNQAECn8aAAIaAAgKQxSXOwAYAgAaAAgKQxSXOwAYAgAAAA==.',
Li='Lightbrngr:BAABNQAECn8xAAIFAAoKVxu1FgDKAQAFAAoKVxu1FgDKAQAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggIDAAAAA==.Lilbertha:BAAANQAECgIIBAAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIGAABNQAECgoKHgAGAGQXAA==.Lildump:BAAANQAECgYIEwABNQAECgoKFgAeACscAA==.Limitlessone:BAABNQAECn8aAAIBAAcKCh79mABOAgABAAcKCh79mABOAgAAAA==.Lionescanor:BAAANQAECgMIAwAAAA==.Liptonaysti:BAAANQAECgQIDQAAAA==.Lissandine:BAEBNQAECn8mAAMMAAoKYBJQCwAbAgAMAAoKYBJQCwAbAgANAAUKHgTqbgC9AAAAAA==.Liya:BAAANQAECgEIAwABNQAFFAUIDQAEABUhAA==.Lizzywizzy:BAAANQADCgYIBgABNQAECgoKHgAGAGQXAA==.',
Lo='Locrian:BAAANQAECgEIAgAAAA==.Lokikillz:BAAANQAECgYIEQAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAABNQAECn8rAAMIAAkKohMhcgA+AgAIAAkKyxIhcgA+AgAQAAIKeBgxJgB8AAAAAA==.',
Lu='Luulk:BAABNQAECn8YAAMEAAYK1hSfYQBrAQAEAAYK1hSfYQBrAQAOAAEKAADYdwAAAAAAAA==.',
Ly='Lych:BAAANQAECgcIDgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgcIDwAAAA==.Lìvíd:BAAANQADCgIIAgAAAA==.',
Ma='Madoris:BAABNQAECn8VAAMgAAUKRwtvJAC1AAAgAAUKRwtvJAC1AAAaAAQKAgi2jQCfAAAAAA==.Madscience:BAAANQADCggICAAAAA==.Magemagerson:BAABNQAECn8kAAIBAAoK9yAtCABHAgABAAoK9yAtCABHAgAAAA==.Magnuss:BAABNQAECn8ZAAMBAAoKcgf45gC7AQABAAoKcgf45gC7AQARAAIKJQMyPABPAAAAAA==.Magvox:BAAANQAECgEIAQAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAABNQAECn8eAAIOAAcK1A/5IgAXAQAOAAcK1A/5IgAXAQAAAA==.Mammutos:BAABNQAECn8hAAIgAAcKYBh+BwDJAQAgAAcKYBh+BwDJAQAAAA==.Manifred:BAAANQADCgYIFAAAAA==.Manion:BAABNQAECn8qAAMeAAoK6B0PIQDlAgAeAAoK6B0PIQDlAgAbAAcKJxBEjgCAAQAAAA==.Manipepper:BAABNQAECn8ZAAMCAAYKcgd7fQCIAAACAAYKcgd7fQCIAAAhAAIK6gRkZwBUAAAAAA==.Manippiez:BAAANQAECgMIBwAAAA==.Manipulating:BAAANQADCgYICgAAAA==.Manipulation:BAAANQAECgMIBAAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQAECgIIAgAAAA==.Maplemaga:BAAANQAECggIDQAAAA==.Margot:BAAANQADCgYIDAABNQAECgUICwAdAAAAAA==.Masochista:BAACNQAFFH8NAAIEAAUKFSFwDQB8AQAEAAUKFSFwDQB8AQA1AAQKfxwAAgQACgpIJWcIAHgDAAQACgpIJWcIAHgDAAAA.Mastric:BAEBNQAECn8wAAICAAoKXAZoRAADAQACAAoKXAZoRAADAQAAAA==.',
Mc='Mccaffrey:BAABNQAECn8wAAMIAAkKkRSGHwCGAQAIAAkKkRSGHwCGAQAQAAIKAQ44FQBEAAAAAA==.',
Me='Meetch:BAACNQAFFH8FAAIHAAMKzxhGAgAEAQAHAAMKzxhGAgAEAQA1AAQKfycAAgcACApdHW0mAKMCAAcACApdHW0mAKMCAAAA.Megdar:BAABNQAECn8WAAIlAAcKwwwDNgBlAQAlAAcKwwwDNgBlAQAAAA==.Melledreu:BAACNQAFFH8GAAIRAAIKtAL1CQB1AAARAAIKtAL1CQB1AAA1AAQKf2QAAxEACgqiC/gOALsBABEACQooDPgOALsBAAEACgo0Ban+AJABAAAA.Mellessan:BAAANQAECgEIBAAAAA==.Merix:BAABNQAECn8nAAMVAAkKtx8HRwCpAQAVAAUK8h8HRwCpAQAZAAUKtx2IJwCKAQAAAA==.Mestea:BAABNQAECn8dAAMeAAcK7wk9pAArAQAeAAcK7wk9pAArAQAbAAYK0gd6VQCUAAAAAA==.Mewing:BAAANQAECgQIBAABNQAECgkJJgAFAMwjAA==.',
Mi='Miraclemill:BAAANQADCgcIFQAAAA==.Mirra:BAABNQAECn8dAAIKAAgKpxWYawDbAQAKAAgKpxWYawDbAQAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momoshirow:BAAANQADCgQIBwAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAABNQAECn8iAAIBAAoKVRITkgBbAgABAAoKVRITkgBbAgAAAA==.Mortelinnos:BAABNQAECn8xAAINAAoKbCSRAgCGAgANAAoKbCSRAgCGAgAAAA==.',
My='Mysticguru:BAABNQAECn8cAAIeAAYKVh1WbwC9AQAeAAYKVh1WbwC9AQAAAA==.Mythrax:BAABNQAECn8hAAMTAAkKcxvRAgD8AgATAAkKcxvRAgD8AgAPAAIKpwZ5dgBjAAAAAA==.',
['Mà']='Mànion:BAAANQAECgEIAQAAAA==.',
Na='Naisu:BAAANQAECggICAAAAA==.Naradrae:BAAANQAECgYIEAAAAA==.Narodaran:BAAANQAECggIDAAAAA==.Naughtyrawr:BAAANQAECgUIDAAAAA==.',
Ne='Necropete:BAAANQAECgIIAgABNQAFFAEIAQAdAAAAAA==.Neondemon:BAAANQAECgMIBQAAAA==.Nevets:BAABNQAECn8sAAIPAAoKUx4xBAC+AQAPAAoKUx4xBAC+AQAAAA==.Nevrs:BAAANQAECgYIEQAAAA==.Newworld:BAAANQAECgEIAQAAAA==.',
Ni='Nikolajokic:BAAANQAECgIIAwAAAA==.Nimit:BAABNQAECn8pAAIJAAgKEBxfHwCaAQAJAAgKEBxfHwCaAQAAAA==.',
No='Noazora:BAAANQAECgEIAQAAAA==.Noughtsee:BAABNQAECn8fAAIBAAcKGQrXkQCjAAABAAcKGQrXkQCjAAAAAA==.Novic:BAABNQAECn8mAAIKAAoKPxHcZADxAQAKAAoKPxHcZADxAQAAAA==.Noxinox:BAAANQADCgYIBwAAAA==.Nozom:BAAANQADCgEIAQABNQAECggIFgAOAKQRAA==.',
Nu='Nualia:BAABNQAECn8mAAIFAAoKsh3AHgCnAQAFAAoKsh3AHgCnAQAAAA==.',
['Né']='Némésis:BAAANQAECgUIDwAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAABNQAECn8VAAISAAgKCBQFFgAIAgASAAgKCBQFFgAIAgAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAACNQAFFH8KAAIQAAMKuRdXAAD9AAAQAAMKuRdXAAD9AAA1AAQKfxsAAxAACgo4HQwGALICABAACQo4HQwGALICABQAAQoAAIo8AFMAAAAA.',
Os='Oscassey:BAABNQAECn8wAAIVAAkKYAq9CQCEAQAVAAkKYAq9CQCEAQAAAA==.',
Ox='Oxley:BAABNQAECn8jAAIYAAkKSBiuAQAFAgAYAAkKSBiuAQAFAgAAAA==.',
Pa='Paladingus:BAABNQAECn8gAAMFAAkKoB7meQA4AgAFAAkKChzmeQA4AgAWAAQKbCAYMABdAQAAAA==.Pandidin:BAABNQAECn8kAAMkAAgKlxYMGAD+AQAkAAgKlxYMGAD+AQAlAAIKuQ0CYABgAAAAAA==.Parrythìs:BAAANQABCgIIAgABNQAECgMIAwAdAAAAAA==.Pauldrons:BAACNQAFFH8GAAMHAAIKzgmVGgCGAAAHAAIKzgmVGgCGAAAOAAEKowLxIQA1AAA1AAQKf04AAwcACgpiEVdDAA0CAAcACgpZEVdDAA0CAA4ABwrPBohgACMBAAAA.',
Pe='Peenar:BAABNQAECn8cAAQPAAkKsyFxDwDxAgAPAAgKsyFxDwDxAgAJAAIK8iMXIQG5AAATAAIKJhzRDgCvAAAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAABNQAECn8eAAICAAcKTxerMQA0AQACAAcKTxerMQA0AQAAAA==.Pharlòck:BAAANQADCgUIBgABNQAECgcIHgACAE8XAA==.Phobia:BAAANQADCggICAABNQAECgoKMQAKAJEYAA==.',
Pi='Picklelips:BAAANQADCgQIBQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankmedaddy:BAAANQADCgYIBgAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAwAAAA==.Plankz:BAAANQADCggICQAAAA==.',
Po='Pooterdiddle:BAAANQAECgUICAAAAA==.',
Pr='Priesttess:BAAANQADCgcICgAAAA==.Prohealin:BAABNQAECn8qAAIKAAoKuApEQwD+AAAKAAoKuApEQwD+AAAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.Psychosís:BAAANQADCgQIBAAAAA==.',
Pt='Ptiteagacee:BAABNQAECn8eAAQLAAgK6BtNJwDxAQALAAYK4RpNJwDxAQAKAAYKTxnfaADkAQAcAAUKGhrsCwB+AQAAAA==.',
Pu='Pufdaddy:BAABNQAECn8VAAIfAAcKPA4rCQAvAQAfAAcKPA4rCQAvAQAAAA==.Puffpuffy:BAAANQADCgYIBgAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECggIJAAJAO8bAA==.Pumpkinq:BAABNQAECn9JAAMZAAoK7CEpAwBzAwAZAAoK3SEpAwBzAwAVAAQKvBrnZwATAQAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAABNQAECn8xAAMBAAoKixkpGgCnAQABAAoKixkpGgCnAQARAAMK7xglJQDGAAAAAA==.',
Ra='Raby:BAAANQADCgYIBgAAAA==.Ragemommie:BAAANQAECgMIBAABNQAECgUIBgAdAAAAAA==.Rainer:BAAANQAECgEIAgAAAA==.Ramiel:BAAANQAECgEIAgAAAA==.Rasmus:BAABNQAECn8lAAIWAAoKgxOCCQBiAQAWAAoKgxOCCQBiAQAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAABNQAECn8rAAIfAAoKHCPdAQBOAgAfAAoKHCPdAQBOAgAAAA==.Razzahola:BAAANQADCgIIAgABNQAECgQIBQAdAAAAAA==.Razzmatazz:BAABNQAECn8tAAIBAAkKdhiUDQD+AQABAAkKdhiUDQD+AQAAAA==.',
Re='Reddeyes:BAABNQAECn8hAAIiAAcKWQhQCQDVAAAiAAcKWQhQCQDVAAAAAA==.Regulüs:BAABNQAECn8VAAIWAAkKcxe+DQApAQAWAAkKcxe+DQApAQAAAA==.Rescue:BAABNQAECn8zAAIBAAkK5xdwcQCbAgABAAkK5xdwcQCbAgAAAA==.Reva:BAEANQAECgcICQABNQAECgkJKAALAFMgAA==.',
Ri='Rinedara:BAAANQADCgMIAwAAAA==.Rising:BAAANQAECgEIAQAAAA==.',
Ro='Roamin:BAAANQADCggICAAAAA==.Roasted:BAABNQAECn8xAAIBAAoKqxmlIQCMAQABAAoKqxmlIQCMAQAAAA==.Rockma:BAAANQAECggICwAAAA==.Rollandburn:BAAANQAECgQIEQAAAA==.Romantacykmc:BAAANQADCgcIFQABNQADCgYICwAdAAAAAA==.Roxymigurdia:BAABNQAECn8jAAIJAAoKWiUxBADGAwAJAAoKWiUxBADGAwAAAA==.',
Ru='Rufföaddy:BAABNQAECn8xAAIDAAoK1iJvCAA9AgADAAoK1iJvCAA9AgAAAA==.Rumproast:BAAANQAECgMIBgABNQAECggIFgAOAKQRAA==.Runeesa:BAABNQAECn8ZAAIJAAcKEgtFWQD7AAAJAAcKEgtFWQD7AAAAAA==.',
Ry='Rylena:BAABNQAECn8iAAMJAAgKcCByLQBoAQAJAAgKcCByLQBoAQAPAAUK3BCzTQD6AAAAAA==.Ryuke:BAAANQAECgYIDQAAAA==.Ryvalry:BAAANQAECgEIAQAAAA==.',
['Rà']='Ràvenn:BAAANQAECgEIAQABNQAECgYIDwAdAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
['Rã']='Rãmbõ:BAAANQADCgMIBAAAAA==.',
Sa='Sagikos:BAEBNQAECn8aAAMgAAgKChdRIgAUAgAgAAgKChdRIgAUAgAaAAEKFAlurgA5AAAAAA==.Sandrid:BAAANQABCgMIAwAAAA==.Sardras:BAABNQAECn8sAAIgAAoKHSQNBwBSAwAgAAoKHSQNBwBSAwAAAA==.Sark:BAAANQAECgYICQAAAA==.Sathor:BAAANQAECgUICgAAAA==.Sauccyy:BAAANQAECgQIBQAAAA==.Saucecity:BAAANQAECgQIBQAAAA==.Saucyjenkins:BAAANQAECgcIDgAAAA==.',
Sc='Scranton:BAAANQAECgEIAQAAAA==.',
Se='Sean:BAAANQADCgYICwAAAA==.Selest:BAAANQADCgEIAQAAAA==.Sellout:BAAANQAECgEIAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQAECggICQAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUIDQABNQAECggIGgAgAAoXAA==.Shamerific:BAAANQAECgEIAQAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgcIFgADAIgkAA==.Shammooz:BAACNQAFFH8GAAISAAIKpRlgBQC4AAASAAIKpRlgBQC4AAA1AAQKf2oAAhIACgqMHQQDAPgBABIACgqMHQQDAPgBAAAA.Shamyshaman:BAAANQAECgEIAgAAAA==.Shinier:BAABNQAECn8wAAIDAAoKrSPxBACoAwADAAoKrSPxBACoAwAAAA==.Shockwoods:BAABNQAECn8oAAMeAAoKuiA7AgApAwAeAAoKuiA7AgApAwAbAAIK7A4DDAFzAAAAAA==.Shondo:BAAANQAECgYIBgAAAA==.',
Si='Silversmage:BAAANQAECgUICgAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAABNQAECn8bAAIBAAYKNx2mywDuAQABAAYKNx2mywDuAQAAAA==.',
Sm='Smorcin:BAABNQAECn8jAAIIAAoKFBurUwCPAgAIAAoKFBurUwCPAgAAAA==.',
Sn='Sneekybeef:BAAANQAECgYICQAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.Sosoh:BAAANQAECgQIBgABNQAECgYIGAAEANYUAA==.',
Sp='Spellnchill:BAABNQAECn8WAAIBAAgKSApg2QDVAQABAAgKSApg2QDVAQAAAA==.Spintor:BAABNQAECn8fAAILAAcKsBX2DQAoAQALAAcKsBX2DQAoAQAAAA==.Spookyy:BAAANQAECgIIAgAAAA==.',
Sq='Squidseye:BAAANQAECgYIDQAAAA==.',
St='Stainn:BAAANQAECgMIAwAAAA==.Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAgAAAA==.Stevelock:BAAANQADCgMIAwABNQAECgEIAQAdAAAAAA==.Stoade:BAAANQAECgEIBQAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stormrise:BAAANQAECgYIDQAAAA==.Stricker:BAABNQAECn8qAAMgAAkKRiEYBwBRAwAgAAkKRiEYBwBRAwAaAAYK+hUnHAAFAQAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Sunamue:BAAANQADCgYIBgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgAdAAAAAA==.',
Sw='Sweettooth:BAAANQAECgMIBgAAAA==.',
Sy='Syphian:BAAANQAECgEIBAAAAA==.Syrenda:BAAANQADCgUIBQAAAA==.',
Ta='Taasdingo:BAAANQADCggIEgABNQAECgoKHgAGAGQXAA==.Tacoboat:BAABNQAECn85AAIIAAkKBgzwGQCeAQAIAAkKBgzwGQCeAQAAAA==.Tacopizza:BAAANQADCggIDgAAAA==.Taishigi:BAABNQAECn8lAAICAAoKyxDdDQDYAQACAAoKyxDdDQDYAQAAAA==.Tapewyrm:BAABNQAECn8qAAICAAkKyhfICQALAgACAAkKyhfICQALAgAAAA==.Tathfak:BAAANQADCgUIBQAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECn8iAAMEAAoKYAjQWACPAQAEAAoKYAjQWACPAQAHAAEKAACq5wAtAAAAAA==.Teedge:BAACNQAFFH8KAAIiAAQKlRH5BgAlAQAiAAQKlRH5BgAlAQA1AAQKfzYAAyIACgr4HGcJANwCACIACgppG2cJANwCACMABQrMG3oQADABAAAA.Teefz:BAAANQAECgUICwAAAA==.Terraphy:BAAANQADCgYICwABNQAECgUIDgAdAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAABNQAECn8eAAISAAoKKxX9DQCNAgASAAoKKxX9DQCNAgAAAA==.Thepaintrain:BAABNQAECn8XAAMIAAcKxhAPswCdAQAIAAcKxhAPswCdAQAQAAEKAAAENAAzAAAAAA==.Theporkchop:BAAANQADCgUIBQAAAA==.Thomasa:BAAANQAECgEIAgAAAA==.Thorodron:BAAANQAECgUIBAAAAA==.Thundera:BAAANQAECgQIEQAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgUIEQAAAA==.Timmehh:BAAANQAECgcICgABNQAFFAQICgAiAJURAA==.Tindril:BAABNQAECn8nAAQgAAkKySHJBwBHAwAgAAgKFyXJBwBHAwAXAAUKtgqkRwCSAAAaAAEKAACBugAmAAAAAA==.',
To='Tolan:BAABNQAECn8ZAAIDAAgKvBqAQgBbAgADAAgKvBqAQgBbAgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAACNQAFFH8GAAIeAAIKpAiaJwBnAAAeAAIKpAiaJwBnAAA1AAQKfy8AAh4ACgpzHXcqALkCAB4ACgpzHXcqALkCAAAA.Toxcyurifeet:BAAANQAECgMIAwABNQAFFAMICgAQALkXAA==.Toxicai:BAABNQAECn8nAAIkAAgKghMbBwByAQAkAAgKghMbBwByAQAAAA==.',
Tr='Trakeus:BAABNQAECn8WAAMNAAgKDxYALQA8AgANAAgKDxYALQA8AgAGAAEKXwF/eQATAAAAAA==.Treespriest:BAAANQAECgcICwAAAA==.Treyman:BAABNQAECn8jAAIFAAkKFBTGZgBnAgAFAAkKFBTGZgBnAgAAAA==.Tribune:BAABNQAECn8pAAIEAAkKiyDxIACtAgAEAAkKiyDxIACtAgAAAA==.Trinitree:BAAANQAECgQIBQAAAA==.Trinkler:BAABNQAECn8UAAIBAAgKmxSe0gDhAQABAAgKmxSe0gDhAQAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAABNQAECn8hAAIRAAcKkBZVCwANAgARAAcKkBZVCwANAgAAAA==.',
Ty='Tychondris:BAABNQAECn8xAAIJAAoKkggyVAAIAQAJAAoKkggyVAAIAQAAAA==.Tyzonelfalas:BAABNQAECn8VAAIXAAgKlSEtAQCvAgAXAAgKlSEtAQCvAgAAAA==.',
Ul='Ulsoga:BAABNQAECn8qAAImAAkKUQ6DAQCkAQAmAAkKUQ6DAQCkAQAAAA==.',
Un='Unbórn:BAAANQAECgQIBQAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Valak:BAAANQAECgEIAgAAAA==.Valkyries:BAAANQAECggIBAAAAA==.Varibash:BAAANQADCggICAABNQAECgoKMQAKAJEYAA==.Vaspara:BAACNQAFFH8LAAIDAAMK+htjCAD+AAADAAMK+htjCAD+AAA1AAQKfx4AAgMACgrbG7YfAPECAAMACgrbG7YfAPECAAAA.',
Ve='Vergalis:BAAANQAECgEIAQAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQAECgQIBAAAAA==.',
Vo='Voidlìlíth:BAABNQAECn8oAAIBAAkKDxfuRAAyAQABAAkKDxfuRAAyAQAAAA==.Voidwak:BAABNQAECn8UAAIGAAcKhgKkIgCdAAAGAAcKhgKkIgCdAAAAAA==.Vorronni:BAABNQAECn8mAAMKAAkKkCHNFQDCAQAKAAkKkCHNFQDCAQAcAAEKFRsnIwBPAAAAAA==.',
Wa='Wardo:BAACNQAFFH8gAAMCAAcK2xnhAwA2AQACAAYKMRjhAwA2AQAhAAEKhiCzBQBfAAA1AAQKfz0ABAIACgpwJQYQAFIDAAIACQpVJQYQAFIDACEABwqbG5INACACACYAAQrUG0UwADUAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Warlok:BAAANQADCgEIAQAAAA==.Wastedraider:BAAANQAECgUICAAAAA==.Wastedtank:BAAANQAECgEIAgAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAABNQAECn8XAAIHAAcK1Q4/HAAGAQAHAAcK1Q4/HAAGAQAAAA==.',
Wh='Whitemist:BAAANQAECgYICwAAAA==.Whitepikmin:BAABNQAECn8mAAMXAAoKgx6UCQDbAgAXAAkKgx6UCQDbAgAYAAIK3RGnGwBJAAAAAA==.',
Wi='Wilmer:BAABNQAECn8mAAIJAAoKRBziJQD/AgAJAAoKRBziJQD/AgAAAA==.Wily:BAAANQADCggIDgAAAA==.Windowsvista:BAAANQAECgYIEwAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgcICQAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQAIADwXAA==.',
Wr='Wravc:BAAANQAECgQICQAAAQ==.',
Xa='Xaden:BAAANQAECggIAQAAAA==.Xaspen:BAAANQAECgcIEQAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICgAAAA==.Xoyan:BAAANQAECggIEAAAAA==.',
Ya='Yargonz:BAAANQAECgcIEgAAAA==.Yargz:BAABNQAECn8WAAIWAAgKKQzoLAB1AQAWAAgKKQzoLAB1AQABNQAFFAYIHwAEAD0IAA==.Yargzdk:BAACNQAFFH8fAAIEAAYKPQh8BwDaAAAEAAYKPQh8BwDaAAA1AAQKfyQAAgQACgoyEtlMAMMBAAQACgoyEtlMAMMBAAAA.',
Ye='Yeyol:BAABNQAECn8wAAIVAAkKZRmZHQCTAgAVAAkKZRmZHQCTAgAAAA==.',
Yo='Yolius:BAABNQAECn8VAAIcAAUK3RgUDQBkAQAcAAUK3RgUDQBkAQAAAA==.Yoogi:BAAANQAECgEIAQABNQAECggIFgAOAKQRAA==.Youngbullet:BAAANQAECgQIBAAAAA==.',
Yu='Yungnetero:BAAANQAECgQICQAAAA==.Yunikon:BAABNQAECn84AAQFAAoKtR7zIwA1AwAFAAoKtR7zIwA1AwADAAcKwg/NgACXAQAWAAcKoBRoKwCCAQABNQAECgoKHgAGAGQXAA==.',
Za='Zabala:BAAANQAECgEIAQABNQAECggIJAAFAGwZAA==.Zavorotnuk:BAAANQAECgEIAQAAAA==.',
Ze='Zell:BAAANQAECgYIDwABNQAECgcIFgADAIgkAA==.Zelluss:BAABNQAECn8WAAIDAAcKiCR7IgDiAgADAAcKiCR7IgDiAgAAAA==.Zelrin:BAAANQAECgEIAgAAAA==.Zeltari:BAAANQADCgQICAAAAA==.Zeothule:BAAANQAECggIAgAAAA==.Zephyrex:BAAANQAECgEIAwAAAA==.Zerkerpete:BAAANQAFFAEIAQAAAA==.',
Zh='Zhaphiria:BAACNQAFFH8IAAMfAAQKYRdzDABTAQAfAAQKYRdzDABTAQAjAAIKog6RCQCJAAA1AAQKfx0AAyMACgp9HfsDANkCACMACAqjHfsDANkCAB8ACgpxEY0FAIIBAAAA.Zhul:BAABNQAECn8fAAIJAAgKGxiCOQBHAQAJAAgKGxiCOQBHAQABNQAECgkJIAAFAKAeAA==.',
Zi='Zimmy:BAAANQADCgYIBgAAAA==.',
Zo='Zohzah:BAAANQAECgEIAQAAAA==.Zoomies:BAAANQAECgUICgAAAA==.Zorath:BAAANQAECgMIAgAAAA==.',
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
