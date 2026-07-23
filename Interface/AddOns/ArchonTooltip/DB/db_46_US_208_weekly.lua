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

local lookup = {'Druid-Feral','Druid-Guardian','Druid-Restoration','Paladin-Holy','Unknown-Unknown','DeathKnight-Unholy','Shaman-Elemental','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','DemonHunter-Havoc','Evoker-Preservation','Shaman-Restoration','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Monk-Brewmaster','Paladin-Protection','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Monk-Windwalker','Warlock-Destruction','Priest-Discipline','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Blood','Evoker-Devastation','Shaman-Enhancement','Mage-Fire','Druid-Balance','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8gAAQBAAgJtQ8xGgA8AQABAAcJohAxGgA8AQACAAgJCAo3OADGAAADAAEJJQf12gAnAAAAAA==.',
Ac='Acrux:BAAALgADCgcJCwABLgAFFAIJBgAEAA0LAA==.',
Ad='Adaela:BAAALgAECgEJAQABLgAFFAIJAgAFAAAAAA==.Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Adamwarlock:BAAALgADCgEJAQAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8RAAIGAAUJEBc5ZgArAQAGAAUJEBc5ZgArAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAFAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8cAAIHAAUJ3QrfEACQAAAHAAUJ3QrfEACQAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIIAAYJfhrrQQA9AQAIAAYJfhrrQQA9AQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAIAH4aAA==.',
Al='Alariel:BAABLgAECn8tAAIJAAkJ3xmhJQA3AgAJAAkJ3xmhJQA3AgABLgAFFAcJIAAKAH8aAA==.Alary:BAAALgAECgEJAQABLgAFFAQJBAAFAAAAAA==.Albesuri:BAAALgAECgUJBQABLgAFFAkJGgAJAN0WAA==.Albskin:BAAALgAECgUJCgAAAA==.Alcazar:BAABLgAECn8tAAMJAAkJwB2GHwBYAgAJAAkJwB2GHwBYAgALAAEJAAAniAAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAIMAAgJGwj8HwB+AQAMAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAkJIAAMAIEXAA==.Alerys:BAAALgAFFAIJAgABLgAFFAkJIAAMAIEXAA==.Alliar:BAABLgAECn8nAAMNAAkJxBypJwAhAgANAAkJxBypJwAhAgAHAAIJLgkwkwBNAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAFFAIJAgAFAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAkJIAAMAIEXAA==.',
Am='Amalek:BAAALgAECgQJBQAAAA==.Amerha:BAABLgAECn8eAAMNAAkJuQ1cOwDBAQANAAkJuQ1cOwDBAQAHAAIJiwZzlwBHAAAAAA==.Amgems:BAAALgAECgIJAgAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.Amordred:BAAALgAECgEJAgAAAA==.',
An='Anapplepi:BAAALgADCgUJBQAAAA==.Anasterion:BAACLgAFFH8JAAIOAAMJ0B/1QwAjAQAOAAMJ0B/1QwAjAQAuAAQKfxwAAg4ACAnRIZ4yADYCAA4ACAnRIZ4yADYCAAEuAAUUAwkJAAoARwkA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURHEegDHAAADAAQJURHEegDHAAAAAA==.Ansley:BAAALgAFFAIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8VAAILAAcJORe/GwCgAQALAAcJORe/GwCgAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araalan:BAAALgADCgYJBgAAAA==.Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgAECgEJBgAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAFFAQJCAAPALYYAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgAECgIJAgAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8pAAIQAAcJKhkuRgBZAQAQAAcJKhkuRgBZAQAuAAQKfy8AAhAACQkEI5MlAIYCABAACQkEI5MlAIYCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8fAAIHAAkJvhfUGgAKAgAHAAkJvhfUGgAKAgABLgAECgEJAQAFAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJDQABLgAECgEJAQAFAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAFAAAAAA==.Atrell:BAABLgAECn8eAAIOAAkJrRiqSQDpAQAOAAkJrRiqSQDpAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgYJBwABLgAFFAUJGgARAAwfAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJDwABLgAECgYJCwAFAAAAAA==.Balrock:BAAALgAECgIJAgAAAA==.Balthromaw:BAABLgAECn87AAIPAAkJkx1BAwAxAgAPAAkJkx1BAwAxAgAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJBQAAAA==.Barli:BAAALgAECgIJAgAAAA==.Barqs:BAAALgAFFAIJBAAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSIAJwAYAgADAAYJGSIAJwAYAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAIAPwcAA==.Beardwaffle:BAABLgAECn8rAAIIAAkJ/BwgFABQAgAIAAkJ/BwgFABQAgAAAA==.Bearlando:BAABLgAFFH8IAAICAAUJeRv8BQCcAQACAAUJeRv8BQCcAQABLgAFFAkJJAAHAIEXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQOAAYJiyIISgDoAQAOAAUJiyIISgDoAQASAAUJyw9XKgC5AAAEAAMJdQ7MbgB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIQAAMJ1wRmmACbAAAQAAMJ1wRmmACbAAAuAAQKfxQAAhAABwkyEx20AHYBABAABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Billy:BAAALgAECgMJAwABLgAFFAcJFAAJAAYTAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx1QFQA0AQATAAQJixpQFQA0AQAIAAQJMhqVIQAsAQAuAAQKfygABAgACAkOJC0UAKwCAAgACAl0Iy0UAKwCABQAAwmQJPMiABkBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAKAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIJAAkJFBggMgD9AQAJAAkJFBggMgD9AQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodemongar:BAAALgAECgYJCQAAAA==.Bloodhoundss:BAABLgAECn8nAAIIAAkJhRgYGgAdAgAIAAkJhRgYGgAdAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBWDDACNAQAVAAgJFBWDDACNAQAAAA==.',
Bo='Bob:BAACLgAFFH8ZAAIJAAYJCBZ4CQCTAQAJAAYJCBZ4CQCTAQAuAAQKfyYAAgkACQk+IdoIAEIDAAkACQk+IdoIAEIDAAAA.Bobagos:BAAALgAECgEJAQAAAA==.Bofft:BAABLgAECn8nAAINAAkJdxeCJAAzAgANAAkJdxeCJAAzAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braegen:BAAALgAECgUJBQABLgAECgcJEwAFAAAAAA==.Braera:BAAALgAECgEJAQAAAA==.Brantoz:BAABLgAECn8iAAIIAAkJ1iUYAQB3AwAIAAkJ1iUYAQB3AwABLgAECgkJNgAUAK4lAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brisa:BAAALgADCgEJAQAAAA==.Brttneyfears:BAAALgAFFAEJAQAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8gAAIIAAkJ4hKxCAAXAQAIAAkJ4hKxCAAXAQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8IAAIWAAIJihwEJQCGAAAWAAIJihwEJQCGAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAFFAMJCwANAKQfAA==.',
Bu='Bubble:BAAALgAECgEJAQAAAA==.Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAABLgAFFH8GAAIXAAMJzxbUDwCdAAAXAAMJzxbUDwCdAAAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Cainn:BAAALgAECgYJBwABLgAFFAUJFAAOACMSAA==.Caliginosity:BAABLgAECn8YAAIYAAcJeRc2DAD/AQAYAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Camphreth:BAAALgADCgYJBgAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.Carpetburn:BAAALgAECgYJDAABLgAFFAQJGAAZAMUPAA==.Cayllia:BAAALgAFFAEJAwAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8zAAICAAkJXSBRBADUAgACAAkJXSBRBADUAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCQAAAA==.Chemotherapy:BAABLgAFFH8FAAISAAMJggqWBwCHAAASAAMJggqWBwCHAAAAAA==.Chillingsly:BAAALgAECgcJCQABLgAFFAQJFgAaALUcAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIIAAkJZB2HFABMAgAIAAkJZB2HFABMAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAISAAMJ5hPXCwC5AAASAAMJ5hPXCwC5AAAuAAQKfx8AAxIACQl9HEwIAFUCABIACQlnG0wIAFUCAA4AAglLEawsAHMAAAAA.Condemnation:BAACLgAFFH8YAAIZAAQJxQ9pEwDeAAAZAAQJxQ9pEwDeAAAuAAQKfzgAAxkACQmjGo8QAGkCABkACQmQFo8QAGkCABsACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJDAAAAA==.Conquest:BAAALgAFFAEJAQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAFAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAFAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8aAAIEAAkJ9QqzNAB/AQAEAAkJ9QqzNAB/AQAAAA==.',
Cr='Crayak:BAACLgAFFH8SAAILAAUJTxuNDgAwAQALAAUJTxuNDgAwAQAuAAQKfzEAAwsACQnmIjIFAO8CAAsACQnmIjIFAO8CAAkABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgkJLQAJAMAdAA==.Crossbones:BAACLgAFFH8GAAIcAAMJUg0ERQCIAAAcAAMJUg0ERQCIAAAuAAQKfzIAAxwACAnyH9cFABECABwACAnyH9cFABECAB0ABAlYD049ANcAAAAA.Crux:BAAALgAECgQJBAABLgAECgkJLQAJAMAdAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8KAAIJAAUJCxFMVADxAAAJAAUJCxFMVADxAAAuAAQKfxwAAgkACAltGqUyAC8CAAkACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8jAAIHAAgJQhV8LQCNAQAHAAgJQhV8LQCNAQAAAA==.Curbstomped:BAAALgAFFAIJAwAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAABLgAECn8WAAIQAAcJMQ+MngA9AQAQAAcJMQ+MngA9AQAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Daheal:BAAALgAFFAIJAgAAAA==.Danarius:BAAALgADCgEJAQAAAA==.Darkvizzy:BAACLgAFFH8GAAIGAAMJ2hFhpwDNAAAGAAMJ2hFhpwDNAAAuAAQKfyYAAwYACQkVItkYALECAAYACQkMItkYALECAB4ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8cAAIUAAYJTSX7CQCQAQAUAAYJTSX7CQCQAQAuAAQKf04ABBQACAnCJZAFAL0CABQACAmyJZAFAL0CAAgABwnvHpUdAGICABMABgk7IhEZAJEBAAAA.',
De='Deadbones:BAAALgAECgUJBQAAAA==.Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJEwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgcJCwAAAA==.Demonatrixx:BAABLgAECn8WAAIJAAkJJhRaCgAvAQAJAAkJJhRaCgAvAQAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAPAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIQAAUJbhP4YgAcAQAQAAUJbhP4YgAcAQAuAAQKfy4AAhAACAmUG2JBABgCABAACAmUG2JBABgCAAAA.Deselle:BAABLgAECn8gAAIQAAkJmQUBlABQAQAQAAkJmQUBlABQAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCgAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8pAAIDAAkJghKMLQDwAQADAAkJghKMLQDwAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAISAAkJNR1/BQCZAgASAAkJNR1/BQCZAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgAFFAIJAgAAAA==.Donatelloh:BAABLgAECn8eAAMXAAkJyxJJOgAYAQAXAAgJmxRJOgAYAQARAAYJ/AnfSADYAAAAAA==.Dortbraz:BAAALgAECgYJCAABLgAECgkJFgAOAFIQAA==.Dotmeharder:BAABLgAECn8bAAMPAAcJ8xOkegBnAQAPAAcJ8xOkegBnAQAaAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8QAAMKAAMJ+hXCQQDAAAAKAAMJ+hXCQQDAAAAMAAEJ8wEnGAAqAAAuAAQKfx8AAwoABgmoIVAlALQBAAoABgnKH1AlALQBAB8ABgmkHuAMAEABAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJEAAKAPoVAA==.Drakuza:BAABLgAFFH8JAAINAAQJQBFGNgAJAQANAAQJQBFGNgAJAQAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g1oEACsAQAgAAkJ7g1oEACsAQAAAA==.Draxyl:BAACLgAFFH8FAAMeAAIJbAtqGgBrAAAeAAIJsQlqGgBrAAAGAAEJDgrzjgBBAAAuAAQKf00AAwYACQmYGY0wAD0CAAYACQmvGI0wAD0CAB4ABwnOEMoEAD0BAAAA.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMJAAkJpRC7WAB9AQAJAAkJpRC7WAB9AQAVAAUJwwvBHwCfAAAAAA==.Drogbar:BAABLgAECn8kAAMdAAkJzxiZCwBoAgAdAAkJzxiZCwBoAgAWAAgJYAhMFgAGAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMPAAkJchCSRwDDAQAPAAkJchCSRwDDAQAYAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgcJCgAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn80AAIGAAkJ2yGACwARAwAGAAkJ2yGACwARAwAAAA==.Duo:BAABLgAECn9JAAMhAAkJIxWXAACcAQAhAAgJeReXAACcAQAQAAkJcwdX1gDoAAABLgAECggJIAABALUPAA==.',
['Dä']='Därkside:BAAALgAECgMJBQAAAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMRAAkJ3CCOCQCZAgARAAkJ3CCOCQCZAgAXAAIJ0gWFbgBXAAAAAA==.',
Ec='Eclipisa:BAAALgADCgQJBAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIPAAcJFgRcyAC/AAAPAAcJFgRcyAC/AAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.Eira:BAAALgAECgMJAgAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAFAAAAAA==.Eleidon:BAAALgAECgYJCwAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMZAAkJ7Q/LKACNAQAZAAgJ8w3LKACNAQAbAAkJqQtMMgB3AQAAAA==.Elèctra:BAACLgAFFH8IAAINAAQJQxIsGgDlAAANAAQJQxIsGgDlAAAuAAQKfzEAAw0ACAlWHgkGAMkBAA0ACAlWHgkGAMkBAAcABglPFLpAADEBAAAA.',
En='Enhai:BAAALgADCgEJAQAAAA==.Enseth:BAAALgAECgQJCQAAAA==.Enyô:BAABLgAECn8kAAIQAAkJJRUARQAMAgAQAAkJJRUARQAMAgAAAA==.',
Eo='Eorae:BAAALgAECgIJCAAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.',
Er='Erada:BAACLgAFFH8GAAIQAAMJJBjXLgDzAAAQAAMJJBjXLgDzAAAuAAQKfyUAAhAACQnOHdMZAL8CABAACQnOHdMZAL8CAAAA.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAkJGgAJAN0WAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgUJCwABLgAECggJIAABALUPAA==.',
Fa='Faceblock:BAAALgAECgYJCAAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIXAAkJFiakAQBdAwAXAAkJFiakAQBdAwABLgAFFAUJGgAfAD8jAA==.Felzugger:BAABLgAFFH8SAAIJAAUJBhYwHAAXAQAJAAUJBhYwHAAXAQABLgAFFAkJJAAHAIEXAA==.',
Fh='Fhalanx:BAABLgAECn8UAAMEAAYJJQZTXwC4AAAEAAUJ6gZTXwC4AAAOAAUJzQnKKwB4AAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAFFAUJDQAiABEOAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAACLgAFFH8HAAIQAAMJ0gavTQCBAAAQAAMJ0gavTQCBAAAuAAQKfyMAAhAABwkkHycGAPgBABAABwkkHycGAPgBAAAA.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAFFAMJBwAQANIGAA==.Flapp:BAABLgAECn8lAAMPAAkJWxa2PgDhAQAPAAkJWxa2PgDhAQAYAAIJsQiDXABZAAABLgAFFAMJBwAQANIGAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Fllaapp:BAAALgAECgIJAgAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.Flynnrider:BAAALgAECgEJAQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIcAAkJ1Bl2MAAaAgAcAAkJ1Bl2MAAaAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenlight:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgUJCgABLgAFFAUJCgAMAIAPAA==.Furyiosa:BAAALgAECgMJBAAAAA==.',
Ga='Gaiseric:BAABLgAFFH8HAAIGAAMJ7xJinADYAAAGAAMJ7xJinADYAAAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Gango:BAAALgAECgEJAQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQZAAgJ1QkkMABdAQAZAAgJ1QkkMABdAQAbAAQJRQNmZACcAAAkAAEJ8gqJjAAuAAAAAA==.Geraldene:BAABLgAECn8VAAIbAAgJMQrSNQAqAQAbAAgJMQrSNQAqAQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgAECgMJAwAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgAECgQJBQAAAA==.',
Go='Goonenhance:BAAALgAECgIJBAAAAA==.Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Graysun:BAAALgAFFAEJAQAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIJAAkJ6hYjNgDtAQAJAAkJ6hYjNgDtAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJRQASAMgaAA==.Grimthruul:BAABLgAECn8zAAIHAAkJ/w7oBQBWAQAHAAkJ/w7oBQBWAQAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBUfHgBsAQATAAcJUBUfHgBsAQAAAA==.Grumpig:BAABLgAECn8cAAIEAAYJ0BzUAgDmAQAEAAYJ0BzUAgDmAQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAABLgAECn8VAAIOAAYJwCXGKwB0AgAOAAYJwCXGKwB0AgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMbAAkJ0xH0KQCjAQAbAAcJDRX0KQCjAQAkAAcJAhLkPgAVAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAFAAAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAFAAAAAA==.Hanharr:BAAALgAECgMJBQAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.Hayleigh:BAAALgAECgMJAwAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhGxJQCfAQAiAAkJBhGxJQCfAQAAAA==.Heyro:BAAALgAFFAEJAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgUJDAAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8WAAIBAAUJVxrhBgA9AQABAAUJVxrhBgA9AQAuAAQKfzUAAgEACQkwHisFAKMCAAEACQkwHisFAKMCAAAA.Hiphopuler:BAABLgAECn85AAIbAAgJpBmgGwAAAgAbAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMOAAkJUB6eHwCuAgAOAAkJUB6eHwCuAgASAAQJUxioIgDzAAAAAA==.Holybeef:BAAALgAECgEJAgAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgUJCQAAAA==.Holyschmit:BAABLgAECn80AAIEAAgJYRpSGwApAgAEAAgJYRpSGwApAgAAAA==.Holysmite:BAAALgADCgEJAQAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxO8FACnAQAUAAkJVxO8FACnAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RmYCgDDAQAWAAgJ1RmYCgDDAQAAAA==.Huntris:BAABLgAECn8aAAIdAAkJ6RlDFAADAgAdAAkJ6RlDFAADAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAABLgAECn8gAAMNAAcJ2Q0WFwCfAAANAAcJ2Q0WFwCfAAAHAAUJRASLewB9AAAAAA==.Hypnotykk:BAABLgAECn8aAAIcAAgJFBQITwC1AQAcAAgJFBQITwC1AQAAAA==.',
Ia='Iadygaga:BAAALgAFFAEJAQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Ik='Ikova:BAAALgAECgMJBAAAAA==.',
Il='Illogical:BAAALgAECgMJAwABLgAFFAkJIwAQABkXAA==.',
Im='Immunè:BAAALgAECgIJBAABLgAFFAUJEQAGABAXAA==.Imrah:BAABLgAECn80AAQXAAkJuhPvGADqAQAXAAkJuhPvGADqAQARAAMJ2QbdawBtAAAjAAEJrwNU0QAfAAAAAA==.',
In='Incarnate:BAAALgAECgQJCAABLgAECgYJEwAFAAAAAA==.Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgABLgAECgkJEgAFAAAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8UAAIbAAUJThfEEwAoAQAbAAUJThfEEwAoAQAuAAQKfzQAAhsACQlyG6QNAIwCABsACQlyG6QNAIwCAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8TAAIlAAUJvx5nFQBgAQAlAAUJvx5nFQBgAQAuAAQKfyIAAiUACAkzGOkjAHUBACUACAkzGOkjAHUBAAAA.Jocon:BAABLgAECn8mAAIPAAkJAwf5dABQAQAPAAkJAwf5dABQAQAAAA==.Joraan:BAAALgAECgcJCAAAAA==.',
Js='Js:BAAALgADCgIJAgAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kaidò:BAAALgAECgIJAgABLgAECgYJCwAFAAAAAA==.Kailec:BAAALgAECgEJAQAAAA==.Kamo:BAAALgAECgQJCQABLgAFFAQJEAAdALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAdALEOAA==.Kanami:BAABLgAECn8sAAIIAAkJBB/oDACdAgAIAAkJBB/oDACdAgAAAA==.Kaori:BAABLgAECn8UAAIOAAgJCAg/sgAfAQAOAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhmDDQAKAgACAAkJDhmDDQAKAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Katarr:BAAALgAECgUJBQAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgAECgEJAQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx3fDABYAgAlAAkJbx3fDABYAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8UAAIOAAUJIxLOSQAZAQAOAAUJIxLOSQAZAQAuAAQKf0oAAw4ACQl8Go0uAEcCAA4ACQlJGY0uAEcCABIABwlyGk4PAM4BAAAA.Keedron:BAACLgAFFH8aAAMJAAkJ3RYVEwAYAgAJAAgJ+xcVEwAYAgALAAEJDA9UFgBZAAAuAAQKfxsAAgkACAlJJIkLACUDAAkACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIGAAgJqRPodQB4AQAGAAgJqRPodQB4AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8yAAMGAAkJDx++FgC/AgAGAAkJDx++FgC/AgAmAAMJEgmDMgBSAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCggJEQAAAA==.Kilfogg:BAABLgAECn8XAAIHAAcJoxfmKwC5AQAHAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAMJAwAAAA==.Kilua:BAAALgAFFAEJAQAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgUJDAABLgAFFAIJAgAFAAAAAA==.Kiyo:BAACLgAFFH8JAAMKAAMJRwkCSwChAAAKAAMJRwkCSwChAAAMAAMJeg8uIQCdAAAuAAQKfycABAwACQlJGBINAAECAAwACQlJGBINAAECAAoABgk3EMdKAAEBAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIQAAcJ/R75BgDwAQAQAAcJ/R75BgDwAQAuAAQKfxcAAhAACAm6IwgVACoDABAACAm6IwgVACoDAAAA.Kons:BAAALgADCgEJAQAAAA==.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAFAAAAAA==.Korvasa:BAAALgAECgQJBAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAAOAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIPAAMJ2APnjQCpAAAPAAMJ2APnjQCpAAAuAAQKfxYAAg8ABwlgFFZSANABAA8ABwlgFFZSANABAAAA.Krymzendeath:BAABLgAECn8sAAMSAAkJKQvrBAAXAQASAAkJKQvrBAAXAQAOAAUJcgLeTwFfAAABLgAFFAQJJgAUALUaAA==.Krísztina:BAABLgAECn8pAAQaAAgJWAuFEQBLAQAaAAgJwgiFEQBLAQAYAAgJqAmDFQD+AAAPAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAkJGgAJAN0WAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAFAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kä']='Kämö:BAAALgAECgEJAQABLgAFFAQJEAAdALEOAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIdAAQJsQ5QFgAeAQAdAAQJsQ5QFgAeAQAuAAQKfyQAAh0ACQkmGOQHAHICAB0ACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Laelada:BAAALgAFFAEJAQAAAA==.Lakey:BAABLgAECn8XAAQbAAgJByaFFgAdAgAbAAgJByaFFgAdAgAZAAUJ6SJ7HADqAQAkAAMJOA73SgCuAAABLgAFFAYJIAADAJIYAA==.Lakeyy:BAACLgAFFH8gAAMDAAYJkhgzIgBHAQADAAUJQRYzIgBHAQAiAAUJAxVCIQAWAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAABLgAFFH8FAAIjAAUJxxHRLgD+AAAjAAUJxxHRLgD+AAABLgAFFAYJIAADAJIYAA==.Lanayrd:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Lanternesmog:BAAALgAECgEJAQAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAAOAC0cAA==.Lawrence:BAACLgAFFH8MAAMHAAUJbxBDKQDwAAAHAAQJbxBDKQDwAAANAAQJ7QeaSADLAAAuAAQKfyMAAwcACAmaIcIKAOoCAAcACAmaIcIKAOoCAA0AAwkbDkGnAH0AAAEuAAUUBwkUAAkABhMA.Lazuril:BAAALgAECgEJAgAAAQ==.',
Le='Leadhead:BAAALgADCgEJAQAAAA==.Leanhaum:BAAALgAECgIJBAAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.Lewless:BAAALgAECgEJAQAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lickmybubble:BAAALgAECgEJAQAAAA==.Lightbane:BAAALgADCgYJBgAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilikoii:BAAALgAECgMJAwABLgAFFAYJIAADAJIYAA==.Lilslaver:BAAALgAECgcJEQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Liradra:BAAALgAECgEJAQAAAA==.Lisex:BAACLgAFFH8rAAQGAAkJBRUrEwBCAgAGAAcJ1xYrEwBCAgAmAAQJSQ0ZEgABAQAeAAIJTAgMHwBMAAAuAAQKfzEAAwYACQmjI/cWAPICAAYACQmZI/cWAPICACYABwkiHS0JAPQBAAAA.Lithe:BAABLgAFFH8MAAIOAAQJKQ5WHwD7AAAOAAQJKQ5WHwD7AAAAAA==.',
Lo='Locklear:BAABLgAECn8iAAIOAAkJbBbFRgDyAQAOAAkJbBbFRgDyAQAAAA==.Logic:BAACLgAFFH8jAAMQAAkJGRckGQAsAgAQAAgJqBQkGQAsAgAhAAQJyBgZAwDnAAAuAAQKfysAAhAACQlvI0kUAOACABAACQlvI0kUAOACAAAA.Lolbrez:BAAALgAECgEJAQAAAA==.Lolshield:BAAALgAECgYJCgABLgAFFAUJGgARAAwfAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8yAAISAAkJjgodHQAsAQASAAkJjgodHQAsAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xlBBQAXAgAnAAgJ9xlBBQAXAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAYJIAADAJIYAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAgJDAAcAAYHAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAACLgAFFH8GAAIGAAIJeRFF3gCGAAAGAAIJeRFF3gCGAAAuAAQKfy4AAgYACQkvHUApAFwCAAYACQkvHUApAFwCAAAA.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH81AAIJAAkJyiA5AgDsAgAJAAkJyiA5AgDsAgAuAAQKfycAAgkACQkZIkEIAEgDAAkACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAkJNQAJAMogAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIQAAkJbhW9YQC8AQAQAAkJbhW9YQC8AQAAAA==.Magirzul:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAQ==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAIOAAQJLRynNgBAAQAOAAQJLRynNgBAAQAuAAQKfy0AAg4ACQn9Ho0kAHMCAA4ACQn9Ho0kAHMCAAAA.Makima:BAAALgAECgUJBQAAAA==.Malazen:BAAALgAECgYJDwAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIGAAkJ+BwcIQCEAgAGAAkJ+BwcIQCEAgAAAA==.Mamageek:BAABLgAECn8XAAINAAkJ9hHmKADsAQANAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAFAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Mareo:BAAALgAECgEJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAQAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Mastahblasta:BAAALgAECgYJBgAAAA==.Mastahunta:BAAALgAECgQJBAABLgAFFAQJCAANAEMSAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8kAAIOAAkJcB3eJgBoAgAOAAkJcB3eJgBoAgAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIeAAgJyBTVGwB9AQAeAAgJyBTVGwB9AQABLgAECgkJHgACACEWAA==.Mcversatile:BAABLgAECn8eAAICAAkJIRZ1EgDKAQACAAkJIRZ1EgDKAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIbAAkJrBksEABkAgAbAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8yAAIMAAkJ+yJgAAA7AwAMAAkJ+yJgAAA7AwAuAAQKfycAAgwACQkZJk4AAN8DAAwACQkZJk4AAN8DAAAA.Meleeman:BAAALgAECgUJBQAAAA==.Mereoleona:BAAALgAECggJEgAAAA==.Metalmagus:BAABLgAECn8iAAIQAAgJCRp9TwDtAQAQAAgJCRp9TwDtAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSIyBQCTAgAgAAkJTSIyBQCTAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAkJGgAJAN0WAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8mAAIRAAkJYRMlHwCtAQARAAkJYRMlHwCtAQAAAA==.Misslobster:BAABLgAECn8VAAMNAAkJoRMdCgBVAQANAAkJoRMdCgBVAQAHAAEJ6wb4iwAsAAAAAA==.Mistweaver:BAABLgAFFH8NAAIjAAQJ9BuIJQBBAQAjAAQJ9BuIJQBBAQAAAA==.Mistygoblin:BAABLgAECn8XAAIjAAYJQA3mFgCvAAAjAAYJQA3mFgCvAAABLgAFFAQJCAANAEMSAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgkJDgAAAA==.Mokoko:BAACLgAFFH8gAAMKAAcJfxqrBgAPAgAKAAcJfxqrBgAPAgAfAAIJGRPOBQBNAAAuAAQKfzEAAwoACQmhIdEFACcDAAoACQmHIdEFACcDAB8ABwlFHWYLACUCAAAA.Mokolock:BAAALgADCgEJAQAAAA==.Mokomage:BAAALgAECgYJDwABLgAFFAcJIAAKAH8aAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR1hDwBpAgAiAAkJKR1hDwBpAgADAAQJDxFhggDUAAACAAEJch3NYQBNAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgAECgQJBAAAAA==.Moothai:BAABLgAECn8yAAMXAAkJbCPlCAC3AgAXAAkJbCPlCAC3AgARAAYJ7hlIKwBdAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moshiach:BAAALgAECgYJBgAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgAECgMJAwABLgAECgYJBgAFAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJGgARAAwfAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAFAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAFAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIGAAkJVBthUQDPAQAGAAkJVBthUQDPAQAAAA==.Necrota:BAACLgAFFH8JAAIGAAMJLxxThwD7AAAGAAMJLxxThwD7AAAuAAQKfxoAAwYACAmVHrZHAOsBAAYACAkWHrZHAOsBAB4AAQlcG5FBAEUAAAEuAAUUBwkbABAA/R4A.Nekronomicon:BAAALgAFFAMJBAABLgAFFAQJGAAZAMUPAA==.Neuron:BAACLgAFFH8hAAIDAAgJPhutAQD6AQADAAgJPhutAQD6AQAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.Nexgen:BAAALgAECgUJBQAAAA==.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8uAAIoAAkJnxBLBwDoAQAoAAkJnxBLBwDoAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nofitputspit:BAAALgAECgYJBgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAABLgAECn8YAAIPAAYJ4gkHFACvAAAPAAYJ4gkHFACvAAAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAFAAAAAA==.',
Nu='Nucwel:BAAALgAECgMJAwAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgAECgQJBAAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAIEAAgJEiKdEQCHAgAEAAgJEiKdEQCHAgAAAA==.Oreyn:BAAALgAECgcJDgAAAA==.Orgelmir:BAAALgAECgEJAQAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQABLgAECgYJBgAFAAAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladian:BAAALgAECgIJAgABLgAFFAQJCAANAEMSAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn9FAAMSAAkJyBpLCQA9AgAOAAkJ2RiyLABOAgASAAkJCBlLCQA9AgAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJEAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAACLgAFFH8HAAIlAAMJFRzpDQARAQAlAAMJFRzpDQARAQAuAAQKfxwAAiUACAlQHpMTAAcCACUACAlQHpMTAAcCAAAA.Patoko:BAABLgAECn8qAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8aAAMfAAUJPyOrAQCKAQAfAAUJPyOrAQCKAQAKAAQJfB2dHwBjAQAuAAQKfzwAAx8ACQlUJi4AAIUDAB8ACQlRJi4AAIUDAAoABgnPIC4cAPQBAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSMwGQCUAQADAAQJbSMwGQCUAQAuAAQKfzsAAwMACQn9Jd8AANkDAAMACQn9Jd8AANkDACIABgkfECJEAPwAAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQABLgAECgkJIgADADQaAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAFFAIJAgAAAA==.Phráxas:BAAALgAECgIJAgABLgAECgcJEwAFAAAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8vAAMbAAcJ+R4/FgAgAgAbAAcJ+R4/FgAgAgAkAAUJnR9RLwBiAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgIJAwABLgAECgUJCAAFAAAAAA==.',
Po='Poepoe:BAAALgAFFAEJAQAAAA==.Polyrhythm:BAABLgAFFH8FAAMaAAEJFxHmEwBGAAAaAAEJFxHmEwBGAAAPAAEJ6QW4ZAA4AAAAAA==.Polyrhythms:BAAALgAFFAEJAgAAAA==.Porthub:BAAALgAECgQJBwAAAA==.Potatofist:BAAALgADCgEJAQABLgAECgcJGAADAP4gAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIZAAMJlQi6NAC5AAAZAAMJlQi6NAC5AAAuAAQKfx4AAhkABgmxH8MTABACABkABgmxH8MTABACAAAA.Priyoshi:BAAALgAECgEJAQAAAA==.Prosthesis:BAAALgAECgQJBAAAAA==.Prrowl:BAABLgAECn8WAAICAAUJKwg5DgB5AAACAAUJKwg5DgB5AAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAABLgAECn8WAAIOAAkJUhCHVADMAQAOAAkJUhCHVADMAQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAAOAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.Rixxa:BAABLgAECn8gAAINAAYJzwoxhQDTAAANAAYJzwoxhQDTAAAAAA==.Rizzpinchy:BAAALgADCgUJBQAAAA==.',
Ro='Roksolid:BAABLgAECn8lAAIHAAkJWxcIGwAJAgAHAAkJWxcIGwAJAgAAAA==.Rollos:BAABLgAECn8gAAIPAAkJUBVvNgD/AQAPAAkJUBVvNgD/AQAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxK2MAC3AQAjAAgJCxK2MAC3AQAAAA==.Ronaro:BAAALgADCgEJAQAAAA==.Rookesbane:BAAALgAECgIJAgAAAA==.Rotpaw:BAAALgAECgMJAwAAAA==.Roxyvega:BAAALgADCgIJAgABLgAFFAIJBgAEAA0LAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8jAAIKAAkJBiLJBQCpAgAKAAkJBiLJBQCpAgAuAAQKfyEAAgoACQm3JfAAAMwDAAoACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8WAAQPAAYJUhXLlAASAQAPAAUJUhXLlAASAQAYAAEJ+A1zcAA2AAAaAAEJAABJSgAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJRQASAMgaAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAIAH4aAA==.Saeli:BAAALgAECgEJAgAAAA==.Saelybricek:BAAALgAECggJCQAAAA==.Saintnick:BAAALgAECgYJDwAAAA==.Salvester:BAAALgAECgIJAgABLgAECgcJLwAbAPkeAA==.Samtarkras:BAABLgAECn8tAAIMAAkJqhqfBwB8AgAMAAkJqhqfBwB8AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAFAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAABLgAFFH8MAAIcAAgJBgdcNwA+AQAcAAgJBgdcNwA+AQAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8WAAIaAAQJtRyfAQBZAQAaAAQJtRyfAQBZAQAuAAQKf8cABBoACQmPJUoAAGcDABoACQmPJUoAAGcDAA8ABwmaIrMCAGQCABgABwmAIEYBANMBAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8zAAMkAAkJsxjrEQBGAgAkAAkJsxjrEQBGAgAbAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8JAAIkAAMJThFbJwDBAAAkAAMJThFbJwDBAAAuAAQKf2oAAiQACQnFJOUCADYDACQACQnFJOUCADYDAAEuAAUUCQkkAAcAgRcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAGAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAEBLgAFFH8MAAIPAAcJiBiDLACTAQAPAAcJiBiDLACTAQABLgAFFAcJHgAQAMEiAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shastashaman:BAAALgAFFAIJAwAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIcAAQJSQvIXQDpAAAcAAQJSQvIXQDpAAAuAAQKfyoAAhwACAnIIAgYAJcCABwACAnIIAgYAJcCAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAkJIwAKAAYiAA==.Shodin:BAAALgADCgEJAQAAAA==.Shoheki:BAAALgADCgMJAwAAAA==.Shotsyll:BAAALgAECgUJBgABLgAECggJGAADAEkZAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.Skynomad:BAAALgAECgQJBgABLgAECgYJCgAFAAAAAA==.',
Sl='Slyde:BAABLgAECn84AAIGAAkJ5SQUBQBUAwAGAAkJ5SQUBQBUAwAAAA==.',
Sm='Smalldk:BAACLgAFFH8XAAIGAAcJbRY8FwBIAQAGAAcJbRY8FwBIAQAuAAQKfyUAAgYACAnPIq8VAPoCAAYACAnPIq8VAPoCAAEuAAUUCQkNAAoAxxMA.Smick:BAACLgAFFH8GAAIEAAIJDQtLGwBjAAAEAAIJDQtLGwBjAAAuAAQKfyEAAgQACQmiElcsALABAAQACQmiElcsALABAAAA.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgcJDgAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snowingmagic:BAAALgAECgEJAQABLgAFFAQJBAAFAAAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solfreid:BAAALgADCgMJAwABLgAECgkJLQAJAMAdAA==.Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCOICwAqAgACAAcJNSGICwAqAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9TAAIIAAkJjiFzCQDLAgAIAAkJjiFzCQDLAgAAAA==.Soulfox:BAAALgAECgEJAwABLgAFFAQJCAANAEMSAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAUJFAAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAABLgAECn8VAAIGAAcJTRdAXgCtAQAGAAcJTRdAXgCtAQAAAA==.',
Sq='Squidmonk:BAABLgAFFH8IAAIjAAMJfxG0HwCrAAAjAAMJfxG0HwCrAAAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8qAAMVAAgJ7BSwDACKAQAVAAgJ7BSwDACKAQAJAAIJEg11JgBSAAABLgAFFAQJFgAaALUcAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAABLgAECn8UAAIlAAgJgROhHgChAQAlAAgJgROhHgChAQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIXAAgJvhumAQB4AgAXAAgJvhumAQB4AgAuAAQKfxUAAhcACAlEH5kMALECABcACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormscout:BAAALgAFFAIJAwAAAA==.Stormshout:BAAALgAECgEJAQAAAA==.Stormsigil:BAAALgAECgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Stormsurge:BAAALgAECgIJBAAAAA==.Straigtasian:BAAALgAECgQJBwAAAA==.Straydog:BAABLgAECn8uAAMNAAkJ4ySPAQC5AwANAAkJ4ySPAQC5AwAHAAEJHhRCnwA7AAAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIGAAkJlhYXfwBlAQAGAAkJlhYXfwBlAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAFAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAFAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAFAAAAAA==.Superpowers:BAABLgAECn8XAAIRAAgJWR+zDQBdAgARAAgJWR+zDQBdAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yFZBADWAgATAAkJ4yFZBADWAgAAAA==.Sus:BAABLgAFFH8IAAIcAAQJAwokcQC9AAAcAAQJAwokcQC9AAAAAA==.Suzel:BAABLgAECn8dAAIGAAUJSwn4HgCiAAAGAAUJSwn4HgCiAAAAAA==.',
Sw='Sweatmachine:BAAALgAECgEJAQAAAA==.Swoof:BAAALgAECggJEQABLgAFFAgJDAAcAAYHAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn88AAILAAkJhxR8EwD5AQALAAkJhxR8EwD5AQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAFFAIJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAZAN8OAA==.Synwise:BAABLgAECn83AAIDAAkJaiFIBgBTAwADAAkJaiFIBgBTAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8TAAIcAAUJGhaVPAA0AQAcAAUJGhaVPAA0AQAuAAQKfzUAAxwACQlmHRAhAGICABwACQlmHRAhAGICABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIXAAgJCxnTGAAcAgAXAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQbAAkJlhqZEQBUAgAbAAkJlhqZEQBUAgAZAAQJlA2XVgCmAAAkAAIJbhIWagB2AAAAAA==.',
Te='Teknicaliti:BAAALgAECgEJAgAAAA==.',
Th='Thanah:BAAALgAECgUJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8UAAIGAAUJXBOpZwApAQAGAAUJXBOpZwApAQAuAAQKfyoAAwYACQkdGJ1MANwBAAYACQkdGJ1MANwBACYAAQneCWQ+ACoAAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thendron:BAAALgAECgEJAQABLgAFFAMJBAAFAAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAFAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8QAAIVAAQJmBwIBAA/AQAVAAQJmBwIBAA/AQAuAAQKfzkAAhUACQnWHjYEAIQCABUACQnWHjYEAIQCAAAA.Tinytea:BAACLgAFFH8QAAIRAAQJhSOwEgCOAQARAAQJhSOwEgCOAQAuAAQKf0IAAhEACQkyJdkBAEoDABEACQkyJdkBAEoDAAAA.Tinytilted:BAAALgAECgQJBAAAAA==.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJEwAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8OAAMEAAUJuxvEFACEAQAEAAUJuxvEFACEAQAOAAEJUQ1QugBDAAAuAAQKfygAAwQACQkYHeUVAGECAAQACAkqH+UVAGECAA4ABQnfEC+9AAwBAAAA.Torb:BAAALgAECgYJBgAAAA==.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgAECgMJCQAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.Tough:BAAALgADCgEJAQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMIAAYJ0SGHLQD9AQAIAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJDAAGABAVAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgAECgIJAgABLgAECgcJEAAFAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAFAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAFAAAAAA==.Tuckrh:BAAALgAECgYJCAAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgUJCQAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgfwIwB7AAAUAAMJfgfwIwB7AAAuAAQKfx4AAhQACQkPD/UaAGEBABQACQkPD/UaAGEBAAEuAAUUBAkUAAcAQAoA.Twippy:BAABLgAFFH8UAAIHAAQJQApsGwCpAAAHAAQJQApsGwCpAAAAAA==.Twistbae:BAAALgAFFAMJAwABLgAFFAQJFAAHAEAKAA==.Twobeers:BAAALgAECgYJBgAAAA==.',
Ty='Tyanis:BAABLgAECn8cAAIOAAYJ1woB4QDdAAAOAAYJ1woB4QDdAAABLgAECgcJDgAFAAAAAA==.Tyriam:BAABLgAECn8wAAMOAAkJ2hrVLQBJAgAOAAgJ2hrVLQBJAgAEAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIQAAgJixODbgCdAQAQAAgJixODbgCdAQAAAA==.',
Un='Undeadboss:BAAALgAECgEJAQABLgAFFAQJCAANAEMSAA==.Underwear:BAAALgAECgMJAwABLgAECgQJBwAFAAAAAA==.Ungrul:BAABLgAECn8bAAMUAAgJzAdrBQD5AAAUAAgJcQdrBQD5AAATAAEJzQvdFAAoAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Vandy:BAABLgAECn8nAAMLAAkJLAraNwAmAQALAAYJtwvaNwAmAQAJAAkJXAmLkAD/AAAAAA==.Varodonaris:BAAALgAECgYJCgAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECggJCAAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8dAAMfAAcJihJJBQASAQAfAAUJtg9JBQASAQAKAAcJdBJCHQC0AAAuAAQKfyAAAx8ACQktHUgEAMkCAB8ACAlhIEgEAMkCAAoAAgmBEIGHAE0AAAAA.Verso:BAABLgAECn8rAAInAAkJWRtxAwBnAgAnAAkJWRtxAwBnAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinius:BAAALgADCgEJAQAAAA==.Vinushka:BAAALgAECgkJEAAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgkJMwAKABYcAA==.Vitalithry:BAABLgAECn8zAAMKAAkJFhx4EABkAgAKAAkJDhx4EABkAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.Vizzeek:BAAALgAECgEJAQABLgAFFAMJBgAGANoRAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAFAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgMJBAAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAAOAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAFAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAACLgAFFH8HAAIGAAMJvQ3KpQDOAAAGAAMJvQ3KpQDOAAAuAAQKfyoAAgYACQlzFeFkAJ0BAAYACQlzFeFkAJ0BAAAA.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQHAAkJ0R86CQDJAgAHAAkJ0R86CQDJAgANAAgJ4BnuIwA3AgAgAAIJ7xHPPQA3AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8aAAMkAAgJhRXcCQDEAQAkAAgJhRXcCQDEAQAbAAEJ0gvrHwAmAAAuAAQKfz4AAyQACAlFIsIJALICACQACAlFIsIJALICABsAAQklJexdAGIAAAAA.Windoelicker:BAAALgAECgYJEgAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh42DgC7AgAjAAgJqh42DgC7AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8eAAIDAAcJpA3WCACeAQADAAcJpA3WCACeAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulfbane:BAAALgADCgYJBgAAAA==.Wulfvane:BAAALgADCgMJAwAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCgkJDgAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMcAAkJ7xq3OQD3AQAcAAgJFxu3OQD3AQAWAAgJbxbvJgDyAQAAAA==.',
Xe='Xesxia:BAAALgAECgMJAwAAAA==.',
Xu='Xu:BAACLgAFFH8MAAIGAAQJEBXscgAaAQAGAAQJEBXscgAaAQAuAAQKfx8AAwYACAn0HiU8ABACAAYACAn0HiU8ABACACYAAQlgENk8AC0AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAIEAAkJdgr/MQCOAQAEAAkJdgr/MQCOAQAAAA==.Yey:BAABLgAECn8hAAQEAAkJjxm5GgAvAgAEAAkJjxm5GgAvAgASAAMJJgGTTAA6AAAOAAEJDQTUwgEiAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8iAAIQAAkJ8g/PVADeAQAQAAkJ8g/PVADeAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zaralan:BAAALgADCgQJBAAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIPAAMJGQxVfwDGAAAPAAMJGQxVfwDGAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChtaDAAbAgACAAgJChtaDAAbAgAiAAUJvw2aRAD6AAABAAIJpAcYXQAlAAABLgAFFAMJBgAPABkMAA==.Zaydämon:BAABLgAECn8WAAIJAAgJ4R1IHwCWAgAJAAgJ4R1IHwCWAgABLgAFFAMJBgAPABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zello:BAABLgAECn8XAAMbAAgJlAuGCQDgAAAbAAUJiw6GCQDgAAAkAAgJdgJrXAClAAAAAA==.Zenzuken:BAAALgAECgEJAQAAAA==.',
Zh='Zhengy:BAAALgADCgMJAwABLgAECgcJEwAFAAAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgkJMAABAL8YAA==.Ziggybeast:BAACLgAFFH8KAAIDAAIJBxm/SgCRAAADAAIJBxm/SgCRAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTIgGpAGIAAAIAAwl4DVdhAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCgADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIGAAIJZxipyACbAAAGAAIJZxipyACbAAAuAAQKf0MAAgYACQlMHTQsAE8CAAYACQlMHTQsAE8CAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgUJBgAAAA==.',
Zy='Zydia:BAAALgAECgUJCQAAAA==.',
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
