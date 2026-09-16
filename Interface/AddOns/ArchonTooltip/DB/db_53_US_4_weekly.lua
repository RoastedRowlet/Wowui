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

local lookup = {'Evoker-Devastation','Rogue-Assassination','Unknown-Unknown','Rogue-Subtlety','Evoker-Augmentation','Hunter-BeastMastery','Warrior-Arms','Monk-Windwalker','Druid-Feral','Paladin-Retribution','Priest-Shadow','Priest-Holy','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Evoker-Preservation','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Protection','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Rogue-Outlaw','Shaman-Elemental','Monk-Brewmaster','Warrior-Fury','Shaman-Restoration',}
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aabc:BAAANQADCgEIAQAAAA==.Aaubree:BAAANQADCgIIAgAAAA==.',
Ab='Ababymage:BAAANQAECgcIDwAAAA==.Abbiocco:BAAANQAECgIIAgAAAA==.Abbotsmurfh:BAEANQAECgMIBAAAAA==.',
Ac='Acareseandra:BAAANQAECgUIDQAAAA==.Achkdragon:BAABNQAECoEdAAIBAAkJjhVrCACNAgABAAkJjhVrCACNAgAAAA==.',
Ad='Adelyne:BAAANQAECgEIAwAAAA==.Adeshu:BAAANQADCgQIBAAAAA==.Adhd:BAAANQAECgQIBgAAAA==.Adorele:BAAANQAECgIIAgABNQAECggIHgACAP4eAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQADCggICAAAAA==.',
Ai='Aibohphobia:BAAANQADCgIIAgAAAA==.',
Al='Alakazamn:BAAANQAECgQIEgAAAA==.Albalupus:BAAANQADCgQIBwAAAA==.Albirt:BAAANQABCgQIAwAAAA==.Aldoraeinna:BAAANQADCgUICQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBwADAAAAAA==.Alexyus:BAAANQADCggIDAAAAA==.Aliski:BAAANQADCgUICAABNQADCggIFgADAAAAAA==.Alodso:BAAANQADCgYIBgAAAA==.Aloys:BAAANQADCggIGAAAAA==.Alpharetta:BAAANQAECgQIBAAAAA==.',
Am='Amavessa:BAAANQADCgcIFwAAAA==.Amorous:BAAANQAECgQIBwAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Andromedus:BAAANQAECgMIBAAAAA==.Aneedaheals:BAAANQAECgEIAgAAAA==.Animositea:BAAANQAECgEIAQAAAA==.Anyasil:BAAANQAECgUICgAAAA==.',
Ap='Apostle:BAAANQAECgUIBgAAAA==.',
Ar='Arboribus:BAAANQADCgUIBgAAAA==.Archdogepie:BAAANQAECgEIAgAAAA==.Arcédd:BAAANQADCgMIAwAAAA==.Arrianassa:BAAANQAECgIIAgAAAA==.Arrietty:BAAANQADCgYIBgAAAA==.Arrowniri:BAAANQAECgQICwAAAA==.Artogand:BAAANQADCgcIDQAAAA==.Aruho:BAAANQAECgEIAgAAAA==.Arvad:BAAANQAECgUICgAAAA==.',
As='Ascalon:BAAANQAECggIEgAAAA==.Asclepión:BAAANQAECgcIDwAAAA==.Asteria:BAAANQADCgcIDgAAAA==.',
At='Athania:BAAANQAECgQIBAAAAA==.Atoli:BAAANQAECgcIEAAAAA==.',
Av='Avannir:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.Averlandra:BAABNQAECoEeAAMCAAgJ/h70BwDRAgACAAgJ7x30BwDRAgAEAAcJLhvuDwAvAgAAAA==.Avrora:BAAANQADCggICgABNQAECgEIAQADAAAAAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAABNQAFFIEOAAMBAAUJECRrAAAWAgABAAUJECRrAAAWAgAFAAEJoBpsAwBjAAAAAA==.Azbrodeus:BAAANQADCgYICAAAAA==.Azstastic:BAAANQAECgYICAAAAA==.',
Ba='Bacondad:BAAANQADCgcIFgAAAA==.Bandit:BAAANQADCggICgAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAAANQAECgcIEQAAAA==.',
Be='Bearicades:BAAANQAECgEIAQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCgYIBwAAAA==.Beg:BAAANQADCgMIAwABNQAECgQIBwADAAAAAA==.Bejeweled:BAAANQAECgQIBgAAAA==.Bellatrixt:BAABNQAECoEYAAIGAAkJFSBWDgAHAwAGAAkJFSBWDgAHAwAAAA==.Bellilia:BAAANQADCgcIGgAAAA==.Belvard:BAAANQADCgUIBQABNQAECgQICQADAAAAAA==.Berkinoff:BAAANQAECgUICQAAAA==.Besty:BAAANQAECgcIDwAAAA==.',
Bh='Bharmir:BAAANQAECgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgQICAAAAA==.Bigdemon:BAAANQAECgYIDAAAAA==.Bighardshock:BAAANQAECgMIAwAAAA==.Bigshrimp:BAAANQAECgUICgAAAA==.Bigstoot:BAAANQAECgIIAgAAAA==.Bilong:BAAANQADCgYIEAAAAA==.',
Bl='Blazingdh:BAAANQADCgIIAgAAAA==.Bleddyn:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQADCgYICQAAAA==.Blesslock:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQAECgQIBAABNQAECgUIBQADAAAAAA==.Bluebean:BAAANQAECgYIDAAAAA==.Bluelili:BAAANQADCgUIBgAAAA==.Bluemeenie:BAAANQAECgUICAAAAA==.Bluish:BAAANQAECgUIBQAAAA==.Bluntknucks:BAAANQABCgQIBgAAAA==.',
Bo='Bobsmage:BAAANQADCgYIBgAAAA==.Bonybolt:BAAANQABCgIIAgAAAA==.Bool:BAAANQADCgIIBAABNQAECgIIAgADAAAAAA==.Booti:BAAANQAECgYICgAAAA==.Borz:BAAANQAECgEIAgAAAA==.Boxspring:BAAANQAECggICwAAAA==.',
Br='Brays:BAAANQAECgMIBQAAAA==.Brbtacos:BAAANQAECgcIDAAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Breezeblöcks:BAAANQADCgYIBgAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAAANQAECgUICwAAAA==.Brndo:BAAANQAECgEIAgAAAA==.Brogoth:BAAANQAECgQIBwAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brunoxp:BAAANQAECgcIDwAAAA==.',
Bu='Bumblebee:BAAANQADCgEIAQAAAA==.Bunbop:BAAANQAECgYICAAAAA==.Burgoth:BAAANQADCgIIAgAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
['Bè']='Bèndèr:BAEANQABCgEIAQABNQABCgQIBAADAAAAAA==.',
Ca='Cabss:BAAANQAECgIIAwAAAA==.Caelum:BAAANQADCggIGAAAAA==.Calaban:BAAANQAECgUIBwAAAA==.Caldìr:BAAANQADCgYIBQAAAA==.Callazia:BAAANQAECgEIAQAAAA==.Callvar:BAAANQADCggICAAAAA==.Calvandersen:BAAANQADCgQIBAAAAA==.Calyssena:BAAANQAECgMIBQAAAA==.Camalyn:BAAANQABCgEIAQAAAA==.Candies:BAAANQAECgUICAAAAA==.Carrot:BAAANQAECgQICQAAAA==.Casaundra:BAEANQADCgYIBgABNQADCgcIBwADAAAAAA==.Cashmir:BAAANQAECgUICwAAAA==.Castalerus:BAAANQADCggIEAAAAA==.Casterlady:BAAANQADCgEIAQAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgUICQAAAA==.Catsmurga:BAABNQAECoEhAAIHAAkJGhr+JgCtAgAHAAkJGhr+JgCtAgAAAA==.',
Cc='Ccogs:BAAANQABCgQIBAABNQABCgQIBQADAAAAAA==.',
Ce='Celibate:BAAANQAECgYIEAAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Cello:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.Celticfrost:BAAANQAECgUICgAAAA==.',
Ch='Chaewon:BAAANQADCgYICAAAAA==.Chasèd:BAAANQADCgIIAgAAAA==.Chuddette:BAAANQAECgMICQAAAA==.Chumashu:BAAANQAECgYICAABNQAECgkJIgAIAN4kAA==.',
Ci='Circlinsmoth:BAAANQABCgMIAwAAAA==.Cirmorte:BAAANQADCgYIBgAAAA==.Ciroza:BAAANQAECgIIAgAAAA==.',
Co='Cogsworthh:BAAANQABCgQIBQAAAA==.Corpserunner:BAAANQAECgQICQAAAA==.',
Cr='Creekstone:BAAANQAECgQIBwAAAA==.Cristty:BAAANQADCggIDwAAAA==.Crowul:BAAANQADCgMIAwAAAA==.Crystallyn:BAAANQAECgUICgAAAA==.',
Cu='Cubanmage:BAAANQAECgEIAQABNQAECgUICgADAAAAAA==.Cutter:BAAANQADCgUIBQAAAA==.',
Cy='Cybelliar:BAAANQAECgUIBQAAAA==.Cynders:BAAANQAECgQICAAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBQABNQABCgQIBQADAAAAAA==.',
Da='Dabalt:BAAANQAECgMIAwABNQAECgUIBQADAAAAAA==.Dadamaxx:BAAANQAECgMIBQAAAA==.Daemlon:BAAANQAECgQIBQAAAA==.Daniel:BAAANQADCgEIAQAAAA==.Darbane:BAAANQAECgMIBAAAAA==.Dargonsevzer:BAAANQAECgcIDAAAAA==.Darkbeárd:BAAANQAECgYIBgAAAA==.Daspen:BAABNQAECoEiAAIJAAgJ8B6iAgD5AgAJAAgJ8B6iAgD5AgAAAA==.Daysalt:BAAANQAECggICAAAAA==.Daßalt:BAAANQAECgUIBQAAAA==.',
De='Deadlyangel:BAAANQABCgQICgAAAA==.Deadshotdak:BAAANQADCgQIBwABNQAECgUICgADAAAAAA==.Deathbychaos:BAAANQADCgUIBgAAAA==.Deathcrip:BAAANQADCgUIBQAAAA==.Delonge:BAAANQAECgcICgAAAA==.Delriel:BAAANQAECgEIAQAAAA==.Demeters:BAAANQADCgUIBQAAAA==.Demetra:BAAANQABCgIIAgAAAA==.Demonfuryx:BAAANQADCgYIBgAAAA==.Demonkeeper:BAAANQADCgYICAAAAA==.Denaror:BAAANQADCgEIAQAAAA==.Denzai:BAAANQAECgYICAAAAA==.Deshyr:BAAANQAECgQICAAAAA==.Despere:BAAANQABCgEIAQAAAA==.Deviant:BAABNQAECoEZAAMCAAkJNCNHCwCOAgACAAcJiR5HCwCOAgAEAAcJch7qDQBPAgAAAA==.Devvy:BAAANQAECgQIBAAAAA==.Dewzero:BAAANQADCgcIBwAAAA==.Deyalanis:BAAANQADCggICAAAAA==.',
Dh='Dha:BAAANQAECgYICwAAAA==.',
Di='Diablìta:BAAANQADCggIDQAAAA==.Dingaling:BAAANQADCggIEwAAAA==.Dirt:BAAANQAECgcIEQAAAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dj='Djdeath:BAAANQADCgUICAABNQAECggIDgADAAAAAA==.',
Dk='Dkdiddy:BAAANQAECgQIDAAAAA==.',
Do='Docnathrius:BAAANQAECgIIAgAAAA==.Dogodeath:BAAANQADCggIFgAAAA==.Domago:BAAANQAECgYIDgAAAA==.Dorknight:BAAANQAECgMIBQAAAA==.Dotfeardot:BAAANQAECgEIAgAAAA==.Dotsandfear:BAAANQABCgQIBAAAAA==.Dougue:BAABNQAECoEaAAMEAAkJMh2NBQAAAwAEAAkJvhyNBQAAAwACAAIJvgQnQABqAAAAAA==.',
Dp='Dpalm:BAAANQAECgYIEAAAAA==.',
Dr='Dracogelly:BAAANQAECgEIAQAAAA==.Draedio:BAAANQAECgIIAgAAAA==.Dragonarc:BAAANQABCgUICAAAAA==.Dragonnuts:BAAANQAECgUICQAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drazelle:BAAANQABCgIIAgAAAA==.Drdeathtron:BAAANQAECgMIAwAAAA==.Drenare:BAAANQADCgEIAQABNQAECgkJGwAHADAmAA==.Drevix:BAAANQAECgQICQAAAA==.Drneil:BAAANQADCgMIAwAAAA==.Dromanicus:BAAANQADCggICAAAAA==.Drovodian:BAAANQADCggIEwAAAA==.Dru:BAAANQAECgUICgAAAA==.Druidzilla:BAAANQABCgUIBQABNQADCgcIEwADAAAAAA==.',
Du='Dudaelah:BAAANQADCgYIBgAAAA==.Dudeak:BAAANQAECgUIBQAAAA==.Dulled:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Dundoh:BAABNQAECoEXAAIKAAgJ4R3DHgCvAgAKAAgJ4R3DHgCvAgAAAA==.Durm:BAAANQAECgMIBQAAAA==.Duskknight:BAAANQAECgUICAAAAA==.',
Ea='Earthlight:BAAANQADCgYICwAAAA==.',
Eb='Ebonchillz:BAAANQADCgYICQAAAA==.',
Ed='Edmundo:BAAANQADCggIBAAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eleeza:BAAANQAECgUICgAAAA==.Ellephino:BAAANQADCgcIDQABNQAECgIIAgADAAAAAA==.Elleìgh:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.Ellidiir:BAAANQADCgcIBwAAAA==.Elm:BAAANQAECgEIAQAAAA==.Elmzoth:BAACNQAFFIEGAAILAAMJciQ8AwBOAQALAAMJciQ8AwBOAQA1AAQKgTAAAwsACQlxJiEAAAkEAAsACQlxJiEAAAkEAAwAAQkUJu97AG8AAAE1AAQKAQgBAAMAAAAA.Elmzy:BAAANQADCggICAABNQAECgEIAQADAAAAAA==.Elvanshalee:BAAANQAECgQICQAAAA==.Elylreith:BAAANQADCgYICAAAAA==.Elysiain:BAAANQADCggIDgAAAA==.',
Em='Eminjangidge:BAAANQAECgQIBAAAAA==.',
En='Envoshat:BAAANQADCgcIDAAAAA==.',
Er='Erael:BAAANQADCggICAAAAA==.Erebseth:BAAANQADCgQIBgAAAA==.Eredeath:BAAANQAECgUICwAAAA==.Eremier:BAAANQAECgEIAQAAAA==.',
Es='Esdeäth:BAABNQAECoEXAAMNAAgJEx8PEQDXAgANAAgJEx8PEQDXAgAOAAIJlQ1VSABwAAAAAA==.Estar:BAAANQAECgMIAwAAAA==.Estaslól:BAAANQAECgYIDwAAAA==.Estelars:BAAANQADCgUIBQAAAA==.Esxcanor:BAAANQADCggICAABNQAECgcIDQADAAAAAA==.',
Et='Etel:BAAANQADCgcIBwAAAA==.Etrnlrapture:BAAANQAECgQICAAAAA==.',
Eu='Eulerion:BAAANQAECgUICQAAAA==.Eulkick:BAAANQADCgUIBQABNQAECgUICQADAAAAAA==.',
Ev='Evol:BAAANQAECgUICQAAAA==.Evolooshon:BAAANQADCgIIAgAAAA==.Evrac:BAAANQAECgUICQAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQAECgQIBAAAAA==.Faerysti:BAAANQADCggIDwAAAA==.Fafnir:BAAANQAECgQIBgABNQAECgkJHQAPAJciAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQAECgEIAQAAAA==.',
Fe='Fearinshatt:BAAANQADCgUIBQAAAA==.Fellina:BAAANQADCgUIAwAAAA==.Femaelan:BAEANQADCgcIBwAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQABCgQIBAABNQAECgIIAwADAAAAAA==.',
Fh='Fhalen:BAAANQAECgUICAAAAA==.',
Fi='Fimbik:BAAANQAECgIIAgAAAA==.Fischtya:BAAANQADCgMIAwAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQABCgIIAgADAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Foot:BAAANQADCgYIDAABNQAECgQIBwADAAAAAA==.Forgotskillz:BAAANQAECgUICgAAAA==.Fortunatos:BAAANQADCgcIDQAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQAECgEIAQAAAA==.Friendship:BAAANQADCgIIAgABNQAECgUICQADAAAAAA==.Frstyfyre:BAAANQADCgYIDgAAAA==.',
Fu='Fullmonty:BAAANQADCgYIEgAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
['Få']='Fårnsworth:BAEANQABCgQIBAAAAA==.',
Ga='Galdrelyne:BAAANQAECgQIBQAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Ganks:BAAANQABCgYIDAAAAA==.Gaobot:BAAANQADCgcIDwAAAA==.Garalagon:BAEANQADCgQIBAABNQADCgcIBwADAAAAAA==.Garros:BAAANQABCgEIAQAAAA==.',
Gb='Gb:BAAANQAECgcICQABNQAECgcIDQADAAAAAA==.',
Gd='Gdi:BAAANQAECgEIAQAAAA==.',
Ge='Genetunica:BAAANQADCgUICAAAAA==.Genevieve:BAAANQAECgEIAQAAAA==.Gerallt:BAAANQAFFAEIAQAAAA==.Gerdian:BAAANQAECgUIBQAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQAECgQIBAAAAA==.',
Gi='Gigantór:BAAANQAECgUICwAAAA==.Giggtyman:BAAANQAECgIIBAAAAA==.Gille:BAAANQAECgUICwAAAA==.',
Go='Goldendrae:BAAANQAECgQICAAAAA==.Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAAANQAECgUICwABNQAECgYIDAADAAAAAA==.Greekie:BAAANQAECgEIAQAAAA==.Grotir:BAAANQADCggIDQAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAAANQAECgUICgAAAA==.',
['Gò']='Gòóse:BAAANQAECgQIBwAAAA==.',
Ha='Halogens:BAAANQADCgcICQAAAA==.Handmemychi:BAAANQAECgUICAABNQAECgcIEQADAAAAAA==.Handmemygun:BAAANQAECgcIEQAAAA==.Hanzdormu:BAABNQAECoEeAAMQAAkJVh89AwBMAwAQAAkJVh89AwBMAwABAAQJNA9GHADfAAAAAA==.Hanzumbra:BAAANQADCggICAABNQAECgkJHgAQAFYfAA==.Hanzybadger:BAAANQAECgEIAQABNQAECgkJHgAQAFYfAA==.Harbofdeath:BAAANQAECgEIAQAAAA==.Hawktuahh:BAAANQADCgcIDQAAAA==.',
He='Healteamsix:BAAANQADCgYIBgAAAA==.Helioz:BAAANQAECgEIAQAAAA==.Hemogøblin:BAAANQAECgQIBAAAAA==.Hessn:BAABNQAECoEWAAMRAAkJvBH7JADzAQARAAgJFhP7JADzAQASAAEJ8ga4jQAgAAAAAA==.',
Hi='Hixz:BAAANQADCgcIBwABNQAECgIIAwADAAAAAA==.',
Ho='Holypumper:BAAANQADCggIDgAAAA==.Holyrayne:BAAANQAECgYIBgAAAA==.',
Hu='Huntardis:BAAANQAECgQIBgAAAA==.Huntterc:BAAANQAECgEIAQAAAA==.',
Hy='Hyasept:BAAANQAECgEIAQAAAA==.Hydraulic:BAAANQAECgQIBAAAAA==.',
Ia='Ialôr:BAAANQAECgUICgAAAA==.',
Ib='Ibz:BAAANQAECggICAAAAA==.',
Id='Idus:BAAANQADCgUIBgAAAA==.',
Il='Ilectos:BAAANQABCggICwAAAA==.',
Im='Impishlee:BAAANQAECgEIAQAAAA==.Impowitz:BAAANQADCggIFgAAAA==.',
In='Incestion:BAAANQADCgUIBQAAAA==.',
Ir='Iradeorum:BAAANQAECgQICQAAAA==.Irishfelocks:BAAANQAECgIIAgAAAA==.',
Is='Isadel:BAAANQADCgcICwAAAA==.Isavedu:BAAANQAECgUIDAAAAA==.',
It='Itherael:BAAANQAECgEIAQAAAA==.Ithlord:BAAANQAECgEIAQAAAA==.',
Iv='Ivanbear:BAAANQADCgQIBgAAAA==.Ivannacream:BAAANQADCggICAABNQAECgYIEAADAAAAAA==.Ivansting:BAAANQAECgMIAwAAAA==.Ivanthas:BAAANQADCgcICAAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQAECgEIAQAAAA==.Jahzzy:BAAANQAECgUICgABNQABCgQIBAADAAAAAA==.Jaiyanaa:BAAANQAECgUICwAAAA==.Jaquita:BAAANQAECgMIBQAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Jc='Jcliff:BAAANQADCgMIAwAAAA==.',
Je='Jeffglodblum:BAAANQADCgcIDQAAAA==.Jeluljingo:BAAANQAECgUIBgABNQADCggIDgADAAAAAA==.Jezilla:BAAANQAECgEIAgAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinsu:BAAANQADCgcIEQAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAUIDgABABAkAA==.Jollyreaper:BAAANQAECgQIBQAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Julauri:BAAANQADCgIIAgAAAA==.Juñior:BAABNQAECoEdAAIPAAkJlyL3BABeAwAPAAkJlyL3BABeAwAAAA==.',
Ka='Kaelashe:BAAANQAECgQIBQAAAA==.Kaelyndrace:BAAANQAECgUICwAAAA==.Kaeredan:BAAANQADCggIDwAAAA==.Kahuno:BAAANQAECgcIEwAAAA==.Kalimyst:BAAANQAECgUICgAAAA==.Kalutak:BAAANQAECgYIDgAAAA==.Kamisen:BAAANQADCggIFAAAAA==.Kappaccino:BAAANQAECgEIAQABNQAECgkJIgAIAN4kAA==.Karaktzn:BAAANQAECgEIAQAAAA==.Karande:BAAANQADCgYIBgAAAA==.Karedon:BAAANQADCgMIBAAAAA==.Kasstrah:BAAANQADCgYICAAAAA==.Kataraz:BAAANQADCgUIBwAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Keenforge:BAAANQAECgcICwABNQADCgUIBQADAAAAAA==.Keknein:BAAANQAECgQIBAAAAA==.Kellindor:BAAANQADCggICAAAAA==.Kendrà:BAEANQADCgYIBgABNQADCgcIBwADAAAAAA==.Kentaris:BAAANQAECgUICgAAAA==.Keroleaf:BAAANQAECgQICAAAAA==.',
Kh='Khakkora:BAAANQADCgEIAQAAAA==.',
Ki='Kiergadran:BAAANQAECgUIBwAAAA==.Killimanjaro:BAAANQAECgUICwAAAA==.Kind:BAAANQABCgQIAwAAAA==.Kinoclaw:BAAANQAECggICgAAAA==.',
Kl='Klaelune:BAAANQAECgcICgAAAA==.',
Kn='Knaring:BAAANQAECgUICAAAAA==.Knocked:BAAANQADCgMIAwABNQAECgYIDwADAAAAAA==.Knockedw:BAAANQADCgYIBgABNQAECgYIDwADAAAAAA==.Knowthing:BAAANQAECgUICQAAAA==.',
Ko='Kohola:BAABNQAECoEgAAIGAAkJUCAZCQBDAwAGAAkJUCAZCQBDAwAAAA==.Kolar:BAAANQADCgYIBgAAAA==.Kolby:BAAANQADCgcIDgAAAA==.Koldar:BAAANQAECgMIBAAAAA==.Kookies:BAAANQADCgIIAgAAAA==.',
Kr='Krîmsön:BAAANQAECggICAAAAA==.',
Ku='Kudo:BAAANQAECgYIDAAAAA==.',
Kv='Kvr:BAAANQADCgQIBgABNQAECgIIAgADAAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgYICAAAAA==.Lanthal:BAAANQADCgcIBwAAAA==.Lararrek:BAAANQAECgQICQAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAAANQAECgcIDQAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Lea:BAAANQADCgQIBAAAAA==.Leadfoot:BAAANQAECgUICgAAAA==.Lejaa:BAAANQAECgEIAwAAAA==.Lersneaq:BAAANQADCgYIDQAAAA==.Lexidragon:BAAANQADCgYIEQABNQAECgUIBgADAAAAAA==.',
Li='Lidina:BAAANQAECgQIBAAAAA==.Lifebreak:BAAANQAECgIIAgAAAA==.Lifestream:BAAANQAECgMIAwAAAA==.Lightheels:BAAANQAECgUICAAAAA==.Lightmourne:BAABNQAECoEWAAITAAgJaRHrDgDeAQATAAgJaRHrDgDeAQAAAA==.Lilkitz:BAAANQADCgEIAQAAAA==.Liteforged:BAAANQADCgUIBgAAAA==.',
Lo='Lockgob:BAAANQADCggICAAAAA==.Lolohjeez:BAAANQADCgcIBwAAAA==.Lotionman:BAAANQAFFAIIAgAAAA==.Lougi:BAABNQAECoEaAAQUAAkJnBcWDACTAgAUAAkJnBcWDACTAgASAAYJdA1UPgBpAQARAAEJHA0ofABCAAAAAA==.Lougii:BAAANQAECgEIAQABNQAECgkJGgAUAJwXAA==.',
Lt='Ltcrisp:BAAANQAECgQIEAAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAABNQAECoEjAAMVAAgJaBCqEQAFAgAVAAgJaBCqEQAFAgAWAAYJWBRrMgCUAQAAAA==.Lup:BAAANQADCgYICgAAAA==.',
Ly='Lynaya:BAAANQADCggICAAAAA==.Lysted:BAAANQAECgcIEgAAAA==.Lytherella:BAAANQAECgMIBQAAAA==.',
['Lô']='Lônghorn:BAAANQAECgcIEQAAAA==.',
Ma='Magecyalien:BAAANQADCggIGAAAAA==.Mahat:BAAANQAECgUIBgAAAA==.Mahona:BAAANQAECgcIEAAAAA==.Maideejai:BAAANQADCgUIBQAAAA==.Malichai:BAAANQADCgYIBgAAAA==.Manado:BAAANQADCgcIDgAAAA==.Manapuddin:BAAANQADCgYIBgABNQAECgUICAADAAAAAA==.Marcaine:BAAANQAECgIIAgAAAA==.Margareth:BAAANQAECgUICQAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.Mavverick:BAAANQADCgYIDAAAAA==.Mavverickk:BAAANQADCgYICgAAAA==.Maxime:BAAANQAECgMIAwAAAA==.Mayo:BAAANQAECgUICwAAAA==.',
Mc='Mcdruid:BAAANQAECgEIAQAAAA==.',
Me='Mechamos:BAAANQADCgQIBAAAAA==.Medenut:BAAANQAECgEIAgAAAA==.Mellarr:BAAANQAECgEIAQAAAA==.Menalial:BAAANQADCgYIBgAAAA==.Mergos:BAAANQAECgIIAgAAAA==.',
Mi='Mid:BAAANQAECgYICwAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQAECgEIAQAAAA==.Miori:BAAANQAECgEIAQAAAA==.Mirac:BAAANQAECgYICwAAAA==.Missti:BAAANQADCgcIBwAAAA==.Mistletow:BAAANQABCgIIAgAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQAECgEIAQAAAA==.',
Mo='Mogorasil:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.Monkichi:BAAANQAECgMIBQAAAA==.Mono:BAAANQAECgUIBwAAAA==.Moopsy:BAAANQADCggIEwAAAA==.Morganella:BAAANQADCgYICwAAAA==.Morghan:BAAANQAECgUICwAAAA==.Morgrul:BAAANQABCgYICgAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAAANQAECgUICAAAAA==.Muravath:BAAANQABCgQIBAAAAA==.Musicjam:BAAANQADCgQIBAAAAA==.',
Na='Nadaht:BAAANQADCgYIBgAAAA==.Nahjii:BAAANQADCgMIAwAAAA==.Nahteew:BAAANQADCggIDgAAAA==.Naomì:BAAANQADCgUIBwABNQAECgcIDQADAAAAAA==.Naruto:BAAANQADCgUIBQAAAA==.Nazurash:BAAANQAECgYICwAAAA==.',
Ne='Necros:BAAANQADCgYICgAAAA==.Nekgahza:BAAANQADCgIIAgAAAA==.Nelyar:BAAANQAECgUICwAAAA==.Neonepie:BAAANQAECgUIBgAAAA==.Neostardust:BAAANQADCgYIBgAAAA==.Nermith:BAAANQADCgUIBQAAAA==.Nettero:BAAANQAECgcIEAAAAA==.',
Ni='Nickolasrage:BAAANQAECgQIBAAAAA==.Nightfalls:BAAANQADCgMIAwAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nirazenezar:BAAANQADCgYIBgAAAA==.Nisgaa:BAAANQAECgYIDAAAAA==.',
No='Nockedup:BAAANQAECggICAAAAA==.Noots:BAAANQADCgUIBQAAAA==.Norro:BAEBNQAECoEaAAMXAAkJfB3JCQDwAgAXAAkJfB3JCQDwAgAGAAEJDQvCyAA+AAAAAA==.Norrow:BAEBNQAECoEgAAIXAAkJlx2LCgDjAgAXAAkJlx2LCgDjAgABNQAECgkJGgAXAHwdAA==.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAAANQAECgQICQAAAA==.',
Ny='Nymeris:BAAANQAECgQICQAAAA==.Nyritha:BAAANQAECgQIBwAAAA==.Nyxanunit:BAAANQAECgQICQAAAA==.',
Og='Oggi:BAAANQAECgEIAQAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQADCgUICgAAAA==.',
Om='Omau:BAAANQAECgQICQAAAA==.Omgheroism:BAAANQADCggICQAAAA==.Omìnous:BAAANQAECgcICwAAAA==.',
On='Oneinall:BAAANQAECgcIDQAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Or='Oriyn:BAAANQADCggIEwABNQAECgUICwADAAAAAA==.Orkar:BAAANQADCgIIAgAAAA==.',
Ov='Overknight:BAAANQAECgQIBgAAAA==.',
Oz='Ozempic:BAAANQAECgcIEAAAAA==.Ozknife:BAAANQAECgUICQABNQADCgIIAgADAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQAECgEIAQAAAA==.Padthai:BAAANQAECgUICAAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQADCgQIBQAAAA==.Papsfear:BAAANQADCgYIDQAAAA==.Paryejah:BAAANQADCgMIAwAAAA==.',
Pe='Pease:BAAANQAECgYIBgAAAA==.Peke:BAAANQADCgEIAQAAAA==.Penetrate:BAAANQAECgcIEQAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECggIDgADAAAAAA==.Phoenix:BAAANQAECgQIBAAAAA==.',
Pi='Piped:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.',
Pl='Pluka:BAAANQAECgEIAQAAAA==.',
Pn='Pnub:BAAANQAECgYICgAAAA==.',
Po='Poet:BAAANQADCgUIBQABNQAECgcICgADAAAAAA==.Polarbear:BAAANQAECgEIAgAAAA==.Pomato:BAAANQADCggIGAAAAA==.',
Pr='Praxitelis:BAAANQADCgcICAAAAA==.Priorsmurfh:BAEANQADCgcIEQABNQAECgMIBAADAAAAAA==.Promithia:BAAANQAECgUICwAAAA==.Propaladin:BAAANQADCgYICAAAAA==.Proticia:BAAANQADCgMIAwABNQAECgQICQADAAAAAA==.',
Ps='Psychopull:BAAANQADCgUIBQAAAA==.Psydesho:BAAANQADCgIIBAAAAA==.',
Py='Pyriz:BAAANQADCggIFgAAAA==.',
['Pë']='Pëëk:BAAANQAECgEIAgAAAA==.',
Qu='Quiverx:BAAANQAECgUICgAAAA==.',
Ra='Rachelmariet:BAAANQAECgQICQAAAA==.Radiumnight:BAAANQADCggIDgAAAA==.Raeghar:BAAANQAECgcIEAAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Raihua:BAAANQADCgQIBAAAAA==.Rammpart:BAAANQAECgEIAgAAAA==.Rapak:BAAANQADCggIDwAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rattleballs:BAAANQAECgUICwAAAA==.Ravpt:BAEANQAECgQIBwABNQAECgkJGgACAE4eAA==.Ravvs:BAEBNQAECoEaAAMCAAkJTh5BBAAwAwACAAkJTh5BBAAwAwAYAAIJxxJwDwCRAAAAAA==.',
Re='Refnar:BAAANQAECgYICwAAAA==.Reifle:BAAANQADCgQIBAAAAA==.Rekonsider:BAABNQAECoEgAAIHAAkJNR/WGgD2AgAHAAkJNR/WGgD2AgAAAA==.Remielle:BAAANQAECgQIBQAAAA==.Renewingfist:BAAANQADCggIDgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAAANQAECgQICAAAAA==.',
Rf='Rff:BAAANQADCgUIBQABNQAECgkJGwAHADAmAA==.',
Rh='Rhadamanthus:BAAANQAECgUICgAAAA==.',
Ri='Rikora:BAAANQAECgMIBgAAAA==.Ring:BAAANQADCggIDwAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAABNQAECoEaAAIZAAkJ+B5MCwBAAwAZAAkJ+B5MCwBAAwAAAA==.Ronnster:BAAANQAECggIDgAAAA==.Rooj:BAAANQAECgUIBQAAAA==.Roojdk:BAAANQAECgQIBAAAAA==.Roojvm:BAAANQAECgUICwAAAA==.Roojvr:BAAANQAECgEIAgAAAA==.Rootevil:BAAANQADCgMIAwAAAA==.Rorkhan:BAAANQABCgYIBwAAAA==.Royalet:BAAANQAECgUICgAAAA==.',
Ru='Rubbyy:BAAANQAECgMIAwAAAA==.Rukie:BAAANQADCgIIAgAAAA==.Runk:BAAANQADCgUIBgAAAA==.Ruthlee:BAAANQAECgcIEgAAAA==.',
Ry='Ryenwithane:BAAANQAECgcIEgABNQAFFAMIBgAaAB4jAA==.Rynella:BAAANQADCggIFQAAAA==.Ryzix:BAAANQADCggICAAAAA==.',
['Ró']='Róscô:BAAANQAECgIIAgAAAA==.',
Sa='Saimedin:BAAANQAECgQIBgAAAA==.Salin:BAAANQAECgUICQAAAA==.Salome:BAAANQAECgcIEwAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYICgAAAA==.Sapote:BAAANQADCggIDQAAAA==.Sasoo:BAAANQADCgMIAwAAAA==.Sastor:BAAANQAECgEIAgAAAA==.Sasuske:BAAANQADCgQICAAAAA==.Satheist:BAAANQAECgQIBQAAAA==.',
Sc='Scaredyet:BAAANQABCgMIAwAAAA==.Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Scute:BAAANQADCggICAAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQADCggIDAAAAA==.Seije:BAAANQABCgQIBAAAAA==.Seinduke:BAAANQAECgIIAwAAAA==.Seitan:BAAANQADCgEIAQAAAA==.Senael:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECgcICAAAAA==.Setierian:BAAANQADCgYIEgAAAA==.Seya:BAAANQABCgIIAgAAAA==.',
Sh='Shamearthen:BAAANQADCgUIBwAAAA==.Shamrexm:BAAANQADCggIDQAAAA==.Shanegillis:BAAANQAECgQICAAAAA==.Shashdrkiron:BAAANQAECgQIBgAAAA==.Sheer:BAAANQADCgIIAwAAAA==.Shenlong:BAAANQAECgEIAQAAAA==.Shidae:BAAANQAECgYIBgAAAA==.Shidaestraza:BAAANQADCgcIDgAAAA==.Shintorg:BAAANQAECgUICgAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgQICAAAAA==.Shocksi:BAAANQAECgUICwAAAA==.Shrimpkin:BAAANQAECgQIBAAAAA==.Shàdðw:BAAANQAECgYIBwAAAA==.',
Si='Sidon:BAAANQABCgEIAQAAAA==.Sienna:BAAANQAECgMIBgAAAA==.Sigmardoom:BAABNQAECoEbAAIbAAkJ9iNaAACuAwAbAAkJ9iNaAACuAwAAAA==.Sinabunch:BAAANQADCgYIBgAAAA==.Sini:BAAANQAECgIIAwAAAA==.Sivat:BAAANQAECggIEQAAAA==.',
Sk='Skyfel:BAAANQAECgQIBwAAAQ==.',
Sl='Slampiece:BAAANQAFFAIIAgAAAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slymuffin:BAAANQAECgMIBAAAAA==.',
Sm='Smanzerra:BAAANQAECggICAAAAA==.Smerig:BAAANQADCgIIAwAAAA==.Smúrph:BAAANQAECgQICAAAAA==.',
Sn='Snaptime:BAAANQAECgUICQAAAA==.Snowoman:BAAANQADCgEIAQAAAA==.',
So='Softgrl:BAAANQAECgYIEAAAAA==.Solarcorona:BAAANQAECgQIBAAAAA==.Solenne:BAAANQAECgYIDAAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQADCgYIDwABNQAECgYICwADAAAAAA==.Soulhacker:BAAANQAECggIAgAAAA==.Sovereignt:BAAANQAECgUIBQAAAA==.',
Sp='Sparechange:BAAANQAECgIIAgAAAA==.Spinachio:BAAANQAECgQIBQAAAA==.Spiro:BAAANQAECgUICQAAAA==.Spártacus:BAAANQAECgMIBAAAAA==.',
Ss='Ssargeras:BAAANQABCgYICAAAAA==.',
St='Stalkér:BAAANQAECgcIEQAAAA==.Steeltemplar:BAAANQAECgcIEQAAAA==.Stefanee:BAAANQAECgUICwAAAA==.Stisti:BAAANQAECgUICgAAAA==.Stoneclaw:BAAANQADCgYIDAAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.Stown:BAAANQADCgEIAQAAAA==.Styxdraco:BAAANQADCgUIBgAAAA==.',
Su='Succiboi:BAAANQAECgUICQAAAA==.Sugarplum:BAAANQADCgMIAwAAAA==.Sugastank:BAAANQADCgYICAAAAA==.Sugreeva:BAAANQAECgQICQAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Supplement:BAAANQAECggICwAAAA==.Surtain:BAAANQAECgIIAgABNQAECgkJGgAHAJUkAA==.Sustained:BAAANQAECgIIAgABNQAECgkJGgAHAJUkAA==.Susts:BAABNQAECoEaAAIHAAkJlST0BwCRAwAHAAkJlST0BwCRAwAAAA==.',
Sw='Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQAECgQIBAAAAA==.',
Sy='Synari:BAAANQAECgUIBgAAAA==.Sync:BAAANQAECgQICAAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAAANQAECgcIEgAAAA==.Taggis:BAAANQAECgcIEwAAAA==.Talalana:BAAANQADCgYIBgAAAA==.Tallwar:BAAANQAECgUICwAAAA==.Tansero:BAABNQAECoEeAAIQAAkJYBx6CAC/AgAQAAkJYBx6CAC/AgAAAA==.Tarklyn:BAAANQAECgIIAgAAAA==.Tarotina:BAAANQADCggICAAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Telriel:BAAANQAECgEIAQAAAA==.Terrabrew:BAAANQAECgUICQAAAA==.Teseban:BAAANQADCgYICwAAAA==.',
Th='Thaeron:BAABNQAECoEWAAIPAAgJ/RzwDgCeAgAPAAgJ/RzwDgCeAgAAAA==.Thakar:BAAANQAECgUICQAAAA==.Thedizz:BAAANQABCgQIBAAAAA==.Thelana:BAAANQABCgIIAgAAAA==.Themayo:BAAANQAECgQIBgABNQAECgQICAADAAAAAA==.Theonidus:BAAANQAECggIBQAAAA==.Thragrom:BAAANQAECgYIDgAAAA==.Threedayvic:BAAANQAECgIIBAAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.Thîïcc:BAAANQAECgQIBAABNQAECgUIDAADAAAAAA==.',
Ti='Tickl:BAAANQADCgYIFAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQAECgIIAwAAAA==.Tiktokthot:BAAANQAECgQIBgAAAA==.Tilila:BAAANQADCgQIBAAAAA==.Timojen:BAAANQADCgcIDwAAAA==.',
To='Toastman:BAAANQADCgUIBQAAAA==.Toetummy:BAAANQADCggIDAAAAA==.Tokkz:BAAANQADCgUIDwAAAA==.Tonysparks:BAAANQADCggIDAAAAA==.Toracina:BAAANQAECgMIAwAAAA==.Totalshocker:BAAANQADCgMIAwAAAA==.Tougyu:BAAANQAECgUICQAAAA==.',
Tr='Trakyr:BAAANQAECgIIAgAAAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQADCgcIEgAAAA==.Troodon:BAAANQAECgEIAQAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCgcICAAAAA==.Tríke:BAAANQADCgYIDgAAAA==.Trùk:BAAANQADCgYIBgAAAA==.',
Tu='Tulurakuq:BAAANQAECgEIAQAAAA==.Tuurok:BAAANQADCgcIFAAAAA==.',
Tw='Twelvepak:BAAANQADCgMIAwAAAA==.',
Un='Uncledigem:BAAANQABCgMIAwABNQADCgcIEwADAAAAAA==.Unstable:BAAANQAECgMIBgAAAA==.',
Ur='Urnirus:BAAANQAECgMIBQAAAA==.',
Uv='Uvvu:BAAANQAECgYIBgAAAA==.',
Va='Vampnor:BAAANQAECgQIDAAAAA==.Vanhelzing:BAAANQADCgcIDQAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQAECgQIBAAAAA==.Varinna:BAAANQADCgUIBQAAAA==.Varlaeus:BAAANQAECgYIDgAAAA==.Varlais:BAAANQAECgUICwABNQAECgYIDgADAAAAAA==.',
Ve='Veachkidd:BAAANQAECgQIBAAAAA==.Veledora:BAAANQAECgQICAAAAA==.Velidnissara:BAAANQAECgQIBwAAAA==.Velkoz:BAAANQAECgEIBAAAAA==.Vellean:BAAANQADCggICAAAAA==.Velsa:BAAANQAECgQIBAAAAA==.Venat:BAAANQAECgMIBAAAAA==.Vensa:BAAANQADCgQIBAAAAA==.Vex:BAAANQAECgMIAwAAAA==.',
Vi='Vissaia:BAAANQAECgUIDgAAAA==.',
Vo='Volacious:BAAANQADCgQIBwAAAA==.Voodou:BAAANQADCgYIBgAAAA==.Vordo:BAAANQADCgYIDAAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEIAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Warlockkink:BAAANQADCgQIBAAAAA==.Washlunk:BAAANQAECgEIAgAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAABNQAECoEdAAMcAAkJJh1ACwAPAwAcAAkJJh1ACwAPAwAZAAMJUQeKkQCSAAAAAA==.Waxyness:BAAANQADCgMIAwAAAA==.',
Wh='Wharph:BAAANQAECgQIBwAAAA==.Whitedahlia:BAAANQADCggIEwAAAA==.Whitepyre:BAAANQAECggIDgABNQAFFAUIDgABABAkAA==.Wholadin:BAAANQAECgMIAwAAAA==.Whome:BAAANQADCgUIBgAAAA==.',
Wi='Wilmarth:BAAANQAECgUIBwAAAA==.Winchèster:BAAANQAECgQICQABNQAECgQIEAADAAAAAA==.Windbreaker:BAAANQADCgMIAwAAAA==.',
Wo='Wollmane:BAAANQADCggIDAABNQAECgMIAwADAAAAAA==.Wongo:BAAANQADCggICAABNQAFFAcIEAAIAIAYAA==.Woodticks:BAAANQADCgYIDAAAAA==.',
Wr='Wråth:BAAANQAECgUIBwAAAA==.',
Xe='Xeleci:BAAANQAECgUICwAAAA==.',
Ya='Yamon:BAAANQAECgMIBQAAAA==.Yamsees:BAAANQAECgIIAgAAAA==.Yardsnack:BAAANQADCgQIBgAAAA==.Yashipha:BAAANQADCgIIAgAAAA==.',
Yb='Ybnxdolo:BAAANQADCgcIEwAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Ye='Yevven:BAAANQADCgYICwAAAA==.',
Yu='Yulmegerth:BAAANQADCgYIEgAAAA==.Yummieyum:BAAANQADCggICgAAAA==.Yurthong:BAAANQAECgQIBAAAAA==.',
Za='Zairy:BAAANQADCggICAABNQAECggICAADAAAAAA==.Zart:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
Ze='Zedrolor:BAABNQAECoEZAAIbAAkJ2CGIAACEAwAbAAkJ2CGIAACEAwAAAA==.Zekar:BAAANQAECgEIAQAAAA==.Zenful:BAAANQADCgMIAwAAAA==.Zenithcia:BAABNQAECoEWAAIRAAcJcxOBKgDLAQARAAcJcxOBKgDLAQAAAA==.Zeoma:BAAANQADCgcIDwAAAA==.Zerafìn:BAAANQAECgUIDgAAAA==.Zerenitynow:BAAANQAECgUICwAAAA==.Zereora:BAAANQADCgIIAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEIAgAAAA==.',
Zi='Zilyn:BAABNQAECoEdAAIcAAkJzg5RLAAPAgAcAAkJzg5RLAAPAgAAAA==.',
Zo='Zookeeper:BAAANQADCgUIBwAAAA==.',
Zr='Zraidn:BAAANQAECgMIBQAAAA==.Zromaverick:BAAANQADCgEIAQAAAA==.',
['Àr']='Àrthäs:BAAANQABCgEIAQAAAA==.',
['Ëx']='Ëxcel:BAAANQADCgEIAQAAAA==.',
['Ðu']='Ðungeon:BAAANQADCggICQAAAA==.',
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
