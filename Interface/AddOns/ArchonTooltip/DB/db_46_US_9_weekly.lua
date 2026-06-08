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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Evoker-Augmentation','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abyssia:BAABLgAECn8VAAIBAAcJRBrqRACsAQABAAcJRBrqRACsAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8mAAICAAgJpRStIACwAQACAAgJpRStIACwAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECggJCAAAAA==.Alcha:BAABLgAECn8oAAMDAAkJihveJgA8AgADAAkJ2xjeJgA8AgAEAAcJoBrcCQCYAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgkJKAADAIobAA==.Alenndar:BAABLgAECn8eAAIFAAgJmxK7NAC/AQAFAAgJmxK7NAC/AQAAAA==.Alexdaddario:BAACLgAFFH8HAAIGAAMJhxUzKQDVAAAGAAMJhxUzKQDVAAAuAAQKfyEAAwYABglAIkcfAMABAAYABglAIkcfAMABAAcAAgniCGxiAD0AAAAA.Alkuhh:BAAALgADCgcJDgABLgAECgkJKAADAIobAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexObZgCpAQAIAAgJexObZgCpAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8XAAMKAAgJQRLXEAC0AQAKAAcJrhLXEAC0AQALAAIJSAqIHABgAAABLgAECggJLAACACceAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8uAAIMAAgJnCUXAgDhAgAMAAgJnCUXAgDhAgAAAA==.Annalease:BAAALgAECgMJBgAAAA==.Anticlimax:BAABLgAECn8rAAMBAAgJChOuUACIAQABAAgJChOuUACIAQAMAAEJTgafOQAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJCwAAAA==.',
Ap='Apparition:BAACLgAFFH8IAAINAAMJPAYENACfAAANAAMJPAYENACfAAAuAAQKfyQAAw0ACQnDGO0MAJICAA0ACQnDGO0MAJICAA4ABQmVCoZpAGUAAAAA.Apprentice:BAACLgAFFH8SAAIIAAQJZCE1PwBhAQAIAAQJZCE1PwBhAQAuAAQKfy8AAggACAleJfcRAOkCAAgACAleJfcRAOkCAAAA.',
Ar='Arale:BAAALgADCgQJBAABLgAECgkJJQAPABoaAA==.Ardrhyes:BAAALgADCgMJAwABLgAECggJNAADAGQUAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/QdQCHAQAIAAgJpw/QdQCHAQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8MAAIQAAQJ6BeuJgAzAQAQAAQJ6BeuJgAzAQAuAAQKfxwAAhAACQlKHWsWAGICABAACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgMJBAABLgAECgQJCwARAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8JAAIQAAMJkAg0VACVAAAQAAMJkAg0VACVAAAuAAQKf0MAAxAACQn2FUYbAGUCABAACQn2FUYbAGUCABIABgndEH1BAB0BAAAA.',
Av='Avdol:BAAALgAFFAEJAgABLgAFFAcJEQADAIEcAA==.Avienndha:BAABLgAECn8sAAIMAAgJLxxeBgAhAgAMAAgJLxxeBgAhAgAAAA==.',
Aw='Awake:BAACLgAFFH8FAAITAAMJ6hAiIQDKAAATAAMJ6hAiIQDKAAAuAAQKfx4AAxMACQntG94JAJsCABMACQntG94JAJsCABQAAwnjDOdtAIsAAAAA.',
Az='Azgrunga:BAACLgAFFH8GAAIVAAMJkg/fMwDNAAAVAAMJkg/fMwDNAAAuAAQKfy8AAhUACQlVGjQcAAUCABUACQlVGjQcAAUCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwAAAA==.Benderbrod:BAAALgAECgUJBgABLgAECgYJBwARAAAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8fAAIVAAcJtBp2OQDBAQAVAAcJtBp2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8yAAIQAAgJoR0BFgCNAgAQAAgJoR0BFgCNAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIWAAkJkh8wBQDtAgAWAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8JAAIXAAMJ1w+FPQC/AAAXAAMJ1w+FPQC/AAAuAAQKfyMAAhcACQlzIMMFAPwCABcACQlzIMMFAPwCAAEuAAQKCQkcABgAKRIA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgAECgUJBQAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIQAAMJvRS0SwCsAAAQAAMJvRS0SwCsAAAuAAQKfzMAAxAACAnmGx0nABcCABAACAnmGx0nABcCABIABglnGNk9AC0BAAAA.Cheesefries:BAABLgAECn8sAAMZAAgJqR72DQCuAgAZAAgJqR72DQCuAgAUAAYJ0R2OHgCoAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrha8PgCOAQAFAAcJrha8PgCOAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMUAAkJDRfQGwC+AQAUAAYJQxrQGwC+AQATAAcJaQvbPQD7AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMZAAgJ3RERNwB/AQAZAAgJ3RERNwB/AQATAAYJ1QVFVwClAAAAAA==.Clear:BAAALgADCggJCgAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgcJBwARAAAAAA==.Cokegirll:BAABLgAECn8ZAAIaAAgJCxLWSgC1AQAaAAgJCxLWSgC1AQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJKAAUAF8aAA==.Creamie:BAABLgAECn8oAAIUAAgJXxoyFwDnAQAUAAgJXxoyFwDnAQAAAA==.Creamish:BAABLgAECn8aAAIbAAgJlhUQDAAEAgAbAAgJlhUQDAAEAgABLgAECggJKAAUAF8aAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMcAAgJ3hQrIwDgAQAcAAgJ3hQrIwDgAQAYAAIJ9A7cfAExAAAAAA==.Crumbshot:BAAALgAECgEJAQAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8IAAIIAAMJng9IeQDeAAAIAAMJng9IeQDeAAAuAAQKfxgAAwgACQkvDwhRAOIBAAgACQkvDwhRAOIBAAkAAwm/AwoRAFYAAAAA.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn8zAAIHAAkJfhUwDgDvAQAHAAkJfhUwDgDvAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJMwAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIWAAgJEQ/nHwAkAQAWAAgJEQ/nHwAkAQAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgADCgMJBgABLgADCgcJCAARAAAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8uAAMTAAgJIRjDFgDyAQATAAgJIRjDFgDyAQAZAAcJGhgWJQDlAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAECgkJNAADAO8eAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCgAAAA==.Dill:BAABLgAECn9LAAIVAAkJniRzAwAtAwAVAAkJniRzAwAtAwAAAA==.Dimonds:BAAALgAECgMJBAAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBgAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgQJBAABLgAECgUJCAARAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgwmTQDJAAAGAAcJMgwmTQDJAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJCgARAAAAAA==.Dyabolykal:BAAALgAECgQJCAABLgAECgQJCgARAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIYAAkJKRIkZACdAQAYAAkJKRIkZACdAQAAAA==.Elly:BAABLgAFFH8GAAIdAAMJ7QZqKADQAAAdAAMJ7QZqKADQAAAAAA==.Elsharion:BAABLgAECn8VAAMcAAgJ5B0WKgCzAQAcAAgJ5B0WKgCzAQAYAAQJKguSEwGSAAABLgAFFAgJGwAZAP0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAgJGwAZAP0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAgJGwAZAP0gAA==.Elshie:BAACLgAFFH8bAAIZAAgJ/SByBACyAgAZAAgJ/SByBACyAgAuAAQKfxcAAhkACQlBHmENAH4CABkACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8IAAIeAAQJyxfITwBDAQAeAAQJyxfITwBDAQABLgAFFAcJEQADAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn9EAAIFAAkJIxu+EwCkAgAFAAkJIxu+EwCkAgAAAA==.Evermoreivy:BAAALgAECgMJAwAAAA==.',
Fa='Fastasheet:BAACLgAFFH8gAAITAAYJmB8fAwD/AQATAAYJmB8fAwD/AQAuAAQKfz4AAhMACQl5JrwBAFUDABMACQl5JrwBAFUDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgADCgIJAgABLgAFFAEJAQARAAAAAA==.Fill:BAABLgAECn8gAAIbAAgJfyQ5BwBPAgAbAAgJfyQ5BwBPAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAABLgAECn8lAAIUAAgJVRWZHgCoAQAUAAgJVRWZHgCoAQABLgAFFAMJBgAKAAYYAA==.',
Fo='Foboshi:BAAALgAECgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIcAAkJ0RcIJADbAQAcAAkJ0RcIJADbAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.Fuzzywuzzy:BAAALgAECgIJAgAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJGAAUABofAA==.',
Ga='Gainz:BAAALgAECgEJAgAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8lAAMOAAgJSAifOgAfAQAOAAgJSAifOgAfAQANAAQJIQWEVQCUAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8/AAIUAAkJPiaDAAB6AwAUAAkJPiaDAAB6AwAAAA==.Giliaa:BAAALgAECgcJBwAAAA==.Gilljoww:BAAALgADCgEJAQAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.Gireigtulb:BAAALgAECgIJAgAAAA==.',
Gn='Gnz:BAAALgAFFAMJAwAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAcJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAECgkJHgAaAJMZAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halløw:BAAALgAECgQJBAAAAA==.Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgMJBAAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8KAAIVAAQJJwW+KgDzAAAVAAQJJwW+KgDzAAAuAAQKfzoAAhUACQkxFm0VAD0CABUACQkxFm0VAD0CAAAA.Hilazy:BAABLgAECn8UAAIbAAgJDRiqDgC5AQAbAAgJDRiqDgC5AQAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8fAAMNAAkJpxRjEwA5AgANAAkJpxRjEwA5AgAOAAEJLAoJggAwAAAAAA==.Holysheet:BAABLgAFFH8GAAIYAAMJ6A/fZwDOAAAYAAMJ6A/fZwDOAAAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8jAAMFAAgJuhs+JgATAgAFAAcJeRo+JgATAgAGAAcJWxdlJwCGAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJGAAUABofAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAARAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8hAAIIAAkJmwZnhQBmAQAIAAkJmwZnhQBmAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8bAAIIAAgJpgVroQA0AQAIAAgJpgVroQA0AQAAAA==.Ihavenofutur:BAAALgAECgYJEgAAAA==.',
Il='Illari:BAAALgAECgYJEgAAAA==.Illidantwo:BAACLgAFFH8bAAIfAAcJZRhuAgAIAgAfAAcJZRhuAgAIAgAuAAQKfzEAAh8ACQlDJBEEADoDAB8ACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIWAAgJPB2ODAAXAgAWAAgJPB2ODAAXAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAQAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8YAAIdAAkJgxM7FAD0AQAdAAkJgxM7FAD0AQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAUJFAABABYZAA==.Jabu:BAAALgAFFAIJAwABLgAFFAUJFAABABYZAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiUiEABiAgANAAYJLiUiEABiAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8YAAIgAAkJ4wfaGwAZAQAgAAkJ4wfaGwAZAQAAAA==.Jeryeth:BAABLgAECn8yAAMhAAkJTiJXAgAaAwAhAAkJOyJXAgAaAwAWAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgIJBAAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAAALgAFFAIJAwAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAECLgAFFH8jAAIiAAcJzR83AACmAgAiAAcJzR83AACmAgAuAAQKfy8AAiIACAloJt0AAGgDACIACAloJt0AAGgDAAAA.Kanda:BAAALgAECgcJBQAAAA==.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAYAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgAECggJCQAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQbD5wAgAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAaAF8aAA==.Kiwí:BAABLgAECn8dAAMJAAgJXR2XCABqAQAJAAUJDh2XCABqAQAIAAYJdBa5hgBjAQAAAA==.',
Kr='Krasavice:BAABLgAECn89AAIaAAgJGiQbEADGAgAaAAgJGiQbEADGAgAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQARAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8uAAIaAAgJMhVIQADWAQAaAAgJMhVIQADWAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAhPQgARAQABAAYJsAhPQgARAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8lAAMYAAkJ7xlJJwBbAgAYAAkJ7xlJJwBbAgAcAAcJvRKkMwB6AQAAAA==.Lemurshoes:BAAALgAFFAEJAgAAAA==.Lena:BAABLgAECn8qAAIaAAkJ4CNxDQDdAgAaAAkJ4CNxDQDdAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIeAAgJGB1qJACsAgAeAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgADCgcJCAARAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8qAAIQAAgJKCAADwDPAgAQAAgJKCAADwDPAgAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAARAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJMgAXAAMlAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8GAAIgAAMJ+hPdCwDiAAAgAAMJ+hPdCwDiAAAuAAQKfzoAAiAACQmBHioEALcCACAACQmBHioEALcCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIjAAgJKgc2FQAFAQAjAAgJKgc2FQAFAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQADAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIYAAkJlSFpGACnAgAYAAkJlSFpGACnAgAAAA==.Mankirijilla:BAAALgAECgMJBAAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJDAAQAOgXAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIQAAcJTiHUGgBoAgAQAAcJTiHUGgBoAgAAAA==.Maximus:BAABLgAECn8nAAIYAAkJQA5YXQCsAQAYAAkJQA5YXQCsAQAAAA==.',
Me='Mechlil:BAAALgAECgIJBAAAAA==.Meditacoss:BAAALgAFFAEJAQAAAA==.Meelu:BAABLgAECn8WAAMFAAkJGgqdSgBaAQAFAAkJGgqdSgBaAQAGAAEJRQJCnwAXAAABLgAECgkJHAAYACkSAA==.Mellowlizard:BAABLgAFFH8RAAIDAAcJgRyQEgD9AQADAAcJgRyQEgD9AQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.Metuss:BAABLgAECn8YAAMZAAgJgR96FABlAgAZAAgJgR96FABlAgATAAYJ3A/dOwADAQAAAA==.',
Mi='Mira:BAABLgAECn8vAAIaAAcJsRZzWACOAQAaAAcJsRZzWACOAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECgkJQQATAIAgAA==.Mkicon:BAABLgAECn8oAAIIAAgJMhL9awCdAQAIAAgJMhL9awCdAQAAAA==.Mkultra:BAABLgAECn8mAAMeAAgJSCI9KABYAgAeAAgJhR49KABYAgAkAAcJQx8dGwB3AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8kAAIeAAgJCRObVAC/AQAeAAgJCRObVAC/AQAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8tAAIlAAgJsRo4BQAhAgAlAAgJsRo4BQAhAgAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzAOwggA3AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn80AAMDAAkJ7x6CDgDTAgADAAkJ7x6CDgDTAgAEAAIJ/w25VABwAAAAAA==.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8hAAMEAAkJHxqPAAA9AgAEAAYJCxiPAAA9AgADAAgJ3xg1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKAAQAK4VAA==.Multanni:BAABLgAECn8zAAISAAgJohmDHQDoAQASAAgJohmDHQDoAQAAAA==.',
My='Myonecrosis:BAABLgAECn8lAAMDAAgJWiK3FQCdAgADAAgJWiK3FQCdAgAEAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwARAAAAAA==.Nakrog:BAAALgAECgMJBAAAAA==.Napster:BAABLgAECn8nAAQcAAkJ/iRIBgAgAwAcAAgJ3iRIBgAgAwAYAAIJ4SEr5gDJAAAiAAEJIA1rTgArAAAAAA==.Nasa:BAACLgAFFH8VAAITAAYJXBxzBwCQAQATAAYJXBxzBwCQAQAuAAQKfxsAAhMACQkJH/QLALwCABMACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgEJAgAAAA==.Nellarixi:BAABLgAECn9BAAIOAAkJNyPhAgA2AwAOAAkJNyPhAgA2AwAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8iAAMXAAgJ8hvcBACcAgAXAAgJ8hvcBACcAgALAAIJpgnuBgCgAAAuAAQKf2AAAxcACQmbJrIAAIYDABcACQmXJrIAAIYDAAsACAklIL8DAN4CAAAA.',
No='Nolwenn:BAACLgAFFH8HAAMNAAMJ8wWmMgCpAAANAAMJ8wWmMgCpAAAOAAEJ1QAzPQAfAAAuAAQKfxUAAg0ABwmtGJAYAAACAA0ABwmtGJAYAAACAAAA.Nomaa:BAABLgAECn8sAAIPAAgJOwKJHgC5AAAPAAgJOwKJHgC5AAAAAA==.Nomäd:BAAALgAECgcJEAAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgARAAAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAISAAcJqA5XRwAGAQASAAcJqA5XRwAGAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgx/IQAvAQAHAAkJxgx/IQAvAQAGAAEJ4gOCiQAmAAAgAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAFFAEJAgAAAA==.Oktoberfest:BAABLgAECn8YAAIUAAkJGh94CACjAgAUAAkJGh94CACjAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8gAAIiAAgJ9hIOEwCZAQAiAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECggJCwAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAbAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAFFAIJAwAAAA==.',
Po='Pocahontas:BAABLgAECn8sAAMCAAgJJx72CwCZAgACAAgJJx72CwCZAgAOAAEJEhcBdgBDAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8dAAINAAkJPRhIEQBSAgANAAkJPRhIEQBSAgAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quepaspete:BAAALgAFFAEJAQAAAA==.Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8LAAIaAAMJaxmkVwDiAAAaAAMJaxmkVwDiAAAuAAQKfy0AAhoABwk8I1MRAK4CABoABwk8I1MRAK4CAAAA.Racker:BAABLgAECn8UAAIVAAgJQBURIQDiAQAVAAgJQBURIQDiAQAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMVAAUJ8RnGSgB6AQAVAAUJ8RnGSgB6AQAWAAQJUxA6MADCAAAAAA==.Rengots:BAABLgAECn8WAAIaAAYJ3hBvYABGAQAaAAYJ3hBvYABGAQAAAA==.Renne:BAABLgAECn8jAAIfAAcJyBV5HgDLAQAfAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgYJCwAAAA==.Rokkoz:BAABLgAECn8jAAMHAAgJYhIbKQD9AAAGAAcJthQMNABvAQAHAAgJiAsbKQD9AAAAAA==.Romer:BAABLgAECn8WAAIZAAkJvQisSQArAQAZAAkJvQisSQArAQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQABAAcJmB3hVwBzAQAMAAQJGiEQDgBzAQAfAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIiAAYJSg6aJgDTAAAiAAYJSg6aJgDTAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCggJDgAAAA==.Sarnt:BAAALgAECggJCwAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxywDQB1AgAGAAkJjxywDQB1AgAFAAMJSwu2lAB/AAABLgAECgkJGwAeAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQADAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIXAAgJIg01NABWAQAXAAgJIg01NABWAQAAAA==.Scibiol:BAAALgADCgkJGwAAAA==.',
Se='Senseideath:BAAALgAFFAIJAgABLgADCgcJBwARAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgQJBAAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBk2iwCZAAADAAIJXBk2iwCZAAABLgAFFAUJDgAIAOkYAA==.Shirokhan:BAABLgAECn8nAAIIAAgJjB1ULwBVAgAIAAgJjB1ULwBVAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sialle:BAAALgAECgkJCQAAAA==.Sidewinderx:BAAALgAECgMJAwAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8HAAIDAAQJJRvFNQBZAQADAAQJJRvFNQBZAQAuAAQKf0gAAwMACQnzJEIDAFoDAAMACQnzJEIDAFoDAAQAAwmhGR9HAJoAAAAA.',
Sn='Snagglespark:BAACLgAFFH8NAAISAAQJrhWIHgAZAQASAAQJrhWIHgAZAQAuAAQKfzwAAhIACQnsHn0KAK0CABIACQnsHn0KAK0CAAAA.Sneakytacoss:BAAALgAECgYJBgABLgAFFAEJAQARAAAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8tAAIBAAkJ7RpkGwBmAgABAAkJ7RpkGwBmAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwARAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCAAAAA==.Spinna:BAAALgAECgQJBgAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A3NJwAFAQAHAAgJ3A3NJwAFAQAAAA==.Starvnmarvn:BAAALgAECgYJDQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAQJDgAaAN4SAA==.Stormmonk:BAAALgAECgEJAQAAAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xqkCABcAgAKAAgJ3xqkCABcAgAAAA==.Sunwing:BAAALgAECgQJBQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8bAAIeAAgJtw9pZwCQAQAeAAgJtw9pZwCQAQAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJEAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg/FIwCiAQANAAgJSg/FIwCiAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8uAAIWAAgJnhrCDQADAgAWAAgJnhrCDQADAgAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAACLgAFFH8GAAMKAAMJBhgPHADHAAAKAAIJFCIPHADHAAAXAAIJlAGxWABYAAAuAAQKf0EAAgoACQlVID8CAE0DAAoACQlVID8CAE0DAAAA.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgMJAwABLgAFFAMJBwAQAJAiAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.Thunderbolt:BAAALgADCgkJCwABLgADCgcJBwARAAAAAA==.Thymós:BAAALgAECgEJAgAAAA==.',
Ti='Tiamat:BAAALgADCgcJBwAAAA==.Tiffina:BAAALgAFFAIJAgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8MAAMPAAUJ2wpjEQBuAAADAAUJ2wo5XAAAAQAPAAIJXQNjEQBuAAAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJEwARAAAAAA==.Trillion:BAAALgADCgUJBQABLgAECgkJNAADAO8eAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8FAAIYAAIJASIWcAC+AAAYAAIJASIWcAC+AAAuAAQKfysAAhgACAlOJJoVALgCABgACAlOJJoVALgCAAAA.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twixx:BAABLgAFFH8WAAImAAQJxRZJCgA0AQAmAAQJxRZJCgA0AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAABLgAECn8bAAMEAAgJxgdWIQCYAAADAAgJwgc/kwARAQAEAAcJsAJWIQCYAAAAAA==.',
Ud='Uddercover:BAABLgAECn8bAAIdAAYJ7RR1JwBKAQAdAAYJ7RR1JwBKAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAbAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQARAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIeAAMJiSGwnADMAAAeAAMJiSGwnADMAAAuAAQKfxwAAx4ABgkdJuY9AEACAB4ABgkdJuY9AEACACQAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBFpNQAyAQANAAYJQg9pNQAyAQACAAQJMA/9WADQAAAOAAIJ4QcYhQAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8HAAIkAAMJxxCCJgCqAAAkAAMJxxCCJgCqAAAuAAQKfyIAAiQACAn2G5wSANoBACQACAn2G5wSANoBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAECgkJHAAYACkSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQARAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn8mAAIOAAkJnxj9DwBVAgAOAAkJnxj9DwBVAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn80AAMDAAgJZBRrRwDAAQADAAgJZBRrRwDAAQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBr8oAA1AQAIAAYJdBr8oAA1AQAAAA==.',
Wi='Windswept:BAAALgAECgIJAgAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAAAAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAgJGQATAMokAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAgJGQATAMokAA==.Xeromus:BAABLgAECn8sAAMGAAgJKRmrGQDyAQAGAAgJKRmrGQDyAQAFAAIJ8wTgwwA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgMJBgAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgQJCgAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMcAAkJ1Rg5HQAOAgAcAAkJ1Rg5HQAOAgAiAAIJkwEZVQAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAMJBgATAEskAA==.Zarika:BAACLgAFFH8GAAInAAMJfSJRBQAyAQAnAAMJfSJRBQAyAQAuAAQKfxoAAycACAnJIaECAIYCACcACAnJIaECAIYCAB0ABAmGEh5OALoAAAEuAAUUCAkZABMAyiQA.Zarì:BAACLgAFFH8ZAAITAAgJyiRiAADpAgATAAgJyiRiAADpAgAuAAQKfx4AAhMACQkTJg4DAGUDABMACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAMJBgATAEskAA==.',
Ze='Zeblaw:BAACLgAFFH8FAAIIAAIJOAkbqAB0AAAIAAIJOAkbqAB0AAAuAAQKfy8AAggACAkHGWZKAPYBAAgACAkHGWZKAPYBAAAA.Zekmal:BAAALgAFFAQJBAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8GAAITAAMJSyRMDwA5AQATAAMJSyRMDwA5AQAuAAQKfz0ABBMACQnCJOsBAE4DABMACQnCJOsBAE4DABQABQlHEpVDAOQAABkAAQm4D/FrACoAAAAA.',
['Ðä']='Ðärëðëvïl:BAAALgAECgMJBgAAAA==.',
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
