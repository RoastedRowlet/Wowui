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

local lookup = {'DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Druid-Guardian','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Elemental','Druid-Feral','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Preservation','Paladin-Protection','Priest-Holy','Hunter-Marksmanship','Shaman-Restoration','DeathKnight-Blood','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','DeathKnight-Frost',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abartheris:BAAANQAECgEIAQAAAA==.',
Ac='Acanoffood:BAABNQAECoEcAAIBAAcK+hQUKQDbAQABAAcK+hQUKQDbAQAAAA==.',
Ad='Adeptus:BAEANQAECgYIDwAAAA==.',
Ae='Aeliana:BAAANQAECgcIEgAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAABNQAECoEhAAQCAAgKzQ9SQQCBAQACAAYKbhFSQQCBAQADAAYKRwzHDQBMAQAEAAYKPwm0KwBJAQAAAA==.Agriopas:BAAANQADCgEIAQABNQAECggIJwAFAAYTAA==.',
Ah='Aharon:BAAANQADCggIFQAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgQIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECggIDgAGAAAAAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Alataar:BAAANQADCgMIAwAAAA==.Albus:BAABNQAECoEuAAIHAAkK6SCaJwA5AwAHAAkK6SCaJwA5AwAAAA==.Alexrogan:BAAANQADCgYIBgAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAABNQAECoEgAAIIAAgKNCHnNwDNAgAIAAgKNCHnNwDNAgAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alrya:BAAANQAECgEJAQAAAA==.Alysaliu:BAABNQAECoEhAAMJAAkKjyF2KQDGAgAJAAgK0yF2KQDGAgAKAAQKBxZzLQAMAQAAAA==.',
Am='Amishmage:BAAANQAECgMIAwABNQAECgUIBgAGAAAAAA==.Amishpaladin:BAAANQAECgUIBgAAAA==.Amory:BAAANQADCggIDgABNQAECgYICQAGAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAABNQAECoEpAAILAAkKpyNtCACrAwALAAkKpyNtCACrAwAAAA==.Andromedae:BAAANQAECgUIDgAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQAECgUIBgAAAA==.Angelicshado:BAAANQABCgYIDgAAAA==.',
Ap='Apostasy:BAAANQAECgYIEAABNQAECgcIDAAGAAAAAA==.',
Ar='Arborelai:BAAANQAECgUICAAAAA==.Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQAECgEIAQAAAA==.Arthrex:BAAANQAECgUIBwAAAA==.Arturias:BAAANQADCgcIEwABNQAECggIJAAMAMMgAA==.',
As='Ascendance:BAAANQAECgUICgABNQAECggIIwANAMkcAA==.Ashiok:BAAANQAECgQICAABNQAECggIKQAOAP0RAA==.Asmobob:BAAANQAECgYIEAAAAA==.',
At='Athenè:BAAANQAECgEIAQAAAA==.Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAABNQAECoElAAMPAAkKvhwRCACnAgAPAAgKPB8RCACnAgAQAAMKPhD7egC2AAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAAANQAECgUIEwAAAA==.Avanie:BAAANQADCggIJQAAAA==.',
Ay='Ayhae:BAAANQADCggIIgAAAA==.',
Az='Azurelock:BAAANQADCgYICwAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Backstabath:BAEANQAECgcIEAAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECgcIEQAAAA==.Bartlebe:BAAANQAECgIIAgAAAA==.Bastor:BAAANQAECgIIAgAAAA==.',
Be='Bearnekkid:BAAANQADCgYIEAABNQAECggIIwANAMkcAA==.Bearsgomoo:BAABNQAECoEbAAMRAAcKrR8SFACIAgARAAcKrR8SFACIAgAQAAcKzB23MAA2AgAAAA==.Beneb:BAAANQAECgMIAwAAAA==.Benebeorn:BAACNQAFFIEFAAMMAAMKJQptDwDOAAAMAAMKAAltDwDOAAABAAEK0QuBEgBGAAA1AAQKgSsAAwEACQpQHjcXAI0CAAEACAoJHjcXAI0CAAwAAwoEH4dTAAkBAAAA.Benkinobi:BAAANQAECgQIBwAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgcIDAABNQAECggIGgASABAYAA==.Billyjoe:BAAANQADCggIDgAAAA==.Binti:BAAANQABCgQIBAAAAA==.Bittronoxus:BAABNQAECoEjAAIHAAcKuA342QCtAQAHAAcKuA342QCtAQAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgUIBwAAAA==.Bleys:BAAANQADCgYIEgABNQAECggIIAAIAEEXAA==.Blinky:BAAANQADCgYICgAAAA==.',
Bo='Bobbysmerica:BAAANQAFFAEIAgAAAA==.Bockchoy:BAAANQADCgQIBAAAAA==.Bodikhan:BAAANQAECgIIAgAAAA==.Bovix:BAAANQAFFAIIAwABNQAECgkJHwAHAOocAA==.',
Br='Braeli:BAAANQADCgUIBQAAAA==.Branimir:BAAANQABCgIIAgAAAA==.Braxte:BAABNQAECoEhAAILAAgKWSIVKwD+AgALAAgKWSIVKwD+AgAAAA==.Breecy:BAAANQAECgUIDQAAAA==.Britziola:BAAANQAECgIIAgABNQAECgYICQAGAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAABNQAECoEvAAMHAAkK1iGZIgBIAwAHAAkKXSGZIgBIAwATAAIKux+1JgCZAAAAAA==.Buggs:BAAANQAECgUICAABNQAECgkJLwAHANYhAA==.Buldozz:BAABNQAECoEgAAIUAAgKDBovOABnAgAUAAgKDBovOABnAgAAAA==.Burnination:BAABNQAECoEbAAITAAcKjCSMAwDnAgATAAcKjCSMAwDnAgAAAA==.Burnzie:BAAANQAECgEIAQAAAA==.Butterfayce:BAABNQAECoEgAAMUAAgKlRdyRgAtAgAUAAgKlRdyRgAtAgAIAAUKFhHY6QAOAQAAAA==.',
Ca='Cadastrasz:BAABNQAECoE8AAIVAAgKkhXaFgAzAgAVAAgKkhXaFgAzAgAAAA==.Cae:BAAANQAECgcIDgAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAAANQAECgYIDgAAAA==.',
Ce='Ceenit:BAABNQAECoEiAAMIAAgKuhdjZgA7AgAIAAgKuhdjZgA7AgAWAAQKDQdySwCRAAAAAA==.',
Ch='Chainedfire:BAAANQADCggIEAAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgcIMAAPAKQZAA==.Chasefury:BAAANQADCgMIAwABNQAECgcIMAAPAKQZAA==.Chasemon:BAABNQAECoEwAAQPAAcKpBm9EwCIAQAQAAcKbBcnOwDvAQAPAAUK/Ri9EwCIAQAFAAIKiRp6OgCOAAAAAA==.Chaser:BAAANQADCgUIBQABNQAECgcIMAAPAKQZAA==.Chasergoonie:BAAANQAECgEIAQABNQAECgcIMAAPAKQZAA==.Chasewise:BAAANQAECgQIBwABNQAECgcIMAAPAKQZAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAAANQAECgUIDwAAAA==.Chelsilly:BAABNQAECoEbAAIXAAcKmRlITQAUAgAXAAcKmRlITQAUAgAAAA==.Chelsily:BAAANQADCggIDgAAAA==.Chicosan:BAAANQADCgcIEgAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.Chrisolski:BAAANQADCgQIBAABNQAECgQIBAAGAAAAAA==.',
Co='Corien:BAAANQAECgEIAQAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.Cryomara:BAAANQADCggICAAAAA==.',
Cu='Cutiepotooti:BAAANQAECgQIBAAAAA==.',
Cy='Cycosis:BAAANQADCgYIBgAAAA==.Cyndraexa:BAAANQAECgEIAQAAAA==.Cynia:BAAANQAECgUICQAAAA==.Cyrene:BAACNQAFFIEmAAMSAAcKwiWDAACeAgASAAYKuCWDAACeAgAYAAUKZiGlBAD5AQA1AAQKgR8AAxgACQrWI0IGAGIDABgACQrWI0IGAGIDABIACQo/F7FjACMCAAAA.',
Da='Daegit:BAAANQABCgIIAQAAAA==.Dagoata:BAAANQADCggIDwAAAA==.Daizy:BAAANQAECgEIAQAAAA==.Dandien:BAAANQADCgEIAQABNQAECggIJAAMAMMgAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQAECgUIBQABNQAECgkJIQACAE0ZAA==.Darthbane:BAAANQAECgEIAQAAAA==.Darthvada:BAAANQAECgUICQAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Deirdra:BAAANQADCgUIBQABNQAECggIIAAIAEEXAA==.Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAABNQAECoEkAAIMAAgKwyC6FADYAgAMAAgKwyC6FADYAgAAAA==.Denariah:BAAANQAECgEIAQABNQAECgUIDgAGAAAAAA==.Dernen:BAAANQAECgEIAQAAAA==.Derpnface:BAAANQAECgEIAQAAAA==.Desecration:BAABNQAECoEbAAIBAAgKBiC9DwDjAgABAAgKBiC9DwDjAgABNQAECgkJIAAZABkfAA==.Devilsautho:BAAANQADCggIDwAAAA==.',
Di='Diablos:BAAANQABCggIEAAAAA==.Dirgir:BAAANQAECgUIDgAAAA==.Disk:BAABNQAECoEuAAQEAAkKvhkQDwB4AgAEAAkK6hYQDwB4AgACAAkKMxWZHgBhAgADAAIKTwYtFwBXAAAAAA==.Distonia:BAAANQAECgUIDwAAAA==.',
Dr='Dracheo:BAABNQAECoEvAAMHAAkKNRvaXgCuAgAHAAkKsxraXgCuAgATAAIKMBY8KwB3AAAAAA==.Dragonbrr:BAAANQADCgMIAwABNQAECgQICwAGAAAAAA==.Drakmore:BAAANQAECgIIAgABNQAECgUIEgAGAAAAAA==.Drakonna:BAAANQAECgUIEgAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEJAgAGAAAAAA==.Dreammoon:BAAANQABCgYICwAAAA==.Dreygur:BAAANQAECgYICwAAAA==.Droiden:BAAANQAECgYICQAAAA==.Droidetté:BAAANQAECgQIBgAAAA==.Drotar:BAAANQAECgUIDAAAAA==.',
Du='Dumbdog:BAABNQAECoEaAAQRAAkKBB+WDADnAgARAAkKBB+WDADnAgAQAAIK9hdThQCMAAAPAAEKfBcQMgBEAAABNQAFFAYIFAAVAL8gAA==.Dumichauch:BAACNQAFFIEFAAIRAAMKDQqKCgDhAAARAAMKDQqKCgDhAAA1AAQKgS8AAhEACQoBG/kQAK4CABEACQoBG/kQAK4CAAAA.',
Eg='Egadwall:BAAANQADCggIDwAAAA==.Eggars:BAAANQAECgUIDwAAAA==.',
Ei='Eightyhd:BAAANQAECgUIBQAAAA==.',
Ek='Ekhor:BAAANQADCggIJQAAAA==.',
El='Eliuwu:BAAANQADCgcIDQABNQAECggIIAAIADQhAA==.Elyrina:BAAANQADCgQIBAABNQAECggIIAAIADQhAA==.',
En='Enky:BAAANQAECgQICgAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Eu='Euforia:BAAANQABCgMIAwAAAA==.',
Ev='Eviltiger:BAABNQAECoEpAAMSAAkK9xkLUwBPAgASAAgKJxwLUwBPAgAYAAgK8A6CKQDdAQAAAA==.',
Ew='Ewik:BAABNQAECoEfAAIVAAgKFR/oDADFAgAVAAgKFR/oDADFAgAAAA==.',
Fa='Faent:BAAANQAECgUICAAAAA==.Falimonki:BAAANQAECgUICAAAAA==.Falinora:BAACNQAFFIEFAAIUAAMKkBAYEwDvAAAUAAMKkBAYEwDvAAA1AAQKgS8AAxQACQrMHewXAAgDABQACQrMHewXAAgDAAgAAgr3FWA1AYkAAAAA.Falstad:BAABNQAECoEhAAIaAAgKUQlkXABgAQAaAAgKUQlkXABgAQAAAA==.Fantasticfox:BAABNQAECoE4AAMJAAgKZBg3SQBZAgAJAAgKZBg3SQBZAgAKAAQKzwfdPgC8AAAAAA==.Farindor:BAAANQABCgcICAAAAA==.Fattyx:BAABNQAECoEoAAIBAAkKYiP/BAB8AwABAAkKYiP/BAB8AwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQAGAAAAAA==.Felixs:BAAANQAECgEIAQAAAA==.Feodin:BAABNQAECoEvAAIIAAkK4iNkDwB/AwAIAAkK4iNkDwB/AwAAAA==.',
Fi='Firetaur:BAAANQADCgcIBwAAAA==.Fistariir:BAAANQADCggICAABNQAECggIFwAbAAMeAA==.Fitzchivalry:BAAANQAECgMIAwAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQAGAAAAAA==.Flatsham:BAAANQAECgUIBgAAAA==.Fleabag:BAAANQADCgMJAwAAAA==.',
Fo='Forcewild:BAAANQAECgUIDQAAAA==.',
Fr='Fraeja:BAAANQADCgQIBAAAAA==.Friean:BAABNQAECoEXAAITAAcKAgl2FAA9AQATAAcKAgl2FAA9AQAAAA==.Frostitut:BAABNQAECoEgAAIHAAgKcxyXbQCNAgAHAAgKcxyXbQCNAgAAAA==.',
Fu='Furflation:BAAANQAECgQICgAAAA==.Fuzzychunks:BAAANQAECgEIAQAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAAAAA==.Gano:BAEANQADCggIDgABNQAECgkJLAANAE0hAA==.Garr:BAEANQADCgMIAwABNQAECgcIEAAGAAAAAA==.Gazdk:BAAANQAECgUIDgAAAA==.',
Ge='Geekgirl:BAAANQADCgUIBQAAAA==.',
Gh='Ghevraxion:BAAANQADCgQIBAAAAA==.',
Gi='Giliandra:BAAANQADCgIIAgAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECggIFgAZAEESAA==.',
Gn='Gnomerci:BAAANQAECggIBAABNQAFFAcIGwASAPseAA==.',
Go='Goonthar:BAACNQAFFIEGAAILAAMKrxsrGQAKAQALAAMKrxsrGQAKAQA1AAQKgSEAAgsACQq2I1EMAI8DAAsACQq2I1EMAI8DAAAA.Gorethak:BAAANQAECgEIAQAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAAANQAECgcIEwAAAA==.Gripmedaddy:BAAANQAECgUIDgAAAA==.Grollgrr:BAAANQAECgIIBAAAAA==.Grompo:BAAANQAECgEIAQABNQAFFAIIAgAGAAAAAA==.Gromps:BAAANQADCgYIBgAAAA==.Grompy:BAAANQAFFAIIAgAAAA==.Gruffnstuff:BAAANQAECgEIAQAAAA==.',
Gu='Gungan:BAAANQADCgUIBQAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAABNQAECoEWAAIRAAcKZyQjDQDgAgARAAcKZyQjDQDgAgAAAA==.',
Ha='Haddice:BAAANQAECgUICQAAAA==.Hairyteeth:BAAANQAECgUICAAAAA==.Halgrad:BAEANQAECggIAwAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgUIDgAGAAAAAA==.Hantoll:BAAANQABCgQIBQAAAA==.',
He='Heebiejeebie:BAAANQAECgUIDQAAAA==.Hellaeus:BAAANQAECgYIEQAAAA==.Henne:BAEANQAECgIIAwABNQAECggIAwAGAAAAAA==.Heswithme:BAAANQADCggIEAAAAA==.',
Hi='Hisokä:BAABNQAECoEhAAIMAAgKpRHeLwD5AQAMAAgKpRHeLwD5AQAAAA==.',
Ho='Holycreambar:BAABNQAECoEaAAIIAAcKyxt8cAAgAgAIAAcKyxt8cAAgAgAAAA==.Hottrikk:BAAANQABCgYIEQAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgQIBgAGAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgUICQAAAA==.Hurajin:BAAANQADCgUIEQAAAA==.',
Hy='Hydronir:BAAANQAECgUICAABNQAFFAYIFAAVAL8gAA==.Hygelak:BAAANQAECgUICQAAAA==.Hypaxia:BAAANQAECgUIBwAAAA==.',
Ig='Iggysmalls:BAAANQADCgEIAQAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgUICAAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAABNQAECoEaAAISAAgKEBh0TgBcAgASAAgKEBh0TgBcAgAAAA==.',
Ja='Jagons:BAAANQAECgUIDQAAAA==.Jahfar:BAAANQAECgMIBAAAAA==.Janara:BAAANQAECgIIAgAAAA==.',
Je='Jehtadin:BAAANQADCgcIBwABNQAECggIIAAJAMkfAA==.Jehtlock:BAABNQAECoEgAAMJAAgKyR8WLQC4AgAJAAgKyR8WLQC4AgAKAAQKiRQSLwACAQAAAA==.Jehtstab:BAAANQADCgIIAgABNQAECggIIAAJAMkfAA==.',
Ji='Jickson:BAAANQADCgIIAQAAAA==.Jimvisible:BAAANQAECgQIDgAAAA==.',
Jo='Joan:BAAANQAECgIIAwABNQAECgkJLgAHAOkgAA==.Johadro:BAAANQAECgEIAQAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQADCgQIBQAAAA==.',
Ka='Kahlanah:BAAANQAECgUIBQAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgQICQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAABNQAECoEeAAIIAAgKNBULhADuAQAIAAgKNBULhADuAQAAAA==.Karti:BAAANQAECgMIBAAAAA==.Karzdormi:BAECNQAFFIEMAAMVAAQKRxvqDQDuAAAVAAMK0BfqDQDuAAAcAAIKDRx+CQCrAAA1AAQKgScABBwACQrZIs0JALsCABwACApZIs0JALsCABUABQqhIP4cAN4BAB0AAgoLHQwWAKgAAAAA.Karzsera:BAEANQADCggICAABNQAFFAQIDAAVAEcbAA==.Kassicker:BAAANQAECgMIAwAAAA==.Kaylly:BAAANQADCgYIBgABNQAECgcIJgAQANUQAA==.Kayyllynt:BAABNQAECoEmAAMQAAcK1RDASQCVAQAQAAcK1RDASQCVAQARAAMKWA+wUQCTAAAAAA==.Kazmas:BAAANQAECgIIAgABNQAECgQIBQAGAAAAAA==.',
Ke='Kegeraetor:BAAANQAFFAEIAQABNQAECgkJLwAaAAkiAA==.Keinthdra:BAABNQAECoEZAAMNAAkKORuDOwAOAgANAAkKORuDOwAOAgAaAAYKExFqXQBbAQAAAA==.Keliste:BAAANQADCgMIAwAAAA==.Kennaea:BAAANQADCggIDgABNQAECgkJLwAHADUbAA==.',
Kh='Khrysais:BAAANQABCgQIBAAAAA==.',
Ki='Kinuye:BAAANQAECgUIDgAAAA==.',
Kr='Kraio:BAAANQAECgUIDgAAAA==.',
La='Lamora:BAAANQADCggICAAAAA==.Lampard:BAAANQAECgYICwAAAA==.Landarios:BAAANQADCgcIDAABNQAECggIJAAMAMMgAA==.Langtry:BAAANQAECggIDgAAAA==.Laraj:BAABNQAECoExAAISAAgKyhYiWwA5AgASAAgKyhYiWwA5AgAAAA==.Larissaqt:BAECNQAFFIEOAAIIAAUKAQ08CgB3AQAIAAUKAQ08CgB3AQA1AAQKgTMAAggACQqOIvEdADUDAAgACQqOIvEdADUDAAAA.Latindk:BAAANQADCgYIDwAAAA==.Latinhunter:BAAANQAECgQICAAAAA==.Latinmonk:BAAANQADCgYIEgAAAA==.Latinshamy:BAAANQAECgUICgAAAA==.Lavande:BAAANQAECgQICQABNQAECgkJJQAPAL4cAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQAECgUICAABNQAECgkJJwASAEceAA==.Legomyagro:BAABNQAECoEgAAMHAAgKkiBoRgDoAgAHAAgKkiBoRgDoAgATAAEKDBSaOQBDAAAAAA==.Lenipi:BAAANQADCgcIDwAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.Leyez:BAAANQABCgEIAQAAAA==.',
Li='Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQAECgUICQAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggIDwAAAA==.Logrey:BAAANQAECgEIAQABNQAECgUIDgAGAAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.Loneshott:BAAANQAFFAIIAgAAAA==.Longhealz:BAAANQADCgUIBQAAAA==.Loup:BAAANQADCgQIBAAAAA==.',
Lu='Lunabellz:BAAANQAECgUICgAAAA==.Lunavia:BAAANQAECgUIDwAAAA==.Lushie:BAAANQADCgQIBAAAAA==.Luvalotbear:BAAANQAECgcIDQAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lyceus:BAAANQADCgcIBwAAAA==.Lynch:BAAANQADCgUIBgAAAA==.',
Ma='Maalgus:BAAANQAECgUIDgAAAA==.Mad:BAAANQAECgUIBgAAAA==.Maery:BAAANQADCgUIBgAAAA==.Mahota:BAAANQADCgMIAwAAAA==.Maladash:BAAANQADCgIIAgABNQAECgkJLwAIAOIjAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQAECgIJAgAAAA==.Marfach:BAAANQAECgUIBQAAAA==.Margoul:BAAANQAECgQIEwAAAA==.Marikk:BAAANQABCggIGwAAAA==.Mayyhem:BAACNQAFFIEUAAIVAAYKvyCMAgBXAgAVAAYKvyCMAgBXAgA1AAQKgR4AAxUACQrCJN4DAG4DABUACQrCJN4DAG4DABwAAwr1FsQmAN4AAAAA.',
Mc='Mcallister:BAAANQAECgYICQAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECggIIQAaAFwmAA==.Mcsquid:BAAANQADCgUIBQAAAA==.',
Me='Meatbubble:BAAANQAECgUIBQAAAA==.Mechee:BAAANQADCgYIEwAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgcIEwAAAA==.Metch:BAAANQAECgUIBwAAAA==.',
Mi='Mimiker:BAACNQAFFIEEAAIcAAMK2Ap6CADTAAAcAAMK2Ap6CADTAAA1AAQKgS8AAxwACQoHIbsEADwDABwACQoHIbsEADwDABUAAgqlAW1FAEgAAAAA.Mimilock:BAAANQAECgUICAABNQAFFAMIBAAcANgKAA==.Minime:BAABNQAECoEgAAMSAAkKKSR1DQBiAwASAAkKqyN1DQBiAwAYAAgK9hlXGgBpAgABNQAFFAcIGwASAPseAA==.Miniobi:BAAANQADCgYIFAAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mistikeye:BAAANQAECgEIAQAAAA==.Mizahella:BAAANQAECgQIDwAAAA==.',
Mo='Mobo:BAAANQAECgEIAQAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQAECgUICwAAAA==.Mokei:BAAANQADCggIDwAAAA==.Mokushi:BAAANQAECgUIBQAAAA==.Mondragore:BAABNQAECoEWAAMeAAcKJxRAGADJAQAeAAcKJxRAGADJAQAfAAIK9QiRJwBhAAAAAA==.Moriko:BAABNQAECoEeAAISAAgKkRclXAA3AgASAAgKkRclXAA3AgAAAA==.Mourn:BAABNQAECoEvAAIaAAkKCSL5CQBZAwAaAAkKCSL5CQBZAwAAAA==.',
Mu='Muertomarrow:BAAANQAECgUICQAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAABNQAECoEhAAIJAAgK/Q6rcgDfAQAJAAgK/Q6rcgDfAQAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgQIBgAGAAAAAA==.Naliannagoat:BAAANQAECgQICgAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgQIBgAGAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAABNQAECoEgAAIIAAgKQRfTdAAVAgAIAAgKQRfTdAAVAgAAAA==.Nastro:BAAANQADCgUIBgAAAA==.Naughtica:BAAANQAECgUIDgAAAA==.Navellint:BAAANQAECgUIBgAAAA==.Nawticlaws:BAAANQAECgEIAgAAAA==.Nawtifox:BAAANQAECgUICQAAAA==.Nawtishot:BAABNQAECoEhAAISAAgKbh/4LwC7AgASAAgKbh/4LwC7AgAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAAANQAECgcIEgAAAA==.',
Ni='Niraleth:BAAANQAECgcICgAAAA==.Nitebrite:BAAANQAECgUIBwAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgYJEAABNQAECgcIDQAGAAAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAABNQAECoEuAAIIAAkKcyEyGwBCAwAIAAkKcyEyGwBCAwAAAA==.',
['Nï']='Nïssan:BAAANQAECgQICAAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQAECgEIAQAAAA==.',
Od='Oden:BAAANQAECgUIBwAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAwABNQAECgkJIQAJAI8hAA==.',
Ol='Oleyander:BAAANQAECgQICAAAAA==.Olskimonk:BAAANQADCgYIBgABNQAECgQIBAAGAAAAAA==.',
Om='Omgitsashami:BAABNQAECoEWAAIZAAgKQRIxXADMAQAZAAgKQRIxXADMAQAAAA==.',
Op='Oprawinfury:BAAANQADCgYIDAAAAA==.',
Or='Orcanist:BAAANQAECgUIDwAAAA==.Oronarcane:BAAANQADCgcJEQAAAA==.',
Os='Osanyin:BAAANQAECgYIEQAAAA==.',
Pa='Pacoesfu:BAAANQAECggICAAAAA==.Padray:BAABNQAECoE1AAIgAAkKIB9kCwAaAwAgAAkKIB9kCwAaAwAAAA==.Pamarolyn:BAAANQADCgYICQAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pen:BAABNQAECoEZAAIQAAcKhAsxUQBtAQAQAAcKhAsxUQBtAQAAAA==.Pepperbottom:BAAANQAECgcIEwAAAA==.Perforation:BAABNQAECoEoAAISAAgK6SXsCgB0AwASAAgK6SXsCgB0AwABNQAECgkJIAAZABkfAA==.',
Pf='Pfft:BAAANQAECgUICQABNQAECggIIwANAMkcAA==.',
Ph='Phaedril:BAAANQADCggICAAAAA==.Phaided:BAAANQABCggIFAAAAA==.Phoebere:BAAANQAECgUICwAAAA==.Phungi:BAAANQAECgUICwAAAA==.',
Pi='Pinocclio:BAAANQAECgQICgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgQIBQAAAA==.Popeums:BAAANQAECgUIDwAAAA==.Poppyqtpi:BAAANQAECgUIDgAAAA==.Poyoh:BAABNQAECoEfAAIRAAgKvh7yEACuAgARAAgKvh7yEACuAgAAAA==.',
Pr='Pravoce:BAAANQADCggIDgAAAA==.Prescamacho:BAAANQAECgEIAQAAAA==.Prolific:BAEANQABCgYIBwABNQAECgcIEAAGAAAAAA==.Prolifichds:BAEANQAECgEIAQABNQAECgcIEAAGAAAAAA==.Propane:BAAANQAECgUIBwABNQAECgkJNQAXAKQbAA==.',
Pu='Purification:BAABNQAECoEaAAIUAAgKLxyGKQCpAgAUAAgKLxyGKQCpAgABNQAECgkJIAAZABkfAA==.',
['Pí']='Pínt:BAAANQAECgIIBAAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAECgkJLwAaAAkiAA==.Raelyni:BAABNQAECoEgAAIXAAgKqxISWwDhAQAXAAgKqxISWwDhAQAAAA==.Rajnagaran:BAAANQAECgYIBwAAAA==.Rakion:BAAANQAECgYIBgAAAA==.Rakkah:BAABNQAECoEXAAISAAcKhBmhdgD0AQASAAcKhBmhdgD0AQAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgcIFwASAIQZAA==.Raveniss:BAAANQAECgUIBQAAAA==.Rawrie:BAAANQAECgUICAAAAA==.Raygun:BAAANQADCgYIBgABNQAECgYICQAGAAAAAA==.Rayzorevoker:BAAANQADCggJDQAAAA==.Rayzorlock:BAAANQAECgYICQAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgEIAQAAAA==.Regal:BAAANQADCgcIBwAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Rh='Rhymu:BAAANQADCgUIBQAAAA==.',
Ri='Riallis:BAAANQAECgYIBgABNQAECgkJLQAXAFEfAA==.',
Ro='Rogersoner:BAAANQAECgQIBgAAAA==.Rotation:BAABNQAECoEXAAMhAAYK7hFVFQAjAQAhAAUKaRRVFQAjAQAMAAUKRAbIWwDcAAAAAA==.Rotblade:BAABNQAECoEbAAMDAAcK3hdVCAAEAgADAAcK3hdVCAAEAgACAAEKUgTNjQAsAAAAAA==.Rottontomato:BAAANQADCgQJBAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMJAwAAAA==.Ruukia:BAAANQADCgEIAQAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAABNQAECoEjAAINAAgKyRzcIgCaAgANAAgKyRzcIgCaAgAAAA==.Sapheer:BAAANQADCgQIBgAAAA==.Saralisa:BAAANQADCgUIBQAAAA==.Sathenoth:BAAANQADCgcIEwAAAA==.Sañtoro:BAAANQAECgEIAQAAAA==.',
Sc='Scy:BAAANQAECgQIBwAAAA==.',
Se='Sertraline:BAAANQADCgYIAgABNQAECgkJJQAPAL4cAA==.',
Sh='Shadowmorn:BAAANQAECgcIEQAAAA==.Shalako:BAAANQADCgcICwAAAA==.Shambali:BAABNQAECoElAAMRAAkKRBlqEQCpAgARAAkKRBlqEQCpAgAQAAEK8wgNrAAjAAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECggIIAAUAAwaAA==.Shandro:BAABNQAECoEgAAITAAgK4QoTDwCMAQATAAgK4QoTDwCMAQAAAA==.Shaniallon:BAAANQAECgcIDAAAAA==.Sharana:BAAANQADCggICAAAAA==.Shaunï:BAAANQAECgUICgAAAA==.Showong:BAABNQAECoEZAAMZAAgK9RHfWgDRAQAZAAgK9RHfWgDRAQAOAAEKAAhOJgEqAAAAAA==.',
Si='Silentbolts:BAABNQAECoEuAAIHAAkKnRkkaACZAgAHAAkKnRkkaACZAgABNQAFFAMIBQAQAB4MAA==.Silentchill:BAACNQAFFIEFAAIQAAMKHgyOFgDLAAAQAAMKHgyOFgDLAAA1AAQKgSwAAhAACQpIIvoMAFUDABAACQpIIvoMAFUDAAAA.Silentspirit:BAAANQAECggIEQABNQAFFAMIBQAQAB4MAA==.Sinomen:BAAANQAECggIEQABNQAFFAEIAQAGAAAAAA==.',
Sk='Skyblue:BAAANQAECgQJBgAAAA==.',
Sm='Smokebull:BAAANQAECgEIAQAAAA==.',
Sn='Snowdayz:BAAANQABCgMIBQAAAA==.',
So='Sonarak:BAABNQAECoEhAAIaAAgKXCa+BgCBAwAaAAgKXCa+BgCBAwAAAA==.Sornafayne:BAAANQADCggIGwAAAA==.Sorrengail:BAAANQAECgUIDQAAAA==.',
Sp='Sparklebilly:BAAANQADCggICAAAAA==.Spy:BAAANQADCgQIBAAAAA==.',
St='Stampa:BAAANQADCgcIBwAAAA==.Starcloud:BAAANQAECgYICgAAAA==.Starrie:BAAANQAECgYICQAAAA==.Steelhoof:BAABNQAECoEwAAIYAAgKfgS1OABbAQAYAAgKfgS1OABbAQAAAA==.Steil:BAAANQADCgYICgAAAA==.Steponmyface:BAAANQAECgQICgABNQAECgcIGwARAK0fAA==.Stewie:BAAANQADCgcICQABNQADCggICAAGAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAEANQAECgIIAgABNQAECgcIEAAGAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECggIIAAfAIEfAA==.Struckerzz:BAAANQAECgUICAAAAA==.Struckophile:BAAANQADCgcIDQAAAA==.Struckrucker:BAABNQAECoEgAAIfAAgKgR+jBgDBAgAfAAgKgR+jBgDBAgAAAA==.',
Su='Succubussi:BAABNQAECoElAAMJAAkK+hU5SABcAgAJAAkK+hU5SABcAgAKAAIKew2yWQBqAAAAAA==.Sushie:BAAANQAECggIEgABNQAFFAYIEgAUAJsRAA==.',
Sw='Swipe:BAAANQADCggIDwAAAA==.',
Sy='Synge:BAAANQABCggIGQAAAA==.Synn:BAAANQADCgQIBAABNQADCggIFwAGAAAAAA==.Syrena:BAAANQABCgEJAQAAAA==.Syvina:BAAANQAECgEIAQAAAA==.',
Ta='Tabby:BAAANQADCgUIBgAAAA==.Taconight:BAAANQAECgUIDAAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECgUIBwAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQADCggIEgAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCggIJQAAAA==.Tarnished:BAAANQAECgcIEgAAAA==.Tasil:BAAANQADCgUIBQABNQAECgQIBQAGAAAAAA==.Tateer:BAAANQAECgUICgAAAA==.Tateerfel:BAAANQADCgIIAgABNQAECgUICgAGAAAAAA==.Tateernugget:BAAANQADCgUICgABNQAECgUICgAGAAAAAA==.Tawneestone:BAABNQAECoEhAAIiAAgKLCEgBgDlAgAiAAgKLCEgBgDlAgAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECgUJCgAAAA==.Telandaraa:BAABNQAECoEtAAMXAAkKUR+RGwDsAgAXAAkKUR+RGwDsAgAgAAcKlA6qLQCPAQAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAABNQAECoEnAAISAAkKRx5HHAANAwASAAkKRx5HHAANAwAAAA==.Themock:BAAANQAECgEIAQAAAA==.Theresjohnny:BAAANQADCgcIEwAAAA==.Thesentinel:BAAANQAECgUICAABNQAECggIIwANAMkcAA==.Theshift:BAABNQAECoEpAAMXAAkKrx3nGwDrAgAXAAkKrx3nGwDrAgAbAAQKUQ9CFQC7AAAAAA==.Thisisjustin:BAAANQAECgIIAgAAAA==.Thoreen:BAAANQADCgUIBgAAAA==.Thrish:BAABNQAECoEtAAISAAkKaR7xHQAFAwASAAkKaR7xHQAFAwAAAA==.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECgkJLwAIAOIjAA==.',
Ti='Timothy:BAAANQADCggICAAAAA==.',
To='Totemiclord:BAABNQAECoEpAAIOAAgK/RGsVgDyAQAOAAgK/RGsVgDyAQAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgUIDgAGAAAAAA==.',
Ts='Tsavo:BAAANQAECgEIAQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgQICgABNQAECgcIGgAIAMsbAA==.',
Ty='Tyriais:BAAANQAECgUIDQAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAAANQAECgUICwAAAA==.',
Va='Valvaa:BAAANQABCgEIAQAAAA==.Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAACNQAFFIEFAAILAAMKVAeWIADBAAALAAMKVAeWIADBAAA1AAQKgS8AAgsACQp7HkcsAPgCAAsACQp7HkcsAPgCAAAA.',
Vi='Vindenna:BAAANQAECgcIEgAAAA==.Vinge:BAEBNQAECoEsAAINAAkKTSFaFQD3AgANAAkKTSFaFQD3AgAAAA==.Violetxx:BAAANQAECgYIDgAAAA==.Viral:BAAANQAECgQIBAAAAA==.Viralswine:BAAANQADCgQIBAAAAA==.',
Vl='Vladi:BAAANQAECgUIBwAAAA==.',
Vo='Volgrim:BAAANQADCggIDwAAAA==.Voltaic:BAABNQAECoEgAAMZAAkKGR/IFAANAwAZAAkKGR/IFAANAwAOAAEKLh/w/gBVAAAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAABNQAECoEhAAIZAAgKISQ7EgAfAwAZAAgKISQ7EgAfAwAAAA==.',
Vy='Vyrista:BAAANQAECgUICAAAAA==.Vyrzeth:BAAANQADCgUIBgAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQAECgIIAgAAAA==.Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQAECgQICQAAAA==.Wartooth:BAAANQAECgQICAAAAA==.Wauwen:BAAANQADCgIIAgABNQAECgYICQAGAAAAAA==.Way:BAAANQAECgUIBgAAAA==.Waycaps:BAACNQAFFIEFAAIhAAMKtxViAgDgAAAhAAMKtxViAgDgAAA1AAQKgSYAAyEACQqAISsCAE8DACEACQqAISsCAE8DAAwABQpXFZJIAE0BAAAA.',
We='Weetbix:BAAANQAECgIIAwAAAA==.',
Wh='Wheresjohnny:BAABNQAECoEgAAIaAAgKIhqQLgA9AgAaAAgKIhqQLgA9AgAAAA==.Whiteaug:BAAANQAECgEIAQABNQAFFAYIFAAVAL8gAA==.',
Wi='Wiccked:BAABNQAECoElAAIjAAgKmRezBQA/AgAjAAgKmRezBQA/AgAAAA==.Wildheitt:BAABNQAECoEgAAIUAAgK6RuMMQCEAgAUAAgK6RuMMQCEAgAAAA==.Willsky:BAAANQADCgYIBgAAAA==.Windrange:BAAANQAECgUICAAAAA==.Wintérhoof:BAAANQAECgQIBAABNQAECgYICwAGAAAAAA==.',
Wo='Wonderpally:BAAANQAECgQIBAAAAA==.Woodscale:BAAANQADCgEIAQAAAA==.Wovenbones:BAABNQAECoEwAAMNAAgK2BoCKgBuAgANAAgK2BoCKgBuAgAkAAgK8wiqQwBuAQAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFIEbAAMSAAcK+x5qAgAsAgASAAYKOR1qAgAsAgAYAAYKoxfLBAD1AQA1AAQKgToAAxgACQr9JR4HAFMDABgACQrRJB4HAFMDABIACAoGJssaABQDAAAA.',
Yu='Yuhon:BAAANQAECgMIAwAAAA==.Yupa:BAAANQAECgYIEQABNQAECggIHgASAJEXAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgkJIQAJAI8hAA==.',
Za='Zafira:BAAANQAECgYIDAAAAA==.Zainea:BAABNQAECoE0AAIXAAkKWh5wHADoAgAXAAkKWh5wHADoAgABNQAECgYIDAAGAAAAAA==.Zarena:BAAANQADCggIFwAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECgkJGQACAAsXAA==.Zelrex:BAABNQAECoEZAAMCAAkKCxdYFQCtAgACAAkKCxdYFQCtAgAEAAUKPAb8NADwAAAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgQIBAAAAA==.',
Zh='Zhuntyr:BAAANQAECgUIBwAAAA==.',
Zi='Zierosouls:BAAANQADCgcIDAAAAA==.Ziggedion:BAABNQAECoEgAAIdAAgK9xSdBwAHAgAdAAgK9xSdBwAHAgAAAA==.Zindar:BAAANQAECgUIDwAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.Ziyan:BAAANQAECgIIAgABNQAECgYIBgAGAAAAAA==.',
Zo='Zolpidem:BAAANQADCgQIBAABNQAECgkJJQAPAL4cAA==.',
Zu='Zulljyn:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAACNQAFFIEGAAIOAAMKDyGsEAAlAQAOAAMKDyGsEAAlAQA1AAQKgSkAAg4ACQpNI14NAHADAA4ACQpNI14NAHADAAAA.',
['Ár']='Áres:BAABNQAECoEbAAIkAAgKghLqMgDXAQAkAAgKghLqMgDXAQAAAA==.',
['Çò']='Çòñstàñtîñè:BAAANQABCgcICwAAAA==.',
['Ït']='Ïtzpäpälötl:BAAANQAECgYIEQAAAA==.',
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
