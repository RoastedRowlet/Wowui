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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Warrior-Fury','Warrior-Arms','Mage-Frost','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Shaman-Elemental','Mage-Arcane','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Vengeance','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Hunter-Marksmanship','Paladin-Protection','Warlock-Affliction','Paladin-Holy','Mage-Fire','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJDAABLgAFFAMJAwABAAAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Adipocere:BAAALgAECgYJBgABLgAFFAMJCQACAAoPAA==.Admaris:BAABLgAECn8WAAIDAAYJFB1mOwC3AQADAAYJFB1mOwC3AQAAAA==.Adordron:BAAALgAECgEJAQAAAA==.',
Ag='Age:BAABLgAECn8nAAMEAAkJzhx1EQBXAgAEAAkJzhx1EQBXAgAFAAMJnw0QJwC2AAAAAA==.Agni:BAACLgAFFH8hAAIGAAcJSBtOFQADAgAGAAcJSBtOFQADAgAuAAQKfyYAAgYACQnnI6gEALYDAAYACQnnI6gEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8vAAIEAAkJlBdsFwAfAgAEAAkJlBdsFwAfAgAAAA==.',
Al='Alavendis:BAABLgAECn8VAAIHAAcJRhy7QwClAQAHAAcJRhy7QwClAQABLgAECgQJBgABAAAAAA==.Alexá:BAAALgAECgUJCQABLgAECgcJIwAIAEQhAA==.Almight:BAAALgAECgMJBwAAAA==.Alnasham:BAACLgAFFH8VAAMJAAYJkxumAADMAQAJAAUJQh2mAADMAQAKAAIJUBiYMQCnAAAuAAQKfyoAAwkACAmUIjYHAEICAAkACAmUIjYHAEICAAoAAQmUBvCkACMAAAAA.Alphashadow:BAAALgAECgQJCgAAAA==.Altria:BAAALgAECgkJBQAAAA==.Alvoka:BAABLgAECn8cAAMGAAkJyhOVagAAAgAGAAkJyhOVagAAAgALAAQJpQ9rCQDZAAAAAA==.',
Am='Amarillos:BAAALgAECgkJEAAAAA==.Amarillys:BAACLgAFFH8UAAIMAAUJGB5eBgC/AQAMAAUJGB5eBgC/AQAuAAQKfyMAAwwACQlDHRkOAHoCAAwACQlDHRkOAHoCAA0AAQnYFJZjADEAAAAA.Ambrotos:BAABLgAECn8WAAIOAAgJ2wgPbABSAQAOAAgJ2wgPbABSAQAAAA==.Amither:BAAALgAECgYJBgAAAA==.Ammutseba:BAABLgAECn8pAAMPAAkJFhrgBwDmAQAPAAkJFhrgBwDmAQAHAAEJXQr1CgElAAAAAA==.Amperage:BAAALgAECgEJAQAAAA==.',
An='Anfall:BAABLgAECn8UAAIJAAkJhRmfBQByAgAJAAkJhRmfBQByAgAAAA==.Angermeier:BAABLgAECn8sAAIEAAkJ+BvqDwBnAgAEAAkJ+BvqDwBnAgAAAA==.Angryjeid:BAAALgAECgYJBgABLgAFFAIJAwABAAAAAA==.Angrylady:BAAALgAECgEJAwAAAA==.Anika:BAAALgADCgQJBAAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Arayvia:BAAALgADCgkJCgAAAA==.Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAgAAAA==.Arg:BAAALgAECgYJCAAAAA==.Arowin:BAABLgAECn8aAAIQAAgJuhPlIgCYAQAQAAgJuhPlIgCYAQAAAA==.Arrielle:BAAALgAECgYJBgAAAA==.Arthaniis:BAACLgAFFH8PAAIKAAQJ3B0HFABPAQAKAAQJ3B0HFABPAQAuAAQKfxwAAgoACAnMIP8IAAIDAAoACAnMIP8IAAIDAAAA.',
As='Asdar:BAAALgADCgEJAQAAAA==.Asmonremix:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgYJDQAAAA==.',
Au='Audideath:BAABLgAECn8XAAMRAAYJGxotfwBQAQARAAYJQBktfwBQAQASAAQJSBTRCwD+AAAAAA==.Audry:BAAALgADCgcJCQAAAA==.Augtistic:BAABLgAECn8bAAMTAAkJShJIHQDcAQATAAkJShJIHQDcAQAUAAYJcwIJKwDFAAABLgAFFAMJBgARACESAA==.Auurdeath:BAAALgAECgcJDQAAAA==.',
Av='Avidswolf:BAABLgAECn8pAAIGAAgJKRADfgBhAQAGAAgJKRADfgBhAQAAAA==.Avãcyn:BAABLgAECn8oAAMFAAgJ7wr7JQAiAQAFAAgJ7wr7JQAiAQAEAAYJSwYGXADIAAAAAA==.',
Aw='Aw:BAACLgAFFH8XAAIVAAgJiyJdAAC0AgAVAAgJiyJdAAC0AgAuAAQKfxgAAhUACAmeJo0BAJEDABUACAmeJo0BAJEDAAAA.Awppenheimer:BAABLgAECn8hAAMWAAkJ6x2OEADKAQAXAAgJFRz5LwAMAgAWAAYJdRyOEADKAQAAAA==.',
Ax='Ax:BAECLgAFFH8YAAMRAAYJwA82MQB0AQARAAUJwA82MQB0AQAYAAEJAAAlVAAAAAAuAAQKfxwAAhEABwmMHNVeAJgBABEABwmMHNVeAJgBAAAA.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAABLgAFFH8JAAIHAAYJbww5KwBNAQAHAAYJbww5KwBNAQAAAA==.',
Ba='Babycarrots:BAAALgAECgcJCAAAAA==.Baconz:BAABLgAECn8cAAMKAAkJPxRwJADtAQAKAAkJPxRwJADtAQAZAAEJ/QI70wAiAAAAAA==.Bakeon:BAABLgAECn8mAAMZAAkJGxaIIwAfAgAZAAkJGxaIIwAfAgAKAAMJYAQidABxAAAAAA==.Bakkaz:BAAALgADCgYJBgAAAA==.Baldozhi:BAAALgAECgYJCwAAAA==.Balyndis:BAAALgADCgYJBgAAAA==.Bangbang:BAAALgAFFAIJAgAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAABLgAECn8WAAMQAAUJOBEwPAAEAQAQAAUJOBEwPAAEAQADAAQJTxZaYQD/AAAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECggJHQAaAEoSAA==.Beardcheese:BAAALgAECgIJAQAAAA==.Bearington:BAAALgAECgEJAQAAAA==.Beni:BAAALgAFFAIJAgAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAACLgAFFH8OAAIbAAUJPQ+7IwAIAQAbAAUJPQ+7IwAIAQAuAAQKfyEAAxsACAlpF+0bALQBABwABgk6HSYdAPEBABsACAnsEu0bALQBAAAA.',
Bi='Bigdaddy:BAAALgADCgkJCQAAAA==.Bink:BAABLgAECn8ZAAIIAAkJ9xo1BADcAgAIAAkJ9xo1BADcAgAAAA==.Birblock:BAABLgAFFH8QAAMXAAUJjiE9JQCBAQAXAAUJjiE9JQCBAQAWAAEJWQvOIgBFAAABLgAFFAkJMwAIAKsjAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAABLgAECn8lAAIHAAcJwgkTgwD9AAAHAAcJwgkTgwD9AAAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAABLgAECn8ZAAMdAAkJCAmEUQDxAAAdAAgJEgeEUQDxAAAbAAIJZxhGegBFAAAAAA==.Blãckheart:BAAALgAECgEJAQAAAA==.',
Bo='Bobbo:BAAALgAECgYJDQAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Bolterguy:BAAALgADCgkJCQAAAA==.Boomerss:BAAALgADCgEJAQAAAA==.Boomin:BAAALgAECggJDgAAAA==.',
Br='Braass:BAAALgAECgQJCAABLgAECgUJFgAQADgRAA==.Breachnclear:BAAALgAECgYJCAAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8mAAIbAAkJdRpFEgAQAgAbAAkJdRpFEgAQAgAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgAECgUJCQABLgAECggJIQACAP4YAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8fAAIZAAkJmCB+CAAUAwAZAAkJmCB+CAAUAwAAAA==.Brutechaos:BAAALgADCgQJBAABLgAECgkJHwAZAJggAA==.Bruteflappy:BAAALgADCgkJCQABLgAECgkJHwAZAJggAA==.',
Bu='Buffygirl:BAABLgAECn8bAAMTAAgJ8RW2IgCqAQATAAgJ8RW2IgCqAQAeAAUJbw1mKwB1AAAAAA==.Bustle:BAAALgADCgkJCQAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECgkJEgAAAA==.',
['Bå']='Båne:BAABLgAECn8oAAIHAAgJlg2vZABEAQAHAAgJlg2vZABEAQAAAA==.',
Ca='Carnal:BAAALgADCgYJCQAAAA==.Casini:BAAALgADCgMJAwAAAA==.Caydened:BAAALgAECgQJBwABLgAECggJJQAOAN8dAA==.Cazic:BAAALgAECgYJEgAAAA==.',
Ce='Cedren:BAACLgAFFH8IAAIHAAMJlhmnUQDWAAAHAAMJlhmnUQDWAAAuAAQKfxkAAgcACQnbHfEdAJ4CAAcACQnbHfEdAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIHAAcJsyKpIQCHAgAHAAcJsyKpIQCHAgAAAA==.Certified:BAAALgAECgYJCAAAAA==.',
Ch='Chalix:BAAALgAECgEJAQAAAA==.Cheapheal:BAACLgAFFH8JAAIQAAQJPhmRFwAwAQAQAAQJPhmRFwAwAQAuAAQKfzkAAxAACQnXJLsDABoDABAACQnXJLsDABoDAAMABglWGUEyAMIBAAAA.Cheaptide:BAAALgAECgkJDAAAAA==.Cheburashka:BAACLgAFFH8bAAIKAAgJ9x5nAgCOAgAKAAgJ9x5nAgCOAgAuAAQKfxcAAgoACAnNIhAPALYCAAoACAnNIhAPALYCAAAA.Chewymentos:BAABLgAECn8XAAMOAAcJjhNgVQCLAQAOAAcJjhNgVQCLAQAfAAEJKQEuQQAMAAABLgAECggJLwAgALMMAA==.Chimerabob:BAAALgAECgYJDwAAAA==.Chunkyhunter:BAAALgAECgYJBgABLgAFFAUJEQAcAMIcAA==.Chunkymonkey:BAACLgAFFH8RAAMcAAUJwhw5DQBAAQAcAAUJwhw5DQBAAQAbAAIJGA65HACKAAAuAAQKfx8AAxwACAlKIS4LAMcCABwACAlKIS4LAMcCABsABQlxGuw9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cj='Cjpriestly:BAAALgAECgEJAQAAAA==.',
Cl='Clappncheeks:BAABLgAECn8nAAIIAAgJIhwQDwAuAgAIAAgJIhwQDwAuAgAAAA==.Claudefrollo:BAABLgAECn8mAAIQAAgJQRMtIQCkAQAQAAgJQRMtIQCkAQAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corlem:BAAALgAECggJCwAAAA==.Corrüpt:BAABLgAECn8VAAMhAAgJVhpGBQAXAgAhAAgJVhpGBQAXAgAXAAYJ4xWzegA5AQAAAA==.',
Cr='Crimsa:BAABLgAECn88AAIhAAkJDQlNCwCHAQAhAAkJDQlNCwCHAQAAAA==.Crimsongost:BAAALgAECgQJBwAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Crocs:BAAALgAECggJCAAAAA==.Cryogen:BAABLgAECn8ZAAIQAAgJQiBuGQDoAQAQAAgJQiBuGQDoAQAAAA==.',
Cs='Cs:BAABLgAECn8pAAIbAAkJ1yLSAwBSAwAbAAkJ1yLSAwBSAwAAAA==.',
Cu='Curufin:BAAALgAECgUJCwAAAA==.',
Da='Daddysmooth:BAAALgAECgYJCAAAAA==.Daemon:BAACLgAFFH8KAAIRAAQJHxtqPABYAQARAAQJHxtqPABYAQAuAAQKfzQAAhEACQnPI0kFAEcDABEACQnPI0kFAEcDAAAA.Daemonproph:BAABLgAECn8jAAIVAAgJOxRSFgC1AQAVAAgJOxRSFgC1AQAAAA==.Dakini:BAABLgAECn8ZAAIiAAcJWiSNEQBzAgAiAAcJWiSNEQBzAgAAAA==.Daktaklakpak:BAABLgAFFH8NAAQOAAMJKRyEYACqAAAOAAIJeR6EYACqAAAIAAIJlxnvIAClAAAfAAEJihdJLgBAAAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8mAAIgAAkJ1B9WBADDAgAgAAkJ1B9WBADDAgAAAA==.Dangerruss:BAABLgAECn8dAAIgAAkJHRKBEgCGAQAgAAkJHRKBEgCGAQAAAA==.Dangyy:BAAALgADCgMJAwAAAA==.Darkhaven:BAAALgAECgYJCAAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAACLgAFFH8YAAIjAAUJOCGGAACJAQAjAAUJOCGGAACJAQAuAAQKfx8AAyMACAn1HSABAMACACMACAn1HSABAMACAAYABAkrCGYZAcwAAAAA.Dasmonkey:BAAALgAECgIJAgAAAA==.Daxos:BAABLgAECn8mAAIGAAkJ9BiHSwBUAgAGAAkJ9BiHSwBUAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJEwAAAA==.Deelahn:BAABLgAECn8cAAMMAAgJrAprLwA7AQAMAAgJrAprLwA7AQANAAEJXABxiwAGAAAAAA==.Demideudle:BAAALgAECgEJAQAAAA==.Demonicchoas:BAABLgAECn9HAAMWAAkJiSAaAQAmAwAWAAgJJyIaAQAmAwAXAAcJAxwhIgBMAgAAAA==.Denagorn:BAACLgAFFH8PAAMCAAcJSBasDQC9AQACAAcJIQ6sDQC9AQAgAAQJABbmBAAnAQAuAAQKfzwAAgIACQluHRQYANgCAAIACQluHRQYANgCAAEuAAUUCAkkABEArxYA.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAABLgAECn8WAAIDAAkJ4B8CCAApAwADAAkJ4B8CCAApAwAAAA==.Deutzfr:BAABLgAECn8fAAMHAAcJUh4TMADwAQAHAAcJUh4TMADwAQAPAAUJLw27GAC9AAAAAA==.',
Di='Dizzleman:BAAALgAECgkJCwAAAA==.',
Do='Dominant:BAABLgAECn8uAAIGAAkJViD+EwDMAgAGAAkJViD+EwDMAgAAAA==.Dooma:BAABLgAFFH8MAAMXAAgJ8BGxGQCwAQAXAAcJ4hGxGQCwAQAhAAIJSxPrCgCkAAAAAA==.Dorgie:BAAALgAFFAIJAwABLgAFFAIJBgAaAPoaAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIGAAgJSiHeIQDsAgAGAAgJSiHeIQDsAgAAAA==.',
Dr='Draco:BAAALgAECgUJBQAAAA==.Drag:BAAALgAECgQJCwAAAA==.Dragnaught:BAAALgAECgEJAQABLgAECgQJCwABAAAAAA==.Dragon:BAABLgAECn8YAAIeAAkJFhBdFgDoAQAeAAkJFhBdFgDoAQAAAA==.Dragowolf:BAAALgADCgYJBgAAAA==.Drbob:BAAALgAECgQJBgAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAABLgAFFH8GAAIaAAMJNBlmIgDoAAAaAAMJNBlmIgDoAAABLgAFFAYJFAAiAM0jAA==.Drock:BAABLgAECn8pAAIHAAkJ8R+aCwDaAgAHAAkJ8R+aCwDaAgAAAA==.Druidgale:BAABLgAECn8jAAIDAAkJowvkUAA4AQADAAkJowvkUAA4AQAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAABLgAECn8aAAIbAAkJ1xQcFQD0AQAbAAkJ1xQcFQD0AQAAAA==.Drybonez:BAABLgAECn8mAAMKAAkJhhbFLQByAQAKAAYJrhvFLQByAQAZAAYJAg2kWwArAQAAAA==.Drygth:BAABLgAECn8ZAAQNAAkJqiCiDgCZAgANAAcJMCKiDgCZAgAMAAgJuRm5EQA7AgAkAAEJbwm+VAA4AAAAAA==.',
Du='Dubshox:BAABLgAECn8gAAIKAAgJPRw6HgDXAQAKAAgJPRw6HgDXAQAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ea='Earthly:BAAALgAECgEJBAAAAA==.',
Ei='Eisador:BAABLgAECn8rAAIOAAkJnQ9jRgC2AQAOAAkJnQ9jRgC2AQAAAA==.',
El='Eldritch:BAAALgADCgcJBwAAAA==.Elemotional:BAABLgAECn8fAAIJAAkJkR0XBAChAgAJAAkJkR0XBAChAgAAAA==.',
Em='Emp:BAAALgAECgUJCgAAAA==.',
Eq='Equilibrio:BAABLgAECn8jAAMlAAkJbiDiBwBrAgAlAAgJ5yHiBwBrAgAEAAEJHRbkhgBGAAAAAA==.',
Er='Erilee:BAAALgAECgMJAwAAAA==.',
Es='Essos:BAAALgAECgQJBAAAAA==.',
Et='Ettle:BAAALgAECgEJAQABLgAECgUJBgABAAAAAA==.',
Ev='Evelira:BAAALgAECgQJBAABLgAFFAgJHQAGALUXAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAABLgAECn8jAAQIAAcJRCHDEwD7AQAIAAcJMx/DEwD7AQAfAAYJNxkHFAAJAQAOAAEJjxoHAQE9AAAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECgkJJAATAEgVAA==.',
Fa='Faelthas:BAACLgAFFH8aAAIbAAUJ9CTHAQDvAQAbAAUJ9CTHAQDvAQAuAAQKfzEAAhsACAksJtkCAGkDABsACAksJtkCAGkDAAAA.Fathercoast:BAACLgAFFH8FAAIkAAIJWB0yLgCrAAAkAAIJWB0yLgCrAAAuAAQKfy0AAw0ACQmUHEIUABACAA0ACQmUHEIUABACACQABwlpGvQfAJQBAAAA.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAABLgAECn8YAAMHAAkJqB2sEACrAgAHAAkJqB2sEACrAgAPAAIJ7R06HACgAAAAAA==.Felstrider:BAAALgAECgUJCAAAAA==.Fembouyant:BAABLgAECn8XAAISAAkJtBSIBAAVAgASAAkJtBSIBAAVAgAAAA==.Ferador:BAACLgAFFH8fAAMOAAgJQhF1CQDSAQAOAAYJ+RN1CQDSAQAfAAUJZwU8EwAKAQAuAAQKfyUAAx8ACAkEIAIjAA4CAB8ACAnFFQIjAA4CAA4ABQmKIdVlAGABAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.Fistsphoyou:BAAALgAECgEJAQAAAA==.',
Fl='Flowmo:BAAALgAECgYJCAABLgAECggJFwAbANobAA==.',
Fo='Forsakken:BAAALgAECgUJBQAAAA==.Fortou:BAAALgADCgMJAgAAAA==.Fourbees:BAAALgAECgYJDQAAAA==.',
Fr='Frizly:BAABLgAECn8kAAMMAAgJHwp0MQAuAQAMAAgJHwp0MQAuAQANAAEJ5AALigAQAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIGAAkJ/hGTXQAhAgAGAAkJ/hGTXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.Fursure:BAAALgADCgcJBwAAAA==.',
Ga='Galdrell:BAABLgAECn8WAAMgAAgJsw3JGgAoAQAgAAgJsw3JGgAoAQACAAEJggB7YQEXAAAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgAECgEJAQAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8nAAMRAAkJKh9LEwAIAwARAAkJKh9LEwAIAwASAAUJBRslEgAmAQAAAA==.',
Gn='Gnnome:BAABLgAECn8eAAIGAAgJEAoilgAxAQAGAAgJEAoilgAxAQAAAA==.',
Go='Gog:BAAALgAFFAEJAQAAAA==.Goodolruss:BAAALgADCgUJBQAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIYAAkJ3yVfAADPAwAYAAkJ3yVfAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8sAAIRAAkJgRwjMQAmAgARAAkJgRwjMQAmAgAAAA==.Greine:BAAALgADCgEJAQAAAA==.Grimaldus:BAABLgAECn8ZAAIgAAkJah98BAC9AgAgAAkJah98BAC9AgAAAA==.Grimmble:BAAALgAECgYJCwAAAA==.Grimmortal:BAAALgAECggJCAAAAA==.Grimreaper:BAABLgAECn8qAAMmAAkJuh/SAQCtAgAmAAkJuh/SAQCtAgAaAAIJeRA0UwCRAAAAAA==.Groag:BAABLgAECn8VAAQnAAgJuSENAgC2AgAnAAgJuSENAgC2AgAmAAQJMRr7FwB6AAAaAAIJ0xvXTwBBAAABLgAECgkJGQANAKogAA==.Groovytony:BAAALgAECgYJBgAAAA==.Grototh:BAABLgAECn8VAAIHAAcJOBdBQQCtAQAHAAcJOBdBQQCtAQABLgAECgkJGQANAKogAA==.Gruffles:BAABLgAECn8rAAIDAAgJrCIUDwDLAgADAAgJrCIUDwDLAgAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8jAAIHAAkJ5R07IgA0AgAHAAkJ5R07IgA0AgAAAA==.',
Ha='Haarp:BAAALgAECgQJBgAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handicat:BAAALgADCgEJAQABLgAECgkJHgANAHIUAA==.Handimage:BAAALgADCgEJAQABLgAECgkJHgANAHIUAA==.Handipally:BAAALgAECgEJAQABLgAECgkJHgANAHIUAA==.Handipriest:BAABLgAECn8eAAINAAkJchT1GADjAQANAAkJchT1GADjAQAAAA==.Haqq:BAACLgAFFH8HAAIEAAQJoQW2JQD+AAAEAAQJoQW2JQD+AAAuAAQKfywAAgQACQkOFNkbAPsBAAQACQkOFNkbAPsBAAAA.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgAECgcJDQABLgAECggJEAABAAAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8zAAIRAAgJjRAOZgCHAQARAAgJjRAOZgCHAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgAECgcJEAAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8gAAIRAAkJciAHGQCdAgARAAkJciAHGQCdAgAAAA==.',
Ho='Hoafustis:BAAALgAECgEJAQAAAA==.Hobo:BAABLgAECn8eAAIOAAYJuBqDVACNAQAOAAYJuBqDVACNAQAAAA==.Hollowshädix:BAAALgAFFAIJAgAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBQAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Huggrnaut:BAAALgAECgYJDQAAAA==.Hundard:BAAALgAECgQJBQAAAA==.Huntersmarc:BAAALgAECgEJAQAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAACLgAFFH8FAAIoAAEJ3SJKEwBkAAAoAAEJ3SJKEwBkAAAuAAQKfx0AAigACQlBIyoBADMDACgACQlBIyoBADMDAAAA.Iblisshaytan:BAABLgAECn8cAAMVAAcJZBU3IgBCAQAVAAcJOBU3IgBCAQAHAAYJzBKRggD+AAABLgAFFAUJDgAGAGMQAA==.Ibtrollin:BAAALgAECgYJDwAAAA==.',
Ic='Icepak:BAAALgADCgUJBQAAAA==.',
Ig='Ignacious:BAACLgAFFH8FAAIZAAMJ5Qi8RwCxAAAZAAMJ5Qi8RwCxAAAuAAQKfzAABBkACQkKJOMCAFADABkACQkKJOMCAFADAAoABwlTGxUqAIcBAAkAAQlWDxUsADUAAAAA.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAABLgAECn8nAAIoAAgJrRZlDADPAQAoAAgJrRZlDADPAQAAAA==.Immolate:BAABLgAECn8aAAQXAAkJzyEHNgA0AgAXAAcJbx8HNgA0AgAWAAUJsCKSFgCVAQAhAAEJAAAzJABhAAAAAA==.',
In='Infamous:BAAALgAECggJEwAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJEQAAAA==.',
Io='Ionissa:BAAALgAECgcJBwAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAwAAAA==.',
Is='Ischia:BAACLgAFFH8cAAIMAAUJQxZGAgCNAQAMAAUJQxZGAgCNAQAuAAQKfyIAAwwACAkdEjUgAOABAAwACAkdEjUgAOABAA0ABgkbCthIAMUAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIaAAIJpx+nEADFAAAaAAIJpx+nEADFAAAuAAQKfxgAAhoABwliI8MXAEsCABoABwliI8MXAEsCAAAA.Jallypally:BAAALgADCggJCQAAAA==.Jamuel:BAAALgAECgkJCAAAAA==.Janokdiso:BAAALgAECgEJAQABLgAECgkJKAAGAHYfAA==.Javaman:BAAALgADCgYJCAABLgADCgQJBQABAAAAAA==.Javeighqueas:BAAALgADCgQJAgABLgAFFAQJDQARAFkWAA==.',
Jc='Jch:BAACLgAFFH8eAAMOAAgJchp+AADCAQAOAAcJDBp+AADCAQAfAAEJ1hyZKABRAAAuAAQKfyIAAw4ACQllJP0BAH8DAA4ACQllJP0BAH8DAB8AAQmiB06PACwAAAAA.',
Je='Jedijed:BAAALgAFFAIJAwAAAA==.Jedikepjr:BAACLgAFFH8LAAICAAMJyRRRVgDgAAACAAMJyRRRVgDgAAAuAAQKfxQAAgIABwnTHM1XAKwBAAIABwnTHM1XAKwBAAEuAAUUAgkDAAEAAAAA.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECggJCwAAAA==.Joneztown:BAABLgAECn8WAAIcAAkJQRq5CwC/AgAcAAkJQRq5CwC/AgAAAA==.Jordantheorc:BAABLgAECn8nAAMOAAkJihxFEQCvAgAOAAkJihxFEQCvAgAfAAIJvwLsgQBAAAAAAA==.',
Jp='Jprottsoo:BAACLgAFFH8NAAIQAAQJ2B/HDwByAQAQAAQJ2B/HDwByAQAuAAQKfygAAhAACQnvISUEABADABAACQnvISUEABADAAAA.',
Jt='Jtee:BAABLgAECn8tAAMiAAgJehWJJADMAQAiAAgJehWJJADMAQACAAEJbAo3fQEuAAAAAA==.',
Ju='Jukkrit:BAAALgAECgEJAQAAAA==.',
Jy='Jy:BAAALgADCgMJAwAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8kAAIDAAkJ2woBTwBAAQADAAkJ2woBTwBAAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECgkJIwAhAKgZAA==.Karoo:BAAALgADCgYJBgAAAA==.Kataris:BAAALgAECgEJAQABLgAECggJJQAOAN8dAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAgAAAA==.Keizzer:BAABLgAECn8kAAICAAkJlx8OHgC3AgACAAkJlx8OHgC3AgAAAA==.Kelesa:BAAALgADCgEJAQAAAA==.Keshisaru:BAABLgAECn8UAAIOAAgJehS6JgAfAgAOAAgJehS6JgAfAgAAAA==.',
Kh='Kharms:BAABLgAECn8nAAIcAAkJJSLzAwANAwAcAAkJJSLzAwANAwAAAA==.Khavan:BAAALgAECgMJAgAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.Kiwi:BAAALgAECgYJCgAAAA==.',
Kl='Klunder:BAABLgAECn8fAAIZAAkJlx48DADhAgAZAAkJlx48DADhAgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIbAAgJ2hvTFABmAgAbAAgJ2hvTFABmAgAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAABLgAECn8gAAIOAAkJwxuFJgAwAgAOAAkJwxuFJgAwAgAAAA==.Kostik:BAAALgAECgQJBQAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAACLgAFFH8FAAIHAAMJzwkMWwC9AAAHAAMJzwkMWwC9AAAuAAQKfyoAAgcACQlhGcAeAEcCAAcACQlhGcAeAEcCAAAA.Krux:BAAALgAECgIJBAAAAA==.',
Ky='Kybinc:BAAALgADCgQJBQAAAA==.',
['Kí']='Kírã:BAAALgAECgUJCAAAAA==.',
La='Lacie:BAAALgADCgkJDAAAAA==.Laennaya:BAABLgAECn89AAIhAAkJaw1qCQCrAQAhAAkJaw1qCQCrAQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAABLgAECn8hAAIGAAcJhAkkqAATAQAGAAcJhAkkqAATAQAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgMJCgAAAA==.Lazybigger:BAAALgAECgEJAQAAAA==.Lazyfrost:BAABLgAECn8oAAIGAAkJdh80DgD0AgAGAAkJdh80DgD0AgAAAA==.Lazyunholy:BAAALgAECgEJAQABLgAECgkJKAAGAHYfAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8fAAMiAAgJYSCWEwB2AgAiAAgJYSCWEwB2AgACAAEJZA4ZPwE1AAAAAA==.Lethô:BAACLgAFFH8JAAIDAAMJiCAhJAAfAQADAAMJiCAhJAAfAQAuAAQKfzQAAwMACQkKIigDAIgDAAMACQkKIigDAIgDABAAAQk7EqR8ADcAAAAA.Lethö:BAAALgAECgYJCAAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Lickemlow:BAAALgAECgEJAQAAAA==.Liesx:BAAALgAECgEJAQAAAA==.Lilboothang:BAABLgAECn8ZAAIXAAgJaRPeTwCgAQAXAAgJaRPeTwCgAQAAAA==.Lillìth:BAAALgAECgYJCwAAAA==.Lilzarthe:BAAALgAFFAIJAwAAAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Loachella:BAAALgADCgUJBQAAAA==.Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAACLgAFFH8JAAIHAAMJHCaZLQBEAQAHAAMJHCaZLQBEAQAuAAQKfzIAAgcACQneJRgCALcDAAcACQneJRgCALcDAAAA.Loko:BAACLgAFFH8gAAIQAAgJ6x9KAQC3AgAQAAgJ6x9KAQC3AgAuAAQKfzYAAhAACQmAJK4CADwDABAACQmAJK4CADwDAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAFFAEJAQAAAA==.Louiie:BAABLgAECn8dAAIaAAgJShK+HACXAQAaAAgJShK+HACXAQAAAA==.',
Lu='Luckygrapes:BAACLgAFFH8OAAIdAAQJkB9lFwBsAQAdAAQJkB9lFwBsAQAuAAQKfxsAAh0ACAmqHs8OAGkCAB0ACAmqHs8OAGkCAAAA.Lukdanuke:BAAALgAECgYJCgAAAA==.Lumi:BAAALgAECgEJAgAAAA==.Luxxus:BAAALgAECgcJCwABLgAECgkJJAACAJcfAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAABLgAECn8fAAIKAAkJYxAeKACTAQAKAAkJYxAeKACTAQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8gAAIXAAkJXQ9/SwCsAQAXAAkJXQ9/SwCsAQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAIcAAcJnh0NFABPAgAcAAcJnh0NFABPAgAAAA==.Mantakore:BAACLgAFFH8SAAIeAAUJzQmwFAAqAQAeAAUJzQmwFAAqAQAuAAQKfzQAAh4ACAmOGY4MAPoBAB4ACAmOGY4MAPoBAAAA.Marcdruid:BAAALgAECgUJBwAAAA==.Maubles:BAAALgAECgYJEQABLgAFFAUJFgAgACsRAA==.',
Me='Meadöw:BAABLgAECn8gAAIDAAkJ/hHfKAD5AQADAAkJ/hHfKAD5AQAAAA==.Meiling:BAAALgAECgUJBQAAAA==.Meladra:BAAALgAECgEJAQAAAA==.Menopaws:BAABLgAECn8gAAQpAAkJ3SEaAgAQAwApAAkJ3SEaAgAQAwAoAAYJphaLFABTAQAQAAQJghGqYACfAAAAAA==.Mertrik:BAABLgAECn8dAAMKAAkJghu8EAChAgAKAAkJghu8EAChAgAJAAEJuBiBKQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8lAAIYAAkJlx9sCwBdAgAYAAkJlx9sCwBdAgAAAA==.Mikailla:BAAALgAFFAIJAwABLgAECgEJAQABAAAAAA==.Mikayy:BAACLgAFFH8UAAMaAAcJkCMjBACzAQAaAAYJNiQjBACzAQAnAAEJUSCBCwBgAAAuAAQKfzIAAxoACQk5JpEFAMgCABoACQnOJZEFAMgCACcAAQmSJrEaAHEAAAAA.Milenko:BAABLgAECn8yAAIVAAkJUSVZAQBVAwAVAAkJUSVZAQBVAwAAAA==.Milly:BAAALgAECgYJEgABLgAECgkJMgAVAFElAA==.Mimid:BAAALgAECgYJDgAAAA==.Mimonk:BAAALgAECgQJBAAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minii:BAAALgAECgYJBgAAAA==.Minteafresh:BAAALgAECgUJDAAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8bAAMEAAgJQxNfBADvAQAEAAcJQRZfBADvAQAFAAIJrQlVKwB9AAAuAAQKfyYAAwQACAnuHe8RAMACAAQACAnuHe8RAMACAAUABAk3Gc0YADABAAAA.Montshifter:BAAALgAECgEJAQABLgAECgQJCwABAAAAAA==.Moort:BAAALgAECgYJDwAAAA==.Moothafacka:BAAALgADCgcJBwAAAA==.Mordecaii:BAAALgAECgcJBAAAAA==.Morganlefay:BAAALgADCgcJEgAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAABLgAECn8UAAIRAAgJ1Ar6gwBGAQARAAgJ1Ar6gwBGAQAAAA==.Moyana:BAAALgAECgQJBQAAAA==.',
Ms='Msbehaven:BAABLgAECn8dAAIXAAkJfAW0fQAzAQAXAAkJfAW0fQAzAQAAAA==.',
Mt='Mthafknfreez:BAACLgAFFH8OAAIGAAUJYxDIUwArAQAGAAUJYxDIUwArAQAuAAQKfycAAgYACQm3GTksAFICAAYACQm3GTksAFICAAAA.',
My='Mynuturchin:BAAALgAECgYJEQAAAA==.',
['Mî']='Mîg:BAABLgAECn8jAAIHAAkJoRAlUQB7AQAHAAkJoRAlUQB7AQAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJCAABLgAECgUJFgAQADgRAA==.Nahtikal:BAABLgAECn8kAAMdAAgJnhXOHwD0AQAdAAgJnhXOHwD0AQAcAAYJSQ2qPgDrAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgYJBgABLgAECgkJJwARACofAA==.',
Ne='Neytiri:BAAALgAECgEJAQAAAA==.',
Ni='Nilfalath:BAAALgAECgYJDgAAAA==.Nippy:BAAALgAECgYJEAAAAA==.',
No='Noriva:BAAALgAECgMJBAAAAA==.Notthechosen:BAAALgAECgEJAQABLgAFFAUJEwAEAFIPAA==.',
Ny='Nymeriã:BAABLgAECn8dAAMDAAcJIQl7XQAMAQADAAcJIQl7XQAMAQAQAAUJfwS+ZQBnAAAAAA==.Nymeriå:BAAALgADCggJCQAAAA==.',
Ob='Obzy:BAAALgADCgkJGAABLgAFFAQJDQARAFkWAA==.Obzz:BAACLgAFFH8NAAIRAAQJWRZ9RgBEAQARAAQJWRZ9RgBEAQAuAAQKfxkAAhEACQk5HMQiAGcCABEACQk5HMQiAGcCAAAA.',
Od='Odiedude:BAAALgAECgYJBgAAAA==.Odieous:BAABLgAECn8gAAIiAAkJchzVCADpAgAiAAkJchzVCADpAgAAAA==.',
Ok='Okamy:BAABLgAECn8eAAIRAAkJfiCvEwC/AgARAAkJfiCvEwC/AgABLgAECgcJIwAIAEQhAA==.',
Om='Omeganemesis:BAAALgAECgcJCAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8uAAMHAAkJ4xZcPwC0AQAHAAkJaBZcPwC0AQAVAAgJkg8gHgBlAQABLgAFFAQJDQARAFkWAA==.',
Or='Orghujon:BAAALgAECgYJDAAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgAECgkJEgAAAA==.Palamon:BAAALgAECgYJDAAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBgAAAA==.Papadaddy:BAAALgADCgUJBQAAAA==.Parthos:BAAALgAECggJDQAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAACLgAFFH8WAAIbAAQJ3x90FQBTAQAbAAQJ3x90FQBTAQAuAAQKfxsAAhsABwnWIwYNAFMCABsABwnWIwYNAFMCAAAA.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgAECgEJAgAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAABLgAFFH8HAAIHAAMJrxk8SwDrAAAHAAMJrxk8SwDrAAABLgAFFAQJFgAbAN8fAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.Piyre:BAAALgAECgEJAwAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pocus:BAAALgAECgkJDQABLgAECggJIQAHAHAbAA==.Pokedone:BAAALgAECgIJAgAAAA==.Polskashaman:BAABLgAECn8gAAIJAAkJVxGJDQC8AQAJAAkJVxGJDQC8AQAAAA==.Poptart:BAACLgAFFH8MAAICAAUJJgteQgAPAQACAAUJJgteQgAPAQAuAAQKfxoAAgIACAlLFCBdAMsBAAIACAlLFCBdAMsBAAAA.Power:BAAALgAFFAIJAgABLgAFFAYJGgACADQmAA==.',
Pr='Prea:BAAALgAECgYJCwAAAA==.Premiumferal:BAAALgAECgYJDgABLgAECgkJJwARACofAA==.Primecarry:BAACLgAFFH8UAAIiAAYJzSP6BQAvAgAiAAYJzSP6BQAvAgAuAAQKfyMAAyIACAkCI6EJANcCACIACAkCI6EJANcCACAABgkfIHgOAMIBAAAA.',
Pu='Puhtater:BAAALgAECgMJBgAAAA==.Pumpmedaddy:BAAALgAECgUJBQAAAA==.Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgYJEwAAAA==.',
['Pë']='Pëpsï:BAAALgAECgcJEQAAAA==.',
Qu='Quanah:BAAALgAECgUJCwAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgABAAAAAA==.Ragecritz:BAABLgAFFH8GAAMFAAQJLwLdKgB/AAAFAAMJvgLdKgB/AAAEAAEJgACKTQAPAAAAAA==.Raigko:BAAALgAECgkJDQAAAA==.Raintolin:BAAALgAECgYJEAABLgAFFAQJCgARAB8bAA==.Raiva:BAAALgAFFAIJBAABLgAFFAMJCwARAJAaAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Raspberri:BAAALgAECgEJAQAAAA==.Rassputen:BAABLgAECn8tAAIYAAkJRhlUDwD6AQAYAAkJRhlUDwD6AQAAAA==.',
Re='Redjive:BAAALgAECgYJCAAAAA==.Redonkulos:BAABLgAFFH8GAAIaAAIJ+hrMKwCVAAAaAAIJ+hrMKwCVAAAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAbAPwPAA==.Redthorne:BAAALgADCgMJAwAAAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAACLgAFFH8TAAMNAAUJVhwGDwBZAQANAAQJVhwGDwBZAQAMAAQJAR7HDABXAQAuAAQKfyEAAw0ACAlTIxUTAF0CAA0ABwnjIxUTAF0CAAwABwkzHPIsAE0BAAAA.Reliri:BAAALgAECgYJDAAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgkJFQAAAA==.Rider:BAAALgADCgYJBgABLgAFFAgJHAAiAM0XAA==.Rincewind:BAAALgADCgEJAQAAAA==.Rinth:BAABLgAECn8iAAMfAAkJPCL6CQAEAwAfAAgJpSH6CQAEAwAOAAMJ2yQpfwAnAQAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIgAAgJQhpCCABWAgAgAAgJQhpCCABWAgAAAA==.Roguen:BAACLgAFFH8FAAIaAAQJZQwpGQAwAQAaAAQJZQwpGQAwAQAuAAQKfzwAAhoACQnSFNYRAAICABoACQnSFNYRAAICAAEuAAUUBQkOAAYAYxAA.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAABLgAECn8UAAIZAAgJIQzfYwARAQAZAAgJIQzfYwARAQABLgAFFAYJFAAfABALAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAABLgAECn8WAAIlAAgJ9BgaDgDwAQAlAAgJ9BgaDgDwAQAAAA==.Roulduke:BAABLgAECn8oAAIKAAkJMxFrIgC5AQAKAAkJMxFrIgC5AQAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Rylearria:BAAALgADCgMJAwAAAA==.Ryna:BAAALgADCgkJCAAAAA==.',
['Rù']='Rùckús:BAACLgAFFH8GAAIRAAMJIRL2gQDeAAARAAMJIRL2gQDeAAAuAAQKfywAAhEACQkVH9QWAKsCABEACQkVH9QWAKsCAAAA.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8vAAMgAAgJswxxGwAiAQAgAAgJswxxGwAiAQACAAEJbgUOjwEnAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAECgcJHwAHAFIeAA==.Sakiara:BAAALgAECgQJBgAAAA==.Salaen:BAAALgAECgkJCwAAAA==.Sammybeans:BAABLgAECn8kAAICAAkJMhepRADgAQACAAkJMhepRADgAQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAABLgAECn8lAAIOAAgJ3x0XHgBbAgAOAAgJ3x0XHgBbAgAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAABLgAECn8UAAIYAAgJxgNYOgCQAAAYAAgJxgNYOgCQAAAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Sc='Scrandle:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Screwball:BAAALgADCgEJAQAAAA==.',
Se='Seceron:BAAALgAECggJEQAAAA==.Sekai:BAAALgAFFAMJBAAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8kAAMMAAgJ3gZASQAUAQAMAAYJiwhASQAUAQANAAgJNAQXRADYAAAAAA==.Serpentsin:BAAALgAECgMJBAAAAA==.',
Sg='Sgtslappy:BAABLgAECn88AAIEAAkJqx9rCgCqAgAEAAkJqx9rCgCqAgAAAA==.',
Sh='Shanarelle:BAACLgAFFH8KAAIDAAQJpQhkNADMAAADAAQJpQhkNADMAAAuAAQKfxoAAgMACAnPGR4eAE0CAAMACAnPGR4eAE0CAAAA.Sharis:BAAALgADCgUJBQABLgAECggJJQAOAN8dAA==.Shasa:BAACLgAFFH8MAAIOAAQJMAz3OAAhAQAOAAQJMAz3OAAhAQAuAAQKfy0AAg4ACQnhGegZAG0CAA4ACQnhGegZAG0CAAAA.Shatteredsky:BAABLgAECn8VAAIZAAgJNCJTCAAXAwAZAAgJNCJTCAAXAwAAAA==.Shazik:BAAALgAECgEJAQAAAA==.Sheroko:BAAALgAECgEJAQAAAA==.Shilbalam:BAAALgAECgcJBwAAAA==.Shinanìgans:BAAALgAECgYJDQAAAA==.Shmoopy:BAAALgAECgYJBgABLgAECgYJEAABAAAAAA==.Shortyman:BAAALgAECgUJBwABLgAECgkJJwARACofAA==.Shruikan:BAABLgAECn8UAAQTAAcJTRk+HADlAQATAAcJ2Rg+HADlAQAUAAcJ7g8NGQBvAQAeAAMJlgWuPACFAAAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgYJFwARABsaAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAACLgAFFH8LAAIRAAMJkBr5bwD+AAARAAMJkBr5bwD+AAAuAAQKfzMAAxEACQlzHfcbAIwCABEACQlCHPcbAIwCABgAAgkCHYw/AHcAAAAA.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAgAAAA==.Sisturfistur:BAAALgAECgUJBwAAAA==.',
Sk='Skunkpaw:BAAALgADCgYJEQAAAA==.Skysong:BAACLgAFFH8cAAMUAAgJtw5VAQCmAQAUAAUJ9Q9VAQCmAQATAAYJ2AoQFQB/AQAuAAQKfyEABBQACAnJHc4MAA4CABQABwlhG84MAA4CAB4ABwlqFy4NAO0BABMAAwnVF0xCANoAAAAA.',
Sl='Slashedeye:BAACLgAFFH8HAAIjAAMJ/xm2AQABAQAjAAMJ/xm2AQABAQAuAAQKfzcAAiMACQk8GnkCAA4CACMACQk8GnkCAA4CAAAA.',
Sm='Smallfoot:BAAALgAECgEJAQAAAA==.Smellsoftree:BAAALgAECgcJCwAAAA==.',
Sn='Snowynn:BAABLgAECn8sAAMpAAkJAxOSDwDMAQApAAkJAxOSDwDMAQADAAEJWwHx6gAZAAAAAA==.Snubby:BAABLgAECn8pAAMXAAkJEySrDADbAgAXAAcJKSWrDADbAgAWAAUJuSJ0DAD7AQAAAA==.',
So='Soleil:BAABLgAECn8VAAMNAAkJkQ9qLAB6AQANAAkJkQ9qLAB6AQAkAAQJuw/PTwCSAAAAAA==.Solheim:BAACLgAFFH8RAAMIAAUJeRzcCQBoAQAIAAUJWhzcCQBoAQAfAAIJHB2jGgCvAAAuAAQKfyQAAx8ACAkYI9kKAPgCAB8ACAkoItkKAPgCAAgABAlFHUs2AO8AAAAA.Souffle:BAACLgAFFH8OAAIXAAMJEBCzZADhAAAXAAMJEBCzZADhAAAuAAQKfyIAAxcABwlAGQNMAOUBABcABwlAGQNMAOUBABYAAQkAAHVtADoAAAEuAAUUBQkRAAIASRkA.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMbAAgJ/A8ZMgCJAQAbAAgJ/A8ZMgCJAQAcAAEJ/we5lgArAAAAAA==.Spookypink:BAABLgAECn8gAAICAAkJkCL0DADoAgACAAkJkCL0DADoAgAAAA==.Spárda:BAAALgAECgMJAwABLgAECgcJIwAIAEQhAA==.',
Sq='Squirtz:BAAALgAECgYJBwAAAA==.',
Sr='Srirachajane:BAAALgADCgkJDQABLgAECggJGQAoADAbAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Starwon:BAAALgADCgIJAgAAAA==.Strathin:BAAALgADCgkJDQAAAA==.Strathz:BAABLgAECn8lAAMWAAkJpCCeCgAVAgAWAAYJPx+eCgAVAgAXAAcJjh4hQwDGAQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIiAAgJ1hq3GABNAgAiAAgJ1hq3GABNAgAAAA==.Summerset:BAAALgAECgYJEAAAAA==.Sushi:BAAALgAECgYJCAAAAA==.',
Sy='Sylatis:BAACLgAFFH8zAAMIAAkJqyMNAABIAwAIAAkJqyMNAABIAwAfAAYJiRTMAwAHAgAuAAQKfxYAAx8ACAk0JVsNANsCAB8ACAk0JVsNANsCAAgAAwmkHggoAHUAAAAA.Sylvara:BAAALgAECgMJBgAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.Sylätis:BAAALgAFFAIJAwABLgAFFAkJMwAIAKsjAA==.',
['Sö']='Söultender:BAABLgAECn8lAAQkAAgJGBV0HgC3AQAkAAgJBg90HgC3AQAMAAUJABNSOQD9AAANAAEJvAlNYwAyAAAAAA==.',
Ta='Taichi:BAACLgAFFH8ZAAIdAAUJDBdmFwBsAQAdAAUJDBdmFwBsAQAuAAQKfyIAAh0ACAkAHksMAI4CAB0ACAkAHksMAI4CAAAA.Talys:BAACLgAFFH8dAAIeAAgJ/BgpAwCEAgAeAAgJ/BgpAwCEAgAuAAQKfysAAh4ACQlAHIcIALICAB4ACQlAHIcIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgAECgIJAgAAAA==.Tarth:BAACLgAFFH8gAAIpAAgJOB6GAACkAgApAAgJOB6GAACkAgAuAAQKfyMAAikACAkEJmwBAEEDACkACAkEJmwBAEEDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8nAAIeAAgJNBuZCABTAgAeAAgJNBuZCABTAgAAAA==.Taïko:BAAALgADCgQJBAAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgYJEQABLgAFFAQJCgARAB8bAA==.Tenniell:BAAALgAECgQJDQAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAACLgAFFH8HAAIGAAMJJRAgbwDjAAAGAAMJJRAgbwDjAAAuAAQKfyUAAgYACQmHF2ItAE0CAAYACQmHF2ItAE0CAAAA.',
Th='Thab:BAAALgAECgYJDAABLgAECgkJJAATAEgVAA==.Thabk:BAABLgAECn8kAAMTAAkJSBVEHQDTAQATAAkJSBVEHQDTAQAUAAEJaAdCQwAoAAAAAA==.Thaelorn:BAAALgAECgMJAwAAAA==.Thakb:BAAALgAECgMJAwABLgAECgkJJAATAEgVAA==.Tharit:BAAALgADCgYJCgAAAA==.Theodius:BAAALgAECgQJBAAAAA==.Theshortbuss:BAABLgAECn8hAAMCAAgJ/hgYOgACAgACAAgJ/hgYOgACAgAgAAEJogEpVgAQAAAAAA==.Thesuffering:BAAALgAECgUJBwAAAA==.Thesyra:BAAALgAECgkJEgAAAA==.Thingtwò:BAAALgAECgIJAgAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDgAAAA==.',
Ti='Tiddybear:BAAALgAECgkJDwAAAA==.Timerunhunt:BAAALgADCgUJBgAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAABLgAECn8YAAIYAAgJVgcRLQDZAAAYAAgJVgcRLQDZAAAAAA==.Toastz:BAABLgAFFH8HAAIOAAMJARDcTADoAAAOAAMJARDcTADoAAAAAA==.Tokken:BAACLgAFFH8RAAIEAAQJTheqGQA2AQAEAAQJTheqGQA2AQAuAAQKfyIAAgQACQnpHEcMAPYCAAQACQnpHEcMAPYCAAAA.',
Tr='Treebeast:BAACLgAFFH8GAAIKAAMJDROBFwCXAAAKAAMJDROBFwCXAAAuAAQKfxUAAgoABwlnH4kcAC0CAAoABwlnH4kcAC0CAAAA.Treediddy:BAABLgAFFH8HAAIpAAQJqxMVDQD4AAApAAQJqxMVDQD4AAABLgAFFAQJFgAbAN8fAA==.Troile:BAAALgAECggJEAAAAA==.Trojen:BAAALgADCgcJBwAAAA==.Trolladin:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
Tu='Tubularoso:BAABLgAECn8WAAIWAAcJ6g8KEAAmAQAWAAcJ6g8KEAAmAQAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Tw='Twobtn:BAAALgAECgUJBQAAAA==.',
Ty='Tyras:BAAALgADCgYJBgAAAA==.',
Ul='Ulanda:BAABLgAECn8nAAQDAAgJvQ8ATgBEAQADAAcJVw0ATgBEAQApAAcJWgeLMwCzAAAQAAEJqwHHjwAcAAAAAA==.',
Um='Umako:BAACLgAFFH8QAAMnAAUJjx6WAQBvAQAnAAQJcyCWAQBvAQAaAAQJjxYqEwCzAAAuAAQKfyEAAycACQmuIfIAAEQDACcACQmUIfIAAEQDABoACAlGFyYdABYCAAAA.',
Un='Underbogg:BAAALgAECgEJAQAAAA==.Unus:BAAALgADCgQJBAABLgAECgkJLgAGAFYgAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Ux='Ux:BAAALgAECgcJBwAAAA==.',
Va='Vaedric:BAAALgAECgIJAwAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgcJEQAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAACLgAFFH8TAAIEAAUJUg/eHQAmAQAEAAUJUg/eHQAmAQAuAAQKfx8AAgQACAkRG70nAB8CAAQACAkRG70nAB8CAAAA.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8qAAIEAAgJOib8BQDvAgAEAAgJOib8BQDvAgABLgAFFAEJBQAoAN0iAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8cAAIHAAgJfQ3AaQA3AQAHAAgJfQ3AaQA3AQAAAA==.Voids:BAAALgADCgcJDAAAAA==.Voodoochild:BAAALgAECgEJAQAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAABLgAFFH8IAAMIAAQJtg5wEgAtAQAIAAQJtg5wEgAtAQAfAAMJmghjGQC2AAABLgAFFAYJFAAfABALAA==.',
Vy='Vyzerion:BAAALgAECgYJBgABLgAECgcJIwAIAEQhAA==.',
['Vé']='Vénandi:BAAALgAECgIJAgAAAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgABAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMZAAgJwBqHIwAKAgAZAAgJwBqHIwAKAgAKAAQJ7AWpcwBuAAAAAA==.',
Wa='Wagtar:BAAALgADCgQJBAABLgADCgQJBQABAAAAAA==.Walkerwhite:BAAALgAECgkJDwABLgAECggJIQANAN0ZAA==.Warjd:BAABLgAECn8aAAIEAAgJQQyiNABiAQAEAAgJQQyiNABiAQAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Weebo:BAAALgADCgYJCQAAAA==.Wesjin:BAABLgAECn8aAAIdAAkJcRq2DgBrAgAdAAkJcRq2DgBrAgAAAA==.Wetbonez:BAAALgAECgEJAQAAAA==.Wez:BAABLgAECn8WAAICAAgJ7wpikwAxAQACAAgJ7wpikwAxAQAAAA==.',
Wh='Whiskee:BAACLgAFFH8WAAIoAAQJShyUAwBpAQAoAAQJShyUAwBpAQAuAAQKfysABCgACQl5I7QEAM0CACgACQl5I7QEAM0CAAMABwn0D0JMAEoBABAAAQn/E316ADsAAAAA.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Wintulyn:BAAALgAECgYJCwAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgAECgQJBAAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wr='Wrattchild:BAAALgADCgYJBgAAAA==.',
Wy='Wyndia:BAAALgAECgYJDAAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJCQABLgAECggJJQAkABgVAA==.',
Xb='Xbert:BAAALgAECgMJAwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8dAAIGAAgJtRehCAB2AgAGAAgJtRehCAB2AgAuAAQKfxwAAgYACAn+IZIuALgCAAYACAn+IZIuALgCAAAA.Xerlk:BAAALgAECgcJDwAAAA==.',
Xi='Xihuang:BAABLgAECn8WAAIQAAgJ9xENIwCXAQAQAAgJ9xENIwCXAQABLgAFFAUJDgAGAGMQAA==.Xiia:BAABLgAECn8qAAIfAAkJ4B9YAwCJAgAfAAkJ4B9YAwCJAgAAAA==.',
Xx='Xxoouu:BAABLgAFFH8XAAIdAAcJyxHnDADpAQAdAAcJyxHnDADpAQAAAA==.Xxuu:BAAALgAFFAYJAQABLgAFFAcJFwAdAMsRAA==.Xxuublue:BAAALgAFFAYJAQAAAA==.Xxuuvoker:BAAALgAECgkJCQABLgAFFAcJFwAdAMsRAA==.',
Ya='Yaoguai:BAABLgAECn8fAAMQAAkJNhIOHwC1AQAQAAkJNhIOHwC1AQADAAEJwAPE4wAhAAAAAA==.Yasei:BAAALgAECgYJBwAAAA==.Yawgmoth:BAABLgAECn8jAAMhAAkJqBkhAwBwAgAhAAkJqBkhAwBwAgAXAAEJKgx4KwEzAAAAAA==.',
Yd='Ydalflow:BAAALgADCgkJDQAAAA==.',
Za='Zammboomafoo:BAABLgAECn8jAAIgAAgJEiJABACmAgAgAAgJEiJABACmAgAAAA==.Zanian:BAABLgAECn8eAAMDAAgJNReIJwABAgADAAgJNReIJwABAgAoAAIJoAMHPgBEAAAAAA==.Zarthie:BAAALgADCgYJBgABLgAFFAIJAwABAAAAAA==.Zarthy:BAABLgAECn8WAAITAAcJyBO7JACXAQATAAcJyBO7JACXAQABLgAFFAIJAwABAAAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgcJEgAAAA==.Zerra:BAAALgAECgEJAgAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zi='Zip:BAAALgADCgkJCQAAAA==.',
Zo='Zodd:BAAALgADCgEJAwAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgUJCwABLgAECgkJTgAGAA4lAA==.Zuo:BAAALgAECgMJBAAAAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAIoAAgJMBv3BQCjAgAoAAgJMBv3BQCjAgAAAA==.',
['Zà']='Zàánn:BAABLgAECn8eAAIKAAcJTRSRMgBXAQAKAAcJTRSRMgBXAQAAAA==.',
['Ær']='Æris:BAAALgAECgQJBAAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAFFAUJGAAjADghAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAFFAUJGAAjADghAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgAECgYJDAAAAA==.',
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
