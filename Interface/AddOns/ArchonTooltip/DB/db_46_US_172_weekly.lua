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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Paladin-Holy','Mage-Arcane','Druid-Guardian','Druid-Balance','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','Hunter-Marksmanship','DemonHunter-Vengeance','Monk-Mistweaver','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','DeathKnight-Frost','Priest-Discipline','Hunter-Survival','Warrior-Arms','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adrador:BAABLgAECn8mAAMBAAgJkiRrAgC/AgABAAgJkiRrAgC/AgACAAIJZxTtEwFvAAAAAA==.Adrenaline:BAACLgAFFH8OAAIDAAQJrh7SBwBUAQADAAQJrh7SBwBUAQAuAAQKfzcAAgMACQmEI+EBAAsDAAMACQmEI+EBAAsDAAAA.',
Ae='Aelik:BAACLgAFFH8GAAIEAAMJQgudaQCcAAAEAAMJQgudaQCcAAAuAAQKfygAAgQACAmMHF8rAA0CAAQACAmMHF8rAA0CAAAA.Aeolian:BAAALgADCgMJAwAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8kAAIFAAkJfB6XEQC9AgAFAAkJfB6XEQC9AgAAAA==.Alda:BAAALgADCgkJEQAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAABLgAECn8ZAAIHAAgJzgi5OQBoAQAHAAgJzgi5OQBoAQAAAA==.',
Am='Amilee:BAAALgAECgQJCQAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8JAAIIAAMJkiDADQAYAQAIAAMJkiDADQAYAQAuAAQKfyAAAggACQlPIG4EAAEDAAgACQlPIG4EAAEDAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLglLPABcAQAJAAkJLglLPABcAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJBAABLgAECgcJCQAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAECgcJEwAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJCAABLgAECgYJBgAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAIJBgAKAK4gAA==.Arrogance:BAAALgADCgcJBwABLgAECgYJBgAGAAAAAA==.Arthia:BAAALgAECgQJDwAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAECggJJAADAAUbAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAECgYJCAAAAA==.Attima:BAABLgAECn84AAILAAkJDg/CAgDZAQALAAkJDg/CAgDZAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8iAAMMAAgJ5wisIADHAAANAAcJwgcQNwDhAAAMAAgJiAisIADHAAAAAA==.',
Av='Avaryn:BAACLgAFFH8OAAIJAAQJwhBSIAAGAQAJAAQJwhBSIAAGAQAuAAQKfzYAAgkACQlfISgGACMDAAkACQlfISgGACMDAAAA.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgcJEwABLgAECgkJOwAOABAfAA==.Badaracka:BAAALgAECgEJAQABLgAECgkJOwAOABAfAA==.Badarackie:BAABLgAECn87AAMOAAkJEB+dCQDvAgAOAAgJ0iGdCQDvAgAPAAgJexWUFADFAQAAAA==.Badash:BAABLgAECn8kAAMDAAgJBRs7CgAGAgADAAgJBRs7CgAGAgAQAAEJMQSurQAvAAAAAA==.Bahamuth:BAABLgAECn86AAICAAkJkxunGwBfAgACAAkJkxunGwBfAgAAAA==.Bakshi:BAAALgAECgEJAwAAAA==.Barbattos:BAACLgAFFH8MAAIRAAQJohe0DwA4AQARAAQJohe0DwA4AQAuAAQKfzYAAxEACQkOJKABAEQDABEACQkOJKABAEQDABIAAQnkJGVdAGIAAAAA.Barnabas:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Barragon:BAAALgAECgYJDwAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8kAAIBAAkJBRl5BgAtAgABAAkJBRl5BgAtAgAAAA==.',
Bi='Biggerbunny:BAABLgAECn8sAAITAAgJthSrGACvAQATAAgJthSrGACvAQAAAA==.Binkter:BAAALgAECgIJBAABLgAECgEJAQAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJEQABLgAECgkJKwAUAB4lAA==.Blargle:BAABLgAECn8cAAIVAAgJNAwiSwBoAQAVAAgJNAwiSwBoAQAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Bloodrake:BAABLgAECn87AAIVAAkJHB6mDQDRAgAVAAkJHB6mDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.',
Bo='Boahan:BAAALgAECgMJBQABLgAECgUJCAAGAAAAAA==.Boggart:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgEJAgAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8uAAMKAAgJbhsZCwCUAgAKAAgJbhsZCwCUAgACAAMJmgtw9wBlAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8YAAMWAAcJVhj4CAC3AQAWAAYJ3Rj4CAC3AQAXAAYJeQ0+fQAEAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.',
Bu='Bubbloseven:BAAALgAECgQJBgAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAAALgAECgYJDwAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8LAAIQAAMJzwz+IgDYAAAQAAMJzwz+IgDYAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJBQAAAA==.Calibre:BAABLgAECn8eAAIYAAcJohX7SABeAQAYAAcJohX7SABeAQAAAA==.Calyptus:BAABLgAECn8cAAIXAAYJgAqrhAD0AAAXAAYJgAqrhAD0AAAAAA==.Caprious:BAACLgAFFH8NAAIEAAQJURnYJwALAQAEAAQJURnYJwALAQAuAAQKfzYAAgQACQnhJNUEADIDAAQACQnhJNUEADIDAAAA.Capylaura:BAAALgAECgUJDgAAAA==.Caratine:BAABLgAECn8UAAIYAAcJigkFdADoAAAYAAcJigkFdADoAAAAAA==.Cassandrar:BAABLgAECn8yAAQZAAkJGSQIAQA5AwAZAAgJMiQIAQA5AwAaAAYJtiBfEgDAAQAbAAEJphSyFwA7AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJMgAZABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAABLgAECn8WAAIJAAYJpgh2XwDUAAAJAAYJpgh2XwDUAAAAAA==.',
Ce='Celìa:BAABLgAECn8cAAIVAAgJxwe9WwA4AQAVAAgJxwe9WwA4AQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chema:BAAALgAFFAIJAwABLgAFFAIJBgAKAK4gAA==.Chestylarue:BAAALgAECgEJAQABLgAECgYJCgAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAQJDQAEAGceAA==.Christy:BAAALgADCgkJEQAAAA==.Chugg:BAABLgAECn8cAAIcAAgJbgi1SQAmAQAcAAgJbgi1SQAmAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8eAAICAAkJfBM5MQD1AQACAAkJfBM5MQD1AQAAAA==.Cinnamonster:BAAALgADCgEJAQAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJCgAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAINAAcJDSArFgBeAgANAAcJDSArFgBeAgAAAA==.',
Cu='Cubcake:BAAALgADCggJCAAAAA==.Curtastrophe:BAABLgAECn89AAIFAAkJHh39FgCXAgAFAAkJHh39FgCXAgAAAA==.Curticus:BAAALgADCgQJBAAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIQAAgJOxjUHwCkAQAQAAgJOxjUHwCkAQABLgAFFAIJAgAGAAAAAA==.Dalinar:BAAALgAECgMJBgAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECgYJBwAGAAAAAA==.',
De='Deadtauren:BAAALgADCgYJDwAAAA==.Deathdemon:BAAALgAECgIJAgAAAA==.Deathfue:BAAALgAECgEJAwABLgAECgcJCQAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgQJBwAGAAAAAA==.Decimated:BAACLgAFFH8NAAIEAAQJZx5zMQD7AAAEAAQJZx5zMQD7AAAuAAQKfxwAAgQACQmMHzEbAGICAAQACQmMHzEbAGICAAAA.Demon:BAAALgAECgUJCQAAAA==.Demonilla:BAAALgAECgMJAwAAAA==.Dempkiston:BAAALgADCggJCQAAAA==.Denable:BAABLgAECn8VAAIJAAUJbQ1rXwDUAAAJAAUJbQ1rXwDUAAAAAA==.Denogan:BAAALgAECgUJBgABLgAECgYJEwAGAAAAAA==.Deservis:BAAALgAECgUJDgABLgAECgcJHgAYAKIVAA==.Destro:BAABLgAECn8eAAIXAAgJgQ/dSgB9AQAXAAgJgQ/dSgB9AQABLgAECgkJLQAdAAgWAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgMJBAAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAAALgAECgYJEgAAAA==.Discoflurry:BAAALgAECgcJDQABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECgYJEwAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDwAAAA==.Dogsoldier:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgAFFAIJAgAAAA==.',
Dp='Dpskuk:BAAALgADCgMJAwAAAA==.',
Dr='Dragan:BAAALgAECgQJCAAAAA==.Dragapult:BAAALgAECggJAwAAAA==.Dragonias:BAABLgAECn8VAAIeAAcJQRNqDgD+AAAeAAcJQRNqDgD+AAAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgAECgIJAgAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAcJGAAVAIshAA==.Drinny:BAABLgAECn8yAAIIAAkJtwjvIwBdAQAIAAkJtwjvIwBdAQAAAA==.Drqueenisin:BAAALgADCggJEwAAAA==.Druido:BAAALgADCgYJCwAAAA==.',
Du='Duerek:BAAALgAECgEJAgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
Ea='Earthangel:BAABLgAECn8WAAIIAAUJGxWyLgARAQAIAAUJGxWyLgARAQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECgYJBgAGAAAAAA==.',
Ei='Eine:BAABLgAECn85AAIVAAkJDxWoIAAVAgAVAAkJDxWoIAAVAgAAAA==.Eitherwind:BAAALgAECgYJEwAAAA==.',
El='Eldergreen:BAABLgAECn8iAAIJAAgJzAkNUwD/AAAJAAgJzAkNUwD/AAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAABLgAECn8VAAITAAUJDwqiPwC7AAATAAUJDwqiPwC7AAAAAA==.Elindria:BAABLgAECn8rAAQUAAkJHiVAAQA7AwAUAAkJHiVAAQA7AwAfAAUJmiO6CACSAQAYAAQJUhq6ewA0AQAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAAALgAECgcJCwAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn8vAAQPAAkJSCCpCQBiAgAPAAgJaR+pCQBiAgAgAAkJphW/IQClAQAOAAIJyh9GRQCuAAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCgAAAA==.',
Eo='Eotech:BAAALgADCggJCAAAAA==.',
Er='Erendora:BAABLgAECn8XAAIJAAcJDBCoQwA6AQAJAAcJDBCoQwA6AQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgUJEAAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Ev='Eva:BAAALgAECgEJAgAAAA==.Eviae:BAABLgAECn8WAAIhAAUJuAl8LQCUAAAhAAUJuAl8LQCUAAAAAA==.Evillure:BAABLgAECn8dAAMEAAgJAxN5RgCqAQAEAAgJAxN5RgCqAQAhAAUJjAmLLQCTAAAAAA==.',
Fa='Falan:BAABLgAECn8ZAAIcAAgJnhHDLQCnAQAcAAgJnhHDLQCnAQAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEBLgAECn8VAAIZAAcJSCP8AgBOAgAZAAcJSCP8AgBOAgABLgAECgYJCgAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJCgAAAA==.Fentril:BAAALgADCgIJAgABLgAECgYJEwAGAAAAAA==.Feår:BAABLgAECn8dAAMXAAkJJAw7XABNAQAXAAgJQQo7XABNAQAiAAMJ3Q8RSwCMAAAAAA==.',
Fi='Finley:BAAALgAECgQJBQAAAA==.Fircane:BAAALgADCgQJBAAAAA==.',
Fl='Flane:BAAALgAFFAEJAQABLgAFFAYJFgADAB8iAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgUJBgAAAA==.',
Fo='Foog:BAAALgAECgQJBAAAAA==.',
Fr='Fragil:BAABLgAECn8pAAIaAAcJ8xuTFgCSAQAaAAcJ8xuTFgCSAQAAAA==.Frostmane:BAACLgAFFH8JAAIEAAMJyB2CXQCoAAAEAAMJyB2CXQCoAAAuAAQKfzAAAwQACQloJOoGAA4DAAQACQloJOoGAA4DACEABwn+HMANADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Fudge:BAAALgADCgYJBgAAAA==.Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAABLgAECn8UAAIJAAcJKAkKUwD/AAAJAAcJKAkKUwD/AAAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJCgAAAA==.',
Gi='Girion:BAABLgAECn8WAAIBAAUJswxDJgCTAAABAAUJswxDJgCTAAAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8KAAMYAAQJSwubNgAAAQAYAAQJpwibNgAAAQAfAAIJuA8OCABpAAAuAAQKfy0AAx8ACQmVIXsCAI8CABgACQkrH6EdAKACAB8ACQmXHHsCAI8CAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgUJDgAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAABLgAECn8vAAMSAAkJ5x9lBQDXAgASAAkJ5x9lBQDXAgAjAAQJdgY1LgCoAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAQJDQAEAGceAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECgcJDgAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn8oAAIRAAgJpBO8CwDSAQARAAgJpBO8CwDSAQAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCQAGAAAAAA==.Halnan:BAAALgADCgEJAQABLgAECgcJHgAYAKIVAA==.Harkanum:BAABLgAECn89AAQRAAkJGg1bDQCyAQARAAkJGg1bDQCyAQAjAAQJ1BiPCwAaAQASAAQJrxMmSAC3AAAAAA==.Hartman:BAAALgADCgcJBwAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECggJCQAAAA==.',
He='Healinturds:BAAALgAECgYJDAABLgAECgcJHgAYAKIVAA==.Hector:BAABLgAECn8eAAICAAkJfCKWFACMAgACAAkJfCKWFACMAgAAAA==.Heelys:BAAALgAECgUJCQAAAA==.Helloagain:BAACLgAFFH8PAAIFAAQJxxi3KQBiAQAFAAQJxxi3KQBiAQAuAAQKfyAAAgUABglqIyFdACMCAAUABglqIyFdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgADCggJCwAAAA==.',
Hi='Hidethetotem:BAABLgAECn8bAAIcAAcJPh2YFgBDAgAcAAcJPh2YFgBDAgAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8LAAICAAQJCA6zKAAwAQACAAQJCA6zKAAwAQAuAAQKfxwAAgIACAnOHeAsAHACAAIACAnOHeAsAHACAAAA.Hiown:BAAALgAECgEJAQAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgADCgUJBQAAAA==.Holyspike:BAABLgAECn8UAAIcAAcJ+g//OwBfAQAcAAcJ+g//OwBfAQAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAAALgAECggJDQAAAA==.Holytickles:BAABLgAECn8rAAMIAAkJMRdkDABWAgAIAAkJMRdkDABWAgATAAgJ+hvFEwDjAQABLgAFFAYJEAAXAIcTAA==.Holytotem:BAAALgADCggJCAAAAA==.Homerr:BAABLgAECn8UAAIVAAcJzw9BWwA5AQAVAAcJzw9BWwA5AQAAAA==.Honiahaka:BAABLgAECn86AAIVAAkJfw7lMwC8AQAVAAkJfw7lMwC8AQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJEAAXAIcTAA==.',
Hu='Huckster:BAABLgAECn8ZAAIEAAgJhg6GWAB2AQAEAAgJhg6GWAB2AQAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ6CQBIAwACAAgJXSQ6CQBIAwABAAEJbgXWTQAYAAABLgAFFAMJBwAUAAIYAA==.Humanoidhunt:BAAALgAECgIJAwABLgAFFAMJBwAUAAIYAA==.Humanoidvoid:BAACLgAFFH8HAAMUAAMJAhgIBwDzAAAUAAMJoBUIBwDzAAAYAAEJriKaZABhAAAuAAQKf0UABBgACQm7IH0LALMCABgACAk6I30LALMCABQACAnlH7MFAJYCAB8ACAkoCAcPAAsBAAAA.',
Hy='Hydrah:BAAALgAECgEJAQABLgAECgcJCQAGAAAAAA==.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgAECgEJAQAAAA==.',
Ih='Ihatemustard:BAABLgAECn8aAAIfAAkJnBIiBgDiAQAfAAkJnBIiBgDiAQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgAECgEJAQAAAA==.',
In='Inoru:BAAALgAECgYJCAAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAABLgAECn8UAAIIAAcJthKIIAB5AQAIAAcJthKIIAB5AQAAAA==.',
It='Ithurtshuh:BAAALgAECgQJBwAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAABLgAECn8tAAMVAAgJLxuuJQD7AQAVAAgJLxuuJQD7AQAeAAIJ1QrseQBaAAAAAA==.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgIJAgABLgAECgcJIAACAAEaAA==.Jakoby:BAAALgAECgUJBQABLgAECgcJIAACAAEaAA==.Jandrisel:BAAALgAECgYJBwAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAABLgAECn84AAIZAAgJHCGmAgDDAgAZAAgJHCGmAgDDAgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn89AAIcAAkJ5B/hBAAhAwAcAAkJ5B/hBAAhAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8MAAIXAAQJPQ9iOQAcAQAXAAQJPQ9iOQAcAQAuAAQKfyIAAhcACQnvHg42ADQCABcACQnvHg42ADQCAAAA.',
Ji='Jilara:BAABLgAECn8hAAICAAcJNQZNlQAAAQACAAcJNQZNlQAAAQAAAA==.Jimmyjim:BAAALgAECgcJEwAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8sAAMXAAkJJRPWKgDyAQAXAAkJJRPWKgDyAQAiAAMJxwjoRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECgcJIAACAAEaAA==.',
Ka='Kahlanrahl:BAAALgADCgMJAwAAAA==.Kaiatra:BAABLgAECn8TAAIkAAYJJyIYBwCwAQAkAAYJJyIYBwCwAQAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8eAAICAAYJDiO8MwDsAQACAAYJDiO8MwDsAQAAAA==.',
Ke='Kellytgt:BAABLgAECn8qAAIYAAgJxBh8KADiAQAYAAgJxBh8KADiAQAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAABLgAECn8YAAIlAAgJXRA5GgCnAQAlAAgJXRA5GgCnAQAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCwAAAA==.',
Ko='Korhina:BAABLgAECn89AAIDAAkJcSaEAABlAwADAAkJcSaEAABlAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgQJBwAAAA==.',
Ku='Kuroyukihime:BAABLgAECn8rAAIFAAkJlRwgFwCXAgAFAAkJlRwgFwCXAgAAAA==.Kuwaii:BAABLgAECn8dAAISAAcJuxhzGwCrAQASAAcJuxhzGwCrAQABLgAECggJHgANAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgMJAwAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwcmLQAbAQAIAAkJQwcmLQAbAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgADCgUJCAAAAA==.',
La='Lashela:BAAALgAECgYJEQAAAA==.Laughter:BAAALgAECgYJDwAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgYJDgAAAA==.',
Le='Leansipper:BAABLgAFFH8HAAINAAMJsBMVHADtAAANAAMJsBMVHADtAAAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgQJBAABLgAECggJIwAVALAVAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgAECgYJBgABLgAECgYJBwAGAAAAAA==.Lillianaxe:BAAALgAECgYJDAAAAA==.Lilyvain:BAAALgAECgIJAwAAAA==.Lireal:BAABLgAECn8mAAIKAAkJ9yNyAQB+AwAKAAkJ9yNyAQB+AwAAAA==.Listerine:BAAALgAECgYJBgAAAA==.Litercola:BAAALgAECgYJCAAAAA==.Livnod:BAAALgAECgMJBgAAAA==.',
Lo='Lorine:BAABLgAECn8yAAIBAAkJzhmECAD4AQABAAkJzhmECAD4AQAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgADCgkJEAABLgAECgkJHQAXACQMAA==.Lunara:BAAALgAECgMJBQAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8hAAMYAAgJrQdpbwDzAAAYAAgJcAZpbwDzAAAUAAMJbgabOQBsAAAAAA==.Mageab:BAABLgAFFH8HAAIFAAYJCx3CDADzAQAFAAYJCx3CDADzAQAAAA==.Magis:BAAALgADCgkJHAAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgUJBwAAAA==.Materia:BAAALgAECgcJBwAAAA==.',
Me='Meeralax:BAAALgAECgYJEAAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAABLgAECn8pAAIYAAgJOCAqEgBxAgAYAAgJOCAqEgBxAgAAAA==.Merckz:BAAALgAECgEJAQABLgAECggJKQAYADggAA==.Metalmonkey:BAAALgADCgMJBQAAAA==.',
Mi='Michello:BAABLgAECn8SAAIVAAcJIhzWMgDAAQAVAAcJIhzWMgDAAQAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8bAAIFAAgJ6hogLwAbAgAFAAgJ6hogLwAbAgABLgAECgkJHgACAHwiAA==.Mint:BAABLgAECn8dAAIKAAcJjCP9EQCDAgAKAAcJjCP9EQCDAgAAAA==.Mintberrytea:BAAALgAECgEJAQABLgAECgcJHQAKAIwjAA==.Mintchaitea:BAAALgAECgcJCQABLgAECgcJHQAKAIwjAA==.Misstress:BAABLgAECn8nAAMNAAgJhAuLKAAyAQANAAgJUwuLKAAyAQAMAAEJ/gikRQAnAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgIJAgAAAA==.Moonhunt:BAAALgAECgMJBgAAAA==.Moonly:BAABLgAECn8gAAImAAkJnAv1EwDCAQAmAAkJnAv1EwDCAQAAAA==.Morrag:BAABLgAECn8VAAMXAAcJXwgUiwDoAAAXAAcJ6QcUiwDoAAAWAAEJjAbjJwAvAAAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgcJHgAYAKIVAA==.Musho:BAAALgADCgYJEgAAAA==.',
My='Myn:BAAALgAECgcJEwAAAA==.Myw:BAAALgAECgcJBwABLgAFFAcJHQAcABsXAA==.',
['Mæ']='Mædenless:BAAALgAECgYJCAAAAA==.',
['Mí']='Mísfìt:BAABLgAECn8zAAMcAAkJQRkdFQBPAgAcAAkJQRkdFQBPAgAHAAEJ0wULjwApAAAAAA==.',
Na='Nakaito:BAABLgAECn8UAAIXAAcJlQx4ZwAzAQAXAAcJlQx4ZwAzAQABLgAECgkJJwAZAM0XAA==.Narcoleptic:BAABLgAECn8yAAQRAAkJ7RgXBQCIAgARAAkJ7RgXBQCIAgASAAgJDBOjIQB9AQAjAAQJrgVULwCdAAAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJDQAGAAAAAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJAgAAAA==.Nightmarexx:BAACLgAFFH8UAAIaAAUJZh5YCQByAQAaAAUJZh5YCQByAQAuAAQKf0kAAhoACAl4IUEHAG4CABoACAl4IUEHAG4CAAAA.Nightsawdy:BAABLgAECn8cAAMVAAcJARY5WQA/AQAVAAYJORY5WQA/AQAmAAYJNxErIgA8AQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAABLgAECn8UAAMVAAUJkhy6XQAzAQAVAAUJkhy6XQAzAQAmAAEJ5ROQLABBAAAAAA==.Nikwillig:BAAALgAECgcJCQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgkJEQAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
No='Nocturnum:BAAALgAECgYJCgABLgAFFAQJDwAFAMcYAA==.',
Nt='Ntadadarknes:BAAALgAECgIJAwABLgAECggJIgAJAMwJAA==.',
Op='Opalinnas:BAABLgAECn8gAAMJAAkJcBZlIgDxAQAJAAkJcBZlIgDxAQANAAUJeQgrQwCrAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAECgQJCQAAAA==.',
Pe='Peachtea:BAAALgAECgQJDAAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQfaNwAAAQAHAAgJbQfaNwAAAQAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCQAAAA==.',
Po='Poisonclaw:BAAALgAECgIJAwAAAA==.Poprotonix:BAABLgAECn8VAAICAAYJXwhMsgDPAAACAAYJXwhMsgDPAAAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJBAAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn86AAIlAAkJuiNRAQCYAwAlAAkJuiNRAQCYAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMiAAkJIQlHEADxAAAiAAkJIQlHEADxAAAXAAMJaAPB1QBbAAAAAA==.',
Pu='Pubis:BAAALgAECgYJDQAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdiQQAhAgACAAkJ5RdiQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgMJBgAAAA==.',
Py='Pyre:BAABLgAECn81AAIlAAkJCA76FwC8AQAlAAkJCA76FwC8AQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgkJDgAAAA==.',
Ra='Rabmaxx:BAABLgAECn8XAAIUAAYJ0A3XIwD0AAAUAAYJ0A3XIwD0AAAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgADCgQJBAAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAAALgAFFAEJAQAAAA==.Ravenwynnd:BAABLgAECn8mAAInAAkJuyLtAQDxAgAnAAkJuyLtAQDxAgAAAA==.Raynelock:BAABLgAECn8wAAMiAAkJghCJBgClAQAiAAkJghCJBgClAQAXAAIJtQcZCQFKAAAAAA==.Raynman:BAABLgAECn86AAIcAAkJdRVCGAA1AgAcAAkJdRVCGAA1AgAAAA==.Razgriz:BAAALgAECgEJAQAAAA==.Razix:BAABLgAECn8yAAQSAAkJehTXFgDWAQASAAkJehTXFgDWAQAjAAYJ6wkyEgCfAAARAAMJYwclPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Reija:BAAALgAECgEJAgAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJLQAdAAgWAA==.Revealed:BAAALgADCgEJAQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAABLgAECn8WAAMQAAUJyhVBPAAFAQAQAAUJyhVBPAAFAQAnAAEJJQ1bRQAuAAAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIVAAkJhQ4oVABOAQAVAAkJhQ4oVABOAQAAAA==.Rinas:BAABLgAECn8rAAMUAAgJHSDmBgB3AgAUAAgJHSDmBgB3AgAYAAIJ1A1b0wA1AAAAAA==.Rivendell:BAAALgAECgEJAgAAAA==.Rivenlynn:BAAALgADCgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAACLgAFFH8FAAIhAAIJ7BuQGQCzAAAhAAIJ7BuQGQCzAAAuAAQKfzcAAiEACAk/IAgHACMCACEACAk/IAgHACMCAAAA.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAABLgAECn8UAAMVAAYJfQOWjADAAAAVAAYJfQOWjADAAAAeAAMJpAA3hgA2AAAAAA==.Salios:BAABLgAFFH8NAAIXAAQJNB64KQA+AQAXAAQJNB64KQA+AQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgkJJgAKAPcjAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAQJDQAEAGceAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8oAAMSAAkJKhchFADxAQASAAkJKhchFADxAQARAAEJsgFhTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBgAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgQJBgAAAA==.Servoker:BAACLgAFFH8RAAIRAAYJXxvLCQCgAQARAAYJXxvLCQCgAQAuAAQKfyUAAxIACAnbICEKANQCABIACAnbICEKANQCABEABwkkGrwVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shabzyt:BAAALgADCgQJBAAAAA==.Shaienne:BAAALgAECgMJAwAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAABLgAECn8VAAIcAAUJ0iKdIgDoAQAcAAUJ0iKdIgDoAQAAAA==.Shenuton:BAAALgAECgMJBQAAAA==.Shieldinterd:BAAALgADCgcJCAABLgAECgcJHgAYAKIVAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shockthêràpy:BAACLgAFFH8GAAIcAAIJ8BCsGgCQAAAcAAIJ8BCsGgCQAAAuAAQKfzAABBwACQlbGG0nAPMBABwACQlbGG0nAPMBAAcAAwkWF45LALAAAB0AAQlPCkYrADgAAAAA.Shoes:BAABLgAECn89AAQmAAkJTSXqAABEAwAmAAkJxSPqAABEAwAeAAgJIx/cDQDVAgAVAAgJ9SKvFABlAgAAAA==.Shtdruid:BAAALgAECgUJBQAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.Shöçkér:BAAALgADCgEJAQAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAFFAIJBQAhAOwbAA==.Sibearian:BAABLgAECn8cAAQMAAYJBRxlEAByAQAMAAYJBRxlEAByAQAoAAYJ0ArNGADlAAANAAIJPwSEdQBNAAAAAA==.Simi:BAABLgAECn8jAAIVAAgJsBWeQACMAQAVAAgJsBWeQACMAQAAAA==.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQbpIAA4AQADAAgJIQbpIAA4AQAQAAQJzgKHhwChAAAAAA==.Skôrn:BAABLgAECn8wAAIFAAcJLQ9LdQBRAQAFAAcJLQ9LdQBRAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIaAAgJOhdmGgAvAgAaAAgJOhdmGgAvAgAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgIJAgAAAA==.Smokesçreen:BAABLgAECn83AAMUAAkJfBwdCABaAgAUAAkJfBwdCABaAgAYAAUJugW1oQCHAAAAAA==.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8XAAIRAAgJIQXyFwAIAQARAAgJIQXyFwAIAQAAAA==.Soonerpride:BAABLgAECn8cAAICAAgJAyNAGQBtAgACAAgJAyNAGQBtAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn84AAMTAAkJnyJgAwAAAwATAAkJnyJgAwAAAwAIAAIJmRX+ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAABLgAECn8VAAMaAAgJGg6bGAB+AQAaAAgJGg6bGAB+AQAZAAEJJgRJIgAnAAAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Stinky:BAABLgAECn8XAAIbAAgJjgmeCQA3AQAbAAgJjgmeCQA3AQAAAA==.Stix:BAABLgAECn8jAAMaAAgJmxjrFgCPAQAaAAgJmxjrFgCPAQAbAAQJzxO5DgDAAAAAAA==.Stoya:BAAALgAECgQJBgABLgAECgkJJgAKAPcjAA==.Stuef:BAABLgAECn82AAIHAAkJGiF6BQDPAgAHAAkJGiF6BQDPAgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8gAAMEAAkJNCBBEQClAgAEAAkJNCBBEQClAgAhAAcJ4AkvIgDbAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAABLgAECn8XAAMgAAYJuBw3IgCLAQAgAAYJuBw3IgCLAQAOAAEJ2AF+mQAaAAABLgAECgcJHgAYAKIVAA==.Stäirs:BAABLgAECn85AAIQAAkJVxxnDQBTAgAQAAkJVxxnDQBTAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgkJEQABLgAECgcJFAARAH8GAA==.',
Sy='Sylaria:BAAALgAECgMJBgAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAAALgAECgcJEgAAAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECgYJHgAXABkdAA==.',
['Sï']='Sïn:BAABLgAECn8eAAIXAAYJGR1XSgB/AQAXAAYJGR1XSgB/AQAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIKAAIJriAaFQCYAAAKAAIJriAaFQCYAAAuAAQKfxcAAgoABwk5JAYKANMCAAoABwk5JAYKANMCAAAA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgAECgcJBwABLgAECggJKgAYAMQYAA==.Tankin:BAAALgADCgMJAwAAAA==.Tantric:BAAALgAECgIJAgABLgAECgYJBgAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8RAAIJAAUJnwpBGAA7AQAJAAUJnwpBGAA7AQAuAAQKfx4AAgkABwmzGYEwAOkBAAkABwmzGYEwAOkBAAAA.',
Te='Technique:BAAALgADCgUJBQAAAA==.Teebags:BAAALgADCgEJAQAAAA==.Teknoman:BAACLgAFFH8FAAIQAAIJ+h4jJwCyAAAQAAIJ+h4jJwCyAAAuAAQKfzcAAhAACAkUIB0MAGQCABAACAkUIB0MAGQCAAAA.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAAALgAECgkJCQAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECgYJEwAGAAAAAA==.',
Th='Thaddeus:BAAALgAECgEJAQABLgAFFAQJDQAGAAAAAQ==.Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAABLgAECn8WAAIVAAUJIhhZawARAQAVAAUJIhhZawARAQAAAA==.Tharain:BAAALgADCgkJEQAAAA==.Thebigbeast:BAAALgAECgEJAQABLgAFFAYJEAAXAIcTAA==.Thecurt:BAABLgAECn84AAIOAAkJiiRFAQBAAwAOAAkJiiRFAQBAAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgMJAwAAAA==.Thehuzz:BAAALgAECggJDAAAAA==.Thermidor:BAABLgAECn8gAAImAAkJYBV5CQBLAgAmAAkJYBV5CQBLAgAAAA==.Thorsamie:BAAALgAECgYJBwAAAA==.Thrasios:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgMJBAAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgMJBAAAAA==.',
Tk='Tkdfath:BAAALgAECgYJCgAAAA==.',
To='Torvia:BAAALgAECgMJBgAAAA==.Totemix:BAAALgADCgcJEgAAAA==.Totemsoul:BAAALgAECgEJAQABLgAECgcJCQAGAAAAAA==.',
Tr='Trisinz:BAABLgAECn8eAAINAAgJ/hKSHwBzAQANAAgJ/hKSHwBzAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEgAAAA==.Turk:BAABLgAECn87AAMYAAkJgBYmHQAiAgAYAAkJgBYmHQAiAgAUAAEJCQ/BcwAxAAAAAA==.Turkish:BAABLgAECn83AAMEAAkJhRn+KAAXAgAEAAkJhRn+KAAXAgAkAAEJ7gYCJAAsAAAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yGyBwBWAQADAAQJ3yGyBwBWAQAuAAQKfycAAgMACQnSH7sDABcDAAMACQnSH7sDABcDAAAA.',
Ty='Tychaa:BAAALgADCgkJEQAAAA==.Tylat:BAAALgADCgEJAgAAAA==.Tyranax:BAACLgAFFH8FAAIlAAIJ1wqmKACHAAAlAAIJ1wqmKACHAAAuAAQKfywABCUACAmCHUUOADMCACUACAn7GkUOADMCAAgABgnVH1IcAPoBABMABwkyE5YiAF4BAAAA.Tyyregade:BAAALgADCgkJCgABLgAECgYJEwAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAQAAAA==.',
Ur='Urawizardtui:BAACLgAFFH8MAAIFAAQJNgpqRgAqAQAFAAQJNgpqRgAqAQAuAAQKfzwABAUACQk+H/wUAKUCAAUACQk+H/wUAKUCAAsABQmDCGQOAN0AACkAAQk8EPQMADcAAAAA.',
Us='Us:BAAALgAECggJCQAAAA==.',
Va='Vadose:BAABLgAECn8eAAIXAAcJgQqmgQBXAQAXAAcJgQqmgQBXAQABLgAECggJIwAVALAVAA==.Vales:BAAALgAECgMJAwABLgAECgkJIwAVAP0JAA==.Valsavis:BAAALgAECgYJEwAAAA==.Valytrois:BAAALgAECgcJDQAAAA==.Varinix:BAAALgADCgMJBQAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAABLgAECn8UAAIRAAcJfwYLGQD8AAARAAcJfwYLGQD8AAAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgQJBQAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgAECgYJBgAAAA==.',
Vi='Vitur:BAABLgAECn8+AAIYAAkJ/iDvDQCYAgAYAAkJ/iDvDQCYAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIYAAcJGQqtcADwAAAYAAcJGQqtcADwAAAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAABLgAECn8WAAMXAAUJGA6OlwDQAAAXAAQJoAyOlwDQAAAWAAIJuhQAJAA9AAAAAA==.Volt:BAABLgAECn8tAAIdAAkJCBa7BgALAgAdAAkJCBa7BgALAgAAAA==.Volumoso:BAAALgAECgEJAQAAAA==.Volwryn:BAAALgAECgQJBQABLgAECgYJBgAGAAAAAA==.',
Vy='Vynarian:BAABLgAECn8WAAIFAAUJKBRyoAACAQAFAAUJKBRyoAACAQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECgYJHAAPANIcAA==.',
Wa='Warbeard:BAABLgAECn8oAAIQAAkJ8gszHgCwAQAQAAkJ8gszHgCwAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckbums:BAAALgAECgQJBQAAAA==.Wreckd:BAAALgAECgkJEwAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgkJDgAAAA==.',
Xi='Xitãozinho:BAAALgAECgUJBwAAAA==.',
Xo='Xolair:BAAALgAECgYJDgAAAA==.',
Ya='Yaalia:BAAALgAECgUJDAAAAA==.Yaan:BAABLgAECn8aAAIHAAcJkAoPQADcAAAHAAcJkAoPQADcAAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn89AAQnAAkJOB0gBACTAgAnAAkJOB0gBACTAgAQAAYJGA5fWQBIAQADAAIJKA3xNgBVAAAAAA==.Zandibar:BAABLgAECn8WAAIQAAUJ4hdBOwAJAQAQAAUJ4hdBOwAJAQAAAA==.Zaptoasted:BAAALgAECgEJAQAAAA==.Zaroff:BAAALgAECgQJBAAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgADCgkJEQABLgAECgcJFAAXABAGAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zinder:BAABLgAECn8cAAIFAAcJFxATZwBwAQAFAAcJFxATZwBwAQAAAA==.',
Zu='Zuggie:BAABLgAECn8UAAIXAAcJEAackADdAAAXAAcJEAackADdAAAAAA==.Zugtail:BAAALgAECgEJAQABLgAECgcJFAAXABAGAA==.Zurtrinik:BAACLgAFFH8WAAIDAAYJHyLlAwCqAQADAAYJHyLlAwCqAQAuAAQKfyUAAgMACAmZJDwCAE0DAAMACAmZJDwCAE0DAAAA.',
Zz='Zzonked:BAABLgAECn8pAAMEAAkJCghNZwBQAQAEAAkJzgZNZwBQAQAhAAIJ/gtGPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8gAAIYAAgJ3xcZMgC1AQAYAAgJ3xcZMgC1AQAAAA==.',
['Är']='Äréa:BAAALgADCgkJCQAAAA==.',
['Äs']='Äshnärd:BAABLgAECn8vAAIcAAgJTiUoBwD1AgAcAAgJTiUoBwD1AgAAAA==.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAABLgAECn8UAAIHAAcJ1RcBJABzAQAHAAcJ1RcBJABzAQAAAA==.',
['Ðr']='Ðruidess:BAAALgAECgMJAwAAAA==.',
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
