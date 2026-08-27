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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Priest-Holy','Druid-Balance','Rogue-Assassination','DeathKnight-Blood','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Monk-Mistweaver','Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Evoker-Preservation','DeathKnight-Frost','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-08-25',data={Ac='Achooe:BAABLgAECn8vAAMBAAkJsQq5HAAvAQABAAkJsQq5HAAvAQACAAEJJgJI0QEXAAAAAA==.Acrylic:BAAALgAECgkJCQAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJDAAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgUJEQAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxtDCACaAgAGAAkJJxtDCACaAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBC6XADIAQAJAAkJQBC6XADIAQAAAA==.Agathorz:BAAALgAECgYJBwAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alanala:BAAALgADCgYJBgAAAA==.Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alcestis:BAAALgAECgEJAQAAAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBmqMADtAAADAAMJgBmqMADtAAAuAAQKfzcAAwMACQnlJJoDAC8DAAMACQnlJJoDAC8DAAsABgn0EBUwAAgBAAAA.Allei:BAAALgAECgYJCQABLgAFFAcJHQAMACQIAA==.Alyndrya:BAABLgAECn9BAAQEAAkJoxycAgA7AgAEAAkJLxycAgA7AgAFAAYJGhbFEQD8AAANAAEJkg3yNwAoAAAAAA==.Alyndrys:BAABLgAECn8jAAIOAAcJmhPoFgBeAQAOAAcJmhPoFgBeAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNRMxOgDeAQAFAAkJNRMxOgDeAQAAAA==.Amithralia:BAABLgAECn8zAAIMAAkJhCDBCQAeAwAMAAkJhCDBCQAeAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SImHQDFAQAPAAYJ0SImHQDFAQAAAA==.Angelstar:BAAALgADCgIJAgAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8bAAIQAAkJpRa7QgDTAQAQAAkJpRa7QgDTAQABLgAECgkJMAARAKUQAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAkJUgAMABoiAA==.Aokuma:BAACLgAFFH9SAAMMAAkJGiIZAQBtAwAMAAkJGiIZAQBtAwASAAMJkBdjHgCQAAAuAAQKfywAAwwACQlPJI8GACIDAAwACQlPJI8GACIDABIABAlSIRJIAAwBAAAA.',
Ap='Apep:BAAALgAECgEJAQAAAA==.Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn85AAITAAkJ2xidAABdAgATAAkJ2xidAABdAgAAAA==.Apriline:BAAALgADCgYJCAAAAA==.',
Aq='Aquaten:BAABLgAECn8jAAIGAAgJ9xVhFQD4AQAGAAgJ9xVhFQD4AQAAAA==.',
Ar='Aramac:BAAALgAECgQJBgAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRCZawDxAAAMAAgJJg6ZawDxAAASAAYJIBZyTwDPAAAAAA==.Arcafrost:BAAALgAECgkJCgAAAA==.Arceus:BAABLgAECn8aAAIUAAYJ4g7JCwC4AAAUAAYJ4g7JCwC4AAAAAA==.Archaon:BAABLgAECn9PAAMQAAkJPBpTAwBpAgAQAAkJPBpTAwBpAgAVAAEJAADdUgAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFwAWAAEWAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9IAAMWAAkJpib/AQBrAwAWAAkJpib/AQBrAwAXAAgJiiS/HwDkAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEwAAAA==.Asmódeus:BAABLgAECn8cAAQYAAgJoQ73DQBTAQAYAAYJWw73DQBTAQAQAAgJCgrIfgA7AQAVAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgAECgQJBQAAAA==.Atorbarak:BAAALgAECgYJDwABLgAFFAIJBQAIAJwGAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.Awfwiction:BAAALgADCgEJAQAAAA==.',
Ax='Axon:BAACLgAFFH8KAAIJAAIJKwq/VACGAAAJAAIJKwq/VACGAAAuAAQKfy8AAgkACQmhGYUtAGMCAAkACQmhGYUtAGMCAAAA.',
Ay='Ayame:BAAALgAECgEJBAABLgAFFAgJBwAEAFAcAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMZAAYJJxUINgA+AQAZAAYJJxUINgA+AQAaAAQJvBYcRgDvAAABLgAECgcJEwAbAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgABLgAECgkJEgAbAAAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8jAAIcAAgJHQW9KQDnAAAcAAgJHQW9KQDnAAAAAA==.Baelthas:BAAALgADCgcJDgAAAA==.Ballard:BAAALgADCgYJBgAAAA==.Bashon:BAABLgAECn8UAAIWAAkJ8A6hCAC6AQAWAAkJ8A6hCAC6AQAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Bearybonds:BAAALgAECgMJAwAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belgaron:BAAALgAECggJCgABLgAECggJIgAPAGkcAA==.Belitha:BAACLgAFFH8NAAIFAAMJFiCySQAMAQAFAAMJFiCySQAMAQAuAAQKfzEAAgUACQkaIQsTAOgCAAUACQkaIQsTAOgCAAAA.Belmaris:BAABLgAECn8zAAITAAkJNB2GAgCuAgATAAkJNB2GAgCuAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgYJCwAAAA==.Bety:BAAALgAECgkJCQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8kAAIdAAkJJw7UfQBoAQAdAAkJJw7UfQBoAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8cAAIMAAkJrBLwKQAFAgAMAAkJrBLwKQAFAgAAAA==.Bighunt:BAAALgAECgYJCwABLgAECgkJHAAMAKwSAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8fAAIEAAkJdw1FJQBPAQAEAAkJdw1FJQBPAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn9DAAINAAkJPCKNAwChAgANAAkJPCKNAwChAgAAAA==.Blegh:BAACLgAFFH8PAAMeAAUJaRicKQAiAQAeAAUJGhacKQAiAQAfAAEJlxUfDQBLAAAuAAQKfyMAAx8ACQnCHqcKADECAB8ABwnHHqcKADECAB4ABwl/GygfAMoBAAEuAAUUBwkQAAgANBkA.Blueflu:BAAALgAECgcJCwAAAA==.Bluegrass:BAACLgAFFH8KAAIOAAMJqyDTAwAfAQAOAAMJqyDTAwAfAQAuAAQKf3oAAg4ACQnLJTcAAF0DAA4ACQnLJTcAAF0DAAAA.',
Bo='Bondï:BAABLgAECn8fAAMgAAgJxAnuRABkAQAgAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAABLgAECn8VAAIhAAkJSRCtGADIAAAhAAkJSRCtGADIAAAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAFFAEJAQAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxgyPwADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAbAAAAAA==.',
Br='Brat:BAAALgAFFAIJAgABLgAFFAkJOAAaAE0bAA==.Brighteye:BAAALgAECggJEgAAAA==.Brisket:BAABLgAECn8gAAMLAAkJSQ95BABKAQALAAkJwwx5BABKAQAcAAgJOg1XBQA9AQAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleoseven:BAAALgAECgEJAQABLgAECgkJQgAdAM8bAA==.Buckme:BAACLgAFFH8fAAIIAAUJcBA4JQASAQAIAAUJcBA4JQASAQAuAAQKfyAAAggACAmgF9s1AAYCAAgACAmgF9s1AAYCAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bulldogs:BAAALgAECgEJAQAAAA==.Bulletprooff:BAAALgAECgEJAQAAAA==.Bulova:BAAALgADCgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAACLgAFFH8IAAIJAAYJUxdkUAA9AQAJAAYJUxdkUAA9AQAuAAQKfxoAAgkACQmeJMUBAD8DAAkACQmeJMUBAD8DAAEuAAUUCQkUABAA7BoA.Bustedhoof:BAAALgADCgMJAwAAAA==.',
['Bà']='Bàal:BAAALgAECgEJAQABLgAECgEJAQAbAAAAAA==.',
Ca='Caiphage:BAABLgAECn82AAIFAAkJqBuxAgBqAgAFAAkJqBuxAgBqAgAAAA==.Caladelm:BAABLgAECn85AAICAAkJah9aAwDSAgACAAkJah9aAwDSAgAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8xAAIdAAkJGRNMCQCzAQAdAAkJGRNMCQCzAQAAAA==.Carlarae:BAABLgAECn8YAAIJAAcJtgSr/QCwAAAJAAcJtgSr/QCwAAAAAA==.Carya:BAAALgAECgEJAQABLgAECgkJMAARAKUQAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih0CTgBDAQAJAAQJih0CTgBDAQAuAAQKfxwAAgkACQksIdUTAOMCAAkACQksIdUTAOMCAAAA.Cegeo:BAABLgAECn9IAAIVAAkJihnAAwBTAgAVAAkJihnAAwBTAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn94AAMDAAkJnSM/AQDlAgADAAkJnSM/AQDlAgALAAEJ0g5seAAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhN9lQCXAAAQAAIJjhN9lQCXAAAuAAQKfyMAAxAABwncH8oyAA0CABAABwncH8oyAA0CABgABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAwAAAA==.',
Ci='Ciennajewel:BAABLgAECn8aAAIRAAgJVRtNEwBBAgARAAgJVRtNEwBBAgAAAA==.Cirdle:BAABLgAECn9PAAMIAAkJShMfCQDwAQAIAAkJShMfCQDwAQAHAAMJIwZ1KwBnAAAAAA==.Cirona:BAABLgAECn8wAAMMAAkJJR4BAgCjAgAMAAkJJR4BAgCjAgAOAAEJvg41GAArAAABLgAECgkJMQAWAAcfAA==.',
Cl='Clausewitz:BAABLgAECn8aAAIcAAkJ7gq9HgA9AQAcAAkJ7gq9HgA9AQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8PAAMQAAUJVhocIwAKAQAQAAUJVhocIwAKAQAYAAEJngZUKgBCAAAuAAQKfyAAAhAACQk+HAkjAFQCABAACQk+HAkjAFQCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAbAAAAAA==.Coletta:BAAALgAECgEJAQAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazy:BAAALgADCgEJAQAAAA==.Crazynlazy:BAABLgAECn8hAAIXAAgJ7gILXQDNAAAXAAgJ7gILXQDNAAAAAA==.Creamtastic:BAABLgAECn8UAAIhAAkJYhflCgB5AQAhAAkJYhflCgB5AQABLgABCgQJBAAbAAAAAA==.Creamyweamy:BAABLgAECn8gAAIRAAgJWRR4HwDIAQARAAgJWRR4HwDIAQABLgABCgQJBAAbAAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA0DqgArAQAJAAcJQA0DqgArAQAiAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAABLgAECn8fAAMBAAcJrRkFBACAAQABAAYJHBsFBACAAQAgAAMJdB1JCwAFAQAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8gAAMXAAkJWBWfHQD0AQAXAAkJWBWfHQD0AQAjAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn88AAIJAAkJOBF6DQCLAQAJAAkJOBF6DQCLAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8/AAIhAAkJAySvAACKAwAhAAkJAySvAACKAwABLgAFFAkJSQAaAGwlAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAIJAgABLgAFFAkJOAAaAE0bAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8kAAIhAAcJ6yTVBQC3AgAhAAcJ6yTVBQC3AgAuAAQKf5cAAiEACQmzJgwAAAkEACEACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAbAAAAAA==.Daggonet:BAACLgAFFH8FAAIdAAMJFxFQSADLAAAdAAMJFxFQSADLAAAuAAQKfx4AAh0ACQknIBIOAPsCAB0ACQknIBIOAPsCAAAA.Dahlina:BAAALgAECgUJBQABLgAFFAMJDQAFABYgAA==.Dalrin:BAABLgAECn8XAAMjAAYJ7A+uFQBiAQAjAAYJ7A+uFQBiAQAXAAQJzAfqZwCjAAAAAA==.Darkcarnival:BAABLgAECn8xAAIQAAkJ1BodIABkAgAQAAkJ1BodIABkAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAUJDgAWABcYAA==.Darkknightx:BAACLgAFFH8MAAIDAAQJ1w2DJgAbAQADAAQJ1w2DJgAbAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAABLgAECn8fAAIdAAgJqhK8CgCTAQAdAAgJqhK8CgCTAQABLgAFFAIJBQAXABEDAA==.Darthraider:BAABLgAECn8dAAIdAAcJGxH3hgBWAQAdAAcJGxH3hgBWAQAAAA==.Dasnotgood:BAABLgAECn8eAAMOAAcJ4B6xAwBiAQAOAAYJsSCxAwBiAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQXAAgJxweBSwAHAQAXAAgJxweBSwAHAQAWAAEJowGnqgAhAAAjAAEJeAGKSAAdAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgcJCwAAAA==.',
De='Deathspeaker:BAAALgAECgIJAgABLgAECgkJOQAlACsVAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8bAAIFAAkJKRW0NwDnAQAFAAkJKRW0NwDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demeek:BAAALgAECgEJAQAAAA==.Demiish:BAABLgAECn8gAAIVAAcJmRULBABAAQAVAAcJmRULBABAAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8tAAMRAAkJdxN4KACDAQARAAkJdxN4KACDAQAZAAcJ3hDRMgBPAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8nAAISAAkJVxUQHQDgAQASAAkJVxUQHQDgAQAAAA==.Desdemona:BAABLgAECn83AAIBAAkJFiGuAQA9AgABAAkJFiGuAQA9AgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8KAAIIAAQJAA7JRwAeAQAIAAQJAA7JRwAeAQAuAAQKfxwAAwgACQl6GukcAHcCAAgACQl6GukcAHcCAAcAAglsA8FGABoAAAAA.',
Di='Dianimal:BAABLgAECn8pAAISAAkJ7ApQPwARAQASAAkJ7ApQPwARAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJFgAgAEUeAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAACLgAFFH8HAAMCAAMJFQvDmQCFAAACAAIJTQ/DmQCFAAAgAAIJDBe2HgBjAAAuAAQKfzIAAyAACQkLJZMEAE8DACAACQkLJZMEAE8DAAIACAnvIisbAKECAAAA.',
Dk='Dklel:BAACLgAFFH8QAAIdAAUJ0CG7UQBOAQAdAAUJ0CG7UQBOAQAuAAQKf0AAAh0ACQl4Jj8HADwDAB0ACQl4Jj8HADwDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8OAAICAAQJnBTYIAAIAQACAAQJnBTYIAAIAQAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AbZKAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBKjcgCIAQACAAkJIBKjcgCIAQAAAA==.Dorow:BAAALgAECgEJAQAAAA==.',
Dr='Draaka:BAAALgAECgQJBgAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGwAFACkVAA==.Dragon:BAAALgAECgkJEQAAAA==.Dragonpunch:BAABLgAECn8qAAIhAAkJ6xkgHwAhAgAhAAkJ6xkgHwAhAgAAAA==.Driftyshaman:BAABLgAECn8qAAIXAAgJ7wqfTQD/AAAXAAgJ7wqfTQD/AAAAAA==.Driftysnow:BAAALgADCgQJBAABLgAECggJKgAXAO8KAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn80AAIdAAkJhwz5EgAgAQAdAAkJhwz5EgAgAQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAABLgAECn8nAAMIAAkJUB97AwC3AgAIAAkJUB97AwC3AgAHAAUJaxKLBADnAAABLgAECggJIgAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8uAAIjAAkJtA35EACkAQAjAAkJtA35EACkAQAAAA==.',
Dy='Dyamï:BAABLgAECn8zAAIhAAkJiiCTCAASAwAhAAkJiiCTCAASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
['Dá']='Dánte:BAAALgAECgMJBgAAAA==.',
Eg='Eglosira:BAABLgAECn8dAAIJAAkJmAjgggByAQAJAAkJmAjgggByAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgAECgEJAQAAAA==.Electric:BAABLgAECn8hAAIXAAgJXArFRgAZAQAXAAgJXArFRgAZAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAACLgAFFH8LAAIJAAMJDgp/QQDCAAAJAAMJDgp/QQDCAAAuAAQKfx4AAgkABwlLERyfADwBAAkABwlLERyfADwBAAAA.Ellä:BAAALgAECgYJDAAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxOBPwAuAQAIAAQJGxOBPwAuAQAuAAQKfzoAAggACQmPItcJAAkDAAgACQmPItcJAAkDAAAA.Elviric:BAAALgAECgkJCgAAAA==.',
Er='Eraleth:BAAALgAECgYJBgABLgAFFAMJDQAFABYgAA==.Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQABLgAECgkJEgAbAAAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Eu='Eukina:BAAALgAECgYJDAAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Ex='Exq:BAAALgAECgEJAQAAAA==.',
Fa='Faben:BAAALgAECgcJCgAAAA==.Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhH9QwCBAQAMAAcJvhH9QwCBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.Felfireflux:BAAALgAECgMJAwAAAA==.Fellirane:BAAALgAECgUJCAAAAA==.Felrein:BAAALgADCgUJBQABLgAECgkJKQAcAPELAA==.',
Fi='Finegas:BAAALgAECgYJBgABLgAECgkJEgAbAAAAAA==.Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8iAAIjAAgJUBuhAABxAgAjAAgJUBuhAABxAgAuAAQKfygAAiMACQnsJbUDAO8CACMACQnsJbUDAO8CAAAA.Floofndoom:BAAALgAFFAEJAQABLgAFFAgJIgAjAFAbAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAgJIgAjAFAbAA==.',
Fr='Fredrickk:BAABLgAECn8XAAMWAAcJARbcPwCuAQAWAAcJARbcPwCuAQAXAAQJWwqNegB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAABLgAFFAgJIgAjAFAbAA==.Furrylight:BAAALgAFFAIJAwABLgAFFAUJFAAWAGUYAA==.Furryphase:BAACLgAFFH8UAAIWAAUJZRirJQBUAQAWAAUJZRirJQBUAQAuAAQKfyQAAxYACQnxHAwNALUCABYACQnxHAwNALUCABcABAlyCTR+AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAgJIgAjAFAbAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.Gex:BAAALgAECgEJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn86AAIWAAkJth6tEwCvAgAWAAkJth6tEwCvAgAAAA==.',
Go='Goatjira:BAAALgAECgUJDQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Greygorypack:BAEALgADCgYJBQABLgAECgYJBgAbAAAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAmAGAgAA==.Gripisrdy:BAABLgAECn8xAAMdAAkJfSA0FQDIAgAdAAkJfSA0FQDIAgAUAAMJgRjqNQC/AAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8nAAMnAAkJ8CJGAQD0AgAnAAkJ8CJGAQD0AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAACLgAFFH8FAAMXAAIJEQMCLwBWAAAXAAIJEQMCLwBWAAAWAAIJZAj1RgBJAAAuAAQKfxkAAhYACAnUDnJIAIwBABYACAnUDnJIAIwBAAAA.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAgAAAA==.Haggrd:BAABLgAECn8iAAICAAkJnR8IJwBoAgACAAkJnR8IJwBoAgAAAA==.Hairyjolene:BAABLgAECn8jAAIIAAgJERNpSQDFAQAIAAgJERNpSQDFAQAAAA==.Halleberries:BAEALgAECgYJBgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJCAADADAWAA==.Handsome:BAABLgAFFH8FAAIIAAMJHhetSgCSAAAIAAMJHhetSgCSAAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Headpats:BAAALgAFFAEJAgABLgAFFAkJSQAaAGwlAA==.Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgkJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAACLgAFFH8MAAMdAAQJtRPwaAAnAQAdAAQJxRLwaAAnAQAmAAIJ4BIpEwCOAAAuAAQKfxUABCYACAlbFBUKAKkAABQABgmHEA4mAA8BACYAAgkVHBUKAKkAAB0ABAmZDGgpAXcAAAAA.',
Hi='Highlander:BAAALgAECgEJAgAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxP2mgBAAAAFAAEJvxP2mgBAAAABLgAFFAkJUgAMABoiAA==.Hikarimonk:BAABLgAFFH8oAAIhAAkJHh/8AgDbAgAhAAkJHh/8AgDbAgABLgAFFAkJUgAMABoiAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAkJUgAMABoiAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Hoather:BAAALgAECgQJBAABLgAFFAMJBwACABULAA==.Holyarceus:BAAALgADCgQJBAABLgAECgYJGgAUAOIOAA==.Holyblimblam:BAABLgAECn8WAAIgAAYJRR66JQDaAQAgAAYJRR66JQDaAQAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8uAAMdAAgJUx4mDAB4AQAdAAgJ5h0mDAB4AQAUAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIZAAYJNA0RRwDzAAAZAAYJNA0RRwDzAAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Humper:BAAALgAECgMJBwAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.Huntley:BAAALgAECgkJEwABLgAECgkJIAALAEkPAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèri:BAAALgADCgkJCQAAAA==.Hèrifire:BAAALgADCgYJBgAAAA==.Hèrifury:BAABLgAECn80AAMcAAkJlx03AQCjAgAcAAkJlx03AQCjAgADAAMJagyNGACFAAAAAA==.',
Ic='Icyjackets:BAABLgAECn8jAAMdAAgJtA9VdgB3AQAdAAgJtA9VdgB3AQAUAAQJpAUkRwBxAAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAFFAEJAwAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Is='Iscorn:BAAALgAECgcJDAAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA88UwCpAQAIAAkJlA88UwCpAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRcmJgDHAQADAAgJBRcmJgDHAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn9LAAMMAAkJLRSgBgCCAQAMAAkJLRSgBgCCAQASAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAbAAAAAA==.Jel:BAAALgADCgEJAQAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAbAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIXAAYJfg7LWgDUAAAXAAYJfg7LWgDUAAAAAA==.Jessicà:BAAALgAECgQJBQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAwAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8mAAMWAAYJIhYRNgCrAQAWAAYJIhYRNgCrAQAXAAUJfBL/XADNAAAAAA==.Jiwà:BAABLgAFFH8IAAIWAAUJjgcxOAACAQAWAAUJjgcxOAACAQABLgAFFAYJEwAZAJ4KAA==.Jiwâ:BAACLgAFFH8TAAIZAAYJngo/HwD5AAAZAAYJngo/HwD5AAAuAAQKfzkAAhkACQlGHhcNAIICABkACQlGHhcNAIICAAAA.Jiwå:BAAALgAECgYJCwAAAA==.',
Jo='Joecool:BAAALgAECgQJBAAAAA==.Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJDQAFABYgAA==.Kahless:BAAALgAECgEJAQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAcaRwApAQADAAkJMAcaRwApAQAAAA==.Kaliyah:BAAALgADCgcJCQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAABLgAECn8VAAISAAkJvAd6DAD1AAASAAkJvAd6DAD1AAAAAA==.Kavorkyan:BAAALgAECgkJEwAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMmAAkJYCCbEgBPAQAdAAYJ7hpDXQDbAQAmAAcJyB+bEgBPAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9NAAMKAAkJKR45CACwAgAKAAkJKR45CACwAgAPAAEJ6gt8JQAkAAAAAA==.',
Ki='Kiamara:BAABLgAECn8uAAIQAAkJIQuSDwAMAQAQAAkJIQuSDwAMAQAAAA==.Kinderlin:BAABLgAECn8sAAICAAkJER36AwClAgACAAkJER36AwClAgAAAA==.Kipo:BAABLgAECn8VAAIGAAkJlQ+oAwBvAQAGAAkJlQ+oAwBvAQAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.Kotys:BAAALgAECgUJCAAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhbbNwC4AQAMAAcJbhbbNwC4AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.Krzytotems:BAAALgAECgMJAwAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECggJEQAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQfAAgJfRaSDwDiAQAfAAYJNhmSDwDiAQAeAAMJfRSEQgDYAAAlAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.Lethalarrow:BAAALgAECgYJBgAAAA==.Lethalpally:BAAALgAECgEJAQAAAA==.Lethalpixi:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgcJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgcJCwAAAA==.Lista:BAABLgAECn8XAAMaAAkJqiD6AwBaAwAaAAkJqiD6AwBaAwAZAAEJEgrijgAsAAABLgAECgkJSQAPAM8lAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyVwAQBPAwAGAAkJDiVwAQBPAwAIAAgJlybzDADrAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Locklobstah:BAAALgADCgIJAgAAAA==.Lola:BAAALgAECgkJAgAAAA==.Loralynn:BAACLgAFFH8dAAMMAAcJJAgqDwAzAQAMAAcJJAgqDwAzAQASAAEJggIlNQAlAAAuAAQKfxQAAgwABwn7FD04ALYBAAwABwn7FD04ALYBAAAA.Lorianne:BAACLgAFFH8HAAIWAAIJwRVzaQBtAAAWAAIJwRVzaQBtAAAuAAQKfygAAxYACAmvGGQpAOkBABYACAmvGGQpAOkBABcABQmxC7tWAOoAAAEuAAUUBwkdAAwAJAgA.Lorri:BAAALgADCgQJBQABLgAFFAcJHQAMACQIAA==.',
Lu='Lucianas:BAABLgAECn8UAAICAAgJUw5SjgBVAQACAAgJUw5SjgBVAQAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgkJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8jAAIIAAgJIh69GgCFAgAIAAgJIh69GgCFAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgIJBAAAAA==.Madaea:BAABLgAECn8zAAIhAAkJqh8MCwDoAgAhAAkJqh8MCwDoAgAAAA==.Madameuyen:BAAALgADCgkJEQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRzlHgCkAgAJAAkJHRzlHgCkAgABLgAFFAQJGwAGAJgbAA==.Mahai:BAAALgADCgcJBAABLgAECgkJEgAbAAAAAA==.Mak:BAABLgAECn8WAAIRAAcJSBwDFAA3AgARAAcJSBwDFAA3AgABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx39KwAtAgAIAAgJUx39KwAtAgAAAA==.Makthamonk:BAAALgAECgYJCQABLgAECggJGAAIAFMdAA==.Malholis:BAABLgAECn8pAAIaAAkJ/A5xBQDGAQAaAAkJ/A5xBQDGAQAAAA==.Malzeth:BAAALgAECgcJDAAAAA==.Marrilyn:BAAALgAFFAEJAwABLgAFFAgJIwAQAN8eAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn83AAIIAAkJzyCgCwD3AgAIAAkJzyCgCwD3AgAAAA==.Mate:BAAALgAECgUJDAABLgAECgkJIAALAEkPAA==.Mavuika:BAAALgAECgIJAwAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Meatloaf:BAAALgAECgQJBAAAAA==.Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAFFAIJAgAAAA==.Megabyte:BAAALgADCgUJBQAAAA==.Melbeast:BAABLgAECn8oAAIIAAkJlx3pBwAOAgAIAAkJlx3pBwAOAgAAAA==.Melorea:BAAALgAECggJDAAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxATXADKAQAJAAkJNhATXADKAQAiAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMVAAgJpQkqFQACAQAVAAgJpQkqFQACAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgAECgMJAwAAAA==.Mignon:BAAALgAECgYJDAABLgAECgkJIAALAEkPAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJEgAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn9JAAIBAAkJ5wT5CgCyAAABAAkJ5wT5CgCyAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECggJEAAAAA==.Moistwhispa:BAAALgAECgQJCAABLgAECgkJIAASAO4WAA==.Molfise:BAABLgAECn89AAMPAAkJfCLhAQBKAgAKAAkJdiJWAQBbAgAPAAkJtxrhAQBKAgAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn9AAAIRAAkJ4B+FBgAKAwARAAkJ4B+FBgAKAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8xAAMcAAkJGQemBwDoAAAcAAgJ8gSmBwDoAAALAAgJJAfJOQDeAAAAAA==.Mopp:BAAALgAECgYJCwAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgUJCAAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEQAbAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAgAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mysticx:BAAALgAECgYJDAABLgAECgcJHwAXAAMTAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAhAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgYjtAAbAQAJAAgJBgYjtAAbAQABLgAECgkJEgAbAAAAAA==.',
Na='Nachtelf:BAACLgAFFH8GAAIIAAMJwhIwNADWAAAIAAMJwhIwNADWAAAuAAQKf3kAAggACQlJIpMHACEDAAgACQlJIpMHACEDAAAA.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAWAFYTAA==.Nannysham:BAABLgAECn8WAAIWAAkJVhMlLQADAgAWAAkJVhMlLQADAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAACLgAFFH8GAAIJAAMJSxWbNwDnAAAJAAMJSxWbNwDnAAAuAAQKf2gAAgkACQnSJPwFAFMDAAkACQnSJPwFAFMDAAAA.Nathel:BAAALgAECgcJBwAAAA==.Natherel:BAABLgAECn8YAAQLAAgJ2QSEQQDBAAALAAcJVgWEQQDBAAADAAUJ5gPofQB+AAAcAAEJ5QEkWwAgAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8qAAMeAAgJQRSmBwAcAgAeAAgJQRSmBwAcAgAlAAYJUxYfEwBhAQAuAAQKf08AAx4ACQmNJUgAAGsDAB4ACQmNJUgAAGsDACUACAl2G3wNAPgBAAEuAAUUCQk4ABoATRsA.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRNSLQDxAQAMAAkJaRNSLQDxAQABLgAECggJIgAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgUJEwAAAA==.',
No='Nonphatmilk:BAABLgAECn8WAAIhAAkJIB1KBAAeAgAhAAkJIB1KBAAeAgAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAACLgAFFH8FAAIdAAMJLARDYQCXAAAdAAMJLARDYQCXAAAuAAQKfy0AAx0ACQmbEipRANABAB0ACQmbEipRANABABQAAQkbEnpFADIAAAAA.Novatron:BAAALgAECgYJBgAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR/xTAD1AQAJAAgJCR/xTAD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8dAAIMAAgJcgYaawDzAAAMAAgJcgYaawDzAAAAAA==.',
Om='Omee:BAABLgAECn8oAAMEAAkJ1RvlDwAqAgAEAAkJ1RvlDwAqAgAFAAYJ+Qs9jAAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w6PlwBKAQAJAAcJ4w6PlwBKAQAAAA==.',
Op='Ophela:BAAALgAECgMJBQAAAA==.',
Or='Or:BAAALgAECgIJAgAAAA==.Orakio:BAABLgAFFH8UAAIdAAQJIRaiXACiAAAdAAQJIRaiXACiAAABLgAFFAYJIgAJAAMaAA==.Oralena:BAABLgAECn8jAAIIAAgJXggRdQBVAQAIAAgJXggRdQBVAQAAAA==.Orioncheats:BAABLgAECn9CAAIdAAkJzxuAKwBSAgAdAAkJzxuAKwBSAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAbAAAAAA==.',
Ox='Oxygën:BAABLgAECn8wAAIJAAkJXxC0DQCIAQAJAAkJXxC0DQCIAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8RAAIgAAQJgBt5HQAyAQAgAAQJgBt5HQAyAQAuAAQKfxwAAiAACAnfIvUHAAwDACAACAnfIvUHAAwDAAEuAAUUBQkOABYAFxgA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAbAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9MAAMPAAkJaR+jCAC8AgAPAAkJaR+jCAC8AgAhAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8VAAIDAAgJuRjxIgDbAQADAAgJuRjxIgDbAQAAAA==.Persephonee:BAAALgADCgEJAQAAAA==.',
Ph='Pharune:BAABLgAECn8xAAIkAAkJvRIDFgCjAQAkAAkJvRIDFgCjAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8yAAIJAAkJShhXOQAzAgAJAAkJShhXOQAzAgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJFAAXADEgAA==.Picklebob:BAAALgAECggJCAABLgAFFAQJFAAXADEgAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJFAAXADEgAA==.Picklebosh:BAABLgAFFH8UAAIXAAQJMSBYDgBUAQAXAAQJMSBYDgBUAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Plantain:BAAALgADCgIJAgAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Pointnshoot:BAAALgAECgEJAQABLgAFFAIJAgAbAAAAAA==.Ponky:BAABLgAECn8cAAIZAAkJKhHxKgB7AQAZAAkJKhHxKgB7AQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pothands:BAAALgADCgEJAQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8NAAIMAAMJghQzQgCpAAAMAAMJghQzQgCpAAABLgAFFAkJSQAaAGwlAA==.',
Pr='Preacha:BAAALgAECgYJCgABLgAFFAIJBQAXABEDAA==.Precious:BAACLgAFFH84AAIaAAkJTRs5AgADAwAaAAkJTRs5AgADAwAuAAQKf1YABBoACQltJiUAAPQDABoACQltJiUAAPQDABEABglwDxs2AGQBABkABAkvE7pXALUAAAAA.',
Pu='Puppet:BAAALgAECgkJCQABLgAFFAkJOAAaAE0bAA==.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAcAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIfAAkJXgunEAABAQAfAAkJXgunEAABAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAACLgAFFH8IAAIDAAMJ3xL8IQClAAADAAMJ3xL8IQClAAAuAAQKfzoAAwMACAkVHiETAFkCAAMACAn4HSETAFkCAAsAAQmKFVZzADsAAAAA.Raezil:BAAALgAECgEJAQAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8iAAMPAAgJaRx0EgAtAgAPAAgJaRx0EgAtAgAhAAIJpw2loABYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJCgABLgAECgkJMwAMAIQgAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8wAAIRAAkJpRBUJgCTAQARAAkJpRBUJgCTAQAAAA==.Raziel:BAAALgAECgQJBAAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Redranger:BAAALgADCgQJBAABLgAECgIJBQAbAAAAAA==.Rehum:BAABLgAECn8UAAICAAYJPghx9QDEAAACAAYJPghx9QDEAAAAAA==.Remagtrepxe:BAAALgAECgEJAQABLgAECggJKgAXAO8KAA==.Remniscence:BAAALgAECgEJAQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Renard:BAAALgAECgkJCgAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8uAAMjAAkJRxEDFQBtAQAjAAgJFBMDFQBtAQAWAAYJ3gfSjgC7AAAAAA==.Revèndreth:BAAALgAECgQJBQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgQJBwAAAA==.',
Rh='Rhylee:BAAALgAECgYJCQAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9LAAIZAAkJChVaGAAEAgAZAAkJChVaGAAEAgAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Rm='Rmplstiltskn:BAAALgADCgkJCQAAAA==.',
Ro='Robberttrest:BAABLgAECn8dAAIIAAYJ0hE+GgAQAQAIAAYJ0hE+GgAQAQAAAA==.Rockydemon:BAAALgAECgEJAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMdAAkJERs8QQD/AQAdAAkJ5xo8QQD/AQAmAAYJrhWxCABaAQAAAA==.Rockymage:BAAALgAECgQJBgAAAA==.Rockymonk:BAAALgAECgEJAQAAAA==.Rockypally:BAAALgAECgEJAQAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn9MAAIfAAkJgRyGAACLAgAfAAkJgRyGAACLAgAAAA==.Roryn:BAACLgAFFH8LAAICAAMJWR8bOgCxAAACAAMJWR8bOgCxAAAuAAQKf2wAAgIACQlWJmkBAIIDAAIACQlWJmkBAIIDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8IAAIDAAMJfBmdLwDyAAADAAMJfBmdLwDyAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAkJNwAMALQfAA==.Rugiia:BAACLgAFFH83AAIMAAkJtB88AgAnAwAMAAkJtB88AgAnAwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJbsbAC4BAAAA.Rugiian:BAABLgAFFH8NAAIhAAUJ7xycHACOAQAhAAUJ7xycHACOAQABLgAFFAkJNwAMALQfAA==.Rulakir:BAAALgADCgQJBAABLgAFFAYJIgAJAAMaAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQkZZQB0AQAQAAkJjQkZZQB0AQAAAA==.Ryuka:BAABLgAECn8uAAIkAAkJEwugKAAUAQAkAAkJEwugKAAUAQAAAA==.',
['Râ']='Râezil:BAAALgAECgEJAQABLgAECgEJAQAbAAAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAbAAAAAA==.Samyria:BAABLgAECn8eAAIIAAkJSxExDgCPAQAIAAkJSxExDgCPAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgAECgMJAwAAAA==.Sapphiriana:BAAALgADCggJCAABLgAECgkJTAAfAIEcAA==.Satyaru:BAABLgAECn8qAAQhAAkJFwwxQABtAQAhAAkJFwwxQABtAQAPAAcJlg4bPAAQAQAKAAEJogooFwAhAAAAAA==.Saucy:BAABLgAECn8XAAMXAAgJeyB+DQCQAgAXAAgJeyB+DQCQAgAjAAEJAADDSgAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAbAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8+AAIRAAkJlxfVAwDxAQARAAkJlxfVAwDxAQAAAA==.Selati:BAAALgADCgMJAwAAAA==.Seric:BAABLgAECn8pAAMcAAkJ8QtFHQBLAQAcAAkJ8QtFHQBLAQADAAQJugTShwBjAAAAAA==.Sesethi:BAAALgAECgQJBgABLgAECggJHgAQAAQfAA==.',
Sh='Shadowdancèr:BAABLgAECn8lAAMZAAkJGxoEHgDVAQAZAAgJaxkEHgDVAQAaAAQJMhPzUgC2AAAAAA==.Shadowlocke:BAAALgAECgYJCwAAAA==.Shadowyisis:BAABLgAECn8VAAIZAAkJyBQWFwAQAgAZAAkJyBQWFwAQAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8bAAIGAAQJmBucBgA1AQAGAAQJmBucBgA1AQAuAAQKf0QAAwYACQnQI3ECACIDAAYACQm3I3ECACIDAAcABwnWHTkbAE8CAAAA.Shenandoah:BAAALgAECgQJBAAAAA==.Shiftyelf:BAAALgADCgYJBgAAAA==.Shirizani:BAAALgAECgQJBAABLgAFFAYJGAABAIwNAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Silentwrath:BAAALgAECgEJAQABLgAECgkJGwANAJMIAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAEALgAECgMJBAABLgAFFAkJLQAcAL8dAA==.Skybox:BAAALgAECgUJCAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMaAAYJvhFAMAAeAQAaAAUJiBBAMAAeAQARAAUJfQ/9UwCNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8MAAIJAAMJKgRSUQCRAAAJAAMJKgRSUQCRAAAuAAQKfzUAAgkACQmEE+FGAAYCAAkACQmEE+FGAAYCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.Snuggy:BAAALgAECgcJDwAAAA==.',
So='Soapytatas:BAAALgAFFAEJAgAAAA==.Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQgAAkJRgzjLwCbAQAgAAkJRgzjLwCbAQABAAYJQBOeKgDFAAACAAEJYBbEhQE5AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAbAAAAAA==.Splashdaddy:BAACLgAFFH8cAAIWAAUJvyEYDACPAQAWAAUJvyEYDACPAQAuAAQKfykAAhYACQmkJJkHADYDABYACQmkJJkHADYDAAEuAAUUAQkBABsAAAAA.Spoiled:BAABLgAFFH8GAAIhAAYJdQbsGQD7AAAhAAYJdQbsGQD7AAABLgAFFAkJOAAaAE0bAA==.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgcJDAAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn9AAAMWAAkJOQ5LCwCBAQAWAAkJOQ5LCwCBAQAXAAIJcQh2JgBEAAAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDQAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Summonme:BAABLgAECn8mAAQQAAkJNiawAABVAwAQAAkJfySwAABVAwAYAAUJ1CD0AQDBAQAVAAMJpiXNBgDdAAAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sw='Sweetshot:BAAALgADCgIJAgAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgUJDgAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn9fAAIkAAkJqyRnAABDAwAkAAkJqyRnAABDAwAAAA==.',
Ta='Taea:BAABLgAECn8xAAMWAAkJBx/jAQD/AgAWAAkJBx/jAQD/AgAXAAYJfRtlBgCKAQAAAA==.Taeus:BAACLgAFFH8iAAMJAAYJAxoqHACPAQAJAAYJAxoqHACPAQAiAAEJjhz6BQBVAAAuAAQKfx0AAwkACQkiGeBeAB4CAAkACQkiGeBeAB4CACkABAloExwDALQAAAAA.Taintedcure:BAAALgADCgkJEgAAAA==.Taintedkoma:BAAALgAECggJCwABLgAECggJIAAVAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Taliesien:BAAALgADCgYJBgABLgAECgkJbgAlAIoNAA==.Tamer:BAAALgAECgYJBgABLgAFFAcJJAAhAOskAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAABLgAECn8eAAIFAAcJGAiCGQC8AAAFAAcJGAiCGQC8AAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIcAAkJoiEKCAClAgAcAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AHm0wCjAAAIAAgJ/AHm0wCjAAAAAA==.',
Te='Tearinass:BAAALgAECgkJCQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgUJCgAAAA==.Temajin:BAABLgAECn8YAAMgAAYJrguwSgARAQAgAAYJrguwSgARAQACAAIJvwtzrQEqAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Tenthrol:BAAALgAECgQJCgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgABLgAECgkJMAARAKUQAA==.Teratrendera:BAABLgAECn8dAAMlAAgJ+CHkBADTAgAlAAgJ+CHkBADTAgAeAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.Tesx:BAAALgAECgEJAgAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA/ZlwANAQAQAAcJQgzZlwANAQAVAAEJChYqOgBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICIFEwC6AgAIAAgJICIFEwC6AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAABLgAECn8YAAIDAAgJTiPhDACdAgADAAgJTiPhDACdAgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Ticktac:BAAALgAECgMJAwAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAABLgAECn8bAAMYAAkJnR+jAACQAgAYAAkJ+BqjAACQAgAVAAQJ1B8bBQAWAQAAAA==.Tilisi:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8nAAICAAgJnBbNSwD/AQACAAgJnBbNSwD/AQAAAA==.Tinkr:BAAALgAECgUJCAAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJEAABLgAECgkJIAAXAFQVAA==.Torrey:BAABLgAECn9JAAMNAAkJRhH9CgCtAQANAAkJRhH9CgCtAQAFAAQJXAidIwB7AAAAAA==.Totemsareus:BAABLgAFFH8OAAMWAAUJFxgMEQBNAQAWAAUJFxgMEQBNAQAXAAEJtgLOQAAqAAAAAA==.',
Tr='Tradd:BAACLgAFFH8YAAMaAAUJtRlEDwBWAQAaAAUJtRlEDwBWAQAZAAEJ4wsrKAA7AAAuAAQKfycAAxoACQmLHpsJANgCABoACQmLHpsJANgCABkABgm9EtwKABUBAAAA.Tresara:BAAALgADCgMJAwABLgAECgkJMQAWAAcfAA==.Trigg:BAAALgAECgUJBQABLgAFFAMJDQAFABYgAA==.Tristyana:BAACLgAFFH8GAAIIAAMJlgsSQACvAAAIAAMJlgsSQACvAAAuAAQKf2AAAggACQmSHh0QAM8CAAgACQmSHh0QAM8CAAAA.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsiddahn:BAAALgAECgQJBAAAAA==.Tsunâde:BAABLgAECn9JAAQPAAkJzyV+AABCAwAPAAkJzyV+AABCAwAhAAcJgxZEIwCZAQAKAAcJhBFqLQBRAQAAAA==.',
Tw='Twanu:BAAALgADCgUJBQAAAA==.Twinkletoe:BAAALgAECgQJBAABLgAECgkJSQAPAM8lAA==.',
Ty='Tylurien:BAABLgAECn8rAAIgAAkJEyKqBwARAwAgAAkJEyKqBwARAwAAAA==.Tyrael:BAAALgAECgEJAwABLgAECgkJbgAlAIoNAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uh='Uhnlikley:BAAALgAECgMJBAAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn9BAAIVAAkJSRAfDwBNAQAVAAkJSRAfDwBNAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9uAAIlAAkJig3YBAAFAQAlAAkJig3YBAAFAQAAAA==.Valora:BAACLgAFFH8GAAIaAAMJEQsqHwCVAAAaAAMJEQsqHwCVAAAuAAQKf3gABBoACQn1Hw8BACwDABoACQnJHg8BACwDABkACQk4FSEUAC4CABEABwljHX4hALYBAAAA.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8bAAIMAAgJYQZGcADkAAAMAAgJYQZGcADkAAAAAA==.Vargen:BAABLgAECn8tAAIoAAkJIBkDAwDLAQAoAAkJIBkDAwDLAQAAAA==.Varonika:BAABLgAECn8YAAIVAAcJewPwLQBhAAAVAAcJewPwLQBhAAAAAA==.Varrallis:BAAALgAECgEJAQAAAA==.Vayla:BAABLgAECn8zAAIcAAkJ3hsaCQBlAgAcAAkJ3hsaCQBlAgAAAA==.',
Ve='Vee:BAAALgAECgYJDwABLgAECgkJGwAFACkVAA==.Vegasbeasty:BAAALgADCgUJBQAAAA==.Vegasduc:BAAALgAECgEJAQAAAA==.Vegasducks:BAAALgAECgYJCQAAAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJLgAdAFMeAA==.Venøm:BAAALgADCgUJBQAAAA==.Veralyn:BAAALgAECgUJBgAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn9ZAAICAAkJihDKCwCrAQACAAkJihDKCwCrAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTANKbADvAAAMAAkJTANKbADvAAAAAA==.',
['Vä']='Vänhelsing:BAAALgAECgEJAQABLgAFFAMJBwACABULAA==.',
['Vè']='Vèngeance:BAAALgAECgMJAwAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjww6iADIAAAJAAMJjww6iADIAAAuAAQKfyoAAgkACQk+HwMeAKgCAAkACQk+HwMeAKgCAAAA.Wargrimm:BAABLgAECn8wAAIXAAkJLx83CwCuAgAXAAkJLx83CwCuAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8ZAAIgAAQJISaSEwCRAQAgAAQJISaSEwCRAQAuAAQKf5QAAyAACQnQJhIAAPgDACAACQnQJhIAAPgDAAIACQnTI98GADgDAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJIAASAO4WAA==.Whiisper:BAAALgAECgYJBwABLgAECgkJIAASAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJIAASAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJIAASAO4WAA==.Whisperz:BAAALgAECgMJAwABLgAECgkJIAASAO4WAA==.Whizpa:BAABLgAECn8gAAISAAkJ7hatFwAQAgASAAkJ7hatFwAQAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJIAASAO4WAA==.',
Wi='Wickedywaque:BAAALgAECgYJBgAAAA==.Wickerchickn:BAABLgAECn8ZAAIkAAkJThTsFgCbAQAkAAkJThTsFgCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJIAASAO4WAA==.Wilshammy:BAABLgAECn8jAAIWAAYJUAJ7IwB4AAAWAAYJUAJ7IwB4AAAAAA==.Wisper:BAAALgAECgIJAgABLgAECgkJIAASAO4WAA==.Wispy:BAABLgAECn8fAAIXAAcJAxOYNgBfAQAXAAcJAxOYNgBfAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQABLgAECgkJHAAZACoRAA==.',
Wr='Wrathbarrage:BAABLgAECn8WAAMIAAkJXBTRNAAKAgAIAAkJXBTRNAAKAgAGAAEJ6wbLZgAxAAABLgAECgkJGwANAJMIAA==.Wrathbourne:BAABLgAECn8bAAMNAAkJkwhqAwAuAQANAAkJEghqAwAuAQAEAAUJgQh6SQCQAAAAAA==.Wrathchoi:BAABLgAECn8UAAMPAAYJlgyeDQCqAAAPAAYJlgyeDQCqAAAKAAQJigJgDgBbAAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJGwANAJMIAA==.Wrathwraith:BAAALgAECgQJBQAAAA==.',
Xa='Xantchaa:BAAALgAECgEJAgABLgAECgkJHAAJAMQbAA==.Xaquandrel:BAACLgAFFH8IAAIDAAMJMBbIMQDoAAADAAMJMBbIMQDoAAAuAAQKfzUAAgMACQkgGtQSAFwCAAMACQkgGtQSAFwCAAAA.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8vAAMIAAkJvB6SMwDhAQAIAAkJDB2SMwDhAQAGAAYJxB8GHwCkAQAAAA==.Xilo:BAABLgAECn8UAAIkAAgJXBzfBAB0AQAkAAgJXBzfBAB0AQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAbAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazahk:BAABLgAECn8XAAQLAAcJXRsNAgDiAQALAAcJXRsNAgDiAQAcAAMJ1QydDACAAAADAAIJiBItGwBwAAABLgAECgQJBQAbAAAAAA==.Yazlura:BAAALgADCgMJAwAAAA==.Yazoth:BAAALgAECgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAMJBAABLgAFFAQJBQAOABcQAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgAECgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgQJBQAAAA==.',
Za='Zagyg:BAAALgAECgEJAQAAAA==.Zahon:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.Zandra:BAAALgAECgQJBAAAAA==.',
Ze='Zeddiccus:BAABLgAECn8cAAIJAAkJxBujNABGAgAJAAkJxBujNABGAgAAAA==.Zenicks:BAAALgAECgYJEQABLgAECgkJbgAlAIoNAA==.Zeva:BAABLgAECn8oAAIZAAkJCA+lBgB2AQAZAAkJCA+lBgB2AQAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAbAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8WAAIUAAgJ3B8aDgApAgAUAAgJ3B8aDgApAgABLgAECgkJMAARAKUQAA==.',
Zu='Zulti:BAAALgAECgUJBQAAAA==.Zurazaee:BAABLgAECn8jAAIRAAgJMhkuEwBCAgARAAgJMhkuEwBCAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAACLgAFFH8GAAIkAAMJsQ+wEwCKAAAkAAMJsQ+wEwCKAAAuAAQKf4EAAiQACQnrHgQBALYCACQACQnrHgQBALYCAAAA.',
['Ïr']='Ïridescent:BAAALgAECgQJBAAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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
