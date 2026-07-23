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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warrior-Fury','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Paladin-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abomination:BAABLgAECn8wAAIBAAkJrwRyLgDrAAABAAkJrwRyLgDrAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8kAAMEAAkJYwuumQBGAQAEAAkJYwuumQBGAQAFAAIJCwHQDgA+AAAAAA==.Adylina:BAAALgADCgMJAwABLgAECgkJJAAEAGMLAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgUJBgABLgAECgYJBgAGAAAAAA==.Aldaran:BAAALgAECgYJBgAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.Alyriana:BAAALgAECgcJCAAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJFAAIAC0RAA==.',
As='Ashfallen:BAABLgAECn8YAAIHAAYJ9ASFzwCTAAAHAAYJ9ASFzwCTAAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIJAAMJkhczNADgAAAJAAMJkhczNADgAAAuAAQKfywAAgkACQkBIKkLAK0CAAkACQkBIKkLAK0CAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQw1NABIAQAKAAgJOQw1NABIAQAAAA==.Auryx:BAABLgAECn8aAAILAAcJohdkBwAoAQALAAcJohdkBwAoAQAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAUJCAAMABkhAA==.',
Az='Azrel:BAABLgAECn8XAAMNAAkJtAzaIgA5AQANAAkJBAzaIgA5AQAOAAYJJwRMMgCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8gAAQMAAcJSyGPCwBCAgAMAAcJSyGPCwBCAgAPAAUJ9BzAAwA3AQAQAAEJzwflKwA8AAAuAAQKfyIABA8ACAlFJUgKADoCAAwABgmPJXYQAHECAA8ABwkBHEgKADoCABAAAQk0CZRJAC8AAAAA.Baelfor:BAAALgAECgIJBAAAAA==.Balbo:BAAALgAECgkJDAABLgAFFAcJHwAOAEYmAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8fAAIOAAcJRiZqAQD5AQAOAAcJRiZqAQD5AQAuAAQKfzEAAw4ACQnwJhQAAAUEAA4ACQnwJhQAAAUEAA0ABwlbJEIIAGsCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bayleef:BAABLgAECn8vAAILAAkJXx28DgDgAgALAAkJXx28DgDgAgAAAA==.',
Be='Beardik:BAAALgAECgUJDAAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Beefjerkie:BAAALgADCgcJBwAAAA==.Belac:BAAALgAECgIJAgABLgAFFAQJFgAIADMYAA==.Beldr:BAABLgAECn8YAAIRAAkJtA7MKgByAQARAAkJtA7MKgByAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg4zUAAIAQAJAAYJzg4zUAAIAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.Blutonium:BAAALgADCgQJBAAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgADCggJBgAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJCgABLgAECgkJKAASABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABTENQACAgAIAAkJABTENQACAgATAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8PAAIUAAYJnRitCAB9AQAUAAYJnRitCAB9AQAuAAQKfzEAAhQACQmHHfUHAOQCABQACQmHHfUHAOQCAAAA.',
Bu='Bucksmon:BAAALgAECgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAgAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECgkJJQANABMRAA==.Cheetoh:BAABLgAFFH8LAAMOAAQJMxCLEAC8AAAOAAMJWAyLEAC8AAANAAIJ5hQnKQB3AAABLgAFFAgJIQADAOsVAA==.Chilli:BAABLgAECn8gAAIEAAcJURuTBgDnAQAEAAcJURuTBgDnAQAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8WAAIIAAQJMxiKRgA8AQAIAAQJMxiKRgA8AQAuAAQKfyQAAggACAljGe07AOsBAAgACAljGe07AOsBAAAA.',
Co='Conall:BAACLgAFFH8XAAIVAAUJ1BN/SgAYAQAVAAUJ1BN/SgAYAQAuAAQKfzUAAhUACQlqHaUqAFcCABUACQlqHaUqAFcCAAAA.Confetti:BAABLgAECn8fAAILAAcJvSHuFgCPAgALAAcJvSHuFgCPAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECggJCQAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
Dd='Ddofpain:BAAALgAECgEJAQAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAFFAIJAgAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJCgAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Demure:BAAALgAECgEJAgAAAA==.Dermo:BAAALgAECgQJBAAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBwAAAA==.',
Dm='Dmaw:BAACLgAFFH8LAAIWAAUJJwl/GQDgAAAWAAUJJwl/GQDgAAAuAAQKfxoAAxYABgmoCONCANMAABYABgmoCONCANMAAAMABglmDAFMANIAAAAA.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMWAAkJwA94JACPAQAWAAkJwA94JACPAQADAAcJcxIhOgAZAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAFFAIJAgAAAA==.Dragonsloot:BAACLgAFFH8cAAMMAAgJTA7jIABZAQAMAAgJTA7jIABZAQAQAAMJbgEqJQByAAAuAAQKfzkABAwACQl4HBMQAGgCAAwACQl4HBMQAGgCABAABwleBwUeAAkBAA8AAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8gAAIXAAYJiQ38GgD4AAAXAAYJiQ38GgD4AAAAAA==.Drubeastin:BAACLgAFFH8GAAIYAAQJqxCXSQAaAQAYAAQJqxCXSQAaAQAuAAQKfzAAAhgACQkPH50RAMQCABgACQkPH50RAMQCAAAA.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
Dy='Dyspeptic:BAAALgAFFAIJAgABLgAFFAcJFAAVANMOAA==.',
['Dó']='Dónkey:BAAALgAECgQJBQAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgYJEwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgAECgMJAwAAAA==.Elenoa:BAAALgAECgQJBQAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiPhHQBxAgAIAAcJbiXhHQBxAgAZAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgUJDAAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAQAAAA==.',
Fa='Fappio:BAAALgAECgQJEAABLgAECgkJQAAQACkkAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ9SUACVAQAHAAkJig1SUACVAQAUAAQJyhAxSACVAAAaAAMJIAZ+JwBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8UAAIHAAgJfBwbJACfAQAHAAgJfBwbJACfAQAuAAQKfyMAAgcACAl1ItcUAJwCAAcACAl1ItcUAJwCAAAA.Forlath:BAAALgAECggJDgAAAA==.',
Fr='Freaktotem:BAAALgADCgkJCQAAAA==.Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBgAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Galgor:BAABLgAECn8XAAIbAAYJCRXJDAA4AQAbAAYJCRXJDAA4AQAAAA==.Gamõn:BAAALgAECgMJBwAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gh='Ghaerult:BAAALgADCgEJAQABLgAFFAEJAwAGAAAAAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.Groundbeefed:BAAALgADCgYJBgAAAA==.Grover:BAAALgAECgYJBgAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIVAAcJ0BedhwBhAQAVAAcJ0BedhwBhAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Hanoe:BAAALgADCgcJBwAAAA==.Harami:BAABLgAECn8cAAIVAAgJfg0JlgBIAQAVAAgJfg0JlgBIAQABLgAFFAMJDgAUANIXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBtDJACLAgAEAAkJfBtDJACLAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJEQAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAwAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAZAAQJSw0tUQB6AAATAAEJ0QkYPwA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMcAAcJJhAkQACAAQAcAAcJJhAkQACAAQAdAAMJ8B2NXwDGAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8lAAIVAAkJ8yNXAgDfAgAVAAkJ8yNXAgDfAgAuAAQKfyUAAhUACAl1Ji0FAHoDABUACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8QAAIYAAgJVRzzBABQAgAYAAgJVRzzBABQAgAuAAQKfxQAAx4ABgkuHq8wALEBAB4ABgkaHq8wALEBABgAAQluIBC4AFMAAAEuAAUUCQklABUA8yMA.Hornfu:BAABLgAECn8fAAMDAAcJ0hWiAwBuAQADAAcJzBWiAwBuAQACAAMJTxU8DQBQAAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJGwAVANIiAA==.Humanwolf:BAABLgAECn8WAAMXAAcJsRClBQDSAAAbAAcJvQnBqgAcAQAXAAQJwBKlBQDSAAAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8jAAIIAAUJjSELNwBtAQAIAAUJjSELNwBtAQAuAAQKfy0AAggACQn9IRkUAK0CAAgACQn9IRkUAK0CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAgJIQADAOsVAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJGwAVANIiAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ji='Jinkal:BAAALgAECgEJBAAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8RAAIfAAUJow4MHQA1AQAfAAUJow4MHQA1AQAuAAQKfyYAAh8ABwl0FucnAMwBAB8ABwl0FucnAMwBAAEuAAUUBgkVAB8AcBEA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAgJFQAeANsZAA==.',
['Jû']='Jûstin:BAABLgAECn8YAAIHAAkJnCR6AABZAwAHAAkJnCR6AABZAwABLgAFFAgJEwAgAA0RAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8OAAIUAAMJ0hc0FwDpAAAUAAMJ0hc0FwDpAAAuAAQKfyoAAxQACQlSHRgJAJkCABQACQlSHRgJAJkCABoAAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQABLgAECgUJCAAGAAAAAA==.Katrint:BAABLgAECn8jAAMhAAkJ6iPKDQBLAgAhAAkJ6iPKDQBLAgAiAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8gAAMRAAcJUyN1AgB0AgARAAcJUyN1AgB0AgAKAAEJPg3CFABRAAAuAAQKfxoAAhEACAmhHkYQAGMCABEACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAcJFQAbALYRAA==.Kiramouse:BAACLgAFFH8mAAQTAAUJDCO6CwDCAAAIAAQJYhxfIgD7AAATAAIJxiC6CwDCAAAZAAIJgyGhEACvAAAuAAQKfxkABAgACQklIcsRAL4CAAgABwnII8sRAL4CABkAAgk3I2ssAGUAABMAAQndDSw5AEIAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAgJIQADAOsVAA==.',
Ku='Kuti:BAAALgAECgMJAwABLgAFFAMJDgAUANIXAA==.',
Ky='Kyrié:BAABLgAECn89AAIRAAkJ4iBQBQAnAwARAAkJ4iBQBQAnAwAAAA==.',
La='Lanzadora:BAABLgAECn8bAAIYAAYJvhqwFgAAAQAYAAYJvhqwFgAAAQAAAA==.Largecaliber:BAAALgAECgEJAQAAAA==.Lasinak:BAABLgAECn8tAAQKAAYJGRLOBwAfAQAKAAYJGRLOBwAfAQAjAAYJ5gV6SADkAAARAAEJQAYFGwAeAAABLgAFFAMJDgAUANIXAA==.',
Le='Leafsitter:BAAALgAECgEJAQAAAA==.Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCwAAAA==.Leto:BAABLgAECn8VAAIEAAkJJA5dDwA9AQAEAAkJJA5dDwA9AQABLgAECgkJJgAWAOIWAA==.',
Li='Liability:BAACLgAFFH8MAAIkAAcJqwNTCQALAQAkAAcJqwNTCQALAQAuAAQKfzcAAiQACQlsCmkjABUBACQACQlsCmkjABUBAAAA.Linez:BAAALgADCgQJBAAAAA==.Lisanalgaib:BAABLgAECn8cAAQaAAkJNAriAgAbAQAaAAkJEwniAgAbAQAUAAIJjQ4gEwBaAAAHAAMJVAPmLAA8AAAAAA==.Lithiel:BAAALgAECggJCAAAAA==.Littlearrow:BAAALgAECgYJCgAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8bAAIYAAUJLx3pLgBSAQAYAAUJLx3pLgBSAQAuAAQKf0EAAhgACQlHI+IJAAkDABgACQlHI+IJAAkDAAAA.',
Ma='Mageskinker:BAAALgADCgUJBQAAAA==.Magital:BAAALgAECgYJCwABLgAFFAgJHAAMAEwOAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIaAAcJMwbvHQCsAAAaAAcJMwbvHQCsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAVANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgUJCAAAAA==.Meowmeowmeow:BAABLgAECn8cAAIOAAcJkxuaDADtAQAOAAcJkxuaDADtAQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIXAAkJXxnICAD+AQAXAAkJXxnICAD+AQAAAA==.Mikeoxlongg:BAAALgAECggJDAABLgAECggJIAAVAMwVAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAlAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.Morkdaorc:BAAALgAECgYJCgAAAA==.',
Mu='Muzuki:BAAALgAECgYJEwAAAA==.',
My='Myrala:BAAALgADCgcJBgAAAA==.Mystis:BAAALgADCgYJBgAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAQJDQAVAE4MAA==.',
Na='Naianasha:BAABLgAECn8WAAQMAAkJ6g+FAgCvAQAMAAkJ6g+FAgCvAQAQAAMJogPdOgA4AAAPAAEJngBgCQADAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAILAAkJHSHjBwA5AwALAAkJHSHjBwA5AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJQAAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgYJCwAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgIJAQAAAA==.Nonsocial:BAABLgAFFH8SAAMNAAUJZSJlAwCMAQANAAUJZSJlAwCMAQAOAAUJPxrSBgA+AQABLgAFFAkJPQAEAOggAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDQAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJgAWAOIWAA==.',
Nu='Nun:BAAALgAECgYJBwAAAA==.Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIlAAMJ5hgaAQDkAAAlAAMJ5hgaAQDkAAABLgAFFAcJHwAOAEYmAA==.',
Os='Osti:BAABLgAFFH8KAAMnAAQJpxP/BAA/AQAnAAQJphP/BAA/AQAYAAMJlQoMMQDMAAAAAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgcJDgAAAA==.Pahine:BAABLgAFFH8MAAISAAQJtQ8uCADCAAASAAQJtQ8uCADCAAABLgAFFAMJDgAUANIXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAABLgAFFH8NAAMVAAUJ1gmPJwDZAAAVAAUJ1gmPJwDZAAAfAAEJQgBvUgAVAAAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Potaytoes:BAAALgAECgYJCQABLgAECgkJJgAWAOIWAA==.Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn82AAIEAAkJDSGfFADdAgAEAAkJDSGfFADdAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAABLgAFFH8FAAIdAAMJSgEpKwBLAAAdAAMJSgEpKwBLAAAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8bAAIVAAUJ0iJjHQCTAQAVAAUJ0iJjHQCTAQAuAAQKfzYAAhUACQnzJfUEAFADABUACQnzJfUEAFADAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAFFAYJCwAVAHIZAA==.Rabbidlight:BAACLgAFFH8LAAMVAAYJchmEEwA/AQAVAAUJ8xiEEwA/AQAfAAEJsgEeJAA1AAAuAAQKfxYAAxUACAnCHdVmALIBABUABwnDHNVmALIBAB8ABglGDsJgALIAAAAA.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rainquis:BAAALgAECgEJAQAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.',
Re='Rekson:BAABLgAECn8gAAIbAAkJsRXWNAArAgAbAAkJsRXWNAArAgAAAA==.Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8lAAIVAAkJYRuZNgAnAgAVAAkJYRuZNgAnAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJDAAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAABLgAECn8hAAIgAAYJhRvKBQBGAQAgAAYJhRvKBQBGAQAAAA==.Satoru:BAAALgAECgYJDQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAkJVAAIAHkfAA==.',
Se='Segen:BAABLgAECn8aAAIEAAgJBBLVbQCfAQAEAAgJBBLVbQCfAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn8tAAIYAAYJKBGIFwD4AAAYAAYJKBGIFwD4AAAAAA==.Sen:BAABLgAECn8yAAQYAAkJvyONEADMAgAYAAkJgyKNEADMAgAeAAcJ7h6gCQDbAQAnAAIJDxXwTQB6AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJDAAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8YAAMCAAcJqAfEWACmAAACAAcJJQTEWACmAAADAAQJ/AcwXgCYAAABLgAFFAMJDgAUANIXAA==.Shalanath:BAAALgAECgEJAQAAAA==.Shammy:BAAALgAECgEJAwAAAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJDAAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Si='Sieben:BAAALgAECgEJAQAAAA==.Silverbackh:BAAALgAECgQJBAAAAA==.Silverbacksh:BAAALgADCgYJBgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8hAAIDAAgJ6xVXBQDIAQADAAgJ6xVXBQDIAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGKwkAIcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCggJCwAAAA==.',
Sm='Sm:BAAALgAECgIJAwAAAA==.Smilepally:BAABLgAECn8ZAAIVAAcJKBUKDQBbAQAVAAcJKBUKDQBbAQAAAA==.',
Sn='Snipedyou:BAAALgAECgIJAwAAAA==.Snomed:BAACLgAFFH8KAAITAAMJ9B/WAADaAAATAAMJ9B/WAADaAAAuAAQKfxcAAhMACAluImYCAJoCABMACAluImYCAJoCAAEuAAUUBwkfAA4ARiYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8mAAMWAAkJ4hZQGgBFAgAWAAkJ4hZQGgBFAgADAAEJ0gEKwgAUAAAAAA==.',
St='Stache:BAAALgAECgcJDgAAAA==.Stantic:BAACLgAFFH8MAAQYAAYJbAeZDQDvAAAYAAQJjQuZDQDvAAAeAAMJJQFQIwBjAAAnAAEJHAJtNgA7AAAuAAQKfx0AAxgACAmgHzogAEQCABgACAnBGzogAEQCAB4ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDgABLgAFFAQJFgAIADMYAA==.Stevethuzad:BAAALgAECgQJBgABLgAECgUJBwAGAAAAAA==.Stormydaniel:BAACLgAFFH8GAAIcAAIJfQaIdABVAAAcAAIJfQaIdABVAAAuAAQKfyAAAxwACQluEZUrAAsCABwACQluEZUrAAsCAB0ABAn6AeyTAEwAAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.Sunzmoo:BAAALgAECgMJAwAAAA==.',
Sw='Swagadin:BAAALgAFFAQJAwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Sy='Synikal:BAAALgAECgYJBwAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx0IHwBaAgAHAAkJAx0IHwBaAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Tellie:BAAALgADCgUJBQAAAA==.Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thelights:BAAALgADCgMJAwAAAA==.Theprototype:BAAALgAECgYJCgAAAA==.Threeofseven:BAAALgAECgEJAgAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8UAAIBAAQJXSPTDgCSAQABAAQJXSPTDgCSAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDQAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAoAAIJdBOhWgBvAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAFFAIJAgAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undeadlysoul:BAAALgAECgYJCAAAAA==.Undedagaindk:BAACLgAFFH8tAAMbAAkJ2h42AgD1AQAbAAkJ2h42AgD1AQABAAIJ9B06OABUAAAuAAQKfyUAAxsACQllJicKAEoDABsACQllJicKAEoDAAEAAwl7IM46AKgAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgcJDQAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8hAAMnAAkJsg5JGwDDAQAnAAkJ4gtJGwDDAQAYAAMJTxriowD6AAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8jAAIHAAgJ/gxYcwA7AQAHAAgJ/gxYcwA7AQABLgAECgkJFgAMAOoPAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn9AAAQmAAkJQhMBFgB1AQAmAAkJahEBFgB1AQAVAAgJjAy9CwGqAAAfAAEJ7QEnoQAnAAAAAA==.',
Vo='Voidflame:BAAALgAECgcJDAAAAA==.Volteil:BAABLgAECn8ZAAIDAAgJCx8fEQA9AgADAAgJCx8fEQA9AgAAAA==.',
Vu='Vuori:BAAALgAECgEJAQAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIWAAkJ4R+uBwAiAwAWAAkJ4R+uBwAiAwAAAA==.',
['Vì']='Vìi:BAAALgAECgcJBwAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAcJHwAOAEYmAA==.',
Wh='Whitelove:BAABLgAECn8xAAMjAAkJexuADAClAgAjAAkJexuADAClAgARAAYJKRYoMQBIAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJDwABLgAECgkJKAASABIYAA==.Whìtepowder:BAAALgAECgEJAQAAAA==.Whý:BAABLgAECn8YAAIZAAkJzgXPFQD7AAAZAAkJzgXPFQD7AAAAAA==.',
Wi='Wikm:BAABLgAFFH8FAAIHAAMJBwaAdQCaAAAHAAMJBwaAdQCaAAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJGwAVANIiAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn84AAIcAAkJChoeEwCzAgAcAAkJChoeEwCzAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAISAAkJEhi+CQAgAgASAAkJEhi+CQAgAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIbAAgJLRj/QgD5AQAbAAgJLRj/QgD5AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgAECgEJAQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8LAAMcAAMJuBd1SgDGAAAcAAMJuBd1SgDGAAAdAAMJOhcDNAC/AAAuAAQKfxUAAxwACAlBGaM9AIoBABwABQnHG6M9AIoBAB0ABwnrHHlOAPwAAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCwAcALgXAA==.',
Zo='Zoomies:BAAALgAECgYJDgABLgAECgkJQAAQACkkAA==.',
Zu='Zugmeoff:BAAALgAECgIJAgAAAA==.',
['Zé']='Zémzel:BAAALgAECgQJBwAAAA==.',
['ßu']='ßubbleßutt:BAAALgADCgYJBwAAAA==.',
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
