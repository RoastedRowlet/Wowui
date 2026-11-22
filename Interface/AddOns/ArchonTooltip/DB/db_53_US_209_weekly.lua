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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Evoker-Preservation','Warlock-Demonology','Warlock-Affliction','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Rogue-Assassination','Hunter-Survival','Druid-Feral','Rogue-Subtlety','Paladin-Protection','Rogue-Outlaw','Evoker-Devastation','Monk-Brewmaster','Monk-Mistweaver',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aassvik:BAABNQAECn89AAIBAAoKCiGvFQApAwABAAoKCiGvFQApAwAAAA==.',
Ab='Absolute:BAACNQAFFH8aAAICAAgKyyAZAQAnAgACAAgKyyAZAQAnAgA1AAQKfzYAAgIACgpVJloBAG8DAAIACgpVJloBAG8DAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8TAAMDAAgKvxpTCQDqAQADAAgKvxpTCQDqAQAEAAEK1AA1GQAwAAA1AAQKfz8ABAMACgrsJZ4DAFcDAAMACgrsJZ4DAFcDAAQABgp/EIU7AEQBAAUAAQoAALxtACAAAAAA.Achievsome:BAABNQAECn9DAAQGAAoKBCWuAwCfAwAGAAoKBCWuAwCfAwABAAcKthUaiQB7AQAHAAMKIxFEEACDAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesodx:BAAANQAECgcICAABNQAECgoKHwAIAOUbAA==.Aesomx:BAAANQAECgIIAQABNQAECgoKHwAIAOUbAA==.Aesoxp:BAAANQAECggIEQABNQAECgoKHwAIAOUbAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgoKHQAJAHMRAA==.',
Ah='Ahjbastet:BAAANQAECgYIBQAAAA==.Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.Aisatsan:BAAANQADCgMIAwAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgcIDgAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAABNQAECn8UAAIKAAgKxgkqDgBlAQAKAAgKxgkqDgBlAQAAAA==.Algas:BAAANQAECgIIAQAAAA==.Aliengrey:BAABNQAECn8aAAILAAcK1RQCtwCWAQALAAcK1RQCtwCWAQAAAA==.Alindrin:BAAANQABCgIIAgAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8tAAIMAAoKjBMTcwBIAgAMAAoKjBMTcwBIAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECggICAAAAA==.',
Am='Amane:BAABNQAECn9CAAMNAAgK1CLSBgCnAgANAAgK1CLSBgCnAgAOAAgKaxtfNAB8AQAAAA==.American:BAAANQAECgMIAwAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQADCggIDQAAAA==.',
An='Anger:BAAANQADCggIDQAAAA==.Angryfyne:BAAANQAECggICAAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hXGUgArAgABAAgK4hXGUgArAgAGAAYKyQoSQwAbAQAAAA==.Anowon:BAAANQAECggIAQABNQAECggICAAPAAAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgoKNwAEACklAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgoKKgAMAEcNAA==.Arkanis:BAABNQAECn9KAAIQAAoKsRjEBgBSAgAQAAoKsRjEBgBSAgAAAA==.Arkherym:BAAANQAECgYIBgAAAA==.Armament:BAABNQAECn8/AAMRAAoKEhiHXAB2AgARAAoKEhiHXAB2AgAQAAEKAABrQQAAAAAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggIEAABNQAECggIDgAPAAAAAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn9WAAILAAoKRCSLCQA/AwALAAoKRCSLCQA/AwAAAA==.Aurius:BAABNQAECn8YAAIMAAkKkRNzlgD2AQAMAAkKkRNzlgD2AQAAAA==.',
Av='Avalancha:BAABNQAECn8wAAIFAAkKyRcYFQAWAgAFAAkKyRcYFQAWAgAAAA==.Avinoch:BAABNQAECn8qAAIFAAcKOQsNOgDaAAAFAAcKOQsNOgDaAAAAAA==.',
Ax='Axon:BAAANQAECggIEAAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAPAAAAAA==.',
Az='Azekor:BAAANQAECgMIAwAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIIAAgKDhoFQwAPAgAIAAgKDhoFQwAPAgAAAA==.',
Ba='Babykay:BAAANQADCgUIDQABNQAECgoKOgASAOAeAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAABNQAECn8YAAITAAkKrA2WFwBRAQATAAkKrA2WFwBRAQAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAPAAAAAA==.Bartholomäus:BAAANQAECgYIBgAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAABNQAECn8mAAIRAAoKXgv/cgCqAQARAAoKXgv/cgCqAQAAAA==.',
Be='Beezlebumon:BAABNQAECn87AAMIAAkKWxeoGwAHAgAIAAkKWxeoGwAHAgAUAAIKZgtJpAAxAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgUIBAAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgYIBQAAAA==.Bewater:BAABNQAECn8zAAILAAkK/xgtYgACAgALAAkK/xgtYgACAgAAAA==.',
Bl='Blegh:BAABNQAFFH8HAAMLAAQKYQpcGADRAAALAAQK9QlcGADRAAAVAAIKvQRoGwBxAAAAAA==.Bluerain:BAAANQADCgcIBwAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8lAAIIAAoKVB9TEwBaAgAIAAoKVB9TEwBaAgAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECn9FAAMWAAoK6B0mKgC7AgAWAAoK6B0mKgC7AgASAAYKGw4lmQDWAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8UAAIBAAUKZx9MDQDUAQABAAUKZx9MDQDUAQA1AAQKfz0AAwEACgo6ImQdAPwCAAEACgo6ImQdAPwCAAYABQq6GUw2AOIAAAAA.',
Br='Bracknor:BAABNQAECn8dAAILAAgKKhF8fAAVAgALAAgKKhF8fAAVAgAAAA==.Brandonb:BAABNQAECn9pAAIXAAoKqSLtHwBaAwAXAAoKqSLtHwBaAwAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECggIEQABNQAFFAYIFgALAFIaAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn80AAIYAAoKZSCQBQDfAgAYAAoKZSCQBQDfAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECggIEQAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.Brynnbramble:BAAANQADCggIDwAAAA==.',
By='Bysokar:BAABNQAECn8rAAIZAAoKcBs4FQCqAgAZAAoKcBs4FQCqAgAAAA==.',
Ca='Cainfortea:BAAANQAECgUICQAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Cakevoid:BAAANQAECggICwAAAA==.Calipal:BAABNQAECn8lAAIMAAcK9Qf+/QDsAAAMAAcK9Qf+/QDsAAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAABNQAECn8lAAIBAAoK0CCqDAB7AwABAAoK0CCqDAB7AwABNQAFFAkKFAAWAO8jAA==.Catalinasham:BAACNQAFFH8UAAIWAAkK7yNCAADIAwAWAAkK7yNCAADIAwA1AAQKfzgAAhYACgrRI5YIAJADABYACgrRI5YIAJADAAE1AAUUCQoUABYA7yMA.Cataster:BAAANQADCgcIAwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAgAAAA==.Cerberusbone:BAABNQAECn8jAAMUAAoKQRJVJgDKAQAUAAkKPBJVJgDKAQAIAAYKxQxsfgAjAQAAAA==.',
Ch='Challengerz:BAAANQAECgYIDwAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIEAAAAA==.Chritiane:BAAANQAECgYIBwAAAA==.',
Ci='Cinderlily:BAABNQAECn8oAAMaAAcKIhrPEgDSAQAaAAcKIhrPEgDSAQAKAAQK/gVXGwCPAAAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAPAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8PAAMbAAQKZBmsGQAoAQAbAAQKmxWsGQAoAQAJAAIKZwxsCAB5AAA1AAQKfygABBsACgqbIu8ZAB8DABsACgqnIe8ZAB8DAAkAAwq3Hq8UALUAABwAAQoAAKknAE0AAAAA.Connery:BAAANQADCgYIKAAAAA==.Coryuchiha:BAAANQAECgMIAwAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crippleya:BAAANQAECgEIAQAAAA==.Crithappens:BAAANQAECgUIBQAAAA==.Criturrpants:BAABNQAECn8VAAMQAAcKCxXzFQA8AQAQAAYKGxbzFQA8AQATAAEKzRCcQQA6AAAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAIXAAkKlRhUWgDLAgAXAAkKlRhUWgDLAgAAAA==.Cynthea:BAAANQAECgcICwAAAA==.Cyp:BAABNQAECn9MAAIRAAoK5xloOwBTAgARAAoK5xloOwBTAgAAAA==.',
['Cü']='Cüpcake:BAABNQAECn8kAAIOAAoK8wtjLwCbAQAOAAoK8wtjLwCbAQAAAA==.',
Da='Dababycar:BAABNQAECn8fAAMdAAoKuhNWOwAqAgAdAAkKlBVWOwAqAgAMAAcKfQxOzAA+AQAAAA==.Dabbyduck:BAABNQAECn8iAAMbAAkK7BmONAC4AgAbAAkK7BmONAC4AgAJAAcKLg4fGQCjAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgUIBgAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQADCggIFQAAAA==.',
De='Deadincide:BAEBNQAECn8/AAMIAAoKwhMbQgATAgAIAAkKsRMbQgATAgAeAAkK5g4vNQDOAQAAAA==.Deadstasheo:BAACNQAFFH8XAAIIAAYKcRf7AQCpAQAIAAYKcRf7AQCpAQA1AAQKfykAAggACgpyI5YYAPoCAAgACgpyI5YYAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn9BAAIMAAoKixnZRQBYAgAMAAoKixnZRQBYAgAAAA==.Deezmonz:BAABNQAECn8dAAMJAAoKcxHXFwCgAAAbAAoKuxAedgB6AQAJAAMKaxDXFwCgAAAAAA==.Delik:BAABNQAECn8wAAIfAAkKKRaNCQA6AgAfAAkKKRaNCQA6AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgQIAwAAAA==.Deneol:BAABNQAECn8nAAMGAAoKShofEQDoAgAGAAoKShofEQDoAgAHAAEK3BG+JwA3AAAAAA==.Destrogen:BAACNQAFFH8LAAMcAAUKwRmwAQBEAQAcAAUKFBawAQBEAQAbAAEKTB6UMQBXAAA1AAQKf0QABBwACgp4IhABACEDABwACgp4IhABACEDABsABArODSv2AN8AAAkAAgqkDQFcAG4AAAAA.Desìre:BAABNQAECn8vAAMHAAkKzR40AwDJAgAHAAgKfx80AwDJAgABAAMKIRqrqwDdAAAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECggIDgAPAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECn82AAIIAAoKJh9cDwCJAgAIAAoKJh9cDwCJAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgUIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECggIEwAPAAAAAA==.Doomwing:BAAANQADCgYIBgAAAA==.',
Dr='Dracodeez:BAABNQAECn8gAAIgAAoKlhwkCABtAgAgAAoKlhwkCABtAgAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECn8tAAMIAAoKHSCCDgBEAwAIAAoKHSCCDgBEAwAUAAQKZBcXjwDHAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Dundaz:BAAANQAECgYIBgAAAA==.Durunk:BAABNQAECn8XAAIWAAYKZwqQrQDAAAAWAAYKZwqQrQDAAAAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAABNQAECn8aAAIZAAgKghHhMACQAQAZAAgKghHhMACQAQAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIGgAZAIIRAA==.',
Ec='Eclipcees:BAAANQADCgQIAwAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Electronvolt:BAEANQADCgcICAABNQAECgoKPwAIAMITAA==.Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQADCgUIDgAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgUIFwAeAHgPAA==.',
Er='Eradion:BAAANQAECgMIAwAAAA==.Eredarlord:BAAANQAECgcIDQABNQAECgoKIQAWAJ0ZAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8pAAMLAAgKuBY3nQDMAQALAAgKuBY3nQDMAQAhAAIKqRNZEwBDAAAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECgoKQgAVAOINAA==.',
Es='Eszran:BAABNQAECn8jAAIiAAoKkhPaDQDvAQAiAAoKkhPaDQDvAQAAAA==.',
Eu='Euthanized:BAAANQAECgIIBwAAAA==.',
Fe='Felviiv:BAAANQAECgYIDgAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn9BAAIUAAoKxh9aEgAaAwAUAAoKxh9aEgAaAwABNQAECgMIAwAPAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAYIFAAGAEwQAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAABNQAECn8aAAITAAkKIiXhBQCuAgATAAkKIiXhBQCuAgAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAABNQAECn8XAAIfAAkKGAiYFgAzAQAfAAkKGAiYFgAzAQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAABNQAECn8fAAIBAAkKSgpmdwB0AQABAAkKSgpmdwB0AQAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn9HAAMVAAoKER3BGQC4AQAVAAoKRBfBGQC4AQALAAYKyx0ttgCYAQAAAA==.Frearyne:BAABNQAECn83AAIEAAoKKSVUAgCpAwAEAAoKKSVUAgCpAwAAAA==.Frinu:BAAANQAECgQIBQABNQABCgIIAgAPAAAAAA==.Frogs:BAAANQADCggIKwAAAA==.Frostyshadow:BAABNQAECn8rAAIXAAkKESHGHABkAwAXAAkKESHGHABkAwAAAA==.Frozatresh:BAAANQAECgEIAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIZAAkKzBUdIwAOAgAZAAkKzBUdIwAOAgAAAA==.',
Fy='Fyxxer:BAAANQADCgIIAgABNQAFFAYIFAAGAEwQAA==.Fyxxie:BAACNQAFFH8UAAIGAAYKTBDABwAeAQAGAAYKTBDABwAeAQA1AAQKfzsAAwYACgp0HiALAKsCAAYACgp0HiALAKsCAAcAAQrYHm0hAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Gi='Gialiana:BAABNQAECn8tAAIVAAoKOBYaLADqAQAVAAoKOBYaLADqAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAgIGgACAMsgAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8fAAIQAAYKzR11DAD0AQAQAAYKzR11DAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.Grully:BAABNQAECn8qAAIWAAoKgQwfZwDXAQAWAAoKgQwfZwDXAQAAAA==.',
Gu='Gurt:BAABNQAECn8eAAMcAAkKaRBFCADZAQAcAAkKaRBFCADZAQAJAAMKXAVKUACPAAAAAA==.Guzzug:BAABNQAECn9NAAIRAAoKKiGUIQC9AgARAAoKKiGUIQC9AgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8rAAICAAkKZht8GgCFAgACAAkKZht8GgCFAgAAAA==.Hailsbelle:BAABNQAECn8mAAIOAAoKDQj6PABKAQAOAAoKDQj6PABKAQAAAA==.Haldis:BAAANQAECgYICQABNQAECggICgAPAAAAAA==.Harleymama:BAAANQABCgIIAgAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8xAAIgAAkKXxeaLQAvAgAgAAkKXxeaLQAvAgAAAA==.Helado:BAAANQAECgUIDQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highertotem:BAAANQADCgUIBAABNQAECgEIAQAPAAAAAA==.Highwayman:BAABNQAECn8VAAIjAAkKpA01awBpAQAjAAkKpA01awBpAQABNQAECgoKYQALAHUkAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQAECgcIBwAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAABNQAECn8rAAIMAAcK0BIy2gBnAQAMAAcK0BIy2gBnAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIIAAAAA==.Ievil:BAABNQAECn8yAAMIAAoKxwt3LQB9AQAIAAoKxwt3LQB9AQAUAAEKAABK3QAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgoKXgAOALIkAA==.',
Im='Imjustpika:BAACNQAFFH8TAAIhAAcKgw5XAAAdAgAhAAcKgw5XAAAdAgA1AAQKfyoAAiEACgp9HPwEAH8CACEACgp9HPwEAH8CAAAA.',
In='Inawee:BAABNQAECn9WAAIEAAoK4h7SDgDnAgAEAAoK4h7SDgDnAgAAAA==.Inferniö:BAACNQAFFH8WAAMXAAcKBCDuCAA5AgAXAAYKth7uCAA5AgAfAAEKPSUiCwBtAAA1AAQKf1IAAxcACgpyJR0QAJIDABcACgrzJB0QAJIDAB8AAQqtIyYwAGsAAAAA.Inkurushio:BAAANQAECgMIBAAAAA==.Inshallah:BAAANQAECgMIAwABNQAECgoKHwAIAOUbAA==.Intothefray:BAAANQADCgUIDgAAAA==.',
Io='Iolanie:BAAANQAECgMIAwABNQAECgcIBwAPAAAAAA==.',
Is='Ismat:BAABNQAECn9pAAIWAAoKIhCSUQDNAQAWAAoKIhCSUQDNAQAAAA==.',
Ja='Jaeza:BAAANQADCggIKQABNQAECgYICgAPAAAAAA==.Jaqu:BAAANQAECgEIAQAAAA==.Jarshh:BAABNQAECn8eAAIQAAkKuB0KCAArAgAQAAkKuB0KCAArAgAAAA==.Jaycinth:BAAANQAECgcIBwAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgIIAgAAAA==.',
Ju='Judge:BAABNQAECn8+AAQkAAoKLCP5AwAqAwAkAAoKLCP5AwAqAwAdAAMKSwSR/QCBAAAMAAMKVBC5dgFmAAABNQAECgMIAwAPAAAAAA==.Juura:BAABNQAECn86AAMJAAoKNhHVBgBuAQAJAAkKJBLVBgBuAQAbAAgK3g1ngwBZAQAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8nAAIdAAoKfh8LEQA1AwAdAAoKfh8LEQA1AwAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAABNQAECn8cAAIjAAoK6hFFGAAaAgAjAAoK6hFFGAAaAgAAAA==.Kaveros:BAABNQAECn8kAAMjAAoKRRhFNAAqAgAlAAcKHhs4BwBIAgAjAAoKahRFNAAqAgAAAA==.',
Ke='Kelaan:BAABNQAECn85AAMkAAoKrCOWAwA0AwAkAAoKrCOWAwA0AwAMAAEKAAAuoQE2AAAAAA==.Kelimao:BAABNQAECn8aAAMDAAkKyQcsPwAtAQADAAkKyQcsPwAtAQAEAAEKmQkxdgAzAAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Kiritos:BAABNQAECn8rAAIEAAoKZh9BDAAGAwAEAAoKZh9BDAAGAwAAAA==.Kiserys:BAABNQAECn8dAAMmAAcKJhAeGgCnAQAmAAcKJhAeGgCnAQAaAAQK/xHWNQDlAAAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Koko:BAAANQAECgMIAwAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Koombah:BAAANQADCgQIBAAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgMIAQAAAA==.',
Kr='Krysto:BAABNQAECn8tAAILAAkK7woekADpAQALAAkK7woekADpAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUICwAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
Ky='Kyllista:BAAANQADCggIGQAAAA==.',
La='Laquisha:BAAANQAECgEIAQAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.Lepershaun:BAAANQADCgYIBgABNQAECgkJMQAQAMEVAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilatharia:BAAANQABCgIIAgAAAA==.Lilbowar:BAAANQAECgEIAQAAAA==.Lillath:BAAANQABCgQIBgAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECn9mAAMMAAoKnyJYHwBGAwAMAAoKOiJYHwBGAwAkAAUKOiF9JABKAQAAAA==.Lorenth:BAABNQAECn8eAAIBAAkKTQbEhwBCAQABAAkKTQbEhwBCAQAAAA==.Lorgoza:BAAANQAECgQIBAAAAA==.',
Lu='Lucerza:BAAANQAECgEIAQABNQAECgoKIwAOAH0WAA==.Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
Lv='Lvcky:BAAANQAECgMIAwAAAA==.',
['Lì']='Lìte:BAABNQAECn8mAAICAAoK1wxtIwCCAQACAAoK1wxtIwCCAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn8/AAMjAAoKHQt7HwDUAQAjAAoKHQt7HwDUAQAgAAEKhgdTagArAAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAAUAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwAXABEhAA==.Malidros:BAAANQAECgYIEgABNQAECggICgAPAAAAAA==.Malign:BAABNQAECn8sAAMgAAoKQCOtAwCcAwAgAAkKiSOtAwCcAwAjAAkKByJoCAA3AwABNQAFFAgIGgACAMsgAA==.Manhatten:BAAANQAECgQIBQAAAA==.Marhault:BAABNQAECn9hAAMLAAoKdSSPBgBYAwALAAoKciSPBgBYAwAhAAUKbR9MCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAIUAAkK7RvZJACTAgAUAAkK7RvZJACTAgAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8bAAIMAAcKqQ+b2ABqAQAMAAcKqQ+b2ABqAQAAAA==.Mazah:BAABNQAECn9fAAMSAAoKKxmKKQA6AgASAAoKKxmKKQA6AgAWAAoKpBHNPgAZAgAAAA==.Mazlo:BAACNQAFFH8GAAIfAAQKBBJJCACXAAAfAAQKBBJJCACXAAA1AAQKf1cAAx8ACgp/IBAEAPUCAB8ACgp/IBAEAPUCABcAAgrrAP3DATgAAAAA.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgoKHQAJAHMRAA==.Mellethir:BAABNQAECn83AAMXAAoKfQpv5gC9AQAXAAoK5Qlv5gC9AQAfAAQKKAqPJwCjAAAAAA==.Messalina:BAAANQAECggICgAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECggIDgAAAA==.Minipimp:BAAANQADCgYIGQAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAABNQAECn8mAAIEAAcKfBM7LwB2AQAEAAcKfBM7LwB2AQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8tAAILAAoK8h8LMwB6AgALAAoK8h8LMwB6AgAAAA==.Moglayn:BAABNQAECn9RAAIUAAoKvyXpAQDWAwAUAAoKvyXpAQDWAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAInAAQKWQ1uBgD4AAAnAAQKWQ1uBgD4AAA1AAQKfxsAAicACQpOGnENACQCACcACQpOGnENACQCAAE1AAUUBwgRABQAKg4A.Monorìth:BAEBNQAFFH8RAAIUAAcKKg5uDgBtAQAUAAcKKg5uDgBtAQAAAA==.Morninstar:BAAANQADCgMIAwAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgQIBQAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgoKPwAjAB0LAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIEQABNQABCggIFgAPAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAABNQAECn8YAAIiAAYKvxL8HQAsAQAiAAYKvxL8HQAsAQAAAA==.Nastyiam:BAACNQAFFH8OAAIYAAQKHAagBADHAAAYAAQKHAagBADHAAA1AAQKf0kAAhgACgruFVINAEACABgACgruFVINAEACAAAA.',
Ne='Nerfornothin:BAABNQAECn8xAAILAAoKZgdghgCsAQALAAoKZgdghgCsAQAAAA==.Nethbubble:BAAANQAECgEIAQABNQAFFAQIBgAaAP4FAA==.Nethflap:BAACNQAFFH8GAAIaAAMK/gXFEQCwAAAaAAMK/gXFEQCwAAA1AAQKfy8AAhoACgpSEDwbABQCABoACgpSEDwbABQCAAAA.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQAECgQIBAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Nights:BAAANQABCgIIAgAAAA==.Niik:BAABNQAECn8qAAIWAAoKkRpKMQCcAgAWAAoKkRpKMQCcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAACNQAFFH8IAAIYAAMKSxeRAwDsAAAYAAMKSxeRAwDsAAA1AAQKf0AAAhgACgqYJL8BAJwDABgACgqYJL8BAJwDAAAA.',
Ny='Nycterine:BAAANQAECggIDgABNQAECggIGgAfAK0XAA==.Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgUIDQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.',
Os='Osanyin:BAAANQADCgQIBAABNQAECggICgAPAAAAAA==.',
Ou='Outstanding:BAAANQAECgUIBgABNQAECgoKPQABAAohAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAABNQAECn8WAAMeAAoKWh2kGgB0AgAeAAoKWh2kGgB0AgAUAAEKVBDCoAA1AAAAAA==.Perfections:BAAANQADCgQIBgAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgMIAwAAAA==.Pikagosa:BAAANQAECgIIAgABNQAFFAcIEwAhAIMOAA==.Pilgor:BAABNQAECn8fAAMKAAoKfQ+aDACKAQAKAAkKXg6aDACKAQAaAAoKqgbMFwB4AQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAPAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQIDwAAAA==.Polkovnik:BAABNQAECn8fAAIRAAkKVRvFZQBeAgARAAkKVRvFZQBeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEBNQAECn8lAAIXAAkKKQW/sgA/AQAXAAkKKQW/sgA/AQABNQAECgoKPwAIAMITAA==.Quickfinger:BAAANQAECggIAQAAAA==.Quiniustius:BAAANQAECgQIBQAAAA==.',
Ra='Ragingpwner:BAAANQADCgUICQAAAA==.Ramacondama:BAAANQAECgcIEQABNQAECggIQgANANQiAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECgoKOgASAOAeAA==.Ravel:BAABNQAECn8eAAIoAAkKFRsMDgBAAgAoAAkKFRsMDgBAAgAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECn86AAMSAAoK4B6AKADfAgASAAoK4B6AKADfAgAYAAIKtgKHMgBUAAAAAA==.Reios:BAABNQAECn87AAIbAAoKuh7PIgCGAgAbAAoKuh7PIgCGAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhastaman:BAAANQAECgUIBQABNQAECgoKPwARABIYAA==.Rhaz:BAABNQAECn9BAAMdAAoKuRWMLABzAgAdAAoKuRWMLABzAgAMAAEKAADpvAEqAAAAAA==.Rheeannon:BAAANQABCgQIBgAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECggIFwAhACcaAA==.',
Ri='Rickyspanish:BAABNQAECn9EAAICAAoKJyGFDQANAwACAAoKJyGFDQANAwAAAA==.Rictor:BAAANQAECggICAAAAA==.Rifter:BAABNQAECn8bAAIkAAcK7w3dMgDrAAAkAAcK7w3dMgDrAAAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAPAAAAAA==.Rinnobu:BAAANQAECggIDgAAAA==.Ripnmaim:BAEANQADCgYICQABNQAECgoKPwAIAMITAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Rollnine:BAAANQAECgEIAgAAAA==.Romeric:BAAANQADCggIDgAAAA==.Roupert:BAABNQAECn8XAAIhAAgKJxq7BQBXAgAhAAgKJxq7BQBXAgAAAA==.',
Ru='Rubyouraw:BAABNQAECn8XAAIQAAgKrQ9KFAA0AQAQAAgKrQ9KFAA0AQAAAA==.Ruffneck:BAABNQAECn8qAAILAAkKpBJUaABDAgALAAkKpBJUaABDAgAAAA==.Russk:BAAANQAECgYIBwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICwAAAA==.',
Sa='Saelaan:BAABNQAECn8mAAInAAkK3Rv7BgAHAgAnAAkK3Rv7BgAHAgABNQAECgoKOQAkAKwjAA==.Sailfu:BAACNQAFFH8YAAIZAAgKwx3mAgD/AQAZAAgKwx3mAgD/AQA1AAQKfzAAAhkACgo1JcgFAHQDABkACgo1JcgFAHQDAAE1AAUUCAgaAAIAyyAA.Saiyurie:BAAANQABCgIIAgAAAA==.Sakrine:BAAANQAECgIIAQAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAABNQAECn8kAAIGAAkKIB3kFgD2AQAGAAkKIB3kFgD2AQAAAA==.Sandarr:BAABNQAECn8uAAIkAAoKHhQyHgB+AQAkAAoKHhQyHgB+AQAAAA==.Sanguinne:BAABNQAECn8pAAIJAAcK3AoyDwDZAAAJAAcK3AoyDwDZAAAAAA==.Santhus:BAABNQAECn8gAAIjAAoKMA/ISQDZAQAjAAoKMA/ISQDZAQAAAA==.Sarabela:BAAANQADCggICAABNQAECgoKLgAkAB4UAA==.Saretae:BAAANQADCggIHQABNQAFFAcIFgAXAAQgAA==.Sargemarge:BAABNQAECn8dAAIWAAkKICMxDQBXAwAWAAkKICMxDQBXAwAAAA==.Sarume:BAAANQAECggIDgABNQAECggIQgANANQiAA==.',
Sc='Sci:BAABNQAECn8tAAIdAAgKGyUPEABLAwAdAAgKGyUPEABLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAABNQAECgMIAwAPAAAAAA==.Selener:BAAANQAECggIDQAAAA==.Serbitar:BAAANQAECggICAABNQAECgoKLQAIAB0gAA==.Serrata:BAABNQAECn8lAAILAAoKWB8SHADSAgALAAoKWB8SHADSAgAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCggIEAAAAA==.Shadowplay:BAEANQAECgQIBgABNQAECgoKPwAIAMITAA==.Shamski:BAAANQAECgMIAgABNQAECgYICgAPAAAAAA==.Shamydavisjr:BAAANQABCggIFgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgQIBgAAAA==.Shathice:BAAANQAECgYIBQABNQAECgoKJwAdAH4fAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.Shocky:BAAANQABCgEIAQABNQADCgIIAgAPAAAAAA==.',
Si='Sidelvar:BAAANQABCggIFAAAAA==.Silandros:BAAANQAECgYIBwAAAA==.Silther:BAABNQAECn8dAAIkAAkKwhbyGQCkAQAkAAkKwhbyGQCkAQAAAA==.',
Sk='Skarath:BAABNQAECn8dAAQQAAYK3AYqJACSAAATAAUKYAgoMQCtAAAQAAUKoAQqJACSAAARAAQKXAO3EwFUAAAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAABNQAECn8kAAIEAAkKwAtzOQAxAQAEAAkKwAtzOQAxAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn89AAIWAAoK0RgdNABMAgAWAAoK0RgdNABMAgAAAA==.Sorrowsöng:BAABNQAECn8dAAMMAAkKrhhPhwC9AQAMAAkKrhhPhwC9AQAdAAQKDQVpyQCFAAAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAPAAAAAA==.Southvik:BAAANQAECggIEQABNQAECgoKPQABAAohAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAUIFAABAGcfAA==.Sparrhawk:BAAANQAECgcIEgAAAA==.Spiced:BAACNQAFFH8IAAIDAAMKSiFmDwAIAQADAAMKSiFmDwAIAQA1AAQKfzAAAgMACgo0IqIKAPQCAAMACgo0IqIKAPQCAAAA.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAABNQAECn9KAAMGAAoKARMEFwD0AQAGAAoKARMEFwD0AQAHAAUKkRP2DgA9AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Stabussy:BAAANQAECgMIDAABNQAECggIEQAPAAAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBgAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQAECgQICAAAAA==.Stingella:BAAANQAECgcIBwAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Sttriker:BAABNQAECn8oAAIOAAoK4wSkUADiAAAOAAoK4wSkUADiAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgQIBQAPAAAAAA==.Stéalth:BAAANQAECgUIBQAAAA==.',
Sy='Symditho:BAAANQABCgcICwAAAA==.Synsairis:BAABNQAECn8eAAIZAAkKKQ2VJQBtAQAZAAkKKQ2VJQBtAQAAAA==.',
Ta='Talenelat:BAAANQAECgIIAQAAAA==.Talonknight:BAABNQAECn8kAAMKAAkKXwqxEQAaAQAKAAgKgQqxEQAaAQAmAAYKBQeuKQDdAAAAAA==.Talset:BAAANQAECgEIAgAAAA==.Tau:BAABNQAECn8oAAIkAAoK1hQDGQCtAQAkAAoK1hQDGQCtAQAAAA==.Tauria:BAAANQAECgQIBAAAAA==.Taurrows:BAAANQAECgUIBgAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgQIDQAAAA==.',
Te='Tempedsoul:BAAANQABCgcIDQAAAA==.',
Th='Thaendofyou:BAAANQAECggICwAAAA==.Thalassia:BAAANQAECgMIAwAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAABNQAECn8XAAMeAAUKeA9dawDwAAAeAAUKeA9dawDwAAAUAAMKOQkaewByAAAAAA==.Thellan:BAAANQAECgEIAQAAAA==.Themonk:BAAANQADCggICgABNQAECgkJNAAUADsXAA==.Therise:BAABNQAECn8zAAMNAAoKkg7NDwBJAQANAAoKyg3NDwBJAQAOAAIKYwkfhAA1AAABNQAECgoKXwASACsZAA==.Thetank:BAABNQAECn80AAMUAAkKOxdYQgDzAQAUAAkKOxdYQgDzAQAIAAEKFAm+jwArAAAAAA==.Thoroughbred:BAAANQADCgYIDQAAAA==.Throwdini:BAABNQAECn88AAILAAoKUxQ6TgAyAgALAAoKUxQ6TgAyAgAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAPAAAAAA==.Thunderegg:BAABNQAECn8YAAILAAkKARGsjwCXAQALAAkKARGsjwCXAQABNQAECgoKXwASACsZAA==.Thundermaker:BAABNQAECn8aAAISAAoKbBdIKQA7AgASAAoKbBdIKQA7AgABNQAECgoKLQAIAB0gAA==.',
Ti='Timotthy:BAABNQAECn8yAAQFAAgKMSFDEwAvAgAFAAYKPiBDEwAvAgAiAAcKxSD4FAB+AQADAAEKAACBygAXAAAAAA==.Tixxle:BAAANQADCggIGAAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgcICQABNQAFFAQIDwAbAGQZAA==.',
Tr='Treateak:BAAANQAECgUICgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAABNQAECn8VAAISAAkKvBsBLwDAAgASAAkKvBsBLwDAAgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn9gAAIVAAoKXhsMEQDfAgAVAAoKXhsMEQDfAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAABNQAECn8aAAIfAAgKrRfWCQAxAgAfAAgKrRfWCQAxAgAAAA==.Tyriem:BAABNQAECn8hAAILAAoKVBRXQACqAgALAAoKVBRXQACqAgAAAA==.Tyssanton:BAABNQAECn8oAAMmAAkKnAiNIwAnAQAmAAgKVASNIwAnAQAaAAkKXQQ7MQARAQAAAA==.',
Tz='Tziganin:BAABNQAECn8cAAISAAkKdxNjTAClAQASAAkKdxNjTAClAQAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgoKJwAdAH4fAA==.',
Un='Unholybussy:BAAANQAECgcIDwAAAA==.',
Ut='Utaadh:BAABNQAECn85AAIOAAkKfhQkKwC3AQAOAAkKfhQkKwC3AQAAAA==.',
Va='Vael:BAABNQAECn8kAAIGAAoKzRgcEABXAgAGAAoKzRgcEABXAgABNQAECgoKXgAOALIkAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAPAAAAAA==.Vallderossa:BAAANQAECgIIAgAAAA==.Vallerin:BAABNQAECn84AAIYAAoKXRpDCgB5AgAYAAoKXRpDCgB5AgAAAA==.Vanek:BAAANQAECgEIAQAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgoKXgAOALIkAA==.Velazar:BAAANQAECgQIBAAAAA==.Verras:BAAANQADCgEIAQAAAA==.',
Vi='Vicente:BAABNQAECn8XAAICAAoKIAZJKQBPAQACAAoKIAZJKQBPAQAAAA==.Vicenti:BAAANQADCgYIEQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQAECgMIAwABNQAECgoKPQABAAohAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8WAAILAAYKUhoQBQAGAgALAAYKUhoQBQAGAgA1AAQKfzMABAsACgopIYEwANsCAAsACgopIYEwANsCABUAAQpBGIqBAEEAACEAAQoAAGwTADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8tAAMUAAkKhhsPLQBiAgAUAAkKhhsPLQBiAgAIAAMK5gNRcQBdAAAAAA==.',
Wa='Wagwan:BAABNQAECn8fAAQIAAoK5RviFABKAgAIAAoKMxviFABKAgAeAAIKXCDegwCfAAAUAAEKdyL2gQBlAAAAAA==.Walls:BAABNQAECn8qAAIMAAoKRw0rngCRAQAMAAoKRw0rngCRAQAAAA==.Wardrik:BAAANQADCgUIBQAAAA==.Waste:BAABNQAECn8fAAMbAAkKXx1OWADLAQAbAAkKqhxOWADLAQAJAAIKtxWnKwBRAAAAAA==.Wawel:BAABNQAECn8qAAQmAAoKUh7HDgBwAgAmAAkKWR3HDgBwAgAaAAYKkCDXIQC+AQAKAAQKAxk+FADrAAAAAA==.Wazwaz:BAAANQAECgIIAQABNQAECggILQAdABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgUIDAAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.Winstagram:BAAANQADCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgUICgAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIFgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xi='Xibaba:BAAANQAECgEIAgAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yo='Yogí:BAABNQAECn85AAIYAAoKGhqwDwBuAgAYAAoKGhqwDwBuAgAAAA==.Yokos:BAAANQAECgUIBgAAAA==.Yoursummons:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zafiel:BAAANQADCgcIBwAAAA==.Zahneel:BAABNQAECn8cAAMEAAkKoQ/1LwBwAQAEAAkKoQ/1LwBwAQAFAAUKrAUWVABwAAAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8NAAIMAAUK/hv3DgBdAQAMAAUK/hv3DgBdAQA1AAQKf0UAAgwACgpHJQ4IAFoDAAwACgpHJQ4IAFoDAAAA.Zarisong:BAABNQAECn8XAAMkAAkKBxXDJABJAQAkAAkKBxXDJABJAQAMAAMKswgUfQFeAAABNQAECgoKIAAjADAPAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.',
Zo='Zoburg:BAAANQAECgcIEQABNQAECgoKPQABAAohAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAPAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQAECgUIDgAAAA==.',
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
