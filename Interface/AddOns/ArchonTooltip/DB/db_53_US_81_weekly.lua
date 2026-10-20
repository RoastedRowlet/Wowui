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

local lookup = {'Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Shaman-Elemental','Warlock-Destruction','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Warlock-Demonology','Mage-Arcane','Hunter-Marksmanship','DemonHunter-Devourer','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aakai:BAABNQAECn8yAAQBAAoKwBlyDAB6AQACAAgKoBldBgBsAgABAAUKFRZyDAB6AQADAAIKEQp8MgB/AAAAAA==.Aarmorr:BAABNQAECn8pAAIEAAkKcAmbHgBwAQAEAAkKcAmbHgBwAQAAAA==.',
Ac='Acinianis:BAAANQADCggIDwAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQAECgIIAgAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICgAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAABNQAECn8kAAIFAAgK0xp7UwB2AgAFAAgK0xp7UwB2AgAAAA==.Alicalsastre:BAAANQAECggIEAAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAABNQAECn8kAAMGAAgKTgxKGgDyAAAGAAgKTgxKGgDyAAAHAAUKzgS0hAC/AAAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgYIBQAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgIIAwABNQAECgYIDwAIAAAAAA==.Amata:BAAANQAECgQIBgAAAA==.Amblance:BAAANQAECgIIAgAAAA==.Amelianne:BAAANQAECgEIAQAAAA==.Ammastary:BAAANQAECgQIBgAAAA==.Ammonfrey:BAAANQADCgUIBQAAAA==.',
An='Andrea:BAABNQAECn8gAAIJAAgKXhHQBgBEAQAJAAgKXhHQBgBEAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8ZAAMKAAcKcg5olQBVAQAKAAcKcg5olQBVAQALAAQKUQdEVgCzAAAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQADCggIFQAAAA==.Archonsfury:BAAANQAECgQIBAAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8aAAIMAAoKKha7bwBEAgAMAAoKKha7bwBEAgAAAA==.',
As='Ashentris:BAAANQAECgQICAAAAA==.Asnew:BAABNQAECn8jAAINAAoKXwvzVwCTAQANAAoKXwvzVwCTAQAAAA==.Asura:BAABNQAECn8XAAMOAAgKlxQEUQDPAQAOAAcKfRQEUQDPAQAPAAIKvA1XlwBmAAAAAA==.',
At='Athelstan:BAABNQAECn8VAAILAAcK5wpdQAAsAQALAAcK5wpdQAAsAQAAAA==.Atonement:BAAANQADCgIIAgABNQAECgkJLQAQADsbAA==.',
Au='Aumaril:BAAANQAECgcIBwAAAA==.Aumaryl:BAABNQAECn8bAAMBAAoKbxUuFABHAgABAAkKoBYuFABHAgADAAIKOg2RTAA9AAAAAA==.Auralynn:BAAANQAECgcIDwAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAABNQAECn8qAAIHAAkKoQgLEgBJAQAHAAkKoQgLEgBJAQAAAA==.',
Az='Azariel:BAABNQAECn8iAAMRAAgKJhJ2mgDuAQARAAgKJhJ2mgDuAQAQAAEKAAB7dQAnAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECn8pAAIQAAkKIxkaBADOAQAQAAkKIxkaBADOAQAAAA==.',
Ba='Baane:BAAANQAECgQIBgABNQAECgQIDAAIAAAAAA==.Babnik:BAEBNQAECn8XAAIFAAcK4wv5rwCkAQAFAAcK4wv5rwCkAQAAAA==.Balderdashe:BAAANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAABNQAECn8jAAMSAAkKTRpiAQCTAQAKAAkKVBm7VAAlAgASAAcK0BFiAQCTAQAAAA==.Belovis:BAACNQAFFH8OAAIRAAUKZRqTCgCfAQARAAUKZRqTCgCfAQA1AAQKfyoAAhEACgqgIv4fAEMDABEACgqgIv4fAEMDAAAA.Betsea:BAAANQADCgcIBwABNQAECgcIJQATABkYAA==.',
Bi='Bidock:BAAANQAECgQJBAAAAA==.Bidoof:BAABNQAECn8eAAIUAAgKlAvUJADfAAAUAAgKlAvUJADfAAAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn8kAAIVAAkKGRprAQAKAgAVAAkKGRprAQAKAgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQIDgAAAA==.',
Bo='Boggrog:BAAANQAECgMIDAAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUICQAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgUIBwAAAA==.Bordeaux:BAAANQAECgMIBQABNQAECgQIDgAIAAAAAA==.Bosshog:BAABNQAECn8eAAIWAAcK4wqLOADhAAAWAAcK4wqLOADhAAAAAA==.',
Br='Brabanzio:BAAANQAECgUIEgABNQAECgoKMAAEAIYaAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgIIAwAAAA==.Brotato:BAAANQABCgcICwABNQAECgYICQAIAAAAAA==.Brotatochip:BAAANQAECgYICQAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAABNQAECn8YAAITAAoKrhdGBACqAgATAAoKrhdGBACqAgAAAA==.Burningblunt:BAAANQAECgYICgAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQAECgUICAABNQAECggIFQAXAPcEAA==.Castle:BAAANQAECgQIDAAAAA==.Catsinhats:BAAANQADCggIDQABNQAECgoKNQAOAMAZAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgoKNQAOAMAZAA==.',
Ce='Cecelya:BAABNQAECn8kAAMKAAkKEhpJPwBuAgAKAAkKEhpJPwBuAgALAAEKyAW+MQA6AAAAAA==.',
Ch='Chablis:BAAANQAECgEIAQAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwAUADEdAA==.Chivactdl:BAAANQADCgYJCgABNQAECggIKgAEADITAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAAANQAECgUICgAAAA==.Chunknoriss:BAAANQAECgYIDQABNQAECggIKgAEADITAA==.',
Ci='Cilarnen:BAAANQAECgUIDAAAAA==.',
Cl='Claudiuss:BAAANQAECgUIBQABNQAECgoKMAAEAIYaAA==.Clure:BAABNQAECn8jAAITAAgKECMxFQArAwATAAgKECMxFQArAwABNQAECgoKMQAYALMaAA==.Clurelock:BAAANQAECgEIAQABNQAECgoKMQAYALMaAA==.Clurethyr:BAABNQAECn8xAAIYAAoKsxpIAgAlAgAYAAoKsxpIAgAlAgAAAA==.',
Co='Conchobhar:BAAANQAECgYIBgAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8NAAMKAAUKdw17EwBvAQAKAAUKdw17EwBvAQALAAEKAAByGABEAAA1AAQKfy0AAwoACgodFTBJAEoCAAoACQrUFjBJAEoCAAsACAq2HYshACoCAAAA.Corrosion:BAABNQAECn8iAAIZAAoKbRz+BgASAwAZAAoKbRz+BgASAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAIRAAUKIxPB8QA5AQARAAUKIxPB8QA5AQABNQAECgkJNgARADggAA==.Crylessplz:BAAANQAECgQICAABNQAECgkJLQAQADsbAA==.',
Ct='Cthuwu:BAAANQAECgUIBgABNQAFFAIIBgAFAJsdAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8eAAMJAAgKnxq+CwBvAgAJAAgKnxq+CwBvAgAaAAMK1BbzQwClAAAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAABNQAECn8VAAIFAAcKQxRCcgDIAAAFAAcKQxRCcgDIAAAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgYIBgAAAA==.Darkkromdor:BAABNQAECn8qAAIRAAoKYhq0YgByAgARAAoKYhq0YgByAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8nAAIUAAkKahjkJwBfAgAUAAkKahjkJwBfAgAAAA==.Deathcat:BAABNQAECn81AAMOAAoKwBkeLgB5AgAOAAoKwBkeLgB5AgAPAAYKPgthYQAfAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgQIBgAAAA==.Decayy:BAABNQAECn8fAAINAAoKrRS2LQBeAgANAAoKrRS2LQBeAgAAAA==.Dedbull:BAAANQADCggIIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn8kAAILAAgKjxNsDAA4AQALAAgKjxNsDAA4AQAAAA==.',
Do='Dolemite:BAABNQAECn8cAAMbAAYKNxPMRQDuAAAbAAUKVg/MRQDuAAAcAAYK/A4oMQDgAAAAAA==.Donalbain:BAABNQAECn8wAAIEAAoKhhqkCAA5AgAEAAoKhhqkCAA5AgAAAA==.Donninban:BAAANQAECgYICwAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgoKKgAdAKMYAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAAANQAECgQICQAAAA==.Drizzeh:BAAANQABCggIEAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgIIAgAAAA==.',
Ea='Eas:BAAANQADCgUIBQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQAECgIIAQAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eloweñ:BAAANQABCgQIBAAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn8qAAINAAoKLxQIDACJAQANAAoKLxQIDACJAQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8dAAIHAAgKtwfbVgB7AQAHAAgKtwfbVgB7AQAAAA==.Emìly:BAABNQAECn8nAAMcAAkKIBQFHADEAQAcAAcKYxYFHADEAQAbAAkKERK/DQBFAQAAAA==.',
En='Entaria:BAAANQAECgUIBwAAAA==.',
Ep='Ephria:BAABNQAECn8rAAMEAAoKBCMZEABDAwAEAAoKBCMZEABDAwAWAAEKAACXTQEnAAAAAA==.Episkey:BAAANQAECgQICAAAAA==.',
Er='Eroversion:BAAANQAECgYIEgABNQAECgkJPAAeAO8ZAA==.Eroward:BAABNQAECn88AAIeAAkK7xmFBgBSAQAeAAkK7xmFBgBSAQAAAA==.',
Es='Esmay:BAABNQAECn8gAAIWAAkKFA4rHQBHAQAWAAkKFA4rHQBHAQAAAA==.',
Et='Ethren:BAABNQAECn8qAAIDAAkKxw4/BgC3AQADAAkKxw4/BgC3AQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMIAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fangsofblood:BAAANQADCggICAAAAA==.',
Fe='Felbolter:BAABNQAECn8kAAIXAAcKGB6rCAByAgAXAAcKGB6rCAByAgAAAA==.Feliri:BAAANQADCgMIAwAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAABNQAECn8sAAIFAAoK9RcKEQDoAQAFAAoK9RcKEQDoAQAAAA==.Finkate:BAAANQAECgcICQAAAA==.Firebringer:BAAANQAECggIEAAAAA==.Fistmegently:BAAANQADCggICAAAAA==.',
Fl='Flamehunter:BAAANQAECgYIBQAAAA==.Flo:BAABNQAECn80AAQLAAoKMhRlCgBQAQALAAoKMhRlCgBQAQASAAYKrgtvEAAiAQAKAAEK8wJSpQAmAAAAAA==.Floki:BAABNQAECn8VAAMeAAcKGxFkHQBsAQAeAAcKGxFkHQBsAQAMAAUKlAeG9wDuAAAAAA==.Flokin:BAAANQAECgEIAQAAAA==.Flowing:BAABNQAECn8pAAQfAAgKwhQgCAAbAgAfAAgKwhQgCAAbAgAYAAYKIwcqMgAIAQAgAAQKfATALwCcAAAAAA==.',
Fo='Foods:BAABNQAECn81AAQMAAoK6gtaTQADAQAMAAoKKQpaTQADAQAeAAUKWg2ELQDJAAAhAAIKUAtdLwBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQIBwAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAABNQAECn8WAAIRAAcKfhP3ygCGAQARAAcKfhP3ygCGAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAABNQAECn8dAAIFAAcKQRjDNgBOAQAFAAcKQRjDNgBOAQAAAA==.',
Gl='Glasgoww:BAAANQADCgUIBQABNQAECgoKMAAEAIYaAA==.Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgQIBQAAAA==.',
Go='Goburina:BAABNQAECn8lAAIEAAoKQRArXwDxAQAEAAoKQRArXwDxAQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gr='Gryffen:BAAANQABCgcIBwAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECn8iAAIFAAoKHhuZTwCAAgAFAAoKHhuZTwCAAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8qAAQfAAkKdg+HAQCLAQAfAAkKkA6HAQCLAQAgAAYKow3hHwBYAQAYAAUKzgRgOwC+AAAAAA==.Hallowed:BAAANQADCgUIBQAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn8wAAIeAAoKJBiQAwCqAQAeAAoKJBiQAwCqAQAAAA==.',
He='Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgQIBgAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgcIJQATABkYAA==.Honk:BAAANQADCggIEQAAAA==.',
Im='Imwithfloki:BAABNQAECn8ZAAQaAAYKXhraHgCoAQAaAAYKXhraHgCoAQAJAAEKAAC1OwBLAAAGAAEKhhBpQAA1AAAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECn8mAAIFAAkK6SW2CACXAwAFAAkK6SW2CACXAwAAAA==.Ismokeu:BAABNQAECn8lAAIKAAoKKRnCSABMAgAKAAoKKRnCSABMAgAAAA==.Ismyn:BAAANQAECgIIAgAAAA==.Istran:BAAANQAECgQIBQAAAA==.',
Iv='Ivrys:BAAANQAECgcIDwAAAA==.',
Iw='Iwillbethere:BAAANQAECgMIAgAAAA==.',
Ja='Jackoneal:BAAANQAECgYIEAAAAA==.Jalidelo:BAABNQAECn8jAAIKAAgKHRU6WgATAgAKAAgKHRU6WgATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn8oAAIiAAoKsxmRGACQAQAiAAoKsxmRGACQAQAAAA==.Jokersfists:BAAANQAECgQICAABNQAECggIFwAjAD4MAA==.Jokersmage:BAABNQAECn8XAAIjAAgKPgxYOgBIAQAjAAgKPgxYOgBIAQAAAA==.Joraflheim:BAAANQABCgMIBAAAAA==.Joranbragi:BAABNQAECn8VAAIRAAYKMQMUrgCJAAARAAYKMQMUrgCJAAAAAA==.Jordanjr:BAABNQAECn80AAMkAAoKZRYrDAAvAQAFAAoKOBL3TACHAgAkAAkKPhArDAAvAQAAAA==.Josunlee:BAAANQAECgUIBgAAAA==.Jotoonice:BAABNQAECn8iAAMVAAoKTRCtFgBIAQAVAAYKBxOtFgBIAQAjAAcKmgeoRwEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8LAAMkAAQKgRAjEwAOAQAkAAQKtw4jEwAOAQAFAAEKFw7SNwBLAAA1AAQKfzIAAyQACgoGGHccAG8CACQACgp+FXccAG8CAAUAAgpsIXQmAakAAAAA.',
Ju='Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECn8qAAIFAAkKzA7GFwC7AQAFAAkKzA7GFwC7AQAAAA==.Kaedina:BAAANQAECggIEQABNQAECgoKNAAkAGUWAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgEIAQABNQADCgcICgAIAAAAAA==.Karvel:BAABNQAECn8fAAINAAgKEhyXLwBUAgANAAgKEhyXLwBUAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECgkJHgATAHwcAA==.Kaydullz:BAAANQAECgcIDAAAAA==.',
Kc='Kchowchow:BAAANQAECgUIBQABNQAECgkJHgATAHwcAA==.',
Ke='Kelonaar:BAACNQAFFH8MAAMWAAQKbBOyBQD4AAAWAAQKbBOyBQD4AAAEAAIKuAPWJgBuAAA1AAQKfyYAAxYACgpsHmojAPkCABYACgpsHmojAPkCAAQAAgqxHfLiAKQAAAAA.Keloni:BAAANQAECgIIAgABNQAFFAQIDAAWAGwTAA==.Kenack:BAAANQAECgQICAAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.',
Ki='Killermoomoo:BAAANQAECgQIBgAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUICQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAAANQAECgUICQAAAA==.Lanval:BAABNQAECn8xAAIRAAoKeBhsFwDGAQARAAoKeBhsFwDGAQAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.Laurian:BAAANQABCgMIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn83AAIaAAoK+BhnDQCQAgAaAAoK+BhnDQCQAgAAAA==.Leftblank:BAAANQAECgQIBQAAAA==.',
Li='Lich:BAAANQAECgQIBAAAAA==.Lighthugger:BAABNQAECn8tAAIRAAkKxhZKeAA8AgARAAkKxhZKeAA8AgAAAA==.Lilyoptra:BAAANQAECgUIDAABNQAECgUIDAAIAAAAAA==.Liqmycrits:BAAANQADCggIGwAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgcIFwAUAEERAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAIAAAAAA==.',
Lo='Lockpockets:BAAANQAECgQIDQAAAA==.Loriane:BAAANQAECgIIAgABNQAECgcIEQAIAAAAAA==.Lorianth:BAABNQAECn8zAAIkAAoKXw+6CQBJAQAkAAoKXw+6CQBJAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgYIAwAAAA==.',
Lu='Lucifér:BAAANQABCggICgAAAA==.Lundigras:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQAECgQIBgAAAA==.Lylora:BAABNQAECn87AAIGAAoK/yVHAQDGAwAGAAoK/yVHAQDGAwAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8kAAMKAAgKfhb1UgAqAgAKAAgKfhb1UgAqAgALAAEKAACZiwAfAAAAAA==.',
Ma='Madclaws:BAABNQAECn80AAMHAAoKpxkbBwDFAQAaAAcKXxcjGgDWAQAHAAkK3hsbBwDFAQAAAA==.Madman:BAAANQAECgUICgAAAA==.Magekaestey:BAAANQADCggIDwABNQAECggIHwAMAHkNAA==.Malala:BAAANQADCgYIEgABNQAECgoKOQAKAMwZAA==.Malyndra:BAAANQAECgUICAABNQAECgYIDAAIAAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8gAAIiAAgKdQiYnQCcAQAiAAgKdQiYnQCcAQAAAA==.',
Me='Mesmash:BAABNQAECn8dAAIeAAcKYiLOCQCrAgAeAAcKYiLOCQCrAgAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDgABNQAECgYIDwAIAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIAwAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECgYICQABNQAECgkJLAAKAF8ZAA==.Miniborg:BAAANQAECgUICgABNQAECgkJNgARADggAA==.Minidude:BAAANQAECgUICAAAAA==.Misfire:BAAANQAECgEIAQAAAA==.Mistycrusade:BAAANQAECgUIBwAAAA==.Mizzen:BAABNQAECn8dAAMOAAgKcRbDPQAoAgAOAAgKcRbDPQAoAgANAAIKpQzytABfAAABNQAFFAQICgALAOUMAA==.',
Mo='Moejojojo:BAABNQAECn8WAAIbAAcKwB/pHgA5AgAbAAcKwB/pHgA5AgAAAA==.Moofasaha:BAABNQAECn8YAAMEAAYKbB23YgDlAQAEAAYKbB23YgDlAQAWAAMKiAjS+wCbAAAAAA==.Morog:BAABNQAECn8UAAMFAAgKHB8rOwC4AgAFAAgKHB8rOwC4AgAkAAEKAACNigA0AAAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAABNQAECn8UAAIjAAcKXQjPMAE7AQAjAAcKXQjPMAE7AQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgUIBQABNQAFFAEIAQAIAAAAAA==.',
['Mã']='Mãrshy:BAAANQAECggIEwABNQAFFAEIAQAIAAAAAA==.',
['Mä']='Märshy:BAAANQAECgQIBAABNQAFFAEIAQAIAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECn85AAIKAAoKzBnCDQAQAgAKAAoKzBnCDQAQAgAAAA==.Nashalie:BAABNQAECn8qAAMiAAgKWCOjGAAlAwAiAAgKWCOjGAAlAwAXAAIKOgzdVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgcIEgAAAA==.Nexbasia:BAABNQAECn8kAAIJAAkKcw9yEQDrAQAJAAkKcw9yEQDrAQAAAA==.',
Ni='Nickyboy:BAAANQAECgEIAQAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBAAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAABNQAECn8WAAIFAAgKWQktmQDVAQAFAAgKWQktmQDVAQAAAA==.',
Om='Ominis:BAAANQADCgQIBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAABNQAECn8WAAQQAAUKkhUGQAD6AAAQAAQKkhUGQAD6AAARAAQKbQGShQFSAAATAAIKuwFuHgE4AAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAILAAQKdBpcCgBTAQALAAQKdBpcCgBTAQA1AAQKfxwAAgsACQpNIisRAOgCAAsACQpNIisRAOgCAAAA.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgMIAwAAAA==.Pallydoof:BAAANQADCgcIBwAAAA==.Pallyscorned:BAABNQAECn8iAAIQAAgKuBf/HQD5AQAQAAgKuBf/HQD5AQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgcIEQAIAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAABNQAECn8uAAMbAAkKZiEPCwAjAwAbAAkKDiEPCwAjAwAdAAcKjx+bDgAKAgAAAA==.',
Ph='Phenixy:BAAANQAECgQIBgAAAA==.Phoebell:BAAANQAECgQIBwAAAA==.Phoinix:BAAANQADCggIDgAAAA==.',
Pi='Pinkducky:BAAANQADCggIGwAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECgkJLAAKAF8ZAA==.',
Po='Ponyo:BAABNQAECn8pAAIKAAkKSiN9GgAKAwAKAAkKSiN9GgAKAwAAAA==.Poppyseed:BAAANQAECgYIBgAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pr='Prinnce:BAAANQAECgQIBAABNQAECgkJJwAcACAUAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8bAAMkAAcK4hB2OACMAQAkAAcKARB2OACMAQAFAAMK1hF5HgHAAAAAAA==.',
Ra='Raddra:BAAANQAECgUICQAAAA==.Raddrah:BAAANQAECgQIAwAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radmuster:BAAANQADCgcIBwABNQAECggIFwALAEwVAA==.Radra:BAABNQAECn8bAAIlAAgKSBCpOAB/AQAlAAgKSBCpOAB/AQAAAA==.Raeku:BAABNQAECn8iAAImAAgKoh5WAwDfAgAmAAgKoh5WAwDfAgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn8pAAIKAAkKIxhzCwAuAgAKAAkKIxhzCwAuAgAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECn8pAAIRAAkK5g0rMABwAQARAAkK5g0rMABwAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAACNQAFFH8OAAIEAAQKOButEABGAQAEAAQKOButEABGAQA1AAQKfywAAgQACgrgIFoSADUDAAQACgrgIFoSADUDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgYIDQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAIAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgkJLgAbAGYhAA==.',
Ry='Ryllae:BAAANQADCgIIAgABNQAECggIIwAUADEdAA==.Ryuu:BAAANQAECgIIAwAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8ZAAMnAAkK5AcIGgC2AAAiAAkKcwfaqwB7AQAnAAQKuwYIGgC2AAABNQAECgoKIgAFAB4bAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgoKIgAFAB4bAA==.',
Sa='Saint:BAABNQAECn8gAAMTAAcKwxBCjwBwAQATAAYKcRFCjwBwAQARAAcKWRZqWwAOAQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAABNQAECn8jAAMfAAkKBwfoBADgAAAfAAkK9gboBADgAAAgAAYKIwRZKgDVAAAAAA==.Sarmuc:BAABNQAECn85AAIZAAoKcxaECQDdAgAZAAoKcxaECQDdAgAAAA==.Saryda:BAAANQAECgQIDgAAAA==.Sauda:BAAANQAECgUICAAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQAECgQIBwAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sellenah:BAAANQADCgQIBAABNQAECgUIBwAIAAAAAA==.Selûne:BAAANQABCggICgAAAA==.Sensu:BAAANQAECgQIDAAAAA==.Serrest:BAAANQAECgUICgAAAA==.Seä:BAABNQAECn8lAAITAAcKGRgZVQAaAgATAAcKGRgZVQAaAgAAAA==.',
Sh='Shacktown:BAAANQABCgYICQAAAA==.Shadowdoh:BAAANQAECgYIDAAAAA==.Shapzan:BAAANQAECgMICQAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAABNQAECn8qAAIEAAgKMhN5LwAlAQAEAAgKMhN5LwAlAQAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAABNQAECn8pAAINAAkKdSGwAgBrAgANAAkKdSGwAgBrAgAAAA==.',
Sm='Smalltwngirl:BAABNQAECn8aAAIGAAgKBREyCQCkAQAGAAgKBREyCQCkAQABNQAFFAQIDgAEADgbAA==.',
So='Solaire:BAAANQAECgUIBgAAAA==.Solaspirus:BAAANQAECgUIDAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8sAAMKAAkKXxn5FADKAQAKAAkKXxn5FADKAQALAAUKmQUkUADRAAAAAA==.Sonofagun:BAAANQAECgYIBgAAAA==.',
Sp='Spectors:BAABNQAECn8qAAQnAAgKOQY7DgBvAQAnAAcKoAY7DgBvAQAiAAcKHwPs5wD5AAAXAAEKAAA5hQAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgUICwAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgMIAgAAAA==.',
Sw='Sweetstorm:BAABNQAECn8YAAIUAAYKogItbADIAAAUAAYKogItbADIAAAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.Sydley:BAAANQABCgUIBQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAAANQAECgYICwAAAA==.Tarixx:BAAANQAECggIDQAAAA==.Tazanoth:BAABNQAECn8sAAQFAAkKBhodYgBSAgAFAAgKBxsdYgBSAgAmAAgK6BskBgBDAgAkAAYKPQo+RwAiAQAAAA==.',
Te='Tekeela:BAAANQAECggIEAABNQAFFAIIBgAFAJsdAA==.Tekeelà:BAACNQAFFH8GAAIFAAIKmx3hIACvAAAFAAIKmx3hIACvAAA1AAQKfzUAAgUACgrzIdgOAGsDAAUACgrzIdgOAGsDAAAA.',
Th='Thalarus:BAAANQADCgIIBQABNQADCgcICgAIAAAAAA==.Thalion:BAAANQAECgUIBQAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Theroux:BAAANQADCggIEAAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAABNQAECn8UAAMTAAcKEwz2rgAiAQATAAcKEwz2rgAiAQARAAEKewYquwEqAAAAAA==.Thobu:BAAANQAECgQIBAAAAA==.Thornscale:BAABNQAECn8dAAQfAAgKVQp3DgBfAQAgAAgKmAeoHQB0AQAfAAcKMgp3DgBfAQAYAAEKJQIMUwAmAAAAAA==.',
Ti='Tigolcrittys:BAAANQADCggIEQABNQAECgoKIgAFAB4bAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAAANQAECgcIDQAAAA==.Totem:BAAANQAECgIIAgAAAA==.Tovê:BAAANQAECgcIDQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMXAAgKzCCABADhAgAXAAgKzCCABADhAgAnAAMKQBLkGQC3AAAAAA==.',
Tu='Turger:BAAANQAECgEIAQABNQAECgYIGAAEAGwdAA==.',
Va='Vaeluptuous:BAABNQAECn8WAAIiAAYKBxHaQAAMAQAiAAYKBxHaQAAMAQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8pAAMXAAoKGCC2BADaAgAXAAgKSh62BADaAgAiAAkKqxpaNAAsAQAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgYIDAAAAA==.Varaine:BAAANQADCgYICwABNQAECgcIFwAUAEERAA==.',
Ve='Veebs:BAAANQAECgUJBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECn8pAAIlAAoKkQyNCACHAQAlAAoKkQyNCACHAQAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAIUAAgKMR2PIQCPAgAUAAgKMR2PIQCPAgAAAA==.',
Wa='Wanagi:BAAANQAECgQICAAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8fAAIMAAgKeQ1TpwC7AQAMAAgKeQ1TpwC7AQAAAA==.Warriorguyes:BAABNQAECn8ZAAIMAAgKyBsXagBSAgAMAAgKyBsXagBSAgAAAA==.',
Wh='Whomper:BAAANQAECgQIBAAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAAANQAECgYIDAAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn8oAAINAAkK2w7jDACAAQANAAkK2w7jDACAAQAAAA==.',
Wo='Womphunt:BAABNQAECn8dAAIFAAgK8xRaKgByAQAFAAgK8xRaKgByAQAAAA==.',
Wu='Wulyn:BAAANQAECgMICQAAAA==.',
Wy='Wylla:BAABNQAECn8aAAIbAAUKiw2RRAD2AAAbAAUKiw2RRAD2AAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xs='Xsuns:BAABNQAECn8eAAIGAAgKxBdlIgATAgAGAAgKxBdlIgATAgAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQADCgQIBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgQICAAAAA==.Zarathiel:BAABNQAECn8YAAIMAAkKHAxEnwDOAQAMAAkKHAxEnwDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn8gAAInAAcKdgZFDwBbAQAnAAcKdgZFDwBbAQAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggIDAAAAA==.',
['Ëd']='Ëddìë:BAAANQADCggICAABNQAECgkJLQAQADsbAA==.',
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
