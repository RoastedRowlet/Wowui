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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Unknown-Unknown','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Guardian','Druid-Restoration','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','Warrior-Arms','DeathKnight-Unholy','Paladin-Protection','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abomination:BAABLgAECn8aAAIBAAcJjQMTLAClAAABAAcJjQMTLAClAAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUBwknAAEAPCYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgUJCgAAAA==.Adina:BAAALgAFFAEJAQAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAEAAAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.Alindril:BAAALgAECgcJBwAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAMJAwAEAAAAAA==.',
As='Ashfallen:BAAALgAECgYJDAAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8FAAIFAAIJOBtYKAClAAAFAAIJOBtYKAClAAAuAAQKfygAAgUACAmxH5oLAGgCAAUACAmxH5oLAGgCAAAA.',
Au='Audric:BAABLgAECn8gAAIGAAgJOgxDIwBYAQAGAAgJOgxDIwBYAQAAAA==.Auryx:BAAALgADCgUJBwAAAA==.',
Az='Azrel:BAAALgAECggJCAAAAA==.',
Ba='Baddragon:BAACLgAFFH8SAAQHAAUJ5B6NAQBkAQAHAAUJ9ByNAQBkAQAIAAQJ4BqJDgAZAQAJAAEJzweNHwBJAAAuAAQKfyIABAcACAlFJUgKADoCAAgABgmPJXYQAHECAAcABwkBHEgKADoCAAkAAQk0CZRJAC8AAAAA.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8WAAIKAAYJKiY/AAAnAgAKAAYJKiY/AAAnAgAuAAQKfzEAAwoACQnwJhQAAAUEAAoACQnwJhQAAAUEAAsABwlcJKYEAHMCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAAALgAECgkJEQAAAA==.Bayleef:BAABLgAECn8qAAIMAAkJKxsZFABkAgAMAAkJKxsZFABkAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgADCgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAFFAMJBQANAHAFAA==.Beldr:BAAALgAECggJDgAAAA==.Benito:BAABLgAECn8VAAIFAAYJzg6hNwAYAQAFAAYJzg6hNwAYAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgADCgEJAQAAAA==.Brujochingon:BAABLgAECn8XAAMNAAkJ7AofQwCTAQANAAkJ7AofQwCTAQAOAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8FAAIPAAMJwwtNDgDeAAAPAAMJwwtNDgDeAAAuAAQKfyoAAg8ACQnlHPUHAOQCAA8ACQnlHPUHAOQCAAAA.',
Ca='Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgMJAwABLgAECgUJDwAEAAAAAA==.Cheetoh:BAAALgADCgYJBgABLgAFFAUJGQADANsaAA==.Chiz:BAABLgAECn8XAAIQAAYJPRn/iQC+AQAQAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8FAAINAAMJcAWgXADAAAANAAMJcAWgXADAAAAuAAQKfyIAAg0ACAkqFh0yANEBAA0ACAkqFh0yANEBAAAA.',
Co='Conall:BAACLgAFFH8HAAIRAAMJ0AeMRQDbAAARAAMJ0AeMRQDbAAAuAAQKfzIAAhEACQmyGKYkACoCABEACQmyGKYkACoCAAAA.Confetti:BAAALgAECgYJEQAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgQJBAAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgQJBAAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgADCgcJDAABLgAECgYJDgAEAAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJAwAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCAAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAEAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMDAAYJZgxzMgDrAAADAAYJZgxzMgDrAAASAAYJdwbjQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMSAAkJwA94JACPAQASAAkJwA94JACPAQADAAcJcxLWJQAxAQAAAA==.Doñagladys:BAAALgAECgEJAQAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAQAAAA==.Dragonsloot:BAACLgAFFH8QAAMIAAUJmRE2HAAhAQAIAAUJmRE2HAAhAQAJAAIJVwF/HQBmAAAuAAQKfzMABAgACQm1GmkOADMCAAgACQm1GmkOADMCAAkABwl9Bc8XAAgBAAcAAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAAALgAECgQJDAAAAA==.Drubeastin:BAABLgAECn8WAAITAAgJXRc7NwDRAQATAAgJXRc7NwDRAQAAAA==.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dó']='Dónkey:BAAALgADCgcJDwAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgADCggJDAAAAA==.Elementtamer:BAAALgADCgIJAgAAAA==.',
Er='Erza:BAAALgAECgcJDAAAAA==.',
Es='Esh:BAABLgAECn8eAAMNAAgJxCEKJwB1AgANAAYJwiMKJwB1AgAUAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgADCgEJAQAAAA==.Evilemt:BAAALgAECgEJAgAAAA==.Evilmt:BAAALgADCgEJBAAAAA==.',
Fa='Fappio:BAAALgAECgMJBAABLgAECggJJwAJAGQjAA==.Faîth:BAAALgAECgUJCAABLgAECgkJIwAQANwdAA==.',
Fl='Flamesshadow:BAAALgAECgUJBQAAAA==.',
Fo='Forgiven:BAACLgAFFH8JAAIVAAUJdiAmFgB6AQAVAAUJdiAmFgB6AQAuAAQKfyMAAhUACAl1IugLAK0CABUACAl1IugLAK0CAAAA.',
Fr='Frogsbreath:BAAALgAECgYJBwAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgADCgEJAQAAAA==.',
Ga='Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgcJCAAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgADCggJCQAAAA==.Gullveig:BAABLgAECn8WAAIRAAcJQxfFXgBpAQARAAcJQxfFXgBpAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAAALgAECgYJCwABLgAECgkJHgAPADAVAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8bAAIQAAcJRhKEbQBgAQAQAAcJRhKEbQBgAQAAAA==.Hellmagi:BAAALgAECgcJDgAAAA==.Helmon:BAAALgAECgYJCAAAAA==.Hexson:BAABLgAECn8XAAQNAAgJrBIRbQCHAQANAAgJrBIRbQCHAQAUAAQJSw0tUQB6AAAOAAEJ0QmjJQA2AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMWAAcJJhAkQACAAQAWAAcJJhAkQACAAQAXAAMJ8B2/QgDQAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8fAAIRAAgJ/SNzAADPAgARAAgJ/SNzAADPAgAuAAQKfyIAAhEACAl1Ji0FAHoDABEACAl1Ji0FAHoDAAAA.Hordeforsure:BAABLgAECn8UAAMYAAYJLh6vMACxAQAYAAYJGh6vMACxAQATAAEJbiAQuABTAAABLgAFFAgJHwARAP0jAA==.Hornfu:BAAALgAECgYJEAAAAA==.',
Hu='Hugemistake:BAAALgAECgQJBQABLgAFFAMJBwARACogAA==.Humanwolf:BAAALgAECgEJAgAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Inovar:BAACLgAFFH8LAAINAAMJEiDvQAAHAQANAAMJEiDvQAAHAQAuAAQKfy0AAg0ACQn9IeoKAMgCAA0ACQn9IeoKAMgCAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAUJGQADANsaAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAMJBwARACogAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAABLgAECn8YAAIZAAYJJhb3KAB3AQAZAAYJJhb3KAB3AQABLgAFFAQJCwAZAMUUAA==.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAABLgAECn8eAAMPAAkJMBUQDAADAgAPAAkJMBUQDAADAgAaAAMJTgSaIwBlAAAAAA==.Kangarooz:BAAALgAECgUJCgAAAA==.Karlthuzad:BAAALgAECgQJBQAAAA==.Katrint:BAABLgAECn8eAAMbAAgJDyQdDgD2AQAbAAgJDyQdDgD2AQAcAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8VAAMdAAUJrSP1AgDcAQAdAAUJrSP1AgDcAQAGAAEJPg3CFABRAAAuAAQKfxoAAh0ACAmhHkYQAGMCAB0ACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAQJBwAQAIoFAA==.Kiramouse:BAABLgAFFH8SAAMNAAQJuBpfIgD7AAANAAMJABlfIgD7AAAUAAEJ3R+gEQBdAAAAAA==.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAUJGQADANsaAA==.',
Ky='Kyrié:BAABLgAECn8eAAIdAAYJgCHAHgDqAQAdAAYJgCHAHgDqAQAAAA==.',
La='Lanzadora:BAAALgAECgQJBgAAAA==.Lasinak:BAAALgAECgMJAwABLgAECgkJHgAPADAVAA==.',
Le='Leiya:BAAALgAECgQJCAAAAA==.',
Li='Liability:BAABLgAECn8uAAIeAAkJ+QS0GgASAQAeAAkJ+QS0GgASAQAAAA==.Linez:BAAALgADCgQJBAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8IAAITAAMJvhPdMwDxAAATAAMJvhPdMwDxAAAuAAQKfzIAAhMACAlwI0MLALgCABMACAlwI0MLALgCAAAA.',
Ma='Magital:BAAALgADCgcJCwABLgAFFAUJEAAIAJkRAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAAALgAECgcJDQAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgARANsVAA==.',
Mc='Mctowservan:BAAALgAECgEJAQAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgEJAQAAAA==.Melara:BAAALgAECgEJAQAAAA==.Meowmeowmeow:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIfAAkJXxkLBAAkAgAfAAkJXxkLBAAkAgAAAA==.Mikeoxlongg:BAAALgAECggJCQAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJDAAEAAAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgMJBQAAAA==.',
['Mî']='Mîsfire:BAAALgADCgEJAQABLgAECggJFwARACsVAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECggJGwAVAPALAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn8/AAIMAAkJHSHLBAA+AwAMAAkJHSHLBAA+AwAAAA==.',
Ne='Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBQAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nopandaloons:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Nosfyrakktu:BAAALgADCgcJDAABLgAECgcJIgASACoXAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIgAAMJ5hi0BAACAQAgAAMJ5hi0BAACAQABLgAFFAYJFgAKAComAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgQJBgABLgAECgUJCAAEAAAAAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECggJDwAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAEAAAAAA==.',
Pr='Profitt:BAABLgAECn8nAAIQAAkJQR6iGACNAgAQAAkJQR6iGACNAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECgcJBwAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8HAAIRAAMJKiD7LAAiAQARAAMJKiD7LAAiAQAuAAQKfzQAAhEACQn3JOsCAEkDABEACQn3JOsCAEkDAAAA.Quâsar:BAAALgAECggJCQABLgAECgkJIwAQANwdAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECgYJEwAEAAAAAA==.Rabbidlight:BAAALgAECgYJEwAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgUJBgAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8hAAIRAAgJDBnoPADIAQARAAgJDBnoPADIAQAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAEAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJEQAAAA==.Satoru:BAAALgAECgEJAQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAgJJQANAKEbAA==.',
Se='Segen:BAAALgAECgUJEQAAAA==.Semip:BAABLgAECn8UAAITAAYJHQeIegDqAAATAAYJHQeIegDqAAAAAA==.Sen:BAABLgAECn8rAAQTAAgJXSRbDQChAgATAAgJDCNbDQChAgAYAAYJ6iFEJAAGAgAhAAIJDxXPOgB+AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAEAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8UAAMCAAcJjgZ+RwClAAACAAcJCwN+RwClAAADAAQJ/AcwXgCYAAABLgAECgkJHgAPADAVAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgEJAgAAAA==.Shîver:BAABLgAECn8jAAIQAAkJ3B2qKQDMAgAQAAkJ3B2qKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8ZAAIDAAUJ2xo3CABLAQADAAUJ2xo3CABLAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGCEaAJcBAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAEAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sm='Smilepally:BAAALgAECgIJAgAAAA==.',
Sn='Snipedyou:BAAALgAECgEJAQAAAA==.Snomed:BAABLgAFFH8JAAIOAAMJ9B/WAADaAAAOAAMJ9B/WAADaAAABLgAFFAYJFgAKAComAA==.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8iAAISAAcJKhcQHAC8AQASAAcJKhcQHAC8AQAAAA==.',
St='Stantic:BAACLgAFFH8MAAQTAAYJbAeZDQDvAAATAAQJjQuZDQDvAAAYAAMJJQFQIwBjAAAhAAEJHAJxJABFAAAuAAQKfx0AAxMACAmgHzogAEQCABMACAnBGzogAEQCABgABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDQABLgAFFAMJBQANAHAFAA==.Stevethuzad:BAAALgAECgQJBQAAAA==.Stormydaniel:BAAALgAECggJDQAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAECgcJBwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIVAAkJAh1eEwBnAgAVAAkJAh1eEwBnAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAECgcJCwAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8FAAIBAAMJwxxpDwATAQABAAMJwxxpDwATAQAuAAQKfxkAAgEACAmMIN8JACICAAEACAmMIN8JACICAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAEAAAAAA==.Trigodun:BAABLgAECn8iAAMFAAgJzBc8JAA1AgAFAAgJ6hQ8JAA1AgAiAAIJcRN8OgBwAAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAVAAIdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgQJCQAAAA==.',
Un='Undedagaindk:BAACLgAFFH8dAAIjAAcJVR4KBABEAgAjAAcJVR4KBABEAgAuAAQKfyIAAyMACQliJicKAEoDACMACQliJicKAEoDAAEAAgl7INEpALMAAAAA.',
Up='Uppercut:BAAALgAECgIJAgAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAAALgAECgcJDwAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8bAAIVAAgJ8AubUwA6AQAVAAgJ8AubUwA6AQAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8wAAQkAAkJ3xJWEABmAQAkAAkJ4BBWEABmAQARAAQJ5g452wDWAAAZAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8XAAIDAAgJxR3aDgAMAgADAAgJxR3aDgAMAgAAAA==.',
Vy='Vyrric:BAABLgAECn8cAAISAAkJwB03BgDoAgASAAkJwB03BgDoAgAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJFgAKAComAA==.',
Wh='Whitelove:BAABLgAECn8xAAMlAAkJehvuBgDDAgAlAAkJehvuBgDDAgAdAAYJKRYHJABbAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgADCgEJAQABLgAECggJJQAmAH4XAA==.Whý:BAAALgAECggJDgAAAA==.',
Wi='Wikm:BAAALgAECgQJCAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEQAAAA==.',
Xa='Xalithrya:BAAALgAECgUJDAABLgAFFAMJBwARACogAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8hAAIWAAgJNRqcEQBvAgAWAAgJNRqcEQBvAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgADCgEJAQAAAA==.',
Za='Zapey:BAABLgAECn8lAAImAAgJfhfICADQAQAmAAgJfhfICADQAQAAAA==.',
Ze='Zem:BAAALgAECgYJBgAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8GAAMWAAMJThWTLQDNAAAWAAMJThWTLQDNAAAXAAEJuRiuMgBSAAAuAAQKfxUAAxYACAlBGaM9AIoBABYABQnHG6M9AIoBABcABwnrHPQ1AAcBAAAA.Zmrr:BAAALgADCgIJAgABLgAFFAMJBgAWAE4VAA==.',
Zo='Zoomies:BAAALgAECgYJBwABLgAECggJJwAJAGQjAA==.',
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
