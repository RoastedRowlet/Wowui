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

local lookup = {'Druid-Feral','Druid-Guardian','Druid-Restoration','Paladin-Holy','DeathKnight-Unholy','Unknown-Unknown','Shaman-Elemental','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','DemonHunter-Havoc','Evoker-Preservation','Shaman-Restoration','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Monk-Brewmaster','Paladin-Protection','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Blood','Evoker-Devastation','Shaman-Enhancement','Mage-Fire','Druid-Balance','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8fAAQBAAgJtQ8vGgA8AQABAAcJohAvGgA8AQACAAgJpAk0OADGAAADAAEJJQf12gAnAAAAAA==.',
Ac='Acrux:BAAALgADCgQJBAABLgAECgkJHgAEAKESAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8QAAIFAAUJEBc8ZgArAQAFAAUJEBc8ZgArAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAGAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8cAAIHAAUJ3Qq0AgCsAAAHAAUJ3Qq0AgCsAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIIAAYJfhrpQQA9AQAIAAYJfhrpQQA9AQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAIAH4aAA==.',
Al='Alariel:BAABLgAECn8tAAIJAAkJ3xmkJQA3AgAJAAkJ3xmkJQA3AgABLgAFFAQJEgAKALMeAA==.Alary:BAAALgAECgEJAQABLgAFFAQJBAAGAAAAAA==.Albesuri:BAAALgAECgUJBQABLgAFFAgJGQAJAPsXAA==.Albskin:BAAALgAECgMJAwAAAA==.Alcazar:BAABLgAECn8sAAMJAAgJfB2IHwBYAgAJAAgJfB2IHwBYAgALAAEJAAAkiAAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAIMAAgJGwj8HwB+AQAMAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJHwAMANcZAA==.Alerys:BAAALgAFFAIJAgABLgAFFAgJHwAMANcZAA==.Alliar:BAABLgAECn8nAAMNAAkJxBynJwAhAgANAAkJxBynJwAhAgAHAAIJLgkykwBNAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAGAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJHwAMANcZAA==.',
Am='Amalek:BAAALgAECgEJAQAAAA==.Amerha:BAABLgAECn8eAAMNAAkJuQ1bOwDBAQANAAkJuQ1bOwDBAQAHAAIJiwZ2lwBHAAAAAA==.Amgems:BAAALgAECgIJAgAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anapplepi:BAAALgADCgUJBQAAAA==.Anasterion:BAACLgAFFH8JAAIOAAMJ0B8BRAAjAQAOAAMJ0B8BRAAjAQAuAAQKfxwAAg4ACAnRIaAyADYCAA4ACAnRIaAyADYCAAEuAAUUAwkJAAoARwkA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURHEegDHAAADAAQJURHEegDHAAAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8VAAILAAcJORfAGwCgAQALAAcJORfAGwCgAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgAECgEJAgAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJPQAPAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgAECgEJAQAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8mAAIQAAYJ5hpORgBZAQAQAAYJ5hpORgBZAQAuAAQKfy8AAhAACQkEI5clAIYCABAACQkEI5clAIYCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8fAAIHAAkJvhfUGgAKAgAHAAkJvhfUGgAKAgABLgAECgEJAQAGAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJDQABLgAECgEJAQAGAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAGAAAAAA==.Atrell:BAABLgAECn8eAAIOAAkJrRirSQDpAQAOAAkJrRirSQDpAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgYJBgABLgAFFAUJGgARAAwfAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJDwAAAA==.Balrock:BAAALgAECgEJAQAAAA==.Balthromaw:BAABLgAECn8xAAIPAAkJwhrJJABLAgAPAAkJwhrJJABLAgAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJBQAAAA==.Barli:BAAALgAECgIJAgAAAA==.Barqs:BAAALgAFFAIJBAAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSICJwAYAgADAAYJGSICJwAYAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAIAPwcAA==.Beardwaffle:BAABLgAECn8rAAIIAAkJ/BwhFABQAgAIAAkJ/BwhFABQAgAAAA==.Bearlando:BAABLgAFFH8IAAICAAUJeRv7BQCcAQACAAUJeRv7BQCcAQABLgAFFAgJHQAHANAXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQOAAYJiyIKSgDoAQAOAAUJiyIKSgDoAQASAAUJyw9XKgC5AAAEAAMJdQ7RbgB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIQAAMJ1wR1mACbAAAQAAMJ1wR1mACbAAAuAAQKfxQAAhAABwkyEx20AHYBABAABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Billy:BAAALgAECgMJAwABLgAFFAYJEgAJAIIUAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx1UFQA0AQATAAQJixpUFQA0AQAIAAQJMhqZIQAsAQAuAAQKfygABAgACAkOJC0UAKwCAAgACAl0Iy0UAKwCABQAAwmQJPIiABkBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAKAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIJAAkJFBghMgD9AQAJAAkJFBghMgD9AQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodemongar:BAAALgAECgMJAwAAAA==.Bloodhoundss:BAABLgAECn8nAAIIAAkJhRgYGgAdAgAIAAkJhRgYGgAdAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBWDDACNAQAVAAgJFBWDDACNAQAAAA==.',
Bo='Bob:BAACLgAFFH8ZAAIJAAYJCBZ4CQCTAQAJAAYJCBZ4CQCTAQAuAAQKfyYAAgkACQk+IdoIAEIDAAkACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8nAAINAAkJdxeAJAA0AgANAAkJdxeAJAA0AgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braegen:BAAALgAECgUJBQAAAA==.Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAFFAEJAQAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8cAAIIAAkJyRCKKQCyAQAIAAkJyRCKKQCyAQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8IAAIWAAIJihwNJQCGAAAWAAIJihwNJQCGAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAECgkJHwANAHUZAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAABLgAFFH8FAAIXAAIJyQsoRAA3AAAXAAIJyQsoRAA3AAAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Cainn:BAAALgAECgYJBwABLgAFFAUJEgAOACMSAA==.Caliginosity:BAABLgAECn8YAAIYAAcJeRc2DAD/AQAYAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Camphreth:BAAALgADCgYJBgAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8zAAICAAkJViBRBADUAgACAAkJViBRBADUAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCQAAAA==.Chemotherapy:BAAALgAECgUJBwAAAA==.Chillingsly:BAAALgAECgEJAQABLgAFFAQJDQAZAAkXAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIIAAkJZB2JFABMAgAIAAkJZB2JFABMAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAISAAMJ5hPXCwC5AAASAAMJ5hPXCwC5AAAuAAQKfxwAAhIACQm7GkwIAFUCABIACQm7GkwIAFUCAAAA.Condemnation:BAACLgAFFH8QAAIaAAQJxQ+TKAAIAQAaAAQJxQ+TKAAIAQAuAAQKfzgAAxoACQmjGo0QAGkCABoACQmQFo0QAGkCABsACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJDAAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAGAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAGAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8aAAIEAAkJ9QqyNAB/AQAEAAkJ9QqyNAB/AQAAAA==.',
Cr='Crayak:BAACLgAFFH8RAAILAAQJTxuLDgAwAQALAAQJTxuLDgAwAQAuAAQKfzEAAwsACQnmIjIFAO8CAAsACQnmIjIFAO8CAAkABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECggJLAAJAHwdAA==.Crossbones:BAABLgAECn8rAAMcAAgJlxyRJABQAgAcAAgJlxyRJABQAgAdAAQJWA9NPQDXAAAAAA==.Crux:BAAALgAECgEJAQABLgAECggJLAAJAHwdAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8KAAIJAAUJCxFWVADxAAAJAAUJCxFWVADxAAAuAAQKfxwAAgkACAltGqUyAC8CAAkACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8jAAIHAAgJQhV6LQCNAQAHAAgJQhV6LQCNAQAAAA==.Curbstomped:BAAALgAECggJCwAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAABLgAECn8WAAIQAAcJMQ+MngA9AQAQAAcJMQ+MngA9AQAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIFAAMJ2hFmpwDNAAAFAAMJ2hFmpwDNAAAuAAQKfyYAAwUACQkVItkYALECAAUACQkMItkYALECAB4ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8bAAIUAAUJ8CT/CQCQAQAUAAUJ8CT/CQCQAQAuAAQKf0gABBQACAmRJZIFAL0CABQACAn6JJIFAL0CAAgABwnvHpUdAGICABMABgk7IhEZAJEBAAAA.',
De='Deadbones:BAAALgAECgUJBQAAAA==.Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJEwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgcJCwAAAA==.Demonatrixx:BAABLgAECn8WAAIJAAkJJhSNAQA/AQAJAAkJJhSNAQA/AQAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAPAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIQAAUJbhMTYwAcAQAQAAUJbhMTYwAcAQAuAAQKfy4AAhAACAmUG2NBABgCABAACAmUG2NBABgCAAAA.Deselle:BAABLgAECn8gAAIQAAkJmQX/kwBQAQAQAAkJmQX/kwBQAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCgAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8pAAIDAAkJghKOLQDwAQADAAkJghKOLQDwAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAISAAkJNR1/BQCZAgASAAkJNR1/BQCZAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgEJAQAAAA==.',
Do='Dolbyatmos:BAAALgAFFAIJAgAAAA==.Donatelloh:BAABLgAECn8dAAMXAAgJoxJHOgAYAQAXAAcJuRRHOgAYAQARAAYJ/AneSADYAAAAAA==.Dortbraz:BAAALgAECgYJCAABLgAECgkJFgAOAFIQAA==.Dotmeharder:BAABLgAECn8bAAMPAAcJ8xOkegBnAQAPAAcJ8xOkegBnAQAZAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8PAAMKAAMJQBO8QQDAAAAKAAMJQBO8QQDAAAAMAAEJ8wEoBQAqAAAuAAQKfxwAAwoABgmoIU0lALQBAAoABgnKH00lALQBAB8ABgmkHuAMAEABAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJDwAKAEATAA==.Drakuza:BAABLgAFFH8IAAINAAQJQBE9NgAJAQANAAQJQBE9NgAJAQAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g1pEACsAQAgAAkJ7g1pEACsAQAAAA==.Draxyl:BAABLgAECn9HAAMFAAkJrxiMMAA9AgAFAAkJrxiMMAA9AgAeAAQJhQQtAwBhAAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMJAAkJpRC9WAB9AQAJAAkJpRC9WAB9AQAVAAUJwwvAHwCfAAAAAA==.Drogbar:BAABLgAECn8kAAMdAAkJzxicCwBoAgAdAAkJzxicCwBoAgAWAAgJYAhMFgAGAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMPAAkJchCRRwDDAQAPAAkJchCRRwDDAQAYAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgYJCQAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn80AAIFAAkJ2yGACwARAwAFAAkJ2yGACwARAwAAAA==.Duo:BAABLgAECn8/AAMhAAkJoRMKBADDAQAhAAgJgxUKBADDAQAQAAkJcwdR1gDoAAABLgAECggJHwABALUPAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMRAAkJ3CCOCQCZAgARAAkJ3CCOCQCZAgAXAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIPAAcJFgReyAC/AAAPAAcJFgReyAC/AAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAGAAAAAA==.Eleidon:BAAALgAECgYJCgAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMaAAkJ7Q/IKACNAQAaAAgJ8w3IKACNAQAbAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMNAAgJmRo2HwBVAgANAAgJmRo2HwBVAgAHAAYJTxS3QAAxAQAAAA==.',
En='Enseth:BAAALgAECgQJBQAAAA==.Enyô:BAABLgAECn8kAAIQAAkJJRUDRQAMAgAQAAkJJRUDRQAMAgAAAA==.',
Eo='Eorae:BAAALgAECgIJBwAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAABLgAECn8lAAIQAAkJzh3VGQC/AgAQAAkJzh3VGQC/AgAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAgJGQAJAPsXAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgUJCwABLgAECggJHwABALUPAA==.',
Fa='Faceblock:BAAALgAECgYJCAAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIXAAkJFiakAQBdAwAXAAkJFiakAQBdAwABLgAFFAUJGgAfAD8jAA==.Felzugger:BAABLgAFFH8NAAIJAAUJRhUzBQAaAQAJAAUJRhUzBQAaAQABLgAFFAgJHQAHANAXAA==.',
Fh='Fhalanx:BAAALgAECgUJEAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECggJKAAiAIkYAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAABLgAECn8bAAIQAAYJjR0RBAD+AAAQAAYJjR0RBAD+AAAAAA==.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgYJGwAQAI0dAA==.Flapp:BAABLgAECn8iAAMPAAkJLBS0PgDhAQAPAAkJLBS0PgDhAQAYAAIJsQiDXABZAAABLgAECgYJGwAQAI0dAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIcAAkJ1Bl4MAAaAgAcAAkJ1Bl4MAAaAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenlight:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgUJCgABLgAFFAUJCgAMAIAPAA==.Furyiosa:BAAALgAECgEJAQAAAA==.',
Ga='Gaiseric:BAABLgAFFH8HAAIFAAMJ7xJlnADYAAAFAAMJ7xJlnADYAAAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQaAAgJ1QkjMABdAQAaAAgJ1QkjMABdAQAbAAQJRQNmZACcAAAkAAEJ8gqCjAAuAAAAAA==.Geraldene:BAABLgAECn8VAAIbAAgJMQrMNQAqAQAbAAgJMQrMNQAqAQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgAECgMJAwAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgAECgQJBQAAAA==.',
Go='Goonenhance:BAAALgAECgIJBAAAAA==.Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIJAAkJ6hYlNgDtAQAJAAkJ6hYlNgDtAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJRQASAMgaAA==.Grimthruul:BAABLgAECn8iAAIHAAkJcArjAQDhAAAHAAkJcArjAQDhAAAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBUfHgBsAQATAAcJUBUfHgBsAQAAAA==.Grumpig:BAAALgAECgUJEgAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAAALgAECgYJEgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMbAAkJ0xH0KQCjAQAbAAcJDRX0KQCjAQAkAAcJAhLgPgAVAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAGAAAAAA==.Hamsandwich:BAAALgAECgUJBQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAGAAAAAA==.Hanharr:BAAALgAECgMJBQAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhGtJQCfAQAiAAkJBhGtJQCfAQAAAA==.Heyro:BAAALgAECgYJBgAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgUJCwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8VAAIBAAQJVxriBgA9AQABAAQJVxriBgA9AQAuAAQKfzUAAgEACQkwHisFAKMCAAEACQkwHisFAKMCAAAA.Hiphopuler:BAABLgAECn85AAIbAAgJpBmgGwAAAgAbAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMOAAkJUB6eHwCuAgAOAAkJUB6eHwCuAgASAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgUJCQAAAA==.Holyschmit:BAABLgAECn8xAAIEAAgJYRpVGwApAgAEAAgJYRpVGwApAgAAAA==.Holysmite:BAAALgADCgEJAQAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxO+FACnAQAUAAkJVxO+FACnAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RmYCgDDAQAWAAgJ1RmYCgDDAQAAAA==.Huntris:BAABLgAECn8aAAIdAAkJ6RlHFAADAgAdAAkJ6RlHFAADAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAABLgAECn8dAAMNAAcJ3Qt3aQAfAQANAAcJ3Qt3aQAfAQAHAAUJRASJewB9AAAAAA==.Hypnotykk:BAABLgAECn8aAAIcAAgJFBQHTwC1AQAcAAgJFBQHTwC1AQAAAA==.',
Ia='Iadygaga:BAAALgAECggJCQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Ik='Ikova:BAAALgAECgMJBAAAAA==.',
Il='Illogical:BAAALgAECgMJAwABLgAFFAgJIgAQALEVAA==.',
Im='Immunè:BAAALgAECgIJBAABLgAFFAUJEAAFABAXAA==.Imrah:BAABLgAECn80AAQXAAkJuhPuGADqAQAXAAkJuhPuGADqAQARAAMJ2QbcawBtAAAjAAEJrwNU0QAfAAAAAA==.',
In='Incarnate:BAAALgAECgEJAwABLgAECgYJEwAGAAAAAA==.Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgABLgAECgkJEgAGAAAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8TAAIbAAQJ4hnCEwAoAQAbAAQJ4hnCEwAoAQAuAAQKfzQAAhsACQlyG6QNAIwCABsACQlyG6QNAIwCAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8TAAIlAAUJvx5vFQBgAQAlAAUJvx5vFQBgAQAuAAQKfyIAAiUACAkzGOojAHUBACUACAkzGOojAHUBAAAA.Jocon:BAABLgAECn8mAAIPAAkJAwf5dABQAQAPAAkJAwf5dABQAQAAAA==.Joraan:BAAALgAECgcJCAAAAA==.',
Js='Js:BAAALgADCgIJAgAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJEAAdALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAdALEOAA==.Kanami:BAABLgAECn8sAAIIAAkJBB/oDACdAgAIAAkJBB/oDACdAgAAAA==.Kaori:BAABLgAECn8UAAIOAAgJCAg/sgAfAQAOAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhmDDQAKAgACAAkJDhmDDQAKAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Katarr:BAAALgAECgUJBQAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgcJFQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx3fDABYAgAlAAkJbx3fDABYAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8SAAIOAAUJIxLbSQAZAQAOAAUJIxLbSQAZAQAuAAQKf0oAAw4ACQl8Go4uAEcCAA4ACQlJGY4uAEcCABIABwlyGk4PAM4BAAAA.Keedron:BAACLgAFFH8ZAAIJAAgJ+xchEwAYAgAJAAgJ+xchEwAYAgAuAAQKfxsAAgkACAlJJIkLACUDAAkACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIFAAgJqRPldQB4AQAFAAgJqRPldQB4AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8yAAMFAAkJDx++FgC/AgAFAAkJDx++FgC/AgAmAAMJEgmDMgBSAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCggJEQAAAA==.Kilfogg:BAABLgAECn8XAAIHAAcJoxfmKwC5AQAHAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8JAAMKAAMJRwn5SgChAAAKAAMJRwn5SgChAAAMAAMJeg8vIQCdAAAuAAQKfycABAwACQlJGBMNAAECAAwACQlJGBMNAAECAAoABgk3EMZKAAEBAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIQAAcJ/R75BgDwAQAQAAcJ/R75BgDwAQAuAAQKfxcAAhAACAm6IwgVACoDABAACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAGAAAAAA==.Korvasa:BAAALgAECgQJBAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAAOAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIPAAMJ2AP4jQCpAAAPAAMJ2AP4jQCpAAAuAAQKfxYAAg8ABwlgFFZSANABAA8ABwlgFFZSANABAAAA.Krymzendeath:BAABLgAECn8ZAAMSAAcJ6AvfIgD+AAASAAcJ6AvfIgD+AAAOAAUJcgLWTwFfAAABLgAFFAQJGgAUAL8YAA==.Krísztina:BAABLgAECn8pAAQZAAgJWAuHEQBLAQAZAAgJwgiHEQBLAQAYAAgJqAmCFQD+AAAPAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAgJGQAJAPsXAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAGAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIdAAQJsQ5QFgAeAQAdAAQJsQ5QFgAeAQAuAAQKfyQAAh0ACQkmGOQHAHICAB0ACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Laelada:BAAALgAECgQJBAAAAA==.Lakey:BAABLgAECn8XAAQbAAgJByaEFgAdAgAbAAgJByaEFgAdAgAaAAUJ6SJ6HADqAQAkAAMJOA73SgCuAAABLgAFFAUJHgADAEEWAA==.Lakeyy:BAACLgAFFH8eAAMDAAUJQRY6IgBHAQADAAUJQRY6IgBHAQAiAAQJpxRJIQAWAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAABLgAFFH8FAAIjAAUJxxHMLgD+AAAjAAUJxxHMLgD+AAABLgAFFAUJHgADAEEWAA==.Lanayrd:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAAOAC0cAA==.Lawrence:BAACLgAFFH8MAAMHAAUJbxBBKQDwAAAHAAQJbxBBKQDwAAANAAQJ7QfFSADLAAAuAAQKfyMAAwcACAmaIcIKAOoCAAcACAmaIcIKAOoCAA0AAwkbDjunAH0AAAEuAAUUBgkSAAkAghQA.Lazuril:BAAALgAECgEJAgAAAQ==.',
Le='Leanhaum:BAAALgAECgIJBAAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lickmybubble:BAAALgAECgEJAQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilikoii:BAAALgAECgMJAwABLgAFFAUJHgADAEEWAA==.Lilslaver:BAAALgAECgcJEQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Liradra:BAAALgAECgEJAQAAAA==.Lisex:BAACLgAFFH8pAAQFAAgJ1xY2EwBCAgAFAAcJ1xY2EwBCAgAmAAQJSQ0YEgABAQAeAAEJAAAfGgA0AAAuAAQKfzEAAwUACQmjI/cWAPICAAUACQmZI/cWAPICACYABwkiHS0JAPUBAAAA.Lithe:BAAALgAFFAMJBAABLgAFFAQJGAAHAD4dAA==.',
Lo='Locklear:BAABLgAECn8iAAIOAAkJbBbGRgDyAQAOAAkJbBbGRgDyAQAAAA==.Logic:BAACLgAFFH8iAAMQAAgJsRU7GQAsAgAQAAgJqBQ7GQAsAgAhAAMJEBYZAwDnAAAuAAQKfysAAhAACQlvI00UAOACABAACQlvI00UAOACAAAA.Lolbrez:BAAALgAECgEJAQAAAA==.Lolshield:BAAALgAECgYJCgABLgAFFAUJGgARAAwfAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8xAAISAAkJjgodHQAsAQASAAkJjgodHQAsAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xlBBQAXAgAnAAgJ9xlBBQAXAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJHgADAEEWAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAYJCgAcAOMFAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAACLgAFFH8FAAIFAAIJeRE5HABLAAAFAAIJeRE5HABLAAAuAAQKfy4AAgUACQkvHT4pAFwCAAUACQkvHT4pAFwCAAAA.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8bAAIJAAgJIxuDBADpAQAJAAgJIxuDBADpAQAuAAQKfycAAgkACQkZIkEIAEgDAAkACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAgJGwAJACMbAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIQAAkJbhW9YQC8AQAQAAkJbhW9YQC8AQAAAA==.Magirzul:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAQ==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAIOAAQJLRy5NgBAAQAOAAQJLRy5NgBAAQAuAAQKfy0AAg4ACQn9HowkAHMCAA4ACQn9HowkAHMCAAAA.Makima:BAAALgAECgUJBQAAAA==.Malazen:BAAALgAECgIJBAAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIFAAkJ+BwdIQCEAgAFAAkJ+BwdIQCEAgAAAA==.Mamageek:BAABLgAECn8XAAINAAkJ9hHmKADsAQANAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAGAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAQAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Mastahunta:BAAALgAECgQJBAABLgAECggJKwANAJkaAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8kAAIOAAkJcB3dJgBoAgAOAAkJcB3dJgBoAgAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIeAAgJyBTUGwB9AQAeAAgJyBTUGwB9AQABLgAECgkJHgACACEWAA==.Mcversatile:BAABLgAECn8eAAICAAkJIRZ1EgDKAQACAAkJIRZ1EgDKAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIbAAkJrBksEABkAgAbAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8iAAIMAAgJBCGBAQARAwAMAAgJBCGBAQARAwAuAAQKfycAAgwACQkZJk4AAN8DAAwACQkZJk4AAN8DAAAA.Mereoleona:BAAALgAECgcJEQAAAA==.Metalmagus:BAABLgAECn8iAAIQAAgJCRp9TwDtAQAQAAgJCRp9TwDtAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSIyBQCTAgAgAAkJTSIyBQCTAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAgJGQAJAPsXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8mAAIRAAkJOhMjHwCtAQARAAkJOhMjHwCtAQAAAA==.Misslobster:BAAALgAECgkJEQAAAA==.Mistweaver:BAABLgAFFH8JAAIjAAQJ5xmDJQBBAQAjAAQJ5xmDJQBBAQAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJKwANAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgkJDgAAAA==.Mokoko:BAACLgAFFH8SAAMKAAQJsx5YAgBbAQAKAAQJsx5YAgBbAQAfAAEJVQsfCgBTAAAuAAQKfzEAAwoACQmhIdEFACcDAAoACQmHIdEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJEgAKALMeAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR1eDwBpAgAiAAkJKR1eDwBpAgADAAQJDxFhggDUAAACAAEJch3LYQBNAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMXAAkJbCPlCAC3AgAXAAkJbCPlCAC3AgARAAYJ7hlFKwBdAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgAECgMJAwABLgAECgYJBgAGAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJGgARAAwfAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAGAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIFAAkJVBtcUQDPAQAFAAkJVBtcUQDPAQAAAA==.Necrota:BAACLgAFFH8IAAIFAAMJ1RtbhwD7AAAFAAMJ1RtbhwD7AAAuAAQKfxoAAwUACAmVHrFHAOsBAAUACAkWHrFHAOsBAB4AAQlcG5FBAEUAAAEuAAUUBwkbABAA/R4A.Nekronomicon:BAAALgAECgYJBwAAAA==.Neuron:BAACLgAFFH8dAAIDAAgJPhutAQD6AQADAAgJPhutAQD6AQAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.Nexgen:BAAALgAECgUJBQAAAA==.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8uAAIoAAkJnxBMBwDoAQAoAAkJnxBMBwDoAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nofitputspit:BAAALgAECgYJBgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgUJDgAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAGAAAAAA==.',
Nu='Nucwel:BAAALgAECgMJAwAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgAECgEJAQAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAIEAAgJEiKeEQCHAgAEAAgJEiKeEQCHAgAAAA==.Oreyn:BAAALgAECgcJDgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladian:BAAALgAECgIJAgABLgAECggJKwANAJkaAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn9FAAMSAAkJyBpLCQA9AgAOAAkJ2Ri1LABOAgASAAkJCBlLCQA9AgAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJEAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAABLgAECn8cAAIlAAgJaB6SEwAHAgAlAAgJaB6SEwAHAgAAAA==.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8aAAMfAAUJPyOsAQCKAQAfAAUJPyOsAQCKAQAKAAQJfB2gHwBjAQAuAAQKfzwAAx8ACQlUJi4AAIUDAB8ACQlRJi4AAIUDAAoABgnPIC8cAPQBAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSM2GQCUAQADAAQJbSM2GQCUAQAuAAQKfzsAAwMACQn9Jd8AANkDAAMACQn9Jd8AANkDACIABgkfEB1EAPwAAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQABLgAECgkJIgADADQaAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAFFAIJAgAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8tAAMbAAcJ+R4/FgAgAgAbAAcJ+R4/FgAgAgAkAAUJnR9OLwBiAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgIJAwABLgAECgUJCAAGAAAAAA==.',
Po='Poepoe:BAAALgAFFAEJAQAAAA==.Polyrhythm:BAAALgAFFAEJAgAAAA==.Polyrhythms:BAAALgAFFAEJAQAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIaAAMJlQjANAC5AAAaAAMJlQjANAC5AAAuAAQKfx4AAhoABgmxH8MTABACABoABgmxH8MTABACAAAA.Prosthesis:BAAALgAECgQJBAAAAA==.Prrowl:BAABLgAECn8WAAICAAUJKwi0AgB+AAACAAUJKwi0AgB+AAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAABLgAECn8WAAIOAAkJUhCKVADMAQAOAAkJUhCKVADMAQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAAOAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.Rizzpinchy:BAAALgADCgUJBQAAAA==.',
Ro='Roksolid:BAABLgAECn8lAAIHAAkJWxcJGwAJAgAHAAkJWxcJGwAJAgAAAA==.Rollos:BAABLgAECn8gAAIPAAkJUBVtNgD/AQAPAAkJUBVtNgD/AQAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxK0MAC3AQAjAAgJCxK0MAC3AQAAAA==.Rookesbane:BAAALgAECgIJAgAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8iAAIKAAgJdyHTBQCnAgAKAAgJdyHTBQCnAgAuAAQKfyEAAgoACQm3JfAAAMwDAAoACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8WAAQPAAYJUhXHlAASAQAPAAUJUhXHlAASAQAYAAEJ+A1zcAA2AAAZAAEJAABMSgAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJRQASAMgaAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAIAH4aAA==.Saeli:BAAALgAECgEJAgAAAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgYJDwAAAA==.Salvester:BAAALgAECgIJAgABLgAECgcJLQAbAPkeAA==.Samtarkras:BAABLgAECn8tAAIMAAkJqhqgBwB8AgAMAAkJqhqgBwB8AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAGAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAABLgAFFH8KAAIcAAYJ4wVhNwA+AQAcAAYJ4wVhNwA+AQAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8NAAIZAAQJCReSBABBAQAZAAQJCReSBABBAQAuAAQKf6wABBkACQmPJUsAAGcDABkACQmPJUsAAGcDABgABgkhINgHANMBAA8ABglbGYFcAIkBAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8zAAMkAAkJsxjsEQBGAgAkAAkJsxjsEQBGAgAbAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8JAAIkAAMJThFaJwDBAAAkAAMJThFaJwDBAAAuAAQKf2oAAiQACQnFJOcCADYDACQACQnFJOcCADYDAAEuAAUUCAkdAAcA0BcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAFAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAABLgAFFH8LAAIPAAYJAReoLACTAQAPAAYJAReoLACTAQABLgAFFAcJGAAQAJAfAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shastashaman:BAAALgAECgIJAgAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIcAAQJSQvJXQDpAAAcAAQJSQvJXQDpAAAuAAQKfyoAAhwACAnIIAoYAJcCABwACAnIIAoYAJcCAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJIgAKAHchAA==.Shodin:BAAALgADCgEJAQAAAA==.Shotsyll:BAAALgAECgIJAgABLgAECggJFgADAEkZAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.Skynomad:BAAALgAECgQJBgABLgAECgYJCgAGAAAAAA==.',
Sl='Slyde:BAABLgAECn8yAAIFAAkJziQTBQBUAwAFAAkJziQTBQBUAwAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIFAAYJzBg8FwBIAQAFAAYJzBg8FwBIAQAuAAQKfyUAAgUACAnPIq8VAPoCAAUACAnPIq8VAPoCAAEuAAUUBwkJAAoAlBUA.Smick:BAABLgAECn8eAAIEAAkJoRJVLACwAQAEAAkJoRJVLACwAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgcJDgAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCOICwAqAgACAAcJNSGICwAqAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9TAAIIAAkJjiFwCQDLAgAIAAkJjiFwCQDLAgAAAA==.Soulfox:BAAALgAECgEJAwABLgAECggJKwANAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAUJFAAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAABLgAECn8VAAIFAAcJTRc+XgCuAQAFAAcJTRc+XgCuAQAAAA==.',
Sq='Squidmonk:BAAALgAECggJCQAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8gAAIVAAgJfBOwDACKAQAVAAgJfBOwDACKAQABLgAFFAQJDQAZAAkXAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAABLgAECn8UAAIlAAgJgROfHgChAQAlAAgJgROfHgChAQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIXAAgJvhumAQB4AgAXAAgJvhumAQB4AgAuAAQKfxUAAhcACAlEH5kMALECABcACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Stormsurge:BAAALgAECgIJBAAAAA==.Straydog:BAABLgAECn8uAAMNAAkJ4ySPAQC5AwANAAkJ4ySPAQC5AwAHAAEJHhRCnwA7AAAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIFAAkJlhYUfwBlAQAFAAkJlhYUfwBlAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAGAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAGAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAGAAAAAA==.Superpowers:BAABLgAECn8XAAIRAAgJWR+yDQBdAgARAAgJWR+yDQBdAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yFZBADWAgATAAkJ4yFZBADWAgAAAA==.Sus:BAABLgAFFH8IAAIcAAQJAwoncQC9AAAcAAQJAwoncQC9AAAAAA==.Suzel:BAABLgAECn8dAAIFAAUJSwkzBQC3AAAFAAUJSwkzBQC3AAAAAA==.',
Sw='Sweatmachine:BAAALgAECgEJAQAAAA==.Swoof:BAAALgAECggJEQABLgAFFAYJCgAcAOMFAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn88AAILAAkJhxR9EwD5AQALAAkJhxR9EwD5AQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAFFAIJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAaAN8OAA==.Synwise:BAABLgAECn83AAIDAAkJaiFIBgBTAwADAAkJaiFIBgBTAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8SAAIcAAQJGhaZPAA0AQAcAAQJGhaZPAA0AQAuAAQKfzUAAxwACQlmHQ8hAGICABwACQlmHQ8hAGICABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIXAAgJCxnTGAAcAgAXAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQbAAkJlhqZEQBUAgAbAAkJlhqZEQBUAgAaAAQJlA2WVgCmAAAkAAIJbhIKagB2AAAAAA==.',
Te='Teknicaliti:BAAALgAECgEJAQAAAA==.',
Th='Thanah:BAAALgAECgUJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8TAAIFAAUJXBOtZwApAQAFAAUJXBOtZwApAQAuAAQKfyoAAwUACQkdGJlMANwBAAUACQkdGJlMANwBACYAAQneCWQ+ACoAAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAGAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8QAAIVAAQJmBwIBAA/AQAVAAQJmBwIBAA/AQAuAAQKfzkAAhUACQnWHjYEAIQCABUACQnWHjYEAIQCAAAA.Tinytea:BAACLgAFFH8QAAIRAAQJhSO8EgCOAQARAAQJhSO8EgCOAQAuAAQKf0IAAhEACQkyJdkBAEoDABEACQkyJdkBAEoDAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDwAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8OAAMEAAUJuxvKFACEAQAEAAUJuxvKFACEAQAOAAEJUQ1VugBDAAAuAAQKfygAAwQACQkYHeUVAGECAAQACAkqH+UVAGECAA4ABQnfEC69AAwBAAAA.Torb:BAAALgAECgUJBQAAAA==.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgAECgEJAQAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMIAAYJ0SGHLQD9AQAIAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAFAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgAECgEJAQABLgAECgcJEAAGAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAGAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAGAAAAAA==.Tuckrh:BAAALgAECgYJBwAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgUJCQAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgfsIwB7AAAUAAMJfgfsIwB7AAAuAAQKfx4AAhQACQkPD/QaAGEBABQACQkPD/QaAGEBAAEuAAUUBAkNAAcA6gcA.Twippy:BAABLgAFFH8NAAIHAAQJ6gecLwDVAAAHAAQJ6gecLwDVAAAAAA==.Twobeers:BAAALgAECgYJBgAAAA==.',
Ty='Tyanis:BAABLgAECn8bAAIOAAYJ1wr+4ADdAAAOAAYJ1wr+4ADdAAABLgAECgcJDgAGAAAAAA==.Tyriam:BAABLgAECn8wAAMOAAkJ2hrWLQBJAgAOAAgJ2hrWLQBJAgAEAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIQAAgJixODbgCdAQAQAAgJixODbgCdAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAGAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAGAAAAAA==.Vandy:BAABLgAECn8nAAMLAAkJLAraNwAmAQALAAYJtwvaNwAmAQAJAAkJXAmJkAD/AAAAAA==.Varodonaris:BAAALgAECgYJCQAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECgIJAgAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8aAAMfAAYJvA9KBQASAQAfAAUJtg9KBQASAQAKAAUJqRFBPADWAAAuAAQKfyAAAx8ACQkuHUgEAMkCAB8ACAlhIEgEAMkCAAoAAgmHEH2HAE0AAAAA.Verso:BAABLgAECn8rAAInAAkJWRtxAwBnAgAnAAkJWRtxAwBnAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinushka:BAAALgAECggJDwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgkJMwAKABYcAA==.Vitalithry:BAABLgAECn8zAAMKAAkJFhx6EABkAgAKAAkJDhx6EABkAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgMJBAAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAAOAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAGAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAACLgAFFH8GAAIFAAMJvQ3NpQDOAAAFAAMJvQ3NpQDOAAAuAAQKfykAAgUACQlxFeFkAJ0BAAUACQlxFeFkAJ0BAAAA.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQHAAkJ0R85CQDJAgAHAAkJ0R85CQDJAgANAAgJ4BnsIwA3AgAgAAIJ7xHOPQA3AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8SAAIkAAgJVBTbCQDEAQAkAAgJVBTbCQDEAQAuAAQKfzkAAyQACAlFIsIJALICACQACAlFIsIJALICABsAAQklJeldAGIAAAAA.Windoelicker:BAAALgAECgYJEgAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh45DgC7AgAjAAgJqh45DgC7AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8XAAIDAAYJoA0GIgBJAQADAAYJoA0GIgBJAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulfvane:BAAALgADCgMJAwAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCgkJDgAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMcAAkJ7xq7OQD3AQAcAAgJFxu7OQD3AQAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIFAAQJRBTwcgAaAQAFAAQJRBTwcgAaAQAuAAQKfx4AAwUACAn0HiE8ABACAAUACAn0HiE8ABACACYAAQlgENk8AC0AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAIEAAkJdgr/MQCOAQAEAAkJdgr/MQCOAQAAAA==.Yey:BAABLgAECn8hAAQEAAkJjxm8GgAvAgAEAAkJjxm8GgAvAgASAAMJJgGTTAA6AAAOAAEJDQTRwgEiAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8iAAIQAAkJ8g/QVADeAQAQAAkJ8g/QVADeAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIPAAMJGQxrfwDGAAAPAAMJGQxrfwDGAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChtaDAAbAgACAAgJChtaDAAbAgAiAAUJvw2VRAD6AAABAAIJpAcTXQAlAAABLgAFFAMJBgAPABkMAA==.Zaydämon:BAABLgAECn8WAAIJAAgJ4R1IHwCWAgAJAAgJ4R1IHwCWAgABLgAFFAMJBgAPABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zello:BAAALgAECggJDAAAAA==.Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgkJMAABAL8YAA==.Ziggybeast:BAACLgAFFH8KAAIDAAIJBxnCSgCRAAADAAIJBxnCSgCRAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTIgGpAGIAAAIAAwl4DVZhAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCgADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIFAAIJZxisyACbAAAFAAIJZxisyACbAAAuAAQKf0MAAgUACQlMHTMsAE8CAAUACQlMHTMsAE8CAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgUJBgAAAA==.',
Zy='Zydia:BAAALgAECgEJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAFFAMJBgAPABkMAA==.',
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
