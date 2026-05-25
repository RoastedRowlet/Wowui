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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Warrior-Fury','Warrior-Arms','Mage-Frost','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Shaman-Elemental','Mage-Arcane','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Vengeance','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Paladin-Protection','Warlock-Affliction','Paladin-Holy','Hunter-Marksmanship','Mage-Fire','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJDAABLgAFFAMJAwABAAAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Adipocere:BAAALgAECgYJBgABLgAFFAMJCQACAAoPAA==.Admaris:BAABLgAECn8UAAIDAAYJFB1mOwC3AQADAAYJFB1mOwC3AQAAAA==.',
Ag='Age:BAABLgAECn8nAAMEAAkJzhwcDwBhAgAEAAkJzhwcDwBhAgAFAAMJnw0QJwC2AAAAAA==.Agni:BAACLgAFFH8dAAIGAAYJtR2AGgC8AQAGAAYJtR2AGgC8AQAuAAQKfyYAAgYACQnnI6gEALYDAAYACQnnI6gEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8vAAIEAAkJlBdeFAAqAgAEAAkJlBdeFAAqAgAAAA==.',
Al='Alavendis:BAABLgAECn8VAAIHAAcJRhxBPwCqAQAHAAcJRhxBPwCqAQABLgAECgQJBgABAAAAAA==.Alexá:BAAALgAECgUJCQABLgAECgcJIwAIAEQhAA==.Almight:BAAALgAECgMJBwAAAA==.Alnasham:BAACLgAFFH8VAAMJAAYJkxumAADMAQAJAAUJQh2mAADMAQAKAAIJUBhsLACrAAAuAAQKfyoAAwkACAmUIkEGAEcCAAkACAmUIkEGAEcCAAoAAQmUBvSXACMAAAAA.Alphashadow:BAAALgAECgQJBAAAAA==.Altria:BAAALgADCggJDQAAAA==.Alvoka:BAABLgAECn8cAAMGAAkJyhOVagAAAgAGAAkJyhOVagAAAgALAAQJpQ+VCADgAAAAAA==.',
Am='Amarillos:BAAALgAECgkJEAAAAA==.Amarillys:BAACLgAFFH8KAAIMAAUJPBSEDABKAQAMAAUJPBSEDABKAQAuAAQKfyMAAwwACQlDHRkOAHoCAAwACQlDHRkOAHoCAA0AAQnYFJZjADEAAAAA.Ambrotos:BAABLgAECn8VAAIOAAcJLwfvfgASAQAOAAcJLwfvfgASAQAAAA==.Amither:BAAALgAECgYJBgAAAA==.Ammutseba:BAABLgAECn8pAAMPAAkJFhoUBwDsAQAPAAkJFhoUBwDsAQAHAAEJXQr0+wAlAAAAAA==.Amperage:BAAALgAECgEJAQAAAA==.',
An='Anfall:BAABLgAECn8UAAIJAAkJhRnTBAB3AgAJAAkJhRnTBAB3AgAAAA==.Angermeier:BAABLgAECn8sAAIEAAkJ+BuMDQByAgAEAAkJ+BuMDQByAgAAAA==.Angryjeid:BAAALgAECgYJBgABLgAFFAMJCwACAMkUAA==.Angrylady:BAAALgAECgEJAwAAAA==.Anika:BAAALgADCgEJAQAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Arayvia:BAAALgADCgkJCgAAAA==.Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAgAAAA==.Arg:BAAALgAECgYJCAAAAA==.Arowin:BAABLgAECn8aAAIQAAgJuhMEIACaAQAQAAgJuhMEIACaAQAAAA==.Arrielle:BAAALgAECgYJBgAAAA==.Arthaniis:BAACLgAFFH8LAAIKAAMJfBz4IADzAAAKAAMJfBz4IADzAAAuAAQKfxwAAgoACAnMIP8IAAIDAAoACAnMIP8IAAIDAAAA.',
As='Asdar:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgYJDQAAAA==.',
Au='Audideath:BAABLgAECn8XAAMRAAYJGxo1dgBRAQARAAYJQBk1dgBRAQASAAQJSBTRCwD+AAAAAA==.Audry:BAAALgADCgcJCQAAAA==.Augtistic:BAABLgAECn8bAAMTAAkJShJIHQDcAQATAAkJShJIHQDcAQAUAAYJcwIJKwDFAAABLgAECgkJLAARABUfAA==.Auurdeath:BAAALgAECgcJCwAAAA==.',
Av='Avidswolf:BAABLgAECn8oAAIGAAgJKRB1bwB+AQAGAAgJKRB1bwB+AQAAAA==.Avãcyn:BAABLgAECn8oAAMFAAgJ7wp/IQApAQAFAAgJ7wp/IQApAQAEAAYJSwbKVQDKAAAAAA==.',
Aw='Aw:BAACLgAFFH8XAAIVAAgJiyIuAADUAgAVAAgJiyIuAADUAgAuAAQKfxgAAhUACAmeJo0BAJEDABUACAmeJo0BAJEDAAAA.Awppenheimer:BAABLgAECn8hAAMWAAkJ6x2OEADKAQAXAAgJFRzUKgAWAgAWAAYJdRyOEADKAQAAAA==.',
Ax='Ax:BAECLgAFFH8SAAMRAAUJpBE2WgAaAQARAAQJpBE2WgAaAQAYAAEJAABsSgAAAAAuAAQKfxwAAhEABwmMHJhXAJsBABEABwmMHJhXAJsBAAAA.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAAALgAFFAMJAwAAAA==.',
Ba='Babycarrots:BAAALgAECgcJCAAAAA==.Baconz:BAABLgAECn8cAAMKAAkJPxRwJADtAQAKAAkJPxRwJADtAQAZAAEJ/QIvwgAiAAAAAA==.Bakeon:BAABLgAECn8lAAMZAAgJThdYKADuAQAZAAgJThdYKADuAQAKAAMJYAQidABxAAAAAA==.Bakkaz:BAAALgADCgYJBgAAAA==.Baldozhi:BAAALgAECgYJCwAAAA==.Balyndis:BAAALgADCgYJBgAAAA==.Bangbang:BAAALgAFFAIJAgAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAABLgAECn8UAAMDAAQJAhYVXgD7AAADAAQJAhYVXgD7AAAQAAQJ/w/+RQDCAAAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECggJHQAaAEoSAA==.Beardcheese:BAAALgAECgIJAQAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAACLgAFFH8JAAIbAAUJ/gPbKwDZAAAbAAUJ/gPbKwDZAAAuAAQKfyAAAxwACAmQFSYdAPEBABwABgk6HSYdAPEBABsACAn/D4UgAIQBAAAA.',
Bi='Bink:BAABLgAECn8ZAAIIAAkJ9xo1BADcAgAIAAkJ9xo1BADcAgAAAA==.Birblock:BAABLgAFFH8LAAMXAAUJDxeCOwAtAQAXAAUJBxeCOwAtAQAWAAEJWQsNHwBGAAABLgAFFAkJLAAIAAsgAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAABLgAECn8gAAIHAAYJBwr/jgDYAAAHAAYJBwr/jgDYAAAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAABLgAECn8ZAAMdAAkJCAmhRgD3AAAdAAgJEgehRgD3AAAbAAIJZxjlcwBGAAAAAA==.Blãckheart:BAAALgAECgEJAQAAAA==.',
Bo='Bobbo:BAAALgAECgYJDQAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Bolterguy:BAAALgADCgkJCQAAAA==.Boomin:BAAALgAECggJDgAAAA==.',
Br='Braass:BAAALgAECgQJCAABLgAECgQJFAADAAIWAA==.Breachnclear:BAAALgAECgYJCAAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8mAAIbAAkJdRrNEAAVAgAbAAkJdRrNEAAVAgAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgAECgUJCQABLgAECgcJGgACAFEYAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8fAAIZAAkJmCAKBwAZAwAZAAkJmCAKBwAZAwAAAA==.Brutechaos:BAAALgADCgQJBAABLgAECgkJHwAZAJggAA==.Bruteflappy:BAAALgADCgkJCQABLgAECgkJHwAZAJggAA==.',
Bu='Buffygirl:BAABLgAECn8bAAMTAAgJ8RUxIAC0AQATAAgJ8RUxIAC0AQAeAAUJbw0RKQB1AAAAAA==.Bustle:BAAALgADCgkJCQAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECgkJEgAAAA==.',
['Bå']='Båne:BAABLgAECn8oAAIHAAgJlg2dXQBMAQAHAAgJlg2dXQBMAQAAAA==.',
Ca='Carnal:BAAALgADCgUJCAAAAA==.Casini:BAAALgADCgMJAwAAAA==.Caydened:BAAALgAECgQJBwABLgAECggJHwAOANkdAA==.Cazic:BAAALgAECgYJDwAAAA==.',
Ce='Cedren:BAACLgAFFH8IAAIHAAMJlhkzSADgAAAHAAMJlhkzSADgAAAuAAQKfxkAAgcACQnbHfEdAJ4CAAcACQnbHfEdAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIHAAcJsyKpIQCHAgAHAAcJsyKpIQCHAgAAAA==.Certified:BAAALgAECgYJCAAAAA==.',
Ch='Chalix:BAAALgAECgEJAQAAAA==.Cheapheal:BAACLgAFFH8IAAIQAAQJPhkpEwBHAQAQAAQJPhkpEwBHAQAuAAQKfzgAAxAACQk9JMUDAA0DABAACQk9JMUDAA0DAAMABglWGWMvAMIBAAAA.Cheaptide:BAAALgAECgkJDAAAAA==.Cheburashka:BAACLgAFFH8VAAIKAAcJlh2+BQD/AQAKAAcJlh2+BQD/AQAuAAQKfxcAAgoACAnNIhAPALYCAAoACAnNIhAPALYCAAAA.Chewymentos:BAAALgAECgUJDwABLgAECggJLwAfALMMAA==.Chimerabob:BAAALgAECgYJDwAAAA==.Chunkyhunter:BAAALgAECgYJBgABLgAFFAUJEQAcAMIcAA==.Chunkymonkey:BAACLgAFFH8RAAMcAAUJwhyWCgBKAQAcAAUJwhyWCgBKAQAbAAIJGA65HACKAAAuAAQKfxsAAxwACAlKIS4LAMcCABwACAlKIS4LAMcCABsABQlxGuw9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cj='Cjpriestly:BAAALgAECgEJAQAAAA==.',
Cl='Clappncheeks:BAABLgAECn8hAAIIAAgJIhwZDgArAgAIAAgJIhwZDgArAgAAAA==.Claudefrollo:BAABLgAECn8lAAIQAAgJQRNvHgCmAQAQAAgJQRNvHgCmAQAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corlem:BAAALgAECgUJBwAAAA==.Corrüpt:BAABLgAECn8VAAMgAAgJVhpKBAAmAgAgAAgJVhpKBAAmAgAXAAYJ4xWtcgA/AQAAAA==.',
Cr='Crimsa:BAABLgAECn8zAAIgAAkJDQkXCgCKAQAgAAkJDQkXCgCKAQAAAA==.Crimsongost:BAAALgAECgQJBwAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Crocs:BAAALgAECggJCAAAAA==.Cryogen:BAABLgAECn8ZAAIQAAgJQiAxFwDqAQAQAAgJQiAxFwDqAQAAAA==.',
Cs='Cs:BAABLgAECn8pAAIbAAkJ1yLSAwBSAwAbAAkJ1yLSAwBSAwAAAA==.',
Cu='Curufin:BAAALgAECgUJCwAAAA==.',
Da='Daddysmooth:BAAALgAECgYJCAAAAA==.Daemon:BAACLgAFFH8GAAIRAAMJoxvlXwANAQARAAMJoxvlXwANAQAuAAQKfysAAhEACQl5IzwFADwDABEACQl5IzwFADwDAAAA.Daemonproph:BAABLgAECn8jAAIVAAgJOxTtEwC7AQAVAAgJOxTtEwC7AQAAAA==.Dakini:BAABLgAECn8ZAAIhAAcJWiTTDwB3AgAhAAcJWiTTDwB3AgAAAA==.Daktaklakpak:BAABLgAFFH8NAAQOAAMJKRyYUgCuAAAOAAIJeR6YUgCuAAAIAAIJlxnsHACqAAAiAAEJihegKABHAAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8mAAIfAAkJ1B9WBADDAgAfAAkJ1B9WBADDAgAAAA==.Dangerruss:BAABLgAECn8bAAIfAAgJyxLNFABTAQAfAAgJyxLNFABTAQAAAA==.Dangyy:BAAALgADCgMJAwAAAA==.Darkhaven:BAAALgAECgYJCAAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAACLgAFFH8TAAIjAAUJhxysAABnAQAjAAUJhxysAABnAQAuAAQKfx8AAyMACAn1HSABAMACACMACAn1HSABAMACAAYABAkrCGYZAcwAAAAA.Dasmonkey:BAAALgAECgIJAgAAAA==.Daxos:BAABLgAECn8mAAIGAAkJ9Bg9QAAAAgAGAAkJ9Bg9QAAAAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJEwAAAA==.Deelahn:BAABLgAECn8cAAMMAAgJrArCKwBHAQAMAAgJrArCKwBHAQANAAEJXAC8fgAWAAAAAA==.Demideudle:BAAALgAECgEJAQAAAA==.Demonicchoas:BAABLgAECn9CAAMWAAkJiSAaAQAmAwAWAAgJJyIaAQAmAwAXAAcJAxzeHgBSAgAAAA==.Denagorn:BAACLgAFFH8IAAMCAAQJAQ4ENQAkAQACAAQJ5g0ENQAkAQAfAAMJeQaVCwCJAAAuAAQKfzwAAgIACQluHRQYANgCAAIACQluHRQYANgCAAEuAAUUCAkkABEArxYA.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAABLgAECn8WAAIDAAkJ4B8kBwAqAwADAAkJ4B8kBwAqAwAAAA==.Deutzfr:BAABLgAECn8dAAMHAAcJMB20LAD2AQAHAAcJMB20LAD2AQAPAAUJLw09FwC+AAAAAA==.',
Di='Dizzleman:BAAALgAECgkJAgAAAA==.',
Do='Dominant:BAABLgAECn8pAAIGAAkJox5jGACtAgAGAAkJox5jGACtAgAAAA==.Dooma:BAABLgAFFH8MAAMXAAgJ8BH6EgC3AQAXAAcJ4hH6EgC3AQAgAAIJSxPRBwCtAAAAAA==.Dorgie:BAAALgAFFAIJAgABLgAFFAIJBgAaAPoaAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIGAAgJSiHeIQDsAgAGAAgJSiHeIQDsAgAAAA==.',
Dr='Draco:BAAALgAECgUJBQAAAA==.Drag:BAAALgAECgQJCgAAAA==.Dragon:BAABLgAECn8YAAIeAAkJFhBdFgDoAQAeAAkJFhBdFgDoAQAAAA==.Dragowolf:BAAALgADCgYJBgAAAA==.Drbob:BAAALgAECgQJBgAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAABLgAFFH8GAAIaAAMJNBkQHgDxAAAaAAMJNBkQHgDxAAABLgAFFAYJFAAhAM0jAA==.Drock:BAABLgAECn8gAAIHAAkJWB4EEACnAgAHAAkJWB4EEACnAgAAAA==.Druidgale:BAABLgAECn8jAAIDAAkJowt4TAA5AQADAAkJowt4TAA5AQAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAABLgAECn8aAAIbAAkJ1xRaEwD4AQAbAAkJ1xRaEwD4AQAAAA==.Drybonez:BAABLgAECn8lAAMKAAgJlBgMKgB0AQAKAAYJrhsMKgB0AQAZAAUJhwiidADEAAAAAA==.Drygth:BAABLgAECn8YAAQNAAkJlyCiDgCZAgANAAcJMCKiDgCZAgAMAAcJ5BqzFAAKAgAkAAEJbwm+VAA4AAAAAA==.',
Du='Dubshox:BAABLgAECn8gAAIKAAgJPRxbGwDaAQAKAAgJPRxbGwDaAQAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ea='Earthly:BAAALgAECgEJAwAAAA==.',
Ei='Eisador:BAABLgAECn8rAAIOAAkJjw9gTwCGAQAOAAkJjw9gTwCGAQAAAA==.',
El='Eldritch:BAAALgADCgcJBwAAAA==.Elemotional:BAABLgAECn8eAAIJAAkJHx3OAwCZAgAJAAkJHx3OAwCZAgAAAA==.',
Em='Emp:BAAALgAECgQJBAAAAA==.',
Eq='Equilibrio:BAABLgAECn8jAAMlAAkJbiDiBgB2AgAlAAgJ5yHiBgB2AgAEAAEJHRaPewBLAAAAAA==.',
Er='Erilee:BAAALgAECgMJAwAAAA==.',
Es='Essos:BAAALgAECgIJAgAAAA==.',
Et='Ettle:BAAALgAECgEJAQABLgAECgUJBgABAAAAAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAABLgAECn8jAAQIAAcJRCGREQAFAgAIAAcJMx+REQAFAgAiAAYJNxmnEgALAQAOAAEJjxpa7QA9AAAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECgkJJAATAEgVAA==.',
Fa='Faelthas:BAACLgAFFH8aAAIbAAUJ9CTHAQDvAQAbAAUJ9CTHAQDvAQAuAAQKfzEAAhsACAksJtkCAGkDABsACAksJtkCAGkDAAAA.Fathercoast:BAABLgAECn8tAAMNAAkJlBxiEQAmAgANAAkJlBxiEQAmAgAkAAcJaRr0HwCUAQAAAA==.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAABLgAECn8YAAMHAAkJqB1UDgC2AgAHAAkJqB1UDgC2AgAPAAIJ7R1jGgChAAAAAA==.Felstrider:BAAALgAECgUJCAAAAA==.Fembouyant:BAABLgAECn8XAAISAAkJtBSIBAAVAgASAAkJtBSIBAAVAgAAAA==.Ferador:BAACLgAFFH8ZAAMOAAcJ+hHiIABEAQAOAAQJOBniIABEAQAiAAUJZwU8EwAKAQAuAAQKfyUAAyIACAkEIAIjAA4CACIACAnFFQIjAA4CAA4ABQmKIfpbAGMBAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.Fistsphoyou:BAAALgAECgEJAQAAAA==.',
Fl='Flowmo:BAAALgAECgYJCAABLgAECggJFwAbANobAA==.',
Fo='Forsakken:BAAALgAECgUJBQAAAA==.Fortou:BAAALgADCgMJAgAAAA==.Fourbees:BAAALgAECgYJDQAAAA==.',
Fr='Frizly:BAABLgAECn8eAAMMAAgJ2AaYNAANAQAMAAgJ2AaYNAANAQANAAEJ5ABffwAQAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIGAAkJ/hGTXQAhAgAGAAkJ/hGTXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.',
Ga='Galdrell:BAABLgAECn8WAAMfAAgJsw2SGAAqAQAfAAgJsw2SGAAqAQACAAEJggB7YQEXAAAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgADCgIJAgAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8nAAMRAAkJKh9LEwAIAwARAAkJKh9LEwAIAwASAAUJBRvpDwAtAQAAAA==.',
Gn='Gnnome:BAABLgAECn8eAAIGAAgJEApOhQBQAQAGAAgJEApOhQBQAQAAAA==.',
Go='Gog:BAAALgAFFAEJAQAAAA==.Goodolruss:BAAALgADCgUJBQAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIYAAkJ3yVfAADPAwAYAAkJ3yVfAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8sAAIRAAkJgRzELAApAgARAAkJgRzELAApAgAAAA==.Grimaldus:BAABLgAECn8ZAAIfAAkJah98BAC9AgAfAAkJah98BAC9AgAAAA==.Grimmble:BAAALgAECgYJCwAAAA==.Grimmortal:BAAALgAECggJCAAAAA==.Grimreaper:BAABLgAECn8qAAMmAAkJuh+QAQC1AgAmAAkJuh+QAQC1AgAaAAIJeRA0UwCRAAAAAA==.Groag:BAABLgAECn8VAAQnAAgJuSG5AQC+AgAnAAgJuSG5AQC+AgAmAAQJMRryFQB7AAAaAAIJ0xvuSQBCAAAAAA==.Groovytony:BAAALgAECgYJBgAAAA==.Grototh:BAAALgAECgcJDwAAAA==.Gruffles:BAABLgAECn8rAAIDAAgJrCLUDQDMAgADAAgJrCLUDQDMAgAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8jAAIHAAkJ5R1oHwA7AgAHAAkJ5R1oHwA7AgAAAA==.',
Ha='Haarp:BAAALgAECgQJBgAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handicat:BAAALgADCgEJAQABLgAECgkJHgANAHIUAA==.Handimage:BAAALgADCgEJAQABLgAECgkJHgANAHIUAA==.Handipriest:BAABLgAECn8eAAINAAkJchSpFQD5AQANAAkJchSpFQD5AQAAAA==.Haqq:BAACLgAFFH8GAAIEAAQJWwVjIQD9AAAEAAQJWwVjIQD9AAAuAAQKfysAAgQACQnbEq4aAPQBAAQACQnbEq4aAPQBAAAA.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgAECgcJDQABLgAECggJEAABAAAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8zAAIRAAgJjRA6XgCKAQARAAgJjRA6XgCKAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgAECgcJDAAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8gAAIRAAkJciD3FQCiAgARAAkJciD3FQCiAgAAAA==.',
Ho='Hoafustis:BAAALgAECgEJAQAAAA==.Hobo:BAABLgAECn8WAAIOAAYJ9xHWdwAhAQAOAAYJ9xHWdwAhAQAAAA==.Hollowshädix:BAAALgAECgMJAwAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBQAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Hundard:BAAALgAECgQJBQAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAABLgAECn8ZAAIoAAkJKSMPAQA1AwAoAAkJKSMPAQA1AwABLgAECggJKgAEADomAA==.Iblisshaytan:BAABLgAECn8XAAMVAAcJOBXKHgBIAQAVAAcJOBXKHgBIAQAHAAUJJAtmmQDoAAABLgAFFAUJCgAGAAoPAA==.Ibtrollin:BAAALgAECgUJCQAAAA==.',
Ic='Icepak:BAAALgADCgUJBQAAAA==.',
Ig='Ignacious:BAACLgAFFH8FAAIZAAMJ5QjIOwC/AAAZAAMJ5QjIOwC/AAAuAAQKfy8ABBkACQkKJOMCAFADABkACQkKJOMCAFADAAoABwlTG3wmAIoBAAkAAQlWDxUsADUAAAAA.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAABLgAECn8nAAIoAAgJrRYdCwDWAQAoAAgJrRYdCwDWAQAAAA==.Immolate:BAABLgAECn8aAAQXAAkJzyEHNgA0AgAXAAcJbx8HNgA0AgAWAAUJsCKSFgCVAQAgAAEJAAAzJABhAAAAAA==.',
In='Infamous:BAAALgAECggJEgAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJEQAAAA==.',
Io='Ionissa:BAAALgAECgcJBwAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAwAAAA==.',
Is='Ischia:BAACLgAFFH8WAAIMAAUJ/xBGAgCNAQAMAAUJ/xBGAgCNAQAuAAQKfyIAAwwACAkdEjUgAOABAAwACAkdEjUgAOABAA0ABgkbCnJGAMgAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIaAAIJpx+nEADFAAAaAAIJpx+nEADFAAAuAAQKfxgAAhoABwliI8MXAEsCABoABwliI8MXAEsCAAAA.Jallypally:BAAALgADCggJCQAAAA==.Jamuel:BAAALgAECgkJCAAAAA==.Janokdiso:BAAALgAECgEJAQABLgAECgkJKAAGAHYfAA==.Javaman:BAAALgADCgMJAwABLgADCgQJBAABAAAAAA==.Javeighqueas:BAAALgADCgQJAgABLgAFFAMJCQARAN8SAA==.',
Jc='Jch:BAACLgAFFH8cAAMOAAgJchp+AADCAQAOAAcJDBp+AADCAQAiAAEJ1hw3IwBWAAAuAAQKfyIAAw4ACQllJP0BAH8DAA4ACQllJP0BAH8DACIAAQmiB06PACwAAAAA.',
Je='Jedijed:BAAALgAFFAIJAgABLgAFFAMJCwACAMkUAA==.Jedikepjr:BAACLgAFFH8LAAICAAMJyRSxSADxAAACAAMJyRSxSADxAAAuAAQKfxQAAgIABwnTHBFSALQBAAIABwnTHBFSALQBAAAA.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECggJCwAAAA==.Joneztown:BAABLgAECn8WAAIcAAkJQRq5CwC/AgAcAAkJQRq5CwC/AgAAAA==.Jordantheorc:BAABLgAECn8nAAMOAAkJihxFEQCvAgAOAAkJihxFEQCvAgAiAAIJvwLsgQBAAAAAAA==.',
Jp='Jprottsoo:BAACLgAFFH8JAAIQAAMJlBo6HwD9AAAQAAMJlBo6HwD9AAAuAAQKfygAAhAACQnvIYMDABMDABAACQnvIYMDABMDAAAA.',
Jt='Jtee:BAABLgAECn8sAAMhAAgJehXaJAC5AQAhAAgJehXaJAC5AQACAAEJbAqNYwExAAAAAA==.',
Ju='Jukkrit:BAAALgAECgEJAQAAAA==.',
Jy='Jy:BAAALgADCgMJAwAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8kAAIDAAkJ2wrBSgBBAQADAAkJ2wrBSgBBAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECgkJHgAgAOAYAA==.Karoo:BAAALgADCgYJBgAAAA==.Kataris:BAAALgAECgEJAQABLgAECggJHwAOANkdAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAgAAAA==.Keizzer:BAABLgAECn8kAAICAAkJlx8OHgC3AgACAAkJlx8OHgC3AgAAAA==.Kelesa:BAAALgADCgEJAQAAAA==.Keshisaru:BAABLgAECn8UAAIOAAgJehS6JgAfAgAOAAgJehS6JgAfAgAAAA==.',
Kh='Kharms:BAABLgAECn8iAAIcAAkJ1B9gBgDFAgAcAAkJ1B9gBgDFAgAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.',
Kl='Klunder:BAABLgAECn8fAAIZAAkJlx6BCgDlAgAZAAkJlx6BCgDlAgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIbAAgJ2hvTFABmAgAbAAgJ2hvTFABmAgAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAABLgAECn8fAAIOAAkJwxtfIQA2AgAOAAkJwxtfIQA2AgAAAA==.Kostik:BAAALgAECgQJBAAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAACLgAFFH8FAAIHAAMJzwlgUQDFAAAHAAMJzwlgUQDFAAAuAAQKfycAAgcACQlhGS4cAE4CAAcACQlhGS4cAE4CAAAA.Krux:BAAALgAECgIJBAAAAA==.',
Ky='Kybinc:BAAALgADCgQJBAAAAA==.',
['Kí']='Kírã:BAAALgAECgMJAwAAAA==.',
La='Lacie:BAAALgADCgkJDAAAAA==.Laennaya:BAABLgAECn82AAIgAAkJaw3oBwC4AQAgAAkJaw3oBwC4AQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAABLgAECn8YAAIGAAYJywc4wQDqAAAGAAYJywc4wQDqAAAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgMJCQAAAA==.Lazybigger:BAAALgAECgEJAQAAAA==.Lazyfrost:BAABLgAECn8oAAIGAAkJdh8dDAACAwAGAAkJdh8dDAACAwAAAA==.Lazyunholy:BAAALgAECgEJAQABLgAECgkJKAAGAHYfAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8fAAMhAAgJYSCWEwB2AgAhAAgJYSCWEwB2AgACAAEJZA4ZPwE1AAAAAA==.Lethô:BAACLgAFFH8HAAIDAAMJXyCpIAAiAQADAAMJXyCpIAAiAQAuAAQKfzMAAwMACQkKIrMCAIoDAAMACQkKIrMCAIoDABAAAQk7ErVzADcAAAAA.Lethö:BAAALgAECgMJAwAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Lickemlow:BAAALgAECgEJAQAAAA==.Liesx:BAAALgAECgEJAQAAAA==.Lilboothang:BAABLgAECn8ZAAIXAAgJaRMESgCmAQAXAAgJaRMESgCmAQAAAA==.Lillìth:BAAALgAECgYJCgAAAA==.Lilzarthe:BAAALgAFFAEJAQAAAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Loachella:BAAALgADCgUJBQAAAA==.Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAACLgAFFH8JAAIHAAMJHCa3JgBLAQAHAAMJHCa3JgBLAQAuAAQKfzIAAgcACQneJRgCALcDAAcACQneJRgCALcDAAAA.Loko:BAACLgAFFH8aAAIQAAcJPhsGBAAVAgAQAAcJPhsGBAAVAgAuAAQKfzYAAhAACQmAJEwCAD8DABAACQmAJEwCAD8DAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAFFAEJAQAAAA==.Louiie:BAABLgAECn8dAAIaAAgJShLDGQCiAQAaAAgJShLDGQCiAQAAAA==.',
Lu='Luckygrapes:BAACLgAFFH8LAAIdAAQJBRvlFABgAQAdAAQJBRvlFABgAQAuAAQKfxsAAh0ACAmqHs8OAGkCAB0ACAmqHs8OAGkCAAAA.Lukdanuke:BAAALgAECgYJCgAAAA==.Lumi:BAAALgAECgEJAgAAAA==.Luxxus:BAAALgAECgcJCwABLgAECgkJJAACAJcfAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAABLgAECn8dAAIKAAgJdRBFLwBWAQAKAAgJdRBFLwBWAQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8gAAIXAAkJXQ9ARQC0AQAXAAkJXQ9ARQC0AQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAIcAAcJnh0NFABPAgAcAAcJnh0NFABPAgAAAA==.Mantakore:BAACLgAFFH8SAAIeAAUJzQnsEQA8AQAeAAUJzQnsEQA8AQAuAAQKfzQAAh4ACAmOGaYLAPkBAB4ACAmOGaYLAPkBAAAA.Marcdruid:BAAALgAECgUJBwAAAA==.Maubles:BAAALgAECgYJEQABLgAFFAQJFAAfAFgPAA==.',
Me='Meadöw:BAABLgAECn8XAAIDAAgJEhD0NwCVAQADAAgJEhD0NwCVAQAAAA==.Meiling:BAAALgAECgUJBQAAAA==.Meladra:BAAALgAECgEJAQAAAA==.Menopaws:BAABLgAECn8ZAAQpAAkJvCDkBACXAgApAAkJqiDkBACXAgAoAAYJphZGEgBdAQAQAAQJghGqYACfAAAAAA==.Mertrik:BAABLgAECn8dAAMKAAkJghu8EAChAgAKAAkJghu8EAChAgAJAAEJuBiBKQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8lAAIYAAkJlx9sCwBdAgAYAAkJlx9sCwBdAgAAAA==.Mikailla:BAAALgAFFAIJAwABLgAECgEJAQABAAAAAA==.Mikayy:BAACLgAFFH8TAAMaAAYJEiQjBACzAQAaAAUJAiUjBACzAQAnAAEJUSAxCgBjAAAuAAQKfzIAAxoACQk5JrMEANECABoACQnOJbMEANECACcAAQmSJhEZAHIAAAAA.Milenko:BAABLgAECn8uAAIVAAgJLSUZBADiAgAVAAgJLSUZBADiAgAAAA==.Milly:BAAALgAECgMJBgABLgAECggJLgAVAC0lAA==.Mimid:BAAALgAECgYJDgAAAA==.Mimonk:BAAALgAECgQJBAAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minii:BAAALgAECgYJBgAAAA==.Minteafresh:BAAALgAECgQJBwAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8VAAMEAAcJbxJUBQCdAQAEAAYJ9xRUBQCdAQAFAAIJrQlsJAB+AAAuAAQKfyQAAwQACAnuHe8RAMACAAQACAnuHe8RAMACAAUABAk3Gc0YADABAAAA.Moort:BAAALgAECgYJDwAAAA==.Moothafacka:BAAALgADCgcJBwAAAA==.Mordecaii:BAAALgAECgcJBAAAAA==.Morganlefay:BAAALgADCgcJEgAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAABLgAECn8UAAIRAAgJ1ArFeQBKAQARAAgJ1ArFeQBKAQAAAA==.Moyana:BAAALgAECgQJBQAAAA==.',
Ms='Msbehaven:BAABLgAECn8bAAIXAAgJnwVUjQAKAQAXAAgJnwVUjQAKAQAAAA==.',
Mt='Mthafknfreez:BAACLgAFFH8KAAIGAAUJCg8lXAACAQAGAAUJCg8lXAACAQAuAAQKfycAAgYACQm3Gb4nAF8CAAYACQm3Gb4nAF8CAAAA.',
My='Mynuturchin:BAAALgAECgYJDgAAAA==.',
['Mî']='Mîg:BAABLgAECn8jAAIHAAkJoRBJSgCFAQAHAAkJoRBJSgCFAQAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJCAABLgAECgQJFAADAAIWAA==.Nahtikal:BAABLgAECn8hAAMdAAgJQRS0IADRAQAdAAgJQRS0IADRAQAcAAYJSg2lOQDtAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgcJCQABLgAECgkJJwARACofAA==.',
Ne='Neytiri:BAAALgADCggJEAAAAA==.',
Ni='Nilfalath:BAAALgAECgYJDgAAAA==.Nippy:BAAALgAECgUJCgABLgAECgYJBgABAAAAAA==.',
No='Noriva:BAAALgAECgMJBAAAAA==.Notthechosen:BAAALgAECgEJAQABLgAFFAQJDgAEAB0OAA==.',
Ny='Nymeriã:BAABLgAECn8WAAMDAAYJygg7aADbAAADAAYJygg7aADbAAAQAAUJfwTXXgBnAAAAAA==.Nymeriå:BAAALgADCggJCQAAAA==.',
Ob='Obzy:BAAALgADCgYJBgABLgAFFAMJCQARAN8SAA==.Obzz:BAACLgAFFH8JAAIRAAMJ3xJvcgDoAAARAAMJ3xJvcgDoAAAuAAQKfxkAAhEACQk5HMoeAG0CABEACQk5HMoeAG0CAAAA.',
Od='Odiedude:BAAALgAECgYJBgAAAA==.Odieous:BAABLgAECn8YAAIhAAkJPRkeDACoAgAhAAkJPRkeDACoAgAAAA==.',
Ok='Okamy:BAABLgAECn8dAAIRAAkJbx/CFgCcAgARAAkJbx/CFgCcAgABLgAECgcJIwAIAEQhAA==.',
Om='Omeganemesis:BAAALgADCgQJBAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8tAAMHAAgJhBjKOAASAgAHAAgJ9xfKOAASAgAVAAgJkg/0GgBsAQABLgAFFAMJCQARAN8SAA==.',
Or='Orghujon:BAAALgAECgUJCQAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgAECgkJEgAAAA==.Palamon:BAAALgAECgYJDAAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBgAAAA==.Papadaddy:BAAALgADCgUJBQAAAA==.Parthos:BAAALgAECggJDQAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAACLgAFFH8WAAIbAAQJ3x8ZEQBgAQAbAAQJ3x8ZEQBgAQAuAAQKfxsAAhsABwnWI/sLAFYCABsABwnWI/sLAFYCAAAA.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgAECgEJAQAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAABLgAFFH8GAAIHAAMJrxn1QQD3AAAHAAMJrxn1QQD3AAABLgAFFAQJFgAbAN8fAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.Piyre:BAAALgAECgEJAgAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pocus:BAAALgAECgkJCwABLgAECggJIQAHAHAbAA==.Pokedone:BAAALgAECgIJAgAAAA==.Polskashaman:BAABLgAECn8fAAIJAAgJahLJDwB6AQAJAAgJahLJDwB6AQAAAA==.Poptart:BAACLgAFFH8LAAICAAQJJgtsNwAeAQACAAQJJgtsNwAeAQAuAAQKfxoAAgIACAlLFCBdAMsBAAIACAlLFCBdAMsBAAAA.Power:BAAALgAFFAIJAgABLgAFFAYJGAACAPElAA==.',
Pr='Prea:BAAALgAECgUJCgAAAA==.Premiumferal:BAAALgAECgYJDgABLgAECgkJJwARACofAA==.Primecarry:BAACLgAFFH8UAAIhAAYJzSM+BAA3AgAhAAYJzSM+BAA3AgAuAAQKfyMAAyEACAkCI6EJANcCACEACAkCI6EJANcCAB8ABgkfIBsNAMUBAAAA.',
Pu='Puhtater:BAAALgAECgIJBAAAAA==.Pumpmedaddy:BAAALgAECgUJBQAAAA==.Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgYJEwAAAA==.',
['Pë']='Pëpsï:BAAALgAECgcJEQAAAA==.',
Qu='Quanah:BAAALgAECgUJCwAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgABAAAAAA==.Ragecritz:BAABLgAFFH8FAAMFAAQJaQEgJQB4AAAFAAMJtwEgJQB4AAAEAAEJgAClRQAPAAAAAA==.Raigko:BAAALgAECgcJCwAAAA==.Raintolin:BAAALgAECgYJEAABLgAFFAMJBgARAKMbAA==.Raiva:BAAALgAECgYJCAABLgAFFAMJCgARAGYaAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Raspberri:BAAALgAECgEJAQAAAA==.Rassputen:BAABLgAECn8tAAIYAAkJRhmDDQACAgAYAAkJRhmDDQACAgAAAA==.',
Re='Redjive:BAAALgAECgYJCAAAAA==.Redonkulos:BAABLgAFFH8GAAIaAAIJ+hqsJgCbAAAaAAIJ+hqsJgCbAAAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAbAPwPAA==.Redthorne:BAAALgADCgMJAwAAAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAACLgAFFH8OAAMNAAQJABvxDABgAQANAAQJABvxDABgAQAMAAMJFh65EQAMAQAuAAQKfyAAAw0ACAlTIxUTAF0CAA0ABwnjIxUTAF0CAAwABwnmGt0tADgBAAAA.Reliri:BAAALgAECgYJCAAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgkJFQAAAA==.Rider:BAAALgADCgYJBgABLgAFFAcJGgAhAJYYAA==.Rinth:BAABLgAECn8iAAMiAAkJPCL6CQAEAwAiAAgJpSH6CQAEAwAOAAMJ2ySHcgAtAQAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIfAAgJQhpCCABWAgAfAAgJQhpCCABWAgAAAA==.Roguen:BAABLgAECn87AAIaAAkJexShEQD2AQAaAAkJexShEQD2AQABLgAFFAUJCgAGAAoPAA==.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAABLgAECn8UAAIZAAgJIQwyXAARAQAZAAgJIQwyXAARAQABLgAFFAYJFAAiABALAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAABLgAECn8VAAIlAAcJ6RckEgCfAQAlAAcJ6RckEgCfAQAAAA==.Roulduke:BAABLgAECn8oAAIKAAkJMxFEHwC8AQAKAAkJMxFEHwC8AQAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Rylearria:BAAALgADCgMJAwAAAA==.Ryna:BAAALgADCgkJCAAAAA==.',
['Rù']='Rùckús:BAABLgAECn8sAAIRAAkJFR8eFACvAgARAAkJFR8eFACvAgAAAA==.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8vAAMfAAgJswwyGQAkAQAfAAgJswwyGQAkAQACAAEJbgVydAEqAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAECgcJHQAHADAdAA==.Sakiara:BAAALgAECgQJBgAAAA==.Salaen:BAAALgAECgkJCQAAAA==.Sammybeans:BAABLgAECn8kAAICAAkJMhcYPADzAQACAAkJMhcYPADzAQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAABLgAECn8fAAIOAAgJ2R1LHABSAgAOAAgJ2R1LHABSAgAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAABLgAECn8UAAIYAAgJxgMANgCQAAAYAAgJxgMANgCQAAAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Sc='Scrandle:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.Screwball:BAAALgADCgEJAQAAAA==.',
Se='Seceron:BAAALgAECggJEQAAAA==.Sekai:BAAALgAFFAMJAwAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8kAAMMAAgJ3gZASQAUAQAMAAYJiwhASQAUAQANAAgJNARPPAD3AAAAAA==.Serpentsin:BAAALgAECgMJBAAAAA==.',
Sg='Sgtslappy:BAABLgAECn85AAIEAAkJqx8lCgCgAgAEAAkJqx8lCgCgAgAAAA==.',
Sh='Shanarelle:BAACLgAFFH8GAAIDAAMJmgqUNgC4AAADAAMJmgqUNgC4AAAuAAQKfxoAAgMACAnPGR4eAE0CAAMACAnPGR4eAE0CAAAA.Shasa:BAACLgAFFH8IAAIOAAMJsQz/RgDaAAAOAAMJsQz/RgDaAAAuAAQKfy0AAg4ACQnhGegZAG0CAA4ACQnhGegZAG0CAAAA.Shatteredsky:BAAALgAECggJDgAAAA==.Shazik:BAAALgAECgEJAQAAAA==.Sheroko:BAAALgAECgEJAQAAAA==.Shilbalam:BAAALgAECgEJAQAAAA==.Shinanìgans:BAAALgAECgYJBgAAAA==.Shmoopy:BAAALgAECgYJBgAAAA==.Shortyman:BAAALgAECgUJBwABLgAECgkJJwARACofAA==.Shruikan:BAABLgAECn8UAAQTAAcJTRk+HADlAQATAAcJ2Rg+HADlAQAUAAcJ7g8NGQBvAQAeAAMJlgWuPACFAAAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgYJFwARABsaAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAACLgAFFH8KAAIRAAMJZhp6YAAMAQARAAMJZhp6YAAMAQAuAAQKfzMAAxEACQlzHcQYAJACABEACQlCHMQYAJACABgAAgkCHV46AHkAAAAA.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAgAAAA==.Sisturfistur:BAAALgAECgQJBgAAAA==.',
Sk='Skunkpaw:BAAALgADCgYJEQAAAA==.Skysong:BAACLgAFFH8WAAMUAAcJfxBVAQCmAQAUAAUJ9Q9VAQCmAQATAAUJNgyYHAAtAQAuAAQKfyEABBQACAnJHc4MAA4CABQABwlhG84MAA4CAB4ABwlqFzYMAOwBABMAAwnVF0xCANoAAAAA.',
Sl='Slashedeye:BAABLgAECn81AAIjAAkJvhlFAgA3AgAjAAkJvhlFAgA3AgAAAA==.',
Sm='Smallfoot:BAAALgAECgEJAQAAAA==.Smellsoftree:BAAALgAECgQJBAAAAA==.',
Sn='Snowynn:BAABLgAECn8rAAMpAAkJAxOQDQDOAQApAAkJAxOQDQDOAQADAAEJWwHx6gAZAAAAAA==.Snubby:BAABLgAECn8pAAMXAAkJEyQSCwDhAgAXAAcJKSUSCwDhAgAWAAUJuSJ0DAD7AQAAAA==.',
So='Soleil:BAABLgAECn8VAAMNAAkJkQ9qLAB6AQANAAkJkQ9qLAB6AQAkAAQJuw89SwCSAAAAAA==.Solheim:BAACLgAFFH8PAAMIAAUJRxq6CABmAQAIAAUJKBq6CABmAQAiAAIJHB2jGgCvAAAuAAQKfyQAAyIACAkYI9kKAPgCACIACAkoItkKAPgCAAgABAlFHfwyAO8AAAAA.Souffle:BAACLgAFFH8IAAIXAAMJHAomZADPAAAXAAMJHAomZADPAAAuAAQKfyIAAxcABwlAGQNMAOUBABcABwlAGQNMAOUBABYAAQkAAHVtADoAAAEuAAUUBQkQAAIASRkA.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMbAAgJ/A8ZMgCJAQAbAAgJ/A8ZMgCJAQAcAAEJ/wcEiAAsAAAAAA==.Spookypink:BAABLgAECn8ZAAICAAkJkCJHEAANAwACAAkJkCJHEAANAwAAAA==.Spárda:BAAALgAECgMJAwABLgAECgcJIwAIAEQhAA==.',
Sq='Squirtz:BAAALgAECgYJBgAAAA==.',
Sr='Srirachajane:BAAALgADCgkJDQABLgAECggJGQAoADAbAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Starwon:BAAALgADCgIJAgAAAA==.Strathin:BAAALgADCgkJDQAAAA==.Strathz:BAABLgAECn8lAAMWAAkJpCCeCgAVAgAWAAYJPx+eCgAVAgAXAAcJjh7vPADPAQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIhAAgJ1hq3GABNAgAhAAgJ1hq3GABNAgAAAA==.Summerset:BAAALgAECgYJEAAAAA==.Sushi:BAAALgAECgYJCAAAAA==.',
Sy='Sylatis:BAACLgAFFH8sAAMIAAkJCyAQAAAoAwAIAAkJCyAQAAAoAwAiAAYJiRTMAwAHAgAuAAQKfxYAAyIACAk0JVsNANsCACIACAk0JVsNANsCAAgAAwmkHggoAHUAAAAA.Sylvara:BAAALgAECgMJBgAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.Sylätis:BAAALgAFFAIJAwABLgAFFAkJLAAIAAsgAA==.',
['Sö']='Söultender:BAABLgAECn8lAAQkAAgJGBWXGwDEAQAkAAgJBg+XGwDEAQAMAAUJABOaNgAAAQANAAEJvAlNYwAyAAAAAA==.',
Ta='Taichi:BAACLgAFFH8UAAIdAAUJ2hMdGAA8AQAdAAUJ2hMdGAA8AQAuAAQKfyIAAh0ACAkAHksMAI4CAB0ACAkAHksMAI4CAAAA.Talys:BAACLgAFFH8bAAIeAAgJ/BgBAgCcAgAeAAgJ/BgBAgCcAgAuAAQKfysAAh4ACQlAHIcIALICAB4ACQlAHIcIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgADCgUJBQAAAA==.Tarth:BAACLgAFFH8aAAIpAAcJESKxAABmAgApAAcJESKxAABmAgAuAAQKfyMAAikACAkEJmwBAEEDACkACAkEJmwBAEEDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8mAAIeAAgJNBvmBwBUAgAeAAgJNBvmBwBUAgAAAA==.Taïko:BAAALgADCgQJBAAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgYJDQABLgAFFAMJBgARAKMbAA==.Tenniell:BAAALgAECgQJDQAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAABLgAECn8lAAIGAAkJhxfNKABaAgAGAAkJhxfNKABaAgAAAA==.',
Th='Thab:BAAALgAECgYJDAABLgAECgkJJAATAEgVAA==.Thabk:BAABLgAECn8kAAMTAAkJSBU0GwDcAQATAAkJSBU0GwDcAQAUAAEJaAdCQwAoAAAAAA==.Thaelorn:BAAALgAECgMJAwAAAA==.Thakb:BAAALgAECgMJAwABLgAECgkJJAATAEgVAA==.Tharit:BAAALgADCgYJCgAAAA==.Theodius:BAAALgAECgQJBAAAAA==.Theshortbuss:BAABLgAECn8aAAMCAAcJURhuUQC1AQACAAcJURhuUQC1AQAfAAEJogG7TwAQAAAAAA==.Thesuffering:BAAALgAECgUJBwAAAA==.Thesyra:BAAALgAECggJDAAAAA==.Thingtwò:BAAALgADCgUJBQAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDgAAAA==.',
Ti='Tiddybear:BAAALgAECgkJDwAAAA==.Timerunhunt:BAAALgADCgUJBgAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAABLgAECn8WAAIYAAcJSQiKLQDAAAAYAAcJSQiKLQDAAAAAAA==.Toastz:BAAALgAFFAEJAQAAAA==.Tokken:BAACLgAFFH8PAAIEAAQJXxJrGwAgAQAEAAQJXxJrGwAgAQAuAAQKfyIAAgQACQnpHEcMAPYCAAQACQnpHEcMAPYCAAAA.',
Tr='Treebeast:BAACLgAFFH8GAAIKAAMJDROBFwCXAAAKAAMJDROBFwCXAAAuAAQKfxUAAgoABwlnH4kcAC0CAAoABwlnH4kcAC0CAAAA.Treediddy:BAABLgAFFH8GAAIpAAQJZxOACgD6AAApAAQJZxOACgD6AAABLgAFFAQJFgAbAN8fAA==.Troile:BAAALgAECgcJCQAAAA==.Trojen:BAAALgADCgcJBwAAAA==.Trolladin:BAAALgAECgEJAQABLgAECgUJCQABAAAAAA==.',
Tu='Tubularoso:BAABLgAECn8WAAIWAAcJ6g+FDgApAQAWAAcJ6g+FDgApAQAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Tw='Twobtn:BAAALgAECgUJBQAAAA==.',
Ty='Tyras:BAAALgADCgYJBgAAAA==.',
Ul='Ulanda:BAABLgAECn8gAAQDAAcJVw1LSgBDAQADAAcJVw1LSgBDAQApAAMJmQLqTwA5AAAQAAEJqwHHjwAcAAAAAA==.',
Um='Umako:BAACLgAFFH8OAAMnAAUJjx6WAQBvAQAnAAQJcyCWAQBvAQAaAAIJAxwqEwCzAAAuAAQKfyEAAycACQmuIfIAAEQDACcACQmUIfIAAEQDABoACAlGFyYdABYCAAAA.',
Un='Underbogg:BAAALgAECgEJAQAAAA==.Unus:BAAALgADCgQJBAABLgAECgkJKQAGAKMeAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Ux='Ux:BAAALgAECgcJBwAAAA==.',
Va='Vaedric:BAAALgAECgIJAwAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgcJEQAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAACLgAFFH8OAAIEAAQJHQ4HGwAiAQAEAAQJHQ4HGwAiAQAuAAQKfx4AAgQACAkRG70nAB8CAAQACAkRG70nAB8CAAAA.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8qAAIEAAgJOiYvBQD0AgAEAAgJOiYvBQD0AgAAAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8cAAIHAAgJfQ08XwBHAQAHAAgJfQ08XwBHAQAAAA==.Voids:BAAALgADCgcJDAAAAA==.Voodoochild:BAAALgAECgEJAQAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAABLgAFFH8IAAMIAAQJtg7bDwAzAQAIAAQJtg7bDwAzAQAiAAMJmgiZFQDIAAABLgAFFAYJFAAiABALAA==.',
Vy='Vyzerion:BAAALgAECgYJBgABLgAECgcJIwAIAEQhAA==.',
['Vé']='Vénandi:BAAALgAECgIJAgAAAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgABAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMZAAgJwBqHIwAKAgAZAAgJwBqHIwAKAgAKAAQJ7AVJawBuAAAAAA==.',
Wa='Walkerwhite:BAAALgAECgkJDwABLgAECggJIQANAN0ZAA==.Warjd:BAABLgAECn8aAAIEAAgJQQxlMABlAQAEAAgJQQxlMABlAQAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Weebo:BAAALgADCgYJCQAAAA==.Wesjin:BAABLgAECn8aAAIdAAkJcRq2DgBrAgAdAAkJcRq2DgBrAgAAAA==.Wez:BAABLgAECn8VAAICAAgJDQkWiwA5AQACAAgJDQkWiwA5AQAAAA==.',
Wh='Whiskee:BAACLgAFFH8SAAIoAAQJ/hmEAwBhAQAoAAQJ/hmEAwBhAQAuAAQKfysABCgACQl5I7QEAM0CACgACQl5I7QEAM0CAAMABwn0D49IAEkBABAAAQn/E6VxADsAAAAA.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Wintulyn:BAAALgAECgYJCQAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgADCggJFwAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wr='Wrattchild:BAAALgADCgYJBgAAAA==.',
Wy='Wyndia:BAAALgAECgYJCwAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJCQABLgAECggJJQAkABgVAA==.',
Xb='Xbert:BAAALgAECgMJAwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8XAAIGAAcJDBhQFADoAQAGAAcJDBhQFADoAQAuAAQKfxwAAgYACAn+IZIuALgCAAYACAn+IZIuALgCAAAA.Xerlk:BAAALgAECgUJCAAAAA==.',
Xi='Xihuang:BAAALgAECgcJCwABLgAFFAUJCgAGAAoPAA==.Xiia:BAABLgAECn8nAAIiAAkJCR4JBABdAgAiAAkJCR4JBABdAgAAAA==.',
Xx='Xxoouu:BAABLgAFFH8RAAIdAAcJuQ/UCgDkAQAdAAcJuQ/UCgDkAQAAAA==.Xxuu:BAAALgAFFAYJAQABLgAFFAcJEQAdALkPAA==.Xxuublue:BAAALgAFFAYJAQAAAA==.Xxuuvoker:BAAALgAECgkJCQABLgAFFAcJEQAdALkPAA==.',
Ya='Yaoguai:BAABLgAECn8fAAMQAAkJNhJnHAC4AQAQAAkJNhJnHAC4AQADAAEJwAPE4wAhAAAAAA==.Yasei:BAAALgAECgYJBwAAAA==.Yawgmoth:BAABLgAECn8eAAMgAAkJ4Bi7AgBxAgAgAAkJ4Bi7AgBxAgAXAAEJKgzuGwEzAAAAAA==.',
Yd='Ydalflow:BAAALgADCgkJDQAAAA==.',
Za='Zammboomafoo:BAABLgAECn8bAAIfAAYJXyHKDQC4AQAfAAYJXyHKDQC4AQAAAA==.Zanian:BAABLgAECn8dAAMDAAgJ8RXfKQDkAQADAAgJ8RXfKQDkAQAoAAIJoAOtNQBKAAAAAA==.Zarthie:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Zarthy:BAABLgAECn8WAAITAAcJyBO7JACXAQATAAcJyBO7JACXAQABLgAFFAEJAQABAAAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgcJEgAAAA==.Zerra:BAAALgAECgEJAgAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zi='Zip:BAAALgADCgkJCQAAAA==.',
Zo='Zodd:BAAALgADCgEJAwAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgUJCwABLgAECgkJRQAGAA4lAA==.Zuo:BAAALgAECgMJBAAAAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAIoAAgJMBv3BQCjAgAoAAgJMBv3BQCjAgAAAA==.',
['Zà']='Zàánn:BAABLgAECn8dAAIKAAcJTRSmLgBZAQAKAAcJTRSmLgBZAQAAAA==.',
['Ær']='Æris:BAAALgAECgQJBAAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAFFAUJEwAjAIccAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAFFAUJEwAjAIccAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgAECgYJCwAAAA==.',
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
