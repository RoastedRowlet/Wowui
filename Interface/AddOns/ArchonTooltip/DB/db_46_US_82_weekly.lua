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
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBwAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8cAAIBAAcJSA3ITAAyAQABAAcJSA3ITAAyAQAAAA==.Aegennai:BAABLgAECn8oAAICAAkJVwc/FQBlAQACAAkJVwc/FQBlAQAAAA==.Aegon:BAECLgAFFH8cAAMDAAcJqxxlLACKAQADAAYJyxtlLACKAQAEAAEJDSFeFQBlAAAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAUAAwmUHL4pABsBAAAA.Aegondh:BAEBLgAFFH8GAAIGAAYJ6AgoUAD2AAAGAAYJ6AgoUAD2AAABLgAFFAcJHAADAKscAA==.Aeli:BAAALgAECgQJBAABLgAECgcJHAABAEgNAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIHAAIJPBx5LgCoAAAHAAIJPBx5LgCoAAAuAAQKfzYAAgcACQlSHkUOAEECAAcACQlSHkUOAEECAAAA.',
Ag='Agilaz:BAABLgAECn8yAAIIAAkJeRrSBQA8AgAIAAkJeRrSBQA8AgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.',
Ak='Akey:BAAALgAECgYJEgAAAQ==.Akhae:BAACLgAFFH8IAAIJAAIJ0BhAWQCVAAAJAAIJ0BhAWQCVAAAuAAQKfyUAAwkACQkVFsUwAO0BAAkACQkVFsUwAO0BAAoACQneDc0xAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8pAAICAAcJLhW9FABsAQACAAcJLhW9FABsAQAAAA==.Alcadeias:BAABLgAECn8qAAILAAcJFxbHigBYAQALAAcJFxbHigBYAQAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8nAAIMAAkJGhgAGQABAgAMAAkJGhgAGQABAgAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8YAAILAAkJSAttrgAmAQALAAkJSAttrgAmAQAAAA==.Andrömëdä:BAABLgAECn8UAAINAAcJRBEhJQBKAQANAAcJRBEhJQBKAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8bAAIOAAYJqwnFzQDxAAAOAAYJqwnFzQDxAAAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJHAABAEgNAA==.',
Aq='Aquindra:BAAALgAECgMJBAAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arluz:BAAALgADCgQJBAAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn82AAIPAAkJuCFOBAD/AgAPAAkJuCFOBAD/AgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astérion:BAAALgAFFAEJAQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAEJAQAQAAAAAQ==.',
Ba='Baconpancake:BAAALgAECgcJEwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldpunch:BAAALgAECgQJBAAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgcJEQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAAALgAECgcJEgAAAA==.Barendor:BAAALgADCgUJAQAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMRAAkJIxrYJABvAgARAAkJIxrYJABvAgASAAgJOAVmMwDKAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECgcJDAAAAA==.Beastlypläyä:BAAALgAECgYJDAAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAQJCAACAB0PAA==.Bessarion:BAAALgADCgYJBgAAAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.Bizmofunyuns:BAAALgAECgEJAQAAAA==.',
Bl='Blacksabbth:BAAALgAECgMJBgAAAA==.Blindhealz:BAACLgAFFH8HAAITAAMJLwq8NACyAAATAAMJLwq8NACyAAAuAAQKfzAAAxMACAnMF18XABcCABMACAnMF18XABcCABQABQl4C/5JAOQAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAABLgAECn8UAAIVAAcJkw2WIQAEAQAVAAcJkw2WIQAEAQAAAA==.',
Bo='Bonerblast:BAAALgAECgMJBAAAAA==.Boston:BAABLgAECn81AAQRAAkJhyT5EQDcAgARAAkJhyT5EQDcAgASAAcJzA6oKQAHAQAWAAMJhBvuJQCdAAAAAA==.Bowflex:BAAALgAECggJDgAAAA==.',
Br='Braesong:BAAALgADCgYJDQAAAA==.Brewtholomew:BAABLgAECn8rAAIXAAkJ9RF3RQDNAQAXAAkJ9RF3RQDNAQAAAA==.Briggsey:BAABLgAECn8lAAIDAAgJfQ2NZwBtAQADAAgJfQ2NZwBtAQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBk8QADbAQADAAcJxBg8QADbAQAFAAIJbyBFLgBeAAAAAA==.Brounies:BAABLgAECn8XAAIYAAcJmAgfawDxAAAYAAcJmAgfawDxAAAAAA==.Brunna:BAAALgADCgIJAgAAAA==.Bryce:BAABLgAECn8ZAAILAAgJRBS4awCUAQALAAgJRBS4awCUAQAAAA==.Brèanna:BAAALgAECgQJCgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgAECgMJAgAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBQAZAMUNAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJCQAaAHEEAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8GAAIJAAMJKhJLTQC3AAAJAAMJKhJLTQC3AAAuAAQKfy8AAgkACAmMInwKANQCAAkACAmMInwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIbAAcJcBhnFgCaAQAbAAcJcBhnFgCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIXAAgJ3QSimQAIAQAXAAgJ3QSimQAIAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgAECgMJAgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgYJEwAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwAQAAAAAA==.Carnìfex:BAABLgAECn8pAAMcAAYJ4BrLGwB5AQAcAAYJ4BrLGwB5AQAdAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJBQAAAA==.Catbrin:BAABLgAECn8XAAQeAAkJRiK6CwD6AQAeAAkJRiK6CwD6AQAbAAQJtBdDKQAKAQAYAAMJdxaxgQCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIfAAgJKAzBDABcAQAfAAgJKAzBDABcAQAAAA==.Cephandrius:BAAALgAECgQJBAAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJHgAKAPMbAA==.Cheetah:BAAALgAECgQJDAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8VAAIdAAkJ/wehNwBoAQAdAAkJ/wehNwBoAQAAAA==.Cloudbreaker:BAAALgAECgYJCgAAAA==.Cloudkeg:BAAALgAECgQJCAAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgkJEAAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJEgAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIYAAkJBAp6SgBiAQAYAAkJBAp6SgBiAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8eAAMKAAkJ8xt0KQDJAQAKAAcJshx0KQDJAQAJAAMJWwoonQCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn9FAAMfAAgJpxmACgCMAQAHAAgJchKsHgCdAQAfAAYJqhqACgCMAQAAAA==.Damnitsu:BAEBLgAECn8hAAMfAAcJYhTcDABaAQAfAAYJWxXcDABaAQAHAAcJ9g43KABRAQABLgAECggJRQAfAKcZAA==.Darkcat:BAABLgAECn8rAAIeAAgJlAd6IQD2AAAeAAgJlAd6IQD2AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgQJDAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAISAAkJWBo7DwAVAgASAAkJWBo7DwAVAgAAAA==.Dear:BAAALgAFFAEJAgAAAA==.Deathberry:BAABLgAECn9CAAIDAAkJVyJsBwAdAwADAAkJVyJsBwAdAwAAAA==.Deathdoodles:BAACLgAFFH8HAAIRAAIJqwtN5gCAAAARAAIJqwtN5gCAAAAuAAQKfyAAAhEACQkkGMM4ABoCABEACQkkGMM4ABoCAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAQAAAA==.Decisively:BAAALgAECgEJAQAAAA==.Deekan:BAABLgAECn8eAAILAAkJwQYlmABBAQALAAkJwQYlmABBAQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBwABLgAFFAQJBgAOAFwSAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8XAAIUAAgJQgx0MwBJAQAUAAgJQgx0MwBJAQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAQAAAAAA==.Devlik:BAAALgAECgQJBAAAAA==.',
Df='Dfresh:BAABLgAECn8rAAILAAgJ5wdbqQAmAQALAAgJ5wdbqQAmAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgMJAQAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAAALgAECggJDwAAAA==.',
Do='Dobby:BAAALgAECgYJEAAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMgAAkJEiKYAQB4AwAgAAkJEiKYAQB4AwAhAAEJNA7cJAA1AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIcAAQJgxjjFQApAQAcAAQJgxjjFQApAQAuAAQKfzoAAhwACQmpIPgDAOICABwACQmpIPgDAOICAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQDAAkJwyJ8BgAnAwADAAkJmSJ8BgAnAwAFAAIJyhOASQCSAAAEAAIJVh5LMABaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMfAAgJkBIkCADWAQAfAAgJkBIkCADWAQAHAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMOAAkJZyBuEAD2AgAOAAkJZyBuEAD2AgAiAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQAOAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgQJDAAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Es='Espii:BAAALgAECgkJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAQAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Ev='Evilorc:BAAALgAECgEJAQAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgAQAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8rAAMYAAkJuyGSCwAEAwAYAAgJnCGSCwAEAwAMAAQJDw7LXgCXAAAAAA==.Fakesaint:BAACLgAFFH8NAAIJAAUJNhMrIwBYAQAJAAUJNhMrIwBYAQAuAAQKfzUAAgkACQmfISYIACsDAAkACQmfISYIACsDAAAA.Fangstorm:BAABLgAECn8yAAIeAAkJdxNkDQDbAQAeAAkJdxNkDQDbAQAAAA==.Farorê:BAABLgAECn8YAAIjAAYJ6BfHKQB1AQAjAAYJ6BfHKQB1AQAAAA==.Fatmann:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIGAAkJ2hf4LAAQAgAGAAkJ2hf4LAAQAgAAAA==.Feldruid:BAAALgAECgEJAgAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8LAAIkAAMJEAb4IgB6AAAkAAMJEAb4IgB6AAAuAAQKf0oAAyQACQlIGJMKAEICACQACQlIGJMKAEICAB0AAgm+A6CUAEQAAAAA.',
Fo='Foreverem:BAAALgAECgMJBQAAAA==.',
Fr='Fritopaws:BAABLgAECn8/AAMIAAkJ+h0YAwCmAgAIAAkJih0YAwCmAgAZAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgYJCAAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJEQAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJDgAAAA==.Gaska:BAAALgAECggJCAABLgAECgkJHwABAGscAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn9CAAMWAAkJ6AsJDgCSAQAWAAkJ6AsJDgCSAQARAAgJswddlgA4AQAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJDwABLgAECgkJFgADADcaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgMJAgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8JAAIaAAQJcQTtRQCtAAAaAAQJcQTtRQCtAAAuAAQKfygAAhoABwl9F9UtAIIBABoABwl9F9UtAIIBAAAA.Gummypenguin:BAABLgAECn8VAAMXAAgJGhqcTACDAQAXAAcJiBmcTACDAQAIAAYJTQzRVQDyAAABLgAFFAUJHQAXAMMgAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8fAAIdAAkJHw7eKAC1AQAdAAkJHw7eKAC1AQABLgAECgkJIwAXAMYUAA==.Hakano:BAABLgAECn8lAAIPAAYJrgMAWACmAAAPAAYJrgMAWACmAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8jAAIXAAkJxhSEMgAOAgAXAAkJxhSEMgAOAgAAAA==.Hawkulees:BAAALgAECgIJAQAAAA==.Hazelnoot:BAABLgAECn8mAAMLAAkJ0BvILABLAgALAAkJ0BvILABLAgAlAAYJugWGVQDfAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAINAAkJAhO2FADnAQANAAkJAhO2FADnAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn80AAIgAAkJMAn4FQBqAQAgAAkJMAn4FQBqAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8sAAIFAAkJjQtZDgBTAQAFAAkJjQtZDgBTAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBQAZAMUNAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJDAAQAAAAAA==.Hornsnap:BAABLgAECn8jAAMJAAcJzB3tIgA5AgAJAAcJzB3tIgA5AgAKAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAQAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAFFAQJCQAaAHEEAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQIAAMJfBxZGADQAAAIAAIJ0CNZGADQAAAZAAIJRxeGJgCaAAAXAAEJqibAkwBfAAAuAAQKfz0ABAgACQnAJaQDAGoDAAgACAnDJaQDAGoDABkACAldI78HAKICABcAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgQJDAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8IAAIJAAQJXhQ3NgACAQAJAAQJXhQ3NgACAQAuAAQKfzAAAwkABwl+G84tAPwBAAkABwl+G84tAPwBAAoABgmLGkIvAIABAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQAQAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwARABsfAA==.Insaint:BAACLgAFFH8SAAILAAQJqhbjQAAkAQALAAQJqhbjQAAkAQAuAAQKfzUAAgsACQkJG9AtAEcCAAsACQkJG9AtAEcCAAAA.',
Is='Isabellë:BAABLgAECn8vAAMUAAgJeQqrNwA0AQAUAAgJeQqrNwA0AQAjAAIJnAPFZwBBAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
It='Ithdorel:BAAALgADCggJDQAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhHEbwBaAQADAAcJAhHEbwBaAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJSwAdAKUkAA==.',
Je='Jessamine:BAABLgAECn8hAAIOAAkJXxj/PgAdAgAOAAkJXxj/PgAdAgAAAA==.Jessicafelba:BAABLgAECn8WAAMDAAkJNxp5LQAhAgADAAgJNxp5LQAhAgAFAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8wAAIeAAcJgBZcEQCdAQAeAAcJgBZcEQCdAQAAAA==.Jezzak:BAABLgAECn8mAAIXAAgJmhoRQQDbAQAXAAgJmhoRQQDbAQABLgAECgkJMQAXAAEbAA==.',
Jo='John:BAABLgAFFH8IAAIfAAQJJyCZAgCHAQAfAAQJJyCZAgCHAQAAAA==.Jorien:BAABLgAECn9XAAIXAAkJAxzrGgB/AgAXAAkJAxzrGgB/AgAAAA==.',
Jp='Jp:BAAALgAFFAEJAQAAAA==.Jps:BAAALgAECgYJCAABLgAFFAEJAQAQAAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECgkJGAADAGwZAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMjAAkJWxhHGAAaAgAjAAkJWxhHGAAaAgAUAAIJmxE9bABoAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJEAAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8sAAMdAAkJlx1REAB0AgAdAAkJPRxREAB0AgAkAAYJvBjQGgBeAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJFgAkAKAjAA==.Kardels:BAABLgAECn8WAAIkAAcJoCOACgBDAgAkAAcJoCOACgBDAgAAAA==.Karnn:BAACLgAFFH8XAAMmAAUJdh6pDgBEAQAmAAUJdh6pDgBEAQAPAAEJHQFRKgArAAAuAAQKfycAAyYACAl3JJQKAM8CACYACAl3JJQKAM8CAAEABglfENZSABsBAAAA.Katalight:BAAALgAECgQJAQABLgAECgcJCgAQAAAAAA==.Katrini:BAAALgAECgcJCgAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQAOALAdAA==.',
Ki='Kiascendance:BAAALgAECgkJEgAAAA==.Kiplet:BAABLgAECn8aAAIjAAkJpBa2IwChAQAjAAkJpBa2IwChAQAAAA==.',
Kn='Knockback:BAAALgAECgMJBQAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Korxon:BAABLgAECn8fAAMTAAgJkheNIQC/AQATAAgJkheNIQC/AQAjAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAQAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgASAFgaAA==.',
Ks='Ksyusha:BAAALgAECgYJEgAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgIJAwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJKgAOAGsVAA==.',
La='Lahabrea:BAABLgAECn8fAAMFAAgJBA3wKwAPAQADAAgJwQo+iAApAQAFAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAABLgAECn8hAAMbAAcJ2RvdEQDMAQAbAAcJ5xrdEQDMAQAeAAQJJhQoIQD4AAAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAaAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIGAAkJBBiNPADSAQAGAAkJBBiNPADSAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgASAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalbimbo:BAABLgAECn8VAAILAAgJKwuyogAxAQALAAgJKwuyogAxAQAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIJAAcJ0R4TBACEAgAJAAcJ0R4TBACEAgAuAAQKfyIAAwkACQnNI0sQAJUCAAkACAl0I0sQAJUCAAoAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.Littlebitt:BAAALgAFFAEJAQAAAQ==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Lu='Lunablue:BAAALgAECggJCAAAAA==.',
Ly='Lyv:BAAALgAECgEJAgAAAA==.',
['Lø']='Løllîe:BAAALgAECgYJEgAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgYJEgAQAAAAAA==.',
Ma='Macdee:BAAALgAECgEJAQAAAA==.Madsharona:BAAALgAECgkJCgAAAA==.Magatai:BAABLgAECn8aAAIOAAgJ5QZdnQA8AQAOAAgJ5QZdnQA8AQAAAA==.Mageless:BAAALgAECgUJBgAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAAQAAAAAA==.Manaster:BAAALgAECgcJCwAAAA==.Mandhos:BAAALgAECgMJAwAAAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwAQAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8iAAMRAAcJfBmJdQB2AQARAAcJ5xiJdQB2AQAWAAIJhxoaMgBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAAALgAECgUJCgAAAA==.Maynis:BAAALgAECgMJAwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgQJDgAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgYJCwAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMdAAkJLxYAJQDNAQAdAAgJzRYAJQDNAQAkAAEJ3hGlUQAzAAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAjAKQWAA==.Misahaviran:BAAALgAECgQJBQAAAA==.Mishelö:BAAALgAECgIJAgAAAA==.Misla:BAAALgADCgcJDgAAAA==.Misstriix:BAAALgAECgYJBgAAAA==.Mistynite:BAAALgADCgkJEwAAAA==.',
Mo='Mochimochi:BAAALgAECgYJDQAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgQJBAABLgAECgkJQgAUALQPAA==.Moonshae:BAABLgAECn8lAAIBAAkJjhKIKQDXAQABAAkJjhKIKQDXAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwAMABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwAMABoYAA==.Mouse:BAABLgAECn8VAAInAAcJqx8wBgDwAQAnAAcJqx8wBgDwAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgAECgMJAQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwARAKsLAA==.Nails:BAABLgAECn8aAAIHAAkJhxN8FgDmAQAHAAkJhxN8FgDmAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgcJDwABLgAECgkJGgAmAIURAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nightray:BAAALgADCgUJBQAAAA==.Nikan:BAAALgADCgYJDAAAAA==.Niralth:BAAALgAECgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAAQAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgALANAbAA==.Noriisa:BAABLgAECn8xAAIXAAkJARvaKgAuAgAXAAkJARvaKgAuAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIJAAgJghuoHwBOAgAJAAgJghuoHwBOAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgMJAwAAAA==.',
Ny='Nyvak:BAABLgAECn8WAAMkAAYJqxAdJgD9AAAkAAYJqxAdJgD9AAAdAAUJ9wjcZwC9AAAAAA==.',
Od='Odinhand:BAABLgAECn8uAAIMAAkJWwkjMQBUAQAMAAkJWwkjMQBUAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Ol='Oliissa:BAAALgAECgMJAgAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQAQAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAIOAAkJmCLoDgABAwAOAAkJmCLoDgABAwABLgAFFAQJCAACAB0PAA==.Ozwäldo:BAABLgAFFH8IAAICAAQJHQ8ICgAbAQACAAQJHQ8ICgAbAQAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8YAAIOAAUJbhWVDQCvAQAOAAUJbhWVDQCvAQAuAAQKfz8AAg4ACQmpIswQAPQCAA4ACQmpIswQAPQCAAAA.Pandóra:BAABLgAECn8YAAMUAAYJYQO1XQCcAAAUAAYJYQO1XQCcAAATAAQJXAKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMfAAMJ5SRNBQAtAQAfAAMJ5SRNBQAtAQAHAAIJcB7+EADBAAAuAAQKfzoAAx8ACQmjJkcAAHcDAB8ACQl1JkcAAHcDAAcACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.',
Ph='Pherrall:BAAALgADCgYJBgABLgAFFAgJGQARAM4aAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAQAAAAAA==.Pinkeepink:BAABLgAECn8oAAIFAAkJDQoVEQAwAQAFAAkJDQoVEQAwAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Polox:BAAALgAECgEJAQAAAA==.Potangwang:BAABLgAECn8UAAIXAAcJsw2XdgBOAQAXAAcJsw2XdgBOAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Pu='Punchysev:BAACLgAFFH8GAAMBAAMJ0RbaSgBtAAABAAIJJBLaSgBtAAAPAAIJ1AJnTQBnAAAuAAQKfxcABA8ACQluD0klAIEBAA8ACQlHDEklAIEBAAEABQmTFqZHAEUBACYABQlwE2EyADcBAAAA.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8oAAISAAkJDyIfCACTAgASAAkJDyIfCACTAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMLAAcJ8Q2lpwApAQALAAcJ8Q2lpwApAQAVAAQJ/waCOgBvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMCAAkJ3A16DwC1AQACAAkJ3A16DwC1AQAKAAcJRgMVZwCtAAAAAA==.Raynë:BAAALgAECgYJCgABLgAECgkJIwAXAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Rebecca:BAAALgADCgkJCQAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgASAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8eAAIoAAcJSR8MAQD2AQAoAAcJSR8MAQD2AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCAAYABQmjEtOdAOIAAAAA.Rineli:BAABLgAECn83AAIOAAkJDRFqTgDtAQAOAAkJDRFqTgDtAQAAAA==.Ringadingg:BAABLgAECn80AAIRAAkJhSRqBwA5AwARAAkJhSRqBwA5AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAARAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAHAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIjAAgJ7RrJFQAiAgAjAAgJ7RrJFQAiAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8PAAILAAYJIhoyHwCCAQALAAYJIhoyHwCCAQAuAAQKfzUAAgsACQncJXYCAHADAAsACQncJXYCAHADAAAA.',
Sc='Scony:BAABLgAECn8VAAMHAAkJhxI6FwDeAQAHAAgJahQ6FwDeAQAfAAUJmQm+FgDBAAAAAA==.Screws:BAAALgADCgYJBgAAAA==.Scribs:BAABLgAECn8bAAIXAAgJmANpmwAFAQAXAAgJmANpmwAFAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMOAAgJtB2tcgCRAQAOAAcJbxytcgCRAQAiAAQJTh4SDAARAQABLgAFFAMJBgASAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJVwARALwaAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAFFAMJBgABANEWAA==.Severautism:BAAALgAECgMJAwABLgAFFAMJBgABANEWAA==.Severànce:BAAALgADCgQJBAABLgAFFAMJBgABANEWAA==.Sevotion:BAABLgAECn8xAAQLAAkJUx0oNgBKAgALAAgJKB0oNgBKAgAlAAkJSxVRHAAfAgAVAAcJog8qLQClAAABLgAFFAMJBgABANEWAA==.',
Sh='Shablammy:BAABLgAECn81AAMJAAkJMiVpAQC8AwAJAAkJMiVpAQC8AwAKAAEJ6BAuogAyAAAAAA==.Shadownome:BAAALgAECgQJDwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJMwAVACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgMJBAAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgAECgUJBQAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgEJAQAAAA==.Silvanosh:BAABLgAECn8aAAIXAAkJWQwEWQCVAQAXAAkJWQwEWQCVAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQZAAkJeBqbEAApAgAZAAkJZRmbEAApAgAIAAcJfRd6KADmAQAXAAQJfREGzgCnAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJBQAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJDAAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgcJCgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAgJMgAOAHYgAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxzoCwDVAgABAAkJaxzoCwDVAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgMJAgAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAYJDwANAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8bAAMUAAkJYRb1FgARAgAUAAkJYRb1FgARAgAjAAEJvQZ4cAAqAAABLgAFFAMJBgABANEWAA==.Stonemother:BAAALgAECgYJDQAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAQAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwALAMgcAA==.',
Sw='Swampmonster:BAAALgAECgYJEQAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIGAAQJchnaRQAQAQAGAAQJchnaRQAQAQAuAAQKfywAAwYACAkkJAMRAPYCAAYACAnOIwMRAPYCAA0ABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgcJEwAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAFFAIJBQAWANcLAA==.Taurastrage:BAABLgAECn8WAAIkAAcJdhuIEwDTAQAkAAcJdhuIEwDTAQABLgAFFAIJBQAWANcLAA==.Taurdk:BAACLgAFFH8FAAIWAAIJ1wsHIAB9AAAWAAIJ1wsHIAB9AAAuAAQKfxwAAxYACQnjGYkEAH8CABYACQnjGYkEAH8CABEAAglCBp5GAVQAAAAA.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8LAAIMAAMJix1kIwAFAQAMAAMJix1kIwAFAQAuAAQKfx8AAgwACAkmIpsMAIsCAAwACAkmIpsMAIsCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAkACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAkACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAkACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJVwARALwaAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgAKAKgeAA==.Teetau:BAABLgAECn8+AAIbAAkJfAfRMADhAAAbAAkJfAfRMADhAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAhAEEcAA==.Thadregosa:BAABLgAECn9FAAMhAAkJQRxMAgCdAgAhAAkJQRxMAgCdAgAaAAcJwAp+YgCuAAAAAA==.Thander:BAAALgADCgMJAwABLgAECgQJCAAQAAAAAA==.Thannicus:BAAALgAECgYJDgAAAA==.Thedarkskull:BAAALgAECgEJAgAAAA==.Thordar:BAAALgADCggJDgAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIYAAkJchx4DwDVAgAYAAkJchx4DwDVAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAYAHIcAA==.Tiffy:BAAALgADCgkJTQAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tintreach:BAAALgAECgYJCwAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAAALgAECgYJEwAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJBwAAAA==.',
To='Tokalu:BAABLgAECn8aAAImAAkJhRFwHgC2AQAmAAkJhRFwHgC2AQAAAA==.Tonjudsonson:BAACLgAFFH8eAAIbAAYJoyF7AwDgAQAbAAYJoyF7AwDgAQAuAAQKfywAAhsACQmCJfUAAGQDABsACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAIKAAkJDwypNgBbAQAKAAkJDwypNgBbAQAAAA==.Toxix:BAABLgAECn8eAAICAAkJJSPZAQAPAwACAAkJJSPZAQAPAwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8yAAIFAAkJWQm9EAA0AQAFAAkJWQm9EAA0AQAAAA==.Twobricks:BAABLgAECn8uAAIYAAkJERNAJgAaAgAYAAkJERNAJgAaAgAAAA==.',
Ty='Tyrssana:BAAALgAECgYJEgABLgAFFAUJDgAhAEMMAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIjAAYJIxpaIgCrAQAjAAYJIxpaIgCrAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8uAAIVAAkJyRl4CABMAgAVAAkJyRl4CABMAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAABLgAECn8YAAMVAAkJph26CQAvAgAVAAkJgBu6CQAvAgALAAIJSCC4+gC6AAAAAA==.Urlacher:BAAALgAECgMJBQAAAA==.',
Va='Vaccaria:BAAALgAECgMJAwABLgAECgMJAwAQAAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAJANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgYJEgAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECgkJGAADAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAImAAUJ1SQ9CACPAQAmAAUJ1SQ9CACPAQAuAAQKfxoAAiYACAk9I0MEAEgDACYACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBwAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIZAAcJBxlPEgCeAQAZAAcJBxlPEgCeAQAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgATADMYAA==.Visea:BAAALgAECgQJCwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCAAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAgAAAA==.Watevr:BAEALgAECgYJBgABLgAECggJRQAfAKcZAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwAQAAAAAA==.Wesleypriest:BAABLgAECn8fAAMTAAkJBwk/LQBtAQATAAkJ5gg/LQBtAQAjAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgYJDgAAAA==.',
Wr='Wrandanden:BAAALgADCgUJDAAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8wAAIVAAkJwRaDCwALAgAVAAkJwRaDCwALAgAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgAOAEkXAA==.',
Xe='Xear:BAAALgADCgcJDwABLgADCgkJTQAQAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAfAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAIOAAcJSReajQC3AQAOAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMJAAgJQx2/GgBxAgAJAAgJQx2/GgBxAgAKAAEJWAjekQAlAAABLgAECgkJJQARACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAITAAQJlw9HJgAPAQATAAQJlw9HJgAPAQABLgAFFAcJGgAJANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAdAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCAAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCAAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAJANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAAALgAECgQJCAAAAA==.Zeratule:BAAALgAECgIJAwAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn9MAAILAAkJGx67FwCyAgALAAkJGx67FwCyAgAAAA==.',
Zi='Zijo:BAAALgAECgYJEAAAAA==.Zinnkura:BAAALgAECgYJEwAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8nAAIDAAkJUA3STwCrAQADAAkJUA3STwCrAQAAAA==.',
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
