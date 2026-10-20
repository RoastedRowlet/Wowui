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

local lookup = {'Priest-Holy','Warlock-Demonology','Warrior-Protection','Priest-Discipline','Mage-Frost','Unknown-Unknown','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Shaman-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Shaman-Enhancement','Paladin-Protection','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abraxøs:BAAANQADCgEIAQAAAA==.',
Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgcIDAAAAA==.Adolin:BAAANQAECgUIBQABNQAECgoKQAABAOQeAA==.',
Af='After:BAAANQADCgMIBQABNQAECgoKHgACAE4TAA==.Afterall:BAAANQAECgMIAwABNQAECgoKHgACAE4TAA==.',
Ag='Aggropull:BAABNQAECn8zAAIDAAkKFwmuHABzAQADAAkKFwmuHABzAQAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgcIHgAEAPgiAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQADCgEIAQAAAA==.Aleriath:BAAANQADCggIEgAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Alroy:BAAANQADCgIIAgAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Ambry:BAAANQADCgEIAQAAAA==.Amordrolan:BAAANQAECgEIAgAAAA==.',
An='Anchovia:BAAANQADCgYICgAAAA==.Ankhesukmoon:BAAANQADCgcICgAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQADCgEIAQAAAA==.Anthonyisme:BAABNQAECn8gAAIFAAkKfBC1CQA1AgAFAAkKfBC1CQA1AgAAAA==.Anthonysbear:BAAANQAECgEIAQABNQAECgkJIAAFAHwQAA==.Anugoron:BAAANQADCgEIAQAAAA==.',
Ap='Apoptosis:BAAANQADCgcIFwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcamania:BAAANQAFFAEIAQABNQADCgEIAQAGAAAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQADCgEIAQAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Arthalon:BAAANQAECgEIAQAAAA==.Aryndinnin:BAABNQAECn8gAAIHAAkKDBmPEAB2AgAHAAkKDBmPEAB2AgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Ashmay:BAAANQAECgEIAQAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQAECgQIBAAAAA==.',
At='Athrunn:BAAANQAECggIDgABNQAECgoKMAAIAFslAA==.Attincy:BAAANQADCggILAAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECn8sAAIJAAkKig8lKwB+AQAJAAkKig8lKwB+AQAAAA==.',
Ay='Ayah:BAABNQAECn8gAAIBAAkKHBQxVwAdAgABAAkKHBQxVwAdAgAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECn8jAAIKAAgKzwo2SQCCAQAKAAgKzwo2SQCCAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECn8hAAILAAcKbRMQQwAcAQALAAcKbRMQQwAcAQAAAA==.',
Ba='Babycale:BAABNQAECn8fAAIMAAkKIh05DwAHAwAMAAkKIh05DwAHAwAAAA==.Badger:BAAANQAECgQIBgAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDgAAAA==.',
Be='Beardette:BAAANQADCgEIAQAAAA==.Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAABNQAECn8UAAMNAAcK6RARKgBHAQANAAYKShMRKgBHAQAOAAUKogumIgD7AAAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECgIIAgABNQAECgoKKgAPAD4YAA==.Bellsbane:BAAANQADCggICAAAAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECn8hAAICAAgK8ge+pwCEAQACAAgK8ge+pwCEAQAAAA==.',
Bf='Bfx:BAABNQAECn8eAAIQAAoKZQ5eVADAAQAQAAoKZQ5eVADAAQAAAA==.',
Bi='Biggiesize:BAAANQADCggIEAAAAA==.Bigred:BAAANQADCgUIAgAAAA==.Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECn8aAAINAAcK5BxyEwAsAgANAAcK5BxyEwAsAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgkJGwAJAGkXAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECn8uAAMRAAoKayEXCAB7AwARAAoKayEXCAB7AwAQAAMKeRHIsgCLAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQICAAGAAAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAABNQAECn8dAAIRAAgKKRPqGAAkAQARAAgKKRPqGAAkAQAAAA==.Burnin:BAAANQADCgEIAQAAAA==.Bushidoo:BAAANQADCgEIAQAAAA==.Bustie:BAAANQAECgEIAgAAAA==.',
['Bé']='Bétrayal:BAAANQAECgEIAQAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAQICgASAJ8WAA==.Calahunts:BAACNQAFFH8KAAISAAQKnxbZFgADAQASAAQKnxbZFgADAQA1AAQKfzMAAxIACgqFIDgJAJMDABIACgqFIDgJAJMDAAgAAQq8AiGdACIAAAAA.Cankklezz:BAAANQADCgMIBAAAAA==.Carloway:BAABNQAECn8VAAITAAcKLwrEnQA8AQATAAcKLwrEnQA8AQAAAA==.Catlinn:BAABNQAECn8cAAMUAAYKagNc9QCVAAAUAAYKagNc9QCVAAAJAAIKvwDE2AEXAAAAAA==.Catßenatar:BAAANQADCggIEQAAAA==.Cayldaria:BAAANQADCgEIAQAAAA==.',
Cd='Cdude:BAAANQADCgIIAwAAAA==.',
Ce='Ceph:BAACNQAFFH8IAAIHAAMKqx7VBgARAQAHAAMKqx7VBgARAQA1AAQKfyQAAgcACQp4ISoGADkDAAcACQp4ISoGADkDAAAA.',
Ch='Charinae:BAAANQADCgUICgAAAA==.Chillay:BAAANQADCgcIBwAAAA==.Chokeahoa:BAAANQADCggIEAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECn8nAAIJAAoKTRe2OABYAQAJAAoKTRe2OABYAQAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Clauyia:BAAANQADCgIIAgAAAA==.Cleaveauge:BAABNQAECn8kAAMDAAoKPhYfCAA0AQADAAYKHBkfCAA0AQALAAoK1BO0RwARAQAAAA==.Cloggy:BAACNQAFFH8NAAMCAAYKLxpIFwA7AQACAAUKLxpIFwA7AQAVAAEKAADQCgBTAAA1AAQKfzQAAwIACgpFJFgIAIoDAAIACgpFJFgIAIoDABYAAgqLIgwOAGIAAAAA.',
Cn='Cntrl:BAAANQADCgcIFAABNQAECgQICwAGAAAAAA==.',
Co='Cokolo:BAAANQADCggIGgAAAA==.Coldflame:BAABNQAECn8qAAIXAAoKNxwwBwBaAgAXAAoKNxwwBwBaAgAAAA==.Corpulent:BAAANQADCgQIBQAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.Corvinia:BAAANQADCgEIAQAAAA==.',
Cp='Cptboomerang:BAABNQAECn8mAAISAAoK9RMmEwDYAQASAAoK9RMmEwDYAQAAAA==.',
Cr='Crackasbank:BAAANQABCgIIAgAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgQICAABNQAECgkJHwAYAJoWAA==.Crownpal:BAAANQAECgYIDAABNQAECgoKLAAZAIgZAA==.Crownroyale:BAABNQAECn8sAAIZAAoKiBmLAQDlAQAZAAoKiBmLAQDlAQAAAA==.Crownwarrior:BAAANQAECgEIAgABNQAECgoKLAAZAIgZAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAUIDwATALQdAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAABNQAECn8zAAMYAAoKgBX4HABIAQAYAAoKgBX4HABIAQATAAEK6wGOJQEnAAAAAA==.Daityasfist:BAACNQAFFH8PAAIaAAYKWCT5AgBGAgAaAAYKWCT5AgBGAgA1AAQKfx4AAhoACgpkJjIEAJEDABoACgpkJjIEAJEDAAAA.Daler:BAAANQADCgYICgAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECn8WAAIbAAgKPxvVGwBYAgAbAAgKPxvVGwBYAgAAAA==.Danishhunter:BAAANQAECgYICAAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAABNQAECn8aAAIcAAcKkwedFgAxAQAcAAcKkwedFgAxAQAAAA==.Darkseksi:BAAANQAECgQICQAAAA==.Dashmodius:BAABNQAECn8oAAIdAAoKcx+ICgAzAwAdAAoKcx+ICgAzAwAAAA==.Datakutasa:BAABNQAECn8XAAIQAAcKpyAfBwC8AQAQAAcKpyAfBwC8AQAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQAECgcIBwAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgIIBQAAAA==.',
Dd='Ddggaaman:BAAANQAECgQIBAAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAABNQAECn8cAAQeAAkKrAZlEgAMAQAeAAgKkgVlEgAMAQAfAAYK7QXJJgD/AAAgAAcKPwIrNQDrAAAAAA==.Deathera:BAAANQAFFAQIBAABNQAFFAUIDwATALQdAA==.Deathpack:BAACNQAFFH8NAAIhAAQK+yEfCgBFAQAhAAQK+yEfCgBFAQA1AAQKfzYAAiEACgqrIx8EAJ8DACEACgqrIx8EAJ8DAAAA.Deathsmiley:BAABNQAECn8dAAMhAAgKRQ4iQgC8AQAhAAgKRQ4iQgC8AQARAAIKQQOFyQA2AAAAAA==.Delani:BAAANQAECgQIBwAAAA==.Delavi:BAAANQAECgEIAQABNQAECgQIBwAGAAAAAA==.Demonbob:BAABNQAECn8rAAIKAAgKfRixLQA3AgAKAAgKfRixLQA3AgAAAA==.Deohgee:BAABNQAECn8YAAISAAYKuBXKoQDCAQASAAYKuBXKoQDCAQAAAA==.Deranker:BAACNQAFFH8KAAIXAAMKGx20MQADAQAXAAMKGx20MQADAQA1AAQKfyoAAxcACgq2HcRmALACABcACgq2HcRmALACAAUAAQoAAJtJADIAAAAA.Derpintine:BAAANQAECgEJAQAAAA==.Desdela:BAAANQADCgYIBwABNQAECgEIAQAGAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBwAAAA==.Diablox:BAABNQAECn9AAAIYAAoKaxq6JQDtAgAYAAoKaxq6JQDtAgAAAA==.Dibuono:BAAANQADCgMJBQAAAA==.Dinpyro:BAABNQAECn8kAAITAAgK6BJyIwBYAQATAAgK6BJyIwBYAQAAAA==.Ditherio:BAAANQADCgEIAQAAAA==.Diyther:BAABNQAECn8aAAMTAAcKCx6hHQB1AQATAAcKCx6hHQB1AQAYAAQKqBP1rwAzAQAAAA==.',
Dk='Dkaara:BAAANQADCggIEgAAAA==.',
Do='Doofu:BAAANQADCgEIAgAAAA==.Doofysvacuum:BAABNQAECn8yAAIdAAgKPReQCwBdAQAdAAgKPReQCwBdAQAAAA==.',
Dr='Draganhammer:BAABNQAECn8oAAIJAAkKJxKRewA0AgAJAAkKJxKRewA0AgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Dreadvyr:BAAANQAECggIDgAAAA==.Droodar:BAAANQAECgEIAQABNQAECgcIHgAEAPgiAA==.Droopey:BAABNQAECn8jAAIXAAgKKQeHRgAvAQAXAAgKKQeHRgAvAQAAAA==.',
Du='Duckywg:BAABNQAECn8gAAIKAAgKTxJSNAAKAgAKAAgKTxJSNAAKAgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgYICgAAAA==.',
Ec='Eclipsea:BAAANQAECgUIEQAAAA==.',
Ed='Edith:BAAANQADCgUJBgAAAA==.',
Ei='Eilistraaee:BAABNQAECn8vAAIUAAkKTx2GKADGAgAUAAkKTx2GKADGAgAAAA==.Eiryn:BAAANQAECgEIAQAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECn8pAAIiAAgK5R7GAwDZAQAiAAgK5R7GAwDZAQAAAA==.Eluneatic:BAAANQAECgEIAQAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQAECgQIBAAAAA==.Envyy:BAAANQAECgQIBAAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Es='Essex:BAAANQADCgEIAQAAAA==.',
Et='Etchlock:BAAANQADCgYICAAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAABNQAECn8bAAICAAoKgwraKwBFAQACAAoKgwraKwBFAQAAAA==.',
Ew='Ewanae:BAABNQAECn8YAAMiAAkKrhL0EwAqAgAiAAkKrhL0EwAqAgAYAAIKUQIdHgFUAAABNQAFFAMIBQAOAPAHAA==.',
Ex='Exera:BAAANQAECgEIAQAAAA==.',
Fa='Falygarro:BAAANQAECgIIAgABNQAECgQIBAAGAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFgAAAA==.Feliodas:BAAANQADCgEIAQAAAA==.Feralmoan:BAAANQADCgEIAgAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgIIBgAAAA==.',
Fi='Fiolidris:BAAANQAECgQIBAAAAA==.Firetotes:BAABNQAECn80AAITAAoKaR55CQAqAgATAAoKaR55CQAqAgAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgABNQAECgIIAgAGAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQADCgEIAQAAAA==.',
Fo='Foidscarred:BAACNQAFFH8IAAIKAAcKVw56CACtAQAKAAcKVw56CACtAQA1AAQKfxkAAgoACQppIEwLAJoBAAoACQppIEwLAJoBAAE1AAUUAwoJABwAnBsA.Forfoxsakes:BAAANQAECgQIBwAAAA==.Forget:BAABNQAECn8nAAQRAAkKDRtXBwDCAQARAAkKDRtXBwDCAQAhAAQKfxbxbADrAAAQAAMKmwzGswCJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCggIHQABNQAECgoKJAADAD4WAA==.Frostfíre:BAAANQADCgMIBAAAAA==.Frosttdk:BAABNQAECn8ZAAMhAAgKHSOZEQABAwAhAAgKHSOZEQABAwAQAAQKpBuLdgA+AQABNQAFFAQICAASAIkgAA==.Fruitluupz:BAAANQAECgQICQAAAA==.',
['Fæ']='Færrow:BAAANQADCggIDgAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAABNQAECn8XAAISAAcKKhQohwD9AQASAAcKKhQohwD9AQAAAA==.Garomok:BAAANQADCgMIBQAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAABNQAECn8VAAIYAAgKYSRsGwAlAwAYAAgKYSRsGwAlAwABNQAFFAMIBQACALQiAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQADCgEIAQAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgUICgAAAA==.',
Gi='Gimick:BAAANQADCgQIBQABNQAECgIIAwAGAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgYIDQAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgUICgAAAA==.Greenmonk:BAAANQAECgYICQAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAABNQAECn8aAAITAAcKdQvLNwAGAQATAAcKdQvLNwAGAQAAAA==.Grippyfemboy:BAAANQAECgUIBwABNQAFFAcIGwAjADcmAA==.Grün:BAAANQAECgUIDAAAAA==.',
Gu='Gulugg:BAAANQADCgcIDQAAAA==.Gurfquake:BAABNQAECn8fAAMYAAkKmhbrQQBuAgAYAAkKmhbrQQBuAgATAAQKRxLS8QCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgQIBgABNQAECgoKKAAdAHMfAA==.Hanahanug:BAAANQADCgYIBwAAAA==.Hangwenaz:BAABNQAECn8yAAILAAkKCB4bIwAsAwALAAkKCB4bIwAsAwABNQAECgkJIAAHAAwZAA==.Harrell:BAAANQAECgMIAwAAAA==.',
He='Headsplitter:BAAANQAECgIIAgAAAA==.Hearah:BAABNQAECn8fAAMTAAcKDQ+LjQBnAQATAAcKDQ+LjQBnAQAYAAYKdQXJyAABAQAAAA==.Hehez:BAAANQAECgEIAgAAAA==.Helk:BAAANQADCggICQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQADCgEIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hexdabear:BAAANQAECgYICgABNQAECgcIDwAGAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgUIDAABNQAECgcIDwAGAAAAAA==.Hexvoker:BAAANQAECgQIBAABNQAECgcIDwAGAAAAAA==.Hexxer:BAAANQAECgQIBgABNQAECgcIDwAGAAAAAA==.Hexzel:BAAANQAECgcIDwAAAA==.',
Hi='Hightide:BAAANQAECggIAQAAAA==.Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECgoKKgAXAJYRAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFH8KAAIUAAMKTSQzEgA9AQAUAAMKTSQzEgA9AQA1AAQKfy8AAhQACQrBJOUDALUDABQACQrBJOUDALUDAAAA.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECn8nAAIXAAkKfhpedQCTAgAXAAkKfhpedQCTAgABNQAFFAcIEwAQAGMkAA==.Hondô:BAECNQAFFH8TAAQQAAcKYyQvAADeAgAQAAcKYyQvAADeAgAhAAIKZyBbEgC3AAARAAEKAABiLABDAAA1AAQKf1YAAxAACgrFJhEAAB0EABAACgrFJhEAAB0EABEAAQoAAIayAGUAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwABNQAFFAgIFAAaAOYWAA==.',
Hu='Huntermanjoe:BAABNQAECn8lAAISAAoKEQ2CLQBoAQASAAoKEQ2CLQBoAQAAAA==.Huntersdie:BAAANQADCgYICgAAAA==.Hunterzalt:BAABNQAECn8qAAIRAAgKFBZSQAD9AQARAAgKFBZSQAD9AQAAAA==.',
Hy='Hypatia:BAAANQADCgMIAwABNQAECgoKJwAiAHgMAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAcIEwAQAGMkAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAABNQAECn8dAAIJAAkKfRhSKQCDAQAJAAkKfRhSKQCDAQAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgQIBAAAAA==.',
Id='Idra:BAABNQAECn8wAAIIAAoKWyXUAAD4AgAIAAoKWyXUAAD4AgAAAA==.',
If='Iffa:BAAANQAECgEIBQABNQAECgMIBQAGAAAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgcIEAAAAA==.',
Im='Imakewhitez:BAAANQADCgYIBgAAAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgQICAAGAAAAAA==.Itsmyfault:BAAANQADCgYIDwAAAA==.',
Ja='Jackul:BAAANQAECggIEAAAAA==.Jakilk:BAABNQAECn8eAAMQAAcKRwfmdwA6AQAQAAcKRwfmdwA6AQARAAQK6AEIrgBxAAAAAA==.Jakilky:BAABNQAECn8bAAMRAAYKDwTIjgDIAAARAAYKgAPIjgDIAAAQAAUKzgKVrACbAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQAECgIIBAAAAA==.Jaycomo:BAAANQADCggIEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECn8gAAIJAAcKOQdm6wBFAQAJAAcKOQdm6wBFAQAAAA==.',
Je='Jebuss:BAAANQAECgEIAQAAAA==.Jeeplife:BAAANQADCgUIBgAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBgABNQAECggIIAAQAD4fAA==.Jellydead:BAABNQAECn8gAAIQAAgKPh9IMABuAgAQAAgKPh9IMABuAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQAECgUIBQAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwAGAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIDwABNQAECgoKJAADAD4WAA==.Juggernåut:BAAANQAECgQIBAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFH8PAAITAAUKtB02CADQAQATAAUKtB02CADQAQA1AAQKfywAAxMACgqNIaYVACIDABMACgqNIaYVACIDABgABwq5DkmOAIABAAAA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECn8tAAIPAAoKWBmaAgBxAgAPAAoKWBmaAgBxAgABNQABCgYIDAAGAAAAAA==.Kaelthuss:BAAANQAECgYIDwAAAA==.Kaimio:BAAANQADCgEIAQAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFwAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQJCAAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAABNQAECn8eAAMdAAoKBQYHMwCqAQAdAAoKBQYHMwCqAQAKAAEKAACangAhAAAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECn8gAAILAAoKIh78HACQAQALAAoKIh78HACQAQAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQABNQADCgEIAQAGAAAAAA==.',
Ki='Kikimay:BAAANQADCgYIDQAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAAGAAAAAA==.',
Ko='Kobii:BAAANQAECgIIAgAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAABNQAECn8eAAICAAoKThP4PQATAQACAAoKThP4PQATAQAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgEIAQABNQAECgIIBQAGAAAAAA==.',
Kr='Kreepingdeth:BAAANQADCgEIAgAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ku='Kurokitsune:BAAANQAECgQIBAAAAA==.',
Ky='Kylofinn:BAAANQAECgYIDgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAABNQAECn8lAAIjAAkKrRIPBgCeAQAjAAkKrRIPBgCeAQAAAA==.Laesandra:BAAANQAECgMIBwAAAA==.Lalatide:BAAANQAECgYIDgAAAA==.Languish:BAAANQAECggIAwAAAA==.Lastris:BAABNQAECn8VAAMJAAkK+wkLAwEaAQAJAAcKowULAwEaAQAUAAYKdwcd0ADbAAAAAA==.Lathvia:BAAANQADCgcICAABNQAECgoKFgAUANcNAA==.Lavénder:BAAANQADCgYICgAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAABNQAECn8gAAIJAAoKVRDHMABuAQAJAAoKVRDHMABuAQAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFH8bAAIjAAcKNyZIAAAGAwAjAAcKNyZIAAAGAwA1AAQKfzMAAiMACgrNJsEAAOYDACMACgrNJsEAAOYDAAAA.Lildwarf:BAEBNQAECn8XAAILAAgKkBaqiwD/AQALAAgKkBaqiwD/AQABNQAFFAEIAQAGAAAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgAGAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECn8iAAIQAAkKlg/QTgDZAQAQAAkKlg/QTgDZAQAAAA==.Livesoff:BAAANQAECgMIAwABNQAECgoKKAAQAE0NAA==.Lizerd:BAAANQADCgYIBgABNQAECgoKNQABANceAA==.',
Lo='Lochgimli:BAAANQABCgUIBwAAAA==.Louvetier:BAAANQAECgQIBQAAAA==.Loxleigh:BAAANQADCgYJDgAAAA==.',
Lu='Lucario:BAACNQAFFH8bAAQCAAgKshrpAQCDAgACAAcKoB3pAQCDAgAVAAIKCQzZAwBcAAAWAAEKkgurHwBJAAA1AAQKfygAAwIACgoaJRoGAJ4DAAIACgoaJRoGAJ4DABYABwrgG8YQAPUBAAAA.Luckyboi:BAABNQAECn8nAAMXAAkKMBkXcACdAgAXAAkK7RYXcACdAgAFAAMKyxakJADJAAAAAA==.Luckymeoww:BAABNQAECn8qAAMQAAgK4BMoTgDcAQAQAAgK4BMoTgDcAQAhAAQKbhHQdQDLAAAAAA==.Lunargrowth:BAAANQADCgQICAAAAA==.Luurain:BAAANQAECgQIBAAAAA==.',
['Lð']='Lðxic:BAAANQAECgUICgAAAA==.',
Ma='Machiki:BAAANQADCgEIAQABNQADCgEIAQAGAAAAAA==.Maeveran:BAABNQAECn8dAAMJAAgKQAxhuACtAQAJAAgKLwxhuACtAQAjAAIKFweyOQAuAAAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIAAHAAwZAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQADCgEIAQAAAA==.Mandanah:BAAANQADCgEIAQAAAA==.Mandrei:BAAANQAECgIIAgAAAA==.Mangonutt:BAAANQADCggIFAAAAA==.Maryjuana:BAABNQAECn8qAAIkAAkKPA5vJQADAgAkAAkKPA5vJQADAgAAAA==.Mastalys:BAEANQAECgUIBQAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEwAAAA==.Mavet:BAABNQAECn82AAMBAAoKihXqVAAkAgABAAkKcxXqVAAkAgAkAAgKRhR1EAANAQAAAA==.Mavina:BAABNQAECn9AAAMBAAoK5B7QEQA6AwABAAoK5B7QEQA6AwAEAAEKVgXyMAAiAAAAAA==.Mazez:BAAANQAECgcIDgAAAA==.',
Me='Meanmuggin:BAAANQAECgUIBwAAAA==.Meatshieldz:BAAANQADCgQIDAAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Megapally:BAAANQAECgIIAgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYIEQAQAJQaAA==.Meketek:BAABNQAECn8hAAIhAAgKVxMcFABmAQAhAAgKVxMcFABmAQAAAA==.Melodica:BAAANQAECgMIAgAAAA==.Melodie:BAAANQADCgUIBgAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAABNQAECn82AAIXAAoKaBgsYQC8AgAXAAoKaBgsYQC8AgAAAA==.Mercader:BAAANQAECgYICgAAAA==.Merrvoid:BAABNQAECn8tAAISAAoKcRRbUAB+AgASAAoKcRRbUAB+AgAAAA==.Messîah:BAAANQAECgYIBwAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAABNQAECn8dAAIfAAkK8AasGwCQAQAfAAkK8AasGwCQAQAAAA==.Mildo:BAABNQAECn8oAAIWAAgKyBuECQBhAgAWAAgKyBuECQBhAgAAAA==.Millerlight:BAAANQAECgUICwAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAAGAAAAAA==.Minervá:BAABNQAFFH8FAAMOAAMK8AdWAQCVAAAOAAIKqwpWAQCVAAAPAAEKeQIAEwA5AAAAAA==.Minotàurus:BAAANQAECgYIDwAAAA==.Mintonka:BAABNQAECn8aAAIYAAcK1gMSTwClAAAYAAcK1gMSTwClAAAAAA==.Miranaaster:BAABNQAECn8ZAAIXAAoKMxZhfwCAAgAXAAoKMxZhfwCAAgAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAABNQAECn8UAAMaAAkKZQMkGgDYAAAaAAkKSwMkGgDYAAAZAAEK/wP3MgAqAAABNQAECgoKJgAUAKUPAA==.Mixologist:BAAANQADCgEIAQAAAA==.Miyagimiah:BAAANQADCgUICQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBgAAAA==.Mokame:BAABNQAECn8qAAIPAAoKPhgjEABYAQAPAAoKPhgjEABYAQAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Moonshroom:BAAANQAECgIIAgABNQAECgIIAgAGAAAAAA==.Moovina:BAAANQADCgMIAwABNQAECgoKQAABAOQeAA==.Moraien:BAAANQAFFAQIBAAAAA==.Morchanna:BAABNQAECn8cAAISAAoKhAxcfQATAgASAAoKhAxcfQATAgAAAA==.Morf:BAAANQADCgMIBAAAAA==.Morgy:BAAANQADCggICQAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrae:BAAANQADCgEIAQAAAA==.Myrokorian:BAAANQADCgcIBwAAAA==.Mystichex:BAAANQAECgIIAgABNQAECgcIDwAGAAAAAA==.',
['Mä']='Mäzikeen:BAAANQAECgYIEwABNQAECgkJJwAhAMkcAA==.',
Na='Nalkoa:BAAANQADCgYIBgAAAA==.Natalietes:BAAANQAECgYICgAAAA==.Nattylight:BAABNQAECn8eAAMRAAcKnRF2VwCVAQARAAcKnRF2VwCVAQAQAAEKlQXw8QAlAAAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgkJHwAYAJoWAA==.',
Ne='Newhealer:BAAANQAECgUIBwAAAA==.',
Nh='Nhly:BAAANQADCgEIAQAAAA==.',
Ni='Nibletz:BAAANQAECgYIBgAAAA==.Nightshot:BAAANQADCgEIAQAAAA==.Ninelinez:BAABNQAECn8YAAIZAAgKHiOPBwDBAgAZAAgKHiOPBwDBAgAAAA==.',
No='Nool:BAAANQADCgMIAwAAAA==.Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAABNQAECn8WAAMkAAYKEgpkQgAfAQAkAAYKEgpkQgAfAQABAAEKvhCGAQErAAABNQAECgoKFgAUANcNAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIEAAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECggIGAAZAB4jAA==.',
['Nò']='Nòte:BAAANQADCgQIBQABNQAECgIJAgAGAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oa='Oatmealstout:BAAANQADCgEIAQAAAA==.',
Oc='Ochana:BAABNQAECn8WAAIUAAoK1w36CwAGAgAUAAoK1w36CwAGAgAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwAGAAAAAA==.',
Ol='Oldnote:BAAANQADCgIIAwAAAA==.Oleßigßahlz:BAAANQADCgEIAQAAAA==.Olgalina:BAAANQADCgQICQABNQAECgcIHgAEAPgiAA==.Olorinn:BAAANQABCgQIBAAAAA==.',
Op='Opirix:BAABNQAECn81AAMBAAoK1x5AIgDlAgABAAoK1x5AIgDlAgAkAAYKzBocKADoAQAAAA==.',
Os='Osenji:BAAANQADCgQIBQAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAwAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDQABNQAECgEIAQAGAAAAAA==.Painkillerx:BAAANQADCgIIAgAAAA==.Pallycakes:BAABNQAECn8ZAAIJAAgKiAXaBgETAQAJAAgKiAXaBgETAQAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Parkane:BAAANQAECgQIBAAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAABNQAECn8gAAIPAAkKkg2oFwAiAQAPAAkKkg2oFwAiAQAAAA==.Patreszas:BAABNQAECn8oAAIfAAoKEhNGEwAbAgAfAAoKEhNGEwAbAgAAAA==.Pawshocker:BAABNQAECn8hAAIiAAoKVyIfCAD4AgAiAAoKVyIfCAD4AgABNQAFFAcIGwAjADcmAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Pepperss:BAAANQAECgIIAwAAAA==.Peptobismo:BAAANQAECgIIAwAAAA==.Peàches:BAAANQAECgIIBQAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgIIAwAAAA==.Piécémákér:BAAANQAECgEIAQAAAA==.',
Po='Pohaberry:BAABNQAECn8qAAISAAkK7hL8WQBmAgASAAkK7hL8WQBmAgAAAA==.Pokemage:BAABNQAECn8mAAIXAAgK7Q+2IQCMAQAXAAgK7Q+2IQCMAQAAAA==.Popedk:BAABNQAECn8lAAMQAAoKlSGuEgAiAwAQAAoKlSGuEgAiAwAhAAEKPhl5pQBCAAABNQAFFAcIDgAYADYYAA==.Popesham:BAABNQAFFH8OAAIYAAcKNhg3BwAFAgAYAAcKNhg3BwAFAgAAAA==.Poppa:BAAANQADCgEIAQAAAA==.',
Pr='Prannanm:BAAANQADCgIIAgAAAA==.Priestduude:BAAANQAECgYJBgAAAA==.Product:BAAANQAECgIIAgAAAA==.',
Pu='Pullacrapton:BAAANQAECgUICgAAAA==.Putress:BAAANQAECgIIAgAAAA==.',
Qu='Quasi:BAABNQAECn8rAAIkAAoKKhcyAgAsAgAkAAoKKhcyAgAsAgAAAA==.Quiggins:BAABNQAECn8vAAIJAAgKDgdL5ABTAQAJAAgKDgdL5ABTAQAAAA==.Quikbrownfox:BAAANQADCgcICAABNQAECgkJIgAZAE8TAA==.Quirky:BAAANQADCgUIFwAAAA==.',
Ra='Raeziel:BAAANQAECgQIBwAAAA==.Raffunn:BAAANQADCgcICQABNQAECgMIAwAGAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgEIAQAAAA==.Razurel:BAAANQADCgEIAQAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgQIDQABNQAFFAQIDQAhAPshAA==.Reignz:BAAANQAECgQIEwAAAA==.Reinhardt:BAABNQAECn8tAAMjAAoKRh15CQAGAwAjAAoKRh15CQAGAwAJAAcKIhJSzgB/AQAAAA==.Repent:BAAANQAECggIAQAAAA==.Reticular:BAABNQAECn8XAAIjAAgKqQ9xDwAYAQAjAAgKqQ9xDwAYAQAAAA==.',
Rh='Rhaenne:BAAANQAECgQIBwAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcIDQAAAA==.',
Ru='Rubonyx:BAABNQAECn8eAAQEAAcK+CKFAAA8AgAEAAcK+CKFAAA8AgAkAAMKgB3sTADhAAABAAIKqwZP7wBWAAAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECn8WAAIMAAcKXwiHUwBuAQAMAAcKXwiHUwBuAQAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAABNQAECn8aAAIPAAgKMhBcRwDPAQAPAAgKMhBcRwDPAQAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAgABNQAECgIIAgAGAAAAAA==.',
Sa='Sagbag:BAAANQADCgEIAQAAAA==.Sagerin:BAABNQAECn8XAAIQAAgKhhFhHQD/AAAQAAgKhhFhHQD/AAAAAA==.Sageslife:BAAANQAECgUIEQAAAA==.Saintofthetp:BAAANQAECgYIBgAAAA==.Saison:BAAANQADCgEIAgAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQADCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Screamodevo:BAAANQAECgEIAQAAAA==.Scronk:BAAANQADCgcIBwABNQAECgMIBwAGAAAAAA==.Scruffmcgruf:BAABNQAECn8aAAIBAAgKzA42bwDQAQABAAgKzA42bwDQAQAAAA==.Scubany:BAAANQADCgIJAwAAAA==.Scyl:BAAANQADCgIIAgABNQAECgIIBQAGAAAAAA==.',
Se='Senadora:BAABNQAECn8VAAIaAAcKoR1EIQAiAgAaAAcKoR1EIQAiAgAAAA==.Sergrahm:BAAANQADCgYIDwAAAA==.Sezeth:BAABNQAECn8UAAMhAAkK2Bh1MAAiAgAhAAkKKRh1MAAiAgAQAAYKJA/CewAtAQAAAA==.',
Sh='Shaboomboom:BAACNQAFFH8FAAIYAAIKHRRxIgCjAAAYAAIKHRRxIgCjAAA1AAQKfyoAAhgACgonG+ktAMUCABgACgonG+ktAMUCAAAA.Shadowglaive:BAABNQAECn8qAAIdAAkKLx/kCQA6AwAdAAkKLx/kCQA6AwAAAA==.Shadownight:BAABNQAECn8iAAIQAAgKTyOJFgAHAwAQAAgKTyOJFgAHAwAAAA==.Shalbust:BAAANQADCgEIAQAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Shanice:BAAANQADCgMIBAAAAA==.Sharburst:BAAANQAECggIDwAAAA==.Sharleet:BAAANQAECggIBwAAAA==.Sharlocke:BAAANQAECgYIBgAAAA==.Shaval:BAABNQAECn+lAQIJAAkK/SZdAAAPBAAJAAkK/SZdAAAPBAAAAA==.Shawman:BAAANQAECgQIBQAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFH8KAAMLAAQK/hCuHQAjAQALAAQKUg6uHQAjAQAcAAIK8g2KAwCPAAA1AAQKfycAAwsACgpZG6hjAGMCAAsACgoMG6hjAGMCABwAAwqtG6UaAPsAAAAA.Shewadin:BAAANQADCgQICQAAAA==.Shewnasty:BAAANQAECgYIEAAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQADCgEIAQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECn8iAAIZAAkKTxMWDgAVAgAZAAkKTxMWDgAVAgAAAA==.Shøøtingstar:BAAANQAECgUICQABNQAECgkJJwAhAMkcAA==.',
Si='Signet:BAABNQAECn8dAAITAAcKBx3LGgCGAQATAAcKBx3LGgCGAQAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skerrit:BAAANQADCgIIAQAAAA==.Skoss:BAABNQAECn8jAAMCAAkKFxMyZAAtAgACAAkKFxMyZAAtAgAWAAIKxw6MWgBxAAAAAA==.Skullshine:BAACNQAFFH8eAAQQAAYKZyEmBQDUAQAQAAUKZyEmBQDUAQAhAAIKmwusDQBOAAARAAEKAACyNgAlAAA1AAQKfygAAxAACgpLI30OAEQDABAACQoIJX0OAEQDACEAAgqfGtg+AKkAAAAA.Skunkie:BAABNQAECn8dAAMTAAoKPBHQZwDVAQATAAoKPBHQZwDVAQAYAAEK1hjxJQFGAAAAAA==.Skybreaker:BAAANQADCgEIAQAAAA==.Skynyrd:BAAANQADCggICwAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDQAAAA==.Slickfifty:BAAANQAECgQIBwAAAA==.Slippewy:BAAANQAECgIIAgAAAA==.Sluewt:BAAANQAECggIEgABNQAECgoKLwABAP8gAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smolderr:BAABNQAECn8dAAISAAkKkAXBtwCUAQASAAkKkAXBtwCUAQAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.Soulbleach:BAAANQADCgEIAQAAAA==.',
Sp='Spacecadet:BAAANQAECgMIAwAAAA==.Spaciousyeti:BAABNQAECn8ZAAIhAAgKGRm+NgD9AQAhAAgKGRm+NgD9AQAAAA==.Spearowhunt:BAAANQAECgYIBgAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcICAAAAA==.Splits:BAAANQAECgIIAgAAAA==.Spook:BAAANQADCgEIAQAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stawnk:BAAANQADCgEIAQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBgAAAA==.Stoickdvast:BAABNQAECn8nAAQhAAkKyRwhCADVAQAhAAkKFxshCADVAQARAAYKcxC8eQARAQAQAAMKOBT6nADEAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECggIDgAAAA==.Strànge:BAAANQADCgYIBwAAAA==.Stun:BAAANQAECgIIAgAAAA==.Stunllub:BAAANQAECggIDgAAAA==.',
Su='Suggs:BAACNQAFFH8OAAQCAAYKfhiABwD0AAACAAQKlRyABwD0AAAWAAEKOAxtCQBSAAAVAAEKAADZDgBHAAA1AAQKfyUABAIACgptIWY2ALECAAIACQoxIWY2ALECABUAAwpcHtAXAM4AABYAAgqrGzNTAIUAAAAA.Supergoten:BAAANQAECgEIAQAAAA==.Surnaturelle:BAAANQADCggICQABNQAECgoKJwAiAHgMAA==.',
Sw='Swiiani:BAABNQAECn8YAAIYAAYKvgexRAC+AAAYAAYKvgexRAC+AAAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECgcIDAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQADCgEIAQABNQAECgEIAQAGAAAAAA==.',
Ta='Taelinn:BAAANQADCggIDAABNQAECgoKKAAfABITAA==.Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQADCgEIAQAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECgUICgAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAZAE8TAA==.Taurelai:BAAANQADCgEIAQAAAA==.Tauriko:BAACNQAFFH8GAAIJAAMK0gqwGwDKAAAJAAMK0gqwGwDKAAA1AAQKfywAAgkACgoOHJRLALICAAkACgoOHJRLALICAAAA.Tayvos:BAAANQAECggICQAAAA==.Tazurel:BAAANQADCgQIBQAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAABNQAECn8hAAQQAAkK2hUgPgAmAgAQAAkK2hUgPgAmAgAhAAIKPARxnQBXAAARAAEKoBX5wgBCAAAAAA==.',
Th='Thebestlorax:BAAANQAECgYICwABNQAECgkJIgAZAE8TAA==.Thejonesyy:BAAANQADCgcIBwAAAA==.Theler:BAAANQAECgMIAwABNQAFFAYIDQACAC8aAA==.Theradestria:BAAANQAECgYIDAAAAA==.Thestigg:BAABNQAECn8cAAIJAAkKYgnnwgCWAQAJAAkKYgnnwgCWAQAAAA==.Thighighs:BAAANQAECgIIAgABNQAFFAYIEAAJAFEaAA==.Thundersloot:BAAANQAECgEIAQABNQAECgoKFwAUAH8SAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAABNQAECn8fAAMWAAgKLAhaLgARAQACAAYKOgg6zgAtAQAWAAYKvQVaLgARAQAAAA==.',
To='Toedumbz:BAAANQAECgYIDwAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQAECgQIBAAAAA==.Troflgar:BAAANQAECgcICwAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgcIBgABNQAECgoKJAADAD4WAA==.',
Ts='Tsuky:BAAANQAECgYIBwAAAA==.Tsukytank:BAAANQAECgEIAgAAAA==.Tsumikui:BAABNQAECn80AAQWAAoKSBJcDAAxAgAWAAgKkA9cDAAxAgAVAAgKNw3BCQDjAQACAAoKPg9vQAANAQAAAA==.',
Ty='Tyinastor:BAAANQAECgQIBwAAAA==.',
Ub='Ubarzwaz:BAAANQADCgEIAQAAAA==.',
Ud='Udderless:BAAANQAECggIEQAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Um='Umila:BAAANQAECgEIAQAAAA==.',
Un='Unalived:BAABNQAECn8qAAIXAAoKlhFwOwBGAQAXAAoKlhFwOwBGAQAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCggIHQAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Vanillia:BAAANQAECgcICAAAAA==.Varauge:BAAANQADCggICQAAAA==.Varnir:BAABNQAECn8VAAIcAAkKrwWAFgA0AQAcAAkKrwWAFgA0AQAAAA==.Varíann:BAAANQADCgcIDAAAAA==.',
Ve='Velro:BAAANQAECggIDwAAAA==.Vemmox:BAABNQAECn8ZAAIXAAoK5hDYTwAcAQAXAAoK5hDYTwAcAQAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venefica:BAAANQAECgQIBQAAAA==.Venôm:BAAANQAECggICAAAAA==.Veroks:BAAANQADCgUIDQABNQAECggIDwAGAAAAAA==.Vesemir:BAABNQAECn8nAAIdAAcKBBEnEgAgAQAdAAcKBBEnEgAgAQAAAA==.',
Vh='Vhpsv:BAAANQAECggICgAAAA==.',
Vi='Vianir:BAABNQAECn8dAAIJAAkKLg+AqADPAQAJAAkKLg+AqADPAQAAAA==.Vindictive:BAAANQAECggICQAAAA==.Vitals:BAABNQAECn8zAAMlAAoKjgeuGQASAQAlAAoKjgeuGQASAQAMAAIKjARIOwBlAAAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgUIBwAAAA==.',
Wa='Warscared:BAABNQAECn8UAAILAAgKJQTA2wA1AQALAAgKJQTA2wA1AQAAAA==.Wasabis:BAABNQAECn8sAAIYAAgKfgmYfwCmAQAYAAgKfgmYfwCmAQAAAA==.',
We='Wels:BAABNQAECn8vAAIBAAoK/yA2EgA4AwABAAoK/yA2EgA4AwAAAA==.',
Wh='Whichwitch:BAAANQADCgcIEgAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAABNQAECn8VAAIYAAcKbBW2egCzAQAYAAcKbBW2egCzAQAAAA==.',
Wi='Wigglypuffsr:BAABNQAECn8bAAIJAAkKaRdrdQBDAgAJAAkKaRdrdQBDAgAAAA==.Wiikkid:BAAANQADCgQIBQAAAA==.Wilkosmom:BAABNQAECn8pAAIXAAoKWh7aOgARAwAXAAoKWh7aOgARAwAAAA==.Winddrake:BAAANQAECgYIDAAAAA==.Wixania:BAAANQAECgQIBAAAAA==.',
Xa='Xaanu:BAAANQADCgIIAwAAAA==.Xanelivan:BAAANQAECgUIDAAAAA==.Xanneste:BAABNQAECn8lAAIKAAkKewodHwACAQAKAAkKewodHwACAQAAAA==.Xaru:BAAANQADCgEIAQAAAA==.',
Xe='Xecutioner:BAAANQAECgIIAgAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQADCgEIAQAAAA==.',
Xk='Xkatarina:BAAANQAECgIIAQAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQADCggIDgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yo='Yoshiyokai:BAAANQAECggIBwAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAcAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAAANQAECggIEAABNQAFFAQIDQAhAPshAA==.',
['Yâ']='Yâtiri:BAAANQADCggIGQAAAA==.',
Za='Zaebos:BAAANQADCgcICAAAAA==.Zakwa:BAAANQAECggICwAAAA==.Zalfanso:BAEANQADCgEIAgAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQADCgEIAQAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggIDAAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAABNQAECn8YAAIIAAoKpgy+DAApAQAIAAoKpgy+DAApAQAAAA==.',
Zi='Ziralila:BAABNQAECn8iAAISAAgKYwhvVwAAAQASAAgKYwhvVwAAAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAABNQAECn8VAAILAAcKwhExqAC4AQALAAcKwhExqAC4AQAAAA==.',
Zu='Zuglybob:BAAANQADCgUICQAAAA==.Zuulax:BAAANQADCgEIAQAAAA==.Zuulis:BAAANQADCgEIAQAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Óm']='Ómèn:BAAANQAECgMIBQAAAA==.',
['Ör']='Örin:BAABNQAECn81AAMMAAoK3SOEBACOAwAMAAoKACOEBACOAwAmAAgKTR9yBADIAgAAAA==.',
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
