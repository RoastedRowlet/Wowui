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

local lookup = {'Priest-Holy','Warlock-Demonology','Warrior-Protection','Priest-Discipline','Mage-Frost','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Warrior-Fury','Priest-Shadow','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECggIDQAAAA==.Adolin:BAAANQAECgUIBQABNQAECgoKSQABAPseAA==.',
Ae='Aegeax:BAAANQAECgcIBwAAAA==.',
Af='After:BAAANQAECgQIBAABNQAECgoKIAACAPcTAA==.Afterall:BAAANQAECgMIAwABNQAECgoKIAACAPcTAA==.',
Ag='Aggropull:BAABNQAECn8zAAIDAAkKFwmuHABzAQADAAkKFwmuHABzAQAAAA==.',
Ai='Ainzoolbone:BAAANQADCgIIAgAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgcIJAAEAPgiAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Alroy:BAAANQADCgIIAgAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIBAAAAA==.Anthonyisme:BAABNQAECn8gAAIFAAkKfBC1CQA1AgAFAAkKfBC1CQA1AgAAAA==.Anthonysbear:BAAANQABCgIIBAABNQAECgkJIAAFAHwQAA==.',
Ap='Apoptosis:BAAANQADCgcIDwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcamania:BAAANQAFFAEIAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Aryndinnin:BAABNQAECn8hAAIGAAkKThuPEAB2AgAGAAkKThuPEAB2AgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Ashmay:BAAANQABCgcIBgAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQAECgQIBAAAAA==.',
At='Athrunn:BAAANQAECggIDgABNQAECgoKMAAHAFslAA==.Attincy:BAAANQADCggILAAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECn80AAIIAAkKpA95agCBAQAIAAkKpA95agCBAQAAAA==.',
Ay='Ayah:BAABNQAECn8oAAIBAAkKHRWMPgC7AQABAAkKHRWMPgC7AQAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECn8lAAIJAAkKMgo2SQCCAQAJAAkKMgo2SQCCAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECn8oAAIKAAgKzhEYWwBxAQAKAAgKzhEYWwBxAQAAAA==.',
Ba='Babycale:BAABNQAECn8fAAILAAkKIh05DwAHAwALAAkKIh05DwAHAwAAAA==.Badger:BAAANQAECgQIBgAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQAECgMIAwAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Beardette:BAAANQABCgIIAgAAAA==.Bearenstein:BAAANQAECgEIAQAAAA==.Beartrixa:BAAANQAECgEIAQAAAA==.Beastlight:BAABNQAECn8VAAMMAAcK6RARKgBHAQAMAAYKShMRKgBHAQANAAUKogumIgD7AAAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECgIIAgABNQAECgoKLgAOADoaAA==.Bellsbane:BAAANQADCggICAAAAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECn8hAAICAAgK8ge+pwCEAQACAAgK8ge+pwCEAQAAAA==.',
Bf='Bfx:BAABNQAECn8mAAIPAAoKJRCtFQDWAQAPAAoKJRCtFQDWAQAAAA==.',
Bi='Biggiesize:BAAANQADCggIEAAAAA==.Bigred:BAAANQADCgUIAgAAAA==.Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECn8aAAIMAAcK5BxyEwAsAgAMAAcK5BxyEwAsAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgkJJAAIAJgcAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECn8xAAMQAAoKayEXCAB7AwAQAAoKayEXCAB7AwAPAAMKeRHIsgCLAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQICAARAAAAAA==.Budgi:BAAANQADCgIIAgAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAABNQAECn8lAAIQAAgKOxP1PgAEAgAQAAgKOxP1PgAEAgAAAA==.Bustie:BAAANQAECgEIAgAAAA==.',
['Bé']='Bétrayal:BAAANQABCgMIAwAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAUICwASAEIUAA==.Calahunts:BAACNQAFFH8LAAISAAUKQhTZFgADAQASAAUKQhTZFgADAQA1AAQKfz0AAxIACgq8JZ8CAGQDABIACgq8JZ8CAGQDAAcAAQq8AiGdACIAAAAA.Calatath:BAAANQAECgQIBAABNQAFFAUICwASAEIUAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAABNQAECn8VAAITAAcKLwrEnQA8AQATAAcKLwrEnQA8AQAAAA==.Catlinn:BAABNQAECn8cAAMUAAYKagNc9QCVAAAUAAYKagNc9QCVAAAIAAIKvwDE2AEXAAAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAACNQAFFH8JAAIGAAMKqx7VBgARAQAGAAMKqx7VBgARAQA1AAQKfyUAAgYACgqWISoGADkDAAYACgqWISoGADkDAAAA.',
Ch='Charinae:BAAANQADCgUICgAAAA==.Chiggin:BAAANQAECgIIAwAAAA==.Chillay:BAAANQAECgQIBAAAAA==.Chokeahoa:BAAANQADCggIEAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECn8yAAIIAAoKTRe3QQD1AQAIAAoKTRe3QQD1AQAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Clauyia:BAAANQAECgQIBAAAAA==.Cleaveauge:BAABNQAECn8pAAMDAAoKkheJEgAUAQAKAAoKKBUuXgBoAQADAAYKHBmJEgAUAQAAAA==.Cloggy:BAACNQAFFH8NAAMCAAYKLxpIFwA7AQACAAUKLxpIFwA7AQAVAAEKAADQCgBTAAA1AAQKfz0AAwIACgpOJFgIAIoDAAIACgpOJFgIAIoDABYAAgqLIlcfAFAAAAAA.Clovver:BAAANQADCgEIAQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgQIDwARAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAABNQAECn82AAIXAAoKhBx9JwBXAgAXAAoKhBx9JwBXAgAAAA==.Corpulent:BAAANQADCgQIBAAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAABNQAECn8nAAISAAoKDBaaOgD2AQASAAoKDBaaOgD2AQAAAA==.',
Cr='Crackasbank:BAAANQAECgIIAgAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgUICwABNQAECgoKIQAYAAUVAA==.Crownpal:BAAANQAECgYIDAABNQAECgoKNQAZAOUZAA==.Crownroyale:BAABNQAECn81AAMZAAoK5RkhBQDWAQAZAAoK5RkhBQDWAQAaAAEKugLrTwAYAAAAAA==.Crownwarrior:BAAANQAECgYIBwABNQAECgoKNQAZAOUZAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAYIBgABAFkXAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAACNQAFFH8GAAIYAAIKVxFMEwCOAAAYAAIKVxFMEwCOAAA1AAQKfzoAAxgACgr0F28hAPIBABgACgr0F28hAPIBABMAAQrrAY4lAScAAAAA.Daityasfist:BAACNQAFFH8QAAIaAAcKliT5AgBGAgAaAAcKliT5AgBGAgA1AAQKfycAAhoACgpoJp8AAHkDABoACgpoJp8AAHkDAAAA.Daler:BAAANQADCgYICQAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECn8WAAIbAAgKPxvVGwBYAgAbAAgKPxvVGwBYAgAAAA==.Danishhunter:BAAANQAECgcICwAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAABNQAECn8aAAIcAAcKkwedFgAxAQAcAAcKkwedFgAxAQAAAA==.Darkseksi:BAABNQAECn8VAAIdAAgKcgd7IwDrAAAdAAgKcgd7IwDrAAAAAA==.Dashmodius:BAABNQAECn8tAAIeAAoKmCCICgAzAwAeAAoKmCCICgAzAwAAAA==.Datakutasa:BAABNQAECn8fAAIPAAkKvx3yDwAgAgAPAAkKvx3yDwAgAgAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQAECgcIDgAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQAECgYIBgAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAABNQAECn8cAAQfAAkKrAZlEgAMAQAfAAgKkgVlEgAMAQAgAAYK7QXJJgD/AAAhAAcKPwIrNQDrAAAAAA==.Deathera:BAABNQAFFH8GAAIBAAYKWRc9BQD3AQABAAYKWRc9BQD3AQAAAA==.Deathpack:BAACNQAFFH8NAAIiAAQK+yEfCgBFAQAiAAQK+yEfCgBFAQA1AAQKfzkAAiIACgqrIx8EAJ8DACIACgqrIx8EAJ8DAAAA.Deathsmiley:BAABNQAECn8gAAMiAAkK6gwiQgC8AQAiAAkK6gwiQgC8AQAQAAIKQQOFyQA2AAAAAA==.Delani:BAAANQAECgUICwAAAA==.Delavi:BAAANQADCggIAwABNQAECgUICwARAAAAAA==.Demonbob:BAABNQAECn8rAAIJAAgKfRixLQA3AgAJAAgKfRixLQA3AgAAAA==.Deohgee:BAABNQAECn8dAAISAAcKzBPKoQDCAQASAAcKzBPKoQDCAQAAAA==.Deranker:BAACNQAFFH8LAAIXAAMKGx20MQADAQAXAAMKGx20MQADAQA1AAQKfysAAxcACgrQHsRmALACABcACgrQHsRmALACAAUAAQoAAJtJADIAAAAA.Derpintine:BAAANQAECgEIAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQARAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAACNQAFFH8FAAIYAAMKsgwDFQCDAAAYAAMKsgwDFQCDAAA1AAQKf0oAAhgACgqKHSoTAHQCABgACgqKHSoTAHQCAAAA.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAABNQAECn8qAAITAAkK/hNNMQDcAQATAAkK/hNNMQDcAQAAAA==.Diyther:BAABNQAECn8eAAMTAAcKDyDpPwCYAQATAAcKDyDpPwCYAQAYAAQKqBP1rwAzAQAAAA==.',
Dk='Dkaara:BAAANQADCggIEgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECn8yAAIeAAgKPRenIABIAgAeAAgKPRenIABIAgAAAA==.',
Dr='Draganhammer:BAABNQAECn8oAAIIAAkKJxKRewA0AgAIAAkKJxKRewA0AgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Dreadvyr:BAABNQAECn8YAAMQAAkKRQgJPQDuAAAiAAcKkgf5ZAAPAQAQAAcKAQgJPQDuAAAAAA==.Droodar:BAAANQAECgEIAQABNQAECgcIJAAEAPgiAA==.Droopey:BAABNQAECn8kAAMXAAgK1gdZlwAVAQAXAAgKKQdZlwAVAQAFAAEKFAepLgArAAAAAA==.',
Du='Duckywg:BAABNQAECn8gAAIJAAgKTxJSNAAKAgAJAAgKTxJSNAAKAgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgYICgAAAA==.',
Ea='Easykill:BAAANQAECgQIBwABNQAECggIMgATAPcjAA==.',
Ec='Eclipsea:BAAANQAECgUIEQAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECn8zAAIUAAoKBB2GKADGAgAUAAoKBB2GKADGAgAAAA==.Eiryn:BAAANQADCgcICwAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECn8xAAIjAAgK6x52DwByAgAjAAgK6x52DwByAgAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQAECgQIBAAAAA==.Envyy:BAAANQAECgQIBAAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAABNQAECn8kAAICAAoKaAyrSQCIAQACAAoKaAyrSQCIAQAAAA==.',
Ew='Ewanae:BAABNQAECn8YAAMjAAkKrhL0EwAqAgAjAAkKrhL0EwAqAgAYAAIKUQIdHgFUAAABNQAFFAQIBgANAPAHAA==.',
Fa='Falygarro:BAAANQAECgIIAgABNQAECgQIBAARAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgQIBgAAAA==.',
Fi='Fiolidris:BAAANQAECgQIBAAAAA==.Firetotes:BAABNQAECn8+AAMTAAoKaR4VFQCgAgATAAoKaR4VFQCgAgAYAAEKAAD74QAAAAAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgABNQADCggIFgARAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.Fluidruid:BAAANQABCgYIBgAAAA==.',
Fo='Foidscarred:BAACNQAFFH8IAAIJAAcKVw56CACtAQAJAAcKVw56CACtAQA1AAQKfxoAAgkACQoUITAZANECAAkACQoUITAZANECAAE1AAUUAwoJABwAnBsA.Forfoxsakes:BAAANQAECgQICwAAAA==.Forget:BAABNQAECn81AAQQAAoK3xxhEgAhAgAQAAoK3xxhEgAhAgAiAAQKfxbxbADrAAAPAAMKmwzGswCJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQAECgUIBgABNQAECgoKKQADAJIXAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAABNQAECn8cAAMiAAkKXCOZEQABAwAiAAkKXCOZEQABAwAPAAQKpBuLdgA+AQABNQAFFAQICAASAIkgAA==.Fruitluupz:BAAANQAECgQICQAAAA==.',
['Fæ']='Færrow:BAAANQADCggICwAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAABNQAECn8YAAISAAgKSBQohwD9AQASAAgKSBQohwD9AQAAAA==.Garomok:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAABNQAECn8VAAIYAAgKYSRsGwAlAwAYAAgKYSRsGwAlAwABNQAFFAMIBQACALQiAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgUIBwAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgYIDgAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwARAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgYIDQAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgUICgAAAA==.Greenmonk:BAAANQAECgcIDwAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAABNQAECn8fAAITAAcKow2MXQAmAQATAAcKow2MXQAmAQAAAA==.Grippyfemboy:BAAANQAFFAEIAQABNQAFFAgIHQAkAOUlAA==.Grün:BAAANQAECgUIDAAAAA==.',
Gu='Gulugg:BAAANQADCgcIEAAAAA==.Gurfquake:BAABNQAECn8hAAMYAAoKBRXrQQBuAgAYAAoKBRXrQQBuAgATAAQKSxLS8QCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgMIBQABNQAECgoKLQAeAJggAA==.Hanahanug:BAAANQADCgYIBwAAAA==.Hangwenaz:BAABNQAECn84AAIKAAkKLR8bIwAsAwAKAAkKLR8bIwAsAwABNQAECgkJIQAGAE4bAA==.Harrell:BAAANQAECgMIAwAAAA==.',
He='Headsplitter:BAAANQAECgIIAgAAAA==.Hearah:BAABNQAECn8fAAMTAAcKDQ+LjQBnAQATAAcKDQ+LjQBnAQAYAAYKdQXJyAABAQAAAA==.Hehez:BAAANQAECgUIBQAAAA==.Helk:BAAANQADCggICQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hex:BAAANQAECgIIAgAAAA==.Hexdabear:BAAANQAECgYICgABNQAECggIDgARAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hexfliction:BAAANQAECgIIAgABNQAECggIDgARAAAAAA==.Hextater:BAAANQAECgUICwABNQAECggIDgARAAAAAA==.Hexvoker:BAAANQAECgQIBAABNQAECggIDgARAAAAAA==.Hexxer:BAAANQAECgQICgABNQAECggIDgARAAAAAA==.Hexzel:BAAANQAECggIDgAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECgoKNAAXADITAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFH8LAAIUAAMKTSQzEgA9AQAUAAMKTSQzEgA9AQA1AAQKfzQAAhQACQrBJOUDALUDABQACQrBJOUDALUDAAAA.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECn8sAAIXAAkKfhpedQCTAgAXAAkKfhpedQCTAgABNQAFFAcIEwAPAGMkAA==.Hondô:BAECNQAFFH8TAAQPAAcKYyQvAADeAgAPAAcKYyQvAADeAgAiAAIKZyBbEgC3AAAQAAEKAABiLABDAAA1AAQKf2AAAw8ACgrIJhEAAB0EAA8ACgrIJhEAAB0EABAAAQoAAIayAGUAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwABNQAFFAgIFAAaAOYWAA==.',
Hu='Huntermanjoe:BAABNQAECn8sAAISAAoK2Q03eAAfAgASAAoK2Q03eAAfAgAAAA==.Huntersdie:BAAANQADCgYICQAAAA==.Hunterzalt:BAABNQAECn8tAAIQAAkKaxRSQAD9AQAQAAkKaxRSQAD9AQAAAA==.',
Hy='Hypatia:BAAANQADCgMIAwABNQAECgoKJwAjAHgMAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAcIEwAPAGMkAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAABNQAECn8mAAIIAAkK4RiNSQDbAQAIAAkK4RiNSQDbAQAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgQIBAAAAA==.',
Id='Idra:BAABNQAECn8wAAIHAAoKWyXfAgCwAwAHAAoKWyXfAgCwAwAAAA==.',
If='Iffa:BAAANQAECgEIBQABNQAECgcICQARAAAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgcIEAAAAA==.',
Il='Illidaria:BAAANQABCgEIAQAAAA==.',
Im='Imakewhitez:BAAANQADCgcIDQAAAA==.',
Ip='Ipomoea:BAAANQAECgYIBgABNQAECgoKGgAUAP4NAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgQIBAARAAAAAA==.Itsmyfault:BAAANQADCgYIDwAAAA==.',
Ja='Jackul:BAABNQAECn8ZAAICAAkK0Q6CRACZAQACAAkK0Q6CRACZAQAAAA==.Jakilk:BAABNQAECn8eAAMPAAcKRwfmdwA6AQAPAAcKRwfmdwA6AQAQAAQK6AEIrgBxAAAAAA==.Jakilky:BAABNQAECn8bAAMQAAYKDwTIjgDIAAAQAAYKgAPIjgDIAAAPAAUKzgKVrACbAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQAECgIIAgAAAA==.Jaycomo:BAAANQADCggIEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECn8gAAIIAAcKOQdm6wBFAQAIAAcKOQdm6wBFAQAAAA==.',
Je='Jebuss:BAAANQAECgQIBAAAAA==.Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBgABNQAECgkJIQAPANgdAA==.Jellydead:BAABNQAECn8hAAIPAAkK2B1IMABuAgAPAAkK2B1IMABuAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQAECgUIBwAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwARAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIDgABNQAECgoKKQADAJIXAA==.Juggernåut:BAAANQAECgQIBAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFH8PAAITAAUKtB02CADQAQATAAUKtB02CADQAQA1AAQKfy0AAxMACgpYIqYVACIDABMACgpYIqYVACIDABgABwq5DkmOAIABAAE1AAUUBggGAAEAWRcA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECn82AAIOAAoKIhr0DgBZAgAOAAoKIhr0DgBZAgABNQABCgYIDAARAAAAAA==.Kaelthuss:BAAANQAECgUIDgAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgUICQAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAABNQAECn8iAAMeAAoKBgYHMwCqAQAeAAoKBgYHMwCqAQAJAAEKAACangAhAAAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECn8nAAIKAAoKqx7zJABVAgAKAAoKqx7zJABVAgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAARAAAAAA==.',
Ko='Kobii:BAAANQAECgIIAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAABNQAECn8gAAICAAoK9xOBegD0AQACAAoK9xOBegD0AQAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgMIAgABNQAECgcIBwARAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ku='Kurokitsune:BAAANQAECgQIBAAAAA==.',
Ky='Kylofinn:BAABNQAECn8ZAAMKAAgKYhAhXwBlAQAKAAgKYhAhXwBlAQAcAAEKAAAjMQA8AAAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAABNQAECn8sAAIkAAkK/RJREgCAAQAkAAkK/RJREgCAAQAAAA==.Laesandra:BAAANQAECgMIBQAAAA==.Lalatide:BAAANQAECgYIEQAAAA==.Languish:BAAANQAECggIAgAAAA==.Lastris:BAABNQAECn8VAAMIAAkK+wkLAwEaAQAIAAcKowULAwEaAQAUAAYKdwcd0ADbAAAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgoKGgAUAP4NAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAABNQAECn8nAAIIAAoKbxOZYACZAQAIAAoKbxOZYACZAQAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFH8dAAIkAAgK5SVIAAAGAwAkAAgK5SVIAAAGAwA1AAQKfzkAAiQACgrtJsEAAOYDACQACgrtJsEAAOYDAAAA.Lildwarf:BAEBNQAECn8XAAIKAAgKkBaqiwD/AQAKAAgKkBaqiwD/AQABNQAFFAEIAgARAAAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgARAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECn8lAAIPAAkKvg/QTgDZAQAPAAkKvg/QTgDZAQAAAA==.Liusanjie:BAAANQADCgEIAQAAAA==.Livesoff:BAAANQAECgMIAgABNQAECgoKLAAPABQOAA==.Lizerd:BAAANQADCgYIBgABNQAFFAIIBQABAIwYAA==.',
Lo='Lochgimli:BAAANQAECgEIAQAAAA==.Louvetier:BAAANQAECgQIBgAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFH8bAAQCAAgKshrpAQCDAgACAAcKoB3pAQCDAgAVAAIKCQzDBwBYAAAWAAEKkgurHwBJAAA1AAQKfy4ABAIACgogJRoGAJ4DAAIACgoaJRoGAJ4DABYABwrgG8YQAPUBABUAAQqvH98UAF0AAAAA.Lucilight:BAAANQAECgQIBgAAAA==.Luckyboi:BAABNQAECn8nAAMXAAkKMBkXcACdAgAXAAkK7RYXcACdAgAFAAMKyxakJADJAAAAAA==.Luckymeoww:BAABNQAECn8qAAMPAAgK4BMoTgDcAQAPAAgK4BMoTgDcAQAiAAQKbhHQdQDLAAAAAA==.Lunargrowth:BAAANQADCgQICAAAAA==.Luurain:BAAANQAECgQIBwAAAA==.',
['Lð']='Lðxic:BAAANQAECgUICgAAAA==.',
Ma='Maeveran:BAABNQAECn8kAAMkAAgKLw0QHgAKAQAIAAgKLwxhuACtAQAkAAgK3AoQHgAKAQAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIQAGAE4bAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQABCgYICwAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgIIAgAAAA==.Mangonutt:BAAANQADCggIEgAAAA==.Maryjuana:BAABNQAECn8qAAIdAAkKPA5vJQADAgAdAAkKPA5vJQADAgAAAA==.Mastalys:BAEANQAECgYIBgAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECn87AAMdAAoKgxiUKQDbAQAdAAgKbxaUKQDbAQABAAoK0hWIQgCoAQAAAA==.Mavina:BAABNQAECn9JAAMBAAoK+x7QEQA6AwABAAoK+x7QEQA6AwAEAAEKVgXyMAAiAAAAAA==.Mazez:BAABNQAECn8XAAQgAAgKfQ/ZDQD8AAAgAAcKLhDZDQD8AAAfAAEKBAyuIwA3AAAhAAEKsQCuVgATAAAAAA==.',
Me='Meanmuggin:BAAANQAECgUIBwAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Megapally:BAAANQAECgIIAgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYIEQAPAJQaAA==.Meketek:BAABNQAECn8oAAIiAAkK1hP1JQChAQAiAAkK1hP1JQChAQAAAA==.Melodica:BAAANQAECgMIAwAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAACNQAFFH8HAAIXAAQKRQStHQDCAAAXAAQKRQStHQDCAAA1AAQKfz8AAhcACgq5GQs0ACECABcACgq5GQs0ACECAAAA.Mercader:BAAANQAECgYICwAAAA==.Merrvoid:BAABNQAECn8uAAISAAoKcRRbUAB+AgASAAoKcRRbUAB+AgAAAA==.Messîah:BAAANQAECgYIBgAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAABNQAECn8lAAIgAAkK8wasGwCQAQAgAAkK8wasGwCQAQAAAA==.Mildo:BAABNQAECn8qAAIWAAgKyBuECQBhAgAWAAgKyBuECQBhAgAAAA==.Millerlight:BAAANQAECgUIDQAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAARAAAAAA==.Minervá:BAACNQAFFH8GAAQNAAQK8Af1AQCOAAANAAIKqwr1AQCOAAAbAAEKlgReEQA+AAAOAAEKeQKiGgA3AAA1AAQKfxQABAwACQrzGcENANMBAAwABwqzG8ENANMBAA0AAwqHGEwdAJYAAA4AAwrrCl9WAHAAAAAA.Minotàurus:BAABNQAECn8XAAISAAgKoA4sbQBeAQASAAgKoA4sbQBeAQAAAA==.Mintonka:BAABNQAECn8cAAIYAAcK3AN+dgCzAAAYAAcK3AN+dgCzAAAAAA==.Miranaaster:BAABNQAECn8hAAIXAAoKTxcsQgDuAQAXAAoKTxcsQgDuAQAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAABNQAECn8dAAQaAAkKwANCJQD6AAAaAAkKpgNCJQD6AAAZAAEK/wP3MgAqAAAGAAEKmAIGNgAfAAAAAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECn8uAAIOAAoKOho/JwCaAgAOAAoKOho/JwCaAgAAAA==.Monstershi:BAAANQABCgIIAgAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Moonshroom:BAAANQAECgIIAgABNQAECgIIAgARAAAAAA==.Moovina:BAAANQADCgMIAwABNQAECgoKSQABAPseAA==.Moraien:BAABNQAFFH8FAAMWAAUKcQl1EQCNAAAWAAIKCwh1EQCNAAACAAMK1wr9NgCCAAAAAA==.Morchanna:BAABNQAECn8jAAISAAoK2wxcfQATAgASAAoK2wxcfQATAgAAAA==.Morf:BAAANQADCgMIBAAAAA==.Morgy:BAAANQADCggICAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrae:BAAANQAECgEIAQAAAA==.Myrokorian:BAAANQADCgcIBwAAAA==.Mystichex:BAAANQAECgIIAgABNQAECggIDgARAAAAAA==.',
['Mä']='Mäzikeen:BAABNQAECn8VAAMlAAcKLRo2FABqAQAlAAUKdx02FABqAQAJAAcK1RQQLAA+AQABNQAECgkJKQAiAD0dAA==.',
Na='Nalkoa:BAAANQADCgYIBgAAAA==.Natalietes:BAAANQAECgYICgAAAA==.Nattylight:BAABNQAECn8fAAMQAAcKnRF2VwCVAQAQAAcKnRF2VwCVAQAPAAEKlQXw8QAlAAAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgoKIQAYAAUVAA==.',
Ne='Newhealer:BAAANQAECgUIBwAAAA==.',
Ni='Nibletz:BAAANQAECggICgAAAA==.Nightshayde:BAAANQADCggICAAAAA==.Ninelinez:BAABNQAECn8ZAAIZAAkK1iGPBwDBAgAZAAkK1iGPBwDBAgAAAA==.',
No='Nool:BAAANQADCgMIAwAAAA==.Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAABNQAECn8WAAMdAAYKEgpkQgAfAQAdAAYKEgpkQgAfAQABAAEKvhCGAQErAAABNQAECgoKGgAUAP4NAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgkJGQAZANYhAA==.',
['Nò']='Nòte:BAAANQADCgQIBAABNQAECgIJAgARAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oa='Oatmealstout:BAAANQADCgEIAQAAAA==.',
Oc='Ochana:BAABNQAECn8aAAIUAAoK/g38LQDvAQAUAAoK/g38LQDvAQAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwARAAAAAA==.',
Ol='Oldnote:BAAANQADCgIIAgAAAA==.Oleßigßahlz:BAAANQADCgEIAQAAAA==.Olgalina:BAAANQADCgQICAABNQAECgcIJAAEAPgiAA==.Olorinn:BAAANQADCgQIBAAAAA==.',
Op='Opirix:BAACNQAFFH8FAAIBAAIKjBgKHQCRAAABAAIKjBgKHQCRAAA1AAQKfz0AAwEACgrXHkAiAOUCAAEACgrXHkAiAOUCAB0ACAquFxwoAOgBAAAA.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Painkillerx:BAAANQADCgIIAgAAAA==.Paladrome:BAAANQADCgYIBgABNQAECgoKLAAPABQOAA==.Pallycakes:BAABNQAECn8aAAIIAAgKlgXaBgETAQAIAAgKlgXaBgETAQAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Parkane:BAAANQAECgQICAAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAABNQAECn8nAAIOAAoKyA9IHwCNAQAOAAoKyA9IHwCNAQAAAA==.Patreszas:BAABNQAECn8oAAIgAAoKEhNGEwAbAgAgAAoKEhNGEwAbAgAAAA==.Patusk:BAAANQADCgYIBgABNQAECgoKKAAgABITAA==.Pawshocker:BAABNQAECn8jAAIjAAoKVyIfCAD4AgAjAAoKVyIfCAD4AgABNQAFFAgIHQAkAOUlAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Pepperss:BAAANQAECgUIBwAAAA==.Peptobismo:BAAANQAECgIIAgAAAA==.Peàches:BAAANQAECgMIBgABNQAECgcIBwARAAAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgMIBQAAAA==.',
Po='Pohaberry:BAABNQAECn83AAISAAoKyRFwPADvAQASAAoKyRFwPADvAQAAAA==.Pokemage:BAABNQAECn8uAAIXAAkKKA+zUQC5AQAXAAkKKA+zUQC5AQAAAA==.Popedk:BAABNQAECn8lAAMPAAoKlSGuEgAiAwAPAAoKlSGuEgAiAwAiAAEKPhl5pQBCAAABNQAFFAcIDgAYADYYAA==.Popesham:BAACNQAFFH8OAAIYAAcKNhg3BwAFAgAYAAcKNhg3BwAFAgA1AAQKfxgAAhgACQqSInINALgCABgACQqSInINALgCAAAA.',
Pr='Prannanm:BAAANQADCgIIAgAAAA==.Priestduude:BAAANQAECgYJBgAAAA==.Product:BAAANQAECgIIAgAAAA==.',
Pu='Pullacrapton:BAAANQAECgcICgAAAA==.Puncturé:BAABNQAECn85AAMmAAoKqAuzOACFAQAmAAoKqAuzOACFAQALAAIKjAS1RgBgAAAAAA==.',
Qu='Quasi:BAABNQAECn80AAIdAAoKERhdCwA0AgAdAAoKERhdCwA0AgAAAA==.Quiggins:BAABNQAECn88AAIIAAkKKglJeABhAQAIAAkKKglJeABhAQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJIgAZAE8TAA==.Quirky:BAAANQADCgUIFwAAAA==.',
Ra='Raeziel:BAAANQAECgQIBgAAAA==.Raffunn:BAAANQADCgcICQABNQAECgMIAwARAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgQIBQAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgUIDwABNQAFFAQIDQAiAPshAA==.Reignz:BAAANQAECgQIEgAAAA==.Reinhardt:BAABNQAECn80AAMkAAoKVh15CQAGAwAkAAoKVh15CQAGAwAIAAcKIhJSzgB/AQAAAA==.Reticular:BAABNQAECn8aAAMkAAgK1xHQHQAMAQAkAAgK1xHQHQAMAQAIAAIKQAnnCwFwAAAAAA==.',
Rh='Rhaenne:BAAANQAECgQICwAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcIDQAAAA==.',
Ru='Rubonyx:BAABNQAECn8kAAQEAAcK+CIYAgAsAgAEAAcK+CIYAgAsAgAdAAMKgB3sTADhAAABAAIKqwZP7wBWAAAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECn8WAAILAAcKXwiHUwBuAQALAAcKXwiHUwBuAQAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAABNQAECn8eAAIOAAgKMhBcRwDPAQAOAAgKMhBcRwDPAQAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAwABNQAECgIIAgARAAAAAA==.',
Sa='Sagerin:BAABNQAECn8fAAIPAAkK0A8xHwB7AQAPAAkK0A8xHwB7AQAAAA==.Sageslife:BAAANQAECgcIEwAAAA==.Saintofthetp:BAAANQAECgUIBgAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Screamodevo:BAAANQABCgIIAgABNQABCgYIBgARAAAAAA==.Scronk:BAAANQADCgcIBwABNQAECgMIBQARAAAAAA==.Scruffmcgruf:BAABNQAECn8fAAIBAAkKQxA2bwDQAQABAAkKQxA2bwDQAQAAAA==.Scubany:BAAANQADCgIJAgAAAA==.Scyl:BAAANQADCgIIAgABNQAECgcIBwARAAAAAA==.',
Se='Senadora:BAABNQAECn8bAAIaAAcKoR1EIQAiAgAaAAcKoR1EIQAiAgAAAA==.Sergrahm:BAAANQADCgYIDwAAAA==.Sezeth:BAABNQAECn8UAAMiAAkK2Bh1MAAiAgAiAAkKKRh1MAAiAgAPAAYKJA/CewAtAQAAAA==.',
Sh='Shaboomboom:BAACNQAFFH8FAAIYAAIKHRRxIgCjAAAYAAIKHRRxIgCjAAA1AAQKfyoAAhgACgonG+ktAMUCABgACgonG+ktAMUCAAAA.Shadowglaive:BAABNQAECn8xAAIeAAoKBSLkCQA6AwAeAAoKBSLkCQA6AwAAAA==.Shadownight:BAABNQAECn8iAAIPAAgKTyOJFgAHAwAPAAgKTyOJFgAHAwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Shanice:BAAANQADCgMIAwAAAA==.Sharburst:BAAANQAECggIDgAAAA==.Sharleet:BAAANQAECggIBwAAAA==.Sharlocke:BAAANQAECgYIBgAAAA==.Shaval:BAABNQAECn+lAQIIAAkK/SZdAAAPBAAIAAkK/SZdAAAPBAAAAA==.Shawman:BAAANQAECggICwAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFH8KAAMKAAQK/hCuHQAjAQAKAAQKUg6uHQAjAQAcAAIK8g2KAwCPAAA1AAQKfykAAwoACgpZG6hjAGMCAAoACgoMG6hjAGMCABwAAwqtG6UaAPsAAAAA.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgYIEgAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCggIDQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECn8iAAIZAAkKTxMWDgAVAgAZAAkKTxMWDgAVAgAAAA==.Shøøtingstar:BAAANQAECgUICQABNQAECgkJKQAiAD0dAA==.',
Si='Signet:BAABNQAECn8jAAITAAcKqx/vLgDpAQATAAcKqx/vLgDpAQAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skerrit:BAAANQADCgIIAgAAAA==.Skoss:BAABNQAECn8rAAMCAAkK3xToNgDOAQACAAkK3xToNgDOAQAWAAIKxw6MWgBxAAAAAA==.Skullshine:BAACNQAFFH8fAAQPAAcKWCAmBQDUAQAPAAUKZyEmBQDUAQAiAAMK3RNGDACrAAAQAAEKAACyNgAlAAA1AAQKfysAAw8ACgqtJX0OAEQDAA8ACQoIJX0OAEQDACIAAwoYJDM3AD8BAAAA.Skunkie:BAABNQAECn8hAAMTAAoKmBLQZwDVAQATAAoKmBLQZwDVAQAYAAEK1hjxJQFGAAAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDAAAAA==.Slickfifty:BAAANQAECgQICgAAAA==.Slippewy:BAAANQAECgIIAgAAAA==.Sluewt:BAABNQAECn8ZAAMIAAoKfQpIwACcAQAIAAkKsgtIwACcAQAUAAYKEg3yuQAJAQABNQAECgoKNgABAMEjAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smolderr:BAABNQAECn8lAAISAAkKVwbAjAAYAQASAAkKVwbAjAAYAQAAAA==.',
Sn='Snakebite:BAAANQADCgEIAQAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spacecadet:BAAANQAECgMIAwAAAA==.Spaciousyeti:BAABNQAECn8iAAIiAAkKaheCIwCyAQAiAAkKaheCIwCyAQAAAA==.Spearowhunt:BAAANQAECgYIBgAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIFgAAAA==.Spook:BAAANQADCgEIAQAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECn8pAAQiAAkKPR08GgC5AgAiAAkKixs8GgC5AgAQAAYKcxC8eQARAQAPAAMKOBT6nADEAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECggIDwAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stun:BAAANQAECgIIAgAAAA==.Stunllub:BAAANQAECggIDQAAAA==.',
Su='Suggs:BAACNQAFFH8QAAQCAAYKfhicDQDoAAACAAQKlRycDQDoAAAWAAEKOAw2HgBLAAAVAAEKAADZDgBHAAA1AAQKfycABAIACgptIWY2ALECAAIACQoxIWY2ALECABUAAwpcHtAXAM4AABYAAgqrGzNTAIUAAAAA.Superali:BAAANQADCgIIAgAAAA==.Supergoten:BAAANQAECgEIAQAAAA==.',
Sw='Swiiani:BAABNQAECn8YAAIYAAYKvgfpvQAWAQAYAAYKvgfpvQAWAQAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECggIDwAAAA==.Sylvànis:BAAANQAECgEIAQABNQAECggICgARAAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQARAAAAAA==.',
Ta='Taelinn:BAAANQADCggICwABNQAECgoKKAAgABITAA==.Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECgcIDAAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAZAE8TAA==.Taurelai:BAAANQABCggIDgAAAA==.Tauriko:BAACNQAFFH8KAAIIAAQKggywGwDKAAAIAAQKggywGwDKAAA1AAQKfzYAAggACgo6HtEmAGgCAAgACgo6HtEmAGgCAAAA.Tayvos:BAAANQAECggIEAAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAABNQAECn8pAAQPAAkK2hUgPgAmAgAPAAkK2hUgPgAmAgAiAAkKxwhDLwBqAQAQAAEKoBX5wgBCAAAAAA==.',
Th='Thebestlorax:BAAANQAECgYIDgABNQAECgkJIgAZAE8TAA==.Thejonesyy:BAAANQADCgcIBwAAAA==.Theler:BAAANQAECgMIAwABNQAFFAYIDQACAC8aAA==.Theradestria:BAAANQAECgYIDAAAAA==.Thestigg:BAABNQAECn8iAAIIAAkK5gnnwgCWAQAIAAkK5gnnwgCWAQAAAA==.Thighighs:BAAANQAECgIIAgABNQAFFAYIEAAIAFEaAA==.Thndrdwnundr:BAAANQADCgEIAQAAAA==.Thundersloot:BAAANQAECgEIAQABNQAECgoKGwAUAKwSAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAABNQAECn8fAAMWAAgKLAhaLgARAQACAAYKOgg6zgAtAQAWAAYKvQVaLgARAQAAAA==.',
To='Toedumbz:BAAANQAECgYIEgAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.Tomoee:BAAANQAECgMIAwAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQAECgYICAAAAA==.Troflgar:BAAANQAECgcICwAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgcIBgABNQAECgoKKQADAJIXAA==.',
Ts='Tsuky:BAAANQAECgYIDgAAAA==.Tsukytank:BAAANQAECgEIAgAAAA==.Tsumikui:BAACNQAFFH8GAAICAAIKWwwKGgCSAAACAAIKWwwKGgCSAAA1AAQKfzwABBYACgrJE1wMADECABYACAqQD1wMADECAAIACgqnEm4qAAgCABUACAo3DcEJAOMBAAAA.',
Ty='Tyinastor:BAAANQAECgQICgAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAAANQAECggIEwAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Un='Unalived:BAABNQAECn80AAIXAAoKMhPARQDiAQAXAAoKMhPARQDiAQAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAABNQAECn8VAAIFAAkK0Qf1GgAbAQAFAAkK0Qf1GgAbAQAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCggIHwAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Vanillia:BAAANQAECgcIDAAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAABNQAECn8YAAIcAAkKFAeAFgA0AQAcAAkKFAeAFgA0AQAAAA==.Varíann:BAAANQADCgcIDAAAAA==.',
Ve='Velro:BAAANQAECggIDQAAAA==.Vemmox:BAABNQAECn8bAAIXAAoK5hDy4ADHAQAXAAoK5hDy4ADHAQAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQAECgEIAQAAAA==.Venefica:BAAANQAECgQIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Veroks:BAAANQADCgUIDQABNQAECggIDQARAAAAAA==.Vesemir:BAABNQAECn8uAAIeAAgKLhEjGwBXAQAeAAgKLhEjGwBXAQAAAA==.',
Vh='Vhpsv:BAAANQAECggICgAAAA==.',
Vi='Vianir:BAABNQAECn8fAAIIAAkKLg+AqADPAQAIAAkKLg+AqADPAQAAAA==.Vindictive:BAAANQAECggIEAAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgUIBgAAAA==.',
Wa='Wads:BAAANQAECgUIBQAAAA==.Warscared:BAABNQAECn8UAAIKAAgKJQTA2wA1AQAKAAgKJQTA2wA1AQAAAA==.Wasabis:BAABNQAECn8zAAIYAAoKWQmYfwCmAQAYAAoKWQmYfwCmAQAAAA==.',
We='Wels:BAABNQAECn82AAIBAAoKwSOYCwAoAwABAAoKwSOYCwAoAwAAAA==.',
Wh='Whichwitch:BAAANQADCggIEgAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAABNQAECn8VAAIYAAcKbBW2egCzAQAYAAcKbBW2egCzAQAAAA==.',
Wi='Wigglypuffsr:BAABNQAECn8kAAIIAAkKmByuNQAiAgAIAAkKmByuNQAiAgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECn8xAAIXAAoKYh4ZFwCsAgAXAAoKYh4ZFwCsAgAAAA==.Winddrake:BAABNQAECn8VAAISAAoKuBBKogDBAQASAAoKuBBKogDBAQAAAA==.Windstorm:BAAANQADCgMIAwAAAA==.Wixania:BAAANQAECgQIBQAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAABNQAECn8WAAICAAgKAwYGgAD1AAACAAgKAwYGgAD1AAAAAA==.Xanneste:BAABNQAECn8qAAIJAAoKxAryIQCGAQAJAAoKxAryIQCGAQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xe='Xecutioner:BAAANQAECgIIAgAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xk='Xkatarina:BAAANQAECgIIAQAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQAECgIIAgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.Yanelaru:BAAANQABCgYIBgAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yo='Yoshiyokai:BAAANQAECggIBwAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAcAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAAANQAECggIEAABNQAFFAQIDQAiAPshAA==.',
['Yâ']='Yâtiri:BAAANQAECgMIAwAAAA==.',
Za='Zaebos:BAAANQAECgMIAwAAAA==.Zakwa:BAAANQAECggICgAAAA==.Zalfanso:BAEANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQABCgQIBAAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggIDAAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAABNQAECn8jAAIHAAoKKA1FDwDWAQAHAAoKKA1FDwDWAQAAAA==.',
Zi='Ziralila:BAABNQAECn8oAAISAAkKIwgVhgAmAQASAAkKIwgVhgAmAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAABNQAECn8VAAIKAAcKwhExqAC4AQAKAAcKwhExqAC4AQAAAA==.',
Zu='Zuglybob:BAAANQADCgUIBwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Ño']='Ñote:BAAANQADCgYIBgABNQAECgIJAgARAAAAAA==.',
['Óm']='Ómèn:BAAANQAECgMIBQABNQAFFAEIAQARAAAAAA==.',
['Ör']='Örin:BAACNQAFFH8GAAMLAAIKbh8wBQDAAAALAAIKbh8wBQDAAAAnAAEKxg2zAwBIAAA1AAQKf0AABAsACgpqJJMBADEDAAsACgr0I5MBADEDACcACApNH3IEAMgCACYAAQqMBqqaADYAAAAA.',
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
