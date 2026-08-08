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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Paladin-Protection','Druid-Balance','Mage-Frost','DemonHunter-Havoc','Druid-Guardian','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Hunter-Survival','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','Warrior-Protection','Monk-Windwalker','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJCgAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8fAAIBAAcJgw43SQBHAQABAAcJgw43SQBHAQABLgAECgYJBgACAAAAAA==.Aegennai:BAABLgAECn8sAAIDAAkJVwezFQBkAQADAAkJVwezFQBkAQAAAA==.Aegon:BAECLgAFFH8lAAMEAAgJsh0nLwCJAQAEAAcJIx0nLwCJAQAFAAIJDSEKFgBmAAAuAAQKfyMAAwQACQn8H+s4ACgCAAQABgkfIes4ACgCAAYAAwmUHL4pABsBAAAA.Aegondh:BAEBLgAFFH8JAAIHAAYJyA11UgD2AAAHAAYJyA11UgD2AAABLgAFFAgJJQAEALIdAA==.Aegonpriest:BAEALgAFFAQJBAABLgAFFAgJJQAEALIdAA==.Aeli:BAAALgAECgQJBQABLgAECgYJBgACAAAAAA==.Aelias:BAAALgAECgYJBgAAAA==.Aelio:BAAALgAECgIJAgABLgAECgYJBgACAAAAAA==.Aeliyn:BAAALgAECgUJBQAAAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIIAAIJPBzbLwCoAAAIAAIJPBzbLwCoAAAuAAQKfzYAAggACQlSHrUOAD8CAAgACQlSHrUOAD8CAAAA.',
Ag='Agilaz:BAABLgAECn80AAIJAAkJeRz0BQA8AgAJAAkJeRz0BQA8AgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAKANEeAA==.',
Ak='Akey:BAAALgAECgkJHQAAAQ==.Akhae:BAACLgAFFH8IAAIKAAIJ0BjtWwCUAAAKAAIJ0BjtWwCUAAAuAAQKfyUAAwoACQkVFqYxAO0BAAoACQkVFqYxAO0BAAsACQneDaoyAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8uAAIDAAgJhBgyBQAeAQADAAgJhBgyBQAeAQAAAA==.Alcadeias:BAABLgAECn8rAAMMAAcJFxbQjABYAQAMAAcJFxbQjABYAQANAAEJWA9bGAAsAAAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alethiah:BAAALgAECgUJBwAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgAECgIJAgAAAA==.Altrus:BAAALgAECgQJBwAAAA==.Alupindat:BAABLgAECn8nAAIOAAkJGhi3GQD+AQAOAAkJGhi3GQD+AQAAAA==.Alysyn:BAAALgAECgUJBgABLgAFFAMJBgAPAFgDAA==.',
Am='Amehnet:BAAALgAFFAEJAQAAAA==.Amuria:BAAALgAECgMJAwAAAA==.',
An='Anaeda:BAABLgAECn8dAAIMAAkJng2/KACpAAAMAAkJng2/KACpAAAAAA==.Andrömëdä:BAABLgAECn8VAAIQAAgJKhFdJgBHAQAQAAgJKhFdJgBHAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8iAAIPAAYJhw59HADvAAAPAAYJhw59HADvAAAAAA==.Anveenia:BAAALgAECgEJAgAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgYJBgACAAAAAA==.',
Aq='Aquindra:BAAALgAECgMJBwAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arluz:BAAALgADCgQJBAAAAA==.Arthar:BAAALgAECgQJBAABLgAFFAIJBQARAI0WAA==.',
As='Asharahett:BAAALgAECgIJAwAAAA==.Ashvyth:BAABLgAECn82AAISAAkJuCFxBAD/AgASAAkJuCFxBAD/AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astarra:BAAALgADCgQJBAAAAA==.',
Av='Avaylia:BAAALgAECgEJAQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAIJBQACAAAAAQ==.',
Az='Azurehate:BAAALgADCgMJAwAAAA==.Azurehope:BAAALgAECgEJAQAAAA==.',
Ba='Baconpancake:BAABLgAECn8UAAIMAAgJKBdSYgCsAQAMAAgJKBdSYgCsAQAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldpunch:BAAALgAECgYJBgAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgkJEgAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAABLgAECn8ZAAIOAAgJLBcpBQCYAQAOAAgJLBcpBQCYAQAAAA==.Barendor:BAAALgAECgMJAwAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.Bastarta:BAAALgADCggJCAAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMTAAkJIxqfJQBtAgATAAkJIxqfJQBtAgAUAAgJOAWJNADHAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECggJEwAAAA==.Beastlypläyä:BAAALgAECgYJEAAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAYJGwADAGUZAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Bilac:BAAALgAECgQJBAABLgAFFAQJDAAVAOEFAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.Bizmofunyuns:BAAALgAECgIJAwAAAA==.',
Bl='Blacksabbth:BAAALgAECgQJDwAAAA==.Blindhealz:BAACLgAFFH8HAAIWAAMJLwqLNgCwAAAWAAMJLwqLNgCwAAAuAAQKfzAAAxYACAnMF+EXABUCABYACAnMF+EXABUCABcABQl4C7hLAOAAAAAA.Blinkzy:BAAALgAECgUJBgAAAA==.Bloodsharp:BAAALgAECgYJCwAAAA==.Blusoleil:BAABLgAECn8VAAINAAgJ2A0LIgAEAQANAAgJ2A0LIgAEAQAAAA==.Blutamera:BAAALgAECgEJAQABLgAECgkJFQANANgNAA==.',
Bo='Bonerblast:BAAALgAECgMJBQAAAA==.Boston:BAABLgAECn81AAQTAAkJhyRdEgDbAgATAAkJhyRdEgDbAgAUAAcJzA6WKgAEAQAYAAMJhBuYJgCdAAAAAA==.Bowflex:BAABLgAECn8UAAIZAAgJRw/lFAAwAQAZAAgJRw/lFAAwAQAAAA==.',
Br='Braesong:BAAALgAECgQJDAAAAA==.Branden:BAAALgADCgIJAgABLgAECgQJCwACAAAAAA==.Brewtholomew:BAACLgAFFH8HAAIZAAMJbQimPAC2AAAZAAMJbQimPAC2AAAuAAQKfysAAhkACQn1EfFGAM0BABkACQn1EfFGAM0BAAAA.Briggsey:BAABLgAECn8qAAIEAAgJsg0zaQBqAQAEAAgJsg0zaQBqAQAAAA==.Briznot:BAABLgAECn8YAAMEAAgJbBnSQADaAQAEAAcJxBjSQADaAQAGAAIJbyBSLwBeAAAAAA==.Brounies:BAABLgAECn8ZAAIaAAkJyAgubADwAAAaAAkJyAgubADwAAAAAA==.Brunna:BAAALgAECgYJCQAAAA==.Bryce:BAABLgAECn8ZAAIMAAgJRBRFbQCUAQAMAAgJRBRFbQCUAQAAAA==.Brèanna:BAAALgAECgQJCgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubs:BAAALgADCgUJCQABLgAECgUJCgACAAAAAA==.Bubbadubya:BAAALgAECgUJCgAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBQAbAMUNAA==.Buhnahnabred:BAAALgAECgIJAgAAAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJDAAVAOEFAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8KAAIKAAMJzhmpTwC3AAAKAAMJzhmpTwC3AAAuAAQKfzEAAgoACQm8IHwKANQCAAoACQm8IHwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIRAAcJcBgCFwCaAQARAAcJcBgCFwCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIZAAgJ3QSQnAAIAQAZAAgJ3QSQnAAIAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJCQAAAA==.Caleesia:BAAALgAECgUJBwAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAABLgAECn8bAAMJAAcJphYiBADoAAAZAAQJ+BFfpQD3AAAJAAcJuhQiBADoAAAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwACAAAAAA==.Carnìfex:BAABLgAECn8vAAMcAAcJmh4dAgC+AQAcAAcJmh4dAgC+AQAdAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJBQAAAA==.Catbrin:BAABLgAECn8XAAQeAAkJRiL9CwD6AQAeAAkJRiL9CwD6AQARAAQJtBc2KgALAQAaAAMJdxajggCzAAAAAA==.Cathedarra:BAAALgAFFAEJAQAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIfAAgJKAzlDABcAQAfAAgJKAzlDABcAQAAAA==.Cephandrius:BAAALgAECgQJBAABLgAFFAIJBQARAI0WAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Chatpile:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJIAALAJMcAA==.Cheetah:BAAALgAECgQJDAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8VAAIdAAkJ/wcaOQBiAQAdAAkJ/wcaOQBiAQAAAA==.Cloudbreaker:BAAALgAECgcJEQAAAA==.Cloudkeg:BAAALgAECgQJCwAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Cobramage:BAAALgAECgQJBAAAAA==.Constellate:BAAALgAECgkJEAAAAA==.Cotterpins:BAAALgADCgMJAwABLgAECgkJGgAIAIcTAA==.',
Cr='Creeönyx:BAAALgAECgEJAQAAAA==.Crunchyjim:BAAALgAECgIJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCggJGQAAAA==.',
Cy='Cylord:BAAALgADCgIJAgAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIaAAkJBApISwBhAQAaAAkJBApISwBhAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8gAAMLAAkJkxx0KQDJAQALAAgJjB10KQDJAQAKAAMJWwrlnwCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn9rAAQfAAkJ6BxDAQCfAQAfAAYJ0xxDAQCfAQAgAAYJaxZPAQBWAQAIAAkJ/BXHBQAzAQAAAA==.Damnitsu:BAEBLgAECn8yAAQIAAkJZxPgBABTAQAfAAYJWxUCDQBaAQAIAAkJEA/gBABTAQAgAAUJpxXsAQAKAQABLgAECgkJawAfAOgcAA==.Damur:BAAALgAECgMJBgABLgAECgkJMwAGAFkJAA==.Dark:BAABLgAECn8UAAMMAAcJ6A6VFgAaAQAMAAcJ6A6VFgAaAQAhAAEJ7gFXIgAbAAAAAA==.Darkcat:BAABLgAECn8rAAIeAAgJlAdFIgD3AAAeAAgJlAdFIgD3AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgQJDAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAIUAAkJWBqdDwARAgAUAAkJWBqdDwARAgAAAA==.Dear:BAABLgAFFH8GAAMeAAIJqQ9QDwBNAAAeAAEJ3x5QDwBNAAARAAEJcgDnOQADAAAAAA==.Deathberry:BAABLgAECn9EAAIEAAkJuiK8BwAaAwAEAAkJuiK8BwAaAwAAAA==.Deathdoodles:BAACLgAFFH8HAAITAAIJqwvP7QB9AAATAAIJqwvP7QB9AAAuAAQKfyAAAhMACQkkGPw5ABgCABMACQkkGPw5ABgCAAAA.Deathsharp:BAAALgAECgMJAwAAAA==.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAgAAAA==.Decisively:BAAALgAECgEJAQAAAA==.Deekan:BAABLgAECn8gAAIMAAkJNAePmwA/AQAMAAkJNAePmwA/AQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgAECgEJAQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBwABLgAFFAkJGgAPAO0aAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwABLgAECgkJGgALAEgSAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8YAAIXAAkJsQsxKwB6AQAXAAkJsQsxKwB6AQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQACAAAAAA==.Devlik:BAAALgAECgUJBQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAIMAAgJ5weVrAAkAQAMAAgJ5weVrAAkAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgQJAQAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQABLgAFFAUJGAAPAG4VAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAABLgAECn8UAAIZAAgJJguebQBmAQAZAAgJJguebQBmAQAAAA==.',
Do='Dobby:BAAALgAECgcJEgABLgAECggJCAACAAAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMiAAkJEiKiAQB4AwAiAAkJEiKiAQB4AwAjAAEJNA53JQA1AAAAAA==.Drivewayhash:BAAALgAECgEJAQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIcAAQJgxj7FgAoAQAcAAQJgxj7FgAoAQAuAAQKfzoAAhwACQmpIBYEAOECABwACQmpIBYEAOECAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQEAAkJwyK9BgAlAwAEAAkJmSK9BgAlAwAGAAIJyhOASQCSAAAFAAIJVh6TMQBaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMfAAgJkBIkCADWAQAfAAgJkBIkCADWAQAIAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elleneo:BAAALgAECgQJBAAAAA==.Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMPAAkJZyDrEAD1AgAPAAkJZyDrEAD1AgAkAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIwAPABEbAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgQJDAAAAA==.',
Er='Erlandis:BAAALgAECgEJAQAAAA==.',
Es='Espii:BAAALgAECgkJAwAAAA==.Estella:BAABLgAECn8XAAIPAAcJIwzMGAALAQAPAAcJIwzMGAALAQAAAA==.',
Et='Et:BAAALgAECgEJAQAAAA==.Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwACAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Eu='Euandros:BAAALgAECgEJAgAAAA==.',
Ev='Evilorc:BAAALgAECgEJAwAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezhra:BAAALgAECgIJAgABLgAECgUJBwACAAAAAA==.Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgUJBgAAAA==.Fakename:BAABLgAECn8rAAMaAAkJuyHKCwADAwAaAAgJnCHKCwADAwAOAAQJDw59YACXAAAAAA==.Fakesaint:BAACLgAFFH8WAAIKAAcJFBcxBwDmAQAKAAcJFBcxBwDmAQAuAAQKfz0AAwoACQlsImgIACoDAAoACQlsImgIACoDAAsAAgn7HuIRAK0AAAAA.Fangstorm:BAABLgAECn8yAAIeAAkJdxOaDQDcAQAeAAkJdxOaDQDcAQAAAA==.Farorê:BAABLgAECn8YAAIlAAYJ6BduKgB1AQAlAAYJ6BduKgB1AQAAAA==.Fatmann:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIHAAkJ2heGLQARAgAHAAkJ2heGLQARAgAAAA==.Feldruid:BAAALgAECgIJBAAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fi='Fidgit:BAAALgAECgQJBAAAAA==.Fishslap:BAAALgAECgYJCwAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8YAAImAAMJ2A00EQCiAAAmAAMJ2A00EQCiAAAuAAQKf00AAyYACQlIGNYKAEECACYACQlIGNYKAEECAB0AAgm+A36YAEEAAAAA.Flexidari:BAAALgAECgEJAQAAAA==.Flexorcist:BAAALgAECgMJAwAAAA==.',
Fo='Foreverem:BAAALgAECgMJBQAAAA==.',
Fr='Frawnix:BAAALgADCgEJAgAAAA==.Fritopaws:BAABLgAECn8/AAMJAAkJ+h0uAwClAgAJAAkJih0uAwClAgAbAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgYJCQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgcJEgAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJEwAAAA==.Gaska:BAAALgAECggJCAABLgAFFAcJCAABABgLAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn9YAAMYAAkJIREqAgDHAQAYAAkJIREqAgDHAQATAAgJswe+mQA2AQAAAA==.Ginzie:BAAALgAECggJDgAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgAECgMJAwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJEAABLgADCgcJDgACAAAAAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgUJBgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8MAAIVAAQJ4QViSACpAAAVAAQJ4QViSACpAAAuAAQKfykAAhUABwl9F0ouAIIBABUABwl9F0ouAIIBAAAA.Gummypenguin:BAABLgAECn8aAAMZAAgJGhqcTACDAQAZAAgJGhicTACDAQAJAAYJTQzRVQDyAAABLgAFFAkJLQAZADQeAA==.',
Gw='Gwenldoyn:BAABLgAECn8UAAIGAAYJqglaCQCWAAAGAAYJqglaCQCWAAAAAA==.',
Ha='Hadhox:BAABLgAECn8gAAIdAAkJaA4mKgCvAQAdAAkJaA4mKgCvAQABLgAECgkJJwAZAMYUAA==.Hakano:BAABLgAECn8lAAISAAYJrgPlWACmAAASAAYJrgPlWACmAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8nAAIZAAkJxhS1MwANAgAZAAkJxhS1MwANAgAAAA==.Hawkdubya:BAAALgADCgYJBQABLgAECgUJCgACAAAAAA==.Hawkster:BAAALgADCgYJCQABLgAECgUJCQACAAAAAA==.Hawkulees:BAAALgAECgUJCQAAAA==.Hazelnoot:BAABLgAECn8mAAMMAAkJ0BtLLgBIAgAMAAkJ0BtLLgBIAgAhAAYJugWnVgDdAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Heartdonor:BAAALgAECgMJAgABLgAFFAUJGAAPAG4VAA==.Helzer:BAABLgAECn8XAAMOAAkJ1Bu6AQCMAgAOAAkJ1Bu6AQCMAgAaAAkJGhX6AgA1AgABLgAFFAMJBQATAG0PAA==.Hexcist:BAABLgAECn80AAIQAAkJAhMkFQDmAQAQAAkJAhMkFQDmAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn80AAIiAAkJMAk+FgBqAQAiAAkJMAk+FgBqAQAAAA==.',
Ho='Holehbones:BAAALgADCgEJAQAAAA==.Hollyanne:BAABLgAECn8sAAIGAAkJjQuzDgBSAQAGAAkJjQuzDgBSAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBQAbAMUNAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgQJCgABLgAECgYJEAACAAAAAA==.Hornsharp:BAABLgAECn8lAAMKAAcJRB6zIwA5AgAKAAcJRB6zIwA5AgALAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Hunalli:BAAALgAECgUJCAABLgAFFAQJDAAVAOEFAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQJAAMJfBxZGADQAAAJAAIJ0CNZGADQAAAbAAIJRxdkJwCaAAAZAAEJqibUmQBeAAAuAAQKfz0ABAkACQnAJaQDAGoDAAkACAnDJaQDAGoDABsACAldI+AHAKACABkAAwmbJEmTALIAAAAA.',
Ia='Iamu:BAAALgADCgUJBQAAAA==.',
Ic='Iconius:BAAALgAECgQJDAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8SAAMKAAUJMhrxEgA0AQAKAAUJMhrxEgA0AQALAAMJewkhJACHAAAuAAQKfzEAAwoABwmgG7UuAPsBAAoABwmgG7UuAPsBAAsABgmLGg8wAH8BAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQACAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwATABsfAA==.Insaint:BAACLgAFFH8eAAIMAAQJNBi9HgASAQAMAAQJNBi9HgASAQAuAAQKfzcAAgwACQlkHLAuAEYCAAwACQlkHLAuAEYCAAAA.',
Is='Isabellë:BAABLgAECn87AAMXAAkJow/YBQCAAQAXAAkJow/YBQCAAQAlAAIJnANhaQBBAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
It='Ithdorel:BAAALgADCggJDwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIEAAcJAhEfcgBWAQAEAAcJAhEfcgBWAQAAAA==.Jasön:BAAALgAECgEJAQABLgAECgkJGgALAEgSAA==.Jatia:BAAALgADCgEJAQABLgAFFAMJBQAdALgZAA==.',
Je='Jessamine:BAABLgAECn8jAAIPAAkJERsWQAAcAgAPAAkJERsWQAAcAgAAAA==.Jessicafelba:BAABLgAECn8WAAMEAAkJNxoTLgAgAgAEAAgJNxoTLgAgAgAGAAIJVAvkcAA1AAABLgADCgcJDgACAAAAAA==.Jethró:BAAALgADCgIJAgAAAA==.Jetta:BAABLgAECn88AAIeAAgJsxrlAQDgAQAeAAgJsxrlAQDgAQAAAA==.Jezzak:BAABLgAECn8vAAIZAAkJ/hvJBgAeAgAZAAkJ/hvJBgAeAgABLgAECgkJMQAZAAEbAA==.',
Jo='John:BAABLgAFFH8IAAIfAAQJJyCqAgCEAQAfAAQJJyCqAgCEAQAAAA==.Jorien:BAABLgAECn9XAAIZAAkJAxzeGwB+AgAZAAkJAxzeGwB+AgAAAA==.',
Jp='Jp:BAAALgAFFAEJAQAAAA==.Jps:BAAALgAECgYJCAABLgAFFAEJAQACAAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECgkJGAAEAGwZAA==.Justadwarf:BAAALgAECgcJCQAAAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMlAAkJWxhHGAAaAgAlAAkJWxhHGAAaAgAXAAIJmxGcbgBnAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJEAAAAA==.Kaenaya:BAAALgAECgUJBgAAAA==.Kaetii:BAAALgAECgEJAQAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8sAAMdAAkJlx27EAByAgAdAAkJPRy7EAByAgAmAAYJvBhMGwBdAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJFgAmAKAjAA==.Kardels:BAABLgAECn8WAAImAAcJoCPHCgBCAgAmAAcJoCPHCgBCAgAAAA==.Karnadaz:BAAALgAECgEJAQABLgAECgUJDQACAAAAAA==.Karnn:BAACLgAFFH8aAAMnAAcJJBZeDwBDAQAnAAYJORpeDwBDAQASAAIJbAFzIwAyAAAuAAQKfycAAycACAl3JJQKAM8CACcACAl3JJQKAM8CAAEABglfEANVABwBAAAA.Karzuna:BAAALgAECgEJAgAAAA==.Katalight:BAAALgAECgQJAQAAAA==.Kaytana:BAAALgADCgUJCQABLgAECgUJBwACAAAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAPALAdAA==.Kennathus:BAAALgADCgIJAgABLgAECgkJMwAGAFkJAA==.',
Ki='Kiascendance:BAABLgAFFH8FAAIKAAUJfgvlGgDyAAAKAAUJfgvlGgDyAAAAAA==.Kiplet:BAABLgAECn8aAAIlAAkJpBZIJAChAQAlAAkJpBZIJAChAQAAAA==.',
Kn='Knockback:BAAALgAECgUJCgAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Koriane:BAAALgAECgQJBAAAAA==.Korxon:BAABLgAECn8fAAMWAAgJkhfJIgC5AQAWAAgJkhfJIgC5AQAlAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krastikon:BAAALgAECgEJAgAAAA==.Krazilec:BAAALgADCgYJBgABLgADCgYJBgACAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgAUAFgaAA==.',
Ks='Ksyusha:BAABLgAECn8XAAMMAAkJuAqALwCMAAAMAAkJuAqALwCMAAAhAAIJ1QoSFQBfAAAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgQJCAAAAA==.',
['Kä']='Kämi:BAAALgAECgUJBwABLgAECgcJKwAPAEUWAA==.',
La='Lahabrea:BAABLgAECn8fAAMGAAgJBA3wKwAPAQAEAAgJwQpLigAlAQAGAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAACLgAFFH8FAAIRAAIJjRaEFACCAAARAAIJjRaEFACCAAAuAAQKfzMAAxEACAmHH1wBAHICABEACAkbH1wBAHICAB4ABAkmFAMiAPkAAAAA.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAVAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIHAAkJBBhlPQDSAQAHAAkJBBhlPQDSAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgAUAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalarrow:BAAALgAECgYJBgAAAA==.Lethalbimbo:BAABLgAECn8WAAIMAAgJKwtPpgAuAQAMAAgJKwtPpgAuAQAAAA==.Lethallok:BAAALgAECgQJBAAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIKAAcJ0R6tBACCAgAKAAcJ0R6tBACCAgAuAAQKfyIAAwoACQnNI0sQAJUCAAoACAl0I0sQAJUCAAsAAQnnESyFADcAAAAA.Linddrel:BAABLgAECn8XAAMhAAcJEBSBBgBtAQAhAAYJaRSBBgBtAQAMAAcJhxSDrAApAQAAAA==.Littlebitt:BAAALgAFFAIJBQAAAQ==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonarius:BAAALgAECgEJAQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.Lostham:BAAALgAECgQJBgAAAA==.',
Lu='Lunablue:BAAALgAFFAEJAQAAAA==.Lunasblood:BAAALgADCgkJCQAAAA==.',
Ly='Lyv:BAAALgAECgEJAgAAAA==.',
['Lø']='Løllîe:BAABLgAECn8bAAISAAgJaA3pAwBGAQASAAgJaA3pAwBGAQAAAA==.Løllïe:BAAALgADCgYJDAABLgAECggJGwASAGgNAA==.',
Ma='Macdee:BAAALgAECgEJAwABLgAECgkJGgALAEgSAA==.Magatai:BAABLgAECn8cAAIPAAgJOQegnwA8AQAPAAgJOQegnwA8AQAAAA==.Mageless:BAAALgAECgUJBgAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Makagongar:BAAALgAECgIJAwABLgAECggJIwATAPwaAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAACAAAAAA==.Manaster:BAAALgAECgkJDAAAAA==.Mandhos:BAAALgAECgMJAwABLgAECggJIwATAPwaAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwACAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8jAAMTAAgJ/BpmdwB1AQATAAgJfRpmdwB1AQAYAAIJhxpaMwBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAABLgAECn8hAAIPAAkJ1AfvFAArAQAPAAkJ1AfvFAArAQAAAA==.Maynis:BAAALgAECgUJBgAAAA==.',
Mc='Mcbrynhammer:BAABLgAECn8aAAIMAAYJbQ2gHADrAAAMAAYJbQ2gHADrAAAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Methallica:BAAALgAECgYJCwAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMdAAkJLxbZJQDJAQAdAAgJzRbZJQDJAQAmAAEJ3hEmUwAzAAAAAA==.Mikewazowski:BAAALgADCgcJCQAAAA==.Minarii:BAABLgAECn8XAAIXAAgJPRhJAwD0AQAXAAgJPRhJAwD0AQABLgAECgkJNwAPAA0RAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAlAKQWAA==.Misahaviran:BAAALgAECgQJBQABLgAECggJIwATAPwaAA==.Misha:BAAALgAECgEJAwAAAA==.Mishelö:BAAALgAECgIJAgAAAA==.Misla:BAAALgAECgQJBwAAAA==.Misstriix:BAAALgAECgYJBwAAAA==.Mistynite:BAAALgADCgkJGgAAAA==.',
Mo='Mochimochi:BAABLgAECn8UAAMlAAcJjhQBCQAcAQAlAAcJjhQBCQAcAQAXAAEJxQIumgAdAAAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgUJCQABLgAECgkJQgAXALQPAA==.Moonshae:BAABLgAECn8mAAMBAAkJjhJ8KgDZAQABAAkJjhJ8KgDZAQAnAAEJ7Bk2GQBMAAAAAA==.Moosesanta:BAAALgAECgEJAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwAOABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwAOABoYAA==.Mouse:BAABLgAECn8WAAIgAAcJqx9GBgDvAQAgAAcJqx9GBgDvAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.Mustevistust:BAAALgAECgMJAwABLgAECggJIwATAPwaAA==.',
My='Mystiquè:BAAALgAECgUJCQAAAA==.',
['Mö']='Mö:BAAALgADCgEJAQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwATAKsLAA==.Nails:BAABLgAECn8aAAIIAAkJhxMNFwDkAQAIAAkJhxMNFwDkAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naszun:BAAALgADCgQJBAAAAA==.Naviriel:BAAALgAECgUJBQABLgAECgkJHAAnAJ8SAA==.',
Ne='Nethermoon:BAAALgAECgEJAwAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nightray:BAAALgAECgMJAwABLgAFFAIJBQARAI0WAA==.Nikan:BAAALgAECggJEgAAAA==.Ninjadoodles:BAAALgAECgEJAwABLgAFFAIJBwATAKsLAA==.Niralth:BAAALgAECgUJBQAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAACAAAAAA==.Nonsocial:BAAALgAFFAMJAwABLgAFFAkJSgAPAOggAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgAMANAbAA==.Noriisa:BAABLgAECn8xAAIZAAkJARv2KwAtAgAZAAkJARv2KwAtAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIKAAgJghtHIABOAgAKAAgJghtHIABOAgAAAA==.',
Ny='Nyvak:BAABLgAECn8eAAMmAAgJKxB0BQAnAQAmAAgJKxB0BQAnAQAdAAUJ9whgagC4AAAAAA==.',
Od='Odinhand:BAABLgAECn8wAAIOAAkJugtcMgBRAQAOAAkJugtcMgBRAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Oh='Ohgreatdink:BAAALgAECgQJCAAAAA==.',
Ol='Oliissa:BAAALgAECgUJCgAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQACAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIPAAkJmCJeDwAAAwAPAAkJmCJeDwAAAwABLgAFFAYJGwADAGUZAA==.Ozwäldo:BAABLgAFFH8bAAIDAAYJZRkOAgCjAQADAAYJZRkOAgCjAQAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgAECggJEgAAAA==.Panduh:BAACLgAFFH8YAAIPAAUJbhWVDQCvAQAPAAUJbhWVDQCvAQAuAAQKfz8AAg8ACQmpIlgRAPICAA8ACQmpIlgRAPICAAAA.Pandóra:BAABLgAECn8ZAAMXAAYJYQNtXwCaAAAXAAYJYQNtXwCaAAAWAAQJIAOQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMfAAMJ5SRaBQAqAQAfAAMJ5SRaBQAqAQAIAAIJcB7+EADBAAAuAAQKfz0AAx8ACQmjJksAAHcDAB8ACQl1JksAAHcDAAgACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Peppermintxo:BAAALgAECgQJCAABLgAECgYJEAACAAAAAA==.Perceval:BAAALgAECgYJCgAAAA==.',
Ph='Pherrall:BAAALgAECgUJBQABLgAFFAkJKAATAIcbAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAACAAAAAA==.Pinkeepink:BAABLgAECn8uAAIGAAkJUwp/EQAvAQAGAAkJUwp/EQAvAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Polox:BAAALgAECgEJAgAAAA==.Popacooldown:BAAALgAECgIJAgAAAA==.Potangwang:BAABLgAECn8UAAIZAAcJsw3eeABOAQAZAAcJsw3eeABOAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prild:BAAALgAECgEJAQAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8qAAIUAAkJDyJXCACQAgAUAAkJDyJXCACQAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMMAAcJ8Q0WqwAmAQAMAAcJ8Q0WqwAmAQANAAQJ/wZQOwBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMDAAkJ3A3MDwC1AQADAAkJ3A3MDwC1AQALAAcJRgPoaACsAAAAAA==.Raynë:BAAALgAECgYJCgABLgAECgkJJwAZAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Rebecca:BAAALgADCgkJCQAAAA==.Reemo:BAAALgAECgEJAQAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgAUAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8fAAIoAAgJZSAwAQD0AQAoAAgJZSAwAQD0AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCAAcABQmjEgWgAOMAAAAA.Rineli:BAABLgAECn83AAIPAAkJDRHMTwDsAQAPAAkJDRHMTwDsAQAAAA==.Ringadingg:BAABLgAECn80AAITAAkJhSS7BwA3AwATAAkJhSS7BwA3AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAATAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAIAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIlAAgJ7RonFgAhAgAlAAgJ7RonFgAhAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Santobonko:BAABLgAECn8eAAIMAAkJ5hKPDwBkAQAMAAkJ5hKPDwBkAQAAAA==.Saphir:BAAALgAECgQJBAAAAA==.Sarazah:BAACLgAFFH8WAAIMAAgJPyADEgDdAQAMAAgJPyADEgDdAQAuAAQKfzUAAgwACQncJaYCAG4DAAwACQncJaYCAG4DAAAA.',
Sc='Scony:BAABLgAECn8VAAMIAAkJhxLUFwDcAQAIAAgJahTUFwDcAQAfAAUJmQkKFwDBAAAAAA==.Screws:BAAALgADCgYJBgABLgAECgkJGgAIAIcTAA==.Scribs:BAABLgAECn8bAAIZAAgJmANpngAFAQAZAAgJmANpngAFAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMPAAgJtB0/dACRAQAPAAcJbxw/dACRAQAkAAQJTh4SDAARAQABLgAFFAMJBgAUAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selineda:BAAALgAECgIJAwAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Seniko:BAAALgAECgMJAwAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJVwATALwaAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAMJBwABANEWAA==.Severautism:BAAALgAECgMJAwABLgAFFAMJBwABANEWAA==.Severànce:BAAALgADCgQJBAABLgAFFAMJBwABANEWAA==.Sevivify:BAACLgAFFH8HAAMBAAMJ0RZbTgBtAAABAAIJJBJbTgBtAAASAAIJ1AKxTgBnAAAuAAQKfxoABBIACQluD60lAIEBABIACQlHDK0lAIEBACcABQlwEyczADgBAAEACAn8GRoRABIBAAAA.Sevotion:BAABLgAECn8xAAQMAAkJUx0oNgBKAgAMAAgJKB0oNgBKAgAhAAkJSxUCHQAbAgANAAcJog8qLQClAAABLgAFFAMJBwABANEWAA==.',
Sh='Shablammy:BAABLgAECn81AAMKAAkJMiV/AQC7AwAKAAkJMiV/AQC7AwALAAEJ6BCSpQAyAAAAAA==.Shadowginni:BAABLgAECn8bAAMXAAkJlA+YBQCHAQAXAAkJlA+YBQCHAQAWAAUJmQIXGgBfAAAAAA==.Shadownome:BAAALgAECgQJDwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJOQANACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgQJCQAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgAECgUJBQAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgIJAgAAAA==.Silvanosh:BAABLgAECn8aAAIZAAkJWQzFWgCVAQAZAAkJWQzFWgCVAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQbAAkJeBoPEQAjAgAbAAkJZRkPEQAjAgAJAAcJfRd6KADmAQAZAAQJfREB0gCnAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwABLgAFFAEJAQACAAAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJCgAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJEQAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgcJCgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAkJBQAPAKMLAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
So='Sofia:BAAALgADCgcJDgAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sploof:BAAALgAECgkJCQAAAA==.Sprynt:BAACLgAFFH8IAAIBAAcJGAtVFwAYAQABAAcJGAtVFwAYAQAuAAQKfx8AAgEACQlrHDYMANYCAAEACQlrHDYMANYCAAAA.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgUJCgAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAcJEAAQAMAdAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8dAAMXAAkJYRatFwAKAgAXAAkJYRatFwAKAgAlAAEJvQY6cgAqAAABLgAFFAMJBwABANEWAA==.Stonemother:BAAALgAECggJEAAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgACAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.Stàrîñà:BAAALgAECgQJBwAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwAMAMgcAA==.',
Sw='Swampmonster:BAABLgAECn8UAAMKAAYJrhcncwADAQAKAAUJGBUncwADAQALAAMJaQpwjgBUAAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIHAAQJchkLSAAQAQAHAAQJchkLSAAQAQAuAAQKfywAAwcACAkkJAMRAPYCAAcACAnOIwMRAPYCABAABAlLJFE/AP8AAAAA.Swoksaar:BAAALgAFFAEJAQAAAA==.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAABLgAECn8UAAIDAAgJqgcIHwABAQADAAgJqgcIHwABAQAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAFFAIJBQAYANcLAA==.Taurastrage:BAABLgAECn8WAAImAAcJdhuIEwDTAQAmAAcJdhuIEwDTAQABLgAFFAIJBQAYANcLAA==.Taurdk:BAACLgAFFH8FAAIYAAIJ1wufIQB9AAAYAAIJ1wufIQB9AAAuAAQKfyIAAxgACQlbG8gDAKACABgACQlbG8gDAKACABMAAglCBn9OAVMAAAAA.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8LAAIOAAMJix2sJAADAQAOAAMJix2sJAADAQAuAAQKfx8AAg4ACAkmItAMAIoCAA4ACAkmItAMAIoCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAmACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAmACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAmACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJVwATALwaAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgALAKgeAA==.Teetau:BAABLgAECn8+AAIRAAkJfAciMgDhAAARAAkJfAciMgDhAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAjAEEcAA==.Thadregosa:BAABLgAECn9FAAMjAAkJQRxbAgCdAgAjAAkJQRxbAgCdAgAVAAcJwAowZQCrAAAAAA==.Thander:BAAALgAECgEJAQABLgAECgQJCwACAAAAAA==.Thannicus:BAAALgAECgYJDgAAAA==.Thedarkskull:BAAALgAECgEJAgAAAA==.Thordar:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8pAAIaAAkJHh2yDwDVAgAaAAkJHh2yDwDVAgAAAA==.Tiberius:BAAALgADCgYJBgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJKQAaAB4dAA==.Tiffy:BAAALgAECggJDQAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAABLgAECn8YAAInAAkJrBtqBgArAQAnAAkJrBtqBgArAQAAAA==.',
Tm='Tmtglizzy:BAAALgAFFAEJAgAAAA==.',
To='Tokalu:BAABLgAECn8cAAInAAkJnxIyHwCzAQAnAAkJnxIyHwCzAQAAAA==.Tonjudsonson:BAACLgAFFH8hAAIRAAgJHBzLAwDdAQARAAgJHBzLAwDdAQAuAAQKfywAAhEACQmCJfUAAGQDABEACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAILAAkJDwzDNwBZAQALAAkJDwzDNwBZAQAAAA==.Toothléssév:BAAALgAECgIJAgABLgAFFAMJBwABANEWAA==.Totemgranny:BAAALgADCgcJDgAAAA==.Toxix:BAABLgAECn8fAAIDAAkJJSPpAQAOAwADAAkJJSPpAQAOAwAAAA==.',
Tr='Trashao:BAAALgADCgQJBAAAAA==.Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.Trrunks:BAAALgADCgcJBwAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuber:BAAALgAECggJCAAAAA==.Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8zAAIGAAkJWQkoEQAzAQAGAAkJWQkoEQAzAQAAAA==.Twobricks:BAABLgAECn8wAAIaAAkJzhbVJgAZAgAaAAkJzhbVJgAZAgAAAA==.',
Ty='Tyamat:BAAALgAECgEJAQABLgAECgcJGwAJAKYWAA==.Tyrssana:BAABLgAECn8WAAIHAAgJ+RBdGgCvAAAHAAgJ+RBdGgCvAAABLgAFFAcJEQAjAF8KAA==.',
Ud='Udderlydead:BAAALgAECgQJBAAAAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIlAAYJIxrwIgCrAQAlAAYJIxrwIgCrAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8wAAINAAkJXR+fCABMAgANAAkJXR+fCABMAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAACLgAFFH8GAAMMAAIJnw+dTQB6AAAMAAIJnw+dTQB6AAAhAAEJ5g0gKQArAAAuAAQKfxwAAw0ACQmIH+kJAC4CAA0ACQmAG+kJAC4CAAwABQnrHhgaAP8AAAAA.Urlacher:BAAALgAECgMJBQAAAA==.',
Va='Vaccaria:BAAALgAECgQJBAABLgAFFAEJAQACAAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAKANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAABLgAECn8bAAIMAAkJfhQ0CADrAQAMAAkJfhQ0CADrAQAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Velaraeline:BAAALgAECgMJAwAAAA==.Velskud:BAAALgAECgMJAwAAAA==.Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCwABLgAECgkJGAAEAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAInAAUJ1STFCACOAQAnAAUJ1STFCACOAQAuAAQKfxoAAicACAk9I0MEAEgDACcACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJCAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIbAAcJBxlPEgCeAQAbAAcJBxlPEgCeAQAAAA==.Violyt:BAAALgAECgUJCAAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgAWADMYAA==.Visea:BAAALgAECgQJCwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCwAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAgAAAA==.Watevr:BAEBLgAECn8dAAIpAAgJlg1ZAQA7AQApAAgJlg1ZAQA7AQABLgAECgkJawAfAOgcAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwACAAAAAA==.Wesleypriest:BAABLgAECn8fAAMWAAkJBwmuLgBmAQAWAAkJ5giuLgBmAQAlAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgYJEAAAAA==.',
Wr='Wrandanden:BAAALgAECgEJAQAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8wAAINAAkJwRa7CwAKAgANAAkJwRa7CwAKAgAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAPAEkXAA==.',
Xe='Xear:BAAALgADCgkJRgABLgAECggJDQACAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAKANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAfAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIPAAcJSReajQC3AQAPAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMKAAgJQx1RGwBxAgAKAAgJQx1RGwBxAgALAAEJWAjekQAlAAABLgAECgkJJQATACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAIWAAQJlw+rJwANAQAWAAQJlw+rJwANAQABLgAFFAcJGgAKANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAdAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Ys='Yssuplef:BAAALgAECggJDgAAAA==.',
Yu='Yuefei:BAAALgAECgIJAgAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCwAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCwAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAKANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAABLgAECn8XAAIMAAYJFwkJKQCoAAAMAAYJFwkJKQCoAAAAAA==.Zeratule:BAAALgAECgIJAwAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAgAAAA==.Zerm:BAABLgAECn9MAAIMAAkJGx5aGACxAgAMAAkJGx5aGACxAgAAAA==.Zermonk:BAAALgADCgEJAQAAAA==.',
Zi='Zijo:BAAALgAECgcJEAAAAA==.Zinnkura:BAABLgAECn8eAAIKAAkJqw9eCgCEAQAKAAkJqw9eCgCEAQAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
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
