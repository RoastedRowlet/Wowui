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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Balance','Mage-Frost','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','DemonHunter-Devourer','Warrior-Protection','Hunter-Survival','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Paladin-Protection','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBwAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8ZAAIBAAcJSA0gQgAwAQABAAcJSA0gQgAwAQAAAA==.Aegennai:BAABLgAECn8fAAICAAgJ7gbmFgAyAQACAAgJ7gbmFgAyAQAAAA==.Aegon:BAECLgAFFH8cAAMDAAcJqxw/HQCfAQADAAYJyxs/HQCfAQAEAAEJDSGUEABmAAAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAUAAwmUHL4pABsBAAAA.Aegondh:BAEALgAECgMJAwABLgAFFAcJHAADAKscAA==.Aeli:BAAALgAECgIJAgABLgAECgcJGQABAEgNAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIGAAIJPByvJwCvAAAGAAIJPByvJwCvAAAuAAQKfzYAAgYACQlSHjQMAEoCAAYACQlSHjQMAEoCAAAA.',
Ag='Agilaz:BAABLgAECn8xAAIHAAgJcBsFBwAGAgAHAAgJcBsFBwAGAgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAIANEeAA==.',
Ak='Akey:BAAALgAECgUJDAAAAQ==.Akhae:BAACLgAFFH8IAAIIAAIJ0BiMTQCfAAAIAAIJ0BiMTQCfAAAuAAQKfyUAAwgACQkVFoIrAPIBAAgACQkVFoIrAPIBAAkACQneDSYsAHsBAAAA.Akrihail:BAAALgAECgQJBgAAAA==.',
Al='Albinism:BAABLgAECn8pAAICAAcJLhVUEgBwAQACAAcJLhVUEgBwAQAAAA==.Alcadeias:BAABLgAECn8kAAIKAAcJ8xVigwBNAQAKAAcJ8xVigwBNAQAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8nAAILAAkJGhj/FQAJAgALAAkJGhj/FQAJAgAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8YAAIKAAkJSAttrgAmAQAKAAkJSAttrgAmAQAAAA==.Andrömëdä:BAAALgAECgcJDgAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8VAAIMAAYJ0QhXxgDhAAAMAAYJ0QhXxgDhAAAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJGQABAEgNAA==.',
Aq='Aquindra:BAAALgAECgMJBAAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn8zAAINAAkJEyFIBAD1AgANAAkJEyFIBAD1AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAAAAQ==.',
Ba='Baconpancake:BAAALgAECgcJDQAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgcJCwAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAAALgAECgQJBwAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAABLgAECn8iAAMOAAkJ+RgqIgBqAgAOAAkJ+RgqIgBqAgAPAAgJOAVxLgDRAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECgMJAwAAAA==.Beastlypläyä:BAAALgAECgYJCAAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECgkJMAAMAJgiAA==.Bessarion:BAAALgADCgYJBgAAAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgcJGAAAAA==.Blindhealz:BAACLgAFFH8GAAIQAAMJLwoILAC6AAAQAAMJLwoILAC6AAAuAAQKfy0AAxAACAnUFdYYAOkBABAACAnUFdYYAOkBABEABQl4C3tEANcAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAAALgAECgcJDgAAAA==.',
Bo='Bonerblast:BAAALgAECgMJBAAAAA==.Boston:BAABLgAECn81AAQOAAkJhyS5DgDlAgAOAAkJhyS5DgDlAgAPAAcJzA6qJQAMAQASAAMJhBslHwCgAAAAAA==.',
Br='Braesong:BAAALgADCgIJAgAAAA==.Brewtholomew:BAABLgAECn8pAAITAAkJ9RH8OwDYAQATAAkJ9RH8OwDYAQAAAA==.Briggsey:BAABLgAECn8lAAIDAAgJfQ2pXQB7AQADAAgJfQ2pXQB7AQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBmPOwDfAQADAAcJxBiPOwDfAQAFAAIJbyD8KQBfAAAAAA==.Brounies:BAABLgAECn8XAAIUAAcJmAibZAD1AAAUAAcJmAibZAD1AAAAAA==.Bryce:BAABLgAECn8ZAAIKAAgJRBTXXwCYAQAKAAgJRBTXXwCYAQAAAA==.Brèanna:BAAALgAECgMJBgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Bunnyfu:BAAALgAECgYJEAABLgAECgcJKAAVAH0XAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8FAAIIAAIJLgu/WwBwAAAIAAIJLgu/WwBwAAAuAAQKfykAAggACAmMInwKANQCAAgACAmMInwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIWAAcJcBhBEwCdAQAWAAcJcBhBEwCdAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8eAAITAAgJsAS+jgAHAQATAAgJsAS+jgAHAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgYJDQAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwAXAAAAAA==.Carnìfex:BAABLgAECn8jAAMYAAYJ4BonGQB6AQAYAAYJ4BonGQB6AQAZAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAABLgAECn8WAAQaAAgJoCGmEACJAQAaAAgJoCGmEACJAQAWAAQJtBfJIwAMAQAUAAMJdxbOewCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIbAAgJKAyPCwBkAQAbAAgJKAyPCwBkAQAAAA==.Cephandrius:BAAALgAECgQJBAAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJHQAJAPMbAA==.Cheetah:BAAALgAECgMJCAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8UAAIZAAgJzAdgPwAyAQAZAAgJzAdgPwAyAQAAAA==.Cloudbreaker:BAAALgAECgQJBgAAAA==.Cloudkeg:BAAALgAECgQJCAAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECggJDQAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAABLgAECn8WAAIUAAgJdAqxUAA5AQAUAAgJdAqxUAA5AQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8dAAMJAAkJ8xt0KQDJAQAJAAcJshx0KQDJAQAIAAMJWwo6kACQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn81AAMbAAgJ3havCwBhAQAGAAgJCxF7HQCRAQAbAAYJuRivCwBhAQAAAA==.Damnitsu:BAEBLgAECn8aAAMGAAcJzQ2fKAA2AQAGAAcJ8AyfKAA2AQAbAAMJaw5FFwCjAAABLgAECggJNQAbAN4WAA==.Darkcat:BAABLgAECn8rAAIaAAgJlAeiHAD+AAAaAAgJlAeiHAD+AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgMJCAAAAA==.',
De='Deadflexy:BAABLgAECn8ZAAIPAAgJKxnsEwC5AQAPAAgJKxnsEwC5AQAAAA==.Dear:BAAALgAECgUJCwAAAA==.Deathberry:BAABLgAECn87AAIDAAgJUCIIEgCwAgADAAgJUCIIEgCwAgAAAA==.Deathdoodles:BAACLgAFFH8HAAIOAAIJqwuFxACFAAAOAAIJqwuFxACFAAAuAAQKfyAAAg4ACQkkGC8yACICAA4ACQkkGC8yACICAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAQAAAA==.Deekan:BAABLgAECn8cAAIKAAkJrQZIkQA0AQAKAAkJrQZIkQA0AQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgAECgQJBAABLgAFFAMJCQAVAEoUAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8VAAIRAAgJ8ghiOAAQAQARAAgJ8ghiOAAQAQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAXAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAABLgAECn8rAAIKAAgJ5wfMnAAhAQAKAAgJ5wfMnAAhAQAAAA==.',
Di='Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgUJBQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAAALgAECggJCAAAAA==.',
Do='Dobby:BAAALgAECgUJDAAAAA==.',
Dr='Dragondude:BAABLgAECn80AAMcAAkJrCGPAQBzAwAcAAkJrCGPAQBzAwAdAAEJNA4aIgA3AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIYAAQJgxjeDwAyAQAYAAQJgxjeDwAyAQAuAAQKfzoAAhgACQmpIDwDAOsCABgACQmpIDwDAOsCAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn8zAAQDAAkJmSEOBwAWAwADAAkJbyEOBwAWAwAFAAIJyhOASQCSAAAEAAIJVh5KKgBbAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMbAAgJkBIkCADWAQAbAAgJkBIkCADWAQAGAAYJPAouOQBMAQAAAA==.',
El='Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn81AAMMAAkJVSAYDgD1AgAMAAkJVSAYDgD1AgAeAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQAMAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgMJCAAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Es='Espii:BAAALgAECgkJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAXAAAAAA==.Etheri:BAAALgAECgcJCQAAAA==.',
Ev='Evilorc:BAAALgADCgcJCgAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgAXAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8oAAMUAAgJnCFJCgAGAwAUAAgJnCFJCgAGAwALAAIJuwzNgAAwAAAAAA==.Fakesaint:BAACLgAFFH8IAAIIAAQJ+BPjIwA0AQAIAAQJ+BPjIwA0AQAuAAQKfzQAAggACQmfIboGADADAAgACQmfIboGADADAAAA.Fangstorm:BAABLgAECn8vAAIaAAkJHRKpDADKAQAaAAkJHRKpDADKAQAAAA==.Farorê:BAABLgAECn8YAAIfAAYJ6BdWJgB8AQAfAAYJ6BdWJgB8AQAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIgAAkJ2hf5KAARAgAgAAkJ2hf5KAARAgAAAA==.Feldruid:BAAALgADCgMJAwAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8FAAIhAAIJQQTjIgBbAAAhAAIJQQTjIgBbAAAuAAQKfzoAAyEACAnXD/QXAGgBACEACAnXD/QXAGgBABkAAgm+A0mGAEcAAAAA.',
Fo='Foreverem:BAAALgAECgIJAgAAAA==.',
Fr='Fritopaws:BAABLgAECn88AAMHAAkJ9R2YAgCwAgAHAAkJhR2YAgCwAgAiAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgEJAQAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJDwAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECggJDQAAAA==.Gaska:BAAALgAECggJCAABLgAECgkJHwABAGscAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn8xAAMSAAgJMwrxEwARAQAOAAgJswdCiAA/AQASAAgJFQrxEwARAQAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJDwABLgAECggJFQADAKkaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECgcJCQAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAABLgAECn8oAAIVAAcJfRfcKQB9AQAVAAcJfRfcKQB9AQAAAA==.Gummypenguin:BAABLgAECn8VAAMTAAgJGhqcTACDAQATAAcJiBmcTACDAQAHAAYJTQzRVQDyAAABLgAFFAUJHQATAMMgAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8bAAIZAAkJJg3jKQCbAQAZAAkJJg3jKQCbAQAAAA==.Hakano:BAABLgAECn8lAAINAAYJrgPBUgCoAAANAAYJrgPBUgCoAAAAAA==.Harbiin:BAAALgAECgIJAgAAAA==.Hathdox:BAABLgAECn8hAAITAAcJTRh+SwCnAQATAAcJTRh+SwCnAQABLgAECgkJGwAZACYNAA==.Hazelnoot:BAABLgAECn8mAAMKAAkJ0BvoJgBPAgAKAAkJ0BvoJgBPAgAjAAYJugUhUADgAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAIkAAkJAhPFEQDwAQAkAAkJAhPFEQDwAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn8sAAIcAAgJ4gm1FgBQAQAcAAgJ4gm1FgBQAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8rAAIFAAgJ0AviDwAoAQAFAAgJ0AviDwAoAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgAXAAAAAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJCAAXAAAAAA==.Hornsnap:BAABLgAECn8eAAMIAAcJYR1LIgAnAgAIAAcJYR1LIgAnAgAJAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAXAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAECgcJKAAVAH0XAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQHAAMJfBxZGADQAAAHAAIJ0CNZGADQAAAiAAIJRxeXIgCdAAATAAEJqiagegBkAAAuAAQKfz0ABAcACQnAJaQDAGoDAAcACAnDJaQDAGoDACIACAldI7cGAKkCABMAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgMJCAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAABLgAECn8pAAMIAAcJ3hfqNACwAQAIAAcJ3hfqNACwAQAJAAYJixqmKgCEAQAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQAXAAAAAA==.Ilovekayla:BAAALgAECgEJBAAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECggJGAAVAGoPAA==.Insaint:BAACLgAFFH8NAAIKAAQJhBOkNwAkAQAKAAQJhBOkNwAkAQAuAAQKfzMAAgoACQl2GkkuAC4CAAoACQl2GkkuAC4CAAAA.',
Is='Isabellë:BAABLgAECn8lAAMRAAgJ1wd5OwABAQARAAgJ1wd5OwABAQAfAAIJnAO/YABCAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhGJaABhAQADAAcJAhGJaABhAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJSwAZAKUkAA==.',
Je='Jessamine:BAABLgAECn8hAAIMAAkJXxjoOAAeAgAMAAkJXxjoOAAeAgAAAA==.Jessicafelba:BAABLgAECn8VAAMDAAgJqRqIOwDfAQADAAcJqRqIOwDfAQAFAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8pAAIaAAcJZBIfFABZAQAaAAcJZBIfFABZAQAAAA==.Jezzak:BAABLgAECn8mAAITAAgJmhqPNwDoAQATAAgJmhqPNwDoAQABLgAECgkJMQATAAEbAA==.',
Jo='John:BAAALgAECgkJEAAAAA==.Jorien:BAABLgAECn9KAAITAAkJ/BpiHABlAgATAAkJ/BpiHABlAgAAAA==.',
Jp='Jp:BAAALgAECgUJCAABLgAECgYJCAAXAAAAAA==.Jps:BAAALgAECgYJCAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECggJGAADAGwZAA==.',
Ka='Kaboonski:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMfAAkJWxhHGAAaAgAfAAkJWxhHGAAaAgARAAIJmxF0ZABcAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJDwAAAA==.Kamikori:BAABLgAECn8kAAMZAAgJ1hw+IwDFAQAZAAcJZBw+IwDFAQAhAAYJvBgAGABoAQAAAA==.Kardelbrew:BAAALgAECgMJAwABLgAECgYJEQAXAAAAAA==.Kardels:BAAALgAECgYJEQAAAA==.Karnn:BAACLgAFFH8XAAMlAAUJdh6JCwBQAQAlAAUJdh6JCwBQAQANAAEJHQFRKgArAAAuAAQKfycAAyUACAl3JJQKAM8CACUACAl3JJQKAM8CAAEABglfEJJHABkBAAAA.Katalight:BAAALgAECgQJAQABLgAECgcJCQAXAAAAAA==.Katrini:BAAALgAECgcJCQAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAMALAdAA==.',
Ki='Kiascendance:BAAALgAECgkJEgAAAA==.Kiplet:BAABLgAECn8aAAIfAAkJpBYlIACsAQAfAAkJpBYlIACsAQAAAA==.',
Kn='Knockback:BAAALgAECgMJBQAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Korxon:BAABLgAECn8fAAMQAAgJkhelHgC1AQAQAAgJkhelHgC1AQAfAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAXAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECggJGQAPACsZAA==.',
Ks='Ksyusha:BAAALgAECgUJDAAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgEJAQAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJJwAMAGsVAA==.',
La='Lahabrea:BAABLgAECn8fAAMFAAgJBA3wKwAPAQADAAgJwQryfAA0AQAFAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAAALgAECgYJCgAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAVAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBgAAAA==.',
Le='Leeara:BAABLgAECn8bAAIgAAgJQhmmNQAhAgAgAAgJQhmmNQAhAgAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgAPAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalbimbo:BAAALgAECgUJCgAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIIAAcJ0R7uAQCYAgAIAAcJ0R7uAQCYAgAuAAQKfyEAAwgACAmAI0sQAJUCAAgABwkOI0sQAJUCAAkAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Ly='Lyv:BAAALgAECgEJAQAAAA==.',
['Lø']='Løllîe:BAAALgAECgUJDAAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgUJDAAXAAAAAA==.',
Ma='Madsharona:BAAALgAECgkJCQAAAA==.Magatai:BAABLgAECn8ZAAIMAAcJYAf4tQD8AAAMAAcJYAf4tQD8AAAAAA==.Mageless:BAAALgAECgEJAQAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAAXAAAAAA==.Manaster:BAAALgAECgcJCgAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwAXAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8gAAMOAAcJ5xgZbAB5AQAOAAcJ5xgZbAB5AQASAAIJEBbcFABGAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAAALgAECgIJAgAAAA==.Maynis:BAAALgADCgcJCwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgMJCAAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgUJBgAAAA==.',
Mi='Micflinigan:BAABLgAECn8qAAMZAAkJLxYTIQDVAQAZAAgJzRYTIQDVAQAhAAEJ3hGVSgA1AAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAfAKQWAA==.Misahaviran:BAAALgAECgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Misla:BAAALgADCgIJAgAAAA==.Mistynite:BAAALgADCgkJDwAAAA==.',
Mo='Mochimochi:BAAALgAECgQJBwAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgQJBAABLgAECgkJOgARAKEPAA==.Moonshae:BAABLgAECn8lAAIBAAkJjhICJADVAQABAAkJjhICJADVAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwALABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwALABoYAA==.Mouse:BAAALgAECgcJEwAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwAOAKsLAA==.Nails:BAABLgAECn8ZAAIGAAgJ0BJ0HACaAQAGAAgJ0BJ0HACaAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgcJDwABLgAECggJGQAlANIPAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Niralth:BAAALgAECgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAAXAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgAKANAbAA==.Noriisa:BAABLgAECn8xAAITAAkJARvaJAA4AgATAAkJARvaJAA4AgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIIAAgJghvqGwBSAgAIAAgJghvqGwBSAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgEJAQAAAA==.',
Ny='Nyvak:BAAALgAECgUJCwAAAA==.',
Od='Odinhand:BAABLgAECn8uAAILAAkJWwlTLABZAQALAAkJWwlTLABZAQAAAA==.',
Oe='Oenei:BAAALgADCgEJAQAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQAXAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIMAAkJmCI2DAADAwAMAAkJmCI2DAADAwAAAA==.Ozwäldo:BAAALgAECgYJCQABLgAECgkJMAAMAJgiAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8XAAIMAAUJbhWVDQCvAQAMAAUJbhWVDQCvAQAuAAQKfz8AAgwACQmpIuUNAPYCAAwACQmpIuUNAPYCAAAA.Pandóra:BAABLgAECn8UAAMRAAYJ2gLOWACEAAARAAYJ2gLOWACEAAAQAAMJlgKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMbAAMJ5SRJBAA3AQAbAAMJ5SRJBAA3AQAGAAIJcB7+EADBAAAuAAQKfzoAAxsACQmjJjUAAH0DABsACQl1JjUAAH0DAAYACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAXAAAAAA==.Pinkeepink:BAABLgAECn8gAAIFAAcJWQg/FQDjAAAFAAcJWQg/FQDjAAAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Potangwang:BAAALgAECgcJDgAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Pu='Punchysev:BAAALgAFFAIJAgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8oAAIPAAkJDyLABgCfAgAPAAkJDyLABgCfAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8XAAMKAAcJcgxiqAAPAQAKAAcJcgxiqAAPAQAmAAQJ/waINQBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8qAAMCAAgJkg4mEQCAAQACAAgJkg4mEQCAAQAJAAcJRgMFXQCxAAAAAA==.Raynë:BAAALgAECgQJBAABLgAECgkJGwAZACYNAA==.',
Re='Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgEJAQAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECggJGQAPACsZAA==.',
Ri='Rina:BAACLgAFFH8dAAInAAYJIh8+AQCmAQAnAAYJIh8+AQCmAQAuAAQKfywAAycACAlaIxUCAOoCACcACAlaIxUCAOoCACAABQmjEh2TANwAAAAA.Rineli:BAABLgAECn8rAAIMAAgJeRIYWwC0AQAMAAgJeRIYWwC0AQAAAA==.Ringadingg:BAABLgAECn8xAAIOAAgJZiRQEQDRAgAOAAgJZiRQEQDRAgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJMQAOAGYkAA==.Rivets:BAAALgADCgMJAwABLgAECggJGQAGANASAA==.',
Ro='Roastduck:BAABLgAECn8bAAIfAAgJ7RoAEwAtAgAfAAgJ7RoAEwAtAgAAAA==.Rosequartz:BAAALgAECgQJBgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJAwAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8PAAIKAAYJIholFACTAQAKAAYJIholFACTAQAuAAQKfzUAAgoACQncJbUBAHEDAAoACQncJbUBAHEDAAAA.',
Sc='Scony:BAAALgAECgkJEgAAAA==.Screws:BAAALgADCgYJBgAAAA==.Scribs:BAABLgAECn8bAAITAAgJmANjjAAMAQATAAgJmANjjAAMAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMMAAgJtB0tawCMAQAMAAcJbxwtawCMAQAeAAQJTh4SDAARAQABLgAFFAMJBgAPAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJSgAOABUYAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAIJAgAXAAAAAA==.Severautism:BAAALgAECgMJAwABLgAFFAIJAgAXAAAAAA==.Severànce:BAAALgADCgQJBAABLgAFFAIJAgAXAAAAAA==.Sevotion:BAABLgAECn8xAAQKAAkJUx0oNgBKAgAKAAgJKB0oNgBKAgAjAAkJSxV7GQAkAgAmAAcJog8qLQClAAABLgAFFAIJAgAXAAAAAA==.',
Sh='Shablammy:BAABLgAECn8tAAMIAAgJICXqBABRAwAIAAgJICXqBABRAwAJAAEJ6BD4kQAzAAAAAA==.Shadownome:BAAALgAECgMJCwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgADCgUJBQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJMwAmACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgMJBAAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAABLgAECn8aAAITAAkJWQzYTQCgAQATAAkJWQzYTQCgAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQiAAkJeBqHDgA1AgAiAAkJZRmHDgA1AgAHAAcJfRd6KADmAQATAAQJfREkuwCrAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJBQAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJCAAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgQJBgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAYJKgAMAPsjAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxw+CgDVAgABAAkJaxw+CgDVAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgMJBQABLgAFFAYJDwAkAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8bAAMRAAkJYRZpFAAOAgARAAkJYRZpFAAOAgAfAAEJvQbXZwAtAAABLgAFFAIJAgAXAAAAAA==.Stonemother:BAAALgAECgMJBwAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAXAAAAAA==.Stubly:BAAALgADCgEJAQAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECggJGgAKANwbAA==.',
Sw='Swampmonster:BAAALgAECgQJCwABLgAECgYJDwAXAAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIgAAQJchnENwAiAQAgAAQJchnENwAiAQAuAAQKfywAAyAACAkkJAMRAPYCACAACAnOIwMRAPYCACQABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgcJDQAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAECgkJGgASAOMZAA==.Taurastrage:BAABLgAECn8WAAIhAAcJdhuIEwDTAQAhAAcJdhuIEwDTAQABLgAECgkJGgASAOMZAA==.Taurdk:BAABLgAECn8aAAMSAAkJ4xmLAwCBAgASAAkJ4xmLAwCBAgAOAAIJQgY7KAFXAAAAAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8IAAILAAMJSRszIgDuAAALAAMJSRszIgDuAAAuAAQKfx4AAgsACAlnH8cNAGgCAAsACAlnH8cNAGgCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECggJFQAhAAQhAA==.Tazbeard:BAAALgADCgYJCQABLgAECggJFQAhAAQhAA==.Tazllidan:BAAALgADCgYJBgABLgAECggJFQAhAAQhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJSgAOABUYAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgAJAKgeAA==.Teetau:BAABLgAECn87AAIWAAkJege6KQDlAAAWAAkJege6KQDlAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJQgAdACUZAA==.Thadregosa:BAABLgAECn9CAAMdAAkJJRmRAgCAAgAdAAkJJRmRAgCAAgAVAAcJwApgVgCyAAAAAA==.Thander:BAAALgADCgMJAwABLgAECgQJCAAXAAAAAA==.Thannicus:BAAALgAECgYJDAAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIUAAkJchwmDgDWAgAUAAkJchwmDgDWAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAUAHIcAA==.Tiffy:BAAALgADCgkJPQAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAAALgAECgUJDAAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJBAAAAA==.',
To='Tokalu:BAABLgAECn8ZAAIlAAgJ0g+nJgBpAQAlAAgJ0g+nJgBpAQAAAA==.Tonjudsonson:BAACLgAFFH8eAAIWAAYJoyE5AgDvAQAWAAYJoyE5AgDvAQAuAAQKfywAAhYACQmCJfUAAGQDABYACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8ZAAIJAAgJrQsRPAAoAQAJAAgJrQsRPAAoAQAAAA==.Toxix:BAABLgAECn8dAAICAAgJtiNyAwC5AgACAAgJtiNyAwC5AgAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8tAAIFAAgJZAieEgAGAQAFAAgJZAieEgAGAQAAAA==.Twobricks:BAABLgAECn8uAAIUAAkJERNPIwAdAgAUAAkJERNPIwAdAgAAAA==.',
Ty='Tyrssana:BAAALgAECgUJDAABLgAFFAQJCgAdABIHAA==.',
Ug='Uglykitten:BAABLgAECn8cAAIfAAYJIxoBJgB+AQAfAAYJIxoBJgB+AQAAAA==.',
Uh='Uhmerica:BAABLgAECn8uAAImAAkJyRlBBwBTAgAmAAkJyRlBBwBTAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAAALgAECggJEwAAAA==.Urlacher:BAAALgAECgEJAQAAAA==.',
Va='Vaccaria:BAAALgAECgMJAwABLgAECgMJAwAXAAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDAAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAIANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgUJDAAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECggJGAADAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAIlAAUJ1SSQBQCeAQAlAAUJ1SSQBQCeAQAuAAQKfxoAAiUACAk9I0MEAEgDACUACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBwAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgcJEwAAAA==.Viridiana:BAAALgAECgYJCgAAAA==.Visea:BAAALgAECgMJBwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCAAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECggJMwAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECggJNQAbAN4WAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwAXAAAAAA==.Wesleypriest:BAABLgAECn8fAAMQAAkJBwl0KQBjAQAQAAkJ5gh0KQBjAQAfAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgMJBAAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8pAAImAAgJJRUuEACnAQAmAAgJJRUuEACnAQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAMAEkXAA==.',
Xe='Xear:BAAALgADCgUJBQABLgADCgkJPQAXAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAIANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAbAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIMAAcJSReajQC3AQAMAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMIAAgJQx1+FwB1AgAIAAgJQx1+FwB1AgAJAAEJWAjekQAlAAABLgAECgkJIgAOAPkYAA==.',
Yh='Yhorn:BAAALgAFFAMJAwABLgAFFAcJGgAIANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAZAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCAAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCAAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAIANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAAALgADCggJCAAAAA==.Zeratule:BAAALgADCgkJCgAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn9MAAIKAAkJGx6wEwC4AgAKAAkJGx6wEwC4AgAAAA==.',
Zi='Zijo:BAAALgAECgYJCgAAAA==.Zinnkura:BAAALgAECgUJDQAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8fAAIDAAcJUg12dQBDAQADAAcJUg12dQBDAQAAAA==.',
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
