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

local lookup = {'Priest-Holy','Unknown-Unknown','Warrior-Protection','Mage-Frost','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Balance','Warlock-Demonology','DeathKnight-Unholy','Druid-Guardian','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Shaman-Enhancement','Paladin-Protection','Priest-Shadow','Priest-Discipline','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgcIDAAAAA==.Adolin:BAAANQAECgUIBQABNQAECgkJOAABAPAfAA==.',
Af='After:BAAANQADCgMIBAABNQAECgcIEwACAAAAAA==.Afterall:BAAANQAECgMIAwABNQAECgcIEwACAAAAAA==.',
Ag='Aggropull:BAABNQAECn8xAAIDAAgKjwlLHABzAQADAAgKjwlLHABzAQAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgUIEQACAAAAAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAABNQAECn8cAAIEAAgKmxKKCQA2AgAEAAgKmxKKCQA2AgAAAA==.',
Ap='Apoptosis:BAAANQADCgcIDwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcamania:BAAANQAFFAEIAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Aryndinnin:BAABNQAECn8gAAIFAAkKDBlMEAB2AgAFAAkKDBlMEAB2AgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQAECgQIBAAAAA==.',
At='Athrunn:BAAANQAECggIDgABNQAECgkJJwAGAAUmAA==.Attincy:BAAANQADCggIKgAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECn8kAAIHAAgKixACpADTAQAHAAgKixACpADTAQAAAA==.',
Ay='Ayah:BAABNQAECn8dAAIBAAgKbxULVgAdAgABAAgKbxULVgAdAgAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECn8iAAIIAAcKggtJSACCAQAIAAcKggtJSACCAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECn8bAAIJAAcKbRNBrQCmAQAJAAcKbRNBrQCmAQAAAA==.',
Ba='Babycale:BAABNQAECn8cAAIKAAkKsRz4DgAHAwAKAAkKsRz4DgAHAwAAAA==.Badger:BAAANQAECgQIBgAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Beardette:BAAANQABCgIIAgAAAA==.Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgYIEgAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECgIIAgABNQAECgkJIwALAPYXAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECn8gAAIMAAgK8geEpQCEAQAMAAgK8geEpQCEAQAAAA==.',
Bf='Bfx:BAABNQAECn8ZAAINAAkKbQ+fUwDAAQANAAkKbQ+fUwDAAQAAAA==.',
Bi='Biggiesize:BAAANQADCggICAAAAA==.Bigred:BAAANQADCgUIAgAAAA==.Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECn8aAAIOAAcK5BwSEwAsAgAOAAcK5BwSEwAsAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgkJGAAHAGkXAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECn8pAAMPAAkKrCIHCAB8AwAPAAkKrCIHCAB8AwANAAMKeREEsQCLAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQICAACAAAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAAANQAECgcIEgAAAA==.Bustie:BAAANQAECgEIAgAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAMICQAQAJ8WAA==.Calahunts:BAACNQAFFH8JAAIQAAMKnxZHFgADAQAQAAMKnxZHFgADAQA1AAQKfy4AAxAACQohJA0JAJQDABAACQohJA0JAJQDAAYAAQq8At6aACIAAAAA.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAABNQAECn8VAAIRAAcKLwo0nAA8AQARAAcKLwo0nAA8AQAAAA==.Catlinn:BAABNQAECn8bAAMSAAYKSAJB4gC3AAASAAYKSAJB4gC3AAAHAAIKvwDq0QEXAAAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAABNQAECn8kAAIFAAkKeCELBgA5AwAFAAkKeCELBgA5AwAAAA==.',
Ch='Charinae:BAAANQADCgUIBQAAAA==.Chokeahoa:BAAANQADCggIDAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECn8hAAIHAAkKXxaQYgBuAgAHAAkKXxaQYgBuAgAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Cleaveauge:BAABNQAECn8aAAIJAAgKZBKthAAMAgAJAAgKZBKthAAMAgAAAA==.Cloggy:BAACNQAFFH8KAAMMAAUKrByAFQBOAQAMAAQKrByAFQBOAQATAAEKAACDCgBTAAA1AAQKfy0AAwwACQo4JAcIAIsDAAwACQo4JAcIAIsDABQAAQpgJGNcAGwAAAAA.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgMICAACAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAABNQAECn8fAAIVAAkKRB2NXgDCAgAVAAkKRB2NXgDCAgAAAA==.Corpulent:BAAANQADCgQIBAAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAABNQAECn8eAAIQAAkKjRUUUwB1AgAQAAkKjRUUUwB1AgAAAA==.',
Cr='Crackasmasha:BAAANQADCggIFgAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgQICAABNQAECggIGwAWAIYXAA==.Crownpal:BAAANQAECgYIDAABNQAECgkJIwAXAKkbAA==.Crownroyale:BAABNQAECn8jAAIXAAkKqRt7CQCGAgAXAAkKqRt7CQCGAgAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAUIDwARALQdAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAABNQAECn8uAAMWAAkKvhHqUgAqAgAWAAkKvhHqUgAqAgARAAEK6wFQIgEnAAAAAA==.Daityasfist:BAACNQAFFH8OAAIYAAYKWCTaAgBHAgAYAAYKWCTaAgBHAgA1AAQKfx0AAhgACQrZJhkEAJIDABgACQrZJhkEAJIDAAAA.Daler:BAAANQADCgYICQAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECn8WAAIZAAgKPxtuGwBYAgAZAAgKPxtuGwBYAgAAAA==.Danishhunter:BAAANQAECgEIAQAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAABNQAECn8aAAIaAAcKkwdqFgAxAQAaAAcKkwdqFgAxAQAAAA==.Darkseksi:BAAANQAECgQIBAAAAA==.Dashmodius:BAABNQAECn8iAAIbAAkKfR9aCgAzAwAbAAkKfR9aCgAzAwAAAA==.Datakutasa:BAAANQAECgYIDgAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQAECgEIAQAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQAECgQIBAAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAABNQAECn8bAAQcAAgKYQcxEgAMAQAcAAcKGAYxEgAMAQAdAAYK7QWDJgD/AAAeAAcKPwKzNADrAAAAAA==.Deathera:BAAANQAECgcIBwABNQAFFAUIDwARALQdAA==.Deathpack:BAACNQAFFH8NAAIfAAQK+yGeCQBHAQAfAAQK+yGeCQBHAQA1AAQKfzIAAh8ACQo5JQAEAKADAB8ACQo5JQAEAKADAAAA.Deathsmiley:BAABNQAECn8bAAMfAAgKRQ73QAC9AQAfAAgKRQ73QAC9AQAPAAIKQQOlxwA2AAAAAA==.Delani:BAAANQAECgMIBAAAAA==.Delavi:BAAANQADCgYIAwABNQAECgMIBAACAAAAAA==.Demonbob:BAABNQAECn8rAAIIAAgKfRj1LAA4AgAIAAgKfRj1LAA4AgAAAA==.Deohgee:BAAANQAECgUIDwAAAA==.Deranker:BAACNQAFFH8IAAIVAAMKGx2SMAADAQAVAAMKGx2SMAADAQA1AAQKfyYAAxUACQpvHqRlALMCABUACQpvHqRlALMCAAQAAQoAALZIADIAAAAA.Derpintine:BAAANQAECgEJAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAABNQAECn85AAIWAAkKuhsjJQDuAgAWAAkKuhsjJQDuAgAAAA==.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAABNQAECn8eAAIRAAgKnQ/adgCjAQARAAgKnQ/adgCjAQAAAA==.Diyther:BAAANQAECgYIEwAAAA==.',
Dk='Dkaara:BAAANQADCggIEgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECn8mAAIbAAgKPRdVIABIAgAbAAgKPRdVIABIAgAAAA==.',
Dr='Draganhammer:BAABNQAECn8nAAIHAAkKJxKJeQA0AgAHAAkKJxKJeQA0AgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Dreadvyr:BAAANQAECggICAAAAA==.Droodar:BAAANQAECgEIAQABNQAECgUIEQACAAAAAA==.Droopey:BAABNQAECn8bAAIVAAcK+QZJEQFsAQAVAAcK+QZJEQFsAQAAAA==.',
Du='Duckywg:BAABNQAECn8gAAIIAAgKTxKaMwALAgAIAAgKTxKaMwALAgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMJAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgYICgAAAA==.',
Ec='Eclipsea:BAAANQAECgUIEQAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECn8qAAISAAgKoB4OKADGAgASAAgKoB4OKADGAgAAAA==.Eiryn:BAAANQADCgUICQAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECn8hAAIgAAcKXB87DwB0AgAgAAcKXB87DwB0AgAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQAECgQIBAAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAAANQAECgYIEAAAAA==.',
Ew='Ewanae:BAABNQAECn8YAAMgAAkKrhK1EwAqAgAgAAkKrhK1EwAqAgAWAAIKUQIrGgFUAAABNQAFFAIIAgACAAAAAA==.',
Fa='Falygarro:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgMIAwAAAA==.',
Fi='Fiolidris:BAAANQAECgQIBAAAAA==.Firetotes:BAABNQAECn8tAAIRAAkKkB1sHQD1AgARAAkKkB1sHQD1AgAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgABNQADCggIFgACAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Foidscarred:BAACNQAFFH8HAAIIAAYKBA1ICACtAQAIAAYKBA1ICACtAQA1AAQKfxUAAggACAp8H8AYANECAAgACAp8H8AYANECAAE1AAUUAwoJABoAnBsA.Forfoxsakes:BAAANQAECgQIBwAAAA==.Forget:BAABNQAECn8bAAQPAAcK/B2PRQDhAQAPAAYKXx+PRQDhAQAfAAQKfxajagDrAAANAAMKmwz5sQCJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCggIHAABNQAECggIGgAJAGQSAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAABNQAECn8WAAMfAAgKHSMkEQADAwAfAAgKHSMkEQADAwANAAQKpBuCdQA+AQABNQAFFAQICAAQAIkgAA==.Fruitluupz:BAAANQAECgQICQAAAA==.',
['Fæ']='Færrow:BAAANQADCggICwAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQAECgcIEQAAAA==.Garomok:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECggIEQABNQAFFAMIBQAMALQiAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgUIBwAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgQICAAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgYICQAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgQIBgAAAA==.Greenmonk:BAAANQAECgYICAAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQAECgUIDwAAAA==.Grippyfemboy:BAAANQAECgMIAwABNQAFFAcIGwAhADcmAA==.Grün:BAAANQAECgQICQAAAA==.',
Gu='Gulugg:BAAANQADCgYIBgAAAA==.Gurfquake:BAABNQAECn8bAAMWAAgKhhflQABvAgAWAAgKhhflQABvAgARAAMK3BAU7wCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgIIBAABNQAECgkJIgAbAH0fAA==.Hanahanug:BAAANQADCgYIBwAAAA==.Hangwenaz:BAABNQAECn8vAAIJAAkKCB5rIgAtAwAJAAkKCB5rIgAtAwABNQAECgkJIAAFAAwZAA==.Harrell:BAAANQAECgMIAwAAAA==.',
He='Headsplitter:BAAANQAECgEIAgAAAA==.Hearah:BAABNQAECn8fAAMRAAcKDQ8ZjABnAQARAAcKDQ8ZjABnAQAWAAYKdQVGxgABAQAAAA==.Helk:BAAANQADCggICQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hexdabear:BAAANQAECgUICQABNQAECgcIDQACAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgQICAABNQAECgcIDQACAAAAAA==.Hexvoker:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Hexxer:BAAANQAECgQIBQABNQAECgcIDQACAAAAAA==.Hexzel:BAAANQAECgcIDQAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECggIIgAVAIMSAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFH8KAAISAAMKTSTJEQA9AQASAAMKTSTJEQA9AQA1AAQKfy0AAhIACQp4JM8DALUDABIACQp4JM8DALUDAAAA.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECn8lAAIVAAkKFBpAdACVAgAVAAkKFBpAdACVAgABNQAFFAcIEwANAGMkAA==.Hondô:BAECNQAFFH8TAAQNAAcKYyQtAADdAgANAAcKYyQtAADdAgAfAAIKZyC8EQC4AAAPAAEKAAC5KwBDAAA1AAQKf1MAAw0ACQoFJxEAAB0EAA0ACQoFJxEAAB0EAA8AAQoAAPewAGUAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwABNQAFFAcIEwAYAOsZAA==.',
Hu='Huntermanjoe:BAABNQAECn8ZAAIQAAgK5g5OdgAgAgAQAAgK5g5OdgAgAgAAAA==.Huntersdie:BAAANQADCgYICQAAAA==.Hunterzalt:BAABNQAECn8qAAIPAAgKFBawPwD9AQAPAAgKFBawPwD9AQAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAcIEwANAGMkAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAABNQAECn8WAAIHAAgKsxj4cQBHAgAHAAgKsxj4cQBHAgAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgQIBAAAAA==.',
Id='Idra:BAABNQAECn8nAAIGAAkKBSbRAgCxAwAGAAkKBSbRAgCxAwAAAA==.',
If='Iffa:BAAANQAECgEIAwABNQAECgMIBAACAAAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgcIEAAAAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgQIBAACAAAAAA==.Itsmyfault:BAAANQADCgYIDwAAAA==.',
Ja='Jackul:BAAANQAECgcICAAAAA==.Jakilk:BAABNQAECn8eAAMNAAcKRwfTdgA6AQANAAcKRwfTdgA6AQAPAAQK6AGOrABxAAAAAA==.Jakilky:BAABNQAECn8bAAMPAAYKDwSbjQDIAAAPAAYKgAObjQDIAAANAAUKzgLnqgCbAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQADCggIDAAAAA==.Jaycomo:BAAANQADCggJEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECn8gAAIHAAcKOQfn5wBFAQAHAAcKOQfn5wBFAQAAAA==.',
Je='Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBQABNQAECggIHgANAD4fAA==.Jellydead:BAABNQAECn8eAAINAAgKPh/FLwBuAgANAAgKPh/FLwBuAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQAECgIIAgAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwACAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIDgABNQAECggIGgAJAGQSAA==.Juggernåut:BAAANQAECgQIBAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFH8PAAIRAAUKtB34BwDRAQARAAUKtB34BwDRAQA1AAQKfysAAxEACQpxIUEVACIDABEACQpxIUEVACIDABYABwq5DreMAIABAAAA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECn8kAAILAAkKVBYIKQCMAgALAAkKVBYIKQCMAgABNQABCgYIDAACAAAAAA==.Kaelthuss:BAAANQAECgUIDQAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQJCAAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAAANQAECggIEQAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECn8bAAIJAAkKOh3GRQC1AgAJAAkKOh3GRQC1AgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAACAAAAAA==.',
Ko='Kobii:BAAANQAECgEIAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAAANQAECgcIEwAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgEIAQAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ku='Kurokitsune:BAAANQAECgQIBAAAAA==.',
Ky='Kylofinn:BAAANQAECgUICgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAABNQAECn8dAAIhAAcK4BTHJgCkAQAhAAcK4BTHJgCkAQAAAA==.Laesandra:BAAANQAECgMIBQAAAA==.Lalatide:BAAANQAECgUICwAAAA==.Lastris:BAAANQAECgcIEgAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgcICwACAAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAABNQAECn8YAAIHAAcKoBOYrQC/AQAHAAcKoBOYrQC/AQAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFH8bAAIhAAcKNyZEAAAGAwAhAAcKNyZEAAAGAwA1AAQKfy0AAiEACQrnJr8AAOYDACEACQrnJr8AAOYDAAAA.Lildwarf:BAEANQAECgcIEwAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgACAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECn8fAAINAAgKuBAJTgDZAQANAAgKuBAJTgDZAQAAAA==.Lizerd:BAAANQADCgYIBgABNQAECgkJMAABAEQgAA==.',
Lo='Lochgimli:BAAANQABCgUIBwAAAA==.Louvetier:BAAANQAECgEIAQAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFH8ZAAQMAAcKoB27AQCMAgAMAAcKoB27AQCMAgATAAEKAAB/CwBOAAAUAAEKkgvUHwBJAAA1AAQKfycAAwwACQrnJeIFAJ8DAAwACQrnJeIFAJ8DABQABwrgG6IQAPUBAAAA.Luckyboi:BAABNQAECn8nAAMVAAkKMBm4bQCiAgAVAAkK7Ra4bQCiAgAEAAMKyxYwJADJAAAAAA==.Luckymeoww:BAABNQAECn8mAAMNAAgK4BNdTQDcAQANAAgK4BNdTQDcAQAfAAQKbhFkcwDLAAAAAA==.Luurain:BAAANQADCggICAAAAA==.',
['Lð']='Lðxic:BAAANQAECgQICgAAAA==.',
Ma='Maeveran:BAABNQAECn8cAAMHAAgKLwyZtQCtAQAHAAgKLwyZtQCtAQAhAAEKAADmdQAlAAAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIAAFAAwZAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQABCgYJCwAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgIIAgAAAA==.Mangonutt:BAAANQADCggIEgAAAA==.Maryjuana:BAABNQAECn8qAAIiAAkKPA4VJQADAgAiAAkKPA4VJQADAgAAAA==.Mastalys:BAEANQAECgUIBQAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECn8tAAMBAAkKnxTTUwAkAgABAAkKnxTTUwAkAgAiAAcKGBYjKQDcAQAAAA==.Mavina:BAABNQAECn84AAMBAAkK8B95EQA7AwABAAkK8B95EQA7AwAjAAEKVgVfMAAiAAAAAA==.Mazez:BAAANQAECgYIDAAAAA==.',
Me='Meanmuggin:BAAANQAECgUIBwAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYIEQANAJQaAA==.Meketek:BAABNQAECn8aAAIfAAcKaxXJRwCYAQAfAAcKaxXJRwCYAQAAAA==.Melodica:BAAANQAECgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAABNQAECn8yAAIVAAkKbhhoXwDAAgAVAAkKbhhoXwDAAgAAAA==.Mercader:BAAANQAECgQIBgAAAA==.Merrvoid:BAABNQAECn8qAAIQAAkKWhX+TgB/AgAQAAkKWhX+TgB/AgAAAA==.Messîah:BAAANQAECgYIBgAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAABNQAECn8aAAIdAAgKHwd/GwCQAQAdAAgKHwd/GwCQAQAAAA==.Mildo:BAABNQAECn8iAAIUAAcKnBp5CQBhAgAUAAcKnBp5CQBhAgAAAA==.Millerlight:BAAANQAECgUIBQAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.Minervá:BAAANQAFFAIIAgAAAA==.Minotàurus:BAAANQAECgcIDQAAAA==.Mintonka:BAABNQAECn8UAAIWAAcK1gPVwQAKAQAWAAcK1gPVwQAKAQAAAA==.Miranaaster:BAABNQAECn8WAAIVAAkKtBXyfACEAgAVAAkKtBXyfACEAgAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAAANQAECgYIDAABNQAECgkJJQASAEsQAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECn8jAAILAAkK9hfIJgCaAgALAAkK9hfIJgCaAgAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Moraien:BAAANQAFFAQIBAAAAA==.Morchanna:BAAANQAECggIEwAAAA==.Morf:BAAANQADCgMIBAAAAA==.Morgy:BAAANQADCggICAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrokorian:BAAANQADCgcIBwAAAA==.Mystichex:BAAANQAECgIIAgABNQAECgcIDQACAAAAAA==.',
['Mä']='Mäzikeen:BAAANQAECgYIDQABNQAECggIIAAfAG0fAA==.',
Na='Natalietes:BAAANQAECgYICgAAAA==.Nattylight:BAABNQAECn8aAAMPAAcKnRGeVgCWAQAPAAcKnRGeVgCWAQANAAEKlQU97wAlAAAAAA==.Nattylite:BAAANQADCgQIBgABNQAECggIGwAWAIYXAA==.',
Ne='Newhealer:BAAANQAECgIIAwAAAA==.',
Ni='Nibletz:BAAANQADCgcICAAAAA==.Ninelinez:BAABNQAECn8XAAIXAAcKzCN8BwDBAgAXAAcKzCN8BwDBAgAAAA==.',
No='Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAAANQAECgUIEQABNQAECgcICwACAAAAAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgcIFwAXAMwjAA==.',
['Nò']='Nòte:BAAANQADCgQIBAABNQAECgIJAgACAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQAECgcICwAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwACAAAAAA==.',
Ol='Oldnote:BAAANQADCgIIAgAAAA==.Oleßigßahlz:BAAANQADCgEIAQAAAA==.Olgalina:BAAANQADCgQICAABNQAECgUIEQACAAAAAA==.Olorinn:BAAANQABCgQIBAAAAA==.',
Op='Opirix:BAABNQAECn8wAAMBAAkKRCCZIQDmAgABAAkKRCCZIQDmAgAiAAYKzBqvJwDpAQAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgYIEwAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAABNQAECn8ZAAILAAgK4gwkRwDMAQALAAgK4gwkRwDMAQAAAA==.Patreszas:BAABNQAECn8mAAIdAAgKwhYWEwAbAgAdAAgKwhYWEwAbAgAAAA==.Pawshocker:BAABNQAECn8eAAIgAAkKfSHtBwD6AgAgAAkKfSHtBwD6AgABNQAFFAcIGwAhADcmAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Peàches:BAAANQAECgMIAgAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgEIAgAAAA==.',
Po='Pohaberry:BAABNQAECn8kAAIQAAkKUBKMWABnAgAQAAkKUBKMWABnAgAAAA==.Pokemage:BAABNQAECn8fAAIVAAgK4Q2U0QDhAQAVAAgK4Q2U0QDhAQAAAA==.Popedk:BAABNQAECn8jAAMNAAkKpyB4EgAiAwANAAkKpyB4EgAiAwAfAAEKPhlPogBCAAABNQAFFAYIDAAWAKAXAA==.Popesham:BAABNQAFFH8MAAIWAAYKoBfwBgAFAgAWAAYKoBfwBgAFAgAAAA==.',
Pr='Priestduude:BAAANQAECgYJBgAAAA==.Product:BAAANQAECgIIAgAAAA==.',
Pu='Pullacrapton:BAAANQAECgQIBgAAAA==.',
Qu='Quasi:BAABNQAECn8jAAIiAAkKOBeHFwCYAgAiAAkKOBeHFwCYAgAAAA==.Quiggins:BAABNQAECn8pAAIHAAgKdAXn4ABTAQAHAAgKdAXn4ABTAQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJIgAXAE8TAA==.Quirky:BAAANQADCgUIEwAAAA==.',
Ra='Raeziel:BAAANQAECgMIAwAAAA==.Raffunn:BAAANQADCgcICQABNQAECgMIAwACAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQADCgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgEIAQAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgQIDQABNQAFFAQIDQAfAPshAA==.Reignz:BAAANQAECgQIDQAAAA==.Reinhardt:BAABNQAECn8nAAMhAAkKIB1WCQAGAwAhAAkKIB1WCQAGAwAHAAcKIhI/ywB/AQAAAA==.Reticular:BAAANQAECgcIDgAAAA==.',
Rh='Rhaenne:BAAANQAECgMIBAAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcICAAAAA==.',
Ru='Rubonyx:BAAANQAECgUIEQAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECn8WAAIKAAcKXwgJUgBuAQAKAAcKXwgJUgBuAQAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAAANQAECggIEwAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAQABNQAECgIIAgACAAAAAA==.',
Sa='Sagerin:BAAANQAECgUIDgAAAA==.Sageslife:BAAANQAECgUIEQAAAA==.Saintofthetp:BAAANQAECgEIAQAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Screamodevo:BAAANQABCgIIAgAAAA==.Scronk:BAAANQADCgcIBwABNQAECgMIBQACAAAAAA==.Scruffmcgruf:BAABNQAECn8aAAIBAAgKzA7EbQDQAQABAAgKzA7EbQDQAQAAAA==.Scubany:BAAANQADCgIJAgAAAA==.Scyl:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.',
Se='Senadora:BAABNQAECn8VAAIYAAcKoR3NIAAiAgAYAAcKoR3NIAAiAgAAAA==.Sergrahm:BAAANQADCgYIDwAAAA==.Sezeth:BAAANQAFFAIIAgAAAA==.',
Sh='Shaboomboom:BAACNQAFFH8FAAIWAAIKHRTMIQCjAAAWAAIKHRTMIQCjAAA1AAQKfyYAAhYACQrfHG0tAMUCABYACQrfHG0tAMUCAAAA.Shadowglaive:BAABNQAECn8lAAIbAAkKLx+5CQA7AwAbAAkKLx+5CQA7AwAAAA==.Shadownight:BAABNQAECn8iAAINAAgKTyNKFgAHAwANAAgKTyNKFgAHAwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Shanice:BAAANQADCgMIAwAAAA==.Sharburst:BAAANQAECggIDgAAAA==.Sharleet:BAAANQAECggIBwAAAA==.Sharlocke:BAAANQAECgYIBgAAAA==.Shaval:BAABNQAECn+TAQIHAAkK/SZaAAAPBAAHAAkK/SZaAAAPBAAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFH8KAAMJAAQK/hAFHQAjAQAJAAQKUg4FHQAjAQAaAAIK8g16AwCPAAA1AAQKfyUAAwkACQokG25iAGMCAAkACQrMGm5iAGMCABoAAwqtG2saAPsAAAAA.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgUIDwAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCggIDQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECn8iAAIXAAkKTxPyDQAVAgAXAAkKTxPyDQAVAgAAAA==.Shøøtingstar:BAAANQAECgUICAABNQAECggIIAAfAG0fAA==.',
Si='Signet:BAAANQAECgUIEQAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skoss:BAABNQAECn8gAAMMAAgK7hGkYgAtAgAMAAgKlRGkYgAtAgAUAAIKxw4WWgBxAAAAAA==.Skullshine:BAACNQAFFH8bAAMNAAYKZyEUBQDUAQANAAUKZyEUBQDUAQAPAAEKAAD0NQAlAAA1AAQKfyUAAg0ACQoIJV0OAEQDAA0ACQoIJV0OAEQDAAAA.Skunkie:BAABNQAECn8ZAAMRAAgKmRKZZgDVAQARAAgKmRKZZgDVAQAWAAEK1hjSIQFGAAAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDAAAAA==.Slickfifty:BAAANQAECgEIAgAAAA==.Slippewy:BAAANQAECgIIAgAAAA==.Sluewt:BAAANQAECggIEQABNQAECgkJKgABAIwhAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smolderr:BAABNQAECn8aAAIQAAgKmQU+tQCVAQAQAAgKmQU+tQCVAQAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQAECgYIEwAAAA==.Spearowhunt:BAAANQAECgYIBgAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIFgAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECn8gAAQfAAgKbR+6GQC6AgAfAAgKah66GQC6AgAPAAYKwwyreAARAQANAAMKOBS2mwDDAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECgcICwAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stun:BAAANQAECgIIAgAAAA==.Stunllub:BAAANQAECgcICwAAAA==.',
Su='Suggs:BAACNQAFFH8KAAQMAAUKXRviHQAFAQAMAAMK7yLiHQAFAQAUAAEKOAx3HgBLAAATAAEKAACJDgBHAAA1AAQKfyMABAwACQqaITk1ALICAAwACApbITk1ALICABMAAwpcHpgXAM4AABQAAgqrG7tSAIUAAAAA.Surnaturelle:BAAANQADCggICAABNQAECggIJQAgAEkPAA==.',
Sw='Swiiani:BAAANQAECgUIEQAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECgcIDAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQACAAAAAA==.',
Ta='Taelinn:BAAANQADCggICAABNQAECggIJgAdAMIWAA==.Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECgUICgAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAXAE8TAA==.Taurelai:BAAANQABCggIDgAAAA==.Tauriko:BAABNQAECn8oAAIHAAkKZRsoSgCzAgAHAAkKZRsoSgCzAgAAAA==.Tayvos:BAAANQAECggIBwAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAABNQAECn8eAAQNAAgKqBeSPQAmAgANAAgKqBeSPQAmAgAfAAIKPARBmgBXAAAPAAEKoBVUwQBCAAAAAA==.',
Th='Thebestlorax:BAAANQAECgYIBwABNQAECgkJIgAXAE8TAA==.Theler:BAAANQAECgMIAwABNQAFFAUICgAMAKwcAA==.Theradestria:BAAANQAECgUIDAAAAA==.Thestigg:BAABNQAECn8XAAIHAAgKVAoHwACWAQAHAAgKVAoHwACWAQAAAA==.Thighighs:BAAANQAECgIIAgABNQAFFAYIEAAHAFEaAA==.Thndrdwnundr:BAAANQADCgEIAQAAAA==.Thundersloot:BAAANQAECgEIAQABNQAECgYICQACAAAAAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAABNQAECn8fAAMUAAgKLAgvLgARAQAMAAYKOgjfywAtAQAUAAYKvQUvLgARAQAAAA==.',
To='Toedumbz:BAAANQAECgcIDAAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQADCgEIAQAAAA==.Troflgar:BAAANQAECgYICQAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgYIBgABNQAECggIGgAJAGQSAA==.',
Ts='Tsuky:BAAANQAECgQIBAAAAA==.Tsukytank:BAAANQAECgEIAgAAAA==.Tsumikui:BAABNQAECn8wAAQUAAkKpRJHDAAxAgAUAAgKkA9HDAAxAgAMAAkKmwzPewDsAQATAAgKNw2zCQDjAQAAAA==.',
Ty='Tyinastor:BAAANQAECgMIAwAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAAANQAECgcIEAAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Un='Unalived:BAABNQAECn8iAAIVAAgKgxIbuAASAgAVAAgKgxIbuAASAgAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAAANQAECggIEAAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCgcIDgAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Vanillia:BAAANQAECgYIBgAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQAECgcIDwAAAA==.Varíann:BAAANQADCgcIDAAAAA==.',
Ve='Velro:BAAANQAECggIDQAAAA==.Vemmox:BAAANQAECgcIEAAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venefica:BAAANQAECgEIAQAAAA==.Venôm:BAAANQAECggICAAAAA==.Veroks:BAAANQADCgUIDQABNQAECggIDQACAAAAAA==.Vesemir:BAABNQAECn8gAAIbAAcK1A8+MQCzAQAbAAcK1A8+MQCzAQAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAABNQAECn8bAAIHAAgKdxDzpQDPAQAHAAgKdxDzpQDPAQAAAA==.Vindictive:BAAANQAECggICAAAAA==.Vitals:BAABNQAECn8qAAIkAAgKtAbFJACeAQAkAAgKtAbFJACeAQAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgMIBQAAAA==.',
Wa='Warscared:BAAANQAECgcIEwAAAA==.Wasabis:BAABNQAECn8sAAIWAAgKfgnyfQCmAQAWAAgKfgnyfQCmAQAAAA==.',
We='Wels:BAABNQAECn8qAAIBAAkKjCHeEQA4AwABAAkKjCHeEQA4AwAAAA==.',
Wh='Whichwitch:BAAANQADCgUICAAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgYIEwAAAA==.',
Wi='Wigglypuffsr:BAABNQAECn8YAAIHAAkKaReocwBDAgAHAAkKaReocwBDAgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECn8kAAIVAAkKcR8jOgATAwAVAAkKcR8jOgATAwAAAA==.Winddrake:BAAANQAECgYIDAAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQAECgQIBwAAAA==.Xanneste:BAABNQAECn8dAAIIAAgKxgmIRQCUAQAIAAgKxgmIRQCUAQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xe='Xecutioner:BAAANQAECgIIAgAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQADCggICgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yo='Yoshiyokai:BAAANQAECggIBwAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAaAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAAANQAECggIDQABNQAFFAQIDQAfAPshAA==.',
['Yâ']='Yâtiri:BAAANQADCggIGAAAAA==.',
Za='Zaebos:BAAANQADCgcIBwAAAA==.Zalfanso:BAEANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQABCgQIBAAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICgAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQAECgcIDwAAAA==.',
Zi='Ziralila:BAABNQAECn8aAAIQAAcKpwh2tQCUAQAQAAcKpwh2tQCUAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQAECgYIEQAAAA==.',
Zu='Zuglybob:BAAANQADCgUIBwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Óm']='Ómèn:BAAANQAECgMIBAAAAA==.',
['Ör']='Örin:BAABNQAECn8xAAMKAAkKJCNdBACOAwAKAAkKBiJdBACOAwAlAAgKTR9nBADHAgAAAA==.',
['ße']='ßeast:BAAANQADCggICgAAAA==.',
['ßl']='ßlaze:BAAANQADCgIIAgAAAA==.',
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
