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

local lookup = {'Warrior-Fury','Paladin-Holy','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Mage-Frost','Paladin-Retribution','Hunter-Survival','Warrior-Protection','Priest-Discipline','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Priest-Shadow','Druid-Guardian','Monk-Brewmaster','Priest-Holy','Monk-Windwalker','Warlock-Destruction','DeathKnight-Frost','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acharon:BAABLgAECn85AAIBAAkJGRnQGAAmAgABAAkJGRnQGAAmAgAAAA==.',
Ad='Adrastus:BAAALgAECgcJDwAAAA==.',
Ae='Aesa:BAAALgAECgQJBAABLgAFFAQJCgACAMMKAA==.Aeslin:BAABLgAECn8XAAIDAAYJRSUmGwBuAgADAAYJRSUmGwBuAgAAAA==.',
Af='Af:BAAALgAECgUJBQABLgAFFAcJFwAEAIMdAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAABLgAFFH8KAAICAAQJwwq4KQDUAAACAAQJwwq4KQDUAAAAAA==.Ainslie:BAABLgAECn8WAAIFAAgJbxgnIABCAgAFAAgJbxgnIABCAgAAAA==.',
Al='Alarashinu:BAABLgAECn8hAAIGAAgJAwa1wQAEAQAGAAgJAwa1wQAEAQAAAA==.Alataris:BAAALgADCgUJCgABLgAECggJNwAHABcZAA==.Alawae:BAABLgAECn8xAAIIAAkJiSFYBADpAgAIAAkJiSFYBADpAgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8WAAIJAAgJhxajEwDRAQAJAAgJhxajEwDRAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Andrick:BAAALgAECgUJBgAAAA==.Angela:BAAALgADCgcJEAABLgAECgkJLQAKALsWAA==.Anosvoldgoad:BAAALgAECgIJAQAAAA==.',
Ap='Apaka:BAAALgADCgMJBAAAAA==.Apøllo:BAAALgAECgQJBAAAAA==.',
Ar='Araedia:BAAALgAECggJEwABLgAECgkJJwAFADAUAA==.Arahant:BAACLgAFFH8VAAILAAYJ8BQ1GwCLAQALAAYJ8BQ1GwCLAQAuAAQKfzIAAgsACQkJHgENAIMCAAsACQkJHgENAIMCAAAA.Arazat:BAAALgADCgIJAgAAAA==.Aretas:BAABLgAECn87AAMMAAkJNyLNBADiAgAMAAkJNyLNBADiAgANAAEJthZiXAFAAAAAAA==.Arkøn:BAAALgADCgIJAgAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.Arssi:BAAALgADCgIJAgAAAA==.',
As='Ashuffle:BAAALgAECgQJCwAAAA==.Asifa:BAABLgAECn8rAAIGAAgJ4xiNQgARAgAGAAgJ4xiNQgARAgAAAA==.Astinds:BAAALgAECgEJAgABLgAECggJEQAOAAAAAA==.',
At='Atherion:BAABLgAECn9BAAIGAAgJShU5WwDJAQAGAAgJShU5WwDJAQAAAA==.Attackroot:BAAALgADCgkJCQABLgAECggJGQAMAKwZAA==.Attackzilla:BAAALgAECgYJBwABLgAECggJGQAMAKwZAA==.',
Au='Aurakk:BAAALgADCgcJEQABLgAECggJLgAHAPAhAA==.Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJBQABLgAECgcJEQAOAAAAAA==.Avranarada:BAABLgAECn8nAAMFAAkJMBQ2JgAbAgAFAAkJMBQ2JgAbAgAPAAYJMRC0PAAZAQAAAA==.',
Aw='Aw:BAAALgADCgUJBgABLgAFFAcJFwAEAIMdAA==.',
Az='Azung:BAABLgAECn9IAAIHAAkJSCFZDgDxAgAHAAkJSCFZDgDxAgAAAA==.Azurae:BAAALgADCgkJCQAAAA==.Azureflame:BAAALgADCgYJCQABLgADCggJGAAOAAAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8ZAAIQAAYJaBvcGQCVAQAQAAYJaBvcGQCVAQAuAAQKfzQAAhAACQnjI6MHABwDABAACQnjI6MHABwDAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMRAAkJEhGuCwCeAQARAAkJEhGuCwCeAQASAAEJXwFrNAEUAAAAAA==.Baka:BAABLgAECn84AAMCAAkJACWtAQCdAwACAAkJACWtAQCdAwAHAAYJNBChkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8bAAIJAAkJGhq7DAAbAgAJAAkJGhq7DAAbAgAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8RAAINAAQJ4BimZQAqAQANAAQJ4BimZQAqAQAuAAQKfycAAw0ACAm2H2IvAD8CAA0ABwmcI2IvAD8CAAwAAQlXCExiACIAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECgcJEAAAAA==.Barrelrollin:BAABLgAECn8UAAMDAAgJxxAVXABEAQADAAYJIhEVXABEAQATAAYJWgkaVADlAAAAAA==.Batrito:BAABLgAECn8tAAMKAAkJuxb0FAAwAgAKAAkJuxb0FAAwAgAUAAcJuRSJLgBlAQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAABLgAECn8pAAIQAAcJcAwweABLAQAQAAcJcAwweABLAQAAAA==.Bearlylegál:BAABLgAFFH8FAAIVAAQJDhn3DAAiAQAVAAQJDhn3DAAiAQAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8qAAMCAAkJ2B6gBQA0AwACAAkJ2B6gBQA0AwAHAAYJGAgh5ADWAAAAAA==.Bethlahammer:BAAALgAECgQJCAABLgAECggJFwATAOIeAA==.',
Bi='Bigboom:BAAALgAECgEJAQAAAA==.Billcosbrew:BAACLgAFFH8FAAIWAAMJnB/KKAACAQAWAAMJnB/KKAACAQAuAAQKfyMAAhYACAkHJhYEAEsDABYACAkHJhYEAEsDAAEuAAUUBAkFABUADhkA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgUJDwAAAA==.Blamegame:BAAALgADCgkJCQAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJLAADAJsRAA==.Blizzcon:BAACLgAFFH8FAAIKAAMJxwP0NwCeAAAKAAMJxwP0NwCeAAAuAAQKf0IABAoACAmrGZsQAGUCAAoACAliGZsQAGUCABQABAkRCJ5ZAKsAABcAAglkCo1jAE0AAAAA.',
Bo='Boone:BAAALgAECgEJAQAAAA==.Borrgar:BAABLgAECn8uAAIHAAgJ8CHLIACCAgAHAAgJ8CHLIACCAgAAAA==.',
Br='Brackle:BAABLgAECn82AAIQAAkJ0yFGEQDEAgAQAAkJ0yFGEQDEAgAAAA==.Bracori:BAACLgAFFH8TAAILAAYJZhT2GwCDAQALAAYJZhT2GwCDAQAuAAQKfywAAwsACQmnEA8oAHQBAAsACQmnEA8oAHQBABgABwnPE7o1ACgBAAAA.Brandywynne:BAABLgAECn8pAAIQAAkJvg0lPAC+AQAQAAkJvg0lPAC+AQAAAA==.Brick:BAABLgAECn86AAIEAAkJ6CN7AwAPAwAEAAkJ6CN7AwAPAwAAAA==.Briere:BAAALgAECgEJAgAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAACLgAFFH8OAAMRAAMJaxI6CQDiAAARAAMJaxI6CQDiAAAZAAEJgRf5JABKAAAuAAQKfzwAAxkACQl+HX0HANgBABEACAk9HisHAP0BABkACAnQGX0HANgBAAAA.Bronny:BAAALgAECgIJAgAAAA==.Brownpepperz:BAAALgADCgcJCAAAAA==.Brunspirit:BAAALgAECgUJBwAAAA==.Bruticus:BAAALgADCggJCAAAAA==.',
Bu='Bubblebull:BAAALgAECgIJAwAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAFFAEJAQAAAA==.Bullrush:BAAALgADCgUJCAAAAA==.Bustyheals:BAAALgAECgcJCAABLgAFFAYJFwAMAAwYAA==.Butterbllz:BAACLgAFFH8TAAIHAAQJwhv8JgBnAQAHAAQJwhv8JgBnAQAuAAQKfyUAAgcACQk9IYoMAP8CAAcACQk9IYoMAP8CAAAA.',
['Bô']='Bôreas:BAAALgAECgEJAQABLgAECgUJCAAOAAAAAA==.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn83AAIHAAgJFxksPwAHAgAHAAgJFxksPwAHAgAAAA==.Camany:BAABLgAECn8jAAIQAAkJuRYiLAAoAgAQAAkJuRYiLAAoAgAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAYJEAAUACIMAA==.Caralath:BAAALgAECgQJBwABLgAECgYJCgAOAAAAAA==.Caramaulize:BAAALgAECgQJBAAAAA==.Caretakerz:BAABLgAECn88AAIVAAkJ8h/wAwDcAgAVAAkJ8h/wAwDcAgAAAA==.Cartus:BAABLgAECn8pAAMTAAgJLAyKQwAhAQATAAgJLAyKQwAhAQADAAUJRQWloACHAAAAAA==.',
Ce='Cedre:BAAALgADCgYJEgAAAA==.Celidoria:BAABLgAECn8mAAIHAAgJZiG2JwBiAgAHAAgJZiG2JwBiAgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Charene:BAAALgAECgEJAgAAAA==.Cheesepuff:BAABLgAECn8ZAAISAAYJkwnvvADQAAASAAYJkwnvvADQAAAAAA==.Chemoshh:BAAALgADCgYJDAABLgAECggJLgAHAPAhAA==.Chikara:BAAALgAFFAIJBAAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAYJFgAGALUWAA==.Cinnibar:BAAALgADCgYJCgAAAA==.Cirï:BAAALgAECgcJEwAAAA==.Cisbick:BAABLgAECn8hAAISAAYJhxATlgAQAQASAAYJhxATlgAQAQAAAA==.',
Cl='Clamshell:BAABLgAECn9FAAMNAAkJ1iXpAgBvAwANAAkJ1iXpAgBvAwAaAAEJAABJRQAAAAAAAA==.Clayier:BAABLgAECn8ZAAIbAAYJgRQ5EwAnAQAbAAYJgRQ5EwAnAQAAAA==.',
Cn='Cntendr:BAAALgAECgQJBgAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8oAAMYAAkJYyD3BQDsAgAYAAkJYyD3BQDsAgALAAQJCg8hdQCyAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgAECgIJAgAAAA==.Corbanite:BAAALgAECgQJCQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDwAAAA==.Covertyqt:BAABLgAECn9FAAIGAAkJyiNqBwBBAwAGAAkJyiNqBwBBAwAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn9EAAINAAkJCx+JEQDfAgANAAkJCx+JEQDfAgAAAA==.',
Cr='Cromie:BAAALgADCgkJCQAAAA==.Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgAECgkJCAAAAA==.',
['Cõ']='Cõrpses:BAEALgAECgQJBAABLgAECgkJFQAcAHwhAA==.',
Da='Daboof:BAAALgAECgQJBQAAAA==.Dabzz:BAAALgADCgMJAwAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgAECgIJAwAAAA==.Daggere:BAAALgAECgYJCwAAAA==.Damaged:BAAALgAECgQJBAABLgAECggJNwAHABcZAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgAOAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAABLgAECn8tAAMaAAYJSAyGGgD4AAAaAAYJMgyGGgD4AAANAAYJzAhKzwDmAAAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgQJBQAAAA==.Darckinz:BAABLgAECn8oAAMUAAgJmwtgMgBPAQAUAAgJmwtgMgBPAQAKAAEJ7wa2ggAmAAAAAA==.Darkenmicky:BAABLgAECn8iAAIWAAgJHAzOLQBMAQAWAAgJHAzOLQBMAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8VAAIHAAYJVgk/NQA9AQAHAAYJVgk/NQA9AQAuAAQKfywAAgcACQlqH2oYANYCAAcACQlqH2oYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAFFAEJAQABLgAFFAIJAgAOAAAAAA==.Dayloc:BAABLgAECn9GAAISAAkJ7RNNMwAKAgASAAkJ7RNNMwAKAgAAAA==.',
De='Deataria:BAAALgAECgYJCwAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Deathwish:BAAALgAECgQJBQAAAA==.Deawin:BAAALgAECgYJDAABLgAECggJFAADAMcQAA==.Delryth:BAAALgAECgYJCgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demonatrix:BAAALgADCgEJAQAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8uAAIdAAkJRx32AwCMAgAdAAkJRx32AwCMAgABLgAECgkJFQAcAHwhAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAINAAkJfhBOUgDKAQANAAkJfhBOUgDKAQAAAA==.Divinetism:BAAALgAECgcJDgAAAA==.',
Dl='Dl:BAABLgAECn87AAIUAAkJgx+TCgCmAgAUAAkJgx+TCgCmAgAAAA==.',
Do='Doomsdayy:BAAALgAECgEJAQAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQeAAgJGxWZFACfAQAfAAgJmBHmHwDCAQAeAAYJZBiZFACfAQAgAAEJwwdpSgAtAAAAAA==.Dragkohn:BAABLgAECn8VAAIgAAkJrB+2AgAzAwAgAAkJrB+2AgAzAwABLgAECgkJKwACACcmAA==.Dragonaged:BAAALgAECgEJAQAAAA==.Drakkarr:BAAALgAECgEJAQAAAA==.Drannek:BAAALgAECgEJAgAAAA==.Drimbirt:BAAALgAECgUJCwAAAA==.Drinkmormilk:BAABLgAECn8mAAIHAAgJ2hkGOgAYAgAHAAgJ2hkGOgAYAgAAAA==.Drogman:BAAALgAECgUJCQAAAA==.Droowin:BAAALgAECgQJCAABLgAECggJFAADAMcQAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgcJEAAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAABLgAECn8dAAIQAAkJFxc+LgAgAgAQAAkJFxc+LgAgAgAAAA==.',
Ec='Ectrix:BAAALgAECgEJAQAAAA==.',
Ed='Edensfury:BAABLgAECn8XAAITAAgJ4h5mEABtAgATAAgJ4h5mEABtAgAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAABLgAECn8cAAIQAAkJyxRROQD1AQAQAAkJyxRROQD1AQAAAA==.',
Ek='Ekthelion:BAABLgAECn8oAAIhAAcJshkgEgCgAQAhAAcJshkgEgCgAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIZAAYJaiA1CgAbAgAZAAYJaiA1CgAbAgAAAA==.Eleyert:BAABLgAECn9CAAITAAkJJCbQAAB+AwATAAkJJCbQAAB+AwAAAA==.Elistann:BAAALgAECgMJAwABLgAECggJLgAHAPAhAA==.Elwe:BAABLgAECn8ZAAIXAAkJwiCFBwD0AgAXAAkJwiCFBwD0AgAAAA==.',
Em='Emiri:BAAALgAECgYJBgAAAA==.Emmaga:BAABLgAECn8pAAIGAAgJBhzQNABDAgAGAAgJBhzQNABDAgAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn87AAIQAAgJ/yFKFQClAgAQAAgJ/yFKFQClAgAAAA==.Enseth:BAABLgAECn9CAAQfAAkJExbMFAA0AgAfAAkJExbMFAA0AgAeAAQJNQfjLQCsAAAgAAMJIAq9OQA5AAAAAA==.',
Ep='Ephriam:BAAALgAECgUJBQABLgAFFAYJFgACAL0VAA==.',
Er='Erakha:BAAALgAECgEJAgAAAA==.Erotikzombie:BAABLgAECn8fAAINAAkJwx/+FwC0AgANAAkJwx/+FwC0AgAAAA==.Errilyn:BAAALgADCgYJBgAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAABLgAECn8kAAMNAAgJlBg2OQAYAgANAAgJlBg2OQAYAgAMAAMJ3glPQgCDAAABLgAFFAMJBQAKAMcDAA==.',
Ex='Exene:BAABLgAECn8UAAMiAAkJ1wvxdgAvAQAiAAkJNAfxdgAvAQAdAAQJthFAGwC3AAAAAA==.',
Ez='Ezki:BAAALgAECgUJBQABLgAECggJLgAHAPAhAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAACLgAFFH8FAAIEAAIJlRIsLwCjAAAEAAIJlRIsLwCjAAAuAAQKf0kAAwQACQmBIacDAAoDAAQACQmBIacDAAoDACMABwlwEEUNAFMBAAAA.Fangrell:BAAALgAECgcJBwABLgAFFAMJBgAQAFQHAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAgJKwAEAPoZAA==.Feetworship:BAAALgAECgYJBgABLgAFFAgJKwAEAPoZAA==.Felcon:BAAALgAECgEJBQAAAA==.Felglaives:BAAALgAECgYJCQABLgAECggJGQAMAKwZAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgkJFQABLgAECggJLgAHAPAhAA==.Fet:BAACLgAFFH8rAAMEAAgJ+hkPAgDlAQAEAAgJ+hkPAgDlAQAkAAQJZw4oBwARAQAuAAQKfzUAAwQACQmkJNwIAAMDAAQACQmkJNwIAAMDACQABgmjIUcIAK4BAAAA.Feyu:BAEALgAECgYJCQABLgAFFAMJBgADAKcSAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAFFAIJAgAOAAAAAA==.Fistsoiaaryn:BAABLgAECn8XAAIWAAYJuBEHOAAaAQAWAAYJuBEHOAAaAQAAAA==.',
Fl='Flatline:BAABLgAECn8dAAIKAAkJiBd6DwB2AgAKAAkJiBd6DwB2AgAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flinnt:BAAALgAECgQJBAABLgAECggJLgAHAPAhAA==.Flöti:BAECLgAFFH8GAAIDAAMJpxLUTwCvAAADAAMJpxLUTwCvAAAuAAQKfxgAAgMACAk+GSEdADECAAMACAk+GSEdADECAAAA.',
Fo='Four:BAABLgAECn8pAAIHAAkJJxUHTwDZAQAHAAkJJxUHTwDZAQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAABLgAECn8UAAIGAAcJ9R5GUgDiAQAGAAcJ9R5GUgDiAQAAAA==.Frysky:BAABLgAECn8UAAIVAAYJ+Q2AGQDkAAAVAAYJ+Q2AGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwAOAAAAAA==.Futz:BAACLgAFFH8GAAICAAIJOxyfMwCbAAACAAIJOxyfMwCbAAAuAAQKf1EAAgIACQkYJHcBAKgDAAIACQkYJHcBAKgDAAAA.Fuzzymage:BAAALgAECgEJBgAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAACLgAFFH8KAAIQAAQJTRWkOgAxAQAQAAQJTRWkOgAxAQAuAAQKfyMAAxAACQm4G+0pADICABAACQm4G+0pADICABsABgmZD1RDAEoBAAAA.Gangrell:BAAALgADCgIJAgABLgAFFAMJBgAQAFQHAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Gi='Gilmur:BAAALgAECgEJAQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.Gnopoleon:BAAALgAECgEJAQAAAA==.',
Go='Goobermanic:BAAALgAECgUJCQAAAA==.Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgAECgEJAgAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gp='Gpa:BAAALgADCgcJCQAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMkAAkJXxusAQCvAgAkAAkJXxusAQCvAgAjAAIJUxTMGwB8AAAAAA==.Gravewin:BAAALgAECgUJBwABLgAECggJFAADAMcQAA==.Grendelheim:BAAALgAECgQJBQAAAA==.Grogar:BAAALgADCgMJAwAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.Gutso:BAAALgADCgMJAwAAAA==.',
Gw='Gwynath:BAABLgAECn8kAAQXAAkJqiMBAwBlAwAXAAkJqiMBAwBlAwAKAAYJtxo2IQCKAQAUAAEJShSYfgA7AAAAAA==.',
Ha='Hadez:BAAALgAECgEJAQAAAA==.Hagrok:BAABLgAECn8XAAIbAAgJgwWqFwDyAAAbAAgJgwWqFwDyAAAAAA==.Haldael:BAAALgAECgUJBQAAAA==.Hammerfists:BAAALgAECgQJCQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgQJBQABLgAECggJFgAJAIcWAA==.Hantak:BAAALgAECgQJCwAAAA==.Hathaendron:BAAALgAECgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.Hawkjewa:BAAALgADCgUJBQAAAA==.',
He='Headdinkd:BAAALgADCgEJAQABLgAECgkJEAAOAAAAAA==.Hemorrhagic:BAAALgADCgIJAgAAAA==.Heph:BAAALgADCgcJBwABLgADCggJGAAOAAAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIJAAgJjBOMIAAoAQAJAAgJjBOMIAAoAQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAIWAAgJ2RXKKABqAQAWAAgJ2RXKKABqAQABLgAECgkJCQAOAAAAAA==.Holyyballs:BAABLgAECn8cAAICAAkJjhyjDgCpAgACAAkJjhyjDgCpAgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgkJAwABLgAFFAMJBgAQAFQHAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn84AAIYAAkJtSKmBwDMAgAYAAkJtSKmBwDMAgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.Huyao:BAAALgAECgMJAwAAAA==.',
['Hì']='Hìroko:BAABLgAECn8oAAISAAgJGAWcoQD8AAASAAgJGAWcoQD8AAAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.Ichigò:BAAALgAECgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQAOAAAAAA==.',
Im='Im:BAAALgAECgkJCgABLgAFFAcJFwAEAIMdAA==.Imaleaf:BAAALgAECgQJBAAAAA==.Imananji:BAAALgAECgMJBAABLgAFFAYJFQAVAOANAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8fAAIiAAkJxx3gJQAyAgAiAAkJxx3gJQAyAgAAAA==.Imperius:BAAALgAECgIJAgABLgAECgYJFwADAEUlAA==.',
In='Infernodruid:BAAALgAECgMJBQABLgAECgUJBwAOAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAABLgAECn8kAAIGAAgJTA+geACEAQAGAAgJTA+geACEAQAAAA==.Invictus:BAAALgAECgIJAgAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAABLgAECn8oAAIQAAkJkxaQNAAGAgAQAAkJkxaQNAAGAgAAAA==.',
Ir='Iroh:BAABLgAECn8YAAIYAAkJwR5nDAB7AgAYAAkJwR5nDAB7AgAAAA==.Irondali:BAAALgAECgMJBQAAAA==.',
Is='Ismokeprot:BAAALgAECgUJDQAAAA==.',
Iy='Iyosen:BAAALgAECgcJBwAAAA==.',
Ja='Jainastraza:BAAALgAECgIJAgABLgAECgkJRQANANYlAA==.Jakub:BAAALgAECgYJCQAAAA==.Jarinduva:BAAALgADCggJIAAAAA==.Jawnson:BAABLgAECn81AAMEAAkJlRmADABbAgAEAAkJlRmADABbAgAjAAIJ8RK8GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jekolyn:BAAALgAECgQJBgAAAA==.Jenefer:BAACLgAFFH8XAAMMAAYJDBgNFABJAQAMAAYJDBgNFABJAQANAAEJRgdRVgBNAAAuAAQKfzEAAgwACQnoIXgIAIsCAAwACQnoIXgIAIsCAAAA.Jerzak:BAAALgAECgEJAQAAAA==.',
Ji='Jimjimmy:BAAALgAECgUJBgABLgAECggJFwATAOIeAA==.',
Jo='Joemomo:BAABLgAECn8aAAMBAAgJ1A9hNgBtAQABAAgJ1A9hNgBtAQAlAAEJ7QHNigAMAAAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAAOAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.Joulecrafter:BAAALgAECggJCQAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kachi:BAAALgADCgEJAQAAAA==.Kailback:BAABLgAECn8cAAMNAAkJpxmNRQDvAQANAAgJnBqNRQDvAQAaAAYJVBclDACyAQAAAA==.Kait:BAABLgAECn9BAAMDAAkJWh1qGgB0AgADAAkJWh1qGgB0AgAmAAYJpROSHAAUAQAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECggJFAASAG8LAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgAECgUJBQAAAA==.Kalcifur:BAACLgAFFH8WAAICAAYJvRXrEgCQAQACAAYJvRXrEgCQAQAuAAQKfy0AAgIACQk9F0gfAAYCAAIACQk9F0gfAAYCAAAA.Karper:BAAALgAECgUJCQAAAA==.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgAECgYJBwABLgAFFAYJFwAMAAwYAA==.Kasstigate:BAABLgAECn8XAAIBAAcJLBqKKgCrAQABAAcJLBqKKgCrAQABLgAFFAYJFwAMAAwYAA==.Kastiel:BAAALgAECgcJEwABLgAECgkJGwAJABoaAA==.Kathtel:BAABLgAECn8YAAIGAAgJJAsTlwBHAQAGAAgJJAsTlwBHAQAAAA==.Katstrider:BAABLgAECn9CAAIQAAkJJxoGKAA7AgAQAAkJJxoGKAA7AgAAAA==.Kattarea:BAAALgAECgYJDwABLgAECgkJQgAQACcaAA==.Kavica:BAAALgAECgYJDwABLgAFFAIJCAAFAP8cAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8sAAIJAAgJNyBOCABzAgAJAAgJNyBOCABzAgAAAA==.Kelsier:BAAALgADCgYJBgAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8QAAINAAYJJhjsNQCLAQANAAYJJhjsNQCLAQAuAAQKfyoAAg0ACQkIJTcLABIDAA0ACQkIJTcLABIDAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgUJCQAAAA==.',
Ki='Kirigiri:BAACLgAFFH8FAAIFAAMJLgKIUgB0AAAFAAMJLgKIUgB0AAAuAAQKfx8AAwUABwnXDoFmAP4AAAUABwnXDoFmAP4AABUAAQkAAEA0ACUAAAEuAAUUBgkWAAIAvRUA.Kirøs:BAAALgAECgUJBgAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgAECgMJBAABLgAECgUJBgAOAAAAAA==.',
Kk='Kkazz:BAAALgAECgQJBAABLgAECggJLgAHAPAhAA==.',
Kn='Knom:BAAALgAECgcJEQAAAA==.',
Ko='Kohn:BAABLgAECn8rAAICAAkJJyaUAADPAwACAAkJJyaUAADPAwAAAA==.Kona:BAEBLgAECn8VAAIcAAkJfCEdAgANAwAcAAkJfCEdAgANAwAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJJgAHAOseAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8RAAIcAAUJGBpMBwAvAQAcAAUJGBpMBwAvAQAuAAQKfyEAAhwACQlTIusEAMYCABwACQlTIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAABLgAECn8dAAIUAAgJOAIfWwCmAAAUAAgJOAIfWwCmAAAAAA==.Lateo:BAABLgAECn9AAAIEAAkJ6hMvEgASAgAEAAkJ6hMvEgASAgAAAA==.Lawz:BAABLgAECn8tAAQRAAkJnAjsEQBDAQARAAgJ+AfsEQBDAQAZAAcJeAayHAC+AAASAAcJuANu3wCaAAAAAA==.',
Le='Leafz:BAACLgAFFH8GAAIFAAMJKBLMOwC7AAAFAAMJKBLMOwC7AAAuAAQKfx8AAwUACAmRFSwvAOUBAAUACAmRFSwvAOUBAA8AAQmfDamMADAAAAAA.Leaonissa:BAAALgAECgMJBAAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgQJBQAAAA==.Lemonruss:BAACLgAFFH8WAAIHAAUJ4hBNSAAXAQAHAAUJ4hBNSAAXAQAuAAQKfyEAAgcACQkWGGksAHICAAcACQkWGGksAHICAAAA.Leshafrierne:BAAALgAECgUJCQABLgAECgUJCwAOAAAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8hAAMZAAcJdgXtIACiAAAZAAcJdgXtIACiAAASAAUJhAPD6wCGAAAAAA==.',
Li='Lightninghah:BAAALgAECgEJAQABLgAECgcJEwAOAAAAAA==.Lillika:BAAALgAECgUJBgAAAA==.Lilturtz:BAAALgAECgIJAgABLgAECgkJQQAYAEAjAA==.Linnea:BAAALgAECgUJDQAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Lockheed:BAAALgADCgMJAwABLgAECggJKAASABgFAA==.Longhorn:BAABLgAECn88AAMHAAkJ4BQDQQABAgAHAAkJoRMDQQABAgAhAAYJkgxoKADQAAAAAA==.Loni:BAAALgAECgcJDwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAAOAAAAAA==.Lortpegsalot:BAABLgAECn8mAAIHAAkJ6x5eIACqAgAHAAkJ6x5eIACqAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAAALgAECgYJEgAAAA==.',
Lu='Lucena:BAABLgAECn85AAIXAAgJ9yBpCQDPAgAXAAgJ9yBpCQDPAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgcJDwAOAAAAAA==.',
Ly='Lyralana:BAABLgAECn8bAAILAAgJQhnOGQBEAgALAAgJQhnOGQBEAgABLgAECgkJQwAFACcbAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Maberu:BAABLgAFFH8HAAILAAQJWgeEOgCxAAALAAQJWgeEOgCxAAABLgAFFAYJFgACAL0VAA==.Madamkluck:BAABLgAECn8pAAIFAAgJcx0QGQB6AgAFAAgJcx0QGQB6AgAAAA==.Magicienne:BAAALgAECgEJAQAAAA==.Maglubiyet:BAABLgAECn83AAImAAcJpxnnDQDOAQAmAAcJpxnnDQDOAQAAAA==.Magoz:BAAALgAECgYJDQAAAA==.Malar:BAAALgADCgUJBQAAAA==.Maleficio:BAAALgAECgEJAQAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Mareshka:BAAALgADCgUJBQAAAA==.Markyb:BAABLgAECn9AAAIHAAkJdBkFJgBqAgAHAAkJdBkFJgBqAgAAAA==.Masamura:BAACLgAFFH8hAAIGAAYJEx7FMACoAQAGAAYJEx7FMACoAQAuAAQKf0MAAgYACQlhIsASAOcCAAYACQlhIsASAOcCAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFgAJAIcWAA==.Maureanna:BAABLgAECn9DAAIFAAkJJxtNEgC5AgAFAAkJJxtNEgC5AgAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Mechahuntard:BAAALgADCgIJAgAAAA==.Medaní:BAEALgAECgkJCAABLgAFFAMJDAAgAHsMAA==.Medari:BAECLgAFFH8MAAIgAAMJewxiIQCSAAAgAAMJewxiIQCSAAAuAAQKfyQAAiAACAnTFxQLACkCACAACAnTFxQLACkCAAAA.Medwyna:BAAALgAECgkJBQAAAA==.Melorm:BAAALgAECgMJCAAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgIJAgAAAA==.Mireille:BAAALgADCgkJFwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAABLgAECn8VAAIHAAYJiRI8swAYAQAHAAYJiRI8swAYAQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgcJEQABLgAECgkJHwAHADAbAA==.Monachier:BAAALgAECgUJCwAAAA==.Moonkin:BAABLgAECn8UAAIFAAYJaxhqPACfAQAFAAYJaxhqPACfAQAAAA==.Moonlïght:BAABLgAECn8fAAIHAAkJMBtVMgA0AgAHAAkJMBtVMgA0AgAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgkJHwAHADAbAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn9HAAISAAkJBwNiuADXAAASAAkJBwNiuADXAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8cAAIGAAkJXwygdACNAQAGAAkJXwygdACNAQAAAA==.Mosho:BAAALgAECgYJCAABLgAFFAgJKwAEAPoZAA==.Mouseharanir:BAAALgAECgcJBwAAAA==.Mousemist:BAABLgAECn8yAAMYAAkJLRrBEgAmAgAYAAkJLRrBEgAmAgALAAcJhAVvTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.Muramasa:BAAALgAECgcJBwABLgAFFAYJIQAGABMeAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAABLgAECn8dAAMlAAgJHh73CABeAgAlAAgJHh73CABeAgABAAEJ1R2nmAA9AAAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mí']='Míyágí:BAAALgAECgEJAQABLgAECggJHgATAJIbAA==.',
['Mó']='Móldy:BAAALgAECgIJBgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJHQAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAQJBQAVAA4ZAA==.Namor:BAAALgAECgcJDQAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgYJCwAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAFFAMJBwAUAKwDAA==.Nedvox:BAECLgAFFH8HAAIUAAMJrAPJKwCVAAAUAAMJrAPJKwCVAAAuAAQKfyIAAhQACAmmEoMwAFoBABQACAmmEoMwAFoBAAAA.Nemein:BAAALgADCgQJBAAAAA==.Nervous:BAAALgAECgQJCwABLgAFFAIJAgAOAAAAAA==.Nessà:BAAALgAECggJEQAAAA==.Nessá:BAAALgAECgMJBQABLgAECggJEQAOAAAAAA==.Neveenn:BAABLgAECn8eAAMFAAgJcBakJwAXAgAFAAgJcBakJwAXAgAPAAEJfwUbnAAjAAAAAA==.Neverbakdown:BAAALgAECgUJDwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Niandri:BAAALgAECgYJCgAAAA==.Nightpigas:BAAALgADCgkJCwABLgAECgYJHgAYAA8YAA==.',
No='Nohatcat:BAABLgAECn9BAAMYAAkJQCP5AgA0AwAYAAkJQCP5AgA0AwALAAUJwxCxaQDQAAAAAA==.Note:BAAALgAECgEJAQAAAA==.Notoom:BAAALgAECgcJEwAAAA==.Noxle:BAAALgADCgIJAgAAAA==.Nozarashi:BAAALgAECgMJAwAAAA==.',
Ny='Nyxara:BAABLgAECn8uAAISAAkJsRqHGwB+AgASAAkJsRqHGwB+AgAAAA==.',
['Nâ']='Nâmii:BAAALgAECgIJAgAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8VAAIQAAgJ8xhBVACiAQAQAAgJ8xhBVACiAQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgAECgYJCQABLgAECgcJEwAOAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCggJGwAAAA==.',
Ob='Obata:BAAALgAECgYJCQAAAA==.',
Oc='Octavius:BAAALgAECggJEgABLgAECggJFwATAOIeAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8jAAIaAAkJ/w9TCwDAAQAaAAkJ/w9TCwDAAQAAAA==.Ojoverde:BAACLgAFFH8QAAISAAQJUwUzaQDsAAASAAQJUwUzaQDsAAAuAAQKfzcAAhIACQkSHMshAFkCABIACQkSHMshAFkCAAAA.',
Ol='Olórin:BAAALgAECgcJCAAAAA==.',
On='Ontahli:BAAALgADCgUJBQABLgAECgkJLQAKALsWAA==.',
Op='Ophillã:BAAALgAECgcJDQABLgAECggJEQAOAAAAAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.Oromë:BAAALgAECgUJBgAAAA==.',
Ov='Overflare:BAAALgAECgIJAwAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugr:BAAALgAECgcJEgAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Painbreak:BAAALgADCgkJCQABLgAECgkJPAAVAPIfAA==.Pajamas:BAABLgAECn8ZAAIMAAgJrBm6GQCOAQAMAAgJrBm6GQCOAQAAAA==.Pallanquin:BAAALgAECgQJCAAAAA==.Pallywacker:BAABLgAECn8YAAIHAAYJ4wde5wDSAAAHAAYJ4wde5wDSAAAAAA==.Papichili:BAAALgADCgkJDgAAAA==.Pashnir:BAAALgAECgEJAQAAAA==.',
Pe='Peachey:BAABLgAECn8tAAIDAAkJNBeBIQBCAgADAAkJNBeBIQBCAgAAAA==.Peaker:BAAALgAECgIJAwAAAA==.Peiythia:BAAALgAECgEJAQAAAA==.',
Ph='Phrantic:BAAALgAECgQJBgAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAABLgAECn8eAAIYAAYJDxgyKwBhAQAYAAYJDxgyKwBhAQAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAABLgAECn8yAAMFAAkJZBB9MADeAQAFAAkJZBB9MADeAQAPAAEJ9gbBnAAiAAABLgAECgQJCAAOAAAAAA==.',
Ps='Psychosix:BAABLgAECn89AAIGAAkJNCUzBgBPAwAGAAkJNCUzBgBPAwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgAECgQJBgAAAA==.',
Qu='Quinberos:BAAALgAECgYJBgABLgAECgkJFgAhAPQYAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgAECgEJAQABLgAECggJLgAHAPAhAA==.Raiola:BAABLgAECn8UAAQIAAYJpBF/OAD1AAAIAAYJpBF/OAD1AAAbAAMJ+AekMgBOAAAQAAEJxgYlOgEvAAAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgAOAAAAAA==.Ramdel:BAABLgAECn8bAAMdAAcJOBhGDgBpAQAnAAcJLhQjIQBqAQAdAAcJvxNGDgBpAQABLgAECgkJNQAIABceAA==.Ramstryder:BAABLgAECn81AAIIAAkJFx4nCgB7AgAIAAkJFx4nCgB7AgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8WAAIJAAcJHCLvAgBUAgAJAAcJHCLvAgBUAgAuAAQKfyIAAgkACAl2JdsCADYDAAkACAl2JdsCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgcJCAAAAA==.Rekmortal:BAABLgAFFH8LAAMlAAUJCBmZHQD9AAAlAAUJCROZHQD9AAABAAQJ0hSBNQDWAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAACLgAFFH8GAAIQAAMJVAfgZwDLAAAQAAMJVAfgZwDLAAAuAAQKfykAAhAACQmBFvg2AP4BABAACQmBFvg2AP4BAAAA.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgAECgUJBwABLgAECggJIwAlAPcaAA==.Rheagall:BAACLgAFFH8FAAImAAMJtBvODADuAAAmAAMJtBvODADuAAAuAAQKfx8AAiYACQlmILkCAOgCACYACQlmILkCAOgCAAAA.Rheagnar:BAAALgADCgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgEJAQAAAA==.Rid:BAAALgAECgEJBAAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Roaraxe:BAAALgAECgQJCAABLgAECggJFwATAOIeAA==.Rowena:BAABLgAECn8rAAIPAAkJiRo8FQBnAgAPAAkJiRo8FQBnAgAAAA==.Rowynna:BAABLgAECn8WAAMhAAkJ9BhRDQDsAQAhAAgJ8xhRDQDsAQAHAAIJJxaTMQF3AAAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJEwAAAA==.',
Ru='Ruxspin:BAABLgAECn8rAAMYAAgJQQoSQgDzAAAYAAcJ6ggSQgDzAAALAAgJwwJ5fgCaAAAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIiAAYJhwn+qwDKAAAiAAYJhwn+qwDKAAAAAA==.Ryzinneko:BAACLgAFFH8SAAMFAAUJEBiLGwB1AQAFAAUJEBiLGwB1AQAcAAIJ9whDFgB4AAAuAAQKfyYAAgUACQlRIOAbAGQCAAUACQlRIOAbAGQCAAAA.',
Sa='Sabend:BAACLgAFFH8eAAMSAAgJFA7NCACdAQASAAcJXRDNCACdAQAZAAEJYACGKABCAAAuAAQKfx8AAxIACAmgHWApAGsCABIACAmgHWApAGsCABkAAQkAAGRmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Sabor:BAAALgAECgEJAQAAAA==.Sacdk:BAAALgAECgMJAwAAAA==.Safaria:BAABLgAECn8vAAIPAAkJ0B8OBwDjAgAPAAkJ0B8OBwDjAgABLgAECgkJMQAXAFkXAA==.Saloenus:BAAALgAECgUJCAAAAA==.Sarlyssa:BAAALgADCgkJEwAAAA==.Sathran:BAAALgAECgUJBwAAAA==.Saucery:BAAALgADCgkJDAAAAA==.Saucymac:BAACLgAFFH8QAAIUAAYJIgwqEwBHAQAUAAYJIgwqEwBHAQAuAAQKfzMAAxQACQnAIYQGAOoCABQACQnAIYQGAOoCABcABQluHCAlAJcBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Semirrhage:BAAALgAECgEJAQAAAA==.Senath:BAABLgAECn8pAAMEAAgJbRwHHACyAQAEAAcJ0hsHHACyAQAjAAIJ8h4DGQClAAAAAA==.Sephrenia:BAAALgADCgcJCwAAAA==.Seradorah:BAAALgADCgQJBAAAAA==.Serandipity:BAABLgAECn8bAAMKAAkJgBqoDACgAgAKAAkJgBqoDACgAgAUAAQJSBBrTwDQAAABLgAFFAYJFwAMAAwYAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8hAAIGAAkJ2Qz3awCgAQAGAAkJ2Qz3awCgAQAAAA==.Shamanagans:BAABLgAECn8ZAAIDAAYJPwt1cgAAAQADAAYJPwt1cgAAAQAAAA==.Shamanigans:BAABLgAECn8sAAIDAAgJmxFmOgDBAQADAAgJmxFmOgDBAQAAAA==.Shamgus:BAAALgAECgYJBgABLgAFFAMJBgAQAFQHAA==.Shammygoat:BAABLgAECn8WAAITAAkJmBrfGQAPAgATAAkJmBrfGQAPAgAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwABLgAECgYJFwADAEUlAA==.Shaqattack:BAACLgAFFH8LAAIYAAUJMBmACACLAQAYAAUJMBmACACLAQAuAAQKfx8AAhgACAkVI0wGABwDABgACAkVI0wGABwDAAAA.Shaqattaq:BAABLgAECn8YAAQkAAcJZRdbCACsAQAkAAcJZRdbCACsAQAjAAUJvQtvEAAIAQAEAAEJAAA4YAA1AAABLgAFFAUJCwAYADAZAA==.Sharkmeat:BAABLgAECn8qAAIUAAkJCxskEABbAgAUAAkJCxskEABbAgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAABLgAECn8VAAIGAAkJoh3aFgDNAgAGAAkJoh3aFgDNAgAAAA==.Shawntelle:BAABLgAECn8wAAIIAAkJHyE2BQDUAgAIAAkJHyE2BQDUAgAAAA==.Shenlune:BAAALgAECggJDAAAAA==.Sheutka:BAABLgAECn8nAAIKAAgJhAzRKQCEAQAKAAgJhAzRKQCEAQAAAA==.Shinaie:BAABLgAECn8nAAIUAAkJYg0RJgCZAQAUAAkJYg0RJgCZAQAAAA==.Shinkicked:BAAALgAECgUJBAABLgAECggJFwATAOIeAA==.Shockanduwu:BAABLgAECn8YAAITAAgJDxffLACNAQATAAgJDxffLACNAQAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFgAJAIcWAA==.Shtylez:BAAALgAECgUJAgAAAA==.Shuna:BAAALgAECgEJAQAAAA==.Shurshott:BAAALgAECgQJBAAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJLQAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwAOAAAAAA==.Sinariel:BAABLgAECn8xAAMLAAkJ4hi/EQCNAgALAAkJ4hi/EQCNAgAYAAgJtRLVKgCHAQAAAA==.Sinesta:BAAALgAECgUJDAAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAABLgAECn8WAAIHAAkJkgmrkwBJAQAHAAkJkgmrkwBJAQAAAA==.',
Sm='Smitemachine:BAAALgADCgYJCQAAAA==.Smmoke:BAABLgAECn9HAAIQAAkJGx8kEADMAgAQAAkJGx8kEADMAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekyone:BAAALgADCgEJAQAAAA==.Sneekypally:BAAALgAFFAEJAQAAAA==.Sniperart:BAABLgAECn8hAAIQAAkJtxt3IgBXAgAQAAkJtxt3IgBXAgABLgAECgkJOwAMADciAA==.',
So='Sordid:BAAALgAECgUJBgAAAA==.Sothh:BAAALgAECgEJAQABLgAECggJLgAHAPAhAA==.Soull:BAABLgAECn8oAAIFAAkJph1kDAD6AgAFAAkJph1kDAD6AgAAAA==.',
Sp='Spacemoo:BAABLgAECn8hAAQNAAgJ8h8nLgBEAgANAAgJ8h8nLgBEAgAaAAQJDBJCJQCiAAAMAAEJhAF/ZwAYAAAAAA==.Sparkie:BAAALgAECgUJBQABLgAECggJNwAHABcZAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.Squashfoot:BAAALgAECgYJCgABLgAECggJFwATAOIeAA==.',
St='Starface:BAACLgAFFH8VAAIVAAYJ4A1AEQD1AAAVAAYJ4A1AEQD1AAAuAAQKfzIAAxUACQknHzQFALcCABUACQknHzQFALcCAAUAAQk9AfDpABsAAAAA.Stargoose:BAAALgAECgcJBwABLgAFFAYJFQAVAOANAA==.Starrior:BAAALgAECgcJCAAAAA==.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgUJCQAAAA==.Stefane:BAABLgAECn8UAAMlAAkJVxSHJwAsAQAlAAgJXBCHJwAsAQAJAAMJExsdKQDnAAAAAA==.Sterrling:BAAALgAECgMJAwAAAA==.Steverogers:BAAALgAFFAEJAQABLgAFFAQJBQAVAA4ZAA==.Stocktonrush:BAAALgAFFAIJAgABLgAFFAQJBQAVAA4ZAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAABLgAECn8UAAIHAAgJxgnLpwApAQAHAAgJxgnLpwApAQAAAA==.Sturmx:BAABLgAECn9HAAInAAkJdR+xBQDgAgAnAAkJdR+xBQDgAgAAAA==.',
Su='Subaaâ:BAABLgAECn8iAAMdAAgJliMGAQAzAwAdAAgJliMGAQAzAwAiAAUJIhQ9hgAaAQABLgAECgkJNQAJAHgfAA==.Subby:BAAALgADCgYJDwAAAA==.Subedei:BAACLgAFFH8LAAINAAMJwhkalgDeAAANAAMJwhkalgDeAAAuAAQKfzEAAwwACQk0I0UGANMCAAwACAk7IkUGANMCAA0ABgnAIgNKAOIBAAAA.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAABLgAECn8nAAIVAAgJ8xeJEADbAQAVAAgJ8xeJEADbAQAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8oAAINAAgJMBModgB1AQANAAgJMBModgB1AQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCggJGAAOAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAABLgAECn8rAAInAAkJ3RfHDwAnAgAnAAkJ3RfHDwAnAgAAAA==.Syrony:BAAALgAECgQJBAAAAA==.',
['Sû']='Sûshealä:BAABLgAECn8dAAIXAAYJAhh1KQB3AQAXAAYJAhh1KQB3AQAAAA==.',
Ta='Tabby:BAAALgAECgEJAwAAAA==.Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn9AAAIVAAgJMiFPBgCWAgAVAAgJMiFPBgCWAgAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Tamlyn:BAAALgAECgIJAgABLgAECgkJJAAXAKojAA==.Taniss:BAAALgAECgEJAgABLgAECggJLgAHAPAhAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Tegen:BAAALgADCgEJAQAAAA==.Terrya:BAAALgADCgkJEQAAAA==.Teryail:BAAALgAECgcJEgAAAA==.',
Th='Thallion:BAAALgAECgQJCAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Thaqknight:BAAALgAECgkJCQAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Therylnn:BAAALgADCgkJCQAAAA==.Theycomeforu:BAAALgAECggJCwAAAA==.Thiccklock:BAAALgAECgYJEQAAAA==.Thily:BAAALgAECgEJAQAAAA==.Thorwallen:BAAALgADCgkJIAABLgAECggJLgAHAPAhAA==.',
Ti='Tickle:BAABLgAECn8eAAIcAAcJOyHuCQAfAgAcAAcJOyHuCQAfAgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCwAOAAAAAA==.Tirithor:BAABLgAECn87AAIHAAkJ1xXvTADeAQAHAAkJ1xXvTADeAQAAAA==.',
To='Tockell:BAAALgAECgQJBwAAAA==.Tony:BAAALgAECgYJCgABLgAFFAQJDQAYAPQSAA==.Toothless:BAAALgAECggJCAAAAA==.Torbin:BAABLgAECn8YAAIQAAgJfwhMdABSAQAQAAgJfwhMdABSAQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgAOAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trill:BAAALgAECggJEgABLgAECggJFAASAG8LAA==.Trilleon:BAABLgAECn8UAAISAAgJbwsmbwBbAQASAAgJbwsmbwBbAQAAAA==.Trillis:BAAALgAECgYJDgABLgAECggJFAASAG8LAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAAOAAAAAA==.Trypriest:BAAALgAECgkJDAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.Tsunameh:BAAALgAECgUJBgAAAA==.',
Tu='Turgà:BAAALgAECgEJBAABLgAECggJEQAOAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgMJBQAAAA==.Tylîus:BAAALgAECgkJEAAAAA==.Tyredelsia:BAAALgADCgIJAgAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgAECgEJAQABLgAECggJEQAOAAAAAA==.',
['Tú']='Túsk:BAAALgAECgcJCgAAAA==.',
['Tý']='Týlïus:BAABLgAECn8WAAIhAAYJqBvzEgCbAQAhAAYJqBvzEgCbAQABLgAECgkJEAAOAAAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCggJGAAAAA==.',
Ut='Uthilon:BAABLgAECn8+AAIhAAkJdCQXAQBKAwAhAAkJdCQXAQBKAwAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn88AAInAAgJVRlGEgAFAgAnAAgJVRlGEgAFAgAAAA==.',
Ve='Vedillian:BAABLgAECn8pAAIkAAgJqBCRCQCOAQAkAAgJqBCRCQCOAQAAAA==.Velanir:BAAALgAECgEJAgAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vendettuh:BAAALgAECgEJAQAAAA==.Vennaya:BAABLgAECn86AAIXAAkJ4Q3wJQCRAQAXAAkJ4Q3wJQCRAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJCQAAAA==.Violentpanda:BAAALgAECgYJDgABLgAECggJLAAGALAkAA==.Vite:BAAALgADCggJJAAAAA==.Vixious:BAAALgADCgkJFQAAAA==.Vizigoth:BAABLgAECn8zAAMSAAgJ+g0DagBnAQASAAgJ+g0DagBnAQAZAAIJCxHzVwBnAAAAAA==.',
Vo='Voladon:BAABLgAECn8iAAIFAAcJcxghMQDaAQAFAAcJcxghMQDaAQAAAA==.Voljanor:BAAALgAECgMJAwAAAA==.Voyana:BAABLgAECn8xAAIXAAkJWRcQEgBMAgAXAAkJWRcQEgBMAgAAAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAYJFgAGALUWAA==.Vymage:BAACLgAFFH8WAAIGAAYJtRYyOQCJAQAGAAYJtRYyOQCJAQAuAAQKfzAAAwYACQmWIkQSADoDAAYACQmWIkQSADoDACgABAn9EBkKANQAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8gAAIXAAcJBhETBgDwAQAXAAcJBhETBgDwAQAuAAQKfy0AAhcACQlbH8YLAJQCABcACQlbH8YLAJQCAAAA.',
['Vã']='Vãsh:BAABLgAECn8lAAQWAAgJSgp0QgDuAAAWAAcJVAh0QgDuAAALAAQJjQWNjgByAAAYAAUJZAJWggBPAAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAABLgAECn8lAAMjAAkJkg/PCAC3AQAjAAkJww3PCAC3AQAEAAcJiA6yJgBdAQAAAA==.Waterlogged:BAAALgADCgUJCAAAAA==.Waterloo:BAAALgAECgEJAQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAABLgAECn8XAAMRAAgJ1hn0BwDpAQARAAgJohj0BwDpAQAZAAEJ/hzoMQBUAAAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIGAAgJqAmjnAA9AQAGAAgJqAmjnAA9AQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.Wizpigas:BAAALgADCgkJGQABLgAECgYJHgAYAA8YAA==.',
Wr='Wrathidan:BAABLgAECn8WAAINAAkJTxDnZACbAQANAAkJTxDnZACbAQAAAA==.',
Wu='Wutangcrom:BAAALgADCggJCAAAAA==.',
['Wì']='Wìccka:BAABLgAECn8hAAMFAAkJFhjXGQB0AgAFAAkJFhjXGQB0AgAPAAIJxgpLeABSAAAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Xu='Xunny:BAABLgAECn8iAAIBAAcJBBHnNwBmAQABAAcJBBHnNwBmAQAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAABLgAFFH8HAAIEAAMJJh4xIAAbAQAEAAMJJh4xIAAbAQABLgAFFAcJFwAEAIMdAA==.',
Yi='Yingyang:BAAALgAECgEJAgAAAA==.',
Yo='Yodaa:BAAALgADCggJCwABLgAECggJLgAHAPAhAA==.Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yt='Yt:BAAALgAECgYJCgABLgAFFAcJFwAEAIMdAA==.',
Yu='Yudie:BAABLgAECn8cAAILAAYJ7g6uNQAYAQALAAYJ7g6uNQAYAQAAAA==.',
Yw='Ywontudie:BAAALgADCgYJDAAAAA==.',
Yz='Yz:BAACLgAFFH8XAAIEAAcJgx2BBABuAgAEAAcJgx2BBABuAgAuAAQKfyIAAgQACQlqInICADMDAAQACQlqInICADMDAAAA.',
Za='Zalysi:BAABLgAECn8WAAMCAAgJHBLhJwDtAQACAAgJHBLhJwDtAQAHAAIJkQdLHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAlAAMJ0hhHUQCIAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgAECgEJAQAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAYJFQAVAOANAA==.',
Zh='Zhastr:BAABLgAECn8jAAIlAAgJ9xotCgBFAgAlAAgJ9xotCgBFAgAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgQJBwABLgAFFAYJDwASANURAA==.Zlufernal:BAACLgAFFH8PAAISAAYJ1RHXOABfAQASAAYJ1RHXOABfAQAuAAQKfy8AAhIACQl2IVMNAA8DABIACQl2IVMNAA8DAAAA.',
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
