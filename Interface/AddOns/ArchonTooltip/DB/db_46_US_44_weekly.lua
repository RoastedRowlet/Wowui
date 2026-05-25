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

local lookup = {'Hunter-BeastMastery','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','DemonHunter-Havoc','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Druid-Guardian','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Hunter-Survival','Paladin-Protection','Mage-Fire','Rogue-Assassination','Warrior-Arms',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAABLgAECn8aAAIBAAgJoAi3YQBVAQABAAgJoAi3YQBVAQAAAA==.Abrakadaver:BAAALgAECgYJCQABLgAECgkJIAACAIIcAA==.',
Ac='Activision:BAAALgAECgYJEQAAAA==.',
Ad='Ademisk:BAAALgADCgYJEgAAAA==.Adventureux:BAACLgAFFH8GAAIBAAMJmRgQOgD/AAABAAMJmRgQOgD/AAAuAAQKfyEAAgEACQmzGY4oABICAAEACQmzGY4oABICAAAA.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8dAAIDAAgJehVHOACdAQADAAgJehVHOACdAQAAAA==.',
Ai='Aiblul:BAAALgAFFAIJAgAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgcJEgABLgAECgkJGgAEAMEiAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgAFAAAAAA==.Aliroarx:BAAALgADCggJFAAAAA==.Almosteasy:BAABLgAECn8XAAIGAAgJLyPFBwAhAwAGAAgJLyPFBwAhAwAAAA==.Alunadoom:BAAALgAECgQJBAAAAA==.Alunagryn:BAACLgAFFH8IAAIHAAQJXAbRIQDwAAAHAAQJXAbRIQDwAAAuAAQKfyQABAcACAllGZwTABICAAcACAnHFZwTABICAAgABwk3F1wfAN0BAAkABQnpGG81AGgBAAAA.Alvera:BAABLgAECn8wAAIKAAkJwR9eGgCGAgAKAAkJwR9eGgCGAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgABLgAECgUJBQAFAAAAAA==.',
An='Anaflora:BAAALgADCgEJAQAAAA==.Anduin:BAAALgAECgYJCQAAAA==.Angerforge:BAAALgAECgcJBwAAAA==.Angrydk:BAAALgAECgcJEgAAAA==.',
Ar='Arielordril:BAAALgAECgYJDQAAAA==.Arm:BAACLgAFFH8GAAILAAIJEwNtNQBlAAALAAIJEwNtNQBlAAAuAAQKfy4AAwwACAmBFzw1ANMBAAwABwnBFjw1ANMBAAsACAmdFWEdALABAAAA.Armee:BAABLgAECn8dAAIJAAkJWRrlDwBnAgAJAAkJWRrlDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgYJCgAAAA==.',
As='Asmilwelme:BAAALgAECgQJCAAAAA==.Astrael:BAACLgAFFH8GAAINAAMJfgjUbwDUAAANAAMJfgjUbwDUAAAuAAQKfx8AAw0ACQmYElxIAOcBAA0ACQnzEVxIAOcBAA4ABQnaEKYOANkAAAAA.Aszayla:BAABLgAECn8cAAINAAgJbRFAYgCeAQANAAgJbRFAYgCeAQAAAA==.Aszea:BAAALgAECgYJCgAAAA==.',
Av='Avoidme:BAAALgAECgUJCgAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwAFAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8uAAIPAAgJ6xF8KgDCAQAPAAgJ6xF8KgDCAQABLgAECgkJFgAQAGAHAA==.Azóg:BAABLgAECn86AAIKAAgJnxp9PwDiAQAKAAgJnxp9PwDiAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAFFAIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8gAAMRAAgJICBNAADuAQARAAYJ9hxNAADuAQASAAcJLCLiAwDbAQAuAAQKfygAAxIACQk9JvsBAJkDABIACQk9JvsBAJkDABEACAmMJCUEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAAALgAFFAMJAwAAAA==.',
Be='Beanvin:BAAALgAECgEJAgAAAA==.Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgcJDgABLgAFFAIJAgAFAAAAAA==.Beastoker:BAAALgAECgYJDAAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAgJGwANAGsiAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgAECgYJEAAAAA==.Beeto:BAACLgAFFH8RAAITAAUJWRcWKgA7AQATAAUJWRcWKgA7AQAuAAQKfxsAAhMACAlaHTokAJcCABMACAlaHTokAJcCAAAA.Bekdrop:BAABLgAECn8RAAIUAAYJNCAbSgCGAQAUAAYJNCAbSgCGAQABLgAFFAgJGwANAGsiAA==.Benlian:BAEBLgAECn8UAAMVAAUJ6ArwNgCMAAAVAAUJ6ArwNgCMAAAKAAUJYAT29ACAAAAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8aAAINAAYJ7hIkJQCPAQANAAYJ7hIkJQCPAQAuAAQKfyMAAw0ACAkgIbkgAPECAA0ACAkgIbkgAPECAA4AAQmmFUseADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.Bishtease:BAAALgADCgQJBAAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8YAAINAAYJdhhEGQDDAQANAAYJdhhEGQDDAQAuAAQKfyoAAg0ACQl4HjQbAAoDAA0ACQl4HjQbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAACLgAFFH8cAAIMAAgJQhwZAgDIAgAMAAgJQhwZAgDIAgAuAAQKfxgAAwwABwktJQEUAIgCAAwABwktJQEUAIgCAAsAAgn1IxZCANIAAAEuAAUUBgkXABYAIhoA.Boof:BAABLgAECn8cAAIIAAkJpxlsGwACAgAIAAkJpxlsGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Bootyful:BAAALgAECgEJAQAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgAECgEJBAAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAAALgAECgkJEwAAAA==.Bruski:BAAALgAECgUJCwAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAFFAQJBwASAA0WAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8YAAITAAgJViKVQwAZAgATAAgJViKVQwAZAgAAAA==.Bushgarden:BAAALgAECgIJAgABLgAECgkJHAAXAK0SAA==.Buzzbuzz:BAABLgAECn8VAAMHAAkJtxcAFwDoAQAHAAgJxhkAFwDoAQAIAAgJkBCTKQBcAQAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAIWAAYJIhodAgAKAgAWAAYJIhodAgAKAgAuAAQKfx8AAxYACQllHzMEABMDABYACQllHzMEABMDABEAAwn5Iu0iABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAIYAAMJaCCBHQAIAQAYAAMJaCCBHQAIAQABLgAFFAYJFwAWACIaAA==.',
['Bö']='Böba:BAAALgAECgYJBgABLgAFFAYJFwAWACIaAA==.',
Ca='Caelin:BAABLgAECn8kAAIUAAcJ7RDZawAmAQAUAAcJ7RDZawAmAQAAAA==.Caishana:BAABLgAECn8yAAMDAAkJaiL+BQAsAwADAAkJaiL+BQAsAwAPAAEJGgYFmQAiAAAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAABLgAECn8UAAMJAAgJ+hV2HAC9AQAJAAgJjBV2HAC9AQAHAAYJjg07LwA0AQAAAA==.',
Ce='Cecil:BAABLgAECn8mAAIZAAkJDwfXMQBmAQAZAAkJDwfXMQBmAQAAAA==.Celeb:BAABLgAECn8oAAICAAgJ8CMJAQAyAwACAAgJ8CMJAQAyAwAAAA==.Celebrity:BAAALgAECgUJCgABLgAECggJKAACAPAjAA==.Celebtard:BAAALgAECgIJAgABLgAECggJKAACAPAjAA==.Cervrakabra:BAAALgAECgEJAgAAAA==.',
Ch='Chaddingus:BAAALgAECgkJEAAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgQJCAAAAA==.Chilltea:BAACLgAFFH8GAAINAAMJ7SCTUgAiAQANAAMJ7SCTUgAiAQAuAAQKfykAAg0ACAmmJEoWALgCAA0ACAmmJEoWALgCAAAA.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8jAAQaAAcJfQrjEwDzAAAaAAYJdwrjEwDzAAAbAAYJ3whirADSAAAXAAEJSgxuNwAsAAAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAABLgAECn8wAAIZAAkJCCB+BQAbAwAZAAkJCCB+BQAbAwAAAA==.',
Co='Coheedkil:BAAALgAECgUJBQAAAA==.Coldbreeze:BAAALgAECgMJAwAAAA==.Collateral:BAAALgAECggJDwAAAA==.Compaktdisc:BAAALgAECgkJEgAAAA==.Conartist:BAAALgAECgYJBwABLgAFFAMJBQAcAAEjAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwAFAAAAAA==.Cowpox:BAABLgAECn8eAAIMAAkJWQ6INACmAQAMAAkJWQ6INACmAQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Creatrix:BAAALgAECgYJCAABLgAFFAMJBQAcAAEjAA==.Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAAALgAECgYJDwAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn8+AAIZAAgJJCP8CQDHAgAZAAgJJCP8CQDHAgAAAA==.Cruv:BAAALgAECgMJAwAAAA==.Cry:BAAALgAECgQJCQAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8MAAIdAAUJhh1zFABIAQAdAAUJhh1zFABIAQAuAAQKfyMAAh0ACQmIIDALANkCAB0ACQmIIDALANkCAAAA.',
Cy='Cybuster:BAAALgAECgcJDwABLgAFFAQJCgANALUVAA==.Cyndle:BAAALgAECgYJBgABLgAECgkJGwAJAMsXAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8cAAINAAkJTxB/ewDaAQANAAkJTxB/ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8bAAICAAkJDBXVCQDOAQACAAkJDBXVCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECggJDgAAAA==.Dakian:BAAALgADCgEJAQAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAABLgAECn8nAAITAAgJvwjMhABFAQATAAgJvwjMhABFAQABLgAECgUJGAAQANsKAA==.Dargong:BAAALgAECggJAgAAAA==.Darkrunes:BAABLgAECn8dAAIUAAcJLho0PgD7AQAUAAcJLho0PgD7AQAAAA==.Darrkness:BAABLgAFFH8GAAIbAAIJ2xCVgwCQAAAbAAIJ2xCVgwCQAAAAAA==.Darthvikingw:BAAALgADCgcJDAAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJCgAAAA==.Deides:BAAALgADCgUJBAAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgUJCQABLgAECgkJJgAVAOYUAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAABLgAECn8cAAITAAgJpx/rIQBfAgATAAgJpx/rIQBfAgAAAA==.Deristus:BAABLgAECn8lAAIbAAkJRBVBPwDHAQAbAAkJRBVBPwDHAQAAAA==.Deroth:BAAALgAECgEJAwAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAAFAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Devi:BAAALgAECgIJAwABLgAECgcJCwAFAAAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dingeoffor:BAAALgAECgEJAwABLgAFFAMJBgAHADgQAA==.Dirtmonkgirt:BAABLgAECn8gAAIcAAkJ3BaXEQASAgAcAAkJ3BaXEQASAgAAAA==.Dirtnasty:BAAALgAFFAIJAgAAAA==.Dirtysham:BAABLgAECn8cAAIPAAgJcBjJIQABAgAPAAgJcBjJIQABAgAAAA==.Discipline:BAABLgAECn8lAAIIAAkJ/BetEAAvAgAIAAkJ/BetEAAvAgAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8cAAMKAAYJVRNfkQBdAQAKAAYJqBJfkQBdAQAVAAYJnAxjKgDVAAAAAA==.Dotdotgoose:BAAALgAECggJCwABLgAECgkJEgAFAAAAAA==.Dotgunner:BAABLgAECn8XAAIbAAcJXRtBQAANAgAbAAcJXRtBQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgkJIAAUAJYdAA==.Downbad:BAACLgAFFH8FAAIbAAMJdQcoJwDhAAAbAAMJdQcoJwDhAAAuAAQKfx8AAxsACAl+H1wXAMgCABsACAl+H1wXAMgCABcABAm8Cwg1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJHQAQAHgQAA==.Drahseer:BAAALgAECgIJAgAAAA==.Drakqueenjd:BAAALgADCgYJBgAAAA==.Drakulya:BAABLgAECn8YAAITAAYJhwu/uADwAAATAAYJhwu/uADwAAAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAABLgAECn8eAAMUAAgJ3Aw0XABQAQAUAAgJhAw0XABQAQAQAAMJMghrWgB5AAAAAA==.Drewish:BAAALgADCgQJBAAAAA==.Driftèr:BAAALgAECgcJEgAAAA==.Drizzle:BAACLgAFFH8FAAIUAAMJHiCKMwAiAQAUAAMJHiCKMwAiAQAuAAQKfyYAAhQACAm2JQ8NAMICABQACAm2JQ8NAMICAAAA.Drkdestro:BAABLgAECn8wAAQbAAkJByK8DwD8AgAbAAkJBSG8DwD8AgAaAAYJoh1VCgCFAQAXAAEJyxzIXwBPAAAAAA==.Drktotem:BAAALgAECgYJBgAAAA==.Druidic:BAACLgAFFH8UAAIMAAUJDSTNCAARAgAMAAUJDSTNCAARAgAuAAQKfzgAAgwACQlsJbkDAFYDAAwACQlsJbkDAFYDAAAA.Drunkhorn:BAAALgADCgMJAwAAAA==.Druvinci:BAAALgADCgQJBAAAAA==.Drü:BAABLgAECn8UAAILAAkJDxLhLQCVAQALAAkJDxLhLQCVAQAAAA==.',
Du='Duneshade:BAAALgADCgUJBQAAAA==.Dunk:BAAALgAECgEJAQAAAA==.Dusan:BAABLgAECn8pAAMJAAkJBB1iCQCuAgAJAAkJBB1iCQCuAgAHAAYJmgsWNQARAQAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ea:BAAALgADCgYJBwAAAA==.Ear:BAAALgADCgcJBwABLgAFFAMJBgAEAMQPAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8kAAMDAAgJIRUhMwC3AQADAAgJIRUhMwC3AQAEAAQJ/wK6IgCqAAAAAA==.',
Ed='Edonsian:BAACLgAFFH8FAAIeAAMJFxfAJADqAAAeAAMJFxfAJADqAAAuAAQKfzoAAx4ACQktG58XAA0CAB4ACQmjGp8XAA0CAB8ABQm2GnEcACkBAAAA.',
Ee='Eepy:BAABLgAECn8aAAMYAAkJoBHtHQDGAQAYAAkJoBHtHQDGAQAcAAUJuxErPwDWAAAAAA==.',
Eg='Egmont:BAAALgADCgcJBwAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgAECgYJCwABLgAECgcJGQASAEobAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAABLgAECn8UAAIfAAgJlBT2FAB7AQAfAAgJlBT2FAB7AQAAAA==.Emorlyn:BAABLgAECn8XAAMBAAkJwg+sNADcAQABAAkJwg+sNADcAQAGAAYJpgIgZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Encanis:BAAALgAECgcJCwAAAA==.Endrai:BAAALgAECgEJAQAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAACLgAFFH8LAAINAAQJ3Q8MTgAtAQANAAQJ3Q8MTgAtAQAuAAQKfx4AAg0ACAlDHBFNAE8CAA0ACAlDHBFNAE8CAAAA.',
Er='Eriksangus:BAABLgAECn8XAAIeAAgJ/wdsQwAOAQAeAAgJ/wdsQwAOAQAAAA==.',
Es='Eskarina:BAAALgADCgcJBwAAAA==.Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAABLgAECn8rAAIMAAkJLBJXKwDbAQAMAAkJLBJXKwDbAQAAAA==.',
Ev='Evilguard:BAABLgAECn8mAAMVAAkJ5hTZEgCyAQAVAAgJmRfZEgCyAQAgAAEJ/gGdMgAJAAAAAA==.Evilpatty:BAAALgAECgMJAwAAAA==.',
Ex='Excessive:BAAALgAECgEJAQAAAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECggJDgAAAA==.',
Fa='Falador:BAAALgAECgYJDAAAAA==.Fariebubbles:BAABLgAECn8aAAIMAAgJFA9GPACAAQAMAAgJFA9GPACAAQAAAA==.Fastandis:BAAALgAECgYJBgAAAA==.Fatale:BAACLgAFFH8HAAIUAAMJZxDeSwDVAAAUAAMJZxDeSwDVAAAuAAQKfxQAAhQABgnZIGQzANgBABQABgnZIGQzANgBAAAA.Fatallock:BAAALgAECgUJBQABLgAFFAMJBwAUAGcQAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMbAAcJgRm/aQCQAQAbAAYJghq/aQCQAQAXAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAABLgAFFH8GAAMDAAMJ/g2wUAB1AAADAAIJLQqwUAB1AAAPAAEJah4HOwBVAAAAAA==.Fenixstraza:BAACLgAFFH8RAAQSAAUJNxaQLwDVAAASAAMJ1hmQLwDVAAAWAAMJThc5GgC/AAARAAIJVwuFCwBJAAAuAAQKfzUABBYACQmMGyUJADUCABYACAk5HSUJADUCABIACQkHGZgSACsCABEAAQkAAB4oAAAAAAAA.Fervis:BAAALgAECgQJCAABLgAECggJFgASABcKAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJEwABLgAECgcJFgANADoMAA==.Firitako:BAAALgAECgcJEQAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECgkJNQAeAIglAA==.Flipper:BAABLgAECn8ZAAMZAAkJKxSrIgAJAgAZAAkJKxSrIgAJAgATAAIJawFyRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8cAAQaAAkJgCCRAwBfAgAaAAkJgCCRAwBfAgAbAAMJmxEFDAE6AAAXAAEJtwQuPAAbAAAAAA==.Frankiejr:BAAALgAECgYJEAABLgAECgcJIwATAKklAA==.Frapsity:BAABLgAECn8kAAMDAAgJbBbBIgAQAgADAAgJbBbBIgAQAgAPAAUJwwrzVgCwAAAAAA==.Frapss:BAAALgADCggJCAABLgAECggJJAADAGwWAA==.Frostamper:BAAALgAECgYJDwAAAA==.Frostnite:BAAALgAECgYJEQAAAA==.Frostpoptart:BAABLgAECn8vAAIDAAkJ0xgAIgATAgADAAkJ0xgAIgATAgAAAA==.Frozenblade:BAAALgAECgYJBgAAAA==.',
Fu='Fupah:BAAALgAECgIJAgAAAA==.Furball:BAAALgAECgMJAwABLgAFFAUJDwAbAHARAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAACLgAFFH8NAAIdAAQJkiIHDACKAQAdAAQJkiIHDACKAQAuAAQKfx4AAx0ACQl+HyoOADgCAB0ACQl+HyoOADgCABwAAQksBJ6WACEAAAAA.Galadrielle:BAAALgAECggJEwAAAA==.Gandelf:BAAALgAECgYJBgABLgAECggJJgABALMZAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Garret:BAAALgADCgQJBAABLgAECgcJJAAUAO0QAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8pAAIhAAkJkAsCHgAZAQAhAAkJkAsCHgAZAQAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAACLgAFFH8FAAIUAAMJSRSaRgDlAAAUAAMJSRSaRgDlAAAuAAQKfzEAAhQACAmFIO8TAIYCABQACAmFIO8TAIYCAAAA.',
Gh='Ghostfate:BAAALgAECgEJAQAAAA==.',
Gi='Gigbutt:BAABLgAECn88AAMiAAkJ9RvzCwBBAgAiAAkJ9RvzCwBBAgAjAAUJaxBoDAAfAQAAAA==.Giggles:BAAALgAECgIJAgAAAA==.Giggléz:BAAALgAECgcJCgAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAINAAgJIBs8RABrAgANAAgJIBs8RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgAECgEJAgAAAA==.Goatedfury:BAACLgAFFH8IAAITAAQJEwKmUwDaAAATAAQJEwKmUwDaAAAuAAQKfxQAAhMACAnVFQVeAJYBABMACAnVFQVeAJYBAAAA.Goblegoble:BAAALgAECgEJAQAAAA==.Gorgrot:BAAALgAECgcJCgABLgAFFAQJDgALAD4XAA==.Gorshot:BAABLgAECn8YAAIBAAkJwgxNPwC5AQABAAkJwgxNPwC5AQAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Greatvibes:BAAALgAECgUJCQABLgAFFAIJAgAFAAAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgAECgUJCAABLgAFFAMJBgAbABAWAA==.Griitz:BAABLgAECn8VAAIKAAgJ6BrZJgBEAgAKAAgJ6BrZJgBEAgAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAACLgAFFH8FAAIkAAMJzB69BgAcAQAkAAMJzB69BgAcAQAuAAQKfygAAyQACAnpIysDAMICACQACAnpIysDAMICACEABgmRDwMXAAUBAAAA.Griswold:BAABLgAECn8aAAIXAAYJVhrmCQB5AQAXAAYJVhrmCQB5AQAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8gAAMNAAgJqRvkQAB2AgANAAgJqRvkQAB2AgAOAAEJ0ibSFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJIAANAKkbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8NAAMKAAQJkx0ITgAvAQAKAAMJSSMITgAvAQAVAAMJLg82HgC2AAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJCAAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8jAAIIAAkJKg1GHQC0AQAIAAkJKg1GHQC0AQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.Hawtdonna:BAAALgAECgcJCgAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8uAAQbAAkJYCIHCgDsAgAbAAkJYCIHCgDsAgAXAAMJeh4PMQD1AAAaAAEJzARgNAAmAAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAwAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAABLgAECn8XAAITAAkJvRccPQAwAgATAAkJvRccPQAwAgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECgkJFQAHALcXAA==.Hoofrat:BAAALgAECgcJBQAAAA==.Hornivore:BAAALgADCgkJDAAAAA==.',
Hp='Hpal:BAAALgAECgQJBAAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgcJDAAFAAAAAA==.Huxley:BAAALgAECgIJAgAAAA==.Huñted:BAABLgAECn8bAAMlAAgJAxMxHACdAQAlAAgJnQ8xHACdAQABAAYJIw7UYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgAECgQJCAAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgcJDAAFAAAAAA==.',
Ic='Icefrosting:BAAALgADCgkJCQABLgAECgkJHwAIAFIaAA==.Icuris:BAAALgAECgMJBQAAAA==.',
Id='Idistroya:BAABLgAECn8ZAAIVAAcJnw+kIQAWAQAVAAcJnw+kIQAWAQABLgAECgkJUAABAKEjAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMaAAgJYBWQCADBAQAaAAYJ1BiQCADBAQAbAAgJCRGuVQCFAQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8XAAIJAAgJkhVVGwACAgAJAAgJkhVVGwACAgAAAA==.Ilithiya:BAAALgAFFAEJAQAAAA==.Ilk:BAAALgAECgEJAQAAAA==.Illidrac:BAABLgAECn8dAAIQAAkJeBAsGACKAQAQAAkJeBAsGACKAQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJGQASAEobAA==.Illudari:BAAALgAECgMJAwABLgAECgcJGQASAEobAA==.Illududu:BAAALgAECgYJBgABLgAECgcJGQASAEobAA==.',
Im='Imangry:BAABLgAECn8gAAImAAgJwBEtEQCFAQAmAAgJwBEtEQCFAQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inconsolable:BAAALgADCgMJAwAAAA==.Inpherno:BAAALgAFFAEJAQAAAA==.',
Is='Isaidnoice:BAABLgAECn8cAAMXAAkJrRKgFgCVAQAXAAcJGxOgFgCVAQAbAAgJmg5EVgCDAQAAAA==.Ishton:BAABLgAFFH8FAAITAAMJegfwVQDTAAATAAMJegfwVQDTAAAAAA==.Istompgnomes:BAABLgAECn8WAAIPAAgJDBi9GADwAQAPAAgJDBi9GADwAQAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgcJEwAAAA==.',
Ja='Jacked:BAABLgAECn8fAAMbAAkJLR4HOADhAQAbAAcJxxsHOADhAQAaAAQJ/hzBEAAhAQAAAA==.Jasøn:BAAALgAECggJEAAAAA==.',
Je='Jecka:BAABLgAECn8pAAMIAAkJlRV6KQBcAQAIAAcJ/BF6KQBcAQAJAAgJVg26QgAuAQAAAA==.Jeckah:BAAALgAECgYJCwABLgAECgkJKQAIAJUVAA==.Jecthyr:BAAALgAECgEJAQABLgAECgkJKQAIAJUVAA==.Jefryepsteen:BAAALgAECgcJDAAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAABLgAECn8kAAIJAAcJ4BlIGwDHAQAJAAcJ4BlIGwDHAQAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8YAAMmAAYJBB5YFABZAQAmAAYJBB5YFABZAQATAAEJrwL0WQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jo='Jordana:BAABLgAECn8bAAIMAAkJ0hUOMgCzAQAMAAkJ0hUOMgCzAQAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJBAAAAA==.',
Js='Jsdruid:BAAALgAECgYJDAAAAA==.',
Ju='Jug:BAABLgAECn8cAAIlAAgJqBuXBADPAgAlAAgJqBuXBADPAgAAAA==.Julaudette:BAAALgAECgQJBAAAAA==.',
Ka='Kainöa:BAAALgAECgYJEwABLgAFFAIJAgAFAAAAAA==.Kakum:BAAALgAECgYJCwAAAA==.Kaldrogo:BAAALgAECgQJCgAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAcJIAAYANcZAA==.Kalnuggets:BAAALgAECgUJBQAAAA==.Kalrathen:BAABLgAECn8fAAIJAAgJxRK+LgCJAQAJAAgJxRK+LgCJAQAAAA==.Kaniku:BAAALgAECgEJBAABLgAFFAUJDgANAEUSAA==.Karmafel:BAAALgAECgUJCgABLgAECgcJDgAFAAAAAA==.Karsh:BAABLgAECn8gAAIeAAkJBwdQNABSAQAeAAkJBwdQNABSAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAABLgAECn8eAAMbAAgJZhi2MAD9AQAbAAgJZhi2MAD9AQAXAAYJoQw3JAA4AQAAAA==.Kazurena:BAAALgADCgcJCQAAAA==.',
Kd='Kdb:BAAALgAECggJCAABLgAFFAUJFAAMAA0kAA==.',
Ke='Kered:BAAALgAECgYJDQABLgAFFAMJBgAMACAYAA==.Keuaakepo:BAABLgAECn9QAAMBAAkJoSPNBQAYAwABAAkJoSPNBQAYAwAlAAEJUQM9MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8pAAIBAAgJtRvJMADvAQABAAgJtRvJMADvAQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECggJCwABLgAECgkJEgAFAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgUJCQAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAABLgAECn8VAAIHAAYJfQn/NgAGAQAHAAYJfQn/NgAGAQAAAA==.',
Ko='Korbanhavoc:BAAALgAECgYJBgAAAA==.Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8qAAMkAAkJMhduBgBLAgAkAAkJMhduBgBLAgAhAAIJ0AwgKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJDQAAAA==.',
Kr='Krethar:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Krypt:BAABLgAECn8pAAIfAAkJWxf5DAD0AQAfAAkJWxf5DAD0AQAAAA==.Krìzl:BAACLgAFFH8JAAINAAMJRR4CVAAfAQANAAMJRR4CVAAfAQAuAAQKfy8AAg0ACAnDI4YfAIYCAA0ACAnDI4YfAIYCAAEuAAUUBgkdAAoAHSUA.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgQJBAAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAACLgAFFH8GAAMbAAMJEBa8XADeAAAbAAMJBBK8XADeAAAXAAEJWhWCGwBOAAAuAAQKfzYABBcACQlaIVsDAL0CABcACAmIIVsDAL0CABsABwnPHNEgAEgCABoAAQkeHt0tADwAAAAA.Lanzen:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.Lanzier:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Larrfena:BAABLgAECn8lAAIBAAgJMB62HABPAgABAAgJMB62HABPAgAAAA==.',
Le='Legit:BAAALgAECgcJDAABLgAECggJHQAUAC4aAA==.Legsday:BAAALgADCgcJEgAAAA==.Lementz:BAACLgAFFH8UAAIEAAUJDiCtAADIAQAEAAUJDiCtAADIAQAuAAQKf0EAAgQACQniJh0AAIwDAAQACQniJh0AAIwDAAAA.Lexiiees:BAABLgAECn8bAAIiAAcJ7QT6LwDvAAAiAAcJ7QT6LwDvAAAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAAALgAECgYJDwABLgAECgcJFgANADoMAA==.Lillia:BAABLgAECn8pAAIbAAkJShFMQADDAQAbAAkJShFMQADDAQAAAA==.',
Lo='Lockyshocky:BAAALgADCgcJCwAAAA==.Lovetobussy:BAABLgAECn8gAAMJAAYJgRsKHADAAQAJAAYJgRsKHADAAQAIAAIJ7w0dWgBuAAAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn9BAAQbAAkJMiImCAABAwAbAAkJMiImCAABAwAXAAUJhR1/GwBxAQAaAAIJ9hyeHQCOAAAAAA==.Lumpia:BAACLgAFFH8FAAIKAAMJ9w7PegDcAAAKAAMJ9w7PegDcAAAuAAQKfyQAAgoACAlvIQ4gAGYCAAoACAlvIQ4gAGYCAAAA.',
['Lè']='Lèah:BAAALgAECgUJCgAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAIJAgABLgAFFAQJCwANADsjAA==.Madgeyoulook:BAAALgAECgEJAQAAAA==.Magenta:BAAALgAECgUJBQAAAA==.Magicchoc:BAAALgAECgYJDAABLgAECgkJJgAVAOYUAA==.Maktah:BAACLgAFFH8JAAIEAAQJMwk5BwANAQAEAAQJMwk5BwANAQAuAAQKfxQAAwQACAn2F+ULAL4BAAQACAn2F+ULAL4BAA8AAQl0EOGFADUAAAAA.Mandrakor:BAAALgADCgEJAQAAAA==.Marshboa:BAAALgAFFAIJAgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mcgurk:BAAALgAECggJCQAAAA==.Mclovinit:BAACLgAFFH8bAAINAAgJayLEAQDgAgANAAgJayLEAQDgAgAuAAQKf1MAAg0ACQmqJnoAAAIEAA0ACQmqJnoAAAIEAAAA.Mcmagic:BAACLgAFFH8HAAINAAQJPxo9VQAbAQANAAQJPxo9VQAbAQAuAAQKfy4AAg0ACAlPIz4XALMCAA0ACAlPIz4XALMCAAEuAAUUCAkbAA0AayIA.Mcpally:BAABLgAECn85AAITAAkJUCKVCgD3AgATAAkJUCKVCgD3AgAAAA==.',
Me='Mecca:BAACLgAFFH8IAAIKAAIJ0x5+jwCuAAAKAAIJ0x5+jwCuAAAuAAQKfxwAAwoABwmEIyEtACcCAAoABwmEIyEtACcCABUABQl7FiAkACABAAAA.Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8dAAIMAAkJeCO3CAADAwAMAAkJeCO3CAADAwAAAA==.Mensu:BAAALgAECgYJCwAAAA==.Mentos:BAABLgAECn8tAAMRAAkJHRriAgBbAgARAAkJHRriAgBbAgAWAAYJJx5NDADqAQAAAA==.Mercilezz:BAAALgAECgIJAgAAAA==.',
Mi='Midwestfel:BAABLgAECn8cAAIUAAgJzwaGkgDRAAAUAAgJzwaGkgDRAAAAAA==.Mikeoxhard:BAAALgAECggJDwAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAABLgAECn8cAAIIAAkJNBGnHgCoAQAIAAkJNBGnHgCoAQAAAA==.Minihulk:BAABLgAECn8UAAQgAAcJhwc2FQDoAAAgAAcJhwc2FQDoAAAKAAMJgwMOBQFnAAAVAAMJowE5RwBFAAAAAA==.Mionn:BAAALgAECgUJDgAAAA==.Misshell:BAAALgAECgEJAwAAAA==.Mistsmoker:BAAALgAECgYJBgABLgAFFAUJEAAhAJUfAA==.',
Ml='Mlleena:BAABLgAECn8rAAMbAAcJfg+wbQBJAQAbAAcJfg+wbQBJAQAaAAMJxAr9GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8nAAMXAAkJVhmXBgBkAgAXAAcJqR2XBgBkAgAbAAYJFhccRAC4AQAAAA==.Moloch:BAAALgAECgEJAgAAAA==.Monangai:BAAALgAECgcJEQABLgAECgcJFgANADoMAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBwAAAA==.Mooncake:BAAALgAECggJEgAAAA==.Moosiah:BAACLgAFFH8GAAIMAAMJIBgVLADlAAAMAAMJIBgVLADlAAAuAAQKfy8AAwsACAm3IWQRACcCAAsACAm3IWQRACcCAAwABgnfHCgoAO8BAAAA.Mortenerra:BAABLgAECn8VAAIJAAUJURVROgDqAAAJAAUJURVROgDqAAAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfire:BAAALgAFFAEJAQAAAA==.Mossfiré:BAAALgAECgYJEAABLgAFFAEJAQAFAAAAAA==.Motoko:BAABLgAECn8qAAQcAAkJGxX+HgCNAQAcAAgJnxb+HgCNAQAYAAYJLxIFNgAWAQAdAAYJ6QiTRADMAAAAAA==.',
Mu='Muatamuata:BAAALgAECgEJAgAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECgkJEgAFAAAAAA==.',
My='Myhealmissed:BAAALgADCggJCAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECggJEAAFAAAAAA==.Møøfi:BAAALgAECgYJCgAAAA==.',
Na='Nachomonk:BAAALgAECgQJBAAAAA==.Nachoshamy:BAAALgAECgUJBQAAAA==.Nameless:BAABLgAECn8nAAMOAAkJxxaIBQDUAQANAAkJ0RIGQAABAgAOAAYJzhqIBQDUAQAAAA==.Narc:BAABLgAECn8hAAIMAAgJIAc8YAD0AAAMAAgJIAc8YAD0AAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Narissa:BAAALgADCgQJBAAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAACLgAFFH8IAAMBAAQJHxWNKwArAQABAAQJHxWNKwArAQAGAAEJnQFyLQA8AAAuAAQKfy4AAwEACQmrIS8MAM0CAAEACQkyIS8MAM0CAAYACQk+F3YQALkCAAAA.Nazure:BAAALgAECgYJBgAAAA==.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn82AAIBAAkJcRfpHQBJAgABAAkJcRfpHQBJAgAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgADCggJHAAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECgkJGgAYAG0SAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8OAAMbAAUJvQ0wTwAAAQAbAAUJiAowTwAAAQAaAAIJExmHFwBOAAAuAAQKfyYABBcACQlIHQgPANoBABcABwmuFggPANoBABsABwlhGfZgAGgBABoABQnEFUEVAOIAAAAA.',
No='Noova:BAABLgAECn8wAAINAAcJ4CCNUABFAgANAAcJ4CCNUABFAgAAAA==.Norooux:BAAALgADCgkJDQAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJCAAHAFwGAA==.',
Ob='Obliverat:BAAALgAECgcJDwAAAA==.',
Ol='Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgQJCgAAAA==.',
Or='Orangesorbet:BAAALgAECgEJAQAAAA==.Orcaneblast:BAACLgAFFH8OAAINAAUJRRLISAA2AQANAAUJRRLISAA2AQAuAAQKfywAAg0ACQnkIcAOAO0CAA0ACQnkIcAOAO0CAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDwAAAA==.Ornn:BAABLgAECn8oAAIfAAgJUiKKBwBnAgAfAAgJUiKKBwBnAgAAAA==.',
Pa='Palmtalon:BAAALgAECgMJBwAAAA==.Pandaminium:BAAALgAECgEJAQAAAA==.Pandarias:BAAALgAECgQJBQAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Partypizza:BAABLgAECn8xAAIPAAkJdR6ZCgCTAgAPAAkJdR6ZCgCTAgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAUJFAAMAA0kAA==.Penne:BAAALgAECgYJBwABLgAFFAQJCwANADsjAA==.Permanence:BAABLgAECn8UAAIUAAYJARZ3bQBbAQAUAAYJARZ3bQBbAQAAAA==.',
Ph='Phoeniex:BAAALgAECgUJBQABLgAECgkJGgAYAG0SAA==.Phoenixphyre:BAAALgADCgUJBQAAAA==.',
Pi='Picobuffu:BAAALgAECgYJDAABLgAFFAMJBQAUADcOAA==.Picodedge:BAACLgAFFH8FAAIUAAMJNw6qTADTAAAUAAMJNw6qTADTAAAuAAQKfy0AAxQACAlDHR8sAPkBABQACAlDHR8sAPkBABAAAQn0DZFYADAAAAAA.Picoroo:BAAALgAECgUJCAABLgAFFAMJBQAUADcOAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pinkgauge:BAAALgAECggJCAAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn8vAAMNAAkJURppKgBTAgANAAkJyxlpKgBTAgAnAAQJ0xE4BwDxAAAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgQJBwAAAA==.Porthos:BAAALgADCgcJDAAAAA==.Poõpsikens:BAAALgAECgMJAwAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAIbAAcJwBmlYwCfAQAbAAcJwBmlYwCfAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAwAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8QAAIKAAUJVx4rMwBdAQAKAAUJVx4rMwBdAQAuAAQKfzcAAwoACAkXJC4VAKcCAAoACAkXJC4VAKcCACAABQkqF4MRABcBAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qq='Qqpewpew:BAAALgAECgcJDwAAAA==.',
Qt='Qtpi:BAABLgAECn8gAAIUAAkJlh0XHgBDAgAUAAkJlh0XHgBDAgAAAA==.',
Qu='Quica:BAAALgAECgEJAQABLgAECgcJFgANADoMAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAINAAgJWxmDQwBuAgANAAgJWxmDQwBuAgABLgAFFAcJFwANAB0bAA==.Raketh:BAABLgAECn8WAAISAAgJFwqgOAAjAQASAAgJFwqgOAAjAQAAAA==.Rallek:BAABLgAECn8wAAIZAAkJfhlmFQA6AgAZAAkJfhlmFQA6AgAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECggJKAAfAFIiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAABLgAECn8UAAIWAAkJYR7GCwB5AgAWAAkJYR7GCwB5AgAAAA==.Rehabherox:BAAALgADCgcJDgAAAA==.Rektek:BAABLgAECn8aAAIeAAkJWBRVNADZAQAeAAkJWBRVNADZAQAAAA==.Rektnasty:BAAALgAECgIJBQAAAA==.Remeras:BAABLgAECn8cAAITAAkJqxAAXgDJAQATAAkJqxAAXgDJAQAAAA==.Resilientaid:BAABLgAECn8cAAIMAAYJeh/cIQAWAgAMAAYJeh/cIQAWAgAAAA==.Restolyfe:BAAALgAECgUJDAAAAA==.Retack:BAAALgAECgEJBAAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8mAAQYAAkJ/A2rNQBJAQAYAAkJ/A2rNQBJAQAdAAIJygssdwBlAAAcAAEJsASChQArAAAAAA==.Rilzi:BAAALgAECggJCgAAAA==.Ripblast:BAAALgAECgEJAQABLgAECgkJGgAYAG0SAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAABLgAECn8YAAMkAAgJbyArBwA2AgAkAAcJBiArBwA2AgAMAAEJCAfUvAAxAAABLgAECgkJPAAiAPUbAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Rohar:BAAALgAECgcJDgAAAA==.Roley:BAAALgADCgcJCgAAAA==.Roots:BAAALgAECgUJEQAAAA==.Rosalie:BAAALgADCgUJBQAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgAECgMJAwAAAA==.Rossick:BAAALgAECgkJCQAAAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAwAAAA==.Ruuf:BAABLgAECn8sAAIPAAkJmgtBLgBbAQAPAAkJmgtBLgBbAQAAAA==.',
Ry='Rynohtwo:BAAALgAECgYJCQAAAA==.Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sabrinaa:BAAALgADCgYJBgAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgAECgEJAwAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgQJBwAAAA==.',
Sc='Scalylusion:BAABLgAECn8ZAAMSAAcJShvkLQBTAQASAAYJ6RjkLQBTAQARAAYJ0xhrIQAgAQAAAA==.Scrivener:BAAALgADCgcJCQAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.',
Se='Seanconery:BAAALgAECgcJDAAAAA==.Senica:BAABLgAECn8pAAIJAAkJUh07EgBPAgAJAAkJUh07EgBPAgAAAA==.Sensedeous:BAAALgADCgcJDgAAAA==.Seriphina:BAAALgAECgIJAgAAAA==.',
Sh='Shabbarankz:BAABLgAECn8dAAIkAAgJABYOCwASAgAkAAgJABYOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAABLgAECn8rAAIEAAkJ+w5uDAC0AQAEAAkJ+w5uDAC0AQAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgQJBAABLgAECgkJGgAYAG0SAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAABLgAECn8WAAINAAcJOgyPwgDoAAANAAcJOgyPwgDoAAAAAA==.Sheepwreck:BAAALgAECgQJBAAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shinedown:BAAALgADCgMJAwAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgADCgQJBAAAAA==.Shotbot:BAAALgADCgYJBgABLgAFFAUJCwATAAISAA==.Shra:BAABLgAECn8hAAIhAAkJMhFQEwCBAQAhAAkJMhFQEwCBAQAAAA==.Shrafu:BAAALgAECgYJDAAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECggJFgASABcKAA==.Sindracosa:BAABLgAECn8XAAMRAAYJsgqMIAApAQARAAYJsgqMIAApAQAWAAYJiQUZLwD5AAABLgAECgkJHQAQAHgQAA==.Sindradori:BAAALgADCgMJAwABLgAECgkJHAAIAKcZAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinoshi:BAAALgADCgQJAgAAAA==.Sinsidious:BAAALgADCggJFwAAAA==.Sizzle:BAAALgAECgkJDQABLgAECgkJFQAHALcXAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAABLgAECn8bAAIiAAkJiRUtFgBcAgAiAAkJiRUtFgBcAgAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAABLgAECn8YAAIPAAgJMROiJwCDAQAPAAgJMROiJwCDAQAAAA==.Smokindots:BAABLgAECn8mAAIbAAkJbRr9NADsAQAbAAkJbRr9NADsAQABLgAFFAMJBgADADUeAA==.Smokinloud:BAAALgAECgcJEwAAAA==.Smokinmyrrh:BAAALgAECggJCwABLgAFFAMJBgADADUeAA==.Smokinperiod:BAAALgADCgUJBQAAAA==.Smokinpsalm:BAABLgAECn8cAAMJAAcJ6xs2HAD7AQAJAAcJ6xs2HAD7AQAIAAYJYAhfQQDfAAABLgAFFAMJBgADADUeAA==.Smokintotem:BAACLgAFFH8GAAIDAAMJNR5zJgAQAQADAAMJNR5zJgAQAQAuAAQKf0UAAwMACQkIIbQNAMACAAMACQkIIbQNAMACAA8AAQlTJRJsAGwAAAAA.',
Sn='Sneakingbush:BAABLgAECn8jAAMiAAcJfQ2jLACaAQAiAAcJUw2jLACaAQAoAAQJ8greEwDCAAAAAA==.Snowberry:BAAALgAECgMJBAAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8OAAIPAAUJfxF/CwCQAQAPAAUJfxF/CwCQAQAuAAQKfxwAAw8ACAlZFUgmAN8BAA8ACAlZFUgmAN8BAAQAAwmxBWgkAJIAAAEuAAUUBgkaAA0A7hIA.Spaghett:BAABLgAFFH8LAAINAAQJOyP7WwADAQANAAQJOyP7WwADAQAAAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAACLgAFFH8FAAIcAAMJASOaDAA2AQAcAAMJASOaDAA2AQAuAAQKfy8AAxwACAmVJZ0GAMECABwACAlmJZ0GAMECAB0ABgnDIHwYAMQBAAAA.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAABLgAECn8UAAILAAgJvAzHKwBIAQALAAgJvAzHKwBIAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgUJBwABLgAECgkJJwAOAMcWAA==.Sundowning:BAABLgAECn8cAAIIAAkJzhUMFAAKAgAIAAkJzhUMFAAKAgAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sw='Sweatsicle:BAAALgADCgUJCAABLgAFFAMJBQAkAMweAA==.Swiftdragon:BAABLgAECn8aAAMYAAkJbRLfLwBqAQAYAAYJrRTfLwBqAQAdAAkJfhuAJgBcAQAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECgkJHAAaAIAgAA==.',
Sy='Sylerwinassa:BAAALgAECgUJCQAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Sylvy:BAEALgAECgUJBgABLgAECgUJFAAVAOgKAA==.Symbolofhope:BAABLgAFFH8GAAIHAAMJOBDGIwDeAAAHAAMJOBDGIwDeAAAAAA==.Synjo:BAABLgAECn80AAIgAAgJgBzZBwDRAQAgAAgJgBzZBwDRAQAAAA==.',
Ta='Taapfer:BAABLgAECn8gAAMCAAkJghwlAwCtAgACAAkJghwlAwCtAgAUAAEJAAAfFQEAAAAAAA==.Tackyh:BAAALgAECgcJDQAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwABLgAECggJEAAFAAAAAA==.Tassidar:BAAALgAECgUJCgAAAA==.Taxevelle:BAAALgAECgEJAQABLgAECgkJNQAeAIglAA==.Taxii:BAABLgAECn81AAMeAAkJiCVqAQBZAwAeAAkJiCVqAQBZAwApAAUJwRrXIwAbAQAAAA==.',
Te='Teapots:BAABLgAECn8aAAIEAAkJwSLVCQDpAQAEAAkJwSLVCQDpAQAAAA==.Teegria:BAAALgADCgYJBgAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAABLgAECn8lAAMIAAkJOxc0HAC9AQAIAAkJOxc0HAC9AQAJAAEJlAk1fgA1AAAAAA==.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgkJMAAZAAggAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAACLgAFFH8LAAITAAUJAhI9MAAuAQATAAUJAhI9MAAuAQAuAAQKfykAAhMACQn4HhoRAAcDABMACQn4HhoRAAcDAAAA.Thefifth:BAACLgAFFH8YAAIWAAcJFw7yAgDiAQAWAAcJFw7yAgDiAQAuAAQKfyoABBYACQlUGnsOAFACABYACQlUGnsOAFACABIACAncGUoSAC8CABEAAwk3Et8yAH8AAAAA.Theralendris:BAABLgAECn8hAAICAAkJ3BQTBwDsAQACAAkJ3BQTBwDsAQAAAA==.Thickarm:BAAALgAFFAIJAgAAAA==.Thyrn:BAAALgADCgYJBgABLgAECggJKAAfAFIiAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8jAAIKAAkJAhoLMAAbAgAKAAkJAhoLMAAbAgAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAUJDgANAEUSAA==.Treebeard:BAAALgAECgQJBAAAAA==.Tri:BAABLgAECn8jAAMTAAcJqSWDHwBrAgATAAcJqSWDHwBrAgAmAAYJ6RyODwCeAQAAAA==.Tristam:BAAALgAECgYJCwAAAA==.',
Ts='Tsavo:BAABLgAECn8nAAMPAAgJIxGELwBUAQAPAAgJIxGELwBUAQADAAEJBAWjoAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgUJEAAAAA==.Tuiren:BAAALgAECgcJBwAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgADCgkJFwAAAA==.Turgrok:BAABLgAECn8VAAIGAAcJwhkpCgCmAQAGAAcJwhkpCgCmAQAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAACLgAFFH8KAAINAAQJtRVZQwA/AQANAAQJtRVZQwA/AQAuAAQKfyUAAw0ACQm3JLwOAFEDAA0ACQm3JLwOAFEDAA4AAQl0IusWAGMAAAAA.Tyllen:BAAALgAECgYJBgABLgAFFAQJCgANALUVAA==.',
Un='Uniförm:BAABLgAECn8dAAMiAAkJyA+9HgB0AQAiAAkJyA+9HgB0AQAoAAEJTgQ6JgAjAAAAAA==.',
Us='Ushioo:BAAALgAECgQJBgAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAACLgAFFH8KAAMfAAMJ9Rk1EwDkAAAfAAMJ9Rk1EwDkAAApAAMJMAS7HgCjAAAuAAQKfzEAAh8ACQkZJYYBADADAB8ACQkZJYYBADADAAAA.Vainhellsing:BAABLgAECn8WAAMQAAkJYAcILgDXAAAQAAYJRwkILgDXAAAUAAcJgwQKmwDBAAAAAA==.Vampage:BAAALgAECgkJEwAAAA==.Vandeadly:BAAALgAECgYJDwABLgAECgkJHgAVAGMiAA==.Vannethir:BAAALgAECgQJBAABLgAFFAUJDgANAEUSAA==.Vanzen:BAAALgAECgYJBgAAAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8ZAAMBAAkJIxsMIgAyAgABAAkJRBoMIgAyAgAGAAcJfhV7MQCrAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8YAAIBAAkJvA9tMgDmAQABAAkJvA9tMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAFFAMJCgAfAPUZAA==.Verycurious:BAAALgAECgUJDwABLgAFFAIJAgAFAAAAAA==.Vexahlias:BAAALgAECgQJAwAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgcJEAABLgAECgkJPAAiAPUbAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgQJBAABLgAECgcJFwALACEQAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
Vy='Vyral:BAAALgAECgcJCQAAAA==.',
['Vá']='Váder:BAAALgAECggJEwAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAFFAMJBgAbABAWAA==.Wernov:BAABLgAECn8aAAIDAAgJTiAKFQB2AgADAAgJTiAKFQB2AgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8QAAIhAAUJlR8LBACCAQAhAAUJlR8LBACCAQAuAAQKfzMAAyEACQkkIPICANwCACEACQkkIPICANwCACQAAQlnFKo5AD0AAAAA.',
Wi='Wichan:BAABLgAECn85AAIhAAkJIB/iAwC4AgAhAAkJIB/iAwC4AgAAAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Win:BAAALgAECgEJAQAAAA==.Windrúnner:BAAALgAECgUJCQAAAA==.Wiziviji:BAABLgAECn8VAAINAAgJtQ0ZmgAqAQANAAgJtQ0ZmgAqAQAAAA==.',
Wo='Woodrow:BAABLgAECn8YAAIZAAgJjh7KIwDBAQAZAAgJjh7KIwDBAQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8eAAMHAAcJ8hkbGADlAQAHAAcJ8hkbGADlAQAIAAYJ4BOPTACtAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
['Wà']='Wàrrîor:BAAALgAECgIJAgAAAA==.',
Xa='Xanddlock:BAAALgADCgQJBAAAAA==.Xanorea:BAAALgADCgcJBwABLgAECggJEQAFAAAAAA==.',
Xc='Xclusive:BAAALgAECgEJAQAAAA==.',
Xf='Xfaith:BAAALgAECgEJAQAAAA==.Xfire:BAABLgAECn8XAAQWAAcJDxPjIAB2AQAWAAYJSBTjIAB2AQASAAQJUQ/mRQDFAAARAAEJdQuJIAA1AAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECggJEAAFAAAAAA==.',
Xr='Xray:BAAALgAECgYJBwAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAAALgAECggJDgAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.',
Yi='Yisoonshin:BAABLgAECn8UAAIdAAYJPyUmEgCDAgAdAAYJPyUmEgCDAgABLgAFFAIJAgAFAAAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJIQAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yuichi:BAAALgAECgEJAQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAAALgAECggJEwAAAA==.',
Za='Zagera:BAAALgADCgcJCAAAAA==.Zaka:BAAALgAECgMJAwABLgAFFAUJEAAKAFceAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECgkJEAAAAA==.Zango:BAAALgADCgMJAwAAAA==.Zanosuke:BAABLgAECn8WAAIiAAkJ5B9MCgBbAgAiAAkJ5B9MCgBbAgAAAA==.Zanzer:BAAALgADCgQJBAABLgAECgYJBgAFAAAAAA==.Zaria:BAABLgAECn8dAAIbAAcJmhNzeABsAQAbAAcJmhNzeABsAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zelkora:BAAALgADCgYJBgAAAA==.Zerica:BAAALgAECgMJBAAAAA==.Zerika:BAABLgAECn8gAAIJAAkJ1B/PBQD9AgAJAAkJ1B/PBQD9AgAAAA==.',
Zi='Zigzwag:BAAALgAECgYJDgAAAA==.Zionna:BAAALgADCgYJAQABLgAECgkJEgAFAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8XAAIEAAgJHBUrDgDaAQAEAAgJHBUrDgDaAQAAAA==.Zoose:BAAALgAECgEJAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8ZAAIeAAcJAhvELAABAgAeAAcJAhvELAABAgABLgAECgcJIwAiAH0NAA==.',
Zy='Zydis:BAAALgAECgcJEgAAAA==.',
['Ád']='Ádolín:BAAALgAECgMJAwAAAA==.',
['Än']='Ännihilation:BAAALgADCgkJFQAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQAFAAAAAA==.',
['És']='Éstéla:BAABLgAECn8wAAIBAAkJrBcnKQAPAgABAAkJrBcnKQAPAgAAAA==.',
['ßl']='ßlackøut:BAAALgAECgUJCAAAAA==.',
['ßr']='ßrïñcey:BAAALgAECgEJAgAAAA==.',
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
