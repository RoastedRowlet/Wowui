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

local lookup = {'Druid-Restoration','Warrior-Protection','Unknown-Unknown','Druid-Guardian','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Shaman-Restoration','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Priest-Shadow','DemonHunter-Havoc','Rogue-Assassination','Shaman-Elemental','Paladin-Protection','Evoker-Preservation','Warlock-Affliction','Druid-Balance','Priest-Holy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Devastation','Warrior-Fury','Monk-Brewmaster','Shaman-Enhancement','Monk-Mistweaver','Rogue-Outlaw','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Monk-Windwalker','Priest-Discipline',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaliyah:BAABNQAECn8wAAIBAAkKVRxVDgDpAgABAAkKVRxVDgDpAgAAAA==.',
Ab='Aboxofchips:BAAANQAECggIBwAAAA==.Absolutswet:BAAANQAFFAUIAQAAAA==.Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQAECgUIEAAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQAECgUIDgABNQAECgkJLAACALMdAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgUIDgADAAAAAA==.Aeliniani:BAAANQAECgEIAQAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAABNQAECn8eAAMEAAcK9h8wDwBqAgAEAAcK9h8wDwBqAgAFAAEKAACbSAAkAAAAAA==.Agliam:BAAANQAECgEJAgAAAA==.',
Ah='Ahngus:BAABNQAECn8gAAICAAgK4hwFCwCLAgACAAgK4hwFCwCLAgAAAA==.',
Ai='Air:BAAANQAECgYIEgAAAA==.',
Al='Alakander:BAAANQAECgMIBgAAAA==.Alexcrowley:BAAANQADCgYICwAAAA==.Alexdh:BAAANQAECgMIBQABNQAFFAcIEAAGALYfAA==.Alexdk:BAAANQADCgMIAwABNQAFFAcIEAAGALYfAA==.Alexdruids:BAAANQAECgUIBQABNQAFFAcIEAAGALYfAA==.Alexhunt:BAACNQAFFH8QAAQGAAcKth/iBAAFAgAGAAUKeSTiBAAFAgAHAAMKIhRNFgDVAAAIAAEKLCAyAgBcAAA1AAQKfyYABAYACQrYIqg9AK8CAAYACAqKIqg9AK8CAAcABwqhIBUgAEsCAAgAAQoAACsRAFgAAAAA.Alexpaladin:BAAANQAECgUIBQABNQAFFAcIEAAGALYfAA==.Alirunna:BAAANQADCgQIBgAAAA==.Allaris:BAAANQAECgQIBAAAAA==.Alplarn:BAAANQAECgQIBgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
Am='Amanarra:BAAANQADCgQIBAAAAA==.Amorlorisy:BAAANQAECgQIBQABNQAECggIBwADAAAAAA==.',
An='Anitwa:BAABNQAECn8lAAMJAAgKMCBdIwC0AgAJAAgKMCBdIwC0AgAKAAEKFRQMpwA4AAAAAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgQIBwAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAABNQAECn8tAAIGAAkKgxduRwCUAgAGAAkKgxduRwCUAgAAAA==.Aranina:BAAANQAECgUIEAAAAA==.Arcami:BAAANQADCgIIAgAAAA==.Arcanedria:BAAANQABCgYIBgAAAA==.Arcanz:BAAANQAECgEIAQAAAA==.Arcturrus:BAAANQAECgUIBQAAAA==.Arel:BAABNQAECn8fAAMLAAkKESHoEABFAwALAAkKESHoEABFAwAMAAEKAABodgFfAAAAAA==.Argeon:BAAANQAFFAEIAQAAAA==.Arkanis:BAAANQADCggIHgAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgcIGwAAAA==.Arrwyn:BAAANQAECgYIEQABNQAECggIGAACAPMlAA==.Arter:BAAANQAECgEIAQABNQAECgkJKAANALkWAA==.Aryhm:BAAANQAECgYICgAAAA==.',
As='Asatralth:BAAANQAECgcIEwAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQAECgUIDQAAAA==.Aszshara:BAAANQAECgMIBQAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAABNQAECn8bAAIEAAgKKxllEQBGAgAEAAgKKxllEQBGAgAAAA==.',
Ba='Babihotdog:BAAANQAECgMIBQAAAA==.Babylego:BAAANQAECggIDAABNQAFFAcIFwANAOofAA==.Badspec:BAAANQAECggIAQAAAA==.Badwolff:BAABNQAECn8bAAIOAAcKYgz8lQBMAQAOAAcKYgz8lQBMAQAAAA==.Baerog:BAAANQAECgUIEAAAAA==.Balid:BAAANQAECgIIAgAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAACNQAFFH8IAAIPAAMKeQmROADeAAAPAAMKeQmROADeAAA1AAQKfzQAAg8ACQrlHZNFAPgCAA8ACQrlHZNFAPgCAAAA.Baodrubao:BAAANQAECgQIBAAAAA==.Barlake:BAAANQADCgUIBQAAAA==.Basicblends:BAAANQAECgQIBQAAAA==.',
Bb='Bblglizzy:BAAANQAECgcICAAAAA==.',
Be='Beefglizzy:BAABNQAECn8ZAAIJAAcK7B+aKwCEAgAJAAcK7B+aKwCEAgAAAA==.Beeftàllow:BAAANQADCgUJBQAAAA==.Beelzaboot:BAABNQAECn8jAAMQAAgKXhXEggDbAQAQAAcK5hTEggDbAQARAAIKYQ9JWAB1AAAAAA==.Belanor:BAABNQAECn8sAAICAAkKsx2UBgD4AgACAAkKsx2UBgD4AgAAAA==.Benjangles:BAABNQAECn8dAAMSAAcKIQgmGgAhAQAPAAcKBgTmOAEqAQASAAYKUgkmGgAhAQAAAA==.Berry:BAABNQAECn8zAAIEAAkKsiTKAQC8AwAEAAkKsiTKAQC8AwAAAA==.Betrayer:BAAANQAECgMIBAABNQAECgkJIwATAGgaAA==.',
Bh='Bhogrenoc:BAAANQAECgQIBAAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECggIJQAJADAgAA==.Bigdamfury:BAAANQAECgQIBQABNQAECgUIBwADAAAAAA==.Bignipsmcgee:BAAANQAECgQICAABNQAECggIAQADAAAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgcICwAAAA==.Bitss:BAAANQADCgEIAQABNQAECggIHgAEAPYfAA==.',
Bl='Blacksam:BAAANQAECgQIBgAAAA==.Blacktastic:BAAANQAECgUICAAAAA==.Blackóut:BAAANQAECgEIAQAAAA==.Bladebane:BAAANQADCgQIBAABNQAECgYIGQAKAG8SAA==.Blastee:BAABNQAECn8rAAIGAAkKMyHfFwA5AwAGAAkKMyHfFwA5AwAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQAECgcICgABNQAECggIEQADAAAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.Bloodlego:BAABNQAECn8cAAIKAAgKIyMaDgAfAwAKAAgKIyMaDgAfAwABNQAFFAcIFwANAOofAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Bolter:BAAANQAECgEIAgAAAA==.Boomnecrotic:BAABNQAECn8dAAIJAAgKoxlEOQA8AgAJAAgKoxlEOQA8AgAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgMIBAAAAA==.Bottlewater:BAAANQADCgUIBgAAAA==.',
Br='Braine:BAAANQADCgQICAAAAA==.Brainsai:BAAANQAECgQIBAABNQAECgIIAgADAAAAAA==.Breathboy:BAAANQAECgQICgAAAA==.Brikz:BAAANQADCgQIBAAAAA==.Bronder:BAAANQADCgYIEAAAAA==.Bruceree:BAAANQAECggICAAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Buffchadwell:BAAANQADCgUIBQAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQADCgUIBQAAAA==.Burghmaul:BAABNQAECn8dAAINAAcKDQs9vACBAQANAAcKDQs9vACBAQAAAA==.',
Ca='Cadwallader:BAAANQABCgIIAgAAAA==.Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Candykate:BAAANQADCgIIAgAAAA==.Canon:BAAANQAECgYIEgAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Ceevee:BAAANQAECgIIBAAAAA==.Celasong:BAAANQAECgEIAQAAAA==.Celayse:BAAANQAECgQIBAAAAA==.Celeritas:BAAANQAECgYIBgAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCggIEwAAAA==.Celydrea:BAABNQAECn8XAAIUAAYKhwKObADBAAAUAAYKhwKObADBAAAAAA==.Ceree:BAABNQAECn8rAAIMAAkKRA2gmgDpAQAMAAkKRA2gmgDpAQAAAA==.',
Ch='Cherryfox:BAAANQADCgYIBgAAAA==.Chimeranzomb:BAAANQADCgQIBAAAAA==.Chippedbeef:BAAANQAECgQIDQAAAA==.Chiwi:BAAANQAECgEIAQAAAA==.Chocogeta:BAABNQAECn8gAAIVAAgKaxMiMQAWAgAVAAgKaxMiMQAWAgAAAA==.Chubbsmcgee:BAAANQAECgEIAQAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQAECgYICwAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAABNQAECn8iAAMWAAkK1CGcDwBtAwAWAAkK1CGcDwBtAwAOAAIK3hql+gBvAAAAAA==.Clag:BAAANQAECgUIBgAAAA==.',
Co='Cogblock:BAABNQAECn8nAAINAAcKChmqegAkAgANAAcKChmqegAkAgAAAA==.Coheed:BAAANQAECgQIBAABNQAECgkJJwAXAPEYAA==.Coldsteak:BAAANQADCggIDgAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cp='Cpwolf:BAAANQADCgYJBwAAAA==.',
Cr='Crappen:BAAANQADCgMIAwAAAA==.Crimsonbull:BAAANQADCggICAABNQAECgkJMgAQAD4hAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Cruelerr:BAAANQADCgQIBAABNQAECgYIEQADAAAAAA==.Crushaturty:BAAANQAECgMIAgAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQADCgcICAAAAA==.Cyndrin:BAABNQAECn8gAAMGAAkKlh3nQwCeAgAGAAgKyh/nQwCeAgAHAAQKfRTeSAATAQAAAA==.',
Da='Daddyfatsaks:BAAANQADCgUIBgAAAA==.Daddyglock:BAAANQAECgUIDAAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAADAAAAAA==.Dahbihgah:BAAANQAECgQIBAABNQAECgkJLQAUAGoWAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAACNQAFFH8XAAINAAcK6h97AwCmAgANAAcK6h97AwCmAgA1AAQKfy0AAg0ACQomJugHALMDAA0ACQomJugHALMDAAAA.Darknite:BAAANQAECgYIDQABNQAECggIGAACAPMlAA==.Darksign:BAAANQADCgIIAgAAAA==.Dathundir:BAAANQAECggIDgABNQAECgkJLAAMAPQbAA==.Davemage:BAABNQAECn8ZAAIPAAcK8RYbpwAyAgAPAAcK8RYbpwAyAgAAAA==.Davidpaine:BAAANQAECgUICgABNQAECgcIDwADAAAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBwAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAABNQAECn8lAAMMAAgKyxX5jAAHAgAMAAgKyxX5jAAHAgAXAAIKjw4XWQB1AAAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Denken:BAAANQADCgUIBQABNQAECgQICAADAAAAAA==.Deseriee:BAAANQADCgMIAwAAAA==.Destnny:BAABNQAECn8WAAMQAAkK9BSETABrAgAQAAkK9BSETABrAgARAAEKbBUpcQA9AAAAAA==.Destrohunter:BAAANQADCggIDgAAAA==.Destroker:BAABNQAECn8hAAIYAAcKpQ+gJQCOAQAYAAcKpQ+gJQCOAQAAAA==.Dewax:BAAANQAECgYICQAAAA==.Deylight:BAAANQADCggIGgAAAA==.',
Dh='Dhalla:BAAANQAECgEIAQABNQAECgYICgADAAAAAA==.Dhspudd:BAAANQADCgYIBgABNQAECgcIHAANAFUWAA==.',
Di='Dillpo:BAAANQABCgUIBwAAAA==.Dioress:BAAANQAECgQIBgAAAA==.Dis:BAABNQAECn8pAAIZAAkK2iLdAAB4AwAZAAkK2iLdAAB4AwABNQAFFAcIGQAWAFIfAA==.Distear:BAAANQAECgMIBAAAAA==.Disyx:BAAANQAECgcIEQABNQAECggIGgAVAD0TAA==.Diyanå:BAABNQAECn8wAAIGAAkKtxbiSQCNAgAGAAkKtxbiSQCNAgAAAA==.',
Do='Dogfoodfrboy:BAAANQAECgIIAgAAAA==.Domainz:BAAANQAECgYIDAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgYIBgABNQAFFAQIDAAZAD4MAA==.Donzw:BAACNQAFFH8MAAQZAAQKPgw+DgBIAAAQAAIKcwqbNACMAAARAAEK1A9sHABOAAAZAAEKAAA+DgBIAAA1AAQKfyQABBkACQp3FmAOAGkBABAACQoOFQ9rABgCABkABwq0EWAOAGkBABEABAoFBgtEALQAAAAA.Dorae:BAAANQAECgEIAQAAAA==.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgcIEgAAAA==.Dragonbender:BAEANQAECgIIAgAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEIAQAAAA==.Dreamender:BAAANQAECggJBQABNQAECggICgADAAAAAA==.Drfrash:BAAANQADCgYIBgAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAABNQAECn8dAAMFAAgK/QxQFwB/AQAFAAcK/QxQFwB/AQAaAAgK4AIybwAJAQAAAA==.Drumin:BAABNQAECn8fAAMWAAkK7yC1IAAGAwAWAAgKDiK1IAAGAwAOAAMKwhXz0QC+AAAAAA==.',
Du='Dudewithpets:BAAANQADCgUIBQAAAA==.Durahar:BAAANQAECgcIEgAAAA==.Durpy:BAAANQAECgQIBgAAAA==.',
Dw='Dwarvanhand:BAACNQAFFH8YAAMTAAcKrxoZBAAKAgATAAYKrxoZBAAKAgAbAAQKBxEFFwA3AQA1AAQKfy0AAxMACQo7I7cJAEMDABMACQo7I7cJAEMDABsAAgoyEuXdAIYAAAAA.',
['Dá']='Dáin:BAAANQAECgMICQABNQAECggIGQAcAFIWAA==.',
['Dâ']='Dâwn:BAABNQAECn8aAAMMAAgK2xxjVgCPAgAMAAgK2xxjVgCPAgAXAAYKDgieRQDVAAAAAA==.',
['Dã']='Dãwn:BAAANQAECggIBgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQAECggIEgABNQAECgkJJQAcAJEjAA==.Earthrender:BAAANQAECgEIAQAAAA==.Eatmacookie:BAAANQAECgUIBQAAAA==.',
El='Elazar:BAAANQAECgcICgAAAA==.Elderian:BAABNQAECn80AAIUAAkKSyaNAQDiAwAUAAkKSyaNAQDiAwAAAA==.Elemenope:BAAANQAECgYIDAAAAA==.Elementhol:BAAANQADCgYIBgAAAA==.Elemitchard:BAAANQAECgUICgAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAABNQAFFH8KAAMdAAQKNhiPCwD+AAAdAAMKRhSPCwD+AAAVAAEKFyDgGgBZAAAAAA==.Elitegamerx:BAAANQAECgYIBgABNQAECgcIEQADAAAAAA==.Elpadrino:BAAANQADCgcICgAAAA==.Elunaryn:BAAANQAECggJAQAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQAECgUIBQAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.Emmabeth:BAAANQADCgMJAwAAAA==.',
En='Eniri:BAAANQAECgMIBgAAAA==.Enyeto:BAABNQAECn8oAAMNAAkKuRY/cAA/AgANAAkKuRY/cAA/AgACAAEKUg2ZQwAvAAAAAA==.',
Er='Ermaghaku:BAAANQAECgIIAgAAAA==.Erodras:BAAANQADCgIIAgAAAA==.Erojin:BAAANQADCgYIBgAAAA==.Eroviaevia:BAAANQAECgYIDwAAAA==.',
Es='Estavar:BAAANQAECgEIAQAAAA==.Esterossa:BAAANQADCgYICwAAAA==.',
Et='Etard:BAAANQADCgMIAwAAAA==.',
Eu='Eunomia:BAABNQAECn8cAAIHAAcKgxYwNQCgAQAHAAcKgxYwNQCgAQAAAA==.',
Ev='Evilest:BAAANQAECgEIAQAAAA==.',
Ex='Excuse:BAAANQAFFAEIAQABNQAECgkJKgAPACQeAA==.Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAABNQAECn8YAAMJAAgKLw5CWQCoAQAJAAgKLw5CWQCoAQAKAAIKCgl2mQBZAAAAAA==.Ezoghoul:BAABNQAECn8bAAINAAgKsRMokADvAQANAAgKsRMokADvAQAAAA==.',
Fa='Faeare:BAAANQAECgIIAgAAAA==.Faene:BAAANQADCgQIBAAAAA==.Faerion:BAAANQAECgUIBgABNQAECgkJLAAOACIkAA==.Fakedemon:BAEANQADCgIIAgABNQAECgYIDQADAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgYIDQADAAAAAA==.Fakendruid:BAEANQAECgYIDQAAAA==.Fakewar:BAEANQADCgYIDAABNQAECgYIDQADAAAAAA==.Fauxx:BAAANQAECgYIBgAAAA==.Fayanor:BAAANQADCggICAAAAA==.',
Fd='Fdup:BAAANQAECgMJBAAAAA==.',
Fe='Felfae:BAAANQAECgUICAAAAA==.Fenneç:BAAANQADCgUIBQABNQAECgcIHAALAK4SAA==.Feverish:BAABNQAECn8jAAIVAAkKkhBeLQArAgAVAAkKkhBeLQArAgAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggIFAAAAA==.Florellia:BAAANQADCgQIBAAAAA==.Flumpy:BAABNQAECn82AAIGAAkKtySoDQBxAwAGAAkKtySoDQBxAwAAAA==.Flurpymcdoof:BAAANQAECgcIBwAAAA==.',
Fo='Folken:BAABNQAECn8hAAIFAAgKPwtwEwDDAQAFAAgKPwtwEwDDAQAAAA==.Foodtruck:BAAANQAECgMIAwABNQAECggIHgAeAKQQAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Fornacater:BAAANQADCgcIBwAAAA==.Foxiefoxy:BAAANQAECgUIDAAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECgkJKAANALkWAA==.Frankzappah:BAAANQABCgIIAgAAAA==.Freetorylane:BAAANQADCgEIAQAAAA==.Freylyn:BAAANQADCgUIBQAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funeralhome:BAAANQAECgQIBAAAAA==.Funkweave:BAEANQAECgcIEwAAAA==.Fupacabras:BAABNQAECn8UAAIWAAgKZgbbpwBAAQAWAAgKZgbbpwBAAQAAAA==.Furidas:BAABNQAECn8VAAICAAcKUB6mDQBTAgACAAcKUB6mDQBTAgAAAA==.Fuse:BAAANQABCgIIAgAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gadreyeth:BAAANQAECgQIBQAAAA==.Gaius:BAAANQABCgIIAgAAAA==.Gangreenanus:BAAANQADCgYICgAAAA==.Garogg:BAABNQAECn8pAAICAAkKyhE6EgD/AQACAAkKyhE6EgD/AQAAAA==.Garotomoreno:BAABNQAECn8nAAIMAAkKrRy/UwCXAgAMAAkKrRy/UwCXAgAAAA==.Garrut:BAABNQAECn8iAAMEAAgKPB/oCADmAgAEAAgKPB/oCADmAgAFAAQKdg7AKADFAAAAAA==.Gaymr:BAAANQADCgIIAgAAAA==.',
Ge='Geraldine:BAAANQAECgQIBwABNQAECggIEQADAAAAAA==.',
Gi='Gigagrog:BAAANQAECgQIBQAAAA==.Giirthquakee:BAAANQAECggIAQAAAA==.Gimick:BAAANQADCggIFAABNQAECgcIIwAPAA0aAA==.Gimmage:BAABNQAECn8jAAMPAAcKDRpL4QDDAQAPAAYKghpL4QDDAQASAAIKfxfKLwB9AAAAAA==.Gingebsham:BAAANQADCgcIBwABNQAECggIHAAbACAKAA==.Girlyouthicc:BAAANQAECgYIDAABNQAFFAcIGAATAK8aAA==.Girthbrøøks:BAAANQADCgYIBgABNQAFFAMIAwADAAAAAA==.',
Gl='Gloiven:BAAANQAECgUIBwABNQAECggIEQADAAAAAA==.',
Go='Gojosatóru:BAAANQAECgQJCwAAAA==.Goldenchef:BAAANQAECgUICQAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gordray:BAAANQAECgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQAECgIIAwAAAA==.Grasswhistle:BAAANQAECgcIDwABNQAFFAQICgAFALgVAA==.Grayzor:BAAANQAECgYICwAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAABNQAECn8nAAIPAAcKJBRmzADrAQAPAAcKJBRmzADrAQAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAABNQAECn8aAAMNAAgKbxq/fQAdAgANAAgKbxq/fQAdAgAfAAEKAAAnMQA6AAAAAA==.Grigdor:BAACNQAFFH8IAAIQAAMKeQs3JQDaAAAQAAMKeQs3JQDaAAA1AAQKfy4AAxEACQp8HA8WALsBABAACAofHClNAGkCABEABgpTGA8WALsBAAAA.Grimnativex:BAAANQADCgIIAgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAABNQAECn8uAAMaAAkKmx+4FwAIAwAaAAkKmx+4FwAIAwABAAEKaQN6ewAjAAAAAA==.Gumbyofgad:BAAANQAECgYIBgAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.Guyblo:BAAANQAECgMIAwABNQAECgkJGQAQAAYVAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgUIEQAAAA==.',
Ha='Habrosh:BAAANQAECgUIDwAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hairlock:BAAANQAECgcIEQABNQAECgkJIwATAGgaAA==.Hakiry:BAABNQAECn8cAAIcAAgKTRz+JQCLAgAcAAgKTRz+JQCLAgAAAA==.Haliburton:BAAANQADCgMIAwAAAA==.Haramhabibi:BAAANQADCgYIBgAAAA==.Harike:BAAANQAECgEIAgAAAA==.Hatrix:BAAANQADCgYIDwAAAA==.Haunt:BAAANQAECgYIEgAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkkaye:BAAANQAFFAEIAQAAAA==.Hawkwardfall:BAAANQADCgYICAAAAA==.Haze:BAAANQAECgEIAgAAAA==.Hazesamaa:BAABNQAECn9CAAIdAAkK8RHZEwBJAgAdAAkK8RHZEwBJAgAAAA==.',
He='Healsforfree:BAAANQADCgIJAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIJAgAAAA==.Hernog:BAABNQAECn8gAAIWAAkKDxxBJwDjAgAWAAkKDxxBJwDjAgAAAA==.Hexmenixy:BAABNQAECn8cAAIQAAcK8Q3EngCUAQAQAAcK8Q3EngCUAQAAAA==.',
Hi='Hianu:BAABNQAECn8ZAAMQAAkKBhUNeAD2AQAQAAkKzQ4NeAD2AQAZAAQKRhr+EgAXAQAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.Hildalock:BAAANQADCggICAABNQAECgUIBQADAAAAAA==.',
Ho='Holabenjy:BAAANQAECgQIEwAAAA==.Holybenjy:BAAANQAECgMIBAAAAA==.Holybibble:BAAANQAECgEIAQAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgcICwAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQAECgMIAwAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holysponge:BAAANQAECgMIAwABNQAFFAUICAAPABoSAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcIFQABNQAECgkJQgAdAPERAA==.Hordak:BAAANQAECgEIAQAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQAECgYIDQAAAA==.Hottodot:BAABNQAECn8cAAIbAAgKIAq9gQCNAQAbAAgKIAq9gQCNAQAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAABNQAECn8VAAIgAAYKIhuTEgC4AQAgAAYKIhuTEgC4AQAAAA==.',
Hr='Hroptatyr:BAAANQADCgMIBwAAAA==.',
Hu='Hudini:BAABNQAECn88AAIPAAkKrhxQOAAXAwAPAAkKrhxQOAAXAwAAAA==.Hugs:BAAANQAECgMIAwAAAA==.Huntsmang:BAAANQADCgEJAQAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hybridkaidou:BAAANQADCgMIAwAAAA==.Hypal:BAABNQAECn8YAAMLAAkKMhLnaADaAQALAAgK9hDnaADaAQAMAAIKjgz7bgFpAAABNQAECggIEAADAAAAAA==.Hypd:BAAANQAECggIEAAAAA==.Hypev:BAAANQAECggIEwABNQAECggIEAADAAAAAA==.Hypm:BAAANQAECgcICgABNQAECggIEAADAAAAAA==.Hyps:BAACNQAFFH8IAAIOAAUKuA42DQB1AQAOAAUKuA42DQB1AQA1AAQKfy8AAw4ACQoVIaERADgDAA4ACQoVIaERADgDABYABQr6D3/BAAoBAAE1AAQKCAgQAAMAAAAA.Hypt:BAABNQAECn8aAAMbAAkKQBFPXQAGAgAbAAgKmxJPXQAGAgATAAIKUAoAbQBNAAABNQAECggIEAADAAAAAA==.',
Ia='Iakned:BAAANQAECgUICQABNQAECggIEQADAAAAAA==.',
Ib='Ibichi:BAAANQADCgcIGQAAAA==.',
Ic='Icet:BAABNQAECn8vAAMdAAkKBxXzFQAxAgAdAAgKDRbzFQAxAgAVAAgKZhD6NQD8AQABNQADCggIDgADAAAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQAECgUIBgAAAA==.',
In='Indàcouch:BAAANQABCgIIBAAAAA==.Invìctús:BAABNQAECn8bAAMSAAgKURpRCQA8AgASAAgKURpRCQA8AgAPAAEKHAVDxgEyAAAAAA==.',
Io='Ionalafe:BAAANQADCgcICQAAAA==.',
It='Ithir:BAAANQADCgcJDAAAAA==.Itsemma:BAAANQAECgcIEgAAAA==.',
Iu='Iustitia:BAAANQABCgYIDwAAAA==.',
Iv='Ivieruem:BAAANQADCgUIDAAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jaanus:BAAANQAECggICAAAAA==.Jackdalilguy:BAAANQAECgMIAwAAAA==.Jackodes:BAAANQAECggIDwABNQAFFAMIBwASAFYaAA==.Jackodm:BAACNQAFFH8HAAMSAAMKVhpACACWAAAPAAMKDhi3LwAJAQASAAIK2xFACACWAAA1AAQKfycAAw8ACQoNI6AtADIDAA8ACQoNI6AtADIDABIAAwpJGSghAN0AAAAA.Jad:BAABNQAECn8lAAIOAAgKbhkiQABdAgAOAAgKbhkiQABdAgAAAA==.Jakedawg:BAAANQAECgIIAgAAAA==.Jamiepapo:BAAANQADCgIIAwAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCggIGgAAAA==.Jarlam:BAAANQABCgcIDwABNQAECggIIgAhAOEUAA==.Jawa:BAAANQAECgEIAQABNQAECggIJQAfAJwLAA==.Jawo:BAABNQAECn8lAAIfAAgKnAuyDgDBAQAfAAgKnAuyDgDBAQAAAA==.',
Jb='Jboom:BAAANQAECgYIDwABNQAECggIJQAJADAgAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jelyl:BAAANQABCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAABNQAECn8iAAIPAAkKHhhQegCJAgAPAAkKHhhQegCJAgAAAA==.',
Jf='Jfôrbj:BAAANQADCgQIBAABNQAECggIJQAJADAgAA==.',
Jo='Johnnysinz:BAABNQAECn8rAAIMAAgK9BzgTQCoAgAMAAgK9BzgTQCoAgAAAA==.Johnnyzyns:BAABNQAECn8cAAMWAAkKbxQBTABDAgAWAAkKbxQBTABDAgAOAAEK5AueJAEmAAABNQAFFAMIAwADAAAAAA==.Johnret:BAAANQAECgcIDwAAAA==.',
Jp='Jp:BAACNQAFFH8aAAIiAAYKfSakAACRAgAiAAYKfSakAACRAgA1AAQKfyMAAiIACQqJJqwAANoDACIACQqJJqwAANoDAAAA.',
Ju='Juhla:BAAANQADCgYIDQAAAA==.Juno:BAAANQADCggIHwAAAA==.',
['Já']='Jáke:BAAANQAECgQIBAAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kahrein:BAAANQAECgIIAgAAAA==.Kaimen:BAAANQAECgYIDQAAAA==.Kainssoul:BAAANQADCgIIAgAAAA==.Kalarin:BAAANQADCgUIBQAAAA==.Kaleb:BAAANQAECgUIBQAAAA==.Kalipriest:BAAANQAECggIDgAAAA==.Kalipso:BAAANQAECgcIEgAAAA==.Kallea:BAAANQADCggICAAAAA==.Kallee:BAAANQADCgEIAQAAAA==.Kalliz:BAAANQADCggIGgAAAA==.Kamehameha:BAAANQAECgYIDwAAAA==.Kamwar:BAACNQAFFH8JAAMfAAUK0xxBAQBMAQAfAAQKqCJBAQBMAQANAAIKjgz9LgCLAAA1AAQKfyIAAx8ACQraJb8AAMADAB8ACQrTJb8AAMADAA0AAwp7Ht3+ANkAAAE1AAUUBwggACMAPiYA.Karideer:BAABNQAECn8UAAIWAAYKwBVTfwCiAQAWAAYKwBVTfwCiAQAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kashulei:BAAANQABCgIIAgAAAA==.Kataraxtis:BAAANQAECgQIBAAAAA==.Kaylax:BAAANQAECgYIEQAAAA==.Kaylost:BAAANQADCgMIBAAAAA==.Kaylub:BAABNQAECn8kAAIQAAgK/BPiZwAgAgAQAAgK/BPiZwAgAgAAAA==.Kazaland:BAAANQADCgYIBwAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECggIEwAAAA==.Kenott:BAAANQAECgIIAwAAAA==.Kenparcell:BAAANQAECgUICAAAAA==.Kerash:BAAANQADCggIMwAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQAECgUIBgABNQAECggIGQAXAJ0XAA==.Kevintt:BAABNQAECn8ZAAMXAAgKnRdwIwDCAQAXAAgKnRdwIwDCAQALAAQKuglU2wDDAAAAAA==.Keys:BAAANQAECgUIDAAAAA==.',
Kh='Kho:BAABNQAECn8WAAIMAAkKgBR+dQA+AgAMAAkKgBR+dQA+AgAAAA==.Khodad:BAAANQAECgIIAgABNQAECgkJFgAMAIAUAA==.Khreegz:BAAANQAECgEIAgAAAA==.Khundalar:BAAANQAECgUIBQAAAA==.',
Ki='Kiarraa:BAAANQAECgQIAwAAAA==.Killachefcjr:BAAANQADCgcIFQAAAA==.Kimi:BAAANQADCgYIBgAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQAECgUIDQAAAA==.Kitana:BAAANQAECgQIBAAAAA==.Kittyvalk:BAAANQADCgQICgAAAA==.',
Kn='Knugget:BAAANQAECgcIEgAAAA==.',
Ko='Kodiakhunter:BAAANQAECgYICQAAAA==.Kodlighting:BAAANQAECgEIAQAAAA==.Kokurai:BAAANQAECgIIAwAAAA==.Komatsu:BAAANQADCgEIAQAAAA==.Koniqeo:BAAANQAECgUICAAAAA==.Koressme:BAAANQADCggIEwAAAA==.Korlat:BAAANQAECgUICAAAAA==.Kovander:BAAANQAECgYIBgAAAA==.Kozdiniar:BAABNQAECn8vAAQaAAkK2COfDgBTAwAaAAkK2COfDgBTAwABAAgKFyLrCwAJAwAEAAEKAACMVABMAAAAAA==.Kozmodai:BAAANQAECggICAABNQAECgkJLwAaANgjAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJLwAaANgjAA==.',
Kr='Kranlem:BAAANQAECgUIBwAAAA==.Krimzin:BAAANQAECgEIAQABNQAFFAUIDAAGAHMbAA==.Kringles:BAAANQAECggIEQAAAA==.Kristree:BAAANQADCgYIDwAAAA==.Krëegz:BAABNQAECn8gAAIGAAkKQRJ2aQA+AgAGAAkKQRJ2aQA+AgAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgkJIAAGAEESAA==.',
Kt='Ktala:BAAANQAECgIIBQAAAA==.',
Ku='Kugot:BAAANQAECggICgAAAA==.Kurupted:BAABNQAECn8aAAIGAAcKgQY/yABsAQAGAAcKgQY/yABsAQAAAA==.',
Ky='Kydrea:BAAANQAECgUIDAAAAA==.Kyne:BAAANQAECgYICgAAAA==.Kynyselda:BAAANQAECgQJBAAAAA==.Kyrabear:BAAANQAECgQIBwAAAA==.Kyrion:BAAANQAECgIIAgAAAA==.',
['Kâ']='Kânê:BAABNQAECn8XAAIMAAcKaR8ggAAkAgAMAAcKaR8ggAAkAgAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larayviana:BAAANQAECgEIAgAAAA==.Larc:BAAANQAECgQIDQAAAA==.Larkos:BAAANQADCgcICgAAAA==.Lassamyna:BAAANQAECgIIAgAAAA==.Latías:BAABNQAECn8fAAIPAAkK2xuldQCSAgAPAAkK2xuldQCSAgAAAA==.',
Le='Leechygos:BAAANQADCggIFQAAAA==.Legenddairy:BAAANQAECgYIDQAAAA==.Legirlas:BAAANQADCgQIBwABNQAECgYIDwADAAAAAA==.Leha:BAAANQAECgUICgAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAABNQAECn8oAAIOAAgKYhkmRwBCAgAOAAgKYhkmRwBCAgAAAA==.Lenorand:BAAANQAECgQIBAABNQAECgUIDgADAAAAAA==.Leushi:BAAANQADCgcIBwAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyarrows:BAAANQAECgcIEQABNQAECgkJKgAUABgaAA==.Lickmyhorns:BAABNQAECn8qAAMUAAkKGBqJHgCiAgAUAAkKGBqJHgCiAgAkAAYKCRB0QwAvAQAAAA==.Liendrah:BAECNQAFFH8PAAIlAAUKEiAYAQCvAQAlAAUKEiAYAQCvAQA1AAQKfyYAAiUACQprIh8DADoDACUACQprIh8DADoDAAAA.Lightbeer:BAAANQABCgMIBQAAAA==.Lightmf:BAAANQAECgcIEgAAAA==.Lightninglip:BAAANQADCgcIFQAAAA==.Lightnleaf:BAAANQAECggICgAAAA==.Lightorange:BAAANQAECgEIAgAAAA==.Lightwaves:BAAANQAECgYICwAAAA==.Lightwhite:BAAANQAECgEIAQAAAA==.Lilet:BAABNQAECn8kAAMCAAgKHhgbDwA2AgACAAgKHhgbDwA2AgANAAEKCwMAYgEfAAAAAA==.Lilfister:BAAANQADCgIIAgAAAA==.Lilitsune:BAAANQAECgUIDgAAAA==.Lilsquishy:BAAANQAECgUIBQAAAA==.Lilthyx:BAAANQADCgIIAgAAAA==.Linareyna:BAAANQADCgIIAgAAAA==.Lionhart:BAAANQAECggIDQABNQAECggIGQAcAFIWAA==.Liotrix:BAAANQADCgYIBgABNQAECgkJIAAGAJYdAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgYIEwAAAA==.Lizolio:BAAANQAECgcIDQAAAA==.',
Ll='Llomel:BAAANQAECgMIBAAAAA==.',
Lo='Lochlan:BAAANQADCggIDwAAAA==.Lohhano:BAAANQABCggIDgAAAA==.Londo:BAAANQADCgcIEwAAAA==.Louanna:BAAANQADCgYIBwAAAA==.',
Lu='Lucianagi:BAAANQAECgYIDAAAAA==.Lucilla:BAAANQADCgcICAAAAA==.Luokang:BAAANQAECggICAAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ly='Lynavas:BAAANQADCgcIEwAAAA==.',
['Là']='Làgs:BAABNQAECn8UAAMcAAgKug+SWgCFAQAcAAcK9hGSWgCFAQAJAAIKsQHv/wATAAABNQAFFAMICQAPABQcAA==.',
Ma='Machiné:BAAANQAECgEIAgABNQAECgEIAQADAAAAAA==.Macnaulty:BAAANQADCggIBgAAAA==.Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAACNQAFFH8HAAIbAAQKAhKfFwAwAQAbAAQKAhKfFwAwAQA1AAQKfycAAhsACQqvIrMKAGsDABsACQqvIrMKAGsDAAAA.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Maibutzfel:BAAANQADCggICQAAAA==.Majamojopowa:BAAANQABCgcIBwAAAA==.Majicman:BAAANQAECgQIBwAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manimal:BAAANQAECgUICQABNQAECgcIEAADAAAAAA==.Mankrikswife:BAAANQADCggIEAABNQAECgcIHQANAA0LAA==.Manutters:BAAANQAECgYIDAAAAA==.Marrylanders:BAACNQAFFH8JAAIPAAMKFBxDLgAVAQAPAAMKFBxDLgAVAQA1AAQKf08AAw8ACQpLJUUSAIoDAA8ACQq2JEUSAIoDABIABAogIkASAIABAAAA.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAABNQAECn86AAMHAAkKayDmCwAaAwAHAAkKayDmCwAaAwAGAAIKox6jMwF3AAABNQAECggIJQAJADAgAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQIBAAAAA==.Mellie:BAAANQAECgQIBgAAAA==.Melmei:BAAANQAECgUIDQAAAA==.Mephixto:BAAANQAECgQIDgAAAA==.Meriweather:BAAANQAECgUIDgAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAABNQAECn8XAAMLAAgK/xUCTQAzAgALAAgK/xUCTQAzAgAMAAQKKwjFPAG4AAABNQAECggIJQAJADAgAA==.Meszyra:BAACNQAFFH8LAAIeAAUKtBOfBACFAQAeAAUKtBOfBACFAQA1AAQKfywAAh4ACQqkG6EIAOsCAB4ACQqkG6EIAOsCAAAA.Meudäil:BAAANQAECgMIAwAAAA==.',
Mg='Mgreenleaf:BAAANQABCgYIEgABNQABCgcIBwADAAAAAA==.',
Mi='Michaelcera:BAABNQAECn8cAAIWAAgKkCBNKgDVAgAWAAgKkCBNKgDVAgAAAA==.Mightymojo:BAAANQADCgYIBgAAAA==.Mijuku:BAABNQAECn8yAAIJAAkKAx6+HQDXAgAJAAkKAx6+HQDXAgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQAECgMIBAAAAA==.Misoeternal:BAAANQAECgUIEgAAAA==.Mistafista:BAAANQAECgIIAgAAAA==.Mistralis:BAAANQAECgQIBwABNQAFFAUICAAPABoSAA==.Mitchard:BAABNQAECn8kAAIKAAkKnQ/BNgD3AQAKAAkKnQ/BNgD3AQAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQAECgMIAwAAAA==.Mizstriss:BAAANQAECgUIBwAAAA==.',
Mo='Molari:BAAANQAECgMIBAAAAA==.Moloyagi:BAAANQABCgIIAgAAAA==.Monksymeg:BAAANQADCgIIBAAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Monterce:BAAANQADCgIIAgAAAA==.Moonfur:BAAANQAECgUIDgAAAA==.Mooseknuck:BAAANQADCgMIAwAAAA==.Mordath:BAAANQAECgUICQAAAA==.Mordetkai:BAAANQADCgYIBgAAAA==.Mordoom:BAAANQAECgUIDgAAAA==.Morikai:BAAANQAECgcIBwAAAA==.Morinn:BAAANQAECgIIAwAAAA==.Mosag:BAABNQAECn8jAAMTAAkKaBrtEQDdAgATAAkKaBrtEQDdAgAbAAcKUB4zWgAPAgAAAA==.Moushou:BAABNQAECn8fAAIEAAcKexJGIQCKAQAEAAcKexJGIQCKAQAAAA==.',
Ms='Mspacman:BAAANQAECgYICAAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAACNQAFFH8FAAIWAAIKcA5MJACYAAAWAAIKcA5MJACYAAA1AAQKfykAAhYACQrqHWggAAcDABYACQrqHWggAAcDAAAA.Muppie:BAAANQADCgQIBQAAAA==.Mutovenator:BAAANQAECgQIBQAAAA==.',
My='Mychef:BAAANQAECgQICAAAAA==.Myrrha:BAACNQAFFH8IAAIeAAQKyRgRBgBLAQAeAAQKyRgRBgBLAQA1AAQKfyYAAx4ACQqYIsAEAEoDAB4ACQqYIsAEAEoDABgABgrBE6gkAJoBAAAA.',
['Mî']='Mîchael:BAAANQADCgIIAgAAAA==.',
['Mï']='Mïsterfox:BAAANQAECgMIBQAAAA==.',
['Mô']='Mônah:BAAANQADCgYICgABNQAECgUIBQADAAAAAA==.',
Na='Nahota:BAAANQAFFAEIAQAAAA==.Nakiro:BAAANQAECgUICgAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Necroussy:BAAANQAECggIAgAAAA==.Nedilap:BAAANQAECggIEQAAAA==.Nef:BAAANQAECgYIDgAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQAECgUIEgAAAA==.Nerovash:BAAANQAECggIBQAAAA==.Nerve:BAAANQAECgcIEAAAAA==.',
Ni='Nightx:BAABNQAECn8VAAMJAAYKBx0eWgCjAQAJAAYKBx0eWgCjAQAKAAEKHg4IqQA1AAAAAA==.Ninn:BAAANQADCgYIBgAAAA==.Nishba:BAAANQADCgMIAwAAAA==.Nishkavel:BAAANQADCgcIEAAAAA==.Nitewang:BAABNQAECn8YAAICAAcK8yUvBgAEAwACAAcK8yUvBgAEAwAAAA==.Nitewing:BAACNQAFFH8aAAIXAAcK2SPMAACnAgAXAAcK2SPMAACnAgA1AAQKfy0AAhcACQpjJr4BAL0DABcACQpjJr4BAL0DAAE1AAQKCAgYAAIA8yUA.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQAECgMIBAAAAA==.Noctaro:BAEBNQAECn8lAAIYAAkKpBW8FABjAgAYAAkKpBW8FABjAgAAAA==.Nokona:BAAANQADCggIEAABNQAECgUIBQADAAAAAA==.Notpizza:BAAANQAECgMIAwABNQAFFAYIDQAPAI4PAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAFFAIIBQAWAHAOAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
['Nø']='Nødiddy:BAAANQAFFAMIAwAAAA==.',
Ob='Obnixa:BAABNQAECn8lAAIGAAkKVyLlGAA1AwAGAAkKVyLlGAA1AwAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCggIGQAAAA==.',
Oh='Ohsora:BAAANQADCgcIBwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECggIKAAOAGIZAA==.',
On='Onfiree:BAAANQAECggJCwAAAA==.',
Op='Opithel:BAABNQAECn8tAAIkAAkKPiWjAQDOAwAkAAkKPiWjAQDOAwAAAA==.Opiurza:BAABNQAECn8aAAIWAAgKnCJwIwD3AgAWAAgKnCJwIwD3AgABNQAECgkJLQAkAD4lAA==.Opizerka:BAAANQAECggIEgABNQAECgkJLQAkAD4lAA==.',
Or='Ordroin:BAAANQADCggICAAAAA==.Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAABNQAECn8dAAIhAAgKxQrlGADSAQAhAAgKxQrlGADSAQAAAA==.Oríllas:BAAANQAECgQICAAAAA==.',
Oy='Oyogo:BAACNQAFFH8QAAIYAAcKDxrkAwA+AgAYAAcKDxrkAwA+AgA1AAQKfyIAAhgACQqlIjoFAFcDABgACQqlIjoFAFcDAAAA.Oyogu:BAAANQADCgUIBQABNQAFFAcIEAAYAA8aAA==.Oyumi:BAACNQAFFH8IAAIBAAMKoxyJCwAEAQABAAMKoxyJCwAEAQA1AAQKfxcAAwEACQrcIkkEAH8DAAEACQrcIkkEAH8DABoAAgpxHgqGALUAAAE1AAUUBwgQABgADxoA.',
Pa='Paech:BAAANQAECgYICgAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBQAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQAECgIIBQAAAA==.Palswarlock:BAAANQAECgQIBAAAAA==.Pamalinaa:BAAANQAECgcIEgAAAA==.Pamplemousse:BAAANQAECggIBwAAAA==.Pandadave:BAAANQADCgYIGAAAAA==.Papanezz:BAAANQAECgQIBgAAAA==.Papasin:BAAANQAECggICAAAAA==.Patapouf:BAAANQAECgIIBwAAAA==.Paulteros:BAAANQADCgMIAwABNQAECggIIgAhAOEUAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgMIBAAAAA==.Pedestal:BAAANQADCggICgAAAA==.Pegully:BAABNQAECn8ZAAIUAAcK4gxZSgB1AQAUAAcK4gxZSgB1AQAAAA==.Pewxtwo:BAAANQADCgYIBwAAAA==.',
Ph='Phephraan:BAABNQAECn8iAAIhAAgK4RRxDwBwAgAhAAgK4RRxDwBwAgAAAA==.Phinehas:BAAANQAECgQICQAAAA==.Phwaz:BAAANQAECgUIEgAAAA==.Phyxyzin:BAAANQADCgUIDQAAAA==.',
Pi='Piccoloo:BAAANQAECgIIAgAAAA==.Piddles:BAAANQADCgYJBgAAAA==.Pikeysham:BAAANQADCgMJAwAAAA==.Pinchebean:BAABNQAECn8ZAAIMAAcK8wzvwACUAQAMAAcK8wzvwACUAQAAAA==.Pinktress:BAABNQAECn8hAAIGAAcK7xMWjwDnAQAGAAcK7xMWjwDnAQAAAA==.Pizzadough:BAACNQAFFH8NAAIPAAYKjg8SFADRAQAPAAYKjg8SFADRAQA1AAQKfyIAAg8ACQqBGNyBAHoCAA8ACQqBGNyBAHoCAAAA.Pizzapurse:BAAANQADCgQIBAAAAA==.',
Pk='Pkcontrol:BAAANQADCgUIBQAAAA==.',
Pl='Plavalagoona:BAAANQADCgMIBAABNQAECggIGwANALETAA==.Plskillmie:BAABNQAECn8bAAMJAAcKigWxjgDoAAAJAAYKKgWxjgDoAAAKAAcKQQNUbwDYAAAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Politics:BAAANQAECggIBgAAAA==.Polygonnacry:BAAANQAECgUIBwAAAA==.Polyhaladin:BAAANQAECgQIBwABNQAFFAIIBQAWAHAOAA==.Popatop:BAAANQADCggIEwAAAA==.Possecutor:BAACNQAFFH8QAAITAAQK2xnwCgA9AQATAAQK2xnwCgA9AQA1AAQKfycAAhMACQogIlMPAPwCABMACQogIlMPAPwCAAAA.Pownadin:BAAANQADCgUICgAAAA==.',
Pr='Prabis:BAAANQAECgUICQAAAA==.Praesidius:BAAANQADCggIEQAAAA==.Priestalama:BAAANQAECgYICwAAAA==.Priestsita:BAAANQAECgcICgAAAA==.Priscillà:BAAANQAECgIIAgABNQAFFAQICAAeAMkYAA==.Pristakos:BAAANQAECgUIBQAAAA==.Promise:BAAANQAECgQIBAAAAA==.Pryîto:BAAANQAECgUIBwAAAA==.',
Pu='Pumachaka:BAAANQAECgQIBwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Pv='Pvp:BAAANQAECgMIAwAAAA==.',
Py='Pyresia:BAAANQAECgQIDQAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAABNQAECn8tAAQGAAgK3SSpFwA6AwAGAAgK3SSpFwA6AwAIAAYKsxblBwDkAQAHAAEKTRcWigAzAAAAAA==.',
Qw='Qwertysquid:BAAANQAECgQIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQAECggIAwABNQAECgkJJQAYAKQVAA==.Raezer:BAEANQADCggICAABNQAECgkJJQAYAKQVAA==.Raiin:BAAANQAECgcIDQABNQAFFAcIGAATAK8aAA==.Raikomori:BAAANQAECggIBwAAAA==.Ralroc:BAAANQADCgcIEAAAAA==.Ranare:BAABNQAECn8YAAQmAAkKVREXCAAaAgAmAAkKVREXCAAaAgAYAAMKWAwsQQCSAAAeAAIKPASnOQA9AAAAAA==.Randomfatguy:BAAANQAECgEIAgAAAA==.Rathrus:BAAANQAECgQICwAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAABNQAECn8ZAAIcAAgKUha/OgAXAgAcAAgKUha/OgAXAgAAAA==.Ravienn:BAAANQAECgQIBgABNQAECggIJQAJADAgAA==.Raxmanus:BAAANQAECgEJAQAAAA==.Rayru:BAAANQAECgIIAgAAAA==.Rayvienne:BAAANQADCgUICQAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQAECgUIEAAAAA==.Reilini:BAABNQAECn8sAAIMAAkK9Bt5TgCmAgAMAAkK9Bt5TgCmAgAAAA==.Remedium:BAAANQABCgYICwAAAA==.Renascor:BAAANQAECgQICgABNQAFFAUIDQAeAC0XAA==.Reàp:BAAANQAECgIIAgAAAA==.',
Rh='Rhojin:BAAANQADCggIFgAAAA==.',
Ri='Rikimaruu:BAABNQAECn8hAAIVAAkKRB2fDAAeAwAVAAkKRB2fDAAeAwAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.Rinsecycle:BAAANQADCggIGAAAAA==.Rivelia:BAAANQAECgIIAwABNQAFFAQICAAeAMkYAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQAECgMIBwAAAA==.Ronek:BAAANQABCgUIBwAAAA==.Rosabella:BAAANQADCgQJBAAAAA==.Roseatrine:BAAANQADCgMIAwABNQAECgkJHwALABEhAA==.Roshisain:BAAANQADCgcICgAAAA==.Rossbob:BAAANQADCgYIBQAAAA==.Rouñders:BAAANQAECgEIAwABNQAFFAcIGAATAK8aAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAABNQAECn8nAAIPAAkKRxaPawCnAgAPAAkKRxaPawCnAgAAAA==.Rueldalf:BAAANQAECgYICwAAAA==.Ruïn:BAAANQADCggIKQAAAA==.',
['Ré']='Réka:BAAANQADCgUICAABNQAECgkJHgAJAPkMAA==.',
['Rô']='Rôôst:BAAANQADCgIIAgAAAA==.Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Saatara:BAAANQADCgYIDQAAAA==.Sacreatia:BAAANQADCgMIAwAAAA==.Sagittarius:BAAANQADCgQIBAAAAA==.Saino:BAAANQAECgEIAQAAAA==.Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgcICQABNQAECgkJKgAPACQeAA==.Samlock:BAACNQAFFH8FAAIRAAIK7BKPCgCnAAARAAIK7BKPCgCnAAA1AAQKfzwAAhEACQpaIH0BAHUDABEACQpaIH0BAHUDAAAA.Sap:BAACNQAFFH8OAAQVAAUKtxR/DwDtAAAdAAMKGBW+CwD5AAAVAAMKKhV/DwDtAAAjAAEKnRFsAwBPAAA1AAQKfyEABBUACQqUICQRAPECABUACQqDICQRAPECACMABgrWFP0NAFwBAB0AAwp3ExI/ALoAAAE1AAQKCAgWAA0AQyUA.Satheriesh:BAAANQADCgUIBQAAAA==.Satyrlord:BAAANQAECgYICAAAAA==.Savella:BAABNQAECn8fAAMiAAkKlBTxEgBKAgAiAAkKlBTxEgBKAgAnAAEKAAApbQAsAAAAAA==.',
Sc='Scaleshot:BAAANQADCgYJBgAAAA==.Scarletblade:BAABNQAECn8yAAMMAAkKHx9BMwD9AgAMAAkKHx9BMwD9AgAXAAQKGBd7OwARAQAAAA==.Schamwoww:BAAANQAECgMIAwAAAA==.Schlam:BAAANQADCggICAAAAA==.Sclas:BAAANQAECgEIAQAAAA==.Scubar:BAAANQAECgUIDQAAAA==.Scuffedcat:BAAANQABCgMIAwAAAA==.',
Se='Seafox:BAAANQAECgIIAwAAAA==.Sear:BAABNQAECn8nAAIkAAkKhRmaGwB3AgAkAAkKhRmaGwB3AgAAAA==.Seasoning:BAAANQADCgIIAgAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selindris:BAAANQAECgUIBQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQADCgUIBQAAAA==.Sephimus:BAAANQADCggIDgABNQAECggIGwAcAOofAA==.Seraphiina:BAABNQAECn8eAAIMAAcK6Ab87wA2AQAMAAcK6Ab87wA2AQAAAA==.Seraphimn:BAAANQADCgEIAQAAAA==.Serbixalot:BAABNQAECn8ZAAIMAAcKbQmT3QBZAQAMAAcKbQmT3QBZAQAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shadowyclaws:BAAANQADCgEIAQAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgUIBgAAAA==.Shararena:BAAANQADCggICAAAAA==.Shataree:BAAANQADCgcICwAAAA==.Shazno:BAAANQAECgIIAgAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCggIDQAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQAECgIIAgABNQAECgkJKgALAP0YAA==.Shox:BAAANQADCgMIAwAAAA==.Shredder:BAAANQAECgEIAgABNQAECggIHgAeAKQQAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sinvalk:BAAANQADCgIIAgAAAA==.Sitaana:BAAANQAECggIEQAAAA==.',
Sk='Skellek:BAAANQADCggICAAAAA==.Skillr:BAABNQAECn8iAAMkAAgKQRWqKQDyAQAkAAcKZxeqKQDyAQAUAAIKgAqIgwBiAAAAAA==.Skyekníght:BAAANQAECgcICwAAAA==.Skysong:BAAANQAECgUICwABNQAFFAQICgAFALgVAA==.',
Sl='Slaa:BAAANQADCgMIAwAAAA==.Sleezyaf:BAABNQAECn8cAAQQAAcKVhWFmgCfAQAQAAYKnRWFmgCfAQARAAMKLAsESgCgAAAZAAEKfxQ8MAA0AAAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAABNQAECn8XAAMfAAgK/x/HCwACAgAfAAcK8RrHCwACAgANAAcKmRbBtgCOAQAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQAECgQICwAAAA==.',
So='Soapyy:BAAANQADCgUIBQAAAA==.Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgUIDgAAAA==.Sollaria:BAAANQADCgYICQAAAA==.Sololvlin:BAAANQAECgIIAgAAAA==.Sololvling:BAABNQAECn8oAAMWAAkKihbsVwAYAgAWAAcK5BnsVwAYAgAhAAQK3BBlJAAPAQAAAA==.Soulcandy:BAAANQADCgEIAQABNQAECgYIDwADAAAAAA==.Sovalyn:BAAANQADCgMIAwAAAA==.Sovereign:BAACNQAFFH8bAAIMAAYKJBy+BAATAgAMAAYKJBy+BAATAgA1AAQKfy0AAgwACQqeItIqABoDAAwACQqeItIqABoDAAAA.',
Sp='Sp:BAAANQAECggIDAAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUICAAAAA==.Spookyloops:BAAANQAFFAEIAQAAAA==.Sproggles:BAAANQAECggIDQABNQAECggIEQADAAAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgcIEgADAAAAAA==.',
St='Stealthfire:BAACNQAFFH8KAAIFAAQKuBWQAQBiAQAFAAQKuBWQAQBiAQA1AAQKfygAAgUACQqFJL8BAK0DAAUACQqFJL8BAK0DAAAA.Sternny:BAAANQAECgIIAgABNQAECgcIFgAOAFMNAA==.Sterny:BAABNQAECn8WAAIOAAcKUw0mlABRAQAOAAcKUw0mlABRAQAAAA==.Stidetroll:BAAANQAECgUIBgAAAA==.Stnnisbrthon:BAAANQADCgQIBAAAAA==.Stormstrikes:BAAANQAECgQIBgAAAA==.Strongw:BAAANQAECggIEAAAAA==.Stul:BAABNQAECn8WAAIkAAcKaQqdOQBzAQAkAAcKaQqdOQBzAQAAAA==.',
Su='Substandard:BAAANQAECgYICQAAAA==.Sugaboomboom:BAAANQAECgIIAQAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQAECgYIEQAAAA==.Sumwun:BAAANQADCggICQABNQAECgYIEQADAAAAAA==.Sunarr:BAABNQAECn8jAAIMAAkKAR1MSQC2AgAMAAkKAR1MSQC2AgAAAA==.Sunkenlily:BAAANQADCgcIDAAAAA==.Superace:BAACNQAFFH8LAAIWAAQKBwu0FAAmAQAWAAQKBwu0FAAmAQA1AAQKfyQAAhYACQrLFn04AJECABYACQrLFn04AJECAAAA.Surachi:BAAANQADCgUIBQAAAA==.Surlee:BAAANQAECgMIBAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQAECgYIEgAAAA==.',
Sw='Swaggernaut:BAAANQAECgMIBQAAAA==.Swiffys:BAABNQAECn8lAAIKAAkKcBSLLgApAgAKAAkKcBSLLgApAgAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Syix:BAAANQADCgYICwAAAA==.Synkadevour:BAAANQAECgUIDAABNQAECgUIEQADAAAAAA==.Synkapriest:BAAANQAECgUIEQAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgUIEQADAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.Syraelyssa:BAAANQABCgEIAQAAAA==.',
Ta='Taappy:BAAANQAECgQICwAAAA==.Tacostuffing:BAAANQADCgYICQAAAA==.Taggs:BAABNQAECn8nAAMTAAkKBRgxFQC1AgATAAkKBRgxFQC1AgAbAAQKxRLBtgDtAAAAAA==.Taggsy:BAAANQAECgcIBwAAAA==.Tail:BAABNQAECn8bAAINAAcKzwkrwwBvAQANAAcKzwkrwwBvAQAAAA==.Tails:BAAANQADCgYIEQAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQAECgYIEwAAAA==.Tanthora:BAAANQAECgEIAQAAAA==.Tao:BAAANQADCgMIAwAAAA==.Tastyfísh:BAAANQADCggICAAAAA==.',
Te='Teddymouse:BAAANQAECggICgAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.',
Th='Thanatóz:BAACNQAFFH8GAAMJAAIK6w96GACUAAAJAAIKlQ56GACUAAAKAAIKKgseFwCCAAA1AAQKfywAAwkACQp6IEokAK4CAAkACQp6IEokAK4CAAoABQrbGYBTAFkBAAAA.Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCggIDgAAAA==.Theblinded:BAAANQADCgQIBAAAAA==.Thebutler:BAABNQAECn8bAAIQAAgKdyJbFgAuAwAQAAgKdyJbFgAuAwABNQAFFAcIGAATAK8aAA==.Thegrimus:BAABNQAECn8qAAIhAAkK9CLjAwBaAwAhAAkK9CLjAwBaAwAAAA==.Thekeres:BAAANQAECgUIBQAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Thorsten:BAAANQAECggIDAABNQAECggIGQAcAFIWAA==.Thrandir:BAAANQAECgUIBQAAAA==.Thrashley:BAAANQADCggICAAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Tigorof:BAAANQABCgIIAgAAAA==.Timøthy:BAABNQAECn8eAAIJAAkK+QwoTQDdAQAJAAkK+QwoTQDdAQAAAA==.Tismtouched:BAAANQAFFAEIAQAAAA==.',
Tk='Tkaniaa:BAAANQADCgQIDwAAAA==.Tkaniy:BAAANQADCgIIAgAAAA==.',
To='Tokeyes:BAABNQAECn8ZAAIQAAgKkgvfjwC6AQAQAAgKkgvfjwC6AQAAAA==.Toost:BAAANQAECgYIDwAAAA==.Torwa:BAAANQAECgIIBQAAAA==.Tossdirt:BAACNQAFFH8ZAAMWAAcKUh8TAQDVAgAWAAcKUh8TAQDVAgAOAAEKHghwLABBAAA1AAQKfygAAxYACQrHJRwIAKYDABYACQrHJRwIAKYDAA4AAQoKCD8lASUAAAAA.Toxle:BAAANQAECgEIAwAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAECNQAFFH8TAAMGAAYKZRdUBgDnAQAGAAYKZhVUBgDnAQAIAAEKmg6DAgBQAAA1AAQKfyAABAYACQq7IRkZADQDAAYACQq7IRkZADQDAAgAAwqjFxsNAPIAAAcAAQp6D8+AAD4AAAE1AAQKCQknAAYANx0A.Trippdaddy:BAAANQAECgIIAgAAAA==.Troubling:BAAANQADCgIIAgAAAA==.Truefaith:BAAANQAECgQIBAAAAA==.Trufflepig:BAAANQAECgMIAwAAAA==.',
Ts='Tserendolgor:BAAANQABCgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.Tullegol:BAAANQAECgIIAgAAAA==.Tunaset:BAAANQAECgUIBQAAAA==.Tunasut:BAAANQADCgcIBwAAAA==.',
Tw='Twinswords:BAAANQAECgEJAQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgQIBAAAAA==.',
Ty='Typhal:BAABNQAECn8hAAIMAAkKZyKZIgA4AwAMAAkKZyKZIgA4AwAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
['Té']='Téllah:BAAANQAECgMIBAAAAA==.',
['Të']='Tëgridy:BAAANQAECgMIAwABNQAECgkJIAAFAHkWAA==.',
Uh='Uhtain:BAAANQAFFAEIAQABNQAECgcICQADAAAAAA==.Uhtan:BAABNQAECn8UAAIMAAcKrRjYjwAAAgAMAAcKrRjYjwAAAgABNQAECgcICQADAAAAAA==.',
Ul='Uleo:BAAANQADCgMIAwAAAA==.',
Un='Uncleklaus:BAABNQAECn8qAAIMAAkK3yF6MAAFAwAMAAkK3yF6MAAFAwAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgYIEgAAAA==.',
Us='Ushiamdi:BAABNQAECn8iAAIEAAgKGh7ZCwCoAgAEAAgKGh7ZCwCoAgAAAA==.',
Ut='Utaan:BAAANQAECgcICQAAAA==.',
Va='Vaduh:BAAANQADCgQIBAAAAA==.Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgIIAQABNQAECgIIAwADAAAAAA==.Valanthé:BAAANQADCgYIEAAAAA==.Vandrey:BAAANQAECgMIAwAAAA==.Vazen:BAAANQADCggIGwAAAA==.',
Ve='Velarasta:BAAANQADCgYIDQAAAA==.Veluna:BAAANQABCgMIAwABNQAECgkJHwALABEhAA==.Veravvang:BAAANQAECgQIBwABNQAECggICgADAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQAECgUIBQAAAA==.Versadeus:BAAANQADCgYIBgAAAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vh='Vhail:BAAANQAECggIAgAAAA==.',
Vi='Vihahowl:BAAANQADCgcICAAAAA==.Vinee:BAAANQADCgcJBwABNQAECgkJKwAGADMhAA==.Vinladen:BAAANQADCgMIAwABNQAECggIHgAVAJkfAA==.Violetta:BAAANQADCgcIBAAAAA==.Violettcloud:BAAANQAECgMIBAABNQAECgkJOAAaAD4jAA==.Virali:BAABNQAECn8hAAIXAAkK/xE7IwDEAQAXAAkK/xE7IwDEAQAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAABNQAECn8aAAIVAAgK2Bl5JABgAgAVAAgK2Bl5JABgAgAAAA==.Viviean:BAAANQAECgIIAgAAAA==.Vixenvalk:BAAANQADCgQIBwAAAA==.Viyinx:BAAANQAECgcIDgABNQAFFAIIBgAJAOsPAA==.Vizuel:BAAANQADCgUIDwABNQAECgIIAwADAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Voodoochef:BAAANQAECgIIAgAAAA==.Vorel:BAAANQAECgQIBAAAAA==.',
Vp='Vpung:BAABNQAECn8cAAIUAAUKRQJoeQCLAAAUAAUKRQJoeQCLAAAAAA==.',
Vy='Vyllin:BAABNQAECn8mAAIXAAkKTh43DgC1AgAXAAkKTh43DgC1AgAAAA==.Vynarran:BAAANQAECgcIDwAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warob:BAAANQAECggIDAAAAA==.Warringmyer:BAABNQAECn8YAAINAAYKZBqkngDLAQANAAYKZBqkngDLAQAAAA==.Warriorlol:BAABNQAECn8WAAINAAgKQyV1MAD6AgANAAgKQyV1MAD6AgAAAA==.Watchdodo:BAAANQAECgQIDAAAAA==.Wax:BAAANQAECgMJAgAAAA==.',
We='Weebscum:BAABNQAECn8tAAMMAAkKyhNjgwAdAgAMAAkKyhNjgwAdAgAXAAMKSwbhWgBsAAAAAA==.',
Wh='Whoyoumadat:BAAANQADCgUIBQAAAA==.',
Wi='Wiket:BAAANQABCgQIBAAAAA==.Wildestspice:BAABNQAECn8iAAMaAAkKhhoMJwCZAgAaAAkKhhoMJwCZAgABAAcK/RaMJQDzAQABNQAFFAUIDQALAAAYAA==.Willowblessu:BAABNQAECn87AAIoAAkKdR3gAQAaAwAoAAkKdR3gAQAaAwAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQAECgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQAECgEIAQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Wovenxlight:BAAANQAECgQIBAAAAA==.',
Wr='Wranglep:BAAANQADCggIEQAAAA==.Wrathin:BAAANQAECgQIBAAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Wu='Wufel:BAAANQAECgYJCQAAAA==.',
Xa='Xaeora:BAABNQAECn8bAAILAAkKzw6jWwADAgALAAkKzw6jWwADAgAAAA==.Xawne:BAAANQAECgUIBgAAAA==.',
Xe='Xeona:BAAANQADCgYJFAAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Xi='Xicalli:BAAANQAECgEIAQAAAA==.',
Ya='Yadhnak:BAAANQADCgQIBAAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yemii:BAAANQAECgMIBQAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yi='Yikes:BAAANQADCgEIAQAAAA==.',
Yo='Yorichef:BAAANQAECgQICQAAAA==.Yoshikawa:BAEBNQAECn81AAMWAAkKAyK0EwBSAwAWAAkKAyK0EwBSAwAOAAYKlxKPiABxAQAAAA==.',
Yr='Yrac:BAAANQAECgEIAQABNQAECggIAQADAAAAAA==.',
Ys='Ysora:BAAANQADCgMIAwAAAA==.',
Za='Zaerath:BAAANQAECgMIBQAAAA==.Zaivama:BAAANQAECgMIAwAAAA==.Zandren:BAAANQAECgQIBAAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAACNQAFFH8IAAIPAAUKGhJoHwCEAQAPAAUKGhJoHwCEAQA1AAQKfxwAAw8ACQpkIiY9AAwDAA8ACQpkIiY9AAwDABIAAgoiF44vAH8AAAAA.',
Ze='Zeenaheals:BAAANQAECggIDgABNQAECggIHgAeAKQQAA==.Zeenalizard:BAABNQAECn8eAAMeAAgKpBDNEgAgAgAeAAgKpBDNEgAgAgAYAAUKIwp3NwDVAAAAAA==.Zegoo:BAABNQAECn8cAAIMAAgKERb9egAxAgAMAAgKERb9egAxAgAAAA==.Zendezit:BAAANQAECgQIBgAAAA==.Zenet:BAAANQAECgUIBQAAAA==.Zenomage:BAAANQABCgQICAAAAA==.Zenthura:BAAANQADCgIIAgABNQAFFAUICAAPABoSAA==.Zenïca:BAAANQAECgMIAwAAAA==.Zewz:BAAANQAECggIBgAAAA==.',
Zi='Zilis:BAAANQAECgQIBQAAAA==.Zimbadah:BAAANQAECgEJAQAAAA==.',
Zn='Znny:BAABNQAECn8vAAIfAAkKpx1+AwAdAwAfAAkKpx1+AwAdAwAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAABNQAECn8yAAMQAAkKPiHTMADCAgAQAAgKPCHTMADCAgARAAQK2R17JQBGAQAAAA==.Zyrb:BAAANQADCggICwAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQAECgQIDwAAAA==.',
['Âr']='Ârthas:BAAANQAECgcICgAAAA==.',
['Çl']='Çlutch:BAAANQAECgIIAwAAAA==.',
['Çr']='Çrimes:BAABNQAECn8eAAIGAAkKGhABawA6AgAGAAkKGhABawA6AgAAAA==.',
['Çu']='Çutty:BAAANQAECggIEwAAAA==.',
['Ðo']='Ðom:BAAANQABCgQIBAAAAA==.',
['ßâ']='ßâßygirl:BAAANQAECgUICwAAAA==.',
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
