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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','Evoker-Augmentation','Monk-Mistweaver','Hunter-BeastMastery','Shaman-Enhancement','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Hunter-Survival','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abyssia:BAABLgAECn8VAAIBAAcJRBqoRwCsAQABAAcJRBqoRwCsAQAAAA==.',
Ac='Acupuncher:BAAALgAECgYJDAAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8qAAICAAgJpRQAIgCuAQACAAgJpRQAIgCuAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alarick:BAAALgADCgMJAwAAAA==.Alberio:BAAALgAECggJDAAAAA==.Alcha:BAABLgAECn8oAAMDAAkJihsjKAA6AgADAAkJ2xgjKAA6AgAEAAcJoBqWCgCVAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgkJKAADAIobAA==.Alenndar:BAABLgAECn8nAAIFAAkJIRKyKgD+AQAFAAkJIRKyKgD+AQAAAA==.Alexdaddario:BAACLgAFFH8KAAIGAAMJkhd3KwDYAAAGAAMJkhd3KwDYAAAuAAQKfyEAAwYABglAIrggAL8BAAYABglAIrggAL8BAAcAAgniCMJpAD0AAAAA.Alkuhh:BAAALgADCgcJDgABLgAECgkJKAADAIobAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8nAAMIAAgJexOTawChAQAIAAgJexOTawChAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAABLgAECn8XAAMKAAgJQRJLEQCyAQAKAAcJrhJLEQCyAQALAAIJSgr5HQBcAAABLgAECgkJLQACAO8cAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8wAAIMAAgJnCVBAgDgAgAMAAgJnCVBAgDgAgAAAA==.Annalease:BAAALgAECgMJBgAAAA==.Anticlimax:BAABLgAECn8sAAMBAAkJoRJ8PwDHAQABAAkJoRJ8PwDHAQAMAAEJTgZaPAAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJCwAAAA==.',
Ap='Apparition:BAACLgAFFH8IAAINAAMJPAboNwCfAAANAAMJPAboNwCfAAAuAAQKfyQAAw0ACQnDGJgNAJECAA0ACQnDGJgNAJECAA4ABQmVCglvAGEAAAAA.Apprentice:BAACLgAFFH8YAAIIAAYJ+xuXLQC2AQAIAAYJ+xuXLQC2AQAuAAQKfy8AAggACAleJRYTAOUCAAgACAleJRYTAOUCAAAA.',
Ar='Arale:BAAALgADCgUJBgABLgAECgkJJgAPABoaAA==.Ardrhyes:BAAALgADCgMJAwABLgAECgkJNQADAO8SAA==.Argonar:BAABLgAECn8bAAIIAAgJpw/YewB9AQAIAAgJpw/YewB9AQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.Artrael:BAAALgAFFAIJAgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8PAAIQAAQJPR7AIgBbAQAQAAQJPR7AIgBbAQAuAAQKfxwAAhAACQlKHWsWAGICABAACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgMJBAABLgAECgQJDwARAAAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAACLgAFFH8KAAIQAAMJkAgZWwCQAAAQAAMJkAgZWwCQAAAuAAQKf0MAAxAACQn2FZocAGQCABAACQn2FZocAGQCABIABgndELpEABwBAAAA.',
Av='Avdol:BAAALgAFFAEJAgABLgAFFAcJEQADAIEcAA==.Avienndha:BAABLgAECn8uAAIMAAgJRB0GBgA4AgAMAAgJRB0GBgA4AgAAAA==.',
Aw='Awake:BAACLgAFFH8IAAITAAMJxxEwJAC9AAATAAMJxxEwJAC9AAAuAAQKfx4AAxMACQntG3oKAJkCABMACQntG3oKAJkCABQAAwnjDOdtAIsAAAAA.',
Az='Azgrunga:BAACLgAFFH8GAAIVAAMJkg+4NwDNAAAVAAMJkg+4NwDNAAAuAAQKfy8AAhUACQlVGg4dAGUCABUACQlVGg4dAGUCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgYJBwAAAA==.Benderbrod:BAAALgAECgUJBgABLgAECgYJBwARAAAAAA==.Beornwildlaw:BAAALgAECgEJAQAAAA==.Bestshaman:BAAALgAECgEJAQAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8gAAIVAAcJpxt2OQDBAQAVAAcJpxt2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Bomburr:BAAALgAECgYJBgABLgAFFAcJFwAIAMUUAA==.Bonk:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8zAAIQAAkJJxtGEgC4AgAQAAkJJxtGEgC4AgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAIWAAkJkh8wBQDtAgAWAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAACLgAFFH8MAAIXAAMJvhVfPgDJAAAXAAMJvhVfPgDJAAAuAAQKfykAAhcACQlzIAEGAPoCABcACQlzIAEGAPoCAAAA.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgAECgUJBQAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8MAAIQAAMJvRQzUQCqAAAQAAMJvRQzUQCqAAAuAAQKfzMAAxAACAnmG+YoABYCABAACAnmG+YoABYCABIABglnGMpAACwBAAAA.Cheesefries:BAABLgAECn8uAAMYAAgJWh+lDQC+AgAYAAgJWh+lDQC+AgAUAAYJ0R2uHwCnAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhZ+QACNAQAFAAcJrhZ+QACNAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8nAAMUAAkJDRfLHAC9AQAUAAYJQxrLHAC9AQATAAcJaQtPQAD7AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8dAAMYAAgJ3RF1OgCAAQAYAAgJ3RF1OgCAAQATAAYJ1QXpWgClAAAAAA==.Clear:BAAALgADCggJCgAAAA==.',
Co='Cogglutch:BAAALgAECgQJBAABLgADCgcJBwARAAAAAA==.Cokegirll:BAABLgAECn8bAAIZAAgJJxI+UACtAQAZAAgJJxI+UACtAQAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJKAAUAF4aAA==.Creamie:BAABLgAECn8oAAIUAAgJXhoCGADlAQAUAAgJXhoCGADlAQAAAA==.Creamish:BAABLgAECn8aAAIaAAgJlhUQDAAEAgAaAAgJlhUQDAAEAgABLgAECggJKAAUAF4aAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgQJCgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8aAAMbAAgJ3hR0JADfAQAbAAgJ3hR0JADfAQAcAAIJ9A49iwExAAAAAA==.Crumbshot:BAAALgAFFAIJAgAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8KAAIIAAMJnxESfQDjAAAIAAMJnxESfQDjAAAuAAQKfxgAAwgACQkvD9xVANgBAAgACQkvD9xVANgBAAkAAwm/A18SAFUAAAAA.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn8zAAIHAAkJfhUhDwDuAQAHAAkJfhUhDwDuAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJMwAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8WAAIWAAgJEQ9VIQAhAQAWAAgJEQ9VIQAhAQAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgAECgEJAQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8uAAMTAAgJIRgTGADvAQATAAgJIRgTGADvAQAYAAcJGhhcJwDmAQAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgIJBAABLgAFFAMJBQADAEkPAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCgAAAA==.Dill:BAABLgAECn9LAAIVAAkJniTlAwAoAwAVAAkJniTlAwAoAwAAAA==.Dimonds:BAAALgAECgMJBAAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBwAAAA==.Divinesmite:BAAALgADCgcJBwAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.Dontpanic:BAAALgADCgYJBgAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgAECgUJBQABLgAECgUJCAARAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgwhUADIAAAGAAcJMgwhUADIAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgMJAwAAAA==.Duntree:BAAALgADCgUJCAAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJBAABLgAECgQJCgARAAAAAA==.Dyabolykal:BAAALgAECgQJCAABLgAECgQJCgARAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIcAAkJKRLGaACbAQAcAAkJKRLGaACbAQABLgAFFAMJDAAXAL4VAA==.Elly:BAABLgAFFH8IAAIdAAMJ7QZPKwDLAAAdAAMJ7QZPKwDLAAAAAA==.Elsharion:BAABLgAECn8VAAMbAAgJ5B2AKwCyAQAbAAgJ5B2AKwCyAQAcAAQJKgtHHQGSAAABLgAFFAgJGwAYAP0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAgJGwAYAP0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAgJGwAYAP0gAA==.Elshie:BAACLgAFFH8bAAIYAAgJ/SDABQCqAgAYAAgJ/SDABQCqAgAuAAQKfxcAAhgACQlBHmENAH4CABgACQlBHmENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8IAAIeAAQJyxf4VwA/AQAeAAQJyxf4VwA/AQABLgAFFAcJEQADAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAACLgAFFH8HAAIFAAMJ1wpzRwCVAAAFAAMJ1wpzRwCVAAAuAAQKf0oAAgUACQkjG3UUAKQCAAUACQkjG3UUAKQCAAAA.Evermoreivy:BAAALgAECgMJAwAAAA==.',
Fa='Fastasheet:BAACLgAFFH8hAAITAAYJmh/QAwD1AQATAAYJmh/QAwD1AQAuAAQKfz4AAhMACQl5JvYBAFMDABMACQl5JvYBAFMDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAFFAEJAQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgADCgIJAgABLgAFFAEJAQARAAAAAA==.Fill:BAABLgAECn8gAAIaAAgJfyS0BwBLAgAaAAgJfyS0BwBLAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flarestepper:BAAALgADCgQJBAAAAA==.Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAABLgAECn8lAAIUAAgJVRWpHwCnAQAUAAgJVRWpHwCnAQABLgAFFAMJCgAKAEwfAA==.',
Fo='Foboshi:BAAALgAECgEJAQAAAA==.',
Fr='Frags:BAABLgAECn8lAAIbAAkJ0RdKJQDaAQAbAAkJ0RdKJQDaAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.Fuzzywuzzy:BAAALgAECgIJAgAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJGAAUABofAA==.',
Ga='Gainz:BAAALgAECgEJAgAAAA==.Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8nAAMOAAgJawoMOAAyAQAOAAgJawoMOAAyAQANAAQJIQXhWQCTAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8/AAIUAAkJPiaNAAB5AwAUAAkJPiaNAAB5AwAAAA==.Giliaa:BAAALgAECgcJBwAAAA==.Gilljoww:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.Gireigtulb:BAAALgAECgIJAgAAAA==.',
Gl='Glizzee:BAAALgAECgEJAQAAAA==.',
Gn='Gnz:BAAALgAFFAMJAwAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Goosebumps:BAAALgAFFAcJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAECgkJHgAZAJMZAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halløw:BAAALgAECgQJBAAAAA==.Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgQJBQAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAACLgAFFH8KAAIVAAQJJwUQLgDyAAAVAAQJJwUQLgDyAAAuAAQKfzoAAhUACQkxFsUWADcCABUACQkxFsUWADcCAAAA.Hilazy:BAABLgAECn8WAAIaAAgJhRm/DADhAQAaAAgJhRm/DADhAQAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8fAAMNAAkJqBR4FAA2AgANAAkJqBR4FAA2AgAOAAEJLApdhwAwAAAAAA==.Holysheet:BAABLgAFFH8GAAIcAAMJ6A/wcADLAAAcAAMJ6A/wcADLAAAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8lAAMFAAgJuhtdJwATAgAFAAcJeRpdJwATAgAGAAcJWxclKQCFAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJGAAUABofAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAARAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAwABLgAFFAEJAQARAAAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8kAAIIAAkJrgfkgwBsAQAIAAkJrgfkgwBsAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8bAAIIAAgJpgWtpwArAQAIAAgJpgWtpwArAQAAAA==.Ihavenofutur:BAAALgAECgYJEwAAAA==.',
Il='Illari:BAAALgAECgYJEgAAAA==.Illidantwo:BAACLgAFFH8bAAIfAAcJZRhPAwD6AQAfAAcJZRhPAwD6AQAuAAQKfzEAAh8ACQlDJBEEADoDAB8ACQlDJBEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8eAAIWAAgJPB1XDQASAgAWAAgJPB1XDQASAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgAECgEJAwAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8YAAIdAAkJgBMtFQDzAQAdAAkJgBMtFQDzAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAYJGwABAHAZAA==.Jabu:BAAALgAFFAIJAwABLgAFFAYJGwABAHAZAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAINAAYJLiXnEABhAgANAAYJLiXnEABhAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8fAAIgAAkJMA1tFQBqAQAgAAkJMA1tFQBqAQAAAA==.Jeryeth:BAABLgAECn8yAAMhAAkJTiKrAgAWAwAhAAkJOyKrAgAWAwAWAAgJMBySCACXAgAAAA==.Jerymander:BAAALgAECgcJCgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAABLgAFFH8FAAIiAAIJEB3OIwCuAAAiAAIJEB3OIwCuAAAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAECLgAFFH8lAAMjAAcJzR9MAACeAgAjAAcJzR9MAACeAgAcAAIJnRQ/hwCaAAAuAAQKfy8AAiMACAloJt0AAGgDACMACAloJt0AAGgDAAAA.Kanda:BAAALgAECgcJCAAAAA==.Karenuwu:BAAALgAFFAIJAwAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAcAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgAECggJCwAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQZA7QAgAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAZAF8aAA==.Kiwí:BAABLgAECn8dAAMJAAgJXR2WBgBRAQAIAAYJdBbbiABiAQAJAAUJDh2WBgBRAQAAAA==.',
Kr='Krasavice:BAABLgAECn8+AAIZAAkJOiP5BwAZAwAZAAkJOiP5BwAZAwAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQARAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8uAAIZAAgJMhXRRADPAQAZAAgJMhXRRADPAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAgcSAAKAQABAAYJsAgcSAAKAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8lAAMcAAkJ7xm5KQBYAgAcAAkJ7xm5KQBYAgAbAAcJvRIsNQB5AQAAAA==.Lemurshoes:BAAALgAFFAEJAgAAAA==.Lena:BAABLgAECn8qAAIZAAkJ4CPyDgDVAgAZAAkJ4CPyDgDVAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgYJDwAAAA==.Leøn:BAABLgAECn8YAAIeAAgJGB1qJACsAgAeAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgAECgEJAQARAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAACLgAFFH8FAAIQAAIJZx+4TgCyAAAQAAIJZx+4TgCyAAAuAAQKfyoAAhAACAkoIPgPAM4CABAACAkoIPgPAM4CAAAA.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAARAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJEAABLgAECgkJOgAXAAMlAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJBAAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8GAAIgAAMJ+hNmDQDaAAAgAAMJ+hNmDQDaAAAuAAQKfzoAAiAACQmBHn4EALUCACAACQmBHn4EALUCAAAA.',
['Lü']='Lüna:BAABLgAECn8mAAIkAAgJKgclFgADAQAkAAgJKgclFgADAQAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQADAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIcAAkJlSFmGgCjAgAcAAkJlSFmGgCjAgAAAA==.Mankirijilla:BAAALgAECgMJBQAAAA==.Mannin:BAAALgAECgMJAwABLgAFFAQJDwAQAD0eAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAIQAAcJTiFPHABmAgAQAAcJTiFPHABmAgAAAA==.Maximus:BAABLgAECn8uAAIcAAkJ7w4LXQC1AQAcAAkJ7w4LXQC1AQAAAA==.Mayyflower:BAAALgAECgEJAQAAAA==.',
Me='Mechlil:BAAALgAECgIJBQAAAA==.Meditacoss:BAAALgAFFAEJAQAAAA==.Meelu:BAABLgAECn8WAAMFAAkJGgrYTABZAQAFAAkJGgrYTABZAQAGAAEJRQJkpQAXAAABLgAFFAMJDAAXAL4VAA==.Mellowlizard:BAABLgAFFH8RAAIDAAcJgRySCACfAQADAAcJgRySCACfAQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgMJBgARAAAAAA==.Metuss:BAABLgAECn8YAAMYAAgJgR/XFQBmAgAYAAgJgR/XFQBmAgATAAYJ3A8rPgADAQAAAA==.',
Mi='Mira:BAABLgAECn8wAAIZAAgJihQBSADFAQAZAAgJihQBSADFAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgYJEAABLgAECgkJQQATAIAgAA==.Mkicon:BAACLgAFFH8GAAIIAAMJqQiqhwDPAAAIAAMJqQiqhwDPAAAuAAQKfygAAggACAkyEjJxAJQBAAgACAkyEjJxAJQBAAAA.Mkultra:BAABLgAECn8nAAMeAAkJCSLHFwC2AgAeAAkJvh7HFwC2AgAlAAcJQx9QHAB1AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8lAAIeAAgJCRNlWQC3AQAeAAgJCRNlWQC3AQAAAA==.Mooganfreman:BAAALgAECgMJAwAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8vAAImAAgJ0hx1BABLAgAmAAgJ0hx1BABLAgAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzAOthwA3AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAACLgAFFH8FAAIDAAMJSQ/IeQDLAAADAAMJSQ/IeQDLAAAuAAQKfzkAAwMACQkgH1YOANgCAAMACQkgH1YOANgCAAQAAgn/DblUAHAAAAAA.',
Mt='Mtkdh:BAAALgAECgkJAwAAAA==.',
Mu='Mudget:BAACLgAFFH8hAAMEAAkJHxqPAAA9AgAEAAYJCxiPAAA9AgADAAgJ3xg1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAQABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJKAAQAK4VAA==.Multanni:BAABLgAECn80AAISAAkJzRicFwAlAgASAAkJzRicFwAlAgAAAA==.',
My='Myonecrosis:BAABLgAECn8nAAMDAAgJdSLuFQCfAgADAAgJdSLuFQCfAgAEAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwARAAAAAA==.Nakrog:BAAALgAECgMJBQAAAA==.Napster:BAABLgAECn8sAAQbAAkJoSUrBQA/AwAbAAgJliUrBQA/AwAcAAQJrhvnhgBfAQAjAAEJIA2DUQArAAAAAA==.Nasa:BAACLgAFFH8VAAITAAYJXBzWCACGAQATAAYJXBzWCACGAQAuAAQKfxsAAhMACQkJH/QLALwCABMACQkJH/QLALwCAAAA.Nathon:BAAALgAECgkJAQAAAA==.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgEJAgAAAA==.Nellarixi:BAABLgAECn9BAAIOAAkJNyMlAwAxAwAOAAkJNyMlAwAxAwAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8oAAMXAAgJ8htJBgCTAgAXAAgJ8htJBgCTAgALAAMJUxgSCAC1AAAuAAQKf2AAAxcACQmbJs4AAIQDABcACQmXJs4AAIQDAAsACAklIL8DAN4CAAAA.',
No='Nodens:BAAALgAFFAEJAQAAAA==.Nolwenn:BAACLgAFFH8HAAMNAAMJ8wWGNgCoAAANAAMJ8wWGNgCoAAAOAAEJ1QCKQQAfAAAuAAQKfxUAAg0ABwmtGK0ZAAACAA0ABwmtGK0ZAAACAAAA.Nomaa:BAABLgAECn8uAAIPAAgJOwJuIAC4AAAPAAgJOwJuIAC4AAAAAA==.Nomäd:BAAALgAECgcJEAAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgMJBgARAAAAAA==.Notstormy:BAAALgAECgYJBgAAAA==.',
Nr='Nramar:BAAALgAECgEJAQAAAA==.',
Nu='Nurgle:BAAALgAECgUJCAAAAA==.',
Ny='Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8VAAISAAcJqA6DSgAGAQASAAcJqA6DSgAGAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgMJBgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgyfIwAtAQAHAAkJxgyfIwAtAQAGAAEJ4gOCiQAmAAAgAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAFFAEJAgAAAA==.Oktoberfest:BAABLgAECn8YAAIUAAkJGh/6CACgAgAUAAkJGh/6CACgAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8gAAIjAAgJ9hIOEwCZAQAjAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECggJEAAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAaAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAABLgAFFH8HAAISAAUJMBO6FQBlAQASAAUJMBO6FQBlAQAAAA==.',
Po='Pocahontas:BAABLgAECn8tAAMCAAkJ7xzLDACWAgACAAgJJx7LDACWAgAOAAIJ/hG1ZACEAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8rAAINAAkJ2R57BQAvAwANAAkJ2R57BQAvAwAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quepaspete:BAAALgAFFAEJAQAAAA==.Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8OAAIZAAMJiByFWADsAAAZAAMJiByFWADsAAAuAAQKfzIAAhkABwk8I1MRAK4CABkABwk8I1MRAK4CAAAA.Racker:BAABLgAECn8WAAIVAAgJgxZNHwDzAQAVAAgJgxZNHwDzAQAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMVAAUJ8RnGSgB6AQAVAAUJ8RnGSgB6AQAWAAQJUxA6MADCAAAAAA==.Rengots:BAABLgAECn8WAAIZAAYJ3hBvYABGAQAZAAYJ3hBvYABGAQAAAA==.Renne:BAABLgAECn8jAAIfAAcJyBV5HgDLAQAfAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgYJDwAAAA==.Rokkoz:BAABLgAECn8kAAMHAAkJzxBnJQAiAQAGAAcJthQMNABvAQAHAAkJ0QpnJQAiAQAAAA==.Romer:BAABLgAECn8WAAIYAAkJvQiaTgArAQAYAAkJvQiaTgArAQAAAA==.Rookiestar:BAAALgAECgEJBgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQMAAcJ/R4QDgBzAQABAAcJmB3YWgBzAQAMAAQJGiEQDgBzAQAfAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIjAAYJSg76JwDTAAAjAAYJSg76JwDTAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Samstephens:BAAALgADCggJDgAAAA==.Sarnt:BAAALgAECggJCwAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxx7DgBzAgAGAAkJjxx7DgBzAgAFAAMJSwulmAB+AAABLgAECgkJGwAeAJQfAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQADAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIXAAgJIg2dNgBSAQAXAAgJIg2dNgBSAQAAAA==.Scibiol:BAAALgADCgkJGwAAAA==.',
Se='Senseideath:BAAALgAFFAIJAgABLgADCgcJBwARAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Shalzindera:BAAALgAECgQJBAAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAABLgAFFH8FAAIDAAIJXBlZkwCVAAADAAIJXBlZkwCVAAABLgAFFAYJEgAIAMIeAA==.Shirokhan:BAABLgAECn8qAAIIAAgJjB3QLgBbAgAIAAgJjB3QLgBbAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sialle:BAAALgAECgkJCQAAAA==.Sidewinderx:BAAALgAECgMJAwAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAACLgAFFH8KAAIDAAQJEhxnOABhAQADAAQJEhxnOABhAQAuAAQKf04AAwMACQkNJcQCAGQDAAMACQkNJcQCAGQDAAQAAwmhGR9HAJoAAAAA.',
Sn='Snagglespark:BAACLgAFFH8PAAISAAUJBhgRHgAlAQASAAUJBhgRHgAlAQAuAAQKf0MAAxIACQkcH00KALcCABIACQkcH00KALcCABAAAQkSDa3aACoAAAAA.Sneakytacoss:BAAALgAECgYJBgABLgAFFAEJAQARAAAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8tAAIBAAkJ7RqIHABmAgABAAkJ7RqIHABmAgAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwARAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCAAAAA==.Spinna:BAAALgAECgUJBwAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A0yKgAEAQAHAAgJ3A0yKgAEAQAAAA==.Starvnmarvn:BAAALgAECgYJDQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Steady:BAAALgAECgEJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAQJDgAZAN4SAA==.Stormmonk:BAAALgAECgEJAQAAAA==.Stormybonk:BAAALgAECgQJBAAAAA==.',
Su='Suhdrake:BAABLgAECn8oAAIKAAgJ3xopCQBUAgAKAAgJ3xopCQBUAgAAAA==.Sunwing:BAAALgAECgQJBQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAABLgAECn8dAAIeAAgJVhFFYgChAQAeAAgJVhFFYgChAQAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJEAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8nAAMNAAgJSg/JJQCfAQANAAgJSg/JJQCfAQAOAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAACLgAFFH8FAAIWAAIJaxaxHwCSAAAWAAIJaxaxHwCSAAAuAAQKfy4AAhYACAmeGokOAP8BABYACAmeGokOAP8BAAAA.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAACLgAFFH8KAAMKAAMJTB/VFwAQAQAKAAMJTB/VFwAQAQAXAAIJlAF/XgBSAAAuAAQKf0MAAgoACQlVIFsCAEoDAAoACQlVIFsCAEoDAAAA.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgMJAwABLgAFFAMJBwAQAJAiAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgYJCwAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.Thunderbolt:BAAALgAFFAIJAgABLgADCgcJBwARAAAAAA==.Thymós:BAAALgAECgYJCAAAAA==.',
Ti='Tiamat:BAAALgADCgcJBwAAAA==.Tiffina:BAAALgAFFAIJAgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8NAAMPAAUJfA6jEwBsAAADAAUJfA7dWQAPAQAPAAIJXQOjEwBsAAABLgAFFAYJFwADAPsPAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQAAAA==.Trillion:BAAALgAECgYJBgABLgAFFAMJBQADAEkPAA==.Trissara:BAAALgAFFAEJAQAAAA==.Trolli:BAACLgAFFH8GAAIcAAIJASJXegC6AAAcAAIJASJXegC6AAAuAAQKfywAAhwACAlOJGQXALQCABwACAlOJGQXALQCAAAA.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.Tuskadin:BAAALgAECgEJAQAAAA==.',
Tw='Twixx:BAABLgAFFH8ZAAInAAQJcheVCwA4AQAnAAQJcheVCwA4AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAACLgAFFH8FAAIDAAIJJAFluABSAAADAAIJJAFluABSAAAuAAQKfxsAAwQACAnGBxQjAJQAAAMACAnCB9OYAAsBAAQABwmwAhQjAJQAAAAA.',
Ud='Uddercover:BAABLgAECn8bAAIdAAYJ7RQNKQBKAQAdAAYJ7RQNKQBKAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Ug='Ugebooge:BAAALgAECgQJBAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAaAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQARAAAAAA==.Undeadlock:BAAALgAECgQJBAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.Uruknazgul:BAAALgADCgYJBQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIeAAMJiSGNqQDIAAAeAAMJiSGNqQDIAAAuAAQKfxwAAx4ABgkdJuY9AEACAB4ABgkdJuY9AEACACUAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vannostrand:BAAALgAECgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQNAAYJWBFLOAAwAQANAAYJQg9LOAAwAQACAAQJMA/9WADQAAAOAAIJ4QepigAtAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8HAAIlAAMJxxATKgCjAAAlAAMJxxATKgCjAAAuAAQKfyIAAiUACAn2G6oTANUBACUACAn2G6oTANUBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAFFAMJDAAXAL4VAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQARAAAAAA==.Voidwarranty:BAAALgAECgUJBQAAAA==.Vokzhen:BAABLgAECn8uAAIOAAkJtBzpCgChAgAOAAkJtBzpCgChAgAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn81AAMDAAkJ7xL6OAD1AQADAAkJ7xL6OAD1AQAEAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAABLgAECgEJAQARAAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBpjpgAtAQAIAAYJdBpjpgAtAQAAAA==.',
Wi='Windswept:BAAALgAECgIJAwAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgkJGAAQAIMfAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAgJGgATAMokAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAgJGgATAMokAA==.Xeromus:BAABLgAECn8uAAMGAAgJIxthFwAPAgAGAAgJIxthFwAPAgAFAAIJ8wSWyAA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgQJCAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgQJDAAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMbAAkJ1RhkHgANAgAbAAkJ1RhkHgANAgAjAAIJkwFzWAAbAAAAAA==.Zaboomaprune:BAAALgAECgkJDAAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDgABLgAFFAMJCQATAJgkAA==.Zarika:BAACLgAFFH8GAAIoAAMJfSLmBQAtAQAoAAMJfSLmBQAtAQAuAAQKfxoAAygACAnJIcUCAIcCACgACAnJIcUCAIcCAB0ABAmGEh5OALoAAAEuAAUUCAkaABMAyiQA.Zarì:BAACLgAFFH8aAAITAAgJyiSAAADkAgATAAgJyiSAAADkAgAuAAQKfx4AAhMACQkTJg4DAGUDABMACQkTJg4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAFFAMJCQATAJgkAA==.',
Ze='Zeblaw:BAACLgAFFH8GAAIIAAIJOAmnrwB0AAAIAAIJOAmnrwB0AAAuAAQKfzAAAggACAkHGVpOAO0BAAgACAkHGVpOAO0BAAAA.Zekmal:BAAALgAFFAQJBAAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zo='Zoethedivine:BAAALgAECgEJAQAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAACLgAFFH8JAAITAAMJmCSpDwA6AQATAAMJmCSpDwA6AQAuAAQKf0MABBMACQlnJUYBAGkDABMACQlnJUYBAGkDABQABQlHEjBFAOMAABgAAQm4D/FrACoAAAAA.',
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
