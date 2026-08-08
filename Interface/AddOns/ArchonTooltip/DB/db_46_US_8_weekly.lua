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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','Rogue-Outlaw','Warlock-Demonology','DemonHunter-Devourer','Warrior-Fury','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Evoker-Devastation','Evoker-Preservation','Druid-Balance','DeathKnight-Unholy','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warrior-Protection','Paladin-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abomination:BAABLgAECn8wAAIBAAkJrwRyLgDrAAABAAkJrwRyLgDrAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8kAAMEAAkJYwuumQBGAQAEAAkJYwuumQBGAQAFAAIJCwHQDgA+AAAAAA==.Adylina:BAAALgADCgMJAwABLgAECgkJJAAEAGMLAA==.',
Ae='Aelera:BAAALgAECgQJBAAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgUJBgABLgAECgYJBgAGAAAAAA==.Aldaran:BAAALgAECgYJBgAAAA==.Alfaxan:BAAALgADCgcJBwAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Alindril:BAAALgAFFAEJAgAAAA==.Alyriana:BAAALgAECggJDQAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Aradana:BAAALgAECgIJAgABLgAECgkJHQAHAK8NAA==.Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJFAAIAC0RAA==.Arylise:BAAALgADCgYJBgAAAA==.',
As='Ashfallen:BAABLgAECn8YAAIJAAYJ9ASFzwCTAAAJAAYJ9ASFzwCTAAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIKAAMJkhczNADgAAAKAAMJkhczNADgAAAuAAQKfywAAgoACQkBIKkLAK0CAAoACQkBIKkLAK0CAAAA.',
Au='Audric:BAABLgAECn8gAAILAAgJOQw1NABIAQALAAgJOQw1NABIAQAAAA==.Auryx:BAABLgAECn8aAAIMAAcJoBfZCAApAQAMAAcJoBfZCAApAQAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAUJCAANABkhAA==.',
Az='Azrel:BAABLgAECn8XAAMOAAkJtAzaIgA5AQAOAAkJBAzaIgA5AQAPAAYJJwRMMgCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8gAAQNAAcJSyGPCwBCAgANAAcJSyGPCwBCAgAQAAUJ9BzAAwA3AQARAAEJzwflKwA8AAAuAAQKfyIABBAACAlFJUgKADoCAA0ABgmPJXYQAHECABAABwkBHEgKADoCABEAAQk0CZRJAC8AAAAA.Baelfor:BAAALgAECgIJBAAAAA==.Balbo:BAEALgAECgkJDAABLgAFFAkJIgAPAGQkAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAECLgAFFH8iAAMPAAkJZCSRAABvAgAPAAkJZCSRAABvAgASAAEJUBmyJwBMAAAuAAQKfzEAAw8ACQnwJhQAAAUEAA8ACQnwJhQAAAUEAA4ABwlbJEIIAGsCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAABLgAECn8gAAITAAkJsRXWNAArAgATAAkJsRXWNAArAgAAAA==.Bayleef:BAABLgAECn8vAAIMAAkJXx28DgDgAgAMAAkJXx28DgDgAgAAAA==.',
Be='Beardik:BAAALgAECgUJDAAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Beefjerkie:BAAALgADCgcJBwAAAA==.Belac:BAAALgAECgIJAgABLgAFFAQJFgAIADMYAA==.Beldr:BAABLgAECn8YAAIUAAkJtA7MKgByAQAUAAkJtA7MKgByAQAAAA==.Benito:BAABLgAECn8VAAIKAAYJzg4zUAAIAQAKAAYJzg4zUAAIAQAAAA==.Berryfreeze:BAAALgAECgEJAgAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgYJCwAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.Blutonium:BAAALgADCgQJBAAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgAECgYJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJCgABLgAECgkJKAAVABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABTENQACAgAIAAkJABTENQACAgAWAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8PAAIXAAYJnRitCAB9AQAXAAYJnRitCAB9AQAuAAQKfzEAAhcACQmHHfUHAOQCABcACQmHHfUHAOQCAAAA.',
Bu='Bucksmon:BAAALgAECgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAgAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECgkJJQAOABMRAA==.Cheetoh:BAABLgAFFH8LAAMPAAQJMxCLEAC8AAAPAAMJWAyLEAC8AAAOAAIJ5hQnKQB3AAABLgAFFAgJIQADAOsVAA==.Chilli:BAABLgAECn8gAAIEAAcJURtwCADiAQAEAAcJURtwCADiAQAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.Cinderhella:BAAALgAECgEJAwAAAA==.',
Cl='Cl:BAACLgAFFH8WAAIIAAQJMxiKRgA8AQAIAAQJMxiKRgA8AQAuAAQKfyQAAggACAljGe07AOsBAAgACAljGe07AOsBAAAA.',
Co='Conall:BAACLgAFFH8XAAIYAAUJ1BN/SgAYAQAYAAUJ1BN/SgAYAQAuAAQKfzUAAhgACQlqHaUqAFcCABgACQlqHaUqAFcCAAAA.Confetti:BAABLgAECn8fAAIMAAcJvSHuFgCPAgAMAAcJvSHuFgCPAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECggJCQAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.Darling:BAAALgAECgEJAQAAAA==.',
Dd='Ddofpain:BAAALgAECgEJAQAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAFFAIJAgAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJCwAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Demure:BAAALgAECgEJAgAAAA==.Dermo:BAAALgAECgQJBAAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBwAAAA==.',
Dm='Dmaw:BAACLgAFFH8LAAIZAAUJJwnmHADbAAAZAAUJJwnmHADbAAAuAAQKfxoAAxkABgmoCONCANMAABkABgmoCONCANMAAAMABglmDAFMANIAAAAA.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMZAAkJwA94JACPAQAZAAkJwA94JACPAQADAAcJcxIhOgAZAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAFFAIJAgAAAA==.Dragonsloot:BAACLgAFFH8cAAMNAAgJTA7jIABZAQANAAgJTA7jIABZAQARAAMJbgEqJQByAAAuAAQKfzkABA0ACQl4HBMQAGgCAA0ACQl4HBMQAGgCABEABwleBwUeAAkBABAAAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8iAAIaAAYJ9w78GgD4AAAaAAYJ9w78GgD4AAAAAA==.Drubeastin:BAACLgAFFH8GAAIbAAQJqxCXSQAaAQAbAAQJqxCXSQAaAQAuAAQKfzAAAhsACQkPH50RAMQCABsACQkPH50RAMQCAAAA.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
Dy='Dyspeptic:BAAALgAFFAIJAgABLgAFFAcJFAAYANMOAA==.',
['Dó']='Dónkey:BAAALgAECgQJCQAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
Eh='Ehunter:BAAALgADCgIJAgAAAA==.',
El='Elcaris:BAAALgAECgYJEwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgAECgMJAwAAAA==.Elenoa:BAAALgAECgQJBQAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiPhHQBxAgAIAAcJbiXhHQBxAgAcAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgYJCAAAAA==.Evilemt:BAAALgAECgUJDgAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAgAAAA==.',
Fa='Fappio:BAAALgAECgQJEAABLgAECgkJQAARACkkAA==.Faîth:BAABLgAECn8YAAQJAAkJeQ9SUACVAQAJAAkJig1SUACVAQAXAAQJyhAxSACVAAAdAAMJIAZ+JwBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8UAAIJAAgJfBwbJACfAQAJAAgJfBwbJACfAQAuAAQKfyMAAgkACAl1ItcUAJwCAAkACAl1ItcUAJwCAAAA.Forlath:BAAALgAECggJDgAAAA==.',
Fr='Freaktotem:BAAALgADCgkJCQAAAA==.Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBgAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Galgor:BAABLgAECn8XAAITAAYJCRWMDwA3AQATAAYJCRWMDwA3AQAAAA==.Gamõn:BAAALgAECgMJBwAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gh='Ghaerult:BAAALgADCgEJAQABLgAECgkJIQAeAMUlAA==.',
Gl='Glasyalabola:BAAALgAECgMJAwAAAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.Groundbeefed:BAAALgADCgYJBgAAAA==.Grover:BAAALgAECgYJBgAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIYAAcJ0BedhwBhAQAYAAcJ0BedhwBhAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Hanoe:BAAALgADCgcJBwAAAA==.Harami:BAABLgAECn8cAAIYAAgJfg0JlgBIAQAYAAgJfg0JlgBIAQABLgAFFAMJDgAXANIXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBtDJACLAgAEAAkJfBtDJACLAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJEQAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAwAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAcAAQJSw0tUQB6AAAWAAEJ0QkYPwA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMfAAcJJhAkQACAAQAfAAcJJhAkQACAAQAgAAMJ8B2NXwDGAAAAAA==.',
Ho='Homicidal:BAAALgAECgEJAgAAAA==.Hordeelf:BAACLgAFFH8qAAIYAAkJYiRXAgDfAgAYAAkJYiRXAgDfAgAuAAQKfyUAAhgACAl1Ji0FAHoDABgACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8TAAIbAAgJiRxJBgBXAgAbAAgJiRxJBgBXAgAuAAQKfxQAAyEABgkuHq8wALEBACEABgkaHq8wALEBABsAAQluIBC4AFMAAAEuAAUUCQkqABgAYiQA.Hornfu:BAABLgAECn8fAAMDAAcJ0hWGBABsAQADAAcJzBWGBABsAQACAAMJTxVwDwBNAAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJGwAYANIiAA==.Humanwolf:BAABLgAECn8YAAMaAAcJsRAYBwDXAAATAAcJmgrBqgAcAQAaAAQJwBIYBwDXAAAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8mAAIIAAUJjSELNwBtAQAIAAUJjSELNwBtAQAuAAQKfy0AAggACQn9IRkUAK0CAAgACQn9IRkUAK0CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAgJIQADAOsVAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJGwAYANIiAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ji='Jinkal:BAAALgAECgEJBAAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8RAAIeAAUJow4MHQA1AQAeAAUJow4MHQA1AQAuAAQKfyYAAh4ABwl0FucnAMwBAB4ABwl0FucnAMwBAAEuAAUUBgkYAB4AcBEA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAgJFQAhANsZAA==.',
['Jû']='Jûstin:BAACLgAFFH8KAAIJAAUJghbfHAArAQAJAAUJghbfHAArAQAuAAQKfxwAAgkACQnGJJwAAFQDAAkACQnGJJwAAFQDAAEuAAUUCAkTABIADREA.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8OAAIXAAMJ0hc0FwDpAAAXAAMJ0hc0FwDpAAAuAAQKfyoAAxcACQlSHRgJAJkCABcACQlSHRgJAJkCAB0AAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQABLgAECgUJCAAGAAAAAA==.Katrint:BAABLgAECn8jAAMiAAkJ6iPKDQBLAgAiAAkJ6iPKDQBLAgAjAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8gAAMUAAcJUyN1AgB0AgAUAAcJUyN1AgB0AgALAAEJPg3CFABRAAAuAAQKfxoAAhQACAmhHkYQAGMCABQACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAcJFQATALYRAA==.Kiramouse:BAACLgAFFH8mAAQWAAUJDCO6CwDCAAAIAAQJYhxfIgD7AAAWAAIJxiC6CwDCAAAcAAIJgyGhEACvAAAuAAQKfxkABAgACQklIcsRAL4CAAgABwnII8sRAL4CABwAAgk3I2ssAGUAABYAAQndDSw5AEIAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAgJIQADAOsVAA==.',
Ku='Kuti:BAAALgAECgMJAwABLgAFFAMJDgAXANIXAA==.',
Ky='Kyrié:BAABLgAECn8+AAIUAAkJ4yBQBQAnAwAUAAkJ4yBQBQAnAwAAAA==.',
La='Lanzadora:BAABLgAECn8bAAIbAAYJvhoQHADzAAAbAAYJvhoQHADzAAAAAA==.Largecaliber:BAAALgAECgEJAgAAAA==.Lasinak:BAABLgAECn8tAAQLAAYJGRL+CQAaAQALAAYJGRL+CQAaAQAkAAYJ5gV6SADkAAAUAAEJQAYgIAAeAAABLgAFFAMJDgAXANIXAA==.',
Le='Leafsitter:BAAALgAECgEJAQAAAA==.Legòlas:BAAALgAECgMJAwAAAA==.Leiya:BAAALgAECgQJCwAAAA==.Leto:BAABLgAECn8VAAIEAAkJJA4WEwA6AQAEAAkJJA4WEwA6AQABLgAECgkJJgAZAOIWAA==.',
Li='Liability:BAACLgAFFH8MAAIlAAcJqwMrCwADAQAlAAcJqwMrCwADAQAuAAQKfzcAAiUACQlsCmkjABUBACUACQlsCmkjABUBAAAA.Linez:BAAALgADCgQJBAAAAA==.Lirria:BAAALgAECgUJAgAAAA==.Lisanalgaib:BAABLgAECn8kAAQdAAkJgQ28AgBQAQAdAAkJvAq8AgBQAQAXAAMJlw8ZEACSAAAJAAMJVAMdNQA6AAAAAA==.Lithiel:BAAALgAECggJCAAAAA==.Littlearrow:BAAALgAECgYJCgAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8bAAIbAAUJLx3pLgBSAQAbAAUJLx3pLgBSAQAuAAQKf0EAAhsACQlHI+IJAAkDABsACQlHI+IJAAkDAAAA.',
Ma='Mageskinker:BAAALgADCgUJCQAAAA==.Magital:BAAALgAECgYJCwABLgAFFAgJHAANAEwOAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIdAAcJMwbvHQCsAAAdAAcJMwbvHQCsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAYANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgUJCAAAAA==.Meowmeowmeow:BAABLgAECn8cAAIPAAcJkxuaDADtAQAPAAcJkxuaDADtAQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIaAAkJXxnICAD+AQAaAAkJXxnICAD+AQAAAA==.Mikeoxlongg:BAAALgAECggJDAABLgAECggJIAAYAMwVAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAHAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.Morkdaorc:BAAALgAECgYJCgAAAA==.',
Mu='Muzuki:BAAALgAECgYJEwAAAA==.',
My='Myrala:BAAALgADCgcJBgAAAA==.Mystis:BAAALgADCgcJCAAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAQJDQAYAE4MAA==.',
Na='Nabi:BAAALgAECgIJAgABLgAFFAQJBQAZAOMIAA==.Naianasha:BAABLgAECn8WAAQNAAkJ6g9IAwCdAQANAAkJ6g9IAwCdAQARAAMJogPdOgA4AAAQAAEJngCaCwADAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIMAAkJHSHjBwA5AwAMAAkJHSHjBwA5AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJQAAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgYJCwAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgIJAQAAAA==.Nonsocial:BAABLgAFFH8XAAMOAAYJ1CC3AgDWAQAOAAYJ1CC3AgDWAQAPAAUJPxrSBgA+AQABLgAFFAkJSgAEAOggAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDQAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJgAZAOIWAA==.',
Nu='Nun:BAAALgAECgYJEAAAAA==.Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAEBLgAFFH8HAAIHAAMJ5hgaAQDkAAAHAAMJ5hgaAQDkAAABLgAFFAkJIgAPAGQkAA==.',
Os='Osti:BAABLgAFFH8RAAMnAAQJYRjGBABbAQAnAAQJYRjGBABbAQAbAAMJlQolOADFAAAAAA==.',
Pa='Padme:BAAALgAECgcJDgAAAA==.Pahine:BAABLgAFFH8MAAIVAAQJtQ/kCQC6AAAVAAQJtQ/kCQC6AAABLgAFFAMJDgAXANIXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAABLgAFFH8NAAMYAAUJ1gmCLQDWAAAYAAUJ1gmCLQDWAAAeAAEJQgBvUgAVAAAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Potaytoes:BAAALgAECgYJCQABLgAECgkJJgAZAOIWAA==.Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn87AAIEAAkJYyKfFADdAgAEAAkJYyKfFADdAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAABLgAFFH8FAAIgAAMJSgG5MQBGAAAgAAMJSgG5MQBGAAAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8bAAIYAAUJ0iJjHQCTAQAYAAUJ0iJjHQCTAQAuAAQKfzYAAhgACQnzJfUEAFADABgACQnzJfUEAFADAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAFFAcJDAAYAIAYAA==.Rabbidlight:BAACLgAFFH8MAAMYAAcJgBgAEAB/AQAYAAYJ6hcAEAB/AQAeAAEJsgHjJgAxAAAuAAQKfxYAAxgACAnCHdVmALIBABgABwnDHNVmALIBAB4ABglGDsJgALIAAAAA.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rainquis:BAAALgAECgEJAQAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.Raveroller:BAAALgAECgUJCAAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.Rivallanna:BAAALgADCgkJEgAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8lAAIYAAkJYRuZNgAnAgAYAAkJYRuZNgAnAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sadist:BAAALgAECgEJAQAAAA==.Sageoffane:BAAALgADCgcJBwABLgAECgUJDAAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAABLgAECn8hAAISAAYJhRvMBwBCAQASAAYJhRvMBwBCAQAAAA==.Satoru:BAAALgAECgYJDQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAkJZgAcABUiAA==.',
Se='Segen:BAABLgAECn8aAAIEAAgJBBLVbQCfAQAEAAgJBBLVbQCfAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn82AAIbAAgJDhMADACiAQAbAAgJDhMADACiAQAAAA==.Sen:BAABLgAECn8zAAQbAAkJvyONEADMAgAbAAkJgyKNEADMAgAhAAcJ7h6gCQDbAQAnAAIJDxXwTQB6AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJDAAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8YAAMCAAcJqAfEWACmAAACAAcJJQTEWACmAAADAAQJ/AcwXgCYAAABLgAFFAMJDgAXANIXAA==.Shalanath:BAAALgAECgEJAQAAAA==.Shammy:BAAALgAECgEJAwAAAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJDQAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Si='Sieben:BAAALgAECgEJAQAAAA==.Silverbackh:BAAALgAECgQJBAAAAA==.Silverbacksh:BAAALgADCgYJBgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8hAAIDAAgJ6xVXBQDIAQADAAgJ6xVXBQDIAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGKwkAIcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCggJCwAAAA==.',
Sm='Sm:BAAALgAECgUJCQAAAA==.Smilepally:BAABLgAECn8ZAAIYAAcJKBWbEABXAQAYAAcJKBWbEABXAQAAAA==.',
Sn='Snipedyou:BAAALgAECgIJBAAAAA==.Snomed:BAECLgAFFH8KAAIWAAMJ9B/WAADaAAAWAAMJ9B/WAADaAAAuAAQKfxcAAhYACAluImYCAJoCABYACAluImYCAJoCAAEuAAUUCQkiAA8AZCQA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8mAAMZAAkJ4hZQGgBFAgAZAAkJ4hZQGgBFAgADAAEJ0gEKwgAUAAAAAA==.',
St='Stache:BAAALgAECgcJEQAAAA==.Stantic:BAACLgAFFH8MAAQbAAYJbAeZDQDvAAAbAAQJjQuZDQDvAAAhAAMJJQFQIwBjAAAnAAEJHAJtNgA7AAAuAAQKfx0AAxsACAmgHzogAEQCABsACAnBGzogAEQCACEABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDgABLgAFFAQJFgAIADMYAA==.Steakplisken:BAAALgAECgEJAgAAAA==.Stevethuzad:BAAALgAECgQJBgABLgAECgUJBwAGAAAAAA==.Stormydaniel:BAACLgAFFH8GAAIfAAIJfQaIdABVAAAfAAIJfQaIdABVAAAuAAQKfyAAAx8ACQluEZUrAAsCAB8ACQluEZUrAAsCACAABAn6AeyTAEwAAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.Sunzmoo:BAAALgAECgMJAwAAAA==.',
Sw='Swagadin:BAAALgAFFAQJAwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweatlord:BAAALgAECgQJBAAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Sy='Synikal:BAAALgAECggJEQAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIJAAkJAx0IHwBaAgAJAAkJAx0IHwBaAgABLgAFFAEJAgAGAAAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Tellie:BAAALgADCgUJBQAAAA==.Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thelights:BAAALgADCgMJAwAAAA==.Theprototype:BAAALgAECgYJDgAAAA==.Threeofseven:BAAALgAECgEJAwAAAA==.Thrøat:BAAALgAECgQJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8UAAIBAAQJXSPTDgCSAQABAAQJXSPTDgCSAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDQAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMKAAgJzRc8JAA1AgAKAAgJ6hQ8JAA1AgAoAAIJdBOhWgBvAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAFFAIJAgAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAFFAEJAgAGAAAAAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undeadlysoul:BAAALgAECgYJCAAAAA==.Undedagaindk:BAACLgAFFH85AAMTAAkJxB82AgD1AQATAAkJxB82AgD1AQABAAIJ9B06OABUAAAuAAQKfyUAAxMACQllJicKAEoDABMACQllJicKAEoDAAEAAwl7IM46AKgAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgcJDQAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8hAAMnAAkJsg5JGwDDAQAnAAkJ4gtJGwDDAQAbAAMJTxriowD6AAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8jAAIJAAgJ/gxYcwA7AQAJAAgJ/gxYcwA7AQABLgAECgkJFgANAOoPAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn9AAAQmAAkJQhMBFgB1AQAmAAkJahEBFgB1AQAYAAgJjAy9CwGqAAAeAAEJ7QEnoQAnAAAAAA==.',
Vo='Voidflame:BAAALgAECggJDQAAAA==.Volteil:BAABLgAECn8ZAAIDAAgJCx8fEQA9AgADAAgJCx8fEQA9AgAAAA==.',
Vu='Vuori:BAAALgAECgEJAQAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIZAAkJ4R+uBwAiAwAZAAkJ4R+uBwAiAwAAAA==.',
['Vì']='Vìi:BAAALgAECgcJBwAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAEALgAECgYJBgABLgAFFAkJIgAPAGQkAA==.',
Wh='Whitelove:BAABLgAECn8xAAMkAAkJexuADAClAgAkAAkJexuADAClAgAUAAYJKRYoMQBIAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJDwABLgAECgkJKAAVABIYAA==.Whìtepowder:BAAALgAECgEJAQAAAA==.Whý:BAABLgAECn8YAAIcAAkJzgXPFQD7AAAcAAkJzgXPFQD7AAAAAA==.',
Wi='Wikm:BAABLgAFFH8FAAIJAAMJBwaAdQCaAAAJAAMJBwaAdQCaAAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJGwAYANIiAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn84AAIfAAkJChoeEwCzAgAfAAkJChoeEwCzAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAIVAAkJEhi+CQAgAgAVAAkJEhi+CQAgAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAITAAgJLRj/QgD5AQATAAgJLRj/QgD5AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgAECgEJAQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8LAAMfAAMJuBd1SgDGAAAfAAMJuBd1SgDGAAAgAAMJOhcDNAC/AAAuAAQKfxcAAx8ACAlBGaM9AIoBAB8ABQnHG6M9AIoBACAABwmTHi4OANYAAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCwAfALgXAA==.',
Zo='Zoomies:BAAALgAECgYJDgABLgAECgkJQAARACkkAA==.',
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
