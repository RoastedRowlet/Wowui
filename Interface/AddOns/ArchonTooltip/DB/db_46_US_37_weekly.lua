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

local lookup = {'Druid-Restoration','Druid-Balance','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Priest-Holy','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Warrior-Fury','Druid-Guardian','DeathKnight-Frost','DemonHunter-Devourer','Priest-Shadow','Evoker-Devastation','DemonHunter-Havoc','Mage-Fire','Evoker-Preservation','Druid-Feral','Shaman-Elemental','Warlock-Affliction','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Aconite:BAAALgAFFAEJAQAAAA==.',
Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8sAAMBAAgJExrnCQBZAgABAAgJExrnCQBZAgACAAUJCB+gGwA9AQAuAAQKfzQAAwIACQnQI5QQAJsCAAIACAncJJQQAJsCAAEACQmeHk8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8yAAIDAAkJIiRXAwCHAwADAAkJIiRXAwCHAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgAECgIJAgAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alielil:BAAALgAECgIJAgABLgAECgkJQAAGAI8YAA==.Alikith:BAABLgAECn85AAQHAAkJJBXBCwAKAgAHAAkJJBXBCwAKAgAIAAMJgAhtJgGMAAAJAAEJyRIziQA4AAAAAA==.Alkaline:BAAALgADCggJEwAAAA==.Altheyra:BAAALgAECgYJCgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alyas:BAAALgAECggJCAAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrai:BAAALgAECgUJBQAAAA==.Ambrìel:BAABLgAECn9CAAIKAAkJ/xCxTwDtAQAKAAkJ/xCxTwDtAQAAAA==.Amelía:BAAALgAECgYJBgABLgAFFAQJEwABAMoJAA==.Amitre:BAAALgAECgcJBwAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMBAAQJyglaOwDBAAABAAQJyglaOwDBAAACAAIJwwLOFwB5AAAuAAQKfyEAAwEACQn1F58rAPwBAAEACQn1F58rAPwBAAIAAQlOHVZ9AEwAAAAA.',
An='Angando:BAABLgAECn8/AAILAAkJmRcMDQAZAgALAAkJmRcMDQAZAgAAAA==.Angandomix:BAAALgAECgEJAgAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Ankleblaster:BAAALgADCgYJDAAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8hAAICAAgJKxHJLAByAQACAAgJKxHJLAByAQAAAA==.',
Ap='Aperfecttool:BAAALgAECggJCQAAAA==.',
Aq='Aquaregia:BAAALgAECgYJBgAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Ariellá:BAAALgAECgQJDQAAAA==.Arrows:BAAALgAECgMJAwAAAA==.Artemidoros:BAABLgAECn8xAAQMAAkJ/yDOBgCzAgAMAAkJLCDOBgCzAgANAAYJGiEVIQA/AgAOAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8VAAIPAAUJCBD9LgAmAQAPAAUJCBD9LgAmAQAuAAQKfyEAAg8ACQkoHR8SALwCAA8ACQkoHR8SALwCAAAA.Asuná:BAABLgAECn8hAAMQAAkJchHKGwDxAQAQAAkJJhDKGwDxAQAGAAYJVQoVRwAdAQAAAA==.',
At='Atheris:BAAALgAECgkJBwAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgUJCgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAgJLAABABMaAA==.',
Ba='Backerrz:BAACLgAFFH8oAAIRAAgJlQ4uJQC2AQARAAgJlQ4uJQC2AQAuAAQKfzEAAxEACQlPHFsaAIYCABEACQlPHFsaAIYCABIAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAFFAQJDQARAEUdAA==.Barathor:BAAALgAECgYJBgAAAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8uAAILAAkJ4iMiAgArAwALAAkJ4iMiAgArAwAAAA==.Bellezora:BAAALgAECgUJBQABLgAECgkJIAABAFcTAA==.Belloichi:BAAALgAECgEJAQAAAA==.Bellwynn:BAAALgAECgcJCgAAAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAACLgAFFH8IAAITAAQJOByuEwBAAQATAAQJOByuEwBAAQAuAAQKfy8AAhMACQltI6wBACcDABMACQltI6wBACcDAAAA.Bestboygrip:BAAALgAECgcJEwAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAACLgAFFH8GAAIDAAQJFREhHwDIAAADAAQJFREhHwDIAAAuAAQKfx0AAwMABwmNHqIDAEACAAMABwmNHqIDAEACABQABgmIB85QAL8AAAAA.Bigjonkillzz:BAAALgADCgEJAQAAAA==.Bigmacd:BAAALgAECgUJBQAAAA==.Bigsave:BAABLgAECn8dAAIBAAkJCA9yUQBJAQABAAkJCA9yUQBJAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8gAAIVAAUJ5BocGAAnAQAVAAUJ5BocGAAnAQAuAAQKf20AAhUACQnAIXYBALECABUACQnAIXYBALECAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.Borghild:BAAALgAECgMJAwAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn83AAMDAAkJQRv8DgCyAgADAAkJQRv8DgCyAgAWAAEJ1xZijgBDAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brick:BAAALgAFFAEJAQAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAABLgAECn8cAAIXAAgJ8RkcHgD+AQAXAAgJ8RkcHgD+AQAAAA==.',
Bu='Buckett:BAAALgAECgUJBQAAAA==.Buckfuttz:BAAALgAECggJEgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH9MAAIUAAYJ5SZMAACAAgAUAAYJ5SZMAACAAgAuAAQKfxcAAhQACQlfJngAANkDABQACQlfJngAANkDAAEuAAUUCQkkABgAPiUA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn85AAILAAkJ3BijAgDpAQALAAkJ3BijAgDpAQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJCwABLgAFFAQJGQAKABcaAA==.Changedragon:BAAALgAECgUJBQAAAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chiron:BAAALgAECgcJEgABLgAECgkJGQARALsJAA==.Chirón:BAABLgAECn8VAAIZAAcJ+QwRFgApAQAZAAcJ+QwRFgApAQAAAA==.Chiyukii:BAAALgAECgkJEQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJLgAHALMeAA==.',
Co='Coastin:BAAALgAECgMJAwABLgAECgMJBgAFAAAAAA==.Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8oAAINAAkJrxwlKQA6AgANAAkJrxwlKQA6AgAAAA==.Cowmein:BAABLgAECn8YAAMCAAgJhwtpPAAfAQACAAgJhwtpPAAfAQABAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crune:BAAALgAECgEJBQAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIaAAcJ9RksRQC3AQAaAAcJ9RksRQC3AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAcJLQAbAIQaAA==.',
['Cü']='Cürrents:BAAALgAECgEJAQAAAA==.',
Da='Dameian:BAAALgAECgEJAQAAAA==.Dapur:BAAALgADCgkJEgAAAA==.Davidmamet:BAAALgADCgIJAwAAAA==.Dayne:BAABLgAECn8hAAIUAAkJmQ8DIgCYAQAUAAkJmQ8DIgCYAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJGQAKABcaAA==.',
De='Dedvoidedge:BAAALgAECgQJBAAAAA==.Demontot:BAAALgADCgkJCgAAAA==.Derik:BAABLgAECn8dAAMNAAkJBRfPBgAuAgANAAkJBRfPBgAuAgAMAAYJZgQ6PQDYAAABLgAFFAUJHgAXAPUeAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8eAAIXAAUJ9R4yFQBjAQAXAAUJ9R4yFQBjAQAuAAQKfyUAAhcACQmHHfMdAP8BABcACQmHHfMdAP8BAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgYJCQAAAA==.',
Do='Donald:BAABLgAECn9xAAMCAAkJ3h68AQCYAgACAAkJ3h68AQCYAgABAAMJiwdCpwB5AAAAAA==.Doublea:BAABLgAECn8WAAIPAAkJ0R8oJAAGAgAPAAkJ0R8oJAAGAgAAAA==.',
Dr='Dragonchest:BAAALgAECggJEgAAAA==.Dragonista:BAAALgAECgIJBAAAAA==.Dragonscrazy:BAAALgAECgUJBQAAAA==.Dragonsfury:BAAALgAECgUJBQAAAA==.Dragonswolf:BAABLgAECn8uAAIXAAgJtRX4KQCwAQAXAAgJtRX4KQCwAQAAAA==.Dragonwing:BAAALgAECgcJCAAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAABLgAECn8ZAAMEAAkJcgxFRgARAQAEAAgJxwtFRgARAQAcAAIJ9AsbHwBYAAAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAgJKAADALAjAA==.Dregon:BAACLgAFFH8oAAIDAAgJsCN+BADaAgADAAgJsCN+BADaAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABYAAgnlIalaAKUAAAAA.Dreinara:BAABLgAECn8pAAIGAAkJSxFHBQCoAQAGAAkJSxFHBQCoAQAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Drfeelsgood:BAAALgADCgEJAQAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn80AAICAAkJeRN+BgB6AQACAAkJeRN+BgB6AQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ec='Echinopsis:BAAALgAECgYJDAAAAA==.',
Ei='Eilyn:BAABLgAECn9CAAIIAAkJthZSNwAkAgAIAAkJthZSNwAkAgAAAA==.',
El='Elena:BAAALgAECgQJBgABLgAECgkJMgADACIkAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIbAAcJMxGQIwC7AQAbAAcJMxGQIwC7AQAAAA==.Elystraeya:BAABLgAECn8iAAMaAAkJrAIP4gBzAAAaAAkJJgIP4gBzAAAdAAkJdQFiZABFAAAAAA==.',
Em='Emastoned:BAAALgAECgYJEAAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMSAAkJPR5kBAA4AgASAAgJIB9kBAA4AgARAAgJBhpSQwDRAQAAAA==.',
Fa='Fangmage:BAABLgAECn8UAAMeAAcJbQ8SCAAVAQAeAAYJhRASCAAVAQAKAAYJ2wjU0QDvAAAAAA==.Fayker:BAAALgAECggJDQAAAA==.Fazlain:BAABLgAECn8pAAINAAgJiR7LKAA7AgANAAgJiR7LKAA7AgAAAA==.',
Fe='Feldraca:BAAALgAECgEJAQAAAA==.Felnir:BAAALgAECgMJBAABLgAECgkJGQARALsJAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAUJGgAQAHoUAA==.',
Fl='Fluffydragon:BAACLgAFFH8bAAIfAAUJDRp5CwDxAAAfAAUJDRp5CwDxAAAuAAQKfyYAAx8ACQkkHDUFAMUCAB8ACQkkHDUFAMUCABwABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAABLgAECn8ZAAIbAAkJoh34AgAZAgAbAAkJoh34AgAZAgABLgAFFAMJEwANAJgeAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8mAAMBAAkJDyXGAQC8AwABAAkJDyXGAQC8AwAgAAMJGyJcHAAoAQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
['Fô']='Fôxx:BAAALgAECggJCQAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Galvvatron:BAAALgAECgYJBgAAAA==.Ganden:BAABLgAECn9DAAICAAkJXiEtBgD1AgACAAkJXiEtBgD1AgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8XAAIIAAUJthRTRwAdAQAIAAUJthRTRwAdAQAuAAQKf1IAAwgACQkVG6cKAMEBAAgACQkVG6cKAMEBAAkAAQkkA2IlAB4AAAAA.Gatelinka:BAAALgAECggJEwABLgAFFAUJGwAfAA0aAA==.Gateto:BAABLgAECn8tAAMPAAkJTiDnCQDaAgAPAAkJTiDnCQDaAgAhAAQJiBCBXgDJAAABLgAFFAUJGwAfAA0aAA==.',
Ge='Geistheiler:BAAALgAFFAIJAwAAAA==.Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gh='Ghaghlin:BAAALgAECgEJAQAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gl='Glynistann:BAAALgAECggJCQAAAA==.',
Gn='Gnomechomsky:BAAALgADCggJDAAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJDgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.Grogon:BAAALgAECgIJAgAAAA==.',
Gu='Gundox:BAAALgAECggJCQAAAA==.',
Gw='Gwenneth:BAAALgAECgUJCAAAAA==.',
['Gú']='Gúr:BAABLgAECn8aAAIYAAgJ+gckDgCiAAAYAAgJ+gckDgCiAAAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8vAAISAAkJJBbwBgDtAQASAAkJJBbwBgDtAQAAAA==.Helsreach:BAAALgAECgEJAQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.Hoshi:BAAALgAECgEJAgAAAA==.',
Hr='Hrungnir:BAABLgAFFH8FAAMgAAMJ7BqvCQCJAAAgAAIJdxavCQCJAAAYAAEJ1iMAGwBiAAAAAA==.Hruoth:BAAALgAECgEJAQAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMNAAYJ1RcshQA0AQANAAYJNBcshQA0AQAOAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn9KAAMNAAkJLBIKDgCRAQANAAkJLBIKDgCRAQAOAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
In='Inaiel:BAAALgADCgYJBgAAAA==.Instaque:BAAALgAECgUJBQAAAA==.',
Ir='Irim:BAABLgAFFH8FAAQiAAMJrg2uKABFAAARAAEJbxAIwQBIAAAiAAEJgwiuKABFAAASAAEJGBA7KABEAAAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAFFAMJAwABLgAFFAUJHgAXAPUeAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8cAAIaAAcJzBWQOABCAQAaAAcJzBWQOABCAQAuAAQKfyQAAxoACAmYIeARAPACABoACAmYIeARAPACAB0AAglECPthAFoAAAAA.Izlaar:BAAALgAECgUJDAAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIXAAkJbBIYMwB/AQAXAAkJbBIYMwB/AQAAAA==.Jacob:BAAALgAECgQJEQAAAA==.Jadedbabe:BAABLgAECn8UAAINAAcJUgr+HgDsAAANAAcJUgr+HgDsAAAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJGQAKABcaAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Johncena:BAAALgAECgYJBgAAAA==.Joppa:BAAALgAECgMJBQABLgAFFAkJMQAbAD8ZAA==.Joyvimon:BAABLgAECn8WAAIaAAkJLg8oCgBaAQAaAAkJLg8oCgBaAQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIjAAgJdwvWlQA8AQAjAAgJdwvWlQA8AQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxuHCQBYAQAEAAYJyxuHCQBYAQAcAAIJEgemBgClAAAuAAQKfxUAAxwACQkBIL4OAO8BAAQABwmCGvgXABMCABwABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kilysta:BAAALgAECgEJAgAAAA==.Kimhera:BAAALgADCgMJAwAAAA==.Kiy:BAAALgAECgkJEQAAAA==.',
Kn='Knìghtmare:BAAALgAECgIJAgAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAABLgAECn8bAAIRAAkJwwPCmgAIAQARAAkJwwPCmgAIAQAAAA==.Kronas:BAAALgAECggJDwAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIaAAkJfxu3PAABAgAaAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8aAAQQAAUJehRXHgBlAQAQAAUJ5hJXHgBlAQAGAAIJVhSpDACZAAAbAAIJfADAQQAyAAAuAAQKfx8ABAYACQl+G+cNAIgCAAYACQl+G+cNAIgCABAABAlUBrE/ALEAABsAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAUJGgAQAHoUAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8sAAIGAAgJIhlCBgD3AQAGAAgJIhlCBgD3AQAuAAQKfzQAAwYACQnOIKYDAB8DAAYACQnOIKYDAB8DABsAAwktCyJvAGUAAAAA.Leomoon:BAAALgAECgMJCAAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMGAAYJqxthIAC/AQAGAAYJqxthIAC/AQAQAAUJGhLrPwAMAQAAAA==.Lewval:BAAALgAECgEJAgAAAA==.',
Li='Lickytung:BAAALgAECgEJAQAAAA==.Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIRAAgJzAemjAAhAQARAAgJzAemjAAhAQAAAA==.Linaetila:BAAALgAECgQJBAAAAA==.Linthsong:BAABLgAECn8aAAIKAAgJRREXDgCDAQAKAAgJRREXDgCDAQABLgAECgkJQAAGAI8YAA==.Lionature:BAAALgAECgUJBQAAAA==.Lionknite:BAACLgAFFH8XAAIjAAQJuxFBMgALAQAjAAQJuxFBMgALAQAuAAQKfzUAAiMACQlNIAAEAJICACMACQlNIAAEAJICAAAA.Lionshame:BAAALgAECgYJBgAAAA==.Lionstocks:BAAALgADCgEJAQAAAA==.Liontabu:BAAALgAECgcJDAAAAA==.Liorii:BAAALgAECgEJBAAAAA==.Liteshocklet:BAAALgAECgIJAwABLgAFFAUJGgAQAHoUAA==.Littledung:BAAALgAECgYJEAAAAA==.Liwellan:BAAALgAECgcJDQAAAA==.',
Lo='Looting:BAABLgAECn8yAAIkAAkJ2BZjAQCaAQAkAAkJ2BZjAQCaAQAAAA==.Lostdragon:BAAALgADCgcJBwAAAA==.Loving:BAAALgAECgIJBQAAAA==.',
Lu='Lucky:BAAALgAECgEJAgAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8JAAIBAAMJgwgeSwCQAAABAAMJgwgeSwCQAAAuAAQKfyEAAwEACAnuCwhdADsBAAEACAnuCwhdADsBACAAAQkoAoZlABkAAAAA.',
Ma='Macack:BAAALgAECgQJBAAAAA==.Mageko:BAAALgAECgEJBgAAAA==.Mageroni:BAAALgAECgcJCAABLgAECgkJGAAJADYUAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Magictoke:BAAALgAECgEJAQAAAA==.Makarion:BAABLgAECn8WAAINAAgJxQtyegBLAQANAAgJxQtyegBLAQAAAA==.Malvina:BAABLgAFFH8GAAIIAAUJ6grvJAD2AAAIAAUJ6grvJAD2AAAAAA==.Maoli:BAABLgAECn8UAAMIAAQJLhUA/wC5AAAIAAMJGhUA/wC5AAAJAAQJHguPaACUAAAAAA==.Marcelius:BAAALgAECgEJAgAAAA==.Markeleth:BAAALgAECgYJBgABLgAECgkJQwAHAHMcAA==.Marohen:BAAALgADCgYJBgAAAA==.Matsumoto:BAAALgAECgEJAwAAAA==.Mauka:BAABLgAECn8tAAMBAAgJUg2mRgB1AQABAAgJUg2mRgB1AQACAAYJQBTdOABUAQAAAA==.Mauzer:BAAALgAECgQJBwABLgAECgkJPgAdAAIcAA==.Mauzii:BAAALgAECgIJAgABLgAECgkJPgAdAAIcAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIjAAkJUh4UMAB3AgAjAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIjAAgJQgZUtwAJAQAjAAgJQgZUtwAJAQAAAA==.',
Me='Meathoof:BAEALgAECgkJAQABLgAFFAUJJAAlAA4iAA==.Melliah:BAAALgAECggJAwAAAA==.Mes:BAABLgAECn8jAAIhAAkJghvEGwADAgAhAAkJghvEGwADAgAAAA==.Metatrøn:BAAALgADCgkJDwAAAA==.',
Mi='Mimmi:BAABLgAECn8aAAIPAAUJOxnTDQBSAQAPAAUJOxnTDQBSAQABLgAECgkJPgAdAAIcAA==.Mishri:BAACLgAFFH8VAAIaAAUJCSO/JQCWAQAaAAUJCSO/JQCWAQAuAAQKfzQAAhoACQn3JIIEAD8DABoACQn3JIIEAD8DAAAA.',
Mo='Monbonestorm:BAAALgAFFAIJAgABLgAFFAIJBgAaAL0PAA==.Mooittooit:BAAALgAECgcJCgAAAA==.Moonsorrow:BAAALgAECgEJAgAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8+AAMdAAkJAhxhCgCCAgAdAAkJAhxhCgCCAgAmAAIJURqbLgBIAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMIAAYJPwjd/gC5AAAIAAYJPwjd/gC5AAAHAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgAECgIJAgAAAA==.Mywifesaidno:BAAALgAECgMJAwAAAA==.',
Na='Nakabeam:BAABLgAECn8vAAIaAAkJIhZ6NAD0AQAaAAkJIhZ6NAD0AQAAAA==.Nakatwin:BAABLgAECn8YAAIaAAcJJhXmWACXAQAaAAcJJhXmWACXAQABLgAECgkJLwAaACIWAA==.Naklek:BAABLgAECn8hAAMgAAgJBh6TBgCOAgAgAAgJBh6TBgCOAgAYAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8bAAINAAgJcBQVHwCIAQANAAgJcBQVHwCIAQAuAAQKfyMAAw0ACQmtH5sOAMYCAA0ACQmtH5sOAMYCAA4ABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCgAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8pAAMGAAkJTgoLLwBWAQAGAAkJTgoLLwBWAQAbAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgYJCAABLgAECgkJNgAKAC0kAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgAECgEJAgAAAA==.',
Op='Ophiuchus:BAABLgAECn8ZAAIRAAkJuwmLZQBzAQARAAkJuwmLZQBzAQAAAA==.',
Or='Orcdung:BAAALgAECgQJBQAAAA==.',
Os='Ostpeppar:BAAALgAECgUJCQAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8YAAQJAAkJNhRPNwBxAQAJAAgJuBNPNwBxAQAHAAgJeA/0HgARAQAIAAEJcwNuyQEfAAAAAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgAECgcJDgABLgAFFAUJHgAXAPUeAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAFFAEJAQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgAECgMJBQAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8uAAMIAAkJwBZ9QgD/AQAIAAkJwBZ9QgD/AQAJAAQJzgh3ZgCbAAAAAA==.Philster:BAAALgAFFAIJBAAAAA==.',
Pi='Pilfering:BAABLgAECn8cAAIRAAYJZgxNFADUAAARAAYJZgxNFADUAAABLgAECgkJMgAkANgWAA==.',
Pl='Playstore:BAAALgAECgUJBQAAAA==.Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8kAAIGAAkJRRX2GAAEAgAGAAkJRRX2GAAEAgAAAA==.Punchem:BAAALgAECgQJBAABLgAECgkJJgABAA8lAA==.Punchyjen:BAAALgADCgQJBAABLgAECgYJCAAFAAAAAA==.Punchykicky:BAAALgAECgMJAwABLgAECgkJQwAHAHMcAA==.Purex:BAABLgAECn8dAAIkAAkJKQYwCgCSAQAkAAkJKQYwCgCSAQAAAA==.',
Py='Pyria:BAAALgAECgYJCgAAAA==.',
['Pé']='Pérrywinklé:BAABLgAFFH8GAAIQAAMJCQjSIACLAAAQAAMJCQjSIACLAAAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIHAAgJ4BoNDgDjAQAHAAgJ4BoNDgDjAQAAAA==.Rathus:BAACLgAFFH8NAAIRAAQJRR08GgBSAQARAAQJRR08GgBSAQAuAAQKfykAAhEACAm/He40AAUCABEACAm/He40AAUCAAAA.Rawdata:BAACLgAFFH8QAAMnAAMJpQ2WEAC+AAAnAAMJpQ2WEAC+AAAPAAMJwApKWgCYAAAuAAQKfykAAycACQk5FYIRAJwBACcACQk5FYIRAJwBAA8ACAkvD1RCAHgBAAEuAAUUBAkIAB0A6xYA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAINAAgJqRetPQC4AQANAAgJqRetPQC4AQABLgAECgkJLAAJAPoeAA==.Rebeka:BAABLgAECn8sAAIJAAkJ+h4nCAAJAwAJAAkJ+h4nCAAJAwAAAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgkJIQAUAJkPAA==.Reniel:BAAALgAECgUJBgABLgAECgkJOQAHACQVAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgcJCQABLgAFFAQJBQAbABMQAA==.Reverendlion:BAABLgAECn8WAAIbAAgJ7BbbIAC/AQAbAAgJ7BbbIAC/AQAAAA==.',
Ri='Rifleburs:BAAALgAECgEJBAAAAA==.Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.Rollwitpunch:BAAALgADCgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.Rule:BAAALgAECggJCQAAAA==.',
Ry='Ryblade:BAABLgAFFH8NAAIIAAQJXgmedwDGAAAIAAQJXgmedwDGAAABLgAFFAYJJAAIAOESAA==.',
Sa='Saiko:BAABLgAECn8VAAIaAAcJpRKnDQArAQAaAAcJpRKnDQArAQABLgAFFAUJGwAiAEEOAA==.Sainthealz:BAAALgAECgEJBAAAAA==.Saladcake:BAABLgAECn81AAIKAAkJfBcqCAD7AQAKAAkJfBcqCAD7AQAAAA==.Salleane:BAACLgAFFH8VAAIIAAUJ2BHLKQDjAAAIAAUJ2BHLKQDjAAAuAAQKfxoAAggACQmOFTNeAMkBAAgACQmOFTNeAMkBAAAA.Samgompers:BAAALgADCgIJAgAAAA==.Sampal:BAABLgAECn9DAAMHAAkJcxwYCABYAgAHAAgJjx4YCABYAgAIAAEJqw1EewFAAAAAAA==.Sampriest:BAABLgAECn81AAMGAAkJOiFlBQAlAwAGAAkJOiFlBQAlAwAQAAEJpxBUewAwAAABLgAECgkJQwAHAHMcAA==.Samwield:BAECLgAFFH8kAAIlAAUJDiLIFQBdAQAlAAUJDiLIFQBdAQAuAAQKf0kABCUACQkmIt4FANICACUACQkmIt4FANICACQAAwlCGEsTAM0AACgAAQnUClgmACsAAAAA.Sanchoe:BAAALgAFFAEJAQAAAA==.Sandhell:BAAALgADCgMJAwAAAA==.Sanjana:BAAALgAECgQJBgAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAgAAAA==.',
Se='Segura:BAAALgAECgMJAwAAAA==.Seirei:BAAALgADCgEJAQABLgAECgkJGQAaAH8bAA==.Seireitei:BAABLgAECn80AAMPAAkJpRtUFACpAgAPAAkJpRtUFACpAgAhAAEJIAZBuwAiAAAAAA==.Selaheal:BAABLgAECn9BAAIbAAkJ3hfjEwAwAgAbAAkJ3hfjEwAwAgAAAA==.Seraath:BAACLgAFFH8oAAImAAgJwRpwAQDSAQAmAAgJwRpwAQDSAQAuAAQKfyYAAyYACQn3IZAAAGQDACYACQn3IZAAAGQDABoAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.Serius:BAAALgAECgMJAwAAAA==.',
Sh='Shadowskull:BAAALgAECgUJCwAAAA==.Shadowsun:BAAALgAECgEJAQAAAA==.Shadowydream:BAAALgAECgQJBQAAAA==.Shadwkllr:BAABLgAECn8YAAMhAAYJ6xMOFgCTAAAhAAYJ6xMOFgCTAAAPAAIJ3g5muQBaAAAAAA==.Shamloo:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Shangdi:BAAALgAECgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8XAAISAAYJQiBFCADKAQASAAYJQiBFCADKAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAABLgAFFH8IAAIdAAQJ6xbnDgAtAQAdAAQJ6xbnDgAtAQAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
Ss='Ssteroidss:BAAALgAECgIJCAAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stepfist:BAAALgAFFAMJAwABLgAFFAQJGQAKABcaAA==.Stergertha:BAAALgAECgEJAQABLgAFFAMJBQAhAM0QAA==.Stersèbuk:BAAALgAECgEJAQABLgAFFAMJBQAhAM0QAA==.Stervana:BAACLgAFFH8KAAIEAAQJjxp5KwAYAQAEAAQJjxp5KwAYAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAEuAAUUAwkFACEAzRAA.Stickytoes:BAAALgADCgYJBgAAAA==.Stilettoes:BAAALgADCgIJAgAAAA==.Stormyknight:BAABLgAECn8sAAMfAAkJ3g5EFgBqAQAfAAkJ3g5EFgBqAQAcAAcJOwtKEwDWAAAAAA==.Stærk:BAACLgAFFH8FAAIhAAMJzRDfMwDAAAAhAAMJzRDfMwDAAAAuAAQKfxQAAiEABwluF9ImALUBACEABwluF9ImALUBAAEuAAUUAwkFACEAzRAA.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAFFAIJAgAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIKAAMJmxJkLwD5AAAKAAMJmxJkLwD5AAABLgAFFAgJKwALAMciAA==.Suswar:BAACLgAFFH8rAAILAAgJxyL9AgBdAgALAAgJxyL9AgBdAgAuAAQKfzAAAgsACQnIJJoAALgDAAsACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn9KAAMfAAkJEQsGGwArAQAfAAgJuwgGGwArAQAEAAkJ8QUwRAAZAQAAAA==.Suvulark:BAAALgAECgIJAgAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.Swordsmyth:BAAALgAECgUJBQAAAA==.',
Ta='Tacostand:BAACLgAFFH8bAAIaAAYJKhXHMABiAQAaAAYJKhXHMABiAQAuAAQKfzIAAhoACQlNIOUHAEwDABoACQlNIOUHAEwDAAAA.Tamarlane:BAAALgAECgEJAQAAAA==.Tatoo:BAACLgAFFH8TAAINAAMJmB51KQD/AAANAAMJmB51KQD/AAAuAAQKf1UAAg0ACQlyJJEEAEcDAA0ACQlyJJEEAEcDAAAA.',
Te='Teeice:BAABLgAECn8iAAIkAAkJdRPEBgD4AQAkAAkJdRPEBgD4AQAAAA==.Teo:BAABLgAECn8nAAIbAAkJrRUhHQDcAQAbAAkJrRUhHQDcAQAAAA==.Tereus:BAAALgAECggJCAAAAA==.Terian:BAAALgAECgkJCQAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIhAAkJAhFqOgBMAQAhAAkJAhFqOgBMAQAAAA==.That:BAAALgAECgEJAgAAAA==.Thekan:BAABLgAECn8bAAIdAAkJlhRXFgDXAQAdAAkJlhRXFgDXAQAAAA==.Theriot:BAACLgAFFH8GAAMIAAMJuRC1bQDVAAAIAAMJuRC1bQDVAAAHAAIJmAKDFgBHAAAuAAQKfzEABAgACQnbHXo6ABkCAAgACQnbHXo6ABkCAAcABwlWC9gpAMsAAAkAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8fAAIPAAkJkwshUQBuAQAPAAkJkwshUQBuAQAAAA==.Thypriest:BAAALgAECgEJAQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgkJCgAAAA==.Tikidragoona:BAAALgAECgQJBgAAAA==.Timberdoodle:BAAALgAECgMJAwAAAA==.Timtamslam:BAAALgAECgYJDAAAAA==.Tinkerspell:BAABLgAECn8gAAIBAAkJVxNILwDmAQABAAkJVxNILwDmAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECgkJIAABAFcTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
Tl='Tlitlitzin:BAAALgAECgQJCAAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAIVAAQJVSHqIQDbAAAVAAQJVSHqIQDbAAABLgAFFAgJKwALAMciAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAInAAQJYQcKDQDwAAAnAAQJYQcKDQDwAAAuAAQKfxoAAicACAkrFG0KACoCACcACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgQJBwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Torvii:BAAALgADCgYJBgAAAA==.Totec:BAAALgAECgkJCgAAAA==.',
Tr='Tralanoth:BAAALgAECgYJBwAAAA==.Treatimus:BAAALgADCgMJAwABLgAECgkJQwAbAH8kAA==.Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAABLgAECn8gAAMOAAYJDwlvBgCoAAAOAAYJDwlvBgCoAAANAAMJewLd/wBfAAAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8ZAAIIAAgJMwixMwBIAQAIAAgJMwixMwBIAQAuAAQKfyUAAggACQl+Fd8wAF8CAAgACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twevara:BAAALgADCgEJAQAAAA==.Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tyrannos:BAAALgAECggJCwAAAA==.Tystraz:BAAALgAECgYJDwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Unclebuck:BAAALgAECgQJBwAAAA==.Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAEBLgAFFH8HAAIjAAMJMxuAOAD1AAAjAAMJMxuAOAD1AAABLgAFFAUJJAAlAA4iAA==.',
Va='Vallo:BAAALgAECgQJBQAAAA==.Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vecna:BAAALgAECgQJBgABLgAECgYJCAAFAAAAAA==.Vector:BAAALgAECgYJCAAAAA==.Veggießurger:BAAALgADCgcJBwAAAA==.Velata:BAABLgAECn8cAAIKAAUJWw9o4ADaAAAKAAUJWw9o4ADaAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJDwAAAA==.Verite:BAABLgAECn8bAAMjAAcJzQOVFwGPAAAjAAcJxwKVFwGPAAAZAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIXAAkJ9RtlEwBWAgAXAAkJ9RtlEwBWAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voidedge:BAABLgAECn8vAAQiAAkJ6hARBgDsAAARAAgJHBAYdgBxAQAiAAYJZAsRBgDsAAASAAUJBxGGHQC8AAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vr='Vritzz:BAAALgADCgkJCQAAAA==.',
Vy='Vynivar:BAAALgAECgEJAgAAAA==.Vynlan:BAAALgAECgQJBAABLgAFFAgJKAADALAjAA==.',
Wa='Waimea:BAAALgAECgQJBQAAAA==.Warlockboi:BAAALgAECgYJBwAAAA==.',
We='Wes:BAABLgAECn89AAIkAAkJvRqHAwB4AgAkAAkJvRqHAwB4AgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willferral:BAAALgAECgQJBAAAAA==.Willybcastin:BAACLgAFFH8GAAIpAAMJqR3qAQADAQApAAMJqR3qAQADAQAuAAQKfxsAAikABgnuI5QBAKEBACkABgnuI5QBAKEBAAEuAAUUCAkrACMAwCMA.Willybwankin:BAACLgAFFH8rAAIjAAgJwCObAABrAgAjAAgJwCObAABrAgAuAAQKfykAAiMACQkxJsoAAOEDACMACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8VAAIHAAkJsgv3IQD4AAAHAAkJsgv3IQD4AAAAAA==.',
Wt='Wtsportal:BAAALgAFFAIJAgAAAA==.',
Wy='Wylalena:BAAALgAECgMJAwAAAA==.Wyvern:BAABLgAECn8gAAIRAAkJFA71UgCjAQARAAkJFA71UgCjAQAAAA==.',
Xa='Xanstar:BAAALgAECgEJAQAAAA==.Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Ye='Yeela:BAAALgADCgYJBgAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAACLgAFFH8GAAMBAAMJzANDUwB3AAABAAMJzANDUwB3AAACAAEJ8wFYVgApAAAuAAQKfxsAAwEACAkAGm4aAHICAAEACAkAGm4aAHICAAIAAgloAkGqABQAAAAA.Zalarian:BAAALgAECgYJBwABLgAECgkJcQAKAEYjAA==.Zalmage:BAABLgAECn9xAAMKAAkJRiMfCgApAwAKAAkJRiMfCgApAwApAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgAECgQJAwAAAA==.Zeseroth:BAACLgAFFH8nAAIIAAgJMx7+DAAQAgAIAAgJMx7+DAAQAgAuAAQKfycAAggACQmkIywDAKMDAAgACQmkIywDAKMDAAAA.Zeserotho:BAAALgAFFAEJAQAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIGAAQJ1SQuDQB3AQAGAAQJ1SQuDQB3AQAuAAQKfyUAAwYACQndIBEGAO4CAAYACQndIBEGAO4CABsABAllEzxyAF0AAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
['Éi']='Éireann:BAAALgAECggJCQAAAA==.',
['Ðc']='Ðced:BAAALgAECgEJAQABLgAFFAQJGQAKABcaAA==.',
['Ön']='Önion:BAAALgADCgUJBAAAAA==.',
['Øm']='Ømen:BAAALgADCgQJBAAAAA==.',
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
