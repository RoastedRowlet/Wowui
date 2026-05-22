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

local lookup = {'Priest-Holy','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Warrior-Fury','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Rogue-Subtlety','Warrior-Arms','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Feral','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Evoker-Devastation','Warlock-Affliction','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abyssia:BAAALgAFFAEJAQAAAA==.',
Ac='Acupuncher:BAAALgADCgEJAgAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8ZAAIBAAgJNhSlGAC9AQABAAgJNhSlGAC9AQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCQAAAA==.',
Al='Alcha:BAABLgAECn8gAAMCAAgJbhosBgCtAQACAAcJoBosBgCtAQADAAcJkBcYQACdAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECggJIAACAG4aAA==.Alenndar:BAAALgAECgcJDwAAAA==.Alexdaddario:BAABLgAECn8hAAMEAAYJQCKjFQDNAQAEAAYJQCKjFQDNAQAFAAIJ4gi2OwBAAAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECggJIAACAG4aAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8lAAMGAAgJmxNtTACzAQAGAAgJmxNtTACzAQAHAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAAALgAECgcJDQABLgAECgcJHwABANMaAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8gAAIIAAYJRCUxBQAEAgAIAAYJRCUxBQAEAgAAAA==.Annalease:BAAALgAECgIJBAAAAA==.Anticlimax:BAABLgAECn8cAAMJAAcJYBT2TwBFAQAJAAcJYBT2TwBFAQAIAAEJTgZAKwAbAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJBgAAAA==.',
Ap='Apparition:BAABLgAECn8iAAMKAAgJbRvNCQCDAgAKAAgJbRvNCQCDAgALAAUJlQr7TwBnAAAAAA==.Apprentice:BAACLgAFFH8LAAIGAAQJPR2KKgBhAQAGAAQJPR2KKgBhAQAuAAQKfywAAgYACAlgJRcNAOACAAYACAlgJRcNAOACAAAA.',
Ar='Argonar:BAABLgAECn8WAAIGAAgJ6Q1QawBlAQAGAAgJ6Q1QawBlAQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8JAAIMAAQJdw7aIAAIAQAMAAQJdw7aIAAIAQAuAAQKfxsAAgwACAkxHmsWAGICAAwACAkxHmsWAGICAAAA.',
At='Atorim:BAAALgAECgEJAgAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAABLgAECn8pAAIMAAkJNA8MLACvAQAMAAkJNA8MLACvAQAAAA==.',
Av='Avdol:BAAALgAECgcJDwABLgAFFAYJEAADAGocAA==.Avienndha:BAABLgAECn8aAAIIAAYJwxXwDAAvAQAIAAYJwxXwDAAvAQAAAA==.',
Aw='Awake:BAAALgAECgYJDAAAAA==.',
Az='Azgrunga:BAACLgAFFH8FAAINAAMJzw5nIgDaAAANAAMJzw5nIgDaAAAuAAQKfy8AAg0ACQlTGqsQACkCAA0ACQlTGqsQACkCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Benderbrod:BAAALgADCgkJCQAAAA==.Beornwildlaw:BAAALgADCgcJCAAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8dAAINAAcJtBp2OQDBAQANAAcJtBp2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8dAAIMAAgJLBmLHQAIAgAMAAgJLBmLHQAIAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8fAAIPAAkJkh8wBQDtAgAPAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAAALgAECgkJCQABLgAECgkJHAAQACkSAA==.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgADCggJCgAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAADAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8HAAIMAAMJmRLhLwDEAAAMAAMJmRLhLwDEAAAuAAQKfygAAwwACAkeGgAdAAwCAAwACAkeGgAdAAwCABEABQmLFVQ3AAEBAAAA.Cheesefries:BAABLgAECn8eAAMSAAYJxh3sFgDuAQASAAYJxh3sFgDuAQATAAYJ/RhAIgBYAQAAAA==.Chereth:BAABLgAECn8WAAIUAAcJhBJrSACBAQAUAAcJhBJrSACBAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8jAAMTAAkJKBR6GwCNAQATAAYJZxZ6GwCNAQAVAAcJaQvIKgAUAQAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8WAAMSAAcJ0BKfKQBRAQASAAcJ0BKfKQBRAQAVAAYJ1QX5PgC1AAAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgYJBgAOAAAAAA==.Cokegirll:BAAALgAECgYJDwAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJGgAWAJEVAA==.Creamie:BAABLgAECn8aAAITAAcJ2hs5HQB+AQATAAcJ2hs5HQB+AQABLgAECggJGgAWAJEVAA==.Creamish:BAABLgAECn8aAAIWAAgJkRUQDAAEAgAWAAgJkRUQDAAEAgAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgEJAQAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8VAAIXAAcJMRd5HgDCAQAXAAcJMRd5HgDCAQAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAABLgAECn8XAAMGAAkJyw1FQwDQAQAGAAkJyw1FQwDQAQAHAAMJvwOvDABdAAAAAA==.',
Da='Dacrus:BAAALgAECgEJBQAAAA==.Dalsen:BAABLgAECn8qAAIFAAkJnhPUCgDOAQAFAAkJnhPUCgDOAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJKgAFAJ4TAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8VAAIPAAcJRQ5VHQD6AAAPAAcJRQ5VHQD6AAAAAA==.Daredevil:BAAALgAECgEJAQABLgADCgYJBgAOAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAQABLgAFFAEJAQAOAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8cAAIVAAgJoRXjFAC/AQAVAAgJoRXjFAC/AQAAAA==.Deskpop:BAAALgADCgYJCgAAAA==.Dewberry:BAAALgAECgEJAgAAAA==.Deáth:BAAALgAECgMJBgAAAA==.',
Di='Diabolikal:BAAALgAECgQJCAAAAA==.Dill:BAABLgAECn86AAINAAkJ2iM8BADrAgANAAkJ2iM8BADrAgAAAA==.Dimonds:BAAALgAECgIJAgAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBgAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgADCgUJCQABLgAECgMJAwAOAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJCAAAAA==.Drùna:BAABLgAECn8YAAIEAAcJMQxIPADGAAAEAAcJMQxIPADGAAAAAA==.',
Du='Duifean:BAAALgADCgMJAwAAAA==.Dundecay:BAAALgADCgEJAQAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJAQABLgAECgQJCAAOAAAAAA==.Dyabolykal:BAAALgAECgQJBgABLgAECgQJCAAOAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIQAAkJKRKJQAC8AQAQAAkJKRKJQAC8AQAAAA==.Elly:BAAALgAECgEJAQAAAA==.Elsharion:BAABLgAECn8VAAMXAAgJ5B1RHwC8AQAXAAgJ5B1RHwC8AQAQAAQJKgva0QCcAAABLgAFFAYJGQASAGUfAA==.Elsharius:BAAALgAECgQJBAABLgAFFAYJGQASAGUfAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAYJGQASAGUfAA==.Elshie:BAACLgAFFH8ZAAISAAYJZR+UBgD+AQASAAYJZR+UBgD+AQAuAAQKfxUAAhIACQntHWENAH4CABIACQntHWENAH4CAAAA.',
Em='Emachine:BAAALgAFFAMJBAABLgAFFAYJEAADAGocAA==.',
Es='Eskyxy:BAAALgAECgYJDgAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn8yAAIUAAgJKBmHGwAhAgAUAAgJKBmHGwAhAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8aAAIVAAYJ+R5VAQDyAQAVAAYJ+R5VAQDyAQAuAAQKfz4AAhUACQl5JskAAGgDABUACQl5JskAAGgDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAECgEJBAAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fill:BAABLgAECn8cAAIWAAcJfiQ3CABfAgAWAAcJfiQ3CABfAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAABLgAECn8bAAITAAgJfBNIGQCeAQATAAgJfBNIGQCeAQABLgAECggJJAAYAGIYAA==.',
Fr='Frags:BAABLgAECn8lAAIXAAkJ0RcTGgDoAQAXAAkJ0RcTGgDoAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJFQATAOsdAA==.',
Ga='Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8XAAILAAYJRQckOwDQAAALAAYJRQckOwDQAAAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8tAAITAAgJ1yNdBwCMAgATAAgJ1yNdBwCMAgAAAA==.Giliaa:BAAALgAECgYJBgAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAUJFAAZAJgTAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgMJAwAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBgAAAA==.',
Hi='Highfeather:BAABLgAECn8jAAINAAYJkBbdMAA6AQANAAYJkBbdMAA6AQAAAA==.Hilazy:BAAALgAECgYJEAAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8dAAMKAAgJhhX3EAALAgAKAAgJhhX3EAALAgALAAEJLAqaYgAyAAAAAA==.Holysheet:BAAALgAFFAIJAwAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8XAAMUAAYJ3R1eMACXAQAUAAUJiBxeMACXAQAEAAYJAhYPKAAzAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAAOAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAgAAAA==.Hydropump:BAAALgAECgYJCAAAAA==.Hyla:BAAALgAECggJEgAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8bAAIGAAcJSQXwpgD1AAAGAAcJSQXwpgD1AAAAAA==.',
Ih='Ihasaface:BAAALgAECgcJEgAAAA==.Ihavenofutur:BAAALgAECgYJDwAAAA==.',
Il='Illari:BAAALgAECgUJDAAAAA==.Illidantwo:BAACLgAFFH8UAAIaAAUJmxxjAQCYAQAaAAUJmxxjAQCYAQAuAAQKfy0AAhoACQlJIxEEADoDABoACQlJIxEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAAALgAECgcJEgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgADCgQJBAAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8VAAIbAAgJwQ8wGACBAQAbAAgJwQ8wGACBAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAEJAQAOAAAAAA==.Jabu:BAAALgAFFAEJAQAAAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAIKAAYJLiXpCgBtAgAKAAYJLiXpCgBtAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAAALgAECggJEgAAAA==.Jeryeth:BAABLgAECn8gAAMPAAgJLx6SCACXAgAPAAgJMBySCACXAgAcAAgJcBc5CgDzAQAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8bAAIdAAUJbiBhAAD2AQAdAAUJbiBhAAD2AQAuAAQKfy8AAh0ACAloJt0AAGgDAB0ACAloJt0AAGgDAAAA.Karenuwu:BAAALgAECggJDgAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAAQAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgADCggJCAAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgEJAwAOAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMEAAYJyRQ4OABYAQAEAAYJyRQ4OABYAQAUAAEJlQb2vAAkAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAeAJEaAA==.Kiwí:BAABLgAECn8aAAMHAAcJUxuABABrAQAHAAUJDh2ABABrAQAGAAUJ0Q5FwADIAAAAAA==.',
Kr='Krasavice:BAABLgAECn8kAAIeAAcJRSRuGQBvAgAeAAcJRSRuGQBvAgAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQAOAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8fAAIeAAYJ7RBcZAAgAQAeAAYJ7RBcZAAgAQAAAA==.Lavish:BAACLgAFFH8NAAIJAAYJsAihJwAuAQAJAAYJsAihJwAuAQAuAAQKfx0AAgkACAkhHO8qAFQCAAkACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8ZAAMXAAcJvRIpJwCEAQAXAAcJvRIpJwCEAQAQAAYJUxwTYwBfAQAAAA==.Lemurshoes:BAAALgAECgYJBgAAAA==.Lena:BAABLgAECn8mAAIeAAgJBST3DgCSAgAeAAgJBST3DgCSAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgQJBAAAAA==.Leøn:BAABLgAECn8YAAIfAAgJGB1qJACsAgAfAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgADCgcJCAAOAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8kAAIMAAgJYB8nCwC6AgAMAAgJYB8nCwC6AgAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAAOAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJCAABLgAECgkJKgAZAO0kAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJAwAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8FAAIgAAIJKRHaCQCpAAAgAAIJKRHaCQCpAAAuAAQKfzYAAiAACQnyHLEDAIMCACAACQnyHLEDAIMCAAAA.',
['Lü']='Lüna:BAABLgAECn8eAAIhAAgJ2gXTEQD4AAAhAAgJ2gXTEQD4AAAAAA==.',
Ma='Macewindu:BAAALgAECgEJAwAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAYJEAADAGocAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAIQAAkJlSGCDADKAgAQAAkJlSGCDADKAgAAAA==.Manthebob:BAAALgADCgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAAALgAECgcJEwAAAA==.Maximus:BAABLgAECn8dAAIQAAkJ9gpuTgCTAQAQAAkJ9gpuTgCTAQAAAA==.',
Me='Meditacoss:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.Mellowlizard:BAABLgAFFH8QAAIDAAYJahyyCgDHAQADAAYJahyyCgDHAQAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgEJAwAOAAAAAA==.Metuss:BAAALgAECggJEgAAAA==.',
Mi='Mira:BAABLgAECn8fAAIeAAcJMRSYRwCTAQAeAAcJMRSYRwCTAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECggJNwAVAGsjAA==.Mkicon:BAABLgAECn8jAAIGAAgJuxESVwCWAQAGAAgJuxESVwCWAQAAAA==.Mkultra:BAABLgAECn8aAAMiAAcJbh6WGgB8AQAfAAcJ7BpxbgCtAQAiAAYJ7B2WGgB8AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJBwAAAA==.Mogmoog:BAAALgAECgYJEgAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8gAAIjAAYJjRhBCQBnAQAjAAYJjRhBCQBnAQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMUAAkJ9AdMWwBAAQAUAAgJcQhMWwBAAQAEAAMJzAOjYwA8AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn8iAAMDAAgJhxn7NwC6AQADAAgJhxn7NwC6AQACAAIJ/w25VABwAAAAAA==.',
Mt='Mtkdh:BAAALgAECgkJAgAAAA==.',
Mu='Mudget:BAACLgAFFH8gAAMCAAgJtxqPAAA9AgACAAYJCxiPAAA9AgADAAcJXBk1BADcAQAuAAQKfz4AAwMACQkuJoQNAA0DAAMABwkTJoQNAA0DAAIABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJJwAMAFIVAA==.Multanni:BAABLgAECn8eAAIRAAcJYhZtKwBAAQARAAcJYhZtKwBAAQAAAA==.',
My='Myonecrosis:BAABLgAECn8TAAMDAAYJzSCyNgC+AQADAAYJzSCyNgC+AQACAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgYJBgAOAAAAAA==.Nakrog:BAAALgAECgEJAQAAAA==.Napster:BAABLgAECn8bAAIXAAgJyh8aGABRAgAXAAgJyh8aGABRAgAAAA==.Nasa:BAACLgAFFH8VAAIVAAYJXBzGAgCpAQAVAAYJXBzGAgCpAQAuAAQKfxsAAhUACQkJH/QLALwCABUACQkJH/QLALwCAAAA.Nazarov:BAAALgAECgEJAgAAAA==.',
Ne='Nellarixi:BAABLgAECn8vAAILAAgJIB5iCgBfAgALAAgJIB5iCgBfAgAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8WAAMZAAgJTBZ7AgB1AgAZAAgJTBZ7AgB1AgAkAAIJpgnuBgCgAAAuAAQKf1cAAxkACQmZJmYAAIYDABkACQmWJmYAAIYDACQACAklIL8DAN4CAAAA.',
No='Nolwenn:BAAALgADCgYJCwAAAA==.Nomaa:BAABLgAECn8aAAIlAAYJ4QGuHgB7AAAlAAYJ4QGuHgB7AAAAAA==.Nomäd:BAAALgAECgYJDQAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgEJAwAOAAAAAA==.',
Nr='Nramar:BAAALgADCgYJBwAAAA==.',
Nu='Nurgle:BAAALgADCgYJDAAAAA==.',
Ny='Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8UAAIRAAYJBhDTOwDsAAARAAYJBhDTOwDsAAAAAA==.',
['Nì']='Nìtsua:BAAALgAECgEJAwAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn8rAAQFAAgJugxwGQAEAQAFAAgJugxwGQAEAQAEAAEJ4gOCiQAmAAAgAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAECgEJAQAAAA==.Oktoberfest:BAABLgAECn8VAAITAAkJ6x12BgCdAgATAAkJ6x12BgCdAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8ZAAIdAAgJ+RIOEwCZAQAdAAgJ+RIOEwCZAQAAAA==.',
Ph='Phok:BAAALgADCgYJCQAAAA==.Phrash:BAAALgAECgIJBAABLgAECgcJHAAWAH4kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAECgcJDgAAAA==.',
Po='Pocahontas:BAABLgAECn8fAAIBAAcJ0xobEgAFAgABAAcJ0xobEgAFAgAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJCwAGAHwXAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAAALgAECggJEgAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8JAAIeAAMJaxm5NADvAAAeAAMJaxm5NADvAAAuAAQKfyIAAh4ABwk8I1MRAK4CAB4ABwk8I1MRAK4CAAAA.Racker:BAAALgAECgYJCAAAAA==.Rainfallen:BAAALgAECgYJBgAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMNAAUJ8RnGSgB6AQANAAUJ8RnGSgB6AQAPAAQJUxA6MADCAAAAAA==.Rengots:BAAALgAECgYJEgAAAA==.Renne:BAABLgAECn8jAAIaAAcJyBV5HgDLAQAaAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgQJBgAAAA==.Rokkoz:BAABLgAECn8bAAMEAAcJthQMNABvAQAEAAcJthQMNABvAQAFAAQJighCKgBRAAAAAA==.Rookiestar:BAAALgAECgEJAgAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQJAAcJ/R5dQAB6AQAJAAcJlx1dQAB6AQAIAAQJGiEQDgBzAQAaAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIdAAYJSg6pHADZAAAdAAYJSg6pHADZAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Sarnt:BAAALgAECggJBAAAAA==.Sass:BAABLgAECn8sAAMEAAkJjxxiCACGAgAEAAkJjxxiCACGAgAUAAMJSgv7ewCAAAAAAA==.Satella:BAAALgAECgcJBwABLgAFFAYJEAADAGocAA==.',
Sc='Schattën:BAAALgAECgcJEgAAAA==.Scibiol:BAAALgADCgkJCQAAAA==.',
Se='Senseideath:BAAALgAECgMJAwABLgADCgYJBgAOAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJBQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAAALgAFFAEJAgABLgAFFAQJCgAGAJAdAA==.Shirokhan:BAABLgAECn8gAAIGAAgJPR3tMwAHAgAGAAgJPR3tMwAHAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgAECgIJAgAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAABLgAECn82AAMDAAgJNyPFEACQAgADAAgJNyPFEACQAgACAAMJoRkfRwCaAAAAAA==.',
Sn='Snagglespark:BAABLgAECn8wAAIRAAkJzxoHDwAvAgARAAkJzxoHDwAvAgAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8fAAIJAAgJdBlMKADiAQAJAAgJdBlMKADiAQAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwAOAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgMJAwAAAA==.',
St='Starlisia:BAAALgAECgYJEQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAQJCgAeAFwOAA==.',
Su='Suhdrake:BAABLgAECn8oAAIYAAgJ3xovBgBjAgAYAAgJ3xovBgBjAgAAAA==.Sunwing:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAAALgAECgYJCgAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgYJCQAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8fAAMKAAYJcREcJABPAQAKAAYJcREcJABPAQALAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8kAAIPAAgJlBlICwDsAQAPAAgJlBlICwDsAQAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAADAAEZAA==.',
Tc='Tcharta:BAABLgAECn8kAAIYAAgJYhjhBgBMAgAYAAgJYhjhBgBMAgAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgIJAgABLgAECgkJKAAMACUdAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgUJBQAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Thunderbolt:BAAALgADCgIJAgABLgADCgYJBgAOAAAAAA==.',
Ti='Tiamat:BAAALgADCgYJBgAAAA==.Tiffina:BAAALgAECggJDwAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAAALgAFFAQJBAAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJEAAOAAAAAA==.Trissara:BAAALgAECgcJCgAAAA==.Trolli:BAABLgAECn8nAAIQAAgJMSSoDgC4AgAQAAgJMSSoDgC4AgAAAA==.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.',
Tw='Twixx:BAABLgAFFH8IAAImAAMJYRLDCADjAAAmAAMJYRLDCADjAAAAAA==.',
Ty='Tyinar:BAAALgAECgEJAwAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAABLgAECn8bAAMCAAgJxgexGQCeAAADAAgJwQeWcQAbAQACAAcJsAKxGQCeAAAAAA==.',
Ud='Uddercover:BAAALgAECgYJDwAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECgcJHAAWAH4kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQAOAAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIfAAMJiSEQZgDpAAAfAAMJiSEQZgDpAAAuAAQKfxcAAx8ABgkdJuY9AEACAB8ABgkdJuY9AEACACIAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vathen:BAABLgAECn8UAAIDAAcJARmNOQAlAgADAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQKAAYJWBFrJgA9AQAKAAYJQg9rJgA9AQABAAQJMA/9WADQAAALAAIJ4QeqZQAuAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAABLgAECn8gAAIiAAcJChvlEQCZAQAiAAcJChvlEQCZAQAAAA==.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAECgkJHAAQACkSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQAOAAAAAA==.Vokzhen:BAABLgAECn8YAAILAAcJRBQQIABwAQALAAcJRBQQIABwAQAAAA==.Volescu:BAAALgAECgEJAwAAAA==.',
Wa='Walkerboah:BAABLgAECn8fAAMDAAcJHxGHZgAzAQADAAcJHxGHZgAzAQACAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAABLgAECn8VAAIGAAYJdBpHegBGAQAGAAYJdBpHegBGAQAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgcJEQAOAAAAAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAYJFwAVAB4mAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAYJFwAVAB4mAA==.Xeromus:BAABLgAECn8gAAMEAAYJHRgLJQBHAQAEAAYJHRgLJQBHAQAUAAIJ8wTWpAA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgEJAQAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMXAAkJ1Rh9FAAfAgAXAAkJ1Rh9FAAfAgAdAAIJkwFXQQAcAAAAAA==.Zaboomaprune:BAAALgAECgcJCwAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJCAABLgAECgkJKwAVAAAkAA==.Zarika:BAABLgAECn8aAAMnAAgJySGdAQCWAgAnAAgJySGdAQCWAgAbAAQJhhIeTgC6AAABLgAFFAYJFwAVAB4mAA==.Zarì:BAACLgAFFH8XAAIVAAYJHiapAAAwAgAVAAYJHiapAAAwAgAuAAQKfxwAAhUACQnfJQ4DAGUDABUACQnfJQ4DAGUDAAAA.Zaö:BAAALgADCgEJAQABLgAECgkJKwAVAAAkAA==.',
Ze='Zeblaw:BAABLgAECn8qAAIGAAgJnxewPgDfAQAGAAgJnxewPgDfAQAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAABLgAECn8rAAMVAAkJACT3AQAuAwAVAAkJACT3AQAuAwASAAEJuA/xawAqAAAAAA==.',
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
