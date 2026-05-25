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

local lookup = {'DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Mage-Fire','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Guardian','DeathKnight-Unholy','Druid-Restoration','Priest-Holy','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','Warrior-Arms','Paladin-Protection','Priest-Discipline',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abomination:BAABLgAECn8jAAIBAAgJkgOOLgC6AAABAAgJkgOOLgC6AAAAAA==.',
Ad='Addison:BAACLgAFFH8GAAICAAUJhCIXBwBiAQACAAUJhCIXBwBiAQAuAAQKfxYAAwIABwlGJl8MAMkCAAIABwlGJl8MAMkCAAMAAQmaFUZ1AEEAAAEuAAUUCAkoAAEAMSYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgUJDwAAAA==.Adina:BAABLgAECn8TAAMEAAcJUwju4wAtAQAEAAcJUwju4wAtAQAFAAIJCwHQDgA+AAAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAGAAAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.Alindril:BAAALgAECgcJBwABLgAECgkJIwAHAAMdAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAQJBwAIABgJAA==.',
As='Ashfallen:BAAALgAECgYJDwAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAACLgAFFH8IAAIJAAMJkheYJADrAAAJAAMJkheYJADrAAAuAAQKfysAAgkACQkBIM8HAMQCAAkACQkBIM8HAMQCAAAA.',
Au='Audric:BAABLgAECn8gAAIKAAgJOQwlKQBeAQAKAAgJOQwlKQBeAQAAAA==.Auryx:BAAALgAECgQJAwAAAA==.',
Az='Azrel:BAAALgAECggJDAAAAA==.',
Ba='Babyoils:BAAALgADCgEJAQAAAA==.Baddragon:BAACLgAFFH8TAAQLAAUJNCEeAgBYAQALAAUJ9BweAgBYAQAMAAQJNCGJDgAZAQANAAEJzwf3IwBFAAAuAAQKfyIABAsACAlFJUgKADoCAAwABgmPJXYQAHECAAsABwkBHEgKADoCAA0AAQk0CZRJAC8AAAAA.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8WAAIOAAYJKiaKAAASAgAOAAYJKiaKAAASAgAuAAQKfzEAAw4ACQnwJhQAAAUEAA4ACQnwJhQAAAUEAA8ABwlbJPwFAHECAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAABLgAECn8aAAIQAAkJMxQ9MQAWAgAQAAkJMxQ9MQAWAgAAAA==.Bayleef:BAABLgAECn8vAAIRAAkJXx3MCwDlAgARAAkJXx3MCwDlAgAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgAECgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAFFAMJCAAIAKQRAA==.Beldr:BAABLgAECn8WAAISAAgJ9w7iKQBUAQASAAgJ9w7iKQBUAQAAAA==.Benito:BAABLgAECn8VAAIJAAYJzg6cQgARAQAJAAYJzg6cQgARAQAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brexxle:BAAALgAECgYJBgABLgAECgkJKAATABIYAA==.Britterz:BAAALgADCgIJAgAAAA==.Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgAECgYJBgAAAA==.Brujochingon:BAABLgAECn8XAAMIAAkJ3QoaTwCXAQAIAAkJ3QoaTwCXAQAUAAEJ3gOkNgAqAAAAAA==.Brèè:BAACLgAFFH8IAAIVAAQJ9g7RCwAjAQAVAAQJ9g7RCwAjAQAuAAQKfzAAAhUACQn+HPUHAOQCABUACQn+HPUHAOQCAAAA.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.Cereniaa:BAAALgAECgEJAQAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgUJBwABLgAECgYJFgAPANAQAA==.Cheetoh:BAAALgAFFAEJAQABLgAFFAUJHgADANwaAA==.Chiz:BAABLgAECn8XAAIEAAYJPRn/iQC+AQAEAAYJPRn/iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAACLgAFFH8IAAIIAAMJpBFRWwDhAAAIAAMJpBFRWwDhAAAuAAQKfyMAAggACAnhGMAzAPIBAAgACAnhGMAzAPIBAAAA.',
Co='Conall:BAACLgAFFH8KAAIWAAMJ0xEtSwDsAAAWAAMJ0xEtSwDsAAAuAAQKfzMAAhYACQm5GIQvACECABYACQm5GIQvACECAAAA.Confetti:BAAALgAECgYJEgAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJFgAAAA==.',
Cr='Croissants:BAAALgAECgYJDgAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Cy='Cynical:BAAALgAECgEJAQAAAA==.',
Da='Dajova:BAAALgAECgYJBgAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgAECgEJAgABLgAECgYJDwAGAAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJAwAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgYJCAAAAA==.Dermo:BAAALgAECgIJAgAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAGAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMDAAYJZgxLPQDdAAADAAYJZgxLPQDdAAAXAAYJdwbjQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8qAAMXAAkJwA94JACPAQAXAAkJwA94JACPAQADAAcJcxL8LgAjAQAAAA==.Doñagladys:BAAALgAECgUJCAAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAgAAAA==.Dragonsloot:BAACLgAFFH8VAAMMAAUJmRHOIQAVAQAMAAUJmRHOIQAVAQANAAMJbgF7HQCPAAAuAAQKfzYABAwACQm1GowPAE8CAAwACQm1GowPAE8CAA0ABwleB7sZABYBAAsAAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAAALgAECgUJEAAAAA==.Drubeastin:BAABLgAECn8lAAIYAAkJCh1nEQCdAgAYAAkJCh1nEQCdAgAAAA==.Druidia:BAAALgADCggJCQAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dó']='Dónkey:BAAALgADCgcJFQAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Eb='Ebot:BAAALgAECgEJAQAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgAECgMJBgAAAA==.Elementtamer:BAAALgADCgIJAgAAAA==.',
Er='Erza:BAAALgAECgcJDQAAAA==.',
Es='Esh:BAABLgAECn8iAAMIAAkJeiONFwB+AgAIAAcJbiWNFwB+AgAZAAQJSRlfIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgAECgEJAQAAAA==.Evilemt:BAAALgAECgEJAwAAAA==.Evilmt:BAAALgAECgEJAgAAAA==.',
Fa='Fappio:BAAALgAECgMJBAABLgAECggJLQANAFokAA==.Faîth:BAABLgAECn8YAAQHAAkJeQ+tQQChAQAHAAkJig2tQQChAQAVAAQJyhCoOACdAAAaAAMJIAZDIABqAAABLgAECgkJJQAEAN8dAA==.',
Fl='Flamesshadow:BAAALgAECgcJDAAAAA==.',
Fo='Forgiven:BAACLgAFFH8KAAIHAAUJdiCfHwBrAQAHAAUJdiCfHwBrAQAuAAQKfyMAAgcACAl1IukPAKgCAAcACAl1IukPAKgCAAAA.Forlath:BAAALgAECggJCAAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJBwAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgADCgEJAQAAAA==.',
Ga='Gabarra:BAAALgAECgYJBgAAAA==.Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Gamõn:BAAALgAECgMJBQAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgcJCAAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgAECgEJAQAAAA==.Gullveig:BAABLgAECn8WAAIWAAcJQxfCdgBgAQAWAAcJQxfCdgBgAQAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAAALgAECgcJEgABLgAECgkJJwAVAF8cAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8kAAIEAAkJpRRbOAAbAgAEAAkJpRRbOAAbAgAAAA==.Heide:BAAALgAECgEJAQAAAA==.Hellmagi:BAAALgAECgcJDgAAAA==.Helmon:BAAALgAECgYJCAAAAA==.Hexson:BAABLgAECn8XAAQIAAgJrhIRbQCHAQAIAAgJrhIRbQCHAQAZAAQJSw0tUQB6AAAUAAEJ0QlyMAA1AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMbAAcJJhAkQACAAQAbAAcJJhAkQACAAQAcAAMJ8B2zTwDIAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8fAAIWAAgJ/SMqAQC2AgAWAAgJ/SMqAQC2AgAuAAQKfyIAAhYACAl1Ji0FAHoDABYACAl1Ji0FAHoDAAAA.Hordeforsure:BAABLgAECn8UAAMdAAYJLh6vMACxAQAdAAYJGh6vMACxAQAYAAEJbiAQuABTAAABLgAFFAgJHwAWAP0jAA==.Hornfu:BAAALgAECgYJEAAAAA==.',
Hu='Hugemistake:BAAALgAECggJDQABLgAFFAMJCgAWAKohAA==.Humanwolf:BAAALgAECgQJBgAAAA==.',
Ik='Ikelbunk:BAAALgADCgIJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Incuntroll:BAAALgAECgUJBQAAAA==.Inovar:BAACLgAFFH8OAAIIAAQJBSFeIAB+AQAIAAQJBSFeIAB+AQAuAAQKfy0AAggACQn9IeoOAL0CAAgACQn9IeoOAL0CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAUJHgADANwaAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAFFAMJCgAWAKohAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAABLgAECn8gAAIeAAcJzhUCJAC/AQAeAAcJzhUCJAC/AQABLgAFFAQJDAAeABYYAA==.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAABLgAECn8nAAMVAAkJXxzNBgCeAgAVAAkJXxzNBgCeAgAaAAMJTgSaIwBlAAAAAA==.Kangarooz:BAAALgAECgUJCgAAAA==.Karaseh:BAAALgADCgkJCQAAAA==.Karlthuzad:BAAALgAECgQJBQAAAA==.Katrint:BAABLgAECn8iAAMfAAgJECR5EQD4AQAfAAgJECR5EQD4AQAgAAMJ3BuEFQCiAAAAAA==.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8ZAAMSAAUJbCRwAwD2AQASAAUJbCRwAwD2AQAKAAEJPg3CFABRAAAuAAQKfxoAAhIACAmhHkYQAGMCABIACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAUJDgAQADgRAA==.Kiramouse:BAACLgAFFH8VAAMIAAQJuBpfIgD7AAAIAAMJABlfIgD7AAAZAAEJ3R9REQBdAAAuAAQKfxcAAwgACAnIIhkQALQCAAgABwmqIhkQALQCABkAAgk3I/kkAGgAAAAA.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAUJHgADANwaAA==.',
Ky='Kyrié:BAABLgAECn8kAAISAAYJgCHHFgDzAQASAAYJgCHHFgDzAQAAAA==.',
La='Lanzadora:BAAALgAECgQJCgAAAA==.Lasinak:BAAALgAECgQJBwABLgAECgkJJwAVAF8cAA==.',
Le='Legòlas:BAAALgAECgEJAQAAAA==.Leiya:BAAALgAECgQJCQAAAA==.Leto:BAAALgADCgcJCAABLgAECgcJIgAXACoXAA==.',
Li='Liability:BAABLgAECn8zAAIhAAkJ1AU1HgAZAQAhAAkJ1AU1HgAZAQAAAA==.Linez:BAAALgADCgQJBAAAAA==.Lithiel:BAAALgAECggJCAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8LAAIYAAMJBh9vMwAWAQAYAAMJBh9vMwAWAQAuAAQKfzoAAhgACAlTI7EPAKwCABgACAlTI7EPAKwCAAAA.',
Ma='Magital:BAAALgAECgQJBAABLgAFFAUJFQAMAJkRAA==.Mailfurion:BAAALgADCgMJAwAAAA==.Makisan:BAAALgAECgcJDQAAAA==.Malassiery:BAAALgADCgcJBwAAAA==.Malis:BAAALgAECgcJDQABLgAECgkJGgAWANsVAA==.',
Mc='Mctowservan:BAAALgAECgEJAQAAAA==.Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgIJAwAAAA==.Melara:BAAALgAECgEJAQAAAA==.Menethel:BAAALgAECgMJAwABLgAECgQJBQAGAAAAAA==.Meowmeowmeow:BAAALgAECgcJEgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8qAAIiAAkJXxnsBQAOAgAiAAkJXxnsBQAOAgAAAA==.Mikeoxlongg:BAAALgAECggJDAAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Missfaery:BAAALgAECgEJAQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJDAAGAAAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgQJBwAAAA==.',
['Mî']='Mîsfire:BAAALgADCgEJAQAAAA==.',
Na='Naianasha:BAAALgAECgYJBwABLgAECggJIAAHAPALAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn9IAAIRAAkJHSEnBgA9AwARAAkJHSEnBgA9AwAAAA==.',
Ne='Nenizaurio:BAAALgAECgYJCwAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBgAAAA==.Noma:BAAALgADCgEJAQAAAA==.Nopants:BAAALgAECgEJAgABLgAECgYJDAAGAAAAAA==.Nosfyrakktu:BAAALgAECgUJBQABLgAECgcJIgAXACoXAA==.',
Nu='Nuxo:BAAALgAECgMJBQAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIjAAMJ5hgaAQDkAAAjAAMJ5hgaAQDkAAABLgAFFAYJFgAOAComAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgQJBgABLgAECgUJCAAGAAAAAA==.Pahine:BAAALgAECgUJBQABLgAECgkJJwAVAF8cAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.Pepedin:BAAALgAFFAEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECgkJEAAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.',
Pr='Profitt:BAABLgAECn8vAAIEAAkJkyAcDwDqAgAEAAkJkyAcDwDqAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qo='Qoheleth:BAAALgAECggJDwAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAACLgAFFH8KAAIWAAMJqiH+MQArAQAWAAMJqiH+MQArAQAuAAQKfzQAAhYACQn4JLgEAD8DABYACQn4JLgEAD8DAAAA.Quâsar:BAAALgAECggJCgABLgAECgkJJQAEAN8dAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQABLgAECggJFgAWAMIdAA==.Rabbidlight:BAABLgAECn8WAAMWAAgJwh3VZgCyAQAWAAcJwxzVZgCyAQAeAAYJRg5nVQCzAAAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgUJBgAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8hAAIWAAgJDBnoSQDKAQAWAAgJDBnoSQDKAQAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAGAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJEQAAAA==.Satoru:BAAALgAECgEJAQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAgJJQAIAKEbAA==.',
Se='Segen:BAABLgAECn8VAAIEAAUJGRMZugD2AAAEAAUJGRMZugD2AAAAAA==.Semip:BAABLgAECn8ZAAIYAAYJWgfCjgDvAAAYAAYJWgfCjgDvAAAAAA==.Sen:BAABLgAECn8wAAQYAAkJLSMQCwDZAgAYAAkJ8SEQCwDZAgAdAAcJ7h6ZCwCIAQAkAAIJDxXJQwB+AAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAGAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAABLgAECn8UAAMCAAcJjgZmUQChAAACAAcJCwNmUQChAAADAAQJ/AcwXgCYAAABLgAECgkJJwAVAF8cAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgMJBAAAAA==.Shîver:BAABLgAECn8lAAIEAAkJ3x2qKQDMAgAEAAkJ3x2qKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8eAAIDAAUJ3BoPCwBFAQADAAUJ3BoPCwBFAQAuAAQKfy8AAwMACQlHHbIHAAADAAMACQkDHbIHAAADAAIABwkfGEEfAI0BAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAGAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sm='Smilepally:BAAALgAECgUJBQAAAA==.',
Sn='Snipedyou:BAAALgAECgEJAQAAAA==.Snomed:BAACLgAFFH8JAAIUAAMJ9B/WAADaAAAUAAMJ9B/WAADaAAAuAAQKfxcAAhQACAluImYCAJoCABQACAluImYCAJoCAAEuAAUUBgkWAA4AKiYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8iAAIXAAcJKhf+IgDAAQAXAAcJKhf+IgDAAQAAAA==.',
St='Stantic:BAACLgAFFH8MAAQYAAYJbAeZDQDvAAAYAAQJjQuZDQDvAAAdAAMJJQFQIwBjAAAkAAEJHALfKgA+AAAuAAQKfx0AAxgACAmgHzogAEQCABgACAnBGzogAEQCAB0ABwmeGxAiABUCAAAA.Statuskwo:BAAALgAECgcJDQABLgAFFAMJCAAIAKQRAA==.Stevethuzad:BAAALgAECgQJBQAAAA==.Stormydaniel:BAABLgAECn8VAAMbAAgJAgnqTwA8AQAbAAgJAgnqTwA8AQAcAAQJ+gGldgBTAAAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8jAAIHAAkJAx2tGABkAgAHAAkJAx2tGABkAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Threeofseven:BAAALgAECgEJAQAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAECgcJCwAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAACLgAFFH8IAAIBAAMJeR0gEwARAQABAAMJeR0gEwARAQAuAAQKfxoAAgEACAmMIGELAF0CAAEACAmMIGELAF0CAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAGAAAAAA==.Trigodun:BAABLgAECn8iAAMJAAgJzRc8JAA1AgAJAAgJ6hQ8JAA1AgAlAAIJdBNgRgB1AAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Ts='Tsumugi:BAAALgADCgEJAQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECgkJIwAHAAMdAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgYJDwAAAA==.',
Un='Undedagaindk:BAACLgAFFH8iAAIQAAgJAh3MAQDEAgAQAAgJAh3MAQDEAgAuAAQKfyUAAxAACQllJicKAEoDABAACQllJicKAEoDAAEAAwl7IKswAK0AAAAA.',
Up='Uppercut:BAAALgAECgIJAgAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAABLgAECn8XAAIkAAkJpAaSHQCRAQAkAAkJpAaSHQCRAQAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAABLgAECn8gAAIHAAgJ8At4YABEAQAHAAgJ8At4YABEAQAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn85AAQmAAkJ3xLaEQB7AQAmAAkJBhHaEQB7AQAWAAQJ5g452wDWAAAeAAEJ7QEnoQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8YAAIDAAgJxR4AEAAkAgADAAgJxR4AEAAkAgAAAA==.',
Vy='Vyrric:BAABLgAECn8lAAIXAAkJ4R+GBQAjAwAXAAkJ4R+GBQAjAwAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAYJFgAOAComAA==.',
Wh='Whitelove:BAABLgAECn8xAAMnAAkJexsACQC8AgAnAAkJexsACQC8AgASAAYJKRbtKQBUAQAAAA==.Whitest:BAAALgAECgcJEgAAAA==.Whixx:BAAALgADCgYJBwABLgAECgkJKAATABIYAA==.Whý:BAABLgAECn8WAAIZAAgJhQVdFADeAAAZAAgJhQVdFADeAAAAAA==.',
Wi='Wikm:BAAALgAFFAMJAwAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJEAAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgAECgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEgAAAA==.',
Xa='Xalithrya:BAAALgAECgYJEQABLgAFFAMJCgAWAKohAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8pAAIbAAgJkxtRFQBzAgAbAAgJkxtRFQBzAgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgAECgYJBgAAAA==.',
Za='Zapey:BAABLgAECn8oAAITAAkJEhgbBwAuAgATAAkJEhgbBwAuAgAAAA==.',
Ze='Zem:BAAALgAECggJDgAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8JAAMcAAMJWxdsIwDgAAAcAAMJWxdsIwDgAAAbAAMJuBcTNADcAAAuAAQKfxUAAxsACAlBGaM9AIoBABsABQnHG6M9AIoBABwABwnrHBlBAP8AAAAA.Zmrr:BAAALgADCgIJAgABLgAFFAMJCQAcAFsXAA==.',
Zo='Zoomies:BAAALgAECgYJCgABLgAECggJLQANAFokAA==.',
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
