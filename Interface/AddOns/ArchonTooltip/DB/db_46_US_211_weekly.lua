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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Druid-Balance','Rogue-Assassination','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Evoker-Preservation','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Monk-Mistweaver','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-06-07',data={Ac='Achooe:BAABLgAECn8tAAMBAAkJsQpJGwAxAQABAAkJsQpJGwAxAQACAAEJJgJTugEZAAAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJBwAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxvGBwCfAgAGAAkJJxvGBwCfAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBCDWADOAQAJAAkJQBCDWADOAQAAAA==.Agathorz:BAAALgAECgEJAgAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBlFLADtAAADAAMJgBlFLADtAAAuAAQKfzcAAwMACQnlJCIDADcDAAMACQnlJCIDADcDAAsABgn0EOgsAA4BAAAA.Allei:BAAALgAECgYJCQABLgAFFAQJDgAMALgJAA==.Alyndrya:BAABLgAECn8oAAQEAAkJSxfqEAAMAgAEAAkJ1xbqEAAMAgAFAAYJvxJkfAAcAQANAAEJkg3NNAAoAAAAAA==.Alyndrys:BAABLgAECn8iAAIOAAcJmhN2FQBeAQAOAAcJmhN2FQBeAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNROMNwDeAQAFAAkJNROMNwDeAQAAAA==.Amithralia:BAABLgAECn8tAAIMAAkJmB8wCQAfAwAMAAkJmB8wCQAfAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SKnGwDGAQAPAAYJ0SKnGwDGAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8VAAIQAAgJjxakQQDRAQAQAAgJjxakQQDRAQAAAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAgJKgAMADseAA==.Aokuma:BAACLgAFFH8qAAIMAAgJOx7xAQAgAwAMAAgJOx7xAQAgAwAuAAQKfywAAwwACQlPJN8GAEIDAAwACQlPJN8GAEIDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8oAAISAAgJug7/CQCRAQASAAgJug7/CQCRAQAAAA==.',
Aq='Aquaten:BAABLgAECn8gAAIGAAgJahTJFQDyAQAGAAgJahTJFQDyAQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRDMZwD1AAAMAAgJJg7MZwD1AAARAAYJIBYGTADPAAAAAA==.Arcafrost:BAAALgAECgkJAQAAAA==.Arceus:BAAALgAECgUJDQAAAA==.Archaon:BAABLgAECn8pAAMQAAgJoA/qXQCAAQAQAAgJoA/qXQCAAQATAAEJAAD5TgAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFgAUAHUUAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9GAAMUAAkJpib/AQBrAwAUAAkJpib/AQBrAwAVAAYJIyXvHQDmAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEgAAAA==.Asmódeus:BAABLgAECn8cAAQWAAgJoQ73DQBTAQAWAAYJWw73DQBTAQAQAAgJCgoQeQBCAQATAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgADCgMJBgAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAABLgAECn8qAAIJAAkJaBjbLQBcAgAJAAkJaBjbLQBcAgAAAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMXAAYJJxUjNABAAQAXAAYJJxUjNABAAQAYAAQJvBZdQgDzAAABLgAECgcJEwAZAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8gAAIaAAgJyQSpKQDcAAAaAAgJyQSpKQDcAAAAAA==.Baelthas:BAAALgADCgcJCAAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAACLgAFFH8HAAIFAAMJFiDvQQAUAQAFAAMJFiDvQQAUAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8vAAISAAkJ7RxVAgCvAgASAAkJ7RxVAgCvAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgEJAQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8hAAIbAAgJaQy/dQBxAQAbAAgJaQy/dQBxAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8aAAIMAAkJkxIwKAAIAgAMAAkJkxIwKAAIAgAAAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8bAAIEAAgJ4wytIwBJAQAEAAgJ4wytIwBJAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn86AAINAAgJvSFDAwCjAgANAAgJvSFDAwCjAgAAAA==.Blegh:BAACLgAFFH8OAAMcAAUJaRjzIwAuAQAcAAUJGhbzIwAuAQAdAAEJlxUaDABNAAAuAAQKfyMAAx0ACQnCHqcKADECAB0ABwnHHqcKADECABwABwl/GygfAMoBAAAA.Blueflu:BAAALgAECgQJBAAAAA==.Bluegrass:BAABLgAECn9NAAIOAAkJnSTIAABeAwAOAAkJnSTIAABeAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMeAAgJxAnuRABkAQAeAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgAFFAEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxhMPAADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAZAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8NAAIIAAQJgAzpRAATAQAIAAQJgAzpRAATAQAuAAQKfxcAAggACAmpEqpNAK4BAAgACAmpEqpNAK4BAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8IAAIJAAYJUxd0RwBNAQAJAAYJUxd0RwBNAQABLgAFFAcJGwAfACgeAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8bAAIFAAgJ1xmUTADCAQAFAAgJ1xmUTADCAQAAAA==.Caladelm:BAABLgAECn8WAAICAAcJphG2igBRAQACAAcJphG2igBRAQAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8jAAIbAAgJAg0edAB0AQAbAAgJAg0edAB0AQAAAA==.Carlarae:BAABLgAECn8WAAIJAAYJOQTS8wC3AAAJAAYJOQTS8wC3AAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih3yQwBWAQAJAAQJih3yQwBWAQAuAAQKfxwAAgkACQksIUMSAOgCAAkACQksIUMSAOgCAAAA.Cegeo:BAABLgAECn9IAAITAAkJihlgAwBXAgATAAkJihlgAwBXAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9UAAMDAAkJnSMDBgD6AgADAAkJnSMDBgD6AgALAAEJ0g4WcQAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhP0iwCaAAAQAAIJjhP0iwCaAAAuAAQKfyMAAxAABwncH3owABACABAABwncH3owABACABYABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAgAAAA==.',
Ci='Ciennajewel:BAABLgAECn8VAAIgAAgJdRoHEgBEAgAgAAgJdRoHEgBEAgAAAA==.Cirdle:BAABLgAECn8lAAMIAAgJtg/7UAClAQAIAAgJtg/7UAClAQAHAAMJIwZOKQBoAAAAAA==.Cirona:BAABLgAECn8dAAIMAAYJeyH8IAA3AgAMAAYJeyH8IAA3AgABLgAECgcJCgAZAAAAAA==.',
Cl='Clausewitz:BAABLgAECn8ZAAIaAAkJ7goxHQBAAQAaAAkJ7goxHQBAAQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8EAAIQAAIJ0BIEkgCSAAAQAAIJ0BIEkgCSAAAuAAQKfyAAAhAACQk+HFAhAFcCABAACQk+HFAhAFcCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAZAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIVAAgJ7gILWADOAAAVAAgJ7gILWADOAAAAAA==.Creamtastic:BAAALgAECgcJBwABLgAECggJHAAgAEMTAA==.Creamyweamy:BAABLgAECn8cAAIgAAgJQxNzIwCcAQAgAAgJQxNzIwCcAQAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA1VoQA1AQAJAAcJQA1VoQA1AQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgEJAwAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8eAAMVAAkJ6BTaGwD3AQAVAAkJ6BTaGwD3AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8nAAIJAAgJpAgBlABMAQAJAAgJpAgBlABMAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8WAAIjAAYJVCAlCgA7AgAjAAYJVCAlCgA7AgABLgAFFAkJLwAYAAkgAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAEJAQABLgAFFAgJKQAYAK8fAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yQRBADCAgAjAAcJ6yQRBADCAgAuAAQKf4wAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAZAAAAAA==.Daggonet:BAABLgAECn8eAAIbAAkJJyDTDAAAAwAbAAkJJyDTDAAAAwAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAVAAQJzAfqZwCjAAAAAA==.Darayia:BAAALgAECgEJAgAAAA==.Darkcarnival:BAABLgAECn8vAAIQAAkJQBpXHgBoAgAQAAkJQBpXHgBoAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAQJDQAeAIAbAA==.Darkknightx:BAACLgAFFH8HAAIDAAQJgAoAJwAJAQADAAQJgAoAJwAJAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgAECgcJDAABLgAECggJGQAUANQOAA==.Darthraider:BAABLgAECn8cAAIbAAcJEA+MigBIAQAbAAcJEA+MigBIAQAAAA==.Dasnotgood:BAABLgAECn8ZAAMOAAcJuh3fDQDIAQAOAAYJUB/fDQDIAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQVAAgJxwdFRwAIAQAVAAgJxwdFRwAIAQAUAAEJowGnqgAhAAAiAAEJeAGbQgAeAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgQJBAAAAA==.',
De='Deathspeaker:BAAALgADCgEJAQABLgAECggJIwAfABMTAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8ZAAIFAAkJyhQ1NQDnAQAFAAkJyhQ1NQDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAABLgAECn8aAAITAAcJtxJuDgBJAQATAAcJtxJuDgBJAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8qAAMgAAgJ+xGmJgCEAQAgAAgJ+xGmJgCEAQAXAAcJ3hCALwBaAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8iAAIRAAkJAhVUGwDkAQARAAkJAhVUGwDkAQAAAA==.Desdemona:BAABLgAECn8mAAIBAAgJACGuBwBWAgABAAgJACGuBwBWAgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8HAAIIAAQJuQxqQgAZAQAIAAQJuQxqQgAZAQAuAAQKfxoAAwgACQlrGhIaAH4CAAgACQlrGhIaAH4CAAcAAglsA1dDABoAAAAA.',
Di='Dianimal:BAABLgAECn8iAAIRAAgJqAdmPQANAQARAAgJqAdmPQANAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEAAZAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8qAAMeAAgJbiRVBQA0AwAeAAgJbiRVBQA0AwACAAgJmSLSGAClAgAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIbAAUJ0CF5RgBXAQAbAAUJ0CF5RgBXAQAuAAQKf0AAAhsACQl4JlwGAEIDABsACQl4JlwGAEIDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8FAAICAAIJzRD6gQCUAAACAAIJzRD6gQCUAAAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AWVHAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBJDbACMAQACAAkJIBJDbACMAQAAAA==.',
Dr='Draaka:BAAALgADCgYJBgAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGQAFAMoUAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xkUHQAeAgAjAAkJ6xkUHQAeAgAAAA==.Driftyshaman:BAABLgAECn8lAAIVAAcJlwrtSwD3AAAVAAcJlwrtSwD3AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn8cAAIbAAgJuwjpigBHAQAbAAgJuwjpigBHAQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAAALgAECgYJBgABLgAECggJIQAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8tAAIiAAkJtA2kDwCsAQAiAAkJtA2kDwCsAQAAAA==.',
Dy='Dyamï:BAABLgAECn8xAAIjAAkJyx3lBwASAwAjAAkJyx3lBwASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAABLgAECn8YAAIJAAgJzQWIsAAdAQAJAAgJzQWIsAAdAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8hAAIVAAgJXAqtQgAaAQAVAAgJXAqtQgAaAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAAALgAECgYJEgAAAA==.Ellä:BAAALgAECgYJCQAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxOFNgAzAQAIAAQJGxOFNgAzAQAuAAQKfzgAAggACQmGIpUIAA8DAAgACQmGIpUIAA8DAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Eu='Eukina:BAAALgAECgEJAQAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhEXQgCAAQAMAAcJvhEXQgCAAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8dAAIiAAcJRh4gAQAJAgAiAAcJRh4gAQAJAgAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAECgQJBAABLgAFFAcJHQAiAEYeAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAcJHQAiAEYeAA==.',
Fr='Fredrickk:BAABLgAECn8WAAMUAAcJdRTLPACvAQAUAAcJdRTLPACvAQAVAAQJWwpkdAB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgQJBgABLgAFFAUJEwAUAGUYAA==.Furryphase:BAACLgAFFH8TAAIUAAUJZRhWIABYAQAUAAUJZRhWIABYAQAuAAQKfyQAAxQACQnxHAwNALUCABQACQnxHAwNALUCABUABAlyCZR3AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAcJHQAiAEYeAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAQAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn85AAIUAAkJth5oEgCwAgAUAAkJth5oEgCwAgAAAA==.',
Go='Goatjira:BAAALgAECgMJBAAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAlAGAgAA==.Gripisrdy:BAABLgAECn8vAAMbAAkJyR9xEwDNAgAbAAkJyR9xEwDNAgAmAAMJgRhZMwDCAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyIzAQD0AgAnAAkJkyIzAQD0AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAABLgAECn8ZAAIUAAgJ1A4xRQCMAQAUAAgJ1A4xRQCMAQAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAQAAAA==.Haggrd:BAABLgAECn8bAAICAAgJJh/5IwBsAgACAAgJJh/5IwBsAgAAAA==.Hairyjolene:BAABLgAECn8gAAIIAAgJ2hHlTACxAQAIAAgJ2hHlTACxAQAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJBwAZAAAAAA==.Handsome:BAAALgAFFAIJAgAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAABLgAFFH8GAAIbAAMJ7hIajgDgAAAbAAMJ7hIajgDgAAAAAA==.',
Hi='Highlander:BAAALgAECgEJAQAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxNUkABAAAAFAAEJvxNUkABAAAABLgAFFAgJKgAMADseAA==.Hikarimonk:BAABLgAFFH8NAAIjAAYJBRBiGQCEAQAjAAYJBRBiGQCEAQABLgAFFAgJKgAMADseAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAgJKgAMADseAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgUJDQAZAAAAAA==.Holyblimblam:BAAALgAECgYJEAAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMbAAgJBB4iQgD2AQAbAAgJmB0iQgD2AQAmAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIXAAYJNA2JQgD9AAAXAAYJNA2JQgD9AAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJDwAAAA==.Icyjackets:BAABLgAECn8gAAMbAAgJJg4NdQBzAQAbAAgJJg4NdQBzAQAmAAQJpAV+QwB1AAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAECgEJAQAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA83TQCwAQAIAAkJlA83TQCwAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRcEJADPAQADAAgJBRcEJADPAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn85AAMMAAgJHg7rQwB5AQAMAAgJHg7rQwB5AQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAZAAAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAZAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIVAAYJfg7yVQDVAAAVAAYJfg7yVQDVAAAAAA==.Jessicà:BAAALgAECgEJAQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAgAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8hAAMUAAYJIhYRNgCrAQAUAAYJIhYRNgCrAQAVAAUJfBLGWADMAAAAAA==.Jiwà:BAABLgAFFH8FAAIUAAUJMQK/OwDiAAAUAAUJMQK/OwDiAAABLgAFFAUJEgAXAPkKAA==.Jiwâ:BAACLgAFFH8SAAIXAAUJ+Qp9HAD7AAAXAAUJ+Qp9HAD7AAAuAAQKfzkAAhcACQlGHhAMAIoCABcACQlGHhAMAIoCAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJBwAFABYgAA==.Kahless:BAAALgADCgQJCQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAftQgAyAQADAAkJMAftQgAyAQAAAA==.Kaliyah:BAAALgADCgcJBwAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgADCgkJFgAAAA==.Kavorkyan:BAAALgAECgcJCAAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMlAAkJYCA9EQBTAQAbAAYJ7hpDXQDbAQAlAAcJyB89EQBTAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9MAAIKAAkJKR6qBwCzAgAKAAkJKR6qBwCzAgAAAA==.',
Ki='Kiamara:BAABLgAECn8fAAIQAAgJ9QiFegA/AQAQAAgJ9QiFegA/AQAAAA==.Kinderlin:BAABLgAECn8jAAICAAYJtxSkpAAlAQACAAYJtxSkpAAlAQAAAA==.Kipo:BAAALgAECggJDwAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhZ8NgC3AQAMAAcJbhZ8NgC3AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQdAAgJfRaSDwDiAQAdAAYJNhmSDwDiAQAcAAMJfRSEQgDYAAAfAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgQJBAAAAA==.Lista:BAAALgAECgkJDgABLgAECgkJQAAPAGclAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyUzAQBVAwAGAAkJDiUzAQBVAwAIAAgJlyZiCwDwAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAACLgAFFH8OAAIMAAQJuAlRNADaAAAMAAQJuAlRNADaAAAuAAQKfxQAAgwABwn7FDw2ALgBAAwABwn7FDw2ALgBAAAA.Lorianne:BAACLgAFFH8HAAIUAAIJwRWFXwBzAAAUAAIJwRWFXwBzAAAuAAQKfygAAxQACAmvGGQpAOkBABQACAmvGGQpAOkBABUABQmxC7tWAOoAAAEuAAUUBAkOAAwAuAkA.Lorri:BAAALgADCgQJBQABLgAFFAQJDgAMALgJAA==.',
Lu='Lucianas:BAAALgAECggJEgAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8gAAIIAAgJIh5NGACKAgAIAAgJIh5NGACKAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgEJAQAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh8qCgDnAgAjAAkJqh8qCgDnAgAAAA==.Madameuyen:BAAALgADCgUJBQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRzYHACoAgAJAAkJHRzYHACoAgABLgAFFAQJDwAGAB8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8UAAIgAAcJURtDGwDhAQAgAAcJURtDGwDhAQABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx1TKAA0AgAIAAgJUx1TKAA0AgAAAA==.Malzeth:BAAALgAECgYJBgAAAA==.Marrilyn:BAAALgAFFAEJAgABLgAFFAcJCwAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn8yAAIIAAkJzyBoCgD7AgAIAAkJzyBoCgD7AgAAAA==.Mate:BAAALgAECgQJBwAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJBwAAAA==.Melbeast:BAABLgAECn8cAAIIAAgJ2hs7KwAnAgAIAAgJ2hs7KwAnAgAAAA==.Melorea:BAAALgAECgMJBQAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxC5VgDTAQAJAAkJNhC5VgDTAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMTAAgJpQnZEwAFAQATAAgJpQnZEwAFAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJGgAAAA==.Mignon:BAAALgAECgMJBgAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn89AAIBAAkJcQTaJADiAAABAAkJcQTaJADiAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgUJCQAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Molfise:BAABLgAECn8oAAMKAAgJ0B7QCwBxAgAKAAgJ7x3QCwBxAgAPAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8/AAIgAAkJ4B/nBQAOAwAgAAkJ4B/nBQAOAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8cAAILAAgJ8AXdNQDkAAALAAgJ8AXdNQDkAAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAZAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAeAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgaZrAAjAQAJAAgJBgaZrAAjAQAAAA==.',
Na='Nachtelf:BAABLgAECn9VAAIIAAkJDyKiBgAlAwAIAAkJDyKiBgAlAwAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAUAFYTAA==.Nannysham:BAABLgAECn8WAAIUAAkJVhO9KgAEAgAUAAkJVhO9KgAEAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn9LAAIJAAkJjCNGCQAsAwAJAAkJjCNGCQAsAwAAAA==.Nathel:BAAALgAECgUJBQAAAA==.Natherel:BAABLgAECn8XAAQLAAgJ2QRKPQDHAAALAAcJVgVKPQDHAAADAAUJ5gPkdwCBAAAaAAEJ5QEIVwAhAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8OAAMfAAUJ8AtgGAD7AAAfAAQJKg1gGAD7AAAcAAQJgAp5QgCxAAAuAAQKfxwAAx8ACAnZFKsNAO4BAB8ABwnWFqsNAO4BABwABwm5GBMnAKABAAEuAAUUCAkpABgArx8A.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRMFLADxAQAMAAkJaRMFLADxAQABLgAECggJIQAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgMJBgAAAA==.',
No='Nonphatmilk:BAAALgAECgYJDAAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMbAAkJmxIWTQDVAQAbAAkJmxIWTQDVAQAmAAEJGxJ6RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR9NSQD5AQAJAAgJCR9NSQD5AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8aAAIMAAgJQAakaADyAAAMAAgJQAakaADyAAAAAA==.',
Om='Omee:BAABLgAECn8hAAMEAAkJUholDwAlAgAEAAkJUholDwAlAgAFAAYJ+QtEhgAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w6ujwBUAQAJAAcJ4w6ujwBUAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAAALgAFFAEJBAABLgAFFAQJEQAJAOwVAA==.Oralena:BAABLgAECn8gAAIIAAgJXghxbQBbAQAIAAgJXghxbQBbAQAAAA==.Orioncheats:BAABLgAECn9BAAIbAAkJzxuJJwBdAgAbAAkJzxuJJwBdAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAZAAAAAA==.',
Ox='Oxygën:BAABLgAECn8cAAIJAAgJaAXdsAAdAQAJAAgJaAXdsAAdAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8NAAIeAAQJgBuWGgBAAQAeAAQJgBuWGgBAAQAuAAQKfxwAAh4ACAnfIlEHAA8DAB4ACAnfIlEHAA8DAAAA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAZAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9HAAMPAAkJQR/+BwDAAgAPAAkJQR/+BwDAAgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8UAAIDAAcJKxpkIQDgAQADAAcJKxpkIQDgAQAAAA==.',
Ph='Pharune:BAABLgAECn8vAAIkAAkJFRJYFACkAQAkAAkJFRJYFACkAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8rAAIJAAkJoBbKNgA3AgAJAAkJoBbKNgA3AgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJCgAVAJAaAA==.Picklebob:BAAALgAECggJBwABLgAFFAQJCgAVAJAaAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJCgAVAJAaAA==.Picklebosh:BAABLgAFFH8KAAIVAAQJkBpXFwBNAQAVAAQJkBpXFwBNAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Ponky:BAABLgAECn8cAAIXAAkJKhF5JwCKAQAXAAkJKhF5JwCKAQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8MAAIMAAMJghTJPAC3AAAMAAMJghTJPAC3AAABLgAFFAkJLwAYAAkgAA==.',
Pr='Precious:BAACLgAFFH8aAAIYAAcJ8xOTDQAeAgAYAAcJ8xOTDQAeAgAuAAQKf0EABBgACQkjJDwDAG0DABgACQkjJDwDAG0DACAABglwDxs2AGQBABcABAkvE2BUALcAAAEuAAUUCAkpABgArx8A.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAaAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIdAAkJXgvIDwAFAQAdAAkJXgvIDwAFAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAABLgAECn85AAMDAAgJFR6WEQBjAgADAAgJ+B2WEQBjAgALAAEJihUQbAA7AAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8hAAMPAAgJaRyQEQAtAgAPAAgJaRyQEQAtAgAjAAIJpw0fkwBYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJBAAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8pAAIgAAgJuQ05KgBqAQAgAAgJuQ05KgBqAQAAAA==.Raziel:BAAALgADCgkJCQAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Rehum:BAABLgAECn8UAAICAAYJPgiD6QDHAAACAAYJPgiD6QDHAAAAAA==.Remagtrepxe:BAAALgADCgMJBQABLgAECgcJJQAVAJcKAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8sAAMiAAkJgRBZEwB2AQAiAAcJdhNZEwB2AQAUAAYJ3geZiAC7AAAAAA==.Revèndreth:BAAALgAECgEJAQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgQJBAAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9CAAIXAAkJGRKDHADaAQAXAAkJGRKDHADaAQAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAABLgAECn8XAAIIAAYJlwshcAAXAQAIAAYJlwshcAAXAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMbAAkJERttPQAFAgAbAAkJ5xptPQAFAgAlAAYJrhWxCABaAQAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8iAAIdAAgJBQ8ECgB4AQAdAAgJBQ8ECgB4AQAAAA==.Roryn:BAACLgAFFH8IAAICAAMJoRRwYgDYAAACAAMJoRRwYgDYAAAuAAQKf1EAAgIACQkmJqYBAHoDAAIACQkmJqYBAHoDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8GAAIDAAIJrxrZOgCjAAADAAIJrxrZOgCjAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAgJLwAMACIiAA==.Rugiia:BAACLgAFFH8vAAIMAAgJIiKYAQA3AwAMAAgJIiKYAQA3AwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJcoZAC8BAAAA.Rugiian:BAABLgAFFH8KAAIjAAUJmBukFwCVAQAjAAUJmBukFwCVAQABLgAFFAgJLwAMACIiAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQkSYAB7AQAQAAkJjQkSYAB7AQAAAA==.Ryuka:BAABLgAECn8dAAIkAAkJUwmxJwAIAQAkAAkJUwmxJwAIAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAZAAAAAA==.Samyria:BAABLgAECn8VAAIIAAYJ+Q6hhwAlAQAIAAYJ+Q6hhwAlAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8nAAQjAAkJDAxsOwBtAQAjAAkJDAxsOwBtAQAPAAcJlg7gOAATAQAKAAEJgAH5mQAYAAAAAA==.Saucy:BAABLgAECn8WAAMVAAcJNSHPEwBCAgAVAAcJNSHPEwBCAgAiAAEJAABLRAAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAZAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8nAAIgAAkJ7hIZHwC+AQAgAAkJ7hIZHwC+AQAAAA==.Seric:BAABLgAECn8pAAMaAAkJ8QuUGwBQAQAaAAkJ8QuUGwBQAQADAAQJugTFgQBlAAAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgcJGgAWAM0bAA==.',
Sh='Shadowdancèr:BAABLgAECn8fAAMXAAgJwhZ6HADaAQAXAAgJwhZ6HADaAQAYAAMJ+RGWTgC4AAAAAA==.Shadowlocke:BAAALgAECgUJBQAAAA==.Shadowyisis:BAABLgAECn8VAAIXAAkJyBSoFQAXAgAXAAkJyBSoFQAXAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8PAAIGAAQJHxtSDwA+AQAGAAQJHxtSDwA+AQAuAAQKf0EAAwYACQnQIygCACgDAAYACQm3IygCACgDAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAUJFwABAIgPAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAYJFQAaAH4VAA==.Skybox:BAAALgAECgQJBAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMYAAYJvhFAMAAeAQAYAAUJiBBAMAAeAQAgAAUJfQ+tUACNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8GAAIJAAMJ1gLHiwCxAAAJAAMJ1gLHiwCxAAAuAAQKfzMAAgkACQmtEv5DAAoCAAkACQmtEv5DAAoCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQeAAkJRgyqLQCeAQAeAAkJRgyqLQCeAQABAAYJQBPJKADFAAACAAEJYBaTcgE6AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAZAAAAAA==.Splashdaddy:BAACLgAFFH8QAAIUAAQJ6yIyGQCFAQAUAAQJ6yIyGQCFAQAuAAQKfyQAAhQACQlGJOwGADgDABQACQlGJOwGADgDAAEuAAUUAQkBABkAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgUJCgAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8nAAIUAAgJugfDYgAlAQAUAAgJugfDYgAlAQAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgIJBAAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8pAAIkAAgJOCF0BgCJAgAkAAgJOCF0BgCJAgAAAA==.',
Ta='Taea:BAAALgAECgcJCgAAAA==.Taeus:BAACLgAFFH8RAAIJAAQJ7BXtTgA+AQAJAAQJ7BXtTgA+AQAuAAQKfxkAAgkACQkiGeBeAB4CAAkACQkiGeBeAB4CAAAA.Taintedcure:BAAALgADCgkJCQAAAA==.Taintedkoma:BAAALgAECgcJCAABLgAECggJIAATAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgYJEgAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIaAAkJoiEKCAClAgAaAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AGXyACnAAAIAAgJ/AGXyACnAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgEJAQAAAA==.Temajin:BAABLgAECn8YAAMeAAYJrgtrSAASAQAeAAYJrgtrSAASAQACAAIJvwsVjwEtAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8aAAMfAAgJcyHyBADIAgAfAAgJcyHyBADIAgAcAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA+4kQAUAQAQAAcJQgy4kQAUAQATAAEJChYUNwBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICI9EQC+AgAIAAgJICI9EQC+AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAAALgAECggJEwAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8mAAICAAgJVhXNSwD/AQACAAgJVhXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJBQABLgAECgkJHgAVAFQVAA==.Torrey:BAABLgAECn9EAAINAAkJRhFlCgCtAQANAAkJRhFlCgCtAQAAAA==.',
Tr='Tradd:BAACLgAFFH8JAAIYAAMJ0xnIJQADAQAYAAMJ0xnIJQADAQAuAAQKfyEAAhgACQmLHvEIANwCABgACQmLHvEIANwCAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJBwAFABYgAA==.Tristyana:BAABLgAECn9RAAIIAAkJBB5BEQC+AgAIAAkJBB5BEQC+AgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn9AAAQPAAkJZyWZAgA7AwAPAAkJZyWZAgA7AwAjAAcJgxZEIwCZAQAKAAcJhBGIKwBUAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJQAAPAGclAA==.',
Ty='Tylurien:BAABLgAECn8pAAIeAAkJkyAIBwAUAwAeAAkJkyAIBwAUAwAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn8zAAITAAgJOg4dDgBOAQATAAgJOg4dDgBOAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9QAAIfAAgJFwx2FgBhAQAfAAgJFwx2FgBhAQAAAA==.Valora:BAABLgAECn9UAAQYAAkJZB2DDgB8AgAYAAkJ8RqDDgB8AgAXAAkJOBUFEgA9AgAgAAcJYx2yHwC5AQAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8YAAIMAAgJ8AVFcADbAAAMAAgJ8AVFcADbAAAAAA==.Vargen:BAABLgAECn8fAAIoAAgJYBhbFwDWAQAoAAgJYBhbFwDWAQAAAA==.Varonika:BAAALgAECgUJEgAAAA==.Vayla:BAABLgAECn8zAAIaAAkJ3htXCABrAgAaAAkJ3htXCABrAgAAAA==.',
Ve='Vee:BAAALgAECgEJBAABLgAECgkJGQAFAMoUAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAbAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8tAAICAAgJ1AuYjQBMAQACAAgJ1AuYjQBMAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTAO/aADyAAAMAAkJTAO/aADyAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjwwwfwDVAAAJAAMJjwwwfwDVAAAuAAQKfyoAAgkACQk+H/4bAK0CAAkACQk+H/4bAK0CAAAA.Wargrimm:BAABLgAECn8uAAIVAAkJyR5dCgCxAgAVAAkJyR5dCgCxAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIeAAQJISarEQCaAQAeAAQJISarEQCaAQAuAAQKf2cAAx4ACQnQJhIAAPgDAB4ACQnQJhIAAPgDAAIACQkSICMPAOQCAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQARAO4WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Whizpa:BAABLgAECn8dAAIRAAkJ7hYoFgAUAgARAAkJ7hYoFgAUAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8ZAAIkAAkJThQ7FQCbAQAkAAkJThQ7FQCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQARAO4WAA==.Wilshammy:BAAALgAECgQJBwAAAA==.Wispy:BAABLgAECn8ZAAIVAAcJQxEEOQBFAQAVAAcJQxEEOQBFAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAABLgAECn8VAAMIAAkJXBQ3MAASAgAIAAkJXBQ3MAASAgAGAAEJ6wYOYgAzAAAAAA==.Wrathbourne:BAAALgAECgYJEgABLgAECgkJFQAIAFwUAA==.Wrathchoi:BAAALgAECgYJDAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJFQAIAFwUAA==.',
Xa='Xantchaa:BAAALgAECgEJAQABLgAECgkJGgAJAI0bAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8pAAMIAAgJux6SMwDhAQAIAAgJzRySMwDhAQAGAAYJxB9yHQCtAQAAAA==.Xilo:BAAALgAECgkJEAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAZAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAEJAQAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgADCgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgMJAwAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8aAAIJAAkJjRsbMQBOAgAJAAkJjRsbMQBOAgAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAZAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8UAAImAAcJcSAeDQAuAgAmAAcJcSAeDQAuAgAAAA==.',
Zu='Zurazaee:BAABLgAECn8gAAIgAAgJGRg6FAArAgAgAAgJGRg6FAArAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAABLgAECn9UAAIkAAkJFRtIBwB0AgAkAAkJFRtIBwB0AgAAAA==.',
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
