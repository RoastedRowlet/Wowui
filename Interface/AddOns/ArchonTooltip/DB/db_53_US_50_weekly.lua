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
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn86AAMBAAoK4SOPAQDnAgABAAoK4SOPAQDnAgACAAEKlhJ5gQBBAAAAAA==.',
Ad='Adorian:BAAANQAECgIIBQAAAA==.Adros:BAAANQAECgEIAQAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxMtEgBAAQADAAQK+BYtEgBAAQACAAIKegarHwB1AAA1AAQKfyUAAwIACQpTHzIoAAgCAAIACArNGjIoAAgCAAMABAq0HeDhAD0BAAAA.',
Ae='Aelfwine:BAABNQAECn8aAAIDAAcKmAabzAD+AAADAAcKmAabzAD+AAAAAA==.',
Ai='Ailaith:BAABNQAECn8/AAMDAAoK1SOgCQA4AwADAAoK1SOgCQA4AwACAAIKAAB6egBYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn9HAAMEAAoKnSFKCQBlAgAEAAcKuRtKCQBlAgAFAAgK1yA2RQDzAQAAAA==.Akibafaris:BAAANQAECggIBwABNQAECggIGgAGAGMWAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAgABNQAECgUIBQAHAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQAECgIIAgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAHAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAHAAAAAA==.Alirik:BAAANQADCgUIBwAAAA==.Alishia:BAAANQAECgEIAQAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICwAHAAAAAA==.Alydrostage:BAABNQAECn8hAAIIAAkK8gu+EwBtAQAIAAkK8gu+EwBtAQAAAA==.Alystriaz:BAABNQAECn8hAAMJAAgK/wkmEAAlAQAJAAgK/wkmEAAlAQAKAAQK2gc4MQBgAAAAAA==.Alzheimerz:BAABNQAECn9AAAQLAAoKlSIjDQAcAwALAAoKOh4jDQAcAwAMAAcK7B6mLgAvAgANAAIKZBfqFgB4AAAAAA==.',
Am='Amaelalin:BAABNQAECn84AAIOAAkKVxd2QwAVAgAOAAkKVxd2QwAVAgAAAA==.Amatoria:BAABNQAECn8WAAMOAAcKaQ8NdgBgAQAOAAcKaQ8NdgBgAQAPAAUK5Qv7TADhAAAAAA==.',
An='Ananiel:BAAANQABCgcICAABNQAECgIIAgAHAAAAAA==.Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAHAAAAAA==.Andaya:BAACNQAFFH8JAAIQAAIK+RxaHACoAAAQAAIK+RxaHACoAAA1AAQKfzAAAxAACgrRHBgrALYCABAACgrRHBgrALYCAAYAAQoAANgXAQAAAAAA.Andemeli:BAABNQAECn8fAAIRAAcKEQeU/ADZAAARAAcKEQeU/ADZAAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgMIBQAAAA==.',
Ar='Arandis:BAABNQAECn8hAAMPAAgKngqvJwAvAQAPAAgKngqvJwAvAQASAAEKCQXgLQApAAAAAA==.Arcblade:BAAANQAECgIIAgABNQAECgoKOQATAAgiAA==.Arcianna:BAABNQAECn85AAITAAoKCCJGBgDkAgATAAoKCCJGBgDkAgAAAA==.Arctica:BAABNQAECn8dAAIUAAcKqQR56wDFAAAUAAcKqQR56wDFAAAAAA==.Arjurn:BAABNQAECn86AAIUAAoKpR1CMgBtAgAUAAoKpR1CMgBtAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn89AAIVAAoKACVEAQADBAAVAAoKACVEAQADBAAAAA==.Artymiss:BAAANQAECgcIEQAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Aurturious:BAAANQADCgYIBgAAAA==.Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn8/AAIDAAoKkx+YGQDSAgADAAoKkx+YGQDSAgAAAA==.',
Ay='Ayorana:BAAANQAECgQIBAAAAA==.',
Az='Azshura:BAAANQAECgcIEgAAAA==.Azzinôth:BAABNQAECn9KAAMWAAoKEBXnHwD3AQAWAAoKEBXnHwD3AQAXAAcKpg7nOAB9AQAAAA==.',
['Aí']='Aírk:BAAANQAECgEIAQAAAA==.',
Ba='Baldr:BAABNQAECn8fAAIRAAoKLApNxQCRAQARAAoKLApNxQCRAQAAAA==.Balgar:BAABNQAECn8dAAIDAAgK3R1GVQByAgADAAgK3R1GVQByAgAAAA==.Balghas:BAAANQAECggIDgAAAA==.Bammz:BAABNQAECn8yAAIYAAoKjR84PQDTAgAYAAoKjR84PQDTAgABNQAECggIFAAPACYaAA==.Bastia:BAAANQAECgEIAQAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAHAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAABNQAECn8YAAIRAAgKGRueVACYAgARAAgKGRueVACYAgAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn8uAAIDAAoKNRgmOQBXAgADAAoKNRgmOQBXAgAAAA==.Bloodytusks:BAAANQAECgEIAQAAAA==.',
Bo='Boomchick:BAAANQADCggIEAABNQAECggIDAAHAAAAAA==.Borian:BAAANQADCggICAAAAA==.Borrkbuster:BAABNQAECn8XAAINAAkKhRI6AwCsAQANAAkKhRI6AwCsAQAAAA==.Botkin:BAAANQAECgIIAgAAAA==.Bowan:BAAANQADCgYIBgAAAA==.',
Br='Brenri:BAAANQAECgcIDgAAAA==.Brewtality:BAAANQAECgQIBQABNQAFFAUIEAAKANEKAA==.Brodysseus:BAAANQAECgcIBwAAAA==.Brudanature:BAAANQADCgUIBQABNQAECgcIGQAZAFkZAA==.Brughe:BAABNQAECn8cAAIDAAkKJRHsdwAfAgADAAkKJRHsdwAfAgAAAA==.Brywynn:BAAANQADCggIFAABNQAECggIGgADAKoNAA==.',
Bu='Bubbleoseven:BAABNQAECn8UAAMOAAcKVxtRUwApAgAOAAcKVxtRUwApAgASAAEKjRAEKAA1AAABNQAFFAUIEAAKANEKAA==.Bumhug:BAAANQAECgUICAABNQAECgoKQAALAJUiAA==.Burnbabyburn:BAABNQAECn8YAAIaAAoKrBAKAwDlAQAaAAoKrBAKAwDlAQAAAA==.Burntbum:BAAANQADCggICAABNQAECgoKIgARAAEKAA==.Buttacutta:BAAANQADCggIPQAAAA==.',
Ca='Cahoots:BAABNQAECn8tAAIbAAoKjx4LDgD9AgAbAAoKjx4LDgD9AgAAAA==.Camaracy:BAAANQADCgYIBgAAAA==.Caneste:BAACNQAFFH8JAAIPAAQKCxFkCwA4AQAPAAQKCxFkCwA4AQA1AAQKfycAAg8ACQodIjAJAEsDAA8ACQodIjAJAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8qAAIcAAoK5xXNEQDkAQAcAAoK5xXNEQDkAQAAAA==.Cayleynne:BAACNQAFFH8JAAIdAAIKMRl0BgCSAAAdAAIKMRl0BgCSAAA1AAQKfykAAh0ACgoIIAMFABgDAB0ACgoIIAMFABgDAAAA.',
Ce='Celestyl:BAABNQAECn8bAAIUAAUKSASVGAF8AAAUAAUKSASVGAF8AAAAAA==.Cernos:BAAANQADCgMIAwAAAA==.Cerwynne:BAAANQAFFAEIAQAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAgAAAA==.Cheapbeerz:BAABNQAECn8mAAMIAAkKcQY9GgAjAQAIAAgKYgY9GgAjAQAUAAcKeALTRwEWAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAABNQAECn8aAAIbAAgKaA/UJgBLAQAbAAgKaA/UJgBLAQAAAA==.Chromstrasza:BAABNQAECn8qAAIJAAoK5Q3BEwATAgAJAAoK5Q3BEwATAgAAAA==.Chrîstopher:BAAANQADCggICAAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn88AAMFAAoK0Bm1IwB0AgAFAAoK0Bm1IwB0AgAeAAEKAAAcMgAwAAAAAA==.',
Co='Comitus:BAABNQAECn84AAIYAAkKCwd1lQBAAQAYAAkKCwd1lQBAAQAAAA==.Conj:BAAANQAECgQIBQAAAA==.Conjarr:BAABNQAECn8vAAIOAAoKGhy3OwB7AgAOAAoKGhy3OwB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECggIJwAfAP8dAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgEIBgAAAA==.Cougarsixsix:BAABNQAECn8WAAIgAAUKfx9rIwA9AQAgAAUKfx9rIwA9AQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8tAAIhAAoKog9AWACvAQAhAAoKog9AWACvAQAAAA==.Crypticcurse:BAAANQADCggILQAAAA==.',
Cy='Cynnai:BAABNQAECn8mAAIYAAkKwBw4NQBcAgAYAAkKwBw4NQBcAgAAAA==.',
['Cå']='Cåstiel:BAAANQAECgEIAwAAAA==.',
Da='Dadythickums:BAAANQAECggICwAAAA==.Daeghrefn:BAAANQADCgYIBgABNQAECgUICgAHAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgUIEAAHAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8hAAMFAAkKsQ49uQBbAQAFAAcKdQ49uQBbAQAEAAMKiQsDSQClAAAAAA==.Danashal:BAABNQAECn8uAAIKAAkKiwfbHAAbAQAKAAkKiwfbHAAbAQAAAA==.Dangerranger:BAAANQAECgIIBAAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgYIDQAAAA==.Darrth:BAABNQAECn8pAAMiAAoKrxRiKgD3AQAiAAoKrxRiKgD3AQAZAAEK2AN10wAqAAAAAA==.Darthbane:BAABNQAECn8aAAMiAAcK3wYoXwAEAQAiAAcKQwYoXwAEAQAhAAUK8wWkVQCiAAAAAA==.Darthjareth:BAAANQADCgYIDAAAAA==.Darthsion:BAAANQADCgEIAQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAHAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQAECgEIAQABNQAECgYIDQAHAAAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn81AAMOAAoKPxnjJQCnAgAOAAoKPxnjJQCnAgAPAAUKdwSyXgCIAAAAAA==.Demontator:BAAANQADCggIDQABNQAECgoKIgARAAEKAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIGAAgKYxYkXgAHAgAGAAgKYxYkXgAHAgAAAA==.Desmádre:BAABNQAECn8aAAMhAAcKPxxaQQAXAgAhAAcKNhtaQQAXAgAZAAYKBxuYTgC7AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn9AAAMQAAoK3CMWCQB7AwAQAAoK3CMWCQB7AwAGAAMK4hBhxABwAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.Distiffany:BAAANQAECgEIAQABNQAECgIIAwAHAAAAAA==.',
Dj='Djthelock:BAAANQAECggIEgAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgkJGgAjABYWAA==.',
Dr='Dravenpryde:BAABNQAECn8eAAIQAAkKYglGgACLAQAQAAkKYglGgACLAQABNQAECgoKLwATALAeAA==.Drbrad:BAAANQAECgUIBgAAAA==.Dreadfists:BAABNQAECn8cAAIiAAoKwhAkOQDvAQAiAAoKwhAkOQDvAQAAAA==.Druen:BAABNQAECn85AAIcAAoKIiGmAwDyAgAcAAoKIiGmAwDyAgAAAA==.Drunkenpo:BAABNQAECn88AAQdAAoKIh6BBABhAgAdAAkKOSCBBABhAgAVAAIKfgxMNABYAAAbAAEKfQ9cWQA0AAAAAA==.Drunkxdemon:BAAANQAECgcIDgAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8ZAAMbAAoKEhkrGACHAgAbAAoKEhkrGACHAgAVAAEKuwRePgAnAAAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8tAAMGAAoKZxVXRQBhAgAGAAgKmBhXRQBhAgAQAAQKwA/OngDOAAABNQAFFAQIEQALANoZAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAABNQAECn8ZAAMVAAYKABQfHAAxAQAVAAYKABQfHAAxAQAbAAIK/gdQTQBeAAAAAA==.Dweñde:BAABNQAECn82AAIFAAoKZA22aACJAQAFAAoKZA22aACJAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgYIDgAAAA==.',
Ed='Eddiemac:BAAANQAECgYIBgAAAA==.Eddrick:BAABNQAECn8zAAMRAAoKDRmATgAvAgARAAoKXhiATgAvAgAgAAcKYBZOHwBeAQAAAA==.Edrid:BAABNQAECn8xAAIUAAkKlh/lIQCtAgAUAAkKlh/lIQCtAgABNQAFFAUIDgAKACocAA==.',
Ei='Eirwen:BAAANQABCgMIAgAAAA==.',
El='Elleryn:BAAANQADCgYIBgABNQAECggIGgADAKoNAA==.Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn9DAAMSAAoKbyNnAQA/AwASAAkKlyNnAQA/AwAOAAEKCCJA1QBiAAAAAA==.',
Er='Eradrá:BAAANQAECgIIBQAAAA==.Eragon:BAABNQAECn8cAAMgAAgKpBPFIQBKAQARAAcKKBA3wwCVAQAgAAgKsxLFIQBKAQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAABNQAECn8XAAIRAAkKIhyOTQCsAgARAAkKIhyOTQCsAgAAAA==.',
Ev='Evandra:BAABNQAECn8bAAIQAAgKQhgsUgCyAQAQAAgKQhgsUgCyAQAAAA==.Evanorah:BAAANQAECgUIDgAAAA==.Eveningstar:BAAANQAECgEIAQAAAA==.',
Fa='Faedeyeda:BAAANQAECgUIDgAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQAECgYIBwABNQAECgoKOAAkAB0cAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIDAAHAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAgAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAgABNQAECgkJHwAQAIQWAA==.Fonta:BAAANQADCgYIBgAAAA==.Fortuna:BAAANQADCgYIBgABNQAECggIDAAHAAAAAA==.',
Fr='Frojio:BAABNQAECn8YAAIiAAgKtgvvSgCOAQAiAAgKtgvvSgCOAQAAAA==.Frosten:BAAANQADCggISwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgMIBAAAAA==.Gaff:BAABNQAECn8jAAIYAAkKvRQDgwBrAQAYAAkKvRQDgwBrAQAAAA==.Galia:BAAANQAECgYIBgAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQAECgEIBAAAAA==.',
Go='Gobby:BAAANQAECgcIBwABNQAECgkJGgAjABYWAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYIDgAAAA==.Gruzaxx:BAAANQABCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQAPAAsRAA==.',
Ha='Hadin:BAABNQAECn8vAAIUAAoKax5ONABmAgAUAAoKax5ONABmAgAAAA==.Halalnt:BAAANQAECgUIDwABNQAECgcIEwAHAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAIAGkaAA==.Hamster:BAAANQADCgYIBgABNQAECgYIFAAIAE0dAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn84AAITAAoKrxf8FADXAQATAAoKrxf8FADXAQAAAA==.Harsaiah:BAAANQADCgYICAABNQAECggIHQAlAIweAA==.Hazenpryde:BAABNQAECn8vAAITAAoKsB4gCQDlAgATAAoKsB4gCQDlAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIHQABNQAECgkJKQAmAJIaAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAABNQAECn84AAIDAAoK9hW8UwB2AgADAAoK9hW8UwB2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8pAAIFAAkKzBzgOAAeAgAFAAkKzBzgOAAeAgAAAA==.',
Hy='Hysgar:BAAANQAECgUIEQABNQAECggIHQAlAIweAA==.',
Ic='Icetiger:BAAANQADCgUICAAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8xAAMPAAoKERtZDwBQAgAPAAoKERtZDwBQAgAOAAUKghY5mgBGAQAAAA==.Imperion:BAAANQABCgIIAgAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn86AAMYAAoKHBwROQBOAgAYAAoKHBwROQBOAgAnAAEKAAA8TQAAAAAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgYICAAAAA==.',
Ja='Jackfruit:BAABNQAECn8iAAMRAAkK9A212ABqAQARAAgKDAq12ABqAQAlAAYKUQphjgD7AAAAAA==.Jaod:BAAANQADCgYIHAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIBQAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kaedor:BAAANQABCgEIAQAAAA==.Kahnrah:BAAANQAECgEIAgAAAA==.Kalarae:BAAANQAECgcIDAAAAA==.Kaljeer:BAABNQAECn8nAAIMAAoKYhQTOwD5AQAMAAoKYhQTOwD5AQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kalmyk:BAAANQAECgcIDwAAAA==.Kaltharion:BAAANQAECgIIAQAAAA==.Kaluren:BAACNQAFFH8OAAIlAAUKyyDECADWAQAlAAUKyyDECADWAQA1AAQKfyoAAyUACQqtJi4BAOEDACUACQqtJi4BAOEDABEABQosIPXiAFUBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8eAAMFAAoKLAzkmgCjAQAFAAoK7AnkmgCjAQAEAAIKeBFpWQB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8tAAIdAAkKWiPSAwBKAwAdAAkKWiPSAwBKAwAAAA==.Kapp:BAAANQAECgYIEgAAAA==.Karabar:BAABNQAECn87AAMgAAoKCh9oDABWAgAgAAoKCh9oDABWAgARAAEKAACswQEAAAAAAA==.Karnnaged:BAAANQAECgMIBwABNQAECgQIBQAHAAAAAA==.Karnnagex:BAAANQAECgQIBQABNQAECgQIBQAHAAAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAHAAAAAA==.Karnnagexxl:BAAANQAECgQIBQAAAA==.Kasarra:BAABNQAECn8YAAIWAAgKzg6wNwBPAQAWAAgKzg6wNwBPAQAAAA==.Kayiku:BAAANQADCggIJAAAAA==.Kazagol:BAABNQAECn8vAAIXAAoKjBh1HABxAgAXAAoKjBh1HABxAgAAAA==.',
Ke='Kezzi:BAAANQADCgcIBgAAAA==.',
Kh='Khamaracy:BAABNQAECn8gAAIEAAYKOwvOEwCwAAAEAAYKOwvOEwCwAAAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAABNQAECn8nAAIRAAkK8xg5bgDgAQARAAkK8xg5bgDgAQAAAA==.',
Kr='Krobax:BAAANQAECgEIAgAAAA==.Kryptus:BAABNQAECn84AAIUAAoKyhpZQAA+AgAUAAoKyhpZQAA+AgAAAA==.',
Ku='Kuppycake:BAAANQAECgEIAQAAAA==.Kurick:BAABNQAECn8dAAQlAAgKjB5TcwC+AQAlAAUK6SFTcwC+AQARAAcK4RhuvACkAQAgAAEKAxDaXAA4AAAAAA==.Kurshak:BAABNQAECn8zAAMoAAoKfhZVNQA/AgAoAAoKfhZVNQA/AgAcAAEKKgkGRwAvAAAAAA==.',
Ky='Kyngizzard:BAAANQAECgcIEwAAAA==.',
La='Latte:BAABNQAECn8WAAIDAAcK2BWufACmAQADAAcK2BWufACmAQAAAA==.',
Le='Lenity:BAABNQAECn8vAAIMAAcKaww4bgA+AQAMAAcKaww4bgA+AQAAAA==.Lepidolite:BAAANQAECgEIAQAAAA==.',
Lo='Loan:BAAANQADCggIGwABNQAECgYIFAAIAE0dAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgYIEgAAAA==.Longtrail:BAAANQAECgEIAQAAAA==.Lookatchu:BAAANQADCgIIAgAAAA==.',
Lu='Lucoryphus:BAAANQAECgUICgAAAA==.Lukeduke:BAACNQAFFH8OAAInAAUKnxwxAgCJAQAnAAUKnxwxAgCJAQA1AAQKfycAAicACQrKIwsEAE8DACcACQrKIwsEAE8DAAAA.Luketheduke:BAAANQAECgMIBAABNQAFFAUIDgAnAJ8cAA==.Lunaries:BAAANQAECgEIAgAAAA==.Lunä:BAABNQAECn8qAAMQAAoKpxv7IwCOAgAQAAoKpxv7IwCOAgAGAAQKlAgZtACNAAAAAA==.',
Ly='Lydia:BAABNQAECn8uAAMUAAoKNRcswgAAAgAUAAkK+xQswgAAAgAIAAIKEBzMKwCcAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICwAHAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgYIEAAAAA==.',
Ma='Malcontent:BAAANQAECgQIBAABNQAECgkJGgAjABYWAA==.Malfeasance:BAAANQADCgUIBQABNQAECgkJGgAjABYWAA==.Malifel:BAABNQAECn8aAAMjAAkKFhbHCQCwAQAjAAcKfRjHCQCwAQAXAAgK8wz4NgCMAQAAAA==.Mallord:BAAANQAECgQIBAABNQAECgkJGgAjABYWAA==.Malstrom:BAAANQAECgMIBgABNQAECgkJGgAjABYWAA==.Mandarin:BAABNQAECn8YAAMmAAgKAA+UKACOAQAmAAgKAA+UKACOAQAoAAEK0wHRlQAOAAAAAA==.Mararose:BAAANQABCgQIBgAAAA==.Marashades:BAABNQAECn8gAAQZAAgKnB70KgBvAgAZAAgKnB70KgBvAgAiAAMKAQawmwBSAAAhAAEKdwtKfgA8AAAAAA==.Marsali:BAAANQAECgIIAgAAAA==.',
Me='Melabrin:BAABNQAECn8qAAIFAAoKFAyFWQC0AQAFAAoKFAyFWQC0AQAAAA==.Mercia:BAABNQAECn8mAAIgAAoKdB6zDwCiAgAgAAoKdB6zDwCiAgAAAA==.Mercý:BAAANQADCggIIAAAAA==.Merekoma:BAABNQAECn8mAAIXAAkKvxV/IACIAQAXAAkKvxV/IACIAQAAAA==.',
Mi='Mieena:BAAANQABCgUIBQAAAA==.Milhouse:BAAANQAECgIIBwAAAA==.Mingonashoba:BAAANQAECgIICAAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAABNQAECn8dAAMbAAgKaguONwBYAQAbAAcK3QuONwBYAQAVAAUKPwJKQQBvAAAAAA==.Mistaricky:BAABNQAECn8ZAAMYAAgKhRMbigBaAQAYAAgKhRMbigBaAQAfAAEKxAj3NAAxAAAAAA==.',
Mo='Moadeed:BAABNQAECn8VAAITAAcKDhEsLAA3AQATAAcKDhEsLAA3AQAAAA==.Moongazer:BAAANQAECgQIBgAAAA==.Morassabe:BAAANQADCggIDwAAAA==.Morphmious:BAABNQAECn87AAIcAAoKwx7qCwD2AQAcAAoKwx7qCwD2AQAAAA==.Mortesque:BAAANQAECgQICwAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgYIDwAAAA==.',
My='Mycenaean:BAAANQAECgEIAQABNQAFFAIICQAdADEZAA==.Myroku:BAAANQADCggICAABNQAECgkJGgAjABYWAA==.Myrrh:BAABNQAECn8qAAMKAAoKOgblJACZAQAKAAoKOgblJACZAQAJAAIKTwRTHgBhAAAAAA==.Mysklef:BAAANQAECgIIAwABNQAECggIHQAlAIweAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCQAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICwAHAAAAAA==.Nausican:BAAANQAECgMIBAAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgoKJwAQAAIhAA==.Necrosector:BAABNQAECn9EAAIRAAoKviLhEAAgAwARAAoKviLhEAAgAwAAAA==.Nelandra:BAABNQAECn8dAAIPAAcKgRTdJABGAQAPAAcKgRTdJABGAQAAAA==.Neongrasp:BAABNQAECn8YAAIhAAoK4xO2JACnAQAhAAoK4xO2JACnAQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAQIEQALANoZAA==.Nirvelli:BAAANQADCgYIBgABNQAECgIIBQAHAAAAAA==.',
No='Nobara:BAAANQAECgcICAABNQAECgoKNgAhAK8jAA==.Nomahuata:BAABNQAECn8+AAIGAAoK7A46aADoAQAGAAoK7A46aADoAQAAAA==.',
Nu='Nufrus:BAABNQAECn8YAAIDAAgKKwht0ABgAQADAAgKKwht0ABgAQAAAA==.Nurgle:BAAANQADCggIEQAAAA==.',
Ny='Nyeli:BAABNQAECn8aAAIDAAgKqg1SkQB3AQADAAgKqg1SkQB3AQAAAA==.Nyxi:BAABNQAECn8XAAIQAAYKSQupjAD7AAAQAAYKSQupjAD7AAAAAA==.',
['Né']='Néo:BAAANQAECgMIBAAAAA==.',
Oc='Octavios:BAAANQAECgQIBAAAAA==.',
Om='Ommeta:BAABNQAECn8XAAMWAAkKahjtMQBzAQAWAAYKGxjtMQBzAQAXAAUKGRNYOADGAAABNQAFFAQICAAoAGYIAA==.',
On='Onefiddy:BAAANQAECgUIBQABNQAECgoKOAAkAB0cAA==.Onefiftyone:BAABNQAECn84AAQkAAoKHRwWDQAyAgAkAAkKrBsWDQAyAgAQAAcKYBhvqQAeAQAGAAEKAAD7PAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgUIDgAAAA==.Palpetine:BAAANQAECgEIAQAAAA==.Paltator:BAABNQAECn8iAAIRAAoKAQpnmgCDAQARAAoKAQpnmgCDAQAAAA==.Pandazuken:BAABNQAECn8vAAIGAAoK+hl1RgBcAgAGAAoK+hl1RgBcAgAAAA==.Paradots:BAACNQAFFH8QAAIKAAUK0QqmCgA/AQAKAAUK0QqmCgA/AQA1AAQKf0QAAgoACgrSHCEFAB8DAAoACgrSHCEFAB8DAAAA.Paranitis:BAAANQAECgEIAQAAAA==.Paraparaboom:BAABNQAECn8nAAIfAAgK/x3aBQC8AgAfAAgK/x3aBQC8AgAAAA==.Pastlives:BAAANQAECgYIDwAAAA==.',
Ph='Phantasee:BAAANQADCgQIBAAAAA==.Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgYIDQAHAAAAAA==.',
Pi='Pixpax:BAAANQAECgYIDQAAAA==.Pixyofdeath:BAAANQAECggIBgAAAA==.Pixystix:BAABNQAECn8YAAIjAAUKtiDoDABoAQAjAAUKtiDoDABoAQABNQAECggIBgAHAAAAAA==.',
Po='Pomortem:BAABNQAECn8ZAAIZAAcKWRmfOwBEAQAZAAcKWRmfOwBEAQAAAA==.Potsomancy:BAACNQAFFH8MAAIUAAYK1RoODwAAAgAUAAYK1RoODwAAAgA1AAQKfx8AAhQACQokJP1IAPECABQACQokJP1IAPECAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQAECgQIBAABNQAECgUICQAHAAAAAA==.Raivel:BAABNQAECn8gAAIQAAcKsQ6WcwBCAQAQAAcKsQ6WcwBCAQABNQAECggIGgADAKoNAA==.Rambogg:BAAANQADCgMIAwABNQAFFAcIEQAUAMoIAA==.Raneyth:BAAANQAECgYIEwAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQAECgEIAQABNQAECgoKSgAWABAVAA==.Ravusternath:BAAANQADCggIFQAAAA==.',
Re='Rednaa:BAAANQABCgIIAgAAAA==.Redwinetoast:BAAANQAECgUIDAAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8xAAQJAAoKUBjYCADgAQAJAAkKXxfYCADgAQAKAAQKVg2ZPwCjAAApAAEKAAAAJQAxAAABNQAECgYIFAAIAE0dAA==.Reposess:BAAANQABCggIFAAAAA==.Reshyk:BAAANQAECgUICgAAAA==.',
Rh='Rhobes:BAAANQADCggIJAAAAA==.Rhondta:BAAANQADCgEIAQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Rillidan:BAEANQADCgMIAwABNQAECgoKJgAPAJkPAA==.Riordaa:BAABNQAECn8cAAIlAAgKbAeRfAAsAQAlAAgKbAeRfAAsAQAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAHAAAAAA==.Roflwhat:BAAANQAECgIIAgAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIHAAAAA==.',
Ru='Rumor:BAABNQAECn8pAAMmAAkKkhqNEwB4AgAmAAkKkhqNEwB4AgAoAAQKvgjxcQBdAAAAAA==.Rurry:BAACNQAFFH8OAAIKAAUKKhzQCACsAQAKAAUKKhzQCACsAQA1AAQKfyYAAwoACQqQI9EDAHgDAAoACQqQI9EDAHgDAAkAAQohJeI0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn82AAMhAAoKryOcFAAUAwAhAAoKryOcFAAUAwAZAAIKMgpeugBTAAAAAA==.Ryuuko:BAAANQAECggICAAAAA==.',
['Rä']='Rägnårok:BAAANQADCgYIBgAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8RAAMLAAQK2hkaBQDwAAALAAMK2hkaBQDwAAAMAAMK4AkFGwCRAAA1AAQKfzEAAwsACgrJIqcGAGgDAAsACgoAIacGAGgDAAwABwqtEuApAHUBAAAA.',
Sa='Sabastion:BAAANQADCgMIAwABNQAECgkJGgAjABYWAA==.Sableanne:BAAANQAECgYICQAAAA==.Safetysham:BAAANQAECgMIBAAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYIBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAHAAAAAA==.Salmoo:BAABNQAECn8fAAIQAAkKhBbnNwAkAgAQAAkKhBbnNwAkAgAAAA==.Saltytator:BAAANQAECgMIBQABNQAECgoKIgARAAEKAA==.Santhon:BAAANQADCgQICAAAAA==.Satanized:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggILgAAAA==.',
Sc='Scaledaddy:BAABNQAECn8rAAMpAAoKyglGDACUAQApAAkKcApGDACUAQAJAAQK3AbdMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECgoKOgABAOEjAA==.Scaryl:BAABNQAECn8cAAIoAAYKxQWUVQC3AAAoAAYKxQWUVQC3AAAAAA==.Schneè:BAABNQAECn9HAAInAAoKZBY9EQCMAQAnAAoKZBY9EQCMAQAAAA==.Scoom:BAACNQAFFH8OAAIUAAUK5hyfGgCmAQAUAAUK5hyfGgCmAQA1AAQKfy8AAhQACQoFJcYZAG4DABQACQoFJcYZAG4DAAAA.Scourgespawn:BAACNQAFFH8LAAMiAAUKlhmoBwB+AQAiAAUKlhmoBwB+AQAhAAEKAADhIwA9AAA1AAQKfyoAAyIACQoeJMwQAAkDACIACQoeJMwQAAkDACEABAogEcOYAM8AAAAA.',
Se='Seikyo:BAABNQAECn87AAIZAAoK5wwmOgBLAQAZAAoK5wwmOgBLAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgcIEwAHAAAAAA==.Selenë:BAAANQAECgYIEwAAAA==.Sento:BAAANQAECgEIAQAAAA==.Serok:BAAANQAECggIEQAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcIDAAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAHAAAAAA==.Shalis:BAAANQAECgYICwAAAA==.Sharivee:BAAANQAECgUIEQAAAA==.Shazamir:BAABNQAECn8YAAIkAAkKXgVBIwAoAQAkAAkKXgVBIwAoAQAAAA==.Shibui:BAABNQAECn8/AAIWAAoKTBSiHgACAgAWAAoKTBSiHgACAgAAAA==.Shifthead:BAACNQAFFH8IAAIoAAQKZghMFAC3AAAoAAQKZghMFAC3AAA1AAQKfy8AAxwACgoEGLgNAD4CABwACAoAGbgNAD4CACgACgodEag5ACMCAAAA.Shockazilla:BAABNQAECn8nAAIlAAkKHiLdHAAAAwAlAAkKHiLdHAAAAwAAAA==.Shortspanky:BAAANQAECgQIDgAAAA==.',
Si='Silaveen:BAAANQAECgEIBAAAAA==.Silverhorn:BAABNQAECn8XAAIRAAcKKRJYvACkAQARAAcKKRJYvACkAQAAAA==.',
Sk='Skoduh:BAABNQAECn8fAAIDAAgKAxSNdgC1AQADAAgKAxSNdgC1AQAAAA==.',
Sl='Slack:BAABNQAECn8eAAMOAAoKxiH3DgBWAwAOAAoKxiH3DgBWAwAPAAEKAACecABHAAABNQAECgYIFAAIAE0dAA==.Sluggo:BAACNQAFFH8MAAIRAAUK3xHUDAB+AQARAAUK3xHUDAB+AQA1AAQKfyYAAhEACQrUICVTAJwCABEACQrUICVTAJwCAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIBAAAAA==.',
Sp='Spiralist:BAAANQAECgYIDAAAAA==.Spìne:BAAANQAECgQIBAAAAA==.',
St='Steelforged:BAAANQADCgQIBAABNQAECggIGgAbAGgPAA==.Stonedalways:BAAANQAECgYIEwAAAA==.Stonytoni:BAAANQAECgMIAwAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQABNQAECgoKGAAaAKwQAA==.Sunfuri:BAABNQAECn8bAAIfAAgK0ATFGwDsAAAfAAgK0ATFGwDsAAAAAA==.Sus:BAACNQAFFH8NAAIWAAUKXBTcCgB1AQAWAAUKXBTcCgB1AQA1AAQKfyYAAxYACQrKIvIZAMsCABYACQrKIvIZAMsCACMABAp1C0giALAAAAAA.Susanoo:BAAANQAECggIDQAAAA==.',
Ta='Taalia:BAABNQAECn8fAAIQAAYKVAxTiQAEAQAQAAYKVAxTiQAEAQAAAA==.Talonas:BAABNQAECn8hAAMIAAoKBBhCBgBTAgAIAAoKkxdCBgBTAgAUAAYKyBd7EgGGAAAAAA==.Tarathor:BAABNQAECn8cAAIoAAYK6A9tSwDfAAAoAAYK6A9tSwDfAAAAAA==.Tatortott:BAAANQAECggIDQABNQAECgoKIgARAAEKAA==.',
Te='Teknofarious:BAABNQAECn8eAAMaAAkK7QuQAwBfAQAaAAkK7QuQAwBfAQAIAAEKAAAmSwAvAAAAAA==.',
Th='Thaumas:BAAANQAECgEIAQAAAA==.Thesafe:BAAANQAECgYIDgAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAABNQAECn8UAAMIAAYKTR1sDAD0AQAIAAYKTR1sDAD0AQAUAAQKYgaHfgHGAAAAAA==.Thialaa:BAABNQAECn8fAAMnAAoKPRdlCwD5AQAnAAkKDBllCwD5AQAYAAEKlgrGHQE4AAABNQAECgoKPwADANUjAA==.Thialia:BAABNQAECn81AAIOAAoKMRGySwD0AQAOAAoKMRGySwD0AQABNQAECgoKPwADANUjAA==.Thialiaa:BAABNQAECn8bAAIIAAkKpg+sDACwAQAIAAkKpg+sDACwAQABNQAECgoKPwADANUjAA==.Thialiadin:BAABNQAECn8iAAMgAAoKrBZqFADOAQAgAAkK6RdqFADOAQAlAAEKAA/p6gA3AAABNQAECgoKPwADANUjAA==.Thickems:BAAANQAECgYIEAAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn87AAISAAoK+xx7AQABAwASAAoK+xx7AQABAwAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAQIEQALANoZAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgYIEgAAAA==.Trema:BAABNQAECn9PAAMgAAoKPxgWFQBZAgAgAAgKpBwWFQBZAgARAAoK9ws8uACtAQAAAA==.Trialei:BAAANQAECgEIAQAAAA==.Trick:BAAANQAECgQICAAAAA==.Trix:BAAANQAECgEIAQAAAA==.',
Ts='Tserendelgor:BAAANQAECgYIEgABNQAECgoKQAALAJUiAA==.',
Tu='Tulsi:BAAANQAECggIEwAAAA==.',
Ty='Tyronos:BAABNQAECn8dAAIRAAoKZA8KjACfAQARAAoKZA8KjACfAQAAAA==.',
Va='Vaeltharion:BAAANQAECgUIEAAAAA==.Varedrae:BAAANQADCggIFQAAAA==.Vas:BAAANQADCgYIFAAAAA==.',
Ve='Verdandi:BAAANQAECgUICwAAAA==.Vevicenth:BAABNQAECn8iAAMaAAkKmgWsBgDoAAAUAAgKcwWOpwBDAQAaAAYKZgOsBgDoAAAAAA==.',
Vo='Voranth:BAABNQAECn8nAAMQAAoKAiFIDwAzAwAQAAoKAiFIDwAzAwAGAAQKIBItxgAGAQAAAA==.',
Wa='Wainstatick:BAAANQAECgQIBAAAAA==.Wakeko:BAAANQAECgQIBAABNQAECgYIGwAYAIgUAA==.Warenio:BAABNQAECn8nAAMnAAoKKBVTEAAjAgAnAAoKKBVTEAAjAgAYAAIKhQJxEQFGAAAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMIAAkKaRqLCwAIAgAIAAkKfRaLCwAIAgAUAAYKrR0SzwDoAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECggIHQAbAGoLAA==.',
Wh='Whakan:BAAANQADCggIJwABNQAECgUICgAHAAAAAA==.',
Wi='Williamgoat:BAAANQAECgcIDwABNQAECgoKQAALAJUiAA==.',
Wo='Wolfos:BAAANQAECgIICgAAAA==.',
Wt='Wtfox:BAEBNQAECn8mAAIPAAoKmQ8PGgC0AQAPAAoKmQ8PGgC0AQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAABNQAECn8iAAMXAAkKyg6THwCQAQAXAAkKyg6THwCQAQAWAAMKfARPfwAzAAAAAA==.',
Xa='Xalatos:BAAANQAECggIEwAAAA==.Xalfein:BAAANQADCggILgAAAA==.',
Xi='Xinu:BAAANQAECgQIBAABNQAECgoKOAADAKIaAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Xy='Xylendra:BAAANQAECgUICwABNQAECggIHgAbAPcGAA==.',
Ya='Yanakana:BAAANQAECgUIDAAAAA==.',
Yd='Ydrassil:BAAANQAECggIDQABNQAECgkJFwARACIcAA==.',
Za='Zakeko:BAABNQAECn8bAAMYAAYKiBRUsQACAQAYAAYKiBRUsQACAQAnAAEKAAD6PQBLAAAAAA==.Zanderpryde:BAABNQAECn8eAAIOAAkK6Qn8ZgCSAQAOAAkK6Qn8ZgCSAQABNQAECgoKLwATALAeAA==.Zariak:BAAANQAECgEIBAAAAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAABNQAECn8sAAIDAAkKVhceOQBXAgADAAkKVhceOQBXAgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn84AAMDAAoKohptMABzAgADAAoKohptMABzAgACAAEKSwUfZgAwAAAAAA==.Zivalisse:BAAANQAECgIIBwAAAA==.',
Zo='Zota:BAABNQAECn8jAAIDAAkKEBhGUAAYAgADAAkKEBhGUAAYAgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECggIHQAlAIweAA==.Zulfionn:BAABNQAECn8gAAIDAAkKSAd9eQCuAQADAAkKSAd9eQCuAQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgYIFAAIAE0dAA==.',
['Áy']='Áyrá:BAAANQAECgYIEwAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMIDAAAAA==.',
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
