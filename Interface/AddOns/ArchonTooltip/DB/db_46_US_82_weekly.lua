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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','Paladin-Protection','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Hunter-Survival','Evoker-Augmentation','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','Warrior-Protection','Paladin-Holy','Monk-Windwalker','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBwAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8fAAIBAAcJgw43SQBHAQABAAcJgw43SQBHAQAAAA==.Aegennai:BAABLgAECn8sAAICAAkJVwezFQBkAQACAAkJVwezFQBkAQAAAA==.Aegon:BAECLgAFFH8dAAMDAAcJqxxOLwCJAQADAAYJyxtOLwCJAQAEAAEJDSEHFgBmAAAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAUAAwmUHL4pABsBAAAA.Aegondh:BAEBLgAFFH8GAAIGAAYJ6AiBUgD2AAAGAAYJ6AiBUgD2AAABLgAFFAcJHQADAKscAA==.Aeli:BAAALgAECgQJBAABLgAECgcJHwABAIMOAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIHAAIJPBzcLwCoAAAHAAIJPBzcLwCoAAAuAAQKfzYAAgcACQlSHrIOAD8CAAcACQlSHrIOAD8CAAAA.',
Ag='Agilaz:BAABLgAECn8zAAIIAAkJSxvzBQA8AgAIAAkJSxvzBQA8AgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.',
Ak='Akey:BAAALgAECgYJEgAAAQ==.Akhae:BAACLgAFFH8IAAIJAAIJ0BjrWwCUAAAJAAIJ0BjrWwCUAAAuAAQKfyUAAwkACQkVFqQxAO0BAAkACQkVFqQxAO0BAAoACQneDagyAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8pAAICAAcJLhUvFQBrAQACAAcJLhUvFQBrAQAAAA==.Alcadeias:BAABLgAECn8qAAILAAcJFxbQjABYAQALAAcJFxbQjABYAQAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8nAAIMAAkJGhi1GQD+AQAMAAkJGhi1GQD+AQAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8YAAILAAkJSAttrgAmAQALAAkJSAttrgAmAQAAAA==.Andrömëdä:BAABLgAECn8UAAINAAcJRBFaJgBHAQANAAcJRBFaJgBHAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8dAAIOAAYJvAvzCQBqAAAOAAYJvAvzCQBqAAAAAA==.Anveenia:BAAALgAECgEJAQAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJHwABAIMOAA==.',
Aq='Aquindra:BAAALgAECgMJBAAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arluz:BAAALgADCgQJBAAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn82AAIPAAkJuCFxBAD/AgAPAAkJuCFxBAD/AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astérion:BAAALgAFFAEJAQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAEJAQAQAAAAAQ==.',
Ba='Baconpancake:BAAALgAECgcJEwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldpunch:BAAALgAECgQJBQAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgcJEQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAAALgAECgcJEwAAAA==.Barendor:BAAALgADCgYJAgAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMRAAkJIxqfJQBtAgARAAkJIxqfJQBtAgASAAgJOAWHNADHAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECgcJDQAAAA==.Beastlypläyä:BAAALgAECgYJDQAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAQJCAACAB0PAA==.Bessarion:BAAALgADCgYJBgAAAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.Bizmofunyuns:BAAALgAECgEJAgAAAA==.',
Bl='Blacksabbth:BAAALgAECgQJCgAAAA==.Blindhealz:BAACLgAFFH8HAAITAAMJLwqSNgCwAAATAAMJLwqSNgCwAAAuAAQKfzAAAxMACAnMF+AXABUCABMACAnMF+AXABUCABQABQl4C7RLAOAAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAABLgAECn8UAAIVAAcJkw0KIgAEAQAVAAcJkw0KIgAEAQAAAA==.',
Bo='Bonerblast:BAAALgAECgMJBAAAAA==.Boston:BAABLgAECn81AAQRAAkJhyRbEgDbAgARAAkJhyRbEgDbAgASAAcJzA6VKgAEAQAWAAMJhBuZJgCdAAAAAA==.Bowflex:BAAALgAECggJDgAAAA==.',
Br='Braesong:BAAALgADCgYJDQAAAA==.Brewtholomew:BAACLgAFFH8HAAIXAAMJbQhcBwDWAAAXAAMJbQhcBwDWAAAuAAQKfysAAhcACQn1EfBGAM0BABcACQn1EfBGAM0BAAAA.Briggsey:BAABLgAECn8qAAIDAAgJsg0yaQBqAQADAAgJsg0yaQBqAQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBnQQADaAQADAAcJxBjQQADaAQAFAAIJbyBRLwBeAAAAAA==.Brounies:BAABLgAECn8XAAIYAAcJmAgwbADwAAAYAAcJmAgwbADwAAAAAA==.Brunna:BAAALgAECgYJBgAAAA==.Bryce:BAABLgAECn8ZAAILAAgJRBRJbQCUAQALAAgJRBRJbQCUAQAAAA==.Brèanna:BAAALgAECgQJCgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgAECgUJAgAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBQAZAMUNAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJCQAaAHEEAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8HAAIJAAMJKhKkTwC3AAAJAAMJKhKkTwC3AAAuAAQKfzEAAgkACQm7IHwKANQCAAkACQm7IHwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIbAAcJcBgCFwCaAQAbAAcJcBgCFwCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIXAAgJ3QSPnAAIAQAXAAgJ3QSPnAAIAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJCQAAAA==.Caleesia:BAAALgAECgUJAgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAABLgAECn8YAAMIAAYJBxCkGgDZAAAXAAQJ+BFapQD3AAAIAAYJlAukGgDZAAAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwAQAAAAAA==.Carnìfex:BAABLgAECn8pAAMcAAYJ4BpaHAB5AQAcAAYJ4BpaHAB5AQAdAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJBQAAAA==.Catbrin:BAABLgAECn8XAAQeAAkJRiL8CwD6AQAeAAkJRiL8CwD6AQAbAAQJtBc2KgALAQAYAAMJdxakggCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIfAAgJKAznDABcAQAfAAgJKAznDABcAQAAAA==.Cephandrius:BAAALgAECgQJBAAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJHgAKAPMbAA==.Cheetah:BAAALgAECgQJDAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8VAAIdAAkJ/wcZOQBiAQAdAAkJ/wcZOQBiAQAAAA==.Cloudbreaker:BAAALgAECgYJCwAAAA==.Cloudkeg:BAAALgAECgQJCAAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgkJEAAAAA==.',
Cr='Creeönyx:BAAALgAECgEJAQAAAA==.Crunchyjim:BAAALgAECgIJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCggJGQAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIYAAkJBApNSwBhAQAYAAkJBApNSwBhAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8eAAMKAAkJ8xt0KQDJAQAKAAcJshx0KQDJAQAJAAMJWwrfnwCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn9NAAMfAAgJYxqeCgCNAQAHAAgJLhN3HgCiAQAfAAYJqhqeCgCNAQAAAA==.Damnitsu:BAEBLgAECn8jAAMfAAgJxBEDDQBaAQAfAAYJWxUDDQBaAQAHAAgJvA3OKABRAQABLgAECggJTQAfAGMaAA==.Dark:BAAALgADCggJCAAAAA==.Darkcat:BAABLgAECn8rAAIeAAgJlAdHIgD3AAAeAAgJlAdHIgD3AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgQJDAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAISAAkJWBqeDwARAgASAAkJWBqeDwARAgAAAA==.Dear:BAAALgAFFAEJAgAAAA==.Deathberry:BAABLgAECn9DAAIDAAkJuiK8BwAaAwADAAkJuiK8BwAaAwAAAA==.Deathdoodles:BAACLgAFFH8HAAIRAAIJqwvS7QB9AAARAAIJqwvS7QB9AAAuAAQKfyAAAhEACQkkGPg5ABgCABEACQkkGPg5ABgCAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAgAAAA==.Decisively:BAAALgAECgEJAQAAAA==.Deekan:BAABLgAECn8eAAILAAkJwQaRmwA/AQALAAkJwQaRmwA/AQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBwABLgAFFAMJBAAQAAAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8YAAIUAAkJsQsuKwB6AQAUAAkJsQsuKwB6AQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAQAAAAAA==.Devlik:BAAALgAECgUJBQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAILAAgJ5weWrAAkAQALAAgJ5weWrAAkAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgMJAQAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAAALgAECggJEgAAAA==.',
Do='Dobby:BAAALgAECgYJEAAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMgAAkJEiKiAQB4AwAgAAkJEiKiAQB4AwAhAAEJNA52JQA1AAAAAA==.Drivewayhash:BAAALgAECgEJAQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIcAAQJgxgCFwAoAQAcAAQJgxgCFwAoAQAuAAQKfzoAAhwACQmpIBYEAOECABwACQmpIBYEAOECAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQDAAkJwyK9BgAlAwADAAkJmSK9BgAlAwAFAAIJyhOASQCSAAAEAAIJVh6TMQBaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMfAAgJkBIkCADWAQAfAAgJkBIkCADWAQAHAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMOAAkJZyDvEAD1AgAOAAkJZyDvEAD1AgAiAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQAOAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgQJDAAAAA==.',
Er='Erlandis:BAAALgAECgEJAQAAAA==.',
Es='Espii:BAAALgAECgkJAwAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAQAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Ev='Evilorc:BAAALgAECgEJAgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgAQAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezhra:BAAALgADCgUJBQABLgAECgUJAgAQAAAAAA==.Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8rAAMYAAkJuyHKCwADAwAYAAgJnCHKCwADAwAMAAQJDw54YACXAAAAAA==.Fakesaint:BAACLgAFFH8PAAIJAAUJfBi0BADSAAAJAAUJfBi0BADSAAAuAAQKfzUAAgkACQmfIWsIACoDAAkACQmfIWsIACoDAAAA.Fangstorm:BAABLgAECn8yAAIeAAkJdxOZDQDcAQAeAAkJdxOZDQDcAQAAAA==.Farorê:BAABLgAECn8YAAIjAAYJ6BdpKgB1AQAjAAYJ6BdpKgB1AQAAAA==.Fatmann:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIGAAkJ2heILQARAgAGAAkJ2heILQARAgAAAA==.Feldruid:BAAALgAECgEJAgAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8OAAIkAAMJEAYYJAB6AAAkAAMJEAYYJAB6AAAuAAQKf0oAAyQACQlIGNYKAEECACQACQlIGNYKAEECAB0AAgm+A3mYAEEAAAAA.',
Fo='Foreverem:BAAALgAECgMJBQAAAA==.',
Fr='Fritopaws:BAABLgAECn8/AAMIAAkJ+h0uAwClAgAIAAkJih0uAwClAgAZAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgYJCQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJEQAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJEwAAAA==.Gaska:BAAALgAECggJCAABLgAECgkJHwABAGscAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn9LAAMWAAkJUQ5DAAC6AQAWAAkJUQ5DAAC6AQARAAgJswe8mQA2AQAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJEAABLgAECgkJFgADADcaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgUJAgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8JAAIaAAQJcQRXSACpAAAaAAQJcQRXSACpAAAuAAQKfygAAhoABwl9F0kuAIIBABoABwl9F0kuAIIBAAAA.Gummypenguin:BAABLgAECn8VAAMXAAgJGhqcTACDAQAXAAcJiBmcTACDAQAIAAYJTQzRVQDyAAABLgAFFAUJHQAXAMMgAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8fAAIdAAkJHw4mKgCvAQAdAAkJHw4mKgCvAQABLgAECgkJIwAXAMYUAA==.Hakano:BAABLgAECn8lAAIPAAYJrgPlWACmAAAPAAYJrgPlWACmAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8jAAIXAAkJxhS5MwANAgAXAAkJxhS5MwANAgAAAA==.Hawkdubya:BAAALgADCgYJBQABLgAECgUJAgAQAAAAAA==.Hawkulees:BAAALgAECgQJAQAAAA==.Hazelnoot:BAABLgAECn8mAAMLAAkJ0BtLLgBIAgALAAkJ0BtLLgBIAgAlAAYJugWmVgDdAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAINAAkJAhMlFQDmAQANAAkJAhMlFQDmAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn80AAIgAAkJMAk/FgBqAQAgAAkJMAk/FgBqAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8sAAIFAAkJjQu0DgBSAQAFAAkJjQu0DgBSAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBQAZAMUNAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJDQAQAAAAAA==.Hornsharp:BAABLgAECn8jAAMJAAcJzB2xIwA5AgAJAAcJzB2xIwA5AgAKAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAQAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAFFAQJCQAaAHEEAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQIAAMJfBxZGADQAAAIAAIJ0CNZGADQAAAZAAIJRxdiJwCaAAAXAAEJqibTmQBeAAAuAAQKfz0ABAgACQnAJaQDAGoDAAgACAnDJaQDAGoDABkACAldI+EHAKACABcAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgQJDAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8IAAIJAAQJXhQ+OAABAQAJAAQJXhQ+OAABAQAuAAQKfzAAAwkABwl+G7MuAPsBAAkABwl+G7MuAPsBAAoABgmLGg0wAH8BAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQAQAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwARABsfAA==.Insaint:BAACLgAFFH8SAAILAAQJqhaDRAAiAQALAAQJqhaDRAAiAQAuAAQKfzUAAgsACQkJG7EuAEYCAAsACQkJG7EuAEYCAAAA.',
Is='Isabellë:BAABLgAECn8wAAMUAAkJSwrtOAAxAQAUAAkJSwrtOAAxAQAjAAIJnANdaQBBAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
It='Ithdorel:BAAALgADCggJDwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhEecgBWAQADAAcJAhEecgBWAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJSwAdAKUkAA==.',
Je='Jessamine:BAABLgAECn8hAAIOAAkJXxgWQAAcAgAOAAkJXxgWQAAcAgAAAA==.Jessicafelba:BAABLgAECn8WAAMDAAkJNxoSLgAgAgADAAgJNxoSLgAgAgAFAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8yAAIeAAcJcBhxDwC+AQAeAAcJcBhxDwC+AQAAAA==.Jezzak:BAABLgAECn8nAAIXAAgJmhqxQgDaAQAXAAgJmhqxQgDaAQABLgAECgkJMQAXAAEbAA==.',
Jo='John:BAABLgAFFH8IAAIfAAQJJyCqAgCEAQAfAAQJJyCqAgCEAQAAAA==.Jorien:BAABLgAECn9XAAIXAAkJAxzfGwB+AgAXAAkJAxzfGwB+AgAAAA==.',
Jp='Jp:BAAALgAFFAEJAQAAAA==.Jps:BAAALgAECgYJCAABLgAFFAEJAQAQAAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECgkJGAADAGwZAA==.Justadwarf:BAAALgAECgMJAwAAAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMjAAkJWxhHGAAaAgAjAAkJWxhHGAAaAgAUAAIJmxGObgBnAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJEAAAAA==.Kaetii:BAAALgADCgEJAQAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8sAAMdAAkJlx27EAByAgAdAAkJPRy7EAByAgAkAAYJvBhMGwBdAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJFgAkAKAjAA==.Kardels:BAABLgAECn8WAAIkAAcJoCPICgBCAgAkAAcJoCPICgBCAgAAAA==.Karnn:BAACLgAFFH8XAAMmAAUJdh5eDwBDAQAmAAUJdh5eDwBDAQAPAAEJHQFRKgArAAAuAAQKfycAAyYACAl3JJQKAM8CACYACAl3JJQKAM8CAAEABglfEAVVABwBAAAA.Katalight:BAAALgAECgQJAQABLgAECgcJCgAQAAAAAA==.Katrini:BAAALgAECgcJCgAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAOALAdAA==.',
Ki='Kiascendance:BAAALgAECgkJEgAAAA==.Kiplet:BAABLgAECn8aAAIjAAkJpBZDJAChAQAjAAkJpBZDJAChAQAAAA==.',
Kn='Knockback:BAAALgAECgMJBQAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Korxon:BAABLgAECn8fAAMTAAgJkhfFIgC5AQATAAgJkhfFIgC5AQAjAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAQAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgASAFgaAA==.',
Ks='Ksyusha:BAAALgAECgYJEgAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgIJAwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgcJKwAOAEUWAA==.',
La='Lahabrea:BAABLgAECn8fAAMFAAgJBA3wKwAPAQADAAgJwQpHigAlAQAFAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAABLgAECn8oAAMbAAgJbxsbEgDPAQAbAAgJoBobEgDPAQAeAAQJJhQEIgD5AAAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAaAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIGAAkJBBhjPQDSAQAGAAkJBBhjPQDSAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgASAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalarrow:BAAALgADCgIJAgAAAA==.Lethalbimbo:BAABLgAECn8VAAILAAgJKwtQpgAuAQALAAgJKwtQpgAuAQAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIJAAcJ0R6zBACCAgAJAAcJ0R6zBACCAgAuAAQKfyIAAwkACQnNI0sQAJUCAAkACAl0I0sQAJUCAAoAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.Littlebitt:BAAALgAFFAEJAQAAAQ==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Lu='Lunablue:BAAALgAFFAEJAQAAAA==.',
Ly='Lyv:BAAALgAECgEJAgAAAA==.',
['Lø']='Løllîe:BAAALgAECgYJEgAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgYJEgAQAAAAAA==.',
Ma='Macdee:BAAALgAECgEJAQAAAA==.Magatai:BAABLgAECn8aAAIOAAgJ5QafnwA8AQAOAAgJ5QafnwA8AQAAAA==.Mageless:BAAALgAECgUJBgAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Makagongar:BAAALgAECgEJAQAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAAQAAAAAA==.Manaster:BAAALgAECgcJCwAAAA==.Mandhos:BAAALgAECgMJAwAAAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwAQAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8iAAMRAAcJfBlgdwB1AQARAAcJ5xhgdwB1AQAWAAIJhxpaMwBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAAALgAECgUJDAAAAA==.Maynis:BAAALgAECgMJAwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgQJEQAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgYJCwAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMdAAkJLxbYJQDJAQAdAAgJzRbYJQDJAQAkAAEJ3hEiUwAzAAAAAA==.Mikewazowski:BAAALgADCgUJBAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAjAKQWAA==.Misahaviran:BAAALgAECgQJBQAAAA==.Mishelö:BAAALgAECgIJAgAAAA==.Misla:BAAALgAECgEJAQAAAA==.Misstriix:BAAALgAECgYJBgAAAA==.Mistynite:BAAALgADCgkJEwAAAA==.',
Mo='Mochimochi:BAAALgAECgYJDgAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgQJBAABLgAECgkJQgAUALQPAA==.Moonshae:BAABLgAECn8lAAIBAAkJjhJ6KgDZAQABAAkJjhJ6KgDZAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwAMABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwAMABoYAA==.Mouse:BAABLgAECn8WAAInAAcJqx9GBgDvAQAnAAcJqx9GBgDvAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.Mustevistust:BAAALgADCgEJAQAAAA==.',
My='Mystiquè:BAAALgAECgUJAQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwARAKsLAA==.Nails:BAABLgAECn8aAAIHAAkJhxMLFwDkAQAHAAkJhxMLFwDkAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgAECgEJAQABLgAECgkJGgAmAIURAA==.',
Ne='Nethermoon:BAAALgAECgEJAgAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nightray:BAAALgADCgUJBQAAAA==.Nikan:BAAALgADCgYJDAAAAA==.Ninjadoodles:BAAALgAECgEJAQABLgAFFAIJBwARAKsLAA==.Niralth:BAAALgAECgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAAQAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgALANAbAA==.Noriisa:BAABLgAECn8xAAIXAAkJARv2KwAtAgAXAAkJARv2KwAtAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIJAAgJghtGIABOAgAJAAgJghtGIABOAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgMJAwAAAA==.',
Ny='Nyvak:BAABLgAECn8XAAMkAAYJqxCzJgD9AAAkAAYJqxCzJgD9AAAdAAUJ9whdagC4AAAAAA==.',
Od='Odinhand:BAABLgAECn8uAAIMAAkJWwlZMgBRAQAMAAkJWwlZMgBRAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Ol='Oliissa:BAAALgAECgUJAgAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQAQAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIOAAkJmCJhDwAAAwAOAAkJmCJhDwAAAwABLgAFFAQJCAACAB0PAA==.Ozwäldo:BAABLgAFFH8IAAICAAQJHQ+eCgAVAQACAAQJHQ+eCgAVAQAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8YAAIOAAUJbhWVDQCvAQAOAAUJbhWVDQCvAQAuAAQKfz8AAg4ACQmpIlwRAPICAA4ACQmpIlwRAPICAAAA.Pandóra:BAABLgAECn8YAAMUAAYJYQNkXwCaAAAUAAYJYQNkXwCaAAATAAQJXAKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMfAAMJ5SRaBQAqAQAfAAMJ5SRaBQAqAQAHAAIJcB7+EADBAAAuAAQKfzoAAx8ACQmjJksAAHcDAB8ACQl1JksAAHcDAAcACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.',
Ph='Pherrall:BAAALgAECgUJBQABLgAFFAgJHAARAOwaAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAQAAAAAA==.Pinkeepink:BAABLgAECn8oAAIFAAkJDQqAEQAvAQAFAAkJDQqAEQAvAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Polox:BAAALgAECgEJAQAAAA==.Potangwang:BAABLgAECn8UAAIXAAcJsw3geABOAQAXAAcJsw3geABOAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prild:BAAALgAECgEJAQAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Pu='Punchysev:BAACLgAFFH8HAAMBAAMJ0RZSTgBtAAABAAIJJBJSTgBtAAAPAAIJ1AK5TgBnAAAuAAQKfxcABA8ACQluD6olAIEBAA8ACQlHDKolAIEBAAEABQmTFmpJAEYBACYABQlwEyczADgBAAAA.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8oAAISAAkJDyJZCACQAgASAAkJDyJZCACQAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMLAAcJ8Q0XqwAmAQALAAcJ8Q0XqwAmAQAVAAQJ/wZPOwBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMCAAkJ3A3NDwC1AQACAAkJ3A3NDwC1AQAKAAcJRgPmaACsAAAAAA==.Raynë:BAAALgAECgYJCgABLgAECgkJIwAXAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Rebecca:BAAALgADCgkJCQAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgASAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8fAAIoAAgJZSAwAQD0AQAoAAgJZSAwAQD0AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCAAYABQmjEgegAOMAAAAA.Rineli:BAABLgAECn83AAIOAAkJDRHLTwDsAQAOAAkJDRHLTwDsAQAAAA==.Ringadingg:BAABLgAECn80AAIRAAkJhSS7BwA3AwARAAkJhSS7BwA3AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAARAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAHAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIjAAgJ7RonFgAhAgAjAAgJ7RonFgAhAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8QAAILAAcJqRoVEgDdAQALAAcJqRoVEgDdAQAuAAQKfzUAAgsACQncJaYCAG4DAAsACQncJaYCAG4DAAAA.',
Sc='Scony:BAABLgAECn8VAAMHAAkJhxLTFwDcAQAHAAgJahTTFwDcAQAfAAUJmQkIFwDBAAAAAA==.Screws:BAAALgADCgYJBgAAAA==.Scribs:BAABLgAECn8bAAIXAAgJmANpngAFAQAXAAgJmANpngAFAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMOAAgJtB0/dACRAQAOAAcJbxw/dACRAQAiAAQJTh4SDAARAQABLgAFFAMJBgASAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selineda:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJVwARALwaAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAMJBwABANEWAA==.Severautism:BAAALgAECgMJAwABLgAFFAMJBwABANEWAA==.Severànce:BAAALgADCgQJBAABLgAFFAMJBwABANEWAA==.Sevotion:BAABLgAECn8xAAQLAAkJUx0oNgBKAgALAAgJKB0oNgBKAgAlAAkJSxUDHQAbAgAVAAcJog8qLQClAAABLgAFFAMJBwABANEWAA==.',
Sh='Shablammy:BAABLgAECn81AAMJAAkJMiV/AQC7AwAJAAkJMiV/AQC7AwAKAAEJ6BCKpQAyAAAAAA==.Shadownome:BAAALgAECgQJDwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJMwAVACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgMJBAAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgAECgUJBQAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgEJAQAAAA==.Silvanosh:BAABLgAECn8aAAIXAAkJWQzHWgCVAQAXAAkJWQzHWgCVAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQZAAkJeBoREQAjAgAZAAkJZRkREQAjAgAIAAcJfRd6KADmAQAXAAQJfRH60QCnAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJBQAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJDAAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgcJCgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAkJMgAOAHYgAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxw4DADWAgABAAkJaxw4DADWAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgQJAgAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAYJDwANAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8dAAMUAAkJYRatFwAKAgAUAAkJYRatFwAKAgAjAAEJvQY4cgAqAAABLgAFFAMJBwABANEWAA==.Stonemother:BAAALgAECgYJDQAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAQAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwALAMgcAA==.',
Sw='Swampmonster:BAAALgAECgYJEgAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIGAAQJchkZSAAQAQAGAAQJchkZSAAQAQAuAAQKfywAAwYACAkkJAMRAPYCAAYACAnOIwMRAPYCAA0ABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgcJEwAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAFFAIJBQAWANcLAA==.Taurastrage:BAABLgAECn8WAAIkAAcJdhuIEwDTAQAkAAcJdhuIEwDTAQABLgAFFAIJBQAWANcLAA==.Taurdk:BAACLgAFFH8FAAIWAAIJ1wuhIQB9AAAWAAIJ1wuhIQB9AAAuAAQKfyIAAxYACQlbG8gDAKACABYACQlbG8gDAKACABEAAglCBndOAVMAAAAA.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8LAAIMAAMJix2yJAADAQAMAAMJix2yJAADAQAuAAQKfx8AAgwACAkmIs8MAIoCAAwACAkmIs8MAIoCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAkACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAkACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAkACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJVwARALwaAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgAKAKgeAA==.Teetau:BAABLgAECn8+AAIbAAkJfAcgMgDhAAAbAAkJfAcgMgDhAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAhAEEcAA==.Thadregosa:BAABLgAECn9FAAMhAAkJQRxcAgCdAgAhAAkJQRxcAgCdAgAaAAcJwAouZQCrAAAAAA==.Thander:BAAALgAECgEJAQABLgAECgQJCAAQAAAAAA==.Thannicus:BAAALgAECgYJDgAAAA==.Thedarkskull:BAAALgAECgEJAgAAAA==.Thordar:BAAALgADCggJFAAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIYAAkJchyxDwDVAgAYAAkJchyxDwDVAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAYAHIcAA==.Tiffy:BAAALgADCgkJVgAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tintreach:BAAALgAECgYJCwAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAAALgAECgYJEwAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJBwAAAA==.',
To='Tokalu:BAABLgAECn8aAAImAAkJhREyHwCzAQAmAAkJhREyHwCzAQAAAA==.Tonjudsonson:BAACLgAFFH8eAAIbAAYJoyHLAwDdAQAbAAYJoyHLAwDdAQAuAAQKfywAAhsACQmCJfUAAGQDABsACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAIKAAkJDwzBNwBZAQAKAAkJDwzBNwBZAQAAAA==.Totemgranny:BAAALgADCgUJBQAAAA==.Toxix:BAABLgAECn8fAAICAAkJJSPqAQAOAwACAAkJJSPqAQAOAwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8yAAIFAAkJWQkoEQAzAQAFAAkJWQkoEQAzAQAAAA==.Twobricks:BAABLgAECn8uAAIYAAkJERPXJgAZAgAYAAkJERPXJgAZAgAAAA==.',
Ty='Tyrssana:BAAALgAECgYJEgABLgAFFAUJDgAhAEMMAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIjAAYJIxrtIgCrAQAjAAYJIxrtIgCrAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8uAAIVAAkJyRmfCABMAgAVAAkJyRmfCABMAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAABLgAECn8YAAMVAAkJph3pCQAuAgAVAAkJgBvpCQAuAgALAAIJSCAp/gC6AAAAAA==.Urlacher:BAAALgAECgMJBQAAAA==.',
Va='Vaccaria:BAAALgAECgMJAwABLgAECgMJAwAQAAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgYJEgAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCgABLgAECgkJGAADAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAImAAUJ1STFCACOAQAmAAUJ1STFCACOAQAuAAQKfxoAAiYACAk9I0MEAEgDACYACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJCAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIZAAcJBxlPEgCeAQAZAAcJBxlPEgCeAQAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgATADMYAA==.Visea:BAAALgAECgQJCwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCAAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAgAAAA==.Watevr:BAEALgAECgcJDQABLgAECggJTQAfAGMaAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwAQAAAAAA==.Wesleypriest:BAABLgAECn8fAAMTAAkJBwmuLgBmAQATAAkJ5giuLgBmAQAjAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgYJEAAAAA==.',
Wr='Wrandanden:BAAALgADCgUJDAAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8wAAIVAAkJwRa7CwAKAgAVAAkJwRa7CwAKAgAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAOAEkXAA==.',
Xe='Xear:BAAALgADCgkJGQABLgADCgkJVgAQAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAfAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIOAAcJSReajQC3AQAOAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMJAAgJQx1PGwBxAgAJAAgJQx1PGwBxAgAKAAEJWAjekQAlAAABLgAECgkJJQARACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAITAAQJlw+yJwANAQATAAQJlw+yJwANAQABLgAFFAcJGgAJANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAdAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCAAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCAAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAAALgAECgUJDQAAAA==.Zeratule:BAAALgAECgIJAwAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn9MAAILAAkJGx5aGACxAgALAAkJGx5aGACxAgAAAA==.',
Zi='Zijo:BAAALgAECgYJEAAAAA==.Zinnkura:BAAALgAECgYJEwAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8nAAIDAAkJUA2uUQCmAQADAAkJUA2uUQCmAQAAAA==.',
Zv='Zvirä:BAAALgADCgUJAgAAAA==.',
['Ñô']='Ñôg:BAAALgAECgMJAQAAAA==.',
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
