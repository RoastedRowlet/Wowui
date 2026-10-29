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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Evoker-Devastation','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','Mage-Fire','Monk-Windwalker','Druid-Feral','Monk-Brewmaster','Warlock-Affliction','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Paladin-Holy','Druid-Restoration','Warrior-Protection','Druid-Balance','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn80AAMBAAoK4SPhAAD4AgABAAoK4SPhAAD4AgACAAEKlhJ5gQBBAAAAAA==.',
Ad='Adorian:BAAANQAECgIIAgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxMtEgBAAQADAAQK+BYtEgBAAQACAAIKegarHwB1AAA1AAQKfyUAAwIACQpTHzIoAAgCAAIACArNGjIoAAgCAAMABAq0HeDhAD0BAAAA.',
Ae='Aelfwine:BAABNQAECn8XAAIDAAcKEQYPmQD+AAADAAcKEQYPmQD+AAAAAA==.',
Ai='Ailaith:BAABNQAECn8uAAMDAAkKwSJcGgCIAgADAAkKwSJcGgCIAgACAAIKAAB6egBYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn9BAAMEAAoKYiBKCQBlAgAEAAcKuRtKCQBlAgAFAAgKMx9tMgDiAQAAAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAQABNQAECgUIBQAGAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQADCgYICgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAGAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAGAAAAAA==.Alirik:BAAANQADCgIIAgAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICgAGAAAAAA==.Alydrostage:BAABNQAECn8ZAAIHAAcKDw6+EwBtAQAHAAcKDw6+EwBtAQAAAA==.Alystriaz:BAABNQAECn8aAAMIAAcKnQoADgD5AAAIAAcKnQoADgD5AAAJAAQK2gf6JgBiAAAAAA==.Alzheimerz:BAABNQAECn81AAQKAAoKOh4jDQAcAwAKAAoKOh4jDQAcAwALAAIKZBfqFgB4AAAMAAIKHxh+jwBKAAAAAA==.',
Am='Amaelalin:BAABNQAECn8uAAINAAkKghSTMwDuAQANAAkKghSTMwDuAQAAAA==.Amatoria:BAAANQAECgYIEwAAAA==.',
An='Ananiel:BAAANQABCgcICAABNQADCgQIBAAGAAAAAA==.Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAGAAAAAA==.Andaya:BAACNQAFFH8FAAIOAAIKaRJUGACAAAAOAAIKaRJUGACAAAA1AAQKfygAAw4ACgqKGxgrALYCAA4ACgqKGxgrALYCAA8AAQoAABbiAAAAAAAA.Andemeli:BAABNQAECn8XAAIQAAYKnQZaFQH7AAAQAAYKnQZaFQH7AAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgMIAwAAAA==.',
Ar='Arandis:BAABNQAECn8aAAMRAAcK1wntIgDvAAARAAcK1wntIgDvAAASAAEKCQXgLQApAAAAAA==.Arcianna:BAABNQAECn8tAAITAAoKVh+xBQClAgATAAoKVh+xBQClAgAAAA==.Arctica:BAABNQAECn8bAAIUAAcKqQQBvgDMAAAUAAcKqQQBvgDMAAAAAA==.Arjurn:BAABNQAECn81AAIUAAoKtRynIQByAgAUAAoKtRynIQByAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn83AAIVAAoKvSSeAAASBAAVAAoKvSSeAAASBAAAAA==.Artymiss:BAAANQAECgcICwAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn8tAAIDAAoKRBuCHwBsAgADAAoKRBuCHwBsAgAAAA==.',
Ay='Ayorana:BAAANQADCggIEAAAAA==.',
Az='Azshura:BAAANQAECgYICgAAAA==.Azzinôth:BAABNQAECn9AAAMWAAoKOhSMFQACAgAWAAoKOhSMFQACAgAXAAcKpg7nOAB9AQAAAA==.',
Ba='Baldr:BAABNQAECn8dAAIQAAoKeAlNxQCRAQAQAAoKeAlNxQCRAQAAAA==.Balgar:BAABNQAECn8ZAAIDAAgK1x2tPQDrAQADAAgK1x2tPQDrAQAAAA==.Balghas:BAAANQAECggICAAAAA==.Bammz:BAABNQAECn8yAAIYAAoKjR84PQDTAgAYAAoKjR84PQDTAgAAAA==.Bastia:BAAANQADCgYIEwAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAGAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAABNQAECn8YAAIQAAgKGRueVACYAgAQAAgKGRueVACYAgAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn8iAAIDAAgKIhifVgBuAgADAAgKIhifVgBuAgAAAA==.Bloodytusks:BAAANQADCggIFgAAAA==.',
Bo='Boomchick:BAAANQADCggICgABNQAECgIIBAAGAAAAAA==.Borrkbuster:BAAANQAECgUIEQAAAA==.Botkin:BAAANQAECgIIAgAAAA==.',
Br='Brenri:BAAANQAECgYICgAAAA==.Brewtality:BAAANQAECgQIBAABNQAFFAQICwAJAHUKAA==.Brudanature:BAAANQADCgUIBQABNQAECgYIDgAGAAAAAA==.Brughe:BAAANQAECgcIDwAAAA==.Brywynn:BAAANQADCggIFAABNQAECgUIEAAGAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAFFAQICwAJAHUKAA==.Bumhug:BAAANQAECgUICAABNQAECgoKNQAKADoeAA==.Burnbabyburn:BAABNQAECn8YAAIZAAoKrBAKAwDlAQAZAAoKrBAKAwDlAQAAAA==.Burntbum:BAAANQADCggICAABNQAECggIHgAQAPkJAA==.Buttacutta:BAAANQADCggINQAAAA==.',
Ca='Cahoots:BAABNQAECn8sAAIaAAoKjx4LDgD9AgAaAAoKjx4LDgD9AgAAAA==.Caneste:BAACNQAFFH8JAAIRAAQKCxFkCwA4AQARAAQKCxFkCwA4AQA1AAQKfycAAhEACQodIjAJAEsDABEACQodIjAJAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8jAAIbAAcKEBbNEQDkAQAbAAcKEBbNEQDkAQAAAA==.Cayleynne:BAACNQAFFH8FAAIcAAIK2hZsBACQAAAcAAIK2hZsBACQAAA1AAQKfyEAAhwACgqfHwMFABgDABwACgqfHwMFABgDAAAA.',
Ce='Celestyl:BAAANQAECgIICgAAAA==.Cerwynne:BAAANQAECgQIAwAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAQAAAA==.Cheapbeerz:BAABNQAECn8fAAMHAAgKUAY9GgAjAQAHAAcKPgY9GgAjAQAUAAcKeALTRwEWAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAABNQAECn8UAAIaAAgKKg4RHQBCAQAaAAgKKg4RHQBCAQAAAA==.Chromstrasza:BAABNQAECn8qAAIIAAoK5Q3BEwATAgAIAAoK5Q3BEwATAgAAAA==.Chrîstopher:BAAANQADCggICAAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn8tAAMFAAkKchbBLQD5AQAFAAkKchbBLQD5AQAdAAEKAAAcMgAwAAAAAA==.',
Co='Comitus:BAABNQAECn8tAAIYAAkK2gZ3bgA9AQAYAAkK2gZ3bgA9AQAAAA==.Conj:BAAANQAECgQIBAAAAA==.Conjarr:BAABNQAECn8oAAINAAoK3hm3OwB7AgANAAoK3hm3OwB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECggIJwAeAP8dAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgIIAwAAAA==.Cougarsixsix:BAAANQAECgQIDAAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8pAAIfAAgKhg9AWACvAQAfAAgKhg9AWACvAQAAAA==.Crypticcurse:BAAANQADCggILQAAAA==.',
Cy='Cynnai:BAABNQAECn8kAAIYAAkKXxxHIQBrAgAYAAkKXxxHIQBrAgAAAA==.',
Da='Dadythickums:BAAANQAECgYICAAAAA==.Daeghrefn:BAAANQADCgYIBgABNQAECgYIBwAGAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgYIDgAGAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8gAAMFAAgKDA89uQBbAQAFAAYK7Q49uQBbAQAEAAMKiQsDSQClAAAAAA==.Danashal:BAABNQAECn8pAAIJAAkK6wP/GwDJAAAJAAkK6wP/GwDJAAAAAA==.Dangerranger:BAAANQAECgIIBAAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgcICwAAAA==.Darrth:BAABNQAECn8nAAMgAAgKJxW1KwB/AQAgAAgKJxW1KwB/AQAhAAEK2AN10wAqAAAAAA==.Darthbane:BAAANQAECgYIEwAAAA==.Darthjareth:BAAANQADCgYIDAAAAA==.Darthsion:BAAANQADCgEIAQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAGAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn8lAAMNAAkKexm/KwAXAgANAAkKexm/KwAXAgARAAUKSgOyXgCIAAAAAA==.Demontator:BAAANQADCggIDQABNQAECggIHgAQAPkJAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIPAAgKYxYkXgAHAgAPAAgKYxYkXgAHAgAAAA==.Desmádre:BAABNQAECn8aAAMfAAcKPxxaQQAXAgAfAAcKNhtaQQAXAgAhAAYKBxuYTgC7AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn8wAAMOAAkKMiO4DAD7AgAOAAkKMiO4DAD7AgAPAAEKAACCPwEuAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECggIEAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgcIEQAGAAAAAA==.',
Dr='Dravenpryde:BAABNQAECn8eAAIOAAkKYglGgACLAQAOAAkKYglGgACLAQABNQAECgoKLAATALAeAA==.Drbrad:BAAANQAECgQIBAAAAA==.Dreadfists:BAABNQAECn8cAAIgAAoKwhAkOQDvAQAgAAoKwhAkOQDvAQAAAA==.Druen:BAABNQAECn8tAAIbAAoKERteBABuAgAbAAoKERteBABuAgAAAA==.Drunkenpo:BAABNQAECn8wAAIcAAkKNR80AwBRAgAcAAkKNR80AwBRAgAAAA==.Drunkxdemon:BAAANQAECgcIDAAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8ZAAMaAAoKEhkrGACHAgAaAAoKEhkrGACHAgAVAAEKuwTOMQAtAAAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8nAAMPAAoKZxVXRQBhAgAPAAgKmBhXRQBhAgAOAAMKsw6HjwCgAAABNQAFFAIICAAKAIMeAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgUIDwAAAA==.Dweñde:BAABNQAECn8mAAIFAAgKDg9TmQCnAQAFAAgKDg9TmQCnAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgQIBQAAAA==.',
Ed='Eddrick:BAABNQAECn8jAAMiAAgKrRgAFgBVAQAQAAgKmhYLZwCJAQAiAAcKoRQAFgBVAQAAAA==.Edrid:BAABNQAECn8oAAIUAAkKoxygHQCHAgAUAAkKoxygHQCHAgABNQAFFAUIDgAJACocAA==.',
Ei='Eirwen:BAAANQABCgMIAgAAAA==.',
El='Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn87AAMSAAoKbyNnAQA/AwASAAkKlyNnAQA/AwANAAEKCCKTrwBjAAAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAABNQAECn8YAAMiAAgKPBJVFgBRAQAQAAcKKBA3wwCVAQAiAAgKSxFVFgBRAQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggIDwAAAA==.',
Ev='Evandra:BAAANQAECgcIEwAAAA==.Evanorah:BAAANQAECgYICgAAAA==.',
Fa='Faedeyeda:BAAANQAECgYIBwAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQAECgMIAwABNQAECgkJLAAjAAgaAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBwAGAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECggIDwAGAAAAAA==.',
Fr='Frojio:BAABNQAECn8YAAIgAAgKtgvvSgCOAQAgAAgKtgvvSgCOAQAAAA==.Frosten:BAAANQADCggIQwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgMIAwAAAA==.Gaff:BAABNQAECn8eAAIYAAgKvxN4egAhAQAYAAgKvxN4egAhAQAAAA==.Galia:BAAANQAECgYIBgAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Go='Gobby:BAAANQAECgYIBgABNQAECgcIEQAGAAAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYIDgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQARAAsRAA==.',
Ha='Hadin:BAABNQAECn8rAAIUAAkKZx+VMQArAgAUAAkKZx+VMQArAgAAAA==.Halalnt:BAAANQAECgUIDAABNQAECgYICwAGAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAHAGkaAA==.Hamster:BAAANQADCgYIBgABNQAECgYIFAAHAE0dAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn8sAAITAAkKvBb5EwAkAgATAAkKvBb5EwAkAgAAAA==.Harsaiah:BAAANQADCgYICAABNQAECgYIGwAkAKAhAA==.Hazenpryde:BAABNQAECn8sAAITAAoKsB4gCQDlAgATAAoKsB4gCQDlAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIHQABNQAECggIHAAlAN8YAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Heckboy:BAAANQADCgcIBwABNQAECgYIDgAGAAAAAA==.Hephaistian:BAABNQAECn8wAAIDAAoKZRW8UwB2AgADAAoKZRW8UwB2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8kAAIFAAkKYBsmJQAjAgAFAAkKYBsmJQAjAgAAAA==.',
Hy='Hysgar:BAAANQAECgUIDgABNQAECgYIGwAkAKAhAA==.',
Ic='Icetiger:BAAANQADCgUIBgAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8rAAMRAAoKERtZCgBMAgARAAoKERtZCgBMAgANAAUKghY5mgBGAQAAAA==.Imperion:BAAANQABCgIIAgAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn81AAMYAAoK0RkfKgA3AgAYAAoK0RkfKgA3AgAmAAEKAAB0OgAAAAAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgYICAAAAA==.',
Ja='Jackfruit:BAABNQAECn8fAAMQAAkK9A212ABqAQAQAAgKDAq12ABqAQAkAAYKGQimbAD8AAAAAA==.Jaod:BAAANQADCgYIHAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIBQAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCggILAAAAA==.Kalarae:BAAANQAECgcICgAAAA==.Kaljeer:BAABNQAECn8lAAIMAAgK8BUyHADzAQAMAAgK8BUyHADzAQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kalmyk:BAAANQAECgYICAAAAA==.Kaltharion:BAAANQAECgIIAQAAAA==.Kaluren:BAACNQAFFH8OAAIkAAUKyyDECADWAQAkAAUKyyDECADWAQA1AAQKfyoAAyQACQqtJi4BAOEDACQACQqtJi4BAOEDABAABQosIPXiAFUBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8aAAMFAAkK4QvkmgCjAQAFAAkKTwnkmgCjAQAEAAIKeBFpWQB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8pAAIcAAkKWiNXAgCeAgAcAAkKWiNXAgCeAgAAAA==.Kapp:BAAANQAECgYIEAAAAA==.Karabar:BAABNQAECn81AAMiAAoKCR7mCAA1AgAiAAoKCR7mCAA1AgAQAAEKAABndQEAAAAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAGAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAGAAAAAA==.Karnnagexxl:BAAANQAECgQIAwABNQAECgQIBQAGAAAAAA==.Kasarra:BAAANQAECgUICwAAAA==.Kayiku:BAAANQADCggIHAAAAA==.Kazagol:BAABNQAECn8vAAIXAAoKjBh1HABxAgAXAAoKjBh1HABxAgAAAA==.',
Kh='Khamaracy:BAABNQAECn8VAAIEAAUKJgixEwB7AAAEAAUKJgixEwB7AAAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAABNQAECn8jAAIQAAgKJhiNZgCKAQAQAAgKJhiNZgCKAQAAAA==.',
Kr='Kryptus:BAABNQAECn8sAAIUAAoKVBlGPgD7AQAUAAoKVBlGPgD7AQAAAA==.',
Ku='Kurick:BAABNQAECn8bAAMkAAYKoCFTcwC+AQAkAAUK6SFTcwC+AQAQAAYKVhhuvACkAQAAAA==.Kurshak:BAABNQAECn8tAAMnAAoKgxRVNQA/AgAnAAoKgxRVNQA/AgAbAAEKKgm2MAAzAAAAAA==.',
Ky='Kyngizzard:BAAANQAECgYICwAAAA==.',
La='Latte:BAAANQAECgYIEgAAAA==.',
Le='Lenity:BAABNQAECn8oAAIMAAcKawwLSAA+AQAMAAcKawwLSAA+AQAAAA==.',
Lo='Loan:BAAANQADCggIGwABNQAECgYIFAAHAE0dAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgYIEgAAAA==.',
Lu='Lucoryphus:BAAANQAECgYIBwAAAA==.Lukeduke:BAACNQAFFH8OAAImAAUKnxwxAgCJAQAmAAUKnxwxAgCJAQA1AAQKfycAAiYACQrKIwsEAE8DACYACQrKIwsEAE8DAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAUIDgAmAJ8cAA==.Lunaries:BAAANQAECgEIAQAAAA==.Lunä:BAABNQAECn8gAAMOAAkKIxrAMQDaAQAOAAkKIxrAMQDaAQAPAAQKlAhZiACNAAAAAA==.',
Ly='Lydia:BAABNQAECn8qAAMUAAkKexYswgAAAgAUAAgKwxMswgAAAgAHAAIKEBzMKwCcAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICgAGAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgQIBQAAAA==.',
Ma='Malcontent:BAAANQAECgMIAwABNQAECgcIEQAGAAAAAA==.Malfeasance:BAAANQADCgUIBQABNQAECgcIEQAGAAAAAA==.Malifel:BAAANQAECgcIEQAAAA==.Mallord:BAAANQAECgQIBAABNQAECgcIEQAGAAAAAA==.Malstrom:BAAANQAECgMIBAABNQAECgcIEQAGAAAAAA==.Mandarin:BAABNQAECn8WAAIlAAcKmBDqHAB7AQAlAAcKmBDqHAB7AQAAAA==.Mararose:BAAANQABCgQIBgAAAA==.Marashades:BAABNQAECn8bAAQhAAgKUR30KgBvAgAhAAgKUR30KgBvAgAgAAMKAQa2eQBXAAAfAAEKdwtZZwA/AAAAAA==.Marsali:BAAANQADCgcICgAAAA==.',
Me='Melabrin:BAABNQAECn8lAAIFAAkKIQzESQCHAQAFAAkKIQzESQCHAQAAAA==.Mercia:BAABNQAECn8kAAIiAAoKqhqzDwCiAgAiAAoKqhqzDwCiAgAAAA==.Mercý:BAAANQADCggIIAAAAA==.Merekoma:BAABNQAECn8dAAIXAAgKNBVnKgDvAQAXAAgKNBVnKgDvAQAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgEIAwAAAA==.Mingonashoba:BAAANQAECgIIBgAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAABNQAECn8ZAAMaAAgKmAqONwBYAQAaAAcK3QuONwBYAQAVAAUKEQJKQQBvAAAAAA==.Mistaricky:BAABNQAECn8XAAMYAAgKhRPcXwBjAQAYAAgKhRPcXwBjAQAeAAEKxAj3NAAxAAAAAA==.',
Mo='Moadeed:BAABNQAECn8VAAITAAcKDhE1IwDwAAATAAcKDhE1IwDwAAAAAA==.Moongazer:BAAANQADCgYIBgAAAA==.Morassabe:BAAANQADCggIDwAAAA==.Morphmious:BAABNQAECn8zAAIbAAoKqhoICwCCAgAbAAoKqhoICwCCAgAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgYIDwAAAA==.',
My='Mycenaean:BAAANQAECgEIAQABNQAFFAIIBQAcANoWAA==.Myroku:BAAANQABCgMIAwABNQAECgcIEQAGAAAAAA==.Myrrh:BAABNQAECn8qAAMJAAoKOgblJACZAQAJAAoKOgblJACZAQAIAAIKTwTSFwBkAAAAAA==.Mysklef:BAAANQAECgEIAQABNQAECgYIGwAkAKAhAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICgAGAAAAAA==.Nausican:BAAANQAECgEIAQAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgkJJQAOAOohAA==.Necrosector:BAABNQAECn8pAAIQAAkKth1rLABMAgAQAAkKth1rLABMAgAAAA==.Nelandra:BAAANQAECgUIDAAAAA==.Neongrasp:BAABNQAECn8YAAIfAAoK4xNfGAC3AQAfAAoK4xNfGAC3AQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAIICAAKAIMeAA==.',
No='Nomahuata:BAABNQAECn83AAIPAAoKvg46aADoAQAPAAoKvg46aADoAQAAAA==.',
Nu='Nufrus:BAABNQAECn8UAAIDAAcKyght0ABgAQADAAcKyght0ABgAQAAAA==.Nurgle:BAAANQADCgUICQAAAA==.',
Ny='Nyeli:BAAANQAECgUIEAAAAA==.Nyxi:BAAANQAECgYIEQAAAA==.',
['Né']='Néo:BAAANQAECgMIBAAAAA==.',
Oc='Octavios:BAAANQAECgQIBAAAAA==.',
Om='Ommeta:BAAANQAFFAMIAwABNQAFFAQICAAnAGYIAA==.',
On='Onefiftyone:BAABNQAECn8sAAQjAAkKCBraCQARAgAjAAkKCBraCQARAgAOAAUKwBZvqQAeAQAPAAEKAAD7PAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgUIDgAAAA==.Paltator:BAABNQAECn8eAAIQAAgK+QlhmAAiAQAQAAgK+QlhmAAiAQAAAA==.Pandazuken:BAABNQAECn8qAAIPAAoKexh1RgBcAgAPAAoKexh1RgBcAgAAAA==.Paradots:BAACNQAFFH8LAAIJAAQKdQohCQDxAAAJAAQKdQohCQDxAAA1AAQKfzoAAgkACgraGhkGAJICAAkACgraGhkGAJICAAAA.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAABNQAECn8nAAIeAAgK/x3aBQC8AgAeAAgK/x3aBQC8AgAAAA==.Pastlives:BAAANQAECgUICQAAAA==.',
Ph='Phantasee:BAAANQADCgQIBAAAAA==.Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgcICwAGAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQAECggIAwAAAA==.Pixystix:BAAANQAECgQIDAABNQAECggIAwAGAAAAAA==.',
Po='Pomortem:BAAANQAECgYIDgAAAA==.Potsomancy:BAACNQAFFH8MAAIUAAYK1RoODwAAAgAUAAYK1RoODwAAAgA1AAQKfx8AAhQACQokJP1IAPECABQACQokJP1IAPECAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQAECgQIBAABNQAECgUICQAGAAAAAA==.Raivel:BAAANQAECgUIDwABNQAECgUIEAAGAAAAAA==.Rambogg:BAAANQADCgMIAwABNQAFFAYIEAAUAIIKAA==.Raneyth:BAAANQAECgYIDwAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQAECgEIAQABNQAECgoKQAAWADoUAA==.Ravusternath:BAAANQADCggIFQAAAA==.',
Re='Redwinetoast:BAAANQAECgUICwAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8rAAQIAAgKwxbABwCXAQAIAAgKwxbABwCXAQAJAAMKOg+ZPwCjAAAoAAEKAAAAJQAxAAABNQAECgYIFAAHAE0dAA==.Reposess:BAAANQABCggIFAAAAA==.Reshyk:BAAANQAECgYICQAAAA==.',
Rh='Rhobes:BAAANQADCggIJAAAAA==.Rhondta:BAAANQADCgEIAQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQAECgcIEwAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAGAAAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIHAAAAA==.',
Ru='Rumor:BAABNQAECn8cAAMlAAgK3xhQGQCkAQAlAAgK3xhQGQCkAQAnAAQKvgjhWQBmAAAAAA==.Rurry:BAACNQAFFH8OAAIJAAUKKhzQCACsAQAJAAUKKhzQCACsAQA1AAQKfyYAAwkACQqQI9EDAHgDAAkACQqQI9EDAHgDAAgAAQohJeI0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn8uAAMfAAoK1yGcFAAUAwAfAAoK1yGcFAAUAwAhAAIKMgpeugBTAAAAAA==.Ryuuko:BAAANQAECggICAAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8IAAMKAAIKgx46BgCkAAAKAAIKgx46BgCkAAAMAAEKIBBmGQBOAAA1AAQKfzAAAwoACgrJIqcGAGgDAAoACgoAIacGAGgDAAwABwqtEuApAHUBAAAA.',
Sa='Sabastion:BAAANQADCgMIAwABNQAECgcIEQAGAAAAAA==.Sableanne:BAAANQAECgEIAQAAAA==.Safetysham:BAAANQAECgIIAgAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYIBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAGAAAAAA==.Salmoo:BAAANQAECggIDwAAAA==.Saltytator:BAAANQAECgMIBQABNQAECggIHgAQAPkJAA==.Santhon:BAAANQADCgQICAAAAA==.Satanized:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggIKAAAAA==.',
Sc='Scaledaddy:BAABNQAECn8pAAMoAAoKvglGDACUAQAoAAkKYgpGDACUAQAIAAQK3AbdMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECgoKNAABAOEjAA==.Scaryl:BAABNQAECn8WAAInAAUKuwX+fADYAAAnAAUKuwX+fADYAAAAAA==.Schneè:BAABNQAECn83AAImAAoK3hPkEwDoAQAmAAoK3hPkEwDoAQAAAA==.Scoom:BAACNQAFFH8OAAIUAAUK5hyfGgCmAQAUAAUK5hyfGgCmAQA1AAQKfy8AAhQACQoFJcYZAG4DABQACQoFJcYZAG4DAAAA.Scourgespawn:BAACNQAFFH8LAAMgAAUKlhmoBwB+AQAgAAUKlhmoBwB+AQAfAAEKAADhIwA9AAA1AAQKfyoAAyAACQoeJMwQAAkDACAACQoeJMwQAAkDAB8ABAogEcOYAM8AAAAA.',
Se='Seikyo:BAABNQAECn81AAIhAAoKBAz+KgBIAQAhAAoKBAz+KgBIAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgYICwAGAAAAAA==.Selenë:BAAANQAECgYIDAAAAA==.Serok:BAAANQAECggIEAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcICgAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAGAAAAAA==.Shalis:BAAANQAECgYICQAAAA==.Sharivee:BAAANQAECgYICwAAAA==.Shazamir:BAABNQAECn8WAAIjAAcK4gRBIwAoAQAjAAcK4gRBIwAoAQAAAA==.Shibui:BAABNQAECn8wAAIWAAkKlhEmHAC6AQAWAAkKlhEmHAC6AQAAAA==.Shifthead:BAACNQAFFH8IAAInAAQKZgj1DQC/AAAnAAQKZgj1DQC/AAA1AAQKfy8AAxsACgoEGLgNAD4CABsACAoAGbgNAD4CACcACgodEag5ACMCAAAA.Shockazilla:BAABNQAECn8nAAIkAAkKHiLdHAAAAwAkAAkKHiLdHAAAAwAAAA==.Shortspanky:BAAANQAECgQIDQAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAABNQAECn8XAAIQAAcKKRJYvACkAQAQAAcKKRJYvACkAQAAAA==.',
Sk='Skoduh:BAAANQAECggIDgAAAA==.',
Sl='Slack:BAABNQAECn8cAAMNAAgKCCNBEwDNAgANAAgKCCNBEwDNAgARAAEKAACecABHAAABNQAECgYIFAAHAE0dAA==.Sluggo:BAACNQAFFH8MAAIQAAUK3xHUDAB+AQAQAAUK3xHUDAB+AQA1AAQKfyYAAhAACQrUICVTAJwCABAACQrUICVTAJwCAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIAQAAAA==.',
Sp='Spiralist:BAAANQAECgYIDAAAAA==.Spìne:BAAANQAECgQIBAAAAA==.',
St='Steelforged:BAAANQADCgQIBAABNQAECggIFAAaACoOAA==.Stonedalways:BAAANQAECgYIEQAAAA==.Stonytoni:BAAANQAECgMIAQAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQABNQAECgoKGAAZAKwQAA==.Sunfuri:BAABNQAECn8bAAIeAAgK0ATFGwDsAAAeAAgK0ATFGwDsAAAAAA==.Sus:BAACNQAFFH8NAAIWAAUKXBTcCgB1AQAWAAUKXBTcCgB1AQA1AAQKfyYAAxYACQrKIvIZAMsCABYACQrKIvIZAMsCACkABAp1C0giALAAAAAA.Susanoo:BAAANQAECgcICAAAAA==.',
Ta='Taalia:BAAANQAECgUIDwAAAA==.Talonas:BAAANQAECgYICwAAAA==.Tarathor:BAAANQAECgUICwAAAA==.Tatortott:BAAANQAECgYICgABNQAECggIHgAQAPkJAA==.',
Te='Teknofarious:BAABNQAECn8eAAMZAAkK7QvGAQCDAQAZAAkK7QvGAQCDAQAHAAEKAAAmSwAvAAAAAA==.',
Th='Thesafe:BAAANQAECgYIDQAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAABNQAECn8UAAMHAAYKTR1sDAD0AQAHAAYKTR1sDAD0AQAUAAQKYgaHfgHGAAAAAA==.Thialaa:BAAANQAECggIEQABNQAECgkJLgADAMEiAA==.Thialia:BAABNQAECn8pAAINAAoKPA5BQACzAQANAAoKPA5BQACzAQABNQAECgkJLgADAMEiAA==.Thialiaa:BAAANQAECgQIBgABNQAECgkJLgADAMEiAA==.Thialiadin:BAABNQAECn8WAAIiAAkKrhXgDgCwAQAiAAkKrhXgDgCwAQABNQAECgkJLgADAMEiAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn81AAISAAoKWxzsAADqAgASAAoKWxzsAADqAgAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAIICAAKAIMeAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgYIEAAAAA==.Trema:BAABNQAECn9AAAMiAAoK6xcWFQBZAgAiAAgKNBwWFQBZAgAQAAoK9ws8uACtAQAAAA==.Trialei:BAAANQABCgIIAgAAAA==.Trick:BAAANQAECgMIAwAAAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgYIDQABNQAECgoKNQAKADoeAA==.',
Tu='Tulsi:BAAANQAECgcIDQAAAA==.',
Ty='Tyronos:BAABNQAECn8WAAIQAAgKPA8ojwAzAQAQAAgKPA8ojwAzAQAAAA==.',
Va='Vaeltharion:BAAANQAECgYIDgAAAA==.Varedrae:BAAANQADCggIFQAAAA==.Vas:BAAANQADCgYIFAAAAA==.Vaydark:BAAANQADCgQIBAABNQAECgkJMAAWAJYRAA==.',
Ve='Verdandi:BAAANQAECgUICgAAAA==.Vevicenth:BAABNQAECn8YAAMZAAgKcgSsBgDoAAAUAAcKBQSTpAD9AAAZAAYKZgOsBgDoAAAAAA==.',
Vo='Voranth:BAABNQAECn8lAAMOAAkK6iFPDAABAwAOAAkK6iFPDAABAwAPAAQKIBItxgAGAQAAAA==.',
Wa='Wainstatick:BAAANQADCgcIBwAAAA==.Warenio:BAABNQAECn8hAAImAAgKeBdTEAAjAgAmAAgKeBdTEAAjAgAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMHAAkKaRqLCwAIAgAHAAkKfRaLCwAIAgAUAAYKrR0SzwDoAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECggIGQAaAJgKAA==.',
Wh='Whakan:BAAANQADCggIIgABNQAECgYIBwAGAAAAAA==.',
Wi='Williamgoat:BAAANQADCggIEQABNQAECgoKNQAKADoeAA==.',
Wo='Wolfos:BAAANQAECgIICgAAAA==.',
Wt='Wtfox:BAEBNQAECn8dAAIRAAgKzRCRKQDbAQARAAgKzRCRKQDbAQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAABNQAECn8aAAMXAAcKMw1UIgAVAQAXAAcKMw1UIgAVAQAWAAMKfATQaAA1AAAAAA==.',
Xa='Xalatos:BAAANQAECggIEAAAAA==.Xalfein:BAAANQADCggIJAAAAA==.',
Xi='Xinu:BAAANQAECgQIBAABNQAECgkJLAADAP4aAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Xy='Xylendra:BAAANQAECgUIBQABNQAECgcIFgAaAJ8GAA==.',
Ya='Yanakana:BAAANQAECgUIDAAAAA==.',
Yd='Ydrassil:BAAANQABCgQIBAABNQAECggIDwAGAAAAAA==.',
Za='Zakeko:BAABNQAECn8UAAMYAAUKHRTU1ABHAQAYAAUKHRTU1ABHAQAmAAEKAAD6PQBLAAAAAA==.Zanderpryde:BAABNQAECn8aAAINAAkK6QllRACgAQANAAkK6QllRACgAQABNQAECgoKLAATALAeAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAABNQAECn8fAAIDAAcK7RI5VQCdAQADAAcK7RI5VQCdAQAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn8sAAIDAAkK/hq5MAAdAgADAAkK/hq5MAAdAgAAAA==.Zivalisse:BAAANQAECgIIAwAAAA==.',
Zo='Zota:BAABNQAECn8ZAAIDAAkKuxPrQADgAQADAAkKuxPrQADgAQAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgYIGwAkAKAhAA==.Zulfionn:BAABNQAECn8cAAIDAAcKIQdvdgBIAQADAAcKIQdvdgBIAQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgYIFAAHAE0dAA==.',
['Áy']='Áyrá:BAAANQAECgYIEgAAAA==.',
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
