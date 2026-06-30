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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warrior-Fury','Priest-Shadow','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Paladin-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abomination:BAABLgAECn8wAAIBAAkJrwRyLgDrAAABAAkJrwRyLgDrAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8iAAMEAAgJTAuumQBGAQAEAAgJTAuumQBGAQAFAAIJCwHQDgA+AAAAAA==.Adylina:BAAALgADCgMJAwABLgAECggJIgAEAEwLAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgUJBgABLgAECgYJBgAGAAAAAA==.Aldaran:BAAALgAECgYJBgAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJEAAIAC0RAA==.',
As='Ashfallen:BAABLgAECn8YAAIHAAYJ9ASFzwCTAAAHAAYJ9ASFzwCTAAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIJAAMJkhczNADgAAAJAAMJkhczNADgAAAuAAQKfywAAgkACQkBIKkLAK0CAAkACQkBIKkLAK0CAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQw1NABIAQAKAAgJOQw1NABIAQAAAA==.Auryx:BAAALgAECgcJEwAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAMJBAAGAAAAAA==.',
Az='Azrel:BAABLgAECn8XAAMLAAkJtAzaIgA5AQALAAkJBAzaIgA5AQAMAAYJJwRMMgCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8fAAQNAAcJSyGPCwBCAgANAAcJSyGPCwBCAgAOAAUJ9BzAAwA3AQAPAAEJzwflKwA8AAAuAAQKfyIABA4ACAlFJUgKADoCAA0ABgmPJXYQAHECAA4ABwkBHEgKADoCAA8AAQk0CZRJAC8AAAAA.Balbo:BAAALgAECgkJDAABLgAFFAYJHgAMAFUmAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8eAAIMAAYJVSZqAQD5AQAMAAYJVSZqAQD5AQAuAAQKfzEAAwwACQnwJhQAAAUEAAwACQnwJhQAAAUEAAsABwlbJEIIAGsCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bayleef:BAABLgAECn8vAAIQAAkJXx28DgDgAgAQAAkJXx28DgDgAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Belac:BAAALgAECgIJAgABLgAFFAQJFgAIADMYAA==.Beldr:BAABLgAECn8YAAIRAAkJtA7MKgByAQARAAkJtA7MKgByAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg4zUAAIAQAJAAYJzg4zUAAIAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.Blutonium:BAAALgADCgQJBAAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgADCggJBgAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJCgABLgAECgkJKAASABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABTENQACAgAIAAkJABTENQACAgATAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8OAAIUAAYJnRitCAB9AQAUAAYJnRitCAB9AQAuAAQKfzEAAhQACQmHHfUHAOQCABQACQmHHfUHAOQCAAAA.',
Bu='Bucksmon:BAAALgAECgEJAQAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAgAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECgkJJQALABERAA==.Cheetoh:BAABLgAFFH8LAAMMAAQJMxCLEAC8AAAMAAMJWAyLEAC8AAALAAIJ5hQnKQB3AAABLgAFFAgJIQADAOsVAA==.Chilli:BAAALgAECgYJEQAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8WAAIIAAQJMxiKRgA8AQAIAAQJMxiKRgA8AQAuAAQKfyQAAggACAljGe07AOsBAAgACAljGe07AOsBAAAA.',
Co='Conall:BAACLgAFFH8XAAIVAAUJ1BOmGADOAAAVAAUJ1BOmGADOAAAuAAQKfzUAAhUACQlqHaUqAFcCABUACQlqHaUqAFcCAAAA.Confetti:BAABLgAECn8fAAIQAAcJvSHuFgCPAgAQAAcJvSHuFgCPAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgcJCAAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
Dd='Ddofpain:BAAALgAECgEJAQAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAFFAIJAgAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJBwAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Dermo:BAAALgAECgMJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBwAAAA==.',
Dm='Dmaw:BAABLgAECn8aAAMWAAYJqAjjQgDTAAAWAAYJqAjjQgDTAAADAAYJZgwBTADSAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMWAAkJwA94JACPAQAWAAkJwA94JACPAQADAAcJcxIhOgAZAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAFFAIJAgAAAA==.Dragonsloot:BAACLgAFFH8bAAMNAAcJJBDjIABZAQANAAcJJBDjIABZAQAPAAMJbgEqJQByAAAuAAQKfzkABA0ACQl4HBMQAGgCAA0ACQl4HBMQAGgCAA8ABwleBwUeAAkBAA4AAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8dAAIXAAYJ4gz8GgD4AAAXAAYJ4gz8GgD4AAAAAA==.Drubeastin:BAACLgAFFH8GAAIYAAQJqxCXSQAaAQAYAAQJqxCXSQAaAQAuAAQKfzAAAhgACQkPH50RAMQCABgACQkPH50RAMQCAAAA.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
Dy='Dyspeptic:BAAALgAECggJCAABLgAFFAYJDgAVABcGAA==.',
['Dó']='Dónkey:BAAALgADCgkJGAAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgYJEwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgAECgMJAwAAAA==.Elenoa:BAAALgAECgQJBQAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiPhHQBxAgAIAAcJbiXhHQBxAgAZAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgUJDAAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAQAAAA==.',
Fa='Fappio:BAAALgAECgQJEAABLgAECgkJQAAPACkkAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ9SUACVAQAHAAkJig1SUACVAQAUAAQJyhAxSACVAAAaAAMJIAZ+JwBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8SAAIHAAYJpxobJACfAQAHAAYJpxobJACfAQAuAAQKfyMAAgcACAl1ItcUAJwCAAcACAl1ItcUAJwCAAAA.Forlath:BAAALgAECggJDgAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBgAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Galgor:BAAALgAECgYJEQAAAA==.Gamõn:BAAALgAECgMJBwAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gh='Ghaerult:BAAALgADCgEJAQABLgAECgkJIQAbAMUlAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.Groundbeefed:BAAALgADCgYJBgAAAA==.Grover:BAAALgAECgYJBgAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIVAAcJ0BedhwBhAQAVAAcJ0BedhwBhAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Hanoe:BAAALgADCgcJBwAAAA==.Harami:BAABLgAECn8cAAIVAAgJfg0JlgBIAQAVAAgJfg0JlgBIAQABLgAFFAMJDgAUANIXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBtDJACLAgAEAAkJfBtDJACLAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJEQAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAwAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAZAAQJSw0tUQB6AAATAAEJ0QkYPwA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMcAAcJJhAkQACAAQAcAAcJJhAkQACAAQAdAAMJ8B2NXwDGAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8iAAIVAAkJ8yNXAgDfAgAVAAkJ8yNXAgDfAgAuAAQKfyIAAhUACAl1Ji0FAHoDABUACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8PAAIYAAcJwBr4AgAKAgAYAAcJwBr4AgAKAgAuAAQKfxQAAx4ABgkuHq8wALEBAB4ABgkaHq8wALEBABgAAQluIBC4AFMAAAEuAAUUCQkiABUA8yMA.Hornfu:BAABLgAECn8aAAMDAAYJ7BVGAgAxAQADAAYJ5hVGAgAxAQACAAMJTxWDBwBTAAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJGwAVANIiAA==.Humanwolf:BAAALgAFFAEJAQAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8bAAIIAAUJjSG1DgAeAQAIAAUJjSG1DgAeAQAuAAQKfy0AAggACQn9IRkUAK0CAAgACQn9IRkUAK0CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAgJIQADAOsVAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJGwAVANIiAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ji='Jinkal:BAAALgAECgEJAwAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8RAAIbAAUJow4MHQA1AQAbAAUJow4MHQA1AQAuAAQKfyYAAhsABwl0FucnAMwBABsABwl0FucnAMwBAAEuAAUUBgkUABsAcBEA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAgJFQAeANsZAA==.',
['Jû']='Jûstin:BAAALgAFFAEJAQABLgAFFAYJEQAfAEgQAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8OAAIUAAMJ0hc0FwDpAAAUAAMJ0hc0FwDpAAAuAAQKfyoAAxQACQlSHRgJAJkCABQACQlSHRgJAJkCABoAAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQABLgAECgQJBwAGAAAAAA==.Katrint:BAABLgAECn8jAAMgAAkJ6iPKDQBLAgAgAAkJ6iPKDQBLAgAhAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8fAAMRAAYJ2SR1AgB0AgARAAYJ2SR1AgB0AgAKAAEJPg3CFABRAAAuAAQKfxoAAhEACAmhHkYQAGMCABEACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAcJFQAiALYRAA==.Kiramouse:BAACLgAFFH8mAAQTAAUJDCO6CwDCAAATAAIJxiC6CwDCAAAIAAQJYhzaHAC3AAAZAAIJgyGhEACvAAAuAAQKfxkABAgACQklIcsRAL4CAAgABwnII8sRAL4CABkAAgk3I2ssAGUAABMAAQndDSw5AEIAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAgJIQADAOsVAA==.',
Ky='Kyrié:BAABLgAECn86AAIRAAgJiyRQBQAnAwARAAgJiyRQBQAnAwAAAA==.',
La='Lanzadora:BAABLgAECn8bAAIYAAYJvhpXCgAVAQAYAAYJvhpXCgAVAQAAAA==.Largecaliber:BAAALgAECgEJAQAAAA==.Lasinak:BAABLgAECn8mAAQjAAYJXAZ6SADkAAAjAAYJ5gV6SADkAAAKAAYJWgi+BgCxAAARAAEJQAbYDgAoAAABLgAFFAMJDgAUANIXAA==.',
Le='Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCwAAAA==.Leto:BAAALgAECgcJDQABLgAECgkJJgAWAOIWAA==.',
Li='Liability:BAACLgAFFH8HAAIkAAQJbQJ5DQBXAAAkAAQJbQJ5DQBXAAAuAAQKfzUAAiQACQnKB2kjABUBACQACQnKB2kjABUBAAAA.Linez:BAAALgADCgQJBAAAAA==.Lisanalgaib:BAAALgAECggJEQAAAA==.Lithiel:BAAALgAECggJCAAAAA==.Littlearrow:BAAALgAECgYJBgAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8bAAIYAAUJLx3pLgBSAQAYAAUJLx3pLgBSAQAuAAQKf0EAAhgACQlHI+IJAAkDABgACQlHI+IJAAkDAAAA.',
Ma='Mageskinker:BAAALgADCgUJBQAAAA==.Magital:BAAALgAECgYJCgABLgAFFAcJGwANACQQAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIaAAcJMwbvHQCsAAAaAAcJMwbvHQCsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAVANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgQJBwAAAA==.Meowmeowmeow:BAABLgAECn8cAAIMAAcJkxuaDADtAQAMAAcJkxuaDADtAQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIXAAkJXxnICAD+AQAXAAkJXxnICAD+AQAAAA==.Mikeoxlongg:BAAALgAECggJDAAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAlAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.Morkdaorc:BAAALgAECgYJCgAAAA==.',
Mu='Muzuki:BAAALgAECgUJEAAAAA==.',
My='Myrala:BAAALgADCgcJBgAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAQJCgAVAE4MAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECgkJCgAGAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIQAAkJHSHjBwA5AwAQAAkJHSHjBwA5AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJQAAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgYJCgAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgEJAQAAAA==.Nonsocial:BAABLgAFFH8MAAIMAAUJPxrSBgA+AQAMAAUJPxrSBgA+AQABLgAFFAkJMQAEAF8fAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDQAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJgAWAOIWAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIlAAMJ5hgaAQDkAAAlAAMJ5hgaAQDkAAABLgAFFAYJHgAMAFUmAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgcJDgAAAA==.Pahine:BAABLgAFFH8JAAISAAMJpQ68BQCGAAASAAMJpQ68BQCGAAABLgAFFAMJDgAUANIXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAABLgAFFH8GAAMVAAMJCgiddwDGAAAVAAMJCgiddwDGAAAbAAEJQgBvUgAVAAAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Potaytoes:BAAALgAECgQJBAABLgAECgkJJgAWAOIWAA==.Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn81AAIEAAkJDSGfFADdAgAEAAkJDSGfFADdAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECggJEgAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8bAAIVAAUJ0iJjHQCTAQAVAAUJ0iJjHQCTAQAuAAQKfzYAAhUACQnzJfUEAFADABUACQnzJfUEAFADAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECggJFgAVAMIdAA==.Rabbidlight:BAABLgAECn8WAAMVAAgJwh3VZgCyAQAVAAcJwxzVZgCyAQAbAAYJRg7CYACyAAAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rainquis:BAAALgAECgEJAQAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.',
Re='Rekson:BAABLgAECn8gAAIiAAkJsRXWNAArAgAiAAkJsRXWNAArAgAAAA==.Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8lAAIVAAkJYRuZNgAnAgAVAAkJYRuZNgAnAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAABLgAECn8bAAIfAAYJeBeiAwAZAQAfAAYJeBeiAwAZAQAAAA==.Satoru:BAAALgAECgYJCgAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAkJQQAIAH0bAA==.',
Se='Segen:BAABLgAECn8aAAIEAAgJBBLVbQCfAQAEAAgJBBLVbQCfAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn8jAAIYAAYJQguMEwCdAAAYAAYJQguMEwCdAAAAAA==.Sen:BAABLgAECn8yAAQYAAkJvyONEADMAgAYAAkJgyKNEADMAgAeAAcJ7h6gCQDbAQAnAAIJDxXwTQB6AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8YAAMCAAcJqAfEWACmAAACAAcJJQTEWACmAAADAAQJ/AcwXgCYAAABLgAFFAMJDgAUANIXAA==.Shalanath:BAAALgAECgEJAQAAAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJCQAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Si='Sieben:BAAALgAECgEJAQAAAA==.Silverbackh:BAAALgAECgQJBAAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8hAAIDAAgJ6xVXBQDIAQADAAgJ6xVXBQDIAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGKwkAIcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCggJCwAAAA==.',
Sm='Sm:BAAALgAECgIJAwAAAA==.Smilepally:BAABLgAECn8YAAIVAAcJKBXCBQBkAQAVAAcJKBXCBQBkAQAAAA==.',
Sn='Snipedyou:BAAALgAECgIJAwAAAA==.Snomed:BAACLgAFFH8KAAITAAMJ9B/WAADaAAATAAMJ9B/WAADaAAAuAAQKfxcAAhMACAluImYCAJoCABMACAluImYCAJoCAAEuAAUUBgkeAAwAVSYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8mAAMWAAkJ4hZQGgBFAgAWAAkJ4hZQGgBFAgADAAEJ0gEKwgAUAAAAAA==.',
St='Stache:BAAALgAECgQJBAAAAA==.Stantic:BAACLgAFFH8MAAQYAAYJbAeZDQDvAAAYAAQJjQuZDQDvAAAeAAMJJQFQIwBjAAAnAAEJHAJtNgA7AAAuAAQKfx0AAxgACAmgHzogAEQCABgACAnBGzogAEQCAB4ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDgABLgAFFAQJFgAIADMYAA==.Stevethuzad:BAAALgAECgQJBgABLgAECgUJBwAGAAAAAA==.Stormydaniel:BAACLgAFFH8GAAIcAAIJfQaIdABVAAAcAAIJfQaIdABVAAAuAAQKfx8AAxwACQkfEZUrAAsCABwACQkfEZUrAAsCAB0ABAn6AeyTAEwAAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.Sunzmoo:BAAALgAECgMJAwAAAA==.',
Sw='Swagadin:BAAALgAFFAQJAQAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx0IHwBaAgAHAAkJAx0IHwBaAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thelights:BAAALgADCgMJAwAAAA==.Threeofseven:BAAALgAECgEJAgAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8UAAIBAAQJXSPTDgCSAQABAAQJXSPTDgCSAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDQAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAoAAIJdBOhWgBvAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAFFAIJAgAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undedagaindk:BAACLgAFFH8oAAMiAAgJKh42AgD1AQAiAAgJKh42AgD1AQABAAIJ9B06OABUAAAuAAQKfyUAAyIACQllJicKAEoDACIACQllJicKAEoDAAEAAwl7IM46AKgAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgcJCwAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8hAAMnAAkJsg5JGwDDAQAnAAkJ4gtJGwDDAQAYAAMJTxriowD6AAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8jAAIHAAgJ/gxYcwA7AQAHAAgJ/gxYcwA7AQABLgAECgkJCgAGAAAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn9AAAQmAAkJQhMBFgB1AQAmAAkJahEBFgB1AQAVAAgJjAy9CwGqAAAbAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8ZAAIDAAgJCx8fEQA9AgADAAgJCx8fEQA9AgAAAA==.',
Vu='Vuori:BAAALgAECgEJAQAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIWAAkJ4R+uBwAiAwAWAAkJ4R+uBwAiAwAAAA==.',
['Vì']='Vìi:BAAALgAECgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJHgAMAFUmAA==.',
Wh='Whitelove:BAABLgAECn8xAAMjAAkJexuADAClAgAjAAkJexuADAClAgARAAYJKRYoMQBIAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJDwABLgAECgkJKAASABIYAA==.Whý:BAABLgAECn8YAAIZAAkJzgXPFQD7AAAZAAkJzgXPFQD7AAAAAA==.',
Wi='Wikm:BAAALgAFFAMJBAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJGwAVANIiAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn84AAIcAAkJChoeEwCzAgAcAAkJChoeEwCzAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAISAAkJEhi+CQAgAgASAAkJEhi+CQAgAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIiAAgJLRj/QgD5AQAiAAgJLRj/QgD5AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgAECgEJAQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8KAAMcAAMJuBd1SgDGAAAcAAMJuBd1SgDGAAAdAAMJOhcDNAC/AAAuAAQKfxUAAxwACAlBGaM9AIoBABwABQnHG6M9AIoBAB0ABwnrHHlOAPwAAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCgAcALgXAA==.',
Zo='Zoomies:BAAALgAECgYJDgABLgAECgkJQAAPACkkAA==.',
Zu='Zugmeoff:BAAALgAECgEJAQAAAA==.',
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
