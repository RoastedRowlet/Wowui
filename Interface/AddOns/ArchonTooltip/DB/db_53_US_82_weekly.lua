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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Warrior-Arms','Monk-Brewmaster','Mage-Frost','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Warrior-Fury','DemonHunter-Havoc','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIEgAAAA==.',
Ae='Aegennai:BAABNQAECn8aAAIBAAYKGAUnIwAiAQABAAYKGAUnIwAiAQAAAA==.Aegondk:BAEBNQAFFH8GAAICAAMK0xnfDQD1AAACAAMK0xnfDQD1AAAAAA==.Aelias:BAAANQAECgMIAwAAAA==.Aevaela:BAABNQAECn8lAAIDAAgKgRy1EABxAgADAAgKgRy1EABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn8iAAMEAAgKiRWQMQC9AQAEAAcKFRWQMQC9AQAFAAMKnheyDgHhAAAAAA==.',
Ak='Akey:BAAANQAECgUIDAAAAQ==.Akhae:BAABNQAECn8lAAMGAAgKdBJGYgDjAQAGAAgKdBJGYgDjAQAHAAEKtwHkTAElAAAAAA==.',
Al='Albinism:BAAANQAECgQICAAAAA==.Alcadeias:BAAANQAECgEIAQAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amuria:BAAANQAECgQIBwAAAA==.',
An='Anaeda:BAABNQAECn8cAAIIAAgKrwyRuQCkAQAIAAgKrwyRuQCkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgMIBQAJAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIFgAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIEQAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQAECgYIEgAAAA==.Arthar:BAABNQAECn85AAIKAAkKwx3qOADeAgAKAAkKwx3qOADeAgAAAA==.',
As='Ashvyth:BAABNQAECn8cAAILAAcKLyCECQCFAgALAAcKLyCECQCFAgAAAA==.',
Av='Avious:BAAANQAECgQIBAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAMAOUbAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.',
Ba='Baconpancake:BAAANQAECgIIBQAAAA==.Baldpunch:BAAANQADCggILgAAAA==.Balinor:BAAANQAECgIIAgAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgUIDQAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgUIDQAJAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAAANQAECgYIEgAAAA==.Beaj:BAAANQAECgMIBgAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8YAAMNAAYKdx79XQAEAgANAAYKdx79XQAEAgAOAAIKkA60YgBwAAAAAA==.Bigblingaxe:BAAANQADCgIIAgAAAA==.Bilac:BAAANQADCgEIAQABNQAECgkJLAAPACISAA==.',
Bl='Blusoleil:BAAANQAECgMIBQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECn8kAAQCAAgK+Bq6MQAWAgACAAgKkxi6MQAWAgAQAAUK/Bq3XACZAQARAAMKsRC5mwCgAAAAAA==.',
Br='Branches:BAABNQAECn8iAAMSAAcKLQ+xVACCAQASAAcKLQ+xVACCAQATAAcKpw3QNgBhAQAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAAANQAECgYIEAAAAA==.Briggsey:BAABNQAECn8YAAIUAAcKHQl0rgBvAQAUAAcKHQl0rgBvAQAAAA==.Briznot:BAAANQAECgYIDAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBAAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgYIEwAAAA==.',
Bu='Bubbadubya:BAAANQADCgYIHAAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQAECgMIAwABNQAECgkJLAAPACISAA==.Burningwolf:BAAANQAECgYIEgAAAA==.',
['Bó']='Bórs:BAAANQAECgQICgAAAA==.',
Ca='Caiden:BAAANQAECgQIBgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgYIFwAAAA==.Calesona:BAAANQAECgIIAgAAAA==.Carnìfex:BAAANQAECgQIBQAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAAANQAECgYIDQAAAA==.',
Ce='Cerà:BAAANQAECgQIEAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgYIDQAAAA==.',
Cl='Clizee:BAAANQAECgQICgAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQAECgcIEQAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Coldtex:BAAANQAECggIAQAAAA==.Constellate:BAAANQAECgYIEwAAAA==.Cotterpins:BAAANQAECgYIBwAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECn8qAAMHAAkKBhk6MQCzAgAHAAkKBhk6MQCzAgAGAAMKXAz97wCFAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgUIDgAJAAAAAA==.Damnitsu:BAEANQAECgUIDgAAAA==.Darckside:BAAANQAECgIIAgAAAA==.Dazen:BAAANQADCgYIEwAAAA==.',
De='Deadflexy:BAAANQAECgYIDAAAAA==.Deathberry:BAABNQAECn8jAAIUAAgKPRv8TgBkAgAUAAgKPRv8TgBkAgAAAA==.Deathdoodles:BAAANQAECgYIDgABNQAECgkJKQANAFQYAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgUIBwAAAA==.Dejavù:BAAANQAFFAIIAgAAAA==.Demonblood:BAABNQAECn8XAAIRAAgKmBJ1TQC9AQARAAgKmBJ1TQC9AQAAAA==.Demonicmac:BAAANQADCgMJAwABNQAECgQICAAJAAAAAA==.Deräth:BAABNQAECn8WAAIOAAcKbAe8OgBPAQAOAAcKbAe8OgBPAQAAAA==.Devlik:BAAANQAECgMIAQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAJAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIEAAAAA==.Dionne:BAAANQAECgUIBgAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgkJHwAVACYcAA==.Ditsie:BAAANQAECgEJAQAAAA==.',
Dm='Dmega:BAAANQAECgUIEQAAAA==.',
Do='Dogfunk:BAAANQABCgcICgAAAA==.',
Dr='Dragea:BAAANQAECgUICAAAAA==.Dragondude:BAABNQAECn8WAAMWAAgKnR8oFABrAgAWAAcK4R4oFABrAgAXAAEKuQVkOwA2AAAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFH8QAAIRAAUK3RZqDQB4AQARAAUK3RZqDQB4AQA1AAQKfyUAAhEACQrCIGEbANECABEACQrCIGEbANECAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgYIDAAAAA==.',
Dy='Dyelin:BAABNQAECn8bAAIUAAcKwBlrXAA+AgAUAAcKwBlrXAA+AgAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQAECgIIAgAAAA==.Elyron:BAABNQAECn8cAAIVAAcKIRcBuAASAgAVAAcKIRcBuAASAgAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn8oAAMMAAkKfhwNCwARAgAVAAkKDBkhVQDWAgAMAAcKOR0NCwARAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgQIAgAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgYIFwAJAAAAAA==.Ezind:BAAANQAECgUICAAAAA==.',
Fa='Fakename:BAAANQAECgUICQAAAA==.Fakesaint:BAABNQAECn8pAAIGAAgKuiMfFQAjAwAGAAgKuiMfFQAjAwAAAA==.Fangstorm:BAABNQAECn8cAAIYAAcKuA33FwB3AQAYAAcKuA33FwB3AQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgMIBQAAAA==.',
Fe='Feldruid:BAAANQAECgQIDAAAAA==.Felup:BAABNQAECn8qAAQUAAgKKiFoHgAIAwAUAAgKKiFoHgAIAwAZAAIK+xGwVQB8AAAaAAEK5BtrKgBCAAAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAABNQAECn8dAAMbAAkKTQ2qYQDwAQAbAAkKTQ2qYQDwAQAIAAEKDALiwgEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8iAAIcAAgKdQ/LDgC/AQAcAAgKdQ/LDgC/AQAAAA==.Fuzzwig:BAAANQADCgcIDQAAAA==.',
Ga='Gaska:BAAANQAECgYICgABNQAECgUIDAAJAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgUIAgABNQAECgYICwAJAAAAAA==.',
Gr='Graxus:BAAANQAECgQIAgAAAA==.Greth:BAAANQADCggIHQAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.',
Gu='Gudge:BAABNQAECn8sAAMPAAkKIhIgCAAYAgAPAAkKIhIgCAAYAgAWAAEK8wFJVAAeAAAAAA==.Gummypenguin:BAABNQAECn8ZAAIFAAkKsh8zRQCaAgAFAAkKsh8zRQCaAgABNQAFFAUIEQAFAFQkAA==.',
Ha='Hadhox:BAAANQAECgIIAwABNQAECggIHAAFAF4OAA==.Halforcked:BAAANQADCgUIBQAAAA==.Hathdox:BAABNQAECn8cAAIFAAgKXg5WfQAPAgAFAAgKXg5WfQAPAgAAAA==.Hawkulees:BAAANQADCgYIGAAAAA==.Hazelnoot:BAABNQAECn8rAAIIAAkKJySYDwCLAwAIAAkKJySYDwCLAwAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgEIAgAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8XAAIdAAcKhg2LRQCUAQAdAAcKhg2LRQCUAQAAAA==.',
Hi='Hitsuryu:BAAANQAECgUIEQAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8bAAMeAAkKlw2SPQDTAQAeAAgKlw2SPQDTAQAfAAYK3gTJEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgMJBAAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAJAAAAAA==.Hornsharp:BAAANQAECgQIBQAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgkJLAAPACISAA==.Hunilla:BAAANQAECgYIEgABNQAECgkJLAAPACISAA==.',
Ia='Iamu:BAAANQADCgYIGQAAAA==.',
Ib='Ibris:BAAANQADCgYIEwAAAA==.',
Ic='Iconius:BAAANQADCgYIEwAAAA==.',
Ie='Ieatwetsocks:BAABNQAECn8dAAMGAAkKvxS4VgAKAgAGAAkKvxS4VgAKAgAHAAIKWwSsHQFOAAAAAA==.',
Ig='Ignivar:BAAANQADCggIFgAAAA==.',
In='Indra:BAAANQAECgUICAAAAA==.Innexshaman:BAABNQAECn8YAAIHAAgK5BnbQgBnAgAHAAgK5BnbQgBnAgAAAA==.Insaint:BAABNQAECn8lAAIIAAkKzxYIYAB1AgAIAAkKzxYIYAB1AgAAAA==.',
Ir='Ironfield:BAABNQAECn8VAAMGAAcKGxv6VwAGAgAGAAcKGxv6VwAGAgAHAAMKFQOsBgF3AAABNQADCgUIBQAJAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgUIEgAAAA==.',
Je='Jessamine:BAABNQAECn8tAAIVAAkKRxR8jQBkAgAVAAkKRxR8jQBkAgAAAA==.Jetta:BAAANQAECgQICAAAAA==.Jezzak:BAABNQAECn8iAAIFAAgKCBJQdQAiAgAFAAgKCBJQdQAiAgABNQAECggIJAAFAPgXAA==.',
Jo='John:BAABNQAECn8+AAIfAAkKUSSRAAC3AwAfAAkKUSSRAAC3AwAAAA==.Jorien:BAABNQAECn8nAAIFAAgK4B21QgChAgAFAAgK4B21QgChAgAAAA==.',
Jp='Jp:BAAANQAECgUIBwAAAA==.Jpb:BAAANQAECgEIAQABNQAECgUIBwAJAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgUIBwAJAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgUIBwAJAAAAAA==.',
Ju='Justadwarf:BAAANQAECgUIBgAAAA==.Justatsuj:BAAANQAECgQIBAAAAA==.Juston:BAAANQAECgYIDAAAAA==.',
Ka='Kaboonsky:BAAANQAECgcIEgAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIJAgAAAA==.Kamikori:BAAANQAECgUIEQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAJAAAAAA==.Karnadaz:BAABNQAECn8hAAIKAAkKRhqvYQBlAgAKAAkKRhqvYQBlAgAAAA==.Karnkarn:BAAANQAECgYICgAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgMIBQAJAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIGAAcKRCMnMwCRAgAGAAcKRCMnMwCRAgAAAA==.',
Ko='Kolosho:BAAANQAECgYIBgAAAA==.Korxana:BAABNQAECn8bAAIgAAgK+Q5qJQCxAQAgAAgK+Q5qJQCxAQAAAA==.Korxon:BAABNQAECn8oAAINAAkK2RbdNQCNAgANAAkK2RbdNQCNAgAAAA==.Kotus:BAAANQAECgQIBAAAAA==.',
Ks='Ksyusha:BAAANQAECgUICgAAAA==.',
Ky='Kyfess:BAAANQAECgUICAAAAA==.',
['Kä']='Kämi:BAAANQADCgYICgABNQAECgQICAAJAAAAAA==.',
La='Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgEIAQAAAA==.Lanuadra:BAABNQAECn8nAAIDAAkKphdtDwCCAgADAAkKphdtDwCCAgAAAA==.Lawry:BAAANQAECgYICwAAAA==.Layhee:BAAANQAFFAIIAwAAAA==.',
Le='Leasidhe:BAAANQADCgcJDgABNQADCgQIBAAJAAAAAA==.Lethalbimbo:BAAANQADCggIGAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQABCgQIBAABNQADCgcIBwAJAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFH8TAAIGAAUKfRy/CQCvAQAGAAUKfRy/CQCvAQA1AAQKfzAAAwYACQpwIXsrALICAAYACQpwIXsrALICAAcACAoWFcJcAAgCAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgUICAAAAA==.',
Lo='Lomea:BAAANQADCgYICQABNQAECgIIAgAJAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQABCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgYIEgAJAAAAAA==.',
['Lø']='Løllîe:BAAANQAECgQICQAAAA==.',
Ma='Macarius:BAAANQAECgYIDAAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAAJAAAAAA==.Magatai:BAAANQAECgEIAQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAJAAAAAA==.Manaster:BAAANQAECgMIBgAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgQIBgAAAA==.Mathas:BAAANQAECgEIAgAAAA==.Mathius:BAAANQAECgEIAQAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQADCgYIHQAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgYIGgAAAA==.',
Me='Meanwhile:BAAANQADCgUIAgAAAA==.Meowmixx:BAAANQADCgMIAwAAAA==.Merkii:BAAANQADCgYIBgABNQAECggIHAAeACgbAA==.',
Mi='Micflinigan:BAABNQAECn8dAAMcAAgK5BWrCgAaAgAcAAgK5BWrCgAaAgAKAAMKJg+8FgGoAAAAAA==.Midnightmare:BAAANQABCgMIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgQIBgAAAA==.Ming:BAAANQADCgQIBAABNQAECgkJLQAhAHYgAA==.Minilove:BAAANQADCgUICAAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgMIBwAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQIBgAAAA==.Moonshae:BAABNQAECn8oAAMhAAkKExITFwAIAgAhAAkKExITFwAIAgAiAAUK8hlYOABMAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgIIAgAAAA==.',
My='Mystiquè:BAAANQADCgYIHAAAAA==.',
Na='Nahmbra:BAAANQAECgIIBAAAAA==.Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQABCgQIBAAAAA==.Naviriel:BAAANQADCgYIBAABNQAECgYICAAJAAAAAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQAECgQICAABNQAECgkJOQAKAMMdAA==.',
No='Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFH8JAAIgAAcKGg1rAwDIAQAgAAcKGg1rAwDIAQA1AAQKfxgAAiAACQoTJEsEAHMDACAACQoTJEsEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgYIDAAJAAAAAA==.Noriisa:BAABNQAECn8kAAIFAAgK+BcUWwBhAgAFAAgK+BcUWwBhAgAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAABNQAECn8dAAIGAAcKGhqZVgALAgAGAAcKGhqZVgALAgAAAA==.',
Ny='Nyvak:BAAANQAECgUICQAAAA==.',
Od='Odinhand:BAABNQAECn8pAAISAAgKjgvxSgC2AQASAAgKjgvxSgC2AQAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCgYIHAAAAA==.',
Oz='Ozwäld:BAAANQAECgYIEgABNQAECgkJLQABAMEgAA==.Ozwäldo:BAABNQAECn8tAAIBAAkKwSBmBgAeAwABAAkKwSBmBgAeAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn8fAAMVAAkKJhyjeQCKAgAVAAkKJhyjeQCKAgAMAAIKVRJMMgBvAAAAAA==.Pandóra:BAAANQAECgEIAQAAAA==.Pariousa:BAABNQAECn8jAAIeAAkKzSN8DQAUAwAeAAkKzSN8DQAUAwAAAA==.',
Pe='Peppermintxo:BAAANQAECgQIBAABNQADCgIJAgAJAAAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgIIAgAAAA==.',
Pi='Pinkeepink:BAAANQAECgIIAwAAAA==.',
Po='Popacooldown:BAAANQADCgUIDwAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgYICgAAAA==.',
Pu='Puhk:BAAANQADCgcIBwAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgYIDgAAAA==.Raijù:BAAANQAECgEIAQAAAA==.Ralganor:BAABNQAECn8tAAIRAAkKyR/zEAAkAwARAAkKyR/zEAAkAwAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECgUIBgAAAA==.Ravilan:BAAANQAECgMIBQAAAA==.Raynlight:BAAANQAECgYIDgAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Rineli:BAAANQADCgcICgABNQAECgQIBgAJAAAAAA==.Ringadingg:BAABNQAECn8dAAMQAAgKGiBHGAD6AgAQAAgKGiBHGAD6AgACAAEKSCCdlwBeAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgIIBwAAAA==.',
Sa='Saladin:BAAANQADCgYICgAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgUICwAAAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECgYICwAAAA==.Scribs:BAAANQAECgYICwAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQAECggICAAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8bAAMHAAgKYxzrewCrAQAHAAYKZhrrewCrAQAGAAMKsAiF6gCRAAABNQAECgkJJgAjAJkYAA==.Severalforms:BAAANQAECggIEQABNQAECgkJJgAjAJkYAA==.Severànce:BAABNQAECn8mAAQjAAkKmRjUDQDcAQAjAAgK8RXUDQDcAQAdAAUK/BNtTgBcAQAkAAQKvBGLTgDiAAAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJJgAjAJkYAA==.',
Sh='Shablammy:BAAANQAECgUIEQAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgYIEwAAAA==.Shadowson:BAAANQABCgEIAQAAAA==.Shammygand:BAAANQADCgUJBQABNQAECgkJGwAXACQbAA==.Shanker:BAAANQADCgMIAwAAAA==.Sheephappéns:BAAANQADCgcIBwABNQAECgkJJgAjAJkYAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn8pAAINAAkKVBixLwCnAgANAAkKVBixLwCnAgAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECn8vAAIlAAgKMR4bDQCQAgAlAAgKMR4bDQCQAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skydragon:BAAANQADCggIHwAAAA==.',
Sl='Slay:BAAANQAECgEIAQABNQAECggIJwARAPYeAA==.Slayful:BAAANQABCgQJBAAAAA==.Sleepydwarf:BAAANQADCggJCAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAAANQAECgYICwAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICAAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAAANQAECgYIDAAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgYIBwAJAAAAAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCgYIGwAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIIBwAdAH8eAA==.Stubly:BAAANQADCgQJBAAAAA==.',
Su='Sunfyrie:BAAANQAECgUIEQAAAA==.',
Sw='Sweèt:BAAANQAECgIIAQAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgMIBgAAAA==.Taurdk:BAAANQAECgYIDQAAAA==.Taylorshift:BAABNQAECn8jAAISAAkKPRywFwAIAwASAAkKPRywFwAIAwAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECggIJwARAPYeAA==.Teetau:BAABNQAECn8cAAIlAAcKWQO6OQDXAAAlAAcKWQO6OQDXAAAAAA==.',
Th='Thadregosa:BAABNQAECn8ZAAIXAAcKexTZFQDsAQAXAAcKexTZFQDsAQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCggIFwAAAA==.Thedarkskull:BAAANQABCgIIAgAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCggILAAAAA==.Timoleon:BAAANQAECgMIAwAAAA==.Tirna:BAAANQAECgEJAgAAAA==.Tirnotham:BAAANQAECgUIDAAAAA==.',
Tm='Tmtglizzy:BAABNQAECn8fAAMGAAgKwhheRABNAgAGAAgKwhheRABNAgAHAAQK7xWItgAhAQAAAA==.',
To='Tokalu:BAAANQAECgYICAAAAA==.Tonjudsonson:BAACNQAFFH8NAAIlAAQK1xSCAwAjAQAlAAQK1xSCAwAjAQA1AAQKfy4AAiUACQqsIj0DAIUDACUACQqsIj0DAIUDAAAA.Torath:BAAANQADCgYJCwABNQADCggIFwAJAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIGwAAAA==.',
Tw='Twiki:BAAANQAECgUIEQAAAA==.Twobricks:BAABNQAECn8pAAITAAgKWRNkKQDQAQATAAgKWRNkKQDQAQAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQAECgUICgABNQAECgkJJQAXADsQAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn8pAAIgAAgKvR8IDgC4AgAgAAgKvR8IDgC4AgABNQABCgYICAAJAAAAAA==.',
Ur='Urdeadtoo:BAAANQAECgUIEQAAAA==.Urlacher:BAAANQAECgIIAgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQAECgUIDAAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIHAAAAA==.Verlynna:BAAANQADCgEIAQAAAA==.Vertexx:BAAANQAECgEIAQAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgYIDAAJAAAAAA==.Vierth:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQADCgQIBAAAAA==.Visea:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIGQAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgYIGQAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
Wa='Watevr:BAEANQADCgcIDgABNQAECgUIDgAJAAAAAA==.',
We='Weemer:BAAANQADCgcICwAAAA==.Wesleypipes:BAABNQAECn8bAAIGAAgKOBPIcQCyAQAGAAgKOBPIcQCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQAECgYIDQAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpala:BAABNQAECn8gAAIbAAkKhBYFNwCFAgAbAAkKhBYFNwCFAgABNQAECgkJGQAGALYaAA==.Wolfmato:BAABNQAECn8eAAIGAAgKkh44JwDFAgAGAAgKkh44JwDFAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAAANQAECgUIEQAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQAECgYIBgAJAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgkJIwAeAM0jAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAUIEwAGAH0cAA==.',
Ys='Yssuplef:BAAANQAECgUICgAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.',
Za='Zaiyra:BAAANQAECgQIBQAAAA==.Zakoor:BAAANQADCgcIFQAAAA==.Zareena:BAAANQADCgcIHQAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIIAAAAA==.Zekia:BAABNQAECn8gAAIFAAcKNRxTVQBvAgAFAAcKNRxTVQBvAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergul:BAAANQABCgQIBAAAAA==.Zerm:BAABNQAECn8kAAIIAAgKCxQffwAmAgAIAAgKCxQffwAmAgAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAAANQAECgUICgAAAA==.',
Zo='Zorsa:BAAANQAECgIIAwAAAA==.',
Zu='Zuljawn:BAABNQAECn8cAAIEAAcKxA4oNgCZAQAEAAcKxA4oNgCZAQAAAA==.',
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
