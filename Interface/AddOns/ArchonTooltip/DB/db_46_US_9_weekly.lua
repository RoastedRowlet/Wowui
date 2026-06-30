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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Warlock-Affliction','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Evoker-Augmentation','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abbierose:BAAALgADCgUJBQAAAA==.Abyssia:BAABLgAECn8VAAIBAAcJRBrISACsAQABAAcJRBrISACsAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8wAAICAAgJtBR5AwApAQACAAgJtBR5AwApAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.Aethenadawn:BAAALgAECgEJAQAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECggJDQAAAA==.Alcha:BAABLgAECn8pAAMDAAkJGx2MKQA1AgADAAkJbRqMKQA1AgAEAAcJoBrXCgCVAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgkJKQADABsdAA==.Alenndar:BAABLgAECn8oAAIFAAkJ1RL6KAALAgAFAAkJ1RL6KAALAgAAAA==.Alexdaddario:BAACLgAFFH8KAAIGAAMJkhfWLADXAAAGAAMJkhfWLADXAAAuAAQKfyEAAwYABglAIjUhAL8BAAYABglAIjUhAL8BAAcAAgniCBRtAD0AAAAA.Alkuhh:BAAALgADCgcJDgABLgAECgkJKQADABsdAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexNXbQCgAQAIAAgJexNXbQCgAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8XAAMKAAgJQRJ+EQCyAQAKAAcJrhJ+EQCyAQALAAIJSgp1HgBcAAABLgAECgkJLQACAO8cAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn84AAIMAAkJUCVRAgDfAgAMAAkJUCVRAgDfAgAAAA==.Annalease:BAAALgAECgMJBgAAAA==.Anticlimax:BAABLgAECn8sAAMBAAkJoRJCQADIAQABAAkJoRJCQADIAQAMAAEJTgaTPQAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJCwAAAA==.',
Ap='Apparition:BAACLgAFFH8IAAINAAMJPAbQOQCdAAANAAMJPAbQOQCdAAAuAAQKfyQAAw0ACQnDGOINAI8CAA0ACQnDGOINAI8CAA4ABQmVCtxwAGEAAAAA.Apprentice:BAACLgAFFH8YAAIIAAYJ+xvaLwCtAQAIAAYJ+xvaLwCtAQAuAAQKfy8AAggACAleJZsTAOQCAAgACAleJZsTAOQCAAAA.',
Ar='Arale:BAAALgADCgUJBgABLgAECgkJJgAPABoaAA==.Ardrhyes:BAAALgADCgYJBgABLgAECgkJNQADAO8SAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/EfQB8AQAIAAgJpw/EfQB8AQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.Artrael:BAABLgAFFH8KAAIQAAUJtgYyAwCdAAAQAAUJtgYyAwCdAAAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8QAAIRAAQJmx6wJABZAQARAAQJmx6wJABZAQAuAAQKfxwAAhEACQlKHWsWAGICABEACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgMJBAABLgAECgYJEQASAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8KAAIRAAMJkAi5XQCQAAARAAMJkAi5XQCQAAAuAAQKf0MAAxEACQn2FS0dAGMCABEACQn2FS0dAGMCABMABgndEA1GABsBAAAA.',
Av='Avdol:BAAALgAFFAEJAwABLgAFFAcJEQADAIEcAA==.Avienndha:BAABLgAECn82AAIMAAkJGR4kBgA3AgAMAAkJGR4kBgA3AgAAAA==.',
Aw='Awake:BAACLgAFFH8KAAIUAAMJxxF0JQC9AAAUAAMJxxF0JQC9AAAuAAQKfx4AAxQACQntG7UKAJgCABQACQntG7UKAJgCABUAAwnjDOdtAIsAAAAA.',
Az='Azgrunga:BAACLgAFFH8GAAIWAAMJkg9vOQDNAAAWAAMJkg9vOQDNAAAuAAQKfy8AAhYACQlVGg4dAGUCABYACQlVGg4dAGUCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwABLgAFFAEJAQASAAAAAA==.Benderbrod:BAAALgAFFAEJAQAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.Bestshaman:BAAALgAECgEJAQAAAA==.',
Bi='Bitcoin:BAAALgADCgQJBAAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8hAAIWAAcJpxt2OQDBAQAWAAcJpxt2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Bomburr:BAAALgAECgYJCQABLgAFFAcJFwAIAMUUAA==.Bonk:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8zAAIRAAkJJxuwEgC3AgARAAkJJxuwEgC3AgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIXAAkJkh8wBQDtAgAXAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8UAAIYAAUJwBTQCgALAQAYAAUJwBTQCgALAQAuAAQKfykAAhgACQlzIB4GAPoCABgACQlzIB4GAPoCAAAA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgAECgcJDAAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIRAAMJvRSTUwCqAAARAAMJvRSTUwCqAAAuAAQKfzMAAxEACAnmG7IpABYCABEACAnmG7IpABYCABMABglnGNFBACwBAAAA.Chayara:BAAALgAFFAMJAQAAAA==.Cheesebugga:BAAALgAECgUJBQAAAA==.Cheesefries:BAABLgAECn82AAMZAAkJ/x/2DQC+AgAZAAkJ/x/2DQC+AgAVAAYJ0R0OIACmAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhZZQQCMAQAFAAcJrhZZQQCMAQAAAA==.Cherub:BAAALgADCgEJAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMVAAkJDRcZHQC8AQAVAAYJQxoZHQC8AQAUAAcJaQt2QQD6AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.Chôpstixx:BAAALgAECgMJAwAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMZAAgJ3RHaOwCBAQAZAAgJ3RHaOwCBAQAUAAYJ1QWUXACjAAAAAA==.Clear:BAAALgADCggJCgAAAA==.',
Co='Cogglutch:BAAALgAECgQJBAABLgADCgcJBwASAAAAAA==.Cokegirll:BAABLgAECn8bAAIaAAgJJxL/UQCsAQAaAAgJJxL/UQCsAQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJKAAVAF4aAA==.Creamie:BAABLgAECn8oAAIVAAgJXhpIGADlAQAVAAgJXhpIGADlAQAAAA==.Creamish:BAABLgAECn8aAAIbAAgJlhUQDAAEAgAbAAgJlhUQDAAEAgABLgAECggJKAAVAF4aAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMcAAgJ3hTqJADfAQAcAAgJ3hTqJADfAQAdAAIJ9A64nQEuAAAAAA==.Crumbshot:BAAALgAFFAIJAgAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8PAAIIAAMJDxaiJgC4AAAIAAMJDxaiJgC4AAAuAAQKfxgAAwgACQkvD0VXANcBAAgACQkvD0VXANcBAAkAAwm/AwcTAFUAAAAA.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn81AAIHAAkJfhWADwDuAQAHAAkJfhWADwDuAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJNQAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIXAAgJEQ/pIQAgAQAXAAgJEQ/pIQAgAQAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgAECgEJAQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgUJBwABLgAFFAEJAQASAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8uAAMUAAgJIRh8GADuAQAUAAgJIRh8GADuAQAZAAcJGhhVKADnAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAFFAMJCAADAEYUAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCwAAAA==.Dill:BAABLgAECn9OAAIWAAkJniQSBAAmAwAWAAkJniQSBAAmAwAAAA==.Dimonds:BAAALgAECgMJBAAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJCQAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Dondeezy:BAAALgAECgEJAQAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgYJCgAAAA==.Dreadshade:BAAALgAECgYJBgAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgyBUQDIAAAGAAcJMgyBUQDIAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJCwASAAAAAA==.Dyabolykal:BAAALgAECgQJCAABLgAECgQJCwASAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIdAAkJKRJLawCYAQAdAAkJKRJLawCYAQABLgAFFAUJFAAYAMAUAA==.Elly:BAABLgAFFH8JAAIeAAMJ7QakLADLAAAeAAMJ7QakLADLAAAAAA==.Elsharion:BAABLgAECn8VAAMcAAgJ5B0GLACxAQAcAAgJ5B0GLACxAQAdAAQJKgtKIQGSAAABLgAFFAgJGwAZAP0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAgJGwAZAP0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAgJGwAZAP0gAA==.Elshie:BAACLgAFFH8bAAIZAAgJ/SB6BgCoAgAZAAgJ/SB6BgCoAgAuAAQKfxcAAhkACQlBHmENAH4CABkACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8IAAIfAAQJyxdLXAA7AQAfAAQJyxdLXAA7AQABLgAFFAcJEQADAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAACLgAFFH8KAAIFAAMJ1wr3DwCJAAAFAAMJ1wr3DwCJAAAuAAQKf0oAAgUACQkjG7oUAKQCAAUACQkjG7oUAKQCAAAA.Evermoreivy:BAAALgAECgMJAwAAAA==.',
Fa='Fanairus:BAAALgAECgkJCQAAAA==.Fastasheet:BAACLgAFFH8oAAIUAAkJExuOAAArAgAUAAkJExuOAAArAgAuAAQKfz4AAhQACQl5JhECAFEDABQACQl5JhECAFEDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgAECgEJAQABLgAFFAEJAQASAAAAAA==.Fill:BAABLgAECn8gAAIbAAgJfyTsBwBKAgAbAAgJfyTsBwBKAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flarestepper:BAAALgADCgQJBAAAAA==.Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAACLgAFFH8KAAIVAAMJ+AMDDQCTAAAVAAMJ+AMDDQCTAAAuAAQKfyUAAhUACAlVFQkgAKYBABUACAlVFQkgAKYBAAEuAAUUAwkMAAoAWSAA.',
Fo='Foboshi:BAAALgAECgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIcAAkJ0RfOJQDZAQAcAAkJ0RfOJQDZAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.Fuzzywuzzy:BAAALgAECgIJAgAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJGAAVABofAA==.',
Ga='Gainz:BAAALgAFFAMJAwAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8sAAMOAAkJGA2wAwAXAQAOAAkJGA2wAwAXAQANAAQJIQU/XACOAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAACLgAFFH8HAAIVAAMJ4SDyBwDpAAAVAAMJ4SDyBwDpAAAuAAQKfz8AAhUACQk+JpUAAHgDABUACQk+JpUAAHgDAAAA.Giliaa:BAAALgAECgcJBwAAAA==.Gilljoww:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.Gireigtulb:BAAALgAECgIJAgAAAA==.',
Gl='Glizzee:BAAALgAECgEJAQAAAA==.',
Gn='Gnz:BAAALgAFFAMJBAAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAcJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAYJGQAYAMcQAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halløw:BAAALgAECgQJBAAAAA==.Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgQJBQAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8KAAIWAAQJJwWNLwDyAAAWAAQJJwWNLwDyAAAuAAQKfzoAAhYACQkxFh4XADUCABYACQkxFh4XADUCAAAA.Hilazy:BAABLgAECn8aAAIbAAkJ7xkRDQDgAQAbAAkJ7xkRDQDgAQAAAA==.Hiping:BAAALgAECgYJDwAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8fAAMNAAkJqBRcFQAwAgANAAkJqBRcFQAwAgAOAAEJLAreiQAwAAAAAA==.Holysheet:BAABLgAFFH8GAAIdAAMJ6A+xdADKAAAdAAMJ6A+xdADKAAAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8qAAMFAAkJFxrBJwATAgAFAAcJeRrBJwATAgAGAAgJUBWvKQCGAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJGAAVABofAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAASAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQASAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8kAAIIAAkJrgfRhQBsAQAIAAkJrgfRhQBsAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8bAAIIAAgJpgW3qQArAQAIAAgJpgW3qQArAQAAAA==.Ihavenofutur:BAABLgAECn8UAAIIAAcJIgop4gDYAAAIAAcJIgop4gDYAAAAAA==.',
Il='Illari:BAAALgAECgYJEgAAAA==.Illidantwo:BAACLgAFFH8cAAIgAAcJZRjSAwDyAQAgAAcJZRjSAwDyAQAuAAQKfzEAAiAACQlDJBEEADoDACAACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIXAAgJPB2rDQAQAgAXAAgJPB2rDQAQAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAwAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8YAAIeAAkJgBOwFQDyAQAeAAkJgBOwFQDyAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAYJGwABAHAZAA==.Jabu:BAAALgAFFAIJBAABLgAFFAYJGwABAHAZAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiVOEQBfAgANAAYJLiVOEQBfAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8fAAIhAAkJNg3NFQBrAQAhAAkJNg3NFQBrAQAAAA==.Jeryeth:BAABLgAECn8yAAMiAAkJTiLJAgAVAwAiAAkJOyLJAgAVAwAXAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgcJCgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAABLgAFFH8FAAIjAAIJEB3CJACtAAAjAAIJEB3CJACtAAAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAECLgAFFH8pAAMQAAcJzR9ZAACbAgAQAAcJzR9ZAACbAgAdAAMJBhKMbADWAAAuAAQKfy8AAhAACAloJt0AAGgDABAACAloJt0AAGgDAAAA.Kanda:BAAALgAECgcJCAAAAA==.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAdAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Keiràe:BAAALgADCgYJBAAAAA==.Kelsí:BAAALgAECgkJEAAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgASAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQbG7wAgAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAaAF8aAA==.Kiwí:BAABLgAECn8dAAMJAAgJXR2rBgBSAQAIAAYJdBbHigBiAQAJAAUJDh2rBgBSAQAAAA==.',
Ko='Konen:BAAALgADCgEJAQABLgAECgkJKgAFABcaAA==.',
Kr='Krasavice:BAABLgAECn9FAAIaAAkJOiNmCAAXAwAaAAkJOiNmCAAXAwAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQASAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8zAAIaAAkJoxN2RgDOAQAaAAkJoxN2RgDOAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAhbSgAKAQABAAYJsAhbSgAKAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8lAAMdAAkJ7xluKgBXAgAdAAkJ7xluKgBXAgAcAAcJvRLKNQB5AQAAAA==.Lemurshoes:BAAALgAFFAEJAgAAAA==.Lena:BAABLgAECn8qAAIaAAkJ4COTDwDUAgAaAAkJ4COTDwDUAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Letsgomen:BAAALgAECgQJBAAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIfAAgJGB1qJACsAgAfAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgAECgEJAQASAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAACLgAFFH8GAAIRAAMJFhoOQQDhAAARAAMJFhoOQQDhAAAuAAQKfysAAhEACAmDImkQAM0CABEACAmDImkQAM0CAAAA.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAASAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJOgAYAAMlAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8GAAIhAAMJ+hMDDgDaAAAhAAMJ+hMDDgDaAAAuAAQKfzoAAiEACQmBHpAEALUCACEACQmBHpAEALUCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIkAAgJKgeDFgADAQAkAAgJKgeDFgADAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQADAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIdAAkJlSEJGwCiAgAdAAkJlSEJGwCiAgAAAA==.Mankirijilla:BAAALgAECgMJBQAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJEAARAJseAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIRAAcJTiHpHABlAgARAAcJTiHpHABlAgAAAA==.Maximus:BAABLgAECn8uAAIdAAkJ7w5wXwCyAQAdAAkJ7w5wXwCyAQAAAA==.Mayyflower:BAAALgAECgIJBAAAAA==.',
Me='Mechlil:BAAALgAECgIJBQAAAA==.Meditacoss:BAAALgAFFAEJAQAAAA==.Meelu:BAABLgAECn8WAAMFAAkJGgrLTQBXAQAFAAkJGgrLTQBXAQAGAAEJRQJyqAAXAAABLgAFFAUJFAAYAMAUAA==.Mellowlizard:BAABLgAFFH8RAAIDAAcJgRySCACfAQADAAcJgRySCACfAQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgASAAAAAA==.Metuss:BAABLgAECn8YAAMZAAgJgR9zFgBmAgAZAAgJgR9zFgBmAgAUAAYJ3A+PPwABAQAAAA==.',
Mi='Mira:BAABLgAECn8wAAIaAAgJihS8SQDEAQAaAAgJihS8SQDEAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgYJEAABLgAECgkJTQAUAIoiAA==.Mkicon:BAACLgAFFH8HAAIIAAMJqQgIiwDDAAAIAAMJqQgIiwDDAAAuAAQKfykAAggACAmzFRFzAJMBAAgACAmzFRFzAJMBAAAA.Mkultra:BAABLgAECn8nAAMfAAkJCSJFGAC1AgAfAAkJvh5FGAC1AgAlAAcJQx+7HAB0AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8tAAIfAAkJdBSPBAB7AQAfAAkJdBSPBAB7AQAAAA==.Mooganfreman:BAAALgAECgQJBAAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn83AAImAAkJIx1WAADEAQAmAAkJIx1WAADEAQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzANwjAA0AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAACLgAFFH8IAAIDAAMJRhSaFgDXAAADAAMJRhSaFgDXAAAuAAQKfzkAAwMACQkgH8UOANYCAAMACQkgH8UOANYCAAQAAgn/DblUAHAAAAAA.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8hAAMEAAkJHxqPAAA9AgAEAAYJCxiPAAA9AgADAAgJ3xg1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKgARAK4VAA==.Multanni:BAABLgAECn80AAITAAkJzRj0FwAkAgATAAkJzRj0FwAkAgAAAA==.',
My='Myonecrosis:BAABLgAECn8vAAMDAAkJwSF8FgCdAgADAAkJwSF8FgCdAgAEAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwASAAAAAA==.Nadalyñ:BAAALgADCgEJAQAAAA==.Nakrog:BAAALgAECgQJBwAAAA==.Napster:BAABLgAECn8sAAQcAAkJoSVNBQA+AwAcAAgJliVNBQA+AwAdAAQJrhsmiQBeAQAQAAEJIA3HUgArAAAAAA==.Nasa:BAACLgAFFH8VAAIUAAYJXBxfCQCGAQAUAAYJXBxfCQCGAQAuAAQKfxsAAhQACQkJH/QLALwCABQACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgIJBAAAAA==.Nellarixi:BAACLgAFFH8HAAIOAAMJ/RRxCADWAAAOAAMJ/RRxCADWAAAuAAQKf0EAAg4ACQk3I0MDAC4DAA4ACQk3I0MDAC4DAAAA.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH80AAMYAAkJUxrpBgCQAgAYAAkJUxrpBgCQAgALAAUJxRRFCAC1AAAuAAQKf2AAAxgACQmbJtIAAIMDABgACQmXJtIAAIMDAAsACAklIL8DAN4CAAAA.',
No='Nodens:BAAALgAFFAEJAQAAAA==.Nolwenn:BAACLgAFFH8IAAMNAAMJ8wV2OACnAAANAAMJ8wV2OACnAAAOAAEJ1QCSQwAfAAAuAAQKfxUAAg0ABwmtGCwaAP8BAA0ABwmtGCwaAP8BAAAA.Nomaa:BAABLgAECn82AAIPAAkJvAIRBAB/AAAPAAkJvAIRBAB/AAAAAA==.Nomäd:BAAALgAECgcJEAAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgASAAAAAA==.Notouchie:BAAALgADCgEJAQAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyanthra:BAAALgADCgEJAQAAAA==.Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAITAAcJqA77SwAFAQATAAcJqA77SwAFAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgx2JAAtAQAHAAkJxgx2JAAtAQAGAAEJ4gOCiQAmAAAhAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAFFAEJAgAAAA==.Oktoberfest:BAABLgAECn8YAAIVAAkJGh8qCQCgAgAVAAkJGh8qCQCgAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8gAAIQAAgJ9hIOEwCZAQAQAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECggJEgAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAbAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAABLgAFFH8NAAITAAYJLxHsBABwAQATAAYJLxHsBABwAQAAAA==.',
Po='Pocahontas:BAABLgAECn8tAAMCAAkJ7xwNDQCVAgACAAgJJx4NDQCVAgAOAAIJ/hFbZwCAAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8rAAINAAkJ2R6tBQAsAwANAAkJ2R6tBQAsAwAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quepaspete:BAAALgAFFAEJAQAAAA==.Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8SAAIaAAMJgBxmGADfAAAaAAMJgBxmGADfAAAuAAQKfzQAAhoABwk8I1MRAK4CABoABwk8I1MRAK4CAAEuAAMKBQkFABIAAAAA.Racker:BAABLgAECn8ZAAIWAAkJwhnRHwDwAQAWAAkJwhnRHwDwAQAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMWAAUJ8RnGSgB6AQAWAAUJ8RnGSgB6AQAXAAQJUxA6MADCAAAAAA==.Rengots:BAABLgAECn8YAAIaAAcJjBE/kgAbAQAaAAcJjBE/kgAbAQAAAA==.Renne:BAABLgAECn8jAAIgAAcJyBV5HgDLAQAgAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ri='Risha:BAAALgADCgEJAQAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgYJDwAAAA==.Rokkoz:BAABLgAECn8kAAMHAAkJzxBUJgAhAQAGAAcJthQMNABvAQAHAAkJ0QpUJgAhAQAAAA==.Romer:BAABLgAECn8WAAIZAAkJvQi7UAAsAQAZAAkJvQi7UAAsAQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQABAAcJmB0DXAB0AQAMAAQJGiEQDgBzAQAgAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIQAAYJSg6IKADTAAAQAAYJSg6IKADTAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCggJEwAAAA==.Saphroniå:BAAALgADCgIJAgAAAA==.Sarnt:BAAALgAECggJCwAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxzVDgBwAgAGAAkJjxzVDgBwAgAFAAMJSwuOmgB8AAABLgAECgkJGwAfAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQADAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIYAAgJIg3GNwBPAQAYAAgJIg3GNwBPAQAAAA==.Scibiol:BAAALgAECgUJBQAAAA==.',
Se='Selvina:BAAALgAECgYJBgAAAA==.Senseideath:BAAALgAFFAIJAgABLgADCgcJBwASAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shadowinder:BAAALgAECgEJAQAAAA==.Shadowmortis:BAAALgADCgMJAwAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgQJBAAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBmJlgCVAAADAAIJXBmJlgCVAAABLgAFFAYJGQAIAMIeAA==.Shirokhan:BAABLgAECn8qAAIIAAgJjB12LwBbAgAIAAgJjB12LwBbAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sialle:BAAALgAECgkJCQAAAA==.Sidewinderx:BAAALgAECgQJBAAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8NAAIDAAQJEhxAOwBeAQADAAQJEhxAOwBeAQAuAAQKf04AAwMACQkNJfsCAGIDAAMACQkNJfsCAGIDAAQAAwmhGR9HAJoAAAAA.',
Sn='Snagglespark:BAACLgAFFH8UAAITAAUJhBqpGgBGAQATAAUJhBqpGgBGAQAuAAQKf00AAxMACQmLIdQAAHkCABMACQmLIdQAAHkCABEAAQkSDdHeACoAAAAA.Sneakytacoss:BAAALgAECgYJBgABLgAFFAEJAQASAAAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8tAAIBAAkJ7Rr9HABmAgABAAkJ7Rr9HABmAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwASAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCQABLgAECgYJCgASAAAAAA==.Spicyfeet:BAAALgADCgcJBwAAAA==.Spinna:BAAALgAECgUJCAAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A0+KwAEAQAHAAgJ3A0+KwAEAQAAAA==.Starvnmarvn:BAAALgAECgYJDQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Steady:BAAALgAECgIJBAAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAUJEQAaAN4SAA==.Stormmonk:BAAALgAECgEJAQAAAA==.Stormybonk:BAAALgAECgUJBQAAAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xpLCQBUAgAKAAgJ3xpLCQBUAgAAAA==.Sunwing:BAAALgAECgUJCQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8lAAMnAAkJkxT4AABvAQAfAAgJVhFGZACfAQAnAAUJZxn4AABvAQAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJEAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg9IJwCXAQANAAgJSg9IJwCXAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAACLgAFFH8FAAIXAAIJaxbZIACRAAAXAAIJaxbZIACRAAAuAAQKfy8AAhcACAn1G9IOAP4BABcACAn1G9IOAP4BAAAA.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAACLgAFFH8MAAMKAAMJWSByGAAQAQAKAAMJWSByGAAQAQAYAAIJlAGiYQBPAAAuAAQKf0YAAgoACQlmIGQCAEoDAAoACQlmIGQCAEoDAAAA.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thera:BAAALgAECgMJAwABLgAECgYJCgASAAAAAA==.Thiccpickles:BAAALgAECgMJAwABLgAFFAMJBwARAJAiAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.Thunderbolt:BAAALgAFFAIJAgABLgADCgcJBwASAAAAAA==.Thymós:BAAALgAECgcJDgAAAA==.',
Ti='Tiffina:BAAALgAFFAIJAgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8PAAMPAAUJRxFaFABsAAADAAUJRxGNXAAPAQAPAAIJXQNaFABsAAABLgAFFAYJFwADAPsPAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJFAANAGAdAA==.Trillion:BAAALgAECgYJBgABLgAFFAMJCAADAEYUAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8GAAIdAAIJASL6fgC4AAAdAAIJASL6fgC4AAAuAAQKfywAAh0ACAlOJAMYALMCAB0ACAlOJAMYALMCAAAA.',
Tu='Tuckerherout:BAAALgAECgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twixx:BAABLgAFFH8cAAInAAQJchdrDAA3AQAnAAQJchdrDAA3AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAACLgAFFH8FAAIDAAIJJAFYvABSAAADAAIJJAFYvABSAAAuAAQKfxsAAwQACAnGB80jAJMAAAMACAnCBzabAAcBAAQABwmwAs0jAJMAAAAA.',
Ud='Uddercover:BAABLgAECn8bAAIeAAYJ7RSsKQBKAQAeAAYJ7RSsKQBKAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Ug='Ugebooge:BAAALgAECgQJBQAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAbAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQASAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8PAAIfAAcJ8BcTCQCxAQAfAAcJ8BcTCQCxAQAuAAQKfxwAAx8ABgkdJuY9AEACAB8ABgkdJuY9AEACACUAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBGjOQAqAQANAAYJQg+jOQAqAQACAAQJMA/9WADQAAAOAAIJ4QcijQAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8IAAIlAAMJxxDFKwCcAAAlAAMJxxDFKwCcAAAuAAQKfyIAAiUACAn2GwgUANMBACUACAn2GwgUANMBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAABLgAECn8XAAIcAAkJexRnFgBYAgAcAAkJexRnFgBYAgABLgAFFAUJFAAYAMAUAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQASAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn80AAIOAAkJuB8FCgCuAgAOAAkJuB8FCgCuAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn81AAMDAAkJ7xKPOQD0AQADAAkJ7xKPOQD0AQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAABLgAECgEJAQASAAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBpxqAAtAQAIAAYJdBpxqAAtAQAAAA==.',
Wi='Windswept:BAAALgAECgIJAwAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgkJGAARAIMfAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAgJGgAUAMokAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAgJGgAUAMokAA==.Xeromus:BAABLgAECn82AAMGAAkJZRvtAQCKAQAGAAkJZRvtAQCKAQAFAAIJ8wSjygA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgQJCgAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAABLgAECn8UAAMRAAUJfxptBABgAQARAAUJfxptBABgAQATAAIJUQYKmQBFAAAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMcAAkJ1RjAHgAMAgAcAAkJ1RjAHgAMAgAQAAIJkwHYWQAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAUJEQAUAIofAA==.Zarika:BAACLgAFFH8GAAIoAAMJfSIrBgAsAQAoAAMJfSIrBgAsAQAuAAQKfxoAAygACAnJIdACAIcCACgACAnJIdACAIcCAB4ABAmGEh5OALoAAAEuAAUUCAkaABQAyiQA.Zarì:BAACLgAFFH8aAAIUAAgJyiSVAADgAgAUAAgJyiSVAADgAgAuAAQKfx4AAhQACQkTJg4DAGUDABQACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAUJEQAUAIofAA==.',
Ze='Zeblaw:BAACLgAFFH8GAAIIAAIJOAn/swBqAAAIAAIJOAn/swBqAAAuAAQKfzAAAggACAkHGbBPAO0BAAgACAkHGbBPAO0BAAAA.Zekmal:BAAALgAFFAQJBAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgAECgQJBAAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8RAAIUAAUJih98AgBAAQAUAAUJih98AgBAAQAuAAQKf0MABBQACQlnJVgBAGcDABQACQlnJVgBAGcDABUABQlHEvFFAOMAABkAAQm4D/FrACoAAAAA.',
['Ðä']='Ðärëðëvïl:BAAALgAECgQJCAABLgADCgcJBwASAAAAAA==.',
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
