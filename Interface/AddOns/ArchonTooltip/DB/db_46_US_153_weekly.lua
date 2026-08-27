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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Balance','Druid-Feral','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Warrior-Protection','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Druid-Guardian','Warrior-Arms','Priest-Discipline','Rogue-Assassination','Shaman-Elemental','Evoker-Devastation','Rogue-Subtlety','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aakkulay:BAAALgAECgQJBgABLgAECgcJDQABAAAAAA==.',
Ab='Absofsteels:BAABLgAECn9EAAQCAAkJbR7fBABWAgACAAkJXBzfBABWAgADAAMJWh4TBgALAQAEAAEJ2gsdZAAhAAAAAA==.',
Ac='Acaric:BAABLgAECn9JAAIFAAkJdg07FQAxAQAFAAkJdg07FQAxAQAAAA==.Ache:BAAALgAFFAMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAACLgAFFH8TAAIGAAYJrQwjGABeAQAGAAYJrQwjGABeAQAuAAQKfyUAAgYACQlEFoMiADYCAAYACQlEFoMiADYCAAAA.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgAECgYJBgAAAA==.Aireola:BAAALgAECgEJAwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAFFAMJBwAHAH8KAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgIJAgABLgAECgkJQAAIANAhAA==.Alchemist:BAAALgADCgkJKgAAAA==.Alidor:BAACLgAFFH8FAAMEAAIJxgWVJgBBAAAEAAIJxgWVJgBBAAACAAEJGgOWsAAtAAAuAAQKfyAAAwQACAkoCokzAM0AAAIABgnTBI7PAOkAAAQABwkPCokzAM0AAAAA.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAABLgAECn8UAAICAAgJZAxgGADwAAACAAgJZAxgGADwAAAAAA==.Altaressa:BAAALgAECgQJBAAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amberyaheard:BAAALgADCgYJEAAAAA==.Amira:BAACLgAFFH8aAAIJAAUJbCQaAgCUAQAJAAUJbCQaAgCUAQAuAAQKfyUAAgkACAmsJWoCAEUDAAkACAmsJWoCAEUDAAEuAAUUBwkSAAoAOBEA.Amorillis:BAAALgADCgcJDQAAAA==.Amorleroin:BAAALgAECgQJBAAAAA==.Amormage:BAABLgAECn8iAAIFAAgJ+gxJEwBCAQAFAAgJ+gxJEwBCAQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.Amuri:BAAALgAECgYJBgAAAA==.',
An='Angmar:BAAALgAECgQJBAAAAA==.Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8dAAILAAkJRhBtSwCkAQALAAkJRhBtSwCkAQAAAA==.',
Ap='Aphytex:BAAALgADCgEJAQAAAA==.Apothneskin:BAAALgADCgMJAwAAAA==.',
Ar='Arauial:BAABLgAECn8qAAIJAAkJeyFrCADkAgAJAAkJeyFrCADkAgAAAA==.Archdrake:BAAALgAECgYJEAAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8PAAIGAAcJQAqpVAD/AAAGAAcJQAqpVAD/AAAuAAQKfy0AAgYACQl9G7YgAEECAAYACQl9G7YgAEECAAAA.Arizann:BAABLgAECn9HAAQHAAkJfB9LDgDmAgAHAAkJfB9LDgDmAgAMAAcJ7RGvLwBgAQANAAEJyAsQVgAtAAAAAA==.Arobotpr:BAABLgAECn8/AAIOAAkJdRlOEQBMAgAOAAkJdRlOEQBMAgAAAA==.Arrenn:BAAALgAECgYJBgAAAA==.Arthanìa:BAAALgAECgYJBgAAAA==.Artpandalay:BAAALgAECgQJBQABLgAECgYJCAABAAAAAA==.',
As='Asima:BAAALgAECgQJCAAAAA==.Assoul:BAAALgAECgIJAgAAAA==.Astaren:BAABLgAECn85AAMPAAgJgiJdAAAXAwAPAAgJgiJdAAAXAwAQAAUJ5xGyCQDVAAAAAA==.Asuran:BAACLgAFFH8KAAIRAAQJtBqeGwBCAQARAAQJtBqeGwBCAQAuAAQKfzwAAxEACQn2JVAIANsCABEACAlcJVAIANsCABIACQkKI0AGAKoCAAAA.',
At='Atem:BAABLgAECn8UAAISAAUJrQutOACTAAASAAUJrQutOACTAAAAAA==.Atilla:BAAALgAECgUJCAABLgAFFAQJDQAGAEMUAA==.',
Au='Aulinn:BAAALgAECgQJBQAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Ax='Axefu:BAAALgADCgQJBAAAAA==.Axefury:BAAALgADCgYJDwAAAA==.Axegrunion:BAAALgADCgUJBQAAAA==.',
Az='Azaris:BAABLgAECn8+AAIOAAkJzRzvDQB2AgAOAAkJzRzvDQB2AgAAAA==.',
Ba='Babykraze:BAAALgAECgEJAQAAAA==.Baeleaf:BAAALgAECgQJDAAAAA==.Baelrog:BAABLgAECn8ZAAMTAAkJsQ7fCgAOAQATAAkJsQ7fCgAOAQAUAAIJCQPmxwEfAAAAAA==.Baldheadelf:BAAALgAFFAUJAQAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMLAAkJBBLrRwDUAQALAAkJBBLrRwDUAQAVAAIJQgq8NgAsAAAAAA==.Baranina:BAACLgAFFH8TAAMGAAcJWx3HBwAnAQAGAAMJ2iHHBwAnAQAWAAUJERkJFQAcAQAuAAQKfysABBYACAnTI4IOAM4CABYACAkgIoIOAM4CAAYABQmOHws2ANYBABcABgnGINcmAGcBAAAA.Barricaded:BAAALgAECgkJEgAAAA==.Bashbash:BAAALgAECgMJAwAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQABAAAAAA==.Bastrd:BAAALgAECgYJDAAAAA==.Battlecat:BAAALgADCgEJAQABLgAFFAMJBgASADogAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgAECgUJEgAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Bearypie:BAAALgAECgkJBQAAAA==.Beastums:BAABLgAECn8/AAIXAAkJxRnNDQBKAgAXAAkJxRnNDQBKAgAAAA==.Bence:BAAALgAECgYJBgAAAA==.Benji:BAABLgAECn8bAAMFAAkJbBgvVQDdAQAFAAkJbBgvVQDdAQAYAAEJeQYuIgAhAAAAAA==.',
Bi='Biggiecat:BAAALgADCgYJBgABLgAECggJOQAFAAsdAA==.Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blacken:BAAALgAECgEJAgAAAA==.Blazinitup:BAAALgADCgQJCQAAAA==.Blimey:BAAALgAECggJBgAAAA==.Blindaf:BAABLgAECn8wAAMZAAkJXRWNFgDUAQAZAAkJXRWNFgDUAQALAAYJKAVoIwB8AAAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIaAAcJqhGJPQAKAQAaAAcJqhGJPQAKAQAAAA==.Blite:BAAALgADCgkJMQAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8qAAMTAAkJ7RL4BwBYAQATAAYJEhH4BwBYAQAUAAkJ3wUQpgAuAQAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8cAAMHAAYJuw15DgBAAQAHAAYJuw15DgBAAQAMAAMJtwFOQwBpAAAuAAQKfy8AAwcACQmfHlsBAPUCAAcACQmfHlsBAPUCAAwAAQl/ESaKADcAAAAA.Blueeyearch:BAABLgAECn8VAAMWAAcJxx2cFwD2AAAGAAYJESLQTgB8AQAWAAUJoRKcFwD2AAAAAA==.Bluetish:BAAALgAECgQJDgAAAA==.',
Bo='Bo:BAAALgAECggJCAAAAA==.Bobb:BAAALgAFFAIJAgAAAA==.Bolgan:BAAALgAECgMJCAABLgAECggJMAAaAPQdAA==.Bonedecay:BAAALgAECgEJCQAAAA==.Bonerina:BAAALgAECggJEgAAAA==.Boomadk:BAACLgAFFH8TAAMCAAQJKRi4ZgArAQACAAQJgBe4ZgArAQADAAIJSRP6HACbAAAuAAQKfykAAwIACQkPIkUfAMYCAAIACQm1IUUfAMYCAAMACAlKHdgCAHsCAAAA.Boomapriest:BAAALgAECgcJCwAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAABLgAECn8XAAILAAkJDhfaLAAUAgALAAkJDhfaLAAUAgAAAA==.Booshly:BAAALgAECgUJBQAAAA==.Boosta:BAAALgAECgUJBQAAAA==.Bootstrapbil:BAAALgAECgUJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCwAAAA==.Brasserz:BAABLgAECn8wAAIXAAkJoBiqDABZAgAXAAkJoBiqDABZAgAAAA==.Breezybone:BAAALgAECgYJBgAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAABLgAECn8oAAITAAgJjhs6AwAaAgATAAgJjhs6AwAaAgAAAA==.Briochebun:BAABLgAECn8fAAIUAAkJSBzkIACnAgAUAAkJSBzkIACnAgAAAA==.Briollias:BAAALgAECgEJAQAAAA==.Brody:BAAALgAECgEJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgMJAwABLgAECgkJLwAHADwdAA==.Bumpycassock:BAAALgADCgEJAQAAAA==.Bustin:BAABLgAECn8aAAIUAAgJzh6yMQA5AgAUAAgJzh6yMQA5AgAAAA==.Buzzieozzie:BAAALgAECgEJAQAAAA==.',
Bw='Bwangifer:BAABLgAECn8/AAIVAAkJKxpnBQBRAgAVAAkJKxpnBQBRAgAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgAECgEJAQABLgAECgkJMQAXAP8gAA==.Caitriona:BAAALgAECgEJAQABLgAECgkJIAAbAJ0LAA==.Calabera:BAAALgADCgEJAQAAAA==.Calfrunsam:BAAALgAECgEJAQAAAA==.Cannala:BAAALgADCgkJMAAAAA==.Cargae:BAAALgADCggJIgAAAA==.Casstrait:BAAALgAECgQJBwAAAA==.',
Cc='Ccelionn:BAAALgAECgEJAQAAAA==.',
Ce='Celathel:BAABLgAECn8ZAAMVAAkJCBW4AwAeAQAVAAYJYha4AwAeAQALAAYJtxFHhAAXAQAAAA==.Cellysia:BAABLgAECn9BAAMJAAkJpAoOKwBwAQAJAAkJpAoOKwBwAQAOAAcJrwJRXAClAAAAAA==.Celsìus:BAABLgAECn8XAAIFAAYJbhOg1QBEAQAFAAYJbhOg1QBEAQAAAA==.Ceramyth:BAABLgAECn8bAAIIAAYJkB7+AwCBAQAIAAYJkB7+AwCBAQAAAA==.Ceres:BAABLgAECn8/AAIcAAkJdR0fAgClAgAcAAkJdR0fAgClAgAAAA==.Cesara:BAACLgAFFH8JAAMOAAMJFhSRJADSAAAOAAMJFhSRJADSAAAJAAMJJBC+IwCdAAAuAAQKfzwAAw4ACQlHI48EABADAA4ACQlHI48EABADAAkAAglhBCR/ADMAAAAA.',
Ch='Chaahck:BAAALgAECgMJAwAAAA==.Chal:BAAALgAECgYJCAAAAA==.Chaplin:BAAALgAECgIJAgABLgAECgkJPQAdACQSAA==.Chbribs:BAABLgAECn8aAAIeAAkJWBRhHQBiAQAeAAkJWBRhHQBiAQAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgAECgQJCAAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Coldsteel:BAAALgADCgQJBAAAAA==.Columbina:BAACLgAFFH8pAAILAAcJmhb7JgCQAQALAAcJmhb7JgCQAQAuAAQKfxwAAgsACAkKG7dEAOEBAAsACAkKG7dEAOEBAAAA.Comma:BAABLgAECn8UAAISAAcJFxKwHABjAQASAAcJFxKwHABjAQAAAA==.Cooperhowerd:BAAALgADCgkJMQAAAA==.Corein:BAAALgAECgYJCgAAAA==.Corn:BAABLgAECn8fAAIUAAgJiRfSegB5AQAUAAgJiRfSegB5AQAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAACLgAFFH8LAAIfAAUJ6RLXCgAUAQAfAAUJ6RLXCgAUAQAuAAQKf0IAAx8ACQlQI1ECACkDAB8ACQlQI1ECACkDABIAAgk1EFFHAFYAAAAA.Crackundead:BAACLgAFFH8RAAICAAcJ4BF4FwCsAQACAAcJ4BF4FwCsAQAuAAQKfxYAAgIACQmpFR4IANEBAAIACQmpFR4IANEBAAAA.Crapdragon:BAAALgAECggJCwAAAA==.Cravens:BAAALgAECgYJCwAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8/AAIHAAkJWx8mCQAnAwAHAAkJWx8mCQAnAwAAAA==.Cyrinx:BAAALgAECgkJEQAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAABLgAECn8hAAQJAAYJCSCGBADMAQAJAAYJCSCGBADMAQAgAAIJbgylJAA3AAAOAAEJ5AE4nAAXAAAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgAECgQJCQAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dagravytrain:BAAALgADCgMJAwAAAA==.Dajango:BAAALgAECgYJDQAAAA==.Dalend:BAAALgAECgQJBAAAAA==.Damerot:BAACLgAFFH8IAAIRAAMJWBDVNgDXAAARAAMJWBDVNgDXAAAuAAQKfxYAAxEABQk1Ey1CADwBABEABQk1Ey1CADwBABIAAQmeAgtbACEAAAAA.Dandity:BAAALgAECgcJDQAAAA==.Dangerous:BAABLgAECn8dAAIhAAcJdBd8AQCKAQAhAAcJdBd8AQCKAQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAACLgAFFH8GAAIdAAMJ0A69LwCKAAAdAAMJ0A69LwCKAAAuAAQKfxsAAx0ABgkvIVIGAAACAB0ABgkvIVIGAAACACIAAQlDAVqXABkAAAAA.Darnel:BAAALgADCgQJBAAAAA==.Dawnsingers:BAAALgADCgIJAgAAAA==.',
De='Deadbeard:BAACLgAFFH8NAAICAAUJ0x+sQAB1AQACAAUJ0x+sQAB1AQAuAAQKf0cAAgIACQl8Jj4BAIoDAAIACQl8Jj4BAIoDAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAFFAEJAQAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Debased:BAAALgAECgYJDAAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAABLgAECn8WAAMKAAgJQxB4PQB5AQAKAAgJQxB4PQB5AQAaAAUJfwtWWQCsAAAAAA==.Delphina:BAAALgAECgMJBgAAAA==.Demini:BAABLgAECn8dAAIZAAgJ0gwMDADbAAAZAAgJ0gwMDADbAAAAAA==.Demisê:BAACLgAFFH8KAAMEAAMJCAzELQCQAAACAAMJCwd7twC5AAAEAAMJCgvELQCQAAAuAAQKfyIAAwIACQn2F9gyADMCAAIACQkWF9gyADMCAAQABQmGEdk3ALUAAAAA.Demonessa:BAAALgAECgcJEQAAAA==.Demonslyer:BAABLgAECn8lAAMLAAkJoRq9BQDDAQALAAkJAhi9BQDDAQAZAAIJyRbuEQCNAAAAAA==.Derbygirl:BAAALgAECgQJCQAAAA==.Derius:BAAALgAECgUJBQABLgAFFAQJDQAGAEMUAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8jAAMQAAgJkhR4JAC6AQAQAAgJkhR4JAC6AQAjAAYJtQz0HgA3AQAAAA==.Desso:BAABLgAECn9AAAIaAAkJfxlAAgAfAgAaAAkJfxlAAgAfAgAAAA==.Detraz:BAAALgADCgEJAQAAAA==.Devilskin:BAABLgAECn8XAAIiAAgJvQiJFAChAAAiAAgJvQiJFAChAAAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAABLgAECgcJJgAGAEseAA==.Dillinger:BAABLgAECn86AAINAAkJRhhSCQAwAgANAAkJRhhSCQAwAgAAAA==.Dingodgaf:BAACLgAFFH8LAAIUAAIJZQNRWgBgAAAUAAIJZQNRWgBgAAAuAAQKfzgAAhQACAkWDVEXACIBABQACAkWDVEXACIBAAAA.',
Dj='Djinnjuicy:BAAALgAECgEJAQAAAA==.',
Do='Dodo:BAAALgAECgkJBwAAAA==.Dokholliday:BAAALgAECgEJAQAAAA==.Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8rAAIFAAYJSBfNiABlAQAFAAYJSBfNiABlAQAAAA==.Dorianmyth:BAAALgAECgYJBQABLgAECgkJKQAdAJ8RAA==.',
Dr='Draemora:BAAALgAECgEJAQAAAA==.Dragonmynutz:BAAALgAECgYJBwAAAA==.Dragonshammy:BAAALgAFFAEJAQAAAA==.Draknarok:BAABLgAECn8gAAICAAgJRRqbPwAEAgACAAgJRRqbPwAEAgAAAA==.Dranius:BAACLgAFFH8NAAIFAAQJGQnlbQAHAQAFAAQJGQnlbQAHAQAuAAQKfxgAAgUACAm5EySJAMABAAUACAm5EySJAMABAAAA.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAABLgAECn8iAAINAAYJ+hFpBgDwAAANAAYJ+hFpBgDwAAAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAACLgAFFH8LAAMbAAQJLhXoSQAzAQAbAAQJLhXoSQAzAQAcAAEJXgFuLQAoAAAuAAQKfykAAhsACQmTGhUmAEUCABsACQmTGhUmAEUCAAAA.Driztette:BAABLgAECn81AAIdAAkJxSB9AgDAAgAdAAkJxSB9AgDAAgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Druidbearpig:BAAALgAECgYJDQABLgAECgkJJwAbANARAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgABLgAFFAIJBQAkAD4VAA==.Drylustine:BAAALgADCgMJAwAAAA==.Drystine:BAABLgAECn8zAAIZAAkJSh68CwBrAgAZAAkJSh68CwBrAgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.Dugtig:BAAALgAECgcJCgAAAA==.',
['Dí']='Dín:BAAALgAECgIJAgAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgkJKwAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Eg='Eggs:BAAALgAECgIJAwAAAA==.',
Eh='Ehisdv:BAAALgAECgMJAwAAAA==.',
Ei='Eillaura:BAACLgAFFH8KAAIJAAMJEiABFgAQAQAJAAMJEiABFgAQAQAuAAQKfyUAAgkACQksG54LAK0CAAkACQksG54LAK0CAAAA.',
El='Elemag:BAAALgAECgEJAgAAAA==.Eleredra:BAAALgAECgMJAwABLgAECgkJHQAOANgTAA==.Elipsis:BAACLgAFFH8MAAIJAAQJjCBuCgAMAQAJAAQJjCBuCgAMAQAuAAQKfx0AAgkACQmpE1ssAJUBAAkACQmpE1ssAJUBAAAA.Ellessae:BAAALgAECgEJAQAAAA==.Ellyn:BAAALgAECgYJBgAAAA==.Elm:BAABLgAECn9JAAQHAAkJVBTgMwDNAQAHAAkJVBTgMwDNAQAMAAkJ1xQpBwBlAQAeAAYJ+wsxDQCvAAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAACLgAFFH8FAAIGAAMJ7go6dQCyAAAGAAMJ7go6dQCyAAAuAAQKfxsAAgYACQlvGQUvAPUBAAYACQlvGQUvAPUBAAAA.Elycia:BAAALgAFFAEJAQABLgAFFAMJBQAGAO4KAA==.Elyenora:BAAALgAECgQJBAABLgAFFAMJBQAGAO4KAA==.Elyssaelyend:BAAALgAECgYJDAABLgAECgkJLAAHAJ8ZAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emberion:BAAALgAECgYJCAAAAA==.Emmental:BAABLgAECn8pAAIiAAgJ3RDODAD7AAAiAAgJ3RDODAD7AAAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAABLgAECn8YAAMJAAcJdRZJIADAAQAJAAcJdRZJIADAAQAOAAEJdAYlkwAnAAAAAA==.Enricco:BAABLgAECn8tAAIiAAcJaAQoFwCKAAAiAAcJaAQoFwCKAAAAAA==.',
Er='Eramortis:BAAALgADCgYJBgAAAA==.Ereko:BAABLgAECn8lAAIGAAkJOBAURgDPAQAGAAkJOBAURgDPAQAAAA==.Erythorbic:BAABLgAECn8hAAMbAAgJ8xzrKQAzAgAbAAcJfRzrKQAzAgAcAAMJQyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCwAAAA==.',
Ev='Evictor:BAAALgAECgYJEAABLgAECgkJHwAaALMZAA==.',
Ex='Exileelfsam:BAABLgAECn8vAAIXAAkJVwtrHAC5AQAXAAkJVwtrHAC5AQAAAA==.',
Fa='Fallenrose:BAAALgAECgEJAQAAAA==.Fallensk:BAAALgADCgIJAgAAAA==.Falord:BAAALgADCgUJBQAAAA==.Faranth:BAAALgAECgIJAwAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Fatman:BAAALgAECgUJBwAAAA==.Faîle:BAACLgAFFH8nAAMgAAcJexU8FgDGAQAgAAcJexU8FgDGAQAOAAEJ1QGdQQAyAAAuAAQKfyoAAyAACAlEHycIAL0CACAACAlEHycIAL0CAAkABgkhCDNKABABAAAA.',
Fe='Feer:BAABLgAECn8UAAIGAAcJqhC0EwBJAQAGAAcJqhC0EwBJAQAAAA==.Feldron:BAABLgAECn8cAAMkAAkJZh3ACgDmAgAkAAgJGR7ACgDmAgAhAAEJgxjzHQA9AAAAAA==.Felshatter:BAABLgAECn87AAILAAkJUBLnBQC9AQALAAkJUBLnBQC9AQAAAA==.Feltigress:BAABLgAECn8wAAINAAkJnCKZAgD7AgANAAkJnCKZAgD7AgAAAA==.Fendag:BAABLgAECn8ZAAIDAAUJDASyEwBFAAADAAUJDASyEwBFAAAAAA==.',
Ff='Ffugher:BAAALgAECgkJEgAAAA==.Ffugin:BAAALgADCgYJCQAAAA==.Ffugit:BAAALgAECgYJBgAAAA==.Ffuglee:BAAALgAECgcJCgAAAA==.Ffugme:BAABLgAECn84AAIIAAkJoRT2AgDFAQAIAAkJoRT2AgDFAQAAAA==.Ffugnutz:BAAALgAECgYJCwAAAA==.Ffugoff:BAAALgAECgcJCQAAAA==.Ffugstain:BAAALgADCgkJDgAAAA==.Ffugtard:BAABLgAECn8XAAIGAAkJWgsqgwA4AQAGAAkJWgsqgwA4AQAAAA==.Ffugtastic:BAAALgADCgEJAQAAAA==.Ffugtoy:BAAALgAECgYJBgAAAA==.Ffugyou:BAAALgAECgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAABLgAECgYJBwABAAAAAA==.Finnian:BAABLgAECn8zAAITAAkJdh6xCAD/AgATAAkJdh6xCAD/AgAAAA==.Fio:BAACLgAFFH8OAAIKAAQJdSIZHgB/AQAKAAQJdSIZHgB/AQAuAAQKfyoAAwoACQleJbMCAFoDAAoACQleJbMCAFoDABoAAQlJG0JwAFEAAAAA.Firiona:BAABLgAECn8iAAMgAAYJSBg8JACtAQAgAAYJSBg8JACtAQAOAAQJrB0jCABOAQABLgAECggJOgAZAHUcAA==.Fistfuloftok:BAAALgAECgIJAgABLgAECgkJLAANAB4iAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIlAAgJzRc/JACKAQAlAAgJzRc/JACKAQAAAA==.Flinn:BAABLgAECn8dAAIeAAkJBh6yBgCQAgAeAAkJBh6yBgCQAgAAAA==.Flowers:BAABLgAECn8zAAMLAAkJgiBXCwDtAgALAAkJgiBXCwDtAgAZAAQJVRwLNQDqAAAAAA==.Fläva:BAABLgAECn8UAAMUAAYJVxbAsgAbAQAUAAYJdxXAsgAbAQAIAAEJqhhjFQBGAAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgYJBgAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Friendlyhoss:BAAALgADCgEJAQAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8wAAIFAAkJBBqZOAA2AgAFAAkJBBqZOAA2AgAAAA==.',
Fu='Furiousdemon:BAAALgADCgEJAQAAAA==.Furysbubble:BAAALgAECgEJAQAAAA==.Furyswarm:BAAALgAECgkJAgAAAA==.',
['Fá']='Fállen:BAAALgAECgEJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Ga='Gadrîel:BAAALgAECgUJAQAAAA==.Gafocalypse:BAABLgAECn8gAAIEAAkJwhVNFQDCAQAEAAkJwhVNFQDCAQAAAA==.Gaius:BAAALgAECgcJDQAAAA==.Garddidit:BAAALgADCgUJBQABLgAECggJJAAVAG8eAA==.',
Ge='Gernaj:BAAALgAECgEJAQAAAA==.Getvoked:BAAALgAECgUJBQAAAA==.',
Gh='Ghostffudge:BAAALgAECgkJCQAAAA==.',
Gi='Ginarrah:BAAALgAECgYJBgAAAA==.Ginsan:BAAALgADCgIJAgAAAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDQAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.Goovs:BAAALgAECgcJCQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgkJNAAAAA==.Grep:BAAALgAECgQJCQAAAA==.Greygor:BAABLgAECn8dAAIRAAkJfAllCgAnAQARAAkJfAllCgAnAQAAAA==.Grotok:BAABLgAECn8bAAMCAAkJARSGDABxAQACAAkJDxGGDABxAQADAAIJAx1/EQBTAAAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgkJEQAAAA==.Gurgatron:BAAALgAECggJDgABLgAFFAMJBgASADogAA==.Guulen:BAAALgAECgMJAwAAAA==.',
Gy='Gyozitgar:BAAALgAECgEJAwAAAA==.',
Ha='Halaragdan:BAAALgADCgEJAQAAAA==.Halraku:BAAALgAECgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECggJDwAAAA==.Halygosa:BAAALgAECgEJAQAAAA==.Hamoro:BAAALgADCgYJBgABLgAECgcJDQABAAAAAA==.Hariffug:BAAALgAECgYJCgAAAA==.Hasklaufien:BAAALgAECgIJBgAAAA==.',
He='Healinside:BAAALgAECgYJBgAAAA==.Hemmingway:BAAALgADCggJEQAAAA==.Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hiest:BAAALgAECgYJEAAAAA==.Hinderberg:BAAALgAECggJCAAAAA==.',
Ho='Holdor:BAAALgAECgIJAgAAAA==.Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAABLgAECn8XAAMIAAgJLRmYBwD4AAAIAAgJmBiYBwD4AAAUAAIJWA1cTQBRAAAAAA==.',
Hu='Hugulin:BAABLgAECn8iAAIGAAkJ+gWYjQAkAQAGAAkJ+gWYjQAkAQAAAA==.Huntârdandy:BAAALgADCggJEAAAAA==.',
['Hå']='Håtsuharu:BAAALgADCgkJCQAAAA==.',
['Hé']='Héllboy:BAAALgAECgEJAQAAAA==.',
Ia='Iamspeed:BAAALgADCgUJBQAAAA==.',
Ic='Iceblocklulz:BAAALgAECgMJAgAAAA==.Icedsoul:BAABLgAECn8jAAIFAAkJ6QiOngA9AQAFAAkJ6QiOngA9AQAAAA==.Icee:BAAALgADCgcJCgAAAA==.Iceflame:BAAALgAECgMJAwABLgAECgkJLwAHADwdAA==.',
Ig='Iggey:BAABLgAECn8zAAIfAAkJjBz/BwB1AgAfAAkJjBz/BwB1AgAAAA==.',
Ik='Ikigai:BAAALgAECgQJBAAAAA==.Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn89AAILAAkJ4xZUBQDWAQALAAkJ4xZUBQDWAQAAAA==.Illadus:BAABLgAECn8kAAILAAkJ1QvUFQDXAAALAAkJ1QvUFQDXAAAAAA==.Illed:BAAALgADCgcJBwAAAA==.Illiviix:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgkJEwAAAA==.Intoxicated:BAABLgAECn8jAAIaAAkJAwyRNAAxAQAaAAkJAwyRNAAxAQAAAA==.',
Io='Ione:BAAALgADCgcJBwAAAA==.',
Ir='Iranna:BAACLgAFFH8lAAQhAAgJViJ9AQDPAQAhAAUJqSB9AQDPAQAmAAYJhhsOAwB8AQAkAAQJoiAgEAAOAQAuAAQKfzUABCEACAmQJRYDAI4CACYACAlwI0YBAN8CACEABwn2IBYDAI4CACQABwmKIAgVAPkBAAAA.Irondihh:BAAALgAECgMJAwABLgAECgcJJgAGAEseAA==.',
It='Itsredbelow:BAAALgAECgYJEAAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAFFAMJBwAHAH8KAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgkJKwACAG0gAA==.Jaggedace:BAAALgAECgUJBQAAAA==.Janaki:BAABLgAECn8eAAMHAAgJsxkwHwBNAgAHAAgJsxkwHwBNAgAMAAQJghbuUQDGAAAAAA==.',
Je='Jehoichin:BAAALgAECgQJBAAAAA==.Jesmah:BAAALgAECgYJBgAAAA==.Jestêr:BAABLgAFFH8SAAMhAAUJyh0sAQB8AQAhAAUJyh0sAQB8AQAkAAEJbgfgPABIAAABLgAFFAcJJwAgAHsVAA==.',
Ji='Jibbtotem:BAAALgAECgQJBAABLgAECggJEgABAAAAAA==.Jivanos:BAAALgAECgQJBQAAAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn9RAAIUAAkJJhfsNwAiAgAUAAkJJhfsNwAiAgAAAA==.',
Ju='Juicie:BAAALgAECgYJDwAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQARABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQARABkeAA==.',
['Jè']='Jèstèr:BAABLgAFFH8NAAIdAAUJzxOeJQBUAQAdAAUJzxOeJQBUAQABLgAFFAcJJwAgAHsVAA==.',
Ka='Kainoa:BAAALgADCgMJAwAAAA==.Kalea:BAAALgAECgIJBwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECgkJGAADAIwbAA==.Kalietha:BAAALgAECgEJAQAAAA==.Kalila:BAAALgAFFAEJAQAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kassandrah:BAAALgAECgIJAgAAAA==.Kat:BAABLgAECn8YAAMlAAkJZhS7GgDPAQAlAAcJNBq7GgDPAQAKAAcJZgarTwCUAAAAAA==.Katsuko:BAABLgAECn8zAAIEAAkJyRhlEAAFAgAEAAkJyRhlEAAFAgAAAA==.Kattnirra:BAABLgAECn8uAAIGAAkJSREAPADwAQAGAAkJSREAPADwAQAAAA==.Katze:BAABLgAECn9PAAIGAAkJ8xgQIwBXAgAGAAkJ8xgQIwBXAgAAAA==.Kauwela:BAAALgADCgUJBQAAAA==.Kaylé:BAAALgAECgYJDQAAAA==.',
Ke='Keabdeo:BAAALgADCgcJBwAAAA==.Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgcJBwAAAA==.Keepper:BAABLgAECn8oAAIbAAkJ8hCaVwCWAQAbAAkJ8hCaVwCWAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kelsior:BAAALgAECgQJBAAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8WAAIJAAgJRRB5NAAzAQAJAAgJRRB5NAAzAQAAAA==.Ketheric:BAABLgAFFH8IAAMEAAMJCA62OgBLAAACAAMJBQnhcwBxAAAEAAEJlBu2OgBLAAABLgAFFAUJEgAdAG0fAA==.',
Kh='Khrixtie:BAAALgADCgUJAQAAAA==.',
Ki='Killahaseo:BAAALgAECgkJDwABLgAECgkJKwAQAF8YAA==.Killmoedee:BAABLgAECn9AAAMIAAkJ0CGhAgADAwAIAAkJ0CGhAgADAwAUAAEJrRrEZwFOAAAAAA==.Kittyclyzm:BAAALgAFFAEJAQABLgAFFAMJCQAOABYUAA==.Kitwryn:BAAALgADCgkJDQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCgABLgAECgYJBwABAAAAAA==.',
Kl='Klexios:BAABLgAECn85AAISAAgJvQVRCADTAAASAAgJvQVRCADTAAAAAA==.',
Ko='Kodohoof:BAAALgAECgYJDwAAAA==.Koopa:BAAALgAECgkJEQAAAA==.Korbandallas:BAABLgAECn8WAAMCAAgJ1gjkGgDdAAACAAgJ1gjkGgDdAAADAAEJzAd9GAAkAAAAAA==.Kozzmo:BAAALgAECgEJAQAAAA==.',
Kr='Kracious:BAAALgAECgUJBQAAAA==.Kratosaurion:BAAALgADCgMJAwAAAA==.Kraulhoof:BAAALgAECgEJAgABLgAECgYJBwABAAAAAA==.Krispy:BAABLgAECn8iAAIcAAkJUg8bDAB9AQAcAAkJUg8bDAB9AQAAAA==.Kruise:BAAALgAECgcJCAAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn8/AAIlAAkJwB/wBQDfAgAlAAkJwB/wBQDfAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
Ky='Kylenna:BAAALgAECgMJAwABLgAFFAMJBQAGAO4KAA==.',
['Kö']='Köz:BAABLgAECn8WAAMdAAkJYRMMCADLAQAdAAgJ+xMMCADLAQAiAAIJAwg9LgAsAAAAAA==.',
La='Laetri:BAABLgAECn8kAAILAAkJ2RRyRgCzAQALAAkJ2RRyRgCzAQAAAA==.Lailiia:BAAALgAECgcJCgABLgAECgkJOgAJAFAkAA==.Lasttok:BAABLgAECn8sAAMNAAkJHiIoAwDnAgANAAkJvB8oAwDnAgAMAAgJvBpjIADFAQAAAA==.Laylene:BAAALgAECgcJEAAAAA==.Lazloo:BAABLgAECn8yAAMRAAkJcSWdAgBIAwARAAkJbSWdAgBIAwAfAAcJOhwTFwCjAQAAAA==.Lazymidget:BAABLgAECn8eAAIWAAcJJh1VLQDFAQAWAAcJJh1VLQDFAQAAAA==.Lazytok:BAAALgAECgMJBgAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAABLgAECn8uAAMEAAcJShRoBQBxAQAEAAcJShRoBQBxAQADAAEJBQs7GAAmAAABLgAECgkJPgAXAAoUAA==.Legindkiller:BAAALgADCgkJNAAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAkJFAAEAMgeAA==.',
Li='Lightace:BAABLgAECn8ZAAIUAAcJSgdQ0gDwAAAUAAcJSgdQ0gDwAAAAAA==.Lilgeezus:BAAALgADCgEJAQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAABLgAECn8cAAIXAAkJASFCBQDTAgAXAAkJASFCBQDTAgAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8fAAIbAAgJZQhWlAATAQAbAAgJZQhWlAATAQAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Loril:BAAALgAECgQJBAAAAA==.Lostdraco:BAABLgAECn8cAAIjAAcJrwXEEwDPAAAjAAcJrwXEEwDPAAAAAA==.Lostdream:BAABLgAECn8eAAMLAAcJfAN61gCIAAALAAYJLwN61gCIAAAZAAIJKwM2fQAjAAAAAA==.Loun:BAABLgAECn9FAAIlAAkJwBlUDgBUAgAlAAkJwBlUDgBUAgAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgAECgEJAgABLgAECggJHwAKAEYeAA==.Luteil:BAAALgADCgMJAwAAAA==.Luvlycruelty:BAABLgAECn8gAAIbAAkJnQs0CgBgAQAbAAkJnQs0CgBgAQAAAA==.',
Ly='Lyn:BAECLgAFFH8KAAIlAAQJkiTjDwCnAQAlAAQJkiTjDwCnAQAuAAQKf04AAiUACQmZJlQAAIYDACUACQmZJlQAAIYDAAAA.',
Ma='Mackenziiee:BAACLgAFFH8KAAIGAAMJfw88ZADdAAAGAAMJfw88ZADdAAAuAAQKfzIAAgYACQnoHcoVAKYCAAYACQnoHcoVAKYCAAAA.Mackthyra:BAAALgADCgcJBwABLgAFFAMJCgAGAH8PAA==.Madglowup:BAABLgAECn8kAAImAAkJ4iLEAAAmAwAmAAkJ4iLEAAAmAwAAAA==.Maggie:BAAALgAECgIJAgAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8gAAIFAAkJhxzBLwBaAgAFAAkJhxzBLwBaAgAAAA==.Magtaki:BAAALgAECgkJCAAAAA==.Magyar:BAEALgAECgUJBQAAAA==.Mainline:BAAALgAECggJDwAAAA==.Maizepriest:BAABLgAECn88AAIOAAkJbSK/BAAMAwAOAAkJbSK/BAAMAwAAAA==.Maliaa:BAAALgAECgMJAwAAAA==.Mannysaf:BAABLgAECn8jAAIRAAgJrA4ENwBrAQARAAgJrA4ENwBrAQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAkJFQAFALkUAA==.Marus:BAAALgADCgMJAwAAAA==.Maxz:BAAALgAECgEJAQAAAA==.',
Mc='Mcmurtrey:BAABLgAFFH8FAAIkAAIJxwodIQB6AAAkAAIJxwodIQB6AAAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Meerkat:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Megazord:BAAALgAECgIJBAABLgAECggJOgAZAHUcAA==.Mellowblink:BAABLgAECn8pAAIFAAgJxhdQWADUAQAFAAgJxhdQWADUAQABLgAECggJOgAZAHUcAA==.Melorian:BAAALgADCgkJEAAAAA==.Melvier:BAAALgAECgEJAQAAAA==.Memeñtomori:BAABLgAECn8uAAMgAAkJGwY2DwDmAAAgAAkJGwY2DwDmAAAOAAUJTwNVdwBRAAAAAA==.Menara:BAAALgAECgYJEAAAAA==.',
Mi='Micromancer:BAAALgADCgMJAwAAAA==.Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAFFAEJAQAAAA==.Milkyboy:BAAALgADCgQJBAAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH9XAAQGAAkJNCZSAABfAwAGAAkJjCVSAABfAwAWAAgJHCNDAQCJAgAXAAMJIyTEIADTAAAuAAQKfz8ABBcACQnbJlYAAIsDABcACQk6JlYAAIsDABYACAkCJu0DAGUDAAYABglLJAxkAH0BAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECgkJMwAkAMIXAA==.Miravus:BAABLgAECn8zAAMkAAkJwheAHACyAQAkAAkJJheAHACyAQAhAAUJSRIGEAAkAQAAAA==.Mirlanda:BAABLgAECn8dAAIhAAgJ2wd5FQDUAAAhAAgJ2wd5FQDUAAAAAA==.Misttie:BAABLgAECn8bAAIlAAgJqw9fKABvAQAlAAgJqw9fKABvAQABLgAFFAQJDAAJAIwgAA==.',
Mo='Monie:BAAALgAECgEJAQAAAA==.Monkerick:BAABLgAECn8WAAQaAAkJkxmmBwAVAQAaAAUJ3RamBwAVAQAKAAcJgQolXgD+AAAlAAEJGhcaEgBBAAAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Moonfalla:BAAALgAECgEJAQAAAA==.Mooningyall:BAAALgAECgMJAwAAAA==.Morber:BAAALgAECgQJBQAAAA==.Mordeckai:BAAALgADCggJBwAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgkJMQAAAA==.',
Mt='Mtmind:BAAALgAECgMJAwABLgAFFAUJAQABAAAAAA==.',
Mu='Murkoobi:BAAALgAECgMJBQAAAA==.Mursk:BAAALgAECgMJBAAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJBQAAAA==.Mystáke:BAACLgAFFH8FAAIKAAIJxAufVABZAAAKAAIJxAufVABZAAAuAAQKfx0AAgoACQmLFsgIAKIBAAoACQmLFsgIAKIBAAAA.',
['Mä']='Mäble:BAAALgAECgEJAQAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mí']='Mícky:BAAALgAECgEJAQAAAA==.',
['Mò']='Mòus:BAABLgAECn8XAAQjAAYJPg0dIQAkAQAjAAYJPg0dIQAkAQAQAAUJVAaMRwC8AAAPAAEJQQGSRgAXAAABLgAFFAQJDQAGAEMUAA==.',
['Mó']='Mómo:BAAALgAECggJCwAAAA==.Móus:BAAALgAECgUJDwABLgAFFAQJDQAGAEMUAA==.',
Na='Nagatok:BAAALgAECgkJDAABLgAECgkJLAANAB4iAA==.Narcissus:BAAALgAECgYJBgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAcJJwAgAHsVAA==.Naro:BAAALgAECgcJDAABLgAECgkJNgAFAC0kAA==.Naromancer:BAABLgAECn82AAIFAAkJLSRBDQAPAwAFAAkJLSRBDQAPAwAAAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn82AAQeAAkJURQyIwA2AQAMAAcJrRNTLgBoAQAeAAcJERMyIwA2AQANAAUJIhAyIADeAAAAAA==.Nautrium:BAAALgAECgMJBAAAAA==.Nazari:BAAALgAECgEJAQAAAA==.',
Ne='Necrotis:BAAALgADCgkJNAAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn86AAMJAAkJUCTVAQCVAwAJAAkJUCTVAQCVAwAOAAYJzxq6UADOAAAAAA==.Neytholy:BAAALgAECgcJDAAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.Nezukö:BAAALgAECgUJCQAAAA==.',
Ni='Nienna:BAAALgAECgIJAwAAAA==.Nikkisan:BAAALgAECgMJAwAAAA==.Nitalan:BAAALgAECgMJAwAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAFFAEJAwAAAA==.',
No='Noa:BAAALgADCgEJAQAAAA==.Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAACLgAFFH8MAAIFAAIJvAK0XABkAAAFAAIJvAK0XABkAAAuAAQKfxYAAgUABQmLAwgSAZEAAAUABQmLAwgSAZEAAAAA.Nokaj:BAAALgAECgEJAgAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgYJDAAAAA==.Noras:BAABLgAECn8fAAMaAAkJsxkAEQA/AgAaAAkJnxkAEQA/AgAlAAUJshO5QgDvAAAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8rAAIfAAkJqRJwEwDGAQAfAAkJqRJwEwDGAQAAAA==.Notagnoblin:BAEBLgAFFH8aAAIEAAUJHyLbDAAqAQAEAAUJHyLbDAAqAQABLgAFFAgJJgAlAKokAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Oa='Oaklyn:BAAALgAECgMJAwAAAA==.Oakshrus:BAAALgAECgEJAgAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIjAAkJGQ6OCgB1AQAjAAkJGQ6OCgB1AQAAAA==.Obolisq:BAAALgAECgEJAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJEQAAAA==.',
Od='Oddsoul:BAAALgAECgYJDwAAAA==.',
Og='Ogrelurd:BAABLgAECn8XAAMfAAcJSSBeDAAhAgAfAAcJSSBeDAAhAgARAAQJGxgoYADVAAAAAA==.',
Oh='Ohlordy:BAAALgAECgcJEQAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJCgAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Oo='Oougway:BAAALgAECgYJBwAAAA==.',
Op='Ophelia:BAACLgAFFH8PAAMnAAMJvxbVBADpAAAnAAMJvxbVBADpAAAbAAIJRxFPnwCLAAAuAAQKf0wABBsACQkqI+0lAEYCABsACAm7He0lAEYCACcABwluIssJAMUBABwAAQmmCJh0ADAAAAAA.',
Or='Orakwa:BAABLgAECn8kAAMRAAkJxxowAgB5AgARAAkJxBowAgB5AgASAAUJmhXHKwDaAAAAAA==.',
Os='Osiyo:BAAALgAECgEJAQAAAA==.',
Ou='Outen:BAABLgAECn8hAAIGAAkJSg04EABzAQAGAAkJSg04EABzAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Palalamadi:BAAALgADCgMJAwAAAA==.Pallinda:BAABLgAECn8tAAMTAAkJfBYIGABIAgATAAkJfBYIGABIAgAUAAkJkRLMWgC9AQAAAA==.Panakananama:BAAALgAECgcJDwAAAA==.Panz:BAABLgAECn82AAMQAAkJCwuILwB7AQAQAAkJCwuILwB7AQAjAAEJIA5MJwAvAAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papagrip:BAAALgAFFAIJBAABLgAFFAMJBgAbAIALAA==.Papalock:BAABLgAFFH8GAAIbAAMJgAucgADDAAAbAAMJgAucgADDAAAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgcJCAAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgMJCAAAAA==.Pazuzuu:BAAALgAECgIJAgABLgAECgkJJwAbANARAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Peanuttbutte:BAAALgAECgEJAQAAAA==.Pendulum:BAAALgAECgEJAQAAAA==.Pendulumlaw:BAACLgAFFH8KAAIfAAMJ3hBkKQDHAAAfAAMJ3hBkKQDHAAAuAAQKfxQAAx8ACQk2G5AHAH4CAB8ACQkdG5AHAH4CABEAAgkeEgSAAHcAAAAA.Pennypacker:BAAALgAECggJDwAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAABLgAECn8YAAMGAAYJcRCKkQAcAQAGAAYJcRCKkQAcAQAWAAUJVAgkIwCaAAAAAA==.',
Ph='Phara:BAABLgAECn8cAAQOAAkJcwswKgCAAQAOAAkJcwswKgCAAQAgAAUJZgirNgDwAAAJAAIJlAFvfAA3AAAAAA==.Phenomenon:BAAALgADCgYJBgAAAA==.Phoel:BAAALgADCgkJGAAAAA==.Phoopalychu:BAAALgAECgUJBQABLgAECgkJJAAKAKcSAA==.Phoopanchu:BAABLgAECn8kAAIKAAkJpxI5KgDbAQAKAAkJpxI5KgDbAQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pillowpantsu:BAAALgAECgYJBgAAAA==.Pinkbuns:BAABLgAECn9PAAIFAAkJsxwUBgBBAgAFAAkJsxwUBgBBAgAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn8+AAIVAAkJyiRgAAARAwAVAAkJyiRgAAARAwAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsthyr:BAAALgAECgYJBwAAAA==.Popsy:BAABLgAECn8jAAIUAAkJ9hATWgC/AQAUAAkJ9hATWgC/AQAAAA==.Potatoad:BAAALgAECggJCAAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8vAAIRAAkJCiFBDACmAgARAAkJCiFBDACmAgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAgJGAACAKskAA==.Prideflag:BAAALgAECgMJAwAAAA==.Priesthealer:BAAALgADCgkJCQAAAA==.Priestin:BAAALgAECgEJAQAAAA==.Primaldead:BAACLgAFFH8HAAIbAAIJXQuppQCFAAAbAAIJXQuppQCFAAAuAAQKf1kAAhsACQnMHLsTALACABsACQnMHLsTALACAAAA.Pristin:BAAALgAECgcJDgAAAA==.Profundity:BAABLgAECn8WAAMKAAcJDw/OFADtAAAKAAcJDw/OFADtAAAaAAEJNRAwnQAyAAAAAA==.',
Ps='Psyduck:BAAALgAFFAIJAgABLgAFFAkJZwAUAAgmAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8rAAICAAkJbSAVFQDJAgACAAkJbSAVFQDJAgAAAA==.',
Qe='Qeini:BAABLgAECn82AAIgAAkJjBmIDgCGAgAgAAkJjBmIDgCGAgAAAA==.',
Ra='Radrin:BAAALgAECgUJCwAAAA==.Rafoff:BAABLgAECn8bAAIQAAkJZQq6CgDEAAAQAAkJZQq6CgDEAAAAAA==.Rahll:BAAALgADCgkJNAAAAA==.Rancoramble:BAABLgAECn8bAAIEAAkJjQY7MADgAAAEAAkJjQY7MADgAAAAAA==.Randis:BAABLgAECn8yAAMCAAkJCA8FWwC2AQACAAkJCA8FWwC2AQADAAYJoQKRKQCHAAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Rantcasey:BAABLgAFFH8GAAIGAAMJsg+jNADVAAAGAAMJsg+jNADVAAABLgAFFAMJCgAfAN4QAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razlek:BAAALgAECgUJBQAAAA==.Razonghoul:BAABLgAECn9FAAICAAkJvCISDQAFAwACAAkJvCISDQAFAwAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Rejine:BAAALgAECgIJAgAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAABLgAECn8WAAQTAAcJsg3TEACkAAATAAYJugzTEACkAAAUAAQJjAnJLgGBAAAIAAEJCgICTwAVAAAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAABLgAECn8gAAIGAAkJciRsHAB6AgAGAAkJciRsHAB6AgAAAA==.Reversewally:BAABLgAFFH8KAAIkAAMJKwrkIAB7AAAkAAMJKwrkIAB7AAAAAA==.Rexiis:BAABLgAECn8nAAMbAAkJ0BGMRQDKAQAbAAkJ0BGMRQDKAQAnAAEJAABdNAAzAAAAAA==.Reyth:BAABLgAECn8aAAIFAAkJpQl7JgC+AAAFAAkJpQl7JgC+AAAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8mAAIkAAcJKyG9EACcAgAkAAcJKyG9EACcAgAAAA==.',
Ri='Rightintwo:BAAALgADCgUJBQAAAA==.Rimos:BAAALgAECgMJBAAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn9FAAMiAAkJ4hXsGQASAgAiAAkJ4hXsGQASAgAdAAYJGA31cAAJAQAAAA==.Rivenwood:BAAALgAECgEJAwAAAA==.',
Ro='Rockadin:BAABLgAECn8bAAIUAAYJQBRrugAQAQAUAAYJQBRrugAQAQAAAA==.Rokki:BAABLgAECn9EAAIFAAkJPhV2BwAQAgAFAAkJPhV2BwAQAgAAAA==.Roostor:BAAALgAECgQJCAAAAA==.Rosael:BAAALgAECgEJAQAAAA==.Roundhouse:BAABLgAECn8aAAIlAAkJZBhWEAA6AgAlAAkJZBhWEAA6AgAAAA==.',
Ru='Rubbmytotems:BAABLgAECn8UAAIiAAcJiAtITwD5AAAiAAcJiAtITwD5AAAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8yAAMGAAkJjhcAMQAYAgAGAAkJjhcAMQAYAgAWAAIJrQn8egBXAAAAAA==.Rumí:BAABLgAECn8hAAILAAkJYAkmbwBFAQALAAkJYAkmbwBFAQAAAA==.Russell:BAAALgADCgkJKgAAAA==.Rutgore:BAACLgAFFH8FAAIkAAIJPhUdMQCfAAAkAAIJPhUdMQCfAAAuAAQKfzgAAiQACQlHHoIIAJ4CACQACQlHHoIIAJ4CAAAA.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDQAAAA==.Safewerd:BAEBLgAECn8ZAAMKAAkJUBHFQABrAQAKAAkJUBHFQABrAQAaAAMJNgeRhgBNAAAAAA==.Saitama:BAABLgAECn8wAAIaAAgJ9B0cAwDYAQAaAAgJ9B0cAwDYAQAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgcJEAAAAA==.Saraceleste:BAABLgAECn8YAAIFAAcJWw6WFwAeAQAFAAcJWw6WFwAeAQAAAA==.Sarahfi:BAABLgAECn8WAAMIAAgJ0RDaBQAvAQAIAAcJYBDaBQAvAQAUAAcJ/Ah7+QC/AAAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAABLgAECn8nAAIbAAkJpxRlBgDLAQAbAAkJpxRlBgDLAQAAAA==.Sarasophie:BAAALgAECgUJBQAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgcJEwAAAA==.Sathenazarke:BAACLgAFFH8iAAMjAAYJVR7SAADoAQAjAAYJVR7SAADoAQAPAAYJ5wudGAAOAQAuAAQKfzYABCMACQlgIo0EACwCACMABwnoII0EACwCAA8ACAnkGNIRACECABAABwncGqEbAOsBAAEuAAUUCAklACEAViIA.Saths:BAAALgADCgEJAQABLgAECggJEwABAAAAAA==.',
Sc='Schallue:BAABLgAECn8gAAIoAAgJkAh8BwAoAQAoAAgJkAh8BwAoAQAAAA==.Schism:BAAALgAECgYJEAAAAA==.Scoban:BAACLgAFFH8rAAITAAgJTiF8AwC1AgATAAgJTiF8AwC1AgAuAAQKfywAAhMACQkfIAsOAKgCABMACQkfIAsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Selise:BAAALgAECgQJBAAAAA==.Selithel:BAABLgAECn8XAAIZAAgJ4AfgLgAOAQAZAAgJ4AfgLgAOAQAAAA==.Seraphnite:BAABLgAECn8UAAIUAAgJ+AzWigBbAQAUAAgJ+AzWigBbAQABLgAECgQJBAABAAAAAA==.Serioussurv:BAABLgAECn8mAAMGAAcJSx6iBwAUAgAGAAcJSx6iBwAUAgAXAAcJARS4AwBtAQAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgkJMwAEAMkYAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAABLgAECn8WAAQOAAcJtgZTXQCiAAAOAAYJowdTXQCiAAAgAAUJUQWUWgCVAAAJAAEJFgHNfgAXAAAAAA==.Shaeliana:BAAALgAECgQJDgAAAA==.Shalera:BAAALgAECgkJBwAAAA==.Shaohlin:BAAALgAECgUJDQAAAA==.Shaqfu:BAAALgADCgkJJwAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shawk:BAAALgAECgEJAQAAAA==.Shayy:BAABLgAECn8aAAIgAAgJLw84BgCpAQAgAAgJLw84BgCpAQAAAA==.Shields:BAAALgAECgkJCQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAABLgAECn9VAAIFAAkJWxyRBACJAgAFAAkJWxyRBACJAgAAAA==.Shivers:BAAALgAFFAMJAwAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Shockers:BAAALgAECgQJCAAAAA==.Sholin:BAABLgAECn9BAAIlAAkJ4iSQAQBUAwAlAAkJ4iSQAQBUAwAAAA==.Shomea:BAABLgAECn8qAAMEAAgJlQj1CQDYAAAEAAgJlQj1CQDYAAACAAMJ9QbVJAF9AAAAAA==.Shugz:BAAALgADCgkJLAAAAA==.Shumai:BAAALgAECgkJEAAAAA==.',
Si='Sikotick:BAABLgAECn8lAAIHAAkJXx1RFwCMAgAHAAkJXx1RFwCMAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAACLgAFFH8dAAIFAAYJ8R4cHgB+AQAFAAYJ8R4cHgB+AQAuAAQKfzkAAgUACQkRIUUaAL0CAAUACQkRIUUaAL0CAAAA.Silverbolt:BAABLgAECn8vAAIRAAkJ4A6sKwCmAQARAAkJ4A6sKwCmAQAAAA==.Simbelmyne:BAAALgAECgQJCAAAAA==.Sinderone:BAACLgAFFH8mAAMTAAgJxBIOCQArAgATAAgJxBIOCQArAgAUAAIJlwz/mwCDAAAuAAQKf0AAAxMACQl/H0gIAAcDABMACQl/H0gIAAcDABQABQn9FwXeAOEAAAAA.',
Sk='Skaaduush:BAAALgAECgYJDAAAAA==.Skyjin:BAAALgAECgIJAgAAAA==.Skyne:BAAALgAECgEJAQAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn87AAICAAkJwCD2EwDQAgACAAkJwCD2EwDQAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Slippinwater:BAAALgAECgIJAgAAAA==.Sllew:BAACLgAFFH8HAAICAAMJthnohAD/AAACAAMJthnohAD/AAAuAAQKfy0AAgIACQkVIugPAO0CAAIACQkVIugPAO0CAAAA.Slothfu:BAAALgAECgEJAQAAAA==.Slye:BAAALgAECgEJAQAAAA==.Slyhoof:BAAALgAECgYJCAABLgAECgkJJQALAKEaAA==.Slyvanna:BAAALgAECgMJBAABLgAECgkJJQALAKEaAA==.Slèw:BAAALgAECgQJBwAAAA==.',
Sm='Smartwater:BAABLgAECn8VAAIUAAcJSA04GwAFAQAUAAcJSA04GwAFAQAAAA==.Smitestuff:BAAALgAECgYJDwAAAA==.Smokymcpot:BAAALgADCgYJBgAAAA==.Smoulder:BAAALgAECggJDgAAAA==.',
Sn='Snigles:BAABLgAECn8/AAMhAAkJMxraBAA9AgAhAAkJuxfaBAA9AgAkAAcJVhM5BACAAQAAAA==.Sniperism:BAAALgAECgEJAQAAAA==.Snurp:BAAALgAECgEJAQABLgAFFAQJCwADAE0bAA==.',
So='Softnsquishy:BAAALgAECgYJBQAAAA==.Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgAECgEJAQAAAA==.Souei:BAAALgADCgEJAQABLgAECgkJGwACAAEUAA==.Soulfinder:BAAALgADCgMJAwAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.Southpau:BAAALgADCgUJBQAAAA==.',
Sp='Spartos:BAABLgAECn8UAAIRAAYJsBRxQABDAQARAAYJsBRxQABDAQAAAA==.Speedy:BAAALgAECgUJCAAAAA==.Sposi:BAEBLgAECn84AAIEAAkJzSGzBQDLAgAEAAkJzSGzBQDLAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.Sprinkle:BAAALgAECgIJAgAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAABLgAECn8jAAMdAAYJXwZpjQC/AAAdAAYJXwZpjQC/AAAiAAUJ7AQydwCIAAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAABLgAECn8eAAIRAAkJWx2/EgBcAgARAAkJWx2/EgBcAgAAAA==.Stoneweaver:BAAALgAECgEJAwABLgAECgkJLwAHADwdAA==.',
Su='Subliminal:BAABLgAECn8XAAMkAAkJChG4JABvAQAkAAkJChG4JABvAQAmAAEJswxMJQAxAAAAAA==.Sumasuka:BAABLgAECn8UAAMdAAgJehTtCgCIAQAdAAYJxBbtCgCIAQAiAAQJvwcZGQB4AAAAAA==.Sumbtch:BAAALgAECgUJCgAAAA==.Sungdihhwoo:BAAALgAECgIJAgABLgAECgcJJgAGAEseAA==.Susann:BAAALgAFFAEJAQABLgAFFAQJDQAGAEMUAA==.',
Sv='Svartalfar:BAAALgADCgcJBgAAAA==.',
Sy='Syravia:BAABLgAECn8oAAIUAAkJtAWAuAATAQAUAAkJtAWAuAATAQAAAA==.',
['Sé']='Séraphyne:BAAALgAECgYJDgAAAA==.',
['Sò']='Sòl:BAAALgAFFAIJAgABLgAFFAQJBwAIABASAA==.',
Ta='Talarin:BAAALgAECggJEgAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAABLgAECn8ZAAIoAAkJ5RE0AQBXAQAoAAkJ5RE0AQBXAQAAAA==.Tatersmonk:BAECLgAFFH8mAAIlAAgJqiRRAgBlAgAlAAgJqiRRAgBlAgAuAAQKfyMAAiUACQnpJLsDAFQDACUACQnpJLsDAFQDAAAA.Taterthot:BAAALgAECgEJAQAAAA==.Tavinrayn:BAABLgAECn8vAAMoAAkJBB51AAAVAgAoAAkJBB51AAAVAgAFAAMJ3Aa5IAF3AAAAAA==.Tazzar:BAABLgAECn8/AAIQAAkJoQ/NIwC+AQAQAAkJoQ/NIwC+AQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECgkJSQAHAFQUAA==.Tekesh:BAAALgAECgMJCQAAAA==.Tekêsh:BAABLgAECn8bAAMIAAgJZCO+BACsAgAIAAgJZCO+BACsAgAUAAYJKxXnqQAoAQAAAA==.Telarin:BAABLgAECn8kAAQXAAkJmRnJBQAEAQAGAAcJ9RvUYgCAAQAXAAgJ1hHJBQAEAQAWAAEJuAOdRAAhAAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.Teshara:BAAALgAECgMJBAAAAA==.Tezrian:BAAALgAECgYJCQABLgAECggJOgAZAHUcAA==.',
Th='Thalliana:BAAALgAECgQJEAAAAA==.Thandor:BAAALgAECgYJEgAAAA==.Thanedrius:BAAALgAECgUJBQAAAA==.Thebigdawg:BAACLgAFFH8TAAIKAAMJxiFTGwDtAAAKAAMJxiFTGwDtAAAuAAQKfxwAAgoACQnjHu8IAAwDAAoACQnjHu8IAAwDAAAA.Thedeadangel:BAAALgADCgEJAQAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgkJDwAAAA==.Thiñgtwo:BAAALgAECgYJCAAAAA==.Thomss:BAAALgAFFAIJAwAAAA==.Throhk:BAAALgAECgEJAQAAAA==.Thuliaga:BAAALgAECgkJCwAAAA==.Thörskin:BAAALgADCgUJAQAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJEQABLgAECgkJHQAOANgTAA==.Tikdab:BAAALgAECgYJCQAAAA==.Tinneas:BAAALgADCgEJAgAAAA==.Tished:BAAALgAECgEJAQAAAA==.Titlepush:BAAALgAECgYJBgAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgAECgIJAwAAAA==.Tomás:BAABLgAECn89AAMdAAkJJBKJKAAcAgAdAAkJJBKJKAAcAgAiAAkJFxfeCABFAQAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8iAAIEAAgJPxuEDAC1AQAEAAgJPxuEDAC1AQAuAAQKfzIAAgQACQnCIRUDADEDAAQACQnCIRUDADEDAAAA.Toordn:BAAALgAECgQJBwAAAA==.Torstai:BAABLgAECn8bAAInAAkJTQqiEwA0AQAnAAkJTQqiEwA0AQAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAABLgAECn8aAAMXAAkJ0B5uCQCHAgAXAAkJvh1uCQCHAgAWAAQJ1hzaQQBRAQAAAA==.',
Ts='Tserendolgor:BAABLgAECn86AAQZAAgJdRyGEAAfAgAZAAgJCRyGEAAfAgALAAYJ9hz1SQCoAQAVAAUJ/hfcIACWAAAAAA==.',
Tu='Tunz:BAAALgAECgEJAgAAAA==.Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAiAFcWAA==.Twinsha:BAABLgAECn8dAAMiAAgJVxYyLQCPAQAiAAgJVxYyLQCPAQAdAAcJJwS1WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAiAFcWAA==.',
Ty='Tyinregard:BAAALgADCgIJAgAAAA==.Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrannis:BAAALgAECgIJAgAAAA==.Tyrasong:BAAALgAECgMJBgAAAA==.Tyresious:BAABLgAECn8wAAIUAAkJoSNaCQAdAwAUAAkJoSNaCQAdAwAAAA==.',
['Tà']='Tàric:BAAALgAECgQJCAAAAA==.',
Un='Unauma:BAACLgAFFH8NAAIHAAQJwgjTSgCQAAAHAAQJwgjTSgCQAAAuAAQKfzEAAwcACQknHHIWAJQCAAcACQknHHIWAJQCAB4ABwl1IY8KADwCAAEuAAUUBgkKAB0AeRIA.Undeadpanda:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.Unholydk:BAABLgAECn8aAAILAAkJPRlILQASAgALAAkJPRlILQASAgAAAA==.',
Ut='Utherrex:BAAALgAECgcJBwABLgAECgkJJwAbANARAA==.',
Va='Vaa:BAAALgAECgcJCwAAAA==.Vahaghn:BAACLgAFFH8KAAIfAAMJWSGMGQAZAQAfAAMJWSGMGQAZAQAuAAQKfzAAAh8ACQk3IxcCAA4DAB8ACQk3IxcCAA4DAAAA.Valcerus:BAABLgAECn85AAIFAAgJCx3tBQBJAgAFAAgJCx3tBQBJAgAAAA==.Valedus:BAABLgAECn8/AAIUAAkJiCQRBwA2AwAUAAkJiCQRBwA2AwAAAA==.Valhallæ:BAAALgAECgMJAwAAAA==.Validrela:BAAALgAECgUJBwAAAA==.Vampirism:BAAALgAECgUJBwABLgAECggJHwAKAEYeAA==.Vaskie:BAEALgAFFAIJAgABLgAFFAMJCAARADsYAA==.',
Ve='Veelete:BAAALgADCgkJEwABLgAECggJKQATABQeAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECgkJOgAJAFAkAA==.Vespra:BAABLgAECn9EAAIdAAkJRyDBCQAYAwAdAAkJRyDBCQAYAwAAAA==.',
Vh='Vhas:BAABLgAECn8UAAMHAAkJ1QntTgBTAQAHAAkJ1QntTgBTAQAeAAMJbARdGQBSAAAAAA==.Vhem:BAAALgAECgkJBwAAAA==.',
Vi='Vickie:BAAALgAECgMJAwAAAA==.Viix:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Visage:BAAALgADCgQJBAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8yAAIIAAkJEwjgHgAdAQAIAAkJEwjgHgAdAQAAAA==.Voldamar:BAAALgAECgcJEwAAAA==.Voltashi:BAABLgAECn81AAQlAAkJPBZMEgAjAgAlAAkJPBZMEgAjAgAaAAQJSBHWVgCzAAAKAAQJygnDoQBWAAAAAA==.Volthreal:BAAALgADCgQJAwAAAA==.Voltuk:BAACLgAFFH8GAAISAAMJOiDNCgAMAQASAAMJOiDNCgAMAQAuAAQKfycABBIACQlfGLwMAB4CABIACQmgFrwMAB4CABEABQngFk9MABUBAB8ABAkaE1ZFALQAAAAA.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAFFAQJCAAGANQSAA==.',
Wa='Wagyuboi:BAAALgAECgcJDwAAAA==.Wallypaly:BAABLgAECn8nAAMUAAgJDhbyjwBSAQAUAAcJVxfyjwBSAQAIAAUJ6RaCIwD5AAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn9WAAMTAAkJVCE/BgApAwATAAkJVCE/BgApAwAUAAQJ9wpDLgCeAAAAAA==.Warwarb:BAAALgAECgYJBgABLgAECgkJNwAbAA8cAA==.Waterliliy:BAABLgAECn8dAAIOAAkJ2BOtMgBQAQAOAAkJ2BOtMgBQAQAAAA==.Wayhn:BAAALgADCgUJBQAAAA==.',
We='Weaveraz:BAAALgAECgIJAgAAAA==.',
Wh='Whatcrap:BAAALgAECgQJBAAAAA==.Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8wAAMGAAkJ0RooIwBXAgAGAAkJ0RooIwBXAgAWAAYJkQtBIACuAAAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECggJOQAFAAsdAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgAECgEJAwABLgAFFAQJCwAbAC4VAA==.Xelvandar:BAAALgAECgEJAQABLgAECggJFgAIANEQAA==.Xenhaseo:BAABLgAECn8rAAIQAAkJXxh/FQAuAgAQAAkJXxh/FQAuAgAAAA==.',
Xh='Xhuri:BAAALgAECgIJBwAAAA==.',
Xi='Xilla:BAAALgAECgcJCAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAABLgAECn8vAAIHAAkJPB1KAwAsAgAHAAkJPB1KAwAsAgAAAA==.',
Yo='Yorllik:BAAALgAECgUJDAAAAA==.Yougotwreckd:BAABLgAFFH8JAAIUAAQJiwbMXAD2AAAUAAQJiwbMXAD2AAAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8bAAILAAgJQBYxawBOAQALAAgJQBYxawBOAQAAAA==.',
Yu='Yuzuha:BAAALgADCgkJAwAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIQAAkJJCH/CwCaAgAQAAkJJCH/CwCaAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJEAABAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zapura:BAAALgADCgYJBgAAAA==.Zaraelil:BAAALgADCgMJAwAAAA==.Zarkhan:BAABLgAECn8kAAMCAAcJuxUnDAB4AQACAAcJuxUnDAB4AQADAAEJmhOROAA6AAABLgAECgcJDQABAAAAAA==.Zarulyn:BAAALgAECgkJEgAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAABLgAECn8fAAMjAAkJ1hIxBgDuAQAjAAkJ1hIxBgDuAQAQAAcJwgyyOgBBAQAAAA==.Zendragon:BAAALgADCgQJBAABLgAFFAMJBgASADogAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8pAAMdAAkJnxFRPQC5AQAdAAkJnxFRPQC5AQApAAgJrAY2GwAnAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgYJCgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn88AAIGAAkJWA7XUACwAQAGAAkJWA7XUACwAQAAAA==.',
['Äc']='Äcid:BAABLgAECn8sAAIdAAkJ1xslHQBkAgAdAAkJ1xslHQBkAgAAAA==.',
['Åp']='Åpollo:BAABLgAFFH8SAAIKAAcJOBFgEQBvAQAKAAcJOBFgEQBvAQAAAA==.',
['Èa']='Èastçoast:BAAALgADCgcJGQAAAA==.',
['Êl']='Êlydala:BAAALgAECgYJBwAAAA==.',
['Ðe']='Ðeja:BAAALgAECgMJBgABLgAECggJFgAIANEQAA==.',
['Ðè']='Ðèath:BAAALgAECgEJAgAAAA==.',
['Ðð']='Ððå:BAAALgADCgEJAQAAAA==.',
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
