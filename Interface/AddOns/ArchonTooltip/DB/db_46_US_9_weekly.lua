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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Unknown-Unknown','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Evoker-Augmentation','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Rogue-Subtlety','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Warlock-Affliction','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abbierose:BAAALgADCgUJBQAAAA==.Abyssia:BAABLgAECn8XAAIBAAcJRBrISACsAQABAAcJRBrISACsAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8wAAICAAgJtBRGBwAhAQACAAgJtBRGBwAhAQAAAA==.Adiwolf:BAAALgAECgkJEQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.Aethenadawn:BAAALgAECgEJAQAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECgkJDgAAAA==.Alcha:BAABLgAECn8pAAMDAAkJGx2MKQA1AgADAAkJbRqMKQA1AgAEAAcJoBrXCgCVAQAAAA==.Alenndar:BAABLgAECn8oAAIFAAkJ1RL6KAALAgAFAAkJ1RL6KAALAgAAAA==.Alexdaddario:BAACLgAFFH8KAAIGAAMJkhfWLADXAAAGAAMJkhfWLADXAAAuAAQKfyEAAwYABglAIjUhAL8BAAYABglAIjUhAL8BAAcAAgniCBRtAD0AAAAA.Alkuhh:BAAALgADCgcJDgABLgAECgkJKQADABsdAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexNXbQCgAQAIAAgJexNXbQCgAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8XAAMKAAgJQRJ+EQCyAQAKAAcJrhJ+EQCyAQALAAIJSgp1HgBcAAABLgAECgkJLQACAO8cAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn9JAAIMAAkJYCU2AABDAwAMAAkJYCU2AABDAwAAAA==.Annalease:BAAALgAECgMJBgAAAA==.Anticlimax:BAABLgAECn8sAAMBAAkJoRJCQADIAQABAAkJoRJCQADIAQAMAAEJTgaTPQAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAFFAMJAwAAAA==.',
Ap='Apparition:BAACLgAFFH8IAAINAAMJPAbQOQCdAAANAAMJPAbQOQCdAAAuAAQKfyQAAw0ACQnDGOINAI8CAA0ACQnDGOINAI8CAA4ABQmVCtxwAGEAAAAA.Apprentice:BAACLgAFFH8ZAAIIAAcJ2RraLwCtAQAIAAcJ2RraLwCtAQAuAAQKfy8AAggACAleJZsTAOQCAAgACAleJZsTAOQCAAAA.',
Ar='Arale:BAAALgADCgUJBgABLgAFFAEJAQAPAAAAAA==.Ardrhyes:BAAALgADCgYJBgABLgAECgkJNQADAO8SAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/EfQB8AQAIAAgJpw/EfQB8AQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.Artrael:BAABLgAFFH8LAAIQAAYJ9gUOBQDDAAAQAAYJ9gUOBQDDAAAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8QAAIRAAQJmx6wJABZAQARAAQJmx6wJABZAQAuAAQKfxwAAhEACQlKHWsWAGICABEACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgUJBwABLgAECgYJEQAPAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8KAAIRAAMJkAi5XQCQAAARAAMJkAi5XQCQAAAuAAQKf0MAAxEACQn2FS0dAGMCABEACQn2FS0dAGMCABIABgndEA1GABsBAAAA.Autobot:BAAALgADCgQJBAAAAA==.',
Av='Avdol:BAAALgAFFAEJAwABLgAFFAgJEgADAMwaAA==.Avienndha:BAABLgAECn9HAAIMAAkJdyB9AAC7AgAMAAkJdyB9AAC7AgAAAA==.',
Aw='Awake:BAACLgAFFH8MAAITAAMJxxF0JQC9AAATAAMJxxF0JQC9AAAuAAQKfx4AAxMACQntG7UKAJgCABMACQntG7UKAJgCABQAAwnjDOdtAIsAAAAA.',
Az='Azgrunga:BAACLgAFFH8GAAIVAAMJkg9vOQDNAAAVAAMJkg9vOQDNAAAuAAQKfy8AAhUACQlVGg4dAGUCABUACQlVGg4dAGUCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwABLgAFFAEJAgAPAAAAAA==.Benderbrod:BAAALgAFFAEJAgAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.Bestshaman:BAAALgAECgEJAQAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8hAAIVAAcJpxt2OQDBAQAVAAcJpxt2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Bomburr:BAAALgAECgYJCQABLgAFFAcJFwAIAMUUAA==.Bonk:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8zAAIRAAkJJxuwEgC3AgARAAkJJxuwEgC3AgAAAA==.Bouquet:BAAALgAECgMJAwAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIWAAkJkh8wBQDtAgAWAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8VAAIXAAYJahElEQAmAQAXAAYJahElEQAmAQAuAAQKfykAAhcACQlzIB4GAPoCABcACQlzIB4GAPoCAAAA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAABLgAFFH8GAAIBAAMJ3hhGIwDmAAABAAMJ3hhGIwDmAAAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Calin:BAAALgADCggJCAAAAA==.Candor:BAAALgAECggJDQAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIRAAMJvRSTUwCqAAARAAMJvRSTUwCqAAAuAAQKfzMAAxEACAnmG7IpABYCABEACAnmG7IpABYCABIABglnGNFBACwBAAAA.Chayara:BAAALgAFFAQJAQAAAA==.Cheesebugga:BAAALgAECgUJBQAAAA==.Cheesefries:BAABLgAECn89AAMYAAkJFyD2DQC+AgAYAAkJFyD2DQC+AgAUAAYJ0R0OIACmAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhZZQQCMAQAFAAcJrhZZQQCMAQAAAA==.Cherub:BAAALgAECgMJAwAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMUAAkJDRcZHQC8AQAUAAYJQxoZHQC8AQATAAcJaQt2QQD6AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.Chôpstixx:BAAALgAECgQJAwAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMYAAgJ3RHaOwCBAQAYAAgJ3RHaOwCBAQATAAYJ1QWUXACjAAAAAA==.Clear:BAAALgADCggJCgAAAA==.',
Co='Cogglutch:BAAALgAECgQJBAABLgADCgcJBwAPAAAAAA==.Cokegirll:BAABLgAECn8bAAIZAAgJJxL/UQCsAQAZAAgJJxL/UQCsAQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJKAAUAF4aAA==.Creamie:BAABLgAECn8oAAIUAAgJXhpIGADlAQAUAAgJXhpIGADlAQAAAA==.Creamish:BAABLgAECn8aAAIaAAgJlhUQDAAEAgAaAAgJlhUQDAAEAgABLgAECggJKAAUAF4aAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCwAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMbAAgJ3hTqJADfAQAbAAgJ3hTqJADfAQAcAAIJ9A64nQEuAAAAAA==.Crumbshot:BAAALgAFFAMJBAAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8bAAIIAAYJgxXmFwCNAQAIAAYJgxXmFwCNAQAuAAQKfxgAAwgACQkvD0VXANcBAAgACQkvD0VXANcBAAkAAwm/AwcTAFUAAAAA.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn83AAIHAAkJ0BWADwDuAQAHAAkJ0BWADwDuAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJNwAHANAVAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIWAAgJEQ/pIQAgAQAWAAgJEQ/pIQAgAQAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgAECgEJAQAAAA==.',
De='Deadlyshiet:BAABLgAFFH8JAAIdAAUJDx6XGQB5AQAdAAUJDx6XGQB5AQABLgAFFAkJMQATAIgeAA==.Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgUJBwABLgAFFAIJAgAPAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Denrin:BAABLgAECn8UAAIRAAcJeA7/CgBCAQARAAcJeA7/CgBCAQAAAA==.Deone:BAABLgAECn8uAAMTAAgJIRh8GADuAQATAAgJIRh8GADuAQAYAAcJGhhVKADnAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAFFAMJCAADAEYUAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJDgAAAA==.Dill:BAABLgAECn9WAAMVAAkJxyQSBAAmAwAVAAkJxyQSBAAmAwAWAAIJvyKGBgDOAAAAAA==.Dimonds:BAAALgAECgMJBAAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJCQAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Dondeezy:BAAALgAECgcJCgAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgYJCgAAAA==.Dreadshade:BAAALgAECgYJBgAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgyBUQDIAAAGAAcJMgyBUQDIAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgABLgAECgYJBgAPAAAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.Duzz:BAAALgAECgMJAwAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJDgAPAAAAAA==.Dyabolykal:BAAALgAECgQJCwABLgAECgQJDgAPAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIcAAkJKRJLawCYAQAcAAkJKRJLawCYAQABLgAFFAYJFQAXAGoRAA==.Elly:BAABLgAFFH8JAAIeAAMJ7QakLADLAAAeAAMJ7QakLADLAAAAAA==.Elsharion:BAABLgAECn8VAAMbAAgJ5B0GLACxAQAbAAgJ5B0GLACxAQAcAAQJKgtKIQGSAAABLgAFFAkJHAAYAGsgAA==.Elsharius:BAAALgAECgQJBAABLgAFFAkJHAAYAGsgAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAkJHAAYAGsgAA==.Elshie:BAACLgAFFH8cAAIYAAkJayB6BgCoAgAYAAkJayB6BgCoAgAuAAQKfxcAAhgACQlBHmENAH4CABgACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8IAAIdAAQJyxdLXAA7AQAdAAQJyxdLXAA7AQABLgAFFAgJEgADAMwaAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAACLgAFFH8LAAIFAAQJ+QkqFADAAAAFAAQJ+QkqFADAAAAuAAQKf0oAAgUACQkjG7oUAKQCAAUACQkjG7oUAKQCAAAA.Evermoreivy:BAAALgAECgMJBgAAAA==.',
Fa='Fanairus:BAAALgAECgkJCQAAAA==.Fastasheet:BAACLgAFFH8xAAITAAkJiB56AAD6AgATAAkJiB56AAD6AgAuAAQKfz4AAhMACQl5JhECAFEDABMACQl5JhECAFEDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgAECgEJAQABLgAFFAIJAgAPAAAAAA==.Fill:BAABLgAECn8gAAIaAAgJfyTsBwBKAgAaAAgJfyTsBwBKAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flarestepper:BAAALgADCgQJBAAAAA==.Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAACLgAFFH8RAAIUAAMJ4wbrEwCYAAAUAAMJ4wbrEwCYAAAuAAQKfycAAhQACAnCFQkgAKYBABQACAnCFQkgAKYBAAEuAAUUBAkTAAoAIhoA.',
Fo='Foboshi:BAAALgAECgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIbAAkJ0RfOJQDZAQAbAAkJ0RfOJQDZAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.Fuzzywuzzy:BAAALgAECgIJAgAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJGAAUABofAA==.',
Ga='Gainz:BAAALgAFFAMJAwAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn85AAMOAAkJxg0sCAAWAQAOAAkJxg0sCAAWAQANAAcJ+QZuEACXAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAACLgAFFH8HAAIUAAMJ4SBiJAAZAQAUAAMJ4SBiJAAZAQAuAAQKfz8AAhQACQk+JpUAAHgDABQACQk+JpUAAHgDAAAA.Giliaa:BAAALgAECgcJBwAAAA==.Giljoww:BAAALgAECggJCAAAAA==.Gilljoww:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.Gireigtulb:BAAALgAECgIJAgAAAA==.',
Gl='Glizzee:BAAALgAECgEJAQAAAA==.',
Gn='Gnz:BAABLgAFFH8HAAIRAAMJ0hFdLACIAAARAAMJ0hFdLACIAAAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAkJAgAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAcJGgAXAFEOAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halløw:BAAALgAECgQJBAAAAA==.Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgQJBQAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8KAAIVAAQJJwWNLwDyAAAVAAQJJwWNLwDyAAAuAAQKfzoAAhUACQkxFh4XADUCABUACQkxFh4XADUCAAAA.Hilazy:BAABLgAECn8bAAIaAAkJMhoRDQDgAQAaAAkJMhoRDQDgAQAAAA==.Hiping:BAAALgAECgYJDwAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBwAAAA==.Holyfed:BAAALgAFFAIJAgAAAA==.Holyphok:BAABLgAECn8fAAMNAAkJqBRcFQAwAgANAAkJqBRcFQAwAgAOAAEJLAreiQAwAAAAAA==.Holysheet:BAABLgAFFH8GAAIcAAMJ6A+xdADKAAAcAAMJ6A+xdADKAAABLgAFFAkJMQATAIgeAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn85AAMFAAkJ6RwtAQDdAgAFAAkJ6RwtAQDdAgAGAAgJaRWvKQCGAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJGAAUABofAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAAPAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQAPAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8kAAIIAAkJrgfRhQBsAQAIAAkJrgfRhQBsAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8bAAIIAAgJpgW3qQArAQAIAAgJpgW3qQArAQAAAA==.Ihavenofutur:BAABLgAECn8UAAIIAAcJIgop4gDYAAAIAAcJIgop4gDYAAAAAA==.',
Il='Illari:BAAALgAECgYJEgAAAA==.Illidantwo:BAACLgAFFH8fAAIfAAgJJRjSAwDyAQAfAAgJJRjSAwDyAQAuAAQKfzEAAh8ACQlDJBEEADoDAB8ACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIWAAgJPB2rDQAQAgAWAAgJPB2rDQAQAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAwAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8YAAIeAAkJgBOwFQDyAQAeAAkJgBOwFQDyAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAcJHAABAPkVAA==.Jabu:BAABLgAFFH8FAAQFAAIJIQR+YgBWAAAFAAIJIQR+YgBWAAAGAAEJFAWaKwArAAAHAAEJewseQwAlAAABLgAFFAcJHAABAPkVAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiVOEQBfAgANAAYJLiVOEQBfAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8rAAIgAAkJFRfUAQC8AQAgAAkJFRfUAQC8AQAAAA==.Jeryeth:BAABLgAECn8yAAMhAAkJTiLJAgAVAwAhAAkJOyLJAgAVAwAWAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgkJEgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAABLgAFFH8IAAIiAAMJgRt7CAD5AAAiAAMJgRt7CAD5AAAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAECLgAFFH8xAAMQAAkJxiNZAACbAgAQAAkJxiNZAACbAgAcAAMJNhWkOQCfAAAuAAQKfy8AAhAACAloJt0AAGgDABAACAloJt0AAGgDAAAA.Kanda:BAAALgAECgcJCAAAAA==.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAcAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Keiràe:BAAALgAECgUJBQAAAA==.Kelsí:BAABLgAECn8UAAIbAAkJEAyeNQB6AQAbAAkJEAyeNQB6AQAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgAPAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQbG7wAgAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAZAF8aAA==.Kiwí:BAACLgAFFH8JAAIIAAMJKhhlNgDUAAAIAAMJKhhlNgDUAAAuAAQKfx0AAwkACAldHasGAFIBAAgABgl0FseKAGIBAAkABQkOHasGAFIBAAAA.',
Ko='Konen:BAAALgAECgEJAQABLgAECgkJOQAFAOkcAA==.',
Kr='Krasavice:BAABLgAECn9FAAIZAAkJOiNmCAAXAwAZAAkJOiNmCAAXAwAAAA==.Krenik:BAAALgADCgMJAwAAAA==.Krisp:BAAALgAECgQJBAABLgAFFAIJAgAPAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn83AAIZAAkJjRZ2RgDOAQAZAAkJjRZ2RgDOAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAhbSgAKAQABAAYJsAhbSgAKAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8lAAMcAAkJ7xluKgBXAgAcAAkJ7xluKgBXAgAbAAcJvRLKNQB5AQAAAA==.Lemurshoes:BAAALgAFFAEJAgAAAA==.Lena:BAABLgAECn8qAAIZAAkJ4COTDwDUAgAZAAkJ4COTDwDUAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Letsgomen:BAAALgAECgQJBAAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIdAAgJGB1qJACsAgAdAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAACLgAFFH8GAAIRAAMJFhoOQQDhAAARAAMJFhoOQQDhAAAuAAQKfy0AAhEACQlQImkQAM0CABEACQlQImkQAM0CAAAA.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAAPAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJOgAXAAMlAA==.Lucentdawn:BAAALgAECgUJCAAAAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8GAAIgAAMJ+hMDDgDaAAAgAAMJ+hMDDgDaAAAuAAQKfzoAAiAACQmBHpAEALUCACAACQmBHpAEALUCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIjAAgJKgeDFgADAQAjAAgJKgeDFgADAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAgJEgADAMwaAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIcAAkJlSEJGwCiAgAcAAkJlSEJGwCiAgAAAA==.Mankirijilla:BAAALgAECgMJBQAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJEAARAJseAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIRAAcJTiHpHABlAgARAAcJTiHpHABlAgAAAA==.Maximus:BAABLgAECn80AAIcAAkJURAPEwAUAQAcAAkJURAPEwAUAQAAAA==.Mayyflower:BAAALgAECgIJBAAAAA==.',
Me='Mechlil:BAAALgAECgIJBQAAAA==.Meditacoss:BAAALgAFFAEJAQAAAA==.Meelu:BAABLgAECn8WAAMFAAkJGgrLTQBXAQAFAAkJGgrLTQBXAQAGAAEJRQJyqAAXAAABLgAFFAYJFQAXAGoRAA==.Mellowlizard:BAABLgAFFH8SAAIDAAgJzBqSCACfAQADAAgJzBqSCACfAQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgAPAAAAAA==.Metuss:BAABLgAECn8YAAMYAAgJgR9zFgBmAgAYAAgJgR9zFgBmAgATAAYJ3A+PPwABAQAAAA==.',
Mi='Mira:BAABLgAECn8wAAIZAAgJihS8SQDEAQAZAAgJihS8SQDEAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgYJEAABLgAECgkJTQATAIoiAA==.Mkdemcon:BAAALgADCgMJAwAAAA==.Mkicon:BAACLgAFFH8HAAIIAAMJqQgIiwDDAAAIAAMJqQgIiwDDAAAuAAQKfy0AAggACQlqF98UAAcBAAgACQlqF98UAAcBAAAA.Mkultra:BAABLgAECn8nAAMdAAkJCSJFGAC1AgAdAAkJvh5FGAC1AgAkAAcJQx+7HAB0AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8yAAIdAAkJhRXrCACDAQAdAAkJhRXrCACDAQAAAA==.Mooganfreman:BAAALgAECgQJBQAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8/AAIlAAkJvh3HAADSAQAlAAkJvh3HAADSAQAAAA==.Moondawn:BAAALgADCgMJAwAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzANwjAA0AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAACLgAFFH8IAAIDAAMJRhRJLADIAAADAAMJRhRJLADIAAAuAAQKfzkAAwMACQkgH8UOANYCAAMACQkgH8UOANYCAAQAAgn/DblUAHAAAAAA.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8iAAMEAAkJHxqPAAA9AgAEAAYJCxiPAAA9AgADAAgJ3xg1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKgARAK4VAA==.Mugginz:BAAALgAECgQJBAAAAA==.Multanni:BAABLgAECn80AAISAAkJzRj0FwAkAgASAAkJzRj0FwAkAgAAAA==.',
My='Myonecrosis:BAABLgAECn8+AAQDAAkJbSN8FgCdAgADAAkJGCN8FgCdAgAmAAMJWCBWAwAgAQAEAAEJ+BI1bAA7AAAAAA==.Myrk:BAAALgAECgEJAgAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwAPAAAAAA==.Nadalyñ:BAAALgADCgEJAQAAAA==.Nakrog:BAAALgAECgQJCQAAAA==.Napster:BAABLgAECn8tAAQbAAkJ/SJNBQA+AwAbAAkJ/SJNBQA+AwAcAAQJrhsmiQBeAQAQAAEJIA3HUgArAAAAAA==.Nasa:BAACLgAFFH8WAAITAAcJQBlfCQCGAQATAAcJQBlfCQCGAQAuAAQKfxsAAhMACQkJH/QLALwCABMACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgUJCAAAAA==.Nellarixi:BAACLgAFFH8HAAIOAAMJ/RS9EADIAAAOAAMJ/RS9EADIAAAuAAQKf0EAAg4ACQk3I0MDAC4DAA4ACQk3I0MDAC4DAAAA.Nephtthys:BAAALgAFFAIJAgAAAA==.Neptune:BAAALgAECgEJAgAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH9CAAMXAAkJQR3vAgCzAgAXAAkJWBzvAgCzAgALAAYJkhohAQBXAQAuAAQKf2AAAxcACQmbJtIAAIMDABcACQmXJtIAAIMDAAsACAklIL8DAN4CAAAA.',
No='Nodens:BAAALgAFFAEJAQAAAA==.Nolwenn:BAACLgAFFH8IAAMNAAMJ8wV2OACnAAANAAMJ8wV2OACnAAAOAAEJ1QCSQwAfAAAuAAQKfxUAAg0ABwmtGCwaAP8BAA0ABwmtGCwaAP8BAAAA.Nomaa:BAABLgAECn9HAAImAAkJwAO/BQDIAAAmAAkJwAO/BQDIAAAAAA==.Nomäd:BAAALgAECggJEgAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgAPAAAAAA==.Notouchie:BAAALgADCgEJAQAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyanthra:BAAALgAECggJCQAAAA==.Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAISAAcJqA77SwAFAQASAAcJqA77SwAFAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAACLgAFFH8IAAIHAAQJ2gM6FgBrAAAHAAQJ2gM6FgBrAAAuAAQKfzUABAcACQnGDHYkAC0BAAcACQnGDHYkAC0BAAYAAQniA4KJACYAACAAAQmRAzk5ACQAAAAA.',
Ok='Okko:BAAALgAFFAEJAgAAAA==.Oktoberfest:BAABLgAECn8YAAIUAAkJGh8qCQCgAgAUAAkJGh8qCQCgAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Or='Orflame:BAAALgAECggJCAAAAA==.',
Pe='Perky:BAABLgAECn8hAAIQAAgJoxMOEwCZAQAQAAgJoxMOEwCZAQAAAA==.',
Ph='Phok:BAABLgAECn8UAAMYAAgJJhuhHAAzAgAYAAgJJhuhHAAzAgATAAEJogUvuAAgAAAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAaAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAABLgAFFH8OAAISAAYJxRFfCwBdAQASAAYJxRFfCwBdAQAAAA==.',
Po='Pocahontas:BAABLgAECn8tAAMCAAkJ7xwNDQCVAgACAAgJJx4NDQCVAgAOAAIJ/hFbZwCAAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8rAAINAAkJ2R6tBQAsAwANAAkJ2R6tBQAsAwAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quepaspete:BAAALgAFFAIJAgAAAA==.Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8VAAIZAAMJgBzcKADqAAAZAAMJgBzcKADqAAAuAAQKfzkAAhkABwlFI1MRAK4CABkABwlFI1MRAK4CAAEuAAQKBgkMAA8AAAAA.Racker:BAABLgAECn8fAAIVAAkJqR56AgAQAgAVAAkJqR56AgAQAgAAAA==.Ragñar:BAAALgAECgYJBgAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8VAAMVAAUJ8RnGSgB6AQAVAAUJ8RnGSgB6AQAWAAQJUxA6MADCAAAAAA==.Rengots:BAABLgAECn8ZAAIZAAcJFRM/kgAbAQAZAAcJFRM/kgAbAQAAAA==.Renne:BAABLgAECn8jAAIfAAcJyBV5HgDLAQAfAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rhaez:BAAALgAECgMJAwAAAA==.Rheana:BAAALgAECgYJEAAAAA==.',
Ri='Risha:BAAALgAECgUJBQAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAABLgAECn8VAAIRAAcJQxdECACBAQARAAcJQxdECACBAQAAAA==.Rokkoz:BAABLgAECn8kAAMHAAkJzxBUJgAhAQAGAAcJthQMNABvAQAHAAkJ0QpUJgAhAQAAAA==.Romer:BAABLgAECn8WAAIYAAkJvQi7UAAsAQAYAAkJvQi7UAAsAQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQABAAcJmB0DXAB0AQAMAAQJGiEQDgBzAQAfAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIQAAYJSg6IKADTAAAQAAYJSg6IKADTAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCgkJHQABLgAECgYJBgAPAAAAAA==.Saphroniå:BAAALgAECgMJAwAAAA==.Sarnt:BAAALgAECggJCwAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxzVDgBwAgAGAAkJjxzVDgBwAgAFAAMJSwuOmgB8AAABLgAECgkJGwAdAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAgJEgADAMwaAA==.',
Sc='Schattën:BAABLgAECn8fAAIXAAgJIg3GNwBPAQAXAAgJIg3GNwBPAQAAAA==.Scibiol:BAAALgAECgUJBQAAAA==.',
Se='Selvina:BAAALgAECgYJBgAAAA==.Senseideath:BAAALgAFFAIJAgABLgADCgcJBwAPAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAgAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shadowinder:BAAALgAECgEJAQAAAA==.Shadowmortis:BAAALgAECgUJCQAAAA==.Shaka:BAAALgAECgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgcJCwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBmJlgCVAAADAAIJXBmJlgCVAAABLgAFFAYJHgAIANMeAA==.Shirokhan:BAABLgAECn8qAAIIAAgJjB12LwBbAgAIAAgJjB12LwBbAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sialle:BAAALgAECgkJCQAAAA==.Sidewinderx:BAAALgAECgUJBQAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8NAAIDAAQJEhxAOwBeAQADAAQJEhxAOwBeAQAuAAQKf04AAwMACQkNJfsCAGIDAAMACQkNJfsCAGIDAAQAAwmhGR9HAJoAAAAA.Sinmage:BAABLgAECn8YAAIIAAkJUCAgAgD7AgAIAAkJUCAgAgD7AgABLgAFFAQJDQADABIcAA==.',
Sn='Snagglespark:BAACLgAFFH8VAAISAAYJQxmpGgBGAQASAAYJQxmpGgBGAQAuAAQKf00AAxIACQmvIdgBAGwCABIACQmvIdgBAGwCABEAAQkSDdHeACoAAAAA.Sneakytacoss:BAAALgAECgYJBgABLgAFFAEJAQAPAAAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8tAAIBAAkJ7Rr9HABmAgABAAkJ7Rr9HABmAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwAPAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCQABLgAECgYJCgAPAAAAAA==.Spicyfeet:BAAALgADCgcJBwAAAA==.Spinna:BAAALgAECgUJCAAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A0+KwAEAQAHAAgJ3A0+KwAEAQAAAA==.Starvnmarvn:BAAALgAECgYJDQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Steady:BAAALgAECgIJBAAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAUJFAAZAN4SAA==.Stormmonk:BAAALgAECgEJAQAAAA==.Stormybonk:BAAALgAECgUJBQAAAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xpLCQBUAgAKAAgJ3xpLCQBUAgAAAA==.Sunwing:BAAALgAECgUJCgAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8zAAMnAAkJdhU7AgCCAQAdAAgJVhFGZACfAQAnAAYJChs7AgCCAQAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJEAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg9IJwCXAQANAAgJSg9IJwCXAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgAECgEJAQAAAA==.Takato:BAAALgADCgMJAwAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAACLgAFFH8FAAIWAAIJaxbZIACRAAAWAAIJaxbZIACRAAAuAAQKfzEAAhYACQkcG9IOAP4BABYACQkcG9IOAP4BAAAA.Tarenus:BAAALgAECggJCwAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAACLgAFFH8TAAMKAAQJIhoACQALAQAKAAQJIhoACQALAQAXAAIJlAGiYQBPAAAuAAQKf1EAAwoACQlRIjYAADsDAAoACQlRIjYAADsDABcAAQkfAd0cAAoAAAAA.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thera:BAAALgAECgMJAwABLgAECgYJCgAPAAAAAA==.Thiccpickles:BAAALgAECgMJAwABLgAFFAMJCgARAJAiAA==.Thornpaw:BAAALgAECgUJBQAAAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.Thunderbolt:BAAALgAFFAIJAgABLgADCgcJBwAPAAAAAA==.Thymós:BAAALgAECgcJDgAAAA==.',
Ti='Tiffina:BAAALgAFFAIJAgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Tiffzen:BAAALgAECgQJBAAAAA==.Tinyfaith:BAAALgAECgYJCgAAAA==.Titum:BAABLgAFFH8PAAMmAAUJRxFaFABsAAADAAUJRxGNXAAPAQAmAAIJXQNaFABsAAABLgAFFAcJGAADAAEQAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJFAANAGAdAA==.Trillion:BAAALgAECgYJBgABLgAFFAMJCAADAEYUAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8GAAIcAAIJASL6fgC4AAAcAAIJASL6fgC4AAAuAAQKfywAAhwACAlOJAMYALMCABwACAlOJAMYALMCAAAA.',
Tu='Tuckerherout:BAAALgAECgEJAwAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twistmyrunes:BAAALgAECgQJBAAAAA==.Twixx:BAABLgAFFH8cAAInAAQJchdrDAA3AQAnAAQJchdrDAA3AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAACLgAFFH8FAAIDAAIJJAFYvABSAAADAAIJJAFYvABSAAAuAAQKfxsAAwQACAnGB80jAJMAAAMACAnCBzabAAcBAAQABwmwAs0jAJMAAAAA.',
Ud='Uddercover:BAABLgAECn8bAAIeAAYJ7RSsKQBKAQAeAAYJ7RSsKQBKAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Ug='Ugebooge:BAAALgAECgQJBQAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAaAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQAPAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8PAAIdAAcJExi1FgCQAQAdAAcJExi1FgCQAQAuAAQKfxwAAx0ABgkdJuY9AEACAB0ABgkdJuY9AEACACQAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBGjOQAqAQANAAYJQg+jOQAqAQACAAQJMA/9WADQAAAOAAIJ4QcijQAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8IAAIkAAMJxxDFKwCcAAAkAAMJxxDFKwCcAAAuAAQKfyIAAiQACAn2GwgUANMBACQACAn2GwgUANMBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAABLgAECn8XAAIbAAkJexRnFgBYAgAbAAkJexRnFgBYAgABLgAFFAYJFQAXAGoRAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAIJAgAPAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn8/AAIOAAkJ4SABAQDJAgAOAAkJ4SABAQDJAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
['Vä']='Väder:BAAALgAECgIJAgAAAA==.',
Wa='Walkerboah:BAABLgAECn81AAMDAAkJ7xKPOQD0AQADAAkJ7xKPOQD0AQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAABLgAECgEJAQAPAAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBpxqAAtAQAIAAYJdBpxqAAtAQAAAA==.',
Wi='Windswept:BAAALgAECgIJAwAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgkJIQARAPEgAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAkJGwATAAIkAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAkJGwATAAIkAA==.Xeromus:BAABLgAECn86AAMGAAkJvBwMBACSAQAGAAkJvBwMBACSAQAFAAIJ8wSjygA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgQJCgAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAABLgAECn8fAAMRAAkJTRt+AwA6AgARAAgJUBp+AwA6AgASAAQJHQxoHQBDAAAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMbAAkJ1RjAHgAMAgAbAAkJ1RjAHgAMAgAQAAIJkwHYWQAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAYJEgATAL0gAA==.Zarika:BAACLgAFFH8GAAIoAAMJfSIrBgAsAQAoAAMJfSIrBgAsAQAuAAQKfxoAAygACAnJIdACAIcCACgACAnJIdACAIcCAB4ABAmGEh5OALoAAAEuAAUUCQkbABMAAiQA.Zarì:BAACLgAFFH8bAAITAAkJAiSVAADgAgATAAkJAiSVAADgAgAuAAQKfx4AAhMACQkTJg4DAGUDABMACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAYJEgATAL0gAA==.',
Ze='Zeblaw:BAACLgAFFH8GAAIIAAIJOAn/swBqAAAIAAIJOAn/swBqAAAuAAQKfzAAAggACAkHGbBPAO0BAAgACAkHGbBPAO0BAAAA.Zekmal:BAABLgAFFH8GAAITAAQJHwbIEgB4AAATAAQJHwbIEgB4AAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgAECgUJCQAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8SAAITAAYJvSDCAgCgAQATAAYJvSDCAgCgAQAuAAQKf0MABBMACQlnJVgBAGcDABMACQlnJVgBAGcDABQABQlHEvFFAOMAABgAAQm4D/FrACoAAAAA.',
['Zä']='Zäo:BAAALgAECgEJAQABLgAFFAYJEgATAL0gAA==.',
['Ðä']='Ðärëðëvïl:BAAALgAECgQJCAABLgADCgcJBwAPAAAAAA==.',
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
