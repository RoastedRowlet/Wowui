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

local lookup = {'Mage-Arcane','Monk-Brewmaster','Warlock-Affliction','Evoker-Devastation','Rogue-Assassination','Unknown-Unknown','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Warrior-Arms','Druid-Restoration','Rogue-Subtlety','DemonHunter-Vengeance','Evoker-Augmentation','DemonHunter-Havoc','Shaman-Restoration','Hunter-BeastMastery','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Shaman-Elemental','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','Priest-Holy','Mage-Frost','Monk-Windwalker','Warrior-Protection','Druid-Feral','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Warrior-Fury','Hunter-Marksmanship','Druid-Guardian','Rogue-Outlaw','Monk-Mistweaver','Mage-Fire',}
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aabc:BAAANQAECgQIBQAAAA==.Aaubree:BAAANQAECgcIBwAAAA==.',
Ab='Ababymage:BAABNQAECoEZAAIBAAgKYhGcswD5AQABAAgKYhGcswD5AQAAAA==.Abbiocco:BAAANQAECgUIDQAAAA==.Abbotsmurfh:BAEBNQAECoEWAAICAAcKlxX1DwDLAQACAAcKlxX1DwDLAQAAAA==.',
Ac='Acareseandra:BAABNQAECoEeAAIDAAgKdxEtBwALAgADAAgKdxEtBwALAgAAAA==.Achkdragon:BAABNQAECoElAAIEAAkKGBeJDgBZAgAEAAkKGBeJDgBZAgAAAA==.Acquirer:BAAANQAECgQICAAAAA==.',
Ad='Adelyne:BAAANQAECgUIAwAAAA==.Adeshu:BAAANQAECgEJAQAAAA==.Adhd:BAAANQAECgYIEgAAAA==.Adorele:BAAANQAECgIIAgABNQAFFAMIBwAFABoiAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQAECgQIBAAAAA==.',
Ai='Aibohphobia:BAAANQAECgUIDAAAAA==.Aindriu:BAAANQADCgEIAQAAAA==.',
Al='Alaion:BAAANQADCgQIBAAAAA==.Alakazamn:BAAANQAECgQIEgAAAA==.Albalupus:BAAANQADCgQIBwAAAA==.Albirt:BAAANQABCggIDAAAAA==.Aldoraeinna:BAAANQADCgUICQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBwAGAAAAAA==.Alexyus:BAAANQAECgEIAQAAAA==.Aliski:BAAANQADCgUICAABNQAECgYICgAGAAAAAA==.Alodso:BAAANQADCgYIBgAAAA==.Aloys:BAAANQAECgYIDwAAAA==.Alpharetta:BAAANQAECgcIDwAAAA==.',
Am='Amavessa:BAAANQAECgQICQAAAA==.Amorous:BAAANQAECgQICgAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Anankee:BAAANQABCgEJAQAAAA==.Ancasta:BAAANQADCgIIAgAAAA==.Andromedus:BAAANQAECgYICwAAAA==.Aneedaheals:BAAANQAECgYIDgAAAA==.Animositea:BAAANQAECgEIAQABNQAECgYIEQAGAAAAAA==.Anyasil:BAABNQAECoEjAAMHAAgKBCEmDgD1AgAHAAgKBCEmDgD1AgAIAAEK0Q4+JwAwAAAAAA==.',
Ap='Apostle:BAAANQAECgUIDAAAAA==.',
Ar='Arboribus:BAAANQADCgYIDAAAAA==.Arcaniopure:BAAANQADCgYICgAAAA==.Arcedd:BAAANQADCgYICAAAAA==.Archdogepie:BAAANQAECgIIBAAAAA==.Arcédd:BAAANQADCgMIAwAAAA==.Argerity:BAAANQADCgIIAgAAAA==.Arrianassa:BAAANQAECgUIEAAAAA==.Arrietty:BAAANQADCgYIBgAAAA==.Arrowniri:BAABNQAECoEcAAMJAAgKkQ2yXABeAQAJAAgKGw2yXABeAQAKAAQKYAyxbQCkAAAAAA==.Arrowtide:BAAANQAECgQICAABNQAECgUICQAGAAAAAA==.Arrowzmight:BAAANQAECgUICQAAAA==.Artogand:BAAANQADCggIHwAAAA==.Aruho:BAAANQAECgUIDAAAAA==.Arvad:BAABNQAECoEhAAILAAgK8B21JwCyAgALAAgK8B21JwCyAgAAAA==.',
As='Ascalon:BAACNQAFFIEGAAIMAAMK/AfdHwDLAAAMAAMK/AfdHwDLAAA1AAQKgSMAAgwACQrzFL5TAHMCAAwACQrzFL5TAHMCAAAA.Asclepión:BAABNQAECoEqAAINAAkKCBS5FQBzAgANAAkKCBS5FQBzAgAAAA==.Ashynii:BAAANQADCgIIAgAAAA==.Askiastout:BAAANQAECggICAAAAA==.Asteria:BAAANQADCggIIAAAAA==.',
At='Athania:BAAANQAECgUIEwAAAA==.Atoli:BAABNQAECoEiAAIKAAgK6Q8FNgDDAQAKAAgK6Q8FNgDDAQAAAA==.',
Av='Avannir:BAAANQAECgEIAQABNQAECgQICgAGAAAAAA==.Averlandra:BAACNQAFFIEHAAIFAAMKGiIECQAxAQAFAAMKGiIECQAxAQA1AAQKgTEAAwUACQrsISwGAFsDAAUACQrsISwGAFsDAA4ABwouG5IZAPoBAAAA.Avrora:BAAANQADCggICgABNQAECgkJGwAPAFofAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAACNQAFFIEYAAMEAAUKgCZEAQA1AgAEAAUKgCZEAQA1AgAQAAEKoBqGCQBTAAA1AAQKgRYAAgQACQpoJfkGAP8CAAQACQpoJfkGAP8CAAAA.Azbrodeus:BAAANQADCgYIGAAAAA==.Azstastic:BAABNQAECoEdAAIRAAgKGx4mGwCcAgARAAgKGx4mGwCcAgAAAA==.',
Ba='Bacondad:BAAANQADCggIHgABNQAECgUIBQAGAAAAAA==.Bandit:BAAANQADCggJCgAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAABNQAECoEsAAISAAkKZxEqUwDtAQASAAkKZxEqUwDtAQAAAA==.',
Be='Bearicades:BAAANQAECgEIAQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCggICQABNQAECgMIBQAGAAAAAA==.Beg:BAAANQADCgMIAwABNQAECgcIHAANAC4SAA==.Bejeweled:BAAANQAECgUIDwAAAA==.Bellatrixt:BAACNQAFFIEIAAITAAUKVQb3CwBcAQATAAUKVQb3CwBcAQA1AAQKgSMAAhMACQphIQ8lAOQCABMACQphIQ8lAOQCAAAA.Bellilia:BAAANQAECgQICQAAAA==.Belvard:BAAANQADCgUIBQABNQAECgQIDQAGAAAAAA==.Berkinoff:BAABNQAECoEdAAIMAAgKtx8dOQDJAgAMAAgKtx8dOQDJAgAAAA==.Besty:BAABNQAECoEfAAIUAAkKiBJ0MgAqAgAUAAkKiBJ0MgAqAgAAAA==.',
Bh='Bharmir:BAAANQAECgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgQICQAAAA==.Bigdemon:BAABNQAECoEVAAIVAAkKSxneEgC9AgAVAAkKSxneEgC9AgAAAA==.Bighardshock:BAAANQAECgQIDAAAAA==.Bigshrimp:BAABNQAECoEgAAIWAAgKsRUGEABNAgAWAAgKsRUGEABNAgAAAA==.Bigstoot:BAAANQAECgQICwAAAA==.Bilong:BAAANQAECgMIAwAAAA==.Birdieqt:BAAANQAECgIIAgAAAA==.',
Bl='Blazingdh:BAAANQADCgIIAgAAAA==.Bleddyn:BAAANQAECgYIBwABNQAECgYIDwAGAAAAAA==.Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQAECgUIBgAAAA==.Blesslock:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQAECgcIEAAAAA==.Blizzdawg:BAAANQADCgQIBAAAAA==.Bluebean:BAABNQAECoEZAAMSAAkKmxhmNABoAgASAAkKmxhmNABoAgAXAAUK8g9fogAhAQAAAA==.Bluelili:BAAANQADCgYIDAAAAA==.Bluemeenie:BAABNQAECoEeAAIUAAgKRRGPPQDgAQAUAAgKRRGPPQDgAQAAAA==.Bluish:BAAANQAECgUJBQABNQAECgcIEAAGAAAAAA==.Bluntknucks:BAAANQABCgQIBgAAAA==.',
Bo='Bobsmage:BAAANQAECgUIBQAAAA==.Bodysnatcher:BAAANQADCgUIBQABNQAECgQICAAGAAAAAA==.Bonybolt:BAAANQAECgEIAQAAAA==.Bool:BAAANQADCgIIBAABNQAECgQICwAGAAAAAA==.Booti:BAAANQAECgYJEAAAAA==.Borz:BAAANQAECgYIDQAAAA==.Bottleabeer:BAAANQADCgMIAwAAAA==.Boxspring:BAAANQAECggIEgAAAA==.',
Br='Brakum:BAAANQABCgQIBAABNQAECggIHgAKAI4aAA==.Brays:BAAANQAECgYICwAAAA==.Brbtacos:BAABNQAECoEiAAMYAAgKYRr3WwBaAgAYAAgKYRr3WwBaAgAZAAUKUw5DPwDTAAAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Breezeblöcks:BAAANQADCggIDQAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAABNQAECoEhAAMLAAcKyiVIGgD6AgALAAcKyiVIGgD6AgAYAAUKuAq08QAAAQAAAA==.Brndo:BAAANQAECgYIDgAAAA==.Brogoth:BAAANQAECgQICgAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brukah:BAAANQADCggICAAAAA==.Brunoxp:BAACNQAFFIEGAAIaAAUKwhHBBwB7AQAaAAUKwhHBBwB7AQA1AAQKgSwAAhoACQr5Il4LAE0DABoACQr5Il4LAE0DAAAA.',
Bu='Bubblebun:BAAANQAFFAIIAgAAAA==.Bumblebee:BAAANQADCgEJAQAAAA==.Burgoth:BAAANQADCgUIBwAAAA==.Burndo:BAAANQAECgIIAgABNQAECgYIDgAGAAAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
['Bè']='Bèndèr:BAEANQABCgEIAQABNQABCgQIBAAGAAAAAA==.',
Ca='Cabss:BAAANQAECgUIDQAAAA==.Caelum:BAAANQAECgYIDwAAAA==.Calaban:BAAANQAECgUIEAAAAA==.Caldìr:BAAANQAECgQICQAAAA==.Callazia:BAAANQAECgUICgAAAA==.Callvar:BAAANQADCggJCAAAAA==.Calvandersen:BAAANQADCgQIBAAAAA==.Calyssena:BAABNQAECoEXAAIbAAcKZR4eNAB2AgAbAAcKZR4eNAB2AgAAAA==.Camalyn:BAAANQABCgEIAQAAAA==.Candies:BAABNQAECoEdAAMSAAkKrxptNABoAgASAAcKIyBtNABoAgAXAAQKOBC3wwDcAAAAAA==.Candybars:BAAANQAECggIAQAAAA==.Canthea:BAAANQAECgcIEAAAAA==.Carrot:BAABNQAECoEfAAITAAcKUyICNACtAgATAAcKUyICNACtAgAAAA==.Casaundra:BAEANQADCggIFQAAAA==.Cashmir:BAABNQAECoEhAAMcAAgKMgvlDgCQAQAcAAgK8QrlDgCQAQABAAcKkgUfCwFUAQAAAA==.Castalerus:BAAANQADCggIGAAAAA==.Casterlady:BAAANQADCgEIAQAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgUJDgAAAA==.Catsmurga:BAABNQAECoFFAAIMAAkKaSIHDgCFAwAMAAkKaSIHDgCFAwAAAA==.',
Cc='Cche:BAAANQAECgMIAwAAAA==.Ccogs:BAAANQABCgQIBAABNQABCgQIBQAGAAAAAA==.',
Ce='Celibate:BAABNQAECoEiAAIMAAcKBxy2awAuAgAMAAcKBxy2awAuAgAAAA==.Cellasril:BAAANQADCgUJBQAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Cello:BAAANQAECgMIBQABNQAECgQICAAGAAAAAA==.Celticfrost:BAABNQAECoEhAAMcAAgKPgsTIQDAAAABAAgKDQtcyADQAQAcAAUKhgcTIQDAAAAAAA==.',
Ch='Chaewon:BAAANQADCgYIEwAAAA==.Chasèd:BAAANQAECgQIBAAAAA==.Chuddette:BAAANQAECgMICQAAAA==.Chumashu:BAAANQAFFAEIAQABNQAFFAMIBgAdAA4YAA==.Chïllidan:BAAANQAECggIBwAAAA==.',
Ci='Circlinsmoth:BAAANQABCgMIAwAAAA==.Cirmorte:BAAANQADCggICAAAAA==.Ciroza:BAAANQAECgUIDQAAAA==.',
Cl='Clip:BAAANQAECgQIBAAAAA==.',
Co='Coachzht:BAAANQAECggICAAAAA==.Cogsworthh:BAAANQABCgQIBQAAAA==.Corhrah:BAAANQADCgQIBAABNQAECgkJIwABABQiAA==.Corpserunner:BAABNQAECoEXAAIUAAYKyw/UUwBfAQAUAAYKyw/UUwBfAQAAAA==.',
Cr='Crazytrain:BAAANQAECgIIAQAAAA==.Creekstone:BAAANQAECgQIBwAAAA==.Creep:BAAANQADCgMIAwAAAA==.Cristty:BAAANQADCggIDwAAAA==.Crowul:BAAANQAECgYIBgAAAA==.Crystallyn:BAABNQAECoEhAAIcAAgKMxPxCgDiAQAcAAgKMxPxCgDiAQAAAA==.',
Cu='Cubanmage:BAAANQAECggIEAABNQAECggIHgATALolAA==.Cutter:BAAANQADCgUJBQAAAA==.',
Cy='Cybelis:BAAANQADCgYJBgAAAA==.Cybelliar:BAABNQAECoEcAAMMAAgK5wQqwABJAQAMAAgKcAQqwABJAQAeAAIKaQSNOAA9AAAAAA==.Cynders:BAAANQAECgYIEwAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBQABNQABCgQIBQAGAAAAAA==.',
Da='Dabalt:BAAANQAECgMIAwABNQAECgYIEQAGAAAAAA==.Dadamaxx:BAAANQAECgYIEAAAAA==.Daemlon:BAAANQAECgUIEgAAAA==.Daniel:BAAANQAECgUIBwAAAA==.Darbane:BAAANQAECgMIBAAAAA==.Dargonsevzer:BAAANQAECgcJEgAAAA==.Darkbeárd:BAABNQAECoEaAAIbAAcKnRiTUwD8AQAbAAcKnRiTUwD8AQAAAA==.Daspen:BAACNQAFFIEHAAIfAAMKEBLOAQD+AAAfAAMKEBLOAQD+AAA1AAQKgUgAAh8ACQrcJPcAAM0DAB8ACQrcJPcAAM0DAAAA.Daysalt:BAAANQAECggICQAAAA==.Daßalt:BAAANQAECgYIEQAAAA==.',
De='Deadshotdak:BAAANQAECgYICgABNQAECggIGwAMAEEXAA==.Deathbychaos:BAAANQADCgYIDAAAAA==.Deathcrip:BAAANQADCgUIBQABNQAFFAQICAATAIodAA==.Delonge:BAABNQAFFIEFAAMgAAIK/iFqEgBgAAAhAAEKnCOCMABpAAAgAAEKYSBqEgBgAAAAAA==.Delorand:BAAANQABCggICgAAAA==.Delriel:BAAANQAECgYIEQAAAA==.Demeters:BAAANQADCgUIBQAAAA==.Demetra:BAAANQABCgIIAgAAAA==.Demonfuryx:BAAANQAECgUIBgAAAA==.Demonkeeper:BAAANQADCgYIGAAAAA==.Denaror:BAAANQADCgMJAwAAAA==.Denzai:BAABNQAECoEfAAIEAAgKIhjrDgBQAgAEAAgKIhjrDgBQAgAAAA==.Deshyr:BAABNQAECoEYAAIBAAgKWwTU9QB6AQABAAgKWwTU9QB6AQAAAA==.Despere:BAAANQABCgEIAQAAAA==.Deviant:BAACNQAFFIEKAAMOAAQKdRnOCQANAQAOAAMKBBjOCQANAQAFAAIKoQ/zEgCPAAA1AAQKgSIAAwUACQrBI+oeAF8CAAUABwqfHuoeAF8CAA4ABwoQH4YTAD0CAAAA.Devvy:BAAANQAECgQICAAAAA==.Dewzero:BAAANQAECgEIAQAAAA==.Deyalanis:BAAANQADCggICAAAAA==.',
Dh='Dha:BAABNQAECoEfAAIVAAkK8x6UCQAzAwAVAAkK8x6UCQAzAwAAAA==.',
Di='Diablìta:BAAANQADCggIDQAAAA==.Dingaling:BAAANQAECgUIBQAAAA==.Dirt:BAABNQAECoEuAAIUAAkKoCIABwCQAwAUAAkKoCIABwCQAwAAAA==.Dirtz:BAAANQAECgMIAwABNQAECgkJLgAUAKAiAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dj='Djdeath:BAAANQADCgUICAABNQAECggIEgAGAAAAAA==.',
Dk='Dkdiddy:BAABNQAECoEdAAMaAAgK7BiLRwDTAQAaAAgKLBaLRwDTAQAKAAUKbhkQPwCKAQAAAA==.Dksnow:BAAANQAECgUIBQAAAA==.',
Do='Docnathrius:BAAANQAECgQICQAAAA==.Dogodeath:BAAANQAECgQICQAAAA==.Domago:BAABNQAECoEkAAIhAAkK6hcePwB5AgAhAAkK6hcePwB5AgAAAA==.Dorknight:BAABNQAECoEXAAIJAAcKtAl3YwBCAQAJAAcKtAl3YwBCAQAAAA==.Dotfeardot:BAAANQAECgYIDgAAAA==.Dotsandfear:BAAANQABCgcIBgAAAA==.Dougue:BAACNQAFFIEPAAIOAAUKyRbSBADKAQAOAAUKyRbSBADKAQA1AAQKgSMAAw4ACQrqHW0IAOcCAA4ACQp2HW0IAOcCAAUAAgq+BJN9AF4AAAAA.',
Dp='Dpalm:BAABNQAECoEnAAMHAAkK2x6cDQD8AgAHAAkK2x6cDQD8AgAIAAEKDw+4IwA5AAAAAA==.',
Dr='Dracogelly:BAAANQAECgYIDwAAAA==.Draedio:BAAANQAECgIIAgAAAA==.Dragonarc:BAAANQADCgQIBAAAAA==.Dragonnuts:BAABNQAECoEZAAIiAAgK9hA6HQDbAQAiAAgK9hA6HQDbAQAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Draguula:BAAANQADCgIIAgAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drazelle:BAAANQABCgIIAgAAAA==.Drdeathtron:BAAANQAECgYIDwAAAA==.Drenare:BAAANQADCgEJAQABNQAFFAQICwAMACYjAA==.Drevix:BAABNQAECoEfAAIjAAgK5hD9CgDyAQAjAAgK5hD9CgDyAQAAAA==.Drinkabeer:BAAANQADCgUIBgAAAA==.Drneil:BAAANQADCgMIAwAAAA==.Dromanicus:BAAANQADCggJCAAAAA==.Drovodian:BAAANQAECgUIBQAAAA==.Dru:BAABNQAECoEbAAIMAAgKQRfHcAAhAgAMAAgKQRfHcAAhAgAAAA==.Druidzilla:BAAANQABCgUIBQABNQADCgcIEwAGAAAAAA==.',
Du='Dudaelah:BAAANQADCgYICwAAAA==.Dudeak:BAABNQAECoEYAAIbAAcKfBrhSAAkAgAbAAcKfBrhSAAkAgAAAA==.Dulled:BAAANQADCgUICAABNQAECgQIBgAGAAAAAA==.Dundoh:BAABNQAECoEnAAIYAAkKxx/EJgAQAwAYAAkKxx/EJgAQAwAAAA==.Durimluz:BAAANQADCgIIAgABNQAECggIHAAZAJUaAA==.Durm:BAABNQAECoEXAAIkAAcKqBNcKgDVAQAkAAcKqBNcKgDVAQAAAA==.Durson:BAAANQADCggICAABNQAECgYIEwAGAAAAAA==.Duskknight:BAABNQAECoEdAAMaAAgKahbXPgD9AQAaAAgKqBTXPgD9AQAJAAcKVxYwRgDBAQAAAA==.',
Ea='Earthivan:BAAANQADCgYIDwAAAA==.Earthlight:BAAANQADCgYICwAAAA==.',
Eb='Ebonchillz:BAAANQADCgYICQAAAA==.',
Ed='Edmundo:BAAANQADCggJBAAAAA==.Edwalex:BAAANQADCgEIAQAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eldersmurfh:BAEANQADCgcIBwABNQAECgcIFgACAJcVAA==.Eleeza:BAABNQAECoEgAAMZAAgKGhl2EwBHAgAZAAgKGhl2EwBHAgAYAAEKzAo1gQEuAAAAAA==.Ellephino:BAAANQADCgcIDQABNQAECgUIDQAGAAAAAA==.Elleìgh:BAAANQAECgQIBQABNQAECgkJLwAbAFcVAA==.Elm:BAABNQAECoEbAAQPAAkKWh9QBwBnAgAPAAgKIhtQBwBnAgARAAcKCiAnNgDLAQAVAAIK4QtdVgBnAAAAAA==.Elmzoth:BAACNQAFFIEVAAMHAAUKsSTzAgAaAgAHAAUKsSTzAgAaAgAbAAEKUQ3cKQBUAAA1AAQKgWoAAwcACQraJiYAAAsEAAcACQraJiYAAAsEABsAAgq/JpynAOMAAAE1AAQKCQkbAA8AWh8A.Elmzy:BAAANQADCggICAABNQAECgkJGwAPAFofAA==.Elvanshalee:BAAANQAECgQIDQAAAA==.Elylreith:BAAANQADCgYICAAAAA==.Elysiain:BAAANQAECgUICwAAAA==.',
Em='Eminjangidge:BAAANQAECgQIBAAAAA==.',
En='Enthusiast:BAAANQADCgcIBwAAAA==.Envoshat:BAAANQAECgQIBgAAAA==.',
Er='Erael:BAAANQAECgMIBAAAAA==.Erebseth:BAAANQAECgMIBAAAAA==.Eredeath:BAABNQAECoEhAAIRAAgKKxcJKgAmAgARAAgKKxcJKgAmAgAAAA==.Eremier:BAAANQAECgUIBQAAAA==.',
Es='Esdeäth:BAACNQAFFIEHAAIhAAQKZRMsEgA8AQAhAAQKZRMsEgA8AQA1AAQKgSAAAyEACAr9INw1AJgCACEACAr9INw1AJgCACAAAgqVDXxbAGYAAAAA.Eskiestout:BAAANQAECggIAQAAAA==.Estar:BAABNQAECoEWAAIlAAgKgBLKFQDIAQAlAAgKgBLKFQDIAQAAAA==.Estaslól:BAABNQAECoErAAISAAgKzB2rJwClAgASAAgKzB2rJwClAgAAAA==.Estelars:BAAANQADCgUIBQAAAA==.Esxcanor:BAAANQADCggICAABNQAECggIHwABAK4PAA==.',
Et='Etel:BAAANQAECgQICgAAAA==.Ethos:BAAANQAECgYIBgABNQAECgcIEAAGAAAAAA==.Etrnlrapture:BAAANQAECgYIEgAAAA==.',
Eu='Eulerion:BAABNQAECoEVAAMTAAgKaBfCUABVAgATAAgKaBfCUABVAgAkAAQKARNeRQD7AAAAAA==.Eulkick:BAAANQAECgEIAQABNQAECggIFQATAGgXAA==.Eunomia:BAAANQADCgQIBAAAAA==.',
Ev='Evokingdeath:BAAANQADCgUIBQAAAA==.Evol:BAABNQAECoEeAAITAAgKXB6tLwC8AgATAAgKXB6tLwC8AgAAAA==.Evolooshon:BAAANQADCgIIAgAAAA==.Evrac:BAABNQAECoEZAAMmAAgKxA4PCgDEAQAmAAgKmw0PCgDEAQAOAAQKlQouNwDcAAAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQAECgYIEwAAAA==.Faerysti:BAAANQAECgcIEAAAAA==.Fafafeaf:BAAANQABCgIIAgAAAA==.Fafnir:BAAANQAECgcIDgABNQAECgkJMAARAHUkAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQAECgIIBgAAAA==.',
Fe='Fearinshatt:BAAANQAECgIIAgAAAA==.Fellina:BAAANQADCgUIAwAAAA==.Femaelan:BAEANQADCggIEgABNQADCggIFQAGAAAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQAECgUICAAAAA==.',
Fh='Fhalen:BAABNQAECoEgAAIDAAgKiBAjBwAMAgADAAgKiBAjBwAMAgAAAA==.',
Fi='Fimbik:BAAANQAECgYIDAAAAA==.Fischtya:BAAANQADCgMJAwABNQADCgYIBgAGAAAAAA==.Fishymd:BAEANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQABCgIJAgAGAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Foot:BAAANQAECgQIBgABNQAECgcIHAANAC4SAA==.Forgotskillz:BAAANQAECgUICgAAAA==.Forthelast:BAAANQADCgYIBgAAAA==.Fortunatos:BAAANQAECgUIDAAAAA==.Foxycharsong:BAAANQADCgIIAgAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQAECgQIBwAAAA==.Friendship:BAAANQADCgIIAgABNQAECggIGQAiAPYQAA==.Frstyfyre:BAAANQADCgYIDgAAAA==.',
Fu='Fullmonty:BAAANQAECgUICgAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
['Få']='Fårnsworth:BAEANQABCgQIBAAAAA==.',
Ga='Galdrelyne:BAAANQAECgUICgAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Ganks:BAAANQABCgYIEAABNQAECgYIEgAGAAAAAA==.Gaobot:BAAANQAECgIIBAAAAA==.Garalagon:BAEANQADCggIDAABNQADCggIFQAGAAAAAA==.Gargongo:BAAANQAECgUIBQAAAA==.Garros:BAAANQABCgEIAQAAAA==.',
Gb='Gb:BAABNQAECoETAAQgAAkK4BnZLgADAQAhAAYKnhUWhgCpAQAgAAQKhBLZLgADAQADAAMKvBZGFgC/AAABNQAECgcIFAAHAEgdAA==.',
Gd='Gdi:BAAANQAECgQICgAAAA==.',
Ge='Genetunica:BAAANQADCgUICAAAAA==.Genevieve:BAAANQAECgUICwABNQAECggIJAALADoVAA==.Gerallt:BAABNQAECoEdAAIJAAcKgBdyQADdAQAJAAcKgBdyQADdAQAAAA==.Gerdian:BAAANQAECgUICgAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQAECgYIBgAAAA==.',
Gi='Gigantór:BAABNQAECoEhAAIJAAcK5x6aKgBVAgAJAAcK5x6aKgBVAgAAAA==.Giggtyman:BAAANQAECgYICgAAAA==.Gille:BAABNQAECoEgAAIbAAgK2hSnUQAEAgAbAAgK2hSnUQAEAgAAAA==.',
Go='Goldendrae:BAAANQAECgQICAAAAA==.Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAABNQAECoEeAAITAAgK7w9MZAAiAgATAAgK7w9MZAAiAgAAAA==.Greekie:BAAANQAECgYIDAAAAA==.Grelli:BAAANQADCgEIAQABNQAECgUJBgAGAAAAAA==.Grestu:BAABNQAFFIEIAAIKAAgKDgCxGwAoAAAKAAgKDgCxGwAoAAAAAA==.Gromgor:BAAANQAECgIIAgAAAA==.Grotir:BAAANQADCggIDQAAAA==.Grotznik:BAAANQADCgYIBgAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAABNQAECoEcAAMZAAgKcR6CDQCgAgAZAAgKQh6CDQCgAgAYAAIKFheNOgF/AAAAAA==.Gurenkaina:BAAANQADCgIIAQAAAA==.',
['Gò']='Gòóse:BAABNQAECoEcAAMaAAcKcSOPHgC2AgAaAAcKcSOPHgC2AgAKAAEKYBWQkAA5AAAAAA==.',
Ha='Halogens:BAAANQAECggICAAAAA==.Handmemychi:BAABNQAECoEYAAInAAcKSRucEwAWAgAnAAcKSRucEwAWAgABNQAECgkJJAATAIYkAA==.Handmemygun:BAABNQAECoEkAAMTAAkKhiTcBQCmAwATAAkKhiTcBQCmAwAkAAIKrgpMaQBjAAAAAA==.Hanzdormu:BAACNQAFFIEKAAIiAAQKPhuuCgBPAQAiAAQKPhuuCgBPAQA1AAQKgScABCIACQo4IjcEAGcDACIACQo4IjcEAGcDAAQABAo0D7MoAMYAABAAAgpUIcUUALoAAAAA.Hanzumbra:BAAANQADCggJCAABNQAFFAQICgAiAD4bAA==.Hanzybadger:BAAANQAECgEIAQABNQAFFAQICgAiAD4bAA==.Harbofdeath:BAAANQAECgUIEwAAAA==.Harseesus:BAAANQAECgUIBQAAAA==.Hawktuahh:BAAANQADCgcIDQAAAA==.',
He='Healteamsix:BAAANQAECgUIBQAAAA==.Healzarc:BAAANQADCgQIBAAAAA==.Helgaah:BAAANQAECgEIAQAAAA==.Helioz:BAAANQAECgEIAQAAAA==.Hemogøblin:BAAANQAECgQIDAAAAA==.Hereticas:BAAANQADCgEIAQAAAA==.Herroniden:BAAANQADCgQIBAAAAA==.Hessn:BAABNQAECoEhAAMJAAkKTxY6MwAiAgAJAAkKTxY6MwAiAgAaAAEK8gZ15AAdAAAAAA==.',
Hi='Hixz:BAAANQADCggIDQABNQAECgQIDQAGAAAAAA==.',
Ho='Holypumper:BAAANQADCggIEQAAAA==.Holyrayne:BAAANQAECgYIEwAAAA==.Hottieheals:BAAANQADCgcICAAAAA==.',
Hu='Hubrinaku:BAAANQADCgcIBwAAAA==.Huntardis:BAAANQAECgYIEAAAAA==.Huntterc:BAAANQAECgEIAQAAAA==.Huracan:BAAANQABCgIIAgABNQAECgUIEAAGAAAAAA==.',
Hy='Hyasept:BAAANQAECgQICwAAAA==.Hyavia:BAAANQAECgEIAQAAAA==.Hydraulic:BAABNQAECoEaAAIWAAgK6Ah4FgDVAQAWAAgK6Ah4FgDVAQAAAA==.Hygar:BAAANQADCgMIAwAAAA==.',
Ia='Ialôr:BAABNQAECoEbAAIYAAgK5CTwFgBWAwAYAAgK5CTwFgBWAwAAAA==.',
Ib='Ibz:BAABNQAECoEeAAIOAAgKKSVjAwBnAwAOAAgKKSVjAwBnAwAAAA==.',
Ic='Ichedin:BAAANQADCgUIBQAAAA==.',
Id='Idus:BAAANQADCgYIDAAAAA==.',
Il='Ilectos:BAAANQABCggICwAAAA==.Ilirra:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgEIAQAAAA==.Impishlee:BAAANQAECgIJAgAAAA==.Impmommy:BAAANQAECgQIBgAAAA==.Impowitz:BAAANQAECgQICQAAAA==.',
In='Inabakumori:BAAANQADCggICAABNQAECgkJGwAPAFofAA==.Incestion:BAAANQAECgEIAgAAAA==.',
Ir='Iradeorum:BAABNQAECoEXAAIVAAYKEQugOQBPAQAVAAYKEQugOQBPAQAAAA==.Irishfelocks:BAAANQAECgYIEAAAAA==.',
Is='Isadel:BAAANQADCggIHQAAAA==.Isavedu:BAABNQAECoEjAAMYAAgKdxgvaQAzAgAYAAgKdxgvaQAzAgALAAEKWAMfGAEkAAAAAA==.',
It='Itherael:BAAANQAECgEIAQAAAA==.Ithlord:BAAANQAECgQIBgAAAA==.',
Iv='Ivanbear:BAAANQADCgcIFgAAAA==.Ivannacream:BAAANQAECgIIAgABNQAECgkJJAAlAGAfAA==.Ivansting:BAAANQAECgQIBQAAAA==.Ivanthas:BAAANQADCggIEQAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQAECgEIAQAAAA==.Jahzzy:BAABNQAECoEcAAIYAAgK1hqWWQBgAgAYAAgK1hqWWQBgAgABNQABCgQIBgAGAAAAAA==.Jaiyanaa:BAABNQAECoEhAAIaAAcKMCBMJgCDAgAaAAcKMCBMJgCDAgAAAA==.Jakem:BAAANQABCgIIAgAAAA==.Jaquita:BAAANQAECgYIEAAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Jc='Jclif:BAAANQADCgMIAwAAAA==.Jcliff:BAAANQADCgMIAwAAAA==.',
Je='Jeffglodblum:BAAANQADCgcIDQAAAA==.Jellylicious:BAAANQADCggIEwAAAA==.Jeluljingo:BAAANQAECgcIEAABNQADCggIDgAGAAAAAA==.Jezilla:BAAANQAECgYIEgAAAA==.',
Jh='Jhsua:BAAANQAECgQIBwAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinainala:BAAANQAECgUICwAAAA==.Jinsu:BAAANQADCggIIwAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAUIGAAEAIAmAA==.Jollyreaper:BAAANQAECgQIDwAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Judgernaut:BAAANQADCgQIBAAAAA==.Julauri:BAAANQADCgIIBAAAAA==.Junglejuice:BAAANQADCgcICgAAAA==.Juñior:BAABNQAECoEwAAMRAAkKdSQDCQBcAwARAAkKTSQDCQBcAwAPAAYKYyI6CABGAgAAAA==.',
Jw='Jwrecks:BAAANQAECgUIBQABNQAECgYIDQAGAAAAAA==.',
Ka='Kaelashe:BAAANQAECgUICgAAAA==.Kaelyndrace:BAABNQAECoEjAAIYAAgK8xUebgAmAgAYAAgK8xUebgAmAgAAAA==.Kaeredan:BAAANQADCggIDwAAAA==.Kahuno:BAABNQAECoEYAAIXAAgKURONVwDvAQAXAAgKURONVwDvAQAAAA==.Kaiolucas:BAAANQAECgcIBwABNQAECgQIBAAGAAAAAA==.Kaliam:BAAANQADCgYIBgABNQAFFAIIBQAgAP4hAA==.Kalimyst:BAABNQAECoEhAAIbAAgKCiInFgALAwAbAAgKCiInFgALAwAAAA==.Kalutak:BAABNQAECoEcAAMZAAgKlRoTGAAOAgAZAAgKlRoTGAAOAgAYAAIK9BJpOAGDAAAAAA==.Kamisen:BAAANQAECgEIAQAAAA==.Kappaccino:BAAANQAECgEIAgABNQAFFAMIBgAdAA4YAA==.Karaktzn:BAAANQAECgYIEAAAAA==.Karande:BAAANQADCgcICgAAAA==.Karedon:BAAANQADCgYICQAAAA==.Kasstrah:BAAANQADCgYIFAAAAA==.Kataraz:BAAANQADCgYIFwAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Kea:BAAANQAECgIIBAABNQAECgQICAAGAAAAAA==.Keenforge:BAABNQAECoEnAAMJAAkKgxQZMwAiAgAJAAkKgxQZMwAiAgAKAAIKowSwiABNAAABNQADCgUIBQAGAAAAAA==.Keknein:BAAANQAECgYICwAAAA==.Kellindor:BAAANQADCggICAAAAA==.Kendrà:BAEANQADCgcIDQABNQADCggIFQAGAAAAAA==.Kentaris:BAABNQAECoEgAAIoAAcKkRD/AgDAAQAoAAcKkRD/AgDAAQAAAA==.Keroleaf:BAABNQAECoEWAAINAAYKYRGeMQBZAQANAAYKYRGeMQBZAQAAAA==.Key:BAAANQAECgUIBQAAAA==.',
Kh='Khakkora:BAAANQADCgMIAwABNQAECgQIBgAGAAAAAA==.Khamùl:BAAANQAECgMIAwAAAA==.',
Ki='Kiergadran:BAABNQAECoEZAAIdAAgKexBKJQDJAQAdAAgKexBKJQDJAQAAAA==.Killimanjaro:BAABNQAECoEhAAIeAAcKGR9lCgBxAgAeAAcKGR9lCgBxAgAAAA==.Kind:BAAANQABCgQIAwAAAA==.Kinoclaw:BAAANQAFFAEIAQAAAA==.',
Kl='Klaelune:BAABNQAECoEqAAMHAAkKShcvFACjAgAHAAkKShcvFACjAgAbAAkKwhObNgBrAgAAAA==.',
Kn='Knaring:BAAANQAECgUICAAAAA==.Knocked:BAAANQADCgMIAwABNQAECgYIDwAGAAAAAA==.Knockedw:BAAANQADCgYIBgABNQAECgYIDwAGAAAAAA==.Knowthing:BAABNQAECoEZAAIeAAgKYA/0FgCPAQAeAAgKYA/0FgCPAQAAAA==.',
Ko='Kohola:BAABNQAECoElAAITAAkKciL7IQDyAgATAAkKciL7IQDyAgAAAA==.Kolar:BAAANQADCggIHQAAAA==.Kolby:BAAANQADCggIGQAAAA==.Koldar:BAABNQAECoEWAAIXAAcK4hZtUgACAgAXAAcK4hZtUgACAgAAAA==.Kolfsorr:BAAANQABCggIBwAAAA==.Kookies:BAAANQADCgYIBgAAAA==.',
Kr='Kronvoid:BAAANQADCggJCAAAAA==.Kräckerbyrd:BAAANQADCgYIBgAAAA==.Krîmsön:BAABNQAFFIEGAAIUAAMKxAdoFgDNAAAUAAMKxAdoFgDNAAAAAA==.',
Ku='Kudo:BAABNQAECoEjAAINAAkKABLqHAAhAgANAAkKABLqHAAhAgAAAA==.Kuroi:BAAANQADCggIFwAAAA==.',
Kv='Kvr:BAAANQADCgQJBgABNQAECgQICwAGAAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgYIGAAAAA==.Lanthal:BAAANQADCgcIBwAAAA==.Lararrek:BAAANQAECgYIEwAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAABNQAECoEfAAIBAAgKrg+jqAAQAgABAAgKrg+jqAAQAgAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Lea:BAAANQAECgYIBAAAAA==.Leadfoot:BAABNQAECoEhAAIJAAgKWh0uIQCRAgAJAAgKWh0uIQCRAgAAAA==.Leftd:BAAANQADCgUIBQABNQAECgkJLAAKAHsbAA==.Leia:BAAANQAECgEIAQAAAA==.Lejaa:BAAANQAECgEIAwAAAA==.Lersneaq:BAAANQADCgYIDQAAAA==.Lexidragon:BAAANQADCgYIEQABNQAECgcIDQAGAAAAAA==.',
Li='Lidina:BAAANQAECgQIBAAAAA==.Lifebreak:BAAANQAECgIIAgAAAA==.Lifestream:BAAANQAECgYICwAAAA==.Ligeia:BAAANQAECgUIBQAAAA==.Lightbier:BAAANQAECgMIBQAAAA==.Lightheels:BAABNQAECoEeAAMbAAgKzR4KJgC1AgAbAAgKzR4KJgC1AgAHAAEKHAwcdAAoAAAAAA==.Lightmourne:BAABNQAECoEqAAIZAAgK0h5cCwDEAgAZAAgK0h5cCwDEAgAAAA==.Lilbeep:BAAANQADCgQIBgAAAA==.Liliennia:BAAANQADCggIDQAAAA==.Lilkitz:BAAANQADCgEIAgAAAA==.Liteforged:BAAANQADCgYIDAAAAA==.',
Ll='Llord:BAAANQAECgEIAQAAAA==.',
Lo='Lockgob:BAAANQADCggICAAAAA==.Lolohjeez:BAAANQAECgMIAwAAAA==.Lotionman:BAABNQAECoEoAAITAAgKWCQqFwAmAwATAAgKWCQqFwAmAwAAAA==.Lougi:BAACNQAFFIEGAAMKAAQKCAUzDQC8AAAKAAMKMQYzDQC8AAAaAAEKjwEzIAA6AAA1AAQKgSIABAoACQogGisjAEkCAAoACQogGisjAEkCABoABgp0DcN0AB0BAAkAAQocDTO2AD0AAAAA.Lougii:BAAANQAECgUIBgABNQAFFAQIBgAKAAgFAA==.',
Lt='Ltcrisp:BAABNQAECoEaAAIDAAUKOBeYDQBWAQADAAUKOBeYDQBWAQAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAACNQAFFIEHAAINAAMKdhaHCQD+AAANAAMKdhaHCQD+AAA1AAQKgT0AAw0ACQrPI90BAKwDAA0ACQrPI90BAKwDABQABgpYFDhSAGcBAAAA.Lup:BAAANQADCgYICgAAAA==.',
Ly='Lynaya:BAAANQADCggJCAAAAA==.Lysra:BAAANQADCgQJBAAAAA==.Lysted:BAABNQAECoEjAAMTAAkKYh68IAD4AgATAAkKYh68IAD4AgAkAAQKcw26SADlAAAAAA==.Lytherella:BAABNQAECoEXAAIPAAcKcx0UCABKAgAPAAcKcx0UCABKAgAAAA==.',
['Là']='Lànce:BAAANQAECgQIBAABNQAECgUIGgADADgXAA==.',
['Lô']='Lônghorn:BAABNQAECoEsAAIlAAkKACJCAwBuAwAlAAkKACJCAwBuAwAAAA==.',
Ma='Magecyalien:BAAANQAECgYICAAAAA==.Mahat:BAABNQAECoEZAAIDAAcKIQhBDAB1AQADAAcKIQhBDAB1AQAAAA==.Mahona:BAAANQAECgcIEAAAAA==.Maideejai:BAAANQADCgUJBQAAAA==.Malefíc:BAAANQADCgQIBAAAAA==.Malichai:BAAANQADCgYIBgAAAA==.Maliphos:BAAANQADCggIDQAAAA==.Manado:BAAANQADCggIIAAAAA==.Manapuddin:BAAANQADCgYIBgABNQAECggIHgAbAM0eAA==.Manwax:BAAANQAECgEIAQABNQAFFAUIBgAaAMIRAA==.Marcaine:BAAANQAECgIIAgAAAA==.Margareth:BAAANQAECgUICQAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUICQAGAAAAAA==.Mavverick:BAAANQADCgYIDwAAAA==.Mavverickk:BAAANQAECgUICgAAAA==.Maxime:BAAANQAECgYIEwAAAA==.Mayo:BAABNQAECoEjAAMYAAgKrBB2iQDgAQAYAAgKrBB2iQDgAQALAAIKnQIP/QBHAAAAAA==.',
Mc='Mcdruid:BAAANQAECgMIBwAAAA==.',
Md='Mdiggiddy:BAAANQAECgIIAwABNQAECgQIBwAGAAAAAA==.',
Me='Mechamos:BAAANQADCgYICgAAAA==.Medenut:BAAANQAECgYIEgAAAA==.Mellarr:BAAANQAECgEIAQAAAA==.Menalial:BAAANQADCgYIBgAAAA==.Mergos:BAAANQAECgIIAgAAAA==.Mesmureyes:BAAANQADCgUICwAAAA==.',
Mi='Mid:BAAANQAECgYICwAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Mikeyy:BAAANQAECgIIAwAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQAECgEIAQAAAA==.Miori:BAAANQAECgUIDAAAAA==.Missbless:BAAANQADCggIEAAAAA==.Missti:BAAANQAECgQICQABNQAECggIJAALADoVAA==.Mistletow:BAAANQABCgIIAgAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQAECgQICAAAAA==.Mizarc:BAAANQAECgQIBwAAAA==.Mizzit:BAAANQAECgIIAgAAAA==.',
Mo='Mogorasil:BAAANQAECgQICAABNQAECgYICwAGAAAAAA==.Monkichi:BAABNQAECoEYAAIdAAgK6hGlJQDFAQAdAAgK6hGlJQDFAQAAAA==.Mono:BAAANQAECgcIEgAAAA==.Moopsy:BAAANQAECgIIAgAAAA==.Morganella:BAAANQADCgYICwAAAA==.Morghan:BAABNQAECoEhAAIfAAcK+B59CQB7AgAfAAcK+B59CQB7AgAAAA==.Morgrul:BAAANQAECgQIBgAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAABNQAECoEeAAIBAAcKqxfnqAAPAgABAAcKqxfnqAAPAgAAAA==.Mulo:BAAANQADCgMIAwAAAA==.Muravath:BAAANQABCgQIBAAAAA==.Musicjam:BAAANQADCgUICAAAAA==.',
My='Mysp:BAAANQADCggICAABNQAECgQIBgAGAAAAAA==.',
['Mâ']='Mâtano:BAAANQABCgIIAQAAAA==.',
Na='Nadaht:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Nadessa:BAAANQADCgUIBQABNQAECgUIDgAGAAAAAA==.Nahjii:BAAANQADCgMIAwAAAA==.Nahteew:BAAANQAECgIIAgAAAA==.Naomì:BAAANQADCgYJDQAAAA==.Naruto:BAAANQAECgYIDwAAAA==.Nazurash:BAABNQAECoEgAAMaAAgKBhh5UACoAQAaAAcK8hd5UACoAQAKAAYKmhR5PwCIAQAAAA==.',
Ne='Necros:BAAANQADCgYIDgAAAA==.Nekgahza:BAAANQADCggICAAAAA==.Nelriel:BAAANQABCggIEAAAAA==.Nelyar:BAABNQAECoEhAAIHAAcKLwZEOgAsAQAHAAcKLwZEOgAsAQAAAA==.Neonepie:BAAANQAECgYIEwAAAA==.Neostardust:BAAANQADCgYIBgAAAA==.Nermith:BAAANQADCgUIBQAAAA==.Nettero:BAABNQAECoEjAAIMAAkKQxS4VwBnAgAMAAkKQxS4VwBnAgAAAA==.',
Ni='Nickolasrage:BAAANQAECgUIEwAAAA==.Nightfalls:BAAANQADCgMIAwAAAA==.Niklauss:BAAANQAECgIIAQAAAA==.Nineinchmale:BAAANQAECggICAAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nirazenezar:BAAANQADCggIEQAAAA==.Nisgaa:BAABNQAECoEmAAISAAkKRSVzAQDKAwASAAkKRSVzAQDKAwAAAA==.',
No='Nockedup:BAAANQAECggIEAAAAA==.Noots:BAAANQADCgYIDQAAAA==.Noro:BAEANQAECgYICwABNQAFFAUIDwAkAM8RAA==.Norro:BAECNQAFFIEPAAIkAAUKzxEKCgB5AQAkAAUKzxEKCgB5AQA1AAQKgSkAAyQACQolIIYNAPYCACQACQolIIYNAPYCABMAAQoNC245ATgAAAAA.Norrow:BAECNQAFFIEJAAIkAAUKsRdUCQCIAQAkAAUKsRdUCQCIAQA1AAQKgS0AAiQACQodIFAOAO0CACQACQodIFAOAO0CAAE1AAUUBQgPACQAzxEA.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAABNQAECoEgAAQCAAgKjwZyGQAoAQACAAgK5ANyGQAoAQAdAAcKuwaONwAfAQAnAAMK5ADLQwA5AAAAAA==.',
Ny='Nymeris:BAABNQAECoEXAAIgAAYKfgVJMQD2AAAgAAYKfgVJMQD2AAAAAA==.Nyritha:BAAANQAECgUIEAAAAA==.Nyxanunit:BAABNQAECoEgAAIRAAgKfgWZSABNAQARAAgKfgWZSABNAQAAAA==.',
Og='Oggi:BAAANQAECgEIAQAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQAECgMIBAAAAA==.',
Om='Omau:BAAANQAECgYIDwAAAA==.Omgheroism:BAAANQADCggIDAAAAA==.Omìnous:BAABNQAECoEfAAMhAAkK6BlJUABDAgAhAAgKYxhJUABDAgAgAAIKqRypRACoAAAAAA==.',
On='Oneinall:BAABNQAECoEfAAIJAAkKXRPyNwAIAgAJAAkKXRPyNwAIAgAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Op='Oplaya:BAAANQADCgYIBgABNQAECgkJJQAaANMeAA==.',
Or='Oriyn:BAAANQADCggIEwABNQAECgcIIQAeABkfAA==.Orkar:BAAANQADCgIIAgAAAA==.',
Ov='Overknight:BAAANQAECgQIDwAAAA==.',
Oz='Ozempic:BAABNQAECoEZAAMEAAgKqAr5GACZAQAEAAgKdgr5GACZAQAQAAEKOgbuIAAvAAAAAA==.Ozknife:BAABNQAECoEZAAImAAgKWRzzBACVAgAmAAgKWRzzBACVAgABNQADCgIIAgAGAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQAECgEIAQAAAA==.Padthai:BAAANQAECgcIEQAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQAECgQIBQAAAA==.Papsfear:BAAANQADCgYIDQAAAA==.Paryejah:BAAANQADCgMIAwAAAA==.Payenz:BAAANQADCgQIBAAAAA==.',
Pe='Pease:BAABNQAECoEaAAIlAAcKnR60CwBxAgAlAAcKnR60CwBxAgAAAA==.Peke:BAAANQAECgIIBgAAAA==.Penetrate:BAABNQAECoEsAAIeAAkKqSHSAgBmAwAeAAkKqSHSAgBmAwAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECggIEgAGAAAAAA==.Phoenix:BAABNQAECoEWAAITAAkKzhoAHwAAAwATAAkKzhoAHwAAAwAAAA==.',
Pi='Piped:BAAANQADCgMIAwABNQAECgUIEAAGAAAAAA==.',
Pl='Pluka:BAAANQAECgcIDwAAAA==.',
Pn='Pnub:BAAANQAECgYJEAAAAA==.',
Po='Poet:BAAANQADCgUIBQABNQAFFAIIBQAgAP4hAA==.Polarbear:BAAANQAECgEIAgAAAA==.Pomato:BAAANQAECgYIDgAAAA==.Pookle:BAAANQAECgYIBgAAAA==.',
Pr='Praxitelis:BAAANQADCggIEwAAAA==.Priorsmurfh:BAEANQAECgQICAABNQAECgcIFgACAJcVAA==.Promithia:BAABNQAECoEWAAIBAAkKaxWxcQCEAgABAAkKaxWxcQCEAgAAAA==.Propaladin:BAAANQAECgEIAQAAAA==.Proticia:BAAANQADCgMIAwABNQAECgQIDQAGAAAAAA==.',
Ps='Psychopull:BAAANQAECgEIAQAAAA==.Psydesho:BAAANQADCgUIBgAAAA==.',
Pu='Pumpnectarx:BAAANQAECgQIBAAAAA==.',
Py='Pyriz:BAAANQAECgYICgAAAA==.',
['Pë']='Pëëk:BAAANQAECgYIEgAAAA==.',
Qu='Quiverx:BAABNQAECoEeAAITAAgKuiV2DABpAwATAAgKuiV2DABpAwAAAA==.',
Ra='Rachelmariet:BAABNQAECoEXAAIZAAYKJhueIQCpAQAZAAYKJhueIQCpAQAAAA==.Radiumnight:BAAANQAECgMJAgAAAA==.Raeghar:BAABNQAECoEcAAIMAAkKPx0PPAC/AgAMAAkKPx0PPAC/AgAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Rageon:BAAANQADCgYIDQAAAA==.Raihua:BAAANQADCgUICQAAAA==.Rammpart:BAAANQAECgYIEgAAAA==.Rapak:BAAANQADCggIDwAAAA==.Rapsodii:BAAANQADCgcICAAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rashnu:BAAANQAECggICAAAAA==.Rattleballs:BAAANQAECgcIEgAAAA==.Ravpt:BAEANQAFFAIIAgABNQAFFAMIBgAFAHIXAA==.Ravvs:BAECNQAFFIEGAAIFAAMKcheWCgACAQAFAAMKcheWCgACAQA1AAQKgSIAAwUACQrzH9wOAOwCAAUACQrzH9wOAOwCACYAAgq9EikVAH4AAAAA.',
Re='Rebuff:BAAANQABCgUIAwAAAA==.Refnar:BAACNQAFFIEHAAMgAAMKVRHgDACfAAAgAAIKdw7gDACfAAAhAAEKEhcOMwBSAAA1AAQKgR4ABCEACQrhGP1hABACACEABwp9GP1hABACACAABAqnEZgxAPUAAAMAAQowF5AjAEwAAAAA.Reifle:BAAANQAECgQIBAAAAA==.Reiyuka:BAAANQAECgUIBgAAAA==.Rekonsider:BAACNQAFFIEIAAIMAAQKmQ0KGAAcAQAMAAQKmQ0KGAAcAQA1AAQKgSsAAgwACQrbIGEjABwDAAwACQrbIGEjABwDAAAA.Remielle:BAAANQAECgUICgAAAA==.Renewingfist:BAAANQADCggIDgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAABNQAECoEbAAINAAgKhQ/bJgC6AQANAAgKhQ/bJgC6AQAAAA==.',
Rf='Rff:BAAANQADCgUJBQABNQAFFAQICwAMACYjAA==.',
Rh='Rhadamanthus:BAAANQAECgUICgAAAA==.Rhiddik:BAAANQAECggIBwAAAA==.Rhysänd:BAAANQAECgUICQABNQAFFAMIBwAgAFURAA==.',
Ri='Rikora:BAAANQAECgUIEAAAAA==.Ring:BAAANQADCggIFgAAAA==.Riproyal:BAAANQAECgEIAQAAAA==.Ripwon:BAAANQABCgMIBQAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rocha:BAAANQADCgQIBAAAAA==.Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAABNQAECoEmAAIXAAkKACHgEwA/AwAXAAkKACHgEwA/AwAAAA==.Ronnster:BAAANQAECggIEgAAAA==.Roogy:BAAANQADCggICAABNQAECgUIEQAGAAAAAA==.Rooj:BAAANQAECgcIDwAAAA==.Roojdk:BAAANQAECgQIBQAAAA==.Roojvm:BAAANQAECgUICwAAAA==.Roojvr:BAAANQAECgEIAgAAAA==.Rootevil:BAAANQADCgQIBAAAAA==.Rorkhan:BAAANQABCgYIBwAAAA==.Rovver:BAAANQABCgMIAwAAAA==.Royalet:BAABNQAECoEZAAIiAAcKWxYnHADqAQAiAAcKWxYnHADqAQABNQAECgEIAQAGAAAAAA==.',
Ru='Rubbyy:BAAANQAECgMIAwAAAA==.Ruelemental:BAAANQAECgYIDwAAAA==.Runk:BAAANQADCgYIDgAAAA==.Ruthlee:BAABNQAECoEjAAIUAAkKdCMxCACDAwAUAAkKdCMxCACDAwAAAA==.',
Ry='Ryenwithane:BAABNQAECoEZAAITAAkKNCRLEgBBAwATAAkKNCRLEgBBAwABNQAFFAYIFgACAFYjAA==.Rynella:BAAANQAECgUIBwAAAA==.Ryuven:BAAANQADCgQIBAAAAA==.Ryzix:BAAANQAECgYICwAAAA==.',
['Rì']='Rìcco:BAAANQADCggIAQAAAA==.',
['Ró']='Róscô:BAAANQAECgQICAAAAA==.',
Sa='Saimedin:BAAANQAECgYIEgAAAA==.Salin:BAAANQAECgcIDgAAAA==.Salome:BAABNQAECoEvAAIbAAkKVxVuQgA8AgAbAAkKVxVuQgA8AgAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYICgAAAA==.Sapote:BAAANQADCggIDQAAAA==.Sarric:BAAANQAECgIIAgAAAA==.Sasoo:BAAANQADCgMIAwAAAA==.Sastor:BAAANQAECgYIEgAAAA==.Sasuske:BAAANQADCgQICAAAAA==.Satheist:BAAANQAECggIEAAAAA==.',
Sc='Scaredyet:BAAANQAECgIIAgAAAA==.Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQAECgQIBgAGAAAAAA==.Scute:BAAANQAECgQICAAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQAECgIIAwAAAA==.Seigressa:BAAANQADCgYIDAAAAA==.Seije:BAAANQABCgQIBAAAAA==.Seijepaw:BAAANQADCgQIBAAAAA==.Seijethor:BAAANQADCgcIBwAAAA==.Seinduke:BAAANQAECgQIDQAAAA==.Seitan:BAAANQAECgEIAQAAAA==.Senael:BAAANQADCgEIAQAAAA==.Sesnic:BAABNQAECoEbAAINAAgKnRF1IQDwAQANAAgKnRF1IQDwAQAAAA==.Setierian:BAAANQAECgEIAQAAAA==.Seya:BAAANQABCgIIAgAAAA==.',
Sh='Shadymourne:BAAANQADCgQIBAAAAA==.Shamanablast:BAAANQABCggIDQAAAA==.Shamearthen:BAAANQADCgUIBwAAAA==.Shamrexm:BAAANQAECgYICgAAAA==.Shanegillis:BAAANQAECgYIDwAAAA==.Shashdrkiron:BAAANQAECgQICgAAAA==.Sheer:BAAANQAECgUICQAAAA==.Shenlong:BAAANQAECgYIEQAAAA==.Shidae:BAAANQAECgYIDQAAAA==.Shidaestraza:BAAANQADCggIFgAAAA==.Shintorg:BAABNQAECoEhAAMhAAgKLQXqugAoAQAhAAcKpgXqugAoAQAgAAMKiAToUgB7AAAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgUIEQABNQAECgcIFAAdAO8XAA==.Shocksi:BAABNQAECoEaAAISAAgK2yPjDgA3AwASAAgK2yPjDgA3AwAAAA==.Shrimpkin:BAABNQAECoEaAAIMAAgKth0mQwCoAgAMAAgKth0mQwCoAgAAAA==.Shrimprage:BAAANQADCgQJBAAAAA==.Shàdðw:BAAANQAECgYIBwAAAA==.',
Si='Sidon:BAAANQABCgEIAQAAAA==.Sienna:BAABNQAECoEbAAIkAAcKzgikNwBkAQAkAAcKzgikNwBkAQAAAA==.Sigmardoom:BAACNQAFFIEGAAIjAAMKxRssAQAaAQAjAAMKxRssAQAaAQA1AAQKgSQAAiMACQo0JE4BAH4DACMACQo0JE4BAH4DAAAA.Sinabunch:BAAANQADCgYICAAAAA==.Singion:BAAANQADCggIEwAAAA==.Sini:BAAANQAECgUIDAAAAA==.Sinji:BAAANQADCgIIAgAAAA==.Sivat:BAABNQAECoElAAIUAAkKfxuHGADqAgAUAAkKfxuHGADqAgAAAA==.',
Sk='Skronq:BAAANQADCgYIDgAAAA==.Skyfel:BAAANQAECgUIFQAAAQ==.',
Sl='Slampiece:BAABNQAFFIEKAAIBAAUKexFuGQCFAQABAAUKexFuGQCFAQABNQAFFAcIEwAEAIIZAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slingers:BAAANQADCgYIBgAAAA==.Slymuffin:BAAANQAECgMIBAAAAA==.',
Sm='Smanzerra:BAAANQAECggIEAAAAA==.Smashcaster:BAAANQADCgUIBwABNQAECggIEgAGAAAAAA==.Smerig:BAAANQADCgIIAwAAAA==.Smileycyrus:BAAANQAECggIBAAAAA==.Smúrph:BAAANQAECgQJCAAAAA==.',
Sn='Snafueight:BAAANQADCgQIBAAAAA==.Snafumage:BAAANQADCgEJAQAAAA==.Snaptime:BAABNQAECoEfAAIoAAgKOR/9AADeAgAoAAgKOR/9AADeAgAAAA==.Snikrmydodle:BAAANQADCggICAABNQAECgkJIwAaAOUhAA==.Snowblade:BAAANQADCgEIAQAAAA==.Snowshamy:BAAANQAECggIAwAAAA==.',
So='Softgrl:BAABNQAECoEkAAIlAAkKYB+iBAA1AwAlAAkKYB+iBAA1AwAAAA==.Solarcorona:BAAANQAECgUIDwAAAA==.Solenne:BAABNQAECoEkAAILAAgKOhUcSgAgAgALAAgKOhUcSgAgAgAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQAECgQIBwAAAA==.Soulhacker:BAAANQAECggIAgAAAA==.Sovereignt:BAAANQAECgUIBQAAAA==.',
Sp='Spaghetti:BAAANQADCgMIAwABNQAFFAMIBwAgAFURAA==.Sparechange:BAAANQAECgIIAwAAAA==.Spinachio:BAAANQAECgUIEgAAAA==.Spiro:BAABNQAECoEZAAIEAAgKhwt2FwCxAQAEAAgKhwt2FwCxAQAAAA==.Spártacus:BAAANQAECgcIDQAAAA==.',
Sq='Squishypart:BAAANQADCgQIBAAAAA==.',
Ss='Ssargeras:BAAANQABCgYICAAAAA==.',
St='Stalkér:BAABNQAECoEmAAIRAAkKPh8AEAAJAwARAAkKPh8AEAAJAwAAAA==.Steeltemplar:BAABNQAECoEsAAILAAkKphGyRwApAgALAAkKphGyRwApAgAAAA==.Stefanee:BAABNQAECoEjAAINAAgKQR8IDgDUAgANAAgKQR8IDgDUAgAAAA==.Stisti:BAABNQAECoEYAAIJAAcKThffRgC+AQAJAAcKThffRgC+AQAAAA==.Stoneclaw:BAAANQADCgYIDAAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwABNQAECgQICwAGAAAAAA==.Stormwrath:BAAANQAECgIIAgABNQAECgQIDQAGAAAAAA==.Stown:BAAANQADCgEIAQAAAA==.Strawngarm:BAAANQAECgIIAgABNQAFFAYIEAAKAC0hAA==.Styxdraco:BAAANQADCgYIDgAAAA==.',
Su='Subvert:BAAANQAECgMIBAABNQAFFAUIDwAMAJEfAA==.Succiboi:BAABNQAECoEZAAQgAAgK4BbTIQBXAQAgAAUKsBTTIQBXAQAhAAQKxRa+wQAaAQADAAEKiRKvJABHAAAAAA==.Sugarplum:BAAANQADCgMIAwAAAA==.Sugastank:BAAANQADCgYIFgAAAA==.Sugreeva:BAAANQAECgYIEQAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Supplement:BAABNQAECoEhAAIHAAgKyBdsHQAxAgAHAAgKyBdsHQAxAgAAAA==.Surtain:BAAANQAECgIIAgABNQAFFAUIDwAMAJEfAA==.Sustained:BAAANQAECgcICwABNQAFFAUIDwAMAJEfAA==.Susts:BAACNQAFFIEPAAIMAAUKkR9UCgDaAQAMAAUKkR9UCgDaAQA1AAQKgR0AAwwACQrqJKMZAEYDAAwACQrqJKMZAEYDACMAAQqEIe4lAFwAAAAA.',
Sw='Sweetluke:BAAANQADCgIIAgAAAA==.Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQAECgYIEgAAAA==.',
Sy='Synari:BAAANQAECgUICgAAAA==.Sync:BAAANQAECgQIDQAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAABNQAECoEeAAMMAAkKPSJNOwDCAgAMAAgKxyNNOwDCAgAeAAMKdRxtJQDnAAAAAA==.Taggis:BAABNQAECoEjAAMBAAkKFCKBdgB7AgABAAcKPCKBdgB7AgAcAAMK3R9sGgD3AAAAAA==.Tahane:BAAANQADCgIIAgAAAA==.Talalana:BAAANQADCgYIBgAAAA==.Tallwar:BAABNQAECoEhAAIMAAcKlgn3rQB8AQAMAAcKlgn3rQB8AQAAAA==.Tansero:BAACNQAFFIEFAAIiAAMKcBXVDQDxAAAiAAMKcBXVDQDxAAA1AAQKgSwAAiIACQqgHoAKAOwCACIACQqgHoAKAOwCAAAA.Tarklyn:BAAANQAECgUICQAAAA==.Tarotina:BAAANQAECgQICQAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQAECgYIEQAAAA==.Telriel:BAAANQAECgEIAQAAAA==.Terrabrew:BAABNQAECoEcAAMdAAgKYhzbFgBtAgAdAAgKYhzbFgBtAgACAAEK8QF7LwAlAAAAAA==.Teseban:BAAANQAECgQIBAAAAA==.',
Th='Thaeron:BAABNQAECoEwAAIRAAkKiRtuGAC2AgARAAkKiRtuGAC2AgAAAA==.Thakar:BAABNQAECoEZAAIXAAgKoh+VKAC9AgAXAAgKoh+VKAC9AgAAAA==.Thedizz:BAAANQABCgQJBAAAAA==.Thelana:BAAANQABCgIIAgAAAA==.Themayo:BAABNQAECoEUAAMdAAcK7xdJIQD0AQAdAAcK7xdJIQD0AQACAAMKqRSaIQCpAAAAAA==.Theonidus:BAAANQAECggICQAAAA==.Thragrom:BAABNQAECoElAAMaAAkK0x5uFAD/AgAaAAkK0x5uFAD/AgAKAAMKlAtHdQCIAAAAAA==.Threedayvic:BAAANQAECgUIDgAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.Thîïcc:BAAANQAECgQJCQABNQAECgUJDgAGAAAAAA==.',
Ti='Tickl:BAAANQADCgYIFAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQAECgYIEAAAAA==.Tiktokthot:BAAANQAECgYICQAAAA==.Tilila:BAAANQADCgQIBAAAAA==.Timojen:BAAANQADCgcIDwAAAA==.',
To='Toastman:BAAANQADCgYICwAAAA==.Toastmysoul:BAAANQADCgIIAgAAAA==.Toetummy:BAAANQADCggIDAAAAA==.Tokkz:BAAANQAFFAEIAQAAAA==.Tonysparks:BAAANQADCggIDAAAAA==.Toracina:BAAANQAECgYIEQAAAA==.Totalshocker:BAAANQADCgMIAwAAAA==.Tougyu:BAAANQAECgYJDwAAAA==.',
Tr='Trakyr:BAAANQAECgQICQAAAA==.Treebean:BAAANQADCgcJDQABNQAECgkJGQASAJsYAA==.Treppenwitz:BAAANQADCgUIBQABNQAECgcIGAAXAN8TAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQAECgIIAgAAAA==.Troodon:BAAANQAECgEIAQAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCggIFgAAAA==.Tríke:BAAANQAECgUICQAAAA==.Trùk:BAAANQADCgYIBgAAAA==.',
Tu='Tulurakuq:BAAANQAECgUJBgAAAA==.Tuurok:BAAANQAECgQICQAAAA==.',
Tw='Twelvepak:BAAANQADCgMIAwAAAA==.',
Un='Uncledigem:BAAANQABCgMIAwABNQADCgcIEwAGAAAAAA==.Unstable:BAAANQAECgQIBwAAAA==.',
Ur='Urnirus:BAABNQAECoEXAAMNAAcKHxZJLgBzAQANAAYKeRNJLgBzAQAfAAEKAAsLNgA3AAAAAA==.',
Uv='Uvvu:BAAANQAECgcICAAAAA==.',
Va='Vampnor:BAABNQAECoEaAAITAAYKhCXaOwCTAgATAAYKhCXaOwCTAgAAAA==.Vanhelzing:BAAANQADCggIHQAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQAECgQIBAAAAA==.Varinna:BAAANQADCgUIBQAAAA==.Varlaeus:BAABNQAECoEoAAIMAAgKlRLAbwAjAgAMAAgKlRLAbwAjAgAAAA==.Varlais:BAABNQAECoEjAAIPAAgKMR8xBQC2AgAPAAgKMR8xBQC2AgABNQAECggIKAAMAJUSAA==.',
Ve='Veachkidd:BAAANQAECgYJCgAAAA==.Velazurin:BAAANQADCgMIBAAAAA==.Veledora:BAAANQAECgUIDQAAAA==.Velidnissara:BAABNQAECoEUAAIMAAQKHgLOFAF2AAAMAAQKHgLOFAF2AAAAAA==.Velkoz:BAAANQAECgEIBQAAAA==.Vellean:BAAANQADCggJCAAAAA==.Velsa:BAAANQAECgUICQABNQAECgUIEAAGAAAAAA==.Venat:BAAANQAECgQIBgAAAA==.Vensa:BAAANQADCgQJBAAAAA==.Vex:BAAANQAECgMIAwAAAA==.',
Vi='Vissaia:BAABNQAECoEXAAMLAAcKYRrqSgAdAgALAAcKYRrqSgAdAgAYAAEKUwZ/hwErAAAAAA==.',
Vo='Volacious:BAAANQADCgUIEgAAAA==.Voodou:BAAANQADCgYIBgAAAA==.Vordo:BAAANQADCgYIDAAAAA==.Vorr:BAAANQADCgQIBAAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEIAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Warhard:BAAANQADCgMIAwAAAA==.Warlockkink:BAAANQAECgUIBgAAAA==.Warre:BAAANQADCgcIBwAAAA==.Washlunk:BAAANQAECgYIEgAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAABNQAECoEzAAMSAAkKjR/7FQAFAwASAAkKjR/7FQAFAwAXAAUK7htBdwCMAQAAAA==.Waxyness:BAAANQADCgUIBgAAAA==.',
Wh='Wharph:BAABNQAECoEcAAINAAcKLhI2KgCaAQANAAcKLhI2KgCaAQAAAA==.Whitedahlia:BAAANQAECgIIAgAAAA==.Whitepyre:BAAANQAECggJEAABNQAFFAUIGAAEAIAmAA==.Wholadin:BAAANQAECgQIBAAAAA==.Whome:BAAANQADCgYIDgAAAA==.',
Wi='Wilmarth:BAAANQAECgUIBwAAAA==.Winchèster:BAAANQAECgQICQABNQAECgUIGgADADgXAA==.Windbreaker:BAAANQAECgQIBAAAAA==.',
Wo='Wolldays:BAAANQADCgcIBwABNQAECgQIBAAGAAAAAA==.Wollmane:BAAANQADCggIDAABNQAECgQIBAAGAAAAAA==.Wongo:BAAANQADCggICAABNQAFFAcIFgAdACAeAA==.Woolybugger:BAAANQAECgQIBQAAAA==.',
Wr='Wråth:BAAANQAECgYIDQAAAA==.',
['Wì']='Wìndrush:BAAANQAECgQIBAAAAA==.',
Xa='Xalashock:BAAANQADCggJCAAAAA==.',
Xe='Xeleci:BAABNQAECoEjAAIMAAgKNx2ZSwCMAgAMAAgKNx2ZSwCMAgAAAA==.',
Ya='Yamon:BAABNQAECoEXAAIXAAcKDBVDWQDpAQAXAAcKDBVDWQDpAQAAAA==.Yamsees:BAAANQAECgUIDwAAAA==.Yangduke:BAAANQADCggICAABNQAECgQIDQAGAAAAAA==.Yardsnack:BAAANQADCgQIBgAAAA==.Yashipha:BAAANQADCgYIDAAAAA==.',
Yb='Ybnxdolo:BAAANQADCgcIEwAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Ye='Yevven:BAAANQADCgYICwAAAA==.',
Yu='Yulmegerth:BAAANQADCggIKAAAAA==.Yummieyum:BAAANQADCggIDAAAAA==.Yurthong:BAAANQAECgQIBAAAAA==.',
['Yô']='Yôô:BAAANQAECgIIAgAAAA==.',
Za='Zairy:BAAANQADCggICAABNQAECggIHgAOACklAA==.Zarcise:BAAANQAECgUIBQAAAA==.Zart:BAAANQAECgUIEAAAAA==.',
Ze='Zedrolor:BAACNQAFFIEIAAMjAAQKUBPgAQDEAAAMAAQKiQ+uFgAtAQAjAAIKmiLgAQDEAAA1AAQKgSwAAyMACQr9I5sBAG4DACMACQoJI5sBAG4DAAwABQq0ITKHAOQBAAAA.Zekar:BAAANQAECgQIBQAAAA==.Zenful:BAAANQADCgMIAwAAAA==.Zenithcia:BAABNQAECoEaAAIJAAcKixMEUACUAQAJAAcKixMEUACUAQAAAA==.Zeoma:BAAANQAECgEIAQAAAA==.Zerafìn:BAABNQAECoEjAAIBAAkKrRDIkQBAAgABAAkKrRDIkQBAAgAAAA==.Zerenitynow:BAABNQAECoEiAAMdAAcKhBqlHQAbAgAdAAcKhBqlHQAbAgAnAAIK4QfQPwBPAAAAAA==.Zereora:BAAANQADCgIJAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEIAgAAAA==.Zheyan:BAAANQAECgMIAwAAAA==.',
Zi='Zilyn:BAACNQAFFIEJAAMSAAUKfQ0OCwB6AQASAAUKfQ0OCwB6AQAWAAEKVgAQCAAuAAA1AAQKgSsAAhIACQpZEpxRAPIBABIACQpZEpxRAPIBAAAA.',
Zo='Zookeeper:BAAANQADCgUIBwAAAA==.',
Zr='Zraidn:BAABNQAECoEXAAIFAAcK5h50GwB4AgAFAAcK5h50GwB4AgAAAA==.Zromaverick:BAAANQADCgEIAQAAAA==.',
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
