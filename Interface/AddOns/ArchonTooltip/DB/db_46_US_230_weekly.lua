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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Brewmaster','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Druid-Restoration','Warrior-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Druid-Balance','Hunter-Survival','Priest-Shadow','Priest-Holy','Mage-Fire','Priest-Discipline','Monk-Windwalker','Druid-Guardian','Monk-Mistweaver','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Vengeance','Mage-Arcane','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abaddon:BAABLgAECn8tAAMBAAkJTB8qBwAoAgABAAgJ6R0qBwAoAgACAAgJrBzyRQDwAQAAAA==.Abessedge:BAAALgAECggJDQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8zAAIDAAkJKR0HCgAuAwADAAkJKR0HCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJMwADACkdAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.Aelenia:BAAALgADCggJCAAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alkaios:BAAALgAECgcJDQABLgAFFAQJBgAFAE8KAA==.Almighty:BAAALgAECgUJBQAAAA==.Alor:BAAALgAECgIJBAABLgAECgkJNgAGAHsOAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMHAAgJDhWRVgCDAQAHAAgJDhWRVgCDAQAIAAEJawx8cAAvAAABLgAFFAkJHwAGAGARAA==.Amalthaea:BAAALgAECgcJEwABLgAECgkJLwAJAOoWAA==.Amnoon:BAABLgAECn82AAIKAAkJ+BfnEwBwAgAKAAkJ+BfnEwBwAgAAAA==.Amri:BAACLgAFFH8qAAMLAAcJVQqfCgAHAQALAAYJZwafCgAHAQAMAAYJgBKsMAD/AAAuAAQKfy8AAwwACQnQGtsCALgBAAwACQnQGtsCALgBAAsABglADVUiAN0AAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgQJAgAAAA==.',
Aq='Aquas:BAAALgAECgUJCwAAAA==.',
Ar='Ardor:BAEALgADCgkJDAAAAA==.Ardrhys:BAAALgAFFAQJBAAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAFFAEJAQABLgAFFAcJFAAIAOsVAA==.',
As='Assasin:BAAALgAECgYJBgAAAA==.Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAABLgAECn8YAAINAAkJ8xY2DgDSAQANAAkJ8xY2DgDSAQAAAA==.',
At='Atreus:BAABLgAECn8nAAMIAAkJ7BxcDgA/AgAIAAkJ7BxcDgA/AgAHAAEJVAswIAEqAAABLgAFFAEJAQAEAAAAAA==.Atzalan:BAABLgAECn8UAAIOAAYJpwnpcwD7AAAOAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn80AAQPAAkJfhBxGgBmAQAPAAkJfhBxGgBmAQAQAAUJ1g5wEQDEAAARAAEJ+wnERAAvAAAAAA==.',
Az='Azorah:BAAALgAECgcJCAAAAA==.Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Badhabit:BAAALgADCgYJBgAAAA==.Baku:BAAALgAECgYJBgABLgAFFAcJFAAIAOsVAA==.Baldyguy:BAAALgAECgUJDQAAAA==.Balm:BAACLgAFFH8HAAIOAAQJOwb2IABwAAAOAAQJOwb2IABwAAAuAAQKfzEAAg4ACQkIGr4hADoCAA4ACQkIGr4hADoCAAAA.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgMJAwABLgAFFAEJAQAEAAAAAA==.Beautzibub:BAAALgADCgkJEwAAAA==.Behindyou:BAAALgAECggJDgABLgAECgkJLAASALoXAA==.Bermin:BAAALgAECgEJAQAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bielebog:BAAALgADCgMJAwAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BTEXQCvAQACAAgJ/BTEXQCvAQAAAA==.Blackmouser:BAAALgAECgQJBAAAAA==.Blemish:BAAALgAECgEJAQABLgAFFAQJBwAOADsGAA==.Bloodpac:BAAALgAECgQJCAAAAA==.',
Bm='Bmo:BAABLgAECn8VAAISAAcJZSB1SAAJAgASAAcJZSB1SAAJAgAAAA==.',
Bo='Boadica:BAAALgADCgEJAQAAAA==.Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMSAAIJOQwQqgBtAAASAAIJUAUQqgBtAAAFAAIJOQwOCAA2AAAuAAQKfy8AAwUACQnYI7MCAP8CAAUACQnYI7MCAP8CABIAAwnyFuDiANoAAAAA.Bolvar:BAAALgAECgQJBAAAAA==.Bonedmuch:BAAALgAECggJDgABLgAECgkJLwAJAOoWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8aAAITAAcJ6wa1EwDRAAATAAcJ6wa1EwDRAAAAAA==.Breadria:BAAALgAECgEJAwABLgAFFAMJCgAUAOAMAA==.Bremitin:BAAALgAFFAIJAgABLgAFFAQJBgAFAE8KAA==.Bremitus:BAAALgAECgIJAwABLgAFFAQJBgAFAE8KAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQABLgAFFAEJAwAEAAAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8bAAIHAAgJ5B+wNwAXAgAHAAgJ5B+wNwAXAgAAAA==.Brud:BAABLgAFFH8GAAIRAAMJ3RDADgDdAAARAAMJ3RDADgDdAAAAAA==.Brunstan:BAACLgAFFH8TAAIVAAUJfh8SEgBDAQAVAAUJfh8SEgBDAQAuAAQKfxkAAhUACQnjIL4CALwCABUACQnjIL4CALwCAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.Bullet:BAAALgAECgYJDwAAAA==.',
By='Byakugan:BAACLgAFFH8fAAMGAAkJYBF1BQCDAQAGAAcJ3xB1BQCDAQAWAAMJEgl+TADBAAAuAAQKfyAABAYACQktH5oPAK8CAAYACQktH5oPAK8CABcAAQm+F78pAEEAABYAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8kAAIYAAkJGQkzeACJAQAYAAkJGQkzeACJAQAAAA==.',
Ca='Cain:BAAALgAECgkJEQAAAA==.Calvisi:BAAALgAECgcJDwAAAA==.Calvisichaos:BAABLgAECn9IAAIZAAkJ1xu9BAAuAgAZAAkJ1xu9BAAuAgAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgYJCgAAAA==.Catfor:BAAALgAECgYJBwAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Ci='Cindershade:BAEALgADCgYJBwABLgADCgkJDAAEAAAAAA==.Cissoid:BAAALgAECgEJAQABLgAFFAkJIwAaAKoiAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAABLgAECn8lAAISAAkJtA4jIADhAAASAAkJtA4jIADhAAAAAA==.',
Cr='Creation:BAAALgADCgYJBgAAAA==.Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAQJAQAAAA==.Cropala:BAABLgAECn8sAAISAAkJuhd5PgAMAgASAAkJuhd5PgAMAgAAAA==.Cruelcodex:BAAALgAECgEJAwAAAA==.Crysania:BAAALgAECgYJBgABLgAECgkJKQAbADMNAA==.',
Cy='Cyrridven:BAAALgADCgQJAgAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgkJCwAAAA==.Darkwingduck:BAAALgAECgYJCwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgUJDgABLgAECgYJBgAEAAAAAA==.',
De='Decapitator:BAAALgAECgcJDQAAAA==.Dednburied:BAAALgAECgIJAgAAAA==.Deleto:BAABLgAECn88AAMCAAkJYRiABQAxAgACAAkJYRiABQAxAgABAAkJAxJNDgCQAQAAAA==.Dellandre:BAABLgAECn8mAAIaAAkJ7Q1zCAD+AAAaAAkJ7Q1zCAD+AAABLgAECgkJNgAFANgKAA==.Delta:BAABLgAECn8eAAIHAAgJwwjcgQAcAQAHAAgJwwjcgQAcAQAAAA==.Delti:BAAALgAECgUJBgABLgAECgkJHwAHAFcWAA==.Demondozer:BAAALgAECgQJBQABLgAECgcJCwAEAAAAAA==.Demony:BAAALgAECgEJAgABLgAFFAEJAwAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAACLgAFFH8IAAIDAAMJeAi4iQCyAAADAAMJeAi4iQCyAAAuAAQKfxgAAgMACQlgCIdqAGcBAAMACQlgCIdqAGcBAAAA.Digichowder:BAACLgAFFH8SAAMQAAQJTyCAIAAwAQAQAAMJPSSAIAAwAQARAAEJhhSNQABIAAAuAAQKfycAAxEACQmxIz8EANoCABEACAkOIT8EANoCABAABglXHng5AGABAAAA.Dirtmerchant:BAAALgADCgkJEwAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Dk='Dkdozer:BAAALgAECgMJAwABLgAECgcJCwAEAAAAAA==.Dkwitch:BAAALgAECgEJAQAAAA==.',
Do='Doktaga:BAAALgAECgYJDwAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJDAAAAA==.',
['Dé']='Déspair:BAAALgAECgEJAQABLgAFFAQJBgAFAE8KAA==.',
Ea='Eama:BAAALgADCgUJBwAAAA==.',
Ed='Edin:BAAALgAFFAEJAQABLgAFFAcJKgALAFUKAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAACLgAFFH8IAAIZAAQJVxWYCgDxAAAZAAQJVxWYCgDxAAAuAAQKf0YAAxkACQllIiYBAO8CABkACQllIiYBAO8CAAMABQn6EfSMACABAAAA.Eldhe:BAAALgAECgYJDwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elessar:BAEALgADCgUJBQABLgADCgkJDAAEAAAAAA==.Elistrae:BAACLgAFFH8RAAIcAAUJRRYFBgBCAQAcAAUJRRYFBgBCAQAuAAQKfx8AAxwACQnZFeUZANABABwACQmVDOUZANABABUACAkpFzQzAKABAAAA.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8iAAILAAkJKht3BQC9AgALAAkJKht3BQC9AgAAAA==.Endlol:BAACLgAFFH8KAAIdAAQJjxRzDgAKAQAdAAQJjxRzDgAKAQAuAAQKfy8AAx0ACQkXIY0IAMYCAB0ACQkXIY0IAMYCAB4AAQlSHwRjAFMAAAAA.',
Er='Eredaria:BAAALgAFFAEJAQAAAA==.Ereshkigal:BAAALgAECgMJAwAAAA==.Ergo:BAACLgAFFH8dAAMYAAkJzRBGHwAGAgAYAAgJqBJGHwAGAgAfAAEJ0AN4BgBHAAAuAAQKfygAAxgACQmuIhsjAOYCABgACQmuIhsjAOYCAB8AAgm9F8YDAJAAAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoIagCSAQACAAcJ7RoIagCSAQAAAA==.',
Es='Esv:BAABLgAFFH8OAAIPAAQJbArEEgCOAAAPAAQJbArEEgCOAAABLgAFFAUJIgAYAHUYAA==.',
Ev='Evokryn:BAAALgAFFAEJAwAAAA==.',
Ex='Excido:BAAALgAECgEJAgAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgMJBAAAAA==.Fadedheart:BAAALgAECgYJDAABLgAFFAQJCAACAHgRAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAACLgAFFH8IAAICAAQJeBHkRQDQAAACAAQJeBHkRQDQAAAuAAQKfzcAAwIACQnwIF4YALQCAAIACQnwIF4YALQCABoAAQnVAW1uAA8AAAAA.Faeyir:BAACLgAFFH8TAAIYAAQJIg8qZAAaAQAYAAQJIg8qZAAaAQAuAAQKfyIAAhgACQnDHT9QAEYCABgACQnDHT9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMUAAkJqCDqDwDRAgAUAAkJqCDqDwDRAgAVAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIYAAMJwBg6ggDTAAAYAAMJwBg6ggDTAAAuAAQKfysAAhgACQmUIXsdAKsCABgACQmUIXsdAKsCAAAA.Fathertouchi:BAAALgAECgMJAwAAAA==.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwABLgAFFAQJCgAdAI8UAA==.Ferrilata:BAAALgADCgcJBgAAAA==.',
Fi='Fidena:BAAALgAECgEJAQAAAA==.Fivebones:BAAALgAECgQJBAAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.Flogareth:BAAALgADCgkJCQAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoofin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgMJBAABLgAECgIJAgAEAAAAAA==.Frostybreath:BAAALgAECgIJAgAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Frostydh:BAAALgAECgMJAwABLgAECgIJAgAEAAAAAA==.Frostytotems:BAAALgAECgQJBgAAAA==.Frozenshade:BAAALgAECggJEgABLgAECgkJRgAcAKMdAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gabagool:BAAALgAECgQJBwAAAA==.Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gh='Ghosted:BAAALgAFFAEJAgAAAA==.',
Gi='Gilberticus:BAABLgAECn8qAAMcAAkJDx0mAQCDAgAcAAkJDx0mAQCDAgAUAAUJRBY1rQDpAAAAAA==.Gishmou:BAABLgAECn8fAAIWAAkJwRh/JgAoAgAWAAkJwRh/JgAoAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAISAAgJWhfuUwDOAQASAAgJWhfuUwDOAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJCAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAFFAMJAwABLgAFFAcJFAAIAOsVAA==.Grinch:BAAALgAECgMJBwAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8jAAMaAAkJqiLbAAAmAgAaAAkJqiLbAAAmAgACAAEJxQwLGQE8AAAuAAQKfx0AAhoACQkZJr0BAGcDABoACQkZJr0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAkJIwAaAKoiAA==.Harleyswar:BAAALgADCgEJAQAAAA==.Havocss:BAAALgAECgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgUJCAAAAA==.Hollowheart:BAABLgAECn9KAAMWAAkJ2R0KAwCXAgAWAAkJ2R0KAwCXAgAXAAEJkyFJMwBjAAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyfur:BAABLgAECn8ZAAQgAAgJPg9lBwCCAQAgAAgJUw5lBwCCAQAdAAYJSBCcDADzAAAeAAEJWxTtGwA7AAABLgAECgkJPAAKAN8eAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hotsausage:BAAALgAECgMJAwAAAA==.Hoved:BAAALgADCgEJAQAAAA==.Howle:BAAALgAECgQJBAAAAA==.',
Hu='Huang:BAAALgAECgMJAwAAAA==.',
Hy='Hylanna:BAAALgAECgcJDAAAAA==.Hyorinmaru:BAAALgAFFAEJAgAAAA==.',
['Hó']='Hónor:BAAALgAECgEJAQABLgAFFAQJBgAFAE8KAA==.',
Ic='Ici:BAABLgAECn80AAMSAAkJ3QmDigBbAQASAAkJ3QmDigBbAQAKAAQJuA6AXQDAAAAAAA==.Icritdaily:BAAALgADCgYJCwAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAQJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Inarius:BAAALgAECgYJBgAAAA==.Intensifies:BAAALgAECgcJEgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAABLgAECn8kAAIFAAkJERKyBABdAQAFAAkJERKyBABdAQABLgAECgkJKQAbADMNAA==.Iskothar:BAABLgAECn8+AAIFAAkJ6iGyAgD/AgAFAAkJ6iGyAgD/AgAAAA==.',
It='Itsbob:BAAALgAECgQJAQAAAA==.',
Iv='Ivarboneless:BAABLgAECn8fAAIKAAkJgx1JEwB2AgAKAAkJgx1JEwB2AgAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzdk:BAAALgAECgkJDgAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAQJAQAAAA==.Jatkal:BAABLgAECn8ZAAMJAAkJFxA1BAA+AQAhAAkJzw3jJwB5AQAJAAgJ7g81BAA+AQAAAA==.Jayreezy:BAAALgAECgQJBAAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Jy='Jynxxed:BAAALgAECgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAABLgAECn8UAAMdAAkJygzYKwB2AQAdAAkJygzYKwB2AQAgAAgJFwnqMQBTAQAAAA==.',
Ke='Ketesh:BAACLgAFFH8SAAIiAAQJGB0cBgBDAQAiAAQJGB0cBgBDAQAuAAQKfzwAAiIACQnNIH8DAO0CACIACQnNIH8DAO0CAAEuAAUUBwkqAAsAVQoA.',
Ki='Kilman:BAAALgADCgYJBgAAAA==.Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgAECgYJEAABLgAECgkJPgAFAOohAA==.',
Kl='Kleanse:BAAALgAFFAQJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQbAAYJ4Bc9NgA9AQAbAAYJ4Bc9NgA9AQAOAAYJZAqbcQABAQANAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8lAAIMAAkJCAiYCwC3AAAMAAkJCAiYCwC3AAAAAA==.',
Kr='Krej:BAABLgAECn8XAAIaAAkJMBwzDwAYAgAaAAkJMBwzDwAYAgABLgAFFAcJFAAIAOsVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Landrey:BAAALgADCgkJCwAAAA==.Langarde:BAABLgAECn8fAAIPAAkJCxDHFgCNAQAPAAkJCxDHFgCNAQAAAA==.Laoghaire:BAABLgAECn8YAAIIAAcJ+APYQgCrAAAIAAcJ+APYQgCrAAAAAA==.',
Le='Leonz:BAACLgAFFH8eAAIQAAkJdhuEAwBMAgAQAAkJdhuEAwBMAgAuAAQKfy4AAhAACQmaJCcFABADABAACQmaJCcFABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Lethapriest:BAEALgAECgEJAQABLgAFFAQJCgACAEASAA==.Letharanos:BAECLgAFFH8KAAMCAAQJQBLOjgDtAAACAAQJQBLOjgDtAAAaAAEJfQdjQwAoAAAuAAQKfycAAwIACQl0GQ9FAPMBAAIACQl0GQ9FAPMBABoAAQl7DuRgACgAAAAA.',
Li='Liraffemynn:BAACLgAFFH8bAAIjAAUJhxv+HQCAAQAjAAUJhxv+HQCAAQAuAAQKfz4AAiMACQmOI8UDAHsDACMACQmOI8UDAHsDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lohfall:BAAALgAECgMJAwABLgAFFAQJEwASAGwPAA==.Lonranir:BAABLgAECn8UAAQgAAYJig0nDwDmAAAgAAYJiQ0nDwDmAAAeAAQJmAqeUgCUAAAdAAIJKAHknQAMAAAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAkJIwAaAKoiAA==.Luckylucy:BAABLgAECn8XAAIeAAYJhhanLgBZAQAeAAYJhhanLgBZAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8aAAICAAYJ6BpwggB+AQACAAYJ6BpwggB+AQAAAA==.Magus:BAAALgAECgYJBgAAAA==.Maldran:BAABLgAECn8lAAIWAAcJjh3bKgAPAgAWAAcJjh3bKgAPAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Mallgrab:BAAALgAECgIJAgAAAA==.Manderpants:BAABLgAECn8gAAIUAAcJVwqqgwA3AQAUAAcJVwqqgwA3AQAAAA==.Marien:BAABLgAECn8fAAIaAAkJHBl/DQAyAgAaAAkJHBl/DQAyAgAAAA==.Markaset:BAAALgADCgEJAQAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgAECgcJBwAAAA==.',
Mb='Mbbin:BAACLgAFFH8UAAIYAAQJKCLGLgARAQAYAAQJKCLGLgARAQAuAAQKfzMAAhgACQl/JSEBAGQDABgACQl/JSEBAGQDAAAA.',
Me='Medraneiprst:BAAALgAECgMJAwAAAA==.Mehuman:BAABLgAECn8dAAISAAkJ7RLaIgDRAAASAAkJ7RLaIgDRAAAAAA==.Mehumanhuntr:BAAALgAECgUJBwAAAA==.Mehumanlock:BAABLgAECn8jAAIZAAkJ+xEWCgCkAQAZAAkJ+xEWCgCkAQAAAA==.Melgibson:BAAALgAECgMJAwAAAA==.Menedemnhntr:BAAALgAECgYJBgAAAA==.Merlinn:BAAALgADCgkJDAAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAABLgAECn8WAAIaAAYJQRZdBwAfAQAaAAYJQRZdBwAfAQAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgcJDAAAAA==.Mistyblue:BAAALgAECgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgAECggJDQAAAA==.Mordaci:BAAALgADCgQJBQABLgAECggJHQASACIYAA==.Mordekrieg:BAABLgAFFH8GAAICAAMJUAt2rgDFAAACAAMJUAt2rgDFAAAAAA==.Mortstan:BAABLgAFFH8IAAIaAAUJYxiADgALAQAaAAUJYxiADgALAQAAAA==.',
Mu='Murderone:BAAALgAECggJDQAAAA==.Mutegen:BAAALgADCgUJBQABLgAFFAUJBQAkAHICAA==.',
My='Myash:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgYJBwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgcJCwAAAA==.Nailz:BAABLgAECn8fAAIHAAkJVxZCTwCYAQAHAAkJVxZCTwCYAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECgkJNgAGAHsOAA==.Nardog:BAAALgAECgEJAQAAAA==.Narie:BAAALgAECggJCQAAAA==.Nasaug:BAAALgAECgUJCwABLgAFFAQJBgAFAE8KAA==.Nazzle:BAAALgAECgEJAQAAAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAABLgAECn8nAAIiAAkJghGiCQDvAAAiAAkJghGiCQDvAAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAkJIQADAKgYAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAkJIQADAKgYAA==.Noahvoker:BAAALgAECggJEQABLgAFFAkJIQADAKgYAA==.Noahwarlock:BAACLgAFFH8hAAQDAAkJqBjLIQDHAQADAAcJOh3LIQDHAQAZAAMJXxFuCwDkAAAlAAEJkSOAIABQAAAuAAQKfzIABAMACQmFJAEFAD8DAAMACAlsJAEFAD8DABkABAl0IkEaAHsBACUAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgcJKQAjAFEiAA==.Nook:BAAALgADCgUJBgAAAA==.Nowere:BAAALgADCgcJBwAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAABLgAECn8ZAAMSAAgJmQg3IwDPAAASAAgJpgY3IwDPAAAFAAQJhQgLOAB/AAAAAA==.',
Oh='Ohmylanta:BAAALgAFFAIJBAAAAA==.Ohmylantä:BAABLgAECn8dAAIYAAgJPg0FjABfAQAYAAgJPg0FjABfAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAISAAkJcRr+MQA4AgASAAkJcRr+MQA4AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgAECggJCAABLgAFFAkJIAAJAF0dAA==.Ormond:BAABLgAECn8iAAMKAAkJfxmrKgC6AQAKAAgJsRirKgC6AQASAAYJtQeIHAGXAAAAAA==.Orochinchin:BAAALgAECgUJBgABLgAFFAkJIwAaAKoiAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8xAAQmAAkJpg2kDQB4AQAmAAkJpg2kDQB4AQAHAAQJqAo+JQBxAAAIAAMJRgawZQBCAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgYJEwABLgAECgcJCwAEAAAAAA==.Pallywacker:BAACLgAFFH8FAAIFAAIJtgkWEwBhAAAFAAIJtgkWEwBhAAAuAAQKfzQAAgUACQmIE5wUAIYBAAUACQmIE5wUAIYBAAAA.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Pelanris:BAAALgADCgkJCgAAAA==.Percymorris:BAAALgADCgYJBwAAAA==.Peythilly:BAAALgAECgQJBAAAAA==.',
Pi='Pigishdog:BAACLgAFFH8TAAIDAAQJZQw1KQDmAAADAAQJZQw1KQDmAAAuAAQKf1oAAwMACQneHecTAK4CAAMACQneHecTAK4CABkAAQnVEbM9ADYAAAAA.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQWAAkJqQzYRACbAQAWAAkJqQzYRACbAQAGAAgJHhG8NgB4AQAXAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgAECgQJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn82AAMGAAkJew4ZOQBSAQAGAAgJ/g8ZOQBSAQAWAAgJrxDTXABGAQAAAA==.Quelana:BAAALgADCgMJAwAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAMJBAABLgAFFAgJGwALALgdAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBj40ADnAAACAAUJDBj40ADnAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='React:BAAALgAFFAIJAgABLgAFFAQJCgAdAI8UAA==.Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygIuYAC1AAAKAAYJygIuYAC1AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAkJHwAGAGARAA==.Ripndip:BAAALgAFFAQJAQAAAA==.Riprock:BAAALgAFFAEJAQABLgAFFAQJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJMwADACkdAA==.',
Rn='Rn:BAACLgAFFH8FAAIRAAQJShiPGgATAQARAAQJShiPGgATAQAuAAQKfx4AAxEACQklIkEBAEYDABEACQkIIkEBAEYDABAABwkvIyQpABcCAAEuAAUUBQkGABEAlRsA.',
Ro='Rodeo:BAAALgAECgMJBgAAAA==.Roguehiro:BAABLgAECn8sAAIFAAkJ/yIKBgCKAgAFAAkJ/yIKBgCKAgAAAA==.Rooter:BAACLgAFFH8bAAMLAAgJuB2CBACVAgALAAgJuB2CBACVAgAMAAEJTBMyOQA1AAAuAAQKfz0AAwsACQkRJB8BAJ8DAAsACQkRJB8BAJ8DAAwABwnsGeklALABAAAA.Roronoaxd:BAAALgADCgMJAwAAAA==.Rosalynñ:BAABLgAECn8pAAIZAAgJMgpXFAAMAQAZAAgJMgpXFAAMAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAFFAEJAQABLgAFFAQJAQAEAAAAAA==.',
Sa='Sacea:BAAALgADCgUJBQAAAA==.Saelis:BAACLgAFFH8eAAIOAAYJeRiNCwB/AQAOAAYJeRiNCwB/AQAuAAQKfyAAAw4ACQkaIQEMAAADAA4ACQkaIQEMAAADAA0ABgnwGRYUAH8BAAAA.Salen:BAAALgAECgEJAQAAAA==.Samshara:BAAALgAECggJCwABLgAECgkJRgAcAKMdAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgcJDwABLgAFFAcJFAAIAOsVAA==.Scrounge:BAAALgAFFAEJAQABLgAFFAMJCAADAHgIAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Seong:BAACLgAFFH8gAAIJAAkJXR35BQA2AgAJAAkJXR35BQA2AgAuAAQKfyIAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAkJIAAJAF0dAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAABLgAECn8cAAIYAAgJzQ0uGQAQAQAYAAgJzQ0uGQAQAQABLgAECgkJKQAbADMNAA==.',
Sh='Shadowdivine:BAAALgAECgEJAQABLgAECggJFgACABQZAA==.Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAABLgAECn8VAAITAAgJ8ArwAQAZAQATAAgJ8ArwAQAZAQABLgAECgkJPAAKAN8eAA==.Shamynna:BAAALgAECggJDAAAAA==.Sharpshotjak:BAABLgAFFH8PAAMUAAYJ2hMVEwCOAQAUAAYJ2hMVEwCOAQAVAAEJJgiwHQBEAAAAAA==.Sharreth:BAAALgAECgMJAwAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8zAAIUAAkJNhMjPgDpAQAUAAkJNhMjPgDpAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shizukura:BAAALgADCgEJAQAAAA==.Shockawar:BAACLgAFFH8WAAIQAAUJeRwxAwDEAQAQAAUJeRwxAwDEAQAuAAQKfxkAAhAACQmrHmYYAIgCABAACQmrHmYYAIgCAAAA.Shodam:BAAALgAECgUJAwAAAA==.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8jAAQUAAgJriDEJAByAQAUAAYJAB7EJAByAQAcAAUJxSDkDABdAQAVAAUJcB3GEAAqAQAuAAQKfxsABBQACAk8IdMVAIkCABQABwnxIdMVAIkCABUABwlKIcoaAFMCABwAAwm3IXcxACABAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skibidi:BAAALgAECgcJDgABLgAFFAQJGAAnAMQaAA==.Sklormp:BAAALgAECgEJAgAAAA==.Skofung:BAAALgAECgEJAgAAAA==.',
Sl='Slagscar:BAAALgAFFAMJAQAAAA==.Slaughterhse:BAABLgAECn8XAAIYAAYJ5gOr+gC0AAAYAAYJ5gOr+gC0AAAAAA==.Slootar:BAABLgAECn8UAAQOAAcJ5xuIJAAoAgAOAAcJ5xuIJAAoAgAbAAIJuxBfbABuAAANAAIJMAZVVwAsAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snizzy:BAAALgAECgYJBgAAAA==.Snqwflake:BAABLgAECn8VAAIjAAgJ7xb8FQAUAgAjAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAwAAAA==.Solthin:BAAALgAFFAQJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn9GAAIcAAkJox1tCACXAgAcAAkJox1tCACXAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.Stormshadow:BAAALgAECgEJAQAAAA==.Striker:BAAALgADCgQJAgAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgcJCAAAAA==.Takka:BAACLgAFFH8KAAIWAAYJcwY+GgD7AAAWAAYJcwY+GgD7AAAuAAQKfx0AAhYACQkPGx0YAIgCABYACQkPGx0YAIgCAAAA.Talden:BAACLgAFFH8TAAMSAAQJbA+zJgDvAAASAAQJTg6zJgDvAAAFAAIJDxRpFgBHAAAuAAQKf0UAAxIACQkyHMkfAIkCABIACQkyHMkfAIkCAAUAAwnNEFFGAEwAAAAA.Talkamar:BAACLgAFFH8IAAIhAAQJqBCvEACzAAAhAAQJqBCvEACzAAAuAAQKfyMAAiEACQn7EeoeALYBACEACQn7EeoeALYBAAAA.Tanía:BAAALgAECgMJAwAAAA==.Taylorswift:BAABLgAECn83AAIYAAkJ8xivLABmAgAYAAkJ8xivLABmAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn82AAIFAAkJ2ApYGwA9AQAFAAkJ2ApYGwA9AQAAAA==.Thenard:BAABLgAECn8jAAIUAAgJPBPrVgCfAQAUAAgJPBPrVgCfAQAAAA==.Therealcafna:BAAALgAECgQJBQAAAA==.Thukunaenhan:BAAALgAECgQJBQABLgAFFAQJGAAnAMQaAA==.Thukunamage:BAACLgAFFH8YAAMnAAQJxBrUAwCVAAAYAAQJxBowOgDcAAAnAAIJaBjUAwCVAAAuAAQKfyoAAhgACQmyIIchAJcCABgACQmyIIchAJcCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Ticket:BAAALgADCgkJDAAAAA==.Tili:BAAALgADCgkJGgAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.Tirra:BAAALgADCgkJCQABLgAFFAcJKgALAFUKAA==.',
To='Tomislav:BAABLgAECn8rAAQDAAkJFx3fKwAqAgADAAcJxhnfKwAqAgAZAAQJCB8vCAC/AAAlAAEJmBwZDwBUAAAAAA==.Tomuchmakeup:BAAALgAECgMJAwAAAA==.Touritos:BAABLgAECn8eAAIGAAkJdRGbKgCdAQAGAAkJdRGbKgCdAQAAAA==.',
Tr='Trimblestein:BAAALgAECgcJDQAAAA==.Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgAECgEJAQAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAQJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.Tuskerdu:BAAALgAECgIJAwAAAA==.',
Tw='Twiggyss:BAAALgAECgEJAQAAAA==.Twogora:BAAALgAECgYJCQAAAA==.Twohoofy:BAAALgADCgcJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMkAAgJ6RbMEwB4AgAkAAgJ6RbMEwB4AgAoAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAQJAQAAAA==.Tyler:BAACLgAFFH8LAAIHAAQJfhXYDwBPAQAHAAQJfhXYDwBPAQAuAAQKfxsAAgcACAkOHTgcAKkCAAcACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAABLgAECn8cAAIbAAcJ/Ak4EwCgAAAbAAcJ/Ak4EwCgAAAAAA==.',
Um='Umariel:BAAALgAFFAQJAQAAAA==.',
Va='Valeka:BAAALgAECgEJAQAAAA==.Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgQJCgAAAA==.Valkyrja:BAAALgAECgEJAQAAAA==.Valr:BAACLgAFFH8GAAIFAAQJTwo2DgCaAAAFAAQJTwo2DgCaAAAuAAQKfzQAAgUACQm3DxYXAGgBAAUACQm3DxYXAGgBAAAA.Vancliffe:BAAALgAECgQJBAABLgAFFAcJFAAIAOsVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Violethunts:BAAALgADCgYJBwAAAA==.Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8iAAIYAAUJdRgcNAD3AAAYAAUJdRgcNAD3AAAuAAQKfy4AAhgACAl8GzlIAAICABgACAl8GzlIAAICAAAA.Vsesosorry:BAABLgAFFH8VAAIWAAQJZxS2NgAHAQAWAAQJZxS2NgAHAQABLgAFFAUJIgAYAHUYAA==.Vsè:BAAALgAFFAIJAgABLgAFFAUJIgAYAHUYAA==.',
Vy='Vyke:BAAALgAECgkJEgABLgAFFAkJIAAJAF0dAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Walkens:BAAALgAECgEJAQAAAA==.Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJBgAAAA==.Wardozer:BAAALgAECgcJCwAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAkJIwAaAKoiAA==.',
Wo='Worgenkrantz:BAABLgAECn8pAAMbAAkJMw3RKQCFAQAbAAkJMw3RKQCFAQAOAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8UAAMIAAcJ6xV7EgAQAQAIAAYJOxZ7EgAQAQAHAAIJKQx9ewCHAAAuAAQKfzQAAwgACAniI9kOADgCAAgACAntH9kOADgCACYABAm0IXsDACoBAAAA.',
Wu='Wukain:BAAALgADCgEJAQAAAA==.',
Xa='Xanatas:BAABLgAECn8oAAIaAAgJzBnsAgAQAgAaAAgJzBnsAgAQAgABLgAECgkJPgAFAOohAA==.',
Xo='Xolòtl:BAABLgAECn8vAAMPAAkJFBy7AQBVAgAPAAkJVxq7AQBVAgAQAAIJYx4uEwC0AAABLgAFFAcJFAAIAOsVAA==.Xoss:BAAALgAFFAQJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAYJCAAjABcGAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Yo='Yourhero:BAAALgAECgEJAgAAAA==.Yourleige:BAAALgAECgEJAQAAAA==.Yourportsir:BAAALgADCgIJAgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zaerine:BAAALgAECgYJBgAAAA==.Zakuso:BAAALgAECgQJCQAAAA==.Zalatha:BAAALgADCgEJAQAAAA==.Zalyia:BAABLgAECn8uAAIdAAkJlA2BJwCSAQAdAAkJlA2BJwCSAQAAAA==.Zapix:BAAALgAECgMJAwABLgAECgMJBwAEAAAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIYAAgJcBVpaQADAgAYAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8dAAQpAAgJkheiDQAAAgApAAcJdxiiDQAAAgAMAAcJnhUvKAB8AQALAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHQApAJIXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIHAAgJORqFMAA5AgAHAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQSAAUJQBa4ygD6AAASAAQJxhi4ygD6AAAKAAMJyRCQcgCxAAAFAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAFFAEJAQAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgcJEAAAAA==.',
['Èo']='Èomer:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgMJBAAAAA==.',
['ßa']='ßaroness:BAAALgAECgIJAgAAAA==.',
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
