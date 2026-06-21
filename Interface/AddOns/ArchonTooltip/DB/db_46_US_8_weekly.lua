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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warrior-Fury','Priest-Shadow','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Druid-Restoration','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Paladin-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abomination:BAABLgAECn8wAAIBAAkJrwRvLgDrAAABAAkJrwRvLgDrAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8gAAMEAAgJtAqsmQBGAQAEAAgJtAqsmQBGAQAFAAIJCwHQDgA+AAAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgUJBgABLgAECgYJBgAGAAAAAA==.Aldaran:BAAALgAECgYJBgAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJDgAIAEwNAA==.',
As='Ashfallen:BAABLgAECn8YAAIHAAYJ9ASCzwCTAAAHAAYJ9ASCzwCTAAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIJAAMJkhc6NADgAAAJAAMJkhc6NADgAAAuAAQKfysAAgkACQkBIKgLAK0CAAkACQkBIKgLAK0CAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQwxNABIAQAKAAgJOQwxNABIAQAAAA==.Auryx:BAAALgAECgcJEwAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAMJBAAGAAAAAA==.',
Az='Azrel:BAABLgAECn8XAAMLAAkJtAzaIgA5AQALAAkJBAzaIgA5AQAMAAYJJwRNMgCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8eAAQNAAcJSyGqCwA/AgANAAcJSyGqCwA/AgAOAAUJ9BzBAwA3AQAPAAEJzwfmKwA8AAAuAAQKfyIABA4ACAlFJUgKADoCAA0ABgmPJXYQAHECAA4ABwkBHEgKADoCAA8AAQk0CZRJAC8AAAAA.Balbo:BAAALgAECgkJDAABLgAFFAYJHQAMAComAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8dAAIMAAYJKiZpAQD5AQAMAAYJKiZpAQD5AQAuAAQKfzEAAwwACQnwJhQAAAUEAAwACQnwJhQAAAUEAAsABwlbJEIIAGsCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAABLgAECn8gAAIQAAkJsRXVNAAsAgAQAAkJsRXVNAAsAgAAAA==.Bayleef:BAABLgAECn8vAAIRAAkJXx29DgDgAgARAAkJXx29DgDgAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Belac:BAAALgAECgIJAgABLgAFFAQJFgAIADMYAA==.Beldr:BAABLgAECn8XAAISAAkJtA7GKgByAQASAAkJtA7GKgByAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg4uUAAIAQAJAAYJzg4uUAAIAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgADCggJBgAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJCQABLgAECgkJKAATABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABTCNQACAgAIAAkJABTCNQACAgAUAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8NAAIVAAYJrBasCAB9AQAVAAYJrBasCAB9AQAuAAQKfzEAAhUACQmHHfUHAOQCABUACQmHHfUHAOQCAAAA.',
Bu='Bucksmon:BAAALgADCgEJAQAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAgAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECggJIwALADQQAA==.Cheetoh:BAABLgAFFH8LAAMMAAQJMxCIEAC8AAAMAAMJWAyIEAC8AAALAAIJ5hRGBgBNAAABLgAFFAcJIAADAO8XAA==.Chilli:BAAALgAECgYJEQAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8WAAIIAAQJMxinRgA7AQAIAAQJMxinRgA7AQAuAAQKfyQAAggACAljGes7AOsBAAgACAljGes7AOsBAAAA.',
Co='Conall:BAACLgAFFH8XAAIWAAUJ1BOoBgDXAAAWAAUJ1BOoBgDXAAAuAAQKfzUAAhYACQlqHacqAFcCABYACQlqHacqAFcCAAAA.Confetti:BAABLgAECn8fAAIRAAcJvSHuFgCPAgARAAcJvSHuFgCPAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgcJCAAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAFFAIJAgAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJBwAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Dermo:BAAALgAECgMJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBwAAAA==.',
Dm='Dmaw:BAABLgAECn8aAAMXAAYJqAjjQgDTAAAXAAYJqAjjQgDTAAADAAYJZgz/SwDSAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMXAAkJwA94JACPAQAXAAkJwA94JACPAQADAAcJcxIjOgAZAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAFFAIJAgAAAA==.Dragonsloot:BAACLgAFFH8aAAMNAAYJThLqIABZAQANAAYJThLqIABZAQAPAAMJbgEsJQByAAAuAAQKfzkABA0ACQl4HBUQAGgCAA0ACQl4HBUQAGgCAA8ABwleBwQeAAkBAA4AAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8cAAIYAAYJ4gz9GgD4AAAYAAYJ4gz9GgD4AAAAAA==.Drubeastin:BAACLgAFFH8GAAIZAAQJqxCXSQAaAQAZAAQJqxCXSQAaAQAuAAQKfzAAAhkACQkPH6ARAMQCABkACQkPH6ARAMQCAAAA.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
Dy='Dyspeptic:BAAALgAECggJCAABLgAFFAYJDgAWABcGAA==.',
['Dó']='Dónkey:BAAALgADCgcJFgAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgYJEwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgAECgMJAwAAAA==.Elenoa:BAAALgAECgQJBQAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiPhHQBxAgAIAAcJbiXhHQBxAgAaAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgUJDAAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAQAAAA==.',
Fa='Fappio:BAAALgAECgQJDQABLgAECgkJPgAPACkkAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ9UUACVAQAHAAkJig1UUACVAQAVAAQJyhAvSACVAAAbAAMJIAZ8JwBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8SAAIHAAYJpxouJACfAQAHAAYJpxouJACfAQAuAAQKfyMAAgcACAl1ItkUAJwCAAcACAl1ItkUAJwCAAAA.Forlath:BAAALgAECggJDgAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBgAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Galgor:BAAALgAECgYJCwAAAA==.Gamõn:BAAALgAECgMJBwAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gh='Ghaerult:BAAALgADCgEJAQABLgAECgkJIQAcAMUlAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.Groundbeefed:BAAALgADCgYJBgAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIWAAcJ0BedhwBhAQAWAAcJ0BedhwBhAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Hanoe:BAAALgADCgcJBwAAAA==.Harami:BAABLgAECn8cAAIWAAgJfg0MlgBIAQAWAAgJfg0MlgBIAQABLgAFFAMJDgAVANIXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBtGJACLAgAEAAkJfBtGJACLAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJEQAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAgAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAaAAQJSw0tUQB6AAAUAAEJ0QkaPwA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMdAAcJJhAkQACAAQAdAAcJJhAkQACAAQAeAAMJ8B2JXwDGAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8hAAIWAAkJ8yNZAgDfAgAWAAkJ8yNZAgDfAgAuAAQKfyIAAhYACAl1Ji0FAHoDABYACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8JAAIZAAYJfRREHQCQAQAZAAYJfRREHQCQAQAuAAQKfxQAAx8ABgkuHq8wALEBAB8ABgkaHq8wALEBABkAAQluIBC4AFMAAAEuAAUUCQkhABYA8yMA.Hornfu:BAABLgAECn8UAAMDAAYJgBJpAgCFAAADAAYJOg9pAgCFAAACAAMJTxU3AwBQAAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJGwAWANIiAA==.Humanwolf:BAAALgAECgcJEgAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8XAAIIAAUJBSF1BAAeAQAIAAUJBSF1BAAeAQAuAAQKfy0AAggACQn9IRkUAK0CAAgACQn9IRkUAK0CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAcJIAADAO8XAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJGwAWANIiAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ji='Jinkal:BAAALgAECgEJAgAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8RAAIcAAUJow4THQA1AQAcAAUJow4THQA1AQAuAAQKfyYAAhwABwl0FuUnAMwBABwABwl0FuUnAMwBAAEuAAUUBgkUABwAcBEA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAgJFQAfANsZAA==.',
['Jû']='Jûstin:BAAALgAECgYJCgABLgAFFAYJEQAgAEgQAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8OAAIVAAMJ0hcyFwDpAAAVAAMJ0hcyFwDpAAAuAAQKfyoAAxUACQlSHRgJAJkCABUACQlSHRgJAJkCABsAAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQABLgAECgQJBwAGAAAAAA==.Katrint:BAABLgAECn8jAAMhAAkJ6iPHDQBLAgAhAAkJ6iPHDQBLAgAiAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8fAAMSAAYJ2SR0AgB0AgASAAYJ2SR0AgB0AgAKAAEJPg3CFABRAAAuAAQKfxoAAhIACAmhHkYQAGMCABIACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAYJFAAQAMYTAA==.Kiramouse:BAACLgAFFH8mAAQUAAUJDCO6CwDCAAAUAAIJxiC6CwDCAAAIAAQJYhzPCAC5AAAaAAIJgyGoEACvAAAuAAQKfxkABAgACQklIcsRAL4CAAgABwnII8sRAL4CABoAAgk3I2osAGUAABQAAQndDSw5AEIAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAcJIAADAO8XAA==.',
Ky='Kyrié:BAABLgAECn85AAISAAgJKyNRBQAnAwASAAgJKyNRBQAnAwAAAA==.',
La='Lanzadora:BAABLgAECn8bAAIZAAYJvhqhAwAZAQAZAAYJvhqhAwAZAQAAAA==.Largecaliber:BAAALgAECgEJAQAAAA==.Lasinak:BAABLgAECn8iAAQjAAYJXAZ5SADkAAAjAAYJ5gV5SADkAAAKAAYJnQRVBQBPAAASAAEJQAa0BgApAAABLgAFFAMJDgAVANIXAA==.',
Le='Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCwAAAA==.Leto:BAAALgAECgcJDQABLgAECgkJJgAXAOIWAA==.',
Li='Liability:BAACLgAFFH8GAAIkAAMJsQKMJQBtAAAkAAMJsQKMJQBtAAAuAAQKfzUAAiQACQnKB2kjABUBACQACQnKB2kjABUBAAAA.Linez:BAAALgADCgQJBAAAAA==.Lisanalgaib:BAAALgAECggJEAAAAA==.Lithiel:BAAALgAECggJCAAAAA==.Littlearrow:BAAALgAECgYJBgAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8bAAIZAAUJLx3sLgBSAQAZAAUJLx3sLgBSAQAuAAQKfz4AAhkACQlHI+UJAAkDABkACQlHI+UJAAkDAAAA.',
Ma='Magital:BAAALgAECgYJCgABLgAFFAYJGgANAE4SAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIbAAcJMwbuHQCsAAAbAAcJMwbuHQCsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAWANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgQJBwAAAA==.Meowmeowmeow:BAABLgAECn8cAAIMAAcJkxuaDADtAQAMAAcJkxuaDADtAQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIYAAkJXxnICAD+AQAYAAkJXxnICAD+AQAAAA==.Mikeoxlongg:BAAALgAECggJDAAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAlAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.Morkdaorc:BAAALgAECgYJCgAAAA==.',
Mu='Muzuki:BAAALgAECgUJEAAAAA==.',
My='Myrala:BAAALgADCgYJBgAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAQJCgAWAE4MAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECggJIwAHAP4MAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIRAAkJHSHjBwA5AwARAAkJHSHjBwA5AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJQAAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJCAAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgEJAQAAAA==.Nonsocial:BAABLgAFFH8KAAIMAAUJihjTBgA+AQAMAAUJihjTBgA+AQABLgAFFAkJJgAEAOQaAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDQAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJgAXAOIWAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIlAAMJ5hgaAQDkAAAlAAMJ5hgaAQDkAAABLgAFFAYJHQAMAComAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgcJDgAAAA==.Pahine:BAABLgAFFH8HAAITAAMJpQ48DwDOAAATAAMJpQ48DwDOAAABLgAFFAMJDgAVANIXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAABLgAFFH8GAAMWAAMJCgindwDGAAAWAAMJCgindwDGAAAcAAEJQgBzUgAVAAAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn80AAIEAAkJkyCiFADdAgAEAAkJkyCiFADdAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECggJEgAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8bAAIWAAUJ0iJ2HQCTAQAWAAUJ0iJ2HQCTAQAuAAQKfzYAAhYACQnzJfQEAFADABYACQnzJfQEAFADAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECggJFgAWAMIdAA==.Rabbidlight:BAABLgAECn8WAAMWAAgJwh3VZgCyAQAWAAcJwxzVZgCyAQAcAAYJRg7CYACyAAAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8kAAIWAAkJyhqcNgAnAgAWAAkJyhqcNgAnAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAABLgAECn8VAAIgAAYJwxbcAQDaAAAgAAYJwxbcAQDaAAAAAA==.Satoru:BAAALgAECgYJCgAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAkJOAAIADIaAA==.',
Se='Segen:BAABLgAECn8aAAIEAAgJBBLUbQCfAQAEAAgJBBLUbQCfAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn8gAAIZAAYJpwocnwADAQAZAAYJpwocnwADAQAAAA==.Sen:BAABLgAECn8yAAQZAAkJvyOQEADMAgAZAAkJgyKQEADMAgAfAAcJ7h6gCQDbAQAnAAIJDxXtTQB6AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8XAAMCAAcJqAfEWACmAAACAAcJJQTEWACmAAADAAQJ/AcwXgCYAAABLgAFFAMJDgAVANIXAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJCAAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Si='Sieben:BAAALgAECgEJAQAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8gAAIDAAcJ7xdWBQDIAQADAAcJ7xdWBQDIAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGKkkAIcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCggJCwAAAA==.',
Sm='Sm:BAAALgAECgIJAwAAAA==.Smilepally:BAAALgAECgcJEwAAAA==.',
Sn='Snipedyou:BAAALgAECgIJAwAAAA==.Snomed:BAACLgAFFH8KAAIUAAMJ9B/WAADaAAAUAAMJ9B/WAADaAAAuAAQKfxcAAhQACAluImYCAJoCABQACAluImYCAJoCAAEuAAUUBgkdAAwAKiYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8mAAMXAAkJ4hZRGgBFAgAXAAkJ4hZRGgBFAgADAAEJ0gEKwgAUAAAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stantic:BAACLgAFFH8MAAQZAAYJbAeZDQDvAAAZAAQJjQuZDQDvAAAfAAMJJQFQIwBjAAAnAAEJHAJpNgA7AAAuAAQKfx0AAxkACAmgHzogAEQCABkACAnBGzogAEQCAB8ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDgABLgAFFAQJFgAIADMYAA==.Stevethuzad:BAAALgAECgQJBgABLgAECgUJBwAGAAAAAA==.Stormydaniel:BAACLgAFFH8GAAIdAAIJfQaIdABVAAAdAAIJfQaIdABVAAAuAAQKfx8AAx0ACQkfEZMrAAsCAB0ACQkfEZMrAAsCAB4ABAn6Ae+TAEwAAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAFFAQJAQAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx0KHwBaAgAHAAkJAx0KHwBaAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Threeofseven:BAAALgAECgEJAgAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8UAAIBAAQJXSPZDgCSAQABAAQJXSPZDgCSAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDQAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAoAAIJdBOhWgBvAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAFFAIJAgAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undedagaindk:BAACLgAFFH8oAAMQAAgJKh42AgD1AQAQAAgJKh42AgD1AQABAAIJ9B08OABUAAAuAAQKfyUAAxAACQllJicKAEoDABAACQllJicKAEoDAAEAAwl7IM06AKgAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgcJCwAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8hAAMnAAkJsg5KGwDDAQAnAAkJ4gtKGwDDAQAZAAMJTxriowD6AAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8jAAIHAAgJ/gxZcwA7AQAHAAgJ/gxZcwA7AQAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn9AAAQmAAkJQhMBFgB1AQAmAAkJahEBFgB1AQAWAAgJjAy4CwGqAAAcAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8ZAAIDAAgJCx8fEQA9AgADAAgJCx8fEQA9AgAAAA==.',
Vu='Vuori:BAAALgAECgEJAQAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIXAAkJ4R+wBwAiAwAXAAkJ4R+wBwAiAwAAAA==.',
['Vì']='Vìi:BAAALgAECgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJHQAMAComAA==.',
Wh='Whitelove:BAABLgAECn8xAAMjAAkJexuADAClAgAjAAkJexuADAClAgASAAYJKRYjMQBIAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJDwABLgAECgkJKAATABIYAA==.Whý:BAABLgAECn8XAAIaAAkJzgXNFQD7AAAaAAkJzgXNFQD7AAAAAA==.',
Wi='Wikm:BAAALgAFFAMJBAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJGwAWANIiAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn83AAIdAAkJChodEwCzAgAdAAkJChodEwCzAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAITAAkJEhi+CQAgAgATAAkJEhi+CQAgAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIQAAgJLRj7QgD5AQAQAAgJLRj7QgD5AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8KAAMdAAMJuBdzSgDGAAAdAAMJuBdzSgDGAAAeAAMJOhcENAC/AAAuAAQKfxUAAx0ACAlBGaM9AIoBAB0ABQnHG6M9AIoBAB4ABwnrHHZOAPwAAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCgAdALgXAA==.',
Zo='Zoomies:BAAALgAECgYJDgABLgAECgkJPgAPACkkAA==.',
Zu='Zugmeoff:BAAALgAECgEJAQAAAA==.',
['Zé']='Zémzel:BAAALgAECgQJBwAAAA==.',
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
