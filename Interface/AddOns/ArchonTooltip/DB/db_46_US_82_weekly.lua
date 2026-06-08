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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Mage-Frost','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','Paladin-Protection','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Holy','DemonHunter-Devourer','Warrior-Protection','Hunter-Survival','Paladin-Holy','Monk-Windwalker','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abominasven:BAAALgAECgEJAQAAAA==.',
Ad='Adhira:BAAALgAECgQJBwAAAA==.Adunal:BAAALgAECggJDQAAAA==.',
Ae='Aedrias:BAABLgAECn8cAAIBAAcJSA1eSAAwAQABAAcJSA1eSAAwAQAAAA==.Aegennai:BAABLgAECn8nAAICAAgJVgcaGAA3AQACAAgJVgcaGAA3AQAAAA==.Aegon:BAECLgAFFH8cAAMDAAcJqxwiJgCPAQADAAYJyxsiJgCPAQAEAAEJDSGaEwBlAAAuAAQKfyMAAwMACQn8H+s4ACgCAAMABgkfIes4ACgCAAUAAwmUHL4pABsBAAAA.Aegondh:BAEALgAECgMJAwABLgAFFAcJHAADAKscAA==.Aeli:BAAALgAECgMJAwABLgAECgcJHAABAEgNAA==.Aethelios:BAAALgAECgIJAgAAAA==.Aevaela:BAACLgAFFH8GAAIGAAIJPBxoKwCrAAAGAAIJPBxoKwCrAAAuAAQKfzYAAgYACQlSHnoNAEQCAAYACQlSHnoNAEQCAAAA.',
Ag='Agilaz:BAABLgAECn8yAAIHAAkJeRpgBQBCAgAHAAkJeRpgBQBCAgAAAA==.Aguas:BAAALgAECgMJCgAAAA==.',
Ah='Ahnzure:BAAALgAFFAEJAQABLgAFFAcJGgAIANEeAA==.',
Ak='Akey:BAAALgAECgYJEgAAAQ==.Akhae:BAACLgAFFH8IAAIIAAIJ0Bj6UwCWAAAIAAIJ0Bj6UwCWAAAuAAQKfyUAAwgACQkVFlguAPABAAgACQkVFlguAPABAAkACQneDcUvAHIBAAAA.Akrihail:BAAALgAECgYJCAAAAA==.',
Al='Albinism:BAABLgAECn8pAAICAAcJLhWxEwBvAQACAAcJLhWxEwBvAQAAAA==.Alcadeias:BAABLgAECn8pAAIKAAcJFxaPhQBZAQAKAAcJFxaPhQBZAQAAAA==.Alessag:BAAALgAECgQJBAAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8nAAILAAkJGhjHFwADAgALAAkJGhjHFwADAgAAAA==.',
Am='Amehnet:BAAALgAECgYJCAAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8YAAIKAAkJSAttrgAmAQAKAAkJSAttrgAmAQAAAA==.Andrömëdä:BAABLgAECn8UAAIMAAcJRBEjIwBLAQAMAAcJRBEjIwBLAQAAAA==.Anfisa:BAAALgADCgYJBgAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Anguished:BAAALgADCgIJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAABLgAECn8aAAINAAYJUgkoyAD4AAANAAYJUgkoyAD4AAAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJHAABAEgNAA==.',
Aq='Aquindra:BAAALgAECgMJBAAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgAECgQJBAAAAA==.',
As='Ashvyth:BAABLgAECn82AAIOAAkJuCENBAACAwAOAAkJuCENBAACAwAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.Astérion:BAAALgAECgkJCQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAECgYJDAAPAAAAAQ==.',
Ba='Baconpancake:BAAALgAECgcJEwAAAA==.Baeyik:BAAALgAFFAIJAwAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balinor:BAAALgAECgcJEQAAAA==.Ballz:BAAALgAECgcJBwAAAA==.Balomdruid:BAAALgAECgYJDQAAAA==.Barendor:BAAALgADCgUJAQAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAABLgAECn8lAAMQAAkJIxqlIgB0AgAQAAkJIxqlIgB0AgARAAgJOAX2MADQAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgAECgYJBwAAAA==.Beastlypläyä:BAAALgAECgYJCwAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAFFAQJBAAPAAAAAA==.Bessarion:BAAALgADCgYJBgAAAA==.',
Bi='Bigblingaxe:BAAALgAECgYJCgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgAECgEJAQAAAA==.Blindhealz:BAACLgAFFH8HAAISAAMJLwrhMACzAAASAAMJLwrhMACzAAAuAAQKfzAAAxIACAnMF1cWABcCABIACAnMF1cWABcCABMABQl4C5xGAOsAAAAA.Blinkzy:BAAALgAECgIJAgAAAA==.Bloodsharp:BAAALgAECgUJBwAAAA==.Blusoleil:BAABLgAECn8UAAIUAAcJkw1OIAAFAQAUAAcJkw1OIAAFAQAAAA==.',
Bo='Bonerblast:BAAALgAECgMJBAAAAA==.Boston:BAABLgAECn81AAQQAAkJhySDEADhAgAQAAkJhySDEADhAgARAAcJzA70JwALAQAVAAMJhBuBIwCfAAAAAA==.',
Br='Braesong:BAAALgADCgUJBwAAAA==.Brewtholomew:BAABLgAECn8rAAIWAAkJ9RHEQADUAQAWAAkJ9RHEQADUAQAAAA==.Briggsey:BAABLgAECn8lAAIDAAgJfQ0SYwB0AQADAAgJfQ0SYwB0AQAAAA==.Briznot:BAABLgAECn8YAAMDAAgJbBmFPgDcAQADAAcJxBiFPgDcAQAFAAIJbyBvLABfAAAAAA==.Brounies:BAABLgAECn8XAAIXAAcJmAigaADxAAAXAAcJmAigaADxAAAAAA==.Bryce:BAABLgAECn8ZAAIKAAgJRBSvZgCXAQAKAAgJRBSvZgCXAQAAAA==.Brèanna:BAAALgAECgMJBgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgAECgMJAgAAAA==.Bucciarati:BAAALgADCgYJBgABLgAFFAMJBAAPAAAAAA==.Bunnyfu:BAAALgAECgYJEgABLgAFFAQJBgAYAPEDAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAACLgAFFH8GAAIIAAMJKhK+RgC9AAAIAAMJKhK+RgC9AAAuAAQKfy0AAggACAmMInwKANQCAAgACAmMInwKANQCAAAA.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8hAAIZAAcJcBgNFQCaAQAZAAcJcBgNFQCaAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8lAAIWAAgJ3QQ0kwAMAQAWAAgJ3QQ0kwAMAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgAECgMJAgAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgYJEgAAAA==.Capthunder:BAAALgADCggJFQABLgAECgUJBwAPAAAAAA==.Carnìfex:BAABLgAECn8oAAMaAAYJ4BqpGgB7AQAaAAYJ4BqpGgB7AQAbAAYJJA+DVwBOAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAABLgAECn8XAAQcAAkJRiL/CgD8AQAcAAkJRiL/CgD8AQAZAAQJtBcFJwAKAQAXAAMJdxYKfwCzAAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIdAAgJKAxFDABeAQAdAAgJKAxFDABeAQAAAA==.Cephandrius:BAAALgAECgQJBAAAAA==.Cerà:BAAALgAECgUJCAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheala:BAAALgAECgcJDQABLgAECgkJHgAJAPMbAA==.Cheetah:BAAALgAECgMJCAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAABLgAECn8UAAIbAAgJzAe0QgAyAQAbAAgJzAe0QgAyAQAAAA==.Cloudbreaker:BAAALgAECgQJBgAAAA==.Cloudkeg:BAAALgAECgQJCAAAAA==.Clubfoots:BAAALgAECgEJAQAAAA==.',
Co='Constellate:BAAALgAECgkJEAAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAABLgAECn8XAAIXAAkJBApXSABjAQAXAAkJBApXSABjAQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8eAAMJAAkJ8xt0KQDJAQAJAAcJshx0KQDJAQAIAAMJWwqHlwCQAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn89AAMdAAgJ2RhVCwByAQAGAAgJchJmHQCdAQAdAAYJiRlVCwByAQAAAA==.Damnitsu:BAEBLgAECn8gAAMdAAcJUxJuDABbAQAdAAYJWxVuDABbAQAGAAcJ5wwGKwAxAQABLgAECggJPQAdANkYAA==.Darkcat:BAABLgAECn8rAAIcAAgJlAcWHwD9AAAcAAgJlAcWHwD9AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgMJCAAAAA==.',
De='Deadflexy:BAABLgAECn8aAAIRAAkJWBo7DgAbAgARAAkJWBo7DgAbAgAAAA==.Dear:BAAALgAFFAEJAQAAAA==.Deathberry:BAABLgAECn89AAIDAAkJVyKVBwAWAwADAAkJVyKVBwAWAwAAAA==.Deathdoodles:BAACLgAFFH8HAAIQAAIJqwuh1gCEAAAQAAIJqwuh1gCEAAAuAAQKfyAAAhAACQkkGE81ACECABAACQkkGE81ACECAAAA.Deathtomany:BAAALgADCgYJCQAAAA==.Deathvoker:BAAALgAFFAEJAQAAAA==.Deekan:BAABLgAECn8eAAIKAAkJwQbVkQBDAQAKAAkJwQbVkQBDAQAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBwAAAA==.Demise:BAAALgAECgQJBAABLgAFFAMJBAAPAAAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAABLgAECn8VAAITAAgJ8gg5OQAmAQATAAgJ8gg5OQAmAQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAPAAAAAA==.Devlik:BAAALgAECgQJBAAAAA==.',
Df='Dfresh:BAABLgAECn8rAAIKAAgJ5wddogAoAQAKAAgJ5wddogAoAQAAAA==.',
Di='Dinkalopogis:BAAALgAECgMJAQAAAA==.Dione:BAAALgADCgYJBgAAAA==.Dionne:BAAALgAECgYJBgAAAA==.Dippindots:BAAALgAECgEJAQAAAA==.Ditsie:BAAALgAECgIJBAAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Dm='Dmega:BAAALgAECggJDwAAAA==.',
Do='Dobby:BAAALgAECgYJEAAAAA==.',
Dr='Dragondude:BAABLgAECn83AAMeAAkJEiKDAQB8AwAeAAkJEiKDAQB8AwAfAAEJNA7jIwA1AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAACLgAFFH8FAAIaAAQJgxhHEwAsAQAaAAQJgxhHEwAsAQAuAAQKfzoAAhoACQmpIKQDAOUCABoACQmpIKQDAOUCAAAA.Durgan:BAAALgADCgUJBQAAAA==.',
Dy='Dyelin:BAABLgAECn82AAQDAAkJwyLkBQAsAwADAAkJmSLkBQAsAwAFAAIJyhOASQCSAAAEAAIJVh6MLQBaAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.Earf:BAAALgADCgIJAgAAAA==.',
Ec='Ecgberht:BAAALgADCgEJAQAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMdAAgJkBIkCADWAQAdAAgJkBIkCADWAQAGAAYJPAouOQBMAQAAAA==.',
Eh='Ehlonna:BAAALgAECgIJAgAAAA==.',
El='Elylle:BAAALgAECgQJCQAAAA==.Elyron:BAABLgAECn84AAMNAAkJZyBLDwD7AgANAAkJZyBLDwD7AgAgAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.Emèra:BAAALgAECgcJBwABLgAECgkJIQANAF8YAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgMJCAAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Es='Espii:BAAALgAECgkJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAPAAAAAA==.Etheri:BAAALgAECggJDAAAAA==.',
Ev='Evilorc:BAAALgAECgEJAQAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8rAAMXAAkJuyH4CgAFAwAXAAgJnCH4CgAFAwALAAQJDw6IWwCXAAAAAA==.Fakesaint:BAACLgAFFH8MAAIIAAUJFRPtHwBXAQAIAAUJFRPtHwBXAQAuAAQKfzUAAggACQmfIZQHAC0DAAgACQmfIZQHAC0DAAAA.Fangstorm:BAABLgAECn8yAAIcAAkJdxOnDADdAQAcAAkJdxOnDADdAQAAAA==.Farorê:BAABLgAECn8YAAIhAAYJ6BdOKAB3AQAhAAYJ6BdOKAB3AQAAAA==.',
Fe='Felbane:BAABLgAECn8sAAIiAAkJ2hdJKwAQAgAiAAkJ2hdJKwAQAgAAAA==.Feldruid:BAAALgAECgEJAgAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAACLgAFFH8IAAIjAAMJrQU+IQB6AAAjAAMJrQU+IQB6AAAuAAQKf0EAAyMACAnlFjEQANoBACMACAnlFjEQANoBABsAAgm+A0CNAEcAAAAA.',
Fo='Foreverem:BAAALgAECgIJAwAAAA==.',
Fr='Fritopaws:BAABLgAECn8/AAMHAAkJ+h3bAgCrAgAHAAkJih3bAgCrAgAkAAUJ9x7FEAC4AQAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgMJAwAAAA==.Furpunch:BAAALgAECgEJAQAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJEAAAAA==.Gallindria:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgkJDgAAAA==.Gaska:BAAALgAECggJCAABLgAECgkJHwABAGscAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgcJDQAAAA==.Ginzi:BAABLgAECn85AAMVAAgJ8gvmEABVAQAVAAgJ8gvmEABVAQAQAAgJswf9jgA/AQAAAA==.Githiel:BAAALgAECgMJAwAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgcJDwABLgAECgkJFgADADcaAA==.',
Gr='Gravehorror:BAAALgADCgUJBQAAAA==.Graxus:BAAALgAECggJDAAAAA==.Greatchez:BAAALgAECgcJEgAAAA==.Greth:BAAALgAECgMJAgAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAACLgAFFH8GAAIYAAQJ8QMjQgCwAAAYAAQJ8QMjQgCwAAAuAAQKfygAAhgABwl9FxksAIQBABgABwl9FxksAIQBAAAA.Gummypenguin:BAABLgAECn8VAAMWAAgJGhqcTACDAQAWAAcJiBmcTACDAQAHAAYJTQzRVQDyAAABLgAFFAUJHQAWAMMgAA==.',
Gw='Gwenldoyn:BAAALgAECgYJBgAAAA==.',
Ha='Hadhox:BAABLgAECn8fAAIbAAkJHw7nJgC7AQAbAAkJHw7nJgC7AQABLgAECgkJIwAWAMYUAA==.Hakano:BAABLgAECn8lAAIOAAYJrgO+VQCoAAAOAAYJrgO+VQCoAAAAAA==.Harbiin:BAAALgAECgMJBQAAAA==.Hathdox:BAABLgAECn8jAAIWAAkJxhQzLwAUAgAWAAkJxhQzLwAUAgAAAA==.Hawkulees:BAAALgAECgIJAQAAAA==.Hazelnoot:BAABLgAECn8mAAMKAAkJ0BtDKgBOAgAKAAkJ0BtDKgBOAgAlAAYJugVPUwDfAAAAAA==.Haûnt:BAAALgADCgUJCQAAAA==.',
He='Hexcist:BAABLgAECn80AAIMAAkJAhOSEwDpAQAMAAkJAhOSEwDpAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn8xAAIeAAkJJAkAFQBzAQAeAAkJJAkAFQBzAQAAAA==.',
Ho='Hollyanne:BAABLgAECn8sAAIFAAkJjQtWDQBYAQAFAAkJjQtWDQBYAQAAAA==.Holyfawn:BAAALgADCgEJAQABLgAFFAMJBAAPAAAAAA==.Holyjim:BAAALgAECgEJAQAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgYJCwAPAAAAAA==.Hornsnap:BAABLgAECn8jAAMIAAcJzB1DIQA6AgAIAAcJzB1DIQA6AgAJAAEJ+QwnhQA3AAAAAA==.',
Hu='Huanying:BAAALgAECgEJAQABLgAECgMJAwAPAAAAAA==.Hunalli:BAAALgAECgUJBQABLgAFFAQJBgAYAPEDAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJFAAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQHAAMJfBxZGADQAAAHAAIJ0CNZGADQAAAkAAIJRxdKJACaAAAWAAEJqiYsiABhAAAuAAQKfz0ABAcACQnAJaQDAGoDAAcACAnDJaQDAGoDACQACAldI0YHAKYCABYAAwmbJEmTALIAAAAA.',
Ic='Iconius:BAAALgAECgMJCAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAACLgAFFH8FAAIIAAMJHRE/TACrAAAIAAMJHRE/TACrAAAuAAQKfzAAAwgABwl+G7crAP0BAAgABwl+G7crAP0BAAkABgmLGhktAIEBAAAA.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJBQAPAAAAAA==.Ilovekayla:BAAALgAECgEJBQAAAA==.',
In='Innexdruid:BAAALgAECgYJCgABLgAECgkJJwAQABsfAA==.Insaint:BAACLgAFFH8QAAIKAAQJqhY5OQApAQAKAAQJqhY5OQApAQAuAAQKfzUAAgoACQkJGzwrAEoCAAoACQkJGzwrAEoCAAAA.',
Is='Isabellë:BAABLgAECn8tAAMTAAgJSwqrNAA8AQATAAgJSwqrNAA8AQAhAAIJnAMfZABCAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJBQAAAA==.Jaker:BAAALgAECgIJAwAAAA==.Jalu:BAABLgAECn8YAAIDAAcJAhHGbQBbAQADAAcJAhHGbQBbAQAAAA==.Jasön:BAAALgAECgEJAQAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJSwAbAKUkAA==.',
Je='Jessamine:BAABLgAECn8hAAINAAkJXxixPAAhAgANAAkJXxixPAAhAgAAAA==.Jessicafelba:BAABLgAECn8WAAMDAAkJNxrWKwAkAgADAAgJNxrWKwAkAgAFAAIJVAvkcAA1AAAAAA==.Jetta:BAABLgAECn8vAAIcAAcJgBaIEACdAQAcAAcJgBaIEACdAQAAAA==.Jezzak:BAABLgAECn8mAAIWAAgJmhoYPQDhAQAWAAgJmhoYPQDhAQABLgAECgkJMQAWAAEbAA==.',
Jo='John:BAAALgAFFAIJAwAAAA==.Jorien:BAABLgAECn9RAAIWAAkJZxuoHQBpAgAWAAkJZxuoHQBpAgAAAA==.',
Jp='Jp:BAAALgAECgUJCAABLgAECgYJCAAPAAAAAA==.Jps:BAAALgAECgYJCAAAAA==.',
Ju='Judith:BAAALgADCgYJBgABLgAECggJGAADAGwZAA==.',
Ka='Kabbydots:BAAALgAECgcJBwAAAA==.Kaboonsky:BAABLgAECn8lAAMhAAkJWxhHGAAaAgAhAAkJWxhHGAAaAgATAAIJmxFSZgBvAAAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJDwAAAA==.Kaivyx:BAAALgAECgUJBQAAAA==.Kamikori:BAABLgAECn8qAAMbAAkJfB1dDwB5AgAbAAkJIxxdDwB5AgAjAAYJvBiYGQBhAQAAAA==.Kardelbrew:BAAALgAECgQJBAABLgAECgcJEgAPAAAAAA==.Kardels:BAAALgAECgcJEgAAAA==.Karnn:BAACLgAFFH8XAAMmAAUJdh4uDQBMAQAmAAUJdh4uDQBMAQAOAAEJHQFRKgArAAAuAAQKfycAAyYACAl3JJQKAM8CACYACAl3JJQKAM8CAAEABglfEAROABoBAAAA.Katalight:BAAALgAECgQJAQABLgAECgcJCgAPAAAAAA==.Katrini:BAAALgAECgcJCgAAAA==.',
Ke='Keho:BAAALgAECgUJDAABLgAFFAQJEQANALAdAA==.',
Ki='Kiascendance:BAAALgAECgkJEgAAAA==.Kiplet:BAABLgAECn8aAAIhAAkJpBZyIgCiAQAhAAkJpBZyIgCiAQAAAA==.',
Kn='Knockback:BAAALgAECgMJBQAAAA==.',
Ko='Korbix:BAAALgAECgYJBAAAAA==.Korxon:BAABLgAECn8fAAMSAAgJkhfbHwDAAQASAAgJkhfbHwDAAQAhAAQJDg4OWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAPAAAAAA==.Krazz:BAAALgADCgcJDwABLgAECgkJGgARAFgaAA==.',
Ks='Ksyusha:BAAALgAECgYJEgAAAA==.',
['Kâ']='Kâlsáñg:BAAALgAECgIJAwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJKgANAGsVAA==.',
La='Lahabrea:BAABLgAECn8fAAMFAAgJBA3wKwAPAQADAAgJwQrOggAuAQAFAAYJ2w3wKwAPAQAAAA==.Lanfeer:BAAALgAECgcJEAAAAA==.Lanuadra:BAAALgAECgcJDQABLgAECgkJGAAYAB4cAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBwAAAA==.',
Le='Leeara:BAABLgAECn8cAAIiAAkJBBhjOgDRAQAiAAkJBBhjOgDRAQAAAA==.Legitpoopoo:BAAALgAECgUJDAABLgAFFAMJBgARAFkXAA==.Lem:BAAALgAECgYJDQAAAA==.Lethalbimbo:BAAALgAECgUJCgAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilwinter:BAAALgADCgIJAgAAAA==.Lilysham:BAACLgAFFH8aAAIIAAcJ0R79AgCLAgAIAAcJ0R79AgCLAgAuAAQKfyEAAwgACAmAI0sQAJUCAAgABwkOI0sQAJUCAAkAAQnnESyFADcAAAAA.Linddrel:BAAALgAECgcJDwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Ly='Lyv:BAAALgAECgEJAQAAAA==.',
['Lø']='Løllîe:BAAALgAECgYJEgAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgYJEgAPAAAAAA==.',
Ma='Madsharona:BAAALgAECgkJCgAAAA==.Magatai:BAABLgAECn8aAAINAAgJ5Qa/lgBGAQANAAgJ5Qa/lgBGAQAAAA==.Mageless:BAAALgAECgEJAQAAAA==.Magicjim:BAAALgAECgMJAwAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJCgABLgADCgkJFAAPAAAAAA==.Manaster:BAAALgAECgcJCwAAAA==.Mandhos:BAAALgAECgMJAwAAAA==.Markos:BAAALgADCgYJBgABLgADCgcJDwAPAAAAAA==.Marlie:BAAALgAECgkJDAAAAA==.Martlok:BAABLgAECn8iAAMQAAcJfBnacQB4AQAQAAcJ5xjacQB4AQAVAAIJhxryLgBPAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Mathas:BAAALgAECgQJBgAAAA==.Maynis:BAAALgADCgcJCwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgQJDAAAAA==.',
Me='Meenu:BAAALgADCgIJAgAAAA==.Methallica:BAAALgAECgUJBgAAAA==.',
Mi='Micflinigan:BAABLgAECn8rAAMbAAkJLxYkIwDUAQAbAAgJzRYkIwDUAQAjAAEJ3hFwTgA0AAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgkJGgAhAKQWAA==.Misahaviran:BAAALgAECgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Misla:BAAALgADCgcJCQAAAA==.Mistynite:BAAALgADCgkJDwAAAA==.',
Mo='Mochimochi:BAAALgAECgYJDQAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Mokuer:BAAALgAECgQJBAABLgAECgkJQgATALQPAA==.Moonshae:BAABLgAECn8lAAIBAAkJjhJBJwDWAQABAAkJjhJBJwDWAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJJwALABoYAA==.Mornings:BAAALgAECgYJDQABLgAECgkJJwALABoYAA==.Mouse:BAABLgAECn8VAAInAAcJqx8CBgDvAQAnAAcJqx8CBgDvAQAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgAECgMJAQAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBwAQAKsLAA==.Nails:BAABLgAECn8aAAIGAAkJhxN+FQDmAQAGAAkJhxN+FQDmAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgcJDwABLgAECgkJGgAmAIURAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Niralth:BAAALgAECgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgAECggJCAAAAA==.Noknik:BAAALgADCgcJDAABLgADCgkJFAAPAAAAAA==.Nootloops:BAAALgAECgYJBwABLgAECgkJJgAKANAbAA==.Noriisa:BAABLgAECn8xAAIWAAkJARtYKAAyAgAWAAkJARtYKAAyAgAAAA==.Notamathguy:BAAALgAFFAIJAgAAAA==.Noudders:BAABLgAECn8cAAIIAAgJghtEHgBPAgAIAAgJghtEHgBPAgAAAA==.',
Nu='Nutsandberri:BAAALgAECgEJAQAAAA==.',
Ny='Nyvak:BAAALgAECgYJEQAAAA==.',
Od='Odinhand:BAABLgAECn8uAAILAAkJWwkrLwBVAQALAAkJWwkrLwBVAQAAAA==.',
Oe='Oenei:BAAALgAECgEJAQAAAA==.',
Ol='Oliissa:BAAALgAECgMJAgAAAA==.',
On='Onepunchman:BAAALgAECgEJAgABLgAECgMJBQAPAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8wAAINAAkJmCLfDQAGAwANAAkJmCLfDQAGAwABLgAFFAQJBAAPAAAAAA==.Ozwäldo:BAAALgAFFAQJBAAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFwAAAA==.Panduh:BAACLgAFFH8YAAINAAUJbhWVDQCvAQANAAUJbhWVDQCvAQAuAAQKfz8AAg0ACQmpIogPAPoCAA0ACQmpIogPAPoCAAAA.Pandóra:BAABLgAECn8YAAMTAAYJYQOFWQChAAATAAYJYQOFWQChAAASAAQJXAKQSgBsAAAAAA==.Pariousa:BAACLgAFFH8QAAMdAAMJ5STyBAAyAQAdAAMJ5STyBAAyAQAGAAIJcB7+EADBAAAuAAQKfzoAAx0ACQmjJkIAAHkDAB0ACQl1JkIAAHkDAAYACAmVJUgDAGsDAAAA.Patty:BAAALgADCgkJDwAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAPAAAAAA==.Pinkeepink:BAABLgAECn8iAAIFAAkJTgiWEQAgAQAFAAkJTgiWEQAgAQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Po='Potangwang:BAABLgAECn8UAAIWAAcJsw3NbwBVAQAWAAcJsw3NbwBVAQAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.Prindi:BAAALgADCgEJAQAAAA==.',
Pu='Punchysev:BAABLgAECn8UAAQOAAkJrg4IJACDAQAOAAkJRwwIJACDAQABAAUJkxZeQwBEAQAmAAQJexG5QwDiAAABLgAECgkJGwATAGEWAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Rakith:BAAALgAECgMJAwAAAA==.Ralganor:BAABLgAECn8oAAIRAAkJDyKFBwCZAgARAAkJDyKFBwCZAgAAAA==.Ralzin:BAAALgADCgcJBQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAABLgAECn8YAAMKAAcJ8Q0ToAArAQAKAAcJ8Q0ToAArAQAUAAQJ/wZfOABvAAAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAABLgAECn8sAAMCAAkJ3A1tDgC8AQACAAkJ3A1tDgC8AQAJAAcJRgO7YgCtAAAAAA==.Raynë:BAAALgAECgQJBAABLgAECgkJIwAWAMYUAA==.',
Re='Realistic:BAAALgAECgIJAwAAAA==.Relequen:BAAALgAECgUJBgAAAA==.Ren:BAAALgAECgUJBQAAAA==.Retacus:BAAALgAECgMJAgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgkJGgARAFgaAA==.',
Ri='Rickan:BAAALgAECgEJAQAAAA==.Rina:BAACLgAFFH8eAAIoAAcJSR/RAAD8AQAoAAcJSR/RAAD8AQAuAAQKfywAAygACAlaIxUCAOoCACgACAlaIxUCAOoCACIABQmjErmYAOIAAAAA.Rineli:BAABLgAECn81AAINAAkJDRG0SQD3AQANAAkJDRG0SQD3AQAAAA==.Ringadingg:BAABLgAECn80AAIQAAkJhSSiBgA9AwAQAAkJhSSiBgA9AwAAAA==.Riniching:BAAALgAECgEJAQABLgAECgkJNAAQAIUkAA==.Rivets:BAAALgADCgMJAwABLgAECgkJGgAGAIcTAA==.',
Ro='Roastduck:BAABLgAECn8bAAIhAAgJ7RqaFAAlAgAhAAgJ7RqaFAAlAgAAAA==.Rosequartz:BAAALgAECgUJCgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgcJDwAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sadbunny:BAAALgAECgEJBAAAAA==.Saladin:BAAALgAECgQJBAAAAA==.Sankatlantis:BAAALgAECgUJBQAAAA==.Sarazah:BAACLgAFFH8PAAIKAAYJIho7GgCIAQAKAAYJIho7GgCIAQAuAAQKfzUAAgoACQncJRoCAHIDAAoACQncJRoCAHIDAAAA.',
Sc='Scony:BAABLgAECn8VAAMGAAkJhxIPFgDfAQAGAAgJahQPFgDfAQAdAAUJmQnhFQDDAAAAAA==.Screws:BAAALgADCgYJBgAAAA==.Scribs:BAABLgAECn8bAAIWAAgJmANylAAJAQAWAAgJmANylAAJAQAAAA==.',
Sd='Sdiybt:BAABLgAECn8cAAMNAAgJtB3UbACbAQANAAcJbxzUbACbAQAgAAQJTh4SDAARAQABLgAFFAMJBgARAFkXAA==.',
Se='Seegon:BAAALgAECgEJAgAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgIJAwABLgAECgkJUQAQAPUZAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgMJBAABLgAECgkJGwATAGEWAA==.Severautism:BAAALgAECgMJAwABLgAECgkJGwATAGEWAA==.Severànce:BAAALgADCgQJBAABLgAECgkJGwATAGEWAA==.Sevotion:BAABLgAECn8xAAQKAAkJUx0oNgBKAgAKAAgJKB0oNgBKAgAlAAkJSxUiGwAgAgAUAAcJog8qLQClAAABLgAECgkJGwATAGEWAA==.',
Sh='Shablammy:BAABLgAECn8yAAMIAAkJ9CRuAQC2AwAIAAkJ9CRuAQC2AwAJAAEJ6BCSmgAyAAAAAA==.Shadownome:BAAALgAECgMJCwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgAECgkJCQAAAA==.Shammygand:BAAALgADCgIJAgABLgAECgkJMwAUACIdAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgAECgMJBAAAAA==.Shavalyoth:BAAALgAECgEJAQAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silris:BAAALgAECgEJAQAAAA==.Silvanosh:BAABLgAECn8aAAIWAAkJWQycUwCbAQAWAAkJWQycUwCbAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn80AAQkAAkJeBqTDwAxAgAkAAkJZRmTDwAxAgAHAAcJfRd6KADmAQAWAAQJfRHjxQCpAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgAECgQJBQAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepybrown:BAAALgAECgEJAQAAAA==.Sleepydwarf:BAAALgAECgYJDAAAAA==.Sloppiestjoe:BAAALgADCgQJBAAAAA==.Sludgekicker:BAAALgADCgQJBgAAAA==.Slusch:BAAALgAFFAIJAwABLgAFFAcJLAANAEggAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgAECgEJAQAAAA==.Sprynt:BAABLgAECn8fAAIBAAkJaxw3CwDUAgABAAkJaxw3CwDUAgAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgAECgMJAgAAAA==.Steakadin:BAAALgAECgYJBgAAAA==.Stendo:BAAALgAECgQJCQABLgAFFAYJDwAMAK8fAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAABLgAECn8bAAMTAAkJYRbpFQAUAgATAAkJYRbpFQAUAgAhAAEJvQbybAAqAAAAAA==.Stonemother:BAAALgAECgYJDQAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAPAAAAAA==.Stubly:BAAALgAECgEJAQAAAA==.',
Su='Sunae:BAAALgAECgUJAgAAAA==.Sunfyrie:BAAALgAECgcJDAAAAA==.Sunn:BAAALgADCgYJBgABLgAECgkJGwAKAMgcAA==.',
Sw='Swampmonster:BAAALgAECgYJEAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8JAAIiAAQJchltPwAYAQAiAAQJchltPwAYAQAuAAQKfywAAyIACAkkJAMRAPYCACIACAnOIwMRAPYCAAwABAlLJFE/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Taldieth:BAAALgAECgcJEwAAAA==.Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAECgkJHAAVAOMZAA==.Taurastrage:BAABLgAECn8WAAIjAAcJdhuIEwDTAQAjAAcJdhuIEwDTAQABLgAECgkJHAAVAOMZAA==.Taurdk:BAABLgAECn8cAAMVAAkJ4xkVBACDAgAVAAkJ4xkVBACDAgAQAAIJQgaoNwFXAAAAAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAACLgAFFH8IAAILAAMJSRs2JgDpAAALAAMJSRs2JgDpAAAuAAQKfx4AAgsACAlnH/4OAGMCAAsACAlnH/4OAGMCAAAA.Tazarakk:BAAALgADCgMJAwABLgAECgkJFgAjACkhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgkJFgAjACkhAA==.Tazllidan:BAAALgADCgYJBgABLgAECgkJFgAjACkhAA==.',
Te='Teaar:BAAALgADCgYJBgABLgAECgkJUQAQAPUZAA==.Teedos:BAAALgAECggJDgABLgAECgkJOgAJAKgeAA==.Teetau:BAABLgAECn8+AAIZAAkJfAfxLQDiAAAZAAkJfAfxLQDiAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgkJRQAfAEEcAA==.Thadregosa:BAABLgAECn9FAAMfAAkJQRwmAgCgAgAfAAkJQRwmAgCgAgAYAAcJwAoyXwCvAAAAAA==.Thander:BAAALgADCgMJAwABLgAECgQJCAAPAAAAAA==.Thannicus:BAAALgAECgYJDAAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thordar:BAAALgADCggJDgAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.Thunderjugs:BAAALgAECgIJAgAAAA==.',
Ti='Tibbotanical:BAABLgAECn8lAAIXAAkJchzoDgDVAgAXAAkJchzoDgDVAgAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgkJJQAXAHIcAA==.Tiffy:BAAALgADCgkJRgAAAA==.Timoleon:BAAALgAECgEJAQAAAA==.Tintreach:BAAALgAECgYJCwAAAA==.Tirna:BAAALgAECgUJCQAAAA==.Tirnotham:BAAALgAECgYJEwAAAA==.',
Tm='Tmtglizzy:BAAALgAECgEJBQAAAA==.',
To='Tokalu:BAABLgAECn8aAAImAAkJhRHdHAC6AQAmAAkJhRHdHAC6AQAAAA==.Tonjudsonson:BAACLgAFFH8eAAIZAAYJoyHjAgDnAQAZAAYJoyHjAgDnAQAuAAQKfywAAhkACQmCJfUAAGQDABkACQmCJfUAAGQDAAAA.Tonopah:BAABLgAECn8aAAIJAAkJDwxYNABbAQAJAAkJDwxYNABbAQAAAA==.Toxix:BAABLgAECn8eAAICAAkJJSObAQAUAwACAAkJJSObAQAUAwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.Trismigistus:BAAALgAECgEJAQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tuggsondix:BAAALgAECgYJCgAAAA==.',
Tw='Twiki:BAABLgAECn8vAAIFAAgJmQi3EwAGAQAFAAgJmQi3EwAGAQAAAA==.Twobricks:BAABLgAECn8uAAIXAAkJERPoJAAcAgAXAAkJERPoJAAcAgAAAA==.',
Ty='Tyrssana:BAAALgAECgYJEgABLgAFFAQJDQAfAEMMAA==.',
Ug='Uglykitten:BAABLgAECn8dAAIhAAYJIxrYIACuAQAhAAYJIxrYIACuAQAAAA==.',
Uh='Uhmerica:BAABLgAECn8uAAIUAAkJyRnhBwBQAgAUAAkJyRnhBwBQAgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.Undeniably:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAABLgAECn8VAAIUAAgJUBr7DgDHAQAUAAgJUBr7DgDHAQAAAA==.Urlacher:BAAALgAECgEJAQAAAA==.',
Va='Vaccaria:BAAALgAECgMJAwABLgAECgMJAwAPAAAAAA==.Vaedryn:BAAALgADCgYJBgAAAA==.Vaererelor:BAAALgAECgYJDQAAAA==.Valla:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAFFAEJAQABLgAFFAcJGgAIANEeAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgYJEgAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgYJDwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECggJGAADAGwZAA==.Vierth:BAAALgAECgcJCQAAAA==.Vincenzo:BAACLgAFFH8RAAImAAUJ1STzBgCXAQAmAAUJ1STzBgCXAQAuAAQKfxoAAiYACAk9I0MEAEgDACYACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBwAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAABLgAECn8UAAIkAAcJBxlPEgCeAQAkAAcJBxlPEgCeAQAAAA==.Viridiana:BAAALgAECgYJCgABLgAECgkJLgASADMYAA==.Visea:BAAALgAECgMJBwAAAA==.Viölet:BAAALgAECgMJAwAAAA==.',
Vl='Vlarett:BAAALgAECgQJCAAAAA==.',
Vo='Voidsavage:BAAALgAECgQJCAAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECgkJNgAAAQ==.Voznje:BAAALgAECgIJAgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Warveteran:BAAALgAECgEJAQAAAA==.Watevr:BAEALgAECgYJBgABLgAECggJPQAdANkYAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgMJAwAPAAAAAA==.Wesleypriest:BAABLgAECn8fAAMSAAkJBwntKgBwAQASAAkJ5gjtKgBwAQAhAAMJCwhxaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wi='Wizalf:BAAALgAECgUJCAAAAA==.',
Wr='Wrandanden:BAAALgADCgUJBwAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAgAAAA==.Wynne:BAAALgADCgkJCQAAAA==.',
Xa='Xalabro:BAABLgAECn8uAAIUAAkJ+xUiDAD4AQAUAAkJ+xUiDAD4AQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgANAEkXAA==.',
Xe='Xear:BAAALgADCgcJDwABLgADCgkJRgAPAAAAAA==.Xehorn:BAAALgAECgYJBgABLgAFFAcJGgAIANEeAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJEAAdAOUkAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAINAAcJSReajQC3AQANAAcJSReajQC3AQAAAA==.',
Ya='Yandere:BAAALgAECgEJAQAAAA==.Yashe:BAABLgAECn8eAAMIAAgJQx1xGQByAgAIAAgJQx1xGQByAgAJAAEJWAjekQAlAAABLgAECgkJJQAQACMaAA==.',
Yh='Yhorn:BAABLgAFFH8GAAISAAQJlw/hIgATAQASAAQJlw/hIgATAQABLgAFFAcJGgAIANEeAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAbAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBQAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgQJCAAAAA==.Zareena:BAAALgADCgcJCgAAAA==.Zarnia:BAAALgAECgQJCAAAAA==.Zarrock:BAAALgAECgMJBgAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgQJCAAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAcJGgAIANEeAA==.Zekia:BAAALgAECgQJCAAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zepirra:BAAALgAECgQJBAAAAA==.Zeratule:BAAALgAECgIJAgAAAA==.Zergdemon:BAAALgAECgEJAQAAAA==.Zergul:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn9MAAIKAAkJGx7yFQC2AgAKAAkJGx7yFQC2AgAAAA==.',
Zi='Zijo:BAAALgAECgYJEAAAAA==.Zinnkura:BAAALgAECgYJEwAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAABLgAECn8hAAIDAAkJlgyeTgCqAQADAAkJlgyeTgCqAQAAAA==.',
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
