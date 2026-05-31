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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Unknown-Unknown','Monk-Windwalker','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Mage-Arcane','Monk-Mistweaver','Priest-Holy','Priest-Shadow','Rogue-Outlaw','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Druid-Feral','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Shaman-Restoration','Warrior-Protection','Evoker-Preservation','Rogue-Assassination','DemonHunter-Havoc','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Warrior-Arms','Shaman-Elemental','Druid-Balance','Paladin-Protection','Priest-Discipline',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Aborc:BAAALgAECgQJCAAAAA==.Abraxøs:BAACLgAFFH8HAAIBAAQJ0BFWKQABAQABAAQJ0BFWKQABAQAuAAQKfxUAAwIACAnpHRoKAD0CAAIABwl5HhoKAD0CAAEAAQmHGtNaAFEAAAAA.',
Ad='Adiris:BAAALgAECgkJEgAAAA==.Aduranu:BAAALgAECgcJCAAAAA==.',
Ae='Aegeax:BAAALgAECgMJBwAAAA==.Aerowynn:BAAALgADCgcJBwAAAA==.Aethers:BAAALgADCgYJBwABLgAFFAMJDQADAPEgAA==.Aethrion:BAAALgADCgEJAQAAAA==.',
Af='After:BAAALgADCgcJCAABLgAECggJLQAEALMZAA==.Afterall:BAAALgAECgUJBQABLgAECggJLQAEALMZAA==.',
Ai='Aiou:BAAALgAECgYJEwABLgAFFAEJAQAFAAAAAA==.Airtrun:BAAALgADCgEJAQAAAA==.',
Al='Alaalla:BAABLgAECn8XAAIGAAgJCwm+MgAjAQAGAAgJCwm+MgAjAQAAAA==.Alasttra:BAAALgAECgUJCAAAAA==.Alesallie:BAAALgAFFAEJAwAAAA==.Alexander:BAAALgAECgUJBQAAAA==.Alexie:BAAALgAECgQJCQAAAA==.Algiz:BAAALgAECgUJBQAAAA==.Alleriand:BAAALgADCgcJBwAAAA==.Alleryn:BAAALgAECgMJAwAAAA==.Alpine:BAAALgAECggJCwAAAA==.Alunaarn:BAAALgADCgQJCgAAAA==.',
Am='Amaldra:BAAALgAECgEJAQAAAA==.Amandagarcia:BAABLgAECn8YAAIHAAYJWhBhggD+AAAHAAYJWhBhggD+AAABLgAFFAEJAQAFAAAAAA==.Ambermage:BAAALgAECgYJCgAAAA==.Amerese:BAAALgADCgEJAQAAAA==.Amordrolan:BAAALgAECgEJAgAAAA==.Amourantha:BAAALgADCggJCwAAAA==.',
An='Andersdame:BAABLgAECn8fAAIIAAkJWhTiLwAGAgAIAAkJWhTiLwAGAgAAAA==.Anish:BAAALgAECgUJCwAAAA==.Anrot:BAAALgADCgUJBgAAAA==.Anthonyisme:BAABLgAECn8xAAIJAAkJeQ7xTwDUAQAJAAkJeQ7xTwDUAQAAAA==.',
Ao='Aon:BAAALgAECgQJBwAAAA==.Aonewan:BAAALgAECgMJAwAAAA==.',
Ar='Araels:BAABLgAECn8oAAMKAAkJJQ2BDAB0AQAKAAkJJQ2BDAB0AQAHAAcJnAeQjwDiAAAAAA==.Arindoril:BAAALgADCgYJDAAAAA==.Arktyh:BAABLgAECn82AAMLAAgJiiDhAQBQAgALAAgJACDhAQBQAgAJAAEJchNDNgE6AAAAAA==.Aryndinnin:BAACLgAFFH8aAAIMAAYJAh1xCwD/AQAMAAYJAh1xCwD/AQAuAAQKfyUAAgwACAl4HawLAJcCAAwACAl4HawLAJcCAAAA.',
As='Asdar:BAAALgAECgYJCAAAAA==.Asherah:BAACLgAFFH8KAAIBAAQJ8wncLgDtAAABAAQJ8wncLgDtAAAuAAQKfx4AAwEACQn+EJcvAFwBAAIABwkeDBAaAGQBAAEACAm+EZcvAFwBAAAA.Ashketchums:BAAALgADCgcJBwAAAA==.Asseleven:BAAALgAECgYJBwAAAA==.Astralrepaul:BAAALgAECgYJDwAAAA==.',
At='Atrocity:BAAALgAECgEJAQAAAA==.Attincy:BAAALgAECgEJAQAAAA==.',
Au='Augtistic:BAACLgAFFH8GAAIBAAMJBxnAEAD8AAABAAMJBxnAEAD8AAAuAAQKfxYAAgEACAlKIjYKANICAAEACAlKIjYKANICAAAA.Aussiemuscle:BAAALgADCgEJAQAAAA==.',
Ax='Axelofóðinn:BAABLgAECn81AAIDAAkJJRIYSgDQAQADAAkJJRIYSgDQAQAAAA==.',
Ay='Ayah:BAABLgAECn8nAAMNAAkJNBzhCADGAgANAAkJNBzhCADGAgAOAAMJrAp4WQCBAAAAAA==.Ayayrahn:BAAALgAECgUJCAAAAA==.Ayayrohn:BAAALgADCgUJBgAAAA==.Ayayyron:BAAALgAECgQJBAAAAA==.',
Az='Azerfrost:BAAALgAECgIJAgABLgAECggJFAAPAMgOAA==.Azogothar:BAAALgAECggJCgAAAA==.Aztinuz:BAAALgADCgUJBQAAAA==.',
Ba='Babygerl:BAAALgADCgIJAgAAAA==.Badbuny:BAAALgAECgYJCwAAAA==.Badger:BAAALgAECgUJBgAAAA==.Bahlz:BAAALgADCggJDQAAAA==.Bahlzanator:BAAALgAECgQJCAAAAA==.Bareca:BAAALgAECgUJBAAAAA==.Barnbek:BAAALgADCgYJEAAAAA==.Barode:BAAALgADCgEJAQAAAA==.',
Be='Bearenstein:BAAALgAECgUJBwAAAA==.Beccaw:BAAALgADCgUJCAAAAA==.Beccky:BAAALgADCgEJAQAAAA==.Beginners:BAAALgADCgEJAQAAAA==.Benjamyn:BAAALgADCgkJEQAAAA==.Benthelius:BAAALgADCgkJGQAAAA==.Bereir:BAAALgADCgMJAwAAAA==.Bestial:BAAALgADCgkJDwAAAA==.Bevicia:BAABLgAECn84AAIQAAkJjgohUQCcAQAQAAkJjgohUQCcAQAAAA==.',
Bi='Biggrim:BAAALgAECgIJAgAAAA==.Bigtotemz:BAAALgADCgIJAgAAAA==.Biiwaabik:BAAALgADCgcJDAAAAA==.Binkey:BAAALgADCgQJBAAAAA==.Biscuitlay:BAAALgAECgcJDgAAAA==.Bitsotig:BAABLgAECn8VAAINAAcJRAkdNAAdAQANAAcJRAkdNAAdAQAAAA==.',
Bj='Bjarkes:BAAALgADCgIJAgAAAA==.',
Bl='Blap:BAAALgADCgEJAQAAAA==.Blemish:BAABLgAECn8aAAIIAAYJLx8lTwCcAQAIAAYJLx8lTwCcAQAAAA==.Bloodfm:BAAALgAECgQJBAAAAA==.Bloodglzgob:BAAALgADCgYJCwABLgAECgYJEgAFAAAAAA==.Bloodlordz:BAAALgADCgYJDQABLgAECgUJBQAFAAAAAA==.Bloodology:BAAALgAECgEJAgABLgAECgYJEgAFAAAAAA==.Bloodscum:BAAALgAECgEJAQAAAA==.Bloodsham:BAAALgAECgYJEgAAAA==.Bloodstool:BAAALgADCgUJBQAAAA==.Bloodveil:BAAALgAECgkJDwABLgAFFAMJDgARAIobAA==.Blordz:BAAALgADCgYJCwABLgAECgUJBQAFAAAAAA==.Bluelicht:BAABLgAECn8cAAIRAAcJ7BufTgAHAgARAAcJ7BufTgAHAgABLgAECggJDQAFAAAAAA==.Bluphantom:BAAALgAECgIJBAAAAA==.Blym:BAAALgAECgQJBAAAAA==.',
Bo='Boodiica:BAABLgAECn8pAAISAAgJnRWLGgBuAQASAAgJnRWLGgBuAQAAAA==.Boom:BAAALgADCgEJAQAAAA==.Bootyism:BAABLgAECn8bAAIGAAgJKww+LgA5AQAGAAgJKww+LgA5AQAAAA==.',
Br='Braick:BAAALgAECgEJAQAAAA==.Brandofig:BAABLgAECn8WAAIIAAgJCgOgpgDVAAAIAAgJCgOgpgDVAAAAAA==.Brauman:BAAALgAECgIJAgAAAA==.Braynia:BAAALgAECggJDAAAAA==.Brazo:BAACLgAFFH8HAAMTAAIJzB98NgC3AAATAAIJzB98NgC3AAAGAAEJ1A+ZNABEAAAuAAQKfzQAAxMACAlSJEAGAMgCABMACAlSJEAGAMgCAAYAAQlUGQd/AEIAAAAA.Brazzinoth:BAAALgADCgEJAQABLgAFFAIJBwATAMwfAA==.Brewmasta:BAAALgAFFAEJAQAAAA==.Broxxigarr:BAABLgAECn8UAAIUAAcJ9hUyKgCaAQAUAAcJ9hUyKgCaAQAAAA==.',
Bu='Bucky:BAAALgADCgcJBwAAAA==.Buhlz:BAABLgAECn8XAAIDAAYJDQbT4wC6AAADAAYJDQbT4wC6AAAAAA==.Bujangsenang:BAAALgADCgYJBgAAAA==.Bullybane:BAABLgAECn8eAAIDAAkJkw1RcABzAQADAAkJkw1RcABzAQAAAA==.Bunyan:BAAALgADCgIJAQAAAA==.Buri:BAABLgAECn8eAAMSAAkJ7hRSFQCnAQASAAkJ7hRSFQCnAQARAAMJlwjD9QCRAAAAAA==.Buzzslc:BAAALgAECgkJDQAAAA==.',
By='Bytebait:BAAALgADCgUJCgAAAA==.',
Ca='Caelista:BAAALgADCgUJBQAAAA==.Caktan:BAAALgADCgcJEQAAAA==.Calahunts:BAACLgAFFH8XAAMIAAUJBh+hHgBgAQAIAAQJBh+hHgBgAQAVAAEJAADSMgAAAAAuAAQKfy0ABAgACAlRJEgMAN8CAAgACAlRJEgMAN8CABUAAwlwItBmAKQAABYAAQnED2JYADwAAAAA.Calatath:BAAALgAECgMJBgABLgAFFAUJFwAIAAYfAA==.Carloway:BAAALgAECgcJCgAAAA==.Castiana:BAAALgADCgQJBAAAAA==.Catlinn:BAAALgADCgkJEgAAAA==.Catmint:BAAALgADCgcJCQAAAA==.Catßenatar:BAAALgAECggJCwAAAA==.',
Ce='Celandria:BAAALgAECgYJCwAAAA==.Celical:BAAALgADCgMJAwAAAA==.Celize:BAABLgAECn8kAAMXAAgJDx1RHwA4AgAXAAcJbhxRHwA4AgAYAAcJeiG7CQA1AgAAAA==.Celticsean:BAAALgADCgYJBgAAAA==.Ceph:BAAALgAECgYJCgAAAA==.Cerollan:BAAALgADCgUJBQAAAA==.',
Ch='Cheekfreak:BAAALgADCgUJBgABLgAECggJHAAJACcVAA==.Cheeto:BAAALgAECgUJBwAAAA==.Chenna:BAAALgAECgEJAwAAAA==.Chewwybot:BAAALgADCgMJAwAAAA==.Chifoxx:BAAALgAECgYJCwABLgAECggJHAAXAIoPAA==.Chillay:BAAALgAECgQJBAAAAA==.Chokeahoa:BAAALgAECgYJCQAAAA==.Chorgin:BAAALgADCgEJAQAAAA==.Chromaxion:BAACLgAFFH8NAAIBAAQJNQRDNQDPAAABAAQJNQRDNQDPAAAuAAQKfxYAAgEACAn/C641ADgBAAEACAn/C641ADgBAAAA.Chronic:BAACLgAFFH8PAAIUAAUJOhnjFwA8AQAUAAUJOhnjFwA8AQAuAAQKfx4AAhQACQkWH5cNAOkCABQACQkWH5cNAOkCAAAA.Chrysostom:BAACLgAFFH8TAAIDAAQJdQ9tOgAfAQADAAQJdQ9tOgAfAQAuAAQKfywAAgMACQkFHUsZAJUCAAMACQkFHUsZAJUCAAAA.Chunkycheeks:BAAALgAECgQJBQAAAA==.Chwamz:BAACLgAFFH8FAAIQAAMJ0AS+eQC0AAAQAAMJ0AS+eQC0AAAuAAQKfxwAAxAACAlnGxMoAHECABAACAlnGxMoAHECABkAAQkAAOR8ACIAAAAA.',
Ci='Ciphirion:BAAALgADCgYJBwAAAA==.',
Cl='Clappa:BAAALgAFFAEJAQAAAA==.Clivennik:BAAALgADCgEJAQAAAA==.Cloggy:BAACLgAFFH8ZAAQQAAgJjhx1AwCJAgAQAAgJjhx1AwCJAgAZAAEJWx0gEgBbAAAaAAEJUBuEHQBNAAAuAAQKfysABBAACAnuJdUFAGADABAACAmhJdUFAGADABoABwkMI/IBALUCABkABQnnIVYQAMwBAAAA.Cloudshield:BAAALgAECgYJDAAAAA==.Clydell:BAAALgADCgIJAgAAAA==.',
Co='Coeus:BAAALgADCgMJAwAAAA==.Cokolo:BAAALgAECgIJAwAAAA==.Coldflame:BAACLgAFFH8SAAIJAAQJgBvwNQBpAQAJAAQJgBvwNQBpAQAuAAQKfzUAAgkACQkTIx8UAMsCAAkACQkTIx8UAMsCAAAA.Corgigather:BAAALgAECgMJAwAAAA==.Corruption:BAAALgAECgYJCAAAAA==.Corruptmonk:BAAALgAECgEJAQAAAA==.Cowchucker:BAAALgAECgQJDgAAAA==.Cowzilla:BAAALgAECgMJAwAAAA==.',
Cp='Cptboomerang:BAABLgAECn8lAAIIAAkJhR2hDwDAAgAIAAkJhR2hDwDAAgAAAA==.',
Cr='Crabrangoons:BAAALgAECgYJEAAAAA==.Crath:BAAALgAECgQJBAABLgAECggJEwAFAAAAAA==.Crathdk:BAAALgAECggJEwAAAA==.Crathmonk:BAAALgAECgQJCgABLgAECggJEwAFAAAAAA==.Creamfilling:BAAALgADCgYJBgAAAA==.Crispynugget:BAAALgADCgkJFwAAAA==.Crixo:BAAALgADCgUJBQAAAA==.Crmsondwagon:BAAALgAECgEJAQABLgAECgkJEAAFAAAAAA==.Crownroyale:BAACLgAFFH8KAAITAAMJ0wvfNAC+AAATAAMJ0wvfNAC+AAAuAAQKfzoAAhMACQkPGlkQACgCABMACQkPGlkQACgCAAAA.Cryovex:BAAALgAECgQJBAAAAA==.',
Cy='Cyrissa:BAACLgAFFH8FAAIJAAIJKwNwngB2AAAJAAIJKwNwngB2AAAuAAQKfzAAAgkACAksGB9NANwBAAkACAksGB9NANwBAAAA.',
['Câ']='Cârnägê:BAAALgAECgEJAQAAAA==.',
Da='Dadlover:BAABLgAECn8ZAAIbAAcJwQ1wFQABAQAbAAcJwQ1wFQABAQAAAA==.Daegu:BAABLgAECn84AAIcAAkJFhNgKAACAgAcAAkJFhNgKAACAgAAAA==.Daenlan:BAAALgADCgQJBwAAAA==.Daeynora:BAAALgADCgEJAQAAAA==.Daityasfist:BAABLgAFFH8FAAIGAAMJMiFFBQA2AQAGAAMJMiFFBQA2AQAAAA==.Daler:BAAALgADCgQJBAAAAA==.Dalien:BAABLgAECn8gAAIdAAgJwiU0AwD2AgAdAAgJwiU0AwD2AgAAAA==.Dalinius:BAAALgAECgYJDgAAAA==.Dalonar:BAAALgADCgMJAwAAAA==.Dance:BAAALgADCgYJCwAAAA==.Dancnisraeli:BAAALgAECgUJDgAAAA==.Darcine:BAAALgAECgQJCAAAAA==.Darkbojangle:BAAALgAECgEJAQAAAA==.Darkless:BAAALgAECgEJAQAAAA==.Darkseksi:BAAALgADCgQJBAAAAA==.Dashmodius:BAABLgAECn8iAAMHAAkJAx6AGgBiAgAHAAkJAx6AGgBiAgAKAAEJkhwRJgBUAAAAAA==.Datakutasa:BAAALgAECggJEAABLgAECggJIAAdAEMXAA==.Datfourloko:BAAALgAECgEJAgAAAA==.Dazing:BAAALgAECgYJDAAAAA==.',
De='Deamontsuki:BAABLgAECn8UAAQeAAgJvA6pKwAWAQAeAAYJqQipKwAWAQACAAQJbwkzFQCpAAABAAEJnQRsiAAqAAAAAA==.Deathpack:BAABLgAFFH8GAAIbAAMJih2WCwAXAQAbAAMJih2WCwAXAQAAAA==.Deathweaver:BAAALgADCgUJBQAAAA==.Deceasedpi:BAAALgAECgUJCgAAAA==.Delaci:BAAALgAECgcJDwAAAA==.Delsid:BAAALgADCgUJBQAAAA==.Demonicbeilf:BAAALgADCgEJAQAAAA==.Demonster:BAABLgAECn8ZAAIfAAkJXxPLBgDjAQAfAAkJXxPLBgDjAQAAAA==.Denaian:BAAALgADCgYJBwAAAA==.Deohgee:BAAALgAECgQJEgAAAA==.Deranker:BAABLgAECn8YAAIJAAgJCxvgRwDsAQAJAAgJCxvgRwDsAQAAAA==.Desdela:BAAALgADCgMJAwABLgAECggJCQAFAAAAAA==.Desmus:BAAALgADCgUJBgAAAA==.Devourdeez:BAAALgAECggJCwABLgAFFAgJKQAQAKEbAA==.Dezarath:BAAALgAECgUJBgAAAA==.',
Dh='Dhuumstar:BAAALgADCgkJDwAAAA==.',
Di='Dinivas:BAAALgAECgMJAwAAAA==.Diyther:BAAALgAECgIJAgAAAA==.',
Dk='Dkbuhlz:BAAALgAECgQJBgAAAA==.',
Do='Docfeelgood:BAAALgAECgIJBAAAAA==.Doofysvacuum:BAAALgAECgQJBQABLgAECggJMgAUAJYQAA==.Dotdude:BAABLgAECn8WAAIQAAYJEhUcdgBCAQAQAAYJEhUcdgBCAQAAAA==.',
Dr='Draganhammer:BAAALgAECggJEgAAAA==.Dragolord:BAAALgAECgEJAQAAAA==.Drakkarn:BAABLgAECn8gAAIdAAgJQxc5EwChAQAdAAgJQxc5EwChAQAAAA==.Draxina:BAAALgADCgYJBgAAAA==.Draxxton:BAAALgADCgcJCgAAAA==.Drdurty:BAABLgAECn8dAAIOAAgJsRddFABNAgAOAAgJsRddFABNAgAAAA==.Dreadhoof:BAAALgADCgkJDQAAAA==.Drewcifur:BAAALgAECgUJDgAAAA==.Dron:BAAALgAECgUJBQAAAA==.Droodar:BAAALgADCgUJBQAAAA==.Droopey:BAAALgAECgMJAwAAAA==.Dropxlife:BAAALgAECgQJBAAAAA==.Druttut:BAAALgADCgEJAQAAAA==.Dryst:BAAALgAECgUJCAAAAA==.Drægon:BAAALgADCgQJBwAAAA==.',
Du='Duckywg:BAABLgAECn8WAAIgAAkJdg5xHwBZAQAgAAkJdg5xHwBZAQAAAA==.Duskvoke:BAAALgAECgMJAwABLgAECgUJCwAFAAAAAA==.Duskzen:BAAALgAECgUJCwAAAA==.Dusq:BAAALgAECgEJAQAAAA==.',
['Dì']='Dìsala:BAAALgAECgEJAQAAAA==.',
Ed='Edamame:BAAALgADCgYJCQAAAA==.',
Ei='Eilistraaee:BAACLgAFFH8HAAIhAAMJVxkOJQDiAAAhAAMJVxkOJQDiAAAuAAQKfzQAAyEACQnhIk8DAFwDACEACQnhIk8DAFwDAAMAAQkMB3GOAScAAAAA.',
Ek='Eki:BAAALgAECgIJAgAAAA==.Ekicarys:BAAALgADCgQJBAAAAA==.',
El='Eleratzis:BAABLgAECn8mAAIiAAgJGR54BQB3AgAiAAgJGR54BQB3AgAAAA==.Elfayomega:BAAALgADCgEJAQABLgADCgQJBQAFAAAAAA==.Elmencho:BAABLgAECn8WAAIRAAYJgRAjnABIAQARAAYJgRAjnABIAQAAAA==.Eltiera:BAAALgAECgQJBQAAAA==.Elvenshot:BAAALgADCgMJAwAAAA==.Elyssa:BAAALgAECggJEgAAAA==.',
Em='Emberfist:BAAALgADCgYJCQAAAA==.',
En='Endswell:BAAALgAECgcJCAAAAA==.Endszene:BAAALgADCgMJAwAAAA==.',
Er='Eraylda:BAAALgADCgIJAgAAAA==.Errorin:BAAALgAECgMJAwAAAA==.',
Es='Eskimo:BAAALgAECgQJBgAAAA==.Esquimaux:BAABLgAECn8ZAAIDAAkJRRCFYACWAQADAAkJRRCFYACWAQAAAA==.Essex:BAAALgAECgEJAQAAAA==.',
Et='Etchlock:BAAALgAECgYJCgAAAA==.Etheriademon:BAAALgADCgQJBAAAAA==.',
Eu='Euclyn:BAAALgAECgEJAQAAAA==.',
Ev='Evasive:BAAALgADCgUJBQAAAA==.Eviannis:BAAALgAECgYJBwAAAA==.Evilcaster:BAAALgAECgIJAgAAAA==.Evîe:BAAALgADCgQJBAAAAA==.',
Ew='Ewanae:BAAALgAECgQJBAABLgAFFAQJCgABAPMJAA==.',
Ex='Extacee:BAAALgAECgUJEwAAAA==.Extrafancy:BAAALgADCgkJEwAAAA==.',
Fa='Faerina:BAAALgADCgIJAgAAAA==.Faesonia:BAAALgAECgQJDQAAAA==.Fakhew:BAAALgADCgIJAgAAAA==.Fangthir:BAAALgADCgYJCAABLgAECgUJCQAFAAAAAA==.Faoop:BAAALgADCgIJAgAAAA==.Farrahp:BAAALgADCgYJAwAAAA==.Fasylan:BAAALgADCgEJAQAAAA==.',
Fe='Feastling:BAABLgAECn8ZAAIHAAgJEgszfAAMAQAHAAgJEgszfAAMAQAAAA==.Feefree:BAAALgAECgEJAQAAAA==.Felinthecon:BAAALgADCgEJAQAAAA==.Felthirra:BAAALgADCgEJAQAAAA==.Femboyswag:BAAALgAECgUJBgAAAA==.Feralmoan:BAAALgADCgEJAQAAAA==.Ferrak:BAAALgADCgcJBwAAAA==.',
Fi='Filntlok:BAAALgAECgEJAQAAAA==.Finnabust:BAAALgAECgEJAQAAAA==.Fizzlefarts:BAAALgADCgYJDwAAAA==.Fizzylemon:BAAALgADCgcJCQAAAA==.',
Fl='Flipndrag:BAAALgAECgQJBAAAAA==.Flipnpriest:BAAALgAECgcJCAAAAA==.Flipnslam:BAABLgAECn8ZAAIdAAgJ7AuLIgADAQAdAAgJ7AuLIgADAQAAAA==.Floofball:BAACLgAFFH8NAAIXAAQJIRfuHwA8AQAXAAQJIRfuHwA8AQAuAAQKfx4AAhcABglkJOkaAFsCABcABglkJOkaAFsCAAEuAAUUBQkXAAgABh8A.Floofyprotek:BAAALgAECgEJAQAAAA==.Floralia:BAAALgAECgEJAQAAAA==.',
Fo='Focaex:BAAALgADCgMJAwAAAA==.Forget:BAAALgAECgIJBQAAAA==.Foxyshadow:BAAALgADCgkJCgAAAA==.',
Fr='Fragwork:BAAALgAECgQJBAAAAA==.Frankadank:BAAALgADCgIJAgAAAA==.Freadyfire:BAAALgAECgYJDQAAAA==.Frostfiretip:BAABLgAECn8XAAIJAAgJAQwSiABMAQAJAAgJAQwSiABMAQAAAA==.Frozanath:BAAALgAFFAEJAQAAAA==.Frózen:BAAALgAECgQJBgAAAA==.',
Fu='Fucctaard:BAAALgADCgIJAgAAAA==.Furious:BAAALgADCgYJBgAAAA==.',
Ga='Gaerestord:BAAALgADCgUJBgAAAA==.Gaglinda:BAAALgADCgEJAQAAAA==.Gakusei:BAAALgAECgMJAwAAAA==.Gatortail:BAAALgAECgIJAgAAAA==.Gatzart:BAAALgADCgUJCQAAAA==.',
Gh='Ghoztxm:BAAALgADCgQJBAAAAA==.',
Gi='Gimchick:BAABLgAECn8YAAMMAAgJpxgJJACTAQAMAAcJGhgJJACTAQAGAAcJmg5LMQAqAQAAAA==.',
Gn='Gnomebody:BAAALgADCgcJBwABLgAFFAQJDAARAGcSAA==.',
Go='Goliat:BAAALgAECgUJCQAAAA==.Goofydude:BAAALgAECgYJCQAAAA==.Goofysensei:BAAALgAECgUJCAABLgAECgYJCQAFAAAAAA==.Goyimblade:BAAALgAECgkJEAAAAA==.Goyimstorm:BAAALgAECgcJBgABLgAECgkJEAAFAAAAAA==.',
Gr='Grandejugoso:BAAALgAECgEJAQAAAA==.Grapejuicy:BAAALgAECgUJBQAAAA==.Grea:BAABLgAECn8aAAIBAAgJRwtUPAAYAQABAAgJRwtUPAAYAQAAAA==.Greenforhim:BAAALgAECgYJEQAAAA==.Grumpyguts:BAAALgADCgQJBAAAAA==.',
Gu='Guatemoc:BAAALgAECgEJAQAAAA==.Guldandan:BAAALgAECgIJBAAAAA==.Gulugg:BAAALgAECgYJDgAAAA==.Gurthang:BAAALgAECgMJBgAAAA==.',
Ha='Haaber:BAAALgAECgEJAQAAAA==.Hadenmage:BAAALgADCgkJCwAAAA==.Hadrianus:BAAALgADCgcJBwAAAA==.Haginger:BAABLgAECn8rAAIdAAkJbhw0BwB6AgAdAAkJbhw0BwB6AgABLgAECggJHQAjACIUAA==.Hangwenaz:BAABLgAFFH8FAAIkAAQJzwxSFgAGAQAkAAQJzwxSFgAGAQABLgAFFAYJGgAMAAIdAA==.Harlyq:BAABLgAECn8kAAQTAAcJFB7GOgBdAQATAAUJ/RrGOgBdAQAMAAcJFBG2KwBYAQAGAAIJFAtJaABsAAAAAA==.Harnormogh:BAAALgADCgYJBgAAAA==.Havocpeener:BAAALgADCgIJAgABLgADCgkJCwAFAAAAAA==.Hazy:BAAALgAECgUJBQAAAA==.',
He='Healzin:BAAALgADCgMJBgAAAA==.Hearah:BAACLgAFFH8OAAIcAAQJ0gbZOwDYAAAcAAQJ0gbZOwDYAAAuAAQKfyEAAxwACQm8D+hIAG4BABwACQm8D+hIAG4BACUABAkXBaV1AGkAAAAA.Hellyes:BAAALgAECgEJAQAAAA==.Hellzinger:BAAALgAECgQJBQAAAA==.Helynia:BAAALgADCgYJBgAAAA==.Herthaela:BAAALgADCgUJBQABLgAECgYJBwAFAAAAAA==.Hexdabear:BAAALgADCgcJDgABLgAECgkJFAAMAKAUAA==.Hexdecay:BAAALgAECgUJBQABLgAECgkJFAAMAKAUAA==.Hexkwondo:BAABLgAECn8UAAMMAAkJoBSLHAANAgAMAAkJoBSLHAANAgAGAAQJ/wxnXACfAAAAAA==.Hexquisite:BAAALgAECgEJAQABLgAECgkJFAAMAKAUAA==.Hexxer:BAAALgAECgcJDQABLgAECgkJFAAMAKAUAA==.',
Hi='Hitee:BAAALgAECgMJAwAAAA==.',
Ho='Holybone:BAAALgADCgEJAQAAAA==.Holybooty:BAAALgAFFAEJAQAAAA==.Hondò:BAEBLgAFFH8HAAMLAAMJ1BkvAQANAQALAAMJ1BkvAQANAQAJAAEJHAEvtgA0AAABLgAFFAcJHwARALUgAA==.Hondô:BAECLgAFFH8fAAMRAAcJtSAJBwBrAgARAAcJtSAJBwBrAgAbAAIJqxajFgCPAAAuAAQKf0EAAxEACQnXJaIDAF0DABEACQnXJaIDAF0DABsABgmVIYcIANUBAAAA.Hordediddy:BAAALgAECgYJBgAAAA==.Hosinator:BAABLgAECn9CAAIJAAkJCwsTZACdAQAJAAkJCwsTZACdAQAAAA==.Hotzs:BAAALgAECgQJDAABLgAECggJEwAFAAAAAA==.Hoöp:BAACLgAFFH8JAAIlAAUJEhShEABuAQAlAAUJEhShEABuAQAuAAQKfxQAAiUABwnfHS8ZAAECACUABwnfHS8ZAAECAAEuAAUUBwkRACUAvhMA.',
Hu='Huckleberry:BAAALgADCgcJBwAAAA==.Hukmo:BAAALgAFFAMJBAAAAA==.Huntermanjoe:BAABLgAECn8WAAIIAAcJZgVPkQACAQAIAAcJZgVPkQACAQAAAA==.Huntersdie:BAAALgAECgEJAQAAAA==.Hunterzalt:BAACLgAFFH8KAAISAAMJVBVlHgDNAAASAAMJVBVlHgDNAAAuAAQKfzsAAxIACQm4Ha8IAHcCABIACQm4Ha8IAHcCABEAAQnGAagxASYAAAAA.',
Hy='Hydroplex:BAAALgADCgQJBgAAAA==.',
['Hò']='Hòndo:BAEALgAECgQJBAABLgAFFAcJHwARALUgAA==.',
['Hô']='Hôndo:BAEBLgAFFH8HAAIkAAMJIx3cFgACAQAkAAMJIx3cFgACAQABLgAFFAcJHwARALUgAA==.',
Ia='Iamroot:BAAALgAECgEJAQAAAA==.',
Ic='Icepanda:BAAALgADCgMJAwAAAA==.Ichantspell:BAABLgAECn8gAAIZAAYJaBEUEgAMAQAZAAYJaBEUEgAMAQAAAA==.Icurseyou:BAAALgADCgcJBwABLgAFFAIJBQAJACsDAA==.',
Id='Idra:BAACLgAFFH8VAAIVAAQJ3SbxBwC7AQAVAAQJ3SbxBwC7AQAuAAQKfy0AAhUACQmCJGABAAQDABUACQmCJGABAAQDAAAA.Idrea:BAAALgADCgYJBgAAAA==.',
Ie='Ieatglue:BAAALgAECgMJAwABLgAFFAEJAQAFAAAAAA==.',
Il='Ildjarnn:BAAALgAECgUJCAAAAA==.Illaoii:BAAALgAECgEJAQAAAA==.Illussions:BAABLgAECn8YAAQXAAcJ7ROJUgBcAQAXAAYJlBSJUgBcAQAjAAEJ6RxOUQBOAAAmAAIJeRaVeAA+AAAAAA==.',
Im='Imapotato:BAAALgADCgYJBwAAAA==.Imdyland:BAAALgADCgIJAgAAAA==.',
In='Inashen:BAAALgADCgEJAQABLgAECgMJBwAFAAAAAA==.Informal:BAAALgADCgIJAgAAAA==.Invelmoon:BAAALgAECgQJDAAAAA==.',
Ip='Ipomoea:BAAALgADCgkJDgAAAA==.',
Ir='Iriane:BAABLgAECn8VAAIOAAkJhAQGSwC8AAAOAAkJhAQGSwC8AAAAAA==.',
Is='Isadeamon:BAAALgAECgcJCAAAAA==.',
It='Ithrail:BAACLgAFFH8LAAIHAAUJZwvnQwACAQAHAAUJZwvnQwACAQAuAAQKfx0AAgcACQllHKk8AL0BAAcACQllHKk8AL0BAAAA.Itsmyfault:BAAALgAECgEJAQAAAA==.',
Ja='Jakilk:BAABLgAECn8XAAMSAAkJMgciLADfAAARAAgJaAMbugDvAAASAAgJrQciLADfAAAAAA==.Januae:BAAALgAECgQJBgAAAA==.Jarotapal:BAAALgAECgMJAwAAAA==.Jatza:BAAALgAECgcJEAAAAA==.Javontavius:BAAALgAECgYJDQAAAA==.Jazzmisa:BAABLgAECn89AAIDAAgJHhOwYQCTAQADAAgJHhOwYQCTAQAAAA==.',
Jd='Jdoobie:BAAALgADCgYJBgAAAA==.',
Je='Jehon:BAAALgAECgEJAgAAAA==.Jellydead:BAABLgAECn8oAAIRAAkJVRIXPQD6AQARAAkJVRIXPQD6AQAAAA==.Jerfbek:BAAALgADCgIJAgAAAA==.Jerico:BAAALgADCgIJAgAAAA==.Jesselroes:BAAALgADCgMJAwAAAA==.',
Ji='Jinja:BAAALgADCgcJDwAAAA==.',
Jo='Jockster:BAAALgAECgYJEgAAAA==.Jonawayne:BAAALgAECgUJCQAAAA==.Joseycoyote:BAAALgADCgcJBwAAAA==.José:BAAALgAECgQJBAAAAA==.',
Ju='Judgeandrson:BAAALgAECgUJBQABLgAECggJFwAJAAEMAA==.Judinous:BAACLgAFFH8JAAIJAAMJRCFAWgAeAQAJAAMJRCFAWgAeAQAuAAQKfyUAAgkACQlQIVcnANUCAAkACQlQIVcnANUCAAAA.Juggernåut:BAAALgAECgYJBwAAAA==.Junipper:BAAALgAECggJEgABLgAFFAIJBQAJACsDAA==.',
Jy='Jyourn:BAAALgADCgEJAQAAAA==.',
Ka='Kabooms:BAABLgAECn8cAAIJAAYJAAc83QC9AAAJAAYJAAc83QC9AAAAAA==.Kaelditeta:BAAALgAECgcJEQAAAA==.Kaelsdruid:BAAALgAECgQJBAAAAA==.Kaelsevoker:BAABLgAFFH8IAAIeAAQJRgg1GQDpAAAeAAQJRgg1GQDpAAAAAA==.Kaelthuss:BAAALgADCgMJAwABLgAECgIJBAAFAAAAAA==.Kaiarbarcy:BAAALgAECgYJEwAAAA==.Kaisen:BAAALgADCgUJBQAAAA==.Kalamord:BAAALgADCgYJBgAAAA==.Kalross:BAAALgAECgEJAQAAAA==.Kanao:BAABLgAECn8UAAIHAAgJ0g66TQC+AQAHAAgJ0g66TQC+AQAAAA==.Karethi:BAAALgADCgEJAQAAAA==.Kasna:BAAALgADCgMJAwAAAA==.Katimeen:BAABLgAECn8iAAIOAAkJDQ4YIACmAQAOAAkJDQ4YIACmAQAAAA==.Katla:BAAALgADCgUJBQAAAA==.Kawaiiuwu:BAAALgAECgMJAwAAAA==.',
Ke='Keesah:BAAALgAECgEJAQAAAA==.Keinddora:BAAALgADCgEJAQAAAA==.Kelann:BAABLgAECn8rAAIHAAgJtQbghgD0AAAHAAgJtQbghgD0AAAAAA==.Kensei:BAABLgAECn8jAAMgAAgJmyM8BwCjAgAgAAgJmyM8BwCjAgAHAAIJKCCs2QBcAAAAAA==.Kentohya:BAAALgADCgYJDwAAAA==.Kenöbi:BAAALgAECgQJBQAAAA==.Keroth:BAAALgAECgUJBQAAAA==.Kevingates:BAAALgAECgEJAQABLgAFFAgJFAAdAPIfAA==.',
Kh='Khaoticbrews:BAAALgAECgEJAgABLgAFFAMJBwADAJQSAA==.Kharnoth:BAAALgAECgQJBAAAAA==.Khayla:BAAALgAECgEJAQAAAA==.Khody:BAAALgAECgQJBAAAAA==.',
Ki='Kicknbird:BAAALgADCgEJAQAAAA==.Kilain:BAACLgAFFH8UAAQRAAUJEhvLSwA7AQARAAQJEhvLSwA7AQASAAMJ/RpTDACxAAAbAAEJMxH1HQBGAAAuAAQKfxoABBIACAlqFEUgAEIBABIABAmyIkUgAEIBABEABwkvEASwAP4AABsAAQkQAls5ABIAAAAA.Killertime:BAAALgADCgMJAwAAAA==.Kimbo:BAAALgAECgEJAQAAAA==.Kindaworthy:BAAALgAECgMJAwAAAA==.Kippo:BAEBLgAFFH8PAAMRAAUJaBFLYAAcAQARAAQJaBFLYAAcAQASAAEJAACxUwAAAAAAAA==.',
Kn='Knewbee:BAAALgADCgEJAQABLgADCgQJBQAFAAAAAA==.',
Ko='Kohlin:BAAALgAECgQJBAAAAA==.Kokushîbo:BAAALgAECgUJDAAAAA==.Konkon:BAAALgAECgYJBwAAAA==.Konoa:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Konton:BAAALgAECgUJCAABLgAECggJLQAEALMZAA==.Korabakoki:BAAALgAECgEJAQAAAA==.Kotah:BAAALgAECgMJAwAAAA==.',
Kr='Kradoro:BAAALgADCgYJDAAAAA==.Kratorick:BAAALgADCgEJAQAAAA==.Krazyastrii:BAAALgAECgIJBAABLgAECgQJBgAFAAAAAA==.Krelash:BAABLgAECn8cAAIRAAgJ0hL/YQCRAQARAAgJ0hL/YQCRAQAAAA==.',
Ku='Kukipoo:BAAALgAECgMJAwAAAA==.Kurdzy:BAAALgAECgUJBQAAAA==.',
Kv='Kvarda:BAAALgADCgMJBAAAAA==.',
Ky='Kylofinn:BAAALgAECgMJBAABLgAECgQJBQAFAAAAAA==.Kynetic:BAAALgAECgQJBwAAAA==.',
La='Labatblue:BAAALgAECgMJAwAAAA==.Laynly:BAAALgAECggJCgAAAA==.',
Le='Learning:BAAALgAECgMJAwAAAA==.Leenie:BAAALgAECggJEAAAAA==.Leftleg:BAAALgAECgIJBgAAAA==.Legendrìser:BAACLgAFFH8LAAIDAAUJtwprQwANAQADAAUJtwprQwANAQAuAAQKfxYAAgMACQllGKFNAPkBAAMACQllGKFNAPkBAAAA.Leggomyeggos:BAAALgADCgMJAwAAAA==.Leginge:BAABLgAECn8dAAMjAAgJIhSCDwCCAQAjAAgJIhSCDwCCAQAXAAEJdgHs6AAcAAAAAA==.Leigong:BAAALgAECggJDAAAAA==.Leiyang:BAABLgAECn8sAAIKAAgJfRTVCQCtAQAKAAgJfRTVCQCtAQAAAA==.Lemmykillmr:BAAALgAECgQJBwAAAA==.Lesson:BAAALgAFFAQJBAAAAA==.',
Li='Liaree:BAAALgADCgIJAgAAAA==.Lie:BAABLgAECn8tAAIEAAgJsxmqFADjAQAEAAgJsxmqFADjAQAAAA==.Lifey:BAACLgAFFH8PAAMRAAQJHRb1UwAuAQARAAQJHRb1UwAuAQAbAAMJLwzREADUAAAuAAQKfx0AAxsACQmMHCUNAHQBABEACAmiHFBHAB4CABsABglfGiUNAHQBAAEuAAUUAwkEAAUAAAAA.Lightfemboy:BAAALgAECgYJDwABLgAFFAcJHwATAFEmAA==.Lilpeets:BAAALgAECgUJBQAAAA==.Lilstrikerj:BAAALgAECgIJAwAAAA==.Limonespe:BAABLgAECn8YAAMQAAgJvSSSCwAeAwAQAAgJvSSSCwAeAwAZAAEJAAAbXABaAAAAAA==.Lisal:BAAALgAECgkJAwAAAA==.Lizerd:BAAALgAECgUJCAABLgAFFAYJFAANANYaAA==.',
Lo='Locktendo:BAAALgADCgUJCAAAAA==.Lohkoh:BAAALgAECgQJBAABLgABCgEJAQAFAAAAAA==.Looksmaxxing:BAAALgADCgIJAgAAAA==.Lothon:BAAALgADCgMJAwAAAA==.Lothrean:BAAALgAECgUJCQAAAA==.',
Lu='Luciferal:BAAALgADCgYJBgAAAA==.Lunaluv:BAAALgAECgYJCwAAAA==.Lussions:BAAALgAECgUJDAAAAA==.',
Ly='Lyraelles:BAAALgAECgUJCQAAAA==.Lytefoot:BAAALgADCgQJBAAAAA==.Lytheris:BAAALgAECgYJBgAAAA==.',
['Lë']='Lëägolas:BAAALgADCgcJBgABLgAECgkJEAAFAAAAAA==.',
['Lí']='Líllíth:BAAALgAECgYJDgAAAA==.',
['Lï']='Lïghtly:BAAALgAECgEJAQAAAA==.',
Ma='Machoshaman:BAABLgAECn8bAAMcAAgJuxTnKQDmAQAcAAgJuxTnKQDmAQAlAAIJrRH3dABuAAAAAA==.Maeleia:BAAALgADCggJCAAAAA==.Maeveran:BAABLgAECn8sAAMnAAgJdRclFQBkAQADAAgJ0RSncwBsAQAnAAcJVBUlFQBkAQAAAA==.Mafuyu:BAAALgAECgMJBAAAAA==.Maghalfastir:BAACLgAFFH8NAAIRAAMJxhhTcgD5AAARAAMJxhhTcgD5AAAuAAQKfyYAAhEABwm5IWooAEwCABEABwm5IWooAEwCAAEuAAUUBgkaAAwAAh0A.Magnusvll:BAABLgAECn8WAAMDAAYJKxAOywDbAAADAAYJXA8OywDbAAAnAAUJrAz7MgB9AAAAAA==.Magraah:BAAALgAECgkJEQAAAA==.Mahesvara:BAABLgAECn8lAAIRAAkJzxXoKgBBAgARAAkJzxXoKgBBAgAAAA==.Malafanai:BAAALgAECgEJAgAAAA==.Maliea:BAAALgADCgUJCgAAAA==.Malomea:BAAALgADCgcJBwAAAA==.Malphestor:BAAALgAECgEJAQABLgAECggJGgABAEcLAA==.Malvoryx:BAAALgAECgIJAwAAAA==.Mandrei:BAAALgAECgYJCwAAAA==.Mantisa:BAAALgAECgMJAwAAAA==.Manøn:BAAALgAECgQJBQAAAA==.Maraul:BAAALgAECgEJAQAAAA==.Marlynn:BAAALgAECgcJDAAAAA==.Marshur:BAAALgAECgYJBgABLgAFFAgJGQAQAI4cAA==.Masinverter:BAAALgAECgYJDQAAAA==.Mastalys:BAEALgAECgUJDgAAAQ==.Matrom:BAAALgAECgYJBgAAAA==.Mattamuss:BAAALgAECgcJDgAAAA==.Mattdamon:BAAALgADCgEJAQAAAA==.Mattzappara:BAAALgADCgMJAwAAAA==.Mavet:BAACLgAFFH8KAAMOAAMJmBF9HgDaAAAOAAMJmBF9HgDaAAAoAAIJ2QEWOQBoAAAuAAQKfzwAAw4ACQkxHRcMAHUCAA4ACQkxHRcMAHUCAA0ABAk0A39jAKEAAAAA.Mavina:BAAALgAECgYJDAABLgAECgkJPgABAK0aAA==.Mavinaqt:BAABLgAECn8+AAMBAAkJrRr8EABEAgABAAkJrRr8EABEAgAeAAIJ7QJWRABMAAAAAA==.Maxso:BAAALgAECgkJBQAAAA==.Mazez:BAABLgAECn8WAAQeAAcJVAdKHQD9AAAeAAcJVAdKHQD9AAACAAYJcgo5EAD0AAABAAUJLwj8ZQB+AAAAAA==.',
Mc='Mcpeek:BAAALgAECgUJCwAAAA==.',
Me='Meanswell:BAABLgAECn8VAAQNAAYJqA44OwDyAAANAAUJFQ84OwDyAAAoAAEJPgfZcQAqAAAOAAEJfQJzhwAcAAAAAA==.Meatshieldz:BAAALgAECgkJDgAAAA==.Mechachi:BAABLgAECn8ZAAIMAAgJNBM7MgCAAQAMAAgJNBM7MgCAAQAAAA==.Megabonk:BAAALgADCgcJBwABLgAFFAQJBgAWAB4RAA==.Meglatwo:BAAALgADCgcJBwABLgAFFAMJCgAQAJwMAA==.Meibardo:BAAALgAECgQJAQABLgAECgcJEQAFAAAAAA==.Meketek:BAABLgAECn8uAAIbAAgJfxn+CADKAQAbAAgJfxn+CADKAQAAAA==.Meliretiera:BAAALgAECgQJBAABLgAFFAMJBAAFAAAAAA==.Mellivia:BAAALgAECgUJBQAAAA==.Melodica:BAAALgAECgcJEgAAAA==.Menaly:BAAALgAECgMJBQAAAA==.Mendel:BAAALgADCgQJBQAAAA==.Metaphysical:BAABLgAECn84AAMMAAgJrxYZIwDcAQAMAAgJrxYZIwDcAQATAAUJQBZ3VwDmAAAAAA==.Methenistul:BAAALgAECgEJAwABLgAFFAYJGgAMAAIdAA==.',
Mi='Miasmun:BAAALgAECgUJCAABLgAECgYJDQAFAAAAAA==.Miennie:BAABLgAECn8mAAMCAAgJrAf7DAAvAQACAAgJrAf7DAAvAQABAAIJ7gAXlQAUAAAAAA==.Mildo:BAABLgAECn8sAAMZAAgJUhqIBAAcAgAZAAgJUhqIBAAcAgAQAAEJAAAgNQEOAAAAAA==.Millerlight:BAAALgAECgYJCgAAAA==.Mingemeister:BAAALgAECgIJAgAAAA==.Minotàurus:BAACLgAFFH8KAAMIAAMJQAs0VADWAAAIAAMJQAs0VADWAAAWAAEJYwBhMAAyAAAuAAQKfzMABAgACQm7D449ANMBAAgACQm7D449ANMBABYACAltBXooAEwBABUAAQnJCe44AC0AAAAA.Mintonka:BAABLgAECn8bAAIlAAYJ9gE0bgB+AAAlAAYJ9gE0bgB+AAAAAA==.Mirakodus:BAAALgADCgcJDQAAAA==.Misfired:BAABLgAECn8fAAMWAAkJaxgADABXAgAWAAkJaxgADABXAgAIAAUJvRKNXABSAQAAAA==.Mistbehave:BAABLgAECn8kAAQTAAkJ2A0BJgBsAQATAAgJ2Q0BJgBsAQAMAAcJmgwiOAAKAQAGAAQJBgimdABSAAAAAA==.Miztaqe:BAAALgADCgMJAwAAAA==.',
Mo='Mogthalen:BAAALgADCgMJAwAAAA==.Moneyheavy:BAAALgAECgYJCwAAAA==.Mongkorn:BAAALgAECgEJAQAAAA==.Monstershi:BAAALgAECgEJAQAAAA==.Mooarcane:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.Moomoopie:BAABLgAECn8aAAMnAAcJ0Ag6JQDQAAAnAAcJ0Ag6JQDQAAADAAMJpAg9EQGBAAAAAA==.Moonologist:BAAALgAECgYJBgAAAA==.Moonpig:BAAALgAECgYJCAAAAA==.Moopiehead:BAAALgAECgIJBQAAAA==.Moosiah:BAAALgADCgIJAgAAAA==.Mordayna:BAAALgAECgYJEAAAAA==.Morganà:BAAALgAECgQJBwAAAA==.Morgy:BAABLgAECn8qAAIJAAgJpgefpgAVAQAJAAgJpgefpgAVAQAAAA==.Mortimr:BAAALgAECgUJBAAAAA==.Mortinir:BAAALgAECgEJAQAAAA==.',
Mu='Muneco:BAAALgADCgcJEAAAAA==.',
My='Mylina:BAAALgAECgMJBAAAAA==.Myor:BAAALgADCgUJBQAAAA==.Mystichex:BAAALgAECgEJAgABLgAECgkJFAAMAKAUAA==.Mystsouls:BAABLgAECn8gAAIRAAgJlQ8eXgDYAQARAAgJlQ8eXgDYAQAAAA==.',
['Må']='Måâgic:BAABLgAECn8UAAIJAAYJSwXY3wC5AAAJAAYJSwXY3wC5AAAAAA==.',
Na='Nagasaywhat:BAABLgAECn8bAAIJAAkJZQkeiQBKAQAJAAkJZQkeiQBKAQAAAA==.Nahari:BAAALgADCgIJAgAAAA==.Nalkoa:BAAALgAECgQJBAAAAA==.Narcissist:BAAALgAECgMJAgABLgAECggJOAAMAK8WAA==.Natalietes:BAAALgAECgQJBAAAAA==.Nattylight:BAAALgAECgYJCwAAAA==.Nattylite:BAAALgAECgEJAgABLgAECgkJEAAFAAAAAA==.',
Ne='Necronomicon:BAACLgAFFH8FAAMZAAIJcw62EQCQAAAZAAIJcw62EQCQAAAQAAEJJgPNtgA/AAAuAAQKfykAAxkACQkrHMsCAGYCABkACQmXG8sCAGYCABAABQkbFeWbACEBAAAA.Neetneetneet:BAAALgADCgMJAgAAAA==.Nemoglobine:BAAALgAECgMJAwAAAA==.Nethwarlock:BAAALgAFFAEJAQAAAA==.Newhealer:BAAALgADCgkJCQAAAA==.',
Ni='Niath:BAAALgAECgQJBQAAAA==.Nicetryally:BAAALgADCgMJAwAAAA==.Nightshroud:BAACLgAFFH8OAAIRAAMJiht6bQAEAQARAAMJiht6bQAEAQAuAAQKfzQAAhEACQlCJjEDAGQDABEACQlCJjEDAGQDAAAA.Niipz:BAAALgAECggJDwABLgAECgkJEAAFAAAAAA==.Nilie:BAAALgAECgEJAQAAAA==.Ninelinez:BAABLgAECn8jAAQTAAcJshymFwDZAQATAAcJshymFwDZAQAGAAQJ5wYvWACvAAAMAAEJ8R1ThwBSAAAAAA==.Ninjakiwiz:BAAALgADCgEJAQAAAA==.Ninjaknife:BAAALgADCgEJAQAAAA==.',
No='Noctaholic:BAAALgADCgMJBQAAAA==.Noctria:BAAALgAECgQJBwAAAA==.Nocturnalis:BAAALgADCgYJBgAAAA==.Nords:BAAALgAECgQJCgAAAA==.Nordswizard:BAAALgAECgEJAQAAAA==.Note:BAAALgAECgUJBQAAAA==.Novavanna:BAAALgADCgcJDAAAAA==.Noxistra:BAABLgAECn8fAAQaAAkJFBb/BwDMAQAaAAkJMRT/BwDMAQAQAAcJaBLwawBZAQAZAAMJBgRrXQBWAAAAAA==.Noyan:BAAALgAECgMJAwAAAQ==.',
Nu='Nukedawg:BAAALgAECgMJAwAAAA==.Nunchaku:BAABLgAECn8UAAIEAAcJdR/OEwDtAQAEAAcJdR/OEwDtAQAAAA==.',
['Nä']='Nägasäh:BAABLgAECn8mAAIRAAYJqSD0LwArAgARAAYJqSD0LwArAgAAAA==.',
['Nî']='Nîneline:BAAALgAECgYJEwABLgAECgcJIwATALIcAA==.',
['Nø']='Nørb:BAABLgAECn8jAAIJAAkJHxYqOAAhAgAJAAkJHxYqOAAhAgAAAA==.',
Ob='Obsessions:BAAALgADCgEJAQAAAA==.',
Of='Officyrdoofy:BAABLgAECn8yAAIUAAgJlhAUMAB5AQAUAAgJlhAUMAB5AQAAAA==.',
Og='Ogdirtymac:BAAALgADCgMJAwAAAA==.',
Oi='Oilie:BAAALgAECgEJAQAAAA==.Oilless:BAAALgAECgIJAgAAAA==.',
Oj='Ojhie:BAAALgAECgEJAQAAAA==.',
Ol='Olayro:BAAALgADCgcJBwABLgAECgEJAQAFAAAAAA==.Olgalina:BAAALgADCgYJBgAAAA==.Ollietrollie:BAAALgAECgcJEwAAAA==.',
Om='Ommateal:BAAALgAECgEJAgAAAA==.',
Op='Opirix:BAACLgAFFH8UAAINAAYJ1hp7BQDXAQANAAYJ1hp7BQDXAQAuAAQKfzAAAw0ACAn0IzIIAMgCAA0ACAn0IzIIAMgCAA4AAwlxGC5CAOkAAAAA.',
Or='Orcgirl:BAAALgAECgQJBgAAAA==.',
Os='Osburne:BAAALgAECgQJBAAAAA==.',
Ou='Ouidufromage:BAAALgAECgEJAQAAAA==.',
Ov='Overlandx:BAABLgAECn8VAAMHAAYJ2wXGsACkAAAHAAYJ2wXGsACkAAAgAAMJxAQyWgA8AAAAAA==.Overloaded:BAACLgAFFH8GAAIlAAMJiweFMACtAAAlAAMJiweFMACtAAAuAAQKfyEAAiUACQlvD/4nAJQBACUACQlvD/4nAJQBAAAA.',
Ow='Owlzkaban:BAAALgAECggJDwAAAA==.',
Ox='Oxelox:BAAALgADCgYJBwAAAA==.',
Oz='Ozzytbone:BAAALgAECgUJCQAAAA==.',
Pa='Paddfoot:BAAALgADCgQJBQAAAA==.Painkillerx:BAAALgAECgIJAgAAAA==.Palisa:BAAALgAECgUJCQAAAA==.Pancakeus:BAAALgAECgkJDwAAAA==.Panini:BAAALgAECgEJAQABLgAFFAIJBQAJACsDAA==.Panzurdin:BAAALgAECgMJAwAAAA==.Panzurlock:BAABLgAECn8gAAIQAAgJFx3PLgBSAgAQAAgJFx3PLgBSAgAAAA==.Panzurrkin:BAAALgAECgcJBwAAAA==.Papabelliswa:BAAALgADCgIJAgAAAA==.Papasquat:BAAALgAECgIJAwAAAA==.Paradiso:BAAALgAECgEJAgAAAA==.Parkane:BAAALgADCgQJBAAAAA==.Patreszas:BAABLgAECn8rAAMBAAkJeg3qKACEAQABAAkJMg3qKACEAQACAAYJ7gvlIwAIAQAAAA==.',
Pe='Peener:BAAALgADCgcJFQABLgADCgkJCwAFAAAAAA==.Pellere:BAAALgADCgMJAwAAAA==.Pemberton:BAABLgAECn8bAAIQAAgJKgggewA4AQAQAAgJKgggewA4AQAAAA==.Pepperboy:BAAALgADCgQJBAAAAA==.',
Ph='Pheauxbe:BAAALgADCgYJCAAAAA==.Pheauxly:BAAALgADCgYJDAAAAA==.Phlehm:BAABLgAECn8dAAMXAAcJ5BotJwADAgAXAAcJ5BotJwADAgAmAAIJBA3MawBxAAAAAA==.',
Pi='Pidpv:BAAALgAECgIJAgAAAA==.Piru:BAAALgAECgEJAQAAAA==.',
Pl='Plaguesire:BAAALgADCgYJDgAAAA==.Plutonyx:BAAALgAECgYJCgAAAA==.',
Po='Pocketstaz:BAAALgADCgUJBQAAAA==.Pohaberry:BAAALgAECgQJBwAAAA==.Pookiemookie:BAAALgAECgMJAwAAAA==.Popedk:BAACLgAFFH8IAAIRAAQJ+h4oNABtAQARAAQJ+h4oNABtAQAuAAQKfyEAAhEACQlRJFsHACwDABEACQlRJFsHACwDAAAA.',
Pr='Prannanm:BAAALgAECgYJCAAAAA==.Priestduude:BAAALgAECggJEgAAAA==.Priestpheus:BAAALgAECgEJAQAAAA==.Prismaticp:BAAALgADCgYJDAAAAA==.',
Ps='Psyger:BAAALgAECgYJDwAAAA==.',
Pu='Pullacrapton:BAAALgAECgcJDAAAAA==.Purecorrupt:BAAALgAECgIJAgAAAA==.Putridmeat:BAAALgAECggJEAAAAA==.',
Pw='Pwrsmoke:BAAALgAECgYJEgAAAA==.',
Qu='Quackery:BAAALgADCgIJAgAAAA==.Quiggins:BAABLgAECn8aAAIDAAgJDQVKtwD3AAADAAgJDQVKtwD3AAAAAA==.Quikbrownfox:BAABLgAFFH8KAAIEAAMJ0g67IgDlAAAEAAMJ0g67IgDlAAAAAA==.Quirkster:BAAALgAECgEJAgAAAA==.Quirky:BAAALgADCgcJBwAAAA==.',
Qw='Qweqweqwe:BAAALgAECgQJBgAAAA==.',
Ra='Raakoness:BAABLgAECn8WAAIkAAgJExP4EQC9AQAkAAgJExP4EQC9AQAAAA==.Raeziel:BAAALgAECgQJBQAAAA==.Raffunn:BAAALgAECgYJBwAAAA==.Rakoon:BAAALgADCgMJAwAAAA==.Rathindor:BAAALgADCgEJAQAAAA==.Razusirius:BAAALgAECgEJAgAAAA==.',
Rc='Rchris:BAAALgADCgEJAQAAAA==.',
Re='Rectivius:BAAALgADCgMJAwAAAA==.Reddknight:BAAALgAECgcJEwAAAA==.Reiker:BAAALgAECgYJCAAAAA==.Retzu:BAAALgAECgEJAQAAAA==.Rezme:BAAALgADCgMJAwAAAA==.',
Ri='Riccardo:BAAALgAECgEJBAAAAA==.Rickiebear:BAAALgADCgQJBwABLgADCgcJEgAFAAAAAA==.Rigor:BAABLgAECn8aAAIRAAkJhRcRKQBJAgARAAkJhRcRKQBJAgAAAA==.Rimeborn:BAAALgAECgEJAQAAAA==.Rivenn:BAAALgAECgEJAQABLgAFFAEJAQAFAAAAAA==.Rizzlesschud:BAAALgADCgMJAwAAAA==.Rizzlér:BAAALgADCgUJAwAAAA==.',
Ru='Rubonyx:BAAALgAECgEJAQAAAA==.Ruikai:BAAALgAECgEJAQAAAA==.Rune:BAAALgADCgcJBgAAAA==.',
Ry='Ryoko:BAABLgAECn8XAAMQAAYJKx0zcQBNAQAQAAUJlxszcQBNAQAZAAMJzBgiMwDrAAAAAA==.',
['Rä']='Rävaged:BAAALgAECgQJBAABLgAECggJFwAJAAEMAA==.',
Sa='Sagerin:BAAALgAECgUJDwAAAA==.Sageslife:BAAALgAECgQJCQABLgAECgYJCgAFAAAAAA==.Sailwe:BAAALgAECgIJAwAAAA==.Saintofthetp:BAAALgADCgUJCAAAAA==.Saison:BAAALgADCgYJBgAAAA==.Salém:BAAALgADCgUJBQAAAA==.Sambooka:BAAALgADCgQJBAAAAA==.Samwitwicky:BAAALgAECgQJBAAAAA==.Sanctifie:BAAALgAECgcJCQAAAA==.Saraaj:BAABLgAECn8UAAIQAAgJqRFTWgCDAQAQAAgJqRFTWgCDAQAAAA==.Sarallina:BAAALgADCgUJCQAAAA==.Sarifa:BAAALgADCgcJBwAAAA==.Saripotter:BAABLgAECn8UAAIJAAYJyhD6oQAdAQAJAAYJyhD6oQAdAQAAAA==.',
Sc='Scaleygirl:BAAALgADCgYJBgAAAA==.Scallion:BAAALgADCgIJAwAAAQ==.Scalythott:BAAALgAECgQJBAAAAA==.Scarr:BAAALgAECgUJBgAAAA==.Scorbunny:BAAALgAECgcJCgABLgAFFAQJDAAJAAAUAA==.Scruffmcgruf:BAABLgAECn8pAAINAAkJaRFlGgDfAQANAAkJaRFlGgDfAQAAAA==.Scubany:BAAALgADCgQJBAAAAA==.',
Se='Selem:BAAALgADCgUJBQABLgAECgcJFwAMAFoXAA==.Seth:BAABLgAFFH8JAAIHAAUJkgWqTQDiAAAHAAUJkgWqTQDiAAAAAA==.Sezeth:BAAALgAECgQJBAAAAA==.',
Sh='Shaboomboom:BAACLgAFFH8VAAIiAAUJMxmjBQBGAQAiAAUJMxmjBQBGAQAuAAQKfyMAAiIACAn/IVkEAJgCACIACAn/IVkEAJgCAAEuAAMKBgkGAAUAAAAA.Shadowglaive:BAACLgAFFH8FAAIHAAIJchN0aACPAAAHAAIJchN0aACPAAAuAAQKfy0AAgcACQkCHWQRAKQCAAcACQkCHWQRAKQCAAAA.Shalthorn:BAAALgADCgMJAwAAAA==.Shamful:BAAALgAECgkJAwAAAA==.Sharsu:BAACLgAFFH8YAAIQAAUJSyJsJgB+AQAQAAUJSyJsJgB+AQAuAAQKfzIAAhAACQliJYsGAFYDABAACQliJYsGAFYDAAAA.Shew:BAAALgAECgYJEwAAAA==.Shewadin:BAAALgAECgYJCAAAAA==.Shewcifer:BAAALgAECgMJBwAAAA==.Shewtrmcgavn:BAAALgADCgkJCQAAAA==.Sheylai:BAAALgAECgEJAQAAAA==.Shinwa:BAAALgADCgEJAQABLgAECggJLQAEALMZAA==.Shortcake:BAAALgAECgMJAwABLgAFFAMJCgAEANIOAA==.',
Si='Silhouete:BAAALgAECgEJAQAAAA==.',
Sk='Skaborn:BAABLgAECn8VAAIJAAgJIhShYwCeAQAJAAgJIhShYwCeAQAAAA==.Skillitor:BAAALgADCgcJBwAAAA==.Skillman:BAAALgAECgUJCQAAAA==.Skrizik:BAAALgAECgIJAgAAAA==.Skullshine:BAACLgAFFH8ZAAMRAAcJhx5SHgCyAQARAAcJhx5SHgCyAQASAAEJAAAHSQAAAAAuAAQKfyUAAhEACQmYJI0KAAoDABEACQmYJI0KAAoDAAAA.Skunkie:BAABLgAECn8pAAMcAAkJUh15CgD4AgAcAAkJUh15CgD4AgAlAAQJnA5qWAC/AAAAAA==.Skybreaker:BAAALgAFFAEJAQAAAA==.',
Sl='Sluewt:BAABLgAECn8iAAIDAAgJ8xYpXgCcAQADAAgJ8xYpXgCcAQAAAA==.Slumpd:BAAALgAECgcJBwAAAA==.Slumps:BAAALgAECgYJBwAAAA==.Slushadin:BAAALgAECgUJCQABLgAECgkJIwAJAB8WAA==.Slushpuppy:BAAALgADCgEJAQAAAA==.Slyvanfan:BAAALgAECgIJAgAAAA==.Slìquid:BAAALgADCgUJBQAAAA==.',
Sm='Smileysabear:BAABLgAECn8cAAIXAAgJig8CPgCIAQAXAAgJig8CPgCIAQAAAA==.Smileysalock:BAAALgADCgcJBwABLgAECggJHAAXAIoPAA==.Smolderr:BAABLgAECn8mAAMVAAgJcgbQGADWAAAIAAYJhgWkogDeAAAVAAcJRwbQGADWAAAAAA==.',
Sn='Sneasel:BAAALgAECgQJBwABLgAFFAQJDAAJAAAUAA==.',
So='Soapydish:BAAALgAECgMJAwAAAA==.Solknight:BAAALgAECgQJBQABLgAECgYJDAAFAAAAAA==.Soulshart:BAAALgAECgcJBQAAAA==.',
Sp='Spacerift:BAABLgAFFH8bAAIdAAgJdB4hAQD3AQAdAAgJdB4hAQD3AQAAAA==.Spaciousyeti:BAAALgAECggJEAAAAA==.Sparhawke:BAAALgADCgkJEAAAAA==.Spawne:BAABLgAECn8aAAIHAAkJBxS0NQDZAQAHAAkJBxS0NQDZAQAAAA==.Spearowhunt:BAAALgAECgQJAwAAAA==.Spearowmage:BAAALgADCgYJBgAAAA==.Spearowpally:BAABLgAECn8VAAIDAAkJqQ1OdwBlAQADAAkJqQ1OdwBlAQAAAA==.Spellomode:BAABLgAECn8cAAMJAAgJJxVvVgDBAQAJAAgJQxRvVgDBAQALAAEJ5RP6EQA9AAAAAA==.Spilt:BAAALgAECgEJAQAAAA==.Splits:BAABLgAECn8UAAQPAAgJyA7MDQAYAQAPAAcJSgzMDQAYAQAEAAYJsQyMLwAGAQAfAAUJNA6xEgDmAAAAAA==.',
St='Stanhorn:BAAALgADCgIJAQAAAA==.Starrscream:BAAALgAECgkJBAAAAA==.Stazxd:BAAALgAECgIJAgAAAA==.Steezyah:BAAALgAECgcJDgAAAA==.Stevebrule:BAAALgAECgEJAQAAAA==.Stinkler:BAAALgAECgUJBQAAAA==.Stirrup:BAAALgAECgQJBAAAAA==.Stomach:BAAALgAECgUJDwAAAA==.Stornhas:BAAALgAECgUJBQAAAA==.Strikbrkr:BAAALgAECgQJBgAAAA==.Strikerj:BAAALgAECgQJBAAAAA==.Strànge:BAAALgADCgUJBQAAAA==.Stun:BAABLgAECn8cAAIEAAgJDg0kHgCLAQAEAAgJDg0kHgCLAQAAAA==.Stunllub:BAABLgAECn8WAAIRAAgJNBMiaQCAAQARAAgJNBMiaQCAAQAAAA==.',
Su='Suggs:BAACLgAFFH8VAAIQAAYJmxvcFwC6AQAQAAYJmxvcFwC6AQAuAAQKfyEABBAACQkqJNYOAAMDABAACAmUJNYOAAMDABkAAgl4GhJMAIkAABoAAQkAAKIoAE8AAAAA.Sunwelldone:BAAALgADCgYJDAAAAA==.Supaatits:BAAALgAECgkJEAAAAA==.Superali:BAAALgAECgEJAgAAAA==.Surnaturelle:BAAALgADCgkJDAABLgAECgkJKwAiAAQTAA==.',
Sy='Sylariel:BAAALgAECgQJBQAAAA==.Sylbane:BAAALgADCgQJBAAAAA==.Sylviai:BAAALgAECgQJCAAAAA==.Sylviex:BAAALgADCgIJAgAAAA==.Syphyr:BAAALgADCgQJBwAAAA==.Syradael:BAAALgADCgUJBQAAAA==.Sythyn:BAAALgADCgUJBQAAAA==.',
['Sâ']='Sâmurai:BAAALgAECgEJAQAAAA==.',
['Sæ']='Sæd:BAAALgAECgYJDAAAAA==.',
Ta='Taelinn:BAAALgADCgkJDAABLgAECgkJKwABAHoNAA==.Talet:BAAALgAECgMJAwAAAA==.Tallyjaber:BAAALgAECgEJAQAAAA==.Tastymelo:BAAALgAECgEJAQAAAA==.Taterthott:BAABLgAECn8WAAQNAAcJ6AquSAAWAQANAAcJSgiuSAAWAQAoAAYJ7AXQPgC3AAAOAAMJPgPtbwA+AAAAAA==.Tauriko:BAABLgAECn8UAAIDAAcJoRo8ZACOAQADAAcJoRo8ZACOAQAAAA==.Tayvos:BAAALgAECgkJAwAAAA==.',
Te='Telma:BAAALgAECgYJCgAAAA==.Teradin:BAAALgAECgEJAQAAAA==.Teratori:BAAALgADCgIJAwAAAA==.Terrorknight:BAABLgAECn8hAAIRAAkJUBegPQD4AQARAAkJUBegPQD4AQAAAA==.',
Th='Thams:BAAALgAECggJEQAAAA==.Thebestlorax:BAAALgADCgMJAwABLgAFFAMJCgAEANIOAA==.Thehuntayed:BAAALgADCgkJEgAAAA==.Theldrus:BAAALgAECgYJEAAAAA==.Theradestria:BAAALgAECgUJDwAAAA==.Theranonis:BAAALgADCgYJAwAAAA==.Thestigg:BAAALgAECgYJEQAAAA==.Thighighs:BAABLgAFFH8PAAIPAAQJXhsmAwBbAQAPAAQJXhsmAwBbAQABLgAFFAQJBgAWAB4RAA==.Thirienet:BAAALgAECgYJBwAAAA==.Threaten:BAAALgADCgUJCQAAAA==.Thunderballz:BAAALgADCgkJFwAAAA==.Thunderfall:BAAALgAECgYJEgAAAA==.Thyrä:BAAALgADCgkJHAAAAA==.Thëspiän:BAAALgAECgEJAgAAAA==.',
Ti='Tihro:BAAALgAECgcJEQAAAA==.Timmyjam:BAABLgAECn88AAMZAAkJyRLdBgDQAQAZAAkJyRLdBgDQAQAQAAEJAAAWNgEHAAAAAA==.Tiradia:BAABLgAECn8oAAIVAAcJECYcCgACAwAVAAcJECYcCgACAwAAAA==.Tishekk:BAAALgAECgQJBgAAAA==.Tiustommert:BAAALgAECgQJBAABLgAFFAYJGgAMAAIdAA==.',
To='To:BAAALgAECgEJAQAAAA==.Toffersox:BAAALgAECgYJDgABLgAFFAMJBAAFAAAAAA==.Totemme:BAAALgADCgYJBgAAAA==.',
Tr='Traianus:BAAALgAECgMJAwAAAA==.Traxi:BAAALgAECgQJBAAAAA==.Traynnissa:BAAALgAECgkJDAAAAA==.Treexa:BAAALgADCgQJBAAAAA==.Trorbitach:BAAALgAECgQJBAABLgAFFAYJGgAMAAIdAA==.',
Tu='Tutankhamun:BAABLgAECn8aAAMDAAgJxRM0YgCSAQADAAcJIRI0YgCSAQAnAAYJnQx/JgDGAAAAAA==.',
Tv='Tvenom:BAABLgAECn8UAAIDAAYJgRRPgwBzAQADAAYJgRRPgwBzAQAAAA==.',
Tw='Twistybanana:BAAALgAECgYJDAAAAA==.Twofourfive:BAAALgADCgEJAQAAAA==.',
Ty='Tyinastor:BAAALgAECgYJEQAAAA==.',
['Tö']='Töme:BAAALgAECgEJAQAAAA==.',
['Tø']='Tømb:BAAALgAECgQJBQABLgAFFAQJBwABANARAA==.',
Ud='Udderless:BAAALgAECgUJDAAAAA==.',
Uh='Uhhtari:BAAALgAECgMJAwAAAA==.',
Un='Unbëärable:BAAALgADCggJEAAAAA==.',
Ur='Urmomlikesit:BAAALgADCgEJAQAAAA==.',
Ut='Uthers:BAAALgADCgYJBgABLgAECgUJBQAFAAAAAA==.',
Va='Vaalhazak:BAAALgAECgIJBAAAAA==.Vaehei:BAAALgADCgMJAwAAAA==.Valdril:BAAALgADCgcJBwAAAA==.Valky:BAAALgAECgYJCgAAAA==.Vallasher:BAABLgAFFH8GAAIdAAMJrxLNGAC5AAAdAAMJrxLNGAC5AAAAAA==.Vanhealín:BAAALgAFFAEJAQAAAA==.Varauge:BAAALgAECgMJAwAAAA==.',
Ve='Vecx:BAAALgAECgMJAwABLgAECgYJDQAFAAAAAA==.Veiyn:BAAALgADCgYJBgAAAA==.Veldispel:BAAALgAECgYJCgAAAA==.Velemental:BAAALgAECgIJBQAAAA==.Velgy:BAAALgAECgQJBAAAAA==.Velofmist:BAAALgADCgUJBgAAAA==.Velro:BAABLgAECn8lAAMIAAgJmSO1EgCmAgAIAAgJmSO1EgCmAgAVAAcJlBfDJQD7AQAAAA==.Venecia:BAAALgADCgkJCAAAAA==.Venomfang:BAAALgAECgcJBwAAAA==.Versë:BAAALgAECgEJAQAAAA==.Vexira:BAAALgADCgYJBgAAAA==.Vextrex:BAAALgAECgEJAQABLgAECgkJHgADAJwSAA==.Vexõr:BAAALgAECgYJBgAAAA==.',
Vh='Vhalaan:BAAALgADCgMJAwAAAA==.',
Vi='Vianir:BAABLgAECn8rAAIDAAkJCBMKPwDyAQADAAkJCBMKPwDyAQAAAA==.Viann:BAAALgADCgYJCgAAAA==.Vimora:BAAALgADCgcJAQABLgAECggJGgABAEcLAA==.Vitals:BAAALgAECgcJDAAAAA==.Vitamin:BAAALgAECggJDAAAAA==.',
Vo='Voidness:BAAALgAECgYJCgAAAA==.Voldanis:BAAALgAECgkJAQAAAA==.Volpris:BAAALgAECgEJAQABLgAECggJGgABAEcLAA==.Volzuka:BAAALgAECgEJAQAAAA==.',
Vu='Vulsutyr:BAAALgADCgMJAwAAAA==.Vurse:BAAALgADCgMJAwAAAA==.',
Vy='Vyndeyice:BAAALgAECgEJAQAAAA==.',
['Vá']='Vál:BAAALgAECgYJCAAAAA==.',
['Vé']='Véxør:BAABLgAECn8/AAQmAAkJIhpoEABFAgAmAAgJBhxoEABFAgAXAAgJHQ3ZSABYAQAjAAcJchHDJAAFAQAAAA==.',
['Vê']='Vêxor:BAAALgAFFAMJAwAAAA==.',
['Vë']='Vësper:BAAALgAECgcJDQAAAA==.',
Wa='Waffel:BAAALgAECgEJAQAAAA==.Wafulol:BAACLgAFFH8FAAIDAAMJTAMQbACrAAADAAMJTAMQbACrAAAuAAQKfzYAAgMACAnOGB06ADsCAAMACAnOGB06ADsCAAAA.Warhawkyo:BAAALgAECgYJBwAAAA==.Warlockios:BAAALgAECgEJAQAAAA==.Warmsoup:BAAALgADCgMJAwAAAA==.Warscared:BAABLgAECn8lAAIdAAYJ7ggBLQC6AAAdAAYJ7ggBLQC6AAAAAA==.Wasil:BAAALgADCgIJAgAAAA==.Waxxpoet:BAAALgAECgMJBQAAAA==.',
We='Wels:BAABLgAECn8UAAINAAcJYRZyHgC5AQANAAcJYRZyHgC5AQAAAA==.',
Wh='Whichwitch:BAAALgADCgUJBQAAAA==.Whist:BAAALgADCgEJAgAAAA==.Whiteagle:BAAALgADCgEJAQAAAA==.',
Wi='Widgets:BAAALgADCgcJBwAAAA==.Wigglypuffsr:BAAALgAECggJDQAAAA==.Wiikkid:BAAALgAECgYJEQAAAA==.Winddrake:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfrey:BAAALgAECgEJAQAAAA==.',
Wr='Wrathborne:BAAALgADCgMJAwAAAA==.Wriggle:BAAALgAECgUJBQAAAA==.',
Xa='Xaanu:BAAALgADCgUJBQAAAA==.Xaclov:BAABLgAECn8XAAMRAAYJsRX8lQAnAQARAAYJNxT8lQAnAQASAAEJmxh4QQBGAAAAAA==.Xalcor:BAEALgAECgQJBQAAAA==.Xanelivan:BAAALgAECgQJBAAAAA==.Xanneste:BAAALgAECgMJBgAAAA==.Xano:BAAALgAECgYJDwAAAA==.Xarius:BAAALgAECgUJDQAAAA==.Xayne:BAAALgAECgQJBgAAAA==.',
Xe='Xephryus:BAAALgADCgEJAQAAAA==.',
Xi='Xiz:BAAALgAECgEJAQAAAA==.',
Xo='Xorlandu:BAAALgAECggJCQAAAA==.',
Xx='Xxchan:BAAALgAECgUJBQAAAA==.',
Xy='Xylotus:BAAALgAECgUJEAABLgAFFAEJAQAFAAAAAA==.',
Ya='Yahtzeé:BAACLgAFFH8JAAMDAAQJZwz3awCsAAADAAMJnQP3awCsAAAhAAMJuQIUMgCMAAAuAAQKfysAAyEACQmbEEIfAPMBACEACQmbEEIfAPMBAAMABQkRCCX7AJ0AAAAA.',
Yo='Yokaihp:BAAALgADCgMJAwAAAA==.Yondü:BAAALgAECgUJCwAAAA==.Yoshii:BAAALgAECgUJBQAAAA==.',
Yu='Yujirø:BAABLgAECn8TAAIHAAYJPR6UaAA6AQAHAAYJPR6UaAA6AQABLgAFFAMJBgAbAIodAA==.Yuubel:BAAALgADCgkJGQAAAA==.',
Za='Zale:BAAALgAECgIJAgAAAA==.Zanpakuto:BAABLgAECn8bAAMGAAcJmyKrEwAKAgAGAAcJeSCrEwAKAgATAAQJVSIrIgCGAQAAAA==.Zatay:BAAALgADCgUJBQAAAA==.Zayday:BAAALgADCgEJAQAAAA==.',
Ze='Zedawg:BAAALgAECgUJDQAAAA==.Zelkrys:BAAALgAECgYJCgAAAA==.Zenfemboy:BAACLgAFFH8fAAITAAcJUSb7AACoAgATAAcJUSb7AACoAgAuAAQKfykAAhMACQkfJuMBAIYDABMACQkfJuMBAIYDAAAA.Zerofoxx:BAAALgADCgMJAwAAAA==.',
Zh='Zhdun:BAAALgAECggJDgAAAA==.',
Zi='Zidalix:BAAALgADCgkJCQAAAA==.Ziweix:BAAALgAECgUJBQAAAA==.',
Zo='Zolmijin:BAABLgAECn8qAAMkAAkJsxeOCwAVAgAkAAkJsxeOCwAVAgAdAAUJ3w/1LgCuAAAAAA==.Zombiekush:BAAALgADCgMJBAAAAA==.Zoëy:BAAALgAECgIJAgAAAA==.',
Zu='Zugomik:BAAALgAECggJEgAAAA==.Zukini:BAAALgADCgMJAQAAAA==.Zurydh:BAAALgAECgkJBwAAAA==.Zuul:BAAALgAECgQJCgAAAA==.Zuulax:BAAALgAECgUJDQAAAA==.',
Zy='Zylin:BAAALgAECgkJBwAAAA==.',
['Zæ']='Zæn:BAAALgAECgUJBQAAAA==.',
['Zé']='Zéddicus:BAAALgADCgEJAQAAAA==.',
['Ça']='Çasey:BAAALgAECgYJDQAAAA==.',
['Çh']='Çhèètö:BAAALgAECgEJAQAAAA==.',
['Çé']='Çélädor:BAACLgAFFH8aAAIDAAUJoyFeFwCEAQADAAUJoyFeFwCEAQAuAAQKfy0AAgMACQkvJD8MAO8CAAMACQkvJD8MAO8CAAAA.',
['Çü']='Çürzê:BAAALgADCgMJAwAAAA==.',
['Èm']='Èmrys:BAAALgAECgcJBQAAAA==.',
['Öb']='Öbi:BAAALgAECgYJDAAAAA==.',
['Ör']='Örin:BAABLgAECn83AAIfAAkJVSOcAAA9AwAfAAkJVSOcAAA9AwAAAA==.',
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
