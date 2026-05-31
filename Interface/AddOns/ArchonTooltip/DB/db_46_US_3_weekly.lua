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

local lookup = {'Mage-Frost','Paladin-Retribution','Warrior-Arms','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Druid-Guardian','Paladin-Holy','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abeblinkin:BAABLgAECn85AAIBAAkJoyA5FQDFAgABAAkJoyA5FQDFAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9HAAICAAkJ0ROKUAC+AQACAAkJ0ROKUAC+AQAAAA==.',
Aj='Ajm:BAABLgAFFH8IAAIDAAQJgRQJEwAbAQADAAQJgRQJEwAbAQAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIEAAgJQCNZAQAYAwAEAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8tAAMFAAkJnxqZDgBgAgAFAAkJnxqZDgBgAgAGAAIJqQkFNwBfAAABLgAFFAgJHAAHABIVAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAIAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJDwAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJBQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgQJBQAAAA==.Annisseda:BAACLgAFFH8bAAMJAAUJcB5+DQB3AQAJAAUJcB5+DQB3AQADAAEJAAB7PAAAAAAuAAQKfysAAwkACQmLJD8GAOsCAAkACQmLJD8GAOsCAAMAAQl9IShXAFoAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJDQAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAgJGQAIAAAAAQ==.Articuno:BAAALgAECgUJDQAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Ashér:BAAALgAECgEJAQAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgUJCwAAAA==.',
Az='Azzy:BAACLgAFFH8fAAIJAAcJPB5YAgAtAgAJAAcJPB5YAgAtAgAuAAQKfz4AAgkACQnlJXgCAJMDAAkACQnlJXgCAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQKAAgJVhXKHQDRAQAKAAgJ8xLKHQDRAQALAAYJWQ+MigDtAAAEAAIJBiGBJABfAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwZz3wDAAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAECgkJMAAOAJ8WAA==.',
Be='Beeflocks:BAABLgAECn8dAAIPAAkJBRhFBwDdAQAPAAkJBRhFBwDdAQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAIAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgQJBAAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIJAAcJyxwLIwA9AgAJAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJBwAAAA==.Billyspike:BAABLgAECn8YAAMTAAYJ0RrjDQDVAQATAAYJ0RrjDQDVAQAUAAEJkhILfQA2AAABLgAECgkJEwAIAAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgkJEwAIAAAAAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgkJEwAIAAAAAA==.Billyspikepd:BAAALgAECgkJEwAAAA==.Billyspikepr:BAAALgAECgUJCAABLgAECgkJEwAIAAAAAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RQJPAAcAQACAAQJ0RQJPAAcAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAABLgAECn8YAAIVAAcJGxHuhgBBAQAVAAcJGxHuhgBBAQAAAA==.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8aAAIHAAUJoR1hKwBsAQAHAAUJoR1hKwBsAQAuAAQKfywABAcACQl+If8MANgCAAcACQl+If8MANgCABYAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bothenheim:BAACLgAFFH8YAAMCAAUJGSSIFwCDAQACAAUJGSSIFwCDAQAMAAIJwAq1DwBmAAAuAAQKfyYAAgIACQmAIv8QAMoCAAIACQmAIv8QAMoCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8LAAIXAAcJ7wuEEAC3AQAXAAcJ7wuEEAC3AQAAAA==.Brüisér:BAABLgAECn8kAAIMAAkJbg+VFQBfAQAMAAkJbg+VFQBfAQAAAA==.',
Bu='Bublz:BAAALgAECgcJBwAAAA==.Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgMJBAAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJBwAAAA==.Carathea:BAABLgAECn8iAAIYAAgJMSCCDACLAgAYAAgJMSCCDACLAgAAAA==.Cardstock:BAAALgAECggJCAABLgAFFAgJGQAIAAAAAQ==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8WAAIZAAUJSCEHDgDnAQAZAAUJSCEHDgDnAQAuAAQKfyAAAhkACAm3HkIRAK0CABkACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8SAAMHAAQJCh6sLQBkAQAHAAQJRBysLQBkAQAPAAEJ6RmCFQBYAAAuAAQKfysAAwcACQnMIakFAGIDAAcACQnMIakFAGIDABYAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8QAAIBAAcJSxjtCgDHAQABAAcJSxjtCgDHAQAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAECgEJAQAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAABLgAECn8WAAIaAAYJSxLdCQBGAQAaAAYJSxLdCQBGAQABLgAFFAYJDgAXACobAA==.',
Co='Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAYADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgAECgUJBQABLgAFFAYJDgAXACobAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8pAAIJAAgJAhC/LQCGAQAJAAgJAhC/LQCGAQAAAA==.',
De='Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgADCgkJDQAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8iAAIUAAkJVg2BJQCGAQAUAAkJVg2BJQCGAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8WAAMNAAYJOByCJgBLAQANAAUJKiGCJgBLAQAbAAEJcQggKgBNAAAuAAQKfyEAAw0ACQlYIuASAKACAA0ACAk6HuASAKACABsABglxILUoAOQBAAAA.Demonpunter:BAAALgAFFAEJAQAAAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAmwRwADAQACAAQJnAmwRwADAQAuAAQKfyQAAwwABwniHYENAO8BAAwABwk4GYENAO8BAAIABwlnGyVcAKEBAAAA.',
Di='Dinoscarr:BAAALgAECgQJCQAAAA==.',
Dj='Djholy:BAAALgAECgcJDwAAAA==.',
Do='Dotmaxxing:BAAALgAECgYJCAAAAA==.Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAABLgAECn8bAAIRAAkJ0h5wCQCzAgARAAkJ0h5wCQCzAgAAAA==.',
Dr='Drarmaku:BAAALgAECgIJAgAAAA==.Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgUJBgAAAA==.Dungorogue:BAABLgAECn8fAAIcAAgJEA6cHQCQAQAcAAgJEA6cHQCQAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8zAAMYAAkJqxHmHwCuAQAYAAgJqRLmHwCuAQAdAAkJgQYMMwArAQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAECgQJBQAAAA==.',
En='Eniacoc:BAAALgAECgkJCQAAAA==.Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB7INAAVAgACAAgJdB7INAAVAgABLgAFFAcJEAABAEsYAA==.Excerpt:BAAALgAECgMJAwABLgAFFAcJEAABAEsYAA==.Exortus:BAAALgAFFAMJAwABLgAFFAUJGAACABkkAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgADCgUJDAAAAA==.',
Fe='Fellirane:BAAALgADCgUJBQAAAA==.Fernsama:BAAALgAECgYJBwAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ4Q1DegAQAQALAAcJ4Q1DegAQAQAAAA==.',
Fr='Fraternite:BAAALgAECgcJCwAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAIAAAAAA==.Fruto:BAABLgAECn8wAAIOAAkJnxaXFAD4AQAOAAkJnxaXFAD4AQAAAA==.',
Ga='Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8PAAIJAAYJlBdHDACAAQAJAAYJlBdHDACAAQAuAAQKfyEAAgkACQn9IKEEAF8DAAkACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUBwkLABcA7wsA.Goku:BAAALgAECgQJBAAAAA==.Gothmommy:BAAALgADCgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJCwAXAO8LAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAIAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw1ZUwBIAQAQAAcJNw1ZUwBIAQARAAQJPwLJewBVAAAAAA==.Griphöök:BAAALgAECgEJAQAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAECgEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAECgQJDgAAAA==.',
Ha='Hairball:BAABLgAECn8eAAIeAAkJNBOPEAAdAgAeAAkJNBOPEAAdAgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgMJAwABLgAECgkJIgATAFgQAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAAALgAFFAMJBAAAAA==.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jabzulsor:BAAALgAECgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIVAAgJtw7ydABlAQAVAAgJtw7ydABlAQAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8yAAINAAkJpR01FQCTAgANAAkJpR01FQCTAgAAAA==.',
Ju='Jutti:BAAALgAECgQJCQAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kaluaruun:BAAALgADCgYJBgAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8dAAMXAAcJtwjmEwCRAQAXAAcJtwjmEwCRAQAfAAEJ5gZ+OQA6AAAuAAQKfz4AAxcACQkiG0oLAJwCABcACQkiG0oLAJwCAB8AAQknB22ZACkAAAAA.Kartiri:BAACLgAFFH8YAAMgAAUJnRjwDgCGAQAgAAUJnRjwDgCGAQAFAAQJpAl/PQCwAAAuAAQKfy4ABCAACQmRHVoGAN4CACAACQmRHVoGAN4CAAUABQnWFhsvAF4BAAYABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8OAAMhAAUJ0CPuDAAJAgAhAAUJ0CPuDAAJAgAYAAEJRw6hLgA7AAAuAAQKfzAAAyEACQnEJQUBAL8DACEACQnEJQUBAL8DABgAAQlXHgBaAFcAAAAA.Keicelinis:BAABLgAECn8WAAILAAYJ9xLgcwAfAQALAAYJ9xLgcwAfAQAAAA==.Keratos:BAAALgAECgYJCQAAAA==.',
Kh='Khaalid:BAAALgAECgYJCgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAAALgAECgMJBQAAAA==.Korxin:BAACLgAFFH8TAAINAAYJIxiUEgCSAQANAAYJIxiUEgCSAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8PAAIZAAUJDxNjGQBvAQAZAAUJDxNjGQBvAQAuAAQKfzIAAhkACAnJITQOAMgCABkACAnJITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAABLgAECn8VAAMiAAgJVBQUFACVAQAiAAgJVBQUFACVAQAUAAQJEwyWVgDKAAAAAA==.',
La='Lanstan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgIJAgAAAA==.Leron:BAAALgAECgUJBQAAAA==.Levitticus:BAABLgAECn8wAAIjAAgJEB0SHgAmAgAjAAgJEB0SHgAmAgABLgAFFAYJDgAXACobAA==.',
Li='Liale:BAAALgAECgMJBAAAAA==.Lideyn:BAAALgAECgEJAQAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.',
Lo='Loinari:BAAALgAECgcJDwAAAA==.Lokano:BAAALgAECgQJBgAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8tAAMWAAkJ6A5mCQCVAQAWAAkJ6A5mCQCVAQAHAAEJ4QKiSAEdAAAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEgAIAAAAAA==.Magidragon:BAAALgAECgcJEgAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.',
Md='Mdavis:BAAALgADCgkJCgAAAA==.',
Me='Melt:BAACLgAFFH8cAAMHAAgJEhUdHACkAQAHAAcJEhcdHACkAQAWAAEJEAlAGwBVAAAuAAQKfz4AAwcACQl+I7sHAA0DAAcACQl+I7sHAA0DABYABAmoEncsAAwBAAAA.Metons:BAAALgAECggJDQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJBwAIAAAAAA==.Misfitdk:BAAALgAECgEJBAAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJBAAAAA==.Misfitmonk:BAAALgAECgEJAgAAAA==.Misfittotem:BAAALgAECgEJAgAAAA==.Mistfox:BAAALgAECgYJDAAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgMJBQAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECggJEwAAAA==.Naminé:BAAALgADCgMJAwABLgAECggJIQAkAKEeAA==.Nattyrav:BAACLgAFFH8MAAIlAAQJnR35BQBBAQAlAAQJnR35BQBBAQAuAAQKfygAAyUACQkbH8ADAO4CACUACQlnHsADAO4CABEABgnHG7kxAFwBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn9KAAMfAAkJ1hiiDgBIAgAfAAkJ1hiiDgBIAgAXAAEJUAOjsAAcAAAAAA==.Neryssa:BAACLgAFFH8XAAQHAAgJyho9DwD1AQAHAAcJvBo9DwD1AQAWAAEJYRXSFwBcAAAPAAEJpRxkFABaAAAuAAQKfzoAAwcACQnYJOUGABgDAAcACAlvJOUGABgDABYABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.',
No='Nocter:BAABLgAECn8eAAQHAAkJwhxnNwAuAgAHAAcJZhxnNwAuAgAPAAUJUiCTCwCBAQAWAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJBQAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8bAAICAAYJwwa64QC9AAACAAYJwwa64QC9AAAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIYAAgJdBiJGADxAQAYAAgJdBiJGADxAQAAAA==.',
Oa='Oakhugger:BAABLgAECn8iAAMTAAkJWBCgDQC5AQATAAkJWBCgDQC5AQAUAAEJAAB1ngAAAAAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB5nQQDuAQALAAcJTB5nQQDuAQABLgAECggJIQAkAKEeAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olyvivia:BAAALgAECgMJAwAAAA==.',
Om='Omgega:BAABLgAECn8xAAICAAgJ1xmCUAC+AQACAAgJ1xmCUAC+AQAAAA==.',
On='Onichan:BAAALgAECgYJCQAAAA==.Onimeek:BAABLgAECn89AAMKAAkJ0x35CADTAgAKAAkJ0x35CADTAgALAAIJPAn/9QA4AAAAAA==.',
Or='Oryn:BAAALgAFFAEJAwAAAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAgJGQAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8OAAIXAAYJKhtNDADxAQAXAAYJKhtNDADxAQAuAAQKfyYAAxcACAn8HmoMALQCABcACAn8HmoMALQCAB8ABwnDFfIhAIoBAAAA.Pelagius:BAAALgADCgUJBQAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgcJAgAAAA==.Phyllus:BAAALgAFFAEJAQAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAABLgAECn8cAAIJAAgJzhgAGwABAgAJAAgJzhgAGwABAgAAAA==.',
Po='Poochimus:BAABLgAECn8hAAIlAAkJsRMMCQAWAgAlAAkJsRMMCQAWAgAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAAALgAECgcJDQAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAIAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAMJCwANAJANAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8VAAIhAAQJ9hWfHgAjAQAhAAQJ9hWfHgAjAQAuAAQKf0IAAiEACQnkIXwDAFUDACEACQnkIXwDAFUDAAEuAAUUBgkOABcAKhsA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh55SgCPAQALAAYJOh55SgCPAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMFAAgJPASuUADFAAAFAAgJPASuUADFAAAGAAEJjwENKQAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIfAAYJHR3jIgCDAQAfAAYJHR3jIgCDAQAAAA==.Rindra:BAAALgAECgUJBQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8YAAIVAAgJOhlIBwBnAgAVAAgJOhlIBwBnAgAuAAQKfzwAAhUACQk3JlwEAFMDABUACQk3JlwEAFMDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAgJGAAVADoZAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIJAAMJ1xhZKgDmAAAJAAMJ1xhZKgDmAAAuAAQKfyQAAgkACAneH28TALICAAkACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.Roxis:BAAALgADCgUJBQAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEg77fwAEAQALAAcJEg77fwAEAQAAAA==.Saero:BAABLgAECn8UAAIjAAcJbBncJgC9AQAjAAcJbBncJgC9AQAAAA==.Saluuknir:BAABLgAECn8wAAMFAAkJyg7DJQCWAQAFAAkJiQ7DJQCWAQAGAAYJaAeKIwAMAQAAAA==.Saphh:BAABLgAECn8aAAQmAAcJtBikEAA5AQAVAAcJshfMZgDBAQAmAAUJ/xmkEAA5AQAnAAQJQRV+MgC5AAABLgAFFAQJDAAmALAQAA==.Satrath:BAAALgAFFAIJBAAAAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgYJBwAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAAALgAFFAEJAQAAAA==.Sharky:BAAALgAFFAIJAwABLgAFFAcJIQABAFEdAA==.Shaulana:BAAALgADCgYJBgAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8bAAIiAAUJdSPzAwChAQAiAAUJdSPzAwChAQABLgAECggJFQAEAEAjAA==.',
Si='Siera:BAAALgAECgEJAQABLgAECggJDQAIAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8GAAIVAAIJ2wnOzgB9AAAVAAIJ2wnOzgB9AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIeAAkJ4RmrBgCWAgAeAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECggJDgAAAA==.',
Sn='Sneakylev:BAAALgADCgkJEwABLgAFFAYJDgAXACobAA==.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8MAAICAAMJHCHTRQAHAQACAAMJHCHTRQAHAQAuAAQKfyoAAgIACAkWI0srADsCAAIACAkWI0srADsCAAEuAAUUBAkFAAoAlBUA.Snuuzi:BAAALgAFFAEJAQABLgAFFAQJBQAKAJQVAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Solari:BAABLgAECn8aAAMLAAgJThtSMgDmAQALAAgJMRhSMgDmAQAKAAcJlhUVHwDGAQAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn9CAAICAAcJ5SB1NAAWAgACAAcJ5SB1NAAWAgAAAA==.Souprage:BAAALgAECggJEgAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAECggJIQAkAKEeAA==.Spywar:BAAALgAECgYJCAABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8qAAMdAAkJiAvjJwBvAQAdAAkJiAvjJwBvAQAYAAYJGQUxRADBAAAAAA==.Strentor:BAAALgAECgEJAQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAIAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8rAAIOAAgJFiKbAADJAgAOAAgJFiKbAADJAgAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDAB8AAgk5Hg1UAKMAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAUJGAACABkkAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8bAAIKAAcJsRIIIwA8AQAKAAcJsRIIIwA8AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDQAAAA==.Tharella:BAAALgAECgYJCQAAAA==.Thauriel:BAAALgAECgIJAgAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tipz:BAAALgAECgEJAQABLgAECgUJBQAIAAAAAA==.Titania:BAABLgAECn8eAAIjAAkJTAa9QAB1AQAjAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8LAAINAAMJkA0AUADgAAANAAMJkA0AUADgAAAuAAQKfxwAAg0ABwmiHIc/AMwBAA0ABwmiHIc/AMwBAAAA.Uggotroll:BAAALgAECgQJBAABLgAFFAMJCwANAJANAA==.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAYJHAAdAF8lAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAITAAgJUQ0/FQBKAQATAAgJUQ0/FQBKAQAAAA==.Valerian:BAAALgAECgcJCwAAAA==.Validori:BAAALgADCgEJAQAAAA==.Van:BAAALgADCgcJFAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Veinke:BAAALgAECgQJAwAAAA==.Vengefullev:BAAALgADCgMJAwABLgAFFAYJDgAXACobAA==.Venin:BAAALgAECgYJCwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgQJBQABLgADCgcJBwAIAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgYJCAAAAA==.',
Wo='Worldtree:BAAALgAECgQJCAAAAA==.',
Wy='Wynne:BAAALgAECgcJCAAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAIAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAIAAAAAA==.',
Xz='Xzarrion:BAAALgADCgIJAgAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihb0LgA3AQAOAAUJihb0LgA3AQAXAAYJoBARRAAoAQAfAAUJ3AdeXACKAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMYAAkJhRUbLgCMAQAYAAkJhRUbLgCMAQAdAAcJtwf8RwDIAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAIAAAAAA==.',
Za='Zalconn:BAACLgAFFH8SAAMcAAQJWSbpCADCAQAcAAQJWSbpCADCAQAkAAIJDRcbCgCZAAAuAAQKfykAAxwACQkNJToDAGwDABwACQnLJDoDAGwDACQAAQneJoIYAHIAAAAA.Zarrona:BAABLgAECn8hAAMkAAgJoR7vBAAQAgAkAAcJ+hzvBAAQAgAcAAcJkRqwGwChAQAAAA==.Zayah:BAABLgAECn8WAAIRAAgJyRTFJACpAQARAAgJyRTFJACpAQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgcJCAABLgAECgcJDwAIAAAAAA==.',
Zn='Znasty:BAABLgAECn8qAAIcAAgJhCQoBQDRAgAcAAgJhCQoBQDRAgAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
['Öw']='Öwö:BAAALgAECgEJAQAAAA==.',
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
