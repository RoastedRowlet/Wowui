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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Evoker-Augmentation','Paladin-Retribution','Shaman-Elemental','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Rogue-Subtlety','Druid-Feral','Warrior-Arms','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abyssia:BAABLgAECn8UAAIBAAcJhhmFRgCbAQABAAcJhhmFRgCbAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8gAAICAAgJXhRzHwCxAQACAAgJXhRzHwCxAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECgcJBwAAAA==.Alcha:BAABLgAECn8nAAMDAAkJaBsrJQA9AgADAAkJuRgrJQA9AgAEAAcJoBosCQCaAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgkJJwADAGgbAA==.Alenndar:BAABLgAECn8VAAIFAAcJHBHnRQBkAQAFAAcJHBHnRQBkAQAAAA==.Alexdaddario:BAABLgAECn8hAAMGAAYJQCK1HQDBAQAGAAYJQCK1HQDBAQAHAAIJ4gi8WQA+AAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECgkJJwADAGgbAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexMTYQCkAQAIAAgJexMTYQCkAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8UAAMKAAcJrhIvEAC1AQAKAAcJrhIvEAC1AQALAAEJgwddJQAsAAABLgAECggJLAACACseAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8qAAIMAAgJcyX5AQDgAgAMAAgJcyX5AQDgAgAAAA==.Annalease:BAAALgAECgIJBAAAAA==.Anticlimax:BAABLgAECn8oAAMBAAgJ2xLpUwByAQABAAgJ2xLpUwByAQAMAAEJTgZ9NgAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJCwAAAA==.',
Ap='Apparition:BAACLgAFFH8FAAINAAMJtAXhMACSAAANAAMJtAXhMACSAAAuAAQKfyQAAw0ACQnDGMkLAJUCAA0ACQnDGMkLAJUCAA4ABQmVCvFgAGYAAAAA.Apprentice:BAACLgAFFH8SAAIIAAQJZCFPNQBrAQAIAAQJZCFPNQBrAQAuAAQKfy8AAggACAleJX0QAOUCAAgACAleJX0QAOUCAAAA.',
Ar='Arale:BAAALgADCgQJBAABLgAECgkJJQAPABoaAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/4dAB1AQAIAAgJpw/4dAB1AQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8JAAIQAAQJdw6oMgD2AAAQAAQJdw6oMgD2AAAuAAQKfxwAAhAACQlKHWsWAGICABAACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgEJAgABLgAECgQJBwARAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8GAAIQAAMJkAjrSQCrAAAQAAMJkAjrSQCrAAAuAAQKfzoAAhAACQntFW8ZAGUCABAACQntFW8ZAGUCAAAA.',
Av='Avdol:BAAALgAFFAEJAgABLgAFFAcJEQADAIEcAA==.Avienndha:BAABLgAECn8oAAIMAAgJLxz5BQAkAgAMAAgJLxz5BQAkAgAAAA==.',
Aw='Awake:BAABLgAECn8WAAMSAAkJxhVlFAACAgASAAkJgRRlFAACAgATAAMJ4wznbQCLAAAAAA==.',
Az='Azgrunga:BAACLgAFFH8GAAIUAAMJkg/DLgDUAAAUAAMJkg/DLgDUAAAuAAQKfy8AAhQACQlVGjYaAAgCABQACQlVGjYaAAgCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwAAAA==.Benderbrod:BAAALgAECgEJAQAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8fAAIUAAcJtBp2OQDBAQAUAAcJtBp2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8vAAIQAAgJqB0oFACQAgAQAAgJqB0oFACQAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIVAAkJkh8wBQDtAgAVAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8GAAIWAAMJeg92NwDFAAAWAAMJeg92NwDFAAAuAAQKfxoAAhYACQl5HC4KAJwCABYACQl5HC4KAJwCAAEuAAQKCQkcABcAKRIA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgAECgUJBQAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.Cerberus:BAAALgAECgMJAwABLgADCgcJBwARAAAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIQAAMJvRSAQwC9AAAQAAMJvRSAQwC9AAAuAAQKfzMAAxAACAnmG6skABgCABAACAnmG6skABgCABgABglnGJ86AC8BAAAA.Cheesefries:BAABLgAECn8sAAMZAAgJqR7IDACvAgAZAAgJqR7IDACvAgATAAYJ0R02HQCqAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhZqPACPAQAFAAcJrhZqPACPAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMTAAkJDRdtGgDBAQATAAYJRBptGgDBAQASAAcJaQt7OQADAQAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMZAAgJ3RFjMgB/AQAZAAgJ3RFjMgB/AQASAAYJ1QWWUQCrAAAAAA==.Clear:BAAALgADCgIJAgAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgcJBwARAAAAAA==.Cokegirll:BAABLgAECn8ZAAIaAAgJCxK2RAC8AQAaAAgJCxK2RAC8AQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJJQATAAgaAA==.Creamie:BAABLgAECn8lAAITAAgJCBrmFwDXAQATAAgJCBrmFwDXAQAAAA==.Creamish:BAABLgAECn8aAAIbAAgJlhUQDAAEAgAbAAgJlhUQDAAEAgABLgAECggJJQATAAgaAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMcAAgJ3hRlIQDiAQAcAAgJ3hRlIQDiAQAXAAIJ9A7mcwEwAAAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8HAAIIAAMJng9mcADhAAAIAAMJng9mcADhAAAuAAQKfxgAAwgACQkvD4NQANMBAAgACQkvD4NQANMBAAkAAwm/A6QPAFgAAAAA.',
Da='Dacrus:BAAALgAECgIJBgAAAA==.Dalsen:BAABLgAECn8zAAIHAAkJfhWtDAD2AQAHAAkJfhWtDAD2AQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJMwAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIVAAgJEQ/zHQAqAQAVAAgJEQ/zHQAqAQAAAA==.Daredevil:BAAALgAECgMJBgABLgADCgcJBwARAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgADCgMJBgABLgADCgcJCAARAAAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8uAAMSAAgJIRg0FQD4AQASAAgJIRg0FQD4AQAZAAcJGhgHIgDkAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAECgkJNAADAO8eAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCgAAAA==.Dill:BAABLgAECn9LAAIUAAkJniTiAgAyAwAUAAkJniTiAgAyAwAAAA==.Dimonds:BAAALgAECgIJAgAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBgAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgQJBAABLgAECgUJCAARAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgw1SQDKAAAGAAcJMgw1SQDKAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJCgARAAAAAA==.Dyabolykal:BAAALgAECgQJCAABLgAECgQJCgARAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIXAAkJKRJHXQCeAQAXAAkJKRJHXQCeAQAAAA==.Elly:BAAALgAFFAMJBAAAAA==.Elsharion:BAABLgAECn8VAAMcAAgJ5B0eKAC0AQAcAAgJ5B0eKAC0AQAXAAQJKgsTCwGJAAABLgAFFAcJGgAZAC0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAcJGgAZAC0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAcJGgAZAC0gAA==.Elshie:BAACLgAFFH8aAAIZAAcJLSAiBwBNAgAZAAcJLSAiBwBNAgAuAAQKfxcAAhkACQlBHmENAH4CABkACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8FAAIdAAMJBhHSuwCLAAAdAAMJBhHSuwCLAAABLgAFFAcJEQADAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn9EAAIFAAkJIxusEgClAgAFAAkJIxusEgClAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8bAAISAAYJ+R4bAwDeAQASAAYJ+R4bAwDeAQAuAAQKfz4AAhIACQl5Jn8BAFsDABIACQl5Jn8BAFsDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgADCgIJAgABLgAFFAEJAQARAAAAAA==.Fill:BAABLgAECn8gAAIbAAgJfySfBgBRAgAbAAgJfySfBgBRAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAABLgAECn8kAAITAAgJVRUxHQCqAQATAAgJVRUxHQCqAQABLgAECgkJPAAKAK0dAA==.',
Fo='Foboshi:BAAALgADCgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIcAAkJ0RcyIgDdAQAcAAkJ0RcyIgDdAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJFwATAGAeAA==.',
Ga='Gainz:BAAALgAECgEJAgAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8hAAMOAAgJEQaTQADpAAAOAAgJEQaTQADpAAANAAQJIQUuUwCBAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8/AAITAAkJPiZsAAB7AwATAAkJPiZsAAB7AwAAAA==.Giliaa:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAcJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAECgkJHgAaAJMZAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgMJAwAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8GAAIUAAMJDwVYMwC2AAAUAAMJDwVYMwC2AAAuAAQKfzAAAhQABwldE1M1AF4BABQABwldE1M1AF4BAAAA.Hilazy:BAAALgAECgYJEAAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8eAAMNAAgJhhVZFwD5AQANAAgJhhVZFwD5AQAOAAEJLApveQAxAAAAAA==.Holysheet:BAABLgAFFH8GAAIXAAMJ6A/iXQDTAAAXAAMJ6A/iXQDTAAAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8gAAMFAAgJuhueJAAUAgAFAAcJeRqeJAAUAgAGAAcJWxd2JQCHAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJFwATAGAeAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAARAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8gAAIIAAgJlgbtqAARAQAIAAgJlgbtqAARAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8aAAIIAAgJhwX+oQAdAQAIAAgJhwX+oQAdAQAAAA==.Ihavenofutur:BAAALgAECgYJEgAAAA==.',
Il='Illari:BAAALgAECgYJEAAAAA==.Illidantwo:BAACLgAFFH8XAAIeAAYJIhpjAQCYAQAeAAYJIhpjAQCYAQAuAAQKfzEAAh4ACQlDJBEEADoDAB4ACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIVAAgJPR2GCwAfAgAVAAgJPR2GCwAfAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAQAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8WAAIfAAgJkRLdGwCfAQAfAAgJkRLdGwCfAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAQJEwABAIUYAA==.Jabu:BAAALgAFFAIJAwABLgAFFAQJEwABAIUYAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiUwDwBdAgANAAYJLiUwDwBdAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8XAAIgAAgJWQduHgDuAAAgAAgJWQduHgDuAAAAAA==.Jeryeth:BAABLgAECn8yAAMhAAkJTiIYAgAeAwAhAAkJOyIYAgAeAwAVAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgIJAgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAAALgAECgIJAwAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8hAAIiAAYJOSFqAABRAgAiAAYJOSFqAABRAgAuAAQKfy8AAiIACAloJt0AAGgDACIACAloJt0AAGgDAAAA.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAXAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgAECgUJBQAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQZm2QAkAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAaAF8aAA==.Kiwí:BAABLgAECn8dAAMJAAgJXR2XCABqAQAJAAUJDh2XCABqAQAIAAYJdBa4ewBmAQAAAA==.',
Kr='Krasavice:BAABLgAECn85AAIaAAgJGiS2DwC/AgAaAAgJGiS2DwC/AgAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQARAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8tAAIaAAgJxhSeOwDZAQAaAAgJxhSeOwDZAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAhKOgAbAQABAAYJsAhKOgAbAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8dAAMcAAcJvRKTMQB7AQAcAAcJvRKTMQB7AQAXAAYJ0x5YcwBtAQAAAA==.Lemurshoes:BAAALgAECgcJBwAAAA==.Lena:BAABLgAECn8qAAIaAAkJ4COtCwDjAgAaAAkJ4COtCwDjAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIdAAgJGB1qJACsAgAdAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgADCgcJCAARAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8qAAIQAAgJKCCfDQDSAgAQAAgJKCCfDQDSAgAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAARAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJKgAWAO8kAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8FAAIgAAIJKRH1DgCYAAAgAAIJKRH1DgCYAAAuAAQKfzoAAiAACQmBHqsDALoCACAACQmBHqsDALoCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIjAAgJKgetEwANAQAjAAgJKgetEwANAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQADAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIXAAkJlSHsFQCqAgAXAAkJlSHsFQCqAgAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJCQAQAHcOAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIQAAcJTiG8GABqAgAQAAcJTiG8GABqAgAAAA==.Maximus:BAABLgAECn8mAAIXAAkJQA5yWgClAQAXAAkJQA5yWgClAQAAAA==.',
Me='Mechlil:BAAALgAECgIJAgAAAA==.Meditacoss:BAAALgAECgEJAQABLgAECgYJBgARAAAAAA==.Meelu:BAAALgAECgcJDQABLgAECgkJHAAXACkSAA==.Mellowlizard:BAABLgAFFH8RAAIDAAcJgRzzDAAHAgADAAcJgRzzDAAHAgAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.Metuss:BAABLgAECn8WAAMZAAgJ7R55FABVAgAZAAgJ7R55FABVAgASAAYJ3A+pOAAHAQAAAA==.',
Mi='Mira:BAABLgAECn8sAAIaAAcJMhSYRwCTAQAaAAcJMhSYRwCTAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECggJPQASAGsjAA==.Mkicon:BAABLgAECn8kAAIIAAgJuhFsbwCCAQAIAAgJuhFsbwCCAQAAAA==.Mkultra:BAABLgAECn8lAAMdAAgJSCJPJQBbAgAdAAgJhR5PJQBbAgAkAAcJQx9PGQB6AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8gAAIdAAgJhhJ5UQC8AQAdAAgJhhJ5UQC8AQAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8qAAIlAAgJ+RlaBQASAgAlAAgJ+RlaBQASAgAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzAOvegA7AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn80AAMDAAkJ7x4xDQDXAgADAAkJ7x4xDQDXAgAEAAIJ/w25VABwAAAAAA==.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8gAAMEAAgJtxqPAAA9AgAEAAYJCxiPAAA9AgADAAcJXBk1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKAAQAK4VAA==.Multanni:BAABLgAECn8wAAIYAAgJIxdlIgC5AQAYAAgJIxdlIgC5AQAAAA==.',
My='Myonecrosis:BAABLgAECn8hAAMDAAgJWiIUFAChAgADAAgJWiIUFAChAgAEAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwARAAAAAA==.Nakrog:BAAALgAECgMJBAAAAA==.Napster:BAABLgAECn8mAAQcAAgJ3iS+BQAiAwAcAAgJ3iS+BQAiAwAXAAEJjyYZHAFxAAAiAAEJIA2XSgArAAAAAA==.Nasa:BAACLgAFFH8VAAISAAYJXBxHBgCTAQASAAYJXBxHBgCTAQAuAAQKfxsAAhIACQkJH/QLALwCABIACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgEJAgAAAA==.Nellarixi:BAABLgAECn9BAAIOAAkJNyN9AgAwAwAOAAkJNyN9AgAwAwAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8eAAMWAAgJBRxjAwCvAgAWAAgJBRxjAwCvAgALAAIJpgnuBgCgAAAuAAQKf2AAAxYACQmbJqAAAHwDABYACQmXJqAAAHwDAAsACAklIL8DAN4CAAAA.',
No='Nolwenn:BAABLgAFFH8FAAMNAAIJhgT4NgB0AAANAAIJhgT4NgB0AAAOAAEJ1QAaOAAgAAAAAA==.Nomaa:BAABLgAECn8oAAIPAAgJJALqHAC0AAAPAAgJJALqHAC0AAAAAA==.Nomäd:BAAALgAECgcJEAAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgARAAAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAIYAAcJqA4wQwALAQAYAAcJqA4wQwALAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgwlHgA2AQAHAAkJxgwlHgA2AQAGAAEJ4gOCiQAmAAAgAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAFFAEJAQAAAA==.Oktoberfest:BAABLgAECn8XAAITAAkJYB6OCACZAgATAAkJYB6OCACZAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8gAAIiAAgJ9hIOEwCZAQAiAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECggJCwAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAbAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAFFAEJAQAAAA==.',
Po='Pocahontas:BAABLgAECn8sAAMCAAgJKx7nCgChAgACAAgJKx7nCgChAgAOAAEJEhe2bQBDAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8dAAINAAkJPRhDEABNAgANAAkJPRhDEABNAgAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8LAAIaAAMJaxlUTQDnAAAaAAMJaxlUTQDnAAAuAAQKfykAAhoABwk8I1MRAK4CABoABwk8I1MRAK4CAAAA.Racker:BAAALgAECggJEwAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMUAAUJ8RnGSgB6AQAUAAUJ8RnGSgB6AQAVAAQJUxA6MADCAAAAAA==.Rengots:BAAALgAECgYJEwAAAA==.Renne:BAABLgAECn8jAAIeAAcJyBV5HgDLAQAeAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgUJCgAAAA==.Rokkoz:BAABLgAECn8jAAMHAAgJYhKiJQD/AAAGAAcJthQMNABvAQAHAAgJiAuiJQD/AAAAAA==.Romer:BAAALgAECgcJDQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQAMAAQJGiEQDgBzAQABAAcJmB0mVABxAQAeAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIiAAYJSg6lJADUAAAiAAYJSg6lJADUAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCgYJBgAAAA==.Sarnt:BAAALgAECggJBAAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxyADAB6AgAGAAkJjxyADAB6AgAFAAMJSwsEkQB/AAABLgAECgkJGwAdAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQADAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIWAAgJIg0JMgBNAQAWAAgJIg0JMgBNAQAAAA==.Scibiol:BAAALgADCgkJEgAAAA==.',
Se='Senseideath:BAAALgAFFAIJAgABLgADCgcJBwARAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgQJBAAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBnYgACiAAADAAIJXBnYgACiAAABLgAFFAUJDAAIAA4YAA==.Shirokhan:BAABLgAECn8nAAIIAAgJjB1SLABRAgAIAAgJjB1SLABRAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgAECgIJAgAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8GAAIDAAQJPhuXLQBkAQADAAQJPhuXLQBkAQAuAAQKf0gAAwMACQnzJNUCAF8DAAMACQnzJNUCAF8DAAQAAwmhGR9HAJoAAAAA.',
Sn='Snagglespark:BAACLgAFFH8JAAIYAAQJgRMxHQASAQAYAAQJgRMxHQASAQAuAAQKfzoAAhgACQljHnEKAKQCABgACQljHnEKAKQCAAAA.Sneakytacoss:BAAALgAECgYJBgAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8rAAIBAAkJ8BkCHQBSAgABAAkJ8BkCHQBSAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwARAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCAAAAA==.Spinna:BAAALgAECgEJAgAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A1rJAAIAQAHAAgJ3A1rJAAIAQAAAA==.Starvnmarvn:BAAALgAECgUJCgAAAA==.Starz:BAAALgAECgcJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAQJDgAaAN4SAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xo9CABcAgAKAAgJ3xo9CABcAgAAAA==.Sunwing:BAAALgAECgQJBQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8XAAIdAAgJzQ6xZQCIAQAdAAgJzQ6xZQCIAQAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJDAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg/5IACiAQANAAgJSg/5IACiAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8qAAIVAAgJLBrqDQDzAQAVAAgJLBrqDQDzAQAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAABLgAECn88AAIKAAkJrR3JAgAjAwAKAAkJrR3JAgAjAwAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgMJAwABLgAFFAMJBwAQAJAiAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.Thunderbolt:BAAALgADCgkJCwABLgADCgcJBwARAAAAAA==.Thymós:BAAALgAECgEJAgAAAA==.',
Ti='Tiamat:BAAALgADCgcJBwAAAA==.Tiffina:BAAALgAECggJDwAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8MAAMPAAUJ2wqKDgBxAAADAAUJ2wqpUwALAQAPAAIJXQOKDgBxAAAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJEwARAAAAAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8FAAIXAAIJASKTZADDAAAXAAIJASKTZADDAAAuAAQKfysAAhcACAlOJHQTALkCABcACAlOJHQTALkCAAAA.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twixx:BAABLgAFFH8SAAImAAQJ0haNCAA8AQAmAAQJ0haNCAA8AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAABLgAECn8bAAMEAAgJxgdxHwCZAAADAAgJwgdCjQAWAQAEAAcJsAJxHwCZAAAAAA==.',
Ud='Uddercover:BAABLgAECn8VAAIfAAYJ7RQ4JQBQAQAfAAYJ7RQ4JQBQAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAbAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQARAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIdAAMJiSFYjgDOAAAdAAMJiSFYjgDOAAAuAAQKfxwAAx0ABgkdJuY9AEACAB0ABgkdJuY9AEACACQAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBHaMwAjAQANAAYJQg/aMwAjAQACAAQJMA/9WADQAAAOAAIJ4QfyfAAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8HAAIkAAMJxxBJIgCvAAAkAAMJxxBJIgCvAAAuAAQKfyIAAiQACAn2GzERAN4BACQACAn2GzERAN4BAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAECgkJHAAXACkSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQARAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn8fAAIOAAkJSxarFAALAgAOAAkJSxarFAALAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn8xAAMDAAgJ/BGUUACeAQADAAgJ/BGUUACeAQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBrUlgAwAQAIAAYJdBrUlgAwAQAAAA==.',
Wi='Windswept:BAAALgAECgIJAgAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECggJFwAQAGchAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAcJGAASAKckAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAcJGAASAKckAA==.Xeromus:BAABLgAECn8pAAMGAAgJKRlLGADzAQAGAAgJKRlLGADzAQAFAAIJ8wTxvQA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgMJAwAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgQJBgAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMcAAkJ1RiwGwAQAgAcAAkJ1RiwGwAQAgAiAAIJkwHOUAAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAMJBgASAEskAA==.Zarika:BAABLgAECn8aAAMnAAgJySFnAgCIAgAnAAgJySFnAgCIAgAfAAQJhhIeTgC6AAABLgAFFAcJGAASAKckAA==.Zarì:BAACLgAFFH8YAAISAAcJpyTtAAB9AgASAAcJpyTtAAB9AgAuAAQKfx4AAhIACQkTJg4DAGUDABIACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAMJBgASAEskAA==.',
Ze='Zeblaw:BAACLgAFFH8FAAIIAAIJOAm2ngB0AAAIAAIJOAm2ngB0AAAuAAQKfy8AAggACAkHGRxGAPIBAAgACAkHGRxGAPIBAAAA.Zekmal:BAAALgAFFAQJBAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8GAAISAAMJSySCDQA+AQASAAMJSySCDQA+AQAuAAQKfz0ABBIACQnCJKcBAFQDABIACQnCJKcBAFQDABMABQlHEihBAOQAABkAAQm4D/FrACoAAAAA.',
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
