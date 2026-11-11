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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Druid-Feral','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Rogue-Subtlety','Mage-Arcane','Warlock-Destruction','Priest-Shadow','Priest-Discipline','Priest-Holy','Paladin-Retribution','Rogue-Assassination','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Druid-Balance','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Warrior-Protection','Druid-Restoration','Warlock-Affliction','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aamara:BAABNQAECn8lAAIBAAcKyx3xQQBdAgABAAcKyx3xQQBdAgABNQAECgoKIgACAFYdAA==.',
Ab='Aboyton:BAAANQAECgEIAgAAAA==.',
Ad='Adarksoul:BAAANQAECgEIBAAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwADAPkTAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAACNQAFFH8TAAMEAAYKJCMOCwASAQAEAAQKjiIOCwASAQAFAAQKFhKcEwAJAQA1AAQKf0AAAwQACgpSJT4DAGkDAAQACgpSJT4DAGkDAAUACgp8FFtNAC4CAAAA.Aelistiah:BAAANQAECgMIBQAAAA==.Aerithorn:BAABNQAECn8eAAMGAAgKciCzCQDYAgAGAAgKciCzCQDYAgAHAAEKWQsFRAA1AAAAAA==.Aestus:BAAANQABCgIIAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECgoKOAACACkYAA==.Ahleya:BAAANQAECgYIDAAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAIAAAAAA==.',
Ak='Akazza:BAAANQADCgIIAgAAAA==.Akoris:BAAANQAECgQICAABNQAECgoKLAAJACwVAA==.Akorys:BAABNQAECn8sAAMJAAoKLBVTEADzAQAJAAoKLBVTEADzAQAKAAEKAAB9NQAiAAAAAA==.',
Al='Albyno:BAACNQAFFH8QAAMLAAcKuQv1CwBeAQALAAcKuQv1CwBeAQAMAAEK8wYCEAA/AAA1AAQKfzcAAgsACgrVH8EEAC4DAAsACgrVH8EEAC4DAAAA.Algebrah:BAAANQAECgQICQAAAA==.Alivallia:BAAANQADCgUIBQABNQAECggIKQAEAMQeAA==.Alucius:BAAANQADCgQIBAAAAA==.',
Am='Amara:BAAANQADCgYILAAAAA==.Ambitionz:BAAANQAECgEIAgAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECn9KAAINAAkKZwYbjAAwAQANAAkKZwYbjAAwAQAAAA==.Ancksunamun:BAAANQADCggIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgoKIgACAFYdAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFH8YAAIOAAcKhhnwBQC9AQAOAAcKhhnwBQC9AQA1AAQKfycAAg4ACgr7Ht0FACgDAA4ACgr7Ht0FACgDAAAA.',
Ap='Aperture:BAAANQADCgcIEwAAAA==.',
Aq='Aquua:BAABNQAECn86AAIEAAoKdx4cIwBOAgAEAAoKdx4cIwBOAgAAAA==.',
Ar='Araelen:BAABNQAECn8UAAIPAAgKTwUDHAFdAQAPAAgKTwUDHAFdAQAAAA==.Arcticdps:BAABNQAECn8tAAMNAAoKpha+RACEAgANAAoKpha+RACEAgAQAAEKVxYCbgBDAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECn8zAAQRAAoKjR9gKwDMAQARAAYKeRpgKwDMAQASAAcKUQ6GDABwAQATAAgKGBR3dABlAQAAAA==.Ariestar:BAABNQAECn8UAAIUAAgKCghm3QBgAQAUAAgKCghm3QBgAQAAAA==.Ariiel:BAAANQADCggICQABNQAECgoKMwARAI0fAA==.Arrax:BAAANQADCgQIBAAAAA==.Arthimas:BAAANQAECgIIAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAABNQAECn8kAAIRAAkKcwpzIQBjAQARAAkKcwpzIQBjAQAAAA==.Asidize:BAAANQAECgUIDgAAAA==.Aslor:BAABNQAECn8yAAINAAoKMBhGRAD2AQANAAoKMBhGRAD2AQAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYIDwAAAA==.',
At='Athalia:BAACNQAFFH8NAAMVAAMKShTeBQDbAAAVAAMKKxTeBQDbAAAOAAIKJxZAGQCgAAA1AAQKf0AAAxUACgpIIzoFAIADABUACQqjIzoFAIADAA4ACAofGj4rAEACAAAA.Atlaswolfe:BAAANQAECgcICQAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECggIEQAAAA==.',
Av='Avaldra:BAAANQAECgEIAQAAAA==.Avery:BAAANQAECgEIAQAAAA==.Avex:BAABNQAECn84AAICAAoKKRibXgBaAgACAAoKKRibXgBaAgAAAA==.',
Ax='Axemage:BAABNQAECn9IAAMPAAoKzBmTQgA3AgAPAAoKzBmTQgA3AgAWAAQKKg+OBgCxAAAAAA==.Axeom:BAABNQAECn8+AAIFAAoKSx1yJwDGAgAFAAoKSx1yJwDGAgAAAA==.Axeshammy:BAAANQAECggIDgABNQAECgoKSAAPAMwZAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAACNQAFFH8GAAIPAAMKsAgzKADJAAAPAAMKsAgzKADJAAA1AAQKfxcAAg8ACQqhGiSjADsCAA8ACQqhGiSjADsCAAAA.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAABNQAECn8XAAIUAAgKQBkCsQC9AQAUAAgKQBkCsQC9AQAAAA==.Baldie:BAAANQAECgYIBgAAAA==.Bamboolan:BAAANQAECggIBwAAAA==.Barcliah:BAAANQADCgIIAgAAAA==.Barometer:BAABNQAECn8UAAMFAAcKURZhfAAnAQAFAAYKIRZhfAAnAQAEAAIKlAInHwFSAAAAAA==.Bast:BAAANQAECggIAQABNQAECgoKGAAUAC4MAA==.Baxa:BAAANQAECggICAAAAA==.Baylee:BAABNQAECn8lAAIPAAgKiQScMwE2AQAPAAgKiQScMwE2AQAAAA==.',
Bb='Bbartemis:BAABNQAECn8tAAIOAAkKIgZOfAARAQAOAAkKIgZOfAARAQAAAA==.',
Bc='Bchamp:BAAANQAECgMIAwAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgQIBwABNQAECgYICAAIAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIBAABNQAECgoKNQAOAFMdAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgUIBQAAAA==.Belzenlok:BAAANQAECgIIAgAAAA==.Benjohnbo:BAAANQAECgEIAQAAAA==.Benwins:BAABNQAECn8aAAIWAAkKXAjPAwBKAQAWAAkKXAjPAwBKAQAAAA==.Bergamö:BAABNQAECn8VAAIOAAkKjwozUwCaAQAOAAkKjwozUwCaAQAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcICgAAAA==.Bigangus:BAAANQAECgMICQAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Bigmerch:BAAANQADCgcIDgAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAABNQAECn8YAAIPAAcKxwKw+QCuAAAPAAcKxwKw+QCuAAAAAA==.Bisholoyd:BAABNQAECn8jAAIQAAcK3gqjHwByAQAQAAcK3gqjHwByAQAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgQIAwAAAA==.Blastoise:BAABNQAECn9CAAMXAAoK7iOhBACnAwAXAAoKmyOhBACnAwAYAAoKkyDDCQDPAgAAAA==.Blckbrry:BAAANQAECgEIAQAAAA==.Blinktwice:BAAANQAECgEIBgAAAA==.Blizfishleg:BAABNQAECn8cAAIZAAYKFg+1FABfAQAZAAYKFg+1FABfAQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMICQAAAA==.Bloodshell:BAAANQAECgcIBwABNQAECgkJIAAaAH0bAA==.Bloodybren:BAAANQAECgMIBQAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQAECgEIBAAAAA==.Bongwater:BAAANQADCgEIAQABNQAECgoKPAAbAIkiAA==.Bonkyo:BAAANQADCgYIBgAAAA==.Boombóx:BAAANQAECgQIDQABNQAFFAIIBQANAHQhAA==.Boome:BAAANQAECgIIAgABNQAFFAMIDQAVAEoUAA==.Boostia:BAAANQAECgMIBwAAAA==.Borthos:BAABNQAECn88AAIcAAoK9iA+DACCAgAcAAoK9iA+DACCAgAAAA==.Bowsback:BAAANQADCggILwAAAA==.Bowyohead:BAABNQAECn8yAAITAAoK3h3mFwAGAwATAAoK3h3mFwAGAwAAAA==.',
Br='Bracydaboss:BAAANQAECgEIAwAAAA==.Bradroybboi:BAAANQAECgUIDgAAAA==.Braingap:BAAANQAECgcIEAABNQAECggIDAAIAAAAAA==.Brandoe:BAAANQAECgQICAAAAA==.Breece:BAAANQAECgQIBgAAAA==.Brickinkeys:BAAANQAECggIEwABNQAECgoKIgACAFYdAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECn85AAIdAAoKQwnyAwB3AQAdAAoKQwnyAwB3AQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caenarigos:BAAANQAECgIIAgAAAA==.Caenarius:BAAANQADCgMIAwABNQAECgIIAgAIAAAAAA==.Caimie:BAAANQAECgQIBgAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQIDAAAAA==.Capnmorgan:BAAANQAECgEIAQAAAA==.Cassiaan:BAAANQAECgMIAwAAAA==.Caylavibes:BAABNQAECn8iAAITAAoKEBD0VAAkAgATAAoKEBD0VAAkAgAAAA==.',
Ch='Chaviel:BAAANQAECggICwAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAABNQAECn8oAAITAAkK+RbCOABFAgATAAkK+RbCOABFAgAAAA==.Chironn:BAABNQAECn9HAAIeAAoKuRzKAgCJAgAeAAoKuRzKAgCJAgAAAA==.Chonkerz:BAAANQAECgEIAQAAAA==.Chudlord:BAAANQAECgEIAgAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIBAAAAA==.',
Ci='Cilyian:BAAANQAECggICwABNQAECgoKHgALAGEPAA==.Cinderburn:BAAANQAECgQIDwABNQAECgUIBQAIAAAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.Cindoral:BAAANQAECgEIAQAAAA==.',
Cj='Cj:BAAANQAECgUIBAAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgQIBwAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAgAAAA==.Comfychair:BAABNQAECn8oAAIUAAkKWyFtQQDQAgAUAAkKWyFtQQDQAgAAAA==.Conclaved:BAAANQAECggIAgAAAA==.Confessions:BAAANQABCgMIAQAAAA==.Coowmoo:BAABNQAECn8XAAIfAAgKUBJrHQCLAQAfAAgKUBJrHQCLAQAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAUICQAgAI0WAA==.Cosmonodder:BAAANQAECggIEQABNQAFFAUICQAgAI0WAA==.Cosmoshotter:BAACNQAFFH8JAAMgAAUKjRbeFADyAAAgAAQKjRbeFADyAAACAAIKAAD6NwBLAAA1AAQKfyYAAyAACgobIO4TAPIBACAACgocHe4TAPIBAAIAAgrpI2gXAWwAAAAA.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Crazyotto:BAAANQABCggIBwAAAA==.Cremebrule:BAAANQAECgEIBAAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cuchulainn:BAAANQADCgQIBAAAAA==.Cucubau:BAAANQADCggIGwAAAA==.',
Cy='Cyndra:BAABNQAECn8kAAIPAAoK9QusigB/AQAPAAoK9QusigB/AQAAAA==.',
Da='Dacura:BAAANQAECgQIBAAAAA==.Dakai:BAAANQAECgEIAQAAAA==.Dallthyrian:BAAANQADCgYIBgABNQAECgUICwAIAAAAAA==.Dalthyrian:BAAANQAECgYIEAABNQAECgUICwAIAAAAAA==.Dalthyriian:BAAANQAECgUICwAAAA==.Dalthyrrian:BAAANQAECgEIAQABNQAECgUICwAIAAAAAA==.Dalthyyrian:BAABNQAECn8ZAAIhAAgKnxB3JAA1AQAhAAgKnxB3JAA1AQABNQAECgUICwAIAAAAAA==.Damii:BAAANQADCgYIEgAAAA==.Danarand:BAAANQADCgYIBwABNQAECgkJIwAGAF0RAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgkJFAAEAJsOAA==.Darjen:BAABNQAECn8WAAICAAcKlBq9dAC5AQACAAcKlBq9dAC5AQAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darkshock:BAAANQAECggICgAAAA==.Darksky:BAABNQAECn8fAAIcAAoKiB6xCQCvAgAcAAoKiB6xCQCvAgAAAA==.Darthra:BAAANQAECgEIAQAAAA==.Daysfox:BAACNQAFFH8JAAIgAAMKxwlxEADDAAAgAAMKxwlxEADDAAA1AAQKf0wAAyAACQoNErYSAAMCACAACQoNErYSAAMCAAIAAQq6DAFPAUMAAAAA.Daysmonk:BAABNQAECn8vAAIiAAkKWQyFHQCeAQAiAAkKWQyFHQCeAQAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCggIDQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deadxpool:BAAANQAECgEIAQAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgoKRwAVALAfAA==.Deathdro:BAAANQADCgEIAQAAAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECn9HAAMVAAoKsB8jBgCdAgAVAAkKsB8jBgCdAgAOAAUKKgtnOgDkAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathsdawn:BAAANQAECgcIEQABNQAECgoKTQAcAEYbAA==.Deathstone:BAACNQAFFH8GAAIjAAMKIhUHFACSAAAjAAMKIhUHFACSAAA1AAQKfzUAAyMACgr3H48PAMoCACMACgr3H48PAMoCABgABQqLD41dAIUAAAE1AAUUBwgTABQAhRcA.Deathtress:BAABNQAECn8bAAQjAAkKwhHHMgAVAgAjAAkKwhHHMgAVAgAYAAEKNAN69QAiAAAXAAEKAAAP3QAhAAAAAA==.Debbydowner:BAABNQAECn81AAIDAAoK2gsQhQBmAQADAAoK2gsQhQBmAQAAAA==.Decado:BAABNQAECn8YAAIUAAoKLgwCvQCjAQAUAAoKLgwCvQCjAQAAAA==.Dedine:BAAANQAECgQIBAAAAA==.Deemwins:BAAANQAECgUIBgAAAA==.Deezenuts:BAAANQAFFAIIAgAAAA==.Degen:BAABNQAECn8cAAIaAAcKaQy9RAD+AAAaAAcKaQy9RAD+AAAAAA==.Dejevoid:BAABNQAECn8XAAIcAAoK6wbPOQB3AQAcAAoK6wbPOQB3AQAAAA==.Deliad:BAAANQAECgEIAQAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECn8sAAMkAAoK6Rc0DgBMAgAkAAoK6Rc0DgBMAgADAAMKuAh9JgGLAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Dethmoora:BAAANQAECgIIAQAAAA==.Deww:BAABNQAECn8tAAMSAAoKUBv+BABpAgASAAgKQxj+BABpAgATAAoKURgiNQBVAgAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECn8oAAIhAAkKmgoGLwDuAAAhAAkKmgoGLwDuAAAAAA==.',
Di='Diablesse:BAAANQAECgYICwAAAA==.Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECn85AAIXAAoK7iJiCgDiAgAXAAoK7iJiCgDiAgAAAA==.',
Do='Docdolittle:BAABNQAECn9fAAMCAAoKrySMCQCQAwACAAoKrySMCQCQAwAgAAEKdBHKggA9AAAAAA==.Docfreez:BAACNQAFFH8FAAMPAAIKQx+LOgB1AAAPAAEK8CaLOgB1AAAZAAEKlhfWEQBLAAA1AAQKf00AAxkACgqCJMQHAHACAA8ACgqrIsgwAHICABkACAqMIsQHAHACAAAA.Docragosa:BAAANQAECgMIBAABNQAECggIEQAIAAAAAA==.Doctermoo:BAABNQAECn8jAAMFAAgKshc1NgAsAgAFAAgKshc1NgAsAgAEAAQKGgJt9QAzAAAAAA==.Dogar:BAAANQAECgEIAgAAAA==.Doomhamer:BAAANQADCggICAABNQAECgoKPAAcAPYgAA==.Dopewashere:BAAANQADCgUIBAAAAA==.Doraemee:BAABNQAECn8WAAIcAAYKFBdzMwDpAAAcAAYKFBdzMwDpAAAAAA==.',
Dr='Drbaconbrgr:BAABNQAECn8kAAITAAkKFh2aKQCRAgATAAkKFh2aKQCRAgABNQAECgoKRwACAHklAA==.Drbakedziti:BAAANQADCggIDgABNQAECgoKRwACAHklAA==.Drbaobuns:BAAANQAECgcIEwABNQAECgoKRwACAHklAA==.Drcarrotcake:BAAANQAECgYIEgABNQAECgoKRwACAHklAA==.Drcheeseball:BAAANQAECgYIEAABNQAECgoKRwACAHklAA==.Drchikenparm:BAAANQAECgcIBwABNQAECgoKRwACAHklAA==.Dreggsalad:BAAANQAECgUIEgABNQAECgoKRwACAHklAA==.Dreim:BAEANQAECgYIBwABNQAECgoKWwAUACglAA==.Dreima:BAAANQAECgQIBgAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEIAQABNQAECgoKRwACAHklAA==.Drgatorwine:BAABNQAECn8cAAIhAAgKDh8iEgDyAQAhAAgKDh8iEgDyAQABNQAECgoKRwACAHklAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgoKRwACAHklAA==.Drkimchirice:BAABNQAECn84AAIHAAoK6SSPAQBRAwAHAAoK6SSPAQBRAwABNQAECgoKRwACAHklAA==.Drmacncheese:BAABNQAECn80AAIQAAoKnx8gAQDMAgAQAAoKnx8gAQDMAgABNQAECgoKRwACAHklAA==.Drpumpkinpie:BAABNQAECn8uAAIUAAoKAB79IwDHAgAUAAoKAB79IwDHAgABNQAECgoKRwACAHklAA==.Drshephardpi:BAAANQAECggICAABNQAECgoKRwACAHklAA==.Drshortbread:BAAANQAECgUIDgABNQAECgoKRwACAHklAA==.Druiddres:BAAANQAECgUIBgAAAA==.Druidussy:BAAANQAECgEIAQAAAA==.Drwontonsoup:BAABNQAECn9HAAICAAoKeSWaBABnAwACAAoKeSWaBABnAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.Dumpstur:BAAANQAECgUICwAAAA==.',
['Dé']='Déath:BAAANQAECgEIAQAAAA==.',
['Dö']='Dööku:BAAANQAECgYIBgAAAA==.',
Ei='Eighteen:BAACNQAFFH8FAAIOAAIK4Aq5GwCKAAAOAAIK4Aq5GwCKAAA1AAQKfzkAAg4ACgr3H2IGABsDAA4ACgr3H2IGABsDAAAA.',
Ek='Eksi:BAABNQAECn8mAAIiAAkKjRR0IQB6AQAiAAkKjRR0IQB6AQAAAA==.',
El='Eladaradar:BAAANQADCggICwAAAA==.Elethe:BAAANQAECgMIBAABNQAFFAcIGAAOAIYZAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgQIBgAAAA==.Ellilina:BAAANQAECgIIAgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgQIBQAAAA==.',
Em='Embedded:BAABNQAECn8UAAMEAAkKmw4rdADFAQAEAAgKfBArdADFAQAfAAEKWAP1NQAuAAAAAA==.Eme:BAABNQAECn8eAAMLAAoKYQ8ZDgAcAgALAAoKYQ8ZDgAcAgAMAAMKEAZRIABPAAAAAA==.Empress:BAABNQAECn8qAAIjAAoKrAsBNwCvAQAjAAoKrAsBNwCvAQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAgAIAAAAAA==.Enriq:BAAANQAECgEIAQABNQAECgQICwAIAAAAAA==.Entrophi:BAAANQADCgMIAwABNQADCgQIBAAIAAAAAA==.',
Er='Erikaa:BAABNQAECn8bAAIUAAkKxwuSpgBrAQAUAAkKxwuSpgBrAQAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.Errour:BAAANQADCgQIBAAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIBAAIAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAgABNQAECggIDAAIAAAAAA==.',
Ex='Excruciator:BAABNQAECn83AAMaAAoKgBJfNABTAQAaAAoKgBJfNABTAQAlAAIKtAfIZgBqAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAABNQAECn8kAAIiAAkK8xQtGgDDAQAiAAkK8xQtGgDDAQAAAA==.Falloutzhunt:BAAANQADCgYIBgABNQAECgkJJAAiAPMUAA==.Fantarada:BAAANQADCgcIEgAAAA==.Farahcanle:BAABNQAECn9SAAIGAAoK3xQaFADjAQAGAAoK3xQaFADjAQAAAA==.Farrock:BAABNQAECn8uAAIGAAoKjwwrIwBTAQAGAAoKjwwrIwBTAQAAAA==.Fatherzimms:BAAANQAECgEIAQAAAA==.Fawxette:BAAANQAECgIIAgABNQAECgoKbQAcAFwcAA==.',
Fe='Felanish:BAAANQAECgEIAgAAAA==.Felystia:BAABNQAECn8wAAIPAAkKYQmSiwB9AQAPAAkKYQmSiwB9AQAAAA==.Fenra:BAAANQADCgcIEAAAAA==.Feorblarir:BAABNQAECn8VAAIHAAoK6REjEAClAQAHAAoK6REjEAClAQAAAA==.Ferkel:BAEANQADCgEIAQABNQAECgoKWwAUACglAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQAECgQIBAABNQAECgkJIwAkAC0LAA==.Filledegel:BAAANQAECgYIDQABNQAECgcIDwAIAAAAAA==.Finowscath:BAAANQAECgMIBAAAAA==.Firequencher:BAABNQAECn8gAAIaAAkKfRsxNABGAgAaAAkKfRsxNABGAgAAAA==.Fistacuffs:BAAANQAECgMIBgAAAA==.Fistdoc:BAAANQAECggIEQAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQAECgMIBQAAAA==.Fié:BAAANQAECggICAABNQAECgoKbQAcAFwcAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECn9QAAIbAAoK8RiQFwBJAgAbAAoK8RiQFwBJAgABNQAECgoKbQAcAFwcAA==.Foxknight:BAAANQADCgQIBAABNQAECgoKbQAcAFwcAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQAECgEIAQABNQAECgkJIwAGAF0RAA==.',
Fr='Frederick:BAAANQAECggICwAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECn8uAAIBAAoKLB04KQDDAgABAAoKLB04KQDDAgAAAA==.Friendofbear:BAACNQAFFH8NAAICAAQKIw3WFQDUAAACAAQKIw3WFQDUAAA1AAQKfzcAAgIACgpMGs44AMACAAIACgpMGs44AMACAAAA.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAABNQAECn8VAAIkAAgKgwXkJQC3AAAkAAgKgwXkJQC3AAAAAA==.Fuzywuzzy:BAABNQAECn8VAAMGAAkKcyBrBgAqAwAGAAkKcyBrBgAqAwAHAAQK6A0gKQDGAAAAAA==.Fuzzycoochy:BAAANQADCgQIBAAAAA==.Fuzzykuntz:BAABNQAECn8jAAIYAAoK3glGMQBQAQAYAAoK3glGMQBQAQAAAA==.Fuzzypus:BAAANQADCgYIBgAAAA==.',
Fw='Fwoom:BAAANQADCgUIBQAAAA==.',
Fy='Fynsdood:BAABNQAECn8jAAIGAAkKXRGgIgCCAQAGAAkKXRGgIgCCAQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgkJIwAGAF0RAA==.',
Ga='Gabelock:BAACNQAFFH8dAAQNAAcK0hU6CwC4AQANAAYKcxg6CwC4AQAQAAEKUgtbHgBLAAAmAAEKAADnEgA8AAA1AAQKf0UABA0ACgp/IyklAO8CAA0ACgp/IyklAO8CACYABgrZHT8NAE4BABAABAouGY4wAAYBAAAA.Gabemage:BAABNQAECn8ZAAIPAAkKkhGfswAcAgAPAAkKkhGfswAcAgAAAA==.Gala:BAAANQAECgYICAAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAABNQAECn8oAAIUAAoKlhKQmgDuAQAUAAoKlhKQmgDuAQAAAA==.',
Gi='Gigah:BAABNQAECn8XAAIOAAoKww54FwAjAgAOAAoKww54FwAjAgAAAA==.Gingerbell:BAAANQABCggICgAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgcIEwAAAA==.Glutebruiser:BAAANQAECgUIDQABNQAECgoKLgANACclAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDwAAAA==.',
Go='Gooseshift:BAAANQAECgEIAgAAAA==.Gouchh:BAAANQAECgEIAgAAAA==.',
Gr='Gravithel:BAAANQAECgEIAQAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECn8XAAIJAAgKVyJuCwDNAgAJAAgKVyJuCwDNAgAAAA==.Grimspark:BAAANQAECgEIAgAAAA==.Grimtree:BAABNQAECn8/AAMmAAoK+xH+BwAVAgAmAAkKxBL+BwAVAgANAAgK0wq0hwA5AQAAAA==.Grindor:BAAANQAECgEIAQAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgYIDAAAAA==.Grumpydemon:BAABNQAECn9EAAIcAAoKvBrBGgCCAgAcAAoKvBrBGgCCAgAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gu='Guglugauthu:BAAANQAECgIIAgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Hafchub:BAAANQAECgEIAwAAAA==.Haldril:BAEANQAECgUICAABNQAECgoKWwAUACglAA==.Halfskul:BAABNQAECn8YAAIYAAgK2guCZgB3AQAYAAgK2guCZgB3AQAAAA==.Halotic:BAAANQAECgUIBwAAAA==.Hashah:BAABNQAECn8aAAIRAAcKRyCtGwBqAgARAAcKRyCtGwBqAgAAAA==.Hatefel:BAAANQAECgUIBgABNQAECgkJKwAQAGwjAA==.Havoke:BAAANQADCggIHgAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgoKMQAnAHUWAA==.Healyaass:BAAANQAECgEIAgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgARAEcgAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgoKIgACAFYdAA==.Heyyboyy:BAACNQAFFH8FAAICAAQKSxhzDwD9AAACAAQKSxhzDwD9AAA1AAQKf1EAAwIACgqvJNwKAIYDAAIACgqvJNwKAIYDACAAAwonGQAvAOMAAAAA.',
Ho='Holyaefar:BAAANQAFFAIIAwABNQAFFAYIEwAEACQjAA==.Holymolydin:BAAANQADCggIBgAAAA==.Holysab:BAABNQAECn8jAAMBAAkKeR/PEQAfAwABAAkKeR/PEQAfAwAUAAIKOgntXQFaAAAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAABNQAECn8jAAMTAAoKwRmpSwBCAgATAAoKwRmpSwBCAgARAAIKqga9XgA0AAAAAA==.Holyyumae:BAAANQAECggIAgAAAA==.Holz:BAAANQAECgMICAAAAA==.Horsetowater:BAAANQAECgUICQABNQAECgoKMgATAN4dAA==.Hotsfordays:BAAANQAECggIDwAAAA==.',
Hu='Hugoman:BAAANQAECggIEwABNQAECgoKOwAYAK8YAA==.Huni:BAABNQAECn8cAAIFAAkKsx5ZKADCAgAFAAkKsx5ZKADCAgAAAA==.Hunterj:BAAANQAECgMIAwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAABNQAECn8oAAIUAAoKIBWPXgAFAgAUAAoKIBWPXgAFAgAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgQIBAABNQAECggICwAIAAAAAA==.',
Ib='Ibun:BAAANQAECgcIEgAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECn8oAAIBAAkKYBgCLgCuAgABAAkKYBgCLgCuAgABNQAECgoKMgATAN4dAA==.',
Id='Idgafadin:BAAANQAECgYICQAAAA==.',
Ig='Igneus:BAACNQAFFH8ZAAIPAAcKWSA1CgCvAQAPAAcKWSA1CgCvAQA1AAQKf0kAAg8ACgpcJToDAGoDAA8ACgpcJToDAGoDAAAA.Igriz:BAAANQADCggIMAAAAA==.',
Ii='Iillil:BAACNQAFFH8IAAIcAAQKdATNDgCxAAAcAAQKdATNDgCxAAA1AAQKfywAAhwACgqMDCwsAOABABwACgqMDCwsAOABAAAA.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgUIDQAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQAECgEIAQAAAA==.Insidedoubt:BAAANQAECgcIDgAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUIBQAAAA==.',
It='Itsjeff:BAABNQAECn8bAAMgAAoK0xLoGwCJAQAgAAkKcRDoGwCJAQACAAQKcRmD6wAqAQAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQAECggIEwAAAA==.Jambonjay:BAABNQAECn8gAAIDAAcKuwl+zgBXAQADAAcKuwl+zgBXAQABNQAECggIJwACAJ0RAA==.Jananda:BAABNQAECn8mAAMlAAYKlgEzYQBfAAAlAAYKlgEzYQBfAAAaAAYK5QAHqABIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jastora:BAAANQADCgEIAQABNQADCggIDQAIAAAAAA==.Jaywaz:BAAANQAECgUIBgAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgABNQAECgoKLQAlABEfAA==.Jckjckjck:BAAANQADCgUIBQABNQAECgoKLQAlABEfAA==.Jckjckjckjck:BAABNQAECn8tAAQlAAoKER9cCQAqAwAlAAkKOSBcCQAqAwAaAAoKux9cIwC1AgAGAAUKoBu8MQD0AAAAAA==.',
Je='Jearn:BAAANQAECgMIBgAAAA==.Jermagedupri:BAACNQAFFH8PAAIPAAUKTRUkIACFAQAPAAUKTRUkIACFAQA1AAQKfzEAAg8ACQqzIcI4ABYDAA8ACQqzIcI4ABYDAAAA.Jessupy:BAABNQAECn82AAIbAAkK4xsCIgDlAQAbAAkK4xsCIgDlAQAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQAECgEIAQAAAA==.Jezliu:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgYIDQABNQAECggICwAIAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAABNQAECn8WAAIPAAgKSQlvMAE7AQAPAAgKSQlvMAE7AQAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAABNQAECn8ZAAINAAgKzg06mQCoAQANAAgKzg06mQCoAQAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalkulus:BAAANQADCgYICQAAAA==.Kalrendion:BAAANQAECgIIAgABNQAECgoKIAAYAEERAA==.Kalru:BAAANQAECgQICgAAAA==.Kalzok:BAEANQAECgQIBgABNQAECgoKWwAUACglAA==.Karaillyonna:BAAANQAECgcIDwAAAA==.Karasu:BAAANQAECgQIDAAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAABNQAECn8XAAMGAAcKxQvXMAD6AAAGAAcKxQvXMAD6AAAHAAQKmQILOABeAAAAAA==.Kayho:BAAANQAECgUJCwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAACNQAFFH8JAAIJAAQKfBm2BABLAQAJAAQKfBm2BABLAQA1AAQKfzIAAwkACgpfJIwEAF0DAAkACgpfJIwEAF0DACIABQq4BKBSAKcAAAAA.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAABNQAECn8lAAIYAAoK1gzQKQCCAQAYAAoK1gzQKQCCAQAAAA==.Killamanjoro:BAABNQAECn8cAAIDAAgKxBlnfAAkAgADAAgKxBlnfAAkAgAAAA==.Kimchiwar:BAAANQAECgcIEQAAAA==.Kirasha:BAAANQAECgYIDQAAAA==.Kitak:BAABNQAECn8gAAMYAAoKQRFhLwBdAQAXAAYK2xRcZQBdAQAYAAkKRBBhLwBdAQAAAA==.Kitchenbound:BAABNQAECn8gAAIGAAkKBBmgFgAAAgAGAAkKBBmgFgAAAgAAAA==.Kittychan:BAABNQAECn87AAIYAAoKrxgqFgAsAgAYAAoKrxgqFgAsAgAAAA==.',
Kl='Klaacus:BAABNQAECn9NAAQcAAoKRhupCwAkAwAcAAoKRhupCwAkAwAoAAMK+wjeKABEAAAbAAEKnhH6jgA9AAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUICwAAAA==.',
Ko='Kodomo:BAAANQAECgEIAQAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Kratosmall:BAAANQADCgcIBwABNQAECgYIEgAIAAAAAA==.Krazm:BAABNQAECn8rAAICAAoKASBOKAD3AgACAAoKASBOKAD3AgAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECn8fAAMRAAkKpQ7eJQAAAgARAAkKpQ7eJQAAAgASAAEKXxJFKAA1AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECn8mAAIfAAoKoyIbBQA8AwAfAAoKoyIbBQA8AwABNQAECgoKWwAUACglAA==.',
La='Lakshmi:BAABNQAECn8iAAICAAoKVh29PwCrAgACAAoKVh29PwCrAgAAAA==.Laradin:BAAANQADCgEIAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgQICgAAAA==.Lavagrip:BAABNQAECn8jAAMUAAUKdBMjEwH/AAAUAAUKdBMjEwH/AAAhAAEKAACwcAAvAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFH8RAAMCAAUKECRmBQD+AQACAAUKECRmBQD+AQAgAAIK1BntHABKAAA1AAQKf1MAAwIACgq3Jo0EAMIDAAIACgq3Jo0EAMIDACAABwrZI68TAMMCAAAA.Letmehealu:BAABNQAECn8aAAITAAkK8AxkeQCuAQATAAkK8AxkeQCuAQAAAA==.Lewsky:BAAANQAECgMIBgABNQAFFAMIBQAUAN4LAA==.',
Li='Licelle:BAAANQABCgYICgAAAA==.Lichtghost:BAAANQADCggIDAAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIFwAAAA==.Lilhojx:BAAANQAECgMIAwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECn9FAAIVAAoKTxpFCABaAgAVAAoKTxpFCABaAgAAAA==.Liondori:BAAANQAECgEIAQAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECggIEQAAAA==.',
Lm='Lmj:BAAANQAECgMIDAAAAA==.',
Lo='Lockbox:BAACNQAFFH8FAAINAAIKdCG2GQDKAAANAAIKdCG2GQDKAAA1AAQKf00AAw0ACgq2JEQHAJMDAA0ACgq2JEQHAJMDABAAAwoVIacvAAsBAAAA.Lokmar:BAAANQAECgYICgAAAA==.Loomin:BAABNQAECn9NAAMPAAoKRyIlGwDOAgAPAAoKvyElGwDOAgAZAAUK0hA6HQAEAQAAAA==.Lostpeace:BAAANQADCgcIBwAAAA==.',
Lu='Lucatia:BAABNQAECn8vAAIcAAoKgR67DgAAAwAcAAoKgR67DgAAAwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQAECgIIAgABNQAECgcIDwAIAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICQAAAA==.',
['Lä']='Lädyæk:BAABNQAECn8pAAICAAoKnA5lcADEAQACAAoKnA5lcADEAQAAAA==.',
['Lë']='Lëäë:BAAANQAECgUIBQAAAA==.',
Ma='Madboy:BAAANQAECggIDwAAAA==.Maekyss:BAABNQAECn8jAAMFAAoKMg38fgCPAQAFAAoKMg38fgCPAQAEAAgKuBL7ZwA3AQAAAA==.Magezu:BAAANQAECgYIEQAAAA==.Maggarak:BAABNQAECn8bAAICAAgKkhkJgQCdAQACAAgKkhkJgQCdAQAAAA==.Magimagi:BAAANQAECggIDwAAAA==.Magixstraza:BAABNQAECn9DAAIPAAoKgBrRPwBAAgAPAAoKgBrRPwBAAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBgAAAA==.Mallidin:BAAANQAECgIIAgABNQAECggIBwAIAAAAAA==.Malthoryn:BAAANQAECgMIAwAAAA==.Malzel:BAABNQAECn8UAAMEAAkKeBjSlwBpAQAEAAUK6RnSlwBpAQAfAAUKXBbRIAADAQAAAA==.Mamasan:BAAANQAECgcIDAAAAA==.Mamor:BAABNQAECn8gAAICAAYKOgTE7gC5AAACAAYKOgTE7gC5AAAAAA==.Manaman:BAAANQAECgQIBAAAAA==.Maphra:BAAANQAECgcIDgAAAA==.Marli:BAAANQABCgQIBQAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQICgAAAA==.Mattmurlock:BAAANQAECgEIAQAAAA==.Mazethak:BAAANQAECgEIAQAAAA==.',
Md='Mdeow:BAAANQADCggIGgAAAA==.',
Me='Mechabull:BAAANQAECgEIBAAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAABNQAECn8cAAMpAAoKCg9hFAAaAQApAAYKdRBhFAAaAQADAAkKewx2sAAEAQAAAA==.Melianthal:BAAANQAECgIIBAAAAA==.Melodí:BAAANQADCggICAABNQAECgoKNAAKAB0dAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgQICQAAAA==.',
Mi='Miakoda:BAAANQAECgEIAQABNQAECgUIBgAIAAAAAA==.Micromortis:BAAANQAECgQIBAABNQAECggIEQAIAAAAAA==.Mikuu:BAAANQAECgcIEgAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECggIEAAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAABNQAECn8WAAMJAAgKeRkYEwBLAgAJAAgKeRkYEwBLAgAiAAEKAAATeQAdAAABNQAECgoKLQAlABEfAA==.Mitufu:BAAANQAECggICAAAAA==.',
Mm='Mmeow:BAAANQADCggIEAAAAA==.',
Mo='Moelestyr:BAAANQAECgEIAgAAAA==.Mogonn:BAAANQABCgEIAQAAAA==.Molded:BAAANQAECgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECn9tAAMcAAoKXBxGEADwAgAcAAoKXBxGEADwAgAbAAEKAg4ukgA2AAAAAA==.Morgul:BAABNQAECn8XAAILAAoKpBGfGgAbAgALAAoKpBGfGgAbAgAAAA==.Moriru:BAAANQAECgYIBwAAAA==.Moroton:BAAANQADCgQIBAABNQAECgoKFQAHAOkRAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgQIBQAAAA==.Movechill:BAABNQAECn8ZAAMVAAIKViTCSgBmAAAVAAEKViTCSgBmAAAOAAIKLx0xvgBXAAAAAA==.',
Ms='Mseow:BAAANQAECgUICQAAAA==.',
Mu='Mudbutbrooks:BAABNQAECn8lAAMgAAcK9BHpPQBjAQAgAAcK9BHpPQBjAQAeAAEKyQO1FAAoAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgoKMgATAN4dAA==.Muller:BAABNQAECn8uAAIUAAkK2hKRlgD2AQAUAAkK2hKRlgD2AQAAAA==.',
Mv='Mveow:BAAANQADCgYICwAAAA==.',
Mw='Mweow:BAAANQAECgQIBAAAAA==.',
Mx='Mxeow:BAAANQADCgQICgAAAA==.',
My='Mynnu:BAABNQAECn8aAAITAAcKAReFcgBsAQATAAcKAReFcgBsAQAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Mz='Mzeow:BAAANQADCgYICwAAAA==.',
Na='Nahda:BAAANQADCggIEAAAAA==.Nautprepared:BAABNQAECn8YAAIbAAkKcQVlSwDjAAAbAAkKcQVlSwDjAAAAAA==.',
Ne='Necrodancer:BAAANQAECggIAwAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neegrandy:BAAANQADCgUIBgAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Nefetiree:BAAANQADCgQIBAAAAA==.Neildasstysn:BAAANQAECgYIDAABNQAFFAIIAgAIAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCggIMAAAAA==.',
Ni='Nickeld:BAABNQAECn8sAAIPAAoKvhpCdACVAgAPAAoKvhpCdACVAgAAAA==.Nickhy:BAABNQAECn8aAAMCAAoKLQ2ceACwAQACAAoKLQ2ceACwAQAgAAIKXAQLVABOAAAAAA==.Nietherme:BAABNQAECn8uAAIUAAoKwRNijQCcAQAUAAoKwRNijQCcAQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nightmun:BAAANQAECgEIAQABNQAECgoKTQAcAEYbAA==.Nihildicits:BAAANQAECgQIBgAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgoKGwAEACcaAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nobodyelf:BAAANQADCgYIBgAAAA==.Nofoamlatte:BAAANQAECgUICwABNQAECgoKOwAYAK8YAA==.Nolife:BAAANQAECgEIAgAAAA==.Noms:BAAANQADCggICAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAABNQAECn8XAAITAAgKlxG3bgDSAQATAAgKlxG3bgDSAQAAAA==.Nyalore:BAABNQAECn8WAAILAAoKnhLbHAD+AQALAAoKnhLbHAD+AQAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAwAAAA==.',
Og='Ogyaii:BAAANQAECggICQAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIBAAAAA==.',
On='Ondeom:BAAANQAECggICAABNQAFFAQICQAJAHwZAA==.',
Op='Optamus:BAAANQAECgEIAgAAAA==.',
Or='Oraedia:BAABNQAECn99AAIBAAoKQyQLAgASBAABAAoKQyQLAgASBAAAAA==.Oralen:BAACNQAFFH8NAAMBAAYKDBssCwCCAQABAAYKDBssCwCCAQAUAAEKAAAuOQAAAAA1AAQKfzUAAwEACgo3I38KAHUDAAEACgo3I38KAHUDABQABAogENtQAWkAAAAA.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECn8bAAIDAAoKBg/PlgDjAQADAAoKBg/PlgDjAQAAAA==.',
Ov='Overloader:BAABNQAECn88AAIbAAoKiSISDADTAgAbAAoKiSISDADTAgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Oz='Ozs:BAAANQAECgcIDQAAAA==.',
Pa='Paidactor:BAABNQAECn8aAAINAAoKVxH9RwDrAQANAAoKVxH9RwDrAQAAAA==.Pairodeez:BAAANQADCgMIAQAAAA==.Palahang:BAAANQAECgEIAQAAAA==.Palimax:BAAANQAECgEIAgAAAA==.Pallyaxe:BAABNQAECn8eAAMBAAgKaRCaWgCZAQABAAgKaRCaWgCZAQAUAAUKhAKZUwGbAAABNQAECgoKSAAPAMwZAA==.Pallygank:BAAANQADCgEIAQAAAA==.Pandawannabe:BAABNQAECn8pAAIEAAgKxB7lLwAFAgAEAAgKxB7lLwAFAgAAAA==.Pandussi:BAABNQAECn8aAAIiAAkKxhNiJAACAgAiAAkKxhNiJAACAgAAAA==.Paneer:BAABNQAECn8qAAICAAoK4SLbCwB+AwACAAoK4SLbCwB+AwABNQAFFAIIBQAFAHEcAA==.Paninus:BAAANQAECgEIAgAAAA==.Papabair:BAAANQAECgcICQABNQAECggIEQAIAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgIIAwAAAA==.Perfectplex:BAAANQAECgYIBwAAAA==.Peruano:BAABNQAECn8sAAIQAAoKkRTxCABsAgAQAAoKkRTxCABsAgAAAA==.Petforheals:BAAANQAECgUIDwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECggIKQAEAMQeAA==.',
Pi='Pietastegood:BAABNQAECn85AAIDAAoK1yUdCQCrAwADAAoK1yUdCQCrAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYIBgABNQAECggICwAIAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECggIEQAIAAAAAA==.Pitchblack:BAABNQAECn8YAAIRAAoKugzYIAAyAgARAAoKugzYIAAyAgAAAA==.',
Po='Pocahöntas:BAABNQAECn8bAAICAAoKWgeofACmAQACAAoKWgeofACmAQAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAACNQAFFH8FAAIfAAIKqBcXBgCgAAAfAAIKqBcXBgCgAAA1AAQKf0AAAh8ACgpwIAQFAD8DAB8ACgpwIAQFAD8DAAAA.Pontiack:BAAANQAECggICAAAAA==.Poordemon:BAAANQADCgUIBQABNQAECgkJFgAUAFESAA==.Popehealz:BAAANQADCgYIAgAAAA==.Pownds:BAAANQAECgYIDAAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAABNQAFFH8KAAITAAYKWBpeDQCzAQATAAYKWBpeDQCzAQAAAA==.Procspls:BAAANQADCgIIAgAAAA==.Proenz:BAAANQAECgIIAgAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAgABNQAECgcIGwAGANUOAA==.Pryor:BAAANQAECgYIEgAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGwAGANUOAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGwAGANUOAA==.Prøntø:BAABNQAECn8bAAMGAAcK1Q4ZJwBdAQAGAAcK1Q4ZJwBdAQAHAAIK3QP8OwBJAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgoKMgADACofAA==.Punchbugman:BAAANQAECgEIAQAAAA==.Puritos:BAAANQAECgQICwAAAA==.Pustain:BAAANQAECgEIAQAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECggIDgAIAAAAAA==.Pyrista:BAABNQAECn8kAAICAAkKEBl4SgCOAgACAAkKEBl4SgCOAgAAAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgQIBQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECn82AAIbAAoKpBGVIwDYAQAbAAoKpBGVIwDYAQAAAA==.Radilas:BAAANQAECgEIAQAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECgoKOQADANclAA==.Raendarth:BAAANQAECgUIEAAAAA==.Rageth:BAABNQAECn8nAAMLAAoKRxNhIADQAQALAAkKFBFhIADQAQAMAAYKjg/wDwApAQAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAFFAMIDQAVAEoUAA==.Rakalaag:BAEANQAECgQIDAAAAA==.Rakath:BAABNQAECn8VAAIaAAcKUA8vPgAeAQAaAAcKUA8vPgAeAQAAAA==.Ramidus:BAAANQAECgQICAAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIEAAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECn8yAAIDAAoKKh/aLAAJAwADAAoKKh/aLAAJAwAAAA==.Redharvest:BAABNQAECn8eAAIkAAoKiRUACwABAgAkAAoKiRUACwABAgAAAA==.Redlands:BAAANQAECgEIAgAAAA==.Redredwine:BAAANQADCggICAAAAA==.Refractory:BAAANQAECgUIBwAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Rennala:BAAANQADCggICAAAAA==.Renwick:BAAANQAECgIIAgABNQAFFAcIGAAOAIYZAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAABNQAECn8rAAIUAAoKfxTRnADpAQAUAAoKfxTRnADpAQAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgYIBgABNQAFFAMIDQAVAEoUAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Ribeyes:BAAANQAECgEIAQAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECn89AAIEAAoKJCAdGgCOAgAEAAoKJCAdGgCOAgAAAA==.Rikoe:BAAANQAECgUICgAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQAECgEIAQAIAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQAECgEIAgAAAA==.',
Ro='Rockabye:BAABNQAECn8pAAMRAAkK+hpoFQC1AgARAAkK+hpoFQC1AgATAAIKyAdh0QBrAAAAAA==.Rokar:BAAANQAECgEIAgAAAA==.Roraalionnu:BAAANQADCgUIDgABNQAECgEIAgAIAAAAAA==.Rosannas:BAAANQAECgIIAgABNQAFFAMIDQAVAEoUAA==.Rosi:BAAANQAECgEIAQAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFH8gAAMfAAcKZxPrAACjAQAfAAcKZxPrAACjAQAEAAMKshGyGQD0AAA1AAQKf0wAAx8ACgqOINEFAM4CAB8ACgqOINEFAM4CAAQACQqKFSRIAFYCAAAA.Ruibash:BAEBNQAECn9bAAIUAAoKKCXSEACGAwAUAAoKKCXSEACGAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Rumproast:BAAANQAECggIAQAAAA==.Runebladé:BAABNQAECn8YAAIYAAgKXhmUPQApAgAYAAgKXhmUPQApAgAAAA==.',
Ry='Ryuu:BAAANQAECgEIAQAAAA==.Ryuuzen:BAAANQAECggIDgAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQAECgUIDAAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAIAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAgAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAIAAAAAA==.Sakuraa:BAABNQAECn8uAAMTAAoKvhKvTADwAQATAAoKvhKvTADwAQASAAMKLQEdJABKAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAgAAAA==.Sassassassin:BAAANQAECgQIBAAAAA==.Savaged:BAAANQAECggIEAABNQAECgoKSgAYAG8XAA==.Savajed:BAABNQAECn9KAAMYAAoKbxdCIgC6AQAjAAoKbBGzOQDsAQAYAAkKQBhCIgC6AQAAAA==.Savaragon:BAAANQAECgQIBQABNQAECgoKSgAYAG8XAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scaledoc:BAAANQAECgMIAwABNQAECggIEQAIAAAAAA==.Scallywagg:BAABNQAECn8cAAIFAAoKfhh1IAClAgAFAAoKfhh1IAClAgAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Schism:BAAANQAECgUIBgAAAA==.Scrodo:BAAANQAECgEIBQAAAA==.',
Se='Searcomic:BAAANQAECgcIEgAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECn8xAAMnAAoKdRYoBgBuAgAnAAoKdRYoBgBuAgAMAAMKpQfZLwCbAAAAAA==.Selendas:BAAANQAECgEIAQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinanomi:BAAANQAECgcIDgAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECn83AAMGAAoKuyQ+AgCrAwAGAAoKuyQ+AgCrAwAHAAEKAABfRgAtAAAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgUIEwAAAA==.Shameless:BAAANQAECgcICwAAAA==.Shamwów:BAABNQAECn8XAAIFAAgKnxrwPwBgAgAFAAgKnxrwPwBgAgAAAA==.Sharco:BAABNQAECn8nAAMZAAgKvBgMDgDMAQAZAAYKpR8MDgDMAQAPAAcKrBJX8wCkAQAAAA==.Sharkbites:BAAANQAECgYIDAAAAA==.Shawarmafury:BAACNQAFFH8SAAICAAUK9SNVCADFAQACAAUK9SNVCADFAQA1AAQKf0MAAgIACgrnJncCAN8DAAIACgrnJncCAN8DAAAA.Shelandra:BAAANQAECggIBAAAAA==.Sherrizzahh:BAAANQADCgEIAQAAAA==.Shettani:BAAANQAECggICQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shinshots:BAAANQADCggICAAAAA==.Shockrasta:BAAANQAECgUIDQABNQAFFAIIBQAPAEMfAA==.Shooshmael:BAABNQAECn8cAAIEAAgKKxewWwAPAgAEAAgKKxewWwAPAgAAAA==.Shozo:BAAANQADCgUICAABNQAECgoKNwAGALskAA==.Shujáa:BAAANQAECggIDgAAAA==.Shyvîolet:BAABNQAECn8mAAMFAAoKghWJVwALAgAFAAoKghWJVwALAgAEAAEKMwG/YgETAAAAAA==.Shælynne:BAAANQADCgYIBgABNQAECgoKbQAcAFwcAA==.Shékinah:BAACNQAFFH8OAAIaAAQKkAQdFQCuAAAaAAQKkAQdFQCuAAA1AAQKfzQAAhoACgpJEVg9AAwCABoACgpJEVg9AAwCAAAA.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silentia:BAAANQADCgQIBAABNQAECgkJJgATACgSAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIBAAAAA==.Sinthein:BAAANQAECgUIBwABNQAFFAcIGAAOAIYZAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAIAAAAAA==.',
Sk='Skadgrip:BAAANQAECgEIAQABNQAECgkJFAAEAHgYAA==.Skorpekh:BAABNQAECn8ZAAICAAgKSQZUsQChAQACAAgKSQZUsQChAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECn8cAAIlAAgKWR9IEwCyAgAlAAgKWR9IEwCyAgAAAA==.Sloppyspikes:BAABNQAECn8bAAIoAAoKogd1GAAqAQAoAAoKogd1GAAqAQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECn9iAAMpAAoKhyQSAQBLAwApAAoKhyQSAQBLAwADAAkKxBoLWACDAgABNQAECgoKXwACAK8kAA==.Smidgenn:BAAANQADCgcIEQAAAA==.Smokyblast:BAABNQAECn8jAAIPAAoKiwbUkABxAQAPAAoKiwbUkABxAQAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECn8+AAIPAAkKgwRqBwGBAQAPAAkKgwRqBwGBAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECn8lAAMiAAoKuw8cMgCGAQAiAAkKlw8cMgCGAQAKAAIK0g/dJAA1AAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIEQAAAA==.',
Sp='Sparowprince:BAACNQAFFH8TAAIUAAcKhRd5CQA3AQAUAAcKhRd5CQA3AQA1AAQKf1cAAhQACgqpJY4HAFoDABQACgqpJY4HAFoDAAAA.Spaspanda:BAAANQAECgQIBgABNQAECggIKQAEAMQeAA==.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAIAAAAAA==.Spectraleye:BAAANQAECgcIEQAAAA==.Sproocherlou:BAABNQAECn9HAAIUAAoK+CEcFAAOAwAUAAoK+CEcFAAOAwAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
Sr='Srgoblinghon:BAAANQADCgUIBQAAAA==.',
St='Stankbolt:BAABNQAECn8uAAINAAoKJyVACQAYAwANAAoKJyVACQAYAwAAAA==.Steezya:BAAANQAECgUIEwAAAA==.Stegulos:BAAANQAECgEIAwAAAA==.Stellarum:BAAANQAECgMIBAAAAA==.Stonedemon:BAABNQAECn8XAAMbAAoKEBO+LwCBAQAbAAoKEBO+LwCBAQAoAAEKKg6zLgApAAABNQAFFAcIEwAUAIUXAA==.Stormsy:BAABNQAECn8XAAMBAAkKpQzaVQCrAQABAAkKpQzaVQCrAQAUAAIKHwKIpQE0AAABNQAECgkJJgATACgSAA==.Stormykitty:BAABNQAECn8mAAMTAAkKKBLdWQDAAQATAAkKKBLdWQDAAQARAAEKEQUjYQAvAAAAAA==.Strauch:BAAANQADCgcIIgAAAA==.Striderdh:BAAANQABCggIEQAAAA==.Strongwoman:BAAANQAECgUIEwAAAA==.Sturtza:BAACNQAFFH8JAAICAAIKpBGwIACTAAACAAIKpBGwIACTAAA1AAQKf0wAAgIACgrDIYQGAKoDAAIACgrDIYQGAKoDAAAA.Sturtzam:BAAANQAECgUIBgABNQAFFAIICQACAKQRAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sumat:BAAANQADCgIIAgABNQAECgEIAgAIAAAAAA==.Sunbear:BAAANQADCggIDwAAAA==.Sungayan:BAAANQAECgQIAwAAAA==.Susak:BAAANQAECgcIDAABNQAECgkJGgAXAGIeAA==.Suun:BAABNQAECn89AAIUAAoK8B7oPADfAgAUAAoK8B7oPADfAgAAAA==.',
Sw='Sweetysnail:BAAANQAECgcIEgAAAA==.Swoley:BAABNQAECn8ZAAIBAAgKux/OMQCeAgABAAgKux/OMQCeAgAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taake:BAAANQAECggICQAAAA==.Taanua:BAAANQAECgYIBwAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECn8rAAIZAAoKpgtfDgDFAQAZAAoKpgtfDgDFAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAABNQAECn8XAAIBAAUKPBGgrwAgAQABAAUKPBGgrwAgAQAAAA==.Talisaie:BAABNQAECn8oAAMNAAoKkCM1DAAAAwANAAoKCCM1DAAAAwAQAAUKPR8pBgBsAQABNQAFFAcIFwAbAKUcAA==.Tanisatharae:BAAANQAECgEIAQABNQAECggIDgAIAAAAAA==.Tarahly:BAAANQAECgYICAABNQAECgkJLAABAKwhAA==.Tarahse:BAAANQADCgIIAgABNQAECgkJLAABAKwhAA==.Taron:BAABNQAECn8qAAIDAAkKmBbTUAD5AQADAAkKmBbTUAD5AQAAAA==.Tart:BAACNQAFFH8FAAMEAAMKyw5yJACaAAAEAAIKyw5yJACaAAAFAAEKLwD/NAAXAAA1AAQKfxkAAgQACQp1EL9bAA8CAAQACQp1EL9bAA8CAAAA.Taualain:BAAANQAECgEIAQABNQAECggIKQAEAMQeAA==.',
Te='Techmaestrov:BAAANQAECgUICgAAAA==.Tedjones:BAABNQAECn8WAAIPAAYKAwXnQQEfAQAPAAYKAwXnQQEfAQAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.Tenderrot:BAAANQADCgUIBQAAAA==.',
Tg='Tgbird:BAAANQAECggICAAAAA==.',
Th='Thandana:BAAANQAECgUIDQAAAA==.Thehumanatee:BAABNQAECn8vAAIaAAoKiBeILQBxAgAaAAoKiBeILQBxAgAAAA==.Theroach:BAABNQAECn8XAAMhAAYK/Q8QRADiAAAhAAQK9RQQRADiAAAUAAMKTAi/JwGbAAAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICwAIAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingstabz:BAAANQAECgIIAgAAAA==.Thingytoo:BAAANQAECggIEAAAAA==.Thiqq:BAAANQAECgUIAgAAAA==.Threlindrier:BAAANQAECgIIAwAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAABNQAECn8sAAIDAAoKDQsaZwC1AQADAAoKDQsaZwC1AQAAAA==.Thyphlo:BAABNQAECn8XAAISAAgKzxZtBQCkAQASAAgKzxZtBQCkAQAAAA==.',
Ti='Tictacs:BAAANQABCgYIBgAAAA==.Tiltawhirl:BAAANQAECggICwAAAA==.Tiltedup:BAABNQAECn80AAIPAAoK7hjENgBeAgAPAAoK7hjENgBeAgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQAECgYICwABNQAECgkJJgATACgSAA==.Tirich:BAAANQADCggICAABNQAFFAcIGAAOAIYZAA==.Titaintium:BAAANQAECgQIBAABNQAECgoKPAAbAIkiAA==.',
To='Toshi:BAABNQAECn8kAAINAAoKYwlAhwA6AQANAAoKYwlAhwA6AQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECgoKPwAmAPsRAA==.Touchyouup:BAAANQAECgIIBAAAAA==.',
Tr='Trilguth:BAAANQADCgYIBgAAAA==.Truckkun:BAAANQAECggICwAAAA==.Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAwAAAA==.',
Tu='Tulark:BAAANQABCgYIBgAAAA==.Tullydin:BAABNQAECn8nAAMhAAoKyAj1MgBLAQAUAAgKRQhW3gBeAQAhAAkKewf1MgBLAQAAAA==.Tullyy:BAAANQAECgQIDwAAAA==.Tums:BAABNQAECn81AAMOAAoKUx3UFwAfAgAOAAoK8BvUFwAfAgAVAAgKXBiNIAAeAQAAAA==.Tusaditty:BAAANQADCgYIBgAAAA==.',
Tw='Tweez:BAAANQAECgEIAQAAAA==.Twirls:BAABNQAECn8YAAIKAAgK7RnGDQAdAgAKAAgK7RnGDQAdAgAAAA==.Twistoffate:BAABNQAECn8XAAIZAAYK9AH2NABnAAAZAAYK9AH2NABnAAAAAA==.Twoduces:BAAANQADCgQIBAAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
['Tä']='Tälos:BAAANQADCgUIBQABNQADCggIDQAIAAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAABNQAECn8YAAIZAAcKTgoyIADoAAAZAAcKTgoyIADoAAAAAA==.Unsubtley:BAABNQAECn8bAAIOAAoK2ApXTAC1AQAOAAoK2ApXTAC1AQABNQAECgUICgAIAAAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECn8xAAMUAAoKHB8aewA1AgAUAAoKHB8aewA1AgAhAAUKiRDLNgDCAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAABNQAECn8ZAAINAAoKEw8piwDLAQANAAoKEw8piwDLAQAAAA==.',
Va='Valgorr:BAAANQAECgYIDAAAAA==.Valvalon:BAABNQAECn81AAIZAAoK3R1wBADlAgAZAAoK3R1wBADlAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.Vanessia:BAAANQADCgQIBAAAAA==.Varhaitof:BAAANQADCggICAAAAA==.',
Ve='Veelaria:BAABNQAECn80AAIhAAoKUw9wHwBdAQAhAAoKUw9wHwBdAQAAAA==.Vegetablue:BAAANQAECgEIAQABNQAECgcIBgAIAAAAAA==.Velinddrel:BAAANQADCgUIBQAAAA==.Verahardyr:BAAANQADCgQIBAAAAA==.Veravulp:BAAANQAECgEIAgAAAA==.Verdunkeln:BAAANQAECgcIDAAAAA==.Verymelon:BAAANQABCgQIAgAAAA==.Vet:BAAANQAECgQICAAAAA==.',
Vh='Vhelithiana:BAAANQAECgIIBQAAAA==.',
Vi='Viathun:BAAANQAECgUIBQABNQAECgoKSgAYAG8XAA==.Vicalaus:BAABNQAECn87AAIjAAkKgRz0KQBKAgAjAAkKgRz0KQBKAgABNQAECgoKTQAcAEYbAA==.View:BAABNQAECn8rAAIFAAoK4RWSPQAJAgAFAAoK4RWSPQAJAgAAAA==.Vikcy:BAABNQAECn8VAAIEAAkK7w7jSQCXAQAEAAkK7w7jSQCXAQAAAA==.Vikcyholy:BAAANQAECgQIBQABNQAECgkJFQAEAO8OAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitamind:BAAANQAECgUIBgAAAA==.Vitros:BAAANQADCgcIBwABNQAECgoKMwARAI0fAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgkJFQAGAHMgAA==.Voidwitch:BAABNQAECn8rAAIQAAkKbCODAQCcAgAQAAkKbCODAQCcAgAAAA==.Volstagg:BAAANQAECgEIAQAAAA==.Vortirtbreni:BAAANQAECgQIBQAAAA==.',
Vr='Vrakken:BAABNQAECn85AAIjAAoKdBTPJAAZAgAjAAoKdBTPJAAZAgAAAA==.',
Vu='Vududonkey:BAAANQAECgMIAwABNQAECgkJGwAHAAcPAA==.Vulmaster:BAAANQAECgMIAgAAAA==.',
Vy='Vyndenus:BAACNQAFFH8HAAITAAQKqAyEHwDOAAATAAQKqAyEHwDOAAA1AAQKf1QAAhMACgqIIMAUAB8DABMACgqIIMAUAB8DAAAA.',
Wa='Warriorluv:BAAANQAECgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECggIDAAAAA==.Welor:BAAANQAECgYICQAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Wheremytotem:BAAANQADCggIDQABNQAECgoKMgATAN4dAA==.Whitbone:BAAANQADCgUICQAAAA==.Wholephister:BAAANQAECgEIAQABNQAECggIFwAfAFASAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAABNQAECn8VAAINAAkKwAkBggBHAQANAAkKwAkBggBHAQAAAA==.Wigpetval:BAABNQAECn8nAAMCAAgKnRGImQDUAQACAAgKURGImQDUAQAgAAQKNgtCaQCIAAAAAA==.Wiidge:BAABNQAECn8nAAImAAoKdwoTDACjAQAmAAoKdwoTDACjAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBwAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECn8XAAIaAAYK+xhMSADJAQAaAAYK+xhMSADJAQAAAA==.Wolfchan:BAABNQAECn8jAAIPAAgKTQxMnQBXAQAPAAgKTQxMnQBXAQAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgoKTQAcAEYbAA==.Worldcrafter:BAABNQAECn8nAAMSAAkKBh+PCADbAQATAAgKJCCxKgCLAgASAAYKkRuPCADbAQAAAA==.Worldender:BAABNQAECn8iAAMTAAoKEhu5FAAgAwATAAoKwhq5FAAgAwASAAUKZRhiDQBeAQAAAA==.Wowretail:BAABNQAECn8kAAQhAAcKphs6IQDaAQAhAAYKnB46IQDaAQAUAAYKZRtNrQDFAQABAAQKSSCQwQD4AAAAAA==.',
Wr='Wrathofdawn:BAAANQAECgYIEAAAAA==.Wreckross:BAAANQAECgEIAwAAAA==.',
Wy='Wyldar:BAABNQAECn8iAAIUAAoKKRY5kwD9AQAUAAoKKRY5kwD9AQAAAA==.',
Xa='Xalaria:BAABNQAECn8dAAIPAAoKuwXgmABgAQAPAAoKuwXgmABgAQAAAA==.Xantry:BAACNQAFFH8FAAIUAAMK3gveGwDJAAAUAAMK3gveGwDJAAA1AAQKfxwAAhQACQr+IoE4AO4CABQACQr+IoE4AO4CAAAA.',
Xe='Xeviscerated:BAAANQAECgUICgAAAA==.',
Xm='Xmen:BAABNQAECn8rAAIPAAgKXwurmQBfAQAPAAgKXwurmQBfAQAAAA==.',
Xo='Xoutlawnmeta:BAAANQAECgIIAgAAAA==.',
Xs='Xslight:BAAANQAECgcICQABNQADCggIDgAIAAAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgUICAAAAA==.',
Ye='Yeastybush:BAACNQAFFH8IAAIFAAMKCBhdFQD0AAAFAAMKCBhdFQD0AAA1AAQKfzsAAwUACgpqIQUkANYCAAUACgpqIQUkANYCAAQABQogFYVdAFYBAAAA.',
Yi='Yinsen:BAAANQADCggICAAAAA==.',
Ys='Yseera:BAAANQAECgUIDAAAAA==.Yseeraa:BAAANQAECgEIBQAAAA==.',
Za='Zakutlek:BAAANQAECgEIAQAAAA==.Zalatoes:BAAANQAECgEIAQAAAA==.Zarathea:BAAANQAECgMIBAABNQAECgUIBQAIAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQAECgEIAQAAAA==.Zimms:BAABNQAECn8tAAIiAAoKlR0YDwDyAgAiAAoKlR0YDwDyAgAAAA==.',
Zo='Zoeyredbird:BAABNQAECn8UAAQjAAkKOxjmRgCjAQAjAAcK1RbmRgCjAQAXAAQKURkSRQAbAQAYAAIKDBe+tACGAAAAAA==.Zongo:BAAANQADCgcIBwAAAA==.Zonnit:BAAANQADCgQIBAAAAA==.',
Zw='Zwhitty:BAAANQADCgcICQAAAA==.Zwhittytv:BAABNQAECn8YAAIMAAoKHxRiCgCyAQAMAAoKHxRiCgCyAQAAAA==.',
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
