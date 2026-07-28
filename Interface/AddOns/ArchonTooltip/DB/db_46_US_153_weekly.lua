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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Feral','Priest-Shadow','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Warrior-Protection','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Druid-Guardian','Warrior-Arms','Priest-Discipline','Rogue-Assassination','Shaman-Elemental','Monk-Mistweaver','Evoker-Devastation','Rogue-Subtlety','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aakkulay:BAAALgAECgQJBgABLgAECgcJJAABALsVAA==.',
Ab='Absofsteels:BAABLgAECn9CAAQBAAkJ1B1uBABGAgABAAkJhhtuBABGAgACAAMJWh73BAAMAQADAAEJ2gsdZAAhAAAAAA==.',
Ac='Acaric:BAABLgAECn9FAAIEAAkJhwxmFwAIAQAEAAkJhwxmFwAIAQAAAA==.Ache:BAAALgAFFAMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAACLgAFFH8SAAIFAAUJcQ1mIgAUAQAFAAUJcQ1mIgAUAQAuAAQKfyUAAgUACQlEFoMiADYCAAUACQlEFoMiADYCAAAA.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgAECgYJBgAAAA==.Aireola:BAAALgAECgEJAwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAFFAMJBwAGAH8KAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgIJAgABLgAECgkJQAAHANAhAA==.Alchemist:BAAALgADCgkJKgAAAA==.Alidor:BAACLgAFFH8FAAMDAAIJxgWrJAA6AAADAAIJxgWrJAA6AAABAAEJGgNyqQAuAAAuAAQKfyAAAwMACAkoCokzAM0AAAEABgnTBI7PAOkAAAMABwkPCokzAM0AAAAA.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAABLgAECn8UAAIBAAgJZAxCFQDyAAABAAgJZAxCFQDyAAAAAA==.Altaressa:BAAALgAECgQJBAAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amberyaheard:BAAALgADCgYJEAAAAA==.Amira:BAACLgAFFH8aAAIIAAUJbCQaAgCUAQAIAAUJbCQaAgCUAQAuAAQKfyUAAggACAmsJWoCAEUDAAgACAmsJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amorleroin:BAAALgAECgQJBAAAAA==.Amormage:BAABLgAECn8bAAIEAAgJPwvHEgAwAQAEAAgJPwvHEgAwAQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.Amuri:BAAALgAECgYJBgAAAA==.',
An='Angmar:BAAALgAECgQJAwAAAA==.Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8dAAIJAAkJRhBtSwCkAQAJAAkJRhBtSwCkAQAAAA==.',
Ap='Aphytex:BAAALgADCgEJAQAAAA==.Apothneskin:BAAALgADCgMJAwAAAA==.',
Ar='Arauial:BAABLgAECn8qAAIIAAkJeyFrCADkAgAIAAkJeyFrCADkAgAAAA==.Archdrake:BAAALgAECgUJBwAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8OAAIFAAYJkAupVAD/AAAFAAYJkAupVAD/AAAuAAQKfysAAgUACQlzGbYgAEECAAUACQlzGbYgAEECAAAA.Arizann:BAABLgAECn9HAAQGAAkJfB9LDgDmAgAGAAkJfB9LDgDmAgAKAAcJ7RGvLwBgAQALAAEJyAsQVgAtAAAAAA==.Arobotpr:BAABLgAECn8/AAIMAAkJdRlOEQBMAgAMAAkJdRlOEQBMAgAAAA==.Arrenn:BAAALgAECgUJBQAAAA==.Arthanìa:BAAALgAECgYJBgAAAA==.Artpandalay:BAAALgAECgQJBQABLgAECgYJCAANAAAAAA==.',
As='Asima:BAAALgAECgQJCAAAAA==.Assoul:BAAALgAECgIJAgAAAA==.Astaren:BAABLgAECn84AAMOAAcJRCN7AADJAgAOAAcJRCN7AADJAgAPAAUJ5xHXCADWAAAAAA==.Asuran:BAACLgAFFH8KAAIQAAQJtBqeGwBCAQAQAAQJtBqeGwBCAQAuAAQKfzwAAxAACQn2JVAIANsCABAACAlcJVAIANsCABEACQkKI0AGAKoCAAAA.',
At='Atem:BAABLgAECn8UAAIRAAUJrQutOACTAAARAAUJrQutOACTAAAAAA==.Atilla:BAAALgAECgUJBQABLgAFFAQJDQAFAEMUAA==.',
Au='Aulinn:BAAALgAECgQJBQAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Ax='Axefu:BAAALgADCgQJBAAAAA==.Axefury:BAAALgADCgYJDwAAAA==.Axegrunion:BAAALgADCgUJBQAAAA==.',
Az='Azaris:BAABLgAECn8+AAIMAAkJzRzvDQB2AgAMAAkJzRzvDQB2AgAAAA==.',
Ba='Babykraze:BAAALgAECgEJAQAAAA==.Baeleaf:BAAALgAECgQJDAAAAA==.Baelrog:BAABLgAECn8ZAAMSAAkJsQ7PCAAOAQASAAkJsQ7PCAAOAQATAAIJCQPmxwEfAAAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMJAAkJBBLrRwDUAQAJAAkJBBLrRwDUAQAUAAIJQgq8NgAsAAAAAA==.Baranina:BAACLgAFFH8TAAMFAAcJWx3HBwAnAQAFAAMJ2iHHBwAnAQAVAAUJERkJFQAcAQAuAAQKfysABBUACAnTI4IOAM4CABUACAkgIoIOAM4CAAUABQmOHws2ANYBABYABgnGINcmAGcBAAAA.Barricaded:BAAALgAECgkJEgAAAA==.Bashbash:BAAALgAECgMJAwAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQANAAAAAA==.Bastrd:BAAALgAECgYJCgAAAA==.Battlecat:BAAALgADCgEJAQABLgAFFAMJBgARADogAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgAECgUJEgAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Bearypie:BAAALgAECgkJBQAAAA==.Beastums:BAABLgAECn8/AAIWAAkJxRnNDQBKAgAWAAkJxRnNDQBKAgAAAA==.Bence:BAAALgAECgYJBgAAAA==.Benji:BAABLgAECn8aAAMEAAkJ8xcvVQDdAQAEAAkJ8xcvVQDdAQAXAAEJeQYuIgAhAAAAAA==.',
Bi='Biggiecat:BAAALgADCgYJBgABLgAECgcJOAAEAI0eAA==.Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blacken:BAAALgAECgEJAgAAAA==.Blazinitup:BAAALgADCgQJCQAAAA==.Blimey:BAAALgAECggJBgAAAA==.Blindaf:BAABLgAECn8wAAMYAAkJXRWNFgDUAQAYAAkJXRWNFgDUAQAJAAYJKAVRHwCAAAAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIZAAcJqhGJPQAKAQAZAAcJqhGJPQAKAQAAAA==.Blite:BAAALgADCgkJMQAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8qAAMSAAkJ7RJuBgBYAQASAAYJEhFuBgBYAQATAAkJ3wUQpgAuAQAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8cAAMGAAYJuw3fDABPAQAGAAYJuw3fDABPAQAKAAMJtwFOQwBpAAAuAAQKfy8AAwYACQmfHi4BAPgCAAYACQmfHi4BAPgCAAoAAQl/ESaKADcAAAAA.Blueeyearch:BAABLgAECn8VAAMVAAcJxx2cFwD2AAAFAAYJESLQTgB8AQAVAAUJoRKcFwD2AAAAAA==.Bluetish:BAAALgAECgQJDgAAAA==.',
Bo='Bo:BAAALgAECggJCAAAAA==.Bobb:BAAALgAFFAIJAgAAAA==.Bolgan:BAAALgAECgMJCAABLgAECggJLwAZAPQdAA==.Bonedecay:BAAALgAECgEJCQAAAA==.Bonerina:BAAALgAECggJEgAAAA==.Boomadk:BAACLgAFFH8TAAMBAAQJKRi4ZgArAQABAAQJgBe4ZgArAQACAAIJSRP6HACbAAAuAAQKfykAAwEACQkPIkUfAMYCAAEACQm1IUUfAMYCAAIACAlKHdgCAHsCAAAA.Boomapriest:BAAALgAECgcJCwAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAABLgAECn8XAAIJAAkJDhfaLAAUAgAJAAkJDhfaLAAUAgAAAA==.Booshly:BAAALgAECgUJBQAAAA==.Boosta:BAAALgAECgUJBQAAAA==.Bootstrapbil:BAAALgAECgUJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCQAAAA==.Brasserz:BAABLgAECn8wAAIWAAkJoBiqDABZAgAWAAkJoBiqDABZAgAAAA==.Breezybone:BAAALgAECgUJBQAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAABLgAECn8nAAISAAcJHh4UAwD0AQASAAcJHh4UAwD0AQAAAA==.Briochebun:BAABLgAECn8fAAITAAkJSBzkIACnAgATAAkJSBzkIACnAgAAAA==.Briollias:BAAALgAECgEJAQAAAA==.Brody:BAAALgAECgEJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgMJAwABLgAECgkJLwAGADwdAA==.Bumpycassock:BAAALgADCgEJAQAAAA==.Bustin:BAABLgAECn8aAAITAAgJzh6yMQA5AgATAAgJzh6yMQA5AgAAAA==.',
Bw='Bwangifer:BAABLgAECn8/AAIUAAkJKxpnBQBRAgAUAAkJKxpnBQBRAgAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgAECgEJAQABLgAECgkJMQAWAP8gAA==.Caitriona:BAAALgAECgEJAQABLgAECgkJIAAaAJ0LAA==.Calabera:BAAALgADCgEJAQAAAA==.Calfrunsam:BAAALgAECgEJAQAAAA==.Cannala:BAAALgADCgkJMAAAAA==.Cargae:BAAALgADCggJIgAAAA==.Casstrait:BAAALgAECgMJBAAAAA==.',
Cc='Ccelionn:BAAALgAECgEJAQAAAA==.',
Ce='Celathel:BAABLgAECn8ZAAMUAAkJCBU4AwAfAQAUAAYJYhY4AwAfAQAJAAYJtxFHhAAXAQAAAA==.Cellysia:BAABLgAECn9BAAMIAAkJpAoOKwBwAQAIAAkJpAoOKwBwAQAMAAcJrwJRXAClAAAAAA==.Celsìus:BAABLgAECn8XAAIEAAYJbhOg1QBEAQAEAAYJbhOg1QBEAQAAAA==.Ceramyth:BAABLgAECn8bAAIHAAYJkB5UAwCGAQAHAAYJkB5UAwCGAQAAAA==.Ceres:BAABLgAECn8/AAIbAAkJdR0fAgClAgAbAAkJdR0fAgClAgAAAA==.Cesara:BAACLgAFFH8JAAMMAAMJFhSRJADSAAAMAAMJFhSRJADSAAAIAAMJJBC+IwCdAAAuAAQKfzwAAwwACQlHI48EABADAAwACQlHI48EABADAAgAAglhBCR/ADMAAAAA.',
Ch='Chaahck:BAAALgAECgMJAwAAAA==.Chal:BAAALgAECgYJCAAAAA==.Chaplin:BAAALgAECgIJAgABLgAECgkJPQAcACQSAA==.Chbribs:BAABLgAECn8aAAIdAAkJWBRhHQBiAQAdAAkJWBRhHQBiAQAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgAECgQJBQAAAA==.',
Ci='Cinderella:BAABLgAECn82AAIEAAkJLSRBDQAPAwAEAAkJLSRBDQAPAwAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Coldsteel:BAAALgADCgQJBAAAAA==.Columbina:BAACLgAFFH8pAAIJAAcJmhb7JgCQAQAJAAcJmhb7JgCQAQAuAAQKfxwAAgkACAkKG7dEAOEBAAkACAkKG7dEAOEBAAAA.Comma:BAABLgAECn8UAAIRAAcJFxKwHABjAQARAAcJFxKwHABjAQAAAA==.Cooperhowerd:BAAALgADCgkJMQAAAA==.Corein:BAAALgAECgYJCQAAAA==.Corn:BAABLgAECn8fAAITAAgJiRfSegB5AQATAAgJiRfSegB5AQAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAACLgAFFH8KAAIeAAQJvhVPDQDZAAAeAAQJvhVPDQDZAAAuAAQKf0IAAx4ACQlQI1ECACkDAB4ACQlQI1ECACkDABEAAgk1EFFHAFYAAAAA.Crackundead:BAACLgAFFH8PAAIBAAYJGxH6HQBmAQABAAYJGxH6HQBmAQAuAAQKfxYAAgEACQmpFd0GANUBAAEACQmpFd0GANUBAAAA.Crapdragon:BAAALgAECggJCwAAAA==.Cravens:BAAALgAECgYJCwAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8/AAIGAAkJWx8mCQAnAwAGAAkJWx8mCQAnAwAAAA==.Cyrinx:BAAALgAECgkJEQAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAABLgAECn8hAAQIAAYJCSDbAwDPAQAIAAYJCSDbAwDPAQAfAAIJbgw4IAA3AAAMAAEJ5AE4nAAXAAAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgAECgQJCQAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dagravytrain:BAAALgADCgMJAwAAAA==.Dajango:BAAALgAECgYJDQAAAA==.Damerot:BAACLgAFFH8IAAIQAAMJWBDVNgDXAAAQAAMJWBDVNgDXAAAuAAQKfxYAAxAABQk1Ey1CADwBABAABQk1Ey1CADwBABEAAQmeAgtbACEAAAAA.Dandity:BAAALgAECgcJDQAAAA==.Dangerous:BAABLgAECn8bAAIgAAcJdBdBAQCOAQAgAAcJdBdBAQCOAQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAACLgAFFH8GAAIcAAMJ0A69LACQAAAcAAMJ0A69LACQAAAuAAQKfxsAAxwABgkvIVcFAAACABwABgkvIVcFAAACACEAAQlDAVqXABkAAAAA.Darnel:BAAALgADCgQJBAAAAA==.Dawnsingers:BAAALgADCgIJAgAAAA==.',
De='Deadbeard:BAACLgAFFH8MAAIBAAQJwB6sQAB1AQABAAQJwB6sQAB1AQAuAAQKf0QAAgEACQl8Jj4BAIoDAAEACQl8Jj4BAIoDAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAFFAEJAQAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Debased:BAAALgAECgYJCwAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAABLgAECn8WAAMiAAgJQxB4PQB5AQAiAAgJQxB4PQB5AQAZAAUJfwtWWQCsAAAAAA==.Delphina:BAAALgAECgMJBgAAAA==.Demini:BAABLgAECn8dAAIYAAgJ0gx2CgDXAAAYAAgJ0gx2CgDXAAAAAA==.Demisê:BAACLgAFFH8KAAMDAAMJCAzELQCQAAABAAMJCwd7twC5AAADAAMJCgvELQCQAAAuAAQKfyIAAwEACQn2F9gyADMCAAEACQkWF9gyADMCAAMABQmGEdk3ALUAAAAA.Demonessa:BAAALgAECgcJEQAAAA==.Demonslyer:BAABLgAECn8lAAMJAAkJoRrYBADIAQAJAAkJAhjYBADIAQAYAAIJyRYqDwCNAAAAAA==.Derbygirl:BAAALgAECgQJCQAAAA==.Derius:BAAALgAECgUJBQABLgAFFAQJDQAFAEMUAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8jAAMPAAgJkhR4JAC6AQAPAAgJkhR4JAC6AQAjAAYJtQz0HgA3AQAAAA==.Desso:BAABLgAECn9AAAIZAAkJfxnWAQApAgAZAAkJfxnWAQApAgAAAA==.Devilskin:BAABLgAECn8XAAIhAAgJvQhPEACvAAAhAAgJvQhPEACvAAAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAABLgAECgcJJgAFAEseAA==.Dillinger:BAABLgAECn86AAILAAkJRhhSCQAwAgALAAkJRhhSCQAwAgAAAA==.Dingodgaf:BAACLgAFFH8LAAITAAIJZQPZVABkAAATAAIJZQPZVABkAAAuAAQKfzcAAhMACAl1C6wWAAoBABMACAl1C6wWAAoBAAAA.',
Do='Dodo:BAAALgAECgkJBwAAAA==.Dokholliday:BAAALgAECgEJAQAAAA==.Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8rAAIEAAYJSBfNiABlAQAEAAYJSBfNiABlAQAAAA==.',
Dr='Draemora:BAAALgAECgEJAQAAAA==.Dragonmynutz:BAAALgAECgYJBwAAAA==.Dragonshammy:BAAALgAECgYJDAAAAA==.Draknarok:BAABLgAECn8gAAIBAAgJRRqbPwAEAgABAAgJRRqbPwAEAgAAAA==.Dranius:BAACLgAFFH8NAAIEAAQJGQnlbQAHAQAEAAQJGQnlbQAHAQAuAAQKfxgAAgQACAm5EySJAMABAAQACAm5EySJAMABAAAA.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAABLgAECn8cAAILAAYJuQzXJADjAAALAAYJuQzXJADjAAAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAACLgAFFH8LAAMaAAQJLhXoSQAzAQAaAAQJLhXoSQAzAQAbAAEJXgFuLQAoAAAuAAQKfykAAhoACQmTGhUmAEUCABoACQmTGhUmAEUCAAAA.Driztette:BAABLgAECn81AAIcAAkJxSAkAgDAAgAcAAkJxSAkAgDAAgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Druidbearpig:BAAALgAECgYJDQABLgAECgkJJwAaANARAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgABLgAFFAIJBQAkAD4VAA==.Drylustine:BAAALgADCgMJAwAAAA==.Drystine:BAABLgAECn8vAAIYAAkJLR68CwBrAgAYAAkJLR68CwBrAgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.Dugtig:BAAALgAECgcJCgAAAA==.',
['Dí']='Dín:BAAALgAECgIJAgAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgkJKwAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Eg='Eggs:BAAALgAECgEJAgAAAA==.',
Eh='Ehisdv:BAAALgAECgMJAwAAAA==.',
Ei='Eillaura:BAACLgAFFH8KAAIIAAMJEiABFgAQAQAIAAMJEiABFgAQAQAuAAQKfyUAAggACQksG54LAK0CAAgACQksG54LAK0CAAAA.',
El='Elemag:BAAALgAECgEJAgAAAA==.Eleredra:BAAALgAECgMJAwABLgAECgkJHQAMANgTAA==.Elipsis:BAACLgAFFH8MAAIIAAQJjCB8CQAXAQAIAAQJjCB8CQAXAQAuAAQKfx0AAggACQmpE1ssAJUBAAgACQmpE1ssAJUBAAAA.Ellessae:BAAALgAECgEJAQAAAA==.Ellyn:BAAALgAECgYJBgAAAA==.Elm:BAABLgAECn9DAAQGAAkJVBTgMwDNAQAGAAkJVBTgMwDNAQAKAAkJ1xTKBQBqAQAdAAEJ5BNeLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAACLgAFFH8FAAIFAAMJ7go6dQCyAAAFAAMJ7go6dQCyAAAuAAQKfxsAAgUACQlvGQUvAPUBAAUACQlvGQUvAPUBAAAA.Elycia:BAAALgAECggJCwABLgAFFAMJBQAFAO4KAA==.Elyenora:BAAALgAECgQJBAABLgAFFAMJBQAFAO4KAA==.Elyssaelyend:BAAALgAECgYJDAABLgAECgkJLAAGAJ8ZAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emberion:BAAALgAECgUJBgAAAA==.Emmental:BAABLgAECn8pAAIhAAgJ3RBwCgADAQAhAAgJ3RBwCgADAQAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAABLgAECn8YAAMIAAcJdRZJIADAAQAIAAcJdRZJIADAAQAMAAEJdAYlkwAnAAAAAA==.Enricco:BAABLgAECn8pAAIhAAYJZgO6FQB2AAAhAAYJZgO6FQB2AAAAAA==.',
Er='Eramortis:BAAALgADCgYJBgAAAA==.Ereko:BAABLgAECn8lAAIFAAkJOBAURgDPAQAFAAkJOBAURgDPAQAAAA==.Erythorbic:BAABLgAECn8hAAMaAAgJ8xzrKQAzAgAaAAcJfRzrKQAzAgAbAAMJQyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCwAAAA==.',
Ev='Evictor:BAAALgAECgYJEAABLgAECgkJHwAZALMZAA==.',
Ex='Exileelfsam:BAABLgAECn8vAAIWAAkJVwtrHAC5AQAWAAkJVwtrHAC5AQAAAA==.',
Fa='Fallenrose:BAAALgAECgEJAQAAAA==.Fallensk:BAAALgADCgIJAgAAAA==.Falord:BAAALgADCgUJBQAAAA==.Faranth:BAAALgAECgIJAwAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgAECgQJBgAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8nAAMfAAcJexU8FgDGAQAfAAcJexU8FgDGAQAMAAEJ1QGdQQAyAAAuAAQKfyoAAx8ACAlEHycIAL0CAB8ACAlEHycIAL0CAAgABgkhCDNKABABAAAA.',
Fe='Feer:BAABLgAECn8UAAIFAAcJqhDsEABKAQAFAAcJqhDsEABKAQAAAA==.Feldron:BAABLgAECn8cAAMkAAkJZh3ACgDmAgAkAAgJGR7ACgDmAgAgAAEJgxjzHQA9AAAAAA==.Felshatter:BAABLgAECn87AAIJAAkJUBLzBADDAQAJAAkJUBLzBADDAQAAAA==.Feltigress:BAABLgAECn8wAAILAAkJnCKZAgD7AgALAAkJnCKZAgD7AgAAAA==.Fendag:BAABLgAECn8XAAICAAUJ6wO7EABFAAACAAUJ6wO7EABFAAAAAA==.',
Ff='Ffugher:BAAALgAECgkJEgAAAA==.Ffugin:BAAALgADCgYJCQAAAA==.Ffugit:BAAALgAECgYJBgAAAA==.Ffuglee:BAAALgAECgcJCgAAAA==.Ffugme:BAABLgAECn8vAAIHAAkJXxJHEQCwAQAHAAkJXxJHEQCwAQAAAA==.Ffugnutz:BAAALgAECgYJCwAAAA==.Ffugoff:BAAALgAECgcJCQAAAA==.Ffugstain:BAAALgADCgkJDgAAAA==.Ffugtard:BAABLgAECn8XAAIFAAkJWgsqgwA4AQAFAAkJWgsqgwA4AQAAAA==.Ffugtastic:BAAALgADCgEJAQAAAA==.Ffugtoy:BAAALgAECgYJBgAAAA==.Ffugyou:BAAALgAECgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAABLgAECgYJBwANAAAAAA==.Finnian:BAABLgAECn8zAAISAAkJdh6xCAD/AgASAAkJdh6xCAD/AgAAAA==.Fio:BAACLgAFFH8OAAIiAAQJdSIZHgB/AQAiAAQJdSIZHgB/AQAuAAQKfyQAAyIACAn3JLMCAFoDACIACAn3JLMCAFoDABkAAQlJG0JwAFEAAAAA.Firiona:BAABLgAECn8iAAMfAAYJSBg8JACtAQAfAAYJSBg8JACtAQAMAAQJrB3JBgBSAQAAAA==.Fistfuloftok:BAAALgAECgIJAgABLgAECgkJLAALAB4iAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIlAAgJzRc/JACKAQAlAAgJzRc/JACKAQAAAA==.Flinn:BAABLgAECn8dAAIdAAkJBh6yBgCQAgAdAAkJBh6yBgCQAgAAAA==.Flowers:BAABLgAECn8zAAMJAAkJgiBXCwDtAgAJAAkJgiBXCwDtAgAYAAQJVRwLNQDqAAAAAA==.Fläva:BAABLgAECn8UAAMTAAYJVxbAsgAbAQATAAYJdxXAsgAbAQAHAAEJqhhtEgBHAAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgYJBgAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Friendlyhoss:BAAALgADCgEJAQAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8wAAIEAAkJBBqZOAA2AgAEAAkJBBqZOAA2AgAAAA==.',
Fu='Furiousdemon:BAAALgADCgEJAQAAAA==.Furysbubble:BAAALgAECgEJAQAAAA==.Furyswarm:BAAALgAECgkJAgAAAA==.',
['Fá']='Fállen:BAAALgAECgEJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwANAAAAAA==.',
Ga='Gadrîel:BAAALgAECgUJAQAAAA==.Gafocalypse:BAABLgAECn8gAAIDAAkJwhVNFQDCAQADAAkJwhVNFQDCAQAAAA==.Gaius:BAAALgAECgYJDAABLgAECgcJJAABALsVAA==.Garddidit:BAAALgADCgUJBQABLgAECggJJAAUAG8eAA==.',
Ge='Gernaj:BAAALgAECgEJAQAAAA==.Getvoked:BAAALgAECgUJBQAAAA==.',
Gh='Ghostffudge:BAAALgAECgkJCQAAAA==.',
Gi='Ginarrah:BAAALgADCgcJCAAAAA==.Ginsan:BAAALgADCgIJAgAAAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDQAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.Goovs:BAAALgAECgcJCQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgkJNAAAAA==.Grep:BAAALgAECgQJCQAAAA==.Greygor:BAABLgAECn8XAAIQAAgJOwmhCgAKAQAQAAgJOwmhCgAKAQAAAA==.Grotok:BAABLgAECn8bAAMBAAkJARS9CgB0AQABAAkJDxG9CgB0AQACAAIJAx2wDgBUAAAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgkJEQAAAA==.Gurgatron:BAAALgAECggJDgABLgAFFAMJBgARADogAA==.Guulen:BAAALgAECgMJAwAAAA==.',
Gy='Gyozitgar:BAAALgAECgEJAwAAAA==.',
Ha='Halaragdan:BAAALgADCgEJAQAAAA==.Halraku:BAAALgAECgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECggJDwAAAA==.Halygosa:BAAALgAECgEJAQAAAA==.Hamoro:BAAALgADCgYJBgAAAA==.Hariffug:BAAALgAECgUJBgAAAA==.Hasklaufien:BAAALgAECgIJBgAAAA==.',
He='Healinside:BAAALgAECgYJBgAAAA==.Hemmingway:BAAALgADCggJDAAAAA==.Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hiest:BAAALgAECgYJEAAAAA==.Hinderberg:BAAALgAECggJCAAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAABLgAECn8XAAMHAAgJLRlsBgD6AAAHAAgJmBhsBgD6AAATAAIJWA2gQwBSAAAAAA==.',
Hu='Hugulin:BAABLgAECn8iAAIFAAkJ+gWYjQAkAQAFAAkJ+gWYjQAkAQAAAA==.Huntârdandy:BAAALgADCggJEAAAAA==.',
['Hå']='Håtsuharu:BAAALgADCgkJCQAAAA==.',
['Hé']='Héllboy:BAAALgAECgEJAQAAAA==.',
Ic='Iceblocklulz:BAAALgAECgIJAQAAAA==.Icedsoul:BAABLgAECn8jAAIEAAkJ6QiOngA9AQAEAAkJ6QiOngA9AQAAAA==.Icee:BAAALgADCgcJCgAAAA==.Iceflame:BAAALgAECgMJAwABLgAECgkJLwAGADwdAA==.',
Ig='Iggey:BAABLgAECn8zAAIeAAkJjBz/BwB1AgAeAAkJjBz/BwB1AgAAAA==.',
Ik='Ikigai:BAAALgAECgQJBAAAAA==.Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn89AAIJAAkJ4xZxBADeAQAJAAkJ4xZxBADeAQAAAA==.Illadus:BAABLgAECn8fAAIJAAkJcQh/cQA/AQAJAAkJcQh/cQA/AQAAAA==.Illed:BAAALgADCgcJBwAAAA==.',
In='Indra:BAAALgAECggJEQAAAA==.Intoxicated:BAABLgAECn8jAAIZAAkJAwyRNAAxAQAZAAkJAwyRNAAxAQAAAA==.',
Io='Ione:BAAALgADCgcJBwAAAA==.',
Ir='Iranna:BAACLgAFFH8lAAQgAAgJViJ9AQDPAQAgAAUJqSB9AQDPAQAmAAYJhhsOAwB8AQAkAAQJoiC2DgATAQAuAAQKfzUABCAACAmQJRYDAI4CACYACAlwI0YBAN8CACAABwn2IBYDAI4CACQABwmKIAgVAPkBAAAA.Irondihh:BAAALgAECgMJAwABLgAECgcJJgAFAEseAA==.',
It='Itsredbelow:BAAALgAECgYJCgAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAFFAMJBwAGAH8KAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgkJKwABAG0gAA==.Janaki:BAABLgAECn8eAAMGAAgJsxkwHwBNAgAGAAgJsxkwHwBNAgAKAAQJghbuUQDGAAAAAA==.',
Je='Jehoichin:BAAALgAECgQJBAAAAA==.Jesmah:BAAALgAECgYJBgAAAA==.Jestêr:BAABLgAFFH8SAAMgAAUJyh3+AACCAQAgAAUJyh3+AACCAQAkAAEJbgfgPABIAAABLgAFFAcJJwAfAHsVAA==.',
Ji='Jibbtotem:BAAALgAECgQJBAABLgAECggJEgANAAAAAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn9RAAITAAkJJhfsNwAiAgATAAkJJhfsNwAiAgAAAA==.',
Ju='Juicie:BAAALgAECgYJDwAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQAQABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQAQABkeAA==.',
['Jè']='Jèstèr:BAABLgAFFH8NAAIcAAUJzxOeJQBUAQAcAAUJzxOeJQBUAQABLgAFFAcJJwAfAHsVAA==.',
Ka='Kainoa:BAAALgADCgMJAwAAAA==.Kalea:BAAALgAECgIJBwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECgkJGAACAIwbAA==.Kalietha:BAAALgAECgEJAQAAAA==.Kalila:BAAALgAFFAEJAQAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kassandrah:BAAALgADCgkJDQAAAA==.Kat:BAABLgAECn8YAAMlAAkJZhS7GgDPAQAlAAcJNBq7GgDPAQAiAAcJZgarTwCUAAAAAA==.Katsuko:BAABLgAECn8zAAIDAAkJyRhlEAAFAgADAAkJyRhlEAAFAgAAAA==.Kattnirra:BAABLgAECn8uAAIFAAkJSREAPADwAQAFAAkJSREAPADwAQAAAA==.Katze:BAABLgAECn9PAAIFAAkJ8xgQIwBXAgAFAAkJ8xgQIwBXAgAAAA==.Kauwela:BAAALgADCgUJBQAAAA==.Kaylé:BAAALgAECgYJDQAAAA==.',
Ke='Keabdeo:BAAALgADCgcJBwAAAA==.Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgcJBwAAAA==.Keepper:BAABLgAECn8oAAIaAAkJ8hCaVwCWAQAaAAkJ8hCaVwCWAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8WAAIIAAgJRRB5NAAzAQAIAAgJRRB5NAAzAQAAAA==.Ketheric:BAABLgAFFH8IAAMDAAMJCA62OgBLAAABAAMJBQmPbQBzAAADAAEJlBu2OgBLAAABLgAFFAUJEgAcAG0fAA==.',
Kh='Khrixtie:BAAALgADCgUJAQAAAA==.',
Ki='Killahaseo:BAAALgAECgkJDwABLgAECgkJKwAPAF8YAA==.Killmoedee:BAABLgAECn9AAAMHAAkJ0CGhAgADAwAHAAkJ0CGhAgADAwATAAEJrRrEZwFOAAAAAA==.Kittyclyzm:BAAALgAFFAEJAQABLgAFFAMJCQAMABYUAA==.Kitwryn:BAAALgADCgkJDQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCgABLgAECgYJBwANAAAAAA==.',
Kl='Klexios:BAABLgAECn84AAIRAAcJawY4CAC4AAARAAcJawY4CAC4AAAAAA==.',
Ko='Kodohoof:BAAALgAECgYJDwAAAA==.Koopa:BAAALgAECggJDQAAAA==.Korbandallas:BAABLgAECn8WAAMBAAgJ1giWFwDeAAABAAgJ1giWFwDeAAACAAEJzAfcFAAkAAAAAA==.Kozzmo:BAAALgAECgEJAQAAAA==.',
Kr='Kracious:BAAALgAECgUJBQAAAA==.Kratosaurion:BAAALgADCgMJAwAAAA==.Kraulhoof:BAAALgAECgEJAgABLgAECgYJBwANAAAAAA==.Krispy:BAABLgAECn8iAAIbAAkJUg8bDAB9AQAbAAkJUg8bDAB9AQAAAA==.Kruise:BAAALgAECgcJBwAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn8/AAIlAAkJwB/wBQDfAgAlAAkJwB/wBQDfAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
Ky='Kylenna:BAAALgAECgMJAwABLgAFFAMJBQAFAO4KAA==.',
['Kö']='Köz:BAAALgAECgYJEAAAAA==.',
La='Laetri:BAABLgAECn8kAAIJAAkJ2RRyRgCzAQAJAAkJ2RRyRgCzAQAAAA==.Lailiia:BAAALgAECgcJCgABLgAECgkJOgAIAFAkAA==.Lasttok:BAABLgAECn8sAAMLAAkJHiIoAwDnAgALAAkJvB8oAwDnAgAKAAgJvBpjIADFAQAAAA==.Laylene:BAAALgAECgcJEAAAAA==.Lazloo:BAABLgAECn8yAAMQAAkJcSWdAgBIAwAQAAkJbSWdAgBIAwAeAAcJOhwTFwCjAQAAAA==.Lazymidget:BAABLgAECn8eAAIVAAcJJh1VLQDFAQAVAAcJJh1VLQDFAQAAAA==.Lazytok:BAAALgAECgMJBgAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAABLgAECn8hAAMDAAcJ0xLlBABaAQADAAcJ0xLlBABaAQACAAEJBQvAFAAlAAABLgAECgkJPgAWAAoUAA==.Legindkiller:BAAALgADCgkJNAAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAkJCQADADAZAA==.',
Li='Lightace:BAABLgAECn8ZAAITAAcJSgdQ0gDwAAATAAcJSgdQ0gDwAAAAAA==.Lilgeezus:BAAALgADCgEJAQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAABLgAECn8cAAIWAAkJASFCBQDTAgAWAAkJASFCBQDTAgAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8fAAIaAAgJZQhWlAATAQAaAAgJZQhWlAATAQAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAABLgAECn8ZAAIjAAcJ9wTEEwDPAAAjAAcJ9wTEEwDPAAAAAA==.Lostdream:BAABLgAECn8eAAMJAAcJfAN61gCIAAAJAAYJLwN61gCIAAAYAAIJKwM2fQAjAAAAAA==.Loun:BAABLgAECn9FAAIlAAkJwBlUDgBUAgAlAAkJwBlUDgBUAgAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgAECgEJAgABLgAECggJHwAiAEYeAA==.Luteil:BAAALgADCgMJAwAAAA==.Luvlycruelty:BAABLgAECn8gAAIaAAkJnQukCABmAQAaAAkJnQukCABmAQAAAA==.',
Ly='Lyn:BAECLgAFFH8KAAIlAAQJkiTjDwCnAQAlAAQJkiTjDwCnAQAuAAQKf00AAiUACQmZJlQAAIYDACUACQmZJlQAAIYDAAAA.',
Ma='Mackenziiee:BAACLgAFFH8KAAIFAAMJfw88ZADdAAAFAAMJfw88ZADdAAAuAAQKfzIAAgUACQnoHcoVAKYCAAUACQnoHcoVAKYCAAAA.Mackthyra:BAAALgADCgcJBwABLgAFFAMJCgAFAH8PAA==.Madglowup:BAABLgAECn8kAAImAAkJ4iLEAAAmAwAmAAkJ4iLEAAAmAwAAAA==.Maggie:BAAALgAECgIJAgAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8gAAIEAAkJhxzBLwBaAgAEAAkJhxzBLwBaAgAAAA==.Magtaki:BAAALgAECgkJCAAAAA==.Magyar:BAEALgAECgUJBQAAAA==.Mainline:BAAALgAECggJDwAAAA==.Maizepriest:BAABLgAECn88AAIMAAkJbSK/BAAMAwAMAAkJbSK/BAAMAwAAAA==.Maliaa:BAAALgAECgMJAwAAAA==.Mannysaf:BAABLgAECn8jAAIQAAgJrA4ENwBrAQAQAAgJrA4ENwBrAQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAgJFAAEAHsVAA==.Marus:BAAALgADCgMJAwAAAA==.Maxz:BAAALgAECgEJAQAAAA==.',
Mc='Mcmurtrey:BAABLgAFFH8FAAIkAAIJxwo6HwB6AAAkAAIJxwo6HwB6AAAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Meerkat:BAAALgAECgEJAQABLgAFFAEJAQANAAAAAA==.Megazord:BAAALgAECgIJAgABLgAECgYJIgAfAEgYAA==.Mellowblink:BAABLgAECn8pAAIEAAgJxhdQWADUAQAEAAgJxhdQWADUAQABLgAECgYJIgAfAEgYAA==.Melorian:BAAALgADCgkJEAAAAA==.Melvier:BAAALgAECgEJAQAAAA==.Memeñtomori:BAABLgAECn8uAAMfAAkJGwYfDQDnAAAfAAkJGwYfDQDnAAAMAAUJTwNVdwBRAAAAAA==.Menara:BAAALgAECgYJEAAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Micromancer:BAAALgADCgMJAwAAAA==.Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAFFAEJAQAAAA==.Milkyboy:BAAALgADCgQJBAAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH9TAAQFAAkJNCZSAABfAwAFAAkJjCVSAABfAwAVAAgJHCNDAQCJAgAWAAMJIyTEIADTAAAuAAQKfz8ABBYACQnbJlYAAIsDABYACQk6JlYAAIsDABUACAkCJu0DAGUDAAUABglLJAxkAH0BAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECgkJMwAkAMIXAA==.Miravus:BAABLgAECn8zAAMkAAkJwheAHACyAQAkAAkJJheAHACyAQAgAAUJSRIGEAAkAQAAAA==.Mirlanda:BAABLgAECn8cAAIgAAcJpAZ5FQDUAAAgAAcJpAZ5FQDUAAAAAA==.Misttie:BAABLgAECn8bAAIlAAgJqw9fKABvAQAlAAgJqw9fKABvAQABLgAFFAQJDAAIAIwgAA==.',
Mo='Monie:BAAALgAECgEJAQAAAA==.Monkerick:BAABLgAECn8WAAQZAAkJkxl5BgAbAQAZAAUJ3RZ5BgAbAQAiAAcJgQolXgD+AAAlAAEJGhdDEABBAAAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morber:BAAALgAECgQJBQAAAA==.Mordeckai:BAAALgADCggJBwAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgkJMQAAAA==.',
Mu='Murkoobi:BAAALgAECgMJBQAAAA==.Mursk:BAAALgAECgMJBAAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJBQAAAA==.Mystáke:BAACLgAFFH8FAAIiAAIJxAufVABZAAAiAAIJxAufVABZAAAuAAQKfxgAAiIACQkFFIosAM0BACIACQkFFIosAM0BAAAA.',
['Mä']='Mäble:BAAALgAECgEJAQAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mí']='Mícky:BAAALgAECgEJAQAAAA==.',
['Mò']='Mòus:BAABLgAECn8XAAQjAAYJPg0dIQAkAQAjAAYJPg0dIQAkAQAPAAUJVAaMRwC8AAAOAAEJQQGSRgAXAAABLgAFFAQJDQAFAEMUAA==.',
['Mó']='Mómo:BAAALgAECggJCwAAAA==.Móus:BAAALgAECgUJDwABLgAFFAQJDQAFAEMUAA==.',
Na='Nagatok:BAAALgAECgkJDAABLgAECgkJLAALAB4iAA==.Narcissus:BAAALgAECgYJBgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAcJJwAfAHsVAA==.Naro:BAAALgAECgcJDAABLgAECgkJNgAEAC0kAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn82AAQdAAkJURQyIwA2AQAKAAcJrRNTLgBoAQAdAAcJERMyIwA2AQALAAUJIhAyIADeAAAAAA==.Nautrium:BAAALgAECgMJBAAAAA==.Nazari:BAAALgAECgEJAQAAAA==.',
Ne='Necrotis:BAAALgADCgkJNAAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn86AAMIAAkJUCTVAQCVAwAIAAkJUCTVAQCVAwAMAAYJzxq6UADOAAAAAA==.Neytholy:BAAALgAECgcJDAAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.Nezukö:BAAALgAECgUJCQAAAA==.',
Ni='Nienna:BAAALgAECgIJAgAAAA==.Nikkisan:BAAALgAECgMJAwAAAA==.Nitalan:BAAALgAECgMJAwAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAFFAEJAQAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAACLgAFFH8KAAIEAAIJIgLrWQBdAAAEAAIJIgLrWQBdAAAuAAQKfxYAAgQABQmLAwgSAZEAAAQABQmLAwgSAZEAAAAA.Nokaj:BAAALgAECgEJAgAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgYJDAAAAA==.Noras:BAABLgAECn8fAAMZAAkJsxkAEQA/AgAZAAkJnxkAEQA/AgAlAAUJshO5QgDvAAAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8rAAIeAAkJqRJwEwDGAQAeAAkJqRJwEwDGAQAAAA==.Notagnoblin:BAEBLgAFFH8aAAIDAAUJHyJ2CwAvAQADAAUJHyJ2CwAvAQABLgAFFAcJIQAlABAkAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Oa='Oaklyn:BAAALgAECgMJAwAAAA==.Oakshrus:BAAALgAECgEJAgAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIjAAkJGQ6OCgB1AQAjAAkJGQ6OCgB1AQAAAA==.Obolisq:BAAALgAECgEJAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJEQAAAA==.',
Od='Oddsoul:BAAALgAECgYJDwAAAA==.',
Og='Ogrelurd:BAABLgAECn8XAAMeAAcJSSBeDAAhAgAeAAcJSSBeDAAhAgAQAAQJGxgoYADVAAAAAA==.',
Oh='Ohlordy:BAAALgAECgcJEQAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJCgAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Oo='Oougway:BAAALgAECgYJBwAAAA==.',
Op='Ophelia:BAACLgAFFH8PAAMnAAMJvxZvBADqAAAnAAMJvxZvBADqAAAaAAIJRxFPnwCLAAAuAAQKf0wABBoACQkqI+0lAEYCABoACAm7He0lAEYCACcABwluIssJAMUBABsAAQmmCJh0ADAAAAAA.',
Or='Orakwa:BAABLgAECn8kAAMQAAkJxxrZAQB+AgAQAAkJxBrZAQB+AgARAAUJmhXHKwDaAAAAAA==.',
Ou='Outen:BAABLgAECn8hAAIFAAkJSg3LDQB0AQAFAAkJSg3LDQB0AQAAAA==.',
Oz='Ozzieliem:BAAALgAECgEJAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Palalamadi:BAAALgADCgMJAwAAAA==.Pallinda:BAABLgAECn8tAAMSAAkJfBYIGABIAgASAAkJfBYIGABIAgATAAkJkRLMWgC9AQAAAA==.Panakananama:BAAALgAECgcJDwAAAA==.Panz:BAABLgAECn82AAMPAAkJCwuILwB7AQAPAAkJCwuILwB7AQAjAAEJIA5MJwAvAAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papagrip:BAAALgAFFAIJBAABLgAFFAMJBgAaAIALAA==.Papalock:BAABLgAFFH8GAAIaAAMJgAucgADDAAAaAAMJgAucgADDAAAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgcJCAAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgMJCAAAAA==.Pazuzuu:BAAALgAECgIJAgABLgAECgkJJwAaANARAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Peanuttbutte:BAAALgAECgEJAQAAAA==.Pendulum:BAAALgAECgEJAQAAAA==.Pendulumlaw:BAACLgAFFH8KAAIeAAMJ3hBkKQDHAAAeAAMJ3hBkKQDHAAAuAAQKfxQAAx4ACQk2G5AHAH4CAB4ACQkdG5AHAH4CABAAAgkeEgSAAHcAAAAA.Pennypacker:BAAALgAECggJDwAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAABLgAECn8YAAMFAAYJcRCKkQAcAQAFAAYJcRCKkQAcAQAVAAUJVAgkIwCaAAAAAA==.',
Ph='Phara:BAABLgAECn8cAAQMAAkJcwswKgCAAQAMAAkJcwswKgCAAQAfAAUJZgirNgDwAAAIAAIJlAFvfAA3AAAAAA==.Phenomenon:BAAALgADCgYJBgAAAA==.Phoel:BAAALgADCgkJGAAAAA==.Phoopalychu:BAAALgAECgUJBQABLgAECgkJJAAiAKcSAA==.Phoopanchu:BAABLgAECn8kAAIiAAkJpxI5KgDbAQAiAAkJpxI5KgDbAQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pillowpantsu:BAAALgAECgYJBgAAAA==.Pinkbuns:BAABLgAECn9PAAIEAAkJsxwnBQBGAgAEAAkJsxwnBQBGAgAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn89AAIUAAkJyiRWAAAVAwAUAAkJyiRWAAAVAwAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsthyr:BAAALgAECgYJBwAAAA==.Popsy:BAABLgAECn8jAAITAAkJ9hATWgC/AQATAAkJ9hATWgC/AQAAAA==.Potatoad:BAAALgAECggJCAAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8vAAIQAAkJCiFBDACmAgAQAAkJCiFBDACmAgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAcJFAABABAlAA==.Prideflag:BAAALgAECgMJAwAAAA==.Priesthealer:BAAALgADCgkJCQAAAA==.Priestin:BAAALgAECgEJAQAAAA==.Primaldead:BAACLgAFFH8HAAIaAAIJXQuppQCFAAAaAAIJXQuppQCFAAAuAAQKf1kAAhoACQnMHLsTALACABoACQnMHLsTALACAAAA.Pristin:BAAALgAECgcJDgAAAA==.Profundity:BAABLgAECn8UAAMiAAcJlw1oGQCvAAAiAAcJlw1oGQCvAAAZAAEJNRAwnQAyAAAAAA==.',
Ps='Psyduck:BAAALgAFFAIJAgABLgAFFAkJXgATAAgmAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8rAAIBAAkJbSAVFQDJAgABAAkJbSAVFQDJAgAAAA==.',
Qe='Qeini:BAABLgAECn80AAIfAAkJTxiIDgCGAgAfAAkJTxiIDgCGAgAAAA==.',
Ra='Radrin:BAAALgAECgUJCwAAAA==.Rafoff:BAABLgAECn8bAAIPAAkJZQqVCQDJAAAPAAkJZQqVCQDJAAAAAA==.Rahll:BAAALgADCgkJNAAAAA==.Rancoramble:BAABLgAECn8XAAIDAAkJDQQ7MADgAAADAAkJDQQ7MADgAAAAAA==.Randis:BAABLgAECn8yAAMBAAkJCA8FWwC2AQABAAkJCA8FWwC2AQACAAYJoQKRKQCHAAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Rantcasey:BAABLgAFFH8FAAIFAAMJsgx8NQDIAAAFAAMJsgx8NQDIAAABLgAFFAMJCgAeAN4QAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razlek:BAAALgAECgUJBQAAAA==.Razonghoul:BAABLgAECn9FAAIBAAkJvCISDQAFAwABAAkJvCISDQAFAwAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Rejine:BAAALgAECgIJAgAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAABLgAECn8WAAQSAAcJsg3JDQCjAAASAAYJugzJDQCjAAATAAQJjAnJLgGBAAAHAAEJCgICTwAVAAAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAABLgAECn8gAAIFAAkJciRsHAB6AgAFAAkJciRsHAB6AgAAAA==.Reversewally:BAABLgAFFH8KAAIkAAMJKwqHHgCAAAAkAAMJKwqHHgCAAAAAAA==.Rexiis:BAABLgAECn8nAAMaAAkJ0BGMRQDKAQAaAAkJ0BGMRQDKAQAnAAEJAABdNAAzAAAAAA==.Reyth:BAABLgAECn8aAAIEAAkJpQmCIADGAAAEAAkJpQmCIADGAAAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8mAAIkAAcJKyG9EACcAgAkAAcJKyG9EACcAgAAAA==.',
Ri='Rightintwo:BAAALgADCgUJBQAAAA==.Rimos:BAAALgAECgEJAQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn9FAAMhAAkJ4hXsGQASAgAhAAkJ4hXsGQASAgAcAAYJGA31cAAJAQAAAA==.Rivenwood:BAAALgAECgEJAwAAAA==.',
Ro='Rockadin:BAABLgAECn8bAAITAAYJQBRrugAQAQATAAYJQBRrugAQAQAAAA==.Rokki:BAABLgAECn86AAIEAAcJ5xf4CQCoAQAEAAcJ5xf4CQCoAQAAAA==.Roostor:BAAALgAECgIJAgAAAA==.Rosael:BAAALgAECgEJAQAAAA==.Roundhouse:BAABLgAECn8aAAIlAAkJZBhWEAA6AgAlAAkJZBhWEAA6AgAAAA==.',
Ru='Rubbmytotems:BAABLgAECn8UAAIhAAcJiAtITwD5AAAhAAcJiAtITwD5AAAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8yAAMFAAkJjhcAMQAYAgAFAAkJjhcAMQAYAgAVAAIJrQn8egBXAAAAAA==.Rumí:BAABLgAECn8hAAIJAAkJYAkmbwBFAQAJAAkJYAkmbwBFAQAAAA==.Russell:BAAALgADCgkJKgAAAA==.Rutgore:BAACLgAFFH8FAAIkAAIJPhUdMQCfAAAkAAIJPhUdMQCfAAAuAAQKfzgAAiQACQlHHoIIAJ4CACQACQlHHoIIAJ4CAAAA.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDQAAAA==.Safewerd:BAEBLgAECn8ZAAMiAAkJUBHFQABrAQAiAAkJUBHFQABrAQAZAAMJNgeRhgBNAAAAAA==.Saitama:BAABLgAECn8vAAIZAAgJ9B3eAgC8AQAZAAgJ9B3eAgC8AQABLgAECggJLwAZAPQdAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgcJEAAAAA==.Saraceleste:BAAALgAECgYJDwAAAA==.Sarahfi:BAABLgAECn8WAAMHAAgJ0RDyBAAxAQAHAAcJYBDyBAAxAQATAAcJ/Ah7+QC/AAAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAABLgAECn8nAAIaAAkJpxRsBQDRAQAaAAkJpxRsBQDRAQAAAA==.Sarasophie:BAAALgAECgUJBQAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgcJEwAAAA==.Sathenazarke:BAACLgAFFH8iAAMjAAYJVR7SAADoAQAjAAYJVR7SAADoAQAOAAYJ5wudGAAOAQAuAAQKfzYABCMACQlgIo0EACwCACMABwnoII0EACwCAA4ACAnkGNIRACECAA8ABwncGqEbAOsBAAEuAAUUCAklACAAViIA.Saths:BAAALgADCgEJAQABLgAECggJEwANAAAAAA==.',
Sc='Schallue:BAABLgAECn8gAAIoAAgJkAh8BwAoAQAoAAgJkAh8BwAoAQAAAA==.Schism:BAAALgAECgYJEAAAAA==.Scoban:BAACLgAFFH8rAAISAAgJTiF8AwC1AgASAAgJTiF8AwC1AgAuAAQKfywAAhIACQkfIAsOAKgCABIACQkfIAsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Selise:BAAALgAECgQJBAAAAA==.Selithel:BAABLgAECn8XAAIYAAgJ4AfgLgAOAQAYAAgJ4AfgLgAOAQAAAA==.Seraphnite:BAABLgAECn8UAAITAAgJ+AzWigBbAQATAAgJ+AzWigBbAQABLgAECgQJBAANAAAAAA==.Serioussurv:BAABLgAECn8mAAMFAAcJSx5jBgAXAgAFAAcJSx5jBgAXAgAWAAcJARQPAwB3AQAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgkJMwADAMkYAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAABLgAECn8WAAQMAAcJtgZTXQCiAAAMAAYJowdTXQCiAAAfAAUJUQWUWgCVAAAIAAEJFgHNfgAXAAAAAA==.Shaeliana:BAAALgAECgQJDgAAAA==.Shalera:BAAALgAECgkJBwAAAA==.Shaohlin:BAAALgAECgUJDQAAAA==.Shaqfu:BAAALgADCgkJJwAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shawk:BAAALgAECgEJAQAAAA==.Shayy:BAABLgAECn8aAAIfAAgJLw88BQCsAQAfAAgJLw88BQCsAQAAAA==.Shields:BAAALgAECgkJCQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAABLgAECn9QAAIEAAkJihskBAB+AgAEAAkJihskBAB+AgAAAA==.Shivers:BAAALgAFFAMJAwAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Sholin:BAABLgAECn9BAAIlAAkJ4iSQAQBUAwAlAAkJ4iSQAQBUAwAAAA==.Shomea:BAABLgAECn8pAAMDAAcJtQlRCQDBAAADAAcJtQlRCQDBAAABAAMJ9QbVJAF9AAAAAA==.Shugz:BAAALgADCgkJLAAAAA==.Shumai:BAAALgAECgkJEAAAAA==.',
Si='Sikotick:BAABLgAECn8jAAIGAAgJmh5RFwCMAgAGAAgJmh5RFwCMAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAACLgAFFH8cAAIEAAUJqB/qPQB2AQAEAAUJqB/qPQB2AQAuAAQKfzkAAgQACQkRIUUaAL0CAAQACQkRIUUaAL0CAAAA.Silverbolt:BAABLgAECn8vAAIQAAkJ4A6sKwCmAQAQAAkJ4A6sKwCmAQAAAA==.Simbelmyne:BAAALgAECgQJCAAAAA==.Sinderone:BAACLgAFFH8mAAMSAAgJxBIOCQArAgASAAgJxBIOCQArAgATAAIJlwz/mwCDAAAuAAQKf0AAAxIACQl/H0gIAAcDABIACQl/H0gIAAcDABMABQn9FwXeAOEAAAAA.',
Sk='Skaaduush:BAAALgAECgYJDAAAAA==.Skyjin:BAAALgAECgIJAgAAAA==.Skyne:BAAALgAECgEJAQAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn87AAIBAAkJwCD2EwDQAgABAAkJwCD2EwDQAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Slippinwater:BAAALgAECgIJAgAAAA==.Sllew:BAACLgAFFH8HAAIBAAMJthnohAD/AAABAAMJthnohAD/AAAuAAQKfy0AAgEACQkVIugPAO0CAAEACQkVIugPAO0CAAAA.Slothfu:BAAALgAECgEJAQAAAA==.Slye:BAAALgAECgEJAQAAAA==.Slyhoof:BAAALgAECgYJCAABLgAECgkJJQAJAKEaAA==.Slyvanna:BAAALgAECgMJBAABLgAECgkJJQAJAKEaAA==.Slèw:BAAALgAECgQJBwAAAA==.',
Sm='Smartwater:BAABLgAECn8VAAITAAcJSA0gFwAGAQATAAcJSA0gFwAGAQAAAA==.Smitestuff:BAAALgAECgYJDwAAAA==.Smokymcpot:BAAALgADCgYJBgAAAA==.Smoulder:BAAALgAECgcJDQAAAA==.',
Sn='Snigles:BAABLgAECn8/AAMgAAkJMxraBAA9AgAgAAkJuxfaBAA9AgAkAAcJVhOYAwCDAQAAAA==.Sniperism:BAAALgAECgEJAQAAAA==.Snurp:BAAALgAECgEJAQABLgAFFAQJCwACAE0bAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgAECgEJAQAAAA==.Souei:BAAALgADCgEJAQABLgAECgkJGwABAAEUAA==.Soulfinder:BAAALgADCgMJAwAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.Southpau:BAAALgADCgUJBQAAAA==.',
Sp='Spartos:BAABLgAECn8UAAIQAAYJsBRxQABDAQAQAAYJsBRxQABDAQAAAA==.Speedy:BAAALgAECgMJBAAAAA==.Sposi:BAEBLgAECn84AAIDAAkJzSGzBQDLAgADAAkJzSGzBQDLAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.Sprinkle:BAAALgAECgIJAgAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAABLgAECn8jAAMcAAYJXwZpjQC/AAAcAAYJXwZpjQC/AAAhAAUJ7AQydwCIAAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAABLgAECn8eAAIQAAkJWx2/EgBcAgAQAAkJWx2/EgBcAgAAAA==.Stoneweaver:BAAALgAECgEJAQABLgAECgkJLwAGADwdAA==.',
Su='Subliminal:BAABLgAECn8XAAMkAAkJChG4JABvAQAkAAkJChG4JABvAQAmAAEJswxMJQAxAAAAAA==.Sumasuka:BAABLgAECn8UAAMcAAgJehRDCQCJAQAcAAYJxBZDCQCJAQAhAAQJvwfuFACAAAAAAA==.Sumbtch:BAAALgAECgUJCgAAAA==.Sungdihhwoo:BAAALgAECgIJAgABLgAECgcJJgAFAEseAA==.Susann:BAAALgAFFAEJAQABLgAFFAQJDQAFAEMUAA==.',
Sv='Svartalfar:BAAALgADCgcJBgAAAA==.',
Sy='Syravia:BAABLgAECn8oAAITAAkJtAWAuAATAQATAAkJtAWAuAATAQAAAA==.',
['Sé']='Séraphyne:BAAALgAECgYJDgAAAA==.',
['Sò']='Sòl:BAAALgAFFAIJAgABLgAFFAQJBwAHABASAA==.',
Ta='Talarin:BAAALgAECgcJEQAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAABLgAECn8ZAAIoAAkJ5REPAQBYAQAoAAkJ5REPAQBYAQAAAA==.Tatersmonk:BAECLgAFFH8hAAIlAAcJECSBAgBEAgAlAAcJECSBAgBEAgAuAAQKfyMAAiUACQnpJLsDAFQDACUACQnpJLsDAFQDAAAA.Taterthot:BAAALgAECgEJAQAAAA==.Tavinrayn:BAABLgAECn8vAAMoAAkJBB5fAAAZAgAoAAkJBB5fAAAZAgAEAAMJ3Aa5IAF3AAAAAA==.Tazzar:BAABLgAECn8/AAIPAAkJoQ/NIwC+AQAPAAkJoQ/NIwC+AQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECgkJQwAGAFQUAA==.Tekesh:BAAALgAECgMJCQAAAA==.Tekêsh:BAABLgAECn8bAAMHAAgJZCO+BACsAgAHAAgJZCO+BACsAgATAAYJKxXnqQAoAQAAAA==.Telarin:BAABLgAECn8fAAQFAAkJmRnUYgCAAQAFAAcJ9RvUYgCAAQAWAAgJkA3nIwB/AQAVAAEJuAOdRAAhAAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.Teshara:BAAALgAECgMJBAAAAA==.',
Th='Thalliana:BAAALgAECgQJEAAAAA==.Thandor:BAAALgAECgYJEgAAAA==.Thanedrius:BAAALgAECgUJBQAAAA==.Thebigdawg:BAACLgAFFH8TAAIiAAMJxiE0GgDvAAAiAAMJxiE0GgDvAAAuAAQKfxwAAiIACQnjHu8IAAwDACIACQnjHu8IAAwDAAAA.Thedeadangel:BAAALgADCgEJAQAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgkJDwAAAA==.Thiñgtwo:BAAALgAECgYJCAAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgAECgEJAQAAAA==.Thuliaga:BAAALgAECgkJCwAAAA==.Thörskin:BAAALgADCgUJAQAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJEQABLgAECgkJHQAMANgTAA==.Tikdab:BAAALgAECgYJCQAAAA==.Tinneas:BAAALgADCgEJAgAAAA==.Titlepush:BAAALgAECgYJBgAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgAECgIJAwAAAA==.Tomás:BAABLgAECn89AAMcAAkJJBKJKAAcAgAcAAkJJBKJKAAcAgAhAAkJFxddBwBIAQAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8iAAIDAAgJPxuEDAC1AQADAAgJPxuEDAC1AQAuAAQKfzIAAgMACQnCIRUDADEDAAMACQnCIRUDADEDAAAA.Toordn:BAAALgAECgQJBwAAAA==.Torstai:BAABLgAECn8bAAInAAkJTQqiEwA0AQAnAAkJTQqiEwA0AQAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAABLgAECn8aAAMWAAkJ0B5uCQCHAgAWAAkJvh1uCQCHAgAVAAQJ1hzaQQBRAQAAAA==.',
Ts='Tserendolgor:BAABLgAECn86AAQYAAgJdRyGEAAfAgAYAAgJCRyGEAAfAgAJAAYJ9hz1SQCoAQAUAAUJ/hfcIACWAAABLgAECgYJIgAfAEgYAA==.',
Tu='Tunz:BAAALgAECgEJAgAAAA==.Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAhAFcWAA==.Twinsha:BAABLgAECn8dAAMhAAgJVxYyLQCPAQAhAAgJVxYyLQCPAQAcAAcJJwS1WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAhAFcWAA==.',
Ty='Tyinregard:BAAALgADCgIJAgAAAA==.Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrannis:BAAALgAECgIJAgAAAA==.Tyrasong:BAAALgAECgMJBgAAAA==.Tyresious:BAABLgAECn8wAAITAAkJoSNaCQAdAwATAAkJoSNaCQAdAwAAAA==.',
['Tà']='Tàric:BAAALgAECgQJCAAAAA==.',
Un='Unauma:BAACLgAFFH8NAAIGAAQJwgjTSgCQAAAGAAQJwgjTSgCQAAAuAAQKfzEAAwYACQknHHIWAJQCAAYACQknHHIWAJQCAB0ABwl1IY8KADwCAAEuAAUUBgkKABwAeRIA.Undeadpanda:BAAALgAECgIJAgABLgAECgcJJAABALsVAA==.Unholydk:BAABLgAECn8aAAIJAAkJPRlILQASAgAJAAkJPRlILQASAgAAAA==.',
Ut='Utherrex:BAAALgAECgcJBwABLgAECgkJJwAaANARAA==.',
Va='Vaa:BAAALgAECgcJCwAAAA==.Vahaghn:BAACLgAFFH8KAAIeAAMJWSGMGQAZAQAeAAMJWSGMGQAZAQAuAAQKfzAAAh4ACQk3IxcCAA4DAB4ACQk3IxcCAA4DAAAA.Valcerus:BAABLgAECn84AAIEAAcJjR5OBgASAgAEAAcJjR5OBgASAgAAAA==.Valedus:BAABLgAECn8/AAITAAkJiCQRBwA2AwATAAkJiCQRBwA2AwAAAA==.Valhallæ:BAAALgAECgMJAwAAAA==.Validrela:BAAALgAECgUJBwAAAA==.Vampirism:BAAALgAECgUJBwABLgAECggJHwAiAEYeAA==.Vaskie:BAAALgAFFAIJAgABLgAFFAMJBQAQAL8NAA==.',
Ve='Veelete:BAAALgADCgkJEwABLgAECggJKQASABQeAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECgkJOgAIAFAkAA==.Vespra:BAABLgAECn9EAAIcAAkJRyDBCQAYAwAcAAkJRyDBCQAYAwAAAA==.',
Vh='Vhas:BAABLgAECn8UAAMGAAkJ1QntTgBTAQAGAAkJ1QntTgBTAQAdAAMJbAQBFwBTAAAAAA==.Vhem:BAAALgAECgkJBwAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJDAANAAAAAA==.Visage:BAAALgADCgQJBAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8yAAIHAAkJEwjgHgAdAQAHAAkJEwjgHgAdAQAAAA==.Voldamar:BAAALgAECgcJEwAAAA==.Voltashi:BAABLgAECn81AAQlAAkJPBZMEgAjAgAlAAkJPBZMEgAjAgAZAAQJSBHWVgCzAAAiAAQJygnDoQBWAAAAAA==.Volthreal:BAAALgADCgQJAwAAAA==.Voltuk:BAACLgAFFH8GAAIRAAMJOiDxCQASAQARAAMJOiDxCQASAQAuAAQKfycABBEACQlfGLwMAB4CABEACQmgFrwMAB4CABAABQngFk9MABUBAB4ABAkaE1ZFALQAAAAA.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAFFAQJCAAFANQSAA==.',
Wa='Wagyuboi:BAAALgAECgcJDwAAAA==.Wallypaly:BAABLgAECn8nAAMTAAgJDhbyjwBSAQATAAcJVxfyjwBSAQAHAAUJ6RaCIwD5AAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn9WAAMSAAkJVCE/BgApAwASAAkJVCE/BgApAwATAAQJ9wpqKACdAAAAAA==.Warwarb:BAAALgAECgYJBgABLgAECgkJNwAaAA8cAA==.Waterliliy:BAABLgAECn8dAAIMAAkJ2BOtMgBQAQAMAAkJ2BOtMgBQAQAAAA==.',
We='Weaveraz:BAAALgAECgIJAgAAAA==.',
Wh='Whatcrap:BAAALgAECgQJBAAAAA==.Whir:BAAALgADCgUJBQAAAA==.',
Wi='Wifiog:BAAALgAECgIJAgAAAA==.Windfurypie:BAAALgAECgkJBQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8wAAMFAAkJ0RooIwBXAgAFAAkJ0RooIwBXAgAVAAYJkQtBIACuAAAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECgcJOAAEAI0eAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgAECgEJAwABLgAFFAQJCwAaAC4VAA==.Xelvandar:BAAALgAECgEJAQABLgAECggJFgAHANEQAA==.Xenhaseo:BAABLgAECn8rAAIPAAkJXxh/FQAuAgAPAAkJXxh/FQAuAgAAAA==.',
Xh='Xhuri:BAAALgAECgIJBwAAAA==.',
Xi='Xilla:BAAALgAECgcJCAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAABLgAECn8vAAIGAAkJPB3aAgAxAgAGAAkJPB3aAgAxAgAAAA==.',
Yo='Yorllik:BAAALgAECgUJDAAAAA==.Yougotwreckd:BAABLgAFFH8JAAITAAQJiwbMXAD2AAATAAQJiwbMXAD2AAAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8bAAIJAAgJQBYxawBOAQAJAAgJQBYxawBOAQAAAA==.',
Yu='Yuzuha:BAAALgADCgkJAwAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIPAAkJJCH/CwCaAgAPAAkJJCH/CwCaAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJEAANAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zapura:BAAALgADCgYJBgAAAA==.Zaraelil:BAAALgADCgMJAwAAAA==.Zarkhan:BAABLgAECn8kAAMBAAcJuxWFCgB4AQABAAcJuxWFCgB4AQACAAEJmhOROAA6AAAAAA==.Zarulyn:BAAALgAECgkJEgAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAABLgAECn8fAAMjAAkJ1hIxBgDuAQAjAAkJ1hIxBgDuAQAPAAcJwgyyOgBBAQAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8pAAMcAAkJnxFRPQC5AQAcAAkJnxFRPQC5AQApAAgJrAY2GwAnAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgYJCgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn88AAIFAAkJWA7XUACwAQAFAAkJWA7XUACwAQAAAA==.',
['Äc']='Äcid:BAABLgAECn8sAAIcAAkJ1xslHQBkAgAcAAkJ1xslHQBkAgAAAA==.',
['Åp']='Åpollo:BAABLgAFFH8MAAIiAAUJbxL8GgDnAAAiAAUJbxL8GgDnAAABLgAFFAUJGgAIAGwkAA==.',
['Èa']='Èastçoast:BAAALgADCgcJGQAAAA==.',
['Êl']='Êlydala:BAAALgAECgYJBwAAAA==.',
['Ðe']='Ðeja:BAAALgAECgMJBgABLgAECggJFgAHANEQAA==.',
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
