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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Rogue-Subtlety','Mage-Arcane','Warlock-Destruction','Priest-Shadow','Priest-Holy','Priest-Discipline','Paladin-Retribution','Rogue-Assassination','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Druid-Balance','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Warrior-Protection','Druid-Feral','Druid-Restoration','Warlock-Affliction','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aamara:BAABNQAECn8lAAIBAAcKyx3xQQBdAgABAAcKyx3xQQBdAgABNQAECggIGQACAJYfAA==.',
Ab='Aboyton:BAAANQAECgEIAgAAAA==.',
Ad='Adarksoul:BAAANQAECgEIAQAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwADAPkTAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAACNQAFFH8MAAMEAAUKBhHLDQAFAQAEAAQK3g7LDQAFAQAFAAMK0hNZFwBqAAA1AAQKfzYAAwUACgrLJNoWAD8DAAUACAqfJNoWAD8DAAQACgp8FFtNAC4CAAAA.Aelistiah:BAAANQAECgMIAgAAAA==.Aerithorn:BAABNQAECn8cAAIGAAgKciCzCQDYAgAGAAgKciCzCQDYAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgoKMAACABEYAA==.Ahleya:BAAANQAECgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAHAAAAAA==.',
Ak='Akazza:BAAANQADCgIIAgAAAA==.Akoris:BAAANQAECgQIBAABNQAECgoKKAAIAMATAA==.Akorys:BAABNQAECn8oAAMIAAoKwBOxDQCtAQAIAAoKwBOxDQCtAQAJAAEKAAB9NQAiAAAAAA==.',
Al='Albyno:BAACNQAFFH8PAAMKAAYKGg31CwBeAQAKAAYKGg31CwBeAQALAAEK8wYCEAA/AAA1AAQKfzIAAgoACgrxHlMFALMCAAoACgrxHlMFALMCAAAA.Algebrah:BAAANQAECgQIBQAAAA==.Alivallia:BAAANQADCgUIBQABNQAECggIHAAFALUZAA==.Alucius:BAAANQADCgQIBAAAAA==.',
Am='Amara:BAAANQADCgYIJwAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECn85AAIMAAcKTwTzpACnAAAMAAcKTwTzpACnAAAAAA==.Ancksunamun:BAAANQADCggIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECggIGQACAJYfAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFH8XAAINAAYKih3wBQC9AQANAAYKih3wBQC9AQA1AAQKfyUAAg0ACQrsH90FACgDAA0ACQrsH90FACgDAAAA.',
Ap='Aperture:BAAANQADCgcIEwAAAA==.',
Aq='Aquua:BAABNQAECn81AAIFAAoKphxyFwBFAgAFAAoKphxyFwBFAgAAAA==.',
Ar='Araelen:BAABNQAECn8UAAIOAAgKTwUDHAFdAQAOAAgKTwUDHAFdAQAAAA==.Arcticdps:BAABNQAECn8tAAMMAAoKpha+RACEAgAMAAoKpha+RACEAgAPAAEKVxYCbgBDAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECn8vAAQQAAoKjR9gKwDMAQAQAAYKeRpgKwDMAQARAAgKWBJafQChAQASAAcKUQ6GDABwAQAAAA==.Ariestar:BAABNQAECn8UAAITAAgKCghm3QBgAQATAAgKCghm3QBgAQAAAA==.Ariiel:BAAANQADCggICQABNQAECgoKLwAQAI0fAA==.Arrax:BAAANQADCgEIAQAAAA==.Arthimas:BAAANQAECgIIAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAABNQAECn8gAAIQAAcKGQs9IAAGAQAQAAcKGQs9IAAGAQAAAA==.Asidize:BAAANQAECgUICgAAAA==.Aslor:BAABNQAECn8kAAIMAAkK9ReiZgAnAgAMAAkK9ReiZgAnAgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYIDwAAAA==.',
At='Athalia:BAACNQAFFH8JAAMUAAIK2Bh9BgCeAAAUAAIKqRh9BgCeAAANAAIKURQREgCaAAA1AAQKfzYAAxQACgpIIzoFAIADABQACQqjIzoFAIADAA0AAgpBH39tAK4AAAAA.Atlaswolfe:BAAANQAECgcIBwAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECgcIDgAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAABNQAECn8wAAICAAoKERhCQADiAQACAAoKERhCQADiAQAAAA==.',
Ax='Axemage:BAABNQAECn85AAIOAAoKERhwWACjAQAOAAoKERhwWACjAQAAAA==.Axeom:BAABNQAECn86AAIEAAoK/RxyJwDGAgAEAAoK/RxyJwDGAgAAAA==.Axeshammy:BAAANQAECgMIAwABNQAECgoKOQAOABEYAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAACNQAFFH8GAAIOAAMKsAhGGwDVAAAOAAMKsAhGGwDVAAA1AAQKfxcAAg4ACQqhGiSjADsCAA4ACQqhGiSjADsCAAAA.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAABNQAECn8XAAITAAgKQBkCsQC9AQATAAgKQBkCsQC9AQAAAA==.Baldie:BAAANQAECgYIBgAAAA==.Bamboolan:BAAANQAECgcIBwAAAA==.Barcliah:BAAANQADCgIIAgAAAA==.Barometer:BAAANQAECgcIEgAAAA==.Baxa:BAAANQAECggICAAAAA==.Baylee:BAABNQAECn8lAAIOAAgKiQTwxgC+AAAOAAgKiQTwxgC+AAAAAA==.',
Bb='Bbartemis:BAABNQAECn8iAAINAAgKKASqbgCqAAANAAgKKASqbgCqAAAAAA==.',
Bc='Bchamp:BAAANQADCgQIBAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgQIBAABNQAECgYIBwAHAAAAAA==.Beekerr:BAAANQADCgMIBAABNQAECgoKKAAUAKIbAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgUIBQAAAA==.Belzenlok:BAAANQADCgYIDAAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAABNQAECn8YAAIVAAgK6gdtAgAtAQAVAAgK6gdtAgAtAQAAAA==.Bergamö:BAAANQAECggICQAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcICgAAAA==.Bigangus:BAAANQAECgMIBwAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Bigmerch:BAAANQADCgcIDgAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAABNQAECn8YAAIOAAcKxwKSywC2AAAOAAcKxwKSywC2AAAAAA==.Bisholoyd:BAABNQAECn8bAAIPAAcKUAqjHwByAQAPAAcKUAqjHwByAQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgQIAwAAAA==.Blastoise:BAABNQAECn9CAAMWAAoK7yOhBACnAwAWAAoKmyOhBACnAwAXAAoKkyDsBAD1AgAAAA==.Blizfishleg:BAABNQAECn8WAAIYAAYKFg+1FABfAQAYAAYKFg+1FABfAQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bloodshell:BAAANQADCgQIAwABNQAECgkJHQAZANsaAA==.Bloodybren:BAAANQAECgMIBQAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgYICAAAAA==.Bongwater:BAAANQADCgEIAQABNQAECgoKNAAaAE8hAA==.Bonkyo:BAAANQADCgYIBgAAAA==.Boombóx:BAAANQAECgYICwABNQAECgoKPwAMACcjAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAABNQAECn8xAAIbAAoKFSBiCQBnAgAbAAoKFSBiCQBnAgAAAA==.Bowsback:BAAANQADCggIKAAAAA==.Bowyohead:BAABNQAECn8mAAIRAAoKyx0jEwDOAgARAAoKyx0jEwDOAgAAAA==.',
Br='Bracydaboss:BAAANQAECgEIAwAAAA==.Bradroybboi:BAAANQAECgUIDgAAAA==.Braingap:BAAANQAECgcIEAABNQAECggIDAAHAAAAAA==.Brandoe:BAAANQAECgQIBgAAAA==.Breece:BAAANQAECgQIAwAAAA==.Brickinkeys:BAAANQAECggICQABNQAECggIGQACAJYfAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECn8rAAIcAAoKdggIAwBvAQAcAAoKdggIAwBvAQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caenarigos:BAAANQAECgIIAQAAAA==.Caenarius:BAAANQADCgMIAwABNQAECgIIAQAHAAAAAA==.Caimie:BAAANQAECgQIBgAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQICQAAAA==.Capnmorgan:BAAANQABCgEIAQAAAA==.Cassiaan:BAAANQAECgMIAwAAAA==.Caylavibes:BAABNQAECn8iAAIRAAoKEBD0VAAkAgARAAoKEBD0VAAkAgAAAA==.',
Ch='Chaviel:BAAANQAECggICgAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAABNQAECn8gAAIRAAkK8RbcHwBjAgARAAkK8RbcHwBjAgAAAA==.Chironn:BAABNQAECn85AAIdAAoKwxg3AgBeAgAdAAoKwxg3AgBeAgAAAA==.Chudlord:BAAANQADCggICwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQAECgQICwAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgQIBQAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAQAAAA==.Comfychair:BAABNQAECn8iAAITAAkKux9tQQDQAgATAAkKux9tQQDQAgAAAA==.Coowmoo:BAABNQAECn8VAAIeAAgKWhJrHQCLAQAeAAgKWhJrHQCLAQAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAUICQAfAI0WAA==.Cosmonodder:BAAANQAECggIEQABNQAFFAUICQAfAI0WAA==.Cosmoshotter:BAACNQAFFH8JAAMfAAUKjRbeFADyAAAfAAQKjRbeFADyAAACAAIKAAD6NwBLAAA1AAQKfyYAAx8ACgobINoLABgCAB8ACgocHdoLABgCAAIAAgrpI9/hAHAAAAAA.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Crazyotto:BAAANQABCggIBwAAAA==.Cremebrule:BAAANQAECgEIAgAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cuchulainn:BAAANQADCgQIBAAAAA==.Cucubau:BAAANQADCggIFQAAAA==.',
Cy='Cyndra:BAABNQAECn8VAAIOAAkKQgn6mgAPAQAOAAkKQgn6mgAPAQAAAA==.',
Da='Dacura:BAAANQADCgUIBQAAAA==.Dakai:BAAANQADCgIIAgAAAA==.Dallthyrian:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.Dalthyrian:BAAANQAECgYIDQABNQAECgUICAAHAAAAAA==.Dalthyriian:BAAANQAECgUICAAAAA==.Dalthyrrian:BAAANQAECgEIAQABNQAECgUICAAHAAAAAA==.Dalthyyrian:BAABNQAECn8VAAIgAAcK3A3EIQDuAAAgAAcK3A3EIQDuAAABNQAECgUICAAHAAAAAA==.Damii:BAAANQADCgYIEgAAAA==.Danarand:BAAANQADCgYIBwABNQAECgcIIQAGAPcSAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgkJFAAFAJsOAA==.Darjen:BAABNQAECn8VAAICAAYKdhmragBkAQACAAYKdhmragBkAQAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darkshock:BAAANQAECggICQAAAA==.Darkski:BAAANQADCgQIBAAAAA==.Darksky:BAABNQAECn8UAAIbAAoK/x29BQDBAgAbAAoK/x29BQDBAgAAAA==.Daysfox:BAACNQAFFH8GAAIfAAMKJQbPCgC6AAAfAAMKJQbPCgC6AAA1AAQKfzoAAx8ACQpEDswPAMsBAB8ACQpEDswPAMsBAAIAAQq6DAFPAUMAAAAA.Daysmonk:BAABNQAECn8lAAIhAAgKsww8GAB0AQAhAAgKsww8GAB0AQAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCggIDQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgoKRQAUAFAfAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECn9FAAMUAAoKUB9QAwDEAgAUAAkKmB5QAwDEAgANAAUKKgtnOgDkAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathsdawn:BAAANQAECgUIBwABNQAECgoKRAAbAEYbAA==.Deathstone:BAABNQAECn8nAAMiAAkKBByTGAAMAgAiAAkKBByTGAAMAgAXAAUKiw8NSwCLAAABNQAFFAYIEQATAJ0YAA==.Deathtress:BAABNQAECn8bAAQiAAkKwhHHMgAVAgAiAAkKwhHHMgAVAgAXAAEKNAN69QAiAAAWAAEKAAAP3QAhAAAAAA==.Debbydowner:BAABNQAECn8wAAIDAAoK2gvnXQBpAQADAAoK2gvnXQBpAQAAAA==.Decado:BAABNQAECn8WAAITAAoKqQoCvQCjAQATAAoKqQoCvQCjAQAAAA==.Deemwins:BAAANQAECgUIBQAAAA==.Deezenuts:BAAANQAFFAEIAQAAAA==.Degen:BAABNQAECn8VAAIZAAYK1QmVOQDhAAAZAAYK1QmVOQDhAAAAAA==.Dejevoid:BAABNQAECn8XAAIbAAoK6wbPOQB3AQAbAAoK6wbPOQB3AQAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Deliquium:BAAANQABCggICgABNQAECgUICwAHAAAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECn8qAAMjAAkK/hg0DgBMAgAjAAkK/hg0DgBMAgADAAMKuAh9JgGLAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Dethmoora:BAAANQADCgYIBgAAAA==.Deww:BAABNQAECn8lAAMSAAoK3Br+BABpAgASAAgKQxj+BABpAgARAAkKJxkkJgA5AgAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECn8lAAIgAAkKmgraIgDmAAAgAAkKmgraIgDmAAAAAA==.',
Di='Diablesse:BAAANQAECgUIBQAAAA==.Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECn8xAAIWAAoKCSEJFAAMAwAWAAoKCSEJFAAMAwAAAA==.',
Do='Docdolittle:BAABNQAECn9PAAMCAAoKmCSMCQCQAwACAAoKmCSMCQCQAwAfAAEKdBHKggA9AAAAAA==.Docfreez:BAABNQAECn8/AAMYAAoK+iPEBwBwAgAOAAoKCCExQgAAAwAYAAgKjCLEBwBwAgAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgcIDwAHAAAAAA==.Doctermoo:BAAANQAECgcIDQAAAA==.Dogar:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgoKMQAbABUgAA==.Doraemee:BAAANQAECgUIBwAAAA==.',
Dr='Drbaconbrgr:BAABNQAECn8cAAIRAAcKVhwmPwC4AQARAAcKVhwmPwC4AQABNQAECgoKOAACALUjAA==.Drbakedziti:BAAANQADCggIDgABNQAECgoKOAACALUjAA==.Drbaobuns:BAAANQAECgYICwABNQAECgoKOAACALUjAA==.Drcarrotcake:BAAANQAECgcIEAABNQAECgoKOAACALUjAA==.Drcheeseball:BAAANQAECgYIDgABNQAECgoKOAACALUjAA==.Dreggsalad:BAAANQAECgUIDwABNQAECgoKOAACALUjAA==.Dreim:BAEANQAECgYIBgABNQAECgoKTgATAHMkAA==.Dreima:BAAANQAECgQIBAAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgoKOAACALUjAA==.Drgatorwine:BAABNQAECn8UAAIgAAcKWBv2HgDvAQAgAAcKWBv2HgDvAQABNQAECgoKOAACALUjAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgoKOAACALUjAA==.Drkimchirice:BAABNQAECn8oAAIkAAoKDiT0AQCkAwAkAAoKDiT0AQCkAwABNQAECgoKOAACALUjAA==.Drmacncheese:BAABNQAECn8sAAIPAAoKAh3HAAClAgAPAAoKAh3HAAClAgABNQAECgoKOAACALUjAA==.Drpumpkinpie:BAABNQAECn8dAAITAAoKehn2WwCEAgATAAoKehn2WwCEAgABNQAECgoKOAACALUjAA==.Drshephardpi:BAAANQADCggICgABNQAECgoKOAACALUjAA==.Drshortbread:BAAANQAECgYIDAABNQAECgoKOAACALUjAA==.Druiddres:BAAANQAECgUIBAAAAA==.Drwontonsoup:BAABNQAECn84AAICAAoKtSPoBwCeAwACAAoKtSPoBwCeAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.Dumpstur:BAAANQAECgQIBgAAAA==.',
['Dö']='Dööku:BAAANQADCggIDgAAAA==.',
Ei='Eighteen:BAABNQAECn8zAAINAAoK9x9iBgAbAwANAAoK9x9iBgAbAwAAAA==.',
Ek='Eksi:BAABNQAECn8dAAIhAAkKjRQaGAB1AQAhAAkKjRQaGAB1AQAAAA==.',
El='Eladaradar:BAAANQADCggICgAAAA==.Elethe:BAAANQAECgIIAgABNQAFFAYIFwANAIodAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgQIBgAAAA==.Ellilina:BAAANQAECgIIAgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAABNQAECn8UAAMFAAkKmw4rdADFAQAFAAgKfBArdADFAQAeAAEKWAMSKwAwAAAAAA==.Eme:BAAANQAECgUICwAAAA==.Empress:BAABNQAECn8aAAIiAAgKVQuXTwB2AQAiAAgKVQuXTwB2AQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Enriq:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.Entrophi:BAAANQADCgMIAwABNQADCgQIBAAHAAAAAA==.',
Er='Erikaa:BAABNQAECn8XAAITAAgKLApCkgAtAQATAAgKLApCkgAtAQAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIAQAHAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECggIDAAHAAAAAA==.',
Ex='Excruciator:BAABNQAECn8rAAMZAAkKbRLwRwDLAQAZAAkKbRLwRwDLAQAlAAIKtAfIZgBqAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAABNQAECn8ZAAIhAAkKDBI7FAClAQAhAAkKDBI7FAClAQAAAA==.Falloutzhunt:BAAANQADCgYIBgABNQAECgkJGQAhAAwSAA==.Fantarada:BAAANQADCgcIDAAAAA==.Farahcanle:BAABNQAECn9IAAIGAAoKoBJwDwC1AQAGAAoKoBJwDwC1AQAAAA==.Farrock:BAABNQAECn8mAAIGAAkKLAtsHQAeAQAGAAkKLAtsHQAeAQAAAA==.Fawxette:BAAANQADCggICAABNQAECgoKSQAaAEMXAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAABNQAECn8bAAIOAAgKXwXGlQAYAQAOAAgKXwXGlQAYAQAAAA==.Fenra:BAAANQADCgcIEAAAAA==.Feorblarir:BAABNQAECn8VAAIkAAoK6RFhCADIAQAkAAoK6RFhCADIAQAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQAECgQIAwABNQAECggIIQAjAK4IAA==.Filledegel:BAAANQAECgQICQABNQAECggIDgAHAAAAAA==.Finowscath:BAAANQAECgMIAwAAAA==.Firequencher:BAABNQAECn8dAAIZAAkK2xoxNABGAgAZAAkK2xoxNABGAgAAAA==.Fistacuffs:BAAANQAECgIIAQAAAA==.Fistdoc:BAAANQAECgcIDwAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQAECgIIAgAAAA==.Fié:BAAANQADCggIIgABNQAECgoKSQAaAEMXAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECn9JAAIaAAoKQxclEABKAgAaAAoKQxclEABKAgAAAA==.Foxknight:BAAANQADCgQIBAABNQAECgoKSQAaAEMXAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCgUICgABNQAECgcIIQAGAPcSAA==.',
Fr='Frederick:BAAANQAECggIBwAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECn8oAAIBAAkKUR44KQDDAgABAAkKUR44KQDDAgAAAA==.Friendofbear:BAACNQAFFH8NAAICAAQKIw2PDgDeAAACAAQKIw2PDgDeAAA1AAQKfzQAAgIACgpMGs44AMACAAIACgpMGs44AMACAAAA.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAAANQAECgcIDwAAAA==.Fuzywuzzy:BAABNQAECn8VAAMGAAkKcyBrBgAqAwAGAAkKcyBrBgAqAwAkAAQK6A0gKQDGAAAAAA==.Fuzzycoochy:BAAANQADCgQIBAAAAA==.Fuzzykuntz:BAABNQAECn8hAAIXAAkKigoYKQA0AQAXAAkKigoYKQA0AQAAAA==.Fuzzypus:BAAANQADCgYIBgAAAA==.',
Fw='Fwoom:BAAANQADCgUIBQAAAA==.',
Fy='Fynsdood:BAABNQAECn8hAAIGAAcK9xKgIgCCAQAGAAcK9xKgIgCCAQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgcIIQAGAPcSAA==.',
Ga='Gabelock:BAACNQAFFH8dAAQMAAcK0hWGBQBdAQAMAAYKcxiGBQBdAQAPAAEKUgtbHgBLAAAmAAEKAADnEgA8AAA1AAQKfzgABAwACgp2I88ZAGQCAAwACgp2I88ZAGQCAA8ABAouGY4wAAYBACYAAQoAALUtADsAAAAA.Gabemage:BAABNQAECn8ZAAIOAAkKkhGfswAcAgAOAAkKkhGfswAcAgAAAA==.Gala:BAAANQAECgYIBwAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAABNQAECn8dAAITAAoKfhCQmgDuAQATAAoKfhCQmgDuAQAAAA==.',
Gi='Gigah:BAABNQAECn8XAAINAAoKww54FwAjAgANAAoKww54FwAjAgAAAA==.Gingerbell:BAAANQABCggICgAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgcIEgAAAA==.Glutebruiser:BAAANQAECgEIAwABNQAECgkJKAAMAPQkAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQAECgEIAQAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECn8XAAIIAAgKVyJuCwDNAgAIAAgKVyJuCwDNAgAAAA==.Grimspark:BAAANQABCgUIBQAAAA==.Grimtree:BAABNQAECn8vAAMmAAkKRBP+BwAVAgAmAAgKLRX+BwAVAgAMAAcKMQujcgAWAQAAAA==.Grindor:BAAANQADCggIDAAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgYICwAAAA==.Grumpydemon:BAABNQAECn85AAIbAAoKrBgAEADpAQAbAAoKrBgAEADpAQAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gu='Guglugauthu:BAAANQAECgIIAgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQAECgUIBwABNQAECgoKTgATAHMkAA==.Halfskul:BAABNQAECn8YAAIXAAgK2guCZgB3AQAXAAgK2guCZgB3AQAAAA==.Halotic:BAAANQAECgMIBQAAAA==.Hashah:BAABNQAECn8aAAIQAAcKRyCtGwBqAgAQAAcKRyCtGwBqAgAAAA==.Hatefel:BAAANQAECgUIBQABNQAECggIIQAPABsjAA==.Havoke:BAAANQADCggIGAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgoKMQAnAHUWAA==.Healyaass:BAAANQADCggIIgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgAQAEcgAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECggIGQACAJYfAA==.Heyyboyy:BAACNQAFFH8FAAICAAQKSxiPCAARAQACAAQKSxiPCAARAQA1AAQKf0QAAwIACgqcJNwKAIYDAAIACgqcJNwKAIYDAB8AAwrDDogrALEAAAAA.',
Ho='Holyaefar:BAAANQAFFAIIAwABNQAFFAUIDAAEAAYRAA==.Holymolydin:BAAANQADCggIBgAAAA==.Holysab:BAABNQAECn8aAAMBAAgK7x2+HQBWAgABAAgK7x2+HQBWAgATAAIKOgl6GAFhAAAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAABNQAECn8bAAMRAAoK+RepSwBCAgARAAkKYRipSwBCAgAQAAIKqgbJSAA0AAAAAA==.Holz:BAAANQAECgMICAAAAA==.Horsetowater:BAAANQAECgQICQABNQAECgoKJgARAMsdAA==.Hotsfordays:BAAANQAECggICAAAAA==.',
Hu='Hugoman:BAAANQAECggIDgABNQAECgoKLwAXALUVAA==.Huni:BAABNQAECn8cAAIEAAkKsx5ZKADCAgAEAAkKsx5ZKADCAgAAAA==.Hunterj:BAAANQAECgIIAgAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAABNQAECn8eAAITAAoKahNhQwDvAQATAAoKahNhQwDvAQAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgQIBAABNQAECggICwAHAAAAAA==.',
Ib='Ibun:BAAANQAECgcIDgAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECn8oAAIBAAkKYBgCLgCuAgABAAkKYBgCLgCuAgABNQAECgoKJgARAMsdAA==.',
Ig='Igneus:BAACNQAFFH8YAAIOAAYKSCE1CABpAQAOAAYKSCE1CABpAQA1AAQKfzYAAg4ACgqeJDIEAEgDAA4ACgqeJDIEAEgDAAAA.Igriz:BAAANQADCggIMAAAAA==.',
Ii='Iillil:BAACNQAFFH8IAAIbAAQKdATNDgCxAAAbAAQKdATNDgCxAAA1AAQKfycAAhsACgo6DCwsAOABABsACgo6DCwsAOABAAAA.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgMIBAAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQADCgMIBQAAAA==.Insidedoubt:BAAANQAECgcIDgAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUIBQAAAA==.',
It='Itsjeff:BAABNQAECn8WAAMfAAcKthcsOgB+AQAfAAYKwxQsOgB+AQACAAQKcRmD6wAqAQAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQAECggIEwAAAA==.Jambonjay:BAABNQAECn8gAAIDAAcKuwl+zgBXAQADAAcKuwl+zgBXAQABNQAECggIJQACAJ0RAA==.Jananda:BAABNQAECn8iAAMlAAYKUQHuTwBPAAAlAAYKUQHuTwBPAAAZAAYK5QAHqABIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jastora:BAAANQADCgEIAQABNQADCggIDQAHAAAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgABNQAECgoKHQAlAHYeAA==.Jckjckjck:BAAANQADCgUIBQABNQAECgoKHQAlAHYeAA==.Jckjckjckjck:BAABNQAECn8dAAQlAAoKdh7+BwDVAgAlAAkKjR/+BwDVAgAZAAkKKh9cIwC1AgAGAAEKAABJUgBaAAAAAA==.',
Je='Jearn:BAAANQAECgMIAwAAAA==.Jermagedupri:BAACNQAFFH8PAAIOAAUKTRUkIACFAQAOAAUKTRUkIACFAQA1AAQKfzEAAg4ACQqzIcI4ABYDAA4ACQqzIcI4ABYDAAAA.Jessupy:BAABNQAECn8rAAIaAAkKhxkEGQDaAQAaAAkKhxkEGQDaAQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQADCgYIBgAAAA==.Jezliu:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgUICgABNQAECggICgAHAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAAANQAECgYIDgAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAABNQAECn8UAAIMAAcKDw86mQCoAQAMAAcKDw86mQCoAQAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalkulus:BAAANQADCgYIBwAAAA==.Kalrendion:BAAANQAECgIIAgABNQAECggIFwAXAEESAA==.Kalru:BAAANQAECgMIBQAAAA==.Kalzok:BAEANQAECgQIBQABNQAECgoKTgATAHMkAA==.Karaillyonna:BAAANQAECggIDgAAAA==.Karasu:BAAANQAECgQIDAAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAABNQAECn8UAAMGAAcKPQsmJADpAAAGAAcKPQsmJADpAAAkAAQKmQILOABeAAAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAABNQAECn8wAAMIAAoKGCSMBABdAwAIAAoKGCSMBABdAwAhAAUKuASgUgCnAAAAAA==.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAABNQAECn8hAAIXAAgKxwyFYACNAQAXAAgKxwyFYACNAQAAAA==.Killamanjoro:BAABNQAECn8cAAIDAAgKxBlnfAAkAgADAAgKxBlnfAAkAgAAAA==.Kimchiwar:BAAANQAECgcIDwAAAA==.Kirasha:BAAANQAECgIIBAAAAA==.Kitak:BAABNQAECn8XAAMXAAgKQRLSZgB1AQAXAAcKKw/SZgB1AQAWAAYKZRRcZQBdAQAAAA==.Kitchenbound:BAABNQAECn8aAAIGAAgKKBmgFgAAAgAGAAgKKBmgFgAAAgAAAA==.Kittychan:BAABNQAECn8vAAIXAAoKtRX4FQDSAQAXAAoKtRX4FQDSAQAAAA==.',
Kl='Klaacus:BAABNQAECn9EAAQbAAoKRhupCwAkAwAbAAoKRhupCwAkAwAoAAMK+wizHwBEAAAaAAEKnhH6jgA9AAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUICwAAAA==.',
Ko='Kodomo:BAAANQADCgYIBgAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAABNQAECn8dAAICAAoKACBOKAD3AgACAAoKACBOKAD3AgAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECn8fAAMQAAkKpQ7eJQAAAgAQAAkKpQ7eJQAAAgASAAEKXxJFKAA1AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECn8gAAIeAAoK5yAbBQA8AwAeAAoK5yAbBQA8AwABNQAECgoKTgATAHMkAA==.',
La='Lakshmi:BAABNQAECn8ZAAICAAgKlh+9PwCrAgACAAgKlh+9PwCrAgAAAA==.Laradin:BAAANQADCgEIAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgQIBAAAAA==.Lavagrip:BAABNQAECn8fAAMTAAUKdBMjEwH/AAATAAUKdBMjEwH/AAAgAAEKAACwcAAvAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFH8RAAMCAAUKECRmBQD+AQACAAUKECRmBQD+AQAfAAIK1BlcFABKAAA1AAQKf0wAAwIACgqBJo0EAMIDAAIACgqBJo0EAMIDAB8ABwrZI68TAMMCAAAA.Letmehealu:BAABNQAECn8ZAAIRAAgK7w1keQCuAQARAAgK7w1keQCuAQAAAA==.Lewsky:BAAANQAECgMIBgABNQAFFAMIBQATAN4LAA==.',
Li='Lichtghost:BAAANQADCggIDAAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIFwAAAA==.Lilhojx:BAAANQAECgMIAwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECn84AAIUAAoKgRgWDwCSAQAUAAoKgRgWDwCSAQAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECggIEAAAAA==.',
Lm='Lmj:BAAANQAECgIIBgAAAA==.',
Lo='Lockbox:BAABNQAECn8/AAMMAAoKJyNEBwCTAwAMAAoKJyNEBwCTAwAPAAMKFSGnLwALAQAAAA==.Lokmar:BAAANQAECgYICgAAAA==.Loomin:BAABNQAECn9GAAMOAAoKhyAhGwCUAgAOAAoKwR8hGwCUAgAYAAUK0hA6HQAEAQAAAA==.Lostpeace:BAAANQADCgcIBwAAAA==.',
Lu='Lucatia:BAABNQAECn8uAAIbAAoKgR67DgAAAwAbAAoKgR67DgAAAwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECggIDgAHAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICQAAAA==.',
['Lä']='Lädyæk:BAABNQAECn8iAAICAAoKDw5uhQAAAgACAAoKDw5uhQAAAgAAAA==.',
['Lë']='Lëäë:BAAANQAECgUIBQAAAA==.',
Ma='Madboy:BAAANQAECgYIBwAAAA==.Maekyss:BAABNQAECn8YAAMEAAkKqw38fgCPAQAEAAkKqw38fgCPAQAFAAUKghNosgAuAQAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAABNQAECn8ZAAICAAcKixu1ZgBuAQACAAcKixu1ZgBuAQAAAA==.Magimagi:BAAANQAECgcICAAAAA==.Magixstraza:BAABNQAECn81AAIOAAoKlxncOwAEAgAOAAoKlxncOwAEAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Mallidin:BAAANQAECgIIAgABNQAECgcIBwAHAAAAAA==.Malthoryn:BAAANQAECgMIAwAAAA==.Malzel:BAABNQAECn8UAAMFAAkKeBjSlwBpAQAFAAUK6RnSlwBpAQAeAAUKXBbCFwAUAQAAAA==.Mamasan:BAAANQAECgcIDAAAAA==.Mamor:BAABNQAECn8YAAICAAYK9QJCBAH9AAACAAYK9QJCBAH9AAAAAA==.Maphra:BAAANQAECgYICQAAAA==.Marli:BAAANQABCgQIBQAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQICAAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgYIEAAAAA==.',
Me='Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQAECggIDQAAAA==.Melianthal:BAAANQAECgIIAgAAAA==.Melodí:BAAANQADCggICAABNQAECgoKMAAJACAcAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgQICAAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQAECgUIBQAHAAAAAA==.Micromortis:BAAANQAECgQIBAABNQAECgcIDwAHAAAAAA==.Mikuu:BAAANQAECgYIDQAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECggIDwAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECggIEwABNQAECgoKHQAlAHYeAA==.Mitufu:BAAANQAECggIBQAAAA==.',
Mm='Mmeow:BAAANQADCggIDAAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Molded:BAAANQAECgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECn9SAAMbAAoKExxGEADwAgAbAAoKExxGEADwAgAaAAEKAg4ukgA2AAABNQAECgoKSQAaAEMXAA==.Morgul:BAABNQAECn8XAAIKAAoKpBGfGgAbAgAKAAoKpBGfGgAbAgAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Moroton:BAAANQADCgQIBAABNQAECgoKFQAkAOkRAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.',
Ms='Mseow:BAAANQAECgUIBQAAAA==.',
Mu='Mudbutbrooks:BAABNQAECn8jAAMfAAcKLBEKJADeAAAfAAcKLBEKJADeAAAdAAEKyQO1FAAoAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgoKJgARAMsdAA==.Muller:BAABNQAECn8tAAITAAkK2hJHXgCeAQATAAkK2hJHXgCeAQAAAA==.',
Mv='Mveow:BAAANQADCgYICQAAAA==.',
Mw='Mweow:BAAANQADCgcIGQAAAA==.',
Mx='Mxeow:BAAANQADCgQICAAAAA==.',
My='Mynnu:BAABNQAECn8XAAIRAAcKARdcTAB/AQARAAcKARdcTAB/AQAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Mz='Mzeow:BAAANQADCgYIBgAAAA==.',
Na='Nahda:BAAANQADCggICAAAAA==.Nautprepared:BAAANQAECgcIEgAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Nefetiree:BAAANQADCgQIBAAAAA==.Neildasstysn:BAAANQAECgYICQABNQAFFAEIAQAHAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCggILQAAAA==.',
Ni='Nickeld:BAABNQAECn8nAAIOAAoKwRlCdACVAgAOAAoKwRlCdACVAgAAAA==.Nickhy:BAABNQAECn8VAAMCAAcKzAuGwwB7AQACAAcKzAuGwwB7AQAfAAIKXAQlQwBOAAAAAA==.Nietherme:BAABNQAECn8qAAITAAoK/A+tdABpAQATAAoK/A+tdABpAQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nightmun:BAAANQAECgEIAQABNQAECgoKRAAbAEYbAA==.Nihildicits:BAAANQAECgQIBQAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgoKGwAFACcaAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQAECgQICwABNQAECgoKLwAXALUVAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAABNQAECn8XAAIRAAgKlxG3bgDSAQARAAgKlxG3bgDSAQAAAA==.Nyalore:BAAANQAECggIEwAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAQAAAA==.',
Og='Ogyaii:BAAANQAECggICQAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAABNQAECn9jAAIBAAoKhiCkCAA/AwABAAoKhiCkCAA/AwAAAA==.Oralen:BAACNQAFFH8MAAMBAAUKyhqwCgA4AQABAAUKyhqwCgA4AQATAAEKAAAWKwAAAAA1AAQKfzIAAwEACgo3I38KAHUDAAEACgo3I38KAHUDABMABAogEAANAW8AAAAA.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECn8ZAAIDAAkKKQ7PlgDjAQADAAkKKQ7PlgDjAQAAAA==.',
Ov='Overloader:BAABNQAECn80AAIaAAoKTyF0CQC7AgAaAAoKTyF0CQC7AgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Oz='Ozs:BAAANQAECgUIBQAAAA==.',
Pa='Paidactor:BAAANQAECggIDgAAAA==.Pairodeez:BAAANQADCgMIAQAAAA==.Palahang:BAAANQAECgEIAQAAAA==.Pallyaxe:BAAANQAECgUIEAABNQAECgoKOQAOABEYAA==.Pallygank:BAAANQADCgEIAQAAAA==.Pandawannabe:BAABNQAECn8cAAIFAAgKtRm3MACWAQAFAAgKtRm3MACWAQAAAA==.Pandussi:BAABNQAECn8aAAIhAAkKxhNiJAACAgAhAAkKxhNiJAACAgAAAA==.Paneer:BAABNQAECn8qAAICAAoK4SLbCwB+AwACAAoK4SLbCwB+AwABNQAECgoKHAAEANEXAA==.Paninus:BAAANQAECgEIAQAAAA==.Papabair:BAAANQAECgcICQABNQAECgcIDwAHAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgMIAQAAAA==.Peruano:BAABNQAECn8sAAIPAAoKkRTxCABsAgAPAAoKkRTxCABsAgAAAA==.Petforheals:BAAANQAECgUICwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECggIHAAFALUZAA==.',
Pi='Pietastegood:BAABNQAECn80AAIDAAoKLiIdCQCrAwADAAoKLiIdCQCrAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYIBgABNQAECggICgAHAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECgcIDwAHAAAAAA==.Pitchblack:BAABNQAECn8YAAIQAAoKugzYIAAyAgAQAAoKugzYIAAyAgAAAA==.',
Po='Pocahöntas:BAAANQAECgUICAAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAACNQAFFH8FAAIeAAIKqBcXBgCgAAAeAAIKqBcXBgCgAAA1AAQKfzwAAh4ACgpwIAQFAD8DAB4ACgpwIAQFAD8DAAAA.Pontiack:BAAANQAECggICAAAAA==.Poordemon:BAAANQADCgUIBQABNQAECggIJQAXAIcJAA==.Popehealz:BAAANQADCgYIAgAAAA==.Pownds:BAAANQAECgYICgAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAABNQAFFH8KAAIRAAYKWBoxBwDDAQARAAYKWBoxBwDDAQAAAA==.Procspls:BAAANQADCgIIAgAAAA==.Proenz:BAAANQAECgIIAgAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAQABNQAECgcIGwAGANUOAA==.Pryor:BAAANQAECgcICgAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGwAGANUOAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGwAGANUOAA==.Prøntø:BAABNQAECn8bAAMGAAcK1Q4ZJwBdAQAGAAcK1Q4ZJwBdAQAkAAIK3QP8OwBJAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgoKMgADACofAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQAECgQIBQAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECgcIDAAHAAAAAA==.Pyrista:BAABNQAECn8jAAICAAgKUhl4SgCOAgACAAgKUhl4SgCOAgAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgQIBQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECn8tAAIaAAkKVA9uOADvAQAaAAkKVA9uOADvAQAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECgoKNAADAC4iAA==.Raendarth:BAAANQAECgUIDgAAAA==.Rageth:BAABNQAECn8fAAMKAAkKtQ5hIADQAQAKAAkKtQ5hIADQAQALAAIKXgmTFgByAAAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAFFAIICQAUANgYAA==.Rakalaag:BAEANQAECgQICgAAAA==.Rakath:BAABNQAECn8UAAIZAAYKSQ8jNwDuAAAZAAYKSQ8jNwDuAAAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECn8yAAIDAAoKKh/aLAAJAwADAAoKKh/aLAAJAwAAAA==.Redharvest:BAAANQAECggICAAAAA==.Redredwine:BAAANQADCggICAAAAA==.Refractory:BAAANQAECgUIBgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAYIFwANAIodAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAABNQAECn8kAAITAAkKhRDRnADpAQATAAkKhRDRnADpAQAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBQABNQAFFAIICQAUANgYAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECn8vAAIFAAoK0RspMAC6AgAFAAoK0RspMAC6AgAAAA==.Rikoe:BAAANQAECgUIBQAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgAHAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQADCgQIBAAAAA==.',
Ro='Rockabye:BAABNQAECn8oAAMQAAkK+hpoFQC1AgAQAAkK+hpoFQC1AgARAAEKZwjlwgA7AAAAAA==.Rokar:BAAANQAECgEIAQAAAA==.Roraalionnu:BAAANQADCgUIDgABNQAECgEIAgAHAAAAAA==.Rosannas:BAAANQAECgIIAgABNQAFFAIICQAUANgYAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFH8ZAAMeAAYK9BD3AABEAQAeAAYKTQ/3AABEAQAFAAMKshGyGQD0AAA1AAQKfz8AAx4ACgrQHu0GAF0CAB4ACgqOG+0GAF0CAAUACQqKFSRIAFYCAAAA.Ruibash:BAEBNQAECn9OAAITAAoKcyTSEACGAwATAAoKcyTSEACGAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Runebladé:BAABNQAECn8YAAIXAAgKXhmUPQApAgAXAAgKXhmUPQApAgAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQAECgcIDAAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQAECgUICAAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAHAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAHAAAAAA==.Sakuraa:BAABNQAECn8uAAMRAAoKvhJTLQAPAgARAAoKvhJTLQAPAgASAAMKLQEdJABKAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAQAAAA==.Savaged:BAAANQADCggIDQABNQAECgoKSQAXAG8XAA==.Savajed:BAABNQAECn9JAAMXAAoKbxdKFgDOAQAXAAkKQBhKFgDOAQAiAAoKbBEFLQB3AQAAAA==.Savaragon:BAAANQAECgQIBQABNQAECgoKSQAXAG8XAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scaledoc:BAAANQAECgMIAwABNQAECgcIDwAHAAAAAA==.Scallywagg:BAAANQAECggIEAAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Schism:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgIIAQAAAA==.',
Se='Searcomic:BAAANQAECgcIDwAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECn8xAAMnAAoKdRYoBgBuAgAnAAoKdRYoBgBuAgALAAMKpQfZLwCbAAAAAA==.Selendas:BAAANQADCgcIDQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinanomi:BAAANQAECgEIAQAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECn83AAMGAAoKuyQ+AgCrAwAGAAoKuyQ+AgCrAwAkAAEKAABfRgAtAAAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgcIEwABNQAECgEIAgAHAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgcICgAAAA==.Shameless:BAAANQAECgcICgAAAA==.Shamwów:BAAANQAECgcIEgAAAA==.Sharco:BAABNQAECn8nAAMYAAgKvBgMDgDMAQAYAAYKpR8MDgDMAQAOAAcKrBJX8wCkAQAAAA==.Sharkbites:BAAANQAECgUICQAAAA==.Shawarmafury:BAACNQAFFH8OAAICAAUK9SNVCADFAQACAAUK9SNVCADFAQA1AAQKfzIAAgIACgrnJncCAN8DAAIACgrnJncCAN8DAAAA.Shaydens:BAAANQADCgQIBgAAAA==.Sherrizzahh:BAAANQADCgEIAQAAAA==.Shettani:BAAANQABCgYJCQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockrasta:BAAANQAECgQICwABNQAECgoKPwAYAPojAA==.Shooshmael:BAABNQAECn8cAAIFAAgKKxewWwAPAgAFAAgKKxewWwAPAgAAAA==.Shozo:BAAANQADCgUICAABNQAECgoKNwAGALskAA==.Shujáa:BAAANQAECggIDQAAAA==.Shyvîolet:BAABNQAECn8hAAMEAAkKFhWJVwALAgAEAAkKFhWJVwALAgAFAAEKMwG/YgETAAAAAA==.Shælynne:BAAANQABCgIIAgABNQAECgoKSQAaAEMXAA==.Shékinah:BAACNQAFFH8KAAIZAAMK7wFFEQCTAAAZAAMK7wFFEQCTAAA1AAQKfzEAAhkACgoJEFg9AAwCABkACgoJEFg9AAwCAAAA.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAYIFwANAIodAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAHAAAAAA==.',
Sk='Skadgrip:BAAANQAECgEIAQABNQAECgkJFAAFAHgYAA==.Skorpekh:BAABNQAECn8ZAAICAAgKSQZUsQChAQACAAgKSQZUsQChAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECn8cAAIlAAgKWR9IEwCyAgAlAAgKWR9IEwCyAgAAAA==.Sloppyspikes:BAABNQAECn8ZAAIoAAkKRwd1GAAqAQAoAAkKRwd1GAAqAQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECn9PAAMpAAoKGiPQAAAxAwApAAoKGiPQAAAxAwADAAkKxBoLWACDAgABNQAECgoKTwACAJgkAA==.Smidgenn:BAAANQADCgcIEQAAAA==.Smokyblast:BAABNQAECn8cAAIOAAkKRQaRfABJAQAOAAkKRQaRfABJAQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECn8+AAIOAAkKgwQYpQD8AAAOAAkKgwQYpQD8AAAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECn8fAAMhAAgKIg4cMgCGAQAhAAgKIg4cMgCGAQAJAAEK7g6AMQAzAAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIEQAAAA==.',
Sp='Sparowprince:BAACNQAFFH8RAAITAAYKnRiSCgCfAQATAAYKnRiSCgCfAQA1AAQKf0sAAhMACgr0JAoGAE0DABMACgr0JAoGAE0DAAAA.Spaspanda:BAAANQAECgMIAgABNQAECggIHAAFALUZAA==.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAHAAAAAA==.Spectraleye:BAAANQAECgcIDwAAAA==.Sproocherlou:BAABNQAECn8zAAITAAoKCh0jNAD8AgATAAoKCh0jNAD8AgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAABNQAECn8oAAIMAAkK9CRkEABPAwAMAAkK9CRkEABPAwAAAA==.Steezya:BAAANQAECgUIEwAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stonedemon:BAAANQAECggIDgABNQAFFAYIEQATAJ0YAA==.Stormsy:BAAANQAECgcIEwABNQAECggIGgARALUQAA==.Stormykitty:BAABNQAECn8aAAIRAAgKtRDucwDAAQARAAgKtRDucwDAAQAAAA==.Strauch:BAAANQADCgcIIgAAAA==.Striderdh:BAAANQABCggIEQAAAA==.Strongwoman:BAAANQAECgUIEAAAAA==.Sturtza:BAACNQAFFH8JAAICAAIKpBGCFgCaAAACAAIKpBGCFgCaAAA1AAQKf0EAAgIACgrDIYQGAKoDAAIACgrDIYQGAKoDAAAA.Sturtzam:BAAANQAECgUIBgABNQAFFAIICQACAKQRAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sumat:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.Sunbear:BAAANQADCggIDwAAAA==.Sungayan:BAAANQAECgMIAQAAAA==.Susak:BAAANQAECgYICwABNQAECgkJGgAWAGIeAA==.Suun:BAABNQAECn84AAITAAoK8B6VKgBVAgATAAoK8B6VKgBVAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Sweetysnail:BAAANQAECgYIEQAAAA==.Swoley:BAAANQAECggIEwAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.',
Ta='Taanua:BAAANQAECgUIBgAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECn8oAAIYAAoKpgtfDgDFAQAYAAoKpgtfDgDFAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAABNQAECn8XAAIBAAUKPBGgrwAgAQABAAUKPBGgrwAgAQAAAA==.Talisaie:BAABNQAECn8eAAIMAAoKQiEUCQDsAgAMAAoKQiEUCQDsAgABNQAFFAYIFgAaAIscAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgcIDAAHAAAAAA==.Tarahly:BAAANQAECgYIBgABNQAECggIKQABANMhAA==.Tarahse:BAAANQADCgIIAgABNQAECggIKQABANMhAA==.Taron:BAABNQAECn8dAAIDAAcKXBhOcAA4AQADAAcKXBhOcAA4AQAAAA==.Tart:BAACNQAFFH8FAAMFAAMKyw5yJACaAAAFAAIKyw5yJACaAAAEAAEKLwD/NAAXAAA1AAQKfxkAAgUACQp1EL9bAA8CAAUACQp1EL9bAA8CAAAA.',
Te='Techmaestrov:BAAANQAECgQIBAAAAA==.Tedjones:BAABNQAECn8WAAIOAAYKAwXnQQEfAQAOAAYKAwXnQQEfAQAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.Tenderrot:BAAANQADCgUIBQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thandana:BAAANQAECgQIBQAAAA==.Thehumanatee:BAABNQAECn8rAAIZAAoKwRWILQBxAgAZAAoKwRWILQBxAgAAAA==.Theroach:BAAANQAECgQIDgAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICgAHAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingstabz:BAAANQAECgEIAQAAAA==.Thingytoo:BAAANQAECgcICwAAAA==.Thiqq:BAAANQAECgUIAgAAAA==.Threlindrier:BAAANQAECgIIAwAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAABNQAECn8aAAIDAAcKqQjyjAD1AAADAAcKqQjyjAD1AAAAAA==.Thyphlo:BAAANQAECgYIDgAAAA==.',
Ti='Tictacs:BAAANQABCgYIBgAAAA==.Tiltawhirl:BAAANQAECggICQAAAA==.Tiltedup:BAABNQAECn8oAAIOAAoK8BUiLgA5AgAOAAoK8BUiLgA5AgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCggIEwABNQAECggIGgARALUQAA==.Tirich:BAAANQADCggICAABNQAFFAYIFwANAIodAA==.Titaintium:BAAANQAECgQIBAABNQAECgoKNAAaAE8hAA==.',
To='Toshi:BAABNQAECn8dAAIMAAkKSAhRpgCHAQAMAAkKSAhRpgCHAQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgkJLwAmAEQTAA==.Touchyouup:BAAANQAECgIIAQAAAA==.',
Tr='Trilguth:BAAANQADCgYIBgAAAA==.Truckkun:BAAANQAECggICgAAAA==.Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Ts='Tstick:BAAANQABCgMIBAAAAA==.',
Tu='Tulark:BAAANQABCgYIBgAAAA==.Tullydin:BAABNQAECn8nAAMgAAoKyAj1MgBLAQATAAgKRQhW3gBeAQAgAAkKewf1MgBLAQAAAA==.Tullyy:BAAANQAECgQICgAAAA==.Tums:BAABNQAECn8oAAMUAAoKohsOHAAfAQANAAkKqhvUFwAfAgAUAAgKOBcOHAAfAQAAAA==.',
Tw='Twirls:BAABNQAECn8YAAIJAAgK7RnGDQAdAgAJAAgK7RnGDQAdAgAAAA==.Twistoffate:BAABNQAECn8XAAIYAAYK9AH2NABnAAAYAAYK9AH2NABnAAAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
['Tä']='Tälos:BAAANQADCgUIBQABNQADCggIDQAHAAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAABNQAECn8XAAIYAAcKZgkyIADoAAAYAAcKZgkyIADoAAAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECn8pAAMTAAoKiR4aewA1AgATAAoKiR4aewA1AgAgAAUKwwwPTwCrAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAABNQAECn8ZAAIMAAoKEw/ZTwB0AQAMAAoKEw/ZTwB0AQAAAA==.',
Va='Valgorr:BAAANQAECgYICwAAAA==.Valvalon:BAABNQAECn8xAAIYAAoKbB1wBADlAgAYAAoKbB1wBADlAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.Vanessia:BAAANQADCgQIBAAAAA==.Varhaitof:BAAANQADCggICAAAAA==.',
Ve='Veelaria:BAABNQAECn8sAAIgAAoKbw44FgBTAQAgAAoKbw44FgBTAQAAAA==.Vegetablue:BAAANQAECgEIAQABNQAECgQIBAAHAAAAAA==.Velinddrel:BAAANQADCgUIBQAAAA==.Verahardyr:BAAANQADCgQIBAAAAA==.Veravulp:BAAANQAECgEIAQAAAA==.Verdunkeln:BAAANQAECgMIAwAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQAECgIIAQAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgoKSQAXAG8XAA==.Vicalaus:BAABNQAECn8wAAIiAAkKnRr0KQBKAgAiAAkKnRr0KQBKAgABNQAECgoKRAAbAEYbAA==.View:BAABNQAECn8jAAIEAAoKnhQ6VgAPAgAEAAoKnhQ6VgAPAgAAAA==.Vikcy:BAAANQAECgUICwAAAA==.Vikcyholy:BAAANQAECgEIAQAAAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitamind:BAAANQAECgUIBQAAAA==.Vitros:BAAANQADCgcIBwABNQAECgoKLwAQAI0fAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgkJFQAGAHMgAA==.Voidwitch:BAABNQAECn8hAAIPAAgKGyMWBADwAgAPAAgKGyMWBADwAgAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.Vortirtbreni:BAAANQAECgIIAQAAAA==.',
Vr='Vrakken:BAABNQAECn8pAAIiAAoKYBPDGwDvAQAiAAoKYBPDGwDvAQAAAA==.',
Vu='Vududonkey:BAAANQAECgMIAwABNQAECgkJFwAkAOQOAA==.',
Vy='Vyndenus:BAACNQAFFH8HAAIRAAQKqAyzFQDXAAARAAQKqAyzFQDXAAA1AAQKf0UAAhEACgp4IB8KADwDABEACgp4IB8KADwDAAAA.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECggIDAAAAA==.Welor:BAAANQAECgUIBwAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Wheremytotem:BAAANQADCggIDQABNQAECgoKJgARAMsdAA==.Whitbone:BAAANQADCgUICQAAAA==.Wholephister:BAAANQAECgEIAQABNQAECggIFQAeAFoSAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQAECggICwAAAA==.Wigpetval:BAABNQAECn8lAAMCAAgKnRGImQDUAQACAAgKURGImQDUAQAfAAIKrRVCaQCIAAAAAA==.Wiidge:BAABNQAECn8mAAImAAkKwQoTDACjAQAmAAkKwQoTDACjAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECn8XAAIZAAYK+xhMSADJAQAZAAYK+xhMSADJAQAAAA==.Wolfchan:BAABNQAECn8XAAIOAAgK3Av7eQBPAQAOAAgK3Av7eQBPAQAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgoKRAAbAEYbAA==.Worldcrafter:BAABNQAECn8hAAMSAAkK7x6PCADbAQARAAgK6R/OKgAcAgASAAYKkRuPCADbAQAAAA==.Worldender:BAAANQAECggIEQAAAA==.Wowretail:BAABNQAECn8hAAQgAAcKphs6IQDaAQAgAAYKnB46IQDaAQATAAYKZRtNrQDFAQABAAQKSSCQwQD4AAAAAA==.',
Wr='Wrathofdawn:BAAANQAECggIDQAAAA==.Wreckross:BAAANQABCgUIBQAAAA==.',
Wy='Wyldar:BAABNQAECn8cAAITAAkKVRQ5kwD9AQATAAkKVRQ5kwD9AQAAAA==.',
Xa='Xalaria:BAABNQAECn8VAAIOAAoKTAQyfgBGAQAOAAoKTAQyfgBGAQAAAA==.Xantry:BAACNQAFFH8FAAITAAMK3gveGwDJAAATAAMK3gveGwDJAAA1AAQKfxwAAhMACQr+IoE4AO4CABMACQr+IoE4AO4CAAAA.',
Xe='Xeviscerated:BAAANQAECgMIAwAAAA==.',
Xm='Xmen:BAABNQAECn8dAAIOAAcK/gd9twDYAAAOAAcK/gd9twDYAAAAAA==.',
Xs='Xslight:BAAANQAECgcICAABNQADCggIDgAHAAAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgUIBgAAAA==.',
Ye='Yeastybush:BAABNQAECn8uAAIEAAoK6CCIFAClAgAEAAoK6CCIFAClAgAAAA==.',
Yi='Yinsen:BAAANQADCggICAAAAA==.',
Ys='Yseera:BAAANQAECgUICgAAAA==.Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zarathea:BAAANQAECgMIAwABNQAECgUIBQAHAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAABNQAECn8sAAIhAAoKmRwYDwDyAgAhAAoKmRwYDwDyAgAAAA==.',
Zo='Zoeyredbird:BAABNQAECn8UAAQWAAkKOxjMMAApAQAiAAcK1RbmRgCjAQAWAAQKURnMMAApAQAXAAIKDBe+tACGAAAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.Zwhittytv:BAABNQAECn8YAAILAAoKHxSVBgDEAQALAAoKHxSVBgDEAQAAAA==.',
['Ña']='Ñazary:BAAANQADCggIDwAAAA==.',
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
