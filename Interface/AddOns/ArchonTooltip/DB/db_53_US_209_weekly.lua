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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Evoker-Preservation','Warlock-Demonology','Warlock-Affliction','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Rogue-Assassination','Hunter-Survival','Druid-Feral','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Monk-Brewmaster','Monk-Mistweaver',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aassvik:BAABNQAECn82AAIBAAkKfB9wKQCSAgABAAkKfB9wKQCSAgAAAA==.',
Ab='Absolute:BAACNQAFFH8YAAICAAcKICVZAQDqAQACAAcKICVZAQDqAQA1AAQKfzYAAgIACgpVJiUBAHQDAAIACgpVJiUBAHQDAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8TAAMDAAgKvxpTCQDqAQADAAgKvxpTCQDqAQAEAAEK1AA1GQAwAAA1AAQKfz8ABAMACgrsJToDAFkDAAMACgrsJToDAFkDAAQABgp/EIU7AEQBAAUAAQoAALxtACAAAAAA.Achievsome:BAABNQAECn9DAAQGAAoKBCWuAwCfAwAGAAoKBCWuAwCfAwABAAcKthUaiQB7AQAHAAMKIxFbDwCBAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesodx:BAAANQAECgcICAABNQAECgoKHQAIAAEZAA==.Aesomx:BAAANQAECgIIAQABNQAECgoKHQAIAAEZAA==.Aesoxp:BAAANQAECggIEQABNQAECgoKHQAIAAEZAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgoKHQAJAHMRAA==.',
Ah='Ahjbastet:BAAANQAECgYIBQAAAA==.Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgcICwAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAABNQAECn8UAAIKAAgKxgkqDgBlAQAKAAgKxgkqDgBlAQAAAA==.Algas:BAAANQAECgIIAQAAAA==.Aliengrey:BAABNQAECn8XAAILAAcKAxQCtwCWAQALAAcKAxQCtwCWAQAAAA==.Alindrin:BAAANQABCgIIAgAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8tAAIMAAoKjBMTcwBIAgAMAAoKjBMTcwBIAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECgMIAwAAAA==.',
Am='Amane:BAABNQAECn89AAMNAAgK1CLSBgCnAgANAAgK1CLSBgCnAgAOAAgKXRr2NwDxAQAAAA==.American:BAAANQAECgMIAwAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQADCggIDQAAAA==.',
An='Anger:BAAANQADCggIDQAAAA==.Angryfyne:BAAANQAECggICAAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hXGUgArAgABAAgK4hXGUgArAgAGAAYKyQoSQwAbAQAAAA==.Anowon:BAAANQAECggIAQABNQAECggICAAPAAAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgoKMwAEAOYkAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgoKJAAMAOMLAA==.Arkanis:BAABNQAECn9KAAIQAAoKsRjqBQBcAgAQAAoKsRjqBQBcAgAAAA==.Arkherym:BAAANQAECgIIAgAAAA==.Armament:BAABNQAECn89AAIRAAoK/BaHXAB2AgARAAoK/BaHXAB2AgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggIEAABNQAECgcICAAPAAAAAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn9WAAILAAoKRCTFBwBHAwALAAoKRCTFBwBHAwAAAA==.Aurius:BAAANQAECggIEAAAAA==.',
Av='Avalancha:BAABNQAECn8wAAIFAAkKyRcYFQAWAgAFAAkKyRcYFQAWAgAAAA==.Avinoch:BAABNQAECn8kAAIFAAcK9ggJOQDMAAAFAAcK9ggJOQDMAAAAAA==.',
Ax='Axon:BAAANQAECggIEAAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAPAAAAAA==.',
Az='Azekor:BAAANQADCggIEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIIAAgKDhoFQwAPAgAIAAgKDhoFQwAPAgAAAA==.',
Ba='Babykay:BAAANQADCgUIDQABNQAECgoKOgASAOAeAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAABNQAECn8YAAITAAkKrA1bFQBSAQATAAkKrA1bFQBSAQAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAPAAAAAA==.Bartholomäus:BAAANQAECgYIBgAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAABNQAECn8gAAIRAAoKVgvBagCrAQARAAoKVgvBagCrAQAAAA==.',
Be='Beezlebumon:BAABNQAECn87AAMIAAkKWxeXGQAIAgAIAAkKWxeXGQAIAgAUAAIKZgsingAxAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgUIBAAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgYIBQAAAA==.Bewater:BAABNQAECn8xAAILAAkKyhgWWAADAgALAAkKyhgWWAADAgAAAA==.',
Bl='Blegh:BAABNQAFFH8HAAMLAAQKYQrtFQDTAAALAAQK9QntFQDTAAAVAAIKvQSoFwB0AAAAAA==.Bluberry:BAAANQADCgcIHgAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8lAAIIAAoKVB/JEQBeAgAIAAoKVB/JEQBeAgAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECn9BAAMWAAoK6B0mKgC7AgAWAAoK6B0mKgC7AgASAAYKGw5hjwDWAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8UAAIBAAUKZx9QCwDXAQABAAUKZx9QCwDXAQA1AAQKfzwAAwEACgo6ImQdAPwCAAEACgo6ImQdAPwCAAYABQq6GX0yAOMAAAAA.',
Br='Bracknor:BAABNQAECn8dAAILAAgKKhF8fAAVAgALAAgKKhF8fAAVAgAAAA==.Brandonb:BAABNQAECn9gAAIXAAoKqSLtHwBaAwAXAAoKqSLtHwBaAwAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECggIEQABNQAFFAYIFgALAFIaAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn8uAAIYAAoKkh8jBgDFAgAYAAoKkh8jBgDFAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECggIEQAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.Brynnbramble:BAAANQADCggIDwAAAA==.',
By='Bysokar:BAABNQAECn8rAAIZAAoKcBs4FQCqAgAZAAoKcBs4FQCqAgAAAA==.',
Ca='Cainfortea:BAAANQAECgUICAAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Cakevoid:BAAANQAECgcICwAAAA==.Calipal:BAABNQAECn8fAAIMAAcKtwd99QDkAAAMAAcKtwd99QDkAAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAABNQAECn8hAAIBAAoKyh3TFAAfAwABAAoKyh3TFAAfAwABNQAFFAcKCwAWAKYUAA==.Catalinasham:BAACNQAFFH8LAAIWAAcKphRBDgBpAQAWAAcKphRBDgBpAQA1AAQKfzMAAhYACgrRI2gHAJUDABYACgrRI2gHAJUDAAE1AAUUBwoLABYAphQA.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAgAAAA==.Cerberusbone:BAABNQAECn8aAAMUAAoKfBB+LwCDAQAUAAkKmA9+LwCDAQAIAAYKxQxsfgAjAQAAAA==.',
Ch='Challengerz:BAAANQAECgYIDwAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIEAAAAA==.Chritiane:BAAANQAECgUIBQAAAA==.',
Ci='Cinderlily:BAABNQAECn8iAAMaAAcKMBk2EgDBAQAaAAcKMBk2EgDBAQAKAAQK/gVXGwCPAAAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAPAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8PAAMJAAQKZBmeBwB6AAAbAAQKmxWsGQAoAQAJAAIKZwyeBwB6AAA1AAQKfygABBsACgqbIu8ZAB8DABsACgqnIe8ZAB8DAAkAAwq3HuoSALYAABwAAQoAAKknAE0AAAAA.Connery:BAAANQADCgYIKAAAAA==.Cornpopp:BAAANQADCgYIGAAAAA==.Coryuchiha:BAAANQAECgMIAwAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crippleya:BAAANQAECgEIAQAAAA==.Crithappens:BAAANQAECgUIBQAAAA==.Criturrpants:BAABNQAECn8UAAMQAAcKCxXzFQA8AQAQAAYKGxbzFQA8AQATAAEKzRCLPQA6AAAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAIXAAkKlRhUWgDLAgAXAAkKlRhUWgDLAgAAAA==.Cynthea:BAAANQAECgcICwAAAA==.Cyp:BAABNQAECn9KAAIRAAoK5xlqOABQAgARAAoK5xlqOABQAgAAAA==.',
['Cü']='Cüpcake:BAABNQAECn8kAAIOAAoK8wt5KwCeAQAOAAoK8wt5KwCeAQAAAA==.',
Da='Dababycar:BAABNQAECn8WAAMdAAgKVRMshACOAQAdAAcK/REshACOAQAMAAYKUQ3a3AANAQAAAA==.Dabbyduck:BAABNQAECn8iAAMbAAkK7BmONAC4AgAbAAkK7BmONAC4AgAJAAcKLg4fGQCjAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgUIBgAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQADCggIDQAAAA==.',
De='Deadincide:BAEBNQAECn89AAMIAAoKwhMbQgATAgAIAAkKsRMbQgATAgAeAAkKbg5sMQDNAQAAAA==.Deadstasheo:BAACNQAFFH8WAAIIAAUK0RuWAgBoAQAIAAUK0RuWAgBoAQA1AAQKfykAAggACgpyI5YYAPoCAAgACgpyI5YYAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn87AAIMAAoKXRdjTwAtAgAMAAoKXRdjTwAtAgAAAA==.Deezmonz:BAABNQAECn8dAAMJAAoKcxHpFQCjAAAbAAoKuxAjbQB8AQAJAAMKaxDpFQCjAAAAAA==.Delik:BAABNQAECn8wAAIfAAkKKRaNCQA6AgAfAAkKKRaNCQA6AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgQIAwAAAA==.Deneol:BAABNQAECn8nAAMGAAoKShofEQDoAgAGAAoKShofEQDoAgAHAAEK3BG+JwA3AAAAAA==.Destrogen:BAACNQAFFH8KAAMcAAQK5hptAgDzAAAcAAQKABZtAgDzAAAbAAEKTB5gLQBZAAA1AAQKf0AABBwACgpuIu8AACcDABwACgpuIu8AACcDABsABArODSv2AN8AAAkAAgqkDQFcAG4AAAAA.Desìre:BAABNQAECn8vAAMHAAkKzR40AwDJAgAHAAgKfx80AwDJAgABAAMKIRryoQDgAAAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECgcICAAPAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECn8zAAIIAAoKFx9UDgCKAgAIAAoKFx9UDgCKAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgUIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECggIEwAPAAAAAA==.Doomwing:BAAANQADCgYIBgAAAA==.',
Dr='Dracodeez:BAABNQAECn8gAAIgAAoKlhxgBwB0AgAgAAoKlhxgBwB0AgAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECn8tAAMIAAoKHSCCDgBEAwAIAAoKHSCCDgBEAwAUAAQKZBcXjwDHAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Dundaz:BAAANQAECgQIBAAAAA==.Durunk:BAABNQAECn8XAAIWAAYKZwrvogDEAAAWAAYKZwrvogDEAAAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAABNQAECn8aAAIZAAgKghHhMACQAQAZAAgKghHhMACQAQAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIGgAZAIIRAA==.',
Ec='Eclipcees:BAAANQADCgQIAwAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQADCgUIDgAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgUIFgAeAHgPAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgcIDQABNQAECgoKIQAWAJ0ZAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8pAAMLAAgKuBY3nQDMAQALAAgKuBY3nQDMAQAhAAIKqRPZEQBDAAAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECgkKPAAVAHcNAA==.',
Es='Eszran:BAABNQAECn8jAAIiAAoKkhMjDADyAQAiAAoKkhMjDADyAQAAAA==.',
Eu='Euthanized:BAAANQAECgIIBwAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn9BAAIUAAoKxh9aEgAaAwAUAAoKxh9aEgAaAwABNQAECgMIAwAPAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAYIFAAGAEwQAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAABNQAECn8aAAITAAkKIiVLBQCyAgATAAkKIiVLBQCyAgAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAABNQAECn8XAAIfAAkKGAg1FAA0AQAfAAkKGAg1FAA0AQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAABNQAECn8fAAIBAAkKSgqYbAB/AQABAAkKSgqYbAB/AQAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn9FAAMVAAoKNhzIGwCLAQAVAAoKexTIGwCLAQALAAYKyx0ypgBKAQAAAA==.Frearyne:BAABNQAECn8zAAIEAAoK5iRUAgCpAwAEAAoK5iRUAgCpAwAAAA==.Frinu:BAAANQAECgQIBQABNQABCgIIAgAPAAAAAA==.Frogs:BAAANQADCggIKwAAAA==.Frostyshadow:BAABNQAECn8rAAIXAAkKESHGHABkAwAXAAkKESHGHABkAwAAAA==.Frozatresh:BAAANQAECgEIAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIZAAkKzBUdIwAOAgAZAAkKzBUdIwAOAgAAAA==.',
Fy='Fyxxer:BAAANQADCgIIAgABNQAFFAYIFAAGAEwQAA==.Fyxxie:BAACNQAFFH8UAAIGAAYKTBCiBgAfAQAGAAYKTBCiBgAfAQA1AAQKfzYAAwYACgo+HmQVALUCAAYACgo+HmQVALUCAAcAAQrYHm0hAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Gi='Gialiana:BAABNQAECn8sAAIVAAoKOBakIABUAQAVAAoKOBakIABUAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAcIGAACACAlAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8fAAIQAAYKzR11DAD0AQAQAAYKzR11DAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.Grully:BAABNQAECn8qAAIWAAoKgQwfZwDXAQAWAAoKgQwfZwDXAQAAAA==.',
Gu='Gurt:BAABNQAECn8eAAMcAAkKaRBSBwDfAQAcAAkKaRBSBwDfAQAJAAMKXAVKUACPAAAAAA==.Guzzug:BAABNQAECn9NAAIRAAoKKiH7HQDFAgARAAoKKiH7HQDFAgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8rAAICAAkKZht8GgCFAgACAAkKZht8GgCFAgAAAA==.Hailsbelle:BAABNQAECn8mAAIOAAoKDQgiOABNAQAOAAoKDQgiOABNAQAAAA==.Harleymama:BAAANQABCgIIAgAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8xAAIgAAkKXxeaLQAvAgAgAAkKXxeaLQAvAgAAAA==.Helado:BAAANQAECgUIDQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highertotem:BAAANQADCgUIBAABNQAECgEIAQAPAAAAAA==.Highwayman:BAAANQAECgUICgABNQAECgoKYAALAHQkAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQAECgcIBwAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAABNQAECn8lAAIMAAcK0BIcyQAtAQAMAAcK0BIcyQAtAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIHAAAAA==.Ievil:BAABNQAECn8yAAMIAAoKxwtWKgB+AQAIAAoKxwtWKgB+AQAUAAEKAABK3QAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgoKWAAOABQkAA==.',
Im='Imjustpika:BAACNQAFFH8TAAIhAAcKgw5XAAAdAgAhAAcKgw5XAAAdAgA1AAQKfyoAAiEACgp9HPwEAH8CACEACgp9HPwEAH8CAAAA.',
In='Inawee:BAABNQAECn9MAAIEAAoK4h7SDgDnAgAEAAoK4h7SDgDnAgAAAA==.Inferniö:BAACNQAFFH8WAAMXAAcKBCDuCAA5AgAXAAYKth7uCAA5AgAfAAEKPSXCCQBtAAA1AAQKf00AAxcACgpEJR0QAJIDABcACgrkJB0QAJIDAB8AAQqwIqEuAGMAAAAA.Inkurushio:BAAANQAECgMIBAAAAA==.Inshallah:BAAANQAECgMIAwABNQAECgoKHQAIAAEZAA==.Intothefray:BAAANQADCgUIDgAAAA==.',
Io='Iolanie:BAAANQAECgMIAwABNQAECgcIBwAPAAAAAA==.',
Is='Ismat:BAABNQAECn9gAAIWAAoKIhDBSgDQAQAWAAoKIhDBSgDQAQAAAA==.',
Ja='Jaeza:BAAANQADCggIKQABNQAECgYICgAPAAAAAA==.Jaqu:BAAANQAECgEIAQAAAA==.Jarshh:BAABNQAECn8eAAIQAAkKuB0SBwAzAgAQAAkKuB0SBwAzAgAAAA==.Jaycinth:BAAANQAECgcIBwAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgIIAgAAAA==.',
Ju='Judge:BAABNQAECn80AAQjAAoKKh8OCgCGAgAjAAkKfiAOCgCGAgAdAAMKSwSR/QCBAAAMAAMKVBC5dgFmAAABNQAECgMIAwAPAAAAAA==.Juura:BAABNQAECn80AAMJAAoKNhEHBgBwAQAJAAkKJBIHBgBwAQAbAAgK3g3leQBbAQAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8nAAIdAAoKfh+YDgA/AwAdAAoKfh+YDgA/AwAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAABNQAECn8cAAIkAAoK6hFFGAAaAgAkAAoK6hFFGAAaAgAAAA==.Kaveros:BAABNQAECn8dAAMlAAgKoRg4BwBIAgAlAAcKHhs4BwBIAgAkAAYK4hDDbABDAQAAAA==.',
Ke='Kelaan:BAABNQAECn8xAAMjAAoKJiMwBAAcAwAjAAoKJiMwBAAcAwAMAAEKAAAuoQE2AAAAAA==.Kelimao:BAABNQAECn8aAAMDAAkKyQcNOwAuAQADAAkKyQcNOwAuAQAEAAEKmQmSbwAzAAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Kiritos:BAABNQAECn8rAAIEAAoKZh/aCgAJAwAEAAoKZh/aCgAJAwAAAA==.Kiserys:BAABNQAECn8dAAMmAAcKJhAeGgCnAQAmAAcKJhAeGgCnAQAaAAQK/xHWNQDlAAAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Koombah:BAAANQADCgQIBAAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECn8tAAILAAkK7woekADpAQALAAkK7woekADpAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUICwAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
Ky='Kyllista:BAAANQADCggIEQAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Laquisha:BAAANQAECgEIAQAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.Lepershaun:BAAANQADCgYIBgABNQAECgkJMQAQAMEVAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilatharia:BAAANQABCgIIAgAAAA==.Lilbowar:BAAANQAECgEIAQAAAA==.Lillath:BAAANQABCgQIBgAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECn9mAAMMAAoKnyJYHwBGAwAMAAoKOiJYHwBGAwAjAAUKOiE0IQBOAQAAAA==.Lorenth:BAABNQAECn8eAAIBAAkKTQaPfQBIAQABAAkKTQaPfQBIAQAAAA==.Lorgoza:BAAANQAECgQIBAAAAA==.',
Lu='Lucerza:BAAANQAECgEIAQABNQAECgoKIgAOAGsWAA==.Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
Lv='Lvcky:BAAANQAECgMIAwAAAA==.',
['Lì']='Lìte:BAABNQAECn8lAAICAAkKQw2zJQBXAQACAAkKQw2zJQBXAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn8/AAMkAAoKHQsnUACmAQAkAAoKHQsnUACmAQAgAAEKhgd1ZwAsAAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAAUAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwAXABEhAA==.Malidros:BAAANQAECgYIDwABNQAECgcICAAPAAAAAA==.Malign:BAABNQAECn8sAAMgAAoKQCOtAwCcAwAgAAkKiSOtAwCcAwAkAAkKByLRBwA3AwABNQAFFAcIGAACACAlAA==.Manhatten:BAAANQAECgQIBQAAAA==.Marhault:BAABNQAECn9gAAMLAAoKdCQNBgBYAwALAAoKcSQNBgBYAwAhAAUKbR9MCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAIUAAkK7RvZJACTAgAUAAkK7RvZJACTAgAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8bAAIMAAcKqQ+b2ABqAQAMAAcKqQ+b2ABqAQAAAA==.Mazah:BAABNQAECn9YAAMSAAoKmhhrKAAuAgASAAoKmhhrKAAuAgAWAAoKpBFSOQAdAgAAAA==.Mazlo:BAACNQAFFH8GAAIfAAQKBBJJCACXAAAfAAQKBBJJCACXAAA1AAQKf1EAAx8ACgp/IF0DAMECAB8ACgp/IF0DAMECABcAAgrrAP3DATgAAAAA.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgoKHQAJAHMRAA==.Mellethir:BAABNQAECn83AAMXAAoKfQpv5gC9AQAXAAoK5Qlv5gC9AQAfAAQKKAq4JACjAAAAAA==.Messalina:BAAANQAECgcICAAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECggIDgAAAA==.Minipimp:BAAANQADCgcIGQAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAABNQAECn8gAAIEAAcKfBNHKwB4AQAEAAcKfBNHKwB4AQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8tAAILAAoK8h95LQB9AgALAAoK8h95LQB9AgAAAA==.Moglayn:BAABNQAECn9RAAIUAAoKvyXpAQDWAwAUAAoKvyXpAQDWAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAInAAQKWQ1uBgD4AAAnAAQKWQ1uBgD4AAA1AAQKfxsAAicACQpOGnENACQCACcACQpOGnENACQCAAE1AAUUBwgRABQAKg4A.Monorìth:BAEBNQAFFH8RAAIUAAcKKg5uDgBtAQAUAAcKKg5uDgBtAQAAAA==.Morninstar:BAAANQADCgMIAwAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgQIBAAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgoKPwAkAB0LAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIEQABNQABCggIFgAPAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAABNQAECn8WAAIiAAYKvxL8HQAsAQAiAAYKvxL8HQAsAQAAAA==.Nastyiam:BAACNQAFFH8OAAIYAAQKHAY+BADLAAAYAAQKHAY+BADLAAA1AAQKf0MAAhgACgruFRYMAEUCABgACgruFRYMAEUCAAAA.',
Ne='Nerfornothin:BAABNQAECn8nAAILAAkKuwZumgBjAQALAAkKuwZumgBjAQAAAA==.Nethbubble:BAAANQAECgEIAQABNQAFFAMIBgAaAP4FAA==.Nethflap:BAACNQAFFH8GAAIaAAMK/gUGEACyAAAaAAMK/gUGEACyAAA1AAQKfy8AAhoACgpSEDwbABQCABoACgpSEDwbABQCAAAA.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQAECgQIBAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Nights:BAAANQABCgIIAgAAAA==.Niik:BAABNQAECn8qAAIWAAoKkRpKMQCcAgAWAAoKkRpKMQCcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAACNQAFFH8IAAIYAAMKSxcgAwDwAAAYAAMKSxcgAwDwAAA1AAQKf0AAAhgACgqYJL8BAJwDABgACgqYJL8BAJwDAAAA.',
Ny='Nycterine:BAAANQAECgYIBgABNQAECggIGgAfAK0XAA==.Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgUICAAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.',
Os='Osanyin:BAAANQADCgQIBAABNQAECgcICAAPAAAAAA==.',
Ou='Outstanding:BAAANQAECgUIBgABNQAECgkJNgABAHwfAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAABNQAECn8VAAMeAAoKWh3dFwB8AgAeAAoKWh3dFwB8AgAUAAEKVBA1mgA2AAAAAA==.Perfections:BAAANQADCgQIBgAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgMIAwAAAA==.Pikagosa:BAAANQAECgIIAgABNQAFFAcIEwAhAIMOAA==.Pilgor:BAABNQAECn8fAAMKAAoKfQ+aDACKAQAKAAkKXg6aDACKAQAaAAoKqgYYFgB6AQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAPAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQIDwAAAA==.Polkovnik:BAABNQAECn8fAAIRAAkKVRvFZQBeAgARAAkKVRvFZQBeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEBNQAECn8lAAIXAAkKKQUcqQA/AQAXAAkKKQUcqQA/AQABNQAECgoKPQAIAMITAA==.Quickfinger:BAAANQAECggIAQAAAA==.Quiniustius:BAAANQAECgQIBQAAAA==.',
Ra='Ragingpwner:BAAANQADCgUICQAAAA==.Rallyn:BAAANQADCggICAAAAA==.Ramacondama:BAAANQAECgcIEAABNQAECggIPQANANQiAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECgoKOgASAOAeAA==.Ravel:BAABNQAECn8eAAIoAAkKFRv8DABDAgAoAAkKFRv8DABDAgAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECn86AAMSAAoK4B6AKADfAgASAAoK4B6AKADfAgAYAAIKtgK6LwBUAAAAAA==.Reios:BAABNQAECn87AAIbAAoKuh68HgCNAgAbAAoKuh68HgCNAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhastaman:BAAANQAECgUIBQABNQAECgoKPQARAPwWAA==.Rhaz:BAABNQAECn83AAMdAAoKuRW7JwB8AgAdAAoKuRW7JwB8AgAMAAEKAADpvAEqAAAAAA==.Rheeannon:BAAANQABCgQIBgAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECggIFwAhACcaAA==.',
Ri='Rickyspanish:BAABNQAECn9EAAICAAoKJyGFDQANAwACAAoKJyGFDQANAwAAAA==.Rictor:BAAANQAECggICAAAAA==.Rifter:BAABNQAECn8aAAIjAAcK7Qx6MADlAAAjAAcK7Qx6MADlAAAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAPAAAAAA==.Rinnobu:BAAANQAECgcICAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgoKPQAIAMITAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Rollnine:BAAANQAECgEIAgAAAA==.Romeric:BAAANQADCggIDgAAAA==.Roupert:BAABNQAECn8XAAIhAAgKJxq7BQBXAgAhAAgKJxq7BQBXAgAAAA==.',
Ru='Rubyouraw:BAABNQAECn8WAAIQAAgKrQ9/EgA3AQAQAAgKrQ9/EgA3AQAAAA==.Ruffneck:BAABNQAECn8qAAILAAkKpBJUaABDAgALAAkKpBJUaABDAgAAAA==.Russk:BAAANQAECgYIBwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICwAAAA==.',
Sa='Saelaan:BAABNQAECn8lAAInAAgKYBxgCAC+AQAnAAgKYBxgCAC+AQABNQAECgoKMQAjACYjAA==.Sailfu:BAACNQAFFH8YAAIZAAgKwx0wAgAHAgAZAAgKwx0wAgAHAgA1AAQKfzAAAhkACgo1JcgFAHQDABkACgo1JcgFAHQDAAE1AAUUBwgYAAIAICUA.Saiyurie:BAAANQABCgIIAgAAAA==.Sakrine:BAAANQAECgIIAQAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAABNQAECn8jAAIGAAgKMB7cHQBRAgAGAAgKMB7cHQBRAgAAAA==.Sandarr:BAABNQAECn8nAAIjAAgKuRe3IgDMAQAjAAgKuRe3IgDMAQAAAA==.Sanguinne:BAABNQAECn8jAAIJAAcKtwr+DQDZAAAJAAcKtwr+DQDZAAAAAA==.Santhus:BAABNQAECn8gAAIkAAoKMA/DQgDaAQAkAAoKMA/DQgDaAQAAAA==.Sarabela:BAAANQADCggICAABNQAECggIJwAjALkXAA==.Saretae:BAAANQADCggIHQABNQAFFAcIFgAXAAQgAA==.Sargemarge:BAABNQAECn8dAAIWAAkKICMxDQBXAwAWAAkKICMxDQBXAwAAAA==.Sarume:BAAANQAECggIDAABNQAECggIPQANANQiAA==.',
Sc='Sci:BAABNQAECn8tAAIdAAgKGyUPEABLAwAdAAgKGyUPEABLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAABNQAECgMIAwAPAAAAAA==.Selener:BAAANQAECggIDQAAAA==.Serbitar:BAAANQAECggICAABNQAECgoKLQAIAB0gAA==.Serrata:BAABNQAECn8hAAILAAgKWx1OVwAFAgALAAgKWx1OVwAFAgAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCggIEAAAAA==.Shadowplay:BAEANQAECgQIBgABNQAECgoKPQAIAMITAA==.Shamski:BAAANQAECgMIAgABNQAECgYICgAPAAAAAA==.Shamydavisjr:BAAANQABCggIFgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIBAAAAA==.Shathice:BAAANQAECgQIAwABNQAECgoKJwAdAH4fAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.Shocky:BAAANQABCgEIAQABNQADCgIIAgAPAAAAAA==.',
Si='Sidelvar:BAAANQABCggIFAAAAA==.Silandros:BAAANQAECgYIBwAAAA==.Silther:BAABNQAECn8dAAIjAAkKwhZYFwCoAQAjAAkKwhZYFwCoAQAAAA==.',
Sk='Skarath:BAABNQAECn8dAAQQAAYK3AYqJACSAAATAAUKYAgoMQCtAAAQAAUKoAQqJACSAAARAAQKXAMSCQFUAAAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAABNQAECn8jAAIEAAgKpAwDOQBWAQAEAAgKpAwDOQBWAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn85AAIWAAoKVhjsMQBBAgAWAAoKVhjsMQBBAgAAAA==.Sorrowsöng:BAABNQAECn8dAAMMAAkKrhhjegDEAQAMAAkKrhhjegDEAQAdAAQKDQWSvQCNAAAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAPAAAAAA==.Southvik:BAAANQAECggIEQABNQAECgkJNgABAHwfAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAUIFAABAGcfAA==.Sparrhawk:BAAANQAECgcIDQAAAA==.Spiced:BAACNQAFFH8IAAIDAAMKSiHUDAAQAQADAAMKSiHUDAAQAQA1AAQKfzAAAgMACgo0IswJAPYCAAMACgo0IswJAPYCAAAA.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAABNQAECn9JAAMGAAoKARNeFQD0AQAGAAoKARNeFQD0AQAHAAUKkRP2DgA9AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Stabussy:BAAANQAECgQICwABNQAECggIEQAPAAAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQAECgQICAAAAA==.Stingella:BAAANQAECgcIBwAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Sttriker:BAABNQAECn8oAAIOAAoK4wQ9SwDkAAAOAAoK4wQ9SwDkAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgQIBAAPAAAAAA==.Stéalth:BAAANQAECgUIBQAAAA==.',
Sy='Symditho:BAAANQABCgcICwAAAA==.Synsairis:BAABNQAECn8eAAIZAAkKKQ3FIgBtAQAZAAkKKQ3FIgBtAQAAAA==.',
Ta='Talenelat:BAAANQAECgIIAQAAAA==.Talonknight:BAABNQAECn8jAAMKAAgKzgrEDQD4AAAKAAgKgQrEDQD4AAAmAAUK1QauKQDdAAAAAA==.Talset:BAAANQAECgEIAQAAAA==.Tau:BAABNQAECn8mAAIjAAoKoxTNFgCuAQAjAAoKoxTNFgCuAQAAAA==.Tauria:BAAANQABCggIGwAAAA==.Taurrows:BAAANQAECgUIBAAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgQIDQAAAA==.',
Te='Tempedsoul:BAAANQABCgcIDQAAAA==.',
Th='Thaendofyou:BAAANQAECggICwAAAA==.Thalassia:BAAANQAECgMIAwAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAABNQAECn8WAAMeAAUKeA8WZgDqAAAeAAUKeA8WZgDqAAAUAAMKOQnGdAB3AAAAAA==.Thellan:BAAANQAECgEIAQAAAA==.Themonk:BAAANQADCggICgABNQAECgkJMwAUADsXAA==.Therise:BAABNQAECn8pAAMNAAkK/g4kEwADAQANAAgK7Q8kEwADAQAOAAIKYwl/fQA1AAABNQAECgoKWAASAJoYAA==.Thetank:BAABNQAECn8zAAMUAAkKOxdYQgDzAQAUAAkKOxdYQgDzAQAIAAEKFAnwiQArAAAAAA==.Thoroughbred:BAAANQADCgYIDQAAAA==.Throwdini:BAABNQAECn88AAILAAoKUxSNRQA0AgALAAoKUxSNRQA0AgAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAPAAAAAA==.Thunderegg:BAAANQAECgcIEAABNQAECgoKWAASAJoYAA==.Thundermaker:BAABNQAECn8aAAISAAoKbBcSJQBBAgASAAoKbBcSJQBBAgABNQAECgoKLQAIAB0gAA==.',
Ti='Timotthy:BAABNQAECn8yAAQFAAgKMSFDEwAvAgAFAAYKPiBDEwAvAgAiAAcKxSBbEgCBAQADAAEKAACBygAXAAAAAA==.Tixxle:BAAANQADCggIGAAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgcICQABNQAFFAQIDwAJAGQZAA==.',
Tr='Treateak:BAAANQAECgUICgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAABNQAECn8VAAISAAkKvBsBLwDAAgASAAkKvBsBLwDAAgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn9aAAIVAAoKPhsMEQDfAgAVAAoKPhsMEQDfAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAABNQAECn8aAAIfAAgKrRfWCQAxAgAfAAgKrRfWCQAxAgAAAA==.Tyriem:BAABNQAECn8hAAILAAoKVBRXQACqAgALAAoKVBRXQACqAgAAAA==.Tyssanton:BAABNQAECn8oAAMmAAkKnAiNIwAnAQAmAAgKVASNIwAnAQAaAAkKXQRzIwDVAAAAAA==.',
Tz='Tziganin:BAABNQAECn8cAAISAAkKdxORRQCnAQASAAkKdxORRQCnAQAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgoKJwAdAH4fAA==.',
Un='Unholybussy:BAAANQAECgcIDwAAAA==.',
Ut='Utaadh:BAABNQAECn8zAAIOAAkKhhNwNwD1AQAOAAkKhhNwNwD1AQAAAA==.',
Va='Vael:BAABNQAECn8aAAIGAAoKwhQnGgCzAQAGAAoKwhQnGgCzAQABNQAECgoKWAAOABQkAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAPAAAAAA==.Vallderossa:BAAANQAECgIIAgAAAA==.Vallerin:BAABNQAECn8wAAIYAAoKgRhkDAA/AgAYAAoKgRhkDAA/AgAAAA==.Vanek:BAAANQAECgEIAQAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgoKWAAOABQkAA==.Velazar:BAAANQAECgQIBAAAAA==.Verras:BAAANQADCgEIAQAAAA==.',
Vi='Vicente:BAABNQAECn8XAAICAAoKIAZHJgBSAQACAAoKIAZHJgBSAQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQAECgMIAwABNQAECgkJNgABAHwfAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8WAAILAAYKUhoQBQAGAgALAAYKUhoQBQAGAgA1AAQKfzMABAsACgopIYEwANsCAAsACgopIYEwANsCABUAAQpBGIqBAEEAACEAAQoAAGwTADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8tAAMUAAkKhhsPLQBiAgAUAAkKhhsPLQBiAgAIAAMK5gOYbABdAAAAAA==.',
Wa='Wagwan:BAABNQAECn8dAAQIAAoKARmgGAASAgAIAAoKTxigGAASAgAeAAIKXCDegwCfAAAUAAEKdyIAAAAAAAAAAA==.Walls:BAABNQAECn8kAAIMAAoK4wu6nQB8AQAMAAoK4wu6nQB8AQAAAA==.Wardrik:BAAANQADCgUIBQAAAA==.Waste:BAABNQAECn8fAAMbAAkKXx1aUADQAQAbAAkKqhxaUADQAQAJAAIKtxUoKQBRAAAAAA==.Wawel:BAABNQAECn8qAAQmAAoKUh7HDgBwAgAmAAkKWR3HDgBwAgAaAAYKkCDXIQC+AQAKAAQKAxk+FADrAAAAAA==.Wazwaz:BAAANQAECgIIAQABNQAECggILQAdABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgUIDAAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.Winstagram:BAAANQADCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgUICgAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIFgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xi='Xibaba:BAAANQAECgEIAQAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yo='Yogí:BAABNQAECn85AAIYAAoKGhqwDwBuAgAYAAoKGhqwDwBuAgAAAA==.Yokos:BAAANQAECgUIBgAAAA==.Yoursummons:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zafiel:BAAANQADCgcIBwAAAA==.Zahneel:BAABNQAECn8cAAMEAAkKoQ8aLABxAQAEAAkKoQ8aLABxAQAFAAUKrAV5TgByAAAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8NAAIMAAUK/hv3DgBdAQAMAAUK/hv3DgBdAQA1AAQKf0UAAgwACgpHJZUGAGEDAAwACgpHJZUGAGEDAAAA.Zarisong:BAABNQAECn8XAAMjAAkKBxVlIQBMAQAjAAkKBxVlIQBMAQAMAAMKswgUfQFeAAABNQAECgoKIAAkADAPAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.',
Zo='Zoburg:BAAANQAECgcIDAABNQAECgkJNgABAHwfAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAPAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQAECgQICQAAAA==.',
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
