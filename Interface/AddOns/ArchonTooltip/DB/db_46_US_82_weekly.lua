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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Balance','Monk-Brewmaster','Mage-Frost','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','DemonHunter-Devourer','Warrior-Protection','Hunter-Survival','Paladin-Holy','DemonHunter-Havoc','Priest-Holy','Monk-Windwalker','Paladin-Protection','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBgAAAA==.Adunal:BAAALgAECgYJBwAAAA==.',
Ae='Aedrias:BAABLgAECn8ZAAIBAAcJRw3bLwAoAQABAAcJRw3bLwAoAQAAAA==.Aegennai:BAABLgAECn8XAAICAAgJ5QSREgATAQACAAgJ5QSREgATAQAAAA==.Aegon:BAECLgAFFH8aAAIDAAYJyxv/DAC1AQADAAYJyxv/DAC1AQAuAAQKfyMAAwMACQn8HzEuAOEBAAMABgkfITEuAOEBAAQAAwmUHL4pABsBAAAA.Aeli:BAAALgAECgIJAgABLgAECgcJGQABAEcNAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAABLgAECn82AAIFAAkJUh4OBwBzAgAFAAkJUh4OBwBzAgAAAA==.',
Ag='Agilaz:BAABLgAECn8oAAIGAAgJcBv3BAAVAgAGAAgJcBv3BAAVAgAAAA==.Aguas:BAAALgAECgMJBwAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAYJFAAHANsZAA==.',
Ak='Akey:BAAALgAECgMJBwAAAQ==.Akhae:BAACLgAFFH8GAAIHAAIJ0BheNwClAAAHAAIJ0BheNwClAAAuAAQKfyUAAwcACQkWFnIfAPwBAAcACQkWFnIfAPwBAAgACQneDSEhAIUBAAAA.Akrihail:BAAALgAECgMJBQAAAA==.',
Al='Albinism:BAABLgAECn8kAAICAAcJLBXHDAB5AQACAAcJLBXHDAB5AQAAAA==.Alcadeias:BAABLgAECn8hAAIJAAcJ8xXcbgBFAQAJAAcJ8xXcbgBFAQAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8jAAIKAAkJhhdWHgANAgAKAAkJhhdWHgANAgAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8VAAIJAAgJNgttrgAmAQAJAAgJNgttrgAmAQAAAA==.Andrömëdä:BAAALgAECgYJBgAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAAALgAECgYJCgAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJGQABAEcNAA==.',
Aq='Aquindra:BAAALgAECgMJAwAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn8jAAILAAgJCB7rCgBLAgALAAgJCB7rCgBLAgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAUJIgAMAEIPAA==.',
Ba='Baconpancake:BAAALgAECgUJBQAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgYJBgAAAA==.Balomdruid:BAAALgAECgMJAwAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAAALgAECgcJCwABLgAECggJHgAHAEMdAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgADCgYJDAAAAA==.Beastlypläyä:BAAALgAECgYJCAAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECggJJwAMAAgiAA==.',
Bi='Bigblingaxe:BAAALgAECgIJAgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgcJEQAAAA==.Blindhealz:BAABLgAECn8kAAMNAAgJzhVfEwDtAQANAAgJzhVfEwDtAQAOAAQJrAl2QgCsAAAAAA==.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgIJAgAAAA==.Blusoleil:BAAALgAECgYJBgAAAA==.',
Bo='Bonerblast:BAAALgAECgIJAgAAAA==.Boston:BAABLgAECn80AAQPAAkJhyQ2CAD9AgAPAAkJhyQ2CAD9AgAQAAcJzA6aHAAdAQARAAIJBx/tHABTAAAAAA==.',
Br='Brewtholomew:BAABLgAECn8pAAISAAkJ9BEWKwDgAQASAAkJ9BEWKwDgAQAAAA==.Briggsey:BAABLgAECn8bAAIDAAcJAAlDdgAQAQADAAcJAAlDdgAQAQAAAA==.Briznot:BAABLgAECn8UAAMDAAgJAhmtLgDfAQADAAcJxBitLgDfAQAEAAIJkR1QJwBQAAAAAA==.Brounies:BAABLgAECn8XAAITAAcJmAjWVQDzAAATAAcJmAjWVQDzAAAAAA==.Bryce:BAABLgAECn8VAAIJAAgJRBTmRgCpAQAJAAgJRBTmRgCpAQAAAA==.Brèanna:BAAALgAECgMJAwAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgADCgkJBgAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Bunnyfu:BAAALgAECgYJDQABLgAECgcJJQAUAOYVAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8FAAIHAAIJLguuQQB5AAAHAAIJLguuQQB5AAAuAAQKfykAAgcACAmNImcKAMQCAAcACAmNImcKAMQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8gAAIVAAcJ4Ba/DgCJAQAVAAcJ4Ba/DgCJAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8dAAISAAcJ5wSkdwDxAAASAAcJ5wSkdwDxAAAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgADCggJCQAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgUJCAAAAA==.Capthunder:BAAALgADCgYJDAABLgAECgUJBwAWAAAAAA==.Carnìfex:BAABLgAECn8eAAMXAAYJfRiBFgBMAQAYAAYJJA+DVwBOAQAXAAYJfRiBFgBMAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAAALgAECggJEgAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIZAAgJKAwJCQBsAQAZAAgJKAwJCQBsAQAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJBwABLgAECgkJHAAIAPMbAA==.Cheetah:BAAALgAECgMJBQAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAAALgAECgYJEQAAAA==.Cloudbreaker:BAAALgAECgIJAwAAAA==.Cloudkeg:BAAALgAECgQJBgAAAA==.',
Co='Constellate:BAAALgAECgYJBgAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAAALgAECggJEgAAAA==.',
['Cè']='Cèlane:BAABLgAECn8cAAMIAAkJ8xt0KQDJAQAIAAcJshx0KQDJAQAHAAMJWwqscgCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn8mAAMZAAYJ8RYJCgBSAQAZAAYJ8RYJCgBSAQAFAAYJkxCQIwAaAQAAAA==.Damnitsu:BAEALgAECgYJDwABLgAECgYJJgAZAPEWAA==.Darkcat:BAABLgAECn8jAAIaAAgJUQbtFAAOAQAaAAgJUQbtFAAOAQAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgMJBQAAAA==.',
De='Deadflexy:BAABLgAECn8VAAIQAAgJERkmEACyAQAQAAgJERkmEACyAQAAAA==.Dear:BAAALgAECgUJBwAAAA==.Deathberry:BAABLgAECn8vAAIDAAgJIR8pGwBFAgADAAgJIR8pGwBFAgAAAA==.Deathdoodles:BAACLgAFFH8HAAIPAAIJqwvWkgCYAAAPAAIJqwvWkgCYAAAuAAQKfxsAAg8ACAmVFSNOAJEBAA8ACAmVFSNOAJEBAAAA.Deathvoker:BAAALgAECgQJBAAAAA==.Deekan:BAABLgAECn8UAAIJAAgJywWjqADcAAAJAAgJywWjqADcAAAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgADCgYJCQAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAAALgAECgYJDAAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAWAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAABLgAECn8jAAIJAAgJNgcxfQAoAQAJAAgJNgcxfQAoAQAAAA==.',
Di='Dinkalopogis:BAAALgADCgkJCQAAAA==.Ditsie:BAAALgAECgIJAwAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Do='Dobby:BAAALgAECgMJBwAAAA==.',
Dr='Dragondude:BAABLgAECn8dAAMbAAgJ5xttBwA9AgAbAAgJ5xttBwA9AgAcAAEJNA74GwA4AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAABLgAECn8sAAIXAAkJlyADAgDsAgAXAAkJlyADAgDsAgAAAA==.Durgan:BAAALgADCgMJAwAAAA==.',
Dy='Dyelin:BAABLgAECn8jAAMDAAgJ2huOJgAFAgADAAgJ2huOJgAFAgAEAAIJyhOASQCSAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMZAAgJjxKABwCUAQAZAAgJjxKABwCUAQAFAAYJPAouOQBMAQAAAA==.',
El='Elylle:BAAALgAECgIJBAAAAA==.Elyron:BAABLgAECn8lAAMMAAgJ3BkROgDvAQAMAAgJ3BkROgDvAQAdAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQAMAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgMJBQAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Es='Espii:BAAALgAECgkJAQAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAWAAAAAA==.Etheri:BAAALgAECgYJBgAAAA==.',
Ev='Evilorc:BAAALgADCgcJCgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgADCgEJAQAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8bAAMTAAgJGR6JFABfAgATAAgJGR6JFABfAgAKAAIJuwzNgAAwAAAAAA==.Fakesaint:BAACLgAFFH8GAAIHAAMJeBEjLwDHAAAHAAMJeBEjLwDHAAAuAAQKfzMAAgcACQmfIYMDAD8DAAcACQmfIYMDAD8DAAAA.Fangstorm:BAABLgAECn8gAAIaAAgJogshEABOAQAaAAgJogshEABOAQAAAA==.Farorê:BAAALgAECgYJEAAAAA==.',
Fe='Felbane:BAABLgAECn8mAAIeAAkJyRccIwD9AQAeAAkJyRccIwD9AQAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAABLgAECn8qAAMfAAgJ3gcdHAAFAQAfAAgJ3gcdHAAFAQAYAAEJ8AG/hwAcAAAAAA==.',
Fr='Fritopaws:BAABLgAECn8lAAMGAAgJcRrsBgDZAQAGAAgJPhnsBgDZAQAgAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgEJAQAAAA==.Furpunch:BAAALgADCggJDQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJDwAAAA==.Gallivia:BAAALgAECgcJCwAAAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgYJDAAAAA==.Ginzi:BAABLgAECn8pAAMPAAgJ8wi5awBEAQAPAAgJswe5awBEAQARAAYJYQpeCgAoAQAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgYJCQABLgAECggJFQADAKgaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECgYJBgAAAA==.Greatchez:BAAALgAECgcJDQAAAA==.Greth:BAAALgADCgkJCAAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAABLgAECn8lAAIUAAcJ5hXgJABjAQAUAAcJ5hXgJABjAQAAAA==.Gummypenguin:BAABLgAECn8VAAMSAAgJGhqcTACDAQASAAcJiBmcTACDAQAGAAYJTQzRVQDyAAABLgAFFAUJGAASAK4gAA==.',
Ha='Hadhox:BAABLgAECn8XAAIYAAgJWQzSKwBVAQAYAAgJWQzSKwBVAQAAAA==.Hakano:BAABLgAECn8ZAAILAAYJcwMMRwCnAAALAAYJcwMMRwCnAAAAAA==.Harbiin:BAAALgAECgIJAgAAAA==.Hathdox:BAABLgAECn8VAAISAAYJJxITYQAnAQASAAYJJxITYQAnAQABLgAECggJFwAYAFkMAA==.Hawkulees:BAAALgADCgkJBgAAAA==.Hazelnoot:BAABLgAECn8mAAMJAAkJ0BsKGAB0AgAJAAkJ0BsKGAB0AgAhAAYJuAXPQgDhAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn8gAAIiAAgJdhCJFgBsAQAiAAgJdhCJFgBsAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn8cAAIbAAcJugikFgAYAQAbAAcJugikFgAYAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8hAAIEAAgJXwkzDgAPAQAEAAgJXwkzDgAPAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgAWAAAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJCAAWAAAAAA==.Hornsnap:BAABLgAECn8eAAMHAAcJYR1kGAAyAgAHAAcJYR1kGAAyAgAIAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAWAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAECgcJJQAUAOYVAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJDgAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQGAAMJfBxZGADQAAAGAAIJ0CNZGADQAAAgAAIJRxcIGQCtAAASAAEJqib+VwBuAAAuAAQKfzcABAYACQnAJaQDAGoDAAYACAnDJaQDAGoDACAACAlCI38FAJcCABIAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgMJBQAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAABLgAECn8eAAMHAAYJIBnqNACwAQAHAAYJIBnqNACwAQAIAAYJLhJ6NQAJAQAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJAwAWAAAAAA==.',
In='Innexdruid:BAAALgADCgUJBQABLgAECgYJEAAWAAAAAA==.Insaint:BAACLgAFFH8GAAIJAAMJ4A+bPwDtAAAJAAMJ4A+bPwDtAAAuAAQKfzEAAgkACQnuF8ssAAUCAAkACQnuF8ssAAUCAAAA.',
Is='Isabellë:BAABLgAECn8dAAMOAAcJQQfgNQDqAAAOAAcJQQfgNQDqAAAjAAIJnAM1UgBGAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJAwAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAAALgAECgYJEwAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJOQAYAHEkAA==.',
Je='Jessamine:BAABLgAECn8hAAIMAAkJXxhwKQAyAgAMAAkJXxhwKQAyAgAAAA==.Jessicafelba:BAABLgAECn8VAAMDAAgJqBo2KwDuAQADAAcJqBo2KwDuAQAEAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8kAAIaAAcJOhG2DwBVAQAaAAcJOhG2DwBVAQAAAA==.Jezzak:BAABLgAECn8gAAISAAgJmhplJAAAAgASAAgJmhplJAAAAgABLgAECgkJKQASAAAbAA==.',
Jo='Jorien:BAABLgAECn84AAISAAkJcRizHwAZAgASAAkJcRizHwAZAgAAAA==.',
Jp='Jp:BAAALgAECgIJAgABLgAECgYJCAAWAAAAAA==.Jps:BAAALgAECgYJCAAAAA==.',
Ka='Kaboonski:BAAALgADCgUJBQAAAA==.Kaboonsky:BAABLgAECn8jAAMjAAkJFRhHGAAaAgAjAAkJFRhHGAAaAgAOAAIJmxEPTQB0AAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJCgAAAA==.Kamikori:BAABLgAECn8cAAIYAAcJZBxyGADcAQAYAAcJZBxyGADcAQAAAA==.Kardelbrew:BAAALgAECgMJAwAAAA==.Kardels:BAAALgAECgYJEQAAAA==.Karnn:BAACLgAFFH8SAAMkAAUJdh5eBgBkAQAkAAUJdh5eBgBkAQALAAEJHQFRKgArAAAuAAQKfyQAAyQACAl3JJQKAM8CACQACAl3JJQKAM8CAAEAAwl6C0dbAF8AAAAA.Katalight:BAAALgAECgQJAQABLgAECgUJBQAWAAAAAA==.Katrini:BAAALgAECgUJBQAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJDQAMAHIbAA==.',
Ki='Kiascendance:BAAALgAECgUJBwAAAA==.Kiplet:BAABLgAECn8aAAIjAAkJpBbKGAC8AQAjAAkJpBbKGAC8AQAAAA==.',
Ko='Korxon:BAABLgAECn8aAAMNAAgJkBcqGQDQAQANAAgJkBcqGQDQAQAjAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAWAAAAAA==.Krazz:BAAALgADCgYJCQABLgAECggJFQAQABEZAA==.',
Ks='Ksyusha:BAAALgAECgMJBwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJBwAWAAAAAA==.',
La='Lahabrea:BAABLgAECn8fAAMEAAgJAw3wKwAPAQADAAgJwQqWZgAzAQAEAAYJ2w3wKwAPAQAAAA==.Lanuadra:BAAALgADCgYJBgABLgAECgkJFwAUAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBgAAAA==.',
Le='Leeara:BAABLgAECn8XAAIeAAgJQRmmNQAhAgAeAAgJQRmmNQAhAgAAAA==.Legitpoopoo:BAAALgAECgUJCgABLgAFFAMJBgAQAFkXAA==.Lem:BAAALgAECgUJCAAAAA==.Lethalbimbo:BAAALgAECgMJBQAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilysham:BAACLgAFFH8UAAIHAAYJ2xnQBAABAgAHAAYJ2xnQBAABAgAuAAQKfyEAAwcACAmAI0sQAJUCAAcABwkOI0sQAJUCAAgAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Ly='Lyv:BAAALgAECgEJAQAAAA==.',
['Lø']='Løllîe:BAAALgAECgMJBwAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgMJBwAWAAAAAA==.',
Ma='Magatai:BAABLgAECn8UAAIMAAYJ7gY5rgDoAAAMAAYJ7gY5rgDoAAAAAA==.Mageless:BAAALgAECgEJAQAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJBQABLgADCgkJDgAWAAAAAA==.Manaster:BAAALgAECgYJBgAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Marlie:BAAALgAECgkJCgAAAA==.Martlok:BAABLgAECn8fAAMPAAcJ5xhVVAB/AQAPAAcJ5xhVVAB/AQARAAIJEBbcFABGAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Maynis:BAAALgADCgYJBgAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgIJAwAAAA==.',
Me='Methallica:BAAALgAECgUJBgAAAA==.',
Mi='Micflinigan:BAABLgAECn8gAAMYAAgJCBOGKgBdAQAYAAcJrROGKgBdAQAfAAEJKg8TQAAwAAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAjAKQWAA==.Misahaviran:BAAALgAECgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Mistynite:BAAALgADCgYJBgAAAA==.',
Mo='Mochimochi:BAAALgAECgMJAwAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Moonshae:BAABLgAECn8jAAIBAAkJjhKNGQDTAQABAAkJjhKNGQDTAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJIwAKAIYXAA==.Mornings:BAAALgAECgYJDQABLgAECgkJIwAKAIYXAA==.Mouse:BAAALgAECgYJDwAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgADCgkJCQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwAPAKsLAA==.Nails:BAABLgAECn8VAAIFAAgJixEuFgCWAQAFAAgJixEuFgCWAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgYJCQABLgAECggJFQAkAB4MAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgYJCwABLgADCgkJDgAWAAAAAA==.Nootloops:BAAALgAECgEJAQABLgAECgkJJgAJANAbAA==.Noriisa:BAABLgAECn8pAAISAAkJABvKFABiAgASAAkJABvKFABiAgAAAA==.Notamathguy:BAAALgAECgIJAgAAAA==.Noudders:BAABLgAECn8YAAIHAAgJghuiEwBbAgAHAAgJghuiEwBbAgAAAA==.',
Nu='Nutsandberri:BAAALgADCggJEAAAAA==.',
Od='Odinhand:BAABLgAECn8oAAIKAAkJTwkuIwBUAQAKAAkJTwkuIwBUAQAAAA==.',
Ol='Oliissa:BAAALgADCgkJCQAAAA==.',
On='Onepunchman:BAAALgAECgEJAQABLgAECgMJAwAWAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8nAAIMAAgJCCLzFwCRAgAMAAgJCCLzFwCRAgAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8VAAIMAAUJbhWVDQCvAQAMAAUJbhWVDQCvAQAuAAQKfz8AAgwACQmpIlUIAA8DAAwACQmpIlUIAA8DAAAA.Pandóra:BAAALgAECgYJEwAAAA==.Pariousa:BAACLgAFFH8JAAMZAAMJTR1MBAALAQAZAAMJ0RxMBAALAQAFAAIJcB7+EADBAAAuAAQKfzoAAxkACQmkJhgAAIkDABkACQl1JhgAAIkDAAUACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.Pewpewboo:BAACLgAFFH8iAAIMAAUJQg9VQgA1AQAMAAUJQg9VQgA1AQAuAAQKfykAAgwACQm5HMAzAKQCAAwACQm5HMAzAKQCAAAA.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAWAAAAAA==.Pinkeepink:BAABLgAECn8VAAIEAAYJigSgGQCeAAAEAAYJigSgGQCeAAAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Potangwang:BAAALgAECgYJBgAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8oAAIQAAkJECLKAwDFAgAQAAkJECLKAwDFAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8WAAMJAAcJmAsJfwAlAQAJAAcJHgsJfwAlAQAlAAQJ/wYZKwBxAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8UAAMCAAcJIgpYEgAXAQACAAcJIgpYEgAXAQAIAAcJRgN3SQC2AAAAAA==.',
Re='Ren:BAAALgADCgQJBgAAAA==.Retacus:BAAALgADCgEJAQAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECggJFQAQABEZAA==.',
Ri='Rina:BAACLgAFFH8bAAImAAYJjB6TAACwAQAmAAYJjB6TAACwAQAuAAQKfywAAyYACAlZIxUCAOoCACYACAlZIxUCAOoCAB4ABQmjEiF2AOEAAAAA.Rineli:BAABLgAECn8gAAIMAAcJwQ29fgA9AQAMAAcJwQ29fgA9AQAAAA==.Ringadingg:BAABLgAECn8kAAIPAAgJ5yCHFwB3AgAPAAgJ5yCHFwB3AgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJJAAPAOcgAA==.Rivets:BAAALgADCgMJAwABLgAECggJFQAFAIsRAA==.',
Ro='Roastduck:BAABLgAECn8bAAIjAAgJ7hp/DQBEAgAjAAgJ7hp/DQBEAgAAAA==.Rosequartz:BAAALgAECgQJBgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDQAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sarazah:BAACLgAFFH8NAAIJAAQJbiAKDACXAQAJAAQJbiAKDACXAQAuAAQKfzUAAgkACQncJccAAIADAAkACQncJccAAIADAAAA.',
Sc='Scony:BAAALgAECgcJCgAAAA==.Scribs:BAAALgAECgYJDAAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMMAAgJtB0FTwCsAQAMAAcJbxwFTwCsAQAdAAQJTh4SDAARAQABLgAFFAMJBgAQAFkXAA==.',
Se='Seegon:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJOAAPAG8WAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAEJAQAWAAAAAA==.Severautism:BAAALgAECgMJAwABLgAFFAEJAQAWAAAAAA==.Severànce:BAAALgADCgQJBAABLgAFFAEJAQAWAAAAAA==.Sevotion:BAABLgAECn8xAAQJAAkJUx0oNgBKAgAJAAgJKB0oNgBKAgAhAAkJShXuEQA5AgAlAAcJog8qLQClAAABLgAFFAEJAQAWAAAAAA==.',
Sh='Shablammy:BAABLgAECn8dAAIHAAgJECShAwA9AwAHAAgJECShAwA9AwAAAA==.Shadownome:BAAALgAECgMJCAAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgADCgUJBQAAAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgADCgkJEAAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAABLgAECn8aAAISAAkJWQz7OAClAQASAAkJWQz7OAClAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQgAAkJeBqiCQBGAgAgAAkJZRmiCQBGAgAGAAcJfRd6KADmAQASAAQJfRG3kQCyAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgMJAwAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepydwarf:BAAALgAECgEJAgAAAA==.Sludgekicker:BAAALgADCgIJAgAAAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgADCggJDgAAAA==.Sprynt:BAABLgAECn8ZAAIBAAkJoRmyCgCLAgABAAkJoRmyCgCLAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgADCggJBgAAAA==.Stendo:BAAALgAECgMJBQABLgAFFAUJDQAiANwgAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAAALgAFFAEJAQAAAA==.Stonemother:BAAALgAECgMJBwAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAWAAAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECggJFQAJAOcdAA==.',
Sw='Swampmonster:BAAALgAECgIJAwABLgAECgYJDwAWAAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIeAAQJchlVJQA1AQAeAAQJchlVJQA1AQAuAAQKfywAAx4ACAkkJAwQAIICAB4ACAnOIwwQAIICACIABAlMJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgYJBgAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAECgcJFgAfAHIbAA==.Taurastrage:BAABLgAECn8WAAIfAAcJchvCDwCdAQAfAAcJchvCDwCdAQAAAA==.Taurdk:BAAALgAECgYJCQABLgAECgcJFgAfAHIbAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAABLgAECn8YAAIKAAcJKx7cFgC/AQAKAAcJKx7cFgC/AQAAAA==.Tazarakk:BAAALgADCgMJAwABLgAECggJFQAfAAQhAA==.Tazbeard:BAAALgADCgYJCQABLgAECggJFQAfAAQhAA==.',
Te='Teedos:BAAALgAECggJDQAAAA==.Teetau:BAABLgAECn8lAAIVAAgJ0Qc9IADIAAAVAAgJ0Qc9IADIAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECggJKwAcAOITAA==.Thadregosa:BAABLgAECn8rAAMcAAgJ4hPkBQCxAQAcAAgJ4hPkBQCxAQAUAAcJvwp4SgCsAAAAAA==.Thander:BAAALgADCgMJAwABLgAECgQJBgAWAAAAAA==.Thannicus:BAAALgAECgYJDAAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.',
Ti='Tibbotanical:BAABLgAECn8kAAITAAkJoxvHCwDFAgATAAkJoxvHCwDFAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJAATAKMbAA==.Tiffy:BAAALgADCgkJKwAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirna:BAAALgAECgUJBQAAAA==.Tirnotham:BAAALgAECgMJBwAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJAgAAAA==.',
To='Tokalu:BAABLgAECn8VAAIkAAgJHgzQIwA+AQAkAAgJHgzQIwA+AQAAAA==.Tonjudsonson:BAACLgAFFH8YAAIVAAUJniIhAgCeAQAVAAUJniIhAgCeAQAuAAQKfyoAAhUACAlQJvUAAGQDABUACAlQJvUAAGQDAAAA.Tonopah:BAABLgAECn8VAAIIAAgJNAvwLwAmAQAIAAgJNAvwLwAmAQAAAA==.Toxix:BAAALgAECgcJEQAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAECgkJDgAAAA==.',
Tu='Tuggsondix:BAAALgAECgUJBQAAAA==.',
Tw='Twiki:BAABLgAECn8dAAIEAAcJ8AZJEgDZAAAEAAcJ8AZJEgDZAAAAAA==.Twobricks:BAABLgAECn8oAAITAAkJoBB1KwC0AQATAAkJoBB1KwC0AQAAAA==.',
Ty='Tyrssana:BAAALgAECgMJBwABLgAFFAMJBQAcAIcCAA==.',
Ug='Uglykitten:BAABLgAECn8bAAIjAAYJIxr6HQCMAQAjAAYJIxr6HQCMAQAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAAALgAECgcJEQAAAA==.',
Va='Vaccaria:BAAALgAECgIJAgABLgAECgMJAwAWAAAAAA==.Vaererelor:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAECgkJCQABLgAFFAYJFAAHANsZAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgMJBwAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgQJBwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECggJFAADAAIZAA==.Vierth:BAAALgADCgYJBwAAAA==.Vincenzo:BAACLgAFFH8PAAIkAAQJ1SSHAgCuAQAkAAQJ1SSHAgCuAQAuAAQKfxoAAiQACAk9I0MEAEgDACQACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgcJEQAAAA==.Viridiana:BAAALgAECgYJCQABLgAECggJJQANAOIXAA==.Visea:BAAALgAECgMJBAAAAA==.',
Vl='Vlarett:BAAALgAECgMJBwAAAA==.',
Vo='Voidsavage:BAAALgAECgQJBgAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECggJHQAAAQ==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECgYJJgAZAPEWAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgEJAQAWAAAAAA==.Wesleypriest:BAABLgAECn8dAAMNAAgJrAlVIwBVAQANAAgJhwlVIwBVAQAjAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgADCgEJAQAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8ZAAIlAAgJzhKJDgCCAQAlAAgJzhKJDgCCAQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAMAEkXAA==.',
Xe='Xehorn:BAAALgAECgYJBgABLgAFFAYJFAAHANsZAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJCQAZAE0dAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIMAAcJSReajQC3AQAMAAcJSReajQC3AQAAAA==.',
Ya='Yashe:BAABLgAECn8eAAMHAAgJQx0GEAB/AgAHAAgJQx0GEAB/AgAIAAEJWAjekQAlAAAAAA==.',
Yh='Yhorn:BAAALgAECgcJBwABLgAFFAYJFAAHANsZAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAYAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBAAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJBgAAAA==.Zareena:BAAALgADCgMJAwAAAA==.Zarnia:BAAALgAECgQJBgAAAA==.Zarrock:BAAALgAECgMJBQAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJBgAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAYJFAAHANsZAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zeratule:BAAALgADCgYJBgAAAA==.Zerm:BAABLgAECn86AAIJAAkJxBpMGwBgAgAJAAkJxBpMGwBgAgAAAA==.',
Zi='Zijo:BAAALgAECgQJBAAAAA==.Zinnkura:BAAALgAECgMJBwAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8UAAIDAAYJ2wkThgDvAAADAAYJ2wkThgDvAAAAAA==.',
['Ñô']='Ñôg:BAAALgADCgkJCQAAAA==.',
['Ød']='Ødis:BAAALgADCgcJIAAAAA==.',
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
