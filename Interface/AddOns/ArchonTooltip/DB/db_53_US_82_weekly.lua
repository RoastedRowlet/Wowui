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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Druid-Guardian','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Paladin-Holy','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Priest-Discipline','Paladin-Protection','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIGAAAAA==.',
Ae='Aegennai:BAABNQAECn8vAAIBAAkK0wWGFwBWAQABAAkK0wWGFwBWAQAAAA==.Aegondk:BAABNQAFFH8GAAICAAMK0xlqDgD0AAACAAMK0xlqDgD0AAAAAA==.Aelias:BAAANQAECgUIDAAAAA==.Aevaela:BAABNQAECn8wAAIDAAkKjhveEABxAgADAAkKjhveEABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn80AAMEAAoK3hONGwBiAQAEAAgKHBONGwBiAQAFAAUKhhTq1gDAAAAAAA==.',
Ak='Akey:BAAANQAECggIHgAAAQ==.Akhae:BAABNQAECn8tAAMGAAkKKBdkYwDjAQAGAAkKKBdkYwDjAQAHAAEKtwHeUQElAAAAAA==.',
Al='Albinism:BAAANQAECgUIEQAAAA==.Alcadeias:BAAANQAECgUICAAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amuria:BAAANQAECgQIBwAAAA==.',
An='Anaeda:BAABNQAECn8cAAIIAAgKrwxtvACkAQAIAAgKrwxtvACkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgcIEAAJAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIGwAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIFQAAAA==.',
Ar='Aralleda:BAAANQADCgEIAgAAAA==.Arccane:BAABNQAECn8XAAIKAAcKZBWK2ADWAQAKAAcKZBWK2ADWAQAAAA==.Arthar:BAABNQAECn9MAAILAAoK2h/1OQDeAgALAAoK2h/1OQDeAgAAAA==.',
As='Ashvyth:BAABNQAECn8uAAQMAAkKZx2SBQAHAgAMAAgKYCCSBQAHAgANAAEKkwsNUgA3AAAOAAEKKAWBPAAhAAAAAA==.Astarra:BAAANQADCgEIAQAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAwABNQAECgkJHgAPAOUbAA==.',
Az='Azuredeath:BAAANQADCgEIAQAAAA==.Azurehope:BAAANQADCgEIAQAAAA==.Azurelive:BAAANQABCgYIBgAAAA==.',
Ba='Babalou:BAAANQADCgcIAwAAAA==.Baconpancake:BAAANQAECgQICQAAAA==.Baldpunch:BAAANQAECgEIAQAAAA==.Balinor:BAAANQAECgYIDwAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgUIDwAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgUIDwAJAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAABNQAECn8ZAAIQAAgKthNZWgCmAQAQAAgKthNZWgCmAQAAAA==.Beaj:BAAANQAECgYIEwAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICwAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8sAAMRAAgKICDFIACoAgARAAgKICDFIACoAgASAAQKrA7lOACfAAAAAA==.Bigblingaxe:BAAANQADCggICgAAAA==.Bilac:BAAANQADCgEIAgABNQAFFAIIBQATAEoBAA==.',
Bl='Blacksabbth:BAAANQABCgIIAgAAAA==.Blusoleil:BAAANQAECgYIEgAAAA==.Blux:BAAANQADCgEIAQAAAA==.',
Bo='Bonerblast:BAAANQADCggICwAAAA==.Boston:BAABNQAECn83AAQCAAoKCB+mMgAVAgACAAoKYhqmMgAVAgAQAAgKxR0pKABvAQAUAAYKHhiBOAA4AQAAAA==.',
Br='Branches:BAABNQAECn84AAMVAAkK4w9gKQB7AQAVAAkK4w9gKQB7AQAWAAcKpw1uNwBhAQAAAA==.Branden:BAAANQADCgcIBwABNQADCggIHAAJAAAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAABNQAECn8VAAIFAAgKKQc8xwBzAQAFAAgKKQc8xwBzAQAAAA==.Briggsey:BAABNQAECn8sAAIXAAgKOwpsewA0AQAXAAgKOwpsewA0AQAAAA==.Brisdelle:BAAANQABCgQIBAAAAA==.Briznot:BAABNQAECn8eAAMYAAkKiBL6EQCuAAAXAAcKwhDTfAAxAQAYAAMKjBP6EQCuAAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBgAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCggIFwAAAA==.',
Bu='Bubbadubya:BAAANQADCggILQAAAA==.Bump:BAAANQADCgEIAQAAAA==.Bunnyfu:BAAANQAECgUICwABNQAFFAIIBQATAEoBAA==.Burningwolf:BAABNQAECn8gAAIGAAkKfB/eGwCsAgAGAAkKfB/eGwCsAgAAAA==.',
['Bó']='Bórs:BAAANQAECgQIDAAAAA==.',
Ca='Caiden:BAAANQAECgUIBwAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCggIKQAAAA==.Calesona:BAAANQAECgQIBwAAAA==.Carnìfex:BAAANQAECgUIDgAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAABNQAECn8hAAQZAAkKix/QBQB6AgAZAAkKix/QBQB6AgAaAAgKwxqJEwDEAQAVAAEKrRA2sgAyAAAAAA==.',
Ce='Cerà:BAABNQAECn8iAAIWAAgKChYvFwASAgAWAAgKChYvFwASAgAAAA==.',
Ch='Chapslop:BAAANQADCgcIDgAAAA==.Cheddar:BAAANQADCgEIAgAAAA==.Cheetah:BAAANQADCgcIDwAAAA==.',
Ci='Cinnawhiskey:BAAANQADCgUIBQAAAA==.',
Cl='Cleetus:BAAANQAECgQIBQAAAA==.Clizee:BAABNQAECn8cAAIKAAkKBQc1mQBFAQAKAAkKBQc1mQBFAQAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAABNQAECn8dAAQVAAkKJRAJTwCjAQAVAAkKJRAJTwCjAQAaAAQKfg9XQAC5AAAWAAMKXgtEUACAAAAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Coldtex:BAAANQAECggIAwAAAA==.Constellate:BAAANQAECgYIEwAAAA==.Cotterpins:BAABNQAECn8gAAIIAAkKwBOAawC7AQAIAAkKwBOAawC7AQAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.Crunchyjim:BAAANQAECgMIBAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAwAAAA==.Cyndlia:BAAANQADCgUIBQAAAA==.',
Cz='Cztalone:BAAANQADCgQIBQAAAA==.',
['Cè']='Cèlane:BAABNQAECn86AAMHAAoKFRj+MQCyAgAHAAoKFRj+MQCyAgAGAAQK1wu68gCFAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgYIHAADAPEQAA==.Damnitsu:BAEBNQAECn8cAAMDAAYK8RBxKACBAQADAAYK8A9xKACBAQAbAAUKBgtBZwAVAQAAAA==.Darckside:BAAANQAECgYICAAAAA==.Dazen:BAAANQADCggIGQAAAA==.',
De='Deadflexy:BAABNQAECn8eAAIUAAkKzBjSHwDQAQAUAAkKzBjSHwDQAQAAAA==.Deathberry:BAABNQAECn8jAAIXAAgKPRuXUABjAgAXAAgKPRuXUABjAgAAAA==.Deathdoodles:BAABNQAECn8VAAMQAAcKxA5yQQDcAAAQAAcKog5yQQDcAAACAAIKswkolwBmAAABNQAECgoKPQARAGkYAA==.Deathriaa:BAAANQADCgEIAQABNQAECggIAwAJAAAAAA==.Deathsveil:BAAANQADCgcIBwAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgUIDQAAAA==.Dejavù:BAAANQAFFAIIAwAAAA==.Demonblood:BAABNQAECn8gAAMUAAoKdRE6TgC9AQAUAAkKsBI6TgC9AQAQAAEK2gjfewA0AAAAAA==.Demonicmac:BAAANQADCgMIBAABNQAECgQICAAJAAAAAA==.Deräth:BAABNQAECn8ZAAISAAcKiwdFOwBPAQASAAcKiwdFOwBPAQAAAA==.Devlik:BAAANQAECgMIAQAAAA==.Dew:BAAANQADCgYIBwABNQADCgYIDAAJAAAAAA==.Dezlover:BAAANQADCgQIBQAAAA==.',
Dh='Dhdawg:BAAANQAECgIIAQAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIFwAAAA==.Dionne:BAAANQAECgYIDAAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgoKOQAKAHUdAA==.Ditsie:BAAANQAECgEIAQAAAA==.',
Dm='Dmega:BAABNQAECn8mAAIFAAgKuQvSgABvAQAFAAgKuQvSgABvAQAAAA==.',
Do='Dobby:BAAANQAECgYIBgAAAA==.Dodgeramthis:BAAANQADCgIIAgAAAA==.Dogfunk:BAAANQADCgEIAgAAAA==.Dorne:BAAANQADCgIIAgAAAA==.',
Dr='Dragea:BAAANQAECgYIEAAAAA==.Dragondude:BAABNQAECn8nAAQcAAkKfBw8FABrAgAcAAkKfBw8FABrAgAdAAYKVQy4DwAPAQATAAIKhQsLFQBlAAAAAA==.Dragonsgrasp:BAAANQADCgUIBQAAAA==.Drakoswrath:BAACNQAFFH8RAAIUAAYKdRO5DQB4AQAUAAYKdRO5DQB4AQA1AAQKfzYAAhQACgrCJEUGABQDABQACgrCJEUGABQDAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAABNQAECn8eAAILAAgKtxzRRQAAAgALAAgKtxzRRQAAAgAAAA==.',
Dy='Dyelin:BAABNQAECn8uAAIXAAoKXhlkJABYAgAXAAoKXhlkJABYAgAAAA==.',
['Dõ']='Dõtdropnroll:BAAANQADCgQIBAAAAA==.',
Ek='Ekocteid:BAAANQADCgEIAQAAAA==.',
El='Elylle:BAAANQAECgIIAwABNQAECgQIBAAJAAAAAA==.Elyron:BAABNQAECn8vAAIKAAkK0hYPVgDoAQAKAAkK0hYPVgDoAQAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn8/AAMKAAoKpB/TIwCUAgAKAAoKrB7TIwCUAgAPAAcKOR09CwAQAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgUIBwAAAA==.',
Eu='Euandros:BAABNQAECn8bAAIIAAkKrAnemABaAQAIAAkKrAnemABaAQAAAA==.',
Ev='Evï:BAAANQAECgEIAQAAAA==.',
Ez='Ezhra:BAAANQADCgEIAQABNQADCggIKQAJAAAAAA==.Ezind:BAAANQAECgUIDQAAAA==.',
Fa='Fakename:BAAANQAECggIDAAAAA==.Fakesaint:BAABNQAECn85AAIGAAoKTiR/FQAjAwAGAAoKTiR/FQAjAwAAAA==.Fangstorm:BAABNQAECn8sAAIZAAgKAhI2EQBlAQAZAAgKAhI2EQBlAQAAAA==.Farorê:BAAANQADCgYJDgAAAA==.Fazz:BAAANQAECgYIDwAAAA==.',
Fe='Feldruid:BAAANQAECgQIDAAAAA==.Felup:BAABNQAECn8+AAQXAAoKnyEuHwAHAwAXAAoKnyEuHwAHAwAYAAIK+xEqVgB8AAAeAAEK5BvQKgBCAAAAAA==.',
Fo='Folstagg:BAAANQADCgcIDgAAAA==.Foreverem:BAABNQAECn89AAMfAAoKfxmoGgC1AgAfAAoKfxmoGgC1AgAIAAEKDAJayQEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8vAAIgAAkKSw/lDgC/AQAgAAkKSw/lDgC/AQAAAA==.Fusepins:BAAANQADCgcIAwAAAA==.Fuzzwig:BAAANQADCgcIDwAAAA==.',
Ga='Gaska:BAAANQAECgYICwABNQAECgUIDAAJAAAAAA==.',
Ge='Geheimnis:BAAANQADCgEIAQAAAA==.',
Gh='Ghösty:BAAANQADCgMIAwABNQAECggIAwAJAAAAAA==.',
Gi='Gibs:BAAANQADCgEIAQAAAA==.Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgcIBwABNQAECgkJHQASALYbAA==.',
Gr='Gracela:BAAANQADCgEIAQAAAA==.Graxus:BAAANQAECgYIDQAAAA==.Greth:BAAANQADCggILgAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.Grumpy:BAAANQADCgcIAwABNQAECgkJHgAUAMwYAA==.',
Gu='Gudge:BAACNQAFFH8FAAITAAIKSgHyCgBSAAATAAIKSgHyCgBSAAA1AAQKfzsAAxMACgqpETIIABgCABMACgqpETIIABgCABwAAwruAa01AC8AAAAA.Gummypenguin:BAABNQAECn8qAAIFAAoK4SJiEQDtAgAFAAoK4SJiEQDtAgABNQAFFAUIFwAFAGckAA==.',
Ha='Hadhox:BAAANQAECgMIBAABNQAECgoKNgAFAMQPAA==.Halforcked:BAAANQADCgYICQAAAA==.Hathdox:BAABNQAECn82AAIFAAoKxA+HTwDvAQAFAAoKxA+HTwDvAQAAAA==.Hawkulees:BAAANQADCggIJQAAAA==.Hazelnoot:BAABNQAECn8/AAMIAAoKMSQGEACKAwAIAAoKMSQGEACKAwAfAAMKUgqnswCHAAAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgUICAAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8nAAIhAAgKCQ39NgAtAQAhAAgKCQ39NgAtAQAAAA==.',
Hi='Hitsuryu:BAABNQAECn8eAAITAAcKtQJKGAC0AAATAAcKtQJKGAC0AAAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8fAAMbAAoKYQyyPgDTAQAbAAkKYQyyPgDTAQAiAAYK3gTmEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgYICQAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAJAAAAAA==.Hornsharp:BAAANQAECgUICAAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAFFAIIBQATAEoBAA==.Hunilla:BAABNQAECn8XAAQSAAYKLgxRPABIAQASAAYKLgxRPABIAQARAAUK+gZxvADkAAAjAAEK6gHrGQAfAAABNQAFFAIIBQATAEoBAA==.Huuken:BAAANQADCgUIBQAAAA==.',
Ia='Iamu:BAAANQADCgYIGgAAAA==.',
Ib='Ibris:BAAANQADCggIGQAAAA==.',
Ic='Iconius:BAAANQADCggIGQAAAA==.',
Ie='Ieatwetsocks:BAACNQAFFH8KAAIGAAQKmw//EAAHAQAGAAQKmw//EAAHAQA1AAQKfyQAAwYACgo4FctXAAoCAAYACgo4FctXAAoCAAcAAgpbBO0hAU0AAAAA.',
Ig='Ignivar:BAAANQADCggIGgAAAA==.',
In='Indra:BAAANQAECgYIDAAAAA==.Innexshaman:BAABNQAECn8oAAIHAAoKSRlmJgAYAgAHAAoKSRlmJgAYAgAAAA==.Insaint:BAACNQAFFH8JAAIIAAMKxQw6HADGAAAIAAMKxQw6HADGAAA1AAQKfz0AAggACgoQF4xSAP8BAAgACgoQF4xSAP8BAAAA.',
Ir='Ironfield:BAABNQAECn8gAAMGAAoKNhdvNwALAgAGAAoKNhdvNwALAgAHAAMKFQNFCgF3AAABNQADCgUIBQAJAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAABNQAECn8ZAAISAAYKIwbuSwDmAAASAAYKIwbuSwDmAAAAAA==.',
Je='Jessamine:BAABNQAECn9HAAIKAAoKzRUtRAAcAgAKAAoKzRUtRAAcAgAAAA==.Jetta:BAAANQAECgUIEQAAAA==.Jezzak:BAABNQAECn8mAAIFAAkK/hAOdwAhAgAFAAkK/hAOdwAhAgABNQAECgoKMAAFAMwWAA==.',
Jo='John:BAABNQAECn9XAAIiAAoKdiOVAAC3AwAiAAoKdiOVAAC3AwAAAA==.Jorien:BAABNQAECn86AAIFAAoKbh6RJwB2AgAFAAoKbh6RJwB2AgAAAA==.',
Jp='Jp:BAAANQAECgYICwAAAA==.Jpb:BAAANQAECgIIAgABNQAECgYICwAJAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgYICwAJAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgYICwAJAAAAAA==.',
Ju='Justadwarf:BAAANQAECgUIBgAAAA==.Justatsuj:BAAANQAECgQIBAAAAA==.Juston:BAABNQAECn8cAAMHAAoKGg9FNADMAQAHAAkKGg9FNADMAQAGAAYKRAacywDQAAAAAA==.',
Ka='Kaboonsky:BAABNQAECn8ZAAMRAAkKHRpcTADOAQARAAkKHRpcTADOAQASAAYKMg8OOQBdAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAABNQAECn8eAAIgAAcKyRWzEQCJAQAgAAcKyRWzEQCJAQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAJAAAAAA==.Karnadaz:BAABNQAECn8hAAILAAkKRhoNYwBlAgALAAkKRhoNYwBlAgAAAA==.Karnkarn:BAAANQAECgYICgAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgcIDwAJAAAAAA==.Kaytana:BAAANQADCgEIAQABNQADCggIKQAJAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIGAAcKRCPWMwCQAgAGAAcKRCPWMwCQAgAAAA==.',
Ko='Kolosho:BAAANQAECgcIBwAAAA==.Korxana:BAABNQAECn8mAAIkAAgKjxDqHgBBAQAkAAgKjxDqHgBBAQAAAA==.Korxon:BAABNQAECn89AAIRAAoK4xmyNgCNAgARAAoK4xmyNgCNAgAAAA==.Kotus:BAABNQAECn8gAAMlAAkK0A+wHwBTAQAlAAYKfxWwHwBTAQALAAkK9QdkhQBDAQAAAA==.',
Ks='Ksyusha:BAABNQAECn8eAAIIAAgK+wYx0wD0AAAIAAgK+wYx0wD0AAAAAA==.',
Ky='Kyfess:BAAANQAECgYICwAAAA==.',
['Kä']='Kämi:BAAANQAECgEIAQABNQAECgYIFAAKAJ0LAA==.',
La='Ladgertha:BAAANQADCgYIBgAAAA==.Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgMIAwAAAA==.Lanuadra:BAABNQAECn8nAAIDAAkKpheaDwCCAgADAAkKpheaDwCCAgAAAA==.Lawry:BAAANQAECggIEQAAAA==.Layhee:BAACNQAFFH8FAAIhAAQKAgJqEACOAAAhAAQKAgJqEACOAAA1AAQKfxkAAyEABwoXGPEyAEUBACEABQrNG/EyAEUBACYAAwowEDw3ALAAAAAA.',
Le='Leasidhe:BAAANQADCgcIEAABNQADCgQIBQAJAAAAAA==.Lethalbimbo:BAAANQADCggIIAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAwAAAA==.',
Li='Liesel:BAAANQADCggICwAAAA==.Lillié:BAAANQADCgEIAgAAAA==.Lilysham:BAACNQAFFH8VAAIGAAYKEhn9CQCvAQAGAAYKEhn9CQCvAQA1AAQKfz8AAwYACgopIQMsALICAAYACgopIQMsALICAAcACgrVFjAqAAECAAAA.Lindar:BAAANQADCgEIAgAAAA==.Linddrel:BAAANQAECgYIDgAAAA==.Liquidshadow:BAAANQADCgEIAQAAAA==.',
Lo='Lomea:BAAANQADCgYICgABNQAECgQIBAAJAAAAAA==.Lonarius:BAAANQADCgEIAQAAAA==.',
Lu='Lunasblood:BAAANQADCgcIDAAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECggIGQAQALYTAA==.',
['Lø']='Løllîe:BAABNQAECn8YAAIMAAcK5wn3EQDRAAAMAAcK5wn3EQDRAAAAAA==.',
Ma='Macarius:BAABNQAECn8jAAIOAAkKvRq0CQB2AgAOAAkKvRq0CQB2AgAAAA==.Macdee:BAAANQADCgMIBAABNQAECgQICAAJAAAAAA==.Magatai:BAAANQAECgYICwAAAA==.Mageless:BAAANQADCgIIAwAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDQAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQADCgEIAQABNQADCgUIBQAJAAAAAA==.Manaster:BAAANQAECgYIEwAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgUIDwAAAA==.Mathas:BAAANQAECgUIBgAAAA==.Mathius:BAAANQAECgEIAQAAAA==.Mavis:BAAANQADCgEIAQAAAA==.Maynis:BAAANQADCgEIAQAAAA==.Maysaveyou:BAAANQAECgQIAwAAAA==.',
Me='Meanwhile:BAAANQADCgcIBgAAAA==.Meowmixx:BAAANQADCgMIBAAAAA==.Merkii:BAAANQADCgYIBwABNQAECgoKJAAbADkaAA==.',
Mi='Micflinigan:BAABNQAECn8nAAMgAAgKGxbICgAaAgAgAAgKGxbICgAaAgALAAQK+QwvGgGoAAAAAA==.Midnightmare:BAAANQABCgMIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgUIEQAAAA==.Ming:BAAANQADCgQIBAABNQAECgoKPQAOAK8gAA==.Minilove:BAAANQADCgUICgAAAA==.Mirix:BAAANQAECgcICgAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgUIDAAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQICAAAAA==.Moonshae:BAABNQAECn82AAMOAAoKihNWFwAHAgAOAAoKihNWFwAHAgANAAcK6hP8OABMAQAAAA==.Moose:BAAANQADCgEIAgAAAA==.Moosesanta:BAAANQADCgEIAQAAAA==.Moothrnature:BAAANQADCgEIAQAAAA==.Mortalbion:BAAANQAECgMIAgAAAA==.',
Mu='Murciélago:BAAANQAECgQIBQAAAA==.Mustevistust:BAAANQADCgQIBAABNQAECgUIDwAJAAAAAA==.',
My='Mystiquè:BAAANQADCggIKAAAAA==.',
['Må']='Måmoo:BAAANQADCgEIAQAAAA==.',
Na='Nahmbra:BAAANQAECgcIDwAAAA==.Naithin:BAAANQAECgQIBQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQABCgQIBAAAAA==.Naviriel:BAAANQAECgYIBgABNQAECgkJGAANACwLAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQAECgQICAABNQAECgoKTAALANofAA==.Nilesong:BAAANQADCgEIBAAAAA==.',
No='Nofoxgìven:BAAANQAECgIIAgAAAA==.Noknik:BAAANQADCgEIAQABNQADCgUIBQAJAAAAAA==.Nonsocial:BAACNQAFFH8JAAIkAAcKGg2EAwDIAQAkAAcKGg2EAwDIAQA1AAQKfxgAAiQACQoTJFcEAHMDACQACQoTJFcEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgoKJgAWAHUjAA==.Noriisa:BAABNQAECn8wAAIFAAoKzBaxXABfAgAFAAoKzBaxXABfAgAAAA==.Noudders:BAABNQAECn8vAAIGAAkKoR+3EgD4AgAGAAkKoR+3EgD4AgAAAA==.',
Ny='Nyvak:BAAANQAECgYICwAAAA==.',
Od='Odinhand:BAABNQAECn9AAAIVAAkKjQzBJwCHAQAVAAkKjQzBJwCHAQAAAA==.',
Oe='Oenei:BAAANQADCgMIAwAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCggILQAAAA==.',
Oz='Ozwäld:BAABNQAECn8WAAIKAAcK5Q8/AAGNAQAKAAcK5Q8/AAGNAQABNQAECgoKOQABAK4gAA==.Ozwäldo:BAABNQAECn85AAIBAAoKriCQBgAcAwABAAoKriCQBgAcAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn85AAMKAAoKdR2VHwCoAgAKAAoKdR2VHwCoAgAPAAIKVRLiMgBvAAAAAA==.Pandóra:BAAANQAECgIIAQAAAA==.Pariousa:BAABNQAECn8rAAMbAAoKaCPTDQAVAwAbAAoKzyLTDQAVAwADAAQKBB3/XABEAQAAAA==.',
Pe='Peppermintxo:BAAANQAECgQIBAABNQADCgIJAgAJAAAAAA==.Peärl:BAAANQADCgEIAQAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgYIBwAAAA==.Phylinx:BAAANQADCgIIAgAAAA==.',
Pi='Pinkeepink:BAAANQAECgYIEAAAAA==.Pixiepriest:BAAANQADCgEIBAAAAA==.',
Po='Popacooldown:BAAANQAECgEIAwAAAA==.Potangwang:BAAANQAECgIIAgAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQADCgEIAQAAAA==.',
Pu='Puhk:BAAANQADCgcICQAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.Purplerain:BAAANQADCgEIAQAAAA==.',
Ra='Rahzon:BAABNQAECn8VAAIFAAcKVwunqAAcAQAFAAcKVwunqAAcAQAAAA==.Raijù:BAAANQAECgEIAQAAAA==.Ralganor:BAABNQAECn9HAAIUAAoKZSKtCADuAgAUAAoKZSKtCADuAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICgAAAA==.Randron:BAAANQAECgYICgAAAA==.Ravilan:BAAANQAECgMIBQAAAA==.Raynlight:BAABNQAECn8XAAMSAAgK4hTPPABEAQASAAYK4Q3PPABEAQARAAcKSAamiwD9AAAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.Retaeytoob:BAAANQAFFAEIAQAAAA==.Rexx:BAAANQAECggICAAAAA==.',
Ri='Rina:BAABNQAECn8UAAMmAAgK1BTJJwAGAgAmAAgKbxTJJwAGAgAnAAEKoQlZNAAqAAAAAA==.Rineli:BAAANQADCgcICgABNQAECgUIEQAJAAAAAA==.Ringadingg:BAABNQAECn8vAAMQAAoKPiKZBwDiAgAQAAoKPiKZBwDiAgACAAEKSCDfmgBdAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgcIDQAAAA==.',
Sa='Sadpandaizzy:BAAANQADCgEIAQAAAA==.Sankatlantis:BAAANQADCgYIDAAAAA==.Sanurá:BAAANQAECgMIAwAAAA==.Sarka:BAAANQADCgcICAAAAA==.Sasquatch:BAABNQAECn8dAAMGAAkKRA8WSwC0AQAGAAkKRA8WSwC0AQABAAUKiwedIQDQAAAAAA==.Satuno:BAAANQAECgIIAQABNQAECgkJJgAmAKsTAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECgYICwAAAA==.Scribs:BAAANQAECgYICwAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQADCgEIAQAAAA==.Seismic:BAAANQAECggIEAAAAA==.Seniko:BAAANQAECgMIBQAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8gAAMHAAkK3RtTfQCsAQAHAAYKZhpTfQCsAQAGAAYKig5mhgDwAAABNQAECgkJKAAaAIAgAA==.Severalforms:BAABNQAECn8oAAMaAAkKgCCRBwCnAgAaAAkKVSCRBwCnAgAZAAIK0hdVMACPAAAAAA==.Severànce:BAABNQAECn8oAAQnAAkKmRgDDgDcAQAnAAgK8RUDDgDcAQAhAAUK1BRmTwBcAQAmAAQKvBGVTwDiAAABNQAECgkJKAAaAIAgAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJKAAaAIAgAA==.',
Sh='Shablammy:BAABNQAECn8hAAMGAAgKWyPoEAALAwAGAAgKWyPoEAALAwAHAAEKAADTIQFOAAAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCggIGgAAAA==.Shadowson:BAAANQABCgEIAQAAAA==.Shaelià:BAAANQADCgEIAQAAAA==.Shammygand:BAAANQADCgUIBgABNQAECgoKLQAkAMEZAA==.Shanker:BAAANQADCgMIAwAAAA==.Shavalyoth:BAAANQADCgEIAQAAAA==.Sheephappéns:BAAANQAECggIDwABNQAECgkJKAAaAIAgAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn89AAMRAAoKaRh+MACmAgARAAoKaRh+MACmAgASAAIKGQOxWQAsAAAAAA==.Shikoba:BAAANQADCgEIAQAAAA==.Shutupbird:BAABNQAECn87AAIaAAoKyx1RDQCRAgAaAAoKyx1RDQCRAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skendr:BAAANQADCgEIAQABNQADCggIGgAJAAAAAA==.Skydragon:BAAANQADCggIJQAAAA==.',
Sl='Slack:BAAANQADCgQIBAAAAA==.Slay:BAAANQAECgEIAQABNQAECgoKOgAUALkbAA==.Sleepydwarf:BAAANQADCggICgAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAABNQAECn8dAAMSAAkKthsKEwDxAQASAAkKthsKEwDxAQARAAEKrAj++AA7AAAAAA==.',
Sp='Sparrtacus:BAAANQADCgEIAQAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAABNQAECn8mAAIWAAoKdSOOAwCkAwAWAAoKdSOOAwCkAwAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDwABNQAECgkJIAAIAMATAA==.Starfire:BAAANQADCgEIAQAAAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCggIKwAAAA==.Stealthful:BAAANQAECggIBgAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIICQAhAH8eAA==.Strayaus:BAAANQABCgMIAwAAAA==.Strongbad:BAAANQAECgQIBgAAAA==.Stubly:BAAANQADCgUICgAAAA==.',
Su='Sunfyrie:BAABNQAECn8kAAIRAAcKjhfFWACfAQARAAcKjhfFWACfAQAAAA==.',
Sw='Sweèt:BAAANQAECgIIAgAAAA==.Swiftyretpal:BAAANQAECggICAAAAA==.',
Ta='Tagrit:BAAANQADCgUIBgAAAA==.Taldieth:BAABNQAECn8YAAIBAAcKcQKwIwC2AAABAAcKcQKwIwC2AAAAAA==.Tannas:BAAANQAECgMIAwAAAA==.Tarouhorn:BAAANQAECgEIAQAAAA==.Taurdk:BAAANQAECgYIDQAAAA==.Taylorshift:BAABNQAECn8sAAIVAAoKpB/7FwAIAwAVAAoKpB/7FwAIAwAAAA==.Tazranir:BAAANQADCggICwAAAA==.',
Te='Teaar:BAAANQADCgUIBgABNQAECgoKOgAUALkbAA==.Teetau:BAABNQAECn8sAAIaAAgKqwRiNQC+AAAaAAgKqwRiNQC+AAAAAA==.Texlandar:BAAANQADCgMIAwAAAA==.',
Th='Thadregosa:BAABNQAECn8iAAIdAAgKdhNHDABbAQAdAAgKdhNHDABbAQAAAA==.Thalsan:BAAANQADCgEIAQAAAA==.Thander:BAAANQADCggIHAAAAA==.Thedarkskull:BAAANQABCgIIAgAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQADCgEIAQAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQADCgEIAQAAAA==.Tiffy:BAAANQADCggIOAAAAA==.Timoleon:BAAANQAECgQIAwAAAA==.Tirna:BAAANQAECggIDQAAAA==.Tirnotham:BAABNQAECn8hAAMNAAgKVw7nIwBDAQANAAgKVw7nIwBDAQAOAAIK7QKcNgA0AAAAAA==.',
Tm='Tmtglizzy:BAABNQAECn81AAMGAAkKUR6gHACmAgAGAAkKUR6gHACmAgAHAAQK7xX/uAAgAQAAAA==.',
To='Tobi:BAABNQAECn9FAAMfAAoK3SVDBACxAwAfAAoK3SVDBACxAwAIAAUKMhiH+gApAQAAAA==.Tokalu:BAABNQAECn8YAAINAAkKLAu+IABeAQANAAkKLAu+IABeAQAAAA==.Tonjudsonson:BAACNQAFFH8OAAIaAAUKBRKZAwAjAQAaAAUKBRKZAwAjAQA1AAQKfz4ABBoACgpZIkkDAIYDABoACgpZIkkDAIYDABYABwqZIkoNALECABkAAQoAABhOAAAAAAAA.Torath:BAAANQADCgYIDgABNQADCggIHAAJAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIIgAAAA==.',
Tw='Twiki:BAABNQAECn8oAAIYAAcKNwWPFACcAAAYAAcKNwWPFACcAAAAAA==.Twobricks:BAABNQAECn9DAAIWAAoKJxUeFgAiAgAWAAoKJxUeFgAiAgAAAA==.',
Ty='Tyrielas:BAAANQADCgYICAAAAA==.Tyrssana:BAABNQAECn8fAAMmAAgKJAwYJABDAQAmAAgKJAwYJABDAQAnAAUKXAg8GgCUAAABNQAFFAUICgAcAEcKAA==.',
['Tä']='Täuriel:BAAANQAECgMIAwABNQAECgoKNgAFAMQPAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn89AAIkAAoKzh/eCACHAgAkAAoKzh/eCACHAgABNQAECgYIBgAJAAAAAA==.',
Ur='Urdeadtoo:BAABNQAECn8bAAMfAAcKIx3OTwAsAgAfAAcKIx3OTwAsAgAIAAYKPw6m/wAgAQAAAA==.Urlacher:BAAANQAECgQIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaccaria:BAAANQADCgEIAQABNQADCggIGgAJAAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAABNQAECn8hAAIIAAgKBgqbwQASAQAIAAgKBgqbwQASAQAAAA==.Vayikra:BAAANQADCgMIAwABNQAECgkJKwAHALEMAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIJwAAAA==.Verlynna:BAAANQADCgIIAgAAAA==.Vertexx:BAAANQAECgEIAgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgkJHgAYAIgSAA==.Vierth:BAAANQAECgQIBAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQAECgEIAQAAAA==.Visea:BAAANQADCgIIAwABNQAECgQIBAAJAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIJAAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECggIKAAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
['Vå']='Våder:BAAANQAECgIIAgAAAA==.',
Wa='Warkistla:BAAANQADCggICAABNQAECgkJGAANACwLAA==.Watevr:BAEANQADCgcIGQABNQAECgYIHAADAPEQAA==.',
We='Weemer:BAAANQADCgcIFAAAAA==.Wesleypipes:BAABNQAECn8cAAIGAAkKMRQUcwCyAQAGAAkKMRQUcwCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Willowdragon:BAAANQADCgEIAQAAAA==.Wizalf:BAABNQAECn8cAAIKAAgKuxO2hgBsAQAKAAgKuxO2hgBsAQAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpally:BAABNQAECn8xAAIfAAoKChaJNwCGAgAfAAoKChaJNwCGAgAAAA==.Wolfmato:BAABNQAECn8tAAIGAAoK8R25JwDFAgAGAAoK8R25JwDFAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAABNQAECn8eAAIkAAcK6RGhJwAAAQAkAAcK6RGhJwAAAQAAAA==.',
Xe='Xear:BAAANQADCgEIAQABNQADCggIOAAJAAAAAA==.Xeros:BAAANQADCggICAAAAA==.Xerxeis:BAAANQADCgEIAQABNQAECgcIBwAJAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgoKKwAbAGgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAYIFQAGABIZAA==.',
Ys='Yssuplef:BAABNQAECn8hAAQYAAkKOgy9CgDrAAAXAAcKqgqdjgAIAQAYAAgKRgq9CgDrAAAeAAMKqgh+HACbAAAAAA==.',
Yu='Yuefei:BAAANQADCgYICwAAAA==.Yunjin:BAAANQADCgMIAwAAAA==.',
Za='Zaiyra:BAAANQAECgUIBgAAAA==.Zakoor:BAAANQADCgcIHwAAAA==.Zambreth:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgcIIgAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zaurra:BAAANQAECgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIJQAAAA==.Zekia:BAABNQAECn80AAIFAAkKlBlYSQABAgAFAAkKlBlYSQABAgAAAA==.Zepirra:BAAANQADCgEIAQAAAA==.Zergdemon:BAAANQADCgEIAgAAAA==.Zerm:BAABNQAECn81AAIIAAoKoBeqTQANAgAIAAoKoBeqTQANAgAAAA==.Zermonk:BAAANQADCgEIAQAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAABNQAECn8WAAIGAAgKYQswcwAmAQAGAAgKYQswcwAmAQAAAA==.',
Zo='Zorsa:BAAANQAECgYIDwAAAA==.',
Zu='Zuljawn:BAABNQAECn8sAAIEAAgKYw3NHQBJAQAEAAgKYw3NHQBJAQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAwAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICwAAAA==.',
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
