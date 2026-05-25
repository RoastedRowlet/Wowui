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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Balance','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','DemonHunter-Devourer','Warrior-Protection','Hunter-Survival','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Paladin-Protection','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBwAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8ZAAIBAAcJSA22OgAuAQABAAcJSA22OgAuAQAAAA==.Aegennai:BAABLgAECn8XAAICAAgJ5gTcFgAQAQACAAgJ5gTcFgAQAQAAAA==.Aegon:BAECLgAFFH8aAAIDAAYJyxsLFQCsAQADAAYJyxsLFQCsAQAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAQAAwmUHL4pABsBAAAA.Aegondh:BAEALgAECgMJAwABLgAFFAYJGgADAMsbAA==.Aeli:BAAALgAECgIJAgABLgAECgcJGQABAEgNAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAABLgAECn82AAIFAAkJUh6mCgBWAgAFAAkJUh6mCgBWAgAAAA==.',
Ag='Agilaz:BAABLgAECn8tAAIGAAgJcBuOBgADAgAGAAgJcBuOBgADAgAAAA==.Aguas:BAAALgAECgMJCQAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJFgAHACYaAA==.',
Ak='Akey:BAAALgAECgMJBwAAAQ==.Akhae:BAACLgAFFH8GAAIHAAIJ0Bg6RAChAAAHAAIJ0Bg6RAChAAAuAAQKfyUAAwcACQkVFl0nAPQBAAcACQkVFl0nAPQBAAgACQneDW4oAH4BAAAA.Akrihail:BAAALgAECgQJBgAAAA==.',
Al='Albinism:BAABLgAECn8pAAICAAcJLhU+EAByAQACAAcJLhU+EAByAQAAAA==.Alcadeias:BAABLgAECn8kAAIJAAcJ8xVIeQBbAQAJAAcJ8xVIeQBbAQAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8nAAIKAAkJGhjbEwAMAgAKAAkJGhjbEwAMAgAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8XAAIJAAgJlAttrgAmAQAJAAgJlAttrgAmAQAAAA==.Andrömëdä:BAAALgAECgYJDAAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAAALgAECgYJEQAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJGQABAEgNAA==.',
Aq='Aquindra:BAAALgAECgMJAwAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn8rAAILAAgJ3h8rCgB0AgALAAgJ3h8rCgB0AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAAAAQ==.',
Ba='Baconpancake:BAAALgAECgYJCwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgYJCQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAAALgAECgQJBwAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAABLgAECn8aAAMMAAgJNhjjNAAIAgAMAAgJNhjjNAAIAgANAAgJVQQeLADJAAABLgAECggJHgAHAEMdAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECgMJAwAAAA==.Beastlypläyä:BAAALgAECgYJCAAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECgkJMAAOAJgiAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCQAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgcJEgAAAA==.Blindhealz:BAACLgAFFH8FAAIPAAMJLwoYJgDPAAAPAAMJLwoYJgDPAAAuAAQKfywAAw8ACAnUFbIWAPMBAA8ACAnUFbIWAPMBABAABQl4C5Y9APEAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAAALgAECgYJDAAAAA==.',
Bo='Bonerblast:BAAALgAECgIJAgAAAA==.Boston:BAABLgAECn81AAQMAAkJhyRMDADrAgAMAAkJhyRMDADrAgANAAcJzA69IgAOAQARAAMJhBslHACgAAAAAA==.',
Br='Brewtholomew:BAABLgAECn8pAAISAAkJ9RFqNgDZAQASAAkJ9RFqNgDZAQAAAA==.Briggsey:BAABLgAECn8hAAIDAAgJyAtbXgBuAQADAAgJyAtbXgBuAQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBmONgDmAQADAAcJxBiONgDmAQAEAAIJbyB7JwBgAAAAAA==.Brounies:BAABLgAECn8XAAITAAcJmAg7YAD0AAATAAcJmAg7YAD0AAAAAA==.Bryce:BAABLgAECn8ZAAIJAAgJRBQnVQCsAQAJAAgJRBQnVQCsAQAAAA==.Brèanna:BAAALgAECgMJBgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Bunnyfu:BAAALgAECgYJEAABLgAECgcJJQAUAOcVAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8FAAIHAAIJLgt4TwB4AAAHAAIJLgt4TwB4AAAuAAQKfykAAgcACAmMInwKANQCAAcACAmMInwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIVAAcJcBjNEACgAQAVAAcJcBjNEACgAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8dAAISAAcJ5wTkjgDvAAASAAcJ5wTkjgDvAAAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgYJDQAAAA==.Capthunder:BAAALgADCgcJDwABLgAECgUJBwAWAAAAAA==.Carnìfex:BAABLgAECn8jAAMXAAYJ4BquFgB9AQAXAAYJ4BquFgB9AQAYAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAABLgAECn8WAAQZAAgJoCEXDwCOAQAZAAgJoCEXDwCOAQAVAAQJtBdZHwAOAQATAAMJdxZUdgCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIaAAgJKAydCgBqAQAaAAgJKAydCgBqAQAAAA==.Cephandrius:BAAALgAECgQJBAAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJHAAIAPMbAA==.Cheetah:BAAALgAECgMJCAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAAALgAECgcJEwAAAA==.Cloudbreaker:BAAALgAECgQJBgAAAA==.Cloudkeg:BAAALgAECgQJBwAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgYJBgAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAABLgAECn8WAAITAAgJdAqETAA5AQATAAgJdAqETAA5AQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8cAAMIAAkJ8xt0KQDJAQAIAAcJshx0KQDJAQAHAAMJWwqShQCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn8tAAMaAAcJyBbHCwBPAQAaAAYJiBfHCwBPAQAFAAcJ/BDRIgBPAQAAAA==.Damnitsu:BAEBLgAECn8XAAMFAAYJMA8hKQAfAQAFAAYJ4Q4hKQAfAQAaAAMJzwxLFgCeAAABLgAECgcJLQAaAMgWAA==.Darkcat:BAABLgAECn8rAAIZAAgJlAcKGQANAQAZAAgJlAcKGQANAQAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgMJCAAAAA==.',
De='Deadflexy:BAABLgAECn8ZAAINAAgJKxnQEQDAAQANAAgJKxnQEQDAAQAAAA==.Dear:BAAALgAECgUJBwAAAA==.Deathberry:BAABLgAECn80AAIDAAgJOB95GwBlAgADAAgJOB95GwBlAgAAAA==.Deathdoodles:BAACLgAFFH8HAAIMAAIJqwuQrgCNAAAMAAIJqwuQrgCNAAAuAAQKfx8AAgwACAkRGBpHAMoBAAwACAkRGBpHAMoBAAAA.Deathvoker:BAAALgAECgQJBAAAAA==.Deekan:BAABLgAECn8UAAIJAAgJywWDyQDXAAAJAAgJywWDyQDXAAAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgAECgQJBAABLgAFFAMJCAAUAC0NAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAAALgAECgcJEwAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAWAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAIJAAgJ5wdmiQA9AQAJAAgJ5wdmiQA9AQAAAA==.',
Di='Dionne:BAAALgAECgUJBQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Do='Dobby:BAAALgAECgMJBwAAAA==.',
Dr='Dragondude:BAABLgAECn8sAAMbAAgJTCFIAwD8AgAbAAgJTCFIAwD8AgAcAAEJNA7qHwA3AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAABLgAECn8zAAIXAAkJlyAeAwDgAgAXAAkJlyAeAwDgAgAAAA==.Durgan:BAAALgADCgMJAwAAAA==.',
Dy='Dyelin:BAABLgAECn8rAAMDAAgJcyCjEgCgAgADAAgJcyCjEgCgAgAEAAIJyhOASQCSAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMaAAgJkBIGCQCPAQAaAAgJkBIGCQCPAQAFAAYJPAouOQBMAQAAAA==.',
El='Elylle:BAAALgAECgMJCAAAAA==.Elyron:BAABLgAECn8tAAMOAAgJpx7gIQB6AgAOAAgJpx7gIQB6AgAdAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQAOAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgMJCAAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Es='Espii:BAAALgAECgkJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAWAAAAAA==.Etheri:BAAALgAECgcJBwAAAA==.',
Ev='Evilorc:BAAALgADCgcJCgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8lAAMTAAgJTSETCgD8AgATAAgJTSETCgD8AgAKAAIJuwzNgAAwAAAAAA==.Fakesaint:BAACLgAFFH8GAAIHAAMJeBFgOgDEAAAHAAMJeBFgOgDEAAAuAAQKfzQAAgcACQmfIXQFADYDAAcACQmfIXQFADYDAAAA.Fangstorm:BAABLgAECn8nAAIZAAgJQg2tEgBYAQAZAAgJQg2tEgBYAQAAAA==.Farorê:BAABLgAECn8XAAIeAAYJ6Be0IwCDAQAeAAYJ6Be0IwCDAQAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIfAAkJ2hcrJQAbAgAfAAkJ2hcrJQAbAgAAAA==.Feldruid:BAAALgADCgMJAwAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAABLgAECn8yAAMgAAgJPAuCHAAoAQAgAAgJPAuCHAAoAQAYAAIJvgNqfABIAAAAAA==.',
Fr='Fritopaws:BAABLgAECn80AAMGAAgJ/hxfBQAoAgAGAAgJIhxfBQAoAgAhAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgEJAQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJDwAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECggJDQAAAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn8xAAMRAAgJMwqGEAAkAQAMAAgJswcqfgBBAQARAAgJFQqGEAAkAQAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgYJCQABLgAECggJFQADAKkaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECgcJBwAAAA==.Greatchez:BAAALgAECgcJDQAAAA==.Greth:BAAALgADCgkJCAAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAABLgAECn8lAAIUAAcJ5xVpKwBrAQAUAAcJ5xVpKwBrAQAAAA==.Gummypenguin:BAABLgAECn8VAAMSAAgJGhqcTACDAQASAAcJiBmcTACDAQAGAAYJTQzRVQDyAAABLgAFFAUJHQASAMMgAA==.',
Gw='Gwenldoyn:BAAALgADCgQJBAAAAA==.',
Ha='Hadhox:BAABLgAECn8aAAIYAAkJJg3rJQCjAQAYAAkJJg3rJQCjAQAAAA==.Hakano:BAABLgAECn8jAAILAAYJrgOhTgCqAAALAAYJrgOhTgCqAAAAAA==.Harbiin:BAAALgAECgIJAgAAAA==.Hathdox:BAABLgAECn8cAAISAAYJJRfgYgBSAQASAAYJJRfgYgBSAQABLgAECgkJGgAYACYNAA==.Hawkulees:BAAALgADCgkJBgAAAA==.Hazelnoot:BAABLgAECn8mAAMJAAkJ0BsDIgBeAgAJAAkJ0BsDIgBeAgAiAAYJugX0SwDhAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn8sAAIjAAgJNhI+FgCgAQAjAAgJNhI+FgCgAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn8kAAIbAAgJrQhWFgBDAQAbAAgJrQhWFgBDAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8qAAIEAAgJ0AtEDgAtAQAEAAgJ0AtEDgAtAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgAWAAAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJCAAWAAAAAA==.Hornsnap:BAABLgAECn8eAAMHAAcJYR3QHgArAgAHAAcJYR3QHgArAgAIAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAWAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAECgcJJQAUAOcVAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJDgAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQGAAMJfBxZGADQAAAGAAIJ0CNZGADQAAAhAAIJRxdMHgCiAAASAAEJqiYBawBoAAAuAAQKfzoABAYACQnAJaQDAGoDAAYACAnDJaQDAGoDACEACAldI8cFALACABIAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgMJCAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAABLgAECn8lAAMHAAcJ3hfqNACwAQAHAAcJ3hfqNACwAQAIAAYJLhVhNwAqAQAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBAAWAAAAAA==.Ilovekayla:BAAALgAECgEJAwAAAA==.',
In='Innexdruid:BAAALgAECgQJBAAAAA==.Insaint:BAACLgAFFH8KAAIJAAQJDQ88OgAWAQAJAAQJDQ88OgAWAQAuAAQKfzMAAgkACQl2GpQoAD4CAAkACQl2GpQoAD4CAAAA.',
Is='Isabellë:BAABLgAECn8jAAMQAAcJrQcmPQDzAAAQAAcJrQcmPQDzAAAeAAIJnAO3WgBGAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBAAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhF5YgBkAQADAAcJAhF5YgBkAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJQgAYAHskAA==.',
Je='Jessamine:BAABLgAECn8hAAIOAAkJXxigMwAsAgAOAAkJXxigMwAsAgAAAA==.Jessicafelba:BAABLgAECn8VAAMDAAgJqRo9NwDkAQADAAcJqRo9NwDkAQAEAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8pAAIZAAcJZBL1EQBiAQAZAAcJZBL1EQBiAQAAAA==.Jezzak:BAABLgAECn8lAAISAAgJmhqSMADwAQASAAgJmhqSMADwAQABLgAECgkJMQASAAEbAA==.',
Jo='Jorien:BAABLgAECn9BAAISAAkJ+BlqIQA2AgASAAkJ+BlqIQA2AgAAAA==.',
Jp='Jp:BAAALgAECgIJBAABLgAECgYJCAAWAAAAAA==.Jps:BAAALgAECgYJCAAAAA==.',
Ka='Kaboonski:BAAALgADCgUJBQAAAA==.Kaboonsky:BAABLgAECn8lAAMeAAkJWxhHGAAaAgAeAAkJWxhHGAAaAgAQAAIJmxHwWABzAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJDwAAAA==.Kamikori:BAABLgAECn8eAAIYAAcJZBzKHwDMAQAYAAcJZBzKHwDMAQAAAA==.Kardelbrew:BAAALgAECgMJAwABLgAECgYJEQAWAAAAAA==.Kardels:BAAALgAECgYJEQAAAA==.Karnn:BAACLgAFFH8XAAMkAAUJdh5yCQBWAQAkAAUJdh5yCQBWAQALAAEJHQFRKgArAAAuAAQKfyQAAyQACAl3JJQKAM8CACQACAl3JJQKAM8CAAEAAwl7C3lwAGEAAAAA.Katalight:BAAALgAECgQJAQABLgAECgYJBwAWAAAAAA==.Katrini:BAAALgAECgYJBwAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAOALAdAA==.',
Ki='Kiascendance:BAAALgAECggJDwAAAA==.Kiplet:BAABLgAECn8aAAIeAAkJpBarHQCzAQAeAAkJpBarHQCzAQAAAA==.',
Kn='Knockback:BAAALgAECgMJBQAAAA==.',
Ko='Korxon:BAABLgAECn8fAAMPAAgJkhfGGgDMAQAPAAgJkhfGGgDMAQAeAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAWAAAAAA==.Krazz:BAAALgADCgYJCQABLgAECggJGQANACsZAA==.',
Ks='Ksyusha:BAAALgAECgMJBwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJJwAOAGsVAA==.',
La='Lahabrea:BAABLgAECn8fAAMEAAgJBA3wKwAPAQADAAgJwQoEdQA6AQAEAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAAALgAECgYJBwAAAA==.Lanuadra:BAAALgAECgYJBwABLgAECgkJGAAUAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBgAAAA==.',
Le='Leeara:BAABLgAECn8bAAIfAAgJQhmmNQAhAgAfAAgJQhmmNQAhAgAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgANAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalbimbo:BAAALgAECgMJCAAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8WAAIHAAcJJhoDAwBUAgAHAAcJJhoDAwBUAgAuAAQKfyEAAwcACAmAI0sQAJUCAAcABwkOI0sQAJUCAAgAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Ly='Lyv:BAAALgAECgEJAQAAAA==.',
['Lø']='Løllîe:BAAALgAECgMJBwAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgMJBwAWAAAAAA==.',
Ma='Magatai:BAABLgAECn8VAAIOAAYJ7gZ5xwDgAAAOAAYJ7gZ5xwDgAAAAAA==.Mageless:BAAALgAECgEJAQAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJBQABLgADCgkJDgAWAAAAAA==.Manaster:BAAALgAECgYJCAAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Marlie:BAAALgAECgkJCwAAAA==.Martlok:BAABLgAECn8gAAMMAAcJ5xi9ZAB6AQAMAAcJ5xi9ZAB6AQARAAIJEBbcFABGAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Maynis:BAAALgADCgcJCwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgIJBQAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgUJBgAAAA==.',
Mi='Micflinigan:BAABLgAECn8lAAMYAAkJOhRFIgC6AQAYAAgJ9BRFIgC6AQAgAAEJKg8hSAAuAAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAeAKQWAA==.Misahaviran:BAAALgAECgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Mistynite:BAAALgADCgYJBgAAAA==.',
Mo='Mochimochi:BAAALgAECgQJBwAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgQJBAABLgAECgkJMgAQAFEPAA==.Moonshae:BAABLgAECn8lAAIBAAkJjhJPIADUAQABAAkJjhJPIADUAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwAKABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwAKABoYAA==.Mouse:BAAALgAECgcJEQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwAMAKsLAA==.Nails:BAABLgAECn8ZAAIFAAgJ0BKUGQCkAQAFAAgJ0BKUGQCkAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgYJCQABLgAECggJGQAkANIPAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJDgAWAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgAJANAbAA==.Noriisa:BAABLgAECn8xAAISAAkJARvmHgBDAgASAAkJARvmHgBDAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8YAAIHAAgJghsbGQBUAgAHAAgJghsbGQBUAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgEJAQAAAA==.',
Ny='Nyvak:BAAALgAECgUJCwAAAA==.',
Od='Odinhand:BAABLgAECn8uAAIKAAkJWwnHKABbAQAKAAkJWwnHKABbAQAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBAAWAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIOAAkJmCJVCgASAwAOAAkJmCJVCgASAwAAAA==.Ozwäldo:BAAALgAECgYJCAABLgAECgkJMAAOAJgiAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8WAAIOAAUJbhWVDQCvAQAOAAUJbhWVDQCvAQAuAAQKfz8AAg4ACQmpIukLAAMDAA4ACQmpIukLAAMDAAAA.Pandóra:BAAALgAECgYJEwAAAA==.Pariousa:BAACLgAFFH8OAAMaAAMJDSQ/BAA4AQAaAAMJDSQ/BAA4AQAFAAIJcB7+EADBAAAuAAQKfzoAAxoACQmjJisAAIMDABoACQl1JisAAIMDAAUACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAWAAAAAA==.Pinkeepink:BAABLgAECn8cAAIEAAYJvgjTFwDEAAAEAAYJvgjTFwDEAAAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Potangwang:BAAALgAECgYJDAAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8oAAINAAkJDyLCBQCpAgANAAkJDyLCBQCpAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8WAAMJAAcJmAt7mgAfAQAJAAcJHgt7mgAfAQAlAAQJ/wagMQBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8jAAMCAAgJQAwWEQBlAQACAAgJQAwWEQBlAQAIAAcJRgNtVgCxAAAAAA==.',
Re='Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgEJAQAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECggJGQANACsZAA==.',
Ri='Rina:BAACLgAFFH8cAAImAAYJjB7yAACjAQAmAAYJjB7yAACjAQAuAAQKfywAAyYACAlaIxUCAOoCACYACAlaIxUCAOoCAB8ABQmjEliJAOQAAAAA.Rineli:BAABLgAECn8nAAIOAAgJ2hFNWAC3AQAOAAgJ2hFNWAC3AQAAAA==.Ringadingg:BAABLgAECn8qAAIMAAgJlCMdGACUAgAMAAgJlCMdGACUAgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJKgAMAJQjAA==.Rivets:BAAALgADCgMJAwABLgAECggJGQAFANASAA==.',
Ro='Roastduck:BAABLgAECn8bAAIeAAgJ7RoXEQA2AgAeAAgJ7RoXEQA2AgAAAA==.Rosequartz:BAAALgAECgQJBgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJAgAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8OAAIJAAUJbiDEEgCLAQAJAAUJbiDEEgCLAQAuAAQKfzUAAgkACQncJUYBAH4DAAkACQncJUYBAH4DAAAA.',
Sc='Scony:BAAALgAECgcJCgAAAA==.Scribs:BAABLgAECn8UAAISAAgJtgITkgDnAAASAAgJtgITkgDnAAAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMOAAgJtB3zXwCjAQAOAAcJbxzzXwCjAQAdAAQJTh4SDAARAQABLgAFFAMJBgANAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJQQAMAH8XAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAECgkJGwAQAGEWAA==.Severautism:BAAALgAECgMJAwABLgAECgkJGwAQAGEWAA==.Severànce:BAAALgADCgQJBAABLgAECgkJGwAQAGEWAA==.Sevotion:BAABLgAECn8xAAQJAAkJUx0oNgBKAgAJAAgJKB0oNgBKAgAiAAkJSxUlFwApAgAlAAcJog8qLQClAAABLgAECgkJGwAQAGEWAA==.',
Sh='Shablammy:BAABLgAECn8lAAIHAAgJICUEBABUAwAHAAgJICUEBABUAwAAAA==.Shadownome:BAAALgAECgMJCwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgADCgUJBQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJLAAlACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgMJAwAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAABLgAECn8aAAISAAkJWQz6RgCgAQASAAkJWQz6RgCgAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQhAAkJeBrdDAA8AgAhAAkJZRndDAA8AgAGAAcJfRd6KADmAQASAAQJfRFJqwCwAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJBAAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJCAAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgIJAgAAAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgADCggJDgAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxwmCQDVAgABAAkJaxwmCQDVAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgMJBQABLgAFFAYJDwAjAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8bAAMQAAkJYRZ/EgAaAgAQAAkJYRZ/EgAaAgAeAAEJvQZgYgAtAAAAAA==.Stonemother:BAAALgAECgMJBwAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAWAAAAAA==.Stubly:BAAALgADCgEJAQAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECggJGgAJANwbAA==.',
Sw='Swampmonster:BAAALgAECgQJBwABLgAECgYJDwAWAAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIfAAQJchk3LwAtAQAfAAQJchk3LwAtAQAuAAQKfywAAx8ACAkkJAMRAPYCAB8ACAnOIwMRAPYCACMABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgYJDAAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAECgcJFgAgAHYbAA==.Taurastrage:BAABLgAECn8WAAIgAAcJdhuNEwCNAQAgAAcJdhuNEwCNAQAAAA==.Taurdk:BAAALgAECgcJEQABLgAECgcJFgAgAHYbAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAABLgAECn8eAAIKAAgJZx9WDABrAgAKAAgJZx9WDABrAgAAAA==.Tazarakk:BAAALgADCgMJAwABLgAECggJFQAgAAQhAA==.Tazbeard:BAAALgADCgYJCQABLgAECggJFQAgAAQhAA==.',
Te='Teedos:BAAALgAECggJDQABLgAECgkJMQAIAEAaAA==.Teetau:BAABLgAECn80AAIVAAgJRgiHKADNAAAVAAgJRgiHKADNAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECggJOgAcAOQTAA==.Thadregosa:BAABLgAECn86AAMcAAgJ5BMdBwCtAQAcAAgJ5BMdBwCtAQAUAAcJwArwUQC8AAAAAA==.Thander:BAAALgADCgMJAwABLgAECgQJBwAWAAAAAA==.Thannicus:BAAALgAECgYJDAAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAITAAkJchwTDQDVAgATAAkJchwTDQDVAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQATAHIcAA==.Tiffy:BAAALgADCgkJNAAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAAALgAECgMJBwAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJAwAAAA==.',
To='Tokalu:BAABLgAECn8ZAAIkAAgJ0g9tIwBsAQAkAAgJ0g9tIwBsAQAAAA==.Tonjudsonson:BAACLgAFFH8dAAIVAAUJniJXAwCbAQAVAAUJniJXAwCbAQAuAAQKfywAAhUACQmCJfUAAGQDABUACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8ZAAIIAAgJrQtXNwAqAQAIAAgJrQtXNwAqAQAAAA==.Toxix:BAABLgAECn8WAAICAAcJSSJVCgDeAQACAAcJSSJVCgDeAQAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAECgkJDgAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8qAAIEAAcJAwk6EwDrAAAEAAcJAwk6EwDrAAAAAA==.Twobricks:BAABLgAECn8uAAITAAkJERPMIAAeAgATAAkJERPMIAAeAgAAAA==.',
Ty='Tyrssana:BAAALgAECgMJBwABLgAFFAMJCAAcANEGAA==.',
Ug='Uglykitten:BAABLgAECn8cAAIeAAYJIxo8IwCGAQAeAAYJIxo8IwCGAQAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAAALgAECggJEwAAAA==.Urlacher:BAAALgAECgEJAQAAAA==.',
Va='Vaccaria:BAAALgAECgMJAwABLgAECgMJAwAWAAAAAA==.Vaererelor:BAAALgAECgUJCgAAAA==.Valla:BAAALgAECgEJAQAAAA==.Varnzdort:BAAALgAECgkJCQABLgAFFAcJFgAHACYaAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgMJBwAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgYJDgAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECggJGAADAGwZAA==.Vierth:BAAALgAECgIJAgAAAA==.Vincenzo:BAACLgAFFH8RAAIkAAUJ1SQaBACmAQAkAAUJ1SQaBACmAQAuAAQKfxoAAiQACAk9I0MEAEgDACQACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBwAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgcJEgAAAA==.Viridiana:BAAALgAECgYJCgABLgAECggJKgAPAOgXAA==.Visea:BAAALgAECgMJBwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJBwAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECggJLAAAAQ==.Voznje:BAAALgAECgEJAQABLgAECgEJAQAWAAAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECgcJLQAaAMgWAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwAWAAAAAA==.Wesleypriest:BAABLgAECn8fAAMPAAkJBwn6IwB/AQAPAAkJ5gj6IwB/AQAeAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgIJAgAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8hAAIlAAgJ8xQODwCkAQAlAAgJ8xQODwCkAQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAOAEkXAA==.',
Xe='Xehorn:BAAALgAECgYJBgABLgAFFAcJFgAHACYaAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJDgAaAA0kAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIOAAcJSReajQC3AQAOAAcJSReajQC3AQAAAA==.',
Ya='Yashe:BAABLgAECn8eAAMHAAgJQx3GFAB4AgAHAAgJQx3GFAB4AgAIAAEJWAjekQAlAAAAAA==.',
Yh='Yhorn:BAAALgAFFAMJAwABLgAFFAcJFgAHACYaAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAYAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJBwAAAA==.Zareena:BAAALgADCgYJCQAAAA==.Zarnia:BAAALgAECgQJBwAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJBwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJFgAHACYaAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zeratule:BAAALgADCgYJBgAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn9DAAIJAAkJvB0fEwC1AgAJAAkJvB0fEwC1AgAAAA==.',
Zi='Zijo:BAAALgAECgYJCgAAAA==.Zinnkura:BAAALgAECgMJCAAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8bAAIDAAYJZgzGkAAEAQADAAYJZgzGkAAEAQAAAA==.',
['Ñô']='Ñôg:BAAALgAECgIJAQAAAA==.',
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
