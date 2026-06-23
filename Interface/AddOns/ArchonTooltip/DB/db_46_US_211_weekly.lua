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
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-06-21',data={Ac='Achooe:BAABLgAECn8vAAMBAAkJsQq5HAAvAQABAAkJsQq5HAAvAQACAAEJJgJE0QEXAAAAAA==.Acrylic:BAAALgAECgkJCQAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJBwAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJCAAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxtFCACaAgAGAAkJJxtFCACaAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBC8XADIAQAJAAkJQBC8XADIAQAAAA==.Agathorz:BAAALgAECgYJBwAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alanala:BAAALgADCgYJBgAAAA==.Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBmmMADtAAADAAMJgBmmMADtAAAuAAQKfzcAAwMACQnlJJoDAC8DAAMACQnlJJoDAC8DAAsABgn0EBUwAAgBAAAA.Allei:BAAALgAECgYJCQABLgAFFAQJEgAMAC4LAA==.Alyndrya:BAABLgAECn8sAAQEAAkJ5RfJEAAcAgAEAAkJcRfJEAAcAgAFAAYJvxKggQAcAQANAAEJkg3vNwAoAAAAAA==.Alyndrys:BAABLgAECn8jAAIOAAcJmhPnFgBeAQAOAAcJmhPnFgBeAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNRMwOgDeAQAFAAkJNRMwOgDeAQAAAA==.Amithralia:BAABLgAECn8wAAIMAAkJmB/BCQAeAwAMAAkJmB/BCQAeAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SInHQDFAQAPAAYJ0SInHQDFAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8YAAIQAAgJAxe6QgDTAQAQAAgJAxe6QgDTAQAAAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAkJNgAMAH0gAA==.Aokuma:BAACLgAFFH82AAIMAAkJfSAZAQBtAwAMAAkJfSAZAQBtAwAuAAQKfywAAwwACQlPJI8GACIDAAwACQlPJI8GACIDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8pAAISAAgJvA5jCgCRAQASAAgJvA5jCgCRAQAAAA==.',
Aq='Aquaten:BAABLgAECn8jAAIGAAgJ9xVkFQD4AQAGAAgJ9xVkFQD4AQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRCcawDxAAAMAAgJJg6cawDxAAARAAYJIBZvTwDPAAAAAA==.Arcafrost:BAAALgAECgkJCgAAAA==.Arceus:BAABLgAECn8UAAITAAYJkQ4TAwCFAAATAAYJkQ4TAwCFAAAAAA==.Archaon:BAABLgAECn8tAAMQAAkJRhMWBADTAAAQAAkJRhMWBADTAAAUAAEJAADeUgAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFgAVAHUUAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9GAAMVAAkJpib/AQBrAwAVAAkJpib/AQBrAwAWAAYJIyW/HwDkAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEwAAAA==.Asmódeus:BAABLgAECn8cAAQXAAgJoQ73DQBTAQAXAAYJWw73DQBTAQAQAAgJCgrHfgA7AQAUAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgAECgEJAQAAAA==.Atorbarak:BAAALgAECgUJBQABLgAECggJJQAHAB4QAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAACLgAFFH8HAAIJAAIJzgnTEwCHAAAJAAIJzgnTEwCHAAAuAAQKfy8AAgkACQmhGYgtAGMCAAkACQmhGYgtAGMCAAAA.',
Ay='Ayame:BAAALgAECgEJAQABLgAECgkJIgAYAGIjAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMZAAYJJxUGNgA+AQAZAAYJJxUGNgA+AQAaAAQJvBYZRgDvAAABLgAECgcJEwAbAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8jAAIcAAgJHQW9KQDnAAAcAAgJHQW9KQDnAAAAAA==.Baelthas:BAAALgADCgcJDgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAACLgAFFH8MAAIFAAMJFiC0SQAMAQAFAAMJFiC0SQAMAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8xAAISAAkJNB2GAgCuAgASAAkJNB2GAgCuAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgYJCAAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8hAAIdAAgJaQzTfQBoAQAdAAgJaQzTfQBoAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8cAAIMAAkJrBLyKQAFAgAMAAkJrBLyKQAFAgAAAA==.Bighunt:BAAALgAECgUJCQABLgAECgkJHAAMAKwSAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8eAAIEAAgJmw1BJQBPAQAEAAgJmw1BJQBPAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8+AAINAAkJJiGNAwChAgANAAkJJiGNAwChAgAAAA==.Blegh:BAACLgAFFH8OAAMYAAUJaRibKQAiAQAYAAUJGhabKQAiAQAeAAEJlxUgDQBLAAAuAAQKfyMAAx4ACQnCHqcKADECAB4ABwnHHqcKADECABgABwl/GygfAMoBAAAA.Blueflu:BAAALgAECgUJCQAAAA==.Bluegrass:BAABLgAECn9WAAIOAAkJvyTQAABfAwAOAAkJvyTQAABfAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMfAAgJxAnuRABkAQAfAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgAFFAEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxguPwADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAbAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8VAAIIAAQJrg+LRAAkAQAIAAQJrg+LRAAkAQAuAAQKfx4AAggACAmgF9w1AAYCAAgACAmgF9w1AAYCAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bulldogs:BAAALgADCgEJAQAAAA==.Bulova:BAAALgADCgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8IAAIJAAYJUxdfUAA9AQAJAAYJUxdfUAA9AQABLgAFFAgJGgAMACMcAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8kAAIFAAkJIxmtJwAsAgAFAAkJIxmtJwAsAgAAAA==.Caladelm:BAABLgAECn8aAAICAAgJVxEaCACyAAACAAgJVxEaCACyAAAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8mAAIdAAgJTQ68dgB2AQAdAAgJTQ68dgB2AQAAAA==.Carlarae:BAABLgAECn8WAAIJAAYJOQSm/QCwAAAJAAYJOQSm/QCwAAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih3/TQBDAQAJAAQJih3/TQBDAQAuAAQKfxwAAgkACQksIdcTAOMCAAkACQksIdcTAOMCAAAA.Cegeo:BAABLgAECn9IAAIUAAkJihnAAwBTAgAUAAkJihnAAwBTAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9dAAMDAAkJnSO4BgDzAgADAAkJnSO4BgDzAgALAAEJ0g5seAAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhN8lQCXAAAQAAIJjhN8lQCXAAAuAAQKfyMAAxAABwncH8kyAA0CABAABwncH8kyAA0CABcABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAwAAAA==.',
Ci='Ciennajewel:BAABLgAECn8ZAAIgAAgJdRpNEwBBAgAgAAgJdRpNEwBBAgAAAA==.Cirdle:BAABLgAECn82AAMIAAkJjhCZAgCPAQAIAAkJjhCZAgCPAQAHAAMJIwZ1KwBnAAAAAA==.Cirona:BAABLgAECn8eAAIMAAcJjR+JGgBxAgAMAAcJjR+JGgBxAgABLgAECgkJDQAbAAAAAA==.',
Cl='Clausewitz:BAABLgAECn8aAAIcAAkJ7gq9HgA9AQAcAAkJ7gq9HgA9AQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8JAAMQAAMJNhseYwABAQAQAAMJNhseYwABAQAXAAEJngZSKgBCAAAuAAQKfyAAAhAACQk+HAkjAFQCABAACQk+HAkjAFQCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAbAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIWAAgJ7gIGXQDNAAAWAAgJ7gIGXQDNAAAAAA==.Creamtastic:BAAALgAECggJCwAAAA==.Creamyweamy:BAABLgAECn8gAAIgAAgJWRR2HwDIAQAgAAgJWRR2HwDIAQABLgAECggJCwAbAAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA3+qQArAQAJAAcJQA3+qQArAQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgUJDAAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8gAAMWAAkJWBWfHQD0AQAWAAkJWBWfHQD0AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8rAAIJAAgJqwhWmwBDAQAJAAgJqwhWmwBDAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8iAAIjAAcJSSN3BQC/AgAjAAcJSSN3BQC/AgABLgAFFAkJOgAaAOsjAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAEJAQABLgAFFAkJNAAaACYeAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yTWBQC3AgAjAAcJ6yTWBQC3AgAuAAQKf5UAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAbAAAAAA==.Daggonet:BAABLgAECn8eAAIdAAkJJyARDgD7AgAdAAkJJyARDgD7AgAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAWAAQJzAfqZwCjAAAAAA==.Darkcarnival:BAABLgAECn8xAAIQAAkJ8BodIABkAgAQAAkJ8BodIABkAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAQJEQAfAIAbAA==.Darkknightx:BAACLgAFFH8KAAIDAAQJ1w2BJgAbAQADAAQJ1w2BJgAbAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAABLgAECn8UAAIdAAcJkhARigBQAQAdAAcJkhARigBQAQABLgAECggJGQAVANQOAA==.Darthraider:BAABLgAECn8dAAIdAAcJGxH2hgBWAQAdAAcJGxH2hgBWAQAAAA==.Dasnotgood:BAABLgAECn8ZAAMOAAcJuh3YDgDHAQAOAAYJUB/YDgDHAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQWAAgJxwd+SwAHAQAWAAgJxwd+SwAHAQAVAAEJowGnqgAhAAAiAAEJeAGJSAAdAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgUJCQAAAA==.',
De='Deathspeaker:BAAALgADCgEJAQABLgAECggJJwAlAJYTAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8bAAIFAAkJKRWzNwDnAQAFAAkJKRWzNwDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAABLgAECn8bAAIUAAcJ3ROyDgBSAQAUAAcJ3ROyDgBSAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8rAAMgAAgJ/hN0KACDAQAgAAgJ/hN0KACDAQAZAAcJ3hDPMgBPAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8mAAIRAAkJIRUOHQDgAQARAAkJIRUOHQDgAQAAAA==.Desdemona:BAABLgAECn8qAAIBAAgJACFDCABUAgABAAgJACFDCABUAgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8KAAIIAAQJAA7KRwAeAQAIAAQJAA7KRwAeAQAuAAQKfxwAAwgACQl6GuscAHcCAAgACQl6GuscAHcCAAcAAglsA8BGABoAAAAA.',
Di='Dianimal:BAABLgAECn8lAAIRAAgJiwhOPwARAQARAAgJiwhOPwARAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEgAbAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAACLgAFFH8FAAMCAAMJAgvAmQCFAAACAAIJTQ/AmQCFAAAfAAEJlSU2PQBsAAAuAAQKfy4AAx8ACAmcJZQEAE8DAB8ACAmcJZQEAE8DAAIACAnvIiobAKECAAAA.',
Dk='Dklel:BAACLgAFFH8QAAIdAAUJ0CG5UQBOAQAdAAUJ0CG5UQBOAQAuAAQKf0AAAh0ACQl4Jj8HADwDAB0ACQl4Jj8HADwDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8LAAICAAQJHhBoCQDVAAACAAQJHhBoCQDVAAAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AbdKAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBKkcgCIAQACAAkJIBKkcgCIAQAAAA==.Dorow:BAAALgAECgEJAQAAAA==.',
Dr='Draaka:BAAALgAECgEJAQAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGwAFACkVAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xkhHwAhAgAjAAkJ6xkhHwAhAgAAAA==.Driftyshaman:BAABLgAECn8nAAIWAAcJMgubTQD/AAAWAAcJMgubTQD/AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn8fAAIdAAgJ8AgylAA/AQAdAAgJ8AgylAA/AQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAABLgAECn8UAAIIAAgJ+RoUAQBEAgAIAAgJ+RoUAQBEAgABLgAECggJIgAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8uAAIiAAkJtA36EACkAQAiAAkJtA36EACkAQAAAA==.',
Dy='Dyamï:BAABLgAECn8zAAIjAAkJkyCUCAASAwAjAAkJkyCUCAASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
['Dá']='Dánte:BAAALgAECgEJAQAAAA==.',
Eg='Eglosira:BAABLgAECn8cAAIJAAkJ6gffggByAQAJAAkJ6gffggByAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8hAAIWAAgJXArCRgAZAQAWAAgJXArCRgAZAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAABLgAECn8ZAAIJAAcJBQ8cnwA8AQAJAAcJBQ8cnwA8AQAAAA==.Ellä:BAAALgAECgYJCQAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxOBPwAuAQAIAAQJGxOBPwAuAQAuAAQKfzgAAggACQmGItkJAAkDAAgACQmGItkJAAkDAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.Ether:BAAALgADCgMJAwAAAA==.',
Eu='Eukina:BAAALgAECgUJCgAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhEBRACBAQAMAAcJvhEBRACBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.Felrein:BAAALgADCgUJBQABLgAECgkJKQAcAPELAA==.',
Fi='Finegas:BAAALgAECgYJBgAAAA==.Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8hAAIiAAgJUBuhAABxAgAiAAgJUBuhAABxAgAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAFFAEJAQABLgAFFAgJIQAiAFAbAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAgJIQAiAFAbAA==.',
Fr='Fredrickk:BAABLgAECn8WAAMVAAcJdRTZPwCuAQAVAAcJdRTZPwCuAQAWAAQJWwqJegB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAFFAIJAgABLgAFFAUJEwAVAGUYAA==.Furryphase:BAACLgAFFH8TAAIVAAUJZRijJQBUAQAVAAUJZRijJQBUAQAuAAQKfyQAAxUACQnxHAwNALUCABUACQnxHAwNALUCABYABAlyCTJ+AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAgJIQAiAFAbAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn85AAIVAAkJth6tEwCvAgAVAAkJth6tEwCvAgAAAA==.',
Go='Goatjira:BAAALgAECgUJCwAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Greygorypack:BAAALgADCgYJBQABLgAECgYJBgAbAAAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAmAGAgAA==.Gripisrdy:BAABLgAECn8xAAMdAAkJfSAyFQDIAgAdAAkJfSAyFQDIAgATAAMJgRjnNQC/AAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyJGAQD0AgAnAAkJkyJGAQD0AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAABLgAECn8ZAAIVAAgJ1A5vSACMAQAVAAgJ1A5vSACMAQAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAgAAAA==.Haggrd:BAABLgAECn8eAAICAAgJJh8IJwBoAgACAAgJJh8IJwBoAgAAAA==.Hairyjolene:BAABLgAECn8jAAIIAAgJERNoSQDFAQAIAAgJERNoSQDFAQAAAA==.Halleberries:BAAALgAECgYJBgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJCAADADAWAA==.Handsome:BAAALgAFFAIJAwAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAABLgAFFH8IAAIdAAQJxRLvaAAnAQAdAAQJxRLvaAAnAQAAAA==.',
Hi='Highlander:BAAALgAECgEJAgAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxPzmgBAAAAFAAEJvxPzmgBAAAABLgAFFAkJNgAMAH0gAA==.Hikarimonk:BAABLgAFFH8VAAIjAAcJBBFaFgDMAQAjAAcJBBFaFgDMAQABLgAFFAkJNgAMAH0gAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAkJNgAMAH0gAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgYJFAATAJEOAA==.Holyblimblam:BAAALgAECgYJEgAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMdAAgJBB66RQDxAQAdAAgJmB26RQDxAQATAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIZAAYJNA0PRwDzAAAZAAYJNA0PRwDzAAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Humper:BAAALgAECgMJAwAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.Huntley:BAAALgAECgcJDQAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icyjackets:BAABLgAECn8jAAMdAAgJtA9UdgB3AQAdAAgJtA9UdgB3AQATAAQJpAUhRwBxAAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAECgEJAgAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA8/UwCpAQAIAAkJlA8/UwCpAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRclJgDHAQADAAgJBRclJgDHAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn9CAAMMAAgJ0xADOgCtAQAMAAgJ0xADOgCtAQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAbAAAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAbAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIWAAYJfg7HWgDUAAAWAAYJfg7HWgDUAAAAAA==.Jessicà:BAAALgAECgQJBQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAwAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8lAAMVAAYJIhYRNgCrAQAVAAYJIhYRNgCrAQAWAAUJfBL6XADNAAAAAA==.Jiwà:BAABLgAFFH8HAAIVAAUJMgZQOAABAQAVAAUJMgZQOAABAQABLgAFFAUJEgAZAPkKAA==.Jiwâ:BAACLgAFFH8SAAIZAAUJ+Qo8HwD5AAAZAAUJ+Qo8HwD5AAAuAAQKfzkAAhkACQlGHhgNAIICABkACQlGHhgNAIICAAAA.Jiwå:BAAALgAECgYJCwAAAA==.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJDAAFABYgAA==.Kahless:BAAALgADCgQJCQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAcZRwApAQADAAkJMAcZRwApAQAAAA==.Kaliyah:BAAALgADCgcJCQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgAECgQJBAAAAA==.Kavorkyan:BAAALgAECggJDgAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMmAAkJYCCbEgBPAQAdAAYJ7hpDXQDbAQAmAAcJyB+bEgBPAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9MAAIKAAkJKR44CACwAgAKAAkJKR44CACwAgAAAA==.',
Ki='Kiamara:BAABLgAECn8iAAIQAAgJ9QgzgAA4AQAQAAgJ9QgzgAA4AQAAAA==.Kinderlin:BAABLgAECn8jAAICAAYJtxQXrgAiAQACAAYJtxQXrgAiAQAAAA==.Kipo:BAAALgAECggJDwAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhbeNwC4AQAMAAcJbhbeNwC4AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQeAAgJfRaSDwDiAQAeAAYJNhmSDwDiAQAYAAMJfRSEQgDYAAAlAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgcJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgUJCQAAAA==.Lista:BAABLgAECn8XAAMaAAkJqiD6AwBaAwAaAAkJqiD6AwBaAwAZAAEJEgrdjgAsAAABLgAECgkJQAAPAGclAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyVwAQBPAwAGAAkJDiVwAQBPAwAIAAgJlyb1DADrAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Locklobstah:BAAALgADCgIJAgAAAA==.Loralynn:BAACLgAFFH8SAAMMAAQJLgtoOQDIAAAMAAQJLgtoOQDIAAARAAEJggLCDAAsAAAuAAQKfxQAAgwABwn7FEA4ALYBAAwABwn7FEA4ALYBAAAA.Lorianne:BAACLgAFFH8HAAIVAAIJwRVzaQBtAAAVAAIJwRVzaQBtAAAuAAQKfygAAxUACAmvGGQpAOkBABUACAmvGGQpAOkBABYABQmxC7tWAOoAAAEuAAUUBAkSAAwALgsA.Lorri:BAAALgADCgQJBQABLgAFFAQJEgAMAC4LAA==.',
Lu='Lucianas:BAAALgAECgkJEwAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgkJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8jAAIIAAgJIh6/GgCFAgAIAAgJIh6/GgCFAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgIJAwAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh8OCwDoAgAjAAkJqh8OCwDoAgAAAA==.Madameuyen:BAAALgADCgUJBQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRzmHgCkAgAJAAkJHRzmHgCkAgABLgAFFAQJFgAGAB8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8WAAIgAAcJSBwDFAA3AgAgAAcJSBwDFAA3AgABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx3/KwAtAgAIAAgJUx3/KwAtAgAAAA==.Makthamonk:BAAALgAECgUJCAABLgAECggJGAAIAFMdAA==.Malzeth:BAAALgAECgYJBgAAAA==.Marrilyn:BAAALgAFFAEJAwABLgAFFAcJCwAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn83AAIIAAkJzyCiCwD3AgAIAAkJzyCiCwD3AgAAAA==.Mate:BAAALgAECgQJBwABLgAECgcJDQAbAAAAAA==.Mavuika:BAAALgAECgEJAQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJCAAAAA==.Melbeast:BAABLgAECn8fAAIIAAgJ2htBLwAgAgAIAAgJ2htBLwAgAgAAAA==.Melorea:BAAALgAECgUJBwAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxAVXADKAQAJAAkJNhAVXADKAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMUAAgJpQkpFQACAQAUAAgJpQkpFQACAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJHwAAAA==.Mignon:BAAALgAECgMJBgABLgAECgcJDQAbAAAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJEgAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn9EAAIBAAkJ6ARqAgCQAAABAAkJ6ARqAgCQAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgUJCQAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJIAARAO4WAA==.Molfise:BAABLgAECn8sAAMKAAkJAiBuDABvAgAKAAkJAiBuDABvAgAPAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8/AAIgAAkJ4B+FBgAKAwAgAAkJ4B+FBgAKAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8gAAMLAAgJ8AXIOQDeAAALAAgJ8AXIOQDeAAAcAAMJEQFrBAA7AAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAbAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAfAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgYetAAbAQAJAAgJBgYetAAbAQAAAA==.',
Na='Nachtelf:BAABLgAECn9eAAIIAAkJFSKUBwAhAwAIAAkJFSKUBwAhAwAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAVAFYTAA==.Nannysham:BAABLgAECn8WAAIVAAkJVhMkLQADAgAVAAkJVhMkLQADAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn9VAAIJAAkJqyT8BQBTAwAJAAkJqyT8BQBTAwAAAA==.Nathel:BAAALgAECgcJBwAAAA==.Natherel:BAABLgAECn8YAAQLAAgJ2QSEQQDBAAALAAcJVgWEQQDBAAADAAUJ5gPnfQB+AAAcAAEJ5QEgWwAgAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8WAAMlAAUJfhgcEwBhAQAlAAQJ2xwcEwBhAQAYAAQJmAtxRgCuAAAuAAQKfyAAAyUACAkzFX0NAPgBACUABwk9F30NAPgBABgABwm5GKMoAKABAAEuAAUUCQk0ABoAJh4A.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRNVLQDxAQAMAAkJaRNVLQDxAQABLgAECggJIgAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgUJDQAAAA==.',
No='Nonphatmilk:BAAALgAECggJDwAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMdAAkJmxImUQDQAQAdAAkJmxImUQDQAQATAAEJGxJ6RQAyAAAAAA==.Novatron:BAAALgADCgUJBQAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR/0TAD1AQAJAAgJCR/0TAD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8dAAIMAAgJcgYdawDzAAAMAAgJcgYdawDzAAAAAA==.',
Om='Omee:BAABLgAECn8jAAMEAAkJVxrnDwAqAgAEAAkJVxrnDwAqAgAFAAYJ+Qs8jAAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w6MlwBKAQAJAAcJ4w6MlwBKAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAABLgAFFH8GAAIdAAIJvQ+c4ACEAAAdAAIJvQ+c4ACEAAABLgAFFAUJGAAJAFAYAA==.Oralena:BAABLgAECn8jAAIIAAgJXggUdQBVAQAIAAgJXggUdQBVAQAAAA==.Orioncheats:BAABLgAECn9BAAIdAAkJzxt/KwBSAgAdAAkJzxt/KwBSAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAbAAAAAA==.',
Ox='Oxygën:BAABLgAECn8dAAIJAAgJaAVPuAAVAQAJAAgJaAVPuAAVAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8RAAIfAAQJgBt6HQAyAQAfAAQJgBt6HQAyAQAuAAQKfxwAAh8ACAnfIvUHAAwDAB8ACAnfIvUHAAwDAAAA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAbAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9HAAMPAAkJQR+jCAC8AgAPAAkJQR+jCAC8AgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8UAAIDAAcJKxrvIgDbAQADAAcJKxrvIgDbAQAAAA==.',
Ph='Pharune:BAABLgAECn8xAAIkAAkJvRIDFgCjAQAkAAkJvRIDFgCjAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8uAAIJAAkJoBZZOQAzAgAJAAkJoBZZOQAzAgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJDwAWAIwcAA==.Picklebob:BAAALgAECggJCAABLgAFFAQJDwAWAIwcAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJDwAWAIwcAA==.Picklebosh:BAABLgAFFH8PAAIWAAQJjBwoGgBKAQAWAAQJjBwoGgBKAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Pointnshoot:BAAALgADCgEJAQABLgAFFAEJAQAbAAAAAA==.Ponky:BAABLgAECn8cAAIZAAkJKhHwKgB7AQAZAAkJKhHwKgB7AQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8NAAIMAAMJghQ1QgCpAAAMAAMJghQ1QgCpAAABLgAFFAkJOgAaAOsjAA==.',
Pr='Preacha:BAAALgAECgUJBQABLgAECggJGQAVANQOAA==.Precious:BAACLgAFFH8gAAIaAAcJZxryAQDPAQAaAAcJZxryAQDPAQAuAAQKf0QABBoACQkjJIsDAGkDABoACQkjJIsDAGkDACAABglwDxs2AGQBABkABAkvE7pXALUAAAEuAAUUCQk0ABoAJh4A.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAcAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIeAAkJXgunEAABAQAeAAkJXgunEAABAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAACLgAFFH8FAAIDAAMJ1wwyOADSAAADAAMJ1wwyOADSAAAuAAQKfzoAAwMACAkVHiETAFkCAAMACAn4HSETAFkCAAsAAQmKFVVzADsAAAAA.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8iAAMPAAgJaRx0EgAtAgAPAAgJaRx0EgAtAgAjAAIJpw2hoABYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJCAAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8sAAIgAAgJZRBRJgCTAQAgAAgJZRBRJgCTAQAAAA==.Raziel:BAAALgADCgkJCQAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Redranger:BAAALgADCgQJBAABLgAECgEJAQAbAAAAAA==.Rehum:BAABLgAECn8UAAICAAYJPght9QDEAAACAAYJPght9QDEAAAAAA==.Remagtrepxe:BAAALgAECgEJAQABLgAECgcJJwAWADILAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8uAAMiAAkJUBEDFQBtAQAiAAgJHRMDFQBtAQAVAAYJ3gfOjgC7AAAAAA==.Revèndreth:BAAALgAECgQJBQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgQJBAAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9LAAIZAAkJChVaGAAEAgAZAAkJChVaGAAEAgAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAABLgAECn8XAAIIAAYJlwshcAAXAQAIAAYJlwshcAAXAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMdAAkJERs5QQD/AQAdAAkJ5xo5QQD/AQAmAAYJrhWxCABaAQAAAA==.Rockymage:BAAALgAECgIJAgAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8nAAIeAAkJFRGVCgB0AQAeAAkJFRGVCgB0AQAAAA==.Roryn:BAACLgAFFH8IAAICAAMJoRS1bQDVAAACAAMJoRS1bQDVAAAuAAQKf1oAAgIACQlWJmkBAIIDAAIACQlWJmkBAIIDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8IAAIDAAMJfBmbLwDyAAADAAMJfBmbLwDyAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAgJMwAMACIiAA==.Rugiia:BAACLgAFFH8zAAIMAAgJIiI8AgAnAwAMAAgJIiI8AgAnAwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJbobAC4BAAAA.Rugiian:BAABLgAFFH8NAAIjAAUJ7xxVBQAGAQAjAAUJ7xxVBQAGAQABLgAFFAgJMwAMACIiAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQkZZQB0AQAQAAkJjQkZZQB0AQAAAA==.Ryuka:BAABLgAECn8jAAIkAAkJAgqhKAAUAQAkAAkJAgqhKAAUAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAbAAAAAA==.Samyria:BAABLgAECn8VAAIIAAYJ+Q47kAAfAQAIAAYJ+Q47kAAfAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8oAAQjAAkJFwwzQABtAQAjAAkJFwwzQABtAQAPAAcJlg4cPAAQAQAKAAEJgAH5mQAYAAAAAA==.Saucy:BAABLgAECn8XAAMWAAgJeyB/DQCQAgAWAAgJeyB/DQCQAgAiAAEJAADBSgAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAbAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8zAAIgAAkJaBW/FAAvAgAgAAkJaBW/FAAvAgAAAA==.Selati:BAAALgADCgMJAwAAAA==.Seric:BAABLgAECn8pAAMcAAkJ8QtGHQBLAQAcAAkJ8QtGHQBLAQADAAQJugTOhwBjAAAAAA==.Sesethi:BAAALgAECgQJBAABLgAECggJHgAQAAQfAA==.',
Sh='Shadowdancèr:BAABLgAECn8jAAMZAAkJShoEHgDVAQAZAAgJaxkEHgDVAQAaAAQJVxPyUgC2AAAAAA==.Shadowlocke:BAAALgAECgUJBQAAAA==.Shadowyisis:BAABLgAECn8VAAIZAAkJyBQWFwAQAgAZAAkJyBQWFwAQAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8WAAIGAAQJHxtFAgDwAAAGAAQJHxtFAgDwAAAuAAQKf0QAAwYACQnQI3ICACIDAAYACQm3I3ICACIDAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAUJFwABAIgPAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAYJFwAcAL4WAA==.Skybox:BAAALgAECgUJCAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMaAAYJvhFAMAAeAQAaAAUJiBBAMAAeAQAgAAUJfQ/5UwCNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8LAAIJAAMJJAQFkwCvAAAJAAMJJAQFkwCvAAAuAAQKfzUAAgkACQmEE+NGAAYCAAkACQmEE+NGAAYCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQfAAkJRgziLwCbAQAfAAkJRgziLwCbAQABAAYJQBOgKgDFAAACAAEJYBbAhQE5AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAbAAAAAA==.Splashdaddy:BAACLgAFFH8XAAIVAAQJgCTfGgCSAQAVAAQJgCTfGgCSAQAuAAQKfyQAAhUACQlGJJoHADYDABUACQlGJJoHADYDAAEuAAUUAQkBABsAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgYJDAAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8rAAIVAAgJHggVZwAmAQAVAAgJHggVZwAmAQAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDQAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Summonme:BAAALgAECgcJCwAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgUJCwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8tAAIkAAkJxCEKBwCHAgAkAAkJxCEKBwCHAgAAAA==.',
Ta='Taea:BAAALgAECgkJDQAAAA==.Taeus:BAACLgAFFH8YAAIJAAUJUBgFCwD4AAAJAAUJUBgFCwD4AAAuAAQKfxkAAgkACQkiGeBeAB4CAAkACQkiGeBeAB4CAAAA.Taintedcure:BAAALgADCgkJEgAAAA==.Taintedkoma:BAAALgAECggJCwABLgAECggJIAAUAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAABLgAECn8eAAIFAAcJAghIBADYAAAFAAcJAghIBADYAAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIcAAkJoiEKCAClAgAcAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AHf0wCjAAAIAAgJ/AHf0wCjAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgUJCgAAAA==.Temajin:BAABLgAECn8YAAMfAAYJrguwSgARAQAfAAYJrguwSgARAQACAAIJvwtvrQEqAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8dAAMlAAgJ+CHkBADTAgAlAAgJ+CHkBADTAgAYAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.Tesx:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA/YlwANAQAQAAcJQgzYlwANAQAUAAEJChYpOgBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICIHEwC6AgAIAAgJICIHEwC6AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAABLgAECn8XAAIDAAgJTiPgDACeAgADAAgJTiPgDACeAgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8mAAICAAgJVhXNSwD/AQACAAgJVhXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJDgABLgAECgkJIAAWAFQVAA==.Torrey:BAABLgAECn9EAAINAAkJRhH9CgCtAQANAAkJRhH9CgCtAQAAAA==.Totemsareus:BAAALgAFFAIJBAABLgAFFAQJEQAfAIAbAA==.',
Tr='Tradd:BAACLgAFFH8PAAIaAAMJIx4wKQAEAQAaAAMJIx4wKQAEAQAuAAQKfyEAAhoACQmLHpsJANgCABoACQmLHpsJANgCAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJDAAFABYgAA==.Tristyana:BAABLgAECn9aAAIIAAkJdB4fEADPAgAIAAkJdB4fEADPAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn9AAAQPAAkJZyX0AgA4AwAPAAkJZyX0AgA4AwAjAAcJgxZEIwCZAQAKAAcJhBFnLQBRAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJQAAPAGclAA==.',
Ty='Tylurien:BAABLgAECn8rAAIfAAkJEyKqBwARAwAfAAkJEyKqBwARAwAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn88AAIUAAkJXRAgDwBNAQAUAAkJXRAgDwBNAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9XAAIlAAgJ9AwDFgBtAQAlAAgJ9AwDFgBtAQAAAA==.Valora:BAABLgAECn9dAAQaAAkJth4RDQCcAgAaAAkJTR0RDQCcAgAZAAkJOBUiFAAuAgAgAAcJYx17IQC2AQAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8bAAIMAAgJYQZJcADkAAAMAAgJYQZJcADkAAAAAA==.Vargen:BAABLgAECn8iAAIoAAgJYBikGADVAQAoAAgJYBikGADVAQAAAA==.Varonika:BAABLgAECn8WAAIUAAUJIwPvLQBhAAAUAAUJIwPvLQBhAAAAAA==.Vayla:BAABLgAECn8zAAIcAAkJ3hsbCQBlAgAcAAkJ3hsbCQBlAgAAAA==.',
Ve='Vee:BAAALgAECgUJDQABLgAECgkJGwAFACkVAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAdAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn84AAICAAkJjQ3XAgBjAQACAAkJjQ3XAgBjAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTANNbADvAAAMAAkJTANNbADvAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjww5iADIAAAJAAMJjww5iADIAAAuAAQKfyoAAgkACQk+HwQeAKgCAAkACQk+HwQeAKgCAAAA.Wargrimm:BAABLgAECn8wAAIWAAkJRx83CwCuAgAWAAkJRx83CwCuAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIfAAQJISaTEwCRAQAfAAQJISaTEwCRAQAuAAQKf3AAAx8ACQnQJhIAAPgDAB8ACQnQJhIAAPgDAAIACQktI94GADgDAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJIAARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJIAARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJIAARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whisperz:BAAALgAECgMJAwABLgAECgkJIAARAO4WAA==.Whizpa:BAABLgAECn8gAAIRAAkJ7hasFwAQAgARAAkJ7hasFwAQAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJIAARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8ZAAIkAAkJThTsFgCbAQAkAAkJThTsFgCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJIAARAO4WAA==.Wilshammy:BAAALgAECgUJEAAAAA==.Wispy:BAABLgAECn8fAAIWAAcJAxOWNgBfAQAWAAcJAxOWNgBfAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAABLgAECn8WAAMIAAkJZRTRNAAKAgAIAAkJZRTRNAAKAgAGAAEJ6wbKZgAxAAAAAA==.Wrathbourne:BAAALgAECgYJEgABLgAECgkJFgAIAGUUAA==.Wrathchoi:BAABLgAECn8UAAMPAAYJlgwyAgC/AAAPAAYJlgwyAgC/AAAKAAQJigLNAgByAAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJFgAIAGUUAA==.',
Xa='Xantchaa:BAAALgAECgEJAgABLgAECgkJHAAJAMQbAA==.Xaquandrel:BAACLgAFFH8IAAIDAAMJMBbFMQDoAAADAAMJMBbFMQDoAAAuAAQKfzUAAgMACQkgGtQSAFwCAAMACQkgGtQSAFwCAAAA.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8tAAMIAAgJJh+SMwDhAQAIAAgJOR2SMwDhAQAGAAYJxB8IHwCkAQAAAA==.Xilo:BAABLgAECn8UAAIkAAgJXBzIAAB+AQAkAAgJXBzIAAB+AQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAbAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAMJBAAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgAECgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgMJAwAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8cAAIJAAkJxBumNABGAgAJAAkJxBumNABGAgAAAA==.Zenicks:BAAALgADCgYJBgABLgAECggJVwAlAPQMAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAbAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8UAAITAAcJcSAbDgApAgATAAcJcSAbDgApAgAAAA==.',
Zu='Zurazaee:BAABLgAECn8jAAIgAAgJMhkuEwBCAgAgAAgJMhkuEwBCAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAABLgAECn9dAAIkAAkJphxfBgCaAgAkAAkJphxfBgCaAgAAAA==.',
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
