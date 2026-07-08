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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Paladin-Protection','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Druid-Guardian','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Hunter-Survival','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','Warrior-Protection','Paladin-Holy','Monk-Windwalker','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJCgAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8fAAIBAAcJgw43SQBHAQABAAcJgw43SQBHAQAAAA==.Aegennai:BAABLgAECn8sAAICAAkJVwezFQBkAQACAAkJVwezFQBkAQAAAA==.Aegon:BAECLgAFFH8fAAMDAAcJTx8nLwCJAQADAAYJ9h4nLwCJAQAEAAEJDSF+CABjAAAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAUAAwmUHL4pABsBAAAA.Aegondh:BAEBLgAFFH8GAAIGAAYJ6Ah1UgD2AAAGAAYJ6Ah1UgD2AAABLgAFFAcJHwADAE8fAA==.Aeli:BAAALgAECgQJBAABLgAECgcJHwABAIMOAA==.Aelias:BAAALgAECgEJAQABLgAECgcJHwABAIMOAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIHAAIJPBzbLwCoAAAHAAIJPBzbLwCoAAAuAAQKfzYAAgcACQlSHrUOAD8CAAcACQlSHrUOAD8CAAAA.',
Ag='Agilaz:BAABLgAECn80AAIIAAkJeRz0BQA8AgAIAAkJeRz0BQA8AgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.',
Ak='Akey:BAAALgAECgcJFAAAAQ==.Akhae:BAACLgAFFH8IAAIJAAIJ0BjtWwCUAAAJAAIJ0BjtWwCUAAAuAAQKfyUAAwkACQkVFqYxAO0BAAkACQkVFqYxAO0BAAoACQneDaoyAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8qAAICAAcJLhUvFQBrAQACAAcJLhUvFQBrAQAAAA==.Alcadeias:BAABLgAECn8rAAMLAAcJFxbQjABYAQALAAcJFxbQjABYAQAMAAEJWA9dDgAsAAAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alethiah:BAAALgAECgQJBQAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Altrus:BAAALgAECgEJAQAAAA==.Alupindat:BAABLgAECn8nAAINAAkJGhi3GQD+AQANAAkJGhi3GQD+AQAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgAECgMJAwAAAA==.',
An='Anaeda:BAABLgAECn8dAAILAAkJng0/GACwAAALAAkJng0/GACwAAAAAA==.Andrömëdä:BAABLgAECn8UAAIOAAcJRBFdJgBHAQAOAAcJRBFdJgBHAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8iAAIPAAYJhw6tDwABAQAPAAYJhw6tDwABAQAAAA==.Anveenia:BAAALgAECgEJAgAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJHwABAIMOAA==.',
Aq='Aquindra:BAAALgAECgMJBwAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arluz:BAAALgADCgQJBAAAAA==.Arthar:BAAALgAECgQJBAABLgAECggJLAAQAFUcAA==.',
As='Ashvyth:BAABLgAECn82AAIRAAkJuCFxBAD/AgARAAkJuCFxBAD/AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astérion:BAABLgAECn8eAAILAAkJ5hIJCABwAQALAAkJ5hIJCABwAQAAAA==.',
Av='Avaylia:BAAALgAECgEJAQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAEJAQASAAAAAQ==.',
Az='Azurehope:BAAALgAECgEJAQAAAA==.Azurelive:BAAALgAECgEJAQAAAA==.',
Ba='Baconpancake:BAAALgAECgcJEwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldpunch:BAAALgAECgYJBQAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECggJEQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAABLgAECn8VAAINAAgJsQ/3OQArAQANAAgJsQ/3OQArAQAAAA==.Barendor:BAAALgADCgYJAgAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.Bastarta:BAAALgADCggJCAAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMTAAkJIxqfJQBtAgATAAkJIxqfJQBtAgAUAAgJOAWJNADHAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECggJDwAAAA==.Beastlypläyä:BAAALgAECgYJDQAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAUJEQACAFwRAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Bilac:BAAALgAECgEJAQABLgAFFAQJCQAVAHEEAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.Bizmofunyuns:BAAALgAECgEJAgAAAA==.',
Bl='Blacksabbth:BAAALgAECgQJCwAAAA==.Blindhealz:BAACLgAFFH8HAAIWAAMJLwqLNgCwAAAWAAMJLwqLNgCwAAAuAAQKfzAAAxYACAnMF+EXABUCABYACAnMF+EXABUCABcABQl4C7hLAOAAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAABLgAECn8UAAIMAAcJkw0LIgAEAQAMAAcJkw0LIgAEAQAAAA==.',
Bo='Bonerblast:BAAALgAECgMJBQAAAA==.Boston:BAABLgAECn81AAQTAAkJhyRdEgDbAgATAAkJhyRdEgDbAgAUAAcJzA6WKgAEAQAYAAMJhBuYJgCdAAAAAA==.Bowflex:BAABLgAECn8UAAIZAAgJRw9VCwBAAQAZAAgJRw9VCwBAAQAAAA==.',
Br='Braesong:BAAALgAECgQJBgAAAA==.Branden:BAAALgADCgIJAgAAAA==.Brewtholomew:BAACLgAFFH8HAAIZAAMJbQiUJwDKAAAZAAMJbQiUJwDKAAAuAAQKfysAAhkACQn1EfFGAM0BABkACQn1EfFGAM0BAAAA.Briggsey:BAABLgAECn8qAAIDAAgJsg0zaQBqAQADAAgJsg0zaQBqAQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBnSQADaAQADAAcJxBjSQADaAQAFAAIJbyBSLwBeAAAAAA==.Brounies:BAABLgAECn8ZAAIaAAkJyAgubADwAAAaAAkJyAgubADwAAAAAA==.Brunna:BAAALgAECgYJCQAAAA==.Bryce:BAABLgAECn8ZAAILAAgJRBRFbQCUAQALAAgJRBRFbQCUAQAAAA==.Brèanna:BAAALgAECgQJCgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgAECgUJAgAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBQAbAMUNAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJCQAVAHEEAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8HAAIJAAMJKhKpTwC3AAAJAAMJKhKpTwC3AAAuAAQKfzEAAgkACQm8IHwKANQCAAkACQm8IHwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIQAAcJcBgCFwCaAQAQAAcJcBgCFwCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIZAAgJ3QSQnAAIAQAZAAgJ3QSQnAAIAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJCQAAAA==.Caleesia:BAAALgAECgUJAgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAABLgAECn8ZAAMIAAYJjRKlGgDZAAAZAAQJ+BFfpQD3AAAIAAYJPhClGgDZAAAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwASAAAAAA==.Carnìfex:BAABLgAECn8qAAMcAAYJ4BpbHAB5AQAcAAYJ4BpbHAB5AQAdAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJBQAAAA==.Catbrin:BAABLgAECn8XAAQeAAkJRiL9CwD6AQAeAAkJRiL9CwD6AQAQAAQJtBc2KgALAQAaAAMJdxajggCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIfAAgJKAzlDABcAQAfAAgJKAzlDABcAQAAAA==.Cephandrius:BAAALgAECgQJBAABLgAECggJLAAQAFUcAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Chatpile:BAAALgADCgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJIAAKAJMcAA==.Cheetah:BAAALgAECgQJDAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8VAAIdAAkJ/wcaOQBiAQAdAAkJ/wcaOQBiAQAAAA==.Cloudbreaker:BAAALgAECgYJCwAAAA==.Cloudkeg:BAAALgAECgQJCwAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgkJEAAAAA==.',
Cr='Creeönyx:BAAALgAECgEJAQAAAA==.Crunchyjim:BAAALgAECgIJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCggJGQAAAA==.',
Cy='Cylord:BAAALgADCgIJAgAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIaAAkJBApISwBhAQAaAAkJBApISwBhAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8gAAMKAAkJkxx0KQDJAQAKAAgJjB10KQDJAQAJAAMJWwrlnwCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn9iAAQfAAkJrRyqAACfAQAfAAYJdByqAACfAQAHAAkJ/BVDAwBBAQAgAAMJyAs/AwBaAAAAAA==.Damnitsu:BAEBLgAECn8uAAQHAAkJKxKSAgBqAQAHAAkJEA+SAgBqAQAfAAYJWxUCDQBaAQAgAAUJ7RBzAQDSAAABLgAECgkJYgAfAK0cAA==.Damur:BAAALgADCgQJBAABLgAECgkJMgAFAFkJAA==.Dark:BAAALgAECgYJBgAAAA==.Darkcat:BAABLgAECn8rAAIeAAgJlAdFIgD3AAAeAAgJlAdFIgD3AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgQJDAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAIUAAkJWBqdDwARAgAUAAkJWBqdDwARAgAAAA==.Dear:BAAALgAFFAEJBAAAAA==.Deathberry:BAABLgAECn9EAAIDAAkJuiK8BwAaAwADAAkJuiK8BwAaAwAAAA==.Deathdoodles:BAACLgAFFH8HAAITAAIJqwvP7QB9AAATAAIJqwvP7QB9AAAuAAQKfyAAAhMACQkkGPw5ABgCABMACQkkGPw5ABgCAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAgAAAA==.Decisively:BAAALgAECgEJAQAAAA==.Deekan:BAABLgAECn8gAAILAAkJNAePmwA/AQALAAkJNAePmwA/AQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBwABLgAFFAMJBAASAAAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8YAAIXAAkJsQsxKwB6AQAXAAkJsQsxKwB6AQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQASAAAAAA==.Devlik:BAAALgAECgUJBQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAILAAgJ5weVrAAkAQALAAgJ5weVrAAkAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgMJAQAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAABLgAECn8UAAIZAAgJJgvhFQDIAAAZAAgJJgvhFQDIAAAAAA==.',
Do='Dobby:BAAALgAECgcJEgAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMhAAkJEiKiAQB4AwAhAAkJEiKiAQB4AwAiAAEJNA53JQA1AAAAAA==.Drivewayhash:BAAALgAECgEJAQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIcAAQJgxj7FgAoAQAcAAQJgxj7FgAoAQAuAAQKfzoAAhwACQmpIBYEAOECABwACQmpIBYEAOECAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQDAAkJwyK9BgAlAwADAAkJmSK9BgAlAwAFAAIJyhOASQCSAAAEAAIJVh6TMQBaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMfAAgJkBIkCADWAQAfAAgJkBIkCADWAQAHAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elleneo:BAAALgAECgQJBAAAAA==.Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMPAAkJZyDrEAD1AgAPAAkJZyDrEAD1AgAjAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIwAPABEbAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgQJDAAAAA==.',
Er='Erlandis:BAAALgAECgEJAQAAAA==.',
Es='Espii:BAAALgAECgkJAwAAAA==.Estella:BAAALgADCgEJAQAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwASAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Eu='Euandros:BAAALgAECgEJAQAAAA==.',
Ev='Evilorc:BAAALgAECgEJAgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgASAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezhra:BAAALgADCgYJBQABLgAECgUJAgASAAAAAA==.Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8rAAMaAAkJuyHKCwADAwAaAAgJnCHKCwADAwANAAQJDw59YACXAAAAAA==.Fakesaint:BAACLgAFFH8QAAIJAAUJfBiXEQD+AAAJAAUJfBiXEQD+AAAuAAQKfzgAAwkACQlsImgIACoDAAkACQlsImgIACoDAAoAAQnEGA8VAEcAAAAA.Fangstorm:BAABLgAECn8yAAIeAAkJdxOaDQDcAQAeAAkJdxOaDQDcAQAAAA==.Farorê:BAABLgAECn8YAAIkAAYJ6BduKgB1AQAkAAYJ6BduKgB1AQAAAA==.Fatmann:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIGAAkJ2heGLQARAgAGAAkJ2heGLQARAgAAAA==.Feldruid:BAAALgAECgEJAgAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8RAAIlAAMJWwcuEQBjAAAlAAMJWwcuEQBjAAAuAAQKf0sAAyUACQlIGNYKAEECACUACQlIGNYKAEECAB0AAgm+A36YAEEAAAAA.',
Fo='Foreverem:BAAALgAECgMJBQAAAA==.',
Fr='Fritopaws:BAABLgAECn8/AAMIAAkJ+h0uAwClAgAIAAkJih0uAwClAgAbAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgYJCQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJEQAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJEwAAAA==.Gaska:BAAALgAECggJCAABLgAECgkJHwABAGscAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn9PAAMYAAkJfA4wAQCrAQAYAAkJfA4wAQCrAQATAAgJswe+mQA2AQAAAA==.Ginzie:BAAALgAECggJDgAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJEAABLgAECgkJFgADADcaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgUJAgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8JAAIVAAQJcQRiSACpAAAVAAQJcQRiSACpAAAuAAQKfykAAhUABwl9F0ouAIIBABUABwl9F0ouAIIBAAAA.Gummypenguin:BAABLgAECn8aAAMZAAgJGhpRFgDEAAAIAAYJTQzRVQDyAAAZAAgJGhhRFgDEAAABLgAFFAUJHQAZAMMgAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8fAAIdAAkJHw4mKgCvAQAdAAkJHw4mKgCvAQABLgAECgkJJwAZAMYUAA==.Hakano:BAABLgAECn8lAAIRAAYJrgPlWACmAAARAAYJrgPlWACmAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8nAAIZAAkJxhS1MwANAgAZAAkJxhS1MwANAgAAAA==.Hawkdubya:BAAALgADCgYJBQABLgAECgUJAgASAAAAAA==.Hawkulees:BAAALgAECgQJAQAAAA==.Hazelnoot:BAABLgAECn8mAAMLAAkJ0BtLLgBIAgALAAkJ0BtLLgBIAgAmAAYJugWnVgDdAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAIOAAkJAhMkFQDmAQAOAAkJAhMkFQDmAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn80AAIhAAkJMAk+FgBqAQAhAAkJMAk+FgBqAQAAAA==.',
Ho='Holehbones:BAAALgADCgEJAQAAAA==.Hollyanne:BAABLgAECn8sAAIFAAkJjQuzDgBSAQAFAAkJjQuzDgBSAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBQAbAMUNAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJDQASAAAAAA==.Hornsharp:BAABLgAECn8kAAMJAAcJRB6zIwA5AgAJAAcJRB6zIwA5AgAKAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAFFAQJCQAVAHEEAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQIAAMJfBxZGADQAAAIAAIJ0CNZGADQAAAbAAIJRxdkJwCaAAAZAAEJqibUmQBeAAAuAAQKfz0ABAgACQnAJaQDAGoDAAgACAnDJaQDAGoDABsACAldI+AHAKACABkAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgQJDAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8NAAMJAAQJpBixFADiAAAJAAQJpBixFADiAAAKAAIJwgnEGgB2AAAuAAQKfzAAAwkABwl+G7UuAPsBAAkABwl+G7UuAPsBAAoABgmLGg8wAH8BAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQASAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwATABsfAA==.Insaint:BAACLgAFFH8SAAILAAQJqhZ2RAAiAQALAAQJqhZ2RAAiAQAuAAQKfzUAAgsACQkJG7AuAEYCAAsACQkJG7AuAEYCAAAA.',
Is='Isabellë:BAABLgAECn8wAAMXAAkJUQrwOAAxAQAXAAkJUQrwOAAxAQAkAAIJnANhaQBBAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
It='Ithdorel:BAAALgADCggJDwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhEfcgBWAQADAAcJAhEfcgBWAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJSwAdAKUkAA==.',
Je='Jessamine:BAABLgAECn8jAAIPAAkJERsWQAAcAgAPAAkJERsWQAAcAgAAAA==.Jessicafelba:BAABLgAECn8WAAMDAAkJNxoTLgAgAgADAAgJNxoTLgAgAgAFAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8zAAIeAAcJcBhyDwC+AQAeAAcJcBhyDwC+AQAAAA==.Jezzak:BAABLgAECn8vAAIZAAkJ/htsAwArAgAZAAkJ/htsAwArAgABLgAECgkJMQAZAAEbAA==.',
Jo='John:BAABLgAFFH8IAAIfAAQJJyCqAgCEAQAfAAQJJyCqAgCEAQAAAA==.Jorien:BAABLgAECn9XAAIZAAkJAxzeGwB+AgAZAAkJAxzeGwB+AgAAAA==.',
Jp='Jp:BAAALgAFFAEJAQAAAA==.Jps:BAAALgAECgYJCAABLgAFFAEJAQASAAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECgkJGAADAGwZAA==.Justadwarf:BAAALgAECgcJCAAAAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMkAAkJWxhHGAAaAgAkAAkJWxhHGAAaAgAXAAIJmxGcbgBnAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJEAAAAA==.Kaenaya:BAAALgADCgYJBgAAAA==.Kaetii:BAAALgADCgEJAQAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8sAAMdAAkJlx27EAByAgAdAAkJPRy7EAByAgAlAAYJvBhMGwBdAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJFgAlAKAjAA==.Kardels:BAABLgAECn8WAAIlAAcJoCPHCgBCAgAlAAcJoCPHCgBCAgAAAA==.Karnn:BAACLgAFFH8YAAMnAAYJtxheDwBDAQAnAAUJdh5eDwBDAQARAAIJbAFbHAA3AAAuAAQKfycAAycACAl3JJQKAM8CACcACAl3JJQKAM8CAAEABglfEANVABwBAAAA.Karzuna:BAAALgAECgEJAgAAAA==.Katalight:BAAALgAECgQJAQABLgAECggJCgASAAAAAA==.Katrini:BAAALgAECggJCgAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAPALAdAA==.',
Ki='Kiascendance:BAAALgAECgkJEgAAAA==.Kiplet:BAABLgAECn8aAAIkAAkJpBZIJAChAQAkAAkJpBZIJAChAQAAAA==.',
Kn='Knockback:BAAALgAECgUJCgAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Koriane:BAAALgAECgEJAQAAAA==.Korxon:BAABLgAECn8fAAMWAAgJkhfJIgC5AQAWAAgJkhfJIgC5AQAkAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krastikon:BAAALgAECgEJAQAAAA==.Krazilec:BAAALgADCgYJBgABLgADCgYJBgASAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgAUAFgaAA==.',
Ks='Ksyusha:BAABLgAECn8UAAMLAAcJjgmx3ADiAAALAAYJjgmx3ADiAAAmAAIJ1QraDgBLAAAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgIJAwAAAA==.',
['Kä']='Kämi:BAAALgAECgMJAwABLgAECgcJKwAPAEUWAA==.',
La='Lahabrea:BAABLgAECn8fAAMFAAgJBA3wKwAPAQADAAgJwQpLigAlAQAFAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAABLgAECn8sAAMQAAgJVRwbEgDPAQAQAAgJhRsbEgDPAQAeAAQJJhQDIgD5AAAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAVAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIGAAkJBBhlPQDSAQAGAAkJBBhlPQDSAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgAUAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalarrow:BAAALgAECgYJBgAAAA==.Lethalbimbo:BAABLgAECn8WAAILAAgJKwtPpgAuAQALAAgJKwtPpgAuAQAAAA==.Lethallok:BAAALgADCgMJAwAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIJAAcJ0R6tBACCAgAJAAcJ0R6tBACCAgAuAAQKfyIAAwkACQnNI0sQAJUCAAkACAl0I0sQAJUCAAoAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.Littlebitt:BAAALgAFFAEJAQAAAQ==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonarius:BAAALgAECgEJAQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Lu='Lunablue:BAAALgAFFAEJAQAAAA==.',
Ly='Lyv:BAAALgAECgEJAgAAAA==.',
['Lø']='Løllîe:BAABLgAECn8UAAIRAAcJfQkiTADOAAARAAcJfQkiTADOAAAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgcJFAARAH0JAA==.',
Ma='Macdee:BAAALgAECgEJAgAAAA==.Magatai:BAABLgAECn8cAAIPAAgJOQegnwA8AQAPAAgJOQegnwA8AQAAAA==.Mageless:BAAALgAECgUJBgAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Makagongar:BAAALgAECgIJAgABLgAECgcJIgATAHwZAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAASAAAAAA==.Manaster:BAAALgAECggJCwAAAA==.Mandhos:BAAALgAECgMJAwABLgAECgcJIgATAHwZAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwASAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8iAAMTAAcJfBlmdwB1AQATAAcJ5xhmdwB1AQAYAAIJhxpaMwBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAABLgAECn8YAAIPAAcJIwY8GgCjAAAPAAcJIwY8GgCjAAAAAA==.Maynis:BAAALgAECgMJAwAAAA==.',
Mc='Mcbrynhammer:BAABLgAECn8UAAILAAQJewzmHQCKAAALAAQJewzmHQCKAAAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgYJCwAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMdAAkJLxbZJQDJAQAdAAgJzRbZJQDJAQAlAAEJ3hEmUwAzAAAAAA==.Mikewazowski:BAAALgADCgUJBAAAAA==.Minarii:BAAALgAECgYJCgABLgAECgkJNwAPAA0RAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAkAKQWAA==.Misahaviran:BAAALgAECgQJBQABLgAECgcJIgATAHwZAA==.Misha:BAAALgAECgEJAgAAAA==.Mishelö:BAAALgAECgIJAgAAAA==.Misla:BAAALgAECgMJBQAAAA==.Misstriix:BAAALgAECgYJBgAAAA==.Mistynite:BAAALgADCgkJGgAAAA==.',
Mo='Mochimochi:BAAALgAECgcJEAAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgUJCQABLgAECgkJQgAXALQPAA==.Moonshae:BAABLgAECn8mAAMBAAkJjhJ8KgDZAQABAAkJjhJ8KgDZAQAnAAEJ7BlnEABMAAAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwANABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwANABoYAA==.Mouse:BAABLgAECn8WAAIgAAcJqx9GBgDvAQAgAAcJqx9GBgDvAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.Mustevistust:BAAALgADCgEJAQABLgAECgcJIgATAHwZAA==.',
My='Mystiquè:BAAALgAECgUJAQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwATAKsLAA==.Nails:BAABLgAECn8aAAIHAAkJhxMNFwDkAQAHAAkJhxMNFwDkAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgAECgUJBQABLgAECgkJHAAnAJ8SAA==.',
Ne='Nethermoon:BAAALgAECgEJAwAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nightray:BAAALgADCgUJBQABLgAECggJLAAQAFUcAA==.Nikan:BAAALgAECgYJDAAAAA==.Ninjadoodles:BAAALgAECgEJAwABLgAFFAIJBwATAKsLAA==.Niralth:BAAALgAECgUJBQAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAASAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgALANAbAA==.Noriisa:BAABLgAECn8xAAIZAAkJARv2KwAtAgAZAAkJARv2KwAtAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIJAAgJghtHIABOAgAJAAgJghtHIABOAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgMJAwAAAA==.',
Ny='Nyvak:BAABLgAECn8ZAAMlAAcJLw+0JgD9AAAlAAcJLw+0JgD9AAAdAAUJ9whgagC4AAAAAA==.',
Od='Odinhand:BAABLgAECn8wAAINAAkJugtcMgBRAQANAAkJugtcMgBRAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Ol='Oliissa:BAAALgAECgUJAgAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQASAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIPAAkJmCJeDwAAAwAPAAkJmCJeDwAAAwABLgAFFAUJEQACAFwRAA==.Ozwäldo:BAABLgAFFH8RAAICAAUJXBFnAwAUAQACAAUJXBFnAwAUAQAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgAECgcJCQAAAA==.Panduh:BAACLgAFFH8YAAIPAAUJbhWVDQCvAQAPAAUJbhWVDQCvAQAuAAQKfz8AAg8ACQmpIlgRAPICAA8ACQmpIlgRAPICAAAA.Pandóra:BAABLgAECn8YAAMXAAYJYQNtXwCaAAAXAAYJYQNtXwCaAAAWAAQJXAKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMfAAMJ5SRaBQAqAQAfAAMJ5SRaBQAqAQAHAAIJcB7+EADBAAAuAAQKfz0AAx8ACQmjJksAAHcDAB8ACQl1JksAAHcDAAcACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Peppermintxo:BAAALgAECgEJAgAAAA==.Perceval:BAAALgAECgYJCgAAAA==.',
Ph='Pherrall:BAAALgAECgUJBQABLgAFFAgJIAATAOwaAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAASAAAAAA==.Pinkeepink:BAABLgAECn8tAAIFAAkJUwp/EQAvAQAFAAkJUwp/EQAvAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Polox:BAAALgAECgEJAgAAAA==.Potangwang:BAABLgAECn8UAAIZAAcJsw3eeABOAQAZAAcJsw3eeABOAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prild:BAAALgAECgEJAQAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Pu='Punchysev:BAACLgAFFH8HAAMBAAMJ0RZbTgBtAAABAAIJJBJbTgBtAAARAAIJ1AKxTgBnAAAuAAQKfxcABBEACQluD60lAIEBABEACQlHDK0lAIEBAAEABQmTFmpJAEYBACcABQlwEyczADgBAAAA.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8qAAIUAAkJDyJXCACQAgAUAAkJDyJXCACQAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMLAAcJ8Q0WqwAmAQALAAcJ8Q0WqwAmAQAMAAQJ/wZQOwBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMCAAkJ3A3MDwC1AQACAAkJ3A3MDwC1AQAKAAcJRgPoaACsAAAAAA==.Raynë:BAAALgAECgYJCgABLgAECgkJJwAZAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Rebecca:BAAALgADCgkJCQAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgAUAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8fAAIoAAgJZSAwAQD0AQAoAAgJZSAwAQD0AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCAAYABQmjEgWgAOMAAAAA.Rineli:BAABLgAECn83AAIPAAkJDRHMTwDsAQAPAAkJDRHMTwDsAQAAAA==.Ringadingg:BAABLgAECn80AAITAAkJhSS7BwA3AwATAAkJhSS7BwA3AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAATAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAHAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIkAAgJ7RonFgAhAgAkAAgJ7RonFgAhAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8UAAILAAgJCRwDEgDdAQALAAgJCRwDEgDdAQAuAAQKfzUAAgsACQncJaYCAG4DAAsACQncJaYCAG4DAAAA.',
Sc='Scony:BAABLgAECn8VAAMHAAkJhxLUFwDcAQAHAAgJahTUFwDcAQAfAAUJmQkKFwDBAAAAAA==.Screws:BAAALgADCgYJBgABLgAECgkJGgAHAIcTAA==.Scribs:BAABLgAECn8bAAIZAAgJmANpngAFAQAZAAgJmANpngAFAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMPAAgJtB0/dACRAQAPAAcJbxw/dACRAQAjAAQJTh4SDAARAQABLgAFFAMJBgAUAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selineda:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Seniko:BAAALgAECgMJAwAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJVwATALwaAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAMJBwABANEWAA==.Severautism:BAAALgAECgMJAwABLgAFFAMJBwABANEWAA==.Severànce:BAAALgADCgQJBAABLgAFFAMJBwABANEWAA==.Sevotion:BAABLgAECn8xAAQLAAkJUx0oNgBKAgALAAgJKB0oNgBKAgAmAAkJSxUCHQAbAgAMAAcJog8qLQClAAABLgAFFAMJBwABANEWAA==.',
Sh='Shablammy:BAABLgAECn81AAMJAAkJMiV/AQC7AwAJAAkJMiV/AQC7AwAKAAEJ6BCSpQAyAAAAAA==.Shadownome:BAAALgAECgQJDwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJNAAMACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgQJCQAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgAECgUJBQAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgEJAQAAAA==.Silvanosh:BAABLgAECn8aAAIZAAkJWQzFWgCVAQAZAAkJWQzFWgCVAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQbAAkJeBoPEQAjAgAbAAkJZRkPEQAjAgAIAAcJfRd6KADmAQAZAAQJfREB0gCnAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwABLgAECgQJBAASAAAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJCAAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJEQAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgcJCgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAkJNQAPAHYgAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxw2DADWAgABAAkJaxw2DADWAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgQJAgAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAYJDwAOAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8dAAMXAAkJYRatFwAKAgAXAAkJYRatFwAKAgAkAAEJvQY6cgAqAAABLgAFFAMJBwABANEWAA==.Stonemother:BAAALgAECgcJDwAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgASAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.Stàrîñà:BAAALgAECgQJBAAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwALAMgcAA==.',
Sw='Swampmonster:BAAALgAECgYJEgAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIGAAQJchkLSAAQAQAGAAQJchkLSAAQAQAuAAQKfywAAwYACAkkJAMRAPYCAAYACAnOIwMRAPYCAA4ABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECggJEwAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAFFAIJBQAYANcLAA==.Taurastrage:BAABLgAECn8WAAIlAAcJdhuIEwDTAQAlAAcJdhuIEwDTAQABLgAFFAIJBQAYANcLAA==.Taurdk:BAACLgAFFH8FAAIYAAIJ1wufIQB9AAAYAAIJ1wufIQB9AAAuAAQKfyIAAxgACQlbG8gDAKACABgACQlbG8gDAKACABMAAglCBn9OAVMAAAAA.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8LAAINAAMJix2sJAADAQANAAMJix2sJAADAQAuAAQKfx8AAg0ACAkmItAMAIoCAA0ACAkmItAMAIoCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAlACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAlACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAlACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJVwATALwaAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgAKAKgeAA==.Teetau:BAABLgAECn8+AAIQAAkJfAciMgDhAAAQAAkJfAciMgDhAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAiAEEcAA==.Thadregosa:BAABLgAECn9FAAMiAAkJQRxbAgCdAgAiAAkJQRxbAgCdAgAVAAcJwAowZQCrAAAAAA==.Thander:BAAALgAECgEJAQABLgAECgQJCwASAAAAAA==.Thannicus:BAAALgAECgYJDgAAAA==.Thedarkskull:BAAALgAECgEJAgAAAA==.Thordar:BAAALgADCggJFQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIaAAkJchyyDwDVAgAaAAkJchyyDwDVAgAAAA==.Tiberius:BAAALgADCgYJBgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAaAHIcAA==.Tiffy:BAAALgAECgYJBgAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tintreach:BAAALgAECgYJCwAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAABLgAECn8VAAInAAcJNRtLIQCkAQAnAAcJNRtLIQCkAQAAAA==.',
Tm='Tmtglizzy:BAAALgAFFAEJAgAAAA==.',
To='Tokalu:BAABLgAECn8cAAInAAkJnxIyHwCzAQAnAAkJnxIyHwCzAQAAAA==.Tonjudsonson:BAACLgAFFH8fAAIQAAcJAh/LAwDdAQAQAAcJAh/LAwDdAQAuAAQKfywAAhAACQmCJfUAAGQDABAACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAIKAAkJDwzDNwBZAQAKAAkJDwzDNwBZAQAAAA==.Totemgranny:BAAALgADCgYJBQAAAA==.Toxix:BAABLgAECn8fAAICAAkJJSPpAQAOAwACAAkJJSPpAQAOAwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8yAAIFAAkJWQkoEQAzAQAFAAkJWQkoEQAzAQAAAA==.Twobricks:BAABLgAECn8wAAIaAAkJzhbVJgAZAgAaAAkJzhbVJgAZAgAAAA==.',
Ty='Tyrssana:BAABLgAECn8UAAIGAAcJZxDJkAD/AAAGAAcJZxDJkAD/AAABLgAFFAYJDwAiAIsKAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIkAAYJIxrwIgCrAQAkAAYJIxrwIgCrAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8wAAIMAAkJXR+fCABMAgAMAAkJXR+fCABMAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAABLgAECn8bAAMMAAkJiB/pCQAuAgAMAAkJgBvpCQAuAgALAAUJ6x6kDgAHAQAAAA==.Urlacher:BAAALgAECgMJBQAAAA==.',
Va='Vaccaria:BAAALgAECgQJBAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAABLgAECn8UAAILAAcJqQ3qIAB1AAALAAcJqQ3qIAB1AAAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Velskud:BAAALgAECgMJAwAAAA==.Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCwABLgAECgkJGAADAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAInAAUJ1STFCACOAQAnAAUJ1STFCACOAQAuAAQKfxoAAicACAk9I0MEAEgDACcACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJCAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIbAAcJBxlPEgCeAQAbAAcJBxlPEgCeAQAAAA==.Violyt:BAAALgAECgUJBwAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgAWADMYAA==.Visea:BAAALgAECgQJCwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCwAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAgAAAA==.Watevr:BAEBLgAECn8dAAIpAAgJlg28AAA8AQApAAgJlg28AAA8AQABLgAECgkJYgAfAK0cAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwASAAAAAA==.Wesleypriest:BAABLgAECn8fAAMWAAkJBwmuLgBmAQAWAAkJ5giuLgBmAQAkAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgYJEAAAAA==.',
Wr='Wrandanden:BAAALgAECgEJAQAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8wAAIMAAkJwRa7CwAKAgAMAAkJwRa7CwAKAgAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAPAEkXAA==.',
Xe='Xear:BAAALgADCgkJIgABLgAECgYJBgASAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAfAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIPAAcJSReajQC3AQAPAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMJAAgJQx1RGwBxAgAJAAgJQx1RGwBxAgAKAAEJWAjekQAlAAABLgAECgkJJQATACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAIWAAQJlw+rJwANAQAWAAQJlw+rJwANAQABLgAFFAcJGgAJANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAdAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgAECgIJAgAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCwAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCwAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAAALgAECgYJEAAAAA==.Zeratule:BAAALgAECgIJAwAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAgAAAA==.Zerm:BAABLgAECn9MAAILAAkJGx5aGACxAgALAAkJGx5aGACxAgAAAA==.',
Zi='Zijo:BAAALgAECgcJEAAAAA==.Zinnkura:BAABLgAECn8VAAIJAAcJFhCLWgBOAQAJAAcJFhCLWgBOAQAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8sAAIDAAkJlg2uUQCmAQADAAkJlg2uUQCmAQAAAA==.',
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
