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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Paladin-Holy','Warlock-Destruction','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Evoker-Preservation','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Mage-Frost','Monk-Mistweaver','Rogue-Assassination','Hunter-Survival','Druid-Feral','Paladin-Protection','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aassvik:BAABNQAECn8wAAIBAAgKNyJhLgCuAgABAAgKNyJhLgCuAgAAAA==.',
Ab='Absolute:BAACNQAFFH8YAAICAAcKICXdAAD2AQACAAcKICXdAAD2AQA1AAQKfzIAAgIACgpHJu4AAHcDAAIACgpHJu4AAHcDAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8RAAMDAAcKKhpTCQDqAQADAAcKKhpTCQDqAQAEAAEK1AA1GQAwAAA1AAQKfz8ABAMACgrsJYECAF8DAAMACgrsJYECAF8DAAQABgp/EIU7AEQBAAUAAQoAALxtACAAAAAA.Achievsome:BAABNQAECn85AAQGAAoKBCWuAwCfAwAGAAoKBCWuAwCfAwABAAcKthUaiQB7AQAHAAIKwBA1EgBMAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesodx:BAAANQAECgcICAABNQAECgoKGQAIAMgYAA==.Aesomx:BAAANQAECgIIAgABNQAECgoKGQAIAMgYAA==.Aesoxp:BAABNQAECn8UAAIJAAoKSh+uBgCVAwAJAAoKSh+uBgCVAwABNQAECgoKGQAIAMgYAA==.Aethalas:BAAANQADCgEIAQAAAA==.',
Ag='Agrajag:BAAANQADCgUIBwABNQAECgoKFgAKAK4OAA==.',
Ah='Ahjbastet:BAAANQAECgUIBQAAAA==.Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBQAAAA==.',
Ak='Akagrats:BAAANQADCgEIAgAAAA==.',
Al='Alassar:BAAANQAECgcIDgAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIFAAAAA==.Alessandro:BAABNQAECn8UAAILAAgKxgkqDgBlAQALAAgKxgkqDgBlAQAAAA==.Algas:BAAANQAECgIIBQAAAA==.Aliengrey:BAAANQAECgcIEAAAAA==.Alindrin:BAAANQADCgEIAQAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8tAAIMAAoKjBMTcwBIAgAMAAoKjBMTcwBIAgAAAA==.Alrsta:BAAANQADCgIIAgAAAA==.Alunarteil:BAAANQAECgMIAwAAAA==.',
Am='Amane:BAABNQAECn87AAMNAAgK1CLSBgCnAgANAAgK1CLSBgCnAgAOAAgK5hn2NwDxAQAAAA==.American:BAAANQAECgMIBAAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQADCggIDgAAAA==.',
An='Anger:BAAANQADCggIDQAAAA==.Angryfyne:BAAANQAECggICAAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hXGUgArAgABAAgK4hXGUgArAgAGAAYKyQoSQwAbAQAAAA==.Anowon:BAAANQAECggIAgABNQAECggICAAPAAAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgoKLgAEAIwkAA==.Archtrishop:BAAANQADCgEIAgAAAA==.Aristae:BAAANQADCgEIAwABNQAECgkJIgAMADsMAA==.Arkanis:BAABNQAECn9GAAIQAAoK+BbsBQA2AgAQAAoK+BbsBQA2AgAAAA==.Arkherym:BAAANQADCggICAAAAA==.Armament:BAABNQAECn87AAIRAAoKHRWHXAB2AgARAAoKHRWHXAB2AgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggIEAABNQAECggIFwAJAC0KAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn9NAAISAAoKXCNUCwAaAwASAAoKXCNUCwAaAwAAAA==.Aurius:BAAANQAECggIEAAAAA==.',
Av='Avalancha:BAABNQAECn8vAAIFAAkKGxcYFQAWAgAFAAkKGxcYFQAWAgAAAA==.Avinoch:BAABNQAECn8fAAIFAAcKogZ4OACvAAAFAAcKogZ4OACvAAAAAA==.',
Ax='Axon:BAABNQAECn8bAAIEAAoK6w9nJQD4AQAEAAoK6w9nJQD4AQAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAPAAAAAA==.',
Az='Azekor:BAAANQADCggIFAAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIIAAgKDhoFQwAPAgAIAAgKDhoFQwAPAgAAAA==.',
Ba='Babykay:BAAANQAECgEIAQABNQAECgkJNwATAPweAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAABNQAECn8YAAIUAAkKrA0cEgBbAQAUAAkKrA0cEgBbAQAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAPAAAAAA==.Bartholomäus:BAAANQAECgYICAAAAA==.Batmack:BAAANQADCgEIAQAAAA==.',
Bb='Bbshagoogoo:BAABNQAECn8aAAIRAAkK1wk4pwD2AAARAAkK1wk4pwD2AAAAAA==.',
Be='Beezlebumon:BAABNQAECn86AAMIAAkKWxdVFgAOAgAIAAkKWxdVFgAOAgAVAAIKZgs0kwAzAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellattrix:BAAANQAECgEIAwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgUIBgAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgYIBQAAAA==.Bewater:BAABNQAECn8vAAISAAkKYRgmRwAHAgASAAkKYRgmRwAHAgAAAA==.',
Bl='Blegh:BAABNQAFFH8GAAMSAAMKYQr5EgDYAAASAAMK9Qn5EgDYAAAWAAIKvQRoEwB2AAAAAA==.Bluberry:BAAANQAECgEIAgAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8lAAIIAAoKVB/ZDgBoAgAIAAoKVB/ZDgBoAgAAAA==.Boombastic:BAAANQAECgEIAQAAAA==.Boomchicken:BAAANQADCgMIBAAAAA==.Boomclap:BAABNQAECn89AAMXAAoK6B0mKgC7AgAXAAoK6B0mKgC7AgATAAUKwAyKmgCeAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8RAAIBAAMKWx+3FgARAQABAAMKWx+3FgARAQA1AAQKfzwAAwEACgo6IqEZANwCAAEACgo6IqEZANwCAAYABQq6GQotAOUAAAAA.',
Br='Bracknor:BAABNQAECn8dAAISAAgKKhF8fAAVAgASAAgKKhF8fAAVAgAAAA==.Brakbull:BAAANQAECgEIAQAAAA==.Brakdread:BAAANQAECgEIAgAAAA==.Brakjin:BAAANQAECgEIAQAAAA==.Braklock:BAAANQAECgEIAQAAAA==.Braknight:BAAANQAECgEIAwAAAA==.Brandonb:BAABNQAECn9WAAIYAAoKCyLtHwBaAwAYAAoKCyLtHwBaAwAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECggIEAABNQAFFAYIFgASAFIaAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn8oAAIZAAoKDB11CABwAgAZAAoKDB11CABwAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECggIEgAAAA==.Bryanthesly:BAAANQADCggIFQAAAA==.Brynnbramble:BAAANQAECgEIAQAAAA==.',
By='Bysokar:BAABNQAECn8rAAIaAAoKcBs4FQCqAgAaAAoKcBs4FQCqAgAAAA==.',
Ca='Cainfortea:BAAANQAECgIIBAAAAA==.Cakel:BAAANQADCgcICAAAAA==.Cakevoid:BAAANQAECgcIDAAAAA==.Calipal:BAABNQAECn8aAAIMAAcKpQdr5QDXAAAMAAcKpQdr5QDXAAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAABNQAECn8hAAIBAAoKyh0REAAxAwABAAoKyh0REAAxAwABNQAFFAYKCgAXAIkUAA==.Catalinasham:BAACNQAFFH8KAAIXAAYKiRRBDgBpAQAXAAYKiRRBDgBpAQA1AAQKfyoAAhcACgqtIqYLAEgDABcACgqtIqYLAEgDAAE1AAUUBgoKABcAiRQA.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAgAAAA==.Cerberusbone:BAABNQAECn8YAAMVAAgKihHQPAAkAQAVAAcKWhDQPAAkAQAIAAYKxQxsfgAjAQAAAA==.',
Ch='Challengerz:BAAANQAECgYIEQAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIEAAAAA==.Chritiane:BAAANQAECgUIBQAAAA==.',
Ci='Cinderlily:BAABNQAECn8dAAMbAAcK2BRPFABvAQAbAAcK2BRPFABvAQALAAQK/gVXGwCPAAAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDgAPAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8PAAMKAAQKZBnCBgB7AAAcAAQKmxWsGQAoAQAKAAIKZwzCBgB7AAA1AAQKfygABBwACgqbIu8ZAB8DABwACgqnIe8ZAB8DAAoAAwq3HpEQALgAAB0AAQoAAKknAE0AAAAA.Connery:BAAANQAECgEIAgAAAA==.Cornpopp:BAAANQAECgEIAQAAAA==.Coryuchiha:BAAANQADCgYIDgAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crippleya:BAAANQAECgEIAQAAAA==.Crissmee:BAAANQADCgEIAQAAAA==.Crithappens:BAAANQAECgUIBgAAAA==.Criturrpants:BAAANQAECggIEQAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAIYAAkKlRhUWgDLAgAYAAkKlRhUWgDLAgAAAA==.Cynthea:BAAANQAECgQIBAAAAA==.Cyp:BAABNQAECn9EAAIRAAoK5xkZMABYAgARAAoK5xkZMABYAgAAAA==.',
['Cü']='Cüpcake:BAABNQAECn8kAAIOAAoK8wtIJgCbAQAOAAoK8wtIJgCbAQAAAA==.',
Da='Dababycar:BAABNQAECn8WAAMJAAgKVRMshACOAQAJAAcK/REshACOAQAMAAYKUQ03ywABAQAAAA==.Dabbyduck:BAABNQAECn8iAAMcAAkK7BmONAC4AgAcAAkK7BmONAC4AgAKAAcKLg4fGQCjAQAAAA==.Daelaora:BAAANQADCgEIAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgUIBgAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQADCggIDgAAAA==.',
De='Deadincide:BAEBNQAECn82AAMIAAoKfhMbQgATAgAIAAkKsRMbQgATAgAeAAkKmw3zLQC5AQAAAA==.Deadstasheo:BAACNQAFFH8WAAIIAAUK0RvdAQBxAQAIAAUK0RvdAQBxAQA1AAQKfygAAggACgpyI5YYAPoCAAgACgpyI5YYAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn8wAAIMAAkKgxcNZgDIAQAMAAkKgxcNZgDIAQAAAA==.Deezmonz:BAABNQAECn8WAAMKAAoKrg4KEwCnAAAcAAkK6Q3ViwAOAQAKAAMKaxAKEwCnAAAAAA==.Delik:BAABNQAECn8vAAIfAAkKaRWNCQA6AgAfAAkKaRWNCQA6AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICwAAAA==.Demonlordmeh:BAAANQADCgUICgAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgQIAwAAAA==.Deneol:BAABNQAECn8nAAMGAAoKShofEQDoAgAGAAoKShofEQDoAgAHAAEK3BG+JwA3AAAAAA==.Destrogen:BAACNQAFFH8KAAMdAAQK5hqTAQD0AAAdAAQKABaTAQD0AAAcAAEKTB5gKABZAAA1AAQKfzQABB0ACgqjHycCAKECAB0ACgqjHycCAKECABwABArODSv2AN8AAAoAAgqkDQFcAG4AAAAA.Desìre:BAABNQAECn8uAAMHAAkKzR40AwDJAgAHAAgKfx80AwDJAgABAAMKIRq0lADjAAAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECggIFwAJAC0KAA==.',
Di='Diabolic:BAAANQADCggICQAAAA==.Dipndodge:BAAANQADCgEIAQAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIBAAAAA==.',
Dk='Dksura:BAABNQAECn8vAAIIAAoKsB7/HQDXAgAIAAoKsB7/HQDXAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgUIBQAAAA==.Doomshroud:BAAANQADCgEIAQABNQAECgkJFQAgAKwNAA==.Doomwing:BAAANQADCgYIBgAAAA==.',
Dr='Dracodeez:BAABNQAECn8fAAIhAAoK6xpYBwBaAgAhAAoK6xpYBwBaAgAAAA==.Driretlan:BAAANQADCgYICAAAAA==.Druss:BAABNQAECn8oAAMIAAoKEB+CDgBEAwAIAAoKEB+CDgBEAwAVAAQKZBcXjwDHAAAAAA==.',
Du='Dulzectus:BAAANQADCgEIAQAAAA==.Dumbledog:BAAANQADCgEIAQAAAA==.Durunk:BAABNQAECn8XAAIXAAYKZwoxkgDRAAAXAAYKZwoxkgDRAAAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAABNQAECn8ZAAIaAAgKYxDhMACQAQAaAAgKYxDhMACQAQAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIGQAaAGMQAA==.',
Ec='Eclipcees:BAAANQADCgQIAwAAAA==.',
Ei='Eileen:BAAANQADCgEIAQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQAECgEIAQAAAA==.',
Em='Emilianaluz:BAAANQAECgEIAQAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgUIEgAPAAAAAA==.',
Er='Eradion:BAAANQADCggIDgAAAA==.Eredarlord:BAAANQAECgcIDgABNQAECgoKIQAXAJ0ZAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8pAAMSAAgKuBYigQBvAQASAAgKuBYigQBvAQAiAAIKqROZDwBIAAAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECgkKOgAWAHcNAA==.',
Es='Eszran:BAABNQAECn8iAAIjAAoKaBLeCgDdAQAjAAoKaBLeCgDdAQAAAA==.',
Eu='Euthanized:BAAANQAECgIIBwAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn8/AAIVAAoKxh9aEgAaAwAVAAoKxh9aEgAaAwABNQAECgMIAwAPAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAYIFAAGAEwQAA==.',
Fi='Fiadh:BAAANQADCgQIBQAAAA==.Fiendishtwin:BAAANQADCgMIBAAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAABNQAECn8aAAIUAAkKIiVEBAC7AgAUAAkKIiVEBAC7AgAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAABNQAECn8XAAIfAAkKGAhKEQA3AQAfAAkKGAhKEQA3AQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAABNQAECn8eAAIBAAkKSgqQXwCHAQABAAkKSgqQXwCHAQAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn9DAAMWAAoKNhwMGQCCAQAWAAoKexQMGQCCAQASAAYKyx2yjQBTAQAAAA==.Frearyne:BAABNQAECn8uAAIEAAoKjCRUAgCpAwAEAAoKjCRUAgCpAwAAAA==.Frinu:BAAANQAECgQIBQABNQABCgIIAgAPAAAAAA==.Frogs:BAAANQADCggILAAAAA==.Frostyshadow:BAABNQAECn8rAAIYAAkKESHGHABkAwAYAAkKESHGHABkAwAAAA==.Frozatresh:BAAANQAECgEIAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIaAAkKzBUdIwAOAgAaAAkKzBUdIwAOAgAAAA==.',
Fy='Fyxxer:BAAANQADCgIIAgABNQAFFAYIFAAGAEwQAA==.Fyxxie:BAACNQAFFH8UAAIGAAYKTBBcBQAnAQAGAAYKTBBcBQAnAQA1AAQKfzYAAwYACgo+HmQVALUCAAYACgo+HmQVALUCAAcAAQrYHm0hAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Gi='Gialiana:BAABNQAECn8oAAIWAAoKcBXLHgA/AQAWAAoKcBXLHgA/AQAAAA==.Githryn:BAAANQADCgEIAQAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAcIGAACACAlAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8fAAIQAAYKzR11DAD0AQAQAAYKzR11DAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.Grully:BAABNQAECn8qAAIXAAoKgQwfZwDXAQAXAAoKgQwfZwDXAQAAAA==.',
Gu='Gurt:BAABNQAECn8eAAMdAAkKaRCPBQDpAQAdAAkKaRCPBQDpAQAKAAMKXAVKUACPAAAAAA==.Guzzug:BAABNQAECn9KAAIRAAoKKiHfIACiAgARAAoKKiHfIACiAgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8qAAICAAkKZht8GgCFAgACAAkKZht8GgCFAgAAAA==.Hailsbelle:BAABNQAECn8eAAIOAAkKAAYZRADkAAAOAAkKAAYZRADkAAAAAA==.Harleymama:BAAANQAECgEIAQAAAA==.Hashtag:BAAANQADCgUIEgAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8xAAIhAAkKXxeaLQAvAgAhAAkKXxeaLQAvAgAAAA==.Helado:BAAANQAECgUIDwAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highertotem:BAAANQADCgUIBAABNQAECgEIAwAPAAAAAA==.Highwayman:BAAANQAECgUICgABNQAECgoKVgASALojAA==.',
Ho='Holyling:BAAANQADCgYIBwAAAA==.Holys:BAAANQAECgcICQAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAABNQAECn8gAAIMAAcK0BK4rwAwAQAMAAcK0BK4rwAwAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIFwAAAA==.Ievil:BAABNQAECn8rAAMIAAgKSwwlNwATAQAIAAgKSwwlNwATAQAVAAEKAABK3QAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgoKVAAOABQkAA==.',
Im='Imjustpika:BAACNQAFFH8TAAIiAAcKgw5XAAAdAgAiAAcKgw5XAAAdAgA1AAQKfygAAiIACgp9HPwEAH8CACIACgp9HPwEAH8CAAAA.',
In='Inawee:BAABNQAECn9MAAIEAAoK4h7SDgDnAgAEAAoK4h7SDgDnAgAAAA==.Indolen:BAAANQADCgEIAQAAAA==.Inferniö:BAACNQAFFH8WAAMYAAcKBCDuCAA5AgAYAAYKth7uCAA5AgAfAAEKPSUdCABxAAA1AAQKf0gAAxgACgobJR0QAJIDABgACgq8JB0QAJIDAB8AAQqwIrkpAGUAAAAA.Inkurushio:BAAANQAECgMIBAAAAA==.Intothefray:BAAANQADCgUIDgAAAA==.',
Io='Iolanie:BAAANQAECgMIBQAAAA==.',
Is='Ismat:BAABNQAECn9WAAIXAAoKIhCRQADhAQAXAAoKIhCRQADhAQAAAA==.',
Ja='Jaeza:BAAANQAECgEIAgABNQAECgYICwAPAAAAAA==.Jamaicamon:BAAANQADCgEIAQAAAA==.Jaqu:BAAANQAECgEIAgAAAA==.Jarshh:BAABNQAECn8eAAIQAAkKuB3PBQA7AgAQAAkKuB3PBQA7AgAAAA==.',
Ji='Jinian:BAAANQADCgEIAwAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgIIAgAAAA==.',
Ju='Judge:BAABNQAECn8rAAQkAAoK6B2JCwBHAgAkAAkKDh+JCwBHAgAJAAMKSwSR/QCBAAAMAAMKVBC5dgFmAAABNQAECgMIAwAPAAAAAA==.Juura:BAABNQAECn8sAAMKAAoKuxAPBQB2AQAKAAkKJBIPBQB2AQAcAAgKCw3mdABDAQAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8mAAIJAAoKgR+GDABAAwAJAAoKgR+GDABAAwAAAA==.Karrog:BAAANQADCgEIAQAAAA==.Karsen:BAABNQAECn8cAAIlAAoK6hFFGAAaAgAlAAoK6hFFGAAaAgAAAA==.Kassian:BAAANQAECgEIAgAAAA==.Kaveros:BAABNQAECn8dAAMmAAgKoRg4BwBIAgAmAAcKHhs4BwBIAgAlAAYK4hAsYAA5AQAAAA==.',
Ke='Kelaan:BAABNQAECn8tAAMkAAkKayPNBgDBAgAkAAkKayPNBgDBAgAMAAEKAAAuoQE2AAAAAA==.Kelimao:BAABNQAECn8aAAMDAAkKyQcQNQAvAQADAAkKyQcQNQAvAQAEAAEKmQmgaAAvAAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQAECgEIAQAAAA==.Kiritos:BAABNQAECn8qAAIEAAoKZh/SCAAOAwAEAAoKZh/SCAAOAwAAAA==.Kirkuk:BAAANQADCgEIAgAAAA==.Kiserys:BAABNQAECn8bAAMnAAcKJhAeGgCnAQAnAAcKJhAeGgCnAQAbAAQK/xHWNQDlAAAAAA==.',
Ko='Koharu:BAAANQADCgEIAgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Koombah:BAAANQADCgQIBAAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAgAAAA==.',
Kr='Krysto:BAABNQAECn8sAAISAAkK2QoekADpAQASAAkK2QoekADpAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUICwAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
Ky='Kyllista:BAAANQADCggICAAAAA==.',
La='Lanaela:BAAANQADCgEIAQAAAA==.Laquisha:BAAANQAECgEIAwAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.Lepershaun:BAAANQADCgYIBgABNQAECgkJMAAQAMEVAA==.',
Li='Lightmasta:BAAANQADCgYIBwAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilatharia:BAAANQABCgIIAgAAAA==.Lilbowar:BAAANQAECgEIAQAAAA==.Lilgnomievip:BAAANQAECgEIAgAAAA==.Lillath:BAAANQAECgEIAwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQADCgEIAgAAAA==.',
Lo='Lookforlight:BAABNQAECn9lAAMMAAoKnyJYHwBGAwAMAAoKOiJYHwBGAwAkAAUKOiG5HABTAQAAAA==.Lorenth:BAABNQAECn8eAAIBAAkKTQaIcABNAQABAAkKTQaIcABNAQAAAA==.Lorgoza:BAAANQAECgQIBAAAAA==.',
Lu='Lucerza:BAAANQAECgEIAQABNQAECgoKHgAOAGsWAA==.Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
Lv='Lvcky:BAAANQADCgIIAgAAAA==.',
['Lì']='Lìte:BAABNQAECn8kAAICAAkKQw17IQBcAQACAAkKQw17IQBcAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn88AAMlAAoKCAs5RgCbAQAlAAoKCAs5RgCbAQAhAAEKhgeaYgAvAAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAwAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAAVAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwAYABEhAA==.Malidros:BAAANQAECgcIEAAAAA==.Malign:BAABNQAECn8sAAMhAAoKQCOtAwCcAwAhAAkKiSOtAwCcAwAlAAkKByIeBwAyAwABNQAFFAcIGAACACAlAA==.Manhatten:BAAANQAECgQIBQAAAA==.Marhault:BAABNQAECn9WAAMSAAoKuiNhBwCiAwASAAoKtyNhBwCiAwAiAAUKbR9MCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAIVAAkK7RvZJACTAgAVAAkK7RvZJACTAgAAAA==.Mastadeath:BAAANQADCgEIAQAAAA==.Matt:BAAANQAECgEIBAAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8bAAIMAAcKqQ+b2ABqAQAMAAcKqQ+b2ABqAQAAAA==.Mazah:BAABNQAECn9WAAMXAAoKpBGqLwAxAgAXAAoKpBGqLwAxAgATAAoKmhiZJAAkAgAAAA==.Mazlo:BAACNQAFFH8FAAIfAAMKnxBJCACXAAAfAAMKnxBJCACXAAA1AAQKf0sAAx8ACgosHxAEAPUCAB8ACgosHxAEAPUCABgAAgrrAP3DATgAAAAA.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQADCgEIAQABNQAECgoKFgAKAK4OAA==.Mellethir:BAABNQAECn81AAMYAAoK5Qlv5gC9AQAYAAoK5Qlv5gC9AQAfAAIK1gnRJwBuAAAAAA==.Messalina:BAAANQAECgcIBwABNQAECgcIEAAPAAAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECggIEAAAAA==.Minipimp:BAAANQADCgcIGwAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAABNQAECn8bAAIEAAcKsBFeKQBZAQAEAAcKsBFeKQBZAQAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8rAAISAAkKxx8WQwAUAgASAAkKxx8WQwAUAgAAAA==.Moglayn:BAABNQAECn9RAAIVAAoKvyXpAQDWAwAVAAoKvyXpAQDWAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAIoAAQKWQ1uBgD4AAAoAAQKWQ1uBgD4AAA1AAQKfxsAAigACQpOGnENACQCACgACQpOGnENACQCAAE1AAUUBwgRABUAKg4A.Monorìth:BAEBNQAFFH8RAAIVAAcKKg5uDgBtAQAVAAcKKg5uDgBtAQAAAA==.Morninstar:BAAANQADCgMIAwAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgQIBgAAAA==.',
Ms='Msironimps:BAAANQADCgEIAQAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECgoKPAAlAAgLAA==.',
My='Myspace:BAAANQADCgcICgAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQADCgEIAwABNQADCgEIAwAPAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICQAAAA==.',
Na='Nakiki:BAABNQAECn8WAAIjAAYKvxLfHADVAAAjAAYKvxLfHADVAAAAAA==.Nastyiam:BAACNQAFFH8KAAIZAAMK7wW/AwDMAAAZAAMK7wW/AwDMAAA1AAQKfzwAAhkACgruFZMLAC0CABkACgruFZMLAC0CAAAA.',
Ne='Nerfornothin:BAABNQAECn8fAAISAAkKZwZGnAA1AQASAAkKZwZGnAA1AQAAAA==.Nethbubble:BAAANQAECgEIAQABNQAFFAIIBQAbAHoGAA==.Nethflap:BAACNQAFFH8FAAIbAAIKegZmEQBtAAAbAAIKegZmEQBtAAA1AAQKfy8AAhsACgpSEDwbABQCABsACgpSEDwbABQCAAAA.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQAECgQIBAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Nights:BAAANQADCgEIAQAAAA==.Niik:BAABNQAECn8qAAIXAAoKkRpKMQCcAgAXAAoKkRpKMQCcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAACNQAFFH8IAAIZAAMKSxenAgD1AAAZAAMKSxenAgD1AAA1AAQKf0AAAhkACgqYJL8BAJwDABkACgqYJL8BAJwDAAAA.',
Ny='Nycterine:BAAANQAECgQIBAABNQAECggIGgAfAK0XAA==.Nyxnight:BAAANQADCgEIAgAAAA==.',
Ob='Obi:BAAANQAECgIIAwAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQAECgEIAQABNQAECgYICwAPAAAAAA==.',
Os='Osanyin:BAAANQADCgQIBQABNQAECgcIEAAPAAAAAA==.',
Ou='Outstanding:BAAANQAECgUICAABNQAECggIMAABADciAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIBAAAAA==.',
Pe='Pepis:BAAANQAECggIEQAAAA==.Perfections:BAAANQADCgQIBgAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgIIAgAAAA==.Pikagosa:BAAANQAECgEIAgABNQAFFAcIEwAiAIMOAA==.Pilgor:BAABNQAECn8eAAMLAAoK2A2aDACKAQALAAkKXg6aDACKAQAbAAoKYwa7EwB5AQAAAA==.Pirlivewire:BAAANQADCgEIAQABNQADCgEIAgAPAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQICwAAAA==.Polkovnik:BAABNQAECn8fAAIRAAkKVRvFZQBeAgARAAkKVRvFZQBeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAwAAAA==.Preroll:BAAANQADCgEIAwAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICQAAAA==.',
Qu='Qubit:BAEBNQAECn8lAAIYAAkKKQVqmgBDAQAYAAkKKQVqmgBDAQABNQAECgoKNgAIAH4TAA==.Quickfinger:BAAANQAECggIAQAAAA==.Quiniustius:BAAANQAECgQIBwAAAA==.',
Ra='Ragingpwner:BAAANQADCgUICQAAAA==.Rallyn:BAAANQADCggICAAAAA==.Ramacondama:BAAANQAECgcICQABNQAECggIOwANANQiAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECgkJNwATAPweAA==.Ravel:BAABNQAECn8eAAIgAAkKFRsiCwBLAgAgAAkKFRsiCwBLAgAAAA==.',
Re='Reahla:BAAANQADCgcICAAAAA==.Reclaim:BAABNQAECn83AAMTAAkK/B6AKADfAgATAAkK/B6AKADfAgAZAAIKtgLnKwBVAAAAAA==.Reios:BAABNQAECn85AAIcAAoKax7uGgCKAgAcAAoKax7uGgCKAgAAAA==.Retina:BAAANQADCgEIAQAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhastaman:BAAANQAECgcIBgABNQAECgoKOwARAB0VAA==.Rhaz:BAABNQAECn8tAAMJAAkKqBP/PwDhAQAJAAkKqBP/PwDhAQAMAAEKAADpvAEqAAAAAA==.Rheeannon:BAAANQAECgEIAQAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBwABNQAECggIFwAiACcaAA==.',
Ri='Rickyspanish:BAABNQAECn9BAAICAAoKCiGFDQANAwACAAoKCiGFDQANAwAAAA==.Rictor:BAAANQAECggICgAAAA==.Rifter:BAAANQAECgYIEAAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAPAAAAAA==.Rinnobu:BAAANQAECgUIBQABNQAECggIFwAJAC0KAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgoKNgAIAH4TAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Rollnine:BAAANQAECgEIAgAAAA==.Romeric:BAAANQADCggIDwAAAA==.Roupert:BAABNQAECn8XAAIiAAgKJxq7BQBXAgAiAAgKJxq7BQBXAgAAAA==.',
Ru='Rubyouraw:BAAANQAECgcIDwAAAA==.Ruffneck:BAABNQAECn8qAAISAAkKpBJUaABDAgASAAkKpBJUaABDAgAAAA==.Russk:BAAANQAECgYIBwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYIDQAAAA==.',
Sa='Saelaan:BAABNQAECn8lAAIoAAgKYBxMBwDAAQAoAAgKYBxMBwDAAQABNQAECgkJLQAkAGsjAA==.Sailfu:BAACNQAFFH8WAAIaAAcKJCBpAgC3AQAaAAcKJCBpAgC3AQA1AAQKfy8AAhoACgo1JcgFAHQDABoACgo1JcgFAHQDAAE1AAUUBwgYAAIAICUA.Saiyurie:BAAANQADCgEIAgAAAA==.Sakrine:BAAANQAECgIIAQAAAA==.Salami:BAAANQADCgcIDwAAAA==.Samo:BAABNQAECn8jAAIGAAgKMB7cHQBRAgAGAAgKMB7cHQBRAgAAAA==.Sandarr:BAABNQAECn8lAAIkAAgK9xa3IgDMAQAkAAgK9xa3IgDMAQAAAA==.Sanguinne:BAABNQAECn8eAAIKAAcKtwqlCwDfAAAKAAcKtwqlCwDfAAAAAA==.Santhus:BAABNQAECn8gAAIlAAoKMA9gOgDQAQAlAAoKMA9gOgDQAQAAAA==.Sarabela:BAAANQADCggICAABNQAECggIJQAkAPcWAA==.Saretae:BAAANQADCggIHgABNQAFFAcIFgAYAAQgAA==.Sargemarge:BAABNQAECn8dAAIXAAkKICMxDQBXAwAXAAkKICMxDQBXAwAAAA==.Sarume:BAAANQAECggIDwABNQAECggIOwANANQiAA==.',
Sc='Sci:BAABNQAECn8tAAIJAAgKGyUPEABLAwAJAAgKGyUPEABLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAABNQAECgMIAwAPAAAAAA==.Selener:BAAANQAECggIDAAAAA==.Serbitar:BAAANQAECggICwABNQAECgoKKAAIABAfAA==.Serrata:BAABNQAECn8eAAISAAgKIB0SSAAEAgASAAgKIB0SSAAEAgAAAA==.Seymorweiner:BAAANQADCgQIBgAAAA==.',
Sh='Shaanks:BAAANQADCggIEAAAAA==.Shadowplay:BAEANQAECgEIAgABNQAECgoKNgAIAH4TAA==.Shamski:BAAANQAECgMIBAABNQAECgYIDAAPAAAAAA==.Shamydavisjr:BAAANQADCgEIAwAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIBAAAAA==.Shathice:BAAANQAECgEIAQABNQAECgoKJgAJAIEfAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAgAAAA==.Shocky:BAAANQADCgEIAQABNQADCgIIAwAPAAAAAA==.',
Si='Sidelvar:BAAANQADCgEIAQAAAA==.Silandros:BAAANQAECgYICAAAAA==.Silther:BAABNQAECn8dAAIkAAkKwhbNEwCzAQAkAAkKwhbNEwCzAQAAAA==.',
Sk='Skarath:BAABNQAECn8dAAQQAAYK3AYqJACSAAAUAAUKYAgoMQCtAAAQAAUKoAQqJACSAAARAAQKXAPs+ABVAAAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggIDAAAAA==.',
Sn='Snâppy:BAABNQAECn8jAAIEAAgKpAwDOQBWAQAEAAgKpAwDOQBWAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn8vAAIXAAkKfRpWNwAMAgAXAAkKfRpWNwAMAgAAAA==.Sorrowsöng:BAABNQAECn8dAAMMAAkKrhjfaADBAQAMAAkKrhjfaADBAQAJAAQKDQU4rQCWAAAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAPAAAAAA==.Southvik:BAAANQAECggIEwABNQAECggIMAABADciAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAMIEQABAFsfAA==.Sparrhawk:BAAANQAECgcIDQAAAA==.Spiced:BAACNQAFFH8IAAIDAAMKSiEnCgAZAQADAAMKSiEnCgAZAQA1AAQKfzAAAgMACgo0IkMIAPwCAAMACgo0IkMIAPwCAAAA.Spiceweasel:BAAANQAECgMIAwAAAA==.Spiritbound:BAAANQADCgEIAQAAAA==.Spirithaeler:BAAANQADCgEIAgAAAA==.Spood:BAABNQAECn89AAMGAAoKSRDCFQDHAQAGAAoKSRDCFQDHAQAHAAUKkRP2DgA9AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Stabussy:BAAANQAECgQICwABNQAECggIEwAPAAAAAA==.Starskream:BAAANQADCgQIBQAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQADCgEIAgAAAA==.Stickes:BAAANQAECgQICAAAAA==.Stingella:BAAANQAECgcIBwAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQAECgEIAgABNQAECgYICwAPAAAAAA==.Sttriker:BAABNQAECn8oAAIOAAoK4wR/RADiAAAOAAoK4wR/RADiAAAAAA==.Styx:BAAANQADCgEIAQABNQADCgQIBgAPAAAAAA==.Stéalth:BAAANQAECgUIBQAAAA==.',
Su='Subsequently:BAAANQAECgEIAQABNQAECgoKGwAEAOsPAA==.',
Sy='Symditho:BAAANQABCgcICwAAAA==.Synsairis:BAABNQAECn8eAAIaAAkKKQ3kHgBwAQAaAAkKKQ3kHgBwAQAAAA==.',
Ta='Talenelat:BAAANQAECgIIAQAAAA==.Talonknight:BAABNQAECn8jAAMLAAgKzgpNDAD5AAALAAgKgQpNDAD5AAAnAAUK1QauKQDdAAAAAA==.Talset:BAAANQADCgIIBAAAAA==.Tau:BAABNQAECn8jAAIkAAoKjRSiEwC1AQAkAAoKjRSiEwC1AQAAAA==.Tauria:BAAANQAECgEIAgAAAA==.Taurrows:BAAANQAECgUIBAAAAA==.Tavaran:BAAANQADCgEIAQAAAA==.Tavinz:BAAANQAECgUIDQAAAA==.',
Te='Tempedsoul:BAAANQABCgcIDQAAAA==.',
Th='Thaendofyou:BAAANQAECggICwAAAA==.Thalassia:BAAANQAECgMIBAAAAA==.Thalonis:BAAANQADCgEIAQAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQAECgUIEgAAAA==.Thellan:BAAANQAECgEIAQAAAA==.Themonk:BAAANQADCggICgABNQAECgkJMgAVAD0WAA==.Therise:BAABNQAECn8mAAMNAAkKOg7hFABeAQANAAgKCA/hFABeAQAOAAEKYwkkdAA1AAABNQAECgoKVgAXAKQRAA==.Thetank:BAABNQAECn8yAAMVAAkKPRZYQgDzAQAVAAkKPRZYQgDzAQAIAAEKFAnLgAAtAAAAAA==.Thoroughbred:BAAANQADCgYIDQAAAA==.Throwdini:BAABNQAECn88AAISAAoKUxQnOwAtAgASAAoKUxQnOwAtAgAAAA==.Thunder:BAAANQADCgEIAQAAAA==.Thunderegg:BAAANQAECgUICwABNQAECgoKVgAXAKQRAA==.Thundermaker:BAAANQAECgUIEQABNQAECgoKKAAIABAfAA==.',
Ti='Timotthy:BAABNQAECn8yAAQFAAgKMSFDEwAvAgAFAAYKPiBDEwAvAgAjAAcKxSAbDwCGAQADAAEKAACBygAXAAAAAA==.Tixxle:BAAANQADCggIGQAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgcICQABNQAFFAQIDwAKAGQZAA==.',
Tr='Treateak:BAAANQAECgQICQAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAABNQAECn8VAAITAAkKvBsBLwDAAgATAAkKvBsBLwDAAgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn9VAAIWAAoKPhsMEQDfAgAWAAoKPhsMEQDfAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAABNQAECn8aAAIfAAgKrRfWCQAxAgAfAAgKrRfWCQAxAgAAAA==.Tyriem:BAABNQAECn8hAAISAAoKVBRXQACqAgASAAoKVBRXQACqAgAAAA==.Tyssanton:BAABNQAECn8nAAMnAAkKUgiNIwAnAQAnAAgK/gONIwAnAQAbAAkKXQT0HwDXAAAAAA==.',
Tz='Tziganin:BAABNQAECn8cAAITAAkKdxOZOwCrAQATAAkKdxOZOwCrAQAAAA==.',
Ug='Uggork:BAAANQADCgQICAABNQAECgoKJgAJAIEfAA==.',
Un='Unholybussy:BAAANQAECgcIEAAAAA==.',
Ut='Utaadh:BAABNQAECn8vAAIOAAkKoBJwNwD1AQAOAAkKoBJwNwD1AQAAAA==.',
Va='Vael:BAAANQAECgUIDwABNQAECgoKVAAOABQkAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAPAAAAAA==.Vallderossa:BAAANQAECgEIAgAAAA==.Vallerin:BAABNQAECn8pAAIZAAoKFxWPDQAIAgAZAAoKFxWPDQAIAgAAAA==.Vanek:BAAANQAECgEIAQAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgoKVAAOABQkAA==.Velarine:BAAANQADCgEIAQAAAA==.Velazar:BAAANQAECgQIBAAAAA==.Verras:BAAANQADCgEIAQAAAA==.',
Vi='Vicente:BAABNQAECn8XAAICAAoKIAYQIgBXAQACAAoKIAYQIgBXAQAAAA==.Vicenti:BAAANQAECgEIAQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQAECgMIAwABNQAECggIMAABADciAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8WAAISAAYKUhoQBQAGAgASAAYKUhoQBQAGAgA1AAQKfzMABBIACgopIYEwANsCABIACgopIYEwANsCABYAAQpBGIqBAEEAACIAAQoAAGwTADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8sAAMVAAkKdxsPLQBiAgAVAAkKdxsPLQBiAgAIAAMK5gPuZQBdAAAAAA==.',
Wa='Wagwan:BAABNQAECn8ZAAMIAAoKyBgbFQAbAgAIAAoKTxgbFQAbAgAeAAIKXCDegwCfAAAAAA==.Walls:BAABNQAECn8iAAIMAAkKOwyRqgA5AQAMAAkKOwyRqgA5AQAAAA==.Wardrik:BAAANQADCgUIBQAAAA==.Waste:BAABNQAECn8fAAMcAAkKXx01QwDXAQAcAAkKqhw1QwDXAQAKAAIKtxUoJQBTAAAAAA==.Wawel:BAABNQAECn8qAAQnAAoKUh6uCADGAQAnAAkKWR2uCADGAQAbAAYKkCDXIQC+AQALAAQKAxk+FADrAAAAAA==.Wazwaz:BAAANQAECgIIAQABNQAECggILQAJABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgUIDwAAAA==.Wingsofsteel:BAAANQAECgIIAgAAAA==.Winstagram:BAAANQADCgQIBQAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgUICgAAAA==.Wowiezonk:BAAANQADCgEIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIFgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xi='Xibaba:BAAANQAECgEIAQAAAA==.',
Xs='Xshirroz:BAAANQAECgEIAQAAAA==.',
Yn='Yn:BAAANQAECgEIBAAAAA==.',
Yo='Yogí:BAABNQAECn85AAIZAAoKGhqwDwBuAgAZAAoKGhqwDwBuAgAAAA==.Yokos:BAAANQAECgEIAQAAAA==.Yoursummons:BAAANQAECgEIAQABNQAECgcIEQAPAAAAAA==.',
Yu='Yunkali:BAAANQADCgcIDQAAAA==.',
Za='Zafiel:BAAANQADCgcIBwAAAA==.Zahneel:BAABNQAECn8cAAMEAAkKoQ/tJgBtAQAEAAkKoQ/tJgBtAQAFAAUKrAVTRgBzAAAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8NAAIMAAUK/hv3DgBdAQAMAAUK/hv3DgBdAQA1AAQKfzwAAgwACgqyJE0NAJkDAAwACgqyJE0NAJkDAAAA.Zarisong:BAABNQAECn8WAAMkAAkKohMTKQCUAQAkAAgK8hUTKQCUAQAMAAMKswgUfQFeAAABNQAECgoKIAAlADAPAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQAECgEIAgAAAA==.',
Zo='Zoburg:BAAANQAECgcIEAABNQAECggIMAABADciAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAPAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBwAAAA==.',
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
