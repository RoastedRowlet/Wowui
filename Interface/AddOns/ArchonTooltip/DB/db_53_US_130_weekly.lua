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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Druid-Restoration','Druid-Balance','Paladin-Protection','Warlock-Destruction','Monk-Mistweaver','Paladin-Retribution','Evoker-Preservation','Monk-Windwalker','Evoker-Augmentation','Monk-Brewmaster','Priest-Holy','Warrior-Arms','Warrior-Fury','Paladin-Holy','Warrior-Protection','Evoker-Devastation','Warlock-Demonology','DemonHunter-Devourer','Druid-Feral','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Hunter-Survival','Warlock-Affliction','DemonHunter-Vengeance','DeathKnight-Frost','Shaman-Enhancement',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abonde:BAAANQAECgQIBAAAAA==.Abraxes:BAAANQAECgQICgAAAA==.',
Ac='Acidemon:BAAANQAECgUICgAAAA==.',
Ad='Adalaide:BAAANQAECgYIEQAAAA==.Adannis:BAAANQAECgIIAgABNQAECgYIDAABAAAAAA==.Adelane:BAAANQAECgEIAQABNQAECgUIEQABAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQAECgQIDQAAAA==.Aethas:BAAANQADCgYICAAAAA==.',
Af='Affective:BAABNQAECoEcAAICAAkKfRY1FwBxAgACAAkKfRY1FwBxAgABNQAFFAYIDQADALkQAA==.Afkk:BAAANQADCggIBAAAAA==.',
Ah='Ahuramazda:BAAANQAECgcICQAAAA==.',
Ai='Aidard:BAAANQABCggIDwAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCggIHgAAAA==.',
Ak='Akio:BAABNQAECoEcAAIEAAgKyh3UJgDCAgAEAAgKyh3UJgDCAgAAAA==.',
Al='Aldarya:BAAANQAECgMIBAAAAA==.Alisara:BAABNQAECoEkAAIEAAgKOiW5DgBHAwAEAAgKOiW5DgBHAwAAAA==.Alish:BAAANQADCggIFwAAAA==.Allexx:BAABNQAECoEZAAIEAAgKLhf0QgBYAgAEAAgKLhf0QgBYAgAAAA==.Allyssel:BAACNQAFFIEQAAIFAAUKgBtJBADKAQAFAAUKgBtJBADKAQA1AAQKgSkAAgUACQqwJt8AAO0DAAUACQqwJt8AAO0DAAAA.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAABNQAECoEZAAMGAAkKmhyrEQClAgAGAAkKmhyrEQClAgAHAAMKGQ6IFACkAAAAAA==.Amazinggrace:BAABNQAECoEXAAMDAAcKNQ6fTwBtAQADAAcKZw2fTwBtAQAIAAUKPAuwdADVAAAAAA==.Amentiu:BAAANQADCgUICAABNQAECgUIDwABAAAAAA==.Ammathendis:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Ammiel:BAAANQADCgEIAQABNQAECgkJJQAIAHQcAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQAECgQIBQAAAA==.Angeal:BAAANQAECgUIDQAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAABNQAECoEZAAMJAAcKYQ+VZACeAQAJAAcKYQ+VZACeAQAKAAUK0AlMnQDlAAAAAA==.Annamei:BAAANQAECgUIDQAAAA==.',
Ao='Aoife:BAAANQAECgYIEgAAAA==.Aorina:BAABNQAECoEfAAILAAcKjxV6lgAPAgALAAcKjxV6lgAPAgAAAA==.',
Ar='Arazalor:BAABNQAECoEbAAMMAAgKcwsKKAB5AQAMAAgKcwsKKAB5AQANAAUKjwOucQCvAAAAAA==.Arcangel:BAABNQAECoEdAAMMAAkK7iPWAwBvAwAMAAkK7iPWAwBvAwANAAEK+Rm8igBGAAAAAA==.Arrash:BAAANQADCgYICwABNQAECgYICQABAAAAAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAABNQAECoEYAAIJAAcKPiCEKwCSAgAJAAcKPiCEKwCSAgAAAA==.Arysa:BAAANQADCgUIBQAAAA==.',
As='Ashara:BAABNQAECoEZAAIOAAcKHhUmHgCcAQAOAAcKHhUmHgCcAQAAAA==.Ashenrain:BAAANQAECgQIBAAAAA==.Ashvia:BAAANQAECgMIAwAAAA==.Aspiration:BAAANQABCgMIBQAAAA==.',
At='Atheren:BAAANQAECgcIEgAAAA==.Athshu:BAAANQADCgcIBwAAAA==.Atulan:BAAANQAECgYIDwAAAA==.',
Au='Auntiemimi:BAAANQAECgMIBwAAAA==.',
Av='Avalina:BAAANQAECgYIEQABNQAFFAUICgAPAHkeAA==.Avannar:BAAANQADCgcIFwAAAA==.Avelyn:BAAANQAECgcIBwAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQAECgEJAQAAAA==.',
Ay='Ayani:BAAANQAECgYJEAAAAA==.',
Az='Azrine:BAAANQAECgYIBgAAAA==.',
Ba='Babymanowood:BAAANQADCgcJBwAAAA==.Baddattitude:BAAANQADCgUIDAABNQADCggIGwABAAAAAA==.Baddkharma:BAAANQAECgEIAQAAAA==.Badras:BAAANQAECgYIEgAAAA==.Bagelz:BAABNQAECoEZAAIQAAkKQSGnBgABAwAQAAkKQSGnBgABAwAAAA==.Balforyn:BAAANQAECgUIBQAAAA==.Bathomula:BAAANQAECgUIDQAAAA==.Bayla:BAAANQADCgUIBQABNQAFFAYIEwAQADAXAA==.Bazza:BAAANQADCgYIBgABNQAECgQIDQABAAAAAA==.Bazzwar:BAAANQADCggICwABNQAECgQIDQABAAAAAA==.',
Be='Beric:BAAANQAFFAEIAQAAAA==.Betadine:BAAANQAECgUIBQAAAA==.Bexy:BAABNQAECoEZAAIKAAkK5RQYMgBUAgAKAAkK5RQYMgBUAgAAAA==.',
Bl='Blade:BAABNQAECoEbAAIFAAcKeQdaPgBaAQAFAAcKeQdaPgBaAQAAAA==.',
Bo='Boldan:BAAANQADCgIIAwAAAA==.Boohaha:BAABNQAECoEYAAIKAAgKlhjjOwAnAgAKAAgKlhjjOwAnAgAAAA==.Booze:BAAANQAECgMIAwABNQAECggIAwABAAAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAABNQAECoEaAAIRAAcKFSLKRwBwAgARAAcKFSLKRwBwAgAAAA==.',
Br='Brightwing:BAABNQAECoEmAAISAAkKmB5WBwATAwASAAkKmB5WBwATAwAAAA==.Brigorath:BAAANQAECgQIBAAAAA==.Brokenarro:BAAANQADCgcJGQAAAA==.',
Bu='Bubblebae:BAAANQAECgQICAABNQAECgYIDgABAAAAAA==.Bullshivek:BAAANQAECgUICwAAAA==.',
Ca='Caale:BAAANQAECgUICwAAAA==.Caecus:BAAANQAECgUICwAAAA==.Callsaul:BAEANQAECgMIBgAAAA==.Casmus:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Caylissa:BAAANQAECgMIBQAAAA==.',
Ce='Celryth:BAAANQADCgYIBwAAAA==.Cenvoked:BAAANQAECgcIDgAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgUJDgABNQAECgYIBwABAAAAAA==.Charlicious:BAAANQAECgYIBwAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgYIBwABAAAAAA==.Charticulous:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.Cheylia:BAAANQAECgYIBgAAAA==.Chijoku:BAABNQAECoEfAAINAAgKiwwzPQC8AQANAAgKiwwzPQC8AQAAAA==.Chimster:BAABNQAECoEUAAIEAAYKgR6DVQAgAgAEAAYKgR6DVQAgAgAAAA==.Chimydakilla:BAAANQADCgQIBAABNQAECgYIFAAEAIEeAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggJCAAAAA==.',
Co='Corvò:BAAANQAECgUIDQAAAA==.',
Cr='Craeus:BAAANQAECgcIEQAAAA==.Cralk:BAAANQAECgcIDgABNQAECggIEQABAAAAAA==.Cranked:BAAANQAECgQIBAABNQAECgkJJwATAI8hAA==.Crine:BAAANQADCggICwABNQAECgkJGgAUAL4RAA==.',
Cy='Cyonarah:BAAANQAECgQIBAAAAA==.',
Da='Darem:BAAANQAECgcICQAAAA==.',
De='Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgUIDAAAAA==.Deidra:BAAANQAECgIIAgAAAA==.Dek:BAAANQAECgUIBQAAAA==.Demons:BAAANQABCggIDAAAAA==.Devilette:BAAANQADCgEIAQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAABNQAECoEiAAIEAAgKtSOWEwAnAwAEAAgKtSOWEwAnAwAAAA==.Diggi:BAAANQAECgQICQAAAA==.Diosa:BAABNQAECoEcAAIPAAgKQxJaCwAuAgAPAAgKQxJaCwAuAgAAAA==.Divinekat:BAAANQAECgMIAwAAAA==.Dizza:BAAANQAECgEIAQAAAA==.',
Dk='Dkagon:BAAANQAECgYJDAAAAA==.',
Do='Docholiday:BAAANQAECgUIBQAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQAECgUIDgAAAA==.Dooderonomy:BAAANQAECgUICwAAAA==.Doria:BAAANQADCgQIBAAAAA==.',
Dr='Dragaan:BAAANQAECgYIEQAAAA==.Dragonbait:BAABNQAECoE3AAIRAAkKDR/QHQAfAwARAAkKDR/QHQAfAwAAAA==.Dragonoodles:BAAANQAECgYIEQAAAA==.Dragonzbane:BAAANQAECgUIDQAAAA==.Dranosh:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAwAAAA==.Drekthanas:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Drenea:BAAANQADCgcIGQAAAA==.Drimlek:BAAANQADCgEIAQAAAA==.Drin:BAAANQAECgUICwAAAA==.',
Du='Duplicitous:BAAANQADCgcJBwAAAA==.',
Dy='Dyriana:BAAANQADCgcIFgAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAABNQAECoEVAAIVAAcKKQ9JEgB7AQAVAAcKKQ9JEgB7AQAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQAECgQIDQAAAA==.Ellewoods:BAAANQADCggIDwABNQAECgMIAwABAAAAAA==.Eloise:BAAANQAECgYIBgAAAA==.Eltria:BAABNQAECoEZAAILAAkKbyJpNAAFAwALAAkKbyJpNAAFAwAAAA==.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAABNQAECoEXAAIWAAgKshgxNgBLAgAWAAgKshgxNgBLAgAAAA==.',
Er='Eric:BAAANQAECgIIAgABNQAECgcIGwAXAI0cAA==.Erid:BAAANQADCgcIBwAAAA==.Erverlyn:BAAANQADCgQIBAAAAA==.',
Es='Essential:BAABNQAECoEZAAIYAAkKjSC/AgAAAwAYAAkKjSC/AgAAAwAAAA==.',
Ex='Exces:BAAANQADCgUIBQAAAA==.',
Ez='Ezalth:BAAANQADCggIGwAAAA==.Ezz:BAAANQADCggJDwAAAA==.',
Fa='Fachzile:BAAANQADCgQIBAAAAA==.Faden:BAAANQAECgcIEgABNQAECgkJJwATAI8hAA==.Faenara:BAABNQAECoEcAAMZAAgKBRuFKACRAgAZAAgKBRuFKACRAgARAAUKJw201AD9AAAAAA==.Falafelguy:BAABNQAECoEgAAILAAgK7h15ZQCDAgALAAgK7h15ZQCDAgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Faruqq:BAABNQAECoEZAAMaAAgKFx0oBwCkAgAaAAgKFx0oBwCkAgAXAAcKgAg5qABQAQAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECggIIAALAO4dAA==.Felartamiel:BAAANQADCgcIGgAAAA==.Felkieler:BAAANQADCgYICAABNQAECgQIBQABAAAAAA==.Fey:BAAANQAECgUICgAAAA==.',
Fi='Firêstorm:BAAANQAECggIBgAAAA==.Fishron:BAAANQAECgUICwAAAA==.',
Fl='Flaz:BAABNQAECoEbAAINAAkKUBp/IACUAgANAAkKUBp/IACUAgAAAA==.Fleury:BAAANQABCgUIBAAAAA==.',
Fo='Forestspirit:BAAANQAECgYJDQAAAA==.Fourneau:BAAANQADCggJCAABNQAECggIHAAbAJATAA==.',
Fr='Frawda:BAABNQAECoEWAAMXAAcKKgghoQBlAQAXAAcKKgghoQBlAQAYAAQKNQWOGwCZAAAAAA==.',
Fu='Fusillidari:BAAANQAECgQICAABNQAECgYIEQABAAAAAA==.Fuzzy:BAAANQADCgIIAgAAAA==.',
Ga='Galaxyman:BAAANQADCggIEQAAAA==.Garlone:BAAANQABCgcIBwAAAA==.',
Ge='Geist:BAABNQAECoEXAAIRAAkKkySVHwAWAwARAAkKkySVHwAWAwAAAA==.Geraith:BAABNQAECoEWAAIIAAkKWx+HFwDBAgAIAAkKWx+HFwDBAgAAAA==.Gerios:BAABNQAECoEaAAIEAAgKQhl5OQB5AgAEAAgKQhl5OQB5AgAAAA==.Getafix:BAAANQADCgQIBAAAAA==.Getmadbro:BAAANQAECgMIAwAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQAECgYIBgAAAA==.',
Gl='Glacier:BAAANQABCgYICAAAAA==.Glaedyr:BAAANQADCgEIAQABNQAECggIGAAQAGETAA==.Glendra:BAABNQAECoEZAAIOAAgKthU+GADeAQAOAAgKthU+GADeAQAAAA==.Glorificus:BAAANQADCggJDgAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAAANQAECgYIEwAAAA==.Greensleeves:BAAANQADCgcIGAAAAA==.Gregoriusz:BAABNQAECoEfAAICAAgKhRidGwA/AgACAAgKhRidGwA/AgAAAA==.Greygull:BAAANQAECgMIBAAAAA==.Grimfrost:BAAANQABCgIIAgAAAA==.Grunin:BAAANQADCgcIBwAAAA==.',
Gu='Guinness:BAAANQAECgUIEAAAAA==.Guntank:BAABNQAECoEcAAMYAAgKjBMrEQA8AQAXAAgKfxE5cgDvAQAYAAUKcBIrEQA8AQAAAA==.',
Ha='Hategnomer:BAAANQADCgcIGQAAAA==.Havenfell:BAAANQAECgYJCwAAAA==.Hawkfist:BAABNQAECoEZAAIEAAgKZBVqRwBLAgAEAAgKZBVqRwBLAgAAAA==.',
He='Hercules:BAACNQAFFIEHAAIDAAUKGggxBwAyAQADAAUKGggxBwAyAQA1AAQKgTQAAgMACQoPJLsDAKIDAAMACQoPJLsDAKIDAAAA.Herzagon:BAAANQAECgIIAgAAAA==.',
Hi='Hierodoulos:BAABNQAECoEcAAIMAAgKhyS9BQBEAwAMAAgKhyS9BQBEAwAAAA==.',
Ho='Holykat:BAAANQADCggICwABNQAECgMIAwABAAAAAA==.Homiefrost:BAAANQABCgMIAwAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgMIBQAAAA==.',
Hr='Hroth:BAABNQAECoEYAAIQAAgKYRNkFADgAQAQAAgKYRNkFADgAQAAAA==.Hrothgar:BAAANQADCgIIAgABNQAECggIGAAQAGETAA==.',
Hu='Hunteroni:BAAANQAECgIIAwABNQAECgYIEQABAAAAAA==.',
Ia='Ianos:BAAANQAECgUICQAAAA==.',
Ic='Icenea:BAAANQAECgEIAQABNQAECggIJAAEADolAA==.',
If='Ifearu:BAAANQADCgYIBgABNQADCgcJGQABAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQAECgYICwAAAA==.',
Ik='Ikthus:BAAANQAECgYIDAAAAA==.',
Il='Illtud:BAAANQAECgQICAAAAA==.Ilyessa:BAACNQAFFIEGAAITAAUKZw8JBQB3AQATAAUKZw8JBQB3AQA1AAQKgR8AAhMACQpGIscGAEIDABMACQpGIscGAEIDAAAA.',
Ir='Ironfur:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Ironpipes:BAAANQAECgQIBwAAAA==.',
Is='Iskrå:BAAANQAECgQIBAAAAA==.',
Ja='Jacynth:BAAANQAECgUICgAAAA==.Jaimers:BAABNQAECoEbAAMWAAgK7R8lGwDVAgAWAAgK7R8lGwDVAgAHAAEKVwfEIwAwAAAAAA==.Jardinn:BAAANQAECgYIDgAAAA==.Jaxen:BAABNQAECoEXAAMPAAYKPAr6NgDRAAAPAAQK6gn6NgDRAAAcAAQK3AZR2wCpAAAAAA==.Jaxon:BAAANQAECgQIBAAAAA==.Jaywilde:BAABNQAECoEuAAMXAAkKUxcGRQB/AgAXAAkKUxcGRQB/AgAYAAEKVAXvKAAyAAAAAA==.',
Je='Jenne:BAAANQADCgYIBgAAAA==.Jerkpaladin:BAAANQADCggIFgAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.Jetsetradio:BAAANQAECgQIBAAAAA==.',
Ji='Jizakazam:BAAANQAECgYIDwAAAA==.',
Jo='Josepha:BAAANQADCgMIBAAAAA==.',
Ju='Juggyspally:BAAANQAECgcIEgAAAA==.Justbringit:BAEANQAECgEIAQABNQAECgkJJAAdACcjAA==.Juvens:BAAANQABCgMIAQAAAA==.',
['Jï']='Jïao:BAAANQAFFAEIAQAAAA==.',
Ka='Kairiccars:BAAANQADCgYIBgAAAA==.Karoc:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Karotten:BAAANQAECgYICwAAAA==.Karthair:BAAANQAECgUICgAAAA==.Kassoa:BAAANQAECgcIDQAAAA==.Kaszim:BAABNQAECoElAAMEAAkK2iLEBwCDAwAEAAkK2iLEBwCDAwACAAEKzActcQAwAAAAAA==.',
Ke='Keello:BAABNQAECoEVAAIZAAgKqwLRtgDAAAAZAAgKqwLRtgDAAAAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kenz:BAAANQAECgcIDgAAAA==.Keresis:BAAANQADCgcIBwAAAA==.Kernelsandrs:BAABNQAECoEfAAMEAAkK+SN1GAAIAwAEAAkK+SN1GAAIAwACAAMKlQZkUgCJAAAAAA==.',
Ki='Kileena:BAAANQADCgQIBAABNQAECggIGAAQAGETAA==.Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQAECgcIEAAAAA==.Kirinmaruu:BAAANQAECgQIDAAAAA==.Kirisatsu:BAAANQAECgQIBwAAAA==.Kisatchie:BAAANQAECgUIDAAAAA==.',
Ko='Koalitsiya:BAAANQAECgUIBQAAAA==.Koko:BAAANQADCgQIBAAAAA==.Kozãk:BAAANQADCgcJCwAAAA==.',
Kr='Kreatos:BAAANQAECgQICQAAAA==.Krimez:BAABNQAECoEaAAMUAAkKvhHiCgBfAQAbAAcKshPMFAC9AQAUAAcK6g3iCgBfAQAAAA==.Krynez:BAAANQADCgUIEAABNQAECgkJGgAUAL4RAA==.',
Ky='Kyrhios:BAAANQAECgYIDgAAAA==.',
['Kà']='Kàkarot:BAAANQADCgEJAQAAAA==.',
['Kä']='Käggai:BAAANQAECggIEgAAAA==.',
['Kò']='Kòld:BAABNQAECoEhAAIeAAkKpxcbBwCRAgAeAAkKpxcbBwCRAgAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQADCgcIDgAAAA==.Lark:BAAANQAECgYICwAAAA==.Larthas:BAAANQAECgYIEgAAAA==.Lary:BAAANQAECgMIBAABNQAFFAMIBwAOAL0WAA==.Lascie:BAABNQAECoEbAAMfAAgK3hz+BACKAgAfAAgK3hz+BACKAgALAAIKDAmIbgFtAAAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Leaila:BAAANQAECgUICwAAAA==.Leiha:BAAANQADCggIFAAAAA==.',
Li='Liams:BAAANQADCgcIFAAAAA==.Lidless:BAABNQAECoEcAAILAAgKyRoFZgCCAgALAAgKyRoFZgCCAgAAAA==.Linux:BAAANQAECgUICwAAAA==.',
Ll='Llamadin:BAAANQAECgUICQAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.Lohof:BAAANQABCgIIAgAAAA==.Lovelorn:BAAANQAECgEIAQAAAA==.',
Lu='Luckÿ:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAABNQAECoEaAAIbAAcK9xp0DwAnAgAbAAcK9xp0DwAnAgAAAA==.Lunah:BAAANQADCgIIAgAAAA==.',
Ly='Lynra:BAAANQAECgQIBQAAAA==.Lytol:BAAANQADCggIIwAAAA==.',
Ma='Macloc:BAAANQAECgQJBwAAAA==.Maggiemae:BAAANQADCgUJDQAAAA==.Mahli:BAABNQAECoEbAAMPAAgKDBavGgCJAQAPAAYKDROvGgCJAQAcAAUKlRLRjgBcAQAAAA==.Mark:BAAANQABCgMIAwAAAA==.Marrias:BAABNQAECoEeAAIDAAcKURTcQAC0AQADAAcKURTcQAC0AQAAAA==.Massacre:BAAANQAECgQIBAABNQAECgQICQABAAAAAA==.Mawrix:BAABNQAECoEYAAMgAAcK1QpPIACkAQAgAAcKOQpPIACkAQAhAAYKOQomPABaAQAAAA==.Mawyai:BAAANQADCgQIBAAAAA==.Maxtheyare:BAAANQAECgEIAQAAAA==.',
Me='Mechchimy:BAAANQAECgMIBAABNQAECgYIFAAEAIEeAA==.Medîcus:BAAANQADCgIIAgAAAA==.Megumín:BAAANQAECgQIBAAAAA==.Meith:BAAANQADCgUIBgAAAA==.Melwazul:BAAANQADCgMJAwAAAA==.Melz:BAAANQAECgEIAgAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAACNQAFFIEJAAIiAAUKABVHAADaAQAiAAUKABVHAADaAQA1AAQKgSQAAyIACQodJYgAAKADACIACQodJYgAAKADAAIAAQoQDbRpADkAAAAA.Meyla:BAAANQADCgcJBgAAAA==.',
Mi='Mibby:BAAANQAECgUIBQABNQAECgIIAgABAAAAAA==.Mibs:BAABNQAECoEYAAIXAAgKEBj4VgBDAgAXAAgKEBj4VgBDAgAAAA==.Mickal:BAABNQAECoEaAAIRAAgKqwfqoQBuAQARAAgKqwfqoQBuAQAAAA==.Mikaelangelo:BAAANQAECgEJAQAAAA==.Mindrash:BAAANQAECgUIBQABNQAECgkJGgALAF8gAA==.Mip:BAAANQAECgIIAgAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAABNQAECoEZAAMNAAgK0xMXPgC2AQANAAcKxBEXPgC2AQAMAAYKThFCKwBcAQAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooter:BAABNQAECoEjAAIhAAkKFxdBEwCaAgAhAAkKFxdBEwCaAgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Mortincarne:BAAANQABCgIIAgAAAA==.',
Mu='Mushroom:BAAANQAECgYIDgAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAABNQAECoEZAAIIAAcK9hczOADmAQAIAAcK9hczOADmAQAAAA==.Naqilol:BAAANQAECgMIAwAAAA==.Narfox:BAAANQAECgUICgAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAABNQAECoEcAAIUAAgKRwptCgBvAQAUAAgKRwptCgBvAQAAAA==.Necrophyle:BAAANQAECgQIBgAAAA==.Nefarox:BAAANQAECgMIBwAAAA==.Neilion:BAAANQADCgMIAwAAAA==.Nerfslappy:BAAANQADCggIGgAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAABNQAECoEdAAMJAAgKVxb/PQA0AgAJAAgKVxb/PQA0AgAKAAcKaBhSWQCwAQAAAA==.Nightstealer:BAAANQAECgQIBAAAAA==.Nikkikayama:BAABNQAECoEhAAIEAAkKdCGTGgD8AgAEAAkKdCGTGgD8AgAAAA==.Nikol:BAAANQAECgcJEgABNQAECgkJGQAKAOUUAA==.',
No='Norikoff:BAACNQAFFIEGAAMYAAQKohIWAQDvAAAYAAMKdxEWAQDvAAAXAAIKhQ7uIwCFAAA1AAQKgRgAAxgACQroHcwCAP0CABgACQroHcwCAP0CABcACArVEcOIAK0BAAAA.',
Ny='Nyalla:BAAANQADCgcIGQAAAA==.',
['Nï']='Nïdalee:BAAANQAECgUIDgAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQAECgQIBAAAAA==.',
Of='Offdensen:BAAANQADCgcIGAAAAA==.',
Ok='Okkotsu:BAAANQAECgIIAwAAAA==.Okku:BAAANQAECgIIAwAAAA==.',
Ol='Oldmims:BAABNQAECoEcAAMfAAgKLhyNBQByAgAfAAgKLhyNBQByAgALAAQKbA7PLQHxAAAAAA==.Oldmimse:BAAANQADCggJCAABNQAECggIHAAfAC4cAA==.',
On='Onlybatfans:BAAANQAECgYICwAAAA==.',
Op='Ophina:BAAANQAECgMIBAAAAA==.',
Or='Oramu:BAAANQAECgcIDwAAAA==.Orangejello:BAAANQAECgUIDAAAAA==.Orion:BAAANQADCgMIAwABNQAFFAUIBgATAGcPAA==.Oriòn:BAAANQAECgMIBgAAAA==.Orpseroth:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.',
Ot='Otane:BAAANQAECgYJCgAAAA==.',
Pa='Paiah:BAAANQADCgYICAAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECggIFwAWALIYAA==.Pana:BAABNQAECoEaAAIOAAcK8w/SJABdAQAOAAcK8w/SJABdAQAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAAANQAECgUIDQAAAA==.Pannifer:BAAANQAECgUICgAAAA==.Paolon:BAAANQADCggIFAAAAA==.Papasmurph:BAAANQABCgIIAgAAAA==.Parple:BAAANQAECgUICgABNQAFFAUIDQAGALYaAA==.',
Pe='Penelopei:BAAANQAECgcICwAAAA==.',
Ph='Phantõm:BAAANQADCggIEgAAAA==.Philkulson:BAAANQAECgcIBwABNQAFFAYIDQADALkQAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgcIFwAAAA==.Porterah:BAAANQAECgYIBgAAAA==.Potbellypali:BAAANQABCgQIBgAAAA==.Poutyne:BAABNQAECoEhAAINAAgKfx9IGADZAgANAAgKfx9IGADZAgAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAECgkJJwATAI8hAA==.',
Pu='Punchnugget:BAAANQAECgQICAAAAA==.Punkvc:BAAANQAECgYIEwAAAA==.',
Py='Pyren:BAAANQADCggIGgAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.',
Qu='Quaeras:BAAANQAECgcIDwAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Ragingnoodle:BAAANQADCgQIBAABNQAECgYIEQABAAAAAA==.Ragingshnoz:BAABNQAECoEZAAIaAAcKBx/ECAB1AgAaAAcKBx/ECAB1AgAAAA==.Ragé:BAEBNQAECoEkAAMdAAkKJyMsCAA8AwAdAAgKciQsCAA8AwAFAAQKthyWQQBCAQAAAA==.Rakklock:BAAANQAECgIIAgAAAA==.Ralphe:BAAANQAECgUICgAAAA==.Rashygroin:BAAANQABCgYJBgABNQAECggIGwAfAN4cAA==.Raytow:BAAANQAECgYIDwAAAA==.Razelle:BAAANQAECgUICQAAAA==.',
Re='Reconpalymix:BAAANQAECgEIAgAAAA==.Relana:BAAANQAECgcIBwAAAA==.Remus:BAAANQAECggIBwAAAA==.Reshad:BAAANQAECgMIBwAAAA==.Ressix:BAABNQAECoEbAAIRAAgK+R1LOQClAgARAAgK+R1LOQClAgAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIBQABNQADCggIGAABAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECggIHAALAMkaAA==.Rizzwar:BAAANQAECgQIBQAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQADCggIGAAAAA==.Ronborules:BAAANQAECgQIBQAAAA==.Rosenta:BAAANQAECgUIDAAAAA==.',
Ru='Rumlock:BAAANQAECgQJBQAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIEgAAAA==.',
Sa='Sabinah:BAAANQAECgMIBAAAAA==.Sabing:BAAANQADCgcIGQAAAA==.Sacramento:BAAANQADCgMJAwAAAA==.Saeberis:BAAANQAECgQIBAAAAA==.Saiah:BAAANQAECgYICgAAAA==.Saintbazz:BAAANQAECgQIDQAAAA==.Sal:BAACNQAFFIENAAIGAAUKthouBAC1AQAGAAUKthouBAC1AQA1AAQKgSwAAgYACQqtJAwCALMDAAYACQqtJAwCALMDAAAA.Salivan:BAAANQAECgMIBwAAAA==.Sargaris:BAAANQAECgUIDAAAAA==.Sariva:BAACNQAFFIEKAAQPAAUKeR7kAwDNAAAPAAIKFCLkAwDNAAAcAAIK2BibHQClAAAjAAEKiCLVBABjAAA1AAQKgSUABBwACQqWIKVDAEcCABwABwqIIaVDAEcCAA8ABQrtFpghAFABACMABAr/GtEMAEABAAAA.Sathalis:BAAANQAECgQIBAAAAA==.Saurva:BAAANQAECgcIEgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgYIEgABAAAAAA==.Saxophone:BAABNQAECoEYAAITAAgKJhYRGwAPAgATAAgKJhYRGwAPAgAAAA==.Sayna:BAAANQAECgUIEQAAAA==.',
Sc='Scarecro:BAABNQAECoEaAAMOAAgK7x6jCwCdAgAOAAgK7x6jCwCdAgARAAMKshILCgGXAAAAAA==.',
Se='Sedae:BAABNQAECoEYAAIXAAgKOxkZTwBcAgAXAAgKOxkZTwBcAgAAAA==.Seekvaira:BAABNQAECoEZAAIJAAgKJB2HLwB8AgAJAAgKJB2HLwB8AgAAAA==.Seelenlos:BAAANQADCggIDwAAAA==.Seiya:BAAANQAECgcIDwAAAA==.Selira:BAAANQAECgUICwAAAA==.Selwynn:BAAANQADCggJCAAAAA==.Senji:BAAANQAECgMIAwAAAA==.Senseitots:BAAANQADCggICAAAAA==.Sevalina:BAABNQAECoEZAAIWAAgKbw4RVADMAQAWAAgKbw4RVADMAQAAAA==.',
Sh='Shadowstep:BAAANQAECgQIBAAAAA==.Shalaah:BAAANQAECgYIDwAAAA==.Shamhuntzu:BAEBNQAECoEZAAMdAAkKzxQBGwBJAgAdAAkKzxQBGwBJAgAkAAMKyAUuHQB/AAAAAA==.Shampaign:BAABNQAECoEbAAMKAAgKzB7QHgC7AgAKAAgKzB7QHgC7AgAJAAIKgRTa1AB4AAAAAA==.Shaoevoker:BAAANQAECgQIBAAAAA==.Sharnara:BAAANQAECgQIBAAAAA==.Shatterskull:BAAANQAECgQIBAAAAA==.Shazira:BAAANQAECgQIBAAAAA==.Shep:BAAANQAECgMIAwAAAA==.Sherloch:BAAANQADCgQIBQAAAA==.Shiftyrum:BAAANQAECgMIBAABNQAECgYIEgABAAAAAA==.Shmollboi:BAAANQABCgIIAgAAAA==.',
Si='Sideffects:BAABNQAECoEXAAIJAAgKwRb4NwBQAgAJAAgKwRb4NwBQAgAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAAANQAECgYIEwAAAA==.Silverlord:BAABNQAECoEaAAIVAAcKdhsVCgA4AgAVAAcKdhsVCgA4AgAAAA==.Sinafay:BAABNQAECoEYAAMfAAkKcwvxDACZAQAfAAkKcwvxDACZAQALAAEKuQKHogEiAAAAAA==.Sineu:BAAANQADCgcIBwABNQAECgkJJwATAI8hAA==.Siv:BAABNQAECoEnAAITAAkKjyH6BQBRAwATAAkKjyH6BQBRAwAAAA==.',
Sj='Sjor:BAAANQADCgIIAgAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQADCggIGwAAAA==.',
Sn='Snackkpack:BAAANQAECgIIAgAAAA==.Snapjutsu:BAABNQAECoEbAAMTAAgKnBUnHgDpAQATAAgKnBUnHgDpAQAVAAEKEBUrKQArAAAAAA==.Snorg:BAABNQAECoEbAAILAAgKxQe0xQCpAQALAAgKxQe0xQCpAQAAAA==.Snêaky:BAABNQAECoEUAAMhAAcKSh7bFwBtAgAhAAcKSh7bFwBtAgAgAAEK5QmmRQA5AAAAAA==.',
So='Solarnova:BAAANQAECgUIDQAAAA==.Solorn:BAAANQAECgcIGAAAAQ==.',
Sp='Splash:BAAANQAECgEIAQAAAA==.Spygon:BAAANQAECgUIDAAAAA==.',
St='Strobila:BAAANQAECgYIEAAAAA==.Studdmuffin:BAABNQAECoEYAAMDAAkKKiHsLgAbAgADAAgK/BvsLgAbAgAlAAUKXCEzNgCSAQAAAA==.',
Su='Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAAANQAECgcIEgAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Sylvië:BAAANQAECggIAgAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAABNQAECoEZAAIIAAcKVR0fJgBUAgAIAAcKVR0fJgBUAgAAAA==.Syrathos:BAACNQAFFIEUAAMdAAcK3xfqAACQAgAdAAcK3xfqAACQAgAFAAEKrR3MEgBbAAA1AAQKgSkAAx0ACQrrI1MEAIMDAB0ACQrrI1MEAIMDAAUAAgpiGrVcAJ4AAAAA.Syrioforel:BAAANQAECgEIAgAAAA==.',
Ta='Taojîn:BAABNQAECoEYAAIZAAkKfQyDRwAGAgAZAAkKfQyDRwAGAgAAAA==.Tarted:BAAANQAECgQIBQAAAA==.Tatèrdots:BAAANQABCgMIBwAAAA==.',
Te='Teclis:BAABNQAECoEcAAILAAkKFCE1QADkAgALAAkKFCE1QADkAgAAAA==.Telzindrov:BAAANQAECgcIDwAAAA==.Terrorwithin:BAAANQAECgUICwAAAA==.',
Th='Thalgar:BAAANQAECgIIAgAAAA==.Thalmick:BAABNQAECoEjAAIgAAgK2hh8DwBjAgAgAAgK2hh8DwBjAgAAAA==.Thanoslye:BAAANQAECgEIAQAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Thogarn:BAAANQAECgUICwAAAA==.Thunderkat:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Thundertem:BAAANQAECgQIBAAAAA==.Théière:BAABNQAECoEcAAIbAAgKkBOPEAARAgAbAAgKkBOPEAARAgAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUJDQABAAAAAA==.Tinychimy:BAAANQADCgQIBAABNQAECgYIFAAEAIEeAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAABNQAECoEXAAILAAgKOxArpADxAQALAAgKOxArpADxAQABNQAECgkJGgAQALgbAA==.',
To='Tofper:BAAANQADCgYIBgAAAA==.Toughlove:BAAANQAECgIIAgAAAA==.',
Tr='Trev:BAABNQAECoEXAAMLAAgKDx/rVACtAgALAAgKDx/rVACtAgAfAAEKUB/1MQBHAAAAAA==.Trustfäll:BAAANQAECgQIBAAAAA==.',
Ts='Tsunãmi:BAABNQAECoEiAAMKAAkKkxnSJQCTAgAKAAkKkxnSJQCTAgAmAAgKlQ+XEAAYAgAAAA==.',
Tu='Tuc:BAAANQAECgYICwAAAA==.',
Ty='Tyndareos:BAAANQADCgUIBgAAAA==.Typhoontravv:BAABNQAECoEdAAMOAAkKSRz3CwCYAgAOAAkK/xv3CwCYAgARAAQKrhyfyAAWAQAAAA==.',
['Tø']='Tøkakagé:BAAANQAECgUIDAAAAA==.',
Uf='Ufearme:BAAANQADCggIGwAAAA==.',
Ug='Ugabooga:BAABNQAECoEpAAILAAkKeR5HLAAdAwALAAkKeR5HLAAdAwAAAA==.Uggon:BAAANQAECgMIBwAAAA==.',
Un='Unable:BAAANQAECgUICgAAAA==.',
Ur='Urrikahn:BAAANQADCgcIDgAAAA==.',
Ut='Uthur:BAAANQAECgYIDgAAAA==.Utterchaos:BAABNQAECoEZAAMcAAkKtBQkawDFAQAcAAgKmRIkawDFAQAPAAQK/Ap5OgDDAAAAAA==.',
Va='Vaelaven:BAABNQAECoEaAAINAAgKdA7LOgDMAQANAAgKdA7LOgDMAQAAAA==.Valack:BAAANQAECgMIAwAAAA==.Valfore:BAABNQAECoEgAAIIAAgK5SGdEQD5AgAIAAgK5SGdEQD5AgAAAA==.Valizor:BAAANQAECgUIDAAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAAANQAECgYICQAAAA==.Vayle:BAAANQADCggIDgABNQAECggIHAAEAModAA==.',
Ve='Velaara:BAAANQADCggICgAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vestoris:BAAANQADCgYIFQAAAA==.Vetta:BAABNQAECoEWAAIKAAkKTBHbUADQAQAKAAkKTBHbUADQAQAAAA==.',
Vg='Vger:BAAANQADCggJEwAAAA==.',
Vi='Vieora:BAAANQADCgYIBgAAAA==.Vikvikvik:BAAANQADCgYICwAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgcIBwAAAA==.',
Vo='Volgagrad:BAAANQAECgIIAgAAAA==.Vond:BAAANQABCgIJAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQAECgMIAwABAAAAAA==.',
Wa='Wardum:BAAANQAECgUIBgAAAA==.Watt:BAAANQADCggICAABNQAECgkJJwATAI8hAA==.Wazul:BAAANQADCgcIGAAAAA==.',
Wh='Whisp:BAAANQAECgIIAgAAAA==.Whitearrows:BAABNQAECoEgAAMEAAkKPBv/HQDqAgAEAAkKPBv/HQDqAgACAAQK0w50QwDUAAAAAA==.Whitespell:BAAANQAECggIEwABNQAECgkJIAAEADwbAA==.',
Wi='Wickfel:BAAANQAECgQIBAAAAA==.Wicus:BAAANQADCggICAAAAA==.',
Wy='Wyldfarmer:BAAANQAECgQIBAAAAA==.',
Xa='Xanid:BAAANQAECgQICQAAAA==.',
Xd='Xdwarf:BAAANQAECgYIBgABNQAECggIGwAhAGsRAA==.',
Xe='Xeroxoxo:BAABNQAECoEgAAIDAAkKFB+VEgDwAgADAAkKFB+VEgDwAgAAAA==.Xevric:BAAANQAECggIAwAAAA==.',
Xi='Xieren:BAAANQAECgMIBQABNQAECgQICQABAAAAAA==.',
Xo='Xoz:BAAANQAECgQIBAAAAA==.',
Ya='Yasman:BAAANQADCggIEAAAAA==.',
Ym='Ymedead:BAAANQAECggIEgABNQAECgkJHwAEAPkjAA==.',
Yo='Yoroichi:BAABNQAECoEbAAIhAAgKaxFrIgASAgAhAAgKaxFrIgASAgAAAA==.Yourmomsride:BAABNQAECoEYAAILAAgKCgcKywCeAQALAAgKCgcKywCeAQAAAA==.Youtube:BAAANQAECggIEwAAAA==.',
Yu='Yueyue:BAAANQAECgcIDwAAAA==.Yungtwizzler:BAAANQADCggIDwABNQAECgQIBAABAAAAAA==.',
['Yá']='Yáng:BAAANQAECgQIDQAAAA==.',
Za='Zarylathanea:BAABNQAECoEZAAIEAAYKTQY3rgA9AQAEAAYKTQY3rgA9AQAAAA==.',
Ze='Zenheals:BAAANQAECggIAgAAAA==.Zeroskills:BAAANQAECgYIBgAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQAECgQIDQAAAA==.Zoog:BAABNQAECoEaAAIZAAkKgRzOGgDeAgAZAAkKgRzOGgDeAgAAAA==.',
Zy='Zyrana:BAAANQADCgMIBQAAAA==.Zyridal:BAABNQAECoEYAAILAAcK6QHGKwH0AAALAAcK6QHGKwH0AAAAAA==.Zyvara:BAAANQAECgUICwAAAA==.',
['Zä']='Zärèlíä:BAACNQAFFIEGAAITAAMKzgzMCADGAAATAAMKzgzMCADGAAA1AAQKgT0AAhMACQo0I/4DAH4DABMACQo0I/4DAH4DAAE1AAQKCQkZABEArRwA.',
['Äp']='Äpples:BAAANQAECgEIAgAAAA==.',
['Æz']='Æz:BAABNQAECoEXAAIFAAgKBRG7KwDtAQAFAAgKBRG7KwDtAQAAAA==.',
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
