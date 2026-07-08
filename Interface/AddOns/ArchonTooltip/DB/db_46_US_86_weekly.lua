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

local lookup = {'Warrior-Fury','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Mage-Frost','Paladin-Retribution','Hunter-Survival','Warrior-Protection','Priest-Discipline','Unknown-Unknown','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Priest-Shadow','Druid-Guardian','Monk-Brewmaster','Priest-Holy','Monk-Windwalker','Warlock-Destruction','DeathKnight-Frost','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acharon:BAABLgAECn85AAIBAAkJGRlIGQAkAgABAAkJGRlIGQAkAgAAAA==.',
Ad='Adrastus:BAAALgAFFAIJAwAAAA==.',
Ae='Aesa:BAAALgAECgQJBAABLgAFFAQJCgACAMMKAA==.Aeslin:BAABLgAECn8XAAIDAAYJRSXEGwBuAgADAAYJRSXEGwBuAgAAAA==.',
Af='Af:BAAALgAECgUJBQABLgAFFAgJHAAEAIIbAA==.',
Ag='Aggrofurry:BAAALgAECgEJAQAAAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAABLgAFFH8KAAICAAQJwwqqKgDUAAACAAQJwwqqKgDUAAAAAA==.Ainslie:BAABLgAECn8cAAIFAAkJUxnOAgDGAQAFAAkJUxnOAgDGAQAAAA==.',
Al='Alarashinu:BAABLgAECn8hAAIGAAgJAwYCxAADAQAGAAgJAwYCxAADAQAAAA==.Alataris:BAAALgADCgUJCgABLgAECgkJOwAHAJ4YAA==.Alawae:BAABLgAECn8zAAIIAAkJiSFwBADnAgAIAAkJiSFwBADnAgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8WAAIJAAgJhxajEwDRAQAJAAgJhxajEwDRAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Andrick:BAAALgAECgUJBwAAAA==.Angela:BAAALgADCgcJEAABLgAECgkJLQAKALsWAA==.Anosvoldgoad:BAAALgAECgIJAQAAAA==.',
Ap='Apaka:BAAALgADCgMJBAABLgADCgQJBAALAAAAAA==.Apøllo:BAAALgAECgQJBAAAAA==.',
Ar='Araedia:BAAALgAECggJEwABLgAECgkJMQAFAJAYAA==.Arahant:BAACLgAFFH8WAAIMAAYJ8BTzHACKAQAMAAYJ8BTzHACKAQAuAAQKfzIAAgwACQkJHgENAIMCAAwACQkJHgENAIMCAAAA.Arazat:BAAALgADCgIJAgAAAA==.Aretas:BAABLgAECn89AAMNAAkJNyLtBADfAgANAAkJNyLtBADfAgAOAAEJthanZAE/AAAAAA==.Arkøn:BAAALgADCgIJAgAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arssi:BAAALgAECgMJAwAAAA==.',
As='Ashuffle:BAAALgAECgQJCwAAAA==.Asifa:BAABLgAECn8tAAIGAAkJrRlyQwARAgAGAAkJrRlyQwARAgAAAA==.Astinds:BAAALgAECgYJCQABLgAECggJEgALAAAAAA==.',
At='Atherion:BAACLgAFFH8FAAIGAAIJSwS8rgB5AAAGAAIJSwS8rgB5AAAuAAQKf1AAAgYACAmaFxAGAKkBAAYACAmaFxAGAKkBAAAA.Attackroot:BAAALgADCgkJCQABLgAECggJGQANAKwZAA==.Attackzilla:BAAALgAECgYJBwABLgAECggJGQANAKwZAA==.',
Au='Aurakk:BAAALgADCgcJHQABLgAECgkJNAAHAP8gAA==.Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJBQABLgAECgcJEQALAAAAAA==.Aveticus:BAAALgADCgEJAQAAAA==.Avranarada:BAABLgAECn8xAAMFAAkJkBgXBABnAQAFAAkJkBgXBABnAQAPAAYJMRBIPgAWAQAAAA==.',
Aw='Aw:BAAALgADCgUJBgABLgAFFAgJHAAEAIIbAA==.',
Az='Azkara:BAAALgAFFAEJAgAAAA==.Azung:BAABLgAECn9IAAIHAAkJSCHeDgDvAgAHAAkJSCHeDgDvAgAAAA==.Azurae:BAAALgADCgkJCQAAAA==.Azureflame:BAAALgADCgYJCQABLgADCggJGAALAAAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8cAAIQAAYJaBs9HACUAQAQAAYJaBs9HACUAQAuAAQKfzQAAhAACQnjIwwIABsDABAACQnjIwwIABsDAAAA.Badazzknight:BAAALgAECgQJBAAAAA==.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMRAAkJEhEKDACcAQARAAkJEhEKDACcAQASAAEJXwFrNAEUAAAAAA==.Baka:BAABLgAECn84AAMCAAkJACW+AQCbAwACAAkJACW+AQCbAwAHAAYJNBChkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8bAAIJAAkJGhoJDQAZAgAJAAkJGhoJDQAZAgAAAA==.Bandruì:BAAALgAECgMJBgAAAA==.Bankpoo:BAACLgAFFH8RAAIOAAQJ4BjCaQAmAQAOAAQJ4BjCaQAmAQAuAAQKfycAAw4ACAm2H3MwAD0CAA4ABwmcI3MwAD0CAA0AAQlXCLpjACIAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECggJEQAAAA==.Barrelrollin:BAABLgAECn8VAAMDAAkJBBOeXQBEAQADAAYJIhGeXQBEAQATAAcJRwrgVQDjAAAAAA==.Batrito:BAABLgAECn8tAAMKAAkJuxZ4FQAvAgAKAAkJuxZ4FQAvAgAUAAcJuRTrLgBlAQAAAA==.Battosai:BAAALgAECgEJAQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAABLgAECn8pAAIQAAcJcAx+egBLAQAQAAcJcAx+egBLAQAAAA==.Bearlylegál:BAABLgAFFH8FAAIVAAQJDhnYDQAfAQAVAAQJDhnYDQAfAQAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8tAAMCAAkJLR9iBQA8AwACAAkJLR9iBQA8AwAHAAYJGAj56ADTAAAAAA==.Bethlahammer:BAAALgAECgQJCAABLgAECggJFwATAOIeAA==.',
Bi='Bigboom:BAAALgAECgIJAwAAAA==.Billcosbrew:BAACLgAFFH8FAAIWAAMJnB/+KQABAQAWAAMJnB/+KQABAQAuAAQKfyMAAhYACAkHJhYEAEsDABYACAkHJhYEAEsDAAEuAAUUBAkFABUADhkA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgUJDwAAAA==.Blamegame:BAAALgADCgkJCQAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJLAADAJsRAA==.Blizzcon:BAACLgAFFH8HAAIKAAMJ/Ay+GQB4AAAKAAMJ/Ay+GQB4AAAuAAQKf0QABAoACQkiGAwRAGICAAoACQnhFwwRAGICABQABAkRCFdbAKgAABcAAglkCg1lAE0AAAAA.Blushies:BAAALgAECgUJBQABLgAECgkJQQAYAEAjAA==.',
Bo='Boagrius:BAAALgAECgYJBgAAAA==.Boone:BAAALgAECgEJAQAAAA==.Borrgar:BAABLgAECn80AAIHAAkJ/yB8IQCBAgAHAAkJ/yB8IQCBAgAAAA==.',
Br='Brackle:BAABLgAECn89AAIQAAkJ4yH1EQDCAgAQAAkJ4yH1EQDCAgAAAA==.Bracori:BAACLgAFFH8WAAIMAAYJZhS4HQCDAQAMAAYJZhS4HQCDAQAuAAQKfywAAwwACQmnEA8oAHQBAAwACQmnEA8oAHQBABgABwnPE4c2ACgBAAAA.Brandywynne:BAABLgAECn8pAAIQAAkJvg0lPAC+AQAQAAkJvg0lPAC+AQAAAA==.Brick:BAABLgAECn86AAIEAAkJ6COXAwAOAwAEAAkJ6COXAwAOAwAAAA==.Briere:BAAALgAECgEJAgAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAACLgAFFH8SAAMRAAMJaxKqCQDgAAARAAMJaxKqCQDgAAAZAAEJgReAJQBKAAAuAAQKfzwAAxkACQl+Ha8HANcBABEACAk9HmsHAPsBABkACAnQGa8HANcBAAAA.Bronny:BAAALgAECgIJAgAAAA==.Brownpepperz:BAAALgADCgcJCAAAAA==.Brunspirit:BAAALgAECgYJCwAAAA==.Bruticus:BAAALgAECgYJBgAAAA==.',
Bu='Bubblebull:BAAALgAECgIJAwAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAFFAIJBAAAAA==.Bullrush:BAAALgAECgUJCQAAAA==.Burnii:BAAALgAECgkJEAABLgAECgkJRwAOAAUmAA==.Bustyheals:BAAALgAECggJCQABLgAFFAYJGgANAAwYAA==.Butterbllz:BAACLgAFFH8YAAIHAAUJxhs8EwAbAQAHAAUJxhs8EwAbAQAuAAQKfyUAAgcACQk9IfMMAP0CAAcACQk9IfMMAP0CAAAA.Buuberymufin:BAAALgAECgIJAgAAAA==.',
['Bô']='Bôreas:BAAALgAECgEJAgABLgAECgUJCgALAAAAAA==.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn87AAIHAAkJnhg0QAAGAgAHAAkJnhg0QAAGAgAAAA==.Camany:BAABLgAECn8jAAIQAAkJuRZLLQAnAgAQAAkJuRZLLQAnAgAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAYJEQAUACIMAA==.Caralath:BAAALgAECgQJBwABLgAECgYJDwALAAAAAA==.Caramaulize:BAAALgAECgQJBAAAAA==.Caretakerz:BAABLgAECn9CAAIVAAkJCyASBADbAgAVAAkJCyASBADbAgAAAA==.Cartus:BAABLgAECn8pAAMTAAgJLAykRAAhAQATAAgJLAykRAAhAQADAAUJRQV5owCHAAAAAA==.',
Ce='Cedre:BAAALgADCgcJFwAAAA==.Celidoria:BAABLgAECn8mAAIHAAgJZiGBKABhAgAHAAgJZiGBKABhAgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Charene:BAAALgAECgEJAgAAAA==.Cheesepuff:BAABLgAECn8ZAAISAAYJkwkHvwDNAAASAAYJkwkHvwDNAAAAAA==.Chemoshh:BAAALgADCgYJDAABLgAECgkJNAAHAP8gAA==.Chikara:BAABLgAFFH8IAAMMAAMJjxaRFwDAAAAMAAMJjxaRFwDAAAAYAAIJWharLwCHAAAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.Chunki:BAAALgAECgEJAQAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAYJFwAGALUWAA==.Cinnibar:BAAALgADCgYJCgAAAA==.Cirï:BAABLgAECn8UAAIGAAcJIAeuywD4AAAGAAcJIAeuywD4AAAAAA==.Cisbick:BAABLgAECn8kAAISAAcJYREOlwAOAQASAAcJYREOlwAOAQAAAA==.',
Cl='Clamshell:BAABLgAECn9HAAMOAAkJBSYcAwBuAwAOAAkJBSYcAwBuAwAaAAEJAABVRwAAAAAAAA==.Clayier:BAABLgAECn8ZAAIbAAYJgRSJEwAnAQAbAAYJgRSJEwAnAQAAAA==.',
Cn='Cntendr:BAAALgAECgQJCQAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8xAAMYAAkJYyAaBgDrAgAYAAkJYyAaBgDrAgAMAAUJCAx+eACzAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgAECgYJCgABLgAECgkJLwAHAOAiAA==.Copenzen:BAAALgAECgQJBAAAAA==.Corbanite:BAAALgAECgQJCQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDwAAAA==.Covertyqt:BAABLgAECn9UAAIGAAkJlSTGBwA/AwAGAAkJlSTGBwA/AwAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn9QAAIOAAkJLiAXEgDdAgAOAAkJLiAXEgDdAgAAAA==.',
Cr='Cromie:BAAALgADCgkJCQAAAA==.Crunk:BAAALgAECgQJCAAAAA==.Cryosphere:BAAALgAECgMJAwABLgAECggJFwATAOIeAA==.Cryptis:BAAALgAECgkJCAAAAA==.',
Cs='Cshunter:BAAALgADCgQJBAAAAA==.',
Cu='Cupcàké:BAAALgAECgIJAgAAAA==.',
['Cõ']='Cõrpses:BAEALgAECgUJBQABLgAECgkJFQAcAHwhAA==.',
Da='Daboof:BAAALgAECgQJBwAAAA==.Dabzz:BAAALgADCgMJAwAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgAECgMJBgAAAA==.Daggere:BAAALgAECgYJCwAAAA==.Damaged:BAAALgAECgQJBAABLgAECgkJOwAHAJ4YAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgALAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAABLgAECn8zAAMaAAYJ2g1JGwD1AAAaAAYJxA1JGwD1AAAOAAYJzAgU0wDkAAAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgAECgYJCwAAAA==.Darckinz:BAABLgAECn8pAAMUAAgJtA2jMwBLAQAUAAgJtA2jMwBLAQAKAAEJ7waGhgAlAAAAAA==.Darkenmicky:BAABLgAECn8iAAIWAAgJHAxULgBMAQAWAAgJHAxULgBMAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8XAAIHAAYJkwrBNwA9AQAHAAYJkwrBNwA9AQAuAAQKfywAAgcACQlqH2oYANYCAAcACQlqH2oYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAFFAEJAQABLgAFFAIJAgALAAAAAA==.Dayloc:BAABLgAECn9VAAISAAkJARnpBQBZAQASAAkJARnpBQBZAQAAAA==.',
De='Deadwaifu:BAAALgADCggJCAAAAA==.Deataria:BAAALgAECgYJCwAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Deathwish:BAAALgAECgQJBQAAAA==.Deawin:BAAALgAECgYJDAABLgAECgkJFQADAAQTAA==.Delryth:BAAALgAECgYJCgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demonatrix:BAAALgADCgEJAQAAAA==.Demonikk:BAAALgAECgYJBgAAAA==.Demontyk:BAAALgAECgIJAgAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Deshaller:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.Detox:BAAALgADCgQJBAAAAA==.Devourmax:BAABLgAFFH8JAAIBAAkJIQKlFwCjAAABAAkJIQKlFwCjAAAAAA==.',
Di='Diablõ:BAEBLgAECn88AAIdAAkJLSIEBACMAgAdAAkJLSIEBACMAgABLgAECgkJFQAcAHwhAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAIOAAkJfhA4VADHAQAOAAkJfhA4VADHAQAAAA==.Divinetism:BAAALgAECgcJDgAAAA==.',
Dl='Dl:BAABLgAECn87AAIUAAkJgx/9CgCgAgAUAAkJgx/9CgCgAgAAAA==.',
Do='Doomsdayy:BAAALgAECgEJAQAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQeAAgJGxWZFACfAQAfAAgJmBHmHwDCAQAeAAYJZBiZFACfAQAgAAEJwwdpSgAtAAAAAA==.Dragkohn:BAABLgAECn8bAAIgAAkJ7SC/AgAzAwAgAAkJ7SC/AgAzAwABLgAECgkJKwACACcmAA==.Dragonaged:BAAALgAECgEJAQAAAA==.Drakkarr:BAAALgAECgEJAQAAAA==.Drannek:BAAALgAECgEJAwAAAA==.Drimbirt:BAAALgAECgUJCwAAAA==.Drinkmormilk:BAABLgAECn8oAAIHAAkJWRn6OgAXAgAHAAkJWRn6OgAXAgAAAA==.Drogman:BAAALgAECgUJCQAAAA==.Droowin:BAAALgAECgQJCAABLgAECgkJFQADAAQTAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECggJEwAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Ea='Eastman:BAAALgAECgIJAgAAAA==.',
Eb='Ebullition:BAABLgAECn8dAAIQAAkJFxduLwAfAgAQAAkJFxduLwAfAgAAAA==.',
Ec='Ecletic:BAAALgAECgEJAgAAAA==.Ectrix:BAAALgAECgEJAQAAAA==.',
Ed='Edensfury:BAABLgAECn8XAAITAAgJ4h6vEABtAgATAAgJ4h6vEABtAgAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAABLgAECn8dAAIQAAkJ4BW7OgD0AQAQAAkJ4BW7OgD0AQAAAA==.',
Ek='Ekthelion:BAABLgAECn8oAAIhAAcJshluEgCgAQAhAAcJshluEgCgAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIZAAYJaiA1CgAbAgAZAAYJaiA1CgAbAgAAAA==.Eleyert:BAABLgAECn9RAAITAAkJiybcAAB9AwATAAkJiybcAAB9AwAAAA==.Elistann:BAAALgAECgUJBQABLgAECgkJNAAHAP8gAA==.Elwe:BAABLgAECn8ZAAIXAAkJwiCuBwD0AgAXAAkJwiCuBwD0AgAAAA==.',
Em='Emiri:BAAALgAECgYJCwAAAA==.Emmaga:BAABLgAECn82AAIGAAkJxxqWAwAiAgAGAAkJxxqWAwAiAgAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn9DAAIQAAkJcSAiFgCjAgAQAAkJcSAiFgCjAgAAAA==.Enseth:BAABLgAECn9FAAQfAAkJPxYHFQAzAgAfAAkJPxYHFQAzAgAeAAQJNQfjLQCsAAAgAAMJIAqGOgA5AAAAAA==.',
Ep='Ephriam:BAAALgAECgUJBQABLgAFFAYJGQACAAkXAA==.',
Er='Erakha:BAAALgAECgEJAgAAAA==.Erotikzombie:BAABLgAECn8jAAIOAAkJhyEgDQAEAwAOAAkJhyEgDQAEAwAAAA==.Errilyn:BAAALgADCgYJBgAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAACLgAFFH8FAAMOAAMJZQnIQACqAAAOAAMJZQnIQACqAAANAAEJjwH5QQArAAAuAAQKfyQAAw4ACAmUGGQ6ABcCAA4ACAmUGGQ6ABcCAA0AAwneCdVDAH8AAAEuAAUUAwkHAAoA/AwA.',
Ex='Exene:BAABLgAECn8UAAMiAAkJ1wu2eAAvAQAiAAkJNAe2eAAvAQAdAAQJthFAGwC3AAAAAA==.',
Ez='Ezki:BAAALgAECgcJDgABLgAECgkJNAAHAP8gAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAACLgAFFH8GAAIEAAIJsRJ2MACkAAAEAAIJsRJ2MACkAAAuAAQKf1kAAwQACQlHIsIDAAgDAAQACQlHIsIDAAgDACMABwlwEGYNAFMBAAAA.Fangrell:BAAALgAECgcJCAABLgAFFAMJCwAQAMIKAA==.Faror:BAAALgAECgYJCAAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAgJKwAEAPoZAA==.Feetworship:BAAALgAECgYJBgABLgAFFAgJKwAEAPoZAA==.Felcon:BAAALgAECgEJBQAAAA==.Felglaives:BAAALgAECgcJDgABLgAECggJGQANAKwZAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgkJGgABLgAECgkJNAAHAP8gAA==.Fet:BAACLgAFFH8rAAMEAAgJ+hkPAgDlAQAEAAgJ+hkPAgDlAQAkAAQJZw5tBwARAQAuAAQKfzUAAwQACQmkJNwIAAMDAAQACQmkJNwIAAMDACQABgmjIVgIAK0BAAAA.Feyu:BAEALgAECgYJCQABLgAFFAMJBgADAKcSAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAFFAIJAgALAAAAAA==.Fistsoiaaryn:BAABLgAECn8XAAIWAAYJuBGOOAAaAQAWAAYJuBGOOAAaAQAAAA==.',
Fl='Flatline:BAABLgAECn8hAAIKAAkJdhjIDwB0AgAKAAkJdhjIDwB0AgAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flinnt:BAAALgAECgQJBQABLgAECgkJNAAHAP8gAA==.Flöti:BAECLgAFFH8GAAIDAAMJpxIgUgCvAAADAAMJpxIgUgCvAAAuAAQKfxgAAgMACAk+GSEdADECAAMACAk+GSEdADECAAAA.',
Fo='Four:BAABLgAECn8pAAIHAAkJJxUOUQDVAQAHAAkJJxUOUQDVAQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAABLgAECn8UAAIGAAcJ9R7AUwDhAQAGAAcJ9R7AUwDhAQAAAA==.Frysky:BAABLgAECn8UAAIVAAYJ+Q2AGQDkAAAVAAYJ+Q2AGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwALAAAAAA==.Futz:BAACLgAFFH8GAAICAAIJOxwENQCbAAACAAIJOxwENQCbAAAuAAQKf2QABAIACQkYJIYBAKYDAAIACQkYJIYBAKYDAAcAAwlDB+oiAG0AACEAAglsBKMNADIAAAAA.Fuzzymage:BAAALgAECgEJBwAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAACLgAFFH8NAAIQAAQJTRWxPQAxAQAQAAQJTRWxPQAxAQAuAAQKfyMAAxAACQm4G/AqADICABAACQm4G/AqADICABsABgmZD1RDAEoBAAAA.Gangrell:BAAALgAECgEJAgABLgAFFAMJCwAQAMIKAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Gi='Gilmur:BAAALgAECgUJBwAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.Gnopoleon:BAAALgAECgEJAgAAAA==.',
Go='Goobermanic:BAAALgAECgUJCQAAAA==.Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgAECgEJAgAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gp='Gpa:BAAALgADCgcJCQAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMkAAkJXxusAQCvAgAkAAkJXxusAQCvAgAjAAIJUxQ4HAB8AAAAAA==.Gravewin:BAAALgAECgUJBwABLgAECgkJFQADAAQTAA==.Grendelheim:BAAALgAECgQJBwAAAA==.Grogar:BAAALgADCgMJAwAAAA==.Grumpycat:BAAALgAECgEJAgAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.Gutso:BAAALgADCgMJAwAAAA==.',
Gw='Gwynath:BAABLgAECn8kAAQXAAkJqiMPAwBlAwAXAAkJqiMPAwBlAwAKAAYJtxo2IQCKAQAUAAEJShQHgQA7AAAAAA==.',
Ha='Hadez:BAAALgAECgEJAQAAAA==.Hagrok:BAABLgAECn8bAAIbAAgJzggOGADyAAAbAAgJzggOGADyAAAAAA==.Haldael:BAAALgAECgUJBQAAAA==.Haloternal:BAAALgADCgEJAQAAAA==.Hammerfists:BAAALgAECgQJCQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgQJBQABLgAECggJFgAJAIcWAA==.Hantak:BAAALgAECgUJDAAAAA==.Harborseal:BAAALgAECgEJAQABLgAECgkJQQAYAEAjAA==.Hathaendron:BAAALgAECgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.Hawkjewa:BAAALgAECgEJAgAAAA==.',
He='Headdinkd:BAAALgADCgUJBQABLgAFFAIJAgALAAAAAA==.Hemorrhagic:BAAALgADCgIJAgAAAA==.Heph:BAAALgADCgcJBwABLgADCggJGAALAAAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIJAAgJjBMLIQAoAQAJAAgJjBMLIQAoAQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAIWAAgJ2RU+KQBqAQAWAAgJ2RU+KQBqAQABLgAECgkJCQALAAAAAA==.Holyyballs:BAABLgAECn8hAAICAAkJHR/dDgCoAgACAAkJHR/dDgCoAgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgkJBAABLgAFFAMJCwAQAMIKAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Hunzah:BAAALgADCgQJBAAAAA==.Huskerfister:BAABLgAECn84AAIYAAkJtSLPBwDLAgAYAAkJtSLPBwDLAgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.Huyao:BAAALgAECgMJAwAAAA==.',
['Hì']='Hìroko:BAABLgAECn8vAAISAAkJpgb6EACYAAASAAkJpgb6EACYAAAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.Ichigò:BAAALgAECgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQALAAAAAA==.',
Im='Im:BAAALgAFFAEJAQABLgAFFAgJHAAEAIIbAA==.Imaleaf:BAAALgAECgQJBAAAAA==.Imananji:BAAALgAECgMJBAABLgAFFAYJGAAVAOANAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8fAAIiAAkJxx1kJgAzAgAiAAkJxx1kJgAzAgAAAA==.Imperius:BAAALgAECgIJAgABLgAECgYJFwADAEUlAA==.',
In='Infernodruid:BAAALgAECgMJBQABLgAECgUJBwALAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAABLgAECn8mAAIGAAgJTA+EegCDAQAGAAgJTA+EegCDAQAAAA==.Invictus:BAAALgAECgcJCAAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAACLgAFFH8GAAIQAAMJtQ5hIgDlAAAQAAMJtQ5hIgDlAAAuAAQKfysAAhAACQk2F901AAYCABAACQk2F901AAYCAAAA.',
Ir='Iroh:BAABLgAECn8YAAIYAAkJwR6mDAB6AgAYAAkJwR6mDAB6AgAAAA==.Irondali:BAAALgAECgMJCAAAAA==.',
Is='Ismokeprot:BAAALgAECgUJDQAAAA==.',
Iy='Iyosen:BAAALgAECgcJBwAAAA==.',
Ja='Jainastraza:BAAALgAECgIJAgABLgAECgkJRwAOAAUmAA==.Jakub:BAAALgAECgYJCQAAAA==.Jarchoi:BAAALgADCgUJBQAAAA==.Jarinduva:BAAALgADCggJIAAAAA==.Jawnson:BAABLgAECn9EAAMEAAkJ9hraDABZAgAEAAkJ9hraDABZAgAjAAIJ8RK8GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jekolyn:BAAALgAECgQJBgAAAA==.Jenefer:BAACLgAFFH8aAAMNAAYJDBhGFQBDAQANAAYJDBhGFQBDAQAOAAEJBRzWZABVAAAuAAQKfzEAAg0ACQnoIbQIAIgCAA0ACQnoIbQIAIgCAAAA.Jerzak:BAAALgAECgEJAQAAAA==.',
Ji='Jimjimmy:BAAALgAECgUJBwABLgAECggJFwATAOIeAA==.',
Jo='Joemomo:BAABLgAECn8aAAMBAAgJ1A/KNwBoAQABAAgJ1A/KNwBoAQAlAAEJ7QEBjgAMAAAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAALAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.Joulecrafter:BAAALgAECggJCQABLgAECgkJOwAHANcVAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kachi:BAAALgADCgEJAQAAAA==.Kailback:BAABLgAECn8cAAMOAAkJpxltRgDvAQAOAAgJnBptRgDvAQAaAAYJVBdnDACxAQAAAA==.Kait:BAABLgAECn9BAAMDAAkJWh30GgBzAgADAAkJWh30GgBzAgAmAAYJpRMqHQAUAQAAAA==.Kakarotto:BAAALgAECgcJEAABLgAECgkJGwARAE8UAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgAECgUJBQAAAA==.Kalcifur:BAACLgAFFH8ZAAICAAYJCRewEwCQAQACAAYJCRewEwCQAQAuAAQKfy0AAgIACQk9F+MfAAQCAAIACQk9F+MfAAQCAAAA.Karper:BAAALgAECgUJCQAAAA==.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgAECgMJAwAAAA==.Kassanovva:BAAALgAECgYJBwABLgAFFAYJGgANAAwYAA==.Kasstigate:BAABLgAECn8XAAIBAAcJLBoAKwCqAQABAAcJLBoAKwCqAQABLgAFFAYJGgANAAwYAA==.Kastiel:BAAALgAECgcJEwABLgAECgkJGwAJABoaAA==.Kathtel:BAABLgAECn8YAAIGAAgJJAtWmQBGAQAGAAgJJAtWmQBGAQAAAA==.Katstrider:BAABLgAECn9NAAIQAAkJLxr1BQC2AQAQAAkJLxr1BQC2AQAAAA==.Kattarea:BAAALgAECgYJDwABLgAECgkJTQAQAC8aAA==.Kavica:BAAALgAECgYJDwABLgAFFAIJCwAFAP8cAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8yAAIJAAkJ5x16CAByAgAJAAkJ5x16CAByAgAAAA==.Kelsier:BAAALgADCgYJBgAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8TAAIOAAYJtBhdOQCJAQAOAAYJtBhdOQCJAQAuAAQKfyoAAg4ACQkIJY8LABEDAA4ACQkIJY8LABEDAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgUJCwAAAA==.',
Ki='Kirigiri:BAACLgAFFH8IAAIFAAMJQBGCEQCsAAAFAAMJQBGCEQCsAAAuAAQKfx8AAwUABwnXDkVnAP4AAAUABwnXDkVnAP4AABUAAQkAAEA0ACUAAAEuAAUUBgkZAAIACRcA.Kirøs:BAAALgAECgUJBgAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiterisa:BAAALgAECgUJCQABLgAECgkJQAAXAOcNAA==.Kiwi:BAAALgAECgMJBAABLgAECgUJBwALAAAAAA==.',
Kk='Kkazz:BAAALgAECgQJBAABLgAECgkJNAAHAP8gAA==.',
Kn='Knom:BAAALgAECgcJEQAAAA==.',
Ko='Kohn:BAABLgAECn8rAAICAAkJJyaaAADOAwACAAkJJyaaAADOAwAAAA==.Kohnn:BAAALgAECgQJBAABLgAECgkJKwACACcmAA==.Kona:BAEBLgAECn8VAAIcAAkJfCEpAgAOAwAcAAkJfCEpAgAOAwAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJJgAHAOseAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8RAAIcAAUJGBqiBwAvAQAcAAUJGBqiBwAvAQAuAAQKfyEAAhwACQlTIusEAMYCABwACQlTIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAABLgAECn8mAAIUAAgJBwO9DQBxAAAUAAgJBwO9DQBxAAAAAA==.Lateo:BAABLgAECn9AAAIEAAkJ6hOrEgAQAgAEAAkJ6hOrEgAQAgAAAA==.Lawz:BAABLgAECn8tAAQRAAkJnAh4EgBBAQARAAgJ+Ad4EgBBAQAZAAcJeAZYHQC9AAASAAcJuAMj4gCXAAAAAA==.',
Le='Leafz:BAACLgAFFH8GAAIFAAMJKBJbPQC6AAAFAAMJKBJbPQC6AAAuAAQKfx8AAwUACAmRFcQvAOQBAAUACAmRFcQvAOQBAA8AAQmfDUSPADAAAAAA.Leaonissa:BAAALgAECgMJBAAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgQJBwAAAA==.Lemonruss:BAACLgAFFH8YAAIHAAYJ9Q8sSwAXAQAHAAYJ9Q8sSwAXAQAuAAQKfyEAAgcACQkWGGksAHICAAcACQkWGGksAHICAAAA.Leshafrierne:BAAALgAECgUJCQABLgAECgUJCwALAAAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8hAAMZAAcJdgWPIQCiAAAZAAcJdgWPIQCiAAASAAUJhAPQ7gCDAAAAAA==.',
Li='Lightninghah:BAAALgAECgEJAQABLgAECgcJEwALAAAAAA==.Lilgideon:BAAALgADCgUJBQAAAA==.Lillika:BAAALgAECgUJCQAAAA==.Lilturtz:BAAALgAECgIJAgABLgAECgkJQQAYAEAjAA==.Linnea:BAABLgAECn8aAAMHAAYJvgsqGQCqAAAhAAYJIAreBQCrAAAHAAUJpAoqGQCqAAAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Lockheed:BAAALgADCgMJAwABLgAECgkJLwASAKYGAA==.Longhorn:BAABLgAECn8/AAMHAAkJiBb5QQAAAgAHAAkJSRX5QQAAAgAhAAYJkgz9KADQAAAAAA==.Loni:BAAALgAECgcJDwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAALAAAAAA==.Lortpegsalot:BAABLgAECn8mAAIHAAkJ6x5eIACqAgAHAAkJ6x5eIACqAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAABLgAECn8WAAIDAAcJogbfhADUAAADAAcJogbfhADUAAAAAA==.',
Lu='Lucena:BAABLgAECn8/AAIXAAkJjCMZAQBpAgAXAAkJjCMZAQBpAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgcJDwALAAAAAA==.',
Ly='Lyralana:BAABLgAECn8nAAMMAAgJVx95AQBmAgAMAAgJVx95AQBmAgAYAAEJEglOFwArAAAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Maberu:BAABLgAFFH8KAAIMAAQJwApiHQCWAAAMAAQJwApiHQCWAAABLgAFFAYJGQACAAkXAA==.Madamkluck:BAABLgAECn8pAAIFAAgJcx1hGQB7AgAFAAgJcx1hGQB7AgAAAA==.Magicienne:BAAALgAECgEJAQAAAA==.Maglubiyet:BAABLgAECn9BAAImAAgJoBsWAwAXAQAmAAgJoBsWAwAXAQAAAA==.Magoz:BAABLgAECn8UAAIOAAYJFQ+PEADXAAAOAAYJFQ+PEADXAAAAAA==.Malar:BAAALgADCgUJBQAAAA==.Maleficio:BAAALgAECgYJBgAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Mareshka:BAAALgADCgUJBQAAAA==.Markyb:BAABLgAECn9IAAIHAAkJphrHJgBpAgAHAAkJphrHJgBpAgAAAA==.Masamura:BAACLgAFFH8jAAIGAAgJThj9NACVAQAGAAgJThj9NACVAQAuAAQKf0MAAgYACQlhIkkTAOYCAAYACQlhIkkTAOYCAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFgAJAIcWAA==.Maureanna:BAABLgAECn9DAAIFAAkJJxuKEgC5AgAFAAkJJxuKEgC5AgABLgAECggJJwAMAFcfAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Mc='Mcgunner:BAAALgAECgkJAQAAAA==.',
Me='Mechahuntard:BAAALgADCgIJAgAAAA==.Medaní:BAEALgAECgkJCQABLgAFFAMJDgAgAHsMAA==.Medari:BAECLgAFFH8OAAIgAAMJewwnIgCSAAAgAAMJewwnIgCSAAAuAAQKfyQAAiAACAnTFzcLACkCACAACAnTFzcLACkCAAAA.Meddii:BAEALgAECgIJAQABLgAFFAMJDgAgAHsMAA==.Medwyna:BAAALgAECgkJBQAAAA==.Melorm:BAAALgAECgMJCwAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgMJBAAAAA==.Mireille:BAAALgAECgEJAQAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAABLgAECn8VAAIHAAYJiRKBtwAUAQAHAAYJiRKBtwAUAQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgcJEQABLgAECgkJIAAHADAbAA==.Monachier:BAAALgAECgUJCwAAAA==.Moonkin:BAABLgAECn8UAAIFAAYJaxjNPACgAQAFAAYJaxjNPACgAQAAAA==.Moonlïght:BAABLgAECn8gAAIHAAkJMBsBNAAwAgAHAAkJMBsBNAAwAgAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgkJIAAHADAbAA==.Moose:BAAALgAECgYJEQAAAA==.Mordrakk:BAAALgAECgMJAwAAAA==.Morganlefay:BAABLgAECn9XAAISAAkJDAQXDwCvAAASAAkJDAQXDwCvAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8cAAIGAAkJXwxtdgCMAQAGAAkJXwxtdgCMAQAAAA==.Mosho:BAAALgAECgYJCAABLgAFFAgJKwAEAPoZAA==.Mouseharanir:BAAALgAECgcJBwAAAA==.Mousemist:BAABLgAECn85AAMYAAkJLRoFEwAmAgAYAAkJLRoFEwAmAgAMAAgJ8w5tBgBuAQAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.Muramasa:BAABLgAFFH8FAAIaAAMJHwmXCgCxAAAaAAMJHwmXCgCxAAABLgAFFAgJIwAGAE4YAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Myrthy:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAABLgAECn8lAAMlAAgJBiEqCQBeAgAlAAgJBiEqCQBeAgABAAEJ1R1qmwA8AAAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mí']='Míyágí:BAAALgAECgEJAQABLgAECggJHgATAJIbAA==.',
['Mó']='Móldy:BAAALgAECgMJCAAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJHQAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAQJBQAVAA4ZAA==.Namor:BAAALgAECgcJDQAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgYJCwAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAFFAMJBwAUAKwDAA==.Nedvox:BAECLgAFFH8HAAIUAAMJrAMnLQCVAAAUAAMJrAMnLQCVAAAuAAQKfyIAAhQACAmmEmwxAFYBABQACAmmEmwxAFYBAAAA.Nemein:BAAALgADCgUJCQAAAA==.Nervanna:BAAALgAECgEJAQAAAA==.Nervous:BAAALgAFFAIJAgAAAA==.Nessà:BAAALgAECggJEgAAAA==.Nessá:BAAALgAECgMJBQABLgAECggJEgALAAAAAA==.Neveenn:BAABLgAECn8fAAMFAAgJrBakJwAXAgAFAAgJrBakJwAXAgAPAAEJfwXnngAjAAAAAA==.Neverbakdown:BAAALgAECgUJDwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Niandri:BAAALgAECgYJDwAAAA==.Nightpigas:BAAALgADCgkJCwABLgAECgcJDwALAAAAAA==.',
No='Nohatcat:BAABLgAECn9BAAMYAAkJQCMbAwAzAwAYAAkJQCMbAwAzAwAMAAUJwxC8bADQAAAAAA==.Note:BAAALgAECgEJAQAAAA==.Notoom:BAAALgAECgcJEwAAAA==.Noxle:BAAALgADCgIJAgAAAA==.Nozarashi:BAAALgAECgQJBQAAAA==.',
Ny='Nyxara:BAABLgAECn87AAISAAkJQRw0FwCZAgASAAkJQRw0FwCZAgAAAA==.',
['Nâ']='Nâmii:BAAALgAECgYJCAAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8VAAIQAAgJ8xgVVgCiAQAQAAgJ8xgVVgCiAQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgAECgYJCQABLgAECgcJEwALAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCggJIAAAAA==.',
Ob='Obata:BAAALgAECggJDQAAAA==.',
Oc='Octavius:BAABLgAECn8VAAMOAAgJ5g4LcACEAQAOAAgJ5g4LcACEAQANAAMJqwSuTABeAAABLgAECggJFwATAOIeAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8oAAIaAAkJMBHtCwC5AQAaAAkJMBHtCwC5AQAAAA==.Ojoverde:BAACLgAFFH8SAAISAAQJMgaYawDsAAASAAQJMgaYawDsAAAuAAQKfzcAAhIACQkSHF8iAFgCABIACQkSHF8iAFgCAAAA.',
Ol='Olórin:BAAALgAECgcJCgAAAA==.',
On='Oneseraphim:BAAALgAECgIJAgAAAA==.Ontahli:BAAALgADCgUJBQABLgAECgkJLQAKALsWAA==.',
Op='Ophillã:BAABLgAECn8WAAMKAAcJbxbrHwDOAQAKAAcJbxbrHwDOAQAUAAIJwwrohwAyAAABLgAECggJEgALAAAAAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.Oromë:BAAALgAECgUJCQAAAA==.',
Ov='Overflare:BAAALgAECgIJAwAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugr:BAABLgAECn8WAAMaAAgJEBbBDQCaAQAaAAcJORbBDQCaAQAOAAcJpg2auAAIAQAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDQAAAA==.',
Pa='Painbreak:BAAALgADCgkJCQABLgAECgkJQgAVAAsgAA==.Pajamas:BAABLgAECn8ZAAINAAgJrBkwGgCMAQANAAgJrBkwGgCMAQAAAA==.Pallanquin:BAAALgAECgQJCAAAAA==.Pallywacker:BAABLgAECn8YAAIHAAYJ4wc/7ADPAAAHAAYJ4wc/7ADPAAAAAA==.Papichili:BAAALgAECgEJAQAAAA==.Pashnir:BAAALgAECgEJAQAAAA==.',
Pe='Peachey:BAABLgAECn8tAAIDAAkJNBcgIgBCAgADAAkJNBcgIgBCAgAAAA==.Peaker:BAAALgAECgIJAwAAAA==.Peiythia:BAAALgAECgEJAQAAAA==.',
Ph='Phrantic:BAAALgAECgQJBwAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAABLgAECn8eAAIYAAYJDxjgKwBgAQAYAAYJDxjgKwBgAQABLgAECgcJDwALAAAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAABLgAECn8yAAMFAAkJZBAbMQDdAQAFAAkJZBAbMQDdAQAPAAEJ9gaWnwAiAAABLgAECgQJCAALAAAAAA==.',
Ps='Psychosix:BAABLgAECn89AAIGAAkJNCWCBgBOAwAGAAkJNCWCBgBOAwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgAECgQJBgAAAA==.',
Qu='Quinberos:BAAALgAECgYJBgABLgAECgkJFgAhAPQYAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgAECgYJCQABLgAECgkJNAAHAP8gAA==.Raiola:BAABLgAECn8UAAQIAAYJpBE+OQDxAAAIAAYJpBE+OQDxAAAbAAMJ+AdeMwBOAAAQAAEJxgYpQQEvAAAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.Ramdel:BAABLgAECn8bAAMdAAcJOBiDDgBpAQAnAAcJLhTMIQBqAQAdAAcJvxODDgBpAQABLgAECgkJNgAIABceAA==.Ramstryder:BAABLgAECn82AAIIAAkJFx56CgB3AgAIAAkJFx56CgB3AgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8WAAIJAAcJHCJXAwBOAgAJAAcJHCJXAwBOAgAuAAQKfyIAAgkACAl2JdsCADYDAAkACAl2JdsCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgcJCAAAAA==.Rekmortal:BAABLgAFFH8LAAMlAAUJCBn3HgD7AAAlAAUJCRP3HgD7AAABAAQJ0hQ1NwDWAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAACLgAFFH8LAAIQAAMJwgqqOACCAAAQAAMJwgqqOACCAAAuAAQKfyoAAhAACQmKFjQ4AP0BABAACQmKFjQ4AP0BAAAA.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgAECgUJCAABLgAECgkJJAAlAIEbAA==.Rheagall:BAACLgAFFH8LAAImAAQJFRkdBAD9AAAmAAQJFRkdBAD9AAAuAAQKfyAAAiYACQlmINACAOcCACYACQlmINACAOcCAAAA.Rheagnar:BAAALgADCgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgEJAQAAAA==.Rid:BAAALgAECgEJBQAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Roaraxe:BAAALgAECgQJDAABLgAECggJFwATAOIeAA==.Rowena:BAABLgAECn8rAAIPAAkJiRo8FQBnAgAPAAkJiRo8FQBnAgAAAA==.Rowynna:BAABLgAECn8WAAMhAAkJ9BibDQDrAQAhAAgJ8xibDQDrAQAHAAIJJxYqNgF4AAAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJEwAAAA==.',
Ru='Ruxspin:BAABLgAECn8vAAMYAAkJsQqLQwDxAAAYAAgJmwmLQwDxAAAMAAgJwwKYggCaAAAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIiAAYJhwmBrgDKAAAiAAYJhwmBrgDKAAAAAA==.Ryzinneko:BAACLgAFFH8SAAMFAAUJEBiYHAB1AQAFAAUJEBiYHAB1AQAcAAIJ9whXFwB4AAAuAAQKfyYAAgUACQlRIEgcAGQCAAUACQlRIEgcAGQCAAAA.',
['Rå']='Råti:BAAALgAECgkJCAAAAA==.',
Sa='Sabend:BAACLgAFFH8eAAMSAAgJFA7NCACdAQASAAcJXRDNCACdAQAZAAEJYAAUKQBCAAAuAAQKfx8AAxIACAmgHWApAGsCABIACAmgHWApAGsCABkAAQkAAGRmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Sabor:BAAALgAECgEJAgAAAA==.Sacdk:BAAALgAECgcJCQAAAA==.Safaria:BAABLgAECn8vAAIPAAkJ0B88BwDiAgAPAAkJ0B88BwDiAgABLgAECgkJMQAXAFkXAA==.Saloenus:BAAALgAECgUJCgAAAA==.Sarlyssa:BAAALgADCgkJEwAAAA==.Satharis:BAAALgAECgcJBwABLgAECgkJRQAfAD8WAA==.Sathran:BAAALgAECgUJBwAAAA==.Saucery:BAAALgADCgkJDAAAAA==.Saucymac:BAACLgAFFH8RAAIUAAYJIgwKFABGAQAUAAYJIgwKFABGAQAuAAQKfzMAAxQACQnAIdkGAOQCABQACQnAIdkGAOQCABcABQluHMYlAJcBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.Scotchsoda:BAAALgADCgQJBAAAAA==.',
Se='Semirrhage:BAAALgAECgEJAQAAAA==.Senath:BAABLgAECn8pAAMEAAgJbRyrHACwAQAEAAcJ0hurHACwAQAjAAIJ8h5WGQClAAAAAA==.Sephrenia:BAAALgADCgcJCwAAAA==.Seradorah:BAAALgADCgQJBAAAAA==.Serandipity:BAABLgAECn8bAAMKAAkJgBrjDACeAgAKAAkJgBrjDACeAgAUAAQJSBCuUADOAAABLgAFFAYJGgANAAwYAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8hAAIGAAkJ2QyobQCfAQAGAAkJ2QyobQCfAQAAAA==.Shamalamba:BAAALgAECgkJCQABLgAFFAMJCwAQAMIKAA==.Shamanagans:BAABLgAECn8hAAIDAAYJbQs2EwB9AAADAAYJbQs2EwB9AAAAAA==.Shamanigans:BAABLgAECn8sAAIDAAgJmxFrOwDBAQADAAgJmxFrOwDBAQAAAA==.Shamgus:BAAALgAECgYJBgABLgAFFAMJCwAQAMIKAA==.Shammygoat:BAABLgAECn8WAAITAAkJmBpCGgAPAgATAAkJmBpCGgAPAgAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwABLgAECgYJFwADAEUlAA==.Shaqattack:BAACLgAFFH8LAAIYAAUJMBkHCQCKAQAYAAUJMBkHCQCKAQAuAAQKfx8AAhgACAkVI0wGABwDABgACAkVI0wGABwDAAAA.Shaqattaq:BAABLgAECn8YAAQkAAcJZRdsCACsAQAkAAcJZRdsCACsAQAjAAUJvQtvEAAIAQAEAAEJAAA4YAA1AAABLgAFFAUJCwAYADAZAA==.Sharkmeat:BAABLgAECn8qAAIUAAkJCxumEABVAgAUAAkJCxumEABVAgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnella:BAAALgAECgUJCAAAAA==.Shawnelle:BAAALgAECgUJBQAAAA==.Shawnellie:BAABLgAECn8VAAIGAAkJoh1nFwDNAgAGAAkJoh1nFwDNAgAAAA==.Shawntelle:BAABLgAECn8yAAIIAAkJHyFoBQDRAgAIAAkJHyFoBQDRAgAAAA==.Shenlune:BAAALgAECggJEgAAAA==.Sheutka:BAABLgAECn8qAAMKAAkJ7QxbKwB7AQAKAAkJ7QxbKwB7AQAUAAEJMRA9FwAyAAAAAA==.Shinaie:BAABLgAECn8nAAIUAAkJYg2MJwCSAQAUAAkJYg2MJwCSAQAAAA==.Shinkicked:BAAALgAECgUJBAABLgAECggJFwATAOIeAA==.Shockanduwu:BAABLgAECn8YAAITAAgJDxeNLQCNAQATAAgJDxeNLQCNAQAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFgAJAIcWAA==.Shtylez:BAAALgAECgUJAgAAAA==.Shuna:BAAALgAECgEJAQAAAA==.Shurshott:BAAALgAECgQJBAAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJMwAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwALAAAAAA==.Sinariel:BAABLgAECn8xAAMMAAkJ4hg3EgCNAgAMAAkJ4hg3EgCNAgAYAAgJtRLVKgCHAQAAAA==.Sinesta:BAAALgAECgUJDAAAAA==.Sirdank:BAAALgADCgMJBAAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sk='Skarlate:BAAALgADCgQJBAAAAA==.',
Sl='Slaughtrhaus:BAAALgADCgUJBQAAAA==.Sliko:BAABLgAECn8WAAIHAAkJkgkZlwBGAQAHAAkJkgkZlwBGAQAAAA==.',
Sm='Smitemachine:BAAALgADCgYJCQAAAA==.Smmoke:BAABLgAECn9WAAIQAAkJRyLNEADKAgAQAAkJRyLNEADKAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekyone:BAAALgADCgEJAQAAAA==.Sneekypally:BAAALgAFFAEJAQAAAA==.Sniperart:BAABLgAECn8hAAIQAAkJtxtoIwBWAgAQAAkJtxtoIwBWAgABLgAECgkJPQANADciAA==.',
So='Sordid:BAAALgAECgUJBwAAAA==.Sorenreign:BAAALgAECgIJAgAAAA==.Sothh:BAAALgAECgYJBgABLgAECgkJNAAHAP8gAA==.Soull:BAABLgAECn8oAAIFAAkJph2ZDAD6AgAFAAkJph2ZDAD6AgAAAA==.',
Sp='Spacemoo:BAABLgAECn8hAAQOAAgJ8h/lLgBDAgAOAAgJ8h/lLgBDAgAaAAQJDBKHJgCeAAANAAEJhAESaQAYAAAAAA==.Sparkie:BAAALgAECgUJDgABLgAECgkJOwAHAJ4YAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.Squashfoot:BAAALgAECgYJCwABLgAECggJFwATAOIeAA==.',
St='Starface:BAACLgAFFH8YAAIVAAYJ4A1XEgDyAAAVAAYJ4A1XEgDyAAAuAAQKfzIAAxUACQknH2YFALcCABUACQknH2YFALcCAAUAAQk9AfDpABsAAAAA.Stargoose:BAAALgAFFAIJAgABLgAFFAYJGAAVAOANAA==.Starrior:BAAALgAECgcJCAAAAA==.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgUJCQAAAA==.Stefane:BAABLgAECn8UAAMlAAkJVxRyKAAsAQAlAAgJXBByKAAsAQAJAAMJExvCKQDmAAAAAA==.Sterrling:BAAALgAECgMJAwAAAA==.Steverogers:BAAALgAFFAEJAQABLgAFFAQJBQAVAA4ZAA==.Stocktonrush:BAAALgAFFAIJAgABLgAFFAQJBQAVAA4ZAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAABLgAECn8VAAIHAAgJ/QorqwAmAQAHAAgJ/QorqwAmAQAAAA==.Sturmx:BAABLgAECn9RAAInAAkJdR/iBQDeAgAnAAkJdR/iBQDeAgAAAA==.',
Su='Subaaâ:BAABLgAECn8iAAMdAAgJliMGAQAzAwAdAAgJliMGAQAzAwAiAAUJIhQ9hgAaAQABLgAECgkJNQAJAHgfAA==.Subby:BAAALgADCgYJDwAAAA==.Subedei:BAACLgAFFH8OAAIOAAMJ1x2iOwC6AAAOAAMJ1x2iOwC6AAAuAAQKfzEAAw0ACQk0I0UGANMCAA0ACAk7IkUGANMCAA4ABgnAIh9LAOEBAAAA.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAABLgAECn8pAAIVAAkJJxfzEADbAQAVAAkJJxfzEADbAQAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8pAAIOAAkJ5xP4eAByAQAOAAkJ5xP4eAByAQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgYJBgABLgADCggJGAALAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Sylaurian:BAAALgAECgUJBQAAAA==.Syluxs:BAABLgAECn8rAAInAAkJ3RciEAAlAgAnAAkJ3RciEAAlAgAAAA==.Syrony:BAAALgAECgQJBAAAAA==.',
['Sû']='Sûshealä:BAABLgAECn8dAAIXAAYJAhgiKgB3AQAXAAYJAhgiKgB3AQAAAA==.',
Ta='Tabby:BAAALgAECgEJBAAAAA==.Tadryth:BAAALgADCgQJBQAAAA==.Tahrun:BAAALgADCgcJBwAAAA==.Talila:BAABLgAECn9IAAIVAAkJuyAXAQAgAgAVAAkJuyAXAQAgAgAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Tamlyn:BAAALgAECgIJAgABLgAECgkJJAAXAKojAA==.Taniss:BAAALgAECgMJBAABLgAECgkJNAAHAP8gAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Tegen:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Teron:BAAALgAECgEJAwAAAA==.Terrya:BAAALgAECgEJAgAAAA==.Teryail:BAAALgAECgcJEgAAAA==.',
Th='Thallion:BAAALgAECgQJCAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Thaqknight:BAAALgAECgkJCQAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Thedemon:BAAALgAECgEJAQAAAA==.Theion:BAAALgADCgcJBwAAAA==.Therylnn:BAAALgADCgkJCQAAAA==.Theycomeforu:BAAALgAECggJCwAAAA==.Thiccklock:BAAALgAECgYJEQAAAA==.Thily:BAAALgAECgEJAQAAAA==.Thorwallen:BAAALgAECgMJBQABLgAECgkJNAAHAP8gAA==.',
Ti='Tickle:BAABLgAECn8eAAIcAAcJOyErCgAfAgAcAAcJOyErCgAfAgAAAA==.Tidien:BAAALgADCgQJBAAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCwALAAAAAA==.Tirithor:BAABLgAECn87AAIHAAkJ1xXsTQDdAQAHAAkJ1xXsTQDdAQAAAA==.',
To='Tockell:BAAALgAECgQJBwAAAA==.Tony:BAAALgAECgYJCgABLgAFFAQJDQAYAPQSAA==.Toothless:BAAALgAECggJCAAAAA==.Torbin:BAABLgAECn8YAAIQAAgJfwiDdgBSAQAQAAgJfwiDdgBSAQAAAA==.Totemface:BAAALgAECgkJCQABLgAFFAYJEQAUACIMAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgALAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trill:BAAALgAECggJEwABLgAECgkJGwARAE8UAA==.Trilleon:BAABLgAECn8bAAMRAAkJTxTRAADRAQARAAcJ9BfRAADRAQASAAgJbwtwcQBXAQAAAA==.Trillis:BAAALgAECgYJDgABLgAECgkJGwARAE8UAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAALAAAAAA==.Trypriest:BAABLgAECn8gAAIUAAkJxRzNAACeAgAUAAkJxRzNAACeAgAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.Tsunameh:BAAALgAECgcJCgAAAA==.',
Tu='Turgà:BAAALgAECgEJBAABLgAECggJEgALAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgMJBgAAAA==.Tylíus:BAAALgAECgEJAQABLgAECgkJHgAdAMUdAA==.Tylîus:BAABLgAECn8eAAMdAAkJxR2KAABDAgAdAAgJeh+KAABDAgAnAAEJ1BF8awA3AAAAAA==.Tyredelsia:BAAALgADCgIJAgAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgAECgEJAQABLgAECggJEgALAAAAAA==.',
['Tú']='Túsk:BAAALgAECgcJCgAAAA==.',
['Tý']='Týlius:BAAALgAECgcJCgABLgAECgkJHgAdAMUdAA==.Týlïus:BAABLgAECn8WAAIhAAYJqBvzEgCbAQAhAAYJqBvzEgCbAQABLgAECgkJHgAdAMUdAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Ul='Ulanayro:BAAALgAECgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCggJGAAAAA==.',
Ut='Uthilon:BAABLgAECn9NAAIhAAkJxCUnAQBJAwAhAAkJxCUnAQBJAwAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn9CAAInAAkJWxi7AgCOAQAnAAkJWxi7AgCOAQAAAA==.Vanakith:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.',
Ve='Vedillian:BAABLgAECn8qAAIkAAgJyxGjCQCOAQAkAAgJyxGjCQCOAQAAAA==.Velanir:BAAALgAECgEJAgAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vendettuh:BAAALgAECgEJAQAAAA==.Vennaya:BAABLgAECn9AAAIXAAkJ5w2VJgCQAQAXAAkJ5w2VJgCQAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vh='Vhez:BAAALgADCgQJBAAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJDAAAAA==.Vinculus:BAAALgAECgMJAwAAAA==.Violentpanda:BAAALgAECgYJDgABLgAECggJLAAGALAkAA==.Vite:BAAALgADCggJJAAAAA==.Vitki:BAAALgAECgEJAQAAAA==.Vixious:BAAALgAECgUJBQAAAA==.Vizigoth:BAABLgAECn8zAAMSAAgJ+g1kbABjAQASAAgJ+g1kbABjAQAZAAIJCxHzVwBnAAAAAA==.',
Vo='Voidyb:BAAALgAECgMJAwAAAA==.Voladon:BAABLgAECn8iAAIFAAcJcxh1MQDbAQAFAAcJcxh1MQDbAQAAAA==.Voljanor:BAAALgAECgMJBAAAAA==.Voyana:BAABLgAECn8xAAIXAAkJWRdcEgBLAgAXAAkJWRdcEgBLAgAAAA==.',
Vy='Vydragon:BAAALgAFFAMJAwABLgAFFAYJFwAGALUWAA==.Vymage:BAACLgAFFH8XAAIGAAYJtRagPQB3AQAGAAYJtRagPQB3AQAuAAQKfzAAAwYACQmWIkQSADoDAAYACQmWIkQSADoDACgABAn9EF4KANQAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8hAAIXAAgJYQ+jBgDuAQAXAAgJYQ+jBgDuAQAuAAQKfy0AAhcACQlbH8YLAJQCABcACQlbH8YLAJQCAAAA.',
['Vã']='Vãsh:BAABLgAECn8sAAQWAAkJdgwaQwDuAAAWAAcJVAgaQwDuAAAMAAgJqghmEQCqAAAYAAUJZALRhQBOAAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warhound:BAABLgAECn8nAAIBAAcJ9BSyBABJAQABAAcJ9BSyBABJAQAAAA==.Warninja:BAABLgAECn8sAAMjAAkJDhHvCAC3AQAjAAkJTBDvCAC3AQAEAAcJiA5NJwBcAQAAAA==.Waterlogged:BAAALgADCgUJCAAAAA==.Waterloo:BAAALgAECgMJAwAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAABLgAECn8XAAMRAAgJ1hkrCADoAQARAAgJohgrCADoAQAZAAEJ/hzxMgBUAAAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIGAAgJqAnrngA9AQAGAAgJqAnrngA9AQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.Wizpigas:BAAALgAECgcJDwAAAA==.',
Wr='Wrathidan:BAABLgAECn8WAAIOAAkJTxBhZwCYAQAOAAkJTxBhZwCYAQAAAA==.',
Wu='Wutangcrom:BAAALgADCggJCAAAAA==.',
['Wì']='Wìccka:BAABLgAECn8nAAMFAAkJKRgwGgB0AgAFAAkJKRgwGgB0AgAPAAIJxgpbegBSAAAAAA==.',
Xi='Xifan:BAAALgAECgQJBwAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAABLgAFFH8JAAIEAAMJtx58IQAZAQAEAAMJtx58IQAZAQABLgAFFAgJHAAEAIIbAA==.',
Yi='Yingyang:BAAALgAECgEJAgAAAA==.',
Yo='Yodaa:BAAALgAECgYJBgABLgAECgkJNAAHAP8gAA==.Youngwokongs:BAAALgAECgEJAQAAAA==.',
Yt='Yt:BAAALgAECgYJCgABLgAFFAgJHAAEAIIbAA==.',
Yu='Yudie:BAABLgAECn8cAAIMAAYJ7g6uNQAYAQAMAAYJ7g6uNQAYAQAAAA==.',
Yw='Ywontudie:BAAALgADCgYJDAAAAA==.',
Yz='Yz:BAACLgAFFH8cAAIEAAgJghs/BQBqAgAEAAgJghs/BQBqAgAuAAQKfyUAAgQACQmzJW8BAGADAAQACQmzJW8BAGADAAAA.',
Za='Zalysi:BAABLgAECn8WAAMCAAgJHBLhJwDtAQACAAgJHBLhJwDtAQAHAAIJkQdLHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAlAAMJ0hhNUwCIAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgAECgEJAQAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAYJGAAVAOANAA==.',
Zh='Zhastr:BAABLgAECn8kAAIlAAkJgRtkCgBEAgAlAAkJgRtkCgBEAgAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zluco:BAAALgAFFAEJAQABLgAFFAYJDwASANURAA==.Zlucu:BAAALgAECgQJBwABLgAFFAYJDwASANURAA==.Zlufernal:BAACLgAFFH8PAAISAAYJ1RHqOgBfAQASAAYJ1RHqOgBfAQAuAAQKfy8AAhIACQl2IVMNAA8DABIACQl2IVMNAA8DAAAA.',
['Ðo']='Ðoom:BAAALgAECgQJAgAAAA==.',
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
