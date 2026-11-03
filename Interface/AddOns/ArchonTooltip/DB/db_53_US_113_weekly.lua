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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Druid-Restoration','Priest-Holy','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Druid-Balance','Warrior-Protection','Hunter-BeastMastery','Evoker-Preservation','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Devourer','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Mage-Fire','Hunter-Marksmanship','Priest-Discipline','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg7W+wCVAQABAAcKrg7W+wCVAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgIIAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.Aksala:BAAANQABCgIIAgAAAA==.',
Al='Alaralia:BAAANQAECggIEgABNQAFFAgIGgACADQeAA==.Alarathel:BAAANQADCggICAABNQAFFAgIGgACADQeAA==.Aleion:BAAANQADCgUIBQABNQAECgoKKQADACQTAA==.Alyssandra:BAABNQAECn8hAAMEAAkKwQ77HgB3AQAEAAcKWw/7HgB3AQAFAAgKbgdFeAA7AQAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIEQAAAA==.Ammalane:BAAANQADCgQICQABNQADCggIEQAGAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.Angler:BAAANQADCgIIAQAAAA==.',
Ap='Apollyon:BAABNQAECn8aAAIHAAoKaxZXWQCNAQAHAAoKaxZXWQCNAQAAAA==.',
Ar='Arangarr:BAABNQAECn9FAAIIAAoK0CIYAgDfAwAIAAoK0CIYAgDfAwAAAA==.Arcanu:BAAANQAECgQICAAAAA==.Aresiuz:BAABNQAECn8fAAIJAAkKoRZ5VwCkAQAJAAkKoRZ5VwCkAQABNQAFFAcIFAAKAGYJAA==.Areyana:BAAANQAECggIEAAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQAECgUIEAAAAA==.Arrietty:BAABNQAECn8aAAILAAYKiBLabQA6AQALAAYKiBLabQA6AQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAABNQAECn8hAAMMAAoK1gsxGgBrAQAMAAoK1gsxGgBrAQANAAYK+AaWHQHuAAAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAABNQAECn8ZAAIOAAYKBhdKawALAQAOAAYKBhdKawALAQAAAA==.',
Az='Azeriall:BAABNQAECn9KAAIOAAoKeBh0JwARAgAOAAoKeBh0JwARAgAAAA==.Azerodru:BAAANQADCgEIAgAAAA==.',
Ba='Bacnfen:BAABNQAECn8bAAIOAAkKJQpYZQAcAQAOAAkKJQpYZQAcAQAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAAGAAAAAA==.Banshiï:BAABNQAECn8bAAIEAAgKTAclKQAyAQAEAAgKTAclKQAyAQAAAA==.Baratheøn:BAABNQAECn8jAAMIAAgK9xabHQDFAQAIAAgK9xabHQDFAQAPAAEK2gKFhgAgAAAAAA==.Bason:BAAANQAECggIDQAAAA==.',
Be='Beeftard:BAABNQAECn8jAAILAAoKKhkdNgCLAgALAAoKKhkdNgCLAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodletterr:BAAANQADCgMIAwAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgcICwAAAA==.',
Bo='Bobbyg:BAAANQAECgEIAwAAAA==.Bollace:BAAANQADCgUIBQABNQADCgcIBwAGAAAAAA==.',
Bu='Buckey:BAAANQAECgEIAgAAAA==.Bullythekid:BAAANQAECgUIBwAAAA==.',
By='Byzantium:BAABNQAECn8nAAIQAAgKGgirGwDrAAAQAAgKGgirGwDrAAAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAABNQAECn8WAAIRAAcK7wQyswAHAQARAAcK7wQyswAHAQAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwASAK4SAA==.Celitha:BAAANQADCggIBwAAAA==.',
Ch='Chromatic:BAAANQAECgYIBQAAAA==.Chronic:BAAANQAECgIIBAABNQAECgoKLwANANkUAA==.',
Ci='Cinderflamez:BAAANQABCgMIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAABNQADCggICAAGAAAAAA==.Coldstorm:BAABNQAECn8gAAITAAkK4A44DAD4AQATAAkK4A44DAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAABNQAECn8cAAIEAAYKUwWZNADxAAAEAAYKUwWZNADxAAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn9FAAIRAAoKohwPJgB8AgARAAoKohwPJgB8AgAAAA==.',
Da='Daddyelessar:BAAANQAECgcICAAAAA==.Daemonfyre:BAAANQADCgQIBAAAAA==.Dafattyup:BAABNQAECn8nAAIFAAkKTBEFTgCyAQAFAAkKTBEFTgCyAQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAAANQAECgcICwAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFH8WAAIUAAYKSyPWAADQAQAUAAYKSyPWAADQAQA1AAQKfz0AAxQACgpHJn4BAG0DABQACgpHJn4BAG0DABUAAwqIF4h2AJMAAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgcIDgABNQAECgoKGgAHAGsWAA==.Deathlydruid:BAAANQAECgEIAgAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAABNQAECn8ZAAIHAAYKSAx7SQDtAAAHAAYKSAx7SQDtAAAAAA==.Deeanndra:BAABNQAECn8fAAMUAAgK8gu4cgBMAQAUAAgKzwq4cgBMAQAVAAIKxAysmgA6AAAAAA==.Demiz:BAABNQAECn8yAAIKAAoKoxQkXwDxAQAKAAoKoxQkXwDxAQAAAA==.Demonicus:BAABNQAECn8eAAMEAAkK1hXrBAB8AQAEAAkK1hXrBAB8AQAFAAMKQwefLwFdAAAAAA==.Deredris:BAAANQAECgYIDwABNQAECgcIFQARAJMUAA==.',
Di='Discodruid:BAAANQAECgQICAAAAA==.Discover:BAAANQADCgcIEgAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dj='Djall:BAAANQAECgYIBgAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Dominant:BAAANQAECggICAAAAA==.Domittila:BAAANQAECggIEwABNQAFFAcIFAAKAGYJAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8WAAQVAAcKcRv5BQCkAQAVAAUKhhn5BQCkAQAUAAQK0R0ICwBeAQAHAAIKHSO0GwC6AAA1AAQKfyQABBQACQquJGAmAKMCABQACApVI2AmAKMCAAcABAooI/EmAJsBABUAAgqeIpiBAKYAAAAA.Dorkimedes:BAAANQAECgYIEAAAAA==.Dottie:BAABNQAECn8/AAIFAAoKwgy2SwC6AQAFAAoKwgy2SwC6AQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Dudeabides:BAAANQAECgEIAQABNQAECgoKIQABAMQIAA==.Dulcolax:BAAANQADCgQIBAABNQADCggIEwAGAAAAAA==.Durenn:BAABNQAECn8xAAIOAAoKsyMxCQCdAwAOAAoKsyMxCQCdAwABNQAFFAYIFgAUAEsjAA==.Duskmane:BAAANQABCgIIAgAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAABNQAECn8cAAIQAAcKmBflFgAfAQAQAAcKmBflFgAfAQAAAA==.Dwsavingyou:BAAANQAECgUICwABNQAECgoKGgAHAGsWAA==.',
Dy='Dyrkazen:BAABNQAECn8ZAAIWAAYKqQZQIgDKAAAWAAYKqQZQIgDKAAAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECggIEAABNQAFFAcIFAAKAGYJAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgoKLAAUACsXAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn9BAAMSAAoKshYLCQB9AgASAAoKshYLCQB9AgAXAAUK+RfrHwBXAQAAAA==.',
Er='Erébus:BAABNQAECn8dAAIYAAkKTBYxJAAmAgAYAAkKTBYxJAAmAgAAAA==.',
Eu='Euryphaessa:BAAANQAECgcIDwABNQAECgoKGgAHAGsWAA==.',
Ev='Evergreene:BAAANQADCgcICAABNQADCggIEQAGAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgUIDgAAAA==.',
Ew='Ewanar:BAACNQAFFH8UAAMKAAcKZgl4CgCnAQAKAAcKZgl4CgCnAQAOAAEKAAAcNABBAAA1AAQKfyQAAwoACgo5GoQrAEcCAAoACgo5GoQrAEcCAA4AAwoYGGG0AG8AAAAA.',
Fa='Faevelia:BAAANQAECgEIAQAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAABNQAECn8YAAITAAcK7gWVGgDPAAATAAcK7gWVGgDPAAAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAgIGgACADQeAA==.Ferndugen:BAAANQAECgMIBQAAAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECgoKQwARAHkYAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQAGAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQAECgQIBgAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAAANQAECggIEQABNQAECgoKIQABAMQIAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAABNQAECn8cAAIMAAgK4iI9DgC3AgAMAAgK4iI9DgC3AgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIFwAAAA==.',
Fw='Fwibble:BAABNQAECn8hAAIBAAoKxAjIdACUAQABAAoKxAjIdACUAQAAAA==.',
Fy='Fyrelady:BAAANQADCggIHAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIHAAGAAAAAA==.',
Ga='Gabbey:BAEBNQAECn8VAAIOAAgKkAhbXwAtAQAOAAgKkAhbXwAtAQABNQAECgoKLQANAHMXAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAABNQAECn8VAAIZAAkKShkiKgBzAgAZAAkKShkiKgBzAgAAAA==.Garagon:BAABNQAECn8kAAISAAcKJg36FgBEAQASAAcKJg36FgBEAQAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECggIEAABNQAECgoKIQABAMQIAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gebbo:BAAANQAECgQIBAABNQAECgYIBgAGAAAAAA==.Gerva:BAABNQAECn8hAAIUAAcKjg+KLABQAQAUAAcKjg+KLABQAQAAAA==.',
Gh='Ghorfindor:BAABNQAECn8WAAIaAAYKzwH5ZgBZAAAaAAYKzwH5ZgBZAAAAAA==.Ghostems:BAACNQAFFH8JAAIBAAYK8w0IGAC4AQABAAYK8w0IGAC4AQA1AAQKfyYAAwEACQolIAg4AEQCAAEACQoXHAg4AEQCABMAAQqzI7oqAGAAAAAA.',
Gi='Gilas:BAABNQAECn8iAAMHAAgKWgyeQQAPAQAHAAgKEQyeQQAPAQAUAAUKLweTkwDdAAAAAA==.',
Gl='Glaedr:BAAANQAECgcIDQABNQADCggIFgAGAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAABNQAECn8iAAINAAgKWQau2wDmAAANAAgKWQau2wDmAAAAAA==.',
Gn='Gnikole:BAAANQAECgYIEgAAAA==.',
Go='Goswin:BAAANQAECgYIEwAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQAECgUIBQAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Grimsin:BAAANQADCgQIBAAAAA==.Grizzyy:BAAANQAECgMIBAAAAA==.Gruuven:BAAANQAECggIDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggICQAAAA==.',
Gw='Gwenivive:BAABNQAECn8qAAIRAAoKmBosKABzAgARAAoKmBosKABzAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAIRAAgKzQ/yhQD/AQARAAgKzQ/yhQD/AQAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8hAAMVAAcKDQpUZQANAQAVAAcKmwVUZQANAQAHAAQKHRA+lgCyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.Haunt:BAAANQAECgUIDQAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQAECgIIAwAAAA==.Hellzknîght:BAABNQAECn8gAAMVAAoKagsDTgAfAQAVAAoKGwsDTgAfAQAUAAUKrgl8kADmAAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hellzwarlock:BAAANQADCgEIAQAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQIBwAAAA==.',
Ho='Holek:BAABNQAECn9SAAIRAAoKCyPtCAAwAwARAAoKCyPtCAAwAwAAAA==.Holgo:BAACNQAFFH8PAAIZAAcKUhUNBwCcAQAZAAcKUhUNBwCcAQA1AAQKfysAAhkACgplHh0fAKsCABkACgplHh0fAKsCAAAA.Holstop:BAABNQAECn8oAAIZAAkKfSAcTAClAgAZAAkKfSAcTAClAgABNQAFFAcIJAASAO8mAA==.Holykimoly:BAAANQAECgYICgABNQAECgoKLAAbAK0eAA==.Honzz:BAAANQAECgIIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAAGAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8vAAMJAAoKBR3ZJgDPAgAJAAoKBR3ZJgDPAgAcAAEKAAA6hwAiAAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn83AAITAAoKyRaMBwAFAgATAAoKyRaMBwAFAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgMIBQAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQAECgQIBQAAAA==.Jaiswizzle:BAABNQAECn83AAMHAAoKzBzZFgAoAgAHAAoKzBzZFgAoAgAUAAEKMAZY6gArAAAAAA==.Jamien:BAABNQAECn8qAAMNAAgKoRQYmABcAQANAAgKoRQYmABcAQALAAMKWAbi+wCFAAAAAA==.Jasnos:BAABNQAECn8XAAMXAAYK1Q9sEgDgAAAXAAYK1Q9sEgDgAAASAAEKnQYaUgAoAAAAAA==.Jayy:BAAANQAECgMIBAAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Jh='Jhey:BAAANQAECgIIAgAAAA==.Jhunter:BAAANQAECgIIAgAAAA==.',
Ju='Jubileehunt:BAAANQAECgQIBQAAAA==.',
Ka='Kaathe:BAABNQAECn8XAAMBAAUKzxrbKQFGAQABAAUKzxrbKQFGAQAdAAEKAABbDAAAAAAAAA==.Kaidiis:BAABNQAECn8iAAINAAgK0ggU4wBVAQANAAgK0ggU4wBVAQAAAA==.Karbonn:BAAANQAECggIEAAAAA==.Katiwompus:BAAANQAECgIIAgAAAA==.Katrina:BAAANQADCgIIAgAAAA==.Kay:BAAANQAECggICAAAAA==.',
Kb='Kbear:BAAANQAECgYIBAAAAA==.',
Ke='Kegbreaker:BAABNQAECn8/AAIJAAoK/hrZFgD0AgAJAAoK/hrZFgD0AgAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQAECggIEAAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8sAAIbAAoKrR6FBAD8AgAbAAoKrR6FBAD8AgAAAA==.Kimbustible:BAABNQAECn8XAAIBAAgK1RuiVgDnAQABAAgK1RuiVgDnAQABNQAECgoKLAAbAK0eAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAABNQAECn8VAAINAAgKQAzK2QDpAAANAAgKQAzK2QDpAAAAAA==.',
Ko='Komodostyle:BAABNQAECn8qAAISAAgKOQewGQAfAQASAAgKOQewGQAfAQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8nAAIBAAkKNgY4sAAaAQABAAkKNgY4sAAaAQAAAA==.',
Kr='Krisarugala:BAABNQAECn8ZAAIPAAcKMA+EUwCMAQAPAAcKMA+EUwCMAQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAABNQAECn8WAAIRAAcKuxv8dgCGAQARAAcKuxv8dgCGAQAAAA==.Kurogami:BAAANQADCgQIBQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kymal:BAAANQAECgQIBAAAAA==.Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAABNQAECn8UAAIUAAcKNxRFZgB4AQAUAAcKNxRFZgB4AQAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMOAAIKPwuIJgCSAAAOAAIKPwuIJgCSAAAKAAIKhwI7JwBrAAA1AAQKfy0AAw4ACQqgF2U+AHwCAA4ACQqgF2U+AHwCAAoAAgr7BAXHAF8AAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8TAAMTAAcK4B1RAAAyAgATAAcKHx1RAAAyAgABAAQKuhu0JgBRAQA1AAQKfygAAwEACgrWIzVCAAADAAEACgrBIzVCAAADABMABAoUI10eAPkAAAAA.Lazerturkey:BAABNQAECn8gAAIDAAoKBxYFFwD7AQADAAoKBxYFFwD7AQAAAA==.Laërtes:BAABNQAECn8VAAINAAUKBQa4EwGVAAANAAUKBQa4EwGVAAAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lianne:BAAANQAECgcICQABNQABCgEIAQAGAAAAAA==.Lightbill:BAABNQAECn84AAMLAAoK/R5bCAB6AwALAAoK/R5bCAB6AwANAAIKSQkudAFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8zAAIKAAoK9h2jKADBAgAKAAoK9h2jKADBAgAAAA==.Lilxblitzx:BAABNQAECn8aAAILAAcK8wvjfgAJAQALAAcK8wvjfgAJAQAAAA==.Lilzdrlockz:BAAANQADCgQIBAAAAA==.Lilzriotz:BAAANQAECgUICgAAAA==.',
Lo='Lockoclock:BAAANQAECgEIBQAAAA==.Locomotion:BAAANQADCggICAAAAA==.Lovecraft:BAAANQADCgQIBwAAAA==.',
Lu='Lucyvar:BAABNQAECn8mAAIaAAkKKAaBQgDsAAAaAAkKKAaBQgDsAAAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECn82AAMNAAoK1xosPgA/AgANAAoK1xosPgA/AgAMAAQKsBYpTQC0AAAAAA==.Marlow:BAABNQAECn8oAAIFAAoKMxHyQADfAQAFAAoKMxHyQADfAQAAAA==.Marotal:BAABNQAECn8kAAIBAAkKFRL8ugAOAgABAAkKFRL8ugAOAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgcIDAAAAA==.Maxlife:BAAANQAECggIBwAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAABNQAECn8mAAIRAAgK2hSATwDvAQARAAgK2hSATwDvAQAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.Meridae:BAAANQAECgYIBgAAAA==.',
Mh='Mhael:BAAANQAECgQICgAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minsofar:BAAANQAECgUIBQAAAA==.Mistilinn:BAABNQAECn8tAAIeAAkKZAM9KwDaAAAeAAkKZAM9KwDaAAAAAA==.Miyri:BAAANQAECgEIAQABNQAECgoKOwAWAHYkAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8WAAIPAAcKEh5hBQBPAgAPAAcKEh5hBQBPAgA1AAQKf8wAAg8ACgrhJjEAAJoDAA8ACgrhJjEAAJoDAAAA.Morpheus:BAAANQAECgYIDAAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8tAAMTAAgKERaEHgD3AAABAAgKERYRywDvAQATAAUKMBiEHgD3AAAAAA==.',
My='Myeyes:BAAANQAECgEIAQAAAA==.Mylinkah:BAAANQAECgUIEwAAAA==.Mynamefizz:BAEANQAECgUICAABNQAECgQIBQAGAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgABNQADCggICAAGAAAAAA==.',
['Mé']='Méasha:BAAANQAECgIIAgAAAA==.',
Ni='Nicola:BAABNQAECn8eAAMJAAoKhxnMTwA1AgAJAAoKhxnMTwA1AgAcAAEKAAB+hgAjAAAAAA==.Nightxwish:BAABNQAECn8aAAQJAAYKRx2DTADNAQAJAAYKSByDTADNAQAfAAQK5BcUEQAXAQAcAAEKDAfRfgAtAAAAAA==.Nik:BAAANQAECgYICQAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Nohlife:BAAANQABCgIIAgAAAA==.Noisemarine:BAAANQAECggICgAAAA==.Norellia:BAABNQAECn8ZAAMfAAcKyg0JBwAwAQAfAAcKyg0JBwAwAQAcAAUKAAZcQQB2AAAAAA==.Northspirit:BAAANQAECgYIDgAAAA==.',
Nu='Nuit:BAAANQAECgMIAgAAAA==.',
Ny='Nyarlothep:BAABNQAECn8dAAIbAAcKrBDJDQA3AQAbAAcKrBDJDQA3AQAAAA==.Nymh:BAABNQAECn8YAAMFAAgK3QnKgAAnAQAFAAgKZgnKgAAnAQAgAAEK6AoyJwAyAAAAAA==.Nyx:BAAANQADCgIIAgABNQAECggIKgANAKEUAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYICQABNQAECgoKJQACABYdAA==.Odins:BAABNQAECn8lAAMCAAoKFh3pBgAUAwACAAoKCB3pBgAUAwAOAAgKixvGQwBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgMIBAABNQADCggIEwAGAAAAAA==.Ohyikers:BAACNQAFFH8cAAIPAAcKYCX8AgASAgAPAAcKYCX8AgASAgA1AAQKf2IABA8ACgrqJfYAAPUDAA8ACgrqJfYAAPUDAAMAAgqhHfk4AK0AACEAAQp8Gr06AE8AAAAA.',
Ok='Oken:BAABNQAECn8aAAIPAAYK3AfiVACgAAAPAAYK3AfiVACgAAAAAA==.',
Op='Oppenheimer:BAAANQADCgEIAQAAAA==.Opportunity:BAAANQADCgcIBwABNQAECgoKbQALABcmAA==.',
Ot='Otso:BAABNQAECn8jAAIDAAcKiB4VEQBPAgADAAcKiB4VEQBPAgABNQAECgkJHQAYAEwWAA==.',
Pa='Paapi:BAAANQAECgMIBgAAAA==.Paco:BAAANQADCgYIBgAAAA==.Paladime:BAABNQAECn8YAAINAAcKPg3F0AB6AQANAAcKPg3F0AB6AQAAAA==.Pallek:BAAANQAECggIDwABNQAECgoKUgARAAsjAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgYICwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.',
Ph='Phantomarrow:BAAANQAECgEIAgAAAA==.Phantomcat:BAAANQAECgUIBgAAAA==.Phantomlock:BAABNQAECn8iAAMFAAoKQxVkWABNAgAFAAoKFRVkWABNAgAEAAQKDg4lPQDNAAAAAA==.Pharasan:BAABNQAECn8XAAIOAAgKDQu8ngBZAQAOAAgKDQu8ngBZAQAAAA==.Phatcow:BAABNQAECn89AAIKAAoKaCGuBgCRAwAKAAoKaCGuBgCRAwAAAA==.Pheral:BAEANQADCgIIAgABNQAECgoKLQANAHMXAA==.Phude:BAABNQAECn9RAAINAAoKsxiIRgAjAgANAAoKsxiIRgAjAgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Ps='Psylock:BAAANQAECgUIDQAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAABNQAECn8XAAIFAAkKhQtoTQC0AQAFAAkKhQtoTQC0AQAAAA==.',
Py='Pyramys:BAABNQAECn8gAAMiAAgKmh19DgCQAgAiAAgKmh19DgCQAgAjAAUKIhz7UAB6AQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.Quepaoka:BAAANQABCgMIAwAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQAECgQIBQAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAAGAAAAAA==.Rivër:BAAANQAECgYIBQAAAA==.',
Ro='Rolls:BAAANQAECgQIBgAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAATAOAOAA==.Rootoo:BAAANQADCgEIAQAAAA==.Roozer:BAAANQADCggIHwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAQABNQAECgkJJQAXABsVAA==.Sad:BAABNQAECn8nAAIBAAoK/hlkQwAfAgABAAoK/hlkQwAfAgAAAA==.Saelina:BAAANQAECgYICAABNQAECgoKOwAWAHYkAA==.Saelyria:BAAANQAECgcIDAABNQAECgoKOwAWAHYkAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAABNQAECn8lAAILAAoKpwj6mwC+AAALAAoKpwj6mwC+AAAAAA==.Sainthymn:BAAANQAECggIEwABNQAECgoKJQALAKcIAA==.Sainttide:BAABNQAECn8gAAMOAAoKVQez2QDhAAAOAAkKjwOz2QDhAAAKAAEKnB3BywBXAAABNQAECgoKJQALAKcIAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAABNQAECn8sAAIBAAkKjAuYgQB3AQABAAkKjAuYgQB3AQAAAA==.Savallyne:BAAANQAECgEIAwABNQAECgoKOwAWAHYkAA==.',
Sc='Scoreboard:BAACNQAFFH8dAAMkAAkKXiEHAAA7AgAkAAkKXiEHAAA7AgAiAAEKAACzIwAAAAA1AAQKfzoABCQACgr0JuYAAJwDACQACQoIJ+YAAJwDACIAAwoEJ1lUAGQBACMAAwrGG045AJgAAAAA.Scupper:BAABNQAECn83AAIkAAoKhRqqAQA6AgAkAAoKhRqqAQA6AgAAAA==.',
Se='Sedric:BAAANQAECgEIAgAAAA==.Selline:BAAANQAECgQIBgAAAA==.Selsonblue:BAAANQADCggIEwAAAA==.Sesskaa:BAABNQAECn8oAAMKAAgK/h2cIACKAgAKAAgK/h2cIACKAgACAAIKgwFsMwAeAAAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgYIDQAAAA==.Shathos:BAAANQADCgUIAQAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgAGAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAABNQAECn8YAAIHAAoKvBwhQgD0AQAHAAoKvBwhQgD0AQAAAA==.',
Sk='Skaro:BAABNQAECn8eAAIWAAkKehCXEQCwAQAWAAkKehCXEQCwAQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgkJHgAWAHoQAA==.Skarosham:BAAANQAECgQIBAABNQAECgkJHgAWAHoQAA==.Sketch:BAABNQAECn8iAAIjAAkKIQwrOQDwAQAjAAkKIQwrOQDwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8LAAIMAAQKEhJhBQDFAAAMAAQKEhJhBQDFAAA1AAQKfzoAAgwACgq4IZYJAAQDAAwACgq4IZYJAAQDAAAA.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICgAAAA==.',
So='Sobekk:BAAANQAECggIEQAAAA==.Solomun:BAABNQAECn88AAILAAkKYhy0IwDcAgALAAkKYhy0IwDcAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Sp='Spinky:BAAANQAECggICwAAAA==.Sploosh:BAAANQAECgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIJQAAAA==.Stinko:BAABNQAECn8UAAMEAAcKRgblEQCvAAAEAAcKRgblEQCvAAAFAAUKVwH2MQFXAAAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAABNQAECn8WAAIFAAcKyhDFlwCrAQAFAAcKyhDFlwCrAQAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAABNQAECn8eAAMIAAcKvRHgMAAjAQAIAAYKng/gMAAjAQAPAAEKqAejfQAxAAAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQAGAAAAAA==.',
Su='Surloyn:BAAANQADCggICAABNQAECgoKNwAHAMwcAA==.',
Sw='Swampert:BAACNQAFFH8HAAIZAAQKLBIvIwDlAAAZAAQKLBIvIwDlAAA1AAQKfy0AAhkACQrfHSYxAPsCABkACQrfHSYxAPsCAAAA.Swamperting:BAAANQAECgMIBAABNQAFFAQIBwAZACwSAA==.Swayaos:BAABNQAECn8jAAIFAAoK2Q4WdgAAAgAFAAoK2Q4WdgAAAgABNQAFFAQIBgAcACAEAA==.Swaye:BAACNQAFFH8GAAIcAAQKIAQWCwC1AAAcAAQKIAQWCwC1AAA1AAQKfzUAAhwACgq6FKQjABUCABwACgq6FKQjABUCAAAA.Swifte:BAAANQAECgQIBgAAAA==.Swimchick:BAABNQAECn8WAAIRAAUK1ApexADkAAARAAUK1ApexADkAAAAAA==.Swizzle:BAABNQAECn8ZAAMlAAcKOxOOFgB6AQAlAAcKOxOOFgB6AQAmAAUKNRB+QgAEAQABNQAECgoKNwAHAMwcAA==.',
Sy='Syfa:BAABNQAECn8VAAMVAAgKuA0dUAAXAQAVAAgKuA0dUAAXAQAHAAMKugPvnQAlAAAAAA==.Syllena:BAABNQAECn87AAMWAAoKdiS1BQBDAwAWAAoKdiS1BQBDAwAmAAQK9BKmSgDRAAABNQAECgoKOwAWAHYkAA==.Syndicalism:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.Syraelia:BAAANQAECgEIAgABNQAECgoKOwAWAHYkAA==.Sythia:BAAANQADCgEIAQABNQAFFAQICAAXAEkNAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIJQAAAA==.',
Ta='Tagmoo:BAABNQAECn8/AAIZAAoKQySWCgAwAwAZAAoKQySWCgAwAwAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECgoKKQADACQTAA==.Taloon:BAABNQAECn8YAAIaAAcKpRT6OgAVAQAaAAcKpRT6OgAVAQAAAA==.Taltost:BAABNQAECn8fAAIRAAgKSRAslQBDAQARAAgKSRAslQBDAQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAABNQAECn8ZAAINAAgKxAyi8AA7AQANAAgKxAyi8AA7AQAAAA==.Tarvält:BAAANQAECgQICgAAAA==.',
Te='Teksuo:BAABNQAECn9JAAImAAoK1RNqFgDPAQAmAAoK1RNqFgDPAQAAAA==.Telamontgrim:BAAANQAECgUIBAAAAA==.Tenithon:BAABNQAECn9tAAILAAoKFyalAQDXAwALAAoKFyalAQDXAwAAAA==.Tenscales:BAABNQAECn8fAAISAAkKTxMVDAAmAgASAAkKTxMVDAAmAgAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBAAAAA==.Tholaren:BAABNQAECn8kAAIRAAcK2xDNfQB2AQARAAcK2xDNfQB2AQAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAABNQAECn8WAAITAAkK0gzbFwA7AQATAAkK0gzbFwA7AQAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Totemfreak:BAAANQADCgQIBAAAAA==.Totemicdeath:BAAANQAECgEIAQAAAA==.Touchit:BAAANQAECgMICAAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAABNQAECn8aAAIRAAYKrQzwzQDRAAARAAYKrQzwzQDRAAAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAABNQAECn8VAAMRAAcKkxSGkABMAQARAAcKkxSGkABMAQAeAAUK1Qd6WwC3AAAAAA==.Trillion:BAAANQAECgQICQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAAANQAECgQIEAAAAA==.',
Ud='Udari:BAABNQAECn8kAAINAAgKYRalcwCoAQANAAgKYRalcwCoAQAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQAECgYICAAAAA==.',
Va='Varithal:BAABNQAECn9BAAISAAoKvRrWCACEAgASAAoKvRrWCACEAgABNQABCgEIAQAGAAAAAA==.Vastectomy:BAAANQAECgUIDAAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAABNQAECn8jAAIRAAgKvAmtnAA0AQARAAgKvAmtnAA0AQAAAA==.',
Vi='Vicious:BAACNQAFFH8IAAIKAAMK6Bn9GgDCAAAKAAMK6Bn9GgDCAAA1AAQKfy4AAgoACQolHrAlAM4CAAoACQolHrAlAM4CAAAA.Vixin:BAAANQAECgUIEwAAAA==.',
Vo='Voidsaack:BAABNQAECn8lAAMEAAgKWAasPwDDAAAFAAYKVwV2/gDPAAAEAAYK3ASsPwDDAAAAAA==.Vortan:BAABNQAECn80AAInAAgKZR2CAwDTAgAnAAgKZR2CAwDTAgAAAA==.',
Vr='Vreya:BAAANQADCgQICQABNQADCggIFwAGAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynnd:BAAANQAECgYIBgAAAA==.Vynthus:BAABNQAECn8UAAIYAAYK1A1lKgAMAQAYAAYK1A1lKgAMAQAAAA==.',
Wa='Wanshift:BAAANQAECgEIAQAAAA==.Warhundin:BAEANQAECggIBgABNQAECgoKLQANAHMXAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAABNQAECn8UAAQVAAYK1guVXgAsAQAVAAYK1guVXgAsAQAHAAEKAADpxwA5AAAUAAEKywY46wAqAAAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAABNQAECn8lAAIDAAgKYwuzKwD2AAADAAgKYwuzKwD2AAAAAA==.Whispp:BAAANQAECgUIBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQAGAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgAGAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgAGAAAAAA==.',
Xu='Xuny:BAAANQAECgUIDgAAAA==.',
Ya='Yahzway:BAAANQAECgEIAQAAAA==.',
Yo='Yordi:BAABNQAECn8VAAIRAAUKQgSWBgH5AAARAAUKQgSWBgH5AAAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuria:BAABNQAECn8XAAIaAAYK8QuqSADOAAAaAAYK8QuqSADOAAAAAA==.Yuzuriha:BAABNQAECn9FAAIRAAoKCSPhDgAAAwARAAoKCSPhDgAAAwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQADCggIFQAAAA==.Zarilith:BAAANQAECgEIAQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8yAAIaAAoKjBMkKgBQAgAaAAoKjBMkKgBQAgABNQAECgoKLQANAHMXAA==.',
Zi='Zipy:BAABNQAECn8kAAIJAAcKQg9/bgBUAQAJAAcKQg9/bgBUAQAAAA==.',
Zo='Zorathar:BAAANQADCgIIAwAAAA==.Zorma:BAAANQAECgUIBQAAAA==.',
Zy='Zyllo:BAAANQADCggIGQAAAA==.',
Zz='Zzyzzx:BAAANQADCggIDQAAAA==.',
['Zæ']='Zæ:BAAANQAECgQIBQAAAA==.',
['Äe']='Äemond:BAAANQADCgIIAgAAAA==.',
['Ål']='Ålïce:BAABNQAECn9BAAINAAoK+hpGOgBOAgANAAoK+hpGOgBOAgAAAA==.',
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
