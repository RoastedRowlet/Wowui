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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Druid-Balance','Druid-Restoration','Monk-Brewmaster','Priest-Discipline','Unknown-Unknown','Shaman-Elemental','Priest-Shadow','Evoker-Preservation','Rogue-Subtlety','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','Shaman-Enhancement','Evoker-Devastation','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Paladin-Retribution','Druid-Feral','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Devourer','Rogue-Outlaw','Paladin-Protection','Warrior-Protection','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adobo:BAAANQADCgYIDQAAAA==.Adofian:BAAANQADCgcIEwABNQAECggIJAABAJQSAA==.',
Af='Afflicted:BAAANQADCgYIBgABNQAFFAYIDwACABohAA==.Aft:BAACNQAFFH8RAAIDAAUK0iFECADXAQADAAUK0iFECADXAQA1AAQKfykAAgMACQocJL4HAH8DAAMACQocJL4HAH8DAAAA.',
Ai='Aislin:BAAANQAECgQIBgAAAQ==.',
Ak='Akumu:BAABNQAECn8jAAMEAAgKoR5BOwCfAgAEAAgKoR5BOwCfAgAFAAIKehiLVACAAAAAAA==.',
Al='Alarkin:BAACNQAFFH8WAAMCAAYKhxXKBQDxAQACAAYKOhTKBQDxAQAGAAUKzRSaDABwAQA1AAQKfzgAAwYACQq9JYcIAEcDAAYACQopIYcIAEcDAAIACAq6JfIfABYDAAAA.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAABNQAECn8lAAIHAAkK8xZUBwB6AgAHAAkK8xZUBwB6AgAAAA==.Aldoan:BAAANQAECgIIBAAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQAECgEIAQAAAA==.Alistiri:BAAANQAECgUICwAAAA==.Alix:BAAANQAECgMIBAAAAA==.Allforge:BAAANQAECgYIEAAAAA==.Almina:BAAANQAECgcIDQAAAA==.Alpal:BAACNQAFFH8WAAIIAAYKiRRSBwDuAQAIAAYKiRRSBwDuAQA1AAQKfzkAAggACQq0IJ8OAFQDAAgACQq0IJ8OAFQDAAAA.',
Am='Ambs:BAABNQAECn8ZAAIBAAcKYBa0uwALAgABAAcKYBa0uwALAgAAAA==.',
An='Analyse:BAAANQABCgIIAgAAAA==.Andalya:BAABNQAECn8aAAMJAAcK/gFFhAC7AAAJAAcK/gFFhAC7AAAKAAYKQARtVACyAAAAAA==.Andaria:BAAANQAECgQIBAAAAA==.Andarial:BAAANQAECgMIAwAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIFAAAAA==.',
Ap='Aprix:BAAANQAECgYJDAAAAA==.',
Ar='Araara:BAAANQADCgUIBQAAAA==.Aralyn:BAAANQADCgcIDQAAAA==.Arejay:BAAANQAECgQIBgAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAABNQAECn8dAAIHAAgKaxZzCABVAgAHAAgKaxZzCABVAgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgUJCQAAAA==.Arthurleywin:BAAANQAECgUIDwAAAA==.Arvis:BAAANQAECgMIBAAAAA==.',
As='Asamia:BAACNQAFFH8YAAILAAcKnhucAABwAgALAAcKnhucAABwAgA1AAQKfyIAAgsACQprI5IEACsDAAsACQprI5IEACsDAAAA.Ashaki:BAABNQAECn8cAAIMAAgK/RYIBgA1AgAMAAgK/RYIBgA1AgAAAA==.Asmodéus:BAAANQADCgUIBQABNQAECgYIDgANAAAAAA==.Astå:BAAANQADCggICAABNQAECgkJJQAOADgdAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auralius:BAAANQADCgYIEAAAAA==.Auroramoon:BAAANQAECgUIEQAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.Avis:BAAANQAECgQIBAAAAA==.',
Aw='Awake:BAABNQAECn8dAAMPAAkK2RF6IwATAgAPAAkK2RF6IwATAgAMAAEKkAImMAAjAAAAAA==.',
Ax='Axionar:BAAANQAECggIEQAAAA==.',
Az='Azshauria:BAAANQABCggIEwAAAA==.Azurend:BAABNQAECn8cAAIQAAcK+hhpGwAQAgAQAAcK+hhpGwAQAgAAAA==.Azázél:BAAANQAECgYIDgAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCggIGQABNQAECgkJLQARAKojAA==.Bahula:BAABNQAECn8gAAISAAgKxA50bwC5AQASAAgKxA50bwC5AQAAAA==.Bainehuln:BAAANQAECgcIEwAAAA==.Bastianos:BAAANQAECgcIEgAAAA==.Batsom:BAAANQABCgEIAQAAAA==.Battlecheeks:BAAANQADCgQIBAABNQAECgYIBwANAAAAAA==.',
Be='Beastafied:BAAANQABCgEIAQAAAA==.Bellapearl:BAAANQAECgQIDgAAAA==.Bellmont:BAAANQAECgYIBwAAAA==.Belron:BAAANQAECgMIBgABNQAECgkJMAATAOEOAA==.Bernes:BAABNQAECn8iAAMDAAkKmx70MgBAAgADAAcK1B70MgBAAgAUAAkK9RbMOwAvAgAAAA==.',
Bi='Biffle:BAAANQAECggIBwABNQAECgkJLQARAKojAA==.Bigteef:BAAANQADCgUICQAAAA==.Bioz:BAAANQAECgUIBQAAAA==.Birdhouse:BAABNQAECn8aAAIPAAcK4BwqGQCDAgAPAAcK4BwqGQCDAgAAAA==.',
Bl='Blackthornn:BAACNQAFFH8WAAIVAAYKOhu2AwASAgAVAAYKOhu2AwASAgA1AAQKfzkAAhUACQroIqoFAHUDABUACQroIqoFAHUDAAAA.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Blindape:BAAANQAECgEIAQAAAA==.Bloodcircus:BAAANQAECgcIBwAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECgkJNAAWAGIkAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Bloodworm:BAAANQAECgYICgABNQAFFAYIDwACABohAA==.Blottros:BAAANQAECgUIEQAAAA==.Blottzilla:BAACNQAFFH8WAAIQAAYKGBAZCAC6AQAQAAYKGBAZCAC6AQA1AAQKfzsAAxAACQorHl4IAB4DABAACQorHl4IAB4DABcAAQq0FPo3AEoAAAAA.Bluestreak:BAAANQADCggIEQAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAABNQAECn8vAAIIAAkKEx2sGgAKAwAIAAkKEx2sGgAKAwAAAA==.Booda:BAAANQADCggIDQAAAA==.Boratt:BAAANQAECgQIBAAAAA==.Bowbuttkick:BAACNQAFFH8PAAMCAAYKGiE9AwAuAgACAAYKGiE9AwAuAgAGAAQKrRGnEAAsAQA1AAQKfxwAAwIACQrRJIchAA8DAAIACQrRJIchAA8DAAYAAgoHFAJyAGoAAAAA.Bowjangles:BAEANQAECgQIBwABNQAECggIFgANAAAAAA==.Boxiebrown:BAABNQAECn8lAAICAAkK+BVFYgBPAgACAAkK+BVFYgBPAgAAAA==.',
Br='Bralae:BAAANQAECgYIEgAAAA==.Breaya:BAAANQADCgYIDAAAAA==.Brewskiez:BAAANQADCggIDwAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAACNQAFFH8SAAMUAAYKeh+VBQDJAQAUAAUKEx6VBQDJAQAYAAQKyyIXCQBTAQA1AAQKfyUAAxQACQosJYUgAMYCABQACQrVI4UgAMYCABgACAodIMcbAKkCAAAA.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAABNQAECn8nAAMUAAgKZx/fIADEAgAUAAcKvCLfIADEAgAYAAEKvQ4LpwA4AAAAAA==.Brâgak:BAAANQADCgcIDQAAAA==.',
Bu='Bubbawoodkin:BAAANQAECgQIBgAAAA==.Buffpres:BAAANQAECgQIBAABNQAECgUIDAANAAAAAA==.Butchkween:BAAANQADCggIEAABNQAECggIIQAZAEcRAA==.Buzzlez:BAACNQAFFH8UAAIaAAYKeRD8CwDEAQAaAAYKeRD8CwDEAQA1AAQKfzkAAhoACQqjJJsDALQDABoACQqjJJsDALQDAAAA.',
Ca='Camspally:BAAANQAECgMJAwAAAA==.Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQIBAANAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBwAAAA==.Chahae:BAACNQAFFH8NAAMUAAUKFyXtAgARAgAUAAUKFyXtAgARAgAYAAEKQQdbIAA5AAA1AAQKfzcAAxQACQrKJnIFAKADABQACQrKJnIFAKADABgAAQrWJTCXAF8AAAAA.Channintotem:BAEANQAECgEIAQABNQAECgcIJQAbAOQgAA==.Cheerwine:BAABNQAECn8cAAMcAAgK2wrsFgCGAQAcAAgK2wrsFgCGAQAKAAcKZwpTOABWAQAAAA==.Cheezits:BAAANQAECgcICwAAAA==.Chinnook:BAAANQADCgYIBgAAAA==.Chronicle:BAAANQAECgcICAAAAA==.',
Cl='Clapdo:BAECNQAFFH8OAAMdAAQKKyERFwBjAQAdAAQKKyERFwBjAQAeAAEKAABFBQBPAAA1AAQKfyQAAx0ACQrGJOwgADMDAB0ACQrGJOwgADMDAB4AAQoAAIovAD8AAAAA.Clinician:BAABNQAECn8YAAMaAAkK3xX+NgCJAgAaAAkK3xX+NgCJAgAPAAYKvQ6OPQA7AQAAAA==.',
Co='Commandor:BAAANQADCgEIAQAAAA==.Congolense:BAAANQAECgYICwAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cougrogue:BAAANQAECgQIDQAAAA==.Cowacusrex:BAAANQAECgIIAQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAABNQAECn8cAAQfAAcKyRjnJQDwAQAfAAcKyRjnJQDwAQAgAAMKeQ0NOwCUAAALAAEK+g/bMQAtAAABNQAECgkJKwAXAMkYAA==.Creamer:BAABNQAECn8aAAMSAAkKMxBnZADcAQASAAkKMxBnZADcAQAOAAEK1QgnMwEyAAAAAA==.Crunchin:BAABNQAECn8uAAMbAAkKGBfjmADsAQAbAAgK1BXjmADsAQAIAAkK8AXmewCiAQAAAA==.',
Cu='Cutedwarfxd:BAACNQAFFH8SAAIDAAYK3CRnAwBWAgADAAYK3CRnAwBWAgA1AAQKfycAAgMACQpMJh0FAJ8DAAMACQpMJh0FAJ8DAAAA.',
Da='Dakkadakka:BAAANQAECgUIBwAAAA==.Damane:BAAANQADCgUIBQABNQAECggIEgANAAAAAA==.Danìel:BAACNQAFFH8WAAITAAYKERbKBgDRAQATAAYKERbKBgDRAQA1AAQKfzgAAxMACQr6IpcIAHEDABMACQr6IpcIAHEDACEACApvFcktAM8BAAAA.Darkarts:BAAANQADCgIIAgAAAA==.Darkmoore:BAAANQADCgUIBQAAAA==.Dartwo:BAAANQAECgUIEAAAAA==.',
De='Deadalicious:BAAANQAECgMIBgABNQAECgkJMAATAOEOAA==.Deathspoons:BAACNQAFFH8fAAIDAAcKTxqFAgB3AgADAAcKTxqFAgB3AgA1AAQKfy4AAwMACQrcIogNAEMDAAMACQrcIogNAEMDABQAAQpKIZvIAFcAAAAA.Delecto:BAABNQAECn8VAAIiAAYK6BshCQD9AQAiAAYK6BshCQD9AQAAAA==.Delmônico:BAAANQADCgYIDQAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAACNQAFFH8VAAMRAAYKsRxYBADlAQARAAUKlxlYBADlAQAVAAEK/SWDGQBsAAA1AAQKfzUAAxEACQpbJoALALsCABEABwpdI4ALALsCABUABAr7JbpBAL4BAAAA.Derkamental:BAAANQAECgIIAgAAAA==.Devora:BAEANQADCggICAABNQAECgcIJQAbAOQgAA==.Dextersmash:BAAANQAECgQIBAAAAA==.',
Di='Digallo:BAAANQAECgIIAgAAAA==.Dimsumbun:BAABNQAECn8bAAIEAAcKqwy8qgB4AQAEAAcKqwy8qgB4AQAAAA==.Dingledorf:BAAANQAECgYIEgAAAA==.Dinklebahmp:BAABNQAFFH8GAAIjAAYKhw8+BACQAQAjAAYKhw8+BACQAQABNQAFFAYIEAAkADceAA==.Dinoxeye:BAABNQAECn8ZAAIUAAcKeASuiQD4AAAUAAcKeASuiQD4AAAAAA==.Discosdead:BAAANQADCgUIBQABNQAECgEIAgANAAAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Draacarys:BAAANQADCgQIBAAAAA==.Dragonpandas:BAAANQADCggJCAABNQAECgkJMgAUAPQjAA==.Dramonk:BAACNQAFFH8KAAIfAAUK1g1cCQA3AQAfAAUK1g1cCQA3AQA1AAQKfyYAAh8ACQqjIh8PAO4CAB8ACQqjIh8PAO4CAAAA.Drizzett:BAAANQAECgUIDAAAAA==.Dro:BAAANQABCgIIAgAAAA==.Drogbar:BAAANQABCgIIAgAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.Druiske:BAAANQAECgUICAAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggICAAAAA==.',
Ei='Eir:BAABNQAECn8oAAIIAAkKRQ4HWgAIAgAIAAkKRQ4HWgAIAgAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.Eltariel:BAAANQADCggICwABNQAECgQIBAANAAAAAA==.',
Em='Emeraldjin:BAABNQAECn8oAAIgAAgKfCUOBQBRAwAgAAgKfCUOBQBRAwAAAA==.',
En='Ensera:BAAANQAECgUIEQAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgcIEwAAAA==.Ernet:BAABNQAECn8kAAIBAAgKlBKRuAARAgABAAgKlBKRuAARAgAAAA==.',
Eu='Eugenekrabs:BAAANQADCgYIBgAAAA==.',
Ex='Extraho:BAABNQAECn8qAAIaAAgKfCMxFwAaAwAaAAgKfCMxFwAaAwAAAA==.',
Fa='Fabled:BAACNQAFFH8SAAQFAAYKJh2eBwC2AAAEAAQK4hryFABUAQAFAAIK9SCeBwC2AAAlAAEKAADHCABdAAA1AAQKfyYAAwUACQpSI9IEANYCAAUACAoMINIEANYCAAQABQohIDuUAK8BAAAA.Faeyice:BAAANQAECgcIEgAAAA==.Fat:BAAANQADCgMIAwAAAA==.',
Fe='Fearmachine:BAAANQADCggIFAABNQAECggIEQANAAAAAA==.Feyden:BAAANQAECgQICAAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAFFAYIEgADANwkAA==.',
Fi='Fielton:BAAANQAECgMIBAABNQAECgkJHQAbAAsjAA==.Fiiryazell:BAAANQAECgEIAQAAAA==.Fijasdkanda:BAAANQABCgYIBgAAAA==.Fijaswarerth:BAACNQAFFH8HAAIkAAUKbiBwAQDIAQAkAAUKbiBwAQDIAQA1AAQKfx0AAyQACQqtJdsAANQDACQACQqtJdsAANQDAB0AAgrYEsQpAXoAAAAA.Fijaswitcher:BAAANQAECgcIEgAAAA==.Fimbulvargr:BAABNQAECn8eAAIDAAcKew4lXQB7AQADAAcKew4lXQB7AQAAAA==.Finiith:BAAANQAECgUJBgABNQAFFAYIFgACAIcVAA==.Finîth:BAAANQAECgUICgABNQAFFAYIFgACAIcVAA==.Firebrands:BAAANQAECgIIAgAAAA==.Firedragön:BAAANQAECgIIAgAAAA==.Firelordz:BAAANQADCgQIBAAAAA==.',
Fl='Flogdanoggin:BAAANQADCgcIBwAAAA==.Flogurnoggin:BAAANQADCggIBQAAAA==.Fluffly:BAAANQADCggICAAAAA==.Fluffyokami:BAABNQAECn8eAAIcAAgKERpkDABbAgAcAAgKERpkDABbAgAAAA==.Flyingrodent:BAABNQAECn8nAAMXAAgKiCBbEwAWAgAXAAYK7R1bEwAWAgAQAAcKixBoIwCoAQAAAA==.',
Fo='Foneer:BAABNQAECn8gAAIfAAgKrA24LwCVAQAfAAgKrA24LwCVAQAAAA==.Forestsky:BAABNQAECn8ZAAITAAcKchjoNgD0AQATAAcKchjoNgD0AQAAAA==.',
Fr='Freezepop:BAABNQAECn8rAAIBAAkKKiHwJgBFAwABAAkKKiHwJgBFAwAAAA==.Frenchieboi:BAAANQAECgUIDQABNQAECgcIEQANAAAAAA==.Frenchielock:BAAANQAECgcIEQAAAA==.Frenchthyr:BAAANQAECgUIDQABNQAECgcIEQANAAAAAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Gaden:BAAANQAECgQIBgAAAA==.Galdiian:BAAANQAECgUICgAAAA==.Gatebtch:BAAANQAFFAEIAQAAAA==.Gawdspet:BAACNQAFFH8HAAMFAAMK0w2iEwBtAAAEAAIKkBEmMACaAAAFAAIKWwOiEwBtAAA1AAQKfzAAAwQACQopHrA+AJMCAAQACAqlG7A+AJMCAAUABAptGUYrACIBAAAA.',
Gh='Ghosi:BAABNQAECn8fAAMjAAkKLRcPFwBBAgAjAAkKLRcPFwBBAgAbAAEKegkkpAEyAAAAAA==.',
Gl='Glaivier:BAAANQAECgUICAAAAA==.Glitchhunt:BAAANQAECgcIBwAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAACNQAFFH8RAAMUAAYKvh+WBgCyAQAUAAUKvh+WBgCyAQADAAEKAABoOAAgAAA1AAQKfyYAAhQACQoCJDkMAFcDABQACQoCJDkMAFcDAAAA.Gorehound:BAAANQAECgIIAgAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCggIJwAAAA==.Gotooguy:BAAANQADCgUIBQAAAA==.',
Gr='Grampman:BAAANQAECgYIBgAAAA==.Gremory:BAABNQAECn8cAAMJAAcKRBpQPQAJAgAJAAcKshlQPQAJAgAmAAIKrh69RACaAAAAAA==.Grimholt:BAAANQADCgQICAAAAA==.',
Gu='Guldank:BAAANQAECgUIDwAAAA==.Guretta:BAABNQAECn8eAAIkAAcKnRQcFgDDAQAkAAcKnRQcFgDDAQAAAA==.',
Gw='Gwynhwyvar:BAAANQAECgUIDQAAAA==.',
Ha='Haeneros:BAABNQAECn8XAAInAAcK9xMbEQCaAQAnAAcK9xMbEQCaAQAAAA==.Handmemytank:BAAANQAECgIJAwABNQAFFAMIBwACAFEUAA==.Harumi:BAAANQAECgUIDwAAAA==.',
He='Healeta:BAAANQAECgMIBAAAAA==.Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQAECgIIAgAAAA==.Heavypudding:BAAANQAECgUIDQAAAA==.Hedgehog:BAABNQAECn8wAAMgAAkKjQwAHQCzAQAgAAkKjQwAHQCzAQAfAAUKvwfpSQDPAAAAAA==.Heightning:BAAANQAECgQIBgAAAA==.Heisenberf:BAACNQAFFH8UAAIBAAYKfg93EwDWAQABAAYKfg93EwDWAQA1AAQKfzkAAwEACQrFIYcwACsDAAEACQqeIYcwACsDAAcAAQrsHCM6AFMAAAAA.Hextrathicc:BAABNQAECn81AAIEAAkKVRnBNAC0AgAEAAkKVRnBNAC0AgAAAA==.',
Ho='Holybuttkick:BAABNQAECn8fAAQIAAgK/hKGXAAAAgAIAAgK/hKGXAAAAgAjAAYKvyC7HQD5AQAbAAEK4xbWiwFCAAABNQAFFAYIDwACABohAA==.Hoozurdaddy:BAABNQAECn8fAAIOAAkKghSiTABAAgAOAAkKghSiTABAAgAAAA==.',
Ia='Iamdownhere:BAAANQABCgYICgAAAA==.',
Ic='Iceicelady:BAAANQADCgMIAwAAAA==.',
Ig='Igamm:BAAANQADCgYIDAAAAA==.Ignatius:BAAANQAECgMIBQAAAA==.Igniting:BAABNQAECn8pAAIBAAkKnxjTVwDQAgABAAkKnxjTVwDQAgABNQAECgUICAANAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgcIDgAAAA==.Ikki:BAAANQAECggJCgAAAA==.',
Il='Illuzions:BAAANQAECgMIAwAAAA==.',
Im='Impdh:BAAANQAECgIIAgABNQAFFAYIEgAIALYjAA==.Impenetrable:BAAANQAECgMIAwAAAA==.Impression:BAACNQAFFH8SAAIIAAYKtiNvAgCCAgAIAAYKtiNvAgCCAgA1AAQKfyAAAggACQqTJvUAAOUDAAgACQqTJvUAAOUDAAAA.Imprison:BAAANQAECgIIAwABNQAFFAYIEgAIALYjAA==.',
In='Incarnated:BAAANQAECggIEgAAAA==.Incursion:BAABNQAECn8jAAMIAAgKGBQdWQALAgAIAAgKGBQdWQALAgAbAAYK4QiE/wAaAQAAAA==.Insayn:BAAANQADCgIIAgABNQAECgkJIgAbAEslAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Io='Ioboryu:BAAANQAECgIIAgABNQAFFAYIDwAhACMeAA==.',
Ir='Ironwolf:BAABNQAECn8wAAIkAAkK9w7LFQDHAQAkAAkK9w7LFQDHAQAAAA==.',
Ja='Jademoot:BAABNQAECn8dAAIgAAgK4BgQFAA2AgAgAAgK4BgQFAA2AgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIJAgAAAA==.Jaylaah:BAAANQAECgQIBgAAAA==.Jayvlyn:BAAANQAECgYIDQAAAA==.',
Je='Jessex:BAAANQABCgIIAgAAAA==.',
Ji='Jiinn:BAAANQAECgQIBQAAAA==.',
Jj='Jjman:BAAANQAECgYIBwABNQAECgkJHQAbAAsjAA==.Jjuicyfruit:BAAANQADCgYIEgAAAA==.',
Jo='Jodirty:BAAANQADCgYIBgAAAA==.Joftokal:BAABNQAECn8lAAIOAAgKEBVhVQAhAgAOAAgKEBVhVQAhAgAAAA==.Jokesonme:BAAANQAECgMIBgAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAABNQAECn8aAAIIAAkKMR/OFgAgAwAIAAkKMR/OFgAgAwAAAA==.',
Ju='Junpana:BAAANQAECgYIBwAAAA==.',
Ka='Kakiso:BAABNQAECn8eAAMjAAgKGRbPIQDRAQAjAAgKGRbPIQDRAQAbAAUKgQ0YEgH6AAAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAACNQAFFH8IAAIWAAYKGhhdAQAQAgAWAAYKGhhdAQAQAgA1AAQKfzQAAhYACQojJFUDAGkDABYACQojJFUDAGkDAAAA.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQAECgIIAgAAAA==.',
Kh='Khailyn:BAAANQADCgIJAgAAAA==.',
Ki='Kikuu:BAABNQAECn8lAAIjAAgKpyD9DADKAgAjAAgKpyD9DADKAgAAAA==.Kin:BAAANQADCggICwAAAA==.Kiradanna:BAABNQAECn8wAAIhAAkKSR81DQAPAwAhAAkKSR81DQAPAwAAAA==.Kiroa:BAAANQAECgUIEwAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAABNQAECn8eAAMEAAkKgxi7gQDdAQAEAAcKCBa7gQDdAQAFAAMKnxh7OQDaAAAAAA==.Knotty:BAAANQAECgYIBwAAAA==.Knuckleup:BAAANQADCgUIBQABNQAECgUIBwANAAAAAA==.',
Ko='Koff:BAACNQAFFH8PAAIgAAUKnyXqAQAiAgAgAAUKnyXqAQAiAgA1AAQKfx8AAiAACQpYJdECAIsDACAACQpYJdECAIsDAAAA.Koino:BAAANQAECgUIBQAAAA==.Koreshei:BAAANQAECgUICAAAAA==.Koressita:BAAANQADCgYIBgAAAA==.',
Kr='Krixxus:BAAANQAECgQIBwABNQAECgUIBwANAAAAAA==.',
Ku='Kuni:BAAANQAECgYIGAAAAQ==.Kurius:BAAANQAECgIIBAAAAA==.Kuzan:BAAANQAECgcIEgABNQAECgkJJQAOADgdAA==.',
Ky='Kylian:BAAANQAECgcICwABNQAECgkJMAAhAEkfAA==.',
La='Lamynx:BAAANQAECgUIEgAAAA==.Larinstore:BAAANQAECggIAQAAAA==.Lazydragon:BAABNQAECn8hAAQbAAgK4w3vrADAAQAbAAgK4w3vrADAAQAIAAIKUgf3BAFnAAAjAAIKQAhdZQBIAAAAAA==.',
Le='Lelouch:BAAANQAECgYIDgABNQAECgkJJQAOADgdAA==.Leone:BAAANQAECgQIBAABNQAECggIIwAEAKEeAA==.',
Li='Liberation:BAABNQAECn8XAAIhAAcK8xcYMAC8AQAhAAcK8xcYMAC8AQAAAA==.Lichhorde:BAAANQABCgEIAQAAAA==.Lilgirlblue:BAABNQAECn8bAAICAAgKfA6uggADAgACAAgKfA6uggADAgAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECn8tAAMFAAkKqwscIgBfAQAEAAcKQAmjrgBuAQAFAAcKCwkcIgBfAQAAAA==.Lineste:BAABNQAECn8ZAAIBAAcKIiDvkABdAgABAAcKIiDvkABdAgAAAA==.Lion:BAAANQAECgYIDgAAAA==.',
Ll='Llyolis:BAAANQAECgUIBwAAAA==.',
Lo='Lockdeeznutz:BAAANQADCggIDAAAAA==.Loldie:BAAANQAECgYIEQAAAA==.Lonepanda:BAACNQAFFH8QAAIkAAYKNx7+AAD/AQAkAAYKNx7+AAD/AQA1AAQKfzYAAiQACQpTJX8BALcDACQACQpTJX8BALcDAAAA.Lorwynx:BAABNQAECn8xAAIBAAkKTiD8LAA0AwABAAkKTiD8LAA0AwAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgkJIgAbAEslAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQAECgMIAwAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Maalk:BAAANQADCgYICgAAAA==.Mabellah:BAAANQAECgUIBQAAAA==.Maemikyu:BAABNQAECn9TAAIaAAkKcSTVAgC9AwAaAAkKcSTVAgC9AwAAAA==.Magebuttkick:BAAANQADCggIDAABNQAFFAYIDwACABohAA==.Magusultimis:BAABNQAECn8bAAIHAAgKDAUeGAA2AQAHAAgKDAUeGAA2AQAAAA==.Mahöshöjo:BAAANQAECgMIBQAAAA==.Maintank:BAAANQAECgUIDgAAAA==.Makepoop:BAABNQAECn8qAAIPAAkKZiFxCwAsAwAPAAkKZiFxCwAsAwAAAA==.Maloa:BAAANQADCgYIBgAAAA==.Manbomanbo:BAAANQAECgQIBAABNQAECggIBAANAAAAAA==.Marianita:BAABNQAECn8cAAMTAAkKkx8UFgDoAgATAAkKkx8UFgDoAgAhAAEKAADHaQA3AAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQAECgMIBgAAAA==.Melfist:BAAANQAECgUIEQAAAA==.Melphis:BAAANQADCgcIBwAAAA==.Melysse:BAAANQAECgcIEgAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.Mereo:BAABNQAECn8UAAIfAAYKgxi/KwC5AQAfAAYKgxi/KwC5AQABNQAECgkJJQAOADgdAA==.',
Mi='Mikiko:BAABNQAECn8qAAIOAAgKIg9jZADwAQAOAAgKIg9jZADwAQAAAA==.Mikto:BAAANQADCgEJAQAAAA==.Millcreek:BAABNQAECn8cAAIKAAcKZgz3OQBLAQAKAAcKZgz3OQBLAQAAAA==.Milliananeko:BAAANQAECgQIBAABNQAECgUIDQANAAAAAA==.Miracat:BAAANQAECgQIBgAAAA==.Missindragon:BAABNQAECn8lAAISAAgKRSGtHQDzAgASAAgKRSGtHQDzAgAAAA==.',
Mo='Moarass:BAAANQADCggICAABNQAECgkJIQAKAGcTAA==.Moomoohead:BAAANQAECgQIBQABNQAECgYIBwANAAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAAANQAECgYIEgAAAA==.Morticus:BAABNQAECn8VAAMFAAcKKAOBLwAKAQAFAAcK1AKBLwAKAQAEAAUK9AL2CwGtAAAAAA==.',
Ms='Msthea:BAAANQAECgUIEQAAAA==.',
My='Mythicc:BAAANQADCgUIAgABNQADCggIDQANAAAAAA==.',
['Mä']='Mälina:BAAANQAECgMIBQAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narrthas:BAAANQAECgUICAAAAA==.Narru:BAACNQAFFH8QAAICAAYKYxyHBQD3AQACAAYKYxyHBQD3AQA1AAQKfy8ABAIACQppJQwGAK8DAAIACQppJQwGAK8DAAYABQrEC8hQAOMAACgABAoaC6QOALAAAAAA.',
Ne='Nebyula:BAAANQAECgUIEAAAAA==.',
Ni='Nightswitchh:BAAANQADCggICAAAAA==.Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAAANQAECgUIEQAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQAECgUIBQABNQAFFAYIFAABAH4PAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQAECgMIBgABNQAECgkJJgAdALoWAA==.',
Ny='Nykoleus:BAAANQAECgYICQAAAA==.Nylokar:BAAANQADCgQIBAAAAA==.',
Oa='Oatbarrel:BAAANQADCgcIDwAAAA==.Oatbreaker:BAAANQADCgYICgAAAA==.',
Og='Oggoat:BAAANQAECgUIBgAAAA==.',
Oi='Oignon:BAAANQADCggICAAAAA==.',
Oz='Ozyy:BAAANQAECgEIAQAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Paligator:BAAANQADCgcIDAAAAA==.Pallyfraud:BAAANQADCgIIAgAAAA==.Pallygranny:BAEBNQAECn8lAAIbAAcK5CDUXQB7AgAbAAcK5CDUXQB7AgAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgMIBAAAAA==.',
Pi='Pibbs:BAACNQAFFH8HAAIBAAUKgBQAHQCTAQABAAUKgBQAHQCTAQA1AAQKfyYAAgEACQpNIshOAOQCAAEACQpNIshOAOQCAAAA.',
Pl='Plaguepanda:BAABNQAECn8yAAQUAAkK9CNRGQDzAgAUAAkKUiJRGQDzAgAYAAkKPx8rFADoAgADAAEKFRoJyQA0AAAAAA==.Platinumcas:BAAANQAECgEIAQAAAA==.Pluribus:BAAANQADCgcIDgAAAA==.',
Po='Poohonroids:BAAANQAECgYIDAAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Priestpvp:BAAANQAECgEIAQAAAA==.Priva:BAAANQADCggICgAAAA==.Protagoras:BAAANQAECgEIAgAAAA==.',
['Pä']='Pänz:BAABNQAECn8bAAMcAAgKfw3EEwC9AQAcAAgKfw3EEwC9AQAmAAEKHwdIZQAmAAAAAA==.',
Ra='Rafig:BAACNQAFFH8WAAIBAAYKQiR4BAB9AgABAAYKQiR4BAB9AgA1AAQKfzkAAgEACQqrJvUBAO4DAAEACQqrJvUBAO4DAAAA.Ragefyre:BAAANQAECgIJAgAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgcJDQABNQADCgUIBQANAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAACNQAFFH8JAAIOAAQKgwRCHADZAAAOAAQKgwRCHADZAAA1AAQKfysAAw4ACQqhFdxOADkCAA4ACQqhFdxOADkCABIACQqLD9hqAMcBAAAA.Ratbasterd:BAAANQAECggICAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayve:BAAANQABCgIIAgAAAA==.Rayy:BAABNQAECn8cAAITAAkKwyAsDQA8AwATAAkKwyAsDQA8AwAAAA==.Razgar:BAAANQAECgIIAgAAAA==.',
Re='Reeji:BAAANQAECgMIAwAAAA==.Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAABNQAECn8oAAIVAAgKQRfkKABGAgAVAAgKQRfkKABGAgAAAA==.Rexx:BAAANQADCgMIAwAAAA==.Reywhite:BAAANQAECgEIAgABNQAECgQICAANAAAAAA==.',
Rh='Rhazzah:BAAANQAECgIIAgAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAABNQAECn85AAMSAAkKcxv/JQDLAgASAAkKcxv/JQDLAgAOAAEKAAAyRAEqAAAAAA==.Riteaid:BAAANQAECgQICwAAAA==.Ritual:BAAANQAECgQIBAABNQAECgkJIgAbAEslAA==.',
Ro='Robe:BAAANQAECgIJAwABNQAECgUIDQANAAAAAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAABNQAECn8YAAMeAAgKNwtYHADiAAAdAAgKZwiGsgCZAQAeAAQKwQ1YHADiAAAAAA==.Rorthach:BAAANQAECgEIAQAAAA==.Roru:BAABNQAECn9GAAMEAAkKOhjrPgCSAgAEAAkKOhjrPgCSAgAFAAQK5gKxUgCFAAAAAA==.Roseire:BAAANQAECgQICAAAAA==.Rosethebrute:BAABNQAECn8tAAIdAAgKhR7MTQCdAgAdAAgKhR7MTQCdAgAAAA==.Rosetheholy:BAAANQAECgcIEgABNQAECggILQAdAIUeAA==.Rougeloving:BAABNQAECn8YAAIRAAkKdRn2EABuAgARAAkKdRn2EABuAgAAAA==.',
Ru='Ruler:BAAANQAECggIEwAAAA==.Ruli:BAABNQAECn87AAICAAkK0CCPHgAcAwACAAkK0CCPHgAcAwAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECgkJJQAOAAMeAA==.',
Ry='Ryshin:BAABNQAECn8wAAMVAAkKehUPKABLAgAVAAkKehUPKABLAgARAAUKaQZXNQAJAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAABNQAECn8dAAIbAAkKCyN3JQAtAwAbAAkKCyN3JQAtAwAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQAECgQICQABNQAECggIFgANAAAAAA==.Sanctano:BAAANQAECgcIDwAAAA==.Saneras:BAAANQAECgUICwAAAA==.Sapdo:BAEANQAFFAIIAgABNQAFFAQIDgAdACshAA==.Sarshia:BAAANQADCgYJCAAAAA==.Sayn:BAABNQAECn8iAAIbAAkKSyVZCAC4AwAbAAkKSyVZCAC4AwAAAA==.',
Sc='Schultzies:BAABNQAECn8oAAMMAAkK5h4kAwDLAgAMAAgKyB4kAwDLAgAaAAkKmRbINACSAgAAAA==.Scorchdk:BAAANQADCggIDQAAAA==.',
Sd='Sdog:BAAANQAECgQIBgAAAA==.',
Se='Seanboyymage:BAACNQAFFH8IAAIBAAMKHRKaNwDiAAABAAMKHRKaNwDiAAA1AAQKfzsAAgEACQplHlc0ACEDAAEACQplHlc0ACEDAAAA.Seina:BAABNQAECn8eAAIdAAcKlRY+lADlAQAdAAcKlRY+lADlAQAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgQICQAAAA==.Seulrene:BAABNQAECn8mAAIUAAgKIyCEGwDlAgAUAAgKIyCEGwDlAgAAAA==.Seyna:BAAANQADCgQIBAAAAA==.',
Sh='Shake:BAAANQAECgIIAgAAAA==.Shambella:BAAANQAECgQIBAAAAA==.Shamlaw:BAABNQAECn8dAAISAAgKQhc1VQAPAgASAAgKQhc1VQAPAgAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQAECgUIDAAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAABNQAECn8ZAAMfAAcKHgjiOwAxAQAfAAcKHgjiOwAxAQAgAAMKwwFaRgBMAAAAAA==.Shhuffle:BAABNQAECn8tAAMRAAkKqiMdAgCWAwARAAkK2SIdAgCWAwAVAAgKbx3rIAB4AgAAAA==.Shieldmommy:BAAANQAECgUICAABNQAFFAYIFAABAH4PAA==.Shiv:BAAANQAECgYIDAAAAA==.Shockuse:BAAANQAECgcICwAAAA==.Shodoch:BAAANQADCgYICwAAAA==.Shorukin:BAAANQAECgMIAwAAAA==.Shupasins:BAABNQAECn83AAQSAAkKKB+pGAAOAwASAAkKKB+pGAAOAwAOAAgKrhhyXAAJAgAWAAYK8RbaFwDlAQAAAA==.Shyamablue:BAABNQAECn8ZAAImAAgKXwcuLQAqAQAmAAgKXwcuLQAqAQAAAA==.',
Si='Silvercas:BAABNQAECn8hAAIRAAkKHxNSEgBcAgARAAkKHxNSEgBcAgAAAA==.Simpleyfire:BAABNQAECn8lAAMOAAkKAx4uGwAkAwAOAAkKAx4uGwAkAwASAAcKyRGugQCDAQAAAA==.',
Sk='Skullet:BAABNQAECn8ZAAIdAAgKHQ0mlgDhAQAdAAgKHQ0mlgDhAQAAAA==.Skurmpls:BAAANQADCgcIBwABNQAECgYIDwANAAAAAA==.',
Sl='Slamjam:BAAANQAFFAMIAwABNQAFFAYIEwAPAKwhAA==.Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAABNQAECn8cAAIBAAcKBBHP8wCgAQABAAcKBBHP8wCgAQAAAA==.',
Sm='Smooth:BAABNQAECn8zAAMBAAkKXBrzWADOAgABAAkKEhrzWADOAgAHAAQKNhJJJADIAAAAAA==.',
Sn='Snaphance:BAABNQAECn8ZAAIVAAcKFAzrRACuAQAVAAcKFAzrRACuAQAAAA==.Sneekypete:BAAANQADCgYIBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Sniparcat:BAAANQADCgYICAAAAA==.Snipercat:BAABNQAECn8fAAIdAAkKTBPgbABIAgAdAAkKTBPgbABIAgAAAA==.Snuffles:BAABNQAECn8fAAIbAAcKvR3qZwBgAgAbAAcKvR3qZwBgAgAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solange:BAAANQADCgYIBgAAAA==.Sorscha:BAAANQADCggIDwAAAA==.Soupforsale:BAAANQABCgQIBQAAAA==.',
Sp='Spammy:BAABNQAECn8ZAAMIAAkKwhRqRwBGAgAIAAkKwhRqRwBGAgAbAAEKlAjlogEzAAAAAA==.Sparlyy:BAACNQAFFH8TAAMPAAYKrCGtBwCVAQAPAAQKYSStBwCVAQAaAAIK0STFHwDcAAA1AAQKfzQAAw8ACQqpJvUAAOMDAA8ACQqpJvUAAOMDABoAAgqnFOncAIkAAAAA.Spectrality:BAAANQAECgEIAQABNQAECgUIDQANAAAAAA==.',
Ss='Sswordy:BAACNQAFFH8WAAICAAYKzBYUBgDsAQACAAYKzBYUBgDsAQA1AAQKf1AAAgIACQp7I10FALgDAAIACQp7I10FALgDAAAA.Sswordyvani:BAAANQADCgYIDAABNQAFFAYIFgACAMwWAA==.',
St='Stephhunt:BAAANQAECgQIBAAAAA==.Stimulus:BAABNQAECn8hAAMaAAgKpQu7fACfAQAaAAgKpQu7fACfAQAMAAUKnQJ1GQCeAAAAAA==.Stinkynuuts:BAAANQADCggIHwAAAA==.Stompy:BAAANQAECgEIAgAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgYIBAAAAA==.',
Su='Sumbadvoodoo:BAAANQAECgMIBQAAAA==.Sunkist:BAAANQAECgYIDgAAAA==.Sunwing:BAAANQADCgUJBQAAAA==.Sureina:BAAANQAECgYICgAAAA==.Surlym:BAABNQAECn8tAAIgAAkKGSRcAgCZAwAgAAkKGSRcAgCZAwAAAA==.',
Sw='Swash:BAAANQADCggIDQAAAA==.Switchglaive:BAABNQAECn8wAAMTAAkK4Q6gMwALAgATAAkK1w6gMwALAgAnAAcK7QfbGQAUAQAAAA==.',
Sy='Sylphie:BAAANQAECgIIAgAAAA==.Symphemon:BAABNQAECn8pAAMhAAkKpw7TKgDnAQAhAAkKFQ7TKgDnAQATAAgK7woXSgB3AQAAAA==.Symphoid:BAAANQAECgYICgAAAA==.Syseloris:BAABNQAECn8eAAMnAAgK8hoyCABzAgAnAAgK8hoyCABzAgATAAUK/g8DVgAuAQAAAA==.Sythion:BAACNQAFFH8GAAIXAAQKGQxKCADzAAAXAAQKGQxKCADzAAA1AAQKfygAAxcACQojGPsKALcCABcACQojGPsKALcCABAABwqUEBolAJQBAAAA.',
['Sâ']='Sâlisbury:BAAANQADCgYIDAAAAA==.',
['Së']='Sëphy:BAAANQAECgEIAQAAAA==.',
Ta='Taediris:BAAANQADCgYIDgAAAA==.Taliiha:BAAANQAECgUIBgAAAA==.Tanao:BAAANQAECgUICgAAAA==.',
Te='Teenieween:BAAANQADCgIIAgAAAA==.Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECgYIBgAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thewarfox:BAAANQABCgIIAgAAAA==.Thopegor:BAAANQAECgIJAgAAAA==.Thundergunt:BAAANQAECgcIBwABNQAECgkJLwAIABMdAA==.',
Ti='Tianjin:BAAANQAECgEIAQAAAA==.Tickslap:BAAANQADCggIFQAAAA==.Timid:BAAANQADCgIIAgAAAA==.Tintaglia:BAABNQAECn8cAAIbAAcKCBQBsgC1AQAbAAcKCBQBsgC1AQAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgUIDAAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAABNQAECn8lAAICAAgK6heaWgBiAgACAAgK6heaWgBiAgAAAA==.',
Tu='Tunawhale:BAAANQAECgMIBgAAAA==.',
Tw='Twickenham:BAAANQADCgMIAwAAAA==.',
Ty='Tyloriavis:BAAANQAECgUICgAAAA==.',
['Tä']='Tämpicö:BAAANQADCgQIBAAAAA==.',
Ul='Ulfberht:BAAANQADCggIDwAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgYIEgANAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Unaware:BAAANQADCgYIBgABNQAECgQIBAANAAAAAA==.Uncletouchie:BAAANQADCgIIAgAAAA==.Unáware:BAAANQADCgUIBQAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.Valára:BAAANQABCgYIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Vinsamo:BAAANQADCgcIBwAAAA==.Violentjudge:BAABNQAECn8iAAIbAAgKURwnXACAAgAbAAgKURwnXACAAgAAAA==.Violla:BAAANQAECgcIEQAAAA==.Virgocelest:BAAANQAECgUIDQAAAA==.Viridion:BAAANQAECgUIDAAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vonmack:BAAANQADCggICAAAAA==.Vorlos:BAAANQAECgcIDAABNQAECgkJIgADAJseAA==.',
Vr='Vreeg:BAABNQAECn8cAAIUAAcKBBAFZwBxAQAUAAcKBBAFZwBxAQAAAA==.',
Wh='Whiteflag:BAABNQAECn83AAIbAAkKnSZdBgDGAwAbAAkKnSZdBgDGAwAAAA==.Whoopington:BAAANQAECgcIDAAAAA==.Whyamialive:BAACNQAFFH8VAAIDAAYKhSRAAgCDAgADAAYKhSRAAgCDAgA1AAQKfzgAAgMACQrWJpQAAPUDAAMACQrWJpQAAPUDAAAA.',
Wi='Wickedwolfin:BAAANQADCgYIBgAAAA==.Wiffles:BAAANQAECgUIBQABNQAFFAYIEQAUAL4fAA==.Willowes:BAEANQADCggICAABNQAFFAUIEQAaAHoTAA==.Willowest:BAEANQAECgQIBgABNQAFFAUIEQAaAHoTAA==.Willowing:BAEBNQAECn8ZAAQEAAkKCxn9TwBhAgAEAAgKXBj9TwBhAgAFAAIKtBnYTgCRAAAlAAEKLgJ4NAAnAAABNQAFFAUIEQAaAHoTAA==.Willowish:BAECNQAFFH8RAAIaAAUKehMcEACOAQAaAAUKehMcEACOAQA1AAQKfzYAAxoACQrhIpEHAIcDABoACQrhIpEHAIcDAA8AAQoGCCt8AC4AAAAA.Willowly:BAEANQAECgQIBgABNQAFFAUIEQAaAHoTAA==.Winterz:BAABNQAECn8cAAIBAAkK/BdCZAC2AgABAAkK/BdCZAC2AgAAAA==.Wiskii:BAABNQAECn8cAAIjAAcKbxvcGQAhAgAjAAcKbxvcGQAhAgAAAA==.Wizerds:BAAANQADCgQIBAABNQAECgUIDQANAAAAAA==.',
Wo='Woopecushion:BAAANQADCgIIAgAAAA==.Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgcIDgABNQAFFAYIFgAfAAIRAA==.Wytnarthom:BAAANQAECgcIBwABNQAFFAYIFgAfAAIRAA==.Wytohne:BAACNQAFFH8WAAMfAAYKAhG4BQC5AQAfAAYKAhG4BQC5AQALAAEKfQIqCwA9AAA1AAQKfzgAAx8ACQo2H6gMAAwDAB8ACQo2H6gMAAwDAAsAAQoAAPUvADkAAAAA.',
Xa='Xaree:BAABNQAECn8cAAIgAAcKWh8DEQBqAgAgAAcKWh8DEQBqAgAAAA==.Xariá:BAAANQADCgYIFAABNQAECgUIEQANAAAAAA==.',
Xc='Xcat:BAABNQAECn8hAAIbAAkKRBh9hAAaAgAbAAkKRBh9hAAaAgAAAA==.',
Xy='Xydros:BAAANQABCggJDwAAAA==.Xymer:BAAANQAECgMIBgAAAA==.',
Yi='Yim:BAABNQAECn8gAAIbAAkKIx7ENgDxAgAbAAkKIx7ENgDxAgAAAA==.Yismypetdead:BAAANQAECgQIBAABNQAECgUIBwANAAAAAA==.',
Yo='Yorshka:BAABNQAECn81AAIaAAkKohauNwCHAgAaAAkKohauNwCHAgAAAA==.',
Yw='Ywach:BAAANQAECggIEwABNQAECgkJJQAOADgdAA==.',
['Yú']='Yúno:BAABNQAECn8lAAIOAAkKOB1jGgApAwAOAAkKOB1jGgApAwAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAANAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAANAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgQICQANAAAAAA==.Zalliea:BAAANQAECgUICgAAAA==.Zaraki:BAAANQAECgIIAgAAAA==.',
Ze='Zeff:BAAANQAECgMIBgAAAA==.',
Zn='Znåp:BAAANQADCgQIBAAAAA==.',
Zo='Zompt:BAAANQAECgIIBgAAAA==.Zorndk:BAAANQAECgYICwAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQAECgMIBgANAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Õn']='Õni:BAABNQAFFH8JAAIDAAUK3AsbEABOAQADAAUK3AsbEABOAQAAAA==.',
['Ön']='Öni:BAACNQAFFH8HAAIkAAMKWSCrAwANAQAkAAMKWSCrAwANAQA1AAQKfy0AAiQACQpcJBEDAHMDACQACQpcJBEDAHMDAAAA.',
['Øm']='Ømêgá:BAABNQAECn8eAAMBAAgKUAOSHgFVAQABAAgKUAOSHgFVAQApAAEKdAHDDwAYAAAAAA==.',
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
