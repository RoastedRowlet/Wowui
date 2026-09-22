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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Demonology','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Priest-Holy','Warlock-Destruction','DemonHunter-Havoc','Priest-Shadow','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Paladin-Protection','Warlock-Affliction','Evoker-Augmentation','Hunter-Marksmanship','Druid-Feral',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaluah:BAAANQAECgIIAwAAAA==.',
Ac='Acmis:BAAANQADCgYIFgABNQAECgQJBgABAAAAAA==.Acp:BAAANQAECgcJDwAAAA==.',
Ad='Adomangma:BAAANQABCgQIBQAAAA==.',
Ah='Ahjumma:BAABNQAECoEZAAICAAgK1xpAHgBkAgACAAgK1xpAHgBkAgAAAA==.',
Ai='Ailharn:BAAANQAECgUIDgAAAA==.',
Ak='Akadein:BAAANQADCgUIBQAAAA==.Akun:BAAANQADCgYIDAABNQAECgQJBwABAAAAAA==.Akurantirea:BAAANQAECgQJBwAAAA==.',
Al='Aldin:BAAANQADCgYIBgAAAA==.Algerax:BAAANQAECgIJBQAAAA==.Allise:BAAANQAECgEJAQAAAA==.Alphamaled:BAAANQAECgcJEQAAAA==.Alva:BAAANQADCgYJCAAAAA==.Aléthia:BAAANQAECgUJCgAAAA==.',
Am='Ambaxius:BAAANQADCgYJDAAAAA==.',
An='Anathemá:BAAANQADCgYICgAAAA==.Ang:BAAANQAECgYIBgAAAA==.Ange:BAAANQADCggIEAAAAA==.',
Ap='Apawpriest:BAAANQAECgYIEgAAAA==.',
Ar='Archious:BAAANQADCgQIBAAAAA==.Arke:BAAANQAECgUJBQAAAA==.Arraeroda:BAAANQAECgQJBgAAAA==.Arrence:BAAANQAECgIIAgABNQAECggJGQACANcaAA==.Artleandra:BAAANQADCgMJAwABNQAECgMJBgABAAAAAA==.',
As='Ashara:BAAANQAECgEIAQAAAA==.Ashlena:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Astela:BAAANQAECgUICQAAAA==.Asuka:BAAANQADCgIIAgAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQAAAA==.Autumn:BAAANQAECgYIDgAAAA==.',
Av='Avan:BAAANQADCggICAAAAA==.Avatan:BAAANQAECgUJDgAAAA==.Avedeath:BAAANQADCggIHQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.Averlis:BAAANQADCgIIAgAAAA==.',
Ay='Ayara:BAACNQAFFIEHAAIDAAQK7RpKBACBAQADAAQK7RpKBACBAQA1AAQKgUMAAgMACQqQIs4FAF4DAAMACQqQIs4FAF4DAAAA.Ayrad:BAAANQAECgMIAwAAAA==.',
Ba='Badderdragon:BAABNQAECoEdAAMEAAkKtxWPDABNAgAEAAgK3RePDABNAgAFAAEKpANTOQA4AAAAAA==.Badmrmittens:BAAANQADCggIDwAAAA==.Badmuffin:BAAANQAECgQIBgAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.Barthas:BAAANQABCgQIBAAAAA==.',
Be='Bearlygrillz:BAAANQAECgEIAQAAAA==.Bearrawrxd:BAAANQABCgMIAwAAAA==.Begachan:BAAANQADCgYJBgAAAA==.Berkstein:BAAANQAECgQJBAAAAA==.',
Bi='Bigbadrock:BAAANQABCgQJBAAAAA==.Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgYIDgAAAA==.Bigspriesty:BAAANQADCggJHAAAAA==.Bigtone:BAAANQAECgUICwAAAA==.Bimbomz:BAAANQAECgcJEgAAAA==.Biochemist:BAAANQADCgMIBAABNQAECggJGAAGAMEaAA==.Bioengineer:BAAANQADCgYIBgABNQAECggJGAAGAMEaAA==.Biogenic:BAABNQAECoEYAAQGAAgKwRqiNQAdAgAGAAcKABqiNQAdAgAHAAUKXhDAdQA0AQAIAAEKIAVoJQA+AAAAAA==.Biomass:BAAANQADCgcICAABNQAECggJGAAGAMEaAA==.Biophysics:BAAANQADCgYJCgABNQAECggJGAAGAMEaAA==.Birdbrain:BAAANQAECgcJEgAAAA==.',
Bl='Blewîsa:BAAANQADCgcJCgAAAA==.Blvck:BAAANQADCgcICAAAAA==.',
Bo='Boodylicious:BAAANQADCgYJDQABNQAECgUJCQABAAAAAA==.Borucmonk:BAAANQADCgcIEwABNQAECgQJBgABAAAAAA==.Borucwar:BAAANQAECgQJBgAAAA==.',
Br='Braedia:BAAANQADCggIFwAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQAECgEIAQABNQAECgIJAwABAAAAAA==.Briele:BAAANQAECgUICAAAAA==.Brise:BAAANQADCggIEAAAAA==.Brosabi:BAAANQAECgUJCQABNQAECgcIEQAJAE4jAA==.Brucewaynexb:BAAANQABCgYIBgAAAA==.',
Bu='Bubs:BAAANQAECgQICwAAAA==.Buddhïst:BAABNQAECoEaAAIKAAkKFCM3BgCGAwAKAAkKFCM3BgCGAwAAAA==.Burrhas:BAAANQADCgIIAgAAAA==.Buxky:BAAANQADCgIJAgAAAA==.',
['Bí']='Bítten:BAAANQAECgUICQAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgMJBgABAAAAAA==.Cakewastaken:BAAANQAECgMJBgAAAA==.Cakke:BAAANQADCgUIBgAAAA==.Calkestis:BAAANQADCgUJDAAAAA==.Candre:BAABNQAECoEZAAILAAgKtiGGHAD/AgALAAgKtiGGHAD/AgAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgMIBAABNQAECgQIBgABAAAAAA==.Capristal:BAAANQAECgQIBgAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgYIDAAAAA==.Cassiera:BAABNQAECoEZAAIMAAgKoBoPIwCGAgAMAAgKoBoPIwCGAgAAAA==.Cauldren:BAAANQADCggIJQAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Chay:BAAANQAFFAEIAQAAAA==.Chaylin:BAAANQADCgcICAABNQAFFAEIAQABAAAAAA==.Chikage:BAAANQAECgEIAQAAAA==.Chillen:BAAANQAECggIDAAAAA==.Chillzen:BAAANQADCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQAECgQJBgAAAA==.Chopu:BAAANQAECgUICwAAAA==.Chrîstîne:BAAANQADCgYIBgAAAA==.Chuckspadina:BAABNQAECoEbAAIMAAgKmhHcPQD/AQAMAAgKmhHcPQD/AQAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQADCgcIEQAAAA==.',
Ci='Cibø:BAAANQAECgIIAwAAAA==.Cilghalcao:BAAANQAECgIIAgAAAA==.Cirdae:BAABNQAECoEYAAMGAAgKnRYFTQC0AQAGAAcKaxQFTQC0AQAHAAEKjg3gzQBEAAAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgcIEwABAAAAAA==.Cloudstone:BAAANQAECgIIAgAAAA==.Clõud:BAAANQAECgQIBwAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAABNQAECoEbAAINAAgKsyBmHwD9AgANAAgKsyBmHwD9AgAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgUICgAAAA==.',
Cr='Crazynip:BAABNQAECoEdAAIMAAkKlx8KCQBRAwAMAAkKlx8KCQBRAwAAAA==.Crickit:BAAANQAECgUJCQAAAA==.Crispr:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggICAABNQAECggIGQAOAFUeAA==.Crylucis:BAABNQAECoEZAAIOAAgKVR4FIACOAgAOAAgKVR4FIACOAgAAAA==.Crymagus:BAAANQADCgcIBwABNQAECggIGQAOAFUeAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.',
Cu='Cujo:BAABNQAECoEZAAIHAAgKIxtHJgCGAgAHAAgKIxtHJgCGAgAAAA==.',
Cy='Cyanidesun:BAAANQADCgcIDgAAAA==.Cybre:BAAANQAECgEJAQAAAA==.Cyndaquill:BAAANQAECggJAgAAAA==.Cyndil:BAAANQAECgQJCgAAAA==.Cysora:BAAANQAECgEJAQAAAA==.',
['Cä']='Cästiel:BAAANQAECgQJCAAAAA==.',
Da='Daahntaat:BAAANQABCgMJBQAAAA==.Daesyn:BAAANQABCgMIBAAAAA==.Dallei:BAAANQAECgIIAgAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAAANQAECgUJDQAAAA==.Darcane:BAABNQAECoEbAAIPAAgKtQ9FDgD3AQAPAAgKtQ9FDgD3AQAAAA==.Darctanian:BAAANQADCggICAAAAA==.Darkdestîny:BAAANQADCgcJBwAAAA==.Darkvayne:BAAANQAECgcJCwAAAA==.Darrington:BAAANQAECgUICAAAAA==.Dathrel:BAAANQADCggJHQAAAA==.Davoodoomon:BAAANQADCggJCAAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.Dawnfoxer:BAAANQAECgEIAQAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deburr:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Deezaster:BAAANQAECgEIAQABNQAECggIBgABAAAAAA==.Def:BAAANQAECgcJEAAAAA==.Delani:BAAANQAECgEJAgAAAA==.Delisius:BAAANQADCgYIBgAAAA==.Deltaco:BAAANQADCgcJFwAAAA==.Dementis:BAAANQADCgUIBwABNQADCgUIDgABAAAAAA==.Demonnova:BAACNQAFFIEIAAMDAAQKEQ3PBgD9AAADAAMK8Q/PBgD9AAAQAAEKbwSpEQA/AAA1AAQKgR8AAwMACQrGHHcRAKMCAAMACAqTHncRAKMCABAAAgojCe9TAH4AAAAA.Dendude:BAAANQABCgEIAQAAAA==.Destiny:BAAANQAECgIJAgAAAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFIERAAIRAAYKxh6yAABsAgARAAYKxh6yAABsAgA1AAQKgScAAhEACQqHJqUAAOUDABEACQqHJqUAAOUDAAAA.',
Dg='Dghunter:BAAANQAECgUIDwAAAA==.',
Di='Dietrinea:BAAANQADCgIJAgAAAA==.',
Do='Docsored:BAAANQAECgEJAQAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQAECgUJCQAAAA==.Doomchick:BAAANQABCggJDAAAAA==.',
Dr='Dragn:BAAANQADCggJFAAAAA==.Dragnas:BAABNQAECoEbAAINAAgKkRPkVAAZAgANAAgKkRPkVAAZAgAAAA==.Dragniperake:BAAANQAECgYJDwAAAA==.Drbluejeans:BAAANQAECgEIAQABNQAECggIDAABAAAAAA==.Drbug:BAAANQAECgYIDAABNQAECggIDAABAAAAAA==.Drdots:BAAANQAECgYJEgAAAA==.Dreadnaunt:BAAANQAECgMJBAAAAA==.Dreamhc:BAABNQAECoEZAAMSAAgKrhx8fQAeAgASAAYKcB98fQAeAgATAAMKoxUTFwDOAAAAAA==.Dreamwave:BAAANQADCgUIBQABNQADCgUIDgABAAAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drewed:BAAANQAECgQIBAAAAA==.Drmage:BAAANQAECgEIAQAAAA==.Drugral:BAABNQAECoEdAAIUAAkK1BihFwCtAgAUAAkK1BihFwCtAgAAAA==.',
Du='Dugronn:BAAANQADCggJIwAAAA==.',
Dw='Dwarfvadar:BAAANQAECgIIAgAAAA==.',
Ea='Eadric:BAAANQAECgEJAQAAAA==.',
Ed='Edda:BAAANQAECgEJAQABNQAECgcJEAABAAAAAA==.',
El='Elanthemage:BAAANQAECgQIBAAAAA==.Elarya:BAAANQADCggJCAAAAA==.Eleison:BAACNQAFFIEKAAIRAAUKXhbqAgCzAQARAAUKXhbqAgCzAQA1AAQKgRoAAxEACQrBIQQGAFgDABEACQrBIQQGAFgDAA4AAQp0Bt+lAEIAAAAA.Ellairis:BAAANQAECgcJCQAAAA==.Ellesperis:BAAANQAECgQJBgAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQAECgQJBAAAAA==.Elyssarelsia:BAAANQAECgYJCwAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
Er='Eragôn:BAAANQAECgYJDQAAAA==.Erdrus:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.Erinyes:BAAANQAECgUIDAAAAA==.',
Es='Estee:BAAANQAECgIIAgAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgEIAQAAAA==.',
Fa='Falafel:BAAANQADCggICAAAAA==.Fatfish:BAAANQADCggIBQAAAA==.Fatty:BAABNQAECoEYAAMVAAgKLgvyFQCTAQAVAAgKLgvyFQCTAQAWAAEKJwt8RwAzAAAAAA==.',
Fe='Felscream:BAAANQADCgUIBQAAAA==.Fenja:BAABNQAECoEbAAIHAAgKbRAYQAD2AQAHAAgKbRAYQAD2AQAAAA==.Feul:BAABNQAECoE7AAIGAAkKfBsTHgCgAgAGAAkKfBsTHgCgAgAAAA==.Feyded:BAAANQAECgQJBgAAAA==.Feylis:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Fh='Fhara:BAAANQADCgUIBgAAAA==.',
Fi='Fiasko:BAABNQAECoEaAAINAAgKqBdSUQAmAgANAAgKqBdSUQAmAgAAAA==.Fiir:BAAANQADCggIEwAAAA==.Firehose:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.Fizbang:BAAANQADCgEJAQAAAA==.',
Fl='Flippÿ:BAAANQAECgIIAwAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQAECgQJBgAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgUIDQAAAA==.',
Fo='Foreverdead:BAAANQADCgQIBwAAAA==.Formidonis:BAABNQAECoEdAAMJAAgKOx34LABsAgAJAAcKeR34LABsAgAPAAIKGhEiRwCFAAAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.',
Fr='Frizix:BAAANQAECgEJAQAAAA==.Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAABNQAECoEaAAMSAAgK1xqLWgB9AgASAAgK1xqLWgB9AgATAAIK/xF1IQBvAAAAAA==.',
Fu='Fubber:BAABNQAECoEaAAICAAgKbR6vGACTAgACAAgKbR6vGACTAgAAAA==.Fulgur:BAAANQAECgUJCgAAAA==.Funsizegurly:BAABNQAECoEYAAISAAgKpRROegAmAgASAAgKpRROegAmAgAAAA==.Furrgie:BAAANQADCggJCAAAAA==.',
Ga='Gallypotter:BAABNQAECoEZAAIKAAYKqRWUawCrAQAKAAYKqRWUawCrAQAAAA==.Garygabagool:BAABNQAECoEcAAIIAAkKayD1AgBQAwAIAAkKayD1AgBQAwAAAA==.Gawdshamit:BAAANQAECgUIEAAAAA==.Gawdspet:BAAANQAECgIIAwABNQAECgkJJQAJAKwdAA==.',
Ge='Gemcutter:BAAANQADCgMJBAAAAA==.Geoffreey:BAAANQADCggIFwAAAA==.',
Gh='Ghakk:BAAANQADCgYICAAAAA==.Ghostmane:BAAANQADCgIIAgAAAA==.Ghostorc:BAAANQAECgUIDwAAAA==.',
Gi='Gichidolo:BAAANQADCgEIAQAAAA==.Giegs:BAAANQAECgUICgAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAABNQAECoEZAAINAAgKbBh7SgA/AgANAAgKbBh7SgA/AgAAAA==.Gnawrly:BAAANQAECgYJDwAAAA==.',
Go='Gonzo:BAABNQAECoEUAAIXAAcKyQ+SEACFAQAXAAcKyQ+SEACFAQAAAA==.Goodgirl:BAAANQAECgYIDQABNQAECggIDAABAAAAAA==.Goodgurl:BAAANQAECggIDAAAAA==.Govrek:BAAANQAECgIIBAAAAA==.',
Gr='Greenstone:BAAANQADCgUJCAAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQAECgEJAQAAAA==.Grïm:BAAANQAECgYIEwAAAA==.',
Gt='Gtfobubble:BAAANQAECgYICQAAAA==.Gtfolava:BAAANQADCgcIDAAAAA==.',
Gu='Guldont:BAAANQADCggJFgAAAA==.',
Ha='Hankering:BAAANQAECgIIAwABNQAECggIGgAYABEaAA==.Hankopher:BAABNQAECoEaAAQYAAgKERpoJwC6AQAYAAcKlBhoJwC6AQACAAYKRRUQRwBpAQAUAAQK5BVUUwAvAQAAAA==.Hanziè:BAAANQAECgEJAwAAAA==.Haptics:BAABNQAECoEdAAMZAAkKMB7ICQDtAgAZAAkKzRvICQDtAgAaAAUKPyLWFQD6AQAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgQJCQAAAA==.Hasbin:BAAANQADCgcIDAAAAA==.Hatzel:BAABNQAECoEcAAIGAAkKXB00DwAOAwAGAAkKXB00DwAOAwAAAA==.',
He='Heaf:BAAANQAECgUJBgAAAA==.Hecateis:BAAANQADCggIFgAAAA==.Heenan:BAAANQAECgEIAgAAAA==.Hellhaunt:BAAANQAECgEIAQAAAA==.Hellstar:BAAANQADCggIEgAAAA==.Hemdh:BAAANQADCggIDgABNQAFFAYJDQAZADYgAA==.Herukas:BAAANQAECgQJBwAAAA==.Hexsteele:BAAANQAECgcICgABNQAFFAUICQAHAN8ZAA==.',
Hi='Hikons:BAAANQADCgUICgABNQAECggJGAAVAC4LAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgQJBQAAAA==.Holyblood:BAAANQAECgQIBwAAAA==.Holyfudge:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Holyhyper:BAAANQAECgYIDwAAAA==.Holyness:BAAANQADCgEIAQAAAA==.Holywaddles:BAAANQADCggJFAAAAA==.',
Hr='Hrinnu:BAAANQAECgYJEAAAAA==.',
Ht='Htownshawdo:BAAANQAECgUJCgAAAA==.',
Hu='Huevocutter:BAAANQADCggICAAAAA==.Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQAECgQICAAAAA==.Hurkaj:BAAANQAECgQICQAAAA==.Huwest:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCggIDQAAAA==.',
Ic='Icanhealyou:BAABNQAECoEeAAMbAAgK8h0LBgDZAQAOAAgKIRvQIgB9AgAbAAYKRRwLBgDZAQAAAA==.',
Ih='Ihatepriests:BAAANQAECgUIDQAAAA==.',
Il='Illusk:BAAANQAECgIJBQABNQAECggIGgANAKgXAA==.',
In='Incisor:BAAANQADCgYIBgAAAA==.Incline:BAAANQAECgQIBAAAAA==.Inola:BAAANQAECgMIAwAAAA==.Inoo:BAAANQAECgYJCwAAAA==.',
Ir='Irishhammer:BAAANQAECgQJBgAAAA==.',
Is='Isvnpcdhg:BAAANQAECgEIAgAAAA==.',
It='Itkovien:BAAANQAECgQIBAAAAA==.',
['Iá']='Ián:BAABNQAECoEXAAMPAAcKKB8OHABwAQAJAAUKkRribAB+AQAPAAQKIR8OHABwAQAAAA==.',
Ja='Janq:BAABNQAECoEdAAIHAAgKvRHGOQAVAgAHAAgKvRHGOQAVAgAAAA==.Jayde:BAAANQADCgUIBgAAAA==.',
Je='Jerrodsmage:BAAANQAECgMIBAAAAA==.Jezbrez:BAAANQAECgUJDgAAAA==.',
Ji='Jinz:BAAANQAECgQIBAABNQAECggIGQALADcXAA==.Jinzu:BAABNQAECoEZAAILAAgKNxeqRABBAgALAAgKNxeqRABBAgAAAA==.Jizzledizzle:BAAANQAECgEJAQAAAA==.',
Jo='Jono:BAAANQAECgEJAQAAAA==.',
Jp='Jphlip:BAABNQAECoEYAAMOAAgKbBl+JwBkAgAOAAgKbBl+JwBkAgAbAAQKyQ7vDQDuAAAAAA==.Jpmagi:BAABNQAECoEbAAISAAkKkB2yMgD2AgASAAkKkB2yMgD2AgAAAA==.',
Ju='Juice:BAAANQADCggJFQAAAA==.Juisi:BAABNQAECoEbAAIZAAgKJx2DDQCzAgAZAAgKJx2DDQCzAgAAAA==.Jullene:BAAANQADCgcIBwAAAA==.Justania:BAAANQADCgEIAQABNQAECgcJDwABAAAAAA==.',
['Jô']='Jô:BAAANQAECgEIAQABNQAECgkJHAAHABIeAA==.',
Ka='Kaeloth:BAAANQAECgYJEgAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQIBgAAAA==.Kalal:BAAANQADCgcIDQAAAA==.Kalebmonk:BAAANQADCggJDwABNQAECggIGgALAOYUAA==.Kalebpal:BAABNQAECoEaAAILAAgK5hRQVwD8AQALAAgK5hRQVwD8AQAAAA==.Kamtano:BAAANQAECgQJBgAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAABNQAECoEWAAMSAAcKiSI1bgBIAgASAAYKHyM1bgBIAgATAAEKCB8lJgBWAAAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.Kellholy:BAAANQAECgcIDgAAAA==.',
Kh='Khyzer:BAAANQADCgYIBgABNQAECggJGQACABQUAA==.',
Ki='Kickya:BAAANQABCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgUIDgAAAA==.Kindeesver:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Kirriana:BAAANQAECgIJBQAAAA==.Kisara:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.',
Kk='Kkitty:BAAANQADCggJEQAAAA==.',
Kl='Kleddus:BAAANQAECgMJAwAAAA==.Kletas:BAAANQAECgUJBQAAAA==.Kletus:BAAANQADCgYJCAAAAA==.',
Kn='Knokkpriest:BAAANQAECgYICwAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIDAABNQAECgcIDwABAAAAAA==.Korvash:BAAANQAECgQJCwAAAA==.',
Kr='Kroitz:BAAANQADCgUIBQAAAA==.Kromgol:BAAANQAFFAEIAQAAAA==.',
Ku='Kujaku:BAAANQAECgQJBgAAAA==.',
Kw='Kwende:BAAANQADCggJHAAAAA==.',
Ky='Kyela:BAAANQAECgQJBgAAAA==.Kyrtion:BAABNQAECoEcAAQDAAgK7BAnHQAVAgADAAgK7BAnHQAVAgAQAAEKmwPqZwAlAAAcAAEK3AK6IgAcAAAAAA==.',
['Kä']='Kätsuö:BAAANQADCgYIBgABNQAECgEJAQABAAAAAA==.',
['Kø']='Kørupted:BAAANQAECgQJBgAAAA==.',
La='Lamiisa:BAAANQAECgQICAAAAA==.Lanaris:BAAANQAECgQIBAAAAA==.Laurandrel:BAAANQAECgMJBQAAAA==.Laved:BAABNQAECoEZAAMdAAgKuCAXEQADAwAdAAgKuCAXEQADAwAeAAIKrSGWNQDEAAAAAA==.Lawgi:BAABNQAECoEbAAIfAAgKrxiRDgAyAgAfAAgKrxiRDgAyAgAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAAANQAECgYICwAAAA==.',
Le='Lewìn:BAAANQAECggIDQAAAA==.',
Li='Likäbäws:BAAANQADCgYJCAAAAA==.Lilitü:BAAANQADCggICQAAAA==.Lilshadow:BAAANQADCgIIAgAAAA==.Lilwascal:BAAANQADCgYIDwAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Linatheslayr:BAAANQADCggIDQAAAA==.Linossa:BAABNQAECoEYAAISAAgKlg+ofgAbAgASAAgKlg+ofgAbAgAAAA==.Lithiris:BAAANQAECgcJDwAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lockjam:BAAANQADCgEIAQAAAA==.Lookiezi:BAABNQAECoEXAAIMAAkK5htYEAAIAwAMAAkK5htYEAAIAwAAAA==.Lovemuffîn:BAAANQAECgUJCgAAAA==.',
Lu='Lucidonis:BAAANQAECgYJDQAAAA==.Luminaconri:BAAANQAECgMIAwAAAA==.',
Ly='Lystia:BAAANQAECgIIBAAAAA==.',
['Læ']='Læncelot:BAAANQAECgMIAwAAAA==.',
Ma='Madriel:BAAANQAECgIIAgAAAA==.Maelk:BAAANQADCgQIBAABNQAECgkJHAAHABIeAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAABNQAECoEgAAMSAAgKHh1rXgBzAgASAAgKBRlrXgBzAgATAAIKLSFOGADCAAAAAA==.Maladie:BAABNQAECoEYAAIUAAgKJg/eLgD3AQAUAAgKJg/eLgD3AQAAAA==.Malvaron:BAAANQADCgUIBQAAAA==.Mauna:BAAANQAECgEIAQAAAA==.Mavzy:BAABNQAECoEZAAIgAAgKkw+9BAAXAgAgAAgKkw+9BAAXAgAAAA==.',
Mc='Mcbubbies:BAAANQAFFAEIAQAAAA==.Mcfknkfc:BAAANQAECgUIBQAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQAECggIAgAAAA==.Melpomne:BAAANQADCgcICgAAAA==.',
Mi='Micti:BAAANQAECgYJDwAAAA==.Milamber:BAAANQAECgQICAAAAA==.Minionrogue:BAAANQAECgIJAwAAAA==.Minyon:BAABNQAECoEYAAIRAAcKliN/DQDJAgARAAcKliN/DQDJAgAAAA==.Miruna:BAAANQADCgcICgAAAA==.Missiles:BAAANQADCgIIAgAAAA==.Missing:BAAANQAECgQJBAABNQAECgYIDQABAAAAAA==.Missmage:BAAANQADCggJCAAAAA==.',
Mo='Mogge:BAAANQAECgQIBAABNQAECgcIFwAXAMseAA==.Mommadragon:BAAANQAECgQJBgAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Moosè:BAAANQADCgYIFQAAAA==.',
Mu='Mugron:BAABNQAECoEUAAIXAAcKbSOiBADPAgAXAAcKbSOiBADPAgABNQAFFAYJDwACAAQYAA==.',
My='Mydkfelloff:BAAANQAECggIAgABNQAECggICAABAAAAAA==.Myronath:BAAANQADCgMJAwABNQAECgEIAQABAAAAAA==.Mystafire:BAAANQADCgYIDgAAAA==.Mythpriest:BAAANQAECgIIAgABNQAECggIGQAMAMYPAA==.',
Na='Nadlug:BAAANQADCgcIEwAAAA==.Naki:BAAANQAECgUICAABNQAECgcJEAABAAAAAA==.Naljubuites:BAAANQABCgYJDQAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Narìko:BAAANQADCgYIBgABNQAECgEJAQABAAAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neblig:BAAANQADCgcIBwAAAA==.Neebstrasza:BAAANQADCgYICAAAAA==.Nensuk:BAAANQADCggICQAAAA==.Newdamda:BAAANQAECgQIBAAAAA==.',
Ni='Nicodormus:BAAANQAECgIJAgAAAA==.Nicolius:BAABNQAECoEaAAMMAAgKJhekMgAyAgAMAAgKJhekMgAyAgAfAAIKxAHWRQBDAAAAAA==.Ningenalah:BAABNQAECoEZAAIUAAgKvyMlCwA0AwAUAAgKvyMlCwA0AwAAAA==.Ningenurion:BAAANQAECgIIAwABNQAECggIGQAUAL8jAA==.Nippÿ:BAAANQAECgYIEwAAAA==.Niryûl:BAAANQADCgYJBgAAAA==.',
No='Norav:BAAANQAECgcJEAAAAA==.Nordryd:BAAANQADCgcJBwABNQAECggIEQABAAAAAA==.Nordryde:BAAANQAECggIEQAAAA==.Nordrydm:BAAANQADCggICgABNQAECggIEQABAAAAAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQJBAAAAA==.',
Nu='Nuabo:BAAANQADCgMIAwABNQAECggJGQACANcaAA==.Numb:BAAANQADCggICAAAAA==.',
['Ní']='Níghtmäre:BAAANQAECgUIBQAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgQIBgAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAABNQAECoEdAAIIAAgKfCStAgBbAwAIAAgKfCStAgBbAwAAAA==.',
Os='Osyrus:BAAANQADCgEIAQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgQIBAAAAA==.',
Pa='Padreberk:BAAANQADCgYIEgAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQAECgEJAQAAAA==.Penpineapple:BAAANQAECgEJAQAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIJAgAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAAANQAECgQJBQAAAA==.',
Pi='Pidi:BAAANQAECgQIBAABNQAECggJGAASAKUUAA==.Pioree:BAABNQAECoEhAAQFAAgKeBqVDQCCAgAFAAgKeBqVDQCCAgAEAAQKhBajGwAsAQAhAAIKlAeNFQBMAAAAAA==.Pixen:BAEANQAECgQIBwABNQAECggIHwAJACUZAA==.',
Po='Ponglenis:BAAANQADCggIEAABNQAECgUIBQABAAAAAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECgYJEwAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgQJBwABAAAAAA==.',
Qu='Quanzanon:BAAANQAECgcIEgAAAA==.Quizhik:BAAANQADCggIGQABNQAECgYIDQABAAAAAA==.',
Ra='Rachelrae:BAABNQAECoEbAAIOAAgKXg7SRQDKAQAOAAgKXg7SRQDKAQAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Rag:BAAANQAECgIIAQAAAA==.Ralphy:BAAANQAECgUJDwAAAA==.Ramenwrapz:BAAANQAECgUJCQAAAA==.Raryees:BAABNQAECoEaAAMYAAkK1RpEFwBVAgAYAAkKixZEFwBVAgACAAUKDx/5NQDCAQAAAA==.',
Re='Reddynon:BAAANQAECgYJDgAAAA==.Reginald:BAAANQADCgIIAgABNQAECgQJBwABAAAAAA==.Relin:BAABNQAECoEZAAMiAAkKqx9LDADgAgAiAAkKEB9LDADgAgAKAAEK/iVm2gBvAAAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgkJGQAiAKsfAA==.Relse:BAAANQADCgEJAQAAAA==.Renika:BAAANQAECgcJDwAAAA==.Renmazuo:BAAANQAECgcIDAAAAA==.Renrax:BAAANQAECgIIAgAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgEIAgAAAA==.Revwild:BAAANQAECgQJCQAAAA==.',
Ri='Ricassou:BAAANQAECgQICQAAAA==.Rivendell:BAABNQAECoEaAAILAAgKnyKYGwAFAwALAAgKnyKYGwAFAwAAAA==.',
Ro='Roonkmc:BAAANQAECgUICAABNQADCgEJAQABAAAAAA==.Rorynne:BAAANQAECgUICAAAAA==.',
Rr='Rrubio:BAAANQAECgMIAwAAAA==.',
Ru='Rucy:BAAANQABCgMIAwAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICgABNQADCgEJAQABAAAAAA==.Ryuujin:BAAANQADCgYICwAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgUICAABNQAFFAUJCgARAF4WAA==.',
Sa='Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQAECgQJBgAAAA==.Salorllis:BAAANQAECgQJBwAAAA==.Sanso:BAAANQAECgIJAgABNQAECggIGgAYABEaAA==.Sarah:BAAANQADCggIAgAAAA==.Saristia:BAAANQAECgQJBgAAAA==.Saveu:BAAANQAECgYJEQAAAA==.',
Sc='Screampies:BAAANQAECgQIBgAAAA==.',
Se='Seagulls:BAEANQAECgEJAQAAAA==.Seayaa:BAAANQAECgQJBgAAAA==.Seiryu:BAAANQADCgMIAwAAAA==.Selindia:BAAANQAECgQJBgAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAFFAQICAAKAP8SAA==.',
Sg='Sgt:BAAANQAECgUICAAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIEAAAAA==.Shaedee:BAAANQAECgcIEwAAAA==.Shallon:BAAANQAECgYIDQAAAA==.Shammpoo:BAAANQABCgUIBgAAAA==.Shammyshaga:BAAANQAECgYICQAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Sheeple:BAAANQABCgYJBAAAAA==.Shelby:BAAANQAECgMJAwAAAA==.Shilihu:BAAANQAECgEJAQAAAA==.Shinukishin:BAAANQAECgUJDQAAAA==.Shiu:BAAANQADCgYIBgAAAA==.Shnottz:BAAANQAECgcICAAAAA==.Shorzy:BAAANQAECgYJDgAAAA==.Shredzdh:BAAANQAECgcJDwAAAA==.',
Si='Sienar:BAAANQADCggICwAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQAECgIIAgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQADCgUJBQAAAA==.',
Sl='Sloppyblades:BAAANQADCggJCQAAAA==.Slu:BAACNQAFFIEIAAMSAAQK6BYdDwBqAQASAAQK6BYdDwBqAQATAAEKmgYoCQBKAAA1AAQKgR4AAhIACQqlI1oXAFsDABIACQqlI1oXAFsDAAE1AAQKBwgTAAEAAAAA.',
Sm='Smashinsmith:BAAANQAECgMIBQAAAA==.Smorgasbord:BAAANQAECgIIAgAAAA==.',
Sn='Snackpack:BAAANQAECgYIDgAAAA==.Sneakodemus:BAAANQAECgEJAQAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQAECgEIAQAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQAECgQIBwAAAA==.Somno:BAABNQAECoEZAAIDAAgKFxW2GQA8AgADAAgKFxW2GQA8AgAAAA==.Sonory:BAAANQADCggICAAAAA==.Sophea:BAAANQADCgYJDQAAAA==.Soska:BAAANQADCgYIDAAAAA==.Soulfly:BAAANQAECgEJAgAAAA==.Soulsabi:BAABNQAECoERAAMJAAcKTiMkGgDMAgAJAAcKTiMkGgDMAgAPAAIKuRG6SQB+AAAAAA==.Soulshaper:BAAANQADCgcJGwAAAA==.',
Sp='Spectral:BAABNQAECoEjAAIOAAkKdCG5EAD4AgAOAAkKdCG5EAD4AgAAAA==.Spicy:BAAANQADCgMJAwAAAA==.Spiritspawn:BAABNQAECoEcAAIGAAgKphYcMwAqAgAGAAgKphYcMwAqAgAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAABNQAECoEaAAMeAAkKcg7xFgACAgAeAAkKcg7xFgACAgAdAAEKxQI/iQAoAAAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stardrift:BAAANQADCggIEgAAAA==.Stare:BAAANQABCgUIAwAAAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAABNQAECoEWAAQeAAkKCxQYEgBHAgAeAAkKCxQYEgBHAgAdAAQK0Q24WgDgAAAjAAMKLAzkGQCrAAAAAA==.Stinggrayjr:BAAANQAECgQIBQAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgUIBgAAAA==.Stórm:BAAANQADCgYICQAAAA==.',
Su='Sunderance:BAAANQADCgUIBQABNQAECgkJHAAHABIeAA==.Sunlife:BAAANQAECgIIAQAAAA==.Superhilock:BAABNQAECoEdAAQJAAkKIyHgIwCXAgAJAAcKPSDgIwCXAgAPAAMKCyGqJQAhAQAgAAIK6iHLEAC6AAAAAA==.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgYIDwAAAA==.',
Sy='Sybrand:BAABNQAECoEZAAICAAgKFBQYLQD4AQACAAgKFBQYLQD4AQAAAA==.Syrelliia:BAABNQAECoEcAAIZAAgKLA6YGwAKAgAZAAgKLA6YGwAKAgAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAAANQAECgcIDgAAAA==.',
['Sø']='Sørta:BAAANQAECgQJBgAAAA==.',
Ta='Tae:BAAANQADCggICwAAAA==.Taigun:BAAANQAECgQJBgAAAA==.Tanktotem:BAAANQAECgUIBQAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAAANQAECgYIDAAAAA==.',
Te='Techtonich:BAAANQADCgIJAgAAAA==.Terkey:BAABNQAECoEeAAMOAAgKmRrAIQCDAgAOAAgKmRrAIQCDAgAbAAcKMhC5BwCZAQAAAA==.',
Th='Tharkash:BAAANQAECgQJBQAAAA==.Thedocktore:BAAANQADCgYIBgAAAA==.Thedockwho:BAAANQAECgUJCwAAAA==.Thedoctorwho:BAAANQADCgcJDAAAAA==.Theliarcy:BAAANQAECgIIAgAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thirdeye:BAABNQAECoEYAAIeAAgKQiCwBwD6AgAeAAgKQiCwBwD6AgAAAA==.Thordendal:BAAANQADCgEIAQAAAA==.Thoxic:BAAANQADCgUJBQABNQAECggJGQACABQUAA==.Thunderbuns:BAAANQADCggIEAAAAA==.Thundrcat:BAAANQADCgEIAQAAAA==.',
Ti='Tiffaniie:BAAANQABCgIIAwAAAA==.Timidity:BAAANQAECgMIBQAAAA==.Tinkerbelles:BAAANQADCgMIAwAAAA==.Tipz:BAAANQAECgQIBgAAAA==.Tiras:BAAANQADCgUJBQAAAA==.',
To='Toolip:BAAANQAECgQICAAAAA==.Tornwraith:BAAANQAECgIJAgAAAA==.Towel:BAAANQADCgcIBwABNQAECgUJEAABAAAAAA==.',
Tr='Traumademon:BAAANQABCggICwABNQADCggIEwABAAAAAA==.Traumasdruid:BAAANQADCggIEwAAAA==.Traviana:BAAANQADCggIEwAAAA==.Trehuga:BAABNQAECoElAAIeAAkKExlZDgCDAgAeAAkKExlZDgCDAgAAAA==.Trikky:BAAANQAECgEIAQAAAA==.Triso:BAAANQAECgcIEwAAAA==.Trochanter:BAAANQAECgQIBAAAAA==.Tronus:BAAANQAECgMIBAABNQAECgYJEAABAAAAAA==.',
Ts='Tsukaar:BAABNQAECoEXAAIXAAcKyx4xBwBuAgAXAAcKyx4xBwBuAgAAAA==.',
Tu='Tutorialboss:BAACNQAFFIEKAAIiAAUKuxUjBQCbAQAiAAUKuxUjBQCbAQA1AAQKgScAAyIACQr+IxgDAJEDACIACQryIxgDAJEDAAoAAQpNJO7vAD8AAAAA.',
Tw='Twohorns:BAABNQAECoEdAAIFAAgKFhL1FAABAgAFAAgKFhL1FAABAgAAAA==.',
['Tö']='Töterfrieren:BAAANQAECgYJEQAAAA==.',
Ul='Ulrika:BAAANQADCggJHQAAAA==.Ultrön:BAAANQAECgYIDgAAAA==.',
Um='Umbryelle:BAAANQAECgEJAQAAAA==.',
Un='Undermaw:BAABNQAECoEeAAIMAAgKzx64GADJAgAMAAgKzx64GADJAgAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQAECgEJAQAAAA==.Uniscorn:BAAANQABCgIIAgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAgAAAA==.',
Va='Valennah:BAAANQAECgEIAQAAAA==.Valgaar:BAAANQAECgMJAwAAAA==.Vaneste:BAAANQAECggJEAAAAA==.Vartlock:BAABNQAECoEYAAMJAAgKABsgIwCbAgAJAAgKABsgIwCbAgAPAAEK9BW6YQA9AAAAAA==.Vartrino:BAAANQAECgQJCgABNQAECggIGAAJAAAbAA==.',
Ve='Veganator:BAABNQAECoEbAAIdAAgK+Bi6IABoAgAdAAgK+Bi6IABoAgAAAA==.Veggies:BAAANQAECgIIAgAAAA==.Velani:BAAANQADCggJFgABNQAECgYIDgABAAAAAA==.Velynda:BAAANQADCggJCAABNQAECgUICQABAAAAAA==.Vendoralia:BAAANQADCgIJAwAAAA==.Verifiedbot:BAAANQAECggIBgAAAA==.Verlant:BAAANQAECgUIDQAAAA==.',
Vi='Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwABAAAAAA==.Virâyâ:BAAANQADCgMIAwABNQAECgUJCgABAAAAAA==.Vitus:BAAANQADCggJDQAAAA==.',
Vl='Vladriel:BAAANQAECgQIBwAAAA==.',
Vo='Voljinn:BAAANQADCggIEgAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQAECgMJBAAAAA==.War:BAAANQAECgcIDwAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQADCggIKQAAAA==.',
Wh='Whimsy:BAAANQADCggIHQABNQAECgkJHAAHABIeAA==.Whät:BAAANQADCggJHAABNQAECgEJAQABAAAAAA==.',
Wi='Willowhite:BAAANQAECgUJCwAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubers:BAAANQAECggICAAAAA==.Wubwub:BAAANQAECgcIDgABNQAECggICAABAAAAAA==.Wulfjin:BAAANQAECgYIEAAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQADCgcJEgAAAA==.',
['Xë']='Xërík:BAAANQAECgEJAQAAAA==.',
Ye='Yeyou:BAAANQADCgcJBwAAAA==.',
Yo='Yopan:BAAANQAECgMJAwAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.',
Za='Zada:BAAANQADCgQIBAAAAA==.Zah:BAAANQAECgEJAQAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zappÿ:BAAANQAECgIJAgAAAA==.Zaremis:BAABNQAECoEgAAMGAAgKzSPcDAAkAwAGAAgKzSPcDAAkAwAHAAMKMgM2tgB/AAAAAA==.Zayehuo:BAAANQAECgEIAQAAAA==.',
Ze='Zeeni:BAAANQAECgQIBwAAAA==.Zelphie:BAAANQAECgYIEAAAAA==.Zemmy:BAAANQAECgQJBwAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIBAAAAA==.Zenveyra:BAAANQAECgEIAQAAAA==.Zerase:BAAANQAECgYIDgAAAA==.Zerttrak:BAABNQAECoEbAAIKAAgK5CDkFAD+AgAKAAgK5CDkFAD+AgAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQAECgMIAwAAAA==.Zitania:BAAANQAECgUJCQAAAA==.',
Zu='Zugma:BAABNQAECoEfAAINAAgKsh1aKQDJAgANAAgKsh1aKQDJAgAAAA==.',
['Æl']='Ælin:BAAANQAECgIJBAAAAA==.',
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
