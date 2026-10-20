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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Druid-Balance','Evoker-Devastation','Mage-Arcane','Shaman-Elemental','Mage-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Hunter-Marksmanship','Rogue-Assassination','Priest-Holy','Mage-Fire','Druid-Guardian','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','DeathKnight-Blood','Druid-Feral','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aadrisedh:BAAANQAECgMIBAAAAA==.Aaeryn:BAAANQAECgEIAgAAAA==.Aaliyshaa:BAAANQAECgYIDQAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAABNQAECn8sAAIBAAoKZhRvHAB7AQABAAoKZhRvHAB7AQAAAA==.',
Ab='Abrakadabruh:BAAANQAECgUIDgAAAA==.Abyssal:BAABNQAECn8cAAQCAAoKwhjrCwBZAQADAAcKuw4SRgCWAQACAAcKIhrrCwBZAQAEAAUKbBFjIADDAAAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.Aellwyn:BAAANQAECgMIBwABNQAECggIDwAFAAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgcICgAAAA==.Ainna:BAAANQAECgEIAQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQAECgEIAQAAAA==.Alystair:BAAANQADCgYIBgABNQAECgUIBwAFAAAAAA==.',
Am='Amadayus:BAABNQAECn8lAAIGAAoKsCV0AgDfAwAGAAoKsCV0AgDfAwAAAA==.Ambellina:BAAANQAECgYICgAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anaye:BAAANQADCgIIAgABNQAECgcIGAACACAeAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8FAAMHAAUKkQlOHAAUAQAHAAQKwAtOHAAUAQAIAAEKNAUfCwBRAAA1AAQKf0UABAgACgpyGRkFAPUAAAcACQpmGWlXAFACAAgABgrCFxkFAPUAAAkAAQrJGRMTAEYAAAAA.Archiball:BAAANQAECggICQABNQAECggIDwAFAAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECn83AAIKAAoKKB6QPADVAgAKAAoKKB6QPADVAgAAAA==.Areilin:BAAANQAECgQIBAAAAA==.Areiotyrict:BAAANQAECgUICgAAAA==.Arkaÿne:BAAANQADCgYIBgABNQAECgYIEwAFAAAAAA==.Arnøld:BAAANQAECgUICQAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.Arthorim:BAAANQAECggIAQABNQAECggIDwAFAAAAAA==.',
As='Asham:BAAANQADCgYIGQAAAA==.Asiago:BAAANQAECgQIEwABNQAECgoKKAALAJwbAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgUIBwAAAA==.',
Av='Avvalethra:BAABNQAECn8ZAAIGAAgKThKQkQDmAQAGAAgKThKQkQDmAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCgABNQAFFAYIEgAMAIgWAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAABNQAECn8VAAINAAgKcgSvkgCiAAANAAgKcgSvkgCiAAAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn8uAAIOAAkKSBeHFQBxAQAOAAkKSBeHFQBxAQAAAA==.Barkimadog:BAAANQAECgMIBAAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgcIDwAAAA==.',
Be='Bearfox:BAAANQAECgEIAQAAAA==.Bearlinwall:BAAANQAECgEIAQAAAA==.Bearmaster:BAABNQAECn8ZAAIGAAYK5QKbBgH5AAAGAAYK5QKbBgH5AAAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECggIDQAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAABNQAECn8XAAINAAkKURtmbwCfAgANAAkKURtmbwCfAgAAAA==.Billybones:BAAANQAECgQIEQAAAA==.Bimbobaby:BAAANQAECgEIAQAAAA==.',
Bl='Blackholes:BAABNQAECn8UAAIHAAUKxAgX5wD7AAAHAAUKxAgX5wD7AAAAAA==.Blackwÿn:BAAANQADCggIFgABNQAECgYIEwAFAAAAAA==.Bladeblade:BAABNQAECn8aAAMEAAoKCR5zAwB7AQADAAcKlBC0QgCsAQAEAAoKCR5zAwB7AQABNQAFFAIIBQAKAB8TAA==.Bladedozzer:BAAANQAECgQICwAAAA==.Blindinglite:BAABNQAECn8vAAIDAAoKSBxWEwADAwADAAoKSBxWEwADAwAAAA==.Bloodhaze:BAABNQAECn8bAAIDAAkKtSOwGADVAgADAAkKtSOwGADVAgAAAA==.Bloodline:BAAANQAECggIBAAAAA==.Blorp:BAAANQAECgIIAgABNQAECgoKPgAGAFskAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggIHgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.Boriquagypsy:BAAANQADCgUIBQAAAA==.Bownystark:BAAANQAECgQIBAAAAA==.',
Br='Brchm:BAAANQAECgQIEgAAAA==.Brickly:BAABNQAECn8ZAAMDAAkKqB2uHgCkAgADAAgKqB2uHgCkAgAEAAEKAAAELgBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgoKKAALAJwbAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgUIDQAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.Burntcring:BAAANQAECgEIAQAAAA==.',
Bx='Bxxberry:BAAANQAECgUICAAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgoKLQABAHQbAA==.',
['Bú']='Búkki:BAAANQADCgYIHgAAAA==.',
['Bü']='Bükkì:BAAANQADCggIFgAAAA==.Bükkï:BAAANQADCgcIEgAAAA==.',
Ca='Caboodles:BAABNQAECn8fAAMJAAcK1gdgNADyAAAJAAYKugZgNADyAAAHAAcKSwa4cwCcAAAAAA==.Cachamama:BAAANQAECgIIAwAAAA==.Camishami:BAAANQAFFAEIAgAAAA==.Candyhandz:BAAANQAECgEIAgABNQAECgcIGAACACAeAA==.Capriestsün:BAAANQAECgQIBAABNQAECgoKKQAGADUXAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgoKLQABAHQbAA==.Catharsis:BAAANQAECgEIAQAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn8xAAICAAkKkx3lCgAuAwACAAkKkx3lCgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQAECgQIBAAAAA==.Cheesus:BAABNQAECn8oAAILAAoKnBv6FwAIAwALAAoKnBv6FwAIAwAAAA==.Chicharon:BAABNQAECn8lAAINAAgK1Q2ObQDhAAANAAgK1Q2ObQDhAAAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECggIEwAAAA==.Chlona:BAAANQABCgIIAgAAAA==.Chokolock:BAABNQAECn8YAAIHAAoKdhC8IABsAQAHAAoKdhC8IABsAQAAAA==.Chunggus:BAAANQAECgEIAQAAAA==.Churva:BAABNQAECn8jAAMBAAoKbweGoQAzAQABAAkKrgWGoQAzAQAOAAYKVgZUvAAaAQAAAA==.',
Ci='Circumsize:BAAANQAECgEIAgAAAA==.',
Cl='Cleggane:BAAANQABCgcIBwAAAA==.',
Co='Coko:BAAANQAECgUIBgABNQAECgoKKgAGAL4cAA==.Condemned:BAAANQADCgYIDAAAAA==.Cooch:BAAANQAECgQIBQAAAA==.Cosecantes:BAABNQAECn8fAAMPAAUKhCDYDQDRAQAPAAUKhCDYDQDRAQANAAIKDQNBtAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgoKKQAGADUXAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYICQAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAABNQAECn8bAAIQAAkKPxq+DAD7AQAQAAkKPxq+DAD7AQAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crusäderaura:BAABNQAECn8UAAQQAAcK8CBvSQBCAgAQAAYKUCJvSQBCAgARAAIKAADXqwExAAASAAEKAADldwAlAAAAAA==.Cryptìc:BAACNQAFFH8JAAITAAQKxhPgCgBFAQATAAQKxhPgCgBFAQA1AAQKfyYAAhMACgppIBgDAPABABMACgppIBgDAPABAAE1AAUUBggHAA8Apg0A.',
Da='Dabbia:BAABNQAECn8dAAQIAAkKUhx9CgDQAQAIAAYKJR59CgDQAQAHAAQKfB5czQAvAQAJAAQKMxeTMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICgAAAA==.Dahunte:BAAANQAECgQIBAAAAA==.Damara:BAAANQADCgYIBgAAAA==.Damented:BAAANQADCggIEQABNQAECgoKLQABAHQbAA==.Dandaris:BAAANQAECgEIAgAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICwAAAA==.Deathballz:BAABNQAECn8tAAMUAAkK/BRsLgAuAgAUAAkK/BRsLgAuAgAVAAIKxwa2zABTAAABNQAECgoKGAAHAHYQAA==.Deathgripftw:BAAANQAECgEIBQAAAA==.Deathtreader:BAAANQADCgIIAgAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAAANQAECgUICgAAAA==.Delthrus:BAAANQAECgQIBwABNQAECgkJLAAWAGIQAA==.Demonarc:BAABNQAECn8gAAICAAoK1hYSHAB1AgACAAoK1hYSHAB1AgAAAA==.Detreset:BAABNQAECn8ZAAIXAAkKaRhLEQCWAgAXAAkKaRhLEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECn8WAAINAAgKSAeMAAGNAQANAAgKSAeMAAGNAQAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgkJGgAUAIQKAA==.Dinsum:BAAANQADCggIDgAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgoKNgAYANojAA==.Disorder:BAAANQAECgEIAQAAAA==.Dixeenormis:BAAANQADCgYIBgAAAA==.Dixonbuttsz:BAAANQADCgcIDQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgoKNgAYANojAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgAFAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQADCgYIDQAAAA==.Dragtiago:BAAANQADCgcIEgAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8VAAIZAAgK2BfpIgA2AgAZAAgK2BfpIgA2AgAAAA==.Drezbi:BAAANQAECgEIAgAAAA==.Droodmon:BAAANQADCgIIAgAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8rAAIRAAoK3QwMmQDxAQARAAoK3QwMmQDxAQAAAA==.Durzaka:BAAANQAECgcICwAAAA==.Durzu:BAAANQAECgQIDwAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn81AAMaAAoKaBGvDABjAQAaAAoKIxGvDABjAQAYAAYKRAo9MgAqAQAAAA==.',
Eg='Eggy:BAAANQAECggIBwAAAA==.Egholom:BAABNQAECn8yAAIDAAkKYxRLBwDSAQADAAkKYxRLBwDSAQAAAA==.',
Ek='Eks:BAAANQADCggIDgAAAA==.',
El='Electrcfrost:BAABNQAECn8vAAIOAAoK3xf6EgCAAQAOAAoK3xf6EgCAAQABNQAECgoKOAALAEAdAA==.Elkanàh:BAABNQAECn8oAAMRAAoKbhn8agBcAgARAAgKihn8agBcAgAQAAgKAxt5TQA0AgABNQAFFAYIDwAbAAoVAA==.Elorene:BAABNQAECn8dAAMcAAgK0QfVAwCVAQAcAAgKowfVAwCVAQANAAYK/wHChwG2AAAAAA==.Elunara:BAABNQAECn8VAAIdAAgKZRhmGgDUAQAdAAgKZRhmGgDUAQABNQAFFAUIBQAHAJEJAA==.Elyysian:BAACNQAFFH8KAAITAAUKyRaoCACCAQATAAUKyRaoCACCAQA1AAQKfzQAAxMACgr2I2oAADoDABMACgr2I2oAADoDABsAAwqWA43lAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgUIBwAFAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8MAAINAAYK7hycGQCtAQANAAYK7hycGQCtAQA1AAQKfyUAAw0ACgqrI5E6ABIDAA0ACgqrI5E6ABIDAA8AAQosF+c9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8dAAIBAAcK7Rr0FQCmAQABAAcK7Rr0FQCmAQABNQAECgoKKgAdAJkkAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgUIBgABNQAECgoKKgAdAJkkAA==.',
Fa='Fadam:BAABNQAECn8eAAINAAgKOg0/SAArAQANAAgKOg0/SAArAQAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggICAAAAA==.Fanttic:BAAANQADCgQIBAAAAA==.Fatigue:BAAANQAECgEIAQAAAA==.Fatpo:BAABNQAECn8XAAQbAAgK2hxgagDfAQAbAAcK3xtgagDfAQATAAQKkR4GOwBQAQAeAAEKBSAwIgBUAAABNQAECgkJGQADAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn8vAAINAAoKNR7PDgDzAQANAAoKNR7PDgDzAQAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8QAAIOAAUKWxT9BQDzAAAOAAUKWxT9BQDzAAA1AAQKfxoAAg4ACgpPFcJIAFQCAA4ACgpPFcJIAFQCAAAA.Floriyana:BAAANQAECgMICAAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgoKPQANAIcgAA==.Fourpriest:BAAANQAECgIIBQAAAA==.Foô:BAABNQAECn8sAAMaAAkKbx3XDgALAwAaAAkKbx3XDgALAwAYAAUKHBLNMgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgIICQAAAA==.Frostpaw:BAAANQAECgEIAQAAAA==.',
Fu='Fudead:BAAANQAECgMIBQAAAA==.Fugarra:BAAANQAECggIDwAAAA==.Furyrosa:BAAANQAECgEIAQAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAAFAAAAAA==.',
Fy='Fyah:BAABNQAECn8nAAIRAAoKERyvBwBqAgARAAoKERyvBwBqAgABNQAFFAYIFgAGABUZAA==.Fyaza:BAAANQADCggICQABNQAFFAYIFgAGABUZAA==.',
Ga='Gaga:BAAANQAECgEIAQAAAA==.Gargamels:BAAANQAECggICAABNQAECggIDwAFAAAAAA==.Garou:BAAANQAECgQIBwAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICgAAAA==.Gerttie:BAABNQAECn8YAAMfAAgK4gr8NgBkAQAfAAgK4gr8NgBkAQALAAEKAAAlzwAOAAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8YAAIXAAgKWRHTBQAFAgAXAAgKWRHTBQAFAgA1AAQKfyQAAhcACgr6H8ENAMsCABcACgr6H8ENAMsCAAAA.',
Gl='Gloryho:BAAANQABCgUIBgAAAA==.',
Go='Gobsquadp:BAAANQAECgcIEQABNQAECgoKKgAdAJkkAA==.Gonzzo:BAAANQABCgIIAgAAAA==.',
Gr='Grassmoker:BAAANQAECgUICAAAAA==.Grek:BAAANQAECgcIEAABNQAECgkJJwAgAFMeAA==.Grievex:BAABNQAECn8rAAIRAAoKVggZxgCQAQARAAoKVggZxgCQAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQAECgEIAQAAAA==.Grumpel:BAAANQAECgEIAgAAAA==.',
Gu='Guzzlr:BAAANQAECgcIDgAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAZAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAABNQAECn8wAAIbAAoKVBykDgAHAgAbAAoKVBykDgAHAgAAAA==.Heelz:BAAANQAECgEIAQAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAYIDAARACkOAA==.Hemostasis:BAACNQAFFH8MAAIRAAYKKQ60BwDSAQARAAYKKQ60BwDSAQA1AAQKfzQABBEACgrqICkXAGgDABEACQonIykXAGgDABAAAgrmD3AXAUYAABIAAQodFi5tADcAAAAA.Herjä:BAAANQAECgQIDgAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQAFAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.Hezalon:BAAANQAECgEIAQAAAA==.',
Ho='Homeslice:BAABNQAECn8eAAQJAAcKqBW5AwAEAQAIAAQKuRVgFAAEAQAJAAUKohS5AwAEAQAHAAQKGQnRCAG6AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQAECgEIAQAAAA==.Huun:BAABNQAECn8uAAIhAAkKOB9PAgAjAwAhAAkKOB9PAgAjAwAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQAECgEIAgAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn8zAAMHAAkKtwebXQDGAAAHAAkKtwebXQDGAAAJAAMKtAQIVACCAAAAAA==.',
Ib='Iblow:BAAANQADCgEIAQAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Il='Illydan:BAAANQADCgMIAwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQAECgEIAQAAAA==.',
Ir='Irrenadro:BAABNQAECn89AAIRAAoKDA7skwD8AQARAAoKDA7skwD8AQAAAA==.',
Is='Islandhunter:BAAANQAECgEIAQAAAA==.',
Iy='Iyahna:BAAANQAECgQIBwAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgUIDQAAAA==.',
Je='Jeage:BAAANQAECgQIBgABNQAECgkJIAAOAJ4iAA==.Jera:BAAANQADCgIIAgAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgUIBgABNQAECgkJHQAiAGkiAA==.Jimmybones:BAAANQAECgEIAQAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn8lAAIGAAgKYxlbGQC0AQAGAAgKYxlbGQC0AQAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAkJHgARAAkZAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAUIBQAHAJEJAA==.',
Ke='Keetra:BAACNQAFFH8UAAIGAAUKdhZjDACLAQAGAAUKdhZjDACLAQA1AAQKfyEAAgYACQrkH8UtAOQCAAYACQrkH8UtAOQCAAAA.Keiriline:BAABNQAECn8bAAMUAAcKVRDHTQB/AQAUAAcKVRDHTQB/AQAjAAEKAACL0AAtAAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQADCgQIBAAAAA==.',
Kl='Klix:BAAANQADCgcICAABNQAECgcIGAACACAeAA==.',
Kn='Knight:BAABNQAECn8bAAMNAAkKnB0RcgCaAgANAAgKnB0RcgCaAgAcAAIKzAjaCQBoAAAAAA==.Knuggz:BAAANQAECgcIEQAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.Koshmare:BAAANQAECgEIAQAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAgAAAA==.',
Ku='Kubluk:BAAANQAECgMIAwAAAA==.Kumbustinher:BAAANQADCgcIEQAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAMICgAbAIsmAA==.Kylepala:BAAANQAECgYIBgABNQAFFAMICgAbAIsmAA==.Kylepriest:BAACNQAFFH8KAAIbAAMKiybHBwBYAQAbAAMKiybHBwBYAQA1AAQKfzIAAxsACgqIJssBANADABsACgqIJssBANADAB4AAgopI04XALwAAAAA.Kyntamun:BAAANQADCgYIBgABNQADCgcIDwAFAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgcIGAACACAeAA==.Lambeáu:BAABNQAECn8VAAIGAAgK3RitFwC8AQAGAAgK3RitFwC8AQAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgcIDQAAAA==.Lamdabow:BAAANQADCggICAAAAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQAECgEIAgAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDwAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgoKMAADAMkeAA==.Larzoh:BAABNQAECn8wAAMDAAoKyR5JDABIAwADAAoKyR5JDABIAwACAAMKJQbEWQCdAAAAAA==.Lateesha:BAAANQAECgUIDAAAAA==.Lavac:BAAANQAECgIIAgAAAA==.',
Le='Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgUIDQAAAA==.Lightguard:BAABNQAECn8nAAIRAAgKrRd0iwAPAgARAAgKrRd0iwAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8fAAIGAAcK0APu1gBSAQAGAAcK0APu1gBSAQAAAA==.Lilwiz:BAAANQAECgUICQAAAA==.Linalala:BAABNQAECn+IAAQfAAkKzSZFAAABBAAfAAkKzSZFAAABBAAkAAcKqRHhFACtAQALAAIKLAwbmQB1AAAAAA==.Linnxp:BAAANQAECgMIAgABNQAECgUIBQAFAAAAAA==.Linnxs:BAAANQAECgUIBQAAAA==.Linnxvx:BAAANQAECgMIAgABNQAECgUIBQAFAAAAAA==.Lishp:BAAANQAECgEIBQAAAA==.Literacola:BAABNQAECn8XAAINAAgKsQt2LQBoAQANAAgKsQt2LQBoAQAAAA==.',
Lo='Lorino:BAAANQAECgEIBAAAAA==.Lothaire:BAAANQABCgIIAgAAAA==.',
Lu='Lubaduba:BAAANQAECgEIAQAAAA==.Lugeya:BAAANQAECgUICAAAAA==.Lugeyamnk:BAAANQAECgYICQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgMIAwAAAA==.Lustnbeiber:BAABNQAECn8oAAQOAAkKwhXRQgBqAgAOAAkKwhXRQgBqAgABAAYK4AtbrgATAQAiAAEKgwLTNwAwAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgYIDAAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggIEAABNQAECggIJwASACMkAA==.Lynchà:BAABNQAECn8nAAISAAgKIyT/AQBGAgASAAgKIyT/AQBGAgAAAA==.',
Ma='Maakun:BAABNQAECn8yAAIbAAkKfBcFDwADAgAbAAkKfBcFDwADAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIDQAAAA==.Mahoragga:BAAANQAECgMIBAAAAA==.Mahzad:BAABNQAECn8wAAMBAAoKbSD1FgAaAwABAAoKbSD1FgAaAwAOAAUKPh7CdgC9AQAAAA==.Malchezaar:BAAANQAECgYIDwAAAA==.Malfrun:BAABNQAECn8sAAIWAAkKYhAzBQB4AQAWAAkKYhAzBQB4AQAAAA==.Malzahar:BAAANQAECgEIAwAAAA==.Marinnite:BAAANQADCgYIBgAAAA==.Markzugrberg:BAAANQADCgMIAwAAAA==.Marox:BAABNQAECn8uAAINAAoKJRplHwCTAQANAAoKJRplHwCTAQAAAA==.Marrøwgar:BAABNQAECn8XAAMVAAcKiBubCwCHAQAVAAcKiBubCwCHAQAjAAEKAABhxwA6AAAAAA==.Mathrim:BAECNQAFFH8JAAMHAAMKdxt2JgDSAAAHAAIKtyN2JgDSAAAJAAEK9wpyCQBSAAA1AAQKfzIAAwcACgqkIwAEALgDAAcACgqkIwAEALgDAAkAAgqOFbMPAFkAAAAA.Matooka:BAABNQAECn8aAAIGAAcKjwQG1gBUAQAGAAcKjwQG1gBUAQAAAA==.Maynji:BAAANQADCggICAAAAA==.Mazima:BAAANQAECgUIBAAAAA==.',
Mc='Mcthugger:BAAANQAECgEIAQABNQAECgoKJgARAAkXAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYJEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAABNQAECn8UAAMVAAYKAhxHUQDOAQAVAAYKAhxHUQDOAQAUAAUKhw1XMADbAAAAAA==.Mommÿ:BAACNQAFFH8HAAIbAAIKXRmNEgCZAAAbAAIKXRmNEgCZAAA1AAQKfzUAAxsACgqRHEQoAMkCABsACgqRHEQoAMkCAB4ABgpIDL4QAB0BAAAA.Moneymage:BAAANQAECgQIBQAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8xAAIdAAoKgRFNFwD4AQAdAAoKgRFNFwD4AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgoKKgAGAL4cAA==.Moolificent:BAABNQAECn8aAAIUAAkKhAopHgAuAQAUAAkKhAopHgAuAQAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAABNQAECn8ZAAIfAAoKmRrNFwCCAgAfAAoKmRrNFwCCAgAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECggILgAaAF4XAA==.Muddgore:BAAANQADCggIDgABNQAECggILgAaAF4XAA==.Muddthir:BAAANQADCgQIBAABNQAECggILgAaAF4XAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgoKPgAGAFskAA==.Mustardrogue:BAAANQAECgUIBQAAAA==.',
My='Myzarei:BAAANQAECgUIDQAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn8uAAMaAAgKXheKJwBSAgAaAAgKXheKJwBSAgAYAAQKdhPpNwD5AAAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgEIAgAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECn8vAAINAAoK9g7EOABMAQANAAoK9g7EOABMAQAAAA==.Nisia:BAABNQAECn8UAAMHAAkKDxgYOQCpAgAHAAkKDxgYOQCpAgAJAAEKiwiSfAAwAAABNQAFFAIIBQAKAB8TAA==.Nito:BAABNQAECn8lAAIUAAkKGBEMNAANAgAUAAkKGBEMNAANAgAAAA==.',
No='Nobainer:BAAANQADCgMIAwAAAA==.Nohkano:BAABNQAECn85AAIlAAkKdiZfAADxAwAlAAkKdiZfAADxAwAAAA==.Nokt:BAAANQAECggICwAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgcIDgAAAA==.Noveerra:BAAANQADCgcIDwAAAA==.',
Nu='Numbuh:BAAANQAECgQIDAAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakremi:BAAANQADCgMIAwAAAA==.Oakrogue:BAAANQAECgEIBAAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ortillious:BAAANQAECgQICAABNQAECgYIDAAFAAAAAA==.',
Ov='Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggIDAAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgcIDAABNQAFFAYIDAARACkOAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcJDAAAAA==.Pantheons:BAAANQAECgUIEgAAAA==.Parsi:BAABNQAECn8cAAMEAAcK/xkvDAAFAgAEAAcK/xkvDAAFAgACAAIKmQduYQBnAAAAAA==.Pattysmyth:BAAANQAECgYIDQABNQADCggIEgAFAAAAAA==.Paulinemaroi:BAAANQAECggIEgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECggIEgAFAAAAAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQAECgEIAgABNQAECgcIGAACACAeAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Phaell:BAAANQAECgEIAgAAAA==.Philip:BAAANQAECgcICQAAAA==.Phäell:BAAANQAECgEIAgAAAA==.',
Pl='Playstayshon:BAAANQAECgEIAQAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQADAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDgAFAAAAAA==.Poppafury:BAAANQAECgEIAQAAAA==.Poppapulls:BAAANQAECggIBQAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAwABNQAECgkJGQADAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcJBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgYICwABNQAECgkJFwANAHAYAA==.',
['Pä']='Pändora:BAAANQAECgUIBQAAAA==.',
Ra='Rabite:BAABNQAECn8qAAIdAAoKmSS1AgAfAgAdAAoKmSS1AgAfAgAAAA==.Radiance:BAEANQAECgYICgABNQAFFAUICgAZABQfAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBgAAAA==.Randyvivaldi:BAAANQAECgEIBAAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rathasas:BAABNQAECn8vAAMXAAkK5hzsBACWAQAXAAkK5hzsBACWAQAMAAIK5BfbMACPAAAAAA==.Ratnob:BAABNQAECn8hAAIVAAoK6hQyOQBAAgAVAAoK6hQyOQBAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMgAAkKUx62AwDqAgAgAAkKUx62AwDqAgAMAAEKfwaTQAAqAAAAAA==.Relda:BAAANQAECgcICwABNQAECgkJHQAiAGkiAA==.Remye:BAABNQAECn8tAAIQAAoKVhkbHwBtAQAQAAoKVhkbHwBtAQAAAA==.Rennshi:BAABNQAECn8dAAIDAAkK8CVWCAB2AwADAAkK8CVWCAB2AwAAAA==.Reportedhunt:BAABNQAECn8pAAIGAAoKNRdrQACpAgAGAAoKNRdrQACpAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgQIBgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimmy:BAAANQAECgEIAQABNQADCgEIAQAFAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8dAAMCAAUKoARKJACQAAACAAUKoARKJACQAAADAAIKfgRkiQBSAAAAAA==.Roldaza:BAAANQAECgUIDQAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn8+AAMGAAoKWySYCwAXAgAGAAoKWySYCwAXAgAZAAYKTgy7SwAGAQAAAA==.',
Ru='Rulep:BAAANQAECggIAwAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Ryotwar:BAAANQAECgIIAgAAAA==.Rythmatic:BAABNQAECn82AAMYAAoK2iNDAQDDAgAYAAoKiSNDAQDDAgAaAAcKoyEKIACBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sakieri:BAABNQAECn8qAAMTAAoKcRgXGgB8AgATAAoKcRgXGgB8AgAbAAEKKQMmAwEpAAAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQAECgEIAQAAAA==.Sangan:BAABNQAECn81AAINAAoKhBvFGgCkAQANAAoKhBvFGgCkAQAAAA==.Sangen:BAAANQAECgEIAQAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwAFAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8SAAIMAAYKiBbsAgDWAQAMAAYKiBbsAgDWAQA1AAQKfycAAgwACgpXIKAFADYDAAwACgpXIKAFADYDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgUICwAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQAECgEIAQAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgUJBgAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8mAAMHAAoK8B+1EwA+AwAHAAoK8B+1EwA+AwAJAAIK8RvvTQCVAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8iAAINAAgKjgqobwDdAAANAAgKjgqobwDdAAAAAA==.',
Sk='Skeezer:BAAANQAECgEIAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAgAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQAECggICgAAAA==.',
St='Starfrost:BAAANQAECgEIAQAAAA==.Stingerai:BAABNQAECn8qAAIGAAoKvhzeJwD4AgAGAAoKvhzeJwD4AgAAAA==.Stingerjb:BAAANQAECgQIBgABNQAECgoKKgAGAL4cAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAABNQAECn8WAAIHAAoK8xMXVABZAgAHAAoK8xMXVABZAgAAAA==.Sucemabite:BAAANQADCgEIAQAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYICAABNQAECgkJFgARAAAhAA==.',
Sy='Syl:BAAANQAECgUIDgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECggIJgAmAI4fAA==.Teemonk:BAABNQAECn8mAAImAAgKjh+kEwC7AgAmAAgKjh+kEwC7AgAAAA==.Teepal:BAAANQAECgEIAQABNQAECggIJgAmAI4fAA==.Teila:BAAANQAECgEIAQAAAA==.Teladrel:BAAANQAECggIAwAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAABNQAECn8XAAIiAAYKExelDQAjAQAiAAYKExelDQAjAQAAAA==.Teribullduce:BAABNQAECn8pAAIGAAoKPiK5DQAEAgAGAAoKPiK5DQAEAgAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thickyricky:BAABNQAECn8UAAIaAAkKOBMbFwAPAQAaAAkKOBMbFwAPAQABNQAECgkJHQAiAGkiAA==.Thingol:BAAANQABCgcIFQAAAA==.Thormor:BAAANQAECgQICgABNQAFFAgIGAAXAFkRAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgQICAABNQAECgoKJgARAAkXAA==.Thuggerjr:BAABNQAECn8mAAIRAAoKCRdxaQBgAgARAAoKCRdxaQBgAgAAAA==.Thundersurge:BAAANQAECgEIAQABNQAECgoKKQAGADUXAA==.Thænes:BAAANQAECgYIEwAAAA==.Thûr:BAAANQAECgIIAgABNQAECgoKLQABAHQbAA==.',
Ti='Tigg:BAABNQAECn8eAAIOAAgKNARZ4wDQAAAOAAgKNARZ4wDQAAAAAA==.Tildin:BAAANQAECgEIAQAAAA==.Tinkerdinker:BAAANQAECgEIAwAAAA==.Tipsout:BAACNQAFFH8FAAIKAAIKHxPIEACWAAAKAAIKHxPIEACWAAA1AAQKfzYAAwoACQoKIiEjACwDAAoACQoKIiEjACwDABYABgrWExIiADoBAAAA.',
Tn='Tnemith:BAAANQAECgEIAQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECggIJgAmAI4fAA==.Torastrasza:BAAANQAECgIIAgAAAA==.Totemm:BAAANQAECggIEQAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn8tAAMBAAoKdBsyIQBjAQABAAoKdBsyIQBjAQAOAAUKQhGTsgAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgEIAQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAABNQAECn8XAAIQAAgK4xomCgAgAgAQAAgK4xomCgAgAgAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIBQAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Un='Unfocused:BAABNQAECn84AAILAAoKQB3YCACqAQALAAoKQB3YCACqAQAAAA==.Unholybelac:BAAANQADCgYICgAAAA==.',
Ur='Urgmathron:BAABNQAECn8cAAISAAYKiBrjJAC5AQASAAYKiBrjJAC5AQAAAA==.',
Va='Vakhara:BAABNQAECn8YAAICAAcKIB4bBwCdAQACAAcKIB4bBwCdAQAAAA==.Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIBAABNQAFFAUICgATAMkWAA==.Vansthir:BAAANQAECggIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIBAABNQAFFAUIEQAKAHkRAA==.Vaush:BAABNQAECn8XAAMUAAcKSgO+RACUAAAVAAYKogPlmgDJAAAUAAcKGAK+RACUAAAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQAECgIIAgAAAA==.',
Vi='Victorix:BAAANQADCgUIBQAAAA==.Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8bAAIgAAYK2w1/EQAdAQAgAAYK2w1/EQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBQAFAAAAAA==.Volcanoez:BAAANQAECgIIAgAAAA==.Vonrx:BAAANQAECgEIBgAAAA==.',
Vr='Vrezor:BAAANQAECggIBAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.Vulpala:BAAANQADCggICAAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgoKNQALAJ4hAA==.',
Wa='Wardian:BAAANQAECgQIBwABNQAECgoKJwARADsSAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgoKKQAGADUXAA==.Warthyr:BAAANQADCgIIAgAAAA==.',
We='Welfairline:BAAANQADCggIGgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgoKKQAGAD4iAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8eAAImAAoKAxxUDgD6AgAmAAoKAxxUDgD6AgAAAA==.Yassera:BAAANQAECgQIDgAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8gAAIKAAkKQQ5EXADgAAAKAAkKQQ5EXADgAAAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQAECgEIAQAAAA==.Zapman:BAAANQAECgEIAgAAAA==.Zarik:BAABNQAECn8VAAIHAAYKfQknVwDUAAAHAAYKfQknVwDUAAAAAA==.',
Ze='Zeddoc:BAEANQAECgEIBAAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIBAAFAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAAANQAECgYIEgAAAA==.',
Zo='Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQAECgEIBAAAAA==.',
Zu='Zulugangrene:BAABNQAECn8gAAIRAAcKRA3A0AB6AQARAAcKRA3A0AB6AQAAAA==.Zun:BAABNQAECn8VAAIPAAYKtwgDGwAaAQAPAAYKtwgDGwAaAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgYIEwAFAAAAAA==.',
['Çh']='Çhunchunmaru:BAAANQAECgIIAwABNQAECgoKKgAGAL4cAA==.',
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
