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

local lookup = {'DemonHunter-Devourer','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Shaman-Elemental','Monk-Mistweaver','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Rogue-Subtlety','Druid-Feral','Warrior-Arms','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Evoker-Devastation','Warlock-Affliction','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abyssia:BAABLgAECn8UAAIBAAcJhhm/QQChAQABAAcJhhm/QQChAQAAAA==.',
Ac='Acupuncher:BAAALgADCgEJAgAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAABLgAECn8cAAICAAgJNhSuHQCzAQACAAgJNhSuHQCzAQAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCgAAAA==.',
Al='Alcha:BAABLgAECn8kAAMDAAgJoBobCACgAQAEAAgJkBciOQDdAQADAAcJoBobCACgAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECggJJAADAKAaAA==.Alenndar:BAABLgAECn8VAAIFAAcJHBGCQgBjAQAFAAcJHBGCQgBjAQAAAA==.Alexdaddario:BAABLgAECn8hAAMGAAYJQCIpGwDDAQAGAAYJQCIpGwDDAQAHAAIJ4giWTQA+AAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECggJJAADAKAaAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8lAAMIAAgJexNUWgCyAQAIAAgJexNUWgCyAQAJAAEJsgUQIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAAALgAECgcJEQABLgAECggJKAACAIkcAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8lAAIKAAgJUCQgAgDIAgAKAAgJUCQgAgDIAgAAAA==.Annalease:BAAALgAECgIJBAAAAA==.Anticlimax:BAABLgAECn8kAAMBAAgJ2xK8TQB6AQABAAgJ2xK8TQB6AQAKAAEJTgYnMgAaAAAAAA==.Antipathy:BAAALgAECgMJAwAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJBwAAAA==.',
Ap='Apparition:BAABLgAECn8iAAMLAAgJbhtsDAB7AgALAAgJbhtsDAB7AgAMAAUJlQr8WwBnAAAAAA==.Apprentice:BAACLgAFFH8PAAIIAAQJZCEFKgB7AQAIAAQJZCEFKgB7AQAuAAQKfywAAggACAlNJecPAOQCAAgACAlNJecPAOQCAAAA.',
Ar='Argonar:BAABLgAECn8bAAIIAAgJpw93ZwCRAQAIAAgJpw93ZwCRAQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAACLgAFFH8JAAINAAQJdw6oKgD/AAANAAQJdw6oKgD/AAAuAAQKfxwAAg0ACQlKHWsWAGICAA0ACQlKHWsWAGICAAAA.',
At='Atorim:BAAALgAECgEJAgAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAABLgAECn8yAAINAAkJFBN3IQAZAgANAAkJFBN3IQAZAgAAAA==.',
Av='Avdol:BAAALgAECgcJDwABLgAFFAcJEQAEAIEcAA==.Avienndha:BAABLgAECn8fAAIKAAgJ+xfGBwDWAQAKAAgJ+xfGBwDWAQAAAA==.',
Aw='Awake:BAABLgAECn8VAAMOAAkJyxMfFgDdAQAOAAkJhRIfFgDdAQAPAAMJ4wznbQCLAAAAAA==.',
Az='Azgrunga:BAACLgAFFH8GAAIQAAMJkg/lKADXAAAQAAMJkg/lKADXAAAuAAQKfy8AAhAACQlVGrYWABQCABAACQlVGrYWABQCAAAA.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Barramon:BAAALgAECgUJBQAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beardeddrunk:BAAALgAECgYJBgAAAA==.Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Belieferton:BAAALgAECgUJBQAAAA==.Benderbrod:BAAALgAECgEJAQAAAA==.Beornwildlaw:BAAALgADCgcJCAAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8fAAIQAAcJtBp2OQDBAQAQAAcJtBp2OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8nAAINAAgJQxuYGwBBAgANAAgJQxuYGwBBAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8gAAISAAkJkh8wBQDtAgASAAkJkh8wBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAAALgAFFAMJAwABLgAECgkJHAATACkSAA==.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDwAAAA==.',
['Bë']='Bëan:BAAALgAECgMJAwAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgADCggJCgAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAAEAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8KAAINAAMJFRPEOgDCAAANAAMJFRPEOgDCAAAuAAQKfzIAAw0ACAnmGwIhABwCAA0ACAnmGwIhABwCABQABgmZFuoxAEcBAAAA.Cheesefries:BAABLgAECn8jAAMVAAgJnRy6DgCAAgAVAAgJnRy6DgCAAgAPAAYJ/RgpKABRAQAAAA==.Chereth:BAABLgAECn8ZAAIFAAcJrhYXOQCPAQAFAAcJrhYXOQCPAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8kAAMPAAkJLRQjIACHAQAPAAYJbxYjIACHAQAOAAcJaQv/NAAEAQAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8WAAMVAAcJ0BJlMwBWAQAVAAcJ0BJlMwBWAQAOAAYJ1QXYSgCsAAAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgcJBwARAAAAAA==.Cokegirll:BAAALgAECggJEwAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJGgAWAJYVAA==.Creamie:BAABLgAECn8iAAIPAAcJ2hslHgCWAQAPAAcJ2hslHgCWAQABLgAECggJGgAWAJYVAA==.Creamish:BAABLgAECn8aAAIWAAgJlhUQDAAEAgAWAAgJlhUQDAAEAgAAAA==.Creeda:BAAALgADCgMJAwAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critcomander:BAAALgAECgMJAwAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8ZAAMXAAcJMReWIwDCAQAXAAcJMReWIwDCAQATAAIJ9A4FZQEwAAAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAACLgAFFH8FAAIIAAMJNg9WZgDpAAAIAAMJNg9WZgDpAAAuAAQKfxgAAwgACQkvDxBGAO4BAAgACQkvDxBGAO4BAAkAAwm/A1gOAFkAAAAA.',
Da='Dacrus:BAAALgAECgIJBgAAAA==.Dalsen:BAABLgAECn8zAAIHAAkJfhXvCgD7AQAHAAkJfhXvCgD7AQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECgkJMwAHAH4VAA==.Damnadin:BAAALgAECgcJDAAAAA==.Dankchop:BAABLgAECn8VAAISAAcJRg7WIQD5AAASAAcJRg7WIQD5AAAAAA==.Daredevil:BAAALgAECgEJAgABLgADCgcJBwARAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.Dawnlighted:BAAALgADCgMJAwABLgADCgcJCAARAAAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAgABLgAFFAEJAQARAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8oAAMOAAgJIRhNEwD9AQAOAAgJIRhNEwD9AQAVAAEJ8gz2jAAnAAAAAA==.Deskpop:BAAALgADCgYJCwAAAA==.Dewberry:BAAALgAECgEJAwAAAA==.Deáth:BAAALgAECgYJDwAAAA==.',
Di='Diabolikal:BAAALgAECgQJCQAAAA==.Dill:BAABLgAECn9CAAIQAAkJMSSUAwAZAwAQAAkJMSSUAwAZAwAAAA==.Dimonds:BAAALgAECgIJAgAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBgAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgADCgUJCQABLgAECgUJCAARAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drscruffles:BAAALgAECgUJBQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJDQAAAA==.Drùna:BAABLgAECn8YAAIGAAcJMgzXQwDLAAAGAAcJMgzXQwDLAAAAAA==.',
Du='Duifean:BAAALgAECgIJAgAAAA==.Dundecay:BAAALgADCgEJAQAAAA==.Duntree:BAAALgADCgUJBQAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolycal:BAAALgAECgEJAgABLgAECgQJCQARAAAAAA==.Dyabolykal:BAAALgAECgQJBwABLgAECgQJCQARAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAITAAkJKRJPUQC2AQATAAkJKRJPUQC2AQAAAA==.Elly:BAAALgAFFAEJAQAAAA==.Elsharion:BAABLgAECn8VAAMXAAgJ5B1PJQC2AQAXAAgJ5B1PJQC2AQATAAQJKgsr8wCcAAABLgAFFAcJGgAVAC0gAA==.Elsharius:BAAALgAECgQJBAABLgAFFAcJGgAVAC0gAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAcJGgAVAC0gAA==.Elshie:BAACLgAFFH8aAAIVAAcJLSDrBABbAgAVAAcJLSDrBABbAgAuAAQKfxUAAhUACQntHWENAH4CABUACQntHWENAH4CAAAA.',
Em='Emachine:BAABLgAFFH8FAAIYAAMJBhFwpACUAAAYAAMJBhFwpACUAAABLgAFFAcJEQAEAIEcAA==.',
Es='Eskyxy:BAAALgAECgYJDwAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn87AAIFAAkJlhj4FACAAgAFAAkJlhj4FACAAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8aAAIOAAYJ+R45AgDoAQAOAAYJ+R45AgDoAQAuAAQKfz4AAg4ACQl5JkABAGADAA4ACQl5JkABAGADAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAECgEJBQAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAgAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fightingfed:BAAALgADCgIJAgABLgAFFAEJAQARAAAAAA==.Fill:BAABLgAECn8gAAIWAAgJfyS/BQBWAgAWAAgJfyS/BQBWAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAABLgAECn8kAAIPAAgJVRUcGwCtAQAPAAgJVRUcGwCtAQABLgAECggJKgAZAB4cAA==.',
Fr='Frags:BAABLgAECn8lAAIXAAkJ0ReZHwDgAQAXAAkJ0ReZHwDgAQAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECgkJFwAPAGAeAA==.',
Ga='Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgAECgEJAQAAAA==.',
Ge='Genjyosanzo:BAABLgAECn8bAAIMAAgJEQZUOQAGAQAMAAgJEQZUOQAGAQAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn82AAIPAAkJAiUJAQBaAwAPAAkJAiUJAQBaAwAAAA==.Giliaa:BAAALgAECgcJBwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAUJFAAaAJgTAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDQAAAA==.Grokdepaly:BAAALgAECgYJCAAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBgAAAA==.Hateez:BAAALgAECgMJAwAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBwAAAA==.',
Hi='Highfeather:BAABLgAECn8rAAIQAAcJXRO0MgBaAQAQAAcJXRO0MgBaAQAAAA==.Hilazy:BAAALgAECgYJEAAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAFFAEJAQAAAA==.Holyphok:BAABLgAECn8dAAMLAAgJhhVBFQABAgALAAgJhhVBFQABAgAMAAEJLAo9cAAyAAAAAA==.Holysheet:BAAALgAFFAIJAwAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAABLgAECn8bAAMFAAgJ3xrMJAADAgAFAAcJfhnMJAADAgAGAAYJAhaUMAArAQAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.Hotellobby:BAAALgAECgcJBwABLgAECgkJFwAPAGAeAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAARAAAAAA==.',
Hy='Hydroheals:BAAALgAECgEJAgAAAA==.Hydropump:BAAALgAECgcJCQAAAA==.Hyla:BAAALgAECggJEwAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8fAAIIAAgJPgb0mQArAQAIAAgJPgb0mQArAQAAAA==.',
Ih='Ihasaface:BAABLgAECn8aAAIIAAgJhwXqkAA7AQAIAAgJhwXqkAA7AQAAAA==.Ihavenofutur:BAAALgAECgYJEgAAAA==.',
Il='Illari:BAAALgAECgUJDAAAAA==.Illidantwo:BAACLgAFFH8WAAIbAAYJ1RljAQCYAQAbAAYJ1RljAQCYAQAuAAQKfy8AAhsACQlJIxEEADoDABsACQlJIxEEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAABLgAECn8WAAISAAcJuh0tEAAGAgASAAcJuh0tEAAGAgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgADCgQJBAAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAABLgAECn8WAAIcAAgJkRJbGQCmAQAcAAgJkRJbGQCmAQAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAQJDwABAJ8VAA==.Jabu:BAAALgAFFAIJAgABLgAFFAQJDwABAJ8VAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8YAAILAAYJLiWkDQBoAgALAAYJLiWkDQBoAgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAABLgAECn8UAAIdAAgJ/QT6HQDdAAAdAAgJ/QT6HQDdAAAAAA==.Jeryeth:BAABLgAECn8pAAMeAAkJXCFjAwDVAgAeAAkJOR9jAwDVAgASAAgJMBySCACXAgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
Ju='Jumpbackward:BAAALgAECgEJAQAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8dAAIfAAYJOSFCAABcAgAfAAYJOSFCAABcAgAuAAQKfy8AAh8ACAloJt0AAGgDAB8ACAloJt0AAGgDAAAA.Kanda:BAAALgADCgEJAQAAAA==.Karenuwu:BAAALgAFFAIJAgAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJPAATAJUhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgADCggJCAAAAA==.Kenslee:BAAALgADCgEJAQABLgAECgEJAwARAAAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMGAAYJyRQ4OABYAQAGAAYJyRQ4OABYAQAFAAEJlQZ9zwAkAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJFgAgAF8aAA==.Kiwí:BAABLgAECn8bAAMJAAcJ0hyXCABqAQAJAAUJDh2XCABqAQAIAAUJ6RP2uwDzAAAAAA==.',
Kr='Krasavice:BAABLgAECn8xAAIgAAgJnyMIDgC7AgAgAAgJnyMIDgC7AgAAAA==.Krenik:BAAALgADCgEJAQAAAA==.Krisp:BAAALgADCgEJAQABLgAFFAEJAQARAAAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8kAAIgAAgJyhCGSQCYAQAgAAgJyhCGSQCYAQAAAA==.Lavish:BAACLgAFFH8OAAIBAAYJsAjEMQAmAQABAAYJsAjEMQAmAQAuAAQKfx0AAgEACAkhHO8qAFQCAAEACAkhHO8qAFQCAAAA.',
Le='Leathal:BAABLgAECn8dAAMTAAcJlB87aAB/AQATAAYJ0x47aAB/AQAXAAcJvRIyLgB9AQAAAA==.Lemurshoes:BAAALgAECgYJBgAAAA==.Lena:BAABLgAECn8pAAIgAAkJVCPYCgDcAgAgAAkJVCPYCgDcAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgUJCQAAAA==.Leøn:BAABLgAECn8YAAIYAAgJGB1qJACsAgAYAAgJGB1qJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgADCgcJCAARAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8qAAINAAgJKCDDCwDWAgANAAgJKCDDCwDWAgAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAARAAAAAA==.',
Lu='Lucaeryn:BAAALgAECggJDAABLgAECgkJKgAaAO8kAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECggJEwAAAA==.Lusat:BAAALgAECgMJAwAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAACLgAFFH8FAAIdAAIJKRECDQCdAAAdAAIJKRECDQCdAAAuAAQKfzgAAh0ACQnyHAMFAHwCAB0ACQnyHAMFAHwCAAAA.',
['Lü']='Lüna:BAABLgAECn8eAAIhAAgJ3AWjFADzAAAhAAgJ3AWjFADzAAAAAA==.',
Ma='Macewindu:BAAALgAECgEJBAAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAcJEQAEAIEcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn88AAITAAkJlSGUEgC4AgATAAkJlSGUEgC4AgAAAA==.Manthebob:BAAALgAECgEJAQAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAABLgAECn8ZAAINAAcJTiHZFQBuAgANAAcJTiHZFQBuAgAAAA==.Maximus:BAABLgAECn8mAAITAAkJQA6xTADCAQATAAkJQA6xTADCAQAAAA==.',
Me='Mechlil:BAAALgAECgIJAgAAAA==.Meditacoss:BAAALgAECgEJAQABLgAECgMJAwARAAAAAA==.Meelu:BAAALgAECgcJBwABLgAECgkJHAATACkSAA==.Mellowlizard:BAABLgAFFH8RAAIEAAcJgRzGBwAWAgAEAAcJgRzGBwAWAgAAAA==.Metamarie:BAAALgADCgEJAQABLgAECgEJAwARAAAAAA==.Metuss:BAABLgAECn8VAAMVAAcJQSBEGAAYAgAVAAcJQSBEGAAYAgAOAAYJ3A8+NAAIAQAAAA==.',
Mi='Mira:BAABLgAECn8nAAIgAAcJMhSYRwCTAQAgAAcJMhSYRwCTAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECggJOwAOAGsjAA==.Mkicon:BAABLgAECn8kAAIIAAgJuhEIZQCXAQAIAAgJuhEIZQCXAQAAAA==.Mkultra:BAABLgAECn8iAAMYAAgJbyEdOwDxAQAYAAcJhx0dOwDxAQAiAAcJQx/rFgB/AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJCwAAAA==.Mogmoog:BAABLgAECn8XAAIYAAgJhw8eXACPAQAYAAgJhw8eXACPAQAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8iAAIjAAgJyBi9BQD5AQAjAAgJyBi9BQD5AQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8fAAMFAAkJ9AdMWwBAAQAFAAgJcQhMWwBAAQAGAAMJzANlcQA8AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn8rAAMEAAkJARyBEwCbAgAEAAkJARyBEwCbAgADAAIJ/w25VABwAAAAAA==.',
Mt='Mtkdh:BAAALgAECgkJAgAAAA==.',
Mu='Mudget:BAACLgAFFH8gAAMDAAgJtxqPAAA9AgADAAYJCxiPAAA9AgAEAAcJXBk1BADcAQAuAAQKfz4AAwQACQkuJoQNAA0DAAQABwkTJoQNAA0DAAMABQl1JpkIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECgkJJwANAFIVAA==.Multanni:BAABLgAECn8rAAIUAAgJeBaCIgCkAQAUAAgJeBaCIgCkAQAAAA==.',
My='Myonecrosis:BAABLgAECn8YAAMEAAgJoSATGQB0AgAEAAgJoSATGQB0AgADAAEJ+BI1bAA7AAAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgcJBwARAAAAAA==.Nakrog:BAAALgAECgIJAgAAAA==.Napster:BAABLgAECn8fAAMXAAgJ2yLgEgBVAgAXAAgJ2yLgEgBVAgAfAAEJIA3+RAArAAAAAA==.Nasa:BAACLgAFFH8VAAIOAAYJXBy0BACaAQAOAAYJXBy0BACaAQAuAAQKfxsAAg4ACQkJH/QLALwCAA4ACQkJH/QLALwCAAAA.Nazarov:BAAALgAECgMJBAAAAA==.',
Ne='Necronorris:BAAALgAECgEJAgAAAA==.Nellarixi:BAABLgAECn84AAIMAAkJ6CJqAgA0AwAMAAkJ6CJqAgA0AwAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8WAAMaAAgJTBbeBABhAgAaAAgJTBbeBABhAgAkAAIJpgnuBgCgAAAuAAQKf2AAAxoACQmbJngAAIwDABoACQmXJngAAIwDACQACAklIL8DAN4CAAAA.',
No='Nolwenn:BAAALgAFFAIJAwAAAA==.Nomaa:BAABLgAECn8fAAIlAAgJCgLIGgCsAAAlAAgJCgLIGgCsAAAAAA==.Nomäd:BAAALgAECgcJDwAAAA==.Nosneb:BAAALgAECgEJAgABLgAECgEJAwARAAAAAA==.',
Nr='Nramar:BAAALgADCgYJBwAAAA==.',
Nu='Nurgle:BAAALgAECgMJAwAAAA==.',
Ny='Nyteknight:BAAALgAECgEJAQAAAA==.Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8UAAIUAAYJBhBDRwDmAAAUAAYJBhBDRwDmAAAAAA==.',
['Nì']='Nìtsua:BAAALgAECgEJAwAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn81AAQHAAkJxgw3GgA6AQAHAAkJxgw3GgA6AQAGAAEJ4gOCiQAmAAAdAAEJkQM5OQAkAAAAAA==.',
Ok='Okko:BAAALgAECgEJAwAAAA==.Oktoberfest:BAABLgAECn8XAAIPAAkJYB6PBwCfAgAPAAkJYB6PBwCfAgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8ZAAIfAAgJ9hIOEwCZAQAfAAgJ9hIOEwCZAQAAAA==.',
Ph='Phok:BAAALgAECgQJBAAAAA==.Phrash:BAAALgAECgIJBAABLgAECggJIAAWAH8kAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAFFAEJAQAAAA==.',
Po='Pocahontas:BAABLgAECn8oAAMCAAgJiRwLDAB+AgACAAgJiRwLDAB+AgAMAAEJEhduZgBEAAAAAA==.Poky:BAAALgADCgUJBgABLgAFFAQJDwAIAMMbAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAABLgAECn8bAAILAAkJMBdAEABBAgALAAkJMBdAEABBAgAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8KAAIgAAMJaxlGRADhAAAgAAMJaxlGRADhAAAuAAQKfyYAAiAABwk8I1MRAK4CACAABwk8I1MRAK4CAAAA.Racker:BAAALgAECggJDAAAAA==.Rainfallen:BAAALgAECgYJBwAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMQAAUJ8RnGSgB6AQAQAAUJ8RnGSgB6AQASAAQJUxA6MADCAAAAAA==.Rengots:BAAALgAECgYJEwAAAA==.Renne:BAABLgAECn8jAAIbAAcJyBV5HgDLAQAbAAcJyBV5HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgUJBwAAAA==.Rokkoz:BAABLgAECn8jAAMHAAgJYhLUIAADAQAGAAcJthQMNABvAQAHAAgJiAvUIAADAQAAAA==.Romer:BAAALgAECgcJBwAAAA==.Rookiestar:BAAALgAECgEJAwAAAA==.Rowaen:BAAALgAECgcJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQKAAcJ/R4QDgBzAQABAAcJmB2kTgB3AQAKAAQJGiEQDgBzAQAbAAEJ+Q+FbQA4AAAAAA==.',
['Rí']='Ríta:BAABLgAECn8VAAIfAAYJSg7OIQDUAAAfAAYJSg7OIQDUAAAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Sarnt:BAAALgAECggJBAAAAA==.Sass:BAABLgAECn8sAAMGAAkJjxwHCwB+AgAGAAkJjxwHCwB+AgAFAAMJSwtRigB/AAABLgAFFAEJAgARAAAAAA==.Satella:BAAALgAECgcJBwABLgAFFAcJEQAEAIEcAA==.',
Sc='Schattën:BAABLgAECn8fAAIaAAgJIg3dLQBdAQAaAAgJIg3dLQBdAQAAAA==.Scibiol:BAAALgADCgkJEgAAAA==.',
Se='Senseideath:BAAALgAFFAIJAgABLgADCgcJBwARAAAAAA==.Serrana:BAAALgAECgQJDgAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shadax:BAAALgAECgQJCAAAAA==.Shaka:BAAALgADCgEJAQAAAA==.Shakz:BAAALgAECgYJBwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAAALgAFFAEJAwABLgAFFAQJCwAIAJAdAA==.Shirokhan:BAABLgAECn8mAAIIAAgJeB2HKQBXAgAIAAgJeB2HKQBXAgAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgAECgIJAgAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAABLgAECn8/AAMEAAkJkyRHAwBPAwAEAAkJkyRHAwBPAwADAAMJoRkfRwCaAAAAAA==.',
Sn='Snagglespark:BAACLgAFFH8FAAIUAAMJeRPFJADYAAAUAAMJeRPFJADYAAAuAAQKfzEAAhQACQnQGs8TACECABQACQnQGs8TACECAAAA.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8mAAIBAAgJsBmtMADkAQABAAgJsBmtMADkAQAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwARAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgUJCAAAAA==.Spinna:BAAALgAECgEJAQAAAA==.',
St='Starlisia:BAABLgAECn8VAAIHAAgJ3A3KHwALAQAHAAgJ3A3KHwALAQAAAA==.Starvnmarvn:BAAALgAECgUJBQAAAA==.Starz:BAAALgAECgcJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAQJDgAgAN4SAA==.',
Su='Suhdrake:BAABLgAECn8oAAIZAAgJ3xqbBwBdAgAZAAgJ3xqbBwBdAgAAAA==.Sunwing:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaraa:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAAALgAECggJDgAAAA==.',
['Só']='Sóozabimaru:BAAALgAECgcJDAAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8jAAMLAAgJOg+qHgCqAQALAAgJOg+qHgCqAQAMAAEJ+QIeaQAmAAAAAA==.',
Ta='Tahano:BAAALgADCgEJAQAAAA==.Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8qAAISAAgJLBpWDAAAAgASAAgJLBpWDAAAAgAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAAEAAEZAA==.',
Tc='Tcharta:BAABLgAECn8qAAIZAAgJHhwuBQCoAgAZAAgJHhwuBQCoAgAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgIJAgABLgAFFAMJBQANACsgAA==.Thoror:BAAALgAECgUJCAAAAA==.Thranduil:BAAALgADCgUJBQAAAA==.Thunderblap:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.Thunderbolt:BAAALgADCgkJCwABLgADCgcJBwARAAAAAA==.Thymós:BAAALgAECgEJAQAAAA==.',
Ti='Tiamat:BAAALgADCgcJBwAAAA==.Tiffina:BAAALgAECggJDwAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.Titum:BAABLgAFFH8IAAMlAAQJ7QXACgB0AAAEAAQJ7QVSUQD6AAAlAAIJXQPACgB0AAAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.Totamus:BAAALgADCgEJAQAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQAAAA==.Trissara:BAAALgAECgcJCgAAAA==.Trolli:BAABLgAECn8rAAITAAgJTiTLEADHAgATAAgJTiTLEADHAgAAAA==.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.',
Tw='Twixx:BAABLgAFFH8PAAImAAQJ9xOUBwA3AQAmAAQJ9xOUBwA3AQAAAA==.',
Ty='Tyinar:BAAALgAECgEJBAAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAABLgAECn8bAAMDAAgJxgcIHQCdAAAEAAgJwgd2hAAcAQADAAcJsAIIHQCdAAAAAA==.',
Ud='Uddercover:BAABLgAECn8VAAIcAAYJ7RQcIgBWAQAcAAYJ7RQcIgBWAQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECggJIAAWAH8kAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQARAAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIYAAMJiSGdfADZAAAYAAMJiSGdfADZAAAuAAQKfxwAAxgABgkdJuY9AEACABgABgkdJuY9AEACACIAAQnNIT48AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vathen:BAABLgAECn8UAAIEAAcJARmNOQAlAgAEAAcJARmNOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8ZAAQLAAYJWBFdLgA5AQALAAYJQg9dLgA5AQACAAQJMA/9WADQAAAMAAIJ4QcjdAAuAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAACLgAFFH8HAAIiAAMJxxCVHQC7AAAiAAMJxxCVHQC7AAAuAAQKfyEAAiIACAkUG2wQANQBACIACAkUG2wQANQBAAAA.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAECgkJHAATACkSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAFFAEJAQARAAAAAA==.Vokzhen:BAABLgAECn8dAAIMAAgJSRY8GQDXAQAMAAgJSRY8GQDXAQAAAA==.Volescu:BAAALgAECgIJBQAAAA==.',
Wa='Walkerboah:BAABLgAECn8pAAMEAAgJQBFPUwCLAQAEAAgJQBFPUwCLAQADAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAABLgAECn8VAAIIAAYJdBrrkQA5AQAIAAYJdBrrkQA5AQAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECggJFgANAGchAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAcJGAAOAKckAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAcJGAAOAKckAA==.Xeromus:BAABLgAECn8kAAMGAAgJzRdmGQDTAQAGAAgJzRdmGQDTAQAFAAIJ8wRktQA6AAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Xt='Xtoddgam:BAAALgAECgUJBQAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yo='Yozitga:BAAALgAECgMJAwAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Yv='Yvelmaya:BAAALgAECgEJAQAAAA==.',
Za='Zabawaba:BAABLgAECn8XAAMXAAkJ1RhYGQAUAgAXAAkJ1RhYGQAUAgAfAAIJkwGeSgAcAAAAAA==.Zaboomaprune:BAAALgAECggJCwAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJDQABLgAECgkJNQAOAGEkAA==.Zarika:BAABLgAECn8aAAMnAAgJySEmAgCLAgAnAAgJySEmAgCLAgAcAAQJhhIeTgC6AAABLgAFFAcJGAAOAKckAA==.Zarì:BAACLgAFFH8YAAIOAAcJpyShAACEAgAOAAcJpyShAACEAgAuAAQKfxwAAg4ACQnfJQ4DAGUDAA4ACQnfJQ4DAGUDAAAA.Zaö:BAAALgAECgEJAQABLgAECgkJNQAOAGEkAA==.',
Ze='Zeblaw:BAABLgAECn8uAAIIAAgJTBhHRgDtAQAIAAgJTBhHRgDtAQAAAA==.Zenazure:BAAALgAECgYJCwAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgAECgEJAQAAAA==.',
['Zà']='Zàomega:BAABLgAECn81AAMOAAkJYSTiAQBFAwAOAAkJYSTiAQBFAwAVAAEJuA/xawAqAAAAAA==.',
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
