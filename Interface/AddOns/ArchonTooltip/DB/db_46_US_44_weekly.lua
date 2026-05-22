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

local lookup = {'Hunter-BeastMastery','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Evoker-Preservation','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','DeathKnight-Blood','Warlock-Destruction','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Hunter-Survival','Paladin-Protection','Mage-Fire','Rogue-Assassination','Warrior-Arms',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAABLgAECn8VAAIBAAcJsAhDZAAgAQABAAcJsAhDZAAgAQAAAA==.Abrakadaver:BAAALgAECgIJAwABLgAECggJHgACAKoeAA==.',
Ac='Activision:BAAALgAECgYJCwAAAA==.',
Ad='Ademisk:BAAALgADCgYJEgAAAA==.Adventureux:BAABLgAECn8gAAIBAAgJ7xvTKwDdAQABAAgJ7xvTKwDdAQAAAA==.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8dAAIDAAgJehWaLgCgAQADAAgJehWaLgCgAQAAAA==.',
Ai='Aiblul:BAAALgAFFAIJAgAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgcJEgABLgAECggJGQAEANkiAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgAFAAAAAA==.Aliroarx:BAAALgADCggJFAAAAA==.Almosteasy:BAABLgAECn8XAAIGAAgJLyPFBwAhAwAGAAgJLyPFBwAhAwAAAA==.Alunadoom:BAAALgADCggJDQAAAA==.Alunagryn:BAACLgAFFH8IAAIHAAQJXAYlHADyAAAHAAQJXAYlHADyAAAuAAQKfyQABAcACAllGZwTABICAAcACAnHFZwTABICAAgABwk3F1wfAN0BAAkABQnpGG81AGgBAAAA.Alvera:BAABLgAECn8nAAIKAAgJth7OOABTAgAKAAgJth7OOABTAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgABLgAECgUJBQAFAAAAAA==.',
An='Anaflora:BAAALgADCgEJAQAAAA==.Anduin:BAAALgAECgYJCQAAAA==.Angerforge:BAAALgAECgcJBwAAAA==.Angrydk:BAAALgAECgcJCwAAAA==.',
Ar='Arielordril:BAAALgAECgYJDQAAAA==.Arm:BAACLgAFFH8FAAILAAIJEwMVLQBnAAALAAIJEwMVLQBnAAAuAAQKfy0AAwwACAmBFzw1ANMBAAwABwnBFjw1ANMBAAsACAmcFe8XALUBAAAA.Armee:BAABLgAECn8cAAIJAAgJ3xzlDwBnAgAJAAgJ3xzlDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgYJCgAAAA==.',
As='Asmilwelme:BAAALgAECgQJCAAAAA==.Astrael:BAABLgAECn8eAAMNAAgJBxG4VwCUAQANAAgJSRC4VwCUAQAOAAUJ2hCmDgDZAAAAAA==.Aszayla:BAABLgAECn8UAAINAAcJRxCZfQA/AQANAAcJRxCZfQA/AQAAAA==.Aszea:BAAALgAECgYJCgAAAA==.',
Av='Avoidme:BAAALgAECgUJCgAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwAFAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8pAAIPAAgJ6xF8KgDCAQAPAAgJ6xF8KgDCAQAAAA==.Azóg:BAABLgAECn8yAAIKAAgJHBrHNQDhAQAKAAgJHBrHNQDhAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAFFAIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8dAAMQAAgJICAtAAD7AQARAAcJLCItBgAEAgAQAAYJ9hwtAAD7AQAuAAQKfyQAAxEACQk9JvsBAJkDABEACQk9JvsBAJkDABAACAmMJCUEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAAALgADCgcJCAABLgAFFAMJBwAIAFEFAA==.',
Be='Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgcJDgAAAA==.Beastoker:BAAALgAECgYJDAAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAgJGgANAGsiAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgAECgUJCgAAAA==.Beeto:BAACLgAFFH8PAAISAAQJvxTrIABEAQASAAQJvxTrIABEAQAuAAQKfxsAAhIACAlaHTokAJcCABIACAlaHTokAJcCAAAA.Bekdrop:BAABLgAECn8RAAITAAYJNCBiPACJAQATAAYJNCBiPACJAQABLgAFFAgJGgANAGsiAA==.Benlian:BAEALgAECgUJEQAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8VAAINAAYJJhGrHACPAQANAAYJJhGrHACPAQAuAAQKfyMAAw0ACAkgIbkgAPECAA0ACAkgIbkgAPECAA4AAQmmFUseADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.Bishtease:BAAALgADCgQJBAAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8SAAINAAUJCBaqMwBQAQANAAUJCBaqMwBQAQAuAAQKfyoAAg0ACQl4HjQbAAoDAA0ACQl4HjQbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAACLgAFFH8WAAIMAAgJ8BspAQDMAgAMAAgJ8BspAQDMAgAuAAQKfxYAAgwABwktJYsQAIoCAAwABwktJYsQAIoCAAEuAAUUBgkXABQAIhoA.Boof:BAABLgAECn8cAAIIAAkJpxlsGwACAgAIAAkJpxlsGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgAECgEJAwAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAAALgAECggJEgAAAA==.Bruski:BAAALgAECgMJBgAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAFFAMJBQANAHEZAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8YAAISAAgJVSKVQwAZAgASAAgJVSKVQwAZAgAAAA==.Buzzbuzz:BAAALgAECggJDwABLgAECgkJCQAFAAAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAIUAAYJIhodAgAKAgAUAAYJIhodAgAKAgAuAAQKfx8AAxQACQllHzMEABMDABQACQllHzMEABMDABAAAwn5Iu0iABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAIVAAMJaCBsFgAUAQAVAAMJaCBsFgAUAQABLgAFFAYJFwAUACIaAA==.',
['Bö']='Böba:BAAALgAECgYJBgABLgAFFAYJFwAUACIaAA==.',
Ca='Caelin:BAABLgAECn8kAAITAAcJ7RA4XgAcAQATAAcJ7RA4XgAcAQAAAA==.Caishana:BAABLgAECn8yAAMDAAkJaiIFBAAzAwADAAkJaiIFBAAzAwAPAAEJGgbphAAjAAAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAAALgAECggJEwAAAA==.',
Ce='Cecil:BAABLgAECn8iAAIWAAkJjwMcNQAsAQAWAAkJjwMcNQAsAQAAAA==.Celeb:BAABLgAECn8nAAICAAgJ8CMJAQAyAwACAAgJ8CMJAQAyAwAAAA==.Celebrity:BAAALgAECgUJCgABLgAECggJJwACAPAjAA==.Celebtard:BAAALgAECgIJAgABLgAECggJJwACAPAjAA==.Cervrakabra:BAAALgAECgEJAQAAAA==.',
Ch='Chaddingus:BAAALgAECgkJEAAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgQJCAAAAA==.Chilltea:BAABLgAECn8oAAINAAgJpCQ1EADGAgANAAgJpCQ1EADGAgAAAA==.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8fAAMXAAcJdAq5DwDuAAAXAAYJdAq5DwDuAAAYAAYJ3wg9lQDSAAAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAABLgAECn8nAAIWAAkJCCDDAwArAwAWAAkJCCDDAwArAwAAAA==.',
Co='Coheedkil:BAAALgAECgUJBQAAAA==.Coldbreeze:BAAALgAECgMJAwABLgAECgcJGQABAAsOAA==.Collateral:BAAALgAECgcJCgAAAA==.Compaktdisc:BAAALgAECgkJEgAAAA==.Conartist:BAAALgAECgYJBwABLgAECggJKwAZAH4lAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwAFAAAAAA==.Cowpox:BAABLgAECn8eAAIMAAkJWQ72LQClAQAMAAkJWQ72LQClAQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Creatrix:BAAALgAECgYJCAABLgAECggJKwAZAH4lAA==.Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAAALgAECgYJDAAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn87AAIWAAgJZSLxCAC2AgAWAAgJZSLxCAC2AgAAAA==.Cruv:BAAALgADCgQJAQAAAA==.Cry:BAAALgAECgMJBAAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8LAAIaAAQJhh3YDwBOAQAaAAQJhh3YDwBOAQAuAAQKfyMAAhoACQmIIDALANkCABoACQmIIDALANkCAAAA.',
Cy='Cybuster:BAAALgAECgcJDwABLgAFFAQJCQANAD8QAA==.Cyndle:BAAALgADCgkJCQABLgAECgkJFAAJABAXAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8bAAINAAgJ9hF/ewDaAQANAAgJ9hF/ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8bAAICAAkJDBXVCQDOAQACAAkJDBXVCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECgcJDAAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAABLgAECn8fAAISAAgJhwcVfQAoAQASAAgJhwcVfQAoAQABLgAECgUJGAAbANsKAA==.Dargong:BAAALgAECgIJAgAAAA==.Darkrunes:BAABLgAECn8dAAITAAcJLho0PgD7AQATAAcJLho0PgD7AQAAAA==.Darrkness:BAAALgAFFAIJBAAAAA==.Darthvikingw:BAAALgADCgcJDAAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJCgAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgUJCQABLgAECgkJJgAcAOYUAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAABLgAECn8cAAISAAgJpx8gGABzAgASAAgJpx8gGABzAgAAAA==.Deristus:BAABLgAECn8kAAIYAAkJRBXZMgDOAQAYAAkJRBXZMgDOAQAAAA==.Deroth:BAAALgAECgEJAQAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAAFAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Devi:BAAALgAECgIJAwAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dingeoffor:BAAALgAECgEJAgABLgAECgYJDgAFAAAAAA==.Dirtmonkgirt:BAABLgAECn8gAAIZAAkJ3BaZDQAgAgAZAAkJ3BaZDQAgAgAAAA==.Dirtnasty:BAAALgAECgUJCAAAAA==.Dirtysham:BAABLgAECn8cAAIPAAgJcBjJIQABAgAPAAgJcBjJIQABAgAAAA==.Discipline:BAABLgAECn8eAAIIAAkJ9hVpEAAHAgAIAAkJ9hVpEAAHAgAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8WAAMKAAYJqBJfkQBdAQAKAAYJqBJfkQBdAQAcAAYJ9QZGLACkAAAAAA==.Dotdotgoose:BAAALgAECggJCQABLgAECgkJEgAFAAAAAA==.Dotgunner:BAABLgAECn8XAAIYAAcJXRtBQAANAgAYAAcJXRtBQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgkJIAATAJYdAA==.Downbad:BAACLgAFFH8FAAIYAAMJdQcoJwDhAAAYAAMJdQcoJwDhAAAuAAQKfx8AAxgACAl+H1wXAMgCABgACAl+H1wXAMgCAB0ABAm8Cwg1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJHQAbAHYQAA==.Drahseer:BAAALgAECgIJAgAAAA==.Drakqueenjd:BAAALgADCgYJBgAAAA==.Drakulya:BAABLgAECn8XAAISAAYJhwvAmQD2AAASAAYJhwvAmQD2AAAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAABLgAECn8eAAMTAAgJ2wzUUABDAQATAAgJgwzUUABDAQAbAAMJMghrWgB5AAAAAA==.Drewish:BAAALgADCgQJBAAAAA==.Driftèr:BAAALgAECgcJEgAAAA==.Drizzle:BAACLgAFFH8FAAITAAMJHiAvKgAnAQATAAMJHiAvKgAnAQAuAAQKfyYAAhMACAmzJQ0KAMMCABMACAmzJQ0KAMMCAAAA.Drkdestro:BAABLgAECn8wAAQYAAkJByK8DwD8AgAYAAkJBSG8DwD8AgAXAAYJoh0uBwCXAQAdAAEJyxzIXwBPAAAAAA==.Druidic:BAACLgAFFH8QAAIMAAQJ/iPEDACnAQAMAAQJ/iPEDACnAQAuAAQKfzQAAgwACQkaJbkDAFYDAAwACQkaJbkDAFYDAAAA.Drunkhorn:BAAALgADCgMJAwAAAA==.Druvinci:BAAALgADCgQJBAAAAA==.Drü:BAABLgAECn8UAAILAAkJDxLhLQCVAQALAAkJDxLhLQCVAQAAAA==.',
Du='Duneshade:BAAALgADCgUJBQAAAA==.Dunk:BAAALgAECgEJAQAAAA==.Dusan:BAABLgAECn8pAAMJAAkJBh0cBwC7AgAJAAkJBh0cBwC7AgAHAAYJmgtoLAAVAQAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ear:BAAALgADCgcJBwABLgAFFAMJAwAFAAAAAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8kAAMDAAgJIRUQKgC6AQADAAgJIRUQKgC6AQAEAAQJ/wK6IgCqAAAAAA==.',
Ed='Edonsian:BAABLgAECn80AAMeAAkJCRsdEgAZAgAeAAkJoxodEgAZAgAfAAIJXRkqOgB6AAAAAA==.',
Ee='Eepy:BAABLgAECn8aAAMVAAkJoBHtHQDGAQAVAAkJoBHtHQDGAQAZAAUJuxG8NADgAAAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgAECgYJBQABLgAECgcJGQARAEsbAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAABLgAECn8UAAIfAAgJjxRNEQCEAQAfAAgJjxRNEQCEAQAAAA==.Emorlyn:BAABLgAECn8XAAMBAAkJwg+sNADcAQABAAkJwg+sNADcAQAGAAYJpgIgZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Endrai:BAAALgAECgEJAQAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAACLgAFFH8HAAINAAMJxA8SWAD0AAANAAMJxA8SWAD0AAAuAAQKfx4AAg0ACAk/HBFNAE8CAA0ACAk/HBFNAE8CAAAA.',
Er='Eriksangus:BAABLgAECn8XAAIeAAgJ/wdkOQAQAQAeAAgJ/wdkOQAQAQAAAA==.',
Es='Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAABLgAECn8eAAIMAAgJbw4MQwA7AQAMAAgJbw4MQwA7AQAAAA==.',
Ev='Evilguard:BAABLgAECn8mAAMcAAkJ5hR6DgDMAQAcAAgJmhd6DgDMAQAgAAEJ/gHLJwAIAAAAAA==.Evilpatty:BAAALgADCggJDQAAAA==.',
Ex='Excessive:BAAALgAECgEJAQAAAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECgcJCQAAAA==.',
Fa='Falador:BAAALgAECgMJAwAAAA==.Fariebubbles:BAAALgAECgcJEgAAAA==.Fastandis:BAAALgAECgYJBgAAAA==.Fatale:BAABLgAFFH8HAAITAAMJZxDnPwDdAAATAAMJZxDnPwDdAAAAAA==.Fatallock:BAAALgAECgUJBQABLgAFFAMJBwATAGcQAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMYAAcJgRm/aQCQAQAYAAYJghq/aQCQAQAdAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAAALgAFFAMJAwAAAA==.Fenixstraza:BAACLgAFFH8PAAQRAAQJNxYMJwDlAAARAAMJ1hkMJwDlAAAUAAMJThcnFwC/AAAQAAEJVwvzCQBLAAAuAAQKfy0AAxQACQmMG4AHADsCABQACAk5HYAHADsCABEACQn1FWofAMcBAAAA.Fervis:BAAALgAECgQJCAABLgAECggJFQARABYKAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJEgABLgAECgcJEgAFAAAAAA==.Firitako:BAAALgAECgcJEAAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECgkJLwAeAGMlAA==.Flipper:BAABLgAECn8ZAAMWAAkJKxSrIgAJAgAWAAkJKxSrIgAJAgASAAIJawFyRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8aAAMXAAkJgCCRAwBfAgAXAAkJgCCRAwBfAgAYAAIJBBThEwE6AAAAAA==.Frankiejr:BAAALgAECgQJCgABLgAECgcJHQASAKklAA==.Frapsity:BAABLgAECn8dAAIDAAgJbBZ4GwAYAgADAAgJbBZ4GwAYAgAAAA==.Frostamper:BAAALgAECgUJDgAAAA==.Frostnite:BAAALgAECgYJCQAAAA==.Frostpoptart:BAABLgAECn8oAAIDAAkJyhihIQDtAQADAAkJyhihIQDtAQAAAA==.Frozenblade:BAAALgAECgYJBgAAAA==.',
Fu='Fupah:BAAALgAECgIJAgAAAA==.Furball:BAAALgAECgMJAwABLgAFFAQJDQAYAGoSAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAACLgAFFH8LAAIaAAQJDyEBCgCCAQAaAAQJDyEBCgCCAQAuAAQKfxoAAxoACQl2HYEOABMCABoACQl2HYEOABMCABkAAQksBOKCACMAAAAA.Galadrielle:BAAALgAECgUJCQAAAA==.Gandelf:BAAALgADCgEJAQABLgAECggJIwABADUZAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Garret:BAAALgADCgQJBAABLgAECgcJJAATAO0QAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8pAAIhAAkJkAsBFwAfAQAhAAkJkAsBFwAfAQAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAACLgAFFH8FAAITAAMJSRTJOgDuAAATAAMJSRTJOgDuAAAuAAQKfysAAhMACAksHVAaADQCABMACAksHVAaADQCAAAA.',
Gh='Ghostfate:BAAALgAECgEJAQAAAA==.',
Gi='Gigbutt:BAABLgAECn82AAIiAAkJ9Rv5BwBfAgAiAAkJ9Rv5BwBfAgAAAA==.Giggléz:BAAALgAECgcJCgAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAINAAgJIBs8RABrAgANAAgJIBs8RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgADCgkJFQAAAA==.Goatedfury:BAACLgAFFH8IAAISAAQJEwKBQgDmAAASAAQJEwKBQgDmAAAuAAQKfxQAAhIACAnUFWhOAJMBABIACAnUFWhOAJMBAAAA.Goblegoble:BAAALgAECgEJAQAAAA==.Gorgrot:BAAALgAECgMJAwABLgAFFAQJDgALAD4XAA==.Gorshot:BAABLgAECn8YAAIBAAkJwgxsMgDAAQABAAkJwgxsMgDAAQAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Greatvibes:BAAALgAECgUJCQABLgAECgcJDgAFAAAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgADCgcJBwABLgAECggJMQAdAM4jAA==.Griitz:BAAALgAECggJCQAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAACLgAFFH8FAAIjAAMJzB7yBAAtAQAjAAMJzB7yBAAtAQAuAAQKfygAAyMACAnpIzwCAMoCACMACAnpIzwCAMoCACEABgmRDwMXAAUBAAAA.Griswold:BAABLgAECn8UAAIdAAYJmxjyCABqAQAdAAYJmxjyCABqAQAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8fAAMNAAgJqRvkQAB2AgANAAgJqRvkQAB2AgAOAAEJ0ibSFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJHwANAKkbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8LAAMcAAQJPBQlGADAAAAcAAMJLg8lGADAAAAKAAIJ2x57dwC4AAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJBgAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8fAAIIAAkJJAqhIQBlAQAIAAkJJAqhIQBlAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.Hawtdonna:BAAALgAECgcJBwAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8sAAQYAAkJXyLXBgD6AgAYAAkJXyLXBgD6AgAdAAMJeh4PMQD1AAAXAAEJzAQEKQAmAAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAwAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAABLgAECn8XAAISAAkJvRccPQAwAgASAAkJvRccPQAwAgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECgkJCQAFAAAAAA==.Hoofrat:BAAALgAECgcJBQAAAA==.',
Hp='Hpal:BAAALgAECgQJBAAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgcJDAAFAAAAAA==.Huxley:BAAALgADCgEJAQAAAA==.Huñted:BAABLgAECn8bAAMkAAgJAxMBFwCgAQAkAAgJng8BFwCgAQABAAYJIw7UYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgAECgMJBAAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgcJDAAFAAAAAA==.',
Ic='Icuris:BAAALgAECgMJBQAAAA==.',
Id='Idistroya:BAABLgAECn8ZAAIcAAcJnw89GwAqAQAcAAcJnw89GwAqAQABLgAECgkJRgABAJsjAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMXAAgJXhWQCADBAQAXAAYJ1BiQCADBAQAYAAgJBxHpSQB+AQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8XAAIJAAgJkhVVGwACAgAJAAgJkhVVGwACAgAAAA==.Ilithiya:BAAALgAECggJEQAAAA==.Illidrac:BAABLgAECn8dAAIbAAkJdhAhFACMAQAbAAkJdhAhFACMAQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJGQARAEsbAA==.',
Im='Imangry:BAABLgAECn8YAAIlAAcJRRH7FAApAQAlAAcJRRH7FAApAQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inconsolable:BAAALgADCgMJAwAAAA==.Inpherno:BAAALgAECgcJCAAAAA==.',
Is='Isaidnoice:BAABLgAECn8bAAMdAAgJ7hOgFgCVAQAdAAcJHBOgFgCVAQAYAAcJYg/dXQBHAQAAAA==.Ishton:BAAALgAFFAIJAgAAAA==.Istompgnomes:BAAALgAECggJDwAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgcJEwAAAA==.',
Ja='Jacked:BAABLgAECn8YAAMYAAgJQhw7TwDaAQAYAAYJPhs7TwDaAQAXAAMJMR/BEAAhAQAAAA==.Jasøn:BAAALgAECggJEAAAAA==.',
Je='Jecka:BAABLgAECn8nAAMIAAkJlRX/IQBhAQAIAAcJ/BH/IQBhAQAJAAgJPQ26QgAuAQAAAA==.Jeckah:BAAALgAECgYJCwABLgAECgkJJwAIAJUVAA==.Jecthyr:BAAALgAECgEJAQABLgAECgkJJwAIAJUVAA==.Jefryepsteen:BAAALgAECgUJBQAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAABLgAECn8dAAIJAAcJuRaBHACZAQAJAAcJuRaBHACZAQAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8YAAMlAAYJBB6aEABiAQAlAAYJBB6aEABiAQASAAEJrwL0WQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jo='Jordana:BAABLgAECn8WAAIMAAgJqBXsSQB7AQAMAAgJqBXsSQB7AQAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJAwAAAA==.',
Js='Jsdruid:BAAALgAECgYJDAAAAA==.',
Ju='Jug:BAABLgAECn8cAAIkAAgJqBuXBADPAgAkAAgJqBuXBADPAgAAAA==.Julaudette:BAAALgADCgcJDAAAAA==.',
Ka='Kainöa:BAAALgAECgYJEQABLgAECgcJDgAFAAAAAA==.Kakum:BAAALgAECgQJCAAAAA==.Kaldrogo:BAAALgAECgQJCgAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAYJHgAVAJ4cAA==.Kalnuggets:BAAALgAECgQJBAAAAA==.Kalrathen:BAABLgAECn8fAAIJAAgJxRLEIAB1AQAJAAgJxRLEIAB1AQAAAA==.Kaniku:BAAALgAECgEJBAABLgAFFAQJDAANAA0SAA==.Karmafel:BAAALgAECgEJAQABLgAECgYJGQAaAD4VAA==.Karsh:BAABLgAECn8gAAIeAAkJBwczLABTAQAeAAkJBwczLABTAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAABLgAECn8WAAMdAAcJGBA3JAA4AQAYAAcJ6g5MXQBIAQAdAAYJoQw3JAA4AQAAAA==.Kazurena:BAAALgADCgcJBQAAAA==.',
Ke='Kered:BAAALgAECgYJCgABLgAECggJLgALALYhAA==.Keuaakepo:BAABLgAECn9GAAMBAAkJmyPUBAAQAwABAAkJmyPUBAAQAwAkAAEJUQM9MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8oAAIBAAgJtBtoJQD7AQABAAgJtBtoJQD7AQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECggJCQABLgAECgkJEgAFAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgQJBQAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAABLgAECn8VAAIHAAYJfQn/LQAKAQAHAAYJfQn/LQAKAQAAAA==.',
Ko='Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8qAAMjAAkJLxcEBQBOAgAjAAkJLxcEBQBOAgAhAAIJ0AwgKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJDQAAAA==.',
Kr='Krethar:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Krypt:BAABLgAECn8eAAIfAAkJwhM/GwBxAQAfAAkJwhM/GwBxAQAAAA==.Krìzl:BAACLgAFFH8GAAINAAMJ3BvtSwAVAQANAAMJ3BvtSwAVAQAuAAQKfy8AAg0ACAnDIwsYAJACAA0ACAnDIwsYAJACAAEuAAUUBQkXAAoA7SUA.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgQJBAAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAABLgAECn8xAAQdAAgJziNbAwC9AgAdAAgJiCFbAwC9AgAYAAYJ6h60JgAFAgAXAAEJHh7pIgA/AAAAAA==.Lanzen:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.Lanzier:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Larrfena:BAABLgAECn8cAAIBAAgJMBsFIwAIAgABAAgJMBsFIwAIAgAAAA==.',
Le='Legit:BAAALgAECgcJDAABLgAECggJHQATAC4aAA==.Legsday:BAAALgADCgYJDAAAAA==.Lementz:BAACLgAFFH8UAAIEAAUJDiCtAADIAQAEAAUJDiCtAADIAQAuAAQKfz8AAgQACQnXJhEAAI8DAAQACQnXJhEAAI8DAAAA.Lexiiees:BAABLgAECn8aAAIiAAcJuwSjKgDlAAAiAAcJuwSjKgDlAAAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAAALgAECgYJDwABLgAECgcJEgAFAAAAAA==.Lillia:BAABLgAECn8pAAIYAAkJQRFsNADHAQAYAAkJQRFsNADHAQAAAA==.',
Lo='Lockyshocky:BAAALgADCgcJCQAAAA==.Lovetobussy:BAABLgAECn8aAAIJAAYJ9Bq8GAC8AQAJAAYJ9Bq8GAC8AQAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn9BAAQYAAkJMSJ0BQAPAwAYAAkJMSJ0BQAPAwAdAAUJhR1/GwBxAQAXAAIJ9hyAFgCXAAAAAA==.Lumpia:BAABLgAECn8iAAIKAAgJbSF1FwB3AgAKAAgJbSF1FwB3AgAAAA==.',
['Lè']='Lèah:BAAALgAECgUJCgAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAEJAQABLgAFFAMJCgANADsjAA==.Madgeyoulook:BAAALgAECgEJAQAAAA==.Magenta:BAAALgAECgUJBQAAAA==.Magicchoc:BAAALgAECgYJDAABLgAECgkJJgAcAOYUAA==.Maktah:BAACLgAFFH8IAAIEAAQJSAZ+BQAOAQAEAAQJSAZ+BQAOAQAuAAQKfxQAAwQACAn0F9cIAM8BAAQACAn0F9cIAM8BAA8AAQl0EOGFADUAAAAA.Mandrakor:BAAALgADCgEJAQAAAA==.Marshboa:BAAALgAECgUJCgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mcgurk:BAAALgAECgMJAwAAAA==.Mclovinit:BAACLgAFFH8aAAINAAgJayKwAAD0AgANAAgJayKwAAD0AgAuAAQKf1AAAg0ACQmpJnoAAAIEAA0ACQmpJnoAAAIEAAAA.Mcmagic:BAACLgAFFH8HAAINAAQJPxraJQBtAQANAAQJPxraJQBtAQAuAAQKfycAAg0ABwkrI04lAEYCAA0ABwkrI04lAEYCAAEuAAUUCAkaAA0AayIA.Mcpally:BAABLgAECn83AAISAAkJUCL3BgAFAwASAAkJUCL3BgAFAwAAAA==.',
Me='Mecca:BAACLgAFFH8IAAIKAAIJ0x4qdgC7AAAKAAIJ0x4qdgC7AAAuAAQKfxsAAwoABwmEI1wiADcCAAoABwmEI1wiADcCABwABQl7FiAkACABAAAA.Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8dAAIMAAkJeCO3CAADAwAMAAkJeCO3CAADAwAAAA==.Mensu:BAAALgAECgYJCwAAAA==.Mentos:BAABLgAECn8mAAMQAAkJgxc/AwAsAgAQAAgJgxc/AwAsAgAUAAYJJx5MCgDwAQAAAA==.Mercilezz:BAAALgAECgIJAgAAAA==.',
Mi='Midwestfel:BAABLgAECn8cAAITAAgJzgYcgwDFAAATAAgJzgYcgwDFAAAAAA==.Mikeoxhard:BAAALgAECggJCgAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAABLgAECn8bAAIIAAgJ2xIsIABvAQAIAAgJ2xIsIABvAQAAAA==.Minihulk:BAAALgAECgYJCQAAAA==.Mionn:BAAALgAECgUJDgAAAA==.Misshell:BAAALgAECgEJAQAAAA==.',
Ml='Mlleena:BAABLgAECn8qAAMYAAcJOw8WXgBGAQAYAAcJOw8WXgBGAQAXAAMJxAr9GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8jAAMdAAkJ9BiXBgBkAgAdAAcJqR2XBgBkAgAYAAYJxBQUSACDAQAAAA==.Monangai:BAAALgAECgYJDwABLgAECgcJEgAFAAAAAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBgAAAA==.Mooncake:BAAALgAECggJEgAAAA==.Moosiah:BAABLgAECn8uAAMLAAgJtiGUDQAvAgALAAgJtiGUDQAvAgAMAAYJ3xxiIgDwAQAAAA==.Mortenerra:BAAALgAECgUJEAAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfiré:BAAALgAECgYJEAAAAA==.Motoko:BAABLgAECn8pAAQZAAkJ6ROVGwCBAQAZAAgJRRWVGwCBAQAVAAYJLxIFNgAWAQAaAAYJ6QjpPADMAAAAAA==.',
Mu='Muatamuata:BAAALgAECgEJAQAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECgkJEgAFAAAAAA==.',
My='Myhealmissed:BAAALgADCggJCAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECggJEAAFAAAAAA==.Møøfi:BAAALgAECgQJBwAAAA==.',
Na='Nachomonk:BAAALgAECgEJAQAAAA==.Nachoshamy:BAAALgAECgUJBQAAAA==.Nameless:BAABLgAECn8nAAMOAAkJyBaIBQDUAQANAAkJ0RLeMgALAgAOAAYJzhqIBQDUAQAAAA==.Narc:BAABLgAECn8fAAIMAAgJDweUVQD0AAAMAAgJDweUVQD0AAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Narissa:BAAALgADCgQJBAAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAACLgAFFH8IAAMBAAQJHxWRHgA8AQABAAQJHxWRHgA8AQAGAAEJnQFyLQA8AAAuAAQKfyYAAwEACQkvH2EUAGYCAAYACQk+F3YQALkCAAEACQk5HWEUAGYCAAAA.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn8pAAIBAAgJIxUcOACpAQABAAgJIxUcOACpAQAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgADCggJFQAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECgkJEgAFAAAAAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8NAAMYAAUJvQ1XQQAFAQAYAAQJiApXQQAFAQAXAAIJExmpDgBSAAAuAAQKfyYABB0ACQkvHQgPANoBAB0ABwmuFggPANoBABgABwlhGbxNAHMBABcABQmRFQYQAOoAAAAA.',
No='Noova:BAABLgAECn8sAAINAAcJrB+NUABFAgANAAcJrB+NUABFAgAAAA==.Norooux:BAAALgADCgkJDQAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJCAAHAFwGAA==.',
Ob='Obliverat:BAAALgAECgcJDQAAAA==.',
Ol='Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgQJCgAAAA==.',
Or='Orcaneblast:BAACLgAFFH8MAAINAAQJDRL8OgBEAQANAAQJDRL8OgBEAQAuAAQKfywAAg0ACQnkIR8KAPwCAA0ACQnkIR8KAPwCAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDwAAAA==.Ornn:BAABLgAECn8oAAIfAAgJUyKPBQB4AgAfAAgJUyKPBQB4AgAAAA==.',
Pa='Palmtalon:BAAALgAECgMJBwAAAA==.Pandaminium:BAAALgAECgEJAQAAAA==.Pandarias:BAAALgAECgMJAwAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Partypizza:BAABLgAECn8xAAIPAAkJdR6JBwCiAgAPAAkJdR6JBwCiAgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAQJEAAMAP4jAA==.Penne:BAAALgAECgYJBwABLgAFFAMJCgANADsjAA==.Permanence:BAABLgAECn8UAAITAAYJARZ3bQBbAQATAAYJARZ3bQBbAQAAAA==.',
Ph='Phoeniex:BAAALgAECgUJBQABLgAECgkJEgAFAAAAAA==.',
Pi='Picobuffu:BAAALgAECgYJDAABLgAECggJLAATAEIdAA==.Picodedge:BAABLgAECn8sAAITAAgJQh3oIgD+AQATAAgJQh3oIgD+AQAAAA==.Picoroo:BAAALgAECgUJBQABLgAECggJLAATAEIdAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn8tAAMNAAkJURpvIABgAgANAAkJyxlvIABgAgAmAAQJ0xEhBgD0AAAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgMJAwAAAA==.Porthos:BAAALgADCgcJDAAAAA==.Poõpsikens:BAAALgAECgMJAwAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAIYAAcJwBmlYwCfAQAYAAcJwBmlYwCfAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAwAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8OAAIKAAQJJx6eIwBtAQAKAAQJJx6eIwBtAQAuAAQKfy4AAgoACAniI4MTAJMCAAoACAniI4MTAJMCAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qq='Qqpewpew:BAAALgAECgcJDgAAAA==.',
Qt='Qtpi:BAABLgAECn8gAAITAAkJlh2SFwBHAgATAAkJlh2SFwBHAgAAAA==.',
Qu='Quica:BAAALgAECgEJAQABLgAECgcJEgAFAAAAAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAINAAgJWxmDQwBuAgANAAgJWxmDQwBuAgABLgAFFAcJFwANAB0bAA==.Raketh:BAABLgAECn8VAAIRAAgJFgrqMAAaAQARAAgJFgrqMAAaAQAAAA==.Rallek:BAABLgAECn8wAAIWAAkJfhl0EABLAgAWAAkJfhl0EABLAgAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECggJKAAfAFMiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAABLgAECn8UAAIUAAkJYR7GCwB5AgAUAAkJYR7GCwB5AgAAAA==.Rehabherox:BAAALgADCgcJDgAAAA==.Rektek:BAABLgAECn8aAAIeAAkJWBRVNADZAQAeAAkJWBRVNADZAQAAAA==.Rektnasty:BAAALgAECgIJAwAAAA==.Remeras:BAABLgAECn8bAAISAAkJIRAAXgDJAQASAAkJIRAAXgDJAQAAAA==.Resilientaid:BAABLgAECn8YAAIMAAYJZR8xHQAUAgAMAAYJZR8xHQAUAgAAAA==.Restolyfe:BAAALgAECgUJCwAAAA==.Retack:BAAALgAECgEJAgAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8mAAQVAAkJ/A3HKgBKAQAVAAkJ/A3HKgBKAQAaAAIJygssdwBlAAAZAAEJsASChQArAAAAAA==.Rilzi:BAAALgAECggJCgAAAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAABLgAECn8UAAMjAAgJ7B+kBgAaAgAjAAcJbR+kBgAaAgAMAAEJCAeiqwAxAAABLgAECgkJNgAiAPUbAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Rohar:BAAALgAECgcJDgAAAA==.Roley:BAAALgADCgcJCgAAAA==.Roots:BAAALgAECgUJDwAAAA==.Rosalie:BAAALgADCgUJBQAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgADCgYJBgAAAA==.Rossick:BAAALgAECgkJCQAAAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAwAAAA==.Ruuf:BAABLgAECn8mAAIPAAkJEQq0KgBEAQAPAAkJEQq0KgBEAQAAAA==.',
Ry='Rynohtwo:BAAALgAECgEJAQAAAA==.Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sabrinaa:BAAALgADCgYJBgAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgAECgEJAQAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgQJBwAAAA==.',
Sc='Scalylusion:BAABLgAECn8ZAAMRAAcJSxvkLQBTAQARAAYJ6RjkLQBTAQAQAAYJ1BhrIQAgAQAAAA==.Scrivener:BAAALgADCgEJAQAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.',
Se='Seanconery:BAAALgAECgcJDAAAAA==.Senica:BAABLgAECn8pAAIJAAkJUx07EgBPAgAJAAkJUx07EgBPAgAAAA==.Sensedeous:BAAALgADCgcJDQAAAA==.Seriphina:BAAALgADCgkJFQAAAA==.',
Sh='Shabbarankz:BAABLgAECn8dAAIjAAgJABYOCwASAgAjAAgJABYOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAABLgAECn8jAAIEAAgJkw+ZDAB7AQAEAAgJkw+ZDAB7AQAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgQJBAABLgAECgkJEgAFAAAAAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAAALgAECgcJEgAAAA==.Sheepwreck:BAAALgAECgQJBAAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shinedown:BAAALgADCgMJAwAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgADCgQJBAAAAA==.Shotbot:BAAALgADCgYJBgABLgAFFAUJCgASAAMSAA==.Shra:BAABLgAECn8hAAIhAAkJMhEEDwCEAQAhAAkJMhEEDwCEAQAAAA==.Shrafu:BAAALgAECgYJDAAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECggJFQARABYKAA==.Sindracosa:BAABLgAECn8XAAMQAAYJsgqMIAApAQAQAAYJsgqMIAApAQAUAAYJiQUZLwD5AAABLgAECgkJHQAbAHYQAA==.Sindradori:BAAALgADCgMJAwABLgAECgkJHAAIAKcZAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinoshi:BAAALgADCgQJAgAAAA==.Sinsidious:BAAALgADCggJFwAAAA==.Sizzle:BAAALgAECgkJCQAAAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAABLgAECn8VAAIiAAgJKRctFgBcAgAiAAgJKRctFgBcAgAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAABLgAECn8YAAIPAAgJMRMZIACMAQAPAAgJMRMZIACMAQAAAA==.Smokindots:BAABLgAECn8eAAIYAAkJBxgbVQBeAQAYAAkJBxgbVQBeAQABLgAECgkJPQADAAghAA==.Smokinloud:BAAALgAECgcJBwAAAA==.Smokinmyrrh:BAAALgAECgMJAwABLgAECgkJPQADAAghAA==.Smokinperiod:BAAALgADCgUJBQAAAA==.Smokinpsalm:BAABLgAECn8ZAAMJAAcJ6xs2HAD7AQAJAAcJ6xs2HAD7AQAIAAQJAAcVQgCuAAABLgAECgkJPQADAAghAA==.Smokintotem:BAABLgAECn89AAIDAAkJCCFcCgDFAgADAAkJCCFcCgDFAgAAAA==.',
Sn='Sneakingbush:BAABLgAECn8gAAMiAAcJfQ2jLACaAQAiAAcJUw2jLACaAQAnAAQJ8greEwDCAAAAAA==.Snowberry:BAAALgAECgMJBAAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8KAAIPAAQJOgwkHwDbAAAPAAQJOgwkHwDbAAAuAAQKfxkAAw8ACAlLEUgmAN8BAA8ACAlLEUgmAN8BAAQAAwmxBWgkAJIAAAEuAAUUBgkVAA0AJhEA.Spaghett:BAABLgAFFH8KAAINAAMJOyMRTAAVAQANAAMJOyMRTAAVAQAAAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAABLgAECn8rAAMZAAgJfiWuBQC3AgAZAAgJTyWuBQC3AgAaAAYJwyDFFADJAQAAAA==.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAAALgAECggJDwAAAA==.',
Su='Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgUJBwABLgAECgkJJwAOAMgWAA==.Sundowning:BAABLgAECn8bAAIIAAkJzhWpDwARAgAIAAkJzhWpDwARAgAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sw='Sweatsicle:BAAALgADCgMJAwABLgAFFAMJBQAjAMweAA==.Swiftdragon:BAAALgAECgkJEgAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECgkJGgAXAIAgAA==.',
Sy='Sylerwinassa:BAAALgAECgUJCQAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Sylvy:BAEALgAECgUJBgABLgAECgUJEQAFAAAAAA==.Symbolofhope:BAAALgAECgYJDgAAAA==.Synjo:BAABLgAECn8rAAIgAAgJgBx1BQDkAQAgAAgJgBx1BQDkAQAAAA==.',
Ta='Taapfer:BAABLgAECn8eAAMCAAgJqh4lAwCtAgACAAgJqh4lAwCtAgATAAEJAADu+gAAAAAAAA==.Tackyh:BAAALgAECgYJCwAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwABLgAECggJEAAFAAAAAA==.Tassidar:BAAALgAECgUJCgAAAA==.Taxevelle:BAAALgAECgEJAQABLgAECgkJLwAeAGMlAA==.Taxii:BAABLgAECn8vAAMeAAkJYyWxAgAUAwAeAAkJKyWxAgAUAwAoAAUJwRqIGwAiAQAAAA==.',
Te='Teapots:BAABLgAECn8ZAAIEAAgJ2SJWCQBDAgAEAAgJ2SJWCQBDAgAAAA==.Teegria:BAAALgADCgYJBgAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAABLgAECn8lAAMIAAkJOxeTFQDNAQAIAAkJOxeTFQDNAQAJAAEJlAk1fgA1AAAAAA==.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgkJJwAWAAggAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAACLgAFFH8KAAISAAUJAxJHIwA+AQASAAUJAxJHIwA+AQAuAAQKfykAAhIACQn3HhoRAAcDABIACQn3HhoRAAcDAAAA.Thefifth:BAACLgAFFH8YAAIUAAcJFw7yAgDiAQAUAAcJFw7yAgDiAQAuAAQKfyUABBQACQkNGnsOAFACABQACQkNGnsOAFACABEABAnWGs8mAFUBABAAAwk3Et8yAH8AAAAA.Theralendris:BAABLgAECn8gAAICAAkJ3BSXBQD1AQACAAkJ3BSXBQD1AQAAAA==.Thickarm:BAAALgAECgYJDAABLgAECgcJDgAFAAAAAA==.Thyrn:BAAALgADCgYJBgABLgAECggJKAAfAFMiAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8jAAIKAAkJAhowJgAjAgAKAAkJAhowJgAjAgAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAQJDAANAA0SAA==.Treebeard:BAAALgADCgYJCwAAAA==.Tri:BAABLgAECn8dAAISAAcJqSWbFwB2AgASAAcJqSWbFwB2AgAAAA==.Tristam:BAAALgAECgYJCwAAAA==.',
Ts='Tsavo:BAABLgAECn8nAAMPAAgJIRHPJwBYAQAPAAgJIRHPJwBYAQADAAEJBAWjoAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgUJDAAAAA==.Tuiren:BAAALgAECgcJBwAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgADCgcJDgAAAA==.Turgrok:BAAALgAECgYJEAAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAACLgAFFH8JAAINAAQJPxB/QgA1AQANAAQJPxB/QgA1AQAuAAQKfyIAAw0ACQl+IrwOAFEDAA0ACQl+IrwOAFEDAA4AAQl0IusWAGMAAAAA.',
Un='Uniförm:BAABLgAECn8dAAMiAAkJyA8YGACCAQAiAAkJyA8YGACCAQAnAAEJTgQ4IgAmAAAAAA==.',
Us='Ushioo:BAAALgAECgQJBAAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAACLgAFFH8HAAMfAAMJGRnpDwDnAAAfAAMJGRnpDwDnAAAoAAMJMAR5FgCrAAAuAAQKfzEAAh8ACQkTJRABAD0DAB8ACQkTJRABAD0DAAAA.Vainhellsing:BAABLgAECn8UAAMbAAgJUwc+LgCuAAATAAcJgwSdigC2AAAbAAUJqwk+LgCuAAABLgAECggJKQAPAOsRAA==.Vampage:BAAALgAECggJEQAAAA==.Vandeadly:BAAALgAECgYJDwABLgAECgkJHgAcAGMiAA==.Vannethir:BAAALgAECgQJBAABLgAFFAQJDAANAA0SAA==.Vanzen:BAAALgAECgYJBgAAAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8ZAAMBAAkJIxvXFwBMAgABAAkJRBrXFwBMAgAGAAcJfhV7MQCrAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8XAAIBAAgJahBtMgDmAQABAAgJahBtMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAFFAMJBwAfABkZAA==.Verycurious:BAAALgAECgUJDQABLgAECgcJDgAFAAAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgcJEAABLgAECgkJNgAiAPUbAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgQJBAABLgAECgcJFwALACEQAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
Vy='Vyral:BAAALgAECgYJBwAAAA==.',
['Vá']='Váder:BAAALgAECggJDAAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAECggJMQAdAM4jAA==.Wernov:BAABLgAECn8aAAIDAAgJTiAAEACAAgADAAgJTiAAEACAAgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8OAAIhAAQJlR/AAgCEAQAhAAQJlR/AAgCEAQAuAAQKfzEAAyEACQmqH20CANMCACEACQmqH20CANMCACMAAQlnFIEvAD0AAAAA.',
Wi='Wichan:BAABLgAECn83AAIhAAkJIR8AAwC3AgAhAAkJIR8AAwC3AgAAAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Windrúnner:BAAALgAECgUJCQAAAA==.Wiziviji:BAABLgAECn8VAAINAAgJtQ2CigAnAQANAAgJtQ2CigAnAQAAAA==.',
Wo='Woodrow:BAABLgAECn8YAAIWAAgJjh7FHQDIAQAWAAgJjh7FHQDIAQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8eAAMHAAcJ8xmVEwDrAQAHAAcJ8xmVEwDrAQAIAAYJ3hMDRACkAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
['Wà']='Wàrrîor:BAAALgAECgIJAgAAAA==.',
Xa='Xanddlock:BAAALgADCgQJBAAAAA==.Xanorea:BAAALgADCgcJBwABLgAECggJEQAFAAAAAA==.',
Xc='Xclusive:BAAALgAECgEJAQAAAA==.',
Xf='Xfaith:BAAALgAECgEJAQAAAA==.Xfire:BAABLgAECn8WAAQUAAcJDxPjIAB2AQAUAAYJSBTjIAB2AQARAAQJOw/mRQDFAAAQAAEJdQuRHAA2AAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECggJEAAFAAAAAA==.',
Xr='Xray:BAAALgAECgYJBgAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAAALgAECgYJCgAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.',
Yi='Yisoonshin:BAABLgAECn8UAAIaAAYJPyUmEgCDAgAaAAYJPyUmEgCDAgABLgAECgcJDgAFAAAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJIAAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yuichi:BAAALgAECgEJAQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAAALgAECgYJCwAAAA==.',
Za='Zagera:BAAALgADCgcJBwAAAA==.Zaka:BAAALgAECgMJAwAAAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECgkJDQAAAA==.Zanosuke:BAABLgAECn8VAAIiAAkJ3R9CBwBuAgAiAAkJ3R9CBwBuAgAAAA==.Zanzer:BAAALgADCgQJBAABLgAECgYJBgAFAAAAAA==.Zaria:BAABLgAECn8dAAIYAAcJmhN9bQAjAQAYAAcJmhN9bQAjAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zelkora:BAAALgADCgYJBgAAAA==.Zerica:BAAALgAECgEJAQAAAA==.Zerika:BAABLgAECn8fAAIJAAgJriKyBQDeAgAJAAgJriKyBQDeAgAAAA==.',
Zi='Zigzwag:BAAALgAECgYJCAAAAA==.Zionna:BAAALgADCgYJAQABLgAECgkJEgAFAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8XAAIEAAgJHBUrDgDaAQAEAAgJHBUrDgDaAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8ZAAIeAAcJAhvELAABAgAeAAcJAhvELAABAgABLgAECgcJIAAiAH0NAA==.',
Zy='Zydis:BAAALgAECgcJDgAAAA==.',
['Ád']='Ádolín:BAAALgAECgMJAwAAAA==.',
['Än']='Ännihilation:BAAALgADCggJDQAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQAFAAAAAA==.',
['És']='Éstéla:BAABLgAECn8wAAIBAAkJrBfRHQAkAgABAAkJrBfRHQAkAgAAAA==.',
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
