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

local lookup = {'Shaman-Restoration','Warlock-Destruction','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Hunter-BeastMastery','Paladin-Protection','Unknown-Unknown','Mage-Frost','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Hunter-Survival','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Warrior-Protection','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','DemonHunter-Havoc','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Mage-Fire',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aartoo:BAAALgADCgUJBwAAAA==.',
Ac='Ace:BAAALgAFFAIJAgAAAA==.Ackreshanot:BAAALgAECgUJDgABLgAFFAQJFAABAGEdAA==.Acuminada:BAAALgADCgcJCwAAAA==.Acuna:BAABLgAECn8jAAICAAcJfxNsCQBeAQACAAcJfxNsCQBeAQAAAA==.',
Ad='Adamantine:BAAALgAECgcJEQAAAA==.',
Ae='Aere:BAAALgAECgYJEgAAAA==.Aerotika:BAAALgADCgcJBwAAAA==.',
Ai='Airz:BAABLgAECn8mAAIDAAcJCB3lDgBMAgADAAcJCB3lDgBMAgAAAA==.',
Ak='Akennethpaly:BAAALgADCgQJBwAAAA==.Aknou:BAAALgADCgQJBAAAAA==.Akrichie:BAAALgAECgEJAQABLgAFFAcJEgAEAB8LAA==.Akudama:BAAALgAECgUJCAAAAA==.Akâkiôs:BAABLgAECn8iAAIFAAgJKxb4FwDRAQAFAAgJKxb4FwDRAQAAAA==.',
Al='Aladorman:BAABLgAECn8eAAIGAAcJPgjNZgAaAQAGAAcJPgjNZgAaAQAAAA==.Albertlin:BAAALgAECggJEwAAAA==.Aldin:BAABLgAECn8aAAIHAAYJnA0jIQC1AAAHAAYJnA0jIQC1AAAAAA==.Aleisterr:BAAALgADCgEJAQAAAA==.Alexpaladin:BAAALgADCgEJAQAAAA==.Altarya:BAAALgAECgYJBgABLgAECgcJDgAIAAAAAA==.Altex:BAABLgAECn8tAAIJAAkJ8hraGwB5AgAJAAkJ8hraGwB5AgAAAA==.Altexa:BAAALgADCgMJAwABLgAFFAEJAwAIAAAAAA==.Altriimus:BAAALgAECgQJDgAAAA==.',
Am='Amakuagsak:BAABLgAECn8kAAIGAAgJgQ0rSgBpAQAGAAgJgQ0rSgBpAQAAAA==.Amicus:BAABLgAECn8jAAIKAAcJ4xFuNQB9AQAKAAcJ4xFuNQB9AQAAAA==.',
An='Anadarmas:BAAALgAECgUJBwAAAA==.Ancestor:BAAALgADCgUJBQAAAA==.Aneki:BAAALgAECgEJAQAAAA==.Angelcastiel:BAAALgADCgEJAQAAAA==.Anothertalas:BAAALgAECgIJAQAAAA==.Anthracss:BAAALgAECgUJCgAAAA==.Anthren:BAAALgADCgYJBgABLgAECgIJAwAIAAAAAA==.Anthrun:BAAALgADCgEJAgABLgAECgIJAwAIAAAAAA==.',
Ao='Aoifè:BAAALgAECgMJDAAAAA==.',
Ap='Apollo:BAABLgAECn8kAAMLAAgJ1BpKRACxAQALAAgJ1BpKRACxAQAMAAMJ0AuhWwBoAAAAAA==.Apolynnae:BAAALgADCgMJAwABLgAFFAIJAwAIAAAAAA==.Apolynnæ:BAAALgAFFAIJAwAAAA==.',
Aq='Aquanoria:BAAALgADCggJEwAAAA==.',
Ar='Aragaren:BAAALgAECgYJDAAAAA==.Arasthel:BAAALgAECgkJDAAAAA==.Arthalion:BAAALgAECgEJAQAAAA==.Arvellonwen:BAAALgADCgEJAQAAAA==.Aryasilly:BAAALgAECgcJCwAAAA==.',
As='Ascalapha:BAAALgAECgcJBwAAAA==.Ashe:BAACLgAFFH8dAAMNAAYJQybMAQAgAgANAAYJbSXMAQAgAgAOAAQJTSVLAgCxAQAuAAQKfzAAAw0ACQmhJkIAAPADAA0ACQmdJkIAAPADAA4ABQmYJU4XAJ0BAAAA.',
At='Atownbrew:BAAALgADCgEJAQAAAA==.Attabubble:BAAALgADCgEJAQABLgAFFAUJEAAGAF0fAA==.Attaraxia:BAACLgAFFH8QAAIGAAUJXR9pCQAWAQAGAAUJXR9pCQAWAQAuAAQKfykAAwYACQlFI/sJAPgCAAYACQlFI/sJAPgCAA0AAQm4AYiZABsAAAAA.',
Au='Aure:BAAALgADCgMJAwAAAA==.Aurelith:BAAALgADCgMJBAAAAA==.Auvona:BAAALgAECgYJCAAAAA==.',
Av='Avalora:BAAALgADCgcJCQAAAA==.',
Az='Azaleth:BAAALgAECgYJBgAAAA==.Azavin:BAABLgAECn8WAAIMAAgJNgwLNgCkAQAMAAgJNgwLNgCkAQABLgAFFAMJBgAPAFERAA==.Azol:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Azu:BAAALgADCgEJAQAAAA==.',
Ba='Babba:BAAALgADCgQJBAAAAA==.Baddington:BAAALgAFFAIJAgAAAA==.Baegar:BAAALgAECggJCQAAAA==.Bakugo:BAACLgAFFH8UAAIEAAUJdBgbDgCYAQAEAAUJdBgbDgCYAQAuAAQKfykABAQACQkdIMQJAJ4CAAQACQkmHsQJAJ4CABAABgmNH/EgANsBABEABgmEF7AkAE4BAAAA.Bamfbutcher:BAABLgAECn8aAAISAAkJXxfKIgA/AgASAAkJXxfKIgA/AgAAAA==.Banang:BAAALgADCgUJBQAAAA==.Barrimen:BAABLgAECn8nAAILAAgJoAyTZABbAQALAAgJoAyTZABbAQAAAA==.Bartolomew:BAAALgAECgkJLAAAAQ==.Bashton:BAAALgADCgMJAwAAAA==.Bastian:BAAALgADCgEJAQAAAA==.Batboy:BAAALgAECgYJEgAAAA==.',
Be='Bealzabung:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.Bedemere:BAAALgAECgIJAgAAAA==.Beepers:BAABLgAECn8fAAIGAAkJKg53OwCcAQAGAAkJKg53OwCcAQAAAA==.Behodahlia:BAABLgAECn8eAAIDAAgJKQndNQAFAQADAAgJKQndNQAFAQAAAA==.Benezra:BAAALgAECgEJAQAAAA==.Bexurk:BAABLgAECn8bAAMTAAkJIwVZDwBIAQATAAkJIwVZDwBIAQAFAAEJwgOUhQAiAAAAAA==.',
Bi='Biaku:BAAALgADCgIJAgAAAA==.Bibleman:BAAALgADCgIJAgABLgAECgcJHgADAB8YAA==.Bigbilly:BAAALgADCgkJCQAAAA==.Bigcalcium:BAABLgAECn8oAAILAAgJ/yWOBgBmAwALAAgJ/yWOBgBmAwAAAA==.Bigdemon:BAAALgAECgcJCwAAAA==.Bighimbo:BAABLgAECn8XAAIDAAYJYyCnEwAQAgADAAYJYyCnEwAQAgAAAA==.Biltix:BAACLgAFFH8NAAIUAAQJNSGdCgB8AQAUAAQJNSGdCgB8AQAuAAQKfyIAAhQACQnpHsgSAHwCABQACQnpHsgSAHwCAAAA.Bimzelx:BAAALgAECgMJBQAAAA==.Bipolar:BAAALgAECgUJDAAAAA==.Bitterblood:BAABLgAECn8ZAAIGAAcJwBUDQgCEAQAGAAcJwBUDQgCEAQAAAA==.',
Bl='Blanche:BAAALgADCgYJBgAAAA==.Blastgamer:BAAALgAECgMJBQAAAA==.Blindbob:BAAALgADCgUJBwAAAA==.Blueb:BAAALgADCgkJEgABLgAFFAMJBwAQAMgSAA==.',
Bo='Boboe:BAAALgAECgIJAgAAAA==.Bocaj:BAAALgADCgEJAQABLgAECggJLQAJAHMdAA==.Boltbourne:BAAALgADCgUJBQAAAA==.Bolyn:BAAALgAECgIJAgAAAA==.Bonami:BAAALgADCgYJBgAAAA==.Bongwizard:BAAALgADCgUJBQAAAA==.Boogapib:BAAALgADCgEJAQAAAA==.Booshi:BAABLgAECn8cAAIKAAgJbhUdNwDLAQAKAAgJbhUdNwDLAQAAAA==.Bowiiesenpai:BAABLgAECn8lAAIRAAkJ6B+nCQBsAgARAAkJ6B+nCQBsAgAAAA==.Bowmarc:BAABLgAECn8lAAILAAkJ2RJKLwD7AQALAAkJ2RJKLwD7AQAAAA==.Boykisser:BAAALgAECgUJBgAAAA==.',
Br='Bravehearth:BAAALgAECgMJBgABLgAECgUJBQAIAAAAAA==.Brewcifer:BAAALgADCgYJBgAAAA==.Brightxan:BAABLgAECn8tAAIHAAkJXRoBBgA8AgAHAAkJXRoBBgA8AgAAAA==.Broamdar:BAAALgAECgkJBgAAAA==.Brotha:BAAALgADCgUJCgAAAA==.Brownbeard:BAABLgAECn8iAAIVAAgJ6BJACACMAQAVAAgJ6BJACACMAQAAAA==.',
Bu='Bubbapriest:BAAALgADCgMJAwAAAA==.Bubbashaman:BAAALgAECgYJDQAAAA==.Budgetsushi:BAAALgADCgcJCwAAAA==.Burninator:BAABLgAECn8ZAAQWAAkJ5BWIEwCrAQAWAAYJrhmIEwCrAQAPAAkJYhG3IgCpAQAXAAIJJw1NQABoAAAAAA==.Bus:BAABLgAFFH8PAAIYAAUJSiMeAQD4AQAYAAUJSiMeAQD4AQABLgAFFAkJFgAZALEhAA==.Butterrs:BAAALgAECgUJFgAAAQ==.Butterz:BAABLgAECn8fAAIFAAkJuB5HCwDkAgAFAAkJuB5HCwDkAgABLgAECgUJFgAIAAAAAA==.',
Ca='Cadjin:BAAALgAECgEJAQAAAA==.Caelan:BAAALgAECgcJDAAAAA==.Caloren:BAACLgAFFH8FAAIaAAMJGguFQwDSAAAaAAMJGguFQwDSAAAuAAQKfzIAAxoACQklIfEIANECABoACQklIfEIANECABsAAQnRGaQhAEUAAAAA.Calqlated:BAAALgADCgYJBgABLgAECggJFQAcAMQeAA==.Caorou:BAAALgADCgYJBgAAAA==.Captflower:BAAALgADCgUJBQAAAA==.',
Ce='Cedrid:BAAALgAECgcJCwAAAA==.Cenauria:BAAALgADCgYJBgAAAA==.',
Ch='Chanit:BAABLgAECn8dAAILAAgJHxU1QgC3AQALAAgJHxU1QgC3AQAAAA==.Chaosbeast:BAAALgADCgEJAQAAAA==.Charlemagnê:BAAALgADCgYJBgABLgAECggJIgAFACsWAA==.Charuzu:BAAALgAECggJEwAAAA==.Chaurana:BAABLgAECn8mAAIbAAgJNBZfCACYAQAbAAgJNBZfCACYAQAAAA==.Chenzio:BAAALgADCgUJBQAAAA==.Chikorita:BAAALgAECgcJDgAAAA==.Chilidan:BAAALgAECgIJAgAAAA==.Chimichurri:BAAALgAECgMJAwAAAA==.Chipo:BAAALgAECgEJAgAAAA==.Chrilynn:BAABLgAECn8gAAMLAAcJnBvnXwBnAQALAAYJiRnnXwBnAQAHAAYJlBV0HQDSAAAAAA==.Chuwee:BAAALgADCgIJAgAAAA==.',
Ci='Cind:BAAALgADCgcJCAABLgAECgcJBwAIAAAAAA==.Cinderatrath:BAACLgAFFH8UAAIWAAUJnxKhAgBCAQAWAAUJnxKhAgBCAQAuAAQKfyoAAhYACAkRIkkDAOsCABYACAkRIkkDAOsCAAAA.Cindoreon:BAAALgAECgcJBwAAAA==.',
Cn='Cnydemon:BAAALgADCgEJAQAAAA==.',
Co='Corsaro:BAAALgAECgUJDwAAAA==.Corvixius:BAABLgAECn8aAAISAAcJRwqEPwD0AAASAAcJRwqEPwD0AAAAAA==.',
Cr='Crunchwrap:BAAALgAECgYJEAAAAA==.',
Cu='Cuigy:BAABLgAECn8bAAIBAAcJ2iPkEAB2AgABAAcJ2iPkEAB2AgAAAA==.',
Cy='Cyriene:BAABLgAECn8hAAIGAAcJaREUUQBVAQAGAAcJaREUUQBVAQAAAA==.Cyrik:BAABLgAECn8eAAMdAAgJTh34AgAvAgAdAAgJTh34AgAvAgACAAUJYhEXKQAeAQAAAA==.',
Da='Daevas:BAAALgADCgEJAQABLgAECgcJHgADAB8YAA==.Danksinatra:BAABLgAECn8aAAIeAAgJPxVIQQC5AQAeAAgJPxVIQQC5AQAAAA==.Danté:BAABLgAECn8dAAIJAAgJrBrAUgA/AgAJAAgJrBrAUgA/AgAAAA==.Dardorian:BAAALgAECgEJAgAAAA==.Darkfist:BAAALgAECgYJCQAAAA==.Darko:BAAALgAECgQJCgAAAA==.Darou:BAABLgAECn8gAAMVAAgJZA2IDAAsAQAVAAgJZA2IDAAsAQAfAAEJHQL5TwAVAAAAAA==.Daylen:BAABLgAECn8iAAMQAAgJFBBMHwCBAQAQAAgJFBBMHwCBAQAEAAEJSgFGYQAZAAAAAA==.',
De='Deactrim:BAAALgAFFAEJAQAAAA==.Deadploo:BAAALgADCgMJAwAAAA==.Deadpòól:BAAALgADCgUJBQABLgAECgIJAgAIAAAAAA==.Deafknights:BAAALgAECgcJDgABLgAFFAEJAwAIAAAAAA==.Deathgoat:BAAALgADCgIJAgAAAA==.Deku:BAAALgAECgQJCgABLgAECggJIAAZABkWAA==.Demiglace:BAABLgAECn8oAAQUAAgJmSZ3AgALAwAUAAgJmSZ3AgALAwAgAAEJMRm/YwBGAAADAAEJxxTDaAAwAAABLgAFFAcJJAAaANcgAA==.Demonfloozie:BAAALgADCgkJCQAAAA==.Demongal:BAAALgADCgQJBAAAAA==.Dendrada:BAABLgAECn8hAAIeAAgJ3SCkGABvAgAeAAgJ3SCkGABvAgAAAA==.Dewbie:BAACLgAFFH8MAAIOAAUJdhrmBwBhAQAOAAUJdhrmBwBhAQAuAAQKfy0AAg4ACQnkGoIKADcCAA4ACQnkGoIKADcCAAAA.',
Di='Dirtyshim:BAAALgAECgMJAwAAAA==.Dizimo:BAABLgAECn8dAAIKAAcJGCSICgDVAgAKAAcJGCSICgDVAgAAAA==.',
Dm='Dminn:BAAALgAECgQJBQAAAA==.',
Do='Dogmeat:BAACLgAFFH8QAAIGAAUJEx1UAgB6AQAGAAUJEx1UAgB6AQAuAAQKfx8AAgYABwmhIqUWAIMCAAYABwmhIqUWAIMCAAEuAAUUBgkMACEAixAA.Doncowleone:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.Doomslayer:BAAALgADCgcJDgAAAA==.Doreniel:BAAALgAECgkJAgAAAA==.Dormo:BAAALgAECgcJDAABLgAECgcJHgADAB8YAA==.Dotisa:BAAALgAECgYJDQAAAA==.',
Dr='Drave:BAAALgAECgEJAQAAAA==.Draxker:BAABLgAECn8eAAIWAAgJtw7iBwByAQAWAAgJtw7iBwByAQAAAA==.Dreadmourne:BAAALgAECgUJBgAAAA==.Drfumanchu:BAAALgADCgUJCAABLgAECgUJBQAIAAAAAA==.Druddigon:BAAALgAECgUJCAABLgAECggJFQAcAMQeAA==.',
Du='Duna:BAABLgAECn8dAAIJAAcJaAuKhAAyAQAJAAcJaAuKhAAyAQAAAA==.Duvidressra:BAABLgAECn8oAAMdAAgJ4RIwCAB9AQAdAAgJ4RIwCAB9AQAcAAMJTAV7/QBgAAAAAA==.',
Dx='Dxmvn:BAAALgADCgEJAQAAAA==.',
Dy='Dyingmight:BAAALgAECgQJBAAAAA==.',
['Dä']='Dävïs:BAAALgAECggJEwABLgAECgkJGQAeAPsLAA==.',
Ed='Edea:BAAALgAECgcJDgAAAA==.Edisonn:BAACLgAFFH8MAAIcAAUJyQyfOwAVAQAcAAUJyQyfOwAVAQAuAAQKfykAAxwACAmzIM8WAGICABwACAmzIM8WAGICAAIAAwmYHD07AMcAAAAA.',
El='Eldarya:BAAALgAECgYJCwAAAA==.Eldermoon:BAAALgAECgYJCAAAAA==.Elghinn:BAABLgAECn80AAIiAAkJYhJIDwDMAQAiAAkJYhJIDwDMAQAAAA==.Ellie:BAABLgAECn8yAAIGAAgJMB+OHwAaAgAGAAgJMB+OHwAaAgAAAA==.Elponch:BAAALgAECgcJBwAAAA==.Elroy:BAABLgAECn8vAAILAAgJBxRASwCcAQALAAgJBxRASwCcAQAAAA==.',
Em='Embold:BAACLgAFFH8WAAINAAYJZyISAgBRAgANAAYJZyISAgBRAgAuAAQKfy0AAg0ACQnqJWcAAOcDAA0ACQnqJWcAAOcDAAEuAAUUBwkNABEAIxoA.Emernantus:BAABLgAECn8tAAIHAAgJQQ+aFQAjAQAHAAgJQQ+aFQAjAQAAAA==.Emozi:BAABLgAECn8sAAMcAAkJ1xHZMQDSAQAcAAkJExHZMQDSAQAdAAYJoBHQCwB9AQAAAA==.',
Eu='Eunbyeol:BAABLgAECn8oAAISAAgJIx3nGADYAQASAAgJIx3nGADYAQAAAA==.',
Ex='Excidium:BAAALgAECgYJDQAAAA==.Expired:BAAALgAECgUJBQAAAA==.',
Fa='Faeria:BAABLgAECn8pAAIQAAgJQR5+BwCyAgAQAAgJQR5+BwCyAgAAAA==.Fangwalker:BAAALgAECgQJDwAAAA==.Farmerdotcom:BAAALgADCgEJAQAAAA==.Fatnchunkydk:BAABLgAECn8eAAIfAAcJ+w1SIQDyAAAfAAcJ+w1SIQDyAAAAAA==.Fatpigeon:BAAALgAECgYJEAAAAA==.',
Fe='Feeblemind:BAABLgAECn8iAAIGAAgJgxZ7OACnAQAGAAgJgxZ7OACnAQAAAA==.Feesherman:BAABLgAFFH8NAAILAAUJYiTnCQCnAQALAAUJYiTnCQCnAQAAAA==.Feli:BAABLgAECn8aAAISAAgJlwtUKwBYAQASAAgJlwtUKwBYAQAAAA==.Felldor:BAAALgADCgUJAgAAAA==.Felmommy:BAAALgADCgYJBgAAAA==.Felrindan:BAAALgAECgYJDAAAAA==.Felscream:BAAALgADCgUJBQAAAA==.Fender:BAABLgAECn8fAAIjAAgJARbvCQDCAQAjAAgJARbvCQDCAQAAAA==.Ferchrian:BAAALgADCgEJAQAAAA==.',
Fi='Finfangfoom:BAAALgAECgQJBwABLgAECgUJBQAIAAAAAA==.Fingertoes:BAABLgAECn8tAAMJAAgJcx30LgAbAgAJAAgJcx30LgAbAgAkAAEJNxAFEAA1AAAAAA==.Fishermonk:BAAALgADCgMJAwAAAA==.Fizban:BAAALgADCggJFAAAAA==.',
Fl='Flaygar:BAAALgAECgYJDAAAAA==.Flory:BAABLgAECn8qAAILAAkJLhvEHgBLAgALAAkJLhvEHgBLAgAAAA==.Flowpro:BAAALgADCgMJAwAAAA==.Flyinweasle:BAAALgAECgUJBQAAAA==.',
Fo='Foundation:BAAALgAECgYJCgAAAA==.Foxxycontin:BAABLgAECn8gAAQQAAcJDxDpMAB9AQAQAAcJDxDpMAB9AQAEAAQJYAdFPgChAAARAAEJFQZ8ZgAsAAAAAA==.',
Fr='Freemay:BAAALgAECgUJBQAAAA==.Frostyrican:BAAALgAECgEJAQAAAA==.',
Fu='Fuglybaby:BAAALgAECgEJAQAAAA==.Furyofheaven:BAAALgADCgEJAQAAAA==.',
Fw='Fwakos:BAAALgADCgUJCQAAAA==.',
['Fé']='Fénnie:BAAALgADCgMJAwAAAA==.',
Ga='Gaivahros:BAABLgAECn8XAAILAAgJDQX9mgDzAAALAAgJDQX9mgDzAAAAAA==.Gakpaladin:BAABLgAECn80AAIHAAkJjRsbBQBZAgAHAAkJjRsbBQBZAgAAAA==.Galileo:BAABLgAECn8cAAIKAAcJBBZTJwDPAQAKAAcJBBZTJwDPAQAAAA==.Garland:BAAALgAECgcJDQAAAA==.',
Gd='Gdlez:BAAALgAECgEJAQAAAA==.',
Ge='Gerasstrois:BAAALgAECgcJEQABLgAECggJKAAdAOESAA==.Gerionier:BAAALgADCgEJAQABLgAECgYJFQAQAIAcAA==.Gethael:BAAALgAECgQJBQAAAA==.',
Gh='Ghalathor:BAAALgAECgQJBAAAAA==.',
Gl='Glimsy:BAAALgADCgYJCQAAAA==.Glittermilk:BAAALgADCgUJBQAAAA==.Glizzyglock:BAAALgADCgcJCwABLgAECggJLQAJAHMdAA==.',
Go='Golosan:BAABLgAECn8iAAIUAAkJJR1fCQBmAgAUAAkJJR1fCQBmAgAAAA==.Goododie:BAABLgAECn8hAAILAAYJCR9nSwCbAQALAAYJCR9nSwCbAQAAAA==.Gordil:BAAALgAECgUJBQAAAA==.Gorokan:BAAALgAECgIJAwAAAA==.',
Gr='Grayback:BAAALgAECgcJBgABLgAECgkJGAAaAJwcAA==.Grimsdeath:BAAALgADCgUJBQAAAA==.',
Gu='Guila:BAABLgAECn8eAAIcAAgJiQyGWABVAQAcAAgJiQyGWABVAQAAAA==.Gulaken:BAAALgAECgYJEQAAAA==.',
Ha='Hafnia:BAABLgAECn8UAAIQAAcJ/BjNFADkAQAQAAcJ/BjNFADkAQAAAA==.Hahkon:BAAALgADCgEJAQAAAA==.Hai:BAAALgAECgEJAQAAAA==.Halphion:BAAALgADCgYJBwABLgAECggJGwAMAOUcAA==.Hangry:BAAALgAECgEJAQAAAA==.Hanoe:BAAALgADCgYJBgAAAA==.Haoasakura:BAABLgAECn9BAAILAAkJkSNWBQAdAwALAAkJkSNWBQAdAwAAAA==.Haybuse:BAABLgAECn8nAAIOAAkJkCA2BwB0AgAOAAkJkCA2BwB0AgAAAA==.',
He='Healmd:BAAALgADCgMJAwAAAA==.Healsforhugs:BAAALgADCgMJAwAAAA==.Healzforfood:BAAALgAECgYJCQAAAA==.Healzyou:BAAALgADCgMJAwAAAA==.Heap:BAABLgAECn8sAAIZAAkJIRRoCQDqAQAZAAkJIRRoCQDqAQAAAA==.Hectavius:BAAALgAECgEJAgAAAA==.Hells:BAAALgAECgEJAQAAAA==.Hellslinger:BAAALgAECgQJBwAAAA==.Hewnoshaqa:BAABLgAECn8cAAIGAAgJ9gyTTQBfAQAGAAgJ9gyTTQBfAQAAAA==.Hexeñ:BAABLgAECn8WAAIBAAgJBRMJKgC6AQABAAgJBRMJKgC6AQAAAA==.Hexorcist:BAACLgAFFH8PAAIBAAQJchsRHQAbAQABAAQJchsRHQAbAQAuAAQKfxcAAwEACAnPGYQbADwCAAEACAnPGYQbADwCAAUAAwnVGcNaANkAAAAA.',
Hi='Hibuse:BAAALgAECgMJAwABLgAECgkJJwAOAJAgAA==.Hickerbilly:BAAALgAECgkJEAAAAA==.Higgintoot:BAAALgAECgIJAgABLgAECggJGwAOAD4PAA==.Hitormist:BAABLgAECn8eAAIDAAcJHxjLGQDRAQADAAcJHxjLGQDRAQAAAA==.',
Ho='Holyshoot:BAAALgAECgMJBQAAAA==.Holyspanks:BAAALgADCgEJAQABLgAECggJKAAPADodAA==.Hotdoog:BAAALgADCgcJDAABLgAECgQJCgAIAAAAAA==.',
Hr='Hruuli:BAAALgAECgIJAgAAAA==.',
Hu='Hungweilow:BAAALgADCgUJBgABLgAECgUJBQAIAAAAAA==.Hutsa:BAAALgADCgYJBgABLgAECggJKQALAHIYAA==.Huugar:BAABLgAECn8hAAIFAAcJrw/RLwAnAQAFAAcJrw/RLwAnAQAAAA==.Huulhai:BAAALgAECgYJDAAAAA==.',
['Hæ']='Hædés:BAABLgAECn8cAAIHAAgJthv/CADqAQAHAAgJthv/CADqAQAAAA==.',
['Hè']='Hèxén:BAAALgADCgYJBgABLgAECggJFgABAAUTAA==.',
Ib='Ibeamwork:BAAALgAECgcJEAAAAA==.',
Ic='Icyconjurer:BAAALgADCgMJAwAAAA==.',
Id='Idoworkz:BAAALgADCgcJBwABLgAECgcJEAAIAAAAAA==.',
Ii='Iiquorice:BAAALgAECgMJAwAAAA==.',
Ik='Ikazuchi:BAABLgAECn8sAAIVAAgJERjRBQDVAQAVAAgJERjRBQDVAQAAAA==.',
Il='Illcutabish:BAABLgAECn80AAIlAAkJDBzABACsAgAlAAkJDBzABACsAgAAAA==.',
Im='Imk:BAABLgAECn8kAAMaAAgJghFzQQB2AQAaAAgJghFzQQB2AQAbAAMJNAIwHwBTAAAAAA==.',
In='Ineedatarget:BAAALgADCgEJAQAAAA==.Intbuff:BAAALgAECgIJAgABLgAECgYJFQAKAJUIAA==.Invadiah:BAAALgAECgcJDQAAAA==.Invited:BAAALgAFFAEJAQAAAA==.',
Io='Iock:BAEALgAECgUJCAAAAA==.',
Ir='Ironarms:BAAALgADCgUJBQAAAA==.',
Iw='Iwdominate:BAAALgAECgYJCwAAAA==.',
Iy='Iyana:BAAALgAECgMJBgAAAA==.',
Iz='Izümi:BAABLgAECn8hAAIOAAgJbxqADgD/AQAOAAgJbxqADgD/AQAAAA==.',
Ja='Jazz:BAAALgADCgcJDgAAAA==.',
Je='Jennypoo:BAABLgAECn9BAAMKAAkJLR5QBwAJAwAKAAkJLR5QBwAJAwAhAAIJQwrRXQBKAAAAAA==.Jessd:BAAALgAECgIJBAAAAA==.',
Ji='Jild:BAAALgAECgQJBwAAAA==.Jinwoosung:BAAALgAECgYJDQAAAA==.',
Jo='Johnwarrior:BAABLgAECn8fAAISAAgJIx0PEgAaAgASAAgJIx0PEgAaAgAAAA==.Jorrix:BAABLgAECn8pAAILAAgJDRgxNADoAQALAAgJDRgxNADoAQAAAA==.',
Ju='Juduspriestt:BAABLgAECn8pAAILAAgJchgDNADoAQALAAgJchgDNADoAQAAAA==.Jurt:BAAALgADCgcJDQAAAA==.',
Ka='Kaalysto:BAAALgADCgMJAwAAAA==.Kadao:BAAALgAECgMJAwAAAA==.Kaekko:BAAALgADCgYJBgABLgAECgkJKQALAKggAA==.Kaeko:BAABLgAECn8eAAIRAAgJFxxvEACAAgARAAgJFxxvEACAAgABLgAECgkJKQALAKggAA==.Kaelathaniel:BAACLgAFFH8GAAIcAAMJ1QLuYACzAAAcAAMJ1QLuYACzAAAuAAQKfzEAAxwACAlnEeFEAI0BABwACAllEeFEAI0BAAIAAQl4Ds51AC8AAAAA.Kalerito:BAABLgAECn8sAAIKAAkJRiG9AwBYAwAKAAkJRiG9AwBYAwAAAA==.Kalistae:BAABLgAECn8gAAMRAAgJrh7TDAA3AgARAAgJrh7TDAA3AgAQAAEJ6h/GcwBZAAAAAA==.Kallivath:BAAALgADCgYJCAAAAA==.Kamdrixa:BAAALgADCgYJDAAAAA==.Kardie:BAAALgAECgUJBQAAAA==.Karinus:BAAALgADCgUJBQAAAA==.Karkaroff:BAAALgAECgcJAwABLgAECgkJGAAaAJwcAA==.Karl:BAABLgAECn8mAAIJAAgJdQoqbwBdAQAJAAgJdQoqbwBdAQAAAA==.Karlack:BAAALgADCgUJBQAAAA==.Kaserr:BAACLgAFFH8RAAIlAAUJpxzMDgBMAQAlAAUJpxzMDgBMAQAuAAQKfzAAAiUACQmCIOUCAHYDACUACQmCIOUCAHYDAAAA.Kayserdh:BAABLgAECn8UAAMiAAYJBBvhIwCeAQAiAAYJlBjhIwCeAQAaAAUJXBYVZgAHAQAAAA==.Kazaf:BAABLgAECn8VAAIfAAUJKBr7IgDlAAAfAAUJKBr7IgDlAAAAAA==.',
Ke='Keeirian:BAAALgADCgEJAQAAAA==.Keikoh:BAABLgAECn8pAAILAAkJqCANCAD4AgALAAkJqCANCAD4AgAAAA==.Keitrek:BAABLgAECn8rAAIMAAgJBgs3KgBuAQAMAAgJBgs3KgBuAQAAAA==.Kelleta:BAAALgAECgYJCQAAAA==.Kelthias:BAAALgADCgYJCgAAAA==.Kelypsoc:BAAALgAECgQJBgAAAA==.Kenichï:BAAALgAECgYJDwABLgAECggJFgABAAUTAA==.Keomag:BAAALgAECgQJBwAAAA==.Kerwîck:BAABLgAECn8fAAIMAAgJRiCkBwDQAgAMAAgJRiCkBwDQAgAAAA==.Keyen:BAABLgAECn8pAAIMAAgJjwczNgAlAQAMAAgJjwczNgAlAQAAAA==.',
Kh='Khallan:BAABLgAECn8eAAIKAAgJVwbPUQABAQAKAAgJVwbPUQABAQAAAA==.Khazsz:BAABLgAECn8ZAAMZAAYJMiK5BwA6AgAZAAYJMiK5BwA6AgAjAAMJ/RSrJACuAAAAAA==.',
Ki='Kibalion:BAAALgAECggJEAAAAA==.Kiljaezyn:BAAALgAECgEJAgAAAA==.Killbent:BAAALgAECgYJEQAAAA==.Kilowatts:BAAALgADCgYJBgAAAA==.Kimjongheäl:BAAALgAECgkJEgAAAA==.Kimjongwork:BAAALgAECgEJAQABLgAECgcJEAAIAAAAAA==.Kinnky:BAABLgAECn8dAAIJAAgJcBWRUQClAQAJAAgJcBWRUQClAQAAAA==.Kino:BAAALgAECgUJCQAAAA==.Kiratsuna:BAAALgAECgYJBwAAAA==.Kiriya:BAABLgAECn8YAAIKAAcJPgfyXADaAAAKAAcJPgfyXADaAAAAAA==.Kismiasu:BAAALgAECgYJCAAAAA==.Kitticakes:BAAALgADCgUJBQAAAA==.Kivdruid:BAACLgAFFH8HAAIKAAUJBQZuGgAqAQAKAAUJBQZuGgAqAQAuAAQKfyYAAwoACQlTHFEKANgCAAoACQlTHFEKANgCACEABAk6D3ROAHoAAAAA.Kivpriest:BAABLgAFFH8FAAMQAAMJtgfAHQB4AAAQAAIJyQrAHQB4AAAEAAEJkAEpMgA/AAABLgAFFAUJBwAKAAUGAA==.',
Kk='Kkty:BAAALgADCgQJBwAAAA==.',
Ko='Koore:BAABLgAECn8fAAIHAAgJ2hzdBgAfAgAHAAgJ2hzdBgAfAgAAAA==.Korraavatar:BAAALgAECgIJAgAAAA==.',
Kp='Kpop:BAABLgAECn8bAAIaAAgJSSNlCgC/AgAaAAgJSSNlCgC/AgAAAA==.Kpopkhan:BAABLgAECn8PAAIaAAgJSQz7awBfAQAaAAgJSQz7awBfAQAAAA==.',
Kr='Kreettip:BAABLgAECn8rAAIQAAkJ6xEDGwCmAQAQAAkJ6xEDGwCmAQAAAA==.Krispy:BAAALgADCggJEAABLgAECggJKQAKAGYZAA==.',
Ku='Kugamoo:BAABLgAECn8hAAIhAAkJqRWCHACKAQAhAAkJqRWCHACKAQAAAA==.Kulgen:BAAALgADCgIJAgAAAA==.Kurgen:BAABLgAECn8jAAILAAcJLBV+WgBzAQALAAcJLBV+WgBzAQAAAA==.',
Ky='Kylex:BAAALgAECgEJAgAAAA==.Kyuyoung:BAAALgAECgEJAQABLgAECggJKAASACMdAA==.',
['Kà']='Kàkárót:BAAALgAECgQJBAAAAA==.',
['Kí']='Kísámé:BAAALgAECgEJAQABLgAECggJIQAOAG8aAA==.',
La='Lamasacre:BAAALgAECgEJAQAAAA==.Lamiah:BAAALgAECgIJAwABLgAECgQJBAAIAAAAAA==.Lannybarby:BAABLgAECn8dAAILAAYJYwg3rADXAAALAAYJYwg3rADXAAAAAA==.Laotzu:BAABLgAECn8ZAAMPAAgJ0wi+LgBNAQAPAAcJNQm+LgBNAQAXAAgJ7AN7JwA4AQABLgAECgkJEwAIAAAAAA==.',
Lc='Lckdown:BAABLgAECn8VAAMcAAgJxB4HIQAiAgAcAAgJxB4HIQAiAgACAAEJAAD9QQAAAAAAAA==.',
Le='Legomyegolas:BAABLgAECn8eAAQGAAgJciKFEgB0AgAGAAgJciKFEgB0AgANAAMJNxpuWgDaAAAOAAEJAABRKgBdAAAAAA==.Leviticus:BAAALgADCgEJAQAAAA==.',
Li='Liara:BAAALgADCgEJAQAAAA==.Licentious:BAAALgADCgIJAgAAAA==.Lightsauce:BAAALgAECgYJCQAAAA==.Lilianis:BAAALgAECgIJAgAAAA==.Lilybloom:BAAALgAECgQJBAAAAA==.',
Lo='Loden:BAACLgAFFH8XAAIeAAUJTSCMEQBbAQAeAAUJTSCMEQBbAQAuAAQKfx8AAx4ACQk2IxAZAOYCAB4ACQk2IxAZAOYCABUAAQkAAB4oAAAAAAAA.Lodex:BAAALgAECgEJAQAAAA==.Lokthal:BAAALgADCgYJBgAAAA==.Lootzu:BAAALgAECgkJAQAAAA==.Lovi:BAABLgAECn8mAAIBAAgJfhv2GwAUAgABAAgJfhv2GwAUAgAAAA==.',
Lu='Luckyboi:BAAALgAECgYJEwAAAA==.Luckymonk:BAABLgAECn8mAAQUAAkJBw9qHACFAQAUAAkJBw9qHACFAQADAAQJMQObXABbAAAgAAIJQglTWgBZAAABLgAECgYJEwAIAAAAAA==.Lucyl:BAAALgAECgMJAwAAAA==.Lumina:BAAALgAECggJEwAAAA==.Lunaruu:BAAALgADCgEJAQAAAA==.Lusciifi:BAACLgAFFH8WAAILAAcJDCSBAwARAgALAAcJDCSBAwARAgAuAAQKfysAAgsACAn2JR0GAGwDAAsACAn2JR0GAGwDAAAA.Luvva:BAAALgAECgIJAgAAAA==.',
Ly='Lykie:BAABLgAECn8sAAIHAAkJfB8PBAB5AgAHAAkJfB8PBAB5AgAAAA==.Lykiechi:BAAALgAECgYJBgABLgAECgkJLAAHAHwfAA==.Lyllith:BAAALgADCgYJBgAAAA==.Lyone:BAABLgAECn8cAAIYAAgJgiGbBACYAgAYAAgJgiGbBACYAgAAAA==.Lyrykal:BAAALgADCgEJAQAAAA==.',
['Lú']='Lúvaa:BAACLgAFFH8FAAIeAAIJch9xeAC1AAAeAAIJch9xeAC1AAAuAAQKfywAAx4ACQlnIMkOALoCAB4ACQlnIMkOALoCAB8ABQkLH6kkABsBAAAA.',
Ma='Maahun:BAAALgAECgEJAwAAAA==.Macavity:BAAALgAECgEJAQAAAA==.Maficwar:BAABLgAECn82AAIYAAkJyh03BACkAgAYAAkJyh03BACkAgAAAA==.Mageyuwu:BAAALgAECgEJAQAAAA==.Magikkisback:BAAALgAECgcJEAAAAA==.Manarez:BAAALgAECgYJCgAAAA==.Mandorius:BAABLgAECn8VAAIGAAgJ4BaDMwC8AQAGAAgJ4BaDMwC8AQAAAA==.Manywagons:BAAALgAECgcJDQABLgAFFAkJNAAJAMciAA==.Margherita:BAAALgAECgUJBQAAAA==.Mariora:BAAALgAECgEJAQAAAA==.Marvolo:BAAALgAECgkJAQABLgAECgkJGAAaAJwcAA==.Masacre:BAAALgAECgQJCAAAAA==.Mavalynal:BAAALgADCgcJEgAAAA==.Mavdeath:BAABLgAECn8aAAMeAAkJNSHECgDhAgAeAAkJNSHECgDhAgAVAAUJpBypDAAqAQAAAA==.Mavidari:BAABLgAECn8ZAAIaAAgJDB4iIQCKAgAaAAgJDB4iIQCKAgAAAA==.',
Mc='Mchammered:BAAALgADCgMJBgAAAA==.',
Me='Meeshie:BAACLgAFFH8HAAIQAAMJyBJOEwDWAAAQAAMJyBJOEwDWAAAuAAQKfy0ABBAACAlkGjwQAGQCABAACAlkGjwQAGQCABEABwnjC9gpAC0BAAQABQngEoU3AMoAAAAA.Meleys:BAAALgADCgcJCAAAAA==.',
Mi='Midoriya:BAACLgAFFH8UAAQcAAUJ0CZdCgDKAQAcAAQJ0CZdCgDKAQAdAAIJNCbOBwBwAAACAAEJNhdjEwBYAAAuAAQKfycABBwACQlAJloGAAADABwABwkUJloGAAADAAIAAwn5JZchAEgBAB0AAgmBJh8gAHIAAAAA.Mightyhunts:BAAALgAECgQJBQAAAA==.Mikearuba:BAAALgAECgQJBAAAAA==.Mikuzume:BAAALgAECgYJEQAAAA==.Milkmage:BAABLgAECn8oAAIJAAkJhx3QFgCYAgAJAAkJhx3QFgCYAgAAAA==.Mintt:BAAALgAECgEJAQAAAA==.Mistypaksz:BAABLgAECn8VAAMDAAgJERouDwBIAgADAAgJERouDwBIAgAgAAIJwA5dWgBZAAAAAA==.Miznewbooty:BAABLgAECn8rAAMEAAkJpg8gEwDwAQAEAAkJpg8gEwDwAQARAAQJog5ZRADaAAAAAA==.',
Mo='Moggark:BAAALgADCggJEgAAAA==.Monknack:BAAALgAECgYJCQAAAA==.Moondofrond:BAAALgAECgUJBgAAAA==.Moonq:BAABLgAECn8jAAIKAAgJmwYKUwD9AAAKAAgJmwYKUwD9AAAAAA==.Moorti:BAABLgAECn8VAAMJAAYJ/RspbgBfAQAJAAYJ/RspbgBfAQAkAAEJww7zHAA5AAAAAA==.Moosaurus:BAABLgAECn8mAAIbAAkJaRO0BwCsAQAbAAkJaRO0BwCsAQAAAA==.Mosrael:BAAALgADCgEJAgAAAA==.',
Mu='Muerte:BAAALgAECgIJAgABLgAECggJIAAZABkWAA==.Muffy:BAABLgAECn8bAAIXAAgJjxHbDAC6AQAXAAgJjxHbDAC6AQAAAA==.Muggyx:BAAALgADCgUJBQAAAA==.Multishoted:BAAALgADCgEJAQAAAA==.Murlouh:BAAALgADCgUJCAAAAA==.Mushudoobey:BAAALgAECgIJAgABLgAECgkJJwAJAIchAA==.',
My='Mylthrad:BAAALgADCgMJAwAAAA==.Mythnarra:BAACLgAFFH8SAAMbAAQJdyWAAAC5AQAbAAQJdyWAAAC5AQAaAAEJUgdJbgBEAAAuAAQKfzMAAxsACQn0JTEAAGQDABsACQn0JTEAAGQDABoABgk/HDE4AJkBAAAA.',
['Mí']='Mísanthrope:BAAALgAECgUJDgAAAA==.',
['Mô']='Mônster:BAAALgAECgUJCQAAAA==.',
['Mö']='Mönk:BAACLgAFFH8FAAIDAAMJthfmCgD7AAADAAMJthfmCgD7AAAuAAQKfx8AAgMACAmsHs0MAIYCAAMACAmsHs0MAIYCAAAA.',
['Mø']='Mønstèr:BAAALgAECgcJDAAAAA==.',
Na='Nachtimbess:BAAALgADCgYJBgABLgAFFAIJAwAIAAAAAA==.Nadaline:BAAALgADCgcJBwAAAA==.Nadíne:BAACLgAFFH8KAAIJAAMJzhX/UQABAQAJAAMJzhX/UQABAQAuAAQKfxwAAgkACQkSHkRDAG4CAAkACQkSHkRDAG4CAAAA.Naha:BAAALgAECgkJBwAAAA==.Naimi:BAABLgAECn8VAAMKAAYJcxWrOQBnAQAKAAYJcxWrOQBnAQAhAAQJeQriQgCqAAAAAA==.Nanukimon:BAABLgAECn8gAAMTAAcJExfMCwCMAQATAAcJExfMCwCMAQABAAYJQwtxVAD6AAAAAA==.Nastymcdirty:BAAALgADCgcJBwAAAA==.',
Ne='Nedgamingttv:BAEALgAECgkJCQAAAA==.Nelivath:BAAALgAECgEJAQAAAA==.Nene:BAABLgAFFH8HAAIJAAIJkhE/cQClAAAJAAIJkhE/cQClAAAAAA==.Nevaera:BAABLgAECn8XAAIJAAcJBg6veABJAQAJAAcJBg6veABJAQAAAA==.',
Ni='Nichan:BAAALgAECgEJAwAAAA==.Nick:BAACLgAFFH8iAAMeAAcJFRl5BwANAgAeAAYJFRl5BwANAgAfAAEJAABlMQAAAAAuAAQKfzQAAh4ACQlVJP4EAIQDAB4ACQlVJP4EAIQDAAAA.Nightcraft:BAAALgAECgEJAQAAAA==.Nightshine:BAAALgAECgcJEQAAAA==.Nikor:BAABLgAECn8bAAIHAAYJ3h2LDQCTAQAHAAYJ3h2LDQCTAQAAAA==.Nisan:BAAALgADCgcJBwAAAA==.',
No='Noah:BAAALgAECgIJAgAAAA==.Nocabevoli:BAAALgADCgUJBQABLgAECgIJAwAIAAAAAA==.Nokorii:BAABLgAECn8hAAIQAAYJsRQFIwBiAQAQAAYJsRQFIwBiAQAAAA==.Nomecoma:BAAALgAECgQJAQAAAA==.Nomercy:BAAALgAECgEJAQAAAA==.Norgatha:BAAALgAECgUJCwAAAA==.Notches:BAAALgAECgQJBwAAAA==.Nowheres:BAAALgAECgIJAwABLgAECgUJEgAIAAAAAA==.Noxturn:BAABLgAECn8VAAIGAAgJtBFGUQB1AQAGAAgJtBFGUQB1AQAAAA==.',
Nu='Nuikang:BAAALgAECgEJAQAAAA==.',
Ny='Nyxx:BAABLgAECn8VAAMmAAgJ0BvRAwAdAgAmAAgJ0BvRAwAdAgAnAAEJXAVIDwAsAAABLgAECgUJCQAIAAAAAA==.',
['Nè']='Nèlo:BAABLgAECn8eAAIYAAgJWgwpGQAiAQAYAAgJWgwpGQAiAQAAAA==.',
Oc='Oceansoul:BAABLgAECn8hAAMdAAgJWyDzAgAvAgAdAAgJNSDzAgAvAgAcAAUJcRoQSgB+AQAAAA==.',
Oh='Ohh:BAAALgADCgMJAQAAAA==.Ohthathurtu:BAAALgADCgEJAQAAAA==.',
Ok='Ok:BAAALgADCgYJCgAAAA==.',
On='Ondestra:BAAALgAECgIJAgAAAA==.Onlytoez:BAAALgADCggJCAABLgAFFAMJBwAQAMgSAA==.',
Op='Ophanym:BAAALgADCgEJAQAAAA==.Oppenheimerx:BAAALgADCgMJBQAAAA==.',
Or='Orave:BAABLgAECn8VAAIQAAYJ9x50EgAAAgAQAAYJ9x50EgAAAgAAAA==.Origin:BAAALgAECgIJAwABLgAECgcJFAADAB4bAA==.Orionah:BAAALgAECggJDgAAAA==.',
Os='Ostena:BAAALgAECgIJAgAAAA==.Osymonka:BAAALgADCgYJBgABLgAFFAIJAwAIAAAAAA==.Osywar:BAAALgAECgYJEwABLgAFFAIJAwAIAAAAAA==.',
Ou='Oulawdpriest:BAACLgAFFH8UAAIRAAYJYQzABwCFAQARAAYJYQzABwCFAQAuAAQKfzgABBEACAneHksMAL4CABEACAneHksMAL4CAAQABAkEIO0gAGgBABAAAgkGFXFzAFoAAAAA.',
Ov='Overture:BAABLgAECn8ZAAMKAAYJmg2SWADpAAAKAAYJmg2SWADpAAAhAAUJjxOfQACzAAAAAA==.',
Pa='Palaslap:BAAALgADCgMJAwAAAA==.Pallyrican:BAAALgADCgQJBAAAAA==.Panacea:BAAALgAECgYJCQABLgAECgcJBwAIAAAAAA==.Parkour:BAABLgAECn8XAAIaAAcJ2RmKTABQAQAaAAcJ2RmKTABQAQAAAA==.Pastorale:BAAALgADCgYJBgABLgAECgkJEwAIAAAAAA==.Patata:BAAALgADCgIJAgAAAA==.Paully:BAAALgAECgQJBgAAAA==.Paullymorph:BAABLgAECn8hAAIJAAkJCyHUGACLAgAJAAkJCyHUGACLAgAAAA==.Pawpawbear:BAAALgADCgEJAQAAAA==.Payal:BAAALgADCgQJBAABLgAFFAUJDAAcAMkMAA==.',
Pe='Pewpewkitti:BAAALgADCgUJBQAAAA==.',
Ph='Phenyl:BAABLgAECn8fAAIDAAkJEA0UIACaAQADAAkJEA0UIACaAQAAAA==.Pheurton:BAAALgAECgkJBwAAAA==.',
Pi='Pintobeans:BAAALgAECgcJBwAAAA==.Pithers:BAAALgAECgQJBgAAAA==.',
Pl='Plasmor:BAAALgAECggJDAAAAA==.',
Po='Ponchohunter:BAAALgADCgEJAQAAAA==.Pooh:BAAALgADCgEJAQABLgAECgcJHgADAB8YAA==.Poohpocket:BAAALgADCgQJAwAAAA==.Popkorn:BAACLgAFFH8kAAMaAAcJ1yDdAQCJAgAaAAYJ1yDdAQCJAgAbAAEJAAAQBABqAAAuAAQKfx8ABBoACAmSJrYQAPgCABoACAlZJLYQAPgCACIABQmUIb4qAHABABsAAQlnJW4iAG8AAAAA.Popkornvoke:BAAALgAFFAEJAQABLgAFFAcJJAAaANcgAA==.Poplocks:BAAALgADCgIJAwABLgAECgYJCQAIAAAAAA==.Porrana:BAABLgAECn8iAAMSAAcJtiHvEQAbAgASAAcJVyHvEQAbAgAoAAEJIx0aRABPAAAAAA==.Powaqa:BAABLgAECn82AAICAAgJaAMPFwCzAAACAAgJaAMPFwCzAAAAAA==.',
Ps='Psy:BAAALgAECggJEwAAAA==.',
Pu='Pumpkinspice:BAAALgAECgUJBQAAAA==.Punchkin:BAABLgAECn8bAAMDAAkJEheEEwASAgADAAkJEheEEwASAgAgAAEJWwJViQAmAAAAAA==.Purify:BAAALgAECgQJBQABLgAFFAUJFAADAColAA==.Puzzledmonk:BAAALgADCgcJDQAAAA==.',
Qu='Quasient:BAAALgAECgQJBAAAAA==.Quickspell:BAABLgAECn8iAAIJAAkJvh7yHQBtAgAJAAkJvh7yHQBtAgAAAA==.Quickstep:BAAALgAECgkJBwAAAA==.',
Ra='Rabidpopcorn:BAAALgADCgcJBwAAAA==.Radaghast:BAABLgAECn8gAAIZAAgJGRbWCwC4AQAZAAgJGRbWCwC4AQAAAA==.Raedyyn:BAABLgAECn8dAAIPAAgJCBAxJQBgAQAPAAgJCBAxJQBgAQAAAA==.Ragarth:BAAALgAECgYJCQAAAA==.Ragendecay:BAABLgAECn8eAAIeAAgJRxQOSwCaAQAeAAgJRxQOSwCaAQAAAA==.Ragequits:BAACLgAFFH8XAAMSAAcJ2R83AABcAgASAAYJRCM3AABcAgAoAAIJQRQUCgBbAAAuAAQKfzEAAxIACQnDJpgAAN4DABIACQmtJpgAAN4DACgACQkuIjABACEDAAAA.Ragæ:BAAALgAFFAEJAQAAAA==.Rakshassa:BAABLgAECn8XAAIGAAgJ0BjtNQCyAQAGAAgJ0BjtNQCyAQAAAA==.Ralcar:BAABLgAECn8aAAIaAAYJ1yACLQDKAQAaAAYJ1yACLQDKAQAAAA==.Ratsnart:BAAALgAECgQJBQABLgAFFAEJAwAIAAAAAA==.Razrscale:BAAALgAECgUJBQAAAA==.',
Re='Redhuntsman:BAAALgAECgIJBAAAAA==.Regrow:BAABLgAECn8VAAMKAAYJlQjxawCtAAAKAAYJlQjxawCtAAAZAAUJrQhGLAB4AAAAAA==.Renstrider:BAAALgAECgUJBwAAAA==.',
Rh='Rheas:BAAALgAECgIJAQAAAA==.Rholdentodor:BAAALgADCgUJBQABLgAECgcJCQAIAAAAAA==.',
Ro='Rockabye:BAAALgAECgUJBQABLgAFFAQJDQAeAGQRAA==.Rockstar:BAAALgAECgUJBQAAAA==.Rohra:BAABLgAECn8tAAIKAAgJqA6ROQBnAQAKAAgJqA6ROQBnAQAAAA==.Rombaz:BAAALgAFFAIJBAAAAA==.Ronspoomage:BAAALgADCgkJEQAAAA==.Rosemary:BAAALgADCgQJBAAAAA==.Roybi:BAAALgADCgEJAQAAAA==.Roóz:BAAALgAECgQJEQAAAA==.',
Ru='Ruah:BAAALgAECgEJAQAAAA==.Ruenarn:BAAALgAECgEJAQAAAA==.Runecast:BAAALgADCgcJFQAAAA==.',
Ry='Rynk:BAABLgAECn8yAAIUAAkJTCZbAAB3AwAUAAkJTCZbAAB3AwAAAA==.Rynkidari:BAAALgAECgkJCQABLgAECgkJMgAUAEwmAA==.Ryuoxel:BAAALgAFFAEJAQAAAA==.',
['Rá']='Rágnarok:BAAALgADCgMJAwAAAA==.Ráwkfist:BAABLgAFFH8PAAIPAAUJyxvYEwBNAQAPAAUJyxvYEwBNAQAAAA==.',
Sa='Sabbybunnee:BAAALgADCgcJDAAAAA==.Sabertrek:BAAALgADCgMJAwAAAA==.Saelyrinth:BAAALgADCgUJCAAAAA==.Saltybonez:BAAALgADCgUJBQAAAA==.Sambor:BAABLgAECn8bAAIKAAkJ7wl6QwA5AQAKAAkJ7wl6QwA5AQAAAA==.Sarapheena:BAABLgAECn8nAAIBAAkJ2hR+JgDPAQABAAkJ2hR+JgDPAQAAAA==.Saravian:BAAALgADCgUJBQAAAA==.Sardeench:BAAALgAECgEJAQAAAA==.Satanbomb:BAAALgAECgEJAgAAAA==.Satansbride:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.Saterli:BAACLgAFFH8KAAIQAAQJiQwEEAD+AAAQAAQJiQwEEAD+AAAuAAQKfzgAAxAACQkJHFkFAOgCABAACQkJHFkFAOgCABEABgmTA5JEAKEAAAAA.Saturno:BAAALgAECggJEgAAAA==.Saucypirate:BAABLgAECn8dAAIJAAgJjQ4scwBUAQAJAAgJjQ4scwBUAQAAAA==.Saulgoodman:BAAALgADCgMJAwAAAA==.Sauronknight:BAABLgAFFH8NAAIeAAQJZBFEQgA0AQAeAAQJZBFEQgA0AQAAAA==.',
Sc='Scalvert:BAAALgAECgcJCQAAAA==.Scalypanda:BAABLgAECn8nAAMPAAkJRRMYGADHAQAPAAkJRRMYGADHAQAWAAIJ0gzZNABuAAAAAA==.Scamander:BAABLgAECn8YAAIaAAkJnBwMDwCLAgAaAAkJnBwMDwCLAgAAAA==.Scarléth:BAAALgADCggJCgAAAA==.Scoobs:BAAALgAECgUJDgAAAA==.Scorpinom:BAAALgADCgQJBAAAAA==.Sculi:BAAALgADCgcJBwAAAA==.Scurge:BAAALgAECgIJAgAAAA==.Scuttle:BAAALgADCgIJBgABLgAECgcJHgADAB8YAA==.',
Se='Sei:BAAALgADCgIJAgAAAA==.Seiishiro:BAABLgAECn8mAAMhAAgJFQjYLwAFAQAhAAgJFQjYLwAFAQAKAAEJTATf4gAiAAAAAA==.Seldon:BAABLgAECn8lAAILAAgJbR2QIABAAgALAAgJbR2QIABAAgAAAA==.Semiosphere:BAAALgAECgkJAgAAAA==.Sennistian:BAAALgADCgMJBAABLgAECggJKAAdAOESAA==.Senyor:BAABLgAECn8qAAIHAAgJEhv7BwACAgAHAAgJEhv7BwACAgAAAA==.Seraphiel:BAABLgAECn8VAAMQAAYJgBzzFwDEAQAQAAYJZRvzFwDEAQAEAAUJChMjKwAdAQAAAA==.Seraphymm:BAAALgAECgcJEQAAAA==.',
Sh='Shacklebolt:BAABLgAECn8mAAMcAAgJSBnzJAB/AgAcAAgJSBnzJAB/AgACAAQJWg+9MwDoAAABLgAECgkJGAAaAJwcAA==.Shadowsneak:BAABLgAECn8gAAImAAYJlwxhDQAPAQAmAAYJlwxhDQAPAQAAAA==.Shaelistra:BAABLgAECn8kAAIjAAgJjBesCADgAQAjAAgJjBesCADgAQAAAA==.Shalai:BAAALgADCggJDgAAAA==.Shalilama:BAACLgAFFH8UAAIBAAQJYR1qGgApAQABAAQJYR1qGgApAQAuAAQKf0cAAgEACQnUJcgAALQDAAEACQnUJcgAALQDAAAA.Shamanana:BAAALgAECgYJCwAAAA==.Shamboli:BAAALgADCgUJBQAAAA==.Shanazure:BAABLgAECn8oAAMPAAgJOh3QFADpAQAPAAgJcxrQFADpAQAWAAcJGBlBEwCvAQAAAA==.Sheikai:BAAALgADCgkJHwAAAA==.Shenderp:BAABLgAECn8iAAMQAAYJVRFNKwAmAQAQAAYJVRFNKwAmAQARAAIJowJwWwBIAAAAAA==.Shinerbock:BAABLgAECn8gAAMDAAgJkQ43NgAEAQADAAcJIgw3NgAEAQAgAAEJFQc3eQAsAAAAAA==.Shivä:BAAALgADCgcJCgABLgAECggJIgAFACsWAA==.Shriven:BAAALgAECgIJAgAAAA==.',
Si='Sianvar:BAAALgAECggJDQAAAA==.Silastraza:BAAALgAFFAEJAQAAAA==.Silvanus:BAAALgAECgMJAwAAAA==.Silverjustis:BAABLgAECn8pAAILAAgJCwjWeAAxAQALAAgJCwjWeAAxAQAAAA==.Siwe:BAABLgAECn8nAAQTAAgJfB86BQA9AgATAAgJfB86BQA9AgABAAcJVR2AGgAhAgAFAAEJpBJkgwA8AAAAAA==.',
Sk='Skadoosh:BAABLgAECn8cAAIgAAgJMyLMBgCbAgAgAAgJMyLMBgCbAgAAAA==.Skribblez:BAABLgAECn8eAAMMAAgJvSGjFAAdAgAMAAYJPCGjFAAdAgALAAgJnx9tQwAaAgAAAA==.Skrilled:BAABLgAECn8oAAIGAAYJSxF/ZwAYAQAGAAYJSxF/ZwAYAQAAAA==.',
Sl='Slackback:BAAALgAECgkJBAABLgAFFAQJEQAFALQaAA==.Sloot:BAAALgAECgYJDgAAAA==.Slughorn:BAAALgAECgcJBQABLgAECgkJGAAaAJwcAA==.Slyv:BAAALgADCgcJBwAAAA==.',
Sm='Smellidan:BAAALgADCgEJAwAAAA==.Smïte:BAAALgAECgUJEgAAAA==.Smïtë:BAAALgAECgUJCQAAAA==.',
Sn='Snape:BAAALgAECgYJBgAAAA==.Snowcones:BAAALgAECgcJDwAAAA==.Snowman:BAAALgAECgMJBQAAAA==.Snw:BAAALgAECgcJEwAAAA==.',
So='Solerage:BAAALgAECgYJDAABLgAECgkJJwAWALwkAA==.Sophielloyd:BAAALgAECgQJBAAAAA==.Soul:BAACLgAFFH8KAAIjAAMJNB1rBQAeAQAjAAMJNB1rBQAeAQAuAAQKfxwAAiMACQlwIdAEAMoCACMACQlwIdAEAMoCAAAA.Soulls:BAAALgAECgIJAgAAAA==.Soulsy:BAAALgAECgEJAgAAAA==.Sourgrip:BAABLgAECn8kAAIVAAkJShmdBAAKAgAVAAkJShmdBAAKAgAAAA==.',
Sp='Spanx:BAAALgADCgIJAgAAAA==.Splendorae:BAABLgAECn8nAAIMAAkJqhShIwAFAgAMAAkJqhShIwAFAgAAAA==.Sprints:BAABLgAECn8wAAIBAAgJQxj5GgAcAgABAAgJQxj5GgAcAgAAAA==.Spritz:BAAALgAECgEJAQAAAA==.Sprylf:BAAALgADCgMJBAAAAA==.Spwany:BAABLgAECn8WAAQSAAgJ3wqiNgAdAQASAAcJfwWiNgAdAQAYAAUJoA0WKgDwAAAoAAEJAAA3XgAAAAAAAA==.Spyderelite:BAACLgAFFH8FAAICAAMJrwPnBwC/AAACAAMJrwPnBwC/AAAuAAQKfyoAAgIACAmpFbwFALoBAAIACAmpFbwFALoBAAAA.',
Sq='Squeekems:BAAALgAECgIJAwAAAA==.Squirrel:BAABLgAECn8cAAIGAAkJkhrmFABhAgAGAAkJkhrmFABhAgAAAA==.',
St='Stainedhero:BAAALgADCgEJAQAAAA==.Stankstarstu:BAAALgAECgUJBQAAAA==.Starspeaker:BAABLgAECn8gAAMKAAcJfAY9WwDgAAAKAAcJfAY9WwDgAAAhAAIJiwPfdwBFAAAAAA==.Starykniight:BAAALgADCgMJAwABLgAECgcJHgADAB8YAA==.Steveaustin:BAAALgAECgcJEgABLgAECgcJHgADAB8YAA==.Stinkypeen:BAAALgAECgIJAgAAAA==.Stonecypher:BAAALgAECgYJEgAAAA==.Stoogotz:BAAALgADCgYJCAAAAA==.Stormlesbian:BAAALgADCgUJBQAAAA==.',
Su='Suhe:BAAALgADCggJFQAAAA==.Sundaresh:BAAALgADCgUJBwAAAA==.Sunwing:BAABLgAECn8nAAIQAAkJRhySDwBqAgAQAAkJRhySDwBqAgAAAA==.Sutileza:BAAALgADCgMJAwABLgAECgYJGQAKAJoNAA==.Suvien:BAAALgAECgUJDAAAAA==.',
Sw='Swagette:BAAALgADCgcJBwAAAA==.Swingkitti:BAAALgAECgYJEAAAAA==.',
Sx='Sxtitan:BAAALgAECggJEQAAAA==.',
Sy='Sylvarian:BAABLgAECn8fAAIpAAgJ6g9QAwCNAQApAAgJ6g9QAwCNAQAAAA==.Synareth:BAAALgAECgEJAgAAAA==.Syrodeus:BAAALgAECgQJBAAAAA==.',
Sz='Szz:BAABLgAECn8nAAIWAAkJvCRmAAA9AwAWAAkJvCRmAAA9AwAAAA==.',
['Sÿ']='Sÿn:BAAALgADCgcJFwAAAA==.',
Ta='Taelgar:BAAALgAECgcJEgAAAA==.Tanthalos:BAAALgAECgQJCgABLgAECggJGwAOAD4PAA==.Targaryenelf:BAAALgADCgMJBAAAAA==.Taterdotz:BAAALgAECggJEwAAAA==.Tatortwats:BAABLgAECn8WAAIkAAcJhRhYAwCwAQAkAAcJhRhYAwCwAQAAAA==.Tatyrra:BAAALgADCgUJBQAAAA==.Tayswift:BAAALgADCgQJBAABLgAECgUJFgAIAAAAAA==.',
Te='Tenast:BAAALgADCgIJAgAAAA==.Tepicoyotl:BAABLgAECn8mAAIBAAgJIBB7OQBpAQABAAgJIBB7OQBpAQAAAA==.',
Th='Thaymor:BAAALgADCgkJIQAAAA==.Thelonecone:BAACLgAFFH8PAAMVAAQJhBaoBQApAQAVAAQJgBOoBQApAQAeAAQJlQ8gJQABAQAuAAQKf08AAxUACQl7I8sAABUDABUACQlZIssAABUDAB4ACAkfIooVAPsCAAAA.Theoganth:BAAALgAECgYJBgAAAA==.Theraphee:BAAALgADCgcJEwAAAA==.Therimor:BAABLgAECn8YAAMBAAcJoQgpXQDaAAABAAYJZgkpXQDaAAAFAAEJHwFtiwAVAAAAAA==.Theronshan:BAAALgADCggJGQAAAA==.Thevoid:BAAALgAECgkJEwAAAA==.Thoghas:BAAALgADCgYJBgAAAA==.Thomwizard:BAAALgAECgMJAwAAAA==.Thongrin:BAAALgADCgcJBwAAAA==.Thormorn:BAAALgADCgEJAgAAAA==.Thornarlenan:BAAALgADCgkJDgAAAA==.Thunnha:BAACLgAFFH8JAAIcAAMJlSHJMwAoAQAcAAMJlSHJMwAoAQAuAAQKfycAAxwACAn5I3ELAMMCABwACAn5I3ELAMMCAAIAAQkcG1dmAEMAAAAA.Thurlando:BAAALgADCgIJBAAAAA==.',
Ti='Tierali:BAAALgAECgQJBwAAAA==.',
To='Toastedsushi:BAAALgAECgYJEQAAAA==.Toetagg:BAAALgAECgIJAwAAAA==.Toobooku:BAAALgADCgEJAQAAAA==.Toodamsirius:BAAALgAECgIJAgAAAA==.Toofwess:BAAALgADCgkJCQABLgAECgcJHgADAB8YAA==.Toribia:BAAALgAECgQJBAAAAA==.Torí:BAAALgADCgYJCAAAAA==.Tosala:BAAALgAECgYJEQAAAA==.Totemkiller:BAABLgAECn8lAAIFAAgJYhFuJwBaAQAFAAgJYhFuJwBaAQAAAA==.Totemtwiddlr:BAABLgAECn8UAAIFAAgJuRzIFAB3AgAFAAgJuRzIFAB3AgABLgAFFAEJAwAIAAAAAA==.Totezmcgoats:BAAALgADCgYJDAAAAA==.',
Tr='Traael:BAABLgAECn8nAAIGAAgJCRrlMADGAQAGAAgJCRrlMADGAQAAAA==.Trashbeard:BAAALgADCgIJAgAAAA==.Treebranch:BAAALgAECgEJAgAAAA==.Treesap:BAABLgAECn8nAAInAAkJrxp6AQDHAgAnAAkJrxp6AQDHAgAAAA==.Trinityeve:BAAALgAECgQJCAAAAA==.Trnz:BAAALgAFFAEJAQABLgAFFAEJAwAIAAAAAA==.Trnzlock:BAAALgAFFAEJAwAAAA==.',
Tu='Tulanii:BAAALgADCgMJAgAAAA==.Tularana:BAABLgAECn8kAAIJAAkJvhlwIwBQAgAJAAkJvhlwIwBQAgABLgAFFAIJAwAIAAAAAA==.Tumble:BAABLgAECn8VAAMRAAgJrwfGLwALAQARAAgJrwfGLwALAQAEAAEJCgEIYQAcAAAAAA==.Tummyissues:BAAALgAECgIJAgAAAA==.Tums:BAAALgAECgQJCQAAAA==.',
Tw='Twignberryz:BAAALgADCgcJCQABLgAECgUJBQAIAAAAAA==.Twinkie:BAABLgAECn8VAAIcAAgJ5QhGjgA8AQAcAAgJ5QhGjgA8AQAAAA==.Twodogz:BAABLgAECn8pAAIGAAgJSyFZEACGAgAGAAgJSyFZEACGAgAAAA==.',
Ty='Tyious:BAABLgAECn8oAAMeAAkJDByyLAAGAgAeAAkJDByyLAAGAgAfAAYJCAuRLADaAAAAAA==.Tyndara:BAABLgAECn8kAAILAAgJkhEZTwCRAQALAAgJkhEZTwCRAQAAAA==.',
['Tü']='Tüesdaÿ:BAAALgAECgcJCwAAAA==.',
Uc='Uchihazephyr:BAAALgADCgIJAgABLgAFFAQJFAABAGEdAA==.',
Un='Unbeat:BAAALgAECggJDwAAAA==.Unbeliever:BAAALgAECggJEAAAAA==.Unhoe:BAAALgADCggJEgAAAA==.Unholussie:BAACLgAFFH8NAAIeAAQJLgxWRgAsAQAeAAQJLgxWRgAsAQAuAAQKfzAAAh4ACQl+HIAcAFgCAB4ACQl+HIAcAFgCAAAA.Unholybowner:BAAALgADCgcJDAAAAA==.Unstablè:BAAALgAECgUJCQAAAA==.',
Ur='Ursane:BAACLgAFFH8FAAISAAMJqQqbIwDTAAASAAMJqQqbIwDTAAAuAAQKfyoAAhIACQmaG74OAD8CABIACQmaG74OAD8CAAAA.Ursully:BAABLgAECn8kAAIZAAgJPB4IBgBFAgAZAAgJPB4IBgBFAgAAAA==.',
Uz='Uzi:BAAALgAECgYJEQAAAA==.',
Va='Vaardux:BAABLgAECn8bAAMMAAgJ5RyQDgBjAgAMAAgJ5RyQDgBjAgALAAYJPiIWWADaAQAAAA==.Vaelithra:BAAALgADCgEJAQAAAA==.Vaesyth:BAAALgADCgYJBgAAAA==.Valamarl:BAAALgADCgcJCAAAAA==.Valkeria:BAAALgAECgQJBQAAAA==.Valíthria:BAAALgAECgYJDAAAAA==.Vampulla:BAABLgAECn8mAAIaAAkJwAl1TQBNAQAaAAkJwAl1TQBNAQAAAA==.Vanncint:BAAALgAECgQJBAAAAA==.Vanndrygos:BAABLgAECn8YAAIPAAgJOgg+MQAYAQAPAAgJOgg+MQAYAQAAAA==.Varea:BAAALgAECgIJAgAAAA==.Vashie:BAAALgAECggJEQAAAA==.Vathan:BAAALgAECgEJAgAAAA==.',
Ve='Veigar:BAAALgAECgcJDgABLgAFFAYJHQANAEMmAA==.Velanis:BAAALgADCgUJBwAAAA==.Velmir:BAAALgAECgkJBwAAAA==.Velorius:BAAALgAECgEJAgAAAA==.Venmo:BAAALgAECgEJAQAAAA==.Vexus:BAACLgAFFH8RAAIFAAQJtBoPDgBQAQAFAAQJtBoPDgBQAQAuAAQKfyYAAgUACAmXI8MJAPcCAAUACAmXI8MJAPcCAAAA.Vexuss:BAAALgAECgkJAgABLgAFFAQJEQAFALQaAA==.',
Vi='Vidya:BAAALgADCgMJAwAAAA==.Vivifyght:BAAALgAECgIJAgAAAA==.',
Vl='Vladios:BAAALgAECgYJCgAAAA==.',
Vo='Voidwraith:BAAALgADCgEJAQAAAA==.Vordarian:BAABLgAECn8kAAQDAAkJiAxGJAB4AQADAAkJiAxGJAB4AQAUAAMJmgFTXQBeAAAgAAEJ3AlweAAsAAAAAA==.',
Vy='Vynciaagn:BAAALgADCgcJEgAAAA==.',
Wa='Wafflehouse:BAABLgAECn8YAAIeAAgJCB12KwALAgAeAAgJCB12KwALAgAAAA==.Walolas:BAAALgADCgcJEAAAAA==.Wamiya:BAAALgAECgEJAgAAAA==.Warbatt:BAAALgADCggJCAAAAA==.Watchmeburst:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgAECgcJCgAAAA==.',
Wh='Whaler:BAABLgAECn8lAAISAAgJAiQ9CQCKAgASAAgJAiQ9CQCKAgAAAA==.Whìndy:BAAALgAECgQJBgABLgAECgYJFQAKAJUIAA==.',
Wi='Wildspanks:BAAALgADCgYJCQAAAA==.',
Wo='Wowoo:BAAALgAECgcJCAAAAA==.',
Wu='Wuzntmyfault:BAAALgAECgEJAQABLgAECgYJFQAKAJUIAA==.',
Xe='Xenos:BAAALgAECgIJBAAAAA==.Xenyodk:BAABLgAECn8mAAIeAAkJeCFaCQDvAgAeAAkJeCFaCQDvAgAAAA==.Xenyovoker:BAAALgAECgkJCwAAAA==.',
Xi='Xideris:BAABLgAECn81AAIXAAkJliItAQBtAwAXAAkJliItAQBtAwAAAA==.Xiderís:BAAALgAECgYJBgAAAA==.',
Xt='Xtraxtra:BAABLgAECn8pAAMKAAgJZhm/HABWAgAKAAgJZhm/HABWAgAhAAgJ6Q4dIwBVAQAAAA==.',
Ya='Yaku:BAAALgAECgUJCAAAAA==.',
Ye='Yetzi:BAAALgADCgIJAgAAAA==.Yetzibel:BAAALgADCgQJBAAAAA==.',
Yo='Yoan:BAAALgAFFAMJBgAAAQ==.Yoga:BAABLgAECn8UAAIDAAcJHhsLEwAYAgADAAcJHhsLEwAYAgAAAA==.Yonicbonnet:BAABLgAECn8cAAIKAAgJGQpiRQAxAQAKAAgJGQpiRQAxAQAAAA==.Yoondo:BAAALgAECgUJCgAAAA==.Yorde:BAAALgADCgcJBwAAAA==.',
Ys='Ysandrell:BAAALgADCgMJAwAAAA==.Yshtola:BAABLgAECn8cAAIBAAkJqRVGFQBMAgABAAkJqRVGFQBMAgAAAA==.',
Yu='Yuffie:BAAALgAECgQJBAAAAA==.Yunara:BAACLgAFFH8KAAIaAAMJpR+eMQARAQAaAAMJpR+eMQARAQAuAAQKfzIAAhoACQnVH7kIANMCABoACQnVH7kIANMCAAEuAAUUBgkdAA0AQyYA.Yunge:BAAALgADCgQJBAAAAA==.',
Za='Zabra:BAAALgAECgYJEgAAAA==.Zachpally:BAAALgADCgUJBQAAAA==.Zahvoker:BAABLgAECn8VAAIWAAYJ3AjHDQDrAAAWAAYJ3AjHDQDrAAAAAA==.Zapkitti:BAAALgADCgQJBAAAAA==.Zareline:BAAALgAECgQJBgAAAA==.Zathaeus:BAABLgAECn8rAAIaAAkJpRXEJAD0AQAaAAkJpRXEJAD0AQAAAA==.Zaylian:BAABLgAECn8oAAIiAAkJUxlYCgAkAgAiAAkJUxlYCgAkAgAAAA==.Zayragossa:BAACLgAFFH8KAAIcAAMJERk8RAD9AAAcAAMJERk8RAD9AAAuAAQKfxgAAhwACAn/HuEcADoCABwACAn/HuEcADoCAAAA.',
Ze='Zeerkk:BAABLgAECn8vAAIcAAkJyBjJHQA0AgAcAAkJyBjJHQA0AgAAAA==.Zelanta:BAAALgADCgQJBAAAAA==.Zenderal:BAAALgADCgcJBwABLgAFFAQJFAABAGEdAA==.Zergmark:BAAALgADCgMJAwAAAA==.Zero:BAAALgADCgIJAgAAAA==.',
Zo='Zoomzoom:BAAALgAECgUJBQABLgAFFAYJFAARAGEMAA==.Zouris:BAAALgAECgUJCQAAAA==.',
Zt='Ztaziki:BAAALgADCgQJBAAAAA==.',
Zu='Zulkraa:BAAALgAECgUJCwAAAA==.Zulmex:BAAALgAECgYJCwAAAA==.Zunda:BAAALgAECgkJBwAAAA==.Zurtogg:BAABLgAECn8eAAMSAAgJRhbMHwCiAQASAAgJvhXMHwCiAQAoAAMJVxQGJQDFAAAAAA==.',
['Ài']='Àirén:BAAALgAECgEJAQAAAA==.',
['Îc']='Îcey:BAAALgAECgMJAwAAAA==.',
['Ön']='Öndi:BAAALgADCgYJBgAAAA==.',
['ßr']='ßrûh:BAAALgADCgEJAQAAAA==.',
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
