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

local lookup = {'Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Rogue-Assassination','Monk-Brewmaster','Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warlock-Destruction','Paladin-Retribution','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Druid-Feral','Paladin-Holy','Priest-Holy','Monk-Windwalker','Rogue-Outlaw','Monk-Mistweaver','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ag='Agonie:BAAALgAECgEJAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAECggJIAABAPEhAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgEJAgAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8HAAICAAMJuSG4EQAfAQACAAMJuSG4EQAfAQAuAAQKfxYABAIACAmQH/wPAL4CAAIACAl+H/wPAL4CAAMAAgnjGeIkAKIAAAQAAQlSJBWxAGoAAAAA.Ambassadordh:BAAALgAECgIJAgAAAA==.Amoteph:BAAALgADCgQJBAAAAA==.',
An='Anoiche:BAABLgAECn8WAAIFAAgJaBwqOgAMAgAFAAgJaBwqOgAMAgAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8MAAIFAAUJ9RQGKAAtAQAFAAUJ9RQGKAAtAQAuAAQKfysAAgUABwlzHoQqANcBAAUABwlzHoQqANcBAAAA.',
At='Atilia:BAAALgAECgQJBAABLgAECgkJNQAGAH8jAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAHAAAAAA==.',
Av='Avanzo:BAAALgAECgMJAwAAAA==.',
Ax='Axeldaur:BAAALgADCgMJAwAAAA==.Axelrod:BAABLgAECn8XAAMIAAkJER+ZFgBkAgAIAAgJKh6ZFgBkAgAJAAIJYSX+GQBuAAAAAA==.',
Az='Azucena:BAAALgAECgMJAwAAAA==.',
Ba='Bananos:BAACLgAFFH8MAAMJAAQJuxVzAQBXAQAJAAQJuxVzAQBXAQAIAAEJpgQVlwA7AAAuAAQKfx0AAwkACAk4HPMBALUCAAkACAk4HPMBALUCAAgAAwk3CLfvADoAAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAAALgAFFAMJBAAAAA==.Bertram:BAABLgAECn8iAAIKAAcJUwUYQQDWAAAKAAcJUwUYQQDWAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgQJBAAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgUJDQAAAA==.Booze:BAABLgAECn8gAAMBAAgJ8SEiCwAlAgABAAcJ4CEiCwAlAgALAAIJzRxyEwCmAAAAAA==.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAFAE4TAA==.',
Ch='Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8cAAIMAAgJCARpNQDsAAAMAAgJCARpNQDsAAABLgAFFAQJDQAKAPAMAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgADCgkJCQAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.',
De='Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAAALgAECgYJCgAAAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMKAAgJQxWTKABTAQAKAAcJjhOTKABTAQANAAQJ+QYLbwCdAAAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIOAAQJkhA7HAAzAQAOAAQJkhA7HAAzAQAuAAQKfyIAAg4ACAnoIAkcANYCAA4ACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8PAAIPAAQJ5B2xJgBqAQAPAAQJ5B2xJgBqAQAuAAQKfx0AAg8ACQn0Hx45AJECAA8ACQn0Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgADCgYJBgABLgAECgYJHAABALUdAA==.',
El='Elmono:BAACLgAFFH8YAAIPAAYJQBiiFQCxAQAPAAYJQBiiFQCxAQAuAAQKfz4AAg8ACQnwI8UGACMDAA8ACQnwI8UGACMDAAAA.Elusivepanda:BAABLgAECn8XAAMQAAgJ3yIoBwBXAgAQAAgJ3yIoBwBXAgAJAAEJXxWnIgBBAAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8YAAIRAAkJPBOxLAAFAgARAAkJPBOxLAAFAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8PAAIEAAUJQxdTHQA/AQAEAAUJQxdTHQA/AQAuAAQKfzIABAQACAlMJEkEAEsDAAQACAlMJEkEAEsDAAIABgmTDj5NABwBAAMAAgmAFiI5AIoAAAAA.',
Es='Espresso:BAAALgADCgcJBwAAAA==.',
Eu='Eucharistica:BAACLgAFFH8PAAIFAAYJWhguDwCmAQAFAAYJWhguDwCmAQAuAAQKf00AAgUACQkWJbIBAFYDAAUACQkWJbIBAFYDAAAA.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAISAAcJch+IFwAMAgASAAcJch+IFwAMAgABLgAFFAMJBAAFAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Far:BAACLgAFFH8PAAMEAAUJQRuEEABnAQAEAAUJQRuEEABnAQADAAQJ4Q1qFADvAAAuAAQKfy8ABAQACAkvIvkOAJICAAQACAkvIvkOAJICAAMABwmVHFMSANEBAAIABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8rAAMTAAgJYhoADwCGAgATAAgJYhoADwCGAgAUAAcJAxTXDgCUAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAISAAkJPSSjAgD2AgASAAkJPSSjAgD2AgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8fAAMNAAYJGCG1IgAPAgANAAYJGCG1IgAPAgAKAAYJgRFXTQASAQABLgAECggJGgAVAO0PAA==.Funnelcake:BAAALgADCgcJBwAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIVAAgJ7Q9bFADGAQAVAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAVAO0PAA==.Fzyy:BAAALgADCgMJAwABLgAECggJGgAVAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAFAE4TAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAABLgAECn8jAAIWAAgJlRd8FQDOAQAWAAgJlRd8FQDOAQAAAA==.Goril:BAACLgAFFH8EAAIFAAMJThOcPgDhAAAFAAMJThOcPgDhAAAuAAQKfxgAAgUACAkEG4keABkCAAUACAkEG4keABkCAAAA.Goryious:BAACLgAFFH8HAAIOAAMJowpWLQDmAAAOAAMJowpWLQDmAAAuAAQKfx4AAg4ACQmeFhhAADgCAA4ACQmeFhhAADgCAAEuAAUUBQkNAAIAHRwA.',
Gr='Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAABLgAECn8iAAMEAAgJTx4GIgA5AgAEAAgJwBwGIgA5AgADAAcJOxy8EwDBAQAAAA==.',
Ha='Halarda:BAABLgAECn8dAAMEAAcJuBuRQQCGAQAEAAcJuBuRQQCGAQACAAUJAhC1UAALAQAAAA==.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8wAAINAAgJdR6ECwC1AgANAAgJdR6ECwC1AgAAAA==.',
Ho='Hooves:BAACLgAFFH8aAAIXAAYJxBWrAgCGAQAXAAYJxBWrAgCGAQAuAAQKfz0AAhcACQkpI/QAAGQDABcACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJCgAAAA==.',
Im='Imàdrood:BAABLgAECn82AAMYAAkJaRvyFABbAgAYAAkJaRvyFABbAgAZAAkJwxUuEAANAgAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn9HAAMNAAgJ6xX2HwD4AQANAAgJ6xX2HwD4AQAaAAgJEQ2qDwBCAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAHAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCQABLgAFFAEJAQAHAAAAAA==.',
Jp='Jpl:BAABLgAECn8UAAIEAAkJJQeRQgCCAQAEAAkJJQeRQgCCAQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAbAHYdAA==.Kamideath:BAAALgAECgQJCAABLgAECgcJOgAPAPAkAA==.Kamidh:BAAALgADCgkJFQABLgAECgcJOgAPAPAkAA==.Kamihunt:BAAALgADCgQJBAABLgAECgcJOgAPAPAkAA==.Kamikozy:BAABLgAECn86AAIPAAcJ8CQYJgDaAgAPAAcJ8CQYJgDaAgAAAA==.Kasharas:BAABLgAECn8dAAMNAAgJFA0kPABcAQANAAgJFA0kPABcAQAKAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMRAAcJvyPaHAC9AgARAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgEJAgAAAA==.Khealer:BAABLgAECn8cAAIdAAgJnRMXFgDXAQAdAAgJnRMXFgDXAQAAAA==.Khunter:BAAALgADCgcJBwAAAA==.',
Ki='Kindi:BAABLgAECn8fAAIcAAcJcyOBCQCuAgAcAAcJcyOBCQCuAgAAAA==.Kitymeowmeow:BAACLgAFFH8UAAIeAAUJHyO9AwCSAQAeAAUJHyO9AwCSAQAuAAQKfy4AAh4ACQkhJkoCAHwDAB4ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8NAAIKAAQJ8AwjGAARAQAKAAQJ8AwjGAARAQAuAAQKfzwAAgoACQmfGvQPACMCAAoACQmfGvQPACMCAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIMAAYJHR+1HgByAQAMAAYJHR+1HgByAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAAALgAECgkJCgAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAAALgAECgYJEwAAAA==.',
Li='Lilithe:BAAALgADCgkJCQAAAA==.Lillyvera:BAAALgAECgEJAQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAAALgAECgUJDQAAAA==.',
Lu='Lucia:BAABLgAECn8iAAIRAAgJ1hQ0QQC6AQARAAgJ1hQ0QQC6AQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAQAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAHAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn8rAAMBAAgJRR3vCwAZAgABAAgJRR3vCwAZAgAfAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn81AAIGAAkJfyMJAQD2AgAGAAkJfyMJAQD2AgAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECggJKwATAGIaAA==.Maylida:BAAALgAECgQJBAABLgAFFAYJBwACALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgMJAwAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJAgAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAIKAAgJgSQsBgC/AgAKAAgJgSQsBgC/AgAAAA==.Montar:BAABLgAECn8jAAIEAAcJziPVFQBaAgAEAAcJziPVFQBaAgAAAA==.Moonjuice:BAABLgAECn8kAAMYAAkJ9xGSSgB4AQAYAAgJaBCSSgB4AQAZAAcJqAhzNADsAAAAAA==.Moonlightt:BAAALgAECgQJBAAAAA==.',
Na='Nahaii:BAACLgAFFH8GAAIOAAMJRQ26ZQDqAAAOAAMJRQ26ZQDqAAAuAAQKfyQAAg4ACAmkGpA8AMkBAA4ACAmkGpA8AMkBAAEuAAUUBQkPAAQAQRsA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Nelos:BAABLgAECn8sAAIgAAgJ6hoKEAA8AgAgAAgJ6hoKEAA8AgAAAA==.Neovisus:BAAALgAFFAIJAwAAAA==.',
Ni='Nia:BAABLgAECn8YAAMNAAkJ3x2xBwDtAgANAAkJ3x2xBwDtAgAKAAEJbBpRbABIAAAAAA==.Nineline:BAAALgADCgEJAQABLgAECgYJHgAMAOUcAA==.',
No='Nozarashi:BAABLgAECn8iAAIOAAcJEB/uMAD0AQAOAAcJEB/uMAD0AQAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIMAAMJbBF5KADRAAAMAAMJbBF5KADRAAAuAAQKfy0AAgwACQnvHV0TAHYCAAwACQnvHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAYJGAAPAEAYAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgADCgcJBwAAAA==.',
Po='Poisontips:BAAALgAECgQJCAAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8rAAIEAAgJtB9qFgBWAgAEAAgJtB9qFgBWAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJBwACALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAISAAgJ+x91CQDLAgASAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8jAAIOAAYJqQ+doAA/AQAOAAYJqQ+doAA/AQAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sanctu:BAAALgAECgUJDgABLgAFFAUJDAAFAPUUAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Si='Silico:BAAALgAECgEJAgABLgAECgEJAgAHAAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgEJAgAHAAAAAA==.',
Sk='Skywarp:BAAALgAECgcJBwAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8YAAIdAAgJlQ16JABYAQAdAAgJlQ16JABYAQAAAA==.Smol:BAABLgAECn8dAAIPAAYJMw8ajQAjAQAPAAYJMw8ajQAjAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAbAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgcJGgAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Superspike:BAACLgAFFH8TAAIPAAUJGx7jKgBgAQAPAAUJGx7jKgBgAQAuAAQKfysAAg8ACQmLIyQYABoDAA8ACQmLIyQYABoDAAAA.Surshock:BAABLgAECn8eAAIKAAkJzBQ+KQDLAQAKAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgYJCAAAAA==.',
Ta='Taekay:BAABLgAFFH8GAAMhAAMJ4iBLDwAUAQAhAAMJ4iBLDwAUAQAOAAIJsgpnnQCNAAABLgAFFAgJKAAMABYiAA==.Takamine:BAABLgAECn8tAAIbAAkJlhEDCQDaAQAbAAkJlhEDCQDaAQAAAA==.Talath:BAABLgAECn8VAAITAAYJMBWHLQBWAQATAAYJMBWHLQBWAQAAAA==.Talos:BAABLgAECn8TAAIFAAkJwQiFgQAmAQAFAAkJwQiFgQAmAQAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8kAAQiAAgJpB36FAD9AQAiAAgJVB36FAD9AQAjAAIJrRcCLQCNAAAVAAMJ/A3vLACKAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgADCgYJCAAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAIkAAgJNR8RAgBMAgAkAAgJNR8RAgBMAgAAAA==.Vanillarista:BAABLgAECn8YAAIWAAgJLRb1FQDJAQAWAAgJLRb1FQDJAQAAAA==.Varwyn:BAAALgADCgMJAwAAAA==.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAIOAAYJxBq0fwAaAQAOAAYJxBq0fwAaAQAAAA==.',
We='Weeple:BAAALgADCgYJBgAAAA==.Wesdarian:BAAALgAECgUJBQAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8WAAIYAAgJ2RKnVABVAQAYAAgJ2RKnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIPAAUJuA3lugDSAAAPAAUJuA3lugDSAAAAAA==.',
Xi='Xirious:BAABLgAFFH8FAAIOAAIJjQu5kgCYAAAOAAIJjQu5kgCYAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8oAAIFAAgJ9BzjGgAwAgAFAAgJ9BzjGgAwAgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMeAAgJURuAFABJAgAeAAgJURuAFABJAgAMAAQJiAtmSwCXAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgYJHAABALUdAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQPAAgJnxuLPADmAQAPAAgJnxuLPADmAQAlAAEJnBkbDgBHAAAkAAEJPAnSDQAvAAABLgAECgkJCgAHAAAAAA==.',
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
