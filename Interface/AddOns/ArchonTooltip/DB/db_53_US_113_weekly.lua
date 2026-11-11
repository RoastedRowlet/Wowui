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
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg7W+wCVAQABAAcKrg7W+wCVAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgIIAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.Aksala:BAAANQABCgIIAgAAAA==.',
Al='Alaralia:BAAANQAECggIEgABNQAFFAgIGwACANMeAA==.Alarathel:BAAANQADCggICAABNQAFFAgIGwACANMeAA==.Aleion:BAAANQADCgUIBQABNQAECgoKMAADAPYTAA==.Alyssandra:BAABNQAECn8mAAMEAAoKqw37HgB3AQAEAAcKWw/7HgB3AQAFAAoKQgdudABoAQAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIEQAAAA==.Ammalane:BAAANQADCgQICQABNQADCggIEQAGAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.Angler:BAAANQADCgIIAQAAAA==.',
Ap='Apollyon:BAABNQAECn8cAAIHAAoKaxbfMgBwAQAHAAoKaxbfMgBwAQAAAA==.',
Ar='Arangarr:BAABNQAECn9IAAIIAAoKCiNBAgDrAwAIAAoKCiNBAgDrAwAAAA==.Arcanu:BAAANQAECgQIBQAAAA==.Aresiuz:BAABNQAECn8fAAIJAAkKoRbcZwDnAQAJAAkKoRbcZwDnAQABNQAFFAcIFAAKAGYJAA==.Areyana:BAAANQAECggIEAAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAABNQAECn8WAAILAAYKUBHWPAAkAQALAAYKUBHWPAAkAQAAAA==.Arrietty:BAABNQAECn8fAAIMAAYK8BPPcwBGAQAMAAYK8BPPcwBGAQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAABNQAECn8hAAMNAAoK1gsgHwBgAQANAAoK1gsgHwBgAQAOAAYK+AaWHQHuAAAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAABNQAECn8fAAIPAAYKBhezeAAMAQAPAAYKBhezeAAMAQAAAA==.',
Az='Azeriall:BAABNQAECn9UAAIPAAoKbRqXIABfAgAPAAoKbRqXIABfAgAAAA==.Azerodru:BAAANQADCgEIAgAAAA==.',
Ba='Bacnfen:BAABNQAECn8hAAIPAAkKJQptbQApAQAPAAkKJQptbQApAQAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAAGAAAAAA==.Banshiï:BAABNQAECn8cAAIEAAgKagclKQAyAQAEAAgKagclKQAyAQAAAA==.Baratheøn:BAABNQAECn8pAAQIAAgK9xb2IgDBAQAIAAgK9xb2IgDBAQAQAAYK6QeOJADAAAALAAEK2gLNjwAgAAAAAA==.Bason:BAAANQAECggIDgAAAA==.',
Be='Beeftard:BAABNQAECn8jAAIMAAoKKhkdNgCLAgAMAAoKKhkdNgCLAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Blessica:BAAANQAECgMIAwAAAA==.Bloodletterr:BAAANQADCgMIAwAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgcICwAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwAGAAAAAA==.',
Bu='Buckey:BAAANQAECgMIBAAAAA==.Bullythekid:BAAANQAECgYICQAAAA==.',
By='Byzantium:BAABNQAECn8tAAIRAAgKUAmJHQD9AAARAAgKUAmJHQD9AAAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAABNQAECn8YAAISAAgKtAQdsgAyAQASAAgKtAQdsgAyAQAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwATAK4SAA==.Celitha:BAAANQADCggIBwAAAA==.',
Ch='Chromatic:BAAANQAECgUIBQAAAA==.Chronic:BAAANQAECgIIBAABNQAECgoKLwAOANkUAA==.',
Ci='Cinderflamez:BAAANQABCgMIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAABNQADCggICAAGAAAAAA==.Coldstorm:BAABNQAECn8gAAIUAAkK4A44DAD4AQAUAAkK4A44DAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAABNQAECn8dAAIEAAYKUwWZNADxAAAEAAYKUwWZNADxAAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn9PAAISAAoKMyDdFADtAgASAAoKMyDdFADtAgAAAA==.',
Da='Daddyelessar:BAAANQAECggICQAAAA==.Daemonfyre:BAAANQADCgQIBAAAAA==.Dafattyup:BAABNQAECn8oAAIFAAkKTBE9WQC1AQAFAAkKTBE9WQC1AQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAAANQAECggICgAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Dandrez:BAAANQAECggICAAAAA==.Darruin:BAACNQAFFH8WAAIVAAYKSyNMAQDJAQAVAAYKSyNMAQDJAQA1AAQKfz0AAxUACgpHJggCAGUDABUACgpHJggCAGUDABYAAwqIF/6CAJAAAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgYICwABNQAECgoKHAAHAGsWAA==.Deathlydruid:BAAANQADCgEIAQAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAABNQAECn8bAAIHAAcKxAyMQwAhAQAHAAcKxAyMQwAhAQAAAA==.Deeanndra:BAABNQAECn8fAAMVAAgK8gu4cgBMAQAVAAgKzwq4cgBMAQAWAAIKxAyapwA7AAAAAA==.Demiz:BAABNQAECn81AAIKAAoKLxUkXwDxAQAKAAoKLxUkXwDxAQAAAA==.Demonicus:BAABNQAECn8eAAMEAAkK1hXQBQB5AQAEAAkK1hXQBQB5AQAFAAMKQwefLwFdAAAAAA==.Deredris:BAAANQAECgYIDgABNQAECgcIFQASAJMUAA==.',
Di='Discodruid:BAAANQAECgQICAAAAA==.Discover:BAAANQADCgcIEgAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dj='Djall:BAAANQAECgYIBgAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Dominant:BAAANQAECggICQAAAA==.Domittila:BAAANQAECggIDwABNQAFFAcIFAAKAGYJAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8YAAQWAAgKpBz5BQCkAQAWAAUKhhn5BQCkAQAVAAUKBh8ICwBeAQAHAAIKHSO0GwC6AAA1AAQKfyQABBUACQquJGAmAKMCABUACApVI2AmAKMCAAcABAooI/MrAJcBABYAAgqeIpiBAKYAAAAA.Dorkimedes:BAAANQAECgcIEgAAAA==.Dottie:BAABNQAECn9JAAIFAAoK7gxMVQDAAQAFAAoK7gxMVQDAAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Dulcolax:BAAANQADCgQIBAABNQADCggIEwAGAAAAAA==.Durenn:BAABNQAECn81AAIPAAoKtSMxCQCdAwAPAAoKtSMxCQCdAwABNQAFFAYIFgAVAEsjAA==.Duskmane:BAAANQABCgIIAgAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAABNQAECn8gAAIRAAgKwBclFABjAQARAAgKwBclFABjAQAAAA==.Dwsavingyou:BAAANQAECgcICgABNQAECgoKHAAHAGsWAA==.',
Dy='Dyrkazen:BAABNQAECn8dAAIXAAkK/AWSHgAUAQAXAAkK/AWSHgAUAQAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECggIDQABNQAFFAcIFAAKAGYJAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAFFAIIBQAVAIsRAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn9LAAMTAAoKshZICgB8AgATAAoKshZICgB8AgAYAAUK+RfrHwBXAQAAAA==.',
Er='Erébus:BAABNQAECn8hAAIZAAkKrxYxJAAmAgAZAAkKrxYxJAAmAgAAAA==.',
Eu='Euryphaessa:BAAANQAECgUIDwABNQAECgoKHAAHAGsWAA==.',
Ev='Evergreene:BAAANQADCgcIDQABNQADCggIEQAGAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAABNQAECn8WAAIYAAcK6gTBFwCuAAAYAAcK6gTBFwCuAAAAAA==.',
Ew='Ewanar:BAACNQAFFH8UAAMKAAcKZgl4CgCnAQAKAAcKZgl4CgCnAQAPAAEKAAAcNABBAAA1AAQKfyYAAwoACgo5GtMzADcCAAoACgo5GtMzADcCAA8ABArHGNKZAL8AAAAA.',
Fa='Faevelia:BAAANQAECgIIAwAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAABNQAECn8YAAIUAAcK7gV4HgDNAAAUAAcK7gV4HgDNAAAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAgIGwACANMeAA==.Ferndugen:BAAANQAECgMIBwAAAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECgoKRwASAHsaAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQAGAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQAECgQIBgAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAABNQAECn8gAAIKAAoK5gdxZAByAQAKAAoK5gdxZAByAQABNQAECgoKJwABANULAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAABNQAECn8eAAINAAgK4iI9DgC3AgANAAgK4iI9DgC3AgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIFwAAAA==.',
Fw='Fwibble:BAABNQAECn8nAAIBAAoK1QuubADHAQABAAoK1QuubADHAQAAAA==.',
Fy='Fyrelady:BAAANQADCggIIAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIIAAGAAAAAA==.',
Ga='Gabbey:BAEBNQAECn8VAAIPAAgKkAi5awAtAQAPAAgKkAi5awAtAQABNQAECgkJHAASALgNAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAABNQAECn8XAAIaAAkKUBpbKwCFAgAaAAkKUBpbKwCFAgAAAA==.Garagon:BAABNQAECn8pAAITAAcKJg29GQBDAQATAAcKJg29GQBDAQAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAABNQAECn8YAAINAAoKgQz9HQBpAQANAAoKgQz9HQBpAQABNQAECgoKJwABANULAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gebbo:BAAANQAECgQIBgABNQAECgYIBgAGAAAAAA==.Gerva:BAABNQAECn8mAAIVAAcKjg8MMQBRAQAVAAcKjg8MMQBRAQAAAA==.',
Gh='Ghorfindor:BAABNQAECn8XAAIbAAYKzwFnbwBbAAAbAAYKzwFnbwBbAAAAAA==.Ghostems:BAACNQAFFH8JAAIBAAYK8w0IGAC4AQABAAYK8w0IGAC4AQA1AAQKfycAAwEACQolIARDADYCAAEACQoXHARDADYCABQAAQqzI6YvAF8AAAAA.',
Gi='Gilas:BAABNQAECn8qAAMHAAkKYAwyQAAwAQAHAAgKWQ0yQAAwAQAVAAYKlwaTkwDdAAAAAA==.',
Gl='Glaedr:BAAANQAECgcIDQABNQADCggIFgAGAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAABNQAECn8jAAIOAAgKJQfS6QD3AAAOAAgKJQfS6QD3AAAAAA==.',
Gn='Gnikole:BAABNQAECn8UAAMUAAYK+gWRJQDDAAAUAAUKZwaRJQDDAAABAAUKoAILEgGGAAAAAA==.',
Go='Goswin:BAABNQAECn8VAAIHAAYKLQrGZACpAAAHAAYKLQrGZACpAAAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQAECggIDAAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Grimsin:BAAANQADCgQIBAAAAA==.Grizzyy:BAAANQAECgMIBAAAAA==.Gruuven:BAAANQAECggIDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggICQAAAA==.',
Gw='Gwenivive:BAABNQAECn8rAAISAAoKmBr1MgBqAgASAAoKmBr1MgBqAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAISAAgKzQ/yhQD/AQASAAgKzQ/yhQD/AQAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8hAAMWAAcKDQpUZQANAQAWAAcKmwVUZQANAQAHAAQKHRA+lgCyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.Haunt:BAAANQAECgUIDAAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQAECgIIAgAAAA==.Hellzknîght:BAABNQAECn8iAAMWAAoKzwvpVQAmAQAWAAoKgAvpVQAmAQAVAAUKrgl8kADmAAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hellzwarlock:BAAANQADCgEIAQAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQIBwAAAA==.',
Ho='Holek:BAABNQAECn9XAAISAAoKRCNeCQA6AwASAAoKRCNeCQA6AwAAAA==.Holgo:BAACNQAFFH8PAAIaAAcKUhW1CQCWAQAaAAcKUhW1CQCWAQA1AAQKfy8AAhoACgo7IjATAP8CABoACgo7IjATAP8CAAAA.Holic:BAAANQAECgQIAgAAAA==.Holstop:BAABNQAECn8rAAIaAAoKLB8cTAClAgAaAAoKLB8cTAClAgABNQAFFAcIJAATAO8mAA==.Holykimoly:BAAANQAECgYICgABNQAECgoKMgAcAK8eAA==.Honzz:BAAANQAECgIIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAAGAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8yAAMJAAoKDx7ZJgDPAgAJAAoKDx7ZJgDPAgAdAAEKAAA6hwAiAAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn83AAIUAAoKyRZKCgAmAgAUAAoKyRZKCgAmAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgMIBQAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQAECgQIBQAAAA==.Jaiswizzle:BAABNQAECn87AAMHAAoKzBwKIACzAgAHAAoKzBwKIACzAgAVAAEKMAZY6gArAAAAAA==.Jamien:BAABNQAECn8vAAMOAAgKoRTwoQB0AQAOAAgKoRTwoQB0AQAMAAMKWAbi+wCFAAAAAA==.Jasnos:BAABNQAECn8cAAMYAAYK1Q9NFADeAAAYAAYK1Q9NFADeAAATAAEKnQYaUgAoAAAAAA==.Jastic:BAAANQAECgQIBAABNQAECggIDgAGAAAAAA==.Jayy:BAAANQAECgMIAwAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Jh='Jhey:BAAANQAECgIIAgAAAA==.Jhunter:BAAANQAECgIIAgAAAA==.',
Ju='Jubileehunt:BAAANQAECggIBwAAAA==.',
Ka='Kaathe:BAABNQAECn8XAAMBAAUKzxrbKQFGAQABAAUKzxrbKQFGAQAeAAEKAADyDgAAAAAAAA==.Kaidiis:BAABNQAECn8kAAIOAAgK0ggU4wBVAQAOAAgK0ggU4wBVAQAAAA==.Karbonn:BAAANQAECggIEAAAAA==.Katiwompus:BAAANQAECgQIBgAAAA==.Katrina:BAAANQADCgIIAgABNQAECgoKZwAbAN8YAA==.Kay:BAAANQAECggICAAAAA==.',
Kb='Kbear:BAAANQAECgYIAwAAAA==.',
Ke='Kegbreaker:BAABNQAECn9IAAIJAAoK1xv+GQD2AgAJAAoK1xv+GQD2AgAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAABNQAECn8XAAIMAAoKHBIYQAACAgAMAAoKHBIYQAACAgAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8yAAIcAAoKrx6FBAD8AgAcAAoKrx6FBAD8AgAAAA==.Kimbustible:BAABNQAECn8YAAIBAAgKTB2mXADwAQABAAgKTB2mXADwAQABNQAECgoKMgAcAK8eAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAABNQAECn8VAAIOAAgKQAzv9ADlAAAOAAgKQAzv9ADlAAAAAA==.',
Ko='Komodostyle:BAABNQAECn8wAAMTAAkKYgiBHAAgAQATAAgKVQeBHAAgAQAfAAQK0QULFgBwAAAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8nAAIBAAkKNgayvAAbAQABAAkKNgayvAAbAQAAAA==.',
Kr='Krisarugala:BAABNQAECn8ZAAILAAcKMA+EUwCMAQALAAcKMA+EUwCMAQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAABNQAECn8cAAISAAcKKhzLiQCIAQASAAcKKhzLiQCIAQAAAA==.Kurogami:BAAANQADCgQIBQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kymal:BAAANQAECgQIBAAAAA==.Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAABNQAECn8UAAIVAAcKNxRFZgB4AQAVAAcKNxRFZgB4AQAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMPAAIKPwuIJgCSAAAPAAIKPwuIJgCSAAAKAAIKhwI7JwBrAAA1AAQKfy0AAw8ACQqgF2U+AHwCAA8ACQqgF2U+AHwCAAoAAgr7BI/WAFsAAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8VAAMUAAgKHxxRAAAyAgAUAAgKfhtRAAAyAgABAAUKuhu0JgBRAQA1AAQKfykAAwEACgoOJDVCAAADAAEACgrBIzVCAAADABQABAqpI10eAPkAAAAA.Lazerturkey:BAABNQAECn8gAAIDAAoKBxYFFwD7AQADAAoKBxYFFwD7AQAAAA==.Laërtes:BAABNQAECn8VAAIOAAUKBQY/LgGSAAAOAAUKBQY/LgGSAAAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lianne:BAAANQAECgcIBwABNQABCgEIAQAGAAAAAA==.Lightbill:BAABNQAECn9BAAMMAAoKzx+oCACIAwAMAAoKzx+oCACIAwAOAAIKSQkudAFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8zAAIKAAoK9h2jKADBAgAKAAoK9h2jKADBAgAAAA==.Lilxblitzx:BAABNQAECn8aAAIMAAcK8wv7jwD3AAAMAAcK8wv7jwD3AAAAAA==.Lilzdrlockz:BAAANQADCgQIBAAAAA==.Lilzriotz:BAAANQAECgUICgAAAA==.',
Lo='Lockoclock:BAAANQAECgMIAwAAAA==.Locomotion:BAAANQADCggICAAAAA==.Lovecraft:BAAANQADCgQIBwAAAA==.Lowlife:BAAANQABCgQIBAABNQAFFAEIAQAGAAAAAA==.',
Lu='Lucyvar:BAABNQAECn8mAAIbAAkKKAboSQDqAAAbAAkKKAboSQDqAAAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECn8/AAMOAAoK1xpFSABBAgAOAAoK1xpFSABBAgANAAoKwhJ9FQC/AQAAAA==.Marlow:BAABNQAECn8rAAIFAAoK6hGqRQDyAQAFAAoK6hGqRQDyAQAAAA==.Marotal:BAABNQAECn8lAAIBAAkKFRL8ugAOAgABAAkKFRL8ugAOAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgcIEQAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Mears:BAAANQAECgMIAwAAAA==.Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAABNQAECn8sAAISAAgK2hRDWwD7AQASAAgK2hRDWwD7AQAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.Meridae:BAAANQAECgYIBgAAAA==.',
Mh='Mhael:BAAANQAECgQICgAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minsofar:BAAANQAECgUICgAAAA==.Mistilinn:BAABNQAECn82AAIgAAoKlQOpKQAIAQAgAAoKlQOpKQAIAQAAAA==.Miyri:BAAANQAECgEIAQABNQAFFAUKCQAXAIAUAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8WAAILAAcKEh5hBQBPAgALAAcKEh5hBQBPAgA1AAQKf9sAAgsACgr3JhsAAKEDAAsACgr3JhsAAKEDAAAA.Morpheus:BAAANQAECgQICwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8tAAMUAAgKERaEHgD3AAABAAgKERYRywDvAQAUAAUKMBiEHgD3AAAAAA==.',
My='Myeyes:BAAANQAECgUIBAAAAA==.Mylinkah:BAABNQAECn8bAAQhAAgKohABKABBAQAhAAgKohABKABBAQAXAAEKpAGhVQAeAAAiAAIKQgDZKgAQAAAAAA==.Mynamefizz:BAEANQAECgQIBgABNQAECgQIBQAGAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgABNQADCggICAAGAAAAAA==.',
['Mé']='Méasha:BAAANQAECgIIAgAAAA==.',
Ni='Nicola:BAABNQAECn8fAAMJAAoKqhkMRgAKAgAJAAoKqhkMRgAKAgAdAAEKAAB+hgAjAAAAAA==.Nightxwish:BAABNQAECn8fAAQjAAYKRx0UEQAXAQAJAAYKZByGWADEAQAjAAQK5BcUEQAXAQAdAAEKDAfRfgAtAAAAAA==.Nik:BAAANQAECgYICAAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Nohlife:BAAANQABCgIIAgAAAA==.Noisemarine:BAAANQAECggICAAAAA==.Norellia:BAAANQAECgcIEwAAAA==.Northspirit:BAABNQAECn8WAAIPAAcKJgYrjQDaAAAPAAcKJgYrjQDaAAAAAA==.',
Nu='Nuit:BAAANQAECgMIAgAAAA==.',
Ny='Nyarlothep:BAABNQAECn8dAAIcAAcKrBDeDwAyAQAcAAcKrBDeDwAyAQAAAA==.Nymh:BAABNQAECn8aAAQFAAgKsgpzkQAjAQAFAAgKZglzkQAjAQAkAAIKLwkYLQAvAAAEAAEK4w8AAAAAAAAAAA==.Nyx:BAAANQADCgIIAgABNQAECggILwAOAKEUAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYICAABNQAECgoKJQACABYdAA==.Odins:BAABNQAECn8lAAMCAAoKFh3pBgAUAwACAAoKCB3pBgAUAwAPAAgKixvGQwBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgMIBAABNQADCggIEwAGAAAAAA==.Ohyikers:BAACNQAFFH8cAAILAAcKYCVxBAAHAgALAAcKYCVxBAAHAgA1AAQKf2wABAsACgo2JvYAAPUDAAsACgo2JvYAAPUDAAMAAgrEHi8+ALQAABAAAQp8Gr06AE8AAAAA.',
Ok='Oken:BAABNQAECn8fAAILAAYK4AcWXACfAAALAAYK4AcWXACfAAAAAA==.',
Op='Oppenheimer:BAAANQADCgEIAQAAAA==.Opportunity:BAAANQADCgcIBwABNQAECgoKeQAMABcmAA==.',
Ot='Otso:BAABNQAECn8jAAIDAAcKiB4VEQBPAgADAAcKiB4VEQBPAgABNQAECgkJIQAZAK8WAA==.',
Pa='Paapi:BAAANQAECgYICQAAAA==.Paco:BAAANQADCgYIBgAAAA==.Paladime:BAABNQAECn8YAAIOAAcKPg3F0AB6AQAOAAcKPg3F0AB6AQAAAA==.Pallek:BAAANQAECggIEQABNQAECgoKVwASAEQjAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgQIBwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.Pewpewbite:BAAANQAECgEIAQAAAA==.',
Ph='Phantomarrow:BAAANQAECgIIAQAAAA==.Phantomcat:BAAANQAECgUIBgAAAA==.Phantomlock:BAACNQAFFH8HAAMFAAQKCQPtHQCtAAAFAAQKCQPtHQCtAAAEAAEK0gFCFQA5AAA1AAQKfyMAAwUACgohFmRYAE0CAAUACgrzFWRYAE0CAAQABAoODiU9AM0AAAAA.Pharasan:BAABNQAECn8XAAIPAAgKDQu8ngBZAQAPAAgKDQu8ngBZAQAAAA==.Phatcow:BAABNQAECn8/AAIKAAoKaCGPCACCAwAKAAoKaCGPCACCAwAAAA==.Phude:BAABNQAECn9cAAIOAAoKkxlQSgA7AgAOAAoKkxlQSgA7AgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Ps='Psylock:BAAANQAECgUIDwAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAABNQAECn8XAAIFAAkKhQtJVwC6AQAFAAkKhQtJVwC6AQAAAA==.',
Py='Pyramys:BAABNQAECn8iAAMlAAoKexl9DgCQAgAlAAoKexl9DgCQAgAmAAUKIhz7UAB6AQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.Quepaoka:BAAANQABCgMIAwAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQAECgQIBAAAAA==.Rawcky:BAAANQAECggIBwAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgIIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAAGAAAAAA==.Rivër:BAAANQAECgYIBQAAAA==.',
Ro='Rolls:BAAANQAECgUICAAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAAUAOAOAA==.Rootoo:BAAANQADCgUIBgAAAA==.Roozer:BAAANQADCggIHwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAQABNQAECgkJJQAYABsVAA==.Sad:BAABNQAECn8nAAIBAAoK/hlqTAAbAgABAAoK/hlqTAAbAgAAAA==.Saelina:BAAANQAECgYIBwABNQAFFAUKCQAXAIAUAA==.Saelyria:BAABNQAECn8VAAIIAAkKChTFJACwAQAIAAkKChTFJACwAQABNQAFFAUKCQAXAIAUAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAABNQAECn8lAAIMAAoKpwgNqgC4AAAMAAoKpwgNqgC4AAAAAA==.Sainthymn:BAAANQAECggIEQABNQAECgoKJQAMAKcIAA==.Sainttide:BAABNQAECn8gAAMPAAoKVQez2QDhAAAPAAkKjwOz2QDhAAAKAAEKnB3S2QBVAAABNQAECgoKJQAMAKcIAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAABNQAECn80AAIBAAoKJAw9dgCuAQABAAoKJAw9dgCuAQAAAA==.Savallyne:BAAANQAECgEIAgABNQAFFAUKCQAXAIAUAA==.Sayberix:BAAANQAFFAIIAgABNQAECgcIDAAGAAAAAA==.',
Sc='Scoreboard:BAACNQAFFH8dAAMnAAkKXiENAAA3AgAnAAkKXiENAAA3AgAlAAEKAAAxKAAAAAA1AAQKfzoABCcACgr0JuYAAJwDACcACQoIJ+YAAJwDACUAAwoEJ/ZiAGQBACYAAwrGGwE8AJYAAAAA.Scupper:BAABNQAECn8/AAInAAoK+hqOAQBoAgAnAAoK+hqOAQBoAgAAAA==.',
Se='Sedric:BAAANQAECgEIAQAAAA==.Selline:BAAANQAECgQICgAAAA==.Selsonblue:BAAANQADCggIEwAAAA==.Sesskaa:BAABNQAECn8vAAMKAAkKQx74GADbAgAKAAkKQx74GADbAgACAAcKOQN5JADVAAAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgYIDwAAAA==.Shathos:BAAANQADCgUIAQAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgAGAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAABNQAECn8YAAIHAAoKvBwhQgD0AQAHAAoKvBwhQgD0AQAAAA==.',
Sk='Skaro:BAABNQAECn8mAAIXAAoKRhWaCwBnAgAXAAoKRhWaCwBnAgAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgoKJgAXAEYVAA==.Skarosham:BAAANQAECgQIBAABNQAECgoKJgAXAEYVAA==.Sketch:BAABNQAECn8iAAImAAkKIQwrOQDwAQAmAAkKIQwrOQDwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8LAAINAAQKEhJTBgDDAAANAAQKEhJTBgDDAAA1AAQKfzoAAg0ACgq4IZYJAAQDAA0ACgq4IZYJAAQDAAAA.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Sobekk:BAAANQAECggIEQAAAA==.Solomun:BAABNQAECn9CAAIMAAoKOBu0IwDcAgAMAAoKOBu0IwDcAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.',
Sp='Spinky:BAAANQAECggIDQAAAA==.Sploosh:BAAANQAECgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIJQAAAA==.Stinko:BAABNQAECn8VAAMEAAcKRgauFACqAAAEAAcKRgauFACqAAAFAAUKVwH2MQFXAAAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAABNQAECn8WAAIFAAcKyhDFlwCrAQAFAAcKyhDFlwCrAQAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAABNQAECn8jAAMIAAcKvREtNwAlAQAIAAYKng8tNwAlAQALAAEKqAcJhgAxAAAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQAGAAAAAA==.',
Su='Surloyn:BAAANQAECgUIBQABNQAECgoKOwAHAMwcAA==.',
Sw='Swampert:BAACNQAFFH8HAAIaAAQKLBIvIwDlAAAaAAQKLBIvIwDlAAA1AAQKfy0AAhoACQrfHSYxAPsCABoACQrfHSYxAPsCAAAA.Swamperting:BAAANQAECgMIBAABNQAFFAQIBwAaACwSAA==.Swayaos:BAABNQAECn8lAAIFAAoKwBAWdgAAAgAFAAoKwBAWdgAAAgABNQAFFAQICgAdAL0GAA==.Swaye:BAACNQAFFH8KAAIdAAQKvQbDCwDDAAAdAAQKvQbDCwDDAAA1AAQKfzkAAh0ACgrSFaQjABUCAB0ACgrSFaQjABUCAAAA.Swifte:BAAANQAECgQIBgAAAA==.Swimchick:BAABNQAECn8YAAISAAYK1AqO2QDjAAASAAYK1AqO2QDjAAAAAA==.Swizzle:BAABNQAECn8ZAAMiAAcKOxOOFgB6AQAiAAcKOxOOFgB6AQAhAAUKNRB+QgAEAQABNQAECgoKOwAHAMwcAA==.',
Sy='Syfa:BAABNQAECn8bAAMWAAgKFQ+sVQAnAQAWAAgKFQ+sVQAnAQAHAAMKugPrpwAlAAAAAA==.Syllena:BAACNQAFFH8JAAIXAAUKgBTaAwCCAQAXAAUKgBTaAwCCAQA1AAQKfzwAAxcACgp2JLUFAEMDABcACgp2JLUFAEMDACEABAr0EqZKANEAAAE1AAUUBQoJABcAgBQA.Syndicalism:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.Syraelia:BAAANQAECgEIAQABNQAFFAUKCQAXAIAUAA==.Sythia:BAAANQADCgEIAQABNQAFFAQICAAYAEkNAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIKgAAAA==.',
Ta='Tacomistress:BAAANQADCgUIBQAAAA==.Tagmoo:BAABNQAECn9IAAIaAAoKPSUvBQBiAwAaAAoKPSUvBQBiAwAAAA==.Talashea:BAAANQAECgMIAwAAAA==.Talion:BAAANQADCgEIAQABNQAECgoKMAADAPYTAA==.Taloon:BAABNQAECn8ZAAIbAAcKpRSsRwCLAQAbAAcKpRSsRwCLAQAAAA==.Taltost:BAABNQAECn8lAAISAAgKSRA/kwBzAQASAAgKSRA/kwBzAQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAABNQAECn8ZAAIOAAgKxAyi8AA7AQAOAAgKxAyi8AA7AQAAAA==.Tarvält:BAAANQAECgQIBgAAAA==.',
Te='Teksuo:BAABNQAECn9TAAIhAAoK/BOUFwDjAQAhAAoK/BOUFwDjAQAAAA==.Telamontgrim:BAAANQAECgUIAwAAAA==.Tenithon:BAABNQAECn95AAIMAAoKFyalAQDXAwAMAAoKFyalAQDXAwAAAA==.Tenscales:BAABNQAECn8qAAITAAkK+xWiCwBYAgATAAkK+xWiCwBYAgAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBAAAAA==.Tholaren:BAABNQAECn8lAAISAAcK2xDVjACBAQASAAcK2xDVjACBAQAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAABNQAECn8WAAIUAAkK0gzbFwA7AQAUAAkK0gzbFwA7AQAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Totemfreak:BAAANQADCgUICQAAAA==.Touchit:BAAANQAECgMICAAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAABNQAECn8fAAISAAYKyQwt3gDZAAASAAYKyQwt3gDZAAAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAABNQAECn8VAAMSAAcKkxQapgBLAQASAAcKkxQapgBLAQAgAAUK1Qd6WwC3AAAAAA==.Trillion:BAAANQAECgQICQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAAANQAECgYIDgAAAA==.',
Ud='Udari:BAABNQAECn8pAAIOAAkKghYWYwD6AQAOAAkKghYWYwD6AQAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQAECgYIBgAAAA==.',
Va='Varithal:BAABNQAECn9LAAITAAoKtRuBBQARAwATAAoKtRuBBQARAwABNQABCgEIAQAGAAAAAA==.Vastectomy:BAAANQAECgUIDAAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAABNQAECn8pAAISAAgKvAm6oABWAQASAAgKvAm6oABWAQAAAA==.',
Vi='Vicious:BAACNQAFFH8IAAIKAAMK6Bn9GgDCAAAKAAMK6Bn9GgDCAAA1AAQKfy4AAgoACQolHrAlAM4CAAoACQolHrAlAM4CAAAA.Violetsorren:BAAANQADCggICAAAAA==.Vixin:BAABNQAECn8bAAMKAAcKExAcdABAAQAKAAcKExAcdABAAQAPAAUKDwjT4wDPAAAAAA==.',
Vo='Voidsaack:BAABNQAECn8rAAMEAAkKHgesPwDDAAAFAAcK+wXPuQDKAAAEAAYKhgWsPwDDAAAAAA==.Vortan:BAABNQAECn80AAIoAAgKZR2CAwDTAgAoAAgKZR2CAwDTAgAAAA==.',
Vr='Vreya:BAAANQADCgUIDgABNQADCggIFwAGAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynnd:BAAANQAECgYIBgAAAA==.Vynthus:BAABNQAECn8YAAIZAAkK2wsqJABlAQAZAAkK2wsqJABlAQAAAA==.',
Wa='Warhundin:BAEANQAECggIBgABNQAECgkJHAASALgNAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAABNQAECn8UAAQWAAYK1guVXgAsAQAWAAYK1guVXgAsAQAHAAEKAADpxwA5AAAVAAEKywY46wAqAAAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAABNQAECn8qAAIDAAgKbguUMQD1AAADAAgKbguUMQD1AAAAAA==.Whispp:BAAANQAECgUIBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQAGAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.Wisk:BAAANQAECgMIAwAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgAGAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgAGAAAAAA==.',
Xu='Xuny:BAABNQAECn8UAAISAAYKxQ00pQBNAQASAAYKxQ00pQBNAQAAAA==.',
Ya='Yahzway:BAAANQAECgEIAQAAAA==.',
Yo='Yordi:BAABNQAECn8YAAISAAUKvwSWBgH5AAASAAUKvwSWBgH5AAAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuria:BAABNQAECn8XAAIbAAYK8QssUADOAAAbAAYK8QssUADOAAAAAA==.Yuzuriha:BAABNQAECn9OAAISAAoKrSMfCgA0AwASAAoKrSMfCgA0AwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8yAAIbAAoKjBMkKgBQAgAbAAoKjBMkKgBQAgABNQAECgkJHAASALgNAA==.',
Zi='Zipy:BAABNQAECn8pAAIJAAcKQg8YfABNAQAJAAcKQg8YfABNAQAAAA==.',
Zo='Zorathar:BAAANQADCgIIAwAAAA==.Zorma:BAAANQAECgUIBQAAAA==.',
Zy='Zyllo:BAAANQADCggIGQAAAA==.',
['Zæ']='Zæ:BAAANQAECgQIBAAAAA==.',
['Äe']='Äemond:BAAANQADCgIIAgAAAA==.',
['Ål']='Ålïce:BAABNQAECn9HAAIOAAoKtxsLOwBsAgAOAAoKtxsLOwBsAgAAAA==.',
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
