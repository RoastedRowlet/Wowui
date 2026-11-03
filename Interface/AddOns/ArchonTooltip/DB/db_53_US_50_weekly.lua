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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Evoker-Devastation','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Priest-Holy','Shaman-Restoration','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','DeathKnight-Blood','Mage-Fire','Monk-Windwalker','Druid-Feral','Monk-Brewmaster','Warlock-Affliction','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','Paladin-Protection','Shaman-Enhancement','Paladin-Holy','Druid-Restoration','Warrior-Protection','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn86AAMBAAoK4SNIAQD1AgABAAoK4SNIAQD1AgACAAEKlhJ5gQBBAAAAAA==.',
Ad='Adorian:BAAANQAECgIIAgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxMtEgBAAQADAAQK+BYtEgBAAQACAAIKegarHwB1AAA1AAQKfyUAAwIACQpTHzIoAAgCAAIACArNGjIoAAgCAAMABAq0HeDhAD0BAAAA.',
Ae='Aelfwine:BAABNQAECn8aAAIDAAcKmAYrtwAAAQADAAcKmAYrtwAAAQAAAA==.',
Ai='Ailaith:BAABNQAECn83AAMDAAoK7yHkDAAPAwADAAoK7yHkDAAPAwACAAIKAAB6egBYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn9CAAMEAAoKYiBKCQBlAgAEAAcKuRtKCQBlAgAFAAgKMx+uRQDOAQAAAA==.Akibafaris:BAAANQAECggIBwABNQAECggIGgAGAGMWAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQAECgIIAgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAHAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAHAAAAAA==.Alirik:BAAANQADCgUIBwAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICgAHAAAAAA==.Alydrostage:BAABNQAECn8ZAAIIAAcKDw6+EwBtAQAIAAcKDw6+EwBtAQAAAA==.Alystriaz:BAABNQAECn8gAAMJAAcKnQoGEQD4AAAJAAcKnQoGEQD4AAAKAAQK2gd3LQBgAAAAAA==.Alzheimerz:BAABNQAECn88AAQLAAoKMiEjDQAcAwALAAoKOh4jDQAcAwAMAAcKaxu7MQD5AQANAAIKZBfqFgB4AAAAAA==.',
Am='Amaelalin:BAABNQAECn82AAIOAAkKIxZRQAAAAgAOAAkKIxZRQAAAAgAAAA==.Amatoria:BAAANQAECgYIEwAAAA==.',
An='Ananiel:BAAANQABCgcICAABNQAECgIIAgAHAAAAAA==.Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAHAAAAAA==.Andaya:BAACNQAFFH8HAAIPAAIK+Rz7GACpAAAPAAIK+Rz7GACpAAA1AAQKfywAAw8ACgpsHBgrALYCAA8ACgpsHBgrALYCAAYAAQoAAIwEAQAAAAAA.Andemeli:BAABNQAECn8YAAIQAAcKCwcL7ADNAAAQAAcKCwcL7ADNAAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgMIAwAAAA==.',
Ar='Arandis:BAABNQAECn8gAAMRAAcKXQuKKAADAQARAAcKXQuKKAADAQASAAEKCQXgLQApAAAAAA==.Arcianna:BAABNQAECn84AAITAAoKCCI9BQDqAgATAAoKCCI9BQDqAgAAAA==.Arctica:BAABNQAECn8cAAIUAAcKqQRu2gDLAAAUAAcKqQRu2gDLAAAAAA==.Arjurn:BAABNQAECn86AAIUAAoKpR3cKAB+AgAUAAoKpR3cKAB+AgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn89AAIVAAoKACX3AAAMBAAVAAoKACX3AAAMBAAAAA==.Artymiss:BAAANQAECgcIDgAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn83AAIDAAoKCh0UKAB0AgADAAoKCh0UKAB0AgAAAA==.',
Ay='Ayorana:BAAANQADCggIEAAAAA==.',
Az='Azshura:BAAANQAECgcIDwAAAA==.Azzinôth:BAABNQAECn9GAAMWAAoKEBV4GwD7AQAWAAoKEBV4GwD7AQAXAAcKpg7nOAB9AQAAAA==.',
['Aí']='Aírk:BAAANQAECgEIAQAAAA==.',
Ba='Baldr:BAABNQAECn8fAAIQAAoKLApNxQCRAQAQAAoKLApNxQCRAQAAAA==.Balgar:BAABNQAECn8bAAIDAAgK3R1GVQByAgADAAgK3R1GVQByAgAAAA==.Balghas:BAAANQAECggIDgAAAA==.Bammz:BAABNQAECn8yAAIYAAoKjR84PQDTAgAYAAoKjR84PQDTAgAAAA==.Bastia:BAAANQADCgYIEwAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAHAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAABNQAECn8YAAIQAAgKGRueVACYAgAQAAgKGRueVACYAgAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn8pAAIDAAoKSBZ6OAA2AgADAAoKSBZ6OAA2AgAAAA==.Bloodytusks:BAAANQADCggIFgAAAA==.',
Bo='Boomchick:BAAANQADCggICgAAAA==.Borian:BAAANQADCggICAAAAA==.Borrkbuster:BAABNQAECn8UAAINAAcK4RHTBAAjAQANAAcK4RHTBAAjAQAAAA==.Botkin:BAAANQAECgIIAwAAAA==.',
Br='Brenri:BAAANQAECgYICwAAAA==.Brewtality:BAAANQAECgQIBAABNQAFFAQIDgAKABYMAA==.Brodysseus:BAAANQAECgcIBwAAAA==.Brudanature:BAAANQADCgUIBQABNQAECgcIGQAZAFkZAA==.Brughe:BAABNQAECn8ZAAIDAAkKJRHsdwAfAgADAAkKJRHsdwAfAgAAAA==.Brywynn:BAAANQAECgEIAQABNQAECgYIGgAPAMIPAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAFFAQIDgAKABYMAA==.Bumhug:BAAANQAECgUICQABNQAECgoKPAALADIhAA==.Burnbabyburn:BAABNQAECn8YAAIaAAoKrBAKAwDlAQAaAAoKrBAKAwDlAQAAAA==.Burntbum:BAAANQADCggICAABNQAECgkJIAAQALkJAA==.Buttacutta:BAAANQADCggIPQAAAA==.',
Ca='Cahoots:BAABNQAECn8tAAIbAAoKjx4LDgD9AgAbAAoKjx4LDgD9AgAAAA==.Caneste:BAACNQAFFH8JAAIRAAQKCxFkCwA4AQARAAQKCxFkCwA4AQA1AAQKfycAAhEACQodIjAJAEsDABEACQodIjAJAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8mAAIcAAkKLhbNEQDkAQAcAAkKLhbNEQDkAQAAAA==.Cayleynne:BAACNQAFFH8HAAIdAAIKMRmRBQCWAAAdAAIKMRmRBQCWAAA1AAQKfyUAAh0ACgoIIAMFABgDAB0ACgoIIAMFABgDAAAA.',
Ce='Celestyl:BAABNQAECn8WAAIUAAUKqwPYCQF+AAAUAAUKqwPYCQF+AAAAAA==.Cernos:BAAANQADCgMIAwAAAA==.Cerwynne:BAAANQAECgQIBAAAAA==.',
Ch='Chadman:BAAANQAECgEIAQAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAQAAAA==.Cheapbeerz:BAABNQAECn8jAAMIAAgKUAY9GgAjAQAIAAcKPgY9GgAjAQAUAAcKeALTRwEWAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAABNQAECn8YAAIbAAgKaA95IgBPAQAbAAgKaA95IgBPAQAAAA==.Chromstrasza:BAABNQAECn8qAAIJAAoK5Q3BEwATAgAJAAoK5Q3BEwATAgAAAA==.Chrîstopher:BAAANQADCggICAAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn81AAMFAAoK2xfdJwBHAgAFAAoK2xfdJwBHAgAeAAEKAAAcMgAwAAAAAA==.',
Co='Comitus:BAABNQAECn81AAIYAAkKCwf2hQBCAQAYAAkKCwf2hQBCAQAAAA==.Conj:BAAANQAECgQIBAAAAA==.Conjarr:BAABNQAECn8vAAIOAAoKGhy3OwB7AgAOAAoKGhy3OwB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECggIJwAfAP8dAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgEIBwAAAA==.Cougarsixsix:BAAANQAECgQIEAAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8tAAIgAAoKog9AWACvAQAgAAoKog9AWACvAQAAAA==.Crypticcurse:BAAANQADCggILQAAAA==.',
Cy='Cynnai:BAABNQAECn8mAAIYAAkKwBxhLQBkAgAYAAkKwBxhLQBkAgAAAA==.',
Da='Dadythickums:BAAANQAECggIEAAAAA==.Daeghrefn:BAAANQADCgYIBgABNQAECgYIBwAHAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgUIEAAHAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8hAAMFAAkKsQ49uQBbAQAFAAcKdQ49uQBbAQAEAAMKiQsDSQClAAAAAA==.Danashal:BAABNQAECn8uAAIKAAkKiwesGQAfAQAKAAkKiwesGQAfAQAAAA==.Dangerranger:BAAANQAECgIIBAAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgYIDAAAAA==.Darrth:BAABNQAECn8oAAMhAAkKDhQxMACsAQAhAAkKDhQxMACsAQAZAAEK2AN10wAqAAAAAA==.Darthbane:BAABNQAECn8aAAMhAAcK3wYyVQAEAQAhAAcKQwYyVQAEAQAgAAUK8wVzTwCjAAAAAA==.Darthjareth:BAAANQADCgYIDAAAAA==.Darthsion:BAAANQADCgEIAQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAHAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQAECgEIAQABNQAECgYIDAAHAAAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn8zAAMOAAoKPxmFHgC3AgAOAAoKPxmFHgC3AgARAAUKSgOyXgCIAAAAAA==.Demontator:BAAANQADCggIDQABNQAECgkJIAAQALkJAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIGAAgKYxYkXgAHAgAGAAgKYxYkXgAHAgAAAA==.Desmádre:BAABNQAECn8aAAMgAAcKPxxaQQAXAgAgAAcKNhtaQQAXAgAZAAYKBxuYTgC7AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn84AAMPAAkKlyNeEAASAwAPAAkKlyNeEAASAwAGAAEKAACCPwEuAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECggIEAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECggIGQAiAGQZAA==.',
Dr='Dravenpryde:BAABNQAECn8eAAIPAAkKYglGgACLAQAPAAkKYglGgACLAQABNQAECgoKLwATALAeAA==.Drbrad:BAAANQAECgUIBAAAAA==.Dreadfists:BAABNQAECn8cAAIhAAoKwhAkOQDvAQAhAAoKwhAkOQDvAQAAAA==.Druen:BAABNQAECn84AAIcAAoKIiHVAgD8AgAcAAoKIiHVAgD8AgAAAA==.Drunkenpo:BAABNQAECn84AAIdAAkKOSD1AwBjAgAdAAkKOSD1AwBjAgAAAA==.Drunkxdemon:BAAANQAECgcIDgAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8ZAAMbAAoKEhkrGACHAgAbAAoKEhkrGACHAgAVAAEKuwTjOQAnAAAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8tAAMGAAoKZxVXRQBhAgAGAAgKmBhXRQBhAgAPAAQKwA+2kADVAAABNQAFFAQIDAALANoZAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgQIEQAAAA==.Dweñde:BAABNQAECn8uAAIFAAkKuA2ucgBJAQAFAAkKuA2ucgBJAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgQIBgAAAA==.',
Ed='Eddiemac:BAAANQAECgYIBgAAAA==.Eddrick:BAABNQAECn8rAAMjAAgKcRpvHQBOAQAQAAgKsBi8eACcAQAjAAcKoRRvHQBOAQAAAA==.Edrid:BAABNQAECn8tAAIUAAkK0h7oIQCdAgAUAAkK0h7oIQCdAgABNQAFFAUIDgAKACocAA==.',
Ei='Eirwen:BAAANQABCgMIAgAAAA==.',
El='Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn8/AAMSAAoKbyNnAQA/AwASAAkKlyNnAQA/AwAOAAEKCCICyABjAAAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAABNQAECn8aAAMjAAgKpBPgHABSAQAQAAcKKBA3wwCVAQAjAAgKsxLgHABSAQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAABNQAECn8XAAIQAAkKIhyOTQCsAgAQAAkKIhyOTQCsAgAAAA==.',
Ev='Evandra:BAABNQAECn8ZAAIPAAgKQhgOSADAAQAPAAgKQhgOSADAAQAAAA==.Evanorah:BAAANQAECgUIDAAAAA==.Eveningstar:BAAANQAECgEIAQAAAA==.',
Fa='Faedeyeda:BAAANQAECgUIDQAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQAECgMIAwABNQAECgkJNAAkAJAbAA==.Figment:BAAANQADCgMIAwAAAA==.Finite:BAAANQAECgEIAQABNQAECgoKOgAYABwcAA==.Firered:BAAANQADCgIIBAABNQAECgQIBwAHAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECgkJHwAPAIQWAA==.Fonta:BAAANQADCgQIBAAAAA==.Fortuna:BAAANQADCgYIBgABNQADCggICgAHAAAAAA==.',
Fr='Frojio:BAABNQAECn8YAAIhAAgKtgvvSgCOAQAhAAgKtgvvSgCOAQAAAA==.Frosten:BAAANQADCggISQAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgMIAwAAAA==.Gaff:BAABNQAECn8hAAIYAAkKGBQOdwBmAQAYAAkKGBQOdwBmAQAAAA==.Galia:BAAANQAECgYIBgAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Go='Gobby:BAAANQAECgYIBwABNQAECggIGQAiAGQZAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYIDgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQARAAsRAA==.',
Ha='Hadin:BAABNQAECn8rAAIUAAkKZx8mRQAZAgAUAAkKZx8mRQAZAgAAAA==.Halalnt:BAAANQAECgUIDgABNQAECgUIEQAHAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAIAGkaAA==.Hamster:BAAANQAECgEIAQABNQAECgkJLwAJADwWAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn80AAITAAkKDRj5EwAkAgATAAkKDRj5EwAkAgAAAA==.Harsaiah:BAAANQADCgYICAABNQAECggIHQAlAIweAA==.Hazenpryde:BAABNQAECn8vAAITAAoKsB4gCQDlAgATAAoKsB4gCQDlAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIHQABNQAECgkJJgAmAA0ZAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Heckboy:BAAANQAECgEIAQABNQAECgcIGQAZAFkZAA==.Hephaistian:BAABNQAECn80AAIDAAoK9hW8UwB2AgADAAoK9hW8UwB2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8nAAIFAAkKhhsHMwAVAgAFAAkKhhsHMwAVAgAAAA==.',
Hy='Hysgar:BAAANQAECgUIEAABNQAECggIHQAlAIweAA==.',
Ic='Icetiger:BAAANQADCgUIBgAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8xAAMRAAoKERtVDQBUAgARAAoKERtVDQBUAgAOAAUKghY5mgBGAQAAAA==.Imperion:BAAANQABCgIIAgAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn86AAMYAAoKHBxgMABXAgAYAAoKHBxgMABXAgAnAAEKAAAIRgAAAAAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgYICQAAAA==.',
Ja='Jackfruit:BAABNQAECn8hAAMQAAkK9A212ABqAQAQAAgKDAq12ABqAQAlAAYKLgndgQAAAQAAAA==.Jaod:BAAANQADCgYIHAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIBQAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kaedor:BAAANQAECgEIAQAAAA==.Kahnrah:BAAANQAECgEIAQAAAA==.Kalarae:BAAANQAECgcICgAAAA==.Kaljeer:BAABNQAECn8mAAIMAAkKdhTOPwC4AQAMAAkKdhTOPwC4AQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kalmyk:BAAANQAECgcIDQAAAA==.Kaltharion:BAAANQAECgIIAgAAAA==.Kaluren:BAACNQAFFH8OAAIlAAUKyyDECADWAQAlAAUKyyDECADWAQA1AAQKfyoAAyUACQqtJi4BAOEDACUACQqtJi4BAOEDABAABQosIPXiAFUBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8aAAMFAAkK4QvkmgCjAQAFAAkKTwnkmgCjAQAEAAIKeBFpWQB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8pAAIdAAkKWiPSAwBKAwAdAAkKWiPSAwBKAwAAAA==.Kapp:BAAANQAECgYIEAAAAA==.Karabar:BAABNQAECn87AAMjAAoKCh9uCgBhAgAjAAoKCh9uCgBhAgAQAAEKAAB7pQEAAAAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAHAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAHAAAAAA==.Karnnagexxl:BAAANQAECgQIAwABNQAECgQIBQAHAAAAAA==.Kasarra:BAAANQAECgYIEQAAAA==.Kayiku:BAAANQADCggIJAAAAA==.Kazagol:BAABNQAECn8vAAIXAAoKjBh1HABxAgAXAAoKjBh1HABxAgAAAA==.',
Ke='Kezzi:BAAANQADCgcIBgAAAA==.',
Kh='Khamaracy:BAABNQAECn8bAAIEAAYKhgjvEwCgAAAEAAYKhgjvEwCgAAAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAABNQAECn8jAAIQAAgKJhh6hAAfAgAQAAgKJhh6hAAfAgAAAA==.',
Kr='Kryptus:BAABNQAECn8zAAIUAAoKVBkVQgAiAgAUAAoKVBkVQgAiAgAAAA==.',
Ku='Kurick:BAABNQAECn8dAAQlAAgKjB5TcwC+AQAlAAUK6SFTcwC+AQAQAAcK4RiIoQBKAQAjAAEKAxAMVQA6AAAAAA==.Kurshak:BAABNQAECn8zAAMoAAoKfhZVNQA/AgAoAAoKfhZVNQA/AgAcAAEKKglVPQAxAAAAAA==.',
Ky='Kyngizzard:BAAANQAECgUIEQAAAA==.',
La='Latte:BAAANQAECgcIEwAAAA==.',
Le='Lenity:BAABNQAECn8oAAIMAAcKawwmYQA1AQAMAAcKawwmYQA1AQAAAA==.',
Li='Lichboom:BAAANQAECgEIAgABNQAECggIJwAfAP8dAA==.',
Lo='Loan:BAAANQADCggIGwABNQAECgkJLwAJADwWAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgYIEgAAAA==.Longtrail:BAAANQAECgEIAgAAAA==.Lookatchu:BAAANQADCgIIAgAAAA==.',
Lu='Lucoryphus:BAAANQAECgYIBwAAAA==.Lukeduke:BAACNQAFFH8OAAInAAUKnxwxAgCJAQAnAAUKnxwxAgCJAQA1AAQKfycAAicACQrKIwsEAE8DACcACQrKIwsEAE8DAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAUIDgAnAJ8cAA==.Lunaries:BAAANQAECgEIAQAAAA==.Lunä:BAABNQAECn8pAAMPAAoKpxs3HQChAgAPAAoKpxs3HQChAgAGAAQKlAilowCNAAAAAA==.',
Ly='Lydia:BAABNQAECn8sAAMUAAkKRBcswgAAAgAUAAgKrhQswgAAAgAIAAIKEBzMKwCcAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICgAHAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgUIDAAAAA==.',
Ma='Malcontent:BAAANQAECgQIBAABNQAECggIGQAiAGQZAA==.Malfeasance:BAAANQADCgUIBQABNQAECggIGQAiAGQZAA==.Malifel:BAABNQAECn8ZAAMiAAgKZBlpCAC1AQAiAAcKfRhpCAC1AQAXAAcKFQ/4NgCMAQAAAA==.Mallord:BAAANQAECgQIBAABNQAECggIGQAiAGQZAA==.Malstrom:BAAANQAECgMIBAABNQAECggIGQAiAGQZAA==.Mandarin:BAABNQAECn8XAAMmAAcKmBABJwBsAQAmAAcKmBABJwBsAQAoAAEK0wEAjAAOAAAAAA==.Mararose:BAAANQABCgQIBgAAAA==.Marashades:BAABNQAECn8eAAQZAAgKnB70KgBvAgAZAAgKnB70KgBvAgAhAAMKAQbQjgBTAAAgAAEKdwu1dgA8AAAAAA==.Marsali:BAAANQAECgIIAQAAAA==.',
Me='Melabrin:BAABNQAECn8mAAIFAAkKIQyNYAB5AQAFAAkKIQyNYAB5AQAAAA==.Mercia:BAABNQAECn8mAAIjAAoKdB6zDwCiAgAjAAoKdB6zDwCiAgAAAA==.Mercý:BAAANQADCggIIAAAAA==.Merekoma:BAABNQAECn8eAAIXAAgK1hZnKgDvAQAXAAgK1hZnKgDvAQAAAA==.',
Mi='Mieena:BAAANQABCgUIBQAAAA==.Milhouse:BAAANQAECgIIBQAAAA==.Mingonashoba:BAAANQAECgIICAAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAABNQAECn8bAAMbAAgKaguONwBYAQAbAAcK3QuONwBYAQAVAAUKKQJKQQBvAAAAAA==.Mistaricky:BAABNQAECn8ZAAMYAAgKhRMMewBcAQAYAAgKhRMMewBcAQAfAAEKxAj3NAAxAAAAAA==.',
Mo='Moadeed:BAABNQAECn8VAAITAAcKDhEsLAA3AQATAAcKDhEsLAA3AQAAAA==.Moongazer:BAAANQAECgMIBQAAAA==.Morassabe:BAAANQADCggIDwAAAA==.Morphmious:BAABNQAECn83AAIcAAoK7B28CgDgAQAcAAoK7B28CgDgAQAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgYIDwAAAA==.',
My='Mycenaean:BAAANQAECgEIAQABNQAFFAIIBwAdADEZAA==.Myroku:BAAANQAECgEIAQABNQAECggIGQAiAGQZAA==.Myrrh:BAABNQAECn8qAAMKAAoKOgblJACZAQAKAAoKOgblJACZAQAJAAIKTwQCHABiAAAAAA==.Mysklef:BAAANQAECgIIAgABNQAECggIHQAlAIweAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICgAHAAAAAA==.Nausican:BAAANQAECgMIBAAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgkJJgAPAAEiAA==.Necrosector:BAABNQAECn8yAAIQAAkK7R2rJgCgAgAQAAkK7R2rJgCgAgAAAA==.Nelandra:BAABNQAECn8XAAIRAAYKgBGBLQDhAAARAAYKgBGBLQDhAAAAAA==.Neongrasp:BAABNQAECn8YAAIgAAoK4xOJIACqAQAgAAoK4xOJIACqAQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAQIDAALANoZAA==.',
No='Nobara:BAAANQAECgcICQABNQAECgoKMQAgAKwiAA==.Nomahuata:BAABNQAECn89AAIGAAoK7A46aADoAQAGAAoK7A46aADoAQAAAA==.',
Nu='Nufrus:BAABNQAECn8WAAIDAAgKoQdt0ABgAQADAAgKoQdt0ABgAQAAAA==.Nurgle:BAAANQADCgUICQAAAA==.',
Ny='Nyeli:BAABNQAECn8XAAIDAAYK4RB2xwBzAQADAAYK4RB2xwBzAQABNQAECgYIGgAPAMIPAA==.Nyxi:BAAANQAECgYIEQAAAA==.',
['Né']='Néo:BAAANQAECgMIBAAAAA==.',
Oc='Octavios:BAAANQAECgQIBQAAAA==.',
Om='Ommeta:BAAANQAFFAMIAwABNQAFFAQICAAoAGYIAA==.',
On='Onefiftyone:BAABNQAECn80AAQkAAkKkBtTCwAxAgAkAAkKkBtTCwAxAgAPAAYK0xRvqQAeAQAGAAEKAAD7PAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgUIDgAAAA==.Paltator:BAABNQAECn8gAAIQAAkKuQnGogBHAQAQAAkKuQnGogBHAQAAAA==.Pandazuken:BAABNQAECn8tAAIGAAoK+Rl1RgBcAgAGAAoK+Rl1RgBcAgAAAA==.Paradots:BAACNQAFFH8OAAIKAAQKFgxiCwD5AAAKAAQKFgxiCwD5AAA1AAQKf0EAAgoACgrSHGYEACEDAAoACgrSHGYEACEDAAAA.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAABNQAECn8nAAIfAAgK/x3aBQC8AgAfAAgK/x3aBQC8AgAAAA==.Pastlives:BAAANQAECgUIDgAAAA==.',
Ph='Phantasee:BAAANQADCgQIBAAAAA==.Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgYIDAAHAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQAECggIBgAAAA==.Pixystix:BAAANQAECgQIEQABNQAECggIBgAHAAAAAA==.',
Po='Pomortem:BAABNQAECn8ZAAIZAAcKWRlRNQBIAQAZAAcKWRlRNQBIAQAAAA==.Potsomancy:BAACNQAFFH8MAAIUAAYK1RoODwAAAgAUAAYK1RoODwAAAgA1AAQKfx8AAhQACQokJP1IAPECABQACQokJP1IAPECAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQAECgQIBAABNQAECgUICQAHAAAAAA==.Raivel:BAABNQAECn8aAAIPAAYKwg/AdAAhAQAPAAYKwg/AdAAhAQAAAA==.Rambogg:BAAANQADCgMIAwABNQAFFAcIEQAUAMoIAA==.Raneyth:BAAANQAECgYIDwAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQAECgEIAQABNQAECgoKRgAWABAVAA==.Ravusternath:BAAANQADCggIFQAAAA==.',
Re='Redwinetoast:BAAANQAECgUICwAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8vAAQJAAkKPBYZCADaAQAJAAkKPBYZCADaAQAKAAMKOg+ZPwCjAAApAAEKAAAAJQAxAAAAAA==.Reposess:BAAANQABCggIFAAAAA==.Reshyk:BAAANQAECgYICQAAAA==.',
Rh='Rhobes:BAAANQADCggIJAAAAA==.Rhondta:BAAANQAECgIIAgAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAABNQAECn8aAAIlAAgKbAejbQA7AQAlAAgKbAejbQA7AQAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAHAAAAAA==.Roflwhat:BAAANQAECgIIAgAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIHAAAAA==.',
Ru='Rumor:BAABNQAECn8mAAMmAAkKDRn9EgBQAgAmAAkKDRn9EgBQAgAoAAQKvghLagBdAAAAAA==.Rurry:BAACNQAFFH8OAAIKAAUKKhzQCACsAQAKAAUKKhzQCACsAQA1AAQKfyYAAwoACQqQI9EDAHgDAAoACQqQI9EDAHgDAAkAAQohJeI0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn8xAAMgAAoKrCKcFAAUAwAgAAoKrCKcFAAUAwAZAAIKMgpeugBTAAAAAA==.Ryuuko:BAAANQAECggICAAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8MAAMLAAQK2hn8AwD1AAALAAMK2hn8AwD1AAAMAAIKIBCXHwBOAAA1AAQKfzEAAwsACgrJIqcGAGgDAAsACgoAIacGAGgDAAwABwqtEuApAHUBAAAA.',
Sa='Sabastion:BAAANQADCgMIAwABNQAECggIGQAiAGQZAA==.Sableanne:BAAANQAECgMIAwAAAA==.Safetysham:BAAANQAECgMIBQAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYIBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAHAAAAAA==.Salmoo:BAABNQAECn8fAAIPAAkKhBZwLwAyAgAPAAkKhBZwLwAyAgAAAA==.Saltytator:BAAANQAECgMIBgABNQAECgkJIAAQALkJAA==.Santhon:BAAANQADCgQICAAAAA==.Satanized:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggIKAAAAA==.',
Sc='Scaledaddy:BAABNQAECn8rAAMpAAoKyglGDACUAQApAAkKcApGDACUAQAJAAQK3AbdMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECgoKOgABAOEjAA==.Scaryl:BAABNQAECn8WAAIoAAUKuwX+fADYAAAoAAUKuwX+fADYAAAAAA==.Schneè:BAABNQAECn9BAAInAAoKhBW5DwCBAQAnAAoKhBW5DwCBAQAAAA==.Scoom:BAACNQAFFH8OAAIUAAUK5hyfGgCmAQAUAAUK5hyfGgCmAQA1AAQKfy8AAhQACQoFJcYZAG4DABQACQoFJcYZAG4DAAAA.Scourgespawn:BAACNQAFFH8LAAMhAAUKlhmoBwB+AQAhAAUKlhmoBwB+AQAgAAEKAADhIwA9AAA1AAQKfyoAAyEACQoeJMwQAAkDACEACQoeJMwQAAkDACAABAogEcOYAM8AAAAA.',
Se='Seikyo:BAABNQAECn87AAIZAAoK5wzwMwBOAQAZAAoK5wzwMwBOAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgUIEQAHAAAAAA==.Selenë:BAABNQAECn8WAAIOAAgKdRJskABlAQAOAAgKdRJskABlAQAAAA==.Serok:BAAANQAECggIEAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcICgAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAHAAAAAA==.Shalis:BAAANQAECgYIDwAAAA==.Sharivee:BAAANQAECgYIDAAAAA==.Shazamir:BAABNQAECn8WAAIkAAcK4gRBIwAoAQAkAAcK4gRBIwAoAQAAAA==.Shibui:BAABNQAECn84AAIWAAkK4RO9IQDBAQAWAAkK4RO9IQDBAQAAAA==.Shifthead:BAACNQAFFH8IAAIoAAQKZgihEQC4AAAoAAQKZgihEQC4AAA1AAQKfy8AAxwACgoEGLgNAD4CABwACAoAGbgNAD4CACgACgodEag5ACMCAAAA.Shockazilla:BAABNQAECn8nAAIlAAkKHiLdHAAAAwAlAAkKHiLdHAAAAwAAAA==.Shortspanky:BAAANQAECgQIDwAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAABNQAECn8XAAIQAAcKKRJYvACkAQAQAAcKKRJYvACkAQAAAA==.',
Sk='Skoduh:BAABNQAECn8eAAIDAAgKAxRTYQC9AQADAAgKAxRTYQC9AQAAAA==.',
Sl='Slack:BAABNQAECn8cAAMOAAgKCCOXHgC2AgAOAAgKCCOXHgC2AgARAAEKAACecABHAAABNQAECgkJLwAJADwWAA==.Sluggo:BAACNQAFFH8MAAIQAAUK3xHUDAB+AQAQAAUK3xHUDAB+AQA1AAQKfyYAAhAACQrUICVTAJwCABAACQrUICVTAJwCAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIAgAAAA==.',
Sp='Spiralist:BAAANQAECgYIDgAAAA==.Spìne:BAAANQAECgQIBQAAAA==.',
St='Steelforged:BAAANQADCgQIBAABNQAECggIGAAbAGgPAA==.Stonedalways:BAAANQAECgYIEgAAAA==.Stonytoni:BAAANQAECgMIAgAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQABNQAECgoKGAAaAKwQAA==.Sunfuri:BAABNQAECn8bAAIfAAgK0ATFGwDsAAAfAAgK0ATFGwDsAAAAAA==.Sus:BAACNQAFFH8NAAIWAAUKXBTcCgB1AQAWAAUKXBTcCgB1AQA1AAQKfyYAAxYACQrKIvIZAMsCABYACQrKIvIZAMsCACIABAp1C0giALAAAAAA.Susanoo:BAAANQAECggIDwAAAA==.',
Ta='Taalia:BAABNQAECn8aAAIPAAYKHgzcfgAEAQAPAAYKHgzcfgAEAQAAAA==.Talonas:BAABNQAECn8YAAMIAAgKDBgZCwCnAQAIAAgKKxYZCwCnAQAUAAYKyBf/AwGHAAAAAA==.Tarathor:BAAANQAECgUIEwAAAA==.Tatortott:BAAANQAECggIDQABNQAECgkJIAAQALkJAA==.',
Te='Teknofarious:BAABNQAECn8eAAMaAAkK7QvnAgBqAQAaAAkK7QvnAgBqAQAIAAEKAAAmSwAvAAAAAA==.',
Th='Thesafe:BAAANQAECgYIDQAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAABNQAECn8UAAMIAAYKTR1sDAD0AQAIAAYKTR1sDAD0AQAUAAQKYgaHfgHGAAABNQAECgkJLwAJADwWAA==.Thialaa:BAABNQAECn8aAAInAAkK0BdkCgDqAQAnAAkK0BdkCgDqAQABNQAECgoKNwADAO8hAA==.Thialia:BAABNQAECn8wAAIOAAoK2Q8cSADfAQAOAAoK2Q8cSADfAQABNQAECgoKNwADAO8hAA==.Thialiaa:BAAANQAECgQIEQABNQAECgoKNwADAO8hAA==.Thialiadin:BAABNQAECn8eAAIjAAkKwxZzEgDFAQAjAAkKwxZzEgDFAQABNQAECgoKNwADAO8hAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn87AAISAAoK+xwsAQACAwASAAoK+xwsAQACAwAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAQIDAALANoZAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgYIEAAAAA==.Trema:BAABNQAECn9IAAMjAAoKPxgWFQBZAgAjAAgKpBwWFQBZAgAQAAoK9ws8uACtAQAAAA==.Trialei:BAAANQABCgIIAgAAAA==.Trick:BAAANQAECgYICQABNQAECgoKRAAcAAgmAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAABNQAECn8VAAMmAAgKFQ/jPwAnAQAmAAgKFQ/jPwAnAQAoAAQKYRSVSwDDAAABNQAECgoKPAALADIhAA==.',
Tu='Tulsi:BAAANQAECgcIDgAAAA==.',
Ty='Tyronos:BAABNQAECn8ZAAIQAAoKKg8efQCTAQAQAAoKKg8efQCTAQAAAA==.',
Va='Vaeltharion:BAAANQAECgUIEAAAAA==.Varedrae:BAAANQADCggIFQAAAA==.Vas:BAAANQADCgYIFAAAAA==.Vaydark:BAAANQADCgQIBAABNQAECgkJOAAWAOETAA==.',
Ve='Verdandi:BAAANQAECgUICgAAAA==.Vesperr:BAAANQAECgEIAQAAAA==.Vevicenth:BAABNQAECn8fAAMaAAkKBgWsBgDoAAAUAAgKqASQowAxAQAaAAYKZgOsBgDoAAAAAA==.',
Vo='Voranth:BAABNQAECn8mAAMPAAkKASKrEgD4AgAPAAkKASKrEgD4AgAGAAQKIBItxgAGAQAAAA==.',
Wa='Wainstatick:BAAANQAECgQIBAAAAA==.Wakeko:BAAANQAECgQIBQABNQAECgYIFgAYAMATAA==.Warenio:BAABNQAECn8jAAMnAAkKoBZTEAAjAgAnAAkKoBZTEAAjAgAYAAEKsAFyHQEfAAAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMIAAkKaRqLCwAIAgAIAAkKfRaLCwAIAgAUAAYKrR0SzwDoAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECggIGwAbAGoLAA==.',
Wh='Whakan:BAAANQADCggIIgABNQAECgYIBwAHAAAAAA==.',
Wi='Williamgoat:BAAANQAECgQICAABNQAECgoKPAALADIhAA==.',
Wo='Wolfos:BAAANQAECgIICgAAAA==.',
Wt='Wtfox:BAEBNQAECn8lAAIRAAkKWBAfGwCBAQARAAkKWBAfGwCBAQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAABNQAECn8fAAMXAAkK0Q3bHACJAQAXAAkK0Q3bHACJAQAWAAMKfATYdQAzAAAAAA==.',
Xa='Xalatos:BAAANQAECggIEQAAAA==.Xalfein:BAAANQADCggILAAAAA==.',
Xi='Xinu:BAAANQAECgQIBAABNQAECgkJNAADAPwbAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Xy='Xylendra:BAAANQAECgYIDQABNQAECggIHAAbAPcGAA==.',
Ya='Yanakana:BAAANQAECgUIDAAAAA==.',
Yd='Ydrassil:BAAANQAECggICgABNQAECgkJFwAQACIcAA==.',
Za='Zakeko:BAABNQAECn8WAAMYAAYKwBNbrQDoAAAYAAYKwBNbrQDoAAAnAAEKAAD6PQBLAAAAAA==.Zanderpryde:BAABNQAECn8eAAIOAAkK6QnYWgCYAQAOAAkK6QnYWgCYAQABNQAECgoKLwATALAeAA==.Zariak:BAAANQABCgIIAgAAAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAABNQAECn8lAAIDAAkKBxOqQQAYAgADAAkKBxOqQQAYAgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn80AAIDAAkK/BsDNgA/AgADAAkK/BsDNgA/AgAAAA==.Zivalisse:BAAANQAECgQIBwAAAA==.',
Zo='Zota:BAABNQAECn8eAAIDAAkKjhRWVQDfAQADAAkKjhRWVQDfAQAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECggIHQAlAIweAA==.Zulfionn:BAABNQAECn8dAAIDAAcKIQcVmwA3AQADAAcKIQcVmwA3AQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgkJLwAJADwWAA==.',
['Áy']='Áyrá:BAABNQAECn8XAAIlAAgKcRH6XgBqAQAlAAgKcRH6XgBqAQAAAA==.',
['Øu']='Øuroboros:BAAANQAECgQIBwAAAA==.',
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
