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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Paladin-Protection','Druid-Balance','Mage-Frost','DemonHunter-Havoc','Druid-Guardian','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Hunter-Survival','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','Warrior-Protection','Paladin-Holy','Monk-Windwalker','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJCgAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8fAAIBAAcJgw43SQBHAQABAAcJgw43SQBHAQABLgAECgUJBQACAAAAAA==.Aegennai:BAABLgAECn8sAAIDAAkJVwezFQBkAQADAAkJVwezFQBkAQAAAA==.Aegon:BAECLgAFFH8hAAMEAAcJTx8nLwCJAQAEAAYJ9h4nLwCJAQAFAAIJDSEKFgBmAAAuAAQKfyMAAwQACQn8H+s4ACgCAAQABgkfIes4ACgCAAYAAwmUHL4pABsBAAAA.Aegondh:BAEBLgAFFH8JAAIHAAYJyA1JJwDBAAAHAAYJyA1JJwDBAAABLgAFFAcJIQAEAE8fAA==.Aeli:BAAALgAECgQJBQABLgAECgUJBQACAAAAAA==.Aelias:BAAALgAECgUJBQAAAA==.Aeliyn:BAAALgAECgUJBQAAAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIIAAIJPBzbLwCoAAAIAAIJPBzbLwCoAAAuAAQKfzYAAggACQlSHrUOAD8CAAgACQlSHrUOAD8CAAAA.',
Ag='Agilaz:BAABLgAECn80AAIJAAkJeRz0BQA8AgAJAAkJeRz0BQA8AgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAKANEeAA==.',
Ak='Akey:BAAALgAECggJFQAAAQ==.Akhae:BAACLgAFFH8IAAIKAAIJ0BjtWwCUAAAKAAIJ0BjtWwCUAAAuAAQKfyUAAwoACQkVFqYxAO0BAAoACQkVFqYxAO0BAAsACQneDaoyAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8rAAIDAAgJuxYvFQBrAQADAAgJuxYvFQBrAQAAAA==.Alcadeias:BAABLgAECn8rAAMMAAcJFxbQjABYAQAMAAcJFxbQjABYAQANAAEJWA80EQAsAAAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alethiah:BAAALgAECgUJBwAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Altrus:BAAALgAECgQJBQAAAA==.Alupindat:BAABLgAECn8nAAIOAAkJGhi3GQD+AQAOAAkJGhi3GQD+AQAAAA==.Alysyn:BAAALgAECgUJBQABLgAFFAMJBgAPAFgDAA==.',
Am='Amehnet:BAAALgAFFAEJAQAAAA==.Amuria:BAAALgAECgMJAwAAAA==.',
An='Anaeda:BAABLgAECn8dAAIMAAkJng1BHQCuAAAMAAkJng1BHQCuAAAAAA==.Andrömëdä:BAABLgAECn8UAAIQAAcJRBFdJgBHAQAQAAcJRBFdJgBHAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8iAAIPAAYJhw6HEwD5AAAPAAYJhw6HEwD5AAAAAA==.Anveenia:BAAALgAECgEJAgAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgUJBQACAAAAAA==.',
Aq='Aquindra:BAAALgAECgMJBwAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arluz:BAAALgADCgQJBAAAAA==.Arthar:BAAALgAECgQJBAABLgAECggJLgARAGseAA==.',
As='Ashvyth:BAABLgAECn82AAISAAkJuCFxBAD/AgASAAkJuCFxBAD/AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astérion:BAABLgAECn8eAAIMAAkJ5hJRCgBqAQAMAAkJ5hJRCgBqAQAAAA==.',
Av='Avaylia:BAAALgAECgEJAQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAEJAQACAAAAAQ==.',
Az='Azurehope:BAAALgAECgEJAQAAAA==.',
Ba='Baconpancake:BAAALgAECgcJEwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldpunch:BAAALgAECgYJBgAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECggJEQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAABLgAECn8WAAIOAAgJUxH3OQArAQAOAAgJUxH3OQArAQAAAA==.Barendor:BAAALgADCgYJAgAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.Bastarta:BAAALgADCggJCAAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMTAAkJIxqfJQBtAgATAAkJIxqfJQBtAgAUAAgJOAWJNADHAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECggJEAAAAA==.Beastlypläyä:BAAALgAECgYJDQAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAUJEQADAFwRAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Bilac:BAAALgAECgEJAQABLgAFFAQJCQAVAHEEAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.Bizmofunyuns:BAAALgAECgEJAgAAAA==.',
Bl='Blacksabbth:BAAALgAECgQJCwAAAA==.Blindhealz:BAACLgAFFH8HAAIWAAMJLwqLNgCwAAAWAAMJLwqLNgCwAAAuAAQKfzAAAxYACAnMF+EXABUCABYACAnMF+EXABUCABcABQl4C7hLAOAAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJCgAAAA==.Blusoleil:BAABLgAECn8UAAINAAcJkw0LIgAEAQANAAcJkw0LIgAEAQAAAA==.Blutamera:BAAALgAECgEJAQABLgAECggJFAANAJMNAA==.',
Bo='Bonerblast:BAAALgAECgMJBQAAAA==.Boston:BAABLgAECn81AAQTAAkJhyRdEgDbAgATAAkJhyRdEgDbAgAUAAcJzA6WKgAEAQAYAAMJhBuYJgCdAAAAAA==.Bowflex:BAABLgAECn8UAAIZAAgJRw8LDgA9AQAZAAgJRw8LDgA9AQAAAA==.',
Br='Braesong:BAAALgAECgQJBgAAAA==.Branden:BAAALgADCgIJAgAAAA==.Brewtholomew:BAACLgAFFH8HAAIZAAMJbQiOLwDCAAAZAAMJbQiOLwDCAAAuAAQKfysAAhkACQn1EfFGAM0BABkACQn1EfFGAM0BAAAA.Briggsey:BAABLgAECn8qAAIEAAgJsg0zaQBqAQAEAAgJsg0zaQBqAQAAAA==.Briznot:BAABLgAECn8YAAMEAAgJbBnSQADaAQAEAAcJxBjSQADaAQAGAAIJbyBSLwBeAAAAAA==.Brounies:BAABLgAECn8ZAAIaAAkJyAgubADwAAAaAAkJyAgubADwAAAAAA==.Brunna:BAAALgAECgYJCQAAAA==.Bryce:BAABLgAECn8ZAAIMAAgJRBRFbQCUAQAMAAgJRBRFbQCUAQAAAA==.Brèanna:BAAALgAECgQJCgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgAECgUJAwAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBQAbAMUNAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJCQAVAHEEAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8IAAIKAAMJwBOpTwC3AAAKAAMJwBOpTwC3AAAuAAQKfzEAAgoACQm8IHwKANQCAAoACQm8IHwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIRAAcJcBgCFwCaAQARAAcJcBgCFwCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIZAAgJ3QSQnAAIAQAZAAgJ3QSQnAAIAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJCQAAAA==.Caleesia:BAAALgAECgUJAwAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAABLgAECn8aAAMJAAcJ6hOlGgDZAAAZAAQJ+BFfpQD3AAAJAAcJ/RGlGgDZAAAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwACAAAAAA==.Carnìfex:BAABLgAECn8rAAMcAAcJcxpbHAB5AQAcAAcJcxpbHAB5AQAdAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJBQAAAA==.Catbrin:BAABLgAECn8XAAQeAAkJRiL9CwD6AQAeAAkJRiL9CwD6AQARAAQJtBc2KgALAQAaAAMJdxajggCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIfAAgJKAzlDABcAQAfAAgJKAzlDABcAQAAAA==.Cephandrius:BAAALgAECgQJBAABLgAECggJLgARAGseAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Chatpile:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJIAALAJMcAA==.Cheetah:BAAALgAECgQJDAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8VAAIdAAkJ/wcaOQBiAQAdAAkJ/wcaOQBiAQAAAA==.Cloudbreaker:BAAALgAECgcJEQAAAA==.Cloudkeg:BAAALgAECgQJCwAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgkJEAAAAA==.',
Cr='Creeönyx:BAAALgAECgEJAQAAAA==.Crunchyjim:BAAALgAECgIJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCggJGQAAAA==.',
Cy='Cylord:BAAALgADCgIJAgAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIaAAkJBApISwBhAQAaAAkJBApISwBhAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8gAAMLAAkJkxx0KQDJAQALAAgJjB10KQDJAQAKAAMJWwrlnwCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn9iAAQfAAkJrRzoAACaAQAfAAYJdBzoAACaAQAIAAkJ/BUYBAA8AQAgAAMJyAsWBABYAAAAAA==.Damnitsu:BAEBLgAECn8yAAQIAAkJZxMyAwBmAQAIAAkJEA8yAwBmAQAfAAYJWxUCDQBaAQAgAAUJpxViAQAEAQABLgAECgkJYgAfAK0cAA==.Damur:BAAALgADCgcJCgABLgAECgkJMgAGAFkJAA==.Dark:BAAALgAECgcJDQAAAA==.Darkcat:BAABLgAECn8rAAIeAAgJlAdFIgD3AAAeAAgJlAdFIgD3AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgQJDAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAIUAAkJWBqdDwARAgAUAAkJWBqdDwARAgAAAA==.Dear:BAAALgAFFAEJBAAAAA==.Deathberry:BAABLgAECn9EAAIEAAkJuiK8BwAaAwAEAAkJuiK8BwAaAwAAAA==.Deathdoodles:BAACLgAFFH8HAAITAAIJqwvP7QB9AAATAAIJqwvP7QB9AAAuAAQKfyAAAhMACQkkGPw5ABgCABMACQkkGPw5ABgCAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAgAAAA==.Decisively:BAAALgAECgEJAQAAAA==.Deekan:BAABLgAECn8gAAIMAAkJNAePmwA/AQAMAAkJNAePmwA/AQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgAECgEJAQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBwABLgAFFAUJCQAPAGAYAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8YAAIXAAkJsQsxKwB6AQAXAAkJsQsxKwB6AQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQACAAAAAA==.Devlik:BAAALgAECgUJBQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAIMAAgJ5weVrAAkAQAMAAgJ5weVrAAkAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgMJAgAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAABLgAECn8UAAIZAAgJJguebQBmAQAZAAgJJguebQBmAQAAAA==.',
Do='Dobby:BAAALgAECgcJEgAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMhAAkJEiKiAQB4AwAhAAkJEiKiAQB4AwAiAAEJNA53JQA1AAAAAA==.Drivewayhash:BAAALgAECgEJAQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIcAAQJgxj7FgAoAQAcAAQJgxj7FgAoAQAuAAQKfzoAAhwACQmpIBYEAOECABwACQmpIBYEAOECAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQEAAkJwyK9BgAlAwAEAAkJmSK9BgAlAwAGAAIJyhOASQCSAAAFAAIJVh6TMQBaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMfAAgJkBIkCADWAQAfAAgJkBIkCADWAQAIAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elleneo:BAAALgAECgQJBAAAAA==.Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMPAAkJZyDrEAD1AgAPAAkJZyDrEAD1AgAjAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIwAPABEbAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgQJDAAAAA==.',
Er='Erlandis:BAAALgAECgEJAQAAAA==.',
Es='Espii:BAAALgAECgkJAwAAAA==.Estella:BAAALgADCggJCAAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwACAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Eu='Euandros:BAAALgAECgEJAQAAAA==.',
Ev='Evilorc:BAAALgAECgEJAgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezhra:BAAALgADCgYJBQABLgAECgUJAwACAAAAAA==.Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgUJBQAAAA==.Fakename:BAABLgAECn8rAAMaAAkJuyHKCwADAwAaAAgJnCHKCwADAwAOAAQJDw59YACXAAAAAA==.Fakesaint:BAACLgAFFH8SAAIKAAcJzBX0CACSAQAKAAcJzBX0CACSAQAuAAQKfzgAAwoACQlsImgIACoDAAoACQlsImgIACoDAAsAAQnEGF4ZAEYAAAAA.Fangstorm:BAABLgAECn8yAAIeAAkJdxOaDQDcAQAeAAkJdxOaDQDcAQAAAA==.Farorê:BAABLgAECn8YAAIkAAYJ6BduKgB1AQAkAAYJ6BduKgB1AQAAAA==.Fatmann:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIHAAkJ2heGLQARAgAHAAkJ2heGLQARAgAAAA==.Feldruid:BAAALgAECgEJAgAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fi='Fishslap:BAAALgAECgYJCwAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8TAAIlAAMJWwerEwBjAAAlAAMJWwerEwBjAAAuAAQKf0sAAyUACQlIGNYKAEECACUACQlIGNYKAEECAB0AAgm+A36YAEEAAAAA.Flexorcist:BAAALgADCgUJBQAAAA==.',
Fo='Foreverem:BAAALgAECgMJBQAAAA==.',
Fr='Frawnix:BAAALgADCgEJAgAAAA==.Fritopaws:BAABLgAECn8/AAMJAAkJ+h0uAwClAgAJAAkJih0uAwClAgAbAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgYJCQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgcJEgAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJEwAAAA==.Gaska:BAAALgAECggJCAABLgAFFAcJCAABABgLAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn9YAAMYAAkJIRFnAQC9AQAYAAkJIRFnAQC9AQATAAgJswe+mQA2AQAAAA==.Ginzie:BAAALgAECggJDgAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgAECgMJAwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJEAABLgAECgkJFgAEADcaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgUJAwAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8JAAIVAAQJcQRiSACpAAAVAAQJcQRiSACpAAAuAAQKfykAAhUABwl9F0ouAIIBABUABwl9F0ouAIIBAAAA.Gummypenguin:BAABLgAECn8aAAMZAAgJGhrqGgDDAAAJAAYJTQzRVQDyAAAZAAgJGhjqGgDDAAABLgAFFAcJJAAZAJQdAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8gAAIdAAkJaA4mKgCvAQAdAAkJaA4mKgCvAQABLgAECgkJJwAZAMYUAA==.Hakano:BAABLgAECn8lAAISAAYJrgPlWACmAAASAAYJrgPlWACmAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8nAAIZAAkJxhS1MwANAgAZAAkJxhS1MwANAgAAAA==.Hawkdubya:BAAALgADCgYJBQABLgAECgUJAwACAAAAAA==.Hawkulees:BAAALgAECgUJAgAAAA==.Hazelnoot:BAABLgAECn8mAAMMAAkJ0BtLLgBIAgAMAAkJ0BtLLgBIAgAmAAYJugWnVgDdAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAIQAAkJAhMkFQDmAQAQAAkJAhMkFQDmAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn80AAIhAAkJMAk+FgBqAQAhAAkJMAk+FgBqAQAAAA==.',
Ho='Holehbones:BAAALgADCgEJAQAAAA==.Hollyanne:BAABLgAECn8sAAIGAAkJjQuzDgBSAQAGAAkJjQuzDgBSAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBQAbAMUNAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgQJCwABLgAECgYJDQACAAAAAA==.Hornsharp:BAABLgAECn8lAAMKAAcJRB6zIwA5AgAKAAcJRB6zIwA5AgALAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAFFAQJCQAVAHEEAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQJAAMJfBxZGADQAAAJAAIJ0CNZGADQAAAbAAIJRxdkJwCaAAAZAAEJqibUmQBeAAAuAAQKfz0ABAkACQnAJaQDAGoDAAkACAnDJaQDAGoDABsACAldI+AHAKACABkAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgQJDAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8NAAMKAAQJpBi3GADcAAAKAAQJpBi3GADcAAALAAIJwgk2HwB2AAAuAAQKfzAAAwoABwl+G7UuAPsBAAoABwl+G7UuAPsBAAsABgmLGg8wAH8BAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQACAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwATABsfAA==.Insaint:BAACLgAFFH8VAAIMAAQJARgvHAAAAQAMAAQJARgvHAAAAQAuAAQKfzUAAgwACQkJG7AuAEYCAAwACQkJG7AuAEYCAAAA.',
Is='Isabellë:BAABLgAECn8wAAMXAAkJUQrwOAAxAQAXAAkJUQrwOAAxAQAkAAIJnANhaQBBAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
It='Ithdorel:BAAALgADCggJDwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIEAAcJAhEfcgBWAQAEAAcJAhEfcgBWAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAFFAMJBQAdALgZAA==.',
Je='Jessamine:BAABLgAECn8jAAIPAAkJERsWQAAcAgAPAAkJERsWQAAcAgAAAA==.Jessicafelba:BAABLgAECn8WAAMEAAkJNxoTLgAgAgAEAAgJNxoTLgAgAgAGAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn84AAIeAAgJoRnmAQCLAQAeAAgJoRnmAQCLAQAAAA==.Jezzak:BAABLgAECn8vAAIZAAkJ/htKBAApAgAZAAkJ/htKBAApAgABLgAECgkJMQAZAAEbAA==.',
Jo='John:BAABLgAFFH8IAAIfAAQJJyCqAgCEAQAfAAQJJyCqAgCEAQAAAA==.Jorien:BAABLgAECn9XAAIZAAkJAxzeGwB+AgAZAAkJAxzeGwB+AgAAAA==.',
Jp='Jp:BAAALgAFFAEJAQAAAA==.Jps:BAAALgAECgYJCAABLgAFFAEJAQACAAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECgkJGAAEAGwZAA==.Justadwarf:BAAALgAECgcJCQAAAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMkAAkJWxhHGAAaAgAkAAkJWxhHGAAaAgAXAAIJmxGcbgBnAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJEAAAAA==.Kaenaya:BAAALgAECgMJAwAAAA==.Kaetii:BAAALgAECgEJAQAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8sAAMdAAkJlx27EAByAgAdAAkJPRy7EAByAgAlAAYJvBhMGwBdAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJFgAlAKAjAA==.Kardels:BAABLgAECn8WAAIlAAcJoCPHCgBCAgAlAAcJoCPHCgBCAgAAAA==.Karnn:BAACLgAFFH8YAAMnAAYJtxheDwBDAQAnAAUJdh5eDwBDAQASAAIJbAE7HwA3AAAuAAQKfycAAycACAl3JJQKAM8CACcACAl3JJQKAM8CAAEABglfEANVABwBAAAA.Karzuna:BAAALgAECgEJAgAAAA==.Katalight:BAAALgAECgQJAQABLgAECggJCgACAAAAAA==.Katrini:BAAALgAECggJCgAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAPALAdAA==.Kennathus:BAAALgADCgIJAgABLgAECgkJMgAGAFkJAA==.',
Ki='Kiascendance:BAAALgAFFAMJAwAAAA==.Kiplet:BAABLgAECn8aAAIkAAkJpBZIJAChAQAkAAkJpBZIJAChAQAAAA==.',
Kn='Knockback:BAAALgAECgUJCgAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Koriane:BAAALgAECgEJAQAAAA==.Korxon:BAABLgAECn8fAAMWAAgJkhfJIgC5AQAWAAgJkhfJIgC5AQAkAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krastikon:BAAALgAECgEJAgAAAA==.Krazilec:BAAALgADCgYJBgABLgADCgYJBgACAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgAUAFgaAA==.',
Ks='Ksyusha:BAABLgAECn8VAAMMAAgJPQmx3ADiAAAMAAcJLwmx3ADiAAAmAAIJ1QpHEQBMAAAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgQJCAAAAA==.',
['Kä']='Kämi:BAAALgAECgUJBwABLgAECgcJKwAPAEUWAA==.',
La='Lahabrea:BAABLgAECn8fAAMGAAgJBA3wKwAPAQAEAAgJwQpLigAlAQAGAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAABLgAECn8uAAMRAAgJax6VAwBpAQARAAgJnB2VAwBpAQAeAAQJJhQDIgD5AAAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAVAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIHAAkJBBhlPQDSAQAHAAkJBBhlPQDSAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgAUAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalarrow:BAAALgAECgYJBgAAAA==.Lethalbimbo:BAABLgAECn8WAAIMAAgJKwtPpgAuAQAMAAgJKwtPpgAuAQAAAA==.Lethallok:BAAALgADCgMJAwAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIKAAcJ0R6tBACCAgAKAAcJ0R6tBACCAgAuAAQKfyIAAwoACQnNI0sQAJUCAAoACAl0I0sQAJUCAAsAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJEAAAAA==.Littlebitt:BAAALgAFFAEJAQAAAQ==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonarius:BAAALgAECgEJAQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Lu='Lunablue:BAAALgAFFAEJAQAAAA==.',
Ly='Lyv:BAAALgAECgEJAgAAAA==.',
['Lø']='Løllîe:BAABLgAECn8VAAISAAgJ+gjuBwCFAAASAAgJ+gjuBwCFAAAAAA==.Løllïe:BAAALgADCgYJDAABLgAECggJFQASAPoIAA==.',
Ma='Macdee:BAAALgAECgEJAgAAAA==.Magatai:BAABLgAECn8cAAIPAAgJOQegnwA8AQAPAAgJOQegnwA8AQAAAA==.Mageless:BAAALgAECgUJBgAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Makagongar:BAAALgAECgIJAwABLgAECggJIwATAPwaAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAACAAAAAA==.Manaster:BAAALgAECggJCwAAAA==.Mandhos:BAAALgAECgMJAwABLgAECggJIwATAPwaAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwACAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8jAAMTAAgJ/BpmdwB1AQATAAgJfRpmdwB1AQAYAAIJhxpaMwBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAABLgAECn8hAAIPAAkJ1AdfDgAxAQAPAAkJ1AdfDgAxAQAAAA==.Maynard:BAAALgAECgQJBgAAAA==.Maynis:BAAALgAECgUJBgAAAA==.',
Mc='Mcbrynhammer:BAABLgAECn8UAAIMAAQJewxuJACFAAAMAAQJewxuJACFAAAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgYJCwAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMdAAkJLxbZJQDJAQAdAAgJzRbZJQDJAQAlAAEJ3hEmUwAzAAAAAA==.Mikewazowski:BAAALgADCgUJBAAAAA==.Minarii:BAAALgAECgYJDQABLgAECgkJNwAPAA0RAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAkAKQWAA==.Misahaviran:BAAALgAECgQJBQABLgAECggJIwATAPwaAA==.Misha:BAAALgAECgEJAwAAAA==.Mishelö:BAAALgAECgIJAgAAAA==.Misla:BAAALgAECgQJBwAAAA==.Misstriix:BAAALgAECgYJBgAAAA==.Mistynite:BAAALgADCgkJGgAAAA==.',
Mo='Mochimochi:BAAALgAECgcJEQAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgUJCQABLgAECgkJQgAXALQPAA==.Moonshae:BAABLgAECn8mAAMBAAkJjhJ8KgDZAQABAAkJjhJ8KgDZAQAnAAEJ7BkQEwBNAAAAAA==.Moosesanta:BAAALgAECgEJAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwAOABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwAOABoYAA==.Mouse:BAABLgAECn8WAAIgAAcJqx9GBgDvAQAgAAcJqx9GBgDvAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.Mustevistust:BAAALgADCgEJAQABLgAECggJIwATAPwaAA==.',
My='Mystiquè:BAAALgAECgUJAgAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwATAKsLAA==.Nails:BAABLgAECn8aAAIIAAkJhxMNFwDkAQAIAAkJhxMNFwDkAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgAECgUJBQABLgAECgkJHAAnAJ8SAA==.',
Ne='Nethermoon:BAAALgAECgEJAwAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nightray:BAAALgAECgMJAwABLgAECggJLgARAGseAA==.Nikan:BAAALgAECggJDwAAAA==.Ninjadoodles:BAAALgAECgEJAwABLgAFFAIJBwATAKsLAA==.Niralth:BAAALgAECgUJBQAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAACAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgAMANAbAA==.Noriisa:BAABLgAECn8xAAIZAAkJARv2KwAtAgAZAAkJARv2KwAtAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIKAAgJghtHIABOAgAKAAgJghtHIABOAgAAAA==.',
Ny='Nyvak:BAABLgAECn8aAAMlAAgJvg60JgD9AAAlAAgJvg60JgD9AAAdAAUJ9whgagC4AAAAAA==.',
Od='Odinhand:BAABLgAECn8wAAIOAAkJugtcMgBRAQAOAAkJugtcMgBRAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Ol='Oliissa:BAAALgAECgUJAwAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQACAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIPAAkJmCJeDwAAAwAPAAkJmCJeDwAAAwABLgAFFAUJEQADAFwRAA==.Ozwäldo:BAABLgAFFH8RAAIDAAUJXBF0BAAHAQADAAUJXBF0BAAHAQAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgAECggJCwAAAA==.Panduh:BAACLgAFFH8YAAIPAAUJbhWVDQCvAQAPAAUJbhWVDQCvAQAuAAQKfz8AAg8ACQmpIlgRAPICAA8ACQmpIlgRAPICAAAA.Pandóra:BAABLgAECn8YAAMXAAYJYQNtXwCaAAAXAAYJYQNtXwCaAAAWAAQJXAKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMfAAMJ5SRaBQAqAQAfAAMJ5SRaBQAqAQAIAAIJcB7+EADBAAAuAAQKfz0AAx8ACQmjJksAAHcDAB8ACQl1JksAAHcDAAgACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Peppermintxo:BAAALgAECgEJBQABLgAECgYJDQACAAAAAA==.Perceval:BAAALgAECgYJCgAAAA==.',
Ph='Pherrall:BAAALgAECgUJBQABLgAFFAgJIAATAOwaAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAACAAAAAA==.Pinkeepink:BAABLgAECn8uAAIGAAkJUwp/EQAvAQAGAAkJUwp/EQAvAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Polox:BAAALgAECgEJAgAAAA==.Potangwang:BAABLgAECn8UAAIZAAcJsw3eeABOAQAZAAcJsw3eeABOAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prild:BAAALgAECgEJAQAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8qAAIUAAkJDyJXCACQAgAUAAkJDyJXCACQAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMMAAcJ8Q0WqwAmAQAMAAcJ8Q0WqwAmAQANAAQJ/wZQOwBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMDAAkJ3A3MDwC1AQADAAkJ3A3MDwC1AQALAAcJRgPoaACsAAAAAA==.Raynë:BAAALgAECgYJCgABLgAECgkJJwAZAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Rebecca:BAAALgADCgkJCQAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgAUAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8fAAIoAAgJZSAwAQD0AQAoAAgJZSAwAQD0AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCAAcABQmjEgWgAOMAAAAA.Rineli:BAABLgAECn83AAIPAAkJDRHMTwDsAQAPAAkJDRHMTwDsAQAAAA==.Ringadingg:BAABLgAECn80AAITAAkJhSS7BwA3AwATAAkJhSS7BwA3AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAATAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAIAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIkAAgJ7RonFgAhAgAkAAgJ7RonFgAhAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8UAAIMAAgJCRwDEgDdAQAMAAgJCRwDEgDdAQAuAAQKfzUAAgwACQncJaYCAG4DAAwACQncJaYCAG4DAAAA.',
Sc='Scony:BAABLgAECn8VAAMIAAkJhxLUFwDcAQAIAAgJahTUFwDcAQAfAAUJmQkKFwDBAAAAAA==.Screws:BAAALgADCgYJBgABLgAECgkJGgAIAIcTAA==.Scribs:BAABLgAECn8bAAIZAAgJmANpngAFAQAZAAgJmANpngAFAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMPAAgJtB0/dACRAQAPAAcJbxw/dACRAQAjAAQJTh4SDAARAQABLgAFFAMJBgAUAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selineda:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Seniko:BAAALgAECgMJAwAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJVwATALwaAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAMJBwABANEWAA==.Severautism:BAAALgAECgMJAwABLgAFFAMJBwABANEWAA==.Severànce:BAAALgADCgQJBAABLgAFFAMJBwABANEWAA==.Sevivify:BAACLgAFFH8HAAMBAAMJ0RZbTgBtAAABAAIJJBJbTgBtAAASAAIJ1AKxTgBnAAAuAAQKfxcABBIACQluD60lAIEBABIACQlHDK0lAIEBAAEABQmTFmpJAEYBACcABQlwEyczADgBAAAA.Sevotion:BAABLgAECn8xAAQMAAkJUx0oNgBKAgAMAAgJKB0oNgBKAgAmAAkJSxUCHQAbAgANAAcJog8qLQClAAABLgAFFAMJBwABANEWAA==.',
Sh='Shablammy:BAABLgAECn81AAMKAAkJMiV/AQC7AwAKAAkJMiV/AQC7AwALAAEJ6BCSpQAyAAAAAA==.Shadownome:BAAALgAECgQJDwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJNAANACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgQJCQAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgAECgUJBQAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgIJAgAAAA==.Silvanosh:BAABLgAECn8aAAIZAAkJWQzFWgCVAQAZAAkJWQzFWgCVAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQbAAkJeBoPEQAjAgAbAAkJZRkPEQAjAgAJAAcJfRd6KADmAQAZAAQJfREB0gCnAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwABLgAECgQJBAACAAAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJCAAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJEQAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgcJCgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAkJNQAPAHYgAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sploof:BAAALgAECgEJAQAAAA==.Sprynt:BAACLgAFFH8IAAIBAAcJGAs3EgAjAQABAAcJGAs3EgAjAQAuAAQKfx8AAgEACQlrHDYMANYCAAEACQlrHDYMANYCAAAA.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgQJAwAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAYJDwAQAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8dAAMXAAkJYRatFwAKAgAXAAkJYRatFwAKAgAkAAEJvQY6cgAqAAABLgAFFAMJBwABANEWAA==.Stonemother:BAAALgAECggJEAAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgACAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.Stàrîñà:BAAALgAECgQJBAAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwAMAMgcAA==.',
Sw='Swampmonster:BAAALgAECgYJEgAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIHAAQJchkLSAAQAQAHAAQJchkLSAAQAQAuAAQKfywAAwcACAkkJAMRAPYCAAcACAnOIwMRAPYCABAABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECggJEwAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAFFAIJBQAYANcLAA==.Taurastrage:BAABLgAECn8WAAIlAAcJdhuIEwDTAQAlAAcJdhuIEwDTAQABLgAFFAIJBQAYANcLAA==.Taurdk:BAACLgAFFH8FAAIYAAIJ1wufIQB9AAAYAAIJ1wufIQB9AAAuAAQKfyIAAxgACQlbG8gDAKACABgACQlbG8gDAKACABMAAglCBn9OAVMAAAAA.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8LAAIOAAMJix2sJAADAQAOAAMJix2sJAADAQAuAAQKfx8AAg4ACAkmItAMAIoCAA4ACAkmItAMAIoCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAlACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAlACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAlACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJVwATALwaAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgALAKgeAA==.Teetau:BAABLgAECn8+AAIRAAkJfAciMgDhAAARAAkJfAciMgDhAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAiAEEcAA==.Thadregosa:BAABLgAECn9FAAMiAAkJQRxbAgCdAgAiAAkJQRxbAgCdAgAVAAcJwAowZQCrAAAAAA==.Thander:BAAALgAECgEJAQABLgAECgQJCwACAAAAAA==.Thannicus:BAAALgAECgYJDgAAAA==.Thedarkskull:BAAALgAECgEJAgAAAA==.Thordar:BAAALgADCggJFQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIaAAkJchyyDwDVAgAaAAkJchyyDwDVAgAAAA==.Tiberius:BAAALgADCgYJBgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAaAHIcAA==.Tiffy:BAAALgAECgcJBwAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAABLgAECn8WAAInAAgJ0RpLIQCkAQAnAAgJ0RpLIQCkAQAAAA==.',
Tm='Tmtglizzy:BAAALgAFFAEJAgAAAA==.',
To='Tokalu:BAABLgAECn8cAAInAAkJnxIyHwCzAQAnAAkJnxIyHwCzAQAAAA==.Tonjudsonson:BAACLgAFFH8fAAIRAAcJAh/LAwDdAQARAAcJAh/LAwDdAQAuAAQKfywAAhEACQmCJfUAAGQDABEACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAILAAkJDwzDNwBZAQALAAkJDwzDNwBZAQAAAA==.Totemgranny:BAAALgADCgYJBQAAAA==.Toxix:BAABLgAECn8fAAIDAAkJJSPpAQAOAwADAAkJJSPpAQAOAwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8yAAIGAAkJWQkoEQAzAQAGAAkJWQkoEQAzAQAAAA==.Twobricks:BAABLgAECn8wAAIaAAkJzhbVJgAZAgAaAAkJzhbVJgAZAgAAAA==.',
Ty='Tyamat:BAAALgAECgEJAQABLgAECgcJGgAJAOoTAA==.Tyrssana:BAABLgAECn8VAAIHAAgJKBC1FQChAAAHAAgJKBC1FQChAAABLgAFFAYJDwAiAIsKAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIkAAYJIxrwIgCrAQAkAAYJIxrwIgCrAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8wAAINAAkJXR+fCABMAgANAAkJXR+fCABMAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAABLgAECn8cAAMNAAkJiB/pCQAuAgANAAkJgBvpCQAuAgAMAAUJ6x4dEgAEAQAAAA==.Urlacher:BAAALgAECgMJBQAAAA==.',
Va='Vaccaria:BAAALgAECgQJBAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAKANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAABLgAECn8VAAIMAAgJjg3yHgCkAAAMAAgJjg3yHgCkAAAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Velskud:BAAALgAECgMJAwAAAA==.Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCwABLgAECgkJGAAEAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAInAAUJ1STFCACOAQAnAAUJ1STFCACOAQAuAAQKfxoAAicACAk9I0MEAEgDACcACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJCAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIbAAcJBxlPEgCeAQAbAAcJBxlPEgCeAQAAAA==.Violyt:BAAALgAECgUJCAAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgAWADMYAA==.Visea:BAAALgAECgQJCwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCwAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAgAAAA==.Watevr:BAEBLgAECn8dAAIpAAgJlg3zAAA3AQApAAgJlg3zAAA3AQABLgAECgkJYgAfAK0cAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwACAAAAAA==.Wesleypriest:BAABLgAECn8fAAMWAAkJBwmuLgBmAQAWAAkJ5giuLgBmAQAkAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgYJEAAAAA==.',
Wr='Wrandanden:BAAALgAECgEJAQAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8wAAINAAkJwRa7CwAKAgANAAkJwRa7CwAKAgAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAPAEkXAA==.',
Xe='Xear:BAAALgADCgkJKwABLgAECgcJBwACAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAKANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAfAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIPAAcJSReajQC3AQAPAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMKAAgJQx1RGwBxAgAKAAgJQx1RGwBxAgALAAEJWAjekQAlAAABLgAECgkJJQATACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAIWAAQJlw+rJwANAQAWAAQJlw+rJwANAQABLgAFFAcJGgAKANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAdAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgAECgIJAgAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCwAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCwAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAKANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAABLgAECn8WAAIMAAYJhgeoHACyAAAMAAYJhgeoHACyAAAAAA==.Zeratule:BAAALgAECgIJAwAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAgAAAA==.Zerm:BAABLgAECn9MAAIMAAkJGx5aGACxAgAMAAkJGx5aGACxAgAAAA==.Zermonk:BAAALgADCgEJAQAAAA==.',
Zi='Zijo:BAAALgAECgcJEAAAAA==.Zinnkura:BAABLgAECn8WAAIKAAgJGw+LWgBOAQAKAAgJGw+LWgBOAQAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8tAAIEAAkJ0Q2uUQCmAQAEAAkJ0Q2uUQCmAQAAAA==.',
Zv='Zvirä:BAAALgADCgUJAgAAAA==.',
['Ñô']='Ñôg:BAAALgAECgQJAgAAAA==.',
['Ød']='Ødis:BAAALgADCgcJJQAAAA==.',
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
