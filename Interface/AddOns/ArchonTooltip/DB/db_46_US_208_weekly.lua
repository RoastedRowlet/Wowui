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

local lookup = {'Druid-Feral','Druid-Guardian','Druid-Restoration','DeathKnight-Unholy','Unknown-Unknown','Shaman-Elemental','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','DemonHunter-Havoc','Evoker-Preservation','Shaman-Restoration','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Monk-Brewmaster','Paladin-Protection','Paladin-Holy','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','Shaman-Enhancement','Mage-Fire','Druid-Balance','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8cAAQBAAcJjxCMFgA7AQABAAcJ9g+MFgA7AQACAAYJUgv1OgCRAAADAAEJJQf12gAnAAAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8MAAIEAAQJbRQAVAAuAQAEAAQJbRQAVAAuAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAFAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8WAAIGAAUJBQpQXwCqAAAGAAUJBQpQXwCqAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIHAAYJfhq/OwBBAQAHAAYJfhq/OwBBAQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAHAH4aAA==.',
Al='Alariel:BAABLgAECn8nAAIIAAkJmxiJKQAOAgAIAAkJmxiJKQAOAgABLgAFFAQJCwAJAGMZAA==.Albesuri:BAAALgAECgUJBQABLgAFFAgJGQAIAPsXAA==.Albskin:BAAALgAECgMJAwAAAA==.Alcazar:BAABLgAECn8lAAMIAAcJUx2QLAAAAgAIAAcJUx2QLAAAAgAKAAEJAAAodAAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAILAAgJGwj8HwB+AQALAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJHQALAPwYAA==.Alliar:BAABLgAECn8nAAMMAAkJxBzEIgAkAgAMAAkJxBzEIgAkAgAGAAIJLgm0ggBOAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAFAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJHQALAPwYAA==.',
Am='Amalek:BAAALgADCgUJBQAAAA==.Amerha:BAABLgAECn8ZAAMMAAkJHQ2dNgC7AQAMAAkJHQ2dNgC7AQAGAAEJZQT1ogAkAAAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAACLgAFFH8HAAINAAMJAh4OQgAQAQANAAMJAh4OQgAQAQAuAAQKfxwAAg0ACAnRIRsrADwCAA0ACAnRIRsrADwCAAEuAAUUAwkJAAsAeg8A.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURF4dADGAAADAAQJURF4dADGAAAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8UAAIKAAcJuRUqGgCNAQAKAAcJuRUqGgCNAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJOQAOAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8dAAIPAAUJ5x2fOQBdAQAPAAUJ5x2fOQBdAQAuAAQKfy0AAg8ACAl5IvAlANsCAA8ACAl5IvAlANsCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8cAAIGAAkJRxb5GQD6AQAGAAkJRxb5GQD6AQABLgAECgEJAQAFAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJBwABLgAECgEJAQAFAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAFAAAAAA==.Atrell:BAABLgAECn8eAAINAAkJrRgpQADuAQANAAkJrRgpQADuAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgEJAQABLgAFFAUJFQAQAMYeAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJCQAAAA==.Balrock:BAAALgAECgEJAQAAAA==.Balthromaw:BAABLgAECn8wAAIOAAgJShuzLwANAgAOAAgJShuzLwANAgAAAA==.Bananarang:BAAALgADCgUJBQAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJAwAAAA==.Barqs:BAAALgAFFAIJAwAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSLZIwAZAgADAAYJGSLZIwAZAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAHAPwcAA==.Beardwaffle:BAABLgAECn8rAAIHAAkJ/BwYEQBbAgAHAAkJ/BwYEQBbAgAAAA==.Bearlando:BAAALgAFFAQJBAABLgAFFAcJFwAGAGEXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQNAAYJiyLCQADsAQANAAUJiyLCQADsAQARAAUJyw9XKgC5AAASAAMJdQ4PZwB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIPAAMJ1wSJhACmAAAPAAMJ1wSJhACmAAAuAAQKfxQAAg8ABwkyEx20AHYBAA8ABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx3VDgA9AQATAAQJixrVDgA9AQAHAAQJMhowGgA0AQAuAAQKfygABAcACAkOJC0UAKwCAAcACAl0Iy0UAKwCABQAAwmQJCsfAB8BABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAJAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIIAAkJFBiBLAAAAgAIAAkJFBiBLAAAAgAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodhoundss:BAABLgAECn8mAAIHAAkJHxgWFwAhAgAHAAkJHxgWFwAhAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBUKCwCRAQAVAAgJFBUKCwCRAQAAAA==.',
Bo='Bob:BAACLgAFFH8VAAIIAAYJnBR4CQCTAQAIAAYJnBR4CQCTAQAuAAQKfyYAAggACQk+IdoIAEIDAAgACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8nAAIMAAkJdxflHwA2AgAMAAkJdxflHwA2AgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAECgMJBAAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8aAAIHAAkJjg5LJAC+AQAHAAkJjg5LJAC+AQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8HAAIWAAIJihw7HQCQAAAWAAIJihw7HQCQAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAECgcJFAAMAKYYAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAAALgAFFAIJAgAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Caliginosity:BAABLgAECn8YAAIXAAcJeRc2DAD/AQAXAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8mAAICAAgJGh8mBwBpAgACAAgJGh8mBwBpAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCAAAAA==.Chemotherapy:BAAALgAECgUJBgAAAA==.Chillingsly:BAAALgADCgYJDQABLgAFFAMJBwAYAMcRAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIHAAkJZB0xEQBaAgAHAAkJZB0xEQBaAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAIRAAMJ5hOKCQDFAAARAAMJ5hOKCQDFAAAuAAQKfxwAAhEACQm7GkwIAFUCABEACQm7GkwIAFUCAAAA.Condemnation:BAACLgAFFH8JAAIZAAMJJxD2KADMAAAZAAMJJxD2KADMAAAuAAQKfzgAAxkACQmjGu4NAHECABkACQmQFu4NAHECABoACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJCwAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAFAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAFAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8YAAISAAkJ9QokMACDAQASAAkJ9QokMACDAQAAAA==.',
Cr='Crayak:BAACLgAFFH8PAAIKAAQJTxsVCQBGAQAKAAQJTxsVCQBGAQAuAAQKfzEAAwoACQnmItADAP0CAAoACQnmItADAP0CAAgABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgcJJQAIAFMdAA==.Crossbones:BAABLgAECn8qAAMbAAgJlxyLHQBfAgAbAAgJlxyLHQBfAgAcAAQJWA8XOADhAAAAAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8JAAIIAAUJ8A9yRQD+AAAIAAUJ8A9yRQD+AAAuAAQKfxwAAggACAltGqUyAC8CAAgACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8iAAIGAAgJQhVvKACRAQAGAAgJQhVvKACRAQAAAA==.Curbstomped:BAAALgAECgcJCAAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIEAAMJ2hEGiADWAAAEAAMJ2hEGiADWAAAuAAQKfyQAAwQACQkVIkMUALwCAAQACQkMIkMUALwCAB0ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8WAAIUAAQJ2yQEBwCcAQAUAAQJ2yQEBwCcAQAuAAQKf0IABBQACAlhJd0EAL8CABQACAnKJN0EAL8CAAcABwnvHpUdAGICABMABgk7IuMVAJYBAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJBAAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAOAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIPAAUJbhPLUAAwAQAPAAUJbhPLUAAwAQAuAAQKfyoAAg8ACAleGn5YAC8CAA8ACAleGn5YAC8CAAAA.Deselle:BAABLgAECn8gAAIPAAkJmQWEiQBJAQAPAAkJmQWEiQBJAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8lAAIDAAkJHxHZLQDcAQADAAkJHxHZLQDcAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAIRAAkJNR2FBACeAgARAAkJNR2FBACeAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgEJAQAAAA==.',
Do='Dolbyatmos:BAAALgAFFAEJAQAAAA==.Donatelloh:BAABLgAECn8YAAMeAAYJ7Q4cRwDMAAAeAAUJCxEcRwDMAAAQAAUJ9AofTwC0AAAAAA==.Dortbraz:BAAALgAECgYJCAAAAA==.Dotmeharder:BAABLgAECn8bAAMOAAcJ8xOkegBnAQAOAAcJ8xOkegBnAQAYAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8LAAIJAAMJ1xI5NQDPAAAJAAMJ1xI5NQDPAAAuAAQKfxoAAwkABgmoIV8iAKwBAAkABgnKH18iAKwBAB8ABgmkHq8LAEcBAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJCwAJANcSAA==.Drakuza:BAAALgAFFAEJAQAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g3iDQC1AQAgAAkJ7g3iDQC1AQAAAA==.Draxyl:BAABLgAECn88AAMEAAkJYBfvPAD6AQAEAAkJYBfvPAD6AQAdAAMJaAR3TwA+AAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMIAAkJpRAVUAB+AQAIAAkJpRAVUAB+AQAVAAUJwwtdHACfAAAAAA==.Drogbar:BAABLgAECn8jAAMcAAkJZRgZCgBwAgAcAAkJZRgZCgBwAgAWAAgJYAhwEwARAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMOAAkJchDqPwDQAQAOAAkJchDqPwDQAQAXAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgMJAwAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn8rAAIEAAgJ+iAlJgBXAgAEAAgJ+iAlJgBXAgAAAA==.Duo:BAABLgAECn8uAAMhAAkJ4BAJBQBmAQAhAAcJchIJBQBmAQAPAAkJcwenvgDtAAABLgAECgcJHAABAI8QAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMQAAkJ3CAzCACfAgAQAAkJ3CAzCACfAgAeAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIOAAcJFgQtuQDJAAAOAAcJFgQtuQDJAAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAFAAAAAA==.Eleidon:BAAALgAECgYJCgAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMZAAkJ7Q9wIwCPAQAZAAgJ8w1wIwCPAQAaAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMMAAgJmRrIGgBaAgAMAAgJmRrIGgBaAgAGAAYJTxR8OQA1AQAAAA==.',
En='Enyô:BAABLgAECn8gAAIPAAkJJRVaPQAOAgAPAAkJJRVaPQAOAgAAAA==.',
Eo='Eorae:BAAALgAECgIJAwAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAABLgAECn8cAAIPAAcJOxytRgDwAQAPAAcJOxytRgDwAQAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAgJGQAIAPsXAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgQJCgABLgAECgcJHAABAI8QAA==.',
Fa='Faceblock:BAAALgAECgEJAQAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIeAAkJFiYsAQBnAwAeAAkJFiYsAQBnAwABLgAFFAUJEQAfAD8jAA==.Felzugger:BAAALgAFFAMJBAABLgAFFAcJFwAGAGEXAA==.',
Fh='Fhalanx:BAAALgAECgUJEAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECggJIQAiAKcUAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAAALgAECgYJCwAAAA==.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgkJIgAOACwUAA==.Flapp:BAABLgAECn8iAAMOAAkJLBRVNwDwAQAOAAkJLBRVNwDwAQAXAAIJsQiDXABZAAAAAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIbAAkJ1BkSKAAoAgAbAAkJ1BkSKAAoAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenwings:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgQJBwABLgAFFAQJBwALANUPAA==.',
Ga='Gaiseric:BAAALgAFFAIJAgAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQZAAgJ1QmuKABoAQAZAAgJ1QmuKABoAQAaAAQJRQNmZACcAAAkAAEJ8goFewAvAAAAAA==.Geraldene:BAABLgAECn8VAAIaAAgJMQrxLwA4AQAaAAgJMQrxLwA4AQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgADCgYJBgAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIIAAkJ6hasMADtAQAIAAkJ6hasMADtAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJKQARAHsYAA==.Grimthruul:BAABLgAECn8WAAIGAAgJfATjTADlAAAGAAgJfATjTADlAAAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBVcGgBvAQATAAcJUBVcGgBvAQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAAALgAECgYJEgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMaAAkJ0xH0KQCjAQAaAAcJDRX0KQCjAQAkAAcJAhLDNwATAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAFAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAFAAAAAA==.Hanharr:BAAALgAECgMJAgAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhHTIACoAQAiAAkJBhHTIACoAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgEJAQAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8PAAIBAAQJMRghBQBBAQABAAQJMRghBQBBAQAuAAQKfzUAAgEACQkwHg4EAKsCAAEACQkwHg4EAKsCAAAA.Hiphopuler:BAABLgAECn85AAIaAAgJpBmgGwAAAgAaAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMNAAkJUB6eHwCuAgANAAkJUB6eHwCuAgARAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgEJAgAAAA==.Holyschmit:BAABLgAECn8qAAISAAgJTBovGQAmAgASAAgJTBovGQAmAgAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxPLEQC2AQAUAAkJVxPLEQC2AQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RlOCQDMAQAWAAgJ1RlOCQDMAQAAAA==.Huntris:BAABLgAECn8aAAIcAAkJ6RlnEQATAgAcAAkJ6RlnEQATAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAAALgAECgYJEgAAAA==.Hypnotykk:BAABLgAECn8aAAIbAAgJFBTEQQDFAQAbAAgJFBTEQQDFAQAAAA==.',
Ia='Iadygaga:BAAALgAECgcJCAAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgIJAwABLgAFFAQJDAAEAG0UAA==.Imrah:BAABLgAECn8rAAQeAAgJ0xRUHgClAQAeAAgJ0xRUHgClAQAQAAMJ2QYpZABwAAAjAAEJrwOoqgAgAAAAAA==.',
In='Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8OAAIaAAQJbhfgDwAuAQAaAAQJbhfgDwAuAQAuAAQKfzQAAhoACQlyG3ULAJgCABoACQlyG3ULAJgCAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8NAAIlAAUJvx5TDgB2AQAlAAUJvx5TDgB2AQAuAAQKfyIAAiUACAkzGBUgAHoBACUACAkzGBUgAHoBAAAA.Jocon:BAABLgAECn8jAAIOAAkJ6wVucQBMAQAOAAkJ6wVucQBMAQAAAA==.Joraan:BAAALgAECgYJBgAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJEAAcALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAcALEOAA==.Kanami:BAABLgAECn8pAAIHAAkJ0h0xDQCGAgAHAAkJ0h0xDQCGAgAAAA==.Kaori:BAABLgAECn8UAAINAAgJCAg/sgAfAQANAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhkRCwASAgACAAkJDhkRCwASAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJEAAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx3LCgBhAgAlAAkJbx3LCgBhAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8QAAINAAQJIxK5NgAmAQANAAQJIxK5NgAmAQAuAAQKfz4AAw0ACQlrGoAnAEwCAA0ACQlJGYAnAEwCABEABgnLHP8QAJwBAAAA.Keedron:BAACLgAFFH8ZAAIIAAgJ+xclCQA9AgAIAAgJ+xclCQA9AgAuAAQKfxsAAggACAlJJIkLACUDAAgACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIEAAgJqRPuZwCCAQAEAAgJqRPuZwCCAQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8qAAMEAAkJFxxqJQBaAgAEAAkJFxxqJQBaAgAmAAMJEglpKwBHAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCgIJAgAAAA==.Kilfogg:BAABLgAECn8XAAIGAAcJoxfmKwC5AQAGAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8JAAMLAAMJeg+FHAC6AAALAAMJeg+FHAC6AAAJAAMJRwliPQCxAAAuAAQKfycABAsACQlJGAsMAAQCAAsACQlJGAsMAAQCAAkABgk3EPtEAPQAAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIPAAcJ/R75BgDwAQAPAAcJ/R75BgDwAQAuAAQKfxcAAg8ACAm6IwgVACoDAA8ACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAFAAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAANAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIOAAMJ2AO2eQC0AAAOAAMJ2AO2eQC0AAAuAAQKfxYAAg4ABwlgFFZSANABAA4ABwlgFFZSANABAAAA.Krymzendeath:BAAALgAECgYJCwABLgAFFAQJEAAUALcWAA==.Krísztina:BAABLgAECn8hAAQXAAgJ5QqiEgAGAQAYAAcJIQhpEwASAQAXAAgJqAmiEgAGAQAOAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAgJGQAIAPsXAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAFAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIcAAQJsQ7+EQAwAQAcAAQJsQ7+EQAwAQAuAAQKfyQAAhwACQkmGOQHAHICABwACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Lakey:BAABLgAECn8XAAQaAAgJBybaEwAiAgAaAAgJBybaEwAiAgAZAAUJ6SIZGQDnAQAkAAMJOA73SgCuAAABLgAFFAUJGgADAIkUAA==.Lakeyy:BAACLgAFFH8aAAMDAAUJiRRxGwBeAQADAAUJiRRxGwBeAQAiAAQJERGWHgACAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAAALgAECgYJCQABLgAFFAUJGgADAIkUAA==.Lanayrd:BAAALgAECgEJAQAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAANAC0cAA==.Lawrence:BAACLgAFFH8LAAMGAAQJbxDYHwAFAQAGAAQJbxDYHwAFAQAMAAMJkwnASgCoAAAuAAQKfyMAAwYACAmaIcIKAOoCAAYACAmaIcIKAOoCAAwAAwkbDhaWAH4AAAEuAAUUBQkKAAgAwBMA.Lazuril:BAAALgAECgEJAgAAAA==.',
Le='Leanhaum:BAAALgAECgIJAwAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgYJEAAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8jAAQEAAgJFRUTFQDqAQAEAAcJrBQTFQDqAQAmAAQJSQ2MDAALAQAdAAEJAAAfGgA0AAAuAAQKfzEAAwQACQmjI/cWAPICAAQACQmZI/cWAPICACYABwkiHTgHAPwBAAAA.Lithe:BAAALgAECgYJCwABLgAFFAMJDAAGAAcWAA==.',
Lo='Locklear:BAABLgAECn8iAAINAAkJbBazPQD2AQANAAkJbBazPQD2AQAAAA==.Logic:BAACLgAFFH8eAAMPAAgJfhT3DQA9AgAPAAgJfhT3DQA9AgAhAAIJiA5TAwCFAAAuAAQKfysAAg8ACQlvI7YQAOQCAA8ACQlvI7YQAOQCAAAA.Lolshield:BAAALgAECgYJCgABLgAFFAUJFQAQAMYeAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8qAAIRAAkJcQrQGgAoAQARAAkJcQrQGgAoAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xm9BAAZAgAnAAgJ9xm9BAAZAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJGgADAIkUAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAUJFQAEAMwXAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAABLgAECn8uAAIEAAkJLx2kIwBjAgAEAAkJLx2kIwBjAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8TAAIIAAYJBheDBADpAQAIAAYJBheDBADpAQAuAAQKfycAAggACQkZIkEIAEgDAAgACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJEwAIAAYXAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIPAAkJbhUVWAC9AQAPAAkJbhUVWAC9AQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAINAAQJLRyUJABTAQANAAQJLRyUJABTAQAuAAQKfy0AAg0ACQn9HlseAHkCAA0ACQn9HlseAHkCAAAA.Makima:BAAALgAECgEJAQAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIEAAkJ+BxvHACJAgAEAAkJ+BxvHACJAgAAAA==.Mamageek:BAABLgAECn8XAAIMAAkJ9hHmKADsAQAMAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAFAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAPAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8iAAINAAgJnxxEOwD+AQANAAgJnxxEOwD+AQAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIdAAgJyBQlGACIAQAdAAgJyBQlGACIAQAAAA==.Mcversatile:BAABLgAECn8VAAICAAYJuxc4DwCIAQACAAYJuxc4DwCIAQABLgAECggJFgAdAMgUAA==.',
Me='Meatloaf:BAABLgAECn8rAAIaAAkJrBksEABkAgAaAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8bAAILAAgJ+CCaAAAiAwALAAgJ+CCaAAAiAwAuAAQKfycAAgsACQkZJj0AAOUDAAsACQkZJj0AAOUDAAAA.Mereoleona:BAAALgAECgcJDwAAAA==.Metalmagus:BAABLgAECn8iAAIPAAgJCRpgRwDuAQAPAAgJCRpgRwDuAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSI+BACbAgAgAAkJTSI+BACbAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAgJGQAIAPsXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8kAAIQAAkJ/hJ7HACwAQAQAAkJ/hJ7HACwAQAAAA==.Misslobster:BAAALgAECggJDgAAAA==.Mistweaver:BAAALgAFFAEJAwABLgAFFAIJBQAEAHwcAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJKwAMAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8LAAMJAAQJYxlqEAD/AAAJAAQJYxlqEAD/AAAfAAEJVQsfCgBTAAAuAAQKfy8AAwkACQkjHtEFACcDAAkACQkJHtEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJCwAJAGMZAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR1QDQBuAgAiAAkJKR1QDQBuAgADAAQJDxFhggDUAAACAAEJch2YUABPAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMeAAkJbCN5BwC/AgAeAAkJbCN5BwC/AgAQAAYJ7hnAJwBhAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgADCgkJCQABLgAECgYJBgAFAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJFQAQAMYeAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAFAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIEAAkJVBs7SQDUAQAEAAkJVBs7SQDUAQAAAA==.Necrota:BAACLgAFFH8GAAIEAAMJhhlDcgD6AAAEAAMJhhlDcgD6AAAuAAQKfxoAAwQACAmVHkJAAO8BAAQACAkWHkJAAO8BAB0AAQlcG5FBAEUAAAEuAAUUBwkbAA8A/R4A.Nekronomicon:BAAALgAECgYJBgAAAA==.Neuron:BAACLgAFFH8dAAIDAAgJPhtxAgDlAgADAAgJPhtxAgDlAgAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8rAAIoAAgJrg7LCQCLAQAoAAgJrg7LCQCLAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgUJCgAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAFAAAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgADCgYJCQAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAISAAgJEiJMDwCNAgASAAgJEiJMDwCNAgAAAA==.Oreyn:BAAALgAECgcJDAAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn8pAAMRAAkJexgkDwC1AQARAAgJthgkDwC1AQANAAEJ3RbsSgFJAAAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJDAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAABLgAECn8bAAIlAAcJ9x6/EAAOAgAlAAcJ9x6/EAAOAgAAAA==.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8RAAMfAAUJPyP0AACgAQAfAAUJPyP0AACgAQAJAAIJlBJlRQCGAAAuAAQKfzcAAx8ACQlRJh8AAI0DAB8ACQlRJh8AAI0DAAkABAkNH6E8ABYBAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSPNEwCiAQADAAQJbSPNEwCiAQAuAAQKfzsAAwMACQn9JagAAN4DAAMACQn9JagAAN4DACIABgkfECU9AP8AAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQAAAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAECgUJCgAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8tAAMaAAcJ+R48EwApAgAaAAcJ+R48EwApAgAkAAUJnR+UKgBeAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAgABLgAECgUJCAAFAAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJBwAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIZAAMJlQg6KgDFAAAZAAMJlQg6KgDFAAAuAAQKfx4AAhkABgmxH8MTABACABkABgmxH8MTABACAAAA.Prosthesis:BAAALgADCgcJBwAAAA==.Prrowl:BAAALgAECgUJEAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAAALgAECgkJEQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAANAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8hAAIGAAkJKxZRGgD3AQAGAAkJKxZRGgD3AQAAAA==.Rollos:BAABLgAECn8gAAIOAAkJUBWALwAOAgAOAAkJUBWALwAOAgAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxK9KAC2AQAjAAgJCxK9KAC2AQAAAA==.Rookesbane:BAAALgADCgIJAgAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8eAAIJAAgJbSFCAwC0AgAJAAgJbSFCAwC0AgAuAAQKfyEAAgkACQm3JfAAAMwDAAkACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8VAAQOAAYJUhU5pADtAAAOAAUJUhU5pADtAAAXAAEJ+A1zcAA2AAAYAAEJAACPPwAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJKQARAHsYAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAHAH4aAA==.Saeli:BAAALgAECgEJAQAAAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgYJDQAAAA==.Samtarkras:BAABLgAECn8tAAILAAkJqhrwBgB9AgALAAkJqhrwBgB9AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAFAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAAALgAFFAMJBAABLgAFFAUJFQAEAMwXAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8HAAIYAAMJxxEsBwDlAAAYAAMJxxEsBwDlAAAuAAQKf5cAAxgACQk6JFIAAFEDABgACQk6JFIAAFEDAA4ABglbGUpWAI4BAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8qAAMkAAgJIhSHIACjAQAkAAgJIhSHIACjAQAaAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8HAAIkAAMJGw6tIQDAAAAkAAMJGw6tIQDAAAAuAAQKf2oAAiQACQnFJDYCADgDACQACQnFJDYCADgDAAEuAAUUBwkXAAYAYRcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAEAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAAALgAFFAMJAwABLgAFFAYJEAAPAD0hAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIbAAQJSQvURwD0AAAbAAQJSQvURwD0AAAuAAQKfyYAAhsABglhJBsuAA0CABsABglhJBsuAA0CAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJHgAJAG0hAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.',
Sl='Slyde:BAABLgAECn8lAAIEAAkJOyCuFQCyAgAEAAkJOyCuFQCyAgAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIEAAYJzBicNgBmAQAEAAYJzBicNgBmAQAuAAQKfyUAAgQACAnPIq8VAPoCAAQACAnPIq8VAPoCAAEuAAUUBwkJAAkAlBUA.Smick:BAABLgAECn8bAAISAAcJRBQaLwCJAQASAAcJRBQaLwCJAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgYJDAAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCOcCQAuAgACAAcJNSGcCQAuAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9FAAIHAAkJMSGNCADFAgAHAAkJMSGNCADFAgAAAA==.Soulfox:BAAALgAECgEJAgABLgAECggJKwAMAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAQJDwAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAAALgAECgcJDAAAAA==.',
Sq='Squidmonk:BAAALgAECgYJBgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8gAAIVAAgJfBNJCwCNAQAVAAgJfBNJCwCNAQABLgAFFAMJBwAYAMcRAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAAALgAECggJEwAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIeAAgJvhvDAACOAgAeAAgJvhvDAACOAgAuAAQKfxUAAh4ACAlEH5kMALECAB4ACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Straydog:BAABLgAECn8lAAIMAAkJdiBEBgA4AwAMAAkJdiBEBgA4AwAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIEAAkJlhbvcABuAQAEAAkJlhbvcABuAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAFAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAFAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAFAAAAAA==.Superpowers:BAABLgAECn8XAAIQAAgJWR8VDABiAgAQAAgJWR8VDABiAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yF8AwDfAgATAAkJ4yF8AwDfAgAAAA==.Sus:BAABLgAFFH8HAAIbAAQJaQkcWQDEAAAbAAQJaQkcWQDEAAAAAA==.Suzel:BAABLgAECn8XAAIEAAUJSgc26gCqAAAEAAUJSgc26gCqAAAAAA==.',
Sw='Sweatmachine:BAAALgADCgMJAwAAAA==.Swoof:BAAALgAECggJEQABLgAFFAUJFQAEAMwXAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn8uAAIKAAkJFxH7FADEAQAKAAkJFxH7FADEAQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAECgMJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAZAN8OAA==.Synwise:BAABLgAECn8sAAIDAAkJBB9SCQAVAwADAAkJBB9SCQAVAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8NAAIbAAQJWxPxMAA0AQAbAAQJWxPxMAA0AQAuAAQKfzUAAxsACQlmHV4aAHICABsACQlmHV4aAHICABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIeAAgJCxnTGAAcAgAeAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQaAAkJlhr2DgBfAgAaAAkJlhr2DgBfAgAZAAQJlA2zSgCrAAAkAAIJbhKJXQBxAAAAAA==.',
Th='Thanah:BAAALgAECgMJBgAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8QAAIEAAQJXBP9TwA0AQAEAAQJXBP9TwA0AQAuAAQKfyoAAwQACQkdGJVCAOgBAAQACQkdGJVCAOgBACYAAQneCWoxAC8AAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAFAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8MAAIVAAQJmBzFAgBMAQAVAAQJmBzFAgBMAQAuAAQKfzkAAhUACQnWHlkDAJICABUACQnWHlkDAJICAAAA.Tinytea:BAACLgAFFH8MAAIQAAQJhSMPDQCYAQAQAAQJhSMPDQCYAQAuAAQKf0IAAhAACQkyJXABAE8DABAACQkyJXABAE8DAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDAAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8NAAMSAAQJcx/RFgBSAQASAAQJcx/RFgBSAQANAAEJUQ3mnABDAAAuAAQKfygAAxIACQkYHeUVAGECABIACAkqH+UVAGECAA0ABQnfEDKlABQBAAAA.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgADCgYJCAAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMHAAYJ0SGHLQD9AQAHAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAEAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgADCggJCAABLgAECgcJEAAFAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAFAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAFAAAAAA==.Tuckrh:BAAALgAECgIJAgAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgMJAgAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgeCHACXAAAUAAMJfgeCHACXAAAuAAQKfx4AAhQACQkPD38XAG4BABQACQkPD38XAG4BAAEuAAUUBAkHAAYArAIA.Twippy:BAABLgAFFH8HAAIGAAQJrALeKwDDAAAGAAQJrALeKwDDAAAAAA==.',
Ty='Tyanis:BAABLgAECn8aAAINAAYJ1wqfzADZAAANAAYJ1wqfzADZAAABLgAECgcJDgAFAAAAAA==.Tyriam:BAABLgAECn8wAAMNAAkJ2hrvJgBPAgANAAgJ2hrvJgBPAgASAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIPAAgJixP9YwCdAQAPAAgJixP9YwCdAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAFAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Vandy:BAABLgAECn8nAAMKAAkJLAraNwAmAQAKAAYJtwvaNwAmAQAIAAkJXAnGggD9AAAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8RAAIfAAUJtg8dBAAuAQAfAAUJtg8dBAAuAQAuAAQKfx4AAh8ACAlhIEgEAMkCAB8ACAlhIEgEAMkCAAAA.Verso:BAABLgAECn8pAAInAAkJWRsFAwBmAgAnAAkJWRsFAwBmAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinushka:BAAALgAECgYJCwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECggJKgAJAEQeAA==.Vitalithry:BAABLgAECn8qAAMJAAgJRB5rFgANAgAJAAgJOh5rFgANAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAFAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgEJAQAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAANAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAFAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAABLgAECn8mAAIEAAgJbxUNXACfAQAEAAgJbxUNXACfAQAAAA==.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQGAAkJ0R+PBwDRAgAGAAkJ0R+PBwDRAgAMAAgJ4BkmHwA7AgAgAAIJ7xEgMwA4AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8QAAIkAAcJ6hVBBgDZAQAkAAcJ6hVBBgDZAQAuAAQKfzMAAyQACAlMH08NAGQCACQACAlMH08NAGQCABoAAQklJXtWAGQAAAAA.Windoelicker:BAAALgAECgUJDQAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh70CwC7AgAjAAgJqh70CwC7AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8SAAIDAAUJywqmIgApAQADAAUJywqmIgApAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCggJCAAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMbAAkJ7xqHLwAHAgAbAAgJFxuHLwAHAgAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIEAAQJRBRJWQAnAQAEAAQJRBRJWQAnAQAuAAQKfx4AAwQACAn0Hpk0ABgCAAQACAn0Hpk0ABgCACYAAQlgEJ4xAC8AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAISAAkJdgpGLQCUAQASAAkJdgpGLQCUAQAAAA==.Yey:BAABLgAECn8hAAQSAAkJjxlYFwA3AgASAAkJjxlYFwA3AgARAAMJJgEPRQA6AAANAAEJDQS6kwEkAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8XAAIPAAgJawvyhABSAQAPAAgJawvyhABSAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIOAAMJGQw6bADSAAAOAAMJGQw6bADSAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChthCgAfAgACAAgJChthCgAfAgAiAAUJvw3HPQD8AAABAAIJpAcJTQAlAAABLgAFFAMJBgAOABkMAA==.Zaydämon:BAABLgAECn8WAAIIAAgJ4R1IHwCWAgAIAAgJ4R1IHwCWAgABLgAFFAMJBgAOABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECggJJwABAK0WAA==.Ziggybeast:BAACLgAFFH8JAAIDAAIJBxnaQgCYAAADAAIJBxnaQgCYAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTInafAGIAAAIAAwl4DUNRAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCQADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIEAAIJZxgRpQCiAAAEAAIJZxgRpQCiAAAuAAQKfz0AAgQACQkFHcQqAEECAAQACQkFHcQqAEECAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgUJBgAAAA==.',
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
