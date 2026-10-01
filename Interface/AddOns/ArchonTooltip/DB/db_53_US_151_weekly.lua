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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Blood','Priest-Shadow','Druid-Restoration','Druid-Balance','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Priest-Holy','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','DemonHunter-Havoc','Mage-Frost','Monk-Windwalker','Druid-Feral','Warrior-Protection','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DemonHunter-Vengeance','Paladin-Protection','Evoker-Augmentation','Hunter-Survival',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaluah:BAAANQAECgIIBAAAAA==.',
Ab='Abc:BAAANQAECgUIBQABNQAECggIHwABAFASAA==.',
Ac='Acmis:BAAANQAECgEIAQABNQAECgQJBgACAAAAAA==.Acp:BAABNQAECoEXAAIDAAgKfhvbLwCcAgADAAgKfhvbLwCcAgAAAA==.',
Ad='Adomangma:BAAANQABCgQIBQAAAA==.',
Ah='Ahjumma:BAABNQAECoEhAAIEAAgKiBxVHwCDAgAEAAgKiBxVHwCDAgAAAA==.',
Ai='Ailharn:BAAANQAECgUIEwAAAA==.',
Ak='Akadein:BAAANQADCgUIBQAAAA==.Akun:BAAANQADCgYIDAABNQAECgUIDAACAAAAAA==.Akurantirea:BAAANQAECgUIDAAAAA==.',
Al='Aldin:BAAANQAECgUIBQAAAA==.Algerax:BAAANQAECgIIBQAAAA==.Allise:BAAANQAECgIIAwAAAA==.Alphamaled:BAABNQAECoEZAAIEAAgKCQUEYQAlAQAEAAgKCQUEYQAlAQAAAA==.Alva:BAAANQADCgYICAAAAA==.Aléthia:BAAANQAECgUIDwAAAA==.',
Am='Ambaxius:BAAANQADCgYIEgAAAA==.',
An='Anathemá:BAAANQADCgYICgAAAA==.Ang:BAAANQAECgYIBgAAAA==.Ange:BAAANQADCggIEAAAAA==.',
Ap='Apawpriest:BAABNQAECoEdAAIFAAgKGRXMGgAqAgAFAAgKGRXMGgAqAgAAAA==.',
Ar='Archious:BAAANQADCgQIBAAAAA==.Ardeyn:BAAANQADCgMIAwAAAA==.Arke:BAAANQAECgYICwAAAA==.Arlynn:BAAANQABCgMIAwABNQAECgYIDgACAAAAAA==.Arraeroda:BAAANQAECgQJBgAAAA==.Arrence:BAAANQAECgQIBAABNQAECggIIQAEAIgcAA==.Artleandra:BAAANQADCgMIAwABNQAECgYIDgACAAAAAA==.',
As='Ashara:BAAANQAECgEIAQAAAA==.Ashlena:BAAANQADCgQIBAABNQAECgMIAgACAAAAAA==.Astela:BAAANQAECgYIDwAAAA==.Asuka:BAAANQADCggICgAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQABNQAECgkJGQAFAGQiAA==.Autumn:BAABNQAECoEaAAMGAAgKNh6xDQC+AgAGAAgKNh6xDQC+AgAHAAIK0QTqiABMAAAAAA==.',
Av='Avan:BAAANQADCggICAAAAA==.Avatan:BAABNQAECoEXAAIIAAcKsgoGDwBoAQAIAAcKsgoGDwBoAQAAAA==.Avedeath:BAAANQADCggIHQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.Averlis:BAAANQADCgIIAgAAAA==.',
Ay='Ayane:BAAANQABCgYICAAAAA==.Ayara:BAACNQAFFIEMAAIJAAUKFyB1AwDmAQAJAAUKFyB1AwDmAQA1AAQKgUgAAgkACQryI6UDAJADAAkACQryI6UDAJADAAAA.Ayrad:BAAANQAECgMIAwAAAA==.',
Ba='Badderdragon:BAABNQAECoEmAAMKAAkKhxcsDQBaAgAKAAgKoBksDQBaAgALAAEKTAaSQAA7AAAAAA==.Badmrmittens:BAAANQAECgIIAgAAAA==.Badmuffin:BAAANQAECgQIBgAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.Barthas:BAAANQABCgQIBAAAAA==.',
Be='Bearlygrillz:BAAANQAECgEIAQAAAA==.Bearrawrxd:BAAANQABCgMIAwAAAA==.Begachan:BAAANQADCgYIBgAAAA==.Berkstein:BAAANQAECgQJBAAAAA==.',
Bi='Bigbadrock:BAAANQADCgMIAwAAAA==.Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgYIDgAAAA==.Bigspriesty:BAAANQAECgEIAQAAAA==.Bigtone:BAAANQAECgUICwAAAA==.Bimbomz:BAABNQAECoEeAAIMAAgKjCHYEwDlAgAMAAgKjCHYEwDlAgAAAA==.Biochemist:BAAANQADCgMIBAABNQAECggIHgANAAYcAA==.Bioengineer:BAAANQADCgYIBgABNQAECggIHgANAAYcAA==.Biogenic:BAABNQAECoEeAAQNAAgKBhz0OwAnAgANAAcKdRv0OwAnAgAOAAYKkRY1ZQCdAQAPAAEKIAV+KgA9AAAAAA==.Biomass:BAAANQADCgcICAABNQAECggIHgANAAYcAA==.Biophysics:BAAANQAECgMIAwABNQAECggIHgANAAYcAA==.Birdbrain:BAABNQAECoEcAAIQAAkKOyCvCQAcAwAQAAkKOyCvCQAcAwAAAA==.',
Bl='Bleebloop:BAAANQAECgUIBAABNQAECgkJIAAPANwiAA==.Blewîsa:BAAANQADCgcJCgAAAA==.Blvck:BAAANQADCgcIDQAAAA==.',
Bo='Boodylicious:BAAANQADCgcIFAABNQAECgUIDgACAAAAAA==.Borucmonk:BAAANQADCgcIEwABNQAECgYIEgACAAAAAA==.Borucwar:BAAANQAECgYIEgAAAA==.',
Br='Braedia:BAAANQAECgIIAgAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Briele:BAAANQAECgUIDQAAAA==.Brise:BAAANQAECgEIAQAAAA==.Brosabi:BAAANQAECgYIDwABNQAECgcIEgARAE4jAA==.Brucewaynexb:BAAANQABCgYIBgAAAA==.',
Bu='Bubs:BAAANQAECgQIDgAAAA==.Buddhïst:BAABNQAECoEcAAIDAAkKFCMgCwBjAwADAAkKFCMgCwBjAwAAAA==.Burrhas:BAAANQADCggICgAAAA==.Buxky:BAAANQADCgIJAgAAAA==.',
['Bí']='Bítten:BAAANQAECgUICQAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgYIDgACAAAAAA==.Cakewastaken:BAAANQAECgYIDgAAAA==.Cakke:BAAANQADCgUIBgAAAA==.Calkestis:BAAANQADCgUJDAAAAA==.Candre:BAABNQAECoEhAAISAAgKwiIdIgAKAwASAAgKwiIdIgAKAwAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgMIBAABNQAECgUICgACAAAAAA==.Capristal:BAAANQAECgUICgAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgYIDAAAAA==.Cassiera:BAABNQAECoEhAAITAAgKTBseKwCDAgATAAgKTBseKwCDAgAAAA==.Cauldren:BAAANQADCggIKQAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Chay:BAABNQAECoEaAAIRAAkKHRqkJwCwAgARAAkKHRqkJwCwAgAAAA==.Chaylin:BAAANQADCgcICAABNQAECgkJGgARAB0aAA==.Chikage:BAAANQAECgEIAQAAAA==.Chillen:BAAANQAECggIEwAAAA==.Chillzen:BAAANQADCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQAECgUICwAAAA==.Chopu:BAAANQAECgUIEAAAAA==.Chrîstîne:BAAANQADCgYIBgAAAA==.Chuckspadina:BAABNQAECoEjAAITAAgKKBaiOQBAAgATAAgKKBaiOQBAAgAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQADCgcIEQAAAA==.',
Ci='Cibø:BAAANQAECgQIBwAAAA==.Cilghalcao:BAAANQAECgUIBgAAAA==.Cirdae:BAABNQAECoEgAAMNAAgKmRbUQwAFAgANAAgKmRbUQwAFAgAOAAEKjg0y7wBBAAAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECggIGwARAEQbAA==.Cloudstone:BAAANQAECgYICAAAAA==.Clownfish:BAAANQADCgQIBAAAAA==.Clõud:BAAANQAECgUIDAAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAABNQAECoEdAAIUAAgKZSG0KADtAgAUAAgKZSG0KADtAgAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgUICgAAAA==.',
Cr='Cragshot:BAAANQAECgMIAwAAAA==.Crazynip:BAABNQAECoEkAAITAAkKhyArCQBjAwATAAkKhyArCQBjAwAAAA==.Crickit:BAAANQAECgUIDgAAAA==.Crispr:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggICAABNQAECggIIAAVAEwgAA==.Crylucis:BAABNQAECoEgAAIVAAgKTCD0JACdAgAVAAgKTCD0JACdAgAAAA==.Crymagus:BAAANQADCgcIBwABNQAECggIIAAVAEwgAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgACAAAAAA==.',
Cu='Cujo:BAABNQAECoEfAAIOAAgK4RxEKAClAgAOAAgK4RxEKAClAgAAAA==.',
Cy='Cyanidesun:BAAANQAECgEIAQAAAA==.Cybre:BAAANQAECgIIAwAAAA==.Cyndaquill:BAAANQAECggIAgAAAA==.Cyndil:BAAANQAECgUIDwAAAA==.Cysora:BAAANQAECgEJAQAAAA==.Cysport:BAAANQAECgIIAgAAAA==.',
['Cä']='Cästiel:BAAANQAECgQIDAAAAA==.',
Da='Daahntaat:BAAANQABCgMJBQAAAA==.Daesyn:BAAANQABCgMIBAAAAA==.Dallei:BAAANQAECgQIBgAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAAANQAECgYIEwAAAA==.Darcane:BAABNQAECoEjAAQWAAgKCBHBDgD8AQAWAAgK0hDBDgD8AQARAAYKUQaOpQAkAQAXAAEKuQmxJwA1AAAAAA==.Darctanian:BAAANQADCggICwAAAA==.Darkchaos:BAAANQADCggICAAAAA==.Darkdestîny:BAAANQADCgcIBwAAAA==.Darkvayne:BAAANQAECgcIEAAAAA==.Darrington:BAAANQAECgUIDQAAAA==.Dathrel:BAAANQADCggIJAAAAA==.Davoodoomon:BAAANQAECgEIAQAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.Dawnfoxer:BAAANQAECgQICAAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deburr:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.Deezaster:BAAANQAECgEIAQABNQAECggIDgACAAAAAA==.Def:BAABNQAECoEXAAIYAAgKzxYTeQBUAgAYAAgKzxYTeQBUAgAAAA==.Delani:BAAANQAECgMIBQAAAA==.Delisius:BAAANQADCgYIBgAAAA==.Deltaco:BAAANQADCgcIFwAAAA==.Dementis:BAAANQADCggIDwAAAA==.Demonnova:BAACNQAFFIEMAAMJAAUKJhVQBgBeAQAJAAQKVBlQBgBeAQAZAAEKbwQZFwA7AAA1AAQKgSEAAwkACQrHHUEWAIACAAkACAqTHkEWAIACABkAAgqqDfxiAH0AAAAA.Dendude:BAAANQABCgEIAQAAAA==.Destiny:BAAANQAECgIJAgAAAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFIEVAAIFAAYKYyFbAQBbAgAFAAYKYyFbAQBbAgA1AAQKgSoAAgUACQqLJnIBAMUDAAUACQqLJnIBAMUDAAAA.',
Dg='Dghunter:BAAANQAECgYIEgAAAA==.',
Di='Dietrinea:BAAANQADCgIIAgAAAA==.',
Do='Docsored:BAAANQAECgUIBgAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQAECgUIDgAAAA==.Doomchick:BAAANQABCggIDgAAAA==.',
Dr='Dragn:BAAANQAECgEIAQAAAA==.Dragnas:BAABNQAECoEjAAIUAAgKsRdzVQBHAgAUAAgKsRdzVQBHAgAAAA==.Dragniperake:BAABNQAECoEaAAITAAgKPhgoNgBPAgATAAgKPhgoNgBPAgAAAA==.Drbluejeans:BAAANQAECgEIAQABNQAECggIDQACAAAAAA==.Drbug:BAAANQAECgYIDAABNQAECggIDQACAAAAAA==.Drdots:BAABNQAECoEbAAIRAAgKXhM/UQAYAgARAAgKXhM/UQAYAgAAAA==.Dreadnaunt:BAAANQAECgMIBgAAAA==.Dreamhc:BAABNQAECoEgAAMYAAgKgh6ijwAfAgAYAAYKWyCijwAfAgAaAAMKrxjrGgDVAAAAAA==.Dreamwave:BAAANQADCgcICgABNQADCggIDwACAAAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drewed:BAAANQAECgYICgAAAA==.Drmage:BAAANQAECgEIAQAAAA==.Drugral:BAABNQAECoEmAAIMAAkKdiE7DAAxAwAMAAkKdiE7DAAxAwAAAA==.',
Du='Dugronn:BAAANQAECgEIAQAAAA==.',
Dw='Dwarfvadar:BAAANQAECgUIBwAAAA==.',
Ea='Eadric:BAAANQAECgEIAQAAAA==.',
Ed='Edda:BAAANQAECgEJAQABNQAECggIFwAYAM8WAA==.',
El='Elanthemage:BAAANQAECgQIBAAAAA==.Elarya:BAAANQADCggICgAAAA==.Electria:BAAANQADCgIIAgAAAA==.Eleison:BAACNQAFFIEOAAIFAAUKLCADAwDlAQAFAAUKLCADAwDlAQA1AAQKgR0AAwUACQoiIisGAFoDAAUACQoiIisGAFoDABUAAQp0Bt/CAEIAAAAA.Ellairis:BAAANQAECgcIEAAAAA==.Ellesperis:BAAANQAECgUICwAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQAECgUICQAAAA==.Elyssarelsia:BAAANQAECgYIEAAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
Er='Eragôn:BAABNQAECoEYAAIKAAgKjxHjEQD1AQAKAAgKjxHjEQD1AQAAAA==.Erdrus:BAAANQADCggICAABNQAECgcIGAAVAKEcAA==.Erinyes:BAAANQAECgUIDAAAAA==.',
Es='Estee:BAAANQAECgUIBwAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgIIAgAAAA==.',
Fa='Falafel:BAAANQADCggICAAAAA==.Fatfish:BAAANQADCggIBQAAAA==.Fatty:BAABNQAECoEfAAMBAAgKUBKEFQDMAQABAAgKUBKEFQDMAQAbAAEKJwv1UwAxAAAAAA==.',
Fe='Feargasm:BAAANQABCgMIBQAAAA==.Felscream:BAAANQADCgcIDAAAAA==.Fenja:BAABNQAECoEjAAIOAAgKuBRYQwAbAgAOAAgKuBRYQwAbAgAAAA==.Feul:BAABNQAECoE7AAINAAkKfBuXKQB/AgANAAkKfBuXKQB/AgAAAA==.Feyded:BAAANQAECgQJBgAAAA==.Feylis:BAAANQADCgUIBQABNQAECgYIDwACAAAAAA==.',
Fh='Fhara:BAAANQADCgUIBgAAAA==.',
Fi='Fiasko:BAABNQAECoEeAAIUAAgKzhomUQBWAgAUAAgKzhomUQBWAgAAAA==.Fiir:BAAANQADCggIEwAAAA==.Firehose:BAAANQADCgUIBQABNQAECggIGwARAEQbAA==.Fizbang:BAAANQADCgEJAQAAAA==.',
Fl='Flippÿ:BAAANQAECgIIAwAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQAECgQJBgAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgUIDQAAAA==.',
Fo='Foreverdead:BAAANQADCgQIBwAAAA==.Formidonis:BAABNQAECoEfAAMRAAgKkR6hNwBxAgARAAcKAB+hNwBxAgAWAAIKGhHtTQB/AAAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.',
Fr='Frieddough:BAAANQADCgMIAwAAAA==.Frizix:BAAANQAECgEIAgAAAA==.Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAABNQAECoEeAAMYAAgKLBwfZwB/AgAYAAgKLBwfZwB/AgAaAAIK/xHcKABqAAAAAA==.',
Fu='Fubber:BAABNQAECoEiAAIEAAkKLR7aEAAAAwAEAAkKLR7aEAAAAwAAAA==.Fulgur:BAAANQAECgUIDwAAAA==.Funsizegurly:BAABNQAECoEgAAIYAAgKPBeEegBRAgAYAAgKPBeEegBRAgAAAA==.Furrgie:BAAANQAECgEIAQAAAA==.',
Ga='Gallypotter:BAABNQAECoEZAAIDAAYKqRXbiACWAQADAAYKqRXbiACWAQAAAA==.Garygabagool:BAABNQAECoEcAAIPAAkKayDYBAAnAwAPAAkKayDYBAAnAwAAAA==.Gawdshamit:BAABNQAECoEZAAMNAAYKhw6uhAApAQANAAYKhw6uhAApAQAOAAQKegJCzgCMAAAAAA==.Gawdspet:BAAANQAFFAEIAQABNQAFFAMIBgAWANMNAA==.',
Ge='Gemcutter:BAAANQADCgYICQAAAA==.Geoffreey:BAAANQAECgMIAwAAAA==.',
Gh='Ghakk:BAAANQADCgYICAAAAA==.Ghostmane:BAAANQADCgIIAgAAAA==.Ghostorc:BAAANQAECgYIEAAAAA==.',
Gi='Gichidolo:BAAANQADCgEIAQAAAA==.Giegs:BAAANQAECgUICgAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAABNQAECoEhAAIUAAgKuxzERACAAgAUAAgKuxzERACAAgAAAA==.Gnawrly:BAABNQAECoEXAAMcAAgKoBE5DgC+AQAcAAcKBxM5DgC+AQAGAAYK9gm4MwATAQAAAA==.',
Go='Gonzo:BAABNQAECoEVAAIdAAcKyQ+EFQBxAQAdAAcKyQ+EFQBxAQAAAA==.Goodgirl:BAAANQAECgYIDgABNQAECggIDQACAAAAAA==.Goodgurl:BAAANQAECggIDQAAAA==.Govrek:BAAANQAECgQICAAAAA==.',
Gr='Greenstone:BAAANQADCgUIDQAAAA==.Gretchn:BAAANQADCgQIBAAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQAECgIIAgAAAA==.Grïm:BAABNQAECoEeAAIaAAgKhCE0AwDeAgAaAAgKhCE0AwDeAgAAAA==.',
Gt='Gtfobubble:BAAANQAECgYICgAAAA==.Gtfolava:BAAANQADCgcIDAAAAA==.',
Gu='Guldont:BAAANQADCggIGQAAAA==.',
Ha='Hankering:BAAANQAECgIIAwABNQAECggIHgAeABEaAA==.Hankopher:BAABNQAECoEeAAQeAAgKERp7NACeAQAeAAcKlBh7NACeAQAEAAcKbxRkRgCdAQAMAAQK5BU3ZwAKAQAAAA==.Hanziè:BAAANQAECgUICAAAAA==.Haptics:BAABNQAECoEmAAMfAAkK2SLjBwApAwAfAAkKPB/jBwApAwAgAAUKhiR2FQAVAgAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgQJCQAAAA==.Hasbin:BAAANQADCgcIEAAAAA==.Hatzel:BAABNQAECoEhAAINAAkKaB6lEAAXAwANAAkKaB6lEAAXAwAAAA==.',
He='Heaf:BAAANQAECgYIDAAAAA==.Hecateis:BAAANQAECgEIAQAAAA==.Heenan:BAAANQAECgIIBAAAAA==.Hellhaunt:BAAANQAECgUIBgAAAA==.Hellstar:BAAANQADCggIGAAAAA==.Hemdh:BAAANQADCggIDgABNQAFFAYIDgAfADYgAA==.Herukas:BAAANQAECgUIDAAAAA==.Hexsteele:BAAANQAECggIDwABNQAFFAYIDwAOANIYAA==.',
Hi='Hikons:BAAANQADCgUICgABNQAECggIHwABAFASAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgQJBQAAAA==.Holyblood:BAAANQAECgQIBwAAAA==.Holyfudge:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.Holyhyper:BAAANQAECgcIEAAAAA==.Holyness:BAAANQADCgEIAQAAAA==.Holywaddles:BAAANQAECgEIAQAAAA==.',
Hr='Hrinnu:BAAANQAECgYIEwAAAA==.',
Ht='Htownshawdo:BAAANQAECgUIDwAAAA==.',
Hu='Huevocutter:BAAANQADCggICAAAAA==.Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQAECgQICAAAAA==.Hurkaj:BAAANQAECgQICwAAAA==.Huwest:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCggIDQAAAA==.',
Ic='Icanhealyou:BAABNQAECoEmAAMVAAkKJB+wEgAKAwAVAAkKqh2wEgAKAwAhAAYKRRwoBwDSAQAAAA==.',
Ih='Ihatepriests:BAAANQAECgYIDgAAAA==.',
Il='Illusk:BAAANQAECgIJBQABNQAECggIHgAUAM4aAA==.',
In='Incisor:BAAANQADCgYIBgABNQAECgMIAgACAAAAAA==.Incline:BAAANQAECgQIBAAAAA==.Inola:BAAANQAECgMIAwAAAA==.Inoo:BAAANQAECgcIEgAAAA==.',
Ir='Irishhammer:BAAANQAECgQJBgAAAA==.',
Is='Isvnpcdhg:BAAANQAECgMIAwAAAA==.',
It='Itkovien:BAAANQAECgQIBAAAAA==.',
['Iá']='Ián:BAABNQAECoEdAAMWAAgKlB6RHgBpAQARAAYKjxrkZwDPAQAWAAQKIR+RHgBpAQAAAA==.',
Ja='Janq:BAABNQAECoEfAAIOAAgKmxOHQwAaAgAOAAgKmxOHQwAaAgAAAA==.Jayde:BAAANQADCgUIBgAAAA==.',
Je='Jellyfish:BAAANQAECgIIAgAAAA==.Jerrodsmage:BAAANQAECgQIBgAAAA==.Jezbrez:BAAANQAECgUIDwAAAA==.',
Ji='Jimmycricket:BAAANQADCgcIBwAAAA==.Jinz:BAAANQAECgYICgABNQAECggIHwASAJwYAA==.Jinzu:BAABNQAECoEfAAISAAgKnBjrSwBiAgASAAgKnBjrSwBiAgAAAA==.Jizzledizzle:BAAANQAECgQIBQAAAA==.',
Jo='Jono:BAAANQAECgQIBQAAAA==.Jordyne:BAAANQADCgMIAwAAAA==.',
Jp='Jphlip:BAABNQAECoEgAAMVAAgKbBmPNABTAgAVAAgKbBmPNABTAgAhAAQKyQ5yEADrAAAAAA==.Jpmagi:BAACNQAFFIEHAAIYAAQK2xi1FAB4AQAYAAQK2xi1FAB4AQA1AAQKgR4AAhgACQoLHwY2AAADABgACQoLHwY2AAADAAAA.',
Ju='Juice:BAAANQAECgIIAwAAAA==.Juisi:BAABNQAECoEbAAIfAAgKJx3QEwCVAgAfAAgKJx3QEwCVAgAAAA==.Jullene:BAAANQADCgcIDQAAAA==.Justania:BAAANQADCgEIAQABNQAECggIGQATABoDAA==.',
['Jô']='Jô:BAAANQAECgEIAQAAAA==.',
Ka='Kaeloth:BAABNQAECoEaAAISAAgK3xzeSABtAgASAAgK3xzeSABtAgAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQIBgAAAA==.Kalal:BAAANQAECgUIBQAAAA==.Kalebmonk:BAAANQADCggJDwABNQAECggIHgASAEQVAA==.Kalebpal:BAABNQAECoEeAAISAAgKRBXJaQAEAgASAAgKRBXJaQAEAgAAAA==.Kamtano:BAAANQAECgQJBgAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAABNQAECoEeAAMYAAgKYSMhTwC8AgAYAAcKrCMhTwC8AgAaAAEKVSEFKwBgAAAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.Kellholy:BAABNQAECoEZAAISAAkK0CSaBgCzAwASAAkK0CSaBgCzAwAAAA==.',
Kh='Khyzer:BAAANQADCgYIBgABNQAECggIIAAEAHoWAA==.',
Ki='Kickya:BAAANQABCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Kikii:BAAANQAECgQIBAAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgUIEgABNQADCggIDwACAAAAAA==.Kindeesver:BAAANQADCgMIAwABNQAECgMIAwACAAAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Kirriana:BAAANQAECgIIBQAAAA==.Kisara:BAAANQADCgIIAgABNQAECgcIGAAVAKEcAA==.',
Kk='Kkitty:BAAANQAECgEIAQAAAA==.',
Kl='Kleddus:BAAANQAECgMIBgAAAA==.Kletas:BAAANQAECgUJBQAAAA==.Kletus:BAAANQAECgQIBAAAAA==.',
Kn='Knokkpriest:BAAANQAECgYICwAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIDAABNQAECgcIEQACAAAAAA==.Korvash:BAAANQAECgQJCwAAAA==.',
Kr='Kroitz:BAAANQADCgUIBQAAAA==.Kromgol:BAAANQAFFAEIAQAAAA==.Krupp:BAAANQADCgUIBQAAAA==.',
Ku='Kujaku:BAAANQAECgQJBgAAAA==.',
Kw='Kwende:BAAANQADCggJHAAAAA==.',
Ky='Kyela:BAAANQAECgQJBgAAAA==.Kyrtion:BAABNQAECoEeAAQJAAgKnRICIQAJAgAJAAgKnRICIQAJAgAZAAEKmwOSegAlAAAiAAEK3AK8KgAcAAAAAA==.',
['Kä']='Kätsuö:BAAANQADCgcIDQABNQAECgQIBQACAAAAAA==.',
['Kø']='Kørupted:BAAANQAECgQIBwAAAA==.',
La='Lamiisa:BAAANQAECgQICAAAAA==.Lanaris:BAAANQAECgUICQAAAA==.Laurandrel:BAAANQAECgUICgAAAA==.Laved:BAABNQAECoEfAAMHAAgKfyKaEQAZAwAHAAgKfyKaEQAZAwAGAAIKrSHWPwC/AAAAAA==.Lawgi:BAABNQAECoEjAAIjAAgKDRs0EQA+AgAjAAgKDRs0EQA+AgAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkillem:BAAANQAECgMIAwABNQAECgYIEQACAAAAAA==.Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAAANQAECgYIEQAAAA==.',
Le='Lewìn:BAABNQAECoEUAAIDAAcKvSVZGAAJAwADAAcKvSVZGAAJAwAAAA==.',
Li='Likäbäws:BAAANQADCgYJCAAAAA==.Lilitü:BAAANQADCggICQAAAA==.Lilpoopsie:BAAANQAECgcIBwAAAA==.Lilshadow:BAAANQADCgIIAgAAAA==.Lilwascal:BAAANQADCgYIDwAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Linatheslayr:BAAANQADCggIDQAAAA==.Linossa:BAABNQAECoEYAAIYAAgKlg/8nQD/AQAYAAgKlg/8nQD/AQAAAA==.Lithiris:BAABNQAECoEZAAMTAAgKGgPzgABDAQATAAgKGgPzgABDAQASAAUKNARs+QC5AAAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lockjam:BAAANQADCgEIAgAAAA==.Lookiezi:BAABNQAECoEYAAITAAkK5hsFFgD9AgATAAkK5hsFFgD9AgAAAA==.Lovemuffîn:BAAANQAECgUIDwAAAA==.',
Lu='Lucidonis:BAABNQAECoEYAAIGAAgKdRLgHAD1AQAGAAgKdRLgHAD1AQAAAA==.Luminaconri:BAAANQAECgQIBwAAAA==.',
Ly='Lystia:BAAANQAECgUICQAAAA==.',
['Læ']='Læncelot:BAAANQAECgMIAwAAAA==.',
Ma='Madriel:BAAANQAECgUIBwAAAA==.Maelk:BAAANQADCggIDAABNQAECgEIAQACAAAAAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAABNQAECoEiAAMYAAgKlB1ieQBUAgAYAAgKexlieQBUAgAaAAIKLSHfHgC2AAAAAA==.Maladie:BAABNQAECoEgAAIMAAgKwxNANQD0AQAMAAgKwxNANQD0AQAAAA==.Malvaron:BAAANQADCgYICwAAAA==.Mauna:BAAANQAECgUIBQAAAA==.Mavzy:BAABNQAECoEdAAIXAAgKmBGkBQAfAgAXAAgKmBGkBQAfAgAAAA==.',
Mc='Mcbubbies:BAABNQAECoEZAAMFAAkKZCKSBQBmAwAFAAkKZCKSBQBmAwAVAAQKwRgvgQAjAQAAAA==.Mcfknkfc:BAAANQAECgUIBwAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQAECggIAgAAAA==.Melpomne:BAAANQADCgcICgAAAA==.',
Mi='Micti:BAABNQAECoEZAAIWAAcKrhb7DQAHAgAWAAcKrhb7DQAHAgAAAA==.Milamber:BAAANQAECgYIDgAAAA==.Minionrogue:BAAANQAECgIJAwAAAA==.Minyon:BAABNQAECoEfAAIFAAgK9SLYCQAfAwAFAAgK9SLYCQAfAwAAAA==.Miruna:BAAANQAECgEIAQAAAA==.Missiles:BAAANQADCgIIAgAAAA==.Missing:BAAANQAECgQICAABNQAECgYIDgACAAAAAA==.Missmage:BAAANQADCggICgAAAA==.',
Mo='Mogge:BAAANQAECgQIBAABNQAECggIHwAdABceAA==.Mommadragon:BAAANQAECgQJBgAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Moosè:BAAANQADCgYIFQAAAA==.',
Mu='Mugron:BAABNQAECoEcAAIdAAgKrCLNAwAaAwAdAAgKrCLNAwAaAwABNQAFFAYIFQAEAJgfAA==.',
My='Mydkfelloff:BAAANQAECggIAgABNQAECggIFgAOAN0fAA==.Myronath:BAAANQADCgMIAwABNQAECgUIBgACAAAAAA==.Mystafire:BAAANQAECgEIAQAAAA==.Mythpriest:BAAANQAECgIIAgABNQAECggIHAATAMYPAA==.',
Na='Nadlug:BAAANQADCgcIEwAAAA==.Naki:BAAANQAECgYICgABNQAECggIFwAYAM8WAA==.Naljubuites:BAAANQABCgYJDQAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Narìko:BAAANQAECgMIAwABNQAECgQIBQACAAAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neblig:BAAANQADCgcIBwAAAA==.Neebstrasza:BAAANQADCgYICAAAAA==.Nensuk:BAAANQAECgEIAQAAAA==.Newdamda:BAAANQAECgUICQAAAA==.',
Ni='Nicodormus:BAAANQAECgIJAgAAAA==.Nicolius:BAABNQAECoEeAAMTAAgKEhoiMwBcAgATAAgKEhoiMwBcAgAjAAIKxAEpVAA7AAAAAA==.Ningenalah:BAABNQAECoEdAAMMAAgKSSTzEQD1AgAMAAgKSSTzEQD1AgAeAAMKSyIXRwAiAQAAAA==.Ningenurion:BAAANQAECgIIAwABNQAECggIHQAMAEkkAA==.Nippÿ:BAABNQAECoEaAAMaAAgKcRhNBgBVAgAaAAgKcRhNBgBVAgAYAAMKDwflWAGiAAAAAA==.Niryûl:BAAANQADCgYIBgAAAA==.',
No='Norav:BAAANQAECgcJEAAAAA==.Nordryd:BAAANQADCggICAABNQAECgkJFwALAE8UAA==.Nordryde:BAABNQAECoEXAAQLAAkKTxQhEwBMAgALAAkKTxQhEwBMAgAKAAEK5hMAMQBCAAAkAAEKGhISHAA1AAAAAA==.Nordrydm:BAAANQAECgUIBQABNQAECgkJFwALAE8UAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQJBAAAAA==.',
Nu='Nuabo:BAAANQADCgMIAwABNQAECggIIQAEAIgcAA==.Numb:BAAANQADCggICAAAAA==.',
['Ní']='Níghtmäre:BAAANQAECgUIBQAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgQIBgAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAABNQAECoEgAAIPAAkK3CJJAQCmAwAPAAkK3CJJAQCmAwAAAA==.',
Os='Osyrus:BAAANQADCgEIAQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgQIBAAAAA==.',
Pa='Padreberk:BAAANQADCgYIEgAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQAECgMIBAAAAA==.Penpineapple:BAAANQAECgMIBAAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIIAgAAAA==.Persnickity:BAAANQADCggICAAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAAANQAECgQICQAAAA==.',
Pi='Pidi:BAAANQAECgYICgABNQAECggIIAAYADwXAA==.Pioree:BAABNQAECoEqAAQLAAkKFxlQEAB2AgALAAgKeBpQEAB2AgAKAAcKLhdTEQABAgAkAAQKOggHEwCqAAAAAA==.Pixen:BAEANQAECgQIBwABNQAECgkJJQARAJUYAA==.',
Po='Ponglenis:BAAANQADCggIEAABNQAECgYICwACAAAAAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECggIEwAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgkJFgAEAJcdAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgUIDAACAAAAAA==.',
Qu='Quanzanon:BAABNQAECoEZAAIHAAgKvQrmQQCfAQAHAAgKvQrmQQCfAQAAAA==.Quizhik:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.',
Ra='Rachelrae:BAABNQAECoEjAAIVAAgKGg8XVgDEAQAVAAgKGg8XVgDEAQAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Raffikki:BAAANQADCgIIAgAAAA==.Rag:BAAANQAECgUIBgAAAA==.Ralphy:BAAANQAECgUIEgAAAA==.Ramenwrapz:BAAANQAECgcIEQAAAA==.Raryees:BAABNQAECoEeAAQeAAkKmRs/IQAxAgAeAAkKwRY/IQAxAgAEAAYK4x0PMwABAgAMAAIKJBydgwClAAAAAA==.',
Re='Reddynon:BAABNQAECoEYAAMkAAcKPRoACgB9AQAkAAUK5BoACgB9AQAKAAUKzBesGwBTAQAAAA==.Reginald:BAAANQADCgIIAgABNQAECgUIDAACAAAAAA==.Relin:BAABNQAECoEfAAMQAAkKXSK2CQAcAwAQAAkKwiG2CQAcAwADAAEK/iWP/QBuAAAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgkJHwAQAF0iAA==.Relse:BAAANQADCgUIBgAAAA==.Renika:BAAANQAECgcJDwAAAA==.Renmazuo:BAAANQAECgcIDAAAAA==.Renrax:BAAANQAECgIIAgAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgIIBAAAAA==.Respwar:BAAANQADCgcIBwAAAA==.Revwild:BAAANQAECgQICQAAAA==.',
Ri='Ricassou:BAAANQAECgUIDgAAAA==.Rivendell:BAABNQAECoEiAAISAAgKoiObGwAqAwASAAgKoiObGwAqAwAAAA==.Rivit:BAAANQADCgMIAwAAAA==.',
Ro='Roonkmc:BAAANQAECgYIDgABNQADCgUIBgACAAAAAA==.Rorynne:BAAANQAECgYICgAAAA==.',
Rr='Rrubio:BAAANQAECgUIBQAAAA==.',
Ru='Rucy:BAAANQABCgMIAwAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICgABNQADCgUIBgACAAAAAA==.Ryuujin:BAAANQAECgEIAQAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgYICgABNQAFFAUIDgAFACwgAA==.',
Sa='Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQAECgQJBgAAAA==.Salorllis:BAAANQAECgUIDAAAAA==.Sanso:BAAANQAECgIJAgABNQAECggIHgAeABEaAA==.Sarah:BAAANQADCggIAgAAAA==.Saristia:BAAANQAECgQJBgAAAA==.Saveu:BAABNQAECoEYAAMVAAcK5hjNUwDNAQAVAAYKkBvNUwDNAQAFAAEKAQt1aAAnAAAAAA==.',
Sc='Schannon:BAAANQADCgQIBAAAAA==.Screampies:BAAANQAECgQIBgAAAA==.',
Se='Seagulls:BAEANQAECgIIAwAAAA==.Seayaa:BAAANQAECgQJBgAAAA==.Seiryu:BAAANQADCgMIAwAAAA==.Selindia:BAAANQAECgQJBgAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAECgQIBwACAAAAAA==.',
Sg='Sgt:BAAANQAECgYIDgAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIEAAAAA==.Shaedee:BAABNQAECoEaAAIFAAgKIxSoGwAgAgAFAAgKIxSoGwAgAgAAAA==.Shallon:BAAANQAECgYIDQAAAA==.Shamalott:BAAANQABCgQIBAAAAA==.Shammpoo:BAAANQABCgUIBgAAAA==.Shammyshaga:BAAANQAECgYIDwAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Sheeple:BAAANQABCgYJBAAAAA==.Shelby:BAAANQAECgQIBwAAAA==.Shilihu:BAAANQAECgIIAwAAAA==.Shinukishin:BAABNQAECoEXAAIMAAkK8yD2CwA0AwAMAAkK8yD2CwA0AwAAAA==.Shiu:BAAANQADCgYIBgAAAA==.Shnottz:BAAANQAECgcICgAAAA==.Shocknar:BAAANQADCgIIAgAAAA==.Shorzy:BAABNQAECoEYAAIJAAcK1hwFGgBUAgAJAAcK1hwFGgBUAgAAAA==.Shredzdh:BAABNQAECoEaAAIJAAgKLxsTFACaAgAJAAgKLxsTFACaAgAAAA==.Shrine:BAAANQADCggICAAAAA==.',
Si='Sienar:BAAANQADCggICwAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQAECgIIAgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQADCgUICgAAAA==.',
Sl='Sloppyblades:BAAANQADCggJCQAAAA==.Slu:BAACNQAFFIENAAMYAAUKrBZyDwCtAQAYAAUKrBZyDwCtAQAaAAEKmga7DQBGAAA1AAQKgSEAAhgACQr1I9sdAE0DABgACQr1I9sdAE0DAAE1AAQKCAgbABEARBsA.',
Sm='Smashinsmith:BAAANQAECgcICwAAAA==.Smorgasbord:BAAANQAECgIIAgAAAA==.',
Sn='Snackpack:BAAANQAECgYIEAAAAA==.Sneakodemus:BAAANQAECgEJAQAAAA==.Snockerz:BAAANQADCggICAAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQAECgMIBAAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQAECgUIDAAAAA==.Somno:BAABNQAECoEhAAMJAAgKyR4kEgCzAgAJAAgKVB0kEgCzAgAiAAEKriP6HgBnAAAAAA==.Sonory:BAAANQAECgIIAgAAAA==.Sophea:BAAANQADCgYIEgAAAA==.Soska:BAAANQADCgYIEgAAAA==.Soulfly:BAAANQAECgQIBgAAAA==.Soulsabi:BAABNQAECoESAAMRAAcKTiP+JgCzAgARAAcKTiP+JgCzAgAWAAIKuRFbUAB4AAAAAA==.Soulshaper:BAAANQAECgEIAQAAAA==.',
Sp='Spectral:BAABNQAECoElAAIVAAkKdCGaGADlAgAVAAkKdCGaGADlAgAAAA==.Spicy:BAAANQADCgMJAwAAAA==.Spiritspawn:BAABNQAECoEcAAINAAgKphbyQgAIAgANAAgKphbyQgAIAgAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAABNQAECoEjAAMGAAkKqBHgGAAlAgAGAAkKqBHgGAAlAgAHAAEKxQI/mAAnAAAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stabystab:BAAANQADCgUIBQAAAA==.Stardrift:BAAANQADCggIEgAAAA==.Stare:BAAANQABCgUIAwABNQAECgkJHQAGAH8WAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAABNQAECoEdAAQGAAkKfxZMEwBuAgAGAAkKfxZMEwBuAgAHAAQK0Q2/ZwDYAAAcAAMKLAxTIACkAAAAAA==.Stinggrayjr:BAAANQAECgYICwAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgUIBgAAAA==.Stórm:BAAANQADCggICwAAAA==.',
Su='Sunderance:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.Sunlife:BAAANQAECgIIAgAAAA==.Superhilock:BAABNQAECoEmAAQRAAkKIyMYKACtAgARAAcKtCIYKACtAgAWAAMKSiHMJwAjAQAXAAIK6iGGFAC0AAAAAA==.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBgACAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgYIDwAAAA==.',
Sw='Sweetcreams:BAAANQADCgUIBQAAAA==.',
Sy='Sybrand:BAABNQAECoEgAAIEAAgKehaaMQAJAgAEAAgKehaaMQAJAgAAAA==.Syrelliia:BAABNQAECoEkAAIfAAgKMQ8aJQD9AQAfAAgKMQ8aJQD9AQAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAABNQAECoEZAAIDAAgKJxZmPwBkAgADAAgKJxZmPwBkAgAAAA==.',
['Sø']='Sørta:BAAANQAECgQJBgAAAA==.',
Ta='Tae:BAAANQADCggIEQAAAA==.Taigun:BAAANQAECgQJBgAAAA==.Tanktotem:BAAANQAECgUIBQAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAABNQAECoEWAAIEAAkKlx0IFADgAgAEAAkKlx0IFADgAgAAAA==.',
Te='Techtonich:BAAANQADCgcICQAAAA==.Terkey:BAABNQAECoEgAAMVAAgKmRqsLQByAgAVAAgKmRqsLQByAgAhAAcKMhBtCQCLAQABNQAFFAMIBwAYAJEOAA==.',
Th='Tharkash:BAAANQAECgYICwAAAA==.Thedocktore:BAAANQADCgYIBgAAAA==.Thedockwho:BAAANQAECgUIEAAAAA==.Thedoctorwho:BAAANQADCggIFAAAAA==.Theliarcy:BAAANQAECgYICAAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thiccake:BAAANQABCgYICAABNQAECgYIDgACAAAAAA==.Thirdeye:BAABNQAECoEaAAIGAAgKbyEgCgDyAgAGAAgKbyEgCgDyAgAAAA==.Thordendal:BAAANQADCgEIAQAAAA==.Thoxic:BAAANQADCgUIBQABNQAECggIIAAEAHoWAA==.Thunderbuns:BAAANQAECgYIBgAAAA==.Thundrcat:BAAANQADCgIIAwAAAA==.',
Ti='Tiffaniie:BAAANQABCgIIAwAAAA==.Timidity:BAAANQAECgYICgAAAA==.Tinkerbelles:BAAANQADCgMIAwAAAA==.Tipz:BAAANQAECgQIBgAAAA==.Tiras:BAAANQADCgUJBQAAAA==.',
To='Toolip:BAAANQAECgYIDgAAAA==.Tornwraith:BAAANQAECgMIBQAAAA==.Towel:BAAANQADCgcIBwABNQAECgcIGgAWAKEWAA==.',
Tr='Traumademon:BAAANQABCggICwABNQADCggIEwACAAAAAA==.Traumasdruid:BAAANQADCggIEwAAAA==.Traviana:BAAANQADCggIEwAAAA==.Trehuga:BAABNQAECoEqAAMGAAkK1BkyEQCMAgAGAAkK1BkyEQCMAgAHAAEKthM+jwA6AAAAAA==.Trikky:BAAANQAECgIIAwAAAA==.Triso:BAABNQAECoEbAAIRAAgKRBsvMgCFAgARAAgKRBsvMgCFAgAAAA==.Trixiie:BAAANQAECgUIBQAAAA==.Trochanter:BAAANQAECgQIBQAAAA==.Tronus:BAAANQAECgQIBQABNQAECgYIEwACAAAAAA==.',
Ts='Tsukaar:BAABNQAECoEfAAIdAAgKFx5FBwCgAgAdAAgKFx5FBwCgAgAAAA==.',
Tu='Tutorialboss:BAACNQAFFIENAAIQAAUKvxj+BQCsAQAQAAUKvxj+BQCsAQA1AAQKgSkAAxAACQr+I28EAHkDABAACQryI28EAHkDAAMAAQpNJFgTAT8AAAAA.',
Tw='Twohorns:BAABNQAECoEkAAILAAgK2hVEFQAtAgALAAgK2hVEFQAtAgAAAA==.',
['Tö']='Töterfrieren:BAABNQAECoEaAAIaAAgK2wvBDACcAQAaAAgK2wvBDACcAQAAAA==.',
Ul='Ulrika:BAAANQADCggJHQAAAA==.Ultrön:BAAANQAECgcIEwAAAA==.',
Um='Umbryelle:BAAANQAECgMIBAAAAA==.',
Un='Undermaw:BAABNQAECoEgAAITAAgKzx5uIAC9AgATAAgKzx5uIAC9AgAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQAECgEJAQAAAA==.Uniscorn:BAAANQABCgIIAgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAgAAAA==.',
Va='Vaelianne:BAAANQADCgMIAwAAAA==.Vaesh:BAAANQAECgMIAwAAAA==.Valennah:BAAANQAECgEIAgAAAA==.Valgaar:BAAANQAECgQIBwAAAA==.Vaneste:BAAANQAECggIEgAAAA==.Vapelife:BAAANQABCgQIBAAAAA==.Vartlock:BAABNQAECoEgAAQRAAgK9R1QJQC6AgARAAgK9R1QJQC6AgAWAAEK9BXZZwA9AAAXAAEKyA85JQA7AAAAAA==.Vartrino:BAAANQAECgQIDgABNQAECggIIAARAPUdAA==.',
Ve='Veganator:BAABNQAECoEkAAIHAAkKDRi4HQCrAgAHAAkKDRi4HQCrAgAAAA==.Veggies:BAAANQAECgIIAgAAAA==.Velani:BAAANQADCggJFgABNQAECgcIGAAVAKEcAA==.Velynda:BAAANQADCggIDwABNQAECgYIDwACAAAAAA==.Vendoralia:BAAANQAECgIIAgAAAA==.Verifiedbot:BAAANQAECggIDgAAAA==.Verlant:BAABNQAECoEYAAITAAgKNxDrTwDmAQATAAgKNxDrTwDmAQAAAA==.',
Vi='Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwACAAAAAA==.Viraya:BAAANQADCgcIBwABNQAECgUIDwACAAAAAA==.Virâyâ:BAAANQADCgMIAwABNQAECgUIDwACAAAAAA==.Vitus:BAAANQAECgMIAwAAAA==.',
Vl='Vladriel:BAAANQAECgYICgAAAA==.',
Vo='Voidy:BAAANQADCgYIBgABNQAECggIHwABAFASAA==.Voljinn:BAAANQADCggIEgAAAA==.',
['Vá']='Vánlanthiriá:BAAANQADCgYIBgAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQAECgQIBgAAAA==.War:BAAANQAECgcIEQAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQADCggILwAAAA==.',
Wh='Whimsy:BAAANQADCggIHQABNQAECgEIAQACAAAAAA==.Whät:BAAANQADCggJHAABNQAECgQIBQACAAAAAA==.',
Wi='Willowhite:BAAANQAECgUIEAAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubers:BAAANQAECggIDQABNQAECggIFgAOAN0fAA==.Wubwub:BAABNQAECoEWAAIOAAgK3R8bHwDeAgAOAAgK3R8bHwDeAgAAAA==.Wulfjin:BAABNQAECoEbAAMDAAgK1RrMNACKAgADAAgKFxnMNACKAgAlAAcKHBSBBgDWAQAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQADCgcIEgAAAA==.',
['Xë']='Xërík:BAAANQAECgIIAwAAAA==.',
Ye='Yeyou:BAAANQADCgcIBwAAAA==.',
Yo='Yopan:BAAANQAECgQIBwAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUJBQABNQAECgQIBQACAAAAAA==.',
Za='Zada:BAAANQADCgQIBAAAAA==.Zah:BAAANQAECgMIAwAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zappÿ:BAAANQAECgIIAgAAAA==.Zaremis:BAABNQAECoEiAAMNAAgKzSMGEgAMAwANAAgKzSMGEgAMAwAOAAMKMgOo0wB8AAAAAA==.Zayehuo:BAAANQAECgEIAQAAAA==.',
Ze='Zeeni:BAAANQAECgUIDAAAAA==.Zelphie:BAABNQAECoEZAAIDAAcKmA+dbQDdAQADAAcKmA+dbQDdAQAAAA==.Zemmy:BAAANQAECgUIDAAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIBAAAAA==.Zenveyra:BAAANQAECgEIAQAAAA==.Zerase:BAABNQAECoEYAAQVAAcKoRwQNwBHAgAVAAcKoRwQNwBHAgAFAAQKcgoLRAC9AAAhAAIK0gTEGwBUAAAAAA==.Zerttrak:BAABNQAECoEjAAMDAAgK/iDkHADwAgADAAgK/iDkHADwAgAQAAEKORn8YgBIAAAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQAECgMIAwAAAA==.Zitania:BAAANQAECgUIDgAAAA==.Zivallia:BAAANQADCggICAAAAA==.',
Zu='Zugma:BAABNQAECoEfAAIUAAgKsh1LOQCpAgAUAAgKsh1LOQCpAgAAAA==.',
['Æl']='Ælin:BAAANQAECgUICQAAAA==.',
['Çh']='Çhristopher:BAAANQADCgYICgAAAA==.',
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
