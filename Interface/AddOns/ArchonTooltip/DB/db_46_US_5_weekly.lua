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

local lookup = {'Mage-Frost','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warrior-Fury','Unknown-Unknown','Paladin-Retribution','Shaman-Enhancement','Shaman-Restoration','Priest-Holy','Paladin-Holy','Druid-Restoration','DeathKnight-Blood','Warrior-Protection','Shaman-Elemental','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Mage-Arcane','Paladin-Protection','Priest-Discipline','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','DemonHunter-Devourer','Monk-Brewmaster','Monk-Windwalker','Warrior-Arms','Priest-Shadow','DeathKnight-Frost','Rogue-Outlaw','Evoker-Preservation','Hunter-Survival','DemonHunter-Havoc','Warlock-Affliction','DemonHunter-Vengeance',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abuum:BAAALgADCgYJBgABLgAFFAMJCAABABMDAA==.',
Ac='Acronica:BAAALgAECgEJAwAAAA==.Acropora:BAABLgAFFH8FAAMCAAMJ3gMOEABJAAADAAIJAQMPKQBNAAACAAMJ3gMOEABJAAAAAA==.',
Ad='Adagar:BAAALgAECgYJDgAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAQJBwAEAHgXAA==.Aethandor:BAAALgAECgUJDQAAAA==.',
Ai='Ainslie:BAAALgADCgEJAQAAAA==.',
Ak='Akassa:BAABLgAECn8hAAIFAAcJygvoWwDiAAAFAAcJygvoWwDiAAAAAA==.Akavaleera:BAAALgAECgQJBwAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwAGAAAAAA==.Akíto:BAAALgAECgcJDQAAAA==.',
Al='Alaric:BAAALgADCgUJBQAAAA==.Alecto:BAABLgAECn8ZAAIHAAkJFAuniABfAQAHAAkJFAuniABfAQAAAA==.Algo:BAABLgAECn8aAAMIAAkJVwTKHAAYAQAIAAkJVwTKHAAYAQAJAAcJYwTkggDZAAAAAA==.Allet:BAAALgAECgUJCAABLgAECgkJEgAGAAAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amalthea:BAAALgAECgQJCQAAAA==.Amarah:BAACLgAFFH8bAAIKAAMJBiUwEgA7AQAKAAMJBiUwEgA7AQAuAAQKf0cAAgoACQnwHmwMAKACAAoACQnwHmwMAKACAAAA.Amarak:BAAALgADCgEJAQAAAA==.Ameilie:BAAALgAECgYJDAAAAA==.Ammathos:BAAALgAFFAkJAwAAAA==.',
An='Anapuwae:BAAALgAECgYJCwAAAA==.Andron:BAAALgADCgQJBAAAAA==.Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgIJAwAAAA==.Ankoki:BAAALgADCggJCAAAAA==.',
Ap='Applemonster:BAAALgAECggJEAAAAA==.',
Ar='Aragörn:BAAALgAFFAEJAQAAAA==.Arboghast:BAAALgAECgUJCAAAAA==.Argadin:BAABLgAFFH8FAAIHAAQJ7AOagAC1AAAHAAQJ7AOagAC1AAAAAA==.Argdru:BAAALgAECgYJDQABLgAFFAQJBQAHAOwDAA==.Arglock:BAAALgADCgIJAgABLgAFFAQJBQAHAOwDAA==.Argrekd:BAAALgADCgMJAwABLgAFFAQJBQAHAOwDAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgIJAwAAAA==.Arknox:BAABLgAECn8dAAMLAAkJJQ2aLgCiAQALAAkJJQ2aLgCiAQAHAAEJEAuHqwEqAAAAAA==.Arrogant:BAAALgADCgIJAgAAAA==.Arthaslk:BAAALgAECgcJEAABLgAECgcJFwAFABYYAA==.Aryssol:BAAALgAECgEJBgAAAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAcJIQAMAIAbAA==.Ashallel:BAAALgAECgQJBAABLgAFFAcJIQAMAIAbAA==.Ashclaw:BAAALgAECgEJAQAAAA==.Ashx:BAAALgADCgIJBAABLgAECgkJIAABAKoXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Ate:BAABLgAECn85AAINAAgJ8BuKDwATAgANAAgJ8BuKDwATAgABLgAECgcJLgAOAB0cAA==.Atlette:BAACLgAFFH8RAAIKAAUJFyEHDACKAQAKAAUJFyEHDACKAQAuAAQKfyoAAgoACQluH2MCAEUDAAoACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8OAAIEAAQJmRDBHgAjAQAEAAQJmRDBHgAjAQAuAAQKf1EAAgQACQmZIswQABcDAAQACQmZIswQABcDAAEuAAUUCAkxAAgAJxcA.Attman:BAACLgAFFH8dAAIJAAUJMx4IHACLAQAJAAUJMx4IHACLAQAuAAQKfx4AAwkACAkSHAobAHMCAAkACAkSHAobAHMCAA8AAwlFAzyEADoAAAAA.',
Au='Augtism:BAAALgAECgYJBgAAAA==.Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgAECgQJBQABLgAECgYJEQAGAAAAAA==.',
Az='Azael:BAAALgAECgEJAQAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Baldsmon:BAAALgAECgUJBQAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAABLgAECgcJLgAOAB0cAA==.Ballsofire:BAABLgAECn8uAAIOAAcJHRxPFACsAQAOAAcJHRxPFACsAQAAAA==.Balstir:BAAALgADCgkJCQAAAA==.Basherz:BAAALgAECgQJBgAAAA==.Baus:BAAALgAECgEJAgAAAA==.',
Be='Bearmane:BAABLgAECn8VAAMCAAcJHB8XEgCZAQACAAUJUSMXEgCZAQAQAAYJpxhVHwBSAQAAAA==.Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAABLgAECn8pAAMRAAkJGhQ6CADKAQARAAgJgxQ6CADKAQASAAcJygfDOADuAAAAAA==.Belithel:BAABLgAECn8gAAIBAAkJqhcFdgDmAQABAAkJqhcFdgDmAQAAAA==.Bencreepin:BAABLgAECn8nAAINAAkJrRgUAwAFAgANAAkJrRgUAwAFAgAAAA==.Beniz:BAACLgAFFH8HAAITAAMJ1wJGkwCbAAATAAMJ1wJGkwCbAAAuAAQKfyAAAxMACAkWCT+NACABABMACAmMCD+NACABABQAAgkFCcdaAF4AAAAA.Bernoulli:BAABLgAECn8fAAIVAAkJOhm+HwAdAgAVAAkJOhm+HwAdAgAAAA==.Bestiaalfa:BAAALgAECgQJBAAAAA==.Bettyford:BAAALgAECgcJBgAAAA==.',
Bi='Bigblunts:BAAALgADCgEJAgAAAA==.Bigcrunch:BAAALgAECggJCQAAAA==.Bigdabs:BAAALgAECgYJBgAAAA==.Bignative:BAAALgAECgYJCAAAAA==.Bigrockbiter:BAAALgAECgIJAgABLgAECgkJEQAGAAAAAA==.Bigspitter:BAABLgAFFH8GAAIEAAMJ7RkjMgALAQAEAAMJ7RkjMgALAQABLgAFFAcJEwAWAJoYAA==.Bironic:BAAALgAFFAIJAgAAAA==.',
Bl='Bloodbones:BAAALgADCgYJBgAAAA==.Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAABLgAFFH8LAAILAAcJ5BtNBAAyAgALAAcJ5BtNBAAyAgABLgAFFAkJTQAVACclAA==.Bloodymyst:BAABLgAFFH9NAAIVAAkJJyV3AACsAwAVAAkJJyV3AACsAwAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boethius:BAAALgAECgMJBQABLgAECgkJEgAGAAAAAA==.Boopsnoopems:BAABLgAECn8yAAIXAAkJxxW8AgDXAQAXAAkJxxW8AgDXAQAAAA==.Borderline:BAAALgADCgYJBgABLgAFFAgJIwAYACQNAA==.Bowlful:BAAALgAECgEJAQABLgAECgkJEgAGAAAAAA==.',
Br='Braileth:BAAALgAECgYJCAAAAA==.Briannajade:BAABLgAECn8gAAIBAAgJygh6nABBAQABAAgJygh6nABBAQAAAA==.Brisha:BAACLgAFFH8rAAILAAkJzx62BgBeAgALAAkJzx62BgBeAgAuAAQKfzMAAwsACQlIJHQAALUDAAsACQlIJHQAALUDABcAAQk8EhBPADQAAAAA.Britti:BAAALgADCgYJBgAAAA==.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgAFFAEJAQAAAA==.Bruisedsky:BAAALgAECgMJAwABLgAFFAcJCwAZAL4gAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAFFAQJBwAEAH8PAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMaAAgJex24DgDFAgAaAAgJex24DgDFAgAbAAYJag3uTwAPAQABLgAFFAQJBwAEAH8PAA==.',
By='Byron:BAAALgAECgcJDQAAAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIMAAkJ1SKyAQCJAwAMAAkJ1SKyAQCJAwAAAA==.Calene:BAACLgAFFH8VAAIRAAQJ+hozAgATAQARAAQJ+hozAgATAQAuAAQKfxkAAhEABwliHLgIAL0BABEABwliHLgIAL0BAAAA.Cammi:BAABLgAECn8aAAILAAYJKRo0LgCkAQALAAYJKRo0LgCkAQAAAA==.Cammywammy:BAABLgAECn8fAAIJAAgJehb0KAAaAgAJAAgJehb0KAAaAgAAAA==.Candy:BAAALgAECgEJAQAAAA==.Carlyyrae:BAACLgAFFH8FAAIJAAMJFQm2NAB3AAAJAAMJFQm2NAB3AAAuAAQKfy0AAwkACQmlHBUMAPoCAAkACQmlHBUMAPoCAA8AAgnHAvu+AB8AAAAA.Casare:BAABLgAECn8hAAIbAAcJEBHFGADrAAAbAAcJEBHFGADrAAAAAA==.Catjam:BAABLgAFFH8GAAIHAAQJEyCaLQBZAQAHAAQJEyCaLQBZAQABLgAFFAkJWgAcAP4kAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celestinee:BAAALgAECgEJAgAAAA==.Celithe:BAABLgAECn8cAAIdAAgJuw9oZgBaAQAdAAgJuw9oZgBaAQABLgAECgkJOwABACgZAA==.Celyda:BAAALgADCgcJBwAAAA==.Cenarian:BAAALgADCgEJAQAAAA==.',
Ch='Chabotloe:BAAALgAECgYJCgAAAA==.Chantriss:BAAALgAECgQJBAAAAA==.Chape:BAACLgAFFH8OAAIVAAcJcBCiHwByAQAVAAcJcBCiHwByAQAuAAQKfzkABBUACQnCIZwGADkDABUACQnCIZwGADkDAB4ABglKGTQmAH0BAB8ABAlHGcpEAOwAAAAA.Chapito:BAAALgAECgcJCAAAAA==.Chi:BAAALgAFFAIJAgABLgAFFAMJGwAKAAYlAA==.Chipmonked:BAABLgAECn9CAAQeAAkJlAyiJgB6AQAeAAkJ1wuiJgB6AQAfAAYJmQtXSgDYAAAVAAUJIwPLUACQAAAAAA==.Chlop:BAABLgAECn8ZAAIEAAgJcBx0HADUAgAEAAgJcBx0HADUAgAAAA==.Chochalinda:BAAALgAFFAEJAgAAAA==.Chopper:BAAALgAECgIJAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn84AAMZAAkJZAnaCgBtAQAZAAkJZAnaCgBtAQAcAAEJvwBYqQAHAAAAAA==.',
Cl='Clawhalla:BAAALgAECgcJEQAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECggJDAAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgcJDQABLgAFFAEJAQAGAAAAAA==.Confronter:BAAALgAECgMJBwAAAA==.Cong:BAABLgAFFH8MAAIgAAQJGhYVFwAnAQAgAAQJGhYVFwAnAQABLgAFFAYJHwAdAFAeAA==.Congdh:BAACLgAFFH8fAAIdAAYJUB5OCAChAQAdAAYJUB5OCAChAQAuAAQKfyUAAh0ACQkPJMkKAPMCAB0ACQkPJMkKAPMCAAAA.Congore:BAABLgAFFH8MAAIEAAQJRxBtSgDGAAAEAAQJRxBtSgDGAAABLgAFFAYJHwAdAFAeAA==.Conmann:BAAALgAECgYJEgAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAABLgAECgkJHQALACUNAA==.Crossy:BAAALgAECgQJBQAAAA==.Crowdad:BAAALgAECgkJBwAAAQ==.Cryogenic:BAABLgAECn8WAAIBAAcJoQhxKwCoAAABAAcJoQhxKwCoAAAAAA==.Cryptex:BAAALgADCgEJAQABLgAFFAEJAQAGAAAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAABLgAECn8cAAIUAAkJfQ6xCwCEAQAUAAkJfQ6xCwCEAQAAAA==.',
Da='Daak:BAAALgAECgEJAQABLgAECgkJSAAeAOoUAA==.Daangalangg:BAABLgAFFH8IAAIVAAIJFhaKLQBzAAAVAAIJFhaKLQBzAAAAAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Dabthorne:BAAALgADCgEJAgAAAA==.Daegra:BAABLgAECn8VAAMRAAkJZBpCBgAHAgARAAYJtR1CBgAHAgASAAgJtA98JABxAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAACLgAFFH8IAAIEAAQJaBG8fQALAQAEAAQJaBG8fQALAQAuAAQKfxgAAgQACQmxHh9DAPkBAAQACQmxHh9DAPkBAAAA.Darkacedia:BAABLgAECn8jAAMTAAgJLh9bHQCmAgATAAgJLh9bHQCmAgAUAAMJyQ9aQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Darkzach:BAABLgAFFH8FAAIEAAMJ8RixNQD+AAAEAAMJ8RixNQD+AAAAAA==.Darkzetta:BAAALgAECgQJAQABLgAFFAcJHgAhAGsQAA==.Datbish:BAAALgAECgkJEQAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAABLgAECn8gAAMEAAcJPSH3NgAjAgAEAAcJPSH3NgAjAgAiAAUJxiBBDwCBAQAAAA==.Deadcells:BAABLgAECn8UAAIgAAcJ+h0yEADuAQAgAAcJ+h0yEADuAQABLgAECgcJIAAEAD0hAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAABLgAFFH8FAAIEAAIJbxYx1QCMAAAEAAIJbxYx1QCMAAAAAA==.Deadlyhoof:BAAALgAECgcJBwAAAA==.Dealosed:BAACLgAFFH8PAAMRAAYJJQ50BQAoAQARAAUJmxF0BQAoAQASAAQJ+wkYDwD/AAAuAAQKfzQABBEACQkvI2gBAP0CABEACQm7ImgBAP0CABIABwnOIMoRAJECACMABgllHtwHALsBAAAA.Decrepit:BAABLgAECn8vAAIEAAkJbhqgKQBaAgAEAAkJbhqgKQBaAgAAAA==.Defect:BAAALgAECgQJBgAAAA==.Defy:BAAALgAECgYJEgAAAA==.Delenn:BAAALgAFFAIJAgAAAA==.Demonclawz:BAABLgAECn8VAAITAAgJGgwxcwBTAQATAAgJGgwxcwBTAQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Deo:BAAALgAECggJCAAAAA==.Dex:BAAALgAECgEJAQAAAA==.Deyast:BAAALgADCgYJBgAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diddious:BAAALgADCgMJBQAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgAECgQJBAABLgAFFAYJCgANABcJAA==.Disastasmite:BAAALgAECgEJAQABLgAFFAYJCgANABcJAA==.Dive:BAACLgAFFH8JAAIBAAQJTSB9RgBZAQABAAQJTSB9RgBZAQAuAAQKfyUAAwEACQklIuwmANcCAAEACQlhHewmANcCABYABQnyHHwLAB8BAAAA.Dizzy:BAAALgAFFAEJAQABLgAFFAcJHgAhAGsQAA==.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIeAAkJkhwxDgCxAgAeAAkJkhwxDgCxAgABLgAECgIJAwAGAAAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAACLgAFFH8FAAIFAAEJLhvyMQBNAAAFAAEJLhvyMQBNAAAuAAQKfzAAAgUACQkjGTcbABQCAAUACQkjGTcbABQCAAAA.Doogtoo:BAAALgAECgEJAQABLgAFFAEJBQAFAC4bAA==.Doogtwo:BAABLgAECn8WAAMJAAgJBRc8CADGAQAJAAgJBRc8CADGAQAPAAEJ+QinMQAgAAABLgAFFAEJBQAFAC4bAA==.Dotproduct:BAAALgAECggJCAABLgAECgcJGAAdAIMiAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAAGAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCwAAAA==.Dragonchape:BAAALgAECgEJAQAAAA==.Dragoneggs:BAACLgAFFH8UAAMcAAMJcxnrPgDMAAAcAAMJcxnrPgDMAAAkAAMJCw1NEwB1AAAuAAQKfycAAxwACQnaHuwIAOkCABwACQnaHuwIAOkCACQABwkZE6EaADABAAAA.Dragonforce:BAAALgAECgYJDAABLgAECgkJEQAGAAAAAA==.Drakkoh:BAAALgAECgUJBgABLgAFFAIJAgAGAAAAAA==.Dratinì:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8vAAIhAAkJ3CPtBQD0AgAhAAkJ3CPtBQD0AgAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drrippy:BAABLgAFFH8HAAIFAAQJ3Rz8KwAEAQAFAAQJ3Rz8KwAEAQAAAA==.Drunkenutz:BAABLgAECn81AAMVAAkJlRxQBAAdAgAVAAgJzx5QBAAdAgAeAAgJhRZlIACkAQAAAA==.Dräx:BAAALgAECgkJAQAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAgJIwAYACQNAA==.Dundo:BAAALgAFFAIJAgABLgAFFAMJDwAPAFUeAA==.',
Dy='Dyab:BAAALgAECgEJAQAAAA==.',
['Dä']='Dälf:BAACLgAFFH8FAAICAAUJ6hyrAgBbAQACAAUJ6hyrAgBbAQAuAAQKfxwAAwIABwmcIWULAAoCAAIABgluI2ULAAoCAAwABgktEN9YAEgBAAEuAAUUCQlKABkAUSEA.',
Ea='Eatinoreos:BAABLgAECn8UAAIDAAkJ/BubCwCbAgADAAkJ/BubCwCbAgAAAA==.',
Ec='Echidona:BAABLgAECn8bAAISAAgJERn8EwB2AgASAAgJERn8EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAAALgAECgQJBAABLgAFFAcJFgATAGYjAA==.',
El='Elenix:BAABLgAECn8aAAMPAAkJyRy0CAAGAwAPAAkJyRy0CAAGAwAJAAMJhA3zgACQAAABLgAFFAMJBgALABghAA==.Elinras:BAACLgAFFH8RAAIHAAQJEgodTAB9AAAHAAQJEgodTAB9AAAuAAQKfzMAAgcACQnXGd8NAIsBAAcACQnXGd8NAIsBAAAA.Elliott:BAAALgADCgMJBQABLgADCggJDQAGAAAAAA==.Elmesia:BAAALgAECgkJAwAAAA==.Elonsalt:BAAALgAECgcJEAAAAA==.Eloris:BAABLgAECn8YAAIdAAgJHhY3RQC3AQAdAAgJHhY3RQC3AQAAAA==.Elrizon:BAAALgAECgYJCwAAAA==.Elvar:BAAALgAECggJDwABLgAECgQJBQAGAAAAAA==.Elwynbria:BAAALgADCgcJBwAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIKAAcJ2RUIIADhAQAKAAcJ2RUIIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAACLgAFFH8MAAIjAAMJVR9cCAD6AAAjAAMJVR9cCAD6AAAuAAQKfysAAiMACAlqIuUAAAwDACMACAlqIuUAAAwDAAAA.',
En='Endboss:BAAALgAECgUJBQAAAA==.Enfuega:BAAALgAECgQJDQAAAA==.Eniar:BAACLgAFFH8SAAMLAAcJXwdxEAD2AAALAAcJXwdxEAD2AAAHAAIJCgKfZQBNAAAuAAQKfxwAAwsACAnHFLguAMgBAAsACAnHFLguAMgBAAcABAl0CTDvALIAAAAA.',
Er='Eroninja:BAAALgAECgQJCAABLgAECgkJIAABAKoXAA==.',
Eu='Eurong:BAACLgAFFH8UAAIDAAYJuBfnFAB0AQADAAYJuBfnFAB0AQAuAAQKfxwAAgMACQmhH0waADICAAMACQmhH0waADICAAAA.',
Ev='Evangelune:BAABLgAECn8xAAIBAAkJhAc+FwAhAQABAAkJhAc+FwAhAQAAAA==.Evotroxx:BAAALgADCgMJAwABLgAFFAgJMQAIACcXAA==.Evral:BAAALgAECgcJCgAAAA==.',
Ew='Ewright:BAAALgAECgEJAQABLgAECgkJGgAhAP8fAA==.',
Ez='Ezynuff:BAABLgAECn8wAAMJAAkJ3RiuGgB1AgAJAAkJ3RiuGgB1AgAPAAUJKQgicQCXAAAAAA==.',
['Eï']='Eïr:BAAALgAECgMJAwAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAATACIfAA==.Fapple:BAABLgAECn8lAAMMAAgJxxniHQBXAgAMAAgJxxniHQBXAgADAAcJPxW+KQCFAQABLgAECgkJQAAkACkkAA==.Fatesworn:BAAALgAECgMJBQAAAA==.Faïry:BAACLgAFFH8nAAMaAAcJ8BhqGACnAQAaAAcJeBhqGACnAQAlAAMJTwuxJACtAAAuAAQKfzMAAxoACQkxHcoRAKoCABoACAmpH8oRAKoCACUABgkUCjYjALYAAAAA.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felalle:BAAALgADCgYJBgAAAA==.Felfrostette:BAAALgAECgEJAQAAAA==.Felheart:BAABLgAECn8qAAImAAkJqRiVAgA/AgAmAAkJqRiVAgA/AgAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgkJNQAVAJUcAA==.Felwyrm:BAAALgAECgYJDAABLgAFFAgJIwAYACQNAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAABLgAFFH8GAAIMAAIJuQ0hWABpAAAMAAIJuQ0hWABpAAAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgcJCgAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAACLgAFFH8GAAIcAAQJPwzGJQCRAAAcAAQJPwzGJQCRAAAuAAQKfx0AAyQACAkRDmkkAFUBACQABwkuDGkkAFUBABwACAkmDkQ+ADEBAAAA.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJLgAOAB0cAA==.Forrestpump:BAAALgADCgMJAwAAAA==.',
Fr='Fries:BAECLgAFFH8HAAITAAQJpg+IZQD7AAATAAQJpg+IZQD7AAAuAAQKfyQAAxMACAkDJKEUAKoCABMACAkDJKEUAKoCABQAAQmHGhtgAE8AAAEuAAUUBgkMAAgA2R8A.Frostwarlock:BAAALgADCgQJBAAAAA==.Frozenpyre:BAAALgAECgYJEQAAAA==.',
Fu='Funch:BAACLgAFFH8VAAMUAAMJoxD5DADQAAAUAAMJoxD5DADQAAAnAAIJ/AxlCQCRAAAuAAQKfzQAAhQACQk8G3cDAF8CABQACQk8G3cDAF8CAAAA.',
['Fè']='Fènrir:BAAALgAECgYJCAABLgAECgkJGgAhAP8fAA==.',
Ga='Gabbathegoo:BAACLgAFFH8KAAMUAAcJ3A0aDABjAAATAAUJ+wsXfQDKAAAUAAIJnhEaDABjAAAuAAQKfxoABBMACQkVHlkYAJICABMACQl3HVkYAJICACcAAQn0IxoMAGoAABQAAgnAAlcXAA0AAAAA.Gainz:BAAALgAFFAMJAwAAAA==.Gainzz:BAAALgAECgQJBgAAAA==.Galesdeyn:BAABLgAECn8WAAIdAAcJQhdRWQB7AQAdAAcJQhdRWQB7AQAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAABAD4dAA==.Garonnaa:BAABLgAFFH8RAAINAAcJrAodJgDBAAANAAcJrAodJgDBAAAAAA==.',
Gh='Ghari:BAABLgAECn8oAAIEAAgJpROkgQBgAQAEAAgJpROkgQBgAQAAAA==.',
Gi='Gilrog:BAABLgAECn8bAAIEAAcJDA+FmwAzAQAEAAcJDA+FmwAzAQAAAA==.Gingerlock:BAAALgAECgUJCgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.Glizzbox:BAAALgADCgEJAQABLgAECgcJHgAnAAMgAA==.Gloryseeker:BAAALgAECgEJAQAAAA==.',
Gn='Gnnz:BAAALgAECgYJBwAAAA==.Gnoblin:BAAALgAECgQJCAAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.Gorerich:BAAALgADCgIJAgAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAABLgAECn9UAAIPAAkJ9RX/AwD5AQAPAAkJ9RX/AwD5AQAAAA==.Greyer:BAABLgAFFH8FAAMEAAMJkgyoqQDKAAAEAAMJegyoqQDKAAAiAAEJYgmnHwA5AAABLgAFFAMJCwAgALsiAA==.Greylooms:BAACLgAFFH8LAAMgAAMJuyKkGwANAQAgAAMJuyKkGwANAQAFAAEJHRgBUgBHAAAuAAQKfzIAAyAACQkwIVsDAPwCACAACQkwIVsDAPwCAAUABgmEHekyAOABAAAA.Griplock:BAABLgAECn8tAAMEAAkJrhkEBgAbAgANAAkJXRbKAgAgAgAEAAkJqxUEBgAbAgAAAA==.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Hammerdon:BAAALgAECgQJCAAAAA==.Happyfriend:BAACLgAFFH8jAAMYAAgJJA2HFADyAAAYAAgJJA2HFADyAAAhAAEJZABFQgAvAAAuAAQKfysABBgACQnzGBAbAPcBABgACQnzGBAbAPcBACEABwmiEX8kALQBAAoAAQkPCkV2ACQAAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellaholy:BAAALgADCgYJBgAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwABLgAECgkJHQALACUNAA==.Heàl:BAABLgAECn8aAAMhAAkJ/x9bDgBwAgAhAAkJ/x9bDgBwAgAYAAEJFgcQgwApAAAAAA==.',
Hi='Hidejames:BAABLgAECn8yAAMRAAkJbxjhAwBnAgARAAkJbxjhAwBnAgASAAMJEQaNVQBSAAAAAA==.Hidolo:BAAALgAECgMJAwAAAA==.Hims:BAABLgAECn8ZAAMdAAYJFiEYNwAaAgAdAAYJFiEYNwAaAgAoAAEJtRxSKABFAAABLgAFFAkJWgAcAP4kAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8mAAIMAAgJNxr5BADHAgAMAAgJNxr5BADHAgAuAAQKf00AAwwACQlFJs8AANwDAAwACQlFJs8AANwDAAIABQkXDmkrALoAAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAABLgAECn8WAAIfAAYJmwt7VgC0AAAfAAYJmwt7VgC0AAAAAA==.',
Hp='Hpvoodoo:BAAALgAECgcJCAAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJEgAGAAAAAA==.',
Hy='Hylaina:BAAALgAECgMJAwAAAA==.Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQABLgAECgkJEQAGAAAAAA==.',
Ia='Iamamonk:BAAALgADCgEJAQAAAA==.',
Ic='Iclapu:BAAALgAECgEJAgABLgAECgkJMQAeADAdAA==.',
Id='Idrick:BAAALgAECgQJBAAAAA==.',
Ig='Iggz:BAAALgADCgkJCQABLgAECgkJSAAeAOoUAA==.Ignia:BAAALgADCgYJCgABLgAECgkJSAAeAOoUAA==.Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8cAAQoAAgJ3RkwBwAWAgAoAAgJ3RkwBwAWAgAmAAMJ1AmTVgCNAAAdAAEJuBSfNwA7AAAAAA==.',
Il='Ilililililli:BAABLgAECn8dAAMVAAkJoRavRgBRAQAVAAkJoRavRgBRAQAfAAIJdgjqhQBNAAAAAA==.Illinelf:BAAALgAECgYJCwABLgAECgcJFQACABwfAA==.Illumi:BAAALgAECgEJAQAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIPAAcJrR6CEgCOAgAPAAcJrR6CEgCOAgAAAA==.Imfubar:BAAALgAECgMJAwAAAA==.Imhammered:BAABLgAECn8pAAILAAgJ+BL5IQD0AQALAAgJ+BL5IQD0AQAAAA==.Impullse:BAABLgAFFH8GAAIJAAIJ7QSPbwBeAAAJAAIJ7QSPbwBeAAAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAFFAcJDQAcAJYXAA==.',
It='Ithilwen:BAABLgAECn80AAIYAAkJySGtCADpAgAYAAkJySGtCADpAgAAAA==.Itiswhatitiz:BAABLgAECn8lAAMaAAgJvhmdZwB0AQAaAAgJvhmdZwB0AQAlAAUJRAznBwDEAAAAAA==.Itsbonertime:BAAALgADCgEJAQAAAA==.Itsybityshiv:BAACLgAFFH8OAAISAAQJJBxLFgBaAQASAAQJJBxLFgBaAQAuAAQKfzYAAxIACQmbHdcKAHcCABIACQmbHdcKAHcCABEAAQmgGPQfADMAAAAA.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgIJBAAAAA==.Jahq:BAABLgAECn8VAAIdAAYJAyF8NAAnAgAdAAYJAyF8NAAnAgAAAA==.Jakarr:BAAALgAECgUJBwAAAA==.Jambs:BAAALgADCgEJAQAAAA==.Jandaelia:BAAALgAECgEJAQAAAA==.Jaysontatum:BAAALgAECgEJAQAAAA==.',
Je='Jeabuss:BAAALgADCgkJFQAAAA==.',
Jh='Jhani:BAABLgAECn8ZAAIBAAkJLwS2owA1AQABAAkJLwS2owA1AQAAAA==.',
Ji='Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8wAAIBAAkJASEUGgC9AgABAAkJASEUGgC9AgAAAA==.Joobles:BAAALgAECgEJAQABLgAECgkJMQAeADAdAA==.Jormojo:BAAALgAECgQJBgAAAA==.Jotwnky:BAABLgAECn8eAAQnAAcJAyC3BQAMAgAnAAUJSSO3BQAMAgAUAAQJsxo7IwA+AQATAAMJGB9WuADoAAAAAA==.Jotwnkyy:BAACLgAFFH8JAAISAAQJAhMjHQA1AQASAAQJAhMjHQA1AQAuAAQKfzIAAhIABwkiILwUAPsBABIABwkiILwUAPsBAAEuAAQKBwkeACcAAyAA.',
Ju='Jungol:BAAALgAECgIJAgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kairupaws:BAAALgAECgQJBAAAAA==.Kaliban:BAAALgAECgQJBAAAAA==.Kaltank:BAAALgAECggJAwAAAA==.Kamin:BAABLgAECn8jAAIOAAgJwiHjAwARAwAOAAgJwiHjAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAABLgAECn8UAAMTAAgJhxkndQBPAQATAAgJhxkndQBPAQAUAAEJnxEdbQA6AAAAAA==.Katamaran:BAABLgAFFH8HAAIBAAMJ6wlMSACrAAABAAMJ6wlMSACrAAABLgAFFAcJHgAhAGsQAA==.Kaykaypally:BAACLgAFFH8GAAIHAAMJ4AnPTwB0AAAHAAMJ4AnPTwB0AAAuAAQKfx8AAgcACQluEjpXAMYBAAcACQluEjpXAMYBAAAA.',
Ke='Keis:BAAALgAECgYJBgABLgAFFAcJFgATAGYjAA==.Kelareece:BAAALgAECgQJBAAAAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn80AAMHAAcJ+hh/bgCRAQAHAAcJ+hh/bgCRAQALAAQJah14PABVAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgAGAAAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8nAAILAAkJSyJsCgDlAgALAAkJSyJsCgDlAgAAAA==.Kidori:BAAALgAECgEJAQABLgAECgkJJwALAEsiAA==.Killakevv:BAAALgAECgEJAQAAAA==.Kinji:BAAALgADCgYJCAABLgAECgkJIAABAKoXAA==.Kirisute:BAAALgAECgEJAQAAAA==.Kirsha:BAAALgAECgMJAwAAAA==.Kisyri:BAAALgAECggJCAAAAA==.Kittycatmeow:BAAALgAFFAMJBAAAAA==.',
Ko='Kolsch:BAAALgAECgIJAgAAAA==.Konfu:BAAALgAECgEJAQAAAA==.Koopa:BAAALgAECgQJCAABLgAECgkJHQALACUNAA==.Koriandar:BAABLgAECn84AAIBAAgJ/AxngQB1AQABAAgJ/AxngQB1AQAAAA==.Kormega:BAAALgAECgUJBwAAAA==.Koyama:BAAALgADCgcJBwAAAA==.',
Kr='Krispies:BAAALgAECgMJAwAAAA==.Kristysavage:BAACLgAFFH8IAAMlAAMJ6h/tDwCgAAAlAAMJ6h/tDwCgAAAaAAEJlB+7agBLAAAuAAQKf0QAAyUACQnCIKIHAKQCACUACQnCIKIHAKQCABoAAQlAIsv6AGUAAAAA.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAABLgAFFAIJAgAGAAAAAA==.Krynetic:BAAALgAECgIJAgAAAA==.',
Ku='Kulaesca:BAAALgAECgIJAgAAAA==.Kurad:BAAALgAECgIJAwAAAA==.Kuru:BAAALgAECgMJAwAAAA==.',
Ky='Kynar:BAACLgAFFH8+AAMEAAkJwyNEAQBOAwAEAAkJySJEAQBOAwANAAcJUhJeIADlAAAuAAQKfxcAAgQACAkuH60/ADoCAAQACAkuH60/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyrieirving:BAAALgAFFAEJAQABLgAECgEJAQAGAAAAAA==.Kyua:BAABLgAECn8VAAImAAcJFAjwNADrAAAmAAcJFAjwNADrAAAAAA==.',
La='Lambshot:BAABLgAECn8gAAMaAAcJIiELFABFAQAaAAcJIiELFABFAQAbAAEJ/AahjwArAAAAAA==.Lambsy:BAACLgAFFH9XAAQFAAkJmxt2AQDeAgAFAAkJmxt2AQDeAgAgAAYJYxfkBQCSAQAOAAEJpAgYLQA7AAAuAAQKfx8AAwUACAmrIBARAMgCAAUACAl4HhARAMgCACAAAQnuI0A5AEsAAAAA.Lanana:BAAALgAECgYJBgAAAA==.Landwhalexxl:BAABLgAECn8XAAIBAAcJ9BGOpACPAQABAAcJ9BGOpACPAQAAAA==.Laneera:BAAALgAECgQJDgAAAA==.',
Le='Leap:BAAALgAECgEJAQAAAA==.Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn81AAIZAAkJWiPMAQDJAgAZAAkJWiPMAQDJAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Liegh:BAAALgAECgQJBQAAAA==.Lightofhope:BAABLgAECn8fAAQhAAgJexG+LgBlAQAhAAgJexG+LgBlAQAYAAUJnwbWOADgAAAKAAIJyQZ0egAfAAAAAA==.Lihandra:BAAALgAECgYJCgAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgABLgAFFAYJFwABAPAVAA==.Lilyy:BAACLgAFFH8XAAIBAAYJ8BW8HwByAQABAAYJ8BW8HwByAQAuAAQKfycAAgEACQmIIFQPAAADAAEACQmIIFQPAAADAAAA.Liria:BAAALgAECgYJDQAAAA==.Lisana:BAAALgAECgEJAQAAAA==.Lisanalgaib:BAABLgAECn8ZAAIHAAgJlRfcWQC/AQAHAAgJlRfcWQC/AQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Livelyjoker:BAAALgADCgMJAgAAAA==.Lizzimcguire:BAABLgAFFH8LAAIZAAcJviCBAAA4AgAZAAcJviCBAAA4AgAAAA==.',
Lo='Loharfal:BAAALgADCgcJCAAAAA==.Loksham:BAAALgAECgkJEQAAAA==.Lokî:BAAALgAECgQJBAAAAA==.Loraen:BAABLgAECn8vAAIBAAkJZRElDQCQAQABAAkJZRElDQCQAQAAAA==.Lorelei:BAAALgAECgEJAQABLgAECgkJJAAgABkbAA==.Lostep:BAABLgAFFH8NAAIKAAUJCAYzDgDGAAAKAAUJCAYzDgDGAAABLgAFFAkJNwAJAPEkAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAACLgAFFH8IAAMfAAMJWQs5EQCtAAAfAAMJWQs5EQCtAAAVAAIJgw9WMABmAAAuAAQKfxwAAxUACAkGEws5AI4BABUACAkGEws5AI4BAB8AAwnZDSV7AFwAAAEuAAQKAQkBAAYAAAAA.Lunarmon:BAAALgAECgUJDgAAAA==.Lunchable:BAABLgAECn8eAAIPAAgJnhmJFgBlAgAPAAgJnhmJFgBlAgAAAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.Lyx:BAAALgADCgEJAgAAAA==.',
['Lè']='Lèa:BAAALgAECgEJAQABLgAECgkJGgAhAP8fAA==.',
['Lé']='Léblanc:BAABLgAECn8oAAIBAAkJ/x2ARAAOAgABAAkJ/x2ARAAOAgAAAA==.',
Ma='Macaboros:BAAALgADCgMJAwAAAA==.Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Maevora:BAAALgAECgcJDQAAAA==.Magicaltoast:BAAALgAECgcJEQAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makah:BAAALgAECgMJAwAAAA==.Makizenin:BAAALgADCgcJDwAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Mankala:BAAALgADCgIJAgAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Maraud:BAAALgADCgEJAQAAAA==.Mari:BAAALgAECgMJBQABLgAFFAMJGwAKAAYlAA==.Marni:BAAALgAECggJEgAAAA==.Matroxx:BAABLgAECn8YAAMVAAcJfBA7MwAnAQAVAAcJfBA7MwAnAQAfAAQJPSA2BwAiAQABLgAFFAgJMQAIACcXAA==.Mazi:BAAALgAECgMJBgAAAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAACLgAFFH8HAAIEAAQJfw9DfQAMAQAEAAQJfw9DfQAMAQAuAAQKfysAAgQACAnQIWYmAKICAAQACAnQIWYmAKICAAAA.Meeputa:BAEBLgAECn8zAAIaAAkJmSKyAQAfAwAaAAkJmSKyAQAfAwABLgAECgkJMwAaAJkiAA==.Megamaid:BAAALgAECgYJDAAAAA==.Melysia:BAACLgAFFH8hAAIMAAcJgBt9CgBMAgAMAAcJgBt9CgBMAgAuAAQKfzoAAwwACQl0IP8MANQCAAwACQl0IP8MANQCAAIAAgmmCdZJAEYAAAAA.',
Mi='Mia:BAAALgAECgMJAwAAAA==.Miadas:BAAALgAFFAEJAQABLgAFFAMJBgACAJQaAA==.Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mika:BAAALgAFFAEJAQABLgAFFAMJGwAKAAYlAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgAFFAIJAgAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwAGAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECgIJAgABLgAFFAMJGwAKAAYlAA==.',
Mo='Moardotsnow:BAABLgAECn8oAAMTAAkJ4ST8PADoAQATAAUJ9iT8PADoAQAUAAQJvSRYEgAkAQAAAA==.Moby:BAABLgAECn8tAAMnAAkJnQ5sAwBSAQAnAAkJGA1sAwBSAQATAAkJPgiHGACzAAAAAA==.Moistmender:BAAALgAECgkJEgAAAA==.Moonleaf:BAAALgAECgkJAwAAAA==.Moosaki:BAAALgAECgkJCQABLgAECgkJMgASAIwjAA==.Mortui:BAABLgAECn8WAAImAAgJBCCoCQCPAgAmAAgJBCCoCQCPAgABLgAFFAgJMQAIACcXAA==.Motoharu:BAAALgAECgEJAQAAAA==.Mous:BAAALgADCgMJAwAAAA==.Mozes:BAAALgADCgMJAwAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgcJGAAdAIMiAA==.Murridan:BAABLgAECn8pAAIdAAkJoiKUCQA7AwAdAAkJoiKUCQA7AwAAAA==.',
My='Mykaela:BAABLgAECn8uAAMXAAgJShXYAwCJAQAXAAgJ6hLYAwCJAQAHAAUJFgjzKwCoAAAAAA==.Myraela:BAAALgAECgYJEgABLgAECgkJJwANAE8hAA==.Mythhealer:BAAALgAECgQJBAAAAA==.',
['Më']='Mëow:BAABLgAECn9DAAIQAAkJ4wg2CQD4AAAQAAkJ4wg2CQD4AAAAAA==.',
Na='Naabu:BAAALgAECgEJAQAAAA==.Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAABLgAECn8uAAIaAAgJHhaGDACpAQAaAAgJHhaGDACpAQAAAA==.',
Ne='Neev:BAAALgAECgMJAwAAAA==.Nehpets:BAAALgAECgMJAwAAAA==.Nellybearwl:BAAALgAECgkJEQAAAA==.Nephelym:BAAALgAFFAIJAgAAAA==.Nerfherder:BAAALgAECgQJBQAAAA==.Nerv:BAAALgADCgUJBwAAAA==.Nexes:BAAALgAECgUJBwAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJBQAAAA==.Nirina:BAABLgAECn8xAAIaAAkJWgzVDgCFAQAaAAkJWgzVDgCFAQAAAA==.Nixie:BAAALgAECgYJBgAAAA==.',
Nn='Nnuiq:BAAALgAECgIJAwAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECgkJIAABAKoXAA==.Northsouth:BAAALgAECgEJAgAAAA==.Notdicey:BAAALgAFFAIJAwAAAA==.Notstephen:BAAALgAECgUJCgABLgAFFAEJAQAGAAAAAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAACLgAFFH8LAAMIAAUJRxdCBAA7AQAIAAUJRxdCBAA7AQAPAAIJhA2NRQB0AAAuAAQKfycAAwgACQlMIVcDANICAAgACQkwHlcDANICAA8ABglnJHQaAEACAAEuAAUUBgkKAA0AFwkA.',
['Ný']='Nýks:BAAALgAECgEJAQAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Oi='Oiflar:BAAALgAECgkJEgABLgAECgkJQAAkACkkAA==.',
Ok='Okaytwin:BAAALgADCgEJAQAAAA==.',
Ol='Olangi:BAAALgAECggJDQAAAA==.Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8cAAIdAAgJkBZgLAB1AQAdAAgJkBZgLAB1AQAuAAQKfyQAAh0ACQliIKwPAAEDAB0ACQliIKwPAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECggJDAAAAA==.Onlybakshots:BAAALgAECgYJCAAAAA==.',
Op='Oppose:BAAALgAECgQJBAAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Orexion:BAABLgAECn8iAAMFAAkJmg0FNgBwAQAFAAkJRQ0FNgBwAQAgAAYJ8gtHNwDoAAAAAA==.Ormagöden:BAABLgAECn8oAAIiAAkJMhSMAwBPAgAiAAkJMhSMAwBPAgAAAA==.',
Ov='Ovakill:BAAALgADCgEJAQAAAA==.',
Oz='Ozzpoxzo:BAABLgAECn8YAAIUAAUJMgacDABqAAAUAAUJMgacDABqAAAAAA==.',
Pa='Pageantry:BAAALgADCgkJCQAAAA==.Palladean:BAABLgAECn8zAAIHAAkJFxdAPAATAgAHAAkJFxdAPAATAgAAAA==.Pandemic:BAAALgAECgMJBgAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwAGAAAAAA==.Pastasauce:BAABLgAECn8mAAIHAAkJ+RtrBACOAgAHAAkJ+RtrBACOAgAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Pegero:BAAALgAECgIJAgABLgAFFAEJAQAGAAAAAA==.Penelohpe:BAAALgAECgcJCgABLgAECggJIwAOAMIhAA==.Penwork:BAAALgAECggJCwAAAA==.Penz:BAABLgAECn8hAAIEAAkJeR0sBQBIAgAEAAkJeR0sBQBIAgAAAA==.Perrian:BAAALgADCgMJBAAAAA==.Pestilential:BAAALgAECgQJAQAAAA==.Petey:BAAALgADCgEJAgAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Phatt:BAAALgAECgEJAQAAAA==.Philex:BAAALgAECgYJBwABLgAFFAcJFgATAGYjAA==.Phoenixfyre:BAAALgAECgcJCgAAAA==.Phoon:BAACLgAFFH8WAAITAAcJZiOvIADNAQATAAcJZiOvIADNAQAuAAQKfyEABBMACAmoHkMdAKYCABMACAmoHkMdAKYCABQAAglGGVVJAJIAACcAAQkAAKAqAEoAAAAA.Phøenixbane:BAABLgAECn8hAAIHAAgJxh41KQBdAgAHAAgJxh41KQBdAgAAAA==.',
Pi='Piggy:BAAALgAECgEJAgAAAA==.Pillowpants:BAAALgAECgEJAQAAAA==.Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgcJEwAAAA==.',
Pl='Plaguefist:BAAALgAECgkJEQAAAA==.Plata:BAAALgAFFAEJAQAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.Plumsàuce:BAAALgAECgEJAQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.Pompous:BAAALgAECgEJAQAAAA==.',
Pr='Praytroxx:BAAALgAECgcJDwABLgAFFAgJMQAIACcXAA==.Premonitions:BAABLgAECn8fAAIJAAgJVBTNPQC3AQAJAAgJVBTNPQC3AQAAAA==.Premune:BAABLgAECn84AAQLAAkJ6x9cDQCuAgALAAkJ6x9cDQCuAgAXAAgJ+RCQGQBNAQAHAAIJOgioGwFjAAAAAA==.Preparation:BAABLgAFFH8HAAIcAAQJZgzlGwDKAAAcAAQJZgzlGwDKAAABLgAFFAQJFQARAPoaAA==.Prion:BAACLgAFFH8QAAIdAAQJ8w8xRQAYAQAdAAQJ8w8xRQAYAQAuAAQKfxkAAh0ACAklFEBTAIwBAB0ACAklFEBTAIwBAAAA.',
Ps='Psycs:BAAALgAECgYJDgAAAA==.',
Pu='Pucco:BAAALgADCgYJBgAAAA==.Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAFFAQJCQABAE0gAA==.Purplemage:BAAALgAECgkJDQABLgAECgkJEgAGAAAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
['Pú']='Púre:BAAALgAECgIJAgAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMTAAgJSB2FOgAiAgATAAgJrhuFOgAiAgAUAAMJzRe1JQCGAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgATAEgdAA==.',
Ra='Radeøn:BAAALgAECgEJAQAAAA==.Ragingtauren:BAAALgAECgMJBwAAAA==.Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH83AAMJAAkJ8SRJAACeAwAJAAkJ8SRJAACeAwAPAAIJYxKBJQCCAAAuAAQKfx4AAwkACAkhHysfACQCAAkACAkhHysfACQCAA8ABAkKGWlVAPAAAAAA.Raistlain:BAABLgAECn8WAAIBAAcJjAixuAAUAQABAAcJjAixuAAUAQAAAA==.Raistlin:BAABLgAECn8gAAMmAAkJ7Bb8FADnAQAmAAkJ7Bb8FADnAQAdAAEJywOo8AAiAAAAAA==.Ralfio:BAABLgAECn9AAAIkAAkJKSQgAQCeAwAkAAkJKSQgAQCeAwAAAA==.Ralfiosky:BAAALgAECggJEwABLgAECgkJQAAkACkkAA==.Ramennoodlez:BAAALgAECgYJCgAAAA==.Rat:BAAALgAFFAIJAgABLgAFFAUJCQAiAAAgAA==.Ratren:BAAALgADCgQJAwAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAACLgAFFH8GAAMCAAMJlBrADADrAAACAAMJlBrADADrAAAQAAIJnwhKNgBLAAAuAAQKfysABAIACQn6GzIKAB4CAAIABwkjITIKAB4CAAMABwlPGNwlAJ0BABAACAnDEakeAFgBAAAA.',
Re='Readycheck:BAABLgAECn84AAMDAAkJsxkGAwAdAgADAAkJqRkGAwAdAgAQAAgJyQ8xIwA2AQAAAA==.Reckalossi:BAAALgAECgkJAQABLgAFFAQJEQAHABIKAA==.Redcows:BAAALgAECgUJBQAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8iAAIHAAgJzB1pNQBNAgAHAAgJzB1pNQBNAgAAAA==.Remulous:BAABLgAECn8VAAIaAAcJyQiuqwDsAAAaAAcJyQiuqwDsAAAAAA==.Revelaen:BAACLgAFFH8cAAMZAAYJLhB8AwDWAAAcAAYJLhDgMgD2AAAZAAQJpgZ8AwDWAAAuAAQKfyMAAxwACQlxHQ0JAOcCABwACQlxHQ0JAOcCABkABQlYBowoANwAAAAA.',
Ri='Rick:BAACLgAFFH8iAAMaAAUJAiYBGACqAQAaAAUJAiYBGACqAQAbAAEJXBoLJQBUAAAuAAQKfysAAxoACQmkI5kOANwCABsACAlpI+QJAAUDABoACQlqI5kOANwCAAAA.Rickers:BAAALgAECgMJAwABLgAFFAUJIgAaAAImAA==.Rikosan:BAAALgAECgEJAwAAAA==.Ripbozo:BAAALgADCgIJAgAAAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAABLgAECn8hAAMLAAYJayW0FABoAgALAAYJayW0FABoAgAHAAQJnRkyrQAoAQABLgAFFAgJDwAkAEIkAA==.Roonoa:BAAALgAECgUJBQAAAA==.Roseblood:BAAALgAECgMJAwABLgAECgUJBQAGAAAAAA==.Roust:BAAALgAECgUJBQABLgAFFAQJCQABAE0gAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saba:BAAALgAECgMJBAAAAA==.Saephora:BAABLgAECn8+AAIBAAkJQgvaHwDiAAABAAkJQgvaHwDiAAAAAA==.Saerea:BAACLgAFFH8IAAIEAAMJNBkokwDmAAAEAAMJNBkokwDmAAAuAAQKfyAAAgQACAkuH30zAGkCAAQACAkuH30zAGkCAAAA.Saggypants:BAAALgAFFAIJAgAAAA==.Sahhm:BAACLgAFFH8MAAIHAAMJ+SDpIQADAQAHAAMJ+SDpIQADAQAuAAQKfxIAAgcABAlyJa1qAJkBAAcABAlyJa1qAJkBAAAA.Sakurai:BAAALgAFFAMJAwABLgAFFAcJIAASADAOAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAQJFQARAPoaAA==.Sammel:BAACLgAFFH8KAAMhAAMJjhR8EgDWAAAhAAMJjhR8EgDWAAAYAAEJehEMMQA0AAAuAAQKfx4AAyEACQktGlcUAE0CACEACQktGlcUAE0CABgAAQm2Gz4fAE8AAAAA.Sandmanslim:BAAALgAECgUJBQAAAA==.Sargus:BAAALgADCgcJBwAAAA==.Sathreina:BAACLgAFFH8TAAIHAAUJjg2BKwDdAAAHAAUJjg2BKwDdAAAuAAQKfyoAAgcACQlEFm9MAOEBAAcACQlEFm9MAOEBAAAA.Satinofhell:BAAALgAECgQJBgAAAA==.Sawbones:BAAALgAECgYJBgAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIeAAkJKRtoEgCAAgAeAAkJKRtoEgCAAgAAAA==.Schmeckles:BAABLgAFFH8HAAIJAAMJnAMCZAB/AAAJAAMJnAMCZAB/AAAAAA==.Scootzmcgee:BAAALgAFFAEJAQAAAA==.',
Se='Sego:BAAALgAECgEJAgAAAA==.Seikura:BAAALgADCgMJAwAAAA==.Sekii:BAAALgAECgQJBAABLgAFFAcJFgATAGYjAA==.Sekimaru:BAACLgAFFH8gAAMSAAcJMA6VDQAvAQASAAYJcRCVDQAvAQARAAEJ6wLtEQBGAAAuAAQKfzQAAxIACQnXGlcLAG4CABIACQnXGlcLAG4CABEAAQmnB1EqAC0AAAAA.Sekimura:BAAALgAFFAEJAQABLgAFFAcJIAASADAOAA==.Selok:BAAALgAFFAEJAgAAAA==.Senli:BAAALgADCgIJAgAAAA==.',
Sh='Shaddik:BAAALgAECgQJBgABLgAECggJEAAGAAAAAA==.Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJEAAAAA==.Shaeledoran:BAACLgAFFH8TAAIEAAUJwxuCTgBVAQAEAAUJwxuCTgBVAQAuAAQKf0EAAgQACQnHILsbAKECAAQACQnHILsbAKECAAAA.Shamaneggs:BAABLgAFFH8IAAIJAAMJZQ5EWgCYAAAJAAMJZQ5EWgCYAAAAAA==.Shamatroxx:BAACLgAFFH8xAAIIAAgJJxdrAwCeAQAIAAgJJxdrAwCeAQAuAAQKfzEAAggACQlyJOkAAEoDAAgACQlyJOkAAEoDAAAA.Shamphen:BAAALgAFFAEJAQAAAA==.Shampomaster:BAAALgADCgMJAwAAAA==.Sheist:BAABLgAFFH8FAAIcAAIJygkBXwBbAAAcAAIJygkBXwBbAAABLgAFFAQJCQABAE0gAA==.Shenzuu:BAAALgAECgUJBwAAAA==.Shieetz:BAAALgAECgYJEQAAAA==.Shlock:BAAALgAECgYJBwAAAA==.Shlomie:BAAALgADCggJGgAAAA==.Shlomiel:BAAALgADCgEJAQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgAECgEJAQAAAA==.Shorttemper:BAAALgAECgIJAgAAAA==.Shänk:BAABLgAECn8lAAMSAAcJVBJ+CQDbAAASAAcJVBJ+CQDbAAARAAQJVgtNFgDLAAABLgAFFAIJAgAGAAAAAA==.',
Si='Sibirica:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Siena:BAABLgAECn8kAAMJAAgJhgrVDwAzAQAJAAgJhgrVDwAzAQAPAAYJKA2qUwDqAAAAAA==.Silanthius:BAAALgAECgYJCwAAAA==.Silith:BAAALgAECggJEgAAAA==.Silre:BAABLgAECn8eAAIUAAgJtRDVEQArAQAUAAgJtRDVEQArAQAAAA==.Silverfangg:BAAALgAECgMJAwAAAA==.Sinergy:BAABLgAECn8UAAITAAYJIh8zRAD/AQATAAYJIh8zRAD/AQAAAA==.Singularité:BAAALgAFFAEJAQABLgAFFAQJFQARAPoaAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skirmish:BAABLgAECn8ZAAIEAAYJLRQ6mAA4AQAEAAYJLRQ6mAA4AQAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJEgAGAAAAAA==.Slappeey:BAAALgAECgkJEgAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECgkJQAAkACkkAA==.Snaxx:BAAALgAECgMJBgABLgAFFAEJAQAGAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8PAAMEAAMJViBIJgD9AAAEAAMJViBIJgD9AAAiAAIJLRYEHABIAAAuAAQKf00AAwQACQkmJfEPAO0CAAQACQlZJPEPAO0CACIACAnPJCADAMICAAAA.',
So='Softlight:BAAALgAECgMJAwAAAA==.Solarius:BAAALgAECgMJBAAAAA==.Solokills:BAAALgAFFAEJAQAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwAGAAAAAA==.Soundtrack:BAAALgADCgEJAQABLgAECgkJHQALACUNAA==.',
Sp='Spaceman:BAABLgAFFH8FAAMfAAUJOwymEwCSAAAfAAQJvQWmEwCSAAAVAAEJ+wT3QgAxAAABLgAFFAgJIwAYACQNAA==.Spaghettiz:BAAALgADCgkJCQAAAA==.Sproxx:BAAALgAECgEJAgABLgAECgkJEgAGAAAAAA==.Spyridon:BAAALgAECgcJDQAAAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMdAAcJox60LwA9AgAdAAcJox60LwA9AgAmAAQJOB77PgAAAQAAAA==.Squirrels:BAABLgAECn9IAAMeAAkJ6hQgAwCCAQAeAAkJ6hQgAwCCAQAVAAQJuwXsUgCGAAAAAA==.Squirtstorm:BAABLgAECn9DAAMJAAkJLCCBCQAbAwAJAAkJLCCBCQAbAwAPAAUJ2Bd4CwATAQAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8yAAMSAAkJjCMwBAD7AgASAAkJjCMwBAD7AgAjAAEJNxbHIgA+AAAAAA==.Stealthberry:BAAALgAECgEJAQAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.Stillcreepin:BAAALgAFFAIJAwAAAA==.Stompy:BAAALgADCgkJEAABLgAFFAcJHgAhAGsQAA==.Storienn:BAABLgAECn8YAAMHAAkJlReBXAC5AQAHAAgJBBiBXAC5AQAXAAIJ1hXbOAB7AAAAAA==.Stormzpaly:BAAALgADCgkJCQAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Subarashii:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.Suküna:BAACLgAFFH8MAAIdAAMJPBhZXgDVAAAdAAMJPBhZXgDVAAAuAAQKf0MAAh0ACQkOJCQHABwDAB0ACQkOJCQHABwDAAAA.Sunbur:BAAALgADCgEJAQAAAA==.Sunglo:BAAALgAECgUJBQAAAA==.Superbean:BAAALgAECgQJBQAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAACLgAFFH8RAAIJAAcJ1SO5DgD3AQAJAAcJ1SO5DgD3AQAuAAQKfzQAAgkACQm1JFgCAM0CAAkACQm1JFgCAM0CAAAA.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAIEAAcJPhSEeQCRAQAEAAcJPhSEeQCRAQAAAA==.Syrelia:BAABLgAECn87AAIBAAkJKBmhKwBrAgABAAkJKBmhKwBrAgAAAA==.',
Ta='Takèda:BAABLgAECn8uAAIlAAkJJiHQAQASAgAlAAkJJiHQAQASAgAAAA==.Taldain:BAABLgAECn8eAAQQAAkJ2x2qFQCnAQADAAgJ4xnnGgD0AQAQAAcJABmqFQCnAQACAAIJaSOoJwDQAAAAAA==.Talonstrykz:BAABLgAECn8VAAISAAgJ0A42IgDnAQASAAgJ0A42IgDnAQAAAA==.Tankdeesnuts:BAABLgAECn88AAIOAAkJlQeKIQAjAQAOAAkJlQeKIQAjAQAAAA==.Tashalle:BAAALgAECgEJAQABLgAECgkJNAAYAMkhAA==.Tassarosea:BAAALgAFFAIJAgABLgAFFAcJCwAZAL4gAA==.Tauloe:BAABLgAECn9MAAIPAAkJ+ROXBADWAQAPAAkJ+ROXBADWAQAAAA==.Tayna:BAAALgAECggJDAAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8aAAIHAAgJrhP+ggBpAQAHAAgJrhP+ggBpAQAAAA==.Terpene:BAAALgADCgEJAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEgAGAAAAAA==.Teyassha:BAAALgAECgEJBAAAAA==.',
Th='Thomosaurus:BAAALgAECgEJAQAAAA==.Thomö:BAABLgAECn8gAAMaAAkJKQnGYwB+AQAaAAkJ1gjGYwB+AQAlAAYJ2gSgHAAMAQAAAA==.Throatfist:BAABLgAFFH8FAAMeAAIJIAsoJABJAAAeAAEJ2RIoJABJAAAfAAEJZwP6EwBCAAABLgAFFAYJHwAdAFAeAA==.Throme:BAAALgAECgkJEAAAAA==.Thunk:BAACLgAFFH8PAAIPAAMJVR6hGgDFAAAPAAMJVR6hGgDFAAAuAAQKfyYAAg8ACQmXJfUDAGADAA8ACQmXJfUDAGADAAAA.',
Ti='Timdawg:BAACLgAFFH8NAAIBAAUJMB58KgAnAQABAAUJMB58KgAnAQAuAAQKfxQAAgEACAn1InUaALwCAAEACAn1InUaALwCAAEuAAUUCQkdABMAYBwA.Timmolate:BAABLgAFFH8dAAMTAAkJYBxcAgDnAgATAAkJPRxcAgDnAgAUAAEJ+ALjEwA9AAAAAA==.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Todrick:BAAALgAECgEJAQAAAA==.Tomotostein:BAACLgAFFH8UAAIHAAQJeBnFIwD7AAAHAAQJeBnFIwD7AAAuAAQKfzMAAgcACQlpIzYJAB8DAAcACQlpIzYJAB8DAAAA.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAABLgAECn8VAAMJAAgJghLfNgDVAQAJAAgJghLfNgDVAQAPAAYJdxHbRwAVAQABLgAECgkJNQAVAJUcAA==.',
Tr='Tradrael:BAAALgAECgEJAQAAAA==.Tristîtia:BAAALgAFFAEJAQAAAA==.Trulu:BAAALgAECgIJAgAAAA==.',
Ts='Tsuma:BAAALgAECgQJCAAAAA==.Tsume:BAABLgAECn8VAAIaAAcJ8BX/YgB/AQAaAAcJ8BX/YgB/AQAAAA==.',
Tt='Tt:BAAALgAECgEJAQABLgAFFAMJCwAgALsiAA==.',
Tu='Tum:BAAALgAFFAEJAQAAAA==.Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAFFAIJAgAAAA==.Tystian:BAABLgAECn8dAAMmAAcJFhenBgBcAQAmAAYJ9RmnBgBcAQAdAAUJpgqcGQC8AAAAAA==.Tyv:BAABLgAECn80AAMWAAkJAxYhAwABAgAWAAkJAxYhAwABAgABAAYJKgak1wDnAAAAAA==.',
['Té']='Téa:BAAALgAECgMJAwABLgAECgkJGgAhAP8fAA==.',
Ua='Uav:BAAALgAECgEJAQAAAA==.',
Un='Unclejoey:BAAALgAECgEJAQABLgAECgkJQAAkACkkAA==.',
Ur='Urä:BAAALgAECgkJEAAAAA==.',
Uz='Uzì:BAAALgAECgQJBAAAAA==.',
Va='Vainatetosix:BAABLgAECn8ZAAIEAAgJQhNfFwD4AAAEAAgJQhNfFwD4AAAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIBAAkJ6SAaNwA8AgABAAkJ6SAaNwA8AgAAAA==.Valtasia:BAAALgADCgEJAQAAAA==.Valyndra:BAAALgAECgcJDAABLgAECgkJMQAXAH4WAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAACLgAFFH8MAAIOAAQJohGlFwDdAAAOAAQJohGlFwDdAAAuAAQKfyMAAg4ACQl/DhIYAH8BAA4ACQl/DhIYAH8BAAAA.Vaylorian:BAABLgAECn8xAAQXAAkJfhaiAgDfAQAXAAgJvBeiAgDfAQAHAAgJqhFcEQBdAQALAAUJpRjvBwBZAQAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQABLgAECgkJMQAXAH4WAA==.Velectran:BAABLgAECn8qAAIHAAgJJRfXUQDTAQAHAAgJJRfXUQDTAQABLgAECgkJOwABACgZAA==.Velorian:BAAALgAECgUJBwAAAA==.Vesperi:BAAALgAECggJCAABLgAECgkJOwABACgZAA==.',
Vi='Vikav:BAAALgAECgEJAQAAAA==.Vilgehkfrúna:BAAALgAECgEJAQAAAA==.Virdreth:BAAALgAECgMJCAAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Vortash:BAAALgAECgcJEQAAAA==.',
Vy='Vyndragon:BAAALgAECgMJAwAAAA==.Vynle:BAAALgAECgQJDwAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAABABMDAA==.',
['Vä']='Vämpira:BAAALgAECgYJCwAAAA==.',
Wa='Warheimer:BAAALgAECgQJBQAAAA==.Warlickmadic:BAAALgAECgEJAQAAAA==.Warrgodx:BAABLgAECn8XAAMFAAcJFhhYPABUAQAFAAcJFhhYPABUAQAgAAMJmxKXRgCwAAAAAA==.Wartroxx:BAABLgAFFH8HAAMUAAQJCQ6hDADUAAATAAQJOg0hJgD4AAAUAAMJIQ6hDADUAAABLgAFFAgJMQAIACcXAA==.Wartui:BAAALgADCgMJAwABLgAFFAgJMQAIACcXAA==.',
We='Welcome:BAAALgAECgQJBAAAAA==.Wengja:BAABLgAECn8gAAQVAAcJryULBwDqAgAVAAcJryULBwDqAgAeAAEJ9QSVjgAnAAAfAAEJAACmiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECgkJJAAgABkbAA==.Whoknows:BAABLgAECn8YAAIdAAcJgyK1IQBLAgAdAAcJgyK1IQBLAgAAAA==.',
Wi='Wiz:BAAALgAECgQJBgAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIPAAkJxR2mCAAIAwAPAAkJxR2mCAAIAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgYJCQAAAA==.',
Xi='Xiak:BAAALgAECgEJAQABLgAFFAMJBgACAJQaAA==.Xialai:BAAALgADCgMJAwAAAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.Yavanoa:BAAALgADCgkJCQAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH9aAAMcAAkJ/iTNAABRAwAcAAkJ/iTNAABRAwAZAAQJ8CG6BAAgAQAuAAQKfyMAAxkACQkrJVQDAOoCABkABwmsJVQDAOoCABwABwkQIm0mAK0BAAAA.Yoyohunty:BAAALgAECgEJBQAAAA==.Yozki:BAABLgAECn8fAAIBAAkJTh3pNABFAgABAAkJTh3pNABFAgAAAA==.',
Yt='Ytix:BAAALgAECgMJAwAAAA==.',
Yu='Yuji:BAAALgAECgEJAQABLgAFFAMJDwAPAFUeAA==.Yuuki:BAAALgAECgQJBQABLgAFFAQJFQARAPoaAA==.Yuulia:BAABLgAECn8kAAMgAAkJGRsaCwA2AgAgAAkJqhoaCwA2AgAOAAYJeRhvGQCGAQAAAA==.',
Yv='Yvonnê:BAAALgADCgEJAQAAAA==.',
Za='Zabada:BAAALgAECgEJAgAAAA==.Zaldrea:BAAALgAFFAEJAQABLgAFFAcJHgAhAGsQAA==.Zandrea:BAAALgAFFAEJAQABLgAFFAcJHgAhAGsQAA==.Zariee:BAABLgAECn8zAAImAAgJeBIRIAB5AQAmAAgJeBIRIAB5AQAAAA==.Zaze:BAAALgAECgEJAQAAAA==.',
Ze='Zel:BAAALgADCgEJAQABLgAECgkJEAAGAAAAAA==.Zemsen:BAACLgAFFH8IAAIBAAMJEwMGMgDgAAABAAMJEwMGMgDgAAAuAAQKfzAAAwEACQmjGOY8AIQCAAEACQmjGOY8AIQCABYAAgneBcAZAEoAAAAA.Zentrea:BAAALgAFFAEJAQABLgAFFAcJHgAhAGsQAA==.Zenyea:BAAALgAFFAEJAwABLgAFFAcJHgAhAGsQAA==.Zetta:BAACLgAFFH8eAAIhAAcJaxCECgC3AQAhAAcJaxCECgC3AQAuAAQKfysAAiEACQmbH+sMALUCACEACQmbH+sMALUCAAAA.Zettadrake:BAAALgAECgQJBAABLgAFFAcJHgAhAGsQAA==.',
Zo='Zoguk:BAAALgADCgEJAQAAAA==.Zoktavir:BAAALgAECgEJAQAAAA==.Zoltan:BAABLgAECn8VAAIBAAYJnQve2QA9AQABAAYJnQve2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8tAAIHAAkJVR5tHQCVAgAHAAkJVR5tHQCVAgAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAFFAEJAQAAAA==.',
['ßl']='ßlue:BAACLgAFFH8HAAIeAAQJDBQFJgARAQAeAAQJDBQFJgARAQAuAAQKf2kABB4ACQmqIGsGANQCAB4ACQmqIGsGANQCABUACAnFGqsWAGQCAB8AAwm+DFxlAIwAAAAA.',
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
