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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Druid-Balance','Rogue-Assassination','DeathKnight-Blood','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Evoker-Augmentation','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','Evoker-Devastation','Paladin-Holy','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Monk-Mistweaver','Druid-Guardian','Evoker-Preservation','DeathKnight-Frost','Rogue-Outlaw','Rogue-Subtlety',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-06-28',data={Ac='Achooe:BAABLgAECn8vAAMBAAkJsQq5HAAvAQABAAkJsQq5HAAvAQACAAEJJgJI0QEXAAAAAA==.Acrylic:BAAALgAECgkJCQAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJDAAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJCwAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxtDCACaAgAGAAkJJxtDCACaAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBC6XADIAQAJAAkJQBC6XADIAQAAAA==.Agathorz:BAAALgAECgYJBwAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alanala:BAAALgADCgYJBgAAAA==.Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBmqMADtAAADAAMJgBmqMADtAAAuAAQKfzcAAwMACQnlJJoDAC8DAAMACQnlJJoDAC8DAAsABgn0EBUwAAgBAAAA.Allei:BAAALgAECgYJCQABLgAFFAQJEgAMAC4LAA==.Alyndrya:BAABLgAECn8xAAQEAAkJHxk3AgBtAQAEAAkJqxg3AgBtAQAFAAYJvxKhgQAcAQANAAEJkg3yNwAoAAAAAA==.Alyndrys:BAABLgAECn8jAAIOAAcJmhPoFgBeAQAOAAcJmhPoFgBeAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNRMxOgDeAQAFAAkJNRMxOgDeAQAAAA==.Amithralia:BAABLgAECn8zAAIMAAkJgyDBCQAeAwAMAAkJgyDBCQAeAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SImHQDFAQAPAAYJ0SImHQDFAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8YAAIQAAgJAxe7QgDTAQAQAAgJAxe7QgDTAQAAAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAkJOgAMAAciAA==.Aokuma:BAACLgAFFH86AAIMAAkJByIZAQBtAwAMAAkJByIZAQBtAwAuAAQKfywAAwwACQlPJI8GACIDAAwACQlPJI8GACIDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8uAAISAAgJahPCAABDAQASAAgJahPCAABDAQAAAA==.',
Aq='Aquaten:BAABLgAECn8jAAIGAAgJ9xVhFQD4AQAGAAgJ9xVhFQD4AQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRCZawDxAAAMAAgJJg6ZawDxAAARAAYJIBZyTwDPAAAAAA==.Arcafrost:BAAALgAECgkJCgAAAA==.Arceus:BAABLgAECn8UAAITAAYJkQ48BgCBAAATAAYJkQ48BgCBAAAAAA==.Archaon:BAABLgAECn81AAMQAAkJWxeEAQA/AgAQAAkJWxeEAQA/AgAUAAEJAADdUgAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFgAVAHUUAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9GAAMVAAkJpib/AQBrAwAVAAkJpib/AQBrAwAWAAYJIyW/HwDkAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEwAAAA==.Asmódeus:BAABLgAECn8cAAQXAAgJoQ73DQBTAQAXAAYJWw73DQBTAQAQAAgJCgrIfgA7AQAUAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgAECgMJBAAAAA==.Atorbarak:BAAALgAECgYJCQABLgAECggJJQAHAB4QAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAACLgAFFH8JAAIJAAIJzgnYMACHAAAJAAIJzgnYMACHAAAuAAQKfy8AAgkACQmhGYUtAGMCAAkACQmhGYUtAGMCAAAA.',
Ay='Ayame:BAAALgAECgEJAgABLgAECgkJIgAYAGIjAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMZAAYJJxUINgA+AQAZAAYJJxUINgA+AQAaAAQJvBYcRgDvAAABLgAECgcJEwAbAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8jAAIcAAgJHQW9KQDnAAAcAAgJHQW9KQDnAAAAAA==.Baelthas:BAAALgADCgcJDgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAACLgAFFH8MAAIFAAMJFiCySQAMAQAFAAMJFiCySQAMAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8xAAISAAkJNB2GAgCuAgASAAkJNB2GAgCuAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgYJCAAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8hAAIdAAgJaQzUfQBoAQAdAAgJaQzUfQBoAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8cAAIMAAkJrBLwKQAFAgAMAAkJrBLwKQAFAgAAAA==.Bighunt:BAAALgAECgUJCQABLgAECgkJHAAMAKwSAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8eAAIEAAgJmw1FJQBPAQAEAAgJmw1FJQBPAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8+AAINAAkJJiGNAwChAgANAAkJJiGNAwChAgAAAA==.Blegh:BAACLgAFFH8OAAMYAAUJaRicKQAiAQAYAAUJGhacKQAiAQAeAAEJlxUfDQBLAAAuAAQKfyMAAx4ACQnCHqcKADECAB4ABwnHHqcKADECABgABwl/GygfAMoBAAAA.Blueflu:BAAALgAECgUJCQAAAA==.Bluegrass:BAABLgAECn9fAAIOAAkJvyTQAABfAwAOAAkJvyTQAABfAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMfAAgJxAnuRABkAQAfAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgAFFAEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxgyPwADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAbAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8aAAIIAAUJcBC9DgAyAQAIAAUJcBC9DgAyAQAuAAQKfyAAAggACAmgF9s1AAYCAAgACAmgF9s1AAYCAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bulldogs:BAAALgADCgEJAQAAAA==.Bulova:BAAALgADCgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAACLgAFFH8IAAIJAAYJUxdkUAA9AQAJAAYJUxdkUAA9AQAuAAQKfxoAAgkACQmQJIUAAGADAAkACQmQJIUAAGADAAEuAAUUCAkbAAwAIxwA.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8tAAIFAAkJJxsUAQBaAgAFAAkJJxsUAQBaAgAAAA==.Caladelm:BAABLgAECn8hAAICAAkJEBV6AgAdAgACAAkJEBV6AgAdAgAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8rAAIdAAgJSRF3BwAoAQAdAAgJSRF3BwAoAQAAAA==.Carlarae:BAABLgAECn8WAAIJAAYJOQSr/QCwAAAJAAYJOQSr/QCwAAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih0CTgBDAQAJAAQJih0CTgBDAQAuAAQKfxwAAgkACQksIdUTAOMCAAkACQksIdUTAOMCAAAA.Cegeo:BAABLgAECn9IAAIUAAkJihnAAwBTAgAUAAkJihnAAwBTAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9mAAMDAAkJnSO4BgDzAgADAAkJnSO4BgDzAgALAAEJ0g5seAAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhN9lQCXAAAQAAIJjhN9lQCXAAAuAAQKfyMAAxAABwncH8oyAA0CABAABwncH8oyAA0CABcABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAwAAAA==.',
Ci='Ciennajewel:BAABLgAECn8aAAIgAAgJVRtNEwBBAgAgAAgJVRtNEwBBAgAAAA==.Cirdle:BAABLgAECn8/AAMIAAkJjBHfAwDQAQAIAAkJjBHfAwDQAQAHAAMJIwZ1KwBnAAAAAA==.Cirona:BAABLgAECn8eAAIMAAcJjR+IGgBxAgAMAAcJjR+IGgBxAgABLgAECgkJFQAVADgbAA==.',
Cl='Clausewitz:BAABLgAECn8aAAIcAAkJ7gq9HgA9AQAcAAkJ7gq9HgA9AQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8KAAMQAAMJNhshGADXAAAQAAMJNhshGADXAAAXAAEJngZUKgBCAAAuAAQKfyAAAhAACQk+HAkjAFQCABAACQk+HAkjAFQCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAbAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIWAAgJ7gILXQDNAAAWAAgJ7gILXQDNAAAAAA==.Creamtastic:BAAALgAECggJDAAAAA==.Creamyweamy:BAABLgAECn8gAAIgAAgJWRR4HwDIAQAgAAgJWRR4HwDIAQABLgAECggJDAAbAAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA0DqgArAQAJAAcJQA0DqgArAQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgUJDAAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8gAAMWAAkJWBWfHQD0AQAWAAkJWBWfHQD0AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8wAAIJAAgJAQ1CDAD5AAAJAAgJAQ1CDAD5AAAAAA==.',
Cu='Cuddly:BAABLgAFFH8pAAIjAAkJMyKaAAAXAwAjAAkJMyKaAAAXAwABLgAFFAkJPAAaABslAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAIJAgABLgAFFAkJOgAaAL8fAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yTVBQC3AgAjAAcJ6yTVBQC3AgAuAAQKf5UAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAbAAAAAA==.Daggonet:BAABLgAECn8eAAIdAAkJJyASDgD7AgAdAAkJJyASDgD7AgAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAWAAQJzAfqZwCjAAAAAA==.Darkcarnival:BAABLgAECn8xAAIQAAkJ8BodIABkAgAQAAkJ8BodIABkAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAUJCQAVALQXAA==.Darkknightx:BAACLgAFFH8KAAIDAAQJ1w2DJgAbAQADAAQJ1w2DJgAbAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAABLgAECn8WAAIdAAcJkhCIDADUAAAdAAcJkhCIDADUAAABLgAECggJGgAVANQOAA==.Darthraider:BAABLgAECn8dAAIdAAcJGxH3hgBWAQAdAAcJGxH3hgBWAQAAAA==.Dasnotgood:BAABLgAECn8ZAAMOAAcJuh3ZDgDHAQAOAAYJUB/ZDgDHAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQWAAgJxweBSwAHAQAWAAgJxweBSwAHAQAVAAEJowGnqgAhAAAiAAEJeAGKSAAdAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgUJCQAAAA==.',
De='Deathspeaker:BAAALgADCgEJAQABLgAECgkJKwAlAM4TAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8bAAIFAAkJKRW0NwDnAQAFAAkJKRW0NwDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAABLgAECn8cAAIUAAcJ3ROyDgBSAQAUAAcJ3ROyDgBSAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8sAAMgAAkJeRN4KACDAQAgAAkJeRN4KACDAQAZAAcJ3hDRMgBPAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8mAAIRAAkJIRUQHQDgAQARAAkJIRUQHQDgAQAAAA==.Desdemona:BAABLgAECn8rAAIBAAgJACFDCABUAgABAAgJACFDCABUAgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8KAAIIAAQJAA7JRwAeAQAIAAQJAA7JRwAeAQAuAAQKfxwAAwgACQl6GukcAHcCAAgACQl6GukcAHcCAAcAAglsA8FGABoAAAAA.',
Di='Dianimal:BAABLgAECn8lAAIRAAgJiwhQPwARAQARAAgJiwhQPwARAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEgAbAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAACLgAFFH8HAAMCAAMJFQvDmQCFAAACAAIJTQ/DmQCFAAAfAAIJDBeTDwBuAAAuAAQKfy4AAx8ACAmcJZMEAE8DAB8ACAmcJZMEAE8DAAIACAnvIisbAKECAAAA.',
Dk='Dklel:BAACLgAFFH8QAAIdAAUJ0CG7UQBOAQAdAAUJ0CG7UQBOAQAuAAQKf0AAAh0ACQl4Jj8HADwDAB0ACQl4Jj8HADwDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8LAAICAAQJHhDnGgDNAAACAAQJHhDnGgDNAAAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AbZKAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBKjcgCIAQACAAkJIBKjcgCIAQAAAA==.Dorow:BAAALgAECgEJAQAAAA==.',
Dr='Draaka:BAAALgAECgEJAQAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGwAFACkVAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xkgHwAhAgAjAAkJ6xkgHwAhAgAAAA==.Driftyshaman:BAABLgAECn8oAAIWAAgJ7wqfTQD/AAAWAAgJ7wqfTQD/AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn8kAAIdAAgJ7QmtEACqAAAdAAgJ7QmtEACqAAAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAABLgAECn8ZAAIIAAgJpBxFAgBIAgAIAAgJpBxFAgBIAgABLgAECggJIgAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8uAAIiAAkJtA35EACkAQAiAAkJtA35EACkAQAAAA==.',
Dy='Dyamï:BAABLgAECn8zAAIjAAkJkyCTCAASAwAjAAkJkyCTCAASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
['Dá']='Dánte:BAAALgAECgEJAQAAAA==.',
Eg='Eglosira:BAABLgAECn8dAAIJAAkJmAjgggByAQAJAAkJmAjgggByAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8hAAIWAAgJXArFRgAZAQAWAAgJXArFRgAZAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAABLgAECn8eAAIJAAcJSxEWEwCrAAAJAAcJSxEWEwCrAAAAAA==.Ellä:BAAALgAECgYJDAAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxOBPwAuAQAIAAQJGxOBPwAuAQAuAAQKfzgAAggACQmGItcJAAkDAAgACQmGItcJAAkDAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.Ether:BAAALgADCgQJBAAAAA==.',
Eu='Eukina:BAAALgAECgUJCgAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhH9QwCBAQAMAAcJvhH9QwCBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.Fellirane:BAAALgAECgMJAwAAAA==.Felrein:BAAALgADCgUJBQABLgAECgkJKQAcAPELAA==.',
Fi='Finegas:BAAALgAECgYJBgAAAA==.Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8hAAIiAAgJUBuhAABxAgAiAAgJUBuhAABxAgAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAFFAEJAQABLgAFFAgJIQAiAFAbAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAgJIQAiAFAbAA==.',
Fr='Fredrickk:BAABLgAECn8WAAMVAAcJdRTcPwCuAQAVAAcJdRTcPwCuAQAWAAQJWwqNegB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAFFAIJAwABLgAFFAUJEwAVAGUYAA==.Furryphase:BAACLgAFFH8TAAIVAAUJZRirJQBUAQAVAAUJZRirJQBUAQAuAAQKfyQAAxUACQnxHAwNALUCABUACQnxHAwNALUCABYABAlyCTR+AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAgJIQAiAFAbAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn85AAIVAAkJth6tEwCvAgAVAAkJth6tEwCvAgAAAA==.',
Go='Goatjira:BAAALgAECgUJCwAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Greygorypack:BAAALgADCgYJBQABLgAECgYJBgAbAAAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAmAGAgAA==.Gripisrdy:BAABLgAECn8xAAMdAAkJfSA0FQDIAgAdAAkJfSA0FQDIAgATAAMJgRjqNQC/AAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyJGAQD0AgAnAAkJkyJGAQD0AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAABLgAECn8aAAMVAAgJ1A5ySACMAQAVAAgJ1A5ySACMAQAWAAEJGAlcFQAnAAAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAgAAAA==.Haggrd:BAABLgAECn8fAAICAAgJJh8IJwBoAgACAAgJJh8IJwBoAgAAAA==.Hairyjolene:BAABLgAECn8jAAIIAAgJERNpSQDFAQAIAAgJERNpSQDFAQAAAA==.Halleberries:BAAALgAECgYJBgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJCAADADAWAA==.Handsome:BAAALgAFFAIJAwAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAABLgAFFH8KAAMdAAQJxRLwaAAnAQAdAAQJxRLwaAAnAQAmAAIJkQpbCQCMAAAAAA==.',
Hi='Highlander:BAAALgAECgEJAgAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxP2mgBAAAAFAAEJvxP2mgBAAAABLgAFFAkJOgAMAAciAA==.Hikarimonk:BAABLgAFFH8aAAIjAAcJmx35BADhAQAjAAcJmx35BADhAQABLgAFFAkJOgAMAAciAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAkJOgAMAAciAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgYJFAATAJEOAA==.Holyblimblam:BAAALgAECgYJEgAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMdAAgJBB69RQDxAQAdAAgJmB29RQDxAQATAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIZAAYJNA0RRwDzAAAZAAYJNA0RRwDzAAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Humper:BAAALgAECgMJBQAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.Huntley:BAAALgAECggJDwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECggJDQAAAA==.',
Ic='Icyjackets:BAABLgAECn8jAAMdAAgJtA9VdgB3AQAdAAgJtA9VdgB3AQATAAQJpAUkRwBxAAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAECgEJAgAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA88UwCpAQAIAAkJlA88UwCpAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRcmJgDHAQADAAgJBRcmJgDHAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn9GAAMMAAkJhxEAOgCtAQAMAAkJhxEAOgCtAQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAbAAAAAA==.Jel:BAAALgADCgEJAQAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAbAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIWAAYJfg7LWgDUAAAWAAYJfg7LWgDUAAAAAA==.Jessicà:BAAALgAECgQJBQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAwAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8mAAMVAAYJIhYRNgCrAQAVAAYJIhYRNgCrAQAWAAUJfBL/XADNAAAAAA==.Jiwà:BAABLgAFFH8HAAIVAAUJMgYxOAACAQAVAAUJMgYxOAACAQABLgAFFAUJEgAZAPkKAA==.Jiwâ:BAACLgAFFH8SAAIZAAUJ+Qo/HwD5AAAZAAUJ+Qo/HwD5AAAuAAQKfzkAAhkACQlGHhcNAIICABkACQlGHhcNAIICAAAA.Jiwå:BAAALgAECgYJCwAAAA==.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJDAAFABYgAA==.Kahless:BAAALgADCgQJCQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAcaRwApAQADAAkJMAcaRwApAQAAAA==.Kaliyah:BAAALgADCgcJCQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgAECgUJCAAAAA==.Kavorkyan:BAAALgAECgkJEgAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMmAAkJYCCbEgBPAQAdAAYJ7hpDXQDbAQAmAAcJyB+bEgBPAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9MAAIKAAkJKR45CACwAgAKAAkJKR45CACwAgAAAA==.',
Ki='Kiamara:BAABLgAECn8mAAIQAAgJigo1gAA4AQAQAAgJigo1gAA4AQAAAA==.Kinderlin:BAABLgAECn8jAAICAAYJtxQZrgAiAQACAAYJtxQZrgAiAQAAAA==.Kipo:BAAALgAECggJDwAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhbbNwC4AQAMAAcJbhbbNwC4AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgcJDwAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQeAAgJfRaSDwDiAQAeAAYJNhmSDwDiAQAYAAMJfRSEQgDYAAAlAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgcJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgUJCQAAAA==.Lista:BAABLgAECn8XAAMaAAkJqiD6AwBaAwAaAAkJqiD6AwBaAwAZAAEJEgrijgAsAAABLgAECgkJQAAPAGclAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyVwAQBPAwAGAAkJDiVwAQBPAwAIAAgJlybzDADrAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Locklobstah:BAAALgADCgIJAgAAAA==.Lola:BAAALgAECgkJAgAAAA==.Loralynn:BAACLgAFFH8SAAMMAAQJLgtoOQDIAAAMAAQJLgtoOQDIAAARAAEJggKvHAAqAAAuAAQKfxQAAgwABwn7FD04ALYBAAwABwn7FD04ALYBAAAA.Lorianne:BAACLgAFFH8HAAIVAAIJwRVzaQBtAAAVAAIJwRVzaQBtAAAuAAQKfygAAxUACAmvGGQpAOkBABUACAmvGGQpAOkBABYABQmxC7tWAOoAAAEuAAUUBAkSAAwALgsA.Lorri:BAAALgADCgQJBQABLgAFFAQJEgAMAC4LAA==.',
Lu='Lucianas:BAAALgAECgkJEwAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgkJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8jAAIIAAgJIh69GgCFAgAIAAgJIh69GgCFAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgIJAwAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh8MCwDoAgAjAAkJqh8MCwDoAgAAAA==.Madameuyen:BAAALgADCgUJBQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRzlHgCkAgAJAAkJHRzlHgCkAgABLgAFFAQJGAAGAJgbAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8WAAIgAAcJSBwDFAA3AgAgAAcJSBwDFAA3AgABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx39KwAtAgAIAAgJUx39KwAtAgAAAA==.Makthamonk:BAAALgAECgUJCAABLgAECggJGAAIAFMdAA==.Malholis:BAAALgAECgIJAgAAAA==.Malzeth:BAAALgAECgcJDAAAAA==.Marrilyn:BAAALgAFFAEJAwABLgAFFAcJCwAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn83AAIIAAkJzyCgCwD3AgAIAAkJzyCgCwD3AgAAAA==.Mate:BAAALgAECgQJBwABLgAECggJDwAbAAAAAA==.Mavuika:BAAALgAECgEJAQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJCAAAAA==.Melbeast:BAABLgAECn8gAAIIAAgJ2hs/LwAgAgAIAAgJ2hs/LwAgAgAAAA==.Melorea:BAAALgAECggJDAAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxATXADKAQAJAAkJNhATXADKAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMUAAgJpQkqFQACAQAUAAgJpQkqFQACAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJHwAAAA==.Mignon:BAAALgAECgMJBgABLgAECggJDwAbAAAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJEgAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn9IAAIBAAkJ6gStAwDIAAABAAkJ6gStAwDIAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgYJCwAAAA==.Moistwhispa:BAAALgAECgMJBQABLgAECgkJIAARAO4WAA==.Molfise:BAABLgAECn80AAMKAAkJciGeAAAuAgAKAAkJAiCeAAAuAgAPAAgJEBY+AgBFAQAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8/AAIgAAkJ4B+FBgAKAwAgAAkJ4B+FBgAKAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8hAAMLAAgJ8AXJOQDeAAALAAgJ8AXJOQDeAAAcAAMJGQHTCAA9AAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAbAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAfAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgYjtAAbAQAJAAgJBgYjtAAbAQAAAA==.',
Na='Nachtelf:BAABLgAECn9nAAIIAAkJSSKTBwAhAwAIAAkJSSKTBwAhAwAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAVAFYTAA==.Nannysham:BAABLgAECn8WAAIVAAkJVhMlLQADAgAVAAkJVhMlLQADAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn9VAAIJAAkJqyT8BQBTAwAJAAkJqyT8BQBTAwAAAA==.Nathel:BAAALgAECgcJBwAAAA==.Natherel:BAABLgAECn8YAAQLAAgJ2QSEQQDBAAALAAcJVgWEQQDBAAADAAUJ5gPofQB+AAAcAAEJ5QEkWwAgAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8YAAMlAAcJHxQfEwBhAQAlAAQJ2xwfEwBhAQAYAAYJRwnaFQCdAAAuAAQKfysAAxgACQkjHpgAAIsCABgACQkjHpgAAIsCACUABwk9F3wNAPgBAAEuAAUUCQk6ABoAvx8A.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRNSLQDxAQAMAAkJaRNSLQDxAQABLgAECggJIgAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgUJDQAAAA==.',
No='Nonphatmilk:BAAALgAECggJDwAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMdAAkJmxIqUQDQAQAdAAkJmxIqUQDQAQATAAEJGxJ6RQAyAAAAAA==.Novatron:BAAALgADCgUJBQAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR/xTAD1AQAJAAgJCR/xTAD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8dAAIMAAgJcgYaawDzAAAMAAgJcgYaawDzAAAAAA==.',
Om='Omee:BAABLgAECn8kAAMEAAkJVxrlDwAqAgAEAAkJVxrlDwAqAgAFAAYJ+Qs9jAAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w6PlwBKAQAJAAcJ4w6PlwBKAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Or:BAAALgAECgIJAgAAAA==.Orakio:BAABLgAFFH8HAAIdAAIJvQ+d4ACEAAAdAAIJvQ+d4ACEAAABLgAFFAUJGgAJAPkYAA==.Oralena:BAABLgAECn8jAAIIAAgJXggRdQBVAQAIAAgJXggRdQBVAQAAAA==.Orioncheats:BAABLgAECn9BAAIdAAkJzxuAKwBSAgAdAAkJzxuAKwBSAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAbAAAAAA==.',
Ox='Oxygën:BAABLgAECn8jAAIJAAgJWQl5mgBEAQAJAAgJWQl5mgBEAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8RAAIfAAQJgBt5HQAyAQAfAAQJgBt5HQAyAQAuAAQKfxwAAh8ACAnfIvUHAAwDAB8ACAnfIvUHAAwDAAEuAAUUBQkJABUAtBcA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAbAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9HAAMPAAkJQR+jCAC8AgAPAAkJQR+jCAC8AgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8UAAIDAAcJKxrxIgDbAQADAAcJKxrxIgDbAQAAAA==.Persephonee:BAAALgADCgEJAQAAAA==.',
Ph='Pharune:BAABLgAECn8xAAIkAAkJvRIDFgCjAQAkAAkJvRIDFgCjAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8vAAIJAAkJoBZXOQAzAgAJAAkJoBZXOQAzAgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJEAAWAIwcAA==.Picklebob:BAAALgAECggJCAABLgAFFAQJEAAWAIwcAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJEAAWAIwcAA==.Picklebosh:BAABLgAFFH8QAAIWAAQJjBwoGgBKAQAWAAQJjBwoGgBKAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Pointnshoot:BAAALgAECgEJAQABLgAFFAEJAQAbAAAAAA==.Ponky:BAABLgAECn8cAAIZAAkJKhHxKgB7AQAZAAkJKhHxKgB7AQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pothands:BAAALgADCgEJAQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8NAAIMAAMJghQzQgCpAAAMAAMJghQzQgCpAAABLgAFFAkJPAAaABslAA==.',
Pr='Preacha:BAAALgAECgYJCgABLgAECggJGgAVANQOAA==.Precious:BAACLgAFFH8gAAIaAAcJZxr6BADIAQAaAAcJZxr6BADIAQAuAAQKf0QABBoACQkjJIoDAGkDABoACQkjJIoDAGkDACAABglwDxs2AGQBABkABAkvE7pXALUAAAEuAAUUCQk6ABoAvx8A.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAcAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIeAAkJXgunEAABAQAeAAkJXgunEAABAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAACLgAFFH8IAAIDAAMJ3xLHDwC8AAADAAMJ3xLHDwC8AAAuAAQKfzoAAwMACAkVHiETAFkCAAMACAn4HSETAFkCAAsAAQmKFVZzADsAAAAA.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8iAAMPAAgJaRx0EgAtAgAPAAgJaRx0EgAtAgAjAAIJpw2loABYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJCQABLgAECgkJMwAMAIMgAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8tAAIgAAgJiRFUJgCTAQAgAAgJiRFUJgCTAQAAAA==.Raziel:BAAALgAECgQJBAAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Redranger:BAAALgADCgQJBAABLgAECgEJBAAbAAAAAA==.Rehum:BAABLgAECn8UAAICAAYJPghx9QDEAAACAAYJPghx9QDEAAAAAA==.Remagtrepxe:BAAALgAECgEJAQABLgAECggJKAAWAO8KAA==.Remniscence:BAAALgAECgEJAQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8uAAMiAAkJUBEDFQBtAQAiAAgJHRMDFQBtAQAVAAYJ3gfSjgC7AAAAAA==.Revèndreth:BAAALgAECgQJBQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgQJBAAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9LAAIZAAkJChVaGAAEAgAZAAkJChVaGAAEAgAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAABLgAECn8dAAIIAAYJ0hFoCQAyAQAIAAYJ0hFoCQAyAQAAAA==.Rockydemon:BAAALgAECgEJAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMdAAkJERs8QQD/AQAdAAkJ5xo8QQD/AQAmAAYJrhWxCABaAQAAAA==.Rockymage:BAAALgAECgIJAwAAAA==.Rockymonk:BAAALgAECgEJAQAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8uAAIeAAkJcxNOAADUAQAeAAkJcxNOAADUAQAAAA==.Roryn:BAACLgAFFH8KAAICAAMJWR8+HADGAAACAAMJWR8+HADGAAAuAAQKf2MAAgIACQlWJmkBAIIDAAIACQlWJmkBAIIDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8IAAIDAAMJfBmdLwDyAAADAAMJfBmdLwDyAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAgJNgAMACIiAA==.Rugiia:BAACLgAFFH82AAIMAAgJIiI8AgAnAwAMAAgJIiI8AgAnAwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJbsbAC4BAAAA.Rugiian:BAABLgAFFH8NAAIjAAUJ7xycHACOAQAjAAUJ7xycHACOAQABLgAFFAgJNgAMACIiAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQkZZQB0AQAQAAkJjQkZZQB0AQAAAA==.Ryuka:BAABLgAECn8jAAIkAAkJAgqgKAAUAQAkAAkJAgqgKAAUAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAbAAAAAA==.Samyria:BAABLgAECn8VAAIIAAYJ+Q49kAAfAQAIAAYJ+Q49kAAfAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8pAAQjAAkJFwwxQABtAQAjAAkJFwwxQABtAQAPAAcJlg4bPAAQAQAKAAEJogpUDAAgAAAAAA==.Saucy:BAABLgAECn8XAAMWAAgJeyB+DQCQAgAWAAgJeyB+DQCQAgAiAAEJAADDSgAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAbAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn86AAIgAAkJXRd3AgB/AQAgAAkJXRd3AgB/AQAAAA==.Selati:BAAALgADCgMJAwAAAA==.Seric:BAABLgAECn8pAAMcAAkJ8QtFHQBLAQAcAAkJ8QtFHQBLAQADAAQJugTShwBjAAAAAA==.Sesethi:BAAALgAECgQJBQABLgAECggJHgAQAAQfAA==.',
Sh='Shadowdancèr:BAABLgAECn8jAAMZAAkJShoEHgDVAQAZAAgJaxkEHgDVAQAaAAQJVxPzUgC2AAAAAA==.Shadowlocke:BAAALgAECgUJBQAAAA==.Shadowyisis:BAABLgAECn8VAAIZAAkJyBQWFwAQAgAZAAkJyBQWFwAQAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8YAAIGAAQJmBuXBAAIAQAGAAQJmBuXBAAIAQAuAAQKf0QAAwYACQnQI3ECACIDAAYACQm3I3ECACIDAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAYJGAABAIwNAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAcJGgAcANsWAA==.Skybox:BAAALgAECgUJCAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMaAAYJvhFAMAAeAQAaAAUJiBBAMAAeAQAgAAUJfQ/9UwCNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8MAAIJAAMJKgQTLQCfAAAJAAMJKgQTLQCfAAAuAAQKfzUAAgkACQmEE+FGAAYCAAkACQmEE+FGAAYCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQfAAkJRgzjLwCbAQAfAAkJRgzjLwCbAQABAAYJQBOeKgDFAAACAAEJYBbEhQE5AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAbAAAAAA==.Splashdaddy:BAACLgAFFH8aAAIVAAQJ6yRIBgB0AQAVAAQJ6yRIBgB0AQAuAAQKfyQAAhUACQlGJJkHADYDABUACQlGJJkHADYDAAEuAAUUAQkBABsAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgYJDAAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8wAAIVAAgJEwvXCADjAAAVAAgJEwvXCADjAAAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDQAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Summonme:BAABLgAECn8PAAMQAAkJtyFnAAAnAwAQAAkJtyFnAAAnAwAXAAEJkQ1nPwAzAAAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgUJDAAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn81AAIkAAkJ4SI9AAAcAwAkAAkJ4SI9AAAcAwAAAA==.',
Ta='Taea:BAABLgAECn8VAAIVAAkJOBsrAQCCAgAVAAkJOBsrAQCCAgAAAA==.Taeus:BAACLgAFFH8aAAIJAAUJ+Rg0EwA9AQAJAAUJ+Rg0EwA9AQAuAAQKfxkAAgkACQkiGeBeAB4CAAkACQkiGeBeAB4CAAAA.Taintedcure:BAAALgADCgkJEgAAAA==.Taintedkoma:BAAALgAECggJCwABLgAECggJIAAUAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Taliesien:BAAALgADCgYJBgABLgAECggJawAlAE4OAA==.Tamer:BAAALgAECgYJBgABLgAFFAcJHwAjAOskAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAABLgAECn8eAAIFAAcJAgjwCQDWAAAFAAcJAgjwCQDWAAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIcAAkJoiEKCAClAgAcAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AHm0wCjAAAIAAgJ/AHm0wCjAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgUJCgAAAA==.Temajin:BAABLgAECn8YAAMfAAYJrguwSgARAQAfAAYJrguwSgARAQACAAIJvwtzrQEqAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8dAAMlAAgJ+CHkBADTAgAlAAgJ+CHkBADTAgAYAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.Tesx:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA/ZlwANAQAQAAcJQgzZlwANAQAUAAEJChYqOgBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICIFEwC6AgAIAAgJICIFEwC6AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAABLgAECn8YAAIDAAgJTiPhDACdAgADAAgJTiPhDACdAgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8nAAICAAgJnBbNSwD/AQACAAgJnBbNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJDgABLgAECgkJIAAWAFQVAA==.Torrey:BAABLgAECn9EAAINAAkJRhH9CgCtAQANAAkJRhH9CgCtAQAAAA==.Totemsareus:BAABLgAFFH8JAAMVAAUJtBc4BgB2AQAVAAUJtBc4BgB2AQAWAAEJtgLXIwAwAAAAAA==.',
Tr='Tradd:BAACLgAFFH8QAAIaAAMJIx5oDADWAAAaAAMJIx5oDADWAAAuAAQKfyEAAhoACQmLHpsJANgCABoACQmLHpsJANgCAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJDAAFABYgAA==.Tristyana:BAABLgAECn9gAAIIAAkJkR4dEADPAgAIAAkJkR4dEADPAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn9AAAQPAAkJZyX0AgA4AwAPAAkJZyX0AgA4AwAjAAcJgxZEIwCZAQAKAAcJhBFqLQBRAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJQAAPAGclAA==.',
Ty='Tylurien:BAABLgAECn8rAAIfAAkJEyKqBwARAwAfAAkJEyKqBwARAwAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn88AAIUAAkJXRAfDwBNAQAUAAkJXRAfDwBNAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9rAAIlAAgJTg7jAQDmAAAlAAgJTg7jAQDmAAAAAA==.Valora:BAABLgAECn9mAAQaAAkJhh9bAAAfAwAaAAkJHR5bAAAfAwAZAAkJOBUhFAAuAgAgAAcJYx1+IQC2AQAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8bAAIMAAgJYQZGcADkAAAMAAgJYQZGcADkAAAAAA==.Vargen:BAABLgAECn8jAAIoAAgJYBikGADVAQAoAAgJYBikGADVAQAAAA==.Varonika:BAABLgAECn8WAAIUAAUJIwPwLQBhAAAUAAUJIwPwLQBhAAAAAA==.Vayla:BAABLgAECn8zAAIcAAkJ3hsaCQBlAgAcAAkJ3hsaCQBlAgAAAA==.',
Ve='Vee:BAAALgAECgUJDQABLgAECgkJGwAFACkVAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAdAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn85AAICAAkJlg2ZBgBbAQACAAkJlg2ZBgBbAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTANKbADvAAAMAAkJTANKbADvAAAAAA==.',
['Vä']='Vänhelsing:BAAALgAECgEJAQABLgAFFAMJBwACABULAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjww6iADIAAAJAAMJjww6iADIAAAuAAQKfyoAAgkACQk+HwMeAKgCAAkACQk+HwMeAKgCAAAA.Wargrimm:BAABLgAECn8wAAIWAAkJRx83CwCuAgAWAAkJRx83CwCuAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8WAAIfAAQJISaSEwCRAQAfAAQJISaSEwCRAQAuAAQKf3kAAx8ACQnQJhIAAPgDAB8ACQnQJhIAAPgDAAIACQktI98GADgDAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJIAARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJIAARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJIAARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whisperz:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whizpa:BAABLgAECn8gAAIRAAkJ7hatFwAQAgARAAkJ7hatFwAQAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJIAARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8ZAAIkAAkJThTsFgCbAQAkAAkJThTsFgCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJIAARAO4WAA==.Wilshammy:BAABLgAECn8UAAIVAAUJAQKcqgB0AAAVAAUJAQKcqgB0AAAAAA==.Wispy:BAABLgAECn8fAAIWAAcJAxOYNgBfAQAWAAcJAxOYNgBfAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAABLgAECn8WAAMIAAkJZRTRNAAKAgAIAAkJZRTRNAAKAgAGAAEJ6wbLZgAxAAAAAA==.Wrathbourne:BAAALgAECgYJEgABLgAECgkJFgAIAGUUAA==.Wrathchoi:BAABLgAECn8UAAMPAAYJlgwvBQC7AAAPAAYJlgwvBQC7AAAKAAQJigJEBgBoAAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJFgAIAGUUAA==.Wrathwraith:BAAALgAECgQJBAAAAA==.',
Xa='Xantchaa:BAAALgAECgEJAgABLgAECgkJHAAJAMQbAA==.Xaquandrel:BAACLgAFFH8IAAIDAAMJMBbIMQDoAAADAAMJMBbIMQDoAAAuAAQKfzUAAgMACQkgGtQSAFwCAAMACQkgGtQSAFwCAAAA.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8vAAMIAAkJux7jCwAJAQAGAAYJxB8GHwCkAQAIAAkJCx3jCwAJAQAAAA==.Xilo:BAABLgAECn8UAAIkAAgJXBzVAQB+AQAkAAgJXBzVAQB+AQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAbAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAMJBAAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgAECgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgMJAwAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8cAAIJAAkJxBujNABGAgAJAAkJxBujNABGAgAAAA==.Zenicks:BAAALgADCgYJDAABLgAECggJawAlAE4OAA==.Zeva:BAAALgADCgcJBgAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAbAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8VAAITAAgJ3B8aDgApAgATAAgJ3B8aDgApAgAAAA==.',
Zu='Zurazaee:BAABLgAECn8jAAIgAAgJMhkuEwBCAgAgAAgJMhkuEwBCAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAABLgAECn9mAAIkAAkJ/BybAABiAgAkAAkJ/BybAABiAgAAAA==.',
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
