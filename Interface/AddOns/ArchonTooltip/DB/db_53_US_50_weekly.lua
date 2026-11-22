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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Evoker-Devastation','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Priest-Discipline','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','DeathKnight-Blood','Mage-Fire','Monk-Windwalker','Druid-Feral','Monk-Brewmaster','Warlock-Affliction','Warrior-Fury','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','Shaman-Enhancement','Paladin-Holy','Druid-Restoration','Warrior-Protection','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn86AAMBAAoK4SO8AQDhAgABAAoK4SO8AQDhAgACAAEKlhJ5gQBBAAAAAA==.',
Ad='Adorian:BAAANQAECgMIAwAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxMtEgBAAQADAAQK+BYtEgBAAQACAAIKegarHwB1AAA1AAQKfyUAAwIACQpTHzIoAAgCAAIACArNGjIoAAgCAAMABAq0HeDhAD0BAAAA.',
Ae='Aelfwine:BAABNQAECn8aAAIDAAcKmAaX2gD9AAADAAcKmAaX2gD9AAAAAA==.',
Ai='Ailaith:BAABNQAECn9GAAMDAAoK6CQjBwBTAwADAAoK6CQjBwBTAwACAAIKAAB6egBYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn9JAAMEAAoKnSFKCQBlAgAEAAcKuRtKCQBlAgAFAAgK1yB1TADuAQAAAA==.Akibafaris:BAAANQAECggIBwABNQAECggIGgAGAGMWAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQAECgIIAgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAHAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAHAAAAAA==.Alirik:BAAANQADCgUIBwAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICgAHAAAAAA==.Alydrostage:BAABNQAECn8hAAIIAAkK8gu+EwBtAQAIAAkK8gu+EwBtAQAAAA==.Alystriaz:BAABNQAECn8iAAMJAAkKogqgDgBbAQAJAAkKogqgDgBbAQAKAAQK2ge1MwBgAAAAAA==.Alzheimerz:BAABNQAECn9AAAQLAAoKlSIjDQAcAwALAAoKOh4jDQAcAwAMAAcK7B6+MwAsAgANAAIKZBfqFgB4AAAAAA==.',
Am='Amaelalin:BAABNQAECn88AAIOAAoKqBYmOwBPAgAOAAoKqBYmOwBPAgAAAA==.Amatoria:BAABNQAECn8aAAMOAAgKeA8JbACZAQAOAAgKeA8JbACZAQAPAAUKyAzQPwCwAAAAAA==.',
An='Ananiel:BAAANQABCgcICAABNQAECgIIAgAHAAAAAA==.Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAHAAAAAA==.Andaya:BAACNQAFFH8JAAIQAAIK+RxPHwCnAAAQAAIK+RxPHwCnAAA1AAQKfzQAAxAACgoNHRgrALYCABAACgoNHRgrALYCAAYAAQoAAGwkAQAAAAAA.Andemeli:BAABNQAECn8fAAIRAAcKEQfRCwHXAAARAAcKEQfRCwHXAAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgMIAwAAAA==.',
Ar='Arandis:BAABNQAECn8oAAMPAAgK7QqNKABAAQAPAAgK7QqNKABAAQASAAEKCQXgLQApAAAAAA==.Arcblade:BAAANQAECgIIAgABNQAECgoKPQATAAgiAA==.Arcianna:BAABNQAECn89AAITAAoKCCKfBgDnAgATAAoKCCKfBgDnAgAAAA==.Arctica:BAABNQAECn8eAAIUAAgK7gRV3QDyAAAUAAgK7gRV3QDyAAAAAA==.Arjurn:BAABNQAECn86AAIUAAoKpR1FNwBoAgAUAAoKpR1FNwBoAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn89AAIVAAoKACWCAQD8AwAVAAoKACWCAQD8AwAAAA==.Artymiss:BAAANQAECgcIDgAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Aurturious:BAAANQADCgYIBgAAAA==.Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn9OAAIDAAoKkx+lHQDLAgADAAoKkx+lHQDLAgAAAA==.',
Ay='Ayorana:BAAANQAECgQIBAAAAA==.',
Az='Azshura:BAAANQAECgcIEQAAAA==.Azzinôth:BAABNQAECn9KAAMWAAoKEBXlIgDzAQAWAAoKEBXlIgDzAQAXAAcKpg7nOAB9AQAAAA==.',
['Aí']='Aírk:BAAANQAECgEIAQAAAA==.',
Ba='Baldr:BAABNQAECn8fAAIRAAoKLApNxQCRAQARAAoKLApNxQCRAQAAAA==.Balgar:BAABNQAECn8eAAIDAAkKaR7USwA4AgADAAkKaR7USwA4AgAAAA==.Balghas:BAAANQAECggIDgAAAA==.Bammz:BAABNQAECn8yAAIYAAoKjR84PQDTAgAYAAoKjR84PQDTAgABNQAECggIFAAPACYaAA==.Bastia:BAAANQADCgYIEwAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAHAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAABNQAECn8YAAIRAAgKGRueVACYAgARAAgKGRueVACYAgAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn83AAIDAAoKjRrtLQCLAgADAAoKjRrtLQCLAgAAAA==.Bloodytusks:BAAANQADCggIFgAAAA==.',
Bo='Boomchick:BAAANQADCggIEAABNQAECggIDAAHAAAAAA==.Borian:BAAANQADCggICAAAAA==.Borrkbuster:BAABNQAECn8ZAAINAAkKKxNVAwC4AQANAAkKKxNVAwC4AQAAAA==.Botkin:BAAANQAECgIIAgAAAA==.Bowan:BAAANQADCgYIBgAAAA==.',
Br='Brenri:BAAANQAECggIEAAAAA==.Brewtality:BAAANQAECgQIBAABNQAFFAUIEAAKANEKAA==.Brodysseus:BAAANQAECgcIBwAAAA==.Brudanature:BAAANQADCgUIBQABNQAECgcIGQAZAFkZAA==.Brughe:BAABNQAECn8cAAIDAAkKJRHsdwAfAgADAAkKJRHsdwAfAgAAAA==.Brywynn:BAAANQADCggIFAABNQAECggIHAADAGQOAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAFFAUIEAAKANEKAA==.Bumhug:BAAANQAECgUICAABNQAECgoKQAALAJUiAA==.Burnbabyburn:BAABNQAECn8YAAIaAAoKrBAKAwDlAQAaAAoKrBAKAwDlAQAAAA==.Burntbum:BAAANQADCggICAABNQAECgoKIgARAAEKAA==.Buttacutta:BAAANQADCggIPQAAAA==.',
Ca='Cahoots:BAABNQAECn8tAAIbAAoKjx4LDgD9AgAbAAoKjx4LDgD9AgAAAA==.Camaracy:BAAANQADCgYIBgAAAA==.Caneste:BAACNQAFFH8JAAIPAAQKCxFkCwA4AQAPAAQKCxFkCwA4AQA1AAQKfycAAg8ACQodIjAJAEsDAA8ACQodIjAJAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8tAAIcAAoK5xXNEQDkAQAcAAoK5xXNEQDkAQAAAA==.Cayleynne:BAACNQAFFH8JAAIdAAIKMRlaBwCIAAAdAAIKMRlaBwCIAAA1AAQKfy0AAh0ACgoIIAMFABgDAB0ACgoIIAMFABgDAAAA.',
Ce='Celestyl:BAABNQAECn8gAAIUAAYKHgQbCAGnAAAUAAYKHgQbCAGnAAAAAA==.Cernos:BAAANQADCgMIAwAAAA==.Cerwynne:BAAANQAFFAEIAQAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAQAAAA==.Cheapbeerz:BAABNQAECn8mAAMIAAkKcQY9GgAjAQAIAAgKYgY9GgAjAQAUAAcKeALTRwEWAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAABNQAECn8aAAIbAAgKaA/YKQBKAQAbAAgKaA/YKQBKAQAAAA==.Chromstrasza:BAABNQAECn8qAAIJAAoK5Q3BEwATAgAJAAoK5Q3BEwATAgAAAA==.Chrîstopher:BAAANQADCggICAAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn88AAMFAAoK0BmQKABtAgAFAAoK0BmQKABtAgAeAAEKAAAcMgAwAAAAAA==.',
Co='Comitus:BAABNQAECn88AAIYAAoK0QfshgB3AQAYAAoK0QfshgB3AQAAAA==.Conj:BAAANQAECgQIBAAAAA==.Conjarr:BAABNQAECn8vAAIOAAoKGhy3OwB7AgAOAAoKGhy3OwB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECgkJKAAfAEAcAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgIIBgAAAA==.Cougarsixsix:BAABNQAECn8aAAIgAAYKUR+kGwCUAQAgAAYKUR+kGwCUAQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8tAAIhAAoKog9AWACvAQAhAAoKog9AWACvAQAAAA==.Crypticcurse:BAAANQADCggILQAAAA==.',
Cy='Cynnai:BAABNQAECn8mAAIYAAkKwBxPOgBXAgAYAAkKwBxPOgBXAgAAAA==.',
Da='Dadythickums:BAAANQAECggICwAAAA==.Daeghrefn:BAAANQADCgYIBgABNQAECgUIBwAHAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgUIDgAHAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8nAAMFAAoKjg49uQBbAQAFAAgKTw49uQBbAQAEAAMKiQsDSQClAAAAAA==.Danashal:BAABNQAECn8uAAIKAAkKiwcBHwAZAQAKAAkKiwcBHwAZAQAAAA==.Dangerranger:BAAANQAECgIIBAAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECggIEQAAAA==.Darrth:BAABNQAECn8pAAMiAAoKrxQVLwDwAQAiAAoKrxQVLwDwAQAZAAEK2AN10wAqAAAAAA==.Darthbane:BAABNQAECn8dAAMiAAgK/Qa1WwAoAQAiAAgKeAa1WwAoAQAhAAUK8wWCWQChAAAAAA==.Darthjareth:BAAANQADCgYIDAAAAA==.Darthsion:BAAANQADCgEIAQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAHAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQADCggIFgABNQAECggIEQAHAAAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn81AAMOAAoKPxlYKwCcAgAOAAoKPxlYKwCcAgAPAAUKdwSyXgCIAAAAAA==.Demontator:BAAANQADCggIDQABNQAECgoKIgARAAEKAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIGAAgKYxYkXgAHAgAGAAgKYxYkXgAHAgAAAA==.Desmádre:BAABNQAECn8aAAMhAAcKPxxaQQAXAgAhAAcKNhtaQQAXAgAZAAYKBxuYTgC7AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn9FAAMQAAoK3CNLCgB5AwAQAAoK3CNLCgB5AwAGAAMK4hADzwBwAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAABNQAECn8bAAMFAAkK0RC2iwBFAQAFAAcKexG2iwBFAQAEAAIKJg8pJQBiAAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgoKIAAjAA8WAA==.',
Dr='Dravenpryde:BAABNQAECn8eAAIQAAkKYglGgACLAQAQAAkKYglGgACLAQABNQAECgoKLwATALAeAA==.Drbrad:BAAANQAECgUIBAAAAA==.Dreadfists:BAABNQAECn8cAAIiAAoKwhAkOQDvAQAiAAoKwhAkOQDvAQAAAA==.Druen:BAABNQAECn89AAIcAAoKryFpAwAMAwAcAAoKryFpAwAMAwAAAA==.Drunkenpo:BAABNQAECn9AAAQdAAoKgB8DAwDKAgAdAAoKgB8DAwDKAgAVAAIKfgw/NwBWAAAbAAEKfQ/6XQA0AAAAAA==.Drunkxdemon:BAAANQAECgcIDAAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8ZAAMbAAoKEhkrGACHAgAbAAoKEhkrGACHAgAVAAEKuwRbQQAmAAAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8tAAMGAAoKZxVXRQBhAgAGAAgKmBhXRQBhAgAQAAQKwA/BpgDPAAABNQAFFAQIEQALANoZAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAABNQAECn8aAAMVAAcKkBMWGgBiAQAVAAcKkBMWGgBiAQAbAAIK/geiUQBeAAAAAA==.Dweñde:BAABNQAECn8+AAIFAAoKUQ5/XQC8AQAFAAoKUQ5/XQC8AQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECggIDgAAAA==.',
Ed='Eddiemac:BAAANQAECgYIBgAAAA==.Eddrick:BAABNQAECn88AAMgAAoK+hkoEQAYAgARAAoKXhjxVwAnAgAgAAgKDBooEQAYAgAAAA==.Edrid:BAABNQAECn8yAAIUAAkKlh9FJgCmAgAUAAkKlh9FJgCmAgABNQAFFAUIDgAKACocAA==.',
Ei='Eirwen:BAAANQABCgMIAgAAAA==.',
El='Elleryn:BAAANQADCgYIBgABNQAECggIHAADAGQOAA==.Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn9HAAMSAAoKbyNnAQA/AwASAAkKlyNnAQA/AwAOAAEKCCKc3gBhAAAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAABNQAECn8dAAMgAAkKWBJBIABtAQARAAcKKBA3wwCVAQAgAAkKihFBIABtAQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAABNQAECn8XAAIRAAkKIhyOTQCsAgARAAkKIhyOTQCsAgAAAA==.',
Ev='Evandra:BAABNQAECn8cAAIQAAkKsBaQTADgAQAQAAkKsBaQTADgAQAAAA==.Evanorah:BAAANQAECgUICwAAAA==.Eveningstar:BAAANQAECgEIAQAAAA==.',
Fa='Faedeyeda:BAAANQAECgUIDAAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQAECggICgABNQAECgoKPAAkAK8cAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBwAHAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECgkJHwAQAIQWAA==.Fonta:BAAANQADCgYIDAAAAA==.Fortuna:BAAANQADCgYIBgABNQAECggIDAAHAAAAAA==.',
Fr='Frojio:BAABNQAECn8YAAIiAAgKtgvvSgCOAQAiAAgKtgvvSgCOAQAAAA==.Frosten:BAAANQADCggIUwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgMIAwAAAA==.Gaff:BAABNQAECn8lAAIYAAoKpRMxeQCaAQAYAAoKpRMxeQCaAQAAAA==.Galia:BAAANQAECgYIBgAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Go='Gobby:BAAANQAECgcIBwABNQAECgoKIAAjAA8WAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYIDgAAAA==.Gruzaxx:BAAANQABCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQAPAAsRAA==.',
Ha='Hadin:BAABNQAECn8zAAIUAAoKJh/8KgCTAgAUAAoKJh/8KgCTAgAAAA==.Halalnt:BAAANQAECgUIDQABNQAECggIEgAHAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAIAGkaAA==.Hamster:BAAANQADCgYIBgABNQAECgYIFAAIAE0dAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn88AAITAAoKrxcqFgDhAQATAAoKrxcqFgDhAQAAAA==.Harsaiah:BAAANQADCgYICAABNQAECggIHQAlAIweAA==.Hazenpryde:BAABNQAECn8vAAITAAoKsB4gCQDlAgATAAoKsB4gCQDlAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIHQABNQAECgoKMQAmADMdAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAABNQAECn84AAIDAAoK9hW8UwB2AgADAAoK9hW8UwB2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8tAAIFAAoKAh3HIgCGAgAFAAoKAh3HIgCGAgAAAA==.',
Hy='Hysgar:BAAANQAECgUIDgABNQAECggIHQAlAIweAA==.',
Ic='Icetiger:BAAANQADCgUICAAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8xAAMPAAoKERuLEABQAgAPAAoKERuLEABQAgAOAAUKghY5mgBGAQAAAA==.Imperion:BAAANQABCgIIAgAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn86AAMYAAoKHBxjPgBJAgAYAAoKHBxjPgBJAgAnAAEKAAAXUgAAAAAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgYICAAAAA==.',
Ja='Jackfruit:BAABNQAECn8jAAMRAAoKnBC12ABqAQARAAgKDAq12ABqAQAlAAcK/Ao8gQAzAQAAAA==.Jaod:BAAANQADCgYIHAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIBQAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kaedor:BAAANQABCgEIAQAAAA==.Kahnrah:BAAANQADCggILAAAAA==.Kalarae:BAAANQAECgcICgAAAA==.Kaljeer:BAABNQAECn8nAAIMAAoKYhRUQQD4AQAMAAoKYhRUQQD4AQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kalmyk:BAAANQAECgcIDwAAAA==.Kaltharion:BAAANQAECgQIBQAAAA==.Kaluren:BAACNQAFFH8OAAIlAAUKyyDECADWAQAlAAUKyyDECADWAQA1AAQKfyoAAyUACQqtJi4BAOEDACUACQqtJi4BAOEDABEABQosIPXiAFUBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8iAAMFAAoK8gzkmgCjAQAFAAoKsgrkmgCjAQAEAAIKeBFpWQB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8zAAIdAAoKmyJOAgD2AgAdAAoKmyJOAgD2AgAAAA==.Kapp:BAABNQAECn8WAAMnAAcKhRJKGQA/AQAnAAcKhRJKGQA/AQAYAAIKxALlTAE6AAAAAA==.Karabar:BAABNQAECn87AAMgAAoKCh/FDQBQAgAgAAoKCh/FDQBQAgARAAEKAACh1AEAAAAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAHAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAHAAAAAA==.Karnnagexxl:BAAANQAECgQIAwABNQAECgQIBQAHAAAAAA==.Kasarra:BAABNQAECn8ZAAIWAAkKMw48NQB3AQAWAAkKMw48NQB3AQAAAA==.Kayiku:BAAANQADCggIJAAAAA==.Kazagol:BAABNQAECn8vAAIXAAoKjBh1HABxAgAXAAoKjBh1HABxAgAAAA==.',
Ke='Kezzi:BAAANQADCgcIBgAAAA==.',
Kh='Khamaracy:BAABNQAECn8lAAIEAAcK6wr+DgDbAAAEAAcK6wr+DgDbAAAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQAECggICAAAAA==.Kovalenko:BAABNQAECn8vAAIRAAkK8xjUcwDnAQARAAkK8xjUcwDnAQAAAA==.',
Kr='Kryptus:BAABNQAECn84AAIUAAoKyhoLRgA7AgAUAAoKyhoLRgA7AgAAAA==.',
Ku='Kurick:BAABNQAECn8dAAQlAAgKjB5TcwC+AQAlAAUK6SFTcwC+AQARAAcK4RhuvACkAQAgAAEKAxAaYgA4AAAAAA==.Kurshak:BAABNQAECn8zAAMoAAoKfhZVNQA/AgAoAAoKfhZVNQA/AgAcAAEKKgnMTAAvAAAAAA==.',
Ky='Kyngizzard:BAAANQAECggIEgAAAA==.',
La='Latte:BAABNQAECn8bAAIDAAgKthgfVwAdAgADAAgKthgfVwAdAgAAAA==.Lazy:BAAANQADCgMIAwAAAA==.',
Le='Lenity:BAABNQAECn85AAIMAAoKkQyVWAClAQAMAAoKkQyVWAClAQAAAA==.',
Lo='Loan:BAAANQADCggIGwABNQAECgYIFAAIAE0dAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAABNQAECn8VAAIDAAgK3QQF2AACAQADAAgK3QQF2AACAQAAAA==.Lookatchu:BAAANQADCgIIAgAAAA==.',
Lu='Lucoryphus:BAAANQAECgUIBwAAAA==.Lukeduke:BAACNQAFFH8OAAInAAUKnxwxAgCJAQAnAAUKnxwxAgCJAQA1AAQKfycAAicACQrKIwsEAE8DACcACQrKIwsEAE8DAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAUIDgAnAJ8cAA==.Lunaries:BAAANQAECgEIAgAAAA==.Lunä:BAABNQAECn8qAAMQAAoKpxuiKACIAgAQAAoKpxuiKACIAgAGAAQKlAh/vgCNAAAAAA==.',
Ly='Lydia:BAABNQAECn80AAMUAAoKNRfnjQCKAQAUAAkK+xTnjQCKAQAIAAIKEBzMKwCcAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICgAHAAAAAA==.',
['Lú']='Lúthien:BAABNQAECn8ZAAMTAAcKWQftSACaAAATAAYKHAftSACaAAAcAAUKEgTPQwBEAAAAAA==.',
Ma='Malcontent:BAAANQAECgQIAwABNQAECgoKIAAjAA8WAA==.Malfeasance:BAAANQADCgUIBQABNQAECgoKIAAjAA8WAA==.Malifel:BAABNQAECn8gAAMjAAoKDxbfCgCuAQAXAAoKKxDhGwDKAQAjAAcKfRjfCgCuAQAAAA==.Mallord:BAAANQAECgQIBAABNQAECgoKIAAjAA8WAA==.Malstrom:BAAANQAECgMIBAABNQAECgoKIAAjAA8WAA==.Mandarin:BAABNQAECn8gAAMmAAgKeg9aKgCcAQAmAAgKeg9aKgCcAQAoAAEK0wHHnAAOAAAAAA==.Mararose:BAAANQABCgQIBgAAAA==.Marashades:BAABNQAECn8hAAQZAAkKqB7rHwD9AQAZAAkKqB7rHwD9AQAiAAMKAQYzpABSAAAhAAEKdwuGhAA7AAAAAA==.Marsali:BAAANQAECgIIAQAAAA==.',
Me='Melabrin:BAABNQAECn8qAAIFAAoKFAyHYQCxAQAFAAoKFAyHYQCxAQAAAA==.Mercia:BAABNQAECn8mAAIgAAoKdB6zDwCiAgAgAAoKdB6zDwCiAgAAAA==.Mercý:BAAANQADCggIIAAAAA==.Merekoma:BAABNQAECn8sAAIXAAkKPRcBGgDeAQAXAAkKPRcBGgDeAQAAAA==.',
Mi='Mieena:BAAANQABCgUIBQAAAA==.Milhouse:BAAANQAECgIIAwAAAA==.Mingonashoba:BAAANQAECgQICgAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAABNQAECn8eAAMbAAkKzQs+MAAaAQAbAAgKPgw+MAAaAQAVAAUKPwJKQQBvAAAAAA==.Mistaricky:BAABNQAECn8ZAAMYAAgKhRMAowDFAQAYAAgKhRMAowDFAQAfAAEKxAj3NAAxAAAAAA==.',
Mo='Moadeed:BAABNQAECn8WAAITAAgK5BC3MAARAQATAAgK5BC3MAARAQAAAA==.Moongazer:BAAANQAECgQIBgAAAA==.Morassabe:BAAANQADCggIDwAAAA==.Morphmious:BAABNQAECn87AAIcAAoKwx4ICwCCAgAcAAoKwx4ICwCCAgAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgcIEgAAAA==.',
My='Mycenaean:BAAANQAECgEIAQABNQAFFAIICQAdADEZAA==.Myroku:BAAANQADCggICAABNQAECgoKIAAjAA8WAA==.Myrrh:BAABNQAECn8qAAMKAAoKOgblJACZAQAKAAoKOgblJACZAQAJAAIKTwTlHwBhAAAAAA==.Mysklef:BAAANQAECgIIAgABNQAECggIHQAlAIweAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgUICAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICgAHAAAAAA==.Nausican:BAAANQAECgMIBAAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgoKLwAQAE4hAA==.Necrosector:BAABNQAECn9MAAIRAAoK2SIqEwAZAwARAAoK2SIqEwAZAwAAAA==.Nelandra:BAABNQAECn8iAAIPAAgKMRTcHgCXAQAPAAgKMRTcHgCXAQAAAA==.Neongrasp:BAABNQAECn8YAAIhAAoK4xOCJwClAQAhAAoK4xOCJwClAQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAQIEQALANoZAA==.Nirvelli:BAAANQADCgYIBgABNQAECgMIAwAHAAAAAA==.',
No='Nobara:BAAANQAECggIDQABNQAECgoKPQAhAN8kAA==.Nomahuata:BAABNQAECn9IAAIGAAoKKxEjPgDcAQAGAAoKKxEjPgDcAQAAAA==.',
Nu='Nufrus:BAABNQAECn8YAAIDAAgKKwht0ABgAQADAAgKKwht0ABgAQAAAA==.Nurgle:BAAANQADCggIEQAAAA==.',
Ny='Nyeli:BAABNQAECn8cAAIDAAgKZA4ymACEAQADAAgKZA4ymACEAQAAAA==.Nyxi:BAABNQAECn8bAAIQAAcKfQomhgAiAQAQAAcKfQomhgAiAQAAAA==.',
['Né']='Néo:BAAANQAECgMIBAAAAA==.',
Oc='Octavios:BAAANQAECgQIBAAAAA==.',
Om='Ommeta:BAABNQAECn8YAAMWAAkKahgrNgByAQAWAAYKGxgrNgByAQAXAAUKGRO/OwDCAAABNQAFFAQICAAoAGYIAA==.',
On='Onefiddy:BAAANQAECgUIBgABNQAECgoKPAAkAK8cAA==.Onefiftyone:BAABNQAECn88AAQkAAoKrxzODQA5AgAkAAkKUxzODQA5AgAQAAgKUxgjiQAZAQAGAAEKAAD7PAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgUIDgAAAA==.Paltator:BAABNQAECn8iAAIRAAoKAQo4qAB+AQARAAoKAQo4qAB+AQAAAA==.Pandazuken:BAABNQAECn83AAIGAAoKlxrRLwAaAgAGAAoKlxrRLwAaAgAAAA==.Paradots:BAACNQAFFH8QAAIKAAUK0QoaDAA7AQAKAAUK0QoaDAA7AQA1AAQKf0gAAgoACgrSHJIFAB8DAAoACgrSHJIFAB8DAAAA.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAABNQAECn8oAAIfAAkKQBzaBQC8AgAfAAkKQBzaBQC8AgAAAA==.Pastlives:BAAANQAECgYIDwAAAA==.',
Ph='Phantasee:BAAANQADCgQIBAAAAA==.Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECggIEQAHAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQAECggIBgAAAA==.Pixystix:BAABNQAECn8dAAMjAAcKlxzOCQDLAQAjAAYK7yDOCQDLAQAXAAEK3wbqWQAsAAABNQAECggIBgAHAAAAAA==.',
Po='Pomortem:BAABNQAECn8ZAAIZAAcKWRl6QAA8AQAZAAcKWRl6QAA8AQAAAA==.Potsomancy:BAACNQAFFH8MAAIUAAYK1RoODwAAAgAUAAYK1RoODwAAAgA1AAQKfx8AAhQACQokJP1IAPECABQACQokJP1IAPECAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQAECgQIBAABNQAECgUICQAHAAAAAA==.Raivel:BAABNQAECn8kAAIQAAcK5g5fdwBNAQAQAAcK5g5fdwBNAQABNQAECggIHAADAGQOAA==.Rambogg:BAAANQADCgMIAwABNQAFFAcIEQAUAMoIAA==.Raneyth:BAAANQAECgYIDwAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQAECgEIAQABNQAECgoKSgAWABAVAA==.Ravusternath:BAAANQADCggIFQAAAA==.',
Re='Redwinetoast:BAAANQAECgYIDAAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8yAAQJAAoKuRg3CQDoAQAJAAkK1xc3CQDoAQAKAAQKVg2ZPwCjAAApAAEKAAAAJQAxAAABNQAECgYIFAAIAE0dAA==.Reposess:BAAANQABCggIFAAAAA==.Reshyk:BAAANQAECggIDwAAAA==.',
Rh='Rhobes:BAAANQADCggIJAAAAA==.Rhondta:BAAANQAECgEIAQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Rillidan:BAEANQADCgMIAwABNQAECgoKJgAPAJkPAA==.Riordaa:BAABNQAECn8dAAIlAAkKbwfBdABXAQAlAAkKbwfBdABXAQAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAHAAAAAA==.Roflwhat:BAAANQAECgIIAgAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIHAAAAA==.',
Ru='Rumor:BAABNQAECn8xAAMmAAoKMx1aCgAqAwAmAAoKMx1aCgAqAwAoAAQKvghJdwBdAAAAAA==.Rurry:BAACNQAFFH8OAAIKAAUKKhzQCACsAQAKAAUKKhzQCACsAQA1AAQKfyYAAwoACQqQI9EDAHgDAAoACQqQI9EDAHgDAAkAAQohJeI0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn89AAMhAAoK3yScFAAUAwAhAAoK3yScFAAUAwAZAAIKMgpeugBTAAAAAA==.Ryuuko:BAAANQAECggICAAAAA==.',
['Rä']='Rägnårok:BAAANQADCgYIBgAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8RAAMLAAQK2hlgBgDsAAALAAMK2hlgBgDsAAAMAAMK4AnmHQCRAAA1AAQKfzEAAwsACgrJIqcGAGgDAAsACgoAIacGAGgDAAwABwqtEuApAHUBAAAA.',
Sa='Sabastion:BAAANQADCgMIAwABNQAECgoKIAAjAA8WAA==.Sableanne:BAAANQAECgYIDgAAAA==.Safetysham:BAAANQAECgMIAgAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYIBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAHAAAAAA==.Salmoo:BAABNQAECn8fAAIQAAkKhBbwPQAdAgAQAAkKhBbwPQAdAgAAAA==.Saltytator:BAAANQAECgMIBQABNQAECgoKIgARAAEKAA==.Santhon:BAAANQADCgQICAAAAA==.Satanized:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggILgAAAA==.',
Sc='Scaledaddy:BAABNQAECn8rAAMpAAoKyglGDACUAQApAAkKcApGDACUAQAJAAQK3AbdMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECgoKOgABAOEjAA==.Scaryl:BAABNQAECn8hAAIoAAYKWwYgVQDKAAAoAAYKWwYgVQDKAAAAAA==.Schneè:BAABNQAECn9LAAInAAoKLBcVDgDZAQAnAAoKLBcVDgDZAQAAAA==.Scoom:BAACNQAFFH8OAAIUAAUK5hyfGgCmAQAUAAUK5hyfGgCmAQA1AAQKfy8AAhQACQoFJcYZAG4DABQACQoFJcYZAG4DAAAA.Scourgespawn:BAACNQAFFH8LAAMiAAUKlhmoBwB+AQAiAAUKlhmoBwB+AQAhAAEKAADhIwA9AAA1AAQKfyoAAyIACQoeJMwQAAkDACIACQoeJMwQAAkDACEABAogEcOYAM8AAAAA.',
Se='Seikyo:BAABNQAECn87AAIZAAoK5wx0PgBFAQAZAAoK5wx0PgBFAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECggIEgAHAAAAAA==.Selenë:BAAANQAECgYIEgAAAA==.Serok:BAAANQAECggIEAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcICgAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAHAAAAAA==.Shalis:BAAANQAECgcICgAAAA==.Sharivee:BAAANQAECgYIDAAAAA==.Shazamir:BAABNQAECn8YAAIkAAkKXgVBIwAoAQAkAAkKXgVBIwAoAQAAAA==.Shibui:BAABNQAECn9GAAIWAAoKKhZCHAAtAgAWAAoKKhZCHAAtAgAAAA==.Shifthead:BAACNQAFFH8IAAIoAAQKZgjdFgC2AAAoAAQKZgjdFgC2AAA1AAQKfy8AAxwACgoEGLgNAD4CABwACAoAGbgNAD4CACgACgodEag5ACMCAAAA.Shockazilla:BAABNQAECn8nAAIlAAkKHiLdHAAAAwAlAAkKHiLdHAAAAwAAAA==.Shortspanky:BAAANQAECgQIDgAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAABNQAECn8YAAIRAAgKZBFYvACkAQARAAgKZBFYvACkAQAAAA==.',
Sk='Skoduh:BAABNQAECn8fAAIDAAgKAxQjhACxAQADAAgKAxQjhACxAQAAAA==.',
Sl='Slack:BAABNQAECn8eAAMOAAoKxiHTEQBKAwAOAAoKxiHTEQBKAwAPAAEKAACecABHAAABNQAECgYIFAAIAE0dAA==.Sluggo:BAACNQAFFH8MAAIRAAUK3xHUDAB+AQARAAUK3xHUDAB+AQA1AAQKfyYAAhEACQrUICVTAJwCABEACQrUICVTAJwCAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIAQAAAA==.',
Sp='Spiralist:BAAANQAECggIDQAAAA==.Spìne:BAAANQAECgQIBAAAAA==.',
St='Steelforged:BAAANQADCgQIBAABNQAECggIGgAbAGgPAA==.Stonedalways:BAABNQAECn8cAAIQAAkKighPcwBZAQAQAAkKighPcwBZAQAAAA==.Stonytoni:BAAANQAECgMIAQAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQABNQAECgoKGAAaAKwQAA==.Sunfuri:BAABNQAECn8bAAIfAAgK0ATFGwDsAAAfAAgK0ATFGwDsAAAAAA==.Sus:BAACNQAFFH8NAAIWAAUKXBTcCgB1AQAWAAUKXBTcCgB1AQA1AAQKfyYAAxYACQrKIvIZAMsCABYACQrKIvIZAMsCACMABAp1C0giALAAAAAA.Susanoo:BAAANQAECggIEAAAAA==.',
Ta='Taalia:BAABNQAECn8kAAIQAAcKcgsohAAnAQAQAAcKcgsohAAnAQAAAA==.Talonas:BAABNQAECn8qAAMIAAoK0RiFBgBfAgAIAAoKgRiFBgBfAgAUAAYKyBdt8QDMAAAAAA==.Tarathor:BAABNQAECn8hAAIoAAcKQQ7BRAARAQAoAAcKQQ7BRAARAQAAAA==.Tatortott:BAAANQAECggIDQABNQAECgoKIgARAAEKAA==.',
Te='Teknofarious:BAABNQAECn8eAAMaAAkK7QsKBABdAQAaAAkK7QsKBABdAQAIAAEKAAAmSwAvAAAAAA==.',
Th='Thesafe:BAAANQAECgYIDQAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAABNQAECn8UAAMIAAYKTR1sDAD0AQAIAAYKTR1sDAD0AQAUAAQKYgaHfgHGAAAAAA==.Thialaa:BAABNQAECn8mAAMnAAoKPxmWCQA9AgAnAAkKWBuWCQA9AgAYAAEKlgoGKQE4AAABNQAECgoKRgADAOgkAA==.Thialia:BAABNQAECn85AAIOAAoKjRMsSgAPAgAOAAoKjRMsSgAPAgABNQAECgoKRgADAOgkAA==.Thialiaa:BAABNQAECn8dAAIIAAoKYBAiCwDvAQAIAAoKYBAiCwDvAQABNQAECgoKRgADAOgkAA==.Thialiadin:BAABNQAECn8pAAMgAAoKEBkLEgALAgAgAAkKpBoLEgALAgAlAAEKAA8n9AA3AAABNQAECgoKRgADAOgkAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn87AAISAAoK+xyhAQD+AgASAAoK+xyhAQD+AgAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAQIEQALANoZAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgYIEAAAAA==.Trema:BAABNQAECn9VAAMgAAoKGRkWFQBZAgAgAAgKpBwWFQBZAgARAAoK0Qw8uACtAQAAAA==.Trialei:BAAANQABCgIIAgAAAA==.Trick:BAAANQAECgQICAABNQAECgoKRQAcAAomAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAABNQAECn8ZAAMoAAkK8xO1MgB2AQAoAAcK7BK1MgB2AQAmAAgKFQ/jPwAnAQABNQAECgoKQAALAJUiAA==.',
Tu='Tulsi:BAABNQAECn8ZAAILAAoKxxlmEwCZAQALAAoKxxlmEwCZAQAAAA==.',
Ty='Tyronos:BAABNQAECn8dAAIRAAoKZA/pmACbAQARAAoKZA/pmACbAQAAAA==.',
Va='Vaeltharion:BAAANQAECgUIDgAAAA==.Varedrae:BAAANQADCggIFQAAAA==.Vas:BAAANQADCgYIFAAAAA==.Vaydark:BAAANQAECggIBQABNQAECgoKRgAWACoWAA==.',
Ve='Verdandi:BAAANQAECgUICgAAAA==.Vevicenth:BAABNQAECn8mAAMUAAoKswe3iwCPAQAUAAkKkQe3iwCPAQAaAAYKZgOsBgDoAAAAAA==.',
Vo='Voranth:BAABNQAECn8vAAMQAAoKTiGqEAA2AwAQAAoKTiGqEAA2AwAGAAQKIBItxgAGAQAAAA==.',
Wa='Wainstatick:BAAANQAECgUICQAAAA==.Wakeko:BAAANQAECgUICAABNQAECgcIHAAYAMkVAA==.Warenio:BAABNQAECn8tAAMnAAoKpxVTEAAjAgAnAAoKpxVTEAAjAgAYAAIKhQJnHAFGAAAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMIAAkKaRqLCwAIAgAIAAkKfRaLCwAIAgAUAAYKrR0SzwDoAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECgkJHgAbAM0LAA==.',
Wh='Whakan:BAAANQADCggIJwABNQAECgUIBwAHAAAAAA==.',
Wi='Williamgoat:BAABNQAECn8ZAAIeAAkKWw80BwD1AQAeAAkKWw80BwD1AQABNQAECgoKQAALAJUiAA==.',
Wo='Wolfos:BAAANQAECgIICgAAAA==.',
Wt='Wtfox:BAEBNQAECn8mAAIPAAoKmQ8WHAC0AQAPAAoKmQ8WHAC0AQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAABNQAECn8iAAMXAAkKyg4ZIgCOAQAXAAkKyg4ZIgCOAQAWAAMKfAQ7hgAyAAAAAA==.',
Xa='Xalatos:BAAANQAECggIEgAAAA==.Xalfein:BAAANQADCggILgAAAA==.',
Xi='Xinu:BAAANQAECgQIBAABNQAECgoKPAADABMbAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Xy='Xylendra:BAAANQAECgUICwABNQAECgoKIwAbAJEHAA==.',
Ya='Yanakana:BAAANQAECgUIDAAAAA==.',
Yd='Ydrassil:BAAANQAECggIEAABNQAECgkJFwARACIcAA==.',
Za='Zakeko:BAABNQAECn8cAAMYAAcKyRUulgBUAQAYAAcKyRUulgBUAQAnAAEKAAD6PQBLAAAAAA==.Zanderpryde:BAABNQAECn8eAAIOAAkK6QkUcQCJAQAOAAkK6QkUcQCJAQABNQAECgoKLwATALAeAA==.Zariak:BAAANQABCgIIAgAAAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusal:BAAANQAECgQIBAAAAA==.Zeusinator:BAABNQAECn80AAIDAAkKpxluLwCGAgADAAkKpxluLwCGAgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn88AAMDAAoKExtsMQCAAgADAAoKExtsMQCAAgACAAEKSwXMagAwAAAAAA==.Zivalisse:BAAANQAECgMICgAAAA==.',
Zo='Zota:BAABNQAECn8jAAIDAAkKEBgNWwATAgADAAkKEBgNWwATAgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECggIHQAlAIweAA==.Zulfionn:BAABNQAECn8oAAIDAAkKGAgtfgC+AQADAAkKGAgtfgC+AQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgYIFAAIAE0dAA==.',
['Áy']='Áyrá:BAAANQAECgcIEwAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMIBwAAAA==.',
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
