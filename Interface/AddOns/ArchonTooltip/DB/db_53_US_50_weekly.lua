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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warrior-Arms','Evoker-Preservation','Mage-Fire','Monk-Windwalker','Druid-Feral','Monk-Brewmaster','Evoker-Devastation','Warlock-Affliction','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Druid-Restoration','Paladin-Holy','Rogue-Subtlety','Druid-Balance','Warrior-Protection','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn8uAAMBAAkKeCNEAAC1AgABAAkKeCNEAAC1AgACAAEKlhJ5gQBBAAAAAA==.',
Ad='Adorian:BAAANQAECgIIAgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxMtEgBAAQADAAQK+BYtEgBAAQACAAIKegarHwB1AAA1AAQKfyUAAwIACQpTHzIoAAgCAAIACArNGjIoAAgCAAMABAq0HeDhAD0BAAAA.',
Ae='Aelfwine:BAAANQAECgcIDgAAAA==.',
Ai='Ailaith:BAABNQAECn8mAAMDAAkKwSIXAwC7AgADAAkKwSIXAwC7AgACAAIKAAB6egBYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn87AAMEAAoK1h1KCQBlAgAEAAcKuRtKCQBlAgAFAAgKzhubDwDGAQAAAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAQABNQAECgUIBQAGAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQADCgYICgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAGAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAGAAAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICgAGAAAAAA==.Alydrostage:BAABNQAECn8XAAIHAAcKDw6+EwBtAQAHAAcKDw6+EwBtAQAAAA==.Alystriaz:BAAANQAECgYIEQAAAA==.Alzheimerz:BAABNQAECn8tAAMIAAkKdx8jDQAcAwAIAAkKdx8jDQAcAwAJAAIKZBfqFgB4AAAAAA==.',
Am='Amaelalin:BAABNQAECn8mAAIKAAkK/hAZEgDkAQAKAAkK/hAZEgDkAQAAAA==.Amatoria:BAAANQAECgYIEgAAAA==.',
An='Ananiel:BAAANQABCgQIBAAAAA==.Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAGAAAAAA==.Andaya:BAABNQAECn8kAAMLAAoKhhsYKwC2AgALAAoKhhsYKwC2AgAMAAEKAADvqAAAAAAAAA==.Andemeli:BAAANQAECgYIDgAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgMIAwAAAA==.',
Ar='Arandis:BAABNQAECn8UAAMNAAcKAQnTQQAjAQANAAYKkArTQQAjAQAOAAEKCQXgLQApAAAAAA==.Arcianna:BAABNQAECn8kAAIPAAkKIh/7BgAbAwAPAAkKIh/7BgAbAwAAAA==.Arctica:BAABNQAECn8VAAIQAAcKTAQtTQEPAQAQAAcKTAQtTQEPAQAAAA==.Arjurn:BAABNQAECn8vAAIQAAoKShrYBgBhAgAQAAoKShrYBgBhAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn8xAAIRAAoKrSQhAAAgBAARAAoKrSQhAAAgBAAAAA==.Artymiss:BAAANQAECgcIDAAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn8kAAIDAAoKJhkkCABDAgADAAoKJhkkCABDAgAAAA==.',
Ay='Ayorana:BAAANQADCggIEAAAAA==.',
Az='Azshura:BAAANQAECgYICAAAAA==.Azzinôth:BAABNQAECn83AAMSAAoKGxE+EABqAQATAAcKpg7nOAB9AQASAAoK2xA+EABqAQAAAA==.',
Ba='Baldr:BAABNQAECn8bAAIUAAgKxglNxQCRAQAUAAgKxglNxQCRAQAAAA==.Balgar:BAABNQAECn8VAAIDAAcK6x3vGAC2AQADAAcK6x3vGAC2AQAAAA==.Balghas:BAAANQAECggIBgAAAA==.Bammz:BAABNQAECn8yAAIVAAoKjR9CDgDoAQAVAAoKjR9CDgDoAQAAAA==.Bastia:BAAANQADCgYIEwAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAGAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAAANQAECgcIEQAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn8bAAIDAAgKqRcwLQBpAQADAAgKqRcwLQBpAQAAAA==.Bloodytusks:BAAANQADCggIFgAAAA==.',
Bo='Boomchick:BAAANQADCggICgABNQAECgIIBAAGAAAAAA==.Borrkbuster:BAAANQAECgUIEAAAAA==.',
Br='Brenri:BAAANQAECgQIBAAAAA==.Brewtality:BAAANQAECgQIBAABNQAFFAIIBwAWAIUPAA==.Brudanature:BAAANQADCgUIBQABNQAECgYIDQAGAAAAAA==.Brughe:BAAANQAECgcIDwAAAA==.Brywynn:BAAANQADCggIFAABNQAECgYIEAAGAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAFFAIIBwAWAIUPAA==.Bumhug:BAAANQAECgQIBAABNQAECgkJLQAIAHcfAA==.Burnbabyburn:BAABNQAECn8YAAIXAAoKrBDPAABoAQAXAAoKrBDPAABoAQAAAA==.Burntbum:BAAANQADCggICAABNQAECgcIHQAUAD0KAA==.Buttacutta:BAAANQADCggILgAAAA==.',
Ca='Cahoots:BAABNQAECn8qAAIYAAoKEB0LDgD9AgAYAAoKEB0LDgD9AgAAAA==.Caneste:BAACNQAFFH8JAAINAAQKCxFkCwA4AQANAAQKCxFkCwA4AQA1AAQKfycAAg0ACQodIjAJAEsDAA0ACQodIjAJAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8jAAIZAAcKEBbNEQDkAQAZAAcKEBbNEQDkAQAAAA==.Cayleynne:BAABNQAECn8dAAIaAAoK8BwDBQAYAwAaAAoK8BwDBQAYAwAAAA==.',
Ce='Celestyl:BAAANQAECgMICQAAAA==.Cerwynne:BAAANQAECgQIBAAAAA==.',
Ch='Chadman:BAAANQAECgEIAQAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAQAAAA==.Cheapbeerz:BAABNQAECn8fAAMHAAgKUAY9GgAjAQAHAAcKPgY9GgAjAQAQAAcKeALTRwEWAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQAECggIDwAAAA==.Chromstrasza:BAABNQAECn8nAAIbAAoK5A3BEwATAgAbAAoK5A3BEwATAgAAAA==.Chrîstopher:BAAANQADCggICAAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn8lAAMFAAkKtRH3JwBRAQAFAAkKtRH3JwBRAQAcAAEKAAAcMgAwAAAAAA==.',
Co='Comitus:BAABNQAECn8lAAIVAAkKuAVePwAlAQAVAAkKuAVePwAlAQAAAA==.Conj:BAAANQAECgQIBAAAAA==.Conjarr:BAABNQAECn8mAAIKAAoKqhm3OwB7AgAKAAoKqhm3OwB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECggIIgAdAP4dAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgIIAwAAAA==.Cougarsixsix:BAAANQAECgQICQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8pAAIeAAgKhg9AWACvAQAeAAgKhg9AWACvAQAAAA==.Crypticcurse:BAAANQADCgcIKwAAAA==.',
Cy='Cynnai:BAABNQAECn8iAAIVAAkKXxz1AwCvAgAVAAkKXxz1AwCvAgAAAA==.',
Da='Dadythickums:BAAANQAECgYIBgAAAA==.Daeghrefn:BAAANQADCgYIBgABNQAECgYIBwAGAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgYIDgAGAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8gAAMFAAgKDA89uQBbAQAFAAYK7Q49uQBbAQAEAAMKiQsDSQClAAAAAA==.Danashal:BAABNQAECn8jAAIWAAgK6APJEgC0AAAWAAgK6APJEgC0AAAAAA==.Dangerranger:BAAANQAECgIIBAAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgYICwAAAA==.Darrth:BAABNQAECn8fAAMfAAcKSxbbFQBbAQAfAAcKSxbbFQBbAQAgAAEK2AN10wAqAAAAAA==.Darthbane:BAAANQAECgUIEgAAAA==.Darthjareth:BAAANQADCgYIDAAAAA==.Darthsion:BAAANQADCgEIAQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAGAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQAECgEIAQABNQAECgYICwAGAAAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn8iAAMKAAgKZBpEDwABAgAKAAgKZBpEDwABAgANAAUKSgOyXgCIAAAAAA==.Demontator:BAAANQADCggIDQABNQAECgcIHQAUAD0KAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIMAAgKYxYkXgAHAgAMAAgKYxYkXgAHAgAAAA==.Desmádre:BAABNQAECn8aAAMeAAcKPxxaQQAXAgAeAAcKNhtaQQAXAgAgAAYKBxuYTgC7AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn8oAAMLAAkKJyJeBACxAgALAAkKJyJeBACxAgAMAAEKAACCPwEuAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECggIEAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgYIEAAGAAAAAA==.',
Dr='Dravenpryde:BAABNQAECn8eAAILAAkKYglGgACLAQALAAkKYglGgACLAQABNQAECgoKKAAPADEcAA==.Drbrad:BAAANQAECgQIBAAAAA==.Dreadfists:BAABNQAECn8aAAIfAAgKiRIkOQDvAQAfAAgKiRIkOQDvAQAAAA==.Druen:BAABNQAECn8kAAIZAAkK4RteBwDsAgAZAAkK4RteBwDsAgAAAA==.Drunkenpo:BAABNQAECn8oAAIaAAkKKR/tAABBAgAaAAkKKR/tAABBAgAAAA==.Drunkxdemon:BAAANQAECgcIDgAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8ZAAMYAAoKEhkrGACHAgAYAAoKEhkrGACHAgARAAEKuwR+JQAtAAAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8iAAMMAAoKMBVXRQBhAgAMAAgKmBhXRQBhAgALAAMKGw5cWQCoAAABNQAFFAIIBgAIAIMeAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgUICwAAAA==.Dweñde:BAABNQAECn8gAAIFAAgKaA5TmQCnAQAFAAgKaA5TmQCnAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgUIBgAAAA==.',
Ed='Eddrick:BAABNQAECn8cAAMUAAgKWxiRGADBAQAUAAgKmhaRGADBAQAhAAIKNxhSVACSAAAAAA==.Edrid:BAABNQAECn8ZAAIQAAgKQxwiBgBvAgAQAAgKQxwiBgBvAgABNQAFFAUIDgAWACocAA==.',
Ei='Eirwen:BAAANQABCgMIAgAAAA==.',
El='Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn8yAAIOAAkKaiM8AACpAgAOAAkKaiM8AACpAgAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAABNQAECn8WAAMhAAcKtxMWCwBKAQAUAAcKKBA3wwCVAQAhAAcKlhIWCwBKAQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggIDwAAAA==.',
Ev='Evandra:BAABNQAECn8WAAILAAcKihkYFAC0AQALAAcKihkYFAC0AQAAAA==.Evanorah:BAAANQAECgYICgAAAA==.',
Fa='Faedeyeda:BAAANQAECgYIBwAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQAECgMIAwABNQAECgkJJAAiANUYAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBwAGAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECggIEAAGAAAAAA==.',
Fr='Frojio:BAABNQAECn8YAAIfAAgKtgvvSgCOAQAfAAgKtgvvSgCOAQAAAA==.Frosten:BAAANQADCggIOwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgMIAwAAAA==.Gaff:BAABNQAECn8ZAAIVAAcKWBUBrwCnAQAVAAcKWBUBrwCnAQAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Go='Gobby:BAAANQADCgUIBQABNQAECgYIEAAGAAAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYIDgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQANAAsRAA==.',
Ha='Hadin:BAABNQAECn8jAAIQAAkKQh/GCAA9AgAQAAkKQh/GCAA9AgAAAA==.Halalnt:BAAANQAECgYIDAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAHAGkaAA==.Hamster:BAAANQADCgYIBgABNQAECgYIFAAHAE0dAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn8kAAIPAAkKhRb5EwAkAgAPAAkKhRb5EwAkAgAAAA==.Harsaiah:BAAANQADCgYICAABNQAECgUIEwAGAAAAAA==.Hazenpryde:BAABNQAECn8oAAIPAAoKMRwgCQDlAgAPAAoKMRwgCQDlAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIHQABNQAECgcIGAAjAFwYAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAABNQAECn8qAAIDAAoK8hJuIwCLAQADAAoK8hJuIwCLAQAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8cAAIFAAkKgBe0KQBLAQAFAAkKgBe0KQBLAQAAAA==.',
Hy='Hysgar:BAAANQAECgUIDQABNQAECgUIEwAGAAAAAA==.',
Ic='Icetiger:BAAANQADCgEIAQAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8lAAMNAAoKxBqXAQBuAgANAAoKxBqXAQBuAgAKAAUKghY5mgBGAQAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn8vAAIVAAoK0RlKBwBPAgAVAAoK0RlKBwBPAgAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgYICAAAAA==.',
Ja='Jackfruit:BAABNQAECn8aAAMUAAgKrgm12ABqAQAUAAgKrgm12ABqAQAkAAUK+wgSQwDhAAAAAA==.Jaod:BAAANQADCgYIHAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIBQAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCggILAAAAA==.Kalarae:BAAANQAECgcICgAAAA==.Kaljeer:BAABNQAECn8eAAIlAAcK5hVeEwA9AQAlAAcK5hVeEwA9AQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kalmyk:BAAANQAECgIIAgAAAA==.Kaltharion:BAAANQAECgIIAgAAAA==.Kaluren:BAACNQAFFH8OAAIkAAUKyyDECADWAQAkAAUKyyDECADWAQA1AAQKfyoAAyQACQqtJi4BAOEDACQACQqtJi4BAOEDABQABQosIPXiAFUBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8aAAMFAAkK4QvkmgCjAQAFAAkKTwnkmgCjAQAEAAIKeBFpWQB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8hAAIaAAkKTSPSAwBKAwAaAAkKTSPSAwBKAwAAAA==.Kapp:BAAANQAECgYIDwAAAA==.Karabar:BAABNQAECn8vAAIhAAoKCR5HAgAwAgAhAAoKCR5HAgAwAgAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAGAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAGAAAAAA==.Karnnagexxl:BAAANQAECgMIAwABNQAECgQIBQAGAAAAAA==.Kasarra:BAAANQAECgQIBgAAAA==.Kayiku:BAAANQADCggIFAAAAA==.Kazagol:BAABNQAECn8pAAITAAoKuxZ1HABxAgATAAoKuxZ1HABxAgAAAA==.',
Kh='Khamaracy:BAAANQAECgUIDAAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAABNQAECn8cAAIUAAgKHxgJHQCuAQAUAAgKHxgJHQCuAQAAAA==.',
Kr='Kryptus:BAABNQAECn8iAAIQAAoK0xbmNQBTAQAQAAoK0xbmNQBTAQAAAA==.',
Ku='Kurick:BAAANQAECgUIEwAAAA==.Kurshak:BAABNQAECn8nAAImAAoKgxQZEgBIAQAmAAoKgxQZEgBIAQAAAA==.',
Ky='Kyngizzard:BAAANQAECgMIBgABNQAECgYIDAAGAAAAAA==.',
La='Latte:BAAANQAECgYIEgAAAA==.',
Le='Lenity:BAABNQAECn8iAAIlAAcKawzoDgBfAQAlAAcKawzoDgBfAQAAAA==.',
Li='Lichboom:BAAANQAECgEIAQABNQAECggIIgAdAP4dAA==.',
Lo='Loan:BAAANQADCggIGwABNQAECgYIFAAHAE0dAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgUIEQAAAA==.Longtrail:BAAANQAECgEIAQAAAA==.',
Lu='Lucoryphus:BAAANQAECgYIBwAAAA==.Lukeduke:BAACNQAFFH8OAAInAAUKnxwxAgCJAQAnAAUKnxwxAgCJAQA1AAQKfycAAicACQrKIwsEAE8DACcACQrKIwsEAE8DAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAUIDgAnAJ8cAA==.Lunaries:BAAANQAECgEIAQAAAA==.Lunä:BAABNQAECn8cAAILAAkKIxrvDQDvAQALAAkKIxrvDQDvAQAAAA==.',
Ly='Lydia:BAABNQAECn8pAAMQAAgKjBkswgAAAgAQAAcK5RYswgAAAgAHAAIKEBx7DwCTAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICgAGAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgIIAwAAAA==.',
Ma='Malcontent:BAAANQAECgMIAwABNQAECgYIEAAGAAAAAA==.Malfeasance:BAAANQADCgUIBQABNQAECgYIEAAGAAAAAA==.Malifel:BAAANQAECgYIEAAAAA==.Mallord:BAAANQAECgQIBAABNQAECgYIEAAGAAAAAA==.Malstrom:BAAANQAECgIIBAABNQAECgYIEAAGAAAAAA==.Mandarin:BAABNQAECn8WAAIjAAcKmBCpCQCdAQAjAAcKmBCpCQCdAQAAAA==.Mararose:BAAANQABCgQIBgAAAA==.Marashades:BAABNQAECn8VAAIgAAcKlR7CCQCiAQAgAAcKlR7CCQCiAQAAAA==.Marsali:BAAANQADCgcICgAAAA==.',
Me='Melabrin:BAABNQAECn8dAAIFAAkKzwlTIQBpAQAFAAkKzwlTIQBpAQAAAA==.Mercia:BAABNQAECn8bAAIhAAgKEB6zDwCiAgAhAAgKEB6zDwCiAgAAAA==.Mercý:BAAANQADCggIIAAAAA==.Merekoma:BAABNQAECn8bAAITAAcKexiUDgBAAQATAAcKexiUDgBAAQAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgIIAwAAAA==.Mingonashoba:BAAANQAECgIIBQAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAABNQAECn8XAAMYAAcK3QvhFQD6AAAYAAcK3QvhFQD6AAARAAQKIgJKQQBvAAAAAA==.Mistaricky:BAABNQAECn8WAAMVAAcKqBTeMgBGAQAVAAcKqBTeMgBGAQAdAAEKxAj3NAAxAAAAAA==.',
Mo='Moadeed:BAAANQAECgYIDAAAAA==.Moongazer:BAAANQADCgYIBgAAAA==.Morassabe:BAAANQADCgcIBwAAAA==.Morphmious:BAABNQAECn8sAAIZAAkKNxkICwCCAgAZAAkKNxkICwCCAgAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgYIDwAAAA==.',
My='Myroku:BAAANQABCgMIAwABNQAECgYIEAAGAAAAAA==.Myrrh:BAABNQAECn8qAAMWAAoKOgblJACZAQAWAAoKOgblJACZAQAbAAIKTwQvDwBuAAAAAA==.Mysklef:BAAANQAECgIIAQABNQAECgUIEwAGAAAAAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICgAGAAAAAA==.Nausican:BAAANQAECgEIAQAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECggIHQALAKUiAA==.Necrosector:BAABNQAECn8hAAIUAAkKwBryYwBvAgAUAAkKwBryYwBvAgAAAA==.Nelandra:BAAANQAECgUICQAAAA==.Neongrasp:BAABNQAECn8YAAIeAAoK4xPjBQDWAQAeAAoK4xPjBQDWAQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninelives:BAAANQAECgUIBQAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAIIBgAIAIMeAA==.',
No='Nomahuata:BAABNQAECn8xAAIMAAoKxgy4IgAxAQAMAAoKxgy4IgAxAQAAAA==.',
Nu='Nufrus:BAABNQAECn8UAAIDAAcKygjheAC8AAADAAcKygjheAC8AAAAAA==.Nurgle:BAAANQADCgUICQAAAA==.',
Ny='Nyeli:BAAANQAECgYIEAAAAA==.Nyxi:BAAANQAECgYIEAAAAA==.',
['Né']='Néo:BAAANQAECgMIBAAAAA==.',
Oc='Octavios:BAAANQAECgMIAwAAAA==.',
Om='Ommeta:BAAANQAFFAMIAwABNQAFFAMIBwAmAGYIAA==.',
On='Onefiftyone:BAABNQAECn8kAAQiAAkK1RhvAwDnAQAiAAkK1RhvAwDnAQALAAUKtxZvqQAeAQAMAAEKAAD7PAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgQIDQAAAA==.Paltator:BAABNQAECn8dAAIUAAcKPQqVYQACAQAUAAcKPQqVYQACAQAAAA==.Pandazuken:BAABNQAECn8jAAIMAAgK0Rp1RgBcAgAMAAgK0Rp1RgBcAgAAAA==.Paradots:BAACNQAFFH8HAAIWAAIKhQ+ICQBxAAAWAAIKhQ+ICQBxAAA1AAQKfzAAAhYACgpYGdIOALwCABYACgpYGdIOALwCAAAA.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAABNQAECn8iAAIdAAgK/h19AgC4AQAdAAgK/h19AgC4AQAAAA==.',
Ph='Phantasee:BAAANQADCgQIBAAAAA==.Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgYICwAGAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQAECggIAgAAAA==.Pixystix:BAAANQAECgQICgABNQAECggIAgAGAAAAAA==.',
Po='Pomortem:BAAANQAECgYIDQAAAA==.Potsomancy:BAACNQAFFH8MAAIQAAYK1RoODwAAAgAQAAYK1RoODwAAAgA1AAQKfx8AAhAACQokJP1IAPECABAACQokJP1IAPECAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQAECgQIBAAGAAAAAA==.Raivel:BAAANQAECgUIDAABNQAECgYIEAAGAAAAAA==.Rambogg:BAAANQADCgMIAwABNQAFFAUIDwAQABsNAA==.Raneyth:BAAANQAECgYIDgAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQAECgEIAQABNQAECgoKNwASABsRAA==.Ravusternath:BAAANQADCggIFQAAAA==.',
Re='Redwinetoast:BAAANQAECgUICwAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8kAAQbAAcKuxeqAwBwAQAbAAcKuxeqAwBwAQAWAAMKOg+ZPwCjAAAoAAEKAAAAJQAxAAABNQAECgYIFAAHAE0dAA==.Reposess:BAAANQABCggIFAAAAA==.Reshyk:BAAANQAECgYICQAAAA==.',
Rh='Rhobes:BAAANQADCggIJAAAAA==.Rhondta:BAAANQADCgEIAQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAABNQAECn8XAAIkAAcKwwZiLwAlAQAkAAcKwwZiLwAlAQAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAGAAAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIHAAAAA==.',
Ru='Rumor:BAABNQAECn8YAAMjAAcKXBj0CwB7AQAjAAcKXBj0CwB7AQAmAAMKdAYrmAB4AAAAAA==.Rurry:BAACNQAFFH8OAAIWAAUKKhzQCACsAQAWAAUKKhzQCACsAQA1AAQKfyYAAxYACQqQI9EDAHgDABYACQqQI9EDAHgDABsAAQohJeI0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn8nAAMeAAgKgCKcFAAUAwAeAAgKgCKcFAAUAwAgAAIKMgpeugBTAAAAAA==.Ryuuko:BAAANQAECggICAAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8GAAIIAAIKgx7IEwCsAAAIAAIKgx7IEwCsAAA1AAQKfy4AAwgACgoAIacGAGgDAAgACgoAIacGAGgDACUABgoHEuApAHUBAAAA.',
Sa='Safetysham:BAAANQADCgcICwAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYIBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAGAAAAAA==.Salmoo:BAAANQAECggIEAAAAA==.Saltytator:BAAANQAECgMIBQABNQAECgcIHQAUAD0KAA==.Santhon:BAAANQADCgQICAAAAA==.Satanized:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggIKAAAAA==.',
Sc='Scaledaddy:BAABNQAECn8lAAMoAAoKkAleBADyAAAoAAkKUApeBADyAAAbAAQKYgbdMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECgkJLgABAHgjAA==.Scaryl:BAAANQAECgUIEgAAAA==.Schneè:BAABNQAECn8yAAInAAoKgBHkEwDoAQAnAAoKgBHkEwDoAQAAAA==.Scoom:BAACNQAFFH8OAAIQAAUK5hyfGgCmAQAQAAUK5hyfGgCmAQA1AAQKfy8AAhAACQoFJcYZAG4DABAACQoFJcYZAG4DAAAA.Scourgespawn:BAACNQAFFH8LAAMfAAUKlhmoBwB+AQAfAAUKlhmoBwB+AQAeAAEKAADhIwA9AAA1AAQKfyoAAx8ACQoeJMwQAAkDAB8ACQoeJMwQAAkDAB4ABAogEcOYAM8AAAAA.',
Se='Seikyo:BAABNQAECn8vAAIgAAoKBAx5EQBVAQAgAAoKBAx5EQBVAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgYIDAAGAAAAAA==.Selenë:BAAANQAECgYICwAAAA==.Serok:BAAANQAECggIEAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcICgAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAGAAAAAA==.Shalis:BAAANQAECgcICwAAAA==.Sharivee:BAAANQAECgUICwAAAA==.Shazamir:BAABNQAECn8VAAIiAAcK4gRBIwAoAQAiAAcK4gRBIwAoAQAAAA==.Shibui:BAABNQAECn8oAAISAAkKyxCuCAC5AQASAAkKyxCuCAC5AQAAAA==.Shifthead:BAACNQAFFH8HAAImAAMKZgi9CADOAAAmAAMKZgi9CADOAAA1AAQKfy4AAxkACgoxF7gNAD4CABkACAoAGbgNAD4CACYACgpKEIYaABABAAAA.Shockazilla:BAABNQAECn8gAAIkAAkKBCHdHAAAAwAkAAkKBCHdHAAAAwAAAA==.Shortspanky:BAAANQAECgQICwAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAABNQAECn8WAAIUAAYKZRNYvACkAQAUAAYKZRNYvACkAQAAAA==.',
Sk='Skoduh:BAAANQAECgYIDQAAAA==.',
Sl='Slack:BAAANQAECgcIEQABNQAECgYIFAAHAE0dAA==.Sluggo:BAACNQAFFH8MAAIUAAUK3xHUDAB+AQAUAAUK3xHUDAB+AQA1AAQKfyYAAhQACQrUICVTAJwCABQACQrUICVTAJwCAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIAQAAAA==.',
Sp='Spiralist:BAAANQAECgUIBwAAAA==.',
St='Stonedalways:BAAANQAECgYIEAAAAA==.Stonytoni:BAAANQAECgMIAgAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQABNQAECgoKGAAXAKwQAA==.Sunfuri:BAABNQAECn8bAAIdAAgK0ATFGwDsAAAdAAgK0ATFGwDsAAAAAA==.Sus:BAACNQAFFH8NAAISAAUKXBTcCgB1AQASAAUKXBTcCgB1AQA1AAQKfyYAAxIACQrKIvIZAMsCABIACQrKIvIZAMsCACkABAp1C0giALAAAAAA.Susanoo:BAAANQAECggICAAAAA==.',
Ta='Taalia:BAAANQAECgUIDAAAAA==.Talonas:BAAANQAECggICAAAAA==.Tarathor:BAAANQAECgUIDAAAAA==.Tatortott:BAAANQAECgQIBAABNQAECgcIHQAUAD0KAA==.',
Te='Teknofarious:BAABNQAECn8eAAMXAAkK7QuDAACuAQAXAAkK7QuDAACuAQAHAAEKAAAmSwAvAAAAAA==.',
Th='Thesafe:BAAANQAECgYIDQAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAABNQAECn8UAAMHAAYKTR1sDAD0AQAHAAYKTR1sDAD0AQAQAAQKYgaHfgHGAAAAAA==.Thialaa:BAAANQAECggICgABNQAECgkJJgADAMEiAA==.Thialia:BAABNQAECn8iAAIKAAkK+QxAJQBrAQAKAAkK+QxAJQBrAQABNQAECgkJJgADAMEiAA==.Thialiaa:BAAANQADCgYIBgABNQAECgkJJgADAMEiAA==.Thialiadin:BAAANQAECgUIDQABNQAECgkJJgADAMEiAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn8vAAIOAAoKWxwVAAANAwAOAAoKWxwVAAANAwAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAIIBgAIAIMeAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgYIEAAAAA==.Trema:BAABNQAECn81AAMhAAkKhBkWFQBZAgAhAAcKRh4WFQBZAgAUAAkKRQwKWQATAQAAAA==.Trialei:BAAANQABCgIIAgAAAA==.Trick:BAAANQADCgYIBwABNQAECgoKOAAZAIUlAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgYIDgABNQAECgkJLQAIAHcfAA==.',
Tu='Tulsi:BAAANQAECgcIDgAAAA==.',
Ty='Tyronos:BAABNQAECn8VAAIUAAcKJBCfWAATAQAUAAcKJBCfWAATAQAAAA==.',
Va='Vaeltharion:BAAANQAECgYIDgAAAA==.Varedrae:BAAANQADCggIFQAAAA==.Vas:BAAANQADCgYIFAAAAA==.',
Ve='Verdandi:BAAANQAECgUICgAAAA==.Vevicenth:BAAANQAECgcIDgAAAA==.',
Vo='Voranth:BAABNQAECn8dAAMLAAgKpSLoAwDIAgALAAgKpSLoAwDIAgAMAAQKIBItxgAGAQAAAA==.',
Wa='Warenio:BAABNQAECn8hAAInAAgKeBdTEAAjAgAnAAgKeBdTEAAjAgAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMHAAkKaRqLCwAIAgAHAAkKfRaLCwAIAgAQAAYKrR0SzwDoAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECgcIFwAYAN0LAA==.',
Wh='Whakan:BAAANQADCggIIgABNQAECgYIBwAGAAAAAA==.',
Wi='Williamgoat:BAAANQADCggICwABNQAECgkJLQAIAHcfAA==.',
Wo='Wolfos:BAAANQAECgIICgAAAA==.',
Wt='Wtfox:BAEBNQAECn8dAAINAAgKzRCRKQDbAQANAAgKzRCRKQDbAQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAABNQAECn8UAAMTAAcKhwj9QwAxAQATAAcKhwj9QwAxAQASAAMKfASUTgA6AAAAAA==.',
Xa='Xalatos:BAAANQAECgcIDwAAAA==.Xalfein:BAAANQADCggIHAAAAA==.',
Xi='Xinu:BAAANQAECgQIBAABNQAECgkJJAADAMcZAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQAECgUIDAAAAA==.',
Yd='Ydrassil:BAAANQAECgEIAQABNQAECggIDwAGAAAAAA==.',
Za='Zakeko:BAAANQAECgUIDAAAAA==.Zanderpryde:BAAANQAECgcIEgABNQAECgoKKAAPADEcAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAABNQAECn8YAAIDAAcK8BB4JwB8AQADAAcK8BB4JwB8AQAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn8kAAIDAAkKxxmDUQB7AgADAAkKxxmDUQB7AgAAAA==.Zivalisse:BAAANQAECgEIAQAAAA==.',
Zo='Zota:BAAANQAECggIEgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgUIEwAGAAAAAA==.Zulfionn:BAABNQAECn8VAAIDAAcKcgZWRQAqAQADAAcKcgZWRQAqAQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgYIFAAHAE0dAA==.',
['Áy']='Áyrá:BAAANQAECgcIEgAAAA==.',
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
