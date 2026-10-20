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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Warlock-Demonology','Druid-Guardian','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Priest-Discipline','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIEgAAAA==.',
Ae='Aegennai:BAABNQAECn8gAAIBAAcKqARdEAD8AAABAAcKqARdEAD8AAAAAA==.Aegondk:BAEBNQAFFH8GAAICAAMK0xlqDgD0AAACAAMK0xlqDgD0AAAAAA==.Aelias:BAAANQAECgQIBwAAAA==.Aevaela:BAABNQAECn8oAAIDAAgKgRzeEABxAgADAAgKgRzeEABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn8nAAMEAAoKWRP7EwDlAAAEAAgKwRL7EwDlAAAFAAQK5xX3EQHhAAAAAA==.',
Ak='Akey:BAAANQAECgUIEQAAAQ==.Akhae:BAABNQAECn8pAAMGAAgK1BRkYwDjAQAGAAgK1BRkYwDjAQAHAAEKtwHeUQElAAAAAA==.',
Al='Albinism:BAAANQAECgQIDAAAAA==.Alcadeias:BAAANQAECgMIAwAAAA==.Alethiah:BAAANQAECgIIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amuria:BAAANQAECgQIBwAAAA==.',
An='Anaeda:BAABNQAECn8cAAIIAAgKrwxtvACkAQAIAAgKrwxtvACkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgQICQAJAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIFwAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIEQAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAABNQAECn8XAAIKAAcKZBWK2ADWAQAKAAcKZBWK2ADWAQAAAA==.Arthar:BAABNQAECn9CAAILAAoKbx71OQDeAgALAAoKbx71OQDeAgAAAA==.',
As='Ashvyth:BAABNQAECn8eAAIMAAgKrB+iCQCFAgAMAAgKrB+iCQCFAgAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgANAOUbAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.Azurelive:BAAANQABCgYIBgAAAA==.',
Ba='Babalou:BAAANQADCgcIAwAAAA==.Baconpancake:BAAANQAECgUICQAAAA==.Baldpunch:BAAANQADCggINAAAAA==.Balinor:BAAANQAECgUIBgAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgUIDgAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgUIDgAJAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAABNQAECn8VAAIOAAcKJRRZWgCmAQAOAAcKJRRZWgCmAQAAAA==.Beaj:BAAANQAECgUICgAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8eAAMPAAcK3h4XEwDbAQAPAAcK3h4XEwDbAQAQAAIKkA7sYwBwAAAAAA==.Bigblingaxe:BAAANQADCgIIAgAAAA==.Bilac:BAAANQADCgEIAQABNQAECgoKLwARALwQAA==.',
Bl='Blusoleil:BAAANQAECgUICQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECn8oAAQCAAkKVBqmMgAVAgACAAkKpBemMgAVAgAOAAUKFhykXQCZAQASAAMKsRAInQCgAAAAAA==.',
Br='Branches:BAABNQAECn8pAAMTAAcKpw1uNwBhAQATAAcKpw1uNwBhAQAUAAcKnhBmFgAqAQAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAABNQAECn8VAAIFAAgKKQc8xwBzAQAFAAgKKQc8xwBzAQAAAA==.Briggsey:BAABNQAECn8fAAIVAAcKhwmjRAACAQAVAAcKhwmjRAACAQAAAA==.Briznot:BAAANQAECggIDQAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBQAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgcIFAAAAA==.',
Bu='Bubbadubya:BAAANQADCgcIIwAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQAECgQIBgABNQAECgoKLwARALwQAA==.Burningwolf:BAAANQAECgcIEgAAAA==.',
['Bó']='Bórs:BAAANQAECgUICwAAAA==.',
Ca='Caiden:BAAANQAECgQIBgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Calesona:BAAANQAECgIIAwAAAA==.Carnìfex:BAAANQAECgQICQAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAAANQAECgcIDgAAAA==.',
Ce='Cerà:BAABNQAECn8YAAITAAcK0RHjDgBVAQATAAcK0RHjDgBVAQAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgYIDQAAAA==.',
Cl='Clizee:BAAANQAECgQICgAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAABNQAECn8YAAMUAAgKRhEJTwCjAQAUAAcKRhEJTwCjAQAWAAQKfg9XQAC5AAAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Coldtex:BAAANQAECggIAQAAAA==.Constellate:BAAANQAECgYIEwAAAA==.Cotterpins:BAAANQAECgcICAAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.Crunchyjim:BAAANQAECgMIBAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.Cyndlia:BAAANQADCgEIAQAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECn8zAAMHAAoKWBZCEACTAQAHAAoKWBZCEACTAQAGAAQK1wtkdgBnAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgYIFQADAIEPAA==.Damnitsu:BAEBNQAECn8VAAMDAAYKgQ9xKACBAQADAAYKXQ5xKACBAQAXAAUKBgtBZwAVAQAAAA==.Darckside:BAAANQAECgIIAgAAAA==.Dazen:BAAANQADCgcIFAAAAA==.',
De='Deadflexy:BAAANQAECgcIDQAAAA==.Deathberry:BAABNQAECn8jAAIVAAgKPRuXUABjAgAVAAgKPRuXUABjAgAAAA==.Deathdoodles:BAAANQAECgcIEAABNQAECgkJMAAPAFQYAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgUICQAAAA==.Dejavù:BAAANQAFFAIIAgAAAA==.Demonblood:BAABNQAECn8YAAMSAAkKFhE6TgC9AQASAAgKmBI6TgC9AQAOAAEKCwieUgA4AAAAAA==.Demonicmac:BAAANQADCgMJAwABNQAECgQICAAJAAAAAA==.Deräth:BAABNQAECn8WAAIQAAcKbAdFOwBPAQAQAAcKbAdFOwBPAQAAAA==.Devlik:BAAANQAECgMIAQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAJAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Dh='Dhdawg:BAAANQAECgIIAQAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIEAAAAA==.Dionne:BAAANQAECgYIBgAAAA==.Ditsie:BAAANQAECgEJAQAAAA==.',
Dm='Dmega:BAABNQAECn8YAAIFAAcKkAvgPwA3AQAFAAcKkAvgPwA3AQAAAA==.',
Do='Dogfunk:BAAANQABCgcICgAAAA==.Dorne:BAAANQADCgIIAQAAAA==.',
Dr='Dragea:BAAANQAECgUICAAAAA==.Dragondude:BAABNQAECn8YAAMYAAgKZB08FABrAgAYAAgKZB08FABrAgAZAAEKuQXvOwA2AAAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFH8QAAISAAUK3Ra5DQB4AQASAAUK3Ra5DQB4AQA1AAQKfycAAhIACgqLIMMbANACABIACgqLIMMbANACAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgcIDQAAAA==.',
Dy='Dyelin:BAABNQAECn8dAAIVAAgK2hgVXgA9AgAVAAgK2hgVXgA9AgAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQAECgIIAgAAAA==.Elyron:BAABNQAECn8fAAIKAAkKhhR4uQARAgAKAAkKhhR4uQARAgAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn8sAAMNAAoKcBw9CwAQAgAKAAoKBBpwVwDRAgANAAcKOR09CwAQAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgQIBQAAAA==.',
Eu='Euandros:BAAANQAECgQIBAAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQAAAA==.Ezind:BAAANQAECgYIDAAAAA==.',
Fa='Fakename:BAAANQAECgcICwAAAA==.Fakesaint:BAABNQAECn8sAAIGAAkKsiF/FQAjAwAGAAkKsiF/FQAjAwAAAA==.Fangstorm:BAABNQAECn8eAAIaAAgKfA1pGAB0AQAaAAgKfA1pGAB0AQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgUIDAAAAA==.',
Fe='Feldruid:BAAANQAECgQIDAAAAA==.Felup:BAABNQAECn8zAAQVAAkKnB0GBgBSAgAVAAkKnB0GBgBSAgAbAAIK+xEqVgB8AAAcAAEK5BvQKgBCAAAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAABNQAECn8mAAMdAAoKwRTFBwBKAgAdAAoKwRTFBwBKAgAIAAEKDAJayQEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8qAAIeAAkKdw05BQBWAQAeAAkKdw05BQBWAQAAAA==.Fusepins:BAAANQADCgcIAwAAAA==.Fuzzwig:BAAANQADCgcIDQAAAA==.',
Ga='Gaska:BAAANQAECgYICwABNQAECgUIDAAJAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgcIBQABNQAECggIDAAJAAAAAA==.',
Gr='Gracela:BAAANQADCgEIAQAAAA==.Graxus:BAAANQAECgQIBQAAAA==.Greth:BAAANQADCggIJAAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.Grumpy:BAAANQADCgcIAwABNQAECgcIDQAJAAAAAA==.',
Gu='Gudge:BAABNQAECn8vAAMRAAoKvBAyCAAYAgARAAoKvBAyCAAYAgAYAAEK8wFTVQAeAAAAAA==.Gummypenguin:BAABNQAECn8dAAIFAAoKgCFnRgCZAgAFAAoKgCFnRgCZAgABNQAFFAUIFgAFAGckAA==.',
Ha='Hadhox:BAAANQAECgMIBAABNQAECgkJJwAFAAoOAA==.Halforcked:BAAANQADCgUIBQAAAA==.Hathdox:BAABNQAECn8nAAIFAAkKCg5SFADQAQAFAAkKCg5SFADQAQAAAA==.Hawkulees:BAAANQADCgcIHQAAAA==.Hazelnoot:BAABNQAECn80AAIIAAoKZyNnAgAEAwAIAAoKZyNnAgAEAwAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAFFAEIAQAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8ZAAIfAAgKdwxsRgCUAQAfAAgKdwxsRgCUAQAAAA==.',
Hi='Hitsuryu:BAAANQAECgUIEQAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8fAAMXAAoKYQyyPgDTAQAXAAkKYQyyPgDTAQAgAAYK3gTmEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgMJBAAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAJAAAAAA==.Hornsharp:BAAANQAECgQIBwAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgoKLwARALwQAA==.Hunilla:BAABNQAECn8XAAQQAAYKLgxRPABIAQAQAAYKLgxRPABIAQAPAAUK+gZxvADkAAAhAAEK6gHnDAAgAAABNQAECgoKLwARALwQAA==.',
Ia='Iamu:BAAANQADCgYIGQAAAA==.',
Ib='Ibris:BAAANQADCgcIFAAAAA==.',
Ic='Iconius:BAAANQADCgcIFAAAAA==.',
Ie='Ieatwetsocks:BAABNQAECn8gAAMGAAoK9xTLVwAKAgAGAAoK9xTLVwAKAgAHAAIKWwTtIQFNAAAAAA==.',
Ig='Ignivar:BAAANQADCggIFgAAAA==.',
In='Indra:BAAANQAECgYIDAAAAA==.Innexshaman:BAABNQAECn8eAAIHAAkKSRjOQwBnAgAHAAkKSRjOQwBnAgAAAA==.Insaint:BAACNQAFFH8FAAIIAAMKhgc6HADGAAAIAAMKhgc6HADGAAA1AAQKfywAAggACgpxFdMtAHYBAAgACgpxFdMtAHYBAAAA.',
Ir='Ironfield:BAABNQAECn8YAAMGAAgKYxoJWQAGAgAGAAgKYxoJWQAGAgAHAAMKFQNFCgF3AAABNQADCgUIBQAJAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAABNQAECn8ZAAIQAAYKIwbuSwDmAAAQAAYKIwbuSwDmAAAAAA==.',
Je='Jessamine:BAABNQAECn82AAIKAAoKMhOcCgAhAgAKAAoKMhOcCgAhAgAAAA==.Jetta:BAAANQAECgQIDAAAAA==.Jezzak:BAABNQAECn8mAAIFAAkK/hAOdwAhAgAFAAkK/hAOdwAhAgABNQAECgoKKAAFAMwWAA==.',
Jo='John:BAABNQAECn9GAAIgAAoKTiKVAAC3AwAgAAoKTiKVAAC3AwAAAA==.Jorien:BAABNQAECn8sAAIFAAkKGxvfQwCfAgAFAAkKGxvfQwCfAgAAAA==.',
Jp='Jp:BAAANQAECgUICAAAAA==.Jpb:BAAANQAECgEIAQABNQAECgUICAAJAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgUICAAJAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgUICAAJAAAAAA==.',
Ju='Justadwarf:BAAANQAECgYIBgAAAA==.Justatsuj:BAAANQAECgQIBAAAAA==.Juston:BAABNQAECn8WAAMHAAgKqg3hFgBoAQAHAAcKqg3hFgBoAQAGAAYKRAacywDQAAAAAA==.',
Ka='Kaboonsky:BAABNQAECn8ZAAMPAAkKHRpnDwD/AQAPAAkKHRpnDwD/AQAQAAYKMg8OOQBdAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIJAgAAAA==.Kamikori:BAAANQAECgUIEQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAJAAAAAA==.Karnadaz:BAABNQAECn8hAAILAAkKRhoNYwBlAgALAAkKRhoNYwBlAgAAAA==.Karnkarn:BAAANQAECgYICgAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgQICQAJAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIGAAcKRCPWMwCQAgAGAAcKRCPWMwCQAgAAAA==.',
Ko='Kolosho:BAAANQAECgYIBgAAAA==.Korxana:BAABNQAECn8bAAIiAAgK+Q7zJQCwAQAiAAgK+Q7zJQCwAQAAAA==.Korxon:BAABNQAECn8tAAIPAAoKDxi0HgCLAQAPAAoKDxi0HgCLAQAAAA==.Kotus:BAAANQAECgcICQAAAA==.',
Ks='Ksyusha:BAAANQAECgUIDwAAAA==.',
Ky='Kyfess:BAAANQAECgYICwAAAA==.',
['Kä']='Kämi:BAAANQADCgYICgABNQAECgQIDAAJAAAAAA==.',
La='Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgEIAQAAAA==.Lanuadra:BAABNQAECn8nAAIDAAkKpheaDwCCAgADAAkKpheaDwCCAgAAAA==.Lawry:BAAANQAECgYICwAAAA==.Layhee:BAAANQAFFAMIBAAAAA==.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAAJAAAAAA==.Lethalbimbo:BAAANQADCggIGwAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQABCgQIBAABNQADCgcIBwAJAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFH8VAAIGAAYKEhn9CQCvAQAGAAYKEhn9CQCvAQA1AAQKfzQAAwYACgopIQMsALICAAYACgopIQMsALICAAcACAoWFbtdAAkCAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgUICAAAAA==.',
Lo='Lomea:BAAANQADCgYICQABNQAECgIIAgAJAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQADCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgcIFQAOACUUAA==.',
['Lø']='Løllîe:BAAANQAECgQICQAAAA==.',
Ma='Macarius:BAAANQAECggIDQAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAAJAAAAAA==.Magatai:BAAANQAECgIIAgAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAJAAAAAA==.Manaster:BAAANQAECgUICgAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgQICgAAAA==.Mathas:BAAANQAECgEIAgAAAA==.Mathius:BAAANQAECgEIAQAAAA==.Maynis:BAAANQABCgQIBgAAAA==.',
Me='Meanwhile:BAAANQADCgcIBQAAAA==.Meowmixx:BAAANQADCgMIAwAAAA==.Merkii:BAAANQADCgYIBgABNQAECgoKHgAXAKAYAA==.',
Mi='Micflinigan:BAABNQAECn8kAAMeAAgKGxa4AgCvAQAeAAgKGxa4AgCvAQALAAMKJg8vGgGoAAAAAA==.Midnightmare:BAAANQABCgMIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgUICwAAAA==.Ming:BAAANQADCgQIBAABNQAECgoKMwAjAHUgAA==.Minilove:BAAANQADCgUICAAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgQICwAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQIBwAAAA==.Moonshae:BAABNQAECn8xAAMjAAoKGxLaCABMAQAjAAkKZxPaCABMAQAkAAcK6hP8OABMAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgMIAgAAAA==.',
Mu='Murciélago:BAAANQAECgQIBAAAAA==.',
My='Mystiquè:BAAANQADCgYIHgAAAA==.',
Na='Nahmbra:BAAANQAECgUICQAAAA==.Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQABCgQIBAAAAA==.Naviriel:BAAANQADCgYIBAABNQAECggICQAJAAAAAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQAECgQICAABNQAECgoKQgALAG8eAA==.',
No='Nofoxgìven:BAAANQAECgIIAgAAAA==.Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFH8JAAIiAAcKGg2EAwDIAQAiAAcKGg2EAwDIAQA1AAQKfxgAAiIACQoTJFcEAHMDACIACQoTJFcEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgYIEgAJAAAAAA==.Noriisa:BAABNQAECn8oAAIFAAoKzBaxXABfAgAFAAoKzBaxXABfAgAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAABNQAECn8gAAIGAAkKPxq+VwAKAgAGAAkKPxq+VwAKAgAAAA==.',
Ny='Nyvak:BAAANQAECgUICgAAAA==.',
Od='Odinhand:BAABNQAECn8yAAIUAAkKXQrvDQBuAQAUAAkKXQrvDQBuAQAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCggIIwAAAA==.',
Oz='Ozwäld:BAABNQAECn8WAAIKAAcK5Q81XwD/AAAKAAcK5Q81XwD/AAABNQAECgoKMgABAK4gAA==.Ozwäldo:BAABNQAECn8yAAIBAAoKriCQBgAcAwABAAoKriCQBgAcAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn8mAAMKAAoK4hljHgCXAQAKAAoK4hljHgCXAQANAAIKVRLiMgBvAAAAAA==.Pandóra:BAAANQAECgIIAQAAAA==.Pariousa:BAABNQAECn8kAAIXAAoKzyLTDQAVAwAXAAoKzyLTDQAVAwAAAA==.',
Pe='Peppermintxo:BAAANQAECgUIBAABNQADCgIJAgAJAAAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgIIAgAAAA==.Phylinx:BAAANQADCgEIAQAAAA==.',
Pi='Pinkeepink:BAAANQAECgMIBgAAAA==.',
Po='Popacooldown:BAAANQAECgEIAQAAAA==.Potangwang:BAAANQAECgIIAQAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgYICgAAAA==.',
Pu='Puhk:BAAANQADCgcICQAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgYIDgAAAA==.Raijù:BAAANQAECgEIAQAAAA==.Ralganor:BAABNQAECn82AAISAAoK0x5TAQDpAgASAAoK0x5TAQDpAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECgUICgAAAA==.Ravilan:BAAANQAECgMIBQAAAA==.Raynlight:BAAANQAECgYIDgAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.Retaeytoob:BAAANQAECgEIAQAAAA==.',
Ri='Rina:BAABNQAECn8UAAMlAAgK1BTJJwAGAgAlAAgKbxTJJwAGAgAmAAEKoQlZNAAqAAAAAA==.Rineli:BAAANQADCgcICgABNQAECgUICwAJAAAAAA==.Ringadingg:BAABNQAECn8hAAMOAAoKax2MGAD6AgAOAAoKax2MGAD6AgACAAEKSCDfmgBdAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgIIBwAAAA==.',
Sa='Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgcIDAAAAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECgYICwAAAA==.Scribs:BAAANQAECgYICwAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQAECggICAAAAA==.Seniko:BAAANQABCgIIAgAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8dAAMHAAkK3RtTfQCsAQAHAAYKZhpTfQCsAQAGAAUKlQc77QCRAAABNQAECgkJKAAmAJkYAA==.Severalforms:BAABNQAECn8aAAMWAAkKnh5xAQCNAgAWAAkKcx5xAQCNAgAaAAIK0hdVMACPAAABNQAECgkJKAAmAJkYAA==.Severànce:BAABNQAECn8oAAQmAAkKmRgDDgDcAQAmAAgK8RUDDgDcAQAfAAUK1BRmTwBcAQAlAAQKvBGVTwDiAAAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJKAAmAJkYAA==.',
Sh='Shablammy:BAAANQAECgUIEQAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgcIFAAAAA==.Shadowolves:BAAANQADCgEIAQAAAA==.Shadowson:BAAANQABCgEIAQAAAA==.Shammygand:BAAANQADCgUJBQABNQAECgoKHQAZALsaAA==.Shanker:BAAANQADCgMIAwAAAA==.Sheephappéns:BAAANQAECggICAABNQAECgkJKAAmAJkYAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn8wAAMPAAkKVBh+MACmAgAPAAkKVBh+MACmAgAQAAIKGQNvNAAzAAAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECn80AAIWAAgKFx9RDQCRAgAWAAgKFx9RDQCRAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skydragon:BAAANQADCggIHwAAAA==.',
Sl='Slay:BAAANQAECgEIAQAAAA==.Slayful:BAAANQABCgQJBAAAAA==.Sleepydwarf:BAAANQADCggJCAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAAANQAECggIDAAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICgAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAAANQAECgYIEgAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgcICAAJAAAAAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCggIIAAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIICQAfAH8eAA==.Strongbad:BAAANQAECgIIAgAAAA==.Stubly:BAAANQADCgUIBAAAAA==.',
Su='Sunfyrie:BAABNQAECn8aAAIPAAcKHRf4GACsAQAPAAcKHRf4GACsAQAAAA==.',
Sw='Sweèt:BAAANQAECgIIAgAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgUICgAAAA==.Taurdk:BAAANQAECgYIDQAAAA==.Taylorshift:BAABNQAECn8nAAIUAAoKpB/7FwAIAwAUAAoKpB/7FwAIAwAAAA==.Tazbeard:BAAANQADCgcIAwABNQAECgMIAwAJAAAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgEIAQAJAAAAAA==.Teetau:BAABNQAECn8eAAIWAAgKDQTaOgDXAAAWAAgKDQTaOgDXAAAAAA==.',
Th='Thadregosa:BAABNQAECn8bAAIZAAgK2BL9FQDrAQAZAAgK2BL9FQDrAQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCggIFwAAAA==.Thedarkskull:BAAANQABCgIIAgAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Timoleon:BAAANQAECgQIAwAAAA==.Tirna:BAAANQAECgEJAgAAAA==.Tirnotham:BAAANQAECgUIEQAAAA==.',
Tm='Tmtglizzy:BAABNQAECn8jAAMGAAkKKRwDIQBkAQAGAAkKKRwDIQBkAQAHAAQK7xX/uAAgAQAAAA==.',
To='Tokalu:BAAANQAECggICQAAAA==.Tonjudsonson:BAACNQAFFH8OAAIWAAUKBRKZAwAjAQAWAAUKBRKZAwAjAQA1AAQKfzIAAxYACgrMH0kDAIYDABYACgrMH0kDAIYDABoAAQoAAHYpAAAAAAAA.Torath:BAAANQADCgYJCwABNQADCggIFwAJAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIGwAAAA==.',
Tw='Twiki:BAABNQAECn8cAAIbAAcK7QPAMwD1AAAbAAcK7QPAMwD1AAAAAA==.Twobricks:BAABNQAECn8yAAITAAkK7hVaBAAvAgATAAkK7hVaBAAvAgAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQAECgUIDwABNQAFFAMIBQAZANwCAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn8yAAIiAAkKwx4EAQC8AgAiAAkKwx4EAQC8AgABNQABCgYICAAJAAAAAA==.',
Ur='Urdeadtoo:BAAANQAECgUIEQAAAA==.Urlacher:BAAANQAECgQIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAABNQAECn8UAAIIAAYKaArahwDBAAAIAAYKaArahwDBAAAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIHAAAAA==.Verlynna:BAAANQADCgEIAQAAAA==.Vertexx:BAAANQAECgEIAgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECggIDQAJAAAAAA==.Vierth:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQADCgQIBAAAAA==.Visea:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIGQAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECggIGgAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
Wa='Watevr:BAEANQADCgcIDgABNQAECgYIFQADAIEPAA==.',
We='Weemer:BAAANQADCgcICwAAAA==.Wesleypipes:BAABNQAECn8bAAIGAAgKOBMUcwCyAQAGAAgKOBMUcwCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQAECgcIEwAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpally:BAABNQAECn8kAAIdAAoK0RSJNwCGAgAdAAoK0RSJNwCGAgAAAA==.Wolfmato:BAABNQAECn8kAAIGAAoKkR25JwDFAgAGAAoKkR25JwDFAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAAANQAECgUIEQAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQAECgYIBgAJAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgoKJAAXAM8iAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAYIFQAGABIZAA==.',
Ys='Yssuplef:BAAANQAECgUIDwAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.',
Za='Zaiyra:BAAANQAECgQIBQAAAA==.Zakoor:BAAANQADCgcIFQAAAA==.Zambreth:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgcIHQAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zaurra:BAAANQAECgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIIAAAAA==.Zekia:BAABNQAECn8lAAIFAAgK+RkcVwBtAgAFAAgK+RkcVwBtAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergul:BAAANQABCgQIBAAAAA==.Zerm:BAABNQAECn8oAAIIAAkKThJdgQAmAgAIAAkKThJdgQAmAgAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAAANQAECgYIDQAAAA==.',
Zo='Zorsa:BAAANQAECgMIBgAAAA==.',
Zu='Zuljawn:BAABNQAECn8eAAIEAAgKYw28NgCYAQAEAAgKYw28NgCYAQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIKAAAAA==.',
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
