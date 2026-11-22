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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Retribution','Druid-Balance','Evoker-Devastation','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Shaman-Enhancement','Mage-Frost','Paladin-Holy','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Druid-Guardian','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Monk-Windwalker','Monk-Brewmaster',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aadrisedh:BAAANQAECgQIAwAAAA==.Aaeryn:BAAANQAECgEIAQAAAA==.Aaliyshaa:BAABNQAECn8aAAMBAAoKaA5QawByAQABAAkKqgtQawByAQACAAIKMgoMMQE4AAAAAA==.Aaramis:BAABNQAECn86AAIBAAoKBRgOOAA5AgABAAoKBRgOOAA5AgAAAA==.',
Ab='Abrakadabruh:BAABNQAECn8jAAIDAAkK9xSLSgAvAgADAAkK9xSLSgAvAgAAAA==.Abyssal:BAABNQAECn8iAAQEAAoK4xr5IgCGAQAFAAcKuw4SRgCWAQAEAAgK3hn5IgCGAQAGAAUKnxNjIADDAAAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.Adannist:BAAANQADCgQIBAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.Aellwyn:BAAANQAECgMICwABNQAECgkJHAACAB4IAA==.',
Ah='Ahiru:BAAANQAECgMIAwAAAA==.',
Ai='Aidoffhealer:BAAANQADCgcICgAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQAECgIIAgAAAA==.Alystair:BAAANQADCgYIBgABNQAECgcICwAHAAAAAA==.',
Am='Amadayus:BAABNQAECn8oAAIIAAoKwyV0AgDfAwAIAAoKwyV0AgDfAwAAAA==.Ambellina:BAAANQAECgYICgAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anaye:BAAANQADCgIIAgABNQAECgkJJwAEAEUeAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8HAAMJAAcKxgpOHAAUAQAJAAUKvw1OHAAUAQAKAAIKUAYfCwBRAAA1AAQKf1IABAoACgoMHYoMAJcBAAkACQqvHGlXAFACAAoABwp+GYoMAJcBAAsAAQrJGRQ1AD0AAAAA.Archiball:BAAANQAECggICQABNQAECgkJHAACAB4IAA==.Arclock:BAABNQAECn8bAAIJAAkK2grHZwCfAQAJAAkK2grHZwCfAQAAAA==.Arconnai:BAABNQAECn9GAAIMAAoKxCCQPADVAgAMAAoKxCCQPADVAgAAAA==.Areilin:BAAANQAECgQIBgAAAA==.Areiotyrict:BAABNQAECn8nAAMNAAcKcATlIgCTAAANAAcKUQTlIgCTAAAOAAIKJgPEPgBGAAAAAA==.Argeras:BAAANQADCgQIBAAAAA==.Argeron:BAAANQADCgYIDAAAAA==.Arkaÿne:BAAANQADCgYIBgABNQAECgcIHAAPAE4OAA==.Arnøld:BAAANQAECgUICgABNQAECgYIDgAHAAAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.Artificial:BAAANQADCgEIAQAAAA==.',
As='Asham:BAAANQAECgEIAQAAAA==.Ashan:BAAANQAECggIBQAAAA==.Asiago:BAAANQAECgQIEAABNQAECgoKQgAQAM8gAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgcICwAAAA==.',
Av='Avvalethra:BAABNQAECn8bAAIIAAoK6g+QkQDmAQAIAAoK6g+QkQDmAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAcIIwARAPgcAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAABNQAECn80AAIDAAoKvgazjwCHAQADAAoKvgazjwCHAQAAAA==.Baineofagony:BAAANQADCgUIBQAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn9AAAICAAkKlhvfKQA4AgACAAkKlhvfKQA4AgAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECggIDgAAAA==.',
Be='Bearlinwall:BAAANQAECgMIBQAAAA==.Bearmaster:BAABNQAECn8cAAIIAAYK5QKbBgH5AAAIAAYK5QKbBgH5AAAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECgcIDAAAAA==.Bereaved:BAAANQADCgUIBQAAAA==.Bews:BAAANQADCgQIBAAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAABNQAECn8dAAIDAAkKURtmbwCfAgADAAkKURtmbwCfAgAAAA==.Bigtug:BAAANQAECgEIAgAAAA==.Billybones:BAABNQAECn8ZAAISAAUKhAlsbADtAAASAAUKhAlsbADtAAAAAA==.Bimbobaby:BAABNQAECn8eAAMTAAgKrhGxXgDFAQATAAgKrhGxXgDFAQAUAAEKAABgigAgAAABNQAECgEIAQAHAAAAAA==.',
Bl='Blackholes:BAABNQAECn8VAAIJAAUKxAgX5wD7AAAJAAUKxAgX5wD7AAAAAA==.Blackwÿn:BAAANQAECgEIAQABNQAECgcIHAAPAE4OAA==.Bladeblade:BAABNQAECn8fAAMGAAoK7B93BgA6AgAGAAoK7B93BgA6AgAFAAcKlBC0QgCsAQABNQAFFAUIDwAMAN8dAA==.Bladedozzer:BAAANQAECgcICQAAAA==.Blindinglite:BAABNQAECn85AAIFAAoKAh1WEwADAwAFAAoKAh1WEwADAwAAAA==.Bloodhaze:BAABNQAECn8eAAIFAAoKnCOwGADVAgAFAAoKnCOwGADVAgAAAA==.Blorp:BAAANQAECgYICwABNQAECgoKRgAIANEkAA==.Blueorange:BAAANQAECggIEAAAAA==.',
Bo='Bodizzle:BAAANQAECgIIAgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.Boriquagypsy:BAAANQADCgUIBQAAAA==.Bownystark:BAAANQAECgQIBAAAAA==.',
Br='Brchm:BAAANQAECgQIDQAAAA==.Brickly:BAABNQAECn8ZAAMFAAkKqB2uHgCkAgAFAAgKqB2uHgCkAgAGAAEKAAAELgBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgoKQgAQAM8gAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgUICQAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.',
Bx='Bxxberry:BAAANQAECgYICAAAAA==.',
By='Byeon:BAAANQAECgUICQAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgoKRwABAEsdAA==.',
['Bú']='Búkki:BAAANQADCgYIHgAAAA==.',
['Bü']='Bükkì:BAAANQADCggIGQAAAA==.Bükkï:BAAANQADCgcIEgAAAA==.',
Ca='Caboodles:BAABNQAECn8rAAMLAAgKNAdgNADyAAALAAYKugZgNADyAAAJAAgK6wWXywC6AAAAAA==.Cachamama:BAAANQAECgIIAgAAAA==.Camishami:BAACNQAFFH8JAAIBAAQK4BuvEgA2AQABAAQK4BuvEgA2AQA1AAQKfygAAwEACQqCGOsqAHsCAAEACQqCGOsqAHsCAAIAAgrLCvf6ADgAAAAA.Candyhandsjf:BAABNQAECn8nAAIEAAkKRR4KEABXAgAEAAkKRR4KEABXAgAAAA==.Candyhandz:BAAANQADCgYIEQABNQAECgkJJwAEAEUeAA==.Cannlol:BAAANQAECgIIAgAAAA==.Capriestsün:BAAANQAECgUICgABNQAECgoKNQAIAFYYAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgoKRwABAEsdAA==.Catharsis:BAAANQAECgQIBgAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn9AAAIEAAoKfB3lCgAuAwAEAAoKfB3lCgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQAECgQIBAAAAA==.Cheesus:BAABNQAECn9CAAIQAAoKzyBtEACpAgAQAAoKzyBtEACpAgAAAA==.Chicharon:BAABNQAECn8+AAIDAAoKgQ7DZwDlAQADAAoKgQ7DZwDlAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAABNQAECn8eAAIVAAoKeREQGACSAQAVAAoKeREQGACSAQAAAA==.Chlona:BAAANQABCgIIAgAAAA==.Chokolock:BAABNQAECn87AAIJAAoK5hUWPgAcAgAJAAoK5hUWPgAcAgAAAA==.Chunggus:BAAANQABCgYICQAAAA==.Churva:BAABNQAECn8jAAMBAAoKbweGoQAzAQABAAkKrgWGoQAzAQACAAYKVgZUvAAaAQAAAA==.',
Cl='Cleggane:BAAANQABCgcIBwAAAA==.',
Co='Coko:BAAANQAECgYICwABNQAECgoKQwAIAIUjAA==.Condemned:BAAANQADCgYIDAAAAA==.Cooch:BAAANQAECgYICAAAAA==.Cosecantes:BAABNQAECn8gAAMWAAYKjR3YDQDRAQAWAAYKjR3YDQDRAQADAAIKDQNBtAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgoKNQAIAFYYAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgcIDQAAAA==.Crackjönes:BAAANQADCgMIAwAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAABNQAECn8qAAIXAAkKcR7RJQCZAgAXAAkKcR7RJQCZAgAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crucify:BAAANQAECggIDgAAAA==.Crul:BAAANQABCgIIAQAAAA==.Crusäderaura:BAAANQAECgcIEwAAAA==.Cryptìc:BAACNQAFFH8KAAIUAAUKJRPgCgBFAQAUAAUKJRPgCgBFAQA1AAQKfygAAhQACgpyIK0QAO4CABQACgpyIK0QAO4CAAE1AAUUBggHABYApg0A.Crâckjones:BAAANQADCgUIBQAAAA==.',
Da='Dabbia:BAABNQAECn8dAAQKAAkKUhx9CgDQAQAKAAYKJR59CgDQAQAJAAQKfB5czQAvAQALAAQKMxeTMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Dahunte:BAAANQAECgYICQAAAA==.Damara:BAAANQADCggICgAAAA==.Damented:BAAANQADCggIEQABNQAECgoKRwABAEsdAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadcheck:BAAANQAECgEIAQAAAA==.Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECn8uAAMSAAkK/BRsLgAuAgASAAkK/BRsLgAuAgAYAAIKxwa2zABTAAABNQAECgoKOwAJAOYVAA==.Deathcabb:BAAANQAECgIIAwAAAA==.Deathtreader:BAAANQADCgYICAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAABNQAECn8XAAMIAAcKRwjHqwBbAQAIAAcKRwjHqwBbAQAZAAMKtgLKcgBrAAAAAA==.Delthrus:BAAANQAECgQIDwABNQAECgoKPAAOAOYRAA==.Demonarc:BAABNQAECn8lAAIEAAoKDxkSHAB1AgAEAAoKDxkSHAB1AgAAAA==.Detreset:BAABNQAECn8ZAAIaAAkKaRhLEQCWAgAaAAkKaRhLEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhann:BAABNQAECn8oAAMDAAoKhAz1bADYAQADAAoKhAz1bADYAQAbAAEKGQvjDQA0AAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgkJGgASAIQKAA==.Dinsum:BAAANQADCggIFgAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgoKSAAcAIYkAA==.Disorder:BAAANQAECgIIAwAAAA==.Dixeenormis:BAAANQAECgEIAQAAAA==.Dixonbuttsz:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgoKSAAcAIYkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgAHAAAAAA==.Doomscroll:BAAANQAECgEIAQAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQAECgMIAwAAAA==.Dragtiago:BAAANQADCgYIFQAAAA==.Drakarys:BAAANQADCggICgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8WAAIZAAgK2BfpIgA2AgAZAAgK2BfpIgA2AgAAAA==.Drezbi:BAAANQAECgQICQAAAA==.Droodmon:BAAANQADCgIIAgAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8vAAIPAAoKFQ4MmQDxAQAPAAoKFQ4MmQDxAQAAAA==.Durzaka:BAAANQAECgcIEwAAAA==.Durzu:BAAANQAECgQIDgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
['Dá']='Dáeves:BAAANQAECggIDgABNQAFFAYICwAUAOAXAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn9GAAMdAAoKTxK8KgA/AgAdAAoKIxG8KgA/AgAcAAoKVA1sTwDFAQAAAA==.',
Eg='Egholom:BAABNQAECn81AAIFAAoKURLWLQClAQAFAAoKURLWLQClAQAAAA==.',
Ek='Eks:BAAANQADCggIGwAAAA==.',
El='Electrcfrost:BAABNQAECn9VAAICAAoKWCP8BwA6AwACAAoKWCP8BwA6AwABNQAECgoKVgAQAMskAA==.Elkanàh:BAABNQAECn9GAAQPAAoKLyC/HgDmAgAPAAoKLyC/HgDmAgAXAAgKNRx5TQA0AgAeAAEKZwuVbQAnAAABNQAFFAgIEgATAGAUAA==.Elorene:BAABNQAECn8iAAMbAAgKfQjVAwCVAQAbAAgKTwjVAwCVAQADAAYK/wHChwG2AAAAAA==.Elunara:BAABNQAECn8ZAAIfAAgKZRhmGgDUAQAfAAgKZRhmGgDUAQABNQAFFAcIBwAJAMYKAA==.Elyysian:BAACNQAFFH8LAAIUAAYK4BeoCACCAQAUAAYK4BeoCACCAQA1AAQKf0sAAxQACgpxJKAEAI4DABQACgpxJKAEAI4DABMAAwqWA43lAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIBAAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQAECgMIAwABNQAECgcICwAHAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8MAAIDAAYK7hycGQCtAQADAAYK7hycGQCtAQA1AAQKfzQAAwMACgrFI34hALoCAAMACgrFI34hALoCABYAAQosF+c9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8wAAIBAAgKbRvKMgBSAgABAAgKbRvKMgBSAgABNQAECgoKQAAfAF4lAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgYICwABNQAECgoKQAAfAF4lAA==.',
Fa='Fadam:BAABNQAECn82AAIDAAoK8Q98ZQDqAQADAAoK8Q98ZQDqAQAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggIDwAAAA==.Fanttic:BAAANQADCgQIBAAAAA==.Fastrialimas:BAAANQAECgUIBQAAAA==.Fatigue:BAAANQAECgcICQAAAA==.Fatpo:BAABNQAECn8XAAQTAAgK2hxgagDfAQATAAcK3xtgagDfAQAUAAQKkR4GOwBQAQAgAAEKBSAwIgBUAAABNQAECgkJGQAFAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn82AAIDAAoKJB9fdgCRAgADAAoKJB9fdgCRAgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8cAAICAAcK7hUxBgCaAQACAAcK7hUxBgCaAQA1AAQKfzYAAgIACgrUIaUOAPgCAAIACgrUIaUOAPgCAAAA.Floriyana:BAAANQAECgMICQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAFFAkJCwADAJUKAA==.Fourpriest:BAAANQAECgUICgAAAA==.Foô:BAABNQAECn8+AAMdAAoKqSDXDgALAwAdAAoKqSDXDgALAwAcAAUKHBLNMgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAABNQAECn8fAAIDAAoKgwz8dQDDAQADAAoKgwz8dQDDAQAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAABNQAECn8cAAICAAkKHghdZgBUAQACAAkKHghdZgBUAQAAAA==.Furdinand:BAAANQADCgUICgAAAA==.Furyrosa:BAAANQADCggICgAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Fuzybritches:BAAANQADCgcICgABNQAECgUIEwAHAAAAAA==.',
Fy='Fyah:BAACNQAFFH8FAAIPAAIKcBG3JACJAAAPAAIKcBG3JACJAAA1AAQKfzgAAg8ACgpCHr8+AG4CAA8ACgpCHr8+AG4CAAE1AAUUBwgXAAgAaRYA.Fyaza:BAAANQADCggICQABNQAFFAcIFwAIAGkWAA==.',
Ga='Gaga:BAAANQADCgMIAgAAAA==.Gargamels:BAAANQAECggIEgABNQAECgkJHAACAB4IAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICwAAAA==.Gerttie:BAABNQAECn8oAAMhAAgKKBMNKwCXAQAhAAgKKBMNKwCXAQAQAAEKAAAlzwAOAAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8wAAIaAAkKthu8AQAsAwAaAAkKthu8AQAsAwA1AAQKfygAAhoACgr6H8ENAMsCABoACgr6H8ENAMsCAAAA.Gistlek:BAAANQAECggICAAAAA==.',
Gl='Gloryho:BAAANQABCgUIBgABNQAECgEIAQAHAAAAAA==.',
Go='Gobsquadp:BAABNQAECn8jAAITAAkKcg+dagCeAQATAAkKcg+dagCeAQABNQAECgoKQAAfAF4lAA==.Gonzzo:BAAANQAECgMIAQAAAA==.',
Gr='Grassmoker:BAAANQAECgUIDAAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJJwAiAFMeAA==.Grievex:BAABNQAECn89AAIPAAoKpgqinQCSAQAPAAoKpgqinQCSAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumnumnug:BAAANQADCggICgAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Gu='Guzzlr:BAAANQAECgYIEQAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAZAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Haring:BAABNQAECn8aAAIFAAkK4RVlHgAZAgAFAAkK4RVlHgAZAgAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAACNQAFFH8FAAITAAIKPhvJKgCPAAATAAIKPhvJKgCPAAA1AAQKf0kAAhMACgqyHekYABIDABMACgqyHekYABIDAAAA.Hedumnotner:BAAANQAECggICAAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAcIDgAPABMPAA==.Hemostasis:BAACNQAFFH8OAAIPAAcKEw+0BwDSAQAPAAcKEw+0BwDSAQA1AAQKf0kABA8ACgraI4sTABcDAA8ACgraI4sTABcDABcAAgrmD3AXAUYAAB4AAQodFi5tADcAAAAA.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQAHAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.',
Ho='Homeslice:BAABNQAECn8hAAQLAAgKIxRHDwDZAAAKAAQKuRVgFAAEAQALAAUKohRHDwDZAAAJAAUKZgrRCAG6AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECn9BAAIjAAoKcSHQAQDZAgAjAAoKcSHQAQDZAgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcIBwAAAA==.',
['Hó']='Hózaÿ:BAAANQADCgEIAQAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn9fAAMJAAoK4g4qUwDaAQAJAAoK4g4qUwDaAQALAAMKtAQIVACCAAAAAA==.',
Ib='Iblow:BAAANQADCgEIAQAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Il='Illydan:BAAANQADCgMIAwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQADCgUIBQAAAA==.',
Ir='Irrenadro:BAABNQAECn9MAAIPAAoKKBHskwD8AQAPAAoKKBHskwD8AQAAAA==.',
Is='Islandhunter:BAAANQABCgQIBAAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgYIDAAAAA==.',
Je='Jeage:BAAANQAECgQIBQABNQAECgkJIAACAJ4iAA==.Jera:BAAANQADCgIIAwAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgYICAABNQAECgkJGgAdABgZAA==.Jimmybones:BAAANQABCgIIAgAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn87AAIIAAoKAxpUTQA0AgAIAAoKAxpUTQA0AgAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kallivar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAoKKgAPAOYfAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAcIBwAJAMYKAA==.',
Ke='Keetra:BAACNQAFFH8dAAIIAAYKXxQ+CwA/AQAIAAYKXxQ+CwA/AQA1AAQKfysAAggACgoQIcUtAOQCAAgACgoQIcUtAOQCAAAA.Keiriline:BAABNQAECn8mAAMSAAcKYhDHTQB/AQASAAcKYhDHTQB/AQAkAAIKqAKL0AAtAAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQAECgUIBAAAAA==.Kitdrco:BAAANQAECgQICAAAAA==.',
Kl='Klix:BAAANQADCgcICwABNQAECgkJJwAEAEUeAA==.',
Kn='Knight:BAABNQAECn8bAAMDAAkKnB0RcgCaAgADAAgKnB0RcgCaAgAbAAIKzAjaCQBoAAAAAA==.Knugchurch:BAAANQAECgQIBAAAAA==.Knuggz:BAABNQAECn8vAAIMAAkKYxuLMgB0AgAMAAkKYxuLMgB0AgAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgMIAgAAAA==.Kumbustinhur:BAAANQAECgMIAwAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAQIEQATALAlAA==.Kylepala:BAAANQAECgYIBgABNQAFFAQIEQATALAlAA==.Kylepriest:BAACNQAFFH8RAAMTAAQKsCX2DgC3AQATAAQKsCX2DgC3AQAUAAMK9g31EACQAAA1AAQKf0gABBMACgqIJssBANADABMACgqIJssBANADABQACAplGggRAEkCACAAAgopI04XALwAAAAA.Kyntamun:BAAANQADCgcIDQABNQAECgUICQAHAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgkJJwAEAEUeAA==.Lambeáu:BAABNQAECn8kAAIIAAgKSx6GXAAPAgAIAAgKSx6GXAAPAgAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAABNQAECn8XAAQRAAgKsAreFQDYAAARAAcKOwbeFQDYAAAiAAMKXwSqHQB2AAAaAAUKbwW9RQB0AAAAAA==.Lamdabow:BAAANQAECggIEQABNQAECggIFwARALAKAA==.Lamdadk:BAAANQADCggICQAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgoKMAAFAMkeAA==.Larzoh:BAABNQAECn8wAAMFAAoKyR5JDABIAwAFAAoKyR5JDABIAwAEAAMKJQbEWQCdAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lethargy:BAAANQADCgYIDAAAAA==.Levapally:BAAANQAECgEIAQAAAA==.',
Li='Lidorila:BAAANQADCgcIEQAAAA==.Lightguard:BAABNQAECn8oAAIPAAgKchl0iwAPAgAPAAgKchl0iwAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8qAAIIAAoKCQXu1gBSAQAIAAoKCQXu1gBSAQAAAA==.Lilwiz:BAAANQAECgUIDQAAAA==.Linalala:BAABNQAECn/mAAQhAAkK8yaYAQAPBAAhAAkK8yaYAQAPBAAlAAcKqRHhFACtAQAQAAIKLAwbmQB1AAAAAA==.Linnxp:BAAANQAECgQIBgABNQAECgYIDAAHAAAAAA==.Linnxs:BAAANQAECgYIDAAAAA==.Linnxvx:BAAANQAECgIIAgABNQAECgYIDAAHAAAAAA==.Literacola:BAABNQAECn8uAAIDAAoKMBDDXQD9AQADAAoKMBDDXQD9AQAAAA==.',
Lo='Lorino:BAAANQAECgEIAQAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAABNQAECn8aAAMUAAoKuQ7dHgCXAQAUAAkKlwzdHgCXAQATAAUKOw/WmAAQAQAAAA==.Lugeyamnk:BAABNQAECn8cAAImAAkK2BC/HwCgAQAmAAkK2BC/HwCgAQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgUIBQAAAA==.Lustnbeiber:BAABNQAECn8sAAQCAAkKwhXRQgBqAgACAAkKwhXRQgBqAgABAAYK4AtbrgATAQAVAAUKWASwLACOAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgcIEgAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggIEAABNQAECgoKLQAeAD4jAA==.Lynchà:BAABNQAECn8tAAIeAAoKPiO8BwAmAwAeAAoKPiO8BwAmAwAAAA==.Lynchä:BAAANQAECgYIBgABNQAECgoKLQAeAD4jAA==.',
Ma='Maakun:BAABNQAECn8/AAITAAkKbhgdPgByAgATAAkKbhgdPgByAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Maddundead:BAAANQADCgIIAgAAAA==.Magawarrior:BAAANQADCgQIDQAAAA==.Magmalance:BAAANQAECgYIBwABNQAECgkJLQAYAD4gAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECn9EAAMBAAoKpyH1FgAaAwABAAoKpyH1FgAaAwACAAgKlRsmTACmAQAAAA==.Malchezaar:BAABNQAECn8rAAIJAAoKGxDRYQCwAQAJAAoKGxDRYQCwAQAAAA==.Malfrun:BAABNQAECn88AAIOAAoK5hEnEAC0AQAOAAoK5hEnEAC0AQAAAA==.Marinnite:BAAANQADCggIDgAAAA==.Markzugrberg:BAAANQADCgMIAwAAAA==.Marox:BAABNQAECn83AAIDAAoK+xrFPgBRAgADAAoK+xrFPgBRAgAAAA==.Marrøwgar:BAABNQAECn8tAAMYAAkKPiAyDgCZAgAYAAkKPiAyDgCZAgAkAAEKAABhxwA6AAAAAA==.Mathrim:BAECNQAFFH8SAAQJAAUKWiC9IACuAAAJAAMKtyO9IACuAAALAAEKoBl8DgBRAAAKAAEKAACqHgAAAAA1AAQKfzwAAwkACgo+JQAEALgDAAkACgo+JQAEALgDAAsAAgqOFRJUAIIAAAAA.Matooka:BAABNQAECn8cAAIIAAkK2QQG1gBUAQAIAAkK2QQG1gBUAQAAAA==.Maynji:BAAANQADCggICAAAAA==.Mazima:BAAANQAECggIEgAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAFFAIIBwAPAFISAA==.',
Me='Meyzer:BAAANQAECgUIBQAAAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Mikun:BAAANQAECgUIBgAAAA==.Mingosh:BAAANQADCgMIAwAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYIEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojix:BAAANQAECggICAAAAA==.Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAABNQAECn8UAAMYAAYKAhxHUQDOAQAYAAYKAhxHUQDOAQASAAUKhw3VcADcAAAAAA==.Mommÿ:BAACNQAFFH8QAAITAAQKuxhTGQAsAQATAAQKuxhTGQAsAQA1AAQKfz4AAxMACgrOHUQoAMkCABMACgrOHUQoAMkCACAABgpIDL4QAB0BAAAA.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8xAAIfAAoKgRFNFwD4AQAfAAoKgRFNFwD4AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgoKQwAIAIUjAA==.Moolificent:BAABNQAECn8aAAISAAkKhAq8UQBqAQASAAkKhAq8UQBqAQAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAABNQAECn8fAAIhAAoK0RvNFwCCAgAhAAoK0RvNFwCCAgAAAA==.',
Mu='Muat:BAAANQAECggIAgAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgoKUAAdAMYVAA==.Muddgore:BAAANQADCggIDgABNQAECgoKUAAdAMYVAA==.Muddthir:BAAANQADCgQIBAABNQAECgoKUAAdAMYVAA==.Murderino:BAAANQADCggICAAAAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgoKRgAIANEkAA==.Mustardrogue:BAAANQAECgUIBQAAAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn9QAAMdAAoKxhVlFwBuAQAcAAkK1w8VVQCxAQAdAAkK7RZlFwBuAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgQIBAAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECn9EAAIDAAoKkBFkWwADAgADAAoKkBFkWwADAgAAAA==.Nisia:BAABNQAECn8UAAMJAAkKDxgYOQCpAgAJAAkKDxgYOQCpAgALAAEKiwiSfAAwAAABNQAFFAUIDwAMAN8dAA==.Nito:BAABNQAECn8lAAISAAkKGBEMNAANAgASAAkKGBEMNAANAgAAAA==.',
No='Nobainer:BAAANQADCgQIAwABNQADCgUIBQAHAAAAAA==.Nohkano:BAACNQAFFH8IAAInAAMKCyVdAwBEAQAnAAMKCyVdAwBEAQA1AAQKf1wAAycACgqSJl8AAPEDACcACgqSJl8AAPEDACYABwriC9oqAEIBAAAA.Nokt:BAABNQAECn8VAAIJAAkKuhT7fQDrAQAJAAkKuhT7fQDrAQAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECggIDwAAAA==.Noveerra:BAAANQADCgcIDwABNQAECgUICQAHAAAAAA==.',
Nu='Numbuh:BAAANQAECgQIBwAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakdusa:BAAANQAECgEIAQAAAA==.Oakrogue:BAAANQAECgQICQAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ok='Okboomie:BAAANQABCgEIAQAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ornahua:BAAANQAECggIAwAAAA==.Ortillious:BAAANQAECgQICAABNQAECgcIEgAHAAAAAA==.',
Ov='Overclock:BAAANQAECgEIAQAAAA==.Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggIDwAAAA==.',
Pa='Painwhisper:BAAANQABCgQIBAAAAA==.Paladeez:BAAANQAECggIDgABNQAFFAcIDgAPABMPAA==.Palaweenie:BAAANQABCgQIBAAAAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcIDAAAAA==.Pantheons:BAAANQAECgQIEQAAAA==.Parsi:BAABNQAECn82AAMGAAkKxB5SBACcAgAGAAkKxB5SBACcAgAEAAIKmQduYQBnAAAAAA==.Pattysmyth:BAABNQAECn8XAAIOAAYKsApbKgCsAAAOAAYKsApbKgCsAAABNQADCggIEgAHAAAAAA==.Paulinemaroi:BAABNQAECn8XAAIDAAoKAx+xVgAPAgADAAoKAx+xVgAPAgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgoKFwADAAMfAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgkJJwAEAEUeAA==.Pennywhys:BAAANQADCgYIBgAAAA==.Peäches:BAAANQAECgMIAwAAAA==.',
Ph='Phaell:BAAANQADCgEIAQAAAA==.Philip:BAAANQAECggIEAAAAA==.Phäel:BAAANQABCgIIAgAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQAFAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDAAHAAAAAA==.Poppafury:BAAANQAECgEIAQAAAA==.Poppapulls:BAAANQAECggIEAAAAA==.Pottyy:BAAANQABCgIIBAAAAA==.Poubear:BAAANQAECggIEAABNQAECgkJHAACAB4IAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQAFAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcIBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgYICgABNQAECgoKJAAUAIUdAA==.',
['Pä']='Pändora:BAAANQAECgYICAAAAA==.',
Qu='Quigonjin:BAAANQADCgMIAwAAAA==.',
Ra='Rabite:BAABNQAECn9AAAIfAAoKXiVoBABkAwAfAAoKXiVoBABkAwAAAA==.Radiance:BAEANQAECgYIDgABNQAFFAcIDAAZALoeAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQAECgEIAQAAAA==.Ramshunter:BAAANQAECgQIBQAAAA==.Randyvivaldi:BAAANQAECggIDAAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rasnas:BAAANQADCgYIBgAAAA==.Rathasas:BAABNQAECn9SAAMaAAoKWR/RBgD2AgAaAAoKWR/RBgD2AgARAAIKaRjbMACPAAAAAA==.Ratnob:BAABNQAECn8hAAIYAAoK6hQyOQBAAgAYAAoK6hQyOQBAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMiAAkKUx62AwDqAgAiAAkKUx62AwDqAgARAAEKfwaTQAAqAAAAAA==.Relda:BAAANQAECgUICwABNQAECgkJGgAdABgZAA==.Remye:BAABNQAECn8tAAIXAAoKVhlsPgBqAgAXAAoKVhlsPgBqAgAAAA==.Rennshi:BAABNQAECn8dAAIFAAkK8CVWCAB2AwAFAAkK8CVWCAB2AwAAAA==.Reportedhunt:BAABNQAECn81AAIIAAoKVhhrQACpAgAIAAoKVhhrQACpAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgYIBgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimkitty:BAAANQAECgMIAwABNQAECgEIAQAHAAAAAA==.Rimmy:BAAANQAECgUICQABNQAECgEIAQAHAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8pAAMEAAYK6AboPQC1AAAEAAYK6AboPQC1AAAFAAIKfgRkiQBSAAAAAA==.Roldaza:BAAANQAECgUICgAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn9GAAMIAAoK0SRpFwA8AwAIAAoK0SRpFwA8AwAZAAYKTgy7SwAGAQAAAA==.',
Ru='Rulep:BAABNQAECn8aAAMSAAoKwQwQPQCpAQASAAoKwQwQPQCpAQAYAAEKAACY4wAwAAABNQAECgoKHwADAIMMAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Ryotwar:BAAANQAECgcIDAAAAA==.Rythmatic:BAABNQAECn9IAAMcAAoKhiRTDAATAwAcAAoKPiRTDAATAwAdAAcKoyEKIACBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sacrilege:BAAANQAECggIBAAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAABNQAECn8gAAITAAoKYhHAPwA7AgATAAoKYhHAPwA7AgABNQAECgEIAQAHAAAAAA==.Sakieri:BAABNQAECn8+AAMUAAoKZRoXGgB8AgAUAAoKZRoXGgB8AgATAAkKRREoTgAAAgAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQAECgQIAwAAAA==.Sangan:BAABNQAECn9KAAIDAAoKSB/1IQC4AgADAAoKSB/1IQC4AgAAAA==.Sangen:BAAANQABCgMIAwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwAHAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Sebaz:BAAANQAECgIIAQAAAA==.Secondcoming:BAAANQADCgYIBgAAAA==.Segolas:BAAANQADCgEIAQAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8jAAIRAAcK+ByzAADJAQARAAcK+ByzAADJAQA1AAQKfysAAhEACgpFJKAFADYDABEACgpFJKAFADYDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAABNQAECn8bAAMEAAkKyAXmLwAZAQAEAAkKmwXmLwAZAQAGAAMKqQQGLABCAAAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shambho:BAAANQAECgUIBAAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgYIBwAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Siatralle:BAABNQAECn8mAAMRAAkKYSMXAQBJAwARAAkKYSMXAQBJAwAaAAkKbh/GBAA+AwAAAA==.Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8vAAMJAAoKDSG1EwA+AwAJAAoK/SC1EwA+AwALAAMKgh3vTQCVAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8nAAIDAAkKJgqU/QCSAQADAAkKJgqU/QCSAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAiAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Solodruid:BAAANQABCgEIAQAAAA==.Soulezz:BAAANQAECgUJBwAAAA==.',
Sp='Spectrum:BAAANQADCgQIBwAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECn9DAAIIAAoKhSM5DQAlAwAIAAoKhSM5DQAlAwAAAA==.Stingerge:BAAANQAECggICAABNQAECgoKQwAIAIUjAA==.Stingerjb:BAAANQAECggIDgABNQAECgoKQwAIAIUjAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAABNQAECn8cAAIJAAoK/BYXVABZAgAJAAoK/BYXVABZAgAAAA==.Sucemabite:BAAANQADCgEIAQAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunalios:BAAANQAECgIIAwAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgkJFgAPAAAhAA==.',
Sy='Syl:BAAANQAECgUIDgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgoKLQAmAIIcAA==.Teemonk:BAABNQAECn8tAAImAAoKghykEwC7AgAmAAoKghykEwC7AgAAAA==.Teepal:BAAANQADCgUIBQABNQAECgoKLQAmAIIcAA==.Teila:BAAANQABCggIJgAAAA==.Teladrel:BAAANQAECggIAwAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAABNQAECn8zAAIVAAoK8BZeDABRAgAVAAoK8BZeDABRAgAAAA==.Teribullduce:BAACNQAFFH8LAAIIAAUKmhigBwB6AQAIAAUKmhigBwB6AQA1AAQKf0MAAggACgrYJIcLADADAAgACgrYJIcLADADAAAA.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thasaran:BAAANQAECgYICQAAAA==.Thickyricky:BAABNQAECn8aAAMdAAkKGBm0MgASAgAdAAkKOBO0MgASAgAcAAMKAR7UjAAAAQAAAA==.Thingol:BAAANQABCgYIFQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAkJMAAaALYbAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgUIEAABNQAFFAIIBwAPAFISAA==.Thuggerjr:BAACNQAFFH8HAAIPAAIKUhL1IQCUAAAPAAIKUhL1IQCUAAA1AAQKfzsAAg8ACgrmGQBQADwCAA8ACgrmGQBQADwCAAAA.Thundersurge:BAAANQAECgUICQABNQAECgoKNQAIAFYYAA==.Thænes:BAABNQAECn8cAAMPAAcKTg4G7ABEAQAPAAYKMg8G7ABEAQAeAAYK6QeUQQCiAAAAAA==.Thûr:BAAANQAECgQIBwABNQAECgoKRwABAEsdAA==.',
Ti='Tigg:BAABNQAECn8mAAICAAgKNARZ4wDQAAACAAgKNARZ4wDQAAAAAA==.Tildin:BAAANQADCggIEwAAAA==.Tinkerdinker:BAAANQAECgIIAwAAAA==.Tipsout:BAACNQAFFH8PAAMMAAUK3x1DFAARAQAMAAQK3x1DFAARAQAOAAEKAABRCgAAAAA1AAQKf0wAAwwACgqWJWsGAFsDAAwACgqWJWsGAFsDAA4ABwp7FRIiADoBAAAA.',
Tn='Tnemith:BAAANQABCgUIBQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgoKLQAmAIIcAA==.Torastrasza:BAAANQAFFAIIAgAAAA==.Totemm:BAABNQAECn8XAAIBAAkKBSBpMACgAgABAAkKBSBpMACgAgAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn9HAAMBAAoKSx2IJgCUAgABAAoKSx2IJgCUAgACAAUKQhGTsgAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgQIBQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAABNQAECn8XAAIXAAgK4xoKTADkAQAXAAgK4xoKTADkAQAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIBQAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Ul='Ulakyai:BAAANQADCgEIAQABNQAECgUICQAHAAAAAA==.',
Un='Unfocused:BAABNQAECn9WAAIQAAoKyyTNAwBUAwAQAAoKyyTNAwBUAwAAAA==.Unholybelac:BAAANQADCgYIDQAAAA==.',
Ur='Urgmathron:BAABNQAECn8uAAIeAAkKJhhvFwC+AQAeAAkKJhhvFwC+AQAAAA==.',
Va='Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAYICwAUAOAXAA==.Vansthir:BAAANQAECggIDgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIDgABNQAFFAYIEgAMAHsUAA==.Vaush:BAABNQAECn8ZAAMYAAcKSgPlmgDJAAAYAAYKogPlmgDJAAASAAcKGALNjgCEAAAAAA==.',
Ve='Veigär:BAAANQAECgEIAgAAAA==.Verasuchi:BAAANQAECgIIAQAAAA==.',
Vi='Victorix:BAAANQADCgUIBQAAAA==.Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8eAAIiAAYK2w1/EQAdAQAiAAYK2w1/EQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.Volcanoez:BAAANQAECgIIBAAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vr='Vrezor:BAAANQAECggIDAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.Vulgatee:BAAANQAECggICwAAAA==.Vulpala:BAABNQAECn8XAAIPAAkKDxNBZAAJAgAPAAkKDxNBZAAJAgAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgoKUgAQAEolAA==.',
Wa='Wardian:BAAANQAECgYIDAABNQAECgoKNwAPAAEXAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgoKNQAIAFYYAA==.Warthyr:BAAANQADCgIIAgAAAA==.',
We='Welfairline:BAAANQADCggIHgAAAA==.',
Wh='Whatasham:BAAANQAECgcICgABNQAFFAUICwAIAJoYAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMIBQAAAA==.Xarttoplek:BAAANQAECgQIBQABNQAECgoKQwAIAIUjAA==.',
Xs='Xsslopgob:BAAANQAECgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8jAAImAAoKfR1UDgD6AgAmAAoKfR1UDgD6AgAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8mAAIMAAoKqA/NngDPAQAMAAoKqA/NngDPAQAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCggIMQAAAA==.Zarik:BAABNQAECn8xAAIJAAoK0Qm9ZQClAQAJAAoK0Qm9ZQClAQAAAA==.',
Ze='Zeddoc:BAEANQAECgEIAgAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIAgAHAAAAAA==.Zenfist:BAAANQADCgUIBQAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAABNQAECn8vAAIPAAoKuRbnYAARAgAPAAoKuRbnYAARAgAAAA==.Zenotath:BAAANQABCgMIAgAAAA==.Zenveil:BAAANQAECggIEAAAAA==.',
Zo='Zodier:BAAANQAECggICgABNQAFFAYIDAAWAG8XAA==.Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYIEAAAAA==.',
Zu='Zugore:BAAANQADCgMIAwAAAA==.Zulugangrene:BAABNQAECn8sAAIPAAoKBA3EngCQAQAPAAoKBA3EngCQAQAAAA==.Zun:BAABNQAECn8dAAIWAAgKlAq+EgBhAQAWAAgKlAq+EgBhAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgcIHAAPAE4OAA==.',
['Çh']='Çhunchunmaru:BAAANQAECgIIAwABNQAECgoKQwAIAIUjAA==.',
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
