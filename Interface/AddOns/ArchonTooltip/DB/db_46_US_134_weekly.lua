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

local lookup = {'DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','Druid-Guardian','Druid-Feral','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Warlock-Destruction','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Priest-Holy','Evoker-Augmentation','DeathKnight-Frost','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Warlock-Affliction','Monk-Mistweaver','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Priest-Shadow','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Shaman-Restoration','Rogue-Subtlety','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aazr:BAAALgADCgQJBAAAAA==.',
Ab='Abartheris:BAABLgAECn8dAAIBAAYJTwWS4wDEAAABAAYJTwWS4wDEAAAAAA==.Abroghast:BAAALgAECgUJBQAAAA==.',
Ac='Acanoffood:BAABLgAECn8vAAMCAAkJghOEPADJAQACAAkJghOEPADJAQADAAYJfgyuGADLAAAAAA==.',
Ad='Adel:BAAALgAECgMJAwAAAA==.Adelil:BAAALgADCgEJBAAAAA==.Ademai:BAAALgADCgIJAgAAAA==.Adeptus:BAABLgAECn8VAAIEAAYJ5Q36IgDwAAAEAAYJ5Q36IgDwAAAAAA==.',
Ae='Aemeath:BAACLgAFFH8HAAICAAQJeA5/UQDoAAACAAQJeA5/UQDoAAAuAAQKfxwAAgIACAkXHDY6AAsCAAIACAkXHDY6AAsCAAAA.Aendres:BAAALgAECgYJEAAAAA==.Aethalyn:BAAALgAECggJCAAAAA==.',
Af='Afitis:BAAALgADCgIJAgAAAA==.',
Ag='Agriopas:BAABLgAECn83AAMFAAgJQBQ+FgCPAQAFAAgJ5BM+FgCPAQAGAAcJ8g0UHAAXAQAAAA==.',
Ah='Aharon:BAAALgADCgkJCgAAAA==.',
Ai='Aireas:BAABLgAECn8cAAIHAAgJaCDDFgCWAgAHAAgJaCDDFgCWAgAAAA==.Aizen:BAAALgADCgYJBgABLgAECgYJCAAIAAAAAA==.',
Al='Alassomorph:BAAALgAECgcJEAAAAA==.Alazaie:BAAALgADCgMJAwAAAA==.Albus:BAACLgAFFH8PAAIJAAQJexdZVAA0AQAJAAQJexdZVAA0AQAuAAQKfywAAgkACQl3IDQZABQDAAkACQl3IDQZABQDAAAA.Aldasar:BAAALgADCgkJCQAAAA==.Allayna:BAEBLgAECn83AAIKAAkJdiF2EgDMAgAKAAkJdiF2EgDMAgAAAA==.Almitvez:BAAALgADCgcJBwABLgAECggJGwALADAdAA==.Aloha:BAACLgAFFH8NAAIMAAQJyBTjIAALAQAMAAQJyBTjIAALAQAuAAQKfxwAAwwACAm/E1kmAMwBAAwACAm/E1kmAMwBAAoAAQkQAvKzAR0AAAAA.Alohacuzz:BAAALgAECgEJAgAAAA==.Alysaliu:BAACLgAFFH8XAAIHAAYJFB7cIgCdAQAHAAYJFB7cIgCdAQAuAAQKfzYAAwcACQkYJf4GAB0DAAcACQkYJf4GAB0DAA0ABAnBFXkrABIBAAAA.Alysen:BAAALgAECgYJEgABLgAECgYJHQAOAC8jAA==.',
Am='Amisan:BAAALgADCgEJAQAAAA==.Amishpaladin:BAAALgAFFAMJBAAAAA==.Amishwarlock:BAAALgAECgYJCQABLgAFFAMJBAAIAAAAAA==.Amonotep:BAAALgAECgQJAwAAAA==.Amorianar:BAAALgAECgEJAQABLgAECgkJHgAPAHsVAA==.Amory:BAAALgAECgYJDAABLgAECgEJAQAIAAAAAA==.',
An='Anchor:BAABLgAECn8cAAIPAAYJrwaNXwC2AAAPAAYJrwaNXwC2AAAAAA==.Andja:BAACLgAFFH8MAAIQAAQJuiOnCQCQAQAQAAQJuiOnCQCQAQAuAAQKf0kAAhAACQlyJm4AAIYDABAACQlyJm4AAIYDAAAA.Andromedae:BAABLgAECn8pAAIRAAkJoBBvIQCqAQARAAkJoBBvIQCqAQAAAA==.Andurìl:BAAALgAECggJEAAAAA==.Anexa:BAAALgAECgYJDwAAAA==.Angela:BAAALgAECgYJDQAAAA==.Angelicshado:BAAALgADCgYJBgAAAA==.Anthbow:BAAALgAECgYJCQAAAA==.Anurek:BAAALgAECgEJAQABLgAECgEJAwAIAAAAAA==.',
Ar='Arelok:BAAALgAECgEJAQAAAA==.Argulas:BAAALgADCgkJFQAAAA==.Ariajade:BAAALgAECgEJAQAAAA==.Ark:BAAALgAECgYJEgAAAA==.Arn:BAAALgAECgQJCQABLgAECgkJFwASAC4LAA==.Arthrex:BAABLgAECn8UAAITAAcJxRoSCAD+AQATAAcJxRoSCAD+AQAAAA==.Arthus:BAAALgAECgYJDAAAAA==.Arturias:BAAALgAECgQJCwABLgAECgkJOQAUAMoiAA==.',
As='Ashant:BAAALgADCgUJBQAAAA==.Asmobob:BAABLgAECn8nAAIUAAkJlBqgCwBeAgAUAAkJlBqgCwBeAgAAAA==.',
Au='Augmentin:BAABLgAECn8iAAMVAAgJSRy8HgBHAgAVAAcJDB+8HgBHAgAWAAgJMhAUMQBKAQAAAA==.Auntfranny:BAAALgADCgEJAQAAAA==.Autoshot:BAAALgAECgUJBQAAAA==.',
Av='Avanie:BAAALgADCgYJBgAAAA==.Avina:BAAALgAECgYJDwAAAA==.Avrami:BAAALgADCgkJCgAAAA==.',
Aw='Aw:BAABLgAECn9CAAQHAAkJuSLaBgAfAwAHAAkJuSLaBgAfAwANAAUJFhZyJAA3AQAXAAIJyxYkNQBBAAAAAA==.Awokenbigdam:BAAALgAECgEJAQAAAA==.',
Az='Azràel:BAAALgAECgQJBwAAAA==.',
Ba='Babycoffee:BAAALgAECgkJDgAAAA==.Bahamutz:BAAALgADCgUJBAAAAA==.Bahwee:BAAALgAECgYJDwAAAA==.Bamboodragon:BAAALgAECggJCgAAAA==.Bangbangdou:BAABLgAECn8nAAIMAAkJshnwEQB6AgAMAAkJshnwEQB6AgAAAA==.Banzjo:BAAALgAECgEJAQAAAA==.Bastor:BAAALgAECgQJBAAAAA==.Bayle:BAAALgAECgYJDQAAAA==.',
Be='Bearnekkid:BAAALgAECgEJAQABLgAECgYJFgAPAAkXAA==.Bearsgomoo:BAAALgAECgYJDgABLgAECgkJNQATADghAA==.Beef:BAAALgAECgEJAQABLgAECgQJBQAIAAAAAA==.Beerthrowguy:BAABLgAECn8bAAMLAAkJ0yGgBAD0AgALAAkJ0yGgBAD0AgAYAAcJJhxAHgATAgABLgAECgkJJAAFAKsmAA==.Bellaofroses:BAAALgAECgEJAQAAAA==.Bellatrix:BAAALgADCgYJBgAAAA==.Beneb:BAAALgAECgYJCwAAAA==.Benebeorn:BAACLgAFFH8VAAICAAUJ7Rl7NQA4AQACAAUJ7Rl7NQA4AQAuAAQKfx8AAgIACQmsIrUaALMCAAIACQmsIrUaALMCAAAA.Benkinobi:BAAALgAECgQJDQAAAA==.',
Bh='Bhaer:BAAALgAECgEJAgAAAA==.',
Bi='Bichewich:BAAALgADCgYJBgAAAA==.Bigal:BAAALgAECgMJAwABLgAECgkJDgAIAAAAAA==.Bigshot:BAAALgADCgYJCQAAAA==.Billyjoe:BAAALgAECgMJBQAAAA==.Binti:BAAALgADCgMJAwAAAA==.Bittronoxus:BAABLgAECn84AAIJAAkJ/BU3NABBAgAJAAkJ/BU3NABBAgAAAA==.',
Bl='Blackryder:BAAALgAECgUJDgAAAA==.Bladesosteel:BAABLgAECn8UAAICAAcJixMfWABzAQACAAcJixMfWABzAQAAAA==.Bleys:BAAALgAECgQJBwABLgAECgkJMgAKAMkdAA==.Bloge:BAAALgAECgEJAQAAAA==.',
Bo='Bobbysmerica:BAABLgAECn85AAMZAAkJFCKkAwDvAgAZAAkJFCKkAwDvAgAQAAEJ9At+QgA0AAAAAA==.Bobocanfly:BAABLgAECn8nAAMDAAkJyhgICADqAQADAAkJyhgICADqAQAUAAEJAAAPdAAxAAAAAA==.Bodikhan:BAAALgAECgYJCwAAAA==.Bonesnatcher:BAAALgADCgEJAQAAAA==.Boozumbler:BAAALgAECgIJAwAAAA==.',
Br='Braxte:BAABLgAECn8uAAMOAAkJdR1nFwCRAgAOAAgJOR5nFwCRAgAQAAUJmxRHJQAzAQAAAA==.Breecy:BAAALgAECgUJDgAAAA==.Briguydkguy:BAACLgAFFH8KAAIBAAQJkQtUdwAGAQABAAQJkQtUdwAGAQAuAAQKfxgAAgEACAmfFuhgANEBAAEACAmfFuhgANEBAAAA.Brisstle:BAAALgAECggJEAAAAA==.Britziola:BAABLgAECn8gAAMNAAcJ9BuHBgDpAQANAAcJ9BuHBgDpAQAHAAEJVAuZOwEwAAABLgAECgEJAQAIAAAAAA==.Brokenvoid:BAABLgAECn8oAAICAAcJPh1UQwCyAQACAAcJPh1UQwCyAQABLgAFFAEJAQAIAAAAAA==.Bruiser:BAABLgAFFH8FAAMQAAMJMQY9KQCoAAAQAAMJMQY9KQCoAAAOAAEJRQCPUwAfAAAAAA==.Brusalt:BAAALgADCggJCAAAAA==.Brusten:BAABLgAECn8mAAIBAAkJySLBBwAvAwABAAkJySLBBwAvAwABLgAECgkJLgAOAHUdAA==.Bryce:BAEALgAECgUJEQABLgAFFAEJAQAIAAAAAA==.',
Bu='Buggies:BAACLgAFFH8gAAIJAAYJKiEaIgDZAQAJAAYJKiEaIgDZAQAuAAQKfzUAAgkACQmpJX4SADgDAAkACQmpJX4SADgDAAAA.Buggs:BAAALgAECgQJBQABLgAFFAYJIAAJACohAA==.Buldozz:BAABLgAECn8oAAIMAAcJVxa+NQClAQAMAAcJVxa+NQClAQAAAA==.Bullit:BAAALgADCgYJDgABLgAECgYJFgAPAAkXAA==.Burnination:BAABLgAECn8uAAIJAAkJOyU1BQBYAwAJAAkJOyU1BQBYAwAAAA==.Burnzie:BAAALgADCgcJCAAAAA==.Butterfayce:BAABLgAECn83AAMMAAkJGSETBQA5AwAMAAkJGSETBQA5AwAKAAYJ7w7/xwDxAAAAAA==.',
By='Bycew:BAEALgAFFAEJAQAAAA==.',
Bz='Bzu:BAAALgAECgcJCwAAAA==.',
Ca='Cadastrasz:BAACLgAFFH8PAAMSAAQJCAO2PgC7AAASAAQJCAO2PgC7AAAaAAEJtQF3KgAuAAAuAAQKf2cABBoACQkZFG4KADICABoACQkZFG4KADICABIACQmQC9YwAGkBABsAAwmsAWM5AE4AAAAA.Cae:BAAALgAECgQJBAAAAA==.Camachopres:BAAALgAECgUJCgAAAA==.Cameocreme:BAAALgAECgkJCgAAAA==.Captfrost:BAAALgAECgEJAQAAAA==.Carsonkiller:BAAALgADCgEJAQABLgAECggJJgANAJIbAA==.Catalyze:BAAALgAECgQJCAABLgAECgkJJQASANQNAA==.Cateurize:BAABLgAECn8lAAISAAkJ1A0MKACaAQASAAkJ1A0MKACaAQAAAA==.',
Ce='Ceenit:BAACLgAFFH8LAAIKAAQJAxiFMgA5AQAKAAQJAxiFMgA5AQAuAAQKfysAAgoACQkhHz8eAIYCAAoACQkhHz8eAIYCAAAA.Celalaliia:BAAALgADCgMJAwAAAA==.Celawyn:BAABLgAECn8YAAIcAAkJ8gpKJwBgAQAcAAkJ8gpKJwBgAQAAAA==.',
Ch='Chainedfire:BAAALgAECgQJCQAAAA==.Chasemon:BAABLgAECn8vAAMGAAkJyh8SAwDfAgAGAAkJyh8SAwDfAgAFAAEJphuJWABNAAAAAA==.Chaser:BAAALgAECgYJDwABLgAECgkJLwAGAMofAA==.Chasewise:BAAALgAECgUJBQABLgAECgkJLwAGAMofAA==.Chasez:BAAALgADCgYJBgABLgAECgkJLwAGAMofAA==.Chaøtical:BAAALgAECgcJEQAAAA==.Chicosan:BAAALgAECgYJEAAAAA==.Chiliconcrne:BAAALgAECgIJAgAAAA==.Chrisolski:BAAALgAECgMJBwABLgAECgcJBwAIAAAAAA==.',
Ci='Cirragos:BAABLgAECn8XAAQSAAcJfw6RSAD9AAASAAcJfw6RSAD9AAAaAAYJJAaRIgDRAAAbAAEJCQrvJQAvAAAAAA==.',
Cl='Clamer:BAAALgADCgcJEAAAAA==.Clawdite:BAAALgADCgYJBgABLgAECggJGwALADAdAA==.Clawesome:BAAALgAECgUJBgAAAA==.Cleansinq:BAAALgAECgEJAgAAAA==.Cloudsmoker:BAABLgAECn8nAAMVAAgJjA+2RwBmAQAVAAgJjA+2RwBmAQAWAAYJ3wzATgDDAAAAAA==.',
Co='Corien:BAAALgAECgYJEgAAAA==.Cortado:BAAALgAECgEJAQAAAA==.',
Cr='Crazegrippin:BAAALgAECgIJAwAAAA==.Crimsonmoon:BAABLgAECn8uAAIdAAkJPRBWDACSAQAdAAkJPRBWDACSAQAAAA==.Crow:BAAALgAFFAUJBQAAAQ==.Cryomara:BAAALgADCggJEAAAAA==.',
Cu='Cueball:BAAALgADCgYJDgAAAA==.Cutiepotooti:BAAALgAECgYJCgABLgAFFAUJFwAVAPAPAA==.',
Cy='Cylasta:BAAALgAECgEJAQAAAA==.Cyndraexa:BAABLgAECn8WAAIeAAYJEwXUUgC6AAAeAAYJEwXUUgC6AAAAAA==.Cynia:BAABLgAECn8bAAIUAAgJIgofKQAhAQAUAAgJIgofKQAhAQAAAA==.Cynra:BAABLgAECn8pAAMVAAkJbBylDQDkAgAVAAkJbBylDQDkAgAWAAEJXRJlhAA1AAAAAA==.Cyrakos:BAAALgADCgEJAQAAAA==.Cyrene:BAABLgAFFH8HAAIfAAUJvx7rGwB+AQAfAAUJvx7rGwB+AQAAAA==.',
['Cõ']='Cõwbell:BAAALgADCgEJAQAAAA==.',
Da='Daizy:BAAALgAECgEJAQAAAA==.Dalize:BAABLgAECn8aAAQaAAcJYxmGCwAaAgAaAAcJYxmGCwAaAgAbAAIJER1uLQCvAAASAAIJYRgWUACMAAAAAA==.Danarrath:BAABLgAECn8VAAIFAAcJlhLHJAAYAQAFAAcJlhLHJAAYAQABLgAECggJFQAgAHkRAA==.Danger:BAAALgAECgQJBQAAAA==.Danklins:BAABLgAECn9IAAMSAAkJNx3WCwCVAgASAAkJNx3WCwCVAgAbAAcJSxHUCwBKAQAAAA==.Dariabell:BAAALgAECgMJBQAAAA==.Darkramone:BAAALgAECgQJBgAAAA==.Darrow:BAAALgADCgQJBAAAAA==.Darthbane:BAAALgAECgYJDwAAAA==.Darthvada:BAABLgAECn8hAAMhAAgJDRkHHwBRAQABAAcJWBZcegBmAQAhAAcJbRIHHwBRAQAAAA==.Daydream:BAAALgAECgQJBQAAAA==.',
De='Deadlydemon:BAAALgADCgEJAQAAAA==.Deadpoint:BAABLgAECn8dAAIOAAYJLyOIJADKAQAOAAYJLyOIJADKAQAAAA==.Deadski:BAABLgAECn8VAAIBAAYJixnHiABKAQABAAYJixnHiABKAQAAAA==.Deathbayne:BAAALgAECgEJAQAAAA==.Deathfrost:BAACLgAFFH8KAAIJAAQJ0RCXXQAlAQAJAAQJ0RCXXQAlAQAuAAQKfykAAgkACAlSH74sAGACAAkACAlSH74sAGACAAAA.Debz:BAAALgADCgkJCQAAAA==.Defeatzhealz:BAAALgAECgYJEwAAAA==.Defeatzhunt:BAABLgAECn8XAAMfAAgJCxnXHABZAgAfAAgJCxnXHABZAgAdAAEJAABunAAJAAAAAA==.Deirdra:BAAALgAECgUJBQABLgAECgkJMgAKAMkdAA==.Delarium:BAAALgAECgIJAwAAAA==.Demonaria:BAABLgAECn85AAMUAAkJyiJHBQDhAgAUAAkJiSJHBQDhAgADAAUJbSLzDAB1AQAAAA==.Denariah:BAAALgAECgMJAwABLgAECgcJHgAFAM4bAA==.Dendranaar:BAAALgAECgMJBAAAAA==.Dernen:BAABLgAECn8VAAMgAAgJeRG4EACZAQAgAAgJeRG4EACZAQAPAAIJ7ga8iwBLAAAAAA==.Derpnface:BAABLgAECn8UAAIiAAYJTg8PMwBXAQAiAAYJTg8PMwBXAQAAAA==.Desecration:BAABLgAECn8vAAICAAcJPySvJAAwAgACAAcJPySvJAAwAgABLgAECggJIgAjACUkAA==.Devilhandler:BAAALgADCgcJDgAAAA==.Devilsautho:BAAALgAECgUJDgAAAA==.Dezimorikko:BAAALgADCgcJBwAAAA==.',
Di='Dirgir:BAABLgAECn8rAAIhAAkJYSLvAwD2AgAhAAkJYSLvAwD2AgAAAA==.Disk:BAAALgAECggJCgAAAA==.Distonia:BAABLgAECn8nAAIjAAkJHxw3DgDXAgAjAAkJHxw3DgDXAgAAAA==.',
Do='Dorothy:BAACLgAFFH8QAAMTAAUJ2x5mCQA/AQATAAUJ1BVmCQA/AQABAAMJpRwccAATAQAuAAQKfyAAAgEACAkoHZVYALQBAAEACAkoHZVYALQBAAAA.',
Dr='Dracheo:BAACLgAFFH8cAAIJAAYJjxp/KgCrAQAJAAYJjxp/KgCrAQAuAAQKfzsAAgkACQkpIkoVANMCAAkACQkpIkoVANMCAAAA.Dragonbrr:BAAALgAECgUJDQABLgAECgcJGQAMAF8kAA==.Dragonwizard:BAABLgAECn8pAAIJAAcJKhwPWwDHAQAJAAcJKhwPWwDHAQAAAA==.Drakonna:BAAALgAECgYJDQAAAA==.Dranix:BAAALgAECgUJCwAAAA==.Draupaadi:BAAALgAECgUJBgAAAA==.Drazz:BAAALgAECgQJBAABLgAFFAIJAgAIAAAAAA==.Dreygur:BAABLgAECn8VAAIBAAkJKBfBLABEAgABAAkJKBfBLABEAgAAAA==.Droiden:BAABLgAECn8jAAIfAAkJPxAqRQDGAQAfAAkJPxAqRQDGAQAAAA==.Droidetté:BAABLgAECn8YAAIWAAcJhwbvSADZAAAWAAcJhwbvSADZAAAAAA==.Droidén:BAAALgAECgEJAQAAAA==.Drotar:BAABLgAECn89AAQWAAkJuBMpGQD2AQAWAAkJuBMpGQD2AQAGAAYJKAWkMACLAAAFAAEJtA1RbwAoAAAAAA==.Drovak:BAAALgAECgcJEAAAAA==.',
Du='Dumbdog:BAACLgAFFH8VAAIVAAQJeCNFFwCUAQAVAAQJeCNFFwCUAQAuAAQKfzYAAxUACQlgJYQDAFoDABUACQlgJYQDAFoDABYABgmaEx0+ADoBAAEuAAUUCAkpABoAjhsA.Dumichauch:BAACLgAFFH8YAAIVAAYJ2A4CGQCEAQAVAAYJ2A4CGQCEAQAuAAQKfzMAAhUACQmTG+4XAHcCABUACQmTG+4XAHcCAAAA.Durin:BAABLgAECn8nAAIKAAkJQBT3RwDjAQAKAAkJQBT3RwDjAQAAAA==.Duzzer:BAAALgADCgEJAQAAAA==.',
['Dé']='Déâth:BAAALgADCgkJCwAAAA==.',
Ec='Echo:BAAALgAECgcJCAAAAA==.',
Eg='Eggars:BAABLgAECn8jAAMHAAkJzwi5YwBzAQAHAAkJzwi5YwBzAQAXAAMJEgfXMABPAAAAAA==.',
Ek='Ekee:BAAALgAECgYJDwAAAA==.',
El='Elegance:BAAALgADCgIJAgAAAA==.Ellý:BAAALgADCgEJAQAAAA==.',
Em='Emberleaf:BAAALgADCgcJDgAAAA==.Emofriz:BAAALgAECgUJCQAAAA==.Emolate:BAACLgAFFH8FAAIHAAUJ4weSYAD1AAAHAAUJ4weSYAD1AAAuAAQKfyQAAgcACAneE3lHAL8BAAcACAneE3lHAL8BAAEuAAUUCAkpAB8AGiAA.',
En='Ensetrend:BAAALgAECgMJBQAAAA==.Enve:BAABLgAECn8iAAICAAkJVh86GwBnAgACAAkJVh86GwBnAgAAAA==.',
Er='Erentiumxus:BAAALgAECgEJBAAAAA==.Erso:BAAALgADCgcJBwAAAA==.Erunkies:BAAALgAECgEJAQAAAA==.',
Eu='Euforia:BAAALgAECgEJAQAAAA==.',
Ev='Evangelein:BAAALgAECgEJAQAAAA==.Evanorah:BAAALgAECgIJAgAAAA==.Eviltiger:BAACLgAFFH8FAAIfAAIJkRaVcACdAAAfAAIJkRaVcACdAAAuAAQKf0QAAx8ACQmeIz4HABwDAB8ACQmeIz4HABwDAB0ACQmdFXEKALkBAAAA.',
Ew='Ewik:BAABLgAECn8ZAAMaAAgJYRd7EgAYAgAaAAgJYRd7EgAYAgAbAAMJLA1FGgBxAAAAAA==.',
Ex='Excalìbur:BAAALgAECgQJBgABLgAECggJEAAIAAAAAA==.',
Ey='Eydor:BAAALgADCggJCAAAAA==.',
Fa='Faent:BAABLgAECn8cAAIkAAYJxhLFLQAfAQAkAAYJxhLFLQAfAQAAAA==.Falimonki:BAAALgAECgMJAwAAAA==.Falinora:BAACLgAFFH8ZAAMMAAYJBhuyDQDMAQAMAAYJBhuyDQDMAQAKAAEJrw7SpQBFAAAuAAQKfzUAAwwACQnFGqMiAAoCAAwACAltGaMiAAoCAAoACQnbF0V+AGYBAAAA.Famous:BAAALgAECgMJAwAAAA==.Fantasticfox:BAACLgAFFH8LAAMHAAQJBAVlZwDkAAAHAAQJBAVlZwDkAAANAAEJVAHHKQAuAAAuAAQKf0kAAwcACQncFSg1AP8BAAcACQncFSg1AP8BAA0ABAlJCkUyAO8AAAAA.',
Fe='Felbyte:BAAALgADCgMJAwAAAA==.Felixs:BAABLgAECn8VAAIXAAYJAxxODgBkAQAXAAYJAxxODgBkAQAAAA==.Fellhanded:BAAALgADCgcJBwAAAA==.Feloron:BAAALgAECgQJCgAAAA==.Feluria:BAAALgADCgYJBgAAAA==.Feodin:BAACLgAFFH8KAAIKAAQJ1RmbLQBGAQAKAAQJ1RmbLQBGAQAuAAQKfxgAAwoACQkQG1ZEAO4BAAoACQkQG1ZEAO4BAAQABQlADC8wAJkAAAAA.Feosdragon:BAAALgADCgYJBgAAAA==.Feraldank:BAAALgAECgIJBAAAAA==.Ferrovax:BAAALgADCgEJAQABLgAECggJGgACADYcAA==.',
Fi='Fistariir:BAAALgAFFAMJAwABLgAFFAYJGQAlAC8WAA==.Fitzchivalry:BAAALgAECgYJDQAAAA==.',
Fl='Flatsham:BAAALgAECgQJCAABLgAECgcJEwAIAAAAAA==.Fleethefield:BAAALgAECgYJEAAAAA==.Flowabridge:BAABLgAECn8WAAIJAAYJrwOvAgH2AAAJAAYJrwOvAgH2AAABLgAECgkJMgAWACUVAA==.',
Fo='Foomanchu:BAAALgAECgQJBAABLgAECggJFwADAAkMAA==.Forcewild:BAABLgAECn8hAAIFAAkJzRt8BgCHAgAFAAkJzRt8BgCHAgAAAA==.',
Fr='Fragos:BAAALgAECgYJBwAAAA==.Friz:BAACLgAFFH8MAAMNAAQJgQjwFAB8AAAHAAIJHAvangCCAAANAAMJqgfwFAB8AAAuAAQKfyYAAw0ACQmwHF4IADwCAA0ACAmIH14IADwCAAcABQkZF8qeABsBAAAA.Frostychunks:BAABLgAECn8hAAIJAAkJdRuXMABQAgAJAAkJdRuXMABQAgAAAA==.',
Fu='Fuddrucker:BAAALgAECgkJDgAAAA==.Furflation:BAABLgAECn8nAAMaAAkJWBf+BwBrAgAaAAkJWBf+BwBrAgAbAAYJWx1wCQCGAQAAAA==.Furgam:BAAALgAECgEJAQAAAA==.Fury:BAAALgADCgYJCgABLgAECgYJFgAPAAkXAA==.Fuzzychunks:BAABLgAECn8VAAMWAAYJSSLkKgBvAQAWAAUJ0iLkKgBvAQAVAAIJHh3VgwCnAAABLgAECgkJIQAJAHUbAA==.',
Ga='Gabapentin:BAABLgAECn8UAAMiAAgJsBYeHADBAQAiAAgJsBYeHADBAQAYAAMJ6BdDZgDGAAAAAA==.Gaeren:BAAALgADCgkJEwAAAA==.Gal:BAAALgAECgEJAwAAAA==.Galiron:BAAALgAECgYJBgABLgAECgkJMAAFAPofAA==.Gallenn:BAAALgAECgkJBgAAAA==.Gannon:BAABLgAECn8kAAIJAAgJWBzUTADuAQAJAAgJWBzUTADuAQAAAA==.Gano:BAEALgAECgUJCAABLgAFFAYJHAABAPIUAA==.Garr:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Garuuk:BAAALgAECgYJBgAAAA==.Gazir:BAABLgAECn8eAAMPAAkJexX+GwD0AQAPAAkJexX+GwD0AQAgAAMJzwvHKQCPAAAAAA==.',
Ge='Geniús:BAAALgADCgYJBgAAAA==.Genji:BAAALgAECgYJDQAAAA==.',
Gi='Giliandra:BAAALgADCggJFAAAAA==.Gingerbich:BAAALgAECgYJDAAAAA==.',
Gl='Glitch:BAACLgAFFH8LAAIZAAMJXwCrJQBUAAAZAAMJXwCrJQBUAAAuAAQKfykAAhkACQmoAlMqANYAABkACQmoAlMqANYAAAAA.',
Gn='Gnxs:BAAALgAECgQJCwAAAA==.',
Go='Goonthar:BAACLgAFFH8SAAIOAAUJyRbpGQA8AQAOAAUJyRbpGQA8AQAuAAQKfzUAAg4ACQlYITcKALkCAA4ACQlYITcKALkCAAAA.Gorethak:BAABLgAECn8XAAIBAAYJgBuLcgB3AQABAAYJgBuLcgB3AQAAAA==.',
Gr='Grannykul:BAAALgADCgEJAQAAAA==.Grindrage:BAAALgADCgEJAQAAAA==.Gripmedaddy:BAAALgAECgQJCAAAAA==.Grobble:BAAALgAECggJEQAAAA==.Grollgrr:BAABLgAECn8UAAIjAAcJ5hwLIABCAgAjAAcJ5hwLIABCAgAAAA==.Grompo:BAAALgAECgkJDAABLgAECgkJQgAHALkiAA==.Grompy:BAAALgAECgYJBgABLgAECgkJQgAHALkiAA==.Gruffbeard:BAAALgAECgIJAgABLgAECgYJDwAIAAAAAA==.',
Gu='Gunee:BAAALgADCgEJAQAAAA==.Gunghoiguana:BAAALgAECgYJDwAAAA==.',
Gy='Gyattso:BAAALgAECgcJDAAAAA==.Gyxx:BAABLgAFFH8TAAMKAAQJ4RYbOQAqAQAKAAQJ4RYbOQAqAQAMAAMJfxhsLgCwAAAAAA==.',
Ha='Haddice:BAABLgAECn8hAAIJAAgJPQr2iABfAQAJAAgJPQr2iABfAQAAAA==.Hafarti:BAAALgADCgUJBAAAAA==.Hairyteeth:BAAALgAECgUJDgAAAA==.Hajime:BAABLgAECn8iAAIlAAgJ0wnsLABjAQAlAAgJ0wnsLABjAQAAAA==.Halgrad:BAEALgAECgkJAQAAAA==.Hamburgers:BAAALgAECgEJAQAAAA==.Hansasperger:BAAALgAECgYJCQAAAA==.Harriedotter:BAAALgAECgMJBgAAAA==.Havárti:BAAALgADCgkJCQAAAA==.',
He='Heebiejeebie:BAACLgAFFH8PAAMHAAQJCw2DXAD/AAAHAAQJygqDXAD/AAAXAAEJCQxdIgBLAAAuAAQKf1wABBcACQlPHxwFAC0CAAcACQmqGuwjAEoCABcABwmEIBwFAC0CAA0AAglpC4NXAGgAAAAA.Hellaeus:BAABLgAECn9HAAIKAAkJIh0VGgCdAgAKAAkJIh0VGgCdAgAAAA==.Hellkun:BAAALgAECgEJAQAAAA==.Hellsong:BAAALgAECgYJBgAAAA==.Hephtoo:BAAALgAECgEJAQAAAA==.Heresjohnny:BAAALgAECgIJAgAAAA==.',
Hi='Hinatasan:BAAALgAECgEJAgAAAA==.Hira:BAAALgAECgUJBQAAAA==.Hisokä:BAABLgAECn9UAAIUAAkJixlEDABSAgAUAAkJixlEDABSAgAAAA==.',
Ho='Hoku:BAAALgAECgMJBAAAAA==.Holycreambar:BAABLgAECn80AAIKAAkJoB/5FAC8AgAKAAkJoB/5FAC8AgAAAA==.Holyjuan:BAAALgADCgkJEgAAAA==.Hoofsbane:BAAALgADCgcJBwAAAA==.',
Hu='Huntingale:BAAALgAECgMJAwAAAA==.Huntinshift:BAABLgAECn8iAAIfAAcJhAzHfAA4AQAfAAcJhAzHfAA4AQAAAA==.Huslangr:BAAALgADCgEJAQAAAA==.Huwn:BAAALgADCgQJBAAAAA==.',
Hy='Hygelak:BAABLgAECn8cAAIKAAcJmwcwxAD2AAAKAAcJmwcwxAD2AAAAAA==.Hypaxia:BAABLgAECn8ZAAMfAAcJYA0rdQBJAQAfAAcJYA0rdQBJAQAdAAYJtAd+HQC2AAABLgAECgYJFwAdAFkYAA==.',
Ib='Ibpowerline:BAAALgADCgYJBgAAAA==.',
Ic='Icethorn:BAAALgAECgIJAwABLgAECgYJCgAIAAAAAA==.',
Ig='Iggysmalls:BAABLgAECn8sAAMCAAkJSiKCBgAaAwACAAkJSiKCBgAaAwADAAYJThIhFAABAQAAAA==.',
Ii='Iidrizztdour:BAAALgADCgEJAQAAAA==.',
Il='Iluminaughti:BAAALgAECgcJCwAAAA==.',
Im='Immoc:BAACLgAFFH8bAAICAAYJ2BuSHgChAQACAAYJ2BuSHgChAQAuAAQKfy8AAwIACQl0HyohAIoCAAIACQl0HyohAIoCAAMAAQnrC542ACEAAAAA.',
In='Indy:BAABLgAECn8vAAIYAAkJExPTJgDZAQAYAAkJExPTJgDZAQAAAA==.Infidius:BAAALgADCggJEAAAAA==.Interés:BAAALgADCgQJBAAAAA==.Intodeep:BAAALgAECgkJDgAAAA==.Invocation:BAAALgAECgYJCAABLgAECggJIgAjACUkAA==.',
Io='Iownyourcow:BAAALgAECgIJAgAAAA==.',
Ip='Ip:BAAALgAFFAMJBAAAAA==.',
Ir='Iroha:BAAALgADCgYJBgAAAA==.Ironstag:BAAALgADCgQJBAAAAA==.',
Is='Istandalone:BAACLgAFFH8aAAMBAAYJISCTIgC/AQABAAUJISCTIgC/AQAhAAEJAAAZUAAAAAAuAAQKfxoAAgEACAm8Hy4hALwCAAEACAm8Hy4hALwCAAAA.',
Ix='Ixioth:BAAALgAECgEJAQAAAA==.',
Ja='Jaglok:BAAALgADCgEJAQAAAA==.Jagons:BAABLgAECn8dAAImAAgJ9AtzCwBwAQAmAAgJ9AtzCwBwAQAAAA==.Jahfar:BAAALgAECgYJDgAAAA==.Jaken:BAAALgAECgEJAgAAAA==.Janara:BAAALgAECgUJCgAAAA==.',
Je='Jehtadin:BAAALgAECgkJEQAAAA==.Jehthero:BAAALgAECgYJCgABLgAECgkJEQAIAAAAAA==.Jehtshot:BAABLgAECn8cAAMdAAgJkRz9FQCBAgAdAAgJkRz9FQCBAgAfAAMJ3hxYiADPAAABLgAECgkJEQAIAAAAAA==.Jehtword:BAAALgAECgMJAwABLgAECgkJEQAIAAAAAA==.Jemjemner:BAAALgAECgEJAQAAAA==.Jesy:BAAALgAECgYJDAABLgAFFAYJFgAfAMYXAA==.',
Ji='Jickson:BAAALgAECgEJAQAAAA==.Jimvisible:BAACLgAFFH8JAAIkAAMJBSSJHwATAQAkAAMJBSSJHwATAQAuAAQKfyIAAyQACQkqJtwAAHcDACQACQkqJtwAAHcDACYAAQm/JTkdAGgAAAAA.',
Jo='Joan:BAAALgAECgIJAgABLgAFFAQJDwAJAHsXAA==.Johadro:BAAALgADCgEJAQAAAA==.',
Jr='Jr:BAAALgAECgMJBAAAAA==.',
Ju='Judgejobrown:BAAALgAECggJEAAAAA==.Judgenawt:BAABLgAECn84AAIKAAkJwB69GAClAgAKAAkJwB69GAClAgAAAA==.Junon:BAAALgAECgUJCwAAAA==.',
Ka='Kahlanah:BAAALgAECggJDQAAAA==.Kain:BAABLgAECn81AAIHAAkJQhGhQQDSAQAHAAkJQhGhQQDSAQAAAA==.Kaiá:BAAALgADCgUJBQAAAA==.Kalegard:BAAALgADCgcJDgAAAA==.Kalerah:BAAALgADCgYJBgAAAA==.Kalis:BAABLgAECn8lAAIJAAgJWg9ohQBmAQAJAAgJWg9ohQBmAQAAAA==.Kalisara:BAAALgADCgUJBQABLgAECggJFgAVAMsUAA==.Kallum:BAABLgAECn8WAAIVAAgJyxT4NAC+AQAVAAgJyxT4NAC+AQAAAA==.Kaltak:BAAALgAECgIJAgAAAA==.Kalvynx:BAABLgAECn8hAAIYAAgJBRYXKwC/AQAYAAgJBRYXKwC/AQAAAA==.Karasu:BAAALgAECgQJBwAAAA==.Karn:BAABLgAECn8zAAIKAAkJJR7iGQCeAgAKAAkJJR7iGQCeAgAAAA==.Karti:BAAALgAECgQJCwAAAA==.Karzdormi:BAEALgAECgcJDAAAAA==.Karzen:BAEALgAECgkJCgABLgAECgcJDAAIAAAAAA==.Kathell:BAAALgAECgIJBAABLgAFFAYJFgAfAMYXAA==.Kaydie:BAAALgADCgYJBgABLgADCgkJFAAIAAAAAA==.Kaylly:BAAALgAECgQJBAABLgAECgkJPwAVAC8VAA==.Kayllynt:BAAALgADCgkJJAABLgAECgkJPwAVAC8VAA==.Kayyllynt:BAABLgAECn8/AAMVAAkJLxUKIAA9AgAVAAkJLxUKIAA9AgAWAAcJ2Q9YMgBDAQAAAA==.',
Ke='Kegeraetor:BAACLgAFFH8QAAILAAUJ5haFFQBiAQALAAUJ5haFFQBiAQAuAAQKfzAAAgsACQlTIpIXAOMBAAsACQlTIpIXAOMBAAAA.Keinthdra:BAACLgAFFH8RAAMhAAMJBRYPJgCtAAABAAMJkwlrpwC7AAAhAAMJ5BUPJgCtAAAuAAQKfz8AAyEACQkeIFIOABkCACEACQk0HVIOABkCAAEABQkxFseSADgBAAAA.Kelein:BAAALgAECgEJAQABLgAECggJEAAIAAAAAA==.Keliste:BAAALgAECgUJCQAAAA==.Kema:BAAALgAECgcJDgAAAA==.Kennaea:BAAALgAECgIJAgABLgAFFAYJHAAJAI8aAA==.Kervana:BAAALgAECgMJBAABLgAFFAYJGQAlAC8WAA==.',
Kh='Khrysais:BAAALgADCgMJAwAAAA==.Khyranni:BAAALgAECgIJBwAAAA==.',
Ki='Killigula:BAABLgAECn9JAAIOAAkJJRw7CwCrAgAOAAkJJRw7CwCrAgAAAA==.Kinks:BAAALgAECgYJCQAAAA==.Kinuye:BAAALgAECgQJDgAAAA==.Kishara:BAAALgAECgUJBQABLgAFFAYJFgAfAMYXAA==.Kiwi:BAAALgAECgIJAwAAAA==.',
Kl='Klondor:BAABLgAECn9IAAQfAAkJuxKeLQAbAgAfAAkJ8hGeLQAbAgAcAAkJwQm0HQCqAQAdAAIJxwF5fwBIAAAAAA==.Klutch:BAAALgADCgUJCAAAAA==.',
Ko='Kobato:BAAALgAECggJCAABLgAFFAQJDwAfAGYNAA==.Kohakuu:BAAALgADCgEJAQAAAA==.Korash:BAABLgAECn8VAAMHAAkJ+CHeaQBkAQAHAAcJ+iHeaQBkAQANAAIJ6CEcOwDIAAAAAA==.',
Kr='Kraio:BAABLgAECn8nAAIJAAgJ3BdNSgD2AQAJAAgJ3BdNSgD2AQAAAA==.Kraisa:BAAALgAECgIJAgAAAA==.Krak:BAAALgAECgEJAQAAAA==.Krakenbones:BAAALgAECgUJCwAAAA==.Krangu:BAAALgADCgcJBwAAAA==.Krenolarian:BAAALgADCgUJBQAAAA==.Kronax:BAAALgADCgQJBAAAAA==.',
Kv='Kvoke:BAAALgAECgIJCQAAAA==.',
La='Lamora:BAAALgAECgYJEwAAAA==.Lampard:BAABLgAECn8XAAIOAAgJoBIRQQCgAQAOAAgJoBIRQQCgAQAAAA==.Laraj:BAACLgAFFH8FAAIfAAMJNxHQVQDmAAAfAAMJNxHQVQDmAAAuAAQKfzIAAh8ACQmFIZQQAMICAB8ACQmFIZQQAMICAAAA.Larissaqt:BAEBLgAECn8eAAIEAAkJVRmbCgATAgAEAAkJVRmbCgATAgAAAA==.Lasmìnia:BAAALgAECgEJAQAAAA==.Latindk:BAAALgADCgMJAwAAAA==.Latinhunter:BAABLgAECn8VAAIfAAYJcg4jlQAIAQAfAAYJcg4jlQAIAQAAAA==.Latinmonk:BAAALgAECgUJCAAAAA==.Latinshamy:BAABLgAECn8ZAAIjAAYJYxjoSAB9AQAjAAYJYxjoSAB9AQAAAA==.Lavande:BAAALgAECgQJCgAAAA==.',
Le='Lealu:BAAALgAECgUJBAAAAA==.Leara:BAABLgAECn8VAAIjAAgJGxQoMwDYAQAjAAgJGxQoMwDYAQABLgAFFAYJFgAfAMYXAA==.Legochicken:BAAALgAECgkJCQAAAA==.Legomyagro:BAAALgAECggJEwAAAA==.Lehaya:BAAALgAECgEJAQAAAA==.Leiasolo:BAAALgAECgQJCAAAAA==.Leonaá:BAABLgAECn8cAAMVAAkJRCNNAwCJAwAVAAkJRCNNAwCJAwAGAAkJFBppBgBxAgABLgAFFAIJCAARAAwgAA==.Lewpysoup:BAAALgAECgkJAQABLgAFFAYJCQAWABwKAA==.',
Li='Lightfall:BAAALgAECgYJDAAAAA==.Lilbessy:BAABLgAECn8hAAIjAAgJ8gVXaAASAQAjAAgJ8gVXaAASAQAAAA==.Lishaliel:BAAALgADCgcJBwABLgAFFAYJFgAfAMYXAA==.Lizy:BAAALgADCgkJHAABLgAECgEJAQAIAAAAAA==.Lizzia:BAAALgADCgQJBAAAAA==.',
Lo='Longhealz:BAAALgAECgQJBwAAAA==.Loopysoup:BAAALgAECgEJAQABLgAFFAYJCQAWABwKAA==.Loopyswoop:BAAALgAECgcJEAABLgAFFAYJCQAWABwKAA==.Lothriel:BAABLgAECn8tAAITAAgJ2RfZAwA7AgATAAgJ2RfZAwA7AgAAAA==.',
Lu='Lucid:BAAALgAECgEJAQAAAA==.Ludioduo:BAAALgAECgUJBwAAAA==.Luedayen:BAABLgAECn8oAAMRAAkJBhvWDwBoAgARAAkJBhvWDwBoAgAeAAEJqgpQhAAuAAAAAA==.Lukesunwalkr:BAAALgAECgUJBQAAAA==.Lunabellz:BAABLgAECn8jAAIWAAgJLgqjOQAeAQAWAAgJLgqjOQAeAQAAAA==.Lunavia:BAABLgAECn8kAAIfAAkJGR9NEwCtAgAfAAkJGR9NEwCtAgAAAA==.Luxembourge:BAAALgAECgUJDgAAAA==.',
Ma='Maalgus:BAABLgAECn8bAAILAAgJMB1fDwA9AgALAAgJMB1fDwA9AgAAAA==.Maarajade:BAAALgAECgEJAQAAAA==.Mad:BAAALgAECgYJDQAAAA==.Madea:BAAALgAECgEJAQAAAA==.Magivyne:BAAALgAECgEJAQAAAA==.Mahota:BAAALgADCggJDwAAAA==.Makennah:BAAALgADCgcJBwAAAA==.Maladash:BAABLgAECn8eAAQCAAgJUBd/NAAnAgACAAgJUBd/NAAnAgADAAMJYwd/KwBJAAAUAAEJAgkXdAAxAAABLgAFFAQJCgAKANUZAA==.Malephar:BAAALgAECgUJBQAAAA==.Manachi:BAAALgAECgIJAgAAAA==.Margolem:BAAALgAECgYJBgAAAA==.Margoul:BAAALgAECgYJCQAAAA==.Massfootmen:BAAALgADCgUJBQAAAA==.Matiowen:BAAALgADCgMJAwAAAA==.Mauie:BAAALgADCgEJAQAAAA==.Mayyhem:BAACLgAFFH8pAAIaAAgJjhtJAgDFAgAaAAgJjhtJAgDFAgAuAAQKfzIAAxoACQkNI3kBAG8DABoACQkNI3kBAG8DABsAAgnfGegvAJgAAAAA.Mazrethil:BAAALgADCgEJAQAAAA==.',
Mc='Mcallister:BAABLgAECn9BAAMVAAkJwB2sDQDkAgAVAAkJwB2sDQDkAgAWAAQJNxftOwASAQABLgAECgEJAQAIAAAAAA==.Mcjudgin:BAABLgAECn8bAAQEAAgJZiXeAABnAwAEAAgJZiXeAABnAwAMAAMJSxVOYACmAAAKAAEJCh1YLAFIAAABLgAECgkJJAAFAKsmAA==.Mcsquid:BAAALgAECgEJAQAAAA==.',
Md='Mdrakeyd:BAABLgAECn8XAAICAAYJkRcUcwAvAQACAAYJkRcUcwAvAQAAAA==.',
Me='Meatbubble:BAAALgADCgkJFAAAAA==.Mechee:BAABLgAECn8bAAMYAAkJJRrCDQCxAgAYAAkJJRrCDQCxAgAiAAQJaQ5iTgC+AAAAAA==.Mephisston:BAAALgADCgIJAgAAAA==.Mesasneaky:BAAALgAECgUJBQAAAA==.',
Mi='Mimi:BAAALgAECgMJAwAAAA==.Mimiker:BAACLgAFFH8UAAISAAYJmxSkGgBtAQASAAYJmxSkGgBtAQAuAAQKfzcABBIACQk/HXUNAJ4CABIACQk/HXUNAJ4CABsABwkPF3MSALoBABoABAmzD0ElALgAAAAA.Minime:BAACLgAFFH8MAAIfAAQJpyHBFgCVAQAfAAQJpyHBFgCVAQAuAAQKfx4AAx8ACQnZJOoCAF0DAB8ACQnZJOoCAF0DAB0ABQkbG1s4AIMBAAEuAAUUCAkpAB8AGiAA.Minininja:BAAALgADCgcJDAABLgAECgQJEgAIAAAAAA==.Miniobi:BAAALgAECgYJDgAAAA==.Mirabella:BAABLgAECn8dAAIeAAgJegcSOwAdAQAeAAgJegcSOwAdAQAAAA==.Miriell:BAAALgADCgYJDAAAAA==.Mistdemeanor:BAAALgAECgEJAgAAAA==.Mizahella:BAAALgAECgYJDAAAAA==.',
Mo='Mofassa:BAAALgAECgEJAQAAAA==.Mokei:BAAALgAECgQJBQAAAA==.Mokushi:BAAALgAECgYJDQAAAA==.Mollie:BAAALgADCgcJBwABLgADCgkJFAAIAAAAAA==.Mondragore:BAAALgAECgQJBAAAAA==.Monkgruff:BAAALgAECgYJDwAAAA==.Monkèy:BAAALgADCgUJBQAAAA==.Moonsilver:BAABLgAECn8bAAMOAAgJnxFOLACbAQAOAAgJ6BBOLACbAQAZAAUJ0xAPNwCNAAAAAA==.Moriko:BAACLgAFFH8PAAIfAAQJZg0EQAAhAQAfAAQJZg0EQAAhAQAuAAQKfzYAAh8ACQnTHAAWAIgCAB8ACQnTHAAWAIgCAAAA.Mornak:BAAALgAECgkJCAAAAA==.Mourn:BAAALgAFFAIJAwABLgAFFAUJEAALAOYWAA==.',
Mu='Mudstomper:BAAALgAECggJCAABLgAFFAQJDwAfAGYNAA==.Muertomarrow:BAAALgAECgcJDwAAAA==.Mulroth:BAAALgAECgQJBAAAAA==.Murdermitten:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Murloc:BAAALgAECgYJCgAAAA==.Musasa:BAABLgAECn8kAAIVAAgJphmtIAA+AgAVAAgJphmtIAA+AgAAAA==.Mustardseed:BAABLgAECn81AAIHAAkJsRE9QADWAQAHAAkJsRE9QADWAQAAAA==.Muxaro:BAAALgAECgQJCwAAAA==.',
My='Myme:BAAALgAECgEJAQABLgAECgcJFwASAH8OAA==.',
['Mí']='Mísery:BAAALgAECgYJDQAAAA==.',
Na='Naked:BAAALgAECgIJAwAAAA==.Naliannagoat:BAAALgADCgEJAQAAAA==.Nalibeefcake:BAAALgADCgcJDQAAAA==.Narkoleptick:BAAALgAECgYJCQAAAA==.Narkoleptik:BAAALgAFFAQJBAAAAA==.Nasrith:BAABLgAECn8yAAIKAAkJyR18GQChAgAKAAkJyR18GQChAgAAAA==.Nastro:BAAALgAECgYJDQAAAA==.Naughtica:BAAALgAECgUJDAABLgAECgcJCwAIAAAAAA==.Nawtishot:BAAALgADCgEJAQAAAA==.Nazanath:BAAALgAECgIJAgAAAA==.',
Ne='Neeb:BAABLgAECn8gAAIEAAgJzRnuDQDXAQAEAAgJzRnuDQDXAQAAAA==.Neeber:BAABLgAECn8UAAMOAAUJrxbwUgD0AAAOAAQJfRLwUgD0AAAZAAUJtRWgLwC1AAAAAA==.Neebtacular:BAAALgAECgEJAQAAAA==.Nekk:BAABLgAECn8nAAIZAAkJcx3FBwB3AgAZAAkJcx3FBwB3AgAAAA==.',
Ni='Niamyau:BAAALgADCgMJAwAAAA==.Ninick:BAAALgAECgEJAQAAAA==.Niraleth:BAAALgAECgcJEAAAAA==.Nitebrite:BAABLgAECn8bAAIRAAYJ4hKyNAAiAQARAAYJ4hKyNAAiAQAAAA==.',
No='Noatak:BAAALgAECgEJAgAAAA==.Nohozis:BAAALgADCgQJBAAAAA==.Noimia:BAACLgAFFH8MAAIYAAQJ7R9RGwBrAQAYAAQJ7R9RGwBrAQAuAAQKfzMAAhgACQkLHjEMAMYCABgACQkLHjEMAMYCAAAA.Noraina:BAAALgADCgEJAQAAAA==.Normanosborn:BAAALgAECgQJCgAAAA==.',
Ny='Nyquiil:BAAALgAECgUJBwAAAA==.Nyssil:BAAALgADCgcJCwAAAA==.',
['Né']='Nésa:BAAALgAECgMJAwAAAA==.',
['Nï']='Nïssan:BAAALgAECggJEgAAAA==.',
Ob='Obscûr:BAABLgAECn8XAAQCAAYJfxGckwDrAAACAAUJxQ2ckwDrAAAUAAUJHg0LPQCwAAADAAEJWCHsJgBdAAAAAA==.',
Oc='Ochtli:BAAALgADCgUJBQAAAA==.',
Od='Oden:BAABLgAECn8jAAIPAAkJDhyPCwCeAgAPAAkJDhyPCwCeAgAAAA==.',
Og='Oggy:BAAALgAECgIJAgAAAA==.',
Ok='Oksanabaiul:BAABLgAECn8ZAAIPAAUJ5R5zNgBQAQAPAAUJ5R5zNgBQAQABLgAFFAYJFwAHABQeAA==.',
Ol='Oldcode:BAAALgAECgUJCgAAAA==.Oleyander:BAAALgAECgcJEQAAAA==.Olskigather:BAAALgADCgMJAwAAAA==.Olskimonk:BAAALgAECgYJCwABLgAECgcJBwAIAAAAAA==.',
Om='Omgitsashami:BAAALgAECgYJBgAAAA==.',
Or='Orondrean:BAAALgADCgEJAQAAAA==.Oronin:BAAALgAECgQJBQAAAA==.',
Os='Osanyin:BAAALgAECgcJEgAAAA==.',
Ot='Otsuka:BAAALgADCgEJAQAAAA==.',
Pa='Pacoesfu:BAAALgADCgcJBgAAAA==.Padray:BAACLgAFFH8bAAIeAAYJPhP5DQBuAQAeAAYJPhP5DQBuAQAuAAQKf08AAh4ACQnVHiUKAKgCAB4ACQnVHiUKAKgCAAAA.Paecos:BAAALgADCgYJDQAAAA==.Palize:BAAALgADCgcJFQABLgAECgcJGgAaAGMZAA==.Pandamnation:BAAALgAFFAMJAwABLgAFFAUJDQAjAFAXAQ==.Panhia:BAAALgAECgQJEgAAAA==.Parliament:BAAALgAECgYJCwAAAA==.',
Pe='Pecoes:BAAALgADCgUJBQAAAA==.Pekoyami:BAAALgADCgUJBQAAAA==.Pen:BAABLgAECn8yAAIWAAkJJRW0GQDyAQAWAAkJJRW0GQDyAQAAAA==.Pennyflame:BAAALgAECgEJAQAAAA==.Pepenlock:BAAALgAECgQJBQAAAA==.Pepperbottom:BAABLgAECn8mAAMNAAgJkhtDDwDYAQANAAgJnRlDDwDYAQAHAAYJ0BFMaQBlAQAAAA==.Perforation:BAAALgAECggJEAABLgAECggJIgAjACUkAA==.',
Pf='Pfft:BAABLgAECn8WAAIPAAYJCRdBNwBMAQAPAAYJCRdBNwBMAQAAAA==.',
Ph='Phantasmshot:BAABLgAECn84AAIfAAgJMREoUQCiAQAfAAgJMREoUQCiAQAAAA==.Phoebere:BAAALgAECgYJDQAAAA==.Phung:BAAALgAECgkJDgAAAA==.Phungi:BAAALgAECgYJDAAAAA==.',
Po='Polymnia:BAAALgAECgUJDAAAAA==.Pomelo:BAABLgAECn8UAAIKAAYJbhoFcQCBAQAKAAYJbhoFcQCBAQAAAA==.Popeums:BAABLgAECn8nAAMlAAkJmwaJRgDbAAAlAAcJlAKJRgDbAAARAAYJbAiCRADJAAAAAA==.Poplock:BAAALgADCgYJBgAAAA==.Poppiqt:BAABLgAECn8hAAIYAAkJFBR9IAAEAgAYAAkJFBR9IAAEAgAAAA==.Powlie:BAAALgAECgMJAwAAAA==.Poyoh:BAABLgAECn8yAAIVAAkJ1hv0EgCsAgAVAAkJ1hv0EgCsAgAAAA==.',
Pr='Pravoce:BAABLgAECn8aAAMeAAgJmA0CLABuAQAeAAgJmA0CLABuAQAlAAUJ9wtzQgDwAAAAAA==.Prolifichd:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Prufrock:BAAALgADCgYJBgAAAA==.',
['Pí']='Pínt:BAABLgAECn8nAAMfAAkJHCQ4BwAdAwAfAAkJMiM4BwAdAwAcAAYJtB7SDgDZAQAAAA==.',
Qu='Quelissa:BAAALgADCgkJCQABLgAECggJFAAjAKwUAA==.',
Ra='Radjason:BAAALgADCggJCQAAAA==.Raeagald:BAABLgAFFH8MAAIZAAUJiCHpCQB2AQAZAAUJiCHpCQB2AQABLgAFFAUJEAALAOYWAA==.Raelyni:BAABLgAECn83AAIRAAkJ+hu2CwCeAgARAAkJ+hu2CwCeAgAAAA==.Rafael:BAAALgADCgMJAwAAAA==.Rageroyal:BAAALgADCgEJAQAAAA==.Rahum:BAAALgAECgQJBwAAAA==.Rakkah:BAABLgAECn8iAAMfAAgJGRMfWwCHAQAfAAgJIxEfWwCHAQAdAAYJaQlRTgAXAQAAAA==.Rakkuh:BAAALgAECgQJBAAAAA==.Ramjam:BAAALgADCgYJCQAAAA==.Ranann:BAAALgAECgQJBAAAAA==.Rangwashu:BAAALgAECgYJDgABLgAECggJFQAgAHkRAA==.Raveniss:BAABLgAECn8dAAIWAAgJuAefPAAPAQAWAAgJuAefPAAPAQAAAA==.Rawrie:BAABLgAECn8oAAMPAAkJtgewOwA3AQAPAAkJtgewOwA3AQAjAAMJsglogwCGAAAAAA==.Raygun:BAABLgAECn8oAAIJAAcJbRJJhwBiAQAJAAcJbRJJhwBiAQABLgAECgEJAQAIAAAAAA==.Rayzorevoker:BAAALgADCgcJDQAAAA==.Raziell:BAAALgADCgMJAwAAAA==.',
Re='Redhilda:BAABLgAECn8hAAIPAAcJQQrxSgD5AAAPAAcJQQrxSgD5AAAAAA==.Redmayhem:BAAALgADCgYJBgAAAA==.Remygos:BAAALgADCgEJAQAAAA==.',
Rh='Rhymu:BAAALgAECgYJCgAAAA==.',
Ri='Risperian:BAAALgAECgkJCQAAAA==.Rissaria:BAAALgAECgIJAgAAAA==.',
Ro='Roshelle:BAAALgAECgIJAgAAAA==.Rotation:BAABLgAECn8XAAQDAAgJCQy6FgDgAAADAAYJMA66FgDgAAAUAAQJQgZpWACEAAACAAMJ9gVh2gBsAAAAAA==.Rotblade:BAABLgAECn8aAAInAAkJ2BdOCACmAQAnAAkJ2BdOCACmAQAAAA==.',
Ru='Rudewenn:BAAALgAECgYJDwAAAA==.Runandhide:BAABLgAECn8VAAIJAAYJmhDXuQBuAQAJAAYJmhDXuQBuAQAAAA==.',
Ry='Ryllativity:BAAALgADCgEJAQAAAA==.',
['Ró']='Rógue:BAAALgAECgQJCgABLgAECgUJCgAIAAAAAA==.',
['Rø']='Røøtsftw:BAAALgAECgYJBgAAAA==.',
Sa='Sadsnap:BAABLgAECn8ZAAIgAAcJxyBECQBFAgAgAAcJxyBECQBFAgAAAA==.Safetybear:BAABLgAECn8kAAIFAAkJqyY3AACHAwAFAAkJqyY3AACHAwAAAA==.Salamender:BAACLgAFFH8WAAIaAAYJ0RJjDgCdAQAaAAYJ0RJjDgCdAQAuAAQKfy0AAhoACQkEHA8FAMQCABoACQkEHA8FAMQCAAAA.Sapheer:BAABLgAECn8XAAIeAAkJPAoqLQBnAQAeAAkJPAoqLQBnAQAAAA==.Sargothys:BAAALgAECgIJAgAAAA==.Sariais:BAAALgAECgEJAQAAAA==.Sassymoo:BAACLgAFFH8LAAIVAAQJOA26LQD2AAAVAAQJOA26LQD2AAAuAAQKfyUAAxUABwkNHygaAGsCABUABwkNHygaAGsCAAUAAQmPBME6ABEAAAEuAAUUBQkNACMAUBcA.Sathenoth:BAAALgADCggJCAAAAA==.Satraa:BAAALgAECgUJBQABLgAFFAIJCAARAAwgAA==.Savagejoker:BAAALgAECgEJAQABLgAECggJIQAoAL4iAA==.Sañtoro:BAAALgAECgQJDQAAAA==.',
Sc='Scalesboi:BAAALgADCgMJAwAAAA==.Scipione:BAAALgAECgYJEQAAAA==.Scy:BAABLgAECn8aAAMfAAgJBg0fXwB9AQAfAAgJ2QwfXwB9AQAdAAMJjwW3LABcAAAAAA==.',
Se='Seddona:BAAALgADCgkJCQAAAA==.Seithe:BAAALgAECgEJAgAAAA==.Seluun:BAABLgAECn8lAAIJAAYJyRKrpwAqAQAJAAYJyRKrpwAqAQAAAA==.Semandemon:BAAALgAECgEJAwAAAA==.Sephandrius:BAAALgADCgEJAQABLgAECggJFQAgAHkRAA==.Seraphae:BAABLgAECn8ZAAMRAAgJkg9iKAB2AQARAAgJkw5iKAB2AQAlAAYJ0gz+NgAqAQAAAA==.',
Sh='Shadowmorn:BAABLgAECn8vAAIPAAkJVAZcQgAaAQAPAAkJVAZcQgAaAQAAAA==.Shalako:BAAALgAECgIJAwAAAA==.Shambali:BAAALgAECgcJBwAAAA==.Shamidozz:BAAALgAECgQJBQABLgAECgcJKAAMAFcWAA==.Shamnistic:BAABLgAECn8iAAMgAAkJrh+DBgBkAgAgAAkJrh+DBgBkAgAjAAEJyg0M0QAqAAAAAA==.Shandro:BAABLgAECn8tAAIJAAkJfgvUaQChAQAJAAkJfgvUaQChAQAAAA==.Shaniallon:BAABLgAECn8tAAMfAAkJNxEBQQDTAQAfAAkJExEBQQDTAQAdAAcJdwuFFQABAQAAAA==.Shara:BAAALgADCgMJBgAAAA==.Sharana:BAAALgADCggJDQAAAA==.Shaunï:BAABLgAECn8bAAIfAAgJiiDOFgCTAgAfAAgJiiDOFgCTAgAAAA==.Sheriff:BAAALgAECgEJAQAAAA==.Shieldman:BAAALgADCgMJAwAAAA==.Shiftylock:BAABLgAECn8eAAMFAAcJzhvzGQBsAQAFAAYJKhzzGQBsAQAGAAQJSRcFIgDKAAAAAA==.Shine:BAAALgAECgMJAwAAAA==.Showong:BAAALgAECgEJAQAAAA==.',
Si='Silius:BAAALgAECgUJDAAAAA==.Simoncrunch:BAAALgAECgEJBQAAAA==.Sin:BAAALgAECgEJAQABLgAECgEJAwAIAAAAAA==.Sinomen:BAACLgAFFH8NAAIgAAUJdRxwBQBWAQAgAAUJdRxwBQBWAQAuAAQKf0AAAiAACQnOJT8AAIEDACAACQnOJT8AAIEDAAEuAAUUCAkVABIALRcA.Sinzilla:BAAALgAECgYJDQAAAA==.Sizzen:BAAALgADCgkJCQAAAA==.',
Sk='Skunkdrunk:BAAALgADCgYJBwAAAA==.Skyblue:BAAALgAECgcJEwAAAA==.',
Sm='Smokebull:BAABLgAECn8aAAIOAAgJgArCPABKAQAOAAgJgArCPABKAQAAAA==.Smolcat:BAAALgAECgQJBAABLgAFFAgJKQAaAI4bAA==.',
Sn='Sneeble:BAAALgADCgkJCQAAAA==.Snoopshaman:BAAALgAECgEJAgABLgAECgkJJAAFAKsmAA==.Snowcake:BAAALgAECgEJBwAAAA==.Snowdayz:BAAALgADCgQJBAAAAA==.',
So='Sofiavers:BAAALgAECgQJBAAAAA==.Solarhoof:BAAALgADCgEJAQAAAA==.Sonarak:BAAALgAECgEJAQABLgAECgkJJAAFAKsmAA==.Sornafayne:BAAALgAECgYJDAAAAA==.Sorrengail:BAABLgAECn8fAAIjAAgJ6yDIDgDSAgAjAAgJ6yDIDgDSAgAAAA==.Soulvamp:BAAALgADCgUJBQAAAA==.',
Sp='Spareme:BAAALgAECgQJCAABLgAECgkJDgAIAAAAAA==.Specialkidd:BAAALgAECgkJDwABLgAECgkJJAAPAP8eAA==.Springrollz:BAAALgAECggJEAABLgAFFAgJKQAfABogAA==.Spy:BAABLgAECn81AAIfAAkJCh9OEwCtAgAfAAkJCh9OEwCtAgAAAA==.',
Sr='Sravoz:BAAALgAECgYJCQAAAA==.',
St='Stabbitha:BAAALgADCgkJHAAAAA==.Stampa:BAAALgAECgQJBwAAAA==.Starrie:BAABLgAECn9EAAMjAAkJxhDmPACsAQAjAAkJxhDmPACsAQAPAAgJbgtQQAAiAQAAAA==.Steaknshake:BAAALgAECgYJCgAAAA==.Steelhoof:BAACLgAFFH8PAAIdAAQJkwMuGADeAAAdAAQJkwMuGADeAAAuAAQKf0YAAh0ACQnrEZUJAM8BAB0ACQnrEZUJAM8BAAAA.Steil:BAAALgAECgYJCwAAAA==.Steponmyface:BAABLgAECn81AAMTAAkJOCEABQBcAgABAAgJIyKVIQB5AgATAAkJ4hkABQBcAgAAAA==.Stewie:BAAALgADCgcJCgABLgADCgkJFAAIAAAAAA==.Stonesoul:BAABLgAECn8hAAMjAAkJgRqmEQC1AgAjAAkJgRqmEQC1AgAPAAEJ3wvNpAApAAAAAA==.Stories:BAABLgAECn8VAAIJAAYJ0BhmoACWAQAJAAYJ0BhmoACWAQABLgAECggJEAAIAAAAAA==.Storm:BAEALgAECgYJCgABLgAFFAYJHAABAPIUAA==.Stormfury:BAAALgAECgEJAwAAAA==.Strongheart:BAAALgADCgkJGAABLgAECgYJFgAPAAkXAA==.Strucker:BAAALgADCgcJCwABLgAECgkJMgALAJQgAA==.Struckerdots:BAAALgAECgQJBAABLgAECgkJMgALAJQgAA==.Struckerz:BAAALgADCgkJEAABLgAECgkJMgALAJQgAA==.Struckerzz:BAAALgAECgQJBwAAAA==.Struckrucker:BAABLgAECn8yAAILAAkJlCD1BQDWAgALAAkJlCD1BQDWAgAAAA==.Stygian:BAAALgAECgEJAQAAAA==.',
Su='Succubussi:BAAALgAECgcJDgAAAA==.Sudimmoc:BAAALgAECgIJAgAAAA==.Sugarbear:BAAALgADCgUJBQAAAA==.Sushie:BAAALgADCgMJAwABLgAFFAcJEwAMAH0TAA==.',
Sv='Svikja:BAAALgAECgQJBwAAAA==.',
Sw='Swipe:BAAALgAECgcJEAAAAA==.',
Sy='Synn:BAAALgAECgYJCAAAAA==.Syvina:BAABLgAECn8WAAIlAAYJIgkGPgAGAQAlAAYJIgkGPgAGAQAAAA==.',
Ta='Tabby:BAAALgAECgMJBgAAAA==.Taconight:BAABLgAECn8dAAIRAAcJGAe9PwDhAAARAAcJGAe9PwDhAAAAAA==.Tacosaladin:BAAALgADCggJCAAAAA==.Tag:BAAALgAECgYJCAAAAA==.Takyon:BAAALgADCgYJBgABLgAECggJFgABALcjAA==.Tallynz:BAABLgAECn8lAAIRAAkJYBd4DwBiAgARAAkJYBd4DwBiAgAAAA==.Tankornot:BAACLgAFFH8FAAIKAAMJ8iIkbQDEAAAKAAMJ8iIkbQDEAAAuAAQKfxcAAgoABQlmIDBVAMABAAoABQlmIDBVAMABAAAA.Tarasque:BAAALgAECgEJAQABLgAECgEJBwAIAAAAAA==.Tarlgreyhair:BAAALgAECgYJDQAAAA==.Tarnished:BAABLgAECn8dAAIJAAkJwwK+xwD4AAAJAAkJwwK+xwD4AAAAAA==.Tarr:BAABLgAECn8eAAIKAAgJzxj4RQDpAQAKAAgJzxj4RQDpAQAAAA==.Tateerfel:BAABLgAECn8pAAQCAAgJDyIEFwCCAgACAAgJnCEEFwCCAgAUAAYJBxt/GwCRAQADAAMJTR8eEwAPAQAAAA==.Tateertot:BAAALgAECgEJAwABLgAECggJKQACAA8iAA==.Tawneestone:BAABLgAECn9LAAIZAAkJACapAABqAwAZAAkJACapAABqAwAAAA==.',
Te='Teedizzle:BAAALgAECggJEwAAAA==.Teek:BAABLgAECn8YAAMXAAYJwAQXFQDfAAAXAAYJnAIXFQDfAAAHAAYJwASBxgC7AAAAAA==.Telandaraa:BAACLgAFFH8IAAIRAAIJDCAfHwCsAAARAAIJDCAfHwCsAAAuAAQKfy8AAxEACQkpJLoBAF0DABEACQkpJLoBAF0DACUAAwkWCfxEAJEAAAAA.Telrae:BAABLgAECn81AAIHAAkJ8SGnCwDsAgAHAAkJ8SGnCwDsAgAAAA==.',
Th='Theb:BAABLgAECn8ZAAICAAkJihCcPwC+AQACAAkJihCcPwC+AQAAAA==.Thechase:BAAALgAECgYJBgABLgAECgkJLwAGAMofAA==.Thedenny:BAAALgADCgMJAwAAAA==.Thederpb:BAAALgAECggJEQAAAA==.Thejuice:BAAALgADCgcJDwAAAA==.Theldara:BAACLgAFFH8WAAIfAAYJxhfMEwCjAQAfAAYJxhfMEwCjAQAuAAQKfzEAAx8ACQleIUQpABICAB8ACQleIUQpABICAB0ABgkTFlk7AHMBAAAA.Themock:BAABLgAECn8WAAMWAAYJoRKPRQDnAAAWAAQJrBGPRQDnAAAVAAMJawKCzgAvAAAAAA==.Thereaper:BAAALgAECgMJAwAAAA==.Theresjohnny:BAAALgADCgkJGwAAAA==.Thesentinel:BAAALgAECgEJAQABLgAECgYJFgAPAAkXAA==.Theshift:BAABLgAECn8/AAIlAAkJVR0uBgAVAwAlAAkJVR0uBgAVAwAAAA==.Thesixtyone:BAAALgADCgcJBwAAAA==.Thino:BAAALgAECgMJAwAAAA==.Thisisjustin:BAABLgAECn8mAAIpAAkJWh6qAQBvAgApAAkJWh6qAQBvAgAAAA==.Thoreen:BAAALgAECgUJCwAAAA==.Thotsnprayer:BAAALgADCgMJBAAAAA==.Thraiel:BAAALgADCgQJBAABLgAECgUJDgAIAAAAAA==.Thrish:BAACLgAFFH8ZAAMcAAUJERWIEQAvAQAcAAUJyBKIEQAvAQAfAAQJow0xRQATAQAuAAQKfzYABB8ACQmSHu8cAFgCAB8ACAm7Ge8cAFgCABwABgn/HsQcALIBAB0AAQkFAoiYAB4AAAAA.Throom:BAAALgADCgIJAgAAAA==.Thuggies:BAABLgAECn8bAAIkAAgJmxwwDwArAgAkAAgJmxwwDwArAgAAAA==.Thunderfist:BAAALgAECgYJDQABLgAFFAQJCgAKANUZAA==.',
Ti='Tizzlerizzle:BAAALgAECgQJCwAAAA==.',
To='Tomacco:BAAALgADCggJEgAAAA==.Toreto:BAAALgADCgUJBwAAAA==.Toshi:BAAALgAECgQJBwAAAA==.Totemiclord:BAABLgAECn8zAAMPAAkJ7RIpHgDjAQAPAAkJ7RIpHgDjAQAjAAcJGQc7bgABAQAAAA==.',
Ts='Tsukiyami:BAAALgAECgUJDwABLgAECggJGwAfAIogAA==.',
Tw='Twixaldo:BAAALgAECgQJBgABLgAECgkJNAAKAKAfAA==.Twixiepaw:BAAALgAECgYJBgABLgAECgkJNAAKAKAfAA==.',
Ty='Ty:BAAALgADCgEJAQAAAA==.Tylus:BAAALgAECgQJBQAAAA==.',
Ub='Ubpriest:BAAALgAECgQJBwAAAA==.',
Up='Upinya:BAABLgAECn8YAAMNAAkJSArREgARAQANAAkJSArREgARAQAHAAEJ+QCnMgEcAAAAAA==.',
Ut='Uthrob:BAAALgADCgkJCQAAAA==.',
Uz='Uzumaki:BAAALgAECgQJBAAAAA==.',
Va='Vadderung:BAABLgAECn8aAAICAAgJNhyXKgBWAgACAAgJNhyXKgBWAgAAAA==.Vaelenth:BAAALgAECgEJAQAAAA==.Valera:BAAALgAECgYJCwABLgAFFAQJDAAQALojAA==.Valkilmer:BAAALgADCgEJAQAAAA==.Vallasha:BAABLgAECn8vAAIXAAgJqxJiCgCoAQAXAAgJqxJiCgCoAQAAAA==.Valoth:BAAALgADCgEJAQAAAA==.Valtures:BAAALgAECgMJCAAAAA==.Vampyre:BAACLgAFFH8NAAIfAAUJqRk+NAA6AQAfAAUJqRk+NAA6AQAuAAQKfykAAh8ACQmoII0NANsCAB8ACQmoII0NANsCAAAA.Vayne:BAACLgAFFH8aAAIOAAYJPB35CwCTAQAOAAYJPB35CwCTAQAuAAQKfzUAAw4ACQnnJL8RAMICAA4ACQnnJL8RAMICABAAAQksEwdBADYAAAAA.',
Ve='Vejek:BAAALgAECgkJCwAAAA==.Veloistina:BAAALgAECgEJAQABLgAECgkJNAAKAKAfAA==.Veloria:BAAALgAECgEJAwAAAA==.Venator:BAAALgADCgQJBAAAAA==.',
Vh='Vh:BAAALgAECgQJCAAAAA==.',
Vi='Videlle:BAAALgADCgMJAwAAAA==.Vieoree:BAAALgAECgUJDAAAAA==.Vigoh:BAAALgADCgcJBwABLgAECgcJFwASAH8OAA==.Vinge:BAECLgAFFH8cAAIBAAYJ8hSqLQCTAQABAAYJ8hSqLQCTAQAuAAQKfzMAAgEACQmLIuotAIECAAEACQmLIuotAIECAAAA.Vinter:BAAALgAECgcJBwAAAA==.Violetferal:BAAALgADCgkJIQAAAA==.Violetrain:BAABLgAECn8iAAIKAAcJKQRf7QDAAAAKAAcJKQRf7QDAAAAAAA==.Violetxx:BAAALgAECgYJBgAAAA==.Viral:BAAALgAECgYJBwAAAA==.Viralswine:BAAALgAECgcJCgAAAA==.Visarys:BAAALgAECgQJBAAAAA==.Vixipixi:BAAALgADCgYJEgAAAA==.',
Vo='Vollibear:BAAALgAECgMJAwAAAA==.Voltaic:BAABLgAECn8iAAIjAAgJJSRLDQDhAgAjAAgJJSRLDQDhAgAAAA==.Vothdomosh:BAAALgAECgUJBQABLgAECgcJGQAMAF8kAA==.',
Vr='Vraylaros:BAABLgAECn8aAAIjAAkJhREMLwDsAQAjAAkJhREMLwDsAQAAAA==.',
Vy='Vyrista:BAABLgAECn8ZAAIUAAcJchFrJABCAQAUAAcJchFrJABCAQAAAA==.Vyrzeth:BAAALgAECgYJDAAAAA==.Vyzual:BAAALgAECgYJBgABLgAFFAcJFgAMAD8SAA==.Vyzualize:BAACLgAFFH8WAAIMAAcJPxKFBACYAQAMAAcJPxKFBACYAQAuAAQKfy0AAgwACQl0IKoHAPICAAwACQl0IKoHAPICAAAA.',
Wa='Wae:BAACLgAFFH8MAAIhAAYJ1RqfDACTAQAhAAYJ1RqfDACTAQAuAAQKfxkAAiEACQmLHsUJAG0CACEACQmLHsUJAG0CAAAA.Waferblade:BAAALgADCgcJBwAAAA==.Waknipi:BAABLgAECn8kAAMKAAkJcxzEJwBZAgAKAAkJcxzEJwBZAgAMAAEJIQUEnAAtAAAAAA==.Wauwen:BAAALgAECgEJAQAAAA==.Wavecheck:BAAALgAECgMJBQAAAA==.Way:BAAALgAECgIJAgAAAA==.Waycaps:BAACLgAFFH8QAAIDAAQJBx/7AgBZAQADAAQJBx/7AgBZAQAuAAQKfy0AAgMACAk2I9ABAPgCAAMACAk2I9ABAPgCAAAA.Wayfairinc:BAAALgAECgcJCgABLgAECgkJOQAZABQiAA==.',
We='Wednesdáy:BAABLgAECn8kAAMOAAcJxRWJPwCmAQAOAAcJxRWJPwCmAQAZAAEJfAzLUQArAAAAAA==.Werlock:BAAALgAECgcJCgABLgAECgkJJQASANQNAA==.Wetton:BAAALgAECgYJDQAAAA==.',
Wh='Wheresjohnny:BAABLgAECn83AAIhAAkJyBteDAA7AgAhAAkJyBteDAA7AgAAAA==.',
Wi='Wiccked:BAABLgAECn8uAAIXAAkJnBm3BAArAgAXAAkJnBm3BAArAgAAAA==.Willamena:BAAALgAECgYJBgAAAA==.Windrange:BAACLgAFFH8YAAIJAAYJ9xK9MwCHAQAJAAYJ9xK9MwCHAQAuAAQKfy4AAgkACQmuIFcrAMUCAAkACQmuIFcrAMUCAAAA.Winterice:BAAALgAECgQJBgAAAA==.Wintérhoof:BAAALgAECgYJCQABLgAECgkJFQABACgXAA==.',
Wo='Wonderpally:BAAALgAECgIJAgAAAA==.Woodscale:BAAALgAECgYJDQAAAA==.Wovenbones:BAABLgAECn8dAAIBAAgJlxmhPQADAgABAAgJlxmhPQADAgAAAA==.',
Wu='Wuggs:BAAALgAECgIJAgABLgAFFAYJIAAJACohAA==.Wumbo:BAAALgADCgYJDAAAAA==.',
Wy='Wyvarn:BAABLgAECn8XAAMSAAkJLgsWLQB+AQASAAkJLgsWLQB+AQAbAAEJawUpKAAmAAAAAA==.',
Xa='Xargothys:BAAALgAECgYJDQAAAA==.',
Xi='Xiisle:BAABLgAECn8gAAIKAAkJzSTLBQA+AwAKAAkJzSTLBQA+AwAAAA==.Xine:BAAALgADCgkJFAAAAA==.Xisle:BAAALgAECgIJAgABLgAECgkJIAAKAM0kAA==.',
Xt='Xt:BAAALgAECgMJBwAAAA==.',
Xx='Xxthequeenbe:BAAALgAECgYJBgAAAA==.',
Xy='Xynara:BAABLgAECn8fAAICAAkJrwb7cwAtAQACAAkJrwb7cwAtAQAAAA==.',
Ya='Yanya:BAABLgAECn8UAAIjAAgJrBT/JQAdAgAjAAgJrBT/JQAdAgAAAA==.',
Ye='Yergat:BAACLgAFFH8pAAQfAAgJGiCBFQCbAQAfAAUJdCWBFQCbAQAdAAcJ+hksDQBNAQAcAAQJWRN/EAA1AQAuAAQKf1MABBwACQlLJkIAAI8DAB0ACQn1Iu8BAJ0DABwACQlLJkIAAI8DAB8AAwnwIllmADQBAAAA.',
Yo='Yongu:BAAALgADCgkJCwAAAA==.',
Ys='Ysabela:BAAALgAECgQJBAABLgAECgYJHQAOAC8jAA==.',
Yu='Yupa:BAABLgAECn8hAAIZAAgJJRsHDgD9AQAZAAgJJRsHDgD9AQABLgAFFAQJDwAfAGYNAA==.',
Za='Zafira:BAACLgAFFH8NAAIjAAUJUBfYHQBkAQAjAAUJUBfYHQBkAQAuAAQKfywAAyMACQmjHFoRAIwCACMACQmjHFoRAIwCAA8ABQkfC6SKAE0AAAAA.Zainea:BAABLgAECn8VAAIRAAkJCBoZCwCoAgARAAkJCBoZCwCoAgABLgAFFAUJDQAjAFAXAA==.Zargothys:BAAALgADCgkJCQAAAA==.Zarndarg:BAAALgAECgQJBAAAAA==.Zartuu:BAAALgAECgcJCQAAAA==.Zattani:BAAALgAECgQJBgAAAA==.',
Ze='Zeel:BAAALgAECgUJBQAAAA==.Zelblades:BAABLgAECn8cAAMDAAgJyA81DwBLAQADAAgJyA81DwBLAQACAAMJlAVexgBtAAABLgAFFAYJFAAkAO8WAA==.Zelrex:BAACLgAFFH8UAAMkAAYJ7xbwEQBoAQAkAAUJRBzwEQBoAQAmAAEJmgHNEQBCAAAuAAQKfyoAAyQACQm6H3MPAK0CACQACQm6H3MPAK0CACYAAQmmFCMdAEIAAAAA.Zenitzu:BAAALgAECgEJAQAAAA==.Zerat:BAAALgAECgMJAwAAAA==.Zerazer:BAACLgAFFH8RAAIbAAUJ1CT2AACuAQAbAAUJ1CT2AACuAQAuAAQKfxYAAhsACQmfIQUEADUCABsACQmfIQUEADUCAAAA.',
Zh='Zhuntyr:BAABLgAECn8cAAIfAAgJohI+TACxAQAfAAgJohI+TACxAQAAAA==.',
Zi='Ziggedion:BAABLgAECn8UAAISAAkJYQjfNABTAQASAAkJYQjfNABTAQAAAA==.Zindar:BAABLgAECn8nAAISAAkJyR/3BwDSAgASAAkJyR/3BwDSAgAAAA==.Ziyan:BAABLgAECn8kAAMPAAkJ/x5ECADOAgAPAAkJ/x5ECADOAgAjAAEJTAnE1wAnAAAAAA==.',
Zv='Zv:BAAALgADCgUJBQAAAA==.',
Zy='Zylos:BAAALgADCgYJBwAAAA==.Zynzz:BAAALgAECgQJBwAAAA==.Zyvox:BAAALgAECgcJCAABLgAECgkJRQARAJQXAA==.',
['Zô']='Zômi:BAAALgAECggJDQAAAA==.',
['Àg']='Àgony:BAAALgAECgcJBwAAAA==.',
['Âx']='Âxell:BAAALgAECgEJAQABLgAECgkJLwAlAMYXAA==.',
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
