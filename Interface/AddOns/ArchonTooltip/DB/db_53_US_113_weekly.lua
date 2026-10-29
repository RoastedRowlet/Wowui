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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Druid-Restoration','Priest-Holy','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Druid-Balance','Warrior-Protection','Evoker-Preservation','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','DemonHunter-Vengeance','Priest-Shadow','Hunter-Marksmanship','Priest-Discipline','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg7W+wCVAQABAAcKrg7W+wCVAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgIIAwAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.Aksala:BAAANQABCgIIAgAAAA==.',
Al='Alaralia:BAAANQAECggIEwABNQAFFAgIFwACACEeAA==.Alarathel:BAAANQADCggICAABNQAFFAgIFwACACEeAA==.Aleion:BAAANQADCgUIBQABNQAECgkJIwADAMgSAA==.Alyssandra:BAABNQAECn8bAAMEAAkKdQz7HgB3AQAEAAcKWw/7HgB3AQAFAAYK9ASijgDTAAAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIEQAAAA==.Ammalane:BAAANQADCgQIBQABNQADCggIEQAGAAAAAA==.',
An='Anabelli:BAAANQAECgEIAQAAAA==.Angler:BAAANQADCgIIAQAAAA==.',
Ap='Apollyon:BAABNQAECn8UAAIHAAoKpBJXWQCNAQAHAAoKpBJXWQCNAQAAAA==.',
Ar='Arangarr:BAABNQAECn88AAIIAAoKJCBWAwB0AwAIAAoKJCBWAwB0AwAAAA==.Arcanu:BAAANQAECgQICwAAAA==.Aresiuz:BAABNQAECn8eAAIJAAkKoRbBPwC1AQAJAAkKoRbBPwC1AQABNQAFFAcIFAAKAGYJAA==.Areyana:BAAANQAECgUIDgAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQAECgQICwAAAA==.Arrietty:BAABNQAECn8VAAILAAUKIhNdZQARAQALAAUKIhNdZQARAQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAABNQAECn8dAAMMAAoKZwqhFABjAQAMAAoKZwqhFABjAQANAAYK+AaWHQHuAAAAAA==.',
As='Asmodea:BAAANQAECgEIAQAAAA==.',
At='Atlasfall:BAAANQAECgcIEwAAAA==.',
Az='Azeriall:BAABNQAECn9AAAIOAAoK2xcFHwAEAgAOAAoK2xcFHwAEAgAAAA==.Azerodru:BAAANQADCgEIAQAAAA==.',
Ba='Bacnfen:BAABNQAECn8aAAIOAAgKiQrPXwDtAAAOAAgKiQrPXwDtAAAAAA==.Baconhammr:BAAANQAECgEIAQAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAAGAAAAAA==.Banshiï:BAABNQAECn8WAAIEAAgKQQYlKQAyAQAEAAgKQQYlKQAyAQAAAA==.Baratheøn:BAABNQAECn8cAAMIAAgKUxYcFwC+AQAIAAgKUxYcFwC+AQAPAAEK2gJfdgAiAAAAAA==.Bason:BAAANQAECggICwAAAA==.',
Be='Beeftard:BAABNQAECn8hAAILAAkKVxsdNgCLAgALAAkKVxsdNgCLAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAgAAAA==.Bippity:BAAANQAECgQICQAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgcIDQAAAA==.',
Bo='Bobbyg:BAAANQAECgEIAgAAAA==.Bollace:BAAANQADCgUIBQABNQADCgcIBwAGAAAAAA==.',
By='Byzantium:BAABNQAECn8hAAIQAAcKrAdEGgDAAAAQAAcKrAdEGgDAAAAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICQAAAA==.',
Ca='Caluu:BAAANQAECgYIEgAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwARAK4SAA==.Celitha:BAAANQADCgcIBwAAAA==.',
Ch='Chromatic:BAAANQAECgUIBAAAAA==.Chronic:BAAANQAECgIIBAABNQAECgoKKwANAGoUAA==.',
Ci='Cinderflamez:BAAANQAECgEIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAABNQADCggICAAGAAAAAA==.Coldstorm:BAABNQAECn8gAAISAAkK4A44DAD4AQASAAkK4A44DAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAABNQAECn8cAAIEAAYKUwWZNADxAAAEAAYKUwWZNADxAAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn8/AAITAAoK3BpfIwBXAgATAAoK3BpfIwBXAgAAAA==.',
Da='Daddyelessar:BAAANQAECgcICAAAAA==.Daemonfyre:BAAANQADCgEIAQAAAA==.Dafattyup:BAABNQAECn8gAAIFAAgKyA/GpgCGAQAFAAgKyA/GpgCGAQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAAANQAECgMIBwAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFH8VAAIUAAUKQiQmAQCJAQAUAAUKQiQmAQCJAQA1AAQKfzkAAhQACgpHJpAAAIADABQACgpHJpAAAIADAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQAECgEIAQAAAA==.Deathblitz:BAAANQAECgcIDQABNQAECgoKFAAHAKQSAA==.Deathlydruid:BAAANQAECgEIBgAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAABNQAECn8ZAAIHAAYKSAyJOwD0AAAHAAYKSAyJOwD0AAAAAA==.Deeanndra:BAABNQAECn8dAAIUAAgKzwq4cgBMAQAUAAgKzwq4cgBMAQAAAA==.Demiz:BAABNQAECn8yAAIKAAoKoxQkXwDxAQAKAAoKoxQkXwDxAQAAAA==.Demonicus:BAABNQAECn8ZAAMEAAkK1hXAAwB8AQAEAAkK1hXAAwB8AQAFAAMKQwefLwFdAAAAAA==.Deredris:BAAANQAECgcIEAABNQAECgcIFQATAJMUAA==.',
Di='Discodruid:BAAANQAECgQICwAAAA==.Discover:BAAANQAECgEIAQAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQAECgEIAQAAAA==.Domittila:BAAANQAECggIEgABNQAFFAcIFAAKAGYJAA==.Dommy:BAAANQAECgEIAQAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8WAAQVAAcKcRv5BQCkAQAVAAUKhhn5BQCkAQAUAAQK0R0ICwBeAQAHAAIKHSO0GwC6AAA1AAQKfyMABBQACQquJGAmAKMCABQACApVI2AmAKMCAAcABAooI6AdAKQBABUAAgqeIpiBAKYAAAAA.Dorkimedes:BAAANQAECgUIDgAAAA==.Dottie:BAABNQAECn82AAIFAAoKfAxKOQDEAQAFAAoKfAxKOQDEAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Dudeabides:BAAANQAECgEIAwABNQAECgkJGwABAIUJAA==.Dulcolax:BAAANQABCgIIAgABNQADCggIEwAGAAAAAA==.Durenn:BAABNQAECn8wAAIOAAoKLyMxCQCdAwAOAAoKLyMxCQCdAwABNQAFFAUIFQAUAEIkAA==.Duskmane:BAAANQAECgEIAQAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAABNQAECn8XAAIQAAcKMxUGFAAAAQAQAAcKMxUGFAAAAQAAAA==.Dwsavingyou:BAAANQAECgYIBwABNQAECgoKFAAHAKQSAA==.',
Dy='Dyrkazen:BAABNQAECn8ZAAIWAAYKqQZjHADNAAAWAAYKqQZjHADNAAAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECgcIDwABNQAFFAcIFAAKAGYJAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgoKKAAUANAVAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn82AAMRAAoKshZqBgCFAgARAAoKshZqBgCFAgAXAAUK+RfrHwBXAQAAAA==.',
Er='Erébus:BAABNQAECn8WAAIYAAkKvhQxJAAmAgAYAAkKvhQxJAAmAgAAAA==.',
Eu='Euryphaessa:BAAANQAECgUIBgABNQAECgoKFAAHAKQSAA==.',
Ev='Evergreene:BAAANQADCgcICAABNQADCggIEQAGAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgUIEAAAAA==.',
Ew='Ewanar:BAACNQAFFH8UAAMKAAcKZgl4CgCnAQAKAAcKZgl4CgCnAQAOAAEKAAAcNABBAAA1AAQKfyEAAwoACgo5Gh8gAEQCAAoACgo5Gh8gAEQCAA4AAwoYGGOYAG8AAAAA.',
Fa='Faevelia:BAAANQAECgEIAQAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQAECgYIEgAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAgIFwACACEeAA==.Ferndugen:BAAANQAECgIIAwAAAA==.',
Fi='Fishtank:BAAANQAECgQJBQABNQAECgoKOgATAHkYAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQICAAGAAAAAA==.Fizehtotems:BAEANQAECgQICAAAAA==.',
Fo='Foragarn:BAAANQAECgIIAgAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAAANQAECgYIEAABNQAECgkJGwABAIUJAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQAECgEIAQAAAA==.Froznfate:BAABNQAECn8aAAIMAAgK4iI9DgC3AgAMAAgK4iI9DgC3AgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIFwAAAA==.',
Fw='Fwibble:BAABNQAECn8bAAIBAAkKhQkkZQCAAQABAAkKhQkkZQCAAQAAAA==.',
Fy='Fyrelady:BAAANQADCggIHAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIHAAGAAAAAA==.',
Ga='Gabbey:BAEBNQAECn8UAAIOAAgKHQh0TAAoAQAOAAgKHQh0TAAoAQABNQAECgoKMgAZAIwTAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAAANQAECggIEwAAAA==.Garagon:BAABNQAECn8eAAIRAAYKuA7EFAAfAQARAAYKuA7EFAAfAQAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECgQIDgABNQAECgkJGwABAIUJAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAABNQAECn8bAAIUAAYKmA/OLgARAQAUAAYKmA/OLgARAQAAAA==.',
Gh='Ghorfindor:BAAANQAECgUIEQAAAA==.Ghostems:BAACNQAFFH8JAAIBAAYK8w0IGAC4AQABAAYK8w0IGAC4AQA1AAQKfyMAAwEACQolIHcoAFICAAEACQoXHHcoAFICABIAAQqzIwIiAGQAAAAA.',
Gi='Gilas:BAABNQAECn8gAAMHAAcKqQx8PgDnAAAHAAcKUQx8PgDnAAAUAAUKLweTkwDdAAAAAA==.',
Gl='Glaedr:BAAANQAECgcIEAABNQADCggIFgAGAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAABNQAECn8iAAINAAgKWQYktwDrAAANAAgKWQYktwDrAAAAAA==.',
Gn='Gnikole:BAAANQAECgUIEAAAAA==.',
Go='Goswin:BAAANQAECgUIEQAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQAECgUIBQAAAA==.Greenfelpowa:BAAANQAECgYIDQAAAA==.Grimsin:BAAANQADCgQIBAAAAA==.Grizzyy:BAAANQAECgMIBAAAAA==.Gruuven:BAAANQAECgcJDwAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAABNQAECn8nAAITAAoK5hl7GgCHAgATAAoK5hl7GgCHAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAITAAgKzQ/yhQD/AQATAAgKzQ/yhQD/AQAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8hAAMVAAcKDQpUZQANAQAVAAcKmwVUZQANAQAHAAQKHRA+lgCyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.Haunt:BAAANQAECgUICQAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQAECgEIAQAAAA==.Hellzknîght:BAABNQAECn8aAAMVAAcKbg29WgA/AQAVAAcK7wy9WgA/AQAUAAUKrgl8kADmAAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hellzwarlock:BAAANQADCgEIAQAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQICwAAAA==.',
Ho='Holek:BAABNQAECn9JAAITAAoK3SBpEADMAgATAAoK3SBpEADMAgAAAA==.Holgo:BAACNQAFFH8OAAIaAAcKUhV3BACqAQAaAAcKUhV3BACqAQA1AAQKfyYAAhoACgo0HP4iAGECABoACgo0HP4iAGECAAAA.Holstop:BAABNQAECn8jAAIaAAkKMB4cTAClAgAaAAkKMB4cTAClAgABNQAFFAcIIwARAOkmAA==.Holykimoly:BAAANQAECgYIDAABNQAECgoKLAAbAK0eAA==.Honsz:BAAANQAECgEIAQAAAA==.Honzz:BAAANQAECgIIBgAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAAGAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEQAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8tAAMJAAgKWh/ZJgDPAgAJAAgKWh/ZJgDPAgAcAAEKAAA6hwAiAAAAAA==.Icicle:BAAANQAECgMIBAAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn8uAAISAAoKNBZKCgAmAgASAAoKNBZKCgAmAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgMIBQAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQAECgQIBQAAAA==.Jaiswizzle:BAABNQAECn8uAAMHAAoKzBx8EQAvAgAHAAoKzBx8EQAvAgAUAAEKMAZY6gArAAAAAA==.Jamien:BAABNQAECn8kAAMNAAgKBBTVkwAqAQANAAcKnBbVkwAqAQALAAMKWAbi+wCFAAAAAA==.Jasnos:BAAANQAECgQIEgAAAA==.Jayy:BAAANQAECgMIBAAAAA==.',
Je='Jean:BAAANQAECgcIEgAAAA==.',
Ju='Jubileehunt:BAAANQAECgQIBQAAAA==.',
Ka='Kaathe:BAABNQAECn8VAAIBAAUKzxrbKQFGAQABAAUKzxrbKQFGAQAAAA==.Kaidiis:BAABNQAECn8bAAINAAgK0ggU4wBVAQANAAgK0ggU4wBVAQAAAA==.Karbonn:BAAANQAECgUIDwAAAA==.Katiwompus:BAAANQAECgIIAgAAAA==.Katrina:BAAANQADCgIIAgABNQAECgoKTAAZAAgXAA==.Kay:BAAANQAECggICAAAAA==.',
Ke='Kegbreaker:BAABNQAECn82AAIJAAoKpxp/DgACAwAJAAoKpxp/DgACAwAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQAECgUIDgAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8sAAIbAAoKrR6FBAD8AgAbAAoKrR6FBAD8AgAAAA==.Kimbustible:BAABNQAECn8VAAIBAAgK1RuQPgD6AQABAAgK1RuQPgD6AQABNQAECgoKLAAbAK0eAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAAANQAECggIDwAAAA==.',
Ko='Komodostyle:BAABNQAECn8oAAIRAAgKOQd8FAAjAQARAAgKOQd8FAAjAQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8nAAIBAAkKNgZojgAmAQABAAkKNgZojgAmAQAAAA==.',
Kr='Krisarugala:BAABNQAECn8ZAAIPAAcKMA+EUwCMAQAPAAcKMA+EUwCMAQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgUIDwAAAA==.Kurogami:BAAANQADCgQIBQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAABNQAECn8UAAIUAAcKNxRFZgB4AQAUAAcKNxRFZgB4AQAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMOAAIKPwuIJgCSAAAOAAIKPwuIJgCSAAAKAAIKhwI7JwBrAAA1AAQKfy0AAw4ACQqgF2U+AHwCAA4ACQqgF2U+AHwCAAoAAgr7BKCtAF8AAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8TAAMSAAcK4B1RAAAyAgASAAcKHx1RAAAyAgABAAQKuhu0JgBRAQA1AAQKfycAAwEACgrWIzVCAAADAAEACQpHJDVCAAADABIABAoUI10eAPkAAAAA.Lazerturkey:BAABNQAECn8eAAIDAAkKiBQFFwD7AQADAAkKiBQFFwD7AQAAAA==.Laërtes:BAAANQAECgUIEAAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lianne:BAAANQAECgcICQABNQABCgEIAQAGAAAAAA==.Lightbill:BAABNQAECn8vAAMLAAoKth5WBQB/AwALAAoKth5WBQB/AwANAAIKSQkudAFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8xAAIKAAoKGRujKADBAgAKAAoKGRujKADBAgAAAA==.Lilxblitzx:BAABNQAECn8aAAILAAcK8wtwZgAOAQALAAcK8wtwZgAOAQAAAA==.Lilzdrlockz:BAAANQADCgQIBAAAAA==.Lilzriotz:BAAANQAECgQIBQAAAA==.',
Lo='Lockoclock:BAAANQAECgIIAgAAAA==.Locomotion:BAAANQADCggICAAAAA==.Lovecraft:BAAANQADCgQIBwAAAA==.',
Lu='Lucyvar:BAABNQAECn8hAAIZAAkKsQSnPwDLAAAZAAkKsQSnPwDLAAAAAA==.Luma:BAAANQAECgQIBwAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECn8tAAMNAAoK5xlLNQAjAgANAAoK5xlLNQAjAgAMAAQKsBYpTQC0AAAAAA==.Marlow:BAABNQAECn8fAAIFAAgKPROhSwCBAQAFAAgKPROhSwCBAQAAAA==.Marotal:BAABNQAECn8jAAIBAAkK0Q/8ugAOAgABAAkK0Q/8ugAOAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgYICwAAAA==.Maxlife:BAAANQAECggIBwAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAABNQAECn8fAAITAAcKyRJEVwCXAQATAAcKyRJEVwCXAQAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAgAAAA==.',
Mh='Mhael:BAAANQAECgQIDAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minphoria:BAAANQAECgEIAgAAAA==.Minsofar:BAAANQAECgEIAwAAAA==.Mistilinn:BAABNQAECn8tAAIdAAkKZAMAIwDmAAAdAAkKZAMAIwDmAAAAAA==.Miyri:BAAANQAECgEIAgABNQAECgoKNgAWAHEkAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8WAAIPAAcKEh5hBQBPAgAPAAcKEh5hBQBPAgA1AAQKf78AAg8ACgrhJkYAAAwEAA8ACgrhJkYAAAwEAAAA.Morpheus:BAAANQAECgQICwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8sAAMSAAgKyxWEHgD3AAABAAgKyxURywDvAQASAAUKMBiEHgD3AAAAAA==.',
My='Myeyes:BAAANQAECgEIAwAAAA==.Mylinkah:BAAANQAECgcIEAAAAA==.Mynamefizz:BAEANQAECgQICgABNQAECgQICAAGAAAAAA==.Mysticmeat:BAAANQAECgUIBgAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgABNQADCggICAAGAAAAAA==.',
['Mé']='Méasha:BAAANQAECgIIAgAAAA==.',
Ni='Nicola:BAABNQAECn8bAAMJAAoKuhjMTwA1AgAJAAoKuhjMTwA1AgAcAAEKAAB+hgAjAAAAAA==.Nightxwish:BAABNQAECn8VAAQeAAUKzRsUEQAXAQAJAAUKqxmPVQBcAQAeAAQK5BcUEQAXAQAcAAEKDAfRfgAtAAAAAA==.Nik:BAAANQAECgUICgAAAA==.',
No='Nocko:BAAANQAECgEIAQAAAA==.Nohlife:BAAANQABCgIIAgAAAA==.Noisemarine:BAAANQAECgYICwAAAA==.Norellia:BAABNQAECn8UAAMeAAcKyg1IBQA0AQAeAAcKyg1IBQA0AQAcAAEKAACqgAAqAAAAAA==.Northspirit:BAAANQAECgYIEAAAAA==.',
Nu='Nuit:BAAANQAECgIIBAAAAA==.',
Ny='Nyarlothep:BAAANQAECgcIDAAAAA==.Nymh:BAAANQAECgYIDwAAAA==.Nyx:BAAANQAECgEIAQABNQAECggIJAANAAQUAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYICgABNQAECgoKJAACAOIaAA==.Odins:BAABNQAECn8kAAMCAAoK4hrpBgAUAwACAAoK1BrpBgAUAwAOAAgKixvGQwBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgMIBAABNQADCggIEwAGAAAAAA==.Ohyikers:BAACNQAFFH8bAAIPAAYKwyVZAwC2AQAPAAYKwyVZAwC2AQA1AAQKf1sAAw8ACgrqJfYAAPUDAA8ACgrqJfYAAPUDAB8AAQp8Gr06AE8AAAAA.',
Ok='Oken:BAABNQAECn8VAAIPAAUK8gZKVQBzAAAPAAUK8gZKVQBzAAAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECgoKXAALALwlAA==.',
Ot='Otso:BAABNQAECn8dAAIDAAcKiB4VEQBPAgADAAcKiB4VEQBPAgABNQAECgkJFgAYAL4UAA==.',
Pa='Paapi:BAAANQAECgMIBAAAAA==.Paco:BAAANQADCgYIBgAAAA==.Paladime:BAABNQAECn8YAAINAAcKPg3F0AB6AQANAAcKPg3F0AB6AQAAAA==.Pallek:BAAANQAECggIDwABNQAECgoKSQATAN0gAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgQICwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQAECgEIAQAAAA==.',
Ph='Phantomarrow:BAAANQAECgEIAgAAAA==.Phantomcat:BAAANQAECgUIBwAAAA==.Phantomlock:BAABNQAECn8dAAMFAAoKQBRkWABNAgAFAAoKEhRkWABNAgAEAAQKDg4lPQDNAAAAAA==.Pharasan:BAABNQAECn8XAAIOAAgKDQu8ngBZAQAOAAgKDQu8ngBZAQAAAA==.Phatcow:BAABNQAECn85AAIKAAoKjCB0BQB6AwAKAAoKjCB0BQB6AwAAAA==.Pheral:BAEANQADCgIIAgABNQAECgoKMgAZAIwTAA==.Phude:BAABNQAECn9GAAINAAoKhBfhPwD8AQANAAoKhBfhPwD8AQAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIBAAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Ps='Psylent:BAAANQAECgUICAAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAAANQAECggIDgAAAA==.',
Py='Pyramys:BAABNQAECn8gAAMgAAgKmh19DgCQAgAgAAgKmh19DgCQAgAhAAUKIhz7UAB6AQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.Quepaoka:BAAANQABCgMIAwAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQAECgQIBQAAAA==.Rawcky:BAAANQAECgEIAQAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAAGAAAAAA==.Rivër:BAAANQAECgUIBwAAAA==.',
Ro='Rolls:BAAANQAECgQIBgAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAASAOAOAA==.Rootoo:BAAANQADCgEIAQAAAA==.Roozer:BAAANQADCggIGwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAgABNQAECgYIHQARANkaAA==.Sad:BAABNQAECn8kAAIBAAgKYB0keQCMAgABAAgKYB0keQCMAgAAAA==.Saelina:BAAANQAECgYICQABNQAECgoKNgAWAHEkAA==.Saelyria:BAAANQAECgYIBwABNQAECgoKNgAWAHEkAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAABNQAECn8kAAILAAoKiwgAhgC5AAALAAoKiwgAhgC5AAAAAA==.Sainthymn:BAABNQAECn8VAAIJAAoKiA35owApAQAJAAoKiA35owApAQABNQAECgoKJAALAIsIAA==.Sainttide:BAABNQAECn8fAAMOAAoKBwez2QDhAAAOAAkKjwOz2QDhAAAKAAEKlxVCvwA9AAABNQAECgoKJAALAIsIAA==.Salv:BAAANQAECgMICQAAAA==.Sandiera:BAABNQAECn8kAAIBAAkKEQhYjQAoAQABAAkKEQhYjQAoAQAAAA==.Savallyne:BAAANQAECgEIBAABNQAECgoKNgAWAHEkAA==.',
Sc='Scoreboard:BAACNQAFFH8XAAMiAAkKTBYxAABRAQAiAAkKTBYxAABRAQAgAAEKAADxHAAAAAA1AAQKfzkABCIACgr0JuYAAJwDACIACQoIJ+YAAJwDACAAAwoEJzs/AGQBACEAAwrGG6MyAKQAAAAA.Scupper:BAABNQAECn8uAAIiAAoKWRlSBQCdAgAiAAoKWRlSBQCdAgAAAA==.',
Se='Sedric:BAAANQAECgEIAwAAAA==.Selline:BAAANQAECgQIBQAAAA==.Selsonblue:BAAANQADCggIEwAAAA==.Sesskaa:BAABNQAECn8iAAMKAAcKKR1UJwAVAgAKAAcKKR1UJwAVAgACAAIKgwGkLAAeAAAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgUICwAAAA==.Shathos:BAAANQADCgUIAQAAAA==.Shishkbob:BAAANQAECgEIAgAAAA==.Shätterz:BAAANQADCgUJBQABNQAECgEIAQAGAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAABNQAECn8YAAIHAAoKvBycJQBqAQAHAAoKvBycJQBqAQAAAA==.',
Sk='Skaro:BAABNQAECn8aAAIWAAYKuhRpEwBBAQAWAAYKuhRpEwBBAQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgYIGgAWALoUAA==.Skarosham:BAAANQAECgQIBAABNQAECgYIGgAWALoUAA==.Sketch:BAABNQAECn8iAAIhAAkKIQwrOQDwAQAhAAkKIQwrOQDwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8JAAIMAAMKdhNaBgCKAAAMAAMKdhNaBgCKAAA1AAQKfzYAAgwACgpZIZYJAAQDAAwACgpZIZYJAAQDAAAA.Sleepinslime:BAAANQAECgEIAgAAAA==.',
Sm='Smokiebear:BAAANQAECggIDAAAAA==.',
So='Sobekk:BAAANQAECggICQAAAA==.Solomun:BAABNQAECn83AAILAAkKsxu0IwDcAgALAAkKsxu0IwDcAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBwAGAAAAAA==.',
Sp='Spinky:BAAANQAECgMIAwAAAA==.Sploosh:BAAANQAECgUIBgAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIHwAAAA==.Stinko:BAABNQAECn8UAAMEAAcKRgacDQCxAAAEAAcKRgacDQCxAAAFAAUKVwH2MQFXAAAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAABNQAECn8WAAIFAAcKyhDFlwCrAQAFAAcKyhDFlwCrAQAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAABNQAECn8YAAMIAAYKmBNeKwAGAQAIAAUKaxFeKwAGAQAPAAEKqAcebgAzAAAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQAGAAAAAA==.',
Su='Surloyn:BAAANQADCggICAABNQAECgoKLgAHAMwcAA==.',
Sw='Swampert:BAACNQAFFH8HAAIaAAQKLBIvIwDlAAAaAAQKLBIvIwDlAAA1AAQKfy0AAhoACQrfHSYxAPsCABoACQrfHSYxAPsCAAAA.Swamperting:BAAANQAECgMIBQABNQAFFAQIBwAaACwSAA==.Swayaos:BAABNQAECn8jAAIFAAoK2Q4WdgAAAgAFAAoK2Q4WdgAAAgABNQAFFAMIBQAcACAEAA==.Swaye:BAACNQAFFH8FAAIcAAMKIATMCAC+AAAcAAMKIATMCAC+AAA1AAQKfzEAAhwACgquEaQjABUCABwACgquEaQjABUCAAAA.Swifte:BAAANQAECgQIBgAAAA==.Swimchick:BAAANQAECgUIEQAAAA==.Swizzle:BAABNQAECn8ZAAMjAAcKOxOOFgB6AQAjAAcKOxOOFgB6AQAkAAUKNRB+QgAEAQABNQAECgoKLgAHAMwcAA==.',
Sy='Syfa:BAAANQAECgYIDwAAAA==.Syllena:BAABNQAECn82AAMWAAoKcSS1BQBDAwAWAAoKcSS1BQBDAwAkAAQKsBCmSgDRAAABNQAECgoKNgAWAHEkAA==.Syndicalism:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.Syraelia:BAAANQAECgEIAgABNQAECgoKNgAWAHEkAA==.Sythia:BAAANQADCgEIAQABNQAFFAQICAAXAEkNAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIIQAAAA==.',
Ta='Tagmoo:BAABNQAECn82AAIaAAoKLiPKDQD4AgAaAAoKLiPKDQD4AgAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECgkJIwADAMgSAA==.Taloon:BAABNQAECn8XAAIZAAcKYxSsRwCLAQAZAAcKYxSsRwCLAQAAAA==.Taltost:BAABNQAECn8eAAITAAcK5RCKjgAUAQATAAcK5RCKjgAUAQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAABNQAECn8XAAINAAcKYQyi8AA7AQANAAcKYQyi8AA7AQAAAA==.Tarvält:BAAANQAECgUICQAAAA==.',
Te='Teksuo:BAABNQAECn8/AAIkAAoKQBOAEgC+AQAkAAoKQBOAEgC+AQAAAA==.Telamontgrim:BAAANQAECgUIBAAAAA==.Tenithon:BAABNQAECn9cAAILAAoKvCWlAQDXAwALAAoKvCWlAQDXAwAAAA==.Tenscales:BAAANQAECgYICwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBQAAAA==.Tholaren:BAABNQAECn8eAAITAAYKqxEzgQAwAQATAAYKqxEzgQAwAQAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQAECgEIAQAAAA==.',
Ti='Ti:BAAANQAECgIIAwAAAA==.Tinkerspell:BAABNQAECn8WAAISAAkK0gzbFwA7AQASAAkK0gzbFwA7AQAAAA==.Tinny:BAAANQAECgEIAQAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Totemicdeath:BAAANQAECgEIAQAAAA==.Touchit:BAAANQAECgMICAAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAABNQAECn8VAAITAAUKIxDWtwDAAAATAAUKIxDWtwDAAAAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAABNQAECn8VAAMTAAcKkxQJbwBZAQATAAcKkxQJbwBZAQAdAAUK1Qd6WwC3AAAAAA==.Trillion:BAAANQAECgQICQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBQAAAA==.',
Ty='Tyfa:BAAANQAECgQIDgAAAA==.',
Ud='Udari:BAABNQAECn8eAAINAAgKWhQHYwCTAQANAAgKWhQHYwCTAQAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAwAAAA==.',
Uz='Uzume:BAAANQAECgYIBwAAAA==.',
Va='Vaghar:BAAANQAECgEIAQAAAA==.Varithal:BAABNQAECn83AAIRAAoK3hikEACgAgARAAoK3hikEACgAgABNQABCgEIAQAGAAAAAA==.Vastectomy:BAAANQAECgUIDAAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAABNQAECn8gAAITAAcKIQqYkAAQAQATAAcKIQqYkAAQAQAAAA==.',
Vi='Vicious:BAACNQAFFH8IAAIKAAMK6Bn9GgDCAAAKAAMK6Bn9GgDCAAA1AAQKfy4AAgoACQolHrAlAM4CAAoACQolHrAlAM4CAAAA.Vixin:BAAANQAECgYIEgAAAA==.',
Vo='Voidsaack:BAABNQAECn8lAAMEAAgKWAasPwDDAAAEAAYK3ASsPwDDAAAFAAYKVwWpsACQAAAAAA==.Vortan:BAABNQAECn8yAAIlAAgKZR2CAwDTAgAlAAgKZR2CAwDTAgAAAA==.',
Vr='Vreya:BAAANQADCgUIBgABNQADCggIFwAGAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAwAAAA==.Vynnd:BAAANQAECgYIBgAAAA==.Vynthus:BAABNQAECn8UAAIYAAYK1A1QIgAWAQAYAAYK1A1QIgAWAQAAAA==.',
Wa='Warhundin:BAEANQAECgcIBAABNQAECgoKMgAZAIwTAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQICAAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAABNQAECn8UAAQVAAYK1guVXgAsAQAVAAYK1guVXgAsAQAHAAEKAADpxwA5AAAUAAEKywY46wAqAAAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAABNQAECn8fAAIDAAcKVgsWKADQAAADAAcKVgsWKADQAAAAAA==.Whispp:BAAANQAECgQICQAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQICAAGAAAAAA==.',
Wi='Willough:BAAANQAECgEIAQAAAA==.',
Wy='Wymstar:BAAANQAECgEIAQAAAA==.Wyvoker:BAAANQADCgMIAgABNQAECgEIAQAGAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.',
Xu='Xuny:BAAANQAECgQICQAAAA==.',
Ya='Yahzway:BAAANQAECgEIAgAAAA==.',
Yo='Yordi:BAAANQAECgUIEQAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuria:BAAANQAECgYIEgAAAA==.Yuzuriha:BAABNQAECn88AAITAAoKHiL+EwBOAwATAAoKHiL+EwBOAwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQAECgEIAQAAAA==.Zarilith:BAAANQAECgEIAQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8yAAIZAAoKjBMkKgBQAgAZAAoKjBMkKgBQAgAAAA==.',
Zi='Zipy:BAABNQAECn8eAAIJAAYK4w44aAAeAQAJAAYK4w44aAAeAQAAAA==.',
Zo='Zorathar:BAAANQADCgIIAgAAAA==.',
Zy='Zyllo:BAAANQADCggIFgAAAA==.',
Zz='Zzyzzx:BAAANQADCggICQAAAA==.',
['Zæ']='Zæ:BAAANQAECgUIBQAAAA==.',
['Äe']='Äemond:BAAANQADCgIIAgAAAA==.',
['Ål']='Ålïce:BAABNQAECn84AAINAAkK+hj+SADdAQANAAkK+hj+SADdAQAAAA==.',
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
