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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Retribution','Druid-Balance','Evoker-Devastation','Shaman-Elemental','DeathKnight-Frost','Shaman-Enhancement','Mage-Frost','Paladin-Holy','Paladin-Protection','Priest-Shadow','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Druid-Guardian','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Monk-Windwalker','Monk-Brewmaster',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aadrisedh:BAAANQAECgQIAwAAAA==.Aaeryn:BAAANQAECgEIAQAAAA==.Aaliyshaa:BAAANQAECgYIEQAAAA==.Aanorim:BAAANQAECgEIAQAAAA==.Aaramis:BAABNQAECn82AAIBAAoKExbWQQBZAgABAAoKExbWQQBZAgAAAA==.',
Ab='Abrakadabruh:BAABNQAECn8dAAICAAkKgxNmRAAbAgACAAkKgxNmRAAbAgAAAA==.Abyssal:BAABNQAECn8iAAQDAAoK4xpfGwCZAQADAAgK3hlfGwCZAQAEAAcKuw4SRgCWAQAFAAUKnxNjIADDAAAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.Adannist:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICgAAAA==.Aellwyn:BAAANQAECgQICQABNQAECggIEgAGAAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgcICgAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQAECgIIAwAAAA==.Alystair:BAAANQADCgYIBgABNQAECgYICAAGAAAAAA==.',
Am='Amadayus:BAABNQAECn8oAAIHAAoKwyV0AgDfAwAHAAoKwyV0AgDfAwAAAA==.Ambellina:BAAANQAECgYICQAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anaye:BAAANQADCgIIAgABNQAECgcIIAADACcfAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8HAAMIAAcKxgpOHAAUAQAIAAUKvw1OHAAUAQAJAAIKUAYfCwBRAAA1AAQKf1EABAkACgoMHWYJAHABAAgACQqvHGlXAFACAAkABwp+GWYJAHABAAoAAQrJGZguAD0AAAAA.Archiball:BAAANQAECggICQABNQAECggIEgAGAAAAAA==.Arclock:BAAANQAECgcIEgAAAA==.Arconnai:BAABNQAECn9EAAILAAoK3x9JLQBkAgALAAoK3x9JLQBkAgAAAA==.Areilin:BAAANQAECgQIBgAAAA==.Areiotyrict:BAABNQAECn8aAAMMAAUK8QOwIwBYAAAMAAUKqgOwIwBYAAANAAIKJgPEPgBGAAAAAA==.Arkaÿne:BAAANQADCgYIBgABNQAECgYIFAAOABEOAA==.Arnøld:BAAANQAECgcIDgAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.Artificial:BAAANQADCgEIAQAAAA==.',
As='Asham:BAAANQAECgEIAQAAAA==.Ashan:BAAANQAECgYIAwAAAA==.Ashinalani:BAAANQAECgEIAQAAAA==.Asiago:BAAANQAECgQIEAABNQAECgoKOQAPAP8eAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgYICAAAAA==.',
Av='Avvalethra:BAABNQAECn8bAAIHAAoK6g+QkQDmAQAHAAoK6g+QkQDmAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAcIHAAQACsZAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAABNQAECn8gAAICAAgKfQWRswATAQACAAgKfQWRswATAQAAAA==.Baineofagony:BAAANQADCgUIBQAAAA==.Balancedtech:BAAANQAECgEIAwAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn86AAIRAAkK9BkLMgDYAQARAAkK9BkLMgDYAQAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECggIDgAAAA==.',
Be='Bearlinwall:BAAANQAECgMIBQAAAA==.Bearmaster:BAABNQAECn8cAAIHAAYK5QKbBgH5AAAHAAYK5QKbBgH5AAAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECggIDAAAAA==.Bereaved:BAAANQADCgUIBQAAAA==.Bews:BAAANQADCgQIBAAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAABNQAECn8hAAICAAkKURtmbwCfAgACAAkKURtmbwCfAgAAAA==.Billybones:BAABNQAECn8ZAAISAAUKhAlsbADtAAASAAUKhAlsbADtAAAAAA==.Bimbobaby:BAAANQAECgQICgABNQADCgEIAQAGAAAAAA==.',
Bl='Blackholes:BAABNQAECn8VAAIIAAUKxAgX5wD7AAAIAAUKxAgX5wD7AAAAAA==.Blackwÿn:BAAANQADCggIFgABNQAECgYIFAAOABEOAA==.Bladeblade:BAABNQAECn8fAAMFAAoK7B8eBQBAAgAFAAoK7B8eBQBAAgAEAAcKlBC0QgCsAQABNQAFFAQICQALADcQAA==.Bladedozzer:BAAANQAECgQICQAAAA==.Blindinglite:BAABNQAECn83AAIEAAoKSBxWEwADAwAEAAoKSBxWEwADAwAAAA==.Bloodhaze:BAABNQAECn8dAAIEAAoKnCOwGADVAgAEAAoKnCOwGADVAgAAAA==.Bloodline:BAAANQAECggIBQAAAA==.Blorp:BAAANQAECgUICAABNQAECgoKRgAHANEkAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQAECgIIAgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.Boriquagypsy:BAAANQADCgUIBQAAAA==.Bownystark:BAAANQAECgQIBAAAAA==.',
Br='Brchm:BAAANQAECgQIDQAAAA==.Brickly:BAABNQAECn8ZAAMEAAkKqB2uHgCkAgAEAAgKqB2uHgCkAgAFAAEKAAAELgBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgoKOQAPAP8eAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgUICwAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.',
Bx='Bxxberry:BAAANQAECgYICAAAAA==.',
By='Byeon:BAAANQAECgUIBQAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgoKOwABAPocAA==.',
['Bú']='Búkki:BAAANQADCgYIHgAAAA==.',
['Bü']='Bükkì:BAAANQADCggIGQAAAA==.Bükkï:BAAANQADCgcIEgAAAA==.',
Ca='Caboodles:BAABNQAECn8pAAMKAAcKGwhgNADyAAAKAAYKugZgNADyAAAIAAcKkAZUuACvAAAAAA==.Cachamama:BAAANQAECgIIAgAAAA==.Camishami:BAACNQAFFH8JAAIBAAQK4Bv6DQA2AQABAAQK4Bv6DQA2AQA1AAQKfyQAAwEACQqCGFIgAIwCAAEACQqCGFIgAIwCABEAAgrLCjreADgAAAAA.Candyhandsjf:BAABNQAECn8gAAIDAAcKJx9QGgClAQADAAcKJx9QGgClAQAAAA==.Candyhandz:BAAANQAECgIIBAABNQAECgcIIAADACcfAA==.Cannlol:BAAANQADCgcICgAAAA==.Capriestsün:BAAANQAECgUICwABNQAECgoKMQAHAFYYAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgoKOwABAPocAA==.Catharsis:BAAANQAECgQIBgAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn8+AAIDAAoKfB3lCgAuAwADAAoKfB3lCgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQAECgQIBAAAAA==.Cheesus:BAABNQAECn85AAIPAAoK/x76FwAIAwAPAAoK/x76FwAIAwAAAA==.Chicharon:BAABNQAECn82AAICAAkKvA1ccQCdAQACAAkKvA1ccQCdAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAABNQAECn8eAAITAAoKeRGiEwCVAQATAAoKeRGiEwCVAQAAAA==.Chlona:BAAANQAECgEIAQAAAA==.Chokolock:BAABNQAECn8pAAIIAAoKZxTnOgD2AQAIAAoKZxTnOgD2AQAAAA==.Chunggus:BAAANQABCgYICQAAAA==.Churva:BAABNQAECn8jAAMBAAoKbweGoQAzAQABAAkKrgWGoQAzAQARAAYKVgZUvAAaAQAAAA==.',
Cl='Cleggane:BAAANQABCgcIBwAAAA==.',
Co='Coko:BAAANQAECgUIBQABNQAECgoKNwAHADgjAA==.Condemned:BAAANQADCgYIDAAAAA==.Cooch:BAAANQAECgYICwAAAA==.Cosecantes:BAABNQAECn8gAAMUAAYKjR3YDQDRAQAUAAYKjR3YDQDRAQACAAIKDQNBtAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgoKMQAHAFYYAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYICAAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAABNQAECn8pAAIVAAkKcR4hHACqAgAVAAkKcR4hHACqAgAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crucify:BAAANQAECggIDAAAAA==.Crul:BAAANQAECgEIAQAAAA==.Crusäderaura:BAABNQAECn8WAAQVAAgKayFvSQBCAgAVAAcKqyJvSQBCAgAOAAIKAADXqwExAAAWAAEKAADldwAlAAAAAA==.Cryptìc:BAACNQAFFH8KAAIXAAUKJRPgCgBFAQAXAAUKJRPgCgBFAQA1AAQKfygAAhcACgpyIK0QAO4CABcACgpyIK0QAO4CAAE1AAUUBggHABQApg0A.',
Da='Dabbia:BAABNQAECn8dAAQJAAkKUhx9CgDQAQAJAAYKJR59CgDQAQAIAAQKfB5czQAvAQAKAAQKMxeTMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Dahunte:BAAANQAECgYICQAAAA==.Damara:BAAANQADCggICgAAAA==.Damented:BAAANQAECgEIAQABNQAECgoKOwABAPocAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadcheck:BAAANQAECgEIAgAAAA==.Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECn8uAAMSAAkK/BRsLgAuAgASAAkK/BRsLgAuAgAYAAIKxwa2zABTAAABNQAECgoKKQAIAGcUAA==.Deathcabb:BAAANQABCgEIAQAAAA==.Deathtreader:BAAANQADCgYICAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAABNQAECn8XAAMHAAcKRwhwjQBTAQAHAAcKRwhwjQBTAQAZAAMKtgLKcgBrAAAAAA==.Delthrus:BAAANQAECgQICwABNQAECgoKOAANAKQRAA==.Demonarc:BAABNQAECn8jAAIDAAoK/xgSHAB1AgADAAoK/xgSHAB1AgAAAA==.Detreset:BAABNQAECn8ZAAIaAAkKaRhLEQCWAgAaAAkKaRhLEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECn8lAAMCAAoKhAzhWQDeAQACAAoKhAzhWQDeAQAbAAEKGQvpCQA5AAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgkJGgASAIQKAA==.Dinsum:BAAANQADCggIFAAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgoKRwAcAIYkAA==.Disorder:BAAANQAECgIIAwAAAA==.Dixeenormis:BAAANQAECgEIAQAAAA==.Dixonbuttsz:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgoKRwAcAIYkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgAGAAAAAA==.Doomscroll:BAAANQAECgEIAQAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQAECgMIBAAAAA==.Dragtiago:BAAANQADCgYIFQAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8WAAIZAAgK2BfpIgA2AgAZAAgK2BfpIgA2AgAAAA==.Drezbi:BAAANQAECgQICQAAAA==.Droodmon:BAAANQADCgIIAgAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8vAAIOAAoKFQ4MmQDxAQAOAAoKFQ4MmQDxAQAAAA==.Durzaka:BAABNQAECn8WAAIBAAcKwA8VZgBRAQABAAcKwA8VZgBRAQAAAA==.Durzu:BAAANQAECgQIDwAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
['Dá']='Dáeves:BAAANQAECggIDgABNQAFFAYICwAXAOAXAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn9GAAMdAAoKTxIDGgA/AQAcAAoKVA03PwC6AQAdAAoKIxEDGgA/AQAAAA==.',
Eg='Eggy:BAAANQAECggIBgAAAA==.Egholom:BAABNQAECn81AAIEAAoKURKEJACqAQAEAAoKURKEJACqAQAAAA==.',
Ek='Eks:BAAANQADCggIFAAAAA==.',
El='Electrcfrost:BAABNQAECn9CAAIRAAoKrCCKDQDqAgARAAoKrCCKDQDqAgABNQAECgoKQwAPAGMgAA==.Elkanàh:BAABNQAECn83AAMVAAoKsxx5TQA0AgAVAAgKNRx5TQA0AgAOAAoKKxqDQQAzAgABNQAFFAcIEAAeAOoTAA==.Elorene:BAABNQAECn8dAAMbAAgK0QfVAwCVAQAbAAgKowfVAwCVAQACAAYK/wHChwG2AAAAAA==.Elunara:BAABNQAECn8ZAAIfAAgKZRhmGgDUAQAfAAgKZRhmGgDUAQABNQAFFAcIBwAIAMYKAA==.Elyysian:BAACNQAFFH8LAAIXAAYK4BeoCACCAQAXAAYK4BeoCACCAQA1AAQKf0MAAxcACgpMJKAEAI4DABcACgpMJKAEAI4DAB4AAwqWA43lAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIBAAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgYICAAGAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8MAAICAAYK7hycGQCtAQACAAYK7hycGQCtAQA1AAQKfyUAAwIACgqrI5E6ABIDAAIACgqrI5E6ABIDABQAAQosF+c9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8hAAIBAAcK7RrWSQC5AQABAAcK7RrWSQC5AQABNQAECgoKOAAfAF4lAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgUIBQABNQAECgoKOAAfAF4lAA==.',
Fa='Fadam:BAABNQAECn8yAAICAAoKxQ8TVgDoAQACAAoKxQ8TVgDoAQAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggIDgAAAA==.Fanttic:BAAANQADCgQIBAAAAA==.Fastrialimas:BAAANQAECgEIAQAAAA==.Fatigue:BAAANQAECgEIAQAAAA==.Fatpo:BAABNQAECn8XAAQeAAgK2hxgagDfAQAeAAcK3xtgagDfAQAXAAQKkR4GOwBQAQAgAAEKBSAwIgBUAAABNQAECgkJGQAEAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn82AAICAAoKJB9pTQAAAgACAAoKJB9pTQAAAgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8WAAIRAAYKcBbBBgBGAQARAAYKcBbBBgBGAQA1AAQKfywAAhEACgqGIF8QAM0CABEACgqGIF8QAM0CAAAA.Floriyana:BAAANQAECgMIDAAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgoKTAACAJ8hAA==.Fourpriest:BAAANQAECgUICgAAAA==.Foô:BAABNQAECn82AAMdAAoKPCDXDgALAwAdAAoKPCDXDgALAwAcAAUKHBLNMgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgYICgAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQAECggIEgAAAA==.Furdinand:BAAANQADCgUICgAAAA==.Furyrosa:BAAANQADCggICgAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAAGAAAAAA==.Fuzybritches:BAAANQAECgEIAQABNQAECgYIDgAGAAAAAA==.',
Fy='Fyah:BAABNQAECn80AAIOAAoKrR0rMgBuAgAOAAoKrR0rMgBuAgABNQAFFAcIFwAHAGkWAA==.Fyaza:BAAANQADCggICQABNQAFFAcIFwAHAGkWAA==.',
Ga='Gaga:BAAANQAECgEIAQAAAA==.Gargamels:BAAANQAECggIDwABNQAECggIEgAGAAAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICwAAAA==.Gerttie:BAABNQAECn8oAAMhAAgKKBNmIQCdAQAhAAgKKBNmIQCdAQAPAAEKAAAlzwAOAAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8mAAIaAAgKzhp8AgCfAgAaAAgKzhp8AgCfAgA1AAQKfyYAAhoACgr6H8ENAMsCABoACgr6H8ENAMsCAAAA.Gistlek:BAAANQAECggICAAAAA==.',
Gl='Gloryho:BAAANQAECgEIAQABNQADCgEIAQAGAAAAAA==.',
Go='Gobsquadp:BAABNQAECn8cAAIeAAkKcg9yXwCHAQAeAAkKcg9yXwCHAQABNQAECgoKOAAfAF4lAA==.',
Gr='Grassmoker:BAAANQAECgUIDQAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJJwAiAFMeAA==.Grievex:BAABNQAECn89AAIOAAoKpgoEgQCKAQAOAAoKpgoEgQCKAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Gu='Guzzlr:BAAANQAECgYIEQAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAZAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Haring:BAAANQAECggIEgAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAACNQAFFH8FAAIeAAIKPhvgIgCVAAAeAAIKPhvgIgCVAAA1AAQKf0MAAh4ACgqwHaUVAP4CAB4ACgqwHaUVAP4CAAAA.Hedumnotner:BAAANQAECggICAAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAYIDQAOACkOAA==.Hemostasis:BAACNQAFFH8NAAIOAAYKKQ60BwDSAQAOAAYKKQ60BwDSAQA1AAQKf0gABA4ACgraI30NACUDAA4ACgraI30NACUDABUAAgrmD3AXAUYAABYAAQodFi5tADcAAAAA.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQAGAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.',
Ho='Homeslice:BAABNQAECn8hAAQKAAgKIxSLCwDgAAAJAAQKuRVgFAAEAQAKAAUKohSLCwDgAAAIAAUKZgrRCAG6AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECn89AAIjAAoKrCCFAQDcAgAjAAoKrCCFAQDcAgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcJBwAAAA==.',
['Hó']='Hózaÿ:BAAANQADCgEIAQAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn9TAAMIAAoKBg41RgDNAQAIAAoKBg41RgDNAQAKAAMKtAQIVACCAAAAAA==.',
Ib='Iblow:BAAANQADCgEIAQAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Il='Illydan:BAAANQADCgMIAwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQAECgEIAQAAAA==.',
Ir='Irrenadro:BAABNQAECn9IAAIOAAoKJBDskwD8AQAOAAoKJBDskwD8AQAAAA==.',
Is='Islandhunter:BAAANQAECgEIAgAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgYIDAAAAA==.',
Je='Jeage:BAAANQAECgQIBQABNQAECgkJIAARAJ4iAA==.Jera:BAAANQADCgIIAwAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgYICwABNQAECgkJGQAdANYXAA==.Jimmybones:BAAANQABCgIIAgAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn8yAAIHAAkK8xi9WQDSAQAHAAkK8xi9WQDSAQAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.Juicyreds:BAAANQAECgEIAQAAAA==.Juzze:BAAANQAECgEIAQAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kallivar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAoKKgAOAOYfAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAcIBwAIAMYKAA==.',
Ke='Keetra:BAACNQAFFH8dAAIHAAYKXxRkBwBHAQAHAAYKXxRkBwBHAQA1AAQKfysAAgcACgoQIfMkAIECAAcACgoQIfMkAIECAAAA.Keiriline:BAABNQAECn8lAAMSAAcKVRDHTQB/AQASAAcKVRDHTQB/AQAkAAIKqAKL0AAtAAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQAECgUIBQAAAA==.',
Kl='Klix:BAAANQADCgcICwABNQAECgcIIAADACcfAA==.',
Kn='Knight:BAABNQAECn8bAAMCAAkKnB0RcgCaAgACAAgKnB0RcgCaAgAbAAIKzAjaCQBoAAAAAA==.Knuggz:BAABNQAECn8bAAILAAcKrxr+WAC8AQALAAcKrxr+WAC8AQAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.',
Kr='Kragtharr:BAAANQAECggIAQAAAA==.Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgMIAgAAAA==.Kumbustinher:BAAANQAECgMIAwAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAMIDwAeAKYmAA==.Kylepala:BAAANQAECgYIBgABNQAFFAMIDwAeAKYmAA==.Kylepriest:BAACNQAFFH8PAAMeAAMKpiYrEQBXAQAeAAMKpiYrEQBXAQAXAAMK9g0hDQCVAAA1AAQKf0QABB4ACgqIJssBANADAB4ACgqIJssBANADABcABwqNF1kVAM0BACAAAgopI04XALwAAAAA.Kyntamun:BAAANQADCgcIDQABNQAECgUIBQAGAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgcIIAADACcfAA==.Lambeáu:BAABNQAECn8iAAIHAAgKoxy8TgDyAQAHAAgKoxy8TgDyAQAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAABNQAECn8XAAQQAAgKsAq8EgDbAAAQAAcKOwa8EgDbAAAiAAMKXwSqHQB2AAAaAAUKbwW9RQB0AAAAAA==.Lamdabow:BAAANQAECgcIDAABNQAECggIFwAQALAKAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQAECgEIAQAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgoKMAAEAMkeAA==.Larzoh:BAABNQAECn8wAAMEAAoKyR5JDABIAwAEAAoKyR5JDABIAwADAAMKJQbEWQCdAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgIIAQAAAA==.',
Le='Lethargy:BAAANQADCgYIDAAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgUIEQAAAA==.Lightguard:BAABNQAECn8oAAIOAAgKchl0iwAPAgAOAAgKchl0iwAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8jAAIHAAgKkgTu1gBSAQAHAAgKkgTu1gBSAQAAAA==.Lilwiz:BAAANQAECgUIEAAAAA==.Linalala:BAABNQAECn/NAAQhAAkK7yY2AQAKBAAhAAkK7yY2AQAKBAAlAAcKqRHhFACtAQAPAAIKLAwbmQB1AAAAAA==.Linnxp:BAAANQAECgMIBgABNQAECgYICwAGAAAAAA==.Linnxs:BAAANQAECgYICwAAAA==.Linnxvx:BAAANQAECgIIBQABNQAECgYICwAGAAAAAA==.Literacola:BAABNQAECn8mAAICAAoKyQ31WgDaAQACAAoKyQ31WgDaAQAAAA==.',
Lo='Lorino:BAAANQAECgEIAQAAAA==.Lothaire:BAAANQAECgEIAQAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAABNQAECn8WAAMXAAoKuQ5LGQCYAQAXAAkKlwxLGQCYAQAeAAQKhws6mwDUAAAAAA==.Lugeyamnk:BAABNQAECn8WAAImAAkKywuWIABfAQAmAAkKywuWIABfAQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgUICgAAAA==.Lustnbeiber:BAABNQAECn8sAAQRAAkKwhXRQgBqAgARAAkKwhXRQgBqAgABAAYK4AtbrgATAQATAAUKWASMJgCPAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgcIEgAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggIEAABNQAECgkJKwAWAB4hAA==.Lynchà:BAABNQAECn8rAAIWAAkKHiG8BwAmAwAWAAkKHiG8BwAmAwAAAA==.Lynchä:BAAANQAECgYIBgABNQAECgkJKwAWAB4hAA==.',
Ma='Maakun:BAABNQAECn87AAIeAAkKbhgdPgByAgAeAAkKbhgdPgByAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIDQAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECn8/AAMBAAoKECH1FgAaAwABAAoKECH1FgAaAwARAAgKlRujOgCwAQAAAA==.Malchezaar:BAABNQAECn8fAAIIAAgKMg6EfwAqAQAIAAgKMg6EfwAqAQAAAA==.Malfrun:BAABNQAECn84AAINAAoKpBEfDQCtAQANAAoKpBEfDQCtAQAAAA==.Marinnite:BAAANQADCggIDgAAAA==.Markzugrberg:BAAANQADCgMIAwAAAA==.Marox:BAABNQAECn83AAICAAoK+xqUMABfAgACAAoK+xqUMABfAgAAAA==.Marrøwgar:BAABNQAECn8hAAMYAAkKuhwdFAAnAgAYAAkKuhwdFAAnAgAkAAEKAABhxwA6AAAAAA==.Mathrim:BAECNQAFFH8SAAQIAAUKWiAiGAC3AAAIAAMKtyMiGAC3AAAKAAEKoBmxCwBTAAAJAAEKAAAWFQAAAAA1AAQKfzsAAwgACgo+JQAEALgDAAgACgo+JQAEALgDAAoAAgqOFRJUAIIAAAAA.Matooka:BAABNQAECn8cAAIHAAkK2QQG1gBUAQAHAAkK2QQG1gBUAQAAAA==.Maynji:BAAANQADCggICAAAAA==.Mazima:BAAANQAECgcIEQAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAECgoKMgAOADQYAA==.',
Me='Meyzer:BAAANQAECgUIBQAAAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Mikun:BAAANQAECgMIBQAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQAECgEIAQAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojix:BAAANQAECggICQAAAA==.Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAABNQAECn8UAAMYAAYKAhxHUQDOAQAYAAYKAhxHUQDOAQASAAUKhw3VcADcAAAAAA==.Mommÿ:BAACNQAFFH8MAAIeAAMKPxZaGgDgAAAeAAMKPxZaGgDgAAA1AAQKfz4AAx4ACgrOHUQoAMkCAB4ACgrOHUQoAMkCACAABgpIDL4QAB0BAAAA.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8xAAIfAAoKgRFNFwD4AQAfAAoKgRFNFwD4AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgoKNwAHADgjAA==.Moolificent:BAABNQAECn8aAAISAAkKhAq8UQBqAQASAAkKhAq8UQBqAQAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAABNQAECn8fAAIhAAoK0RvNFwCCAgAhAAoK0RvNFwCCAgAAAA==.',
Mu='Muat:BAAANQAECggIAQAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgoKPQAdAJEVAA==.Muddgore:BAAANQADCggIDgABNQAECgoKPQAdAJEVAA==.Muddthir:BAAANQADCgQIBAABNQAECgoKPQAdAJEVAA==.Murderino:BAAANQADCggICAAAAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgoKRgAHANEkAA==.Mustardrogue:BAAANQAECgUIBQAAAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn89AAMdAAoKkRV8FABxAQAdAAkK7RZ8FABxAQAcAAcK+xCpZgAjAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgIIAwAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.Nezoomi:BAAANQAECgEIAQAAAA==.',
Ni='Nirath:BAABNQAECn88AAICAAoK+w/3VgDmAQACAAoK+w/3VgDmAQAAAA==.Nisia:BAABNQAECn8UAAMIAAkKDxgYOQCpAgAIAAkKDxgYOQCpAgAKAAEKiwiSfAAwAAABNQAFFAQICQALADcQAA==.Nito:BAABNQAECn8lAAISAAkKGBEMNAANAgASAAkKGBEMNAANAgAAAA==.',
No='Nobainer:BAAANQADCgQIAwABNQADCgUIBQAGAAAAAA==.Nohkano:BAACNQAFFH8HAAInAAMK/iQQAgBMAQAnAAMK/iQQAgBMAQA1AAQKf0oAAycACgpmJl8AAPEDACcACgpmJl8AAPEDACYABwriC84jAEQBAAAA.Nokt:BAAANQAECggIEAAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECggIDwAAAA==.Noveerra:BAAANQADCgcIDwABNQAECgUIBQAGAAAAAA==.',
Nu='Numbuh:BAAANQAECgQIBwAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakremi:BAAANQAECgEIAQAAAA==.Oakrogue:BAAANQAECgIIBQAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ok='Okboomie:BAAANQABCgEIAQAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ornahua:BAAANQAECggIAwAAAA==.Ortillious:BAAANQAECgQICAABNQAECgcIEgAGAAAAAA==.',
Ov='Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggIDgAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECggIEAABNQAFFAYIDQAOACkOAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcIDAAAAA==.Pantheons:BAAANQAECgQIEQAAAA==.Parsi:BAABNQAECn8qAAMFAAkKbx25BABUAgAFAAkKbx25BABUAgADAAIKmQduYQBnAAAAAA==.Pattysmyth:BAABNQAECn8VAAINAAYKlQk7IwCsAAANAAYKlQk7IwCsAAABNQADCggIEgAGAAAAAA==.Paulinemaroi:BAABNQAECn8XAAICAAoKAx+uQwAeAgACAAoKAx+uQwAeAgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgoKFwACAAMfAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgcIIAADACcfAA==.Pennywhys:BAAANQADCgYIBgAAAA==.Peäches:BAAANQAECgMIAwAAAA==.',
Ph='Phaell:BAAANQAECgEIAQAAAA==.Philip:BAAANQAECggIEgAAAA==.Phäel:BAAANQAECgEIAQAAAA==.Phäell:BAAANQAECgEIAgAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQAEAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDAAGAAAAAA==.Poppafury:BAAANQAECgEIAQAAAA==.Poppapulls:BAAANQAECggIDwAAAA==.Pottyy:BAAANQABCgIIBAAAAA==.Poubear:BAAANQAECggICwABNQAECggIEgAGAAAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQAEAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcIBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgYICgABNQAECgoKJAAXAIUdAA==.',
['Pä']='Pändora:BAAANQAECgYICQAAAA==.',
Ra='Rabite:BAABNQAECn84AAIfAAoKXiVoBABkAwAfAAoKXiVoBABkAwAAAA==.Radiance:BAEANQAECgcIDAABNQAFFAYICwAZAJkeAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECggIDQAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rathasas:BAABNQAECn9CAAMaAAkK8h36DwCpAgAaAAkK8h36DwCpAgAQAAIKaRjbMACPAAAAAA==.Ratnob:BAABNQAECn8hAAIYAAoK6hQyOQBAAgAYAAoK6hQyOQBAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMiAAkKUx62AwDqAgAiAAkKUx62AwDqAgAQAAEKfwaTQAAqAAAAAA==.Relda:BAAANQAECgUIDwABNQAECgkJGQAdANYXAA==.Remye:BAABNQAECn8tAAIVAAoKVhlsPgBqAgAVAAoKVhlsPgBqAgAAAA==.Rennshi:BAABNQAECn8dAAIEAAkK8CVWCAB2AwAEAAkK8CVWCAB2AwAAAA==.Reportedhunt:BAABNQAECn8xAAIHAAoKVhhrQACpAgAHAAoKVhhrQACpAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgYIBgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimmy:BAAANQAECgEIAQABNQADCgEIAQAGAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8mAAMDAAYK6AZHNgC3AAADAAYK6AZHNgC3AAAEAAIKfgRkiQBSAAAAAA==.Roldaza:BAAANQAECgUICgAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn9GAAMHAAoK0SRpFwA8AwAHAAoK0SRpFwA8AwAZAAYKTgy7SwAGAQAAAA==.',
Ru='Rulep:BAAANQAECggIBwAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Ryotwar:BAAANQAECgcIDAAAAA==.Rythmatic:BAABNQAECn9HAAMcAAoKhiTwCQASAwAcAAoKPiTwCQASAwAdAAcKoyEKIACBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQAECgcICwABNQADCgEIAQAGAAAAAA==.Sakieri:BAABNQAECn82AAMXAAoKcRgXGgB8AgAXAAoKcRgXGgB8AgAeAAkKrg65RADtAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQAECgEIAgAAAA==.Sangan:BAABNQAECn9AAAICAAoKfB3nJgCHAgACAAoKfB3nJgCHAgAAAA==.Sangen:BAAANQABCgMIAwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwAGAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Secondcoming:BAAANQADCgYIBgAAAA==.Segolas:BAAANQADCgEIAQAAAA==.Selaris:BAAANQAECgEIAQAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8cAAIQAAcKKxnmAABrAQAQAAcKKxnmAABrAQA1AAQKfykAAhAACgpFJKAFADYDABAACgpFJKAFADYDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAABNQAECn8XAAMDAAcKuwQwNQC9AAADAAcKfAQwNQC9AAAFAAMKqQTMJQBDAAAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shaming:BAAANQAECgEIAQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgYIBwAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8uAAMIAAoKDSG1EwA+AwAIAAoK/SC1EwA+AwAKAAMKgh16IABgAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8nAAICAAkKJgqU/QCSAQACAAkKJgqU/QCSAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAiAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Solodruid:BAAANQAECgEIAgAAAA==.Soulezz:BAAANQAECgUJBwAAAA==.',
Sp='Spectrum:BAAANQADCgQIBAAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECn83AAIHAAoKOCNCCgAkAwAHAAoKOCNCCgAkAwAAAA==.Stingerge:BAAANQAECgEIAQABNQAECgoKNwAHADgjAA==.Stingerjb:BAAANQAECggIDgABNQAECgoKNwAHADgjAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAABNQAECn8cAAIIAAoK/BYXVABZAgAIAAoK/BYXVABZAgAAAA==.Sucemabite:BAAANQADCgEIAQAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgkJFgAOAAAhAA==.',
Sy='Syl:BAAANQAECgUIDgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgoKLQAmAIIcAA==.Teemonk:BAABNQAECn8tAAImAAoKghykEwC7AgAmAAoKghykEwC7AgAAAA==.Teepal:BAAANQADCgUIBQABNQAECgoKLQAmAIIcAA==.Teila:BAAANQABCggIJgAAAA==.Teladrel:BAAANQAECggIBAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAABNQAECn8kAAITAAgKpRSNEwCWAQATAAgKpRSNEwCWAQAAAA==.Teribullduce:BAACNQAFFH8HAAIHAAQKCxrmCgAUAQAHAAQKCxrmCgAUAQA1AAQKfzkAAgcACgqXJNILABYDAAcACgqXJNILABYDAAAA.Terscheckii:BAAANQAECgEIAQAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thasaran:BAAANQADCggICAAAAA==.Thickyricky:BAABNQAECn8ZAAMdAAkK1he0MgASAgAdAAkKOBO0MgASAgAcAAMKqBrheADkAAAAAA==.Thingol:BAAANQABCgYIFQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAgIJgAaAM4aAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgQIDAABNQAECgoKMgAOADQYAA==.Thuggerjr:BAABNQAECn8yAAIOAAoKNBiqRwAfAgAOAAoKNBiqRwAfAgAAAA==.Thundersurge:BAAANQAECgUICQABNQAECgoKMQAHAFYYAA==.Thænes:BAABNQAECn8UAAMOAAYKEQ4G7ABEAQAOAAYKEQ4G7ABEAQAWAAQKawaxTQBPAAAAAA==.Thûr:BAAANQAECgQIBgABNQAECgoKOwABAPocAA==.',
Ti='Tigg:BAABNQAECn8mAAIRAAgKNARZ4wDQAAARAAgKNARZ4wDQAAAAAA==.Tildin:BAAANQADCggIEwAAAA==.Tinkerdinker:BAAANQAECgIIAwAAAA==.Tipsout:BAACNQAFFH8JAAMLAAQKNxCQFgDRAAALAAMKNxCQFgDRAAANAAEKAACGCAAAAAA1AAQKf0gAAwsACgqWJScEAGgDAAsACgqWJScEAGgDAA0ABwp7FRIiADoBAAAA.',
Tn='Tnemith:BAAANQABCgUIBQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgoKLQAmAIIcAA==.Torastrasza:BAAANQAFFAIIAgAAAA==.Totemm:BAABNQAECn8VAAIBAAkKGh9pMACgAgABAAkKGh9pMACgAgAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn87AAMBAAoK+hyxKQBSAgABAAoK+hyxKQBSAgARAAUKQhGTsgAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgQIBQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAABNQAECn8XAAIVAAgK4xp4OwD2AQAVAAgK4xp4OwD2AQAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIBQAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Un='Unfocused:BAABNQAECn9DAAIPAAoKYyAZEQB4AgAPAAoKYyAZEQB4AgAAAA==.Unholybelac:BAAANQADCgYIDQAAAA==.',
Ur='Urgmathron:BAABNQAECn8jAAIWAAcKixnjJAC5AQAWAAcKixnjJAC5AQAAAA==.',
Va='Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAYICwAXAOAXAA==.Vansthir:BAAANQAECggIDgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIEAABNQAFFAYIEgALAHsUAA==.Vaush:BAABNQAECn8ZAAMYAAcKSgPlmgDJAAAYAAYKogPlmgDJAAASAAcKGAK1egCFAAAAAA==.',
Ve='Veigär:BAAANQAECgEIAgAAAA==.Verasuchi:BAAANQAECgIIAQAAAA==.',
Vi='Victorix:BAAANQADCgUIBQAAAA==.Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8eAAIiAAYK2w1/EQAdAQAiAAYK2w1/EQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAAGAAAAAA==.Volcanoez:BAAANQAECgIIBAAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vr='Vrezor:BAAANQAECggIDAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.Vulpala:BAAANQAECgYIDAAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgoKSQAPAOEkAA==.',
Wa='Wardian:BAAANQAECgYICwABNQAECgoKLwAOAJMTAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgoKMQAHAFYYAA==.Warnath:BAAANQAECgUIBQAAAA==.Warthyr:BAAANQADCgIIAgAAAA==.',
We='Welfairline:BAAANQADCggIHgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAFFAQIBwAHAAsaAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.Xarttoplek:BAAANQAECgMIAwABNQAECgoKNwAHADgjAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8hAAImAAoKfR1UDgD6AgAmAAoKfR1UDgD6AgAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8kAAILAAkKtg7NngDPAQALAAkKtg7NngDPAQAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgYIKAAAAA==.Zarik:BAABNQAECn8iAAIIAAgKfAkDdgBAAQAIAAgKfAkDdgBAAQAAAA==.',
Ze='Zeddoc:BAEANQAECgEIAwAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIAwAGAAAAAA==.Zenfist:BAAANQADCgUIBQAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAABNQAECn8iAAIOAAoKWw19rAA2AQAOAAoKWw19rAA2AQAAAA==.Zenotath:BAAANQABCgMIAgAAAA==.Zenveil:BAAANQAECgQIBAAAAA==.',
Zo='Zodier:BAAANQAECggICwABNQAFFAYIDAAUAG8XAA==.Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYIEAAAAA==.',
Zu='Zugore:BAAANQADCgMIAwAAAA==.Zulugangrene:BAABNQAECn8sAAIOAAoKBA3XggCGAQAOAAoKBA3XggCGAQAAAA==.Zun:BAABNQAECn8dAAIUAAgKlAooDgBnAQAUAAgKlAooDgBnAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgYIFAAOABEOAA==.',
['Çh']='Çhunchunmaru:BAAANQAECgIIAwABNQAECgoKNwAHADgjAA==.',
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
