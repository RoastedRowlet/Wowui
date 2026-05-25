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

local lookup = {'DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','Druid-Feral','Druid-Guardian','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Warlock-Destruction','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Priest-Holy','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Warlock-Affliction','Monk-Mistweaver','Warrior-Protection','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Monk-Windwalker','Shaman-Restoration','Rogue-Subtlety','Priest-Discipline','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw','Shaman-Enhancement','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aazr:BAAALgADCgQJBAAAAA==.',
Ab='Abartheris:BAABLgAECn8dAAIBAAYJTwWxyQDEAAABAAYJTwWxyQDEAAAAAA==.Abroghast:BAAALgAECgUJBQAAAA==.',
Ac='Acanoffood:BAABLgAECn8vAAMCAAkJghOwMgDbAQACAAkJghOwMgDbAQADAAYJfgxmFQDTAAAAAA==.',
Ad='Adel:BAAALgAECgMJAwAAAA==.Adelil:BAAALgADCgEJBAAAAA==.Ademai:BAAALgADCgIJAgAAAA==.Adeptus:BAABLgAECn8VAAIEAAYJ5Q36IgDwAAAEAAYJ5Q36IgDwAAAAAA==.',
Ae='Aemeath:BAACLgAFFH8HAAICAAQJeA6JQAD8AAACAAQJeA6JQAD8AAAuAAQKfxwAAgIACAkXHDY6AAsCAAIACAkXHDY6AAsCAAAA.Aendres:BAAALgAECgYJEAAAAA==.Aethalyn:BAAALgAECggJCAAAAA==.',
Af='Afitis:BAAALgADCgIJAgAAAA==.',
Ag='Agriopas:BAABLgAECn8tAAMFAAgJ2A6pFgAoAQAFAAcJ8g2pFgAoAQAGAAcJigySJADoAAAAAA==.',
Ah='Aharon:BAAALgADCgkJCgAAAA==.',
Ai='Aireas:BAABLgAECn8VAAIHAAgJeR0RGwBnAgAHAAgJeR0RGwBnAgAAAA==.Aizen:BAAALgADCgYJBgABLgAECgYJCAAIAAAAAA==.',
Al='Alassomorph:BAAALgAECgYJDwAAAA==.Alazaie:BAAALgADCgMJAwAAAA==.Albus:BAACLgAFFH8NAAIJAAQJexfqQwA+AQAJAAQJexfqQwA+AQAuAAQKfywAAgkACQl3ILEUAMMCAAkACQl3ILEUAMMCAAAA.Aldasar:BAAALgADCggJCAAAAA==.Allayna:BAABLgAECn83AAIKAAkJdiFJDQDgAgAKAAkJdiFJDQDgAgAAAA==.Almitvez:BAAALgADCgcJBwABLgAECggJGQALAAkbAA==.Aloha:BAACLgAFFH8IAAIMAAMJmRnBIgDbAAAMAAMJmRnBIgDbAAAuAAQKfxwAAwwACAm/E7khANABAAwACAm/E7khANABAAoAAQkQAtaAASEAAAAA.Alohacuzz:BAAALgAECgEJAgAAAA==.Alysaliu:BAACLgAFFH8QAAIHAAUJxRv7NgA2AQAHAAUJxRv7NgA2AQAuAAQKfzYAAwcACQkYJT0FACgDAAcACQkYJT0FACgDAA0ABAnBFXkrABIBAAAA.Alysen:BAAALgAECgQJCgABLgAECgYJHQAOAC8jAA==.',
Am='Amisan:BAAALgADCgEJAQAAAA==.Amishpaladin:BAAALgAFFAMJBAAAAA==.Amishwarlock:BAAALgAECgYJCQABLgAFFAMJBAAIAAAAAA==.Amonotep:BAAALgAECgQJAwAAAA==.Amorianar:BAAALgAECgEJAQABLgAECgkJEwAIAAAAAA==.Amory:BAAALgAECgYJCwABLgADCgkJGQAIAAAAAA==.',
An='Anchor:BAABLgAECn8XAAIPAAYJfAbPUgD7AAAPAAYJfAbPUgD7AAAAAA==.Andja:BAABLgAECn9CAAIQAAkJVyY/AACIAwAQAAkJVyY/AACIAwAAAA==.Andromedae:BAABLgAECn8hAAIRAAkJoBDJHAC6AQARAAkJoBDJHAC6AQAAAA==.Andurìl:BAAALgAECgYJDAAAAA==.Anexa:BAAALgAECgYJDwAAAA==.Angela:BAAALgAECgQJBwAAAA==.Angelicshado:BAAALgADCgYJBgAAAA==.Anthbow:BAAALgAECgEJAQAAAA==.Anurek:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.',
Ar='Argulas:BAAALgADCgkJFQAAAA==.Ariajade:BAAALgAECgEJAQAAAA==.Ark:BAAALgAECgYJEgAAAA==.Arn:BAAALgAECgQJCQABLgAECgcJEwAIAAAAAA==.Arthrex:BAAALgAECgYJEAAAAA==.Arthus:BAAALgAECgYJDAAAAA==.Arturias:BAAALgAECgQJCwABLgAECgkJOQASAMoiAA==.',
As='Ashant:BAAALgADCgUJBQAAAA==.Asmobob:BAABLgAECn8kAAISAAgJlxnlDgACAgASAAgJlxnlDgACAgAAAA==.',
Au='Augmentin:BAABLgAECn8fAAMTAAgJSRxTGwBIAgATAAcJDB9TGwBIAgAUAAgJVw+aMwAaAQAAAA==.Auntfranny:BAAALgADCgEJAQAAAA==.Autoshot:BAAALgAECgUJBQAAAA==.',
Av='Avanie:BAAALgADCgYJBgAAAA==.Avina:BAAALgAECgYJDgAAAA==.Avrami:BAAALgADCgkJCgAAAA==.',
Aw='Aw:BAABLgAECn84AAQHAAkJ6yBFCgDpAgAHAAgJqCBFCgDpAgANAAUJFhZyJAA3AQAVAAIJyxYxKwBFAAAAAA==.Awokenbigdam:BAAALgAECgEJAQAAAA==.',
Az='Azràel:BAAALgAECgQJBAAAAA==.',
Ba='Babycoffee:BAAALgAECgkJDgAAAA==.Bahamutz:BAAALgADCgUJBAAAAA==.Bahwee:BAAALgAECgYJDwAAAA==.Bamboodragon:BAAALgAECggJCAAAAA==.Bangbangdou:BAABLgAECn8kAAIMAAgJcxyMEgBZAgAMAAgJcxyMEgBZAgAAAA==.Banzjo:BAAALgAECgEJAQAAAA==.Bastor:BAAALgADCgIJAgAAAA==.Bayle:BAAALgAECgYJDQAAAA==.',
Be='Bearnekkid:BAAALgAECgEJAQABLgAECgYJDAAIAAAAAA==.Bearsgomoo:BAAALgAECgUJBgABLgAECggJKwABACMiAA==.Beef:BAAALgAECgEJAQABLgAECgQJBQAIAAAAAA==.Beerthrowguy:BAABLgAECn8bAAMLAAkJ0yGbAwD7AgALAAkJ0yGbAwD7AgAWAAcJJhyXGAAUAgAAAA==.Bellaofroses:BAAALgADCgcJDAAAAA==.Bellatrix:BAAALgADCgYJBgAAAA==.Beneb:BAAALgAECgYJCwAAAA==.Benebeorn:BAACLgAFFH8RAAICAAUJ7RjlJgBKAQACAAUJ7RjlJgBKAQAuAAQKfx8AAgIACQmsIrUaALMCAAIACQmsIrUaALMCAAAA.Benkinobi:BAAALgAECgQJCwAAAA==.',
Bh='Bhaer:BAAALgAECgEJAgAAAA==.',
Bi='Bichewich:BAAALgADCgYJBgAAAA==.Bigal:BAAALgAECgMJAwABLgAECgkJDgAIAAAAAA==.Bigshot:BAAALgADCgYJCQAAAA==.Billyjoe:BAAALgAECgMJBQAAAA==.Binti:BAAALgADCgMJAwAAAA==.Bittronoxus:BAABLgAECn8tAAIJAAkJxBLiOwAPAgAJAAkJxBLiOwAPAgAAAA==.',
Bl='Blackryder:BAAALgAECgUJDgAAAA==.Bladesosteel:BAAALgAECgcJDAAAAA==.Bleys:BAAALgAECgQJBwABLgAECgkJMgAKAMkdAA==.Bloge:BAAALgAECgEJAQAAAA==.',
Bo='Bobbysmerica:BAABLgAECn8tAAMXAAgJuCEyBgCIAgAXAAgJuCEyBgCIAgAQAAEJ9At+QgA0AAAAAA==.Bobocanfly:BAABLgAECn8kAAMDAAgJ9RgzCQCtAQADAAgJ9RgzCQCtAQASAAEJAAAPdAAxAAAAAA==.Bodikhan:BAAALgAECgUJCgAAAA==.',
Br='Braxte:BAABLgAECn8uAAMOAAkJdR1nFwCRAgAOAAgJOR5nFwCRAgAQAAUJmxTRHQBAAQAAAA==.Breecy:BAAALgAECgUJDgAAAA==.Briguydkguy:BAACLgAFFH8KAAIBAAQJkQsOXgASAQABAAQJkQsOXgASAQAuAAQKfxgAAgEACAmfFuhgANEBAAEACAmfFuhgANEBAAAA.Brisstle:BAAALgAECggJEAAAAA==.Britziola:BAAALgAECgYJEwABLgADCgkJGQAIAAAAAA==.Brokenvoid:BAABLgAECn8mAAICAAcJPh1VPAC1AQACAAcJPh1VPAC1AQAAAA==.Bruiser:BAABLgAFFH8FAAMQAAMJMQa6HQCsAAAQAAMJMQa6HQCsAAAOAAEJRQCDRQAfAAAAAA==.Brusalt:BAAALgADCggJCAAAAA==.Brusten:BAABLgAECn8UAAIBAAkJ0iDJCQAEAwABAAkJ0iDJCQAEAwABLgAECgkJLgAOAHUdAA==.Bryce:BAAALgAECgUJEQABLgAECgcJDgAIAAAAAA==.',
Bu='Buggies:BAACLgAFFH8WAAIJAAUJ4iLmJgCIAQAJAAUJ4iLmJgCIAQAuAAQKfzUAAgkACQmpJX4SADgDAAkACQmpJX4SADgDAAAA.Buggs:BAAALgAECgQJBQABLgAFFAUJFgAJAOIiAA==.Buldozz:BAABLgAECn8oAAIMAAcJVxa+NQClAQAMAAcJVxa+NQClAQAAAA==.Bullit:BAAALgADCgYJCAABLgAECgYJDAAIAAAAAA==.Burnination:BAABLgAECn8rAAIJAAgJLSSXEQDYAgAJAAgJLSSXEQDYAgAAAA==.Burnzie:BAAALgADCgUJAwAAAA==.Butterfayce:BAABLgAECn83AAMMAAkJGSHiAwBBAwAMAAkJGSHiAwBBAwAKAAYJ7w7ZrQAAAQAAAA==.',
By='Bycew:BAAALgAECgcJDgAAAA==.',
Bz='Bzu:BAAALgAECgcJCwAAAA==.',
Ca='Cadastrasz:BAACLgAFFH8GAAIYAAIJQQJoSABlAAAYAAIJQQJoSABlAAAuAAQKf2EABBkACQl6E3cJACwCABkACQl6E3cJACwCABgACQk0Cm8rAGsBABoAAwmsAWM5AE4AAAAA.Cae:BAAALgAECgEJAQAAAA==.Camachopres:BAAALgAECgUJBwAAAA==.Cameocreme:BAAALgAECgcJCAAAAA==.Captfrost:BAAALgAECgEJAQAAAA==.Carsonkiller:BAAALgADCgEJAQABLgAECggJHgANACIaAA==.Catalyze:BAAALgAECgQJCAABLgAECgkJJQAYANQNAA==.Cateurize:BAABLgAECn8lAAIYAAkJ1A0QIwCgAQAYAAkJ1A0QIwCgAQAAAA==.',
Ce='Ceenit:BAABLgAECn8rAAIKAAkJIR9mFwCYAgAKAAkJIR9mFwCYAgAAAA==.Celalaliia:BAAALgADCgMJAwAAAA==.Celawyn:BAABLgAECn8WAAIbAAgJlwssKwAmAQAbAAgJlwssKwAmAQAAAA==.',
Ch='Chainedfire:BAAALgAECgQJBwAAAA==.Chasemon:BAABLgAECn8pAAIFAAgJeh5iBQBwAgAFAAgJeh5iBQBwAgAAAA==.Chaser:BAAALgAECgYJDAABLgAECggJKQAFAHoeAA==.Chaøtical:BAAALgAECgYJEAAAAA==.Chicosan:BAAALgAECgYJCwAAAA==.Chiliconcrne:BAAALgAECgIJAgAAAA==.Chrisolski:BAAALgAECgMJBAABLgAECgUJCgAIAAAAAA==.',
Ci='Cirragos:BAABLgAECn8XAAQYAAcJfw6jQAAAAQAYAAcJfw6jQAAAAQAZAAYJJAaXHwDSAAAaAAEJCQriIQAwAAAAAA==.',
Cl='Clamer:BAAALgADCgcJEAAAAA==.Clawdite:BAAALgADCgYJBgABLgAECggJGQALAAkbAA==.Clawesome:BAAALgAECgUJBgAAAA==.Cleansinq:BAAALgAECgEJAgAAAA==.Cloudsmoker:BAABLgAECn8gAAMTAAgJZw+sQQBnAQATAAgJZw+sQQBnAQAUAAMJOwbVdQBMAAAAAA==.',
Co='Corien:BAAALgAECgYJEQAAAA==.',
Cr='Crazegrippin:BAAALgAECgIJAwAAAA==.Crimsonmoon:BAABLgAECn8uAAIcAAkJPRCFCgCfAQAcAAkJPRCFCgCfAQAAAA==.Cryomara:BAAALgADCgYJCgAAAA==.',
Cu='Cueball:BAAALgADCgYJDgAAAA==.Cutiepotooti:BAAALgAECgQJBAABLgAFFAUJEwATABoMAA==.',
Cy='Cylasta:BAAALgADCgQJBgAAAA==.Cyndraexa:BAABLgAECn8VAAIdAAYJgQRESQC7AAAdAAYJgQRESQC7AAAAAA==.Cynia:BAABLgAECn8ZAAISAAcJmQq3JwABAQASAAcJmQq3JwABAQAAAA==.Cynra:BAABLgAECn8jAAMTAAkJFBvSDwC0AgATAAkJFBvSDwC0AgAUAAEJXRLLdAA1AAAAAA==.Cyrakos:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõwbell:BAAALgADCgEJAQAAAA==.',
Da='Dalize:BAAALgAECgcJCwAAAA==.Danarrath:BAABLgAECn8UAAIGAAYJCRPEIwDtAAAGAAYJCRPEIwDtAAABLgAECgcJEQAIAAAAAA==.Danger:BAAALgAECgQJBQAAAA==.Danklins:BAABLgAECn9AAAMYAAkJHB1HCgCXAgAYAAkJHB1HCgCXAgAaAAcJSxE5CgBZAQAAAA==.Dariabell:BAAALgAECgIJAgAAAA==.Darkramone:BAAALgAECgQJBgAAAA==.Darrow:BAAALgADCgQJBAAAAA==.Darthbane:BAAALgAECgQJCQAAAA==.Darthvada:BAABLgAECn8dAAMBAAcJHRXhbgBhAQABAAcJHRXhbgBhAQAeAAUJVg0OMACxAAAAAA==.',
De='Deadlydemon:BAAALgADCgEJAQAAAA==.Deadpoint:BAABLgAECn8dAAIOAAYJLyMMHwDTAQAOAAYJLyMMHwDTAQAAAA==.Deadski:BAABLgAECn8VAAIBAAYJixmjeABMAQABAAYJixmjeABMAQAAAA==.Deathfrost:BAACLgAFFH8KAAIJAAQJ0RC/SgAzAQAJAAQJ0RC/SgAzAQAuAAQKfykAAgkACAlSH30lAGkCAAkACAlSH30lAGkCAAAA.Debz:BAAALgADCgkJCQAAAA==.Defeatzhealz:BAAALgAECgYJEwAAAA==.Defeatzhunt:BAABLgAECn8XAAMfAAgJCxnXHABZAgAfAAgJCxnXHABZAgAcAAEJAABunAAJAAAAAA==.Deirdra:BAAALgAECgUJBQABLgAECgkJMgAKAMkdAA==.Delarium:BAAALgAECgIJAwAAAA==.Demonaria:BAABLgAECn85AAMSAAkJyiKWAwDyAgASAAkJiSKWAwDyAgADAAUJbSJtCwB5AQAAAA==.Denariah:BAAALgAECgMJAwABLgAECgcJHgAGAM4bAA==.Dendranaar:BAAALgAECgMJBAAAAA==.Dernen:BAAALgAECgcJEQAAAA==.Derpnface:BAABLgAECn8UAAIgAAYJTg8PMwBXAQAgAAYJTg8PMwBXAQAAAA==.Desecration:BAABLgAECn8vAAICAAcJPyQEIAA3AgACAAcJPyQEIAA3AgAAAA==.Devilhandler:BAAALgADCgcJDgAAAA==.Devilsautho:BAAALgAECgEJAQAAAA==.Dezimorikko:BAAALgADCgcJBwAAAA==.',
Di='Dirgir:BAABLgAECn8jAAIeAAkJCyGRBQCvAgAeAAkJCyGRBQCvAgAAAA==.Disk:BAAALgAECggJCgAAAA==.Distonia:BAABLgAECn8kAAIhAAgJ0hpfFAB7AgAhAAgJ0hpfFAB7AgAAAA==.',
Do='Dorothy:BAACLgAFFH8IAAIBAAMJownoLgDdAAABAAMJownoLgDdAAAuAAQKfx8AAgEACAkoHU1NALgBAAEACAkoHU1NALgBAAAA.',
Dr='Dracheo:BAACLgAFFH8TAAIJAAUJ6hbvOwBLAQAJAAUJ6hbvOwBLAQAuAAQKfzsAAgkACQkpItAQAN0CAAkACQkpItAQAN0CAAAA.Dragonbrr:BAAALgAECgUJDAABLgAECgcJGQAMAF8kAA==.Dragonwizard:BAABLgAECn8pAAIJAAcJKhyvUADNAQAJAAcJKhyvUADNAQAAAA==.Drakonna:BAAALgAECgQJBwAAAA==.Dranix:BAAALgAECgUJCwAAAA==.Draupaadi:BAAALgAECgEJAQAAAA==.Dreygur:BAAALgAECgcJDQAAAA==.Droiden:BAABLgAECn8aAAIfAAcJ6w0GcAAyAQAfAAcJ6w0GcAAyAQAAAA==.Droidetté:BAAALgAECgUJCwAAAA==.Droidén:BAAALgAECgEJAQAAAA==.Drotar:BAABLgAECn8zAAQUAAgJHBH1KwBHAQAUAAcJrRH1KwBHAQAFAAYJKAWLKACPAAAGAAEJtA0dWAAoAAAAAA==.Drovak:BAAALgAECgcJEAAAAA==.',
Du='Dumbdog:BAACLgAFFH8RAAITAAQJVh/fFgBqAQATAAQJVh/fFgBqAQAuAAQKfzYAAxMACQlgJYQDAFoDABMACQlgJYQDAFoDABQABgmaEx0+ADoBAAEuAAUUBwkiABkAYxwA.Dumichauch:BAACLgAFFH8QAAITAAUJnQ60GgBLAQATAAUJnQ60GgBLAQAuAAQKfzMAAhMACQmTG+4XAHcCABMACQmTG+4XAHcCAAAA.Durin:BAABLgAECn8kAAIKAAgJBBVfUAC4AQAKAAgJBBVfUAC4AQAAAA==.Duzzer:BAAALgADCgEJAQAAAA==.',
['Dé']='Déâth:BAAALgADCgkJCwAAAA==.',
Ec='Echo:BAAALgAECgcJCAAAAA==.',
Eg='Eggars:BAABLgAECn8gAAMHAAgJfQihcgA/AQAHAAgJfQihcgA/AQAVAAMJEgcMKABRAAAAAA==.',
Ek='Ekee:BAAALgAECgYJDgAAAA==.',
El='Elegance:BAAALgADCgIJAgAAAA==.Ellý:BAAALgADCgEJAQAAAA==.',
Em='Emberleaf:BAAALgADCgcJDgAAAA==.Emofriz:BAAALgAECgUJCQAAAA==.Emolate:BAABLgAECn8VAAIHAAgJagkCawBPAQAHAAgJagkCawBPAQABLgAFFAgJKQAfABogAA==.',
En='Ensetrend:BAAALgAECgIJAwAAAA==.Enve:BAABLgAECn8iAAICAAkJVh+RFgByAgACAAkJVh+RFgByAgAAAA==.',
Er='Erso:BAAALgADCgcJBwAAAA==.Erunkies:BAAALgAECgEJAQAAAA==.',
Eu='Euforia:BAAALgAECgEJAQAAAA==.',
Ev='Evanorah:BAAALgAECgEJAQAAAA==.Eviltiger:BAABLgAECn8+AAMfAAkJvSJBCAD4AgAfAAkJbyFBCAD4AgAcAAkJnRXGCADJAQAAAA==.',
Ew='Ewik:BAABLgAECn8ZAAMZAAgJYRd7EgAYAgAZAAgJYRd7EgAYAgAaAAMJLA20FwBzAAAAAA==.',
Ex='Excalìbur:BAAALgAECgQJBgABLgAECgYJDAAIAAAAAA==.',
Ey='Eydor:BAAALgADCggJCAAAAA==.',
Fa='Faent:BAABLgAECn8cAAIiAAYJxhLuJwAoAQAiAAYJxhLuJwAoAQAAAA==.Falimonki:BAAALgAECgMJAwAAAA==.Falinora:BAACLgAFFH8QAAMMAAUJCxg/EgBlAQAMAAUJCxg/EgBlAQAKAAEJrw4nhwBMAAAuAAQKfzUAAwwACQnFGqMiAAoCAAwACAltGaMiAAoCAAoACQnbF6psAHUBAAAA.Famous:BAAALgAECgMJAwAAAA==.Fantasticfox:BAABLgAECn9FAAMHAAkJpRPiMwDxAQAHAAkJpRPiMwDxAQANAAQJSQpFMgDvAAAAAA==.',
Fe='Felbyte:BAAALgADCgMJAwAAAA==.Felixs:BAABLgAECn8UAAIVAAYJtxvwCwBnAQAVAAYJtxvwCwBnAQAAAA==.Fellhanded:BAAALgADCgcJBwAAAA==.Feloron:BAAALgAECgQJCgAAAA==.Feluria:BAAALgADCgYJBgAAAA==.Feodin:BAACLgAFFH8HAAIKAAQJKRH7MAAtAQAKAAQJKRH7MAAtAQAuAAQKfxgAAwoACQkQG3U6APkBAAoACQkQG3U6APkBAAQABQlADHUqAJoAAAAA.Feosdragon:BAAALgADCgYJBgAAAA==.Feraldank:BAAALgAECgIJAwAAAA==.Ferrovax:BAAALgADCgEJAQABLgAECggJGgACADYcAA==.',
Fi='Fistariir:BAAALgAFFAMJAwABLgAFFAUJFwAjAMgWAA==.Fitzchivalry:BAAALgAECgQJBwAAAA==.',
Fl='Fleethefield:BAAALgAECgYJEAAAAA==.Flowabridge:BAABLgAECn8WAAIJAAYJrwOvAgH2AAAJAAYJrwOvAgH2AAABLgAECggJMAAUAHQTAA==.',
Fo='Foomanchu:BAAALgAECgQJBAABLgAECgYJFAADALUMAA==.Forcewild:BAABLgAECn8eAAIGAAgJ2R3VBgBZAgAGAAgJ2R3VBgBZAgAAAA==.',
Fr='Fragos:BAAALgAECgYJBwAAAA==.Friz:BAACLgAFFH8MAAMNAAQJgQgvEACAAAAHAAIJHAtkhwCLAAANAAMJqgcvEACAAAAuAAQKfyYAAw0ACQmwHF4IADwCAA0ACAmIH14IADwCAAcABQkZF8qeABsBAAAA.Frostychunks:BAABLgAECn8eAAIJAAgJdxvFPgAFAgAJAAgJdxvFPgAFAgAAAA==.',
Fu='Fuddrucker:BAAALgAECgkJDgAAAA==.Furflation:BAABLgAECn8kAAMZAAgJNReICgASAgAZAAgJNReICgASAgAaAAYJWx1cCACKAQAAAA==.Furgam:BAAALgAECgEJAQAAAA==.Fury:BAAALgADCgYJCgABLgAECgYJDAAIAAAAAA==.Fuzzychunks:BAABLgAECn8UAAMUAAYJCSJ9JgBqAQAUAAUJgiJ9JgBqAQATAAIJHh22egCoAAABLgAECggJHgAJAHcbAA==.',
Ga='Gabapentin:BAABLgAECn8UAAMgAAgJsBbtFwDKAQAgAAgJsBbtFwDKAQAWAAMJ6Bd3UgDHAAAAAA==.Gaeren:BAAALgADCgkJEwAAAA==.Gal:BAAALgAECgEJAwAAAA==.Galiron:BAAALgAECgYJBgABLgAECgkJMAAGAPofAA==.Gannon:BAABLgAECn8kAAIJAAgJWBytQgD4AQAJAAgJWBytQgD4AQAAAA==.Gano:BAEALgAECgUJCAABLgAFFAUJFAABAJQVAA==.Garr:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Garuuk:BAAALgAECgYJBgAAAA==.Gazir:BAAALgAECgkJEwAAAA==.',
Ge='Geniús:BAAALgADCgYJBgAAAA==.Genji:BAAALgAECgYJDQAAAA==.',
Gi='Giliandra:BAAALgADCggJFAAAAA==.Gingerbich:BAAALgAECgYJBgAAAA==.',
Gl='Glitch:BAACLgAFFH8HAAIXAAMJWwAAHwBjAAAXAAMJWwAAHwBjAAAuAAQKfygAAhcACQmhAmkkAOQAABcACQmhAmkkAOQAAAAA.',
Gn='Gnxs:BAAALgAECgQJCwAAAA==.',
Go='Goonthar:BAACLgAFFH8LAAIOAAUJZQ3eHQATAQAOAAUJZQ3eHQATAQAuAAQKfywAAg4ACAmaI/oKAAQDAA4ACAmaI/oKAAQDAAAA.Gorethak:BAABLgAECn8WAAIBAAYJORrWbABmAQABAAYJORrWbABmAQAAAA==.',
Gr='Grannykul:BAAALgADCgEJAQAAAA==.Grindrage:BAAALgADCgEJAQAAAA==.Gripmedaddy:BAAALgAECgQJBwAAAA==.Grobble:BAAALgADCgkJKQAAAA==.Grollgrr:BAAALgAECgQJCAAAAA==.Grompo:BAAALgAECgQJBAABLgAECgkJOAAHAOsgAA==.Grompy:BAAALgADCgQJBAABLgAECgkJOAAHAOsgAA==.Gruffbeard:BAAALgAECgIJAgABLgAECgYJDwAIAAAAAA==.',
Gu='Gunee:BAAALgADCgEJAQAAAA==.Gunghoiguana:BAAALgAECgYJDQAAAA==.',
Gy='Gyattso:BAAALgAECgcJDAAAAA==.Gyxx:BAABLgAFFH8TAAMKAAQJ4RZ1JABIAQAKAAQJ4RZ1JABIAQAMAAMJfxhQJgDCAAAAAA==.',
Ha='Haddice:BAABLgAECn8dAAIJAAcJjwkzmQAsAQAJAAcJjwkzmQAsAQAAAA==.Hafarti:BAAALgADCgUJBAAAAA==.Hairyteeth:BAAALgAECgUJDgAAAA==.Hajime:BAABLgAECn8dAAIjAAYJTQkvNAAXAQAjAAYJTQkvNAAXAQAAAA==.Halgrad:BAEALgAECgUJAQAAAA==.Hamburgers:BAAALgAECgEJAQAAAA==.Hansasperger:BAAALgAECgYJCAAAAA==.Harriedotter:BAAALgAECgEJAwAAAA==.Havárti:BAAALgADCgkJCQAAAA==.',
He='Heebiejeebie:BAACLgAFFH8GAAMVAAIJWQ/gGgBIAAAHAAIJ1wrvjQCAAAAVAAEJCQzgGgBIAAAuAAQKf1YABAcACQmPHWMgAEoCAAcACQnDGWMgAEoCABUABgn9HaUIAKgBAA0AAglpC4NXAGgAAAAA.Hellaeus:BAABLgAECn8wAAIKAAgJDBzRNQAJAgAKAAgJDBzRNQAJAgAAAA==.Hellsong:BAAALgAECgYJBgAAAA==.Heresjohnny:BAAALgAECgIJAgAAAA==.',
Hi='Hinatasan:BAAALgAECgEJAgAAAA==.Hira:BAAALgAECgUJBQAAAA==.Hisokä:BAABLgAECn9CAAISAAkJixm/CQBeAgASAAkJixm/CQBeAgAAAA==.',
Ho='Hoku:BAAALgAECgMJBAAAAA==.Holycreambar:BAABLgAECn8sAAIKAAgJ/SAnIABoAgAKAAgJ/SAnIABoAgAAAA==.Holyjuan:BAAALgADCgkJEgAAAA==.Hoofsbane:BAAALgADCgcJBwAAAA==.',
Hu='Huntingale:BAAALgAECgMJAwAAAA==.Huntinshift:BAABLgAECn8dAAIfAAcJlAkkeAAgAQAfAAcJlAkkeAAgAQAAAA==.Huslangr:BAAALgADCgEJAQAAAA==.Huwn:BAAALgADCgQJBAAAAA==.',
Hy='Hygelak:BAABLgAECn8aAAIKAAYJTAcxxADfAAAKAAYJTAcxxADfAAAAAA==.Hypaxia:BAABLgAECn8ZAAMfAAcJYA1BZgBJAQAfAAcJYA1BZgBJAQAcAAYJtAfuGQC9AAABLgAECgYJFwAcAFkYAA==.',
Ib='Ibpowerline:BAAALgADCgYJBgAAAA==.',
Ic='Icethorn:BAAALgAECgIJAwABLgAECgQJBAAIAAAAAA==.',
Ig='Iggysmalls:BAABLgAECn8jAAMCAAkJ2R+gCQDnAgACAAkJ2R+gCQDnAgADAAYJThKxEQAFAQAAAA==.',
Ii='Iidrizztdour:BAAALgADCgEJAQAAAA==.',
Il='Iluminaughti:BAAALgAECgYJCgAAAA==.',
Im='Immoc:BAACLgAFFH8SAAICAAUJRRwAKABGAQACAAUJRRwAKABGAQAuAAQKfy8AAwIACQl0HyohAIoCAAIACQl0HyohAIoCAAMAAQnrC8EvACIAAAAA.',
In='Indy:BAABLgAECn8vAAIWAAkJExOLHwDaAQAWAAkJExOLHwDaAQAAAA==.Infidius:BAAALgADCggJEAAAAA==.Interés:BAAALgADCgQJBAAAAA==.Intodeep:BAAALgAECgkJDgAAAA==.Invocation:BAAALgAECgYJBwABLgAECgcJLwACAD8kAA==.',
Io='Iownyourcow:BAAALgAECgIJAgAAAA==.',
Ip='Ip:BAAALgAFFAEJAQAAAA==.',
Ir='Iroha:BAAALgADCgYJBgAAAA==.Ironstag:BAAALgADCgQJBAAAAA==.',
Is='Istandalone:BAACLgAFFH8UAAMBAAUJSR5ZOQBQAQABAAQJSR5ZOQBQAQAeAAEJAACIQwAAAAAuAAQKfxoAAgEACAm8Hy4hALwCAAEACAm8Hy4hALwCAAAA.',
Ix='Ixioth:BAAALgAECgEJAQAAAA==.',
Ja='Jaglok:BAAALgADCgEJAQAAAA==.Jagons:BAABLgAECn8bAAIkAAcJ+gmbDQAvAQAkAAcJ+gmbDQAvAQAAAA==.Jahfar:BAAALgAECgYJBwAAAA==.Jaken:BAAALgAECgEJAgAAAA==.Janara:BAAALgAECgUJCgAAAA==.',
Je='Jehtadin:BAAALgAECgkJEQAAAA==.Jehthero:BAAALgAECgYJCgABLgAECgkJEQAIAAAAAA==.Jehtshot:BAABLgAECn8cAAMcAAgJkRz9FQCBAgAcAAgJkRz9FQCBAgAfAAMJ3hxYiADPAAABLgAECgkJEQAIAAAAAA==.Jehtword:BAAALgAECgMJAwABLgAECgkJEQAIAAAAAA==.Jemjemner:BAAALgAECgEJAQAAAA==.Jesy:BAAALgAECgYJDAABLgAFFAUJEQAfAAscAA==.',
Ji='Jimvisible:BAACLgAFFH8JAAIiAAMJBSRBGAAlAQAiAAMJBSRBGAAlAQAuAAQKfyAAAyIABwm9JnMGAKQCACIABwm9JnMGAKQCACQAAQm/JSYaAGkAAAAA.',
Jo='Joan:BAAALgAECgIJAgABLgAFFAQJDQAJAHsXAA==.Johadro:BAAALgADCgEJAQAAAA==.',
Jr='Jr:BAAALgAECgMJBAAAAA==.',
Ju='Judgejobrown:BAAALgAECggJEAAAAA==.Judgenawt:BAABLgAECn84AAIKAAkJwB6sEgC4AgAKAAkJwB6sEgC4AgAAAA==.Junon:BAAALgAECgUJCwAAAA==.',
Ka='Kahlanah:BAAALgAECgUJBQAAAA==.Kain:BAABLgAECn8qAAIHAAgJtxAwUQCRAQAHAAgJtxAwUQCRAQAAAA==.Kaiá:BAAALgADCgUJBQAAAA==.Kalegard:BAAALgADCgcJDgAAAA==.Kalerah:BAAALgADCgYJBgAAAA==.Kalis:BAABLgAECn8kAAIJAAgJWg8YdgBwAQAJAAgJWg8YdgBwAQAAAA==.Kallum:BAABLgAECn8UAAITAAcJexWzOACRAQATAAcJexWzOACRAQAAAA==.Kaltak:BAAALgAECgIJAgAAAA==.Kalvynx:BAABLgAECn8hAAIWAAgJBRZCIwC+AQAWAAgJBRZCIwC+AQAAAA==.Karasu:BAAALgAECgMJBgAAAA==.Karn:BAABLgAECn8zAAIKAAkJJR7EEwCxAgAKAAkJJR7EEwCxAgAAAA==.Karti:BAAALgAECgQJBwAAAA==.Karzdormi:BAEALgAECgcJDAAAAA==.Kathell:BAAALgAECgIJBAABLgAFFAUJEQAfAAscAA==.Kaylly:BAAALgAECgQJBAABLgAECgkJNAATANgSAA==.Kayllynt:BAAALgADCgkJJAABLgAECgkJNAATANgSAA==.Kayyllynt:BAABLgAECn80AAMTAAkJ2BIwIgAUAgATAAkJ2BIwIgAUAgAUAAcJ2Q8BLABGAQAAAA==.',
Ke='Kegeraetor:BAACLgAFFH8PAAILAAQJ5xtmFwA3AQALAAQJ5xtmFwA3AQAuAAQKfzAAAgsACQlTIsUUAOgBAAsACQlTIsUUAOgBAAEuAAUUBQkFABcAKx0A.Keinthdra:BAACLgAFFH8OAAMeAAMJ5BVCHQC9AAAeAAMJ5BVCHQC9AAABAAMJVgaWigC6AAAuAAQKfzwAAx4ACQkUHwIOAPkBAB4ACQkqHAIOAPkBAAEABQkxFq2AADwBAAAA.Kelein:BAAALgAECgEJAQABLgAECgYJDAAIAAAAAA==.Keliste:BAAALgAECgUJCQAAAA==.Kema:BAAALgAECgcJDgAAAA==.Kennaea:BAAALgAECgIJAgABLgAFFAUJEwAJAOoWAA==.Kervana:BAAALgAECgMJBAABLgAFFAUJFwAjAMgWAA==.',
Kh='Khrysais:BAAALgADCgMJAwAAAA==.',
Ki='Killigula:BAABLgAECn84AAIOAAkJQBvtDQBuAgAOAAkJQBvtDQBuAgAAAA==.Kinks:BAAALgAECgQJBAAAAA==.Kinuye:BAAALgAECgQJCAAAAA==.Kishara:BAAALgAECgUJBQABLgAFFAUJEQAfAAscAA==.Kiwi:BAAALgAECgIJAwAAAA==.',
Kl='Klondor:BAABLgAECn84AAQbAAgJAgsTIQB0AQAbAAgJUAoTIQB0AQAfAAYJHglddQAHAQAcAAIJxwF5fwBIAAAAAA==.Klutch:BAAALgADCgUJCAAAAA==.',
Ko='Kobato:BAAALgAECggJCAABLgAFFAIJBgAfACQRAA==.Kohakuu:BAAALgADCgEJAQAAAA==.Korash:BAABLgAECn8VAAMHAAkJ+CHMXwBrAQAHAAcJ+iHMXwBrAQANAAIJ6CEcOwDIAAAAAA==.',
Kr='Kraio:BAABLgAECn8iAAIJAAcJxhU5ZgCUAQAJAAcJxhU5ZgCUAQAAAA==.Kraisa:BAAALgADCgQJBAAAAA==.Krak:BAAALgAECgEJAQAAAA==.Krakenbones:BAAALgAECgUJCwAAAA==.Krangu:BAAALgADCgYJBgAAAA==.Krenolarian:BAAALgADCgUJBQAAAA==.Kronax:BAAALgADCgQJBAAAAA==.',
Kv='Kvoke:BAAALgAECgIJCQAAAA==.',
Ky='Kyranni:BAAALgAECgIJBQAAAA==.',
La='Lamora:BAAALgAECgYJEwAAAA==.Lampard:BAABLgAECn8XAAIOAAgJoBIRQQCgAQAOAAgJoBIRQQCgAQAAAA==.Laraj:BAABLgAECn8jAAIfAAkJBR6qDQC+AgAfAAkJBR6qDQC+AgAAAA==.Larissaqt:BAEBLgAECn8eAAIEAAkJVRl/CAAeAgAEAAkJVRl/CAAeAgAAAA==.Latindk:BAAALgADCgMJAwAAAA==.Latinhunter:BAAALgAECgYJDgAAAA==.Latinmonk:BAAALgAECgUJCAAAAA==.Latinshamy:BAABLgAECn8ZAAIhAAYJYxjHPgCBAQAhAAYJYxjHPgCBAQAAAA==.Lavande:BAAALgAECgQJCgAAAA==.',
Le='Lealu:BAAALgAECgUJBAAAAA==.Leara:BAABLgAECn8VAAIhAAgJGxSjKwDcAQAhAAgJGxSjKwDcAQABLgAFFAUJEQAfAAscAA==.Legomyagro:BAAALgAECggJEwAAAA==.Lehaya:BAAALgAECgEJAQAAAA==.Leiasolo:BAAALgAECgQJCAAAAA==.Leonaá:BAAALgAECgkJEwABLgAECgkJLwARACkkAA==.Lewpysoup:BAAALgAECgkJAQABLgAFFAUJBgAUAAsLAA==.',
Li='Lightfall:BAAALgAECgYJCwAAAA==.Lilbessy:BAABLgAECn8dAAIhAAcJfgXRZwDrAAAhAAcJfgXRZwDrAAAAAA==.Lishaliel:BAAALgADCgcJBwABLgAFFAUJEQAfAAscAA==.Lizy:BAAALgADCgkJDQABLgADCgkJGQAIAAAAAA==.Lizzia:BAAALgADCgQJBAAAAA==.',
Lo='Longhealz:BAAALgAECgQJBwAAAA==.Loopysoup:BAAALgAECgEJAQABLgAFFAUJBgAUAAsLAA==.Loopyswoop:BAAALgAECgcJDwABLgAFFAUJBgAUAAsLAA==.Lothriel:BAABLgAECn8tAAIlAAgJ2RfZAwA7AgAlAAgJ2RfZAwA7AgAAAA==.',
Lu='Lucid:BAAALgAECgEJAQAAAA==.Ludioduo:BAAALgAECgUJBgAAAA==.Luedayen:BAABLgAECn8oAAMRAAkJBhvWDwBoAgARAAkJBhvWDwBoAgAdAAEJqgp+cgAwAAAAAA==.Lukesunwalkr:BAAALgAECgEJAQAAAA==.Lunabellz:BAABLgAECn8fAAIUAAcJ5wjnPQDmAAAUAAcJ5wjnPQDmAAAAAA==.Lunavia:BAABLgAECn8hAAIfAAcJ+x3LMQDrAQAfAAcJ+x3LMQDrAQAAAA==.Luxembourge:BAAALgAECgUJDgAAAA==.',
Ma='Maalgus:BAABLgAECn8ZAAILAAgJCRvPDwAiAgALAAgJCRvPDwAiAgAAAA==.Maarajade:BAAALgAECgEJAQAAAA==.Mad:BAAALgAECgQJBwAAAA==.Magivyne:BAAALgAECgEJAQAAAA==.Mahota:BAAALgADCggJDwAAAA==.Makennah:BAAALgADCgcJBwAAAA==.Maladash:BAABLgAECn8eAAQCAAgJUBd/NAAnAgACAAgJUBd/NAAnAgADAAMJYwfKJABPAAASAAEJAgkXdAAxAAABLgAFFAQJBwAKACkRAA==.Malephar:BAAALgAECgUJBQAAAA==.Manachi:BAAALgAECgIJAgAAAA==.Margolem:BAAALgAECgYJBgAAAA==.Margoul:BAAALgAECgEJAQAAAA==.Massfootmen:BAAALgADCgUJBQAAAA==.Matiowen:BAAALgADCgMJAwAAAA==.Mauie:BAAALgADCgEJAQAAAA==.Mayyhem:BAACLgAFFH8iAAIZAAcJYxwvAwBoAgAZAAcJYxwvAwBoAgAuAAQKfzIAAxkACQkNI3kBAG8DABkACQkNI3kBAG8DABoAAgnfGegvAJgAAAAA.Mazrethil:BAAALgADCgEJAQAAAA==.',
Mc='Mcallister:BAABLgAECn81AAITAAgJXR6pFACCAgATAAgJXR6pFACCAgABLgADCgkJGQAIAAAAAA==.Mcjudgin:BAABLgAECn8bAAQEAAgJZiXeAABnAwAEAAgJZiXeAABnAwAMAAMJSxWxVwCoAAAKAAEJCh1YLAFIAAAAAA==.Mcsquid:BAAALgAECgEJAQAAAA==.',
Md='Mdrakeyd:BAABLgAECn8UAAICAAYJkReVZwAwAQACAAYJkReVZwAwAQAAAA==.',
Me='Meatbubble:BAAALgADCgkJFAAAAA==.Mechee:BAAALgAECggJDwAAAA==.Mephisston:BAAALgADCgIJAgAAAA==.Mesasneaky:BAAALgAECgUJBQAAAA==.',
Mi='Mimi:BAAALgAECgMJAwAAAA==.Mimiker:BAACLgAFFH8JAAIYAAUJYw6vJAAKAQAYAAUJYw6vJAAKAQAuAAQKfzYABBgACQk/HXUNAJ4CABgACQk/HXUNAJ4CABoABwkPF3MSALoBABkABAmzDz0iALgAAAAA.Minime:BAABLgAECn8VAAMfAAkJOiOyAwA8AwAfAAkJOiOyAwA8AwAcAAUJGxtbOACDAQABLgAFFAgJKQAfABogAA==.Minininja:BAAALgADCgcJDAABLgAECgQJEgAIAAAAAA==.Miniobi:BAAALgAECgQJBQAAAA==.Mirabella:BAABLgAECn8dAAIdAAgJegcAMwAlAQAdAAgJegcAMwAlAQAAAA==.Miriell:BAAALgADCgYJBgAAAA==.Mistdemeanor:BAAALgAECgEJAgAAAA==.Mizahella:BAAALgAECgUJBgAAAA==.',
Mo='Mofassa:BAAALgAECgEJAQAAAA==.Mokei:BAAALgAECgQJBQAAAA==.Mokushi:BAAALgAECgYJDQAAAA==.Mollie:BAAALgADCgcJBwABLgADCgkJFAAIAAAAAA==.Mondragore:BAAALgAECgQJBAAAAA==.Monkgruff:BAAALgAECgYJDwAAAA==.Monkèy:BAAALgADCgUJBQAAAA==.Moonsilver:BAABLgAECn8UAAMOAAcJBw/kOwAuAQAOAAcJngzkOwAuAQAXAAUJ0xBGMACXAAAAAA==.Moriko:BAACLgAFFH8GAAIfAAIJJBHEWwCZAAAfAAIJJBHEWwCZAAAuAAQKfzQAAh8ACQlRHAAWAIgCAB8ACQlRHAAWAIgCAAAA.Mornak:BAAALgAECgkJCAAAAA==.Mourn:BAAALgAECgEJAQABLgAFFAUJBQAXACsdAA==.',
Mu='Mudstomper:BAAALgAECggJCAABLgAFFAIJBgAfACQRAA==.Muertomarrow:BAAALgAECgYJDgAAAA==.Mulroth:BAAALgAECgQJBAAAAA==.Murdermitten:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Murloc:BAAALgAECgYJCgAAAA==.Musasa:BAABLgAECn8kAAITAAgJphmtIAA+AgATAAgJphmtIAA+AgAAAA==.Mustardseed:BAABLgAECn81AAIHAAkJsRHjNwDhAQAHAAkJsRHjNwDhAQAAAA==.Muxaro:BAAALgAECgQJBwAAAA==.',
['Mí']='Mísery:BAAALgAECgYJDQAAAA==.',
Na='Naked:BAAALgAECgIJAwAAAA==.Naliannagoat:BAAALgADCgEJAQAAAA==.Nalibeefcake:BAAALgADCgcJDQAAAA==.Narkoleptick:BAAALgAECgYJCQAAAA==.Nasrith:BAABLgAECn8yAAIKAAkJyR0HEwC1AgAKAAkJyR0HEwC1AgAAAA==.Nastro:BAAALgAECgQJBwAAAA==.Naughtica:BAAALgAECgMJBwABLgAECgYJCgAIAAAAAA==.Nawtishot:BAAALgADCgEJAQAAAA==.Nazanath:BAAALgAECgIJAgAAAA==.',
Ne='Neeb:BAABLgAECn8dAAIEAAgJMBk+DwCiAQAEAAgJMBk+DwCiAQAAAA==.Neeber:BAAALgAECgUJDwAAAA==.Neebtacular:BAAALgAECgEJAQAAAA==.Nekk:BAABLgAECn8kAAIXAAgJrRyYCgAjAgAXAAgJrRyYCgAjAgAAAA==.',
Ni='Niamyau:BAAALgADCgMJAwAAAA==.Niraleth:BAAALgAECgIJAwAAAA==.Nitebrite:BAABLgAECn8bAAIRAAYJ4hIZLwAwAQARAAYJ4hIZLwAwAQAAAA==.',
No='Noatak:BAAALgAECgEJAgAAAA==.Nohozis:BAAALgADCgQJBAAAAA==.Noimia:BAABLgAECn8yAAIWAAkJdRwnDACjAgAWAAkJdRwnDACjAgAAAA==.Noraina:BAAALgADCgEJAQAAAA==.Normanosborn:BAAALgAECgQJCgAAAA==.',
Ny='Nyquiil:BAAALgAECgUJBQAAAA==.Nyssil:BAAALgADCgcJCwAAAA==.',
['Né']='Nésa:BAAALgAECgMJAwAAAA==.',
['Nï']='Nïssan:BAAALgAECgcJEQAAAA==.',
Ob='Obscûr:BAABLgAECn8WAAMCAAYJJA5KhQDsAAACAAUJxQ1KhQDsAAASAAUJHg2gMwC4AAAAAA==.',
Oc='Ochtli:BAAALgADCgUJBQAAAA==.',
Od='Oden:BAABLgAECn8ZAAIPAAgJnx4mDQBwAgAPAAgJnx4mDQBwAgAAAA==.',
Og='Oggy:BAAALgAECgIJAgAAAA==.',
Ok='Oksanabaiul:BAABLgAECn8ZAAIPAAUJ5R7aLwBTAQAPAAUJ5R7aLwBTAQABLgAFFAUJEAAHAMUbAA==.',
Ol='Oldcode:BAAALgAECgUJCgAAAA==.Oleyander:BAAALgAECgUJCQAAAA==.Olskigather:BAAALgADCgMJAwAAAA==.Olskimonk:BAAALgAECgUJCgAAAA==.',
Or='Orondrean:BAAALgADCgEJAQAAAA==.Oronin:BAAALgAECgMJAwAAAA==.',
Os='Osanyin:BAAALgAECgcJEgAAAA==.',
Ot='Otsuka:BAAALgADCgEJAQAAAA==.',
Pa='Pacoesfu:BAAALgADCgcJBgAAAA==.Padray:BAACLgAFFH8SAAIdAAQJuhNpEQA+AQAdAAQJuhNpEQA+AQAuAAQKf08AAh0ACQnVHgEIALECAB0ACQnVHgEIALECAAAA.Paecos:BAAALgADCgYJDQAAAA==.Palize:BAAALgADCgYJBgABLgAECgcJCwAIAAAAAA==.Panhia:BAAALgAECgQJEgAAAA==.Parliament:BAAALgAECgYJCwAAAA==.',
Pe='Pekoyami:BAAALgADCgUJBQAAAA==.Pen:BAABLgAECn8wAAIUAAgJdBNxIACXAQAUAAgJdBNxIACXAQAAAA==.Pepenlock:BAAALgAECgQJBQAAAA==.Pepperbottom:BAABLgAECn8eAAMNAAgJIhooCACfAQANAAgJnRkoCACfAQAHAAQJ+BAjmgDyAAAAAA==.Perforation:BAAALgAECgQJBAABLgAECgcJLwACAD8kAA==.',
Pf='Pfft:BAAALgAECgYJDAAAAA==.',
Ph='Phantasmshot:BAABLgAECn8pAAIfAAgJfQ89TwCHAQAfAAgJfQ89TwCHAQAAAA==.Phoebere:BAAALgAECgQJBwAAAA==.Phung:BAAALgAECgkJDQAAAA==.Phungi:BAAALgAECgYJDAAAAA==.',
Po='Polymnia:BAAALgAECgUJDAAAAA==.Pomelo:BAAALgAECgUJDwAAAA==.Popeums:BAABLgAECn8kAAMjAAgJegR1PADlAAAjAAcJlAJ1PADlAAARAAUJYQXsRwCbAAAAAA==.Poplock:BAAALgADCgYJBgAAAA==.Poppiqt:BAABLgAECn8eAAIWAAgJHhTBIgDBAQAWAAgJHhTBIgDBAQAAAA==.Powlie:BAAALgAECgMJAwAAAA==.Poyoh:BAABLgAECn8yAAITAAkJ1htPEACvAgATAAkJ1htPEACvAgAAAA==.',
Pr='Pravoce:BAABLgAECn8aAAMdAAgJmA2IJQB2AQAdAAgJmA2IJQB2AQAjAAUJ9wvJOAD8AAAAAA==.Prolifichd:BAAALgAECgEJAgABLgAECgEJAwAIAAAAAA==.Prufrock:BAAALgADCgYJBgAAAA==.',
['Pí']='Pínt:BAABLgAECn8kAAMfAAgJjyMtDwCwAgAfAAgJgyItDwCwAgAbAAYJtB7SDgDZAQAAAA==.',
Qu='Quelissa:BAAALgADCgkJCQABLgAECggJEAAIAAAAAA==.',
Ra='Radjason:BAAALgADCggJCQAAAA==.Raeagald:BAABLgAFFH8FAAIXAAUJKx2ACQBYAQAXAAUJKx2ACQBYAQAAAA==.Raelyni:BAABLgAECn83AAIRAAkJ+htwCQCtAgARAAkJ+htwCQCtAgAAAA==.Rafael:BAAALgADCgMJAwAAAA==.Rageroyal:BAAALgADCgEJAQAAAA==.Rahum:BAAALgAECgQJBgAAAA==.Rakkah:BAABLgAECn8hAAMfAAcJBRWQZQBLAQAfAAcJvBKQZQBLAQAcAAYJaQlRTgAXAQAAAA==.Rakkuh:BAAALgAECgQJBAAAAA==.Ramjam:BAAALgADCgYJCQAAAA==.Ranann:BAAALgAECgQJBAAAAA==.Rangwashu:BAAALgAECgYJDQABLgAECgcJEQAIAAAAAA==.Raveniss:BAABLgAECn8dAAIUAAgJuAdANQARAQAUAAgJuAdANQARAQAAAA==.Rawrie:BAABLgAECn8hAAMPAAgJcQfuPgAIAQAPAAgJcQfuPgAIAQAhAAMJsglogwCGAAAAAA==.Raygun:BAABLgAECn8dAAIJAAcJaxERewBlAQAJAAcJaxERewBlAQABLgADCgkJGQAIAAAAAA==.Rayzorevoker:BAAALgADCgcJDQAAAA==.Raziell:BAAALgADCgMJAwAAAA==.',
Re='Redhilda:BAABLgAECn8ZAAIPAAYJgApjTADTAAAPAAYJgApjTADTAAAAAA==.Redmayhem:BAAALgADCgYJBgAAAA==.Remygos:BAAALgADCgEJAQAAAA==.',
Rh='Rhymu:BAAALgAECgQJBAAAAA==.',
Ri='Rissaria:BAAALgAECgIJAgAAAA==.',
Ro='Roshelle:BAAALgAECgIJAgAAAA==.Rotation:BAABLgAECn8UAAQDAAYJtQxTFQDUAAADAAYJQwxTFQDUAAASAAMJPAZpWACEAAACAAIJkQYJ2gBMAAAAAA==.Rotblade:BAABLgAECn8aAAImAAkJ2BfxBgCwAQAmAAkJ2BfxBgCwAQAAAA==.',
Ru='Rudewenn:BAAALgAECgYJDwAAAA==.Runandhide:BAABLgAECn8VAAIJAAYJmhDXuQBuAQAJAAYJmhDXuQBuAQAAAA==.',
Ry='Ryllativity:BAAALgADCgEJAQAAAA==.',
['Ró']='Rógue:BAAALgAECgQJBQABLgAECgUJCAAIAAAAAA==.',
['Rø']='Røøtsftw:BAAALgAECgYJBgAAAA==.',
Sa='Sadsnap:BAABLgAECn8ZAAInAAcJxyBECQBFAgAnAAcJxyBECQBFAgAAAA==.Safetybear:BAAALgAECgkJEgAAAA==.Salamender:BAACLgAFFH8NAAIZAAUJOxKmDwBhAQAZAAUJOxKmDwBhAQAuAAQKfy0AAhkACQkEHGEEAMYCABkACQkEHGEEAMYCAAAA.Sapheer:BAAALgAECgcJCgAAAA==.Sargothys:BAAALgAECgIJAgAAAA==.Sariais:BAAALgAECgEJAQAAAA==.Sassymoo:BAACLgAFFH8LAAITAAQJOA25JAAMAQATAAQJOA25JAAMAQAuAAQKfyMAAxMABwkNH/MWAG0CABMABwkNH/MWAG0CAAYAAQmPBME6ABEAAAEuAAUUBAkLACEApBYA.Sathenoth:BAAALgADCggJCAAAAA==.Satraa:BAAALgAECgUJBQABLgAECgkJLwARACkkAA==.Savagejoker:BAAALgAECgEJAQABLgAECggJIQAoAL4iAA==.Sañtoro:BAAALgAECgQJDQAAAA==.',
Sc='Scalesboi:BAAALgADCgMJAwAAAA==.Scipione:BAAALgAECgYJEQAAAA==.Scy:BAABLgAECn8WAAMfAAcJ1QuuZwBGAQAfAAcJ1QuuZwBGAQAcAAEJagQeOgAkAAAAAA==.',
Se='Seddona:BAAALgADCgkJCQAAAA==.Seithe:BAAALgAECgEJAQAAAA==.Seluun:BAABLgAECn8kAAIJAAYJ5BEBmwApAQAJAAYJ5BEBmwApAQAAAA==.Semandemon:BAAALgAECgEJAQAAAA==.Sephandrius:BAAALgADCgEJAQABLgAECgcJEQAIAAAAAA==.Seraphae:BAABLgAECn8ZAAMRAAgJkw+bIgCLAQARAAgJlg6bIgCLAQAjAAYJ0gzJLgA2AQAAAA==.',
Sh='Shadowmorn:BAABLgAECn8dAAIPAAgJJQOQUQDBAAAPAAgJJQOQUQDBAAAAAA==.Shalako:BAAALgAECgIJAwAAAA==.Shambali:BAAALgAECgcJBwAAAA==.Shamidozz:BAAALgAECgQJBQABLgAECgcJKAAMAFcWAA==.Shamnistic:BAABLgAECn8iAAMnAAkJrh/8BABwAgAnAAkJrh/8BABwAgAhAAEJyg0ftgAqAAAAAA==.Shandro:BAABLgAECn8tAAIJAAkJfgsPXQCrAQAJAAkJfgsPXQCrAQAAAA==.Shaniallon:BAABLgAECn8tAAMfAAkJNxE9NgDaAQAfAAkJExE9NgDaAQAcAAcJdwv6EgAHAQAAAA==.Shara:BAAALgADCgMJBgAAAA==.Sharana:BAAALgADCgUJBQAAAA==.Shaunï:BAAALgAECgYJEgAAAA==.Sheriff:BAAALgAECgEJAQAAAA==.Shieldman:BAAALgADCgMJAwAAAA==.Shiftylock:BAABLgAECn8eAAMGAAcJzhvEFAByAQAGAAYJKhzEFAByAQAFAAQJSRcFIgDKAAAAAA==.Shine:BAAALgAECgMJAwAAAA==.Showong:BAAALgAECgEJAQAAAA==.',
Si='Silentaska:BAABLgAECn8ZAAIYAAYJoSH7IwCaAQAYAAYJoSH7IwCaAQAAAA==.Silentbruce:BAAALgAFFAEJAQAAAA==.Silentchill:BAACLgAFFH8FAAIUAAIJYwpGLQCSAAAUAAIJYwpGLQCSAAAuAAQKfywAAxQACAmvHfsXAEoCABQACAmvHfsXAEoCABMAAQkFAs/kACAAAAAA.Silius:BAAALgAECgUJDAAAAA==.Simoncrunch:BAAALgAECgEJBQAAAA==.Sin:BAAALgAECgEJAQABLgAECgEJAwAIAAAAAA==.Sinomen:BAACLgAFFH8JAAInAAUJcBfABABEAQAnAAUJcBfABABEAQAuAAQKfy4AAicACQnmJH8AAFQDACcACQnmJH8AAFQDAAEuAAUUCAkUABgALRcA.Sinzilla:BAAALgAECgYJDQAAAA==.Sizzen:BAAALgADCgkJCQAAAA==.',
Sk='Skunkdrunk:BAAALgADCgYJBwAAAA==.Skyblue:BAAALgAECgcJEwAAAA==.',
Sm='Smokebull:BAABLgAECn8ZAAIOAAcJ+QrmQQAUAQAOAAcJ+QrmQQAUAQAAAA==.Smolcat:BAAALgAECgQJBAABLgAFFAcJIgAZAGMcAA==.',
Sn='Sneeble:BAAALgADCgkJCQAAAA==.Snoopshaman:BAAALgAECgEJAQABLgAECggJGwAEAGYlAA==.Snowcake:BAAALgAECgEJBwAAAA==.',
So='Sofiavers:BAAALgAECgQJBAAAAA==.Solarhoof:BAAALgADCgEJAQAAAA==.Sonarak:BAAALgAECgEJAQABLgAECggJGwAEAGYlAA==.Sornafayne:BAAALgAECgYJCgAAAA==.Sorrengail:BAABLgAECn8dAAIhAAcJryGXEwCDAgAhAAcJryGXEwCDAgAAAA==.Soulvamp:BAAALgADCgUJBQAAAA==.',
Sp='Spareme:BAAALgAECgQJCAABLgAECgkJDgAIAAAAAA==.Specialkidd:BAAALgAECgkJDwABLgAECgkJEgAIAAAAAA==.Springrollz:BAAALgAECggJEAABLgAFFAgJKQAfABogAA==.Spy:BAABLgAECn8vAAIfAAkJ7RqgGgBdAgAfAAkJ7RqgGgBdAgAAAA==.',
Sr='Sravoz:BAAALgAECgYJCQAAAA==.',
St='Stabbitha:BAAALgADCgkJHAAAAA==.Stampa:BAAALgAECgQJBwAAAA==.Starrie:BAABLgAECn86AAMhAAgJmRGePwB9AQAhAAgJmRGePwB9AQAPAAgJbgueNwApAQAAAA==.Steaknshake:BAAALgAECgQJBAAAAA==.Steelhoof:BAACLgAFFH8GAAIcAAIJDASPHAB7AAAcAAIJDASPHAB7AAAuAAQKf0QAAhwACQnGEMUIAMkBABwACQnGEMUIAMkBAAAA.Steil:BAAALgAECgYJCQAAAA==.Steponmyface:BAABLgAECn8rAAMBAAgJIyJGGwCBAgABAAgJIyJGGwCBAgAlAAIJzxvxHgCDAAAAAA==.Stewie:BAAALgADCgcJCgABLgADCgkJFAAIAAAAAA==.Stonesoul:BAABLgAECn8hAAMhAAkJgRoiDgC7AgAhAAkJgRoiDgC7AgAPAAEJ3wv8jgAqAAAAAA==.Stories:BAABLgAECn8VAAIJAAYJ0BhmoACWAQAJAAYJ0BhmoACWAQAAAA==.Storm:BAEALgAECgYJCgABLgAFFAUJFAABAJQVAA==.Stormfury:BAAALgAECgEJAwAAAA==.Strongheart:BAAALgADCgcJBwABLgAECgYJDAAIAAAAAA==.Strucker:BAAALgADCgcJCwABLgAECgkJMgALAJQgAA==.Struckerdots:BAAALgAECgQJBAABLgAECgkJMgALAJQgAA==.Struckerz:BAAALgADCgkJEAABLgAECgkJMgALAJQgAA==.Struckerzz:BAAALgAECgQJBwAAAA==.Struckrucker:BAABLgAECn8yAAILAAkJlCDFBADeAgALAAkJlCDFBADeAgAAAA==.Stygian:BAAALgAECgEJAQAAAA==.',
Su='Succubussi:BAAALgAECgcJCwAAAA==.Sudimmoc:BAAALgAECgIJAgAAAA==.Sugarbear:BAAALgADCgUJBQAAAA==.Sushie:BAAALgADCgMJAwABLgAFFAUJEAAMABITAA==.',
Sv='Svikja:BAAALgAECgQJBwAAAA==.',
Sw='Swipe:BAAALgAECgcJEAAAAA==.',
Sy='Synn:BAAALgAECgYJBgAAAA==.Syvina:BAABLgAECn8VAAIjAAYJIgn7NAASAQAjAAYJIgn7NAASAQAAAA==.',
Ta='Tabby:BAAALgAECgMJBgAAAA==.Taconight:BAABLgAECn8bAAIRAAYJKgdfPQDXAAARAAYJKgdfPQDXAAAAAA==.Tacosaladin:BAAALgADCggJCAAAAA==.Tag:BAAALgAECgYJCAAAAA==.Takyon:BAAALgADCgYJBgABLgAECggJFgABALcjAA==.Tallynz:BAABLgAECn8hAAIRAAkJYBeeDAB0AgARAAkJYBeeDAB0AgAAAA==.Tankornot:BAABLgAECn8UAAIKAAUJZiBqTQDAAQAKAAUJZiBqTQDAAQAAAA==.Tarasque:BAAALgAECgEJAQABLgAECgEJBwAIAAAAAA==.Tarlgreyhair:BAAALgAECgYJCwAAAA==.Tarnished:BAABLgAECn8dAAIJAAkJwwLttAD+AAAJAAkJwwLttAD+AAAAAA==.Tarr:BAABLgAECn8aAAIKAAcJchdEXwCTAQAKAAcJchdEXwCTAQAAAA==.Tateerfel:BAABLgAECn8hAAMSAAYJpiHrFgCZAQACAAYJVx8dQwCcAQASAAYJBxvrFgCZAQAAAA==.Tateertot:BAAALgAECgEJAQABLgAECgYJIQASAKYhAA==.Tawneestone:BAABLgAECn9CAAIXAAkJ0CWWAABqAwAXAAkJ0CWWAABqAwAAAA==.',
Te='Teedizzle:BAAALgAECggJEwAAAA==.Teek:BAABLgAECn8YAAMVAAYJwAQXFQDfAAAVAAYJnAIXFQDfAAAHAAYJwAQDtQDCAAAAAA==.Telandaraa:BAABLgAECn8vAAMRAAkJKSS6AQBdAwARAAkJKSS6AQBdAwAjAAMJFgn8RACRAAAAAA==.Telrae:BAABLgAECn81AAIHAAkJ8SHkCAD5AgAHAAkJ8SHkCAD5AgAAAA==.',
Th='Theb:BAABLgAECn8ZAAICAAkJihD4NgDKAQACAAkJihD4NgDKAQAAAA==.Thechase:BAAALgAECgYJBgABLgAECggJKQAFAHoeAA==.Thederpb:BAAALgAECggJEQAAAA==.Thejuice:BAAALgADCgcJDwAAAA==.Theldara:BAACLgAFFH8RAAIfAAUJCxzjGABdAQAfAAUJCxzjGABdAQAuAAQKfzEAAx8ACQleIUQpABICAB8ACQleIUQpABICABwABgkTFlk7AHMBAAAA.Themock:BAABLgAECn8VAAMUAAYJ9Q4ZSQC1AAAUAAQJFg0ZSQC1AAATAAMJawJsvgAwAAAAAA==.Thereaper:BAAALgAECgMJAwAAAA==.Theresjohnny:BAAALgADCgkJGwAAAA==.Thesentinel:BAAALgADCgYJCAABLgAECgYJDAAIAAAAAA==.Theshift:BAABLgAECn80AAIjAAkJJxkKCwCUAgAjAAkJJxkKCwCUAgAAAA==.Thesixtyone:BAAALgADCgcJBwAAAA==.Thisisjustin:BAABLgAECn8mAAIpAAkJWh4PAQCWAgApAAkJWh4PAQCWAgAAAA==.Thoreen:BAAALgAECgQJBwAAAA==.Thotsnprayer:BAAALgADCgMJBAAAAA==.Thraiel:BAAALgADCgQJBAABLgAECgUJDgAIAAAAAA==.Thrish:BAACLgAFFH8QAAMfAAUJVxT/MgAXAQAfAAQJow3/MgAXAQAbAAQJphQtFQD8AAAuAAQKfzYABB8ACQmSHu8cAFgCAB8ACAm7Ge8cAFgCABsABgn/HjAZALcBABwAAQkFAoiYAB4AAAAA.Throom:BAAALgADCgIJAgAAAA==.Thuggies:BAABLgAECn8bAAIiAAgJmxxNDAA7AgAiAAgJmxxNDAA7AgAAAA==.Thunderfist:BAAALgAECgYJDQABLgAFFAQJBwAKACkRAA==.',
Ti='Tizzlerizzle:BAAALgAECgQJBwAAAA==.',
To='Tomacco:BAAALgADCggJEgAAAA==.Toreto:BAAALgADCgUJBwAAAA==.Toshi:BAAALgAECgQJBwAAAA==.Totemiclord:BAABLgAECn8aAAIPAAgJRA6NMgBEAQAPAAgJRA6NMgBEAQAAAA==.',
Ts='Tsukiyami:BAAALgAECgUJDwABLgAECgYJEgAIAAAAAA==.',
Tw='Twixaldo:BAAALgAECgQJBgABLgAECggJLAAKAP0gAA==.Twixiepaw:BAAALgAECgYJBgABLgAECggJLAAKAP0gAA==.',
Ty='Ty:BAAALgADCgEJAQAAAA==.Tylus:BAAALgAECgEJAQAAAA==.',
Ub='Ubpriest:BAAALgAECgQJBwAAAA==.',
Up='Upinya:BAABLgAECn8YAAMNAAkJSAp3DwAcAQANAAkJSAp3DwAcAQAHAAEJ+QCnMgEcAAAAAA==.',
Ut='Uthrob:BAAALgADCggJCAAAAA==.',
Uz='Uzumaki:BAAALgAECgQJBAAAAA==.',
Va='Vadderung:BAABLgAECn8aAAICAAgJNhyXKgBWAgACAAgJNhyXKgBWAgAAAA==.Valera:BAAALgAECgYJCwABLgAECgkJQgAQAFcmAA==.Valkilmer:BAAALgADCgEJAQAAAA==.Vallasha:BAABLgAECn8nAAIVAAcJHRH7DABmAQAVAAcJHRH7DABmAQAAAA==.Valoth:BAAALgADCgEJAQAAAA==.Valtures:BAAALgAECgMJCAAAAA==.Vampyre:BAACLgAFFH8KAAIfAAQJhhcJKAA0AQAfAAQJhhcJKAA0AQAuAAQKfykAAh8ACQmoIMAJAOgCAB8ACQmoIMAJAOgCAAAA.Vayne:BAACLgAFFH8RAAIOAAQJ/x6oEgBFAQAOAAQJ/x6oEgBFAQAuAAQKfzUAAw4ACQnnJL8RAMICAA4ACQnnJL8RAMICABAAAQksEwdBADYAAAAA.',
Ve='Vejek:BAAALgAECgkJBQAAAA==.Veloistina:BAAALgAECgEJAQABLgAECggJLAAKAP0gAA==.Veloria:BAAALgAECgEJAgAAAA==.Venator:BAAALgADCgQJBAAAAA==.',
Vh='Vh:BAAALgAECgQJCAAAAA==.',
Vi='Videlle:BAAALgADCgMJAwAAAA==.Vieoree:BAAALgAECgUJDAAAAA==.Vigoh:BAAALgADCgcJBwABLgAECgcJFwAYAH8OAA==.Vinge:BAECLgAFFH8UAAIBAAUJlBV/RQA7AQABAAUJlBV/RQA7AQAuAAQKfzMAAgEACQmLIuotAIECAAEACQmLIuotAIECAAAA.Vinter:BAAALgADCgkJEwAAAA==.Violetferal:BAAALgADCgkJIQAAAA==.Violetrain:BAABLgAECn8iAAIKAAcJKQR7zwDOAAAKAAcJKQR7zwDOAAAAAA==.Viralswine:BAAALgAECgcJCgAAAA==.Visarys:BAAALgAECgQJBAAAAA==.Vixipixi:BAAALgADCgYJEgAAAA==.',
Vo='Vollibear:BAAALgAECgMJAwAAAA==.Voltaic:BAABLgAECn8bAAIhAAcJNCMdEgCFAgAhAAcJNCMdEgCFAgABLgAECgcJLwACAD8kAA==.Vothdomosh:BAAALgAECgMJAwABLgAECgcJGQAMAF8kAA==.',
Vr='Vraylaros:BAAALgAECgkJEgAAAA==.',
Vy='Vyrista:BAABLgAECn8YAAISAAcJoQ8vIAA7AQASAAcJoQ8vIAA7AQAAAA==.Vyrzeth:BAAALgAECgMJBgAAAA==.Vyzualize:BAACLgAFFH8TAAIMAAYJahKFBACYAQAMAAYJahKFBACYAQAuAAQKfy0AAgwACQl0IKoHAPICAAwACQl0IKoHAPICAAAA.',
Wa='Wae:BAACLgAFFH8JAAIeAAUJeRhsDwA3AQAeAAUJeRhsDwA3AQAuAAQKfxkAAh4ACQmLHpkHAHsCAB4ACQmLHpkHAHsCAAAA.Waferblade:BAAALgADCgcJBwAAAA==.Waknipi:BAABLgAECn8hAAMKAAkJcxzIIQBgAgAKAAkJcxzIIQBgAgAMAAEJIQUEnAAtAAAAAA==.Wauwen:BAAALgADCgkJGQAAAA==.Wavecheck:BAAALgAECgMJBQAAAA==.Way:BAAALgAECgIJAgAAAA==.Waycaps:BAACLgAFFH8NAAIDAAQJRx47AgBLAQADAAQJRx47AgBLAQAuAAQKfy0AAgMACAk2I9ABAPgCAAMACAk2I9ABAPgCAAAA.Wayfairinc:BAAALgAECgIJAgABLgAECggJLQAXALghAA==.',
We='Wednesdáy:BAABLgAECn8kAAMOAAcJxRWJPwCmAQAOAAcJxRWJPwCmAQAXAAEJfAwERwAxAAAAAA==.Werlock:BAAALgAECgcJCgABLgAECgkJJQAYANQNAA==.Wetton:BAAALgAECgYJCwAAAA==.',
Wh='Wheresjohnny:BAABLgAECn83AAIeAAkJyBvkCQBJAgAeAAkJyBvkCQBJAgAAAA==.',
Wi='Wiccked:BAABLgAECn8pAAIVAAgJ0xe3BAArAgAVAAgJ0xe3BAArAgAAAA==.Windrange:BAACLgAFFH8RAAIJAAUJxhJoRgA6AQAJAAUJxhJoRgA6AQAuAAQKfy4AAgkACQmuIFcrAMUCAAkACQmuIFcrAMUCAAAA.Winterice:BAAALgAECgQJBQAAAA==.Wintérhoof:BAAALgAECgYJBgABLgAECgcJDQAIAAAAAA==.',
Wo='Wonderpally:BAAALgADCgkJCQAAAA==.Woodscale:BAAALgAECgQJBwAAAA==.Wovenbones:BAABLgAECn8cAAIBAAgJ1RikNwD+AQABAAgJ1RikNwD+AQAAAA==.',
Wu='Wuggs:BAAALgAECgIJAgABLgAFFAUJFgAJAOIiAA==.Wumbo:BAAALgADCgYJDAAAAA==.',
Wy='Wyvarn:BAAALgAECgcJEwAAAA==.',
Xa='Xargothys:BAAALgAECgYJDQAAAA==.',
Xi='Xiisle:BAABLgAECn8eAAIKAAgJ6yS5DQDdAgAKAAgJ6yS5DQDdAgAAAA==.Xine:BAAALgADCgkJFAAAAA==.Xisle:BAAALgAECgIJAgABLgAECggJHgAKAOskAA==.',
Xt='Xt:BAAALgADCgYJDAAAAA==.',
Xy='Xynara:BAABLgAECn8aAAICAAkJwwS9dwAKAQACAAkJwwS9dwAKAQAAAA==.',
Ya='Yanya:BAAALgAECggJEAAAAA==.',
Ye='Yergat:BAACLgAFFH8pAAQfAAgJGiBPCQCuAQAfAAUJdCVPCQCuAQAcAAcJ+hksDQBNAQAbAAQJWRPUDABHAQAuAAQKf0EABBsACQl6JYYAAHADABwACQn1Iu8BAJ0DABsACQlWJYYAAHADAB8AAwnwIllmADQBAAAA.',
Yo='Yongu:BAAALgADCgkJCwAAAA==.',
Ys='Ysabela:BAAALgAECgEJAQABLgAECgYJHQAOAC8jAA==.',
Yu='Yupa:BAABLgAECn8dAAIXAAcJlBsBEADAAQAXAAcJlBsBEADAAQABLgAFFAIJBgAfACQRAA==.',
Za='Zafira:BAACLgAFFH8LAAIhAAQJpBYsIgAkAQAhAAQJpBYsIgAkAQAuAAQKfyoAAyEACQmjHFoRAIwCACEACQmjHFoRAIwCAA8AAwnmDOVxAHsAAAAA.Zainea:BAAALgAECggJDwABLgAFFAQJCwAhAKQWAA==.Zarndarg:BAAALgAECgQJBAAAAA==.Zartuu:BAAALgAECgcJCQAAAA==.Zattani:BAAALgAECgQJBgAAAA==.',
Ze='Zeel:BAAALgAECgUJBQAAAA==.Zelblades:BAABLgAECn8cAAMDAAgJyA9fDQBPAQADAAgJyA9fDQBPAQACAAMJlAVexgBtAAABLgAFFAUJCQAiAJoVAA==.Zelrex:BAACLgAFFH8JAAIiAAUJmhX9EQBOAQAiAAUJmhX9EQBOAQAuAAQKfyoAAyIACQm6H24MADkCACIACQm6H24MADkCACQAAQmmFCMdAEIAAAAA.Zerat:BAAALgAECgMJAwAAAA==.Zerazer:BAACLgAFFH8LAAIaAAUJYyIDAQCOAQAaAAUJYyIDAQCOAQAuAAQKfxQAAhoACQmfIVMDAEICABoACQmfIVMDAEICAAAA.',
Zh='Zhuntyr:BAABLgAECn8aAAIfAAcJvxBzXwBaAQAfAAcJvxBzXwBaAQAAAA==.',
Zi='Ziggedion:BAABLgAECn8UAAIYAAkJYQhoLQBfAQAYAAkJYQhoLQBfAQAAAA==.Zindar:BAABLgAECn8kAAIYAAgJLR9cDQBqAgAYAAgJLR9cDQBqAgAAAA==.Ziyan:BAAALgAECgkJEgAAAA==.',
Zv='Zv:BAAALgADCgUJBQAAAA==.',
Zy='Zylos:BAAALgADCgYJBwAAAA==.Zynzz:BAAALgAECgQJBwAAAA==.',
['Zô']='Zômi:BAAALgAECgcJDAAAAA==.',
['Àg']='Àgony:BAAALgAECgcJBwAAAA==.',
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
