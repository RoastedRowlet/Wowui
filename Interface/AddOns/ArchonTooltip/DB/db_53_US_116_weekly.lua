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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Elemental','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Retribution','Druid-Balance','Evoker-Devastation','DeathKnight-Frost','Shaman-Enhancement','Mage-Frost','Paladin-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-Marksmanship','Evoker-Preservation','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Priest-Holy','Druid-Guardian','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Monk-Windwalker','Monk-Brewmaster',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aadrisedh:BAAANQAECgQIAwAAAA==.Aaeryn:BAAANQAECgEIAQAAAA==.Aaliyshaa:BAAANQAECgYIEwAAAA==.Aaramis:BAABNQAECn86AAIBAAoKBRi6MgA9AgABAAoKBRi6MgA9AgAAAA==.',
Ab='Abrakadabruh:BAABNQAECn8jAAICAAkK9xQrRAAzAgACAAkK9xQrRAAzAgAAAA==.Abyssal:BAABNQAECn8iAAQDAAoK4xrvHwCNAQAEAAcKuw4SRgCWAQADAAgK3hnvHwCNAQAFAAUKnxNjIADDAAAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.Adannist:BAAANQADCgQIBAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.Aellwyn:BAAANQAECgUICAABNQAECggIGgAGAGUHAA==.',
Ai='Aidoffhealer:BAAANQADCgcICgAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQAECgIIAgAAAA==.Alystair:BAAANQADCgYIBgABNQAECgcICwAHAAAAAA==.',
Am='Amadayus:BAABNQAECn8oAAIIAAoKwyV0AgDfAwAIAAoKwyV0AgDfAwAAAA==.Ambellina:BAAANQAECgYICgAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anaye:BAAANQADCgIIAgABNQAECgkJJwADAEUeAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8HAAMJAAcKxgpOHAAUAQAJAAUKvw1OHAAUAQAKAAIKUAYfCwBRAAA1AAQKf1IABAoACgoMHYoMAJcBAAkACQqvHGlXAFACAAoABwp+GYoMAJcBAAsAAQrJGWoyAD0AAAAA.Archiball:BAAANQAECggICAABNQAECggIGgAGAGUHAA==.Arclock:BAABNQAECn8bAAIJAAkK2grPXwCiAQAJAAkK2grPXwCiAQAAAA==.Arconnai:BAABNQAECn9GAAIMAAoKxCDbMQBqAgAMAAoKxCDbMQBqAgAAAA==.Areilin:BAAANQAECgQIBgAAAA==.Areiotyrict:BAABNQAECn8iAAMNAAYK5wODJQBoAAANAAYKuwODJQBoAAAOAAIKJgPEPgBGAAAAAA==.Arkaÿne:BAAANQADCgYIBgABNQAECgYIFAAPABEOAA==.Arnøld:BAAANQAECgUICgAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.Artificial:BAAANQADCgEIAQAAAA==.',
As='Asham:BAAANQAECgEIAQAAAA==.Ashan:BAAANQAECggIBQAAAA==.Asiago:BAAANQAECgQIEAABNQAECgoKQgAQAM8gAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgcICwAAAA==.',
Av='Avvalethra:BAABNQAECn8bAAIIAAoK6g+QkQDmAQAIAAoK6g+QkQDmAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAcIHQARACsZAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAABNQAECn8rAAICAAoKIwadjAB6AQACAAoKIwadjAB6AQAAAA==.Baineofagony:BAAANQADCgUIBQAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn9AAAIGAAkKlhvaJQA8AgAGAAkKlhvaJQA8AgAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECggIDgAAAA==.',
Be='Bearlinwall:BAAANQAECgMIBQAAAA==.Bearmaster:BAABNQAECn8cAAIIAAYK5QKbBgH5AAAIAAYK5QKbBgH5AAAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECggIDAAAAA==.Bereaved:BAAANQADCgUIBQAAAA==.Bews:BAAANQADCgQIBAAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAABNQAECn8dAAICAAkKURtmbwCfAgACAAkKURtmbwCfAgAAAA==.Billybones:BAABNQAECn8ZAAISAAUKhAlsbADtAAASAAUKhAlsbADtAAAAAA==.Bimbobaby:BAAANQAECgYIEQABNQADCgEIAQAHAAAAAA==.',
Bl='Blackholes:BAABNQAECn8VAAIJAAUKxAgX5wD7AAAJAAUKxAgX5wD7AAAAAA==.Blackwÿn:BAAANQADCggIFgABNQAECgYIFAAPABEOAA==.Bladeblade:BAABNQAECn8fAAMFAAoK7B/2BQA6AgAFAAoK7B/2BQA6AgAEAAcKlBC0QgCsAQABNQAFFAUIDQAMAN8dAA==.Bladedozzer:BAAANQAECgcICQAAAA==.Blindinglite:BAABNQAECn85AAIEAAoKAh1WEwADAwAEAAoKAh1WEwADAwAAAA==.Bloodhaze:BAABNQAECn8dAAIEAAoKnCOwGADVAgAEAAoKnCOwGADVAgAAAA==.Blorp:BAAANQAECgYICwABNQAECgoKRgAIANEkAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQAECgIIAgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.Boriquagypsy:BAAANQADCgUIBQAAAA==.Bownystark:BAAANQAECgQIBAAAAA==.',
Br='Brchm:BAAANQAECgQIDQAAAA==.Brickly:BAABNQAECn8ZAAMEAAkKqB2uHgCkAgAEAAgKqB2uHgCkAgAFAAEKAAAELgBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgoKQgAQAM8gAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgUICQAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.',
Bx='Bxxberry:BAAANQAECgYICAAAAA==.',
By='Byeon:BAAANQAECgUICQAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgoKQQABAPocAA==.',
['Bú']='Búkki:BAAANQADCgYIHgAAAA==.',
['Bü']='Bükkì:BAAANQADCggIGQAAAA==.Bükkï:BAAANQADCgcIEgAAAA==.',
Ca='Caboodles:BAABNQAECn8rAAMLAAgKNAdgNADyAAALAAYKugZgNADyAAAJAAgK6wXVwQC6AAAAAA==.Cachamama:BAAANQAECgIIAgAAAA==.Camishami:BAACNQAFFH8JAAIBAAQK4Bt0EAA2AQABAAQK4Bt0EAA2AQA1AAQKfygAAwEACQqCGH8mAH8CAAEACQqCGH8mAH8CAAYAAgrLCp/vADgAAAAA.Candyhandsjf:BAABNQAECn8nAAIDAAkKRR59DgBgAgADAAkKRR59DgBgAgAAAA==.Candyhandz:BAAANQADCgYIEQABNQAECgkJJwADAEUeAA==.Cannlol:BAAANQAECgMIAgAAAA==.Capriestsün:BAAANQAECgUICgABNQAECgoKNQAIAFYYAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgoKQQABAPocAA==.Catharsis:BAAANQAECgQIBgAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn9AAAIDAAoKfB3lCgAuAwADAAoKfB3lCgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQAECgQIBAAAAA==.Cheesus:BAABNQAECn9CAAIQAAoKzyAzDwCsAgAQAAoKzyAzDwCsAgAAAA==.Chicharon:BAABNQAECn8+AAICAAoKgQ7fYADlAQACAAoKgQ7fYADlAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAABNQAECn8eAAITAAoKeRFKFgCUAQATAAoKeRFKFgCUAQAAAA==.Chlona:BAAANQABCgIIAgAAAA==.Chokolock:BAABNQAECn8yAAIJAAoKSBULOwAXAgAJAAoKSBULOwAXAgAAAA==.Chunggus:BAAANQABCgYICQAAAA==.Churva:BAABNQAECn8jAAMBAAoKbweGoQAzAQABAAkKrgWGoQAzAQAGAAYKVgZUvAAaAQAAAA==.',
Cl='Cleggane:BAAANQABCgcIBwAAAA==.',
Co='Coko:BAAANQAECgUIBQABNQAECgoKPwAIADgjAA==.Condemned:BAAANQADCgYIDAAAAA==.Cooch:BAAANQAECgYICAAAAA==.Cosecantes:BAABNQAECn8gAAMUAAYKjR3YDQDRAQAUAAYKjR3YDQDRAQACAAIKDQNBtAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgoKNQAIAFYYAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYIDQAAAA==.Crackjönes:BAAANQADCgMIAwAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAABNQAECn8qAAIVAAkKcR5HIgCeAgAVAAkKcR5HIgCeAgAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crucify:BAAANQAECggIDgAAAA==.Crul:BAAANQABCgIIAQAAAA==.Crusäderaura:BAAANQAECgcIEwAAAA==.Cryptìc:BAACNQAFFH8KAAIWAAUKJRPgCgBFAQAWAAUKJRPgCgBFAQA1AAQKfygAAhYACgpyIK0QAO4CABYACgpyIK0QAO4CAAE1AAUUBggHABQApg0A.',
Da='Dabbia:BAABNQAECn8dAAQKAAkKUhx9CgDQAQAKAAYKJR59CgDQAQAJAAQKfB5czQAvAQALAAQKMxeTMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Dahunte:BAAANQAECgYICQAAAA==.Damara:BAAANQADCggICgAAAA==.Damented:BAAANQADCggIEQABNQAECgoKQQABAPocAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadcheck:BAAANQAECgEIAQAAAA==.Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECn8uAAMSAAkK/BRsLgAuAgASAAkK/BRsLgAuAgAXAAIKxwa2zABTAAABNQAECgoKMgAJAEgVAA==.Deathcabb:BAAANQAECgIIAgAAAA==.Deathtreader:BAAANQADCgYICAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAABNQAECn8XAAMIAAcKRwgzngBbAQAIAAcKRwgzngBbAQAYAAMKtgLKcgBrAAAAAA==.Delthrus:BAAANQAECgQIDwABNQAECgoKOQAOALARAA==.Demonarc:BAABNQAECn8lAAIDAAoKDxkSHAB1AgADAAoKDxkSHAB1AgAAAA==.Detreset:BAABNQAECn8ZAAIZAAkKaRhLEQCWAgAZAAkKaRhLEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECn8oAAMCAAoKhAw6ZQDaAQACAAoKhAw6ZQDaAQAaAAEKGQt5DAA0AAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgkJGgASAIQKAA==.Dinsum:BAAANQADCggIFgAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgoKSAAbAIYkAA==.Disorder:BAAANQAECgIIAwAAAA==.Dixeenormis:BAAANQAECgEIAQAAAA==.Dixonbuttsz:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgoKSAAbAIYkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgAHAAAAAA==.Doomscroll:BAAANQAECgEIAQAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQAECgMIAwAAAA==.Dragtiago:BAAANQADCgYIFQAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8WAAIYAAgK2BfpIgA2AgAYAAgK2BfpIgA2AgAAAA==.Drezbi:BAAANQAECgQICQAAAA==.Droodmon:BAAANQADCgIIAgAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8vAAIPAAoKFQ4MmQDxAQAPAAoKFQ4MmQDxAQAAAA==.Durzaka:BAAANQAECgcIEwAAAA==.Durzu:BAAANQAECgQIDgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
['Dá']='Dáeves:BAAANQAECggIDgABNQAFFAYICwAWAOAXAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn9GAAMcAAoKTxK8KgA/AgAcAAoKIxG8KgA/AgAbAAoKVA0USADFAQAAAA==.',
Eg='Egholom:BAABNQAECn81AAIEAAoKURL+KQCoAQAEAAoKURL+KQCoAQAAAA==.',
Ek='Eks:BAAANQADCggIFgAAAA==.',
El='Electrcfrost:BAABNQAECn9MAAIGAAoKRyMvCAAyAwAGAAoKRyMvCAAyAwAAAA==.Elkanàh:BAABNQAECn8+AAQPAAoKfx3DNgB7AgAPAAoKfx3DNgB7AgAVAAgKNRx5TQA0AgAdAAEKZwseaAAnAAABNQAFFAcIEAAeAOoTAA==.Elorene:BAABNQAECn8iAAMaAAgKfQjVAwCVAQAaAAgKTwjVAwCVAQACAAYK/wHChwG2AAAAAA==.Elunara:BAABNQAECn8ZAAIfAAgKZRhmGgDUAQAfAAgKZRhmGgDUAQABNQAFFAcIBwAJAMYKAA==.Elyysian:BAACNQAFFH8LAAIWAAYK4BeoCACCAQAWAAYK4BeoCACCAQA1AAQKf0oAAxYACgpMJKAEAI4DABYACgpMJKAEAI4DAB4AAwqWA43lAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIBAAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgcICwAHAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8MAAICAAYK7hycGQCtAQACAAYK7hycGQCtAQA1AAQKfysAAwIACgrAIxAjAKgCAAIACgrAIxAjAKgCABQAAQosF+c9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8qAAIBAAgKSBrAPQAIAgABAAgKSBrAPQAIAgABNQAECgoKPAAfAF4lAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgUIBQABNQAECgoKPAAfAF4lAA==.',
Fa='Fadam:BAABNQAECn82AAICAAoK8Q+jXgDrAQACAAoK8Q+jXgDrAQAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggIDwAAAA==.Fanttic:BAAANQADCgQIBAAAAA==.Fastrialimas:BAAANQAECgEIAQAAAA==.Fatigue:BAAANQAECgEIAQAAAA==.Fatpo:BAABNQAECn8XAAQeAAgK2hxgagDfAQAeAAcK3xtgagDfAQAWAAQKkR4GOwBQAQAgAAEKBSAwIgBUAAABNQAECgkJGQAEAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn82AAICAAoKJB9fdgCRAgACAAoKJB9fdgCRAgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8bAAIGAAYK2xivBwBPAQAGAAYK2xivBwBPAQA1AAQKfzEAAgYACgrUIU4NAP0CAAYACgrUIU4NAP0CAAAA.Floriyana:BAAANQAECgMICQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgoKTQACAEciAA==.Fourpriest:BAAANQAECgUICgAAAA==.Foô:BAABNQAECn8+AAMcAAoKqSDXDgALAwAcAAoKqSDXDgALAwAbAAUKHBLNMgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAABNQAECn8XAAICAAgKugpopwBDAQACAAgKugpopwBDAQAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAABNQAECn8aAAIGAAgKZQeFcgAbAQAGAAgKZQeFcgAbAQAAAA==.Furdinand:BAAANQADCgUICgAAAA==.Furyrosa:BAAANQADCggICgAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Fuzybritches:BAAANQADCgcICgABNQAECgYIDAAHAAAAAA==.',
Fy='Fyah:BAACNQAFFH8FAAIPAAIKcBEgIQCLAAAPAAIKcBEgIQCLAAA1AAQKfzgAAg8ACgpCHi84AHYCAA8ACgpCHi84AHYCAAE1AAUUBwgXAAgAaRYA.Fyaza:BAAANQADCggICQABNQAFFAcIFwAIAGkWAA==.',
Ga='Gaga:BAAANQADCgMIAgAAAA==.Gargamels:BAAANQAECggIEAABNQAECggIGgAGAGUHAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICwAAAA==.Gerttie:BAABNQAECn8oAAMhAAgKKBMbJwCaAQAhAAgKKBMbJwCaAQAQAAEKAAAlzwAOAAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8oAAIZAAgKOB3oAgDGAgAZAAgKOB3oAgDGAgA1AAQKfycAAhkACgr6H8ENAMsCABkACgr6H8ENAMsCAAAA.Gistlek:BAAANQAECggICAAAAA==.',
Gl='Gloryho:BAAANQABCgUIBgABNQADCgEIAQAHAAAAAA==.',
Go='Gobsquadp:BAABNQAECn8dAAIeAAkKcg/TawCBAQAeAAkKcg/TawCBAQABNQAECgoKPAAfAF4lAA==.',
Gr='Grassmoker:BAAANQAECgUIDAAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJJwAiAFMeAA==.Grievex:BAABNQAECn89AAIPAAoKpgqMkACWAQAPAAoKpgqMkACWAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumnumnug:BAAANQADCgYIBgAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Gu='Guzzlr:BAAANQAECgYIEQAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAYAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Haring:BAABNQAECn8WAAIEAAkKSxX2HAARAgAEAAkKSxX2HAARAgAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAACNQAFFH8FAAIeAAIKPhthJwCRAAAeAAIKPhthJwCRAAA1AAQKf0kAAh4ACgqyHekYABIDAB4ACgqyHekYABIDAAAA.Hedumnotner:BAAANQAECggICAAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAYIDQAPACkOAA==.Hemostasis:BAACNQAFFH8NAAIPAAYKKQ60BwDSAQAPAAYKKQ60BwDSAQA1AAQKf0kABA8ACgraI/sQAB8DAA8ACgraI/sQAB8DABUAAgrmD3AXAUYAAB0AAQodFi5tADcAAAAA.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQAHAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.',
Ho='Homeslice:BAABNQAECn8hAAQLAAgKIxSrDQDbAAAKAAQKuRVgFAAEAQALAAUKohSrDQDbAAAJAAUKZgrRCAG6AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECn9BAAIjAAoKcSGeAQDhAgAjAAoKcSGeAQDhAgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcIBwAAAA==.',
['Hó']='Hózaÿ:BAAANQADCgEIAQAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn9bAAMJAAoKVA5PTgDWAQAJAAoKVA5PTgDWAQALAAMKtAQIVACCAAAAAA==.',
Ib='Iblow:BAAANQADCgEIAQAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Il='Illestone:BAAANQAECgEIAQABNQAFFAIIBQAPABsJAA==.Illydan:BAAANQADCgMIAwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQADCgUIBQAAAA==.',
Ir='Irrenadro:BAABNQAECn9LAAIPAAoKzRDskwD8AQAPAAoKzRDskwD8AQAAAA==.',
Is='Islandhunter:BAAANQABCgQIBAAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgYIDAAAAA==.',
Je='Jeage:BAAANQAECgQIBQABNQAECgkJIAAGAJ4iAA==.Jera:BAAANQADCgIIAwAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgYICAABNQAECgkJHgATAGkiAA==.Jimmybones:BAAANQABCgIIAgAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn8yAAIIAAkK8xhnawA8AgAIAAkK8xhnawA8AgAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kallivar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAoKKgAPAOYfAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAcIBwAJAMYKAA==.',
Ke='Keetra:BAACNQAFFH8dAAIIAAYKXxRmCQBCAQAIAAYKXxRmCQBCAQA1AAQKfysAAggACgoQIcUtAOQCAAgACgoQIcUtAOQCAAAA.Keiriline:BAABNQAECn8lAAMSAAcKVRDHTQB/AQASAAcKVRDHTQB/AQAkAAIKqAKL0AAtAAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQAECgUIBAAAAA==.Kitdrco:BAAANQAECgQIBAAAAA==.',
Kl='Klix:BAAANQADCgcICwABNQAECgkJJwADAEUeAA==.',
Kn='Knight:BAABNQAECn8bAAMCAAkKnB0RcgCaAgACAAgKnB0RcgCaAgAaAAIKzAjaCQBoAAAAAA==.Knuggz:BAABNQAECn8mAAIMAAkKXhueMQBrAgAMAAkKXhueMQBrAgAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgMIAgAAAA==.Kumbustinher:BAAANQAECgMIAwAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAQIEQAeALAlAA==.Kylepala:BAAANQAECgYIBgABNQAFFAQIEQAeALAlAA==.Kylepriest:BAACNQAFFH8RAAMeAAQKsCXjDAC8AQAeAAQKsCXjDAC8AQAWAAMK9g1HDwCQAAA1AAQKf0gABB4ACgqIJssBANADAB4ACgqIJssBANADABYACAplGsYPAEoCACAAAgopI04XALwAAAAA.Kyntamun:BAAANQADCgcIDQABNQAECgUICQAHAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgkJJwADAEUeAA==.Lambeáu:BAABNQAECn8kAAIIAAgKSx6aUAAWAgAIAAgKSx6aUAAWAgAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAABNQAECn8XAAQRAAgKsAqhFADZAAARAAcKOwahFADZAAAiAAMKXwSqHQB2AAAZAAUKbwW9RQB0AAAAAA==.Lamdabow:BAAANQAECgcIEAABNQAECggIFwARALAKAA==.Lamdadk:BAAANQADCggICQAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgoKMAAEAMkeAA==.Larzoh:BAABNQAECn8wAAMEAAoKyR5JDABIAwAEAAoKyR5JDABIAwADAAMKJQbEWQCdAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lethargy:BAAANQADCgYIDAAAAA==.Levapally:BAAANQAECgEIAQAAAA==.',
Li='Lidorila:BAAANQADCgUIEQAAAA==.Lightguard:BAABNQAECn8oAAIPAAgKchl0iwAPAgAPAAgKchl0iwAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8mAAIIAAgKkgTu1gBSAQAIAAgKkgTu1gBSAQAAAA==.Lilwiz:BAAANQAECgUIDQAAAA==.Linalala:BAABNQAECn/gAAQhAAkK8yZnAQAQBAAhAAkK8yZnAQAQBAAlAAcKqRHhFACtAQAQAAIKLAwbmQB1AAAAAA==.Linnxp:BAAANQAECgMIBQABNQAECgYIDAAHAAAAAA==.Linnxs:BAAANQAECgYIDAAAAA==.Linnxvx:BAAANQAECgQIAQABNQAECgYIDAAHAAAAAA==.Literacola:BAABNQAECn8uAAICAAoKMBCoVgAAAgACAAoKMBCoVgAAAgAAAA==.',
Lo='Lorino:BAAANQAECgEIAQAAAA==.Lothaire:BAAANQADCgYIBQAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAABNQAECn8YAAMWAAoKuQ6NHACXAQAWAAkKlwyNHACXAQAeAAQKhwspqQDPAAAAAA==.Lugeyamnk:BAABNQAECn8aAAImAAkK2BA9HQCgAQAmAAkK2BA9HQCgAQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgUIBQAAAA==.Lustnbeiber:BAABNQAECn8sAAQGAAkKwhXRQgBqAgAGAAkKwhXRQgBqAgABAAYK4AtbrgATAQATAAUKWAT9KQCPAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgcIEgAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggIEAABNQAECgoKLQAdAD4jAA==.Lynchà:BAABNQAECn8tAAIdAAoKPiO8BwAmAwAdAAoKPiO8BwAmAwAAAA==.Lynchä:BAAANQAECgYIBgABNQAECgoKLQAdAD4jAA==.',
Ma='Maakun:BAABNQAECn8/AAIeAAkKbhgdPgByAgAeAAkKbhgdPgByAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIDQAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECn9DAAMBAAoKKyH1FgAaAwABAAoKKyH1FgAaAwAGAAgKlRu/RACqAQAAAA==.Malchezaar:BAABNQAECn8mAAIJAAoKGxDIWQCzAQAJAAoKGxDIWQCzAQAAAA==.Malfrun:BAABNQAECn85AAIOAAoKsBFKDwCqAQAOAAoKsBFKDwCqAQAAAA==.Marinnite:BAAANQADCggIDgAAAA==.Markzugrberg:BAAANQADCgMIAwAAAA==.Marox:BAABNQAECn83AAICAAoK+xpTOQBVAgACAAoK+xpTOQBVAgAAAA==.Marrøwgar:BAABNQAECn8nAAMXAAkKEiBSDgCKAgAXAAkKEiBSDgCKAgAkAAEKAABhxwA6AAAAAA==.Mathrim:BAECNQAFFH8SAAQJAAUKWiDdHACzAAAJAAMKtyPdHACzAAALAAEKoBk0DQBSAAAKAAEKAABrGgAAAAA1AAQKfzwAAwkACgo+JQAEALgDAAkACgo+JQAEALgDAAsAAgqOFRJUAIIAAAAA.Matooka:BAABNQAECn8cAAIIAAkK2QQG1gBUAQAIAAkK2QQG1gBUAQAAAA==.Maynji:BAAANQADCggICAAAAA==.Mazima:BAAANQAECgcIEgAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAFFAIIBQAPABsJAA==.',
Me='Meyzer:BAAANQAECgUIBQAAAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Mikun:BAAANQAECgMIBAAAAA==.Mingosh:BAAANQADCgMIAwAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYIEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojix:BAAANQAECggICAAAAA==.Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAABNQAECn8UAAMXAAYKAhxHUQDOAQAXAAYKAhxHUQDOAQASAAUKhw3VcADcAAAAAA==.Mommÿ:BAACNQAFFH8PAAIeAAMKyhnoHQDiAAAeAAMKyhnoHQDiAAA1AAQKfz4AAx4ACgrOHUQoAMkCAB4ACgrOHUQoAMkCACAABgpIDL4QAB0BAAAA.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8xAAIfAAoKgRFNFwD4AQAfAAoKgRFNFwD4AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgoKPwAIADgjAA==.Moolificent:BAABNQAECn8aAAISAAkKhAq8UQBqAQASAAkKhAq8UQBqAQAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAABNQAECn8fAAIhAAoK0RvNFwCCAgAhAAoK0RvNFwCCAgAAAA==.',
Mu='Muat:BAAANQAECggIAgAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgoKRQAcAMYVAA==.Muddgore:BAAANQADCggIDgABNQAECgoKRQAcAMYVAA==.Muddthir:BAAANQADCgQIBAABNQAECgoKRQAcAMYVAA==.Murderino:BAAANQADCggICAAAAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgoKRgAIANEkAA==.Mustardrogue:BAAANQAECgUIBQAAAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn9FAAMcAAoKxhUEFgBxAQAbAAgKohCyXAB5AQAcAAkK7RYEFgBxAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgIIAwAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECn9AAAICAAoKkBH8VAAEAgACAAoKkBH8VAAEAgAAAA==.Nisia:BAABNQAECn8UAAMJAAkKDxgYOQCpAgAJAAkKDxgYOQCpAgALAAEKiwiSfAAwAAABNQAFFAUIDQAMAN8dAA==.Nito:BAABNQAECn8lAAISAAkKGBEMNAANAgASAAkKGBEMNAANAgAAAA==.',
No='Nobainer:BAAANQADCgQIAwABNQADCgUIBQAHAAAAAA==.Nohkano:BAACNQAFFH8IAAInAAMKCyXLAgBKAQAnAAMKCyXLAgBKAQA1AAQKf1MAAycACgpmJl8AAPEDACcACgpmJl8AAPEDACYABwriC9QnAEIBAAAA.Nokt:BAABNQAECn8VAAIJAAkKuhT7fQDrAQAJAAkKuhT7fQDrAQAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECggIDwAAAA==.Noveerra:BAAANQADCgcIDwABNQAECgUICQAHAAAAAA==.',
Nu='Numbuh:BAAANQAECgQIBwAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakremi:BAAANQADCgMIAwAAAA==.Oakrogue:BAAANQAECgQIBgAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ok='Okboomie:BAAANQABCgEIAQAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ornahua:BAAANQAECggIAwAAAA==.Ortillious:BAAANQAECgQICAABNQAECgcIEgAHAAAAAA==.',
Ov='Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggIDwAAAA==.',
Pa='Painwhisper:BAAANQABCgQIBAAAAA==.Paladeez:BAAANQAECggIDgABNQAFFAYIDQAPACkOAA==.Palaweenie:BAAANQABCgQIBAAAAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcIDAAAAA==.Pantheons:BAAANQAECgQIEQAAAA==.Parsi:BAABNQAECn8uAAMFAAkK8R1XBQBaAgAFAAkK8R1XBQBaAgADAAIKmQduYQBnAAAAAA==.Pattysmyth:BAABNQAECn8WAAIOAAYKsApDJwCtAAAOAAYKsApDJwCtAAABNQADCggIEgAHAAAAAA==.Paulinemaroi:BAABNQAECn8XAAICAAoKAx9PTwATAgACAAoKAx9PTwATAgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgoKFwACAAMfAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgkJJwADAEUeAA==.Pennywhys:BAAANQADCgYIBgAAAA==.Peäches:BAAANQAECgMIAwAAAA==.',
Ph='Phaell:BAAANQADCgEIAQAAAA==.Philip:BAAANQAECggIEAAAAA==.Phäel:BAAANQABCgIIAgAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQAEAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDAAHAAAAAA==.Poppafury:BAAANQAECgEIAQAAAA==.Poppapulls:BAAANQAECggIEAAAAA==.Pottyy:BAAANQABCgIIBAAAAA==.Poubear:BAAANQAECggICgABNQAECggIGgAGAGUHAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQAEAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcIBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgYICgABNQAECgoKJAAWAIUdAA==.',
['Pä']='Pändora:BAAANQAECgYICAAAAA==.',
Ra='Rabite:BAABNQAECn88AAIfAAoKXiVoBABkAwAfAAoKXiVoBABkAwAAAA==.Radiance:BAEANQAECgYIDgABNQAFFAcIDAAYALoeAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQAECgEIAQAAAA==.Ramshunter:BAAANQAECgQIBQAAAA==.Randyvivaldi:BAAANQAECggICwAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rathasas:BAABNQAECn9GAAMZAAkK8h36DwCpAgAZAAkK8h36DwCpAgARAAIKaRjbMACPAAAAAA==.Ratnob:BAABNQAECn8hAAIXAAoK6hQyOQBAAgAXAAoK6hQyOQBAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMiAAkKUx62AwDqAgAiAAkKUx62AwDqAgARAAEKfwaTQAAqAAAAAA==.Relda:BAAANQAECgUICwABNQAECgkJHgATAGkiAA==.Remye:BAABNQAECn8tAAIVAAoKVhlsPgBqAgAVAAoKVhlsPgBqAgAAAA==.Rennshi:BAABNQAECn8dAAIEAAkK8CVWCAB2AwAEAAkK8CVWCAB2AwAAAA==.Reportedhunt:BAABNQAECn81AAIIAAoKVhhrQACpAgAIAAoKVhhrQACpAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgYIBgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimmy:BAAANQAECgYIBAABNQADCgEIAQAHAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8pAAMDAAYK6AYTOwC1AAADAAYK6AYTOwC1AAAEAAIKfgRkiQBSAAAAAA==.Roldaza:BAAANQAECgUICgAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn9GAAMIAAoK0SRpFwA8AwAIAAoK0SRpFwA8AwAYAAYKTgy7SwAGAQAAAA==.',
Ru='Rulep:BAAANQAECggICQABNQAECggIFwACALoKAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Ryotwar:BAAANQAECgcIDAAAAA==.Rythmatic:BAABNQAECn9IAAMbAAoKhiRfCwAWAwAbAAoKPiRfCwAWAwAcAAcKoyEKIACBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sacrilege:BAAANQAECggIBAAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQAECggIDgABNQADCgEIAQAHAAAAAA==.Sakieri:BAABNQAECn89AAMWAAoKZRoXGgB8AgAWAAoKZRoXGgB8AgAeAAkKOhBySQD9AQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQAECgQIAwAAAA==.Sangan:BAABNQAECn9GAAICAAoK4B5yIQCvAgACAAoK4B5yIQCvAgAAAA==.Sangen:BAAANQABCgMIAwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwAHAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Sebaz:BAAANQAECgEIAQAAAA==.Secondcoming:BAAANQADCgYIBgAAAA==.Segolas:BAAANQADCgEIAQAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8dAAIRAAcKKxkiAQBiAQARAAcKKxkiAQBiAQA1AAQKfyoAAhEACgpFJKAFADYDABEACgpFJKAFADYDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAABNQAECn8aAAMDAAgKiwXZMQD2AAADAAgKVwXZMQD2AAAFAAMKqQRTKQBCAAAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shambho:BAAANQAECgUIBAAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgYIBwAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8vAAMJAAoKDSG1EwA+AwAJAAoK/SC1EwA+AwALAAMKgh3vTQCVAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8nAAICAAkKJgqU/QCSAQACAAkKJgqU/QCSAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAiAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Solodruid:BAAANQABCgEIAQAAAA==.Soulezz:BAAANQAECgUJBwAAAA==.',
Sp='Spectrum:BAAANQADCgQIBAAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECn8/AAIIAAoKOCMlDQAdAwAIAAoKOCMlDQAdAwAAAA==.Stingerjb:BAAANQAECggIDgABNQAECgoKPwAIADgjAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAABNQAECn8cAAIJAAoK/BYXVABZAgAJAAoK/BYXVABZAgAAAA==.Sucemabite:BAAANQADCgEIAQAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunalios:BAAANQAECgEIAQAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgkJFgAPAAAhAA==.',
Sy='Syl:BAAANQAECgUIDgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgoKLQAmAIIcAA==.Teemonk:BAABNQAECn8tAAImAAoKghykEwC7AgAmAAoKghykEwC7AgAAAA==.Teepal:BAAANQADCgUIBQABNQAECgoKLQAmAIIcAA==.Teila:BAAANQABCggIJgAAAA==.Teladrel:BAAANQAECggIAwAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAABNQAECn8qAAITAAgK+BVIFQCmAQATAAgK+BVIFQCmAQAAAA==.Teribullduce:BAACNQAFFH8JAAIIAAQKIxw6CwAmAQAIAAQKIxw6CwAmAQA1AAQKf0EAAggACgrLJBwKADQDAAgACgrLJBwKADQDAAAA.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thasaran:BAAANQAECgMIAwAAAA==.Thickyricky:BAABNQAECn8aAAMcAAkKGBm0MgASAgAcAAkKOBO0MgASAgAbAAMKAR5DgQABAQABNQAECgkJHgATAGkiAA==.Thingol:BAAANQABCgYIFQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAgIKAAZADgdAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgQIDAABNQAFFAIIBQAPABsJAA==.Thuggerjr:BAACNQAFFH8FAAIPAAIKGwlBJQB4AAAPAAIKGwlBJQB4AAA1AAQKfzcAAg8ACgrmGehHAEICAA8ACgrmGehHAEICAAAA.Thundersurge:BAAANQAECgUICQABNQAECgoKNQAIAFYYAA==.Thænes:BAABNQAECn8UAAMPAAYKEQ4G7ABEAQAPAAYKEQ4G7ABEAQAdAAQKawZqVABOAAAAAA==.Thûr:BAAANQAECgQIBwABNQAECgoKQQABAPocAA==.',
Ti='Tigg:BAABNQAECn8mAAIGAAgKNARZ4wDQAAAGAAgKNARZ4wDQAAAAAA==.Tildin:BAAANQADCggIEwAAAA==.Tinkerdinker:BAAANQAECgIIAwAAAA==.Tipsout:BAACNQAFFH8NAAMMAAUK3x1VEQAVAQAMAAQK3x1VEQAVAQAOAAEKAACKCQAAAAA1AAQKf0gAAwwACgqWJXwFAGADAAwACgqWJXwFAGADAA4ABwp7FRIiADoBAAAA.',
Tn='Tnemith:BAAANQABCgUIBQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgoKLQAmAIIcAA==.Torastrasza:BAAANQAFFAIIAgAAAA==.Totemm:BAABNQAECn8WAAIBAAkKGh9pMACgAgABAAkKGh9pMACgAgAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn9BAAMBAAoK+hwtLQBZAgABAAoK+hwtLQBZAgAGAAUKQhGTsgAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgQIBQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAABNQAECn8XAAIVAAgK4xqTRQDrAQAVAAgK4xqTRQDrAQAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIBQAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Ul='Ulakyai:BAAANQADCgEIAQABNQAECgUICQAHAAAAAA==.',
Un='Unfocused:BAABNQAECn9MAAIQAAoK8CErDQDHAgAQAAoK8CErDQDHAgABNQAECgoKTAAGAEcjAA==.Unholybelac:BAAANQADCgYIDQAAAA==.',
Ur='Urgmathron:BAABNQAECn8mAAIdAAkKxRZtGQCSAQAdAAkKxRZtGQCSAQAAAA==.',
Va='Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAYICwAWAOAXAA==.Vansthir:BAAANQAECggIDgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIDgABNQAFFAYIEgAMAHsUAA==.Vaush:BAABNQAECn8ZAAMXAAcKSgPlmgDJAAAXAAYKogPlmgDJAAASAAcKGALMhgCFAAAAAA==.',
Ve='Veigär:BAAANQAECgEIAgAAAA==.Verasuchi:BAAANQAECgIIAQAAAA==.',
Vi='Victorix:BAAANQADCgUIBQAAAA==.Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8eAAIiAAYK2w1/EQAdAQAiAAYK2w1/EQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.Volcanoez:BAAANQAECgIIBAAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vr='Vrezor:BAAANQAECggIDAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.Vulgatee:BAAANQAECgMIAwAAAA==.Vulpala:BAABNQAECn8VAAIPAAkKDxM1WgAQAgAPAAkKDxM1WgAQAgAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgoKUgAQAEolAA==.',
Wa='Wardian:BAAANQAECgYIDAABNQAECgoKNAAPAAEXAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgoKNQAIAFYYAA==.Warthyr:BAAANQADCgIIAgAAAA==.',
We='Welfairline:BAAANQADCggIHgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAFFAQICQAIACMcAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.Xarttoplek:BAAANQAECgMIAwABNQAECgoKPwAIADgjAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8jAAImAAoKfR1UDgD6AgAmAAoKfR1UDgD6AgAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8lAAIMAAkKtg7NngDPAQAMAAkKtg7NngDPAQAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgYIKQAAAA==.Zarik:BAABNQAECn8oAAIJAAgK3Ql0hABBAQAJAAgK3Ql0hABBAQAAAA==.',
Ze='Zeddoc:BAEANQAECgEIAgAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIAgAHAAAAAA==.Zenfist:BAAANQADCgUIBQAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAABNQAECn8oAAIPAAoKbhHHgAC2AQAPAAoKbhHHgAC2AQAAAA==.Zenotath:BAAANQABCgMIAgAAAA==.Zenveil:BAAANQAECggICwAAAA==.',
Zo='Zodier:BAAANQAECggICgABNQAFFAYIDAAUAG8XAA==.Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYIEAAAAA==.',
Zu='Zugore:BAAANQADCgMIAwAAAA==.Zulugangrene:BAABNQAECn8sAAIPAAoKBA2IkQCUAQAPAAoKBA2IkQCUAQAAAA==.Zun:BAABNQAECn8dAAIUAAgKlAq0EABjAQAUAAgKlAq0EABjAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgYIFAAPABEOAA==.',
['Çh']='Çhunchunmaru:BAAANQAECgIIAwABNQAECgoKPwAIADgjAA==.',
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
