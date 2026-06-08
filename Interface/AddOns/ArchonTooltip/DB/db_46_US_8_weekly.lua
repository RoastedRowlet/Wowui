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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warrior-Fury','Priest-Shadow','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Druid-Restoration','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warrior-Protection','Rogue-Outlaw','Paladin-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abomination:BAABLgAECn8pAAIBAAkJeAMPLgDiAAABAAkJeAMPLgDiAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8aAAMEAAcJfgju4wAtAQAEAAcJfgju4wAtAQAFAAIJCwHQDgA+AAAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgQJBAAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgQJBAAGAAAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJDAAIAEwNAA==.',
As='Ashfallen:BAAALgAECgYJEwAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIJAAMJkhf5LgDgAAAJAAMJkhf5LgDgAAAuAAQKfysAAgkACQkBIIUKALUCAAkACQkBIIUKALUCAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQwVMABWAQAKAAgJOQwVMABWAQAAAA==.Auryx:BAAALgAECgYJDAAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAIJAwAGAAAAAA==.',
Az='Azrel:BAABLgAECn8WAAMLAAkJtAwLIAA6AQALAAkJBAwLIAA6AQAMAAYJJwR/LgCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8ZAAQNAAYJZSFuDwDmAQANAAYJZSFuDwDmAQAOAAUJ9BwUAwBEAQAPAAEJzwf4KAA8AAAuAAQKfyIABA4ACAlFJUgKADoCAA0ABgmPJXYQAHECAA4ABwkBHEgKADoCAA8AAQk0CZRJAC8AAAAA.Balbo:BAAALgAECgkJDAABLgAFFAYJFwAMAComAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8XAAIMAAYJKiYAAQADAgAMAAYJKiYAAQADAgAuAAQKfzEAAwwACQnwJhQAAAUEAAwACQnwJhQAAAUEAAsABwlbJI0HAGwCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAABLgAECn8gAAIQAAkJsRWbMQAwAgAQAAkJsRWbMQAwAgAAAA==.Bayleef:BAABLgAECn8vAAIRAAkJXx3nDQDhAgARAAkJXx3nDQDhAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAFFAQJEAAIALEXAA==.Beldr:BAABLgAECn8XAAISAAkJtA63KABzAQASAAkJtA63KABzAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg64SwAOAQAJAAYJzg64SwAOAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgADCggJBgAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJBwABLgAECgkJKAATABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABSUMgAJAgAIAAkJABSUMgAJAgAUAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8MAAIVAAUJtBY4DQApAQAVAAUJtBY4DQApAQAuAAQKfzAAAhUACQn+HPUHAOQCABUACQn+HPUHAOQCAAAA.',
Bu='Bucksmon:BAAALgADCgEJAQAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECgcJIQALAKwRAA==.Cheetoh:BAABLgAFFH8GAAILAAIJ5hS4IgB6AAALAAIJ5hS4IgB6AAABLgAFFAYJHwADAEgbAA==.Chilli:BAAALgAECgEJAgAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8QAAIIAAQJsRdlPgBAAQAIAAQJsRdlPgBAAQAuAAQKfyQAAggACAljGc84APEBAAgACAljGc84APEBAAAA.',
Co='Conall:BAACLgAFFH8TAAIWAAUJ1BHOQAAbAQAWAAUJ1BHOQAAbAQAuAAQKfzUAAhYACQlqHXknAFoCABYACQlqHXknAFoCAAAA.Confetti:BAABLgAECn8fAAIRAAcJvSHCFQCQAgARAAcJvSHCFQCQAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgYJBwAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAECgUJBQAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJBQAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Dermo:BAAALgAECgMJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMDAAYJZgx4RwDVAAADAAYJZgx4RwDVAAAXAAYJdwbjQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMXAAkJwA94JACPAQAXAAkJwA94JACPAQADAAcJcxK3NgAbAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAECgcJCgAAAA==.Dragonsloot:BAACLgAFFH8aAAMNAAYJThIeGwBpAQANAAYJThIeGwBpAQAPAAMJbgHmIgByAAAuAAQKfzkABA0ACQl4HGwPAGgCAA0ACQl4HGwPAGgCAA8ABwleB6McAA8BAA4AAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8WAAIYAAUJVgunIAC1AAAYAAUJVgunIAC1AAAAAA==.Drubeastin:BAABLgAECn8wAAIZAAkJDx9FDwDNAgAZAAkJDx9FDwDNAgAAAA==.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dó']='Dónkey:BAAALgADCgcJFgAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgYJDwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgADCgIJAgAAAA==.Elenoa:BAAALgAECgMJAwAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiP/GwB2AgAIAAcJbiX/GwB2AgAaAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgUJDAAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAQAAAA==.',
Fa='Fappio:BAAALgAECgQJCwABLgAECgkJOAAPACkkAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ9BTACUAQAHAAkJig1BTACUAQAVAAQJyhCPQgCYAAAbAAMJIAYgJQBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8PAAIHAAUJdiAfJwB0AQAHAAUJdiAfJwB0AQAuAAQKfyMAAgcACAl1ImUTAJ0CAAcACAl1ImUTAJ0CAAAA.Forlath:BAAALgAECggJCAAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBQAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Gamõn:BAAALgAECgMJBgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIWAAcJ0BccgABjAQAWAAcJ0BccgABjAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAABLgAECn8aAAIWAAcJngupqQAdAQAWAAcJngupqQAdAQABLgAFFAMJCwAVAPEXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBvMIQCRAgAEAAkJfBvMIQCRAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJDgAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAQAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAaAAQJSw0tUQB6AAAUAAEJ0QkeOgA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMcAAcJJhAkQACAAQAcAAcJJhAkQACAAQAdAAMJ8B0AWgDGAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8fAAIWAAgJ/SPNAABWAgAWAAgJ/SPNAABWAgAuAAQKfyIAAhYACAl1Ji0FAHoDABYACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8JAAIZAAYJpBRLFQCbAQAZAAYJpBRLFQCbAQAuAAQKfxQAAx4ABgkuHq8wALEBAB4ABgkaHq8wALEBABkAAQluIBC4AFMAAAEuAAUUCAkfABYA/SMA.Hornfu:BAAALgAECgYJEAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJEwAWAMogAA==.Humanwolf:BAAALgAECgcJEwAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8PAAIIAAUJBSEWMABsAQAIAAUJBSEWMABsAQAuAAQKfy0AAggACQn9IXcSALMCAAgACQn9IXcSALMCAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAYJHwADAEgbAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJEwAWAMogAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8MAAIfAAMJYhbvKQDOAAAfAAMJYhbvKQDOAAAuAAQKfyMAAh8ABwl0FgUmAM4BAB8ABwl0FgUmAM4BAAEuAAUUBQkSAB8AZhQA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAYJEgAeAJoXAA==.',
['Jû']='Jûstin:BAAALgAECgEJAQABLgAFFAYJEAAgAEgQAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8LAAIVAAMJ8Rf5EwDtAAAVAAMJ8Rf5EwDtAAAuAAQKfyoAAxUACQlSHTQIAJ0CABUACQlSHTQIAJ0CABsAAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQAAAA==.Katrint:BAABLgAECn8jAAMhAAkJ6iOaDABQAgAhAAkJ6iOaDABQAgAiAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8eAAMSAAUJniRPBAALAgASAAUJniRPBAALAgAKAAEJPg3CFABRAAAuAAQKfxoAAhIACAmhHkYQAGMCABIACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAUJCAAEACYFAA==.Kiramouse:BAACLgAFFH8eAAQUAAUJNiIzCwC1AAAIAAQJYhxfIgD7AAAaAAIJgyEODgC3AAAUAAIJXx0zCwC1AAAuAAQKfxkABAgACQklIV4QAMMCAAgABwnII14QAMMCABoAAgk3I7kpAGcAABQAAQndDUs0AEMAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAYJHwADAEgbAA==.',
Ky='Kyrié:BAABLgAECn8wAAISAAYJYyR9EABVAgASAAYJYyR9EABVAgAAAA==.',
La='Lanzadora:BAABLgAECn8VAAIZAAYJ/xlQXACEAQAZAAYJ/xlQXACEAQAAAA==.Largecaliber:BAAALgAECgEJAQAAAA==.Lasinak:BAABLgAECn8aAAMjAAYJMAQ7SADUAAAjAAYJMAQ7SADUAAAKAAYJDANXYACIAAABLgAFFAMJCwAVAPEXAA==.',
Le='Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCgAAAA==.Leto:BAAALgAECgcJCAABLgAECgkJJQAXAAcWAA==.',
Li='Liability:BAABLgAECn80AAIkAAkJrAZ/IQAXAQAkAAkJrAZ/IQAXAQAAAA==.Linez:BAAALgADCgQJBAAAAA==.Lithiel:BAAALgAECggJCAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8UAAIZAAUJLx2lJQBcAQAZAAUJLx2lJQBcAQAuAAQKfzwAAhkACQk7I9sIAAoDABkACQk7I9sIAAoDAAAA.',
Ma='Magital:BAAALgAECgYJCgABLgAFFAYJGgANAE4SAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIbAAcJMwYdHACsAAAbAAcJMwYdHACsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAWANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgMJBQABLgAECgQJBQAGAAAAAA==.Meowmeowmeow:BAABLgAECn8WAAIMAAcJ2hh7DgC8AQAMAAcJ2hh7DgC8AQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIYAAkJXxnABwAIAgAYAAkJXxnABwAIAgAAAA==.Mikeoxlongg:BAAALgAECggJDAAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAlAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgQJCwAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAMJBgAWACsNAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECggJIgAHAPALAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIRAAkJHSFQBwA7AwARAAkJHSFQBwA7AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJPwAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBwAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgEJAQAAAA==.Nonsocial:BAABLgAFFH8IAAIMAAUJCBO4BwAiAQAMAAUJCBO4BwAiAQAAAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDAAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJQAXAAcWAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIlAAMJ5hgaAQDkAAAlAAMJ5hgaAQDkAAABLgAFFAYJFwAMAComAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgcJDQAAAA==.Pahine:BAAALgAFFAMJAwABLgAFFAMJCwAVAPEXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAAALgAFFAIJAwAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn80AAIEAAkJkyDeEgDjAgAEAAkJkyDeEgDjAgAAAA==.Protoknightl:BAAALgAECgQJBAAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECggJEgAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8TAAIWAAUJyiCeHQB6AQAWAAUJyiCeHQB6AQAuAAQKfzYAAhYACQnzJSQEAFUDABYACQnzJSQEAFUDAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECggJFgAWAMIdAA==.Rabbidlight:BAABLgAECn8WAAMWAAgJwh3VZgCyAQAWAAcJwxzVZgCyAQAfAAYJRg6oXQCyAAAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8kAAIWAAkJyhrdMgAqAgAWAAkJyhrdMgAqAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJEQAAAA==.Satoru:BAAALgAECgYJCgAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAgJLQAIAMEbAA==.',
Se='Segen:BAABLgAECn8YAAIEAAcJtBDYkwBLAQAEAAcJtBDYkwBLAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn8fAAIZAAYJpwq0lAAJAQAZAAYJpwq0lAAJAQAAAA==.Sen:BAABLgAECn8xAAQZAAkJvyNRDgDUAgAZAAkJgyJRDgDUAgAeAAcJ7h5HDQB/AQAnAAIJDxXaSgB+AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8VAAMCAAcJjgbXWACfAAACAAcJCwPXWACfAAADAAQJ/AcwXgCYAAABLgAFFAMJCwAVAPEXAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJBgAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8fAAIDAAYJSBugBwCOAQADAAYJSBugBwCOAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGDcjAIkBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCgMJAwAAAA==.',
Sm='Sm:BAAALgAECgIJAwAAAA==.Smilepally:BAAALgAECgcJDgAAAA==.',
Sn='Snipedyou:BAAALgAECgIJAwAAAA==.Snomed:BAACLgAFFH8KAAIUAAMJ9B/WAADaAAAUAAMJ9B/WAADaAAAuAAQKfxcAAhQACAluImYCAJoCABQACAluImYCAJoCAAEuAAUUBgkXAAwAKiYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8lAAMXAAkJBxayGgAuAgAXAAkJBxayGgAuAgADAAEJ0gGAtQAUAAAAAA==.',
St='Stache:BAAALgADCgUJBQAAAA==.Stantic:BAACLgAFFH8MAAQZAAYJbAeZDQDvAAAZAAQJjQuZDQDvAAAeAAMJJQFQIwBjAAAnAAEJHAI7MgA8AAAuAAQKfx0AAxkACAmgHzogAEQCABkACAnBGzogAEQCAB4ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDQABLgAFFAQJEAAIALEXAA==.Stevethuzad:BAAALgAECgQJBQAAAA==.Stormydaniel:BAACLgAFFH8FAAIcAAIJfQZBaQBaAAAcAAIJfQZBaQBaAAAuAAQKfx8AAxwACQkfEfsoAAwCABwACQkfEfsoAAwCAB0ABAn6AZyKAE0AAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx1XHQBaAgAHAAkJAx1XHQBaAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Threeofseven:BAAALgAECgEJAgAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8QAAIBAAQJwCKMDACUAQABAAQJwCKMDACUAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAoAAIJdBOEVQBuAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAECgYJBwAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undedagaindk:BAACLgAFFH8jAAMQAAgJAh3uBACzAgAQAAgJAh3uBACzAgABAAEJ9B0WMwBXAAAuAAQKfyUAAxAACQllJicKAEoDABAACQllJicKAEoDAAEAAwl7IO03AKoAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgYJDAAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8bAAInAAkJtgm8HACyAQAnAAkJtgm8HACyAQAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8iAAIHAAgJ8As9bgA6AQAHAAgJ8As9bgA6AQAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8/AAQmAAkJQhO2FAB4AQAmAAkJahG2FAB4AQAWAAgJjAw3+wCvAAAfAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8YAAIDAAgJxR7tEgAcAgADAAgJxR7tEgAcAgAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIXAAkJ4R8FBwAhAwAXAAkJ4R8FBwAhAwAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJFwAMAComAA==.',
Wh='Whitelove:BAABLgAECn8xAAMjAAkJext1CwCrAgAjAAkJext1CwCrAgASAAYJKRavLgBKAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJCwABLgAECgkJKAATABIYAA==.Whý:BAABLgAECn8XAAIaAAkJzgU4FAAAAQAaAAkJzgU4FAAAAQAAAA==.',
Wi='Wikm:BAAALgAFFAMJBAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJEwAWAMogAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8xAAIcAAkJhhkoFACeAgAcAAkJhhkoFACeAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAITAAkJEhj7CAAkAgATAAkJEhj7CAAkAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIQAAgJLRiXPwD9AQAQAAgJLRiXPwD9AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8KAAMdAAMJOhe2LQDMAAAdAAMJOhe2LQDMAAAcAAMJuBfoQgDJAAAuAAQKfxUAAxwACAlBGaM9AIoBABwABQnHG6M9AIoBAB0ABwnrHMNJAP0AAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCgAdADoXAA==.',
Zo='Zoomies:BAAALgAECgYJDgABLgAECgkJOAAPACkkAA==.',
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
