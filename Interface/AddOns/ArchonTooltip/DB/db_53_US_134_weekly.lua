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

local lookup = {'Druid-Guardian','Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Feral','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Frost','Paladin-Holy','Evoker-Preservation','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Druid-Restoration','Paladin-Retribution','Priest-Discipline','DeathKnight-Unholy','Evoker-Devastation','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Shaman-Elemental','DemonHunter-Vengeance','Warlock-Affliction','DeathKnight-Frost',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abartheris:BAAANQADCgUIBQAAAA==.',
Ac='Acanoffood:BAAANQAECgUIDQAAAA==.',
Ad='Adeptus:BAEANQAECgQJBQAAAA==.',
Ae='Aeliana:BAAANQAECgUICwAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAAANQAECgcJEgAAAA==.Agriopas:BAAANQADCgEIAQABNQAECggIGQABAI8MAA==.',
Ah='Aharon:BAAANQADCgcIEgAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgQIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECggICgACAAAAAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Albus:BAABNQAECoEhAAIDAAkKXR78KwAMAwADAAkKXR78KwAMAwAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAAANQAECgYIEgAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alrya:BAAANQAECgEJAQAAAA==.Alysaliu:BAABNQAECoEgAAMEAAkKiiENFADxAgAEAAgKziENFADxAgAFAAQKBxYkJgAeAQAAAA==.',
Am='Amishmage:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Amishpaladin:BAAANQAECgIIAgAAAA==.Amory:BAAANQADCggICgABNQAECgMIAwACAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAABNQAECoEaAAIGAAgKZyIFHwD/AgAGAAgKZyIFHwD/AgAAAA==.Andromedae:BAAANQAECgMIBQAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQAECgEJAQAAAA==.Angelicshado:BAAANQABCgYIDgAAAA==.',
Ap='Apostasy:BAAANQAECgYIEAAAAA==.',
Ar='Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQADCgcIGwAAAA==.Arthrex:BAAANQAECgMJAwAAAA==.Arturias:BAAANQADCgcIEwABNQAECgcJEwACAAAAAA==.',
As='Ascendance:BAAANQADCgcIFAABNQAECgcIEAACAAAAAA==.Ashiok:BAAANQAECgEIAQAAAA==.Asmobob:BAAANQAECgQIBgAAAA==.',
At='Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAABNQAECoEbAAMHAAgKbB74BACvAgAHAAgKbB74BACvAgAIAAEKkBHceQBKAAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAAANQAECgUICQAAAA==.Avanie:BAAANQADCgcIFgAAAA==.',
Aw='Aw:BAAANQADCgYIBgABNQAECgIIBAACAAAAAA==.',
Ay='Ayhae:BAAANQADCgcIEwAAAA==.',
Az='Azurelock:BAAANQADCgYICgAAAA==.',
Ba='Babycoffee:BAAANQADCgEJAQAAAA==.Backstabath:BAAANQAECgYICQAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECgYJCQAAAA==.Bartlebe:BAAANQAECgIIAgAAAA==.Bastor:BAAANQAECgIIAgAAAA==.',
Be='Bearnekkid:BAAANQADCgYIEAABNQAECgcIEAACAAAAAA==.Bearsgomoo:BAAANQAECgUJCQAAAA==.Beneb:BAAANQADCggIDgAAAA==.Benebeorn:BAABNQAECoEiAAMJAAkK5xwfEgCbAgAJAAgKdBwfEgCbAgAKAAIKTxxOSwCyAAAAAA==.Benkinobi:BAAANQADCgYIEAAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgcIDAABNQAECgYIDgACAAAAAA==.Billyjoe:BAAANQADCggIDgAAAA==.Bittronoxus:BAAANQAECgQJEAAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgUIBwAAAA==.Bleys:BAAANQADCgYIEgABNQAECgYIEgACAAAAAA==.Blinky:BAAANQADCgQIBAAAAA==.',
Bo='Bobbysmerica:BAAANQAECgIIAwAAAA==.Bodikhan:BAAANQAECgEIAQAAAA==.Bovix:BAAANQAFFAEIAQABNQAECgkJHAADAOocAA==.',
Br='Branimir:BAAANQABCgIIAgAAAA==.Braxte:BAAANQAECgcJEgAAAA==.Breecy:BAAANQABCggIEwAAAA==.Britziola:BAAANQADCggIGAABNQAECgMIAwACAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAABNQAECoEjAAMDAAkKPB8CLAAMAwADAAkK7h4CLAAMAwALAAIK8x4XHACeAAAAAA==.Buggs:BAAANQADCgcIDQABNQAECgkJIwADADwfAA==.Buldozz:BAABNQAECoEXAAIMAAcKdhjoNwAaAgAMAAcKdhjoNwAaAgAAAA==.Burnination:BAAANQAECgQIDQAAAA==.Burnzie:BAAANQADCgYJCQAAAA==.Butterfayce:BAAANQAECgYIEgAAAA==.',
Ca='Cadastrasz:BAABNQAECoElAAINAAgKvhImFAAPAgANAAgKvhImFAAPAgAAAA==.Cae:BAAANQAECgUJDAAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAAANQAECgIIAwAAAA==.',
Ce='Ceenit:BAAANQAECgYIEQAAAA==.',
Ch='Chainedfire:BAAANQADCgYICgAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgcIHwAIAFQUAA==.Chasefury:BAAANQADCgMIAwABNQAECgcIHwAIAFQUAA==.Chasemon:BAABNQAECoEfAAMIAAcKVBS2MQDbAQAIAAcKuxO2MQDbAQABAAEKvxhfLgBEAAAAAA==.Chaser:BAAANQADCgUIBQABNQAECgcIHwAIAFQUAA==.Chasergoonie:BAAANQAECgEIAQABNQAECgcIHwAIAFQUAA==.Chasewise:BAAANQAECgMIAwABNQAECgcIHwAIAFQUAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAAANQAECgQJBgAAAA==.Chelsilly:BAAANQAECgUIDQAAAA==.Chelsily:BAAANQABCgIIAgAAAA==.Chicosan:BAAANQADCgYIDwAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.Chrisolski:BAAANQADCgQJBAABNQAECgQIBAACAAAAAA==.',
Co='Corien:BAAANQADCgcICQAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.Cryomara:BAAANQADCggIAgAAAA==.',
Cy='Cyndraexa:BAAANQADCgcJGwAAAA==.Cynia:BAAANQAECgQIBAAAAA==.Cyrene:BAACNQAFFIEaAAMOAAcKySRPAgAKAgAOAAUKsiBPAgAKAgAPAAQKbR+jAwCSAQA1AAQKgRsAAw4ACQqnI/MDAHwDAA4ACQqnI/MDAHwDAA8ACApkGN9MAAwCAAAA.',
Da='Daegit:BAAANQABCgIIAQAAAA==.Daizy:BAAANQADCgYIBgAAAA==.Dandien:BAAANQABCgQJBAABNQAECgcJEwACAAAAAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQADCgYICAABNQAECgYIEAACAAAAAA==.Darthbane:BAAANQADCgYIEQAAAA==.Darthvada:BAAANQAECgMJAwAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Deirdra:BAAANQADCgUIBQABNQAECgYIEgACAAAAAA==.Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAAANQAECgcJEwAAAA==.Denariah:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.Dernen:BAAANQADCgcIDgAAAA==.Derpnface:BAAANQADCgcIGwAAAA==.Desecration:BAAANQAECgYJDAABNQAECggIEwACAAAAAA==.Devilsautho:BAAANQADCggICAAAAA==.',
Di='Diablos:BAAANQABCggJEAAAAA==.Dirgir:BAAANQAECgMIBQAAAA==.Disk:BAABNQAECoEiAAQQAAgKxhewDgBaAgAQAAgKixewDgBaAgARAAUKzQ0DNwAjAQASAAIKMwPyEwBUAAAAAA==.Distonia:BAAANQAECgQIBgAAAA==.',
Dr='Dracheo:BAABNQAECoEjAAMDAAkKYBoZRwC2AgADAAkK3hkZRwC2AgALAAIKMBYvHgCKAAAAAA==.Dragonbrr:BAAANQADCgMIAwABNQAECgQJCgACAAAAAA==.Drakmore:BAAANQADCgUIBQABNQAECgIJBQACAAAAAA==.Drakonna:BAAANQAECgIJBQAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEJAgACAAAAAA==.Dreammoon:BAAANQABCgYICwAAAA==.Dreygur:BAAANQAECgQIBAAAAA==.Droiden:BAAANQAECgIIAgAAAA==.Droidetté:BAAANQAECgIIAgAAAA==.Drotar:BAAANQAECgIIAgAAAA==.',
Du='Dumbdog:BAAANQAECggIEwABNQAFFAUJCgANADgeAA==.Dumichauch:BAABNQAECoEjAAITAAkKHxkMDQCaAgATAAkKHxkMDQCaAgAAAA==.',
Eg='Egadwall:BAAANQADCgYIDAAAAA==.Eggars:BAAANQAECgQIBgAAAA==.',
Ek='Ekhor:BAAANQADCgcIFgAAAA==.',
El='Eliuwu:BAAANQADCgcIDQABNQAECgYIEgACAAAAAA==.Elyrina:BAAANQADCgQIBAABNQAECgYIEgACAAAAAA==.',
En='Enky:BAAANQAECgQICgAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Ev='Eviltiger:BAABNQAECoEaAAMPAAgKhxo/MQBuAgAPAAgKhxo/MQBuAgAOAAEKwgOSXQA2AAAAAA==.',
Ew='Ewik:BAAANQAECgcJEAAAAA==.',
Fa='Faent:BAAANQADCggIDgAAAA==.Falimonki:BAAANQADCggIDgAAAA==.Falinora:BAABNQAECoEjAAIMAAkK9RusEQD+AgAMAAkK9RusEQD+AgAAAA==.Falstad:BAAANQAECgYJDwAAAA==.Fantasticfox:BAABNQAECoEjAAMEAAgK7hLiTQDoAQAEAAcKGBPiTQDoAQAFAAQKLQeGNgDEAAAAAA==.Farindor:BAAANQABCgcICAAAAA==.Fattyx:BAABNQAECoEiAAIJAAkK5yHQAwCIAwAJAAkK5yHQAwCIAwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQACAAAAAA==.Felixs:BAAANQADCgcIGwAAAA==.Feodin:BAABNQAECoEjAAIUAAkKGiJeDQBpAwAUAAkKGiJeDQBpAwAAAA==.',
Fi='Firetaur:BAAANQADCgcJBwAAAA==.Fistariir:BAAANQADCggICAABNQAECggIFwAVAAMeAA==.Fitzchivalry:BAAANQADCgUIBQAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQACAAAAAA==.Flatsham:BAAANQADCggIFQAAAA==.Fleabag:BAAANQADCgMJAwAAAA==.',
Fo='Forcewild:BAAANQAECgQIBAAAAA==.',
Fr='Friean:BAAANQAECgYICgAAAA==.Frostitut:BAAANQAECgYIEgAAAA==.',
Fu='Furflation:BAAANQAECgQIBgAAAA==.Fuzzychunks:BAAANQADCgcIGQAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAAAAA==.Gano:BAEANQADCggIDgABNQAECgkJIAAWAKkYAA==.Garr:BAAANQADCgMJAwABNQAECgYICQACAAAAAA==.Gazdk:BAAANQAECgMIBQAAAA==.',
Ge='Geekgirl:BAAANQADCgUIBQAAAA==.',
Gi='Giliandra:BAAANQADCgEIAQAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECgcJCwACAAAAAA==.',
Gn='Gnomerci:BAAANQAECgcIAQABNQAFFAYJDwAPADkdAA==.',
Go='Goonthar:BAABNQAECoEXAAIGAAkKvCKdCgCFAwAGAAkKvCKdCgCFAwAAAA==.Gorethak:BAAANQADCgcIGgAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAAANQAECgYIDgAAAA==.Gripmedaddy:BAAANQAECgQIBQAAAA==.Grollgrr:BAAANQAECgIIBAAAAA==.Grompo:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.Grompy:BAAANQAECgIIBAAAAA==.Gruffnstuff:BAAANQADCgcIFgAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAAANQAECgQIBwAAAA==.',
Ha='Haddice:BAAANQAECgMJAwAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgQIBQACAAAAAA==.Hantoll:BAAANQABCgQIBQAAAA==.',
He='Heebiejeebie:BAAANQAECgMJBwAAAA==.Hellaeus:BAAANQAECgUICwAAAA==.Heswithme:BAAANQADCggIEAAAAA==.',
Hi='Hisokä:BAAANQAECgcJEgAAAA==.',
Ho='Holycreambar:BAAANQAECgUJCQAAAA==.Hottrikk:BAAANQABCgUJDAAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgUJBwAAAA==.Hurajin:BAAANQADCgUIDAAAAA==.',
Hy='Hydronir:BAAANQAECgEIAwABNQAFFAUJCgANADgeAA==.Hygelak:BAAANQADCggIFAAAAA==.Hypaxia:BAAANQAECgMIAwAAAA==.',
Ig='Iggysmalls:BAAANQADCgEIAQAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgIJAwAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAAANQAECgYIDgAAAA==.',
Ja='Jagons:BAAANQAECgQIBgAAAA==.Jahfar:BAAANQAECgEJAQAAAA==.Janara:BAAANQAECgEIAQAAAA==.',
Je='Jehtadin:BAAANQADCgcIBwABNQAECgYIEgACAAAAAA==.Jehtlock:BAAANQAECgYIEgAAAA==.',
Ji='Jimvisible:BAAANQAECgQIDQAAAA==.',
Jo='Johadro:BAAANQADCgYJDwAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQADCgQIBQAAAA==.',
Ka='Kahlanah:BAAANQADCggICAAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgQIBQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAAANQAECgYIEAAAAA==.Karzdormi:BAEBNQAECoEgAAMXAAkKjyIQBwDdAgAXAAgKHiIQBwDdAgANAAUKiSC+FgDiAQAAAA==.Karzsera:BAEANQADCggICAABNQAECgkJIAAXAI8iAA==.Kassicker:BAAANQADCgYIBgAAAA==.Kayyllynt:BAABNQAECoEZAAMIAAUKnBCSTwAZAQAIAAUKnBCSTwAZAQATAAIKMwtzRQBYAAAAAA==.',
Ke='Keinthdra:BAAANQAECgcIDQAAAA==.Kennaea:BAAANQADCggIDgABNQAECgkJIwADAGAaAA==.',
Ki='Kinuye:BAAANQAECgMIBgAAAA==.',
Kr='Kraio:BAAANQAECgQIBwAAAA==.',
La='Lampard:BAAANQAECgYICwAAAA==.Landarios:BAAANQADCgcIBwABNQAECgcJEwACAAAAAA==.Langtry:BAAANQAECggICgAAAA==.Laraj:BAABNQAECoEkAAIPAAgKyhbbNQBdAgAPAAgKyhbbNQBdAgAAAA==.Larissaqt:BAEBNQAECoEjAAIUAAkKgCFvFwAgAwAUAAkKgCFvFwAgAwAAAA==.Latindk:BAAANQADCgUIBQAAAA==.Latinhunter:BAAANQAECgEIAQAAAA==.Latinmonk:BAAANQADCgYIDgAAAA==.Latinshamy:BAAANQAECgIIAgAAAA==.Lavande:BAAANQAECgQIBQABNQAECggJGwAHAGweAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQADCggIFQABNQAECgkJGwAPADodAA==.Legomyagro:BAAANQAECgcJEgAAAA==.Lenipi:BAAANQADCgcIDwAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.',
Li='Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQAECgMJAwAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggJDwAAAA==.Logrey:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.Longhealz:BAAANQABCggICAAAAA==.',
Lu='Lunabellz:BAAANQAECgMJBAAAAA==.Lunavia:BAAANQAECgQIBgAAAA==.Luvalotbear:BAAANQABCgMIBAABNQAECgYJEAACAAAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lyceus:BAAANQADCgcIBwAAAA==.Lynch:BAAANQADCgUIBQAAAA==.',
Ma='Maalgus:BAAANQAECgQIBQAAAA==.Mad:BAAANQAECgEJAQAAAA==.Maery:BAAANQADCgUIBgAAAA==.Maladash:BAAANQADCgIIAgABNQAECgkJIwAUABoiAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQAECgIJAgAAAA==.Margoul:BAAANQAECgQJBwAAAA==.Marikk:BAAANQABCggIFAAAAA==.Mayyhem:BAABNQAFFIEKAAINAAUKOB7pAgD0AQANAAUKOB7pAgD0AQAAAA==.',
Mc='Mcallister:BAAANQAECgMIAwAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECgcJEgACAAAAAA==.Mcsquid:BAAANQADCgUIBQAAAA==.',
Me='Mechee:BAAANQADCgUIDQAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgcIEwAAAA==.Metch:BAAANQAECgIJAgAAAA==.',
Mi='Mimiker:BAABNQAECoEjAAMXAAkKPBzHCQCSAgAXAAgKLxvHCQCSAgANAAIKpQFrNwBKAAAAAA==.Mimilock:BAAANQADCggIFQABNQAECgkJIwAXADwcAA==.Minime:BAABNQAECoEaAAMPAAkKqyOcBACcAwAPAAkKqyOcBACcAwAOAAcKdREMIwC/AQABNQAFFAYJDwAPADkdAA==.Miniobi:BAAANQADCgYJDgAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mizahella:BAAANQAECgIJAwAAAA==.',
Mo='Mobo:BAAANQADCgcIGwAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQAECgIJAgAAAA==.Mokei:BAAANQADCgcIBwAAAA==.Mondragore:BAAANQAECgUJCwAAAA==.Moonsilver:BAAANQADCggIFwAAAA==.Moriko:BAABNQAECoEdAAIPAAgKShePNgBaAgAPAAgKShePNgBaAgAAAA==.Mourn:BAABNQAECoEjAAIYAAkKwh/0CgApAwAYAAkKwh/0CgApAwAAAA==.',
Mu='Muertomarrow:BAAANQAECgQIBAAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAAANQAECgcJEgAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.Naliannagoat:BAAANQAECgIJBAAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgIIAgACAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAAANQAECgYIEgAAAA==.Nastro:BAAANQADCgUIBgAAAA==.Naughtica:BAAANQAECgQJBwAAAA==.Navellint:BAAANQADCggIGQAAAA==.Nawticlaws:BAAANQAECgEIAQAAAA==.Nawtifox:BAAANQADCgYIBgAAAA==.Nawtishot:BAAANQAECgcIEgAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAAANQAECgQIBgAAAA==.',
Ni='Niraleth:BAAANQADCggICgAAAA==.Nitebrite:BAAANQAECgIIAgAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgYJEAAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAABNQAECoEiAAIUAAgKnh4NLACrAgAUAAgKnh4NLACrAgAAAA==.',
['Nï']='Nïssan:BAAANQAECgQIBAAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQADCgcIGQAAAA==.',
Od='Oden:BAAANQAECgIIAgAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAwABNQAECgkJIAAEAIohAA==.',
Ol='Olskimonk:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.',
Om='Omgitsashami:BAAANQAECgcJCwAAAA==.',
Op='Oprawinfury:BAAANQADCgYIBgAAAA==.',
Or='Orcanist:BAAANQAECgQJBgAAAA==.Oronarcane:BAAANQADCgcJEQAAAA==.',
Os='Osanyin:BAAANQAECgQICgAAAA==.',
Pa='Padray:BAABNQAECoEjAAIZAAkKyhfIDgCyAgAZAAkKyhfIDgCyAgAAAA==.Pamarolyn:BAAANQADCgYJBgAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pen:BAAANQAECgQICAAAAA==.Pepperbottom:BAAANQAECgUIDAAAAA==.Perforation:BAABNQAECoEYAAIPAAcKAyUCGADqAgAPAAcKAyUCGADqAgABNQAECggIEwACAAAAAA==.',
Pf='Pfft:BAAANQADCgYIDgABNQAECgcIEAACAAAAAA==.',
Ph='Phaided:BAAANQABCggIEAAAAA==.Phoebere:BAAANQAECgIIAgAAAA==.Phungi:BAAANQAECgUICwAAAA==.',
Pi='Pinocclio:BAAANQAECgQJBgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgEIAQAAAA==.Popeums:BAAANQAECgQIBgAAAA==.Poppyqtpi:BAAANQAECgQIBQAAAA==.Poyoh:BAAANQAECgYIEgAAAA==.',
Pr='Pravoce:BAAANQADCggIDgAAAA==.Propane:BAAANQAECgIIAgABNQAECgkJJQAaAIMaAA==.',
Pu='Purification:BAAANQAECgYIDAABNQAECggIEwACAAAAAA==.',
['Pí']='Pínt:BAAANQAECgIIBAAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAECgkJIwAYAMIfAA==.Raelyni:BAAANQAECgYIEgAAAA==.Rajnagaran:BAAANQADCgUJBwAAAA==.Rakkah:BAAANQAECgYIEAAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgYIEAACAAAAAA==.Raveniss:BAAANQADCgcICwAAAA==.Rawrie:BAAANQAECgMIAwAAAA==.Raygun:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.Rayzorevoker:BAAANQADCggJDQAAAA==.Rayzorlock:BAAANQAECgIJAwAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgEIAQAAAA==.Regal:BAAANQADCgcIBwAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Rh='Rhymu:BAAANQADCgUIBQAAAA==.',
Ro='Rogersoner:BAAANQAECgIIAgAAAA==.Rotation:BAAANQAECgQJBwAAAA==.Rotblade:BAAANQAECgUIDQAAAA==.Rottontomato:BAAANQADCgQJBAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMJAwAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAAANQAECgcIEAAAAA==.Sapheer:BAAANQADCgQIBgAAAA==.Saralisa:BAAANQADCgUIBQAAAA==.Sathenoth:BAAANQADCgcIEwAAAA==.Sañtoro:BAAANQADCggIHQAAAA==.',
Sc='Scy:BAAANQAECgMJAwAAAA==.',
Se='Sertraline:BAAANQADCgIIAgABNQAECggJGwAHAGweAA==.',
Sh='Shadowmorn:BAAANQAECgUICgAAAA==.Shalako:BAAANQADCgcICAAAAA==.Shambali:BAABNQAECoEaAAMTAAgKNhu4DgB9AgATAAgKNhu4DgB9AgAIAAEK8wjViAAoAAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECgcIFwAMAHYYAA==.Shandro:BAAANQAECgYIEgAAAA==.Shaniallon:BAAANQADCgcJBwABNQAECgYIEAACAAAAAA==.Shaunï:BAAANQAECgEJAQAAAA==.Showong:BAAANQAECgQICQAAAA==.',
Si='Silentbolts:BAABNQAECoEZAAIDAAkKYBRsYgBnAgADAAkKYBRsYgBnAgABNQAECgkJJAAIAFQhAA==.Silentchill:BAABNQAECoEkAAIIAAkKVCHGCQBYAwAIAAkKVCHGCQBYAwAAAA==.Silentspirit:BAAANQAECgUICQABNQAECgkJJAAIAFQhAA==.Sin:BAAANQADCggJCAABNQAECgYICQACAAAAAA==.Sinomen:BAAANQAECgIJAgABNQAECggICAACAAAAAA==.',
Sk='Skyblue:BAAANQAECgQJBgAAAA==.',
Sm='Smokebull:BAAANQADCgQIBAAAAA==.',
So='Sonarak:BAAANQAECgcJEgAAAA==.Sornafayne:BAAANQADCgcIDAAAAA==.Sorrengail:BAAANQAECgQIBAAAAA==.',
Sp='Spy:BAAANQADCgQIBAAAAA==.',
St='Stampa:BAAANQADCgcIBwAAAA==.Starcloud:BAAANQABCgQIBAAAAA==.Starrie:BAAANQAECgIJAgAAAA==.Steelhoof:BAABNQAECoEgAAIOAAgKwwIKLgBKAQAOAAgKwwIKLgBKAQAAAA==.Steil:BAAANQADCgMIBAAAAA==.Steponmyface:BAAANQAECgIJBAABNQAECgUJCQACAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAAANQAECgIIAgABNQAECgYICQACAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECgYIEgACAAAAAA==.Struckerzz:BAAANQAECgUJCAAAAA==.Struckophile:BAAANQADCgcIDQAAAA==.Struckrucker:BAAANQAECgYIEgAAAA==.',
Su='Succubussi:BAABNQAECoEZAAIEAAkKoxWsMQBYAgAEAAkKoxWsMQBYAgAAAA==.Sushie:BAAANQAECgYIBwABNQAFFAUICwAMAEQRAA==.',
Sw='Swipe:BAAANQADCggICAAAAA==.',
Sy='Synge:BAAANQABCggIFAAAAA==.Synn:BAAANQADCgQIBAABNQADCgcICAACAAAAAA==.Syrena:BAAANQABCgEJAQAAAA==.Syvina:BAAANQADCggJHQAAAA==.',
Ta='Tabby:BAAANQADCgUIBgAAAA==.Taconight:BAAANQAECgQIBAAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECgMJBQAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQADCggIEgAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCgcIFgAAAA==.Tarnished:BAAANQAECgUICQAAAA==.Tateer:BAAANQAECgEJAQAAAA==.Tateerfel:BAAANQADCgIIAgABNQAECgEJAQACAAAAAA==.Tateernugget:BAAANQADCgUICgABNQAECgEJAQACAAAAAA==.Tawneestone:BAAANQAECgcJEgAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECgUJCgAAAA==.Telandaraa:BAABNQAECoEfAAIaAAgK7x3FIgB+AgAaAAgK7x3FIgB+AgAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAABNQAECoEbAAIPAAkKOh3XEQAUAwAPAAkKOh3XEQAUAwAAAA==.Themock:BAAANQADCgcJGwAAAA==.Theresjohnny:BAAANQADCgcIEwAAAA==.Thesentinel:BAAANQADCggIEAABNQAECgcIEAACAAAAAA==.Theshift:BAABNQAECoEcAAMaAAkKShh5FwDHAgAaAAkKShh5FwDHAgAVAAQKUQ/KDwDHAAAAAA==.Thisisjustin:BAAANQADCgcIBwAAAA==.Thoreen:BAAANQADCgUIBgAAAA==.Thrish:BAABNQAECoEhAAIPAAkK6BvGFwDrAgAPAAkK6BvGFwDrAgAAAA==.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECgkJIwAUABoiAA==.',
To='Totemiclord:BAABNQAECoEZAAIbAAcKnwnsXQB+AQAbAAcKnwnsXQB+AQAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.',
Ts='Tsavo:BAAANQAECgEIAQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgIJBAABNQAECgUJCQACAAAAAA==.',
Ty='Tyriais:BAAANQAECgQIBAAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAAANQAECgIIAwAAAA==.',
Va='Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAABNQAECoEjAAIGAAkK9xtVIgDtAgAGAAkK9xtVIgDtAgAAAA==.',
Vi='Vindenna:BAAANQAECgUJCQAAAA==.Vinge:BAEBNQAECoEgAAIWAAkKqRjZFwCrAgAWAAkKqRjZFwCrAgAAAA==.Violetxx:BAAANQAECgQJCAAAAA==.Viral:BAAANQAECgIIAgAAAA==.',
Vl='Vladi:BAAANQAECgUIBQAAAA==.',
Vo='Voltaic:BAAANQAECggIEwAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAAANQAECgcJEgAAAA==.',
Vy='Vyrista:BAAANQAECgIJAgAAAA==.Vyrzeth:BAAANQADCgUIBgAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQADCgYIBgAAAA==.Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQADCggIEAAAAA==.Wartooth:BAAANQAECgEJAQAAAA==.Waycaps:BAABNQAECoEbAAIcAAkKoB+/AQAxAwAcAAkKoB+/AQAxAwAAAA==.',
Wh='Wheresjohnny:BAAANQAECgYIEgAAAA==.',
Wi='Wiccked:BAABNQAECoEZAAIdAAcKdBV+BQDwAQAdAAcKdBV+BQDwAQAAAA==.Wildheitt:BAAANQAECgYIEgAAAA==.Windrange:BAAANQADCggIFQAAAA==.Wintérhoof:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.',
Wo='Wonderpally:BAAANQADCggJEgAAAA==.Woodscale:BAAANQADCgEIAQAAAA==.Wovenbones:BAABNQAECoEgAAMWAAgKMhEvLwD1AQAWAAgKkRAvLwD1AQAeAAgK8wgYLACTAQAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFIEPAAMPAAYKOR18AABRAgAPAAYKOR18AABRAgAOAAIKPQ2KEACRAAA1AAQKgTgAAw8ACQr9JYULAEsDAA4ACQoTJAAFAGQDAA8ACAoGJoULAEsDAAAA.',
Yu='Yuhon:BAAANQAECgMIAwAAAA==.Yupa:BAAANQAECgMJBQABNQAECggJHQAPAEoXAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgkJIAAEAIohAA==.',
Za='Zafira:BAAANQAECgYIBQAAAA==.Zainea:BAABNQAECoEmAAIaAAkKWh7PDgAIAwAaAAkKWh7PDgAIAwABNQAECgYIBQACAAAAAA==.Zarena:BAAANQADCgcICAAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECggIDAACAAAAAA==.Zelrex:BAAANQAECggIDAAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgIIAgAAAA==.',
Zh='Zhuntyr:BAAANQAECgIIAgAAAA==.',
Zi='Zierosouls:BAAANQADCgcIDAAAAA==.Ziggedion:BAAANQAECgYIEgAAAA==.Zindar:BAAANQAECgQIBgAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.',
Zo='Zolpidem:BAAANQADCgQIBAABNQAECggJGwAHAGweAA==.',
['Zò']='Zòmi:BAABNQAECoEhAAIbAAkKuiBlDQBNAwAbAAkKuiBlDQBNAwAAAA==.',
['Ár']='Áres:BAAANQAECgcJEQAAAA==.',
['Ït']='Ïtzpäpälötl:BAAANQAECgYIDgAAAA==.',
['Ðr']='Ðrstrange:BAAANQAECgIIAwAAAA==.',
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
