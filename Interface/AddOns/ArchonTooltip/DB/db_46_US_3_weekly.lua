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

local lookup = {'Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','Monk-Windwalker','Evoker-Preservation','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abeblinkin:BAABLgAECn85AAIBAAkJoyBoEgDSAgABAAkJoyBoEgDSAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJEx48JwCJAgACAAkJEx48JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn9CAAICAAkJ0ROjRQDWAQACAAkJ0ROjRQDWAQAAAA==.',
Aj='Ajm:BAAALgAFFAIJBAAAAA==.',
Ak='Akarii:BAAALgAECgYJEAAAAA==.Akeno:BAABLgAECn8VAAIDAAgJQCNZAQAYAwADAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8lAAMEAAkJuRkIEABJAgAEAAkJuRkIEABJAgAFAAIJqQkFNwBfAAABLgAFFAcJFwAGAJUVAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAHAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJDwAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
Am='Amellis:BAAALgAECgUJBQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgEJAQAAAA==.Annisseda:BAACLgAFFH8WAAMIAAUJMB00DABtAQAIAAUJMB00DABtAQAJAAEJAAB/MwAAAAAuAAQKfysAAwgACQmLJAQFAPcCAAgACQmLJAQFAPcCAAkAAQl9IaNOAFoAAAAA.',
Ar='Aradril:BAAALgADCgcJCwAAAA==.Arktos:BAAALgAECgYJCAAAAA==.Arrhythmia:BAAALgAECgkJJQABLgAFFAcJFgAHAAAAAQ==.Articuno:BAAALgAECgQJDAAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgUJCwAAAA==.',
Az='Azzy:BAACLgAFFH8YAAIIAAUJHSHrCABiAQAIAAUJHSHrCABiAQAuAAQKfz4AAggACQnlJeQBAEcDAAgACQnlJeQBAEcDAAAA.',
Ba='Babyboomie:BAAALgAECgUJBQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8kAAQKAAgJVhXKHQDRAQAKAAgJ8xLKHQDRAQALAAYJWQ9RfwD5AAADAAIJBiGwIQBgAAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAABLgAECn8VAAMMAAYJUQ2vJADjAAAMAAUJIA+vJADjAAACAAYJXwYSzADTAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8aAAINAAkJaw+WOADMAQANAAkJaw+WOADMAQAAAA==.Bassoon:BAAALgAECgMJAwABLgAECgkJLgAOAEMWAA==.',
Be='Beeflocks:BAABLgAECn8dAAIPAAkJBRgqBgDoAQAPAAkJBRgqBgDoAQAAAA==.Bekarn:BAABLgAECn8YAAMQAAcJeAofUwA5AQAQAAcJeAofUwA5AQARAAMJ7AhzegBaAAAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAHAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwASAHkdAA==.Bigdh:BAAALgAECgEJAQAAAA==.Bigdraco:BAAALgADCgQJBAAAAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIIAAcJyxwLIwA9AgAIAAcJyxwLIwA9AgAAAA==.Billski:BAAALgAECgcJBwAAAA==.Billyspike:BAABLgAECn8YAAMTAAYJ0RrjDQDVAQATAAYJ0RrjDQDVAQAUAAEJkhIMdAA2AAABLgAECgcJCwAHAAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgcJCwAHAAAAAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgcJCwAHAAAAAA==.Billyspikepd:BAAALgAECgcJCwAAAA==.Billyspikepr:BAAALgAECgUJCAABLgAECgcJCwAHAAAAAA==.',
Bl='Blammo:BAAALgADCgcJCQAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RSrMQArAQACAAQJ0RSrMQArAQAuAAQKfyAAAgIABwm7IW0dALoCAAIABwm7IW0dALoCAAAA.Bloodhase:BAABLgAECn8YAAIVAAcJGxH0fQBBAQAVAAcJGxH0fQBBAQAAAA==.Bloodprince:BAAALgAECgMJAwAAAA==.Bluecard:BAACLgAFFH8VAAIGAAUJ+RYFNQA7AQAGAAUJ+RYFNQA7AQAuAAQKfywABAYACQl+IWILAN4CAAYACQl+IWILAN4CABYAAwnVGMg5AM0AAA8AAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBQAAAA==.Bothenheim:BAACLgAFFH8TAAMCAAUJ2SPpFACAAQACAAUJ2SPpFACAAQAMAAIJwArMDQBmAAAuAAQKfyYAAgIACQmAIoAOANcCAAIACQmAIoAOANcCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8LAAIXAAcJ7wsiDADOAQAXAAcJ7wsiDADOAQAAAA==.Brüisér:BAABLgAECn8kAAIMAAkJbg/FEwBhAQAMAAkJbg/FEwBhAQAAAA==.',
Bu='Bumpinuglies:BAAALgAECgEJAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgAECgQJBAAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJBwAAAA==.Carathea:BAABLgAECn8iAAIYAAgJMSCCDACLAgAYAAgJMSCCDACLAgAAAA==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8RAAIZAAUJtxn0DwCrAQAZAAUJtxn0DwCrAQAuAAQKfyAAAhkACAm3HkIRAK0CABkACAm3HkIRAK0CAAAA.Cayth:BAACLgAFFH8LAAMGAAQJQhgPNgA4AQAGAAQJQhgPNgA4AQAPAAEJjQ9YGABNAAAuAAQKfysAAwYACQnMIakFAGIDAAYACQnMIakFAGIDABYAAgkLAx9VAG8AAAAA.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8QAAIBAAcJSxjtCgDHAQABAAcJSxjtCgDHAQAuAAQKfyQAAgEACQlGJRYaAA8DAAEACQlGJRYaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAAALgAECggJEAAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgAECgEJAQAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAAALgAECgYJEQABLgAFFAYJDQAXAMMYAA==.',
Co='Colivism:BAABLgAECn8kAAIBAAgJpRaleQDeAQABAAgJpRaleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAYADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgADCgkJEwABLgAFFAYJDQAXAMMYAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8jAAIIAAgJSw7lLAB5AQAIAAgJSw7lLAB5AQAAAA==.',
De='Deathsgrace:BAAALgAECgkJCQAAAA==.Deathtank:BAAALgADCgkJCgAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8iAAIUAAkJVg1sIgCIAQAUAAkJVg1sIgCIAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8UAAINAAUJKiG4HABRAQANAAUJKiG4HABRAQAuAAQKfyEAAw0ACQlYIuASAKACAA0ACAk6HuASAKACABoABglxILUoAOQBAAAA.Demonpunter:BAAALgAECgYJDwAAAA==.Dewussi:BAACLgAFFH8TAAICAAQJnAk8PAARAQACAAQJnAk8PAARAQAuAAQKfyQAAwwABwniHYENAO8BAAwABwk4GYENAO8BAAIABwlnG5xUAK0BAAAA.',
Di='Dinoscarr:BAAALgAECgQJCQAAAA==.',
Dj='Djholy:BAAALgAECgcJDgAAAA==.',
Do='Dotmaxxing:BAAALgAECgIJAgAAAA==.Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAABLgAECn8bAAIRAAkJ0h5ECAC4AgARAAkJ0h5ECAC4AgAAAA==.',
Dr='Dreadingfate:BAAALgAECgkJEAAAAA==.Drscholar:BAAALgAECgIJAwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Duber:BAAALgAECgIJAgAAAA==.Dungorogue:BAABLgAECn8XAAIbAAgJpQxpHQCAAQAbAAgJpQxpHQCAAQAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
['Dé']='Déwéy:BAAALgAECgIJAgABLgAFFAQJEwACAJwJAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8yAAMYAAkJqxGUHQC0AQAYAAgJqRKUHQC0AQAcAAkJrgWzLQBCAQAAAA==.Elivoker:BAAALgAECgYJAwAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAECgQJBQAAAA==.',
En='Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJdB7wLgAjAgACAAgJdB7wLgAjAgABLgAFFAcJEAABAEsYAA==.Excerpt:BAAALgAECgMJAwABLgAFFAcJEAABAEsYAA==.Exortus:BAAALgAFFAMJAwABLgAFFAUJEwACANkjAA==.',
Fa='Falloutman:BAAALgAECgEJAQAAAA==.Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgADCgUJDAAAAA==.',
Fe='Fernsama:BAAALgAECgYJBwAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAABLgAECn8XAAILAAcJ4Q2HcgAWAQALAAcJ4Q2HcgAWAQAAAA==.',
Fr='Fraternite:BAAALgAECgcJCgAAAA==.Froackeh:BAAALgAECggJBwAAAA==.Froackie:BAAALgAECgYJEAABLgAECggJBwAHAAAAAA==.Fruto:BAABLgAECn8uAAIOAAkJQxbfEwDyAQAOAAkJQxbfEwDyAQAAAA==.',
Ga='Garzislao:BAAALgAECggJEAAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8NAAIIAAUJhRriFwAvAQAIAAUJhRriFwAvAQAuAAQKfyEAAggACQn9IKEEAF8DAAgACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIQAAUJlQiPBQBzAQAQAAUJlQiPBQBzAQAuAAQKfxcAAhAACAlLFqckAAMCABAACAlLFqckAAMCAAEuAAUUBwkLABcA7wsA.Goku:BAAALgAECgQJBAAAAA==.Gothmommy:BAAALgADCgIJAgAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJCwAXAO8LAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAHAAAAAA==.Grimreaper:BAABLgAECn8lAAMQAAcJNw2XTABJAQAQAAcJNw2XTABJAQARAAQJPwLJewBVAAAAAA==.Groldin:BAAALgAECgQJBgAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAECgEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAECgQJDgAAAA==.',
Ha='Hairball:BAABLgAECn8ZAAIdAAgJJRHgGAC6AQAdAAgJJRHgGAC6AQAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgAECgMJAwABLgAECgkJIAATABoPAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghziDwC8AgANAAkJghziDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ib='Ibefarmin:BAAALgAECgEJAQAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Iceshadow:BAAALgAECgYJCQAAAA==.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jacopo:BAABLgAECn8XAAIVAAgJtw4lbABoAQAVAAgJtw4lbABoAQAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8yAAINAAkJpR2mEQCbAgANAAkJpR2mEQCbAgAAAA==.',
Ju='Jutti:BAAALgAECgQJCQAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8YAAIXAAYJsgYWFQBdAQAXAAYJsgYWFQBdAQAuAAQKfz4AAxcACQkiG0oLAJwCABcACQkiG0oLAJwCAB4AAQknB6mMACkAAAAA.Kartiri:BAACLgAFFH8TAAMfAAUJzRy+EABPAQAfAAQJLh2+EABPAQAEAAQJpAktNgC7AAAuAAQKfy0ABB8ACQmRHVoGAN4CAB8ACQmRHVoGAN4CAAQABQnWFiQsAGcBAAUABQkPGM0lAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAACLgAFFH8JAAIgAAMJACSNGQA9AQAgAAMJACSNGQA9AQAuAAQKfygAAiAACQmJJS4BALYDACAACQmJJS4BALYDAAAA.Keicelinis:BAABLgAECn8WAAILAAYJ9xKBbQAiAQALAAYJ9xKBbQAiAQAAAA==.Keratos:BAAALgAECgYJBgAAAA==.',
Kh='Khaalid:BAAALgAECgYJBgAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kimjoonsang:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Kipz:BAAALgAECgUJBQAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Kookykrook:BAAALgAECgEJAgAAAA==.Korxin:BAACLgAFFH8RAAINAAUJ6hyPIQBDAQANAAUJ6hyPIQBDAQAuAAQKfysAAg0ACQkpI+oEAD8DAA0ACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8NAAIZAAQJGBW/HgAuAQAZAAQJGBW/HgAuAQAuAAQKfzIAAhkACAnJITQOAMgCABkACAnJITQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.Krios:BAAALgADCgQJBAAAAA==.',
Ku='Kurquaan:BAAALgAECggJEwAAAA==.',
Le='Leilar:BAAALgAECgIJAgAAAA==.Leron:BAAALgAECgUJBQAAAA==.Levitticus:BAABLgAECn8wAAIhAAgJEB01GgAMAgAhAAgJEB01GgAMAgABLgAFFAYJDQAXAMMYAA==.',
Li='Liale:BAAALgAECgMJBAAAAA==.Lideyn:BAAALgAECgEJAQAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.',
Lo='Loinari:BAAALgAECgUJCQAAAA==.Lokano:BAAALgAECgQJBgAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAFFAEJAQAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgQJCQAAAA==.Lull:BAABLgAECn8lAAIWAAkJvwxZCgBwAQAWAAkJvwxZCgBwAQAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEgAHAAAAAA==.Magidragon:BAAALgAECgcJEAAAAA==.Magoraga:BAAALgADCgYJBgAAAA==.Mandrah:BAAALgADCgQJBQAAAA==.',
Md='Mdavis:BAAALgADCgkJCgAAAA==.',
Me='Melt:BAACLgAFFH8XAAMGAAcJlRW6DQBuAQAGAAYJFhi6DQBuAQAWAAEJEAnJFwBVAAAuAAQKfz4AAwYACQl+I54GABQDAAYACQl+I54GABQDABYABAmoEncsAAwBAAAA.Metons:BAAALgAECggJDQAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJBwAHAAAAAA==.Misfitdk:BAAALgAECgEJAwAAAA==.Misfitdots:BAAALgAECgEJAQAAAA==.Misfitmagi:BAAALgAECgEJAwAAAA==.Misfitmonk:BAAALgAECgEJAQAAAA==.Mistfox:BAAALgAECgUJBgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgMJBQAAAA==.Mommon:BAAALgAECgYJCAAAAA==.Moonraisin:BAAALgAECgMJBQAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECggJEwAAAA==.Naminé:BAAALgADCgMJAwABLgAECggJIQAiAKEeAA==.Nattyrav:BAACLgAFFH8LAAIjAAQJnR2CBABJAQAjAAQJnR2CBABJAQAuAAQKfygAAyMACQkbH8ADAO4CACMACQlnHsADAO4CABEABgnHG78tAF4BAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn86AAMeAAkJ9RV7FQDkAQAeAAkJ9RV7FQDkAQAXAAEJUAOJmQAcAAAAAA==.Neryssa:BAACLgAFFH8SAAMGAAcJVBtEGgCVAQAGAAYJhBxEGgCVAQAWAAEJYRWPFABcAAAuAAQKfzoAAwYACQnYJNkFAB8DAAYACAlvJNkFAB8DABYABAkpJPUYAIMBAAAA.',
Ni='Nickjamez:BAAALgADCgYJBgAAAA==.Nipz:BAAALgAECgEJAQABLgAECgUJBQAHAAAAAA==.',
No='Nocter:BAABLgAECn8eAAQGAAkJwhxnNwAuAgAGAAcJZhxnNwAuAgAPAAUJUiCTCwCBAQAWAAMJ9g0APgC8AAAAAA==.Noqtir:BAAALgAECgUJBQAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Nu='Nunca:BAAALgAECgEJAQAAAA==.',
Ny='Nymura:BAABLgAECn8bAAICAAYJwwbTzADSAAACAAYJwwbTzADSAAAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIYAAgJdBhQFgD4AQAYAAgJdBhQFgD4AQAAAA==.',
Oa='Oakhugger:BAABLgAECn8gAAMTAAkJGg9aDAC9AQATAAkJGg9aDAC9AQAUAAEJAAAskgAAAAAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8jAAILAAcJTB5nQQDuAQALAAcJTB5nQQDuAQABLgAECggJIQAiAKEeAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.Olyvivia:BAAALgAECgMJAwAAAA==.',
Om='Omgega:BAABLgAECn8xAAICAAgJ1xm0SADNAQACAAgJ1xm0SADNAQAAAA==.',
On='Onichan:BAAALgAECgUJBQABLgAFFAcJFQARAI8ZAA==.Onimeek:BAABLgAECn89AAMKAAkJ0x35CADTAgAKAAkJ0x35CADTAgALAAIJPAkM5gA7AAAAAA==.',
Or='Oryn:BAAALgAFFAEJAwABLgAFFAIJBQABACcVAA==.Oryx:BAAALgAECgEJAwAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgcJEAAAAA==.Paper:BAAALgAFFAcJFgAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAACLgAFFH8NAAIXAAYJwxieCwDWAQAXAAYJwxieCwDWAQAuAAQKfyEAAxcACAn8HgILALYCABcACAn8HgILALYCAB4ABAnaETo+ANoAAAAA.Pelagius:BAAALgADCgUJBQAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgYJAQAAAA==.Phyllus:BAAALgAECgUJBQAAAA==.',
Pi='Pictureplane:BAAALgADCgEJAQAAAA==.Pipeleto:BAABLgAECn8cAAIIAAgJzhhNGAAIAgAIAAgJzhhNGAAIAgAAAA==.',
Po='Poochimus:BAABLgAECn8bAAIjAAkJxxHWCQDpAQAjAAkJxxHWCQDpAQAAAA==.Pookong:BAAALgAECgUJCQAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECggJEQAAAA==.Priestpwnz:BAAALgAECgYJDwAAAA==.Protomán:BAAALgAECgYJDAAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAHAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAMJCAANABYKAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAgAAAA==.',
Re='Redeemedlev:BAACLgAFFH8RAAIgAAQJ7xMIGwAxAQAgAAQJ7xMIGwAxAQAuAAQKfzwAAiAACQnkIREDAGADACAACQnkIREDAGADAAEuAAUUBgkNABcAwxgA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8YAAILAAYJOh5yRQCUAQALAAYJOh5yRQCUAQAAAA==.',
Rh='Rhesand:BAABLgAECn8ZAAMEAAgJPAQERwDlAAAEAAgJPAQERwDlAAAFAAEJjwENJgAEAAAAAA==.Rhëa:BAAALgAECgMJBAAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIeAAYJHR3zHwCGAQAeAAYJHR3zHwCGAQAAAA==.Rindra:BAAALgADCgEJAQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8SAAIVAAUJ/RjPGwChAQAVAAUJ/RjPGwChAQAuAAQKfzwAAhUACQk3Jm8DAFgDABUACQk3Jm8DAFgDAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAUJEgAVAP0YAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8LAAIIAAMJ1xj1JADpAAAIAAMJ1xj1JADpAAAuAAQKfyQAAggACAneH28TALICAAgACAneH28TALICAAAA.Rollster:BAAALgAECgQJBAAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDgAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJEg7AdQAPAQALAAcJEg7AdQAPAQAAAA==.Saero:BAABLgAECn8UAAIhAAcJbBnoIwDAAQAhAAcJbBnoIwDAAQAAAA==.Saluuknir:BAABLgAECn8uAAMEAAkJeQ3XIwCbAQAEAAkJOA3XIwCbAQAFAAYJaAeKIwAMAQAAAA==.Saphh:BAAALgAECgcJEgABLgAFFAQJBwAkAMoMAA==.Satrath:BAAALgAFFAIJAwAAAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgYJBwAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Shadowxd:BAAALgAECgYJCwAAAA==.Sharky:BAAALgAFFAEJAgABLgAFFAcJHwABAFEdAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8WAAIlAAUJuiDKAwCLAQAlAAUJuiDKAwCLAQABLgAECggJFQADAEAjAA==.',
Si='Siera:BAAALgAECgEJAQABLgAECggJDQAHAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgABLgAECgUJBQAHAAAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.Skyrius:BAABLgAFFH8FAAIVAAIJaAJUwAB0AAAVAAIJaAJUwAB0AAAAAA==.',
Sl='Slaty:BAAALgAECgIJAgAAAA==.Slingshotz:BAABLgAECn8ZAAIdAAkJ4RmrBgCWAgAdAAkJ4RmrBgCWAgAAAA==.Slootbag:BAAALgAECggJDgAAAA==.',
Sn='Sneakylev:BAAALgADCgYJCQABLgAFFAYJDQAXAMMYAA==.Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8MAAICAAMJHCHOOwASAQACAAMJHCHOOwASAQAuAAQKfyoAAgIACAkWIwQnAEYCAAIACAkWIwQnAEYCAAAA.Snuuzi:BAAALgAFFAEJAQABLgAFFAMJDAACABwhAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Solari:BAABLgAECn8YAAMKAAgJWBgVHwDGAQAKAAcJlhUVHwDGAQALAAcJvRVRSgCFAQAAAA==.Solix:BAAALgAECgEJAQAAAA==.Solvi:BAAALgAECgYJDgAAAA==.Sophispapa:BAABLgAECn89AAICAAcJ5SDRLwAfAgACAAcJ5SDRLwAfAgAAAA==.Souprage:BAAALgAECggJEAAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgABLgAECggJIQAiAKEeAA==.Spywar:BAAALgAECgYJBwABLgAECggJHwARACkXAA==.',
St='Starlighter:BAABLgAECn8oAAMcAAgJRgvjKgBTAQAcAAgJRgvjKgBTAQAYAAYJGQUHQADIAAAAAA==.Strentor:BAAALgAECgEJAQAAAA==.',
Su='Sunshinë:BAAALgAECgEJAgAAAA==.Supressor:BAAALgADCgQJCAABLgAECgIJAgAHAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8pAAIOAAgJFiJdAADQAgAOAAgJFiJdAADQAgAuAAQKfzAAAw4ACQlSJB8GACUDAA4ACQlSJB8GACUDAB4AAgk5HlpNAKQAAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAUJEwACANkjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8aAAIKAAcJOBL2HwA9AQAKAAcJOBL2HwA9AQAAAA==.',
Th='Thaleon:BAAALgAECgcJDQAAAA==.Tharella:BAAALgAECgYJCQAAAA==.Thauriel:BAAALgAECgIJAgAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Titania:BAABLgAECn8eAAIhAAkJTAa9QAB1AQAhAAkJTAa9QAB1AQAAAA==.',
Tr='Trollztoll:BAAALgAECgIJAgAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAACLgAFFH8IAAINAAMJFgqESQDTAAANAAMJFgqESQDTAAAuAAQKfxwAAg0ABwmiHNA2ANcBAA0ABwmiHNA2ANcBAAAA.',
Un='Unholylord:BAAALgAECggJDAABLgAFFAYJGwAcAF8lAA==.',
Ut='Uthok:BAAALgADCgcJBwAAAA==.',
Va='Vacalocà:BAABLgAECn8UAAITAAgJUQ2SEgBZAQATAAgJUQ2SEgBZAQAAAA==.Valerian:BAAALgAECgcJCgAAAA==.Van:BAAALgADCgcJFAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Venin:BAAALgAECgYJBwAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warrdaddy:BAAALgAECgEJAQABLgADCgcJBwAHAAAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgUJBQAAAA==.',
Wo='Worldtree:BAAALgAECgQJBwAAAA==.',
Wy='Wynne:BAAALgAECgEJAgAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgUJBQAHAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAABLgAFFAIJAgAHAAAAAA==.Xorun:BAAALgAECgEJAQABLgAFFAIJAgAHAAAAAA==.',
Xz='Xzarrion:BAAALgADCgIJAgAAAA==.',
Ya='Yadhi:BAABLgAECn8XAAQOAAYJihY5LAA5AQAOAAUJihY5LAA5AQAXAAYJoBBPPAAnAQAeAAUJ3AfCVACLAAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGwANAAogAA==.Yimomo:BAABLgAECn8cAAMYAAkJhRUbLgCMAQAYAAkJhRUbLgCMAQAcAAcJtwd6PwDnAAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECggJDQAHAAAAAA==.',
Za='Zalconn:BAACLgAFFH8LAAMbAAQJSSKdCQCUAQAbAAQJSSKdCQCUAQAiAAIJDReoCACgAAAuAAQKfykAAxsACQkNJToDAGwDABsACQnLJDoDAGwDACIAAQneJokWAHIAAAAA.Zarrona:BAABLgAECn8hAAMiAAgJoR5pBAATAgAiAAcJ+hxpBAATAgAbAAcJkRoVGQCpAQAAAA==.Zayah:BAAALgAECgcJEQAAAA==.',
Zi='Zinmaris:BAAALgAFFAIJAgAAAA==.Zivanka:BAAALgAECgYJBgABLgAECgcJDgAHAAAAAA==.',
Zn='Znasty:BAABLgAECn8iAAIbAAYJgyUTEAAKAgAbAAYJgyUTEAAKAgAAAA==.',
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
