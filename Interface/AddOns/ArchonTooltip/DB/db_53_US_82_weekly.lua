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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Priest-Shadow','Evoker-Augmentation','Paladin-Protection','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Druid-Feral','Druid-Guardian','Paladin-Holy','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Priest-Discipline','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIEgAAAA==.',
Ae='Aegennai:BAABNQAECn83AAIBAAkK0wVfGgBWAQABAAkK0wVfGgBWAQAAAA==.Aegondk:BAABNQAFFH8GAAICAAMK0xlqDgD0AAACAAMK0xlqDgD0AAAAAA==.Aeli:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.Aelias:BAAANQAECgYIDQAAAA==.Aevaela:BAABNQAECn8wAAIEAAkKjhveEABxAgAEAAkKjhveEABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn83AAMFAAoK3hMEGgChAQAFAAkKJRIEGgChAQAGAAUKhhR+6QDDAAAAAA==.',
Ak='Akey:BAAANQAECggIIQAAAQ==.Akhae:BAABNQAECn8tAAMHAAkKKBdkYwDjAQAHAAkKKBdkYwDjAQAIAAEKtwHeUQElAAAAAA==.',
Al='Albinism:BAABNQAECn8VAAIBAAYKhwg0HwAWAQABAAYKhwg0HwAWAQAAAA==.Alcadeias:BAAANQAECgYIDQAAAA==.Alethiah:BAAANQAECgEIAgAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amehnet:BAAANQAECgEIAQAAAA==.Amuria:BAAANQAECgQICgAAAA==.',
An='Anaeda:BAABNQAECn8cAAIJAAgKrwxtvACkAQAJAAgKrwxtvACkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgcIEgADAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQAECgEIAwAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIEQAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAABNQAECn8XAAIKAAcKZBWK2ADWAQAKAAcKZBWK2ADWAQAAAA==.Argalnor:BAAANQADCgMIAwAAAA==.Arthar:BAABNQAECn9RAAILAAoKECBQMQBsAgALAAoKECBQMQBsAgAAAA==.',
As='Ashvyth:BAABNQAECn8xAAQMAAoKfxwIBQBHAgAMAAkK6h4IBQBHAgANAAEKkwuVWAA2AAAOAAEKKAUMQQAhAAAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAPAOUbAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.Azurelive:BAAANQABCgYIBgAAAA==.',
Ba='Babalou:BAAANQADCgcIAwAAAA==.Baconpancake:BAAANQAECgQIDAAAAA==.Baldpunch:BAAANQAECgEIAQAAAA==.Balinor:BAAANQAECgYIEQAAAA==.Ballz:BAAANQAECgEIAQAAAA==.Balom:BAAANQAECgUIEQAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgUIEQADAAAAAA==.Barnabus:BAAANQAECgIIBwAAAA==.',
Be='Beachbecrazy:BAABNQAECn8ZAAIQAAgKthNZWgCmAQAQAAgKthNZWgCmAQAAAA==.Beaj:BAABNQAECn8YAAMRAAcKCglFEQAGAQARAAcKCglFEQAGAQASAAMKigf1UACMAAAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8tAAMTAAkKPiCVGQD5AgATAAkKPiCVGQD5AgAUAAQKrA47PwCfAAAAAA==.Bigblingaxe:BAAANQADCggICgAAAA==.Bilac:BAAANQADCgEIAQABNQAFFAIIBQAVAEoBAA==.',
Bl='Blacksabbth:BAAANQABCgIIAgAAAA==.Blusoleil:BAABNQAECn8XAAMWAAcKNRETRADiAAAWAAcKNRETRADiAAAJAAUKSgeJOAGFAAAAAA==.Blux:BAAANQAECgQIBQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECn89AAQCAAoKzB8CIQAzAgACAAoKDRwCIQAzAgAQAAgKxR3RLQBnAQAXAAYKHhhqPwAzAQAAAA==.',
Br='Branches:BAABNQAECn85AAMYAAoKXg98JwCsAQAYAAoKXg98JwCsAQAZAAcKpw1uNwBhAQAAAA==.Branden:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAABNQAECn8VAAIGAAgKKQc8xwBzAQAGAAgKKQc8xwBzAQAAAA==.Briggsey:BAABNQAECn8tAAIaAAkK6gkRegBbAQAaAAkK6gkRegBbAQAAAA==.Brisdelle:BAAANQABCgQIBAAAAA==.Briznot:BAABNQAECn8eAAMSAAkKiBJiFACsAAAaAAcKwhBRjQAsAQASAAMKjBNiFACsAAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBgAAAA==.Bryce:BAAANQAECgEIAgAAAA==.Brèanna:BAAANQADCggIFgAAAA==.',
Bu='Bubbadubya:BAAANQADCggIKwAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQAECgUICwABNQAFFAIIBQAVAEoBAA==.Burningwolf:BAABNQAECn8iAAIHAAoKKx2rGgDOAgAHAAoKKx2rGgDOAgAAAA==.',
['Bó']='Bórs:BAAANQAECgQIEgAAAA==.',
Ca='Caiden:BAAANQAECgUIBwAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQAECgEIAQAAAA==.Calesona:BAAANQAECgQICwAAAA==.Carnìfex:BAAANQAECgYIEwAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAABNQAECn8jAAQbAAoKIiAvBADcAgAbAAoKIiAvBADcAgAcAAgKwxooFwC9AQAYAAEKrRA2sgAyAAAAAA==.',
Ce='Cellene:BAAANQAECgUIBQABNQAECgoKPAAIAJ4ZAA==.Cerà:BAABNQAECn8iAAIZAAgKChZNGwASAgAZAAgKChZNGwASAgAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgcIDgAAAA==.',
Ci='Cinnawhiskey:BAAANQADCgUIBQAAAA==.',
Cl='Cleetus:BAAANQAECgcICgAAAA==.Clizee:BAABNQAECn8eAAIKAAkKXgdUqABBAQAKAAkKXgdUqABBAQAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAABNQAECn8eAAQYAAkKJRAJTwCjAQAYAAkKJRAJTwCjAQAcAAUK6A5XQAC5AAAZAAMKXguWVwCEAAAAAA==.',
Co='Cobramage:BAAANQAECgQICgAAAA==.Coldtex:BAAANQAECggIAwAAAA==.Constellate:BAABNQAECn8VAAIdAAcKCBHYfQCgAQAdAAcKCBHYfQCgAQAAAA==.Cotterpins:BAABNQAECn8hAAIJAAoKWRTaWwAMAgAJAAoKWRTaWwAMAgAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.Crunchyjim:BAAANQAECgMIBAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.Cyndlia:BAAANQADCgUIBQAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECn88AAMIAAoKnhn+MQCyAgAIAAoKnhn+MQCyAgAHAAQK1wu68gCFAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgcIIgAEAG0QAA==.Damnitsu:BAEBNQAECn8iAAMEAAcKbRBxKACBAQAEAAYK8A9xKACBAQAeAAYK3AtBZwAVAQAAAA==.Darckside:BAAANQAECgcIDAAAAA==.Dazen:BAAANQADCggIGAAAAA==.',
De='Deadflexy:BAABNQAECn8fAAIXAAoKWRlxGgAdAgAXAAoKWRlxGgAdAgAAAA==.Deathberry:BAABNQAECn8jAAIaAAgKPRuXUABjAgAaAAgKPRuXUABjAgAAAA==.Deathdoodles:BAABNQAECn8XAAMQAAcK6g6kRwDZAAAQAAcKog6kRwDZAAACAAIKEQoolwBmAAABNQAECgoKPgATAGkYAA==.Deathriaa:BAAANQADCgEIAQABNQAECggIAwADAAAAAA==.Deathsveil:BAAANQADCgcIBwAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgYIEAAAAA==.Dejavù:BAAANQAFFAIIAwAAAA==.Demonblood:BAABNQAECn8gAAMXAAoKdRE6TgC9AQAXAAkKsBI6TgC9AQAQAAEK2ggnhAA0AAAAAA==.Demonicmac:BAAANQADCgMIAwABNQAECgQICgADAAAAAA==.Deräth:BAABNQAECn8bAAIUAAgKfQdFOwBPAQAUAAgKfQdFOwBPAQAAAA==.Devlik:BAAANQAECgMIAgAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgADAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Dh='Dhdawg:BAAANQAECgIIAQAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIFgAAAA==.Dionne:BAAANQAECgcIDwAAAA==.Dippindots:BAAANQAECgEIAQABNQAECgoKQAAKALkhAA==.Ditsie:BAAANQAECgEIAQAAAA==.',
Dm='Dmega:BAABNQAECn8uAAIGAAkKrwtJeQCvAQAGAAkKrwtJeQCvAQAAAA==.',
Do='Dobby:BAAANQAECgYIBgAAAA==.Dodgeramthis:BAAANQADCgIIAgAAAA==.Dogfunk:BAAANQABCgcICgAAAA==.Doomalay:BAAANQAECgUIBQAAAA==.Dorne:BAAANQADCgIIAgAAAA==.',
Dr='Dragea:BAABNQAECn8bAAMfAAcK1hdwFgB1AQAfAAYKcxlwFgB1AQAgAAIK3wvxGwB4AAAAAA==.Dragondude:BAABNQAECn8oAAQfAAoKwxk8FABrAgAfAAoKwxk8FABrAgAgAAYKVQyLEQANAQAVAAIKhQsLFwBlAAAAAA==.Dragonsgrasp:BAAANQADCgUICAAAAA==.Drakoswrath:BAACNQAFFH8SAAIXAAcKwRO5DQB4AQAXAAcKwRO5DQB4AQA1AAQKfzcAAhcACgrCJBAHABEDABcACgrCJBAHABEDAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAABNQAECn8eAAILAAgKtxylUQD3AQALAAgKtxylUQD3AQAAAA==.',
Dy='Dyelin:BAABNQAECn8xAAIaAAoKJRqKJwBjAgAaAAoKJRqKJwBjAgAAAA==.',
['Dõ']='Dõtdropnroll:BAAANQAECgMIAgAAAA==.',
Ed='Eddyshadess:BAAANQABCgcICQAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQAECgIIAwABNQAECgQIBwADAAAAAA==.Elyron:BAABNQAECn8zAAIKAAoKmBa8SwAdAgAKAAoKmBa8SwAdAgAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn9AAAMKAAoKpB/SKgCIAgAKAAoKrB7SKgCIAgAPAAcKOR09CwAQAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgUICQAAAA==.',
Eu='Euandros:BAABNQAECn8bAAIJAAkKrAmZqQBlAQAJAAkKrAmZqQBlAQAAAA==.',
Ev='Evï:BAAANQAECgEIAQAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQAECgEIAQADAAAAAA==.Ezind:BAAANQAECgcIEgAAAA==.',
Fa='Fakename:BAAANQAECggIDwAAAA==.Fakesaint:BAABNQAECn88AAIHAAoKgCR/FQAjAwAHAAoKgCR/FQAjAwAAAA==.Fangstorm:BAABNQAECn8vAAIbAAkKEBMREACmAQAbAAkKEBMREACmAQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgYIEAAAAA==.',
Fe='Feldruid:BAAANQAECgQIDQAAAA==.Felup:BAABNQAECn9FAAQaAAoKRSIuHwAHAwAaAAoKRSIuHwAHAwASAAIK+xEqVgB8AAARAAEK5BvQKgBCAAAAAA==.',
Fl='Fluster:BAAANQAECgUIBQAAAA==.Flåsh:BAAANQAECgEIAQAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAABNQAECn9FAAMdAAoKnhsQGwDQAgAdAAoKnhsQGwDQAgAJAAEKDAJayQEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8vAAIhAAkKSw/lDgC/AQAhAAkKSw/lDgC/AQAAAA==.Fusepins:BAAANQADCgcIAwAAAA==.Fuzzwig:BAAANQADCgcIDQAAAA==.',
Ga='Gaska:BAAANQAECgYICwABNQAECgUIDAADAAAAAA==.',
Ge='Geralan:BAAANQAECgEIAQAAAA==.',
Gh='Ghösty:BAAANQADCgMIAwABNQAECggIAwADAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgcIBQABNQAECgkJHQAUALYbAA==.',
Gr='Gracela:BAAANQADCgEIAQAAAA==.Graxus:BAAANQAECgYIDwAAAA==.Greth:BAAANQADCggILAAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.Grumpy:BAAANQADCgcIAwABNQAECgoKHwAXAFkZAA==.',
Gu='Gudge:BAACNQAFFH8FAAIVAAIKSgFACwBWAAAVAAIKSgFACwBWAAA1AAQKfz8AAxUACgqpETIIABgCABUACgqpETIIABgCAB8AAwruAQA6AC4AAAAA.Gummypenguin:BAABNQAECn8qAAIGAAoK4SLCFgDhAgAGAAoK4SLCFgDhAgABNQAFFAUIFwAGAGckAA==.',
Ha='Hadhox:BAAANQAECgMIBgABNQAECgoKPAAGANAPAA==.Halforcked:BAAANQADCgYICQAAAA==.Hathdox:BAABNQAECn88AAIGAAoK0A9YWAACAgAGAAoK0A9YWAACAgAAAA==.Hawkulees:BAAANQADCggIJQAAAA==.Hazelnoot:BAABNQAECn9DAAMJAAoKMSQGEACKAwAJAAoKMSQGEACKAwAdAAMKUgpgxQB5AAAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgUICAAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8nAAIiAAgKCQ06PQAvAQAiAAgKCQ06PQAvAQAAAA==.',
Hi='Hitsuryu:BAABNQAECn8lAAIVAAgKnwJKGAC0AAAVAAgKnwJKGAC0AAAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8fAAMeAAoKYQyyPgDTAQAeAAkKYQyyPgDTAQAjAAYK3gTmEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECggIDAAAAA==.Holynoot:BAAANQAECgMIAwABNQAECgoKQwAJADEkAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgADAAAAAA==.Hornsharp:BAAANQAECgYIDQAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAFFAIIBQAVAEoBAA==.Hunilla:BAABNQAECn8bAAQUAAYKLgxRPABIAQAUAAYKLgxRPABIAQATAAUK+gZxvADkAAAkAAEK6gEPHQAfAAABNQAFFAIIBQAVAEoBAA==.Huuken:BAAANQADCgUIBQAAAA==.',
Ia='Iamu:BAAANQADCgYIGQAAAA==.',
Ib='Ibris:BAAANQADCggIGAAAAA==.',
Ic='Iconius:BAAANQADCggIGAAAAA==.',
Ie='Ieatwetsocks:BAACNQAFFH8KAAIHAAQKmw+6EwAHAQAHAAQKmw+6EwAHAQA1AAQKfyQAAwcACgo4FctXAAoCAAcACgo4FctXAAoCAAgAAgpbBO0hAU0AAAAA.',
Ig='Ignivar:BAAANQADCggIFgAAAA==.',
In='Indra:BAAANQAECgYIDAAAAA==.Innexshaman:BAABNQAECn8rAAIIAAoKSRlqLAAXAgAIAAoKSRlqLAAXAgAAAA==.Insaint:BAACNQAFFH8OAAIJAAUKYAysFgDIAAAJAAUKYAysFgDIAAA1AAQKf0UAAgkACgpfGZY/AF0CAAkACgpfGZY/AF0CAAAA.',
Ir='Ironfield:BAABNQAECn8gAAMHAAoKNhfsQAD6AQAHAAoKNhfsQAD6AQAIAAMKFQNFCgF3AAABNQADCgUIBQADAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAwAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAABNQAECn8dAAIUAAYKNwbuSwDmAAAUAAYKNwbuSwDmAAAAAA==.',
Je='Jessamine:BAABNQAECn9OAAIKAAoKExYCTAAcAgAKAAoKExYCTAAcAgAAAA==.Jetta:BAABNQAECn8WAAIbAAYK8xHnGAAuAQAbAAYK8xHnGAAuAQAAAA==.Jezzak:BAABNQAECn8mAAIGAAkK/hAOdwAhAgAGAAkK/hAOdwAhAgABNQAECgoKMAAGAMwWAA==.',
Jo='John:BAABNQAECn9eAAIjAAoKyCOVAAC3AwAjAAoKyCOVAAC3AwAAAA==.Jorien:BAABNQAECn8+AAIGAAoKbh7vMABxAgAGAAoKbh7vMABxAgAAAA==.',
Jp='Jp:BAAANQAECgYIDQAAAA==.Jpb:BAAANQAECgIIAgABNQAECgYIDQADAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgYIDQADAAAAAA==.',
Ju='Justadwarf:BAAANQAECgUICAAAAA==.Justatsuj:BAAANQAECgQIBQAAAA==.Juston:BAABNQAECn8cAAMIAAoKGg8APQDKAQAIAAkKGg8APQDKAQAHAAYKRAacywDQAAAAAA==.',
Ka='Kaboonsky:BAABNQAECn8ZAAMTAAkKHRqsWADEAQATAAkKHRqsWADEAQAUAAYKMg8OOQBdAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAABNQAECn8mAAIhAAgKSRWxDgB5AQAhAAgKSRWxDgB5AQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAADAAAAAA==.Karnadaz:BAABNQAECn8hAAILAAkKRhoNYwBlAgALAAkKRhoNYwBlAgAAAA==.Karnkarn:BAAANQAECgcIEAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgcIEQADAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIHAAcKRCPWMwCQAgAHAAcKRCPWMwCQAgAAAA==.',
Ko='Kolosho:BAAANQAECgcIBwAAAA==.Korxana:BAABNQAECn8mAAIWAAgKjxDzJQCwAQAWAAgKjxDzJQCwAQAAAA==.Korxon:BAABNQAECn8+AAITAAoK4xmyNgCNAgATAAoK4xmyNgCNAgAAAA==.Kotus:BAABNQAECn8gAAMlAAkK0A+wHwBTAQALAAkK9QcSjQBTAQAlAAYKfxWwHwBTAQAAAA==.',
Ks='Ksyusha:BAABNQAECn8eAAIJAAgK+wbY4wABAQAJAAgK+wbY4wABAQAAAA==.',
Ky='Kyfess:BAAANQAECgYIDQAAAA==.',
['Kä']='Kämi:BAAANQAECgEIAQABNQAECgcIGgAKAPsMAA==.',
La='Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgMIBAAAAA==.Lanuadra:BAABNQAECn8nAAIEAAkKpheaDwCCAgAEAAkKpheaDwCCAgAAAA==.Lawry:BAAANQAECggIEgAAAA==.Layhee:BAACNQAFFH8FAAIiAAQKAgL2EgCMAAAiAAQKAgL2EgCMAAA1AAQKfyAAAyYABwrlGbIgAIYBACYABwrmE7IgAIYBACIABQrNG5I5AEQBAAAA.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAADAAAAAA==.Lethalbimbo:BAAANQADCggIJAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQAECgEIAQAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFH8WAAIHAAcKTBf9CQCvAQAHAAcKTBf9CQCvAQA1AAQKf0AAAwcACgrAIQMsALICAAcACgrAIQMsALICAAgACgrVFroxAPsBAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgYIDgAAAA==.',
Lo='Lomea:BAAANQADCgYICgABNQAECgQIBwADAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQADCgcIDwAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECggIGQAQALYTAA==.',
['Lø']='Løllîe:BAABNQAECn8YAAIMAAcK5wk1FADOAAAMAAcK5wk1FADOAAAAAA==.',
Ma='Macarius:BAABNQAECn8kAAIOAAoK8RlyCQCpAgAOAAoK8RlyCQCpAgAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICgADAAAAAA==.Magatai:BAAANQAECgYIDAAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAwAAAA==.Malotan:BAAANQABCgEIAQABNQADCgUIBQADAAAAAA==.Manaster:BAABNQAECn8YAAMUAAcKjQ5nKwASAQAUAAcKjQ5nKwASAQATAAUKVBX1nQDrAAAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAABNQAECn8UAAIXAAYKGR7bKwCYAQAXAAYKGR7bKwCYAQAAAA==.Mathas:BAAANQAECgUIBwAAAA==.Mathius:BAAANQAECgEIAgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQAECgQIBAAAAA==.',
Mc='Mcbrynhammer:BAAANQAECgEIAwAAAA==.',
Me='Meanwhile:BAAANQADCgcIBQAAAA==.Meowmixx:BAAANQAECgEIAQAAAA==.Merkii:BAAANQADCgYIBgABNQAECgoKJAAeADkaAA==.',
Mi='Micflinigan:BAABNQAECn8nAAMhAAgKGxbICgAaAgAhAAgKGxbICgAaAgALAAQK+QwvGgGoAAAAAA==.Midnightmare:BAAANQAECgEIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAABNQAECn8YAAIUAAYKmArIOQC5AAAUAAYKmArIOQC5AAAAAA==.Ming:BAAANQADCgQIBAABNQAECgoKPQAOAK8gAA==.Minilove:BAAANQADCgUICgAAAA==.Mirix:BAAANQAECgcICgAAAA==.Misha:BAAANQAECgEIAQAAAA==.Mishelö:BAAANQAECgYIDgAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQICQAAAA==.Moonshae:BAABNQAECn86AAMOAAoK4hNWFwAHAgAOAAoK4hNWFwAHAgANAAcK6hP8OABMAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgMIBAAAAA==.',
Mu='Murciélago:BAAANQAECgQIBQAAAA==.Mustevistust:BAAANQADCgQIBAABNQAECgYIFAAXABkeAA==.',
My='Mystiquè:BAAANQADCggIJgAAAA==.',
['Mö']='Mö:BAAANQAECgEIAQAAAA==.',
Na='Nahmbra:BAAANQAECgcIEAAAAA==.Naithin:BAAANQAECgQIBQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQAECgEIAQAAAA==.Naviriel:BAAANQAECgYIBgABNQAECgoKGQANAEMLAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.Nethermoon:BAAANQABCgUIBQAAAA==.',
Ni='Nightray:BAAANQAECgQICgABNQAECgoKUQALABAgAA==.',
No='Nofoxgìven:BAAANQAECgIIAgAAAA==.Noknik:BAAANQABCggICAABNQADCgUIBQADAAAAAA==.Nonsocial:BAACNQAFFH8JAAIWAAcKGg2EAwDIAQAWAAcKGg2EAwDIAQA1AAQKfxgAAhYACQoTJFcEAHMDABYACQoTJFcEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgoKJgAZAHUjAA==.Noriisa:BAABNQAECn8wAAIGAAoKzBaxXABfAgAGAAoKzBaxXABfAgAAAA==.Notamathguy:BAAANQAECgEIAgAAAA==.Noudders:BAABNQAECn83AAIHAAoK0B5YDABSAwAHAAoK0B5YDABSAwAAAA==.',
Ny='Nyvak:BAAANQAECgUIDQAAAA==.',
Od='Odinhand:BAABNQAECn9EAAIYAAkKjwzTKwCMAQAYAAkKjwzTKwCMAQAAAA==.',
Oe='Oenei:BAAANQADCgMIAwAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCggIKwAAAA==.',
Oz='Ozwäld:BAABNQAECn8WAAIKAAcK5Q8/AAGNAQAKAAcK5Q8/AAGNAQABNQAECgoKPQABAK4gAA==.Ozwäldo:BAABNQAECn89AAIBAAoKriCQBgAcAwABAAoKriCQBgAcAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn9AAAMKAAoKuSHyEQD+AgAKAAoKuSHyEQD+AgAPAAIKVRLiMgBvAAAAAA==.Pandóra:BAAANQAECgIIAgAAAA==.Pariousa:BAABNQAECn8rAAMeAAoKaCPTDQAVAwAeAAoKzyLTDQAVAwAEAAQKBB0CbABFAQAAAA==.',
Pe='Peppermintxo:BAAANQAECgUICgABNQADCgIJAgADAAAAAA==.Peärl:BAAANQABCgIIAgAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgcIDgAAAA==.Phylinx:BAAANQADCgIIAgAAAA==.',
Pi='Pinkeepink:BAABNQAECn8cAAISAAcKfgQ7GACTAAASAAcKfgQ7GACTAAAAAA==.',
Po='Popacooldown:BAAANQAECgEIAwAAAA==.Potangwang:BAAANQAECgIIBAAAAA==.',
Pr='Praeforprocs:BAAANQADCgQIBAAAAA==.Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQAECgEIBAAAAA==.',
Pu='Puhk:BAAANQADCgcICQAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAABNQAECn8VAAIGAAcKVwuouAAlAQAGAAcKVwuouAAlAQAAAA==.Raijù:BAAANQAECgEIAgAAAA==.Rakith:BAAANQAECgQIBAAAAA==.Ralganor:BAABNQAECn9OAAIXAAoKtCI1CQDyAgAXAAoKtCI1CQDyAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECgcIDQAAAA==.Ravilan:BAAANQAECgMIBgAAAA==.Raynlight:BAABNQAECn8XAAMUAAgK4hTPPABEAQAUAAYK4Q3PPABEAQATAAcKSAYrmQD4AAAAAA==.',
Re='Remsx:BAAANQADCgEIAQAAAA==.Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQAECgEIAQAAAA==.Retaeytoob:BAAANQAFFAEIAQAAAA==.Rexx:BAAANQAECggIEAAAAA==.',
Ri='Rina:BAABNQAECn8UAAMmAAgK1BTJJwAGAgAmAAgKbxTJJwAGAgAnAAEKoQlZNAAqAAAAAA==.Rineli:BAAANQADCgcICgABNQAECgYIGAAUAJgKAA==.Ringadingg:BAABNQAECn8yAAMQAAoKcSIHCADsAgAQAAoKcSIHCADsAgACAAEKSCDfmgBdAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgcIDwAAAA==.',
Sa='Saladin:BAAANQAECgEIBAAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sanurá:BAAANQAECgMIBQAAAA==.Sarka:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Sasquatch:BAABNQAECn8eAAMHAAoKzA75SgDPAQAHAAoKzA75SgDPAQABAAUKiwfWJADQAAAAAA==.Satuno:BAAANQAECgEIAgABNQAECgkJJwAmACsUAA==.Saunkae:BAAANQAECgQICQAAAA==.',
Sc='Scony:BAAANQAECggIEAAAAA==.Scribs:BAAANQAECgYIDQAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQAECggIEAAAAA==.Seniko:BAAANQAECgMIBQAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8gAAMIAAkK3RtTfQCsAQAIAAYKZhpTfQCsAQAHAAYKig59kQDuAAABNQAECgoKGQAPAO8QAA==.Severalforms:BAABNQAECn8pAAMcAAkKgCAZCQChAgAcAAkKVSAZCQChAgAbAAIK0hdVMACPAAABNQAECgoKGQAPAO8QAA==.Severànce:BAABNQAECn8oAAQnAAkKmRgDDgDcAQAnAAgK8RUDDgDcAQAiAAUK1BRmTwBcAQAmAAQKvBGVTwDiAAABNQAECgoKGQAPAO8QAA==.Sevivify:BAAANQADCgIIAwABNQAECgoKGQAPAO8QAA==.',
Sh='Shablammy:BAABNQAECn8oAAMHAAkKuSONCQB0AwAHAAkKuSONCQB0AwAIAAEKAADTIQFOAAAAAA==.Shadowginni:BAAANQAECgIIAwAAAA==.Shadownome:BAAANQADCggIGAAAAA==.Shadowson:BAAANQAECgEIAQAAAA==.Shammygand:BAAANQADCgUIBQABNQAECgoKLQAWAMEZAA==.Shanker:BAAANQADCgMIAwAAAA==.Shavalyoth:BAAANQAECgUIBQAAAA==.Sheephappéns:BAABNQAECn8ZAAQPAAoK7xClDACxAQAPAAgKIxWlDACxAQAoAAQKUgbwBgCjAAAKAAYKLgI3NgFSAAAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn8+AAMTAAoKaRh+MACmAgATAAoKaRh+MACmAgAUAAIKGQNNYgAsAAAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECn9FAAIcAAoKJx41CgCLAgAcAAoKJx41CgCLAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skendr:BAAANQADCgEIAQABNQADCggIFgADAAAAAA==.Skydragon:BAAANQADCggIHwAAAA==.',
Sl='Slack:BAAANQADCgQIBAAAAA==.Slay:BAAANQAECgEIAQABNQAECgoKPgAXAOYbAA==.Slayful:BAAANQAECgEIAQAAAA==.Sleepydwarf:BAAANQAECgEIAQAAAA==.Slonk:BAAANQAECgQJBgAAAA==.',
So='Sofia:BAABNQAECn8dAAMUAAkKthutFQDvAQAUAAkKthutFQDvAQATAAEKrAj++AA7AAAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICgAAAA==.Spiritly:BAAANQAECgQIBQAAAA==.Sploof:BAABNQAECn8mAAIZAAoKdSNbBACiAwAZAAoKdSNbBACiAwAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgoKIQAJAFkUAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCggIKAAAAA==.Stealthful:BAAANQAECggIDgAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIICQAiAH8eAA==.Strayaus:BAAANQABCgMIAwAAAA==.Strongbad:BAAANQAECgQICwAAAA==.Stubly:BAAANQADCgUICQAAAA==.',
Su='Sunfyrie:BAABNQAECn8kAAITAAcKjheBZwCQAQATAAcKjheBZwCQAQAAAA==.',
Sw='Sweèt:BAAANQAECgIIBAAAAA==.Swifty:BAAANQAECggIAgABNQAECggIEAADAAAAAA==.Swiftyretpal:BAAANQAECggIEAAAAA==.',
Ta='Tagrit:BAAANQADCgUIBgAAAA==.Taldieth:BAABNQAECn8YAAIBAAcKcQIMJwC2AAABAAcKcQIMJwC2AAAAAA==.Tannas:BAAANQAECgMIAwAAAA==.Tarouhorn:BAAANQAECgMIAwAAAA==.Taurdk:BAAANQAECgYIDwAAAA==.Taylorshift:BAABNQAECn8sAAIYAAoKpB/7FwAIAwAYAAoKpB/7FwAIAwAAAA==.Tazranir:BAAANQADCggICwAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgoKPgAXAOYbAA==.Techduinn:BAAANQAECgMIAwAAAA==.Teetau:BAABNQAECn8vAAIcAAkKdAVbNQDeAAAcAAkKdAVbNQDeAAAAAA==.Texlandar:BAAANQADCgMIAwAAAA==.',
Th='Thadregosa:BAABNQAECn8lAAMgAAkKphKZCwCQAQAgAAkKphKZCwCQAQAfAAIKygUoNABMAAAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQAECgEIAQAAAA==.Thedarkskull:BAAANQAECgEIAQAAAA==.Therlisa:BAAANQAECgEIAQAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQAECgEIAQAAAA==.Timoleon:BAAANQAECgQIBQAAAA==.Tirna:BAAANQAECggIDgAAAA==.Tirnotham:BAABNQAECn8jAAMNAAkKdQ+PIACCAQANAAkKdQ+PIACCAQAOAAIK7QKEOwAxAAAAAA==.',
Tm='Tmtglizzy:BAABNQAECn83AAMHAAkKUR66IgCWAgAHAAkKUR66IgCWAgAIAAQKdxb/uAAgAQAAAA==.',
To='Tobi:BAABNQAECn9FAAMdAAoK3SVDBACxAwAdAAoK3SVDBACxAwAJAAUKMhiH+gApAQAAAA==.Tokalu:BAABNQAECn8ZAAINAAoKQwvPHwCJAQANAAoKQwvPHwCJAQAAAA==.Tonjudsonson:BAACNQAFFH8OAAIcAAUKBRKZAwAjAQAcAAUKBRKZAwAjAQA1AAQKf0AABBwACgpZIkkDAIYDABwACgpZIkkDAIYDABkACAoII9YJAB4DABsAAQoAAGpYAAAAAAAA.Torath:BAAANQADCgYICwABNQAECgEIAQADAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIHgAAAA==.',
Tw='Twiki:BAABNQAECn8uAAISAAcKDwbxEwCvAAASAAcKDwbxEwCvAAAAAA==.Twobricks:BAABNQAECn9FAAIZAAoKJxUlGgAhAgAZAAoKJxUlGgAhAgAAAA==.',
Ty='Tyrielas:BAAANQAECgEIAgAAAA==.Tyrssana:BAABNQAECn8fAAMmAAgKJAxNKABAAQAmAAgKJAxNKABAAQAnAAUKXAjtHACTAAABNQAFFAUICgAfAEcKAA==.',
['Tä']='Täuriel:BAAANQAECgMIAwABNQAECgoKPAAGANAPAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn8/AAIWAAoKzh+qCgB6AgAWAAoKzh+qCgB6AgABNQAECgYIBgADAAAAAA==.',
Ur='Urdeadtoo:BAABNQAECn8dAAMdAAgKahzOTwAsAgAdAAgKahzOTwAsAgAJAAYKPw6m/wAgAQAAAA==.Urlacher:BAAANQAECgQIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Valkyrastorm:BAAANQADCgYIBgAAAA==.Vaterunser:BAABNQAECn8hAAIJAAgKBgo20gAeAQAJAAgKBgo20gAeAQAAAA==.Vayikra:BAAANQADCgMIAwABNQAECgkJMQAIAJQOAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIIgAAAA==.Verlynna:BAAANQADCgIIAgAAAA==.Vertexx:BAAANQAECgEIAgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgkJHgASAIgSAA==.Vierth:BAAANQAECgQIBwAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQAECgEIAQAAAA==.Visea:BAAANQADCgIIAwABNQAECgQIBwADAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIHwAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECggILgAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBQAAAA==.',
['Vå']='Våder:BAAANQAECgIIAgAAAA==.',
Wa='Warkistla:BAAANQADCggICAABNQAECgoKGQANAEMLAA==.',
We='Weemer:BAAANQADCgcIFAAAAA==.Wesleypipes:BAABNQAECn8cAAIHAAkKMRQUcwCyAQAHAAkKMRQUcwCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAABNQAECn8cAAIKAAgKuxPnkwBrAQAKAAgKuxPnkwBrAQAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpally:BAACNQAFFH8HAAIdAAMKdw3SFQDRAAAdAAMKdw3SFQDRAAA1AAQKfzMAAh0ACgqbF4k3AIYCAB0ACgqbF4k3AIYCAAAA.Wolfmato:BAABNQAECn8xAAIHAAoK8R25JwDFAgAHAAoK8R25JwDFAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAABNQAECn8lAAIWAAgKhxLYJAAzAQAWAAgKhxLYJAAzAQAAAA==.',
Xe='Xeros:BAAANQADCggICAAAAA==.Xerxeis:BAAANQABCgYICAABNQAECgcIBwADAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgoKKwAeAGgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAcIFgAHAEwXAA==.',
Ys='Yssuplef:BAABNQAECn8hAAQSAAkKOgysDADlAAAaAAcKqgo7mgAPAQASAAgKRgqsDADlAAARAAMKqgh+HACbAAAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.Yunjin:BAAANQADCgMIAwAAAA==.',
Za='Zaiyra:BAAANQAECgUIBgAAAA==.Zakoor:BAAANQADCgcIGwAAAA==.Zambreth:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgcIHQAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zaurra:BAAANQAECgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIIAAAAA==.Zekia:BAABNQAECn80AAIGAAkKlBkcVwBtAgAGAAkKlBkcVwBtAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergdemon:BAAANQAECgEIAQAAAA==.Zergul:BAAANQAECgEIAQAAAA==.Zerm:BAABNQAECn81AAIJAAoKoBfmWQARAgAJAAoKoBfmWQARAgAAAA==.Zermonk:BAAANQAECgEIAgAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAABNQAECn8WAAIHAAgKYQs/gwAUAQAHAAgKYQs/gwAUAQAAAA==.',
Zo='Zorsa:BAABNQAECn8YAAIaAAYKOgZzwwC3AAAaAAYKOgZzwwC3AAAAAA==.',
Zu='Zuljawn:BAABNQAECn8vAAIFAAkKvgwyHQB5AQAFAAkKvgwyHQB5AQAAAA==.',
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
