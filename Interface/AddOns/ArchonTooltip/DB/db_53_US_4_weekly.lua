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

local lookup = {'Mage-Arcane','Evoker-Devastation','Rogue-Assassination','Unknown-Unknown','Warrior-Arms','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Shaman-Restoration','Hunter-BeastMastery','Druid-Balance','DeathKnight-Unholy','Monk-Windwalker','Druid-Feral','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Paladin-Retribution','Priest-Holy','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Blood','Hunter-Marksmanship','Evoker-Preservation','DemonHunter-Vengeance','Paladin-Protection','Warlock-Affliction','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Shaman-Elemental','Monk-Brewmaster','Warrior-Fury','Paladin-Holy','Mage-Frost',}
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aabc:BAAANQADCgQIBAAAAA==.Aaubree:BAAANQADCgIIAgAAAA==.',
Ab='Ababymage:BAABNQAECoEXAAIBAAgKhQ5xiwD6AQABAAgKhQ5xiwD6AQAAAA==.Abbiocco:BAAANQAECgIIBAAAAA==.Abbotsmurfh:BAEANQAECgUJCQAAAA==.',
Ac='Acareseandra:BAAANQAECgUIEgAAAA==.Achkdragon:BAABNQAECoEfAAICAAkKjBXuCgB1AgACAAkKjBXuCgB1AgAAAA==.',
Ad='Adelyne:BAAANQAECgEJAwAAAA==.Adeshu:BAAANQAECgEJAQAAAA==.Adhd:BAAANQAECgYJDAAAAA==.Adorele:BAAANQAECgIIAgABNQAECgkJKAADALsgAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQAECgQIBAAAAA==.',
Ai='Aibohphobia:BAAANQAECgIJAgAAAA==.',
Al='Alakazamn:BAAANQAECgQIEgAAAA==.Albalupus:BAAANQADCgQIBwAAAA==.Albirt:BAAANQABCgcJCAAAAA==.Aldoraeinna:BAAANQADCgUJCQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBwAEAAAAAA==.Alexyus:BAAANQADCggIDAAAAA==.Aliski:BAAANQADCgUICAABNQADCggJHgAEAAAAAA==.Alodso:BAAANQADCgYIBgAAAA==.Aloys:BAAANQAECgMIAwAAAA==.Alpharetta:BAAANQAECgQICAAAAA==.',
Am='Amavessa:BAAANQAECgEIAQAAAA==.Amorous:BAAANQAECgQICgAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Anankee:BAAANQABCgEJAwAAAA==.Andromedus:BAAANQAECgUICQAAAA==.Aneedaheals:BAAANQAECgEJAwAAAA==.Animositea:BAAANQAECgEIAQABNQAECgUIBgAEAAAAAA==.Anyasil:BAAANQAECgcJEQAAAA==.',
Ap='Apostle:BAAANQAECgUJBwAAAA==.',
Ar='Arboribus:BAAANQADCgUIBgAAAA==.Archdogepie:BAAANQAECgEIAgAAAA==.Arcédd:BAAANQADCgMIAwAAAA==.Arrianassa:BAAANQAECgQJBgAAAA==.Arrietty:BAAANQADCgYIBgAAAA==.Arrowniri:BAAANQAECgYIEQAAAA==.Arrowtide:BAAANQAECgQIBQAAAA==.Artogand:BAAANQADCgcIFAAAAA==.Aruho:BAAANQAECgUIBwAAAA==.Arvad:BAAANQAECgYIEAAAAA==.',
As='Ascalon:BAABNQAECoEbAAIFAAkKdhN+QABlAgAFAAkKdhN+QABlAgAAAA==.Asclepión:BAABNQAECoEbAAIGAAkKjAxNFgALAgAGAAkKjAxNFgALAgAAAA==.Asteria:BAAANQADCgcIFQAAAA==.',
At='Athania:BAAANQAECgUJCQAAAA==.Atoli:BAABNQAECoEYAAIHAAgKfgkjKwCaAQAHAAgKfgkjKwCaAQAAAA==.',
Av='Avannir:BAAANQAECgEIAQABNQAECgQICQAEAAAAAA==.Averlandra:BAABNQAECoEoAAMDAAkKuyC1AwBmAwADAAkKuyC1AwBmAwAIAAcKLht8EwAXAgAAAA==.Avrora:BAAANQADCggICgABNQAECggIDQAEAAAAAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAABNQAFFIETAAMCAAUKESaXAAA1AgACAAUKESaXAAA1AgAJAAEKoBoSBQBdAAAAAA==.Azbrodeus:BAAANQADCgYJDgAAAA==.Azstastic:BAAANQAECgcJDwAAAA==.',
Ba='Bacondad:BAAANQADCgcIFgAAAA==.Bandit:BAAANQADCggJCgAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAABNQAECoEbAAIKAAgKbA/ITAC1AQAKAAgKbA/ITAC1AQAAAA==.',
Be='Bearicades:BAAANQAECgEJAQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCggJCQABNQAECgMJAwAEAAAAAA==.Beg:BAAANQADCgMIAwABNQAECgUIDAAEAAAAAA==.Bejeweled:BAAANQAECgQICgAAAA==.Bellatrixt:BAABNQAECoEaAAILAAkKFSDYGADlAgALAAkKFSDYGADlAgAAAA==.Bellilia:BAAANQAECgEIAQAAAA==.Belvard:BAAANQADCgUIBQABNQAECgQICQAEAAAAAA==.Berkinoff:BAAANQAECgYJDwAAAA==.Besty:BAABNQAECoEbAAIMAAgKzxOwKQAaAgAMAAgKzxOwKQAaAgAAAA==.',
Bh='Bharmir:BAAANQAECgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgQICAAAAA==.Bigdemon:BAAANQAECgcIDwAAAA==.Bighardshock:BAAANQAECgMIBAAAAA==.Bigshrimp:BAAANQAECgYIEAAAAA==.Bigstoot:BAAANQAECgIIAwAAAA==.Bilong:BAAANQADCgYIEAAAAA==.',
Bl='Blazingdh:BAAANQADCgIIAgAAAA==.Bleddyn:BAAANQADCgMIAwABNQAECgMIAwAEAAAAAA==.Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQADCgYICQAAAA==.Blesslock:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQAECgQIBQABNQAECgUJBQAEAAAAAA==.Blizzdawg:BAAANQADCgQIBAAAAA==.Bluebean:BAAANQAECgcIEwAAAA==.Bluelili:BAAANQADCgUIBgAAAA==.Bluemeenie:BAAANQAECgYIDgAAAA==.Bluish:BAAANQAECgUJBQAAAA==.Bluntknucks:BAAANQABCgQIBwAAAA==.',
Bo='Bobsmage:BAAANQADCgYIBgAAAA==.Bonybolt:BAAANQABCgIIAgAAAA==.Bool:BAAANQADCgIIBAABNQAECgIIAwAEAAAAAA==.Booti:BAAANQAECgYJEAAAAA==.Borz:BAAANQAECgUIBwAAAA==.Bottleabeer:BAAANQADCgMIAwAAAA==.Boxspring:BAAANQAECggICwAAAA==.',
Br='Brays:BAAANQAECgMIBQAAAA==.Brbtacos:BAAANQAECgcIEQAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Breezeblöcks:BAAANQADCgYIBgAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAAANQAECgUJEAAAAA==.Brndo:BAAANQAECgUIBwAAAA==.Brogoth:BAAANQAECgQICgAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brukah:BAAANQABCgEIAQAAAA==.Brunoxp:BAABNQAECoEdAAINAAkKRBdZFwCwAgANAAkKRBdZFwCwAgAAAA==.',
Bu='Bubblebun:BAAANQAFFAIIAgAAAA==.Bumblebee:BAAANQADCgEJAQAAAA==.Burgoth:BAAANQADCgUIBwAAAA==.Burndo:BAAANQAECgIIAgABNQAECgUIBwAEAAAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
['Bè']='Bèndèr:BAEANQABCgEIAQABNQABCgQIBAAEAAAAAA==.',
Ca='Cabss:BAAANQAECgUICAAAAA==.Caelum:BAAANQAECgMIAwAAAA==.Calaban:BAAANQAECgUICwAAAA==.Caldìr:BAAANQAECgMIBAAAAA==.Callazia:BAAANQAECgUIBgAAAA==.Callvar:BAAANQADCggJCAAAAA==.Calvandersen:BAAANQADCgQIBAAAAA==.Calyssena:BAAANQAECgUJCgAAAA==.Camalyn:BAAANQABCgEIAgAAAA==.Candies:BAAANQAECggJDAAAAA==.Canthea:BAAANQAECgMIAwAAAA==.Carrot:BAAANQAECgYIDwAAAA==.Casaundra:BAEANQADCgcIDQABNQADCgcIDQAEAAAAAA==.Cashmir:BAAANQAECgYJEQAAAA==.Castalerus:BAAANQADCggJGAAAAA==.Casterlady:BAAANQADCgEIAQAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgUJDgAAAA==.Catsmurga:BAABNQAECoEnAAIFAAkKGhvvMgCdAgAFAAkKGhvvMgCdAgAAAA==.',
Cc='Ccogs:BAAANQABCgQIBAABNQABCgQIBgAEAAAAAA==.',
Ce='Celibate:BAABNQAECoEVAAIFAAYKDhXQfgCMAQAFAAYKDhXQfgCMAQAAAA==.Cellasril:BAAANQADCgUJBQAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Cello:BAAANQAECgEJAgABNQAECgMIAwAEAAAAAA==.Celticfrost:BAAANQAECgYIEAAAAA==.',
Ch='Chaewon:BAAANQADCgYJDgAAAA==.Chasèd:BAAANQAECgEIAQAAAA==.Chuddette:BAAANQAECgMICQAAAA==.Chumashu:BAAANQAFFAEIAQABNQAECgkJJQAOAN4kAA==.',
Ci='Circlinsmoth:BAAANQABCgMIAwAAAA==.Cirmorte:BAAANQADCgYIBgAAAA==.Ciroza:BAAANQAECgIJBAAAAA==.',
Co='Cogsworthh:BAAANQABCgQIBgAAAA==.Corpserunner:BAAANQAECgYJDwAAAA==.',
Cr='Crazytrain:BAAANQAECgIIAQAAAA==.Creekstone:BAAANQAECgQIBwAAAA==.Creep:BAAANQADCgMIAwAAAA==.Cristty:BAAANQADCggIDwAAAA==.Crowul:BAAANQADCgMIAwAAAA==.Crystallyn:BAAANQAECgYIEAAAAA==.',
Cu='Cubanmage:BAAANQAECggIBwAAAA==.Cutter:BAAANQADCgUJBQAAAA==.',
Cy='Cybelis:BAAANQADCgYJBgAAAA==.Cybelliar:BAAANQAECgYJCwAAAA==.Cynders:BAAANQAECgUJDQAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBgABNQABCgQIBgAEAAAAAA==.',
Da='Dabalt:BAAANQAECgMIAwABNQAECgUIBgAEAAAAAA==.Dadamaxx:BAAANQAECgUJCgAAAA==.Daemlon:BAAANQAECgQICAAAAA==.Daniel:BAAANQAECgIJAgAAAA==.Darbane:BAAANQAECgMIBAAAAA==.Dargonsevzer:BAAANQAECgcJEgAAAA==.Darkbeárd:BAAANQAECgYJDAAAAA==.Daspen:BAABNQAECoEyAAIPAAkKoCI2AQCWAwAPAAkKoCI2AQCWAwAAAA==.Daysalt:BAAANQAECggJCQAAAA==.Daßalt:BAAANQAECgUIBgAAAA==.',
De='Deadshotdak:BAAANQADCgQJBwABNQAECgYIEAAEAAAAAA==.Deathbychaos:BAAANQADCgUIBgAAAA==.Deathcrip:BAAANQADCgUIBQABNQAECgkJHgALAM8iAA==.Delonge:BAAANQAFFAEIAQAAAA==.Delorand:BAAANQABCggJCAAAAA==.Delriel:BAAANQAECgUIBgAAAA==.Demeters:BAAANQADCgUIBQAAAA==.Demetra:BAAANQABCgIIAwAAAA==.Demonfuryx:BAAANQADCgcIDQAAAA==.Demonkeeper:BAAANQADCgYJDgAAAA==.Denaror:BAAANQADCgMJAwAAAA==.Denzai:BAAANQAECgcIDwAAAA==.Deshyr:BAAANQAECgQICAAAAA==.Despere:BAAANQABCgEIAQAAAA==.Deviant:BAABNQAECoEcAAMDAAkKlCPIEQB3AgADAAcKiR7IEQB3AgAIAAcK7R5sDwBRAgAAAA==.Devvy:BAAANQAECgQIBAAAAA==.Dewzero:BAAANQADCggICAAAAA==.Deyalanis:BAAANQADCggICAAAAA==.',
Dh='Dha:BAAANQAECgcIEAAAAA==.',
Di='Diablìta:BAAANQADCggIDQAAAA==.Dingaling:BAAANQADCggJEwAAAA==.Dirt:BAABNQAECoEcAAIMAAkKtxqmFADcAgAMAAkKtxqmFADcAgAAAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dj='Djdeath:BAAANQADCgUICAABNQAECggJEAAEAAAAAA==.',
Dk='Dkdiddy:BAAANQAECgYIDgAAAA==.',
Do='Dochudson:BAAANQABCgEIAQAAAA==.Docnathrius:BAAANQAECgMIBQAAAA==.Dogodeath:BAAANQAECgEJAQAAAA==.Domago:BAABNQAECoEZAAIQAAkKsRURKgB5AgAQAAkKsRURKgB5AgAAAA==.Dorknight:BAAANQAECgUJCgAAAA==.Dotfeardot:BAAANQAECgIIAwAAAA==.Dotsandfear:BAAANQABCgcIBwAAAA==.Dougue:BAABNQAECoEeAAMIAAkKtB0dBgACAwAIAAkKQB0dBgACAwADAAIKvgRyVQBkAAAAAA==.',
Dp='Dpalm:BAABNQAECoEbAAMRAAgKaR9IDADfAgARAAgKaR9IDADfAgASAAEKDw+NGgA8AAAAAA==.',
Dr='Dracogelly:BAAANQAECgMJAwAAAA==.Draedia:BAAANQADCgEJAQAAAA==.Draedio:BAAANQAECgIIAgAAAA==.Dragonarc:BAAANQABCgUICAAAAA==.Dragonnuts:BAAANQAECgUIDgAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drazelle:BAAANQABCgIIAwAAAA==.Drdeathtron:BAAANQAECgMIAwAAAA==.Drenare:BAAANQADCgEJAQABNQAECgkJIwAFAIomAA==.Drevix:BAAANQAECgYJDwAAAA==.Drinkabeer:BAAANQADCgUIBQAAAA==.Drneil:BAAANQADCgMIAwAAAA==.Dromanicus:BAAANQADCggJCAAAAA==.Drovodian:BAAANQAECgIIAgAAAA==.Dru:BAAANQAECgYIEAAAAA==.Druidzilla:BAAANQABCgUIBQABNQADCgcIEwAEAAAAAA==.',
Du='Dudaelah:BAAANQADCgYICwAAAA==.Dudeak:BAAANQAECgYJCwAAAA==.Dulled:BAAANQADCgIIAgABNQAECgIJAwAEAAAAAA==.Dundoh:BAABNQAECoEeAAITAAkK9x5GGwAHAwATAAkK9x5GGwAHAwAAAA==.Durm:BAAANQAECgUJCgAAAA==.Duskknight:BAAANQAECgYJDgAAAA==.',
Ea='Earthivan:BAAANQADCgUJBQAAAA==.Earthlight:BAAANQADCgYICwAAAA==.',
Eb='Ebonchillz:BAAANQADCgYICQAAAA==.',
Ed='Edmundo:BAAANQADCggJBAAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eleeza:BAAANQAECgYIEAAAAA==.Ellephino:BAAANQADCgcIDQABNQAECgIIBAAEAAAAAA==.Elleìgh:BAAANQAECgQIBQABNQAECggIHQAUAPYTAA==.Ellidiir:BAAANQADCgcIDgAAAA==.Elm:BAAANQAECggIDQAAAA==.Elmzoth:BAACNQAFFIELAAIRAAUKhyNrAQARAgARAAUKhyNrAQARAgA1AAQKgU8AAxEACQq0JhIAABEEABEACQq0JhIAABEEABQAAQoUJqyaAG4AAAE1AAQKCAgNAAQAAAAA.Elmzy:BAAANQADCggICAABNQAECggIDQAEAAAAAA==.Elvanshalee:BAAANQAECgQICQAAAA==.Elylreith:BAAANQADCgYICAAAAA==.Elysiain:BAAANQAECgEIAQAAAA==.',
Em='Eminjangidge:BAAANQAECgQIBAAAAA==.',
En='Enthusiast:BAAANQADCgcIBwAAAA==.Envoshat:BAAANQADCgcJEwAAAA==.',
Er='Erael:BAAANQADCggJDAAAAA==.Erebseth:BAAANQAECgIJAgAAAA==.Eredeath:BAAANQAECgUIEAAAAA==.Eremier:BAAANQAECgEIAQAAAA==.',
Es='Esdeäth:BAABNQAECoEaAAMQAAgKLR+rHQC3AgAQAAgKLR+rHQC3AgAVAAIKlQ3ATwBsAAAAAA==.Estar:BAAANQAECgUICAAAAA==.Estaslól:BAABNQAECoEcAAIKAAgK6xmNHwCXAgAKAAgK6xmNHwCXAgAAAA==.Estelars:BAAANQADCgUIBQAAAA==.Esxcanor:BAAANQADCggICAABNQAECgcJEwAEAAAAAA==.',
Et='Etel:BAAANQAECgIIAgAAAA==.Etrnlrapture:BAAANQAECgYIDgAAAA==.',
Eu='Eulerion:BAAANQAECgcJEAAAAA==.Eulkick:BAAANQAECgEJAQABNQAECgcJEAAEAAAAAA==.Eunomia:BAAANQADCgQIBAAAAA==.',
Ev='Evol:BAAANQAECgYJDwAAAA==.Evolooshon:BAAANQADCgIIAgAAAA==.Evrac:BAAANQAECgUIDgAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQAECgUICQAAAA==.Faerysti:BAAANQAECgQIBAAAAA==.Fafnir:BAAANQAECgQIBwABNQAECgkJJwAWAOojAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQAECgEIAgAAAA==.',
Fe='Fearinshatt:BAAANQADCgYJBgAAAA==.Fellina:BAAANQADCgUIAwAAAA==.Femaelan:BAEANQADCgcIBwABNQADCgcIDQAEAAAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQAECgMJAwAAAA==.',
Fh='Fhalen:BAAANQAECgYJDgAAAA==.',
Fi='Fimbik:BAAANQAECgYIBwAAAA==.Fischtya:BAAANQADCgMJAwAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQABCgIJAgAEAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Foot:BAAANQAECgEIAQABNQAECgUIDAAEAAAAAA==.Forgotskillz:BAAANQAECgUICgAAAA==.Fortunatos:BAAANQAECgIJAgAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQAECgEJAQAAAA==.Friendship:BAAANQADCgIIAgABNQAECgUIDgAEAAAAAA==.Frstyfyre:BAAANQADCgYIDgAAAA==.',
Fu='Fullmonty:BAAANQAECgEIAQAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
['Få']='Fårnsworth:BAEANQABCgQIBAAAAA==.',
Ga='Galdrelyne:BAAANQAECgUJBgAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Ganks:BAAANQABCgYIDgAAAA==.Gaobot:BAAANQADCgcIFQAAAA==.Garalagon:BAEANQADCgYJCAABNQADCgcIDQAEAAAAAA==.Garros:BAAANQABCgEIAQAAAA==.',
Gb='Gb:BAAANQAECgcICQABNQAECgcJFAARAEgdAA==.',
Gd='Gdi:BAAANQAECgIJAwAAAA==.',
Ge='Genetunica:BAAANQADCgUICAAAAA==.Genevieve:BAAANQAECgIIAwAAAA==.Gerallt:BAABNQAECoEUAAIXAAcK4xanLQD0AQAXAAcK4xanLQD0AQAAAA==.Gerdian:BAAANQAECgUICgAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQAECgYIBgAAAA==.',
Gi='Gigantór:BAAANQAECgUJEAAAAA==.Giggtyman:BAAANQAECgIJBAAAAA==.Gille:BAAANQAECgYJEQAAAA==.',
Go='Goldendrae:BAAANQAECgQICAAAAA==.Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAAANQAECgYJDAABNQAECgcJDgAEAAAAAA==.Greekie:BAAANQAECgYJBwAAAA==.Grotir:BAAANQADCggIDQAAAA==.Grotznik:BAAANQADCgYIBgAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAAANQAECgcIEQAAAA==.',
['Gò']='Gòóse:BAAANQAECgUIDAAAAA==.',
Ha='Handmemychi:BAAANQAECgYJDgABNQAECgkJGwALANIjAA==.Handmemygun:BAABNQAECoEbAAMLAAkK0iNiAwCxAwALAAkK0iNiAwCxAwAYAAEKJgxqYAAyAAAAAA==.Hanzdormu:BAABNQAECoEhAAMZAAkKoSBAAwBlAwAZAAkKoSBAAwBlAwACAAQKNA/ZIADXAAAAAA==.Hanzumbra:BAAANQADCggJCAABNQAECgkJIQAZAKEgAA==.Hanzybadger:BAAANQAECgEIAQABNQAECgkJIQAZAKEgAA==.Harbofdeath:BAAANQAECgQJCQAAAA==.Hawktuahh:BAAANQADCgcIDQAAAA==.',
He='Healteamsix:BAAANQADCgYIBgAAAA==.Healzarc:BAAANQADCgQJBAAAAA==.Helgaah:BAAANQADCgQJBAAAAA==.Helioz:BAAANQAECgEIAQAAAA==.Hemogøblin:BAAANQAECgQIBwAAAA==.Hessn:BAABNQAECoEeAAMXAAkKnxVJKAAXAgAXAAgKdRdJKAAXAgANAAEK8gYBogAeAAAAAA==.',
Hi='Hixz:BAAANQADCgcJBwABNQAECgQICAAEAAAAAA==.',
Ho='Holypumper:BAAANQADCggJDgAAAA==.Holyrayne:BAAANQAECgYJCgAAAA==.Hottieheals:BAAANQADCgEIAQAAAA==.',
Hu='Hubrinaku:BAAANQADCgcIBwAAAA==.Huntardis:BAAANQAECgQJCgAAAA==.Huntterc:BAAANQAECgEIAQAAAA==.',
Hy='Hyasept:BAAANQAECgQIBQAAAA==.Hydraulic:BAAANQAECgYJCgAAAA==.Hygar:BAAANQADCgMIAwAAAA==.',
Ia='Ialôr:BAAANQAECgYJDgAAAA==.',
Ib='Ibz:BAAANQAECggJDgAAAA==.',
Ic='Ichedin:BAAANQADCgUJBQAAAA==.',
Id='Idus:BAAANQADCgUIBgAAAA==.',
Il='Ilectos:BAAANQABCggICwAAAA==.',
Im='Impishlee:BAAANQAECgIJAgAAAA==.Impmommy:BAAANQAECgIIAgAAAA==.Impowitz:BAAANQAECgEJAQAAAA==.',
In='Incestion:BAAANQADCgYJCwAAAA==.',
Ir='Iradeorum:BAAANQAECgYJDwAAAA==.Irishfelocks:BAAANQAECgUIBQAAAA==.',
Is='Isadel:BAAANQADCgcIEgAAAA==.Isavedu:BAAANQAECgYJEgAAAA==.',
It='Itherael:BAAANQAECgEIAQAAAA==.Ithlord:BAAANQAECgIJAwAAAA==.',
Iv='Ivanbear:BAAANQADCgUJCwAAAA==.Ivannacream:BAAANQADCggICAABNQAECgYIEAAEAAAAAA==.Ivansting:BAAANQAECgQJBQAAAA==.Ivanthas:BAAANQADCgcIDgAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQAECgEJAQAAAA==.Jahzzy:BAAANQAECgYICwABNQABCgQIBAAEAAAAAA==.Jaiyanaa:BAAANQAECgUIEAAAAA==.Jakem:BAAANQABCgIIAwAAAA==.Jaquita:BAAANQAECgUICgAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Jc='Jclif:BAAANQADCgMIAwAAAA==.Jcliff:BAAANQADCgMIAwAAAA==.',
Je='Jeffglodblum:BAAANQADCgcIDQAAAA==.Jellylicious:BAAANQADCgYJBgAAAA==.Jeluljingo:BAAANQAECgYIDAABNQADCggIDgAEAAAAAA==.Jezilla:BAAANQAECgUIBwAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinainala:BAAANQADCggJCQAAAA==.Jinsu:BAAANQADCgcIGAAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAUIEwACABEmAA==.Jollyreaper:BAAANQAECgQICQAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Judgernaut:BAAANQADCgQIBAAAAA==.Julauri:BAAANQADCgIJAgAAAA==.Junglejuice:BAAANQADCgcJCAAAAA==.Juñior:BAABNQAECoEnAAMWAAkK6iM5BQB0AwAWAAkK6iM5BQB0AwAaAAMKoB7cDwAIAQAAAA==.',
Ka='Kaelashe:BAAANQAECgUJBgAAAA==.Kaelyndrace:BAAANQAECgYJEQAAAA==.Kaeredan:BAAANQADCggIDwAAAA==.Kahuno:BAAANQAECgcIEwAAAA==.Kalimyst:BAAANQAECgYIEAAAAA==.Kalutak:BAABNQAECoEZAAIbAAgKNxqlDABYAgAbAAgKNxqlDABYAgAAAA==.Kamisen:BAAANQADCggIGwAAAA==.Kappaccino:BAAANQAECgEIAQABNQAECgkJJQAOAN4kAA==.Karaktzn:BAAANQAECgQIBQAAAA==.Karande:BAAANQADCgYIBgAAAA==.Karedon:BAAANQADCgMJBAAAAA==.Kasstrah:BAAANQADCgYICgAAAA==.Kataraz:BAAANQADCgYJDQAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Kea:BAAANQAECgEJAQABNQAECgMIAwAEAAAAAA==.Keenforge:BAABNQAECoEYAAMXAAkK8g5BOQCwAQAXAAkK8g5BOQCwAQAHAAEKzwSicQAtAAABNQADCgUIBQAEAAAAAA==.Keknein:BAAANQAECgUICQAAAA==.Kellindor:BAAANQADCggICAAAAA==.Kendrà:BAEANQADCgcIDQAAAA==.Kentaris:BAAANQAECgUJDwAAAA==.Keroleaf:BAAANQAECgYJDgAAAA==.',
Kh='Khakkora:BAAANQADCgEIAQABNQADCgIJAgAEAAAAAA==.',
Ki='Kiergadran:BAAANQAECgUICgAAAA==.Killimanjaro:BAAANQAECgUJEAAAAA==.Kind:BAAANQABCgQIAwAAAA==.Kinoclaw:BAAANQAFFAEIAQAAAA==.',
Kl='Klaelune:BAAANQAECggIEgAAAA==.',
Kn='Knaring:BAAANQAECgUICAAAAA==.Knocked:BAAANQADCgMIAwABNQAECgYIDwAEAAAAAA==.Knockedw:BAAANQADCgYIBgABNQAECgYIDwAEAAAAAA==.Knowthing:BAAANQAECgUIDgAAAA==.',
Ko='Kohola:BAABNQAECoEhAAILAAkKUCCTEQAWAwALAAkKUCCTEQAWAwAAAA==.Kolar:BAAANQADCgcIDQAAAA==.Kolby:BAAANQADCgcIDgAAAA==.Koldar:BAAANQAECgUJCQAAAA==.Kookies:BAAANQADCgYIBgAAAA==.',
Kr='Kronvoid:BAAANQADCggJCAAAAA==.Krîmsön:BAAANQAFFAEIAQAAAA==.',
Ku='Kudo:BAAANQAECgcIEwAAAA==.Kuroi:BAAANQADCgcIBwAAAA==.',
Kv='Kvr:BAAANQADCgQJBgABNQAECgIIAwAEAAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgYJDgAAAA==.Lanthal:BAAANQADCgcIBwAAAA==.Lararrek:BAAANQAECgYJDAAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAAANQAECgcJEwAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Leadfoot:BAAANQAECgYIEAAAAA==.Leftd:BAAANQADCgQIBAABNQAECggIHQAHAOoXAA==.Lejaa:BAAANQAECgEIAwAAAA==.Lersneaq:BAAANQADCgYIDQAAAA==.Lexidragon:BAAANQADCgYJEQABNQAECgUJCwAEAAAAAA==.',
Li='Lidina:BAAANQAECgQIBAAAAA==.Lifebreak:BAAANQAECgIIAgAAAA==.Lifestream:BAAANQAECgUJCAAAAA==.Ligeia:BAAANQAECgUIBQAAAA==.Lightbier:BAAANQAECgMJAwAAAA==.Lightheels:BAAANQAECgYJDgAAAA==.Lightmourne:BAABNQAECoEeAAIbAAgKqRitDABXAgAbAAgKqRitDABXAgAAAA==.Lilbeep:BAAANQADCgQIBAAAAA==.Lilkitz:BAAANQADCgEIAQAAAA==.Liteforged:BAAANQADCgUIBgAAAA==.',
Lo='Lockgob:BAAANQADCggICAAAAA==.Lolohjeez:BAAANQADCgcIBwAAAA==.Lotionman:BAABNQAECoEaAAILAAgKwSFOFgD1AgALAAgKwSFOFgD1AgAAAA==.Lougi:BAABNQAECoEdAAQHAAkKCBkIFAB8AgAHAAkKCBkIFAB8AgANAAYKdA3eSgBaAQAXAAEKHA2zkwA9AAAAAA==.Lougii:BAAANQAECgEIAQABNQAECgkJHQAHAAgZAA==.',
Lt='Ltcrisp:BAABNQAECoEWAAIcAAUKOBdnCQBiAQAcAAUKOBdnCQBiAQAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAABNQAECoEsAAMGAAkKwR+iAwBgAwAGAAkKwR+iAwBgAwAMAAYKWBQyPwB8AQAAAA==.Lup:BAAANQADCgYICgAAAA==.',
Ly='Lynaya:BAAANQADCggJCAAAAA==.Lysra:BAAANQADCgQJBAAAAA==.Lysted:BAABNQAECoEeAAMLAAkKIR1MFAACAwALAAkKIR1MFAACAwAYAAQKcw2yNgD1AAAAAA==.Lytherella:BAAANQAECgUJCgAAAA==.',
['Là']='Lànce:BAAANQADCgQJBAABNQAECgUIFgAcADgXAA==.',
['Lô']='Lônghorn:BAABNQAECoEbAAIdAAgKoSAmBADoAgAdAAgKoSAmBADoAgAAAA==.',
Ma='Magecyalien:BAAANQAECgIIAgAAAA==.Mahat:BAAANQAECgYJDAAAAA==.Mahona:BAAANQAECgcIEAAAAA==.Maideejai:BAAANQADCgUJBQAAAA==.Malichai:BAAANQADCgYIBgAAAA==.Manado:BAAANQADCgcJFQAAAA==.Manapuddin:BAAANQADCgYIBgABNQAECgYJDgAEAAAAAA==.Marcaine:BAAANQAECgIIAgAAAA==.Margareth:BAAANQAECgUICQAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUICQAEAAAAAA==.Mavverick:BAAANQADCgYIDwAAAA==.Mavverickk:BAAANQAECgEIAQAAAA==.Maxime:BAAANQAECgUJCAAAAA==.Mayo:BAAANQAECgYJEQAAAA==.',
Mc='Mcdruid:BAAANQAECgEIAgAAAA==.',
Md='Mdiggiddy:BAAANQAECgEIAQABNQAECgMJBgAEAAAAAA==.',
Me='Mechamos:BAAANQADCgQIBAAAAA==.Medenut:BAAANQAECgUIBwAAAA==.Mellarr:BAAANQAECgEIAQAAAA==.Menalial:BAAANQADCgYIBgAAAA==.Mergos:BAAANQAECgIIAgAAAA==.Mesmureyes:BAAANQADCgUIBQAAAA==.',
Mi='Mid:BAAANQAECgYICwAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQAECgEIAQAAAA==.Miori:BAAANQAECgIJAwAAAA==.Mirac:BAAANQAECgcJEwAAAA==.Missbless:BAAANQADCgYIBgAAAA==.Missti:BAAANQAECgEIAQAAAA==.Mistletow:BAAANQABCgIIBAAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQAECgEJAgAAAA==.Mizzit:BAAANQAECgIIAgAAAA==.',
Mo='Mogorasil:BAAANQAECgEIAQABNQAECgUJCAAEAAAAAA==.Monkichi:BAAANQAECgUICAAAAA==.Mono:BAAANQAECgUICwAAAA==.Moopsy:BAAANQAECgIIAgAAAA==.Morganella:BAAANQADCgYICwAAAA==.Morghan:BAAANQAECgUJEAAAAA==.Morgrul:BAAANQABCgYICgAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAAANQAECgUJDAAAAA==.Mulo:BAAANQADCgMIAwAAAA==.Muravath:BAAANQABCgQIBQAAAA==.Musicjam:BAAANQADCgUICAAAAA==.',
My='Mysp:BAAANQADCggICAABNQAECgIJAwAEAAAAAA==.',
Na='Nadaht:BAAANQADCgYIBgAAAA==.Nahjii:BAAANQADCgMIAwAAAA==.Nahteew:BAAANQAECgIIAgAAAA==.Naomì:BAAANQADCgYJDQAAAA==.Naruto:BAAANQADCgUIBQAAAA==.Nazurash:BAABNQAECoEUAAINAAcKNhMENgDMAQANAAcKNhMENgDMAQAAAA==.',
Ne='Necros:BAAANQADCgYICgAAAA==.Nekgahza:BAAANQADCggICAAAAA==.Nelyar:BAAANQAECgUJEAAAAA==.Neonepie:BAAANQAECgYJDAAAAA==.Neostardust:BAAANQADCgYIBgAAAA==.Nermith:BAAANQADCgUIBQAAAA==.Nettero:BAABNQAECoEbAAIFAAgKnBFKWwACAgAFAAgKnBFKWwACAgAAAA==.',
Ni='Nickolasrage:BAAANQAECgQJCAAAAA==.Nightfalls:BAAANQADCgMIAwAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nirazenezar:BAAANQADCgYIBgAAAA==.Nisgaa:BAAANQAECggIEwAAAA==.',
No='Nockedup:BAAANQAECggICAAAAA==.Noots:BAAANQADCgUIBQAAAA==.Noro:BAEANQAECgEIAQABNQAECgkJJQAYALgdAA==.Norro:BAEBNQAECoEhAAMYAAkKrB5OCgD+AgAYAAkKrB5OCgD+AgALAAEKDQvR8gA8AAABNQAECgkJJQAYALgdAA==.Norrow:BAEBNQAECoElAAIYAAkKuB2JDADcAgAYAAkKuB2JDADcAgAAAA==.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAAANQAECgYIDwAAAA==.',
Ny='Nymeris:BAAANQAECgYJDwAAAA==.Nyritha:BAAANQAECgQICwAAAA==.Nyxanunit:BAAANQAECgUJDgAAAA==.',
Og='Oggi:BAAANQAECgEIAQAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQAECgMIBAAAAA==.',
Om='Omau:BAAANQAECgYJDwAAAA==.Omgheroism:BAAANQADCggICQAAAA==.Omìnous:BAAANQAECgcIEAAAAA==.',
On='Oneinall:BAAANQAECggIEwAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Op='Oplaya:BAAANQADCgYJBgABNQAECggIGQANABkdAA==.',
Or='Oriyn:BAAANQADCggIEwABNQAECgUJEAAEAAAAAA==.Orkar:BAAANQADCgIJAgAAAA==.',
Ov='Overknight:BAAANQAECgQICwAAAA==.',
Oz='Ozempic:BAABNQAECoEYAAMCAAgKqAoqFgCKAQACAAcKSgsqFgCKAQAJAAEKOgZgGAAzAAAAAA==.Ozknife:BAAANQAECgUIDgABNQADCgIIAgAEAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQAECgEIAQAAAA==.Padthai:BAAANQAECgUIDwAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQADCgQIBQAAAA==.Papsfear:BAAANQADCgYIDQAAAA==.Paryejah:BAAANQADCgMIAwAAAA==.',
Pe='Pease:BAAANQAECgYJDAAAAA==.Peke:BAAANQADCgEIAQAAAA==.Penetrate:BAABNQAECoEbAAIeAAgKJB4tBQC2AgAeAAgKJB4tBQC2AgAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECggJEAAEAAAAAA==.Phoenix:BAAANQAECgUICQAAAA==.',
Pi='Piped:BAAANQADCgMIAwABNQAECgQJBgAEAAAAAA==.',
Pl='Pluka:BAAANQAECgUJBgAAAA==.',
Pn='Pnub:BAAANQAECgYJEAAAAA==.',
Po='Poet:BAAANQADCgUIBQABNQAFFAEIAQAEAAAAAA==.Polarbear:BAAANQAECgEIAgAAAA==.Pomato:BAAANQAECgIIAgAAAA==.Pookle:BAAANQADCgIJAgAAAA==.',
Pr='Praxitelis:BAAANQADCgcICAAAAA==.Priorsmurfh:BAEANQADCggIGQABNQAECgUJCQAEAAAAAA==.Promithia:BAAANQAECgYIDQAAAA==.Propaladin:BAAANQAECgEJAQAAAA==.Proticia:BAAANQADCgMIAwABNQAECgQICQAEAAAAAA==.',
Ps='Psychopull:BAAANQADCgUIBQAAAA==.Psydesho:BAAANQADCgUJBQAAAA==.',
Py='Pyriz:BAAANQADCggJHgAAAA==.Pyromedeis:BAAANQABCgEIAQAAAA==.',
['Pë']='Pëëk:BAAANQAECgUIBwAAAA==.',
Qu='Quiverx:BAAANQAECgYIEAABNQAECggIBwAEAAAAAA==.',
Ra='Rachelmariet:BAAANQAECgYJDwAAAA==.Radiumnight:BAAANQAECgMJAgAAAA==.Raeghar:BAAANQAECgcJEgAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Rageon:BAAANQADCgQIBAAAAA==.Raihua:BAAANQADCgQIBAAAAA==.Rammpart:BAAANQAECgUIBwAAAA==.Rapak:BAAANQADCggIDwAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rashnu:BAAANQAECggICAAAAA==.Rattleballs:BAAANQAECgUICwAAAA==.Ravpt:BAEANQAECgQIBwABNQAECgkJHAADAFEeAA==.Ravvs:BAEBNQAECoEcAAMDAAkKUR73BwALAwADAAkKUR73BwALAwAfAAIKvRKKEQCQAAAAAA==.',
Re='Rebuff:BAAANQABCgQJBAAAAA==.Refnar:BAAANQAFFAEIAQAAAA==.Reifle:BAAANQADCgQIBAAAAA==.Rekonsider:BAABNQAECoEiAAIFAAkK1x9JKQDJAgAFAAkK1x9JKQDJAgAAAA==.Remielle:BAAANQAECgUICgAAAA==.Renewingfist:BAAANQADCggIDgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAAANQAECgUIDQAAAA==.',
Rf='Rff:BAAANQADCgUJBQABNQAECgkJIwAFAIomAA==.',
Rh='Rhadamanthus:BAAANQAECgUICgAAAA==.',
Ri='Rikora:BAAANQAECgUJCwAAAA==.Ring:BAAANQADCggIFgAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAABNQAECoEiAAIgAAkK2yCaDABVAwAgAAkK2yCaDABVAwAAAA==.Ronnster:BAAANQAECggJEAAAAA==.Roogy:BAAANQADCggICAABNQAECgUJDAAEAAAAAA==.Rooj:BAAANQAECgcIDAAAAA==.Roojdk:BAAANQAECgQIBQAAAA==.Roojvm:BAAANQAECgUICwAAAA==.Roojvr:BAAANQAECgEIAgAAAA==.Rootevil:BAAANQADCgQIBAAAAA==.Rorkhan:BAAANQABCgYIBwAAAA==.Rovver:BAAANQABCgQIBAAAAA==.Royalet:BAAANQAECgYIEAAAAA==.',
Ru='Rubbyy:BAAANQAECgMIAwAAAA==.Rukie:BAAANQADCgIIAgAAAA==.Runk:BAAANQADCgUIBgAAAA==.Ruthlee:BAABNQAECoEdAAIMAAgKEiRvCwBEAwAMAAgKEiRvCwBEAwAAAA==.',
Ry='Ryenwithane:BAABNQAECoEZAAILAAkKNCRyBgCEAwALAAkKNCRyBgCEAwABNQAFFAUJCwAhAFghAA==.Rynella:BAAANQAECgIIAgAAAA==.Ryzix:BAAANQAECgUJBQAAAA==.',
['Rì']='Rìcco:BAAANQADCggIAQAAAA==.',
['Ró']='Róscô:BAAANQAECgIIAgAAAA==.',
Sa='Saarole:BAAANQADCggJCAAAAA==.Saimedin:BAAANQAECgQICgAAAA==.Salin:BAAANQAECgUJCwAAAA==.Salome:BAABNQAECoEdAAIUAAgK9hPROwD7AQAUAAgK9hPROwD7AQAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYICgAAAA==.Sapote:BAAANQADCggJDQAAAA==.Sasoo:BAAANQADCgMIAwAAAA==.Sastor:BAAANQAECgUIBwAAAA==.Sasuske:BAAANQADCgQICAAAAA==.Satheist:BAAANQAECgcIDAAAAA==.',
Sc='Scaredyet:BAAANQADCgYJBgAAAA==.Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQAECgIJAwAEAAAAAA==.Scute:BAAANQAECgMIAwAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQADCggIDAAAAA==.Seigressa:BAAANQADCgQIBAAAAA==.Seije:BAAANQABCgQIBAAAAA==.Seinduke:BAAANQAECgQICAAAAA==.Seitan:BAAANQADCgEIAQAAAA==.Senael:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECggJEAAAAA==.Setierian:BAAANQAECgEJAQAAAA==.Seya:BAAANQABCgIIAgAAAA==.',
Sh='Shadowpope:BAAANQABCgEIAQAAAA==.Shamearthen:BAAANQADCgUIBwAAAA==.Shamrexm:BAAANQADCggIDQAAAA==.Shanegillis:BAAANQAECgQIDAAAAA==.Shashdrkiron:BAAANQAECgQICgAAAA==.Sheer:BAAANQADCgIIAwAAAA==.Shenlong:BAAANQAECgUIBgAAAA==.Shidae:BAAANQAECgYJDAAAAA==.Shidaestraza:BAAANQADCgcIDgAAAA==.Shintorg:BAAANQAECgYIEAAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgQICQABNQAECgQJCgAEAAAAAA==.Shocksi:BAAANQAECgYIEQAAAA==.Shrimpkin:BAAANQAECgcICwAAAA==.Shrimprage:BAAANQADCgQJBAAAAA==.Shàdðw:BAAANQAECgYIBwAAAA==.',
Si='Sidon:BAAANQABCgEJAgAAAA==.Sienna:BAAANQAECgUICwAAAA==.Sigmardoom:BAABNQAECoEeAAIiAAkKMSSTAACiAwAiAAkKMSSTAACiAwAAAA==.Siluria:BAAANQABCgEIAQAAAA==.Sinabunch:BAAANQADCgYIBgAAAA==.Singion:BAAANQADCgYIBgAAAA==.Sini:BAAANQAECgMIBgAAAA==.Sivat:BAABNQAECoEbAAIMAAkKKBYuHQCHAgAMAAkKKBYuHQCHAgAAAA==.',
Sk='Skronq:BAAANQADCgUIBQAAAA==.Skyfel:BAAANQAECgUJDAAAAQ==.',
Sl='Slampiece:BAAANQAFFAMJAwAAAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slymuffin:BAAANQAECgMIBAAAAA==.',
Sm='Smanzerra:BAAANQAECggICwAAAA==.Smerig:BAAANQADCgIIAwAAAA==.Smúrph:BAAANQAECgQJCAAAAA==.',
Sn='Snafueight:BAAANQADCgQIBAAAAA==.Snafumage:BAAANQADCgEJAQAAAA==.Snaptime:BAAANQAECgYJDwAAAA==.Snikrmydodle:BAAANQADCggICAAAAA==.Snowoman:BAAANQADCgEIAQABNQAECggIAQAEAAAAAA==.Snowshamy:BAAANQAECggIAQAAAA==.',
So='Softgrl:BAAANQAECgYIEAAAAA==.Solarcorona:BAAANQAECgQJCAAAAA==.Solenne:BAAANQAECgcIEwAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQAECgQJBAABNQAECgcJDAAEAAAAAA==.Soulhacker:BAAANQAECggJAgAAAA==.Sovereignt:BAAANQAECgUIBQAAAA==.',
Sp='Spaghetti:BAAANQADCgMIAwABNQAFFAEIAQAEAAAAAA==.Sparechange:BAAANQAECgIIAwAAAA==.Spinachio:BAAANQAECgUICAAAAA==.Spiro:BAAANQAECgYJDwAAAA==.Spártacus:BAAANQAECgMJBAAAAA==.',
Ss='Ssargeras:BAAANQABCgYICAAAAA==.',
St='Stalkér:BAABNQAECoEaAAIWAAgKmx9eEADIAgAWAAgKmx9eEADIAgAAAA==.Steeltemplar:BAABNQAECoEbAAIjAAgKRhIkPwD5AQAjAAgKRhIkPwD5AQAAAA==.Stefanee:BAAANQAECgYJEQAAAA==.Stisti:BAAANQAECgYIEAAAAA==.Stoneclaw:BAAANQADCgYIDAAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwABNQAECgIIAwAEAAAAAA==.Stown:BAAANQADCgEIAQAAAA==.Styxdraco:BAAANQADCgUIBgAAAA==.',
Su='Succiboi:BAAANQAECgUIDgAAAA==.Sugarplum:BAAANQADCgMIAwAAAA==.Sugastank:BAAANQADCgYJDgAAAA==.Sugreeva:BAAANQAECgQICQAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Supplement:BAAANQAECggJEQAAAA==.Surtain:BAAANQAECgIIAgABNQAFFAUJBwAFAAsfAA==.Sustained:BAAANQAECgUIBwABNQAFFAUJBwAFAAsfAA==.Susts:BAACNQAFFIEHAAIFAAUKCx/xBADiAQAFAAUKCx/xBADiAQA1AAQKgR0AAwUACQrqJDcMAHgDAAUACQrqJDcMAHgDACIAAQqEIX8bAGQAAAAA.',
Sw='Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQAECgQICgAAAA==.',
Sy='Synari:BAAANQAECgUICgAAAA==.Sync:BAAANQAECgQICQAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAABNQAECoEcAAMFAAkK6SH4IwDkAgAFAAgKaSP4IwDkAgAeAAMKdRxQGQD8AAAAAA==.Taggis:BAABNQAECoEdAAMBAAkKUiDNUwCRAgABAAcK+R/NUwCRAgAkAAIKiSFDGQC5AAAAAA==.Talalana:BAAANQADCgYIBgAAAA==.Tallwar:BAAANQAECgUJEAAAAA==.Tansero:BAABNQAECoEnAAIZAAkKxR3ZBwD2AgAZAAkKxR3ZBwD2AgAAAA==.Tarklyn:BAAANQAECgQJBgAAAA==.Tarotina:BAAANQAECgEJAQAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQAECgUIBgAAAA==.Telriel:BAAANQAECgEJAQAAAA==.Terrabrew:BAAANQAECgUJDgAAAA==.Teseban:BAAANQADCgYICwAAAA==.',
Th='Thaeron:BAABNQAECoEeAAIWAAgK7BwtEwCmAgAWAAgK7BwtEwCmAgAAAA==.Thakar:BAAANQAECgUIDgAAAA==.Thedizz:BAAANQABCgQJBAAAAA==.Thelana:BAAANQABCgIIAgAAAA==.Themayo:BAAANQAECgQJCgAAAA==.Theonidus:BAAANQAECggICQAAAA==.Thragrom:BAABNQAECoEZAAMNAAgKGR2lFwCtAgANAAgKGR2lFwCtAgAHAAMKlAtzVACRAAAAAA==.Threedayvic:BAAANQAECgUICQAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.Thîïcc:BAAANQAECgQJCQABNQAECgUJDgAEAAAAAA==.',
Ti='Tickl:BAAANQADCgYIFAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQAECgUJCAAAAA==.Tiktokthot:BAAANQAECgUIBwAAAA==.Tilila:BAAANQADCgQIBAAAAA==.Timojen:BAAANQADCgcIDwAAAA==.',
To='Toastman:BAAANQADCgUIBQAAAA==.Toetummy:BAAANQADCggIDAAAAA==.Tokkz:BAAANQAFFAEJAQAAAA==.Tonysparks:BAAANQADCggIDAAAAA==.Toracina:BAAANQAECgQIBgAAAA==.Totalshocker:BAAANQADCgMIAwAAAA==.Tougyu:BAAANQAECgYJDwAAAA==.',
Tr='Trakyr:BAAANQAECgIJBAAAAA==.Treebean:BAAANQADCgcJDQABNQAECgcIEwAEAAAAAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQAECgEIAQAAAA==.Troodon:BAAANQAECgEIAQAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCgcIDwAAAA==.Tríke:BAAANQAECgEIAQAAAA==.Trùk:BAAANQADCgYIBgAAAA==.',
Tu='Tulurakuq:BAAANQAECgUJBgAAAA==.Tuurok:BAAANQAECgEIAQAAAA==.',
Tw='Twelvepak:BAAANQADCgMJAwAAAA==.',
Un='Uncledigem:BAAANQABCgMIAwABNQADCgcIEwAEAAAAAA==.Unstable:BAAANQAECgMJBgAAAA==.',
Ur='Urnirus:BAAANQAECgUJCgAAAA==.',
Uv='Uvvu:BAAANQAECgYIBgAAAA==.',
Va='Vampnor:BAAANQAECgYJEgAAAA==.Vanhelzing:BAAANQADCgcIFAAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQAECgQIBAAAAA==.Varinna:BAAANQADCgUIBQAAAA==.Varlaeus:BAABNQAECoEYAAIFAAgK/A0DaADWAQAFAAgK/A0DaADWAQAAAA==.Varlais:BAAANQAECgYJEQABNQAECggJGAAFAPwNAA==.',
Ve='Veachkidd:BAAANQAECgYJCgAAAA==.Veledora:BAAANQAECgUJDQAAAA==.Velidnissara:BAAANQAECgQIDQAAAA==.Velkoz:BAAANQAECgEIBAAAAA==.Vellean:BAAANQADCggJCAAAAA==.Velsa:BAAANQAECgUICQAAAA==.Venat:BAAANQAECgMIBAAAAA==.Vensa:BAAANQADCgQJBAAAAA==.Vex:BAAANQAECgMIAwAAAA==.',
Vi='Vissaia:BAABNQAECoEVAAMjAAcKYRpHMwAvAgAjAAcKYRpHMwAvAgATAAEKUwbaKwEuAAAAAA==.',
Vo='Volacious:BAAANQADCgUIDAAAAA==.Voodou:BAAANQADCgYIBgAAAA==.Vordo:BAAANQADCgYIDAAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEJAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Warlockkink:BAAANQADCggIDAAAAA==.Warre:BAAANQADCgYIBgAAAA==.Washlunk:BAAANQAECgUIBwAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAABNQAECoEfAAMKAAkKFh/ODQAbAwAKAAkKFh/ODQAbAwAgAAMKUQdosQCPAAAAAA==.Waxyness:BAAANQADCgMIAwAAAA==.',
Wh='Wharph:BAAANQAECgUIDAAAAA==.Whitedahlia:BAAANQAECgIIAgAAAA==.Whitepyre:BAAANQAECggJEAABNQAFFAUIEwACABEmAA==.Wholadin:BAAANQAECgQIBAAAAA==.Whome:BAAANQADCgUIBgAAAA==.',
Wi='Wilmarth:BAAANQAECgUIBwAAAA==.Winchèster:BAAANQAECgQICQABNQAECgUIFgAcADgXAA==.Windbreaker:BAAANQADCgMIAwAAAA==.',
Wo='Wolldays:BAAANQADCgcIBwABNQAECgQIBAAEAAAAAA==.Wollmane:BAAANQADCggIDAABNQAECgQIBAAEAAAAAA==.Wongo:BAAANQADCggICAABNQAFFAcIFQAOAJ4cAA==.Woodticks:BAAANQADCgcJEwAAAA==.Woolybugger:BAAANQAECgEJAQAAAA==.',
Wr='Wråth:BAAANQAECgYJDQAAAA==.',
Xa='Xalashock:BAAANQADCggJCAAAAA==.',
Xe='Xeleci:BAAANQAECgYJEQAAAA==.',
Ya='Yamon:BAAANQAECgUJCgAAAA==.Yamsees:BAAANQAECgQIBQAAAA==.Yangduke:BAAANQADCggICAABNQAECgQICAAEAAAAAA==.Yardsnack:BAAANQADCgQIBgAAAA==.Yashipha:BAAANQADCgIIAgAAAA==.',
Yb='Ybnxdolo:BAAANQADCgcIEwAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Ye='Yevven:BAAANQADCgYICwAAAA==.',
Yu='Yulmegerth:BAAANQADCgcJGQAAAA==.Yummieyum:BAAANQADCggICgAAAA==.Yurthong:BAAANQAECgQIBAAAAA==.',
Za='Zairy:BAAANQADCggICAABNQAECggJDgAEAAAAAA==.Zart:BAAANQAECgQJBgABNQAECgUICQAEAAAAAA==.',
Ze='Zedrolor:BAABNQAECoEiAAIiAAkK3iHoAAB4AwAiAAkK3iHoAAB4AwAAAA==.Zekar:BAAANQAECgMJBAAAAA==.Zenful:BAAANQADCgMJAwAAAA==.Zenithcia:BAABNQAECoEYAAIXAAcKdBP+OACxAQAXAAcKdBP+OACxAQAAAA==.Zeoma:BAAANQADCggJFwAAAA==.Zerafìn:BAABNQAECoEaAAIBAAgKuQ+JogDDAQABAAgKuQ+JogDDAQAAAA==.Zerenitynow:BAAANQAECgYJEQAAAA==.Zereora:BAAANQADCgIJAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEJAgAAAA==.',
Zi='Zilyn:BAABNQAECoElAAIKAAkKKxCnOgAGAgAKAAkKKxCnOgAGAgAAAA==.',
Zo='Zookeeper:BAAANQADCgUIBwAAAA==.',
Zr='Zraidn:BAAANQAECgUJCgAAAA==.Zromaverick:BAAANQADCgEIAQAAAA==.',
['Àr']='Àrthäs:BAAANQABCgEIAgAAAA==.',
['Ëx']='Ëxcel:BAAANQADCgEIAQAAAA==.',
['Ðu']='Ðungeon:BAAANQAECgIIAgAAAA==.',
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
