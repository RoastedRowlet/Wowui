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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Restoration','Warrior-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Hunter-Survival','Priest-Shadow','Priest-Holy','Mage-Fire','Druid-Balance','Priest-Discipline','Druid-Guardian','Monk-Mistweaver','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abaddon:BAABLgAECn8tAAMBAAkJTB8qBwAoAgABAAgJ6R0qBwAoAgACAAgJrBzyRQDwAQAAAA==.Abessedge:BAAALgAECggJDQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8zAAIDAAkJKR0HCgAuAwADAAkJKR0HCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJMwADACkdAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alkaios:BAAALgAECgcJDQABLgAFFAQJBgAFAE8KAA==.Alor:BAAALgAECgIJBAABLgAECgkJNgAGAHsOAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMHAAgJDhWRVgCDAQAHAAgJDhWRVgCDAQAIAAEJawx8cAAvAAABLgAFFAkJHQAGACMRAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLwAJAOoWAA==.Amnoon:BAABLgAECn82AAIKAAkJ+BfnEwBwAgAKAAkJ+BfnEwBwAgAAAA==.Amri:BAACLgAFFH8iAAMLAAYJPRWsMAD/AAALAAUJSxOsMAD/AAAMAAIJ1QtcJQBvAAAuAAQKfy4AAwsACAnRGl4DAHgBAAsACAnRGl4DAHgBAAwABglADVUiAN0AAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgUJCwAAAA==.',
Ar='Ardor:BAEALgADCgkJCQAAAA==.Ardrhys:BAAALgAFFAQJBAAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAFFAEJAQABLgAFFAcJFAAIAOsVAA==.',
As='Assasin:BAAALgAECgYJBgAAAA==.Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAABLgAECn8YAAINAAkJ8xY2DgDSAQANAAkJ8xY2DgDSAQAAAA==.',
At='Atreus:BAABLgAECn8nAAMIAAkJ7BxcDgA/AgAIAAkJ7BxcDgA/AgAHAAEJVAswIAEqAAABLgAFFAEJAQAEAAAAAA==.Atzalan:BAABLgAECn8UAAIOAAYJpwnpcwD7AAAOAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn80AAQPAAkJfhBxGgBmAQAPAAkJfhBxGgBmAQAQAAUJ1g5CDQDKAAARAAEJ+wnERAAvAAAAAA==.',
Az='Azorah:BAAALgAECgYJBwAAAA==.Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Badhabit:BAAALgADCgYJBgAAAA==.Baku:BAAALgAECgYJBgABLgAFFAcJFAAIAOsVAA==.Baldyguy:BAAALgAECgUJDQAAAA==.Balm:BAACLgAFFH8HAAIOAAQJOwbLHAB6AAAOAAQJOwbLHAB6AAAuAAQKfzEAAg4ACQkIGr4hADoCAA4ACQkIGr4hADoCAAAA.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgMJAwABLgAFFAEJAQAEAAAAAA==.Beautzibub:BAAALgADCgkJEAAAAA==.Behindyou:BAAALgAECggJDgABLgAECgkJKQASAAgVAA==.Bermin:BAAALgAECgEJAQAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bielebog:BAAALgADCgMJAwAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BTEXQCvAQACAAgJ/BTEXQCvAQAAAA==.Blackmouser:BAAALgAECgQJBAAAAA==.Blemish:BAAALgAECgEJAQABLgAFFAQJBwAOADsGAA==.Bloodpac:BAAALgAECgQJCAAAAA==.',
Bm='Bmo:BAABLgAECn8VAAISAAcJZSB1SAAJAgASAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMSAAIJOQwQqgBtAAASAAIJUAUQqgBtAAAFAAIJOQwOCAA2AAAuAAQKfy8AAwUACQnYI7MCAP8CAAUACQnYI7MCAP8CABIAAwnyFuDiANoAAAAA.Bonedmuch:BAAALgAECggJDgABLgAECgkJLwAJAOoWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAITAAcJ6wa1EwDRAAATAAcJ6wa1EwDRAAAAAA==.Breadria:BAAALgAECgEJAwABLgAFFAMJCQAUAFkGAA==.Bremitin:BAAALgAFFAIJAgABLgAFFAQJBgAFAE8KAA==.Bremitus:BAAALgAECgIJAwABLgAFFAQJBgAFAE8KAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQABLgAFFAEJAgAEAAAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIHAAgJ5B+wNwAXAgAHAAgJ5B+wNwAXAgAAAA==.Brud:BAABLgAFFH8FAAIRAAMJPwdsEACsAAARAAMJPwdsEACsAAAAAA==.Brunstan:BAACLgAFFH8TAAIVAAUJfh8SEgBDAQAVAAUJfh8SEgBDAQAuAAQKfxkAAhUACQnjIL4CALwCABUACQnjIL4CALwCAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.Bullet:BAAALgAECgYJDwAAAA==.',
By='Byakugan:BAACLgAFFH8dAAMGAAkJIxF1BQCDAQAGAAcJjhB1BQCDAQAWAAMJEgl+TADBAAAuAAQKfyAABAYACQktH5oPAK8CAAYACQktH5oPAK8CABcAAQm+F78pAEEAABYAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8kAAIYAAkJGQkzeACJAQAYAAkJGQkzeACJAQAAAA==.',
Ca='Cain:BAAALgAECgkJDwAAAA==.Calvisi:BAAALgAECgcJDwAAAA==.Calvisichaos:BAABLgAECn9IAAIZAAkJ1xu9BAAuAgAZAAkJ1xu9BAAuAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgYJCgAAAA==.Catfor:BAAALgAECgEJAQAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Ci='Cindershade:BAEALgADCgYJBwABLgADCgkJCQAEAAAAAA==.Cissoid:BAAALgAECgEJAQABLgAFFAkJIQAaAKoiAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAABLgAECn8kAAISAAkJBg5YGQDeAAASAAkJBg5YGQDeAAAAAA==.',
Cr='Creation:BAAALgADCgYJBgAAAA==.Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAQJAQAAAA==.Cropala:BAABLgAECn8pAAISAAkJCBV5PgAMAgASAAkJCBV5PgAMAgAAAA==.Cruelcodex:BAAALgAECgEJAwAAAA==.',
Cy='Cyrridven:BAAALgADCgQJAgAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgYJCwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgUJDgAAAA==.',
De='Decapitator:BAAALgAECgUJCQAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn88AAMCAAkJYRgfBAA6AgACAAkJYRgfBAA6AgABAAkJAxJNDgCQAQAAAA==.Dellandre:BAABLgAECn8mAAIaAAkJ7Q09BgAEAQAaAAkJ7Q09BgAEAQABLgAECgkJNgAFANgKAA==.Delta:BAABLgAECn8eAAIHAAgJwwjcgQAcAQAHAAgJwwjcgQAcAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAHAFcWAA==.Demondozer:BAAALgAECgQJBQABLgAECgcJCwAEAAAAAA==.Demony:BAAALgAECgEJAgABLgAFFAEJAgAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8IAAIDAAMJeAi4iQCyAAADAAMJeAi4iQCyAAAuAAQKfxgAAgMACQlgCIdqAGcBAAMACQlgCIdqAGcBAAAA.Digichowder:BAACLgAFFH8SAAMQAAQJTyCAIAAwAQAQAAMJPSSAIAAwAQARAAEJhhSNQABIAAAuAAQKfycAAxEACQmxIz8EANoCABEACAkOIT8EANoCABAABglXHng5AGABAAAA.Dirtmerchant:BAAALgADCgkJEAAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Dk='Dkdozer:BAAALgAECgEJAQABLgAECgcJCwAEAAAAAA==.Dkwitch:BAAALgAECgEJAQAAAA==.',
Do='Doktaga:BAAALgAECgYJDwAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
['Dé']='Déspair:BAAALgAECgEJAQABLgAFFAQJBgAFAE8KAA==.',
Ea='Eama:BAAALgADCgUJBwAAAA==.',
Ed='Edin:BAAALgAFFAEJAQABLgAFFAYJIgALAD0VAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAACLgAFFH8IAAIZAAQJVxWYCgDxAAAZAAQJVxWYCgDxAAAuAAQKf0YAAxkACQllIiYBAO8CABkACQllIiYBAO8CAAMABQn6EfSMACABAAAA.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAACLgAFFH8PAAIbAAQJmxIuBQA7AQAbAAQJmxIuBQA7AQAuAAQKfx8AAxsACQnZFeUZANABABsACQmVDOUZANABABUACAkpFzQzAKABAAAA.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8fAAIMAAkJWRp3BQC9AgAMAAkJWRp3BQC9AgAAAA==.Endlol:BAACLgAFFH8KAAIcAAQJjxTQCgAdAQAcAAQJjxTQCgAdAQAuAAQKfy8AAxwACQkXIY0IAMYCABwACQkXIY0IAMYCAB0AAQlSHwRjAFMAAAAA.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8bAAMYAAkJSQ9GHwAGAgAYAAgJ7RBGHwAGAgAeAAEJywNFBQBKAAAuAAQKfyYAAhgACQmuIhsjAOYCABgACQmuIhsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoIagCSAQACAAcJ7RoIagCSAQAAAA==.',
Es='Esv:BAABLgAFFH8OAAIPAAQJbArkDwCaAAAPAAQJbArkDwCaAAABLgAFFAUJIgAYAHUYAA==.',
Ev='Evokryn:BAAALgAFFAEJAgAAAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgMJBAAAAA==.Fadedheart:BAAALgAECgYJDAABLgAFFAQJCAACAHgRAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAACLgAFFH8IAAICAAQJeBGAPADcAAACAAQJeBGAPADcAAAuAAQKfzcAAwIACQnwIF4YALQCAAIACQnwIF4YALQCABoAAQnVAW1uAA8AAAAA.Faeyir:BAACLgAFFH8TAAIYAAQJIg8qZAAaAQAYAAQJIg8qZAAaAQAuAAQKfyIAAhgACQnDHT9QAEYCABgACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMUAAkJqCDqDwDRAgAUAAkJqCDqDwDRAgAVAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIYAAMJwBg6ggDTAAAYAAMJwBg6ggDTAAAuAAQKfysAAhgACQmUIXsdAKsCABgACQmUIXsdAKsCAAAA.Fathertouchi:BAAALgAECgMJAwAAAA==.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwABLgAFFAQJCgAcAI8UAA==.Ferrilata:BAAALgADCgcJBgAAAA==.',
Fi='Fivebones:BAAALgAECgQJBAAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoofin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Frozenshade:BAAALgAECggJEgABLgAECgkJRgAbAKMdAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gabagool:BAAALgAECgQJBAAAAA==.Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gh='Ghosted:BAAALgAECgUJEAAAAA==.',
Gi='Gilberticus:BAABLgAECn8qAAMbAAkJDx3SAAClAgAbAAkJDx3SAAClAgAUAAUJRBY1rQDpAAAAAA==.Gishmou:BAABLgAECn8fAAIWAAkJwRh/JgAoAgAWAAkJwRh/JgAoAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAISAAgJWhfuUwDOAQASAAgJWhfuUwDOAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAMJAwABLgAFFAcJFAAIAOsVAA==.Grinch:BAAALgAECgMJBgAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8hAAMaAAkJqiLbAAAmAgAaAAkJqiLbAAAmAgACAAEJxQwLGQE8AAAuAAQKfx0AAhoACQkZJr0BAGcDABoACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAkJIQAaAKoiAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgMJAwAAAA==.Hollowheart:BAABLgAECn9HAAMWAAkJ2R2iAwAzAgAWAAkJ2R2iAwAzAgAXAAEJkyFJMwBjAAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyfur:BAAALgAECggJEwABLgAECgkJPAAKAN8eAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.Howle:BAAALgAECgQJBAAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgcJDAAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAFFAQJBgAFAE8KAA==.',
Ic='Ici:BAABLgAECn80AAMSAAkJ3QmDigBbAQASAAkJ3QmDigBbAQAKAAQJuA6AXQDAAAAAAA==.Icritdaily:BAAALgADCgYJCwAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAQJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Inarius:BAAALgAECgYJBgAAAA==.Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAABLgAECn8gAAIFAAkJKxDjEgCbAQAFAAkJKxDjEgCbAQABLgAECgkJKQAfADMNAA==.Iskothar:BAABLgAECn84AAIFAAkJrSGyAgD/AgAFAAkJrSGyAgD/AgAAAA==.',
It='Itsbob:BAAALgAECgQJAQAAAA==.',
Iv='Ivarboneless:BAABLgAECn8eAAIKAAgJFB9JEwB2AgAKAAgJFB9JEwB2AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzdk:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAQJAQAAAA==.Jatkal:BAAALgAFFAEJAgAAAA==.Jayreezy:BAAALgAECgQJBAAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMcAAkJygzYKwB2AQAcAAkJygzYKwB2AQAgAAgJFwnqMQBTAQAAAA==.',
Ke='Ketesh:BAACLgAFFH8PAAIhAAQJRhooBgArAQAhAAQJRhooBgArAQAuAAQKfzwAAiEACQnNIH8DAO0CACEACQnNIH8DAO0CAAEuAAUUBgkiAAsAPRUA.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgAECgYJEAABLgAECgkJOAAFAK0hAA==.',
Kl='Kleanse:BAAALgAFFAQJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQfAAYJ4Bc9NgA9AQAfAAYJ4Bc9NgA9AQAOAAYJZAqbcQABAQANAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8jAAILAAcJDQakEQBcAAALAAcJDQakEQBcAAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIaAAkJMBwzDwAYAgAaAAkJMBwzDwAYAgABLgAFFAcJFAAIAOsVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCwAAAA==.Langarde:BAABLgAECn8fAAIPAAkJCxDHFgCNAQAPAAkJCxDHFgCNAQAAAA==.Laoghaire:BAABLgAECn8YAAIIAAcJ+APYQgCrAAAIAAcJ+APYQgCrAAAAAA==.',
Le='Leonz:BAACLgAFFH8cAAIQAAkJLxmEAwBMAgAQAAkJLxmEAwBMAgAuAAQKfy4AAhAACQmaJCcFABADABAACQmaJCcFABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Lethapriest:BAEALgAECgEJAQABLgAFFAQJCgACAEASAA==.Letharanos:BAECLgAFFH8KAAMCAAQJQBLOjgDtAAACAAQJQBLOjgDtAAAaAAEJfQdjQwAoAAAuAAQKfycAAwIACQl0GQ9FAPMBAAIACQl0GQ9FAPMBABoAAQl7DuRgACgAAAAA.',
Li='Liraffemynn:BAACLgAFFH8bAAIiAAUJhxv+HQCAAQAiAAUJhxv+HQCAAQAuAAQKfz4AAiIACQmOI8UDAHsDACIACQmOI8UDAHsDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lohfall:BAAALgAECgMJAwABLgAFFAQJEAASAKsOAA==.Lonranir:BAABLgAECn8UAAQgAAYJig1mCwDqAAAgAAYJiQ1mCwDqAAAdAAQJmAqeUgCUAAAcAAIJKAHknQAMAAAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAkJIQAaAKoiAA==.Luckylucy:BAABLgAECn8XAAIdAAYJhhanLgBZAQAdAAYJhhanLgBZAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8aAAICAAYJ6BpwggB+AQACAAYJ6BpwggB+AQAAAA==.Magus:BAAALgADCgkJFgABLgAECgUJDgAEAAAAAA==.Maldran:BAABLgAECn8lAAIWAAcJjh3bKgAPAgAWAAcJjh3bKgAPAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8gAAIUAAcJVwqqgwA3AQAUAAcJVwqqgwA3AQAAAA==.Marien:BAABLgAECn8fAAIaAAkJHBl/DQAyAgAaAAkJHBl/DQAyAgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8UAAIYAAQJKCLaHQBaAQAYAAQJKCLaHQBaAQAuAAQKfyoAAhgACQntIQcdAK4CABgACQntIQcdAK4CAAAA.',
Me='Medraneiprst:BAAALgAECgMJAwAAAA==.Mehuman:BAABLgAECn8cAAISAAgJYhJ8jABYAQASAAgJYhJ8jABYAQAAAA==.Mehumanhuntr:BAAALgAECgUJBwAAAA==.Mehumanlock:BAABLgAECn8jAAIZAAkJ+xEWCgCkAQAZAAkJ+xEWCgCkAQAAAA==.Menedemnhntr:BAAALgAECgYJBgAAAA==.Merlinn:BAAALgADCgkJDAAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAABLgAECn8WAAIaAAYJQRZrBQAlAQAaAAYJQRZrBQAlAQAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgAECgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECgUJCgAAAA==.Mordaci:BAAALgADCgQJBQABLgAECggJHQASACIYAA==.Mordekrieg:BAABLgAFFH8GAAICAAMJUAt2rgDFAAACAAMJUAt2rgDFAAAAAA==.Mortstan:BAABLgAFFH8IAAIaAAUJYxiICwAVAQAaAAUJYxiICwAVAQAAAA==.',
Mu='Murderone:BAAALgAECggJDAAAAA==.Mutegen:BAAALgADCgUJBQABLgAFFAUJBQAjAHICAA==.',
My='Myash:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgcJCwAAAA==.Nailz:BAABLgAECn8fAAIHAAkJVxZCTwCYAQAHAAkJVxZCTwCYAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECgkJNgAGAHsOAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAFFAQJBgAFAE8KAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8mAAIhAAkJRhHNBwDuAAAhAAkJRhHNBwDuAAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAkJIAADADIXAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAkJIAADADIXAA==.Noahvoker:BAAALgAECggJEQABLgAFFAkJIAADADIXAA==.Noahwarlock:BAACLgAFFH8gAAQDAAkJMhfLIQDHAQADAAcJRhvLIQDHAQAZAAMJXxFuCwDkAAAkAAEJkSOAIABQAAAuAAQKfzIABAMACQmFJAEFAD8DAAMACAlsJAEFAD8DABkABAl0IkEaAHsBACQAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgYJJgAiANEjAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAABLgAECn8ZAAMSAAgJmQhCGQDeAAASAAgJpgZCGQDeAAAFAAQJhQgLOAB/AAAAAA==.',
Oh='Ohmylanta:BAAALgAFFAIJBAAAAA==.Ohmylantä:BAABLgAECn8dAAIYAAgJPg0FjABfAQAYAAgJPg0FjABfAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAISAAkJcRr+MQA4AgASAAkJcRr+MQA4AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgAECggJCAABLgAFFAkJHgAJAEwbAA==.Ormond:BAABLgAECn8hAAMKAAgJsRirKgC6AQAKAAgJsRirKgC6AQASAAUJPAWIHAGXAAAAAA==.Orochinchin:BAAALgAECgUJBgABLgAFFAkJIQAaAKoiAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8xAAQlAAkJpg2kDQB4AQAlAAkJpg2kDQB4AQAHAAQJqAqoHQB1AAAIAAMJRgawZQBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJDQABLgAECgcJCwAEAAAAAA==.Pallywacker:BAACLgAFFH8FAAIFAAIJtgkWEwBhAAAFAAIJtgkWEwBhAAAuAAQKfzQAAgUACQmIE5wUAIYBAAUACQmIE5wUAIYBAAAA.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Pelanris:BAAALgADCgMJAwAAAA==.Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAACLgAFFH8QAAIDAAQJSwxoIQD/AAADAAQJSwxoIQD/AAAuAAQKf1kAAwMACQnJHecTAK4CAAMACQnJHecTAK4CABkAAQnVEbM9ADYAAAAA.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQWAAkJqQzYRACbAQAWAAkJqQzYRACbAQAGAAgJHhG8NgB4AQAXAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgAECgQJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn82AAMGAAkJew4ZOQBSAQAGAAgJ/g8ZOQBSAQAWAAgJrxDTXABGAQAAAA==.Quelana:BAAALgADCgMJAwAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAMJBAABLgAFFAcJGgAMAF0gAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBj40ADnAAACAAUJDBj40ADnAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAFFAIJAgABLgAFFAQJCgAcAI8UAA==.Redemptor:BAAALgAECgUJBQAAAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygIuYAC1AAAKAAYJygIuYAC1AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAkJHQAGACMRAA==.Ripndip:BAAALgAFFAQJAQAAAA==.Riprock:BAAALgAFFAEJAQABLgAFFAQJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJMwADACkdAA==.',
Rn='Rn:BAACLgAFFH8FAAIRAAQJShiPGgATAQARAAQJShiPGgATAQAuAAQKfx4AAxEACQklIkEBAEYDABEACQkIIkEBAEYDABAABwkvIyQpABcCAAEuAAUUCAkiABEAgyQA.',
Ro='Rodeo:BAAALgAECgMJBgAAAA==.Roguehiro:BAABLgAECn8pAAIFAAgJxSEKBgCKAgAFAAgJxSEKBgCKAgAAAA==.Rooter:BAACLgAFFH8aAAMMAAcJXSCCBACVAgAMAAcJXSCCBACVAgALAAEJTBP4MQBAAAAuAAQKfz0AAwwACQkRJB8BAJ8DAAwACQkRJB8BAJ8DAAsABwnsGeklALABAAAA.Roronoaxd:BAAALgADCgMJAwAAAA==.Rosalynñ:BAABLgAECn8pAAIZAAgJMgpXFAAMAQAZAAgJMgpXFAAMAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAFFAEJAQABLgAFFAQJAQAEAAAAAA==.',
Sa='Sacea:BAAALgADCgUJBQAAAA==.Saelis:BAACLgAFFH8eAAIOAAYJeRh9CQCNAQAOAAYJeRh9CQCNAQAuAAQKfyAAAw4ACQkaIQEMAAADAA4ACQkaIQEMAAADAA0ABgnwGRYUAH8BAAAA.Salen:BAAALgAECgEJAQAAAA==.Samshara:BAAALgAECggJCwABLgAECgkJRgAbAKMdAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJDwABLgAFFAcJFAAIAOsVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAMJCAADAHgIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Seong:BAACLgAFFH8eAAIJAAkJTBv5BQA2AgAJAAkJTBv5BQA2AgAuAAQKfyIAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAkJHgAJAEwbAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAABLgAECn8WAAIYAAcJxgv4HADHAAAYAAcJxgv4HADHAAABLgAECgkJKQAfADMNAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAABLgAECn8VAAITAAgJ8Ap0AQASAQATAAgJ8Ap0AQASAQABLgAECgkJPAAKAN8eAA==.Shamynna:BAAALgAECgUJCQAAAA==.Sharpshotjak:BAABLgAFFH8PAAMUAAYJ2hPsDQCgAQAUAAYJ2hPsDQCgAQAVAAEJJgjLGwBEAAAAAA==.Sharreth:BAAALgAECgMJAwAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8zAAIUAAkJNhMjPgDpAQAUAAkJNhMjPgDpAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIQAAUJeRwxAwDEAQAQAAUJeRwxAwDEAQAuAAQKfxkAAhAACQmrHmYYAIgCABAACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8jAAQUAAgJriDEJAByAQAUAAYJAB7EJAByAQAbAAUJxSDkDABdAQAVAAUJcB3GEAAqAQAuAAQKfxsABBQACAk8IdMVAIkCABQABwnxIdMVAIkCABUABwlKIcoaAFMCABsAAwm3IXcxACABAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJDgABLgAFFAQJFgAYAMQaAA==.Skofung:BAAALgAECgEJAgAAAA==.',
Sl='Slagscar:BAAALgAFFAMJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIYAAYJ5gOr+gC0AAAYAAYJ5gOr+gC0AAAAAA==.Slootar:BAABLgAECn8UAAQOAAcJ5xuIJAAoAgAOAAcJ5xuIJAAoAgAfAAIJuxBfbABuAAANAAIJMAZVVwAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snizzy:BAAALgAECgYJBgAAAA==.Snqwflake:BAABLgAECn8VAAIiAAgJ7xb8FQAUAgAiAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAwAAAA==.Solthin:BAAALgAFFAQJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9GAAIbAAkJox1tCACXAgAbAAkJox1tCACXAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.Striker:BAAALgADCgIJAgAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgcJCAAAAA==.Takka:BAACLgAFFH8KAAIWAAYJcwZFEwAdAQAWAAYJcwZFEwAdAQAuAAQKfxsAAhYACAkdHR0YAIgCABYACAkdHR0YAIgCAAAA.Talden:BAACLgAFFH8QAAMSAAQJqw75IQDwAAASAAQJjQ35IQDwAAAFAAIJDxRpFgBHAAAuAAQKf0UAAxIACQkyHMkfAIkCABIACQkyHMkfAIkCAAUAAwnNEFFGAEwAAAAA.Talkamar:BAACLgAFFH8IAAImAAQJqBCCDQC5AAAmAAQJqBCCDQC5AAAuAAQKfyMAAiYACQn7EeoeALYBACYACQn7EeoeALYBAAAA.Taylorswift:BAABLgAECn83AAIYAAkJ8xivLABmAgAYAAkJ8xivLABmAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn82AAIFAAkJ2ApYGwA9AQAFAAkJ2ApYGwA9AQAAAA==.Thenard:BAABLgAECn8jAAIUAAgJPBPrVgCfAQAUAAgJPBPrVgCfAQAAAA==.Therealcafna:BAAALgAECgQJBQAAAA==.Thukunaenhan:BAAALgAECgQJBQABLgAFFAQJFgAYAMQaAA==.Thukunamage:BAACLgAFFH8WAAIYAAQJxBotMwDgAAAYAAQJxBotMwDgAAAuAAQKfyoAAhgACQmyIIchAJcCABgACQmyIIchAJcCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Ticket:BAAALgADCgkJCQAAAA==.Tili:BAAALgADCgkJEwAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.Tirra:BAAALgADCgkJCQABLgAFFAYJIgALAD0VAA==.',
To='Tomislav:BAABLgAECn8rAAQDAAkJFx3fKwAqAgADAAcJxhnfKwAqAgAZAAQJCB8OBgC+AAAkAAEJmBzFCwBVAAAAAA==.Tomuchmakeup:BAAALgAECgMJAwAAAA==.Touritos:BAABLgAECn8eAAIGAAkJdRGbKgCdAQAGAAkJdRGbKgCdAQAAAA==.',
Tr='Trimblestein:BAAALgAECgcJDQAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAQJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMjAAgJ6RbMEwB4AgAjAAgJ6RbMEwB4AgAnAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAQJAQAAAA==.Tyler:BAACLgAFFH8LAAIHAAQJfhXYDwBPAQAHAAQJfhXYDwBPAQAuAAQKfxsAAgcACAkOHTgcAKkCAAcACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8cAAIfAAcJ/AkRDQCqAAAfAAcJ/AkRDQCqAAAAAA==.',
Um='Umariel:BAAALgAFFAQJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBwAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAACLgAFFH8GAAIFAAQJTwo2DgCaAAAFAAQJTwo2DgCaAAAuAAQKfzQAAgUACQm3DxYXAGgBAAUACQm3DxYXAGgBAAAA.Vancliffe:BAAALgAECgQJBAABLgAFFAcJFAAIAOsVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Violethunts:BAAALgADCgQJBAAAAA==.Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8iAAIYAAUJdRh3LQD7AAAYAAUJdRh3LQD7AAAuAAQKfy4AAhgACAl8GzlIAAICABgACAl8GzlIAAICAAAA.Vsesosorry:BAABLgAFFH8VAAIWAAQJZxS2NgAHAQAWAAQJZxS2NgAHAQABLgAFFAUJIgAYAHUYAA==.Vsè:BAAALgAFFAIJAgABLgAFFAUJIgAYAHUYAA==.',
Vy='Vyke:BAAALgAECgkJEgABLgAFFAkJHgAJAEwbAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Walkens:BAAALgAECgEJAQAAAA==.Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJBgAAAA==.Wardozer:BAAALgAECgcJCwAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAkJIQAaAKoiAA==.',
Wo='Worgenkrantz:BAABLgAECn8pAAMfAAkJMw3RKQCFAQAfAAkJMw3RKQCFAQAOAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8UAAMIAAcJ6xV7EgAQAQAIAAYJOxZ7EgAQAQAHAAIJKQx9ewCHAAAuAAQKfzQAAwgACAniI9kOADgCAAgACAntH9kOADgCACUABAm0IZ8CACoBAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAABLgAECn8kAAIaAAgJ1hhmAgD0AQAaAAgJ1hhmAgD0AQABLgAECgkJOAAFAK0hAA==.',
Xo='Xolòtl:BAABLgAECn8tAAIPAAkJVxo0AQBfAgAPAAkJVxo0AQBfAgABLgAFFAcJFAAIAOsVAA==.Xoss:BAAALgAFFAQJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAYJCAAiABcGAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAgAAAA==.Yourleige:BAAALgAECgEJAQAAAA==.Yourportsir:BAAALgADCgIJAgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIcAAkJlA2BJwCSAQAcAAkJlA2BJwCSAQAAAA==.Zapix:BAAALgAECgEJAQABLgAECgMJBwAEAAAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIYAAgJcBVpaQADAgAYAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8dAAQoAAgJkheiDQAAAgAoAAcJdxiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHQAoAJIXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIHAAgJORqFMAA5AgAHAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQSAAUJQBa4ygD6AAASAAQJxhi4ygD6AAAKAAMJyRCQcgCxAAAFAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECggJEAAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgcJEAAAAA==.',
['Èo']='Èomer:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgMJBAAAAA==.',
['ßa']='ßaroness:BAAALgAECgEJAQAAAA==.',
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
