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

local lookup = {'Priest-Holy','DeathKnight-Blood','Warrior-Protection','Priest-Discipline','Mage-Frost','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','Warlock-Demonology','DeathKnight-Unholy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Warrior-Fury','Priest-Shadow','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Shaman-Enhancement','Paladin-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECggIDQAAAA==.Adolin:BAAANQAECgUIBQABNQAECgoKUgABAHMhAA==.',
Ae='Aegeax:BAAANQAECgcIBwAAAA==.',
Af='After:BAAANQAECgQIBAABNQAECgoKRQACANMdAA==.Afterall:BAAANQAECgMIAwABNQAECgoKRQACANMdAA==.',
Ag='Aggropull:BAABNQAECn8zAAIDAAkKFwmuHABzAQADAAkKFwmuHABzAQAAAA==.',
Ai='Ainzoolbone:BAAANQADCgUIBwAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgkJKQAEAGUjAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Allistar:BAAANQAECgEIAQAAAA==.Alroy:BAAANQADCgIIAgAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.Amourantha:BAAANQADCgYIBgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIBAAAAA==.Anthonyisme:BAABNQAECn8gAAIFAAkKfBC1CQA1AgAFAAkKfBC1CQA1AgAAAA==.Anthonysbear:BAAANQAECgEIAQABNQAECgkJIAAFAHwQAA==.Antikael:BAAANQADCgYIBgAAAA==.',
Ap='Apoptosis:BAAANQADCgcIDwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcadis:BAAANQADCgYIBgAAAA==.Arcamania:BAAANQAFFAEIAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Arthalon:BAAANQAECgEIAwAAAA==.Aryndinnin:BAABNQAECn8hAAIGAAkKThuPEAB2AgAGAAkKThuPEAB2AgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Ashmay:BAAANQAECgEIAQAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQAECgQIBAAAAA==.',
At='Athrunn:BAAANQAECggIDgABNQAECgoKMAAHAFslAA==.Attincy:BAAANQADCggILAAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECn85AAIIAAoKChAQcwCpAQAIAAoKChAQcwCpAQAAAA==.',
Ay='Ayah:BAABNQAECn8oAAIBAAkKHRUxVwAdAgABAAkKHRUxVwAdAgAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECn8mAAIJAAkKXAo2SQCCAQAJAAkKXAo2SQCCAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECn8uAAIKAAgKWRKibwB5AQAKAAgKWRKibwB5AQAAAA==.',
Ba='Babycale:BAABNQAECn8fAAILAAkKIh05DwAHAwALAAkKIh05DwAHAwAAAA==.Badger:BAAANQAECgQIDAAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQAECgMIBAAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Beardette:BAAANQABCgIIAgAAAA==.Bearenstein:BAAANQAECgEIAQAAAA==.Beartrixa:BAAANQAECgEIAQAAAA==.Beastlight:BAABNQAECn8VAAMMAAcK6RARKgBHAQAMAAYKShMRKgBHAQANAAUKogumIgD7AAAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECggICAABNQAECgoKLwAOAGgaAA==.Bellsbane:BAAANQAECgQIBAAAAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECn8hAAIPAAgK8ge+pwCEAQAPAAgK8ge+pwCEAQAAAA==.',
Bf='Bfx:BAABNQAECn8mAAIQAAoKJRCCHQDFAQAQAAoKJRCCHQDFAQAAAA==.',
Bi='Biggiesize:BAAANQADCggIEAAAAA==.Bigred:BAAANQADCgUIAgAAAA==.Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECn8aAAIMAAcK5BxyEwAsAgAMAAcK5BxyEwAsAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgkJLQAIAFIfAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.Bowjobzz:BAAANQAECgEIAQAAAA==.',
Br='Brazz:BAABNQAECn80AAMCAAoKdSIXCAB7AwACAAoKdSIXCAB7AwAQAAMKeRHIsgCLAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQICAARAAAAAA==.Budgi:BAAANQADCgMIAgAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAABNQAECn8nAAICAAgKOxP1PgAEAgACAAgKOxP1PgAEAgAAAA==.Bustie:BAAANQAECgEIAwAAAA==.',
['Bé']='Bétrayal:BAAANQAECgEIAQAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAUIEAASAGYXAA==.Calahunts:BAACNQAFFH8QAAISAAUKZheUBgBUAQASAAUKZheUBgBUAQA1AAQKf0AAAxIACgrLJagEAFsDABIACgrLJagEAFsDAAcAAQq8AiGdACIAAAAA.Calatath:BAAANQAECgQICAABNQAFFAUIEAASAGYXAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAABNQAECn8VAAITAAcKLwrEnQA8AQATAAcKLwrEnQA8AQAAAA==.Casturbator:BAAANQAECgEIAQAAAA==.Catlinn:BAABNQAECn8cAAMUAAYKagNc9QCVAAAUAAYKagNc9QCVAAAIAAIKvwDE2AEXAAAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAACNQAFFH8NAAIGAAUKshu5AwBbAQAGAAUKshu5AwBbAQA1AAQKfyYAAgYACgqWISoGADkDAAYACgqWISoGADkDAAAA.',
Ch='Chadolas:BAAANQAECgEIAQAAAA==.Charinae:BAAANQADCgUICgAAAA==.Chiggin:BAAANQAECgUICAAAAA==.Chillay:BAAANQAECgQIBAAAAA==.Chokeahoa:BAAANQADCggIEAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECn88AAIIAAoKcxcjTgAMAgAIAAoKcxcjTgAMAgAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Clauyia:BAAANQAECgUIBQAAAA==.Cleaveauge:BAABNQAECn8rAAMDAAoKnBjIGAAKAQAKAAoKMhZUhgAMAgADAAYKHBnIGAAKAQAAAA==.Cloggy:BAACNQAFFH8OAAMPAAcKRhfxEADxAAAPAAYKRhfxEADxAAAVAAEKAADQCgBTAAA1AAQKf0AABA8ACgpWJFgIAIoDAA8ACgpOJFgIAIoDABUAAgqxIbUSAMMAABYAAgqLInMnAEwAAAAA.Clovver:BAAANQADCgEIAQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgQIDwARAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAABNQAECn9AAAIXAAoKYx45IwCXAgAXAAoKYx45IwCXAgAAAA==.Coriolenus:BAAANQADCgMIAwAAAA==.Corpulent:BAAANQADCgQIBAAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAABNQAECn8qAAISAAoK4hbEVABzAgASAAoK4hbEVABzAgAAAA==.',
Cr='Crackasbank:BAAANQAECgUICQAAAA==.Crackazen:BAAANQAECgEIAQAAAA==.Crayven:BAAANQAECgUIBQAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgYIEgABNQAECgoKJQAYALoXAA==.Crownpal:BAAANQAECgYIDAABNQAECgoKPgAZAKsgAA==.Crownroyale:BAABNQAECn8+AAMZAAoKqyDoAQDyAgAZAAoKqyDoAQDyAgAaAAEKugIWWwAYAAAAAA==.Crownwarrior:BAAANQAECgYIEAABNQAECgoKPgAZAKsgAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAYIBgABAFkXAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAACNQAFFH8JAAIYAAMKGg8vDwDYAAAYAAMKGg8vDwDYAAA1AAQKf0oAAxgACgrqGuYbAGUCABgACgrqGuYbAGUCABMAAQrrAY4lAScAAAAA.Daityasfist:BAACNQAFFH8QAAIaAAcKliT5AgBGAgAaAAcKliT5AgBGAgA1AAQKfygAAhoACgp7JgEBAHQDABoACgp7JgEBAHQDAAAA.Daler:BAAANQADCgYICQAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECn8WAAIbAAgKPxvVGwBYAgAbAAgKPxvVGwBYAgAAAA==.Daniellesan:BAAANQAECgQIBQAAAA==.Danishhunter:BAABNQAECn8UAAIJAAcK9gM+UQCqAAAJAAcK9gM+UQCqAAAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAABNQAECn8aAAIcAAcKkwedFgAxAQAcAAcKkwedFgAxAQAAAA==.Darkseksi:BAABNQAECn8cAAIdAAgKKQnRJAAhAQAdAAgKKQnRJAAhAQAAAA==.Dashmodius:BAABNQAECn8xAAIeAAoK8SCICgAzAwAeAAoK8SCICgAzAwAAAA==.Datakutasa:BAABNQAECn8kAAIQAAkKjR7aFAAeAgAQAAkKjR7aFAAeAgAAAA==.Datfourloko:BAAANQAECgEIAwAAAA==.Dathomir:BAAANQAECgcIDgAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQAECgEIAQAAAA==.',
Dd='Ddggaaman:BAAANQAECgYIBgAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAABNQAECn8cAAQfAAkKrAZlEgAMAQAfAAgKkgVlEgAMAQAgAAYK7QXJJgD/AAAhAAcKPwIrNQDrAAAAAA==.Deathera:BAACNQAFFH8GAAIBAAYKWRcOCADwAQABAAYKWRcOCADwAQA1AAQKfx4AAgEACgpRG2omAIMCAAEACgpRG2omAIMCAAAA.Deathpack:BAACNQAFFH8NAAIiAAQK+yEfCgBFAQAiAAQK+yEfCgBFAQA1AAQKfzwAAiIACgqyIx8EAJ8DACIACgqyIx8EAJ8DAAAA.Deathsmiley:BAABNQAECn8iAAMiAAkK6gwiQgC8AQAiAAkK6gwiQgC8AQACAAIKQQOFyQA2AAAAAA==.Delani:BAAANQAECgUIDAAAAA==.Delavi:BAAANQAECgEIAQABNQAECgUIDAARAAAAAA==.Demonbob:BAABNQAECn8rAAIJAAgKfRixLQA3AgAJAAgKfRixLQA3AgAAAA==.Deohgee:BAABNQAECn8jAAISAAcKyhTKoQDCAQASAAcKyhTKoQDCAQAAAA==.Deranker:BAACNQAFFH8PAAIXAAUK6RZWIQDXAAAXAAUK6RZWIQDXAAA1AAQKfysAAxcACgrQHsRmALACABcACgrQHsRmALACAAUAAQoAAJtJADIAAAAA.Derpintine:BAAANQAECgEIAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQARAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAACNQAFFH8HAAIYAAMKqw1RGACNAAAYAAMKqw1RGACNAAA1AAQKf08AAhgACgoEH0YVAJ0CABgACgoEH0YVAJ0CAAAA.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAABNQAECn8zAAITAAkKKhgMIwB5AgATAAkKKhgMIwB5AgAAAA==.Dixonmyas:BAAANQADCgMIAwAAAA==.Diyther:BAABNQAECn8eAAMTAAcKDyC6XAD5AQATAAcKDyC6XAD5AQAYAAQKqBP1rwAzAQAAAA==.',
Dk='Dkaara:BAAANQADCggIEgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECn8yAAIeAAgKPRenIABIAgAeAAgKPRenIABIAgAAAA==.',
Dr='Draganhammer:BAABNQAECn8oAAIIAAkKJxKRewA0AgAIAAkKJxKRewA0AgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Dreadmorne:BAAANQAECgEIAgAAAA==.Dreadvyr:BAABNQAECn8ZAAMCAAkKRQhRSwDmAAAiAAcKkgf5ZAAPAQACAAcKAQhRSwDmAAAAAA==.Droodar:BAAANQAECgEIAQABNQAECgkJKQAEAGUjAA==.Droopey:BAABNQAECn8lAAMXAAkKnAd4swAUAQAXAAgKKQd4swAUAQAFAAIKqwZQLgBSAAAAAA==.',
Du='Duckywg:BAABNQAECn8gAAIJAAgKTxJSNAAKAgAJAAgKTxJSNAAKAgAAAA==.Duguay:BAAANQAECgEIAgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgcIDAAAAA==.',
Ea='Easykill:BAAANQAECggIDwAAAA==.',
Eb='Ebomb:BAAANQAECgIIAgAAAA==.',
Ec='Eclipsea:BAAANQAECgUIEQAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECn88AAIUAAoKOR89GADIAgAUAAoKOR89GADIAgAAAA==.Eiryn:BAAANQAECgUIBQAAAA==.Eisenhauer:BAAANQAECgMIBAAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECn86AAIjAAkKah58CwAvAgAjAAkKah58CwAvAgAAAA==.Eluneatic:BAAANQAECgEIAQAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQAECgQIBAAAAA==.Envyy:BAAANQAECgQIBAAAAA==.',
Er='Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAABNQAECn8tAAIPAAoKiQ8dQwDXAQAPAAoKiQ8dQwDXAQAAAA==.Evelisse:BAAANQADCgEIAQAAAA==.',
Ew='Ewanae:BAABNQAECn8YAAMjAAkKrhL0EwAqAgAjAAkKrhL0EwAqAgAYAAIKUQIdHgFUAAABNQAFFAQIBgANAPAHAA==.',
Ex='Exera:BAAANQAECgEIAQAAAA==.Expert:BAAANQAECgIIAgAAAA==.',
Fa='Falygarro:BAAANQAECgIIAgABNQAECgQIBAARAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgUICwAAAA==.',
Fi='Fiolidris:BAAANQAECgQIBAAAAA==.Firetotes:BAABNQAECn9IAAMTAAoKmR8OFgDbAgATAAoKmR8OFgDbAgAYAAEKAABqBAEAAAAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgABNQAECgIIAgARAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.Fluidruid:BAAANQAECgEIAQABNQAECgEIAwARAAAAAA==.',
Fo='Foidscarred:BAACNQAFFH8IAAIJAAcKVw56CACtAQAJAAcKVw56CACtAQA1AAQKfxoAAgkACQoUITAZANECAAkACQoUITAZANECAAE1AAUUAwoJABwAnBsA.Forfoxsakes:BAAANQAECgQICwAAAA==.Forget:BAABNQAECn9FAAQCAAoK0x1VDwCJAgACAAoK0x1VDwCJAgAiAAQKfxbxbADrAAAQAAMKmwzGswCJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQAECgUIBgABNQAECgoKKwADAJwYAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAABNQAECn8dAAMiAAkKXCOZEQABAwAiAAkKXCOZEQABAwAQAAUKWR2LdgA+AQABNQAFFAQICAASAIkgAA==.Fruitluupz:BAAANQAECgUICgAAAA==.',
['Fæ']='Færrow:BAAANQADCggICwAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAABNQAECn8ZAAISAAgKDBUohwD9AQASAAgKDBUohwD9AQAAAA==.Garomok:BAAANQAECgEIAQAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAABNQAECn8VAAIYAAgKYSRsGwAlAwAYAAgKYSRsGwAlAwABNQAFFAMIBQAPALQiAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgUIBwAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgYIEAAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwARAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgYIDQAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgUICgAAAA==.Greenmonk:BAABNQAECn8YAAMGAAkKUgqNGAA9AQAGAAgKiQuNGAA9AQAaAAEKAAC4gAAJAAAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAABNQAECn8kAAITAAcKfRB3ZABWAQATAAcKfRB3ZABWAQAAAA==.Grippyfemboy:BAABNQAECn8UAAICAAoKdhwBEACAAgACAAoKdhwBEACAAgABNQAFFAgIHQAkAOUlAA==.Grün:BAAANQAECgUIDAAAAA==.',
Gu='Gulugg:BAAANQAECgIIAgAAAA==.Gurfquake:BAABNQAECn8lAAMYAAoKuhfrQQBuAgAYAAoKuhfrQQBuAgATAAQKSxLS8QCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgQICgABNQAECgoKMQAeAPEgAA==.Hanahanug:BAAANQADCgYIBwAAAA==.Hangwenaz:BAABNQAECn8+AAIKAAkKhSAbIwAsAwAKAAkKhSAbIwAsAwABNQAECgkJIQAGAE4bAA==.Harrell:BAAANQAECgMIAwAAAA==.',
He='Headsplitter:BAAANQAECgIIAgAAAA==.Hearah:BAABNQAECn8fAAMTAAcKDQ+LjQBnAQATAAcKDQ+LjQBnAQAYAAYKdQXJyAABAQAAAA==.Hehez:BAAANQAECgcICAAAAA==.Helk:BAAANQADCggICQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hex:BAAANQAECgIIAgAAAA==.Hexdabear:BAAANQAECgUICgABNQAECgoKGAABAPsbAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hexfliction:BAAANQAECgIIBAABNQAECgoKGAABAPsbAA==.Hexkwondo:BAAANQAECgMIAwABNQAECgoKGAABAPsbAA==.Hexnater:BAAANQAECgcICAABNQAECgoKGAABAPsbAA==.Hextater:BAAANQAECgcIEgABNQAECgoKGAABAPsbAA==.Hexvoker:BAAANQAECgQIBAABNQAECgoKGAABAPsbAA==.Hexxer:BAAANQAECgYIEgABNQAECgoKGAABAPsbAA==.Hexzel:BAABNQAECn8YAAMBAAoK+xuGTwA2AgABAAoK+xuGTwA2AgAEAAEKiAM/GQAjAAAAAA==.',
Hi='Hightide:BAAANQAECggIBAAAAA==.Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECgoKPQAXAJwUAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFH8LAAIUAAMKTSQzEgA9AQAUAAMKTSQzEgA9AQA1AAQKfzQAAhQACQrBJOUDALUDABQACQrBJOUDALUDAAAA.Holywrld:BAAANQADCgQIBAAAAA==.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECn8sAAIXAAkKfhpedQCTAgAXAAkKfhpedQCTAgABNQAFFAgIFQAQAIAkAA==.Hondô:BAECNQAFFH8VAAQQAAgKgCQvAADeAgAQAAgKgCQvAADeAgAiAAIKZyBbEgC3AAACAAEKAABiLABDAAA1AAQKf2sAAxAACgrIJhEAAB0EABAACgrIJhEAAB0EAAIAAQoAAIayAGUAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUIBwABNQAFFAkJFgAaAJUVAA==.',
Hu='Huntermanjoe:BAABNQAECn8yAAISAAoK2Q03eAAfAgASAAoK2Q03eAAfAgAAAA==.Huntersdie:BAAANQADCgYICQAAAA==.Hunterzalt:BAABNQAECn82AAICAAoKtxO7JgCcAQACAAoKtxO7JgCcAQAAAA==.',
Hy='Hypatia:BAAANQADCgMIAwABNQAECgoKJwAjAHgMAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAgIFQAQAIAkAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAABNQAECn8xAAIIAAkKtR3KNwBXAgAIAAkKtR3KNwBXAgAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgQIBAAAAA==.',
Id='Idra:BAABNQAECn8wAAIHAAoKWyXfAgCwAwAHAAoKWyXfAgCwAwAAAA==.',
If='Iffa:BAAANQAECggIDgAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgcIEAAAAA==.',
Il='Illidaria:BAAANQAECgEIAQAAAA==.',
Im='Imakewhitez:BAAANQADCgcIDQAAAA==.',
Ip='Ipomoea:BAAANQAECgcICAABNQAECgoKHAAUAP4NAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgQIBAARAAAAAA==.Itsmyfault:BAAANQADCgYIFQAAAA==.',
Ja='Jackul:BAABNQAECn8jAAIPAAkK7g9QVQCbAQAPAAkK7g9QVQCbAQAAAA==.Jakilk:BAABNQAECn8eAAMQAAcKRwfmdwA6AQAQAAcKRwfmdwA6AQACAAQK6AEIrgBxAAAAAA==.Jakilky:BAABNQAECn8bAAMCAAYKDwTIjgDIAAACAAYKgAPIjgDIAAAQAAUKzgKVrACbAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQAECgIIBAAAAA==.Jaycomo:BAAANQADCggIEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECn8mAAIIAAcKOQdm6wBFAQAIAAcKOQdm6wBFAQAAAA==.',
Je='Jebuss:BAAANQAECgUIBQAAAA==.Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBgABNQAECgoKJAAQABMbAA==.Jellydead:BAABNQAECn8kAAIQAAoKExtIMABuAgAQAAoKExtIMABuAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.Jiyu:BAAANQAECgIIBQAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQAECgYICwAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwARAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIDgABNQAECgoKKwADAJwYAA==.Juggernåut:BAAANQAECgYICgAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFH8PAAITAAUKtB02CADQAQATAAUKtB02CADQAQA1AAQKfy0AAxMACgpYIqYVACIDABMACgpYIqYVACIDABgABwq5DkmOAIABAAE1AAUUBggGAAEAWRcA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECn8/AAIOAAoKXxshEgBqAgAOAAoKXxshEgBqAgABNQABCgYIDAARAAAAAA==.Kaelthuss:BAAANQAECgUIEQAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgUICgAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAABNQAECn8nAAMeAAoKmgYHMwCqAQAeAAoKmgYHMwCqAQAJAAEKAACangAhAAAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECn8pAAIKAAoKiR83MQBTAgAKAAoKiR83MQBTAgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAARAAAAAA==.',
Ko='Kobii:BAAANQAECgIIAgAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAABNQAECn8gAAIPAAoK9xOBegD0AQAPAAoK9xOBegD0AQABNQAECgoKRQACANMdAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgUIBgABNQAECgcIBwARAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ku='Kurokitsune:BAAANQAECgQIBAAAAA==.',
Ky='Kylofinn:BAABNQAECn8cAAMKAAgK1hJMbwB6AQAKAAgK1hJMbwB6AQAcAAEKAAAjMQA8AAAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAABNQAECn8vAAIkAAkK/RIvGQB1AQAkAAkK/RIvGQB1AQAAAA==.Laesandra:BAAANQAECgYIDAAAAA==.Lalaluna:BAAANQAECgMIAwAAAA==.Lalatide:BAAANQAECgYIEQAAAA==.Languish:BAAANQAECggIAwAAAA==.Lastris:BAABNQAECn8YAAMIAAkKNQoLAwEaAQAIAAcKowULAwEaAQAUAAcKVQgd0ADbAAAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgoKHAAUAP4NAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Legendrìser:BAAANQADCggICAAAAA==.Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAABNQAECn81AAIIAAoKqxdwQwAtAgAIAAoKqxdwQwAtAgAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFH8dAAIkAAgK5SVIAAAGAwAkAAgK5SVIAAAGAwA1AAQKfzsAAiQACgrtJsEAAOYDACQACgrtJsEAAOYDAAAA.Lildwarf:BAEBNQAECn8XAAIKAAgKkBaqiwD/AQAKAAgKkBaqiwD/AQABNQAECggIGAAaACQfAA==.Lillidin:BAAANQAECgEIAQAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgARAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECn8nAAIQAAkKvg/QTgDZAQAQAAkKvg/QTgDZAQAAAA==.Litebritepeg:BAAANQADCgUIBQAAAA==.Liusanjie:BAAANQADCgEIAQAAAA==.Livesoff:BAAANQAECgMIAwABNQAFFAIIBgAQAJECAA==.Lizerd:BAAANQADCgYIBgABNQAFFAMICAABAKYbAA==.',
Lo='Lochgimli:BAAANQAECgIIAwAAAA==.Lopunny:BAAANQAECgEIAQAAAA==.Louvetier:BAAANQAECgUICwAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFH8bAAQPAAgKshrpAQCDAgAPAAcKoB3pAQCDAgAVAAIKCQzHCwBOAAAWAAEKkgurHwBJAAA1AAQKfy8ABA8ACgp0JRoGAJ4DAA8ACgp0JRoGAJ4DABYABwrgG8YQAPUBABUAAQqvH8keAFEAAAAA.Lucilight:BAAANQAECgYICwAAAA==.Luckyboi:BAABNQAECn8nAAMXAAkKMBkXcACdAgAXAAkK7RYXcACdAgAFAAMKyxakJADJAAAAAA==.Luckymeoww:BAABNQAECn8qAAMQAAgK4BMoTgDcAQAQAAgK4BMoTgDcAQAiAAQKbhHQdQDLAAAAAA==.Lunargrowth:BAAANQADCgQICAAAAA==.Luurain:BAAANQAECgYICgAAAA==.',
['Lð']='Lðxic:BAAANQAECgUICgAAAA==.',
Ma='Madabardas:BAAANQADCgUIBQAAAA==.Maeveran:BAABNQAECn8pAAMkAAgKhw9hIQAvAQAIAAgKLwxhuACtAQAkAAgK7w1hIQAvAQAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIQAGAE4bAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQABCgYICwAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgIIBAAAAA==.Mangonutt:BAAANQADCggIEgAAAA==.Marpz:BAAANQAECgEIAQAAAA==.Maryjuana:BAABNQAECn8qAAIdAAkKPA5vJQADAgAdAAkKPA5vJQADAgAAAA==.Mastalys:BAEANQAECgYIBgAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECn9EAAMBAAoK0hXqVAAkAgABAAoK0hXqVAAkAgAdAAgKiRpyFQDMAQAAAA==.Mavina:BAABNQAECn9SAAQBAAoKcyHQEQA6AwABAAoKcyHQEQA6AwAdAAIKdAvkQgBxAAAEAAEKVgXyMAAiAAAAAA==.Mazez:BAABNQAECn8eAAQgAAgKfQ/CDQA5AQAgAAgK1w7CDQA5AQAfAAEKBAyuIwA3AAAhAAEKsQCuVgATAAAAAA==.',
Me='Meanmuggin:BAAANQAECgUIBwAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Megapally:BAAANQAECgIIAgAAAA==.Meitachi:BAAANQAECgcICwABNQAFFAYIEQAQAJQaAA==.Meketek:BAABNQAECn8qAAIiAAkKZhRbMwCbAQAiAAkKZhRbMwCbAQAAAA==.Melodica:BAAANQAECgUIBwAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAACNQAFFH8IAAIXAAQKRQSdJQC7AAAXAAQKRQSdJQC7AAA1AAQKf0AAAhcACgq5GSxhALwCABcACgq5GSxhALwCAAAA.Mentalist:BAAANQAECgIIAgAAAA==.Mercader:BAAANQAECgYIDgAAAA==.Merrvoid:BAABNQAECn8uAAISAAoKcRRbUAB+AgASAAoKcRRbUAB+AgAAAA==.Messîah:BAAANQAECgcIDAAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAABNQAECn8nAAIgAAkKhQesGwCQAQAgAAkKhQesGwCQAQAAAA==.Mildo:BAABNQAECn8rAAIWAAgKyBuECQBhAgAWAAgKyBuECQBhAgAAAA==.Millerlight:BAABNQAECn8UAAMXAAcKNAT/4gC8AAAXAAcKNAT/4gC8AAAFAAEKAAAqVAAbAAAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAARAAAAAA==.Minervá:BAACNQAFFH8GAAQNAAQK8AetAgB7AAANAAIKqwqtAgB7AAAbAAEKlgRMFQA7AAAOAAEKeQLOHwAyAAA1AAQKfxkABAwACQr4GWkTAMYBAAwABwqzG2kTAMYBAA0AAwqHGF0mANsAAA4AAwruEeVPALIAAAAA.Minotàurus:BAABNQAECn8fAAISAAkKFg9wXADKAQASAAkKFg9wXADKAQAAAA==.Mintonka:BAABNQAECn8cAAIYAAcK3ANbkACyAAAYAAcK3ANbkACyAAAAAA==.Miranaaster:BAABNQAECn8iAAIXAAoKTxcUWwDaAQAXAAoKTxcUWwDaAQAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAABNQAECn8iAAQaAAoKiQaPIwBGAQAaAAoKbwaPIwBGAQAZAAEK/wP3MgAqAAAGAAEKmAJaPgAbAAABNQAECgoKMAAUAJUUAA==.Mixologist:BAAANQABCgIIAgAAAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECn8vAAIOAAoKaBo/JwCaAgAOAAoKaBo/JwCaAgAAAA==.Monstershi:BAAANQAECgEIAQAAAA==.Mooarcane:BAAANQAECgUIBQAAAA==.Moonshroom:BAAANQAECgQIBgABNQAECgUIBQARAAAAAA==.Moopiehead:BAAANQADCgUIBQAAAA==.Moovina:BAAANQADCgMIAwABNQAECgoKUgABAHMhAA==.Moraien:BAABNQAFFH8FAAMWAAUKcQl1EQCNAAAWAAIKCwh1EQCNAAAPAAMK1wr9NgCCAAAAAA==.Morchanna:BAABNQAECn8kAAISAAoK2wxcfQATAgASAAoK2wxcfQATAgAAAA==.Morf:BAAANQADCgMIBAAAAA==.Morgy:BAAANQADCggICAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrae:BAAANQAECgEIAQAAAA==.Myrokorian:BAAANQADCgcIBwAAAA==.Mystichex:BAAANQAECgIIAgABNQAECgoKGAABAPsbAA==.',
['Mä']='Mäzikeen:BAABNQAECn8WAAMlAAcKoBo2FABqAQAlAAUKdx02FABqAQAJAAcKSBWfNgAvAQABNQAECgkJKwAiANEeAA==.',
Na='Nalkoa:BAAANQADCgYIBgAAAA==.Naomasa:BAAANQAECggIAgABNQAECgoKRQACANMdAA==.Natalietes:BAAANQAECgYICgAAAA==.Nattylight:BAABNQAECn8iAAMCAAcKnRF2VwCVAQACAAcKnRF2VwCVAQAQAAEKlQXw8QAlAAAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgoKJQAYALoXAA==.',
Ne='Newhealer:BAAANQAECgUIBwAAAA==.',
Ni='Nibletz:BAAANQAECggIEAAAAA==.Nightshayde:BAAANQADCggICAAAAA==.Ninelinez:BAABNQAECn8ZAAIZAAkK1iGPBwDBAgAZAAkK1iGPBwDBAgAAAA==.',
No='Nool:BAAANQADCgMIAwAAAA==.Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAABNQAECn8WAAMdAAYKEgpkQgAfAQAdAAYKEgpkQgAfAQABAAEKvhCGAQErAAABNQAECgoKHAAUAP4NAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgkJGQAZANYhAA==.',
['Nò']='Nòte:BAAANQAECgEIAwABNQAECgIJAgARAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oa='Oatmealstout:BAAANQAECgEIAQAAAA==.',
Oc='Ochana:BAABNQAECn8cAAIUAAoK/g3mQADdAQAUAAoK/g3mQADdAQAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwARAAAAAA==.',
Ol='Olayro:BAAANQADCgcIBwABNQAFFAIIBQAUAOAiAA==.Oldnote:BAAANQADCgIIAgAAAA==.Oleßigßahlz:BAAANQADCgEIAQAAAA==.Olgalina:BAAANQAECgQIBAABNQAECgkJKQAEAGUjAA==.Olorinn:BAAANQADCgQIBAAAAA==.',
Op='Opirix:BAACNQAFFH8IAAMBAAMKphvhGAD0AAABAAMKphvhGAD0AAAdAAIKiQfqDgBoAAA1AAQKfz0AAwEACgrXHkAiAOUCAAEACgrXHkAiAOUCAB0ACAquFxwoAOgBAAAA.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Paddfoot:BAAANQAECgIIAwAAAA==.Painkillerx:BAAANQADCgIIAgAAAA==.Paladrome:BAAANQAECggICQABNQAFFAIIBgAQAJECAA==.Pallycakes:BAABNQAECn8iAAIIAAkKZwb14gDbAAAIAAkKZwb14gDbAAAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Parkane:BAAANQAECgQICAAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAABNQAECn8qAAIOAAoKyA95KQB6AQAOAAoKyA95KQB6AQAAAA==.Patreszas:BAABNQAECn8oAAIgAAoKEhNGEwAbAgAgAAoKEhNGEwAbAgAAAA==.Patusk:BAAANQADCggIDgABNQAECgoKKAAgABITAA==.Pawshocker:BAABNQAECn8lAAIjAAoKVyIfCAD4AgAjAAoKVyIfCAD4AgABNQAFFAgIHQAkAOUlAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Pepperss:BAAANQAECgUICAAAAA==.Peptobismo:BAAANQAECgIIAwAAAA==.Peàches:BAAANQAECgQIDAABNQAECgcIBwARAAAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgUICwAAAA==.Piécémákér:BAAANQAECgEIAQABNQAECgIIAwARAAAAAA==.',
Po='Pohaberry:BAABNQAECn87AAISAAoKahL8WQBmAgASAAoKahL8WQBmAgAAAA==.Pokemage:BAABNQAECn8xAAIXAAoKPg9NVwDlAQAXAAoKPg9NVwDlAQAAAA==.Popedk:BAABNQAECn8lAAMQAAoKlSGuEgAiAwAQAAoKlSGuEgAiAwAiAAEKPhl5pQBCAAABNQAFFAcIDgAYADYYAA==.Popesham:BAACNQAFFH8OAAIYAAcKNhg3BwAFAgAYAAcKNhg3BwAFAgA1AAQKfxkAAhgACQqSImIUAKUCABgACQqSImIUAKUCAAAA.',
Pr='Prada:BAAANQAECgYIBwAAAA==.Prannanm:BAAANQADCgIIAgAAAA==.Priestduude:BAAANQAECgYJBgAAAA==.Product:BAAANQAECgIIAgAAAA==.',
Pu='Pullacrapton:BAABNQAECn8WAAMIAAoKuQ7huAAgAQAIAAoKSQzhuAAgAQAkAAMK6hUITgCwAAAAAA==.Puncturé:BAABNQAECn9CAAMmAAoKdwwDQgCtAQAmAAoKdwwDQgCtAQALAAIKjARLTABdAAAAAA==.Putress:BAAANQAECgIIBgAAAA==.',
Qu='Quasi:BAABNQAECn89AAIdAAoKjxqMDQBQAgAdAAoKjxqMDQBQAgAAAA==.Quiggins:BAABNQAECn9FAAIIAAkKrQmgnABTAQAIAAkKrQmgnABTAQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJIgAZAE8TAA==.Quirky:BAAANQADCgUIGwAAAA==.',
Ra='Raeziel:BAAANQAECgQIBwAAAA==.Raezor:BAAANQAECgEIAgAAAA==.Raffunn:BAAANQADCgcICQABNQAECgMIAwARAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgQICwAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAABNQAECn8VAAIXAAcK6RZoEgFuAQAXAAcK6RZoEgFuAQABNQAFFAQIDQAiAPshAA==.Reignz:BAABNQAECn8bAAMlAAUKgQV+HAB9AAAlAAUKgQV+HAB9AAAeAAEK2gFbVQAVAAAAAA==.Reinhardt:BAABNQAECn80AAMkAAoKVh15CQAGAwAkAAoKVh15CQAGAwAIAAcKIhJSzgB/AQAAAA==.Reticular:BAABNQAECn8iAAMkAAgKjxIqJQASAQAkAAgKjxIqJQASAQAIAAMKQAkEQAFdAAAAAA==.',
Rh='Rhaenne:BAAANQAECgUIDAAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcIDQAAAA==.',
Ru='Rubonyx:BAABNQAECn8pAAQEAAkKZSMFAQAeAwAEAAkKZSMFAQAeAwAdAAMKgB3sTADhAAABAAIKqwZP7wBWAAAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECn8WAAILAAcKXwiHUwBuAQALAAcKXwiHUwBuAQAAAA==.Ryoko:BAAANQAECggIEAAAAA==.Ryuzin:BAABNQAECn8eAAIOAAgKMhBcRwDPAQAOAAgKMhBcRwDPAQAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAwABNQAECgMIAwARAAAAAA==.',
Sa='Sagerin:BAABNQAECn8nAAIQAAkKERObHgC6AQAQAAkKERObHgC6AQAAAA==.Sageslife:BAAANQAECgcIEwAAAA==.Saintofthetp:BAAANQAECgYICQAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Screamodevo:BAAANQAECgEIAwAAAA==.Scronk:BAAANQADCgcIBwABNQAECgYIDAARAAAAAA==.Scruffmcgruf:BAABNQAECn8kAAIBAAkKQxA2bwDQAQABAAkKQxA2bwDQAQAAAA==.Scubany:BAAANQADCgIJAgAAAA==.Scyl:BAAANQADCgIIAgABNQAECgcIBwARAAAAAA==.',
Se='Senadora:BAABNQAECn8cAAIaAAgKoRpEIQAiAgAaAAgKoRpEIQAiAgAAAA==.Sergrahm:BAAANQADCgYIDwAAAA==.Sezeth:BAABNQAECn8UAAMiAAkK2Bh1MAAiAgAiAAkKKRh1MAAiAgAQAAYKJA/CewAtAQAAAA==.',
Sh='Shaboomboom:BAACNQAFFH8FAAIYAAIKHRRxIgCjAAAYAAIKHRRxIgCjAAA1AAQKfyoAAhgACgonG+ktAMUCABgACgonG+ktAMUCAAAA.Shadowglaive:BAABNQAECn85AAIeAAoK7iLkCQA6AwAeAAoK7iLkCQA6AwAAAA==.Shadownight:BAABNQAECn8iAAIQAAgKTyOJFgAHAwAQAAgKTyOJFgAHAwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Shanice:BAAANQADCgMIAwAAAA==.Sharburst:BAAANQAECggIDwAAAA==.Sharleet:BAAANQAECggIBwAAAA==.Sharlocke:BAAANQAECgYIBgAAAA==.Sharwar:BAAANQAECggIBQAAAA==.Shaval:BAABNQAECn+lAQIIAAkK/SZdAAAPBAAIAAkK/SZdAAAPBAAAAA==.Shawman:BAAANQAECggIEAAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFH8KAAMKAAQK/hCuHQAjAQAKAAQKUg6uHQAjAQAcAAIK8g2KAwCPAAA1AAQKfykAAwoACgpZG6hjAGMCAAoACgoMG6hjAGMCABwAAwqtG6UaAPsAAAAA.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgYIEgAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCggIDQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECn8iAAIZAAkKTxMWDgAVAgAZAAkKTxMWDgAVAgAAAA==.Shøøtingstar:BAAANQAECgUICQABNQAECgkJKwAiANEeAA==.',
Si='Signet:BAABNQAECn8rAAITAAgKtB7HJwBcAgATAAgKtB7HJwBcAgAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgUIBgAAAA==.Skerrit:BAAANQAECgYIBgAAAA==.Skoss:BAABNQAECn8rAAMPAAkK3xSSTAC3AQAPAAkK3xSSTAC3AQAWAAIKxw6MWgBxAAAAAA==.Skullshine:BAACNQAFFH8fAAQQAAcKWCAmBQDUAQAQAAUKZyEmBQDUAQAiAAMK3RM3EACiAAACAAEKAACyNgAlAAA1AAQKfysAAxAACgqtJX0OAEQDABAACQoIJX0OAEQDACIAAwoYJJJIADUBAAAA.Skunkie:BAABNQAECn8hAAMTAAoKmBLQZwDVAQATAAoKmBLQZwDVAQAYAAEK1hjxJQFGAAAAAA==.Skwiish:BAAANQAECgQIBAABNQAECgoKJQAYALoXAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDAAAAA==.Slickfifty:BAAANQAECgUIEAAAAA==.Slippewy:BAAANQAECgMIBAAAAA==.Sluewt:BAABNQAECn8hAAMIAAoKfQpIwACcAQAIAAkKsgtIwACcAQAUAAgKjA3yuQAJAQABNQAECgoKQAABAOIjAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smileysabear:BAAANQAECgQIBAABNQAECgkJIgAiAOoMAA==.Smolderr:BAABNQAECn8oAAISAAkKVwbBtwCUAQASAAkKVwbBtwCUAQAAAA==.',
Sn='Snakebite:BAAANQADCgEIAQAAAA==.Snakesshaman:BAAANQAECgQIBAAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spacecadet:BAAANQAECgYIDQAAAA==.Spaciousyeti:BAABNQAECn8jAAIiAAoKlBe4JQDtAQAiAAoKlBe4JQDtAQAAAA==.Spearowhunt:BAAANQAECggICwAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQAECgIIAgAAAA==.Spook:BAAANQADCggICQAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECn8rAAQiAAkK0R48GgC5AgAiAAkKHx08GgC5AgACAAYKcxC8eQARAQAQAAMKOBT6nADEAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECggIEQAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stun:BAAANQAECgIIAgAAAA==.Stunllub:BAAANQAECggIDgAAAA==.',
Su='Suggs:BAACNQAFFH8QAAQPAAYKfhibEgDmAAAPAAQKlRybEgDmAAAWAAEKOAw2HgBLAAAVAAEKAADZDgBHAAA1AAQKfygABA8ACgptIWY2ALECAA8ACQoxIWY2ALECABUAAwpcHtAXAM4AABYAAgqrGzNTAIUAAAAA.Superali:BAAANQADCgIIAgAAAA==.Supergoten:BAAANQAECgIIAwAAAA==.Surnaturelle:BAAANQAECgEIAQABNQAECgoKJwAjAHgMAA==.',
Sw='Swiiani:BAABNQAECn8ZAAIYAAcKIghUgADWAAAYAAcKIghUgADWAAAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECggIEwAAAA==.Sylvànis:BAAANQAECgEIAwABNQAECggICgARAAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQARAAAAAA==.',
Ta='Taelinn:BAAANQADCggICwABNQAECgoKKAAgABITAA==.Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECgcIDAAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAZAE8TAA==.Taurelai:BAAANQABCggIDgAAAA==.Tauriko:BAACNQAFFH8LAAIIAAQKggywGwDKAAAIAAQKggywGwDKAAA1AAQKfzYAAggACgo6Hsk7AEgCAAgACgo6Hsk7AEgCAAAA.Tayvos:BAABNQAECn8ZAAQEAAkKtgWyGACqAAABAAgKTAMalQDiAAAEAAYKIQayGACqAAAdAAEKAADSkwAUAAAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAABNQAECn8sAAQQAAkK2hUgPgAmAgAQAAkK2hUgPgAmAgAiAAkKOAvYOQB6AQACAAEKoBX5wgBCAAAAAA==.',
Th='Thebestlorax:BAABNQAECn8aAAIMAAoKNiEiBgDPAgAMAAoKNiEiBgDPAgABNQAECgkJIgAZAE8TAA==.Thejonesyy:BAAANQADCgcICwAAAA==.Theler:BAAANQAECgMIAwABNQAFFAcIDgAPAEYXAA==.Theradestria:BAAANQAECgUIDgAAAA==.Thestigg:BAABNQAECn8qAAIIAAkKiw2cmQBZAQAIAAkKiw2cmQBZAQAAAA==.Thighighs:BAAANQAECgIIAgABNQAFFAYIEAAIAFEaAA==.Thndrdwnundr:BAAANQADCgEIAQAAAA==.Thundersloot:BAAANQAECgQIBQABNQAECgoKIAAUAKgUAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAABNQAECn8fAAMWAAgKLAhaLgARAQAPAAYKOgg6zgAtAQAWAAYKvQVaLgARAQAAAA==.',
To='Toedumbz:BAABNQAECn8YAAIYAAgK4BJpewCxAQAYAAgK4BJpewCxAQAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.Tomoee:BAAANQAECggICgAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQAECgcICwAAAA==.Troflgar:BAAANQAECgcICwAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgcICAABNQAECgoKKwADAJwYAA==.',
Ts='Tsuky:BAAANQAECgcIEgAAAA==.Tsukytank:BAAANQAECgEIAgAAAA==.Tsumikui:BAACNQAFFH8JAAIPAAMK2AhCFgDIAAAPAAMK2AhCFgDIAAA1AAQKfz0ABBYACgqNFFwMADECABYACAqQD1wMADECAA8ACgprE+U7APIBABUACAo3DcEJAOMBAAAA.',
Ty='Tyinastor:BAAANQAECgQICgAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAABNQAECn8aAAMbAAoKPhZzJAABAgAbAAoKPhZzJAABAgANAAQKmQucMgBTAAAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Um='Umila:BAAANQAECgEIAQAAAA==.',
Un='Unalived:BAABNQAECn89AAIXAAoKnBS/SwAFAgAXAAoKnBS/SwAFAgAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAABNQAECn8VAAIFAAkK0Qf1GgAbAQAFAAkK0Qf1GgAbAQAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQAECgQIBAAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Vanillia:BAAANQAECggIDwAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAABNQAECn8YAAIcAAkKFAeAFgA0AQAcAAkKFAeAFgA0AQAAAA==.Varíann:BAAANQADCggIDAAAAA==.',
Ve='Velro:BAAANQAECggIDwAAAA==.Vemmox:BAABNQAECn8cAAIXAAoK5hDy4ADHAQAXAAoK5hDy4ADHAQAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQAECgMIAwAAAA==.Venefica:BAAANQAECgQIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Veroks:BAAANQADCgUIDQABNQAECggIDwARAAAAAA==.Vesemir:BAABNQAECn82AAIeAAkKpRJPGQCxAQAeAAkKpRJPGQCxAQAAAA==.',
Vh='Vhpsv:BAAANQAECggICgAAAA==.',
Vi='Vianir:BAABNQAECn8hAAIIAAoKkg+AqADPAQAIAAoKkg+AqADPAQAAAA==.Vilefox:BAAANQAECgEIAQAAAA==.Vindictive:BAABNQAECn8cAAIPAAoKVQaeDgGuAAAPAAoKVQaeDgGuAAAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgYICAAAAA==.',
['Vë']='Vësper:BAAANQAECgIIAgAAAA==.',
Wa='Wads:BAAANQAECggIDwAAAA==.Warscared:BAABNQAECn8UAAIKAAgKJQTA2wA1AQAKAAgKJQTA2wA1AQAAAA==.Wasabis:BAABNQAECn86AAIYAAoKtgr7WABBAQAYAAoKtgr7WABBAQAAAA==.',
We='Wels:BAABNQAECn9AAAIBAAoK4iMjBADcAwABAAoK4iMjBADcAwAAAA==.',
Wh='Whichwitch:BAAANQAECgEIAQAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAABNQAECn8VAAIYAAcKbBW2egCzAQAYAAcKbBW2egCzAQAAAA==.',
Wi='Wigglypuffsr:BAABNQAECn8tAAIIAAkKUh95PABGAgAIAAkKUh95PABGAgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECn85AAIXAAoKdx41IQCgAgAXAAoKdx41IQCgAgAAAA==.Winddrake:BAABNQAECn8ZAAISAAoKRhFKogDBAQASAAoKRhFKogDBAQAAAA==.Windstorm:BAAANQADCgMIAwAAAA==.Wixania:BAAANQAECgYICwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAABNQAECn8ZAAMPAAkKHAmqeQA4AQAPAAkKFAeqeQA4AQAWAAEKqBBmMAA4AAAAAA==.Xanneste:BAABNQAECn8zAAIJAAoKaA4MIwC2AQAJAAoKaA4MIwC2AQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xc='Xcenturion:BAAANQADCgUICQAAAA==.',
Xe='Xecutioner:BAAANQAECgMIAwAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xk='Xkatarina:BAAANQAECgIIAQAAAA==.',
Xt='Xtremeheals:BAAANQADCgYIBgABNQAECgoKFgAIALkOAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQAECgMIAwAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.Yanelaru:BAAANQAECgEIAwAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yo='Yoshiyokai:BAAANQAECggIBwAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAcAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAABNQAECn8VAAIJAAkKJBkLOQDqAQAJAAkKJBkLOQDqAQABNQAFFAQIDQAiAPshAA==.',
['Yâ']='Yâtiri:BAAANQAECgMIAwAAAA==.',
Za='Zaebos:BAAANQAECgUICAAAAA==.Zakwa:BAAANQAECggICwAAAA==.Zalfanso:BAEANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQABCgQIBAAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggIDAAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAABNQAECn8rAAIHAAoKPw+rEgDfAQAHAAoKPw+rEgDfAQAAAA==.',
Zi='Ziralila:BAABNQAECn8sAAISAAkKIwgAuACUAQASAAkKIwgAuACUAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAABNQAECn8VAAIKAAcKwhExqAC4AQAKAAcKwhExqAC4AQAAAA==.',
Zu='Zuglybob:BAAANQADCgUIBwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Ño']='Ñote:BAAANQADCgYIBgABNQAECgIJAgARAAAAAA==.',
['Óm']='Ómèn:BAAANQAECgcIDQABNQAECgkJFgAIANkYAA==.',
['Ör']='Örin:BAACNQAFFH8JAAMLAAMKbiDaAgAgAQALAAMKbiDaAgAgAQAnAAEKxg2zAwBIAAA1AAQKf0IABAsACgpqJMkCAA0DAAsACgr0I8kCAA0DACcACApNH3IEAMgCACYAAQqMBjC8ADYAAAAA.',
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
