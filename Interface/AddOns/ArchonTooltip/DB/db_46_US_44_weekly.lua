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

local lookup = {'Hunter-BeastMastery','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Retribution','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Unholy','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Warlock-Demonology','Mage-Frost','Mage-Fire','Mage-Arcane','Shaman-Elemental','DemonHunter-Havoc','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','DemonHunter-Devourer','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','Paladin-Holy','Monk-Windwalker','Warlock-Affliction','Monk-Brewmaster','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Hunter-Survival','Paladin-Protection',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAABLgAECn8eAAIBAAgJIAmPdABSAQABAAgJIAmPdABSAQAAAA==.Abrakadaver:BAAALgAECgYJCQABLgAECgkJIAACAIIcAA==.',
Ac='Activision:BAABLgAECn8WAAIDAAYJKxriIQCvAQADAAYJKxriIQCvAQAAAA==.',
Ad='Ademisk:BAAALgADCgYJEgAAAA==.Adventureux:BAACLgAFFH8QAAIBAAQJFhuQKABdAQABAAQJFhuQKABdAQAuAAQKfyIAAgEACQmHG/cyAAwCAAEACQmHG/cyAAwCAAAA.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8dAAIEAAgJehUCRACZAQAEAAgJehUCRACZAQAAAA==.',
Ai='Aiblul:BAABLgAFFH8JAAIFAAIJpRoqKgCjAAAFAAIJpRoqKgCjAAAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAABLgAFFH8HAAMGAAQJ9B5EEAB+AQAGAAQJ9B5EEAB+AQAHAAEJLRlmOwBTAAABLgAFFAMJCgAIAPkiAA==.Albinee:BAAALgADCgYJBgABLgAECgcJGQAJAJ0dAA==.Aliroarx:BAAALgADCggJFAAAAA==.Almosteasy:BAABLgAECn8XAAIKAAgJLyPFBwAhAwAKAAgJLyPFBwAhAwAAAA==.Alunadoom:BAAALgAECggJEgAAAA==.Alunagryn:BAACLgAFFH8IAAILAAQJXAbBLgDTAAALAAQJXAbBLgDTAAAuAAQKfyQABAsACAllGZwTABICAAsACAnHFZwTABICAAUABwk3F1wfAN0BAAMABQnpGG81AGgBAAAA.Alvera:BAABLgAECn8wAAIMAAkJwB/iIgB5AgAMAAkJwB/iIgB5AgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgABLgAECgYJBgANAAAAAA==.',
An='Anaflora:BAAALgADCgEJAQAAAA==.Anchorpaddle:BAAALgAECgYJBgAAAA==.Anduin:BAAALgAECgYJCQAAAA==.Angechi:BAEALgAECgYJBgABLgAECgUJFAAOAOgKAA==.Angerforge:BAAALgAECgcJBwAAAA==.Angrydk:BAABLgAECn8fAAMMAAkJYgomZQCaAQAMAAkJYgomZQCaAQAPAAcJswdQGwDxAAAAAA==.',
Ar='Arielordril:BAAALgAECgYJDQAAAA==.Arm:BAACLgAFFH8OAAIQAAQJ7QbJKwDWAAAQAAQJ7QbJKwDWAAAuAAQKfz8AAxAACQkbHigJAL8CABAACQkbHigJAL8CABEABwnBFjw1ANMBAAAA.Armee:BAABLgAECn8dAAIDAAkJWRrlDwBnAgADAAkJWRrlDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artiavis:BAABLgAFFH8FAAISAAUJ4hjrOwBVAQASAAUJ4hjrOwBVAQAAAA==.Artèmís:BAAALgAECgYJCgAAAA==.Arzosah:BAAALgAECgQJBAAAAA==.',
As='Asmilwelme:BAAALgAECgQJCAAAAA==.Astrael:BAACLgAFFH8NAAMTAAQJNA10YwAlAQATAAQJNA10YwAlAQAUAAEJnAYdBwA7AAAuAAQKfyAAAxMACQmYElpYANEBABMACQnzEVpYANEBABUABQnaEKYOANkAAAAA.Aszayla:BAABLgAECn8pAAITAAkJdBErTwDrAQATAAkJdBErTwDrAQAAAA==.Aszea:BAAALgAECgYJCgAAAA==.',
Av='Avoidme:BAAALgAECgUJDAAAAA==.',
Az='Azairius:BAAALgAECgUJBQAAAA==.Azendeth:BAAALgADCgUJBQABLgADCgYJBwANAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8vAAIWAAgJ6xF8KgDCAQAWAAgJ6xF8KgDCAQABLgAECgkJJAAXAJwLAA==.Azóg:BAABLgAECn86AAIMAAgJnxryTADZAQAMAAgJnxryTADZAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAFFAIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8hAAMYAAkJyB9vAAAxAgAYAAcJCB1vAAAxAgAZAAcJLCLiAwDbAQAuAAQKfygAAxkACQk9JvsBAJkDABkACQk9JvsBAJkDABgACAmMJCUEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Barghast:BAAALgAECgEJAQAAAA==.Barlaf:BAABLgAFFH8JAAIBAAQJdQwFTgAHAQABAAQJdQwFTgAHAQABLgAECgMJBAANAAAAAA==.Barriss:BAAALgADCgEJAQAAAA==.',
Be='Beanvin:BAAALgAECgIJBQAAAA==.Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgcJDgABLgAFFAIJAgANAAAAAA==.Beastoker:BAAALgAECggJEwAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAgJHgATAIgiAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAABLgAECn8UAAIaAAYJxBTqDQBEAQAaAAYJxBTqDQBEAQAAAA==.Beeto:BAACLgAFFH8bAAIJAAUJCB+EKABiAQAJAAUJCB+EKABiAQAuAAQKfxwAAgkACQkhHjokAJcCAAkACQkhHjokAJcCAAAA.Bekdrop:BAABLgAECn8SAAIbAAYJbCENTwCVAQAbAAYJbCENTwCVAQABLgAFFAgJHgATAIgiAA==.Benlian:BAEBLgAECn8UAAMOAAUJ6AqJPgCSAAAOAAUJ6AqJPgCSAAAMAAUJYARzHwF+AAAAAA==.',
Bi='Bigboat:BAAALgAECgQJBAAAAA==.Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8aAAITAAYJ7hJCPQB7AQATAAYJ7hJCPQB7AQAuAAQKfyMAAxMACAkgIbkgAPECABMACAkgIbkgAPECABUAAQmmFUseADUAAAEuAAUUBwkTABYAERUA.Bigspook:BAAALgAECgQJBAAAAA==.Bisect:BAAALgADCgQJBwAAAA==.Bishtease:BAAALgADCgQJBAAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8fAAITAAcJnBcGGQApAgATAAcJnBcGGQApAgAuAAQKfyoAAhMACQl4HjQbAAoDABMACQl4HjQbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAACLgAFFH8cAAIRAAgJQhzlBQCiAgARAAgJQhzlBQCiAgAuAAQKfxgAAxEABwktJakXAIYCABEABwktJakXAIYCABAAAgn1I7dNANEAAAEuAAUUBgkXABwAIhoA.Boof:BAABLgAECn8cAAIFAAkJpxlsGwACAgAFAAkJpxlsGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Boonpandit:BAAALgADCgcJBwAAAA==.Bootyful:BAAALgAECgEJAQAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgAECgUJCQAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAABLgAECn8YAAIKAAkJcxfDBgAfAgAKAAkJcxfDBgAfAgAAAA==.Bruski:BAAALgAECgUJDAAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAFFAQJBwAZAA0WAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8YAAIJAAgJViKVQwAZAgAJAAgJViKVQwAZAgAAAA==.Bushgarden:BAAALgAECgUJBwABLgAECgkJIQAdAH8VAA==.Buzzbuzz:BAABLgAECn8VAAMLAAkJtxcAFwDoAQALAAgJxhkAFwDoAQAFAAgJkBA7MwBLAQAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAIcAAYJIhodAgAKAgAcAAYJIhodAgAKAgAuAAQKfx8AAxwACQllHzMEABMDABwACQllHzMEABMDABgAAwn5Iu0iABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAIeAAMJaCAILgD0AAAeAAMJaCAILgD0AAABLgAFFAYJFwAcACIaAA==.',
['Bö']='Böba:BAAALgAECgYJBgABLgAFFAYJFwAcACIaAA==.',
Ca='Cadroyd:BAAALgAECgEJAQAAAA==.Caelin:BAABLgAECn8pAAIbAAkJQhEjSACrAQAbAAkJQhEjSACrAQAAAA==.Caishana:BAABLgAECn8yAAMEAAkJaiKnCAAkAwAEAAkJaiKnCAAkAwAWAAEJGgbAtwAiAAAAAA==.Calonderiel:BAAALgAECgEJAQABLgAECgQJBAANAAAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAABLgAECn8UAAMDAAgJ+hWsIgCpAQADAAgJjBWsIgCpAQALAAYJjg1TOgAlAQAAAA==.',
Ce='Cecil:BAACLgAFFH8HAAIfAAMJ9ALDOACAAAAfAAMJ9ALDOACAAAAuAAQKfzAAAx8ACQltCpUxAI4BAB8ACQltCpUxAI4BAAkAAwluBFM5AW4AAAAA.Celeb:BAABLgAECn8oAAICAAgJ8CMJAQAyAwACAAgJ8CMJAQAyAwAAAA==.Celebrity:BAAALgAECgUJCgABLgAECggJKAACAPAjAA==.Celebtard:BAAALgAECgIJAgABLgAECggJKAACAPAjAA==.Cervitude:BAAALgAECgQJCAAAAA==.Cervrakabra:BAAALgAECgMJBgAAAA==.',
Ch='Chaddingus:BAAALgAECgkJEAAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgUJCQAAAA==.Chilltea:BAACLgAFFH8PAAITAAQJtxm4SwBPAQATAAQJtxm4SwBPAQAuAAQKfzMAAhMACQlgI0kIADgDABMACQlgI0kIADgDAAAA.Chocc:BAAALgAECgUJBQABLgAECgkJJgAOAOYUAA==.Chopadk:BAAALgAECgcJBwABLgAFFAYJFAAgANUYAA==.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8jAAQhAAcJfQoCGgDqAAAhAAYJdwoCGgDqAAASAAYJ3wiEwgDHAAAdAAEJSgzrQAApAAAAAA==.',
Ci='Cigarette:BAAALgAECgEJAQAAAA==.',
Cl='Clique:BAABLgAECn9DAAIfAAkJ5iARBgArAwAfAAkJ5iARBgArAwAAAA==.',
Co='Coheedkil:BAAALgAECgUJCAABLgAECgYJBgANAAAAAA==.Coldbreeze:BAAALgAECgMJAwAAAA==.Collateral:BAAALgAFFAEJAgAAAA==.Compaktdisc:BAAALgAECgkJEgAAAA==.Conartist:BAAALgAFFAIJAgABLgAFFAQJDAAgAKYkAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwANAAAAAA==.Cowpox:BAABLgAECn8eAAIRAAkJWQ48PACgAQARAAkJWQ48PACgAQAAAA==.',
Cp='Cpr:BAAALgAECgQJEAAAAA==.',
Cr='Creatrix:BAAALgAECgYJCAABLgAFFAQJDAAgAKYkAA==.Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAABLgAECn8UAAITAAYJ8AQ57ADFAAATAAYJ8AQ57ADFAAAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn9LAAIfAAkJMSMvBABVAwAfAAkJMSMvBABVAwAAAA==.Cruv:BAAALgAECgMJAwAAAA==.Cry:BAAALgAECgQJDAAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8TAAIiAAUJEiBeFQBwAQAiAAUJEiBeFQBwAQAuAAQKfycAAyIACQkOITALANkCACIACQkOITALANkCACAAAQnfFhGLAEQAAAAA.',
Cy='Cybuster:BAAALgAECgcJDwABLgAFFAQJCgATALUVAA==.Cyndle:BAAALgAECgYJBgABLgAECgkJGwADAMsXAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8cAAITAAkJTxB/ewDaAQATAAkJTxB/ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8bAAICAAkJDBXVCQDOAQACAAkJDBXVCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECgkJEQAAAA==.Dakian:BAAALgADCgEJAQAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAABLgAECn83AAIJAAkJ8g2jXwCvAQAJAAkJ8g2jXwCvAQABLgAECgUJGAAXANsKAA==.Dargong:BAAALgAECggJAgAAAA==.Darkrunes:BAABLgAECn8dAAIbAAcJLho0PgD7AQAbAAcJLho0PgD7AQAAAA==.Darnwrath:BAAALgADCgUJBQAAAA==.Darrkness:BAABLgAFFH8JAAISAAMJtBr/ZQD0AAASAAMJtBr/ZQD0AAAAAA==.Darthvikingw:BAAALgADCgcJDAAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJDgAAAA==.Deaththrone:BAAALgADCgEJAQABLgAECgcJEAANAAAAAA==.Deides:BAAALgADCgYJBwAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgUJCQABLgAECgkJJgAOAOYUAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAABLgAECn8cAAIJAAgJpx8kLQBKAgAJAAgJpx8kLQBKAgAAAA==.Deristus:BAABLgAECn8pAAISAAkJDBY8OgDwAQASAAkJDBY8OgDwAQAAAA==.Deroth:BAAALgAECgEJBAAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAANAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Devi:BAAALgAECgIJAwABLgAECgcJCwANAAAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dingeoffor:BAAALgAFFAMJBAABLgAFFAUJBQASAOIYAA==.Dirtmonkgirt:BAABLgAECn8gAAIgAAkJ3BYwFgADAgAgAAkJ3BYwFgADAgAAAA==.Dirtnasty:BAAALgAFFAIJAgAAAA==.Dirtysham:BAABLgAECn8cAAIWAAgJcBjJIQABAgAWAAgJcBjJIQABAgAAAA==.Discipline:BAABLgAECn8lAAIFAAkJ/BfzFAAlAgAFAAkJ/BfzFAAlAgAAAA==.Dishwasher:BAAALgADCgkJEAAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8cAAMMAAYJVRNfkQBdAQAMAAYJqBJfkQBdAQAOAAYJnAywMgDOAAAAAA==.Dotdotgoose:BAAALgAECggJDAABLgAECgkJEgANAAAAAA==.Dotgunner:BAABLgAECn8XAAISAAcJXRtBQAANAgASAAcJXRtBQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgkJIAAbAJYdAA==.Downbad:BAACLgAFFH8FAAISAAMJdQcoJwDhAAASAAMJdQcoJwDhAAAuAAQKfx8AAxIACAl+H1wXAMgCABIACAl+H1wXAMgCAB0ABAm8Cwg1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJHQAXAHgQAA==.Drahseer:BAAALgAECgYJEQAAAA==.Drakqueenjd:BAAALgADCgYJBgAAAA==.Drakulya:BAABLgAECn8YAAIJAAYJhwti2gDiAAAJAAYJhwti2gDiAAAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAACLgAFFH8GAAIbAAMJ1gaDcACgAAAbAAMJ1gaDcACgAAAuAAQKfyUABBsACAkGEUNSAIsBABsACAkGEUNSAIsBABcAAwkyCGtaAHkAAAIAAgkwDT43ACcAAAAA.Drewish:BAAALgADCgQJBAAAAA==.Driftèr:BAAALgAECgcJEgAAAA==.Drizzle:BAACLgAFFH8PAAIbAAQJuyTBIACnAQAbAAQJuyTBIACnAQAuAAQKfysAAhsACQmhJaUDAEoDABsACQmhJaUDAEoDAAAA.Drkdestro:BAABLgAECn8wAAQSAAkJByK8DwD8AgASAAkJBSG8DwD8AgAhAAYJoh0GDgB2AQAdAAEJyxzIXwBPAAAAAA==.Drktotem:BAAALgAFFAMJAwAAAA==.Druidic:BAACLgAFFH8VAAIRAAUJDSQ3DwD8AQARAAUJDSQ3DwD8AQAuAAQKfzgAAhEACQlsJbkDAFYDABEACQlsJbkDAFYDAAEuAAUUBgkNAB4AbCIA.Drunkhorn:BAAALgADCgMJAwAAAA==.Druvinci:BAAALgAECgYJBgAAAA==.Drü:BAABLgAECn8UAAIQAAkJDxLhLQCVAQAQAAkJDxLhLQCVAQAAAA==.',
Du='Dumbledwarf:BAAALgAECgQJBAAAAA==.Duneshade:BAAALgADCgUJBQAAAA==.Dunk:BAAALgAECgEJAQAAAA==.Dusan:BAABLgAECn8pAAMDAAkJBB1sDACcAgADAAkJBB1sDACcAgALAAYJmgvuQAAFAQAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ea:BAAALgADCgYJCgAAAA==.Ear:BAAALgADCgcJBwABLgAFFAMJCAAIABISAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8lAAMEAAgJrBW/PAC3AQAEAAgJrBW/PAC3AQAIAAQJ/wK6IgCqAAAAAA==.',
Ed='Edonsian:BAACLgAFFH8MAAIGAAQJ6RZDHQA4AQAGAAQJ6RZDHQA4AQAuAAQKfzoAAwYACQktGw4eAPwBAAYACQmjGg4eAPwBACMABQm2GhQiABsBAAAA.',
Ee='Eepy:BAABLgAECn8aAAMeAAkJoBHtHQDGAQAeAAkJoBHtHQDGAQAgAAUJuxHeSgDTAAAAAA==.',
Eg='Egmont:BAAALgAECgYJDAAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgAFFAIJAgABLgAECgcJGgAYAPscAA==.Elliekins:BAAALgADCgkJDwAAAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAABLgAECn8VAAIjAAgJlBQHGgBnAQAjAAgJlBQHGgBnAQAAAA==.Emorlyn:BAABLgAECn8XAAMBAAkJwg+sNADcAQABAAkJwg+sNADcAQAKAAYJpgIgZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Encanis:BAAALgAECgcJCwAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAACLgAFFH8PAAITAAUJZBRfXwAsAQATAAUJZBRfXwAsAQAuAAQKfx4AAhMACAlDHBFNAE8CABMACAlDHBFNAE8CAAAA.',
Er='Eriksangus:BAABLgAECn8XAAIGAAgJ/weoTwAJAQAGAAgJ/weoTwAJAQAAAA==.',
Es='Eskarina:BAAALgADCgcJBwAAAA==.Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAABLgAECn8+AAIRAAkJfhfpGAB8AgARAAkJfhfpGAB8AgAAAA==.',
Ev='Evaporate:BAAALgAECgYJBwAAAA==.Evilguard:BAABLgAECn8mAAMOAAkJ5hQKGAChAQAOAAgJmRcKGAChAQAPAAEJ/gGARAAKAAAAAA==.Evilpatty:BAAALgAECgMJAwAAAA==.',
Ex='Excessive:BAAALgAECgEJAQAAAA==.Excorsism:BAABLgAFFH8GAAIjAAMJ6w+CHgCbAAAjAAMJ6w+CHgCbAAABLgAFFAQJEAAZAGodAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECggJEwAAAA==.',
Fa='Falador:BAAALgAFFAEJAQAAAA==.Fariebubbles:BAABLgAECn8nAAIRAAkJKQ/HNgC7AQARAAkJKQ/HNgC7AQAAAA==.Fastandis:BAAALgAECgYJBgAAAA==.Fataldk:BAABLgAFFH8FAAIMAAMJ8wnergDAAAAMAAMJ8wnergDAAAABLgAFFAMJBwAbAGcQAA==.Fatale:BAACLgAFFH8HAAIbAAMJZxATZAC/AAAbAAMJZxATZAC/AAAuAAQKfxgAAhsABgllIl80APEBABsABgllIl80APEBAAAA.Fatallock:BAAALgAECgUJBQABLgAFFAMJBwAbAGcQAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMSAAcJgRm/aQCQAQASAAYJghq/aQCQAQAdAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAABLgAFFH8QAAMWAAQJMh+tFQBmAQAWAAQJMh+tFQBmAQAEAAIJLQoWaABoAAAAAA==.Fenixstraza:BAACLgAFFH8YAAQZAAUJNxbRPQDMAAAZAAMJ1hnRPQDMAAAcAAMJThcxIQCUAAAYAAIJVwvODQBGAAAuAAQKf0AABBwACQkNHlkGAJ8CABwACQkNHlkGAJ8CABkACQmFGi4RAFoCABgAAQkAADkuAAAAAAAA.Fenwell:BAAALgAECgQJBAAAAA==.Fervis:BAAALgAECgQJCAABLgAECggJFgAZABcKAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJEwABLgAECggJGwAWAB4dAA==.Firitako:BAABLgAECn8XAAMWAAcJshTgVgDqAAAWAAcJshTgVgDqAAAEAAUJSwsMigDBAAAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECgkJQwAGAJclAA==.Flipper:BAABLgAECn8ZAAMfAAkJKxSrIgAJAgAfAAkJKxSrIgAJAgAJAAIJawFyRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8cAAQhAAkJgCCRAwBfAgAhAAkJgCCRAwBfAgASAAMJmxHsLAE6AAAdAAEJtwRDRgAbAAAAAA==.Frankiejr:BAABLgAECn8UAAIEAAcJliYCCgARAwAEAAcJliYCCgARAwABLgAECgkJNAAJAJolAA==.Frapsity:BAABLgAECn8vAAMEAAgJbBYaKwAKAgAEAAgJbBYaKwAKAgAWAAcJvRDhOwBCAQAAAA==.Frapss:BAAALgADCggJCAABLgAECggJLwAEAGwWAA==.Frostamper:BAAALgAECgYJDwAAAA==.Frostnite:BAABLgAECn8vAAMPAAgJIA1MEQBeAQAPAAgJIA1MEQBeAQAOAAEJhwKQZAAeAAAAAA==.Frostpoptart:BAABLgAECn8vAAIEAAkJ0xgAIgATAgAEAAkJ0xgAIgATAgAAAA==.Frozenblade:BAAALgAECgYJBgAAAA==.',
Fu='Funereal:BAAALgADCgEJAQAAAA==.Fupah:BAAALgAECgIJAgAAAA==.Furball:BAAALgAFFAIJAwABLgAFFAYJEgASAOURAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAACLgAFFH8VAAIiAAUJ9CIqEgCKAQAiAAUJ9CIqEgCKAQAuAAQKfyQAAyIACQktIJ0FAOMCACIACQktIJ0FAOMCACAAAQksBBe4AB4AAAAA.Galadrielle:BAABLgAECn8UAAITAAgJowE+/ACuAAATAAgJowE+/ACuAAAAAA==.Gandelf:BAAALgAECgYJDAABLgAECggJLAABAEIfAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Garret:BAAALgADCgQJBAABLgAECgkJKQAbAEIRAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8pAAIkAAkJkAuFKAAPAQAkAAkJkAuFKAAPAQAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAACLgAFFH8PAAIbAAQJQhfIPgAlAQAbAAQJQhfIPgAlAQAuAAQKfzYAAhsACQm+IV4JAAADABsACQm+IV4JAAADAAAA.',
Gh='Ghostfate:BAAALgAECgEJAwAAAA==.',
Gi='Gigadoot:BAAALgAECgMJBQAAAA==.Gigbutt:BAABLgAECn88AAMlAAkJ9Rt/DwAwAgAlAAkJ9Rt/DwAwAgAmAAUJaxDFDgAeAQAAAA==.Giggles:BAAALgAECgUJBQAAAA==.Giggléz:BAAALgAECgcJCgAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAITAAgJIBs8RABrAgATAAgJIBs8RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgAECgEJAgAAAA==.Goatedfury:BAACLgAFFH8IAAIJAAQJEwLRdADEAAAJAAQJEwLRdADEAAAuAAQKfxQAAgkACAnVFWx2AH8BAAkACAnVFWx2AH8BAAAA.Goblegoble:BAAALgAECgYJDgAAAA==.Googrektar:BAAALgAECgUJBgABLgAFFAUJEgATABAaAA==.Goonietai:BAAALgAECgUJBQABLgAFFAUJEgATABAaAA==.Gooseshot:BAAALgAECgMJAwAAAA==.Gorgrot:BAAALgAECgcJCgABLgAFFAQJFQAQAEEcAA==.Gorshot:BAABLgAECn8YAAIBAAkJwgxFUACtAQABAAkJwgxFUACtAQAAAA==.Govacho:BAAALgADCgMJAwAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Greatvibes:BAAALgAECgUJCQABLgAFFAIJAgANAAAAAA==.Greens:BAAALgAECgUJBAAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgAFFAIJAwABLgAFFAQJDQASAE4WAA==.Griitz:BAABLgAECn8VAAIMAAgJ4RoUMQA4AgAMAAgJ4RoUMQA4AgAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAACLgAFFH8PAAInAAQJlCScAgCoAQAnAAQJlCScAgCoAQAuAAQKfy0AAycACQmDJfAAAFYDACcACQmDJfAAAFYDACQABgmRDwMXAAUBAAAA.Griswold:BAABLgAECn8aAAIdAAYJVhrPDABuAQAdAAYJVhrPDABuAQAAAA==.Gryff:BAAALgADCgEJAQAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8gAAMTAAgJqRvkQAB2AgATAAgJqRvkQAB2AgAVAAEJ0ibSFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJIAATAKkbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8NAAMOAAQJkx3gKQCkAAAMAAMJSSPxdwARAQAOAAMJLg/gKQCkAAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJCAAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8lAAIFAAkJKg3YJACiAQAFAAkJKg3YJACiAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.Hawtdonna:BAAALgAECgcJCgAAAA==.',
He='Healcraze:BAAALgAECgEJAgAAAA==.Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8uAAQSAAkJYCLmDQDcAgASAAkJYCLmDQDcAgAdAAMJeh4PMQD1AAAhAAEJzAR7QwAkAAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAwAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAABLgAECn8XAAIJAAkJvRccPQAwAgAJAAkJvRccPQAwAgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECgkJFQALALcXAA==.Hontaa:BAAALgADCgMJAwAAAA==.Hoofrat:BAAALgAECgcJBQAAAA==.Hornivore:BAAALgAECgUJBQAAAA==.',
Hp='Hpal:BAAALgAECgUJBQAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgcJDAANAAAAAA==.Huxley:BAAALgAECgIJAgAAAA==.Huñted:BAABLgAECn8bAAMoAAgJAxNUIQCSAQAoAAgJnQ9UIQCSAQABAAYJIw7UYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgAECgQJDgAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgcJDAANAAAAAA==.',
Ic='Icefrosting:BAAALgAECgkJEAABLgAECgkJMAAFAPIkAA==.Icuris:BAAALgAECgMJBQAAAA==.',
Id='Idistroya:BAABLgAECn8dAAIOAAcJhBFuJQAlAQAOAAcJhBFuJQAlAQABLgAECgkJWAABAKYjAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ig='Iggnogg:BAAALgADCggJCQAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMhAAgJYBWQCADBAQAhAAYJ1BiQCADBAQASAAgJCREUZgBxAQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8XAAIDAAgJkhVVGwACAgADAAgJkhVVGwACAgAAAA==.Ilithiya:BAACLgAFFH8JAAIbAAQJtx8kKgB1AQAbAAQJtx8kKgB1AQAuAAQKfxQAAhsACAlAImQWAI4CABsACAlAImQWAI4CAAAA.Ilk:BAAALgAECgkJEQAAAA==.Illidrac:BAABLgAECn8dAAIXAAkJeBC4HgCAAQAXAAkJeBC4HgCAAQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJGgAYAPscAA==.Illudari:BAAALgAECgMJAwABLgAECgcJGgAYAPscAA==.Illududu:BAAALgAECgYJDwABLgAECgcJGgAYAPscAA==.',
Im='Imangry:BAABLgAECn8tAAIpAAkJvhLGDwDDAQApAAkJvhLGDwDDAQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inconsolable:BAAALgADCgMJAwAAAA==.Inpherno:BAAALgAFFAEJAQAAAA==.',
Is='Isaidnoice:BAABLgAECn8hAAMdAAkJfxWgFgCVAQAdAAcJ+RagFgCVAQASAAgJpg9jYgB6AQAAAA==.Ishton:BAABLgAFFH8JAAIJAAMJegdYegC6AAAJAAMJegdYegC6AAAAAA==.Istompgnomes:BAACLgAFFH8HAAIWAAMJkAvINwCpAAAWAAMJkAvINwCpAAAuAAQKfxcAAhYACAkMGNceAOgBABYACAkMGNceAOgBAAAA.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgcJEwAAAA==.',
Ja='Jacked:BAABLgAECn8fAAMSAAkJLR4zQgDUAQASAAcJxxszQgDUAQAhAAQJ/hzBEAAhAQAAAA==.Jasøn:BAAALgAECggJEAABLgAECggJEQANAAAAAA==.',
Je='Jecah:BAAALgAECgcJCAABLgAECgkJKgAFAM4VAA==.Jecka:BAABLgAECn8qAAMFAAkJzhVpMwBKAQAFAAcJ/BFpMwBKAQADAAgJmw26QgAuAQAAAA==.Jeckah:BAAALgAECggJEwABLgAECgkJKgAFAM4VAA==.Jecthyr:BAAALgAECgEJAQABLgAECgkJKgAFAM4VAA==.Jefryepsteen:BAAALgAECgcJDAAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAABLgAECn8kAAIDAAcJ4Bn9IAC2AQADAAcJ4Bn9IAC2AQAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8aAAMpAAYJBB6sGABTAQApAAYJBB6sGABTAQAJAAEJrwL0WQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jm='Jmoney:BAAALgAECgEJAQAAAA==.',
Jo='Jordana:BAABLgAECn8bAAIRAAkJ0hUdOQCvAQARAAkJ0hUdOQCvAQAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJBAAAAA==.',
Js='Jsdruid:BAABLgAECn8ZAAIRAAgJexcbJQAhAgARAAgJexcbJQAhAgAAAA==.',
Ju='Jug:BAABLgAECn8cAAIoAAgJqBuXBADPAgAoAAgJqBuXBADPAgAAAA==.Julaudette:BAAALgAECgUJDQAAAA==.',
Ka='Kainöa:BAAALgAECgYJEwABLgAFFAIJAgANAAAAAA==.Kakum:BAAALgAECggJEgAAAA==.Kaldrogo:BAAALgAECgQJCwAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAgJMAAeANUXAA==.Kalnuggets:BAAALgAECgYJCwAAAA==.Kalrathen:BAABLgAECn8kAAIDAAgJ4RePFgAYAgADAAgJ4RePFgAYAgAAAA==.Kamiyakaoru:BAAALgAECgQJBQAAAA==.Kaniku:BAAALgAECgYJCgABLgAFFAUJEgATABAaAA==.Karmafel:BAABLgAECn8UAAMbAAUJZgqlxQCeAAAbAAUJZgqlxQCeAAACAAEJAAASQgAAAAABLgAECggJNQAeALcdAA==.Karsh:BAACLgAFFH8HAAIGAAMJ7wFfQgCRAAAGAAMJ7wFfQgCRAAAuAAQKfyAAAgYACQkHB+E+AEgBAAYACQkHB+E+AEgBAAAA.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAABLgAECn8hAAMSAAkJwxeKKQAzAgASAAkJwxeKKQAzAgAdAAYJoQw3JAA4AQAAAA==.Kazurena:BAAALgADCgcJCQAAAA==.',
Kd='Kdb:BAABLgAFFH8NAAIeAAYJbCISCgBXAgAeAAYJbCISCgBXAgAAAA==.',
Ke='Keen:BAAALgAECgEJAQAAAA==.Kered:BAABLgAECn8UAAISAAcJZR8NLAAnAgASAAcJZR8NLAAnAgABLgAFFAQJDwARAAUaAA==.Keuaakepo:BAABLgAECn9YAAMBAAkJpiMZBwAjAwABAAkJpiMZBwAjAwAoAAEJUQM9MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8pAAIBAAgJtRtfQQDaAQABAAgJtRtfQQDaAQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECggJCwABLgAECgkJEgANAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgUJDAAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAABLgAECn8VAAILAAYJfQllQwD5AAALAAYJfQllQwD5AAAAAA==.',
Ko='Korbanhavoc:BAAALgAFFAIJAwAAAA==.Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8qAAMnAAkJMhegCAA9AgAnAAkJMhegCAA9AgAkAAIJ0AwgKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJDwAAAA==.',
Kr='Krethar:BAAALgAECgIJAgABLgAFFAIJAwANAAAAAA==.Kroatoan:BAAALgAECgEJAQABLgAFFAUJDQAJAAISAA==.Krypt:BAABLgAECn8pAAIjAAkJWxcPEQDWAQAjAAkJWxcPEQDWAQAAAA==.Krìzl:BAACLgAFFH8MAAITAAMJcyPVZwAcAQATAAMJcyPVZwAcAQAuAAQKfzEAAhMACAnDI5QnAHoCABMACAnDI5QnAHoCAAEuAAUUBwkkAAwAXiMA.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgQJBAAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAACLgAFFH8NAAQSAAQJThZYTgAlAQASAAQJlBJYTgAlAQAhAAEJHBhBHABUAAAdAAEJWhVOJQBJAAAuAAQKf0MABB0ACQk/JFsDAL0CAB0ACAmIIVsDAL0CABIABwn5IXwVAKICACEAAgm7HPQlAIsAAAAA.Lanzen:BAAALgAECgEJAQABLgAECgYJBgANAAAAAA==.Lanzier:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Larrfena:BAABLgAECn8xAAIBAAkJoh4OEQDFAgABAAkJoh4OEQDFAgAAAA==.',
Le='Legit:BAAALgAECgcJDAABLgAECggJHQAbAC4aAA==.Legsday:BAAALgAECgQJBQAAAA==.Lementz:BAACLgAFFH8UAAIIAAUJDiCtAADIAQAIAAUJDiCtAADIAQAuAAQKf0EAAggACQniJkAAAIMDAAgACQniJkAAAIMDAAAA.Lexiiees:BAABLgAECn8bAAIlAAcJ7QQ/OQDmAAAlAAcJ7QQ/OQDmAAAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAABLgAECn8bAAMWAAgJHh3dEgBVAgAWAAgJHh3dEgBVAgAIAAYJEQ9WHwD4AAAAAA==.Lillia:BAABLgAECn8pAAISAAkJShH/TACzAQASAAkJShH/TACzAQAAAA==.',
Lo='Lockyshocky:BAAALgADCgcJDAAAAA==.Lovetobussy:BAABLgAECn8lAAMDAAYJLiDFFwAMAgADAAYJLiDFFwAMAgAFAAIJ7w3/bQBjAAAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn9TAAQSAAkJ8SMfBwAgAwASAAkJJyMfBwAgAwAhAAgJuh41AwCFAgAdAAUJhR1/GwBxAQAAAA==.Lumpia:BAACLgAFFH8PAAIMAAQJexTSXgA0AQAMAAQJexTSXgA0AQAuAAQKfyUAAgwACQmWIE0ZAKwCAAwACQmWIE0ZAKwCAAAA.',
['Lè']='Lèah:BAAALgAECgUJCgAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAIJAgABLgAFFAUJEAATALgfAA==.Madgeyoulook:BAAALgAECgUJBQAAAA==.Magenta:BAAALgAECgUJBQAAAA==.Magicchoc:BAAALgAECgYJDAABLgAECgkJJgAOAOYUAA==.Maktah:BAACLgAFFH8JAAIIAAQJMwlgDAD2AAAIAAQJMwlgDAD2AAAuAAQKfxYAAwgACAkfGjkNANgBAAgACAkfGjkNANgBABYAAQl0EOGFADUAAAAA.Mandrakor:BAAALgADCgEJAQAAAA==.Manwitchtap:BAAALgAECgEJAQAAAA==.Marinara:BAAALgAECgcJBwABLgAFFAUJEAATALgfAA==.Marshboa:BAAALgAFFAIJAgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mcgurk:BAABLgAECn8XAAMEAAkJHBHzLwDxAQAEAAkJHBHzLwDxAQAWAAgJuBLYJwCrAQAAAA==.Mclovinit:BAACLgAFFH8eAAITAAgJiCKdAgBeAgATAAgJiCKdAgBeAgAuAAQKf1MAAhMACQmqJnoAAAIEABMACQmqJnoAAAIEAAAA.Mcmagic:BAACLgAFFH8HAAITAAQJPxrQcQABAQATAAQJPxrQcQABAQAuAAQKfy4AAhMACAlPI/kdAKYCABMACAlPI/kdAKYCAAEuAAUUCAkeABMAiCIA.Mcpally:BAABLgAECn85AAIJAAkJUCI4EADiAgAJAAkJUCI4EADiAgAAAA==.',
Me='Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8dAAIRAAkJeCO3CAADAwARAAkJeCO3CAADAwAAAA==.Mensu:BAAALgAECgYJCwAAAA==.Mentos:BAABLgAECn8tAAMYAAkJHRrOAwBJAgAYAAkJHRrOAwBJAgAcAAYJJx4fDgDpAQAAAA==.Mercilezz:BAAALgAECgIJAgAAAA==.',
Mi='Midwestfel:BAABLgAECn8cAAIbAAgJzwYqrADJAAAbAAgJzwYqrADJAAAAAA==.Mikeoxhard:BAAALgAECggJEQAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAACLgAFFH8IAAIFAAMJcwpbJgDBAAAFAAMJcwpbJgDBAAAuAAQKfx0AAgUACQk3E74iALEBAAUACQk3E74iALEBAAAA.Minihulk:BAABLgAECn8iAAQPAAcJ4QnRGAAKAQAPAAcJ4QnRGAAKAQAMAAMJgwNFNAFlAAAOAAMJowE2VQBCAAAAAA==.Mionn:BAABLgAECn8ZAAMJAAcJnR3dYgCoAQAJAAYJsxzdYgCoAQApAAYJsBvJFQB0AQAAAA==.Misshell:BAAALgAECgEJAwAAAA==.Mistsmoker:BAAALgAECgYJBgABLgAFFAUJFwAkAOMgAA==.',
Ml='Mlleena:BAABLgAECn82AAMSAAcJEBGgewBBAQASAAcJEBGgewBBAQAhAAMJxAr9GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8nAAMdAAkJVhmXBgBkAgAdAAcJqR2XBgBkAgASAAYJFhfUUQClAQAAAA==.Moloch:BAAALgAECgEJAgAAAA==.Monangai:BAAALgAECgcJEQABLgAECggJGwAWAB4dAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBwAAAA==.Mooncake:BAAALgAECggJEgAAAA==.Moosiah:BAACLgAFFH8PAAIRAAQJBRofJAAyAQARAAQJBRofJAAyAQAuAAQKfzMAAxEACQklHfsMAPMCABEACQklHfsMAPMCABAACAm3IVUVACICAAAA.Mortenerra:BAABLgAECn8fAAIDAAYJjhg1JACeAQADAAYJjhg1JACeAQAAAA==.Mortraedeus:BAAALgAECgQJBAABLgAFFAUJDQAJAAISAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfire:BAAALgAFFAEJAQAAAA==.Mossfiré:BAAALgAECgYJEAABLgAFFAEJAQANAAAAAA==.Mossraven:BAAALgAECgIJAgABLgAFFAEJAQANAAAAAA==.Motoko:BAABLgAECn8qAAQgAAkJGxWaJQCEAQAgAAgJnxaaJQCEAQAeAAYJLxIFNgAWAQAiAAYJ6QhSTQDHAAAAAA==.',
Mu='Muatamuata:BAAALgAECgMJBgAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECgkJEgANAAAAAA==.',
My='Myhealmissed:BAAALgAECgEJAQAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECggJEQANAAAAAA==.Møøfi:BAAALgAECgcJEQAAAA==.',
Na='Nachomonk:BAAALgAECgQJBgAAAA==.Nachoshamy:BAAALgAECgUJBQAAAA==.Nameless:BAABLgAECn8oAAMVAAkJDxeIBQDUAQATAAkJGBPDTADyAQAVAAYJzhqIBQDUAQAAAA==.Narc:BAABLgAECn8iAAIRAAgJIAeFawDvAAARAAgJIAeFawDvAAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Narissa:BAAALgADCgQJBAAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAACLgAFFH8IAAMBAAQJHxU6RQAcAQABAAQJHxU6RQAcAQAKAAEJnQFyLQA8AAAuAAQKfzIAAwEACQk9IpoQAMgCAAEACQnEIZoQAMgCAAoACQk+F3YQALkCAAAA.Nazure:BAAALgAECgYJBgAAAA==.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn9SAAIBAAkJmx2lEwCxAgABAAkJmx2lEwCxAgAAAA==.New:BAAALgAECgEJAwAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgAECgYJCAAAAA==.Nicodranas:BAAALgADCgcJBwAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgAECgYJBgABLgAECgkJIQAiACQdAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8PAAMSAAYJpxA0PgBNAQASAAYJFg40PgBNAQAhAAIJExn2JwBFAAAuAAQKfyoABB0ACQm5HQgPANoBAB0ABwkgGAgPANoBABIABwk9GmBNALEBACEABgnfFaQVABkBAAAA.',
No='Noova:BAABLgAECn8yAAITAAcJ4CCNUABFAgATAAcJ4CCNUABFAgAAAA==.Norooux:BAAALgADCgkJDwAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Nw='Nwf:BAAALgADCgUJBQABLgAECggJGgAGAB0ZAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJCAALAFwGAA==.',
Ob='Obliverat:BAAALgAECgcJDwAAAA==.',
Od='Odysseus:BAAALgADCgUJBQAAAA==.',
Of='Of:BAAALgAECgMJBAAAAA==.',
Ol='Oldmangp:BAAALgADCggJDgAAAA==.Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgUJDAAAAA==.',
Op='Oprawindfúry:BAAALgAECgEJAQAAAA==.',
Or='Orangesorbet:BAAALgAECgEJAQAAAA==.Orcaneblast:BAACLgAFFH8SAAITAAUJEBrhTwBGAQATAAUJEBrhTwBGAQAuAAQKfy8AAhMACQmpIvUOAAADABMACQmpIvUOAAADAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDwAAAA==.Ornn:BAACLgAFFH8FAAIjAAMJWyDREQATAQAjAAMJWyDREQATAQAuAAQKfygAAiMACAlSIhQKAE0CACMACAlSIhQKAE0CAAAA.',
Pa='Palmtalon:BAAALgAECgQJCwAAAA==.Pandaminium:BAAALgAECgEJAQAAAA==.Pandarias:BAAALgAECgQJBQAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Paranoià:BAAALgAECgYJBgAAAA==.Partypizza:BAABLgAECn8xAAIWAAkJdR76DQCJAgAWAAkJdR76DQCJAgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAYJDQAeAGwiAA==.Penne:BAAALgAECgYJBwABLgAFFAUJEAATALgfAA==.Permanence:BAABLgAECn8UAAIbAAYJARZ3bQBbAQAbAAYJARZ3bQBbAQAAAA==.',
Ph='Phoeniex:BAAALgAECgUJBQABLgAECgkJIQAiACQdAA==.Phoenixphyre:BAAALgADCgUJBQAAAA==.',
Pi='Picobuffu:BAAALgAFFAEJAQABLgAFFAQJDgAbAJ0RAA==.Picodedge:BAACLgAFFH8OAAIbAAQJnREjSgAFAQAbAAQJnREjSgAFAQAuAAQKfzAAAxsACQllHJMkADkCABsACQllHJMkADkCABcAAQn0De9vACwAAAAA.Picoroo:BAAALgAECgcJEAABLgAFFAQJDgAbAJ0RAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pinkgauge:BAAALgAECggJCAAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn9EAAMTAAkJ6SGWCwAaAwATAAkJ6SGWCwAaAwAUAAYJZxbrBACOAQAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Pk='Pklock:BAAALgAECgYJBgAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgQJBwAAAA==.Porcini:BAAALgADCgMJAwAAAA==.Portent:BAAALgAECgEJAQAAAA==.Porthos:BAAALgADCgcJDAAAAA==.Poõpsikens:BAAALgAECgMJAwAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAISAAcJwBmlYwCfAQASAAcJwBmlYwCfAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAwAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.Pyrofox:BAAALgAECgEJAQABLgAECgkJIQAiACQdAA==.',
['Pü']='Pünish:BAACLgAFFH8WAAIMAAUJ9h9dSwBXAQAMAAUJ9h9dSwBXAQAuAAQKfz8AAwwACQmqIqYMAAYDAAwACQmqIqYMAAYDAA8ABQkqF9IXABQBAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qq='Qqpewpew:BAAALgAECgcJEQAAAA==.',
Qt='Qtpi:BAABLgAECn8gAAIbAAkJlh0JJAA8AgAbAAkJlh0JJAA8AgAAAA==.',
Qu='Quica:BAAALgAECgEJAQABLgAECggJGwAWAB4dAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAITAAgJWxmDQwBuAgATAAgJWxmDQwBuAgABLgAFFAgJIAATAG4cAA==.Raketh:BAABLgAECn8WAAIZAAgJFwohQwAaAQAZAAgJFwohQwAaAQAAAA==.Rallek:BAABLgAECn8wAAIfAAkJfhlaGgAwAgAfAAkJfhlaGgAwAgAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAFFAMJBQAjAFsgAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAABLgAECn8UAAIcAAkJYR7GCwB5AgAcAAkJYR7GCwB5AgAAAA==.Rehabherox:BAAALgADCgcJDgAAAA==.Rejuvince:BAAALgAECgUJBQAAAA==.Rektek:BAABLgAECn8aAAIGAAkJWBRVNADZAQAGAAkJWBRVNADZAQAAAA==.Rektnasty:BAAALgAECgMJBgAAAA==.Remeras:BAABLgAECn8cAAIJAAkJqxAAXgDJAQAJAAkJqxAAXgDJAQAAAA==.Resilientaid:BAABLgAECn8mAAIRAAgJPR10FQCaAgARAAgJPR10FQCaAgAAAA==.Restolyfe:BAAALgAFFAEJAgAAAA==.Retack:BAAALgAECgEJBAAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8mAAQeAAkJ/A17RgBKAQAeAAkJ/A17RgBKAQAiAAIJygssdwBlAAAgAAEJsASChQArAAAAAA==.Rilzi:BAAALgAECggJCgAAAA==.Ripblast:BAAALgAECgEJAQABLgAECgkJIQAiACQdAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAABLgAECn8YAAMnAAgJbyA4CQAtAgAnAAcJBiA4CQAtAgARAAEJCAeb0gAwAAABLgAECgkJPAAlAPUbAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Rohar:BAAALgAECgcJDgAAAA==.Roley:BAAALgADCgcJCgAAAA==.Rolybones:BAAALgAECgMJAwAAAA==.Roots:BAABLgAECn8iAAIRAAgJ3RDjOwCiAQARAAgJ3RDjOwCiAQAAAA==.Rosalie:BAAALgAECgMJAwAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgAECgMJAwAAAA==.Rossick:BAAALgAECgkJCQAAAA==.Roviz:BAAALgAECgYJBgABLgAFFAMJCgAjAPUZAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAwAAAA==.Ruuf:BAABLgAECn8sAAIWAAkJmgstOABTAQAWAAkJmgstOABTAQAAAA==.',
Ry='Rynohtwo:BAAALgAECgYJDgAAAA==.Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sabrinaa:BAAALgADCgYJBgAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQABLgAECgQJBAANAAAAAA==.Sappygurl:BAAALgAECgIJBAAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgQJBwAAAA==.',
Sc='Scalylusion:BAABLgAECn8aAAMYAAcJ+xyiEQDrAAAZAAYJ6RjkLQBTAQAYAAYJ2xqiEQDrAAAAAA==.Scrivener:BAAALgADCgcJCQAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.Scuddy:BAAALgADCgcJBwAAAA==.',
Se='Seanconery:BAAALgAECgcJDAAAAA==.Sebalen:BAAALgADCgEJAQAAAA==.Senica:BAABLgAECn8pAAIDAAkJUh07EgBPAgADAAkJUh07EgBPAgAAAA==.Sensedeous:BAAALgADCgcJDgAAAA==.Seriphina:BAAALgAECgcJDQAAAA==.Seventhsèal:BAACLgAFFH8IAAIMAAIJ0x4twwCdAAAMAAIJ0x4twwCdAAAuAAQKfxwAAwwABwmEI4w3AB4CAAwABwmEI4w3AB4CAA4ABQl7FiAkACABAAAA.',
Sh='Shabbarankz:BAABLgAECn8dAAInAAgJABYOCwASAgAnAAgJABYOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAABLgAECn80AAIIAAkJUBAqDgDKAQAIAAkJUBAqDgDKAQAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgYJCQABLgAECgkJIQAiACQdAA==.Shalanath:BAAALgADCgcJBwAAAA==.Shammyblammy:BAAALgADCgIJAgAAAA==.Sharded:BAABLgAECn8WAAITAAcJOgy94QAxAQATAAcJOgy94QAxAQABLgAECggJGwAWAB4dAA==.Sheepwreck:BAAALgAECgQJBAAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shinedown:BAAALgAECgEJAQAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgAECgEJAQABLgAECgQJBAANAAAAAA==.Shotbot:BAAALgADCgYJBgABLgAFFAUJDQAJAAISAA==.Shra:BAABLgAECn8hAAIkAAkJMhE3GgB2AQAkAAkJMhE3GgB2AQAAAA==.Shrafu:BAAALgAECgYJDgAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shweet:BAAALgAECgEJAQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECggJFgAZABcKAA==.Sindracosa:BAABLgAECn8XAAMYAAYJsgqMIAApAQAYAAYJsgqMIAApAQAcAAYJiQUZLwD5AAABLgAECgkJHQAXAHgQAA==.Sindradori:BAAALgADCgMJAwABLgAECgkJHAAFAKcZAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinoshi:BAAALgADCgcJCQAAAA==.Sinsidious:BAAALgADCggJFwAAAA==.Sizzle:BAAALgAECgkJDQABLgAECgkJFQALALcXAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAABLgAECn8bAAIlAAkJiRUtFgBcAgAlAAkJiRUtFgBcAgAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAABLgAECn8YAAIWAAgJMRNbMAB6AQAWAAgJMRNbMAB6AQAAAA==.Smokinchi:BAAALgAECgUJBwABLgAFFAQJEQAEAH4gAA==.Smokindots:BAACLgAFFH8IAAISAAQJEQjoYgD8AAASAAQJEQjoYgD8AAAuAAQKfyYAAhIACQltGrs+AOABABIACQltGrs+AOABAAEuAAUUBAkRAAQAfiAA.Smokinloud:BAAALgAECgcJEwAAAA==.Smokinmyrrh:BAABLgAECn8VAAMfAAgJ1BFLKgC6AQAfAAgJ1BFLKgC6AQAJAAIJCA2tQAFnAAABLgAFFAQJEQAEAH4gAA==.Smokinperiod:BAAALgADCgQJBAAAAA==.Smokinpsalm:BAABLgAECn8cAAMDAAcJ6xs2HAD7AQADAAcJ6xs2HAD7AQAFAAYJYAjRTgDSAAABLgAFFAQJEQAEAH4gAA==.Smokintotem:BAACLgAFFH8RAAIEAAQJfiAtHgB1AQAEAAQJfiAtHgB1AQAuAAQKf0YAAwQACQkIIUASALgCAAQACQkIIUASALgCABYAAQlTJXqAAGsAAAAA.Smööqüææd:BAAALgAECgQJBAAAAA==.',
Sn='Snawkin:BAAALgADCgUJBQAAAA==.Sneakingbush:BAABLgAECn88AAMlAAgJWhWIEwAEAgAlAAgJWhWIEwAEAgAaAAQJ8greEwDCAAAAAA==.Snowberry:BAAALgAECgMJBAAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8TAAIWAAcJERXnCwDeAQAWAAcJERXnCwDeAQAuAAQKfx0AAxYACAnpGEgmAN8BABYACAnpGEgmAN8BAAgAAwmxBWgkAJIAAAAA.Spaghett:BAACLgAFFH8QAAITAAUJuB9DRwBaAQATAAUJuB9DRwBaAQAuAAQKfxYAAhMACQnxGgdIAAACABMACQnxGgdIAAACAAAA.Spaghéttí:BAAALgAFFAIJAwABLgAFFAUJEAATALgfAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAACLgAFFH8MAAIgAAQJpiS6BgCkAQAgAAQJpiS6BgCkAQAuAAQKfzAAAyAACAmVJdMIALYCACAACAlmJdMIALYCACIABgnDIKkcAL4BAAAA.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAABLgAECn8lAAIQAAkJlhPqGQD5AQAQAAkJlhPqGQD5AQAAAA==.Stvr:BAAALgADCgEJAQAAAA==.',
Su='Sugarcookie:BAAALgAECgQJBgABLgAECgkJJgAOAOYUAA==.Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgUJBwABLgAECgkJKAAVAA8XAA==.Sundowning:BAABLgAECn8cAAIFAAkJzhXdGAD+AQAFAAkJzhXdGAD+AQAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sv='Svenya:BAAALgADCgYJDgAAAA==.',
Sw='Sweatsicle:BAAALgADCgUJCAABLgAFFAQJDwAnAJQkAA==.Swiftdragon:BAABLgAECn8hAAMiAAkJJB1ICQCbAgAiAAkJJB1ICQCbAgAeAAYJrRSKPgBtAQAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECgkJHAAhAIAgAA==.',
Sy='Sylerwinassa:BAAALgAECgUJCQAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Sylvy:BAEALgAECgUJBwABLgAECgUJFAAOAOgKAA==.Symbolofhope:BAABLgAFFH8KAAILAAQJ5RGOJgANAQALAAQJ5RGOJgANAQABLgAFFAUJBQASAOIYAA==.Synjo:BAABLgAECn80AAIPAAgJgBzLCgDMAQAPAAgJgBzLCgDMAQAAAA==.',
Ta='Taapfer:BAABLgAECn8gAAMCAAkJghwlAwCtAgACAAkJghwlAwCtAgAbAAEJAABjQQEAAAAAAA==.Tackyh:BAAALgAECggJEAAAAA==.Takamatsu:BAAALgAECgEJAgAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwABLgAECggJEQANAAAAAA==.Tassidar:BAAALgAECgUJDwAAAA==.Taxevelle:BAAALgAECgEJAQABLgAECgkJQwAGAJclAA==.Taxii:BAABLgAECn9DAAMGAAkJlyXSAQBeAwAGAAkJlyXSAQBeAwAHAAUJwRq5LAATAQAAAA==.',
Te='Teapots:BAACLgAFFH8KAAIIAAMJ+SKKCAAvAQAIAAMJ+SKKCAAvAQAuAAQKfxsAAggACQnBIggNANwBAAgACQnBIggNANwBAAAA.Teegria:BAAALgADCgYJBgAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAACLgAFFH8JAAIFAAMJbxA/JADOAAAFAAMJbxA/JADOAAAuAAQKfyUAAwUACQk7FzIiALQBAAUACQk7FzIiALQBAAMAAQmUCTV+ADUAAAAA.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgkJQwAfAOYgAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAACLgAFFH8NAAIJAAUJAhKqSgATAQAJAAUJAhKqSgATAQAuAAQKfykAAgkACQn4HhoRAAcDAAkACQn4HhoRAAcDAAAA.Thefifth:BAACLgAFFH8YAAIcAAcJFw7yAgDiAQAcAAcJFw7yAgDiAQAuAAQKfyoABBwACQlUGnsOAFACABwACQlUGnsOAFACABkACAncGa4VACoCABgAAwk3Et8yAH8AAAAA.Theralendris:BAABLgAECn8kAAMCAAkJ+hT6CADdAQACAAkJ+hT6CADdAQAXAAEJSQWJegAiAAAAAA==.Thickarm:BAAALgAFFAIJAgAAAA==.Thyrn:BAAALgADCgYJBgABLgAFFAMJBQAjAFsgAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8jAAIMAAkJAhpYOwARAgAMAAkJAhpYOwARAgAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAUJEgATABAaAA==.Treebeard:BAAALgAECgQJBAAAAA==.Tri:BAABLgAECn80AAMJAAkJmiVmBABWAwAJAAkJmiVmBABWAwApAAYJ6RzhEgCXAQAAAA==.Tristam:BAABLgAECn8ZAAMBAAkJACAQCwD5AgABAAkJACAQCwD5AgAoAAYJ2QfnNgD+AAAAAA==.',
Ts='Tsavo:BAABLgAECn8nAAMWAAgJIxHwOQBLAQAWAAgJIxHwOQBLAQAEAAEJBAWjoAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgUJEAAAAA==.Tuiren:BAAALgAECgcJBwAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgAECgcJDgAAAA==.Turgrok:BAACLgAFFH8FAAIKAAMJFRw8FgAKAQAKAAMJFRw8FgAKAQAuAAQKfxsAAgoACAnjHW4FAEsCAAoACAnjHW4FAEsCAAAA.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQANAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAACLgAFFH8KAAITAAQJtRXCXQAvAQATAAQJtRXCXQAvAQAuAAQKfyUAAxMACQm3JLwOAFEDABMACQm3JLwOAFEDABUAAQl0IusWAGMAAAAA.Tyllen:BAAALgAECggJDgABLgAFFAQJCgATALUVAA==.',
Un='Uniförm:BAABLgAECn8dAAMlAAkJyA/TJABrAQAlAAkJyA/TJABrAQAaAAEJTgSgLAAjAAAAAA==.',
Us='Ushioo:BAAALgAECgQJBwAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAACLgAFFH8KAAMjAAMJ9RnHGgC6AAAjAAMJ9RnHGgC6AAAHAAMJMATELgCdAAAuAAQKfzEAAiMACQkZJbECABcDACMACQkZJbECABcDAAAA.Vainhellsing:BAABLgAECn8kAAMXAAkJnAuwIABuAQAXAAkJnAuwIABuAQAbAAcJ1AVYqADQAAAAAA==.Vampage:BAAALgAECgkJEwAAAA==.Vandeadly:BAAALgAECgYJDwABLgAECgkJHgAOAGMiAA==.Vannethir:BAAALgAECgUJCQABLgAFFAUJEgATABAaAA==.Vanzen:BAAALgAECgYJBgAAAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8ZAAMBAAkJIxvfLQAhAgABAAkJRBrfLQAhAgAKAAcJfhV7MQCrAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8YAAIBAAkJvA9tMgDmAQABAAkJvA9tMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAFFAMJCgAjAPUZAA==.Verycurious:BAAALgAECgUJDwABLgAFFAIJAgANAAAAAA==.Vexahlias:BAABLgAFFH8FAAIMAAMJrxSbkQDkAAAMAAMJrxSbkQDkAAAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgcJEAABLgAECgkJPAAlAPUbAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgQJBAABLgAECgcJFwAQACEQAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
Vy='Vyral:BAAALgAECgkJCwAAAA==.',
['Vá']='Váder:BAAALgAECggJEwAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAFFAQJDQASAE4WAA==.Wernov:BAABLgAECn8aAAIEAAgJTiA4GwBuAgAEAAgJTiA4GwBuAgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8XAAIkAAUJ4yAwBwB9AQAkAAUJ4yAwBwB9AQAuAAQKfz4AAyQACQkkICEEANYCACQACQkkICEEANYCACcAAQlnFJxMADsAAAAA.',
Wi='Wichan:BAABLgAECn9NAAIkAAkJHCGtAwDjAgAkAAkJHCGtAwDjAgAAAA==.Wildstrike:BAAALgAECgYJBgABLgAECgkJKgAgABsVAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Win:BAAALgAECgMJBgAAAA==.Windrúnner:BAAALgAFFAIJAgAAAA==.Wiziviji:BAABLgAECn8VAAITAAgJtQ0dsAAeAQATAAgJtQ0dsAAeAQAAAA==.',
Wo='Woodrow:BAABLgAECn8YAAIfAAgJjh77KQDhAQAfAAgJjh77KQDhAQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8eAAMLAAcJ8hnWHgDUAQALAAcJ8hnWHgDUAQAFAAYJ4BP4WQCqAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
['Wà']='Wàrrîor:BAAALgAECgMJAwAAAA==.',
Xa='Xanddlock:BAAALgADCgYJBwAAAA==.Xanorea:BAAALgADCgcJBwABLgAECggJEQANAAAAAA==.',
Xc='Xclusive:BAAALgAECgEJAQAAAA==.',
Xf='Xfaith:BAAALgAECgEJAgAAAA==.Xfire:BAABLgAECn8XAAQcAAcJDxPjIAB2AQAcAAYJSBTjIAB2AQAZAAQJUQ/mRQDFAAAYAAEJdQt+JQAzAAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECggJEQANAAAAAA==.',
Xr='Xray:BAAALgAECgYJBwAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAABLgAECn8XAAIMAAgJfxkROAAdAgAMAAgJfxkROAAdAgAAAA==.Yes:BAAALgAECggJEQAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.Yezdi:BAAALgAECgkJBQAAAA==.',
Yi='Yisoonshin:BAABLgAECn8UAAIiAAYJPyUmEgCDAgAiAAYJPyUmEgCDAgABLgAFFAIJAgANAAAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJIQAAAA==.Yongwha:BAAALgAECgUJBQAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yuichi:BAAALgAECgEJAQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAABLgAECn8aAAMFAAgJwQj8OAAtAQAFAAgJwQj8OAAtAQADAAEJAwJlewAaAAAAAA==.',
Za='Zagera:BAAALgADCgcJCQAAAA==.Zaka:BAAALgAECgQJBAABLgAFFAUJFgAMAPYfAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECgkJEAAAAA==.Zango:BAAALgADCgMJAwAAAA==.Zanosuke:BAABLgAECn8WAAIlAAkJ5B+lDQBKAgAlAAkJ5B+lDQBKAgAAAA==.Zanzer:BAAALgADCgQJBAABLgAECgYJBgANAAAAAA==.Zarathis:BAAALgADCgEJAQAAAA==.Zaria:BAABLgAECn8dAAISAAcJmhNzeABsAQASAAcJmhNzeABsAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zegera:BAAALgADCgIJAgAAAA==.Zelkora:BAAALgADCgYJBgAAAA==.Zerica:BAAALgAECgMJBQAAAA==.Zerika:BAACLgAFFH8MAAIDAAQJOBDuGADuAAADAAQJOBDuGADuAAAuAAQKfyEAAgMACQn5HxEIAOgCAAMACQn5HxEIAOgCAAAA.',
Zi='Zigzwag:BAAALgAECgYJDgAAAA==.Zionna:BAAALgADCgYJAQABLgAECgkJEgANAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8XAAIIAAgJHBUrDgDaAQAIAAgJHBUrDgDaAQAAAA==.Zoose:BAAALgAECgEJAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8ZAAIGAAcJAhvELAABAgAGAAcJAhvELAABAgABLgAECggJPAAlAFoVAA==.',
Zy='Zydis:BAABLgAECn8YAAMnAAgJ4A7FIAD7AAAnAAYJ6ArFIAD7AAARAAcJRQj2bADrAAAAAA==.',
['Ád']='Ádolín:BAAALgAECgMJAwAAAA==.',
['Än']='Ännihilation:BAAALgAECgUJBgAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQANAAAAAA==.',
['És']='Éstéla:BAACLgAFFH8JAAIBAAMJmRNkXADkAAABAAMJmRNkXADkAAAuAAQKfzAAAgEACQmsF1Q3APwBAAEACQmsF1Q3APwBAAAA.',
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
