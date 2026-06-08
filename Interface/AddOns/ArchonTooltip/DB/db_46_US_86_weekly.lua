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

local lookup = {'Warrior-Fury','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Mage-Frost','Paladin-Retribution','Hunter-Survival','Warrior-Protection','Priest-Discipline','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Priest-Shadow','Druid-Guardian','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Monk-Windwalker','Warlock-Destruction','DeathKnight-Frost','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acharon:BAABLgAECn85AAIBAAkJGRlIFwAuAgABAAkJGRlIFwAuAgAAAA==.',
Ad='Adrastus:BAAALgAECgcJDwAAAA==.',
Ae='Aesa:BAAALgAECgEJAQABLgAFFAMJBgACADEJAA==.Aeslin:BAABLgAECn8XAAIDAAYJRSW9GQBwAgADAAYJRSW9GQBwAgAAAA==.',
Af='Af:BAAALgAECgUJBQABLgAFFAQJDwAEAEQiAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAABLgAFFH8GAAICAAMJMQnGMQCgAAACAAMJMQnGMQCgAAAAAA==.Ainslie:BAABLgAECn8VAAIFAAcJiRqzIwAjAgAFAAcJiRqzIwAjAgAAAA==.',
Al='Alarashinu:BAABLgAECn8hAAIGAAgJAwZhuwALAQAGAAgJAwZhuwALAQAAAA==.Alataris:BAAALgADCgUJCgABLgAECggJNgAHALMYAA==.Alawae:BAABLgAECn8xAAIIAAkJiSEGBADuAgAIAAkJiSEGBADuAgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8WAAIJAAgJhxajEwDRAQAJAAgJhxajEwDRAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Andrick:BAAALgAECgEJAQAAAA==.Angela:BAAALgADCgcJEAABLgAECgkJLQAKALsWAA==.Anosvoldgoad:BAAALgAECgIJAQAAAA==.',
Ap='Apaka:BAAALgADCgMJBAAAAA==.',
Ar='Araedia:BAAALgAECgYJDQABLgAECgkJJQAFADAUAA==.Arahant:BAACLgAFFH8TAAILAAUJjxahHgBNAQALAAUJjxahHgBNAQAuAAQKfzIAAgsACQkJHgENAIMCAAsACQkJHgENAIMCAAAA.Arazat:BAAALgADCgIJAgAAAA==.Aretas:BAABLgAECn87AAMMAAkJNyJnBADoAgAMAAkJNyJnBADoAgANAAEJthY7TQFBAAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.Arssi:BAAALgADCgIJAgAAAA==.',
As='Ashuffle:BAAALgAECgQJCwAAAA==.Asifa:BAABLgAECn8pAAIGAAgJ1BdqRQAFAgAGAAgJ1BdqRQAFAgAAAA==.Astinds:BAAALgAECgEJAQABLgAECgcJDgAOAAAAAA==.',
At='Atherion:BAABLgAECn9BAAIGAAgJShWnWADNAQAGAAgJShWnWADNAQAAAA==.Attackzilla:BAAALgAECgYJBwABLgAECggJGQAMAKwZAA==.',
Au='Aurakk:BAAALgADCgcJDAABLgAECggJLQAHAPAhAA==.Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJBQABLgAECgcJEQAOAAAAAA==.Avranarada:BAABLgAECn8lAAMFAAkJMBQYJQAbAgAFAAkJMBQYJQAbAgAPAAYJ4g01QQD6AAAAAA==.',
Aw='Aw:BAAALgADCgUJBgABLgAFFAQJDwAEAEQiAA==.',
Az='Azung:BAABLgAECn9CAAIHAAkJPCHFEgDKAgAHAAkJPCHFEgDKAgAAAA==.Azurae:BAAALgADCgkJCQAAAA==.Azureflame:BAAALgADCgYJCQABLgADCggJGAAOAAAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8XAAIQAAUJqhmYCgANAQAQAAUJqhmYCgANAQAuAAQKfzQAAhAACQnjI9cGACEDABAACQnjI9cGACEDAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMRAAkJEhHqCgCfAQARAAkJEhHqCgCfAQASAAEJXwFrNAEUAAAAAA==.Baka:BAABLgAECn84AAMCAAkJACWLAQCfAwACAAkJACWLAQCfAwAHAAYJNBChkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8bAAIJAAkJGhr0CwAgAgAJAAkJGhr0CwAgAgAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8RAAINAAQJ4BgBXAAwAQANAAQJ4BgBXAAwAQAuAAQKfycAAw0ACAm2HyAtAEMCAA0ABwmcIyAtAEMCAAwAAQlXCINdACQAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECgcJDwAAAA==.Barrelrollin:BAAALgAECggJEwAAAA==.Batrito:BAABLgAECn8tAAMKAAkJuxb+EwAxAgAKAAkJuxb+EwAxAgATAAcJuRSiLABqAQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAABLgAECn8iAAIQAAcJ9gr3dwBDAQAQAAcJ9gr3dwBDAQAAAA==.Bearlylegál:BAABLgAFFH8FAAIUAAQJDhlICwAlAQAUAAQJDhlICwAlAQAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8qAAMCAAkJ2B4wBQA2AwACAAkJ2B4wBQA2AwAHAAYJGAg/3ADWAAAAAA==.Bethlahammer:BAAALgAECgQJCAABLgAECggJFwAVAOIeAA==.',
Bi='Bigboom:BAAALgAECgEJAQAAAA==.Billcosbrew:BAACLgAFFH8FAAIWAAMJnB8qJgAGAQAWAAMJnB8qJgAGAQAuAAQKfyMAAhYACAkHJhYEAEsDABYACAkHJhYEAEsDAAEuAAUUBAkFABQADhkA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgUJDwAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJLAADAJsRAA==.Blizzcon:BAACLgAFFH8FAAIKAAMJxwMBNACfAAAKAAMJxwMBNACfAAAuAAQKf0IABAoACAmrGdYPAGYCAAoACAliGdYPAGYCABMABAkRCLhVALAAABcAAglkCnxgAE0AAAAA.',
Bo='Boone:BAAALgAECgEJAQAAAA==.Borrgar:BAABLgAECn8tAAIHAAgJ8CFyHgCFAgAHAAgJ8CFyHgCFAgAAAA==.',
Br='Brackle:BAABLgAECn82AAIQAAkJ0yGbDwDKAgAQAAkJ0yGbDwDKAgAAAA==.Bracori:BAACLgAFFH8RAAILAAUJOReYHgBNAQALAAUJOReYHgBNAQAuAAQKfywAAwsACQmnEA8oAHQBAAsACQmnEA8oAHQBABgABwnPE8MzACgBAAAA.Brandywynne:BAABLgAECn8pAAIQAAkJvg0lPAC+AQAQAAkJvg0lPAC+AQAAAA==.Brick:BAABLgAECn86AAIEAAkJ6CMcAwASAwAEAAkJ6CMcAwASAwAAAA==.Briere:BAAALgAECgEJAgAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAACLgAFFH8LAAMRAAMJZxBWCADoAAARAAMJZxBWCADoAAAZAAEJgRc2IwBKAAAuAAQKfzwAAxkACQl+HQYHANsBABEACAk9Ho8GAAECABkACAnQGQYHANsBAAAA.Bronny:BAAALgAECgIJAgAAAA==.Brownpepperz:BAAALgADCgcJCAAAAA==.Brunspirit:BAAALgAECgQJBAAAAA==.Bruticus:BAAALgADCggJCAAAAA==.',
Bu='Bubblebull:BAAALgAECgIJAwAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAECgcJEQAAAA==.Butterbllz:BAACLgAFFH8PAAIHAAQJZhuQIQBsAQAHAAQJZhuQIQBsAQAuAAQKfyUAAgcACQk9IWALAAIDAAcACQk9IWALAAIDAAAA.',
['Bô']='Bôreas:BAAALgAECgEJAQABLgAECgUJBwAOAAAAAA==.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn82AAIHAAgJsxgnPwD+AQAHAAgJsxgnPwD+AQAAAA==.Camany:BAABLgAECn8jAAIQAAkJuRYxKQAuAgAQAAkJuRYxKQAuAgAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAUJDgATAJcNAA==.Caralath:BAAALgAECgQJBwABLgAECgYJBwAOAAAAAA==.Caramaulize:BAAALgAECgQJBAAAAA==.Caretakerz:BAABLgAECn8zAAIUAAkJRx4GBQCzAgAUAAkJRx4GBQCzAgAAAA==.Cartus:BAABLgAECn8pAAMVAAgJLAyoQAAhAQAVAAgJLAyoQAAhAQADAAUJRQXBmgCHAAAAAA==.',
Ce='Cedre:BAAALgADCgYJEgAAAA==.Celidoria:BAABLgAECn8mAAIHAAgJZiEqJQBlAgAHAAgJZiEqJQBlAgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Charene:BAAALgAECgEJAgAAAA==.Cheesepuff:BAABLgAECn8ZAAISAAYJkwnztwDSAAASAAYJkwnztwDSAAAAAA==.Chemoshh:BAAALgADCgYJBgABLgAECggJLQAHAPAhAA==.Chikara:BAAALgAFFAIJAgAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAUJFAAGAPQXAA==.Cinnibar:BAAALgADCgYJCgAAAA==.Cirï:BAAALgAECgcJEwAAAA==.Cisbick:BAABLgAECn8gAAISAAYJhxD6kQATAQASAAYJhxD6kQATAQAAAA==.',
Cl='Clamshell:BAABLgAECn89AAMNAAkJxiWuAgBxAwANAAkJxiWuAgBxAwAaAAEJAAC2QAAAAAAAAA==.Clayier:BAABLgAECn8WAAIbAAYJeBJtFAAPAQAbAAYJeBJtFAAPAQAAAA==.',
Cn='Cntendr:BAAALgAECgQJBgAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8oAAMYAAkJYyCABQDvAgAYAAkJYyCABQDvAgALAAQJCg/lbQCwAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgADCgQJBgABLgAECgkJLQAHAOAiAA==.Corbanite:BAAALgAECgQJCQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDwAAAA==.Covertyqt:BAABLgAECn8/AAIGAAkJpyNPBwBAAwAGAAkJpyNPBwBAAwAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn8+AAINAAkJ7B2zEwDKAgANAAkJ7B2zEwDKAgAAAA==.',
Cr='Cromie:BAAALgADCgkJCQAAAA==.Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgAECgkJCAAAAA==.',
['Cõ']='Cõrpses:BAEALgAECgQJBAABLgAECgkJFQAcAHwhAA==.',
Da='Daboof:BAAALgAECgMJBAAAAA==.Dabzz:BAAALgADCgMJAwAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgAECgIJAwAAAA==.Daggere:BAAALgAECgYJCwAAAA==.Damaged:BAAALgAECgQJBAABLgAECggJNgAHALMYAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgAOAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAABLgAECn8mAAMaAAYJOgpAGwDjAAANAAYJzAhqxwDqAAAaAAYJWAlAGwDjAAAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darckinz:BAABLgAECn8nAAMTAAgJkAtyLwBaAQATAAgJkAtyLwBaAQAKAAEJ7wYofAAmAAAAAA==.Darkenmicky:BAABLgAECn8iAAIWAAgJHAw/LABPAQAWAAgJHAw/LABPAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8TAAIHAAUJWwnIUQD6AAAHAAUJWwnIUQD6AAAuAAQKfywAAgcACQlqH2oYANYCAAcACQlqH2oYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAFFAEJAQABLgAFFAIJAgAOAAAAAA==.Dayloc:BAABLgAECn8+AAISAAkJ2RPrMAAPAgASAAkJ2RPrMAAPAgAAAA==.',
De='Deataria:BAAALgAECgYJCwAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Deathwish:BAAALgAECgIJAgAAAA==.Deawin:BAAALgAECgYJDAABLgAECggJEwAOAAAAAA==.Delryth:BAAALgAECgYJCgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demonatrix:BAAALgADCgEJAQAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8mAAIdAAkJYxwTBQBRAgAdAAkJYxwTBQBRAgABLgAECgkJFQAcAHwhAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAINAAkJfhC7TQDSAQANAAkJfhC7TQDSAQAAAA==.Divinetism:BAAALgAECgcJDgAAAA==.',
Dl='Dl:BAABLgAECn87AAITAAkJgx8GCgCpAgATAAkJgx8GCgCpAgAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQeAAgJGxWZFACfAQAfAAgJmBHmHwDCAQAeAAYJZBiZFACfAQAgAAEJwwdpSgAtAAAAAA==.Dragkohn:BAAALgAECgcJDQABLgAECgkJKwACACcmAA==.Dragonaged:BAAALgAECgEJAQAAAA==.Drakkarr:BAAALgAECgEJAQAAAA==.Drannek:BAAALgAECgEJAgAAAA==.Drimbirt:BAAALgAECgUJCwAAAA==.Drinkmormilk:BAABLgAECn8kAAIHAAgJxxfoQwDwAQAHAAgJxxfoQwDwAQAAAA==.Drogman:BAAALgAECgUJCQAAAA==.Droowin:BAAALgAECgQJBQABLgAECggJEwAOAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgcJDgAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAABLgAECn8dAAIQAAkJFxfAKgAnAgAQAAkJFxfAKgAnAgAAAA==.',
Ec='Ectrix:BAAALgAECgEJAQAAAA==.',
Ed='Edensfury:BAABLgAECn8XAAIVAAgJ4h5/DwBvAgAVAAgJ4h5/DwBvAgAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAABLgAECn8cAAIQAAkJyxQDNgD5AQAQAAkJyxQDNgD5AQAAAA==.',
Ek='Ekthelion:BAABLgAECn8oAAIhAAcJshlXEQCiAQAhAAcJshlXEQCiAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIZAAYJaiA1CgAbAgAZAAYJaiA1CgAbAgAAAA==.Eleyert:BAABLgAECn88AAIVAAkJJCa2AAB/AwAVAAkJJCa2AAB/AwAAAA==.Elistann:BAAALgADCgIJAgABLgAECggJLQAHAPAhAA==.Elwe:BAABLgAECn8ZAAIXAAkJwiDpBgD3AgAXAAkJwiDpBgD3AgAAAA==.',
Em='Emmaga:BAABLgAECn8pAAIGAAgJBhzqMgBGAgAGAAgJBhzqMgBGAgAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn81AAIQAAgJxiC2FwCMAgAQAAgJxiC2FwCMAgAAAA==.Enseth:BAABLgAECn87AAQfAAkJYRVSFwAVAgAfAAkJYRVSFwAVAgAeAAQJNQfjLQCsAAAgAAMJIAq1NwA6AAAAAA==.',
Ep='Ephriam:BAAALgAECgUJBQABLgAFFAUJFAACAKMVAA==.',
Er='Erakha:BAAALgAECgEJAgAAAA==.Erotikzombie:BAABLgAECn8dAAINAAgJYh6YLgA8AgANAAgJYh6YLgA8AgAAAA==.Errilyn:BAAALgADCgYJBgAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAABLgAECn8fAAMNAAcJvRnuSgDaAQANAAcJvRnuSgDaAQAMAAIJHwPEUgBAAAABLgAFFAMJBQAKAMcDAA==.',
Ex='Exene:BAABLgAECn8UAAMiAAkJ1wv4cgAvAQAiAAkJNAf4cgAvAQAdAAQJthFAGwC3AAAAAA==.',
Ez='Ezki:BAAALgADCggJDgABLgAECggJLQAHAPAhAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAABLgAECn9AAAMEAAkJjB9zBADrAgAEAAkJjB9zBADrAgAjAAcJcBC4DABVAQAAAA==.Fangrell:BAAALgAECgcJBwABLgAECgkJKQAQAIEWAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAgJJQAEAPkXAA==.Felcon:BAAALgAECgEJBQAAAA==.Felglaives:BAAALgAECgYJCAABLgAECggJGQAMAKwZAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgkJDwABLgAECggJLQAHAPAhAA==.Fet:BAACLgAFFH8lAAMEAAgJ+RcPAgDlAQAEAAgJ+RcPAgDlAQAkAAQJZw6bBgATAQAuAAQKfzQAAwQACQl3JNwIAAMDAAQACQl3JNwIAAMDACQABgmjIRIIAKwBAAAA.Feyu:BAEALgAECgYJCQABLgAFFAMJBgADAKcSAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAFFAIJAgAOAAAAAA==.Fistsoiaaryn:BAABLgAECn8XAAIWAAYJuBGzNgAbAQAWAAYJuBGzNgAbAQAAAA==.',
Fl='Flatline:BAABLgAECn8cAAIKAAgJeRioEwA1AgAKAAgJeRioEwA1AgAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flinnt:BAAALgAECgQJBAABLgAECggJLQAHAPAhAA==.Flöti:BAECLgAFFH8GAAIDAAMJpxKVSQC0AAADAAMJpxKVSQC0AAAuAAQKfxgAAgMACAk+GSEdADECAAMACAk+GSEdADECAAAA.',
Fo='Four:BAABLgAECn8pAAIHAAkJJxVaSwDaAQAHAAkJJxVaSwDaAQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAABLgAECn8UAAIGAAcJ9R4YUADlAQAGAAcJ9R4YUADlAQAAAA==.Frysky:BAABLgAECn8UAAIUAAYJ+Q2AGQDkAAAUAAYJ+Q2AGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwAOAAAAAA==.Futz:BAACLgAFFH8GAAICAAIJOxzsMQCfAAACAAIJOxzsMQCfAAAuAAQKf0kAAgIACQkYJFIBAKkDAAIACQkYJFIBAKkDAAAA.Fuzzymage:BAAALgAECgEJBQAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAACLgAFFH8GAAIQAAMJZBNOWQDfAAAQAAMJZBNOWQDfAAAuAAQKfyMAAxAACQm4G28mADsCABAACQm4G28mADsCABsABgmZD1RDAEoBAAAA.Gangrell:BAAALgADCgIJAgABLgAECgkJKQAQAIEWAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Gi='Gilmur:BAAALgAECgEJAQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.Gnopoleon:BAAALgAECgEJAQAAAA==.',
Go='Goobermanic:BAAALgAECgQJCAAAAA==.Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgAECgEJAgAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gp='Gpa:BAAALgADCgcJCQAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMkAAkJXxusAQCvAgAkAAkJXxusAQCvAgAjAAIJUxSxGgB+AAAAAA==.Gravewin:BAAALgAECgUJBwABLgAECggJEwAOAAAAAA==.Grendelheim:BAAALgAECgMJBAAAAA==.Grogar:BAAALgADCgMJAwAAAA==.Grumpycat:BAAALgADCgEJAQAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.Gutso:BAAALgADCgMJAwAAAA==.',
Gw='Gwynath:BAABLgAECn8kAAQXAAkJqiO+AgBpAwAXAAkJqiO+AgBpAwAKAAYJtxo2IQCKAQATAAEJShTceAA8AAAAAA==.',
Ha='Hagrok:BAAALgAECgcJEAAAAA==.Haldael:BAAALgAECgUJBQAAAA==.Hammerfists:BAAALgAECgQJCQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgQJBQABLgAECggJFgAJAIcWAA==.Hantak:BAAALgAECgQJCwAAAA==.Hathaendron:BAAALgAECgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.',
He='Headdinkd:BAAALgADCgEJAQABLgAECgkJEAAOAAAAAA==.Hemorrhagic:BAAALgADCgIJAgAAAA==.Heph:BAAALgADCgcJBwABLgADCggJGAAOAAAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIJAAgJjBMiHwAsAQAJAAgJjBMiHwAsAQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAIWAAgJ2RW6JwBrAQAWAAgJ2RW6JwBrAQABLgAECgkJCQAOAAAAAA==.Holyyballs:BAABLgAECn8cAAICAAkJjhzaDQCqAgACAAkJjhzaDQCqAgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgkJAwABLgAECgkJKQAQAIEWAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn84AAIYAAkJtSIgBwDPAgAYAAkJtSIgBwDPAgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.Huyao:BAAALgAECgMJAwAAAA==.',
['Hì']='Hìroko:BAABLgAECn8nAAISAAgJGAWdmwACAQASAAgJGAWdmwACAQAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.Ichigò:BAAALgAECgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQAOAAAAAA==.',
Im='Imaleaf:BAAALgAECgMJAwAAAA==.Imananji:BAAALgAECgMJBAABLgAFFAUJEwAUAJEQAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8fAAIiAAkJxx1vJAAyAgAiAAkJxx1vJAAyAgAAAA==.Imperius:BAAALgAECgIJAgABLgAECgYJFwADAEUlAA==.',
In='Infernodruid:BAAALgAECgMJBQABLgAECgUJBwAOAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAABLgAECn8kAAIGAAgJTA+PcwCMAQAGAAgJTA+PcwCMAQAAAA==.Invictus:BAAALgAECgIJAgAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAABLgAECn8nAAIQAAkJkxYeMQANAgAQAAkJkxYeMQANAgAAAA==.',
Ir='Iroh:BAABLgAECn8YAAIYAAkJwR7DCwB9AgAYAAkJwR7DCwB9AgAAAA==.Irondali:BAAALgAECgIJAgAAAA==.',
Is='Ismokeprot:BAAALgAECgUJDQAAAA==.',
Iy='Iyosen:BAAALgAECgcJBwAAAA==.',
Ja='Jainastraza:BAAALgAECgIJAgABLgAECgkJPQANAMYlAA==.Jakub:BAAALgAECgYJCQAAAA==.Jarinduva:BAAALgADCggJIAAAAA==.Jawnson:BAABLgAECn81AAMEAAkJlRmzCwBdAgAEAAkJlRmzCwBdAgAjAAIJ8RK8GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jekolyn:BAAALgAECgQJBgAAAA==.Jenefer:BAACLgAFFH8VAAMMAAUJmhliGQAHAQAMAAUJmhliGQAHAQANAAEJRgdRVgBNAAAuAAQKfzEAAgwACQnoIeYHAJECAAwACQnoIeYHAJECAAAA.Jerzak:BAAALgAECgEJAQAAAA==.',
Ji='Jimjimmy:BAAALgAECgUJBQABLgAECggJFwAVAOIeAA==.',
Jo='Joemomo:BAABLgAECn8aAAMBAAgJ1A8cNABxAQABAAgJ1A8cNABxAQAlAAEJ7QG0gwAMAAAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAAOAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.Joulecrafter:BAAALgAECggJCQAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kachi:BAAALgADCgEJAQAAAA==.Kailback:BAABLgAECn8cAAMNAAkJpxnXQgDyAQANAAgJnBrXQgDyAQAaAAYJVBc4CwC1AQAAAA==.Kait:BAABLgAECn9BAAMDAAkJWh0gGQB1AgADAAkJWh0gGQB1AgAmAAYJpRMWGwAWAQAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECggJFAASAG8LAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgAECgUJBQAAAA==.Kalcifur:BAACLgAFFH8UAAICAAUJoxW2GABPAQACAAUJoxW2GABPAQAuAAQKfy0AAgIACQk9F/8dAAgCAAIACQk9F/8dAAgCAAAA.Karper:BAAALgAECgUJCQAAAA==.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgAECgYJBwABLgAFFAUJFQAMAJoZAA==.Kasstigate:BAABLgAECn8XAAIBAAcJLBqVKACwAQABAAcJLBqVKACwAQABLgAFFAUJFQAMAJoZAA==.Kastiel:BAAALgAECgcJEwABLgAECgkJGwAJABoaAA==.Kathtel:BAABLgAECn8YAAIGAAgJJAsHkQBQAQAGAAgJJAsHkQBQAQAAAA==.Katstrider:BAABLgAECn9CAAIQAAkJJxqfJQA/AgAQAAkJJxqfJQA/AgAAAA==.Kattarea:BAAALgAECgYJDwABLgAECgkJQgAQACcaAA==.Kavica:BAAALgAECgYJDwABLgAFFAIJBgAFAP8cAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8lAAIJAAgJ9ByYDQAGAgAJAAgJ9ByYDQAGAgAAAA==.Kelsier:BAAALgADCgYJBgAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8OAAINAAUJhBijXgAtAQANAAUJhBijXgAtAQAuAAQKfyoAAg0ACQkIJTUKABYDAA0ACQkIJTUKABYDAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgUJCAAAAA==.',
Ki='Kirigiri:BAACLgAFFH8FAAIFAAMJLgIhTQB/AAAFAAMJLgIhTQB/AAAuAAQKfx8AAwUABwnXDnRkAP4AAAUABwnXDnRkAP4AABQAAQkAAEA0ACUAAAEuAAUUBQkUAAIAoxUA.Kirøs:BAAALgAECgUJBgAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgAECgMJBAABLgAECgUJBgAOAAAAAA==.',
Kk='Kkazz:BAAALgADCgcJCAABLgAECggJLQAHAPAhAA==.',
Kn='Knom:BAAALgAECgcJEQAAAA==.',
Ko='Kohn:BAABLgAECn8rAAICAAkJJyaDAADRAwACAAkJJyaDAADRAwAAAA==.Kona:BAEBLgAECn8VAAIcAAkJfCHqAQARAwAcAAkJfCHqAQARAwAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJJgAHAOseAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8RAAIcAAUJGBpbBgA4AQAcAAUJGBpbBgA4AQAuAAQKfyEAAhwACQlTIusEAMYCABwACQlTIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAABLgAECn8dAAITAAgJOALnVgCsAAATAAgJOALnVgCsAAAAAA==.Lateo:BAABLgAECn9AAAIEAAkJ6hNEEQATAgAEAAkJ6hNEEQATAgAAAA==.Lawz:BAABLgAECn8tAAQRAAkJnAjJEABDAQARAAgJ+AfJEABDAQAZAAcJeAYaGwDDAAASAAcJuAPs1wCeAAAAAA==.',
Le='Leafz:BAACLgAFFH8GAAIFAAMJKBJWOQDCAAAFAAMJKBJWOQDCAAAuAAQKfx8AAwUACAmRFa8tAOYBAAUACAmRFa8tAOYBAA8AAQmfDa+HADAAAAAA.Leaonissa:BAAALgAECgMJBAAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgMJBAAAAA==.Lemonruss:BAACLgAFFH8VAAIHAAUJ0BAGQgAZAQAHAAUJ0BAGQgAZAQAuAAQKfyEAAgcACQkWGGksAHICAAcACQkWGGksAHICAAAA.Leshafrierne:BAAALgAECgUJCQABLgAECgUJCwAOAAAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8hAAMZAAcJdgVLHwCmAAAZAAcJdgVLHwCmAAASAAUJhAMq5QCIAAAAAA==.',
Li='Lightninghah:BAAALgADCgUJBQABLgAECgcJEwAOAAAAAA==.Lillika:BAAALgAECgUJBgAAAA==.Lilturtz:BAAALgAECgIJAgABLgAECgkJOAAYAPkiAA==.Linnea:BAAALgAECgUJCAAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Lockheed:BAAALgADCgMJAwABLgAECggJJwASABgFAA==.Longhorn:BAABLgAECn8zAAMHAAkJ2xJySADiAQAHAAkJnRFySADiAQAhAAYJkgz4JgDQAAAAAA==.Loni:BAAALgAECgcJDwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAAOAAAAAA==.Lortpegsalot:BAABLgAECn8mAAIHAAkJ6x5eIACqAgAHAAkJ6x5eIACqAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAAALgAECgYJEAAAAA==.',
Lu='Lucena:BAABLgAECn8zAAIXAAgJyiC9CgCuAgAXAAgJyiC9CgCuAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgcJDwAOAAAAAA==.',
Ly='Lyralana:BAAALgAECgYJCwABLgAECgkJQwAFACcbAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Maberu:BAAALgAFFAIJAwABLgAFFAUJFAACAKMVAA==.Madamkluck:BAABLgAECn8pAAIFAAgJcx1PGAB6AgAFAAgJcx1PGAB6AgAAAA==.Magicienne:BAAALgAECgEJAQAAAA==.Maglubiyet:BAABLgAECn8wAAImAAcJZxd3EACdAQAmAAcJZxd3EACdAQAAAA==.Magoz:BAAALgAECgUJBwAAAA==.Malar:BAAALgADCgUJBQAAAA==.Maleficio:BAAALgADCgYJBQAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Mareshka:BAAALgADCgUJBQAAAA==.Markyb:BAABLgAECn84AAIHAAkJdBmUIwBtAgAHAAkJdBmUIwBtAgAAAA==.Masamura:BAACLgAFFH8gAAIGAAYJEx5qKgCrAQAGAAYJEx5qKgCrAQAuAAQKf0MAAgYACQlhIpIRAOwCAAYACQlhIpIRAOwCAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFgAJAIcWAA==.Maureanna:BAABLgAECn9DAAIFAAkJJxuSEQC5AgAFAAkJJxuSEQC5AgAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Mechahuntard:BAAALgADCgIJAgAAAA==.Medaní:BAEALgAECgkJAQABLgAFFAMJDAAgAHsMAA==.Medari:BAECLgAFFH8MAAIgAAMJewyoHwCaAAAgAAMJewyoHwCaAAAuAAQKfyQAAiAACAnTF7AKACwCACAACAnTF7AKACwCAAAA.Medwyna:BAAALgAECgkJBQAAAA==.Melorm:BAAALgAECgMJBgAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgEJAQAAAA==.Mireille:BAAALgADCgkJFwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAABLgAECn8VAAIHAAYJiRLYrAAYAQAHAAYJiRLYrAAYAQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgcJEQABLgAECgkJHwAHADAbAA==.Monachier:BAAALgAECgUJCwAAAA==.Moonkin:BAABLgAECn8UAAIFAAYJaxgQOwCfAQAFAAYJaxgQOwCfAQAAAA==.Moonlïght:BAABLgAECn8fAAIHAAkJMBuULwA3AgAHAAkJMBuULwA3AgAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgkJHwAHADAbAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8/AAISAAkJxgKguQDQAAASAAkJxgKguQDQAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8cAAIGAAkJXwyJbgCXAQAGAAkJXwyJbgCXAQAAAA==.Mosho:BAAALgAECgYJCAABLgAFFAgJJQAEAPkXAA==.Mouseharanir:BAAALgAECgcJBwAAAA==.Mousemist:BAABLgAECn8yAAMYAAkJLRreEQAoAgAYAAkJLRreEQAoAgALAAcJhAVvTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAABLgAECn8bAAMlAAgJHh5oCABhAgAlAAgJHh5oCABhAgABAAEJ1R3XkgA9AAAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mí']='Míyágí:BAAALgAECgEJAQABLgAECggJHgAVAJIbAA==.',
['Mó']='Móldy:BAAALgAECgIJBgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJHQAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAQJBQAUAA4ZAA==.Namor:BAAALgAECgUJCgAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgUJCgAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAFFAMJBwATAKwDAA==.Nedvox:BAECLgAFFH8HAAITAAMJrAPeKACXAAATAAMJrAPeKACXAAAuAAQKfyIAAhMACAmmEjIuAGEBABMACAmmEjIuAGEBAAAA.Nemein:BAAALgADCgQJBAAAAA==.Nervous:BAAALgAECgQJCwABLgAFFAIJAgAOAAAAAA==.Nessà:BAAALgAECgcJDgAAAA==.Nessá:BAAALgAECgEJAgABLgAECgcJDgAOAAAAAA==.Neveenn:BAABLgAECn8eAAMFAAgJcBakJwAXAgAFAAgJcBakJwAXAgAPAAEJfwWYlgAjAAAAAA==.Neverbakdown:BAAALgAECgUJDwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Niandri:BAAALgAECgYJBwAAAA==.Nightpigas:BAAALgADCgkJCwABLgAECgUJGQAYAGUWAA==.',
No='Nohatcat:BAABLgAECn84AAMYAAkJ+SItAwAqAwAYAAkJ+SItAwAqAwALAAUJwxD6YgDPAAAAAA==.Note:BAAALgAECgEJAQAAAA==.Notoom:BAAALgAECgcJEwAAAA==.Noxle:BAAALgADCgIJAgAAAA==.Nozarashi:BAAALgAECgMJAwAAAA==.',
Ny='Nyxara:BAABLgAECn8oAAISAAkJBhe6KAAyAgASAAkJBhe6KAAyAgAAAA==.',
['Nâ']='Nâmii:BAAALgAECgIJAgAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8VAAIQAAgJ8xhrTgCrAQAQAAgJ8xhrTgCrAQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgAECgYJCQABLgAECgcJEwAOAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCggJGwAAAA==.',
Ob='Obata:BAAALgAECgYJCQAAAA==.',
Oc='Octavius:BAAALgAECgYJEAABLgAECggJFwAVAOIeAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8jAAIaAAkJ/w9aCgDGAQAaAAkJ/w9aCgDGAQAAAA==.Ojoverde:BAACLgAFFH8QAAISAAQJUwXVYgDvAAASAAQJUwXVYgDvAAAuAAQKfzcAAhIACQkSHF4gAF0CABIACQkSHF4gAF0CAAAA.',
Ol='Olórin:BAAALgAECgcJCAAAAA==.',
On='Ontahli:BAAALgADCgUJBQABLgAECgkJLQAKALsWAA==.',
Op='Ophillã:BAAALgAECgQJBwABLgAECgcJDgAOAAAAAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.Oromë:BAAALgAECgEJAgAAAA==.',
Ov='Overflare:BAAALgAECgIJAwAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugr:BAAALgAECgcJEQAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Painbreak:BAAALgADCgkJCQABLgAECgkJMwAUAEceAA==.Pajamas:BAABLgAECn8ZAAIMAAgJrBldGACTAQAMAAgJrBldGACTAQAAAA==.Pallanquin:BAAALgAECgQJCAAAAA==.Pallywacker:BAABLgAECn8YAAIHAAYJ4wd63wDSAAAHAAYJ4wd63wDSAAAAAA==.Papichili:BAAALgADCgkJDgAAAA==.Pashnir:BAAALgAECgEJAQAAAA==.',
Pe='Peachey:BAABLgAECn8tAAIDAAkJNBcCIABCAgADAAkJNBcCIABCAgAAAA==.Peaker:BAAALgAECgIJAwAAAA==.Peiythia:BAAALgAECgEJAQAAAA==.',
Ph='Phrantic:BAAALgAECgQJBgAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAABLgAECn8ZAAIYAAUJZRb3OQAMAQAYAAUJZRb3OQAMAQAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAABLgAECn8oAAIFAAkJvgzUOwCbAQAFAAkJvgzUOwCbAQABLgAECgQJCAAOAAAAAA==.',
Ps='Psychosix:BAABLgAECn89AAIGAAkJNCWkBQBUAwAGAAkJNCWkBQBUAwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgAECgQJBgAAAA==.',
Qu='Quinberos:BAAALgAECgYJBgABLgAECgkJFgAhAPQYAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgAECgEJAQABLgAECggJLQAHAPAhAA==.Raiola:BAABLgAECn8UAAQIAAYJpBGhNgD6AAAIAAYJpBGhNgD6AAAbAAMJ+AfTMABOAAAQAAEJxgZ6KwExAAAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgAOAAAAAA==.Ramdel:BAABLgAECn8bAAMdAAcJOBicDQBpAQAnAAcJLhSGHwBrAQAdAAcJvxOcDQBpAQABLgAECgkJNQAIABceAA==.Ramstryder:BAABLgAECn81AAIIAAkJFx6dCQCAAgAIAAkJFx6dCQCAAgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8WAAIJAAcJHCL9AQBnAgAJAAcJHCL9AQBnAgAuAAQKfyEAAgkACAlrJdsCADYDAAkACAlrJdsCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgcJCAAAAA==.Rekmortal:BAABLgAFFH8LAAMlAAUJCBnBGgD+AAAlAAUJCRPBGgD+AAABAAQJ0hSpMQDWAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8pAAIQAAkJgRbRMwACAgAQAAkJgRbRMwACAgAAAA==.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgAECgMJBQABLgAECggJIwAlAPcaAA==.Rheagall:BAACLgAFFH8FAAImAAMJtBs4CwD0AAAmAAMJtBs4CwD0AAAuAAQKfx8AAiYACQlmIHcCAOwCACYACQlmIHcCAOwCAAAA.Rheagnar:BAAALgADCgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgEJAQAAAA==.Rid:BAAALgAECgEJAwAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Roaraxe:BAAALgAECgQJCAABLgAECggJFwAVAOIeAA==.Rowena:BAABLgAECn8rAAIPAAkJiRo8FQBnAgAPAAkJiRo8FQBnAgAAAA==.Rowynna:BAABLgAECn8WAAMhAAkJ9BicDADvAQAhAAgJ8xicDADvAQAHAAIJJxa4JgF4AAAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJEwAAAA==.',
Ru='Ruxspin:BAABLgAECn8pAAMYAAgJVgspSgDMAAAYAAYJUwkpSgDMAAALAAgJuAL8dQCaAAAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIiAAYJhwlEpgDKAAAiAAYJhwlEpgDKAAAAAA==.Ryzinneko:BAACLgAFFH8RAAMFAAQJTRpsIQBAAQAFAAQJTRpsIQBAAQAcAAIJ9wgOFAB9AAAuAAQKfyYAAgUACQlRIP8aAGUCAAUACQlRIP8aAGUCAAAA.',
Sa='Sabend:BAACLgAFFH8eAAMSAAgJFA7NCACdAQASAAcJXRDNCACdAQAZAAEJYABZJgBCAAAuAAQKfx8AAxIACAmgHWApAGsCABIACAmgHWApAGsCABkAAQkAAGRmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Sacdk:BAAALgAECgIJAgAAAA==.Safaria:BAABLgAECn8sAAIPAAgJ9B7SDQBzAgAPAAgJ9B7SDQBzAgABLgAECgkJLgAXAHMWAA==.Saloenus:BAAALgAECgUJBwAAAA==.Sarlyssa:BAAALgADCgkJEwAAAA==.Sathran:BAAALgAECgUJBwAAAA==.Saucery:BAAALgADCgkJDAAAAA==.Saucymac:BAACLgAFFH8OAAITAAUJlw2dGwD+AAATAAUJlw2dGwD+AAAuAAQKfzMAAxMACQnAIQkGAO4CABMACQnAIQkGAO4CABcABQluHKgjAJkBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Semirrhage:BAAALgAECgEJAQAAAA==.Senath:BAABLgAECn8pAAMEAAgJbRy4GgCzAQAEAAcJ0hu4GgCzAQAjAAIJ8h4cGAClAAAAAA==.Sephrenia:BAAALgADCgcJCwAAAA==.Seradorah:BAAALgADCgQJBAAAAA==.Serandipity:BAABLgAECn8bAAMKAAkJgBoPDACgAgAKAAkJgBoPDACgAgATAAQJSBDESwDXAAABLgAFFAUJFQAMAJoZAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8hAAIGAAkJ2Qz6ZQCrAQAGAAkJ2Qz6ZQCrAQAAAA==.Shamanagans:BAABLgAECn8ZAAIDAAYJPwtfbgAAAQADAAYJPwtfbgAAAQAAAA==.Shamanigans:BAABLgAECn8sAAIDAAgJmxHvNwDCAQADAAgJmxHvNwDCAQAAAA==.Shamgus:BAAALgAECgYJBgABLgAECgkJKQAQAIEWAA==.Shammygoat:BAABLgAECn8WAAIVAAkJmBqKGAARAgAVAAkJmBqKGAARAgAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwABLgAECgYJFwADAEUlAA==.Shaqattack:BAACLgAFFH8JAAIYAAQJixnoDwA0AQAYAAQJixnoDwA0AQAuAAQKfx8AAhgACAkVI0wGABwDABgACAkVI0wGABwDAAAA.Shaqattaq:BAABLgAECn8YAAQkAAcJZRckCACqAQAkAAcJZRckCACqAQAjAAUJvQtvEAAIAQAEAAEJAAA4YAA1AAABLgAFFAQJCQAYAIsZAA==.Sharkmeat:BAABLgAECn8qAAITAAkJCxtZDwBdAgATAAkJCxtZDwBdAgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAABLgAECn8VAAIGAAkJoh1NFQDTAgAGAAkJoh1NFQDTAgAAAA==.Shawntelle:BAABLgAECn8oAAIIAAkJGSABBwCrAgAIAAkJGSABBwCrAgAAAA==.Shenlune:BAAALgAECgcJCwAAAA==.Sheutka:BAABLgAECn8lAAIKAAgJ/wuwKAB/AQAKAAgJ/wuwKAB/AQAAAA==.Shinaie:BAABLgAECn8nAAITAAkJYg1yIwClAQATAAkJYg1yIwClAQAAAA==.Shockanduwu:BAABLgAECn8YAAIVAAgJDxfYKgCOAQAVAAgJDxfYKgCOAQAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFgAJAIcWAA==.Shtylez:BAAALgAECgUJAgAAAA==.Shurshott:BAAALgAECgQJBAAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJLQAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwAOAAAAAA==.Sinariel:BAABLgAECn8xAAMLAAkJ4hiTEACNAgALAAkJ4hiTEACNAgAYAAgJtRLVKgCHAQAAAA==.Sinesta:BAAALgAECgUJDAAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAABLgAECn8WAAIHAAkJkgl6jQBLAQAHAAkJkgl6jQBLAQAAAA==.',
Sm='Smitemachine:BAAALgADCgYJCQAAAA==.Smmoke:BAABLgAECn8/AAIQAAkJGx/bDgDQAgAQAAkJGx/bDgDQAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAFFAEJAQAAAA==.Sniperart:BAABLgAECn8hAAIQAAkJtxvLHwBdAgAQAAkJtxvLHwBdAgABLgAECgkJOwAMADciAA==.',
So='Sordid:BAAALgAECgUJBgAAAA==.Sothh:BAAALgAECgEJAQABLgAECggJLQAHAPAhAA==.Soull:BAABLgAECn8oAAIFAAkJph3YCwD6AgAFAAkJph3YCwD6AgAAAA==.',
Sp='Spacemoo:BAABLgAECn8hAAQNAAgJ8h/6KwBIAgANAAgJ8h/6KwBIAgAaAAQJDBLwIgCjAAAMAAEJhAGkYgAZAAAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.Squashfoot:BAAALgAECgQJBQABLgAECggJFwAVAOIeAA==.',
St='Starface:BAACLgAFFH8TAAIUAAUJkRD+EwDMAAAUAAUJkRD+EwDMAAAuAAQKfzIAAxQACQknH9wEALgCABQACQknH9wEALgCAAUAAQk9AfDpABsAAAAA.Stargoose:BAAALgAECgcJBwABLgAFFAUJEwAUAJEQAA==.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgUJCQAAAA==.Stefane:BAABLgAECn8UAAMlAAkJVxQmJgAuAQAlAAgJXBAmJgAuAQAJAAMJExtvJwDpAAAAAA==.Sterrling:BAAALgAECgMJAwAAAA==.Steverogers:BAAALgAFFAEJAQABLgAFFAQJBQAUAA4ZAA==.Stocktonrush:BAAALgAFFAIJAgABLgAFFAQJBQAUAA4ZAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAABLgAECn8UAAIHAAgJxgltoQApAQAHAAgJxgltoQApAQAAAA==.Sturmx:BAABLgAECn8/AAInAAkJdR8zBQDjAgAnAAkJdR8zBQDjAgAAAA==.',
Su='Subaaâ:BAABLgAECn8iAAMdAAgJliMGAQAzAwAdAAgJliMGAQAzAwAiAAUJIhQ9hgAaAQABLgAECgkJNQAJAHgfAA==.Subby:BAAALgADCgYJDwAAAA==.Subedei:BAACLgAFFH8LAAINAAMJwhlJigDjAAANAAMJwhlJigDjAAAuAAQKfzEAAwwACQk0I0UGANMCAAwACAk7IkUGANMCAA0ABgnAIhJHAOUBAAAA.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAABLgAECn8lAAIUAAgJnxamEQDAAQAUAAgJnxamEQDAAQAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8oAAINAAgJMBPObwB8AQANAAgJMBPObwB8AQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCggJGAAOAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAABLgAECn8rAAInAAkJ3ReyDgApAgAnAAkJ3ReyDgApAgAAAA==.Syrony:BAAALgAECgQJBAAAAA==.',
['Sû']='Sûshealä:BAABLgAECn8cAAIXAAYJAhjyJwB5AQAXAAYJAhjyJwB5AQAAAA==.',
Ta='Tabby:BAAALgAECgEJAgAAAA==.Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn86AAIUAAgJMB/JBwBnAgAUAAgJMB/JBwBnAgAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Tamlyn:BAAALgAECgIJAgAAAA==.Taniss:BAAALgAECgEJAQABLgAECggJLQAHAPAhAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Tegen:BAAALgADCgEJAQAAAA==.Terrya:BAAALgADCgkJEQAAAA==.Teryail:BAAALgAECgcJEgAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Thaqknight:BAAALgAECgkJCQAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Therylnn:BAAALgADCgkJCQAAAA==.Theycomeforu:BAAALgAECggJCwAAAA==.Thiccklock:BAAALgAECgYJEQAAAA==.Thily:BAAALgAECgEJAQAAAA==.Thorwallen:BAAALgADCgkJGQABLgAECggJLQAHAPAhAA==.',
Ti='Tickle:BAABLgAECn8eAAIcAAcJOyFRCQAiAgAcAAcJOyFRCQAiAgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCwAOAAAAAA==.Tirithor:BAABLgAECn87AAIHAAkJ1xUDSQDgAQAHAAkJ1xUDSQDgAQAAAA==.',
To='Tockell:BAAALgAECgQJBwAAAA==.Tony:BAAALgAECgYJCgABLgAFFAQJDQAYAPQSAA==.Toothless:BAAALgAECggJCAAAAA==.Torbin:BAABLgAECn8YAAIQAAgJfwjBbgBXAQAQAAgJfwjBbgBXAQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgAOAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trill:BAAALgAECgcJCwABLgAECggJFAASAG8LAA==.Trilleon:BAABLgAECn8UAAISAAgJbwvMagBiAQASAAgJbwvMagBiAQAAAA==.Trillis:BAAALgAECgYJDQABLgAECggJFAASAG8LAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAAOAAAAAA==.Trypriest:BAAALgAECgMJAwAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.Tsunameh:BAAALgAECgQJBAAAAA==.',
Tu='Turgà:BAAALgAECgEJBAABLgAECgcJDgAOAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgMJBQAAAA==.Tylîus:BAAALgAECgYJBwABLgAECgYJFgAhAKgbAA==.Tyredelsia:BAAALgADCgIJAgAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgAECgEJAQABLgAECgcJDgAOAAAAAA==.',
['Tú']='Túsk:BAAALgAECgcJCgAAAA==.',
['Tý']='Týlïus:BAABLgAECn8WAAIhAAYJqBvzEgCbAQAhAAYJqBvzEgCbAQAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCggJGAAAAA==.',
Ut='Uthilon:BAABLgAECn8+AAIhAAkJdCTyAABMAwAhAAkJdCTyAABMAwAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn82AAInAAgJWRePFADbAQAnAAgJWRePFADbAQAAAA==.',
Ve='Vedillian:BAABLgAECn8pAAIkAAgJqBBVCQCMAQAkAAgJqBBVCQCMAQAAAA==.Velanir:BAAALgAECgEJAgAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vendettuh:BAAALgAECgEJAQAAAA==.Vennaya:BAABLgAECn8yAAIXAAkJHw1FJQCMAQAXAAkJHw1FJQCMAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJCQAAAA==.Violentpanda:BAAALgAECgYJDgABLgAECggJLAAGALAkAA==.Vite:BAAALgADCggJJAAAAA==.Vixious:BAAALgADCgkJFQAAAA==.Vizigoth:BAABLgAECn8zAAMSAAgJ+g2GZQBuAQASAAgJ+g2GZQBuAQAZAAIJCxHzVwBnAAAAAA==.',
Vo='Voladon:BAABLgAECn8iAAIFAAcJcxjYLwDaAQAFAAcJcxjYLwDaAQAAAA==.Voyana:BAABLgAECn8uAAIXAAkJcxY6EgBAAgAXAAkJcxY6EgBAAgAAAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAUJFAAGAPQXAA==.Vymage:BAACLgAFFH8UAAIGAAUJ9BfbKAAQAQAGAAUJ9BfbKAAQAQAuAAQKfzAAAwYACQmWIkQSADoDAAYACQmWIkQSADoDACgABAn9EGsJANYAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8fAAIXAAYJ2xL8BwCzAQAXAAYJ2xL8BwCzAQAuAAQKfy0AAhcACQlbH8YLAJQCABcACQlbH8YLAJQCAAAA.',
['Vã']='Vãsh:BAABLgAECn8kAAQWAAgJSgqCQADwAAAWAAcJVAiCQADwAAALAAQJjQU2hQByAAAYAAUJZAKxfABPAAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAABLgAECn8kAAMjAAkJoA6HCAC4AQAjAAkJww2HCAC4AQAEAAcJ8gzaJgBPAQAAAA==.Waterlogged:BAAALgADCgUJCAAAAA==.Waterloo:BAAALgAECgEJAQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAABLgAECn8XAAMRAAgJ1hlmBwDrAQARAAgJohhmBwDrAQAZAAEJ/hz7LwBUAAAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIGAAgJqAnRlgBGAQAGAAgJqAnRlgBGAQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.Wizpigas:BAAALgADCgkJGQABLgAECgUJGQAYAGUWAA==.',
Wr='Wrathidan:BAABLgAECn8WAAINAAkJTxBmXwCiAQANAAkJTxBmXwCiAQAAAA==.',
Wu='Wutangcrom:BAAALgADCggJCAAAAA==.',
['Wì']='Wìccka:BAABLgAECn8gAAMFAAkJLBY3HgBKAgAFAAkJLBY3HgBKAgAPAAIJxgrmcwBSAAAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Xu='Xunny:BAABLgAECn8iAAIBAAcJBBFdNQBrAQABAAcJBBFdNQBrAQAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAAALgAFFAEJAQABLgAFFAQJDwAEAEQiAA==.',
Yi='Yingyang:BAAALgAECgEJAQAAAA==.',
Yo='Yodaa:BAAALgADCgcJBwABLgAECggJLQAHAPAhAA==.Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAABLgAECn8cAAILAAYJ7g6uNQAYAQALAAYJ7g6uNQAYAQAAAA==.',
Yw='Ywontudie:BAAALgADCgYJDAAAAA==.',
Yz='Yz:BAACLgAFFH8PAAIEAAQJRCJoDQCaAQAEAAQJRCJoDQCaAQAuAAQKfyAAAgQACQneIVEDAAwDAAQACQneIVEDAAwDAAAA.',
Za='Zalysi:BAABLgAECn8WAAMCAAgJHBLhJwDtAQACAAgJHBLhJwDtAQAHAAIJkQdLHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAlAAMJ0hgXTgCJAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgAECgEJAQAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAUJEwAUAJEQAA==.',
Zh='Zhastr:BAABLgAECn8jAAIlAAgJ9xqcCQBIAgAlAAgJ9xqcCQBIAgAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgQJBwABLgAFFAUJDQASAPgTAA==.Zlufernal:BAACLgAFFH8NAAISAAUJ+BM8VQAQAQASAAUJ+BM8VQAQAQAuAAQKfy8AAhIACQl2IVMNAA8DABIACQl2IVMNAA8DAAAA.',
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
