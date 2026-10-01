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

local lookup = {'Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Druid-Guardian','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Feral','Druid-Balance','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Shaman-Restoration','Druid-Restoration','DeathKnight-Blood','Priest-Discipline','Evoker-Devastation','Priest-Shadow','Priest-Holy','Monk-Brewmaster','Warrior-Protection','Shaman-Elemental','DemonHunter-Vengeance','Warlock-Affliction','DeathKnight-Frost','Evoker-Augmentation',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abartheris:BAAANQADCgYICgAAAA==.',
Ac='Acanoffood:BAAANQAECgUIEgAAAA==.',
Ad='Adeptus:BAEANQAECgUICQAAAA==.',
Ae='Aeliana:BAAANQAECgcIEgAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAABNQAECoEbAAQBAAgK+wuaDABXAQABAAYKRwyaDABXAQACAAYKPwlZKABRAQADAAMKawmfXgCbAAAAAA==.Agriopas:BAAANQADCgEIAQABNQAECggIIAAEANkQAA==.',
Ah='Aharon:BAAANQADCgcIEgAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgQIBgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECggIDgAFAAAAAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Albus:BAABNQAECoEqAAIGAAkK6SCnHABRAwAGAAkK6SCnHABRAwAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAABNQAECoEeAAIHAAgKCSDALQDUAgAHAAgKCSDALQDUAgAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alrya:BAAANQAECgEJAQAAAA==.Alysaliu:BAABNQAECoEhAAMIAAkKjyG1HQDdAgAIAAgK0yG1HQDdAgAJAAQKBxYtKgAVAQAAAA==.',
Am='Amishmage:BAAANQAECgEIAQABNQAECgIIBAAFAAAAAA==.Amishpaladin:BAAANQAECgIIBAAAAA==.Amory:BAAANQADCggIDgABNQAECgMIAwAFAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAABNQAECoEgAAIKAAgKoCLqJQD6AgAKAAgKoCLqJQD6AgAAAA==.Andromedae:BAAANQAECgQICQAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQAECgUIBgAAAA==.Angelicshado:BAAANQABCgYIDgAAAA==.',
Ap='Apostasy:BAAANQAECgYIEAABNQAECgcIBwAFAAAAAA==.',
Ar='Arborelai:BAAANQAECgMIAwAAAA==.Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQADCgcIIQAAAA==.Arthrex:BAAANQAECgUIBgAAAA==.Arturias:BAAANQADCgcIEwABNQAECggIHwALAEwgAA==.',
As='Ascendance:BAAANQAECgUIBQABNQAECggIGwAMAEEbAA==.Ashiok:BAAANQAECgMIBAAAAA==.Asmobob:BAAANQAECgQICgAAAA==.',
At='Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAABNQAECoEfAAMNAAgKmx7WBgCbAgANAAgKmx7WBgCbAgAOAAIK+RP7eQCIAAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAAANQAECgUIDgAAAA==.Avanie:BAAANQADCggIHAAAAA==.',
Aw='Aw:BAAANQADCgYIBgABNQAECgcICwAFAAAAAA==.',
Ay='Ayhae:BAAANQADCggIGQAAAA==.',
Az='Azurelock:BAAANQADCgYICwAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Backstabath:BAAANQAECgcIEAAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECgYIDwAAAA==.Bartlebe:BAAANQAECgIIAgAAAA==.Bastor:BAAANQAECgIIAgAAAA==.',
Be='Bearnekkid:BAAANQADCgYIEAABNQAECggIGwAMAEEbAA==.Bearsgomoo:BAAANQAECgYIDwAAAA==.Beneb:BAAANQAECgMIAwAAAA==.Benebeorn:BAABNQAECoEoAAMPAAkKTx6vEwCfAgAPAAgKCR6vEwCfAgALAAIKTxyEWwClAAAAAA==.Benkinobi:BAAANQAECgQIBAAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgcIDAABNQAECggIGAAQADAXAA==.Billyjoe:BAAANQADCggIDgAAAA==.Binti:BAAANQABCgQIBAAAAA==.Bittronoxus:BAAANQAECgQIEQAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgUIBwAAAA==.Bleys:BAAANQADCgYIEgABNQAECggIHgAHAMAVAA==.Blinky:BAAANQADCgYICgAAAA==.',
Bo='Bobbysmerica:BAAANQAFFAEIAQAAAA==.Bodikhan:BAAANQAECgEIAQAAAA==.Bovix:BAAANQAFFAIIAwABNQAECgkJHQAGAOocAA==.',
Br='Braeli:BAAANQADCgUIBQAAAA==.Branimir:BAAANQABCgIIAgAAAA==.Braxte:BAABNQAECoEbAAIKAAgKzCAgLQDaAgAKAAgKzCAgLQDaAgAAAA==.Breecy:BAAANQAECgUIBQAAAA==.Britziola:BAAANQADCggIHgABNQAECgMIAwAFAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAABNQAECoEsAAMGAAkKzSHYIwA4AwAGAAkKUyHYIwA4AwARAAIKux9bIACqAAAAAA==.Buggs:BAAANQAECgMIAwABNQAECgkJLAAGAM0hAA==.Buldozz:BAABNQAECoEeAAISAAgKDBrMLgBxAgASAAgKDBrMLgBxAgAAAA==.Burnination:BAAANQAECgUIEgAAAA==.Burnzie:BAAANQAECgEIAQAAAA==.Butterfayce:BAABNQAECoEeAAMSAAgKahZ5PAAzAgASAAgKahZ5PAAzAgAHAAUKFhGxyAAWAQAAAA==.',
Ca='Cadastrasz:BAABNQAECoEzAAITAAgKhxU+FAA9AgATAAgKhxU+FAA9AgAAAA==.Cae:BAAANQAECgYIDQAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAAANQAECgUICAAAAA==.',
Ce='Ceenit:BAABNQAECoEaAAMHAAcKSRlwZgAOAgAHAAcKSRlwZgAOAgAUAAQKDQemQQCWAAAAAA==.',
Ch='Chainedfire:BAAANQADCggIDQAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgcIJwAOAAkZAA==.Chasefury:BAAANQADCgMIAwABNQAECgcIJwAOAAkZAA==.Chasemon:BAABNQAECoEnAAMOAAcKCRnPMwD9AQAOAAcKRxfPMwD9AQAEAAIKhRm4LwCNAAAAAA==.Chaser:BAAANQADCgUIBQABNQAECgcIJwAOAAkZAA==.Chasergoonie:BAAANQAECgEIAQABNQAECgcIJwAOAAkZAA==.Chasewise:BAAANQAECgMIBgABNQAECgcIJwAOAAkZAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAAANQAECgQICgAAAA==.Chelsilly:BAAANQAECgUIEgAAAA==.Chelsily:BAAANQADCggICAAAAA==.Chicosan:BAAANQADCgYIDwAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.Chrisolski:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.',
Co='Corien:BAAANQADCgcIDwAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.Cryomara:BAAANQADCggICAAAAA==.',
Cy='Cyndraexa:BAAANQADCgcIIQAAAA==.Cynia:BAAANQAECgQICAAAAA==.Cyrene:BAACNQAFFIEhAAMQAAcKTyVEAACnAgAQAAYKuCVEAACnAgAVAAUKxSCTAwABAgA1AAQKgR4AAxUACQrWI4oEAHcDABUACQrWI4oEAHcDABAACQo/F2NRAC0CAAAA.',
Da='Daegit:BAAANQABCgIIAQAAAA==.Dagoata:BAAANQADCgcIBwAAAA==.Daizy:BAAANQADCgYIBgAAAA==.Dandien:BAAANQADCgEIAQABNQAECggIHwALAEwgAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQADCgYICAABNQAECggIFgADAKcUAA==.Darthbane:BAAANQAECgEIAQAAAA==.Darthvada:BAAANQAECgUICAAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Deirdra:BAAANQADCgUIBQABNQAECggIHgAHAMAVAA==.Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAABNQAECoEfAAILAAgKTCALEgDYAgALAAgKTCALEgDYAgAAAA==.Denariah:BAAANQAECgEIAQABNQAECgQICQAFAAAAAA==.Dernen:BAAANQADCgcIDgAAAA==.Derpnface:BAAANQADCgcIHQAAAA==.Desecration:BAAANQAECgYIEgABNQAECgkJGgAWAN8dAA==.Devilsautho:BAAANQADCggICAAAAA==.',
Di='Diablos:BAAANQABCggIEAAAAA==.Dirgir:BAAANQAECgQICQAAAA==.Disk:BAABNQAECoErAAQDAAkKSxnjFwBtAgADAAkK5hTjFwBtAgACAAgKixfMEQBEAgABAAIKTwZ8FQBaAAAAAA==.Distonia:BAAANQAECgQICgAAAA==.',
Dr='Dracheo:BAABNQAECoEsAAMGAAkK8BpIVACvAgAGAAkKbhpIVACvAgARAAIKMBZhJACIAAAAAA==.Dragonbrr:BAAANQADCgMIAwABNQAECgQICwAFAAAAAA==.Drakmore:BAAANQADCgUIBQABNQAECgUICgAFAAAAAA==.Drakonna:BAAANQAECgUICgAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEJAgAFAAAAAA==.Dreammoon:BAAANQABCgYICwAAAA==.Dreygur:BAAANQAECgQICAAAAA==.Droiden:BAAANQAECgYIBgAAAA==.Droidetté:BAAANQAECgQIBgAAAA==.Drotar:BAAANQAECgUIBwAAAA==.',
Du='Dumbdog:BAABNQAECoEXAAQXAAkKux5hCgDuAgAXAAkKux5hCgDuAgAOAAIK9hdzeACPAAANAAEKfBc/KQBGAAABNQAFFAUIDwATAKshAA==.Dumichauch:BAABNQAECoEsAAIXAAkKARuUDQC/AgAXAAkKARuUDQC/AgAAAA==.',
Eg='Egadwall:BAAANQADCgYIDAAAAA==.Eggars:BAAANQAECgQICgAAAA==.',
Ek='Ekhor:BAAANQADCggIHAAAAA==.',
El='Eliuwu:BAAANQADCgcIDQABNQAECggIHgAHAAkgAA==.Elyrina:BAAANQADCgQIBAABNQAECggIHgAHAAkgAA==.',
En='Enky:BAAANQAECgQICgAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Ev='Eviltiger:BAABNQAECoEhAAMQAAgKhxpiRgBOAgAQAAgKhxpiRgBOAgAVAAcKBQ0zLACVAQAAAA==.',
Ew='Ewik:BAABNQAECoEZAAITAAgKmx6bCwDGAgATAAgKmx6bCwDGAgAAAA==.',
Fa='Faent:BAAANQAECgMIAwAAAA==.Falimonki:BAAANQAECgMIAwAAAA==.Falinora:BAABNQAECoEsAAMSAAkKzB0WEwASAwASAAkKzB0WEwASAwAHAAEKYhq+MwFMAAAAAA==.Falstad:BAABNQAECoEaAAIYAAgKuwjZVQBWAQAYAAgKuwjZVQBWAQAAAA==.Fantasticfox:BAABNQAECoEvAAMIAAgKiROwYgDgAQAIAAcKbBOwYgDgAQAJAAQKzwcQOwDBAAAAAA==.Farindor:BAAANQABCgcICAAAAA==.Fattyx:BAABNQAECoElAAIPAAkKAiJFBQBwAwAPAAkKAiJFBQBwAwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQAFAAAAAA==.Felixs:BAAANQADCgcIGwAAAA==.Feodin:BAABNQAECoEsAAIHAAkK0CPcCgCQAwAHAAkK0CPcCgCQAwAAAA==.',
Fi='Firetaur:BAAANQADCgcIBwAAAA==.Fistariir:BAAANQADCggICAABNQAECggIFwAZAAMeAA==.Fitzchivalry:BAAANQAECgMIAwAAAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQAFAAAAAA==.Flatsham:BAAANQAECgUIBQAAAA==.Fleabag:BAAANQADCgMJAwAAAA==.',
Fo='Forcewild:BAAANQAECgQICAAAAA==.',
Fr='Friean:BAAANQAECgYIEAAAAA==.Frostitut:BAABNQAECoEeAAIGAAgKcxxeXACaAgAGAAgKcxxeXACaAgAAAA==.',
Fu='Furflation:BAAANQAECgQICgAAAA==.Fuzzychunks:BAAANQADCgcIHwAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAAAAA==.Gano:BAEANQADCggIDgABNQAECgkJKQAMAL4gAA==.Garr:BAAANQADCgMIAwABNQAECgcIEAAFAAAAAA==.Gazdk:BAAANQAECgQICQAAAA==.',
Ge='Geekgirl:BAAANQADCgUIBQAAAA==.',
Gh='Ghevraxion:BAAANQADCgQIBAAAAA==.',
Gi='Giliandra:BAAANQADCgEIAQAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECgcIEgAFAAAAAA==.',
Gn='Gnomerci:BAAANQAECgcIAgABNQAFFAYIFQAQAFIeAA==.',
Go='Goonthar:BAABNQAECoEfAAIKAAkKfiNFCwCKAwAKAAkKfiNFCwCKAwAAAA==.Gorethak:BAAANQADCgcIIAAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAAANQAECgcIEQAAAA==.Gripmedaddy:BAAANQAECgQICQAAAA==.Grollgrr:BAAANQAECgIIBAAAAA==.Grompo:BAAANQAECgEIAQABNQAECgcICwAFAAAAAA==.Grompy:BAAANQAECgcICwAAAA==.Gruffnstuff:BAAANQADCgcIHAAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAAANQAECgYIDgAAAA==.',
Ha='Haddice:BAAANQAECgUICAAAAA==.Hairyteeth:BAAANQAECgMIAwAAAA==.Halgrad:BAEANQAECggIAgAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgQICQAFAAAAAA==.Hantoll:BAAANQABCgQIBQAAAA==.',
He='Heebiejeebie:BAAANQAECgUIDAAAAA==.Hellaeus:BAAANQAECgYIEQAAAA==.Henne:BAEANQAECgIIAQABNQAECggIAgAFAAAAAA==.Heswithme:BAAANQADCggIEAAAAA==.',
Hi='Hisokä:BAABNQAECoEbAAILAAgKyAsAMADJAQALAAgKyAsAMADJAQAAAA==.',
Ho='Holycreambar:BAAANQAECgYIDwAAAA==.Hottrikk:BAAANQABCgYIEQAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgQIBgAFAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgUJBwAAAA==.Hurajin:BAAANQADCgUIEQAAAA==.',
Hy='Hydronir:BAAANQAECgQIBwABNQAFFAUIDwATAKshAA==.Hygelak:BAAANQAECgQIBAAAAA==.Hypaxia:BAAANQAECgMIAwAAAA==.',
Ig='Iggysmalls:BAAANQADCgEIAQAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgUICAAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAABNQAECoEYAAIQAAgKMBdYPwBlAgAQAAgKMBdYPwBlAgAAAA==.',
Ja='Jagons:BAAANQAECgQICgAAAA==.Jahfar:BAAANQAECgMIBAAAAA==.Janara:BAAANQAECgEIAQAAAA==.',
Je='Jehtadin:BAAANQADCgcIBwABNQAECggIHgAIAEseAA==.Jehtlock:BAABNQAECoEeAAMIAAgKSx6RJgC0AgAIAAgKSx6RJgC0AgAJAAQKiRScLAAGAQAAAA==.',
Ji='Jimvisible:BAAANQAECgQIDgAAAA==.',
Jo='Johadro:BAAANQADCgYIDwAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQADCgQIBQAAAA==.',
Ka='Kahlanah:BAAANQADCggICAAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgQICQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAABNQAECoEcAAIHAAgKTBRnbgD3AQAHAAgKTBRnbgD3AQAAAA==.Karti:BAAANQAECgEIAQAAAA==.Karzdormi:BAECNQAFFIEIAAMaAAQK9iAMCACxAAAaAAIKDRwMCACxAAATAAIKYRi9DQCxAAA1AAQKgSQAAxoACQrEIjgIAM8CABoACApZIjgIAM8CABMABQqhICoaAOIBAAAA.Karzsera:BAEANQADCggICAABNQAFFAQICAAaAPYgAA==.Kassicker:BAAANQAECgMIAwAAAA==.Kayyllynt:BAABNQAECoEZAAMOAAUKnBAFXAAOAQAOAAUKnBAFXAAOAQAXAAIKMwu8UgBUAAAAAA==.',
Ke='Keinthdra:BAABNQAECoEUAAMMAAgKqhk4PwC8AQAMAAgKqhk4PwC8AQAYAAYKWwm+aAAFAQAAAA==.Kennaea:BAAANQADCggIDgABNQAECgkJLAAGAPAaAA==.',
Kh='Khrysais:BAAANQABCgQIBAAAAA==.',
Ki='Kinuye:BAAANQAECgMICQAAAA==.',
Kr='Kraio:BAAANQAECgUIDAAAAA==.',
La='Lamora:BAAANQADCggICAAAAA==.Lampard:BAAANQAECgYICwAAAA==.Landarios:BAAANQADCgcIBwABNQAECggIHwALAEwgAA==.Langtry:BAAANQAECggIDgAAAA==.Laraj:BAABNQAECoEqAAIQAAgKyhZLSwA/AgAQAAgKyhZLSwA/AgAAAA==.Larissaqt:BAECNQAFFIEJAAIHAAQKRg+2CQBAAQAHAAQKRg+2CQBAAQA1AAQKgSsAAgcACQqOIvsVAEoDAAcACQqOIvsVAEoDAAAA.Latindk:BAAANQADCgUICQAAAA==.Latinhunter:BAAANQAECgMIBAAAAA==.Latinmonk:BAAANQADCgYIDgAAAA==.Latinshamy:BAAANQAECgQIBQAAAA==.Lavande:BAAANQAECgQIBQABNQAECggIHwANAJseAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQAECgMIAwABNQAECgkJJAAQACweAA==.Legomyagro:BAABNQAECoEbAAMGAAgKnB8DTADEAgAGAAgKnB8DTADEAgARAAEKDBSWMQBIAAAAAA==.Lenipi:BAAANQADCgcIDwAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.Leyez:BAAANQABCgEIAQAAAA==.',
Li='Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQAECgUICAAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggIDwAAAA==.Logrey:BAAANQAECgEIAQABNQAECgQICQAFAAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.Longhealz:BAAANQADCgUIBQAAAA==.',
Lu='Lunabellz:BAAANQAECgUICQAAAA==.Lunavia:BAAANQAECgQICgAAAA==.Luvalotbear:BAAANQAECgYIBgABNQAECgYJEAAFAAAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lyceus:BAAANQADCgcIBwAAAA==.Lynch:BAAANQADCgUIBgAAAA==.',
Ma='Maalgus:BAAANQAECgQICQAAAA==.Mad:BAAANQAECgUIBgAAAA==.Maery:BAAANQADCgUIBgAAAA==.Mahota:BAAANQADCgMIAwAAAA==.Maladash:BAAANQADCgIIAgABNQAECgkJLAAHANAjAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQAECgIJAgAAAA==.Margoul:BAAANQAECgQICwAAAA==.Marikk:BAAANQABCggIGQAAAA==.Mayyhem:BAACNQAFFIEPAAITAAUKqyHPAwAGAgATAAUKqyHPAwAGAgA1AAQKgRwAAxMACQrCJBMDAHkDABMACQrCJBMDAHkDABoAAwr1FkEjAOUAAAAA.',
Mc='Mcallister:BAAANQAECgMIAwAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECggIGwAYAOclAA==.Mcsquid:BAAANQADCgUIBQAAAA==.',
Me='Mechee:BAAANQADCgYIEwAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgcIEwAAAA==.Metch:BAAANQAECgUIBwAAAA==.',
Mi='Mimiker:BAABNQAECoEsAAMaAAkK4iC7AwBLAwAaAAkK4iC7AwBLAwATAAIKpQEYPwBKAAAAAA==.Mimilock:BAAANQAECgMIAwABNQAECgkJLAAaAOIgAA==.Minime:BAABNQAECoEdAAMQAAkKqyNuCAB8AwAQAAkKqyNuCAB8AwAVAAgKMxQOIAAQAgABNQAFFAYIFQAQAFIeAA==.Miniobi:BAAANQADCgYIFAAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mizahella:BAAANQAECgQIBwAAAA==.',
Mo='Mobo:BAAANQADCgcIGwAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQAECgQIBgAAAA==.Mokei:BAAANQADCggIDwAAAA==.Mokushi:BAAANQAECgUIBQAAAA==.Mondragore:BAAANQAECgYIEQAAAA==.Moriko:BAABNQAECoEdAAIQAAgKShdZSwA/AgAQAAgKShdZSwA/AgAAAA==.Mourn:BAABNQAECoEsAAIYAAkKMiGwCQBNAwAYAAkKMiGwCQBNAwAAAA==.',
Mu='Muertomarrow:BAAANQAECgQIBQAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAABNQAECoEbAAIIAAgKvQxNbADCAQAIAAgKvQxNbADCAQAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgQIBgAFAAAAAA==.Naliannagoat:BAAANQAECgQICAAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgQIBgAFAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAABNQAECoEeAAIHAAgKwBUfYwAYAgAHAAgKwBUfYwAYAgAAAA==.Nastro:BAAANQADCgUIBgAAAA==.Naughtica:BAAANQAECgUIDAAAAA==.Navellint:BAAANQAECgUIBQAAAA==.Nawticlaws:BAAANQAECgEIAgAAAA==.Nawtifox:BAAANQAECgUIBQAAAA==.Nawtishot:BAABNQAECoEbAAIQAAgKPx3FMACZAgAQAAgKPx3FMACZAgAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAAANQAECgUICwAAAA==.',
Ni='Niraleth:BAAANQAECgMIAwAAAA==.Nitebrite:BAAANQAECgIIAgAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgYJEAAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAABNQAECoErAAIHAAkKpx/6GwApAwAHAAkKpx/6GwApAwAAAA==.',
['Nï']='Nïssan:BAAANQAECgQICAAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQADCgcIHwAAAA==.',
Od='Oden:BAAANQAECgMIAwAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAwABNQAECgkJIQAIAI8hAA==.',
Ol='Olskimonk:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.',
Om='Omgitsashami:BAAANQAECgcIEgAAAA==.',
Op='Oprawinfury:BAAANQADCgYIBgAAAA==.',
Or='Orcanist:BAAANQAECgQICgAAAA==.Oronarcane:BAAANQADCgcJEQAAAA==.',
Os='Osanyin:BAAANQAECgQIDgAAAA==.',
Pa='Padray:BAABNQAECoEsAAIbAAkKix2VCwAEAwAbAAkKix2VCwAEAwAAAA==.Pamarolyn:BAAANQADCgYICQAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pen:BAAANQAECgYIDgAAAA==.Pepperbottom:BAAANQAECgYIEgAAAA==.Perforation:BAABNQAECoEhAAIQAAgKgyUfCgBsAwAQAAgKgyUfCgBsAwABNQAECgkJGgAWAN8dAA==.Persnalglory:BAAANQAECgYIBgAAAA==.',
Pf='Pfft:BAAANQAECgUIBQABNQAECggIGwAMAEEbAA==.',
Ph='Phaedril:BAAANQADCggICAAAAA==.Phaided:BAAANQABCggIFAAAAA==.Phoebere:BAAANQAECgMIAwAAAA==.Phungi:BAAANQAECgUICwAAAA==.',
Pi='Pinocclio:BAAANQAECgQICgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgQIBAAAAA==.Popeums:BAAANQAECgQICgAAAA==.Poppyqtpi:BAAANQAECgQICQAAAA==.Poyoh:BAABNQAECoEdAAIXAAgKvh7ADQC9AgAXAAgKvh7ADQC9AgAAAA==.',
Pr='Pravoce:BAAANQADCggIDgAAAA==.Prescamacho:BAAANQADCgYIBgAAAA==.Prolific:BAAANQABCgYIBwABNQAECgcIEAAFAAAAAA==.Propane:BAAANQAECgUIBwABNQAECgkJLgAcADYbAA==.',
Pu='Purification:BAAANQAECgYIEwABNQAECgkJGgAWAN8dAA==.',
['Pí']='Pínt:BAAANQAECgIIBAAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAECgkJLAAYADIhAA==.Raelyni:BAABNQAECoEeAAIcAAgKLBJ9TQDnAQAcAAgKLBJ9TQDnAQAAAA==.Rajnagaran:BAAANQAECgQIBAAAAA==.Rakion:BAAANQAECgYIBgAAAA==.Rakkah:BAABNQAECoEXAAIQAAcKhBk3YgD8AQAQAAcKhBk3YgD8AQAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgcIFwAQAIQZAA==.Raveniss:BAAANQADCgcICwAAAA==.Rawrie:BAAANQAECgUICAAAAA==.Raygun:BAAANQADCgYIBgABNQAECgMIAwAFAAAAAA==.Rayzorevoker:BAAANQADCggJDQAAAA==.Rayzorlock:BAAANQAECgIJAwAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgEIAQAAAA==.Regal:BAAANQADCgcIBwAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Rh='Rhymu:BAAANQADCgUIBQAAAA==.',
Ro='Rogersoner:BAAANQAECgQIBgAAAA==.Rotation:BAAANQAECgUIDAAAAA==.Rotblade:BAAANQAECgUIEgAAAA==.Rottontomato:BAAANQADCgQJBAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMJAwAAAA==.Ruukia:BAAANQADCgEIAQAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAABNQAECoEbAAIMAAgKQRsNIgByAgAMAAgKQRsNIgByAgAAAA==.Sapheer:BAAANQADCgQIBgAAAA==.Saralisa:BAAANQADCgUIBQAAAA==.Sathenoth:BAAANQADCgcIEwAAAA==.Sañtoro:BAAANQAECgEIAQAAAA==.',
Sc='Scy:BAAANQAECgQIBgAAAA==.',
Se='Sertraline:BAAANQADCgYIAgABNQAECggIHwANAJseAA==.',
Sh='Shadowmorn:BAAANQAECgYIEAAAAA==.Shalako:BAAANQADCgcICwAAAA==.Shambali:BAABNQAECoEjAAMXAAkKPBl5DgCzAgAXAAkKPBl5DgCzAgAOAAEK8wiemwAkAAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECggIHgASAAwaAA==.Shandro:BAABNQAECoEeAAIRAAgKkArqCwCtAQARAAgKkArqCwCtAQAAAA==.Shaniallon:BAAANQAECgcIBwAAAA==.Shaunï:BAAANQAECgQIBQAAAA==.Showong:BAAANQAECgQIDQAAAA==.',
Si='Silentbolts:BAABNQAECoEgAAIGAAkKyRaLYwCIAgAGAAkKyRaLYwCIAgABNQAECgkJJwAOAOghAA==.Silentchill:BAABNQAECoEnAAIOAAkK6CEuDABOAwAOAAkK6CEuDABOAwAAAA==.Silentspirit:BAAANQAECgUICQABNQAECgkJJwAOAOghAA==.Sin:BAAANQADCggICAABNQAECgcIEAAFAAAAAA==.Sinomen:BAAANQAECggICgABNQAECggICAAFAAAAAA==.',
Sk='Skyblue:BAAANQAECgQJBgAAAA==.',
Sm='Smokebull:BAAANQADCgQIBgAAAA==.',
Sn='Snowdayz:BAAANQABCgMIBQAAAA==.',
So='Sonarak:BAABNQAECoEbAAIYAAgK5yU9BwBuAwAYAAgK5yU9BwBuAwAAAA==.Sornafayne:BAAANQADCggIEgAAAA==.Sorrengail:BAAANQAECgQICAAAAA==.',
Sp='Sparklebilly:BAAANQADCggICAAAAA==.Spy:BAAANQADCgQIBAAAAA==.',
St='Stampa:BAAANQADCgcIBwAAAA==.Starcloud:BAAANQAECgQIBAAAAA==.Starrie:BAAANQAECgMIAwAAAA==.Steelhoof:BAABNQAECoEoAAIVAAgKJQSwMgBaAQAVAAgKJQSwMgBaAQAAAA==.Steil:BAAANQADCgMIBAAAAA==.Steponmyface:BAAANQAECgQICAABNQAECgYIDwAFAAAAAA==.Stewie:BAAANQADCgIIAgABNQADCggICAAFAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAAANQAECgIIAgABNQAECgcIEAAFAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECggIHgAdACYfAA==.Struckerzz:BAAANQAECgUICAAAAA==.Struckophile:BAAANQADCgcIDQAAAA==.Struckrucker:BAABNQAECoEeAAIdAAgKJh+ZBQDFAgAdAAgKJh+ZBQDFAgAAAA==.',
Su='Succubussi:BAABNQAECoEgAAMIAAkKoxWfPwBUAgAIAAkKoxWfPwBUAgAJAAIKew2YVABuAAAAAA==.Sushie:BAAANQAECgcICAABNQAFFAYIEQASAJsRAA==.',
Sw='Swipe:BAAANQADCggIDwAAAA==.',
Sy='Synge:BAAANQABCggIGQAAAA==.Synn:BAAANQADCgQIBAABNQADCggIDgAFAAAAAA==.Syrena:BAAANQABCgEJAQAAAA==.Syvina:BAAANQADCggIIwAAAA==.',
Ta='Tabby:BAAANQADCgUIBgAAAA==.Taconight:BAAANQAECgQICAAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECgMIBQAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQADCggIEgAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCggIHAAAAA==.Tarnished:BAAANQAECgYIDwAAAA==.Tasil:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.Tateer:BAAANQAECgQIBQAAAA==.Tateerfel:BAAANQADCgIIAgABNQAECgQIBQAFAAAAAA==.Tateernugget:BAAANQADCgUICgABNQAECgQIBQAFAAAAAA==.Tawneestone:BAABNQAECoEbAAIeAAgK6h+bBQDZAgAeAAgK6h+bBQDZAgAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECgUJCgAAAA==.Telandaraa:BAABNQAECoEmAAIcAAkKUR/FFAD8AgAcAAkKUR/FFAD8AgAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAABNQAECoEkAAIQAAkKLB63FgASAwAQAAkKLB63FgASAwAAAA==.Themock:BAAANQADCgcIIQAAAA==.Theresjohnny:BAAANQADCgcIEwAAAA==.Thesentinel:BAAANQAECgIIAwABNQAECggIGwAMAEEbAA==.Theshift:BAABNQAECoEgAAMcAAkKShhYIAC2AgAcAAkKShhYIAC2AgAZAAQKUQ+qEgDDAAAAAA==.Thisisjustin:BAAANQAECgIIAgAAAA==.Thoreen:BAAANQADCgUIBgAAAA==.Thrish:BAABNQAECoEqAAIQAAkKAB6CGgD8AgAQAAkKAB6CGgD8AgAAAA==.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECgkJLAAHANAjAA==.',
Ti='Timothy:BAAANQADCggICAAAAA==.',
To='Totemiclord:BAABNQAECoEhAAIfAAgKYw+0UQDhAQAfAAgKYw+0UQDhAQAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgQICQAFAAAAAA==.',
Ts='Tsavo:BAAANQAECgEIAQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgQICAABNQAECgYIDwAFAAAAAA==.',
Ty='Tyriais:BAAANQAECgUICQAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAAANQAECgMIBgAAAA==.',
Va='Valvaa:BAAANQABCgEIAQAAAA==.Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAABNQAECoEsAAIKAAkKRh7NIwADAwAKAAkKRh7NIwADAwAAAA==.',
Vi='Vindenna:BAAANQAECgYIDwAAAA==.Vinge:BAEBNQAECoEpAAIMAAkKviBMDgAcAwAMAAkKviBMDgAcAwAAAA==.Violetxx:BAAANQAECgQICAAAAA==.Viral:BAAANQAECgIIAgAAAA==.Viralswine:BAAANQADCgQIBAAAAA==.',
Vl='Vladi:BAAANQAECgUIBgAAAA==.',
Vo='Volgrim:BAAANQADCgcIBwAAAA==.Voltaic:BAABNQAECoEaAAMWAAkK3x1qEgAJAwAWAAkK3x1qEgAJAwAfAAEKLh/i5ABXAAAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAABNQAECoEbAAIWAAgKISRQDgApAwAWAAgKISRQDgApAwAAAA==.',
Vy='Vyrista:BAAANQAECgUIBwAAAA==.Vyrzeth:BAAANQADCgUIBgAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQADCgYIBgAAAA==.Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQAECgQIBQAAAA==.Wartooth:BAAANQAECgMIBAAAAA==.Way:BAAANQAECgQIBAAAAA==.Waycaps:BAABNQAECoEgAAIgAAkKgCGXAQBhAwAgAAkKgCGXAQBhAwAAAA==.',
We='Weetbix:BAAANQAECgIIAgAAAA==.',
Wh='Wheresjohnny:BAABNQAECoEeAAIYAAgK/hhPKwAwAgAYAAgK/hhPKwAwAgAAAA==.',
Wi='Wiccked:BAABNQAECoEhAAIhAAgKmRdqBABUAgAhAAgKmRdqBABUAgAAAA==.Wildheitt:BAABNQAECoEeAAISAAgK6RsQKQCOAgASAAgK6RsQKQCOAgAAAA==.Willsky:BAAANQADCgYIBgAAAA==.Windrange:BAAANQAECgMIAwAAAA==.Wintérhoof:BAAANQADCgIIAgABNQAECgQICAAFAAAAAA==.',
Wo='Wonderpally:BAAANQAECgQIBAAAAA==.Woodscale:BAAANQADCgEIAQAAAA==.Wovenbones:BAABNQAECoEoAAMMAAgKbBjRKgA1AgAMAAgKbBjRKgA1AgAiAAgK8wgVOgB3AQAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFIEVAAMQAAYKUh5OAQA0AgAQAAYKOR1OAQA0AgAVAAUKbhI4CAB6AQA1AAQKgToAAxUACQr9JSIFAG0DABUACQrRJCIFAG0DABAACAoGJlYSAC8DAAAA.',
Yu='Yuhon:BAAANQAECgMIAwAAAA==.Yupa:BAAANQAECgUICgABNQAECggJHQAQAEoXAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECgkJIQAIAI8hAA==.',
Za='Zafira:BAAANQAECgYIBQAAAA==.Zainea:BAABNQAECoEuAAIcAAkKWh64FQD2AgAcAAkKWh64FQD2AgABNQAECgYIBQAFAAAAAA==.Zarena:BAAANQADCggIDgAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECggIEQAFAAAAAA==.Zelrex:BAAANQAECggIEQAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgIIAgAAAA==.',
Zh='Zhuntyr:BAAANQAECgIIAgAAAA==.',
Zi='Zierosouls:BAAANQADCgcIDAAAAA==.Ziggedion:BAABNQAECoEeAAIjAAgKmxSgBgADAgAjAAgKmxSgBgADAgAAAA==.Zindar:BAAANQAECgQICgAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.',
Zo='Zolpidem:BAAANQADCgQIBAABNQAECggIHwANAJseAA==.',
Zu='Zulljyn:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAABNQAECoElAAIfAAkK4yFBDgBcAwAfAAkK4yFBDgBcAwAAAA==.',
['Ár']='Áres:BAABNQAECoEZAAIiAAgKchGlLADVAQAiAAgKchGlLADVAQAAAA==.',
['Çò']='Çòñstàñtîñè:BAAANQABCgYICAAAAA==.',
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
