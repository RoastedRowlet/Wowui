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

local lookup = {'Hunter-BeastMastery','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','Priest-Shadow','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Mage-Frost','Mage-Fire','Mage-Arcane','Shaman-Elemental','DemonHunter-Havoc','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Hunter-Survival','Paladin-Protection','Rogue-Assassination','Warrior-Arms',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAABLgAECn8eAAIBAAgJIAmFZwBcAQABAAgJIAmFZwBcAQAAAA==.Abrakadaver:BAAALgAECgYJCQABLgAECgkJIAACAIIcAA==.',
Ac='Activision:BAABLgAECn8VAAIDAAYJKxrMHgC3AQADAAYJKxrMHgC3AQAAAA==.',
Ad='Ademisk:BAAALgADCgYJEgAAAA==.Adventureux:BAACLgAFFH8JAAIBAAMJkhrHQwAAAQABAAMJkhrHQwAAAQAuAAQKfyIAAgEACQmHG2IrABkCAAEACQmHG2IrABkCAAAA.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8dAAIEAAgJehVoPQCcAQAEAAgJehVoPQCcAQAAAA==.',
Ai='Aiblul:BAABLgAFFH8FAAIFAAIJ2Rb7IwCoAAAFAAIJ2Rb7IwCoAAAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgcJEgABLgAFFAMJBwAGALgiAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgAHAAAAAA==.Aliroarx:BAAALgADCggJFAAAAA==.Almosteasy:BAABLgAECn8XAAIIAAgJLyPFBwAhAwAIAAgJLyPFBwAhAwAAAA==.Alunadoom:BAAALgAECgcJCgAAAA==.Alunagryn:BAACLgAFFH8IAAIJAAQJXAa2JgDfAAAJAAQJXAa2JgDfAAAuAAQKfyQABAkACAllGZwTABICAAkACAnHFZwTABICAAUABwk3F1wfAN0BAAMABQnpGG81AGgBAAAA.Alvera:BAABLgAECn8wAAIKAAkJwB8cHgCAAgAKAAkJwB8cHgCAAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgABLgAECgUJBQAHAAAAAA==.',
An='Anaflora:BAAALgADCgEJAQAAAA==.Anduin:BAAALgAECgYJCQAAAA==.Angechi:BAEALgADCgYJBgABLgAECgUJFAALAOgKAA==.Angerforge:BAAALgAECgcJBwAAAA==.Angrydk:BAABLgAECn8aAAMKAAgJdAlwiwA5AQAKAAgJCwhwiwA5AQAMAAcJswcvGADgAAAAAA==.',
Ar='Arielordril:BAAALgAECgYJDQAAAA==.Arm:BAACLgAFFH8GAAINAAIJEwOtOwBZAAANAAIJEwOtOwBZAAAuAAQKfzcAAw0ACQntGxoLAI4CAA0ACQntGxoLAI4CAA4ABwnBFjw1ANMBAAAA.Armee:BAABLgAECn8dAAIDAAkJWRrlDwBnAgADAAkJWRrlDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgYJCgAAAA==.',
As='Asmilwelme:BAAALgAECgQJCAAAAA==.Astrael:BAACLgAFFH8JAAMPAAMJBg4QcgDeAAAPAAMJBg4QcgDeAAAQAAEJnAYFBQA8AAAuAAQKfyAAAw8ACQmYEj9SAM0BAA8ACQnzET9SAM0BABEABQnaEKYOANkAAAAA.Aszayla:BAABLgAECn8kAAIPAAgJ7BKhXwCoAQAPAAgJ7BKhXwCoAQAAAA==.Aszea:BAAALgAECgYJCgAAAA==.',
Av='Avoidme:BAAALgAECgUJCgAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwAHAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8vAAISAAgJ6xF8KgDCAQASAAgJ6xF8KgDCAQABLgAECgkJHQATAL0HAA==.Azóg:BAABLgAECn86AAIKAAgJnxrNRQDeAQAKAAgJnxrNRQDeAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAFFAIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8gAAMUAAgJICBzAADiAQAUAAYJ9hxzAADiAQAVAAcJLCLiAwDbAQAuAAQKfygAAxUACQk9JvsBAJkDABUACQk9JvsBAJkDABQACAmMJCUEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAABLgAFFH8GAAIBAAMJ7Q9hTADpAAABAAMJ7Q9hTADpAAAAAA==.Barriss:BAAALgADCgEJAQAAAA==.',
Be='Beanvin:BAAALgAECgIJBQAAAA==.Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgcJDgABLgAFFAIJAgAHAAAAAA==.Beastoker:BAAALgAECggJEwAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAgJHgAPAIgiAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgAECgYJEAAAAA==.Beeto:BAACLgAFFH8WAAIWAAUJ9Bu9IQBdAQAWAAUJ9Bu9IQBdAQAuAAQKfxwAAhYACQkhHjokAJcCABYACQkhHjokAJcCAAAA.Bekdrop:BAABLgAECn8SAAIXAAYJbCEeSQCTAQAXAAYJbCEeSQCTAQABLgAFFAgJHgAPAIgiAA==.Benlian:BAEBLgAECn8UAAMLAAUJ6AokOQCWAAALAAUJ6AokOQCWAAAKAAUJYAQRBwGAAAAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8aAAIPAAYJ7hKnLwB/AQAPAAYJ7hKnLwB/AQAuAAQKfyMAAw8ACAkgIbkgAPECAA8ACAkgIbkgAPECABEAAQmmFUseADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.Bishtease:BAAALgADCgQJBAAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8ZAAIPAAYJdhhbIgCzAQAPAAYJdhhbIgCzAQAuAAQKfyoAAg8ACQl4HjQbAAoDAA8ACQl4HjQbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAACLgAFFH8cAAIOAAgJQhxKAwC8AgAOAAgJQhxKAwC8AgAuAAQKfxgAAw4ABwktJZ8VAIgCAA4ABwktJZ8VAIgCAA0AAgn1I2FHANEAAAEuAAUUBgkXABgAIhoA.Boof:BAABLgAECn8cAAIFAAkJpxlsGwACAgAFAAkJpxlsGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Bootyful:BAAALgAECgEJAQAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgAECgUJCQAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAAALgAECgkJEwAAAA==.Bruski:BAAALgAECgUJDAAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAFFAQJBwAVAA0WAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8YAAIWAAgJViKVQwAZAgAWAAgJViKVQwAZAgAAAA==.Bushgarden:BAAALgAECgQJBgABLgAECgkJIQAZAH8VAA==.Buzzbuzz:BAABLgAECn8VAAMJAAkJtxcAFwDoAQAJAAgJxhkAFwDoAQAFAAgJkBDfLQBJAQAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAIYAAYJIhodAgAKAgAYAAYJIhodAgAKAgAuAAQKfx8AAxgACQllHzMEABMDABgACQllHzMEABMDABQAAwn5Iu0iABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAIaAAMJaCDQIwD6AAAaAAMJaCDQIwD6AAABLgAFFAYJFwAYACIaAA==.',
['Bö']='Böba:BAAALgAECgYJBgABLgAFFAYJFwAYACIaAA==.',
Ca='Cadroyd:BAAALgAECgEJAQAAAA==.Caelin:BAABLgAECn8kAAIXAAcJ7RA1eAAVAQAXAAcJ7RA1eAAVAQAAAA==.Caishana:BAABLgAECn8yAAMEAAkJaiJLBwAoAwAEAAkJaiJLBwAoAwASAAEJGgYTpgAiAAAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAABLgAECn8UAAMDAAgJ+hUzHwCzAQADAAgJjBUzHwCzAQAJAAYJjg3DNQAYAQAAAA==.',
Ce='Cecil:BAABLgAECn8qAAMbAAkJUAdMNABrAQAbAAkJUAdMNABrAQAWAAMJbgS5JgFmAAAAAA==.Celeb:BAABLgAECn8oAAICAAgJ8CMJAQAyAwACAAgJ8CMJAQAyAwAAAA==.Celebrity:BAAALgAECgUJCgABLgAECggJKAACAPAjAA==.Celebtard:BAAALgAECgIJAgABLgAECggJKAACAPAjAA==.Cervitude:BAAALgAECgIJAwAAAA==.Cervrakabra:BAAALgAECgIJBAAAAA==.',
Ch='Chaddingus:BAAALgAECgkJEAAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgQJCAAAAA==.Chilltea:BAACLgAFFH8KAAIPAAMJ7SA4XQAXAQAPAAMJ7SA4XQAXAQAuAAQKfzIAAg8ACAlgJc4PAOkCAA8ACAlgJc4PAOkCAAAA.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8jAAQcAAcJfQplFgDuAAAcAAYJdwplFgDuAAAdAAYJ3wgEtgDPAAAZAAEJSgwQPAApAAAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAABLgAECn85AAIbAAkJ5iADBQAxAwAbAAkJ5iADBQAxAwAAAA==.',
Co='Coheedkil:BAAALgAECgUJBQAAAA==.Coldbreeze:BAAALgAECgMJAwAAAA==.Collateral:BAAALgAFFAEJAQAAAA==.Compaktdisc:BAAALgAECgkJEgAAAA==.Conartist:BAAALgAECggJDwABLgAFFAMJCQAeAL0lAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwAHAAAAAA==.Cowpox:BAABLgAECn8eAAIOAAkJWQ7PNwClAQAOAAkJWQ7PNwClAQAAAA==.',
Cp='Cpr:BAAALgAECgQJEAAAAA==.',
Cr='Creatrix:BAAALgAECgYJCAABLgAFFAMJCQAeAL0lAA==.Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAAALgAECgYJEAAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn9GAAIbAAgJvCORBwD/AgAbAAgJvCORBwD/AgAAAA==.Cruv:BAAALgAECgMJAwAAAA==.Cry:BAAALgAECgQJCgAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8RAAIfAAUJxh7sEwBeAQAfAAUJxh7sEwBeAQAuAAQKfyMAAh8ACQmIIDALANkCAB8ACQmIIDALANkCAAAA.',
Cy='Cybuster:BAAALgAECgcJDwABLgAFFAQJCgAPALUVAA==.Cyndle:BAAALgAECgYJBgABLgAECgkJGwADAMsXAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8cAAIPAAkJTxB/ewDaAQAPAAkJTxB/ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8bAAICAAkJDBXVCQDOAQACAAkJDBXVCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECggJDwAAAA==.Dakian:BAAALgADCgEJAQAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAABLgAECn8rAAIWAAgJvwhGmAApAQAWAAgJvwhGmAApAQABLgAECgUJGAATANsKAA==.Dargong:BAAALgAECggJAgAAAA==.Darkrunes:BAABLgAECn8dAAIXAAcJLho0PgD7AQAXAAcJLho0PgD7AQAAAA==.Darnwrath:BAAALgADCgUJBQAAAA==.Darrkness:BAABLgAFFH8GAAIdAAIJ2xDyjgCQAAAdAAIJ2xDyjgCQAAAAAA==.Darthvikingw:BAAALgADCgcJDAAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJDgAAAA==.Deaththrone:BAAALgADCgEJAQABLgAECgUJCgAHAAAAAA==.Deides:BAAALgADCgYJBwAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgUJCQABLgAECgkJJgALAOYUAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAABLgAECn8cAAIWAAgJpx/UJgBPAgAWAAgJpx/UJgBPAgAAAA==.Deristus:BAABLgAECn8pAAIdAAkJDBa0NAD5AQAdAAkJDBa0NAD5AQAAAA==.Deroth:BAAALgAECgEJBAAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAAHAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgAHAAAAAA==.Devi:BAAALgAECgIJAwABLgAECgcJCwAHAAAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dingeoffor:BAAALgAFFAMJAwABLgAFFAQJBwAJAJAMAA==.Dirtmonkgirt:BAABLgAECn8gAAIeAAkJ3BahEwALAgAeAAkJ3BahEwALAgAAAA==.Dirtnasty:BAAALgAFFAIJAgAAAA==.Dirtysham:BAABLgAECn8cAAISAAgJcBjJIQABAgASAAgJcBjJIQABAgAAAA==.Discipline:BAABLgAECn8lAAIFAAkJ/BeREgAiAgAFAAkJ/BeREgAiAgAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8cAAMKAAYJVRNfkQBdAQAKAAYJqBJfkQBdAQALAAYJnAxELgDSAAAAAA==.Dotdotgoose:BAAALgAECggJCwABLgAECgkJEgAHAAAAAA==.Dotgunner:BAABLgAECn8XAAIdAAcJXRtBQAANAgAdAAcJXRtBQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgkJIAAXAJYdAA==.Downbad:BAACLgAFFH8FAAIdAAMJdQcoJwDhAAAdAAMJdQcoJwDhAAAuAAQKfx8AAx0ACAl+H1wXAMgCAB0ACAl+H1wXAMgCABkABAm8Cwg1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJHQATAHgQAA==.Drahseer:BAAALgAECgIJAgAAAA==.Drakqueenjd:BAAALgADCgYJBgAAAA==.Drakulya:BAABLgAECn8YAAIWAAYJhws4ywDbAAAWAAYJhws4ywDbAAAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAABLgAECn8fAAMXAAgJ3Ax+ZABFAQAXAAgJhAx+ZABFAQATAAMJMghrWgB5AAAAAA==.Drewish:BAAALgADCgQJBAAAAA==.Driftèr:BAAALgAECgcJEgAAAA==.Drizzle:BAACLgAFFH8IAAIXAAMJHSTeMAA4AQAXAAMJHSTeMAA4AQAuAAQKfysAAhcACQmhJeQCAEwDABcACQmhJeQCAEwDAAAA.Drkdestro:BAABLgAECn8wAAQdAAkJByK8DwD8AgAdAAkJBSG8DwD8AgAcAAYJoh23CwB/AQAZAAEJyxzIXwBPAAAAAA==.Drktotem:BAAALgAECgYJBgAAAA==.Druidic:BAACLgAFFH8UAAIOAAUJDSRqCwAMAgAOAAUJDSRqCwAMAgAuAAQKfzgAAg4ACQlsJbkDAFYDAA4ACQlsJbkDAFYDAAAA.Drunkhorn:BAAALgADCgMJAwAAAA==.Druvinci:BAAALgAECgYJBgAAAA==.Drü:BAABLgAECn8UAAINAAkJDxLhLQCVAQANAAkJDxLhLQCVAQAAAA==.',
Du='Dumbledwarf:BAAALgAECgQJBAAAAA==.Duneshade:BAAALgADCgUJBQAAAA==.Dunk:BAAALgAECgEJAQAAAA==.Dusan:BAABLgAECn8pAAMDAAkJBB2pCgCmAgADAAkJBB2pCgCmAgAJAAYJmguFOgD+AAAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ea:BAAALgADCgYJCgAAAA==.Ear:BAAALgADCgcJBwABLgAFFAMJBgAGAMQPAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8lAAMEAAgJrBXcNgC5AQAEAAgJrBXcNgC5AQAGAAQJ/wK6IgCqAAAAAA==.',
Ed='Edonsian:BAACLgAFFH8FAAIgAAMJFxcpKgDnAAAgAAMJFxcpKgDnAAAuAAQKfzoAAyAACQktG7IaAAQCACAACQmjGrIaAAQCACEABQm2GsweACIBAAAA.',
Ee='Eepy:BAABLgAECn8aAAMaAAkJoBHtHQDGAQAaAAkJoBHtHQDGAQAeAAUJuxFGRADWAAAAAA==.',
Eg='Egmont:BAAALgAECgIJAgAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgAFFAIJAgABLgAECgcJGgAUAPscAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAABLgAECn8VAAIhAAgJlBQwFwBxAQAhAAgJlBQwFwBxAQAAAA==.Emorlyn:BAABLgAECn8XAAMBAAkJwg+sNADcAQABAAkJwg+sNADcAQAIAAYJpgIgZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Encanis:BAAALgAECgcJCwAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAACLgAFFH8NAAIPAAUJZBTITgAzAQAPAAUJZBTITgAzAQAuAAQKfx4AAg8ACAlDHBFNAE8CAA8ACAlDHBFNAE8CAAAA.',
Er='Eriksangus:BAABLgAECn8XAAIgAAgJ/wfTSAALAQAgAAgJ/wfTSAALAQAAAA==.',
Es='Eskarina:BAAALgADCgcJBwAAAA==.Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAABLgAECn80AAIOAAkJOxdvFwB4AgAOAAkJOxdvFwB4AgAAAA==.',
Ev='Evaporate:BAAALgAECgYJBgAAAA==.Evilguard:BAABLgAECn8mAAMLAAkJ5hQGFQCrAQALAAgJmRcGFQCrAQAMAAEJ/gFNOgAJAAAAAA==.Evilpatty:BAAALgAECgMJAwAAAA==.',
Ex='Excessive:BAAALgAECgEJAQAAAA==.Excorsism:BAAALgAFFAIJAgABLgAFFAQJDQAVAPAaAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECggJEwAAAA==.',
Fa='Falador:BAAALgAECgcJEAAAAA==.Fariebubbles:BAABLgAECn8iAAIOAAgJMxD2OwCSAQAOAAgJMxD2OwCSAQAAAA==.Fastandis:BAAALgAECgYJBgAAAA==.Fataldk:BAAALgAECgIJAgABLgAFFAMJBwAXAGcQAA==.Fatale:BAACLgAFFH8HAAIXAAMJZxA8VQDMAAAXAAMJZxA8VQDMAAAuAAQKfxQAAhcABgnZICU3ANMBABcABgnZICU3ANMBAAAA.Fatallock:BAAALgAECgUJBQABLgAFFAMJBwAXAGcQAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMdAAcJgRm/aQCQAQAdAAYJghq/aQCQAQAZAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAABLgAFFH8JAAMSAAMJFyBhGwAbAQASAAMJFyBhGwAbAQAEAAIJLQoQWQB1AAAAAA==.Fenixstraza:BAACLgAFFH8WAAQVAAUJNxaWNADSAAAVAAMJ1hmWNADSAAAYAAMJThfdHAC1AAAUAAIJVwunDABJAAAuAAQKf0AABBgACQkNHsIFAKMCABgACQkNHsIFAKMCABUACQmFGpIPAFUCABQAAQkAAFQqAAAAAAAA.Fervis:BAAALgAECgQJCAABLgAECggJFgAVABcKAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJEwABLgAECgcJFgAPADoMAA==.Firitako:BAAALgAECgcJEgAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECgkJPgAgAJclAA==.Flipper:BAABLgAECn8ZAAMbAAkJKxSrIgAJAgAbAAkJKxSrIgAJAgAWAAIJawFyRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8cAAQcAAkJgCCRAwBfAgAcAAkJgCCRAwBfAgAdAAMJmxG/GgE6AAAZAAEJtwRLQAAbAAAAAA==.Frankiejr:BAAALgAECgYJEQABLgAECgcJKgAWAKklAA==.Frapsity:BAABLgAECn8pAAMEAAgJbBaTJgANAgAEAAgJbBaTJgANAgASAAYJnQyzTQDiAAAAAA==.Frapss:BAAALgADCggJCAABLgAECggJKQAEAGwWAA==.Frostamper:BAAALgAECgYJDwAAAA==.Frostnite:BAABLgAECn8cAAIMAAgJdgoNEQAzAQAMAAgJdgoNEQAzAQAAAA==.Frostpoptart:BAABLgAECn8vAAIEAAkJ0xgAIgATAgAEAAkJ0xgAIgATAgAAAA==.Frozenblade:BAAALgAECgYJBgAAAA==.',
Fu='Fupah:BAAALgAECgIJAgAAAA==.Furball:BAAALgAECgMJAwABLgAFFAUJEAAdAM8SAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAACLgAFFH8QAAIfAAQJ7iKjDQCTAQAfAAQJ7iKjDQCTAQAuAAQKfyQAAx8ACQktIO0EAOcCAB8ACQktIO0EAOcCAB4AAQksBI2kACEAAAAA.Galadrielle:BAABLgAECn8UAAIPAAgJowH17AClAAAPAAgJowH17AClAAAAAA==.Gandelf:BAAALgAECgYJDAABLgAECggJLAABAEIfAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Garret:BAAALgADCgQJBAABLgAECgcJJAAXAO0QAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8pAAIiAAkJkAtSIgAXAQAiAAkJkAtSIgAXAQAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAACLgAFFH8IAAIXAAMJSRS1UADYAAAXAAMJSRS1UADYAAAuAAQKfzYAAhcACQm+IeMHAAEDABcACQm+IeMHAAEDAAAA.',
Gh='Ghostfate:BAAALgAECgEJAgAAAA==.',
Gi='Gigadoot:BAAALgAECgIJAgAAAA==.Gigbutt:BAABLgAECn88AAMjAAkJ9Rt3DQA4AgAjAAkJ9Rt3DQA4AgAkAAUJaxCHDQAfAQAAAA==.Giggles:BAAALgAECgIJAgAAAA==.Giggléz:BAAALgAECgcJCgAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAIPAAgJIBs8RABrAgAPAAgJIBs8RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgAECgEJAgAAAA==.Goatedfury:BAACLgAFFH8IAAIWAAQJEwJoYADOAAAWAAQJEwJoYADOAAAuAAQKfxQAAhYACAnVFYdpAIIBABYACAnVFYdpAIIBAAAA.Goblegoble:BAAALgAECgYJBgAAAA==.Googrektar:BAAALgAECgEJAQABLgAFFAUJEgAPABAaAA==.Goonietai:BAAALgADCgQJBAABLgAFFAUJEgAPABAaAA==.Gorgrot:BAAALgAECgcJCgABLgAFFAQJEgANAP0aAA==.Gorshot:BAABLgAECn8YAAIBAAkJwgzXRQC4AQABAAkJwgzXRQC4AQAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Greatvibes:BAAALgAECgUJCQABLgAFFAIJAgAHAAAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgAECgUJCAABLgAFFAMJCQAdABYXAA==.Griitz:BAABLgAECn8VAAIKAAgJ4RpaKwA+AgAKAAgJ4RpaKwA+AgAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAACLgAFFH8IAAIlAAMJriIiBgAtAQAlAAMJriIiBgAtAQAuAAQKfy0AAyUACQmDJb0AAF0DACUACQmDJb0AAF0DACIABgmRDwMXAAUBAAAA.Griswold:BAABLgAECn8aAAIZAAYJVhoBCwB0AQAZAAYJVhoBCwB0AQAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8gAAMPAAgJqRvkQAB2AgAPAAgJqRvkQAB2AgARAAEJ0ibSFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJIAAPAKkbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8NAAMKAAQJkx1uXAAiAQAKAAMJSSNuXAAiAQALAAMJLg8sIgCvAAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJCAAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8kAAIFAAkJKg0YIgCXAQAFAAkJKg0YIgCXAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.Hawtdonna:BAAALgAECgcJCgAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8uAAQdAAkJYCKpCwDlAgAdAAkJYCKpCwDlAgAZAAMJeh4PMQD1AAAcAAEJzAQqOwAkAAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAwAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAABLgAECn8XAAIWAAkJvRccPQAwAgAWAAkJvRccPQAwAgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECgkJFQAJALcXAA==.Hoofrat:BAAALgAECgcJBQAAAA==.Hornivore:BAAALgADCgkJEAAAAA==.',
Hp='Hpal:BAAALgAECgUJBQAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.Huxley:BAAALgAECgIJAgAAAA==.Huñted:BAABLgAECn8bAAMmAAgJAxNhHgCaAQAmAAgJnQ9hHgCaAQABAAYJIw7UYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgAECgQJCgAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgcJDAAHAAAAAA==.',
Ic='Icefrosting:BAAALgAECgUJBQABLgAECgkJJAAFAGkaAA==.Icuris:BAAALgAECgMJBQAAAA==.',
Id='Idistroya:BAABLgAECn8fAAILAAcJhBHCIAAzAQALAAcJhBHCIAAzAQABLgAECgkJUAABAKEjAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ig='Iggnogg:BAAALgADCgIJAgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMcAAgJYBWQCADBAQAcAAYJ1BiQCADBAQAdAAgJCRFkXAB+AQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8XAAIDAAgJkhVVGwACAgADAAgJkhVVGwACAgAAAA==.Ilithiya:BAAALgAFFAEJAQAAAA==.Ilk:BAAALgAECgQJBQAAAA==.Illidrac:BAABLgAECn8dAAITAAkJeBDjGgCFAQATAAkJeBDjGgCFAQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJGgAUAPscAA==.Illudari:BAAALgAECgMJAwABLgAECgcJGgAUAPscAA==.Illududu:BAAALgAECgYJDwABLgAECgcJGgAUAPscAA==.',
Im='Imangry:BAABLgAECn8oAAInAAgJ9hKYEQCSAQAnAAgJ9hKYEQCSAQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inconsolable:BAAALgADCgMJAwAAAA==.Inpherno:BAAALgAFFAEJAQAAAA==.',
Is='Isaidnoice:BAABLgAECn8hAAMZAAkJfxWgFgCVAQAZAAcJ+RagFgCVAQAdAAgJpg+ZWACIAQAAAA==.Ishton:BAABLgAFFH8IAAIWAAMJegcVZADFAAAWAAMJegcVZADFAAAAAA==.Istompgnomes:BAABLgAECn8WAAISAAgJDBhWGwDtAQASAAgJDBhWGwDtAQAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgcJEwAAAA==.',
Ja='Jacked:BAABLgAECn8fAAMdAAkJLR4MPQDaAQAdAAcJxxsMPQDaAQAcAAQJ/hzBEAAhAQAAAA==.Jasøn:BAAALgAECggJEAAAAA==.',
Je='Jecka:BAABLgAECn8pAAMFAAkJlRXZLQBJAQAFAAcJ/BHZLQBJAQADAAgJVg26QgAuAQAAAA==.Jeckah:BAAALgAECgYJCwABLgAECgkJKQAFAJUVAA==.Jecthyr:BAAALgAECgEJAQABLgAECgkJKQAFAJUVAA==.Jefryepsteen:BAAALgAECgcJDAAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAABLgAECn8kAAIDAAcJ4BmeHQDAAQADAAcJ4BmeHQDAAQAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8aAAMnAAYJBB46FgBWAQAnAAYJBB46FgBWAQAWAAEJrwL0WQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jm='Jmoney:BAAALgAECgEJAQAAAA==.',
Jo='Jordana:BAABLgAECn8bAAIOAAkJ0hVdNQCxAQAOAAkJ0hVdNQCxAQAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJBAAAAA==.',
Js='Jsdruid:BAAALgAECgcJDQAAAA==.',
Ju='Jug:BAABLgAECn8cAAImAAgJqBuXBADPAgAmAAgJqBuXBADPAgAAAA==.Julaudette:BAAALgAECgQJBwAAAA==.',
Ka='Kainöa:BAAALgAECgYJEwABLgAFFAIJAgAHAAAAAA==.Kakum:BAAALgAECgcJDgAAAA==.Kaldrogo:BAAALgAECgQJCwAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAcJJQAaAJgaAA==.Kalnuggets:BAAALgAECgYJCwAAAA==.Kalrathen:BAABLgAECn8fAAIDAAgJxRK+LgCJAQADAAgJxRK+LgCJAQAAAA==.Kamiyakaoru:BAAALgAECgQJBAAAAA==.Kaniku:BAAALgAECgEJBAABLgAFFAUJEgAPABAaAA==.Karmafel:BAAALgAECgUJDwABLgAECgcJDgAHAAAAAA==.Karsh:BAABLgAECn8gAAIgAAkJBwcrOQBMAQAgAAkJBwcrOQBMAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAABLgAECn8fAAMdAAgJZhghNQD4AQAdAAgJZhghNQD4AQAZAAYJoQw3JAA4AQAAAA==.Kazurena:BAAALgADCgcJCQAAAA==.',
Kd='Kdb:BAAALgAFFAQJBAABLgAFFAUJFAAOAA0kAA==.',
Ke='Keen:BAAALgAECgEJAQAAAA==.Kered:BAAALgAECgYJEwABLgAFFAMJCgAOAOAaAA==.Keuaakepo:BAABLgAECn9QAAMBAAkJoSNyBwARAwABAAkJoSNyBwARAwAmAAEJUQM9MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8pAAIBAAgJtRvvNwDnAQABAAgJtRvvNwDnAQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECggJCwABLgAECgkJEgAHAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgUJCQAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAABLgAECn8VAAIJAAYJfQkrPgDqAAAJAAYJfQkrPgDqAAAAAA==.',
Ko='Korbanhavoc:BAAALgAECgcJDQAAAA==.Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8qAAMlAAkJMhdwBwBBAgAlAAkJMhdwBwBBAgAiAAIJ0AwgKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJDwAAAA==.',
Kr='Krethar:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Krypt:BAABLgAECn8pAAIhAAkJWxe3DgDnAQAhAAkJWxe3DgDnAQAAAA==.Krìzl:BAACLgAFFH8JAAIPAAMJRR5mYAAOAQAPAAMJRR5mYAAOAQAuAAQKfzAAAg8ACAnDI5MjAHgCAA8ACAnDI5MjAHgCAAEuAAUUBgkeAAoAHSUA.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgQJBAAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAACLgAFFH8JAAQdAAMJFhe3YwDiAAAdAAMJChO3YwDiAAAcAAEJ0RTUGABUAAAZAAEJWhVOHwBNAAAuAAQKfzoABBkACQl6IlsDAL0CABkACAmIIVsDAL0CAB0ABwkRH3IdAGYCABwAAQkeHlEzADsAAAAA.Lanzen:BAAALgAECgEJAQABLgAECgYJBgAHAAAAAA==.Lanzier:BAAALgAECgUJBQABLgAECgYJBgAHAAAAAA==.Larrfena:BAABLgAECn8qAAIBAAgJVh7ZHgBXAgABAAgJVh7ZHgBXAgAAAA==.',
Le='Legit:BAAALgAECgcJDAABLgAECggJHQAXAC4aAA==.Legsday:BAAALgAECgMJAwAAAA==.Lementz:BAACLgAFFH8UAAIGAAUJDiCtAADIAQAGAAUJDiCtAADIAQAuAAQKf0EAAgYACQniJiYAAIoDAAYACQniJiYAAIoDAAAA.Lexiiees:BAABLgAECn8bAAIjAAcJ7QQnNADpAAAjAAcJ7QQnNADpAAAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAAALgAECgYJEwABLgAECgcJFgAPADoMAA==.Lillia:BAABLgAECn8pAAIdAAkJShEMRgC9AQAdAAkJShEMRgC9AQAAAA==.',
Lo='Lockyshocky:BAAALgADCgcJDAAAAA==.Lovetobussy:BAABLgAECn8lAAMDAAYJLiAfFQAVAgADAAYJLiAfFQAVAgAFAAIJ7w26YwBeAAAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn9KAAQdAAkJ8yJ0BgAeAwAdAAkJ8yJ0BgAeAwAZAAUJhR1/GwBxAQAcAAMJ9hxEIQCMAAAAAA==.Lumpia:BAACLgAFFH8IAAIKAAMJpBKlggDdAAAKAAMJpBKlggDdAAAuAAQKfyUAAgoACQmWIBUVALYCAAoACQmWIBUVALYCAAAA.',
['Lè']='Lèah:BAAALgAECgUJCgAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAIJAgABLgAFFAUJEAAPALgfAA==.Madgeyoulook:BAAALgAECgEJAQAAAA==.Magenta:BAAALgAECgUJBQAAAA==.Magicchoc:BAAALgAECgYJDAABLgAECgkJJgALAOYUAA==.Maktah:BAACLgAFFH8JAAIGAAQJMwkYCQAGAQAGAAQJMwkYCQAGAQAuAAQKfxUAAwYACAkvGaQMAMsBAAYACAkvGaQMAMsBABIAAQl0EOGFADUAAAAA.Mandrakor:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgcJBwABLgAFFAUJEAAPALgfAA==.Marshboa:BAAALgAFFAIJAgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mcgurk:BAAALgAECgkJEgAAAA==.Mclovinit:BAACLgAFFH8eAAIPAAgJiCLwAgDVAgAPAAgJiCLwAgDVAgAuAAQKf1MAAg8ACQmqJnoAAAIEAA8ACQmqJnoAAAIEAAAA.Mcmagic:BAACLgAFFH8HAAIPAAQJPxo5YAAPAQAPAAQJPxo5YAAPAQAuAAQKfy4AAg8ACAlPI0kaAKYCAA8ACAlPI0kaAKYCAAEuAAUUCAkeAA8AiCIA.Mcpally:BAABLgAECn85AAIWAAkJUCL4DADoAgAWAAkJUCL4DADoAgAAAA==.',
Me='Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8dAAIOAAkJeCO3CAADAwAOAAkJeCO3CAADAwAAAA==.Mensu:BAAALgAECgYJCwAAAA==.Mentos:BAABLgAECn8tAAMUAAkJHRpgAwBQAgAUAAkJHRpgAwBQAgAYAAYJJx5YDQDpAQAAAA==.Mercilezz:BAAALgAECgIJAgAAAA==.',
Mi='Midwestfel:BAABLgAECn8cAAIXAAgJzwZvoADCAAAXAAgJzwZvoADCAAAAAA==.Mikeoxhard:BAAALgAECggJDwAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAACLgAFFH8FAAIFAAMJNwk/IQDEAAAFAAMJNwk/IQDEAAAuAAQKfx0AAgUACQk3E18fAKwBAAUACQk3E18fAKwBAAAA.Minihulk:BAABLgAECn8ZAAQMAAcJlgi+FwDlAAAMAAcJlgi+FwDlAAAKAAMJgwPhGAFnAAALAAMJowEiTQBFAAAAAA==.Mionn:BAAALgAECgUJDgAAAA==.Misshell:BAAALgAECgEJAwAAAA==.Mistsmoker:BAAALgAECgYJBgABLgAFFAUJFQAiAOMgAA==.',
Ml='Mlleena:BAABLgAECn8xAAMdAAcJahAQcwBJAQAdAAcJahAQcwBJAQAcAAMJxAr9GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8nAAMZAAkJVhmXBgBkAgAZAAcJqR2XBgBkAgAdAAYJFheuSgCvAQAAAA==.Moloch:BAAALgAECgEJAgAAAA==.Monangai:BAAALgAECgcJEQABLgAECgcJFgAPADoMAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBwAAAA==.Mooncake:BAAALgAECggJEgAAAA==.Moosiah:BAACLgAFFH8KAAIOAAMJ4BoWLQDwAAAOAAMJ4BoWLQDwAAAuAAQKfzIAAw4ACAljHsMQALgCAA4ACAljHsMQALgCAA0ACAm3IS0TACUCAAAA.Mortenerra:BAABLgAECn8aAAIDAAYJ/BW6LgBBAQADAAYJ/BW6LgBBAQAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfire:BAAALgAFFAEJAQAAAA==.Mossfiré:BAAALgAECgYJEAABLgAFFAEJAQAHAAAAAA==.Motoko:BAABLgAECn8qAAQeAAkJGxUlIgCJAQAeAAgJnxYlIgCJAQAaAAYJLxIFNgAWAQAfAAYJ6QiMSADKAAAAAA==.',
Mu='Muatamuata:BAAALgAECgIJBAAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECgkJEgAHAAAAAA==.',
My='Myhealmissed:BAAALgADCggJCAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECggJEAAHAAAAAA==.Møøfi:BAAALgAECgYJDgAAAA==.',
Na='Nachomonk:BAAALgAECgQJBgAAAA==.Nachoshamy:BAAALgAECgUJBQAAAA==.Nameless:BAABLgAECn8nAAMRAAkJxxaIBQDUAQAPAAkJ0RIDSwDjAQARAAYJzhqIBQDUAQAAAA==.Narc:BAABLgAECn8iAAIOAAgJIAf1ZAD0AAAOAAgJIAf1ZAD0AAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Narissa:BAAALgADCgQJBAAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAACLgAFFH8IAAMBAAQJHxUpNQAqAQABAAQJHxUpNQAqAQAIAAEJnQFyLQA8AAAuAAQKfy4AAwEACQmrISYPAMQCAAEACQkyISYPAMQCAAgACQk+F3YQALkCAAAA.Nazure:BAAALgAECgYJBgAAAA==.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn8/AAIBAAkJSBqmGAB8AgABAAkJSBqmGAB8AgAAAA==.New:BAAALgAECgEJAQAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgAECgIJAgAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECgkJIQAfACQdAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8PAAMdAAYJpxCEMABbAQAdAAYJFg6EMABbAQAcAAIJExlSHgBMAAAuAAQKfyoABBkACQm5HQgPANoBABkABwkgGAgPANoBAB0ABwk9GuNGALoBABwABgnfFaQSAB0BAAAA.',
No='Noova:BAABLgAECn8yAAIPAAcJ4CCNUABFAgAPAAcJ4CCNUABFAgAAAA==.Norooux:BAAALgADCgkJDQAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJCAAJAFwGAA==.',
Ob='Obliverat:BAAALgAECgcJDwAAAA==.',
Od='Odysseus:BAAALgADCgUJBQAAAA==.',
Of='Of:BAAALgAECgMJAwAAAA==.',
Ol='Oldmangp:BAAALgADCgMJBQAAAA==.Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgUJDAAAAA==.',
Op='Oprawindfúry:BAAALgAECgEJAQAAAA==.',
Or='Orangesorbet:BAAALgAECgEJAQAAAA==.Orcaneblast:BAACLgAFFH8SAAIPAAUJEBp/PgBRAQAPAAUJEBp/PgBRAQAuAAQKfywAAg8ACQnkIVMRAN8CAA8ACQnkIVMRAN8CAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDwAAAA==.Ornn:BAABLgAECn8oAAIhAAgJUiKjCABbAgAhAAgJUiKjCABbAgAAAA==.',
Pa='Palmtalon:BAAALgAECgMJBwAAAA==.Pandaminium:BAAALgAECgEJAQAAAA==.Pandarias:BAAALgAECgQJBQAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Paranoià:BAAALgAECgUJBQABLgAECgUJBQAHAAAAAA==.Partypizza:BAABLgAECn8xAAISAAkJdR4MDACPAgASAAkJdR4MDACPAgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAUJFAAOAA0kAA==.Penne:BAAALgAECgYJBwABLgAFFAUJEAAPALgfAA==.Permanence:BAABLgAECn8UAAIXAAYJARZ3bQBbAQAXAAYJARZ3bQBbAQAAAA==.',
Ph='Phoeniex:BAAALgAECgUJBQABLgAECgkJIQAfACQdAA==.Phoenixphyre:BAAALgADCgUJBQAAAA==.',
Pi='Picobuffu:BAAALgAECgYJDAABLgAFFAMJCQAXAJIUAA==.Picodedge:BAACLgAFFH8JAAIXAAMJkhRfUADZAAAXAAMJkhRfUADZAAAuAAQKfy4AAxcACAlDHYsvAPMBABcACAlDHYsvAPMBABMAAQn0DVZhADAAAAAA.Picoroo:BAAALgAECgcJEAABLgAFFAMJCQAXAJIUAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pinkgauge:BAAALgAECggJCAAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn81AAMPAAkJDxvOLgBHAgAPAAkJGxrOLgBHAgAQAAYJZxYkBACdAQAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgQJBwAAAA==.Porcini:BAAALgADCgMJAwAAAA==.Portent:BAAALgAECgEJAQAAAA==.Porthos:BAAALgADCgcJDAAAAA==.Poõpsikens:BAAALgAECgMJAwAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAIdAAcJwBmlYwCfAQAdAAcJwBmlYwCfAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAwAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8UAAIKAAUJ9h/4NQBoAQAKAAUJ9h/4NQBoAQAuAAQKfz8AAwoACQmqIk4KAA0DAAoACQmqIk4KAA0DAAwABQkqFwsUABABAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qq='Qqpewpew:BAAALgAECgcJDwAAAA==.',
Qt='Qtpi:BAABLgAECn8gAAIXAAkJlh0OIQA7AgAXAAkJlh0OIQA7AgAAAA==.',
Qu='Quica:BAAALgAECgEJAQABLgAECgcJFgAPADoMAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAIPAAgJWxmDQwBuAgAPAAgJWxmDQwBuAgABLgAFFAgJGwAPALAaAA==.Raketh:BAABLgAECn8WAAIVAAgJFwopPgAQAQAVAAgJFwopPgAQAQAAAA==.Rallek:BAABLgAECn8wAAIbAAkJfhmHFwA1AgAbAAkJfhmHFwA1AgAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECggJKAAhAFIiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAABLgAECn8UAAIYAAkJYR7GCwB5AgAYAAkJYR7GCwB5AgAAAA==.Rehabherox:BAAALgADCgcJDgAAAA==.Rejuvince:BAAALgAECgUJBQAAAA==.Rektek:BAABLgAECn8aAAIgAAkJWBRVNADZAQAgAAkJWBRVNADZAQAAAA==.Rektnasty:BAAALgAECgMJBgAAAA==.Remeras:BAABLgAECn8cAAIWAAkJqxAAXgDJAQAWAAkJqxAAXgDJAQAAAA==.Resilientaid:BAABLgAECn8iAAIOAAYJeh8GJAAYAgAOAAYJeh8GJAAYAgAAAA==.Restolyfe:BAAALgAECgUJEAAAAA==.Retack:BAAALgAECgEJBAAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8mAAQaAAkJ/A3pPABJAQAaAAkJ/A3pPABJAQAfAAIJygssdwBlAAAeAAEJsASChQArAAAAAA==.Rilzi:BAAALgAECggJCgAAAA==.Ripblast:BAAALgAECgEJAQABLgAECgkJIQAfACQdAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAABLgAECn8YAAMlAAgJbyD5BwAwAgAlAAcJBiD5BwAwAgAOAAEJCAdMxwAwAAABLgAECgkJPAAjAPUbAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Rohar:BAAALgAECgcJDgAAAA==.Roley:BAAALgADCgcJCgAAAA==.Rolybones:BAAALgAECgMJAwAAAA==.Roots:BAABLgAECn8UAAIOAAYJyAxRaQDmAAAOAAYJyAxRaQDmAAAAAA==.Rosalie:BAAALgAECgMJAwAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgAECgMJAwAAAA==.Rossick:BAAALgAECgkJCQAAAA==.Roviz:BAAALgAECgYJBgABLgAFFAMJCgAhAPUZAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAwAAAA==.Ruuf:BAABLgAECn8sAAISAAkJmgtNMgBZAQASAAkJmgtNMgBZAQAAAA==.',
Ry='Rynohtwo:BAAALgAECgYJDgAAAA==.Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sabrinaa:BAAALgADCgYJBgAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgAECgIJBAAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgQJBwAAAA==.',
Sc='Scalylusion:BAABLgAECn8aAAMUAAcJ+xx/EADvAAAVAAYJ6RjkLQBTAQAUAAYJ2xp/EADvAAAAAA==.Scrivener:BAAALgADCgcJCQAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.Scuddy:BAAALgADCgcJBwAAAA==.',
Se='Seanconery:BAAALgAECgcJDAAAAA==.Sebalen:BAAALgADCgEJAQAAAA==.Senica:BAABLgAECn8pAAIDAAkJUh07EgBPAgADAAkJUh07EgBPAgAAAA==.Sensedeous:BAAALgADCgcJDgAAAA==.Seriphina:BAAALgAECgYJCAAAAA==.Seventhsèal:BAACLgAFFH8IAAIKAAIJ0x6gowCkAAAKAAIJ0x6gowCkAAAuAAQKfxwAAwoABwmEI8oxACMCAAoABwmEI8oxACMCAAsABQl7FiAkACABAAAA.',
Sh='Shabbarankz:BAABLgAECn8dAAIlAAgJABYOCwASAgAlAAgJABYOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAABLgAECn80AAIGAAkJUBAmDADTAQAGAAkJUBAmDADTAQAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgYJCAABLgAECgkJIQAfACQdAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAABLgAECn8WAAIPAAcJOgyBzQDWAAAPAAcJOgyBzQDWAAAAAA==.Sheepwreck:BAAALgAECgQJBAAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shinedown:BAAALgAECgEJAQAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgAECgEJAQAAAA==.Shotbot:BAAALgADCgYJBgABLgAFFAUJCwAWAAISAA==.Shra:BAABLgAECn8hAAIiAAkJMhEaFgB+AQAiAAkJMhEaFgB+AQAAAA==.Shrafu:BAAALgAECgYJDQAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECggJFgAVABcKAA==.Sindracosa:BAABLgAECn8XAAMUAAYJsgqMIAApAQAUAAYJsgqMIAApAQAYAAYJiQUZLwD5AAABLgAECgkJHQATAHgQAA==.Sindradori:BAAALgADCgMJAwABLgAECgkJHAAFAKcZAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinoshi:BAAALgADCgcJCQAAAA==.Sinsidious:BAAALgADCggJFwAAAA==.Sizzle:BAAALgAECgkJDQABLgAECgkJFQAJALcXAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAABLgAECn8bAAIjAAkJiRUtFgBcAgAjAAkJiRUtFgBcAgAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAABLgAECn8YAAISAAgJMRNeKwCAAQASAAgJMRNeKwCAAQAAAA==.Smokindots:BAABLgAECn8mAAIdAAkJbRrtOQDlAQAdAAkJbRrtOQDlAQABLgAFFAMJCQAEAOMhAA==.Smokinloud:BAAALgAECgcJEwAAAA==.Smokinmyrrh:BAAALgAECggJEgABLgAFFAMJCQAEAOMhAA==.Smokinperiod:BAAALgADCgQJBAAAAA==.Smokinpsalm:BAABLgAECn8cAAMDAAcJ6xs2HAD7AQADAAcJ6xs2HAD7AQAFAAYJYAjHSQDBAAABLgAFFAMJCQAEAOMhAA==.Smokintotem:BAACLgAFFH8JAAIEAAMJ4yHDJQArAQAEAAMJ4yHDJQArAQAuAAQKf0UAAwQACQkIIcYPALwCAAQACQkIIcYPALwCABIAAQlTJa90AGsAAAAA.',
Sn='Sneakingbush:BAABLgAECn8sAAMjAAcJsA+jLACaAQAjAAcJoA+jLACaAQAoAAQJ8greEwDCAAAAAA==.Snowberry:BAAALgAECgMJBAAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8OAAISAAUJfxHnDgB/AQASAAUJfxHnDgB/AQAuAAQKfxwAAxIACAlZFUgmAN8BABIACAlZFUgmAN8BAAYAAwmxBWgkAJIAAAEuAAUUBgkaAA8A7hIA.Spaghett:BAACLgAFFH8QAAIPAAUJuB8UNABvAQAPAAUJuB8UNABvAQAuAAQKfxQAAg8ACAmFGStlAJoBAA8ACAmFGStlAJoBAAAA.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAACLgAFFH8JAAIeAAMJvSUGDABLAQAeAAMJvSUGDABLAQAuAAQKfzAAAx4ACAmVJY0HAL0CAB4ACAlmJY0HAL0CAB8ABgnDIGQaAMEBAAAA.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAABLgAECn8cAAINAAkJBxGHGwDUAQANAAkJBxGHGwDUAQAAAA==.Stvr:BAAALgADCgEJAQAAAA==.',
Su='Sugarcookie:BAAALgAECgIJAgABLgAECgkJJgALAOYUAA==.Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgUJBwABLgAECgkJJwARAMcWAA==.Sundowning:BAABLgAECn8cAAIFAAkJzhUbFgD9AQAFAAkJzhUbFgD9AQAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sv='Svenya:BAAALgADCgYJBgAAAA==.',
Sw='Sweatsicle:BAAALgADCgUJCAABLgAFFAMJCAAlAK4iAA==.Swiftdragon:BAABLgAECn8hAAMfAAkJJB0ZCAChAgAfAAkJJB0ZCAChAgAaAAYJrRQONgBrAQAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECgkJHAAcAIAgAA==.',
Sy='Sylerwinassa:BAAALgAECgUJCQAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Sylvy:BAEALgAECgUJBgABLgAECgUJFAALAOgKAA==.Symbolofhope:BAABLgAFFH8HAAIJAAQJkAyvIwD8AAAJAAQJkAyvIwD8AAAAAA==.Synjo:BAABLgAECn80AAIMAAgJgBwHCQDJAQAMAAgJgBwHCQDJAQAAAA==.',
Ta='Taapfer:BAABLgAECn8gAAMCAAkJghwlAwCtAgACAAkJghwlAwCtAgAXAAEJAAAVJwEAAAAAAA==.Tackyh:BAAALgAECgcJDgAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwABLgAECggJEAAHAAAAAA==.Tassidar:BAAALgAECgUJCgAAAA==.Taxevelle:BAAALgAECgEJAQABLgAECgkJPgAgAJclAA==.Taxii:BAABLgAECn8+AAMgAAkJlyU6AQBmAwAgAAkJlyU6AQBmAwApAAUJwRrVJwAYAQAAAA==.',
Te='Teapots:BAACLgAFFH8HAAIGAAMJuCKjBgA3AQAGAAMJuCKjBgA3AQAuAAQKfxsAAgYACQnBIlQLAOMBAAYACQnBIlQLAOMBAAAA.Teegria:BAAALgADCgYJBgAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAACLgAFFH8HAAIFAAMJXQ8iHwDVAAAFAAMJXQ8iHwDVAAAuAAQKfyUAAwUACQk7F7oeALABAAUACQk7F7oeALABAAMAAQmUCTV+ADUAAAAA.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgkJOQAbAOYgAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAACLgAFFH8LAAIWAAUJAhL9OgAeAQAWAAUJAhL9OgAeAQAuAAQKfykAAhYACQn4HhoRAAcDABYACQn4HhoRAAcDAAAA.Thefifth:BAACLgAFFH8YAAIYAAcJFw7yAgDiAQAYAAcJFw7yAgDiAQAuAAQKfyoABBgACQlUGnsOAFACABgACQlUGnsOAFACABUACAncGf8TACQCABQAAwk3Et8yAH8AAAAA.Theralendris:BAABLgAECn8hAAICAAkJ3BT4BwDkAQACAAkJ3BT4BwDkAQAAAA==.Thickarm:BAAALgAFFAIJAgAAAA==.Thyrn:BAAALgADCgYJBgABLgAECggJKAAhAFIiAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8jAAIKAAkJAhoDNQAXAgAKAAkJAhoDNQAXAgAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAUJEgAPABAaAA==.Treebeard:BAAALgAECgQJBAAAAA==.Tri:BAABLgAECn8qAAMWAAcJqSVzIQBqAgAWAAcJqSVzIQBqAgAnAAYJ6RwWEQCbAQAAAA==.Tristam:BAAALgAECggJDgAAAA==.',
Ts='Tsavo:BAABLgAECn8nAAMSAAgJIxGQMwBSAQASAAgJIxGQMwBSAQAEAAEJBAWjoAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgUJEAAAAA==.Tuiren:BAAALgAECgcJBwAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgAECgEJAQAAAA==.Turgrok:BAABLgAECn8ZAAIIAAgJ9Bl9BwD5AQAIAAgJ9Bl9BwD5AQAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQAHAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAACLgAFFH8KAAIPAAQJtRVPTgA0AQAPAAQJtRVPTgA0AQAuAAQKfyUAAw8ACQm3JLwOAFEDAA8ACQm3JLwOAFEDABEAAQl0IusWAGMAAAAA.Tyllen:BAAALgAECggJDgABLgAFFAQJCgAPALUVAA==.',
Un='Uniförm:BAABLgAECn8dAAMjAAkJyA95IQBvAQAjAAkJyA95IQBvAQAoAAEJTgTvKAAjAAAAAA==.',
Us='Ushioo:BAAALgAECgQJBgAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAACLgAFFH8KAAMhAAMJ9RkAFgDVAAAhAAMJ9RkAFgDVAAApAAMJMAQ1JQChAAAuAAQKfzEAAiEACQkZJfwBACUDACEACQkZJfwBACUDAAAA.Vainhellsing:BAABLgAECn8dAAMTAAkJvQdtMgDTAAATAAYJRwltMgDTAAAXAAcJ1AWKngDGAAAAAA==.Vampage:BAAALgAECgkJEwAAAA==.Vandeadly:BAAALgAECgYJDwABLgAECgkJHgALAGMiAA==.Vannethir:BAAALgAECgQJBAABLgAFFAUJEgAPABAaAA==.Vanzen:BAAALgAECgYJBgAAAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8ZAAMBAAkJIxtkJgAwAgABAAkJRBpkJgAwAgAIAAcJfhV7MQCrAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8YAAIBAAkJvA9tMgDmAQABAAkJvA9tMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAFFAMJCgAhAPUZAA==.Verycurious:BAAALgAECgUJDwABLgAFFAIJAgAHAAAAAA==.Vexahlias:BAAALgAFFAIJAgAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgcJEAABLgAECgkJPAAjAPUbAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgQJBAABLgAECgcJFwANACEQAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
Vy='Vyral:BAAALgAECggJCgAAAA==.',
['Vá']='Váder:BAAALgAECggJEwAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAFFAMJCQAdABYXAA==.Wernov:BAABLgAECn8aAAIEAAgJTiDqFwByAgAEAAgJTiDqFwByAgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8VAAIiAAUJ4yDbBACJAQAiAAUJ4yDbBACJAQAuAAQKfz4AAyIACQkkIGwDANwCACIACQkkIGwDANwCACUAAQlnFBVBADwAAAAA.',
Wi='Wichan:BAABLgAECn88AAIiAAkJRx96BAC3AgAiAAkJRx96BAC3AgAAAA==.Wildstrike:BAAALgAECgYJBgABLgAECgkJKgAeABsVAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Win:BAAALgAECgMJBQAAAA==.Windrúnner:BAAALgAECgUJCQAAAA==.Wiziviji:BAABLgAECn8VAAIPAAgJtQ1CnAAmAQAPAAgJtQ1CnAAmAQAAAA==.',
Wo='Woodrow:BAABLgAECn8YAAIbAAgJjh77KQDhAQAbAAgJjh77KQDhAQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8eAAMJAAcJ8hngGgDXAQAJAAcJ8hngGgDXAQAFAAYJ4BNWTwCrAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
['Wà']='Wàrrîor:BAAALgAECgMJAwAAAA==.',
Xa='Xanddlock:BAAALgADCgYJBgAAAA==.Xanorea:BAAALgADCgcJBwABLgAECggJEQAHAAAAAA==.',
Xc='Xclusive:BAAALgAECgEJAQAAAA==.',
Xf='Xfaith:BAAALgAECgEJAgAAAA==.Xfire:BAABLgAECn8XAAQYAAcJDxPjIAB2AQAYAAYJSBTjIAB2AQAVAAQJUQ/mRQDFAAAUAAEJdQvIIgA1AAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECggJEAAHAAAAAA==.',
Xr='Xray:BAAALgAECgYJBwAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAABLgAECn8UAAIKAAgJ5xjMMgAfAgAKAAgJ5xjMMgAfAgAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.Yezdi:BAAALgAECgkJBAAAAA==.',
Yi='Yisoonshin:BAABLgAECn8UAAIfAAYJPyUmEgCDAgAfAAYJPyUmEgCDAgABLgAFFAIJAgAHAAAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJIQAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yuichi:BAAALgAECgEJAQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAABLgAECn8aAAMFAAgJwQgVNAAmAQAFAAgJwQgVNAAmAQADAAEJAwLScQAeAAAAAA==.',
Za='Zagera:BAAALgADCgcJCQAAAA==.Zaka:BAAALgAECgQJBAABLgAFFAUJFAAKAPYfAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECgkJEAAAAA==.Zango:BAAALgADCgMJAwAAAA==.Zanosuke:BAABLgAECn8WAAIjAAkJ5B+vCwBSAgAjAAkJ5B+vCwBSAgAAAA==.Zanzer:BAAALgADCgQJBAABLgAECgYJBgAHAAAAAA==.Zarathis:BAAALgADCgEJAQAAAA==.Zaria:BAABLgAECn8dAAIdAAcJmhNzeABsAQAdAAcJmhNzeABsAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zelkora:BAAALgADCgYJBgAAAA==.Zerica:BAAALgAECgMJBAAAAA==.Zerika:BAACLgAFFH8FAAIDAAMJTAzBHQCnAAADAAMJTAzBHQCnAAAuAAQKfyEAAgMACQn5H8UGAPQCAAMACQn5H8UGAPQCAAAA.',
Zi='Zigzwag:BAAALgAECgYJDgAAAA==.Zionna:BAAALgADCgYJAQABLgAECgkJEgAHAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8XAAIGAAgJHBUrDgDaAQAGAAgJHBUrDgDaAQAAAA==.Zoose:BAAALgAECgEJAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8ZAAIgAAcJAhvELAABAgAgAAcJAhvELAABAgABLgAECgcJLAAjALAPAA==.',
Zy='Zydis:BAABLgAECn8XAAMOAAcJRQicZgDvAAAOAAcJRQicZgDvAAAlAAUJIgq3IwDFAAAAAA==.',
['Ád']='Ádolín:BAAALgAECgMJAwAAAA==.',
['Än']='Ännihilation:BAAALgADCgkJHQAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQAHAAAAAA==.',
['És']='Éstéla:BAACLgAFFH8HAAIBAAMJhA40TwDiAAABAAMJhA40TwDiAAAuAAQKfzAAAgEACQmsF+YuAAoCAAEACQmsF+YuAAoCAAAA.',
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
