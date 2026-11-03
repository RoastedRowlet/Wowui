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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Rogue-Subtlety','Mage-Arcane','Warlock-Destruction','Priest-Shadow','Priest-Discipline','Priest-Holy','Paladin-Retribution','Rogue-Assassination','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Druid-Balance','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Warrior-Protection','Druid-Feral','Druid-Restoration','Warlock-Affliction','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aamara:BAABNQAECn8lAAIBAAcKyx3xQQBdAgABAAcKyx3xQQBdAgABNQAECgoKHwACACMdAA==.',
Ab='Aboyton:BAAANQAECgEIAgAAAA==.',
Ad='Adarksoul:BAAANQAECgEIAQAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwADAPkTAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAACNQAFFH8OAAMEAAUKBhF9EQAAAQAEAAQK3g59EQAAAQAFAAMKXyGgFACjAAA1AAQKf0AAAwUACgpSJaECAGwDAAUACgpSJaECAGwDAAQACgp8FFtNAC4CAAAA.Aelistiah:BAAANQAECgMIAgAAAA==.Aerithorn:BAABNQAECn8dAAIGAAgKciCzCQDYAgAGAAgKciCzCQDYAgAAAA==.Aestus:BAAANQABCgIIAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgoKNAACACkYAA==.Ahleya:BAAANQAECgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAHAAAAAA==.',
Ak='Akazza:BAAANQADCgIIAgAAAA==.Akoris:BAAANQAECgQIBQABNQAECgoKLAAIACwVAA==.Akorys:BAABNQAECn8sAAMIAAoKLBUdDgD6AQAIAAoKLBUdDgD6AQAJAAEKAAB9NQAiAAAAAA==.',
Al='Albyno:BAACNQAFFH8QAAMKAAcKuQv1CwBeAQAKAAcKuQv1CwBeAQALAAEK8wYCEAA/AAA1AAQKfzcAAgoACgrVH/0DADIDAAoACgrVH/0DADIDAAAA.Algebrah:BAAANQAECgQICgAAAA==.Alivallia:BAAANQADCgUIBQABNQAECggIIQAFAG8dAA==.Alucius:BAAANQADCgQIBAAAAA==.',
Am='Amara:BAAANQADCgYILAAAAA==.Ambitionz:BAAANQAECgEIBAAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECn9CAAIMAAgKowZWkwD9AAAMAAgKowZWkwD9AAAAAA==.Ancksunamun:BAAANQADCggIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgoKHwACACMdAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFH8YAAINAAcKhhnwBQC9AQANAAcKhhnwBQC9AQA1AAQKfyYAAg0ACgp6Ht0FACgDAA0ACgp6Ht0FACgDAAAA.',
Ap='Aperture:BAAANQADCgcIEwAAAA==.',
Aq='Aquua:BAABNQAECn86AAIFAAoKdx6jHQBWAgAFAAoKdx6jHQBWAgAAAA==.',
Ar='Araelen:BAABNQAECn8UAAIOAAgKTwUDHAFdAQAOAAgKTwUDHAFdAQAAAA==.Arcticdps:BAABNQAECn8tAAMMAAoKpha+RACEAgAMAAoKpha+RACEAgAPAAEKVxYCbgBDAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECn8zAAQQAAoKjR9gKwDMAQAQAAYKeRpgKwDMAQARAAcKUQ6GDABwAQASAAgKGBQlaABpAQAAAA==.Ariestar:BAABNQAECn8UAAITAAgKCghm3QBgAQATAAgKCghm3QBgAQAAAA==.Ariiel:BAAANQADCggICQABNQAECgoKMwAQAI0fAA==.Arrax:BAAANQADCgQIBAAAAA==.Arthimas:BAAANQAECgIIAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAABNQAECn8hAAIQAAcKGQvrKAAAAQAQAAcKGQvrKAAAAQAAAA==.Asidize:BAAANQAECgUICgAAAA==.Aslor:BAABNQAECn8mAAIMAAkKsRiiZgAnAgAMAAkKsRiiZgAnAgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYIDwAAAA==.',
At='Athalia:BAACNQAFFH8LAAMUAAIK2BiDCACUAAANAAIKURTDFgCZAAAUAAIKqRiDCACUAAA1AAQKfz4AAxQACgpIIzoFAIADABQACQqjIzoFAIADAA0ACAofGvEkAD8CAAAA.Atlaswolfe:BAAANQAECgcIBwAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECgcIDgAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAABNQAECn80AAICAAoKKRhGUwDlAQACAAoKKRhGUwDlAQAAAA==.',
Ax='Axemage:BAABNQAECn9CAAIOAAoKfhlgOwA4AgAOAAoKfhlgOwA4AgAAAA==.Axeom:BAABNQAECn88AAIEAAoKEx1yJwDGAgAEAAoKEx1yJwDGAgAAAA==.Axeshammy:BAAANQAECggICwABNQAECgoKQgAOAH4ZAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAACNQAFFH8GAAIOAAMKsAjYIgDOAAAOAAMKsAjYIgDOAAA1AAQKfxcAAg4ACQqhGiSjADsCAA4ACQqhGiSjADsCAAAA.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAABNQAECn8XAAITAAgKQBkCsQC9AQATAAgKQBkCsQC9AQAAAA==.Baldie:BAAANQAECgYICAAAAA==.Bamboolan:BAAANQAECggICwAAAA==.Barcliah:BAAANQADCgIIAgAAAA==.Barometer:BAAANQAECgcIEgAAAA==.Bast:BAAANQAECggIAQABNQAECgoKGAATAC4MAA==.Baxa:BAAANQAECggICgAAAA==.Baylee:BAABNQAECn8lAAIOAAgKiQScMwE2AQAOAAgKiQScMwE2AQAAAA==.',
Bb='Bbartemis:BAABNQAECn8oAAINAAkKogVwdADzAAANAAkKogVwdADzAAAAAA==.',
Bc='Bchamp:BAAANQAECgMIAwAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgQIBAABNQAECgYIBwAHAAAAAA==.Beekerr:BAAANQADCgMIBAABNQAECgoKLwANAKEcAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgUIBgAAAA==.Belzenlok:BAAANQAECgIIAwAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAABNQAECn8aAAIVAAkKXAgeAwBUAQAVAAkKXAgeAwBUAQAAAA==.Bergamö:BAAANQAFFAEIAQAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcICgAAAA==.Bigangus:BAAANQAECgMIDAAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Bigmerch:BAAANQADCgcIDgAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAABNQAECn8YAAIOAAcKxwIU7ACuAAAOAAcKxwIU7ACuAAAAAA==.Bisholoyd:BAABNQAECn8gAAIPAAcK3gqjHwByAQAPAAcK3gqjHwByAQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgQIAwAAAA==.Blastoise:BAABNQAECn9CAAMWAAoK7iOhBACnAwAWAAoKmyOhBACnAwAXAAoKkyAFCADbAgAAAA==.Blinktwice:BAAANQAECgEIAQAAAA==.Blizfishleg:BAABNQAECn8cAAIYAAYKFg+1FABfAQAYAAYKFg+1FABfAQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bloodshell:BAAANQAECgcICAABNQAECgkJIAAZAH0bAA==.Bloodybren:BAAANQAECgMIBgAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgYICAAAAA==.Bongwater:BAAANQADCgEIAQABNQAECgoKOAAaAIkiAA==.Bonkyo:BAAANQADCgYIBgAAAA==.Boombóx:BAAANQAECgQIEAABNQAECgoKRwAMABYkAA==.Boome:BAAANQAECgIIAgABNQAFFAIICwAUANgYAA==.Boostia:BAAANQAECgQIBgAAAA==.Borthos:BAABNQAECn81AAIbAAoK9iAEDQBgAgAbAAoK9iAEDQBgAgAAAA==.Bowsback:BAAANQADCggILwAAAA==.Bowyohead:BAABNQAECn8sAAISAAoKyx0jHgC5AgASAAoKyx0jHgC5AgAAAA==.',
Br='Bracydaboss:BAAANQAECgEIAwAAAA==.Bradroybboi:BAAANQAECgUIEQAAAA==.Braingap:BAAANQAECgcIEQABNQAECggIDAAHAAAAAA==.Brandoe:BAAANQAECgQIBgAAAA==.Breece:BAAANQAECgQIBAAAAA==.Brickinkeys:BAAANQAECggIEwABNQAECgoKHwACACMdAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECn8yAAIcAAoK8wiyAwBsAQAcAAoK8wiyAwBsAQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caenarigos:BAAANQAECgIIAQAAAA==.Caenarius:BAAANQADCgMIAwABNQAECgIIAQAHAAAAAA==.Caimie:BAAANQAECgQIBwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQICQAAAA==.Capnmorgan:BAAANQABCgEIAQAAAA==.Cassiaan:BAAANQAECgMIAwAAAA==.Caylavibes:BAABNQAECn8iAAISAAoKEBD0VAAkAgASAAoKEBD0VAAkAgAAAA==.',
Ch='Chaviel:BAAANQAECggICgAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAABNQAECn8gAAISAAkK8RZBMQBIAgASAAkK8RZBMQBIAgAAAA==.Chironn:BAABNQAECn9DAAIdAAoK8BqVAgCAAgAdAAoK8BqVAgCAAgAAAA==.Chudlord:BAAANQADCggICwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cilyian:BAAANQADCgQIBAABNQAECgoKFgAKAFgQAA==.Cinderburn:BAAANQAECgQIDwAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgQIBQAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAQAAAA==.Comfychair:BAABNQAECn8mAAITAAkKWyBtQQDQAgATAAkKWyBtQQDQAgAAAA==.Conclaved:BAAANQAECggIAgAAAA==.Coowmoo:BAABNQAECn8XAAIeAAgKUBJrHQCLAQAeAAgKUBJrHQCLAQAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAUICQAfAI0WAA==.Cosmonodder:BAAANQAECggIEwABNQAFFAUICQAfAI0WAA==.Cosmoshotter:BAACNQAFFH8JAAMfAAUKjRbeFADyAAAfAAQKjRbeFADyAAACAAIKAAD6NwBLAAA1AAQKfyYAAx8ACgobIPAQAPoBAB8ACgocHfAQAPoBAAIAAgrpIw8DAW0AAAAA.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Crazyotto:BAAANQABCggIBwAAAA==.Cremebrule:BAAANQAECgEIBgAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cuchulainn:BAAANQADCgQIBAAAAA==.Cucubau:BAAANQADCggIGwAAAA==.',
Cy='Cyndra:BAABNQAECn8bAAIOAAoKxQgMkgBUAQAOAAoKxQgMkgBUAQAAAA==.',
Da='Dacura:BAAANQAECgQIBQAAAA==.Dakai:BAAANQAECgEIAQAAAA==.Dallthyrian:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.Dalthyrian:BAAANQAECgYIDwABNQAECgUICAAHAAAAAA==.Dalthyriian:BAAANQAECgUICAAAAA==.Dalthyrrian:BAAANQAECgEIAQABNQAECgUICAAHAAAAAA==.Dalthyyrian:BAABNQAECn8ZAAIgAAgKnxCYHwA8AQAgAAgKnxCYHwA8AQABNQAECgUICAAHAAAAAA==.Damii:BAAANQADCgYIEgAAAA==.Danarand:BAAANQADCgYIBwABNQAECgkJIwAGAF0RAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgkJFAAFAJsOAA==.Darjen:BAABNQAECn8VAAICAAYKdhltiQBcAQACAAYKdhltiQBcAQAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darkshock:BAAANQAECggIDQAAAA==.Darkski:BAAANQAECgIIAwAAAA==.Darksky:BAABNQAECn8bAAIbAAoKiB5ICAC5AgAbAAoKiB5ICAC5AgAAAA==.Darthra:BAAANQAECgEIAQAAAA==.Daysfox:BAACNQAFFH8JAAIfAAMKxwlkDQDFAAAfAAMKxwlkDQDFAAA1AAQKf0IAAx8ACQoSEVMSAOQBAB8ACQoSEVMSAOQBAAIAAQq6DAFPAUMAAAAA.Daysmonk:BAABNQAECn8vAAIhAAkKWQwkGgChAQAhAAkKWQwkGgChAQAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCggIDQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deadxpool:BAAANQAECgEIAQAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgoKRwAUALAfAA==.Deathdro:BAAANQADCgEIAQAAAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECn9HAAMUAAoKsB8vBQCoAgAUAAkKsB8vBQCoAgANAAUKKgtnOgDkAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathsdawn:BAAANQAECggIDgABNQAECgoKSwAbAEYbAA==.Deathstone:BAABNQAECn8yAAMiAAoKkB8IDgDEAgAiAAoKkB8IDgDEAgAXAAUKiw/0VgCHAAABNQAFFAYIEgATAJ0YAA==.Deathtress:BAABNQAECn8bAAQiAAkKwhHHMgAVAgAiAAkKwhHHMgAVAgAXAAEKNAN69QAiAAAWAAEKAAAP3QAhAAAAAA==.Debbydowner:BAABNQAECn8yAAIDAAoK2guZdwBlAQADAAoK2guZdwBlAQAAAA==.Decado:BAABNQAECn8YAAITAAoKLgwCvQCjAQATAAoKLgwCvQCjAQAAAA==.Dedine:BAAANQAECgQIBAAAAA==.Deemwins:BAAANQAECgUIBQAAAA==.Deezenuts:BAAANQAFFAEIAQAAAA==.Degen:BAABNQAECn8ZAAIZAAcKNgo6QwDnAAAZAAcKNgo6QwDnAAAAAA==.Dejevoid:BAABNQAECn8XAAIbAAoK6wbPOQB3AQAbAAoK6wbPOQB3AQAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Deliquium:BAAANQAECgEIAQABNQAECgoKFgAKAFgQAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECn8sAAMjAAoK6Rc0DgBMAgAjAAoK6Rc0DgBMAgADAAMKuAh9JgGLAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Dethmoora:BAAANQADCgYIBgAAAA==.Deww:BAABNQAECn8rAAMRAAoKUBv+BABpAgARAAgKQxj+BABpAgASAAoKURjmKwBjAgAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECn8oAAIgAAkKmgrKKQDyAAAgAAkKmgrKKQDyAAAAAA==.',
Di='Diablesse:BAAANQAECgUIBQAAAA==.Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECn8yAAIWAAoKWiIJFAAMAwAWAAoKWiIJFAAMAwAAAA==.',
Do='Docdolittle:BAABNQAECn9YAAMCAAoKryRQCAA2AwACAAoKryRQCAA2AwAfAAEKdBHKggA9AAAAAA==.Docfreez:BAABNQAECn9HAAMYAAoKTyTEBwBwAgAOAAoKXSExQgAAAwAYAAgKjCLEBwBwAgAAAA==.Docragosa:BAAANQAECgMIBAABNQAECggIEwAHAAAAAA==.Doctermoo:BAABNQAECn8dAAMEAAgKghbkMgAhAgAEAAgKghbkMgAhAgAFAAIK3QAd/AAIAAAAAA==.Dogar:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECgoKNQAbAPYgAA==.Dopewashere:BAAANQADCgQIAwAAAA==.Doraemee:BAAANQAECgcIEgAAAA==.',
Dr='Drbaconbrgr:BAABNQAECn8kAAISAAkKFh03IgCdAgASAAkKFh03IgCdAgABNQAECgoKQgACACQlAA==.Drbakedziti:BAAANQADCggIDgABNQAECgoKQgACACQlAA==.Drbaobuns:BAAANQAECgYICwABNQAECgoKQgACACQlAA==.Drcarrotcake:BAAANQAECgcIEAABNQAECgoKQgACACQlAA==.Drcheeseball:BAAANQAECgYIDgABNQAECgoKQgACACQlAA==.Drchikenparm:BAAANQADCgIIAgABNQAECgoKQgACACQlAA==.Dreggsalad:BAAANQAECgUIDwABNQAECgoKQgACACQlAA==.Dreim:BAEANQAECgYIBgABNQAECgoKVAATANokAA==.Dreima:BAAANQAECgQIBAAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgoKQgACACQlAA==.Drgatorwine:BAABNQAECn8UAAIgAAcKWBv2HgDvAQAgAAcKWBv2HgDvAQABNQAECgoKQgACACQlAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgoKQgACACQlAA==.Drkimchirice:BAABNQAECn8yAAIkAAoKsSRkAQBKAwAkAAoKsSRkAQBKAwABNQAECgoKQgACACQlAA==.Drmacncheese:BAABNQAECn80AAIPAAoKnx/lAADUAgAPAAoKnx/lAADUAgABNQAECgoKQgACACQlAA==.Drpumpkinpie:BAABNQAECn8lAAITAAoKUhpZQAA3AgATAAoKUhpZQAA3AgABNQAECgoKQgACACQlAA==.Drshephardpi:BAAANQADCggICgABNQAECgoKQgACACQlAA==.Drshortbread:BAAANQAECgYIDQABNQAECgoKQgACACQlAA==.Druiddres:BAAANQAECgUIBAAAAA==.Drwontonsoup:BAABNQAECn9CAAICAAoKJCXkBABYAwACAAoKJCXkBABYAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.Dumpstur:BAAANQAECgUIDQAAAA==.',
['Dé']='Déath:BAAANQAECgEIAgAAAA==.',
['Dö']='Dööku:BAAANQAECgYIBgAAAA==.',
Ei='Eighteen:BAACNQAFFH8FAAINAAIK4ApZGACKAAANAAIK4ApZGACKAAA1AAQKfzcAAg0ACgr3H2IGABsDAA0ACgr3H2IGABsDAAAA.',
Ek='Eksi:BAABNQAECn8jAAIhAAkKjRSXHQB9AQAhAAkKjRSXHQB9AQAAAA==.',
El='Eladaradar:BAAANQAECgEIAQAAAA==.Elethe:BAAANQAECgMIBgABNQAFFAcIGAANAIYZAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgQIBgAAAA==.Ellilina:BAAANQAECgIIAgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgQIBAAAAA==.',
Em='Embedded:BAABNQAECn8UAAMFAAkKmw4rdADFAQAFAAgKfBArdADFAQAeAAEKWAPTMQAuAAAAAA==.Eme:BAABNQAECn8WAAMKAAoKWBCODgDnAQAKAAkKeQ6ODgDnAQALAAMKEAb7HQBPAAAAAA==.Empress:BAABNQAECn8hAAIiAAkKmguXTwB2AQAiAAkKmguXTwB2AQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Enriq:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.Entrophi:BAAANQADCgMIAwABNQADCgQIBAAHAAAAAA==.',
Er='Erikaa:BAABNQAECn8bAAITAAkKxwtulgBfAQATAAkKxwtulgBfAQAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.Errour:BAAANQADCgQIBAAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIAQAHAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECggIDAAHAAAAAA==.',
Ex='Excruciator:BAABNQAECn8vAAMZAAoKMBLwRwDLAQAZAAoKMBLwRwDLAQAlAAIKtAfIZgBqAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAABNQAECn8hAAIhAAkK2RIAGQCvAQAhAAkK2RIAGQCvAQAAAA==.Falloutzhunt:BAAANQADCgYIBgABNQAECgkJIQAhANkSAA==.Fantarada:BAAANQADCgcIDAAAAA==.Farahcanle:BAABNQAECn9OAAIGAAoKFBMuFAC7AQAGAAoKFBMuFAC7AQAAAA==.Farrock:BAABNQAECn8oAAIGAAkKGwzdJAAlAQAGAAkKGwzdJAAlAQAAAA==.Fatherzimms:BAAANQAECgEIAQAAAA==.Fawxette:BAAANQAECgIIAQABNQAECgoKTAAaAPEYAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAABNQAECn8pAAIOAAkKYQltfQCBAQAOAAkKYQltfQCBAQAAAA==.Fenra:BAAANQADCgcIEAAAAA==.Feorblarir:BAABNQAECn8VAAIkAAoK6RFADQCpAQAkAAoK6RFADQCpAQAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQAECgQIBAABNQAECgkJIwAjAC0LAA==.Filledegel:BAAANQAECgQICQABNQAECgcIDgAHAAAAAA==.Finowscath:BAAANQAECgMIAwAAAA==.Firequencher:BAABNQAECn8gAAIZAAkKfRsxNABGAgAZAAkKfRsxNABGAgAAAA==.Fistacuffs:BAAANQAECgQIAgAAAA==.Fistdoc:BAAANQAECggIEwAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQAECgIIAgAAAA==.Fié:BAAANQAECgYIBgABNQAECgoKTAAaAPEYAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECn9MAAIaAAoK8RiEFABKAgAaAAoK8RiEFABKAgAAAA==.Foxknight:BAAANQADCgQIBAABNQAECgoKTAAaAPEYAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCggIEgABNQAECgkJIwAGAF0RAA==.',
Fr='Frederick:BAAANQAECggICAAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECn8uAAIBAAoKLB04KQDDAgABAAoKLB04KQDDAgAAAA==.Friendofbear:BAACNQAFFH8NAAICAAQKIw3sEgDYAAACAAQKIw3sEgDYAAA1AAQKfzcAAgIACgpMGs44AMACAAIACgpMGs44AMACAAAA.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAABNQAECn8VAAIjAAgKgwVOIQC7AAAjAAgKgwVOIQC7AAAAAA==.Fuzywuzzy:BAABNQAECn8VAAMGAAkKcyBrBgAqAwAGAAkKcyBrBgAqAwAkAAQK6A0gKQDGAAAAAA==.Fuzzycoochy:BAAANQADCgQIBAAAAA==.Fuzzykuntz:BAABNQAECn8jAAIXAAoK3gkHLABUAQAXAAoK3gkHLABUAQAAAA==.Fuzzypus:BAAANQADCgYIBgAAAA==.',
Fw='Fwoom:BAAANQADCgUIBQAAAA==.',
Fy='Fynsdood:BAABNQAECn8jAAIGAAkKXRGgIgCCAQAGAAkKXRGgIgCCAQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgkJIwAGAF0RAA==.',
Ga='Gabelock:BAACNQAFFH8dAAQMAAcK0hVjCABZAQAMAAYKcxhjCABZAQAPAAEKUgtbHgBLAAAmAAEKAADnEgA8AAA1AAQKf0AABAwACgp/IyklAO8CAAwACgp/IyklAO8CAA8ABAouGY4wAAYBACYABAqbHrgOAAABAAAA.Gabemage:BAABNQAECn8ZAAIOAAkKkhGfswAcAgAOAAkKkhGfswAcAgAAAA==.Gala:BAAANQAECgYIBwAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAABNQAECn8hAAITAAoKlhKQmgDuAQATAAoKlhKQmgDuAQAAAA==.',
Gi='Gigah:BAABNQAECn8XAAINAAoKww54FwAjAgANAAoKww54FwAjAgAAAA==.Gingerbell:BAAANQABCggICgAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgcIEgAAAA==.Glutebruiser:BAAANQAECgUICgABNQAECgkJKgAMAP8kAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQAECgEIAQAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECn8XAAIIAAgKVyJuCwDNAgAIAAgKVyJuCwDNAgAAAA==.Grimspark:BAAANQABCgUIBQAAAA==.Grimtree:BAABNQAECn83AAMmAAoK+xH+BwAVAgAmAAgKLRX+BwAVAgAMAAgK0wrUfAAxAQAAAA==.Grindor:BAAANQADCggIDAAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgYICwAAAA==.Grumpydemon:BAABNQAECn9CAAIbAAoKvBqSEgAFAgAbAAoKvBqSEgAFAgAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gu='Guglugauthu:BAAANQAECgIIAgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQAECgUIBwABNQAECgoKVAATANokAA==.Halfskul:BAABNQAECn8YAAIXAAgK2guCZgB3AQAXAAgK2guCZgB3AQAAAA==.Halotic:BAAANQAECgUIBwAAAA==.Hashah:BAABNQAECn8aAAIQAAcKRyCtGwBqAgAQAAcKRyCtGwBqAgAAAA==.Hatefel:BAAANQAECgUIBQABNQAECgkJKAAPAKoiAA==.Havoke:BAAANQADCggIHgAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgoKMQAnAHUWAA==.Healyaass:BAAANQADCggIIgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgAQAEcgAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgoKHwACACMdAA==.Heyyboyy:BAACNQAFFH8FAAICAAQKSxieDAAEAQACAAQKSxieDAAEAQA1AAQKf0wAAwIACgqvJNwKAIYDAAIACgqvJNwKAIYDAB8AAwonGfMqANwAAAAA.',
Ho='Holyaefar:BAAANQAFFAIIAwABNQAFFAUIDgAEAAYRAA==.Holymolydin:BAAANQADCggIBgAAAA==.Holysab:BAABNQAECn8gAAMBAAgKFR/qGADCAgABAAgKFR/qGADCAgATAAIKOgmzQAFcAAAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAABNQAECn8fAAMSAAoKUhmpSwBCAgASAAoKUhmpSwBCAgAQAAIKqgZvVgA0AAAAAA==.Holz:BAAANQAECgMICAAAAA==.Horsetowater:BAAANQAECgUIDAABNQAECgoKLAASAMsdAA==.Hotsfordays:BAAANQAECggIEAAAAA==.',
Hu='Hugoman:BAAANQAECggIEQABNQAECgoKNgAXAK8YAA==.Huni:BAABNQAECn8cAAIEAAkKsx5ZKADCAgAEAAkKsx5ZKADCAgAAAA==.Hunterj:BAAANQAECgMIAwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAABNQAECn8kAAITAAoKlRQfWADvAQATAAoKlRQfWADvAQAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgQIBAABNQAECggICwAHAAAAAA==.',
Ib='Ibun:BAAANQAECgcIDgAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECn8oAAIBAAkKYBgCLgCuAgABAAkKYBgCLgCuAgABNQAECgoKLAASAMsdAA==.',
Id='Idgafadin:BAAANQAECgUIBQAAAA==.',
Ig='Igneus:BAACNQAFFH8ZAAIOAAcKWSAMBwC4AQAOAAcKWSAMBwC4AQA1AAQKfz0AAg4ACgq3JMEEAFUDAA4ACgq3JMEEAFUDAAAA.Igriz:BAAANQADCggIMAAAAA==.',
Ii='Iillil:BAACNQAFFH8IAAIbAAQKdATNDgCxAAAbAAQKdATNDgCxAAA1AAQKfysAAhsACgp6DCwsAOABABsACgp6DCwsAOABAAAA.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgUICwAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQADCgMIBQAAAA==.Insidedoubt:BAAANQAECgcIDwAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUIBQAAAA==.',
It='Itsjeff:BAABNQAECn8YAAMfAAkKeRR5IgAdAQACAAQKcRmD6wAqAQAfAAgK9xF5IgAdAQAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQAECggIEwAAAA==.Jambonjay:BAABNQAECn8gAAIDAAcKuwl+zgBXAQADAAcKuwl+zgBXAQABNQAECggIJwACAJ0RAA==.Jananda:BAABNQAECn8mAAMlAAYKlgGhWABfAAAlAAYKlgGhWABfAAAZAAYK5QAHqABIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jastora:BAAANQADCgEIAQABNQADCggIDQAHAAAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgABNQAECgoKJgAlABEfAA==.Jckjckjck:BAAANQADCgUIBQABNQAECgoKJgAlABEfAA==.Jckjckjckjck:BAABNQAECn8mAAQlAAoKER+lBwAuAwAlAAkKOSClBwAuAwAZAAkKKh9cIwC1AgAGAAUKoBulKwD2AAAAAA==.',
Je='Jearn:BAAANQAECgMICAAAAA==.Jermagedupri:BAACNQAFFH8PAAIOAAUKTRUkIACFAQAOAAUKTRUkIACFAQA1AAQKfzEAAg4ACQqzIcI4ABYDAA4ACQqzIcI4ABYDAAAA.Jessupy:BAABNQAECn8xAAIaAAkK4xvyHQDjAQAaAAkK4xvyHQDjAQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQADCgYIBgAAAA==.Jezliu:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgUIDAABNQAECggICgAHAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAABNQAECn8VAAIOAAgKSQlvMAE7AQAOAAgKSQlvMAE7AQAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAABNQAECn8ZAAIMAAgKzg06mQCoAQAMAAgKzg06mQCoAQAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalkulus:BAAANQADCgYIBwAAAA==.Kalrendion:BAAANQAECgIIAgABNQAECggIGQAXAJESAA==.Kalru:BAAANQAECgQICQAAAA==.Kalzok:BAEANQAECgQIBQABNQAECgoKVAATANokAA==.Karaillyonna:BAAANQAECgcIDgAAAA==.Karasu:BAAANQAECgQIDwAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAABNQAECn8WAAMGAAcKPQsrLADzAAAGAAcKPQsrLADzAAAkAAQKmQILOABeAAAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAACNQAFFH8FAAIIAAMKSxtOBQD9AAAIAAMKSxtOBQD9AAA1AAQKfzEAAwgACgoYJIwEAF0DAAgACgoYJIwEAF0DACEABQq4BKBSAKcAAAAA.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAwAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAABNQAECn8jAAIXAAkKpQxnNAAjAQAXAAkKpQxnNAAjAQAAAA==.Killamanjoro:BAABNQAECn8cAAIDAAgKxBlnfAAkAgADAAgKxBlnfAAkAgAAAA==.Kimchiwar:BAAANQAECgcIEAAAAA==.Kirasha:BAAANQAECgMIBwAAAA==.Kitak:BAABNQAECn8ZAAMXAAgKkRLSZgB1AQAXAAcKKw/SZgB1AQAWAAYK2xRcZQBdAQAAAA==.Kitchenbound:BAABNQAECn8aAAIGAAgKKBmgFgAAAgAGAAgKKBmgFgAAAgAAAA==.Kittychan:BAABNQAECn82AAIXAAoKrxg1EwAxAgAXAAoKrxg1EwAxAgAAAA==.',
Kl='Klaacus:BAABNQAECn9LAAQbAAoKRhupCwAkAwAbAAoKRhupCwAkAwAoAAMK+wiqJQBEAAAaAAEKnhH6jgA9AAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUICwAAAA==.',
Ko='Kodomo:BAAANQADCgYIBgAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Kratosmall:BAAANQADCgcIBwABNQAECgYIDgAHAAAAAA==.Krazm:BAABNQAECn8mAAICAAoKACBOKAD3AgACAAoKACBOKAD3AgAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECn8fAAMQAAkKpQ7eJQAAAgAQAAkKpQ7eJQAAAgARAAEKXxJFKAA1AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECn8kAAIeAAoKVSIbBQA8AwAeAAoKVSIbBQA8AwABNQAECgoKVAATANokAA==.',
La='Lakshmi:BAABNQAECn8fAAICAAoKIx29PwCrAgACAAoKIx29PwCrAgAAAA==.Laradin:BAAANQADCgEIAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgQICgAAAA==.Lavagrip:BAABNQAECn8jAAMTAAUKdBMjEwH/AAATAAUKdBMjEwH/AAAgAAEKAACwcAAvAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFH8RAAMCAAUKECRmBQD+AQACAAUKECRmBQD+AQAfAAIK1BkuGQBKAAA1AAQKf1MAAwIACgq3Jo0EAMIDAAIACgq3Jo0EAMIDAB8ABwrZI68TAMMCAAAA.Letmehealu:BAABNQAECn8aAAISAAkK8AxkeQCuAQASAAkK8AxkeQCuAQAAAA==.Lewsky:BAAANQAECgMIBgABNQAFFAMIBQATAN4LAA==.',
Li='Lichtghost:BAAANQADCggIDAAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIFwAAAA==.Lilhojx:BAAANQAECgMIAwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECn89AAIUAAoK5RiRDADeAQAUAAoK5RiRDADeAQAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECggIEAAAAA==.',
Lm='Lmj:BAAANQAECgMIBgAAAA==.',
Lo='Lockbox:BAABNQAECn9HAAMMAAoKFiREBwCTAwAMAAoKFiREBwCTAwAPAAMKFSGnLwALAQAAAA==.Lokmar:BAAANQAECgYICgAAAA==.Loomin:BAABNQAECn9MAAMOAAoKnyHeGADLAgAOAAoKFyHeGADLAgAYAAUK0hA6HQAEAQAAAA==.Lostpeace:BAAANQADCgcIBwAAAA==.',
Lu='Lucatia:BAABNQAECn8vAAIbAAoKgR67DgAAAwAbAAoKgR67DgAAAwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgcIDgAHAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICQAAAA==.',
['Lä']='Lädyæk:BAABNQAECn8oAAICAAoKnA40YgC6AQACAAoKnA40YgC6AQAAAA==.',
['Lë']='Lëäë:BAAANQAECgUIBQAAAA==.',
Ma='Madboy:BAAANQAECgYICAAAAA==.Maekyss:BAABNQAECn8fAAMEAAoKMg38fgCPAQAEAAoKMg38fgCPAQAFAAcK1RNmbgADAQAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAABNQAECn8bAAICAAgKkhl+cQCUAQACAAgKkhl+cQCUAQAAAA==.Magimagi:BAAANQAECggIEAAAAA==.Magixstraza:BAABNQAECn88AAIOAAoK7hkCNQBPAgAOAAoK7hkCNQBPAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Mallidin:BAAANQAECgIIBwABNQAECggICwAHAAAAAA==.Malthoryn:BAAANQAECgMIAwAAAA==.Malzel:BAABNQAECn8UAAMFAAkKeBjSlwBpAQAFAAUK6RnSlwBpAQAeAAUKXBaTHQAFAQAAAA==.Mamasan:BAAANQAECgcIDAAAAA==.Mamor:BAABNQAECn8fAAICAAYKOgTq2QC7AAACAAYKOgTq2QC7AAAAAA==.Maphra:BAAANQAECgcIDwAAAA==.Marli:BAAANQABCgQIBQAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQICAAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgYIEgAAAA==.',
Me='Mechabull:BAAANQAECgEIAQAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAABNQAECn8UAAMpAAoKlw2CEQAeAQApAAYKdRCCEQAeAQADAAkKGgoyrwDkAAAAAA==.Melianthal:BAAANQAECgIIBAAAAA==.Melodí:BAAANQADCggICAABNQAECgoKNAAJAB0dAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgQICAAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQAECgUIBQAHAAAAAA==.Micromortis:BAAANQAECgQIBAABNQAECggIEwAHAAAAAA==.Mikuu:BAAANQAECgUIDwAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECggIEAAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECggIEwABNQAECgoKJgAlABEfAA==.Mitufu:BAAANQAECggIBwAAAA==.',
Mm='Mmeow:BAAANQADCggIEAAAAA==.',
Mo='Moelestyr:BAAANQAECgEIAgAAAA==.Mogonn:BAAANQABCgEIAQAAAA==.Molded:BAAANQAECgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECn9eAAMbAAoKXBxGEADwAgAbAAoKXBxGEADwAgAaAAEKAg4ukgA2AAABNQAECgoKTAAaAPEYAA==.Morgul:BAABNQAECn8XAAIKAAoKpBGfGgAbAgAKAAoKpBGfGgAbAgAAAA==.Moriru:BAAANQAECgYICAAAAA==.Moroton:BAAANQADCgQIBAABNQAECgoKFQAkAOkRAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgQIBQAAAA==.Movechill:BAAANQAECggIDQAAAA==.',
Ms='Mseow:BAAANQAECgUICQAAAA==.',
Mu='Mudbutbrooks:BAABNQAECn8lAAMfAAcK9BEXKgDiAAAfAAcK9BEXKgDiAAAdAAEKyQO1FAAoAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgoKLAASAMsdAA==.Muller:BAABNQAECn8tAAITAAkK2hKRlgD2AQATAAkK2hKRlgD2AQAAAA==.',
Mv='Mveow:BAAANQADCgYICQAAAA==.',
Mw='Mweow:BAAANQADCgcIHQAAAA==.',
Mx='Mxeow:BAAANQADCgQICgAAAA==.',
My='Mynnu:BAABNQAECn8ZAAISAAcKARcbZgBwAQASAAcKARcbZgBwAQAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Mz='Mzeow:BAAANQADCgYICwAAAA==.',
Na='Nahda:BAAANQADCggIEAAAAA==.Nautprepared:BAABNQAECn8WAAIaAAkKQQVbSADPAAAaAAkKQQVbSADPAAAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neegris:BAAANQADCgQIBAAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Nefetiree:BAAANQADCgQIBAAAAA==.Neildasstysn:BAAANQAECgYICQABNQAFFAEIAQAHAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCggIMAAAAA==.',
Ni='Nickeld:BAABNQAECn8qAAIOAAoKvhpCdACVAgAOAAoKvhpCdACVAgAAAA==.Nickhy:BAABNQAECn8YAAMCAAoKiQyAcACXAQACAAoKiQyAcACXAQAfAAIKXASDTQBOAAAAAA==.Nietherme:BAABNQAECn8sAAITAAoK/A+rlwD0AQATAAoK/A+rlwD0AQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nightmun:BAAANQAECgEIAQABNQAECgoKSwAbAEYbAA==.Nihildicits:BAAANQAECgQICAAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgoKGwAFACcaAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQAECgUIDQABNQAECgoKNgAXAK8YAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAABNQAECn8XAAISAAgKlxG3bgDSAQASAAgKlxG3bgDSAQAAAA==.Nyalore:BAABNQAECn8WAAIKAAoKnhLbHAD+AQAKAAoKnhLbHAD+AQAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAQAAAA==.',
Og='Ogyaii:BAAANQAECggICgAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
On='Ondeom:BAAANQAECggICgABNQAFFAMIBQAIAEsbAA==.',
Op='Optamus:BAAANQAECgEIAQAAAA==.',
Or='Oraedia:BAABNQAECn9uAAIBAAoKjiMCAwDjAwABAAoKjiMCAwDjAwAAAA==.Oralen:BAACNQAFFH8NAAMBAAYKDBsrCQCIAQABAAYKDBsrCQCIAQATAAEKAAB/MwAAAAA1AAQKfzQAAwEACgo3I38KAHUDAAEACgo3I38KAHUDABMABAogEP00AWoAAAAA.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECn8bAAIDAAoKBg/PlgDjAQADAAoKBg/PlgDjAQAAAA==.Orstedd:BAAANQAECgMIAwAAAA==.',
Ov='Overloader:BAABNQAECn84AAIaAAoKiSItCgDaAgAaAAoKiSItCgDaAgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Oz='Ozs:BAAANQAECgcIDAAAAA==.',
Pa='Paidactor:BAABNQAECn8TAAIMAAoKUwNXuQCtAAAMAAoKUwNXuQCtAAAAAA==.Pairodeez:BAAANQADCgMIAQAAAA==.Palahang:BAAANQAECgEIAQAAAA==.Pallyaxe:BAABNQAECn8bAAMBAAgKYQ8jUQCcAQABAAgKYQ8jUQCcAQATAAUKhAKZUwGbAAABNQAECgoKQgAOAH4ZAA==.Pallygank:BAAANQADCgEIAQAAAA==.Pandawannabe:BAABNQAECn8hAAIFAAgKbx2PNwC9AQAFAAgKbx2PNwC9AQAAAA==.Pandussi:BAABNQAECn8aAAIhAAkKxhNiJAACAgAhAAkKxhNiJAACAgAAAA==.Paneer:BAABNQAECn8qAAICAAoK4SLbCwB+AwACAAoK4SLbCwB+AwABNQAECgoKIwAEAPgbAA==.Paninus:BAAANQAECgEIAQAAAA==.Papabair:BAAANQAECgcICQABNQAECggIEwAHAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgQIBAAAAA==.Perfectplex:BAAANQAECgYIBwAAAA==.Peruano:BAABNQAECn8sAAIPAAoKkRTxCABsAgAPAAoKkRTxCABsAgAAAA==.Petforheals:BAAANQAECgUICwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECggIIQAFAG8dAA==.',
Pi='Pietastegood:BAABNQAECn84AAIDAAoKNyUdCQCrAwADAAoKNyUdCQCrAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYIBgABNQAECggICgAHAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECggIEwAHAAAAAA==.Pitchblack:BAABNQAECn8YAAIQAAoKugzYIAAyAgAQAAoKugzYIAAyAgAAAA==.',
Po='Pocahöntas:BAABNQAECn8ZAAICAAkKhQZviQBcAQACAAkKhQZviQBcAQAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAACNQAFFH8FAAIeAAIKqBcXBgCgAAAeAAIKqBcXBgCgAAA1AAQKf0AAAh4ACgpwIAQFAD8DAB4ACgpwIAQFAD8DAAAA.Pontiack:BAAANQAECggICQAAAA==.Poordemon:BAAANQADCgUIBQABNQAECggIJQAXAIcJAA==.Popehealz:BAAANQADCgYIAgAAAA==.Pownds:BAAANQAECgYIDAAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAABNQAFFH8KAAISAAYKWBqiCgC6AQASAAYKWBqiCgC6AQAAAA==.Procspls:BAAANQADCgIIAgAAAA==.Proenz:BAAANQAECgIIAwAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAQABNQAECgcIGwAGANUOAA==.Pryor:BAAANQAECgcIEgAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGwAGANUOAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGwAGANUOAA==.Prøntø:BAABNQAECn8bAAMGAAcK1Q4ZJwBdAQAGAAcK1Q4ZJwBdAQAkAAIK3QP8OwBJAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgoKMgADACofAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQAECgQICQAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECggIDgAHAAAAAA==.Pyrista:BAABNQAECn8jAAICAAgKUhl4SgCOAgACAAgKUhl4SgCOAgAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgQIBQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECn82AAIaAAoKpBG2HgDbAQAaAAoKpBG2HgDbAQAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECgoKOAADADclAA==.Raendarth:BAAANQAECgUIDgAAAA==.Rageth:BAABNQAECn8jAAMKAAoKRBNhIADQAQAKAAkKEhFhIADQAQALAAMKKg1VFQC0AAAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAFFAIICwAUANgYAA==.Rakalaag:BAEANQAECgUIDQAAAA==.Rakath:BAABNQAECn8UAAIZAAYKSQ9oRADhAAAZAAYKSQ9oRADhAAAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECn8yAAIDAAoKKh/aLAAJAwADAAoKKh/aLAAJAwAAAA==.Redharvest:BAABNQAECn8UAAIjAAoKsg5BDgCZAQAjAAoKsg5BDgCZAQAAAA==.Redlands:BAAANQAECgEIAQAAAA==.Redredwine:BAAANQADCggICAAAAA==.Refractory:BAAANQAECgUIBgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Rennala:BAAANQADCggICAAAAA==.Renwick:BAAANQAECgEIAgABNQAFFAcIGAANAIYZAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAABNQAECn8nAAITAAoKoxDRnADpAQATAAoKoxDRnADpAQAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBgABNQAFFAIICwAUANgYAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECn83AAIFAAoKrx17IABBAgAFAAoKrx17IABBAgAAAA==.Rikoe:BAAANQAECgUICgAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgAHAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQAECgEIAQAAAA==.',
Ro='Rockabye:BAABNQAECn8oAAMQAAkK+hpoFQC1AgAQAAkK+hpoFQC1AgASAAEKZwiA3AA5AAAAAA==.Rokar:BAAANQAECgEIAQAAAA==.Roraalionnu:BAAANQADCgUIDgABNQAECgEIAgAHAAAAAA==.Rosannas:BAAANQAECgIIAgABNQAFFAIICwAUANgYAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFH8fAAMeAAYKzBVEAQBUAQAeAAYKzBVEAQBUAQAFAAMKshGyGQD0AAA1AAQKf0kAAx4ACgqOILkEANoCAB4ACgqOILkEANoCAAUACQqKFSRIAFYCAAAA.Ruibash:BAEBNQAECn9UAAITAAoK2iTSEACGAwATAAoK2iTSEACGAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Rumproast:BAAANQAECggIAwAAAA==.Runebladé:BAABNQAECn8YAAIXAAgKXhmUPQApAgAXAAgKXhmUPQApAgAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQAECggIDgAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQAECgQICwAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAHAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAHAAAAAA==.Sakuraa:BAABNQAECn8uAAMSAAoKvhJxQQD7AQASAAoKvhJxQQD7AQARAAMKLQEdJABKAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAQAAAA==.Sassassassin:BAAANQAECgQIBAAAAA==.Savaged:BAAANQAECggIDAABNQAECgoKSQAXAG8XAA==.Savajed:BAABNQAECn9JAAMXAAoKbxc7HgC+AQAiAAoKbBGzOQDsAQAXAAkKQBg7HgC+AQAAAA==.Savaragon:BAAANQAECgQIBQABNQAECgoKSQAXAG8XAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scaledoc:BAAANQAECgMIAwABNQAECggIEwAHAAAAAA==.Scallywagg:BAABNQAECn8WAAIEAAoK2hYaJAByAgAEAAoK2hYaJAByAgAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Schism:BAAANQAECgIIAwAAAA==.Scrodo:BAAANQAECgIIAwAAAA==.',
Se='Searcomic:BAAANQAECgcIDwAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECn8xAAMnAAoKdRYoBgBuAgAnAAoKdRYoBgBuAgALAAMKpQfZLwCbAAAAAA==.Selendas:BAAANQADCgcIDQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinanomi:BAAANQAECgMIBAAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECn83AAMGAAoKuyQ+AgCrAwAGAAoKuyQ+AgCrAwAkAAEKAABfRgAtAAAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgcIEwABNQAECgEIAgAHAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgUIDgAAAA==.Shameless:BAAANQAECgcICgAAAA==.Shamwów:BAAANQAECgcIEgAAAA==.Sharco:BAABNQAECn8nAAMYAAgKvBgMDgDMAQAYAAYKpR8MDgDMAQAOAAcKrBJX8wCkAQAAAA==.Sharkbites:BAAANQAECgUICgAAAA==.Shawarmafury:BAACNQAFFH8SAAICAAUK9SNVCADFAQACAAUK9SNVCADFAQA1AAQKfzsAAgIACgrnJv0BAH0DAAIACgrnJv0BAH0DAAAA.Shaydens:BAAANQAECgEIAQAAAA==.Shelandra:BAAANQAECggIBAAAAA==.Sherrizzahh:BAAANQADCgEIAQAAAA==.Shettani:BAAANQAECggICAAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shinshots:BAAANQAECgEIAwAAAA==.Shockrasta:BAAANQAECgQIEAABNQAECgoKRwAYAE8kAA==.Shooshmael:BAABNQAECn8cAAIFAAgKKxewWwAPAgAFAAgKKxewWwAPAgAAAA==.Shozo:BAAANQADCgUICAABNQAECgoKNwAGALskAA==.Shujáa:BAAANQAECggIEAAAAA==.Shush:BAAANQAECgEIAQAAAA==.Shyvîolet:BAABNQAECn8mAAMEAAoKghWJVwALAgAEAAoKghWJVwALAgAFAAEKMwG/YgETAAAAAA==.Shælynne:BAAANQADCgYIBgABNQAECgoKTAAaAPEYAA==.Shékinah:BAACNQAFFH8OAAIZAAQKkARTEgCvAAAZAAQKkARTEgCvAAA1AAQKfzQAAhkACgpJEVg9AAwCABkACgpJEVg9AAwCAAAA.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAcIGAANAIYZAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAHAAAAAA==.',
Sk='Skadgrip:BAAANQAECgEIAQABNQAECgkJFAAFAHgYAA==.Skorpekh:BAABNQAECn8ZAAICAAgKSQZUsQChAQACAAgKSQZUsQChAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECn8cAAIlAAgKWR9IEwCyAgAlAAgKWR9IEwCyAgAAAA==.Sloppyspikes:BAABNQAECn8bAAIoAAoKogd1GAAqAQAoAAoKogd1GAAqAQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECn9YAAMpAAoK6yMuAQAzAwApAAoK6yMuAQAzAwADAAkKxBoLWACDAgABNQAECgoKWAACAK8kAA==.Smidgenn:BAAANQADCgcIEQAAAA==.Smokyblast:BAABNQAECn8iAAIOAAkKewbflgBKAQAOAAkKewbflgBKAQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECn8+AAIOAAkKgwRqBwGBAQAOAAkKgwRqBwGBAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECn8hAAMhAAgKDw8cMgCGAQAhAAgKDw8cMgCGAQAJAAEK7g6AMQAzAAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIEQAAAA==.',
Sp='Sparowprince:BAACNQAFFH8SAAITAAYKnRiSCgCfAQATAAYKnRiSCgCfAQA1AAQKf1IAAhMACgpJJbMHAE0DABMACgpJJbMHAE0DAAAA.Spaspanda:BAAANQAECgQIBgABNQAECggIIQAFAG8dAA==.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAHAAAAAA==.Spectraleye:BAAANQAECgcIDwAAAA==.Sproocherlou:BAABNQAECn89AAITAAoK7yEdFgDzAgATAAoK7yEdFgDzAgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
Sr='Srgoblinghon:BAAANQADCgUIBQAAAA==.',
St='Stankbolt:BAABNQAECn8qAAIMAAkK/yRkEABPAwAMAAkK/yRkEABPAwAAAA==.Steezya:BAAANQAECgUIEwAAAA==.Stegulos:BAAANQAECgIIBAAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stonedemon:BAABNQAECn8VAAMaAAoK3RIyKgB/AQAaAAoK3RIyKgB/AQAoAAEKKg6pKwArAAABNQAFFAYIEgATAJ0YAA==.Stormsy:BAAANQAECggIEwABNQAECggIHQASALUQAA==.Stormykitty:BAABNQAECn8dAAMSAAgKtRDucwDAAQASAAgKtRDucwDAAQAQAAEKEQW0WAAvAAAAAA==.Strauch:BAAANQADCgcIIgAAAA==.Striderdh:BAAANQABCggIEQAAAA==.Strongwoman:BAAANQAECgUIEAAAAA==.Sturtza:BAACNQAFFH8JAAICAAIKpBGKHACXAAACAAIKpBGKHACXAAA1AAQKf0YAAgIACgrDIYQGAKoDAAIACgrDIYQGAKoDAAAA.Sturtzam:BAAANQAECgUIBgABNQAFFAIICQACAKQRAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sumat:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.Sunbear:BAAANQADCggIDwAAAA==.Sungayan:BAAANQAECgMIAQAAAA==.Susak:BAAANQAECgYIDgABNQAECgkJGgAWAGIeAA==.Suun:BAABNQAECn89AAITAAoK8B7oPADfAgATAAoK8B7oPADfAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Sweetysnail:BAAANQAECgYIEQAAAA==.Swoley:BAABNQAECn8ZAAIBAAgKux/OMQCeAgABAAgKux/OMQCeAgAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQAECgEIAgAAAA==.',
Ta='Taake:BAAANQAECgEIAQAAAA==.Taanua:BAAANQAECgYIBwAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECn8qAAIYAAoKpgtfDgDFAQAYAAoKpgtfDgDFAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAABNQAECn8XAAIBAAUKPBGgrwAgAQABAAUKPBGgrwAgAQAAAA==.Talisaie:BAABNQAECn8mAAMMAAoKeCKXDQDlAgAMAAoK8CGXDQDlAgAPAAUKPR8rBQByAQABNQAFFAcIFwAaAKUcAA==.Tanisatharae:BAAANQADCgYIDgABNQAECggIDgAHAAAAAA==.Tarahly:BAAANQAECgYIBgABNQAECgkJKgABAFYhAA==.Tarahse:BAAANQADCgIIAgABNQAECgkJKgABAFYhAA==.Taron:BAABNQAECn8kAAIDAAgKiBfYXwCmAQADAAgKiBfYXwCmAQAAAA==.Tart:BAACNQAFFH8FAAMFAAMKyw5yJACaAAAFAAIKyw5yJACaAAAEAAEKLwD/NAAXAAA1AAQKfxkAAgUACQp1EL9bAA8CAAUACQp1EL9bAA8CAAAA.Taualain:BAAANQADCgQIBAABNQAECggIIQAFAG8dAA==.',
Te='Techmaestrov:BAAANQAECgUICgAAAA==.Tedjones:BAABNQAECn8WAAIOAAYKAwXnQQEfAQAOAAYKAwXnQQEfAQAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.Tenderrot:BAAANQADCgUIBQAAAA==.',
Tg='Tgbird:BAAANQAECggICAAAAA==.',
Th='Thandana:BAAANQAECgUICQAAAA==.Thehumanatee:BAABNQAECn8vAAIZAAoKiBeILQBxAgAZAAoKiBeILQBxAgAAAA==.Theroach:BAABNQAECn8UAAMgAAUKRBEQRADiAAAgAAQK9RQQRADiAAATAAEKMwZ3dQEuAAAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICgAHAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingstabz:BAAANQAECgIIAgAAAA==.Thingytoo:BAAANQAECggIDwAAAA==.Thiqq:BAAANQAECgUIAgAAAA==.Threlindrier:BAAANQAECgIIAwAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAABNQAECn8iAAIDAAkKPgnddwBkAQADAAkKPgnddwBkAQAAAA==.Thyphlo:BAABNQAECn8XAAIRAAgKzxa8BACkAQARAAgKzxa8BACkAQAAAA==.',
Ti='Tictacs:BAAANQABCgYIBgAAAA==.Tiltawhirl:BAAANQAECggIDQAAAA==.Tiltedup:BAABNQAECn8tAAIOAAoK6Be4OABBAgAOAAoK6Be4OABBAgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQAECgYIBgABNQAECggIHQASALUQAA==.Tirich:BAAANQADCggICAABNQAFFAcIGAANAIYZAA==.Titaintium:BAAANQAECgQIBAABNQAECgoKOAAaAIkiAA==.',
To='Toshi:BAABNQAECn8kAAIMAAoKYwnmdgA+AQAMAAoKYwnmdgA+AQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgoKNwAmAPsRAA==.Touchyouup:BAAANQAECgIIAQAAAA==.',
Tr='Trilguth:BAAANQADCgYIBgAAAA==.Truckkun:BAAANQAECggICgAAAA==.Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Ts='Tstick:BAAANQAECgIIAwABNQAECgIIBAAHAAAAAA==.',
Tu='Tulark:BAAANQABCgYIBgAAAA==.Tullydin:BAABNQAECn8nAAMgAAoKyAj1MgBLAQATAAgKRQhW3gBeAQAgAAkKewf1MgBLAQAAAA==.Tullyy:BAAANQAECgQICwAAAA==.Tums:BAABNQAECn8vAAMNAAoKoRzUFwAfAgANAAkKqhvUFwAfAgAUAAgKXBh0HgAgAQAAAA==.Tusaditty:BAAANQADCgYIBgAAAA==.',
Tw='Twirls:BAABNQAECn8YAAIJAAgK7RnGDQAdAgAJAAgK7RnGDQAdAgAAAA==.Twistoffate:BAABNQAECn8XAAIYAAYK9AH2NABnAAAYAAYK9AH2NABnAAAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
['Tä']='Tälos:BAAANQADCgUIBQABNQADCggIDQAHAAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAABNQAECn8YAAIYAAcKTgoyIADoAAAYAAcKTgoyIADoAAAAAA==.Unsubtley:BAAANQAECggIEQABNQAECgMIBgAHAAAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECn8rAAMTAAoK6R4aewA1AgATAAoK6R4aewA1AgAgAAUKwwwPTwCrAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAABNQAECn8ZAAIMAAoKEw9TawBcAQAMAAoKEw9TawBcAQAAAA==.',
Va='Valgorr:BAAANQAECgYICwAAAA==.Valvalon:BAABNQAECn8zAAIYAAoKbB1wBADlAgAYAAoKbB1wBADlAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.Vanessia:BAAANQADCgQIBAAAAA==.Varhaitof:BAAANQADCggICAAAAA==.Varían:BAAANQAECgEIAQAAAA==.',
Ve='Veelaria:BAABNQAECn8wAAIgAAoKMQ+tGgBmAQAgAAoKMQ+tGgBmAQAAAA==.Vegetablue:BAAANQAECgEIAQABNQAECgUIBwAHAAAAAA==.Velinddrel:BAAANQADCgUIBQAAAA==.Verahardyr:BAAANQADCgQIBAAAAA==.Veravulp:BAAANQAECgEIAQAAAA==.Verdunkeln:BAAANQAECgUIBgAAAA==.Verymelon:BAAANQABCgQIAgAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQAECgMIBQAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgoKSQAXAG8XAA==.Vicalaus:BAABNQAECn83AAIiAAkKOhz0KQBKAgAiAAkKOhz0KQBKAgABNQAECgoKSwAbAEYbAA==.View:BAABNQAECn8oAAIEAAoK4RUNNwANAgAEAAoK4RUNNwANAgAAAA==.Vikcy:BAAANQAECggIEAAAAA==.Vikcyholy:BAAANQAECgEIAQAAAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitamind:BAAANQAECgUIBQAAAA==.Vitros:BAAANQADCgcIBwABNQAECgoKMwAQAI0fAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgkJFQAGAHMgAA==.Voidwitch:BAABNQAECn8oAAIPAAkKqiJVAQCTAgAPAAkKqiJVAQCTAgAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.Vortirtbreni:BAAANQAECgIIAgAAAA==.',
Vr='Vrakken:BAABNQAECn8xAAIiAAoK6RPNIgACAgAiAAoK6RPNIgACAgAAAA==.',
Vu='Vududonkey:BAAANQAECgMIAwABNQAECgkJGwAkAAcPAA==.Vulmaster:BAAANQAECgMIAwAAAA==.',
Vy='Vyndenus:BAACNQAFFH8HAAISAAQKqAxVGwDUAAASAAQKqAxVGwDUAAA1AAQKf00AAhIACgqIIBIQADEDABIACgqIIBIQADEDAAAA.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECggIDQAAAA==.Welor:BAAANQAECgYICgAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Whalebarf:BAAANQAECgIIAgABNQAECgkJKgAMAP8kAA==.Wheremytotem:BAAANQADCggIDQABNQAECgoKLAASAMsdAA==.Whitbone:BAAANQADCgUICQAAAA==.Wholephister:BAAANQAECgEIAQABNQAECggIFwAeAFASAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQAECggIEgAAAA==.Wigpetval:BAABNQAECn8nAAMCAAgKnRGImQDUAQACAAgKURGImQDUAQAfAAQKNgtCaQCIAAAAAA==.Wiidge:BAABNQAECn8mAAImAAkKwQoTDACjAQAmAAkKwQoTDACjAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECn8XAAIZAAYK+xhMSADJAQAZAAYK+xhMSADJAQAAAA==.Wolfchan:BAABNQAECn8gAAIOAAgKHwy7jQBdAQAOAAgKHwy7jQBdAQAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgoKSwAbAEYbAA==.Worldcrafter:BAABNQAECn8jAAMRAAkKBh+PCADbAQASAAgKAyC8LgBUAgARAAYKkRuPCADbAQAAAA==.Worldender:BAABNQAECn8iAAMSAAoKEhtLEAAuAwASAAoKwhpLEAAuAwARAAUKZRhiDQBeAQAAAA==.Wowretail:BAABNQAECn8kAAQgAAcKphs6IQDaAQAgAAYKnB46IQDaAQATAAYKZRtNrQDFAQABAAQKSSCQwQD4AAAAAA==.',
Wr='Wrathofdawn:BAAANQAECggIEgAAAA==.Wreckross:BAAANQABCgUIBQAAAA==.',
Wy='Wyldar:BAABNQAECn8fAAITAAkKVRQ5kwD9AQATAAkKVRQ5kwD9AQAAAA==.',
Xa='Xalaria:BAABNQAECn8ZAAIOAAoKtAQ0lgBLAQAOAAoKtAQ0lgBLAQAAAA==.Xantry:BAACNQAFFH8FAAITAAMK3gveGwDJAAATAAMK3gveGwDJAAA1AAQKfxwAAhMACQr+IoE4AO4CABMACQr+IoE4AO4CAAAA.',
Xe='Xeviscerated:BAAANQAECgMIBgAAAA==.',
Xm='Xmen:BAABNQAECn8jAAIOAAgKpwfAtAARAQAOAAgKpwfAtAARAQAAAA==.',
Xs='Xslight:BAAANQAECgcICAABNQADCggIDgAHAAAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgUIBgAAAA==.',
Ye='Yeastybush:BAACNQAFFH8GAAIEAAMKCBhUEgD2AAAEAAMKCBhUEgD2AAA1AAQKfzIAAgQACgpqIQ4bALECAAQACgpqIQ4bALECAAAA.',
Yi='Yinsen:BAAANQADCggICAAAAA==.',
Ys='Yseera:BAAANQAECgUIDgAAAA==.Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zalatoes:BAAANQAECgEIAQAAAA==.Zarathea:BAAANQAECgMIAwABNQAECgUIBQAHAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAABNQAECn8tAAIhAAoKlR0YDwDyAgAhAAoKlR0YDwDyAgAAAA==.',
Zo='Zoeyredbird:BAABNQAECn8UAAQWAAkKOxjnPQAfAQAiAAcK1RbmRgCjAQAWAAQKURnnPQAfAQAXAAIKDBe+tACGAAAAAA==.Zongo:BAAANQADCgcIBwAAAA==.Zonnit:BAAANQAECgEIAQAAAA==.',
Zw='Zwhitty:BAAANQADCgcICQAAAA==.Zwhittytv:BAABNQAECn8YAAILAAoKHxQpCQC2AQALAAoKHxQpCQC2AQAAAA==.',
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
