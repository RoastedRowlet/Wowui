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

local lookup = {'Druid-Feral','Druid-Guardian','Druid-Restoration','DeathKnight-Unholy','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','DemonHunter-Havoc','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Monk-Brewmaster','Paladin-Protection','Paladin-Holy','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','Shaman-Enhancement','Mage-Fire','Druid-Balance','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8cAAQBAAcJjxBFFABCAQABAAcJ9g9FFABCAQACAAYJUgsXMwCUAAADAAEJJQf12gAnAAAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8IAAIEAAQJ6hDrTwAsAQAEAAQJ6hDrTwAsAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJBQAAAA==.Aethelwold:BAAALgADCgQJBAAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJCAAFAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAAALgAECgUJEQAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIGAAYJfhr1NgBFAQAGAAYJfhr1NgBFAQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAGAH4aAA==.',
Al='Alariel:BAABLgAECn8nAAIHAAkJmxiBJQAZAgAHAAkJmxiBJQAZAgABLgAFFAQJCwAIAGMZAA==.Albesuri:BAAALgAECgUJBQABLgAFFAgJGQAHAPsXAA==.Albskin:BAAALgADCgIJAgAAAA==.Alcazar:BAABLgAECn8dAAMHAAcJ2BopNQDRAQAHAAcJ2BopNQDRAQAJAAEJAAAeaQAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAIKAAgJGwj8HwB+AQAKAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJGwAKAPwYAA==.Alliar:BAABLgAECn8nAAMLAAkJxBxAHwAoAgALAAkJxBxAHwAoAgAMAAIJLgnieABOAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAFAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJGwAKAPwYAA==.',
Am='Amalek:BAAALgADCgIJAgAAAA==.Amerha:BAAALgAFFAEJAQAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAACLgAFFH8HAAINAAMJAh5aNwAeAQANAAMJAh5aNwAeAQAuAAQKfxwAAg0ACAnRIUomAEkCAA0ACAnRIUomAEkCAAAA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8XAAIDAAQJURFfbwDFAAADAAQJURFfbwDFAAAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8UAAIJAAcJuhWVFwCRAQAJAAcJuhWVFwCRAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJNwAOAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8YAAIPAAUJ5x3uMQBhAQAPAAUJ5x3uMQBhAQAuAAQKfy0AAg8ACAl5IvAlANsCAA8ACAl5IvAlANsCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8bAAIMAAkJZhXYGADwAQAMAAkJZhXYGADwAQABLgAECgEJAQAFAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAFAAAAAA==.Atrell:BAABLgAECn8eAAINAAkJrRihOAD/AQANAAkJrRihOAD/AQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgADCgcJCAABLgAFFAUJFAAQAMYeAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJCQAAAA==.Balrock:BAAALgADCgkJDQAAAA==.Balthromaw:BAABLgAECn8wAAIOAAgJShvOKwASAgAOAAgJShvOKwASAgAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgEJAQAAAA==.Barqs:BAAALgAECgkJAgAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSJtIQAaAgADAAYJGSJtIQAaAgAAAA==.Bartahh:BAAALgAECggJEgAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCgABLgAECgkJKwAGAPwcAA==.Beardwaffle:BAABLgAECn8rAAIGAAkJ/ByDDgBoAgAGAAkJ/ByDDgBoAgAAAA==.Bearlando:BAAALgAFFAMJAwABLgAFFAYJFgAMAPgaAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgADCgkJFAAAAA==.Belfdelphine:BAABLgAECn8UAAQNAAUJfh8ThwBBAQANAAUJfh8ThwBBAQARAAUJyw9XKgC5AAASAAIJygX/nAAsAAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIPAAMJ1wQIeQCuAAAPAAMJ1wQIeQCuAAAuAAQKfxQAAg8ABwkyEx20AHYBAA8ABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8RAAMTAAQJ9RzmCwBCAQATAAQJuxjmCwBCAQAGAAQJMhruFQA2AQAuAAQKfygABAYACAkOJC0UAKwCAAYACAl0Iy0UAKwCABQAAwmQJMgcACUBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAIAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIHAAkJFBj6KAAIAgAHAAkJFBj6KAAIAgAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodhoundss:BAABLgAECn8lAAIGAAkJHxjWHwDMAQAGAAkJHxjWHwDMAQAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBUrCgCVAQAVAAgJFBUrCgCVAQAAAA==.',
Bo='Bob:BAACLgAFFH8TAAIHAAYJnBR4CQCTAQAHAAYJnBR4CQCTAQAuAAQKfyYAAgcACQk+IdoIAEIDAAcACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8lAAILAAgJdRjGJAADAgALAAgJdRjGJAADAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAECggJEgAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAECgIJAgAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8XAAIGAAgJGgvRNABQAQAGAAgJGgvRNABQAQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8HAAIWAAIJihxOGQCfAAAWAAIJihxOGQCfAAAAAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Buu:BAAALgAFFAEJAQAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Caliginosity:BAABLgAECn8YAAIXAAcJeRc2DAD/AQAXAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJCAAAAA==.Cesard:BAABLgAECn8fAAICAAgJfh05BwBOAgACAAgJfh05BwBOAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJBgAAAA==.Chillingsly:BAAALgADCgEJAQABLgAFFAMJBQAYAIIRAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIGAAkJZB29DgBlAgAGAAkJZB29DgBlAgAAAA==.Chrondeezee:BAAALgAECgYJDAAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBAAAAA==.Circledebull:BAAALgADCgIJAgAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAIRAAMJ5hP/BwDKAAARAAMJ5hP/BwDKAAAuAAQKfxwAAhEACQm7GkwIAFUCABEACQm7GkwIAFUCAAAA.Condemnation:BAACLgAFFH8HAAIZAAMJdQx6JgDLAAAZAAMJdQx6JgDLAAAuAAQKfzUAAxkACQmjGjcNAG4CABkACQkrFjcNAG4CABoACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJCgAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAFAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAFAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8YAAISAAkJ9QobLQCEAQASAAkJ9QobLQCEAQAAAA==.',
Cr='Crayak:BAACLgAFFH8LAAIJAAQJGRsFBwBXAQAJAAQJGRsFBwBXAQAuAAQKfy8AAwkACQmVIogDAPQCAAkACQmVIogDAPQCAAcABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgcJHQAHANgaAA==.Crossbones:BAABLgAECn8kAAMbAAgJuRfTMADvAQAbAAgJthfTMADvAQAcAAQJWA9fNADkAAAAAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8JAAIHAAUJ8A+lPAAIAQAHAAUJ8A+lPAAIAQAuAAQKfxwAAgcACAltGqUyAC8CAAcACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8iAAIMAAgJQhUOJQCTAQAMAAgJQhUOJQCTAQAAAA==.Curbstomped:BAAALgAECgcJCAAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIEAAMJ2hFUdgDiAAAEAAMJ2hFUdgDiAAAuAAQKfyQAAwQACQkVIjcRAMMCAAQACQkMIjcRAMMCAB0ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8SAAIUAAQJWCQkBgCYAQAUAAQJWCQkBgCYAQAuAAQKfzgABBQACAlPJR0EAMkCABQACAnKJB0EAMkCAAYABwlIHZUdAGICABMABgnyHE4iACQBAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJBAAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAOAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8QAAIPAAQJbhMwRgA6AQAPAAQJbhMwRgA6AQAuAAQKfyoAAg8ACAleGn5YAC8CAA8ACAleGn5YAC8CAAAA.Deselle:BAABLgAECn8gAAIPAAkJmQWKfABiAQAPAAkJmQWKfABiAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8iAAIDAAgJQBJvMwCsAQADAAgJQBJvMwCsAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAIRAAkJNR3lAwCjAgARAAkJNR3lAwCjAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgADCgMJAwAAAA==.',
Do='Dolbyatmos:BAAALgADCgUJBQAAAA==.Donatelloh:BAABLgAECn8VAAMeAAYJjg5NQQDOAAAeAAUJCxFNQQDOAAAQAAUJ+QfbUACjAAAAAA==.Dortbraz:BAAALgAECgYJCAAAAA==.Dotmeharder:BAABLgAECn8bAAMOAAcJ8xOkegBnAQAOAAcJ8xOkegBnAQAYAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Drakelayer:BAACLgAFFH8KAAIIAAMJzQ4tMgDKAAAIAAMJzQ4tMgDKAAAuAAQKfxgAAwgABgmoIc4iAKIBAAgABgnBH84iAKIBAB8ABgmkHvYKAEkBAAAA.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8dAAIgAAkJ7g1SDAC2AQAgAAkJ7g1SDAC2AQAAAA==.Draxyl:BAABLgAECn85AAMEAAkJYBcUOAD8AQAEAAkJYBcUOAD8AQAdAAMJaAQxSQA/AAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMHAAkJpRAYSgCGAQAHAAkJpRAYSgCGAQAVAAUJwwspGgCjAAAAAA==.Drogbar:BAABLgAECn8fAAMcAAkJLxbJDgAkAgAcAAgJEBjJDgAkAgAWAAgJYAglEgATAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMOAAkJchDIOgDWAQAOAAkJchDIOgDWAQAXAAMJNAYoUQB7AAAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn8rAAIEAAgJ+iAIIgBcAgAEAAgJ+iAIIgBcAgAAAA==.Duo:BAABLgAECn8oAAMhAAkJ1hCIBABsAQAhAAcJZRKIBABsAQAPAAkJcwdSvQDwAAABLgAECgcJHAABAI8QAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMQAAkJ3CBMBwCkAgAQAAkJ3CBMBwCkAgAeAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8eAAIOAAcJCwRcrwDMAAAOAAcJCwRcrwDMAAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJCAAFAAAAAA==.Eleidon:BAAALgAECgYJCQAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgMJAwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMZAAkJ7Q8CIACeAQAZAAgJ8w0CIACeAQAaAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMLAAgJmRr9FwBdAgALAAgJmRr9FwBdAgAMAAYJTxQUNQA3AQAAAA==.',
En='Enyô:BAABLgAECn8eAAIPAAcJwxe3YwCaAQAPAAcJwxe3YwCaAQAAAA==.',
Eo='Eorae:BAAALgAECgIJAwAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAABLgAECn8XAAIPAAcJVhhUUQDLAQAPAAcJVhhUUQDLAQAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAgJGQAHAPsXAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCAAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgMJBgABLgAECgcJHAABAI8QAA==.',
Fa='Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIeAAkJFib0AABrAwAeAAkJFib0AABrAwABLgAFFAQJDAAfAMogAA==.',
Fh='Fhalanx:BAAALgAECgUJEAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECgcJHQAiAIQTAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAAALgAECgYJBwAAAA==.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgkJIgAOACwUAA==.Flapp:BAABLgAECn8iAAMOAAkJLBRoMgD2AQAOAAkJLBRoMgD2AQAXAAIJsQiDXABZAAAAAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQAAAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIbAAkJ1Bl7IgAwAgAbAAkJ1Bl7IgAwAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenwings:BAAALgAECgcJCwAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgQJBwABLgAFFAQJBwAKANUPAA==.',
Ga='Gaiseric:BAAALgAFFAIJAgAAAA==.Garrosh:BAAALgAECggJAwAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8VAAQZAAcJSwpmMAAtAQAZAAcJSQpmMAAtAQAaAAQJRQNmZACcAAAkAAEJ8gptcgAwAAAAAA==.Geraldene:BAABLgAECn8VAAIaAAgJMQqQLABBAQAaAAgJMQqQLABBAQAAAA==.Geraniho:BAAALgAECgEJBAAAAA==.',
Gh='Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIHAAkJ6hbALAD2AQAHAAkJ6hbALAD2AQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgIJAgABLgAECggJKAARALYYAA==.Grimthruul:BAAALgAECggJEQAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBWZFwB0AQATAAcJUBWZFwB0AQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAAALgAECgYJDwAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMaAAkJ0xH0KQCjAQAaAAcJDRX0KQCjAQAkAAcJAhKwMgAnAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAFAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAFAAAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhEPHgCqAQAiAAkJBhEPHgCqAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8LAAIBAAQJkhXNBABEAQABAAQJkhXNBABEAQAuAAQKfzMAAgEACQnhHaoDAK4CAAEACQnhHaoDAK4CAAAA.Hiphopuler:BAABLgAECn8yAAIaAAcJ6hygGwAAAgAaAAcJ6hygGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMNAAkJUB6eHwCuAgANAAkJUB6eHwCuAgARAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgEJAgAAAA==.Holyschmit:BAABLgAECn8qAAISAAgJTBr9FgAqAgASAAgJTBr9FgAqAgAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxO/DwDEAQAUAAkJVxO/DwDEAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RmDCADQAQAWAAgJ1RmDCADQAQAAAA==.Huntris:BAABLgAECn8aAAIcAAkJ6RnxDwAXAgAcAAkJ6RnxDwAXAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAAALgAECgYJCQAAAA==.Hypnotykk:BAABLgAECn8ZAAIbAAcJnxVTSgCWAQAbAAcJnxVTSgCWAQAAAA==.',
Ia='Iadygaga:BAAALgAECgcJCAAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgIJAwAAAA==.Imrah:BAABLgAECn8rAAQeAAgJ0xS8GwCnAQAeAAgJ0xS8GwCnAQAQAAMJ2QaDXwBwAAAjAAEJrwMulQAgAAAAAA==.',
In='Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgYJCwAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8KAAIaAAQJhg8oEQASAQAaAAQJhg8oEQASAQAuAAQKfzIAAhoACQlyGy0KAKACABoACQlyGy0KAKACAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8IAAIlAAQJmhoTEABZAQAlAAQJmhoTEABZAQAuAAQKfyIAAiUACAkzGGAdAIABACUACAkzGGAdAIABAAAA.Jocon:BAABLgAECn8hAAIOAAkJUQWabQBJAQAOAAkJUQWabQBJAQAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJEAAcALEOAA==.Kanami:BAABLgAECn8jAAIGAAgJ0RwHFwASAgAGAAgJ0RwHFwASAgAAAA==.Kaori:BAABLgAECn8UAAINAAgJCAg/sgAfAQANAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhmNCQAWAgACAAkJDhmNCQAWAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJDQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx1PCQBtAgAlAAkJbx1PCQBtAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8MAAINAAQJQgx3NgAgAQANAAQJQgx3NgAgAQAuAAQKfzcAAw0ACAkjGsMyABQCAA0ACAm+GcMyABQCABEABgnjGd0SAG0BAAAA.Keedron:BAACLgAFFH8ZAAIHAAgJ+xeXBQBPAgAHAAgJ+xeXBQBPAgAuAAQKfxsAAgcACAlJJIkLACUDAAcACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8fAAIEAAgJqROVYgB/AQAEAAgJqROVYgB/AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8nAAMEAAgJwhu0PADsAQAEAAgJwhu0PADsAQAmAAMJEglOIwBbAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kilfogg:BAABLgAECn8XAAIMAAcJoxfmKwC5AQAMAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8GAAMKAAMJeg/dGQDEAAAKAAMJeg/dGQDEAAAIAAIJOgoaQgB/AAAuAAQKfycABAoACQlJGNcKAAsCAAoACQlJGNcKAAsCAAgABgk3EGY/AAUBAB8AAQmRBb9AAC8AAAEuAAUUAwkHAA0AAh4A.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgEJAgAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8VAAIPAAYJ2CL5BgDwAQAPAAYJ2CL5BgDwAQAuAAQKfxcAAg8ACAm6IwgVACoDAA8ACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAFAAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAANAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIOAAMJ2AOZbgC1AAAOAAMJ2AOZbgC1AAAuAAQKfxYAAg4ABwlgFFZSANABAA4ABwlgFFZSANABAAAA.Krymzendeath:BAAALgAECgUJBQABLgAFFAMJDAAUAJcZAA==.Krísztina:BAABLgAECn8hAAQXAAgJ5QrMEAALAQAYAAcJIQgIEQAbAQAXAAgJqAnMEAALAQAOAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAgJGQAHAPsXAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAFAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIcAAQJsQ5mDwA2AQAcAAQJsQ5mDwA2AQAuAAQKfyMAAhwACQkmGOQHAHICABwACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Lakey:BAABLgAECn8WAAQaAAgJniUdFAARAgAaAAgJniUdFAARAgAZAAUJ6SLcFgDxAQAkAAMJOA73SgCuAAABLgAFFAUJFQADADcSAA==.Lakeyy:BAACLgAFFH8VAAMDAAUJNxKmGABcAQADAAUJNxKmGABcAQAiAAQJZBBkGgAdAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAAALgAECgYJBgABLgAFFAUJFQADADcSAA==.Lanayrd:BAAALgAECgEJAQAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJCAANAMkaAA==.Lawrence:BAACLgAFFH8LAAMMAAQJbxD0GgAWAQAMAAQJbxD0GgAWAQALAAMJkwlyQACwAAAuAAQKfyMAAwwACAmaIcIKAOoCAAwACAmaIcIKAOoCAAsAAwkbDu2KAH8AAAEuAAUUBQkFAAcA/Q0A.',
Le='Leanhaum:BAAALgAECgIJAQAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgYJEAAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8hAAQEAAcJIhaAHQCbAQAEAAYJqBWAHQCbAQAmAAQJSQ3aCQATAQAdAAEJAAAfGgA0AAAuAAQKfzEAAwQACQmjI/cWAPICAAQACQmZI/cWAPICACYABwkiHTYGAAQCAAAA.Lithe:BAAALgAECgQJBgABLgAFFAMJCgAMAGMRAA==.',
Lo='Locklear:BAABLgAECn8iAAINAAkJbBbLNQAJAgANAAkJbBbLNQAJAgAAAA==.Logic:BAACLgAFFH8cAAMPAAgJfhRuCQBGAgAPAAgJfhRuCQBGAgAhAAIJiA5fAgCdAAAuAAQKfysAAg8ACQlvI2UOAPACAA8ACQlvI2UOAPACAAAA.Lolshield:BAAALgAECgYJBgABLgAFFAUJFAAQAMYeAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8qAAIRAAkJcQqgGAAqAQARAAkJcQqgGAAqAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xk8BAAbAgAnAAgJ9xk8BAAbAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJFQADADcSAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAQJEAAEAHwUAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAABLgAECn8tAAIEAAkJLx34HwBnAgAEAAkJLx34HwBnAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8TAAIHAAYJBheDBADpAQAHAAYJBheDBADpAQAuAAQKfycAAgcACQkZIkEIAEgDAAcACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJEwAHAAYXAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIPAAkJbhVCUgDJAQAPAAkJbhVCUgDJAQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8IAAINAAQJyRrmIQBQAQANAAQJyRrmIQBQAQAuAAQKfy0AAg0ACQn9HgAaAIkCAA0ACQn9HgAaAIkCAAAA.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIEAAkJ+BwYGQCOAgAEAAkJ+BwYGQCOAgAAAA==.Mamageek:BAABLgAECn8XAAILAAkJ9hHmKADsAQALAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAFAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAPAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8iAAINAAgJnxwSNQAMAgANAAgJnxwSNQAMAgAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIdAAgJyBSrFQCPAQAdAAgJyBSrFQCPAQAAAA==.Mcversatile:BAABLgAECn8VAAICAAYJuxc4DwCIAQACAAYJuxc4DwCIAQABLgAECggJFgAdAMgUAA==.',
Me='Meatloaf:BAABLgAECn8rAAIaAAkJrBksEABkAgAaAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8VAAIKAAcJLR/rAQCgAgAKAAcJLR/rAQCgAgAuAAQKfycAAgoACQkZJjAAAOgDAAoACQkZJjAAAOgDAAAA.Mereoleona:BAAALgAECgYJCQAAAA==.Metalmagus:BAABLgAECn8iAAIPAAgJCRoUQgD6AQAPAAgJCRoUQgD6AQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSKgAwCgAgAgAAkJTSKgAwCgAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAgJGQAHAPsXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8kAAIQAAkJ/hJAGgC1AQAQAAkJ/hJAGgC1AQAAAA==.Misslobster:BAAALgAECggJDgAAAA==.Mistweaver:BAAALgAFFAEJAQABLgAFFAIJAwAFAAAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJKwALAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8LAAMIAAQJYxmpJQAHAQAIAAQJYxmpJQAHAQAfAAEJVQsfCgBTAAAuAAQKfy8AAwgACQkjHtEFACcDAAgACQkJHtEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJCwAIAGMZAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR3SCwByAgAiAAkJKR3SCwByAgADAAQJDxFhggDUAAACAAEJch2YRQBQAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMeAAkJbCNzBgDEAgAeAAkJbCNzBgDEAgAQAAYJ7hlBJQBkAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
My='Myka:BAAALgADCgkJCQABLgAECgYJBgAFAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJFAAQAMYeAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAFAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIEAAkJVBvcQgDYAQAEAAkJVBvcQgDYAQAAAA==.Necrota:BAACLgAFFH8GAAIEAAMJhhk9ZQABAQAEAAMJhhk9ZQABAQAuAAQKfxoAAwQACAmVHuQ6APIBAAQACAkWHuQ6APIBAB0AAQlcG5FBAEUAAAEuAAUUBgkVAA8A2CIA.Neuron:BAACLgAFFH8XAAIDAAcJlhqtAQD6AQADAAcJlhqtAQD6AQAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJBQAAAA==.Nigdruu:BAABLgAECn8hAAIDAAkJ6hkmHABbAgADAAkJ6hkmHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8rAAIoAAgJrg7qCACSAQAoAAgJrg7qCACSAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgQJBgAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAgABLgAECgQJBAAFAAAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgADCgMJAwAAAA==.',
Oo='Oortt:BAAALgAECgUJBQAAAA==.',
Or='Oralys:BAABLgAECn8hAAISAAgJEiKPDQCTAgASAAgJEiKPDQCTAgAAAA==.Oreyn:BAAALgAECgMJAwAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn8oAAIRAAgJthi7DQC6AQARAAgJthi7DQC6AQAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJCwAVAG0bAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAABLgAECn8ZAAIlAAcJ9x5JDwATAgAlAAcJ9x5JDwATAgAAAA==.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgQJBAAAAA==.Payn:BAACLgAFFH8MAAMfAAQJyiDLAACeAQAfAAQJyiDLAACeAQAIAAIJlBKfPQCOAAAuAAQKfy4AAx8ACQnkJSYAAIYDAB8ACQnkJSYAAIYDAAgAAgmbHxBKAKwAAAAA.Paypay:BAACLgAFFH8IAAIDAAQJnyGKEgCRAQADAAQJnyGKEgCRAQAuAAQKfzoAAwMACQnXJZMAANsDAAMACQnXJZMAANsDACIABgkfEHM4AP8AAAAA.',
Pe='Pepperknight:BAAALgAECgYJBgAAAA==.',
Ph='Phalannx:BAAALgADCgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8oAAMaAAcJbxmbGwDEAQAaAAcJbxmbGwDEAQAkAAUJnR9fJwBqAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAgABLgAECgUJCAAFAAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJBwAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIZAAMJlQjEJgDJAAAZAAMJlQjEJgDJAAAuAAQKfx4AAhkABgmxH8MTABACABkABgmxH8MTABACAAAA.Prrowl:BAAALgAECgUJCwAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rakashi:BAAALgADCgcJDgAAAA==.Rareley:BAAALgAECggJCAAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJCAANAMkaAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8bAAIMAAgJsxSqJQCPAQAMAAgJsxSqJQCPAQAAAA==.Rollos:BAABLgAECn8gAAIOAAkJUBXDKgAWAgAOAAkJUBXDKgAWAgAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxIlJAC3AQAjAAgJCxIlJAC3AQAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8cAAIIAAgJbSEiAgC/AgAIAAgJbSEiAgC/AgAuAAQKfyAAAggACQm3JfAAAMwDAAgACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8VAAQOAAYJUhUSmQD0AAAOAAUJUhUSmQD0AAAXAAEJ+A1zcAA2AAAYAAEJAACpOAAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECggJKAARALYYAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAGAH4aAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgYJCQAAAA==.Samtarkras:BAABLgAECn8tAAIKAAkJqho7BgCBAgAKAAkJqho7BgCBAgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAFAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAAALgAFFAEJAQABLgAFFAQJEAAEAHwUAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8FAAIYAAMJghFqBQDpAAAYAAMJghFqBQDpAAAuAAQKf3YAAxgACQmGIbIAAAoDABgACQmGIbIAAAoDAA4ABglbGW9RAJABAAAA.Selket:BAAALgAECgYJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8qAAMkAAgJIhSYHQCxAQAkAAgJIhSYHQCxAQAaAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8GAAIkAAMJUg2XHQDRAAAkAAMJUg2XHQDRAAAuAAQKf2UAAiQACQnFJPcBAEUDACQACQnFJPcBAEUDAAEuAAUUBgkWAAwA+BoA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIbAAQJSQvpPAD1AAAbAAQJSQvpPAD1AAAuAAQKfyYAAhsABglhJJcoABICABsABglhJJcoABICAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJHAAIAG0hAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.',
Sl='Slyde:BAABLgAECn8fAAIEAAgJvB/YMwAMAgAEAAgJvB/YMwAMAgAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIEAAYJzBhqKgB0AQAEAAYJzBhqKgB0AQAuAAQKfyUAAgQACAnPIq8VAPoCAAQACAnPIq8VAPoCAAAA.Smick:BAABLgAECn8bAAISAAcJRBTgKwCLAQASAAcJRBTgKwCLAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgYJCQAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCNUCAAxAgACAAcJNSFUCAAxAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn89AAIGAAkJCyFGCAC9AgAGAAkJCyFGCAC9AgAAAA==.Soulfox:BAAALgAECgEJAgABLgAECggJKwALAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAQJDAAlALQYAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAAALgAECgEJAQAAAA==.',
Sq='Squidmonk:BAAALgAECgYJBgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8gAAIVAAgJfBNhCgCQAQAVAAgJfBNhCgCQAQABLgAFFAMJBQAYAIIRAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAAALgAECggJEwAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8UAAIeAAcJexsIAgD0AQAeAAcJexsIAgD0AQAuAAQKfxUAAh4ACAlEH5kMALECAB4ACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCQAAAA==.Straydog:BAABLgAECn8lAAILAAkJdiAnBQA7AwALAAkJdiAnBQA7AwAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIEAAkJlhYwaABxAQAEAAkJlhYwaABxAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAFAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAFAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Superpowers:BAABLgAECn8XAAIQAAgJWR8HCwBmAgAQAAgJWR8HCwBmAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn8/AAITAAkJhyH1AgDmAgATAAkJhyH1AgDmAgAAAA==.Sus:BAAALgAFFAIJAgAAAA==.Suzel:BAABLgAECn8VAAIEAAUJSgch2gCqAAAEAAUJSgch2gCqAAAAAA==.',
Sw='Sweatmachine:BAAALgADCgMJAwAAAA==.Swoof:BAAALgAECggJEQABLgAFFAQJEAAEAHwUAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn8rAAIJAAgJXhH4FwCMAQAJAAgJXhH4FwCMAQAAAA==.Synath:BAAALgAECgMJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAZAN4OAA==.Synwise:BAABLgAECn8sAAIDAAkJBB9SCAAYAwADAAkJBB9SCAAYAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8LAAIbAAQJWxOIJwA1AQAbAAQJWxOIJwA1AQAuAAQKfzMAAxsACQmIHO8YAGgCABsACQmIHO8YAGgCABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIeAAgJCxnTGAAcAgAeAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgEJAgAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8kAAQaAAkJlhpKDQBpAgAaAAkJlhpKDQBpAgAZAAQJlA2tRgCrAAAkAAEJCg65bQA1AAAAAA==.',
Th='Thanah:BAAALgAECgMJBQAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8MAAIEAAQJRQp6WAAdAQAEAAQJRQp6WAAdAQAuAAQKfyoAAwQACQkdGMg8AOwBAAQACQkdGMg8AOwBACYAAQneCS8rADAAAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAFAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJAwAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8LAAIVAAQJbRtaAgBEAQAVAAQJbRtaAgBEAQAuAAQKfzgAAhUACQnWHuECAJoCABUACQnWHuECAJoCAAAA.Tinytea:BAACLgAFFH8LAAIQAAQJTCNSCgCeAQAQAAQJTCNSCgCeAQAuAAQKf0EAAhAACQkyJS8BAFMDABAACQkyJS8BAFMDAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDAAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8KAAMSAAQJcx9UEwBaAQASAAQJcx9UEwBaAQANAAEJUQ0iigBJAAAuAAQKfygAAxIACQkYHeUVAGECABIACAkqH+UVAGECAA0ABQnfEBubAB4BAAAA.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgADCgYJCAAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMGAAYJ0SGHLQD9AQAGAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAEAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgADCgYJBgABLgAECgcJEAAFAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAFAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAFAAAAAA==.Turkeyleg:BAAALgADCgYJBwAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgcPGQCjAAAUAAMJfgcPGQCjAAAuAAQKfx4AAhQACQkPD/sUAHsBABQACQkPD/sUAHsBAAAA.Twippy:BAAALgADCgYJBgABLgAFFAMJBQAUAH4HAA==.',
Ty='Tyanis:BAABLgAECn8UAAINAAYJ1wrQuQDuAAANAAYJ1wrQuQDuAAABLgAECgcJDgAFAAAAAA==.Tyriam:BAABLgAECn8wAAMNAAkJ2hpcIQBiAgANAAgJ2hpcIQBiAgASAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIPAAgJixOMXQCpAQAPAAgJixOMXQCpAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAFAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Vandy:BAABLgAECn8nAAMHAAkJLAo8eAAJAQAJAAYJtwvaNwAmAQAHAAkJXAk8eAAJAQAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8NAAIfAAQJDA68AwAqAQAfAAQJDA68AwAqAQAuAAQKfx4AAh8ACAlhIEgEAMkCAB8ACAlhIEgEAMkCAAAA.Verso:BAABLgAECn8pAAInAAkJWRuqAgBrAgAnAAkJWRuqAgBrAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinushka:BAAALgAECgYJCwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECggJKgAIAEQeAA==.Vitalithry:BAABLgAECn8qAAMIAAgJRB6nFAAWAgAIAAgJOh6nFAAWAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAFAAAAAA==.',
Vy='Vyndication:BAAALgAFFAEJAQAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJCAANAMkaAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAFAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAABLgAECn8mAAIEAAgJbxVqVACjAQAEAAgJbxVqVACjAQAAAA==.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn8tAAQLAAgJ4BnSGwA/AgALAAgJ4BnSGwA/AgAMAAgJ4h7wEgArAgAgAAIJ7xH1LAA4AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8PAAIkAAYJBhfEBwCiAQAkAAYJBhfEBwCiAQAuAAQKfzMAAyQACAlMH8kLAHECACQACAlMH8kLAHECABoAAQklJelRAGYAAAAA.Windoelicker:BAAALgAECgUJDQAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAAALgAECggJDgAAAA==.',
Wu='Wuggles:BAACLgAFFH8QAAIDAAQJDg0MJgAFAQADAAQJDg0MJgAFAQAuAAQKfygAAwMACQkzHOoWAG0CAAMACQkzHOoWAG0CACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMbAAkJ7xqoKQANAgAbAAgJFxuoKQANAgAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIEAAQJRBRUSAA3AQAEAAQJRBRUSAA3AQAuAAQKfx4AAwQACAn0Hp8vAB0CAAQACAn0Hp8vAB0CACYAAQlgEJArAC8AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAISAAkJdgpFKgCWAQASAAkJdgpFKgCWAQAAAA==.Yey:BAABLgAECn8hAAQSAAkJjxk/FQA7AgASAAkJjxk/FQA7AgARAAMJJgHQPwA7AAANAAEJDQQOeQEnAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8XAAIPAAgJawvSfQBfAQAPAAgJawvSfQBfAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgADCgEJAQAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIOAAMJGQy3YQDUAAAOAAMJGQy3YQDUAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChv6CAAiAgACAAgJChv6CAAiAgAiAAUJvw0ROQD9AAABAAIJpAdmRQAlAAABLgAFFAMJBgAOABkMAA==.Zaydämon:BAABLgAECn8WAAIHAAgJ4R1IHwCWAgAHAAgJ4R1IHwCWAgABLgAFFAMJBgAOABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECggJJwABAK0WAA==.Ziggybeast:BAACLgAFFH8IAAIDAAIJBxmwPQCaAAADAAIJBxmwPQCaAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTIiaYAGIAAAIAAwl4DbBFAFAAAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCAADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAABLgAECn87AAIEAAkJ6RxWKQA5AgAEAAkJ6RxWKQA5AgAAAA==.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgIJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAFFAMJBgAOABkMAA==.',
['Zø']='Zøphar:BAAALgADCgEJAQAAAA==.',
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
