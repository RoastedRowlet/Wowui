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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Unknown-Unknown','Druid-Feral','Druid-Restoration','Druid-Balance','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Monk-Windwalker','Evoker-Preservation','DeathKnight-Unholy','Warrior-Protection','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Monk-Mistweaver','Priest-Shadow','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-05-17',data={Ac='Achooe:BAABLgAECn8lAAMBAAgJngWSIgC2AAABAAgJbAWSIgC2AAACAAEJJgKzZAEaAAAAAA==.',
Ad='Adrel:BAAALgAECgQJBQAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn8pAAQGAAgJKhL0FQC7AQAGAAgJWxH0FQC7AQAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8mAAIJAAgJlxHOWwCTAQAJAAgJlxHOWwCTAQAAAA==.Agathorz:BAAALgAECgEJAgAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgYJDAAAAA==.',
Ak='Akiras:BAAALgADCgYJBgAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECgkJHQAKAKYbAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAABLgAECn8tAAMDAAkJRCRMAgApAwADAAkJRCRMAgApAwALAAYJ9BD3HgAbAQAAAA==.Allei:BAAALgAECgYJCQABLgAFFAMJAwAMAAAAAA==.Alyndrya:BAABLgAECn8ZAAMEAAgJIhQ2EgCxAQAEAAgJIhQ2EgCxAQAFAAYJjRCxcQD5AAAAAA==.Alyndrys:BAABLgAECn8YAAINAAcJlw4DEgCNAQANAAcJlw4DEgCNAQAAAA==.',
Am='Amelialynne:BAABLgAECn8vAAIFAAkJHhJlLwDMAQAFAAkJHhJlLwDMAQAAAA==.Amithralia:BAABLgAECn8gAAIOAAgJyB/eDADBAgAOAAgJyB/eDADBAgAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAAALgAECgUJDgAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAAALgAECgYJEQAAAA==.',
Ao='Aodwarf:BAAALgAECgEJAQABLgAFFAYJGAAOAMAgAA==.Aohikari:BAAALgADCgYJCgABLgAFFAYJGAAOAMAgAA==.Aokuma:BAACLgAFFH8YAAIOAAYJwCCCAQAGAgAOAAYJwCCCAQAGAgAuAAQKfyoAAw4ACQlCJI8GACIDAA4ACQlCJI8GACIDAA8ABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8UAAIQAAgJ9gVMDAAvAQAQAAgJ9gVMDAAvAQAAAA==.',
Aq='Aquaten:BAAALgAECgUJEgAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8WAAMPAAgJzBbqPgDIAAAPAAYJZxTqPgDIAAAOAAcJWA5MagC+AAAAAA==.Arcafrost:BAAALgAECgkJAQAAAA==.Arceus:BAAALgAECgQJBgAAAA==.Archaon:BAABLgAECn8cAAMRAAYJFw46gAALAQARAAYJFw46gAALAQASAAEJAADgQQAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgUJBwAMAAAAAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn86AAMTAAkJiyb/AQBrAwATAAkJiyb/AQBrAwAUAAYJIyWXFQDzAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgUJBwAAAA==.Asmódeus:BAABLgAECn8cAAQVAAgJoA73DQBTAQAVAAYJWw73DQBTAQARAAgJCQozYwBJAQASAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAABLgAECn8eAAIJAAgJbQ8mXACSAQAJAAgJbQ8mXACSAQAAAA==.',
['Aì']='Aìo:BAAALgAECgUJEAABLgAECgYJDAAMAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECggJEgAMAAAAAA==.Baelhay:BAAALgAECgUJEgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAABLgAECn8rAAIFAAkJMSALEwDoAgAFAAkJMSALEwDoAgAAAA==.Belmaris:BAABLgAECn8lAAIQAAgJtxeNBQDgAQAQAAgJtxeNBQDgAQAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAAALgAECgYJEwAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8VAAIOAAgJag5fOQB2AQAOAAgJag5fOQB2AQAAAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAAALgAECgUJDQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8kAAIWAAcJhh5zBQAFAgAWAAcJhh5zBQAFAgAAAA==.Blegh:BAACLgAFFH8GAAMXAAMJ7BVXKADmAAAXAAMJ7BVXKADmAAAYAAEJEAWwCgBIAAAuAAQKfyEAAxgACAkvHqcKADECABgABwk2HacKADECABcABgkgGygfAMoBAAAA.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn8zAAINAAkJQCFpAQACAwANAAkJQCFpAQACAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMZAAgJxAnuRABkAQAZAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8dAAMKAAkJphv1HQASAgAKAAkJphv1HQASAgAaAAUJdxhkLgAPAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAMAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAABLgAECn8WAAIIAAgJyhHiPACmAQAIAAgJyhHiPACmAQAAAA==.Buggers:BAAALgAECgIJAgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8GAAIJAAQJuBjoTwAPAQAJAAQJuBjoTwAPAQABLgAFFAcJGAAbABkeAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8YAAIFAAgJORiUTADCAQAFAAgJORiUTADCAQAAAA==.Caladelm:BAAALgAECgYJDAAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8aAAIcAAcJpgt7fQAvAQAcAAcJpgt7fQAvAQAAAA==.Carlarae:BAABLgAECn8UAAIJAAYJOQSUzAC/AAAJAAYJOQSUzAC/AAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8IAAIJAAQJ5hZiVAAAAQAJAAQJ5hZiVAAAAQAuAAQKfxoAAgkACAnwILcYAJMCAAkACAnwILcYAJMCAAAA.Cegeo:BAABLgAECn82AAISAAkJtRirAgBAAgASAAkJtRirAgBAAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn87AAMDAAkJkyPnAwD8AgADAAkJkyPnAwD8AgALAAEJ0g4zVAAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAABLgAECn8cAAMRAAYJ5x9yWQC7AQARAAUJyiByWQC7AQAVAAQJSBjyEgD9AAAAAA==.',
Ci='Ciennajewel:BAAALgAECgcJCgAAAA==.Cirdle:BAABLgAECn8UAAMIAAcJ7wuMZwAxAQAIAAcJvgqMZwAxAQAHAAMJIwZdIgBoAAAAAA==.Cirona:BAABLgAECn8cAAIOAAYJeyGlGQA7AgAOAAYJeyGlGQA7AgAAAA==.',
Cl='Clausewitz:BAABLgAECn8UAAIdAAgJCgogHAASAQAdAAgJCgogHAASAQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAABLgAECn8dAAIRAAgJnhzZIwAdAgARAAgJnhzZIwAdAgAAAA==.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAMAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8gAAIUAAgJ2AJIRADYAAAUAAgJ2AJIRADYAAAAAA==.Creamyweamy:BAABLgAECn8YAAIeAAcJFRX0HQCYAQAeAAcJFRX0HQCYAQAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJPw3PhAA6AQAJAAcJPw3PhAA6AQAfAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgADCgUJDwAAAA==.Cruzmaster:BAABLgAECn8ZAAMUAAgJ/RUTGwDBAQAUAAgJ/RUTGwDBAQAgAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8aAAIJAAcJYQW1pAACAQAJAAcJYQW1pAACAQAAAA==.',
Cu='Cuddly:BAAALgAFFAIJAwABLgAFFAgJIwAhAGAfAA==.Cupp:BAAALgAECgcJEQAAAA==.Cute:BAAALgAECgYJCAABLgAFFAcJGAAhAAUXAA==.',
Da='Daamass:BAAALgADCgMJAwAAAA==.Daddy:BAACLgAFFH8eAAIiAAcJ6yTtAADtAgAiAAcJ6yTtAADtAgAuAAQKf4cAAiIACQmzJgwAAAkEACIACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAMAAAAAA==.Daggonet:BAAALgAFFAEJAgAAAA==.Dalrin:BAABLgAECn8XAAMgAAYJ7A+uFQBiAQAgAAYJ7A+uFQBiAQAUAAQJzAfqZwCjAAAAAA==.Darayia:BAAALgAECgEJAQAAAA==.Darkcarnival:BAABLgAECn8lAAIRAAgJ0BvFJQAUAgARAAgJ0BvFJQAUAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAABLgAECn8hAAIDAAkJiRdMLAADAgADAAkJiRdMLAADAgAAAA==.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgADCgcJGAABLgAECgYJDgAMAAAAAA==.Darthraider:BAAALgAECgQJCwAAAA==.Dasnotgood:BAAALgAECgUJDAAAAA==.Datoneshammy:BAABLgAECn8UAAQUAAgJxwdwNgAVAQAUAAgJxwdwNgAVAQATAAEJowGnqgAhAAAgAAEJeAG1LQAeAAAAAA==.Davrøs:BAAALgAECgIJBgAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8UAAIFAAgJTxT+PQCQAQAFAAgJTxT+PQCQAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAAALgAECgcJEgAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8eAAMeAAgJfhE2HwCOAQAeAAgJfhE2HwCOAQAjAAYJ2Av/NAD+AAAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8aAAIPAAgJeBUzGwCjAQAPAAgJeBUzGwCjAQAAAA==.Desdemona:BAABLgAECn8aAAIBAAcJQB5UCwDHAQABAAcJQB5UCwDHAQAAAA==.Dethiaris:BAAALgAECgEJAQAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAAALgAFFAQJBAAAAA==.',
Di='Dianimal:BAABLgAECn8YAAIPAAYJ+QaMQQC9AAAPAAYJ+QaMQQC9AAAAAA==.Dings:BAAALgADCggJFAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8eAAMZAAgJcR/yCQCvAgAZAAcJoiLyCQCvAgACAAgJOxzdLQALAgAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIcAAUJ0CFNHwCBAQAcAAUJ0CFNHwCBAQAuAAQKf0AAAhwACQl2JlADAFIDABwACQl2JlADAFIDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8mAAMCAAkJCBbiPgDNAQACAAkJCBbiPgDNAQABAAQJfAGFOABBAAAAAA==.Doomfeather:BAAALgAECgEJAgAAAA==.Dorigog:BAABLgAECn8oAAICAAkJHxI8TACmAQACAAkJHxI8TACmAQAAAA==.',
Dr='Dragee:BAAALgAECgEJAwABLgAECggJFAAFAE8UAA==.Dragon:BAAALgAECgYJCwAAAA==.Dragonpunch:BAABLgAECn8iAAIiAAkJ6xmqFgABAgAiAAkJ6xmqFgABAgAAAA==.Driftyshaman:BAABLgAECn8YAAIUAAcJxgnwOwD7AAAUAAcJxgnwOwD7AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAAALgAECgcJDwAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Dw='Dworflundgrn:BAABLgAECn8qAAIgAAgJvg5FDQCCAQAgAAgJvg5FDQCCAQAAAA==.',
Dy='Dyamï:BAABLgAECn8lAAIiAAgJ+BmHEQA5AgAiAAgJ+BmHEQA5AgAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAAALgAECgYJEgAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8eAAIUAAYJHAyKQgDfAAAUAAYJHAyKQgDfAAAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAAALgADCgkJCgAAAA==.Ellä:BAAALgAECgQJBwAAAA==.Elrythe:BAACLgAFFH8IAAIIAAMJYw8lOADuAAAIAAMJYw8lOADuAAAuAAQKfy8AAggACQlPIDEPAJcCAAgACQlPIDEPAJcCAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECgcJCAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJAwAAAA==.',
Ev='Evilmorana:BAAALgAECgMJAwAAAA==.',
Fa='Fallyynn:BAAALgAECgYJDgAAAA==.Fatalii:BAAALgADCgEJAQABLgAECggJEgAMAAAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIOAAcJvhEsNwCAAQAOAAcJvhEsNwCAAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgADCgYJBgAAAA==.',
Fl='Floofies:BAACLgAFFH8ZAAIgAAUJUiGJAgBkAQAgAAUJUiGJAgBkAQAuAAQKfyMAAiAACQnjJbUDAO8CACAACQnjJbUDAO8CAAAA.Floofyfu:BAAALgAECgYJCgABLgAFFAUJGQAgAFIhAA==.',
Fr='Fredrickk:BAAALgAECgUJBwAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgQJBQABLgAFFAUJEgATAGUYAA==.Furryphase:BAACLgAFFH8SAAITAAUJZRjxDwB8AQATAAUJZRjxDwB8AQAuAAQKfyQAAxMACQnxHAwNALUCABMACQnxHAwNALUCABQABAlyCc1eAHoAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAUJGQAgAFIhAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgUJCQAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECgQJBQAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn8uAAITAAkJcByeDgCaAgATAAkJcByeDgCaAgAAAA==.',
Go='Goatjira:BAAALgAECgEJAQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJFwAcAN4eAA==.Gripisrdy:BAABLgAECn8lAAMcAAgJVx7BJQAyAgAcAAgJVx7BJQAyAgAkAAEJ7h00PgBQAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMlAAkJkCKsAAAFAwAlAAkJkCKsAAAFAwAmAAEJugwNXgA7AAAAAA==.Guìdo:BAAALgAECgYJDgAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAAALgAECgcJDQAAAA==.Hairyjolene:BAAALgAECgUJEgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAECgkJKQAMAAAAAA==.Handsome:BAAALgADCgcJCAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIRAAcJGh+rJQB8AgARAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEQAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAAALgAECgYJEQAAAA==.',
Hi='Hikaridh:BAABLgAFFH8DAAIFAAEJvxMJbABNAAAFAAEJvxMJbABNAAABLgAFFAYJGAAOAMAgAA==.Hikarimonk:BAAALgAFFAEJAQABLgAFFAYJGAAOAMAgAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAYJGAAOAMAgAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgQJBgAMAAAAAA==.Holyblimblam:BAAALgAECgYJEAAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8mAAMcAAgJAx7YLwAFAgAcAAgJlh3YLwAFAgAkAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8eAAIjAAYJNA1YMwAGAQAjAAYJNA1YMwAGAQAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJDwAAAA==.Icyjackets:BAAALgAECgUJEgAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJAwAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJkw8ZNwC8AQAIAAkJkw8ZNwC8AQAAAA==.Jameson:BAABLgAECn8gAAIDAAgJ4RMmJACTAQADAAgJ4RMmJACTAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn8uAAMOAAcJfQ/iPgBcAQAOAAcJfQ/iPgBcAQAPAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgEJAQABLgAECgYJDAAMAAAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAMAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAAALgAECgYJEAAAAA==.Jessicà:BAAALgAECgEJAQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8ZAAMTAAYJIhYRNgCrAQATAAYJIhYRNgCrAQAUAAUJbxJeRgDRAAAAAA==.Jiwà:BAAALgAECgkJAgABLgAFFAQJEAAjAPkKAA==.Jiwâ:BAACLgAFFH8QAAIjAAQJ+QpEEgAoAQAjAAQJ+QpEEgAoAQAuAAQKfzIAAiMACQn4HcsKAGQCACMACQn4HcsKAGQCAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECgcJEQAAAA==.Joss:BAAALgAECgEJAwAAAA==.',
Ka='Kadan:BAAALgAECgYJBgABLgAECgkJKwAFADEgAA==.Kahless:BAAALgADCgMJBgAAAA==.Kaibab:BAAALgADCgEJAQAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8eAAIDAAgJQAeyPQAMAQADAAgJQAeyPQAMAQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgADCgkJDwAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Keyadistor:BAABLgAECn8XAAMcAAkJ3h5DXQDbAQAcAAYJ7hpDXQDbAQAnAAcJEB6zDAA9AQAAAA==.',
Kh='Khamûl:BAAALgAECgEJAQAAAA==.Khazabrew:BAABLgAECn8vAAIKAAkJYh04BwCUAgAKAAkJYh04BwCUAgAAAA==.',
Ki='Kiamara:BAABLgAECn8UAAIRAAcJbAeKhQAAAQARAAcJbAeKhQAAAQAAAA==.Kinderlin:BAABLgAECn8XAAICAAYJLBI6nAABAQACAAYJLBI6nAABAQAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIOAAcJbhZXLQC1AQAOAAcJbhZXLQC1AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQYAAgJfRaSDwDiAQAYAAYJNhmSDwDiAQAXAAMJfRSEQgDYAAAbAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.',
Lo='Loadedtater:BAABLgAECn8yAAQGAAkJpyX9AABFAwAGAAkJmyT9AABFAwAIAAgJjybXBgD4AgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAAALgAFFAMJAwAAAA==.Lorianne:BAACLgAFFH8FAAITAAIJ+hGbQACEAAATAAIJ+hGbQACEAAAuAAQKfygAAxMACAmvGGQpAOkBABMACAmvGGQpAOkBABQABQmxC7tWAOoAAAEuAAUUAwkDAAwAAAAA.Lorri:BAAALgADCgQJBQABLgAFFAMJAwAMAAAAAA==.',
Lu='Lucianas:BAAALgAECgcJDgAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJCAAAAA==.',
Ly='Lysi:BAAALgAECgUJEgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Madaea:BAABLgAECn8zAAIiAAkJqx+7BgDoAgAiAAkJqx+7BgDoAgAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn8uAAIJAAkJ2hqeHQB3AgAJAAkJ2hqeHQB3AgABLgAFFAMJCwAGAAsZAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAAALgAECgYJCwABLgAECgcJEwAMAAAAAA==.Makavali:BAAALgAECgQJBQABLgAECgcJEwAMAAAAAA==.Makdaddy:BAAALgAECgcJEwAAAA==.Malzeth:BAAALgAECgEJAQAAAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn8fAAIIAAkJ3Ru3EwB0AgAIAAkJ3Ru3EwB0AgAAAA==.Mate:BAAALgADCgkJHQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAQAAAA==.Meeseks:BAAALgAECgcJBwAAAA==.Melbeast:BAABLgAECn8WAAIIAAYJixsxWABSAQAIAAYJixsxWABSAQAAAA==.Melorea:BAAALgAECgMJBQAAAA==.Merdin:BAABLgAECn8ZAAMJAAkJHQ9qRgDOAQAJAAkJAw9qRgDOAQAfAAEJpwwYIAAvAAAAAA==.Methmartion:BAAALgAECgUJEgABLgAECgcJCAAMAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJBgAAAA==.Missiah:BAABLgAECn8qAAIBAAgJiwT/IADCAAABAAgJiwT/IADCAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgIJBAAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQAPAO8WAA==.Molfise:BAABLgAECn8bAAMKAAYJMBSIMQALAQAKAAYJdhGIMQALAQAaAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn80AAIeAAgJnh3BCQCMAgAeAAgJnh3BCQCMAgAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAAALgAECgYJEwAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgMJAgAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Mugatoo:BAAALgADCgMJAwAAAA==.Musubi:BAAALgADCgEJAQABLgAECgYJCwAMAAAAAA==.',
Mx='Mxtemlen:BAAALgAECgcJCAABLgAECggJHgAZALkMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJDwAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgYJDQABLgAECgkJIgAiAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgQJDgAMAAAAAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgZPjwAoAQAJAAgJBgZPjwAoAQAAAA==.',
Na='Nachtelf:BAABLgAECn87AAIIAAkJJiEUCADmAgAIAAkJJiEUCADmAgAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nannysham:BAAALgAECggJDgAAAA==.Naomí:BAABLgAECn8cAAIRAAYJ0wymkgAzAQARAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn80AAIJAAkJqyJLBwAiAwAJAAkJqyJLBwAiAwAAAA==.Natherel:BAAALgAECgUJDgAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAAALgAFFAEJAQABLgAFFAcJGAAhAAUXAA==.',
Ne='Newander:BAABLgAECn8qAAIOAAkJJhBkPgBeAQAOAAkJJhBkPgBeAQAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJDAAAAA==.Nirra:BAAALgAECgMJAwAAAA==.',
No='Nonphatmilk:BAAALgAECgMJCAAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMcAAkJmhJKOgDfAQAcAAkJmhJKOgDfAQAkAAEJGxJ6RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCB93NQAKAgAJAAgJCB93NQAKAgAAAA==.',
Og='Ograskygazer:BAAALgAECgUJDgAAAA==.',
Om='Omee:BAABLgAECn8cAAMEAAkJeBYWDwDcAQAEAAgJIhkWDwDcAQAFAAYJ5go6cgD4AAAAAA==.Omy:BAABLgAECn8gAAIJAAcJzARo9AARAQAJAAcJzARo9AARAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAAALgAFFAEJAQABLgAFFAQJCQAJAAIPAA==.Oralena:BAAALgAECgUJEgAAAA==.Orioncheats:BAABLgAECn8pAAIcAAkJqBjfMAABAgAcAAkJqBjfMAABAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAMAAAAAA==.',
Ox='Oxygën:BAAALgAECgQJCAAAAA==.',
Pa='Paladingbat:BAABLgAECn8WAAIZAAgJjyI+BQAKAwAZAAgJjyI+BQAKAwAAAA==.Pallygoboom:BAAALgADCgUJBQABLgAECgYJDgAMAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgYJEAAAAA==.',
Pe='Ped:BAABLgAECn8sAAMaAAkJ4Bw+CQByAgAaAAkJ4Bw+CQByAgAiAAEJ2AHbdgAXAAAAAA==.Peon:BAAALgAECgUJBQAAAA==.',
Ph='Pharune:BAABLgAECn8lAAIoAAgJDRFpEwBbAQAoAAgJDRFpEwBbAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8bAAIJAAcJGBXWZgB4AQAJAAcJGBXWZgB4AQAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAECggJBwAMAAAAAA==.Picklebob:BAAALgAECggJBwAAAA==.Pickleboe:BAAALgAECgUJBQABLgAECggJBwAMAAAAAA==.Picklebosh:BAAALgAECgMJBAABLgAECggJBwAMAAAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgcJBwAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgIJAgABLgAECggJEgAMAAAAAA==.Ponky:BAABLgAECn8cAAIjAAkJKhEGHACdAQAjAAkJKhEGHACdAQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8HAAIOAAMJghS3KwDNAAAOAAMJghS3KwDNAAABLgAFFAgJIwAhAGAfAA==.',
Pr='Precious:BAACLgAFFH8TAAIhAAYJzxNrBQCRAQAhAAYJzxNrBQCRAQAuAAQKfz8ABCEACQkjJBoCAHQDACEACQkjJBoCAHQDAB4ABglwDxs2AGQBACMABAkxE9pCALgAAAEuAAUUBwkYACEABRcA.',
['Pä']='Pängari:BAAALgADCggJDwABLgAECggJIQAdAFANAA==.',
Qu='Quattro:BAAALgAECgkJEwAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn8tAAMDAAgJKhp+GgDYAQADAAgJDBp+GgDYAQALAAEJihV/TwA7AAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8UAAIaAAcJzBd3GgCYAQAaAAcJzBd3GgCYAQABLgAECgkJKgAOACYQAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8YAAIeAAcJ9AqsKgA2AQAeAAcJ9AqsKgA2AQAAAA==.',
Re='Rehum:BAAALgAECgQJDgAAAA==.Remagtrepxe:BAAALgADCgMJBQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCAAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8iAAMgAAgJ9wxOEQA6AQAgAAcJeg5OEQA6AQATAAUJzQXIdgC2AAAAAA==.Revèndreth:BAAALgAECgEJAQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgIJAgAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn8wAAIjAAkJIg90GAC+AQAjAAkJIg90GAC+AQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAAALgAECgYJEQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMcAAkJEBtfLAATAgAcAAkJ5RpfLAATAgAnAAYJrhWxCABaAQAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8XAAIYAAYJzg8LDAAaAQAYAAYJzg8LDAAaAQAAAA==.Roryn:BAACLgAFFH8FAAICAAIJQBGqWgCeAAACAAIJQBGqWgCeAAAuAAQKfz4AAgIACQm5JDgDAEkDAAIACQm5JDgDAEkDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAECgkJDwAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAYJJAAOAFokAA==.Rugiia:BAACLgAFFH8kAAIOAAYJWiR0AgCFAgAOAAYJWiR0AgCFAgAuAAQKfz4AAw4ACQmWJkEAAOMDAA4ACQmWJkEAAOMDAA0ABAlfJeASADgBAAAA.Rugiian:BAAALgAFFAMJAwABLgAFFAYJJAAOAFokAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8YAAIRAAgJngnTYgBJAQARAAgJngnTYgBJAQAAAA==.Ryuka:BAABLgAECn8VAAIoAAkJNQgBHAABAQAoAAkJNQgBHAABAQAAAA==.',
Sa='Sabindeus:BAAALgAECggJAQAAAA==.Samyria:BAAALgAECgMJBwAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8dAAQaAAgJGBHwKAAsAQAaAAcJlg7wKAAsAQAiAAUJBgoYWACBAAAKAAEJgAH5mQAYAAAAAA==.Saucy:BAAALgAECgUJCQAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAMAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8jAAIeAAgJ8BOVGwCuAQAeAAgJ8BOVGwCuAQAAAA==.Seric:BAABLgAECn8hAAIdAAgJUA1gGAA4AQAdAAgJUA1gGAA4AQAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgcJGgAVAMwbAA==.',
Sh='Shadowdancèr:BAAALgAECgYJEgAAAA==.Shadowlocke:BAAALgADCggJDwAAAA==.Shamquen:BAAALgAECggJCwAAAA==.Shanair:BAACLgAFFH8LAAIGAAMJCxmlAwC7AAAGAAMJCxmlAwC7AAAuAAQKfzYAAwYACQnHIrMCAPACAAYACQmuIrMCAPACAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAQJDQABAOEHAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBAAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgIJAgAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAQJCgAdAEoYAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMhAAYJvhFAMAAeAQAhAAUJiBBAMAAeAQAeAAUJfQ+IQwCZAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgUJBQAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgQJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8mAAIJAAkJoA56XgCMAQAJAAkJoA56XgCMAQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgIJAgAAAA==.Solnar:BAABLgAECn8eAAQZAAgJuQzfKwByAQAZAAgJuQzfKwByAQABAAYJQBPrHwDLAAACAAEJYBZeKgE8AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJBwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAMAAAAAA==.Splashdaddy:BAACLgAFFH8GAAITAAMJFiWYFwBCAQATAAMJFiWYFwBCAQAuAAQKfyIAAhMACAlTJIAHAPwCABMACAlTJIAHAPwCAAEuAAMKBgkGAAwAAAAA.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgQJCQAAAA==.',
St='Staks:BAAALgADCgQJBAAAAA==.Starii:BAABLgAECn8aAAITAAcJQwepWQD4AAATAAcJQwepWQD4AAAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgADCgQJBAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvancura:BAAALgAECgIJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8cAAIoAAYJPCLjCgDcAQAoAAYJPCLjCgDcAQAAAA==.',
Ta='Taea:BAAALgADCgIJAgABLgAECgYJHAAOAHshAA==.Taeus:BAACLgAFFH8JAAIJAAQJAg/5QAA6AQAJAAQJAg/5QAA6AQAuAAQKfxcAAgkACAkVGOBeAB4CAAkACAkVGOBeAB4CAAAA.Taintedkoma:BAAALgAECgcJCAAAAA==.Taladiir:BAAALgAECgMJBAAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgUJDAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIdAAkJoiHMBgBiAgAdAAkJoiHMBgBiAgAAAA==.Tayblr:BAABLgAECn8aAAIIAAYJ/wGzrQCEAAAIAAYJ/wGzrQCEAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Temajin:BAAALgAECgYJDgAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAAALgAECgUJEgAAAA==.Teron:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAAALgAECgcJDwAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn8vAAIIAAgJSiDAFgBdAgAIAAgJSiDAFgBdAgAAAA==.Thetimelord:BAAALgAECgUJBgAAAA==.Thewarrior:BAAALgAECgcJDgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8kAAICAAgJVRXNSwD/AQACAAgJVRXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJBQAAAA==.Torrey:BAABLgAECn8vAAIWAAkJ6w+sCQCFAQAWAAkJ6w+sCQCFAQAAAA==.',
Tr='Tradd:BAABLgAECn8bAAIhAAgJ6x0xCwB0AgAhAAgJ6x0xCwB0AgAAAA==.Trigg:BAAALgAECgUJBQABLgAECgkJKwAFADEgAA==.Tristyana:BAABLgAECn83AAIIAAkJYh2uDACwAgAIAAkJYh2uDACwAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn83AAMaAAkJZCWEAQBFAwAaAAkJZCWEAQBFAwAiAAcJgxZEIwCZAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJNwAaAGQlAA==.',
Ty='Tylurien:BAABLgAECn8lAAIZAAgJoSK3BgDpAgAZAAgJoSK3BgDpAgAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Ul='Ulangi:BAAALgADCgIJAgAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn8dAAISAAcJ2gqJDwAFAQASAAcJ2gqJDwAFAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valkoinen:BAABLgAECn83AAIbAAYJGA6DGQABAQAbAAYJGA6DGQABAQAAAA==.Valora:BAABLgAECn87AAQhAAkJZB3XCQCNAgAhAAkJ8RrXCQCNAgAeAAcJYx0/GADMAQAjAAEJcheJXgBAAAAAAA==.Valoria:BAAALgAECgQJDAAAAA==.Vanille:BAAALgAECgUJEQAAAA==.Vargen:BAABLgAECn8ZAAImAAcJmRd0GQCBAQAmAAcJmRd0GQCBAQAAAA==.Varonika:BAAALgAECgUJEgAAAA==.Vayla:BAABLgAECn8qAAIdAAkJZBiEEACeAQAdAAkJZBiEEACeAQAAAA==.',
Ve='Vee:BAAALgAECgEJAgABLgAECggJFAAFAE8UAA==.Veld:BAAALgAECggJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJgAcAAMeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8eAAICAAYJQAq9pADzAAACAAYJQAq9pADzAAAAAA==.',
Vo='Voidofdeath:BAAALgAECgUJDAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn8uAAIOAAkJEwM+WwDtAAAOAAkJEwM+WwDtAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAABLgAECn8qAAIJAAkJPx+QEQDCAgAJAAkJPx+QEQDCAgAAAA==.Wargrimm:BAABLgAECn8kAAIUAAgJvh30DgA+AgAUAAgJvh30DgA+AgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIZAAQJISZwCgCyAQAZAAQJISZwCgCyAQAuAAQKf00AAxkACQmfJhIAAPgDABkACQmfJhIAAPgDAAIABgloHrJKAKoBAAAA.',
We='Webin:BAAALgAECgEJBQAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIaAAgJRR+EEQBtAgAaAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQAPAO8WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQAPAO8WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQAPAO8WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQAPAO8WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQAPAO8WAA==.Whizpa:BAABLgAECn8dAAIPAAkJ7xYdEAAaAgAPAAkJ7xYdEAAaAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQAPAO8WAA==.',
Wi='Wickerchickn:BAABLgAECn8XAAIoAAgJHBR7FABOAQAoAAgJHBR7FABOAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQAPAO8WAA==.Wilshammy:BAAALgADCggJCAAAAA==.Wispy:BAAALgAECgYJCwAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAAALgAECggJDgAAAA==.Wrathbourne:BAAALgAECgYJDQABLgAECggJDgAMAAAAAA==.Wrathchoi:BAAALgAECgYJCwAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECggJDgAMAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8fAAMIAAYJGiGSMwDhAQAIAAYJpR6SMwDhAQAGAAYJ5R08GQCdAQAAAA==.Xilo:BAAALgAECgkJCAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAMAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEAAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8VAAIJAAgJWBirQwDXAQAJAAgJWBirQwDXAQAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAMAAAAAA==.Zirfireballs:BAAALgADCgUJCgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJFwAAAA==.Zorvoth:BAAALgAECgcJBwAAAA==.',
Zu='Zurazaee:BAAALgAECgUJEgAAAA==.',
['År']='Årtêmis:BAAALgAECgYJCAAAAA==.',
['Él']='Élle:BAAALgAECgMJBQAAAA==.',
['Ér']='Éric:BAABLgAECn86AAIoAAkJ8RmEBQBkAgAoAAkJ8RmEBQBkAgAAAA==.',
['Ïr']='Ïridescent:BAAALgAECgQJBAAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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
