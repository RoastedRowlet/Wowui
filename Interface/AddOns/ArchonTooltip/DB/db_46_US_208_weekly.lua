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
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8eAAQBAAgJtQ/cFwBAAQABAAcJohDcFwBAAQACAAcJhgq2OgCmAAADAAEJJQf12gAnAAAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8QAAIEAAUJEBfHWAA1AQAEAAUJEBfHWAA1AQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAFAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8WAAIGAAUJBQpKZQCmAAAGAAUJBQpKZQCmAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIHAAYJfhoDPwBAAQAHAAYJfhoDPwBAAQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAHAH4aAA==.',
Al='Alariel:BAABLgAECn8sAAIIAAkJmxhcKAAeAgAIAAkJmxhcKAAeAgABLgAFFAQJCwAJAGMZAA==.Albesuri:BAAALgAECgUJBQABLgAFFAgJGQAIAPsXAA==.Albskin:BAAALgAECgMJAwAAAA==.Alcazar:BAABLgAECn8oAAMIAAcJbx2hLgABAgAIAAcJbx2hLgABAgAKAAEJAAAFfQAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAILAAgJGwj8HwB+AQALAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJHQALAPwYAA==.Alerys:BAAALgAFFAIJAgABLgAFFAgJHQALAPwYAA==.Alliar:BAABLgAECn8nAAMMAAkJxBwxJQAiAgAMAAkJxBwxJQAiAgAGAAIJLgmsiQBOAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAFAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJHQALAPwYAA==.',
Am='Amalek:BAAALgAECgEJAQAAAA==.Amerha:BAABLgAECn8eAAMMAAkJuQ0cOADBAQAMAAkJuQ0cOADBAQAGAAIJiwYNjgBHAAAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAACLgAFFH8IAAINAAMJAh6ESQAMAQANAAMJAh6ESQAMAQAuAAQKfxwAAg0ACAnRIfouADoCAA0ACAnRIfouADoCAAEuAAUUAwkJAAkARwkA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURGgdwDGAAADAAQJURGgdwDGAAAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8VAAIKAAcJORe5GQCiAQAKAAcJORe5GQCiAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJPQAOAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8hAAIPAAUJ5x1vQgBYAQAPAAUJ5x1vQgBYAQAuAAQKfy0AAg8ACAl5IvAlANsCAA8ACAl5IvAlANsCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8dAAIGAAkJnBczGgADAgAGAAkJnBczGgADAgABLgAECgEJAQAFAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJBwABLgAECgEJAQAFAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAFAAAAAA==.Atrell:BAABLgAECn8eAAINAAkJrRgrRQDsAQANAAkJrRgrRQDsAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgYJBgABLgAFFAUJGAAQAAwfAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJDwAAAA==.Balrock:BAAALgAECgEJAQAAAA==.Balthromaw:BAABLgAECn8xAAIOAAkJwhrFIgBQAgAOAAkJwhrFIgBQAgAAAA==.Bananarang:BAAALgADCgUJBQAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJBAAAAA==.Barqs:BAAALgAFFAIJAwAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSKKJQAYAgADAAYJGSKKJQAYAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAHAPwcAA==.Beardwaffle:BAABLgAECn8rAAIHAAkJ/By2EgBXAgAHAAkJ/By2EgBXAgAAAA==.Bearlando:BAAALgAFFAQJBAABLgAFFAgJGQAGAJoXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQNAAYJiyJeRQDrAQANAAUJiyJeRQDrAQARAAUJyw9XKgC5AAASAAMJdQ7nagB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIPAAMJ1wQFjgCkAAAPAAMJ1wQFjgCkAAAuAAQKfxQAAg8ABwkyEx20AHYBAA8ABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx2GEQA6AQATAAQJixqGEQA6AQAHAAQJMhq/HQAtAQAuAAQKfygABAcACAkOJC0UAKwCAAcACAl0Iy0UAKwCABQAAwmQJPsgABwBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAJAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIIAAkJFBjLLwD8AQAIAAkJFBjLLwD8AQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodhoundss:BAABLgAECn8nAAIHAAkJhRjaFwApAgAHAAkJhRjaFwApAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBW4CwCOAQAVAAgJFBW4CwCOAQAAAA==.',
Bo='Bob:BAACLgAFFH8XAAIIAAYJCBZ4CQCTAQAIAAYJCBZ4CQCTAQAuAAQKfyYAAggACQk+IdoIAEIDAAgACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8nAAIMAAkJdxcmIgA0AgAMAAkJdxcmIgA0AgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAFFAEJAQAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8aAAIHAAkJjg7LJgC8AQAHAAkJjg7LJgC8AQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8IAAIWAAIJihzfIACMAAAWAAIJihzfIACMAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAECgcJFQAMAKYYAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAAALgAFFAIJAwAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Caliginosity:BAABLgAECn8YAAIXAAcJeRc2DAD/AQAXAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8pAAICAAkJyR16BQClAgACAAkJyR16BQClAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCQAAAA==.Chemotherapy:BAAALgAECgUJBgAAAA==.Chillingsly:BAAALgADCgkJFgABLgAFFAMJCAAYAMcRAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIHAAkJZB2hEgBYAgAHAAkJZB2hEgBYAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAIRAAMJ5hOOCgC/AAARAAMJ5hOOCgC/AAAuAAQKfxwAAhEACQm7GkwIAFUCABEACQm7GkwIAFUCAAAA.Condemnation:BAACLgAFFH8NAAIZAAQJxQ8IJAAMAQAZAAQJxQ8IJAAMAQAuAAQKfzgAAxkACQmjGjwPAG8CABkACQmQFjwPAG8CABoACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJCwAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAFAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAFAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8YAAISAAkJ9Qo/MgCCAQASAAkJ9Qo/MgCCAQAAAA==.',
Cr='Crayak:BAACLgAFFH8PAAIKAAQJTxt2CwA8AQAKAAQJTxt2CwA8AQAuAAQKfzEAAwoACQnmIocEAPYCAAoACQnmIocEAPYCAAgABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgcJKAAIAG8dAA==.Crossbones:BAABLgAECn8qAAMbAAgJlxzHIABYAgAbAAgJlxzHIABYAgAcAAQJWA93OgDgAAAAAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8KAAIIAAUJCxEPTAD4AAAIAAUJCxEPTAD4AAAuAAQKfxwAAggACAltGqUyAC8CAAgACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8jAAIGAAgJQhXTKgCOAQAGAAgJQhXTKgCOAQAAAA==.Curbstomped:BAAALgAECgcJCAAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIEAAMJ2hEclgDVAAAEAAMJ2hEclgDVAAAuAAQKfyYAAwQACQkVIl8WALgCAAQACQkMIl8WALgCAB0ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8aAAIUAAUJ8CS9BwCeAQAUAAUJ8CS9BwCeAQAuAAQKf0cABBQACAlhJVIFALgCABQACAnKJFIFALgCAAcABwnvHpUdAGICABMABgk7IpEXAJQBAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgYJCQAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAOAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIPAAUJbhOXWQAsAQAPAAUJbhOXWQAsAQAuAAQKfy4AAg8ACAmUGy0+ABwCAA8ACAmUGy0+ABwCAAAA.Deselle:BAABLgAECn8gAAIPAAkJmQUljABZAQAPAAkJmQUljABZAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8pAAIDAAkJghKfKwDyAQADAAkJghKfKwDyAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAIRAAkJNR36BACbAgARAAkJNR36BACbAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgEJAQAAAA==.',
Do='Dolbyatmos:BAAALgAFFAIJAgAAAA==.Donatelloh:BAABLgAECn8YAAMeAAYJ7Q4eSwDJAAAeAAUJCxEeSwDJAAAQAAUJ9Ar6UQC0AAAAAA==.Dortbraz:BAAALgAECgYJCAABLgAECgkJEQAFAAAAAA==.Dotmeharder:BAABLgAECn8bAAMOAAcJ8xOkegBnAQAOAAcJ8xOkegBnAQAYAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8NAAIJAAMJQBPmOgDKAAAJAAMJQBPmOgDKAAAuAAQKfxsAAwkABgmoIe8jALQBAAkABgnKH+8jALQBAB8ABgmkHjcMAEIBAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJDQAJAEATAA==.Drakuza:BAABLgAFFH8FAAIMAAQJRQvoPADbAAAMAAQJRQvoPADbAAAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g0jDwCyAQAgAAkJ7g0jDwCyAQAAAA==.Draxyl:BAABLgAECn8/AAMEAAkJ4hfSMQAvAgAEAAkJ4hfSMQAvAgAdAAMJaASjUwA+AAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMIAAkJpRC/VAB8AQAIAAkJpRC/VAB8AQAVAAUJwwvdHQCfAAAAAA==.Drogbar:BAABLgAECn8jAAMcAAkJZRgTCwBqAgAcAAkJZRgTCwBqAgAWAAgJYAj1FAAIAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMOAAkJchBiQwDMAQAOAAkJchBiQwDMAQAXAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgMJAwAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn80AAIEAAkJ2yExCgAXAwAEAAkJ2yExCgAXAwAAAA==.Duo:BAABLgAECn83AAMhAAkJHxI/BAClAQAhAAgJmRI/BAClAQAPAAkJcwf4zwDsAAABLgAECggJHgABALUPAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMQAAkJ3CDlCACcAgAQAAkJ3CDlCACcAgAeAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIOAAcJFgQmwADFAAAOAAcJFgQmwADFAAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAFAAAAAA==.Eleidon:BAAALgAECgYJCgAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMZAAkJ7Q8/JgCRAQAZAAgJ8w0/JgCRAQAaAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMMAAgJmRoxHQBXAgAMAAgJmRoxHQBXAgAGAAYJTxTJPAAyAQAAAA==.',
En='Enyô:BAABLgAECn8iAAIPAAkJJRWnQQARAgAPAAkJJRWnQQARAgAAAA==.',
Eo='Eorae:BAAALgAECgIJBAAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAABLgAECn8cAAIPAAcJOxw+SwDzAQAPAAcJOxw+SwDzAQAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAgJGQAIAPsXAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgQJCgABLgAECggJHgABALUPAA==.',
Fa='Faceblock:BAAALgAECgYJBwAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIeAAkJFiZjAQBhAwAeAAkJFiZjAQBhAwABLgAFFAUJFQAfAD8jAA==.Felzugger:BAABLgAFFH8IAAIIAAQJdhOfOQAqAQAIAAQJdhOfOQAqAQABLgAFFAgJGQAGAJoXAA==.',
Fh='Fhalanx:BAAALgAECgUJEAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECggJKAAiAIkYAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAABLgAECn8XAAIPAAYJjR1MYQC2AQAPAAYJjR1MYQC2AQAAAA==.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgYJFwAPAI0dAA==.Flapp:BAABLgAECn8iAAMOAAkJLBTiOgDqAQAOAAkJLBTiOgDqAQAXAAIJsQiDXABZAAABLgAECgYJFwAPAI0dAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIbAAkJ1BkLLAAiAgAbAAkJ1BkLLAAiAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenwings:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgQJCQABLgAFFAUJCAALAIAPAA==.',
Ga='Gaiseric:BAABLgAFFH8FAAIEAAMJwg4XlADXAAAEAAMJwg4XlADXAAAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQZAAgJ1QkmLABoAQAZAAgJ1QkmLABoAQAaAAQJRQNmZACcAAAkAAEJ8gqWhAAuAAAAAA==.Geraldene:BAABLgAECn8VAAIaAAgJMQojMwAsAQAaAAgJMQojMwAsAQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgAECgQJBQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIIAAkJ6hbLMwDrAQAIAAkJ6hbLMwDrAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJOgANAFoaAA==.Grimthruul:BAABLgAECn8XAAIGAAgJTgYeTAD0AAAGAAgJTgYeTAD0AAAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBVJHABuAQATAAcJUBVJHABuAQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAAALgAECgYJEgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMaAAkJ0xH0KQCjAQAaAAcJDRX0KQCjAQAkAAcJAhIUOgAiAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAFAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAFAAAAAA==.Hanharr:BAAALgAECgMJAgAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhETIwCjAQAiAAkJBhETIwCjAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgUJBgAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8TAAIBAAQJVxqlBQBHAQABAAQJVxqlBQBHAQAuAAQKfzUAAgEACQkwHpsEAKcCAAEACQkwHpsEAKcCAAAA.Hiphopuler:BAABLgAECn85AAIaAAgJpBmgGwAAAgAaAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMNAAkJUB6eHwCuAgANAAkJUB6eHwCuAgARAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgUJBwAAAA==.Holyschmit:BAABLgAECn8xAAISAAgJYRrNGQArAgASAAgJYRrNGQArAgAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxOREwCqAQAUAAkJVxOREwCqAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1Rn9CQDFAQAWAAgJ1Rn9CQDFAQAAAA==.Huntris:BAABLgAECn8aAAIcAAkJ6RmaEgAQAgAcAAkJ6RmaEgAQAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAAALgAECgYJEwAAAA==.Hypnotykk:BAABLgAECn8aAAIbAAgJFBTyRwC+AQAbAAgJFBTyRwC+AQAAAA==.',
Ia='Iadygaga:BAAALgAECgcJCAAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Ik='Ikova:BAAALgAECgMJAwAAAA==.',
Im='Immunè:BAAALgAECgIJBAABLgAFFAUJEAAEABAXAA==.Imrah:BAABLgAECn80AAQeAAkJuhMIFwDvAQAeAAkJuhMIFwDvAQAQAAMJ2QazZwBwAAAjAAEJrwPDuwAfAAAAAA==.',
In='Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgABLgAECgkJCQAFAAAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8SAAIaAAQJ4hnbEAAyAQAaAAQJ4hnbEAAyAQAuAAQKfzQAAhoACQlyG3cMAJACABoACQlyG3cMAJACAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8SAAIlAAUJvx7TEQBpAQAlAAUJvx7TEQBpAQAuAAQKfyIAAiUACAkzGPIhAHUBACUACAkzGPIhAHUBAAAA.Jocon:BAABLgAECn8mAAIOAAkJAwdwbgBZAQAOAAkJAwdwbgBZAQAAAA==.Joraan:BAAALgAECgcJCAAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJEAAcALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAcALEOAA==.Kanami:BAABLgAECn8sAAIHAAkJBB+rCwCmAgAHAAkJBB+rCwCmAgAAAA==.Kaori:BAABLgAECn8UAAINAAgJCAg/sgAfAQANAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhlfDAALAgACAAkJDhlfDAALAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Katarr:BAAALgAECgUJBQAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJEAAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx3NCwBbAgAlAAkJbx3NCwBbAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8SAAINAAUJIxIFQAAdAQANAAUJIxIFQAAdAQAuAAQKf0oAAw0ACQl8GuwqAEsCAA0ACQlJGewqAEsCABEABwl0GmAOANABAAAA.Keedron:BAACLgAFFH8ZAAIIAAgJ+xcNDQAsAgAIAAgJ+xcNDQAsAgAuAAQKfxsAAggACAlJJIkLACUDAAgACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIEAAgJqRMwbQCCAQAEAAgJqRMwbQCCAQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8qAAMEAAkJFxxTKABYAgAEAAkJFxxTKABYAgAmAAMJEgnsLABZAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCgUJBwAAAA==.Kilfogg:BAABLgAECn8XAAIGAAcJoxfmKwC5AQAGAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8JAAMJAAMJRwl5QwCsAAAJAAMJRwl5QwCsAAALAAMJeg++HgCmAAAuAAQKfycABAsACQlJGIoMAAQCAAsACQlJGIoMAAQCAAkABgk3EJZHAAEBAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIPAAcJ/R75BgDwAQAPAAcJ/R75BgDwAQAuAAQKfxcAAg8ACAm6IwgVACoDAA8ACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAFAAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAANAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIOAAMJ2APxgwCrAAAOAAMJ2APxgwCrAAAuAAQKfxYAAg4ABwlgFFZSANABAA4ABwlgFFZSANABAAAA.Krymzendeath:BAAALgAECgYJEQABLgAFFAQJEwAUAL8YAA==.Krísztina:BAABLgAECn8pAAQYAAgJWAv9DwBOAQAYAAgJwgj9DwBOAQAXAAgJqAnXEwAEAQAOAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAgJGQAIAPsXAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAFAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIcAAQJsQ4YFAAfAQAcAAQJsQ4YFAAfAQAuAAQKfyQAAhwACQkmGOQHAHICABwACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Lakey:BAABLgAECn8XAAQaAAgJByYRFQAeAgAaAAgJByYRFQAeAgAZAAUJ6SKVGgDsAQAkAAMJOA73SgCuAAABLgAFFAUJHgADAEEWAA==.Lakeyy:BAACLgAFFH8eAAMDAAUJQRb4HQBaAQADAAUJQRb4HQBaAQAiAAQJpxQ+HQAcAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAAALgAECgYJCQABLgAFFAUJHgADAEEWAA==.Lanayrd:BAAALgAECgEJAQAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAANAC0cAA==.Lawrence:BAACLgAFFH8LAAMGAAQJbxDrIwD/AAAGAAQJbxDrIwD/AAAMAAMJkwn7VACTAAAuAAQKfyMAAwYACAmaIcIKAOoCAAYACAmaIcIKAOoCAAwAAwkbDg+eAH0AAAEuAAUUBQkOAAgA0RYA.Lazuril:BAAALgAECgEJAgAAAA==.',
Le='Leanhaum:BAAALgAECgIJBAAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgcJEQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8jAAQEAAgJFRW2GwDlAQAEAAcJrBS2GwDlAQAmAAQJSQ0RDwABAQAdAAEJAAAfGgA0AAAuAAQKfzEAAwQACQmjI/cWAPICAAQACQmZI/cWAPICACYABwkiHSMIAPwBAAAA.Lithe:BAAALgAFFAEJAQABLgAFFAMJEQAGAPMcAA==.',
Lo='Locklear:BAABLgAECn8iAAINAAkJbBYcQgD1AQANAAkJbBYcQgD1AQAAAA==.Logic:BAACLgAFFH8gAAMPAAgJ2xSNEQBDAgAPAAgJqBSNEQBDAgAhAAMJHBSqAgDWAAAuAAQKfysAAg8ACQlvI4USAOYCAA8ACQlvI4USAOYCAAAA.Lolbrez:BAAALgAECgEJAQAAAA==.Lolshield:BAAALgAECgYJCgABLgAFFAUJGAAQAAwfAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8tAAIRAAkJcQqBHAAlAQARAAkJcQqBHAAlAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xkDBQAYAgAnAAgJ9xkDBQAYAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJHgADAEEWAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAUJFgAEAFYYAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAABLgAECn8uAAIEAAkJLx1kJgBhAgAEAAkJLx1kJgBhAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8TAAIIAAYJBheDBADpAQAIAAYJBheDBADpAQAuAAQKfycAAggACQkZIkEIAEgDAAgACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJEwAIAAYXAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIPAAkJbhWtXQDAAQAPAAkJbhWtXQDAAQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAINAAQJLRw7LQBHAQANAAQJLRw7LQBHAQAuAAQKfy0AAg0ACQn9HoIhAHcCAA0ACQn9HoIhAHcCAAAA.Makima:BAAALgAECgUJBQAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIEAAkJ+BzsHgCHAgAEAAkJ+BzsHgCHAgAAAA==.Mamageek:BAABLgAECn8XAAIMAAkJ9hHmKADsAQAMAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAFAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAPAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Mastahunta:BAAALgADCgUJBQABLgAECggJKwAMAJkaAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8iAAINAAgJnxz+PwD8AQANAAgJnxz+PwD8AQAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIdAAgJyBTzGQCEAQAdAAgJyBTzGQCEAQABLgAECgkJHgACACEWAA==.Mcversatile:BAABLgAECn8eAAICAAkJIRb4EADJAQACAAkJIRb4EADJAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIaAAkJrBksEABkAgAaAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8bAAILAAgJ+CABAQAUAwALAAgJ+CABAQAUAwAuAAQKfycAAgsACQkZJkMAAOQDAAsACQkZJkMAAOQDAAAA.Mereoleona:BAAALgAECgcJDwAAAA==.Metalmagus:BAABLgAECn8iAAIPAAgJCRrqSwDxAQAPAAgJCRrqSwDxAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSK3BACYAgAgAAkJTSK3BACYAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAgJGQAIAPsXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8kAAIQAAkJ/hK8HQCvAQAQAAkJ/hK8HQCvAQAAAA==.Misslobster:BAAALgAECggJDwAAAA==.Mistweaver:BAABLgAFFH8HAAIjAAQJ5xkFHwBJAQAjAAQJ5xkFHwBJAQAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJKwAMAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgkJDgAAAA==.Mokoko:BAACLgAFFH8LAAMJAAQJYxlqEAD/AAAJAAQJYxlqEAD/AAAfAAEJVQsfCgBTAAAuAAQKfy8AAwkACQkjHtEFACcDAAkACQkJHtEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJCwAJAGMZAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR1fDgBrAgAiAAkJKR1fDgBrAgADAAQJDxFhggDUAAACAAEJch18WABNAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMeAAkJbCM3CAC6AgAeAAkJbCM3CAC6AgAQAAYJ7hmlKQBfAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgADCgkJCQABLgAECgYJBgAFAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJGAAQAAwfAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAFAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIEAAkJVBvUTQDSAQAEAAkJVBvUTQDSAQAAAA==.Necrota:BAACLgAFFH8GAAIEAAMJhhnLfgD3AAAEAAMJhhnLfgD3AAAuAAQKfxoAAwQACAmVHmpEAO0BAAQACAkWHmpEAO0BAB0AAQlcG5FBAEUAAAEuAAUUBwkbAA8A/R4A.Nekronomicon:BAAALgAECgYJBgAAAA==.Neuron:BAACLgAFFH8dAAIDAAgJPhtvAwDaAgADAAgJPhtvAwDaAgAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8sAAIoAAgJrg6ACgCEAQAoAAgJrg6ACgCEAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgUJDQAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAFAAAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgADCgYJCQAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAISAAgJEiJ1EACKAgASAAgJEiJ1EACKAgAAAA==.Oreyn:BAAALgAECgcJDgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn86AAMNAAkJWhpHKQBSAgANAAkJ2RhHKQBSAgARAAkJKRjdCgAOAgAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJEAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAABLgAECn8bAAIlAAcJ9x4lEgAKAgAlAAcJ9x4lEgAKAgAAAA==.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8VAAMfAAUJPyM6AQCVAQAfAAUJPyM6AQCVAQAJAAMJahncLQD+AAAuAAQKfzoAAx8ACQlRJiYAAIgDAB8ACQlRJiYAAIgDAAkABglqIP8bAO4BAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSNXFgCcAQADAAQJbSNXFgCcAQAuAAQKfzsAAwMACQn9Jb0AANsDAAMACQn9Jb0AANsDACIABgkfEH1AAP0AAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQAAAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAFFAIJAgAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8tAAMaAAcJ+R65FAAjAgAaAAcJ+R65FAAjAgAkAAUJnR+BLQBlAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAgABLgAECgUJCAAFAAAAAA==.',
Po='Poepoe:BAAALgAFFAEJAQAAAA==.Polyrhythm:BAAALgAECgMJBwAAAA==.Polyrhythms:BAAALgAECgEJAQAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIZAAMJlQgvLwC8AAAZAAMJlQgvLwC8AAAuAAQKfx4AAhkABgmxH8MTABACABkABgmxH8MTABACAAAA.Prosthesis:BAAALgAECgEJAQAAAA==.Prrowl:BAAALgAECgUJEAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAAALgAECgkJEQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAANAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8lAAIGAAkJWxdOGQAKAgAGAAkJWxdOGQAKAgAAAA==.Rollos:BAABLgAECn8gAAIOAAkJUBVHMgAKAgAOAAkJUBVHMgAKAgAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxKYLAC2AQAjAAgJCxKYLAC2AQAAAA==.Rookesbane:BAAALgAECgIJAgAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8gAAIJAAgJdyELBACzAgAJAAgJdyELBACzAgAuAAQKfyEAAgkACQm3JfAAAMwDAAkACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8WAAQOAAYJUhWNjQAbAQAOAAUJUhWNjQAbAQAXAAEJ+A1zcAA2AAAYAAEJAABoRAAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJOgANAFoaAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAHAH4aAA==.Saeli:BAAALgAECgEJAgAAAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgYJDwAAAA==.Salvester:BAAALgADCgcJCAABLgAECgcJLQAaAPkeAA==.Samtarkras:BAABLgAECn8tAAILAAkJqhpMBwB9AgALAAkJqhpMBwB9AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAFAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAAALgAFFAMJBAABLgAFFAUJFgAEAFYYAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8IAAIYAAMJxxGPCADlAAAYAAMJxxGPCADlAAAuAAQKf6gABBgACQmPJTwAAGwDABgACQmPJTwAAGwDAA4ABglbGR5aAIoBABcABQnZIAsLAIEBAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8zAAMkAAkJsxiVEABOAgAkAAkJsxiVEABOAgAaAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8JAAIkAAMJThExIwDGAAAkAAMJThExIwDGAAAuAAQKf2oAAiQACQnFJIsCAD4DACQACQnFJIsCAD4DAAEuAAUUCAkZAAYAmhcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAEAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAABLgAFFH8JAAIOAAYJ7BYdIwCcAQAOAAYJ7BYdIwCcAQAAAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIbAAQJSQs9UQDwAAAbAAQJSQs9UQDwAAAuAAQKfyoAAhsACAnIIIQVAJ0CABsACAnIIIQVAJ0CAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJIAAJAHchAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.',
Sl='Slyde:BAABLgAECn8lAAIEAAkJOyD2FwCvAgAEAAkJOyD2FwCvAgAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIEAAYJzBgqPwBlAQAEAAYJzBgqPwBlAQAuAAQKfyUAAgQACAnPIq8VAPoCAAQACAnPIq8VAPoCAAEuAAUUBwkJAAkAlBUA.Smick:BAABLgAECn8cAAISAAgJphJaKgCxAQASAAgJphJaKgCxAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgcJDgAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCN3CgAsAgACAAcJNSF3CgAsAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9OAAIHAAkJjiFxCADSAgAHAAkJjiFxCADSAgAAAA==.Soulfox:BAAALgAECgEJAwABLgAECggJKwAMAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAQJDwAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAAALgAECgcJDgAAAA==.',
Sq='Squidmonk:BAAALgAECgYJBgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8gAAIVAAgJfBPdCwCKAQAVAAgJfBPdCwCKAQABLgAFFAMJCAAYAMcRAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAABLgAECn8UAAIlAAgJgRPRHACiAQAlAAgJgRPRHACiAQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIeAAgJvhsdAQCIAgAeAAgJvhsdAQCIAgAuAAQKfxUAAh4ACAlEH5kMALECAB4ACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Stormsurge:BAAALgAECgIJAwAAAA==.Straydog:BAABLgAECn8uAAMMAAkJ4yREAQC8AwAMAAkJ4yREAQC8AwAGAAEJHhT1lAA8AAAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIEAAkJlhZydgBuAQAEAAkJlhZydgBuAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAFAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAFAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAFAAAAAA==.Superpowers:BAABLgAECn8XAAIQAAgJWR/cDABgAgAQAAgJWR/cDABgAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yHrAwDaAgATAAkJ4yHrAwDaAgAAAA==.Sus:BAABLgAFFH8IAAIbAAQJAwpuYwDCAAAbAAQJAwpuYwDCAAAAAA==.Suzel:BAABLgAECn8XAAIEAAUJSgfn9QCqAAAEAAUJSgfn9QCqAAAAAA==.',
Sw='Sweatmachine:BAAALgADCgMJAwAAAA==.Swoof:BAAALgAECggJEQABLgAFFAUJFgAEAFYYAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn80AAIKAAkJ2RGoFQDNAQAKAAkJ2RGoFQDNAQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAFFAEJAQAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAZAN8OAA==.Synwise:BAABLgAECn80AAIDAAkJxSCfBgBGAwADAAkJxSCfBgBGAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8RAAIbAAQJ6xS4MwA7AQAbAAQJ6xS4MwA7AQAuAAQKfzUAAxsACQlmHXYdAGoCABsACQlmHXYdAGoCABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIeAAgJCxnTGAAcAgAeAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQaAAkJlhpDEABYAgAaAAkJlhpDEABYAgAZAAQJlA22UQCmAAAkAAIJbhJGZAB3AAAAAA==.',
Th='Thanah:BAAALgAECgUJCgAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8SAAIEAAUJXBNNWwAxAQAEAAUJXBNNWwAxAQAuAAQKfyoAAwQACQkdGM1GAOYBAAQACQkdGM1GAOYBACYAAQneCX83AC0AAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAFAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8QAAIVAAQJmBxgAwBEAQAVAAQJmBxgAwBEAQAuAAQKfzkAAhUACQnWHtoDAIYCABUACQnWHtoDAIYCAAAA.Tinytea:BAACLgAFFH8QAAIQAAQJhSNMDwCVAQAQAAQJhSNMDwCVAQAuAAQKf0IAAhAACQkyJaEBAE0DABAACQkyJaEBAE0DAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDAAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8OAAMSAAUJuxswEgCRAQASAAUJuxswEgCRAQANAAEJUQ0UqQBDAAAuAAQKfygAAxIACQkYHeUVAGECABIACAkqH+UVAGECAA0ABQnfEJaxABEBAAAA.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgAECgEJAQAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMHAAYJ0SGHLQD9AQAHAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAEAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgAECgEJAQABLgAECgcJEAAFAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAFAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAFAAAAAA==.Tuckrh:BAAALgAECgQJBQAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgMJAgAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgchIACEAAAUAAMJfgchIACEAAAuAAQKfx4AAhQACQkPD1MZAGQBABQACQkPD1MZAGQBAAEuAAUUBAkLAAYA6gcA.Twippy:BAABLgAFFH8LAAIGAAQJ6gefKQDjAAAGAAQJ6gefKQDjAAAAAA==.',
Ty='Tyanis:BAABLgAECn8aAAINAAYJ1wrz1ADfAAANAAYJ1wrz1ADfAAABLgAECgcJDgAFAAAAAA==.Tyriam:BAABLgAECn8wAAMNAAkJ2ho+KgBOAgANAAgJ2ho+KgBOAgASAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIPAAgJixNaagCgAQAPAAgJixNaagCgAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAFAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Vandy:BAABLgAECn8nAAMKAAkJLAraNwAmAQAKAAYJtwvaNwAmAQAIAAkJXAmfiQD/AAAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8VAAMfAAUJTxGkBAAcAQAfAAUJtg+kBAAcAQAJAAQJJQq9QwCrAAAuAAQKfx4AAh8ACAlhIEgEAMkCAB8ACAlhIEgEAMkCAAAA.Verso:BAABLgAECn8rAAInAAkJWRtNAwBlAgAnAAkJWRtNAwBlAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinushka:BAAALgAECgcJDQAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgkJMwAJABYcAA==.Vitalithry:BAABLgAECn8zAAMJAAkJFhzJDwBkAgAJAAkJDhzJDwBkAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAFAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgMJBAAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAANAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAFAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAABLgAECn8mAAIEAAgJbxUDYQCeAQAEAAgJbxUDYQCeAQAAAA==.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQGAAkJ0R9cCADNAgAGAAkJ0R9cCADNAgAMAAgJ4Bl3IQA5AgAgAAIJ7xHiNwA4AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8RAAIkAAcJFRfkBwDQAQAkAAcJFRfkBwDQAQAuAAQKfzkAAyQACAlFIhMJALgCACQACAlFIhMJALgCABoAAQklJZdZAGMAAAAA.Windoelicker:BAAALgAECgUJDQAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh4RDQC6AgAjAAgJqh4RDQC6AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8SAAIDAAUJywpVJwAZAQADAAUJywpVJwAZAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCggJCAAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMbAAkJ7xpfNAAAAgAbAAgJFxtfNAAAAgAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIEAAQJRBQjZQAkAQAEAAQJRBQjZQAkAQAuAAQKfx4AAwQACAn0Hhw4ABcCAAQACAn0Hhw4ABcCACYAAQlgEIo3AC0AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAISAAkJdgqOLwCRAQASAAkJdgqOLwCRAQAAAA==.Yey:BAABLgAECn8hAAQSAAkJjxnrGAAzAgASAAkJjxnrGAAzAgARAAMJJgGqSAA6AAANAAEJDQSvqwEiAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8fAAIPAAgJ+BBcZgCqAQAPAAgJ+BBcZgCqAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIOAAMJGQyidQDJAAAOAAMJGQyidQDJAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChtDCwAcAgACAAgJChtDCwAcAgAiAAUJvw0LQQD6AAABAAIJpAcTVAAlAAABLgAFFAMJBgAOABkMAA==.Zaydämon:BAABLgAECn8WAAIIAAgJ4R1IHwCWAgAIAAgJ4R1IHwCWAgABLgAFFAMJBgAOABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgkJMAABAL8YAA==.Ziggybeast:BAACLgAFFH8JAAIDAAIJBxmNRwCTAAADAAIJBxmNRwCTAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTIsajAGIAAAIAAwl4DXFYAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCQADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIEAAIJZxjYtQCfAAAEAAIJZxjYtQCfAAAuAAQKf0AAAgQACQlCHd0qAE0CAAQACQlCHd0qAE0CAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
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
