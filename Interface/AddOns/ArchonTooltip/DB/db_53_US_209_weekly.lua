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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Warrior-Arms','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Mage-Frost','Rogue-Assassination','Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Monk-Brewmaster','Monk-Mistweaver','Druid-Feral',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aassvik:BAABNQAECn8rAAIBAAcK3CJhLgCuAgABAAcK3CJhLgCuAgAAAA==.',
Ab='Absolute:BAACNQAFFH8YAAICAAcKICVtAAATAgACAAcKICVtAAATAgA1AAQKfy4AAgIACgroJa8AAHMDAAIACgroJa8AAHMDAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8RAAMDAAcKKhpTCQDqAQADAAcKKhpTCQDqAQAEAAEK1AA1GQAwAAA1AAQKfzYABAMACgqjJX0CAFADAAMACgqjJX0CAFADAAQABgp/EIU7AEQBAAUAAQoAALxtACAAAAAA.Achievsome:BAABNQAECn8zAAQGAAoKXiSuAwCfAwAGAAkKeyWuAwCfAwABAAcKthUaiQB7AQAHAAIKwBCDDgBNAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesodx:BAAANQAECgIIAQABNQAECgoKGAAIAMgYAA==.Aesomx:BAAANQAECgEIAQABNQAECgoKGAAIAMgYAA==.Aesoxp:BAAANQAECgUICQABNQAECgoKGAAIAMgYAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgoKSgAJACohAA==.',
Ah='Ahjbastet:BAAANQAECgEIAQAAAA==.Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgUICwAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAABNQAECn8UAAIKAAgKxgkqDgBlAQAKAAgKxgkqDgBlAQAAAA==.Algas:BAAANQAECgIIAQAAAA==.Aliengrey:BAAANQAECgYIDgAAAA==.Alindrin:BAAANQABCgIIAgAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8rAAILAAoKjBMTcwBIAgALAAoKjBMTcwBIAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECgEIAQAAAA==.',
Am='Amane:BAABNQAECn83AAMMAAgKeyLSBgCnAgAMAAgKeyLSBgCnAgANAAgKVxmOJwBbAQAAAA==.American:BAAANQAECgMIAwAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCggIEgAAAA==.',
An='Anger:BAAANQADCggIDQAAAA==.Angryfyne:BAAANQAECggICAAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hXGUgArAgABAAgK4hXGUgArAgAGAAYKyQoSQwAbAQAAAA==.Anowon:BAAANQAECggIAQABNQAECggICAAOAAAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgoKKgAEAFUkAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgkJGwALAK0IAA==.Arkanis:BAABNQAECn89AAIPAAoK3RMiBQAQAgAPAAoK3RMiBQAQAgAAAA==.Armament:BAABNQAECn81AAIJAAoKjRSHXAB2AgAJAAoKjRSHXAB2AgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggIEAABNQAECggIFwAQAC0KAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn9CAAIRAAoKNiJqDgBuAwARAAoKNiJqDgBuAwAAAA==.Aurius:BAAANQAECggIEAAAAA==.',
Av='Avalancha:BAABNQAECn8oAAIFAAgKqxcYFQAWAgAFAAgKqxcYFQAWAgAAAA==.Avinoch:BAABNQAECn8ZAAIFAAcKkAbWLQCwAAAFAAcKkAbWLQCwAAAAAA==.',
Ax='Axon:BAAANQAECggIEAAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAOAAAAAA==.',
Az='Azekor:BAAANQADCggIEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIIAAgKDhoFQwAPAgAIAAgKDhoFQwAPAgAAAA==.',
Ba='Babykay:BAAANQADCgUIDQABNQAECgkJNAASAPweAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAABNQAECn8XAAITAAkKbw1MDQBiAQATAAkKbw1MDQBiAQAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAOAAAAAA==.Bartholomäus:BAAANQAECgYIBgAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAAANQAECgQICwABNQAECgkJGgAUAHwNAA==.',
Be='Beezlebumon:BAABNQAECn80AAMIAAkKIhcDEQARAgAIAAkKIhcDEQARAgAVAAEKmAmYzAAxAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgQIBAAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgYIBQAAAA==.Bewater:BAABNQAECn8vAAIRAAkKYRhNMAAfAgARAAkKYRhNMAAfAgAAAA==.',
Bl='Blegh:BAAANQAFFAMIAwAAAA==.Bluberry:BAAANQADCgcIHgAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8lAAIIAAoKVB8OCgCAAgAIAAoKVB8OCgCAAgAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECn84AAMWAAoKOB0mKgC7AgAWAAoKOB0mKgC7AgASAAUKwAzFfwCfAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8RAAIBAAMKWx+xEQAVAQABAAMKWx+xEQAVAQA1AAQKfzQAAwEACgpJIMoUAL8CAAEACgpJIMoUAL8CAAYAAwrdE5tQAM8AAAAA.',
Br='Bracknor:BAABNQAECn8dAAIRAAgKKhF8fAAVAgARAAgKKhF8fAAVAgAAAA==.Brandonb:BAABNQAECn9MAAIXAAoKgyGNEwDCAgAXAAoKgyGNEwDCAgAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECgUIDAABNQAFFAYIFgARAFIaAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn8iAAIYAAoKcRsGDACvAgAYAAoKcRsGDACvAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECgYIEAAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.',
By='Bysokar:BAABNQAECn8nAAIZAAoKEBk4FQCqAgAZAAoKEBk4FQCqAgAAAA==.',
Ca='Cainfortea:BAAANQAECgIIBAAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Cakevoid:BAAANQAECgcIBwAAAA==.Calipal:BAABNQAECn8UAAILAAYKawWi5AClAAALAAYKawWi5AClAAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAABNQAECn8dAAIBAAoKdB3iQgBgAgABAAoKdB3iQgBgAgABNQAFFAYKCgAWAIkUAA==.Catalinasham:BAACNQAFFH8KAAIWAAYKiRRBDgBpAQAWAAYKiRRBDgBpAQA1AAQKfyIAAhYACgpzIv8XABMDABYACgpzIv8XABMDAAE1AAUUBgoKABYAiRQA.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUIEQAAAA==.',
Ch='Challengerz:BAAANQAECgYIDwAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIEAAAAA==.',
Ci='Cinderlily:BAABNQAECn8XAAMaAAcKTxOWEABhAQAaAAcKTxOWEABhAQAKAAQK/gVXGwCPAAAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAOAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8PAAMbAAQKZBlYBQCDAAAUAAQKmxWsGQAoAQAbAAIKZwxYBQCDAAA1AAQKfygABBQACgqbIu8ZAB8DABQACgqnIe8ZAB8DABsAAwq3Hh8MAL8AABwAAQoAAKknAE0AAAAA.Connery:BAAANQADCgYIJAAAAA==.Coryuchiha:BAAANQADCgYICgAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgUIBQAAAA==.Criturrpants:BAAANQAECggIDgAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAIXAAkKlRhUWgDLAgAXAAkKlRhUWgDLAgAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECn84AAIJAAoKiBmAQQDJAQAJAAoKiBmAQQDJAQAAAA==.',
['Cü']='Cüpcake:BAABNQAECn8aAAINAAoKSwgmKABXAQANAAoKSwgmKABXAQAAAA==.',
Da='Dababycar:BAABNQAECn8UAAMQAAgKRRIshACOAQAQAAcKxhAshACOAQALAAYKUQ0unwAWAQAAAA==.Dabbyduck:BAABNQAECn8iAAMUAAkK7BmONAC4AgAUAAkK7BmONAC4AgAbAAcKLg4fGQCjAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgUIBgAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQABCggIEgAAAA==.',
De='Deadincide:BAEBNQAECn8uAAMdAAoKfhMWJwCZAQAIAAkKsRMbQgATAgAdAAgKUg4WJwCZAQAAAA==.Deadstasheo:BAACNQAFFH8RAAIIAAQKKiPsAgAhAQAIAAQKKiPsAgAhAQA1AAQKfycAAggACgpyI5YYAPoCAAgACgpyI5YYAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn8pAAILAAkK1xXUVQC1AQALAAkK1xXUVQC1AQAAAA==.Deezmonz:BAAANQAECgYICgABNQAECgoKSgAJACohAA==.Delik:BAABNQAECn8oAAIeAAgKPheNCQA6AgAeAAgKPheNCQA6AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgMIAwAAAA==.Deneol:BAABNQAECn8nAAMGAAoKShofEQDoAgAGAAoKShofEQDoAgAHAAEK3BG+JwA3AAAAAA==.Destrogen:BAACNQAFFH8GAAIcAAQKJArcAADoAAAcAAQKJArcAADoAAA1AAQKfywABBwACgoRHQ0CAFcCABwACQqqHg0CAFcCABQABArODSv2AN8AABsAAgqkDQFcAG4AAAAA.Desìre:BAABNQAECn8nAAIHAAgK+R40AwDJAgAHAAgK+R40AwDJAgAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECggIFwAQAC0KAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECn8uAAIIAAoKsB7/HQDXAgAIAAoKsB7/HQDXAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgUIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECggIDwAOAAAAAA==.Doomwing:BAAANQADCgYIBgAAAA==.',
Dr='Dracodeez:BAABNQAECn8aAAIfAAkKPhyFBgA/AgAfAAkKPhyFBgA/AgAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECn8mAAMIAAoKEB+CDgBEAwAIAAoKEB+CDgBEAwAVAAQKZBcXjwDHAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQAECgQIEQAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAAANQAECggIEQAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIEQAOAAAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQADCgQIBAAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgQIDQAOAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgcIDQABNQAECgoKIQAWAJ0ZAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8nAAMRAAgKoBXbYgB4AQARAAgKoBXbYgB4AQAgAAIKqRPADABJAAAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECggKLwAhAD0MAA==.',
Es='Eszran:BAAANQAECggIEwAAAA==.',
Eu='Euthanized:BAAANQAECgIIBwAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn89AAIVAAoKxh9aEgAaAwAVAAoKxh9aEgAaAwABNQAECgMIAwAOAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAYIFAAGAEwQAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAABNQAECn8aAAITAAkKIiXpAgDMAgATAAkKIiXpAgDMAgAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgcIEQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAABNQAECn8XAAIBAAgKrAQ8lQBWAQABAAgKrAQ8lQBWAQAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn89AAMhAAoK5hsBLwDUAQAhAAcKcRYBLwDUAQARAAYKyx2nagBkAQAAAA==.Frearyne:BAABNQAECn8qAAIEAAoKVSRUAgCpAwAEAAoKVSRUAgCpAwAAAA==.Frinu:BAAANQAECgQIBQABNQABCgIIAgAOAAAAAA==.Frogs:BAAANQADCggIKwAAAA==.Frostyshadow:BAABNQAECn8rAAIXAAkKESHGHABkAwAXAAkKESHGHABkAwAAAA==.Frozatresh:BAAANQAECgEIAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIZAAkKzBUdIwAOAgAZAAkKzBUdIwAOAgAAAA==.',
Fy='Fyxxer:BAAANQADCgIIAgABNQAFFAYIFAAGAEwQAA==.Fyxxie:BAACNQAFFH8UAAIGAAYKTBDRAwA0AQAGAAYKTBDRAwA0AQA1AAQKfzEAAwYACgr9HWQVALUCAAYACgr9HWQVALUCAAcAAQrYHm0hAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAABNQAECn8WAAIUAAkKRxEObAAZAgAUAAkKRxEObAAZAgAAAA==.',
Gi='Gialiana:BAABNQAECn8kAAIhAAoKcBVaFwBSAQAhAAoKcBVaFwBSAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAcIGAACACAlAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8eAAIPAAYKzR11DAD0AQAPAAYKzR11DAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAOAAAAAA==.Grully:BAABNQAECn8mAAIWAAoKgQwfZwDXAQAWAAoKgQwfZwDXAQAAAA==.',
Gu='Gurt:BAABNQAECn8XAAMcAAkKfg1HAwD1AQAcAAkKfg1HAwD1AQAbAAMKXAVKUACPAAAAAA==.Guzzug:BAABNQAECn9KAAIJAAoKKiHsFAC+AgAJAAoKKiHsFAC+AgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8jAAICAAgKxBt8GgCFAgACAAgKxBt8GgCFAgAAAA==.Hailsbelle:BAABNQAECn8aAAINAAkKTgVPPQDXAAANAAkKTgVPPQDXAAAAAA==.Harleymama:BAAANQABCgIIAgAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8uAAIfAAgKRRaaLQAvAgAfAAgKRRaaLQAvAgAAAA==.Helado:BAAANQAECgQIDQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highertotem:BAAANQADCgUIBAABNQAECgEIAQAOAAAAAA==.Highwayman:BAAANQAECgUICgABNQAECgoKTAARALojAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQAECgcIBwAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAABNQAECn8aAAILAAcKfxGFlgAlAQALAAcKfxGFlgAlAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIEQAAAA==.Ievil:BAABNQAECn8lAAMIAAgKMQxnLQAZAQAIAAgKMQxnLQAZAQAVAAEKAABK3QAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgoKSgANAMcjAA==.',
Im='Imjustpika:BAACNQAFFH8SAAIgAAYKGhFXAAAdAgAgAAYKGhFXAAAdAgA1AAQKfyUAAiAACgrDGvwEAH8CACAACgrDGvwEAH8CAAAA.',
In='Inawee:BAABNQAECn9MAAIEAAoK4h6oCQCrAgAEAAoK4h6oCQCrAgAAAA==.Inferniö:BAACNQAFFH8VAAIXAAYKth7uCAA5AgAXAAYKth7uCAA5AgA1AAQKf0AAAxcACgoTJR0QAJIDABcACgq0JB0QAJIDAB4AAQqwIhQhAGkAAAAA.Inkurushio:BAAANQAECgMIBAAAAA==.Intothefray:BAAANQADCgUICQAAAA==.',
Io='Iolanie:BAAANQAECgMIAwAAAA==.',
Is='Ismat:BAABNQAECn9MAAIWAAoK+A8hLwDoAQAWAAoK+A8hLwDoAQAAAA==.',
Ja='Jaeza:BAAANQADCggIKQABNQAECgcICgAOAAAAAA==.Jaqu:BAAANQAECgEIAQAAAA==.Jarshh:BAABNQAECn8aAAIPAAkKbh0gBAA+AgAPAAkKbh0gBAA+AgAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAABNQAECn8iAAQiAAoKtx10CQAoAgAiAAkK1h50CQAoAgAQAAMKSwSR/QCBAAALAAMKVBC5dgFmAAABNQAECgMIAwAOAAAAAA==.Juura:BAABNQAECn8mAAMbAAoKaxDHAwB7AQAbAAkKJBLHAwB7AQAUAAgK5QqaYwA7AQAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8jAAIQAAoKRx8KBwBaAwAQAAoKRx8KBwBaAwAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAABNQAECn8bAAIjAAoK6hHkLQDBAQAjAAoK6hHkLQDBAQAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAABNQAECn8aAAMkAAcKHhs4BwBIAgAkAAcKHhs4BwBIAgAjAAQKDhLwVAAIAQAAAA==.',
Ke='Kelaan:BAABNQAECn8lAAMiAAkKCCNJBQCyAgAiAAkKCCNJBQCyAgALAAEKAAAuoQE2AAAAAA==.Kelimao:BAABNQAECn8WAAMDAAkKIAerLQAiAQADAAkKIAerLQAiAQAEAAEKmQkDWAA1AAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAABNQAECn8jAAIEAAoKOR9rCgCYAgAEAAoKOR9rCgCYAgAAAA==.Kiserys:BAABNQAECn8WAAMlAAcKJhAeGgCnAQAlAAcKJhAeGgCnAQAaAAQK/xHWNQDlAAAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Koombah:BAAANQADCgQIBAAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECn8lAAIRAAgKgAoekADpAQARAAgKgAoekADpAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUICAAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
Ky='Kyllista:BAAANQADCggICAAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Laquisha:BAAANQAECgEIAQAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilatharia:BAAANQABCgIIAgAAAA==.Lilbowar:BAAANQAECgEIAQAAAA==.Lillath:BAAANQABCgQIBgAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECn9fAAMLAAoKOiJYHwBGAwALAAoKOiJYHwBGAwAiAAQK6SChLACqAAAAAA==.Lorenth:BAABNQAECn8aAAIBAAkKDgXuXgA7AQABAAkKDgXuXgA7AQAAAA==.Lorgoza:BAAANQADCggICAAAAA==.',
Lu='Lucerza:BAAANQADCggICAABNQAECgoKGgANAEQTAA==.Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
Lv='Lvcky:BAAANQADCgIIAgAAAA==.',
['Lì']='Lìte:BAABNQAECn8jAAICAAgKbQ5+HQBAAQACAAgKbQ5+HQBAAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn82AAMjAAkKzQl7HwDUAQAjAAkKzQl7HwDUAQAfAAEKhgfmXAAwAAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAAVAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwAXABEhAA==.Malidros:BAAANQAECgYICgAAAA==.Malign:BAABNQAECn8jAAMfAAoKPiOtAwCcAwAfAAkKiSOtAwCcAwAjAAkK2SBeEAClAgABNQAFFAcIGAACACAlAA==.Manhatten:BAAANQAECgQIBQAAAA==.Marhault:BAABNQAECn9MAAMRAAoKuiNoBQA4AwARAAoKtyNoBQA4AwAgAAUKbR9MCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAIVAAkK7RvZJACTAgAVAAkK7RvZJACTAgAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8aAAILAAYKbxGb2ABqAQALAAYKbxGb2ABqAQAAAA==.Mazah:BAABNQAECn9MAAMSAAoKmhgLGQA1AgASAAoKmhgLGQA1AgAWAAIKlQInDAFQAAAAAA==.Mazlo:BAACNQAFFH8FAAIeAAMKnxBJCACXAAAeAAMKnxBJCACXAAA1AAQKf0UAAx4ACgosHxAEAPUCAB4ACgosHxAEAPUCABcAAgrrAP3DATgAAAAA.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgoKSgAJACohAA==.Mellethir:BAABNQAECn8yAAMXAAoKxQlv5gC9AQAXAAoKxQlv5gC9AQAeAAIK1gk0HwBzAAAAAA==.Messalina:BAAANQAECgUIBQABNQAECgYICgAOAAAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgcIDAAAAA==.Minipimp:BAAANQADCgYIGAAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAAANQAECgYIEwAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8qAAIRAAgKxx+GKwAyAgARAAgKxx+GKwAyAgAAAA==.Moglayn:BAABNQAECn9HAAIVAAoKvyXpAQDWAwAVAAoKvyXpAQDWAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAImAAQKWQ1uBgD4AAAmAAQKWQ1uBgD4AAA1AAQKfxsAAiYACQpOGnENACQCACYACQpOGnENACQCAAE1AAUUBggQABUAhA8A.Monorìth:BAEBNQAFFH8QAAIVAAYKhA9uDgBtAQAVAAYKhA9uDgBtAQAAAA==.Morninstar:BAAANQADCgMIAwAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgQIBAAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgkJNgAjAM0JAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIEQABNQABCggIFgAOAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQAECgYIDgAAAA==.Nastyiam:BAACNQAFFH8HAAIYAAMK7wXRAgDRAAAYAAMK7wXRAgDRAAA1AAQKfzIAAhgACgrJFb0IACoCABgACgrJFb0IACoCAAAA.',
Ne='Nerfornothin:BAABNQAECn8fAAIRAAkKZwY6eQBCAQARAAkKZwY6eQBCAQAAAA==.Nethbubble:BAAANQAECgEIAQABNQAECgoKLAAaAFIQAA==.Nethflap:BAABNQAECn8sAAIaAAoKUhA8GwAUAgAaAAoKUhA8GwAUAgAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCggIIgAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECn8pAAIWAAoKCBpKMQCcAgAWAAoKCBpKMQCcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAACNQAFFH8FAAIYAAMKjhUNAgDzAAAYAAMKjhUNAgDzAAA1AAQKfzYAAhgACgpvJL8BAJwDABgACgpvJL8BAJwDAAAA.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgIIAwAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.',
Os='Osanyin:BAAANQADCgQIBAABNQAECgYICgAOAAAAAA==.',
Ou='Outstanding:BAAANQAECgUIBgABNQAECgcIKwABANwiAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECggIDwAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgIIAgAAAA==.Pikagosa:BAAANQABCgEIAQABNQAFFAYIEgAgABoRAA==.Pilgor:BAABNQAECn8dAAMKAAoKDA2aDACKAQAKAAkKXg6aDACKAQAaAAoKYwYZDwB/AQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAOAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQICQAAAA==.Polkovnik:BAABNQAECn8fAAIJAAkKVRvFZQBeAgAJAAkKVRvFZQBeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEBNQAECn8cAAIXAAcKZgUMrgDrAAAXAAcKZgUMrgDrAAABNQAECgoKLgAdAH4TAA==.Quickfinger:BAAANQAECggIAQAAAA==.Quiniustius:BAAANQAECgQIBQAAAA==.',
Ra='Ragingpwner:BAAANQADCgUIBgAAAA==.Rallyn:BAAANQADCggICAAAAA==.Ramacondama:BAAANQADCgEIAQABNQAECggINwAMAHsiAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECgkJNAASAPweAA==.Ravel:BAABNQAECn8aAAInAAkKdBroCAA4AgAnAAkKdBroCAA4AgAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECn80AAMSAAkK/B6AKADfAgASAAkK/B6AKADfAgAYAAIKtgK0JQBaAAAAAA==.Reios:BAABNQAECn8wAAIUAAoKgxnmIQA0AgAUAAoKgxnmIQA0AgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhastaman:BAAANQAECgEIAQABNQAECgoKNQAJAI0UAA==.Rhaz:BAABNQAECn8lAAMQAAgKtwz7VQBCAQAQAAgKtwz7VQBCAQALAAEKAADpvAEqAAAAAA==.Rheeannon:BAAANQABCgQIBgAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECggIFwAgACcaAA==.',
Ri='Rickyspanish:BAABNQAECn86AAICAAoK3R2FDQANAwACAAoK3R2FDQANAwAAAA==.Rifter:BAAANQAECgMICAAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAOAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgoKLgAdAH4TAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Rollnine:BAAANQAECgEIAQAAAA==.Romeric:BAAANQADCggIDgAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Ronuswanson:BAAANQADCgcIGgAAAA==.Roupert:BAABNQAECn8XAAIgAAgKJxq7BQBXAgAgAAgKJxq7BQBXAgAAAA==.',
Ru='Rubyouraw:BAAANQAECgcIDQAAAA==.Ruffneck:BAABNQAECn8nAAIRAAgKWBRUaABDAgARAAgKWBRUaABDAgAAAA==.Russk:BAAANQAECgYIBwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICwAAAA==.',
Sa='Saelaan:BAABNQAECn8fAAImAAcKVx4eDABDAgAmAAcKVx4eDABDAgABNQAECgkJJQAiAAgjAA==.Sailfu:BAACNQAFFH8WAAIZAAcKJCCeAQDBAQAZAAcKJCCeAQDBAQA1AAQKfy4AAhkACgo1JcgFAHQDABkACgo1JcgFAHQDAAE1AAUUBwgYAAIAICUA.Saiyurie:BAAANQABCgIIAgAAAA==.Sakrine:BAAANQAECgIIAQAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAABNQAECn8iAAIGAAcKvB7cHQBRAgAGAAcKvB7cHQBRAgAAAA==.Sandarr:BAABNQAECn8fAAIiAAcK+Ri3IgDMAQAiAAcK+Ri3IgDMAQAAAA==.Sanguinne:BAABNQAECn8YAAIbAAcKBwlMCgDQAAAbAAcKBwlMCgDQAAAAAA==.Santhus:BAABNQAECn8YAAIjAAgK0A6wKQB3AQAjAAgK0A6wKQB3AQAAAA==.Sarabela:BAAANQADCggICAABNQAECgcIHwAiAPkYAA==.Saretae:BAAANQADCggIHQABNQAFFAYIFQAXALYeAA==.Sargemarge:BAABNQAECn8dAAIWAAkKICMxDQBXAwAWAAkKICMxDQBXAwAAAA==.Sarume:BAAANQAECggICwABNQAECggINwAMAHsiAA==.',
Sc='Sci:BAABNQAECn8tAAIQAAgKGyUPEABLAwAQAAgKGyUPEABLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAABNQAECgMIAwAOAAAAAA==.Selener:BAAANQAECggIDAAAAA==.Serbitar:BAAANQAECgUIBQABNQAECgoKJgAIABAfAA==.Serrata:BAABNQAECn8eAAIRAAgKIB34MAAcAgARAAgKIB34MAAcAgAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCggIEAAAAA==.Shadowplay:BAEANQADCggIGgABNQAECgoKLgAdAH4TAA==.Shamski:BAAANQAECgMIAgABNQAECgYICgAOAAAAAA==.Shamydavisjr:BAAANQABCggIFgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIBAAAAA==.Shathice:BAAANQADCgIIAgABNQAECgoKIwAQAEcfAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.Shocky:BAAANQABCgEIAQABNQADCgIIAgAOAAAAAA==.',
Si='Sidelvar:BAAANQABCggIFAAAAA==.Silandros:BAAANQAECgYIBwAAAA==.Silther:BAABNQAECn8ZAAIiAAkKnBbYDgCwAQAiAAkKnBbYDgCwAQAAAA==.',
Sk='Skarath:BAABNQAECn8cAAQPAAUK+wcqJACSAAATAAQKzwooMQCtAAAPAAUKoAQqJACSAAAJAAQKXAPj3gBVAAAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAABNQAECn8iAAIEAAcKdA0DOQBWAQAEAAcKdA0DOQBWAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn8tAAIWAAkKfRoOJgAdAgAWAAkKfRoOJgAdAgAAAA==.Sorrowsöng:BAABNQAECn8ZAAILAAkKrhiTSADeAQALAAkKrhiTSADeAQAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAOAAAAAA==.Southvik:BAAANQAECgcICwABNQAECgcIKwABANwiAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAMIEQABAFsfAA==.Sparrhawk:BAAANQAECgMIBQAAAA==.Spiced:BAACNQAFFH8FAAIDAAMKSiFABwAmAQADAAMKSiFABwAmAQA1AAQKfyYAAgMACgolIhAOAFoDAAMACgolIhAOAFoDAAAA.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAABNQAECn80AAMGAAoKnQ6nEgCfAQAGAAoKnQ6nEgCfAQAHAAUKkRP2DgA9AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Stabussy:BAAANQAECgIIAwABNQAECgcIEQAOAAAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQAECgQIBAAAAA==.Stingella:BAAANQADCgUIBwAAAA==.Stormclaw:BAAANQAECgYIBwABNQAECgkJFgAUAEcRAA==.Stormfall:BAAANQADCgYIEQAAAA==.Sttriker:BAABNQAECn8gAAINAAoKFAT+OgDjAAANAAoKFAT+OgDjAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgQIBAAOAAAAAA==.',
Sy='Synsairis:BAABNQAECn8aAAIZAAkKKQ1dGAByAQAZAAkKKQ1dGAByAQAAAA==.',
Ta='Talenelat:BAAANQAECgIIAQAAAA==.Talonknight:BAABNQAECn8iAAMKAAcKOQyxEQAaAQAKAAcK3AuxEQAaAQAlAAUK1QauKQDdAAAAAA==.Talset:BAAANQADCgIIAgAAAA==.Tau:BAAANQAECggIEwAAAA==.Tauria:BAAANQABCggIGwAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgMIBwAAAA==.',
Te='Tempedsoul:BAAANQABCgcIDQAAAA==.',
Th='Thaendofyou:BAAANQAECggICwAAAA==.Thalassia:BAAANQAECgIIAgAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQAECgQIDQAAAA==.Thellan:BAAANQADCgYIBgAAAA==.Themonk:BAAANQADCggICgABNQAECggILgAVAIMWAA==.Therise:BAABNQAECn8gAAMMAAgKpQ7hFABeAQAMAAcKsg/hFABeAQANAAEKYwnRZgA5AAABNQAECgoKTAASAJoYAA==.Thetank:BAABNQAECn8uAAMVAAgKgxZYQgDzAQAVAAgKgxZYQgDzAQAIAAEKFAk9cAAwAAAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAABNQAECn8yAAIRAAoKUxTdLgAkAgARAAoKUxTdLgAkAgAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAOAAAAAA==.Thunderegg:BAAANQAECgUICgABNQAECgoKTAASAJoYAA==.Thundermaker:BAAANQAECgUICwABNQAECgoKJgAIABAfAA==.',
Ti='Timotthy:BAABNQAECn8pAAQFAAgKXiBDEwAvAgAFAAYKPiBDEwAvAgAoAAcKxx7zCwB1AQADAAEKAACBygAXAAAAAA==.Tixxle:BAAANQADCggIGAAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgcICQABNQAFFAQIDwAbAGQZAA==.',
Tr='Treateak:BAAANQAECgQIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAABNQAECn8VAAISAAkKvBsBLwDAAgASAAkKvBsBLwDAAgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn9LAAIhAAoKLhkMEQDfAgAhAAoKLhkMEQDfAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAABNQAECn8YAAIeAAcKdBnWCQAxAgAeAAcKdBnWCQAxAgAAAA==.Tyriem:BAABNQAECn8hAAIRAAoKVBRXQACqAgARAAoKVBRXQACqAgAAAA==.Tyssanton:BAABNQAECn8gAAMlAAgKoAONIwAnAQAlAAgKoAONIwAnAQAaAAcK4gM7MQARAQAAAA==.',
Tz='Tziganin:BAABNQAECn8YAAISAAkKdxMyLQCoAQASAAkKdxMyLQCoAQAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgoKIwAQAEcfAA==.',
Un='Unholybussy:BAAANQAECgcIDwAAAA==.',
Ut='Utaadh:BAABNQAECn8pAAINAAkKSRJwNwD1AQANAAkKSRJwNwD1AQAAAA==.',
Va='Vael:BAAANQAECgUIDgABNQAECgoKSgANAMcjAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAOAAAAAA==.Vallderossa:BAAANQADCggIFAAAAA==.Vallerin:BAABNQAECn8mAAIYAAkK9BQaDQDBAQAYAAkK9BQaDQDBAQAAAA==.Vanek:BAAANQAECgEIAQAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgoKSgANAMcjAA==.Velazar:BAAANQADCgMIAwAAAA==.Verras:BAAANQADCgEIAQAAAA==.',
Vi='Vicente:BAAANQAECggICwAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQADCgUIBgABNQAECgcIKwABANwiAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8WAAIRAAYKUhoQBQAGAgARAAYKUhoQBQAGAgA1AAQKfzAABBEACgpbIIEwANsCABEACgpbIIEwANsCACEAAQpBGIqBAEEAACAAAQoAAGwTADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8mAAIVAAgKYRsPLQBiAgAVAAgKYRsPLQBiAgAAAA==.',
Wa='Wagwan:BAABNQAECn8YAAMIAAoKyBh5DgA0AgAIAAoKTxh5DgA0AgAdAAIKXCDegwCfAAAAAA==.Walls:BAABNQAECn8bAAILAAkKrQij3ABiAQALAAkKrQij3ABiAQAAAA==.Wardrik:BAAANQADCgUIBQAAAA==.Waste:BAABNQAECn8bAAMUAAkK9BxYNQDVAQAUAAkKPxxYNQDVAQAbAAIKtxWoHQBWAAAAAA==.Wawel:BAABNQAECn8qAAQlAAoKUh48BgDWAQAlAAkKWR08BgDWAQAaAAYKkCDXIQC+AQAKAAQKAxk+FADrAAAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggILQAQABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgQICwAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.Winstagram:BAAANQADCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgUIBQAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIFgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xi='Xibaba:BAAANQAECgEIAQAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAABNQAECn81AAIYAAoKexmwDwBuAgAYAAoKexmwDwBuAgAAAA==.Yokos:BAAANQAECgEIAQAAAA==.Yoursummons:BAAANQAECgEIAQABNQAECgcIEQAOAAAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zafiel:BAAANQADCgcIBwAAAA==.Zahneel:BAABNQAECn8YAAMEAAkKoQ8nHACDAQAEAAkKoQ8nHACDAQAFAAEKAADOagAjAAAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8NAAILAAUK/hv3DgBdAQALAAUK/hv3DgBdAQA1AAQKfzwAAgsACgqyJE0NAJkDAAsACgqyJE0NAJkDAAAA.Zarisong:BAAANQAECgcIDgABNQAECggIGAAjANAOAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgcICwAAAA==.',
Zo='Zoburg:BAAANQAECgQIBwABNQAECgcIKwABANwiAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAOAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQAECgQIBQAAAA==.',
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
