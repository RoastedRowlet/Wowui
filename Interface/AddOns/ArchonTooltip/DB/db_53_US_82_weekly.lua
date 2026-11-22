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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Priest-Shadow','Evoker-Augmentation','Paladin-Protection','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Druid-Feral','Druid-Guardian','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Priest-Discipline','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIEgAAAA==.',
Ae='Aegennai:BAABNQAECn8+AAIBAAkKcwawGwBfAQABAAkKcwawGwBfAQAAAA==.Aegondk:BAABNQAFFH8GAAICAAMK0xlqDgD0AAACAAMK0xlqDgD0AAAAAA==.Aeli:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.Aelias:BAAANQAECgYIDQAAAA==.Aevaela:BAABNQAECn8wAAIEAAkKjhveEABxAgAEAAkKjhveEABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn84AAMFAAoK3hMfGADMAQAFAAoKPBEfGADMAQAGAAUKhhQq9wDDAAAAAA==.',
Ak='Akey:BAAANQAECgcIJQAAAQ==.Akhae:BAABNQAECn8tAAMHAAkKKBdkYwDjAQAHAAkKKBdkYwDjAQAIAAEKtwHeUQElAAAAAA==.',
Al='Albinism:BAABNQAECn8VAAIBAAYKhwh+IQAUAQABAAYKhwh+IQAUAQAAAA==.Alcadeias:BAAANQAECgYIDQAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amehnet:BAAANQAECgEIAQAAAA==.Amuria:BAAANQAECgQIBwAAAA==.',
An='Anaeda:BAABNQAECn8cAAIJAAgKrwxtvACkAQAJAAgKrwxtvACkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgYIEQADAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIFwAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIFwAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAABNQAECn8XAAIKAAcKZBWK2ADWAQAKAAcKZBWK2ADWAQAAAA==.Argalnor:BAAANQADCgMIAwAAAA==.Arthar:BAABNQAECn9RAAILAAoKECD1OQDeAgALAAoKECD1OQDeAgAAAA==.',
As='Ashvyth:BAABNQAECn8yAAQMAAoKfxyABQBHAgAMAAkK6h6ABQBHAgANAAIKWQYcOgBHAAAOAAEKkwsrXQA2AAAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAPAOUbAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.Azurelive:BAAANQABCgYIBgAAAA==.',
Ba='Babalou:BAAANQADCgcIAwAAAA==.Baconpancake:BAAANQAECgQICQAAAA==.Baldpunch:BAAANQAECgEIAQAAAA==.Balinor:BAAANQAECgYIEAAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgUIEAAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgUIEAADAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAABNQAECn8ZAAIQAAgKthNZWgCmAQAQAAgKthNZWgCmAQAAAA==.Beaj:BAABNQAECn8ZAAMRAAcKagkkEwAEAQARAAcKCgkkEwAEAQASAAMKFgn1UACMAAAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8tAAMTAAkKPiDvHADzAgATAAkKPiDvHADzAgAUAAQKrA6YQwCfAAAAAA==.Bigblingaxe:BAAANQADCggICgAAAA==.Bilac:BAAANQADCgEIAQABNQAFFAIIBQAVAEoBAA==.',
Bl='Blacksabbth:BAAANQABCgIIAgAAAA==.Blusoleil:BAABNQAECn8YAAMWAAcKNRETRADiAAAWAAcKNRETRADiAAAJAAUK3QfjRAGJAAAAAA==.Blux:BAAANQAECgYIBQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECn8/AAQCAAoKDyA1IgA+AgACAAoKixw1IgA+AgAXAAcK9Bj4MQCEAQAQAAgKxR1UMQBjAQAAAA==.',
Br='Branches:BAABNQAECn85AAMYAAoKXg+QKgCrAQAYAAoKXg+QKgCrAQAZAAcKpw1uNwBhAQAAAA==.Branden:BAAANQADCgcIBwABNQADCggIFwADAAAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAABNQAECn8VAAIGAAgKKQc8xwBzAQAGAAgKKQc8xwBzAQAAAA==.Briggsey:BAABNQAECn8tAAIaAAkK6gkRgwBaAQAaAAkK6gkRgwBaAQAAAA==.Briznot:BAABNQAECn8eAAMSAAkKiBIrFgCrAAAaAAcKwhD0lgArAQASAAMKjBMrFgCrAAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBgAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCggIFgAAAA==.',
Bu='Bubbadubya:BAAANQADCggIKwAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQAECgUICwABNQAFFAIIBQAVAEoBAA==.Burningwolf:BAABNQAECn8oAAIHAAoKCyCtFgABAwAHAAoKCyCtFgABAwAAAA==.',
['Bó']='Bórs:BAAANQAECgQIDAAAAA==.',
Ca='Caiden:BAAANQAECgUIBwAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCggIJgAAAA==.Calesona:BAAANQAECgQIBwAAAA==.Carnìfex:BAAANQAECgYIEwAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAABNQAECn8jAAQbAAoKIiDHBADXAgAbAAoKIiDHBADXAgAcAAgKwxrIGQC4AQAYAAEKrRA2sgAyAAAAAA==.',
Ce='Cellene:BAAANQAECgYIBgABNQAECgoKPAAIAJ4ZAA==.Cerà:BAABNQAECn8iAAIZAAgKChZWHgAOAgAZAAgKChZWHgAOAgAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgcIDgAAAA==.',
Ci='Cinnawhiskey:BAAANQADCgUIBQAAAA==.',
Cl='Cleetus:BAAANQAECggIDgAAAA==.Clizee:BAABNQAECn8eAAIKAAkKXgf4sQBBAQAKAAkKXgf4sQBBAQAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAABNQAECn8jAAQYAAoKYRAJTwCjAQAYAAoKYRAJTwCjAQAcAAUK6A5XQAC5AAAZAAMKXgsCXQCEAAAAAA==.Cloudkeg:BAAANQADCgYIDAABNQADCggIFwADAAAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Coldtex:BAAANQAECggIAwAAAA==.Constellate:BAAANQAECgYIEwAAAA==.Cotterpins:BAABNQAECn8hAAIJAAoKWRTFZQAGAgAJAAoKWRTFZQAGAgAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.Crunchyjim:BAAANQAECgMIBAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.Cyndlia:BAAANQADCgUIBQAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECn88AAMIAAoKnhn+MQCyAgAIAAoKnhn+MQCyAgAHAAQK1wu68gCFAAAAAA==.',
Da='Damitsu:BAAANQAECgEIAQABNQAECggIIwAEAJUQAA==.Damnitsu:BAABNQAECn8jAAMEAAgKlRBxKACBAQAEAAcKORBxKACBAQAdAAYK3AtBZwAVAQAAAA==.Darckside:BAAANQAECgcICQAAAA==.Dazen:BAAANQADCggIGAAAAA==.',
De='Deadflexy:BAABNQAECn8fAAIXAAoKWRnzHAAVAgAXAAoKWRnzHAAVAgAAAA==.Deathberry:BAABNQAECn8jAAIaAAgKPRuXUABjAgAaAAgKPRuXUABjAgAAAA==.Deathdoodles:BAABNQAECn8XAAMQAAcK6g5SSwDYAAAQAAcKog5SSwDYAAACAAIKEQoolwBmAAABNQAECgoKPgATAGkYAA==.Deathriaa:BAAANQADCgEIAQABNQAECggIAwADAAAAAA==.Deathsveil:BAAANQADCgcIBwAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgYIDgAAAA==.Dejavù:BAABNQAECn8VAAIJAAkKNg8KhwC+AQAJAAkKNg8KhwC+AQAAAA==.Demonblood:BAABNQAECn8gAAMXAAoKdRE6TgC9AQAXAAkKsBI6TgC9AQAQAAEK2gjEiQA0AAAAAA==.Demonicmac:BAAANQADCgMIAwABNQAECgQICAADAAAAAA==.Deräth:BAABNQAECn8bAAIUAAgKfQdFOwBPAQAUAAgKfQdFOwBPAQAAAA==.Devlik:BAAANQAECgMIAQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgADAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Dh='Dhdawg:BAAANQAECgIIAQAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIFgAAAA==.Dionne:BAAANQAECgcIDQAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgoKQAAKALkhAA==.Ditsie:BAAANQAECgEIAQAAAA==.',
Dm='Dmega:BAABNQAECn80AAIGAAkKrwumgwCyAQAGAAkKrwumgwCyAQAAAA==.',
Do='Dobby:BAAANQAECgYIBgABNQAECggIGAAGAC4LAA==.Dodgeramthis:BAAANQADCgIIAgAAAA==.Dogfunk:BAAANQABCgcICgAAAA==.Doomalay:BAAANQAECgUIBQAAAA==.Dorne:BAAANQADCgIIAgAAAA==.',
Dr='Dragea:BAABNQAECn8bAAMeAAcK1hcPGABzAQAeAAYKcxkPGABzAQAfAAIK3wtiHQB3AAAAAA==.Dragondude:BAABNQAECn8oAAQeAAoKwxk8FABrAgAeAAoKwxk8FABrAgAfAAYKVQy+EgAMAQAVAAIKhQt2GABlAAAAAA==.Dragonsgrasp:BAAANQADCgUICAAAAA==.Drakoswrath:BAACNQAFFH8SAAIXAAcKwRO5DQB4AQAXAAcKwRO5DQB4AQA1AAQKfzoAAhcACgrCJM4HAAsDABcACgrCJM4HAAsDAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAABNQAECn8eAAILAAgKtxypWQDxAQALAAgKtxypWQDxAQAAAA==.',
Dy='Dyelin:BAABNQAECn8zAAIaAAoKJRqeLABcAgAaAAoKJRqeLABcAgAAAA==.',
['Dõ']='Dõtdropnroll:BAAANQAECgMIAgAAAA==.',
Ed='Eddyshadess:BAAANQABCgcICQAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQAECgIIAwABNQAECgQIBwADAAAAAA==.Elyron:BAABNQAECn81AAIKAAoKmBbvUQAbAgAKAAoKmBbvUQAbAgAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn9AAAMKAAoKpB+cLwCCAgAKAAoKrB6cLwCCAgAPAAcKOR09CwAQAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgUIBwAAAA==.',
Eu='Euandros:BAABNQAECn8bAAIJAAkKrAlUuABhAQAJAAkKrAlUuABhAQAAAA==.',
Ev='Evï:BAAANQAECgEIAQAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCggIJgADAAAAAA==.Ezind:BAAANQAECgYIDwAAAA==.',
Fa='Fakename:BAAANQAECggIDAAAAA==.Fakesaint:BAABNQAECn9AAAIHAAoKgCR/FQAjAwAHAAoKgCR/FQAjAwAAAA==.Fangstorm:BAABNQAECn8vAAIbAAkKEBNnEgCiAQAbAAkKEBNnEgCiAQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgYIEQAAAA==.',
Fe='Felbane:BAAANQAECgEIAQABNQAECgoKRgAaAEUiAA==.Feldruid:BAAANQAECgQIDAAAAA==.Felup:BAABNQAECn9GAAQaAAoKRSIuHwAHAwAaAAoKRSIuHwAHAwASAAIK+xEqVgB8AAARAAEK5BvQKgBCAAAAAA==.',
Fl='Fluster:BAAANQAECgUIBQAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAABNQAECn9FAAMgAAoKnhvMHgDHAgAgAAoKnhvMHgDHAgAJAAEKDAJayQEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8wAAIhAAoKvg9VDgCcAQAhAAoKvg9VDgCcAQAAAA==.Fusepins:BAAANQADCgcIAwAAAA==.Fuzzwig:BAAANQADCgcIDQAAAA==.',
Ga='Gaska:BAAANQAECgYICwABNQAECgUIDAADAAAAAA==.',
Gh='Ghösty:BAAANQADCgMIAwABNQAECggIAwADAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgcIBQABNQAECgkJHQAUALYbAA==.',
Gr='Gracela:BAAANQADCgEIAQAAAA==.Graxus:BAAANQAECgYIDQAAAA==.Greth:BAAANQADCggILAAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.Grumpy:BAAANQADCgcIAwABNQAECgoKHwAXAFkZAA==.',
Gu='Gudge:BAACNQAFFH8FAAIVAAIKSgFACwBWAAAVAAIKSgFACwBWAAA1AAQKfz8AAxUACgqpETIIABgCABUACgqpETIIABgCAB4AAwruAaY8AC4AAAAA.Gummypenguin:BAABNQAECn8qAAIGAAoK4SKGGgDZAgAGAAoK4SKGGgDZAgABNQAFFAUIFwAGAGckAA==.',
Ha='Hadhox:BAAANQAECgMIBAABNQAECgoKQgAGADcQAA==.Halforcked:BAAANQADCgYICQAAAA==.Hathdox:BAABNQAECn9CAAIGAAoKNxD1XgAKAgAGAAoKNxD1XgAKAgAAAA==.Hawkulees:BAAANQADCggIJQAAAA==.Hazelnoot:BAABNQAECn9EAAMJAAoKMSQGEACKAwAJAAoKMSQGEACKAwAgAAMKUgr5zQB5AAAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgUICAAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8oAAIiAAgKCQ2VQQAwAQAiAAgKCQ2VQQAwAQAAAA==.',
Hi='Hitsuryu:BAABNQAECn8sAAIVAAgK2gJ/EwCoAAAVAAgK2gJ/EwCoAAAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8fAAMdAAoKYQyyPgDTAQAdAAkKYQyyPgDTAQAjAAYK3gTmEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECggICwAAAA==.Holynoot:BAAANQAECgQIBAABNQAECgoKRAAJADEkAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgADAAAAAA==.Hornsharp:BAAANQAECgYIDQAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAFFAIIBQAVAEoBAA==.Hunilla:BAABNQAECn8bAAQUAAYKLgxRPABIAQAUAAYKLgxRPABIAQATAAUK+gZxvADkAAAkAAEK6gGiHwAcAAABNQAFFAIIBQAVAEoBAA==.Huuken:BAAANQADCgUIBQAAAA==.',
Ia='Iamu:BAAANQADCgYIGQAAAA==.',
Ib='Ibris:BAAANQADCggIGAAAAA==.',
Ic='Iconius:BAAANQADCggIGAAAAA==.',
Ie='Ieatwetsocks:BAACNQAFFH8KAAIHAAQKmw8CFgAHAQAHAAQKmw8CFgAHAQA1AAQKfyQAAwcACgo4FctXAAoCAAcACgo4FctXAAoCAAgAAgpbBO0hAU0AAAAA.',
Ig='Ignivar:BAAANQADCggIFgAAAA==.',
In='Indra:BAAANQAECgYIDAAAAA==.Innexshaman:BAABNQAECn8rAAIIAAoKSRl/MQASAgAIAAoKSRl/MQASAgAAAA==.Insaint:BAACNQAFFH8SAAIJAAUKpwwyGQDHAAAJAAUKpwwyGQDHAAA1AAQKf00AAgkACgrHG4syAJgCAAkACgrHG4syAJgCAAAA.',
Ir='Ironfield:BAABNQAECn8gAAMHAAoKNhf7RgD3AQAHAAoKNhf7RgD3AQAIAAMKFQNFCgF3AAABNQADCgUIBQADAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAABNQAECn8dAAIUAAYKNwbuSwDmAAAUAAYKNwbuSwDmAAAAAA==.',
Je='Jessamine:BAABNQAECn9PAAIKAAoKExYQUgAbAgAKAAoKExYQUgAbAgAAAA==.Jetta:BAABNQAECn8WAAIbAAYK8xEJHAAsAQAbAAYK8xEJHAAsAQAAAA==.Jezzak:BAABNQAECn8sAAIGAAoK4BAOdwAhAgAGAAoK4BAOdwAhAgABNQAECgoKMAAGAMwWAA==.',
Jo='John:BAABNQAECn9hAAIjAAoKuSSVAAC3AwAjAAoKuSSVAAC3AwAAAA==.Jorien:BAABNQAECn8+AAIGAAoKbh6SNwBtAgAGAAoKbh6SNwBtAgAAAA==.',
Jp='Jp:BAAANQAECgYICwAAAA==.Jpb:BAAANQAECgIIAgABNQAECgYICwADAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgYICwADAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgYICwADAAAAAA==.',
Ju='Justadwarf:BAAANQAECgUIBgAAAA==.Justatsuj:BAAANQAECgQIBAAAAA==.Juston:BAABNQAECn8cAAMIAAoKGg/zQgDIAQAIAAkKGg/zQgDIAQAHAAYKRAacywDQAAAAAA==.',
Ka='Kaboonsky:BAABNQAECn8ZAAMTAAkKHRoyYQC9AQATAAkKHRoyYQC9AQAUAAYKMg8OOQBdAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAABNQAECn8sAAIhAAgKTBXKDwB/AQAhAAgKTBXKDwB/AQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAADAAAAAA==.Karnadaz:BAABNQAECn8hAAILAAkKRhoNYwBlAgALAAkKRhoNYwBlAgAAAA==.Karnkarn:BAAANQAECgcIDAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIHAAcKRCPWMwCQAgAHAAcKRCPWMwCQAgAAAA==.Killuminatix:BAAANQAECgEIAQAAAA==.',
Ko='Kolosho:BAAANQAECgcIBwAAAA==.Korxana:BAABNQAECn8mAAIWAAgKjxDzJQCwAQAWAAgKjxDzJQCwAQAAAA==.Korxon:BAABNQAECn8+AAITAAoK4xmyNgCNAgATAAoK4xmyNgCNAgAAAA==.Kotus:BAABNQAECn8gAAMlAAkK0A+wHwBTAQAlAAYKfxWwHwBTAQALAAkK9QcHlwBSAQAAAA==.',
Kr='Krastikon:BAAANQAECgUIBQAAAA==.',
Ks='Ksyusha:BAABNQAECn8lAAIJAAgKiQd+6wALAQAJAAgKiQd+6wALAQAAAA==.',
Ky='Kyfess:BAAANQAECgcIDAAAAA==.',
['Kä']='Kämi:BAAANQAECgEIAQABNQAECgcIGgAKAPsMAA==.',
La='Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgMIBAAAAA==.Lanuadra:BAABNQAECn8nAAIEAAkKpheaDwCCAgAEAAkKpheaDwCCAgAAAA==.Lawry:BAABNQAECn8bAAMgAAkKdRCliACCAQAgAAkKdRCliACCAQAJAAcKUgzgzAA9AQAAAA==.Layhee:BAACNQAFFH8FAAIiAAQKAgK1FQCIAAAiAAQKAgK1FQCIAAA1AAQKfyAAAyYABwrlGYQjAIEBACYABwrmE4QjAIEBACIABQrNGy8+AEMBAAAA.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAADAAAAAA==.Lethalbimbo:BAAANQADCggILAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFH8WAAIHAAcKTBf9CQCvAQAHAAcKTBf9CQCvAQA1AAQKf0AAAwcACgrAIQMsALICAAcACgrAIQMsALICAAgACgrVFi43APgBAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgYIDgAAAA==.',
Lo='Lomea:BAAANQADCgYICgABNQAECgQIBwADAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQADCgcIDwAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECggIGQAQALYTAA==.',
['Lø']='Løllîe:BAABNQAECn8fAAIMAAgKAgonEgAEAQAMAAgKAgonEgAEAQAAAA==.',
Ma='Macarius:BAABNQAECn8kAAINAAoK8RlHCgCmAgANAAoK8RlHCgCmAgAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAADAAAAAA==.Magatai:BAAANQAECgYICwAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQADCgUIBQADAAAAAA==.Manaster:BAABNQAECn8ZAAMUAAcKjQ5JLgAVAQAUAAcKjQ5JLgAVAQATAAUKVBVkqADlAAAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAABNQAECn8UAAIXAAYKGR43LwCTAQAXAAYKGR43LwCTAQAAAA==.Mathas:BAAANQAECgUIBgAAAA==.Mathius:BAAANQAECgQIBQAAAA==.Matile:BAAANQAECgEIAQAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQAECgQIAwAAAA==.',
Mc='Mcbrynhammer:BAAANQAECgIIAQAAAA==.',
Me='Meanwhile:BAAANQADCgcIBQAAAA==.Meowmixx:BAAANQADCgQIBAAAAA==.Merkii:BAAANQADCgYIBgABNQAECgoKJAAdADkaAA==.',
Mi='Micflinigan:BAABNQAECn8pAAMhAAkK7BXICgAaAgAhAAkK7BXICgAaAgALAAUKkgsvGgGoAAAAAA==.Midnightmare:BAAANQABCgMIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAABNQAECn8cAAIUAAYK0QqqPAC/AAAUAAYK0QqqPAC/AAAAAA==.Ming:BAAANQADCgQIBAABNQAECgoKPQANAK8gAA==.Minilove:BAAANQADCgUICgAAAA==.Mirix:BAAANQAECgcICgAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgYIDgAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQICQAAAA==.Moofosa:BAAANQABCgQIBgABNQAECgkJFQAJADYPAA==.Moonshae:BAABNQAECn86AAMNAAoK4hNWFwAHAgANAAoK4hNWFwAHAgAOAAcK6hP8OABMAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgMIAgAAAA==.',
Mu='Murciélago:BAAANQAECgQIBQAAAA==.Mustevistust:BAAANQADCgQIBAABNQAECgYIFAAXABkeAA==.',
My='Mystiquè:BAAANQADCggIJgAAAA==.',
Na='Nahmbra:BAAANQAECgcIDwAAAA==.Naithin:BAAANQAECgQIBQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQABCgQIBAAAAA==.Naviriel:BAAANQAECgYIBgABNQAECgoKGQAOAEMLAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.Nethermoon:BAAANQABCgUIBQAAAA==.',
Ni='Nightray:BAAANQAECgQICAABNQAECgoKUQALABAgAA==.',
No='Nofoxgìven:BAAANQAECgIIAgAAAA==.Noknik:BAAANQABCggICAABNQADCgUIBQADAAAAAA==.Nonsocial:BAACNQAFFH8JAAIWAAcKGg2EAwDIAQAWAAcKGg2EAwDIAQA1AAQKfxkAAhYACQoTJFcEAHMDABYACQoTJFcEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgoKLQAZAJQjAA==.Noriisa:BAABNQAECn8wAAIGAAoKzBaxXABfAgAGAAoKzBaxXABfAgAAAA==.Noudders:BAABNQAECn83AAIHAAoK0B5BDgBMAwAHAAoK0B5BDgBMAwAAAA==.',
Ny='Nyvak:BAAANQAECgUIDAAAAA==.',
Od='Odinhand:BAABNQAECn9EAAIYAAkKjwxMLwCLAQAYAAkKjwxMLwCLAQAAAA==.',
Oe='Oenei:BAAANQADCgMIAwAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCggIKwAAAA==.',
Oz='Ozwäld:BAABNQAECn8WAAIKAAcK5Q8/AAGNAQAKAAcK5Q8/AAGNAQABNQAECgoKPQABAK4gAA==.Ozwäldo:BAABNQAECn89AAIBAAoKriCQBgAcAwABAAoKriCQBgAcAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn9AAAMKAAoKuSHTFAD2AgAKAAoKuSHTFAD2AgAPAAIKVRLiMgBvAAAAAA==.Pandóra:BAAANQAECgIIAQAAAA==.Pariousa:BAABNQAECn8rAAMdAAoKaCPTDQAVAwAdAAoKzyLTDQAVAwAEAAQKBB31dgBEAQAAAA==.',
Pe='Peppermintxo:BAAANQAECgYIEAABNQADCgIJAgADAAAAAA==.Peärl:BAAANQABCgIIAgAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgYIEgAAAA==.Phylinx:BAAANQADCgIIAgAAAA==.',
Pi='Pinkeepink:BAABNQAECn8iAAISAAcKhwTRGQCUAAASAAcKhwTRGQCUAAAAAA==.',
Po='Popacooldown:BAAANQAECgEIAwAAAA==.Potangwang:BAAANQAECgIIBAAAAA==.',
Pr='Praeforprocs:BAAANQAECgMIAwAAAA==.Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgYICgAAAA==.',
Pu='Puhk:BAAANQADCgcICQAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAABNQAECn8VAAIGAAcKVwsByAByAQAGAAcKVwsByAByAQAAAA==.Raijù:BAAANQAECgEIAQAAAA==.Rakith:BAAANQAECgQIBAAAAA==.Ralganor:BAABNQAECn9OAAIXAAoKtCI1CgDsAgAXAAoKtCI1CgDsAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECggIDAAAAA==.Ravenswings:BAAANQABCgMIAwAAAA==.Ravilan:BAAANQAECgMIBQAAAA==.Raynlight:BAABNQAECn8XAAMUAAgK4hTPPABEAQAUAAYK4Q3PPABEAQATAAcKSAatowDyAAAAAA==.Razashara:BAAANQAECgQIAwAAAA==.',
Re='Remsx:BAAANQADCgEIAQAAAA==.Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.Retaeytoob:BAAANQAFFAEIAQAAAA==.Rexx:BAAANQAECggIEwAAAA==.',
Ri='Rina:BAABNQAECn8UAAMmAAgK1BTJJwAGAgAmAAgKbxTJJwAGAgAnAAEKoQlZNAAqAAAAAA==.Rineli:BAAANQADCgcICgABNQAECgYIHAAUANEKAA==.Ringadingg:BAABNQAECn8yAAMQAAoKcSIGCQDlAgAQAAoKcSIGCQDlAgACAAEKSCDfmgBdAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgcIDgAAAA==.',
Sa='Sankatlantis:BAAANQADCgYICgAAAA==.Sanurá:BAAANQAECgMIAwAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAABNQAECn8fAAMHAAoKRA/zUADPAQAHAAoKRA/zUADPAQABAAUKiwdTJwDOAAAAAA==.Satuno:BAAANQAECgEIAgABNQAECgoKKAAmAKITAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECggIDgAAAA==.Scribs:BAAANQAECgYICwAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQAECggIEAAAAA==.Seniko:BAAANQAECgMIBQAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8gAAMIAAkK3RtTfQCsAQAIAAYKZhpTfQCsAQAHAAYKig6vmQDuAAABNQAECgoKHAAPAOkRAA==.Severalforms:BAABNQAECn8pAAMcAAkKgCAvCgCbAgAcAAkKVSAvCgCbAgAbAAIK0hdVMACPAAABNQAECgoKHAAPAOkRAA==.Severànce:BAABNQAECn8oAAQnAAkKmRgDDgDcAQAnAAgK8RUDDgDcAQAiAAUK1BRmTwBcAQAmAAQKvBGVTwDiAAABNQAECgoKHAAPAOkRAA==.Sevivify:BAAANQADCgIIAwABNQAECgoKHAAPAOkRAA==.',
Sh='Shablammy:BAABNQAECn8vAAMHAAkK+iM2CQCGAwAHAAkK+iM2CQCGAwAIAAEKAADTIQFOAAAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCggIGAAAAA==.Shadowson:BAAANQABCgEIAQAAAA==.Shammygand:BAAANQADCgUIBQABNQAECgoKLwAWAMEZAA==.Shanker:BAAANQADCgMIAwAAAA==.Shavalyoth:BAAANQAECgUIBgAAAA==.Sheephappéns:BAABNQAECn8cAAQPAAoK6RGMDQC/AQAPAAgKcRaMDQC/AQAoAAQKUgbHBwCjAAAKAAYKLgKSPwFSAAAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn8+AAMTAAoKaRh+MACmAgATAAoKaRh+MACmAgAUAAIKGQNUaAAsAAAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECn9OAAIcAAoK1x6FCAC8AgAcAAoK1x6FCAC8AgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skendr:BAAANQADCgEIAQABNQADCggIFgADAAAAAA==.Skydragon:BAAANQADCggIHwAAAA==.',
Sl='Slack:BAAANQADCgQIBAAAAA==.Slay:BAAANQAECgEIAQABNQAECgoKPgAXAOYbAA==.Sleepydwarf:BAAANQADCggICAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAABNQAECn8dAAMUAAkKthtWFwDwAQAUAAkKthtWFwDwAQATAAEKrAj++AA7AAAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICgAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAABNQAECn8tAAIZAAoKlCO6BACnAwAZAAoKlCO6BACnAwAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgoKIQAJAFkUAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCggIKAAAAA==.Stealthful:BAAANQAECggIDgAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIICQAiAH8eAA==.Stonefist:BAAANQADCgMIAwAAAA==.Strayaus:BAAANQABCgMIAwAAAA==.Strongbad:BAAANQAECgQICAAAAA==.Stubly:BAAANQADCgUICQAAAA==.',
Su='Sunfyrie:BAABNQAECn8kAAITAAcKjhc0cACLAQATAAcKjhc0cACLAQAAAA==.',
Sw='Sweèt:BAAANQAECgIIAgAAAA==.Swifty:BAAANQAECggIAgABNQAECggIEAADAAAAAA==.Swiftyretpal:BAAANQAECggIEAAAAA==.',
Ta='Tagrit:BAAANQADCgUIBgAAAA==.Taldieth:BAABNQAECn8ZAAIBAAcKcQLMKAC+AAABAAcKcQLMKAC+AAAAAA==.Tannas:BAAANQAECgMIAwAAAA==.Tarouhorn:BAAANQAECgMIAwAAAA==.Taurdk:BAAANQAECgYIDQAAAA==.Taylorshift:BAABNQAECn8sAAIYAAoKpB/7FwAIAwAYAAoKpB/7FwAIAwAAAA==.Tazranir:BAAANQADCggICwAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgoKPgAXAOYbAA==.Techduinn:BAAANQAECgMIAwAAAA==.Teetau:BAABNQAECn8vAAIcAAkKdAWKOQDdAAAcAAkKdAWKOQDdAAAAAA==.Texlandar:BAAANQADCgMIAwAAAA==.',
Th='Thadregosa:BAABNQAECn8lAAMfAAkKphJdDACPAQAfAAkKphJdDACPAQAeAAIKygXXNgBMAAAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCggIFwAAAA==.Thedarkskull:BAAANQABCgIIAgAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCggIRwAAAA==.Timoleon:BAAANQAECgQIAwAAAA==.Tirna:BAAANQAECggIDQAAAA==.Tirnotham:BAABNQAECn8qAAMOAAkK5Q9iIACbAQAOAAkK5Q9iIACbAQANAAIK7QKYPgAwAAAAAA==.',
Tm='Tmtglizzy:BAABNQAECn83AAMHAAkKUR5WJwCPAgAHAAkKUR5WJwCPAgAIAAQKdxb/uAAgAQAAAA==.',
To='Tobi:BAABNQAECn9FAAMgAAoK3SVDBACxAwAgAAoK3SVDBACxAwAJAAUKMhiH+gApAQAAAA==.Tokalu:BAABNQAECn8ZAAIOAAoKQwtlIgCJAQAOAAoKQwtlIgCJAQAAAA==.Tonjudsonson:BAACNQAFFH8OAAIcAAUKBRKZAwAjAQAcAAUKBRKZAwAjAQA1AAQKf0AABBwACgpZIkkDAIYDABwACgpZIkkDAIYDABkACAoIIyMLABoDABsAAQoAACtfAAAAAAAA.Torath:BAAANQADCgYICwABNQADCggIFwADAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIJAAAAA==.',
Tw='Twiki:BAABNQAECn8uAAISAAcKDwbEFQCuAAASAAcKDwbEFQCuAAAAAA==.Twobricks:BAABNQAECn9GAAIZAAoKJxX4HAAdAgAZAAoKJxX4HAAdAgAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAABNQAECn8hAAMmAAgKJAznKgBAAQAmAAgKJAznKgBAAQAnAAUKXAgzHwCTAAABNQAFFAYIDAAeABsLAA==.',
['Tä']='Täuriel:BAAANQAECgQIAwABNQAECgoKQgAGADcQAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn9AAAIWAAoKzh/mCwB1AgAWAAoKzh/mCwB1AgABNQAECgYIBwADAAAAAA==.',
Ur='Urdeadtoo:BAABNQAECn8eAAMgAAgKnBzOTwAsAgAgAAgKnBzOTwAsAgAJAAYKPw6m/wAgAQAAAA==.Urlacher:BAAANQAECgQIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaererelor:BAAANQAECgUIBQAAAA==.Valkyrastorm:BAAANQADCgYIDAAAAA==.Vaterunser:BAABNQAECn8oAAIJAAgKUgrg1wAqAQAJAAgKUgrg1wAqAQAAAA==.Vayikra:BAAANQADCgMIAwABNQAECgoKOQAIAFEOAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIKAAAAA==.Verlynna:BAAANQADCgIIAgAAAA==.Vertexx:BAAANQAECgEIAgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgkJHgASAIgSAA==.Vierth:BAAANQAECgQIBwAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQAECgEIAQAAAA==.Visea:BAAANQADCgIIAwABNQAECgQIBwADAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIJQAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECggIKwAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
['Vå']='Våder:BAAANQAECgIIAgAAAA==.',
Wa='Warkistla:BAAANQADCggICAABNQAECgoKGQAOAEMLAA==.',
We='Weemer:BAAANQADCgcIFAAAAA==.Wesleypipes:BAABNQAECn8cAAIHAAkKMRQUcwCyAQAHAAkKMRQUcwCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAABNQAECn8cAAIKAAgKuxOnywDuAQAKAAgKuxOnywDuAQAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpally:BAACNQAFFH8HAAIgAAMKdw2RGADLAAAgAAMKdw2RGADLAAA1AAQKfzMAAiAACgqbF4k3AIYCACAACgqbF4k3AIYCAAAA.Wolfmato:BAABNQAECn87AAMHAAoK8R25JwDFAgAHAAoK8R25JwDFAgAIAAQKJRA3rwCpAAAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAABNQAECn8sAAIWAAgKhxKIJwA1AQAWAAgKhxKIJwA1AQAAAA==.',
Xe='Xeros:BAAANQADCggICAAAAA==.Xerxeis:BAAANQABCgYICAABNQAECgcIBwADAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgoKKwAdAGgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAcIFgAHAEwXAA==.',
Ys='Yssuplef:BAABNQAECn8oAAQSAAkK9AxOCwANAQAaAAcKqgobpAAOAQASAAgKZQtOCwANAQARAAQKMgd+HACbAAAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.Yunjin:BAAANQADCgMIAwAAAA==.',
Za='Zaiyra:BAAANQAECgUIBgAAAA==.Zakoor:BAAANQADCgcIIQAAAA==.Zambreth:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgcIIwAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zaurra:BAAANQAECgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIJgAAAA==.Zekia:BAABNQAECn80AAIGAAkKlBkcVwBtAgAGAAkKlBkcVwBtAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergul:BAAANQABCgQIBAAAAA==.Zerm:BAABNQAECn81AAIJAAoKoBewZAAIAgAJAAoKoBewZAAIAgAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAABNQAECn8dAAIHAAgKewwshwAfAQAHAAgKewwshwAfAQAAAA==.',
Zo='Zorsa:BAABNQAECn8eAAIaAAYKbAZ7ygC8AAAaAAYKbAZ7ygC8AAAAAA==.',
Zu='Zuljawn:BAABNQAECn8vAAIFAAkKvgxaHwB3AQAFAAkKvgxaHwB3AQAAAA==.',
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
