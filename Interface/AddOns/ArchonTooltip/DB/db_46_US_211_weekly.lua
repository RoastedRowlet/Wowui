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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Druid-Balance','Rogue-Assassination','DeathKnight-Blood','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Evoker-Augmentation','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','Evoker-Devastation','Paladin-Holy','Monk-Mistweaver','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Evoker-Preservation','DeathKnight-Frost','Rogue-Outlaw','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-08-04',data={Ac='Achooe:BAABLgAECn8vAAMBAAkJsQq5HAAvAQABAAkJsQq5HAAvAQACAAEJJgJI0QEXAAAAAA==.Acrylic:BAAALgAECgkJCQAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJDAAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgUJEQAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxtDCACaAgAGAAkJJxtDCACaAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBC6XADIAQAJAAkJQBC6XADIAQAAAA==.Agathorz:BAAALgAECgYJBwAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alanala:BAAALgADCgYJBgAAAA==.Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBmqMADtAAADAAMJgBmqMADtAAAuAAQKfzcAAwMACQnlJJoDAC8DAAMACQnlJJoDAC8DAAsABgn0EBUwAAgBAAAA.Allei:BAAALgAECgYJCQABLgAFFAYJHAAMAEgJAA==.Alyndrya:BAABLgAECn9BAAQEAAkJoxxbAgA9AgAEAAkJLxxbAgA9AgAFAAYJGhbeEAD9AAANAAEJkg3yNwAoAAAAAA==.Alyndrys:BAABLgAECn8jAAIOAAcJmhPoFgBeAQAOAAcJmhPoFgBeAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNRMxOgDeAQAFAAkJNRMxOgDeAQAAAA==.Amithralia:BAABLgAECn8zAAIMAAkJhCDBCQAeAwAMAAkJhCDBCQAeAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SImHQDFAQAPAAYJ0SImHQDFAQAAAA==.Angelstar:BAAALgADCgIJAgAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8bAAIQAAkJpRa7QgDTAQAQAAkJpRa7QgDTAQAAAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAkJSwAMABoiAA==.Aokuma:BAACLgAFFH9LAAIMAAkJGiIZAQBtAwAMAAkJGiIZAQBtAwAuAAQKfywAAwwACQlPJI8GACIDAAwACQlPJI8GACIDABEABAlSIRJIAAwBAAAA.',
Ap='Apep:BAAALgAECgEJAQAAAA==.Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn85AAISAAkJ2xiOAABgAgASAAkJ2xiOAABgAgAAAA==.Apriline:BAAALgADCgYJBwAAAA==.',
Aq='Aquaten:BAABLgAECn8jAAIGAAgJ9xVhFQD4AQAGAAgJ9xVhFQD4AQAAAA==.',
Ar='Aramac:BAAALgAECgQJBgAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRCZawDxAAAMAAgJJg6ZawDxAAARAAYJIBZyTwDPAAAAAA==.Arcafrost:BAAALgAECgkJCgAAAA==.Arceus:BAABLgAECn8aAAITAAYJ4g6dCgC5AAATAAYJ4g6dCgC5AAAAAA==.Archaon:BAABLgAECn9PAAMQAAkJPBoaAwBsAgAQAAkJPBoaAwBsAgAUAAEJAADdUgAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFwAVAAEWAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9IAAMVAAkJpib/AQBrAwAVAAkJpib/AQBrAwAWAAgJiiS/HwDkAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEwAAAA==.Asmódeus:BAABLgAECn8cAAQXAAgJoQ73DQBTAQAXAAYJWw73DQBTAQAQAAgJCgrIfgA7AQAUAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgAECgQJBQAAAA==.Atorbarak:BAAALgAECgYJDwABLgAFFAIJBQAIAJwGAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAACLgAFFH8KAAIJAAIJKwq0UwCGAAAJAAIJKwq0UwCGAAAuAAQKfy8AAgkACQmhGYUtAGMCAAkACQmhGYUtAGMCAAAA.',
Ay='Ayame:BAAALgAECgEJBAABLgAECgkJJQAYAI8jAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMZAAYJJxUINgA+AQAZAAYJJxUINgA+AQAaAAQJvBYcRgDvAAABLgAECgcJEwAbAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgABLgAECgkJEgAbAAAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8jAAIcAAgJHQW9KQDnAAAcAAgJHQW9KQDnAAAAAA==.Baelthas:BAAALgADCgcJDgAAAA==.Bashon:BAABLgAECn8UAAIVAAkJ8A7wBwC7AQAVAAkJ8A7wBwC7AQAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Bearybonds:BAAALgAECgMJAwAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belgaron:BAAALgAECggJCgABLgAECggJIgAPAGkcAA==.Belitha:BAACLgAFFH8NAAIFAAMJFiCySQAMAQAFAAMJFiCySQAMAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8zAAISAAkJNB2GAgCuAgASAAkJNB2GAgCuAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgYJCwAAAA==.Bety:BAAALgAECgkJCQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8kAAIdAAkJJw7UfQBoAQAdAAkJJw7UfQBoAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8cAAIMAAkJrBLwKQAFAgAMAAkJrBLwKQAFAgAAAA==.Bighunt:BAAALgAECgYJCwABLgAECgkJHAAMAKwSAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8fAAIEAAkJdw1FJQBPAQAEAAkJdw1FJQBPAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn9DAAINAAkJPCKNAwChAgANAAkJPCKNAwChAgAAAA==.Blegh:BAACLgAFFH8PAAMYAAUJaRicKQAiAQAYAAUJGhacKQAiAQAeAAEJlxUfDQBLAAAuAAQKfyMAAx4ACQnCHqcKADECAB4ABwnHHqcKADECABgABwl/GygfAMoBAAEuAAUUBgkPAAgAyRsA.Blueflu:BAAALgAECgcJCwAAAA==.Bluegrass:BAACLgAFFH8JAAIOAAMJqyCjAwAhAQAOAAMJqyCjAwAhAQAuAAQKf3EAAg4ACQnLJTIAAF8DAA4ACQnLJTIAAF8DAAAA.',
Bo='Bondï:BAABLgAECn8fAAMfAAgJxAnuRABkAQAfAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAABLgAECn8VAAIgAAkJSRDCFwDIAAAgAAkJSRDCFwDIAAAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAFFAEJAQAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxgyPwADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAbAAAAAA==.',
Br='Brat:BAAALgAFFAIJAgABLgAFFAkJVQAaAHAjAA==.Brighteye:BAAALgAECggJEgAAAA==.Brisket:BAABLgAECn8gAAMLAAkJSQ/7AwBJAQALAAkJwwz7AwBJAQAcAAgJOg3yBAA+AQAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleoseven:BAAALgAECgEJAQABLgAECgkJQgAdAM8bAA==.Buckme:BAACLgAFFH8fAAIIAAUJcBD2IwATAQAIAAUJcBD2IwATAQAuAAQKfyAAAggACAmgF9s1AAYCAAgACAmgF9s1AAYCAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bulldogs:BAAALgAECgEJAQAAAA==.Bulletprooff:BAAALgAECgEJAQAAAA==.Bulova:BAAALgADCgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAACLgAFFH8IAAIJAAYJUxdkUAA9AQAJAAYJUxdkUAA9AQAuAAQKfxoAAgkACQmeJKcBAEUDAAkACQmeJKcBAEUDAAEuAAUUCQkSABAA6xgA.Bustedhoof:BAAALgADCgMJAwAAAA==.',
['Bà']='Bàal:BAAALgAECgEJAQABLgAECgEJAQAbAAAAAA==.',
Ca='Caiphage:BAABLgAECn82AAIFAAkJqBtxAgBxAgAFAAkJqBtxAgBxAgAAAA==.Caladelm:BAABLgAECn85AAICAAkJah8IAwDUAgACAAkJah8IAwDUAgAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8xAAIdAAkJGROgCAC0AQAdAAkJGROgCAC0AQAAAA==.Carlarae:BAABLgAECn8YAAIJAAcJtgSr/QCwAAAJAAcJtgSr/QCwAAAAAA==.Carya:BAAALgAECgEJAQAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih0CTgBDAQAJAAQJih0CTgBDAQAuAAQKfxwAAgkACQksIdUTAOMCAAkACQksIdUTAOMCAAAA.Cegeo:BAABLgAECn9IAAIUAAkJihnAAwBTAgAUAAkJihnAAwBTAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn94AAMDAAkJnSMiAQDpAgADAAkJnSMiAQDpAgALAAEJ0g5seAAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhN9lQCXAAAQAAIJjhN9lQCXAAAuAAQKfyMAAxAABwncH8oyAA0CABAABwncH8oyAA0CABcABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAwAAAA==.',
Ci='Ciennajewel:BAABLgAECn8aAAIhAAgJVRtNEwBBAgAhAAgJVRtNEwBBAgAAAA==.Cirdle:BAABLgAECn9OAAMIAAkJYxI8CQDcAQAIAAkJYxI8CQDcAQAHAAMJIwZ1KwBnAAAAAA==.Cirona:BAABLgAECn8wAAMMAAkJJR7gAQCiAgAMAAkJJR7gAQCiAgAOAAEJvg7eFgAsAAABLgAECgkJMQAVAAcfAA==.',
Cl='Clausewitz:BAABLgAECn8aAAIcAAkJ7gq9HgA9AQAcAAkJ7gq9HgA9AQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8PAAMQAAUJVhrKIQAVAQAQAAUJVhrKIQAVAQAXAAEJngZUKgBCAAAuAAQKfyAAAhAACQk+HAkjAFQCABAACQk+HAkjAFQCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAbAAAAAA==.Coletta:BAAALgAECgEJAQAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIWAAgJ7gILXQDNAAAWAAgJ7gILXQDNAAAAAA==.Creamtastic:BAAALgAECggJEwAAAA==.Creamyweamy:BAABLgAECn8gAAIhAAgJWRR4HwDIAQAhAAgJWRR4HwDIAQABLgAECggJEwAbAAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA0DqgArAQAJAAcJQA0DqgArAQAiAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAABLgAECn8aAAMBAAYJ4BkSBABvAQABAAYJ4BkSBABvAQAfAAEJeBmMGABKAAAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8gAAMWAAkJWBWfHQD0AQAWAAkJWBWfHQD0AQAjAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn88AAIJAAkJOBFoDACQAQAJAAkJOBFoDACQAQAAAA==.',
Cu='Cuddly:BAABLgAFFH84AAIgAAkJiyMJAgALAwAgAAkJiyMJAgALAwABLgAFFAkJRwAaAGwlAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAIJAgABLgAFFAkJVQAaAHAjAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8kAAIgAAcJ6yTVBQC3AgAgAAcJ6yTVBQC3AgAuAAQKf5cAAiAACQmzJgwAAAkEACAACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAbAAAAAA==.Daggonet:BAACLgAFFH8FAAIdAAMJFxEORwDLAAAdAAMJFxEORwDLAAAuAAQKfx4AAh0ACQknIBIOAPsCAB0ACQknIBIOAPsCAAAA.Dahlina:BAAALgAECgUJBQABLgAFFAMJDQAFABYgAA==.Dalrin:BAABLgAECn8XAAMjAAYJ7A+uFQBiAQAjAAYJ7A+uFQBiAQAWAAQJzAfqZwCjAAAAAA==.Darkcarnival:BAABLgAECn8xAAIQAAkJ1BodIABkAgAQAAkJ1BodIABkAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAUJDgAVABcYAA==.Darkknightx:BAACLgAFFH8MAAIDAAQJ1w2DJgAbAQADAAQJ1w2DJgAbAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAABLgAECn8fAAIdAAgJqhIOCgCUAQAdAAgJqhIOCgCUAQABLgAFFAIJBQAWABEDAA==.Darthraider:BAABLgAECn8dAAIdAAcJGxH3hgBWAQAdAAcJGxH3hgBWAQAAAA==.Dasnotgood:BAABLgAECn8eAAMOAAcJ4B51AwBkAQAOAAYJsSB1AwBkAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQWAAgJxweBSwAHAQAWAAgJxweBSwAHAQAVAAEJowGnqgAhAAAjAAEJeAGKSAAdAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgcJCwAAAA==.',
De='Deathspeaker:BAAALgAECgIJAgABLgAECgkJOQAlACsVAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8bAAIFAAkJKRW0NwDnAQAFAAkJKRW0NwDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demeek:BAAALgAECgEJAQAAAA==.Demiish:BAABLgAECn8gAAIUAAcJmRWtAwBAAQAUAAcJmRWtAwBAAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8tAAMhAAkJdxN4KACDAQAhAAkJdxN4KACDAQAZAAcJ3hDRMgBPAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8nAAIRAAkJVxUQHQDgAQARAAkJVxUQHQDgAQAAAA==.Desdemona:BAABLgAECn83AAIBAAkJFiGIAQBAAgABAAkJFiGIAQBAAgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8KAAIIAAQJAA7JRwAeAQAIAAQJAA7JRwAeAQAuAAQKfxwAAwgACQl6GukcAHcCAAgACQl6GukcAHcCAAcAAglsA8FGABoAAAAA.',
Di='Dianimal:BAABLgAECn8nAAIRAAgJ1QlQPwARAQARAAgJ1QlQPwARAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEgAbAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAACLgAFFH8HAAMCAAMJFQvDmQCFAAACAAIJTQ/DmQCFAAAfAAIJDBeKHQBjAAAuAAQKfzIAAx8ACQkLJZMEAE8DAB8ACQkLJZMEAE8DAAIACAnvIisbAKECAAAA.',
Dk='Dklel:BAACLgAFFH8QAAIdAAUJ0CG7UQBOAQAdAAUJ0CG7UQBOAQAuAAQKf0AAAh0ACQl4Jj8HADwDAB0ACQl4Jj8HADwDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8OAAICAAQJnBTPHwANAQACAAQJnBTPHwANAQAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AbZKAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBKjcgCIAQACAAkJIBKjcgCIAQAAAA==.Dorow:BAAALgAECgEJAQAAAA==.',
Dr='Draaka:BAAALgAECgQJBQAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGwAFACkVAA==.Dragon:BAAALgAECgkJEQAAAA==.Dragonpunch:BAABLgAECn8qAAIgAAkJ6xkgHwAhAgAgAAkJ6xkgHwAhAgAAAA==.Driftyshaman:BAABLgAECn8qAAIWAAgJ7wqfTQD/AAAWAAgJ7wqfTQD/AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn80AAIdAAkJhwy4EQAgAQAdAAkJhwy4EQAgAQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAABLgAECn8nAAMIAAkJUB8yAwC6AgAIAAkJUB8yAwC6AgAHAAUJaxIoBADnAAABLgAECggJIgAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8uAAIjAAkJtA35EACkAQAjAAkJtA35EACkAQAAAA==.',
Dy='Dyamï:BAABLgAECn8zAAIgAAkJiiCTCAASAwAgAAkJiiCTCAASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
['Dá']='Dánte:BAAALgAECgMJBgAAAA==.',
Eg='Eglosira:BAABLgAECn8dAAIJAAkJmAjgggByAQAJAAkJmAjgggByAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgAECgEJAQAAAA==.Electric:BAABLgAECn8hAAIWAAgJXArFRgAZAQAWAAgJXArFRgAZAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAACLgAFFH8JAAIJAAMJDgoCQQDCAAAJAAMJDgoCQQDCAAAuAAQKfx4AAgkABwlLERyfADwBAAkABwlLERyfADwBAAAA.Ellä:BAAALgAECgYJDAAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxOBPwAuAQAIAAQJGxOBPwAuAQAuAAQKfzoAAggACQmPItcJAAkDAAgACQmPItcJAAkDAAAA.Elviric:BAAALgAECgEJAQAAAA==.',
Er='Eraleth:BAAALgAECgYJBgABLgAFFAMJDQAFABYgAA==.Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQABLgAECgkJEgAbAAAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Eu='Eukina:BAAALgAECgYJDAAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Ex='Exq:BAAALgAECgEJAQAAAA==.',
Fa='Faben:BAAALgAECgcJCgAAAA==.Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhH9QwCBAQAMAAcJvhH9QwCBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.Felfireflux:BAAALgAECgMJAwAAAA==.Fellirane:BAAALgAECgUJCAAAAA==.Felrein:BAAALgADCgUJBQABLgAECgkJKQAcAPELAA==.',
Fi='Finegas:BAAALgAECgYJBgABLgAECgkJEgAbAAAAAA==.Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8iAAIjAAgJUBuhAABxAgAjAAgJUBuhAABxAgAuAAQKfygAAiMACQnsJbUDAO8CACMACQnsJbUDAO8CAAAA.Floofndoom:BAAALgAFFAEJAQABLgAFFAgJIgAjAFAbAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAgJIgAjAFAbAA==.',
Fr='Fredrickk:BAABLgAECn8XAAMVAAcJARbcPwCuAQAVAAcJARbcPwCuAQAWAAQJWwqNegB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAABLgAFFAgJIgAjAFAbAA==.Furrylight:BAAALgAFFAIJAwABLgAFFAUJFAAVAGUYAA==.Furryphase:BAACLgAFFH8UAAIVAAUJZRirJQBUAQAVAAUJZRirJQBUAQAuAAQKfyQAAxUACQnxHAwNALUCABUACQnxHAwNALUCABYABAlyCTR+AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAgJIgAjAFAbAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.Gex:BAAALgAECgEJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn86AAIVAAkJth6tEwCvAgAVAAkJth6tEwCvAgAAAA==.',
Go='Goatjira:BAAALgAECgUJDQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Greygorypack:BAEALgADCgYJBQABLgAECgYJBgAbAAAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAmAGAgAA==.Gripisrdy:BAABLgAECn8xAAMdAAkJfSA0FQDIAgAdAAkJfSA0FQDIAgATAAMJgRjqNQC/AAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8nAAMnAAkJ8CJGAQD0AgAnAAkJ8CJGAQD0AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAACLgAFFH8FAAMWAAIJEQPsLQBWAAAWAAIJEQPsLQBWAAAVAAIJZAhaRABMAAAuAAQKfxkAAhUACAnUDnJIAIwBABUACAnUDnJIAIwBAAAA.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAgAAAA==.Haggrd:BAABLgAECn8iAAICAAkJnR8IJwBoAgACAAkJnR8IJwBoAgAAAA==.Hairyjolene:BAABLgAECn8jAAIIAAgJERNpSQDFAQAIAAgJERNpSQDFAQAAAA==.Halleberries:BAEALgAECgYJBgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJCAADADAWAA==.Handsome:BAABLgAFFH8FAAIIAAMJHhf6SACSAAAIAAMJHhf6SACSAAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgkJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAACLgAFFH8MAAMdAAQJtRPwaAAnAQAdAAQJxRLwaAAnAQAmAAIJ4BJ5EgCRAAAuAAQKfxUABCYACAlbFFYJAKkAABMABgmHEA4mAA8BACYAAgkVHFYJAKkAAB0ABAmZDGgpAXcAAAAA.',
Hi='Highlander:BAAALgAECgEJAgAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxP2mgBAAAAFAAEJvxP2mgBAAAABLgAFFAkJSwAMABoiAA==.Hikarimonk:BAABLgAFFH8nAAIgAAkJHh+0AgDiAgAgAAkJHh+0AgDiAgABLgAFFAkJSwAMABoiAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAkJSwAMABoiAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Hoather:BAAALgAECgQJBAABLgAFFAMJBwACABULAA==.Holyarceus:BAAALgADCgQJBAABLgAECgYJGgATAOIOAA==.Holyblimblam:BAAALgAECgYJEgAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8oAAMdAAgJBB69RQDxAQAdAAgJmB29RQDxAQATAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIZAAYJNA0RRwDzAAAZAAYJNA0RRwDzAAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Humper:BAAALgAECgMJBwAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.Huntley:BAAALgAECgkJEwABLgAECgkJIAALAEkPAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifire:BAAALgADCgYJBgAAAA==.Hèrifury:BAABLgAECn80AAMcAAkJlx0WAQCnAgAcAAkJlx0WAQCnAgADAAMJagwnFwCGAAAAAA==.',
Ic='Icyjackets:BAABLgAECn8jAAMdAAgJtA9VdgB3AQAdAAgJtA9VdgB3AQATAAQJpAUkRwBxAAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAFFAEJAwAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Is='Iscorn:BAAALgAECgcJDAAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA88UwCpAQAIAAkJlA88UwCpAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRcmJgDHAQADAAgJBRcmJgDHAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn9LAAMMAAkJLRQ9BgCBAQAMAAkJLRQ9BgCBAQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAbAAAAAA==.Jel:BAAALgADCgEJAQAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAbAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIWAAYJfg7LWgDUAAAWAAYJfg7LWgDUAAAAAA==.Jessicà:BAAALgAECgQJBQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAwAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8mAAMVAAYJIhYRNgCrAQAVAAYJIhYRNgCrAQAWAAUJfBL/XADNAAAAAA==.Jiwà:BAABLgAFFH8IAAIVAAUJjgcxOAACAQAVAAUJjgcxOAACAQABLgAFFAYJEwAZAJ4KAA==.Jiwâ:BAACLgAFFH8TAAIZAAYJngo/HwD5AAAZAAYJngo/HwD5AAAuAAQKfzkAAhkACQlGHhcNAIICABkACQlGHhcNAIICAAAA.Jiwå:BAAALgAECgYJCwAAAA==.',
Jo='Joecool:BAAALgAECgQJBAAAAA==.Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJDQAFABYgAA==.Kahless:BAAALgAECgEJAQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAcaRwApAQADAAkJMAcaRwApAQAAAA==.Kaliyah:BAAALgADCgcJCQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAABLgAECn8VAAIRAAkJvAfZCgABAQARAAkJvAfZCgABAQAAAA==.Kavorkyan:BAAALgAECgkJEwAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMmAAkJYCCbEgBPAQAdAAYJ7hpDXQDbAQAmAAcJyB+bEgBPAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9NAAMKAAkJKR45CACwAgAKAAkJKR45CACwAgAPAAEJ6gupIgAoAAAAAA==.',
Ki='Kiamara:BAABLgAECn8uAAIQAAkJIQtwDgARAQAQAAkJIQtwDgARAQAAAA==.Kinderlin:BAABLgAECn8sAAICAAkJER2hAwCnAgACAAkJER2hAwCnAgAAAA==.Kipo:BAABLgAECn8VAAIGAAkJlQ9hAwB1AQAGAAkJlQ9hAwB1AQAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.Kotys:BAAALgAECgUJCAAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhbbNwC4AQAMAAcJbhbbNwC4AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.Krzytotems:BAAALgAECgMJAwAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECggJEQAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQeAAgJfRaSDwDiAQAeAAYJNhmSDwDiAQAYAAMJfRSEQgDYAAAlAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.Lethalarrow:BAAALgAECgYJBgAAAA==.Lethalpally:BAAALgAECgEJAQAAAA==.Lethalpixi:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgcJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgcJCwAAAA==.Lista:BAABLgAECn8XAAMaAAkJqiD6AwBaAwAaAAkJqiD6AwBaAwAZAAEJEgrijgAsAAABLgAECgkJSQAPAM8lAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyVwAQBPAwAGAAkJDiVwAQBPAwAIAAgJlybzDADrAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Locklobstah:BAAALgADCgIJAgAAAA==.Lola:BAAALgAECgkJAgAAAA==.Loralynn:BAACLgAFFH8cAAMMAAYJSAk/EAAWAQAMAAYJSAk/EAAWAQARAAEJggJFMwAlAAAuAAQKfxQAAgwABwn7FD04ALYBAAwABwn7FD04ALYBAAAA.Lorianne:BAACLgAFFH8HAAIVAAIJwRVzaQBtAAAVAAIJwRVzaQBtAAAuAAQKfygAAxUACAmvGGQpAOkBABUACAmvGGQpAOkBABYABQmxC7tWAOoAAAEuAAUUBgkcAAwASAkA.Lorri:BAAALgADCgQJBQABLgAFFAYJHAAMAEgJAA==.',
Lu='Lucianas:BAABLgAECn8UAAICAAgJUw5SjgBVAQACAAgJUw5SjgBVAQAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgkJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8jAAIIAAgJIh69GgCFAgAIAAgJIh69GgCFAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgIJBAAAAA==.Madaea:BAABLgAECn8zAAIgAAkJqh8MCwDoAgAgAAkJqh8MCwDoAgAAAA==.Madameuyen:BAAALgADCgkJEQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRzlHgCkAgAJAAkJHRzlHgCkAgABLgAFFAQJGwAGAJgbAA==.Mahai:BAAALgADCgcJBAABLgAECgkJEgAbAAAAAA==.Mak:BAABLgAECn8WAAIhAAcJSBwDFAA3AgAhAAcJSBwDFAA3AgABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx39KwAtAgAIAAgJUx39KwAtAgAAAA==.Makthamonk:BAAALgAECgYJCQABLgAECggJGAAIAFMdAA==.Malholis:BAABLgAECn8pAAIaAAkJ/A4ABQDGAQAaAAkJ/A4ABQDGAQAAAA==.Malzeth:BAAALgAECgcJDAAAAA==.Marrilyn:BAAALgAFFAEJAwABLgAFFAgJHgAQALIeAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn83AAIIAAkJzyCgCwD3AgAIAAkJzyCgCwD3AgAAAA==.Mate:BAAALgAECgUJDAABLgAECgkJIAALAEkPAA==.Mavuika:BAAALgAECgIJAwAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Meatloaf:BAAALgAECgQJBAAAAA==.Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAFFAIJAgAAAA==.Megabyte:BAAALgADCgUJBQABLgAECggJCAAbAAAAAA==.Melbeast:BAABLgAECn8oAAIIAAkJlx1ABwAQAgAIAAkJlx1ABwAQAgAAAA==.Melorea:BAAALgAECggJDAAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxATXADKAQAJAAkJNhATXADKAQAiAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMUAAgJpQkqFQACAQAUAAgJpQkqFQACAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgAECgMJAwAAAA==.Mignon:BAAALgAECgYJDAABLgAECgkJIAALAEkPAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJEgAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn9JAAIBAAkJ5wQvCgCzAAABAAkJ5wQvCgCzAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECggJDgAAAA==.Moistwhispa:BAAALgAECgQJCAABLgAECgkJIAARAO4WAA==.Molfise:BAABLgAECn89AAMPAAkJfCKyAQBQAgAKAAkJdiJAAQBeAgAPAAkJtxqyAQBQAgAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn9AAAIhAAkJ4B+FBgAKAwAhAAkJ4B+FBgAKAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8xAAMcAAkJGQcTBwDoAAAcAAgJ8gQTBwDoAAALAAgJJAfJOQDeAAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgUJCAAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEQAbAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAfAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mysticx:BAAALgAECgYJDAABLgAECgcJHwAWAAMTAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAgAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgYjtAAbAQAJAAgJBgYjtAAbAQABLgAECgkJEgAbAAAAAA==.',
Na='Nachtelf:BAACLgAFFH8GAAIIAAMJwhLiMgDWAAAIAAMJwhLiMgDWAAAuAAQKf3AAAggACQlJIpMHACEDAAgACQlJIpMHACEDAAAA.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAVAFYTAA==.Nannysham:BAABLgAECn8WAAIVAAkJVhMlLQADAgAVAAkJVhMlLQADAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAACLgAFFH8GAAIJAAMJSxU4NQDvAAAJAAMJSxU4NQDvAAAuAAQKf2cAAgkACQnSJPwFAFMDAAkACQnSJPwFAFMDAAAA.Nathel:BAAALgAECgcJBwAAAA==.Natherel:BAABLgAECn8YAAQLAAgJ2QSEQQDBAAALAAcJVgWEQQDBAAADAAUJ5gPofQB+AAAcAAEJ5QEkWwAgAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8qAAMYAAgJQRRiBwAcAgAYAAgJQRRiBwAcAgAlAAYJUxYfEwBhAQAuAAQKf08AAxgACQmNJUEAAHEDABgACQmNJUEAAHEDACUACAl2G3wNAPgBAAEuAAUUCQlVABoAcCMA.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRNSLQDxAQAMAAkJaRNSLQDxAQABLgAECggJIgAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgUJEwAAAA==.',
No='Nonphatmilk:BAABLgAECn8WAAIgAAkJIB0MBAAgAgAgAAkJIB0MBAAgAgAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAACLgAFFH8FAAIdAAMJLARVXwCXAAAdAAMJLARVXwCXAAAuAAQKfy0AAx0ACQmbEipRANABAB0ACQmbEipRANABABMAAQkbEnpFADIAAAAA.Novatron:BAAALgAECgYJBgAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR/xTAD1AQAJAAgJCR/xTAD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8dAAIMAAgJcgYaawDzAAAMAAgJcgYaawDzAAAAAA==.',
Om='Omee:BAABLgAECn8oAAMEAAkJ1RvlDwAqAgAEAAkJ1RvlDwAqAgAFAAYJ+Qs9jAAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w6PlwBKAQAJAAcJ4w6PlwBKAQAAAA==.',
Op='Ophela:BAAALgAECgMJBQAAAA==.',
Or='Or:BAAALgAECgIJAgAAAA==.Orakio:BAABLgAFFH8UAAIdAAQJIhb/JgA1AQAdAAQJIhb/JgA1AQABLgAFFAYJIQAJAAMaAA==.Oralena:BAABLgAECn8jAAIIAAgJXggRdQBVAQAIAAgJXggRdQBVAQAAAA==.Orioncheats:BAABLgAECn9CAAIdAAkJzxuAKwBSAgAdAAkJzxuAKwBSAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAbAAAAAA==.',
Ox='Oxygën:BAABLgAECn8wAAIJAAkJXxCUDACNAQAJAAkJXxCUDACNAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8RAAIfAAQJgBt5HQAyAQAfAAQJgBt5HQAyAQAuAAQKfxwAAh8ACAnfIvUHAAwDAB8ACAnfIvUHAAwDAAEuAAUUBQkOABUAFxgA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAbAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9MAAMPAAkJaR+jCAC8AgAPAAkJaR+jCAC8AgAgAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8UAAIDAAcJKxrxIgDbAQADAAcJKxrxIgDbAQAAAA==.Persephonee:BAAALgADCgEJAQAAAA==.',
Ph='Pharune:BAABLgAECn8xAAIkAAkJvRIDFgCjAQAkAAkJvRIDFgCjAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8yAAIJAAkJShhXOQAzAgAJAAkJShhXOQAzAgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJFAAWADEgAA==.Picklebob:BAAALgAECggJCAABLgAFFAQJFAAWADEgAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJFAAWADEgAA==.Picklebosh:BAABLgAFFH8UAAIWAAQJMSCdDQBaAQAWAAQJMSCdDQBaAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Plantain:BAAALgADCgIJAgAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Pointnshoot:BAAALgAECgEJAQABLgAFFAIJAgAbAAAAAA==.Ponky:BAABLgAECn8cAAIZAAkJKhHxKgB7AQAZAAkJKhHxKgB7AQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pothands:BAAALgADCgEJAQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8NAAIMAAMJghQzQgCpAAAMAAMJghQzQgCpAAABLgAFFAkJRwAaAGwlAA==.',
Pr='Preacha:BAAALgAECgYJCgABLgAFFAIJBQAWABEDAA==.Precious:BAACLgAFFH83AAIaAAgJ6BsLBACqAgAaAAgJ6BsLBACqAgAuAAQKf1YABBoACQltJiQAAPUDABoACQltJiQAAPUDACEABglwDxs2AGQBABkABAkvE7pXALUAAAEuAAUUCQlVABoAcCMA.',
Pu='Puppet:BAAALgAECgkJCQABLgAFFAkJVQAaAHAjAA==.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAcAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIeAAkJXgunEAABAQAeAAkJXgunEAABAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAACLgAFFH8IAAIDAAMJ3xJLIQClAAADAAMJ3xJLIQClAAAuAAQKfzoAAwMACAkVHiETAFkCAAMACAn4HSETAFkCAAsAAQmKFVZzADsAAAAA.Raezil:BAAALgAECgEJAQAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8iAAMPAAgJaRx0EgAtAgAPAAgJaRx0EgAtAgAgAAIJpw2loABYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJCgABLgAECgkJMwAMAIQgAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8wAAIhAAkJpRBUJgCTAQAhAAkJpRBUJgCTAQAAAA==.Raziel:BAAALgAECgQJBAAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Redranger:BAAALgADCgQJBAABLgAECgIJBQAbAAAAAA==.Rehum:BAABLgAECn8UAAICAAYJPghx9QDEAAACAAYJPghx9QDEAAAAAA==.Remagtrepxe:BAAALgAECgEJAQABLgAECggJKgAWAO8KAA==.Remniscence:BAAALgAECgEJAQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Renard:BAAALgAECgUJBQAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8uAAMjAAkJRxEDFQBtAQAjAAgJFBMDFQBtAQAVAAYJ3gfSjgC7AAAAAA==.Revèndreth:BAAALgAECgQJBQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgQJBwAAAA==.',
Rh='Rhylee:BAAALgAECgYJCQAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9LAAIZAAkJChVaGAAEAgAZAAkJChVaGAAEAgAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Rm='Rmplstiltskn:BAAALgADCgkJCQAAAA==.',
Ro='Robberttrest:BAABLgAECn8dAAIIAAYJ0hGQGAAQAQAIAAYJ0hGQGAAQAQAAAA==.Rockydemon:BAAALgAECgEJAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMdAAkJERs8QQD/AQAdAAkJ5xo8QQD/AQAmAAYJrhWxCABaAQAAAA==.Rockymage:BAAALgAECgQJBgAAAA==.Rockymonk:BAAALgAECgEJAQAAAA==.Rockypally:BAAALgAECgEJAQAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn9MAAIeAAkJgRx3AACbAgAeAAkJgRx3AACbAgAAAA==.Roryn:BAACLgAFFH8LAAICAAMJWR/AOQCzAAACAAMJWR/AOQCzAAAuAAQKf2MAAgIACQlWJmkBAIIDAAIACQlWJmkBAIIDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8IAAIDAAMJfBmdLwDyAAADAAMJfBmdLwDyAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAkJNwAMALQfAA==.Rugiia:BAACLgAFFH83AAIMAAkJtB88AgAnAwAMAAkJtB88AgAnAwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJbsbAC4BAAAA.Rugiian:BAABLgAFFH8NAAIgAAUJ7xycHACOAQAgAAUJ7xycHACOAQABLgAFFAkJNwAMALQfAA==.Rulakir:BAAALgADCgQJBAABLgAFFAYJIQAJAAMaAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQkZZQB0AQAQAAkJjQkZZQB0AQAAAA==.Ryuka:BAABLgAECn8uAAIkAAkJEwugKAAUAQAkAAkJEwugKAAUAQAAAA==.',
['Râ']='Râezil:BAAALgAECgEJAQABLgAECgEJAQAbAAAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAbAAAAAA==.Samyria:BAABLgAECn8eAAIIAAkJSxERDQCRAQAIAAkJSxERDQCRAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgAECgMJAwAAAA==.Satyaru:BAABLgAECn8qAAQgAAkJFwwxQABtAQAgAAkJFwwxQABtAQAPAAcJlg4bPAAQAQAKAAEJogogFgAhAAAAAA==.Saucy:BAABLgAECn8XAAMWAAgJeyB+DQCQAgAWAAgJeyB+DQCQAgAjAAEJAADDSgAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAbAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8+AAIhAAkJlxeEAwD0AQAhAAkJlxeEAwD0AQAAAA==.Selati:BAAALgADCgMJAwAAAA==.Seric:BAABLgAECn8pAAMcAAkJ8QtFHQBLAQAcAAkJ8QtFHQBLAQADAAQJugTShwBjAAAAAA==.Sesethi:BAAALgAECgQJBgABLgAECggJHgAQAAQfAA==.',
Sh='Shadowdancèr:BAABLgAECn8lAAMZAAkJGxoEHgDVAQAZAAgJaxkEHgDVAQAaAAQJMhPzUgC2AAAAAA==.Shadowlocke:BAAALgAECgYJCwAAAA==.Shadowyisis:BAABLgAECn8VAAIZAAkJyBQWFwAQAgAZAAkJyBQWFwAQAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8bAAIGAAQJmBtRBgA2AQAGAAQJmBtRBgA2AQAuAAQKf0QAAwYACQnQI3ECACIDAAYACQm3I3ECACIDAAcABwnWHTkbAE8CAAAA.Shenandoah:BAAALgAECgQJBAAAAA==.Shiftyelf:BAAALgADCgYJBgAAAA==.Shirizani:BAAALgAECgQJBAABLgAFFAYJGAABAIwNAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Silentwrath:BAAALgAECgEJAQABLgAECgkJGwANAJMIAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAkJKAAcAIgcAA==.Skybox:BAAALgAECgUJCAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMaAAYJvhFAMAAeAQAaAAUJiBBAMAAeAQAhAAUJfQ/9UwCNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8MAAIJAAMJKgR9TgCWAAAJAAMJKgR9TgCWAAAuAAQKfzUAAgkACQmEE+FGAAYCAAkACQmEE+FGAAYCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.Snuggy:BAAALgAECgcJDwAAAA==.',
So='Soapytatas:BAAALgAFFAEJAgAAAA==.Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQfAAkJRgzjLwCbAQAfAAkJRgzjLwCbAQABAAYJQBOeKgDFAAACAAEJYBbEhQE5AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAbAAAAAA==.Splashdaddy:BAACLgAFFH8cAAIVAAUJvyGQCwCUAQAVAAUJvyGQCwCUAQAuAAQKfykAAhUACQmkJJkHADYDABUACQmkJJkHADYDAAEuAAUUAQkBABsAAAAA.Spoiled:BAABLgAFFH8GAAIgAAYJdQYeGQADAQAgAAYJdQYeGQADAQABLgAFFAkJVQAaAHAjAA==.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgcJDAAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn9AAAMVAAkJOQ5sCgCCAQAVAAkJOQ5sCgCCAQAWAAIJcQgRIwBHAAAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDQAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Summonme:BAABLgAECn8dAAQQAAkJmiSbAABZAwAQAAkJfySbAABZAwAUAAMJpiVFBgDeAAAXAAMJRB0fBgDcAAAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sw='Sweetshot:BAAALgADCgIJAgAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgUJDgAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn9fAAIkAAkJqyRkAABGAwAkAAkJqyRkAABGAwAAAA==.',
Ta='Taea:BAABLgAECn8xAAMVAAkJBx+3AQAAAwAVAAkJBx+3AQAAAwAWAAYJfRvEBQCNAQAAAA==.Taeus:BAACLgAFFH8hAAIJAAYJAxpEGwCRAQAJAAYJAxpEGwCRAQAuAAQKfx0AAwkACQkiGeBeAB4CAAkACQkiGeBeAB4CACkABAloE/ICALQAAAAA.Taintedcure:BAAALgADCgkJEgAAAA==.Taintedkoma:BAAALgAECggJCwABLgAECggJIAAUAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Taliesien:BAAALgADCgYJBgABLgAECgkJbgAlAIoNAA==.Tamer:BAAALgAECgYJBgABLgAFFAcJJAAgAOskAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAABLgAECn8eAAIFAAcJGAgNGAC/AAAFAAcJGAgNGAC/AAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIcAAkJoiEKCAClAgAcAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AHm0wCjAAAIAAgJ/AHm0wCjAAAAAA==.',
Te='Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgUJCgAAAA==.Temajin:BAABLgAECn8YAAMfAAYJrguwSgARAQAfAAYJrguwSgARAQACAAIJvwtzrQEqAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Tenthrol:BAAALgAECgMJAwAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8dAAMlAAgJ+CHkBADTAgAlAAgJ+CHkBADTAgAYAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.Tesx:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA/ZlwANAQAQAAcJQgzZlwANAQAUAAEJChYqOgBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICIFEwC6AgAIAAgJICIFEwC6AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAABLgAECn8YAAIDAAgJTiPhDACdAgADAAgJTiPhDACdAgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Ticktac:BAAALgAECgMJAwAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgAECgkJEwAAAA==.Tilisi:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8nAAICAAgJnBbNSwD/AQACAAgJnBbNSwD/AQAAAA==.Tinkr:BAAALgAECgUJCAAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJEAABLgAECgkJIAAWAFQVAA==.Torrey:BAABLgAECn9JAAMNAAkJRhH9CgCtAQANAAkJRhH9CgCtAQAFAAQJXAjbIQB9AAAAAA==.Totemsareus:BAABLgAFFH8OAAMVAAUJFxj9DwBWAQAVAAUJFxj9DwBWAQAWAAEJtgK2PwAqAAAAAA==.',
Tr='Tradd:BAACLgAFFH8YAAMaAAUJtRmuDgBYAQAaAAUJtRmuDgBYAQAZAAEJ4wvxJgA7AAAuAAQKfycAAxoACQmLHpsJANgCABoACQmLHpsJANgCABkABgm9EhQKABgBAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJDQAFABYgAA==.Tristyana:BAACLgAFFH8GAAIIAAMJlgugPgCvAAAIAAMJlgugPgCvAAAuAAQKf2AAAggACQmSHh0QAM8CAAgACQmSHh0QAM8CAAAA.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsiddahn:BAAALgAECgQJBAAAAA==.Tsunâde:BAABLgAECn9JAAQPAAkJzyV0AABHAwAPAAkJzyV0AABHAwAgAAcJgxZEIwCZAQAKAAcJhBFqLQBRAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJSQAPAM8lAA==.',
Ty='Tylurien:BAABLgAECn8rAAIfAAkJEyKqBwARAwAfAAkJEyKqBwARAwAAAA==.Tyrael:BAAALgAECgEJAwABLgAECgkJbgAlAIoNAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uh='Uhnlikley:BAAALgAECgIJAgAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn9BAAIUAAkJSRAfDwBNAQAUAAkJSRAfDwBNAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9uAAIlAAkJig1VBAALAQAlAAkJig1VBAALAQAAAA==.Valora:BAACLgAFFH8GAAIaAAMJEQs/HgCZAAAaAAMJEQs/HgCZAAAuAAQKf3gABBoACQn1H/UAAC0DABoACQnJHvUAAC0DABkACQk4FSEUAC4CACEABwljHX4hALYBAAAA.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8bAAIMAAgJYQZGcADkAAAMAAgJYQZGcADkAAAAAA==.Vargen:BAABLgAECn8tAAIoAAkJIBnJAgDMAQAoAAkJIBnJAgDMAQAAAA==.Varonika:BAABLgAECn8YAAIUAAcJewPwLQBhAAAUAAcJewPwLQBhAAAAAA==.Varrallis:BAAALgAECgEJAQAAAA==.Vayla:BAABLgAECn8zAAIcAAkJ3hsaCQBlAgAcAAkJ3hsaCQBlAgAAAA==.',
Ve='Vee:BAAALgAECgYJDwABLgAECgkJGwAFACkVAA==.Vegasbeasty:BAAALgADCgUJBQAAAA==.Vegasduc:BAAALgAECgEJAQAAAA==.Vegasducks:BAAALgAECgYJCQAAAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJKAAdAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Veralyn:BAAALgAECgUJBgAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn9ZAAICAAkJihDWCgCsAQACAAkJihDWCgCsAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTANKbADvAAAMAAkJTANKbADvAAAAAA==.',
['Vä']='Vänhelsing:BAAALgAECgEJAQABLgAFFAMJBwACABULAA==.',
['Vè']='Vèngeance:BAAALgAECgMJAwAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjww6iADIAAAJAAMJjww6iADIAAAuAAQKfyoAAgkACQk+HwMeAKgCAAkACQk+HwMeAKgCAAAA.Wargrimm:BAABLgAECn8wAAIWAAkJLx83CwCuAgAWAAkJLx83CwCuAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8ZAAIfAAQJISaSEwCRAQAfAAQJISaSEwCRAQAuAAQKf4sAAx8ACQnQJhIAAPgDAB8ACQnQJhIAAPgDAAIACQnTI98GADgDAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJIAARAO4WAA==.Whiisper:BAAALgAECgYJBwABLgAECgkJIAARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJIAARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whisperz:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whizpa:BAABLgAECn8gAAIRAAkJ7hatFwAQAgARAAkJ7hatFwAQAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJIAARAO4WAA==.',
Wi='Wickedywaque:BAAALgAECgYJBgAAAA==.Wickerchickn:BAABLgAECn8ZAAIkAAkJThTsFgCbAQAkAAkJThTsFgCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJIAARAO4WAA==.Wilshammy:BAABLgAECn8jAAIVAAYJUAI6IQB4AAAVAAYJUAI6IQB4AAAAAA==.Wisper:BAAALgAECgIJAgABLgAECgkJIAARAO4WAA==.Wispy:BAABLgAECn8fAAIWAAcJAxOYNgBfAQAWAAcJAxOYNgBfAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAABLgAECn8WAAMIAAkJXBTRNAAKAgAIAAkJXBTRNAAKAgAGAAEJ6wbLZgAxAAABLgAECgkJGwANAJMIAA==.Wrathbourne:BAABLgAECn8bAAMNAAkJkwgyAwAuAQANAAkJEggyAwAuAQAEAAUJgQh6SQCQAAAAAA==.Wrathchoi:BAABLgAECn8UAAMPAAYJlgyXDACsAAAPAAYJlgyXDACsAAAKAAQJigKjDQBbAAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJGwANAJMIAA==.Wrathwraith:BAAALgAECgQJBQAAAA==.',
Xa='Xantchaa:BAAALgAECgEJAgABLgAECgkJHAAJAMQbAA==.Xaquandrel:BAACLgAFFH8IAAIDAAMJMBbIMQDoAAADAAMJMBbIMQDoAAAuAAQKfzUAAgMACQkgGtQSAFwCAAMACQkgGtQSAFwCAAAA.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8vAAMIAAkJvB6SMwDhAQAIAAkJDB2SMwDhAQAGAAYJxB8GHwCkAQAAAA==.Xilo:BAABLgAECn8UAAIkAAgJXByXBAB1AQAkAAgJXByXBAB1AQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAbAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazahk:BAABLgAECn8VAAQLAAcJXRvMAQDjAQALAAcJXRvMAQDjAQAcAAMJ1QzTCwCAAAADAAEJVhHxKAA0AAABLgAECgQJBQAbAAAAAA==.Yazlura:BAAALgADCgMJAwAAAA==.Yazoth:BAAALgAECgIJAgAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAMJBAABLgAFFAQJBQAOABcQAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgAECgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgQJBQAAAA==.',
Za='Zagyg:BAAALgAECgEJAQAAAA==.Zahon:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.Zandra:BAAALgAECgQJBAAAAA==.',
Ze='Zeddiccus:BAABLgAECn8cAAIJAAkJxBujNABGAgAJAAkJxBujNABGAgAAAA==.Zenicks:BAAALgAECgYJEQABLgAECgkJbgAlAIoNAA==.Zeva:BAABLgAECn8oAAIZAAkJCA/kBQB/AQAZAAkJCA/kBQB/AQAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAbAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8WAAITAAgJ3B8aDgApAgATAAgJ3B8aDgApAgAAAA==.',
Zu='Zulti:BAAALgAECgUJBQAAAA==.Zurazaee:BAABLgAECn8jAAIhAAgJMhkuEwBCAgAhAAgJMhkuEwBCAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAACLgAFFH8GAAIkAAMJsQ8zEwCMAAAkAAMJsQ8zEwCMAAAuAAQKf3gAAiQACQnTHgABAK8CACQACQnTHgABAK8CAAAA.',
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
