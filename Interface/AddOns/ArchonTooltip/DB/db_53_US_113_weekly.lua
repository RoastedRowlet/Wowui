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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Druid-Restoration','Priest-Holy','Shaman-Restoration','Druid-Balance','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Druid-Feral','Warrior-Protection','Hunter-BeastMastery','Evoker-Preservation','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Devourer','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Mage-Fire','Evoker-Augmentation','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Priest-Discipline','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg7W+wCVAQABAAcKrg7W+wCVAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgIIAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.Aksala:BAAANQABCgIIAgAAAA==.',
Al='Alaralia:BAAANQAECggIEgABNQAFFAgIHAACANMeAA==.Alarathel:BAAANQADCggICAABNQAFFAgIHAACANMeAA==.Aleion:BAAANQADCgUIBQABNQAECgoKNAADADwUAA==.Alyssandra:BAABNQAECn8tAAMEAAoKJQ/7HgB3AQAFAAoKHQrsZACnAQAEAAcKWw/7HgB3AQAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIFQAAAA==.Ammalane:BAAANQADCgQICQABNQADCggIFQAGAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.Angler:BAAANQADCgIIAQAAAA==.',
Ap='Apollyon:BAABNQAECn8eAAIHAAoKVxcRJADaAQAHAAoKVxcRJADaAQAAAA==.',
Ar='Arangarr:BAABNQAECn9IAAIIAAoKCiOqAgDoAwAIAAoKCiOqAgDoAwAAAA==.Arcanu:BAAANQAECgQIBQAAAA==.Aresiuz:BAABNQAECn8fAAIJAAkKoRbcZwDnAQAJAAkKoRbcZwDnAQABNQAFFAgIFgAKABMJAA==.Areyana:BAAANQAECggIEAAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAABNQAECn8aAAILAAYKUBG1QAAlAQALAAYKUBG1QAAlAQAAAA==.Arrietty:BAABNQAECn8kAAIMAAYK2xVfcgBeAQAMAAYK2xVfcgBeAQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAABNQAECn8hAAMNAAoK1gsAIgBeAQANAAoK1gsAIgBeAQAOAAYK+AaWHQHuAAAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAABNQAECn8lAAIPAAYKBhcqfwATAQAPAAYKBhcqfwATAQAAAA==.',
Az='Azeriall:BAABNQAECn9dAAIPAAoKmxtFHQCHAgAPAAoKmxtFHQCHAgAAAA==.Azerodru:BAAANQADCgEIAgAAAA==.',
Ba='Bacnfen:BAABNQAECn8jAAIPAAkKIQtTcQA1AQAPAAkKIQtTcQA1AQAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAAGAAAAAA==.Baelmyre:BAAANQAECgIIAgAAAA==.Banshiï:BAABNQAECn8eAAIEAAoKMAihDQDmAAAEAAoKMAihDQDmAAAAAA==.Baratheøn:BAABNQAECn8pAAQIAAgK9xaJJgC+AQAIAAgK9xaJJgC+AQAQAAYK6QdbKADAAAALAAEK2gJclgAgAAAAAA==.Bason:BAAANQAECggIDwAAAA==.',
Be='Beeftard:BAABNQAECn8jAAIMAAoKKhkdNgCLAgAMAAoKKhkdNgCLAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Blessica:BAAANQAECgMIAwAAAA==.Bloodletterr:BAAANQADCgMIAwAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgcICwAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwAGAAAAAA==.',
Bu='Buckey:BAAANQAECggIDgAAAA==.Bullythekid:BAAANQAECggIEAAAAA==.',
By='Byzantium:BAABNQAECn8wAAIRAAkKlgq8GQA7AQARAAkKlgq8GQA7AQAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAEBNQAECn8eAAISAAkK5ASFuQA/AQASAAkK5ASFuQA/AQAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwATAK4SAA==.Celitha:BAAANQADCggIBwAAAA==.',
Ch='Chromatic:BAAANQAECgcICAAAAA==.Chronic:BAAANQAECgIIBAABNQAECgoKLwAOANkUAA==.',
Ci='Cinderflamez:BAAANQABCgMIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAABNQADCggICAAGAAAAAA==.Coldstorm:BAABNQAECn8gAAIUAAkK4A44DAD4AQAUAAkK4A44DAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAABNQAECn8dAAIEAAYKUwWZNADxAAAEAAYKUwWZNADxAAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn9YAAISAAoKfSBNFgDvAgASAAoKfSBNFgDvAgAAAA==.',
Da='Daddyelessar:BAAANQAECggICQAAAA==.Daemonfyre:BAAANQADCgQIBAAAAA==.Dafattyup:BAABNQAECn8oAAIFAAkKTBGhYQCxAQAFAAkKTBGhYQCxAQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAABNQAECn8VAAIPAAoKDgUvcAA4AQAPAAoKDgUvcAA4AQAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Dandrez:BAAANQAECggICAAAAA==.Darruin:BAACNQAFFH8WAAIVAAYKSyOoAQC/AQAVAAYKSyOoAQC/AQA1AAQKfz0AAxUACgpHJmkCAGADABUACgpHJmkCAGADABYAAwqIFyOLAI4AAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgUIDQABNQAECgoKHgAHAFcXAA==.Deathlydruid:BAAANQADCgEIAQAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAABNQAECn8cAAIHAAgKhgzzPgBDAQAHAAgKhgzzPgBDAQAAAA==.Deeanndra:BAABNQAECn8hAAMVAAgKGw24cgBMAQAVAAgKzwq4cgBMAQAWAAMKqw7MkwB3AAAAAA==.Demiz:BAABNQAECn81AAIKAAoKLxUkXwDxAQAKAAoKLxUkXwDxAQAAAA==.Demonicus:BAABNQAECn8gAAMEAAoKpBX/BAC1AQAEAAoKpBX/BAC1AQAFAAMKQwefLwFdAAAAAA==.Deredris:BAAANQAECgYIDgABNQAECgcIFQASAJMUAA==.',
Di='Discodruid:BAAANQAECgQICAAAAA==.Discover:BAAANQADCgcIEgAAAA==.Dixie:BAAANQAECgYIBgAAAA==.',
Dj='Djall:BAAANQAECgYIBgAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Dominant:BAAANQAECggICQAAAA==.Domittila:BAAANQAECggIDwABNQAFFAgIFgAKABMJAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8YAAQWAAgKpBz5BQCkAQAWAAUKhhn5BQCkAQAVAAUKBh8ICwBeAQAHAAIKHSO0GwC6AAA1AAQKfyQABBUACQquJGAmAKMCABUACApVI2AmAKMCAAcABAooI+cuAJUBABYAAgqeIpiBAKYAAAAA.Dorkimedes:BAAANQAECgYIEgAAAA==.Dottie:BAABNQAECn9SAAIFAAoKdA7IVgDQAQAFAAoKdA7IVgDQAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Dulcolax:BAAANQADCgQIBAABNQADCggIEwAGAAAAAA==.Durenn:BAABNQAECn81AAIPAAoKtSMxCQCdAwAPAAoKtSMxCQCdAwABNQAFFAYIFgAVAEsjAA==.Duskmane:BAAANQABCgIIAgAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAABNQAECn8pAAIRAAoKFxtpBwB8AgARAAoKFxtpBwB8AgAAAA==.Dwsavingyou:BAAANQAECggIEQABNQAECgoKHgAHAFcXAA==.',
Dy='Dyrkazen:BAABNQAECn8eAAIXAAoK/QXxHQAvAQAXAAoK/QXxHQAvAQAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECggIDQABNQAFFAgIFgAKABMJAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAFFAIIBQAVAIsRAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn9LAAMTAAoKshYSCwB8AgATAAoKshYSCwB8AgAYAAUK+RfrHwBXAQAAAA==.',
Er='Erébus:BAABNQAECn8lAAIZAAkK4BcxJAAmAgAZAAkK4BcxJAAmAgAAAA==.',
Eu='Euryphaessa:BAABNQAECn8VAAINAAcKwyBQFQDaAQANAAcKwyBQFQDaAQABNQAECgoKHgAHAFcXAA==.',
Ev='Evergreene:BAAANQADCgcIDQABNQADCggIFQAGAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAABNQAECn8YAAIYAAgKOgWDFQDeAAAYAAgKOgWDFQDeAAAAAA==.',
Ew='Ewanar:BAACNQAFFH8WAAMKAAgKEwl4CgCnAQAKAAgKEwl4CgCnAQAPAAEKAAAcNABBAAA1AAQKfyYAAwoACgo5Gjc5ADMCAAoACgo5Gjc5ADMCAA8ABArHGOajAL8AAAAA.',
Fa='Faevelia:BAAANQAECgMIBgAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAABNQAECn8YAAIUAAcK7gV5IQDMAAAUAAcK7gV5IQDMAAAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAgIHAACANMeAA==.Ferndugen:BAAANQAECgQICwAAAA==.',
Fi='Fishtank:BAAANQAECgQJBAAAAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQAGAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQAECgQIBgAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAABNQAECn8mAAIKAAoK5ge7agB0AQAKAAoK5ge7agB0AQABNQAECgoKLQABAI8MAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAABNQAECn8iAAINAAoKTCE9DgC3AgANAAoKTCE9DgC3AgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIFwAAAA==.',
Fw='Fwibble:BAABNQAECn8tAAIBAAoKjwywbwDSAQABAAoKjwywbwDSAQAAAA==.',
Fy='Fyrelady:BAAANQADCggIJAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIJAAGAAAAAA==.',
Ga='Gabbey:BAEBNQAECn8VAAIPAAgKkAiLdAAtAQAPAAgKkAiLdAAtAQABNQAFFAIIBQAOAGoMAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAABNQAECn8XAAIaAAkKUBreLwB/AgAaAAkKUBreLwB/AgAAAA==.Garagon:BAABNQAECn8vAAITAAcKWBLUFACqAQATAAcKWBLUFACqAQAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gaston:BAAANQAECggICAAAAA==.Gauss:BAABNQAECn8dAAINAAoKOw+UGgCdAQANAAoKOw+UGgCdAQABNQAECgoKLQABAI8MAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gebbo:BAAANQAECgQIBgABNQAECggICAAGAAAAAA==.Gerva:BAABNQAECn8sAAIVAAcKjg8fNABRAQAVAAcKjg8fNABRAQAAAA==.',
Gh='Ghorfindor:BAABNQAECn8YAAIbAAcKqwJLbAB1AAAbAAcKqwJLbAB1AAAAAA==.Ghostems:BAACNQAFFH8LAAIBAAcKrAwIGAC4AQABAAcKrAwIGAC4AQA1AAQKfycAAwEACQolIDJJADICAAEACQoXHDJJADICABQAAQqzI3IzAF4AAAAA.',
Gi='Gilas:BAABNQAECn8tAAQHAAkKZg3KPwA/AQAHAAgKIw7KPwA/AQAVAAYKlwaTkwDdAAAWAAEKQQcitwAxAAAAAA==.',
Gl='Glaedr:BAAANQAECgcIDQABNQADCggIFgAGAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAABNQAECn8jAAIOAAgKJQfX+AD1AAAOAAgKJQfX+AD1AAAAAA==.',
Gn='Gnikole:BAABNQAECn8YAAMUAAcKlAWRJQDDAAAUAAUKZwaRJQDDAAABAAYK0gJ4CwGiAAAAAA==.',
Go='Goswin:BAABNQAECn8ZAAIHAAcKHgo9XgDKAAAHAAcKHgo9XgDKAAAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQAECggIDgAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Grimsin:BAAANQADCgQIBAAAAA==.Grizzyy:BAAANQAECgMIBAAAAA==.Gruuven:BAAANQAECggIDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggICQAAAA==.',
Gw='Gwenivive:BAABNQAECn8sAAISAAoKmBp1OQBnAgASAAoKmBp1OQBnAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAISAAgKzQ/yhQD/AQASAAgKzQ/yhQD/AQAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8hAAMWAAcKDQpUZQANAQAWAAcKmwVUZQANAQAHAAQKHRA+lgCyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.Haunt:BAAANQAECgUIDAAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQAECgIIAgAAAA==.Hellzknîght:BAABNQAECn8iAAMWAAoKzwu9WgA/AQAWAAoKgAu9WgA/AQAVAAUKrgl8kADmAAAAAA==.Hellzshaman:BAAANQADCgIIAgAAAA==.Hellzwarlock:BAAANQADCgEIAQAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQIBwAAAA==.',
Ho='Holek:BAABNQAECn9YAAISAAoKRCNPCwAyAwASAAoKRCNPCwAyAwAAAA==.Holgo:BAACNQAFFH8PAAIaAAcKUhVlDACJAQAaAAcKUhVlDACJAQA1AAQKfy8AAhoACgo7IucVAPcCABoACgo7IucVAPcCAAAA.Holic:BAAANQAECggIAgAAAA==.Holstop:BAABNQAECn8rAAIaAAoKLB8cTAClAgAaAAoKLB8cTAClAgABNQAFFAcIJAATAO8mAA==.Holykimoly:BAAANQAECgYICgABNQAECgoKMgAcAK8eAA==.Honsz:BAAANQADCgIIAQAAAA==.Honzz:BAAANQAECgIIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAAGAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8yAAMJAAoKDx7ZJgDPAgAJAAoKDx7ZJgDPAgAdAAEKAAA6hwAiAAAAAA==.Icicle:BAAANQAECgQIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn83AAIUAAoKyRZKCgAmAgAUAAoKyRZKCgAmAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgMIBQAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQAECgQIBQAAAA==.Jaiswizzle:BAABNQAECn87AAMHAAoKzBwKIACzAgAHAAoKzBwKIACzAgAVAAEKMAZY6gArAAAAAA==.Jamien:BAABNQAECn81AAMOAAgKHhVsqAB+AQAOAAgKHhVsqAB+AQAMAAMKWAbi+wCFAAAAAA==.Jasnos:BAABNQAECn8hAAMYAAYK1Q+PFQDdAAAYAAYK1Q+PFQDdAAATAAMK/AaHNwBIAAAAAA==.Jastic:BAAANQAECgQIBAABNQAECggIDwAGAAAAAA==.Jayy:BAAANQAECgMIAwAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Jh='Jhey:BAAANQAECgIIAgAAAA==.Jhunter:BAAANQAECgIIAgAAAA==.',
Ju='Jubileehunt:BAAANQAECggIBwAAAA==.',
Ka='Kaathe:BAABNQAECn8XAAMBAAUKzxrbKQFGAQABAAUKzxrbKQFGAQAeAAEKAACyEAAAAAAAAA==.Kaidiis:BAABNQAECn8tAAIOAAoKRArfnwCOAQAOAAoKRArfnwCOAQAAAA==.Karbonn:BAABNQAECn8UAAIYAAoKkwdMDgBiAQAYAAoKkwdMDgBiAQAAAA==.Katiwompus:BAAANQAECgUIBwAAAA==.Katrina:BAAANQADCgIIAgABNQAECgoKeQAbAOkZAA==.Kay:BAAANQAECggICAAAAA==.',
Kb='Kbear:BAAANQAECgYIAwAAAA==.',
Ke='Kegbreaker:BAACNQAFFH8GAAIJAAIKqQvaLQB3AAAJAAIKqQvaLQB3AAA1AAQKf0wAAgkACgqFHGocAPcCAAkACgqFHGocAPcCAAAA.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAABNQAECn8XAAIMAAoKHBKtRwD1AQAMAAoKHBKtRwD1AQAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8yAAIcAAoKrx6FBAD8AgAcAAoKrx6FBAD8AgAAAA==.Kimbustible:BAABNQAECn8YAAIBAAgKTB0+ZQDrAQABAAgKTB0+ZQDrAQABNQAECgoKMgAcAK8eAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAABNQAECn8cAAIOAAgKQg/uwgBOAQAOAAgKQg/uwgBOAQAAAA==.',
Ko='Komodostyle:BAABNQAECn85AAMTAAoKnQeXHgAdAQATAAgKVQeXHgAdAQAfAAkK3QQbDQAcAQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8nAAIBAAkKNgaDxgAaAQABAAkKNgaDxgAaAQAAAA==.',
Kr='Krisarugala:BAABNQAECn8ZAAILAAcKMA+EUwCMAQALAAcKMA+EUwCMAQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAABNQAECn8jAAISAAoK4xhAPABfAgASAAoK4xhAPABfAgAAAA==.Kurogami:BAAANQADCgQIBQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kymal:BAAANQAECgQIBAAAAA==.Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAABNQAECn8UAAIVAAcKNxRFZgB4AQAVAAcKNxRFZgB4AQAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMPAAIKPwuIJgCSAAAPAAIKPwuIJgCSAAAKAAIKhwI7JwBrAAA1AAQKfy0AAw8ACQqgF2U+AHwCAA8ACQqgF2U+AHwCAAoAAgr7BDLfAFsAAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8VAAMUAAgKHxxRAAAyAgAUAAgKfhtRAAAyAgABAAUKuhu0JgBRAQA1AAQKfykAAwEACgoOJDVCAAADAAEACgrBIzVCAAADABQABAqpI10eAPkAAAAA.Lazerturkey:BAABNQAECn8gAAIDAAoKBxYFFwD7AQADAAoKBxYFFwD7AQAAAA==.Laërtes:BAABNQAECn8VAAIOAAUKBQbKPQGSAAAOAAUKBQbKPQGSAAAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lianne:BAAANQAECgcIBwABNQAECgoKVAATAIQeAA==.Lightbill:BAACNQAFFH8GAAIMAAIK6g2IHwCEAAAMAAIK6g2IHwCEAAA1AAQKf0UAAwwACgrPHxcKAIADAAwACgrPHxcKAIADAA4AAgpJCS50AWkAAAAA.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8zAAIKAAoK9h2jKADBAgAKAAoK9h2jKADBAgAAAA==.Lilxblitzx:BAABNQAECn8aAAIMAAcK8wuKrQAlAQAMAAcK8wuKrQAlAQAAAA==.Lilzdrlockz:BAAANQADCgQIBAAAAA==.Lilzriotz:BAAANQAECgUICgAAAA==.',
Lo='Lockoclock:BAAANQAECgMIAwAAAA==.Locomotion:BAAANQADCggICAAAAA==.Lovecraft:BAAANQADCgQIBwAAAA==.Lowlife:BAAANQABCgQIBAABNQAFFAEIAQAGAAAAAA==.',
Lu='Lucyvar:BAABNQAECn8sAAIbAAkKQghuQQAwAQAbAAkKQghuQQAwAQAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAACNQAFFH8GAAMNAAIKBw8zCwB3AAANAAIKBw8zCwB3AAAOAAIKfQf0KAB2AAA1AAQKf0MAAw0ACgpjGzQTAPoBAA4ACgrXGjRRADkCAA0ACgpOFTQTAPoBAAAA.Marlow:BAABNQAECn8zAAIFAAoKNRTFOwAkAgAFAAoKNRTFOwAkAgAAAA==.Marotal:BAABNQAECn8lAAIBAAkKFRL8ugAOAgABAAkKFRL8ugAOAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgcIEQAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Mears:BAAANQAECgMIAwAAAA==.Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAABNQAECn8yAAISAAgK2hTEZQD5AQASAAgK2hTEZQD5AQAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.Meridae:BAAANQAECgYIBgABNQAECggICAAGAAAAAA==.',
Mh='Mhael:BAAANQAECgQICgAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minphoria:BAAANQADCgcICAAAAA==.Minsofar:BAAANQAECgUICgAAAA==.Mistilinn:BAABNQAECn86AAIgAAoKCASJKgAWAQAgAAoKCASJKgAWAQAAAA==.Miyri:BAAANQAECgEIAQABNQAFFAUKCQAXAIAUAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8XAAILAAgKOBphBQBPAgALAAgKOBphBQBPAgA1AAQKf9sAAgsACgr3JiAAAKADAAsACgr3JiAAAKADAAAA.Morpheus:BAAANQAECgUICwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8tAAMUAAgKERaEHgD3AAABAAgKERYRywDvAQAUAAUKMBiEHgD3AAAAAA==.',
My='Myeyes:BAAANQAECgUIBAAAAA==.Mylinkah:BAABNQAECn8hAAQhAAoKkhFpGwDOAQAhAAoKkhFpGwDOAQAXAAEKpAGhVQAeAAAiAAIKQgAkLQAQAAAAAA==.Mynamefizz:BAEANQAECgQIBgABNQAECgQIBQAGAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgABNQADCggICAAGAAAAAA==.',
['Mé']='Méasha:BAAANQAECgIIAgAAAA==.',
Ni='Nicola:BAABNQAECn8fAAMJAAoKqhnMTwA1AgAJAAoKqhnMTwA1AgAdAAEKAAB+hgAjAAAAAA==.Nightxwish:BAABNQAECn8kAAQjAAYKtB0UEQAXAQAJAAYK0Bw/XQDKAQAjAAQK5BcUEQAXAQAdAAEKDAfRfgAtAAAAAA==.Nik:BAAANQAECgYICAAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Nohlife:BAAANQABCgIIAgAAAA==.Noisemarine:BAAANQAECggICAAAAA==.Norellia:BAABNQAECn8iAAMjAAkKTBT6AwAbAgAjAAkKTBT6AwAbAgAdAAUKKAleRQCWAAAAAA==.Northspirit:BAABNQAECn8WAAIPAAcKJgbKlgDaAAAPAAcKJgbKlgDaAAAAAA==.',
Nu='Nuit:BAAANQAECgMIAgAAAA==.',
Ny='Nyarlothep:BAABNQAECn8dAAIcAAcKrBB4EQAxAQAcAAcKrBB4EQAxAQAAAA==.Nymh:BAABNQAECn8cAAQFAAgK2QpAmwAhAQAFAAgKZglAmwAhAQAkAAIKKgmmIgBlAAAEAAEKzhCeOQAxAAAAAA==.Nyx:BAAANQADCgIIAgABNQAECggINQAOAB4VAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYICAABNQAECgoKJQACABYdAA==.Odins:BAABNQAECn8lAAMCAAoKFh3pBgAUAwACAAoKCB3pBgAUAwAPAAgKixvGQwBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgMIBAABNQADCggIEwAGAAAAAA==.Ohyikers:BAACNQAFFH8cAAILAAcKYCVABgD9AQALAAcKYCVABgD9AQA1AAQKf3UABAsACgpEJvYAAPUDAAsACgpEJvYAAPUDAAMAAgrEHslCALMAABAAAQr1HqQ8AFwAAAAA.',
Ok='Oken:BAABNQAECn8kAAMLAAYK4AcxYQCeAAALAAYK4AcxYQCeAAADAAQKswEEaQBAAAAAAA==.',
Op='Oppenheimer:BAAANQADCgEIAQAAAA==.Opportunity:BAAANQADCgcIBwABNQAFFAMIBQAMADMfAA==.',
Ot='Otso:BAABNQAECn8jAAIDAAcKiB4VEQBPAgADAAcKiB4VEQBPAgABNQAECgkJJQAZAOAXAA==.',
Pa='Paapi:BAAANQAECggICQAAAA==.Paco:BAAANQADCgYIBgAAAA==.Paladime:BAABNQAECn8YAAIOAAcKPg3F0AB6AQAOAAcKPg3F0AB6AQAAAA==.Pallek:BAAANQAECggIEQABNQAECgoKWAASAEQjAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgQIBwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.Pewpewbite:BAAANQAECgEIAQAAAA==.',
Ph='Phantomarrow:BAAANQAECgIIAQAAAA==.Phantomcat:BAAANQAECgUIBgAAAA==.Phantomlock:BAACNQAFFH8IAAMFAAUKCQO4IQCpAAAFAAUKCQO4IQCpAAAEAAEK0gGqFgA4AAA1AAQKfyMAAwUACgohFmRYAE0CAAUACgrzFWRYAE0CAAQABAoODiU9AM0AAAAA.Pharasan:BAABNQAECn8XAAIPAAgKDQu8ngBZAQAPAAgKDQu8ngBZAQAAAA==.Phatcow:BAABNQAECn8/AAIKAAoKaCEUCgB8AwAKAAoKaCEUCgB8AwAAAA==.Phude:BAABNQAECn9mAAIOAAoKHxvVPgBuAgAOAAoKHxvVPgBuAgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Ps='Psylock:BAAANQAECgUIEAAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAABNQAECn8XAAIFAAkKhQsbXwC4AQAFAAkKhQsbXwC4AQAAAA==.',
Py='Pyramys:BAABNQAECn8mAAMlAAoK8B19DgCQAgAlAAoK8B19DgCQAgAmAAUKIhz7UAB6AQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.Quepaoka:BAAANQABCgMIAwAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQAECgQIBAAAAA==.Rawcky:BAAANQAECggICwAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgIIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAAGAAAAAA==.Rivër:BAAANQAECgYIBQAAAA==.',
Ro='Rolls:BAAANQAECgcIDwAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAAUAOAOAA==.Rootoo:BAAANQADCgUIBgAAAA==.Roozer:BAAANQADCggIIwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAQABNQAECgkJJQAYABsVAA==.Sad:BAABNQAECn8nAAIBAAoK/hl6UgAaAgABAAoK/hl6UgAaAgAAAA==.Saelina:BAAANQAECgYIBwABNQAFFAUKCQAXAIAUAA==.Saelyria:BAABNQAECn8VAAIIAAkKChRHKACuAQAIAAkKChRHKACuAQABNQAFFAUKCQAXAIAUAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAABNQAECn8lAAIMAAoKpwijsgC3AAAMAAoKpwijsgC3AAAAAA==.Sainthymn:BAAANQAECggIEQABNQAECgoKJQAMAKcIAA==.Sainttide:BAABNQAECn8gAAMPAAoKVQez2QDhAAAPAAkKjwOz2QDhAAAKAAEKnB0C4wBUAAABNQAECgoKJQAMAKcIAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAABNQAECn87AAIBAAoKGA2KcADQAQABAAoKGA2KcADQAQAAAA==.Savallyne:BAAANQAECgEIAgABNQAFFAUKCQAXAIAUAA==.Sayberix:BAAANQAFFAIIAgABNQAECgcIDAAGAAAAAA==.',
Sc='Scoreboard:BAACNQAFFH8dAAMnAAkKXiESAAAzAgAnAAkKXiESAAAzAgAlAAEKAACcKwAAAAA1AAQKfzoABCcACgr0JuYAAJwDACcACQoIJ+YAAJwDACUAAwoEJ9JsAGQBACYAAwrGG9E9AJQAAAAA.Scupper:BAACNQAFFH8GAAInAAIKrwgdAQB8AAAnAAIKrwgdAQB8AAA1AAQKf0MAAicACgofG6ABAHACACcACgofG6ABAHACAAAA.',
Se='Sedric:BAAANQAECgEIAQAAAA==.Selline:BAAANQAECgQIDgAAAA==.Selsonblue:BAAANQADCggIEwAAAA==.Sesskaa:BAABNQAECn8xAAMKAAkKQx6MHADVAgAKAAkKQx6MHADVAgACAAcKVAO0JgDVAAAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgcIEgAAAA==.Shathos:BAAANQADCgUIAQAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgAGAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAABNQAECn8YAAIHAAoKvBwhQgD0AQAHAAoKvBwhQgD0AQAAAA==.',
Sk='Skaro:BAABNQAECn8tAAIXAAoKThh5CQDBAgAXAAoKThh5CQDBAgAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgoKLQAXAE4YAA==.Skarosham:BAAANQAECgQIBAABNQAECgoKLQAXAE4YAA==.Sketch:BAABNQAECn8iAAImAAkKIQwrOQDwAQAmAAkKIQwrOQDwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8LAAINAAQKEhIiBwDCAAANAAQKEhIiBwDCAAA1AAQKfzoAAg0ACgq4IZYJAAQDAA0ACgq4IZYJAAQDAAAA.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Sobekk:BAAANQAECggIEQAAAA==.Solomun:BAABNQAECn9DAAIMAAoKOBu0IwDcAgAMAAoKOBu0IwDcAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Sp='Spinky:BAAANQAECggIDQAAAA==.Sploosh:BAAANQAECgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIJQAAAA==.Stinko:BAABNQAECn8VAAMEAAcKRgZtFgCpAAAEAAcKRgZtFgCpAAAFAAUKVwH2MQFXAAAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAABNQAECn8WAAIFAAcKyhDFlwCrAQAFAAcKyhDFlwCrAQAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAABNQAECn8jAAMIAAcKvRHSOwAjAQAIAAYKng/SOwAjAQALAAEKqAc5jAAxAAAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQAGAAAAAA==.',
Su='Surloyn:BAAANQAECgUIBQABNQAECgoKOwAHAMwcAA==.',
Sw='Swampert:BAACNQAFFH8HAAIaAAQKLBIvIwDlAAAaAAQKLBIvIwDlAAA1AAQKfy0AAhoACQrfHSYxAPsCABoACQrfHSYxAPsCAAAA.Swamperting:BAAANQAECgMIBAABNQAFFAQIBwAaACwSAA==.Swayaos:BAABNQAECn8pAAIFAAoKbhEWdgAAAgAFAAoKbhEWdgAAAgABNQAFFAQICgAdAL0GAA==.Swaye:BAACNQAFFH8KAAIdAAQKvQYgDQDDAAAdAAQKvQYgDQDDAAA1AAQKfz0AAh0ACgqPFqQjABUCAB0ACgqPFqQjABUCAAAA.Swifte:BAAANQAECgQIBgAAAA==.Swimchick:BAABNQAECn8gAAISAAgKQA0wlACNAQASAAgKQA0wlACNAQAAAA==.Swizzle:BAABNQAECn8cAAMiAAcKOxOOFgB6AQAiAAcKOxOOFgB6AQAhAAUKNRB+QgAEAQABNQAECgoKOwAHAMwcAA==.',
Sy='Syfa:BAABNQAECn8iAAMWAAoKjBHKLwDsAQAWAAoKjBHKLwDsAQAHAAMKugNErgAlAAAAAA==.Syllena:BAACNQAFFH8JAAIXAAUKgBSWBAB3AQAXAAUKgBSWBAB3AQA1AAQKfz0AAxcACgrKJLUFAEMDABcACgrKJLUFAEMDACEABAr0EqZKANEAAAE1AAUUBQoJABcAgBQA.Syndicalism:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.Syraelia:BAAANQAECgEIAQABNQAFFAUKCQAXAIAUAA==.Sythia:BAAANQADCgEIAQABNQAFFAQICAAYAEkNAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggILgAAAA==.',
Ta='Tacomistress:BAAANQADCgUICQAAAA==.Tagmoo:BAACNQAFFH8GAAIaAAIKNx5vIgCwAAAaAAIKNx5vIgCwAAA1AAQKf0wAAhoACgpDJd0FAF8DABoACgpDJd0FAF8DAAAA.Talashea:BAAANQAECgMIAwAAAA==.Talion:BAAANQADCgEIAQABNQAECgoKNAADADwUAA==.Taloon:BAABNQAECn8gAAIbAAoK1xNxJgDYAQAbAAoK1xNxJgDYAQAAAA==.Taltost:BAABNQAECn8nAAISAAgKJRLqlwCEAQASAAgKJRLqlwCEAQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAABNQAECn8bAAIOAAkKJAyi8AA7AQAOAAkKJAyi8AA7AQAAAA==.Tarvält:BAAANQAECgQIBgAAAA==.',
Te='Teksuo:BAABNQAECn9TAAIhAAoK/BOJGQDjAQAhAAoK/BOJGQDjAQAAAA==.Telamontgrim:BAAANQAECgUIAwAAAA==.Tenithon:BAACNQAFFH8FAAIMAAMKMx9mEwANAQAMAAMKMx9mEwANAQA1AAQKf3sAAgwACgosJqUBANcDAAwACgosJqUBANcDAAAA.Tenscales:BAABNQAECn8wAAITAAoKdRe1CAC+AgATAAoKdRe1CAC+AgAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBAAAAA==.Tholaren:BAABNQAECn8rAAISAAcK2xCAlQCKAQASAAcK2xCAlQCKAQAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAABNQAECn8WAAIUAAkK0gzbFwA7AQAUAAkK0gzbFwA7AQAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Totemfreak:BAAANQADCgUICQAAAA==.Touchit:BAAANQAECgMICAAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAABNQAECn8kAAISAAYKZA9s1wADAQASAAYKZA9s1wADAQAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAABNQAECn8VAAMSAAcKkxRWtABJAQASAAcKkxRWtABJAQAgAAUK1Qd6WwC3AAAAAA==.Trillion:BAAANQAECgQICQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAABNQAECn8bAAMKAAYKzxijggAsAQAKAAUK9xWjggAsAQAPAAYK8w4HlQDfAAAAAA==.',
Ud='Udari:BAABNQAECn8vAAIOAAkKAhd+XAAbAgAOAAkKAhd+XAAbAgAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQAECgYIBgAAAA==.',
Va='Varithal:BAABNQAECn9UAAITAAoKhB6JAwBxAwATAAoKhB6JAwBxAwAAAA==.Vastectomy:BAAANQAECgUIDAAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAABNQAECn8rAAISAAgKfwywoAByAQASAAgKfwywoAByAQAAAA==.',
Vi='Vicious:BAACNQAFFH8IAAIKAAMK6Bn9GgDCAAAKAAMK6Bn9GgDCAAA1AAQKfy4AAgoACQolHrAlAM4CAAoACQolHrAlAM4CAAAA.Violetsorren:BAAANQADCggICAAAAA==.Vixin:BAABNQAECn8bAAMKAAcKExDcfQA6AQAKAAcKExDcfQA6AQAPAAUKDwjT4wDPAAAAAA==.',
Vo='Voidsaack:BAABNQAECn80AAMEAAoKxwwZBgCIAQAEAAkKqgwZBgCIAQAFAAgKMgYSrAD8AAAAAA==.Vortan:BAABNQAECn80AAIoAAgKZR2CAwDTAgAoAAgKZR2CAwDTAgAAAA==.',
Vr='Vreya:BAAANQADCgUIDgABNQADCggIFwAGAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynnd:BAAANQAECgYIBgAAAA==.Vynthus:BAABNQAECn8ZAAIZAAoKjwvfIQCQAQAZAAoKjwvfIQCQAQAAAA==.',
Wa='Warhundin:BAEANQAECggIBgABNQAFFAIIBQAOAGoMAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAABNQAECn8UAAQWAAYK1guVXgAsAQAWAAYK1guVXgAsAQAHAAEKAADpxwA5AAAVAAEKywY46wAqAAAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAABNQAECn8wAAIDAAgKbgvaNQDzAAADAAgKbgvaNQDzAAAAAA==.Whispp:BAAANQAECgUIBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQAGAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.Wisk:BAAANQAECgMIAwAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgAGAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgAGAAAAAA==.',
Xu='Xuny:BAABNQAECn8YAAISAAYKxQ2UsgBNAQASAAYKxQ2UsgBNAQAAAA==.',
Ya='Yahzway:BAAANQAECgEIAQAAAA==.',
Yo='Yordi:BAABNQAECn8aAAISAAUKvwSWBgH5AAASAAUKvwSWBgH5AAAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuria:BAABNQAECn8YAAIbAAYK8QvHVQDLAAAbAAYK8QvHVQDLAAAAAA==.Yuzuriha:BAABNQAECn9XAAISAAoKriOpCQA+AwASAAoKriOpCQA+AwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8yAAIbAAoKjBMkKgBQAgAbAAoKjBMkKgBQAgABNQAFFAIIBQAOAGoMAA==.',
Zi='Zipy:BAABNQAECn8vAAIJAAcKCRbwWADaAQAJAAcKCRbwWADaAQAAAA==.',
Zo='Zorathar:BAAANQADCgIIAwAAAA==.Zorma:BAAANQAECgUIBQAAAA==.',
Zy='Zyllo:BAAANQADCggIGQAAAA==.',
['Zæ']='Zæ:BAAANQAECgQIBAAAAA==.',
['Äe']='Äemond:BAAANQADCgIIAgAAAA==.',
['Ål']='Ålïce:BAABNQAECn9MAAIOAAoK9xvSPAB0AgAOAAoK9xvSPAB0AgAAAA==.',
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
