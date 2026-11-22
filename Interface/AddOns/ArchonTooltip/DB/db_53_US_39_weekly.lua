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

local lookup = {'Priest-Holy','DeathKnight-Blood','Warrior-Protection','Priest-Discipline','Mage-Frost','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','Warlock-Demonology','DeathKnight-Unholy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Warrior-Fury','Priest-Shadow','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Rogue-Subtlety','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECggIDQAAAA==.Adolin:BAAANQAECgUIBQABNQAECgoKWwABAOchAA==.',
Ae='Aegeax:BAAANQAECgcIBwAAAA==.',
Af='After:BAAANQAECgQIBAABNQAECgoKUAACAO0gAA==.Afterall:BAAANQAECgMIAwABNQAECgoKUAACAO0gAA==.',
Ag='Aggropull:BAABNQAECn8zAAIDAAkKFwmuHABzAQADAAkKFwmuHABzAQAAAA==.',
Ai='Ainzoolbone:BAAANQADCgUIBwAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgoKMgAEANQjAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Alroy:BAAANQADCgIIAgAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.Amourantha:BAAANQADCgYIBgAAAA==.',
An='Anchovia:BAAANQAECgQIDAAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIBAAAAA==.Anthonyisme:BAABNQAECn8gAAIFAAkKfBC1CQA1AgAFAAkKfBC1CQA1AgAAAA==.Anthonysbear:BAAANQABCgIIBAABNQAECgkJIAAFAHwQAA==.Antikael:BAAANQADCgYIBgAAAA==.',
Ao='Aoesham:BAAANQAECgYIBwAAAA==.',
Ap='Aphelli:BAAANQADCgEIAQAAAA==.Apoptosis:BAAANQADCgcIDwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcadis:BAAANQADCgYIBgAAAA==.Arcamania:BAAANQAFFAEIAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Aryndinnin:BAABNQAECn8hAAIGAAkKThuPEAB2AgAGAAkKThuPEAB2AgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Ashmay:BAAANQABCgcIBgAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQAECgQIBAAAAA==.',
At='Athrunn:BAAANQAECggIDgABNQAECgoKMAAHAFslAA==.Attincy:BAAANQADCggILAAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECn87AAIIAAoKChDEjACyAQAIAAoKChDEjACyAQAAAA==.',
Ay='Ayah:BAABNQAECn8uAAIBAAoK5xQxVwAdAgABAAoK5xQxVwAdAgAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECn8pAAIJAAoK2Qo2SQCCAQAJAAoK2Qo2SQCCAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECn82AAIKAAkK2BIybQC6AQAKAAkK2BIybQC6AQAAAA==.',
Ba='Babycale:BAABNQAECn8fAAILAAkKIh05DwAHAwALAAkKIh05DwAHAwAAAA==.Badger:BAAANQAECgQICQAAAA==.Baggage:BAAANQAECgcICQAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQAECgMIAwAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Beardette:BAAANQABCgIIAgAAAA==.Bearenstein:BAAANQAECgEIAQAAAA==.Beartrixa:BAAANQAECgEIAQAAAA==.Beastlight:BAABNQAECn8VAAMMAAcK6RARKgBHAQAMAAYKShMRKgBHAQANAAUKogumIgD7AAAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECggICAABNQAECgoKNQAOAOUaAA==.Bellsbane:BAAANQAECgMIAwAAAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECn8hAAIPAAgK8ge+pwCEAQAPAAgK8ge+pwCEAQAAAA==.',
Bf='Bfx:BAABNQAECn8mAAIQAAoKJRBdJAC+AQAQAAoKJRBdJAC+AQAAAA==.',
Bi='Biggiesize:BAAANQAECgIIAgAAAA==.Bigred:BAAANQADCgUIAgAAAA==.Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECn8aAAIMAAcK5BxyEwAsAgAMAAcK5BxyEwAsAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgkJLQAIAFIfAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECn80AAMCAAoKdSIXCAB7AwACAAoKdSIXCAB7AwAQAAMKeRHIsgCLAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQICAARAAAAAA==.Budgi:BAAANQADCgMIAgAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAABNQAECn8rAAICAAkKJRL1PgAEAgACAAkKJRL1PgAEAgAAAA==.Bustie:BAAANQAECgMIBQAAAA==.',
['Bé']='Bétrayal:BAAANQABCgMIAwAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAUIEAASAGYXAA==.Calahunts:BAACNQAFFH8QAAISAAUKZhdOCgBLAQASAAUKZhdOCgBLAQA1AAQKf0AAAxIACgrLJboHAE4DABIACgrLJboHAE4DAAcAAQq8AiGdACIAAAAA.Calatath:BAAANQAECgQICAABNQAFFAUIEAASAGYXAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAABNQAECn8VAAITAAcKLwrEnQA8AQATAAcKLwrEnQA8AQAAAA==.Catlinn:BAABNQAECn8dAAMUAAYKagNc9QCVAAAUAAYKagNc9QCVAAAIAAIKvwDE2AEXAAAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAACNQAFFH8NAAIGAAUKshsuBQBQAQAGAAUKshsuBQBQAQA1AAQKfyYAAgYACgqWISoGADkDAAYACgqWISoGADkDAAAA.',
Ch='Chadolas:BAAANQAECgEIAQAAAA==.Charinae:BAAANQADCgUICgAAAA==.Chiggin:BAAANQAECgUIBwAAAA==.Chillay:BAAANQAECgQIBAAAAA==.Chokeahoa:BAAANQADCggIEAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECn9EAAIIAAoK7RikWgAgAgAIAAoK7RikWgAgAgAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Clauyia:BAAANQAECgUIBQAAAA==.Cleaveauge:BAABNQAECn8vAAMKAAoKIhlUhgAMAgAKAAoK3BZUhgAMAgADAAYKHBnvHwD+AAAAAA==.Cloggy:BAACNQAFFH8PAAMPAAgK8BNIFwA7AQAPAAYKRhdIFwA7AQAVAAIKRQPQCgBTAAA1AAQKf0IABA8ACgqtJFgIAIoDAA8ACgqmJFgIAIoDABUAAgqxIekYALwAABYAAgqLIuVcAGwAAAAA.Clovver:BAAANQADCgEIAQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgQIDwARAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAABNQAECn9KAAIXAAoK3h4xJwCiAgAXAAoK3h4xJwCiAgAAAA==.Corpulent:BAAANQADCgQIBAAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAABNQAECn8sAAISAAoK+RilTwAuAgASAAoK+RilTwAuAgAAAA==.',
Cr='Crackasbank:BAAANQAECgUIBgAAAA==.Crackasmasha:BAAANQADCggIFgAAAA==.Crackazen:BAAANQAECgEIAQAAAA==.Crayven:BAAANQAECgUIDQAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgYIEAABNQAECgoKJQAYALoXAA==.Crownpal:BAAANQAECgYIDAABNQAECgoKUgAZANYgAA==.Crownroyale:BAABNQAECn9SAAMZAAoK1iBSAgD0AgAZAAoK1iBSAgD0AgAaAAEKugKCZwAYAAAAAA==.Crownwarrior:BAABNQAECn8bAAIDAAkKKA2YEgCQAQADAAkKKA2YEgCQAQABNQAECgoKUgAZANYgAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAYIBgABAFkXAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAACNQAFFH8KAAIYAAMKGg+CEwDTAAAYAAMKGg+CEwDTAAA1AAQKf1MAAxgACgp1GzYeAIECABgACgp1GzYeAIECABMAAQrrAY4lAScAAAAA.Daityasfist:BAACNQAFFH8QAAIaAAcKliT5AgBGAgAaAAcKliT5AgBGAgA1AAQKfykAAhoACgq1JkYBAHcDABoACgq1JkYBAHcDAAAA.Daler:BAAANQADCgYICQAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECn8WAAIbAAgKPxvVGwBYAgAbAAgKPxvVGwBYAgAAAA==.Daniellesan:BAAANQAECgYICQAAAA==.Danishhunter:BAABNQAECn8aAAIJAAcKCgTaXgCoAAAJAAcKCgTaXgCoAAAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAABNQAECn8aAAIcAAcKkwedFgAxAQAcAAcKkwedFgAxAQAAAA==.Darkseksi:BAABNQAECn8sAAIdAAoKowvIGwC4AQAdAAoKowvIGwC4AQAAAA==.Dashmodius:BAABNQAECn81AAIeAAoKCCGICgAzAwAeAAoKCCGICgAzAwAAAA==.Datakutasa:BAABNQAECn8qAAIQAAoKtR+sDQCgAgAQAAoKtR+sDQCgAgAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQAECgcIDgAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgUICAAAAA==.',
Dd='Ddggaaman:BAAANQAECgYIBgAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAABNQAECn8cAAQfAAkKrAZlEgAMAQAfAAgKkgVlEgAMAQAgAAYK7QXJJgD/AAAhAAcKPwIrNQDrAAAAAA==.Deathera:BAACNQAFFH8GAAIBAAYKWRcRDQDZAQABAAYKWRcRDQDZAQA1AAQKfywAAgEACgo6IccIAKkDAAEACgo6IccIAKkDAAAA.Deathpack:BAACNQAFFH8NAAIiAAQK+yEfCgBFAQAiAAQK+yEfCgBFAQA1AAQKfzwAAiIACgqyIx8EAJ8DACIACgqyIx8EAJ8DAAAA.Deathsmiley:BAABNQAECn8mAAMiAAoK6AwiQgC8AQAiAAoK6AwiQgC8AQACAAIKQQOFyQA2AAAAAA==.Delani:BAAANQAECgUICwAAAA==.Delavi:BAAANQADCggIAwABNQAECgUICwARAAAAAA==.Demonbob:BAABNQAECn8rAAIJAAgKfRixLQA3AgAJAAgKfRixLQA3AgAAAA==.Deohgee:BAABNQAECn8sAAISAAkKpxLAfgC9AQASAAkKpxLAfgC9AQAAAA==.Deranker:BAACNQAFFH8PAAIXAAUK6RayKwDIAAAXAAUK6RayKwDIAAA1AAQKfysAAxcACgrQHsRmALACABcACgrQHsRmALACAAUAAQoAAJtJADIAAAAA.Derpintine:BAAANQAECgEIAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQARAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAACNQAFFH8IAAIYAAMKqw1bHgCKAAAYAAMKqw1bHgCKAAA1AAQKf1sAAhgACgrEH40XAK4CABgACgrEH40XAK4CAAAA.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAABNQAECn88AAITAAkKvRx0HQDOAgATAAkKvRx0HQDOAgAAAA==.Dixonmyas:BAAANQADCggICwAAAA==.Diyther:BAABNQAECn8iAAMTAAkKwx66XAD5AQATAAgKrB66XAD5AQAYAAUKDxH1rwAzAQAAAA==.',
Dk='Dkaara:BAAANQADCggIEgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECn8yAAIeAAgKPRenIABIAgAeAAgKPRenIABIAgAAAA==.',
Dr='Draganhammer:BAABNQAECn8oAAIIAAkKJxKRewA0AgAIAAkKJxKRewA0AgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Dreadmorne:BAAANQAECgUIBQAAAA==.Dreadvyr:BAABNQAECn8fAAMCAAkKagrpQwAuAQACAAgKFgrpQwAuAQAiAAcKkgf5ZAAPAQAAAA==.Droodar:BAAANQAECgEIAQABNQAECgoKMgAEANQjAA==.Droopey:BAABNQAECn8oAAMXAAkK9Ac/zwALAQAXAAgKKQc/zwALAQAFAAMKoQbSKwCHAAAAAA==.',
Du='Duckywg:BAABNQAECn8gAAIJAAgKTxJSNAAKAgAJAAgKTxJSNAAKAgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgYIDQAAAA==.',
Ea='Easykill:BAAANQAECggIDwAAAA==.',
Eb='Ebomb:BAAANQAECgIIAgAAAA==.',
Ec='Echo:BAEANQADCgcIBwABNQAECgoKLQAjADkQAA==.Eclipsea:BAABNQAECn8UAAMbAAYKyAoAUADJAAAbAAUKpAcAUADJAAAOAAIKGgTugwA9AAAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECn9OAAIUAAoKYyAZFQAQAwAUAAoKYyAZFQAQAwAAAA==.Eiryn:BAAANQAECgQIBwAAAA==.Eisenhauer:BAABNQAFFH8KAAIYAAoKpwALKQBCAAAYAAoKpwALKQBCAAAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECn9JAAIkAAkKbB6iDgAqAgAkAAkKbB6iDgAqAgAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQAECgQIBAAAAA==.Envyy:BAAANQAECgQIBAAAAA==.',
Er='Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAABNQAECn89AAMPAAoKMxJARwD/AQAPAAoKMxJARwD/AQAWAAEKJw9XOQAyAAAAAA==.Evelisse:BAAANQADCgEIAQAAAA==.Evovegeta:BAAANQAECgEIAQAAAA==.',
Ew='Ewanae:BAABNQAECn8YAAMkAAkKrhL0EwAqAgAkAAkKrhL0EwAqAgAYAAIKUQIdHgFUAAABNQAFFAUIBwANAJ8IAA==.',
Ex='Expert:BAAANQAECgMIBAAAAA==.',
Fa='Falygarro:BAAANQAECgIIAgABNQAECgQIBAARAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Fenrís:BAAANQADCgIIAgAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Feri:BAAANQABCgIIAgAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgUICgAAAA==.',
Fi='Fiolidris:BAAANQAECgQIBAAAAA==.Firetotes:BAABNQAECn9ZAAMTAAoK8h+3EgAjAwATAAoK8h+3EgAjAwAYAAEKAABCJAEAAAAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Foidscarred:BAACNQAFFH8IAAIJAAcKVw56CACtAQAJAAcKVw56CACtAQA1AAQKfxoAAgkACQoUITAZANECAAkACQoUITAZANECAAE1AAUUAwoJABwAnBsA.Forfoxsakes:BAAANQAECgUICwAAAA==.Forget:BAABNQAECn9QAAQCAAoK7SBlCwDbAgACAAoK7SBlCwDbAgAiAAQKfxbxbADrAAAQAAMKmwzGswCJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQAECgUIBgABNQAECgoKLwAKACIZAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAABNQAECn8dAAMiAAkKXCOZEQABAwAiAAkKXCOZEQABAwAQAAUKWR2LdgA+AQABNQAFFAQICAASAIkgAA==.Fruitluupz:BAAANQAECgUICgAAAA==.',
['Fæ']='Færrow:BAAANQADCggICwAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAABNQAECn8ZAAISAAgKDBUohwD9AQASAAgKDBUohwD9AQAAAA==.Garomok:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAABNQAECn8VAAIYAAgKYSRsGwAlAwAYAAgKYSRsGwAlAwABNQAFFAMIBQAPALQiAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgUIBwAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAABNQAECn8XAAMlAAYKxAHuVgBVAAAIAAQKuQEZfQFeAAAlAAYKmAHuVgBVAAAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwARAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgYIDQAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgUICgAAAA==.Greenmonk:BAABNQAECn8YAAMGAAkKUgrmHQAvAQAGAAgKiQvmHQAvAQAaAAEKAAC4gAAJAAAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAABNQAECn8nAAITAAgKgRAWZACKAQATAAgKgRAWZACKAQAAAA==.Grippyfemboy:BAABNQAECn8VAAICAAoKyRzSEgB9AgACAAoKyRzSEgB9AgABNQAFFAgIIgAlAOglAA==.Grün:BAAANQAECgYIDwAAAA==.',
Gu='Gulugg:BAAANQAECgYICQAAAA==.Gurfquake:BAABNQAECn8lAAMYAAoKuhfrQQBuAgAYAAoKuhfrQQBuAgATAAQKSxLS8QCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgQICgABNQAECgoKNQAeAAghAA==.Halujar:BAAANQADCgQIBgAAAA==.Hanahanug:BAAANQADCgYIBwAAAA==.Hangwenaz:BAABNQAECn8+AAIKAAkKhSAbIwAsAwAKAAkKhSAbIwAsAwABNQAECgkJIQAGAE4bAA==.Harrell:BAAANQAECgMIAwAAAA==.',
He='Headsplitter:BAAANQAECgEIAgAAAA==.Healbot:BAAANQAECggICAAAAA==.Healmore:BAAANQAECggICAAAAA==.Hearah:BAABNQAECn8fAAMTAAcKDQ+LjQBnAQATAAcKDQ+LjQBnAQAYAAYKdQXJyAABAQAAAA==.Hehez:BAAANQAECggIDgAAAA==.Heiter:BAAANQADCgUIBQAAAA==.Helk:BAAANQADCggICQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hex:BAAANQAECgIIAgAAAA==.Hexdabear:BAAANQAECgYICgABNQAECgoKJgATAK8gAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hexfliction:BAAANQAECgIIAgABNQAECgoKJgATAK8gAA==.Hexkwondo:BAAANQAECgMIBAABNQAECgoKJgATAK8gAA==.Hexnater:BAAANQAECgYICwABNQAECgoKJgATAK8gAA==.Hextater:BAAANQAECgYIDwABNQAECgoKJgATAK8gAA==.Hexvoker:BAAANQAECgUIBAABNQAECgoKJgATAK8gAA==.Hexxer:BAABNQAECn8mAAMTAAoKryCUCACQAwATAAoKryCUCACQAwAYAAIKPwmF/AA3AAAAAA==.Hexzel:BAABNQAECn8kAAMBAAoKpB0eIgDRAgABAAoKpB0eIgDRAgAEAAEKiAMnHgAjAAABNQAECgoKJgATAK8gAA==.',
Hi='Hightide:BAAANQAECggIAgAAAA==.Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECgoKRwAXALoVAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFH8LAAIUAAMKTSQzEgA9AQAUAAMKTSQzEgA9AQA1AAQKfzQAAhQACQrBJOUDALUDABQACQrBJOUDALUDAAAA.Holywrld:BAAANQADCgQIBAAAAA==.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECn8sAAIXAAkKfhpedQCTAgAXAAkKfhpedQCTAgABNQAFFAgIFQAQAIAkAA==.Hondô:BAECNQAFFH8VAAQQAAgKgCQvAADeAgAQAAgKgCQvAADeAgAiAAIKZyBbEgC3AAACAAEKAABiLABDAAA1AAQKf3sABBAACgrIJhEAAB0EABAACgrIJhEAAB0EACIABAraIINFAIQBAAIAAQoAAIayAGUAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUIBwABNQAFFAkJIwAaAOggAA==.',
Hu='Huntermanjoe:BAACNQAFFH8FAAISAAMKFAOIGwC4AAASAAMKFAOIGwC4AAA1AAQKf0MAAhIACgrdEKZmAPcBABIACgrdEKZmAPcBAAAA.Huntersdie:BAAANQADCgYICQAAAA==.Hunterzalt:BAABNQAECn9LAAICAAoK+RNlKgCvAQACAAoK+RNlKgCvAQAAAA==.',
Hy='Hypatia:BAAANQADCgMIAwABNQAECgoKJwAkAHgMAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAgIFQAQAIAkAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAABNQAECn84AAIIAAoKdR5bKADAAgAIAAoKdR5bKADAAgAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgQIBAAAAA==.',
Id='Idra:BAABNQAECn8wAAIHAAoKWyXfAgCwAwAHAAoKWyXfAgCwAwAAAA==.',
If='Iffa:BAAANQAECggIDAAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgcIEAAAAA==.',
Il='Illidaria:BAAANQABCgEIAQAAAA==.',
Im='Imakewhitez:BAAANQADCgcIDQAAAA==.',
Ip='Ipomoea:BAAANQAECggIDgABNQAECgoKHAAUAP4NAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgQIBAARAAAAAA==.Itsmyfault:BAAANQADCgYIFQAAAA==.',
Ja='Jackaloupe:BAAANQADCgUIBQAAAA==.Jackul:BAABNQAECn8oAAIPAAkKLBDTZQClAQAPAAkKLBDTZQClAQAAAA==.Jakilk:BAABNQAECn8eAAMQAAcKRwfmdwA6AQAQAAcKRwfmdwA6AQACAAQK6AEIrgBxAAAAAA==.Jakilky:BAABNQAECn8bAAMCAAYKDwTIjgDIAAACAAYKgAPIjgDIAAAQAAUKzgKVrACbAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQAECgMIAgAAAA==.Jaycomo:BAAANQADCggIEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECn8tAAIIAAgKpgdm6wBFAQAIAAgKpgdm6wBFAQAAAA==.',
Je='Jebuss:BAAANQAECgUIBAAAAA==.Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBgABNQAECgoKJgAQAGMbAA==.Jellydead:BAABNQAECn8mAAIQAAoKYxtIMABuAgAQAAoKYxtIMABuAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.Jiyu:BAAANQAECgIIBQAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQAECgYIDAAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwARAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIDgABNQAECgoKLwAKACIZAA==.Juggernåut:BAAANQAECgcICgAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFH8PAAITAAUKtB02CADQAQATAAUKtB02CADQAQA1AAQKfzAAAxMACgpYIqYVACIDABMACgpYIqYVACIDABgABwq5DkmOAIABAAE1AAUUBggGAAEAWRcA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECn9RAAIOAAoKKhxcEgCRAgAOAAoKKhxcEgCRAgABNQABCgYIDAARAAAAAA==.Kaelthuss:BAABNQAECn8VAAIXAAcK3w/sKgFEAQAXAAcK3w/sKgFEAQAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgUICQAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAABNQAECn8sAAMeAAoKAgcHMwCqAQAeAAoKAgcHMwCqAQAJAAEKAACangAhAAAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECn8xAAIKAAoKqyHLIwCyAgAKAAoKqyHLIwCyAgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAAANQAECgYICgABNQAECgcICAARAAAAAA==.',
Ko='Kobii:BAAANQAECgIIAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAABNQAECn8gAAIPAAoK9xOBegD0AQAPAAoK9xOBegD0AQABNQAECgoKUAACAO0gAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgUIBgABNQAECgcIBwARAAAAAA==.',
Kr='Krazyhealz:BAAANQAECgIIAgABNQAECggIEwARAAAAAA==.Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ku='Kurokitsune:BAAANQAECgQIBAAAAA==.',
Ky='Kylofinn:BAABNQAECn8dAAMKAAgKThTvgACFAQAKAAgKThTvgACFAQAcAAEKAAAjMQA8AAAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAABNQAECn80AAIlAAoKLxPsGACuAQAlAAoKLxPsGACuAQAAAA==.Ladiselena:BAAANQAECgQIBAAAAA==.Laesandra:BAAANQAECgYICAAAAA==.Lalaluna:BAAANQAECgYIBwAAAA==.Lalatide:BAABNQAECn8YAAITAAkKeBErYQCVAQATAAkKeBErYQCVAQAAAA==.Languish:BAAANQAECggIAgAAAA==.Lastris:BAABNQAECn8ZAAMIAAkKNwoLAwEaAQAIAAcKpgULAwEaAQAUAAcKVQgd0ADbAAAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgoKHAAUAP4NAA==.Lavénder:BAAANQAECgQIBAAAAA==.',
Le='Legendrìser:BAAANQADCggICAAAAA==.Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAABNQAECn9CAAIIAAoKvxgFVAAxAgAIAAoKvxgFVAAxAgAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFH8iAAIlAAgK6CVIAAAGAwAlAAgK6CVIAAAGAwA1AAQKfzwAAiUACgrtJsEAAOYDACUACgrtJsEAAOYDAAAA.Lildwarf:BAEBNQAECn8XAAIKAAgKkBaqiwD/AQAKAAgKkBaqiwD/AQABNQAECggIGQAaACQfAA==.Lillidin:BAAANQAECgYICwAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgARAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECn8nAAIQAAkKvg/QTgDZAQAQAAkKvg/QTgDZAQAAAA==.Litebritepeg:BAAANQADCgUIBQAAAA==.Liusanjie:BAAANQADCgEIAQAAAA==.Livesoff:BAAANQAECgIIAgABNQAFFAMICAAQAPIDAA==.Lizerd:BAAANQADCgYIBgABNQAFFAMICQABAK4dAA==.',
Lo='Lochgimli:BAAANQAECgEIAgAAAA==.Louvetier:BAAANQAECgUICwAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFH8dAAQPAAgKYxzpAQCDAgAPAAgKYxzpAQCDAgAVAAIKCQzHCwBOAAAWAAEKkgurHwBJAAA1AAQKfy8ABA8ACgp0JRoGAJ4DAA8ACgp0JRoGAJ4DABYABwrgG8YQAPUBABUAAQqvH1InAE0AAAAA.Lucilight:BAAANQAECgYIDQAAAA==.Luckyboi:BAABNQAECn8nAAMXAAkKMBkXcACdAgAXAAkK7RYXcACdAgAFAAMKyxakJADJAAAAAA==.Luckymeoww:BAABNQAECn8qAAMQAAgK4BMoTgDcAQAQAAgK4BMoTgDcAQAiAAQKbhHQdQDLAAAAAA==.Lunargrowth:BAAANQADCgQICAAAAA==.Luurain:BAAANQAECgYIBwAAAA==.',
['Lí']='Líllíth:BAAANQADCgQIBAAAAA==.',
['Lð']='Lðxic:BAAANQAECgUICgAAAA==.',
Ma='Madabardas:BAAANQADCgUIBQAAAA==.Maeveran:BAABNQAECn81AAMlAAoK9w7cGwCSAQAIAAgKLwxhuACtAQAlAAoKyg7cGwCSAQAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIQAGAE4bAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQAECgEIAQAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgYIDgAAAA==.Mangonutt:BAAANQADCggIEgAAAA==.Maryjuana:BAABNQAECn8qAAIdAAkKPA5vJQADAgAdAAkKPA5vJQADAgAAAA==.Mastalys:BAEANQAECgYIBgAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECn9YAAMdAAoKuxkQDwBpAgAdAAoKuxkQDwBpAgABAAoK/RYoRQAjAgAAAA==.Mavina:BAABNQAECn9bAAQBAAoK5yHQEQA6AwABAAoK5yHQEQA6AwAdAAIKdAu+TgBxAAAEAAEKVgXyMAAiAAAAAA==.Mazez:BAABNQAECn8pAAQgAAoKkQ4/CwCvAQAgAAoKGQ4/CwCvAQAfAAEKBAyuIwA3AAAhAAIK/gIvQAAfAAAAAA==.',
Me='Meanmuggin:BAAANQAECgUIBwAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Megapally:BAAANQAECgIIAgAAAA==.Meitachi:BAAANQAECgcICwABNQAFFAYIEQAQAJQaAA==.Meketek:BAABNQAECn8wAAIiAAkKZhSxPACrAQAiAAkKZhSxPACrAQAAAA==.Melatopia:BAAANQADCggICQAAAA==.Melodica:BAAANQAECgUIBQAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAACNQAFFH8IAAIXAAQKRQTeMACuAAAXAAQKRQTeMACuAAA1AAQKf0QAAhcACgqIG5hGADkCABcACgqIG5hGADkCAAAA.Mentalist:BAAANQAECgMIBAAAAA==.Mercader:BAAANQAECgYIDQAAAA==.Merrvoid:BAABNQAECn8uAAISAAoKcRRbUAB+AgASAAoKcRRbUAB+AgAAAA==.Messîah:BAAANQAECgcICwAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAABNQAECn8nAAIgAAkKhQesGwCQAQAgAAkKhQesGwCQAQAAAA==.Mildo:BAABNQAECn85AAQWAAoKzxqECQBhAgAWAAgKyBuECQBhAgAPAAUK/w1dtwDkAAAVAAMKwxe/FQDeAAAAAA==.Millerlight:BAABNQAECn8UAAMXAAcKNATDAAGzAAAXAAcKNATDAAGzAAAFAAEKAAAqVAAbAAAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAARAAAAAA==.Minervá:BAACNQAFFH8HAAQNAAUKnwgWAgDDAAANAAMKqwoWAgDDAAAbAAEKlgT5GAA6AAAOAAEKeQKzJQAyAAA1AAQKfyIABQwACQqOGoQZALsBAAwABwqzG4QZALsBAA0ABAoCHVIdAB8BAA4ABApHE0pYAL8AABsAAQo/A1mEABwAAAAA.Minotàurus:BAABNQAECn8qAAISAAoKIBHNVAAiAgASAAoKIBHNVAAiAgAAAA==.Mintonka:BAABNQAECn8cAAIYAAcK3ANGxAAJAQAYAAcK3ANGxAAJAQAAAA==.Miranaaster:BAABNQAECn8kAAIXAAoKTxc2UwAYAgAXAAoKTxc2UwAYAgAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAABNQAECn8uAAQaAAoKkQk0JwBgAQAaAAoK6Ac0JwBgAQAZAAMK0QgwIgBXAAAGAAEKIQasQgAjAAABNQAECgoKPQAUAGkXAA==.Mixologist:BAAANQABCgIIAgAAAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECn81AAIOAAoK5Ro/JwCaAgAOAAoK5Ro/JwCaAgAAAA==.Monona:BAAANQAECgMIAwABNQAFFAQICAAXAEUEAA==.Monstershi:BAAANQABCgIIAgAAAA==.Mooarcane:BAAANQAECgMIAwABNQAECggIEAARAAAAAA==.Moonshroom:BAAANQAECggIEAAAAA==.Moopiehead:BAAANQADCgUIBQAAAA==.Moovina:BAAANQADCgMIAwABNQAECgoKWwABAOchAA==.Moraien:BAABNQAFFH8FAAMWAAUKcQl1EQCNAAAWAAIKCwh1EQCNAAAPAAMK1wr9NgCCAAAAAA==.Morchanna:BAABNQAECn8kAAISAAoK2wxcfQATAgASAAoK2wxcfQATAgAAAA==.Morf:BAAANQADCgMIBAAAAA==.Morgy:BAAANQADCggICAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrae:BAAANQAECgEIAQAAAA==.Myrokorian:BAAANQADCgcIBwAAAA==.Mystichex:BAAANQAECgIIAgABNQAECgoKJgATAK8gAA==.',
['Mä']='Mäzikeen:BAABNQAECn8XAAMmAAcKoBo2FABqAQAJAAcKSBWpNgBvAQAmAAUKdx02FABqAQABNQAECgkJLQAiANEeAA==.',
Na='Nalkoa:BAAANQADCgYIBgAAAA==.Naomasa:BAABNQAECn8ZAAMDAAoKnhCzDwC8AQADAAoKQg+zDwC8AQAKAAoKkQjImQBLAQABNQAECgoKUAACAO0gAA==.Natalietes:BAAANQAECgYICgAAAA==.Nattylight:BAABNQAECn8iAAMCAAcKnRF2VwCVAQACAAcKnRF2VwCVAQAQAAEKlQXw8QAlAAAAAA==.Nattylite:BAABNQAECn8iAAQmAAoKFw8UDQB9AQAmAAkK+A4UDQB9AQAJAAYKXwsBQgAtAQAeAAEKAAAjbQAzAAABNQAECgoKJQAYALoXAA==.',
Ne='Newhealer:BAAANQAECgQIBwAAAA==.',
Ni='Nibletz:BAAANQAECggIEQAAAA==.Nightshayde:BAAANQADCggICAAAAA==.Ninelinez:BAABNQAECn8ZAAIZAAkK1iGPBwDBAgAZAAkK1iGPBwDBAgAAAA==.',
No='Nool:BAAANQADCgMIAwAAAA==.Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAABNQAECn8WAAMdAAYKEgpkQgAfAQAdAAYKEgpkQgAfAQABAAEKvhCGAQErAAABNQAECgoKHAAUAP4NAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgkJGQAZANYhAA==.',
['Nò']='Nòte:BAAANQAECgEIAQABNQAECgIJAgARAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oa='Oatmealstout:BAAANQADCgEIAQAAAA==.',
Oc='Ochana:BAABNQAECn8cAAIUAAoK/g30UgDJAQAUAAoK/g30UgDJAQAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwARAAAAAA==.',
Ol='Olayro:BAAANQADCgcIBwABNQAFFAIIBQAUAOAiAA==.Oldnote:BAAANQAECgMIAwAAAA==.Olebiggy:BAAANQAECgQIBAAAAA==.Oleßigßahlz:BAAANQADCgEIAQAAAA==.Olgalina:BAAANQAECgQIBAABNQAECgoKMgAEANQjAA==.Olorinn:BAAANQADCgQIBAAAAA==.',
Op='Opirix:BAACNQAFFH8JAAMBAAMKrh1OHgD/AAABAAMKrh1OHgD/AAAdAAIKiQfeEgBkAAA1AAQKfz4AAwEACgrXHkAiAOUCAAEACgrXHkAiAOUCAB0ACAquFxwoAOgBAAAA.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Painkillerx:BAAANQADCgIIAgAAAA==.Paladrome:BAABNQAECn8WAAIIAAoK2QnJmQCZAQAIAAoK2QnJmQCZAQABNQAFFAMICAAQAPIDAA==.Pallycakes:BAABNQAECn8jAAIIAAoK8gY26AAQAQAIAAoK8gY26AAQAQAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Parkane:BAAANQAECgQICAAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAABNQAECn84AAIOAAoK7hInIwDjAQAOAAoK7hInIwDjAQAAAA==.Patreszas:BAABNQAECn8oAAIgAAoKEhNGEwAbAgAgAAoKEhNGEwAbAgAAAA==.Patusk:BAAANQAECgYIBgABNQAECgoKKAAgABITAA==.Pawshocker:BAABNQAECn8oAAIkAAoK4CIfCAD4AgAkAAoK4CIfCAD4AgABNQAFFAgIIgAlAOglAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Pepperss:BAAANQAECgUIBwAAAA==.Peptobismo:BAAANQAECgIIAgAAAA==.Perekles:BAAANQADCgIIAgAAAA==.Peàches:BAAANQAECgQICgABNQAECgcIBwARAAAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgQIDgAAAA==.',
Po='Pohaberry:BAABNQAECn87AAISAAoKahL8WQBmAgASAAoKahL8WQBmAgAAAA==.Pokemage:BAABNQAECn8zAAIXAAoK9Q/rYgDwAQAXAAoK9Q/rYgDwAQAAAA==.Popedk:BAACNQAFFH8FAAQQAAMKkQ1dEQBXAAAQAAIKthNdEQBXAAAiAAEKbActIQA5AAACAAEKAADlOAAgAAA1AAQKfykAAxAACgqhIa4SACIDABAACgqhIa4SACIDACIAAQo+GXmlAEIAAAE1AAUUBwgOABgANhgA.Popesham:BAACNQAFFH8OAAIYAAcKNhg3BwAFAgAYAAcKNhg3BwAFAgA1AAQKfxkAAhgACQqSIjUaAJsCABgACQqSIjUaAJsCAAAA.',
Pr='Prada:BAAANQAECgYICAAAAA==.Prannanm:BAAANQADCgIIAgAAAA==.Priestduude:BAAANQAECgYIBgABNQAECggIEgARAAAAAA==.Product:BAAANQAECgIIAgAAAA==.',
Pu='Pullacrapton:BAABNQAECn8YAAMIAAoKFhFavwBUAQAIAAoKpg5avwBUAQAlAAMK6hUITgCwAAAAAA==.Puncturé:BAABNQAECn9OAAMjAAoKZg6DSADeAQAjAAoKZg6DSADeAQALAAIKjATmUQBbAAAAAA==.',
Qu='Quasi:BAABNQAECn89AAIdAAoKjxrCEABNAgAdAAoKjxrCEABNAgAAAA==.Quiggins:BAABNQAECn9YAAIIAAoKoAtMlACkAQAIAAoKoAtMlACkAQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJIgAZAE8TAA==.Quirky:BAAANQADCgUIGwAAAA==.',
Ra='Raeziel:BAAANQAECgQIBgAAAA==.Raezor:BAAANQABCgQIBAAAAA==.Raffunn:BAAANQADCgcICQABNQAECgMIAwARAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgUIEAAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAABNQAECn8XAAIXAAcK6RZoEgFuAQAXAAcK6RZoEgFuAQABNQAFFAQIDQAiAPshAA==.Reignz:BAABNQAECn8lAAMmAAcKNgunFQD4AAAmAAcKNgunFQD4AAAeAAEK2gE4XwATAAAAAA==.Reinhardt:BAABNQAECn80AAMlAAoKVh15CQAGAwAlAAoKVh15CQAGAwAIAAcKIhJSzgB/AQAAAA==.Reticular:BAABNQAECn8oAAMlAAgKjxKaJgA7AQAlAAgKjxKaJgA7AQAIAAMKQAkdYAFqAAAAAA==.',
Rh='Rhaenne:BAAANQAECgUICwAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcIDQAAAA==.',
Ru='Rubonyx:BAABNQAECn8yAAQEAAoK1COtAACSAwAEAAoK1COtAACSAwAdAAUKZRvNNQDmAAABAAIKqwZP7wBWAAAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECn8ZAAILAAgKtQqHUwBuAQALAAgKtQqHUwBuAQAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAABNQAECn8eAAIOAAgKMhBcRwDPAQAOAAgKMhBcRwDPAQAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAwABNQAECgIIAgARAAAAAA==.',
Sa='Sagerin:BAABNQAECn8xAAIQAAkKERMvJQC3AQAQAAkKERMvJQC3AQAAAA==.Sageslife:BAABNQAECn8WAAIMAAgKuBhnIACYAQAMAAgKuBhnIACYAQAAAA==.Saintofthetp:BAAANQAECgUICAAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarifa:BAAANQAECgUIBQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Scronk:BAAANQADCgcIBwABNQAECgYICAARAAAAAA==.Scruffmcgruf:BAABNQAECn8kAAIBAAkKQxA2bwDQAQABAAkKQxA2bwDQAQAAAA==.Scubany:BAAANQADCgIJAgAAAA==.Scyl:BAAANQADCgIIAgABNQAECgcIBwARAAAAAA==.Scÿthe:BAAANQAECgUIBQAAAA==.',
Se='Senadora:BAABNQAECn8cAAIaAAgKoRpEIQAiAgAaAAgKoRpEIQAiAgAAAA==.Sergrahm:BAAANQADCgYIDwAAAA==.Sezeth:BAABNQAECn8UAAMiAAkK2Bh1MAAiAgAiAAkKKRh1MAAiAgAQAAYKJA/CewAtAQAAAA==.',
Sh='Shaboomboom:BAACNQAFFH8FAAIYAAIKHRRxIgCjAAAYAAIKHRRxIgCjAAA1AAQKfyoAAhgACgonG+ktAMUCABgACgonG+ktAMUCAAAA.Shadowglaive:BAABNQAECn87AAIeAAoKRSPkCQA6AwAeAAoKRSPkCQA6AwAAAA==.Shadownight:BAABNQAECn8iAAIQAAgKTyOJFgAHAwAQAAgKTyOJFgAHAwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shammyduude:BAAANQAECggIEgAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Shanice:BAAANQADCgMIAwAAAA==.Sharburst:BAAANQAECggIDgAAAA==.Sharleet:BAAANQAECggIBwAAAA==.Sharlocke:BAAANQAECgYIBgAAAA==.Sharwar:BAAANQAECggIBQAAAA==.Shaval:BAABNQAECn+lAQIIAAkK/SZdAAAPBAAIAAkK/SZdAAAPBAAAAA==.Shawman:BAAANQAECggIDwAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFH8KAAMKAAQK/hCuHQAjAQAKAAQKUg6uHQAjAQAcAAIK8g2KAwCPAAA1AAQKfykAAwoACgpZG6hjAGMCAAoACgoMG6hjAGMCABwAAwqtG6UaAPsAAAAA.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAABNQAECn8VAAMBAAkKOQ2EpwAfAQABAAgK1Q2EpwAfAQAdAAIK1Q06bABTAAAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCggIDQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECn8iAAIZAAkKTxMWDgAVAgAZAAkKTxMWDgAVAgAAAA==.Shøøtingstar:BAAANQAECgUICgABNQAECgkJLQAiANEeAA==.',
Si='Signet:BAABNQAECn86AAITAAoKER55EgAlAwATAAoKER55EgAlAwAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgUIBgAAAA==.Skerrit:BAAANQAECgYIBQAAAA==.Skoss:BAABNQAECn8xAAMPAAoKzhTTQwAJAgAPAAoKzhTTQwAJAgAWAAIKxw6MWgBxAAAAAA==.Skullshine:BAACNQAFFH8fAAQQAAcKWCAmBQDUAQAQAAUKZyEmBQDUAQAiAAMK3RPmFACiAAACAAEKAACyNgAlAAA1AAQKfzMAAxAACgqtJX0OAEQDABAACQoIJX0OAEQDACIABAqpI79BAJQBAAAA.Skunkie:BAABNQAECn8iAAMTAAoKIxTQZwDVAQATAAoKIxTQZwDVAQAYAAEK1hjxJQFGAAAAAA==.Skwiish:BAAANQAECgQIBAABNQAECgoKJQAYALoXAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDAAAAA==.Slickfifty:BAABNQAECn8YAAISAAUKIQ9i9ADIAAASAAUKIQ9i9ADIAAAAAA==.Slippewy:BAAANQAECgMIBAAAAA==.Sluewt:BAABNQAECn8hAAMIAAoKfQpIwACcAQAIAAkKsgtIwACcAQAUAAgKjA3yuQAJAQABNQAECgoKRQABAOIjAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smileysabear:BAAANQAECgQIBAABNQAECgoKJgAiAOgMAA==.Smolderr:BAABNQAECn8oAAISAAkKVwbBtwCUAQASAAkKVwbBtwCUAQAAAA==.',
Sn='Snakebite:BAAANQADCgEIAQAAAA==.Snakesshaman:BAAANQAECgQIDAAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spacecadet:BAAANQAECgYICwAAAA==.Spaciousyeti:BAABNQAECn8tAAIiAAoKgxnUJwAZAgAiAAoKgxnUJwAZAgAAAA==.Spearowhunt:BAAANQAECggICwAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Spook:BAAANQADCggICQAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECn8tAAQiAAkK0R48GgC5AgAiAAkKHx08GgC5AgACAAYKcxC8eQARAQAQAAMKOBT6nADEAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECggIDwAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stun:BAAANQAECgIIAgAAAA==.Stunllub:BAAANQAECggIDQAAAA==.',
Su='Suggs:BAACNQAFFH8QAAQPAAYKfhjcGQDdAAAPAAQKlRzcGQDdAAAWAAEKOAw2HgBLAAAVAAEKAADZDgBHAAA1AAQKfy0ABA8ACgptIWY2ALECAA8ACQoxIWY2ALECABUABQqYG9AXAM4AABYAAgqrGzNTAIUAAAAA.Superali:BAAANQADCgIIAgAAAA==.Supergoten:BAAANQAECgMIBAAAAA==.Surnaturelle:BAAANQAECgYIBgABNQAECgoKJwAkAHgMAA==.',
Sw='Swiiani:BAABNQAECn8eAAIYAAgK+QeXiAD8AAAYAAgK+QeXiAD8AAAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAABNQAECn8eAAMbAAoKTBdTIQDvAQAbAAoKTBdTIQDvAQAOAAEKAAB/0QAHAAAAAA==.Sylvànis:BAAANQAECgEIAQABNQAECggICgARAAAAAA==.',
['Sâ']='Sâmurai:BAAANQAECgMIAwAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQARAAAAAA==.',
Ta='Taelinn:BAAANQADCggICwABNQAECgoKKAAgABITAA==.Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECggIDwAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAZAE8TAA==.Taurelai:BAAANQABCggIDgAAAA==.Tauriko:BAACNQAFFH8LAAIIAAQKggywGwDKAAAIAAQKggywGwDKAAA1AAQKfzcAAggACgo6HpRLALICAAgACgo6HpRLALICAAAA.Tayvos:BAABNQAECn8eAAQEAAkK9QuyGACqAAABAAgK7Ql2hgBGAQAEAAYKUAmyGACqAAAdAAEKAADSkwAUAAAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAABNQAECn8zAAQQAAoKQRUgPgAmAgAQAAkK2hUgPgAmAgAiAAoKOQ3dNwDBAQACAAEKoBX5wgBCAAAAAA==.',
Th='Thebestlorax:BAABNQAECn8kAAIMAAoK3SH3BgDgAgAMAAoK3SH3BgDgAgABNQAECgkJIgAZAE8TAA==.Thejonesyy:BAAANQADCggIEQAAAA==.Theler:BAAANQAECgMIAwABNQAFFAgIDwAPAPATAA==.Theradestria:BAAANQAECgUIDAAAAA==.Thestigg:BAABNQAECn86AAIIAAoKPxJKaQD+AQAIAAoKPxJKaQD+AQAAAA==.Thighighs:BAAANQAECgIIAgABNQAFFAYIEAAIAFEaAA==.Thndrdwnundr:BAAANQADCgEIAQAAAA==.Thundersloot:BAABNQAECn8YAAIkAAgKAwa4GwBeAQAkAAgKAwa4GwBeAQABNQAECgoKIwAUAKgUAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Tiershan:BAAANQADCggICAAAAA==.Timmyjam:BAABNQAECn8fAAMWAAgKLAhaLgARAQAPAAYKOgg6zgAtAQAWAAYKvQVaLgARAQAAAA==.',
To='Toedumbz:BAABNQAECn8YAAIYAAgK4BJpewCxAQAYAAgK4BJpewCxAQAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.Tomoee:BAABNQAECn8VAAIIAAkKCQ1wlwCeAQAIAAkKCQ1wlwCeAQAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQAECgcIEQAAAA==.Troflgar:BAAANQAECggIDgAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgcICAABNQAECgoKLwAKACIZAA==.',
Ts='Tsuky:BAABNQAECn8ZAAMPAAgKZweLjABDAQAPAAgKZweLjABDAQAWAAEKSAQBPQAmAAAAAA==.Tsukytank:BAAANQAECgEIAgAAAA==.Tsumikui:BAACNQAFFH8KAAIPAAMK2Ag8HgC/AAAPAAMK2Ag8HgC/AAA1AAQKfz4ABBYACgqNFFwMADECABYACAqQD1wMADECAA8ACgprE1RKAPUBABUACAo3DcEJAOMBAAAA.',
Ty='Tyinastor:BAAANQAECgQICgAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAABNQAECn8iAAMbAAoK4xdzJAABAgAbAAoK4xdzJAABAgANAAQKGQ3hPABbAAAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Un='Unalived:BAABNQAECn9HAAIXAAoKuhUVUwAYAgAXAAoKuhUVUwAYAgAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAABNQAECn8VAAIFAAkK0Qf1GgAbAQAFAAkK0Qf1GgAbAQAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQAECgQICAAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Vanillia:BAAANQAECggIDgAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAABNQAECn8YAAIcAAkKFAeAFgA0AQAcAAkKFAeAFgA0AQAAAA==.Varíann:BAAANQADCggIDAAAAA==.',
Ve='Velro:BAAANQAECggIDQAAAA==.Vemmox:BAABNQAECn8cAAIXAAoK5hDy4ADHAQAXAAoK5hDy4ADHAQAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQAECgMIAQAAAA==.Venefica:BAAANQAECgQIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Verathorn:BAAANQAECgIIAgAAAA==.Veroks:BAAANQADCgUIDQABNQAECggIDQARAAAAAA==.Vesemir:BAABNQAECn9DAAIeAAoK4xW6FQAOAgAeAAoK4xW6FQAOAgAAAA==.',
Vh='Vhpsv:BAAANQAECggICgAAAA==.',
Vi='Vianir:BAABNQAECn8lAAIIAAoKsA+AqADPAQAIAAoKsA+AqADPAQAAAA==.Vindictive:BAABNQAECn8cAAIPAAoKVQaeDgGuAAAPAAoKVQaeDgGuAAAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgYIBgAAAA==.',
['Vë']='Vësper:BAAANQAECgIIAgAAAA==.',
Wa='Wads:BAABNQAECn8cAAISAAkKlRH/aQDvAQASAAkKlRH/aQDvAQAAAA==.Warscared:BAABNQAECn8UAAIKAAgKJQTA2wA1AQAKAAgKJQTA2wA1AQAAAA==.Wasabis:BAABNQAECn9FAAIYAAoKbQtTYQBjAQAYAAoKbQtTYQBjAQAAAA==.',
We='Welivin:BAAANQAECgEIAQAAAA==.Wels:BAABNQAECn9FAAIBAAoK4iPoBgDFAwABAAoK4iPoBgDFAwAAAA==.',
Wh='Whichwitch:BAAANQAECgIIAgAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAABNQAECn8VAAIYAAcKbBW2egCzAQAYAAcKbBW2egCzAQAAAA==.',
Wi='Wigglypuffsr:BAABNQAECn8tAAIIAAkKUh9rVAAwAgAIAAkKUh9rVAAwAgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECn85AAIXAAoKdx5tKgCVAgAXAAoKdx5tKgCVAgAAAA==.Winddrake:BAABNQAECn8ZAAISAAoKRhFKogDBAQASAAoKRhFKogDBAQAAAA==.Windstorm:BAAANQADCgMIAwAAAA==.Wixania:BAAANQAECgYICwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAABNQAECn8eAAMPAAkKlQm9jABDAQAPAAkKQwe9jABDAQAWAAIKrAyuJwBbAAAAAA==.Xanneste:BAABNQAECn9BAAIJAAoK9BE8JADpAQAJAAoK9BE8JADpAQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xc='Xcenturion:BAAANQADCgUICQAAAA==.',
Xe='Xecutioner:BAAANQAECgIIAgAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xk='Xkatarina:BAAANQAECgIIAQAAAA==.',
Xt='Xtremeheals:BAAANQADCgYIBgABNQAECgoKGAAIABYRAA==.',
Xx='Xxies:BAAANQAECgcIBwAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQAECgMIAgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yo='Yoshiyokai:BAAANQAECggICwAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAcAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAABNQAECn8WAAIJAAkKzhnrMACRAQAJAAkKzhnrMACRAQABNQAFFAQIDQAiAPshAA==.',
['Yâ']='Yâtiri:BAAANQAECgMIAwAAAA==.',
Za='Zaebos:BAABNQAECn8UAAIYAAYK7grYhAAFAQAYAAYK7grYhAAFAQAAAA==.Zakwa:BAAANQAECggICgAAAA==.Zalfanso:BAAANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQABCgQIBAAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICgAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAABNQAECn88AAIHAAoKjxLCEgAWAgAHAAoKjxLCEgAWAgAAAA==.',
Zi='Zildrlul:BAAANQADCgMIAwAAAA==.Ziralila:BAABNQAECn8yAAISAAkKnAgAuACUAQASAAkKnAgAuACUAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAABNQAECn8VAAIKAAcKwhExqAC4AQAKAAcKwhExqAC4AQAAAA==.',
Zu='Zuglybob:BAAANQADCgUIBwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Ño']='Ñote:BAAANQADCgYIBgABNQAECgIJAgARAAAAAA==.',
['Óm']='Ómèn:BAAANQAECgcIDAABNQAECgkJGQAIANkYAA==.',
['Ör']='Örin:BAACNQAFFH8KAAMLAAMKbiAABQANAQALAAMKbiAABQANAQAnAAEKxg2zAwBIAAA1AAQKf0MABAsACgpqJIQEAI4DAAsACgr0I4QEAI4DACcACApNH3IEAMgCACMAAQqMBl/bADYAAAAA.',
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
