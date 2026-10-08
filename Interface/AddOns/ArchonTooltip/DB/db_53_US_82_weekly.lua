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

local lookup = {'DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Warrior-Arms','Mage-Frost','Unknown-Unknown','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Warlock-Demonology','Priest-Holy','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Devastation','Druid-Guardian','Paladin-Holy',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgYIEQAAAA==.',
Ae='Aegennai:BAAANQAECgUIEgAAAA==.Aegondk:BAEBNQAFFIEGAAIBAAMK0xkWCQAJAQABAAMK0xkWCQAJAQAAAA==.Aelias:BAAANQADCggIHQAAAA==.Aevaela:BAABNQAECoEjAAICAAgKohmmDgB9AgACAAgKohmmDgB9AgAAAA==.',
Ag='Agilaz:BAABNQAECoEaAAIDAAcKvhVtKwDMAQADAAcKvhVtKwDMAQAAAA==.',
Ak='Akey:BAAANQAECgUICAAAAQ==.Akhae:BAABNQAECoEiAAMEAAgKdBJfUwDsAQAEAAgKdBJfUwDsAQAFAAEKtwHXLgElAAAAAA==.',
Al='Albinism:BAAANQAECgQIBQAAAA==.Alcadeias:BAAANQAECgEIAQAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amuria:BAAANQAECgQIBQAAAA==.',
An='Anaeda:BAABNQAECoEaAAIGAAcK0wvhvgBmAQAGAAcK0wvhvgBmAQAAAA==.Anastrianna:BAAANQADCgYICQAAAA==.Andrömëdä:BAAANQAECgIIAQAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIFQAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIEQAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQAECgYIDAAAAA==.Arthar:BAABNQAECoEvAAIHAAkKShvvOQDGAgAHAAkKShvvOQDGAgAAAA==.',
As='Ashvyth:BAAANQAECgYIEwAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAIANIcAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.',
Ba='Baconpancake:BAAANQAECgIIAwAAAA==.Baldpunch:BAAANQADCggIJwAAAA==.Balinor:BAAANQAECgIIAgAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgQICAAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgQICAAJAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAAANQAECgUIDAAAAA==.Beaj:BAAANQAECgIIAwAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAAANQAECgUIDwAAAA==.Bigblingaxe:BAAANQADCgEIAQAAAA==.Bilac:BAAANQADCgEIAQABNQAECggIJAAKAK0SAA==.',
Bl='Blusoleil:BAAANQAECgIIAgAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECoEfAAQBAAgK0xhiKgATAgABAAgKzBZiKgATAgALAAMKKBAUkACjAAAMAAIK1BhXpQCGAAAAAA==.',
Br='Branches:BAABNQAECoEaAAMNAAcKpw2PLwBpAQANAAcKpw2PLwBpAQAOAAcK1QqqUgBlAQAAAA==.Brewtholomew:BAAANQAECgYIEAAAAA==.Briggsey:BAAANQAECgYIDwAAAA==.Briznot:BAAANQAECgYIDAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBAAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgYIDQAAAA==.',
Bu='Bubbadubya:BAAANQADCgYIHAAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQADCgcIGQABNQAECggIJAAKAK0SAA==.Burningwolf:BAAANQAECgUIEQAAAA==.',
['Bó']='Bórs:BAAANQAECgQICQAAAA==.',
Ca='Caiden:BAAANQAECgIIAgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgYIFwAAAA==.Calesona:BAAANQAECgIIAgAAAA==.Carnìfex:BAAANQAECgIIAgAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAAANQAECgYIDQAAAA==.',
Ce='Cerà:BAAANQAECgQIDAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgYIDQAAAA==.',
Cl='Clizee:BAAANQAECgQICAAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQAECgQICAAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Constellate:BAAANQAECgYIEAAAAA==.Cotterpins:BAAANQAECgYIBwAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECoEiAAMFAAgKjRgiQQBGAgAFAAgKjRgiQQBGAgAEAAMKXAw92wCIAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgUICgAJAAAAAA==.Damnitsu:BAEANQAECgUICgAAAA==.Darckside:BAAANQADCgUIBQAAAA==.Dazen:BAAANQADCgYIDQAAAA==.',
De='Deadflexy:BAAANQAECgYIDAAAAA==.Deathberry:BAABNQAECoEbAAIPAAcK2xsJWwAkAgAPAAcK2xsJWwAkAgAAAA==.Deathdoodles:BAAANQAECgUIDAABNQAECgkJIwAQAFQYAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgQIBQAAAA==.Dejavù:BAAANQAECgIIAgAAAA==.Demonblood:BAAANQAECgcIEgAAAA==.Demonicmac:BAAANQADCgMJAwABNQAECgQICAAJAAAAAA==.Deräth:BAAANQAECgYIDwAAAA==.Devlik:BAAANQAECgEIAQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAJAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIEAAAAA==.Dionne:BAAANQAECgUIBgAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgkJHwARAG0bAA==.Ditsie:BAAANQAECgEJAQAAAA==.',
Dm='Dmega:BAAANQAECgQIDAAAAA==.',
Do='Dogfunk:BAAANQABCgcICgAAAA==.',
Dr='Dragea:BAAANQAECgUICAAAAA==.Dragondude:BAAANQAECgYIDQAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFIENAAILAAUK+RU+CgCHAQALAAUK+RU+CgCHAQA1AAQKgSQAAgsACQpgHz8WAOQCAAsACQpgHz8WAOQCAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgUIBgAAAA==.',
Dy='Dyelin:BAAANQAECgYIEwAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQADCgYIDAAAAA==.Elyron:BAAANQAECgYIEwAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECoEiAAMIAAkKQB6SCAAmAgARAAkKNRqARQDqAgAIAAcKbh6SCAAmAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgIIAgAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgYIFwAJAAAAAA==.Ezind:BAAANQAECgMIBAAAAA==.',
Fa='Fakename:BAAANQAECgUICQAAAA==.Fakesaint:BAABNQAECoEmAAIEAAgKPCNIEgAeAwAEAAgKPCNIEgAeAwAAAA==.Fangstorm:BAAANQAECgYIEwAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgEIAQAAAA==.',
Fe='Feldruid:BAAANQAECgQICwAAAA==.Felup:BAABNQAECoEiAAQPAAcKsh+yQgBtAgAPAAcKYR+yQgBtAgASAAIK+xF1UQB/AAATAAEK5BsPJgBDAAAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAAANQAECgcIDAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECoEbAAIUAAgKDQ7NDADHAQAUAAgKDQ7NDADHAQAAAA==.Fuzzwig:BAAANQADCgYIDAAAAA==.',
Ga='Gaska:BAAANQAECgYIBgABNQAECgUIDAAJAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgUIAgABNQAECgYICwAJAAAAAA==.',
Gr='Graxus:BAAANQAECgIIAgAAAA==.Greth:BAAANQADCggIHQAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.',
Gu='Gudge:BAABNQAECoEkAAMKAAgKrRIICQDMAQAKAAgKrRIICQDMAQAVAAEK8wFpTgAeAAAAAA==.Gummypenguin:BAABNQAECoEZAAIWAAkKfSDSNQCnAgAWAAkKfSDSNQCnAgABNQAFFAQIDAAWAFEkAA==.',
Ha='Hadhox:BAAANQAECgEIAQABNQAECgYIEQAJAAAAAA==.Hathdox:BAAANQAECgYIEQAAAA==.Hawkulees:BAAANQADCgYIGAAAAA==.Hazelnoot:BAABNQAECoEjAAIGAAgKQB/DRAChAgAGAAgKQB/DRAChAgAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgEIAgAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAAANQAECgYIDwAAAA==.',
Hi='Hitsuryu:BAAANQAECgUIEQAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECoEaAAMXAAkK2AtlMQDhAQAXAAgK6wxlMQDhAQAYAAYKLASrEAD0AAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgMJBAAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAJAAAAAA==.Hornsharp:BAAANQAECgIIAgAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECggIJAAKAK0SAA==.Hunilla:BAAANQAECgUIDAABNQAECggIJAAKAK0SAA==.',
Ia='Iamu:BAAANQADCgYIEwAAAA==.',
Ib='Ibris:BAAANQADCgYIDQAAAA==.',
Ic='Iconius:BAAANQADCgYIDQAAAA==.',
Ie='Ieatwetsocks:BAABNQAECoEbAAMEAAkKrBSNSgAMAgAEAAkKrBSNSgAMAgAFAAIKWwTBAgFOAAAAAA==.',
Ig='Ignivar:BAAANQADCgYJFAAAAA==.',
In='Indra:BAAANQAECgMIBAAAAA==.Innexshaman:BAAANQAECgcIEQAAAA==.Insaint:BAABNQAECoEcAAIGAAgKORNkdwAOAgAGAAgKORNkdwAOAgAAAA==.',
Ir='Ironfield:BAABNQAECoEUAAMEAAcK4RpqSwAJAgAEAAcK4RpqSwAJAgAFAAMKFQNk7QB4AAABNQADCgUIBQAJAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgQIEQAAAA==.',
Je='Jessamine:BAABNQAECoEkAAIRAAgKXhFBrwACAgARAAgKXhFBrwACAgAAAA==.Jetta:BAAANQAECgQIBQAAAA==.Jezzak:BAABNQAECoEaAAIWAAcKjxJ7fgDhAQAWAAcKjxJ7fgDhAQABNQAECggIIAAWAF0WAA==.',
Jo='John:BAABNQAECoE4AAIYAAgKvSSoAQBaAwAYAAgKvSSoAQBaAwAAAA==.Jorien:BAABNQAECoEfAAIWAAgKhRzcOwCTAgAWAAgKhRzcOwCTAgAAAA==.',
Jp='Jp:BAAANQAECgUIBwAAAA==.Jpd:BAAANQAECgQIBAABNQAECgUIBwAJAAAAAA==.',
Ju='Justadwarf:BAAANQAECgYIBQAAAA==.Justatsuj:BAAANQAECgQIBAAAAA==.Juston:BAAANQAECgUIBQAAAA==.',
Ka='Kaboonsky:BAAANQAECgYIEQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIJAgAAAA==.Kamikori:BAAANQAECgUIEQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAJAAAAAA==.Karnadaz:BAABNQAECoEhAAIHAAkKChqgTwCAAgAHAAkKChqgTwCAAgAAAA==.Karnkarn:BAAANQAECgYICgAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgIIAgAJAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECoEXAAIEAAcKRCPQKQCZAgAEAAcKRCPQKQCZAgAAAA==.',
Ko='Kolosho:BAAANQAECgYIBgAAAA==.Korxana:BAABNQAECoEVAAIZAAcKNA6zKQBkAQAZAAcKNA6zKQBkAQAAAA==.Korxon:BAABNQAECoEjAAIQAAkKahaMLwCJAgAQAAkKahaMLwCJAgAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQAECgUIBgAAAA==.',
Ky='Kyfess:BAAANQAECgMIBAAAAA==.',
['Kä']='Kämi:BAAANQADCgYICgABNQAECgQIBQAJAAAAAA==.',
La='Lanuadra:BAABNQAECoEkAAICAAgKlxZREgBMAgACAAgKlxZREgBMAgAAAA==.Lawry:BAAANQAECgYICwAAAA==.Layhee:BAAANQAFFAEIAQAAAA==.',
Le='Leasidhe:BAAANQADCgcJDgABNQADCgQIBAAJAAAAAA==.Lethalbimbo:BAAANQADCgcIDgAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQABCgQIBAABNQADCgcIBwAJAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFIESAAIEAAUKfRwUBwDJAQAEAAUKfRwUBwDJAQA1AAQKgSgAAwQACQpwIYgiAL8CAAQACQpwIYgiAL8CAAUACApqEhNZAOoBAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgQIBwAAAA==.',
Lo='Lomea:BAAANQADCgYIBgABNQADCgYIDAAJAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQABCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgUIDAAJAAAAAA==.',
['Lø']='Løllîe:BAAANQAECgIIBQAAAA==.',
Ma='Macarius:BAAANQAECgYIDAAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAAJAAAAAA==.Magatai:BAAANQAECgEIAQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAJAAAAAA==.Manaster:BAAANQAECgIIAwAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgIIAwAAAA==.Mathas:BAAANQAECgEIAgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQADCgYIEgAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgYIGQAAAA==.',
Me='Meanwhile:BAAANQADCgUIAgAAAA==.Meowmixx:BAAANQABCgUIBwAAAA==.Merkii:BAAANQADCgYIBgABNQAECggIGgAXAEsbAA==.',
Mi='Micflinigan:BAAANQAECgYIEwAAAA==.Midnightmare:BAAANQABCgMIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgIIAgAAAA==.Ming:BAAANQADCgQIBAABNQAECggIJgAaANAfAA==.Minilove:BAAANQADCgIIAwAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgMIBAAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQIBgAAAA==.Moonshae:BAABNQAECoEgAAMaAAgKlhAKGQC/AQAaAAgKlhAKGQC/AQAbAAUK/xcFMQBYAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgIIAgAAAA==.',
My='Mystiquè:BAAANQADCgYIHAAAAA==.',
Na='Nahmbra:BAAANQAECgIIBAAAAA==.Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Naviriel:BAAANQADCgYIBAABNQAECgYICAAJAAAAAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQAECgQICAABNQAECgkJLwAHAEobAA==.',
No='Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFIEJAAIZAAcK0w+IAgDSAQAZAAcK0w+IAgDSAQA1AAQKgRgAAhkACQodJCADAIQDABkACQodJCADAIQDAAAA.Norgaladwen:BAAANQADCggICgAAAA==.Noriisa:BAABNQAECoEgAAIWAAgKXRZUSwBkAgAWAAgKXRZUSwBkAgAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAABNQAECoEWAAIEAAcKHxYCWwDQAQAEAAcKHxYCWwDQAQAAAA==.',
Ny='Nyvak:BAAANQAECgQIBAAAAA==.',
Od='Odinhand:BAABNQAECoEhAAIOAAcKPQoGUABzAQAOAAcKPQoGUABzAQAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYJCwAAAA==.',
Ol='Oliissa:BAAANQADCgYIHAAAAA==.',
Oz='Ozwäld:BAAANQAECgUIDgABNQAECgkJKAAcAOUfAA==.Ozwäldo:BAABNQAECoEoAAIcAAkK5R9vBQAqAwAcAAkK5R9vBQAqAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECoEfAAMRAAkKbRttZQCfAgARAAkKbRttZQCfAgAIAAIKVRLTLABvAAAAAA==.Pandóra:BAAANQADCgcIDgAAAA==.Pariousa:BAABNQAECoEjAAIXAAkKSCP1CAAyAwAXAAkKSCP1CAAyAwAAAA==.',
Pe='Peppermintxo:BAAANQAECgQIBAABNQADCgIJAgAJAAAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQADCgMIAwAAAA==.',
Pi='Pinkeepink:BAAANQAECgEIAQAAAA==.',
Po='Popacooldown:BAAANQADCgUIDwAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgYIDgAAAA==.Ralganor:BAABNQAECoEkAAILAAgK3B7+HACwAgALAAgK3B7+HACwAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECgMIAgAAAA==.Ravilan:BAAANQAECgMIBQAAAA==.Raynlight:BAAANQAECgUICAAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Rineli:BAAANQADCgcICgABNQAECgIIAgAJAAAAAA==.Ringadingg:BAABNQAECoEXAAMMAAgKiSC1FwDmAgAMAAgKiSC1FwDmAgABAAEKOBYejgA+AAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgIIBwAAAA==.',
Sa='Saladin:BAAANQADCgYICgAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgUICwAAAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECgYICwAAAA==.Scribs:BAAANQAECgYICwAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECoEXAAMFAAcKCBwSfgB5AQAFAAUKyRoSfgB5AQAEAAMKsAjw1gCRAAABNQAECgkJIAAdAOgVAA==.Severalforms:BAAANQAECggIDAABNQAECgkJIAAdAOgVAA==.Severànce:BAABNQAECoEgAAQdAAkK6BVKCwDtAQAdAAgKcRVKCwDtAQAeAAQKyxE4RgDsAAAfAAIKQBiBawCUAAAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJIAAdAOgVAA==.',
Sh='Shablammy:BAAANQAECgUIEQAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgYIDQAAAA==.Shadowson:BAAANQABCgEIAQAAAA==.Shammygand:BAAANQADCgUJBQABNQAECggIGAAgAG4ZAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECoEjAAIQAAkKVBg1JgC1AgAQAAkKVBg1JgC1AgAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECoEoAAIhAAgK9RsRCwCCAgAhAAgK9RsRCwCCAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skydragon:BAAANQADCgYIHQAAAA==.',
Sl='Slay:BAAANQAECgEJAQABNQAECggIHwALAPEeAA==.Slayful:BAAANQABCgQJBAAAAA==.Sleepydwarf:BAAANQADCggJCAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAAANQAECgYICwAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICAAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAAANQAECgUIBwAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgYIBwAJAAAAAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCgYIGwAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIIBQAfAOIcAA==.Stubly:BAAANQADCgQJBAAAAA==.',
Su='Sunfyrie:BAAANQAECgUIDAAAAA==.',
Sw='Sweèt:BAAANQAECgIIAQAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgIIAwAAAA==.Taurdk:BAAANQAECgYIDQAAAA==.Taylorshift:BAABNQAECoEhAAIOAAkKHh6zEwAVAwAOAAkKHh6zEwAVAwAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECggIHwALAPEeAA==.Teetau:BAAANQAECgYIEwAAAA==.',
Th='Thadregosa:BAAANQAECgYIEAAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCgYIFQAAAA==.Thedarkskull:BAAANQABCgIIAgAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCggIJQAAAA==.Timoleon:BAAANQAECgMIAwAAAA==.Tirna:BAAANQAECgEJAgAAAA==.Tirnotham:BAAANQAECgUICAAAAA==.',
Tm='Tmtglizzy:BAABNQAECoEYAAMEAAgKwhjHOABUAgAEAAgKwhjHOABUAgAFAAEKjws8EAE4AAAAAA==.',
To='Tokalu:BAAANQAECgYICAAAAA==.Tonjudsonson:BAACNQAFFIEJAAIhAAQKghOSAgAnAQAhAAQKghOSAgAnAQA1AAQKgSsAAiEACQoyI2ICAJADACEACQoyI2ICAJADAAAA.Torath:BAAANQADCgYJCwABNQADCgYIFQAJAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIGwAAAA==.',
Tw='Twiki:BAAANQAECgUIDAAAAA==.Twobricks:BAABNQAECoEhAAINAAcK/RRqKACrAQANAAcK/RRqKACrAQAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQAECgUIBgABNQAECgkJHwAgAFoQAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECoEhAAIZAAcKCyCIEABvAgAZAAcKCyCIEABvAgABNQABCgYIBgAJAAAAAA==.',
Ur='Urdeadtoo:BAAANQAECgUIDAAAAA==.Urlacher:BAAANQAECgIIAgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQAECgUICAAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCgYIGgAAAA==.Verlynna:BAAANQADCgEIAQAAAA==.Vertexx:BAAANQADCgYJBgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgYIDAAJAAAAAA==.Vierth:BAAANQADCgIIAgABNQADCgYIDAAJAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQADCgQIBAAAAA==.Visea:BAAANQADCgIIAgABNQADCgYIDAAJAAAAAA==.',
Vo='Voidsavage:BAAANQADCgYIFwAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgYIEwAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
Wa='Watevr:BAEANQADCgcIBwABNQAECgUICgAJAAAAAA==.',
We='Weemer:BAAANQADCgcIBwAAAA==.Wesleypipes:BAAANQAECgcIEwAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQAECgUICAAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpala:BAABNQAECoEYAAIiAAkKhxJYQwA6AgAiAAkKhxJYQwA6AgABNQAECgkJGQAEALYaAA==.Wolfmato:BAABNQAECoEXAAIEAAgKkh6KHwDPAgAEAAgKkh6KHwDPAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAAANQAECgUIEQAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQAECgYIBgAJAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgkJIwAXAEgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAUIEgAEAH0cAA==.',
Ys='Yssuplef:BAAANQAECgUIBgAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.',
Za='Zaiyra:BAAANQAECgIIAgAAAA==.Zakoor:BAAANQADCgYIFAAAAA==.Zareena:BAAANQADCgYIHAAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgYIHwAAAA==.Zekia:BAABNQAECoEaAAIWAAcKZxkdYAAtAgAWAAcKZxkdYAAtAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergul:BAAANQABCgQIBAAAAA==.Zerm:BAABNQAECoEcAAIGAAgKERNFfQD/AQAGAAgKERNFfQD/AQAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAAANQAECgUIBgAAAA==.',
Zo='Zorsa:BAAANQAECgEIAQAAAA==.',
Zu='Zuljawn:BAAANQAECgYIEwAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIJgAAAA==.',
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
