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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Druid-Balance','Evoker-Devastation','Shaman-Elemental','Shaman-Enhancement','Mage-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Protection','Evoker-Preservation','Mage-Fire','Rogue-Subtlety','Hunter-Marksmanship','Rogue-Assassination','Priest-Holy','Druid-Guardian','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aadrisedh:BAAANQAECgMIBAAAAA==.Aaeryn:BAAANQAECgEIAgAAAA==.Aaliyshaa:BAAANQAECgYIDQAAAA==.Aanorim:BAAANQAECgEIAQAAAA==.Aaramis:BAABNQAECn8yAAIBAAoKExW8KQAHAgABAAoKExW8KQAHAgAAAA==.',
Ab='Abrakadabruh:BAABNQAECn8VAAICAAcKUxFgYgCHAQACAAcKUxFgYgCHAQAAAA==.Abyssal:BAABNQAECn8fAAQDAAoKyhmXFwB+AQAEAAcKuw4SRgCWAQADAAgKlRmXFwB+AQAFAAUKbBFjIADDAAAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.Adannist:BAAANQADCgQIBAABNQAECgEIAgAGAAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICgAAAA==.Aellwyn:BAAANQAECgMICgABNQAECggIEQAGAAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgcICgAAAA==.Ainna:BAAANQAECgEIAQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQAECgEIAgAAAA==.Alystair:BAAANQADCgYIBgABNQAECgYICAAGAAAAAA==.',
Am='Amadayus:BAABNQAECn8nAAIHAAoKwyV0AgDfAwAHAAoKwyV0AgDfAwAAAA==.Ambellina:BAAANQAECgYICgAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anaye:BAAANQADCgIIAgABNQAECgcIHwADACcfAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8GAAMIAAYKCAlOHAAUAQAIAAQKwAtOHAAUAQAJAAIKUAYfCwBRAAA1AAQKf08ABAkACgreGusEAJwBAAgACQoyGmlXAFACAAkABwp+GesEAJwBAAoAAQrJGSkmAD8AAAAA.Archiball:BAAANQAECggICgABNQAECggIEQAGAAAAAA==.Arclock:BAAANQAECgYIDQAAAA==.Arconnai:BAABNQAECn9BAAILAAoKTB9OHwB4AgALAAoKTB9OHwB4AgAAAA==.Areilin:BAAANQAECgQIBgAAAA==.Areiotyrict:BAAANQAECgUIDwAAAA==.Arkaÿne:BAAANQADCgYIBgABNQAECgYIEwAGAAAAAA==.Arnøld:BAAANQAECgUIEAABNQAECgYICwAGAAAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.Arthorim:BAAANQAECggIBQABNQAECggIEQAGAAAAAA==.',
As='Asham:BAAANQAECgEIAQAAAA==.Ashinalani:BAAANQAECgEIAQAAAA==.Asiago:BAAANQAECgQIEwABNQAECgoKMQAMAMEdAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgYICAAAAA==.',
Av='Avvalethra:BAABNQAECn8bAAIHAAoK6g+QkQDmAQAHAAoK6g+QkQDmAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCgABNQAFFAYIFwANAG0ZAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAABNQAECn8aAAICAAgKngT+sQDjAAACAAgKngT+sQDjAAAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn80AAIOAAkKYBeeTgA9AgAOAAkKYBeeTgA9AgAAAA==.Barkimadog:BAAANQAECgMIBAAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECggIDwAAAA==.',
Be='Bearfox:BAAANQAECgEIAQAAAA==.Bearlinwall:BAAANQAECgEIAgAAAA==.Bearmaster:BAABNQAECn8ZAAIHAAYK5QKbBgH5AAAHAAYK5QKbBgH5AAAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECggIDQAAAA==.Bews:BAAANQADCgQIBAAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAABNQAECn8cAAICAAkKURtmbwCfAgACAAkKURtmbwCfAgAAAA==.Billybones:BAAANQAECgQIEwAAAA==.Bimbobaby:BAAANQAECgQICgAAAA==.',
Bl='Blackholes:BAABNQAECn8VAAIIAAUKxAgX5wD7AAAIAAUKxAgX5wD7AAAAAA==.Blackwÿn:BAAANQADCggIFgABNQAECgYIEwAGAAAAAA==.Bladeblade:BAABNQAECn8fAAMFAAoK7B+FAwBKAgAFAAoK7B+FAwBKAgAEAAcKlBC0QgCsAQABNQAFFAMICAALADcQAA==.Bladedozzer:BAAANQAECgQICwAAAA==.Blindinglite:BAABNQAECn81AAIEAAoKSBxWEwADAwAEAAoKSBxWEwADAwAAAA==.Bloodhaze:BAABNQAECn8dAAIEAAoKnCOwGADVAgAEAAoKnCOwGADVAgAAAA==.Bloodline:BAAANQAECggIBQAAAA==.Blorp:BAAANQAECgUIBgABNQAECgoKQgAHAFskAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggIHgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.Boriquagypsy:BAAANQADCgUIBQAAAA==.Bownystark:BAAANQAECgQIBAAAAA==.',
Br='Brchm:BAAANQAECgQIEgAAAA==.Brickly:BAABNQAECn8ZAAMEAAkKqB2uHgCkAgAEAAgKqB2uHgCkAgAFAAEKAAAELgBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgoKMQAMAMEdAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgUIDwAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.Burntcring:BAAANQAECgEIAQAAAA==.',
Bx='Bxxberry:BAAANQAECgUICAAAAA==.',
By='Byeon:BAAANQAECgQIBAAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgoKMwABAPocAA==.',
['Bú']='Búkki:BAAANQADCgYIHgAAAA==.',
['Bü']='Bükkì:BAAANQADCggIGQAAAA==.Bükkï:BAAANQADCgcIEgAAAA==.',
Ca='Caboodles:BAABNQAECn8jAAMKAAcK1gdgNADyAAAKAAYKugZgNADyAAAIAAcKSwb/7wDqAAAAAA==.Cachamama:BAAANQAECgIIAwAAAA==.Camishami:BAACNQAFFH8FAAIBAAMKLh3rDgDxAAABAAMKLh3rDgDxAAA1AAQKfxgAAwEACQomFnJZAAQCAAEACQomFnJZAAQCAA4AAgrLCrPAADgAAAAA.Candyhandz:BAAANQAECgIIBgABNQAECgcIHwADACcfAA==.Capriestsün:BAAANQAECgQICQABNQAECgoKLwAHAFYYAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgoKMwABAPocAA==.Catharsis:BAAANQAECgQIBgAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn83AAIDAAkKkx3lCgAuAwADAAkKkx3lCgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQAECgQIBAAAAA==.Cheesus:BAABNQAECn8xAAIMAAoKwR36FwAIAwAMAAoKwR36FwAIAwAAAA==.Chicharon:BAABNQAECn8uAAICAAkKvA3RVwClAQACAAkKvA3RVwClAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAABNQAECn8aAAIPAAoKdxG5EgBZAQAPAAoKdxG5EgBZAQAAAA==.Chlona:BAAANQAECgEIAQAAAA==.Chokolock:BAABNQAECn8hAAIIAAoKzBPzKgAGAgAIAAoKzBPzKgAGAgAAAA==.Chunggus:BAAANQAECgEIAQAAAA==.Churva:BAABNQAECn8jAAMBAAoKbweGoQAzAQABAAkKrgWGoQAzAQAOAAYKVgZUvAAaAQAAAA==.',
Ci='Circumsize:BAAANQAECgEIAgAAAA==.',
Cl='Cleggane:BAAANQABCgcIBwAAAA==.',
Co='Coko:BAAANQAECgUIBgABNQAECgoKLgAHAEggAA==.Condemned:BAAANQADCgYIDAAAAA==.Cooch:BAAANQAECgUICQAAAA==.Cosecantes:BAABNQAECn8gAAMQAAYKjR3YDQDRAQAQAAYKjR3YDQDRAQACAAIKDQNBtAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgoKLwAHAFYYAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYICQAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAABNQAECn8jAAIRAAkKfxxOFwCKAgARAAkKfxxOFwCKAgAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crul:BAAANQAECgEIAQAAAA==.Crusäderaura:BAABNQAECn8WAAQRAAgKayFvSQBCAgARAAcKqyJvSQBCAgASAAIKAADXqwExAAATAAEKAADldwAlAAAAAA==.Cryptìc:BAACNQAFFH8JAAIUAAQKxhPgCgBFAQAUAAQKxhPgCgBFAQA1AAQKfycAAhQACgppIK0QAO4CABQACgppIK0QAO4CAAE1AAUUBggHABAApg0A.',
Da='Dabbia:BAABNQAECn8dAAQJAAkKUhx9CgDQAQAJAAYKJR59CgDQAQAIAAQKfB5czQAvAQAKAAQKMxeTMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICgAAAA==.Dahunte:BAAANQAECgYICQAAAA==.Damara:BAAANQADCgYIBgAAAA==.Damented:BAAANQADCggIEQABNQAECgoKMwABAPocAA==.Dandaris:BAAANQAECgEIAgAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadcheck:BAAANQAECgEIAgAAAA==.Deadvocate:BAAANQAECgQICwAAAA==.Deathballz:BAABNQAECn8uAAMVAAkK/BRsLgAuAgAVAAkK/BRsLgAuAgAWAAIKxwa2zABTAAABNQAECgoKIQAIAMwTAA==.Deathgripftw:BAAANQAECgEIBQAAAA==.Deathtreader:BAAANQADCgMIBQAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAAANQAECgYIEQAAAA==.Delthrus:BAAANQAECgQICwABNQAECgoKMgAXAKQRAA==.Demonarc:BAABNQAECn8hAAIDAAoK1hYSHAB1AgADAAoK1hYSHAB1AgAAAA==.Detreset:BAABNQAECn8ZAAIYAAkKaRhLEQCWAgAYAAkKaRhLEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECn8dAAMCAAoKXgiMAAGNAQACAAoKzweMAAGNAQAZAAEKGQuTBgA5AAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgkJGgAVAIQKAA==.Dinsum:BAAANQADCggIFAAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgoKPwAaAIYkAA==.Disorder:BAAANQAECgIIAwAAAA==.Dixeenormis:BAAANQAECgEIAQAAAA==.Dixonbuttsz:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgoKPwAaAIYkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgAGAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQAECgMIBAAAAA==.Dragtiago:BAAANQADCgcIEgAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8VAAIbAAgK2BfpIgA2AgAbAAgK2BfpIgA2AgAAAA==.Drezbi:BAAANQAECgEIAwAAAA==.Droodmon:BAAANQADCgIIAgAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8vAAISAAoKFQ4MmQDxAQASAAoKFQ4MmQDxAQAAAA==.Durzaka:BAABNQAECn8WAAIBAAcKwA/mTgBaAQABAAcKwA/mTgBaAQAAAA==.Durzu:BAAANQAECgQIEAAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
['Dá']='Dáeves:BAAANQAECggICAABNQAFFAYICwAUAOAXAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn89AAMcAAoKaBGsFABWAQAcAAoKIxGsFABWAQAaAAkKmgq+SAA7AQAAAA==.',
Eg='Eggy:BAAANQAECggIBwAAAA==.Egholom:BAABNQAECn8zAAIEAAoK+hEiHAC6AQAEAAoK+hEiHAC6AQAAAA==.',
Ek='Eks:BAAANQADCggIFAAAAA==.',
El='Electrcfrost:BAABNQAECn84AAIOAAoKNR1NDwCfAgAOAAoKNR1NDwCfAgABNQAECgoKPQAMAHQfAA==.Elkanàh:BAABNQAECn8vAAMSAAoKCBr8agBcAgASAAoKCBr8agBcAgARAAgKNRx5TQA0AgABNQAFFAcIEAAdAOoTAA==.Elorene:BAABNQAECn8dAAMZAAgK0QfVAwCVAQAZAAgKowfVAwCVAQACAAYK/wHChwG2AAAAAA==.Elunara:BAABNQAECn8XAAIeAAgKZRhmGgDUAQAeAAgKZRhmGgDUAQABNQAFFAYIBgAIAAgJAA==.Elyysian:BAACNQAFFH8LAAIUAAYK4BeoCACCAQAUAAYK4BeoCACCAQA1AAQKfz0AAxQACgr6I6AEAI4DABQACgr6I6AEAI4DAB0AAwqWA43lAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgYICAAGAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8MAAICAAYK7hycGQCtAQACAAYK7hycGQCtAQA1AAQKfyUAAwIACgqrI5E6ABIDAAIACgqrI5E6ABIDABAAAQosF+c9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8fAAIBAAcK7RoSOAC7AQABAAcK7RoSOAC7AQABNQAECgoKNAAeAJkkAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgUIBgABNQAECgoKNAAeAJkkAA==.',
Fa='Fadam:BAABNQAECn8sAAICAAoKaw7wQgDrAQACAAoKaw7wQgDrAQAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggIDwAAAA==.Fanttic:BAAANQADCgQIBAAAAA==.Fatigue:BAAANQAECgEIAQAAAA==.Fatpo:BAABNQAECn8XAAQdAAgK2hxgagDfAQAdAAcK3xtgagDfAQAUAAQKkR4GOwBQAQAfAAEKBSAwIgBUAAABNQAECgkJGQAEAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn8yAAICAAoKJB8iSwDPAQACAAoKJB8iSwDPAQAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8RAAIOAAYK4xKDBQA0AQAOAAYK4xKDBQA0AQA1AAQKfyMAAg4ACgr6HmgPAJ4CAA4ACgr6HmgPAJ4CAAAA.Floriyana:BAAANQAECgIICwAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgoKRgACAIcgAA==.Fourpriest:BAAANQAECgQICQAAAA==.Foô:BAABNQAECn8yAAMcAAoKIB/XDgALAwAcAAoKIB/XDgALAwAaAAUKHBLNMgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgIICgAAAA==.Frostpaw:BAAANQAECgEIAQAAAA==.',
Fu='Fudead:BAAANQAECgMIBQAAAA==.Fugarra:BAAANQAECggIEAABNQAECggIEQAGAAAAAA==.Furdinand:BAAANQADCgUIBQAAAA==.Furyrosa:BAAANQAECgEIAQAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAAGAAAAAA==.',
Fy='Fyah:BAABNQAECn8wAAISAAoK/RwjJgBrAgASAAoK/RwjJgBrAgABNQAFFAcIFwAHAGkWAA==.Fyaza:BAAANQADCggICQABNQAFFAcIFwAHAGkWAA==.',
Ga='Gaga:BAAANQAECgEIAQAAAA==.Gargamels:BAAANQAECggIEQAAAA==.Garou:BAAANQAECgQIBwAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICgAAAA==.Gerttie:BAABNQAECn8jAAMgAAgK5RG6GgCTAQAgAAgK5RG6GgCTAQAMAAEKAAAlzwAOAAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8gAAIYAAgK2hUkAgBpAgAYAAgK2hUkAgBpAgA1AAQKfyUAAhgACgr6H8ENAMsCABgACgr6H8ENAMsCAAAA.',
Gl='Gloryho:BAAANQAECgEIAQAAAA==.',
Go='Gobsquadp:BAABNQAECn8UAAIdAAgKMxBgfQDgAAAdAAgKMxBgfQDgAAABNQAECgoKNAAeAJkkAA==.Gonzzo:BAAANQABCgIIAgAAAA==.',
Gr='Grassmoker:BAAANQAECgUIDgAAAA==.Grek:BAAANQAECgcIEAABNQAECgkJJwAhAFMeAA==.Grievex:BAABNQAECn80AAISAAoKngnmagCAAQASAAoKngnmagCAAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQAECgEIAQAAAA==.Grumpel:BAAANQAECgEIAgAAAA==.',
Gu='Guzzlr:BAAANQAECgcIDwAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAbAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Haring:BAAANQAECggICQAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAACNQAFFH8FAAIdAAIKPhufGwCdAAAdAAIKPhufGwCdAAA1AAQKfzkAAh0ACgqaHOkYABIDAB0ACgqaHOkYABIDAAAA.Hedumnotner:BAAANQAECggICAAAAA==.Heelz:BAAANQAECgEIAQAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAYIDQASACkOAA==.Hemostasis:BAACNQAFFH8NAAISAAYKKQ60BwDSAQASAAYKKQ60BwDSAQA1AAQKfzoABBIACgpjIikXAGgDABIACgpjIikXAGgDABEAAgrmD3AXAUYAABMAAQodFi5tADcAAAAA.Herjä:BAAANQAECgQIDgAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQAGAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.Hezalon:BAAANQAECgEIAQAAAA==.',
Ho='Homeslice:BAABNQAECn8fAAQKAAgKhBJ8CADmAAAJAAQKuRVgFAAEAQAKAAUKohR8CADmAAAIAAUKAAfRCAG6AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQAECgEIAQAAAA==.Huun:BAABNQAECn80AAIiAAoKKR9PAgAjAwAiAAoKKR9PAgAjAwAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQAECgEIAgAAAA==.',
['Hó']='Hózaÿ:BAAANQADCgEIAQAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn9JAAMIAAoKCAq1TgB4AQAIAAoKCAq1TgB4AQAKAAMKtAQIVACCAAAAAA==.',
Ib='Iblow:BAAANQADCgEIAQAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Il='Illydan:BAAANQADCgMIAwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQAECgEIAgAAAA==.',
Ir='Irrenadro:BAABNQAECn9FAAISAAoKng7skwD8AQASAAoKng7skwD8AQAAAA==.',
Is='Islandhunter:BAAANQAECgIIAgAAAA==.',
Iy='Iyahna:BAAANQAECgQIBwAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgYIDgAAAA==.',
Je='Jeage:BAAANQAECgQIBgABNQAECgkJIAAOAJ4iAA==.Jera:BAAANQADCgIIAwAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgUICQABNQAECgkJHQAPAGkiAA==.Jimmybones:BAAANQAECgEIAQAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn8qAAIHAAgKYxlnawA8AgAHAAgKYxlnawA8AgAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.Juicyreds:BAAANQAECgEIAQAAAA==.Juzze:BAAANQAECgEIAQAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAkJJAASAJwbAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAYIBgAIAAgJAA==.',
Ke='Keetra:BAACNQAFFH8YAAIHAAUKLRljDACLAQAHAAUKLRljDACLAQA1AAQKfyQAAgcACgrQH8UtAOQCAAcACgrQH8UtAOQCAAAA.Keiriline:BAABNQAECn8hAAMVAAcKVRDHTQB/AQAVAAcKVRDHTQB/AQAjAAEKAACL0AAtAAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQAECgQIBAAAAA==.',
Kl='Klix:BAAANQADCgcICwABNQAECgcIHwADACcfAA==.',
Kn='Knight:BAABNQAECn8bAAMCAAkKnB0RcgCaAgACAAgKnB0RcgCaAgAZAAIKzAjaCQBoAAAAAA==.Knuggz:BAABNQAECn8VAAILAAcKrxotTQCdAQALAAcKrxotTQCdAQAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.Koshmare:BAAANQAECgEIAQAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAgAAAA==.',
Ku='Kubluk:BAAANQAECgMIAwAAAA==.Kumbustinher:BAAANQAECgMIAwAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAMIDAAdAKYmAA==.Kylepala:BAAANQAECgYIBgABNQAFFAMIDAAdAKYmAA==.Kylepriest:BAACNQAFFH8MAAIdAAMKpiYODQBZAQAdAAMKpiYODQBZAQA1AAQKfzwAAx0ACgqIJssBANADAB0ACgqIJssBANADAB8AAgopI04XALwAAAAA.Kyntamun:BAAANQADCgcIDQABNQAECgQIBAAGAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgcIHwADACcfAA==.Lambeáu:BAABNQAECn8bAAIHAAgK1xtqOgD3AQAHAAgK1xtqOgD3AQAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAABNQAECn8VAAQNAAcKZwodEwChAAANAAYKwwQdEwChAAAhAAMKXwSqHQB2AAAYAAUKbwUkKQBSAAAAAA==.Lamdabow:BAAANQAECgMIBAAAAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQAECgEIAgAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDwAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgoKMAAEAMkeAA==.Larzoh:BAABNQAECn8wAAMEAAoKyR5JDABIAwAEAAoKyR5JDABIAwADAAMKJQbEWQCdAAAAAA==.Lateesha:BAAANQAECgUIDAAAAA==.Lavac:BAAANQAECgIIAgAAAA==.',
Le='Lethargy:BAAANQADCgYICwAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgUIEQAAAA==.Lightguard:BAABNQAECn8nAAISAAgKrRd0iwAPAgASAAgKrRd0iwAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8hAAIHAAgKkQTu1gBSAQAHAAgKkQTu1gBSAQAAAA==.Lilwiz:BAAANQAECgQIDAAAAA==.Linalala:BAABNQAECn+uAAQgAAkK4ibaAAAHBAAgAAkK4ibaAAAHBAAkAAcKqRHhFACtAQAMAAIKLAwbmQB1AAAAAA==.Linnxp:BAAANQAECgQIBQABNQAECgYICQAGAAAAAA==.Linnxs:BAAANQAECgYICQAAAA==.Linnxvx:BAAANQAECgEIBQABNQAECgYICQAGAAAAAA==.Lishp:BAAANQAECgEIBQAAAA==.Literacola:BAABNQAECn8fAAICAAoKNA2ERwDcAQACAAoKNA2ERwDcAQAAAA==.',
Lo='Lorino:BAAANQAECgEIBAAAAA==.Lothaire:BAAANQAECgEIAQAAAA==.',
Lu='Lubaduba:BAAANQAECgEIAQAAAA==.Lugeya:BAAANQAECgUIDAAAAA==.Lugeyamnk:BAAANQAECgcIEQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgMIBgAAAA==.Lustnbeiber:BAABNQAECn8sAAQOAAkKwhXRQgBqAgAOAAkKwhXRQgBqAgABAAYK4AtbrgATAQAPAAUKWAQTIQCSAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgcIEgAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggIEAABNQAECgkJKQATAB4hAA==.Lynchà:BAABNQAECn8pAAITAAkKHiG8BwAmAwATAAkKHiG8BwAmAwAAAA==.Lynchä:BAAANQAECgYIBgABNQAECgkJKQATAB4hAA==.',
Ma='Maakun:BAABNQAECn82AAIdAAkKfBcdPgByAgAdAAkKfBcdPgByAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIDQAAAA==.Mahoragga:BAAANQAECgMIBAAAAA==.Mahzad:BAABNQAECn85AAMBAAoKECH1FgAaAwABAAoKECH1FgAaAwAOAAYKChzCdgC9AQAAAA==.Malchezaar:BAABNQAECn8ZAAIIAAgK9gyDbAAlAQAIAAgK9gyDbAAlAQAAAA==.Malfrun:BAABNQAECn8yAAIXAAoKpBEoCQC5AQAXAAoKpBEoCQC5AQAAAA==.Malzahar:BAAANQAECgEIAwAAAA==.Marinnite:BAAANQADCgYIBgAAAA==.Markzugrberg:BAAANQADCgMIAwAAAA==.Marox:BAABNQAECn83AAICAAoK+xqNHwB8AgACAAoK+xqNHwB8AgAAAA==.Marrøwgar:BAABNQAECn8dAAMWAAkKBhy1DwAkAgAWAAkKBhy1DwAkAgAjAAEKAABhxwA6AAAAAA==.Mathrim:BAECNQAFFH8OAAQIAAUKtxwXFQCnAAAIAAMKtyMXFQCnAAAKAAEKuQ7ZDABOAAAJAAEKAAAgDwAAAAA1AAQKfzoAAwgACgo+JQAEALgDAAgACgo+JQAEALgDAAoAAgqOFRJUAIIAAAAA.Matooka:BAABNQAECn8aAAIHAAcKjwQG1gBUAQAHAAcKjwQG1gBUAQAAAA==.Maynji:BAAANQADCggICAAAAA==.Mazima:BAAANQAECgQIDAAAAA==.',
Mc='Mcthugger:BAAANQAECgEIAQABNQAECgoKKQASAMQXAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Mikun:BAAANQAECgMIAwAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQAECgEIAQAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAABNQAECn8UAAMWAAYKAhxHUQDOAQAWAAYKAhxHUQDOAQAVAAUKhw19UwDKAAAAAA==.Mommÿ:BAACNQAFFH8KAAIdAAMKtBQyFQDdAAAdAAMKtBQyFQDdAAA1AAQKfzkAAx0ACgqIHUQoAMkCAB0ACgqIHUQoAMkCAB8ABgpIDL4QAB0BAAAA.Moneymage:BAAANQAECgQIBQAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8xAAIeAAoKgRFNFwD4AQAeAAoKgRFNFwD4AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgoKLgAHAEggAA==.Moolificent:BAABNQAECn8aAAIVAAkKhAq8UQBqAQAVAAkKhAq8UQBqAQAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAABNQAECn8fAAIgAAoK0RvNFwCCAgAgAAoK0RvNFwCCAgAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECgkJNgAcANYVAA==.Muddgore:BAAANQADCggIDgABNQAECgkJNgAcANYVAA==.Muddthir:BAAANQADCgQIBAABNQAECgkJNgAcANYVAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgoKQgAHAFskAA==.Mustardrogue:BAAANQAECgUIBQAAAA==.',
My='Myzarei:BAAANQAECgUIDQAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn82AAMcAAkK1hWKJwBSAgAcAAgKXheKJwBSAgAaAAcK+xC6SwAuAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgEIAgAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.Nezoomi:BAAANQAECgEIAQAAAA==.',
Ni='Nirath:BAABNQAECn84AAICAAoK+w+7PwD2AQACAAoK+w+7PwD2AQAAAA==.Nisia:BAABNQAECn8UAAMIAAkKDxgYOQCpAgAIAAkKDxgYOQCpAgAKAAEKiwiSfAAwAAABNQAFFAMICAALADcQAA==.Nito:BAABNQAECn8lAAIVAAkKGBEMNAANAgAVAAkKGBEMNAANAgAAAA==.',
No='Nobainer:BAAANQADCgMIAwAAAA==.Nohkano:BAABNQAECn9CAAMlAAoKPiZfAADxAwAlAAoKPiZfAADxAwAmAAcK4gtCHABLAQAAAA==.Nokt:BAAANQAECggIEgAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgcIDgAAAA==.Noveerra:BAAANQADCgcIDwABNQAECgQIBAAGAAAAAA==.',
Nu='Numbuh:BAAANQAECgQIDAAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakremi:BAAANQADCgMIAwAAAA==.Oakrogue:BAAANQAECgIICAAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ortillious:BAAANQAECgQICAABNQAECgcIEgAGAAAAAA==.',
Ov='Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggIDAAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgcIDQABNQAFFAYIDQASACkOAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcIDAAAAA==.Pantheons:BAAANQAECgQIEwAAAA==.Parsi:BAABNQAECn8lAAMFAAkKCxywAwA/AgAFAAkKCxywAwA/AgADAAIKmQduYQBnAAAAAA==.Pattysmyth:BAAANQAECgUIEgABNQADCggIEgAGAAAAAA==.Paulinemaroi:BAABNQAECn8UAAICAAoKnx5RlwBSAgACAAoKnx5RlwBSAgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgoKFAACAJ8eAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQAECgEIAgABNQAECgcIHwADACcfAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Phaell:BAAANQAECgEIAwAAAA==.Philip:BAAANQAECgcIDwAAAA==.Phäel:BAAANQAECgEIAQAAAA==.Phäell:BAAANQAECgEIBAAAAA==.',
Pl='Playstayshon:BAAANQAECgEIAQAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQAEAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDgAGAAAAAA==.Poppafury:BAAANQAECgEIAQAAAA==.Poppapulls:BAAANQAECggICAAAAA==.Pottyy:BAAANQABCgIIBAAAAA==.Poubear:BAAANQAECggICQABNQAECggIEQAGAAAAAA==.Pougadina:BAAANQAECgIIAwABNQAECgkJGQAEAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcIBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgYICwABNQAECgoKIgAUAIUdAA==.',
['Pä']='Pändora:BAAANQAECgYIBwAAAA==.',
Ra='Rabite:BAABNQAECn80AAIeAAoKmSRoBABkAwAeAAoKmSRoBABkAwAAAA==.Radiance:BAEANQAECgYIDAABNQAFFAYICwAbAJkeAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBgAAAA==.Randyvivaldi:BAAANQAECgEIBAAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rathasas:BAABNQAECn85AAMYAAkKgB0kCQAnAgAYAAkKgB0kCQAnAgANAAIK5BfbMACPAAAAAA==.Ratnob:BAABNQAECn8hAAIWAAoK6hQyOQBAAgAWAAoK6hQyOQBAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMhAAkKUx62AwDqAgAhAAkKUx62AwDqAgANAAEKfwaTQAAqAAAAAA==.Relda:BAAANQAECgUIDgABNQAECgkJHQAPAGkiAA==.Remye:BAABNQAECn8tAAIRAAoKVhlsPgBqAgARAAoKVhlsPgBqAgAAAA==.Rennshi:BAABNQAECn8dAAIEAAkK8CVWCAB2AwAEAAkK8CVWCAB2AwAAAA==.Reportedhunt:BAABNQAECn8vAAIHAAoKVhhrQACpAgAHAAoKVhhrQACpAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgQIBgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimmy:BAAANQAECgEIAgABNQADCgEIAQAGAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8hAAMDAAUKJgX0NQB/AAADAAUKJgX0NQB/AAAEAAIKfgRkiQBSAAAAAA==.Roldaza:BAAANQAECgUIDQAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn9CAAMHAAoKWyRpFwA8AwAHAAoKWyRpFwA8AwAbAAYKTgy7SwAGAQAAAA==.',
Ru='Rulep:BAAANQAECggIBQAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Ryotwar:BAAANQAECgUIBgAAAA==.Rythmatic:BAABNQAECn8/AAMaAAoKhiSpCAD+AgAaAAoKPiSpCAD+AgAcAAcKoyEKIACBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQAECgEIAgABNQADCgEIAQAGAAAAAA==.Sakieri:BAABNQAECn8tAAMUAAoKcRgXGgB8AgAUAAoKcRgXGgB8AgAdAAIKLQecxgA3AAAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQAECgEIAgAAAA==.Sangan:BAABNQAECn8+AAICAAoKfB2yFwCoAgACAAoKfB2yFwCoAgAAAA==.Sangen:BAAANQAECgEIAQAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwAGAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Segolas:BAAANQADCgEIAQAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8XAAINAAYKbRlZAQAOAQANAAYKbRlZAQAOAQA1AAQKfygAAg0ACgoZJKAFADYDAA0ACgoZJKAFADYDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgYIEQAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shaming:BAAANQAECgEIAQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQAECgEIAQAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgYICAAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8qAAMIAAoK8h+1EwA+AwAIAAoK8h+1EwA+AwAKAAIK8RvvTQCVAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8iAAICAAgKjgqU/QCSAQACAAgKjgqU/QCSAQAAAA==.',
Sk='Skeezer:BAAANQAECgEIAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAhAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQAECggICgAAAA==.',
Sp='Spectrum:BAAANQADCgQIBAAAAA==.',
St='Starfrost:BAAANQAECgEIAQAAAA==.Stingerai:BAABNQAECn8uAAIHAAoKSCDeJwD4AgAHAAoKSCDeJwD4AgAAAA==.Stingerjb:BAAANQAECgQIBgABNQAECgoKLgAHAEggAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAABNQAECn8YAAIIAAoK/BYXVABZAgAIAAoK/BYXVABZAgAAAA==.Sucemabite:BAAANQADCgEIAQAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYICAABNQAECgkJFgASAAAhAA==.',
Sy='Syl:BAAANQAECgUIDgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgkJKgAmAKkdAA==.Teemonk:BAABNQAECn8qAAImAAkKqR2kEwC7AgAmAAkKqR2kEwC7AgAAAA==.Teepal:BAAANQAECgEIAQABNQAECgkJKgAmAKkdAA==.Teila:BAAANQAECgEIAQAAAA==.Teladrel:BAAANQAECggIBAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAABNQAECn8dAAIPAAcKgBQzFABEAQAPAAcKgBQzFABEAQAAAA==.Teribullduce:BAACNQAFFH8FAAIHAAQKdw76DADtAAAHAAQKdw76DADtAAA1AAQKfzQAAgcACgp/I1oLAPcCAAcACgp/I1oLAPcCAAAA.Terscheckii:BAAANQAECgEIAQAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thickyricky:BAABNQAECn8XAAMcAAkKwRe0MgASAgAcAAkKOBO0MgASAgAaAAMKcBp6YQDXAAABNQAECgkJHQAPAGkiAA==.Thingol:BAAANQABCgcIFQAAAA==.Thormor:BAAANQAECgQICgABNQAFFAgIIAAYANoVAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgQIDAABNQAECgoKKQASAMQXAA==.Thuggerjr:BAABNQAECn8pAAISAAoKxBdxaQBgAgASAAoKxBdxaQBgAgAAAA==.Thundersurge:BAAANQAECgUIBgABNQAECgoKLwAHAFYYAA==.Thænes:BAAANQAECgYIEwAAAA==.Thûr:BAAANQAECgMIAwABNQAECgoKMwABAPocAA==.',
Ti='Tigg:BAABNQAECn8mAAIOAAgKNARZ4wDQAAAOAAgKNARZ4wDQAAAAAA==.Tildin:BAAANQAECgEIAQAAAA==.Tinkerdinker:BAAANQAECgEIBAAAAA==.Tipsout:BAACNQAFFH8IAAILAAMKNxAkEQDYAAALAAMKNxAkEQDYAAA1AAQKfz8AAwsACgoYIyEjACwDAAsACgoYIyEjACwDABcABgrWExIiADoBAAAA.',
Tn='Tnemith:BAAANQAECgEIAQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgkJKgAmAKkdAA==.Torastrasza:BAAANQAFFAIIAgAAAA==.Totemm:BAABNQAECn8UAAIBAAkKGh9pMACgAgABAAkKGh9pMACgAgAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn8zAAMBAAoK+hyYQABeAgABAAoK+hyYQABeAgAOAAUKQhGTsgAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgEIAQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAABNQAECn8XAAIRAAgK4xrMKQAGAgARAAgK4xrMKQAGAgAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIBQAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Un='Unfocused:BAABNQAECn89AAIMAAoKdB8RHgDZAgAMAAoKdB8RHgDZAgAAAA==.Unholybelac:BAAANQADCgYIDQAAAA==.',
Ur='Urgmathron:BAABNQAECn8iAAITAAcKixnjJAC5AQATAAcKixnjJAC5AQAAAA==.',
Va='Vakhara:BAABNQAECn8fAAIDAAcKJx8PEwC6AQADAAcKJx8PEwC6AQAAAA==.Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIBAABNQAFFAYICwAUAOAXAA==.Vansthir:BAAANQAECggIDgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIDgABNQAFFAYIEgALAHsUAA==.Vaush:BAABNQAECn8ZAAMWAAcKSgPlmgDJAAAWAAYKogPlmgDJAAAVAAcKGAIfZwCJAAAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQAECgIIAgAAAA==.',
Vi='Victorix:BAAANQADCgUIBQAAAA==.Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8eAAIhAAYK2w1/EQAdAQAhAAYK2w1/EQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBQAGAAAAAA==.Volcanoez:BAAANQAECgIIAwAAAA==.Vonrx:BAAANQAECgEIBgAAAA==.',
Vr='Vrezor:BAAANQAECggIDAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.Vulpala:BAAANQAECgUIBQAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgoKPwAMACQkAA==.',
Wa='Wardian:BAAANQAECgQIBwABNQAECgoKKQASAOESAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgoKLwAHAFYYAA==.Warnath:BAAANQAECgUIBQAAAA==.Warthyr:BAAANQADCgIIAgAAAA==.',
We='Welfairline:BAAANQADCggIHgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAFFAQIBQAHAHcOAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8fAAImAAoKfR1UDgD6AgAmAAoKfR1UDgD6AgAAAA==.Yassera:BAAANQAECgQIDgAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8jAAILAAkKtg7NngDPAQALAAkKtg7NngDPAQAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQAECgEIAQAAAA==.Zapman:BAAANQAECgEIAgAAAA==.Zarik:BAABNQAECn8bAAIIAAcKWwm9ewD/AAAIAAcKWwm9ewD/AAAAAA==.',
Ze='Zeddoc:BAEANQAECgEIBQAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIBQAGAAAAAA==.Zenfist:BAAANQADCgUIBQAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAABNQAECn8YAAISAAcKAg5RywCFAQASAAcKAg5RywCFAQAAAA==.Zenotath:BAAANQABCgMIAgAAAA==.',
Zo='Zodier:BAAANQAECggICQABNQAFFAYIDAAQAG8XAA==.Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQAECgEIBAAAAA==.',
Zu='Zulugangrene:BAABNQAECn8oAAISAAkKwwuaggBMAQASAAkKwwuaggBMAQAAAA==.Zun:BAABNQAECn8dAAIQAAgKlAr6CQBxAQAQAAgKlAr6CQBxAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgYIEwAGAAAAAA==.',
['Çh']='Çhunchunmaru:BAAANQAECgIIAwABNQAECgoKLgAHAEggAA==.',
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
