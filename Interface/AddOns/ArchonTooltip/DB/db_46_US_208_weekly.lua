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
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8fAAQBAAgJtQ8xGgA8AQABAAcJohAxGgA8AQACAAgJpAk3OADGAAADAAEJJQf12gAnAAAAAA==.',
Ac='Acrux:BAAALgADCgQJBAABLgAFFAIJBQAEAA0LAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAABLgAFFH8RAAIFAAUJEBc5ZgArAQAFAAUJEBc5ZgArAQAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJCwAAAA==.Aethelwold:BAAALgADCgQJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.Aginah:BAAALgADCgcJDQABLgAECgYJDgAGAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAABLgAECn8cAAIHAAUJ3QqgCwCYAAAHAAUJ3QqgCwCYAAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIIAAYJfhrrQQA9AQAIAAYJfhrrQQA9AQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAIAH4aAA==.',
Al='Alariel:BAABLgAECn8tAAIJAAkJ3xmhJQA3AgAJAAkJ3xmhJQA3AgABLgAFFAQJFAAKALMeAA==.Alary:BAAALgAECgEJAQABLgAFFAQJBAAGAAAAAA==.Albesuri:BAAALgAECgUJBQABLgAFFAkJGgAJAN0WAA==.Albskin:BAAALgAECgUJCgAAAA==.Alcazar:BAABLgAECn8tAAMJAAkJwB2GHwBYAgAJAAkJwB2GHwBYAgALAAEJAAAniAAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAIMAAgJGwj8HwB+AQAMAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJHwAMANcZAA==.Alerys:BAAALgAFFAIJAgABLgAFFAgJHwAMANcZAA==.Alliar:BAABLgAECn8nAAMNAAkJxBypJwAhAgANAAkJxBypJwAhAgAHAAIJLgkwkwBNAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAGAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCQABLgAFFAgJHwAMANcZAA==.',
Am='Amalek:BAAALgAECgEJAQAAAA==.Amerha:BAABLgAECn8eAAMNAAkJuQ1cOwDBAQANAAkJuQ1cOwDBAQAHAAIJiwZzlwBHAAAAAA==.Amgems:BAAALgAECgIJAgAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.Amordred:BAAALgAECgEJAQAAAA==.',
An='Anapplepi:BAAALgADCgUJBQAAAA==.Anasterion:BAACLgAFFH8JAAIOAAMJ0B/1QwAjAQAOAAMJ0B/1QwAjAQAuAAQKfxwAAg4ACAnRIZ4yADYCAA4ACAnRIZ4yADYCAAEuAAUUAwkJAAoARwkA.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAABLgAECn8YAAIDAAQJURHEegDHAAADAAQJURHEegDHAAAAAA==.Ansley:BAAALgAECgMJAwABLgAECgQJCwAGAAAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAABLgAECn8VAAILAAcJORe/GwCgAQALAAcJORe/GwCgAQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgAECgEJBAAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.Artimisia:BAAALgAECgEJAQABLgAECgkJPQAPAFQgAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgAECgIJAgAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8oAAIQAAYJ5houRgBZAQAQAAYJ5houRgBZAQAuAAQKfy8AAhAACQkEI5MlAIYCABAACQkEI5MlAIYCAAAA.',
At='Athelred:BAAALgADCgYJBgAAAA==.Atlasdark:BAABLgAECn8fAAIHAAkJvhfUGgAKAgAHAAkJvhfUGgAKAgABLgAECgEJAQAGAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasgift:BAAALgAECgcJDQABLgAECgEJAQAGAAAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAGAAAAAA==.Atrell:BAABLgAECn8eAAIOAAkJrRiqSQDpAQAOAAkJrRiqSQDpAQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgAECgYJBwABLgAFFAUJGgARAAwfAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJDwABLgAECgYJCwAGAAAAAA==.Balrock:BAAALgAECgEJAQAAAA==.Balthromaw:BAABLgAECn81AAIPAAkJIRzJJABLAgAPAAkJIRzJJABLAgAAAA==.Bangar:BAAALgAECgcJEQAAAA==.Bansol:BAAALgAECgMJBQAAAA==.Barli:BAAALgAECgIJAgAAAA==.Barqs:BAAALgAFFAIJBAAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSIAJwAYAgADAAYJGSIAJwAYAgAAAA==.Bartahh:BAAALgAECggJEwAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCwABLgAECgkJKwAIAPwcAA==.Beardwaffle:BAABLgAECn8rAAIIAAkJ/BwgFABQAgAIAAkJ/BwgFABQAgAAAA==.Bearlando:BAABLgAFFH8IAAICAAUJeRv8BQCcAQACAAUJeRv8BQCcAQABLgAFFAgJHQAHANAXAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgAECgUJBQAAAA==.Belfdelphine:BAABLgAECn8ZAAQOAAYJiyIISgDoAQAOAAUJiyIISgDoAQASAAUJyw9XKgC5AAAEAAMJdQ7MbgB7AAAAAA==.',
Bi='Bifurthegrey:BAAALgAECgcJDgAAAA==.Bigbubba:BAACLgAFFH8HAAIQAAMJ1wRmmACbAAAQAAMJ1wRmmACbAAAuAAQKfxQAAhAABwkyEx20AHYBABAABwkyEx20AHYBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Billy:BAAALgAECgMJAwABLgAFFAYJEwAJAIIUAA==.Biophage:BAACLgAFFH8SAAMTAAQJvx1QFQA0AQATAAQJixpQFQA0AQAIAAQJMhqVIQAsAQAuAAQKfygABAgACAkOJC0UAKwCAAgACAl0Iy0UAKwCABQAAwmQJPMiABkBABMABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgkJHgAKAI8NAA==.Blaxdevoured:BAABLgAECn8ZAAIJAAkJFBggMgD9AQAJAAkJFBggMgD9AQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodemongar:BAAALgAECgUJCAAAAA==.Bloodhoundss:BAABLgAECn8nAAIIAAkJhRgYGgAdAgAIAAkJhRgYGgAdAgAAAA==.Blössöm:BAABLgAECn8gAAIVAAgJFBWDDACNAQAVAAgJFBWDDACNAQAAAA==.',
Bo='Bob:BAACLgAFFH8ZAAIJAAYJCBZ4CQCTAQAJAAYJCBZ4CQCTAQAuAAQKfyYAAgkACQk+IdoIAEIDAAkACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8nAAINAAkJdxeCJAAzAgANAAkJdxeCJAAzAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braegen:BAAALgAECgUJBQABLgAECgcJEwAGAAAAAA==.Braera:BAAALgAECgEJAQAAAA==.Brantoz:BAABLgAECn8hAAIIAAkJ1iUYAQB3AwAIAAkJ1iUYAQB3AwABLgAFFAYJAgAGAAAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAFFAEJAQAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAFFAEJAQAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8gAAIIAAkJ4hIaBgAbAQAIAAkJ4hIaBgAbAQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8IAAIWAAIJihwEJQCGAAAWAAIJihwEJQCGAAAAAA==.Bréwjitsu:BAAALgAECgQJBAABLgAECgkJIAANAFUaAA==.',
Bu='Bubble:BAAALgAECgEJAQAAAA==.Buffmeister:BAAALgAECgMJAwAAAA==.Bugonia:BAAALgAECgEJAQAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Bullocks:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.Bungus:BAAALgAECgEJAQAAAA==.Buu:BAABLgAFFH8FAAIXAAIJyQsmRAA3AAAXAAIJyQsmRAA3AAAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Cainn:BAAALgAECgYJBwABLgAFFAUJEwAOACMSAA==.Caliginosity:BAABLgAECn8YAAIYAAcJeRc2DAD/AQAYAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Camphreth:BAAALgADCgYJBgAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.Cayllia:BAAALgAECgEJAQAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgYJDgAAAA==.Cesard:BAABLgAECn8zAAICAAkJXSBRBADUAgACAAkJXSBRBADUAgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJCQAAAA==.Chemotherapy:BAAALgAFFAMJBAAAAA==.Chillingsly:BAAALgAECgcJCQABLgAFFAQJEgAZAAkXAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIIAAkJZB2HFABMAgAIAAkJZB2HFABMAgAAAA==.Chrondank:BAAALgAECgEJAQAAAA==.Chrondeezee:BAAALgAECgYJDQAAAA==.',
Ci='Ciradyl:BAAALgAECgEJBQAAAA==.Circledebull:BAAALgAECgUJBQAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgYJCgAAAA==.Coeurdeleon:BAACLgAFFH8JAAISAAMJ5hPXCwC5AAASAAMJ5hPXCwC5AAAuAAQKfx8AAxIACQl9HEwIAFUCABIACQlnG0wIAFUCAA4AAglLEWsgAHgAAAAA.Condemnation:BAACLgAFFH8XAAIaAAQJxQ8CDwDnAAAaAAQJxQ8CDwDnAAAuAAQKfzgAAxoACQmjGo8QAGkCABoACQmQFo8QAGkCABsACAnhFvgZAAwCAAAA.Congressmen:BAAALgAECgYJDAAAAA==.Conquest:BAAALgAFFAEJAQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJCQABLgAECgMJAwAGAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAGAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8aAAIEAAkJ9QqzNAB/AQAEAAkJ9QqzNAB/AQAAAA==.',
Cr='Crayak:BAACLgAFFH8SAAILAAUJTxuNDgAwAQALAAUJTxuNDgAwAQAuAAQKfzEAAwsACQnmIjIFAO8CAAsACQnmIjIFAO8CAAkABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgkJLQAJAMAdAA==.Crossbones:BAABLgAECn8rAAMcAAgJlxyQJABQAgAcAAgJlxyQJABQAgAdAAQJWA9OPQDXAAAAAA==.Crux:BAAALgAECgQJBAABLgAECgkJLQAJAMAdAA==.',
Cu='Cuddles:BAAALgAECgEJAQAAAA==.Cudà:BAACLgAFFH8KAAIJAAUJCxFMVADxAAAJAAUJCxFMVADxAAAuAAQKfxwAAgkACAltGqUyAC8CAAkACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8jAAIHAAgJQhV8LQCNAQAHAAgJQhV8LQCNAQAAAA==.Curbstomped:BAAALgAFFAIJAgAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAABLgAECn8WAAIQAAcJMQ+MngA9AQAQAAcJMQ+MngA9AQAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Danarius:BAAALgADCgEJAQAAAA==.Darkvizzy:BAACLgAFFH8GAAIFAAMJ2hFhpwDNAAAFAAMJ2hFhpwDNAAAuAAQKfyYAAwUACQkVItkYALECAAUACQkMItkYALECAB4ABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8cAAIUAAYJTSX7CQCQAQAUAAYJTSX7CQCQAQAuAAQKf00ABBQACAnCJZAFAL0CABQACAmyJZAFAL0CAAgABwnvHpUdAGICABMABgk7IhEZAJEBAAAA.',
De='Deadbones:BAAALgAECgUJBQAAAA==.Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJEwAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgcJCwAAAA==.Demonatrixx:BAABLgAECn8WAAIJAAkJJhQwBwA2AQAJAAkJJhQwBwA2AQAAAA==.Demonicsword:BAAALgAECgUJBQAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAPAPMTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8SAAIQAAUJbhP4YgAcAQAQAAUJbhP4YgAcAQAuAAQKfy4AAhAACAmUG2JBABgCABAACAmUG2JBABgCAAAA.Deselle:BAABLgAECn8gAAIQAAkJmQUBlABQAQAQAAkJmQUBlABQAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCgAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8pAAIDAAkJghKMLQDwAQADAAkJghKMLQDwAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn87AAISAAkJNR1/BQCZAgASAAkJNR1/BQCZAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Dj='Djornaak:BAAALgAECgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgAFFAIJAgAAAA==.Donatelloh:BAABLgAECn8eAAMXAAkJyxJJOgAYAQAXAAgJmxRJOgAYAQARAAYJ/AnfSADYAAAAAA==.Dortbraz:BAAALgAECgYJCAABLgAECgkJFgAOAFIQAA==.Dotmeharder:BAABLgAECn8bAAMPAAcJ8xOkegBnAQAPAAcJ8xOkegBnAQAZAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dp='Dpdoe:BAAALgADCgEJAQAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Dragonkick:BAAALgAECgEJAQAAAA==.Drakelayer:BAACLgAFFH8QAAMKAAMJ+hXCQQDAAAAKAAMJ+hXCQQDAAAAMAAEJ8wGbEwAqAAAuAAQKfx8AAwoABgmoIVAlALQBAAoABgnKH1AlALQBAB8ABgmkHuAMAEABAAAA.Drakeslayer:BAAALgAECgEJAQABLgAFFAMJEAAKAPoVAA==.Drakuza:BAABLgAFFH8JAAINAAQJQBFGNgAJAQANAAQJQBFGNgAJAQAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8eAAIgAAkJ7g1oEACsAQAgAAkJ7g1oEACsAQAAAA==.Draxyl:BAABLgAECn9HAAMFAAkJrxiNMAA9AgAFAAkJrxiNMAA9AgAeAAQJhQQdCwBZAAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMJAAkJpRC7WAB9AQAJAAkJpRC7WAB9AQAVAAUJwwvBHwCfAAAAAA==.Drogbar:BAABLgAECn8kAAMdAAkJzxiZCwBoAgAdAAkJzxiZCwBoAgAWAAgJYAhMFgAGAQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMPAAkJchCSRwDDAQAPAAkJchCSRwDDAQAYAAMJNAYoUQB7AAAAAA==.Druni:BAAALgAECgYJCQAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn80AAIFAAkJ2yGACwARAwAFAAkJ2yGACwARAwAAAA==.Duo:BAABLgAECn9FAAMhAAkJGxR9AAB6AQAhAAgJDhZ9AAB6AQAQAAkJcwdX1gDoAAABLgAECggJHwABALUPAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMRAAkJ3CCOCQCZAgARAAkJ3CCOCQCZAgAXAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8fAAIPAAcJFgRcyAC/AAAPAAcJFgRcyAC/AAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.Eira:BAAALgAECgMJAgAAAA==.',
El='Eladra:BAAALgAECgUJCgABLgAECgYJDgAGAAAAAA==.Eleidon:BAAALgAECgYJCgAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elline:BAAALgADCgYJBwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMaAAkJ7Q/LKACNAQAaAAgJ8w3LKACNAQAbAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8rAAMNAAgJmRo4HwBVAgANAAgJmRo4HwBVAgAHAAYJTxS6QAAxAQAAAA==.',
En='Enseth:BAAALgAECgQJBgAAAA==.Enyô:BAABLgAECn8kAAIQAAkJJRUARQAMAgAQAAkJJRUARQAMAgAAAA==.',
Eo='Eorae:BAAALgAECgIJBwAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
Er='Erada:BAACLgAFFH8FAAIQAAMJRg67LQDLAAAQAAMJRg67LQDLAAAuAAQKfyUAAhAACQnOHdMZAL8CABAACQnOHdMZAL8CAAAA.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAkJGgAJAN0WAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCgAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgUJCwABLgAECggJHwABALUPAA==.',
Fa='Faceblock:BAAALgAECgYJCAAAAA==.Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIXAAkJFiakAQBdAwAXAAkJFiakAQBdAwABLgAFFAUJGgAfAD8jAA==.Felzugger:BAABLgAFFH8SAAIJAAUJBhbLFAAoAQAJAAUJBhbLFAAoAQABLgAFFAgJHQAHANAXAA==.',
Fh='Fhalanx:BAABLgAECn8UAAMEAAYJJQZTXwC4AAAEAAUJ6gZTXwC4AAAOAAUJzQmlHwB9AAAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAFFAQJDAAiABEOAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaapp:BAACLgAFFH8GAAIQAAMJ0gYRQAB/AAAQAAMJ0gYRQAB/AAAuAAQKfyMAAhAABwkkHzkEAPoBABAABwkkHzkEAPoBAAAA.Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAshAA==.Flapfinnigan:BAAALgADCgMJAwABLgAFFAMJBgAQANIGAA==.Flapp:BAABLgAECn8iAAMPAAkJLBS2PgDhAQAPAAkJLBS2PgDhAQAYAAIJsQiDXABZAAABLgAFFAMJBgAQANIGAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Fllaapp:BAAALgAECgIJAgAAAA==.Flowdinstuna:BAAALgAECgYJEQABLgAECggJIQAVAE8TAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIcAAkJ1Bl2MAAaAgAcAAkJ1Bl2MAAaAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenlight:BAAALgAECgcJDQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgUJCgABLgAFFAUJCgAMAIAPAA==.Furyiosa:BAAALgAECgMJBAAAAA==.',
Ga='Gaiseric:BAABLgAFFH8HAAIFAAMJ7xJinADYAAAFAAMJ7xJinADYAAAAAA==.Galandree:BAAALgADCgUJBQAAAA==.Ganyu:BAAALgAECgEJAQAAAA==.Garrosh:BAAALgAECggJBAAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8aAAQaAAgJ1QkkMABdAQAaAAgJ1QkkMABdAQAbAAQJRQNmZACcAAAkAAEJ8gqJjAAuAAAAAA==.Geraldene:BAABLgAECn8VAAIbAAgJMQrSNQAqAQAbAAgJMQrSNQAqAQAAAA==.Geraniho:BAAALgAFFAIJAgAAAA==.',
Gh='Ghouse:BAAALgAECgEJAQAAAA==.Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgAECgMJAwAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Gl='Gloomblade:BAAALgAECgQJBQAAAA==.',
Go='Goonenhance:BAAALgAECgIJBAAAAA==.Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Graysun:BAAALgAFFAEJAQAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn87AAIJAAkJ6hYjNgDtAQAJAAkJ6hYjNgDtAQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgkJCwABLgAECgkJRQASAMgaAA==.Grimthruul:BAABLgAECn8mAAIHAAkJ1gocBwDvAAAHAAkJ1gocBwDvAAAAAA==.Grommkar:BAABLgAECn8XAAITAAcJUBUfHgBsAQATAAcJUBUfHgBsAQAAAA==.Grumpig:BAABLgAECn8ZAAIEAAYJXBz9AQDeAQAEAAYJXBz9AQDeAQAAAA==.',
Gu='Gulli:BAAALgAECgIJAgAAAA==.Gunnulf:BAABLgAECn8VAAIOAAYJwCXGKwB0AgAOAAYJwCXGKwB0AgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMbAAkJ0xH0KQCjAQAbAAcJDRX0KQCjAQAkAAcJAhLkPgAVAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAGAAAAAA==.Hamsandwich:BAAALgAECgYJCAAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgYJCgAGAAAAAA==.Hanharr:BAAALgAECgMJBQAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgMJAwAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJBhGxJQCfAQAiAAkJBhGxJQCfAQAAAA==.Heyro:BAAALgAFFAEJAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hikarisan:BAAALgAECgUJDAAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8WAAIBAAUJVxrhBgA9AQABAAUJVxrhBgA9AQAuAAQKfzUAAgEACQkwHisFAKMCAAEACQkwHisFAKMCAAAA.Hiphopuler:BAABLgAECn85AAIbAAgJpBmgGwAAAgAbAAgJpBmgGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMOAAkJUB6eHwCuAgAOAAkJUB6eHwCuAgASAAQJUxioIgDzAAAAAA==.Holybeef:BAAALgAECgEJAgAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgAECgUJCQAAAA==.Holyschmit:BAABLgAECn80AAIEAAgJYRpSGwApAgAEAAgJYRpSGwApAgAAAA==.Holysmite:BAAALgADCgEJAQAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIUAAkJVxO8FACnAQAUAAkJVxO8FACnAQAAAA==.Hucklebarry:BAABLgAECn8dAAIWAAgJ1RmYCgDDAQAWAAgJ1RmYCgDDAQAAAA==.Huntris:BAABLgAECn8aAAIdAAkJ6RlDFAADAgAdAAkJ6RlDFAADAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAABLgAECn8gAAMNAAcJ2Q2uEACeAAANAAcJ2Q2uEACeAAAHAAUJRASLewB9AAAAAA==.Hypnotykk:BAABLgAECn8aAAIcAAgJFBQITwC1AQAcAAgJFBQITwC1AQAAAA==.',
Ia='Iadygaga:BAAALgAFFAEJAQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Ik='Ikova:BAAALgAECgMJBAAAAA==.',
Il='Illogical:BAAALgAECgMJAwABLgAFFAgJIgAQALEVAA==.',
Im='Immunè:BAAALgAECgIJBAABLgAFFAUJEQAFABAXAA==.Imrah:BAABLgAECn80AAQXAAkJuhPvGADqAQAXAAkJuhPvGADqAQARAAMJ2QbdawBtAAAjAAEJrwNU0QAfAAAAAA==.',
In='Incarnate:BAAALgAECgQJCAABLgAECgYJEwAGAAAAAA==.Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgcJEgABLgAECgkJEgAGAAAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8UAAIbAAUJThfEEwAoAQAbAAUJThfEEwAoAQAuAAQKfzQAAhsACQlyG6QNAIwCABsACQlyG6QNAIwCAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAACLgAFFH8TAAIlAAUJvx5nFQBgAQAlAAUJvx5nFQBgAQAuAAQKfyIAAiUACAkzGOkjAHUBACUACAkzGOkjAHUBAAAA.Jocon:BAABLgAECn8mAAIPAAkJAwf5dABQAQAPAAkJAwf5dABQAQAAAA==.Joraan:BAAALgAECgcJCAAAAA==.',
Js='Js:BAAALgADCgIJAgAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kailec:BAAALgAECgEJAQAAAA==.Kamo:BAAALgAECgQJCQABLgAFFAQJEAAdALEOAA==.Kamô:BAAALgAECgQJBAABLgAFFAQJEAAdALEOAA==.Kanami:BAABLgAECn8sAAIIAAkJBB/oDACdAgAIAAkJBB/oDACdAgAAAA==.Kaori:BAABLgAECn8UAAIOAAgJCAg/sgAfAQAOAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDhmDDQAKAgACAAkJDhmDDQAKAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Katarr:BAAALgAECgUJBQAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgAECgEJAQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJbx3fDABYAgAlAAkJbx3fDABYAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8TAAIOAAUJIxLOSQAZAQAOAAUJIxLOSQAZAQAuAAQKf0oAAw4ACQl8Go0uAEcCAA4ACQlJGY0uAEcCABIABwlyGk4PAM4BAAAA.Keedron:BAACLgAFFH8aAAMJAAkJ3RYVEwAYAgAJAAgJ+xcVEwAYAgALAAEJDA87EQBdAAAuAAQKfxsAAgkACAlJJIkLACUDAAkACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8iAAIFAAgJqRPodQB4AQAFAAgJqRPodQB4AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8yAAMFAAkJDx++FgC/AgAFAAkJDx++FgC/AgAmAAMJEgmDMgBSAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kielord:BAAALgADCggJEQAAAA==.Kilfogg:BAABLgAECn8XAAIHAAcJoxfmKwC5AQAHAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAFFAIJAgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8JAAMKAAMJRwkCSwChAAAKAAMJRwkCSwChAAAMAAMJeg8uIQCdAAAuAAQKfycABAwACQlJGBINAAECAAwACQlJGBINAAECAAoABgk3EMdKAAEBAB8AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCwAAAA==.Koinpúrse:BAAALgAECgMJBAAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8bAAIQAAcJ/R75BgDwAQAQAAcJ/R75BgDwAQAuAAQKfxcAAhAACAm6IwgVACoDABAACAm6IwgVACoDAAAA.Kons:BAAALgADCgEJAQAAAA==.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAGAAAAAA==.Korvasa:BAAALgAECgQJBAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKh5oJgDKAQAiAAgJKh5oJgDKAQABLgAECggJHAAOAJIhAA==.',
Kr='Krangler:BAAALgAECgYJBgAAAA==.Krelock:BAACLgAFFH8GAAIPAAMJ2APnjQCpAAAPAAMJ2APnjQCpAAAuAAQKfxYAAg8ABwlgFFZSANABAA8ABwlgFFZSANABAAAA.Krymzendeath:BAABLgAECn8gAAMSAAcJxgylBQCyAAASAAcJxgylBQCyAAAOAAUJcgLeTwFfAAABLgAFFAQJHgAUAMYYAA==.Krísztina:BAABLgAECn8pAAQZAAgJWAuFEQBLAQAZAAgJwgiFEQBLAQAYAAgJqAmDFQD+AAAPAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAFFAEJAQABLgAFFAkJGgAJAN0WAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAGAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kä']='Kämö:BAAALgAECgEJAQABLgAFFAQJEAAdALEOAA==.',
['Kå']='Kåmo:BAACLgAFFH8QAAIdAAQJsQ5QFgAeAQAdAAQJsQ5QFgAeAQAuAAQKfyQAAh0ACQkmGOQHAHICAB0ACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAgAAAA==.',
La='Laelada:BAAALgAFFAEJAQAAAA==.Lakey:BAABLgAECn8XAAQbAAgJByaFFgAdAgAbAAgJByaFFgAdAgAaAAUJ6SJ7HADqAQAkAAMJOA73SgCuAAABLgAFFAUJHwADAEEWAA==.Lakeyy:BAACLgAFFH8fAAMDAAUJQRYzIgBHAQADAAUJQRYzIgBHAQAiAAQJRxZCIQAWAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lakeyys:BAABLgAFFH8FAAIjAAUJxxHRLgD+AAAjAAUJxxHRLgD+AAABLgAFFAUJHwADAEEWAA==.Lanayrd:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Larian:BAAALgAECgEJAQABLgAFFAQJDAAOAC0cAA==.Lawrence:BAACLgAFFH8MAAMHAAUJbxBDKQDwAAAHAAQJbxBDKQDwAAANAAQJ7QeaSADLAAAuAAQKfyMAAwcACAmaIcIKAOoCAAcACAmaIcIKAOoCAA0AAwkbDkGnAH0AAAEuAAUUBgkTAAkAghQA.Lazuril:BAAALgAECgEJAgAAAQ==.',
Le='Leanhaum:BAAALgAECgIJBAAAAA==.Lebonk:BAAALgAECgEJAQAAAA==.Lediscoboy:BAAALgADCgYJBgAAAA==.Lewless:BAAALgAECgEJAQAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lickmybubble:BAAALgAECgEJAQAAAA==.Lightbane:BAAALgADCgYJBgAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilikoii:BAAALgAECgMJAwABLgAFFAUJHwADAEEWAA==.Lilslaver:BAAALgAECgcJEQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Liradra:BAAALgAECgEJAQAAAA==.Lisex:BAACLgAFFH8pAAQFAAgJ1xYrEwBCAgAFAAcJ1xYrEwBCAgAmAAQJSQ0ZEgABAQAeAAEJAAAfGgA0AAAuAAQKfzEAAwUACQmjI/cWAPICAAUACQmZI/cWAPICACYABwkiHS0JAPQBAAAA.Lithe:BAABLgAFFH8MAAIOAAQJKQ6dFgAGAQAOAAQJKQ6dFgAGAQAAAA==.',
Lo='Locklear:BAABLgAECn8iAAIOAAkJbBbFRgDyAQAOAAkJbBbFRgDyAQAAAA==.Logic:BAACLgAFFH8iAAMQAAgJsRUkGQAsAgAQAAgJqBQkGQAsAgAhAAMJEBYZAwDnAAAuAAQKfysAAhAACQlvI0kUAOACABAACQlvI0kUAOACAAAA.Lolbrez:BAAALgAECgEJAQAAAA==.Lolshield:BAAALgAECgYJCgABLgAFFAUJGgARAAwfAA==.Lonelyphatty:BAAALgAECgcJCQAAAA==.Lorecan:BAABLgAECn8yAAISAAkJjgodHQAsAQASAAkJjgodHQAsAQAAAA==.Lotei:BAAALgADCgUJBQAAAA==.Lowkeyhunter:BAAALgADCgMJAwAAAA==.',
Lu='Luchenta:BAABLgAECn8aAAInAAgJ9xlBBQAXAgAnAAgJ9xlBBQAXAgAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDQABLgAFFAUJHwADAEEWAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAYJCgAcAOMFAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAACLgAFFH8GAAIFAAIJeRFF3gCGAAAFAAIJeRFF3gCGAAAuAAQKfy4AAgUACQkvHUApAFwCAAUACQkvHUApAFwCAAAA.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8sAAIJAAkJVR/5AQDNAgAJAAkJVR/5AQDNAgAuAAQKfycAAgkACQkZIkEIAEgDAAkACQkZIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAkJLAAJAFUfAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAIQAAkJbhW9YQC8AQAQAAkJbhW9YQC8AQAAAA==.Magirzul:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAQ==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAACLgAFFH8MAAIOAAQJLRynNgBAAQAOAAQJLRynNgBAAQAuAAQKfy0AAg4ACQn9Ho0kAHMCAA4ACQn9Ho0kAHMCAAAA.Makima:BAAALgAECgUJBQAAAA==.Malazen:BAAALgAECgYJDwAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn85AAIFAAkJ+BwcIQCEAgAFAAkJ+BwcIQCEAgAAAA==.Mamageek:BAABLgAECn8XAAINAAkJ9hHmKADsAQANAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAAGAAAAAA==.Manajunky:BAAALgAECgkJAQAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgAQAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Mastahblasta:BAAALgAECgYJBgAAAA==.Mastahunta:BAAALgAECgQJBAABLgAECggJKwANAJkaAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8kAAIOAAkJcB3eJgBoAgAOAAkJcB3eJgBoAgAAAA==.',
Mc='Mcdeath:BAABLgAECn8WAAIeAAgJyBTVGwB9AQAeAAgJyBTVGwB9AQABLgAECgkJHgACACEWAA==.Mcversatile:BAABLgAECn8eAAICAAkJIRZ1EgDKAQACAAkJIRZ1EgDKAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIbAAkJrBksEABkAgAbAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8qAAIMAAkJOiKPAADLAgAMAAkJOiKPAADLAgAuAAQKfycAAgwACQkZJk4AAN8DAAwACQkZJk4AAN8DAAAA.Meleeman:BAAALgAECgUJBQAAAA==.Mereoleona:BAAALgAECggJEgAAAA==.Metalmagus:BAABLgAECn8iAAIQAAgJCRp9TwDtAQAQAAgJCRp9TwDtAQAAAA==.Metori:BAAALgAECgQJBwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIgAAkJTSIyBQCTAgAgAAkJTSIyBQCTAgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAkJGgAJAN0WAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8mAAIRAAkJYRMlHwCtAQARAAkJYRMlHwCtAQAAAA==.Misslobster:BAAALgAFFAIJBAAAAA==.Mistweaver:BAABLgAFFH8KAAIjAAQJ5xmIJQBBAQAjAAQJ5xmIJQBBAQAAAA==.Mistygoblin:BAAALgAECgYJEgABLgAECggJKwANAJkaAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgkJDgAAAA==.Mokoko:BAACLgAFFH8UAAMKAAQJsx73CgBPAQAKAAQJsx73CgBPAQAfAAIJGRMoBABRAAAuAAQKfzEAAwoACQmhIdEFACcDAAoACQmHIdEFACcDAB8ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJFAAKALMeAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR1hDwBpAgAiAAkJKR1hDwBpAgADAAQJDxFhggDUAAACAAEJch3NYQBNAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMXAAkJbCPlCAC3AgAXAAkJbCPlCAC3AgARAAYJ7hlIKwBdAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moshiach:BAAALgAECgYJBgAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
Ms='Mscptcrunch:BAAALgAECgEJAQAAAA==.',
My='Myka:BAAALgAECgMJAwABLgAECgYJBgAGAAAAAA==.',
['Mò']='Mòrtale:BAAALgAECgQJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAUJGgARAAwfAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAGAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIFAAkJVBthUQDPAQAFAAkJVBthUQDPAQAAAA==.Necrota:BAACLgAFFH8IAAIFAAMJ1RtThwD7AAAFAAMJ1RtThwD7AAAuAAQKfxoAAwUACAmVHrZHAOsBAAUACAkWHrZHAOsBAB4AAQlcG5FBAEUAAAEuAAUUBwkbABAA/R4A.Nekronomicon:BAAALgAFFAMJAwAAAA==.Neuron:BAACLgAFFH8gAAIDAAgJPhutAQD6AQADAAgJPhutAQD6AQAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.Nexgen:BAAALgAECgUJBQAAAA==.',
Ni='Nickadeath:BAAALgAECgQJCAAAAA==.Nigdruu:BAABLgAECn8iAAIDAAkJNBomHABbAgADAAkJNBomHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8uAAIoAAkJnxBLBwDoAQAoAAkJnxBLBwDoAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nofitputspit:BAAALgAECgYJBgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAABLgAECn8YAAIPAAYJ4glRDgC4AAAPAAYJ4glRDgC4AAAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.Notacatfish:BAAALgAECgEJAwABLgAECgQJBAAGAAAAAA==.',
Nu='Nucwel:BAAALgAECgMJAwAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgAECgQJBAAAAA==.',
Oo='Oortt:BAAALgAECgYJCgAAAA==.',
Or='Oralys:BAABLgAECn8hAAIEAAgJEiKdEQCHAgAEAAgJEiKdEQCHAgAAAA==.Oreyn:BAAALgAECgcJDgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQABLgAECgYJBgAGAAAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladian:BAAALgAECgIJAgABLgAECggJKwANAJkaAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn9FAAMSAAkJyBpLCQA9AgAOAAkJ2RiyLABOAgASAAkJCBlLCQA9AgAAAA==.Palugly:BAAALgAECgkJDAABLgAFFAQJEAAVAJgcAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAACLgAFFH8GAAIlAAMJFRyQCgAcAQAlAAMJFRyQCgAcAQAuAAQKfxwAAiUACAlQHpMTAAcCACUACAlQHpMTAAcCAAAA.Patoko:BAABLgAECn8pAAIgAAkJXxnECgAhAgAgAAkJXxnECgAhAgAAAA==.Paxwet:BAAALgAECgUJBgAAAA==.Payn:BAACLgAFFH8aAAMfAAUJPyOrAQCKAQAfAAUJPyOrAQCKAQAKAAQJfB2dHwBjAQAuAAQKfzwAAx8ACQlUJi4AAIUDAB8ACQlRJi4AAIUDAAoABgnPIC4cAPQBAAAA.Paypay:BAACLgAFFH8JAAIDAAQJbSMwGQCUAQADAAQJbSMwGQCUAQAuAAQKfzsAAwMACQn9Jd8AANkDAAMACQn9Jd8AANkDACIABgkfECJEAPwAAAAA.',
Pe='Pepperknight:BAAALgAECgcJEQABLgAECgkJIgADADQaAA==.',
Ph='Phalannx:BAAALgAECgEJAQAAAA==.Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgQJBwAAAA==.Phinks:BAAALgAFFAIJAgAAAA==.Phráxas:BAAALgAECgIJAgABLgAECgcJEwAGAAAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8tAAMbAAcJ+R4/FgAgAgAbAAcJ+R4/FgAgAgAkAAUJnR9RLwBiAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgIJAwABLgAECgUJCAAGAAAAAA==.',
Po='Poepoe:BAAALgAFFAEJAQAAAA==.Polyrhythm:BAAALgAFFAEJBAAAAA==.Polyrhythms:BAAALgAFFAEJAgAAAA==.Porthub:BAAALgAECgQJBwAAAA==.Potatofist:BAAALgADCgEJAQABLgAECgcJGAADAP4gAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIaAAMJlQi6NAC5AAAaAAMJlQi6NAC5AAAuAAQKfx4AAhoABgmxH8MTABACABoABgmxH8MTABACAAAA.Prosthesis:BAAALgAECgQJBAAAAA==.Prrowl:BAABLgAECn8WAAICAAUJKwhwCgB6AAACAAUJKwhwCgB6AAAAAA==.',
Pu='Pua:BAAALgAECgUJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rareley:BAABLgAECn8WAAIOAAkJUhCHVADMAQAOAAkJUhCHVADMAQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAFFAQJDAAOAC0cAA==.Revival:BAAALgAECgYJCAAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.Rixxa:BAABLgAECn8gAAINAAYJzwoxhQDTAAANAAYJzwoxhQDTAAAAAA==.Rizzpinchy:BAAALgADCgUJBQAAAA==.',
Ro='Roksolid:BAABLgAECn8lAAIHAAkJWxcIGwAJAgAHAAkJWxcIGwAJAgAAAA==.Rollos:BAABLgAECn8gAAIPAAkJUBVvNgD/AQAPAAkJUBVvNgD/AQAAAA==.Ronara:BAABLgAECn8jAAIjAAgJCxK2MAC3AQAjAAgJCxK2MAC3AQAAAA==.Rookesbane:BAAALgAECgIJAgAAAA==.Rotpaw:BAAALgAECgMJAwAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8iAAIKAAgJdyHJBQCpAgAKAAgJdyHJBQCpAgAuAAQKfyEAAgoACQm3JfAAAMwDAAoACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAABLgAECn8WAAQPAAYJUhXLlAASAQAPAAUJUhXLlAASAQAYAAEJ+A1zcAA2AAAZAAEJAABJSgAAAAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgkJRQASAMgaAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAIAH4aAA==.Saeli:BAAALgAECgEJAgAAAA==.Saelybricek:BAAALgAECggJCQAAAA==.Saintnick:BAAALgAECgYJDwAAAA==.Salvester:BAAALgAECgIJAgABLgAECgcJLQAbAPkeAA==.Samtarkras:BAABLgAECn8tAAIMAAkJqhqfBwB8AgAMAAkJqhqfBwB8AgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgAECgQJBAAAAA==.Saradia:BAAALgAECgEJAQAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAGAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.Scuzalbutt:BAABLgAFFH8KAAIcAAYJ4wVcNwA+AQAcAAYJ4wVcNwA+AQAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8SAAIZAAQJCReSBABBAQAZAAQJCReSBABBAQAuAAQKf64ABBkACQmPJUoAAGcDABkACQmPJUoAAGcDABgABgkhINgHANMBAA8ABglbGYBcAIkBAAAA.Selket:BAAALgAECggJDQAAAA==.',
Sh='Shadowfawn:BAABLgAECn8zAAMkAAkJsxjrEQBGAgAkAAkJsxjrEQBGAgAbAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8JAAIkAAMJThFbJwDBAAAkAAMJThFbJwDBAAAuAAQKf2oAAiQACQnFJOUCADYDACQACQnFJOUCADYDAAEuAAUUCAkdAAcA0BcA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shalidor:BAAALgAECgQJBAABLgAECgkJOQAFAPgcAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamanussy:BAAALgAECgEJAQAAAA==.Shamxie:BAAALgAECgQJBQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Shareholder:BAABLgAFFH8MAAIPAAcJiBiDLACTAQAPAAcJiBiDLACTAQABLgAFFAcJGAAQAJAfAA==.Sharklord:BAABLgAECn8cAAIlAAgJ0xfwJgDBAQAlAAgJ0xfwJgDBAQAAAA==.Shastashaman:BAAALgAFFAEJAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIcAAQJSQvIXQDpAAAcAAQJSQvIXQDpAAAuAAQKfyoAAhwACAnIIAgYAJcCABwACAnIIAgYAJcCAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJIgAKAHchAA==.Shodin:BAAALgADCgEJAQAAAA==.Shotsyll:BAAALgAECgUJBgABLgAECggJGAADAEkZAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.Skynomad:BAAALgAECgQJBgABLgAECgYJCgAGAAAAAA==.',
Sl='Slyde:BAABLgAECn84AAIFAAkJ5SQUBQBUAwAFAAkJ5SQUBQBUAwAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIFAAYJzBg8FwBIAQAFAAYJzBg8FwBIAQAuAAQKfyUAAgUACAnPIq8VAPoCAAUACAnPIq8VAPoCAAEuAAUUBwkJAAoAlBUA.Smick:BAACLgAFFH8FAAIEAAIJDQvOFQBjAAAEAAIJDQvOFQBjAAAuAAQKfx4AAgQACQmhElcsALABAAQACQmhElcsALABAAAA.Smokermcpot:BAAALgAECgEJAQAAAA==.Smoulder:BAAALgAECgUJBQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgcJDgAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.Snowingmagic:BAAALgAECgEJAQABLgAFFAQJBAAGAAAAAA==.Snuggyboo:BAAALgAECgEJAgAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCOICwAqAgACAAcJNSGICwAqAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn9TAAIIAAkJjiFzCQDLAgAIAAkJjiFzCQDLAgAAAA==.Soulfox:BAAALgAECgEJAwABLgAECggJKwANAJkaAA==.',
Sp='Spacing:BAAALgAFFAQJBAAAAA==.Speknawz:BAAALgAFFAEJAQABLgAFFAUJFAAlAA8ZAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.Sprocketrot:BAABLgAECn8VAAIFAAcJTRdAXgCtAQAFAAcJTRdAXgCtAQAAAA==.',
Sq='Squidmonk:BAAALgAFFAIJAgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8oAAIVAAgJ7BSwDACKAQAVAAgJ7BSwDACKAQABLgAFFAQJEgAZAAkXAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAshAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgMJAwAAAA==.Stealthops:BAABLgAECn8UAAIlAAgJgROhHgChAQAlAAgJgROhHgChAQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8aAAIXAAgJvhumAQB4AgAXAAgJvhumAQB4AgAuAAQKfxUAAhcACAlEH5kMALECABcACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormscout:BAAALgAFFAEJAQAAAA==.Stormshout:BAAALgAECgEJAQAAAA==.Stormsigil:BAAALgAECgEJAQAAAA==.Stormstyle:BAAALgAECgQJCgAAAA==.Stormsurge:BAAALgAECgIJBAAAAA==.Straydog:BAABLgAECn8uAAMNAAkJ4ySPAQC5AwANAAkJ4ySPAQC5AwAHAAEJHhRCnwA7AAAAAA==.Strongsad:BAAALgAECgYJDwAAAA==.Stumptavion:BAABLgAECn8vAAIFAAkJlhYXfwBlAQAFAAkJlhYXfwBlAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAGAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAGAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Supatrollsky:BAAALgAECgUJBQABLgAECgYJCgAGAAAAAA==.Superpowers:BAABLgAECn8XAAIRAAgJWR+zDQBdAgARAAgJWR+zDQBdAgAAAA==.Supersaiyan:BAAALgAECgYJEgAAAA==.Surtur:BAABLgAECn9AAAITAAkJ4yFZBADWAgATAAkJ4yFZBADWAgAAAA==.Sus:BAABLgAFFH8IAAIcAAQJAwokcQC9AAAcAAQJAwokcQC9AAAAAA==.Suzel:BAABLgAECn8dAAIFAAUJSwnEFQCtAAAFAAUJSwnEFQCtAAAAAA==.',
Sw='Sweatmachine:BAAALgAECgEJAQAAAA==.Swoof:BAAALgAECggJEQABLgAFFAYJCgAcAOMFAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn88AAILAAkJhxR8EwD5AQALAAkJhxR8EwD5AQAAAA==.Sylveon:BAAALgAECgEJAQAAAA==.Synath:BAAALgAFFAIJAgAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDwAaAN8OAA==.Synwise:BAABLgAECn83AAIDAAkJaiFIBgBTAwADAAkJaiFIBgBTAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8TAAIcAAUJGhaVPAA0AQAcAAUJGhaVPAA0AQAuAAQKfzUAAxwACQlmHRAhAGICABwACQlmHRAhAGICABYAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIXAAgJCxnTGAAcAgAXAAgJCxnTGAAcAgAAAA==.Taowg:BAAALgAECgIJBAAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8lAAQbAAkJlhqZEQBUAgAbAAkJlhqZEQBUAgAaAAQJlA2XVgCmAAAkAAIJbhIWagB2AAAAAA==.',
Te='Teknicaliti:BAAALgAECgEJAgAAAA==.',
Th='Thanah:BAAALgAECgUJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8TAAIFAAUJXBOpZwApAQAFAAUJXBOpZwApAQAuAAQKfyoAAwUACQkdGJ1MANwBAAUACQkdGJ1MANwBACYAAQneCWQ+ACoAAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAGAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJBAAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thorgar:BAAALgAECggJCAAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8QAAIVAAQJmBwIBAA/AQAVAAQJmBwIBAA/AQAuAAQKfzkAAhUACQnWHjYEAIQCABUACQnWHjYEAIQCAAAA.Tinytea:BAACLgAFFH8QAAIRAAQJhSOwEgCOAQARAAQJhSOwEgCOAQAuAAQKf0IAAhEACQkyJdkBAEoDABEACQkyJdkBAEoDAAAA.Tinytilted:BAAALgAECgQJBAAAAA==.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJEwAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8OAAMEAAUJuxvEFACEAQAEAAUJuxvEFACEAQAOAAEJUQ1QugBDAAAuAAQKfygAAwQACQkYHeUVAGECAAQACAkqH+UVAGECAA4ABQnfEC+9AAwBAAAA.Torb:BAAALgAECgYJBgAAAA==.Totosapling:BAAALgADCgcJCAAAAA==.Totoshift:BAAALgAECgEJAQAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.Tough:BAAALgADCgEJAQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAwAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMIAAYJ0SGHLQD9AQAIAAUJvSOHLQD9AQATAAEJIxoHPgA8AAABLgAFFAQJCwAFAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsuicide:BAEALgAECgIJAgABLgAECgcJEAAGAAAAAA==.Tsunt:BAEALgAECgcJEAAAAA==.Tsusha:BAEALgADCgkJEAABLgAECgcJEAAGAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJCQAGAAAAAA==.Tuckrh:BAAALgAECgYJBwAAAA==.Tuillina:BAAALgAECgUJBQAAAA==.Turkeyleg:BAAALgAECgUJCQAAAA==.',
Tw='Twiisty:BAACLgAFFH8FAAIUAAMJfgfwIwB7AAAUAAMJfgfwIwB7AAAuAAQKfx4AAhQACQkPD/UaAGEBABQACQkPD/UaAGEBAAEuAAUUBAkRAAcAQAoA.Twippy:BAABLgAFFH8RAAIHAAQJQArCFACyAAAHAAQJQArCFACyAAAAAA==.Twistbae:BAAALgAFFAMJAwABLgAFFAQJEQAHAEAKAA==.Twobeers:BAAALgAECgYJBgAAAA==.',
Ty='Tyanis:BAABLgAECn8cAAIOAAYJ1woB4QDdAAAOAAYJ1woB4QDdAAABLgAECgcJDgAGAAAAAA==.Tyriam:BAABLgAECn8wAAMOAAkJ2hrVLQBJAgAOAAgJ2hrVLQBJAgAEAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAIQAAgJixODbgCdAQAQAAgJixODbgCdAQAAAA==.',
Un='Undeadboss:BAAALgAECgEJAQABLgAECggJKwANAJkaAA==.Underwear:BAAALgAECgMJAwABLgAECgQJBwAGAAAAAA==.Ungrul:BAAALgAECggJDAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAGAAAAAA==.Vandy:BAABLgAECn8nAAMLAAkJLAraNwAmAQALAAYJtwvaNwAmAQAJAAkJXAmLkAD/AAAAAA==.Varodonaris:BAAALgAECgYJCgAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Vendicia:BAAALgAECggJCAAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8cAAMfAAYJyxJJBQASAQAfAAUJtg9JBQASAQAKAAYJsBJAPADWAAAuAAQKfyAAAx8ACQktHUgEAMkCAB8ACAlhIEgEAMkCAAoAAgmBEIGHAE0AAAAA.Verso:BAABLgAECn8rAAInAAkJWRtxAwBnAgAnAAkJWRtxAwBnAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdelta:BAAALgADCgUJBQABLgAECgkJFQAgAE0iAA==.Vikdruid:BAAALgAECgUJBAABLgAECgkJFQAgAE0iAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAgAE0iAA==.Vinius:BAAALgADCgEJAQAAAA==.Vinushka:BAAALgAECggJDwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgkJMwAKABYcAA==.Vitalithry:BAABLgAECn8zAAMKAAkJFhx4EABkAgAKAAkJDhx4EABkAgAfAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.Vizzeek:BAAALgAECgEJAQABLgAFFAMJBgAFANoRAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgUJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vyndication:BAAALgAFFAMJAwAAAA==.Vynirian:BAAALgAECgMJBAAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAFFAQJDAAOAC0cAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgABLgAECgEJAQAGAAAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAACLgAFFH8HAAIFAAMJvQ3KpQDOAAAFAAMJvQ3KpQDOAAAuAAQKfyoAAgUACQlzFeFkAJ0BAAUACQlzFeFkAJ0BAAAA.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn82AAQHAAkJ0R86CQDJAgAHAAkJ0R86CQDJAgANAAgJ4BnuIwA3AgAgAAIJ7xHPPQA3AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8ZAAMkAAgJhRXcCQDEAQAkAAgJhRXcCQDEAQAbAAEJ0gvOGQArAAAuAAQKfz4AAyQACAlFIsIJALICACQACAlFIsIJALICABsAAQklJexdAGIAAAAA.Windoelicker:BAAALgAECgYJEgAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAABLgAECn8WAAIjAAgJqh42DgC7AgAjAAgJqh42DgC7AgAAAA==.',
Wu='Wuggles:BAACLgAFFH8dAAIDAAYJnQ/OBwBuAQADAAYJnQ/OBwBuAQAuAAQKfygAAwMACQkzHMsXAHgCAAMACQkzHMsXAHgCACIABAkcDdFVAM0AAAAA.Wulf:BAAALgADCggJDgAAAA==.Wulfvane:BAAALgADCgMJAwAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.Xandoriel:BAAALgADCgkJDgAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMcAAkJ7xq3OQD3AQAcAAgJFxu3OQD3AQAWAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIFAAQJRBTscgAaAQAFAAQJRBTscgAaAQAuAAQKfx4AAwUACAn0HiU8ABACAAUACAn0HiU8ABACACYAAQlgENk8AC0AAAAA.',
Ya='Yad:BAAALgAECgEJAQAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHgbAA==.',
Ye='Yetil:BAABLgAECn8dAAIEAAkJdgr/MQCOAQAEAAkJdgr/MQCOAQAAAA==.Yey:BAABLgAECn8hAAQEAAkJjxm5GgAvAgAEAAkJjxm5GgAvAgASAAMJJgGTTAA6AAAOAAEJDQTUwgEiAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAABLgAECn8iAAIQAAkJ8g/PVADeAQAQAAkJ8g/PVADeAQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zaerix:BAAALgAECgQJBAAAAA==.Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAABLgAFFH8GAAIPAAMJGQxVfwDGAAAPAAMJGQxVfwDGAAAAAA==.Zaydream:BAABLgAECn8XAAQCAAgJChtaDAAbAgACAAgJChtaDAAbAgAiAAUJvw2aRAD6AAABAAIJpAcYXQAlAAABLgAFFAMJBgAPABkMAA==.Zaydämon:BAABLgAECn8WAAIJAAgJ4R1IHwCWAgAJAAgJ4R1IHwCWAgABLgAFFAMJBgAPABkMAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zello:BAAALgAECggJEwAAAA==.Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgkJMAABAL8YAA==.Ziggybeast:BAACLgAFFH8KAAIDAAIJBxm/SgCRAAADAAIJBxm/SgCRAAAuAAQKfy0ABCIACQlWIQYPAK8CACIACQlWIQYPAK8CAAMAAQkTIgGpAGIAAAIAAwl4DVdhAE4AAAAA.Ziggybrute:BAAALgADCgEJAQABLgAFFAIJCgADAAcZAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAACLgAFFH8IAAIFAAIJZxipyACbAAAFAAIJZxipyACbAAAuAAQKf0MAAgUACQlMHTQsAE8CAAUACQlMHTQsAE8CAAAA.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgUJBgAAAA==.',
Zy='Zydia:BAAALgAECgUJBQAAAA==.',
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
