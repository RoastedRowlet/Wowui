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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Warlock-Demonology','Rogue-Subtlety','Warlock-Destruction','Priest-Shadow','Priest-Holy','Priest-Discipline','Rogue-Assassination','Mage-Arcane','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','Warrior-Protection','Mage-Frost','Druid-Feral','Monk-Windwalker','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Warlock-Affliction','Evoker-Augmentation','Shaman-Enhancement','Evoker-Devastation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aamara:BAABNQAECoEZAAIBAAYK7B0hUAALAgABAAYK7B0hUAALAgABNQAECgcIFAACALcbAA==.',
Ab='Aboyton:BAAANQADCgYIEAAAAA==.',
Ad='Adarksoul:BAAANQAECgEIBAAAAA==.Adhpally:BAAANQADCgIIAgABNQAFFAUIBwADAPEWAA==.Adorara:BAAANQADCgEIAQAAAA==.',
Ae='Aefarshammy:BAABNQAECoEhAAMEAAkK8CR+NwByAgAEAAYK3SR+NwByAgAFAAkKxhPHRwAXAgABNQAFFAEIAQAGAAAAAA==.Aelistiah:BAAANQAECgEIAwAAAA==.Aerithorn:BAABNQAECoEcAAIHAAgKCCEbBwDnAgAHAAgKCCEbBwDnAgAAAA==.',
Ah='Aheck:BAAANQADCgMJAwABNQAECggIHgACAG4YAA==.Ahleya:BAAANQAECgYIDAAAAA==.Ahlonaa:BAAANQADCggJDQAAAA==.',
Ai='Airundies:BAAANQADCgcIBwABNQAECgQICgAGAAAAAA==.',
Ak='Akoris:BAAANQAECgIIBAABNQAECgkJGgAIANYQAA==.Akorys:BAABNQAECoEaAAMIAAkK1hAnFgDrAQAIAAkK1hAnFgDrAQAJAAEK1Qc4MAAjAAAAAA==.',
Al='Albyno:BAACNQAFFIEKAAIKAAUKbQyVCQBsAQAKAAUKbQyVCQBsAQA1AAQKgSAAAgoACQpeGSwNAMECAAoACQpeGSwNAMECAAAA.Algebrah:BAAANQAECgEIAQAAAA==.',
Am='Amara:BAAANQADCgYIGwAAAA==.Ambitionz:BAAANQAECgEIAQAAAA==.Ameadynnie:BAAANQABCgIIAgAAAA==.',
An='Anchint:BAABNQAECoEaAAILAAUKFwMr7QDAAAALAAUKFwMr7QDAAAAAAA==.Ancksunamun:BAAANQADCgYICAAAAA==.Andromedia:BAAANQADCgYIBgABNQAECgcIFAACALcbAA==.Anicarcia:BAAANQADCgQIBAAAAA==.Anuurg:BAAANQADCgIIAgAAAA==.Anwir:BAACNQAFFIERAAIMAAUK7BtrBADVAQAMAAUK7BtrBADVAQA1AAQKgR0AAgwACQqbIOoEADkDAAwACQqbIOoEADkDAAAA.',
Ap='Aperture:BAAANQADCgcIDQAAAA==.',
Aq='Aquua:BAABNQAECoEhAAIEAAgKMBq6OQBoAgAEAAgKMBq6OQBoAgAAAA==.',
Ar='Araelen:BAAANQAECgcIDgAAAA==.Arcticdps:BAABNQAECoEqAAMLAAkK8xhzMwChAgALAAkK8xhzMwChAgANAAEKVxYPaABFAAAAAA==.Ariastel:BAAANQABCgIIAgAAAA==.Ariell:BAABNQAECoEbAAQOAAgKmheQMQBtAQAOAAYKUROQMQBtAQAPAAYKHg3SggBVAQAQAAYKaQ0KDgA6AQAAAA==.Ariestar:BAAANQAECgUICAAAAA==.Ariiel:BAAANQADCggICQABNQAECggIGwAOAJoXAA==.Arthimas:BAAANQAECgIJAgAAAA==.Arthurdent:BAAANQAECgMIBQAAAA==.',
As='Ascendance:BAAANQAECggJBwAAAA==.Ashelash:BAAANQAECgUIDgAAAA==.Asidize:BAAANQAECgUICAAAAA==.Aslor:BAABNQAECoEcAAILAAcKrBkoWgAnAgALAAcKrBkoWgAnAgAAAA==.Aspenoa:BAAANQADCggICAAAAA==.Asralia:BAAANQADCgYICQAAAA==.',
At='Athalia:BAABNQAECoEqAAIRAAkK8iE2BgBaAwARAAkK8iE2BgBaAwAAAA==.Atlaswolfe:BAAANQAECgcIBwAAAA==.',
Au='Audi:BAAANQADCgQIDAAAAA==.Aug:BAAANQAECgYIDgAAAA==.Autofellate:BAAANQADCgIIAgAAAA==.',
Av='Avaldra:BAAANQAECgEIAQAAAA==.Avery:BAAANQAECgEIAQAAAA==.Avex:BAABNQAECoEeAAICAAgKbhjWSwBjAgACAAgKbhjWSwBjAgAAAA==.',
Ax='Axemage:BAABNQAECoEoAAISAAgK0Rn+dQB8AgASAAgK0Rn+dQB8AgAAAA==.Axeom:BAABNQAECoEwAAIFAAgKfxzfKgCUAgAFAAgKfxzfKgCUAgAAAA==.Axeshammy:BAAANQAECgMIBAABNQAECggIKAASANEZAA==.',
Az='Azmodan:BAAANQAECgEIAQAAAA==.Azzith:BAAANQAFFAEIAQAAAA==.',
Ba='Bahgeye:BAAANQADCgUIBQAAAA==.Bajaladin:BAAANQAECgYIEAAAAA==.Barometer:BAAANQAECgUIDgAAAA==.Bast:BAAANQADCggICwABNQAECgcIEgAGAAAAAA==.Baxa:BAAANQAECggICAAAAA==.Baylee:BAABNQAECoEXAAISAAYKcQTFNQEOAQASAAYKcQTFNQEOAQAAAA==.',
Bb='Bbartemis:BAAANQAECgYIEgAAAA==.',
Bc='Bchamp:BAAANQADCgQIBAAAAA==.',
Be='Bearaqobama:BAAANQADCgYIBgAAAA==.Bearlyalivee:BAAANQAECgEIAwABNQAECgUIBwAGAAAAAA==.Bearvul:BAAANQABCgEIAQAAAA==.Beekerr:BAAANQADCgMIAwABNQAECggIHAAMANQcAA==.Begonemist:BAAANQADCgEIAQAAAA==.Belbroon:BAAANQADCgQIBAAAAA==.Beliele:BAAANQAECgQIBQAAAA==.Belzenlok:BAAANQAECgEIAQAAAA==.Benjohnbo:BAAANQAECgEIAQAAAA==.Benwins:BAAANQAECgUICgAAAA==.Bergamö:BAAANQADCgcICQABNQAECgMIBwAGAAAAAA==.Bernecessity:BAAANQAECgYIDAAAAA==.',
Bh='Bho:BAAANQADCgUICgAAAA==.',
Bi='Biffedit:BAAANQADCgcIBwAAAA==.Bigangus:BAAANQAECgIIAgAAAA==.Bigdj:BAAANQAECgEIAQAAAA==.Biom:BAABNQAECoEYAAQTAAYKYRjqmQC4AQATAAYK7BfqmQC4AQAUAAQKZRuiMwAcAQABAAMKISAsrAD8AAAAAA==.Bis:BAAANQADCgEJAgAAAA==.Biscuitbabe:BAAANQAECgYIEwAAAA==.Bisholoyd:BAAANQAECgUICgAAAA==.',
Bl='Blackgold:BAAANQADCgQIBAAAAA==.Blakely:BAAANQADCgIIAQAAAA==.Blastoise:BAABNQAECoEjAAMVAAgK2yBvFQDrAgAVAAcKtiRvFQDrAgAWAAYKgRDfdgAVAQAAAA==.Blckbrry:BAAANQAECgEIAQAAAA==.Blinktwice:BAAANQAECgEIBQAAAA==.Blizfishleg:BAAANQAECgQICgAAAA==.Bllur:BAAANQADCgIIAgAAAA==.Bloodroots:BAAANQAECgMICQAAAA==.Bluur:BAAANQADCgYIBgAAAA==.',
Bo='Bonehacker:BAAANQAECgEIAwAAAA==.Boombóx:BAAANQAECgQIBQABNQAECggIJwALAPAjAA==.Boostia:BAAANQADCgEIAQAAAA==.Borthos:BAABNQAECoEdAAIXAAgKCRsJFwCPAgAXAAgKCRsJFwCPAgAAAA==.Bowsback:BAAANQADCggIHwAAAA==.Bowyohead:BAAANQAECggIEwABNQAECgkJIgABAG8XAA==.',
Br='Bracydaboss:BAAANQADCgQIBAAAAA==.Brandoe:BAAANQAECgQICAAAAA==.Breece:BAAANQAECgIIBAAAAA==.Brickinkeys:BAAANQADCgYIDAABNQAECgcIFAACALcbAA==.Brightmare:BAAANQADCgYIDwAAAA==.Brusa:BAAANQADCgEJAQAAAA==.Brynnix:BAAANQADCgEIAQAAAA==.',
['Bà']='Bàne:BAABNQAECoEVAAIYAAcKeAbnDQBJAQAYAAcKeAbnDQBJAQAAAA==.',
Ca='Caadra:BAAANQADCgIIAgAAAA==.Caimie:BAAANQAECgIIAwAAAA==.Calfionn:BAAANQADCgIIAgAAAA==.Candez:BAAANQADCgUIBQAAAA==.Canroth:BAAANQAECgQIDAAAAA==.Cassiaan:BAAANQAECgIIAgAAAA==.Caylavibes:BAABNQAECoEhAAIPAAkKHxGSRgAtAgAPAAkKHxGSRgAtAgAAAA==.',
Ch='Chaviel:BAAANQAECggICwAAAA==.Cheetasista:BAAANQADCggIDgAAAA==.Cherry:BAAANQAECggIDQAAAA==.Chironn:BAABNQAECoEgAAIZAAgKPhuDAwCtAgAZAAgKPhuDAwCtAgAAAA==.Chonkerz:BAAANQAECgEIAQAAAA==.Chudlord:BAAANQAECgEIAgAAAA==.Chull:BAAANQADCgIIAgAAAA==.Chumbo:BAAANQAECgMIBAAAAA==.',
Ci='Cinderburn:BAAANQAECgQIBwAAAA==.Cinderkai:BAAANQAECgEIAgAAAA==.',
Cl='Clayshaper:BAAANQADCgYIDAAAAA==.Clohhe:BAAANQAECgEIBAAAAA==.Clohordyo:BAAANQAECgQIBAAAAA==.Clwnshoenrgy:BAAANQADCgYIBgAAAA==.',
Co='Combust:BAAANQAECgEIAgAAAA==.Comfychair:BAAANQAECggIDgAAAA==.Coowmoo:BAAANQAECgQIDQAAAA==.Cosmochopper:BAAANQAECgEIAQABNQAFFAIIAgAGAAAAAA==.Cosmonodder:BAAANQAECgYIBgABNQAFFAIIAgAGAAAAAA==.Cosmoshotter:BAAANQAFFAIIAgAAAA==.',
Cr='Craterstab:BAAANQADCgEIAQAAAA==.Cremebrule:BAAANQADCggIMgAAAA==.Critnyspears:BAAANQAECgIIBwAAAA==.Crushleaf:BAAANQADCggICwAAAA==.',
Cu='Cucubau:BAAANQADCgcICQAAAA==.',
Cy='Cyndra:BAAANQAECgMIBgAAAA==.',
Da='Dallthyrian:BAAANQADCgYIBgABNQAECgUICwAGAAAAAA==.Dalthyrian:BAAANQAECgYIEAABNQAECgUICwAGAAAAAA==.Dalthyriian:BAAANQAECgUICwAAAA==.Dalthyrrian:BAAANQAECgEJAQABNQAECgUICwAGAAAAAA==.Dalthyyrian:BAAANQAECgQIBQABNQAECgUICwAGAAAAAA==.Damii:BAAANQADCgUICQAAAA==.Danfarm:BAAANQADCgEIAQAAAA==.Dargonbref:BAAANQADCgUIAQABNQAECgYIEgAGAAAAAA==.Darjen:BAAANQAECgUICAAAAA==.Darkjestêr:BAAANQADCgUIBQAAAA==.Darksky:BAAANQAECgIIAgAAAA==.Daysfox:BAABNQAECoEZAAMaAAcKrwrCNAB8AQAaAAcKRArCNAB8AQACAAEKugwVLgFFAAAAAA==.Daysmonk:BAAANQADCgYIBgAAAA==.',
Dc='Dcash:BAAANQADCgIIAgAAAA==.',
De='Deadenside:BAAANQADCgQIBQAAAA==.Deadmountain:BAAANQADCgIIBAAAAA==.Deahtlyx:BAAANQADCgQIBAABNQAECgkJKAARAGIaAA==.Deathfang:BAAANQADCgUICgAAAA==.Deathlyy:BAABNQAECoEoAAMRAAkKYhrcFwCWAgARAAgKsRvcFwCWAgAMAAQKOwr1NQDnAAAAAA==.Deathmatch:BAAANQAECgIIAwAAAA==.Deathstone:BAABNQAECoEWAAMbAAgKrRcpJABCAgAbAAgKuhYpJABCAgAWAAMKuw8unACgAAABNQAFFAUIBwATAOUUAA==.Deathtress:BAAANQAECgcIEgAAAA==.Debbydowner:BAABNQAECoEWAAIDAAYKLQn1xAA7AQADAAYKLQn1xAA7AQAAAA==.Decado:BAAANQAECgcIEgAAAA==.Deemwins:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Deezenuts:BAAANQAECggIBwAAAA==.Degen:BAAANQAECgQIBwAAAA==.Dejevoid:BAAANQAECgcIDgAAAA==.Delidyr:BAAANQAECgIIAwAAAA==.Deliquium:BAAANQABCggICgAAAA==.Demonroo:BAAANQADCgEIAQAAAA==.Denimdan:BAEBNQAECoEnAAMcAAgKAxmjDAA+AgAcAAgKAxmjDAA+AgADAAMKnwbXCgGPAAAAAA==.Denwere:BAAANQADCgUICAAAAA==.Deww:BAABNQAECoEaAAMQAAkKlhc7BAB1AgAQAAgKQxg7BAB1AgAPAAYK4Bg0WgDjAQAAAA==.',
Dh='Dhawk:BAAANQADCggIFAAAAA==.Dhelilha:BAABNQAECoEcAAIUAAgKLglaLgBAAQAUAAgKLglaLgBAAQAAAA==.',
Di='Distance:BAAANQADCgIIAgAAAA==.',
Dk='Dkalliru:BAABNQAECoEhAAIVAAgKhh5KHAC0AgAVAAgKhh5KHAC0AgAAAA==.',
Do='Docdolittle:BAABNQAECoEsAAICAAkKdCJ1CgB5AwACAAkKdCJ1CgB5AwAAAA==.Docfreez:BAABNQAECoEoAAMdAAgK/CL2BQB/AgAdAAcKDx72BQB/AgASAAcKUB8liABUAgAAAA==.Docragosa:BAAANQAECgMIBAABNQAECgcICQAGAAAAAA==.Doctermoo:BAAANQAECgYICgAAAA==.Dogar:BAAANQAECgEIAQAAAA==.Doomhamer:BAAANQADCggICAABNQAECggIHQAXAAkbAA==.Doraemee:BAAANQAECgQIBgAAAA==.',
Dr='Drbaconbrgr:BAABNQAECoEVAAIPAAcK3RjYSQAhAgAPAAcK3RjYSQAhAgABNQAECgkJHgACAD0hAA==.Drbakedziti:BAAANQADCgYIBgABNQAECgkJHgACAD0hAA==.Drbaobuns:BAAANQAECgYIDAABNQAECgkJHgACAD0hAA==.Drcarrotcake:BAAANQAECgIIAgABNQAECgkJHgACAD0hAA==.Drcheeseball:BAAANQAECgYIEAABNQAECgkJHgACAD0hAA==.Dreggsalad:BAAANQAECgUIEAABNQAECgkJHgACAD0hAA==.Dreima:BAAANQAECgQIBgAAAA==.Dreist:BAAANQADCgIIAgAAAA==.Drfriedrice:BAAANQADCgEJAQABNQAECgkJHgACAD0hAA==.Drgatorwine:BAAANQAECgUIDwABNQAECgkJHgACAD0hAA==.Drhashbrowns:BAAANQAECgQIBgABNQAECgkJHgACAD0hAA==.Drkimchirice:BAABNQAECoEZAAIeAAgKlyPTBAATAwAeAAgKlyPTBAATAwABNQAECgkJHgACAD0hAA==.Drmacncheese:BAABNQAECoEVAAINAAUKUh+CEwDMAQANAAUKUh+CEwDMAQABNQAECgkJHgACAD0hAA==.Drpumpkinpie:BAAANQAECgYIEgABNQAECgkJHgACAD0hAA==.Drshephardpi:BAAANQADCggICgABNQAECgkJHgACAD0hAA==.Drshortbread:BAAANQAECgUICAABNQAECgkJHgACAD0hAA==.Druiddres:BAAANQAECgQIBgAAAA==.Druidussy:BAAANQAECgEIAQAAAA==.Drwontonsoup:BAABNQAECoEeAAICAAkKPSHZCwBuAwACAAkKPSHZCwBuAwAAAA==.',
Du='Dummythicc:BAAANQADCgYICAAAAA==.',
['Dö']='Dööku:BAAANQADCgYIBgAAAA==.',
Ei='Eighteen:BAABNQAECoEjAAIMAAkKlxwbCADsAgAMAAkKlxwbCADsAgAAAA==.',
Ek='Eksi:BAABNQAECoEVAAIfAAcKjxNBKACrAQAfAAcKjxNBKACrAQAAAA==.',
El='Elethe:BAAANQAECgIIAgABNQAFFAUIEQAMAOwbAA==.Elianx:BAAANQAECggIAQAAAA==.Ellebush:BAAANQADCgIIAgAAAA==.Elyrinna:BAAANQABCgQIBQAAAA==.Elzaine:BAAANQAECgMIBQAAAA==.',
Em='Embedded:BAAANQAECgYIEgAAAA==.Eme:BAAANQAECgIIAgAAAA==.Empress:BAABNQAECoEUAAIbAAcKnQs0RABrAQAbAAcKnQs0RABrAQAAAA==.',
En='Endear:BAAANQADCggIBgAAAA==.Energyz:BAAANQAECggIDAAAAA==.Enhanceme:BAAANQADCgQIBAABNQAECgEIAgAGAAAAAA==.Entrophi:BAAANQADCgMIAwAAAA==.',
Er='Erikaa:BAAANQAECgUICQAAAA==.Erisnyx:BAAANQADCgIIAgAAAA==.',
Es='Escoez:BAAANQADCgUIBQABNQAECgEIBAAGAAAAAA==.Esterelore:BAAANQADCgYIBgAAAA==.Estix:BAAANQAECgEIAgABNQAECggIDAAGAAAAAA==.',
Ex='Excruciator:BAABNQAECoEeAAMgAAgKCRKaRACyAQAgAAcKUhOaRACyAQAhAAIKtAfrWABwAAAAAA==.Exhumedraven:BAAANQAECgYICgAAAA==.',
Fa='Falloutz:BAAANQAECgIIAwAAAA==.Farahcanle:BAABNQAECoEnAAIHAAgKEw4dGwCHAQAHAAgKEw4dGwCHAQAAAA==.Farrock:BAABNQAECoEZAAIHAAcKqwpNIwA1AQAHAAcKqwpNIwA1AQAAAA==.Fawxette:BAAANQADCggICAABNQAECgkJNgAXAKoaAA==.',
Fe='Felanish:BAAANQAECgEIAgAAAA==.Felystia:BAAANQAECgQICgAAAA==.Fenra:BAAANQADCgcIDAAAAA==.Feorblarir:BAAANQAECgUICwAAAA==.Fernmister:BAAANQAECgIIAwAAAA==.',
Fi='Fieryfrost:BAAANQADCgYIBgABNQAECgYIEgAGAAAAAA==.Filledegel:BAAANQAECgQICQABNQAECgcICAAGAAAAAA==.Finowscath:BAAANQAECgMIBAAAAA==.Firequencher:BAABNQAECoEUAAIgAAgKJBqcLQBMAgAgAAgKJBqcLQBMAgAAAA==.Fistacuffs:BAAANQAECgIIBQAAAA==.Fistdoc:BAAANQAECgYICAABNQAECgcICQAGAAAAAA==.Fistícuffs:BAAANQADCggIGgAAAA==.Fizzroll:BAAANQADCgcIGgAAAA==.Fié:BAAANQADCggIGgABNQAECgkJNgAXAKoaAA==.',
Fl='Flais:BAAANQAECgIIAwAAAA==.Fleetwoodmac:BAAANQADCgYIBgAAAA==.',
Fo='Foxfel:BAABNQAECoEuAAIiAAgKQRTqLAAPAgAiAAgKQRTqLAAPAgABNQAECgkJNgAXAKoaAA==.Foxknight:BAAANQADCgQIBAABNQAECgkJNgAXAKoaAA==.Foxybag:BAAANQADCggICAAAAA==.Foxytotes:BAAANQADCgUICgABNQAECgYIEgAGAAAAAA==.',
Fr='Frederick:BAAANQAECggIBAAAAA==.Fredo:BAAANQADCgIIAgAAAA==.Friendlypal:BAABNQAECoEYAAIBAAcKvB6kNgBtAgABAAcKvB6kNgBtAgAAAA==.Friendofbear:BAABNQAECoEmAAICAAkK/hnNNwCgAgACAAkK/hnNNwCgAgAAAA==.Fromabove:BAAANQADCgYICQAAAA==.',
Fu='Furryfeet:BAAANQAECgUICQAAAA==.Fuzywuzzy:BAAANQAECgcIEgAAAA==.Fuzzykuntz:BAABNQAECoEVAAIWAAcKKgiNbQA4AQAWAAcKKgiNbQA4AQAAAA==.',
Fy='Fynsdood:BAAANQAECgYIEgAAAA==.Fynslane:BAAANQADCgQIBAABNQAECgYIEgAGAAAAAA==.',
Ga='Gabelock:BAACNQAFFIEPAAQLAAYKNBlNBwDIAQALAAUK3B1NBwDIAQANAAEK6wEpIABCAAAjAAEK3ASDDwA8AAA1AAQKgSwABAsACQoAI84cAPwCAAsACAoyI84cAPwCAA0ABAouGcMtAAoBACMAAQrmHHAoAD0AAAAA.Gabemage:BAAANQAECgcIEAAAAA==.Gala:BAAANQAECgUIBwAAAA==.Gasback:BAAANQADCgYICwAAAA==.',
Gh='Gherkins:BAAANQADCgYICgAAAA==.Ghostreveri:BAAANQAECgYIEQAAAA==.',
Gi='Gigah:BAAANQAECgcIDgAAAA==.Gingerbell:BAAANQABCggICAAAAA==.',
Gl='Glitsch:BAAANQADCgQIBAAAAA==.Glorpnotl:BAAANQADCgYIBgAAAA==.Gloziwitz:BAAANQAECgQIBwAAAA==.Glutebruiser:BAAANQAECgEICAABNQAECgcIFQALABAlAA==.',
Gn='Gnomedguerre:BAAANQADCgYIDQAAAA==.',
Go='Gooseshift:BAAANQAECgEIAgAAAA==.Gouchh:BAAANQAECgEIAgAAAA==.',
Gr='Gravithel:BAAANQADCgcIEAAAAA==.Graybøw:BAAANQADCggIDwAAAA==.Grayseer:BAABNQAECoEXAAIIAAgKVyIrCQDeAgAIAAgKVyIrCQDeAgAAAA==.Grimspark:BAAANQAECgEIAgAAAA==.Grimtree:BAABNQAECoEdAAIjAAgKxxAYBwANAgAjAAgKxxAYBwANAgAAAA==.Grindor:BAAANQAECgEIAQAAAA==.Grommel:BAAANQADCgYICAAAAA==.Grumblecane:BAAANQADCgIIAgAAAA==.Grumpstraza:BAAANQAECgQIBgAAAA==.Grumpydemon:BAABNQAECoEjAAIXAAkKNRONHQBKAgAXAAkKNRONHQBKAgAAAA==.Grymshot:BAAANQAECgQIBgAAAA==.',
Gw='Gwong:BAAANQADCgcIBwAAAA==.',
Ha='Hafchub:BAAANQAECgEIAwAAAA==.Haldril:BAEANQAECgUICAABNQAECgkJNAATAJkjAA==.Halfskul:BAABNQAECoEYAAIWAAgK4gwmXAB4AQAWAAgK4gwmXAB4AQAAAA==.Halotic:BAAANQAECgEIAQAAAA==.Hashah:BAABNQAECoEaAAIOAAcKHSA2FwB7AgAOAAcKHSA2FwB7AgAAAA==.Hatefel:BAAANQAECgUIBgABNQAECgUIDwAGAAAAAA==.Havoke:BAAANQADCggICAAAAA==.',
He='Healsgobrr:BAAANQADCgYICwABNQAECgkJKwAkAD0YAA==.Healyaass:BAAANQAECgEIAQAAAA==.Hecate:BAAANQADCgIIAgAAAA==.Helenfeller:BAAANQADCgEIBAAAAA==.Helgard:BAAANQADCgQIBAAAAA==.Hesha:BAAANQADCgQIBAABNQAECgcIGgAOAB0gAA==.Hexfu:BAAANQADCgMIAwAAAA==.Hexlexxia:BAAANQADCggIDwABNQAECgcIFAACALcbAA==.Heyyboyy:BAABNQAECoEmAAMCAAkKbCJiCQCCAwACAAkKbCJiCQCCAwAaAAEK8g3WdgA5AAAAAA==.',
Ho='Holyaefar:BAAANQAFFAEIAQAAAA==.Holymolydin:BAAANQADCgYIBgAAAA==.Holysab:BAAANQAECgQICQAAAA==.Holysock:BAAANQAECgUICAAAAA==.Holyyaii:BAAANQAECgcIEgAAAA==.Holz:BAAANQAECgIIAwAAAA==.Horsetowater:BAAANQAECgQIBAABNQAECgkJIgABAG8XAA==.',
Hu='Hugoman:BAAANQAECgEIAwABNQAECggIHAAWAE8WAA==.Huni:BAABNQAECoEcAAIFAAkKsx6fHwDOAgAFAAkKsx6fHwDOAgAAAA==.Hunterj:BAAANQADCggICwAAAA==.Huupa:BAAANQADCgYIBgAAAA==.',
Hy='Hydealyn:BAAANQADCggICQAAAA==.Hystaric:BAAANQADCgYIDAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgEIAQAAAA==.',
Ia='Iamyu:BAAANQAECgMIAwABNQAECggICwAGAAAAAA==.',
Ib='Ibun:BAAANQAECgUICwAAAA==.',
Ic='Iceblow:BAAANQADCgcIBwAAAA==.Icentheveins:BAABNQAECoEiAAIBAAkKbxeQLQCVAgABAAkKbxeQLQCVAgAAAA==.',
Ig='Igneus:BAACNQAFFIEMAAISAAUK0yLRCwD6AQASAAUK0yLRCwD6AQA1AAQKgSQAAhIACQrnI3oVAHcDABIACQrnI3oVAHcDAAAA.Igriz:BAAANQADCggIJAAAAA==.',
Ii='Iillil:BAABNQAECoEcAAIXAAkKFgupJQD5AQAXAAkKFgupJQD5AQAAAA==.',
Il='Ilvinabox:BAAANQADCgQIBAAAAA==.',
Im='Imakeuflased:BAAANQADCgIIAgAAAA==.Immamoonchix:BAAANQADCgUICwAAAA==.Imthatguy:BAAANQAECgEIAQAAAA==.Imtheworst:BAAANQADCgIIAgAAAA==.Imzaiahx:BAAANQADCgEIAQAAAA==.',
In='Inkyraven:BAAANQAECgEIAQAAAA==.Insidedoubt:BAAANQAECgUIBwAAAA==.',
Ir='Irodina:BAAANQADCgUICgAAAA==.Ironorchid:BAAANQADCgUJBQAAAA==.',
It='Itsjeff:BAAANQAECgYIEQAAAA==.',
Iz='Izyel:BAAANQADCgEIAQAAAA==.',
Ja='Jambonjay:BAABNQAECoEgAAIDAAcKJgngtgBkAQADAAcKJgngtgBkAQAAAA==.Jananda:BAABNQAECoEUAAMhAAYKyAQ3XgBVAAAhAAUKIAE3XgBVAAAgAAYK0gDdlwBIAAAAAA==.Jarnirdimli:BAAANQABCgYIDAAAAA==.Jaywaz:BAAANQAECgUIBgAAAA==.',
Jc='Jckjck:BAAANQADCgIIAgAAAA==.Jckjckjck:BAAANQADCgUIBQAAAA==.Jckjckjckjck:BAAANQAECgcICAAAAA==.',
Je='Jermagedupri:BAACNQAFFIEPAAISAAUK9BIpGACPAQASAAUK9BIpGACPAQA1AAQKgTEAAhIACQr/ITUqADEDABIACQr/ITUqADEDAAAA.Jessupy:BAABNQAECoEXAAIiAAgKxBZcJwA5AgAiAAgKxBZcJwA5AgAAAA==.Jezashi:BAAANQADCgUIBQAAAA==.Jezina:BAAANQAECgEIAQAAAA==.',
Jh='Jhene:BAAANQAECgYIBgABNQAECggICwAGAAAAAA==.',
Jo='Jofroztok:BAAANQADCgEIAQAAAA==.Johkneesinz:BAAANQADCgYICwAAAA==.Johntapper:BAAANQADCgQIBgAAAA==.Joshuå:BAAANQAECgUIDAAAAA==.',
Ju='Julieteshade:BAAANQADCgMJBAAAAA==.Junkbot:BAAANQADCgYIEAAAAA==.Justiz:BAAANQADCgYIBgAAAA==.',
['Jø']='Jøsh:BAAANQADCgQIBQAAAA==.',
Ka='Kaimingxiona:BAAANQAECgYICgAAAA==.Kaiysz:BAAANQAECgIIAgAAAA==.Kalrendion:BAAANQADCgMIAwABNQAECgcIEQAGAAAAAA==.Kalru:BAAANQAECgEIAgAAAA==.Kalzok:BAEANQADCgYIBgABNQAECgkJNAATAJkjAA==.Karaillyonna:BAAANQAECgcICAAAAA==.Karasu:BAAANQAECgEIAQAAAA==.Karliechirky:BAAANQADCgYIBgAAAA==.Kasher:BAAANQAECgUICQAAAA==.Kayho:BAAANQAECgUJCwAAAA==.',
Ke='Kelltrax:BAAANQAECgMIBAAAAA==.Kelsier:BAABNQAECoEiAAMIAAkKKSNKBABPAwAIAAkKKSNKBABPAwAfAAUKqQSWSACpAAAAAA==.Kelzorn:BAAANQADCgEIAQAAAA==.Keruilin:BAAANQADCgQIAgAAAA==.Kesk:BAAANQADCgUICAAAAA==.',
Kh='Khaster:BAAANQABCgEIAQAAAA==.Khela:BAAANQAECgIIAgAAAA==.Khendra:BAAANQAECgUIBQAAAA==.',
Ki='Kiezo:BAAANQAECgQICQAAAA==.Killachefd:BAAANQAECgYIEAAAAA==.Killamanjoro:BAABNQAECoEcAAIDAAgKWxxyZwA6AgADAAgKWxxyZwA6AgAAAA==.Kimchiwar:BAAANQAECgYIDQAAAA==.Kirasha:BAAANQAECgEIAQAAAA==.Kitak:BAAANQAECgcIEQAAAA==.Kitchenbound:BAAANQAECgcIEQAAAA==.Kittychan:BAABNQAECoEcAAIWAAgKTxZzOAAeAgAWAAgKTxZzOAAeAgAAAA==.',
Kl='Klaacus:BAABNQAECoEoAAMXAAkKRBYwGACCAgAXAAkKiBUwGACCAgAiAAEKnhGjfQBBAAAAAA==.Kloex:BAAANQABCgIIAgAAAA==.',
Kn='Knosk:BAAANQAECgUIBgAAAA==.',
Ko='Kodomo:BAAANQAECgEIAQAAAA==.Kokk:BAAANQAECgMIAwAAAA==.Koudelka:BAAANQAECgQJBAAAAA==.',
Kr='Kralok:BAAANQADCgYICwAAAA==.Krazm:BAAANQAECgcIEAAAAA==.Kreleril:BAAANQADCgEIAQAAAA==.Kriticál:BAABNQAECoEcAAMOAAkK9hCuIQACAgAOAAkK9hCuIQACAgAQAAEKXxIxJQA1AAAAAA==.Krustyg:BAAANQADCgcIDAAAAA==.Krustym:BAAANQADCgYIBgAAAA==.',
Ku='Kuurun:BAEBNQAECoEUAAIlAAgKpB6HCADgAgAlAAgKpB6HCADgAgABNQAECgkJNAATAJkjAA==.',
La='Lakshmi:BAABNQAECoEUAAICAAcKtxvCVABKAgACAAcKtxvCVABKAgAAAA==.Laradin:BAAANQADCgEJAQAAAA==.Larasimus:BAAANQADCgMIAwAAAA==.Larndorn:BAAANQAECgQICgAAAA==.Lavagrip:BAABNQAECoEUAAMTAAUKTgwp+AD0AAATAAUKeQop+AD0AAAUAAEKiBDoYwAxAAAAAA==.Laylea:BAAANQADCgIIAgAAAA==.',
Le='Lelou:BAACNQAFFIELAAMCAAUKxySAAwAJAgACAAUKxySAAwAJAgAaAAEKvh3SHABQAAA1AAQKgTgAAwIACQqdJrcCANIDAAIACQqdJrcCANIDABoABwrTIm4VAJwCAAAA.Letmehealu:BAAANQAECgYICAAAAA==.Lewsky:BAAANQAECgMIBgABNQAECgkJHAATAEAjAA==.',
Li='Lichtghost:BAAANQADCggICQAAAA==.Lightningzap:BAAANQADCgMIAwAAAA==.Lilathiaa:BAAANQADCgYIGwAAAA==.Lilru:BAAANQAECgEIAQAAAA==.Linddria:BAABNQAECoEiAAIRAAgKohMbJwAlAgARAAgKohMbJwAlAgAAAA==.Liondori:BAAANQAECgEIAQAAAA==.Lipspire:BAAANQABCggICAAAAA==.Lissarael:BAAANQAECgcIDgAAAA==.',
Lm='Lmj:BAAANQAECgIICgAAAA==.',
Lo='Lockbox:BAABNQAECoEnAAMLAAgK8CP/DQBMAwALAAgK8CP/DQBMAwANAAMKFSG1LAAQAQAAAA==.Lokmar:BAAANQAECgQIBAAAAA==.Loomin:BAABNQAECoEvAAMSAAkKtR+lOwACAwASAAkKZx2lOwACAwAdAAUKGRG6GAALAQAAAA==.',
Lu='Lucatia:BAABNQAECoEfAAIXAAkKjRw3DwDqAgAXAAkKjRw3DwDqAgAAAA==.Luciaa:BAAANQADCgQIAgAAAA==.Lumièrevide:BAAANQADCgIIAgABNQAECgcICAAGAAAAAA==.Lunastitch:BAAANQADCgEIAQAAAA==.Lunna:BAAANQADCgUICAAAAA==.',
['Lä']='Lädyæk:BAABNQAECoEVAAICAAgKkg7DbQAKAgACAAgKkg7DbQAKAgAAAA==.',
Ma='Maekyss:BAAANQAECgcIEQAAAA==.Magezu:BAAANQAECgYIEQAAAA==.Maggarak:BAAANQAECgYIDAAAAA==.Magixstraza:BAABNQAECoEiAAISAAgKGhenigBPAgASAAgKGhenigBPAgAAAA==.Magwilddued:BAAANQADCgQIBQAAAA==.Mahmba:BAAANQAECgUIBgAAAA==.Malthoryn:BAAANQAECgIIAgAAAA==.Malzel:BAAANQAECgcIDQAAAA==.Mamasan:BAAANQAECgYICwAAAA==.Mamor:BAAANQAECgUICAAAAA==.Maphra:BAAANQAECgUICAAAAA==.Marvindent:BAAANQADCgYIBgAAAA==.Mastatracka:BAAANQAECgQIBwAAAA==.Mazethak:BAAANQAECgEIAQAAAA==.',
Md='Mdeow:BAAANQADCgUIBQAAAA==.',
Me='Mechabull:BAAANQAECgEIAwAAAA==.Meladys:BAAANQADCgUIBQAAAA==.Meleemeal:BAAANQAECgUIBQAAAA==.Melianthal:BAAANQAECgEIAQAAAA==.Melorac:BAAANQAECgUIBwAAAA==.Menoheal:BAAANQADCgMIAwAAAA==.Merope:BAAANQADCgUIBQAAAA==.Mertence:BAAANQAECgYIEQAAAA==.Mexicanbrick:BAAANQADCgEIAQAAAA==.',
Mh='Mheow:BAAANQAECgIIAgAAAA==.',
Mi='Miakoda:BAAANQAECgEIAQAAAA==.Micromortis:BAAANQAECgQJBAABNQAECgcICQAGAAAAAA==.Mikuu:BAAANQAECgQICgAAAA==.Minouetoile:BAAANQADCgYIBgAAAA==.Misamane:BAAANQAECgMIBAAAAA==.Mistdru:BAAANQADCgUIBQAAAA==.Mistical:BAABNQAECoEWAAMIAAgKeRnMDwBbAgAIAAgKeRnMDwBbAgAfAAEKxgHHagAdAAAAAA==.Mitufu:BAAANQAECgIIBQAAAA==.',
Mm='Mmeow:BAAANQADCgcIBwAAAA==.',
Mo='Moelestyr:BAAANQAECgEIAQAAAA==.Mogonn:BAAANQABCgEIAQAAAA==.Moonpiie:BAAANQADCgUIBQAAAA==.Morganya:BAABNQAECoE2AAMXAAkKqhofEwC7AgAXAAkKqhofEwC7AgAiAAEKAg5ugQA3AAAAAA==.Morgul:BAAANQAECgcIDgAAAA==.Moriru:BAAANQAECgMIAwAAAA==.Moroton:BAAANQADCgQIBAABNQAECgUICwAGAAAAAA==.Morrtis:BAAANQADCgYIEwAAAA==.Morticas:BAAANQAECgMIAwAAAA==.',
Ms='Mseow:BAAANQADCggIFgAAAA==.',
Mu='Mudbutbrooks:BAABNQAECoEVAAMaAAYK+BBqNwBmAQAaAAYK+BBqNwBmAQAZAAEKyQNVEgArAAAAAA==.Muddbut:BAAANQADCgQIBAABNQAECgkJIgABAG8XAA==.Muller:BAABNQAECoEaAAITAAcK4RHvmAC7AQATAAcK4RHvmAC7AQAAAA==.',
Mv='Mveow:BAAANQADCgUIAwAAAA==.',
Mw='Mweow:BAAANQADCgYIDwAAAA==.',
My='Mynnu:BAAANQAECgUIEAAAAA==.Mynthara:BAAANQADCggIAgAAAA==.Mythiand:BAAANQADCgIIAgAAAA==.',
Na='Nautprepared:BAAANQAECgUICgAAAA==.',
Ne='Necrodancer:BAAANQAECggJAwAAAA==.Necrogore:BAAANQADCgcIBwAAAA==.Neeo:BAAANQADCgEJAQAAAA==.Neildasstysn:BAAANQAECgYIDAABNQAECggIBwAGAAAAAA==.Nemezyz:BAAANQADCgQIBAAAAA==.Nephey:BAAANQADCgMIAwAAAA==.Neverdruid:BAAANQADCgEIAQAAAA==.Neveya:BAAANQADCgcIHAAAAA==.',
Ni='Nickeld:BAABNQAECoEaAAISAAgK7hvvbACPAgASAAgK7hvvbACPAgAAAA==.Nickhy:BAAANQAECgUICQAAAA==.Nietherme:BAABNQAECoEXAAITAAcKpxHWtAB8AQATAAcKpxHWtAB8AQAAAA==.Nietheryew:BAAANQADCgIIAgAAAA==.Nihildicits:BAAANQADCgIIAgAAAA==.Nikkeld:BAAANQADCgIIAgAAAA==.Nitesblade:BAAANQAECgEIAQABNQAECgcIFwAEAD4fAA==.',
No='Noblefiend:BAAANQADCgQIBAAAAA==.Nofoamlatte:BAAANQADCggIDwABNQAECggIHAAWAE8WAA==.Nolife:BAAANQAECgEIAgAAAA==.Norinithedra:BAAANQADCgMIAwAAAA==.',
Ny='Nyagosa:BAABNQAECoEVAAIPAAgKlxHFXQDXAQAPAAgKlxHFXQDXAQAAAA==.Nyalore:BAAANQAECgcIEwAAAA==.Nymesys:BAAANQADCgYIBgAAAA==.',
Ob='Obiwinonly:BAAANQAECgEIAwAAAA==.',
Oh='Ohnjaxx:BAAANQAECgEIBAAAAA==.',
Op='Optamus:BAAANQAECgEIAgAAAA==.',
Or='Oraedia:BAABNQAECoE5AAIBAAkKQh7AEQAwAwABAAkKQh7AEQAwAwAAAA==.Oralen:BAABNQAECoElAAMBAAkKySLlBwB+AwABAAkKySLlBwB+AwATAAIKbQ8hRwFqAAAAAA==.Orilitha:BAAANQADCgYIDAAAAA==.Orlandris:BAAANQADCgcIGAAAAA==.Orndaith:BAABNQAECoEYAAIDAAkKyw9tgQD0AQADAAkKyw9tgQD0AQAAAA==.',
Ov='Overloader:BAABNQAECoEeAAIiAAkKeh7hDwAKAwAiAAkKeh7hDwAKAwAAAA==.',
Ox='Oxkenpachixo:BAAANQADCgMIAwAAAA==.',
Oy='Oyabun:BAAANQADCgYIBgAAAA==.',
Pa='Pairodeez:BAAANQADCgMIAQAAAA==.Palimax:BAAANQAECgEIAgAAAA==.Pallyaxe:BAAANQAECgQIBgABNQAECggIKAASANEZAA==.Pandawannabe:BAAANQAECgQICAAAAA==.Pandussi:BAABNQAECoEaAAIfAAkKXxNaHgATAgAfAAkKXxNaHgATAgAAAA==.Paneer:BAAANQAFFAEIAQAAAA==.Paninus:BAAANQAECgEIAgAAAA==.Papabair:BAAANQAECgcICQAAAA==.Papawheelie:BAAANQADCgcIBwAAAA==.',
Pe='Pebbletoe:BAAANQADCgUIBQAAAA==.Penta:BAAANQAECgIIAgAAAA==.Perfectplex:BAAANQABCgUIBQAAAA==.Peruano:BAABNQAECoEhAAINAAkKjBOLCABrAgANAAkKjBOLCABrAgAAAA==.Petforheals:BAAANQAECgUIDwAAAA==.',
Ph='Phanchom:BAAANQAECgEIAQAAAA==.Phouy:BAAANQADCgUIBQAAAA==.Phyett:BAAANQADCgEIAQABNQAECgQICAAGAAAAAA==.',
Pi='Pietastegood:BAABNQAECoElAAIDAAgKjyRCGQBHAwADAAgKjyRCGQBHAwAAAA==.Pigbeniz:BAAANQABCgIIAgAAAA==.Pikaboom:BAAANQADCgYJBgABNQAECggICwAGAAAAAA==.Pintsizemage:BAAANQAECgUIBQABNQAECgcICQAGAAAAAA==.Pitchblack:BAAANQAECggIEgAAAA==.',
Po='Pocahöntas:BAAANQAECgQIBwAAAA==.Pocketrocket:BAAANQADCgUIBgAAAA==.Ponce:BAABNQAECoEsAAIlAAkKeB4aBQAyAwAlAAkKeB4aBQAyAwAAAA==.Poordemon:BAAANQADCgUIBQABNQAECggIIQAWAHcIAA==.Popehealz:BAAANQADCgYJAQAAAA==.',
Pr='Predatori:BAAANQADCgIIAgAAAA==.Priestofholy:BAAANQADCgYIDQAAAA==.Privo:BAAANQAFFAQIBAAAAA==.Provolonie:BAAANQADCggIDAAAAA==.Proñto:BAAANQAECggIAgABNQAECgcIGgAHAMcPAA==.Pryor:BAAANQAECgUIBwAAAA==.Pròntò:BAAANQADCgQIBAABNQAECgcIGgAHAMcPAA==.Prõntõ:BAAANQADCgEIAQABNQAECgcIGgAHAMcPAA==.Prøntø:BAABNQAECoEaAAMHAAcKxw8xHgBoAQAHAAcKxw8xHgBoAQAeAAIKvgNUMABOAAAAAA==.',
Pu='Puffthemagic:BAAANQADCgYICQABNQAECggIJgADAFsdAA==.Punchbugman:BAAANQAECgEIAQAAAA==.Puritos:BAAANQAECgEIAgAAAA==.Pustain:BAAANQAECgEIAQAAAA==.',
Py='Pymera:BAAANQAECgMICAABNQAECgUIBgAGAAAAAA==.Pyrista:BAABNQAECoEUAAICAAYKgR0HdAD6AQACAAYKgR0HdAD6AQAAAA==.',
Qd='Qdonis:BAAANQADCgMIAwABNQAECgkJKAAXAEQWAA==.',
Qo='Qortethpally:BAAANQADCgQIBAAAAA==.',
Qu='Quaratus:BAAANQADCgEIAQAAAA==.Quinte:BAEANQABCgQIBAAAAA==.',
Ra='Radetoo:BAABNQAECoEcAAIiAAcK7A3SPgCOAQAiAAcK7A3SPgCOAQAAAA==.Radilas:BAAANQAECgEIAQAAAA==.Radioatlarge:BAAANQAECgUIBQABNQAECggIJQADAI8kAA==.Raendarth:BAAANQAECgUIEAAAAA==.Rageth:BAAANQAECgYIEwAAAA==.Ragglefraggl:BAAANQADCgMIAwABNQAECgkJKgARAPIhAA==.Rakalaag:BAEANQAECgQIBwAAAA==.Rakath:BAAANQAECgQIBwAAAA==.Ramidus:BAAANQAECgQICAAAAA==.Ranciid:BAAANQADCgIIAwAAAA==.Rasmis:BAAANQAECgcIEAAAAA==.Rathorn:BAAANQADCgQIAwAAAA==.',
Re='Reck:BAABNQAECoEmAAIDAAgKWx1CPQC7AgADAAgKWx1CPQC7AgAAAA==.Redlands:BAAANQAECgEIAQAAAA==.Redredwine:BAAANQADCggICAAAAA==.Rejuve:BAAANQADCgYIBgAAAA==.Rektify:BAAANQADCgEIAQAAAA==.Renwick:BAAANQAECgEIAQABNQAFFAUIEQAMAOwbAA==.Restlece:BAAANQABCgEIAQAAAA==.Reunach:BAAANQAECgcIEwAAAA==.',
Rh='Rhahirn:BAAANQAECgMIAwAAAA==.Rhialto:BAAANQADCgIJAgAAAA==.Rhinopill:BAAANQAECgUIBgABNQAECgkJKgARAPIhAA==.Rhyzand:BAAANQADCgQIBwAAAA==.',
Ri='Riasg:BAAANQADCgIIAgAAAA==.Ribeyes:BAAANQAECgEIAQAAAA==.Rickilake:BAAANQADCggIJwAAAA==.Ricksanchez:BAABNQAECoEaAAIEAAkKgRfxMwCDAgAEAAkKgRfxMwCDAgAAAA==.Rinik:BAAANQAECgYIDwAAAA==.Riptiide:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.Rivendra:BAAANQADCggJGAAAAA==.Riverpixie:BAAANQAECgEIAgAAAA==.',
Ro='Rockabye:BAAANQAECgYIEQAAAA==.Rokar:BAAANQAECgEIAgAAAA==.Rosannas:BAAANQADCgYIDAABNQAECgkJKgARAPIhAA==.Rosi:BAAANQAECgEIAQAAAA==.Royallz:BAAANQAECgIIAgAAAA==.',
Ru='Rudeknees:BAACNQAFFIEJAAIEAAMKshE/FAD3AAAEAAMKshE/FAD3AAA1AAQKgS8AAwQACQq1Fiw7AGECAAQACQq1Fiw7AGECACUABQp8AqEmALEAAAAA.Ruibash:BAEBNQAECoE0AAITAAkKmSOfCwCXAwATAAkKmSOfCwCXAwAAAA==.Rukie:BAAANQAECgUIBQAAAA==.Runebladé:BAABNQAECoEWAAIWAAcKoRrnQQDuAQAWAAcKoRrnQQDuAQAAAA==.',
Ry='Ryuu:BAAANQAECgEIAQAAAA==.Ryuuzen:BAAANQAECgUIBgAAAA==.',
Sa='Sabitha:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQADCgEIAQAAAA==.Sacklunch:BAAANQADCgEIAQAAAA==.Sacredkhaos:BAAANQADCgQJBAABNQADCgQIBQAGAAAAAA==.Sacredknight:BAAANQADCgQIBQAAAA==.Saikoumaster:BAAANQAECgEIAgAAAA==.Saintkhaos:BAAANQADCgIIAgABNQADCgQIBQAGAAAAAA==.Sakuraa:BAABNQAECoEcAAMPAAkKSwg9ZQC8AQAPAAkKSwg9ZQC8AQAQAAMKLQGUHwBQAAAAAA==.Samisra:BAAANQADCgYJBgAAAA==.Sarajean:BAAANQAECgEIAgAAAA==.Savaged:BAAANQADCgcIDAABNQAECggIKgAWACgZAA==.Savajed:BAABNQAECoEqAAMWAAgKKBk5NgArAgAWAAgKKBk5NgArAgAbAAYKwAraTwAoAQAAAA==.Savaragon:BAAANQADCgcIEwABNQAECggIKgAWACgZAA==.Sazbena:BAAANQADCgQIBAAAAA==.',
Sc='Scallywagg:BAAANQAECgQIBgAAAA==.Scarletmatch:BAAANQAECgIIAgAAAA==.Scroto:BAAANQAECgEIBAAAAA==.',
Se='Searcomic:BAAANQAECgYIEAAAAA==.Secondwall:BAAANQADCgMIAwAAAA==.Seldav:BAABNQAECoErAAMkAAkKPRgxBQB3AgAkAAkKPRgxBQB3AgAmAAMKWQrpKwCgAAAAAA==.Selendas:BAAANQAECgEIAQAAAA==.Selessa:BAAANQADCggICgAAAA==.Selinathra:BAAANQAECgIIAgAAAA==.Selm:BAABNQAECoEjAAIHAAgKfSTaAwBUAwAHAAgKfSTaAwBUAwAAAA==.',
Sh='Shadedluster:BAAANQADCgQIBQAAAA==.Shaleka:BAAANQADCgYIDQABNQADCgYIEAAGAAAAAA==.Shaluesta:BAAANQADCgcICgAAAA==.Shamanism:BAAANQAECgYICwAAAA==.Shameless:BAAANQAECgYICwAAAA==.Shamwów:BAABNQAECoEXAAIFAAgKnxr2NABlAgAFAAgKnxr2NABlAgAAAA==.Sharco:BAABNQAECoEaAAIdAAYKlR+qCwDOAQAdAAYKlR+qCwDOAQAAAA==.Sharkbites:BAAANQAECgUICQAAAA==.Shawarmafury:BAACNQAFFIEFAAICAAMKKB4WEAAYAQACAAMKKB4WEAAYAQA1AAQKgSoAAgIACQrrJncBAOsDAAIACQrrJncBAOsDAAAA.Shaydens:BAAANQADCgEIAQAAAA==.Shettani:BAAANQAECgEIAQAAAA==.Shiirou:BAAANQADCgQIBAAAAA==.Shockrasta:BAAANQAECgQIBQABNQAECggIKAAdAPwiAA==.Shooshmael:BAABNQAECoEcAAIEAAgKJRVWSwAcAgAEAAgKJRVWSwAcAgAAAA==.Shozo:BAAANQADCgUICAABNQAECggIIwAHAH0kAA==.Shujáa:BAAANQAECgYICAAAAA==.Shælynne:BAAANQABCgIIAgABNQAECgkJNgAXAKoaAA==.Shékinah:BAABNQAECoEpAAIgAAkK5g84NgARAgAgAAkK5g84NgARAgAAAA==.',
Si='Sidesteppin:BAAANQADCgUICAAAAA==.Silirazzle:BAAANQADCgMIAwAAAA==.Sinsister:BAAANQAECgMIBAAAAA==.Sinthein:BAAANQAECgMIBQABNQAFFAUIEQAMAOwbAA==.Sixséven:BAAANQADCgIIAQABNQADCgYIBgAGAAAAAA==.',
Sk='Skadgrip:BAAANQADCgUIBQABNQAECgcIDQAGAAAAAA==.Skorpekh:BAABNQAECoEZAAICAAgK4wYVlgCpAQACAAgK4wYVlgCpAQAAAA==.Skyle:BAAANQADCgQIBAAAAA==.Skypanties:BAAANQAECgQICgAAAA==.',
Sl='Sleepingsun:BAABNQAECoEcAAIhAAgKWR94DwDBAgAhAAgKWR94DwDBAgAAAA==.Sloppyspikes:BAABNQAECoEUAAInAAgKAwdVFAA0AQAnAAgKAwdVFAA0AQAAAA==.',
Sm='Smakm:BAAANQADCgEIAQAAAA==.Smashdocta:BAABNQAECoEiAAIDAAgKuhYyYQBMAgADAAgKuhYyYQBMAgABNQAECgkJLAACAHQiAA==.Smidgenn:BAAANQADCgcIDAAAAA==.Smokyblast:BAAANQAECgYIDgAAAA==.Smolden:BAAANQABCgEIAQAAAA==.',
Sn='Snailtrails:BAAANQADCggIGAAAAA==.Sneakgooner:BAAANQADCgcIBwAAAA==.Snowball:BAABNQAECoEsAAISAAcKGAUeDgFOAQASAAcKGAUeDgFOAQAAAA==.',
So='Sohtan:BAAANQADCgQIBAAAAA==.Sonbrandt:BAABNQAECoEXAAMfAAcKrg3HLgBuAQAfAAcKrg3HLgBuAQAJAAEK7g5cLAA2AAAAAA==.Soulforge:BAAANQADCgQIBAAAAA==.Soulread:BAAANQAECgQIDQAAAA==.',
Sp='Sparowprince:BAACNQAFFIEHAAITAAUK5RRqCACaAQATAAUK5RRqCACaAQA1AAQKgTQAAhMACQrZI2sPAH8DABMACQrZI2sPAH8DAAAA.Speccurious:BAAANQADCgYIBwABNQAECgMIAwAGAAAAAA==.Spectraleye:BAAANQAECgcIEQAAAA==.Sproocherlou:BAABNQAECoEgAAITAAkKbxlhQACuAgATAAkKbxlhQACuAgAAAA==.Sprour:BAAANQAECgYJCAAAAA==.',
St='Stankbolt:BAABNQAECoEVAAILAAcKECW9HgDzAgALAAcKECW9HgDzAgAAAA==.Steezya:BAAANQAECgUIEAAAAA==.Stegulos:BAAANQAECgEIAgAAAA==.Stellarum:BAAANQAECgMIBAAAAA==.Stonedemon:BAAANQAECgQIBAABNQAFFAUIBwATAOUUAA==.Stormsy:BAAANQAECgQIBgABNQAECggIFQAPANwLAA==.Stormykitty:BAABNQAECoEVAAIPAAgK3AsKbwCYAQAPAAgK3AsKbwCYAQAAAA==.Strauch:BAAANQADCgcIFQAAAA==.Striderdh:BAAANQABCggIEAAAAA==.Strongwoman:BAAANQAECgUIDAAAAA==.Sturtza:BAACNQAFFIEFAAICAAIKdwxpIACcAAACAAIKdwxpIACcAAA1AAQKgTIAAgIACQoxIvcHAI8DAAIACQoxIvcHAI8DAAAA.Sturtzam:BAAANQADCgUJBQABNQAFFAIIBQACAHcMAA==.',
Su='Subarashi:BAAANQADCgYIBgAAAA==.Sukmybigtoe:BAAANQADCgIIAQAAAA==.Sunbear:BAAANQADCgYICAAAAA==.Suun:BAABNQAECoEiAAITAAgKJhvFXABXAgATAAgKJhvFXABXAgAAAA==.',
Sw='Swampassuti:BAAANQAECgEIAQAAAA==.Sweetysnail:BAAANQAECgQIBAAAAA==.Swoley:BAABNQAECoEUAAIBAAcKFSETKgCmAgABAAcKFSETKgCmAgAAAA==.',
Sy='Sybelada:BAAANQABCgcJCQAAAA==.Sylphia:BAAANQADCgYIBgAAAA==.Syrina:BAAANQADCgQIBAAAAA==.',
Ta='Taanua:BAAANQAECgEIAQAAAA==.Taelandas:BAAANQADCgUIFQAAAA==.Tagobeets:BAABNQAECoEdAAIdAAgKOQzeDQCjAQAdAAgKOQzeDQCjAQAAAA==.Tailyn:BAAANQADCgUIBQAAAA==.Taleiya:BAAANQAECgMIDwAAAA==.Talisaie:BAAANQAECgUICgABNQAFFAUICwAiAMAeAA==.Tanisatharae:BAAANQAECgEIAQABNQAECgUIBgAGAAAAAA==.Tarahly:BAAANQAECgYICAAAAA==.Tarahse:BAAANQADCgIIAgABNQAECgYICAAGAAAAAA==.Taron:BAAANQAECgUIEgAAAA==.Tart:BAABNQAECoEZAAIEAAkKOxCOTQAUAgAEAAkKOxCOTQAUAgABNQAFFAMICQASAA4QAA==.',
Te='Tedjones:BAAANQAECgUIEAAAAA==.Temupeggy:BAAANQADCgEIAQAAAA==.',
Tg='Tgbird:BAAANQADCgQIBAAAAA==.',
Th='Thandana:BAAANQAECgEIAQAAAA==.Thehumanatee:BAABNQAECoEfAAIgAAgKNxeaLwA+AgAgAAgKNxeaLwA+AgAAAA==.Theroach:BAAANQAECgQIBAAAAA==.Thersh:BAAANQADCgMJAwAAAA==.Theunholyone:BAAANQADCgcIDQAAAA==.Thiccims:BAAANQADCgIIAgABNQAECggICwAGAAAAAA==.Thilidan:BAAANQADCgEIAQAAAA==.Thingytoo:BAAANQAECgUIBgAAAA==.Thiqq:BAAANQADCggICAAAAA==.Thrallsball:BAAANQAECgUIBgABNQAECgkJHgAiAHoeAA==.Threlindrier:BAAANQADCgYICgAAAA==.Throbinggimp:BAAANQADCggICAAAAA==.Thunderzelly:BAAANQADCggIDwAAAA==.Thurien:BAAANQAECgYIDQAAAA==.Thyphlo:BAAANQAECgUICAAAAA==.',
Ti='Tiltawhirl:BAAANQAECggICAAAAA==.Tiltedup:BAABNQAECoEdAAISAAkKDRACowAbAgASAAkKDRACowAbAgAAAA==.Tinesa:BAAANQADCgQIBQAAAA==.Tinkerßell:BAAANQADCgcIDAABNQAECggIFQAPANwLAA==.Tirich:BAAANQADCggICAABNQAFFAUIEQAMAOwbAA==.Titaintium:BAAANQAECgQIBAABNQAECgkJHgAiAHoeAA==.',
To='Toshi:BAABNQAECoEWAAILAAgKiQcBlACEAQALAAgKiQcBlACEAQAAAA==.Totemtree:BAAANQADCgMIAwABNQAECggIHQAjAMcQAA==.Touchyouup:BAAANQAECgEIAgAAAA==.',
Tr='Trustmei:BAAANQAECggICwAAAA==.Trystin:BAAANQAECgIIAwAAAA==.',
Tu='Tulark:BAAANQABCgIIAgAAAA==.Tullydin:BAABNQAECoEbAAMUAAcK0gktMgAmAQATAAcK7QfyzwBBAQAUAAcKaggtMgAmAQAAAA==.Tullyy:BAAANQAECgQICwAAAA==.Tums:BAABNQAECoEcAAMMAAgK1BzoFAAtAgAMAAcK/hvoFAAtAgARAAMKbRqMXQDvAAAAAA==.',
Tw='Tweez:BAAANQAECgEIAQAAAA==.Twirls:BAABNQAECoEXAAIJAAcKKxrNDgDlAQAJAAcKKxrNDgDlAQAAAA==.Twistoffate:BAAANQAECgIICgAAAA==.',
Ty='Tyerant:BAAANQADCgMIAgAAAA==.Tylenill:BAAANQADCgQIBAAAAA==.',
Ug='Uglygoat:BAAANQADCgEIAQAAAA==.',
Um='Umbrasanctus:BAAANQADCgUIBgAAAA==.',
Un='Uncanny:BAAANQAECgEIAQAAAA==.',
Ur='Urtle:BAAANQADCggIFAAAAA==.',
Us='Uselece:BAABNQAECoEaAAMTAAgKsh3tXgBRAgATAAgKsh3tXgBRAgAUAAMKMwv1TQCDAAAAAA==.',
Ut='Uthadandewey:BAAANQADCgcIBwAAAA==.',
Uz='Uzainbolt:BAAANQAECgcIEAAAAA==.',
Va='Valgorr:BAAANQAECgQIBQAAAA==.Valvalon:BAABNQAECoEeAAIdAAkKqBzKAwDdAgAdAAkKqBzKAwDdAgAAAA==.Vandil:BAAANQADCgYIBgAAAA==.',
Ve='Veelaria:BAABNQAECoEdAAIUAAgK/BA0IgCkAQAUAAgK/BA0IgCkAQAAAA==.Vegetablue:BAAANQAECgEIAQAAAA==.Verahardyr:BAAANQADCgIIAgAAAA==.Veravulp:BAAANQAECgEIAgAAAA==.Verdunkeln:BAAANQAECgEIAQAAAA==.Vet:BAAANQAECgQICAAAAA==.',
Vh='Vhelithiana:BAAANQAECgEIAQAAAA==.',
Vi='Viathun:BAAANQADCggICAABNQAECggIKgAWACgZAA==.Vicalaus:BAABNQAECoEhAAIbAAcK6BypJQA2AgAbAAcK6BypJQA2AgABNQAECgkJKAAXAEQWAA==.View:BAABNQAECoEYAAIFAAkK+hLASwAHAgAFAAkK+hLASwAHAgAAAA==.Vikcy:BAAANQAECgIIAwAAAA==.Vilified:BAAANQADCggIEwAAAA==.Violete:BAAANQADCgUIBQAAAA==.Vitros:BAAANQADCgcIBwABNQAECggIGwAOAJoXAA==.',
Vo='Voidbren:BAAANQADCgEIAQABNQAECgcIEgAGAAAAAA==.Voidwitch:BAAANQAECgUIDwAAAA==.Volstagg:BAAANQAECgEIAQAAAA==.',
Vr='Vrakken:BAAANQAECgQIDwAAAA==.',
Vy='Vyndenus:BAABNQAECoEpAAIPAAkKfhhGKACqAgAPAAkKfhhGKACqAgAAAA==.',
Wa='Warriorluv:BAAANQAECgEIAQAAAA==.Warrwing:BAAANQADCgcIBwAAAA==.',
We='Webbfury:BAAANQAECgcICQAAAA==.Wespoo:BAAANQAECgQIBQAAAA==.Wetpug:BAAANQADCggIDQAAAA==.',
Wh='Wheremytotem:BAAANQADCggIDQABNQAECgkJIgABAG8XAA==.Whitbone:BAAANQADCgQIBAAAAA==.Wholephister:BAAANQAECgEIAQABNQAECgQIDQAGAAAAAA==.Whupsmarse:BAAANQADCgcIDQAAAA==.',
Wi='Wickin:BAAANQADCggIDAAAAA==.Wifeyaggroed:BAAANQAECgMIAwAAAA==.Wiggles:BAAANQABCgEIAQAAAA==.Wigpetval:BAABNQAECoEdAAMCAAYKzxcIjgC8AQACAAYKdhcIjgC8AQAaAAIKrRVEXACNAAABNQAECgcIIAADACYJAA==.Wiidge:BAABNQAECoEVAAIjAAcKtguwCgCeAQAjAAcKtguwCgCeAQAAAA==.Wildside:BAAANQADCgUIBwAAAA==.Willregret:BAAANQAECgMIBwAAAA==.Winterbane:BAAANQAECgQIBAAAAA==.',
Wo='Wocky:BAABNQAECoEUAAIgAAYKeBhUQwC6AQAgAAYKeBhUQwC6AQAAAA==.Wolfchan:BAAANQAECgQIBQAAAA==.Wolfmeow:BAAANQADCgMIAwABNQAECgkJKAAXAEQWAA==.Worldcrafter:BAAANQAECgUIEAAAAA==.Worldender:BAAANQAECgUIDAAAAA==.',
Wr='Wrathofdawn:BAAANQAECgIIBAAAAA==.Wreckross:BAAANQAECgEIAgAAAA==.',
Xa='Xantry:BAABNQAECoEcAAITAAkKQCPkJgAPAwATAAkKQCPkJgAPAwAAAA==.',
Xm='Xmen:BAAANQAFFAEIAQAAAA==.',
Xu='Xurkitree:BAAANQAECgMIAwAAAA==.',
Xy='Xymm:BAAANQAECgEIAwAAAA==.',
Ye='Yeastybush:BAABNQAECoEgAAIFAAkKdR01HQDbAgAFAAkKdR01HQDbAgAAAA==.',
Ys='Yseeraa:BAAANQAECgEIBQAAAA==.',
Za='Zalatoes:BAAANQAECgEIAQAAAA==.Zarathea:BAAANQAECgEIAQABNQAECgUIBQAGAAAAAA==.',
Zi='Zilphah:BAAANQADCgMIAwAAAA==.Zimmerwitch:BAAANQAECgEIAQAAAA==.Zimms:BAABNQAECoEiAAIfAAkKhh5mCwAHAwAfAAkKhh5mCwAHAwAAAA==.',
Zo='Zoeyredbird:BAAANQAECgcIDQAAAA==.Zongo:BAAANQADCgcIBwAAAA==.',
Zw='Zwhitty:BAAANQADCgcJCQAAAA==.Zwhittytv:BAAANQAECggICwAAAA==.',
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
