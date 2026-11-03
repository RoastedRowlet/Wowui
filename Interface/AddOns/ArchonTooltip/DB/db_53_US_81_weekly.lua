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

local lookup = {'Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Warlock-Demonology','Mage-Arcane','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aakai:BAABNQAECn9EAAQBAAoKbxyqHQBuAgABAAoKHxqqHQBuAgACAAgKoBldBgBsAgADAAIKEQq+QAB5AAAAAA==.Aarmorr:BAABNQAECn87AAIEAAkKzQlmXgBrAQAEAAkKzQlmXgBrAQAAAA==.',
Ac='Acinianis:BAAANQADCggIEAAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgcICwAAAA==.Adsdad:BAAANQAECgQIBQAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgQIAwAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICgAAAA==.',
Al='Alcarza:BAAANQADCgcICQAAAA==.Alchon:BAABNQAECn8kAAIFAAgK0xp7UwB2AgAFAAgK0xp7UwB2AgAAAA==.Alicalsastre:BAAANQAECggIEAAAAA==.Alista:BAAANQADCgEIAQAAAA==.Allykat:BAABNQAECn8vAAMGAAgK8RDqJAB/AQAGAAgK8RDqJAB/AQAHAAUKzgS0hAC/AAAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgYIBwAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgIIAwABNQAECgYIDwAIAAAAAA==.Amata:BAAANQAECgQIBgAAAA==.Amblance:BAAANQAECggICgAAAA==.Amelianne:BAAANQAECgQIBAAAAA==.Amerria:BAAANQABCgMIAwAAAA==.Ammastary:BAAANQAECgQIBgAAAA==.Ammonfrey:BAAANQADCgUIBQAAAA==.',
An='Andrea:BAABNQAECn8pAAIJAAkKnxGpDwB9AQAJAAkKnxGpDwB9AQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8iAAMKAAkKMRG4YwB4AQAKAAkKMRG4YwB4AQALAAQKUQdEVgCzAAAAAA==.',
Aq='Aqules:BAAANQADCggIDAAAAA==.',
Ar='Arcapeligo:BAAANQADCggIFQAAAA==.Archonsfury:BAAANQAECggIEwAAAA==.Ardagg:BAAANQADCgEIAQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8eAAIMAAoK7Be7bwBEAgAMAAoK7Be7bwBEAgAAAA==.',
As='Ashentris:BAAANQAECgUIEgAAAA==.Asnew:BAABNQAECn8wAAINAAoK4RE3MQBdAQANAAoK4RE3MQBdAQAAAA==.Asura:BAABNQAECn8gAAMOAAoKMBEEUQDPAQAOAAgKNhMEUQDPAQAPAAUKOgk7ZgDFAAAAAA==.',
At='Athelstan:BAABNQAECn8WAAILAAcK5wpdQAAsAQALAAcK5wpdQAAsAQAAAA==.Atonement:BAAANQADCgIIAgABNQAECgoKOQAQAA4dAA==.',
Au='Aumaril:BAAANQAECgcIDAAAAA==.Aumaryl:BAABNQAECn8kAAMBAAoKMRguFABHAgABAAoKMRguFABHAgADAAIKOg3HXAA4AAAAAA==.Auralynn:BAAANQAECgcIEgAAAA==.Auroriana:BAAANQADCgQIBgAAAA==.',
Av='Averus:BAABNQAECn88AAIHAAkKrgl+MgA+AQAHAAkKrgl+MgA+AQAAAA==.',
Az='Azariel:BAABNQAECn8iAAMRAAgKJhJ2mgDuAQARAAgKJhJ2mgDuAQAQAAEKAAB7dQAnAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECn87AAIQAAkKeBzGDgAGAgAQAAkKeBzGDgAGAgAAAA==.',
Ba='Baane:BAAANQAECgQIBgABNQAECgUIGgASABMQAA==.Babnik:BAEBNQAECn8eAAIFAAgK3A35rwCkAQAFAAgK3A35rwCkAQAAAA==.Balderdashe:BAAANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQADCgEIAQAAAA==.Bedhead:BAABNQAECn81AAMSAAkK+xtOBQB/AQAKAAkKAhsHPAASAgASAAcKjxJOBQB/AQAAAA==.Belaim:BAAANQABCgIIAgAAAA==.Belovis:BAACNQAFFH8WAAIRAAUKoxuTCgCfAQARAAUKoxuTCgCfAQA1AAQKfzgAAhEACgrlJDUKADwDABEACgrlJDUKADwDAAAA.Betsea:BAAANQADCgcIBwABNQAECggIJgATAKcWAA==.',
Bi='Bidock:BAAANQAECgUIBAAAAA==.Bidoof:BAABNQAECn8pAAIUAAoK5gxdJgCbAQAUAAoK5gxdJgCbAQAAAA==.Bigblunt:BAAANQADCgUIBgAAAA==.Bigocritties:BAAANQADCgEIAQAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn82AAIVAAkKpB3YCQAwAgAVAAkKpB3YCQAwAgAAAA==.Bixys:BAAANQADCgEIAQAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBgAAAA==.Blackwind:BAAANQADCgEIAQAAAA==.Blokmor:BAABNQAECn8aAAMTAAkK1Q8HbQA8AQATAAcKfw0HbQA8AQAQAAYKvgZuTwCpAAAAAA==.',
Bo='Boggrog:BAABNQAECn8aAAMWAAUKHBAsKwB0AAAMAAUKkwuEzgCkAAAWAAMKhRMsKwB0AAAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUIDwAAAA==.Boneybob:BAAANQADCgEIAQAAAA==.Boras:BAAANQAECgUIBwAAAA==.Bordeaux:BAAANQAECgMIBQABNQAECgYIFgALAOETAA==.Bosshog:BAABNQAECn8tAAMXAAgKrwoBYAArAQAXAAgKrwoBYAArAQAEAAEKdgFd+QAaAAAAAA==.',
Br='Brabanzio:BAABNQAECn8cAAIKAAoKqBIUNgAvAgAKAAoKqBIUNgAvAgABNQAECgoKPgAEACcfAA==.Breadfriend:BAAANQADCggICQAAAA==.Brightnshiny:BAAANQADCgEIAQAAAA==.Broseidon:BAAANQAECgIIAwAAAA==.Brotato:BAAANQADCgEIAQABNQAECgcICwAIAAAAAA==.Brotatochip:BAAANQAECgcICwAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAABNQAECn8jAAITAAoK8Bv6EQABAwATAAoK8Bv6EQABAwAAAA==.Burningblunt:BAAANQAECgYICgAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAABNQAECn8UAAIFAAcKSAf5twD+AAAFAAcKSAf5twD+AAABNQAECggIGQAYAMoFAA==.Castle:BAABNQAECn8bAAMTAAUKJQ/T5AC3AAATAAQKYgrT5AC3AAARAAUKzAwXCwGgAAAAAA==.Catsinhats:BAAANQADCggIDQABNQAECgoKPwAOAHYcAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgoKPwAOAHYcAA==.',
Ce='Cecelya:BAABNQAECn8mAAMKAAoKZRlJPwBuAgAKAAoKZRlJPwBuAgALAAEKyAXEVgAzAAAAAA==.Celerian:BAAANQADCgUIBQAAAA==.',
Ch='Chablis:BAAANQAECgEIAQAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwAUADEdAA==.Chickpea:BAAANQADCgEIAQAAAA==.Chillpills:BAAANQABCgIIAgAAAA==.Chivactdl:BAAANQAECgIIAgABNQAECgoKPQAEAFgRAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAABNQAECn8aAAMHAAgKFBIrKwBuAQAHAAgKFBIrKwBuAQAJAAEKGwzcOwA0AAAAAA==.Chunknoriss:BAABNQAECn8bAAMZAAYKjxg8FQBvAQAZAAYKjxg8FQBvAQAaAAEKAACUdwAgAAABNQAECgoKPQAEAFgRAA==.',
Ci='Cilarnen:BAABNQAECn8ZAAMTAAYKBBO0gAAEAQATAAYKBBO0gAAEAQARAAQKmQa2KQF3AAAAAA==.',
Cl='Claudiuss:BAAANQAECgYICwABNQAECgoKPgAEACcfAA==.Clure:BAABNQAECn8sAAITAAoK1yExFQArAwATAAoK1yExFQArAwABNQAECgoKPAAbAEQdAA==.Clurelock:BAAANQAECgUIBQABNQAECgoKPAAbAEQdAA==.Clurethyr:BAABNQAECn88AAIbAAoKRB2PBwCqAgAbAAoKRB2PBwCqAgAAAA==.',
Co='Conchobhar:BAAANQAECgYICAAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8NAAMKAAUKdw17EwBvAQAKAAUKdw17EwBvAQALAAEKAAByGABEAAA1AAQKfzcAAwoACgrkFiAvAFICAAoACQrOGCAvAFICAAsACAq2HYshACoCAAAA.Corrosion:BAABNQAECn8qAAIcAAoKFx/+BgASAwAcAAoKFx/+BgASAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQADCgEIAQAAAA==.Cromsteel:BAAANQADCgQIBgAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAIRAAUKIxPB8QA5AQARAAUKIxPB8QA5AQABNQAFFAQIBQARAFcLAA==.Crylessplz:BAAANQAECgUIDgABNQAECgoKOQAQAA4dAA==.',
Ct='Cthuwu:BAAANQAECgcIDAABNQAFFAUIDQAFAH8eAA==.',
Cv='Cvhamster:BAAANQADCgcICAAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8nAAMJAAoK6Bi+CwBvAgAJAAgKnxq+CwBvAgAdAAkK+BNiEgDUAQAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAABNQAECn8bAAIFAAgKUxOZkQBKAQAFAAgKUxOZkQBKAQAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgYICAAAAA==.Darkkromdor:BAABNQAECn8tAAIRAAoKXBu0YgByAgARAAoKXBu0YgByAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8qAAIUAAoKChfkJwBfAgAUAAoKChfkJwBfAgAAAA==.Deadtotem:BAAANQADCgEIAQABNQAECgoKKgAUAAoXAA==.Deathcat:BAABNQAECn8/AAMOAAoKdhweLgB5AgAOAAoKdhweLgB5AgAPAAYKPgthYQAfAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICQAAAA==.Deathshadowx:BAAANQAECgQIBgAAAA==.Decayy:BAABNQAECn8mAAINAAoKhhi2LQBeAgANAAoKhhi2LQBeAgAAAA==.Dedbull:BAAANQADCggIIwAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFwAAAA==.Des:BAAANQADCgEIAQAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn81AAILAAoKuBMCEgADAgALAAoKuBMCEgADAgAAAA==.',
Do='Dolemite:BAABNQAECn8pAAMZAAkKFhBnEQCzAQAZAAkKFhBnEQCzAQAaAAYKQA/MRQDuAAAAAA==.Donalbain:BAABNQAECn8+AAIEAAoKJx86CwBOAwAEAAoKJx86CwBOAwAAAA==.Donninban:BAABNQAECn8YAAMXAAYKUhPShgCTAQAXAAYKUhPShgCTAQAEAAQKRxkGpgClAAAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgoKKgAeAKMYAA==.',
Dr='Dradenar:BAAANQADCgEIAQAAAA==.Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAABNQAECn8UAAIfAAUKYxW1DQATAQAfAAUKYxW1DQATAQAAAA==.Dreyfusxano:BAAANQADCgEIAQAAAA==.Drizzeh:BAAANQADCgEIAgAAAA==.Drugoja:BAAANQADCgcICAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgIIAgAAAA==.',
Ea='Eas:BAAANQADCgUIBQAAAA==.',
Eb='Ebolla:BAAANQADCgcICAAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQAECgUICgAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eloweñ:BAAANQABCgQIBAAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn81AAINAAoKmhXUIADHAQANAAoKmhXUIADHAQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8gAAIHAAkKFQjbVgB7AQAHAAkKFQjbVgB7AQAAAA==.Emìly:BAABNQAECn85AAMZAAkK/RUFHADEAQAZAAgKFxYFHADEAQAaAAkKMxTmGACwAQAAAA==.',
En='Entaria:BAAANQAECgUIBwAAAA==.',
Ep='Ephria:BAABNQAECn8vAAMEAAoKiSQZEABDAwAEAAoKiSQZEABDAwAXAAEKAACXTQEnAAAAAA==.Episkey:BAAANQAECgQIDAAAAA==.',
Er='Eroversion:BAABNQAECn8YAAMGAAcK0hBiPgAxAQAGAAUK0RNiPgAxAQAdAAYKlwx4OwCiAAABNQAECgoKXwAWAHEcAA==.Eroward:BAABNQAECn9fAAMWAAoKcRx8BgBeAgAWAAoKcRx8BgBeAgAMAAIKDwXkHAEgAAAAAA==.',
Es='Esmay:BAABNQAECn8vAAIXAAkKvQ+0VABOAQAXAAkKvQ+0VABOAQAAAA==.',
Et='Ethren:BAABNQAECn88AAIDAAkKIBM5DwCxAQADAAkKIBM5DwCxAQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBgAAAA==.',
Ev='Evelynstar:BAAANQADCgMIAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fangsofblood:BAAANQAECgQIBAABNQAECgoKOgARAP0OAA==.',
Fe='Felbolter:BAABNQAECn8qAAIYAAgKlR2rCAByAgAYAAgKlR2rCAByAgAAAA==.Feliri:BAAANQAECgIIAQAAAA==.Fetide:BAAANQADCgIIAwAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAABNQAECn8/AAIFAAoK8RqVMgBLAgAFAAoK8RqVMgBLAgAAAA==.Finkate:BAAANQAECgcICQAAAA==.Firebringer:BAABNQAECn8lAAIgAAoKwwiAHQCDAQAgAAoKwwiAHQCDAQAAAA==.Fistmegently:BAAANQADCgYICwAAAA==.',
Fl='Flamehunter:BAAANQAECgYIDgAAAA==.Flo:BAABNQAECn9HAAQLAAoKMhQtIwAZAgALAAoKMhQtIwAZAgAKAAkKWgf6WwCUAQASAAgKZw1mBQB6AQAAAA==.Floki:BAABNQAECn8WAAMWAAcKGxFkHQBsAQAWAAcKGxFkHQBsAQAMAAUKlAeG9wDuAAAAAA==.Flokin:BAAANQAECgIIAwAAAA==.Flowing:BAABNQAECn86AAQhAAoKgxIgCAAbAgAhAAoKgxIgCAAbAgAbAAYKIwcqMgAIAQAiAAQKfATALwCcAAAAAA==.',
Fo='Foods:BAABNQAECn9JAAQMAAoKFBAVTgDjAQAMAAoKFg8VTgDjAQAWAAUKWg2ELQDJAAAjAAIKUAtdLwBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQICAAAAA==.',
['Fæ']='Fæ:BAAANQADCgcICAAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAABNQAECn8ZAAIRAAcKfhP3ygCGAQARAAcKfhP3ygCGAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBQAAAA==.',
Gi='Gilorion:BAABNQAECn8oAAIFAAkKhBhwRQANAgAFAAkKhBhwRQANAgAAAA==.',
Gl='Glasgoww:BAAANQADCgUIBgABNQAECgoKPgAEACcfAA==.Gler:BAAANQADCgQJBgAAAA==.',
Gn='Gnibat:BAAANQAECgQIBQAAAA==.',
Go='Goburina:BAABNQAECn8xAAIEAAoKVRLtRgDFAQAEAAoKVRLtRgDFAQAAAA==.Goldhawk:BAAANQADCgEIAQAAAA==.Goonette:BAAANQADCgEIAQAAAA==.',
Gr='Gryffen:BAAANQADCgEIAQAAAA==.',
Gu='Gulpron:BAAANQADCgEIAQAAAA==.',
['Gí']='Gímlí:BAABNQAECn8nAAIFAAoKORuZTwCAAgAFAAoKORuZTwCAAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8zAAQhAAkK1A+RCABnAQAhAAkKEw+RCABnAQAiAAYKow3hHwBYAQAbAAUKzgRgOwC+AAAAAA==.Hallowed:BAAANQADCgUIBQAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn9DAAIWAAoKzxhaCQAFAgAWAAoKzxhaCQAFAgAAAA==.',
He='Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgQIBgAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECggIJgATAKcWAA==.Honk:BAAANQAECgQIBAAAAA==.',
Ic='Ichiko:BAAANQADCgUIBQAAAA==.',
Im='Imwithfloki:BAABNQAECn8cAAQdAAYKXhraHgCoAQAdAAYKXhraHgCoAQAJAAEKAAC1OwBLAAAGAAEKhhDAaAAvAAAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECn8mAAIFAAkK6SW2CACXAwAFAAkK6SW2CACXAwAAAA==.Ismokeu:BAABNQAECn8sAAMKAAoKKRnCSABMAgAKAAoKKRnCSABMAgALAAEKAADHZwAAAAAAAA==.Ismyn:BAAANQAECgMIAgAAAA==.Istran:BAAANQAECgcIEQAAAA==.',
Iv='Ivrys:BAAANQAECgcIDwAAAA==.',
Iw='Iwillbethere:BAAANQAECgMIAwAAAA==.',
Ja='Jackoneal:BAABNQAECn8iAAMRAAkK4gOl8gDDAAARAAkK4gOl8gDDAAAQAAEKAABnfwAdAAAAAA==.Jalidelo:BAABNQAECn8jAAIKAAgKHRU6WgATAgAKAAgKHRU6WgATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQADCgIIAgAAAA==.',
Ji='Jimbowaboki:BAAANQADCgEIAQAAAA==.Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn87AAIkAAoKlxyQGgCNAgAkAAoKlxyQGgCNAgAAAA==.Jokersfists:BAABNQAECn8bAAIgAAoKRhHOEwD1AQAgAAoKRhHOEwD1AQABNQAECgoKKQAlAG8OAA==.Jokersmage:BAABNQAECn8pAAIlAAoKbw5JVADtAQAlAAoKbw5JVADtAQAAAA==.Joraflheim:BAAANQABCgMIBAAAAA==.Joranbragi:BAABNQAECn8hAAIRAAYKMQPZGQGMAAARAAYKMQPZGQGMAAAAAA==.Jordanjr:BAABNQAECn8/AAMmAAoKaxd6EgDiAQAFAAoKOBL3TACHAgAmAAoK9RJ6EgDiAQAAAA==.Josunlee:BAAANQAECggIDgAAAA==.Jotoonice:BAABNQAECn8oAAMVAAoKuBGtFgBIAQAVAAYKlxStFgBIAQAlAAgKOgeoRwEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8NAAMFAAYK+w0eGACrAAAmAAQKtw4jEwAOAQAFAAMKfwseGACrAAA1AAQKfzcAAyYACgpzHXccAG8CACYACgp+FXccAG8CAAUABArvIXelACIBAAAA.',
Ju='Juicyfruit:BAAANQADCgEIAQAAAA==.Jules:BAAANQADCgcICAAAAA==.',
Ka='Kaana:BAABNQAECn88AAIFAAkKIBJKWgDQAQAFAAkKIBJKWgDQAQAAAA==.Kaedina:BAABNQAECn8YAAMKAAoKrwuxbADYAQAKAAoKrwuxbADYAQALAAIKzwtNUwA5AAABNQAECgoKPwAmAGsXAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgIIAgABNQADCgcICgAIAAAAAA==.Karvel:BAABNQAECn8fAAINAAgKEhyXLwBUAgANAAgKEhyXLwBUAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECgkJLAATAFUeAA==.Kaydullz:BAABNQAECn8fAAIKAAoKvhf5KQBuAgAKAAoKvhf5KQBuAgAAAA==.',
Kc='Kchowchow:BAAANQAECgUIBQABNQAECgkJLAATAFUeAA==.',
Ke='Kelonaar:BAACNQAFFH8UAAMXAAQKaxehDADtAAAXAAQKaxehDADtAAAEAAIKuAPWJgBuAAA1AAQKfyoAAxcACgpfIGojAPkCABcACgpfIGojAPkCAAQAAwqgFPLiAKQAAAAA.Keloni:BAAANQAECgUIBgABNQAFFAQIFAAXAGsXAA==.Kenack:BAAANQAECgQIDAAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.',
Ki='Killermoomoo:BAAANQAECgQIBgAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUICQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgQIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAABNQAECn8YAAMTAAkKXRqCHACnAgATAAkKXRqCHACnAgARAAEKDAdNagE2AAAAAA==.Lanval:BAABNQAECn9EAAIRAAoKbhqGPwA7AgARAAoKbhqGPwA7AgAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn9EAAIdAAoKbRtnDQCQAgAdAAoKbRtnDQCQAgAAAA==.Leftblank:BAAANQAECgQIBQAAAA==.',
Li='Lich:BAAANQAECgQIBAAAAA==.Lierah:BAAANQADCgEIAQAAAA==.Lighthugger:BAABNQAECn84AAIRAAoKgxoRUAAGAgARAAoKgxoRUAAGAgAAAA==.Lilyoptra:BAABNQAECn8ZAAIkAAYKCQNV1AB6AAAkAAYKCQNV1AB6AAABNQAECgYIGQATAAQTAA==.Liqmycrits:BAAANQADCggIGwAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgcIHAAUAGMRAA==.Liszt:BAAANQADCgMIBAAAAA==.Livana:BAAANQADCggIEgABNQAECgYIDwAIAAAAAA==.',
Lo='Lockpockets:BAABNQAECn8cAAIkAAcKLwq1kQABAQAkAAcKLwq1kQABAQAAAA==.Loriane:BAAANQAECgIIAgABNQAECgcIEQAIAAAAAA==.Lorianth:BAABNQAECn84AAImAAoK6g8cFwCbAQAmAAoK6g8cFwCbAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgcIBQAAAA==.',
Lu='Lucifér:BAAANQADCgEIAQAAAA==.Lundigras:BAAANQADCgUICAAAAA==.',
Ly='Lychi:BAAANQAECgQIBgAAAA==.Lylora:BAABNQAECn9QAAIGAAoKRyZmAABIBAAGAAoKRyZmAABIBAAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8qAAMKAAoKUxX1UgAqAgAKAAoKUxX1UgAqAgALAAUKIQVtQAB6AAAAAA==.',
['Lô']='Lôki:BAAANQADCgYIBgAAAA==.',
Ma='Madclaws:BAABNQAECn9HAAMdAAoK5B2OCQB5AgAdAAoKrRuOCQB5AgAHAAkK0h0OFQBDAgAAAA==.Madman:BAAANQAECgUIDwAAAA==.Magekaestey:BAAANQADCggIEQABNQAECgoKKAAMADIMAA==.Malala:BAAANQADCgYIFAABNQAECgoKTQAKAMQdAA==.Malyndra:BAAANQAECgUICAABNQAECgYIDwAIAAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8gAAIkAAgKdQiYnQCcAQAkAAgKdQiYnQCcAQAAAA==.Masy:BAAANQAECgUIBQAAAA==.',
Me='Mesmash:BAABNQAECn8sAAIWAAgKoyHOCQCrAgAWAAgKoyHOCQCrAgAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDgABNQAECgYIDwAIAAAAAA==.Metatotem:BAAANQAECgYIBgABNQAECgYIDwAIAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIAwAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECgUICQABNQAECgkJLAAKAF8ZAA==.Miniborg:BAAANQAECgUIDAABNQAFFAQIBQARAFcLAA==.Minidude:BAABNQAECn8XAAIMAAkKkw+TXACxAQAMAAkKkw+TXACxAQAAAA==.Misfire:BAAANQAECgEIAQAAAA==.Mistycrusade:BAAANQAECgUICQAAAA==.Mizzen:BAABNQAECn8yAAMOAAoKYR4qCwChAgAOAAoKYR4qCwChAgANAAIKpQzytABfAAABNQAFFAUIDgALANcRAA==.',
Mo='Moejojojo:BAABNQAECn8YAAIaAAcKwB/pHgA5AgAaAAcKwB/pHgA5AgAAAA==.Moofasaha:BAABNQAECn8bAAQEAAYKjx+3YgDlAQAEAAYKjx+3YgDlAQAXAAQKggjS+wCbAAAcAAEKSggPLwA9AAAAAA==.Morog:BAABNQAECn8UAAMFAAgKHB8rOwC4AgAFAAgKHB8rOwC4AgAmAAEKAACNigA0AAAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAABNQAECn8XAAIlAAcKXQjPMAE7AQAlAAcKXQjPMAE7AQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgUIBgABNQAFFAEIAQAIAAAAAA==.',
['Mã']='Mãrshy:BAABNQAECn8cAAIKAAgKgB6IOgB/AgAKAAgKgB6IOgB/AgABNQAFFAEIAQAIAAAAAA==.',
['Mä']='Märshy:BAAANQAECgQIBAABNQAFFAEIAQAIAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECn9NAAMKAAoKxB2BEQAjAwAKAAoKxB2BEQAjAwALAAEKfQR1XQAgAAAAAA==.Nashalie:BAABNQAECn87AAMkAAoKbCGjGAAlAwAkAAoKbCGjGAAlAwAYAAIKOgzdVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAABNQAECn8VAAIEAAcKZxnGigBuAQAEAAcKZxnGigBuAQAAAA==.Neverfrozen:BAAANQAECgYICgAAAA==.Nexbasia:BAABNQAECn82AAIJAAoKtxGGDAC2AQAJAAoKtxGGDAC2AQAAAA==.',
Ni='Nickyboy:BAAANQAECgQIBAAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIFQAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQADCgEIAQAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBAAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAABNQAECn8dAAIFAAgKyQotmQDVAQAFAAgKyQotmQDVAQAAAA==.',
Om='Ominis:BAAANQADCgQIBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAABNQAECn8gAAQQAAUKkhUGQAD6AAAQAAUKkhUGQAD6AAARAAQKbQGShQFSAAATAAIKuwFuHgE4AAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAILAAQKdBpcCgBTAQALAAQKdBpcCgBTAQA1AAQKfxwAAgsACQpNIisRAOgCAAsACQpNIisRAOgCAAAA.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgMIAwAAAA==.Pallydoof:BAAANQADCggICgAAAA==.Pallyscorned:BAABNQAECn8rAAIQAAoKmxdVEQDXAQAQAAoKmxdVEQDXAQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECggIEgAIAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Pandaria:BAAANQAFFAEIAQAAAA==.Panduh:BAABNQAECn8xAAMaAAkKZiEPCwAjAwAaAAkKECEPCwAjAwAeAAcKjx+bDgAKAgAAAA==.',
Ph='Phenixy:BAAANQAECgQIBgAAAA==.Phoebell:BAAANQAECgUIDwAAAA==.Phoinix:BAAANQADCggIDgAAAA==.',
Pi='Pinkducky:BAAANQADCggIHgAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECgkJLAAKAF8ZAA==.',
Po='Ponyo:BAABNQAECn87AAIKAAoKvyP8BQC2AwAKAAoKvyP8BQC2AwAAAA==.Poppyseed:BAAANQAECgcIBwAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pr='Prinnce:BAAANQAECgcIDgABNQAECgkJOQAZAP0VAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8cAAMmAAgKXg92OACMAQAmAAgKnQ52OACMAQAFAAMK1hF5HgHAAAAAAA==.',
Ra='Raddra:BAAANQAECgUICgAAAA==.Raddrah:BAAANQAECgMIAwAAAA==.Raddrap:BAAANQADCgUIBwAAAA==.Radmuster:BAAANQADCgcIBwABNQAECgoKHgALAG0SAA==.Radra:BAABNQAECn8tAAIgAAoKNxBlHACOAQAgAAoKNxBlHACOAQAAAA==.Raeku:BAABNQAECn8rAAInAAoKVB1yAgCKAgAnAAoKVB1yAgCKAgAAAA==.Raharuto:BAAANQADCggICQAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn88AAIKAAoKHh9qCgBzAwAKAAoKHh9qCgBzAwAAAA==.Redhaven:BAABNQAECn8eAAIKAAoKeA3oRQDoAQAKAAoKeA3oRQDoAQAAAA==.Reducto:BAAANQADCgYIDAAAAA==.Retribution:BAABNQAECn86AAIRAAoK/Q47bAC5AQARAAoK/Q47bAC5AQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rokz:BAAANQAECgIIAgAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAACNQAFFH8RAAIEAAYKGRYHBgDWAQAEAAYKGRYHBgDWAQA1AAQKfzsAAgQACgrgIFoSADUDAAQACgrgIFoSADUDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgYIDQAAAA==.Rowdyredneck:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Ru='Ruby:BAABNQAECn8cAAIeAAkKBiDbBQD4AgAeAAkKBiDbBQD4AgAAAA==.Rul:BAAANQADCgIIAgABNQAECgkJMQAaAGYhAA==.',
Ry='Ryllae:BAAANQADCgIIAwABNQAECggIIwAUADEdAA==.Ryuu:BAAANQAECgIIAwAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8dAAMfAAoKXwgIGgC2AAAkAAoK/AfaqwB7AQAfAAQKuwYIGgC2AAABNQAECgoKJwAFADkbAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgoKJwAFADkbAA==.',
Sa='Saint:BAABNQAECn8oAAMRAAgKJRMcwACcAQARAAcKWRYcwACcAQATAAgK3RNCjwBwAQAAAA==.Salopard:BAAANQADCgQIBQAAAA==.Saltsquirrel:BAAANQABCgIIAgAAAA==.Sarandria:BAAANQAECgQIBAABNQAECgkJGQAVAKQYAA==.Sarinae:BAABNQAECn8mAAMhAAkKBwexEAAsAQAhAAkK9gaxEAAsAQAiAAYKIwRZKgDVAAAAAA==.Sarmuc:BAABNQAECn8/AAIcAAoKgRiECQDdAgAcAAoKgRiECQDdAgAAAA==.Saryda:BAABNQAECn8WAAMLAAYK4ROHNQB3AQALAAYK4ROHNQB3AQAKAAEK1wIb5QAsAAAAAA==.Sauda:BAAANQAECgUICAAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQAECgUIDwAAAA==.Scythraza:BAAANQAECgYIBgAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sellenah:BAAANQADCgUIBAABNQAECgUIBwAIAAAAAA==.Selûne:BAAANQADCgEIAQAAAA==.Sensu:BAABNQAECn8aAAMSAAUKExAOCAALAQASAAUKExAOCAALAQALAAEKbAODWgAqAAAAAA==.Serrest:BAAANQAECgYICgAAAA==.Seä:BAABNQAECn8mAAITAAgKpxYZVQAaAgATAAgKpxYZVQAaAgAAAA==.',
Sh='Shacktown:BAAANQAECgEIAQAAAA==.Shadowdoh:BAAANQAECgYIDwAAAA==.Shapzan:BAAANQAECgYIDQAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAABNQAECn89AAIEAAoKWBEgUwCUAQAEAAoKWBEgUwCUAQAAAA==.Shîvå:BAAANQADCgEIAQABNQAECgoKOQAQAA4dAA==.',
Si='Silendreas:BAAANQADCgUIBwAAAA==.',
Sl='Sloth:BAABNQAECn87AAINAAoKFiIQCAD3AgANAAoKFiIQCAD3AgAAAA==.',
Sm='Smalltwngirl:BAABNQAECn8aAAIGAAgKBRGZJQB5AQAGAAgKBRGZJQB5AQABNQAFFAYIEQAEABkWAA==.',
So='Solaire:BAAANQAECgQIBwAAAA==.Solaspirus:BAABNQAECn8XAAQUAAgKAxLYUQBOAQAUAAYK8xPYUQBOAQAgAAMKuwisQQBsAAAoAAEKLRD4NAAoAAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8sAAMKAAkKXxkUKgDBAgAKAAkKXxkUKgDBAgALAAUKmQUkUADRAAAAAA==.Sonofagun:BAAANQAECgYICAAAAA==.',
Sp='Spectors:BAABNQAECn8zAAQfAAoKsAdfCgBXAQAfAAoKUQdfCgBXAQAkAAcKHwPs5wD5AAAYAAEKAAA5hQAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgYIEQAAAA==.Strykah:BAAANQADCgQIBgAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgMIAgAAAA==.',
Sw='Sweetstorm:BAABNQAECn8lAAIUAAcKvAItbADIAAAUAAcKvAItbADIAAAAAA==.',
Sy='Sydburns:BAAANQADCgEIAgAAAA==.Sydley:BAAANQADCgEIAQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAABNQAECn8aAAMXAAgKWAVIYwAhAQAXAAgKWAVIYwAhAQAEAAcKcwIWlADNAAAAAA==.Tarixx:BAABNQAECn8VAAMRAAgKlB35XgDbAQARAAgKKBr5XgDbAQAQAAYKVyB1JQC0AQAAAA==.Tazanoth:BAABNQAECn8xAAQFAAoKYhodYgBSAgAFAAoKIRkdYgBSAgAnAAgK6BskBgBDAgAmAAYKPQo+RwAiAQAAAA==.',
Te='Tekeela:BAABNQAECn8mAAIFAAoKZSCCFQDSAgAFAAoKZSCCFQDSAgABNQAFFAUIDQAFAH8eAA==.Tekeelà:BAACNQAFFH8NAAIFAAUKfx7YDAACAQAFAAUKfx7YDAACAQA1AAQKfz8AAgUACgqTItgOAGsDAAUACgqTItgOAGsDAAAA.Tenack:BAAANQADCgEIAQAAAA==.Terzo:BAAANQABCgQIBgAAAA==.',
Th='Thalarus:BAAANQADCgMIBgABNQADCgcICgAIAAAAAA==.Thalion:BAAANQAECgYICQAAAA==.Theenna:BAAANQADCgEIAgAAAA==.Theroux:BAAANQADCggIEAAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAABNQAECn8XAAMTAAcKWQ73iADtAAATAAcKWQ73iADtAAARAAEKewYquwEqAAAAAA==.Thobu:BAAANQAECgUIBgAAAA==.Thornscale:BAABNQAECn8fAAQhAAkKVwl3DgBfAQAiAAgKmAeoHQB0AQAhAAgKDwl3DgBfAQAbAAEKJQIMUwAmAAAAAA==.',
Ti='Tigolcrittys:BAAANQADCggIEQABNQAECgoKJwAFADkbAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAABNQAECn8WAAIEAAkK+hieMgAiAgAEAAkK+hieMgAiAgAAAA==.Totem:BAAANQAECgQICQAAAA==.Tovê:BAABNQAECn8fAAMEAAoK3BRcIwB3AgAEAAoK3BRcIwB3AgAXAAUKAwuaxwADAQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMYAAgKzCCABADhAgAYAAgKzCCABADhAgAfAAMKQBLkGQC3AAAAAA==.Trxcy:BAAANQAECgMIAwAAAA==.',
Tu='Turger:BAAANQAECgEIAQABNQAECgYIGwAEAI8fAA==.',
Ul='Ulthaine:BAAANQADCgEIAQAAAA==.',
Um='Umbrafang:BAAANQADCgEIAQAAAA==.',
Va='Vaeluptuous:BAABNQAECn8gAAIkAAYKihJ8tQBkAQAkAAYKihJ8tQBkAQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8rAAMYAAoKwSC2BADaAgAYAAgKSh62BADaAgAkAAkKbBvlYQAzAgAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Valsilla:BAAANQADCgEIAQABNQAECggIIwAUADEdAA==.Vapor:BAAANQAECggIDwAAAA==.Varaine:BAAANQAECgUIBQABNQAECgcIHAAUAGMRAA==.',
Ve='Veebs:BAAANQAECgYIBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Victorisdoom:BAAANQADCgEIAQAAAA==.Virauca:BAABNQAECn88AAIgAAoKwxX+EAAcAgAgAAoKwxX+EAAcAgAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIHAAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAIUAAgKMR2PIQCPAgAUAAgKMR2PIQCPAgAAAA==.',
Wa='Wamoo:BAAANQADCgEIAQAAAA==.Wanagi:BAAANQAECgQIEAAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8oAAIMAAoKMgy9aQCKAQAMAAoKMgy9aQCKAQAAAA==.Warriorguyes:BAABNQAECn8jAAIMAAkKXh1sQAAUAgAMAAkKXh1sQAAUAgAAAA==.',
Wh='Whomper:BAAANQAECgQIBAAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAABNQAECn8ZAAIXAAgKVQxGegDlAAAXAAgKVQxGegDlAAAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn86AAINAAkK9BBVLQB0AQANAAkK9BBVLQB0AQAAAA==.',
Wo='Womphunt:BAABNQAECn8tAAIFAAoK/RhtMQBPAgAFAAoK/RhtMQBPAgAAAA==.',
Wu='Wulyn:BAAANQAECgQIEQAAAA==.',
Wy='Wylla:BAABNQAECn8dAAIaAAYK0QuRRAD2AAAaAAYK0QuRRAD2AAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAABNQAECn8VAAINAAoKDQxZKgCHAQANAAoKDQxZKgCHAQAAAA==.',
Xs='Xsuns:BAABNQAECn8uAAIGAAkK0RdlIgATAgAGAAkK0RdlIgATAgAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQAECgMIBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgUIEQAAAA==.Zarathiel:BAABNQAECn8fAAIMAAoKew1EnwDOAQAMAAoKew1EnwDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn8vAAMfAAgKuAZFDwBbAQAfAAgKuAZFDwBbAQAkAAYKnwM8sAC/AAAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggIDAAAAA==.',
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
