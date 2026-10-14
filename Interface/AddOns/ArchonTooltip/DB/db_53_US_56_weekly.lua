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

local lookup = {'Paladin-Holy','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-BeastMastery','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Rogue-Subtlety','Warlock-Destruction','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Assassination','Mage-Arcane','Paladin-Protection','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','Warrior-Protection','Mage-Frost','Druid-Feral','Monk-Windwalker','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Evoker-Augmentation','Shaman-Enhancement',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aamara:BAABNQAECn8gAAIBAAcKyx1AQQBdAgABAAcKyx1AQQBdAgAAAA==.',
Ab='Aboyton:BAAANQAECgEIAQAAAA==.',
Ad='Adarksoul:BAAANQAECgEIAQAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwACAPkTAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAABNQAECn8qAAMDAAkKWiR3FgA/AwADAAgKWiR3FgA/AwAEAAkKlRV5TAAuAgABNQAFFAIIAwAFAAAAAA==.Aelistiah:BAAANQABCggIEwAAAA==.Aerithorn:BAABNQAECn8cAAIGAAgKciCKCQDYAgAGAAgKciCKCQDYAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECggIJAAHAEEZAA==.Ahleya:BAAANQAECgYIBgAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAFAAAAAA==.',
Ak='Akazza:BAAANQADCgIIAgAAAA==.Akoris:BAAANQAECgIIAwABNQAECgkJHAAIADARAA==.Akorys:BAABNQAECn8cAAMIAAkKMBF5GQDjAQAIAAkKMBF5GQDjAQAJAAEKAADBNAAjAAAAAA==.',
Al='Albyno:BAACNQAFFH8NAAMKAAUKtQy3CwBeAQAKAAUKtQy3CwBeAQALAAEK8waeDwBDAAA1AAQKfyMAAgoACQp9GzQMAOACAAoACQp9GzQMAOACAAAA.Algebrah:BAAANQAECgMIAwAAAA==.',
Am='Amara:BAAANQADCgYIHQAAAA==.Ambitionz:BAAANQADCgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECn8gAAIMAAYKvAL/+ADTAAAMAAYKvAL/+ADTAAAAAA==.Ancksunamun:BAAANQADCggIDQAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgcIIAABAMsdAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFH8WAAINAAUK2R3IBQC9AQANAAUK2R3IBQC9AQA1AAQKfyAAAg0ACQrLH9MFACcDAA0ACQrLH9MFACcDAAAA.',
Ap='Aperture:BAAANQADCgcIEwAAAA==.',
Aq='Aquua:BAABNQAECn8oAAIDAAgKYh6dNACiAgADAAgKYh6dNACiAgAAAA==.',
Ar='Araelen:BAAANQAECgcIEAAAAA==.Arcticdps:BAABNQAECn8sAAMMAAkK1BieQwCEAgAMAAkK1BieQwCEAgAOAAEKVxZsbQBDAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECn8kAAQPAAkKTh7qKgDMAQAPAAYKeRrqKgDMAQAQAAcKcw8HfAChAQARAAcKUQ50DABwAQAAAA==.Ariestar:BAAANQAECgcIDQAAAA==.Ariiel:BAAANQADCggICQABNQAECgkJJAAPAE4eAA==.Arthimas:BAAANQAECgIIAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAAANQAECgUIEAAAAA==.Asidize:BAAANQAECgUICgAAAA==.Aslor:BAABNQAECn8fAAIMAAcKahvlZAAoAgAMAAcKahvlZAAoAgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYICQAAAA==.',
At='Athalia:BAACNQAFFH8FAAISAAIKqRj5EwClAAASAAIKqRj5EwClAAA1AAQKfzAAAhIACQoBIxAFAIADABIACQoBIxAFAIADAAAA.Atlaswolfe:BAAANQAECgcIBwAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECgcIDgAAAA==.Autofellate:BAAANQADCgIIAgAAAA==.',
Av='Avaldra:BAAANQABCgEIAQAAAA==.Avex:BAABNQAECn8kAAIHAAgKQRn7XABcAgAHAAgKQRn7XABcAgAAAA==.',
Ax='Axemage:BAABNQAECn8sAAITAAgK+RhRjABmAgATAAgK+RhRjABmAgAAAA==.Axeom:BAABNQAECn8yAAIEAAkKTxr5JgDGAgAEAAkKTxr5JgDGAgAAAA==.Axeshammy:BAAANQAECgMIAwABNQAECggILAATAPkYAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAFFAEIAgAAAA==.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAAANQAECgYIDwAAAA==.Barcliah:BAAANQADCgIIAgAAAA==.Barometer:BAAANQAECgUIDAAAAA==.Bast:BAAANQADCggICwABNQAECgcIDwAFAAAAAA==.Baxa:BAAANQAECggICAAAAA==.Baylee:BAABNQAECn8eAAITAAcKvgOmMAE3AQATAAcKvgOmMAE3AQAAAA==.',
Bb='Bbartemis:BAAANQAECgYIEgAAAA==.',
Bc='Bchamp:BAAANQADCgQIBAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgQIBAABNQAECgYIBwAFAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIBAABNQAECgkJIgANAM0aAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgQIBQAAAA==.Belzenlok:BAAANQADCgUICQAAAA==.Benjohnbo:BAAANQABCgEIAQAAAA==.Benwins:BAAANQAECgcIDQAAAA==.Bergamö:BAAANQADCgcIDwABNQAECgMIBgAFAAAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Bigangus:BAAANQAECgIIAwAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Bigmerch:BAAANQADCgcIDgAAAA==.Biom:BAABNQAECn8dAAQUAAYKDB/DIADbAQAUAAYKnB7DIADbAQAVAAYKZRtyqgDGAQABAAMKISCAvwD5AAAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAAANQAECgYIEwAAAA==.Bisholoyd:BAAANQAECgYIDgAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgQIAwAAAA==.Blastoise:BAABNQAECn8sAAMWAAkKeSSWBACnAwAWAAkKLCSWBACnAwAXAAcKuRg5OwAyAgAAAA==.Blinktwice:BAAANQABCgcIBwAAAA==.Blizfishleg:BAAANQAECgUIDQAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMIBwAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQABCgYICAAAAA==.Boombóx:BAAANQAECgQIBQABNQAECgkJLQAMANMiAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAABNQAECn8kAAIYAAgKSCCdEgDUAgAYAAgKSCCdEgDUAgAAAA==.Bowsback:BAAANQADCggIJwAAAA==.Bowyohead:BAABNQAECn8XAAIQAAkK5Bj3MAChAgAQAAkK5Bj3MAChAgABNQAECgkJKAABAGAYAA==.',
Br='Bracydaboss:BAAANQAECgEIAgAAAA==.Bradroybboi:BAAANQAECgQIBQAAAA==.Braingap:BAAANQAECgIIAgABNQAECggIDAAFAAAAAA==.Brandoe:BAAANQAECgQIBgAAAA==.Breece:BAAANQAECgIIAgAAAA==.Brickinkeys:BAAANQADCgYIDAABNQAECgcIIAABAMsdAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECn8dAAIZAAcKBQeUDgBLAQAZAAcKBQeUDgBLAQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caenarigos:BAAANQAECgEIAQAAAA==.Caenarius:BAAANQADCgMIAwABNQAECgEIAQAFAAAAAA==.Caimie:BAAANQAECgIIAwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQICQAAAA==.Capnmorgan:BAAANQABCgEIAQAAAA==.Cassiaan:BAAANQAECgMIAwAAAA==.Caylavibes:BAABNQAECn8hAAIQAAkKHxHCUwAkAgAQAAkKHxHCUwAkAgAAAA==.',
Ch='Chaviel:BAAANQAECggICgAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAAANQAECggIEAAAAA==.Chironn:BAABNQAECn8nAAIaAAgKrxroAwC8AgAaAAgKrxroAwC8AgAAAA==.Chudlord:BAAANQADCggICwAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIAwAAAA==.',
Ci='Cinderburn:BAAANQAECgQIBwAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgMIBQAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAQAAAA==.Comfychair:BAABNQAECn8WAAIVAAgKUB9ZQADRAgAVAAgKUB9ZQADRAgAAAA==.Coowmoo:BAAANQAECgUIDAAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAMIBwAbAK8cAA==.Cosmonodder:BAAANQAECggIDAABNQAFFAMIBwAbAK8cAA==.Cosmoshotter:BAACNQAFFH8HAAMbAAMKrxx6FADyAAAbAAMKrxx6FADyAAAHAAEKAADuNgBLAAA1AAQKfxkAAxsACQqpFl8bAHcCABsACQqpFl8bAHcCAAcAAQrvIag7AWMAAAAA.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQAECgEIAQAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cuchulainn:BAAANQADCgMIAwAAAA==.Cucubau:BAAANQADCgcICwAAAA==.',
Cy='Cyndra:BAAANQAECgcICgAAAA==.',
Da='Dakai:BAAANQADCgIIAgAAAA==.Dallthyrian:BAAANQADCgYIBgABNQAECgUICAAFAAAAAA==.Dalthyrian:BAAANQAECgYIDQABNQAECgUICAAFAAAAAA==.Dalthyriian:BAAANQAECgUICAAAAA==.Dalthyrrian:BAAANQAECgEJAQABNQAECgUICAAFAAAAAA==.Dalthyyrian:BAAANQAECgUIBwABNQAECgUICAAFAAAAAA==.Damii:BAAANQADCgUICQAAAA==.Danarand:BAAANQADCgMIAwABNQAECgcIGQAGAPcSAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgcIDwAFAAAAAA==.Darjen:BAAANQAECgUIDAAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darkshock:BAAANQADCgIIAgAAAA==.Darksky:BAAANQAECgMIBQAAAA==.Daysfox:BAABNQAECn8jAAMbAAgK4wxrMgC2AQAbAAgKjQxrMgC2AQAHAAEKugwpSgFEAAAAAA==.Daysmonk:BAAANQAECggIEwAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCggIDQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgkJLgASAPYeAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECn8uAAMSAAkK9h4nFADXAgASAAgK9h4nFADXAgANAAQKWAikOQDkAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathsdawn:BAAANQADCggICAABNQAECgkJMQAYAB4cAA==.Deathstone:BAABNQAECn8ZAAMcAAgKPxirKQBIAgAcAAgKPxirKQBIAgAXAAMKcA25qQCeAAABNQAFFAUIDAAVAP4WAA==.Deathtress:BAABNQAECn8bAAQcAAkKwhHTMQAVAgAcAAkKwhHTMQAVAgAXAAEKNAOx8gAiAAAWAAEKAAD12gAhAAAAAA==.Debbydowner:BAABNQAECn8dAAICAAcKDwoIwAB3AQACAAcKDwoIwAB3AQAAAA==.Decado:BAAANQAECgcIDwAAAA==.Deemwins:BAAANQAECgYIBQAAAA==.Deezenuts:BAAANQAECggICAAAAA==.Degen:BAAANQAECgQICwAAAA==.Dejevoid:BAAANQAECggIEAAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Deliquium:BAAANQABCggICgAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECn8pAAMdAAgKaxn7DQBMAgAdAAgKaxn7DQBMAgACAAMKuAj2IgGLAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Deww:BAABNQAECn8bAAMRAAkK2xfvBABpAgARAAgKQxjvBABpAgAQAAYKSBkAaQDfAQAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECn8cAAIUAAgKYArpNQA0AQAUAAgKYArpNQA0AQAAAA==.',
Di='Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECn8oAAIWAAgKEySsEwANAwAWAAgKEySsEwANAwAAAA==.',
Do='Docdolittle:BAABNQAECn83AAMHAAkKxCNUCQCRAwAHAAkKxCNUCQCRAwAbAAEKdBH7gAA9AAAAAA==.Docfreez:BAABNQAECn8tAAMeAAkKeiGnBwBwAgATAAkKmR9DQQACAwAeAAcKmBunBwBwAgAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgcIDwAFAAAAAA==.Doctermoo:BAAANQAECgUIBgAAAA==.Dogar:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECggIJAAYAEggAA==.Doraemee:BAAANQAECgQIBwAAAA==.',
Dr='Drbaconbrgr:BAAANQAECgYIEgABNQAECgkJKAAHABMkAA==.Drbakedziti:BAAANQADCgYIBgABNQAECgkJKAAHABMkAA==.Drbaobuns:BAAANQAECgYICwABNQAECgkJKAAHABMkAA==.Drcarrotcake:BAAANQAECgQIBQABNQAECgkJKAAHABMkAA==.Drcheeseball:BAAANQAECgYIDgABNQAECgkJKAAHABMkAA==.Dreggsalad:BAAANQAECgUIDwABNQAECgkJKAAHABMkAA==.Dreim:BAEANQAECgYIBgABNQAECgkJOwAVAMYjAA==.Dreima:BAAANQAECgQIBAAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgkJKAAHABMkAA==.Drgatorwine:BAAANQAECgYIDgABNQAECgkJKAAHABMkAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgkJKAAHABMkAA==.Drkimchirice:BAABNQAECn8iAAIfAAkK6SPqAQClAwAfAAkK6SPqAQClAwABNQAECgkJKAAHABMkAA==.Drmacncheese:BAABNQAECn8bAAIOAAYK3x+VCgBNAgAOAAYK3x+VCgBNAgABNQAECgkJKAAHABMkAA==.Drpumpkinpie:BAABNQAECn8ZAAIVAAgKTxspWgCFAgAVAAgKTxspWgCFAgABNQAECgkJKAAHABMkAA==.Drshephardpi:BAAANQADCggICgABNQAECgkJKAAHABMkAA==.Drshortbread:BAAANQAECgUICwABNQAECgkJKAAHABMkAA==.Druiddres:BAAANQAECgQIBAAAAA==.Druidussy:BAAANQADCggICAAAAA==.Drwontonsoup:BAABNQAECn8oAAIHAAkKEyTFBwCfAwAHAAkKEyTFBwCfAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAABNQAECn8rAAINAAkKcSBOBgAbAwANAAkKcSBOBgAbAwAAAA==.',
Ek='Eksi:BAABNQAECn8VAAIgAAcKMxQ0LwCZAQAgAAcKMhQ0LwCZAQAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAUIFgANANkdAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgQIBgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgMIBAAAAA==.',
Em='Embedded:BAAANQAECgcIDwAAAA==.Eme:BAAANQAECgIIAgAAAA==.Empress:BAABNQAECn8YAAIcAAcKmAsUTgB2AQAcAAcKmAsUTgB2AQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.Enriq:BAAANQAECgEIAQABNQAECgQICQAFAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erikaa:BAAANQAECgUIBwAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAQABNQAECggIDAAFAAAAAA==.',
Ex='Excruciator:BAABNQAECn8lAAMhAAgKsRM3RwDLAQAhAAcK0xU3RwDLAQAiAAIKtAcyZQBqAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAAANQAECgUIBwAAAA==.Falloutzhunt:BAAANQADCgYIBgABNQAECgUIBwAFAAAAAA==.Fantarada:BAAANQADCgYIBgAAAA==.Farahcanle:BAABNQAECn8vAAIGAAgKyBGQHgClAQAGAAgKyBGQHgClAQAAAA==.Farrock:BAABNQAECn8ZAAIGAAcKLAugLAAuAQAGAAcKLAugLAAuAQAAAA==.Fawxette:BAAANQADCggICAABNQAECgkJPwAYALkcAA==.',
Fe='Felanish:BAAANQAECgEIAQAAAA==.Felystia:BAAANQAECgUIDgAAAA==.Fenra:BAAANQADCgcIDwAAAA==.Feorblarir:BAAANQAECgUICwAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQADCgYIBgABNQAECgcIGAAdAKYIAA==.Filledegel:BAAANQAECgQICQABNQAECgcICQAFAAAAAA==.Finowscath:BAAANQAECgMIAwAAAA==.Firequencher:BAABNQAECn8XAAIhAAgKdRmoMwBGAgAhAAgKdRmoMwBGAgAAAA==.Fistacuffs:BAAANQAECgEIAQAAAA==.Fistdoc:BAAANQAECgcIDwAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQADCgcIGgAAAA==.Fié:BAAANQADCggIIgABNQAECgkJPwAYALkcAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECn83AAIjAAkKixPWKgBHAgAjAAkKixPWKgBHAgABNQAECgkJPwAYALkcAA==.Foxknight:BAAANQADCgQIBAABNQAECgkJPwAYALkcAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCgUICgABNQAECgcIGQAGAPcSAA==.',
Fr='Frederick:BAAANQAECggIAQAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECn8fAAIBAAgK0R61KADDAgABAAgK0R61KADDAgAAAA==.Friendofbear:BAACNQAFFH8GAAIHAAMKhQzfGADvAAAHAAMKhQzfGADvAAA1AAQKfykAAgcACQqqGpk3AMECAAcACQqqGpk3AMECAAAA.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAAANQAECgUICAAAAA==.Fuzywuzzy:BAABNQAECn8VAAMGAAkKcyBTBgApAwAGAAkKcyBTBgApAwAfAAQK6A1DKADIAAAAAA==.Fuzzycoochy:BAAANQADCgMIAwAAAA==.Fuzzykuntz:BAAANQAECgYIEwAAAA==.',
Fw='Fwoom:BAAANQADCgUIBQAAAA==.',
Fy='Fynsdood:BAABNQAECn8ZAAIGAAcK9xINIgCBAQAGAAcK9xINIgCBAQAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgcIGQAGAPcSAA==.',
Ga='Gabelock:BAACNQAFFH8VAAQMAAYKPhonCwC7AQAMAAUKOB8nCwC7AQAOAAEKUguYHgBLAAAkAAEKAACUEgA8AAA1AAQKfy8ABAwACQpkIlMkAPACAAwACAqNIlMkAPACAA4ABAouGV4wAAYBACQAAQoAAEItADsAAAAA.Gabemage:BAABNQAECn8XAAITAAgKTBHrsAAfAgATAAgKTBHrsAAfAgAAAA==.Gala:BAAANQAECgYIBwAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAABNQAECn8YAAIVAAgKChL3lwDuAQAVAAgKChL3lwDuAQAAAA==.',
Gi='Gigah:BAAANQAECggIEAAAAA==.Gingerbell:BAAANQABCggICAAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgQIBgAAAA==.Glutebruiser:BAAANQAECgEIAwABNQAECgcIEQAFAAAAAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAQAAAA==.Gouchh:BAAANQAECgEIAQAAAA==.',
Gr='Gravithel:BAAANQADCggIEQAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECn8XAAIIAAgKVyI/CwDOAgAIAAgKVyI/CwDOAgAAAA==.Grimspark:BAAANQABCgUIBQAAAA==.Grimtree:BAABNQAECn8kAAIkAAgKLRXoBwAWAgAkAAgKLRXoBwAWAgAAAA==.Grindor:BAAANQADCggIDAAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgQIBQAAAA==.Grumpydemon:BAABNQAECn8rAAIYAAkKcBlmGgCCAgAYAAkKcBlmGgCCAgAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Haldril:BAEANQAECgUIBwABNQAECgkJOwAVAMYjAA==.Halfskul:BAABNQAECn8YAAIXAAgK2gt8ZQB3AQAXAAgK2gt8ZQB3AQAAAA==.Halotic:BAAANQAECgIIAwAAAA==.Hashah:BAABNQAECn8aAAIPAAcKRyBiGwBqAgAPAAcKRyBiGwBqAgAAAA==.Hatefel:BAAANQAECgUIBQABNQAECgYIEQAFAAAAAA==.Havoke:BAAANQADCggIDwAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgkJLQAlAA4XAA==.Healyaass:BAAANQADCggIIgAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgAPAEcgAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgcIIAABAMsdAA==.Heyyboyy:BAABNQAECn8vAAMHAAkKhiSoCgCHAwAHAAkKhiSoCgCHAwAbAAEK8g0lhQA3AAAAAA==.',
Ho='Holyaefar:BAAANQAFFAIIAwAAAA==.Holymolydin:BAAANQADCgYIBgAAAA==.Holysab:BAAANQAECgUICwAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAABNQAECn8YAAMQAAgKkRV9SgBCAgAQAAgKkRV9SgBCAgAPAAEK7AIrggAlAAAAAA==.Holz:BAAANQAECgMIBgAAAA==.Horsetowater:BAAANQAECgQIBQABNQAECgkJKAABAGAYAA==.Hotsfordays:BAAANQAECgYIAgAAAA==.',
Hu='Hugoman:BAAANQAECgIIAgABNQAECggIIgAXAF0WAA==.Huni:BAABNQAECn8cAAIEAAkKsx7WJwDDAgAEAAkKsx7WJwDDAgAAAA==.Hunterj:BAAANQADCggICwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAAANQAECggIDwAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgQIBAABNQAECggICwAFAAAAAA==.',
Ib='Ibun:BAAANQAECgYICQAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECn8oAAIBAAkKYBg+LQCvAgABAAkKYBg+LQCvAgAAAA==.',
Ig='Igneus:BAACNQAFFH8QAAITAAUKcyJBEQDoAQATAAUKcyJBEQDoAQA1AAQKfycAAhMACQptJC0YAHQDABMACQptJC0YAHQDAAAA.Igriz:BAAANQADCggIKgAAAA==.',
Ii='Iillil:BAACNQAFFH8FAAIYAAMKdASVDgCxAAAYAAMKdASVDgCxAAA1AAQKfx8AAhgACQqQDL4rAOABABgACQqQDL4rAOABAAAA.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgIIAgAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQADCgMIBQAAAA==.Insidedoubt:BAAANQAECgYIDQAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUIBQAAAA==.',
It='Itsjeff:BAAANQAECgYIDgAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jaeyk:BAAANQAECggICAAAAA==.Jambonjay:BAABNQAECn8gAAICAAcKuwk8zABXAQACAAcKuwk8zABXAQABNQAECggIJQAHAJ0RAA==.Jananda:BAABNQAECn8WAAMiAAYKygSpagBTAAAiAAUKIgGpagBTAAAhAAYK5QArpgBIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jaywaz:BAAANQAECgUIBQAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.Jckjckjckjck:BAAANQAECgcIDgAAAA==.',
Je='Jearn:BAAANQADCgEIAQAAAA==.Jermagedupri:BAACNQAFFH8PAAITAAUKTRVXHwCFAQATAAUKTRVXHwCFAQA1AAQKfzEAAhMACQqzIfY3ABgDABMACQqzIfY3ABgDAAAA.Jessupy:BAABNQAECn8dAAIjAAgKvBjUKABVAgAjAAgKvBjUKABVAgAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQADCgYIBgAAAA==.Jezliu:BAAANQADCgYIBgAAAA==.',
Jh='Jhene:BAAANQAECgUIBgABNQAECggICgAFAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAAANQAECgYICwAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAAANQAECgcIEAAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalrendion:BAAANQADCgMIAwABNQAECgcIEgAFAAAAAA==.Kalru:BAAANQAECgEIAQAAAA==.Kalzok:BAEANQAECgEIAQABNQAECgkJOwAVAMYjAA==.Karaillyonna:BAAANQAECgcICQAAAA==.Karasu:BAAANQAECgMIBAAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAAANQAECgUIDQAAAA==.Kayho:BAAANQAECgUJBwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAABNQAECn8oAAMIAAkK2yN8BABdAwAIAAkK2yN8BABdAwAgAAUKuAR7UQCnAAAAAA==.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAABNQAECn8WAAIXAAgKpAyOXwCNAQAXAAgKpAyOXwCNAQAAAA==.Killamanjoro:BAABNQAECn8cAAICAAgKxBnEegAkAgACAAgKxBnEegAkAgAAAA==.Kimchiwar:BAAANQAECgYIDQAAAA==.Kirasha:BAAANQAECgIIAwAAAA==.Kitak:BAAANQAECgcIEgAAAA==.Kitchenbound:BAAANQAECgcIEwAAAA==.Kittychan:BAABNQAECn8iAAIXAAgKXRauOwAwAgAXAAgKXRauOwAwAgAAAA==.',
Kl='Klaacus:BAABNQAECn8xAAMYAAkKHhyGCwAkAwAYAAkKHhyGCwAkAwAjAAEKnhHsjAA9AAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUICwAAAA==.',
Ko='Kodomo:BAAANQADCgYIBgAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQAFFAEIAQAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECn8eAAMPAAkKpQ55JQAAAgAPAAkKpQ55JQAAAgARAAEKXxLQJwA0AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECn8aAAImAAkKDyH2BAA+AwAmAAkKDyH2BAA+AwABNQAECgkJOwAVAMYjAA==.',
La='Lakshmi:BAAANQAECgcIEwABNQAECgcIIAABAMsdAA==.Laradin:BAAANQADCgEJAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgQIBAAAAA==.Lavagrip:BAABNQAECn8YAAMVAAUK4A4nDwH/AAAVAAUK4A4nDwH/AAAUAAEKAAB1bwAvAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFH8NAAMHAAUKayMyBQD+AQAHAAUKayMyBQD+AQAbAAEKvh2KIQBMAAA1AAQKfzwAAwcACQqUJnQEAMMDAAcACQqUJnQEAMMDABsABwqJI3QTAMQCAAAA.Letmehealu:BAABNQAECn8UAAIQAAgKtwoMeACuAQAQAAgKtwoMeACuAQAAAA==.Lewsky:BAAANQAECgMIBgABNQAFFAMIBQAVAN4LAA==.',
Li='Lichtghost:BAAANQADCggIDAAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIGwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECn8qAAISAAgKxRgiKABLAgASAAgKxRgiKABLAgAAAA==.Liondori:BAAANQADCgYIBgAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECggIEAAAAA==.',
Lm='Lmj:BAAANQAECgIIBgAAAA==.',
Lo='Lockbox:BAABNQAECn8tAAMMAAkK0yIKBwCUAwAMAAkK0yIKBwCUAwAOAAMKFSFiLwALAQAAAA==.Lokmar:BAAANQAECgYICgAAAA==.Loomin:BAABNQAECn82AAMTAAkKhyFGLAA2AwATAAkKlR5GLAA2AwAeAAUK0hDYHAAFAQAAAA==.',
Lu='Lucatia:BAABNQAECn8mAAIYAAkKvRxwDgAAAwAYAAkKvRxwDgAAAwAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgcICQAFAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICQAAAA==.',
['Lä']='Lädyæk:BAAANQAECgcIEwAAAA==.',
Ma='Maekyss:BAAANQAECgcIEgAAAA==.Magezu:BAAANQAECgYIDgAAAA==.Maggarak:BAAANQAECgYIEgAAAA==.Magimagi:BAAANQAECgEIAQAAAA==.Magixstraza:BAABNQAECn8oAAITAAkKzRiLdQCSAgATAAkKzRiLdQCSAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBQAAAA==.Malthoryn:BAAANQAECgIIAgAAAA==.Malzel:BAAANQAECggIEAAAAA==.Mamasan:BAAANQAECgcIDAAAAA==.Mamor:BAAANQAECgUICwAAAA==.Maphra:BAAANQAECgUIBwAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQIBQAAAA==.Mazethak:BAAANQADCgYIBgAAAA==.',
Md='Mdeow:BAAANQADCgYICgAAAA==.',
Me='Mechabull:BAAANQABCgIIAgAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQAECgYIBgAAAA==.Melianthal:BAAANQAECgEIAQAAAA==.Melodí:BAAANQADCggICAABNQAECgkJKAAJAEgcAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgMIBAAAAA==.',
Mi='Miakoda:BAAANQADCgQIBAABNQAECgYIBQAFAAAAAA==.Micromortis:BAAANQAECgQIBAABNQAECgcIDwAFAAAAAA==.Mikuu:BAAANQAECgQICAAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECgYIDQAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAAANQAECgcIEwAAAA==.Mitufu:BAAANQAECgIIBQAAAA==.',
Mm='Mmeow:BAAANQADCggICwAAAA==.',
Mo='Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECn8/AAMYAAkKuRzwDwDwAgAYAAkKuRzwDwDwAgAjAAEKAg4EkAA2AAAAAA==.Morgul:BAAANQAECggIEAAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Moroton:BAAANQADCgQIBAABNQAECgUICwAFAAAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.',
Ms='Mseow:BAAANQADCggIGAAAAA==.',
Mu='Mudbutbrooks:BAABNQAECn8ZAAMbAAYKgxEsPQBkAQAbAAYKgxEsPQBkAQAaAAEKyQN4FAAoAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgkJKAABAGAYAA==.Muller:BAABNQAECn8gAAIVAAgKbxEzlAD3AQAVAAgKbxEzlAD3AQAAAA==.',
Mv='Mveow:BAAANQADCgYICAAAAA==.',
Mw='Mweow:BAAANQADCgYIEQAAAA==.',
Mx='Mxeow:BAAANQADCgQICAAAAA==.',
My='Mynnu:BAAANQAECgUIEAAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Mz='Mzeow:BAAANQADCgYIBgAAAA==.',
Na='Nautprepared:BAAANQAECgUIDQAAAA==.',
Ne='Necrodancer:BAAANQAECggJAgAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Nefetiree:BAAANQADCgQIBAAAAA==.Neildasstysn:BAAANQAECgYICQABNQAECggICAAFAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCgcIIgAAAA==.',
Ni='Nickeld:BAABNQAECn8eAAITAAgKBxwlcwCXAgATAAgKBxwlcwCXAgAAAA==.Nickhy:BAAANQAECgUIDQAAAA==.Nietherme:BAABNQAECn8eAAIVAAkKIg9JlQD0AQAVAAkKIg9JlQD0AQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nihildicits:BAAANQAECgEIAQAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgcIFwADAOYfAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQAECgQIBAABNQAECggIIgAXAF0WAA==.Nolife:BAAANQADCgQIBAAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.Noxis:BAAANQAECggICAAAAA==.',
Ny='Nyagosa:BAABNQAECn8XAAIQAAgKlxFLbQDSAQAQAAgKlxFLbQDSAQAAAA==.Nyalore:BAAANQAECgcIEgAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAQAAAA==.',
Og='Ogyaii:BAAANQADCgQIBAAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIAQAAAA==.',
Op='Optamus:BAAANQABCgMIAwAAAA==.',
Or='Oraedia:BAABNQAECn9GAAIBAAkKQh5+FgAiAwABAAkKQh5+FgAiAwAAAA==.Oralen:BAACNQAFFH8HAAIBAAQKsxeKEABUAQABAAQKsxeKEABUAQA1AAQKfygAAwEACQrJIlEKAHUDAAEACQrJIlEKAHUDABUAAgptDyFwAWcAAAAA.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECn8ZAAICAAkKKQ46lQDjAQACAAkKKQ46lQDjAQAAAA==.',
Ov='Overloader:BAABNQAECn8kAAIjAAkKPB8pFAD5AgAjAAkKPB8pFAD5AgAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Palahang:BAAANQAECgEIAQAAAA==.Pallyaxe:BAAANQAECgUICwABNQAECggILAATAPkYAA==.Pallygank:BAAANQADCgEIAQAAAA==.Pandawannabe:BAAANQAECgcICgAAAA==.Pandussi:BAABNQAECn8aAAIgAAkKxhP4IwACAgAgAAkKxhP4IwACAgAAAA==.Paneer:BAABNQAECn8cAAIHAAkKGiKWCwCAAwAHAAkKGiKWCwCAAwAAAA==.Paninus:BAAANQAECgEIAQAAAA==.Papabair:BAAANQAECgcICQABNQAECgcIDwAFAAAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgIIAQAAAA==.Perfectplex:BAAANQABCgUIBQAAAA==.Peruano:BAABNQAECn8mAAIOAAkKIhXlCABsAgAOAAkKIhXlCABsAgAAAA==.Petforheals:BAAANQAECgUICwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECgcICgAFAAAAAA==.',
Pi='Pietastegood:BAABNQAECn8pAAICAAkKwiP5CACrAwACAAkKwiP5CACrAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYJBgABNQAECggICgAFAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECgcIDwAFAAAAAA==.Pitchblack:BAAANQAECggIEgAAAA==.',
Po='Pocahöntas:BAAANQAECgQIBAAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAABNQAECn8yAAImAAkKdiDiBABBAwAmAAkKdiDiBABBAwAAAA==.Poordemon:BAAANQADCgUIBQABNQAECggIIwAXAIcJAA==.Popehealz:BAAANQADCgYIAgAAAA==.Pownds:BAAANQAECgQIBAAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAABNQAFFH8FAAIQAAUK7xONEACJAQAQAAUK7xONEACJAQAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAQABNQAECgcIGwAGANUOAA==.Pryor:BAAANQAECgUIBQAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGwAGANUOAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGwAGANUOAA==.Prøntø:BAABNQAECn8bAAMGAAcK1Q5tJgBdAQAGAAcK1Q5tJgBdAQAfAAIK3QODOgBJAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECgkJKgACALEfAA==.Punchbugman:BAAANQADCggIDAAAAA==.Puritos:BAAANQAECgIIAgAAAA==.Pustain:BAAANQABCggICgAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECgUIBwAFAAAAAA==.Pyrista:BAABNQAECn8bAAIHAAgK6RcKSQCPAgAHAAgK6RcKSQCPAgAAAA==.',
Qd='Qdonis:BAAANQADCgMIAwABNQAECgkJMQAYAB4cAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgEIAQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECn8jAAIjAAgKOxDANwDvAQAjAAgKOxDANwDvAQAAAA==.Radilas:BAAANQABCgIIAgAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECgkJKQACAMIjAA==.Raendarth:BAAANQAECgUIDgAAAA==.Rageth:BAABNQAECn8aAAIKAAgKMQ89IADQAQAKAAgKMQ89IADQAQAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAFFAIIBQASAKkYAA==.Rakalaag:BAEANQAECgQIBgAAAA==.Rakath:BAAANQAECgQICwAAAA==.Ramidus:BAAANQAECgQIBgAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIDQAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECn8qAAICAAkKsR8PLAAJAwACAAkKsR8PLAAJAwAAAA==.Redlands:BAAANQADCgQIBAAAAA==.Redredwine:BAAANQADCggICAAAAA==.Refractory:BAAANQAECgUIBgAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAUIFgANANkdAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAABNQAECn8aAAIVAAgKhxBkmgDpAQAVAAgKhxBkmgDpAQAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBQABNQAFFAIIBQASAKkYAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECn8gAAIDAAkKRxqbLwC6AgADAAkKRxqbLwC6AgAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQADCggIDgAFAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQADCgQIBAAAAA==.',
Ro='Rockabye:BAABNQAECn8hAAIPAAgKFR0uFQC1AgAPAAgKFR0uFQC1AgAAAA==.Rokar:BAAANQAECgEIAQAAAA==.Roraalionnu:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.Rosannas:BAAANQAECgIIAgABNQAFFAIIBQASAKkYAA==.Rosi:BAAANQADCggICAAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFH8NAAMmAAQKshG2AwAzAQAmAAQKUwq2AwAzAQADAAMKshEhGQD0AAA1AAQKfzMAAwMACQoaGE9HAFYCAAMACQqKFU9HAFYCACYABwoEEKsbAKQBAAAA.Ruibash:BAEBNQAECn87AAIVAAkKxiNfEACHAwAVAAkKxiNfEACHAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Runebladé:BAABNQAECn8YAAIXAAgKXhn/PAApAgAXAAgKXhn/PAApAgAAAA==.',
Ry='Ryuu:BAAANQADCggIDAAAAA==.Ryuuzen:BAAANQAECgUIBwAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQADCgEIAQAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAFAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAQAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAFAAAAAA==.Sakuraa:BAABNQAECn8lAAMQAAkKHw4zVwAZAgAQAAkKHw4zVwAZAgARAAMKLQGxIwBKAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAQAAAA==.Savaged:BAAANQADCgcIDAABNQAECgkJMgAXAH4XAA==.Savajed:BAABNQAECn8yAAMXAAkKfhdxPgAiAgAXAAgKLhhxPgAiAgAcAAkKxA+4OADsAQAAAA==.Savaragon:BAAANQADCgcIEwABNQAECgkJMgAXAH4XAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scallywagg:BAAANQAECgQIBgAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgEIAQAAAA==.',
Se='Searcomic:BAAANQAECgcIDwAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECn8tAAMlAAkKDhceBgBuAgAlAAkKDhceBgBuAgALAAMKpQdvLwCbAAAAAA==.Selendas:BAAANQADCgcIDQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECn8sAAMGAAkK3iM2AgCrAwAGAAkK3iM2AgCrAwAfAAEKAACIRAAtAAAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgYIDQABNQAECgEIAQAFAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgUICAAAAA==.Shameless:BAAANQAECgYICgAAAA==.Shamwów:BAAANQAECgcIEgAAAA==.Sharco:BAABNQAECn8iAAMeAAgKuxjlDQDNAQAeAAYKpR/lDQDNAQATAAcK6AxB8ACnAQAAAA==.Sharkbites:BAAANQAECgUICQAAAA==.Shawarmafury:BAACNQAFFH8KAAIHAAUKWyAECADFAQAHAAUKWyAECADFAQA1AAQKfy0AAgcACQrmJmUCAN8DAAcACQrmJmUCAN8DAAAA.Shaydens:BAAANQADCgIIAgAAAA==.Sherrizzahh:BAAANQADCgEIAQAAAA==.Shettani:BAAANQABCgYJCQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockrasta:BAAANQAECgQIBQABNQAECgkJLQAeAHohAA==.Shooshmael:BAABNQAECn8cAAIDAAgKKxdlWgAQAgADAAgKKxdlWgAQAgAAAA==.Shozo:BAAANQADCgUICAABNQAECgkJLAAGAN4jAA==.Shujáa:BAAANQAECgYIBwAAAA==.Shælynne:BAAANQABCgIIAgABNQAECgkJPwAYALkcAA==.Shékinah:BAACNQAFFH8HAAIhAAMK1gEOHwCWAAAhAAMK1gEOHwCWAAA1AAQKfy0AAiEACQrOELs8AAwCACEACQrOELs8AAwCAAAA.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIAwAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAUIFgANANkdAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAFAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECggIEAAFAAAAAA==.Skorpekh:BAABNQAECn8ZAAIHAAgKSQbargCiAQAHAAgKSQbargCiAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECn8cAAIiAAgKWR8DEwCyAgAiAAgKWR8DEwCyAgAAAA==.Sloppyspikes:BAAANQAECgcIEgAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECn8sAAICAAgKSx2YVgCEAgACAAgKSx2YVgCEAgABNQAECgkJNwAHAMQjAA==.Smidgenn:BAAANQADCgcIEQAAAA==.Smokyblast:BAAANQAECgYIEAAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECn80AAITAAgKmAT6BAGBAQATAAgKmAT6BAGBAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECn8cAAMgAAcKCg+GMQCGAQAgAAcKCg+GMQCGAQAJAAEK7g7uMAAzAAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIDQAAAA==.',
Sp='Sparowprince:BAACNQAFFH8MAAIVAAUK/hZJCgCgAQAVAAUK/hZJCgCgAQA1AAQKfzsAAhUACQr+I0MTAHgDABUACQr+I0MTAHgDAAAA.Spaspanda:BAAANQAECgIIAgABNQAECgcICgAFAAAAAA==.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAFAAAAAA==.Spectraleye:BAAANQAECgcIDwAAAA==.Sproocherlou:BAABNQAECn8nAAIVAAkKgxsTMwD9AgAVAAkKgxsTMwD9AgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAAANQAECgcIEQAAAA==.Steezya:BAAANQAECgUIEwAAAA==.Stegulos:BAAANQABCgIIAgAAAA==.Stellarum:BAAANQAECgMIAwAAAA==.Stonedemon:BAAANQAECgcICAABNQAFFAUIDAAVAP4WAA==.Stormsy:BAAANQAECgQIBgABNQAECggIFwAQAL8OAA==.Stormykitty:BAABNQAECn8XAAIQAAgKvw6KcgDAAQAQAAgKvw6KcgDAAQAAAA==.Strauch:BAAANQADCgcIHAAAAA==.Striderdh:BAAANQABCggIEQAAAA==.Strongwoman:BAAANQAECgQIEAAAAA==.Sturtza:BAACNQAFFH8HAAIHAAIKQg7EJQCcAAAHAAIKQg7EJQCcAAA1AAQKfzoAAgcACQqlI2UGAKsDAAcACQqlI2UGAKsDAAAA.Sturtzam:BAAANQADCgUJBQABNQAFFAIIBwAHAEIOAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sunbear:BAAANQADCggIDwAAAA==.Susak:BAAANQAECgQIBAABNQAECggIEgAFAAAAAA==.Suun:BAABNQAECn8qAAIVAAkKqB3VOwDgAgAVAAkKqB3VOwDgAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Sweetysnail:BAAANQAECgQICAAAAA==.Swoley:BAAANQAECggIEQAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taanua:BAAANQAECgEIAQAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECn8gAAIeAAkKFwtADgDFAQAeAAkKFwtADgDFAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAABNQAECn8XAAIBAAUKPBH8rQAgAQABAAUKPBH8rQAgAQAAAA==.Talisaie:BAAANQAECgcIDwABNQAFFAUIDwAjAPAgAA==.Tanisatharae:BAAANQADCgYIDgABNQAECgUIBwAFAAAAAA==.Tarahly:BAAANQAECgYIBgABNQAECggIGwABADYgAA==.Tarahse:BAAANQADCgIIAgABNQAECggIGwABADYgAA==.Taron:BAAANQAECgUIEgAAAA==.Tart:BAACNQAFFH8FAAMDAAMKyw7LIwCaAAADAAIKyw7LIwCaAAAEAAEKLwARNAAXAAA1AAQKfxkAAgMACQp1ELNaAA8CAAMACQp1ELNaAA8CAAAA.',
Te='Techmaestrov:BAAANQADCggICAAAAA==.Tedjones:BAAANQAECgUIDAAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thandana:BAAANQAECgEIAQAAAA==.Thehumanatee:BAABNQAECn8mAAIhAAgKmRkOLQBxAgAhAAgKmRkOLQBxAgAAAA==.Theroach:BAAANQAECgQICAAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICgAFAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQAECgUIBgAAAA==.Thiqq:BAAANQADCggICAAAAA==.Threlindrier:BAAANQAECgIIAgAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAAANQAECgYIEgAAAA==.Thyphlo:BAAANQAECgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECggICAAAAA==.Tiltedup:BAABNQAECn8eAAITAAkKWBH7twASAgATAAkKWBH7twASAgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCggIEAABNQAECggIFwAQAL8OAA==.Tirich:BAAANQADCggICAABNQAFFAUIFgANANkdAA==.Titaintium:BAAANQAECgQIBAABNQAECgkJJAAjADwfAA==.',
To='Toshi:BAABNQAECn8cAAIMAAgKlQgWpACHAQAMAAgKlQgWpACHAQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECggIJAAkAC0VAA==.Touchyouup:BAAANQAECgEIAQAAAA==.',
Tr='Trilguth:BAAANQADCgYIBgAAAA==.Truckkun:BAAANQAECgIIAgAAAA==.Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAgAAAA==.',
Tu='Tulark:BAAANQABCgYIBgAAAA==.Tullydin:BAABNQAECn8mAAMUAAkKlwldMgBLAQAVAAgKRQj/2gBeAQAUAAgKNQhdMgBLAQAAAA==.Tullyy:BAAANQAECgQICgAAAA==.Tums:BAABNQAECn8iAAMNAAkKzRqGFwAgAgANAAcKUhuGFwAgAgASAAcKwBXLNgD3AQAAAA==.',
Tw='Twirls:BAABNQAECn8YAAIJAAgK7RmaDQAeAgAJAAgK7RmaDQAeAgAAAA==.Twistoffate:BAAANQAECgQICgAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
['Tä']='Tälos:BAAANQADCgUIBQABNQADCggIDQAFAAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAAANQAECgQICwAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECn8eAAMVAAgKsx4EeQA2AgAVAAgKsx4EeQA2AgAUAAQKkQ0cTgCrAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAAANQAECgcIDwAAAA==.',
Va='Valgorr:BAAANQAECgYICwAAAA==.Valvalon:BAABNQAECn8kAAIeAAkKsR1iBADlAgAeAAkKsR1iBADlAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.Vanessia:BAAANQADCgQIBAAAAA==.Varhaitof:BAAANQADCggICAAAAA==.',
Ve='Veelaria:BAABNQAECn8fAAIUAAgKdw+xKACTAQAUAAgKdw+xKACTAQAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Verahardyr:BAAANQADCgQIBAAAAA==.Veravulp:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQIBwAAAA==.',
Vh='Vhelithiana:BAAANQADCggIHwAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECgkJMgAXAH4XAA==.Vicalaus:BAABNQAECn8nAAIcAAgK4hsPKQBLAgAcAAgK4hsPKQBLAgABNQAECgkJMQAYAB4cAA==.View:BAABNQAECn8ZAAIEAAkKAxQ2VQAPAgAEAAkKAxQ2VQAPAgAAAA==.Vikcy:BAAANQAECgIIAwAAAA==.Vikcyholy:BAAANQADCgMIAwAAAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitamind:BAAANQAECgUIBQAAAA==.Vitros:BAAANQADCgcIBwABNQAECgkJJAAPAE4eAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgkJFQAGAHMgAA==.Voidwitch:BAAANQAECgYIEQAAAA==.Volstagg:BAAANQADCgMIAwAAAA==.',
Vr='Vrakken:BAABNQAECn8ZAAIcAAgKTBNQNQAAAgAcAAgKTBNQNQAAAgAAAA==.',
Vu='Vududonkey:BAAANQAECgMIAwABNQAECgcIEgAFAAAAAA==.',
Vy='Vyndenus:BAABNQAECn8yAAIQAAkKyRyFGAASAwAQAAkKyRyFGAASAwAAAA==.',
Wa='Warriorluv:BAAANQADCgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECgcICQAAAA==.Welor:BAAANQAECgUIBQAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Wheremytotem:BAAANQADCggIDQABNQAECgkJKAABAGAYAA==.Whitbone:BAAANQADCgQIBAAAAA==.Wholephister:BAAANQAECgEIAQABNQAECgUIDAAFAAAAAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wiglock:BAAANQAECgEIAgAAAA==.Wigpetval:BAABNQAECn8lAAMHAAgKnRGIlwDVAQAHAAgKURGIlwDVAQAbAAIKrRXeZwCIAAAAAA==.Wiidge:BAABNQAECn8cAAIkAAcKsgv9CwCjAQAkAAcKsgv9CwCjAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBQAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECn8XAAIhAAYK+xiCRwDKAQAhAAYK+xiCRwDKAQAAAA==.Wolfchan:BAAANQAECgQICAAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgkJMQAYAB4cAA==.Worldcrafter:BAAANQAECgUIDgAAAA==.Worldender:BAAANQAECgYICQAAAA==.',
Wr='Wrathofdawn:BAAANQAECgIIAwAAAA==.Wreckross:BAAANQABCgUIBQAAAA==.',
Xa='Xantry:BAACNQAFFH8FAAIVAAMK3gsrGwDJAAAVAAMK3gsrGwDJAAA1AAQKfxwAAhUACQr+ImU3AO8CABUACQr+ImU3AO8CAAAA.',
Xe='Xeviscerated:BAAANQADCgEIAQAAAA==.',
Xm='Xmen:BAAANQAFFAIIAQAAAA==.',
Xs='Xslight:BAAANQAECgEIAQABNQADCggIDgAFAAAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgMIAwAAAA==.',
Ye='Yeastybush:BAABNQAECn8jAAIEAAkKgB2EIwDWAgAEAAkKgB2EIwDWAgAAAA==.',
Yi='Yinsen:BAAANQADCggICAAAAA==.',
Ys='Yseera:BAAANQAECgIIAgAAAA==.Yseeraa:BAAANQAECgEIAQAAAA==.',
Za='Zalatoes:BAAANQADCggIIQAAAA==.Zarathea:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQADCggJDgAAAA==.Zimms:BAABNQAECn8lAAIgAAkKRh7dDgDyAgAgAAkKRh7dDgDyAgAAAA==.',
Zo='Zoeyredbird:BAAANQAECggIEAAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.Zwhittytv:BAAANQAECggIDQAAAA==.',
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
