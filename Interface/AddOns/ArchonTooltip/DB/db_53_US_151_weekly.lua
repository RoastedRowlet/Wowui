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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Restoration','Priest-Shadow','Paladin-Holy','Warlock-Demonology','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Priest-Holy','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Mage-Arcane','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Monk-Windwalker','Druid-Feral','DeathKnight-Frost','Priest-Discipline','Paladin-Protection','DemonHunter-Vengeance','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaluah:BAAANQAECgIIBgAAAA==.',
Ab='Abc:BAAANQAECgUIBQABNQAECggIJQABAFATAA==.',
Ac='Aclord:BAAANQADCgEIAQAAAA==.Acmis:BAAANQAECgEIAQABNQAECgUIEAACAAAAAA==.Acp:BAABNQAECoEaAAIDAAgKmRv8QQCAAgADAAgKmRv8QQCAAgAAAA==.',
Ad='Adomangma:BAAANQABCgQIBQAAAA==.',
Ae='Aetherconri:BAAANQADCgMIAwAAAA==.',
Ah='Ahjumma:BAABNQAECoEpAAIEAAgKEB2dIACWAgAEAAgKEB2dIACWAgAAAA==.',
Ai='Ailharn:BAABNQAECoEcAAIFAAcKyxjqVQDiAQAFAAcKyxjqVQDiAQAAAA==.',
Ak='Akadein:BAAANQAECgQIBAAAAA==.Akun:BAAANQADCgYIDAABNQAECgYIEgACAAAAAA==.Akurantirea:BAAANQAECgYIEgAAAA==.',
Al='Aldin:BAAANQAECgUIBQAAAA==.Algerax:BAAANQAECgIIBQAAAA==.Allise:BAAANQAECgMIBgAAAA==.Alphamaled:BAABNQAECoEeAAIEAAgKRgV/agAlAQAEAAgKRgV/agAlAQAAAA==.Alva:BAAANQADCgYICAAAAA==.Aléthia:BAAANQAECgYIEAAAAA==.',
Am='Ambaxius:BAAANQADCggIGgAAAA==.',
An='Anathemá:BAAANQAECgQIBAAAAA==.Ang:BAAANQAECgYIBgAAAA==.Ange:BAAANQADCggIEAAAAA==.Angeon:BAAANQAECgEIAQAAAA==.',
Ap='Apawpriest:BAABNQAECoEkAAIGAAgKyhV4HgAlAgAGAAgKyhV4HgAlAgAAAA==.',
Ar='Archious:BAAANQADCgQIBAAAAA==.Ardeyn:BAAANQADCgMIBAAAAA==.Arke:BAAANQAECgcIEgAAAA==.Arlynn:BAAANQABCgcICAABNQAECgcIGAAHAIAXAA==.Arraeroda:BAAANQAECgUIEAAAAA==.Arrence:BAAANQAECgQIBAABNQAECggIKQAEABAdAA==.Artleandra:BAAANQADCgMIAwABNQAECgcIGQAIAEAWAA==.',
As='Ashara:BAAANQAECgEIAQAAAA==.Ashlena:BAAANQADCgQIBAABNQAECggIGwAJAJYWAA==.Astela:BAABNQAECoEZAAMKAAcKzQ9YGgCSAQAKAAcKBA9YGgCSAQALAAMKAwyjFgC5AAAAAA==.Asuka:BAAANQADCggICgAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQABNQAECgkJHAAGAIMiAA==.Autumn:BAABNQAECoEiAAMMAAgKCR+GDwDAAgAMAAgKCR+GDwDAAgANAAIK0QQsmABHAAAAAA==.',
Av='Avan:BAAANQADCggICAAAAA==.Avatan:BAABNQAECoEaAAIOAAgKiAtSDgCmAQAOAAgKiAtSDgCmAQAAAA==.Avedeath:BAAANQADCggIHQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.Averlis:BAAANQADCgIIAgAAAA==.',
Ay='Ayane:BAAANQABCgYICAAAAA==.Ayara:BAACNQAFFIESAAIJAAUK6yNYAwAQAgAJAAUK6yNYAwAQAgA1AAQKgU0AAgkACQocJC0EAI0DAAkACQocJC0EAI0DAAAA.Ayrad:BAAANQAECgMIAwAAAA==.',
Ba='Badderdragon:BAABNQAECoEqAAMPAAkK5hjLCwCSAgAPAAkK5hjLCwCSAgAQAAEKTAbnRgA7AAAAAA==.Badmrmittens:BAAANQAECgIIAgAAAA==.Badmuffin:BAAANQAECgUIEAAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.Barthas:BAAANQABCgQIBAAAAA==.',
Be='Bearlygrillz:BAAANQAECgQIBQAAAA==.Bearrawrxd:BAAANQABCgMIAwAAAA==.Begachan:BAAANQADCgYIBgAAAA==.Berkstein:BAAANQAECgUICgAAAA==.',
Bi='Bigbadrock:BAAANQAECgUIBQAAAA==.Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgYIDgAAAA==.Bigspriesty:BAAANQAECgQIBQAAAA==.Bigtone:BAAANQAECgUICwAAAA==.Bimbomz:BAABNQAECoEhAAIRAAgKjCE0HwCyAgARAAgKjCE0HwCyAgAAAA==.Biochemist:BAAANQADCgMIBAABNQAECgkJJQAFAI8cAA==.Bioengineer:BAAANQADCgYIBgABNQAECgkJJQAFAI8cAA==.Biogenic:BAABNQAECoElAAQFAAkKjxzvLwB8AgAFAAgKIRzvLwB8AgASAAcKIhZaXADeAQATAAEKIAUgMAA4AAAAAA==.Biomass:BAAANQADCgcICAABNQAECgkJJQAFAI8cAA==.Biophysics:BAAANQAECgUICAABNQAECgkJJQAFAI8cAA==.Birdbrain:BAABNQAECoEfAAIUAAkKwyAfCgAkAwAUAAkKwyAfCgAkAwAAAA==.',
Bl='Bleebloop:BAAANQAECgUIBQABNQAECgkJKAATAKYkAA==.Blewîsa:BAAANQADCgcJCgAAAA==.Blvck:BAAANQADCgcIDQAAAA==.',
Bo='Boodylicious:BAAANQAECgEIAQABNQAECgcIFgAVABMMAA==.Borucmonk:BAAANQADCgcIFgABNQAECggIIAAOAGUSAA==.Borucwar:BAABNQAECoEgAAIOAAgKZRIMCgAIAgAOAAgKZRIMCgAIAgAAAA==.',
Br='Braedia:BAAANQAECgUIBwAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQAECgEIAQABNQAECgUIDQACAAAAAA==.Briele:BAAANQAECgYIEwAAAA==.Brise:BAAANQAECgEIAQAAAA==.Brosabi:BAAANQAECgYIDwABNQAECgcIGQAIAKEkAA==.Brucewaynexb:BAAANQABCgYIBgAAAA==.',
Bu='Bubs:BAAANQAECgQIDgAAAA==.Buddhïst:BAACNQAFFIEIAAIDAAQKDhe5CwBhAQADAAQKDhe5CwBhAQA1AAQKgR4AAwMACQoUI8URAEQDAAMACQoUI8URAEQDABQAAQp5E8dwAEYAAAAA.Burrhas:BAAANQADCggICgAAAA==.Buxky:BAAANQADCgIJAgAAAA==.',
['Bí']='Bítten:BAAANQAECgUICQAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgcIGQAIAEAWAA==.Cakewastaken:BAABNQAECoEZAAQIAAcKQBZ1cQDjAQAIAAcKIxZ1cQDjAQALAAIKTRFUGwCDAAAKAAEKEhAdcAA5AAAAAA==.Cakke:BAAANQADCgUIBgAAAA==.Calkestis:BAAANQADCgUJDAAAAA==.Candre:BAABNQAECoEpAAIWAAgKhyOTIwAdAwAWAAgKhyOTIwAdAwAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgMIBAABNQAECgUICwACAAAAAA==.Capristal:BAAANQAECgUICwAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgYIDAAAAA==.Cassiera:BAABNQAECoEpAAIHAAgKTBsNNAB5AgAHAAgKTBsNNAB5AgAAAA==.Cauldren:BAAANQADCggIKQAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Chay:BAABNQAECoEdAAIIAAkKTBqhLwCuAgAIAAkKTBqhLwCuAgAAAA==.Chaylin:BAAANQAECgEIAQABNQAECgkJHQAIAEwaAA==.Chikage:BAAANQAECgEIAQAAAA==.Chillen:BAABNQAECoEWAAMXAAgKiBwpDACjAgAXAAgKiBwpDACjAgAYAAEKOAEelQAUAAAAAA==.Chillzen:BAAANQADCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQAECgUICwAAAA==.Chopu:BAABNQAECoEYAAIOAAcKPBn9CQAJAgAOAAcKPBn9CQAJAgAAAA==.Chuckspadina:BAABNQAECoEqAAIHAAgK1Rs5LgCSAgAHAAgK1Rs5LgCSAgAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQAECgcIBwAAAA==.',
Ci='Cibø:BAAANQAECgUIDAAAAA==.Cilghalcao:BAAANQAECggIDAAAAA==.Cirdae:BAABNQAECoEnAAMFAAgKmRbhTAAEAgAFAAgKmRbhTAAEAgASAAEKjg1FCgFAAAAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgkJIAAIALsbAA==.Cloudstone:BAAANQAECgYIDQAAAA==.Clownfish:BAAANQADCgQIBAAAAA==.Clõud:BAAANQAECgYIEgAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAABNQAECoElAAIZAAgKJCPGJgAOAwAZAAgKJCPGJgAOAwAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgUICgAAAA==.',
Cr='Cragshot:BAAANQAECgMIAwAAAA==.Crazynip:BAABNQAECoEvAAIHAAkK3SAjCgBqAwAHAAkK3SAjCgBqAwAAAA==.Crickit:BAAANQAECgYIDwAAAA==.Crikit:BAAANQAECgQIBAABNQAECgYIDwACAAAAAA==.Crispr:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggIDwABNQAECgkJKAAVABgfAA==.Crylucis:BAABNQAECoEoAAIVAAkKGB+4GQD3AgAVAAkKGB+4GQD3AgAAAA==.Crymagus:BAAANQAECgUIBQABNQAECgkJKAAVABgfAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgACAAAAAA==.',
Cu='Cujo:BAABNQAECoEnAAISAAkKQhwpIADuAgASAAkKQhwpIADuAgAAAA==.',
Cy='Cyanidesun:BAAANQAECgEIAQAAAA==.Cybre:BAAANQAECgMIBgAAAA==.Cyndaquill:BAAANQAECggIAgAAAA==.Cyndil:BAABNQAECoEaAAIKAAcKJw3EGwCHAQAKAAcKJw3EGwCHAQAAAA==.Cysora:BAAANQAECgEJAQAAAA==.Cysport:BAAANQAECgIIBAAAAA==.',
['Cä']='Cästiel:BAAANQAECgQIDAAAAA==.',
Da='Daahntaat:BAAANQABCgMJBQAAAA==.Daesyn:BAAANQABCgMIBAAAAA==.Dallei:BAAANQAECgYIDAAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAABNQAECoEdAAIIAAgKhg5mdADbAQAIAAgKhg5mdADbAQAAAA==.Darcaine:BAAANQADCgUIBQABNQAECgkJJwAKANkPAA==.Darcane:BAABNQAECoEnAAQKAAkK2Q+AEADtAQAKAAgK0hCAEADtAQAIAAcK2gcLpwBVAQALAAIKzQasHgBoAAAAAA==.Darctanian:BAAANQAECgIIAgAAAA==.Darkchaos:BAAANQADCggICAAAAA==.Darkdestîny:BAAANQADCgcIBwAAAA==.Darkvayne:BAABNQAECoEYAAIDAAcKYSFVQQCCAgADAAcKYSFVQQCCAgAAAA==.Darrington:BAAANQAECgUIDgAAAA==.Dathrel:BAAANQADCggIKwAAAA==.Davoodoomon:BAAANQAECgEIAQAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.Dawnfoxer:BAAANQAECgQICwAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deburr:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.Deezaster:BAAANQAECgEIAQABNQAECggIDgACAAAAAA==.Def:BAABNQAECoEaAAIaAAgK2RbpiwBMAgAaAAgK2RbpiwBMAgAAAA==.Delani:BAAANQAECgUICQAAAA==.Delisius:BAAANQADCgYIBgAAAA==.Deltaco:BAAANQAECgEIAQAAAA==.Dementis:BAAANQADCggIEQAAAA==.Demonnova:BAACNQAFFIEOAAMJAAYKsxPHBQCuAQAJAAUKwRbHBQCuAQAbAAEKbwSzGwA5AAA1AAQKgSEAAwkACQrHHSIaAGwCAAkACAqTHiIaAGwCABsAAgqqDfdwAHsAAAAA.Dendude:BAAANQABCgEIAQAAAA==.Destiny:BAAANQAECgIJAgAAAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFIEcAAIGAAcKaiHEAADEAgAGAAcKaiHEAADEAgA1AAQKgS0AAgYACQqRJuoBAL0DAAYACQqRJuoBAL0DAAAA.',
Dg='Dghunter:BAABNQAECoEaAAIDAAcKzgJf9wDfAAADAAcKzgJf9wDfAAAAAA==.',
Di='Diabolis:BAAANQAECgUIBQAAAA==.Dietrinea:BAAANQADCgIIAgAAAA==.',
Do='Docsored:BAAANQAECgUICgAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQAECgYIDwAAAA==.Doomchick:BAAANQABCggIDgAAAA==.',
Dr='Dragn:BAAANQAECgIIAwAAAA==.Dragnas:BAABNQAECoEqAAIZAAgKIhrqUgB2AgAZAAgKIhrqUgB2AgAAAA==.Dragniperake:BAABNQAECoEbAAIHAAgKPhj8PwBGAgAHAAgKPhj8PwBGAgAAAA==.Dragnspawn:BAAANQADCgcIBwAAAA==.Drbluejeans:BAAANQAECgEIAQABNQAECggIDQACAAAAAA==.Drbug:BAAANQAECgYIDAABNQAECggIDQACAAAAAA==.Drdots:BAABNQAECoEiAAIIAAgKRxe/VwAuAgAIAAgKRxe/VwAuAgAAAA==.Dreadnaunt:BAAANQAECgQICAAAAA==.Dreamhc:BAABNQAECoEgAAMaAAgKgh4ZqgANAgAaAAYKWyAZqgANAgAcAAMKrxgFIADHAAAAAA==.Dreamwave:BAAANQADCggIEAABNQADCggIEQACAAAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drewed:BAAANQAECgYIDQAAAA==.Drmage:BAAANQAECgEIAQAAAA==.Drugral:BAABNQAECoEqAAIRAAkKdiF/FgDvAgARAAkKdiF/FgDvAgAAAA==.',
Du='Dugronn:BAAANQAECgIIAwAAAA==.',
Dw='Dwarfvadar:BAAANQAECgYICAAAAA==.',
Ea='Eadric:BAAANQAECgQIBAAAAA==.',
Ed='Edda:BAAANQAECgEJAQABNQAECggIGgAaANkWAA==.',
El='Elanthemage:BAAANQAECgUICgAAAA==.Elarya:BAAANQADCggICgAAAA==.Electria:BAAANQADCgIIAgAAAA==.Eleison:BAACNQAFFIETAAIGAAYKERy9AgAnAgAGAAYKERy9AgAnAgA1AAQKgR8AAwYACQrAIhcHAFcDAAYACQrAIhcHAFcDABUAAQp0Bt/bAEIAAAAA.Ellairis:BAABNQAECoEbAAIWAAgKYBYUdQAUAgAWAAgKYBYUdQAUAgAAAA==.Ellesperis:BAAANQAECgcIDQAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQAECgYIDwAAAA==.Elyna:BAAANQADCgYIBgABNQAECggIGwAdALcRAA==.Elyssarelsia:BAABNQAECoEWAAMYAAYK5AcTUgAnAQAXAAYKAgdxLQA3AQAYAAYKGgYTUgAnAQAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
Er='Eragôn:BAABNQAECoEfAAIPAAgK7BHlEwDwAQAPAAgK7BHlEwDwAQAAAA==.Erdrus:BAAANQADCggICAABNQAECgcIHQAVAA0dAA==.Erinyes:BAAANQAECgUIDAAAAA==.',
Es='Estee:BAAANQAECgYICAAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgMIBQAAAA==.',
Fa='Falafel:BAAANQADCggICAAAAA==.Faque:BAAANQADCgcIBwAAAA==.Fatfish:BAAANQADCggIBQAAAA==.Fatty:BAABNQAECoElAAMBAAgKUBPMFwDQAQABAAgKUBPMFwDQAQAeAAEKJwsNYgAsAAAAAA==.',
Fe='Feargasm:BAAANQABCgMIBQAAAA==.Felscream:BAAANQADCgcIDAAAAA==.Fenja:BAABNQAECoEqAAISAAgKUhVhTQAUAgASAAgKUhVhTQAUAgAAAA==.Feul:BAABNQAECoE7AAIFAAkKfBsnNABpAgAFAAkKfBsnNABpAgAAAA==.Feyded:BAAANQAECgUIEAAAAA==.Feylis:BAAANQADCgUIBQABNQAECgcIGQAKAM0PAA==.',
Fh='Fhara:BAAANQADCgUIBgAAAA==.',
Fi='Fiasko:BAABNQAECoEiAAIZAAgKgRs6WgBgAgAZAAgKgRs6WgBgAgAAAA==.Fiir:BAAANQADCggIEwAAAA==.Firehose:BAAANQADCgUIBQABNQAECgkJIAAIALsbAA==.Firesworn:BAAANQAECgIIAgAAAA==.Fizbang:BAAANQADCgQIBQAAAA==.',
Fl='Flippÿ:BAAANQAECgIIAwAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQAECgUIEAAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgUIDQAAAA==.',
Fo='Foreverdead:BAAANQADCgQIBwAAAA==.Formidonis:BAABNQAECoEnAAMIAAkKQiF8CQBwAwAIAAkKQiF8CQBwAwAKAAIKGhHnUgB7AAAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.Foxylady:BAAANQADCgIIAgAAAA==.',
Fr='Frieddough:BAAANQADCgMIAwAAAA==.Frizix:BAAANQAECgEIAwAAAA==.Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAABNQAECoEiAAMaAAgKLByTeQB0AgAaAAgKLByTeQB0AgAcAAIK/xHMMQBcAAAAAA==.',
Fu='Fubber:BAABNQAECoElAAIEAAkKOx4LFQDvAgAEAAkKOx4LFQDvAgAAAA==.Fulgur:BAAANQAECgYIEAAAAA==.Funsizegurly:BAABNQAECoEoAAIaAAgKpxpwfABuAgAaAAgKpxpwfABuAgAAAA==.Furrgie:BAAANQAECgEIAQAAAA==.',
Ga='Gallypotter:BAABNQAECoEZAAIDAAYKqRU7oACUAQADAAYKqRU7oACUAQAAAA==.Garygabagool:BAABNQAECoEcAAITAAkKayCRBgANAwATAAkKayCRBgANAwAAAA==.Gawdshamit:BAABNQAECoEcAAMFAAcK2w+RfgBiAQAFAAcK2w+RfgBiAQASAAQKegL55wCGAAAAAA==.Gawdspet:BAAANQAFFAMIBAABNQAFFAMIBwAKANMNAA==.',
Ge='Gemcutter:BAAANQAECgEIAQAAAA==.Geoffreey:BAAANQAECgQIBwAAAA==.',
Gh='Ghakk:BAAANQADCgYICAAAAA==.Ghostmane:BAAANQADCgIIAgAAAA==.Ghostorc:BAAANQAECgYIEAAAAA==.',
Gi='Gichidolo:BAAANQADCgEIAQAAAA==.Giegs:BAAANQAECgUICgAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAABNQAECoErAAIZAAgKuB2eSQCTAgAZAAgKuB2eSQCTAgAAAA==.Gnawrly:BAABNQAECoEaAAMfAAgKkxLbEADBAQAfAAcKHBTbEADBAQAMAAYK9gljPAAHAQAAAA==.',
Go='Goku:BAAANQADCggICAABNQAECgkJLgAVAA0gAA==.Gonzo:BAABNQAECoEbAAIdAAgKtxFQEgDTAQAdAAgKtxFQEgDTAQAAAA==.Goodgirl:BAAANQAECgYIEAABNQAECggIDQACAAAAAA==.Goodgurl:BAAANQAECggIDQAAAA==.Govrek:BAAANQAECgUIDQAAAA==.',
Gr='Greenstone:BAAANQADCgYIDgAAAA==.Gretchn:BAAANQADCgQIBAAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQAECgMIBQAAAA==.Grïm:BAABNQAECoEmAAIcAAkK6R7mAgAKAwAcAAkK6R7mAgAKAwAAAA==.',
Gt='Gtfobubble:BAAANQAECgYICgAAAA==.Gtfolava:BAAANQADCgcIDAAAAA==.',
Gu='Guldont:BAAANQAECgIIAgAAAA==.',
Ha='Hankering:BAAANQAECgIIAwABNQAECggIIgAgABEaAA==.Hankopher:BAABNQAECoEiAAQgAAgKERpjLwDwAQAgAAgKyRZjLwDwAQAEAAcKbxSzUACRAQARAAQK5BWlfQD8AAAAAA==.Hanziè:BAAANQAECgUIDAAAAA==.Haptics:BAABNQAECoEuAAMYAAkKiSPXBwBCAwAYAAkK7x/XBwBCAwAXAAUKiCT5FwAMAgAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgUIDQAAAA==.Hasbin:BAAANQADCgcIEAAAAA==.Hatzel:BAABNQAECoEiAAIFAAkKaB4bFwD/AgAFAAkKaB4bFwD/AgAAAA==.',
He='Heaf:BAAANQAECgYIEgAAAA==.Hecateis:BAAANQAECgEIAQAAAA==.Heenan:BAAANQAECgUICQAAAA==.Hellhaunt:BAAANQAECgUIBgAAAA==.Hellstar:BAAANQADCggIHQAAAA==.Hemdh:BAAANQADCggIDgABNQAFFAcIEAAYAOYcAA==.Herukas:BAAANQAECgUIDgAAAA==.Hexsteele:BAAANQAECggIEAABNQAFFAYIFQASACIeAA==.',
Hi='Hick:BAAANQADCggICAAAAA==.Higanbana:BAAANQADCgQIBAABNQAECgYICQACAAAAAA==.Hikons:BAAANQAECgEIAQABNQAECggIJQABAFATAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgQIBgAAAA==.Holyblood:BAAANQAECgQICgAAAA==.Holyfudge:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.Holyhyper:BAABNQAECoEbAAIWAAkKqx26PwCxAgAWAAkKqx26PwCxAgAAAA==.Holyness:BAAANQADCgEIAQAAAA==.Holywaddles:BAAANQAECgIIAwAAAA==.',
Hr='Hrinnu:BAABNQAECoEbAAIHAAgKoRrALgCQAgAHAAgKoRrALgCQAgAAAA==.',
Ht='Htownshawdo:BAABNQAECoEZAAIdAAcKngk8HgA3AQAdAAcKngk8HgA3AQAAAA==.',
Hu='Huevocutter:BAAANQADCggICAAAAA==.Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQAECgQICAAAAA==.Hurkaj:BAAANQAECgQICwAAAA==.Huwest:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCggIDQAAAA==.',
Ic='Icanhealyou:BAABNQAECoEuAAMVAAkKDSAIEwAeAwAVAAkKsx4IEwAeAwAhAAYKRRxNCADKAQAAAA==.',
Ih='Ihatepriests:BAAANQAECgYIEAAAAA==.',
Il='Illusk:BAAANQAECgIJBQABNQAECggIIgAZAIEbAA==.',
In='Incisor:BAAANQADCgYIBgABNQAECggIGwAJAJYWAA==.Incline:BAAANQAECgQIBAAAAA==.Inola:BAAANQAECgMIAwAAAA==.Inoo:BAAANQAECgcIEwAAAA==.',
Ir='Irishhammer:BAAANQAECgUIEAAAAA==.',
Is='Isvnpcdhg:BAAANQAECgMIBAAAAA==.',
It='Itkovien:BAAANQAECgUIBQAAAA==.',
['Iá']='Ián:BAABNQAECoEfAAMKAAgK1h6KIABiAQAIAAYK6BpqegDJAQAKAAQKIR+KIABiAQAAAA==.',
Ja='Janq:BAABNQAECoEnAAISAAkKixRjPQBXAgASAAkKixRjPQBXAgAAAA==.Jayde:BAAANQADCgUIBgAAAA==.',
Je='Jellyfish:BAAANQAECgMIAwAAAA==.Jerrodsmage:BAAANQAECgQIBwAAAA==.Jezbrez:BAAANQAECgUIDwAAAA==.',
Ji='Jimmycricket:BAAANQADCgcIBwAAAA==.Jinz:BAAANQAECgYIDwABNQAECggIJwAWAEYdAA==.Jinzu:BAABNQAECoEnAAIWAAgKRh3xQQCpAgAWAAgKRh3xQQCpAgAAAA==.Jizzledizzle:BAAANQAECgQIBgABNQAECgYICQACAAAAAA==.',
Jo='Jono:BAAANQAECgQIBgAAAA==.Jordyne:BAAANQADCgMIAwAAAA==.',
Jp='Jphlip:BAABNQAECoEkAAMVAAgKbBksQQBBAgAVAAgKbBksQQBBAgAhAAQKyQ6WEgDkAAAAAA==.Jpmagi:BAACNQAFFIEMAAIaAAUKlhgPEgC+AQAaAAUKlhgPEgC+AQA1AAQKgSEAAhoACQp4H5Y8AP8CABoACQp4H5Y8AP8CAAAA.',
Ju='Juice:BAAANQAECgMIBgAAAA==.Juisi:BAABNQAECoEiAAIYAAgKqx3PFQCoAgAYAAgKqx3PFQCoAgAAAA==.Jullene:BAAANQADCgcIDQAAAA==.Justania:BAAANQADCgEIAQABNQAECggIIAAHAJMFAA==.',
['Jô']='Jô:BAAANQAECgEIAQAAAA==.',
Ka='Kaeloth:BAABNQAECoEhAAIWAAgKNh/KQgCnAgAWAAgKNh/KQgCnAgAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQICQAAAA==.Kalal:BAAANQAECgYICwAAAA==.Kalebmonk:BAAANQADCggJDwABNQAECggIIgAWAIsWAA==.Kalebpal:BAABNQAECoEiAAIWAAgKixZleQAJAgAWAAgKixZleQAJAgAAAA==.Kamtano:BAAANQAECgUIEAAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAABNQAECoElAAMaAAgKYSMUWQC8AgAaAAcKrCMUWQC8AgAcAAEKVSHJMQBcAAAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.Kellholy:BAABNQAECoEdAAIWAAkK+CTkCgCcAwAWAAkK+CTkCgCcAwAAAA==.',
Kh='Khraden:BAAANQADCggICAAAAA==.Khyzer:BAAANQADCgYIBgABNQAECggIJwAEAFcaAA==.',
Ki='Kickya:BAAANQADCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Kikii:BAAANQAECgUIBQAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgUIFgABNQADCggIEQACAAAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Kirriana:BAAANQAECgIIBQAAAA==.Kisara:BAAANQADCgIIAgABNQAECgcIHQAVAA0dAA==.',
Kk='Kkitty:BAAANQAECgIIAwAAAA==.',
Kl='Klash:BAAANQAECgMIAwAAAA==.Kleddus:BAAANQAECgQICgAAAA==.Kletas:BAAANQAECgUJBQAAAA==.Kletus:BAAANQAECgQIBAAAAA==.',
Kn='Knokkpriest:BAAANQAECgYICwAAAA==.Knokkshee:BAAANQADCgIIAgAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIDAABNQAECgkJGwAiAJIhAA==.Korvash:BAAANQAECgYIEAAAAA==.',
Kr='Kroitz:BAAANQADCgUIBQAAAA==.Kromgol:BAAANQAFFAEIAQAAAA==.Krupp:BAAANQAECgEIAQAAAA==.',
Ku='Kujaku:BAAANQAECgUIEAAAAA==.Kushov:BAAANQADCgMIAwAAAA==.',
Kw='Kwende:BAAANQAECgIIAgAAAA==.',
Ky='Kyela:BAAANQAECgUIEAAAAA==.Kyrtion:BAABNQAECoEhAAQJAAkKhxTFGQBwAgAJAAkKhxTFGQBwAgAbAAEKmwNAiwAkAAAjAAEK3AKQMQAbAAAAAA==.',
['Kä']='Kätsuö:BAAANQAECgMIAwABNQAECgYICQACAAAAAA==.',
['Kø']='Kørupted:BAAANQAECgQIDAAAAA==.',
La='Lamiisa:BAAANQAECgQICAAAAA==.Lanaris:BAAANQAECgUIDQAAAA==.Laurandrel:BAAANQAECgUIDwAAAA==.Laved:BAABNQAECoEnAAMNAAkKsyMPDwA/AwANAAgK/yMPDwA/AwAMAAQKLhylMgBQAQAAAA==.Lawgi:BAABNQAECoEqAAIiAAgK7BswEwBLAgAiAAgK7BswEwBLAgAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkillem:BAAANQAECgQIBwABNQAECggIHQAIAPUZAA==.Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAABNQAECoEdAAMIAAgK9Rl8cADlAQAIAAYKERt8cADlAQAKAAIKoBYITwCGAAAAAA==.',
Le='Lewìn:BAABNQAECoEUAAIDAAcKvSVCIAD6AgADAAcKvSVCIAD6AgAAAA==.',
Li='Likäbäws:BAAANQADCgYJCAAAAA==.Lilitü:BAAANQADCggICQAAAA==.Lilpoopsie:BAAANQAECgcIBwAAAA==.Lilshadow:BAAANQADCgIIAgAAAA==.Lilwascal:BAAANQAECgMIAwAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Linatheslayr:BAAANQADCggIDQAAAA==.Linossa:BAABNQAECoEbAAIaAAgK0hC8rwABAgAaAAgK0hC8rwABAgAAAA==.Lithiris:BAABNQAECoEgAAMHAAgKkwXvhABiAQAHAAgKkwXvhABiAQAWAAUKNAS5HQG1AAAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lockjam:BAAANQAECgEIAQAAAA==.Lookiezi:BAABNQAECoEZAAIHAAkK5huWGwDyAgAHAAkK5huWGwDyAgAAAA==.Lovemuffîn:BAABNQAECoEZAAIZAAkKjhEWfwD6AQAZAAkKjhEWfwD6AQAAAA==.',
Lu='Lucidonis:BAABNQAECoEfAAIMAAgK4BNhHwAHAgAMAAgK4BNhHwAHAgAAAA==.Luminaconri:BAAANQAECgQIBwAAAA==.',
Ly='Lystia:BAAANQAECgYIDwAAAA==.',
['Læ']='Læncelot:BAAANQAECgMIAwAAAA==.',
Ma='Madriel:BAAANQAECgUIBwAAAA==.Maelk:BAAANQADCggIFAABNQAECgEIAQACAAAAAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAABNQAECoEqAAMaAAkKtR6nUwDIAgAaAAkK4RqnUwDIAgAcAAMKcCFXGAAQAQAAAA==.Mailla:BAAANQAECgUIBQAAAA==.Maladie:BAABNQAECoEkAAIRAAgKNxTUQgDqAQARAAgKNxTUQgDqAQAAAA==.Malvaron:BAAANQADCgYICwAAAA==.Mauna:BAAANQAECgUIBQAAAA==.Mavzy:BAABNQAECoEhAAILAAgKixJjBgAkAgALAAgKixJjBgAkAgAAAA==.Mayberav:BAAANQADCgYIBgAAAA==.',
Mc='Mcbubbies:BAABNQAECoEcAAMGAAkKgyKTBwBRAwAGAAkKgyKTBwBRAwAVAAQKwRi3lAAcAQAAAA==.Mcfknkfc:BAAANQAECgUICgAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQAECggIAgAAAA==.Megaroni:BAAANQADCgYIBgAAAA==.Melpomne:BAAANQADCgcICgAAAA==.Menerva:BAAANQAECggICAAAAA==.',
Mi='Micti:BAABNQAECoEhAAIKAAgKrRZCCgBKAgAKAAgKrRZCCgBKAgAAAA==.Milamber:BAABNQAECoEYAAMaAAcKyAdj/QBsAQAaAAcKxQdj/QBsAQAcAAEKYgOERAAtAAAAAA==.Minionrogue:BAAANQAECgIJAwAAAA==.Minyon:BAABNQAECoEjAAIGAAgKMyNwCwAaAwAGAAgKMyNwCwAaAwAAAA==.Miruna:BAAANQAECgIIAwAAAA==.Missiles:BAAANQADCgIIAgAAAA==.Missing:BAAANQAECgQICgABNQAECgcIEQACAAAAAA==.Missmage:BAAANQADCggICgAAAA==.',
Mo='Mogge:BAAANQAECgQIBAABNQAECggIJgAdABceAA==.Mommadragon:BAAANQAECgUIDgAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Monsterpal:BAAANQAECgEIAQAAAA==.Moosè:BAAANQADCgYIFQAAAA==.',
Mu='Mugron:BAABNQAECoEgAAIdAAgKLiNbBAAnAwAdAAgKLiNbBAAnAwABNQAFFAcIHAAEAEUfAA==.Murotarimp:BAAANQAECgEIAQAAAA==.',
My='Mydkfelloff:BAAANQAECggIAgABNQAFFAEIAQACAAAAAA==.Myronath:BAAANQADCgMIAwABNQAECgUIBgACAAAAAA==.Mystafire:BAAANQAECgEIAQAAAA==.Mythpriest:BAAANQAECgIIAgABNQAECggIHAAHAMYPAA==.',
Na='Nadlug:BAAANQADCgcIEwABNQAECgcIBwACAAAAAA==.Naki:BAAANQAECgYICgABNQAECggIGgAaANkWAA==.Naljubuites:BAAANQABCgYJDQAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Narìko:BAAANQAECgYICQAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neblig:BAAANQADCgcIBwAAAA==.Neebstrasza:BAAANQADCgYICgAAAA==.Nensuk:BAAANQAECgQIBQAAAA==.Neska:BAAANQAECgEIAQAAAA==.Newdamda:BAAANQAECgUICwAAAA==.',
Ni='Nicodormus:BAAANQAECgIJAgAAAA==.Nicolius:BAABNQAECoEiAAMHAAgKUxtfNAB3AgAHAAgKUxtfNAB3AgAiAAIKxAGIXwA7AAAAAA==.Ningenalah:BAABNQAECoEhAAMRAAgKgSSfEwAFAwARAAgKgSSfEwAFAwAgAAMKSyJVUgAbAQAAAA==.Ningenurion:BAAANQAECgIIAwABNQAECggIIQARAIEkAA==.Nippÿ:BAABNQAECoEeAAMcAAgKLRlCBwBSAgAcAAgKLRlCBwBSAgAaAAMKDwereAGdAAAAAA==.Niryûl:BAAANQADCgYIBgAAAA==.',
No='Norav:BAABNQAECoEcAAISAAkKSR1BHwD0AgASAAkKSR1BHwD0AgAAAA==.Nordryd:BAAANQADCggICAABNQAFFAUIBwAQAJsKAA==.Nordryde:BAACNQAFFIEHAAIQAAUKmwpSCgBaAQAQAAUKmwpSCgBaAQA1AAQKgRkABBAACQpPFKIVAEMCABAACQpPFKIVAEMCAA8AAQrmE0k1AEIAACQAAQoaEtofADUAAAAA.Nordrydm:BAAANQAECgUIBQABNQAFFAUIBwAQAJsKAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQJBAAAAA==.',
Nu='Nuabo:BAAANQAECgIIAgABNQAECggIKQAEABAdAA==.Numb:BAAANQADCggICAAAAA==.',
['Ní']='Níghtmäre:BAAANQAECgUIBQAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgUIBwAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAABNQAECoEoAAITAAkKpiTjAADIAwATAAkKpiTjAADIAwAAAA==.',
Os='Osyrus:BAAANQADCgEIAQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgUIBgAAAA==.',
Pa='Padreberk:BAAANQADCgYIEgAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQAECgUICQAAAA==.Penpineapple:BAAANQAECgMIBAAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIIAgAAAA==.Persnickity:BAAANQADCggICAAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAAANQAECgYIDwAAAA==.Phat:BAAANQADCgEIAQABNQAECggIJQABAFATAA==.',
Pi='Pidi:BAAANQAECgYIDAABNQAECggIKAAaAKcaAA==.Pioree:BAABNQAECoEqAAQQAAkKFxnOEgBrAgAQAAgKeBrOEgBrAgAPAAcKLhexEwDzAQAkAAQKOggyFgClAAAAAA==.Pixen:BAAANQAECgQIBwABNQAECgkJLwAIABcaAA==.',
Po='Ponglenis:BAAANQADCggIEAABNQAECgcIEQACAAAAAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECggIEwAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgkJHQAEAOcdAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.',
Qu='Quanzanon:BAABNQAECoEdAAINAAgKvQq0SgCQAQANAAgKvQq0SgCQAQAAAA==.Quizhik:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.',
Qw='Qwerty:BAAANQADCgUIBQABNQAECggIJQABAFATAA==.',
Ra='Rachelrae:BAABNQAECoErAAIVAAgKtw9QYgDHAQAVAAgKtw9QYgDHAQAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Raffikki:BAAANQADCgIIAgAAAA==.Rag:BAAANQAECgUICwAAAA==.Ralphy:BAAANQAECgUIEgAAAA==.Ramenwrapz:BAABNQAECoEXAAIVAAgKpB0jHgDeAgAVAAgKpB0jHgDeAgAAAA==.Raryees:BAABNQAECoEjAAQgAAkKNiAaKQAcAgAgAAkKwRYaKQAcAgAEAAYK4x06OwD2AQARAAYKFB0fRADjAQAAAA==.Raveñous:BAAANQADCgMIAwABNQAFFAMIBgAHALwYAA==.',
Re='Reddynon:BAABNQAECoEeAAMkAAcKdxyZCADdAQAkAAYKbxyZCADdAQAPAAUKfRiPHQBaAQAAAA==.Reginald:BAAANQADCgIIAgABNQAECgYIEgACAAAAAA==.Relin:BAABNQAECoEjAAMUAAkKDCPYCAA4AwAUAAkKtCLYCAA4AwADAAEK/iU2HQFsAAAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgkJIwAUAAwjAA==.Relse:BAAANQADCgYICAAAAA==.Renika:BAAANQAECgcJDwAAAA==.Renmazuo:BAAANQAECgcIDgAAAA==.Renrax:BAAANQAECgIIAgAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgQICAAAAA==.Respwar:BAAANQADCgcIBwAAAA==.Revadin:BAAANQAECggICAAAAA==.Revwild:BAAANQAECgQICQAAAA==.',
Ri='Ricassou:BAABNQAECoEXAAIlAAcKFR1ECwA7AgAlAAcKFR1ECwA7AgAAAA==.Rivendell:BAABNQAECoEqAAIWAAgKuiPnIgAgAwAWAAgKuiPnIgAgAwAAAA==.Rivit:BAAANQADCgMIAwAAAA==.',
Ro='Roonkmc:BAABNQAECoEYAAIDAAcKlwftpACJAQADAAcKlwftpACJAQABNQADCgYICAACAAAAAA==.Rorynne:BAAANQAECgYICgAAAA==.',
Rr='Rrubio:BAAANQAECgUIBwAAAA==.',
Ru='Rucy:BAAANQABCgMIAwAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICgABNQADCgYICAACAAAAAA==.Ryuujin:BAAANQAECgEIAQAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgYIDAABNQAFFAYIEwAGABEcAA==.',
Sa='Sabrewulf:BAAANQAECgEIAQAAAA==.Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQAECgUIEAAAAA==.Salorllis:BAAANQAECgYIEgAAAA==.Sanso:BAAANQAECgIJAgABNQAECggIIgAgABEaAA==.Sarah:BAAANQADCggIAgAAAA==.Saristia:BAAANQAECgUIEAAAAA==.Saveu:BAABNQAECoEbAAMVAAgKFRdlUQAFAgAVAAcKGxllUQAFAgAGAAEKAQuddQAnAAAAAA==.',
Sc='Schannon:BAAANQAECgQIBAAAAA==.Screampies:BAAANQAECgQIBgAAAA==.',
Se='Seagulls:BAEANQAECgIIBQAAAA==.Seayaa:BAAANQAECgUIEAAAAA==.Seiryu:BAAANQADCgMIAwAAAA==.Selindia:BAAANQAECgUIEAAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAFFAUIDQADAEgWAA==.',
Sg='Sgt:BAABNQAECoEYAAQYAAgKMhKTKQAUAgAYAAgKMhKTKQAUAgAXAAQK4wVdNwDaAAAmAAIKDAN5GAA/AAAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIEAAAAA==.Shaedee:BAABNQAECoEaAAIGAAgKIxSkIAANAgAGAAgKIxSkIAANAgAAAA==.Shallon:BAAANQAECgcIDgAAAA==.Shamalott:BAAANQABCgQIBAAAAA==.Shammpoo:BAAANQABCgUIBgAAAA==.Shammyshaga:BAAANQAECgYIDwAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Sheeple:BAAANQABCgYIBAAAAA==.Shelby:BAAANQAECgQIBwAAAA==.Shilihu:BAAANQAECgUICAAAAA==.Shinukishin:BAABNQAECoEaAAIRAAkKVSEbEgARAwARAAkKVSEbEgARAwAAAA==.Shiu:BAAANQADCgYIBgAAAA==.Shnottz:BAAANQAFFAEIAQAAAA==.Shocknar:BAAANQADCgIIAgAAAA==.Shorzy:BAABNQAECoEeAAIJAAcKqyAbFgCZAgAJAAcKqyAbFgCZAgAAAA==.Shredzdh:BAABNQAECoEiAAIJAAgK3R9sEADcAgAJAAgK3R9sEADcAgAAAA==.Shrine:BAAANQADCggICAAAAA==.',
Si='Sienar:BAAANQAECgIIAgAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQAECgIIAgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQADCgUICgAAAA==.',
Sl='Sloppyblades:BAAANQADCggICQAAAA==.Slu:BAACNQAFFIESAAMaAAYKxBfnCgAEAgAaAAYKxBfnCgAEAgAcAAEKmga7EQA/AAA1AAQKgSEAAhoACQr1I8YpADMDABoACQr1I8YpADMDAAE1AAQKCQkgAAgAuxsA.',
Sm='Smashinsmith:BAABNQAECoEVAAIZAAgKXBrvUgB1AgAZAAgKXBrvUgB1AgAAAA==.Smorgasbord:BAAANQAECgIIAgAAAA==.',
Sn='Snackpack:BAAANQAECgYIEAAAAA==.Sneakodemus:BAAANQAECgEJAQAAAA==.Snockerz:BAAANQADCggICAAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQAECgMIBQAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQAECgYIEgAAAA==.Somno:BAABNQAECoEpAAMJAAgKfh/iEwCyAgAJAAgK2x3iEwCyAgAjAAEKICWNIwBsAAAAAA==.Sonory:BAAANQAECgIIAgAAAA==.Sophea:BAAANQADCgYIFwAAAA==.Soska:BAAANQADCgYIEgAAAA==.Soulfly:BAAANQAECgQICgAAAA==.Soulsabi:BAABNQAECoEZAAMIAAcKoSRHJgDTAgAIAAcKoSRHJgDTAgAKAAIKuRGPVAB2AAAAAA==.Soulshaper:BAAANQAECgQIBQAAAA==.',
Sp='Spectral:BAACNQAFFIEGAAIVAAQKLRQbEQBTAQAVAAQKLRQbEQBTAQA1AAQKgScAAhUACQp0IfkfANQCABUACQp0IfkfANQCAAAA.Spicy:BAAANQADCgMJAwAAAA==.Spiritspawn:BAABNQAECoEcAAIFAAgKphbyTgD8AQAFAAgKphbyTgD8AQAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAABNQAECoEnAAMMAAkKqBFPHgARAgAMAAkKqBFPHgARAgANAAEKxQIPqgAlAAAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stabystab:BAAANQAECgIIAgAAAA==.Stardrift:BAAANQADCggIEgAAAA==.Stare:BAAANQABCgUIAwABNQAECgkJHwAMAHkXAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAABNQAECoEfAAQMAAkKeRckHQAeAgAMAAkKeRckHQAeAgANAAQK8A5ecADeAAAfAAMKLAzAJgCgAAAAAA==.Stinggrayjr:BAAANQAECgYIDwAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgUIBgAAAA==.Stórm:BAAANQADCggIEwAAAA==.',
Su='Sunderance:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.Sunlife:BAAANQAECggICQAAAA==.Superhilock:BAABNQAECoEqAAQIAAkKVCMdMwCiAgAIAAcK9CIdMwCiAgALAAMKSSTpDgA7AQAKAAMKSiEdKgAfAQAAAA==.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBgACAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgYIEwAAAA==.',
Sw='Sweetcreams:BAAANQADCgUIBQAAAA==.',
Sy='Sybrand:BAABNQAECoEnAAIEAAgKVxoRKQBeAgAEAAgKVxoRKQBeAgAAAA==.Syrelliia:BAABNQAECoEoAAIYAAkKcA7+KQASAgAYAAkKcA7+KQASAgAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAABNQAECoEdAAIDAAgK1BfXSgBmAgADAAgK1BfXSgBmAgAAAA==.',
['Sø']='Sørta:BAAANQAECgUIEAAAAA==.',
Ta='Tae:BAAANQAECgIIAgAAAA==.Taigun:BAAANQAECgUIEAAAAA==.Talendar:BAAANQAECgUIBQAAAA==.Tanktotem:BAAANQAECgUIBQAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAABNQAECoEdAAIEAAkK5x1/FwDbAgAEAAkK5x1/FwDbAgAAAA==.',
Te='Techtonich:BAAANQAECgUIBQAAAA==.Terisa:BAAANQABCgIIAgAAAA==.Terkey:BAABNQAECoEoAAMVAAkKqR7dDgA6AwAVAAkKqR7dDgA6AwAhAAcKMhDlCgCBAQABNQAFFAMICgAaABYPAA==.',
Th='Tharkash:BAAANQAECgYIEQAAAA==.Thedarktore:BAAANQADCgcIBwAAAA==.Thedocktore:BAAANQADCgYIBgAAAA==.Thedockwho:BAABNQAECoEYAAMSAAcK1xE2cQCdAQASAAcKzw82cQCdAQATAAQKkxLZIQACAQAAAA==.Thedoctorwho:BAAANQAECgIIAgAAAA==.Theliarcy:BAABNQAECoEUAAQVAAcKbxu4RAAzAgAVAAcK1Rq4RAAzAgAhAAQKxhjlDgAnAQAGAAEKjAYKcgArAAAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thiccake:BAAANQABCgYICAABNQAECgcIGQAIAEAWAA==.Thirdeye:BAABNQAECoEhAAIMAAkKKh8dCAArAwAMAAkKKh8dCAArAwAAAA==.Thordendal:BAAANQADCgEIAQAAAA==.Thoxic:BAAANQADCgUIBQABNQAECggIJwAEAFcaAA==.Thunderbuns:BAAANQAECgcICwAAAA==.Thundrcat:BAAANQADCgIIAwAAAA==.',
Ti='Tiffaniie:BAAANQABCgIIAwAAAA==.Timidity:BAAANQAECgcICwAAAA==.Tinkerbelles:BAAANQADCgMIAwAAAA==.Tipz:BAAANQAECgQIBgAAAA==.Tiras:BAAANQADCgUJBQAAAA==.',
To='Toolip:BAABNQAECoEYAAIHAAcKgBdqWgDnAQAHAAcKgBdqWgDnAQAAAA==.Tornwraith:BAAANQAECgMICAAAAA==.Towel:BAAANQADCgcIBwABNQAECggIIgAKAKMXAA==.',
Tr='Traumademon:BAAANQABCggICwABNQADCggIEwACAAAAAA==.Traumasdruid:BAAANQADCggIEwAAAA==.Traviana:BAAANQADCggIEwAAAA==.Trehuga:BAABNQAECoE0AAMMAAkKYxuLEACzAgAMAAkKYxuLEACzAgANAAEKGBi9mABGAAAAAA==.Trikky:BAAANQAECgIIBQAAAA==.Triso:BAABNQAECoEgAAIIAAkKuxv1JwDMAgAIAAkKuxv1JwDMAgAAAA==.Trixiie:BAAANQAECgUIBQAAAA==.Trochanter:BAAANQAECgQIBQAAAA==.Tronus:BAAANQAECgQIBQABNQAECggIGwAHAKEaAA==.',
Ts='Tsukaar:BAABNQAECoEmAAIdAAgKFx42CQCPAgAdAAgKFx42CQCPAgAAAA==.',
Tu='Tutorialboss:BAACNQAFFIESAAMUAAYKrhsPBwC1AQAUAAUKSBwPBwC1AQADAAIKIhcpGQC3AAA1AAQKgSsAAxQACQphJDIFAHcDABQACQpWJDIFAHcDAAMAAQpNJOEyAT8AAAAA.',
Tw='Twohorns:BAABNQAECoEsAAIQAAkKkBQ3EwBlAgAQAAkKkBQ3EwBlAgAAAA==.',
['Tö']='Töterfrieren:BAABNQAECoEiAAIcAAgKfA+9CwDNAQAcAAgKfA+9CwDNAQAAAA==.',
Ul='Ulrika:BAAANQAECgIIAgAAAA==.Ultrön:BAABNQAECoEbAAIWAAgKdxpJYABNAgAWAAgKdxpJYABNAgAAAA==.',
Um='Umbryelle:BAAANQAECgQIBQAAAA==.',
Un='Undermaw:BAABNQAECoEoAAIHAAkKMiAVDwBDAwAHAAkKMiAVDwBDAwAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQAECgMIBAAAAA==.Uniscorn:BAAANQABCgIIAgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAwAAAA==.',
Va='Vaelianne:BAAANQADCgUIBwAAAA==.Vaesh:BAAANQAECgQIBgAAAA==.Valennah:BAAANQAECgQIBgAAAA==.Valgaar:BAAANQAECgUIDAAAAA==.Vaneste:BAABNQAECoEYAAMIAAkKghxGOwCGAgAIAAgKZhxGOwCGAgAKAAEKYx2paABDAAAAAA==.Vapelife:BAAANQABCgQIBAAAAA==.Vartlock:BAABNQAECoEmAAQIAAgKmyCbJADZAgAIAAgKmyCbJADZAgALAAEKyA9NKQA7AAAKAAEK9BVMbwA6AAAAAA==.Vartrino:BAAANQAECgQIEAABNQAECggIJgAIAJsgAA==.',
Ve='Veganator:BAABNQAECoEoAAINAAkKaRhDIQClAgANAAkKaRhDIQClAgAAAA==.Veggies:BAAANQAECgIIAgAAAA==.Velani:BAAANQADCggJFgABNQAECgcIHQAVAA0dAA==.Velynda:BAAANQADCggIEAABNQAECgcIGQAKAM0PAA==.Vendoralia:BAAANQAECgIIBAAAAA==.Verifiedbot:BAAANQAECggIDgAAAA==.Verlant:BAABNQAECoEgAAIHAAgK9hB+WQDqAQAHAAgK9hB+WQDqAQAAAA==.',
Vi='Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwACAAAAAA==.Viraya:BAAANQAECgIIAgABNQAECgkJGQAZAI4RAA==.Virikae:BAAANQAECgYIBgAAAA==.Virâyâ:BAAANQADCgMIAwABNQAECgkJGQAZAI4RAA==.Vitus:BAAANQAECgMIAwAAAA==.',
Vl='Vladriel:BAAANQAECgYICgAAAA==.',
Vo='Voidy:BAAANQADCgYIBgABNQAECggIJQABAFATAA==.Voljinn:BAAANQADCggIFAAAAA==.',
['Vá']='Vánlanthiriá:BAAANQADCgYIBgAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQAECgQICAAAAA==.War:BAABNQAECoEbAAIiAAkKkiE5BABjAwAiAAkKkiE5BABjAwAAAA==.Warfury:BAAANQAECgQIBAAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQAECgEIAQAAAA==.',
Wh='Whimsy:BAAANQADCggIHQABNQAECgEIAQACAAAAAA==.Whät:BAAANQADCggJHAABNQAECgYICQACAAAAAA==.',
Wi='Willowhite:BAABNQAECoEYAAIDAAcKxwkhoQCSAQADAAcKxwkhoQCSAQAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubers:BAAANQAFFAEIAQAAAA==.Wubwub:BAABNQAECoEXAAISAAgK3R9nJgDKAgASAAgK3R9nJgDKAgABNQAFFAEIAQACAAAAAA==.Wulfjin:BAABNQAECoEcAAMDAAgK8Rp2QwB7AgADAAgKMxl2QwB7AgAnAAcKHBS8BwDBAQAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQAECgEIAQAAAA==.',
['Xë']='Xërík:BAAANQAECgMIBgAAAA==.',
Ye='Yeyou:BAAANQADCgcIBwAAAA==.',
Yo='Yopan:BAAANQAECgQICwAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUJBQABNQAECgYICQACAAAAAA==.',
Za='Zada:BAAANQADCgQIBAAAAA==.Zah:BAAANQAECgUIBQAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zappÿ:BAAANQAECgIIAgAAAA==.Zaremis:BAABNQAECoEqAAMFAAkKhCRxBQCLAwAFAAkKhCRxBQCLAwASAAMKMgOE7QB3AAAAAA==.Zayehuo:BAAANQAECgQIBQAAAA==.',
Ze='Zeeni:BAAANQAECgUIEAAAAA==.Zelphie:BAABNQAECoEfAAIDAAgKvxKcVABLAgADAAgKvxKcVABLAgAAAA==.Zemmy:BAAANQAECgYIEgAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIBAAAAA==.Zenveyra:BAAANQAECgEIAQAAAA==.Zerase:BAABNQAECoEdAAQVAAcKDR2EQwA4AgAVAAcKDR2EQwA4AgAGAAQKcgpnTQC1AAAhAAIK0gSFHwBRAAAAAA==.Zerttrak:BAABNQAECoEqAAMDAAgKsCIcHgAEAwADAAgKsCIcHgAEAwAUAAEKORnUcABFAAAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQAECgMIAwAAAA==.Zitania:BAABNQAECoEWAAIVAAcKEwwieQB2AQAVAAcKEwwieQB2AQAAAA==.Zivallia:BAAANQADCggICgAAAA==.',
Zu='Zugma:BAABNQAECoEfAAIZAAgKsh0LSgCSAgAZAAgKsh0LSgCSAgAAAA==.',
['Æl']='Ælin:BAAANQAECgUIDgAAAA==.',
['Çh']='Çhristopher:BAAANQADCgYICgAAAA==.',
['ßo']='ßorgrash:BAAANQADCgEIAQAAAA==.',
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
