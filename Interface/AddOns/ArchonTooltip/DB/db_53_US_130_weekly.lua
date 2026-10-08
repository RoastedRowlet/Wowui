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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Hunter-Marksmanship','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Druid-Restoration','Druid-Balance','Paladin-Protection','Priest-Holy','Monk-Mistweaver','Paladin-Retribution','Evoker-Preservation','Monk-Windwalker','Evoker-Devastation','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Paladin-Holy','Warrior-Protection','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Survival','Druid-Feral','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Vengeance','DeathKnight-Frost','Shaman-Enhancement',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abonde:BAAANQAECgQIBgAAAA==.Abraxes:BAAANQAECgUIDwAAAA==.',
Ac='Acidemon:BAAANQAECgYIEAAAAA==.',
Ad='Adalaide:BAABNQAECoEXAAMBAAYKQgyYpABbAQABAAYKQgyYpABbAQACAAIKZAbMYABYAAAAAA==.Adannis:BAAANQAECgIIAgABNQAECgYIEAADAAAAAA==.Adelane:BAAANQAECgEIAQABNQAECgUIEQADAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQAECgUIEQAAAA==.Aethas:BAAANQADCgYICAAAAA==.',
Af='Affective:BAABNQAECoEjAAIEAAkKGhtsEQDIAgAEAAkKGhtsEQDIAgABNQAFFAYIEgAFANwSAA==.Afkk:BAAANQADCggIBAAAAA==.',
Ah='Ahuramazda:BAAANQAFFAIIAwAAAA==.',
Ai='Aidard:BAAANQABCggIDwAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCggIJAAAAA==.',
Ak='Akio:BAABNQAECoEkAAIGAAgK6R0HMgC0AgAGAAgK6R0HMgC0AgAAAA==.',
Al='Aldarya:BAAANQAECgUICQAAAA==.Alisara:BAABNQAECoEtAAIGAAkKnyXnAwDAAwAGAAkKnyXnAwDAAwAAAA==.Alish:BAAANQADCggIFwAAAA==.Allexx:BAABNQAECoEhAAIGAAgKNhlXSQBqAgAGAAgKNhlXSQBqAgAAAA==.Allyssel:BAACNQAFFIEWAAIHAAYKNx0FAwAxAgAHAAYKNx0FAwAxAgA1AAQKgSsAAgcACQqwJmUBAOEDAAcACQqwJmUBAOEDAAAA.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAACNQAFFIEJAAIIAAUKXBl7BQCuAQAIAAUKXBl7BQCuAQA1AAQKgRsAAwgACQooHVoUAKECAAgACQooHVoUAKECAAkAAwoZDigXAKAAAAAA.Amazinggrace:BAABNQAECoEdAAMFAAcK7Q9dYQBlAQAFAAcKew1dYQBlAQAKAAYKVQ8KagAnAQAAAA==.Amentiu:BAAANQADCgUICAABNQAECgYIGQAHAPYGAA==.Ammathendis:BAAANQADCgQIBAABNQAECgUICwADAAAAAA==.Ammiel:BAAANQADCgEIAQABNQAFFAMIBQAKACkSAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQAECgYICwAAAA==.Angeal:BAAANQAECgYIEwAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAABNQAECoEeAAMLAAcKYQ9vdgCOAQALAAcKYQ9vdgCOAQAMAAUK/BZ2ggBXAQAAAA==.Annamei:BAAANQAECgUIEgAAAA==.',
Ao='Aoife:BAAANQAECgYIEgAAAA==.Aorina:BAABNQAECoEmAAINAAgKgRqacgCCAgANAAgKgRqacgCCAgAAAA==.',
Ar='Arazalor:BAABNQAECoEjAAMOAAgKbgyYKwCMAQAOAAgKbgyYKwCMAQAPAAUKjwMQfgCqAAAAAA==.Arcangel:BAACNQAFFIEJAAIOAAUKDBliBADAAQAOAAUKDBliBADAAQA1AAQKgSAAAw4ACQqwJOwDAHkDAA4ACQqwJOwDAHkDAA8AAQr5GQWZAEUAAAAA.Arrash:BAAANQADCgYICwABNQAECgcIEAADAAAAAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAABNQAECoEeAAILAAcK9SGvKwCsAgALAAcK9SGvKwCsAgAAAA==.Arysa:BAAANQADCgUIBQAAAA==.',
As='Ashara:BAABNQAECoEhAAIQAAgK9RMwHwDBAQAQAAgK9RMwHwDBAQAAAA==.Ashenrain:BAAANQAECgQIBQAAAA==.Ashvia:BAAANQAECgMIBQAAAA==.Aspiration:BAAANQABCggICwAAAA==.',
At='Atheren:BAABNQAECoEeAAILAAgKbxW6SQAjAgALAAgKbxW6SQAjAgAAAA==.Athshu:BAAANQADCgcIBwAAAA==.Atulan:BAAANQAECgcIEAAAAA==.',
Au='Auntiemimi:BAAANQAECgQICwAAAA==.',
Av='Avalina:BAABNQAECoEZAAIRAAcKWxQdXQDaAQARAAcKWxQdXQDaAQABNQAFFAYIDwACAH4hAA==.Avannar:BAAANQADCgcIHAAAAA==.Avelyn:BAAANQAECggICQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQAECgUIBgAAAA==.',
Ay='Ayani:BAABNQAECoEZAAMIAAgKHQzUKgCoAQAIAAgKHQzUKgCoAQARAAUKZQ2snwD6AAAAAA==.',
Az='Azrine:BAAANQAECgYIBgAAAA==.',
Ba='Babymanowood:BAAANQADCgcJBwAAAA==.Baddattitude:BAAANQADCggIFAABNQAECgMIBAADAAAAAA==.Baddkharma:BAAANQAECgMIBAAAAA==.Badras:BAAANQAECgYIEgAAAA==.Bagelz:BAACNQAFFIEJAAISAAUK3BnuAgDDAQASAAUK3BnuAgDDAQA1AAQKgRsAAhIACQpBIVwIAO4CABIACQpBIVwIAO4CAAAA.Balforyn:BAAANQAECgUIBQAAAA==.Bathomula:BAAANQAECgYIEwAAAA==.Bayla:BAAANQADCgUIBQABNQAFFAYIGQASADAXAA==.Bazza:BAAANQADCgYIBgABNQAECgUIEQADAAAAAA==.Bazzwar:BAAANQADCggICwABNQAECgUIEQADAAAAAA==.',
Be='Beric:BAAANQAFFAIIAwAAAA==.Betadine:BAAANQAECgUIBQAAAA==.Bexy:BAABNQAECoEfAAIMAAkKyha6OQBQAgAMAAkKyha6OQBQAgAAAA==.',
Bl='Blade:BAABNQAECoEjAAIHAAgKjAd4QQB9AQAHAAgKjAd4QQB9AQAAAA==.',
Bo='Boldan:BAAANQADCgIIAwAAAA==.Boohaha:BAABNQAECoEfAAIMAAgKwhzeKwCPAgAMAAgKwhzeKwCPAgAAAA==.Booze:BAAANQAECgMIAwABNQAECggIAwADAAAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAABNQAECoEdAAITAAcKFSKSWABjAgATAAcKFSKSWABjAgAAAA==.Bowmistress:BAAANQAECgEIAQAAAA==.',
Br='Brightwing:BAACNQAFFIEFAAIUAAMKww+fDgDbAAAUAAMKww+fDgDbAAA1AAQKgSwAAhQACQoAH/UHABgDABQACQoAH/UHABgDAAAA.Brigorath:BAAANQAECgQIBQAAAA==.Brokenarro:BAAANQAECgIIAgAAAA==.',
Bu='Bubblebae:BAAANQAECgQICwABNQAECgcIFAALAHceAA==.Bullshivek:BAAANQAECgYIEQAAAA==.',
Ca='Caale:BAAANQAECgYIEQAAAA==.Caecus:BAAANQAECgYIEQAAAA==.Callsaul:BAEANQAECgMICAAAAA==.Casmus:BAAANQADCgYIBgABNQAECgYIEgADAAAAAA==.Caylissa:BAAANQAECgQICQAAAA==.',
Ce='Celryth:BAAANQADCgYIBwAAAA==.Cenvoked:BAABNQAECoEaAAIUAAgKWA6aHgDIAQAUAAgKWA6aHgDIAQAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgUJDgABNQAECgYIDQADAAAAAA==.Charlicious:BAAANQAECgYIDQAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgYIDQADAAAAAA==.Charticulous:BAAANQADCgUIBQABNQAECgYIDQADAAAAAA==.Cheylia:BAAANQAECgYIDAAAAA==.Chijoku:BAABNQAECoErAAIPAAkKsA7NNgANAgAPAAkKsA7NNgANAgAAAA==.Chimster:BAABNQAECoEWAAIGAAYKgR4SbAAOAgAGAAYKgR4SbAAOAgAAAA==.Chimydakilla:BAAANQAECgIIAgABNQAECgYIFgAGAIEeAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggJCAAAAA==.',
Co='Corvò:BAAANQAECgYIEwAAAA==.',
Cr='Craeus:BAABNQAECoEdAAIMAAgKux2tJwCkAgAMAAgKux2tJwCkAgAAAA==.Cralk:BAAANQAECgcIDgABNQAECgkJGgATAKcbAA==.Cranked:BAAANQAECgcIDQABNQAFFAMIBQAVALgXAA==.Crine:BAAANQAECgEIAQABNQAECgkJIQAWAMwSAA==.',
Cy='Cyonarah:BAAANQAECgUICwAAAA==.',
Da='Darem:BAAANQAECgcICQAAAA==.',
De='Deadcenter:BAAANQAECgEIAQAAAA==.Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgUIDAAAAA==.Deidra:BAAANQAECgIIAwAAAA==.Deigh:BAAANQADCggIBwAAAA==.Dek:BAAANQAECgUIBQAAAA==.Demons:BAAANQABCggIEQAAAA==.Devilette:BAAANQADCgQIBQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAABNQAECoEnAAIGAAkKBCMxCQCEAwAGAAkKBCMxCQCEAwAAAA==.Diggi:BAAANQAECgYIDwAAAA==.Diosa:BAABNQAECoEkAAICAAgKFhTzCgA+AgACAAgKFhTzCgA+AgAAAA==.Divinekat:BAAANQAECgUICAAAAA==.Dizza:BAAANQAECgIIAwAAAA==.',
Dk='Dkagon:BAAANQAECgcIEwAAAA==.',
Do='Docholiday:BAAANQAECgUIBQAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQAECgYIDwAAAA==.Dooderonomy:BAAANQAECgYIEQAAAA==.Doria:BAAANQADCgQIBAAAAA==.',
Dr='Dragaan:BAAANQAECgcIEgAAAA==.Dragonbait:BAABNQAECoFGAAITAAkK4iHhFgBWAwATAAkK4iHhFgBWAwAAAA==.Dragonoodles:BAAANQAECgYIEQAAAA==.Dragonzbane:BAAANQAECgYIEwAAAA==.Dranosh:BAAANQADCgUIBQABNQAECgQIBAADAAAAAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAwAAAA==.Drekthanas:BAAANQAECgIIAgABNQAECgIIAwADAAAAAA==.Drenea:BAAANQADCgcIGQAAAA==.Drimlek:BAAANQADCgEIAQAAAA==.Drin:BAAANQAECgYIEQAAAA==.',
Du='Duplicitous:BAAANQADCgcJBwAAAA==.',
Dy='Dyriana:BAAANQADCgcIFgAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAABNQAECoEbAAIXAAcKJREqEwCRAQAXAAcKJREqEwCRAQAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQAECgUIEQAAAA==.Ellewoods:BAAANQADCggIDwABNQAECgMIAwADAAAAAA==.Eloise:BAAANQAECgYIBgAAAA==.Eltria:BAACNQAFFIEJAAINAAUKfxVYFQCkAQANAAUKfxVYFQCkAQA1AAQKgRsAAg0ACQpvIhI+APwCAA0ACQpvIhI+APwCAAAA.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAABNQAECoEdAAIRAAgKdxu0OABjAgARAAgKdxu0OABjAgAAAA==.',
Er='Eric:BAAANQAECgIIAgABNQAECgcIGwAYAI0cAA==.Erid:BAAANQADCgcIBwAAAA==.Erverlyn:BAAANQADCgQIBAAAAA==.',
Es='Essential:BAACNQAFFIEJAAIZAAUKSwnHAAB2AQAZAAUKSwnHAAB2AQA1AAQKgRsAAhkACQqNIM0DAOoCABkACQqNIM0DAOoCAAAA.',
Ex='Exces:BAAANQADCgUIBQAAAA==.Exicor:BAAANQAECgIIAgABNQAECggIIAANAJIbAA==.',
Ez='Ezalth:BAAANQADCggIHgAAAA==.Ezz:BAAANQADCggJDwAAAA==.',
Fa='Fachzile:BAAANQADCgQIBAAAAA==.Faden:BAAANQAECgcIEgABNQAFFAMIBQAVALgXAA==.Faenara:BAABNQAECoEjAAMaAAgKBRu9MACHAgAaAAgKBRu9MACHAgATAAcKvBFJnACzAQAAAA==.Falafelguy:BAABNQAECoEoAAINAAgK9h4ncgCDAgANAAgK9h4ncgCDAgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwABNQAECgMIBQADAAAAAA==.Faruqq:BAABNQAECoEhAAMbAAgKFx0pCQCQAgAbAAgKFx0pCQCQAgAYAAgK6QgzogCcAQAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECggIKAANAPYeAA==.Felartamiel:BAAANQADCgcIGgAAAA==.Felkieler:BAAANQADCgYICAABNQAECgQIBQADAAAAAA==.Fey:BAAANQAECgUICgAAAA==.',
Fi='Firêstorm:BAAANQAECggIBgAAAA==.Fishron:BAAANQAECgYIEQAAAA==.',
Fl='Flaz:BAACNQAFFIEFAAIPAAIKvhvxGACpAAAPAAIKvhvxGACpAAA1AAQKgR4AAg8ACQpQGlYmAH8CAA8ACQpQGlYmAH8CAAAA.Fleury:BAAANQABCgUIBAAAAA==.',
Fo='Forestspirit:BAAANQAECgcIDgAAAA==.Fourneau:BAAANQADCggJCAABNQAECggIJAAWAAUWAA==.',
Fr='Frawda:BAABNQAECoEWAAMYAAcKKgj7tQBmAQAYAAcKKgj7tQBmAQAZAAQKNQXVHwCWAAAAAA==.',
Fu='Fusillidari:BAAANQAECgUIDQABNQAECgYIEQADAAAAAA==.Fuzzy:BAAANQAECggIAgAAAA==.',
Ga='Galaxyman:BAAANQADCggIEQAAAA==.Garlone:BAAANQABCgcIBwAAAA==.',
Ge='Geist:BAACNQAFFIEIAAMTAAUKWxEbCQCNAQATAAUKWxEbCQCNAQAQAAEKGgYAEAAyAAA1AAQKgRkAAhMACQqTJHkqAAADABMACQqTJHkqAAADAAAA.Geraith:BAACNQAFFIEIAAIKAAUKrhNuDABeAQAKAAUKrhNuDABeAQA1AAQKgRgAAgoACQrtH0AbALwCAAoACQrtH0AbALwCAAAA.Gerios:BAABNQAECoEiAAIGAAgKLxslOQCcAgAGAAgKLxslOQCcAgAAAA==.Getafix:BAAANQADCgQIBAAAAA==.Getmadbro:BAAANQAECgMIAwAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQAECgYICAAAAA==.',
Gl='Glacier:BAAANQABCgYICAAAAA==.Glaedyr:BAAANQADCgEIAQABNQAECggIHgASAEIUAA==.Glendra:BAABNQAECoEhAAIQAAgK9hZRGwDpAQAQAAgK9hZRGwDpAQAAAA==.Glorificus:BAAANQADCggJDgAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAABNQAECoEZAAMWAAgKRAlrHgBOAQAWAAcKyAhrHgBOAQAcAAUKCAqsEQDpAAAAAA==.Greensleeves:BAAANQADCgcIGAAAAA==.Gregoriusz:BAABNQAECoExAAIEAAgKAR7gEgC3AgAEAAgKAR7gEgC3AgAAAA==.Greygull:BAAANQAECgQICAAAAA==.Grimfrost:BAAANQABCgIIAgAAAA==.Grunin:BAAANQADCggIDwAAAA==.',
Gu='Guinness:BAABNQAECoEYAAITAAcK4wzFswB+AQATAAcK4wzFswB+AQAAAA==.Guntank:BAABNQAECoEkAAMYAAgKvxV+egAGAgAYAAgK6RN+egAGAgAZAAUKcBIlFAA2AQAAAA==.',
Ha='Halistarr:BAAANQADCgIIAgAAAA==.Hategnomer:BAAANQADCgcIGQAAAA==.Havenfell:BAAANQAECgcIEgAAAA==.Hawkfist:BAABNQAECoEhAAIGAAgKzBVUVgBGAgAGAAgKzBVUVgBGAgAAAA==.',
He='Hercules:BAACNQAFFIEJAAIFAAUKLAzUCgA7AQAFAAUKLAzUCgA7AQA1AAQKgTwAAgUACQqdJE4FAJUDAAUACQqdJE4FAJUDAAAA.Hervo:BAAANQAECgIIAgAAAA==.Herzagon:BAAANQAECgIIAgAAAA==.',
Hi='Hierodoulos:BAABNQAECoEkAAIOAAgKlyX+BABkAwAOAAgKlyX+BABkAwAAAA==.',
Ho='Holykat:BAAANQADCggICwABNQAECgUICAADAAAAAA==.Homiefrost:BAAANQABCgMIAwAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgQICQAAAA==.',
Hr='Hroth:BAABNQAECoEeAAISAAgKQhR1FgDlAQASAAgKQhR1FgDlAQAAAA==.Hrothgar:BAAANQADCgIIAgABNQAECggIHgASAEIUAA==.',
Hu='Hunteroni:BAAANQAECgIIAwABNQAECgYIEQADAAAAAA==.',
Ia='Ianos:BAAANQAECgUIDQAAAA==.',
Ic='Icenea:BAAANQAECgEIAQABNQAECgkJLQAGAJ8lAA==.',
If='Ifearu:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQAECgcIDAAAAA==.',
Ik='Ikthus:BAAANQAECgYIEAAAAA==.',
Il='Illtud:BAAANQAECgQICwAAAA==.Ilyessa:BAACNQAFFIELAAIVAAUKqxY0BQCcAQAVAAUKqxY0BQCcAQA1AAQKgSIAAhUACQptIgkIADsDABUACQptIgkIADsDAAAA.',
Im='Impastable:BAAANQADCgEIAQABNQAECgYIEQADAAAAAA==.',
Ir='Ironfur:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.Ironpipes:BAAANQAECgUICwAAAA==.',
Is='Iskrå:BAAANQAECgQICQAAAA==.',
Ja='Jacynth:BAAANQAECgUICgAAAA==.Jaimers:BAABNQAECoEjAAMRAAgK/SGRFwACAwARAAgK/SGRFwACAwAJAAEKVweZJwAwAAAAAA==.Jardinn:BAABNQAECoEUAAMLAAcKdx7SOQBnAgALAAcKdx7SOQBnAgAMAAUK+yGlUwDrAQAAAA==.Jaxen:BAABNQAECoEXAAMCAAYKPAp5OgDMAAACAAQK6gl5OgDMAAABAAQK3Aa4+AClAAAAAA==.Jaxon:BAAANQAECgQIBQAAAA==.Jaywilde:BAABNQAECoE3AAMYAAkKZRnbQwClAgAYAAkKZRnbQwClAgAZAAEKVAUnLwAwAAAAAA==.',
Je='Jenne:BAAANQADCgYIBgAAAA==.Jerkpaladin:BAAANQADCggIFgAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.Jetsetradio:BAAANQAECgQIBAAAAA==.',
Ji='Jizakazam:BAAANQAECgYIDwAAAA==.',
Jo='Jojobeanice:BAAANQADCggIBwABNQAECgcIEwADAAAAAA==.Josepha:BAAANQADCgUICQAAAA==.',
Ju='Juggyspally:BAABNQAECoEfAAITAAgK7RHTfwD4AQATAAgK7RHTfwD4AQAAAA==.Justbringit:BAEANQAECgEIAQABNQAECgkJJwAdADojAA==.Juvens:BAAANQABCgMIAQAAAA==.',
['Jï']='Jïao:BAAANQAFFAEIAgAAAA==.',
Ka='Kairiccars:BAAANQADCgYIBgAAAA==.Karoc:BAAANQADCgUIBwABNQAECgcIEgADAAAAAA==.Karot:BAAANQADCggICAABNQAECgcIEgADAAAAAA==.Karotten:BAAANQAECgcIEgAAAA==.Karthair:BAAANQAECgYIEAAAAA==.Kassoa:BAABNQAECoEXAAIYAAgKNhrdWABkAgAYAAgKNhrdWABkAgAAAA==.Kaszim:BAABNQAECoEuAAMGAAkKySTUAgDQAwAGAAkKySTUAgDQAwAEAAEKzAemgQAuAAAAAA==.',
Ke='Keello:BAABNQAECoEZAAIaAAgKPwQlrwD1AAAaAAgKPwQlrwD1AAAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kenz:BAABNQAECoEYAAIeAAgK+RC1BQAtAgAeAAgK+RC1BQAtAgAAAA==.Keresis:BAAANQADCgcIBwAAAA==.Kernelsandrs:BAACNQAFFIEFAAIGAAQKBhO5DABSAQAGAAQKBhO5DABSAQA1AAQKgSEAAwYACQrDJMAdAAYDAAYACQrDJMAdAAYDAAQAAwqVBk1eAIUAAAAA.',
Ki='Kileena:BAAANQADCgQIBAABNQAECggIHgASAEIUAA==.Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQAECgcIEAAAAA==.Kirinmaruu:BAAANQAECgUIEAAAAA==.Kirisatsu:BAAANQAECgQICwAAAA==.Kisatchie:BAAANQAECgYIEgAAAA==.',
Ko='Koalitsiya:BAAANQAECgUICgAAAA==.Koko:BAAANQADCgQIBAAAAA==.Kozãk:BAAANQADCggIEwAAAA==.',
Kr='Kreatos:BAAANQAECgQIDQAAAA==.Krimez:BAABNQAECoEhAAMWAAkKzBKhEgAHAgAWAAgKyhOhEgAHAgAcAAcK6g3wDABVAQAAAA==.Krynez:BAAANQADCgUIEAABNQAECgkJIQAWAMwSAA==.',
Ky='Kyrhios:BAABNQAECoEXAAIZAAgKgRuBBgB6AgAZAAgKgRuBBgB6AgAAAA==.',
['Kà']='Kàkarot:BAAANQADCgEJAQAAAA==.',
['Kä']='Käggai:BAAANQAFFAEIAQAAAA==.',
['Kò']='Kòld:BAABNQAECoEoAAIfAAkKABrtBgDMAgAfAAkKABrtBgDMAgAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQAECgQIBQAAAA==.Lark:BAAANQAECgcIEAAAAA==.Larthas:BAABNQAECoEbAAIeAAgKahKQBQA3AgAeAAgKahKQBQA3AgAAAA==.Lary:BAAANQAECgUICQABNQAFFAMICgAQAMEXAA==.Lascie:BAABNQAECoEjAAMgAAgKYB3yBQCAAgAgAAgKYB3yBQCAAgANAAIKDAnxjQFpAAAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQAECgUICAADAAAAAA==.Leaila:BAAANQAECgUICwAAAA==.Leiha:BAAANQADCggIFAAAAA==.',
Li='Liams:BAAANQADCgcIGAAAAA==.Lidless:BAABNQAECoEgAAINAAgKkhuBdAB/AgANAAgKkhuBdAB/AgAAAA==.Linux:BAAANQAECgYIEQAAAA==.',
Ll='Llamadin:BAAANQAECgYIDwAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.Lohof:BAAANQABCgIIAgAAAA==.Lovelorn:BAAANQAECgUIBQAAAA==.',
Lu='Luckÿ:BAAANQAECgEIAQABNQADCgYIBgADAAAAAA==.Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAABNQAECoEgAAMWAAcKyByJDwBEAgAWAAcKyByJDwBEAgAUAAEKBwNeTAAmAAAAAA==.Lunah:BAAANQADCgIIAgAAAA==.',
Ly='Lynra:BAAANQAECgQIBQAAAA==.Lytol:BAAANQAECgQIBAAAAA==.',
Ma='Macloc:BAAANQAECgQJBwAAAA==.Maggiemae:BAAANQADCgUJDQAAAA==.Mahli:BAABNQAECoEjAAMCAAgKlxiIHACBAQACAAYKDROIHACBAQABAAUK+hbqlgB9AQAAAA==.Mark:BAAANQADCgMIAwAAAA==.Marrias:BAABNQAECoEkAAIFAAcK4hWnTAC6AQAFAAcK4hWnTAC6AQAAAA==.Massacre:BAAANQAECgQIBAABNQAECgQIDQADAAAAAA==.Mawrix:BAABNQAECoEaAAMhAAgKCQ25OQCsAQAhAAcK1Ay5OQCsAQAiAAcKOQoNIwCdAQAAAA==.Mawyai:BAAANQADCgQIBAAAAA==.Maxtheyare:BAAANQAECgQIBQAAAA==.',
Me='Mechchimy:BAAANQAECgMIBQABNQAECgYIFgAGAIEeAA==.Medîcus:BAAANQADCgIIAgAAAA==.Megumín:BAAANQAECgQICAAAAA==.Meith:BAAANQADCgUIBgAAAA==.Melwazul:BAAANQADCgMJAwAAAA==.Melz:BAAANQAECgEIAgAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAACNQAFFIELAAIeAAUKABVrAADOAQAeAAUKABVrAADOAQA1AAQKgScAAx4ACQonJdYAAIgDAB4ACQonJdYAAIgDAAQAAQoQDcF4ADcAAAAA.Meyla:BAAANQADCgcJBgAAAA==.',
Mi='Mibby:BAAANQAECgUIBQABNQAECgIIAgADAAAAAA==.Mibs:BAABNQAECoEgAAIYAAgKFBqFWQBiAgAYAAgKFBqFWQBiAgAAAA==.Mickal:BAABNQAECoEiAAITAAgKNQo4rQCMAQATAAgKNQo4rQCMAQAAAA==.Mikaelangelo:BAAANQAECgEJAQAAAA==.Mindrash:BAAANQAECgUIBQABNQAFFAMIBgANACMTAA==.Mip:BAAANQAECgIIAgAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAABNQAECoEfAAMPAAgK/BMcRQCvAQAPAAcK8xEcRQCvAQAOAAYK5BYlKgCaAQAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooter:BAABNQAECoEmAAIhAAkKFxe0GQCHAgAhAAkKFxe0GQCHAgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQABNQAECgcIEAADAAAAAA==.Mortincarne:BAAANQAECgYIBgAAAA==.',
Mu='Mushroom:BAAANQAECgcIDwAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAABNQAECoEhAAMKAAgK7BZhQQDZAQAKAAcK9hdhQQDZAQAFAAgKpglVaQBIAQAAAA==.Naqilol:BAAANQAECgMIAwAAAA==.Narfox:BAAANQAECgYIEAAAAA==.Narila:BAAANQAECgYIBgABNQAECgcIEAADAAAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAABNQAECoEgAAIcAAkKmQsuCQDIAQAcAAkKmQsuCQDIAQAAAA==.Necrophyle:BAAANQAECgQIBgAAAA==.Nefarox:BAAANQAECgQICwAAAA==.Neilion:BAAANQADCgMIAwAAAA==.Nerfslappy:BAAANQAECgEIAQAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAABNQAECoEdAAMLAAgKVxaUSwAbAgALAAgKVxaUSwAbAgAMAAcKaBjbZwCmAQAAAA==.Nightstealer:BAAANQAECgQIBQAAAA==.Nikkikayama:BAACNQAFFIEJAAIGAAUKLRbfBwCmAQAGAAUKLRbfBwCmAQA1AAQKgSMAAgYACQqOIfgiAO4CAAYACQqOIfgiAO4CAAAA.Nikol:BAAANQAECgcJEgABNQAECgkJHwAMAMoWAA==.',
No='Norikoff:BAACNQAFFIEGAAMZAAQKohKKAQDtAAAZAAMKdxGKAQDtAAAYAAIKhQ5VKwCDAAA1AAQKgRgAAxkACQroHcYDAOwCABkACQroHcYDAOwCABgACArVEZabAK0BAAAA.',
Ny='Nyalla:BAAANQADCgcIGQAAAA==.',
['Nï']='Nïdalee:BAAANQAECgUIEAAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQAECgQIBQAAAA==.',
Of='Offdensen:BAAANQADCgcIGAAAAA==.',
Ok='Okkotsu:BAAANQAECgIIAwAAAA==.Okku:BAAANQAECgIIAwAAAA==.',
Ol='Oldmims:BAABNQAECoEkAAMgAAgK7h2EBQCPAgAgAAgK7h2EBQCPAgANAAQKbA54TgHpAAAAAA==.Oldmimse:BAAANQAECgEIAQABNQAECggIJAAgAO4dAA==.',
On='Onlybatfans:BAAANQAECgYICwAAAA==.',
Op='Ophina:BAAANQAECgQICAAAAA==.',
Or='Oramu:BAAANQAECggIEwAAAA==.Orangejello:BAAANQAECgYIEgAAAA==.Orion:BAAANQAECgYIBgABNQAFFAUICwAVAKsWAA==.Oriòn:BAAANQAECgQICgAAAA==.Orpseroth:BAAANQAECgEIAQABNQAECgYIEAADAAAAAA==.',
Ot='Otane:BAAANQAECgYJCgAAAA==.',
Pa='Paiah:BAAANQAECgIIAgAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECggIHQARAHcbAA==.Pana:BAABNQAECoEbAAIQAAcK8w+gLABNAQAQAAcK8w+gLABNAQAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAAANQAECgYIEwAAAA==.Pannifer:BAAANQAECgUICgAAAA==.Paolon:BAAANQADCggIFAAAAA==.Papasmurph:BAAANQABCgIIAgAAAA==.Parple:BAAANQAECgUICgABNQAFFAYIDwAIAMUXAA==.',
Pc='Pcylock:BAAANQADCgYIBgAAAA==.',
Pe='Penelopei:BAAANQAECgcIDwAAAA==.',
Ph='Phantõm:BAAANQAECgIIAgAAAA==.Philkulson:BAAANQAECgcIDgABNQAFFAYIEgAFANwSAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgcIFwAAAA==.Porterah:BAAANQAECgYIBgAAAA==.Potbellypali:BAAANQABCgQIBgAAAA==.Poutyne:BAABNQAECoEmAAIPAAkK6R3xEwASAwAPAAkK6R3xEwASAwAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAFFAMIBQAVALgXAA==.',
Pu='Punchnugget:BAAANQAECgUICwAAAA==.Punkvc:BAAANQAECgYIEwAAAA==.',
Py='Pyren:BAAANQAECgEIAQAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQADAAAAAA==.',
Qu='Quaeras:BAAANQAECgcIDwAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Ragingnoodle:BAAANQADCgQIBAABNQAECgYIEQADAAAAAA==.Ragingshnoz:BAABNQAECoEhAAIbAAgKHyFRBQACAwAbAAgKHyFRBQACAwAAAA==.Ragé:BAEBNQAECoEnAAMdAAkKOiNSCQA3AwAdAAgKiCRSCQA3AwAHAAQKthwnTAA2AQAAAA==.Rakklock:BAAANQAECgIIAwAAAA==.Ralphe:BAAANQAECgYIEAAAAA==.Rashygroin:BAAANQABCgYJBgABNQAECggIIwAgAGAdAA==.Raytow:BAAANQAECgcIEwAAAA==.Razelle:BAAANQAECgYIDwAAAA==.',
Re='Reconpalymix:BAAANQAECgEIAgAAAA==.Relana:BAAANQAECgcICAAAAA==.Remus:BAAANQAECggIDQAAAA==.Reshad:BAAANQAECgMIBwAAAA==.Ressix:BAABNQAECoEjAAITAAgKmB9gOADLAgATAAgKmB9gOADLAgAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIBQABNQAECgQIBgADAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECggIIAANAJIbAA==.Rizzwar:BAAANQAECgYIBwAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQAECgQIBAAAAA==.Ronborules:BAAANQAECgQIBQAAAA==.Rosenta:BAAANQAECgYIEgAAAA==.',
Ru='Rumlock:BAAANQAECgYICwAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIEgAAAA==.',
Sa='Sabinah:BAAANQAECgMIBAAAAA==.Sabing:BAAANQADCgcIGQAAAA==.Sacramento:BAAANQADCgMJAwAAAA==.Saeberis:BAAANQAECgQIBAAAAA==.Saiah:BAAANQAECgYIEAAAAA==.Saintbazz:BAAANQAECgUIEQAAAA==.Sal:BAACNQAFFIEPAAIIAAYKxReUAwD9AQAIAAYKxReUAwD9AQA1AAQKgTEAAggACQq0JPYCAKMDAAgACQq0JPYCAKMDAAAA.Salivan:BAAANQAECgQICwAAAA==.Sargaris:BAAANQAECgUIDAAAAA==.Sariva:BAACNQAFFIEPAAQCAAYKfiERBADPAAABAAMKqB+oFQAXAQACAAIKuiMRBADPAAAjAAEKiCJzBgBhAAA1AAQKgScABAEACQqYIJpQAEICAAEABwqLIZpQAEICAAIABQrtFg0kAEcBACMABAr/GgsPADgBAAAA.Sathalis:BAAANQAECgQICAAAAA==.Saurva:BAAANQAECgcIEgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgYIEgADAAAAAA==.Saxophone:BAABNQAECoEfAAIVAAgK1hgKHAAuAgAVAAgK1hgKHAAuAgAAAA==.Sayna:BAAANQAECgUIEQAAAA==.',
Sc='Scarecro:BAABNQAECoEiAAMQAAgKOB8TDQCoAgAQAAgKOB8TDQCoAgATAAMKshJ4MAGSAAAAAA==.',
Se='Sedae:BAABNQAECoEgAAIYAAgKjRv3SQCSAgAYAAgKjRv3SQCSAgAAAA==.Seekvaira:BAABNQAECoEgAAILAAkKjRvALQCiAgALAAkKjRvALQCiAgAAAA==.Seelenlos:BAAANQADCggIDwAAAA==.Seiya:BAABNQAECoEYAAIFAAkK0xtEJgCEAgAFAAkK0xtEJgCEAgAAAA==.Selira:BAAANQAECgYIEQAAAA==.Selwynn:BAAANQAECgcIBwAAAA==.Senji:BAAANQAECgMIBAAAAA==.Senseitots:BAAANQADCggICAAAAA==.Sevalina:BAABNQAECoEgAAIRAAgKvxDPUwD8AQARAAgKvxDPUwD8AQAAAA==.',
Sh='Shadowstep:BAAANQAECgQIBQAAAA==.Shalaah:BAABNQAECoEaAAIGAAcKgAn2lwClAQAGAAcKgAn2lwClAQAAAA==.Shamhuntzu:BAECNQAFFIEHAAIdAAUK6wz5BgCBAQAdAAUK6wz5BgCBAQA1AAQKgRsAAx0ACQqkFT4eAEICAB0ACQqkFT4eAEICACQAAwrIBUUiAHoAAAAA.Shampaign:BAABNQAECoEjAAMMAAgK3iBUGgDsAgAMAAgK3iBUGgDsAgALAAIKgRS37gB0AAAAAA==.Shaoevoker:BAAANQAECgQIBAAAAA==.Sharnara:BAAANQAECgUICQAAAA==.Shatterskull:BAAANQAECgQIBAAAAA==.Shazira:BAAANQAECgQIBAAAAA==.Shep:BAAANQAECgUIBQAAAA==.Sherloch:BAAANQADCgQIBQAAAA==.Shi:BAAANQAECgMIAwAAAA==.Shiftyrum:BAAANQAECgQIBQABNQAECgcIHQANAOccAA==.Shmollboi:BAAANQABCgIIAgAAAA==.Shnub:BAAANQAECgQIBAAAAA==.',
Si='Sideffects:BAABNQAECoEaAAILAAgKHxo8OABvAgALAAgKHxo8OABvAgAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAABNQAECoEfAAIBAAcKKhr1XgAZAgABAAcKKhr1XgAZAgAAAA==.Silverlord:BAABNQAECoEgAAIXAAgKLhwSCACTAgAXAAgKLhwSCACTAgAAAA==.Sinafay:BAABNQAECoEaAAMgAAkKcwtxEAB3AQAgAAkKcwtxEAB3AQANAAEKuQJUwgEiAAAAAA==.Sineu:BAAANQADCgcIBwABNQAFFAMIBQAVALgXAA==.Siv:BAACNQAFFIEFAAIVAAMKuBd5CQDrAAAVAAMKuBd5CQDrAAA1AAQKgSoAAhUACQoBI1AFAG0DABUACQoBI1AFAG0DAAAA.',
Sj='Sjor:BAAANQADCgIIAgAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQAECgIIAgAAAA==.',
Sn='Snackkpack:BAAANQAECgIIBAAAAA==.Snapjutsu:BAECNQAFFIEFAAIVAAMKdgV7CwCyAAAVAAMKdgV7CwCyAAA1AAQKgR4AAxUACAouFkUhAPQBABUACAouFkUhAPQBABcAAQoQFfgtACsAAAAA.Snorg:BAABNQAECoEiAAINAAgKZwhi2QCuAQANAAgKZwhi2QCuAQAAAA==.Snêaky:BAABNQAECoEbAAMhAAcKGCA1HAB0AgAhAAcKGCA1HAB0AgAiAAEK5QlkSgA5AAAAAA==.',
So='Solarnova:BAAANQAECgYIEwAAAA==.Solorn:BAAANQAECgcIHwAAAQ==.',
Sp='Splash:BAAANQAECgEIAQAAAA==.Spygon:BAABNQAECoEXAAMGAAcKJBd0ZQAfAgAGAAcKJBd0ZQAfAgAEAAEKBQcpgwAsAAAAAA==.',
St='Strobila:BAAANQAECgYIEAAAAA==.Studd:BAAANQAECgMIAwAAAA==.Studdmuffin:BAACNQAFFIEIAAMlAAUKhQ2kCgDsAAAlAAMK0hKkCgDsAAAFAAIKkgVzGABzAAA1AAQKgRkAAwUACQoqIcxBAO4BAAUACAr8G8xBAO4BACUABQpcIR9BAH4BAAAA.',
Su='Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAABNQAECoEdAAMKAAgKTR1kHwCfAgAKAAgKTR1kHwCfAgAFAAcKBhgqTAC8AQAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Sylvië:BAAANQAECggIAwAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAABNQAECoEhAAIKAAgKIx2BHwCeAgAKAAgKIx2BHwCeAgAAAA==.Syrathos:BAACNQAFFIEVAAMdAAcK3xeFAQBzAgAdAAcK3xeFAQBzAgAHAAEKrR0vFwBXAAA1AAQKgSkAAx0ACQrrI4gFAHMDAB0ACQrrI4gFAHMDAAcAAgpiGotqAJgAAAAA.Syrioforel:BAAANQAECgQIBwAAAA==.',
Ta='Taojîn:BAABNQAECoEYAAIaAAkKfQxCVAD9AQAaAAkKfQxCVAD9AQAAAA==.Tarted:BAAANQAECgUICgAAAA==.Tatèrdots:BAAANQADCgYIBgAAAA==.',
Te='Teclis:BAABNQAECoEeAAINAAkKSCFwSwDbAgANAAkKSCFwSwDbAgAAAA==.Telzindrov:BAABNQAECoEaAAMUAAgKBQaiJwBWAQAUAAgKBQaiJwBWAQAcAAcKBwT4EAD5AAAAAA==.Terrorwithin:BAAANQAECgYIDAAAAA==.',
Th='Thalgar:BAAANQAECgIIAgAAAA==.Thalmick:BAABNQAECoEjAAIiAAgK2hiaEQBVAgAiAAgK2hiaEQBVAgAAAA==.Thanoslye:BAAANQAECgEIAgAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Theyathal:BAAANQAECgcIBwAAAA==.Thogarn:BAAANQAECgYIEQAAAA==.Thunderkat:BAAANQAECgIIAwABNQAECgUICAADAAAAAA==.Thundertem:BAAANQAECgQIBQAAAA==.Théière:BAABNQAECoEkAAIWAAgKBRaxEAAsAgAWAAgKBRaxEAAsAgAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUJDQADAAAAAA==.Tinychimy:BAAANQADCgUICAABNQAECgYIFgAGAIEeAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAABNQAECoEYAAINAAgKOxDmugDqAQANAAgKOxDmugDqAQABNQAECgkJIgASACshAA==.',
To='Tofper:BAAANQADCgYIBgAAAA==.Totemstout:BAAANQAECggICAAAAA==.Toughlove:BAAANQAECgIIAwAAAA==.',
Tr='Trev:BAABNQAECoEeAAMNAAkK6h1EQAD2AgANAAkK6h1EQAD2AgAgAAEKUB+nOABFAAAAAA==.Trustfäll:BAAANQAECgUICwAAAA==.',
Ts='Tsunãmi:BAABNQAECoEiAAMMAAkKkxkCLwCBAgAMAAkKkxkCLwCBAgAmAAgKlQ+GEwAKAgAAAA==.',
Tu='Tuc:BAAANQAECgcIEgAAAA==.',
Ty='Tyndareos:BAAANQADCgUIBgAAAA==.Typhoontravv:BAABNQAECoEfAAMQAAkKgx1RDgCSAgAQAAkKOR1RDgCSAgATAAQKrhwA7AAKAQAAAA==.',
['Tø']='Tøkakagé:BAAANQAECgUIDAAAAA==.',
Uf='Ufearme:BAAANQAECgMIBAAAAA==.',
Ug='Ugabooga:BAABNQAECoEzAAINAAkKSiGoJwA5AwANAAkKSiGoJwA5AwAAAA==.Uggon:BAAANQAECgQICwAAAA==.',
Un='Unable:BAAANQAECgUIDwAAAA==.',
Ur='Urrikahn:BAAANQAECgQIBQAAAA==.',
Ut='Uthur:BAAANQAECgYIDwAAAA==.Utterchaos:BAACNQAFFIEJAAIBAAUKegktDgBoAQABAAUKegktDgBoAQA1AAQKgRsAAwEACQo0FeJ+AL0BAAEACAoqE+J+AL0BAAIABAr8CrY+AL0AAAAA.',
Va='Vaelaven:BAABNQAECoEkAAIPAAkKQBHsMAA1AgAPAAkKQBHsMAA1AgAAAA==.Valack:BAAANQAECgMIAwAAAA==.Valfore:BAABNQAECoEjAAIKAAgKXiK1EwD5AgAKAAgKXiK1EwD5AgAAAA==.Valizor:BAAANQAECgUIEQAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAAANQAECgcIEAAAAA==.Vayle:BAAANQADCggIDgABNQAECggIJAAGAOkdAA==.',
Ve='Velaara:BAAANQAECgEIAQAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vestoris:BAAANQAECgMIAwAAAA==.Vetta:BAACNQAFFIEIAAIMAAUKgAnuCwBnAQAMAAUKgAnuCwBnAQA1AAQKgRgAAgwACQpMEe1gALwBAAwACQpMEe1gALwBAAAA.',
Vg='Vger:BAAANQADCggIEwAAAA==.',
Vi='Vieora:BAAANQADCgYIBgAAAA==.Vikvikvik:BAAANQADCgYICwAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgcIBwAAAA==.',
Vo='Volgagrad:BAAANQAECgcIBwAAAA==.Vond:BAAANQABCgIJAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQAECgMIBQADAAAAAA==.',
Wa='Wardum:BAAANQAECgUICgAAAA==.Watt:BAAANQADCggICAABNQAFFAMIBQAVALgXAA==.Wazul:BAAANQADCgcIGAAAAA==.',
Wh='Whisp:BAAANQAECgIIAgAAAA==.Whitearrows:BAABNQAECoEsAAMGAAkKQCI7CQCEAwAGAAkKQCI7CQCEAwAEAAQKORAmSgDdAAAAAA==.Whitespell:BAAANQAECggIEwABNQAECgkJLAAGAEAiAA==.',
Wi='Wickfel:BAAANQAECgQIBAAAAA==.Wicus:BAAANQADCggICAAAAA==.',
Wy='Wyldfarmer:BAAANQAECgUICQAAAA==.',
Xa='Xanid:BAAANQAECgYIEAAAAA==.',
Xd='Xdwarf:BAAANQAECgYIDAABNQAECggIIwAhAB0VAA==.',
Xe='Xeroxoxo:BAABNQAECoEjAAIFAAkKsx/jGgDPAgAFAAkKsx/jGgDPAgAAAA==.Xevric:BAAANQAECggIAwAAAA==.',
Xi='Xieren:BAAANQAECgQICQABNQAECgQIDQADAAAAAA==.',
Xo='Xoz:BAAANQAECgQIBAAAAA==.',
Ya='Yasman:BAAANQADCggIFwAAAA==.',
Ym='Ymedead:BAAANQAFFAEIAgABNQAFFAQIBQAGAAYTAA==.',
Yo='Yoroichi:BAABNQAECoEjAAIhAAgKHRVzJAA4AgAhAAgKHRVzJAA4AgAAAA==.Yourmomsride:BAABNQAECoEdAAINAAgKqgkI0ADBAQANAAgKqgkI0ADBAQAAAA==.',
Yu='Yueyue:BAABNQAECoEaAAINAAkKWBbsXgCuAgANAAkKWBbsXgCuAgAAAA==.Yungtwizzler:BAAANQADCggIEQABNQAECgQIBAADAAAAAA==.',
['Yá']='Yáng:BAAANQAECgUIEgAAAA==.',
Za='Zarylathanea:BAABNQAECoEfAAIGAAcKXQeApwCDAQAGAAcKXQeApwCDAQAAAA==.',
Ze='Zenheals:BAAANQAECggIAgAAAA==.Zeniel:BAAANQADCgIIAgAAAA==.Zeroskills:BAAANQAECgYIDAAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQAECgUIEQAAAA==.Zoog:BAACNQAFFIEJAAIaAAUKnQ1NCwCEAQAaAAUKnQ1NCwCEAQA1AAQKgRwAAhoACQqBHIogANYCABoACQqBHIogANYCAAAA.',
Zy='Zyrana:BAAANQADCgQICAAAAA==.Zyridal:BAABNQAECoEfAAINAAgKIAOeDAFRAQANAAgKIAOeDAFRAQAAAA==.Zyvara:BAAANQAECgYIEQAAAA==.',
['Zä']='Zärèlíä:BAACNQAFFIELAAIVAAUKOxXCBQCFAQAVAAUKOxXCBQCFAQA1AAQKgT8AAhUACQo0I9sFAGMDABUACQo0I9sFAGMDAAE1AAQKCQkoABMAQCMA.',
['Äp']='Äpples:BAAANQAECgQIBgAAAA==.',
['Æz']='Æz:BAABNQAECoEfAAIHAAgKkhFwMgDmAQAHAAgKkhFwMgDmAQAAAA==.',
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
