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

local lookup = {'Mage-Arcane','Warlock-Affliction','Evoker-Devastation','Rogue-Assassination','Unknown-Unknown','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Warrior-Arms','Druid-Restoration','Rogue-Subtlety','Evoker-Augmentation','DemonHunter-Havoc','Shaman-Restoration','Hunter-BeastMastery','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','Shaman-Elemental','Mage-Frost','Monk-Windwalker','Druid-Feral','Warlock-Demonology','Evoker-Preservation','Warrior-Fury','Priest-Holy','Warlock-Destruction','Rogue-Outlaw','Monk-Mistweaver','Hunter-Marksmanship','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aabc:BAAANQAECgQIBQAAAA==.Aaubree:BAAANQADCggICQAAAA==.',
Ab='Ababymage:BAABNQAECoEYAAIBAAgK9xDxnQD/AQABAAgK9xDxnQD/AQAAAA==.Abbiocco:BAAANQAECgQICAAAAA==.Abbotsmurfh:BAEANQAECgUIDgAAAA==.',
Ac='Acareseandra:BAABNQAECoEbAAICAAcKEhKEBwDZAQACAAcKEhKEBwDZAQAAAA==.Achkdragon:BAABNQAECoEiAAIDAAkKMhaVDQBRAgADAAkKMhaVDQBRAgAAAA==.Acquirer:BAAANQAECgEIAgAAAA==.',
Ad='Adelyne:BAAANQAECgUIAwAAAA==.Adeshu:BAAANQAECgEJAQAAAA==.Adhd:BAAANQAECgYJDAAAAA==.Adorele:BAAANQAECgIIAgABNQAECgkJKwAEAFghAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQAECgQIBAAAAA==.',
Ai='Aibohphobia:BAAANQAECgUIBwAAAA==.Aindriu:BAAANQADCgEIAQAAAA==.',
Al='Alaion:BAAANQADCgQIBAAAAA==.Alakazamn:BAAANQAECgQIEgAAAA==.Albalupus:BAAANQADCgQIBwAAAA==.Albirt:BAAANQABCggIDAAAAA==.Aldoraeinna:BAAANQADCgUICQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBwAFAAAAAA==.Alexyus:BAAANQAECgEIAQAAAA==.Aliski:BAAANQADCgUICAABNQAECgQIBAAFAAAAAA==.Alodso:BAAANQADCgYIBgAAAA==.Aloys:BAAANQAECgYICQAAAA==.Alpharetta:BAAANQAECgcIDwAAAA==.',
Am='Amavessa:BAAANQAECgQIBQAAAA==.Amorous:BAAANQAECgQICgAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Anankee:BAAANQABCgEJAQAAAA==.Andromedus:BAAANQAECgYICgAAAA==.Aneedaheals:BAAANQAECgUICAAAAA==.Animositea:BAAANQAECgEIAQABNQAECgUICwAFAAAAAA==.Anyasil:BAABNQAECoEbAAMGAAgKgB9oDwDLAgAGAAgKgB9oDwDLAgAHAAEK0Q7SIQA0AAAAAA==.',
Ap='Apostle:BAAANQAECgUICAAAAA==.',
Ar='Arboribus:BAAANQADCgYIDAAAAA==.Arcedd:BAAANQADCgYICAAAAA==.Archdogepie:BAAANQAECgIIBAAAAA==.Arcédd:BAAANQADCgMIAwAAAA==.Arrianassa:BAAANQAECgUICwAAAA==.Arrietty:BAAANQADCgYIBgAAAA==.Arrowniri:BAABNQAECoEYAAMIAAgKkQ11UgBlAQAIAAgKGw11UgBlAQAJAAQKYAwZYQCkAAAAAA==.Arrowtide:BAAANQAECgQIBgAAAA==.Arrowzmight:BAAANQAECgEIAQABNQAECgQIBgAFAAAAAA==.Artogand:BAAANQADCggIHAAAAA==.Aruho:BAAANQAECgUIDAAAAA==.Arvad:BAABNQAECoEaAAIKAAcK7x2GMwBbAgAKAAcK7x2GMwBbAgAAAA==.',
As='Ascalon:BAABNQAECoEfAAILAAkKGBSHTQBiAgALAAkKGBSHTQBiAgAAAA==.Asclepión:BAABNQAECoEkAAIMAAkKaRHqFABYAgAMAAkKaRHqFABYAgAAAA==.Ashynii:BAAANQADCgIIAgAAAA==.Asteria:BAAANQADCggIHQAAAA==.',
At='Athania:BAAANQAECgUIDgAAAA==.Atoli:BAABNQAECoEgAAIJAAgKlw+wLgDGAQAJAAgKlw+wLgDGAQAAAA==.',
Av='Avannir:BAAANQAECgEIAQABNQAECgQICQAFAAAAAA==.Averlandra:BAABNQAECoErAAMEAAkKWCHhBABgAwAEAAkKWCHhBABgAwANAAcKLhvmFgAFAgAAAA==.Avrora:BAAANQADCggICgABNQAFFAEIAQAFAAAAAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAABNQAFFIEXAAMDAAUKgCbfAAA8AgADAAUKgCbfAAA8AgAOAAEKoBpPBwBXAAAAAA==.Azbrodeus:BAAANQADCgYIEwAAAA==.Azstastic:BAABNQAECoEVAAIPAAcKJh7tIABJAgAPAAcKJh7tIABJAgAAAA==.',
Ba='Bacondad:BAAANQADCggIHgABNQAECgUIBQAFAAAAAA==.Bandit:BAAANQADCggJCgAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAABNQAECoEkAAIQAAkK5BDvRwDzAQAQAAkK5BDvRwDzAQAAAA==.',
Be='Bearicades:BAAANQAECgEJAQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCggJCQABNQAECgMIAwAFAAAAAA==.Beg:BAAANQADCgMIAwABNQAECgYIEgAFAAAAAA==.Bejeweled:BAAANQAECgQICgAAAA==.Bellatrixt:BAABNQAECoEdAAIRAAkK2yB6HwDjAgARAAkK2yB6HwDjAgAAAA==.Bellilia:BAAANQAECgQIBQAAAA==.Belvard:BAAANQADCgUIBQABNQAECgQIDQAFAAAAAA==.Berkinoff:BAABNQAECoEWAAILAAcKEiBXRQB+AgALAAcKEiBXRQB+AgAAAA==.Besty:BAABNQAECoEfAAISAAkKiBJTKwA+AgASAAkKiBJTKwA+AgAAAA==.',
Bh='Bharmir:BAAANQAECgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgQICAAAAA==.Bigdemon:BAAANQAECgcIEgAAAA==.Bighardshock:BAAANQAECgQICAAAAA==.Bigshrimp:BAABNQAECoEZAAITAAcKwxUeEQAMAgATAAcKwxUeEQAMAgAAAA==.Bigstoot:BAAANQAECgMIBQAAAA==.Bilong:BAAANQADCgYIEAAAAA==.',
Bl='Blazingdh:BAAANQADCgIIAgAAAA==.Bleddyn:BAAANQADCgMIAwABNQAECgYICQAFAAAAAA==.Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQAECgEIAQAAAA==.Blesslock:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQAECgcIDAAAAA==.Blizzdawg:BAAANQADCgQIBAAAAA==.Bluebean:BAAANQAECgcIEwAAAA==.Bluelili:BAAANQADCgYIDAAAAA==.Bluemeenie:BAABNQAECoEXAAISAAcKdQ1LRgCEAQASAAcKdQ1LRgCEAQAAAA==.Bluish:BAAANQAECgUJBQABNQAECgcIDAAFAAAAAA==.Bluntknucks:BAAANQABCgQIBgAAAA==.',
Bo='Bobsmage:BAAANQADCgYIBgAAAA==.Bodysnatcher:BAAANQADCgUIBQABNQAECgQIBwAFAAAAAA==.Bonybolt:BAAANQABCgIIAgAAAA==.Bool:BAAANQADCgIIBAABNQAECgMIBQAFAAAAAA==.Booti:BAAANQAECgYJEAAAAA==.Borz:BAAANQAECgUIDAAAAA==.Bottleabeer:BAAANQADCgMIAwAAAA==.Boxspring:BAAANQAECggIEgAAAA==.',
Br='Brays:BAAANQAECgQICAAAAA==.Brbtacos:BAABNQAECoEbAAMUAAgKvBfiUwBIAgAUAAgKvBfiUwBIAgAVAAUKUw5INgDcAAAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Breezeblöcks:BAAANQADCggIDQAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAABNQAECoEaAAMKAAcKMSXoFwDwAgAKAAcKMSXoFwDwAgAUAAUKuAp10AAGAQAAAA==.Brndo:BAAANQAECgUICQAAAA==.Brogoth:BAAANQAECgQICgAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brukah:BAAANQADCggICAAAAA==.Brunoxp:BAABNQAECoEqAAIWAAkKaSLWBgByAwAWAAkKaSLWBgByAwAAAA==.',
Bu='Bubblebun:BAAANQAFFAIIAgAAAA==.Bumblebee:BAAANQADCgEJAQAAAA==.Burgoth:BAAANQADCgUIBwAAAA==.Burndo:BAAANQAECgIIAgABNQAECgUICQAFAAAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
['Bè']='Bèndèr:BAAANQABCgEIAQABNQABCgQIBAAFAAAAAA==.',
Ca='Cabss:BAAANQAECgUIDQAAAA==.Caelum:BAAANQAECgYICQAAAA==.Calaban:BAAANQAECgUIEAAAAA==.Caldìr:BAAANQAECgQICAAAAA==.Callazia:BAAANQAECgUICgAAAA==.Callvar:BAAANQADCggJCAAAAA==.Calvandersen:BAAANQADCgQIBAAAAA==.Calyssena:BAAANQAECgUIDwAAAA==.Camalyn:BAAANQABCgEIAQAAAA==.Candies:BAABNQAECoEWAAMQAAkKLxcyQwAHAgAQAAYKTR8yQwAHAgAXAAMKVQx6zQCOAAAAAA==.Candybars:BAAANQAECggIAQAAAA==.Canthea:BAAANQAECgYICgAAAA==.Carrot:BAABNQAECoEZAAIRAAcKfCGmMACaAgARAAcKfCGmMACaAgAAAA==.Casaundra:BAEANQADCggIFQAAAA==.Cashmir:BAABNQAECoEZAAIBAAcKkgUy8QBWAQABAAcKkgUy8QBWAQAAAA==.Castalerus:BAAANQADCggJGAAAAA==.Casterlady:BAAANQADCgEIAQAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgUJDgAAAA==.Catsmurga:BAABNQAECoE3AAILAAkKPCD9GwAoAwALAAkKPCD9GwAoAwAAAA==.',
Cc='Ccogs:BAAANQABCgQIBAABNQABCgQIBQAFAAAAAA==.',
Ce='Celibate:BAABNQAECoEbAAILAAcKChU8ewDVAQALAAcKChU8ewDVAQAAAA==.Cellasril:BAAANQADCgUJBQAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Cello:BAAANQAECgEJAgABNQAECgQIBwAFAAAAAA==.Celticfrost:BAABNQAECoEaAAMYAAcK1gpCGwDSAAABAAcKngr3zwCVAQAYAAUKhgdCGwDSAAAAAA==.',
Ch='Chaewon:BAAANQADCgYJDgAAAA==.Chasèd:BAAANQAECgQIBAAAAA==.Chuddette:BAAANQAECgMICQAAAA==.Chumashu:BAAANQAFFAEIAQABNQAECgkJJwAZAN4kAA==.Chïllidan:BAAANQAECggIAgAAAA==.',
Ci='Circlinsmoth:BAAANQABCgMIAwAAAA==.Cirmorte:BAAANQADCggICAAAAA==.Ciroza:BAAANQAECgQICAAAAA==.',
Co='Cogsworthh:BAAANQABCgQIBQAAAA==.Corpserunner:BAABNQAECoEVAAISAAYKyw+QSgBrAQASAAYKyw+QSgBrAQAAAA==.',
Cr='Crazytrain:BAAANQAECgIIAQAAAA==.Creekstone:BAAANQAECgQIBwAAAA==.Creep:BAAANQADCgMIAwAAAA==.Cristty:BAAANQADCggIDwAAAA==.Crowul:BAAANQADCgMIAwAAAA==.Crystallyn:BAABNQAECoEaAAIYAAcKEBXdCgDEAQAYAAcKEBXdCgDEAQAAAA==.',
Cu='Cubanmage:BAAANQAECggIDQAAAA==.Cutter:BAAANQADCgUJBQAAAA==.',
Cy='Cybelis:BAAANQADCgYJBgAAAA==.Cybelliar:BAAANQAECgYIEQAAAA==.Cynders:BAAANQAECgYIEwAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBQABNQABCgQIBQAFAAAAAA==.',
Da='Dabalt:BAAANQAECgMIAwABNQAECgYIDAAFAAAAAA==.Dadamaxx:BAAANQAECgUJCgAAAA==.Daemlon:BAAANQAECgUIDQAAAA==.Daniel:BAAANQAECgUIBwAAAA==.Darbane:BAAANQAECgMIBAAAAA==.Dargonsevzer:BAAANQAECgcJEgAAAA==.Darkbeárd:BAAANQAECgcIEwAAAA==.Daspen:BAABNQAECoE+AAIaAAkKKiQPAQC4AwAaAAkKKiQPAQC4AwAAAA==.Daysalt:BAAANQAECggICQAAAA==.Daßalt:BAAANQAECgYIDAAAAA==.',
De='Deadshotdak:BAAANQAECgQIBAABNQAECggIGgALAOcWAA==.Deathbychaos:BAAANQADCgYIDAAAAA==.Deathcrip:BAAANQADCgUIBQABNQAECgkJJQARAK0jAA==.Delonge:BAAANQAFFAIIAwAAAA==.Delorand:BAAANQABCggICgAAAA==.Delriel:BAAANQAECgUICwAAAA==.Demeters:BAAANQADCgUIBQAAAA==.Demetra:BAAANQABCgIIAgAAAA==.Demonfuryx:BAAANQAECgEIAQAAAA==.Demonkeeper:BAAANQADCgYIEwAAAA==.Denaror:BAAANQADCgMJAwAAAA==.Denzai:BAABNQAECoEZAAIDAAgK+RNREAAVAgADAAgK+RNREAAVAgAAAA==.Deshyr:BAAANQAECgYIDgAAAA==.Despere:BAAANQABCgEIAQAAAA==.Deviant:BAACNQAFFIEGAAMNAAMKjRsOCgC5AAANAAIKbxoOCgC5AAAEAAIKoQ8PDgCTAAA1AAQKgR8AAwQACQqxI2cXAHECAAQABwqfHmcXAHECAA0ABwr8HvIRAEICAAAA.Devvy:BAAANQAECgQICAAAAA==.Dewzero:BAAANQAECgEIAQAAAA==.Deyalanis:BAAANQADCggICAAAAA==.',
Dh='Dha:BAAANQAECgcIEQAAAA==.',
Di='Diablìta:BAAANQADCggIDQAAAA==.Dingaling:BAAANQADCggIEwAAAA==.Dirt:BAABNQAECoEmAAISAAkK+R7dDgAzAwASAAkK+R7dDgAzAwAAAA==.Dirtz:BAAANQAECgMIAwABNQAECgkJJgASAPkeAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dj='Djdeath:BAAANQADCgUICAABNQAECggJEAAFAAAAAA==.',
Dk='Dkdiddy:BAABNQAECoEYAAMWAAgKRhbONgDrAQAWAAgKLBbONgDrAQAJAAQKvA9hUgDhAAAAAA==.',
Do='Docnathrius:BAAANQAECgMIBQAAAA==.Dogodeath:BAAANQAECgQIBQAAAA==.Domago:BAABNQAECoEfAAIbAAkK6hd+MACMAgAbAAkK6hd+MACMAgAAAA==.Dorknight:BAAANQAECgUIDwAAAA==.Dotfeardot:BAAANQAECgUICAAAAA==.Dotsandfear:BAAANQABCgcIBgAAAA==.Dougue:BAACNQAFFIEKAAINAAUKow7vBACkAQANAAUKow7vBACkAQA1AAQKgSEAAw0ACQrqHRUHAPcCAA0ACQp2HRUHAPcCAAQAAgq+BJpqAGEAAAAA.',
Dp='Dpalm:BAABNQAECoEiAAMGAAgKViDwDgDRAgAGAAgKViDwDgDRAgAHAAEKDw/oHwA5AAAAAA==.',
Dr='Dracogelly:BAAANQAECgYICQAAAA==.Draedia:BAAANQAECgIIAgAAAA==.Draedio:BAAANQAECgIIAgAAAA==.Dragonarc:BAAANQADCgQIBAAAAA==.Dragonnuts:BAABNQAECoEXAAIcAAcK9RBGHwCaAQAcAAcK9RBGHwCaAQAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drazelle:BAAANQABCgIIAgAAAA==.Drdeathtron:BAAANQAECgYICQAAAA==.Drenare:BAAANQADCgEJAQABNQAFFAQIBwALAEgiAA==.Drevix:BAABNQAECoEXAAIdAAcKQxBXDAClAQAdAAcKQxBXDAClAQAAAA==.Drinkabeer:BAAANQADCgUIBgAAAA==.Drneil:BAAANQADCgMIAwAAAA==.Dromanicus:BAAANQADCggJCAAAAA==.Drovodian:BAAANQAECgQIBAAAAA==.Dru:BAABNQAECoEaAAILAAgK5xaoXwAmAgALAAgK5xaoXwAmAgAAAA==.Druidzilla:BAAANQABCgUIBQABNQADCgcIEwAFAAAAAA==.',
Du='Dudaelah:BAAANQADCgYICwAAAA==.Dudeak:BAAANQAECgYIEQAAAA==.Dulled:BAAANQADCgUIBwABNQAECgIIAwAFAAAAAA==.Dundoh:BAABNQAECoEkAAIUAAkKkR8uHQAiAwAUAAkKkR8uHQAiAwAAAA==.Durimluz:BAAANQABCgQIAwABNQAECggIGwAVADcaAA==.Durm:BAAANQAECgUIDwAAAA==.Duskknight:BAABNQAECoEWAAMIAAcKVxZWPADQAQAIAAcKVxZWPADQAQAWAAYKLQvyYQAgAQAAAA==.',
Ea='Earthivan:BAAANQADCgYICgAAAA==.Earthlight:BAAANQADCgYICwAAAA==.',
Eb='Ebonchillz:BAAANQADCgYICQAAAA==.',
Ed='Edmundo:BAAANQADCggJBAAAAA==.Edwalex:BAAANQADCgEIAQAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eleeza:BAABNQAECoEaAAMVAAcKoBr4EwAWAgAVAAcKoBr4EwAWAgAUAAEKzAqTVgEuAAAAAA==.Ellephino:BAAANQADCgcIDQABNQAECgQICAAFAAAAAA==.Elleìgh:BAAANQAECgQIBQABNQAECggIJAAeAOgUAA==.Ellidiir:BAAANQADCggIFgAAAA==.Elm:BAAANQAFFAEIAQAAAA==.Elmzoth:BAACNQAFFIEQAAIGAAUKjCQNAgAeAgAGAAUKjCQNAgAeAgA1AAQKgWUAAwYACQraJg4AABUEAAYACQraJg4AABUEAB4AAgq/JqWTAOUAAAE1AAUUAQgBAAUAAAAA.Elmzy:BAAANQADCggICAABNQAFFAEIAQAFAAAAAA==.Elvanshalee:BAAANQAECgQIDQAAAA==.Elylreith:BAAANQADCgYICAAAAA==.Elysiain:BAAANQAECgUIBgAAAA==.',
Em='Eminjangidge:BAAANQAECgQIBAAAAA==.',
En='Enthusiast:BAAANQADCgcIBwAAAA==.Envoshat:BAAANQAECgQIBAAAAA==.',
Er='Erael:BAAANQAECgEIAQAAAA==.Erebseth:BAAANQAECgIIAgAAAA==.Eredeath:BAABNQAECoEZAAIPAAcKIheQKwDuAQAPAAcKIheQKwDuAQAAAA==.Eremier:BAAANQAECgUIBQAAAA==.',
Es='Esdeäth:BAACNQAFFIEGAAIbAAQKZRNhDABCAQAbAAQKZRNhDABCAQA1AAQKgR0AAxsACArqIEkoAK0CABsACArqIEkoAK0CAB8AAgqVDaRWAGgAAAAA.Eskiestout:BAAANQAECggIAQAAAA==.Estar:BAAANQAECgYIDgAAAA==.Estaslól:BAABNQAECoEiAAIQAAgKihtCJQCWAgAQAAgKihtCJQCWAgAAAA==.Estelars:BAAANQADCgUIBQAAAA==.Esxcanor:BAAANQADCggICAABNQAECggIFwABAPMLAA==.',
Et='Etel:BAAANQAECgQIBgAAAA==.Etrnlrapture:BAAANQAECgYIEgAAAA==.',
Eu='Eulerion:BAAANQAECgcJEAAAAA==.Eulkick:BAAANQAECgEIAQABNQAECgcJEAAFAAAAAA==.Eunomia:BAAANQADCgQIBAAAAA==.',
Ev='Evol:BAABNQAECoEXAAIRAAcKZR0eSgBDAgARAAcKZR0eSgBDAgAAAA==.Evolooshon:BAAANQADCgIIAgAAAA==.Evrac:BAABNQAECoEXAAMgAAcK+A0nCwCIAQAgAAcKpQwnCwCIAQANAAQKlQpwMwDhAAAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQAECgUIDQAAAA==.Faerysti:BAAANQAECgYICQAAAA==.Fafafeaf:BAAANQABCgIIAgAAAA==.Fafnir:BAAANQAECgUICwABNQAECgkJLQAPABEkAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQAECgIIBAAAAA==.',
Fe='Fearinshatt:BAAANQADCgYJBgAAAA==.Fellina:BAAANQADCgUIAwAAAA==.Femaelan:BAEANQADCggIDwABNQADCggIFQAFAAAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQAECgQIBgABNQAECgUIBgAFAAAAAA==.',
Fh='Fhalen:BAABNQAECoEYAAICAAcKqw41CADCAQACAAcKqw41CADCAQAAAA==.',
Fi='Fimbik:BAAANQAECgYIDAAAAA==.Fischtya:BAAANQADCgMJAwAAAA==.Fishymd:BAEANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQABCgIJAgAFAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Foot:BAAANQAECgEIAgABNQAECgYIEgAFAAAAAA==.Forgotskillz:BAAANQAECgUICgAAAA==.Fortunatos:BAAANQAECgUIBwAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQAECgQIBQAAAA==.Friendship:BAAANQADCgIIAgABNQAECgcIFwAcAPUQAA==.Frstyfyre:BAAANQADCgYIDgAAAA==.',
Fu='Fullmonty:BAAANQAECgQIBQAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
['Få']='Fårnsworth:BAAANQABCgQIBAAAAA==.',
Ga='Galdrelyne:BAAANQAECgUJBgAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Ganks:BAAANQABCgYIEAAAAA==.Gaobot:BAAANQAECgIIAgAAAA==.Garalagon:BAEANQADCgcIDAABNQADCggIFQAFAAAAAA==.Gargongo:BAAANQAECgUIBQAAAA==.Garros:BAAANQABCgEIAQAAAA==.',
Gb='Gb:BAABNQAECoETAAQfAAkK4BmuKwAMAQAbAAYKnhUEcAC3AQAfAAQKhBKuKwAMAQACAAMKvBYXEwDIAAABNQAECgcIFAAGAEgdAA==.',
Gd='Gdi:BAAANQAECgMIBgAAAA==.',
Ge='Genetunica:BAAANQADCgUICAAAAA==.Genevieve:BAAANQAECgUIBwAAAA==.Gerallt:BAABNQAECoEbAAIIAAcKgBc7NwDrAQAIAAcKgBc7NwDrAQAAAA==.Gerdian:BAAANQAECgUICgAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQAECgYIBgAAAA==.',
Gi='Gigantór:BAABNQAECoEaAAIIAAcKLx5VKQA9AgAIAAcKLx5VKQA9AgAAAA==.Giggtyman:BAAANQAECgIJBAAAAA==.Gille:BAABNQAECoEYAAIeAAcKExXKVgDBAQAeAAcKExXKVgDBAQAAAA==.',
Go='Goldendrae:BAAANQAECgQICAAAAA==.Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAAANQAECgYIEgABNQAECggIGAADAEAHAA==.Greekie:BAAANQAECgYIDAAAAA==.Grotir:BAAANQADCggIDQAAAA==.Grotznik:BAAANQADCgYIBgAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAAANQAECgcIEgAAAA==.Gurenkaina:BAAANQADCgIIAQAAAA==.',
['Gò']='Gòóse:BAAANQAECgYIEgAAAA==.',
Ha='Halogens:BAAANQAECggICAAAAA==.Handmemychi:BAABNQAECoEXAAIhAAcKSRsYEQAfAgAhAAcKSRsYEQAfAgABNQAECgkJHwARAC8kAA==.Handmemygun:BAABNQAECoEfAAMRAAkKLyR0BACsAwARAAkKLyR0BACsAwAiAAIKrgoaXABmAAAAAA==.Hanzdormu:BAACNQAFFIEGAAIcAAQKghqFCABgAQAcAAQKghqFCABgAQA1AAQKgSQABBwACQrYIBsEAF0DABwACQrYIBsEAF0DAAMABAo0DwslAM0AAA4AAgoTIFkSALUAAAAA.Hanzumbra:BAAANQADCggJCAABNQAFFAQIBgAcAIIaAA==.Hanzybadger:BAAANQAECgEIAQABNQAFFAQIBgAcAIIaAA==.Harbofdeath:BAAANQAECgQIDwAAAA==.Hawktuahh:BAAANQADCgcIDQAAAA==.',
He='Healteamsix:BAAANQADCgYIBgAAAA==.Healzarc:BAAANQADCgQIBAAAAA==.Helgaah:BAAANQADCgUICAAAAA==.Helioz:BAAANQAECgEIAQAAAA==.Hemogøblin:BAAANQAECgQICwAAAA==.Herroniden:BAAANQADCgQIBAAAAA==.Hessn:BAABNQAECoEfAAMIAAkKnxWXMgAEAgAIAAgKdReXMgAEAgAWAAEK8gY/xAAdAAAAAA==.',
Hi='Hixz:BAAANQADCggIDQABNQAECgQICQAFAAAAAA==.',
Ho='Holypumper:BAAANQADCggIEQAAAA==.Holyrayne:BAAANQAECgYIDwAAAA==.Hottieheals:BAAANQADCgcICAAAAA==.',
Hu='Hubrinaku:BAAANQADCgcIBwAAAA==.Huntardis:BAAANQAECgYIEAAAAA==.Huntterc:BAAANQAECgEIAQAAAA==.Huracan:BAAANQABCgIIAgABNQAECgUIEAAFAAAAAA==.',
Hy='Hyasept:BAAANQAECgQICQAAAA==.Hydraulic:BAAANQAECgYIEAAAAA==.Hygar:BAAANQADCgMIAwAAAA==.',
Ia='Ialôr:BAABNQAECoEVAAIUAAcKEiWcKADrAgAUAAcKEiWcKADrAgAAAA==.',
Ib='Ibz:BAABNQAECoEWAAINAAgK4SQlAwBmAwANAAgK4SQlAwBmAwAAAA==.',
Ic='Ichedin:BAAANQADCgUJBQAAAA==.',
Id='Idus:BAAANQADCgYIDAAAAA==.',
Il='Ilectos:BAAANQABCggICwAAAA==.Ilirra:BAAANQAECgEIAQAAAA==.',
Im='Impishlee:BAAANQAECgIJAgAAAA==.Impmommy:BAAANQAECgQIBgAAAA==.Impowitz:BAAANQAECgQIBQAAAA==.',
In='Inabakumori:BAAANQADCggICAABNQAFFAEIAQAFAAAAAA==.Incestion:BAAANQAECgEIAQAAAA==.',
Ir='Iradeorum:BAABNQAECoEVAAIjAAYKEQtqNABYAQAjAAYKEQtqNABYAQAAAA==.Irishfelocks:BAAANQAECgUICgAAAA==.',
Is='Isadel:BAAANQADCggIGgAAAA==.Isavedu:BAABNQAECoEcAAMUAAcKhBR/hwCwAQAUAAcKhBR/hwCwAQAKAAEKWANr/gAkAAAAAA==.',
It='Itherael:BAAANQAECgEIAQAAAA==.Ithlord:BAAANQAECgIIAwAAAA==.',
Iv='Ivanbear:BAAANQADCgcIEgAAAA==.Ivannacream:BAAANQADCggICAABNQAECggIHAAkAK4YAA==.Ivansting:BAAANQAECgQIBQAAAA==.Ivanthas:BAAANQADCggIEQAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQAECgEIAQAAAA==.Jahzzy:BAAANQAECgYIEQABNQABCgQIBgAFAAAAAA==.Jaiyanaa:BAABNQAECoEaAAIWAAcKeBrGLwAWAgAWAAcKeBrGLwAWAgAAAA==.Jakem:BAAANQABCgIIAgAAAA==.Jaquita:BAAANQAECgYIEAAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Jc='Jclif:BAAANQADCgMIAwAAAA==.Jcliff:BAAANQADCgMIAwAAAA==.',
Je='Jeffglodblum:BAAANQADCgcIDQAAAA==.Jellylicious:BAAANQADCggIDQAAAA==.Jeluljingo:BAAANQAECgcIDgABNQADCggIDgAFAAAAAA==.Jezilla:BAAANQAECgUIDAAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinainala:BAAANQAECgMIAwAAAA==.Jinsu:BAAANQADCggIIAAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAUIFwADAIAmAA==.Jollyreaper:BAAANQAECgQIDAAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Judgernaut:BAAANQADCgQIBAAAAA==.Julauri:BAAANQADCgIIAgAAAA==.Junglejuice:BAAANQADCgcJCAAAAA==.Juñior:BAABNQAECoEtAAMPAAkKESSpCABMAwAPAAkK6iOpCABMAwAlAAYKYyKfBgBUAgAAAA==.',
Jw='Jwrecks:BAAANQADCgQIBAABNQAECgUIDAAFAAAAAA==.',
Ka='Kaelashe:BAAANQAECgUJBgAAAA==.Kaelyndrace:BAABNQAECoEbAAIUAAcKhRMXhAC5AQAUAAcKhRMXhAC5AQAAAA==.Kaeredan:BAAANQADCggIDwAAAA==.Kahuno:BAABNQAECoEWAAIXAAcKdxMlWwDAAQAXAAcKdxMlWwDAAQAAAA==.Kalimyst:BAABNQAECoEaAAIeAAcKpiCyJwCPAgAeAAcKpiCyJwCPAgAAAA==.Kalutak:BAABNQAECoEbAAMVAAgKNxrAEwAYAgAVAAgKNxrAEwAYAgAUAAIK9BJLEAGKAAAAAA==.Kamisen:BAAANQADCggIIwAAAA==.Kappaccino:BAAANQAECgEIAgABNQAECgkJJwAZAN4kAA==.Karaktzn:BAAANQAECgUICgAAAA==.Karande:BAAANQADCgYIBgAAAA==.Karedon:BAAANQADCgYICQAAAA==.Kasstrah:BAAANQADCgYIDwAAAA==.Kataraz:BAAANQADCgYIEgAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Kea:BAAANQAECgIIAwABNQAECgQIBwAFAAAAAA==.Keenforge:BAABNQAECoEfAAMIAAkKohKHMQAJAgAIAAkKohKHMQAJAgAJAAEKzQTEiQAqAAABNQADCgUIBQAFAAAAAA==.Keknein:BAAANQAECgUICQAAAA==.Kellindor:BAAANQADCggICAAAAA==.Kendrà:BAEANQADCgcIDQABNQADCggIFQAFAAAAAA==.Kentaris:BAABNQAECoEZAAImAAcKvg+TAgDLAQAmAAcKvg+TAgDLAQAAAA==.Keroleaf:BAABNQAECoEUAAIMAAYKYRHQKgBiAQAMAAYKYRHQKgBiAQAAAA==.Key:BAAANQADCgIIAgAAAA==.',
Kh='Khakkora:BAAANQADCgEIAQABNQAECgEIAgAFAAAAAA==.',
Ki='Kiergadran:BAAANQAECgYIEAAAAA==.Killimanjaro:BAABNQAECoEaAAInAAcKfx46CQBpAgAnAAcKfx46CQBpAgAAAA==.Kind:BAAANQABCgQIAwAAAA==.Kinoclaw:BAAANQAFFAEIAQAAAA==.',
Kl='Klaelune:BAABNQAECoEbAAMGAAkKdhTiGwAdAgAGAAgKThXiGwAdAgAeAAgKlxUYQQAcAgAAAA==.',
Kn='Knaring:BAAANQAECgUICAAAAA==.Knocked:BAAANQADCgMIAwABNQAECgYIDwAFAAAAAA==.Knockedw:BAAANQADCgYIBgABNQAECgYIDwAFAAAAAA==.Knowthing:BAABNQAECoEXAAInAAcKdQ/NFgBfAQAnAAcKdQ/NFgBfAQAAAA==.',
Ko='Kohola:BAABNQAECoEjAAIRAAkKfCFpGgD9AgARAAkKfCFpGgD9AgAAAA==.Kolar:BAAANQADCggIFQAAAA==.Kolby:BAAANQADCggIFgAAAA==.Koldar:BAAANQAECgYIDwAAAA==.Kolfsorr:BAAANQABCggIBQAAAA==.Kookies:BAAANQADCgYIBgAAAA==.',
Kr='Kronvoid:BAAANQADCggJCAAAAA==.Kräckerbyrd:BAAANQADCgYIBgAAAA==.Krîmsön:BAAANQAFFAIIAwAAAA==.',
Ku='Kudo:BAABNQAECoEbAAIMAAgK9xIYHQDyAQAMAAgK9xIYHQDyAQAAAA==.Kuroi:BAAANQADCggIDwAAAA==.',
Kv='Kvr:BAAANQADCgQJBgABNQAECgMIBQAFAAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgYIEwAAAA==.Lanthal:BAAANQADCgcIBwAAAA==.Lararrek:BAAANQAECgYIEQAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAABNQAECoEXAAIBAAgK8wtGsQDUAQABAAgK8wtGsQDUAQAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Lea:BAAANQAECgYIBAAAAA==.Leadfoot:BAABNQAECoEaAAIIAAcKwh2EKABEAgAIAAcKwh2EKABEAgAAAA==.Leftd:BAAANQADCgQIBAABNQAECggIJQAJAJkcAA==.Lejaa:BAAANQAECgEIAwAAAA==.Lersneaq:BAAANQADCgYIDQAAAA==.Lexidragon:BAAANQADCgYIEQABNQAECgcIDQAFAAAAAA==.',
Li='Lidina:BAAANQAECgQIBAAAAA==.Lifebreak:BAAANQAECgIIAgAAAA==.Lifestream:BAAANQAECgUICgAAAA==.Ligeia:BAAANQAECgUIBQAAAA==.Lightbier:BAAANQAECgMIAwAAAA==.Lightheels:BAABNQAECoEXAAMeAAcKNiB3KwB8AgAeAAcKNiB3KwB8AgAGAAEKHAwgZwAoAAAAAA==.Lightmourne:BAABNQAECoElAAIVAAgK6B1kCgC2AgAVAAgK6B1kCgC2AgAAAA==.Lilbeep:BAAANQADCgQIBAAAAA==.Liliennia:BAAANQADCgUIBQAAAA==.Lilkitz:BAAANQADCgEIAQAAAA==.Liteforged:BAAANQADCgYIDAAAAA==.',
Ll='Llord:BAAANQAECgEIAQAAAA==.',
Lo='Lockgob:BAAANQADCggICAAAAA==.Lolohjeez:BAAANQADCgcIBwAAAA==.Lotionman:BAABNQAECoEgAAIRAAgKziEdGgD/AgARAAgKziEdGgD/AgAAAA==.Lougi:BAABNQAECoEfAAQJAAkKIBpUHABcAgAJAAkKIBpUHABcAgAWAAYKdA0gYQAkAQAIAAEKHA0bpwA9AAAAAA==.Lougii:BAAANQAECgUIBgABNQAECgkJHwAJACAaAA==.',
Lt='Ltcrisp:BAABNQAECoEWAAICAAUKOBfMCwBYAQACAAUKOBfMCwBYAQAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAABNQAECoE1AAMMAAkK9yIBAgCfAwAMAAkK9yIBAgCfAwASAAYKWBRzSQBxAQAAAA==.Lup:BAAANQADCgYICgAAAA==.',
Ly='Lynaya:BAAANQADCggJCAAAAA==.Lysra:BAAANQADCgQJBAAAAA==.Lysted:BAABNQAECoEhAAMRAAkKYh5EGAAJAwARAAkKYh5EGAAJAwAiAAQKcw2MPwDuAAAAAA==.Lytherella:BAAANQAECgUIDwAAAA==.',
['Là']='Lànce:BAAANQADCggICwABNQAECgUIFgACADgXAA==.',
['Lô']='Lônghorn:BAABNQAECoEkAAIkAAkKfCBgAwA/AwAkAAkKfCBgAwA/AwAAAA==.',
Ma='Magecyalien:BAAANQAECgYICAAAAA==.Mahat:BAAANQAECgYIEgAAAA==.Mahona:BAAANQAECgcIEAAAAA==.Maideejai:BAAANQADCgUJBQAAAA==.Malefíc:BAAANQADCgQIBAAAAA==.Malichai:BAAANQADCgYIBgAAAA==.Maliphos:BAAANQADCgUIBQAAAA==.Manado:BAAANQADCggIHQAAAA==.Manapuddin:BAAANQADCgYIBgABNQAECgcIFwAeADYgAA==.Manwax:BAAANQADCgYIBgABNQAECgkJKgAWAGkiAA==.Marcaine:BAAANQAECgIIAgAAAA==.Margareth:BAAANQAECgUICQAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUICQAFAAAAAA==.Mavverick:BAAANQADCgYIDwAAAA==.Mavverickk:BAAANQAECgQIBQAAAA==.Maxime:BAAANQAECgUIDQAAAA==.Mayo:BAABNQAECoEbAAMUAAcKLw56mQCDAQAUAAcKLw56mQCDAQAKAAIKnQL55ABHAAAAAA==.',
Mc='Mcdruid:BAAANQAECgMIBQAAAA==.',
Md='Mdiggiddy:BAAANQAECgEIAQABNQAECgMIBgAFAAAAAA==.',
Me='Mechamos:BAAANQADCgYICgAAAA==.Medenut:BAAANQAECgUIDAAAAA==.Mellarr:BAAANQAECgEIAQAAAA==.Menalial:BAAANQADCgYIBgAAAA==.Mergos:BAAANQAECgIIAgAAAA==.Mesmureyes:BAAANQADCgUICgAAAA==.',
Mi='Mid:BAAANQAECgYICwAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Mikeyy:BAAANQAECgIIAgAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQAECgEIAQAAAA==.Miori:BAAANQAECgUICAAAAA==.Missbless:BAAANQADCggIDgAAAA==.Missti:BAAANQAECgQIBQAAAA==.Mistletow:BAAANQABCgIIAgAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQAECgQIBgAAAA==.Mizarc:BAAANQAECgQIBAAAAA==.Mizzit:BAAANQAECgIIAgAAAA==.',
Mo='Mogorasil:BAAANQAECgMIBAABNQAECgUICgAFAAAAAA==.Monkichi:BAAANQAECgYIDgAAAA==.Mono:BAAANQAECgYIEAAAAA==.Moopsy:BAAANQAECgIIAgAAAA==.Morganella:BAAANQADCgYICwAAAA==.Morghan:BAABNQAECoEaAAIaAAcKGh5QCABqAgAaAAcKGh5QCABqAgAAAA==.Morgrul:BAAANQAECgIIAgAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAAANQAECgYIEgAAAA==.Mulo:BAAANQADCgMIAwAAAA==.Muravath:BAAANQABCgQIBAAAAA==.Musicjam:BAAANQADCgUICAAAAA==.',
My='Mysp:BAAANQADCggICAABNQAECgIIAwAFAAAAAA==.',
['Mâ']='Mâtano:BAAANQABCgIIAQAAAA==.',
Na='Nadaht:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.Nahjii:BAAANQADCgMIAwAAAA==.Nahteew:BAAANQAECgIIAgAAAA==.Naomì:BAAANQADCgYJDQAAAA==.Naruto:BAAANQAECgQICAAAAA==.Nazurash:BAABNQAECoEaAAMWAAgKDxfbPADIAQAWAAcK8hfbPADIAQAJAAEK3BBrggA2AAAAAA==.',
Ne='Necros:BAAANQADCgYICgAAAA==.Nekgahza:BAAANQADCggICAAAAA==.Nelriel:BAAANQABCggIEAAAAA==.Nelyar:BAABNQAECoEaAAIGAAcKgQRINgAdAQAGAAcKgQRINgAdAQAAAA==.Neonepie:BAAANQAECgYIEgAAAA==.Neostardust:BAAANQADCgYIBgAAAA==.Nermith:BAAANQADCgUIBQAAAA==.Nettero:BAABNQAECoEfAAILAAgK/hNeYQAhAgALAAgK/hNeYQAhAgAAAA==.',
Ni='Nickolasrage:BAAANQAECgQICwAAAA==.Nightfalls:BAAANQADCgMIAwAAAA==.Nineinchmale:BAAANQAECggICAAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nirazenezar:BAAANQADCgYICQAAAA==.Nisgaa:BAABNQAECoEeAAIQAAkKMyRZAQDFAwAQAAkKMyRZAQDFAwAAAA==.',
No='Nockedup:BAAANQAECggIEAAAAA==.Noots:BAAANQADCgYICwAAAA==.Noro:BAEANQAECgEIAwABNQAFFAUICgAiAAEJAA==.Norro:BAECNQAFFIEKAAIiAAUKAQm4CgBAAQAiAAUKAQm4CgBAAQA1AAQKgScAAyIACQp7Hz8LAAMDACIACQp7Hz8LAAMDABEAAQoNC80ZATkAAAAA.Norrow:BAEBNQAECoEqAAIiAAkKHSBjCwABAwAiAAkKHSBjCwABAwABNQAFFAUICgAiAAEJAA==.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAABNQAECoEZAAQZAAcK8Qb0LwApAQAZAAcKuwb0LwApAQAoAAIKRATdJQBIAAAhAAMK5AAXPQA5AAAAAA==.',
Ny='Nymeris:BAABNQAECoEVAAIfAAYKfgXxLQD/AAAfAAYKfgXxLQD/AAAAAA==.Nyritha:BAAANQAECgUIEAAAAA==.Nyxanunit:BAABNQAECoEYAAIPAAcKawURQwA3AQAPAAcKawURQwA3AQAAAA==.',
Og='Oggi:BAAANQAECgEIAQAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQAECgMIBAAAAA==.',
Om='Omau:BAAANQAECgYJDwAAAA==.Omgheroism:BAAANQADCggIDAAAAA==.Omìnous:BAABNQAECoEXAAMbAAkKMBPjagDGAQAbAAgKzhLjagDGAQAfAAIKvhTRSwCGAAAAAA==.',
On='Oneinall:BAABNQAECoEaAAIIAAkKBxNBMQAKAgAIAAkKBxNBMQAKAgAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Op='Oplaya:BAAANQADCgYIBgABNQAECgkJHgAWANUdAA==.',
Or='Oriyn:BAAANQADCggIEwABNQAECgcIGgAnAH8eAA==.Orkar:BAAANQADCgIIAgAAAA==.',
Ov='Overknight:BAAANQAECgQIDwAAAA==.',
Oz='Ozempic:BAABNQAECoEZAAMDAAgKqApWFgCjAQADAAgKdgpWFgCjAQAOAAEKOgYeHQAvAAAAAA==.Ozknife:BAABNQAECoEXAAIgAAcKOB6lBQBfAgAgAAcKOB6lBQBfAgABNQADCgIIAgAFAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQAECgEIAQAAAA==.Padthai:BAAANQAECgYIEAAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQAECgQIBQAAAA==.Papsfear:BAAANQADCgYIDQAAAA==.Paryejah:BAAANQADCgMIAwAAAA==.Payenz:BAAANQADCgQIBAAAAA==.',
Pe='Pease:BAAANQAECgcIEwAAAA==.Peke:BAAANQAECgIIAgAAAA==.Penetrate:BAABNQAECoEkAAInAAkKSR5aBAAEAwAnAAkKSR5aBAAEAwAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECggJEAAFAAAAAA==.Phoenix:BAAANQAECgYIDwAAAA==.',
Pi='Piped:BAAANQADCgMIAwABNQAECgUICwAFAAAAAA==.',
Pl='Pluka:BAAANQAECgUICgAAAA==.',
Pn='Pnub:BAAANQAECgYJEAAAAA==.',
Po='Poet:BAAANQADCgUIBQABNQAFFAIIAwAFAAAAAA==.Polarbear:BAAANQAECgEIAgAAAA==.Pomato:BAAANQAECgYICAAAAA==.Pookle:BAAANQAECgUIBQAAAA==.',
Pr='Praxitelis:BAAANQADCggIEAAAAA==.Priorsmurfh:BAEANQAECgQIBAABNQAECgUIDgAFAAAAAA==.Promithia:BAAANQAECgYIEQAAAA==.Propaladin:BAAANQAECgEJAQAAAA==.Proticia:BAAANQADCgMIAwABNQAECgQIDQAFAAAAAA==.',
Ps='Psychopull:BAAANQADCgUIBQAAAA==.Psydesho:BAAANQADCgUJBQAAAA==.',
Pu='Pumpnectarx:BAAANQAECgQIBAAAAA==.',
Py='Pyriz:BAAANQAECgQIBAAAAA==.',
['Pë']='Pëëk:BAAANQAECgUIDAAAAA==.',
Qu='Quiverx:BAABNQAECoEXAAIRAAcKrCWeHADxAgARAAcKrCWeHADxAgABNQAECggIDQAFAAAAAA==.',
Ra='Rachelmariet:BAABNQAECoEVAAIVAAYKJhtVGwC7AQAVAAYKJhtVGwC7AQAAAA==.Radiumnight:BAAANQAECgMJAgAAAA==.Raeghar:BAABNQAECoEXAAILAAgKLxyKTwBbAgALAAgKLxyKTwBbAgAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Rageon:BAAANQADCgYICQAAAA==.Raihua:BAAANQADCgUICQAAAA==.Rammpart:BAAANQAECgUIDAAAAA==.Rapak:BAAANQADCggIDwAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rashnu:BAAANQAECggICAAAAA==.Rattleballs:BAAANQAECgUICwAAAA==.Ravpt:BAEANQAECgQIBwABNQAECgkJHwAEALYeAA==.Ravvs:BAEBNQAECoEfAAMEAAkKth5iDADtAgAEAAkKth5iDADtAgAgAAIKvRLDEwB+AAAAAA==.',
Re='Rebuff:BAAANQABCgUIAwAAAA==.Refnar:BAABNQAECoEbAAMbAAkKVRiuUAAaAgAbAAcKQRiuUAAaAgAfAAQKpxFELgD9AAAAAA==.Reifle:BAAANQADCgQIBAAAAA==.Rekonsider:BAACNQAFFIEGAAILAAMKphEJFwDhAAALAAMKphEJFwDhAAA1AAQKgSkAAgsACQrbIIMbACsDAAsACQrbIIMbACsDAAAA.Remielle:BAAANQAECgUICgAAAA==.Renewingfist:BAAANQADCggIDgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAAANQAECgYIEwAAAA==.',
Rf='Rff:BAAANQADCgUJBQABNQAFFAQIBwALAEgiAA==.',
Rh='Rhadamanthus:BAAANQAECgUICgAAAA==.Rhiddik:BAAANQAECggIBwAAAA==.Rhysänd:BAAANQAECgQIBAABNQAECgkJGwAbAFUYAA==.',
Ri='Rikora:BAAANQAECgUICwAAAA==.Ring:BAAANQADCggIFgAAAA==.Ripwon:BAAANQABCgMIBQAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rocha:BAAANQADCgQIBAAAAA==.Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAABNQAECoEjAAIXAAkK2yB+EQBCAwAXAAkK2yB+EQBCAwAAAA==.Ronnster:BAAANQAECggJEAAAAA==.Roogy:BAAANQADCggICAABNQAECgUJDAAFAAAAAA==.Rooj:BAAANQAECgcIDwAAAA==.Roojdk:BAAANQAECgQIBQAAAA==.Roojvm:BAAANQAECgUICwAAAA==.Roojvr:BAAANQAECgEIAgAAAA==.Rootevil:BAAANQADCgQIBAAAAA==.Rorkhan:BAAANQABCgYIBwAAAA==.Rovver:BAAANQABCgQIAwAAAA==.Royalet:BAAANQAECgYIEAAAAA==.',
Ru='Rubbyy:BAAANQAECgMIAwAAAA==.Ruelemental:BAAANQAECgQIBAAAAA==.Runk:BAAANQADCgYIDAAAAA==.Ruthlee:BAABNQAECoEiAAISAAkKdCPrBQCWAwASAAkKdCPrBQCWAwAAAA==.',
Ry='Ryenwithane:BAABNQAECoEZAAIRAAkKNCR/CwBgAwARAAkKNCR/CwBgAwABNQAFFAUIEAAoAHIjAA==.Rynella:BAAANQAECgIIAgAAAA==.Ryuven:BAAANQADCgQIBAAAAA==.Ryzix:BAAANQAECgUIBQAAAA==.',
['Rì']='Rìcco:BAAANQADCggIAQAAAA==.',
['Ró']='Róscô:BAAANQAECgQIBQAAAA==.',
Sa='Saarole:BAAANQADCggJCAAAAA==.Saimedin:BAAANQAECgQIDAAAAA==.Salin:BAAANQAECgYIDAAAAA==.Salome:BAABNQAECoEkAAIeAAgK6BQdSAD9AQAeAAgK6BQdSAD9AQAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYICgAAAA==.Sapote:BAAANQADCggIDQAAAA==.Sasoo:BAAANQADCgMIAwAAAA==.Sastor:BAAANQAECgUIDAAAAA==.Sasuske:BAAANQADCgQICAAAAA==.Satheist:BAAANQAECgcIDQAAAA==.',
Sc='Scaredyet:BAAANQAECgIIAgAAAA==.Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQAECgIIAwAFAAAAAA==.Scute:BAAANQAECgQIBwAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQAECgEIAQAAAA==.Seigressa:BAAANQADCgQICAAAAA==.Seije:BAAANQABCgQIBAAAAA==.Seijepaw:BAAANQADCgQIBAAAAA==.Seijethor:BAAANQADCgcIBwAAAA==.Seinduke:BAAANQAECgQICQAAAA==.Seitan:BAAANQAECgEIAQAAAA==.Senael:BAAANQADCgEIAQAAAA==.Sesnic:BAABNQAECoEXAAIMAAgKUQ5XHwDYAQAMAAgKUQ5XHwDYAQAAAA==.Setierian:BAAANQAECgEIAQAAAA==.Seya:BAAANQABCgIIAgAAAA==.',
Sh='Shadymourne:BAAANQADCgQIBAAAAA==.Shamanablast:BAAANQABCggIDQAAAA==.Shamearthen:BAAANQADCgUIBwAAAA==.Shamrexm:BAAANQAECgYICgAAAA==.Shanegillis:BAAANQAECgYIDwAAAA==.Shashdrkiron:BAAANQAECgQICgAAAA==.Sheer:BAAANQAECgQIBAAAAA==.Shenlong:BAAANQAECgUICwAAAA==.Shidae:BAAANQAECgYJDAAAAA==.Shidaestraza:BAAANQADCggIFgAAAA==.Shintorg:BAABNQAECoEaAAMbAAcKvgTasgAFAQAbAAYKQwXasgAFAQAfAAIKcgEHZABCAAAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgQICQABNQAECgUIDQAFAAAAAA==.Shocksi:BAABNQAECoEZAAIQAAcKgyQjGADjAgAQAAcKgyQjGADjAgAAAA==.Shrimpkin:BAAANQAECgcIEgAAAA==.Shrimprage:BAAANQADCgQJBAAAAA==.Shàdðw:BAAANQAECgYIBwAAAA==.',
Si='Sidon:BAAANQABCgEIAQAAAA==.Sienna:BAAANQAECgYIEQAAAA==.Sigmardoom:BAABNQAECoEhAAIdAAkKMSQDAQCIAwAdAAkKMSQDAQCIAwAAAA==.Sinabunch:BAAANQADCgYIBgAAAA==.Singion:BAAANQADCggIDgAAAA==.Sini:BAAANQAECgMIBwAAAA==.Sinji:BAAANQADCgIIAgAAAA==.Sivat:BAABNQAECoEgAAISAAkK7xcGHwCgAgASAAkK7xcGHwCgAgAAAA==.',
Sk='Skronq:BAAANQADCgYICgAAAA==.Skyfel:BAAANQAECgUIEAAAAQ==.',
Sl='Slampiece:BAABNQAFFIEHAAIBAAUKexGXEgCRAQABAAUKexGXEgCRAQABNQAFFAcIDAADADMMAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slymuffin:BAAANQAECgMIBAAAAA==.',
Sm='Smanzerra:BAAANQAECggIDAAAAA==.Smashcaster:BAAANQADCgMIAwABNQAECggJEAAFAAAAAA==.Smerig:BAAANQADCgIIAwAAAA==.Smileycyrus:BAAANQAECggIBAAAAA==.Smúrph:BAAANQAECgQJCAAAAA==.',
Sn='Snafueight:BAAANQADCgQIBAAAAA==.Snafumage:BAAANQADCgEJAQAAAA==.Snaptime:BAABNQAECoEYAAImAAcKdx5PAQBtAgAmAAcKdx5PAQBtAgAAAA==.Snikrmydodle:BAAANQADCggICAABNQAECgUIBQAFAAAAAA==.Snowblade:BAAANQADCgEIAQAAAA==.Snowshamy:BAAANQAECggIAwAAAA==.',
So='Softgrl:BAABNQAECoEcAAIkAAgKrhh6CwA9AgAkAAgKrhh6CwA9AgAAAA==.Solarcorona:BAAANQAECgUIDQAAAA==.Solenne:BAABNQAECoEeAAIKAAgKOhU0PgArAgAKAAgKOhU0PgArAgAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQAECgQIBwABNQAECggIGAALAF8dAA==.Soulhacker:BAAANQAECggIAgAAAA==.Sovereignt:BAAANQAECgUIBQAAAA==.',
Sp='Spaghetti:BAAANQADCgMIAwABNQAECgkJGwAbAFUYAA==.Sparechange:BAAANQAECgIIAwAAAA==.Spinachio:BAAANQAECgUIDQAAAA==.Spiro:BAAANQAECgYJDwAAAA==.Spártacus:BAAANQAECgcICwAAAA==.',
Sq='Squishypart:BAAANQADCgQIBAAAAA==.',
Ss='Ssargeras:BAAANQABCgYICAAAAA==.',
St='Stalkér:BAABNQAECoEjAAIPAAgKbiBTEQDfAgAPAAgKbiBTEQDfAgAAAA==.Steeltemplar:BAABNQAECoEkAAIKAAkKNhEFPQAwAgAKAAkKNhEFPQAwAgAAAA==.Stefanee:BAABNQAECoEbAAIMAAcK/h8/EQCLAgAMAAcK/h8/EQCLAgAAAA==.Stisti:BAABNQAECoEYAAIIAAcKThc9PQDLAQAIAAcKThc9PQDLAQAAAA==.Stoneclaw:BAAANQADCgYIDAAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwABNQAECgMIBQAFAAAAAA==.Stormwrath:BAAANQADCgQIBwABNQAECgQICQAFAAAAAA==.Stown:BAAANQADCgEIAQAAAA==.Styxdraco:BAAANQADCgYIDAAAAA==.',
Su='Subvert:BAAANQAECgEIAQABNQAFFAUICwALAAsfAA==.Succiboi:BAABNQAECoEXAAMfAAcKARdBHwBjAQAfAAUKsBRBHwBjAQAbAAQK6RUfqQAcAQAAAA==.Sugarplum:BAAANQADCgMIAwAAAA==.Sugastank:BAAANQADCgYIEQAAAA==.Sugreeva:BAAANQAECgYIDwAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Supplement:BAABNQAECoEaAAIGAAgKWhWCGwAiAgAGAAgKWhWCGwAiAgAAAA==.Surtain:BAAANQAECgIIAgABNQAFFAUICwALAAsfAA==.Sustained:BAAANQAECgcICQABNQAFFAUICwALAAsfAA==.Susts:BAACNQAFFIELAAILAAUKCx+ECADJAQALAAUKCx+ECADJAQA1AAQKgR0AAwsACQrqJN0SAFkDAAsACQrqJN0SAFkDAB0AAQqEIb8gAF8AAAAA.',
Sw='Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQAECgYIDwAAAA==.',
Sy='Synari:BAAANQAECgUICgAAAA==.Sync:BAAANQAECgQICQAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAABNQAECoEcAAMLAAkK6SHHMwC/AgALAAgKaSPHMwC/AgAnAAMKdRyKHwDvAAAAAA==.Taggis:BAABNQAECoEgAAMBAAkKUyEnaAB9AgABAAcKQyEnaAB9AgAYAAIKiSEHIACsAAAAAA==.Tahane:BAAANQADCgIIAgAAAA==.Talalana:BAAANQADCgYIBgAAAA==.Tallwar:BAABNQAECoEaAAILAAcKyQYQqABQAQALAAcKyQYQqABQAQAAAA==.Tansero:BAABNQAECoEpAAIcAAkKVB4+CQDvAgAcAAkKVB4+CQDvAgAAAA==.Tarklyn:BAAANQAECgQIBwAAAA==.Tarotina:BAAANQAECgQIBgAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQAECgUICwAAAA==.Telriel:BAAANQAECgEIAQAAAA==.Terrabrew:BAABNQAECoEYAAIZAAcKpxwHGAA1AgAZAAcKpxwHGAA1AgAAAA==.Teseban:BAAANQAECgQIBAAAAA==.',
Th='Thaeron:BAABNQAECoElAAIPAAgKkB2aFwCbAgAPAAgKkB2aFwCbAgAAAA==.Thakar:BAABNQAECoEXAAIXAAcKuh/wMQBvAgAXAAcKuh/wMQBvAgAAAA==.Thedizz:BAAANQABCgQJBAAAAA==.Thelana:BAAANQABCgIIAgAAAA==.Themayo:BAAANQAECgUIDQAAAA==.Theonidus:BAAANQAECggICQAAAA==.Thragrom:BAABNQAECoEeAAMWAAkK1R1fFADhAgAWAAkK1R1fFADhAgAJAAMKlAsgaQCEAAAAAA==.Threedayvic:BAAANQAECgUIDgAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.Thîïcc:BAAANQAECgQJCQABNQAECgUJDgAFAAAAAA==.',
Ti='Tickl:BAAANQADCgYIFAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQAECgYIDgAAAA==.Tiktokthot:BAAANQAECgYICQAAAA==.Tilila:BAAANQADCgQIBAAAAA==.Timojen:BAAANQADCgcIDwAAAA==.',
To='Toastman:BAAANQADCgYICwAAAA==.Toetummy:BAAANQADCggIDAAAAA==.Tokkz:BAAANQAFFAEIAQAAAA==.Tonysparks:BAAANQADCggIDAAAAA==.Toracina:BAAANQAECgUICwAAAA==.Totalshocker:BAAANQADCgMIAwAAAA==.Tougyu:BAAANQAECgYJDwAAAA==.',
Tr='Trakyr:BAAANQAECgQICQAAAA==.Treebean:BAAANQADCgcJDQABNQAECgcIEwAFAAAAAA==.Treppenwitz:BAAANQADCgUIBQABNQAECgYIFQAXAFcSAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQAECgIIAgAAAA==.Troodon:BAAANQAECgEIAQAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCgcIFAAAAA==.Tríke:BAAANQAECgMIBAAAAA==.Trùk:BAAANQADCgYIBgAAAA==.',
Tu='Tulurakuq:BAAANQAECgUJBgAAAA==.Tuurok:BAAANQAECgQIBQAAAA==.',
Tw='Twelvepak:BAAANQADCgMIAwAAAA==.',
Un='Uncledigem:BAAANQABCgMIAwABNQADCgcIEwAFAAAAAA==.Unstable:BAAANQAECgMIBgAAAA==.',
Ur='Urnirus:BAAANQAECgUIDwAAAA==.',
Uv='Uvvu:BAAANQAECgcICAAAAA==.',
Va='Vampnor:BAABNQAECoEYAAIRAAYKVCV+NQCHAgARAAYKVCV+NQCHAgAAAA==.Vanhelzing:BAAANQADCggIGgAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQAECgQIBAAAAA==.Varinna:BAAANQADCgUIBQAAAA==.Varlaeus:BAABNQAECoEgAAILAAgKew5peADdAQALAAgKew5peADdAQAAAA==.Varlais:BAABNQAECoEbAAIlAAcKUSB7BQCCAgAlAAcKUSB7BQCCAgABNQAECggIIAALAHsOAA==.',
Ve='Veachkidd:BAAANQAECgYJCgAAAA==.Velazurin:BAAANQADCgMIBAAAAA==.Veledora:BAAANQAECgUIDQAAAA==.Velidnissara:BAAANQAECgQIEQAAAA==.Velkoz:BAAANQAECgEIBQAAAA==.Vellean:BAAANQADCggJCAAAAA==.Velsa:BAAANQAECgUICQABNQAECgUICwAFAAAAAA==.Venat:BAAANQAECgQIBQAAAA==.Vensa:BAAANQADCgQJBAAAAA==.Vex:BAAANQAECgMIAwAAAA==.',
Vi='Vissaia:BAABNQAECoEVAAMKAAcKYRp0PwAmAgAKAAcKYRp0PwAmAgAUAAEKUwYZWQEsAAAAAA==.',
Vo='Volacious:BAAANQADCgUIEQAAAA==.Voodou:BAAANQADCgYIBgAAAA==.Vordo:BAAANQADCgYIDAAAAA==.Vorr:BAAANQADCgQIBAAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEIAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Warhard:BAAANQADCgMIAwAAAA==.Warlockkink:BAAANQAECgEIAQAAAA==.Warre:BAAANQADCgcIBwAAAA==.Washlunk:BAAANQAECgUIDAAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAABNQAECoEoAAMQAAkKFh8xFQD2AgAQAAkKFh8xFQD2AgAXAAQKHhumhwA5AQAAAA==.Waxyness:BAAANQADCgUIBgAAAA==.',
Wh='Wharph:BAAANQAECgYIEgAAAA==.Whitedahlia:BAAANQAECgIIAgAAAA==.Whitepyre:BAAANQAECggJEAABNQAFFAUIFwADAIAmAA==.Wholadin:BAAANQAECgQIBAAAAA==.Whome:BAAANQADCgYIDAAAAA==.',
Wi='Wilmarth:BAAANQAECgUIBwAAAA==.Winchèster:BAAANQAECgQICQABNQAECgUIFgACADgXAA==.Windbreaker:BAAANQADCgYICQAAAA==.',
Wo='Wolldays:BAAANQADCgcIBwABNQAECgQIBAAFAAAAAA==.Wollmane:BAAANQADCggIDAABNQAECgQIBAAFAAAAAA==.Wongo:BAAANQADCggICAABNQAFFAcIFQAZAJ4cAA==.Woolybugger:BAAANQAECgEJAQAAAA==.',
Wr='Wråth:BAAANQAECgYJDQAAAA==.',
Xa='Xalashock:BAAANQADCggJCAAAAA==.',
Xe='Xeleci:BAABNQAECoEbAAILAAcKDB6iVABKAgALAAcKDB6iVABKAgAAAA==.',
Ya='Yamon:BAAANQAECgUIDwAAAA==.Yamsees:BAAANQAECgQIBQAAAA==.Yangduke:BAAANQADCggICAABNQAECgQICQAFAAAAAA==.Yardsnack:BAAANQADCgQIBgAAAA==.Yashipha:BAAANQADCgUIBwAAAA==.',
Yb='Ybnxdolo:BAAANQADCgcIEwAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Ye='Yevven:BAAANQADCgYICwAAAA==.',
Yu='Yulmegerth:BAAANQADCggIIQAAAA==.Yummieyum:BAAANQADCggIDAAAAA==.Yurthong:BAAANQAECgQIBAAAAA==.',
['Yô']='Yôô:BAAANQADCgUIBQAAAA==.',
Za='Zairy:BAAANQADCggICAABNQAECggIFgANAOEkAA==.Zarcise:BAAANQAECgUIBQAAAA==.Zart:BAAANQAECgUICwAAAA==.',
Ze='Zedrolor:BAABNQAECoEoAAMdAAkKLiNFAQBtAwAdAAkKmCJFAQBtAwALAAMKSiJRtAAtAQAAAA==.Zekar:BAAANQAECgMJBAAAAA==.Zenful:BAAANQADCgMIAwAAAA==.Zenithcia:BAABNQAECoEaAAIIAAcKiBOoRQChAQAIAAcKiBOoRQChAQAAAA==.Zeoma:BAAANQADCggIHwAAAA==.Zerafìn:BAABNQAECoEfAAIBAAgKlhExmAAMAgABAAgKlhExmAAMAgAAAA==.Zerenitynow:BAABNQAECoEbAAMZAAcK0hZQHwDcAQAZAAcK0hZQHwDcAQAhAAIK4QdIOQBPAAAAAA==.Zereora:BAAANQADCgIJAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEIAgAAAA==.',
Zi='Zilyn:BAACNQAFFIEGAAIQAAMKEA0bDwDtAAAQAAMKEA0bDwDtAAA1AAQKgSgAAhAACQrdEFlLAOUBABAACQrdEFlLAOUBAAAA.',
Zo='Zookeeper:BAAANQADCgUIBwAAAA==.',
Zr='Zraidn:BAAANQAECgUIDwAAAA==.Zromaverick:BAAANQADCgEIAQAAAA==.',
['Àr']='Àrthäs:BAAANQABCgEIAQAAAA==.',
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
