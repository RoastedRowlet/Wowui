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
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abbierose:BAAALgADCgUJBQAAAA==.Abyssia:BAABLgAECn8VAAIBAAcJRBrJSACsAQABAAcJRBrJSACsAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8qAAICAAgJpRSWIgCtAQACAAgJpRSWIgCtAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECggJDQAAAA==.Alcha:BAABLgAECn8oAAMDAAkJihuMKQA1AgADAAkJ2xiMKQA1AgAEAAcJoBrXCgCVAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgkJKAADAIobAA==.Alenndar:BAABLgAECn8oAAIFAAkJ1RL8KAALAgAFAAkJ1RL8KAALAgAAAA==.Alexdaddario:BAACLgAFFH8KAAIGAAMJkhfZLADXAAAGAAMJkhfZLADXAAAuAAQKfyEAAwYABglAIjIhAL8BAAYABglAIjIhAL8BAAcAAgniCBJtAD0AAAAA.Alkuhh:BAAALgADCgcJDgABLgAECgkJKAADAIobAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexNXbQCgAQAIAAgJexNXbQCgAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8XAAMKAAgJQRJ+EQCzAQAKAAcJrhJ+EQCzAQALAAIJSgp0HgBcAAABLgAECgkJLQACAO8cAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8zAAIMAAkJUCVQAgDfAgAMAAkJUCVQAgDfAgAAAA==.Annalease:BAAALgAECgMJBgAAAA==.Anticlimax:BAABLgAECn8sAAMBAAkJoRI/QADIAQABAAkJoRI/QADIAQAMAAEJTgaQPQAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJCwAAAA==.',
Ap='Apparition:BAACLgAFFH8IAAINAAMJPAbVOQCdAAANAAMJPAbVOQCdAAAuAAQKfyQAAw0ACQnDGOINAI8CAA0ACQnDGOINAI8CAA4ABQmVCtFwAGEAAAAA.Apprentice:BAACLgAFFH8YAAIIAAYJ+xv3LwCsAQAIAAYJ+xv3LwCsAQAuAAQKfy8AAggACAleJZ4TAOQCAAgACAleJZ4TAOQCAAAA.',
Ar='Arale:BAAALgADCgUJBgABLgAECgkJJgAPABoaAA==.Ardrhyes:BAAALgADCgYJBgABLgAECgkJNQADAO8SAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/FfQB8AQAIAAgJpw/FfQB8AQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.Artrael:BAABLgAFFH8GAAIQAAQJBgT0AACkAAAQAAQJBgT0AACkAAAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8PAAIRAAQJPR6rJABZAQARAAQJPR6rJABZAQAuAAQKfxwAAhEACQlKHWsWAGICABEACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgMJBAABLgAECgYJEQASAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8KAAIRAAMJkAi1XQCQAAARAAMJkAi1XQCQAAAuAAQKf0MAAxEACQn2FSsdAGMCABEACQn2FSsdAGMCABMABgndEA1GABsBAAAA.',
Av='Avdol:BAAALgAFFAEJAwABLgAFFAcJEQADAIEcAA==.Avienndha:BAABLgAECn8xAAIMAAkJgR0jBgA3AgAMAAkJgR0jBgA3AgAAAA==.',
Aw='Awake:BAACLgAFFH8IAAIUAAMJxxFzJQC9AAAUAAMJxxFzJQC9AAAuAAQKfx4AAxQACQntG7UKAJgCABQACQntG7UKAJgCABUAAwnjDOdtAIsAAAAA.',
Az='Azgrunga:BAACLgAFFH8GAAIWAAMJkg90OQDNAAAWAAMJkg90OQDNAAAuAAQKfy8AAhYACQlVGg4dAGUCABYACQlVGg4dAGUCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwAAAA==.Benderbrod:BAAALgAECgUJBgABLgAECgYJBwASAAAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.Bestshaman:BAAALgAECgEJAQAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8gAAIWAAcJpxt2OQDBAQAWAAcJpxt2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Bomburr:BAAALgAECgYJCQABLgAFFAcJFwAIAMUUAA==.Bonk:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8zAAIRAAkJJxuwEgC3AgARAAkJJxuwEgC3AgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIXAAkJkh8wBQDtAgAXAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8QAAIYAAQJPBKuAwACAQAYAAQJPBKuAwACAQAuAAQKfykAAhgACQlzIB8GAPoCABgACQlzIB8GAPoCAAAA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgAECgcJDAAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIRAAMJvRSRUwCqAAARAAMJvRSRUwCqAAAuAAQKfzMAAxEACAnmG7ApABYCABEACAnmG7ApABYCABMABglnGM9BACwBAAAA.Cheesefries:BAABLgAECn8xAAMZAAkJ/x/5DQC+AgAZAAkJ/x/5DQC+AgAVAAYJ0R0MIACmAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhZaQQCMAQAFAAcJrhZaQQCMAQAAAA==.Cherub:BAAALgADCgEJAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMVAAkJDRcXHQC8AQAVAAYJQxoXHQC8AQAUAAcJaQt0QQD6AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMZAAgJ3RHXOwCBAQAZAAgJ3RHXOwCBAQAUAAYJ1QWVXACjAAAAAA==.Clear:BAAALgADCggJCgAAAA==.',
Co='Cogglutch:BAAALgAECgQJBAABLgADCgcJBwASAAAAAA==.Cokegirll:BAABLgAECn8bAAIaAAgJJxIAUgCsAQAaAAgJJxIAUgCsAQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJKAAVAF4aAA==.Creamie:BAABLgAECn8oAAIVAAgJXhpHGADlAQAVAAgJXhpHGADlAQAAAA==.Creamish:BAABLgAECn8aAAIbAAgJlhUQDAAEAgAbAAgJlhUQDAAEAgABLgAECggJKAAVAF4aAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMcAAgJ3hTnJADfAQAcAAgJ3hTnJADfAQAdAAIJ9A61nQEuAAAAAA==.Crumbshot:BAAALgAFFAIJAgAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8MAAIIAAMJDxbBDQCcAAAIAAMJDxbBDQCcAAAuAAQKfxgAAwgACQkvD0VXANcBAAgACQkvD0VXANcBAAkAAwm/AwYTAFUAAAAA.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn80AAIHAAkJfhWBDwDuAQAHAAkJfhWBDwDuAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJNAAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIXAAgJEQ/nIQAgAQAXAAgJEQ/nIQAgAQAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgAECgEJAQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAwABLgAFFAEJAQASAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8uAAMUAAgJIRh9GADuAQAUAAgJIRh9GADuAQAZAAcJGhhWKADmAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAFFAMJCAADAEYUAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCwAAAA==.Dill:BAABLgAECn9LAAIWAAkJniQRBAAmAwAWAAkJniQRBAAmAwAAAA==.Dimonds:BAAALgAECgMJBAAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJCQAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgYJCgAAAA==.Dreadshade:BAAALgAECgYJBgAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgx5UQDIAAAGAAcJMgx5UQDIAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJCwASAAAAAA==.Dyabolykal:BAAALgAECgQJCAABLgAECgQJCwASAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIdAAkJKRJNawCYAQAdAAkJKRJNawCYAQABLgAFFAQJEAAYADwSAA==.Elly:BAABLgAFFH8IAAIeAAMJ7QamLADLAAAeAAMJ7QamLADLAAAAAA==.Elsharion:BAABLgAECn8VAAMcAAgJ5B0DLACxAQAcAAgJ5B0DLACxAQAdAAQJKgtFIQGSAAABLgAFFAgJGwAZAP0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAgJGwAZAP0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAgJGwAZAP0gAA==.Elshie:BAACLgAFFH8bAAIZAAgJ/SB8BgCoAgAZAAgJ/SB8BgCoAgAuAAQKfxcAAhkACQlBHmENAH4CABkACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8IAAIfAAQJyxdQXAA7AQAfAAQJyxdQXAA7AQABLgAFFAcJEQADAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAACLgAFFH8KAAIFAAMJ1wr+BACLAAAFAAMJ1wr+BACLAAAuAAQKf0oAAgUACQkjG7oUAKQCAAUACQkjG7oUAKQCAAAA.Evermoreivy:BAAALgAECgMJAwAAAA==.',
Fa='Fanairus:BAAALgAECgkJCQAAAA==.Fastasheet:BAACLgAFFH8iAAIUAAYJmh8VBAD0AQAUAAYJmh8VBAD0AQAuAAQKfz4AAhQACQl5JhECAFEDABQACQl5JhECAFEDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgADCgIJAgABLgAFFAEJAQASAAAAAA==.Fill:BAABLgAECn8gAAIbAAgJfyTsBwBKAgAbAAgJfyTsBwBKAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flarestepper:BAAALgADCgQJBAAAAA==.Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAACLgAFFH8GAAIVAAIJMAVjTwBlAAAVAAIJMAVjTwBlAAAuAAQKfyUAAhUACAlVFQcgAKYBABUACAlVFQcgAKYBAAEuAAUUAwkLAAoAWSAA.',
Fo='Foboshi:BAAALgAECgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIcAAkJ0RfMJQDZAQAcAAkJ0RfMJQDZAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.Fuzzywuzzy:BAAALgAECgIJAgAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJGAAVABofAA==.',
Ga='Gainz:BAAALgAFFAMJAwAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8nAAMOAAgJawpqOQAuAQAOAAgJawpqOQAuAQANAAQJIQU+XACOAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAACLgAFFH8HAAIVAAMJ4SBbAgD1AAAVAAMJ4SBbAgD1AAAuAAQKfz8AAhUACQk+JpYAAHgDABUACQk+JpYAAHgDAAAA.Giliaa:BAAALgAECgcJBwAAAA==.Gilljoww:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.Gireigtulb:BAAALgAECgIJAgAAAA==.',
Gl='Glizzee:BAAALgAECgEJAQAAAA==.',
Gn='Gnz:BAAALgAFFAMJAwAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAcJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAYJGQAYAMcQAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halløw:BAAALgAECgQJBAAAAA==.Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgQJBQAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8KAAIWAAQJJwWTLwDyAAAWAAQJJwWTLwDyAAAuAAQKfzoAAhYACQkxFh4XADUCABYACQkxFh4XADUCAAAA.Hilazy:BAABLgAECn8ZAAIbAAkJ7xnKAAAOAQAbAAkJ7xnKAAAOAQAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8fAAMNAAkJqBRbFQAwAgANAAkJqBRbFQAwAgAOAAEJLArXiQAwAAAAAA==.Holysheet:BAABLgAFFH8GAAIdAAMJ6A+7dADKAAAdAAMJ6A+7dADKAAAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8oAAMFAAkJFxrDJwATAgAFAAcJeRrDJwATAgAGAAgJUBXuAQDTAAAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJGAAVABofAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAASAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQASAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8kAAIIAAkJrgfQhQBsAQAIAAkJrgfQhQBsAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8bAAIIAAgJpgWzqQArAQAIAAgJpgWzqQArAQAAAA==.Ihavenofutur:BAAALgAECgYJEwAAAA==.',
Il='Illari:BAAALgAECgYJEgAAAA==.Illidantwo:BAACLgAFFH8bAAIgAAcJZRjSAwDyAQAgAAcJZRjSAwDyAQAuAAQKfzEAAiAACQlDJBEEADoDACAACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIXAAgJPB2sDQAQAgAXAAgJPB2sDQAQAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAwAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8YAAIeAAkJgBOvFQDyAQAeAAkJgBOvFQDyAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAYJGwABAHAZAA==.Jabu:BAAALgAFFAIJAwABLgAFFAYJGwABAHAZAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiVNEQBfAgANAAYJLiVNEQBfAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8fAAIhAAkJNg3KFQBrAQAhAAkJNg3KFQBrAQAAAA==.Jeryeth:BAABLgAECn8yAAMiAAkJTiLJAgAVAwAiAAkJOyLJAgAVAwAXAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgcJCgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAABLgAFFH8FAAIjAAIJEB3AJACtAAAjAAIJEB3AJACtAAAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAECLgAFFH8oAAMQAAcJzR9ZAACbAgAQAAcJzR9ZAACbAgAdAAMJBhKXbADWAAAuAAQKfy8AAhAACAloJt0AAGgDABAACAloJt0AAGgDAAAA.Kanda:BAAALgAECgcJCAAAAA==.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAdAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Keiràe:BAAALgADCgYJBAAAAA==.Kelsí:BAAALgAECgkJDgAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgASAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQbH7wAgAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAaAF8aAA==.Kiwí:BAABLgAECn8dAAMJAAgJXR2sBgBSAQAIAAYJdBbEigBiAQAJAAUJDh2sBgBSAQAAAA==.',
Ko='Konen:BAAALgADCgEJAQABLgAECgkJKAAFABcaAA==.',
Kr='Krasavice:BAABLgAECn9CAAIaAAkJOiNoCAAXAwAaAAkJOiNoCAAXAwAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQASAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8xAAIaAAkJIBN0RgDOAQAaAAkJIBN0RgDOAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAhpSgAKAQABAAYJsAhpSgAKAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8lAAMdAAkJ7xlxKgBXAgAdAAkJ7xlxKgBXAgAcAAcJvRLJNQB5AQAAAA==.Lemurshoes:BAAALgAFFAEJAgAAAA==.Lena:BAABLgAECn8qAAIaAAkJ4COVDwDUAgAaAAkJ4COVDwDUAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Letsgomen:BAAALgAECgQJBAAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIfAAgJGB1qJACsAgAfAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgAECgEJAQASAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAACLgAFFH8GAAIRAAMJFhoOQQDhAAARAAMJFhoOQQDhAAAuAAQKfysAAhEACAmDImoQAM0CABEACAmDImoQAM0CAAAA.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAASAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJOgAYAAMlAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8GAAIhAAMJ+hMBDgDaAAAhAAMJ+hMBDgDaAAAuAAQKfzoAAiEACQmBHo8EALUCACEACQmBHo8EALUCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIkAAgJKgeDFgADAQAkAAgJKgeDFgADAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQADAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIdAAkJlSEJGwCiAgAdAAkJlSEJGwCiAgAAAA==.Mankirijilla:BAAALgAECgMJBQAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJDwARAD0eAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIRAAcJTiHmHABlAgARAAcJTiHmHABlAgAAAA==.Maximus:BAABLgAECn8uAAIdAAkJ7w5yXwCyAQAdAAkJ7w5yXwCyAQAAAA==.Mayyflower:BAAALgAECgIJBAAAAA==.',
Me='Mechlil:BAAALgAECgIJBQAAAA==.Meditacoss:BAAALgAFFAEJAQAAAA==.Meelu:BAABLgAECn8WAAMFAAkJGgrNTQBXAQAFAAkJGgrNTQBXAQAGAAEJRQJsqAAXAAABLgAFFAQJEAAYADwSAA==.Mellowlizard:BAABLgAFFH8RAAIDAAcJgRySCACfAQADAAcJgRySCACfAQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgASAAAAAA==.Metuss:BAABLgAECn8YAAMZAAgJgR90FgBmAgAZAAgJgR90FgBmAgAUAAYJ3A+MPwABAQAAAA==.',
Mi='Mira:BAABLgAECn8wAAIaAAgJihS6SQDEAQAaAAgJihS6SQDEAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgYJEAABLgAECgkJTQAUAIoiAA==.Mkicon:BAACLgAFFH8HAAIIAAMJqQgkiwDDAAAIAAMJqQgkiwDDAAAuAAQKfykAAggACAmzFRBzAJMBAAgACAmzFRBzAJMBAAAA.Mkultra:BAABLgAECn8nAAMfAAkJCSJEGAC1AgAfAAkJvh5EGAC1AgAlAAcJQx+4HAB0AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8oAAIfAAkJwxPxAwDaAAAfAAkJwxPxAwDaAAAAAA==.Mooganfreman:BAAALgAECgQJBAAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8yAAImAAkJtByBBABLAgAmAAkJtByBBABLAgAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzANtjAA0AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAACLgAFFH8IAAIDAAMJRhR3BgDhAAADAAMJRhR3BgDhAAAuAAQKfzkAAwMACQkgH8UOANYCAAMACQkgH8UOANYCAAQAAgn/DblUAHAAAAAA.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8hAAMEAAkJHxqPAAA9AgAEAAYJCxiPAAA9AgADAAgJ3xg1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKQARAK4VAA==.Multanni:BAABLgAECn80AAITAAkJzRj1FwAkAgATAAkJzRj1FwAkAgAAAA==.',
My='Myonecrosis:BAABLgAECn8qAAMDAAkJwSF8FgCdAgADAAkJwSF8FgCdAgAEAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwASAAAAAA==.Nadalyñ:BAAALgADCgEJAQAAAA==.Nakrog:BAAALgAECgMJBgAAAA==.Napster:BAABLgAECn8sAAQcAAkJoSVOBQA+AwAcAAgJliVOBQA+AwAdAAQJrhsliQBeAQAQAAEJIA3HUgArAAAAAA==.Nasa:BAACLgAFFH8VAAIUAAYJXBxfCQCGAQAUAAYJXBxfCQCGAQAuAAQKfxsAAhQACQkJH/QLALwCABQACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgIJBAAAAA==.Nellarixi:BAACLgAFFH8HAAIOAAMJ/RS+AgDZAAAOAAMJ/RS+AgDZAAAuAAQKf0EAAg4ACQk3I0QDAC4DAA4ACQk3I0QDAC4DAAAA.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8vAAMYAAkJUxrxBgCPAgAYAAkJUxrxBgCPAgALAAMJIhhGCAC1AAAuAAQKf2AAAxgACQmbJtIAAIMDABgACQmXJtIAAIMDAAsACAklIL8DAN4CAAAA.',
No='Nodens:BAAALgAFFAEJAQAAAA==.Nolwenn:BAACLgAFFH8IAAMNAAMJ8wV7OACnAAANAAMJ8wV7OACnAAAOAAEJ1QCNQwAfAAAuAAQKfxUAAg0ABwmtGCsaAP8BAA0ABwmtGCsaAP8BAAAA.Nomaa:BAABLgAECn8xAAIPAAkJYAJFIQC4AAAPAAkJYAJFIQC4AAAAAA==.Nomäd:BAAALgAECgcJEAAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgASAAAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyanthra:BAAALgADCgEJAQAAAA==.Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAITAAcJqA76SwAFAQATAAcJqA76SwAFAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgx4JAAtAQAHAAkJxgx4JAAtAQAGAAEJ4gOCiQAmAAAhAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAFFAEJAgAAAA==.Oktoberfest:BAABLgAECn8YAAIVAAkJGh8qCQCgAgAVAAkJGh8qCQCgAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8gAAIQAAgJ9hIOEwCZAQAQAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECggJEgAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAbAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAABLgAFFH8MAAITAAYJFxG6AQBdAQATAAYJFxG6AQBdAQAAAA==.',
Po='Pocahontas:BAABLgAECn8tAAMCAAkJ7xwNDQCVAgACAAgJJx4NDQCVAgAOAAIJ/hFPZwCAAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8rAAINAAkJ2R6tBQAsAwANAAkJ2R6tBQAsAwAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quepaspete:BAAALgAFFAEJAQAAAA==.Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8OAAIaAAMJgBxbXADsAAAaAAMJgBxbXADsAAAuAAQKfzIAAhoABwk8I1MRAK4CABoABwk8I1MRAK4CAAAA.Racker:BAABLgAECn8ZAAIWAAkJwhmVAQATAQAWAAkJwhmVAQATAQAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMWAAUJ8RnGSgB6AQAWAAUJ8RnGSgB6AQAXAAQJUxA6MADCAAAAAA==.Rengots:BAABLgAECn8XAAIaAAcJjBFBkgAbAQAaAAcJjBFBkgAbAQAAAA==.Renne:BAABLgAECn8jAAIgAAcJyBV5HgDLAQAgAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgYJDwAAAA==.Rokkoz:BAABLgAECn8kAAMHAAkJzxBWJgAhAQAGAAcJthQMNABvAQAHAAkJ0QpWJgAhAQAAAA==.Romer:BAABLgAECn8WAAIZAAkJvQi6UAAsAQAZAAkJvQi6UAAsAQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQABAAcJmB0EXAB0AQAMAAQJGiEQDgBzAQAgAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIQAAYJSg6IKADTAAAQAAYJSg6IKADTAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCggJEwAAAA==.Sarnt:BAAALgAECggJCwAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxzTDgBwAgAGAAkJjxzTDgBwAgAFAAMJSwuOmgB8AAABLgAECgkJGwAfAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQADAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIYAAgJIg3DNwBPAQAYAAgJIg3DNwBPAQAAAA==.Scibiol:BAAALgAECgEJAQAAAA==.',
Se='Selvina:BAAALgAECgYJBgAAAA==.Senseideath:BAAALgAFFAIJAgABLgADCgcJBwASAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shadowinder:BAAALgAECgEJAQAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgQJBAAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBmclgCVAAADAAIJXBmclgCVAAABLgAFFAYJFgAIAMIeAA==.Shirokhan:BAABLgAECn8qAAIIAAgJjB15LwBbAgAIAAgJjB15LwBbAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sialle:BAAALgAECgkJCQAAAA==.Sidewinderx:BAAALgAECgQJBAAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8NAAIDAAQJEhztBQDuAAADAAQJEhztBQDuAAAuAAQKf04AAwMACQkNJfsCAGIDAAMACQkNJfsCAGIDAAQAAwmhGR9HAJoAAAAA.',
Sn='Snagglespark:BAACLgAFFH8UAAITAAUJhBqrGgBGAQATAAUJhBqrGgBGAQAuAAQKf0sAAxMACQmBIHEAABUCABMACQmBIHEAABUCABEAAQkSDdHeACoAAAAA.Sneakytacoss:BAAALgAECgYJBgABLgAFFAEJAQASAAAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8tAAIBAAkJ7Rr/HABmAgABAAkJ7Rr/HABmAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwASAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCAABLgAECgYJCgASAAAAAA==.Spicyfeet:BAAALgADCgcJBwAAAA==.Spinna:BAAALgAECgUJBwAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A0+KwAEAQAHAAgJ3A0+KwAEAQAAAA==.Starvnmarvn:BAAALgAECgYJDQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Steady:BAAALgAECgIJBAAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAUJEAAaAN4SAA==.Stormmonk:BAAALgAECgEJAQAAAA==.Stormybonk:BAAALgAECgUJBQAAAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xpLCQBUAgAKAAgJ3xpLCQBUAgAAAA==.Sunwing:BAAALgAECgQJBQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8gAAMnAAkJvxO6AADkAAAfAAgJVhFEZACfAQAnAAMJChu6AADkAAAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJEAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg9DJwCXAQANAAgJSg9DJwCXAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAACLgAFFH8FAAIXAAIJaxbUIACRAAAXAAIJaxbUIACRAAAuAAQKfy8AAhcACAn1G9QOAP4BABcACAn1G9QOAP4BAAAA.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAACLgAFFH8LAAMKAAMJWSB1GAAQAQAKAAMJWSB1GAAQAQAYAAIJlAGeYQBPAAAuAAQKf0YAAgoACQlmIGQCAEoDAAoACQlmIGQCAEoDAAAA.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thera:BAAALgAECgIJAgABLgAECgYJCgASAAAAAA==.Thiccpickles:BAAALgAECgMJAwABLgAFFAMJBwARAJAiAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.Thunderbolt:BAAALgAFFAIJAgABLgADCgcJBwASAAAAAA==.Thymós:BAAALgAECgcJDgAAAA==.',
Ti='Tiffina:BAAALgAFFAIJAgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8NAAMPAAUJfA5YFABsAAADAAUJfA6mXAAPAQAPAAIJXQNYFABsAAABLgAFFAYJFwADAPsPAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJFAANAGAdAA==.Trillion:BAAALgAECgYJBgABLgAFFAMJCAADAEYUAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8GAAIdAAIJASIDfwC4AAAdAAIJASIDfwC4AAAuAAQKfywAAh0ACAlOJAQYALMCAB0ACAlOJAQYALMCAAAA.',
Tu='Tuckerherout:BAAALgAECgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twixx:BAABLgAFFH8cAAInAAQJchd8AQDwAAAnAAQJchd8AQDwAAAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAACLgAFFH8FAAIDAAIJJAFhvABSAAADAAIJJAFhvABSAAAuAAQKfxsAAwQACAnGB8sjAJMAAAMACAnCBzObAAcBAAQABwmwAssjAJMAAAAA.',
Ud='Uddercover:BAABLgAECn8bAAIeAAYJ7RSrKQBKAQAeAAYJ7RSrKQBKAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Ug='Ugebooge:BAAALgAECgQJBAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAbAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQASAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8JAAIfAAMJZCKYiwDzAAAfAAMJZCKYiwDzAAAuAAQKfxwAAx8ABgkdJuY9AEACAB8ABgkdJuY9AEACACUAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBGlOQAqAQANAAYJQg+lOQAqAQACAAQJMA/9WADQAAAOAAIJ4QcbjQAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8HAAIlAAMJxxDLKwCcAAAlAAMJxxDLKwCcAAAuAAQKfyIAAiUACAn2GwcUANMBACUACAn2GwcUANMBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAABLgAECn8XAAIcAAkJexRoFgBYAgAcAAkJexRoFgBYAgABLgAFFAQJEAAYADwSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQASAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn8vAAIOAAkJrh0FCgCuAgAOAAkJrh0FCgCuAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn81AAMDAAkJ7xKMOQD0AQADAAkJ7xKMOQD0AQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAABLgAECgEJAQASAAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBpsqAAtAQAIAAYJdBpsqAAtAQAAAA==.',
Wi='Windswept:BAAALgAECgIJAwAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgkJGAARAIMfAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAgJGgAUAMokAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAgJGgAUAMokAA==.Xeromus:BAABLgAECn8xAAMGAAkJPRipFwAQAgAGAAkJPRipFwAQAgAFAAIJ8wSkygA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgQJCAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgUJDwAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMcAAkJ1Ri/HgAMAgAcAAkJ1Ri/HgAMAgAQAAIJkwHYWQAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAQJDQAUAFYcAA==.Zarika:BAACLgAFFH8GAAIoAAMJfSIqBgAsAQAoAAMJfSIqBgAsAQAuAAQKfxoAAygACAnJIdACAIcCACgACAnJIdACAIcCAB4ABAmGEh5OALoAAAEuAAUUCAkaABQAyiQA.Zarì:BAACLgAFFH8aAAIUAAgJyiSVAADgAgAUAAgJyiSVAADgAgAuAAQKfx4AAhQACQkTJg4DAGUDABQACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAQJDQAUAFYcAA==.',
Ze='Zeblaw:BAACLgAFFH8GAAIIAAIJOAkNtABqAAAIAAIJOAkNtABqAAAuAAQKfzAAAggACAkHGbFPAO0BAAgACAkHGbFPAO0BAAAA.Zekmal:BAAALgAFFAQJBAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8NAAIUAAQJVhzzAAAvAQAUAAQJVhzzAAAvAQAuAAQKf0MABBQACQlnJVkBAGcDABQACQlnJVkBAGcDABUABQlHEu9FAOMAABkAAQm4D/FrACoAAAAA.',
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
