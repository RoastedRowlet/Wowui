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
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8fAAQBAAgJtQ+zGQA6AQABAAcJohCzGQA6AQACAAgJpAnXNgDGAAADAAEJJQf12gAnAAAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8QAAIEAAUJEBcFYgAvAQAEAAUJEBcFYgAvAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAFAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8WAAIGAAUJBQqnaQCmAAAGAAUJBQqnaQCmAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIHAAYJfho7QQA/AQAHAAYJfho7QQA/AQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAHAH4aAA==.',
Al='Alariel:BAABLgAECn8tAAIIAAkJ3xkYJQA3AgAIAAkJ3xkYJQA3AgABLgAFFAQJDgAJALkZAA==.Albesuri:BAAALgAECgUJBQABLgAFFAgJGQAIAPsXAA==.Albskin:BAAALgAECgMJAwAAAA==.Alcazar:BAABLgAECn8sAAMIAAgJfB3/HgBYAgAIAAgJfB3/HgBYAgAKAAEJAAB5hAAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAILAAgJGwj8HwB+AQALAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJHwALANcZAA==.Alerys:BAAALgAFFAIJAgABLgAFFAgJHwALANcZAA==.Alliar:BAABLgAECn8nAAMMAAkJxBzjJgAhAgAMAAkJxBzjJgAhAgAGAAIJLgnvjwBOAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAFAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJHwALANcZAA==.',
Am='Amalek:BAAALgAECgEJAQAAAA==.Amerha:BAABLgAECn8eAAMMAAkJuQ1iOgDBAQAMAAkJuQ1iOgDBAQAGAAIJiwanlABHAAAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAACLgAFFH8JAAINAAMJ0B+oQAAkAQANAAMJ0B+oQAAkAQAuAAQKfxwAAg0ACAnRIa0xADcCAA0ACAnRIa0xADcCAAEuAAUUAwkJAAkARwkA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURHneQDGAAADAAQJURHneQDGAAAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8VAAIKAAcJORcoGwCgAQAKAAcJORcoGwCgAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgAECgEJAQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJPQAOAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8lAAIPAAUJRB7FRABiAQAPAAUJRB7FRABiAQAuAAQKfy4AAg8ACAnbIt4kAIcCAA8ACAnbIt4kAIcCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8fAAIGAAkJvhduGgALAgAGAAkJvhduGgALAgABLgAECgEJAQAFAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJDQABLgAECgEJAQAFAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAFAAAAAA==.Atrell:BAABLgAECn8eAAINAAkJrRigSADqAQANAAkJrRigSADqAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgYJBgABLgAFFAUJGgAQAAwfAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJDwAAAA==.Balrock:BAAALgAECgEJAQAAAA==.Balthromaw:BAABLgAECn8xAAIOAAkJwho/JABNAgAOAAkJwho/JABNAgAAAA==.Bananarang:BAAALgADCgUJBQAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJBQAAAA==.Barli:BAAALgAECgIJAgAAAA==.Barqs:BAAALgAFFAIJBAAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSKVJgAYAgADAAYJGSKVJgAYAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAHAPwcAA==.Beardwaffle:BAABLgAECn8rAAIHAAkJ/BzQEwBSAgAHAAkJ/BzQEwBSAgAAAA==.Bearlando:BAAALgAFFAQJBAABLgAFFAgJHQAGANAXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQNAAYJiyLJSADpAQANAAUJiyLJSADpAQARAAUJyw9XKgC5AAASAAMJdQ7EbQB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIPAAMJ1wRUlQCjAAAPAAMJ1wRUlQCjAAAuAAQKfxQAAg8ABwkyEx20AHYBAA8ABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx0FFAA3AQATAAQJixoFFAA3AQAHAAQJMhpTIAAsAQAuAAQKfygABAcACAkOJC0UAKwCAAcACAl0Iy0UAKwCABQAAwmQJFkiABkBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAJAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIIAAkJFBiXMQD8AQAIAAkJFBiXMQD8AQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodemongar:BAAALgADCgMJAwAAAA==.Bloodhoundss:BAABLgAECn8nAAIHAAkJhRiMGQAgAgAHAAkJhRiMGQAgAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBVRDACNAQAVAAgJFBVRDACNAQAAAA==.',
Bo='Bob:BAACLgAFFH8ZAAIIAAYJCBZ4CQCTAQAIAAYJCBZ4CQCTAQAuAAQKfyYAAggACQk+IdoIAEIDAAgACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8nAAIMAAkJdxfOIwAzAgAMAAkJdxfOIwAzAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAFFAEJAQAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8aAAIHAAkJjg7DKAC2AQAHAAkJjg7DKAC2AQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8IAAIWAAIJihxbIwCMAAAWAAIJihxbIwCMAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAECgkJHwAMAHUZAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAAALgAFFAIJBAAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Cainn:BAAALgAECgIJAgABLgAFFAUJEgANACMSAA==.Caliginosity:BAABLgAECn8YAAIXAAcJeRc2DAD/AQAXAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8uAAICAAkJxR8tBADVAgACAAkJxR8tBADVAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCQAAAA==.Chemotherapy:BAAALgAECgUJBgAAAA==.Chillingsly:BAAALgAECgEJAQABLgAFFAMJCQAYAMcRAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIHAAkJZB0QFABPAgAHAAkJZB0QFABPAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAIRAAMJ5hNsCwC7AAARAAMJ5hNsCwC7AAAuAAQKfxwAAhEACQm7GkwIAFUCABEACQm7GkwIAFUCAAAA.Condemnation:BAACLgAFFH8QAAIZAAQJxQ85JwAJAQAZAAQJxQ85JwAJAQAuAAQKfzgAAxkACQmjGhYQAGwCABkACQmQFhYQAGwCABoACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJDAAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAFAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAFAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8aAAISAAkJ9QrJMwCBAQASAAkJ9QrJMwCBAQAAAA==.',
Cr='Crayak:BAACLgAFFH8QAAIKAAQJTxt/DQA3AQAKAAQJTxt/DQA3AQAuAAQKfzEAAwoACQnmIgUFAPECAAoACQnmIgUFAPECAAgABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECggJLAAIAHwdAA==.Crossbones:BAABLgAECn8qAAMbAAgJlxx8IwBSAgAbAAgJlxx8IwBSAgAcAAQJWA96PADbAAAAAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8KAAIIAAUJCxEIUgDxAAAIAAUJCxEIUgDxAAAuAAQKfxwAAggACAltGqUyAC8CAAgACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8jAAIGAAgJQhXULACNAQAGAAgJQhXULACNAQAAAA==.Curbstomped:BAAALgAECgcJCAAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAABLgAECn8VAAIPAAcJMQ9inAA+AQAPAAcJMQ9inAA+AQAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIEAAMJ2hF0ogDQAAAEAAMJ2hF0ogDQAAAuAAQKfyYAAwQACQkVIlQYALICAAQACQkMIlQYALICAB0ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8bAAIUAAUJ8CRFCQCTAQAUAAUJ8CRFCQCTAQAuAAQKf0cABBQACAlhJcUFALQCABQACAnKJMUFALQCAAcABwnvHpUdAGICABMABgk7Io4YAJIBAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgcJCwAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAOAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIPAAUJbhMMYAArAQAPAAUJbhMMYAArAQAuAAQKfy4AAg8ACAmUG0FAABkCAA8ACAmUG0FAABkCAAAA.Deselle:BAABLgAECn8gAAIPAAkJmQXSkQBRAQAPAAkJmQXSkQBRAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8pAAIDAAkJghIILQDxAQADAAkJghIILQDxAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAIRAAkJNR1bBQCZAgARAAkJNR1bBQCZAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgEJAQAAAA==.',
Do='Dolbyatmos:BAAALgAFFAIJAgAAAA==.Donatelloh:BAABLgAECn8YAAMeAAYJ7Q4HTgDJAAAeAAUJCxEHTgDJAAAQAAUJ9AqwUwCzAAAAAA==.Dortbraz:BAAALgAECgYJCAABLgAECgkJFQANACsOAA==.Dotmeharder:BAABLgAECn8bAAMOAAcJ8xOkegBnAQAOAAcJ8xOkegBnAQAYAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8NAAIJAAMJQBMiQADBAAAJAAMJQBMiQADBAAAuAAQKfxsAAwkABgmoIQIlALQBAAkABgnKHwIlALQBAB8ABgmkHq0MAEABAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJDQAJAEATAA==.Drakuza:BAABLgAFFH8IAAIMAAQJQBEbNAAKAQAMAAQJQBEbNAAKAQAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g0AEACtAQAgAAkJ7g0AEACtAQAAAA==.Draxyl:BAABLgAECn9CAAMEAAkJrxigLwA+AgAEAAkJrxigLwA+AgAdAAMJaARDVwA9AAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMIAAkJpRCaVwB9AQAIAAkJpRCaVwB9AQAVAAUJwws7HwCfAAAAAA==.Drogbar:BAABLgAECn8kAAMcAAkJzxgQCwBuAgAcAAkJzxgQCwBuAgAWAAgJYAjoFQAGAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMOAAkJchD/RgDEAQAOAAkJchD/RgDEAQAXAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgYJCQAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn80AAIEAAkJ2yEnCwATAwAEAAkJ2yEnCwATAwAAAA==.Duo:BAABLgAECn8+AAMhAAkJIBPvAwDCAQAhAAgJ7xTvAwDCAQAPAAkJcwcn0wDpAAABLgAECggJHwABALUPAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMQAAkJ3CBjCQCZAgAQAAkJ3CBjCQCZAgAeAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIOAAcJFgTrxQDCAAAOAAcJFgTrxQDCAAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAFAAAAAA==.Eleidon:BAAALgAECgYJCgAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMZAAkJ7Q8XKACPAQAZAAgJ8w0XKACPAQAaAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMMAAgJmRqVHgBWAgAMAAgJmRqVHgBWAgAGAAYJTxSkPwAyAQAAAA==.',
En='Enyô:BAABLgAECn8iAAIPAAkJJRXrQwANAgAPAAkJJRXrQwANAgAAAA==.',
Eo='Eorae:BAAALgAECgIJBgAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAABLgAECn8cAAIPAAcJOxx/TQDwAQAPAAcJOxx/TQDwAQAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAgJGQAIAPsXAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgQJCgABLgAECggJHwABALUPAA==.',
Fa='Faceblock:BAAALgAECgYJCAAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIeAAkJFiaLAQBfAwAeAAkJFiaLAQBfAwABLgAFFAUJGgAfAD8jAA==.Felzugger:BAABLgAFFH8IAAIIAAQJdhORQAAfAQAIAAQJdhORQAAfAQABLgAFFAgJHQAGANAXAA==.',
Fh='Fhalanx:BAAALgAECgUJEAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECggJKAAiAIkYAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAABLgAECn8XAAIPAAYJjR3cYwCzAQAPAAYJjR3cYwCzAQAAAA==.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgYJFwAPAI0dAA==.Flapp:BAABLgAECn8iAAMOAAkJLBQkPgDiAQAOAAkJLBQkPgDiAQAXAAIJsQiDXABZAAABLgAECgYJFwAPAI0dAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIbAAkJ1BlTLwAaAgAbAAkJ1BlTLwAaAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenlight:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgUJCgABLgAFFAUJCAALAIAPAA==.Furyiosa:BAAALgADCgEJAQAAAA==.',
Ga='Gaiseric:BAABLgAFFH8HAAIEAAMJ7xJzlwDcAAAEAAMJ7xJzlwDcAAAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQZAAgJ1QlrLgBlAQAZAAgJ1QlrLgBlAQAaAAQJRQNmZACcAAAkAAEJ8goOigAuAAAAAA==.Geraldene:BAABLgAECn8VAAIaAAgJMQrrNAAqAQAaAAgJMQrrNAAqAQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgAECgQJBQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIIAAkJ6hagNQDsAQAIAAkJ6hagNQDsAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJRQARAMgaAA==.Grimthruul:BAABLgAECn8cAAIGAAkJGAhtPQA7AQAGAAkJGAhtPQA7AQAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBVyHQBtAQATAAcJUBVyHQBtAQAAAA==.Grumpig:BAAALgAECgUJDQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAAALgAECgYJEgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMaAAkJ0xH0KQCjAQAaAAcJDRX0KQCjAQAkAAcJAhK1PQAYAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAFAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAFAAAAAA==.Hanharr:BAAALgAECgMJAgAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhGuJAChAQAiAAkJBhGuJAChAQAAAA==.Heyro:BAAALgAECgEJAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgUJBwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8UAAIBAAQJVxqWBgA+AQABAAQJVxqWBgA+AQAuAAQKfzUAAgEACQkwHhUFAKICAAEACQkwHhUFAKICAAAA.Hiphopuler:BAABLgAECn85AAIaAAgJpBmgGwAAAgAaAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMNAAkJUB6eHwCuAgANAAkJUB6eHwCuAgARAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgUJCAAAAA==.Holyschmit:BAABLgAECn8xAAISAAgJYRr2GgAqAgASAAgJYRr2GgAqAgAAAA==.Holysmite:BAAALgADCgEJAQAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxN4FACnAQAUAAkJVxN4FACnAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RlhCgDEAQAWAAgJ1RlhCgDEAQAAAA==.Huntris:BAABLgAECn8aAAIcAAkJ6Rm8EwAIAgAcAAkJ6Rm8EwAIAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAABLgAECn8dAAMMAAcJ3QvCZwAfAQAMAAcJ3QvCZwAfAQAGAAUJRAQmeQB9AAAAAA==.Hypnotykk:BAABLgAECn8aAAIbAAgJFBQ/TQC2AQAbAAgJFBQ/TQC2AQAAAA==.',
Ia='Iadygaga:BAAALgAECgcJCAAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Ik='Ikova:BAAALgAECgMJBAAAAA==.',
Im='Immunè:BAAALgAECgIJBAABLgAFFAUJEAAEABAXAA==.Imrah:BAABLgAECn80AAQeAAkJuhN/GADrAQAeAAkJuhN/GADrAQAQAAMJ2QbMagBtAAAjAAEJrwOVygAfAAAAAA==.',
In='Incarnate:BAAALgAECgEJAgABLgAECgYJDwAFAAAAAA==.Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgABLgAECgkJCQAFAAAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8TAAIaAAQJ4hkAEwArAQAaAAQJ4hkAEwArAQAuAAQKfzQAAhoACQlyG2MNAI0CABoACQlyG2MNAI0CAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8TAAIlAAUJvx5TFABhAQAlAAUJvx5TFABhAQAuAAQKfyIAAiUACAkzGGkjAHUBACUACAkzGGkjAHUBAAAA.Jocon:BAABLgAECn8mAAIOAAkJAwcQcwBTAQAOAAkJAwcQcwBTAQAAAA==.Joraan:BAAALgAECgcJCAAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJEAAcALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAcALEOAA==.Kanami:BAABLgAECn8sAAIHAAkJBB97DAChAgAHAAkJBB97DAChAgAAAA==.Kaori:BAABLgAECn8UAAINAAgJCAg/sgAfAQANAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhk5DQAKAgACAAkJDhk5DQAKAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Katarr:BAAALgAECgUJBQAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgcJFQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx2LDABaAgAlAAkJbx2LDABaAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8SAAINAAUJIxLdRgAZAQANAAUJIxLdRgAZAQAuAAQKf0oAAw0ACQl8GrQtAEgCAA0ACQlJGbQtAEgCABEABwlyGgUPAM8BAAAA.Keedron:BAACLgAFFH8ZAAIIAAgJ+xcrEQAbAgAIAAgJ+xcrEQAbAgAuAAQKfxsAAggACAlJJIkLACUDAAgACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIEAAgJqRMlcwB7AQAEAAgJqRMlcwB7AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8yAAMEAAkJDx8UFgDBAgAEAAkJDx8UFgDBAgAmAAMJEgllMABWAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCggJDgAAAA==.Kilfogg:BAABLgAECn8XAAIGAAcJoxfmKwC5AQAGAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8JAAMJAAMJRwnGSACkAAAJAAMJRwnGSACkAAALAAMJeg9xIACdAAAuAAQKfycABAsACQlJGOgMAAECAAsACQlJGOgMAAECAAkABgk3EI9JAAEBAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIPAAcJ/R75BgDwAQAPAAcJ/R75BgDwAQAuAAQKfxcAAg8ACAm6IwgVACoDAA8ACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAFAAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAANAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIOAAMJ2AMPiwCpAAAOAAMJ2AMPiwCpAAAuAAQKfxYAAg4ABwlgFFZSANABAA4ABwlgFFZSANABAAAA.Krymzendeath:BAABLgAECn8ZAAMRAAcJ6AtlIgD+AAARAAcJ6AtlIgD+AAANAAUJcgICSQFgAAABLgAFFAQJFwAUAL8YAA==.Krísztina:BAABLgAECn8pAAQYAAgJWAsJEQBNAQAYAAgJwggJEQBNAQAXAAgJqAkFFQD/AAAOAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAgJGQAIAPsXAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAFAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIcAAQJsQ6/FQAeAQAcAAQJsQ6/FQAeAQAuAAQKfyQAAhwACQkmGOQHAHICABwACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Lakey:BAABLgAECn8XAAQaAAgJByYpFgAdAgAaAAgJByYpFgAdAgAZAAUJ6SLtGwDsAQAkAAMJOA73SgCuAAABLgAFFAUJHgADAEEWAA==.Lakeyy:BAACLgAFFH8eAAMDAAUJQRYYIQBIAQADAAUJQRYYIQBIAQAiAAQJpxQOIAAXAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAAALgAFFAQJBAABLgAFFAUJHgADAEEWAA==.Lanayrd:BAAALgAECgEJAQAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAANAC0cAA==.Lawrence:BAACLgAFFH8MAAMGAAUJbxDSJwDwAAAGAAQJbxDSJwDwAAAMAAQJ7QecRgDLAAAuAAQKfyMAAwYACAmaIcIKAOoCAAYACAmaIcIKAOoCAAwAAwkbDkikAH0AAAAA.Lazuril:BAAALgAECgEJAgAAAA==.',
Le='Leanhaum:BAAALgAECgIJBAAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgcJEQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8pAAQEAAgJ1xYzEQBCAgAEAAcJ1xYzEQBCAgAmAAQJSQ0+EQABAQAdAAEJAAAfGgA0AAAuAAQKfzEAAwQACQmjI/cWAPICAAQACQmZI/cWAPICACYABwkiHeUIAPkBAAAA.Lithe:BAAALgAFFAIJAgABLgAFFAQJFAAGAHMaAA==.',
Lo='Locklear:BAABLgAECn8iAAINAAkJbBbMRQDyAQANAAkJbBbMRQDyAQAAAA==.Logic:BAACLgAFFH8iAAMPAAgJsRWRFgA5AgAPAAgJqBSRFgA5AgAhAAMJEBbgAgDoAAAuAAQKfysAAg8ACQlvI7UTAOECAA8ACQlvI7UTAOECAAAA.Lolbrez:BAAALgAECgEJAQAAAA==.Lolshield:BAAALgAECgYJCgABLgAFFAUJGgAQAAwfAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8xAAIRAAkJjgq6HAAsAQARAAkJjgq6HAAsAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xkqBQAZAgAnAAgJ9xkqBQAZAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJHgADAEEWAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAYJCQAbAMAFAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAABLgAECn8uAAIEAAkJLx2EKABdAgAEAAkJLx2EKABdAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8aAAIIAAcJdxqDBADpAQAIAAcJdxqDBADpAQAuAAQKfycAAggACQkZIkEIAEgDAAgACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAcJGgAIAHcaAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIPAAkJbhVpYAC8AQAPAAkJbhVpYAC8AQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAINAAQJLRyzMwBBAQANAAQJLRyzMwBBAQAuAAQKfy0AAg0ACQn9HtwjAHQCAA0ACQn9HtwjAHQCAAAA.Makima:BAAALgAECgUJBQAAAA==.Malazen:BAAALgAECgEJAQAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIEAAkJ+ByeIACEAgAEAAkJ+ByeIACEAgAAAA==.Mamageek:BAABLgAECn8XAAIMAAkJ9hHmKADsAQAMAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAFAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAPAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Mastahunta:BAAALgAECgMJAwABLgAECggJKwAMAJkaAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8kAAINAAkJcB09JgBpAgANAAkJcB09JgBpAgAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIdAAgJyBRnGwB/AQAdAAgJyBRnGwB/AQABLgAECgkJHgACACEWAA==.Mcversatile:BAABLgAECn8eAAICAAkJIRYAEgDJAQACAAkJIRYAEgDJAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIaAAkJrBksEABkAgAaAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8iAAILAAgJBCFRAQASAwALAAgJBCFRAQASAwAuAAQKfycAAgsACQkZJksAAN8DAAsACQkZJksAAN8DAAAA.Mereoleona:BAAALgAECgcJEAAAAA==.Metalmagus:BAABLgAECn8iAAIPAAgJCRoCTgDuAQAPAAgJCRoCTgDuAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSINBQCUAgAgAAkJTSINBQCUAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAgJGQAIAPsXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8kAAIQAAkJ/hLSHgCtAQAQAAkJ/hLSHgCtAQAAAA==.Misslobster:BAAALgAECggJDwAAAA==.Mistweaver:BAABLgAFFH8IAAIjAAQJ5xl/IwBDAQAjAAQJ5xl/IwBDAQAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJKwAMAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgkJDgAAAA==.Mokoko:BAACLgAFFH8OAAMJAAQJuRlqEAD/AAAJAAQJuRlqEAD/AAAfAAEJVQsfCgBTAAAuAAQKfzEAAwkACQmhIdEFACcDAAkACQmHIdEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJDgAJALkZAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR0uDwBqAgAiAAkJKR0uDwBqAgADAAQJDxFhggDUAAACAAEJch3aXgBNAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMeAAkJbCOxCAC4AgAeAAkJbCOxCAC4AgAQAAYJ7hnIKgBeAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgAECgMJAwABLgAECgYJBgAFAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJGgAQAAwfAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAFAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIEAAkJVBtzUADQAQAEAAkJVBtzUADQAQAAAA==.Necrota:BAACLgAFFH8IAAIEAAMJ1Ru5gwD9AAAEAAMJ1Ru5gwD9AAAuAAQKfxoAAwQACAmVHsBGAOsBAAQACAkWHsBGAOsBAB0AAQlcG5FBAEUAAAEuAAUUBwkbAA8A/R4A.Nekronomicon:BAAALgAECgYJBwAAAA==.Neuron:BAACLgAFFH8dAAIDAAgJPht3BADJAgADAAgJPht3BADJAgAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.Nexgen:BAAALgAECgMJAwAAAA==.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8uAAIoAAkJnxAwBwDoAQAoAAkJnxAwBwDoAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgUJDgAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAFAAAAAA==.',
Nu='Nucwel:BAAALgAECgMJAwAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgADCgYJCQAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAISAAgJEiJREQCIAgASAAgJEiJREQCIAgAAAA==.Oreyn:BAAALgAECgcJDgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn9FAAMRAAkJyBodCQA9AgANAAkJ2RjjKwBPAgARAAkJCBkdCQA9AgAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJEAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAABLgAECn8bAAIlAAcJ9x47EwAHAgAlAAcJ9x47EwAHAgAAAA==.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8aAAMfAAUJPyOMAQCNAQAfAAUJPyOMAQCNAQAJAAQJfB09HgBnAQAuAAQKfzwAAx8ACQlUJi0AAIYDAB8ACQlRJi0AAIYDAAkABgnPIN4bAPUBAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSM3GACVAQADAAQJbSM3GACVAQAuAAQKfzsAAwMACQn9JdQAANoDAAMACQn9JdQAANoDACIABgkfECNDAPwAAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQAAAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAFFAIJAgAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8tAAMaAAcJ+R7kFQAgAgAaAAcJ+R7kFQAgAgAkAAUJnR/eLgBjAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAgABLgAECgUJCAAFAAAAAA==.',
Po='Poepoe:BAAALgAFFAEJAQAAAA==.Polyrhythm:BAAALgAFFAEJAQAAAA==.Polyrhythms:BAAALgAECgEJAQAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIZAAMJlQgrMwC5AAAZAAMJlQgrMwC5AAAuAAQKfx4AAhkABgmxH8MTABACABkABgmxH8MTABACAAAA.Prosthesis:BAAALgAECgEJAQAAAA==.Prrowl:BAAALgAECgUJEAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAABLgAECn8VAAINAAkJKw5vZQCiAQANAAkJKw5vZQCiAQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAANAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8lAAIGAAkJWxekGgAJAgAGAAkJWxekGgAJAgAAAA==.Rollos:BAABLgAECn8gAAIOAAkJUBXzNAAEAgAOAAkJUBXzNAAEAgAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxKHLwC2AQAjAAgJCxKHLwC2AQAAAA==.Rookesbane:BAAALgAECgIJAgAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8iAAIJAAgJdyEvBQCsAgAJAAgJdyEvBQCsAgAuAAQKfyEAAgkACQm3JfAAAMwDAAkACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8WAAQOAAYJUhUelAATAQAOAAUJUhUelAATAQAXAAEJ+A1zcAA2AAAYAAEJAABrSAAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJRQARAMgaAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAHAH4aAA==.Saeli:BAAALgAECgEJAgAAAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgYJDwAAAA==.Salvester:BAAALgAECgIJAgABLgAECgcJLQAaAPkeAA==.Samtarkras:BAABLgAECn8tAAILAAkJqhp+BwB8AgALAAkJqhp+BwB8AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAFAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAABLgAFFH8JAAIbAAYJwAWANAA+AQAbAAYJwAWANAA+AQAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8JAAIYAAMJxxHlCQDYAAAYAAMJxxHlCQDYAAAuAAQKf6wABBgACQmPJUUAAGkDABgACQmPJUUAAGkDABcABgkhIJ4HANQBAA4ABglbGelbAIoBAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8zAAMkAAkJsxi8EQBIAgAkAAkJsxi8EQBIAgAaAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8JAAIkAAMJThEpJgDCAAAkAAMJThEpJgDCAAAuAAQKf2oAAiQACQnFJMoCADkDACQACQnFJMoCADkDAAEuAAUUCAkdAAYA0BcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAEAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAABLgAFFH8KAAIOAAYJ7BbfKQCUAQAOAAYJ7BbfKQCUAQABLgAFFAcJFAAPAJAfAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIbAAQJSQveWQDpAAAbAAQJSQveWQDpAAAuAAQKfyoAAhsACAnIIDsXAJgCABsACAnIIDsXAJgCAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJIgAJAHchAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.Skynomad:BAAALgAECgEJAgABLgAECgYJCgAFAAAAAA==.',
Sl='Slyde:BAABLgAECn8pAAIEAAkJvCGADwDuAgAEAAkJvCGADwDuAgAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIEAAYJzBg8FwBIAQAEAAYJzBg8FwBIAQAuAAQKfyUAAgQACAnPIq8VAPoCAAQACAnPIq8VAPoCAAAA.Smick:BAABLgAECn8cAAISAAgJphLEKwCwAQASAAgJphLEKwCwAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgcJDgAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCNICwAqAgACAAcJNSFICwAqAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9OAAIHAAkJjiE8CQDNAgAHAAkJjiE8CQDNAgAAAA==.Soulfox:BAAALgAECgEJAwABLgAECggJKwAMAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAUJEwAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAAALgAECgcJDwAAAA==.',
Sq='Squidmonk:BAAALgAECggJCQAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8gAAIVAAgJfBN5DACKAQAVAAgJfBN5DACKAQABLgAFFAMJCQAYAMcRAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAABLgAECn8UAAIlAAgJgRMpHgChAQAlAAgJgRMpHgChAQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIeAAgJvht9AQB7AgAeAAgJvht9AQB7AgAuAAQKfxUAAh4ACAlEH5kMALECAB4ACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Stormsurge:BAAALgAECgIJBAAAAA==.Straydog:BAABLgAECn8uAAMMAAkJ4yR6AQC5AwAMAAkJ4yR6AQC5AwAGAAEJHhQFnAA8AAAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIEAAkJlhYOfQBmAQAEAAkJlhYOfQBmAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAFAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAFAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAFAAAAAA==.Superpowers:BAABLgAECn8XAAIQAAgJWR99DQBeAgAQAAgJWR99DQBeAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yFABADXAgATAAkJ4yFABADXAgAAAA==.Sus:BAABLgAFFH8IAAIbAAQJAwqfbAC9AAAbAAQJAwqfbAC9AAAAAA==.Suzel:BAABLgAECn8XAAIEAAUJSgft/wCnAAAEAAUJSgft/wCnAAAAAA==.',
Sw='Sweatmachine:BAAALgADCgMJAwAAAA==.Swoof:BAAALgAECggJEQABLgAFFAYJCQAbAMAFAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn88AAIKAAkJhxQaEwD6AQAKAAkJhxQaEwD6AQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAFFAIJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAZAN8OAA==.Synwise:BAABLgAECn83AAIDAAkJaiEdBgBTAwADAAkJaiEdBgBTAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8SAAIbAAQJGhaFOQA0AQAbAAQJGhaFOQA0AQAuAAQKfzUAAxsACQlmHR0gAGMCABsACQlmHR0gAGMCABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIeAAgJCxnTGAAcAgAeAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQaAAkJlhpMEQBVAgAaAAkJlhpMEQBVAgAZAAQJlA2TVQCmAAAkAAIJbhJYaAB2AAAAAA==.',
Th='Thanah:BAAALgAECgUJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8SAAIEAAUJXBOVYwAtAQAEAAUJXBOVYwAtAQAuAAQKfyoAAwQACQkdGJxKAOABAAQACQkdGJxKAOABACYAAQneCY87AC0AAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAFAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8QAAIVAAQJmBzXAwBBAQAVAAQJmBzXAwBBAQAuAAQKfzkAAhUACQnWHiEEAIUCABUACQnWHiEEAIUCAAAA.Tinytea:BAACLgAFFH8QAAIQAAQJhSOHEQCQAQAQAAQJhSOHEQCQAQAuAAQKf0IAAhAACQkyJcgBAEsDABAACQkyJcgBAEsDAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDAAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8OAAMSAAUJuxvXEwCFAQASAAUJuxvXEwCFAQANAAEJUQ1JtABDAAAuAAQKfygAAxIACQkYHeUVAGECABIACAkqH+UVAGECAA0ABQnfEMq4ABABAAAA.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgAECgEJAQAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMHAAYJ0SGHLQD9AQAHAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAEAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgAECgEJAQABLgAECgcJEAAFAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAFAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAFAAAAAA==.Tuckrh:BAAALgAECgYJBwAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgUJCAAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgfSIgB7AAAUAAMJfgfSIgB7AAAuAAQKfx4AAhQACQkPD5caAGEBABQACQkPD5caAGEBAAEuAAUUBAkLAAYA6gcA.Twippy:BAABLgAFFH8LAAIGAAQJ6gcGLgDVAAAGAAQJ6gcGLgDVAAAAAA==.',
Ty='Tyanis:BAABLgAECn8aAAINAAYJ1wqb3ADfAAANAAYJ1wqb3ADfAAABLgAECgcJDgAFAAAAAA==.Tyriam:BAABLgAECn8wAAMNAAkJ2hoYLQBKAgANAAgJ2hoYLQBKAgASAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIPAAgJixPSbACeAQAPAAgJixPSbACeAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAFAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Vandy:BAABLgAECn8nAAMKAAkJLAraNwAmAQAKAAYJtwvaNwAmAQAIAAkJXAlrjgD/AAAAAA==.Varodonaris:BAAALgAECgUJCAAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8ZAAMfAAUJMBMnBQASAQAfAAUJtg8nBQASAQAJAAQJ6BZqOgDaAAAuAAQKfx8AAx8ACAlhIEgEAMkCAB8ACAlhIEgEAMkCAAkAAQlIGtOEAE4AAAAA.Verso:BAABLgAECn8rAAInAAkJWRtqAwBnAgAnAAkJWRtqAwBnAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinushka:BAAALgAECggJDwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgkJMwAJABYcAA==.Vitalithry:BAABLgAECn8zAAMJAAkJFhxKEABkAgAJAAkJDhxKEABkAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAFAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgMJBAAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAANAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAFAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAACLgAFFH8GAAIEAAMJvQ2QoADSAAAEAAMJvQ2QoADSAAAuAAQKfycAAgQACAn7FS1jAJ8BAAQACAn7FS1jAJ8BAAAA.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQGAAkJ0R8BCQDLAgAGAAkJ0R8BCQDLAgAMAAgJ4BkrIwA3AgAgAAIJ7xG0OwA4AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8RAAIkAAcJFRdNCQDGAQAkAAcJFRdNCQDGAQAuAAQKfzkAAyQACAlFIp4JALQCACQACAlFIp4JALQCABoAAQklJYRcAGMAAAAA.Windoelicker:BAAALgAECgYJEgAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh7iDQC7AgAjAAgJqh7iDQC7AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8UAAIDAAYJQQuqIABKAQADAAYJQQuqIABKAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCggJCAAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMbAAkJ7xpuOAD4AQAbAAgJFxtuOAD4AQAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIEAAQJRBS4bgAeAQAEAAQJRBS4bgAeAQAuAAQKfx4AAwQACAn0Hv46ABICAAQACAn0Hv46ABICACYAAQlgECg7AC0AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAISAAkJdgodMQCQAQASAAkJdgodMQCQAQAAAA==.Yey:BAABLgAECn8hAAQSAAkJjxkQGgAyAgASAAkJjxkQGgAyAgARAAMJJgFnSwA6AAANAAEJDQRRuwEiAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8iAAIPAAkJ8g9uUwDfAQAPAAkJ8g9uUwDfAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIOAAMJGQypfADGAAAOAAMJGQypfADGAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChsXDAAbAgACAAgJChsXDAAbAgAiAAUJvw2qQwD5AAABAAIJpAc5WgAlAAABLgAFFAMJBgAOABkMAA==.Zaydämon:BAABLgAECn8WAAIIAAgJ4R1IHwCWAgAIAAgJ4R1IHwCWAgABLgAFFAMJBgAOABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zello:BAAALgAECgYJBgAAAA==.Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgkJMAABAL8YAA==.Ziggybeast:BAACLgAFFH8KAAIDAAIJBxnfSACRAAADAAIJBxnfSACRAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTImOnAGIAAAIAAwl4DXdeAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCgADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIEAAIJZxhAwgCfAAAEAAIJZxhAwgCfAAAuAAQKf0MAAgQACQlMHZErAFACAAQACQlMHZErAFACAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
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
