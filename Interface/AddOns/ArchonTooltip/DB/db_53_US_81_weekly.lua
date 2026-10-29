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

local lookup = {'Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Monk-Brewmaster','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Warlock-Demonology','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aakai:BAABNQAECn87AAQBAAoKbxwwFwBlAgACAAgKoBldBgBsAgABAAoKEhowFwBlAgADAAIKEQpFOwB/AAAAAA==.Aarmorr:BAABNQAECn8yAAIEAAkKigltTQBgAQAEAAkKigltTQBgAQAAAA==.',
Ac='Acinianis:BAAANQAECgEIAgAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgcICwAAAA==.Adsdad:BAAANQAECgQIBQAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgQIBQAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICgAAAA==.',
Al='Alcarza:BAAANQAECgEIAQAAAA==.Alchon:BAABNQAECn8kAAIFAAgK0xp7UwB2AgAFAAgK0xp7UwB2AgAAAA==.Alicalsastre:BAAANQAECggIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAABNQAECn8pAAMGAAgK8w6GJQAxAQAGAAgK8w6GJQAxAQAHAAUKzgS0hAC/AAAAAA==.Alonjurah:BAAANQAECgEIAQAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgYIBgAAAA==.',
Am='Amaith:BAAANQAECgQJDAAAAA==.Amantillado:BAAANQAECgIIBAABNQAECgYIDwAIAAAAAA==.Amata:BAAANQAECgQIBgAAAA==.Amblance:BAAANQAECggICwAAAA==.Amelianne:BAAANQAECgMIBwAAAA==.Amerria:BAAANQABCgMIAwAAAA==.Ammastary:BAAANQAECgQIBwAAAA==.Ammonfrey:BAAANQADCgUIBQAAAA==.',
An='Andrea:BAABNQAECn8pAAIJAAkKnxEjCgCcAQAJAAkKnxEjCgCcAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8iAAMKAAkKMREgSgCIAQAKAAkKMREgSgCIAQALAAQKUQdEVgCzAAAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQAECgEIAgAAAA==.Archonsfury:BAAANQAECgYICQAAAA==.Ardagg:BAAANQAECgEIAgAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8dAAIMAAoK/ha7bwBEAgAMAAoK/ha7bwBEAgAAAA==.',
As='Ashentris:BAAANQAECgUIDQAAAA==.Asnew:BAABNQAECn8pAAINAAoKDw6uOAABAQANAAoKDw6uOAABAQAAAA==.Asura:BAABNQAECn8ZAAMOAAkKexMEUQDPAQAOAAgKNhMEUQDPAQAPAAIKvA1XlwBmAAAAAA==.',
At='Athelstan:BAABNQAECn8WAAILAAcK5wpdQAAsAQALAAcK5wpdQAAsAQAAAA==.Atonement:BAAANQADCgIIAgABNQAECgkJNAAQAEUdAA==.',
Au='Aumaril:BAAANQAECggIDQAAAA==.Aumaryl:BAABNQAECn8dAAMBAAoKUxcuFABHAgABAAoKUxcuFABHAgADAAIKOg3CWAA4AAAAAA==.Auralynn:BAAANQAECgcIEgAAAA==.Auroriana:BAAANQAECgEIAQAAAA==.',
Av='Averus:BAABNQAECn8zAAIHAAkKDwloKgA2AQAHAAkKDwloKgA2AQAAAA==.',
Az='Azariel:BAABNQAECn8iAAMRAAgKJhJ2mgDuAQARAAgKJhJ2mgDuAQAQAAEKAAB7dQAnAAAAAA==.Azatre:BAAANQAECgEIAQAAAA==.Azuriah:BAABNQAECn8yAAIQAAkKrhlLDQDOAQAQAAkKrhlLDQDOAQAAAA==.',
Ba='Baane:BAAANQAECgQIBgABNQAECgUIFgASABwOAA==.Babnik:BAEBNQAECn8bAAIFAAcKPg75rwCkAQAFAAcKPg75rwCkAQAAAA==.Balderdashe:BAAANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAABNQAECn8sAAMSAAkKOhvtAwCBAQAKAAkKQRq7VAAlAgASAAcKjxLtAwCBAQAAAA==.Belaim:BAAANQAECgEIAQAAAA==.Belovis:BAACNQAFFH8SAAIRAAUK+hqTCgCfAQARAAUK+hqTCgCfAQA1AAQKfzQAAhEACgouJEIIADcDABEACgouJEIIADcDAAAA.Betsea:BAAANQADCgcIBwABNQAECggIJgATAKcWAA==.',
Bi='Bidock:BAAANQAECgUIBgAAAA==.Bidoof:BAABNQAECn8hAAIUAAoKBwzAIgB/AQAUAAoKBwzAIgB/AQAAAA==.Bigblunt:BAAANQADCgUIBgAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn8tAAIVAAkKLx2zBQD3AQAVAAkKLx2zBQD3AQAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAABNQAECn8YAAMTAAcKxxEddADmAAATAAUKSQ8ddADmAAAQAAYKvgZuTwCpAAAAAA==.',
Bo='Boggrog:BAABNQAECn8WAAMWAAUKHBD8IgB4AAAMAAUKegvfvACSAAAWAAMKhRP8IgB4AAAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUIDgAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgUICwAAAA==.Bordeaux:BAAANQAECgMIBwABNQAECgYIFQALAFAZAA==.Bosshog:BAABNQAECn8mAAMXAAgKYgrBTgAhAQAXAAgKYgrBTgAhAQAEAAEKdgH/3AAaAAAAAA==.',
Br='Brabanzio:BAABNQAECn8UAAIKAAcKwhUcjwBpAQAKAAcKwhUcjwBpAQABNQAECgoKNAAEAJkcAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgIIBQAAAA==.Brotato:BAAANQABCgcICwABNQAECgcIDQAIAAAAAA==.Brotatochip:BAAANQAECgcIDQAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAABNQAECn8cAAITAAoKhxo3DQD5AgATAAoKhxo3DQD5AgAAAA==.Burningblunt:BAAANQAECgYIDQAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQAECgcIDwABNQAECggIFQAYAPcEAA==.Castle:BAABNQAECn8WAAMRAAUKqAtFNQHKAAARAAUKqAtFNQHKAAATAAQKYgrT5AC3AAAAAA==.Catsinhats:BAAANQADCggIDQABNQAECgoKOQAOAHYcAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgoKOQAOAHYcAA==.',
Ce='Cecelya:BAABNQAECn8mAAMKAAoKZRlJPwBuAgAKAAoKZRlJPwBuAgALAAEKyAXARwA2AAAAAA==.',
Ch='Chablis:BAAANQAECgEIAwAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwAUADEdAA==.Chillpills:BAAANQABCgIIAgAAAA==.Chivactdl:BAAANQADCgYJCgABNQAECgkJMQAEACcSAA==.Chosenn:BAAANQAECgUIDQAAAA==.Chotek:BAAANQAECgUIEgAAAA==.Chunknoriss:BAABNQAECn8WAAMZAAYKYRdCEQBlAQAZAAYKYRdCEQBlAQAaAAEKAACUdwAgAAABNQAECgkJMQAEACcSAA==.',
Ci='Cilarnen:BAABNQAECn8UAAMTAAYKyQ/VrwAgAQATAAYKyQ/VrwAgAQARAAQKmQa7AgF7AAAAAA==.',
Cl='Claudiuss:BAAANQAECgUIBgABNQAECgoKNAAEAJkcAA==.Clure:BAABNQAECn8sAAITAAoK1yH9CgAXAwATAAoK1yH9CgAXAwABNQAECgoKOQAbAEQdAA==.Clurelock:BAAANQAECgIIAwABNQAECgoKOQAbAEQdAA==.Clurethyr:BAABNQAECn85AAIbAAoKRB1GBQC1AgAbAAoKRB1GBQC1AgAAAA==.',
Co='Conchobhar:BAAANQAECgYIBwAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8NAAMKAAUKdw17EwBvAQAKAAUKdw17EwBvAQALAAEKAAByGABEAAA1AAQKfzYAAwoACgrkFkcfAGcCAAoACQrOGEcfAGcCAAsACAq2HYshACoCAAAA.Corrosion:BAABNQAECn8mAAIcAAoK1Rz+BgASAwAcAAoK1Rz+BgASAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAIRAAUKIxPB8QA5AQARAAUKIxPB8QA5AQABNQAECgYIDgAIAAAAAA==.Crylessplz:BAAANQAECgYIDAABNQAECgkJNAAQAEUdAA==.',
Ct='Cthuwu:BAAANQAECggICwABNQAFFAQICgAFAJsaAA==.',
Cv='Cvhamster:BAAANQAECgEIAQAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8nAAMdAAoK6BinDADqAQAJAAgKnxq+CwBvAgAdAAkK+BOnDADqAQAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAABNQAECn8ZAAIFAAgKUxMJbQBeAQAFAAgKUxMJbQBeAQAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQAECgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgYIBwAAAA==.Darkkromdor:BAABNQAECn8qAAIRAAoKYhq0YgByAgARAAoKYhq0YgByAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8nAAIUAAkKahjkJwBfAgAUAAkKahjkJwBfAgAAAA==.Deathcat:BAABNQAECn85AAMOAAoKdhweLgB5AgAOAAoKdhweLgB5AgAPAAYKPgthYQAfAQAAAA==.Deathkiss:BAAANQAECgMJBQAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgQIBgAAAA==.Decayy:BAABNQAECn8mAAINAAoKhhi2LQBeAgANAAoKhhi2LQBeAgAAAA==.Dedbull:BAAANQAECgEIAgAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQAECgEIAgAAAA==.Des:BAAANQAECgEIAQAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn8tAAILAAkKOhMjEgCpAQALAAkKOhMjEgCpAQAAAA==.',
Do='Dolemite:BAABNQAECn8iAAMZAAkKFhBqDwCIAQAZAAkKFhBqDwCIAQAaAAUKVg/MRQDuAAAAAA==.Donalbain:BAABNQAECn80AAIEAAoKmRwoFwCLAgAEAAoKmRwoFwCLAgAAAA==.Donninban:BAAANQAECgYIEgAAAA==.Doodoobutter:BAAANQAECgIIAwABNQAECgoKKgAeAKMYAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAAANQAECgUIDgAAAA==.Drizzeh:BAAANQABCggIEAAAAA==.Drugoja:BAAANQADCgcICAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgIIAgAAAA==.',
Ea='Eas:BAAANQADCgUIBQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQAECgUIBwAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eloweñ:BAAANQAECgEIAgAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn80AAINAAoKmhWVGADVAQANAAoKmhWVGADVAQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8eAAIHAAkKFQjbVgB7AQAHAAkKFQjbVgB7AQAAAA==.Emìly:BAABNQAECn8wAAMZAAkKjBQFHADEAQAZAAcKYxYFHADEAQAaAAkK+xPMEwCqAQAAAA==.',
En='Entaria:BAAANQAECgUICQAAAA==.',
Ep='Ephria:BAABNQAECn8uAAMEAAoKiSQZEABDAwAEAAoKiSQZEABDAwAXAAEKAACXTQEnAAAAAA==.Episkey:BAAANQAECgQIDAAAAA==.',
Er='Eroversion:BAABNQAECn8UAAMGAAYK4xFiPgAxAQAGAAUK0RNiPgAxAQAdAAUKFwysOAB6AAABNQAECgoKUgAWAKkbAA==.Eroward:BAABNQAECn9SAAIWAAoKqRvUBABWAgAWAAoKqRvUBABWAgAAAA==.',
Es='Esmay:BAABNQAECn8oAAIXAAkKvQ8wRABEAQAXAAkKvQ8wRABEAQAAAA==.',
Et='Ethren:BAABNQAECn8zAAIDAAkKEBIKDAC+AQADAAkKEBIKDAC+AQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMIAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fangsofblood:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAABNQAECn8nAAIYAAgKlR2rCAByAgAYAAgKlR2rCAByAgAAAA==.Feliri:BAAANQAECgIIAgAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQAECgEIAQAAAA==.Filgulfin:BAABNQAECn82AAIFAAoKdhmZJQBNAgAFAAoKdhmZJQBNAgAAAA==.Finkate:BAAANQAECgcICQAAAA==.Firebringer:BAABNQAECn8cAAIfAAoKdAhcFwCAAQAfAAoKdAhcFwCAAQAAAA==.Fistmegently:BAAANQADCggICAAAAA==.',
Fl='Flamehunter:BAAANQAECgQICwAAAA==.Flo:BAABNQAECn8+AAQLAAoKMhQtIwAZAgALAAoKMhQtIwAZAgASAAgKZw0BBAB8AQAKAAMKvgM6pAB+AAAAAA==.Floki:BAABNQAECn8WAAMWAAcKGxFkHQBsAQAWAAcKGxFkHQBsAQAMAAUKlAeG9wDuAAAAAA==.Flokin:BAAANQAECgIIAwAAAA==.Flowing:BAABNQAECn8wAAQgAAgKAxUgCAAbAgAgAAgKAxUgCAAbAgAbAAYKIwcqMgAIAQAhAAQKfATALwCcAAAAAA==.',
Fo='Foods:BAABNQAECn8/AAQMAAoK7w7rTACeAQAMAAoKnw3rTACeAQAWAAUKWg2ELQDJAAAiAAIKUAtdLwBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQIBwAAAA==.',
['Fæ']='Fæ:BAAANQAECgEIAQAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAABNQAECn8ZAAIRAAcKfhP3ygCGAQARAAcKfhP3ygCGAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAABNQAECn8iAAIFAAgKzBfsUQCnAQAFAAgKzBfsUQCnAQAAAA==.',
Gl='Glasgoww:BAAANQAECgEIAQABNQAECgoKNAAEAJkcAA==.Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgQIBQAAAA==.',
Go='Goburina:BAABNQAECn8vAAIEAAoKvRC6PgCcAQAEAAoKvRC6PgCcAQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gr='Gryffen:BAAANQABCgcICQAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECn8mAAIFAAoKORuZTwCAAgAFAAoKORuZTwCAAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8zAAQgAAkK1A9IBgB0AQAgAAkKEw9IBgB0AQAhAAYKow3hHwBYAQAbAAUKzgRgOwC+AAAAAA==.Hallowed:BAAANQADCgUIBQAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn86AAIWAAoKgxiGBwDsAQAWAAoKgxiGBwDsAQAAAA==.',
He='Healortank:BAAANQAECgEIAgAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgQIBgAAAA==.',
Hi='Hircine:BAAANQAECgEIAgAAAA==.',
Ho='Holysea:BAAANQAECgIIBAABNQAECggIJgATAKcWAA==.Honk:BAAANQAECgQIBAAAAA==.',
Im='Imwithfloki:BAABNQAECn8cAAQdAAYKXhraHgCoAQAdAAYKXhraHgCoAQAJAAEKAAC1OwBLAAAGAAEKhhAlWgAxAAAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUICAAAAA==.Isamidor:BAABNQAECn8mAAIFAAkK6SW2CACXAwAFAAkK6SW2CACXAwAAAA==.Ismokeu:BAABNQAECn8rAAMKAAoKKRnCSABMAgAKAAoKKRnCSABMAgALAAEKAADRVgAAAAAAAA==.Ismyn:BAAANQAECgMIBAAAAA==.Istran:BAAANQAECgcIDAAAAA==.',
Iv='Ivrys:BAAANQAECgcIEAAAAA==.',
Iw='Iwillbethere:BAAANQAECgMIBQAAAA==.',
Ja='Jackoneal:BAABNQAECn8ZAAMRAAcKkQNJGAH3AAARAAcKkQNJGAH3AAAQAAEKAABnfwAdAAAAAA==.Jalidelo:BAABNQAECn8jAAIKAAgKHRU6WgATAgAKAAgKHRU6WgATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQAECgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn8yAAIjAAoKbhuzHwBAAgAjAAoKbhuzHwBAAgAAAA==.Jokersfists:BAAANQAECggIEAABNQAECggIHQAkADUNAA==.Jokersmage:BAABNQAECn8dAAIkAAgKNQ0gbwBoAQAkAAgKNQ0gbwBoAQAAAA==.Joraflheim:BAAANQAECgEIBAAAAA==.Joranbragi:BAABNQAECn8bAAIRAAYKMQPR+ACIAAARAAYKMQPR+ACIAAAAAA==.Jordanjr:BAABNQAECn88AAMlAAoKaxeeDgDhAQAFAAoKOBL3TACHAgAlAAoK/hCeDgDhAQAAAA==.Josunlee:BAAANQAECggICwAAAA==.Jotoonice:BAABNQAECn8mAAMVAAoKuBGtFgBIAQAVAAYKlxStFgBIAQAkAAcKTwioRwEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8MAAMlAAUKbQ8jEwAOAQAlAAQKtw4jEwAOAQAFAAIKJQ27IABaAAA1AAQKfzYAAyUACgpzHXccAG8CACUACgp+FXccAG8CAAUABArvIWWAADIBAAAA.',
Ju='Juicyfruit:BAAANQABCgYICQAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECn8zAAIFAAkKIBITQADjAQAFAAkKIBITQADjAQAAAA==.Kaedina:BAABNQAECn8WAAMKAAoKNguxbADYAQAKAAoKNguxbADYAQALAAIKzwuGRAA8AAABNQAECgoKPAAlAGsXAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgEIAQABNQADCgcICgAIAAAAAA==.Karvel:BAABNQAECn8fAAINAAgKEhyXLwBUAgANAAgKEhyXLwBUAgAAAA==.Katally:BAAANQAECgEIAQAAAA==.Kaychow:BAAANQAECgQICgABNQAECgkJJgATAFUeAA==.Kaydullz:BAABNQAECn8WAAIKAAoKtBWUJQA9AgAKAAoKtBWUJQA9AgAAAA==.',
Kc='Kchowchow:BAAANQAECgUICgABNQAECgkJJgATAFUeAA==.',
Ke='Kelonaar:BAACNQAFFH8QAAMXAAQKTxbOCQDpAAAXAAQKTxbOCQDpAAAEAAIKuAPWJgBuAAA1AAQKfykAAxcACgpsHmojAPkCABcACgpsHmojAPkCAAQAAwqgFPLiAKQAAAAA.Keloni:BAAANQAECgYIBwABNQAFFAQIEAAXAE8WAA==.Kenack:BAAANQAECgQIDAAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.',
Ki='Killermoomoo:BAAANQAECgQIBgAAAA==.',
Kl='Kloverr:BAAANQAECgYIEQAAAA==.Klub:BAAANQAECgEIAQAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUICQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBwAAAA==.Krooler:BAAANQAECgMJBQAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAAANQAECgYIEAAAAA==.Lanval:BAABNQAECn87AAIRAAoKAhmENwAbAgARAAoKAhmENwAbAgAAAA==.Latinlover:BAAANQAECgIIAwAAAA==.Laurian:BAAANQAECgEIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn9BAAIdAAoKWRpnDQCQAgAdAAoKWRpnDQCQAgAAAA==.Leftblank:BAAANQAECgQIBQAAAA==.',
Li='Lich:BAAANQAECgQIBQAAAA==.Lighthugger:BAABNQAECn82AAIRAAoK/xh6PQAFAgARAAoK/xh6PQAFAgAAAA==.Lilyoptra:BAABNQAECn8UAAIjAAYKCQOIvgB2AAAjAAYKCQOIvgB2AAABNQAECgYIFAATAMkPAA==.Liqmycrits:BAAANQADCggIGwAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgcIHAAUAGMRAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAIAAAAAA==.',
Lo='Lockpockets:BAABNQAECn8XAAIjAAcKsQmygQDxAAAjAAcKsQmygQDxAAAAAA==.Loriane:BAAANQAECgIIAwABNQAECggIFAAEAGkjAA==.Lorianth:BAABNQAECn84AAIlAAoK6g8tEQCyAQAlAAoK6g8tEQCyAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgYIAwAAAA==.',
Lu='Lucifér:BAAANQABCggICgAAAA==.Lundigras:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQAECgQIBgAAAA==.Lylora:BAABNQAECn9FAAIGAAoK/yW8AAAPBAAGAAoK/yW8AAAPBAAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8qAAMKAAoKUxX1UgAqAgAKAAoKUxX1UgAqAgALAAUKIQVjNAB9AAAAAA==.',
['Lô']='Lôki:BAAANQAECgIIAgAAAA==.',
Ma='Madclaws:BAABNQAECn8+AAMHAAoK2RslDwBVAgAHAAkK0h0lDwBVAgAdAAcKJhgjGgDWAQAAAA==.Madman:BAAANQAECgQIEQAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgoKKAAMADIMAA==.Malala:BAAANQADCgYIEgABNQAECgoKQwAKAP4aAA==.Malyndra:BAAANQAECgUICAABNQAECgYIDwAIAAAAAA==.Mantre:BAAANQAECgEIAQAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8gAAIjAAgKdQiYnQCcAQAjAAgKdQiYnQCcAQAAAA==.Masy:BAAANQAECgYIBwAAAA==.',
Me='Mesmash:BAABNQAECn8lAAIWAAgKoyEmBwD3AQAWAAgKoyEmBwD3AQAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDgABNQAECgYIDwAIAAAAAA==.Metatotem:BAAANQAECgYIBgABNQAECgYIDwAIAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIBQAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECgUICgABNQAECgkJLAAKAF8ZAA==.Miniborg:BAAANQAECgYIDgAAAA==.Minidude:BAAANQAECggIEgAAAA==.Misfire:BAAANQAECgEIAgAAAA==.Mistycrusade:BAAANQAECgQICgAAAA==.Mizzen:BAABNQAECn8nAAMOAAoKHRuZDABUAgAOAAoKHRuZDABUAgANAAIKpQzytABfAAABNQAFFAUIDgALANcRAA==.',
Mo='Moejojojo:BAABNQAECn8YAAIaAAcKwB/pHgA5AgAaAAcKwB/pHgA5AgAAAA==.Moofasaha:BAABNQAECn8bAAQEAAYKjx+3YgDlAQAEAAYKjx+3YgDlAQAXAAQKggjS+wCbAAAcAAEKSgi6KAA/AAAAAA==.Morog:BAABNQAECn8UAAMFAAgKHB8rOwC4AgAFAAgKHB8rOwC4AgAlAAEKAACNigA0AAAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAABNQAECn8XAAIkAAcKXQjPMAE7AQAkAAcKXQjPMAE7AQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgUICAABNQAFFAEIAQAIAAAAAA==.',
['Mã']='Mãrshy:BAABNQAECn8bAAIKAAgKgB6IOgB/AgAKAAgKgB6IOgB/AgABNQAFFAEIAQAIAAAAAA==.',
['Mä']='Märshy:BAAANQAECgQICgABNQAFFAEIAQAIAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICgAAAA==.Nanarus:BAABNQAECn9DAAMKAAoK/hp8GQCVAgAKAAoK/hp8GQCVAgALAAEKfQRcTgAgAAAAAA==.Nashalie:BAABNQAECn8xAAMjAAgKWCOjGAAlAwAjAAgKWCOjGAAlAwAYAAIKOgzdVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAABNQAECn8VAAIEAAcKZxnGigBuAQAEAAcKZxnGigBuAQAAAA==.Neverfrozen:BAAANQAECgQIBAAAAA==.Nexbasia:BAABNQAECn8sAAIJAAkK5Q9yEQDrAQAJAAkK5Q9yEQDrAQAAAA==.',
Ni='Nickyboy:BAAANQAECgMIBAAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIBAAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBgAAAA==.',
Oc='Octt:BAAANQAECgYIDAAAAA==.',
Ol='Oldcannabis:BAABNQAECn8cAAIFAAgKyQotmQDVAQAFAAgKyQotmQDVAQAAAA==.',
Om='Ominis:BAAANQADCgQIBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAABNQAECn8bAAQQAAUKkhUGQAD6AAAQAAUKkhUGQAD6AAARAAQKbQGShQFSAAATAAIKuwFuHgE4AAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAILAAQKdBpcCgBTAQALAAQKdBpcCgBTAQA1AAQKfxwAAgsACQpNIisRAOgCAAsACQpNIisRAOgCAAAA.',
Oz='Ozo:BAAANQAECgQIDgAAAA==.',
Pa='Paiva:BAAANQAECgMIAwAAAA==.Palandor:BAAANQAECgEIAQAAAA==.Pallydoof:BAAANQADCggICQAAAA==.Pallyscorned:BAABNQAECn8rAAIQAAoKmxc3DADmAQAQAAoKmxc3DADmAQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECggIEwAIAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Pandaria:BAAANQADCggICAAAAA==.Panduh:BAABNQAECn8xAAMaAAkKZiEPCwAjAwAaAAkKECEPCwAjAwAeAAcKjx+bDgAKAgAAAA==.',
Ph='Phenixy:BAAANQAECgQIBgAAAA==.Phoebell:BAAANQAECgYIDAAAAA==.Phoinix:BAAANQADCggIDgAAAA==.',
Pi='Pinkducky:BAAANQAECgEIAQAAAA==.',
Pl='Plen:BAAANQAECgIIAwABNQAECgkJLAAKAF8ZAA==.',
Po='Ponyo:BAABNQAECn8yAAIKAAoKFSOfDQAOAwAKAAoKFSOfDQAOAwAAAA==.Poppyseed:BAAANQAECgYIBgAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pr='Prinnce:BAAANQAECgQICAABNQAECgkJMAAZAIwUAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8bAAMlAAcK4hB2OACMAQAlAAcKARB2OACMAQAFAAMK1hF5HgHAAAAAAA==.',
Ra='Raddra:BAAANQAECgUICQAAAA==.Raddrah:BAAANQAECgMIBwAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radmuster:BAAANQADCgcIBwABNQAECgkJGgALALQSAA==.Radra:BAABNQAECn8mAAIfAAgKwxBsIAAlAQAfAAgKwxBsIAAlAQAAAA==.Raeku:BAABNQAECn8rAAImAAoKVB2cAQCcAgAmAAoKVB2cAQCcAgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBwAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn8yAAIKAAoKax5DBgCCAwAKAAoKax5DBgCCAwAAAA==.Redhaven:BAABNQAECn8YAAIKAAoKCAsIQQCvAQAKAAoKCAsIQQCvAQAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECn8zAAIRAAkKBA+1aACFAQARAAkKBA+1aACFAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAgAAAA==.Ronfax:BAACNQAFFH8QAAIEAAUKLhnDBgCTAQAEAAUKLhnDBgCTAQA1AAQKfzQAAgQACgrgIFoSADUDAAQACgrgIFoSADUDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgYIDQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAIAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgkJMQAaAGYhAA==.',
Ry='Ryllae:BAAANQAECgEIAQABNQAECggIIwAUADEdAA==.Ryuu:BAAANQAECgIIBgAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8cAAMnAAoKXwgIGgC2AAAjAAoK/AfaqwB7AQAnAAQKuwYIGgC2AAABNQAECgoKJgAFADkbAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgoKJgAFADkbAA==.',
Sa='Saint:BAABNQAECn8oAAMRAAgKJRMcwACcAQARAAcKWRYcwACcAQATAAgK3RNCjwBwAQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarandria:BAAANQAECgQIBAABNQAECggIEQAIAAAAAA==.Sarinae:BAABNQAECn8lAAMgAAkKBwexEAAsAQAgAAkK9gaxEAAsAQAhAAYKIwRZKgDVAAAAAA==.Sarmuc:BAABNQAECn8+AAIcAAoKaxiECQDdAgAcAAoKaxiECQDdAgAAAA==.Saryda:BAABNQAECn8VAAMLAAYKUBmHNQB3AQALAAUKkRaHNQB3AQAKAAEK1wKpzQAsAAAAAA==.Sauda:BAAANQAECgUICwAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAgAAAA==.Scubagal:BAAANQAECgYIDAAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sellenah:BAAANQADCgUIBAABNQAECgUICwAIAAAAAA==.Selûne:BAAANQABCggICgAAAA==.Sensu:BAABNQAECn8WAAISAAUKHA6oBgD4AAASAAUKHA6oBgD4AAAAAA==.Serrest:BAAANQAECgYICwAAAA==.Seä:BAABNQAECn8mAAITAAgKpxYZVQAaAgATAAgKpxYZVQAaAgAAAA==.',
Sh='Shacktown:BAAANQAECgEIBAAAAA==.Shadowdoh:BAAANQAECgYIDwAAAA==.Shapzan:BAAANQAECgQIEAAAAA==.Sharks:BAAANQAECgQJCAAAAA==.Shivant:BAABNQAECn8xAAIEAAkKJxLHUgBMAQAEAAkKJxLHUgBMAQAAAA==.',
Si='Silendreas:BAAANQAECgEIAQAAAA==.',
Sl='Sloth:BAABNQAECn8yAAINAAoKgCFsCQC3AgANAAoKgCFsCQC3AgAAAA==.',
Sm='Smalltwngirl:BAABNQAECn8aAAIGAAgKBRFZGwCMAQAGAAgKBRFZGwCMAQABNQAFFAUIEAAEAC4ZAA==.',
So='Solaire:BAAANQAECgQICQAAAA==.Solaspirus:BAAANQAECgYIEAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8sAAMKAAkKXxkUKgDBAgAKAAkKXxkUKgDBAgALAAUKmQUkUADRAAAAAA==.Sonofagun:BAAANQAECgYIBwAAAA==.',
Sp='Spectors:BAABNQAECn8rAAQnAAkKSgY7DgBvAQAnAAgKowY7DgBvAQAjAAcKHwPs5wD5AAAYAAEKAAA5hQAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgYIEwAAAA==.Strykah:BAAANQAECgEIAQAAAA==.Stumpypete:BAAANQAECgEIAwAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgMIBQAAAA==.',
Sw='Sweetstorm:BAABNQAECn8eAAIUAAYKwgItbADIAAAUAAYKwgItbADIAAAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.Sydley:BAAANQABCgUIBQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAAANQAECgcIEwAAAA==.Tarixx:BAABNQAECn8VAAMRAAgKlB3aQQD1AQARAAgKKBraQQD1AQAQAAYKVyB1JQC0AQAAAA==.Tazanoth:BAABNQAECn8tAAQFAAkKqhodYgBSAgAFAAkKPBkdYgBSAgAmAAgK6BskBgBDAgAlAAYKPQo+RwAiAQAAAA==.',
Te='Tekeela:BAABNQAECn8cAAIFAAoKJBuvGACSAgAFAAoKJBuvGACSAgABNQAFFAQICgAFAJsaAA==.Tekeelà:BAACNQAFFH8KAAIFAAQKmxrZCwD1AAAFAAQKmxrZCwD1AAA1AAQKfz4AAgUACgrzIdgOAGsDAAUACgrzIdgOAGsDAAAA.',
Th='Thalarus:BAAANQADCgIIBQABNQADCgcICgAIAAAAAA==.Thalion:BAAANQAECgUIBgAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Theroux:BAAANQAECgEIAQAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAABNQAECn8XAAMTAAcKWQ6rbQD5AAATAAcKWQ6rbQD5AAARAAEKewYquwEqAAAAAA==.Thobu:BAAANQAECgQIBAAAAA==.Thornscale:BAABNQAECn8fAAQgAAkKVwl3DgBfAQAhAAgKmAeoHQB0AQAgAAgKDwl3DgBfAQAbAAEKJQIMUwAmAAAAAA==.',
Ti='Tigolcrittys:BAAANQADCggIEQABNQAECgoKJgAFADkbAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAABNQAECn8VAAIEAAgKJxpVKwD8AQAEAAgKJxpVKwD8AQAAAA==.Totem:BAAANQAECgUIBwAAAA==.Tovê:BAABNQAECn8WAAMEAAkKiBVJIABDAgAEAAkKiBVJIABDAgAXAAUKAwuaxwADAQAAAA==.',
Tr='Traumajazz:BAAANQAECgEIAQAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMYAAgKzCCABADhAgAYAAgKzCCABADhAgAnAAMKQBLkGQC3AAAAAA==.Trxcy:BAAANQADCgMIAwAAAA==.',
Tu='Turger:BAAANQAECgEIAgABNQAECgYIGwAEAI8fAA==.',
Um='Umbrafang:BAAANQAECgEIAQAAAA==.',
Va='Vaeluptuous:BAABNQAECn8bAAIjAAYKihJAewABAQAjAAYKihJAewABAQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8rAAMYAAoKwSC2BADaAgAYAAgKSh62BADaAgAjAAkKbBvlYQAzAgAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECggIEgAAAA==.Varaine:BAAANQADCgYICwABNQAECgcIHAAUAGMRAA==.',
Ve='Veebs:BAAANQAECgYIBwAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECn8zAAIfAAoKpRIXDwD4AQAfAAoKpRIXDwD4AQAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAIUAAgKMR2PIQCPAgAUAAgKMR2PIQCPAgAAAA==.',
Wa='Wanagi:BAAANQAECgUIEQAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8oAAIMAAoKMgwDUQCQAQAMAAoKMgwDUQCQAQAAAA==.Warriorguyes:BAABNQAECn8hAAIMAAgK2RzMQwC/AQAMAAgK2RzMQwC/AQAAAA==.',
We='Weewillywnky:BAAANQAECgEIAQAAAA==.',
Wh='Whomper:BAAANQAECgQIBgAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAABNQAECn8ZAAIXAAgKVQxRYADsAAAXAAgKVQxRYADsAAAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn8xAAINAAkKxRAQJAB0AQANAAkKxRAQJAB0AQAAAA==.',
Wo='Womphunt:BAABNQAECn8jAAIFAAkKlhUaUACsAQAFAAkKlhUaUACsAQAAAA==.',
Wu='Wulyn:BAAANQAECgUIEQAAAA==.',
Wy='Wylla:BAABNQAECn8cAAIaAAYK0QuRRAD2AAAaAAYK0QuRRAD2AAAAAA==.',
Xa='Xalethra:BAAANQAECgQICAAAAA==.',
Xe='Xenophobias:BAAANQAECgcICQAAAA==.',
Xs='Xsuns:BAABNQAECn8nAAIGAAkK0RdlIgATAgAGAAkK0RdlIgATAgAAAA==.',
Yv='Yve:BAAANQAECgMICAAAAA==.',
Za='Zabberz:BAAANQAECgMIBwAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgYIEgAAAA==.Zarathiel:BAABNQAECn8cAAIMAAoKAQ1EnwDOAQAMAAoKAQ1EnwDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn8oAAInAAgKCQZbCQANAQAnAAgKCQZbCQANAQAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggIDQAAAA==.',
['Ëd']='Ëddìë:BAAANQAECgEIAgABNQAECgkJNAAQAEUdAA==.',
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
