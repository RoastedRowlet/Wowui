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
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abomination:BAABLgAECn8vAAIBAAkJrwQgLQDwAAABAAkJrwQgLQDwAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgYJEAAAAA==.Adina:BAABLgAECn8fAAMEAAgJVgnEtgAUAQAEAAgJVgnEtgAUAQAFAAIJCwHQDgA+AAAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alastornox:BAAALgAECgUJBgAAAA==.Alianicus:BAAALgADCgIJAgABLgAECgUJBgAGAAAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAUJDgAIAEwNAA==.',
As='Ashfallen:BAABLgAECn8YAAIHAAYJ9ARCzACTAAAHAAYJ9ARCzACTAAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8JAAIJAAMJkheWMgDgAAAJAAMJkheWMgDgAAAuAAQKfysAAgkACQkBIGILALACAAkACQkBIGILALACAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQwAMwBMAQAKAAgJOQwAMwBMAQAAAA==.Auryx:BAAALgAECgcJEwAAAA==.',
Ay='Ay:BAAALgAFFAEJAwABLgAFFAIJAwAGAAAAAA==.',
Az='Azrel:BAABLgAECn8WAAMLAAkJtAwTIgA5AQALAAkJBAwTIgA5AQAMAAYJJwQqMQCWAAAAAA==.',
Ba='Babyoils:BAAALgADCgQJBAAAAA==.Baddragon:BAACLgAFFH8dAAQNAAcJSyGqCgBFAgANAAcJSyGqCgBFAgAOAAUJ9ByYAwA4AQAPAAEJzwfeKgA8AAAuAAQKfyIABA4ACAlFJUgKADoCAA0ABgmPJXYQAHECAA4ABwkBHEgKADoCAA8AAQk0CZRJAC8AAAAA.Balbo:BAAALgAECgkJDAABLgAFFAYJGQAMAComAA==.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8ZAAIMAAYJKiZLAQD6AQAMAAYJKiZLAQD6AQAuAAQKfzEAAwwACQnwJhQAAAUEAAwACQnwJhQAAAUEAAsABwlbJA8IAGsCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAABLgAECn8gAAIQAAkJsRUxNAAsAgAQAAkJsRUxNAAsAgAAAA==.Bayleef:BAABLgAECn8vAAIRAAkJXx2GDgDgAgARAAkJXx2GDgDgAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Belac:BAAALgAECgIJAgABLgAFFAQJFAAIADMYAA==.Beldr:BAABLgAECn8XAAISAAkJtA4oKgByAQASAAkJtA4oKgByAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg5STgANAQAJAAYJzg5STgANAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bordrin:BAAALgADCggJBgAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgcJCQABLgAECgkJKAATABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8nAAMIAAkJABQuNQADAgAIAAkJABQuNQADAgAUAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8MAAIVAAUJtBYeDwAoAQAVAAUJtBYeDwAoAQAuAAQKfzEAAhUACQmHHfUHAOQCABUACQmHHfUHAOQCAAAA.',
Bu='Bucksmon:BAAALgADCgEJAQAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAgAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECggJIgALADQQAA==.Cheetoh:BAABLgAFFH8KAAMMAAQJMxDiDwC8AAAMAAMJWAziDwC8AAALAAIJ5hR0JwB4AAABLgAFFAcJIAADAO8XAA==.Chilli:BAAALgAECgYJDQAAAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8UAAIIAAQJMxjXQwA9AQAIAAQJMxjXQwA9AQAuAAQKfyQAAggACAljGVc7AOwBAAgACAljGVc7AOwBAAAA.',
Co='Conall:BAACLgAFFH8UAAIWAAUJ1BGaRwAYAQAWAAUJ1BGaRwAYAQAuAAQKfzUAAhYACQlqHfopAFgCABYACQlqHfopAFgCAAAA.Confetti:BAABLgAECn8fAAIRAAcJvSGJFgCQAgARAAcJvSGJFgCQAgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJEQAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgcJCAAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deadmaw:BAAALgAFFAIJAgAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJBgAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCQAAAA==.Dermo:BAAALgAECgMJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBwAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMDAAYJZgxXSgDVAAADAAYJZgxXSgDVAAAXAAYJdwbjQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMXAAkJwA94JACPAQAXAAkJwA94JACPAQADAAcJcxK7OAAbAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonknite:BAAALgAECgcJCgAAAA==.Dragonsloot:BAACLgAFFH8aAAMNAAYJThJgHwBdAQANAAYJThJgHwBdAQAPAAMJbgFQJAByAAAuAAQKfzkABA0ACQl4HOwPAGgCAA0ACQl4HOwPAGgCAA8ABwleB6odAAkBAA4AAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAABLgAECn8cAAIYAAYJ4gxxGgD5AAAYAAYJ4gxxGgD5AAAAAA==.Drubeastin:BAACLgAFFH8GAAIZAAQJqxDQRQAbAQAZAAQJqxDQRQAbAQAuAAQKfzAAAhkACQkPH/AQAMYCABkACQkPH/AQAMYCAAAA.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
Dy='Dyspeptic:BAAALgAECggJCAABLgAFFAYJDgAWABcGAA==.',
['Dó']='Dónkey:BAAALgADCgcJFgAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgYJEwAAAA==.Eleara:BAAALgAECgEJAQAAAA==.Elementtamer:BAAALgAECgMJAwAAAA==.Elenoa:BAAALgAECgMJAwAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiNlHQByAgAIAAcJbiVlHQByAgAaAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgUJDAAAAA==.Evilinside:BAAALgADCgUJBQAAAA==.Evilmt:BAAALgAECgEJBAAAAA==.Evilsilence:BAAALgAECgEJAQAAAA==.',
Fa='Fappio:BAAALgAECgQJDAABLgAECgkJOAAPACkkAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ8bTwCVAQAHAAkJig0bTwCVAQAVAAQJyhBDRgCYAAAbAAMJIAbaJgBnAAABLgAECgkJJQAEAN8dAA==.',
Fe='Fedul:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8SAAIHAAYJpxqrIQCiAQAHAAYJpxqrIQCiAQAuAAQKfyMAAgcACAl1ImsUAJwCAAcACAl1ImsUAJwCAAAA.Forlath:BAAALgAECggJDgAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJCAAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgAECgUJBgAAAA==.',
Ga='Gabarra:BAAALgAECgYJBwAAAA==.Gairmet:BAAALgAECgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Gamõn:BAAALgAECgMJBgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECggJCQAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.Groundbeefed:BAAALgADCgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgQJBAAAAA==.Gullveig:BAABLgAECn8YAAIWAAcJ0BemhQBhAQAWAAcJ0BemhQBhAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Hanoe:BAAALgADCgcJBwAAAA==.Harami:BAABLgAECn8aAAIWAAcJngu/rwAdAQAWAAcJngu/rwAdAQABLgAFFAMJDgAVANIXAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8tAAIEAAkJfBtuIwCNAgAEAAkJfBtuIwCNAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJEQAAAA==.Helmon:BAAALgAECgcJDQAAAA==.Helpmoo:BAAALgAECgEJAQAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAaAAQJSw0tUQB6AAAUAAEJ0QmXPQA0AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMcAAcJJhAkQACAAQAcAAcJJhAkQACAAQAdAAMJ8B0qXgDGAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8fAAIWAAgJ/SPNAABWAgAWAAgJ/SPNAABWAgAuAAQKfyIAAhYACAl1Ji0FAHoDABYACAl1Ji0FAHoDAAAA.Hordeforsure:BAACLgAFFH8JAAIZAAYJfRQHGwCQAQAZAAYJfRQHGwCQAQAuAAQKfxQAAx4ABgkuHq8wALEBAB4ABgkaHq8wALEBABkAAQluIBC4AFMAAAEuAAUUCAkfABYA/SMA.Hornfu:BAAALgAECgYJEAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDgABLgAFFAUJGAAWANIiAA==.Humanwolf:BAAALgAECgcJEwAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8UAAIIAAUJBSFHNABvAQAIAAUJBSFHNABvAQAuAAQKfy0AAggACQn9IY8TAK8CAAgACQn9IY8TAK8CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAcJIAADAO8XAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAUJGAAWANIiAA==.Jazzie:BAAALgAECgEJAQAAAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAACLgAFFH8NAAIfAAMJYhZ3LADFAAAfAAMJYhZ3LADFAAAuAAQKfyYAAh8ABwl0FmEnAM0BAB8ABwl0FmEnAM0BAAEuAAUUBgkTAB8AcBEA.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwABLgAFFAcJFAAeAKIYAA==.',
['Jû']='Jûstin:BAAALgAECgMJAwABLgAFFAYJEQAgAEgQAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAACLgAFFH8OAAIVAAMJ0hdjFgDqAAAVAAMJ0hdjFgDqAAAuAAQKfyoAAxUACQlSHeIIAJoCABUACQlSHeIIAJoCABsAAwlOBJojAGUAAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQABLgAECgQJBwAGAAAAAA==.Katrint:BAABLgAECn8jAAMhAAkJ6iN0DQBMAgAhAAkJ6iN0DQBMAgAiAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgAECgMJAwAAAA==.',
Kh='Kheliyah:BAACLgAFFH8fAAMSAAYJ2SQyAgB3AgASAAYJ2SQyAgB3AgAKAAEJPg3CFABRAAAuAAQKfxoAAhIACAmhHkYQAGMCABIACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAYJEwAQAMYTAA==.Kiramouse:BAACLgAFFH8jAAQUAAUJDCMpCwDDAAAIAAQJYhxfIgD7AAAUAAIJxiApCwDDAAAaAAIJgyHLDwCyAAAuAAQKfxkABAgACQklIV0RAMACAAgABwnII10RAMACABoAAgk3I30rAGYAABQAAQndDWw3AEMAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAcJIAADAO8XAA==.',
Ky='Kyrié:BAABLgAECn82AAISAAYJWCU2DgCBAgASAAYJWCU2DgCBAgAAAA==.',
La='Lanzadora:BAABLgAECn8VAAIZAAYJ/xk+YQB/AQAZAAYJ/xk+YQB/AQAAAA==.Largecaliber:BAAALgAECgEJAQAAAA==.Lasinak:BAABLgAECn8fAAMjAAYJ5gWJRgDqAAAjAAYJ5gWJRgDqAAAKAAYJDAO/ZACEAAABLgAFFAMJDgAVANIXAA==.',
Le='Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCwAAAA==.Leto:BAAALgAECgcJDQABLgAECgkJJgAXAOIWAA==.',
Li='Liability:BAABLgAECn80AAIkAAkJrAbgIgAVAQAkAAkJrAbgIgAVAQAAAA==.Linez:BAAALgADCgQJBAAAAA==.Lisanalgaib:BAAALgAECgQJBQAAAA==.Lithiel:BAAALgAECggJCAAAAA==.Littlearrow:BAAALgAECgYJBgAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8ZAAIZAAUJLx2nKwBUAQAZAAUJLx2nKwBUAQAuAAQKfz0AAhkACQk7I+wJAAYDABkACQk7I+wJAAYDAAAA.',
Ma='Magital:BAAALgAECgYJCgABLgAFFAYJGgANAE4SAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAABLgAECn8VAAIbAAcJMwZnHQCsAAAbAAcJMwZnHQCsAAAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAWANsVAA==.Mandalay:BAAALgADCgQJAQAAAA==.',
Mc='Mctowservan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgYJDAAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgQJBwAAAA==.Meowmeowmeow:BAABLgAECn8cAAIMAAcJkxtUDADtAQAMAAcJkxtUDADtAQAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIYAAkJXxl5CAAEAgAYAAkJXxl5CAAEAgAAAA==.Mikeoxlongg:BAAALgAECggJDAAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJHQAlAK8NAA==.Mixxy:BAAALgADCgIJAgAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.Morkdaorc:BAAALgAECgQJBQAAAA==.',
Mu='Muzuki:BAAALgAECgUJEAAAAA==.',
['Mî']='Mîsfire:BAAALgAECgIJAwABLgAFFAQJCgAWAE4MAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECggJIgAHAPALAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIRAAkJHSG0BwA6AwARAAkJHSG0BwA6AwAAAA==.',
Ne='Necalli:BAAALgAECgMJAwABLgAECgkJPwAmAEITAA==.Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBwAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nomischief:BAAALgAECgEJAQAAAA==.Nonsocial:BAABLgAFFH8IAAIMAAUJCBPACAAaAQAMAAUJCBPACAAaAQAAAA==.Nopants:BAAALgAECgEJBAABLgAECgYJDAAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgkJJgAXAOIWAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIlAAMJ5hgaAQDkAAAlAAMJ5hgaAQDkAAABLgAFFAYJGQAMAComAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgcJDgAAAA==.Pahine:BAABLgAFFH8GAAITAAMJqQp+DwDIAAATAAMJqQp+DwDIAAABLgAFFAMJDgAVANIXAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAABLgAFFH8GAAMWAAMJCgjwcwDGAAAWAAMJCgjwcwDGAAAfAAEJQgCqUAAVAAAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn80AAIEAAkJkyAbFADeAgAEAAkJkyAbFADeAgAAAA==.Protoknightl:BAAALgAECgYJCgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECggJEgAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8YAAIWAAUJ0iIJGwCVAQAWAAUJ0iIJGwCVAQAuAAQKfzYAAhYACQnzJboEAFIDABYACQnzJboEAFIDAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECggJFgAWAMIdAA==.Rabbidlight:BAABLgAECn8WAAMWAAgJwh3VZgCyAQAWAAcJwxzVZgCyAQAfAAYJRg4MYACyAAAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgYJBwAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8kAAIWAAkJyhqoNQAoAgAWAAkJyhqoNQAoAgAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJEQAAAA==.Satoru:BAAALgAECgYJCgAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAgJMQAIADkcAA==.',
Se='Segen:BAABLgAECn8aAAIEAAgJBBIebACgAQAEAAgJBBIebACgAQAAAA==.Selo:BAAALgAECgEJAQAAAA==.Semip:BAABLgAECn8fAAIZAAYJpwoTnAADAQAZAAYJpwoTnAADAQAAAA==.Sen:BAABLgAECn8yAAQZAAkJvyPlDwDOAgAZAAkJgyLlDwDOAgAeAAcJ7h5hCQDbAQAnAAIJDxU+TQB6AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaera:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8WAAMCAAcJqAfgVwCmAAACAAcJJQTgVwCmAAADAAQJ/AcwXgCYAAABLgAFFAMJDgAVANIXAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJBwAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8gAAIDAAcJ7xfwBADLAQADAAcJ7xfwBADLAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGEokAIcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgQJBAAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.Slicey:BAAALgADCggJCAAAAA==.',
Sm='Sm:BAAALgAECgIJAwAAAA==.Smilepally:BAAALgAECgcJDgAAAA==.',
Sn='Snipedyou:BAAALgAECgIJAwAAAA==.Snomed:BAACLgAFFH8KAAIUAAMJ9B/WAADaAAAUAAMJ9B/WAADaAAAuAAQKfxcAAhQACAluImYCAJoCABQACAluImYCAJoCAAEuAAUUBgkZAAwAKiYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8mAAMXAAkJ4hbbGQBEAgAXAAkJ4hbbGQBEAgADAAEJ0gE/vgAUAAAAAA==.',
St='Stache:BAAALgADCgUJBQAAAA==.Stantic:BAACLgAFFH8MAAQZAAYJbAeZDQDvAAAZAAQJjQuZDQDvAAAeAAMJJQFQIwBjAAAnAAEJHAIxNQA7AAAuAAQKfx0AAxkACAmgHzogAEQCABkACAnBGzogAEQCAB4ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDgABLgAFFAQJFAAIADMYAA==.Stevethuzad:BAAALgAECgQJBQABLgAECgUJBwAGAAAAAA==.Stormydaniel:BAACLgAFFH8GAAIcAAIJfQYocQBVAAAcAAIJfQYocQBVAAAuAAQKfx8AAxwACQkfEc0qAAsCABwACQkfEc0qAAsCAB0ABAn6AfGQAE0AAAAA.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx2HHgBaAgAHAAkJAx2HHgBaAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Te='Texxar:BAAALgAECggJCAAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Threeofseven:BAAALgAECgEJAgAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAFFAIJAgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8UAAIBAAQJXSPoDQCWAQABAAQJXSPoDQCWAQAuAAQKfxsAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAoAAIJdBOzWABvAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgAECgYJCAAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undedagaindk:BAACLgAFFH8oAAMQAAgJKh5pBgC0AgAQAAgJKh5pBgC0AgABAAIJ9B0uNwBVAAAuAAQKfyUAAxAACQllJicKAEoDABAACQllJicKAEoDAAEAAwl7IOo5AKkAAAAA.',
Up='Uppercut:BAAALgAECgYJCAAAAA==.',
Us='Us:BAAALgAECgIJAgABLgAECgcJBwAGAAAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8hAAMnAAkJsg7GGgDIAQAnAAkJ4gvGGgDIAQAZAAMJTxqBoAD7AAAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8iAAIHAAgJ8AvYcQA7AQAHAAgJ8AvYcQA7AQAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8/AAQmAAkJQhO4FQB1AQAmAAkJahG4FQB1AQAWAAgJjAxZBQGuAAAfAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8ZAAIDAAgJCx/WEAA+AgADAAgJCx/WEAA+AgAAAA==.',
Vu='Vuori:BAAALgAECgEJAQAAAA==.',
Vy='Vyrric:BAABLgAECn82AAIXAAkJ4R+EBwAiAwAXAAkJ4R+EBwAiAwAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJGQAMAComAA==.',
Wh='Whitelove:BAABLgAECn8xAAMjAAkJexs2DACoAgAjAAkJexs2DACoAgASAAYJKRZUMABIAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgAECggJDgABLgAECgkJKAATABIYAA==.Whý:BAABLgAECn8XAAIaAAkJzgVaFQD8AAAaAAkJzgVaFQD8AAAAAA==.',
Wi='Wikm:BAAALgAFFAMJBAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAUJGAAWANIiAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn83AAIcAAkJChq0EgC0AgAcAAkJChq0EgC0AgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAITAAkJEhiECQAhAgATAAkJEhiECQAhAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIQAAgJLRglQgD6AQAQAAgJLRglQgD6AQAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8KAAMcAAMJuBcHSADHAAAcAAMJuBcHSADHAAAdAAMJOhdCMgC/AAAuAAQKfxUAAxwACAlBGaM9AIoBABwABQnHG6M9AIoBAB0ABwnrHCFNAPwAAAAA.Zmrr:BAAALgAECgUJCAABLgAFFAMJCgAcALgXAA==.',
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
