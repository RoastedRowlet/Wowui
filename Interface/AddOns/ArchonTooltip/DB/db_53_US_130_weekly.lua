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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','DemonHunter-Vengeance','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Druid-Restoration','Druid-Balance','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','Rogue-Assassination','Paladin-Retribution','Evoker-Preservation','Rogue-Subtlety','Monk-Windwalker','Evoker-Devastation','Mage-Frost','Druid-Feral','Monk-Brewmaster','Warrior-Arms','Rogue-Outlaw','Paladin-Holy','Warrior-Protection','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Survival','Druid-Guardian','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abonde:BAAANQAECgQICQAAAA==.Abraxes:BAABNQAECn8YAAIBAAYKMhWLpgC0AQABAAYKMhWLpgC0AQAAAA==.',
Ac='Acidemon:BAAANQAECgcIEwAAAA==.',
Ad='Adalaide:BAABNQAECn8XAAMCAAYK+Az4vABOAQACAAYK+Az4vABOAQADAAIKZAa8ZQBWAAAAAA==.Adannis:BAAANQAECgIIAgABNQAECggIHAAEAOMRAA==.Adelane:BAAANQAECgEIAQABNQAECgUIEQAFAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAABNQAECn8aAAMGAAYKSSB/VwAYAgAGAAYKSSB/VwAYAgAHAAEKAAD+bQBKAAAAAA==.Aethas:BAAANQAECgEIAQAAAA==.',
Af='Affective:BAABNQAECn8lAAIIAAkKTxsjEgDRAgAIAAkKTxsjEgDRAgABNQAFFAcIGAAJAHQTAA==.Afkk:BAAANQADCggIBAABNQAECggICgAFAAAAAA==.',
Ah='Ahuramazda:BAAANQAFFAIIBAAAAA==.',
Ai='Aidard:BAAANQABCggIDwAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aishari:BAAANQADCggIAQAAAA==.Aizlyn:BAAANQADCggIJAAAAA==.',
Ak='Akio:BAABNQAECn8sAAIBAAkKsyJJCgCLAwABAAkKsyJJCgCLAwAAAA==.',
Al='Aldarya:BAAANQAECgUIDgAAAA==.Alisara:BAABNQAECn81AAIBAAkKeyU4BgCtAwABAAkKeyU4BgCtAwAAAA==.Alish:BAAANQADCggIFwAAAA==.Allexx:BAABNQAECn8rAAIBAAkKIBt2MwDPAgABAAkKIBt2MwDPAgAAAA==.Allyssel:BAACNQAFFH8bAAIKAAYKJiBvAwBKAgAKAAYKJiBvAwBKAgA1AAQKfy0AAgoACQq9JvMBANoDAAoACQq9JvMBANoDAAAA.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAACNQAFFH8KAAIHAAUKHBq9BgCuAQAHAAUKHBq9BgCuAQA1AAQKfx0AAwcACQo6HVwVALICAAcACQo6HVwVALICAAsAAwoZDowZAJ0AAAAA.Amazinggrace:BAABNQAECn8kAAMMAAgKpREdUACxAQAMAAgKlxEdUACxAQAJAAcKFA0BawBjAQAAAA==.Amentiu:BAAANQADCgUICAABNQAECgcIIAANAJ0FAA==.Ammathendis:BAAANQADCgQIBAABNQAECgUICwAFAAAAAA==.Ammiel:BAAANQADCgEIAQABNQAFFAMICAAMAL0ZAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQAECgYIEAAAAA==.Angeal:BAABNQAECn8fAAIBAAcK4iBzPwCqAgABAAcK4iBzPwCqAgAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAABNQAECn8kAAMOAAcK4hGLfQCnAQAOAAcK4hGLfQCnAQAPAAUK/BYSlQBPAQAAAA==.Annamei:BAAANQAECgYIEwAAAA==.',
Ao='Aoife:BAAANQAECgYIEgAAAA==.Aorina:BAABNQAECn8uAAIQAAkKlhj5XgDBAgAQAAkKlhj5XgDBAgAAAA==.',
Ar='Arazalor:BAABNQAECn8qAAMRAAgKCQ6ZLwCaAQARAAgKCQ6ZLwCaAQASAAUKewPhiQCoAAAAAA==.Arcangel:BAACNQAFFH8LAAIRAAUKaxmrBQC2AQARAAUKaxmrBQC2AQA1AAQKfyIAAxEACQqwJCkFAG4DABEACQqwJCkFAG4DABIAAQoAAGenAEUAAAAA.Arrash:BAAANQADCgYICwABNQAECggIGgATAOcXAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAABNQAECn8kAAIOAAgKmSLpHwAKAwAOAAgKmSLpHwAKAwAAAA==.Arysa:BAAANQADCgUIBQAAAA==.',
As='Ashara:BAABNQAECn8pAAIUAAgKThOBJQCwAQAUAAgKThOBJQCwAQAAAA==.Ashenrain:BAAANQAECgUICgAAAA==.Ashvia:BAAANQAECgQICQAAAA==.Aspiration:BAAANQADCgYIBgAAAA==.',
At='Atheren:BAABNQAECn8gAAIOAAgKuxOWVgAcAgAOAAgKuxOWVgAcAgAAAA==.Athshu:BAAANQAECgQIBAAAAA==.Atulan:BAAANQAECgcIEAAAAA==.',
Au='Auntiemimi:BAAANQAECgQIDwAAAA==.',
Av='Avalina:BAABNQAECn8ZAAIGAAcKWxS8bADTAQAGAAcKWxS8bADTAQABNQAFFAYIDwADAPkhAA==.Avannar:BAAANQADCgcIHAAAAA==.Avelyn:BAAANQAECggICQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQAECgYIDAAAAA==.',
Ay='Ayani:BAABNQAECn8iAAMHAAkKRw/YKgDNAQAHAAgKiw3YKgDNAQAGAAcKkwwYkgBbAQAAAA==.',
Az='Azrine:BAAANQAECgYIBgAAAA==.',
Ba='Babymanowood:BAAANQADCgcJBwAAAA==.Baddattitude:BAAANQADCggIGAABNQAECgQICAAFAAAAAA==.Baddkharma:BAAANQAECgQIBwAAAA==.Badras:BAAANQAECgYIEgAAAA==.Bagelz:BAACNQAFFH8LAAIVAAUKcBq5AwCxAQAVAAUKcBq5AwCxAQA1AAQKfx0AAhUACQpBIY0KANsCABUACQpBIY0KANsCAAAA.Balforyn:BAAANQAECgUIBQAAAA==.Bathomula:BAABNQAECn8fAAIDAAcKhhokDQAlAgADAAcKhhokDQAlAgAAAA==.Bayla:BAAANQADCgUIBQABNQAFFAcIIAAVAE4VAA==.Bazza:BAAANQADCgYIBgABNQAECgUIEQAFAAAAAA==.Bazzwar:BAAANQADCggICwABNQAECgUIEQAFAAAAAA==.',
Be='Beric:BAACNQAFFH8GAAIWAAMKexFVDwDvAAAWAAMKexFVDwDvAAA1AAQKfxgAAhYACQq7GxYWAMgCABYACQq7GxYWAMgCAAAA.Betadine:BAAANQAECgUIBwAAAA==.Bexy:BAABNQAECn8lAAIPAAkKZxjlOAB5AgAPAAkKZxjlOAB5AgAAAA==.',
Bl='Blade:BAABNQAECn8rAAIKAAgKhAgsRgCPAQAKAAgKhAgsRgCPAQAAAA==.',
Bo='Boldan:BAAANQADCgIIAwAAAA==.Boohaha:BAABNQAECn8mAAMPAAgKWh1pMACdAgAPAAgKWh1pMACdAgAOAAEKAACZJgE+AAAAAA==.Boolabear:BAAANQADCgIIBAAAAA==.Booze:BAAANQAECgMIAwABNQAECggIAwAFAAAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAABNQAECn8hAAIXAAgKuiHESAC3AgAXAAgKuiHESAC3AgAAAA==.Bowmistress:BAAANQAECgEIAQAAAA==.',
Br='Brightwing:BAACNQAFFH8IAAIYAAQKbRFnDQA0AQAYAAQKbRFnDQA0AQA1AAQKfy8AAhgACQoAHywJAA8DABgACQoAHywJAA8DAAAA.Brigorath:BAAANQAECgUICgAAAA==.Brokenarro:BAAANQAECgMIBAAAAA==.',
Bu='Bubblebae:BAAANQAECgQICwABNQAECggIGwAPAO0gAA==.Bullshivek:BAABNQAECn8bAAIRAAgK2RP8JgDmAQARAAgK2RP8JgDmAQAAAA==.Buurz:BAAANQADCggICAAAAA==.',
Ca='Caale:BAABNQAECn8ZAAIZAAcKyQ7+IgCvAQAZAAcKyQ7+IgCvAQAAAA==.Caecus:BAABNQAECn8bAAIMAAgKoBiSNAA4AgAMAAgKoBiSNAA4AgAAAA==.Callsaul:BAEANQAECgMICQAAAA==.Casmus:BAAANQADCgYIBgABNQAECgYIEgAFAAAAAA==.Caylissa:BAAANQAECgQIDQAAAA==.',
Ce='Celryth:BAAANQADCgYIBwAAAA==.Cenvoked:BAABNQAECn8iAAIYAAgKWA6lIQC+AQAYAAgKWA6lIQC+AQAAAA==.Cepha:BAAANQADCggIDAAAAA==.',
Ch='Charbethicc:BAAANQAECgUIDgABNQAECgcIFAACAJAbAA==.Charlicious:BAABNQAECn8UAAICAAcKkBtZXQA8AgACAAcKkBtZXQA8AgAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgcIFAACAJAbAA==.Charticulous:BAAANQADCgUIBQABNQAECgcIFAACAJAbAA==.Cheylia:BAAANQAECgcIEwAAAA==.Chijoku:BAABNQAECn8xAAISAAkKhRCoOwATAgASAAkKhRCoOwATAgAAAA==.Chimster:BAABNQAECn8cAAIBAAYKbyAvcQAsAgABAAYKbyAvcQAsAgAAAA==.Chimydakilla:BAAANQAECgUIBwABNQAECgYIHAABAG8gAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggJCAAAAA==.',
Co='Corvò:BAABNQAECn8fAAIQAAgK9xomjQBkAgAQAAgK9xomjQBkAgAAAA==.',
Cr='Craeus:BAABNQAECn8kAAIPAAgKVh57LQCqAgAPAAgKVh57LQCqAgAAAA==.Cralk:BAAANQAECgcIDgABNQAECgkJHQAXAKIfAA==.Cranked:BAAANQAECggIEwABNQAFFAMICAAaADoaAA==.Crine:BAAANQAECgUIBQABNQAECgkJKQAbAD8WAA==.',
Cy='Cyonarah:BAAANQAECgUIEAAAAA==.',
Da='Damandred:BAAANQADCgYIBgAAAA==.Darem:BAAANQAECgcIDgAAAA==.',
De='Deadcenter:BAAANQAECgEIAQAAAA==.Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgUIEAAAAA==.Deidra:BAAANQAECgMIBgAAAA==.Deigh:BAAANQADCggIBwAAAA==.Dek:BAAANQAECgUIBwAAAA==.Demons:BAAANQABCggIEQAAAA==.Devilette:BAAANQADCgQIBQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAABNQAECn8qAAIBAAkKZiM3CwCDAwABAAkKZiM3CwCDAwAAAA==.Diggi:BAAANQAECgcIEAAAAA==.Diosa:BAABNQAECn8tAAIDAAkK9BGfBgCgAgADAAkK9BGfBgCgAgAAAA==.Divinekat:BAAANQAECgUICgAAAA==.Dizza:BAAANQAECgIIBQAAAA==.',
Dk='Dkagon:BAABNQAECn8aAAIMAAcKPBctTQC+AQAMAAcKPBctTQC+AQAAAA==.',
Do='Docholiday:BAAANQAECgUIBQAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQAECgcIEAAAAA==.Dooderonomy:BAABNQAECn8bAAMGAAgK/Rg7RgBRAgAGAAgK/Rg7RgBRAgALAAEKKBOUJgA6AAAAAA==.Doria:BAAANQADCgQIBAAAAA==.',
Dr='Dragaan:BAABNQAECn8cAAIcAAgKghDEDQDQAQAcAAgKghDEDQDQAQAAAA==.Dragonbait:BAABNQAECn9SAAIXAAkK5iIgGQBeAwAXAAkK5iIgGQBeAwAAAA==.Dragonoodles:BAAANQAECgYIEQAAAA==.Dragonzbane:BAABNQAECn8fAAIXAAcKLBDCvgCZAQAXAAcKLBDCvgCZAQAAAA==.Dranosh:BAAANQADCgUIBQABNQAECgQIBAAFAAAAAA==.Dreadmage:BAAANQAECgYIBgABNQAECgkJKgAdAOAYAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAwABNQAECgYICAAFAAAAAA==.Drekthanas:BAAANQAECgYICAAAAA==.Drenea:BAAANQADCgcIGQAAAA==.Drimlek:BAAANQADCgEIAQAAAA==.Drin:BAABNQAECn8dAAIQAAcKhgws8QClAQAQAAcKhgws8QClAQAAAA==.',
Du='Duplicitous:BAAANQADCgcJBwAAAA==.',
Dy='Dyriana:BAAANQADCgcIFgAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAABNQAECn8bAAIeAAcKXhOaFQCGAQAeAAcKXhOaFQCGAQAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQAECgUIEQAAAA==.Ellewoods:BAAANQADCggIDwABNQAECgMIAwAFAAAAAA==.Eloise:BAAANQAECgYIBgAAAA==.Eltria:BAACNQAFFH8LAAIQAAUKKRLBGgCgAQAQAAUKKRLBGgCgAQA1AAQKfx0AAhAACQpWI41HAPQCABAACQpWI41HAPQCAAAA.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAABNQAECn8kAAIGAAgKdxvmQwBZAgAGAAgKdxvmQwBZAgAAAA==.',
Er='Eric:BAAANQAECgIIAgABNQAECgcIHAAfAOUcAA==.Erid:BAAANQAECgYIBgAAAA==.Erverlyn:BAAANQADCgQIBAAAAA==.',
Es='Essential:BAACNQAFFH8KAAITAAUKnAwQAQBsAQATAAUKnAwQAQBsAQA1AAQKfx0AAhMACQpiIdsEAOACABMACQpiIdsEAOACAAAA.',
Ex='Exces:BAAANQADCgUIBQAAAA==.Exicor:BAAANQAECgUIBwABNQAECgkJJwAQAHQbAA==.',
Ez='Ezalth:BAAANQADCggIHgAAAA==.Ezz:BAAANQADCggJDwAAAA==.',
Fa='Fachzile:BAAANQADCgQIBAAAAA==.Faden:BAABNQAECn8YAAIgAAkKmB5LAwAAAwAgAAkKmB5LAwAAAwABNQAFFAMICAAaADoaAA==.Faenara:BAABNQAECn8pAAMhAAgKBRstOgB5AgAhAAgKBRstOgB5AgAXAAgK1RD2mgDoAQAAAA==.Falafelguy:BAABNQAECn8rAAIQAAgKnh8ngAB+AgAQAAgKnh8ngAB+AgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwABNQAECgQICQAFAAAAAA==.Faruqq:BAABNQAECn8pAAMiAAgK0h2ZCwB+AgAiAAgK0h2ZCwB+AgAfAAgKqQu+oQDEAQAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECggIKwAQAJ4fAA==.Felartamiel:BAAANQADCgcIGgAAAA==.Felii:BAAANQAECgEIAQAAAA==.Felkieler:BAAANQADCgYICAABNQAECgUICgAFAAAAAA==.Fey:BAAANQAECgUICgAAAA==.',
Fi='Firêstorm:BAAANQAECggIBgAAAA==.Fishron:BAABNQAECn8bAAIfAAgK5RGphgAHAgAfAAgK5RGphgAHAgAAAA==.',
Fl='Flaz:BAACNQAFFH8IAAISAAMKBxZHFwDvAAASAAMKBxZHFwDvAAA1AAQKfyEAAhIACQp9G24pAIkCABIACQp9G24pAIkCAAAA.Fleury:BAAANQABCgUIBAAAAA==.',
Fo='Forestspirit:BAABNQAECn8aAAIRAAgKZA8TKwDBAQARAAgKZA8TKwDBAQAAAA==.Fourneau:BAAANQADCggJCAABNQAECgkJLQAbAKQVAA==.Fourseasons:BAAANQADCgIIAgAAAA==.',
Fr='Frawda:BAABNQAECn8YAAMfAAcKBgjGxwBiAQAfAAcKBgjGxwBiAQATAAQKdARCJACMAAAAAA==.',
Fu='Fusillidari:BAAANQAECgUIDwABNQAECgYIEQAFAAAAAA==.Fuzzy:BAAANQAECggIBgAAAA==.',
Ga='Galaxyman:BAAANQADCggIEQAAAA==.Garlone:BAAANQABCgcIBwAAAA==.',
Ge='Geist:BAACNQAFFH8KAAMXAAUK5BEKDACEAQAXAAUK5BEKDACEAQAUAAEKAAA1EwAyAAA1AAQKfxsAAhcACQr/I9g5AOcCABcACQr/I9g5AOcCAAAA.Geraith:BAACNQAFFH8KAAIMAAUKsRINEABPAQAMAAUKsRINEABPAQA1AAQKfxoAAgwACQr2HjkgAK8CAAwACQr2HjkgAK8CAAAA.Gerios:BAABNQAECn8pAAIBAAgKNR1zQACnAgABAAgKNR1zQACnAgAAAA==.Getafix:BAAANQADCgQIBAAAAA==.Getmadbro:BAAANQAECgMIAwAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQAECgcICwAAAA==.',
Gl='Glacier:BAAANQABCgYICAAAAA==.Glaedyr:BAAANQADCgEIAQABNQAECgkJKAAVAGQVAA==.Glendra:BAABNQAECn8pAAIUAAgKVRbuGQAgAgAUAAgKVRbuGQAgAgAAAA==.Glorificus:BAAANQADCggJDgAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAABNQAECn8aAAMbAAgK7gjfIABJAQAbAAcKjAjfIABJAQAjAAUKoAj9EwDrAAAAAA==.Greensleeves:BAAANQADCgcIGAAAAA==.Gregoriusz:BAABNQAECn86AAIIAAkKWh4YDwDzAgAIAAkKWh4YDwDzAgABNQAFFAIIAgAFAAAAAA==.Greygon:BAAANQADCggICAABNQAECggIHwABAMQaAA==.Greygull:BAAANQAECgQICAAAAA==.Grimfrost:BAAANQABCgIIAgAAAA==.Grue:BAAANQADCgQIBAABNQAECgYIBwAFAAAAAA==.Grunin:BAAANQADCggIDwAAAA==.',
Gu='Guinness:BAABNQAECn8dAAIXAAgKLw1qtACwAQAXAAgKLw1qtACwAQAAAA==.Guntank:BAABNQAECn8tAAMfAAkKjhddYwBhAgAfAAkKjhddYwBhAgATAAUKSxQ3FwApAQAAAA==.',
Ha='Halistarr:BAAANQADCgIIAgAAAA==.Hategnomer:BAAANQADCgcIGQAAAA==.Havenfell:BAABNQAECn8eAAIiAAgKtyFcBgD+AgAiAAgKtyFcBgD+AgAAAA==.Hawkfist:BAABNQAECn8pAAIBAAgK0BjYYQBQAgABAAgK0BjYYQBQAgAAAA==.',
He='Hercules:BAACNQAFFH8LAAIJAAUKNhNpDABEAQAJAAUKNhNpDABEAQA1AAQKf0QAAgkACQovJHIGAJMDAAkACQovJHIGAJMDAAAA.Hervo:BAAANQAECgIIAgAAAA==.Herzagon:BAAANQAECgMIBQAAAA==.',
Hi='Hierodoulos:BAABNQAECn8tAAIRAAkKwCXAAADYAwARAAkKwCXAAADYAwAAAA==.',
Ho='Holykat:BAAANQADCggICwABNQAECgUICgAFAAAAAA==.Homiefrost:BAAANQABCgMIAwAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgUIDAAAAA==.',
Hr='Hroth:BAABNQAECn8oAAIVAAkKZBW1EwA8AgAVAAkKZBW1EwA8AgAAAA==.Hrothgar:BAAANQADCgIIAgABNQAECgkJKAAVAGQVAA==.',
Hu='Hunteroni:BAAANQAECgUIBwABNQAECgYIEQAFAAAAAA==.',
['Hè']='Hèalsplz:BAAANQAECgEIAgAAAA==.',
Ia='Ianos:BAAANQAECgYIEQAAAA==.',
Ic='Icenea:BAAANQAECgEIAQABNQAECgkJNQABAHslAA==.',
If='Ifearu:BAAANQADCgYIBgABNQAECgMIBAAFAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQAECgcIDgAAAA==.',
Ik='Ikthus:BAABNQAECn8cAAIEAAgK4xGGBwAhAgAEAAgK4xGGBwAhAgAAAA==.',
Il='Illtud:BAAANQAECgQICwAAAA==.Ilyessa:BAACNQAFFH8OAAIaAAUKoxWRBgCWAQAaAAUKoxWRBgCWAQA1AAQKfyUAAhoACQrWIaEKACcDABoACQrWIaEKACcDAAAA.',
Im='Impastable:BAAANQADCgEIAQABNQAECgYIEQAFAAAAAA==.',
Ir='Irisha:BAAANQAECgEIAQAAAA==.Ironfur:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.Ironpipes:BAAANQAECgUICwAAAA==.',
Is='Iskrå:BAAANQAECgQICQAAAA==.',
Ja='Jacynth:BAAANQAECgYIDAAAAA==.Jaimers:BAABNQAECn8qAAMGAAgKWCOCFAApAwAGAAgKWCOCFAApAwALAAEKVwf1LQAoAAAAAA==.Jardinn:BAABNQAECn8bAAMPAAgK7SBpNACLAgAPAAcKSCBpNACLAgAOAAcK0B8fRgBaAgAAAA==.Jaxen:BAABNQAECn8ZAAMDAAYK/gqLPQDLAAACAAUK9AbY+wDOAAADAAQKiwmLPQDLAAAAAA==.Jaxon:BAAANQAECgUICgAAAA==.Jaywilde:BAABNQAECn9AAAMfAAkK7BqXQwC8AgAfAAkK7BqXQwC8AgATAAEKVAWyNAAvAAAAAA==.',
Je='Jenne:BAAANQADCgYIBgAAAA==.Jerkpaladin:BAAANQADCggIFgAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.Jetsetradio:BAAANQAECgQIBAAAAA==.',
Ji='Jizakazam:BAAANQAECgYIDwAAAA==.',
Jo='Jojobeanice:BAAANQADCggIBwABNQAECgcIEwAFAAAAAA==.Josepha:BAAANQADCgUICQAAAA==.',
Ju='Juggyspally:BAABNQAECn8lAAIXAAgKWRJ3kQD9AQAXAAgKWRJ3kQD9AQAAAA==.Julls:BAAANQAECgEIAgAAAA==.Justbringit:BAEANQAECgEIAQABNQAFFAMIBgAkAMUWAA==.Juvens:BAAANQABCgMIAQAAAA==.',
['Jï']='Jïao:BAAANQAFFAEIAgAAAA==.',
Ka='Kairiccars:BAAANQADCgYIBgAAAA==.Karaine:BAAANQAECgcIBwAAAA==.Karoc:BAAANQADCgUIBwABNQAECggIHgAJAHIeAA==.Karot:BAAANQADCggICAABNQAECggIHgAJAHIeAA==.Karotten:BAABNQAECn8eAAIJAAgKch5cKgCLAgAJAAgKch5cKgCLAgAAAA==.Karthair:BAABNQAECn8ZAAMYAAgKnAysIwClAQAYAAgKnAysIwClAQAbAAYKDg2XJQAKAQAAAA==.Kassoa:BAABNQAECn8dAAIfAAgK5xuaUgCPAgAfAAgK5xuaUgCPAgAAAA==.Kaszim:BAABNQAECn80AAMBAAkKCyY6AQD1AwABAAkKCyY6AQD1AwAIAAEKzAf8kQAsAAAAAA==.',
Ke='Keello:BAABNQAECn8aAAIhAAkK/QPutAAQAQAhAAkK/QPutAAQAQAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kenz:BAABNQAECn8YAAIlAAgKjA7FBgAfAgAlAAgKjA7FBgAfAgAAAA==.Keresis:BAAANQADCgcIBwAAAA==.Kernelsandrs:BAACNQAFFH8GAAIBAAQKRxVNEQBEAQABAAQKRxVNEQBEAQA1AAQKfyMAAwEACQrNJG8rAOoCAAEACQrNJG8rAOoCAAgAAwpHCU5qAH8AAAAA.',
Kh='Khazzangruel:BAAANQAECgMIAwAAAA==.',
Ki='Kileena:BAAANQADCgQIBAABNQAECgkJKAAVAGQVAA==.Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQAECgcIEAAAAA==.Kirinmaruu:BAAANQAECgUIEAAAAA==.Kirisatsu:BAAANQAECgQIDQAAAA==.Kisatchie:BAABNQAECn8bAAImAAcKWBiDGADjAQAmAAcKWBiDGADjAQAAAA==.',
Ko='Koalitsiya:BAAANQAECgUICgAAAA==.Koko:BAAANQADCgQIBAAAAA==.Koyoshial:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.Kozãk:BAAANQADCggIFwAAAA==.',
Kr='Kreatos:BAAANQAECgQIEQAAAA==.Krimez:BAABNQAECn8pAAMbAAkKPxYkEgAtAgAbAAgKKxYkEgAtAgAjAAcKvBArDgBiAQAAAA==.Kromdus:BAAANQAECgIIAgABNQAECggIEwAFAAAAAA==.Krynez:BAAANQADCgUIEAABNQAECgkJKQAbAD8WAA==.',
Ku='Kuthalyoni:BAAANQADCgEIAQAAAA==.',
Ky='Kyrhios:BAABNQAECn8eAAITAAgKkCD4BADbAgATAAgKkCD4BADbAgAAAA==.',
['Kà']='Kàkarot:BAAANQADCgEJAQAAAA==.',
['Kä']='Käggai:BAAANQAFFAMIAwAAAA==.',
['Kò']='Kòld:BAABNQAECn8qAAIdAAkK4Bi/CADCAgAdAAkK4Bi/CADCAgAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Laindra:BAAANQAECgEIAQAAAA==.Lana:BAAANQAECgQIBgAAAA==.Lark:BAABNQAECn8dAAIiAAgKghQFFwC3AQAiAAgKghQFFwC3AQAAAA==.Larthas:BAABNQAECn8iAAIlAAgKABXuBQBJAgAlAAgKABXuBQBJAgAAAA==.Lary:BAAANQAECgYICgABNQAFFAQIDgAUAKIYAA==.Lascie:BAABNQAECn8lAAMcAAgKBh3rBwBpAgAcAAgKBh3rBwBpAgAQAAIKDAkaqAFpAAAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQAECgUICgAFAAAAAA==.Leaila:BAAANQAECgUICwAAAA==.Leiha:BAAANQADCggIFAAAAA==.',
Li='Liams:BAAANQADCgcIGAAAAA==.Lidless:BAABNQAECn8nAAIQAAkKdBseVQDWAgAQAAkKdBseVQDWAgAAAA==.Linux:BAABNQAECn8bAAMBAAgKMxGreAAaAgABAAgKMxGreAAaAgAIAAEKAAAPjwAvAAAAAA==.',
Ll='Llamadin:BAABNQAECn8ZAAIUAAgK+xugFgBFAgAUAAgK+xugFgBFAgAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.Lohof:BAAANQABCgIIAgAAAA==.Lovelorn:BAAANQAECgUICgAAAA==.',
Lu='Luckÿ:BAAANQAECgEIAQABNQAECgkJHAABAGsiAA==.Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAABNQAECn8nAAMbAAgKWh3TCgC8AgAbAAgKWh3TCgC8AgAYAAEKBwMYUgAmAAAAAA==.Lunah:BAAANQADCgIIAgAAAA==.',
Ly='Lynra:BAAANQAECgQIBQAAAA==.Lytol:BAAANQAECgQIBAAAAA==.',
Ma='Macloc:BAAANQAECgQJBwAAAA==.Maggiemae:BAAANQADCgUJDQAAAA==.Mahli:BAABNQAECn8pAAQDAAgK5hlPHgB7AQADAAYKmA9PHgB7AQACAAUKzRb+qQB6AQAEAAMKCB2yFAD8AAAAAA==.Mark:BAAANQADCgYIBwAAAA==.Marrias:BAABNQAECn8sAAIJAAgKdRVlRwD3AQAJAAgKdRVlRwD3AQAAAA==.Massacre:BAAANQAECgQIBAABNQAECgQIEQAFAAAAAA==.Mawrix:BAABNQAECn8iAAQZAAgKrAu9HwDOAQAZAAgK9Aq9HwDOAQAWAAcK7Aq3RwCgAQAgAAEKAABjGgA8AAAAAA==.Mawyai:BAAANQADCgQIBAAAAA==.Maxieflames:BAAANQAECgQIAwAAAA==.Maxtheyare:BAAANQAECgQICAAAAA==.',
Me='Mechchimy:BAAANQAECgMIBQABNQAECgYIHAABAG8gAA==.Medîcus:BAAANQADCgIIAgAAAA==.Megumín:BAAANQAECgQICQAAAA==.Meith:BAAANQADCgUIBgAAAA==.Melwazul:BAAANQADCgMJAwAAAA==.Melz:BAAANQAECgIIAwAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAACNQAFFH8PAAIlAAUKwBqWAAC+AQAlAAUKwBqWAAC+AQA1AAQKfywAAyUACQrlJbsAAJwDACUACQrlJbsAAJwDAAgAAQoQDeSHADUAAAAA.Meyla:BAAANQADCgcIBgAAAA==.',
Mi='Mibby:BAAANQAECgYIBgABNQAECgIIAgAFAAAAAA==.Mibs:BAABNQAECn8pAAIfAAkK8R23KgAOAwAfAAkK8R23KgAOAwAAAA==.Mickal:BAABNQAECn8nAAIXAAgK0wtAtQCuAQAXAAgK0wtAtQCuAQAAAA==.Mikaelangelo:BAAANQAECgIIAQAAAA==.Mindrash:BAAANQAECgUIBwABNQAFFAUICwAQAOgQAA==.Mip:BAAANQAECgIIAgAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mm='Mmoo:BAAANQADCgQIBAAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAABNQAECn8nAAMSAAgKcxFoPQAIAgASAAgKcxFoPQAIAgARAAcKoRVVKQDQAQAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooter:BAABNQAECn8pAAIWAAkKBhiyHwB/AgAWAAkKBhiyHwB/AgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mordø:BAAANQAECgQIBAAAAA==.Mornix:BAAANQADCgUIBQABNQAECggIGgATAOcXAA==.Mortincarne:BAAANQAECgYICgAAAA==.',
Mu='Mushroom:BAABNQAECn8dAAIQAAkKyiEgGQBwAwAQAAkKyiEgGQBwAwAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAABNQAECn8jAAMMAAgKBRY3SgDMAQAMAAcKmBY3SgDMAQAJAAgKJQx1agBlAQAAAA==.Naqilol:BAAANQAECgMIAwAAAA==.Narfox:BAAANQAECgcIEQAAAA==.Narila:BAAANQAECgcIDQABNQAECggIHQAiAIIUAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAABNQAECn8iAAIjAAkKTwxBCgDMAQAjAAkKTwxBCgDMAQAAAA==.Necrophyle:BAAANQAECgQIBgAAAA==.Nefarox:BAAANQAECgQIDwAAAA==.Neilion:BAAANQADCgMIAwAAAA==.Nerfslappy:BAAANQAECgIIAwAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAABNQAECn8eAAMOAAkKxhaqSQBMAgAOAAkKxhaqSQBMAgAPAAcKaBgAeQCdAQAAAA==.Nightstealer:BAAANQAECgUICgAAAA==.Nikkikayama:BAACNQAFFH8LAAIBAAUKXRrnCgCbAQABAAUKXRrnCgCbAQA1AAQKfycAAgEACQqUIXQdACADAAEACQqUIXQdACADAAAA.Nikol:BAAANQAECgcIEwABNQAECgkJJQAPAGcYAA==.',
No='Norikoff:BAACNQAFFH8NAAMTAAcKxBKyAAC6AQATAAYK7BGyAAC6AQAfAAIKhQ4EMwB+AAA1AAQKfxoAAxMACQo/HjYEAPsCABMACQo/HjYEAPsCAB8ACAopEeSvAKABAAAA.',
Ny='Nyalla:BAAANQADCgcIGQAAAA==.',
['Nï']='Nïdalee:BAAANQAECgUIEgAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQAECgQIBQAAAA==.',
Of='Offdensen:BAAANQADCgcIGAAAAA==.',
Ok='Okkotsu:BAAANQAECgIIAwAAAA==.Okku:BAAANQAECgIIAwAAAA==.',
Ol='Oldmims:BAABNQAECn8mAAMcAAkKDh29BADXAgAcAAkKDh29BADXAgAQAAQKMxURawHfAAAAAA==.Oldmimse:BAAANQAECgEIAQABNQAECgkJJgAcAA4dAA==.',
On='Onlybatfans:BAAANQAECgYICwAAAA==.',
Op='Ophina:BAAANQAECgQICgAAAA==.',
Or='Oramu:BAABNQAECn8WAAMfAAkKEhvBQgC+AgAfAAkKEhvBQgC+AgATAAIK9BkUJwBwAAAAAA==.Orangejello:BAABNQAECn8eAAIXAAcKRxQQsQC3AQAXAAcKRxQQsQC3AQAAAA==.Ordim:BAAANQADCgcIBwAAAA==.Orion:BAAANQAECgYIBgABNQAFFAUIDgAaAKMVAA==.Oriòn:BAAANQAECgQIDgAAAA==.Orpseroth:BAAANQAECgcICAABNQAECggIHAAEAOMRAA==.',
Ot='Otane:BAAANQAECgYJCgAAAA==.',
Pa='Paiah:BAAANQAECgIIAgAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECggIJAAGAHcbAA==.Pana:BAABNQAECn8iAAIUAAgKXhOCJAC4AQAUAAgKXhOCJAC4AQAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAABNQAECn8eAAIPAAcKSRaoaADPAQAPAAcKSRaoaADPAQAAAA==.Pannifer:BAAANQAECgUIDwAAAA==.Paolon:BAAANQADCggIFAAAAA==.Papasmurph:BAAANQABCgUIAwAAAA==.Parple:BAAANQAECggIDwABNQAFFAYIEAAHAEgWAA==.',
Pc='Pcylock:BAAANQADCgYIBgAAAA==.',
Pe='Penelopei:BAAANQAECgcIDwAAAA==.',
Ph='Phantõm:BAAANQAECgMIBAAAAA==.Philkulson:BAABNQAECn8XAAInAAkKax+tBQAtAwAnAAkKax+tBQAtAwABNQAFFAcIGAAJAHQTAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgcIFwAAAA==.Porterah:BAAANQAECgYIBgAAAA==.Potbellypali:BAAANQABCgQIBgAAAA==.Poutyne:BAABNQAECn8tAAISAAkKch7UEwAnAwASAAkKch7UEwAnAwAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAFFAMICAAaADoaAA==.',
Pu='Punchnugget:BAAANQAECgUIDwAAAA==.Punkvc:BAABNQAECn8eAAIBAAgKTx1KPgCtAgABAAgKTx1KPgCtAgAAAA==.',
Py='Pyren:BAAANQAECgMIBAAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQAFAAAAAA==.',
['På']='Pånda:BAAANQAECggICgAAAA==.',
Qu='Quaeras:BAABNQAECn8bAAIIAAkKGA8aJQAhAgAIAAkKGA8aJQAhAgAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Raelitha:BAAANQABCgIIAgAAAA==.Ragingnoodle:BAAANQADCgQIBAABNQAECgYIEQAFAAAAAA==.Ragingshnoz:BAABNQAECn8oAAIiAAgKSyHWBQANAwAiAAgKSyHWBQANAwAAAA==.Ragé:BAECNQAFFH8GAAMkAAMKxRYZEACRAAAkAAIK8hAZEACRAAAKAAIKnBT/FQCIAAA1AAQKfyoAAyQACQrjIssKAC0DACQACAqRJMsKAC0DAAoABAq2HIlWACsBAAAA.Rakklock:BAAANQAECgIIAwAAAA==.Ralphe:BAAANQAECgcIEwAAAA==.Rashygroin:BAAANQAECgQIBAABNQAECggIJQAcAAYdAA==.Raytow:BAABNQAECn8bAAMKAAgKaR2RIACSAgAKAAgKaR2RIACSAgAkAAYK+g6wQABCAQAAAA==.Raytwomieux:BAAANQAECgEIAQAAAA==.Razath:BAAANQAECgQIBAABNQAECgkJLQAWAOoUAA==.Razelle:BAABNQAECn8ZAAIcAAgKjwlrEgB9AQAcAAgKjwlrEgB9AQAAAA==.Raînman:BAAANQAECgMIAwAAAA==.',
Re='Reconpalymix:BAAANQAECgEIAgAAAA==.Relana:BAAANQAECggIDwAAAA==.Remus:BAAANQAECggIEwAAAA==.Reshad:BAAANQAECgcIDQAAAA==.Ressix:BAABNQAECn8qAAIXAAgKvSAzRgC/AgAXAAgKvSAzRgC/AgAAAA==.',
Rh='Rhaeyn:BAAANQAECgQIBAABNQAECgUICwAFAAAAAA==.',
Ri='Ribcaught:BAAANQADCgIIAgAAAA==.Ripture:BAAANQADCgYIBgABNQAECgkJJwAQAHQbAA==.Rizzwar:BAAANQAECgYIBwAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQAECgcIDAAAAA==.Ronborules:BAAANQAECgQIBwAAAA==.Rosenta:BAABNQAECn8bAAIGAAcKtw+SgACRAQAGAAcKtw+SgACRAQAAAA==.',
Ru='Rumlock:BAAANQAECgcIDAAAAA==.',
['Rè']='Rèkkos:BAAANQAECgIIAgAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIEgAAAA==.',
Sa='Sabinah:BAAANQAECgMIBAAAAA==.Sabing:BAAANQADCgcIGQAAAA==.Sacramento:BAAANQADCgMJAwAAAA==.Saeberis:BAAANQAECgQIBQAAAA==.Saiah:BAABNQAECn8bAAIBAAcKChNTjwDnAQABAAcKChNTjwDnAQAAAA==.Saintbazz:BAAANQAECgUIEQAAAA==.Sal:BAACNQAFFH8QAAIHAAYKSBb8BADtAQAHAAYKSBb8BADtAQA1AAQKfzMAAgcACQqgJGcEAJEDAAcACQqgJGcEAJEDAAAA.Salivan:BAAANQAECgQIDwAAAA==.Sargaris:BAAANQAECgUIDAAAAA==.Sariva:BAACNQAFFH8PAAQDAAYK+SETBQDIAAACAAMKOCCiHAARAQADAAIKuiMTBQDIAAAEAAEKAABcCABgAAA1AAQKfyoABAIACQomIIZfADYCAAIABwo+IoZfADYCAAMABQrtFmAmAEEBAAQABAprG4ERADABAAAA.Sathalis:BAAANQAECgQICQAAAA==.Saurva:BAAANQAECgcIEgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgYIEgAFAAAAAA==.Saxophone:BAABNQAECn8mAAIaAAgKkhtaGwBeAgAaAAgKkhtaGwBeAgAAAA==.Sayna:BAAANQAECgUIEQAAAA==.',
Sc='Scarecro:BAABNQAECn8pAAMUAAkKAR33CgDpAgAUAAkKAR33CgDpAgAXAAMK4AyFVgGNAAAAAA==.',
Se='Sedae:BAABNQAECn8mAAIfAAkKTxpGNgDnAgAfAAkKTxpGNgDnAgAAAA==.Seekvaira:BAABNQAECn8mAAIOAAkKgBxUKwDPAgAOAAkKgBxUKwDPAgAAAA==.Seelenlos:BAAANQADCggIDwAAAA==.Seiya:BAABNQAECn8cAAIJAAkKYxpXKwCGAgAJAAkKYxpXKwCGAgAAAA==.Selira:BAABNQAECn8bAAIBAAgKHhGDegAWAgABAAgKHhGDegAWAgAAAA==.Selwynn:BAAANQAECgcIBwAAAA==.Senji:BAAANQAECgYICAAAAA==.Senseitots:BAAANQADCggICAAAAA==.Sevalina:BAABNQAECn8kAAIGAAgKABEjYgD2AQAGAAgKABEjYgD2AQAAAA==.',
Sh='Shadowstep:BAAANQAECgUICgAAAA==.Shalaah:BAABNQAECn8gAAIBAAcKiQrWrgCiAQABAAcKiQrWrgCiAQAAAA==.Shamhuntzu:BAECNQAFFH8JAAIkAAUKXhcTBwCbAQAkAAUKXhcTBwCbAQA1AAQKfx0AAyQACQpIGaMgAEUCACQACQpIGaMgAEUCAA0AAwrEBcsnAHIAAAAA.Shampaign:BAABNQAECn8oAAMPAAgKLCEkHwDsAgAPAAgKLCEkHwDsAgAOAAIKgRQvCAF0AAAAAA==.Shaoevoker:BAAANQAECgQIBAAAAA==.Sharnara:BAAANQAECgcIEAAAAA==.Shatterskull:BAAANQAECgQIBAAAAA==.Shazira:BAAANQAECgUICQAAAA==.Shep:BAAANQAECgUIBwAAAA==.Sherloch:BAAANQADCgQIBQAAAA==.Shi:BAAANQAECgQIBgAAAA==.Shiftyrum:BAAANQAECgUIBQABNQAECggIJQAQAH4cAA==.Shmollboi:BAAANQABCgIIAgAAAA==.Shnub:BAAANQAECgQIBAAAAA==.',
Si='Sideffects:BAABNQAECn8gAAIOAAgKLBlyPACBAgAOAAgKLBlyPACBAgAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAABNQAECn8nAAICAAgK/BzQMQC+AgACAAgK/BzQMQC+AgAAAA==.Silverlord:BAABNQAECn8mAAIeAAgKPhtxCQCHAgAeAAgKPhtxCQCHAgAAAA==.Sinafay:BAABNQAECn8cAAMcAAkKSAwQEwB0AQAcAAkKSAwQEwB0AQAQAAEKAACi3gEiAAAAAA==.Sineu:BAAANQADCgcIBwABNQAFFAMICAAaADoaAA==.Siv:BAACNQAFFH8IAAIaAAMKOhpXCwD2AAAaAAMKOhpXCwD2AAA1AAQKfy4AAxoACQr/I20FAHgDABoACQq/I20FAHgDAB4AAQoaI9IqAGUAAAAA.Sixnine:BAAANQAECgIIAgAAAA==.',
Sj='Sjor:BAAANQADCgIIAgAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQAECgIIAgAAAA==.',
Sn='Snackkpack:BAAANQAECgIIBAAAAA==.Snapjutsu:BAECNQAFFH8FAAIaAAMKdgXuDQCvAAAaAAMKdgXuDQCvAAA1AAQKfx4AAxoACAqfFoInAOEBABoACAqfFoInAOEBAB4AAQoQFUQyACsAAAAA.Snorg:BAABNQAECn8pAAIQAAgKRgkI5AC+AQAQAAgKRgkI5AC+AQAAAA==.Snêaky:BAABNQAECn8iAAMWAAcK/yFUGwCfAgAWAAcK/yFUGwCfAgAZAAEKAADfUAA4AAAAAA==.',
So='Solarnova:BAABNQAECn8fAAIBAAcKnQyHmADSAQABAAcKnQyHmADSAQAAAA==.Solorn:BAAANQAECgcIJgAAAQ==.',
Sp='Splash:BAAANQAECgEIAQAAAA==.Spygon:BAABNQAECn8fAAMBAAgKxBorQgCiAgABAAgKxBorQgCiAgAIAAEKAABckgAsAAAAAA==.',
St='Sternhunt:BAAANQAECgQIBAABNQAECggIIwAMAAUWAA==.Strobila:BAAANQAECggIEQAAAA==.Studd:BAAANQAECgQIBQAAAA==.Studdmuffin:BAACNQAFFH8JAAMoAAUK0hKHDwDdAAAoAAMK0hKHDwDdAAAJAAMKcAYQFQCzAAA1AAQKfxsAAwkACQoIIlg0AFUCAAkACQrUG1g0AFUCACgABQpcIWdQAGkBAAAA.',
Su='Suina:BAAANQAECgQIBAABNQAFFAMICAAaADoaAA==.Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAABNQAECn8jAAMMAAgK+B4LGwDUAgAMAAgK+B4LGwDUAgAJAAcKoxXCVQC3AQAAAA==.Suze:BAAANQAECgEIAQABNQAECggIIwAMAPgeAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Sylvië:BAAANQAECggIBgAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAABNQAECn8pAAIMAAgK7RyOJACTAgAMAAgK7RyOJACTAgAAAA==.Syrathos:BAACNQAFFH8WAAMkAAcKWheoAgBCAgAkAAcKWheoAgBCAgAKAAEKAADkGgBVAAA1AAQKfy0AAyQACQofJR0IAE8DACQACQofJR0IAE8DAAoABApMIWBHAIcBAAAA.Syrioforel:BAAANQAECgQICwAAAA==.',
Ta='Taojîn:BAABNQAECn8YAAIhAAkKfQwTYwDsAQAhAAkKfQwTYwDsAQAAAA==.Tarted:BAAANQAECgUICgAAAA==.Tatèrdots:BAAANQAECgEIAQAAAA==.',
Te='Teclis:BAACNQAFFH8FAAIQAAMKpRzLMwDxAAAQAAMKpRzLMwDxAAA1AAQKfyAAAhAACQqQIYRaAMsCABAACQqQIYRaAMsCAAAA.Telzindrov:BAABNQAECn8aAAMYAAgKBQY9KwBOAQAYAAgKBQY9KwBOAQAjAAcKLARbEwD3AAAAAA==.Terrorwithin:BAAANQAECgYIDAAAAA==.',
Th='Thalgar:BAAANQAECgIIAgAAAA==.Thalmick:BAABNQAECn8jAAIZAAgK7RleFABDAgAZAAgK7RleFABDAgAAAA==.Thanoslye:BAAANQAECgIIBAAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Theyathal:BAAANQAECggIDQAAAA==.Thogarn:BAABNQAECn8dAAIOAAkKBApSaADkAQAOAAkKBApSaADkAQAAAA==.Thunderkat:BAAANQAECgMIBQABNQAECgUICgAFAAAAAA==.Thundertem:BAAANQAECgUICgAAAA==.Théière:BAABNQAECn8tAAIbAAkKpBXiDgBsAgAbAAkKpBXiDgBsAgAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUJDQAFAAAAAA==.Tinychimy:BAAANQADCgUICAABNQAECgYIHAABAG8gAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAABNQAECn8cAAIQAAgKORBM0wDdAQAQAAgKORBM0wDdAQABNQAECgkJKAAVAKIhAA==.',
To='Tofper:BAAANQADCgYIBgAAAA==.Totemstout:BAAANQAECggICAAAAA==.Toughlove:BAAANQAECgMIBgAAAA==.',
Tr='Trev:BAABNQAECn8iAAMQAAkK7SAaMAAsAwAQAAkK7SAaMAAsAwAcAAEKAAC6PwBDAAAAAA==.Trustfäll:BAAANQAECgUIEAAAAA==.Trytomilkme:BAAANQAECgEIAQAAAA==.',
Ts='Tsunãmi:BAABNQAECn8iAAMPAAkKkxlROQB3AgAPAAkKkxlROQB3AgAnAAgKXRDtFwDkAQAAAA==.',
Tu='Tuc:BAABNQAECn8eAAIHAAgKHQkqMwCGAQAHAAgKHQkqMwCGAQAAAA==.',
Ty='Tyndareos:BAAANQADCgUIBgAAAA==.Typhoontravv:BAABNQAECn8fAAMUAAkKgB3TEgBzAgAUAAkKIh3TEgBzAgAXAAQKSBstDwH/AAAAAA==.',
['Tø']='Tøkakagé:BAAANQAECgUIEQAAAA==.',
Uf='Ufearme:BAAANQAECgQICAAAAA==.',
Ug='Ugabooga:BAABNQAECn87AAIQAAkKtCCrIwBPAwAQAAkKtCCrIwBPAwAAAA==.Uggon:BAAANQAECgQIEAAAAA==.',
Un='Unable:BAABNQAECn8aAAITAAcKHBAVEACjAQATAAcKHBAVEACjAQAAAA==.',
Ur='Urrikahn:BAAANQAECgQIBQAAAA==.',
Us='Usedtinfoil:BAAANQAECgEIAQAAAA==.',
Ut='Uthur:BAABNQAECn8XAAIUAAgKCAo/MwBFAQAUAAgKCAo/MwBFAQAAAA==.Utterchaos:BAACNQAFFH8LAAICAAUK5gs/EwBlAQACAAUK5gs/EwBlAQA1AAQKfx0AAwIACQojFTCUAK8BAAIACApoEjCUAK8BAAMABApQDm5CALkAAAAA.',
Va='Vaelaven:BAABNQAECn8tAAISAAkK3BHUMABXAgASAAkK3BHUMABXAgAAAA==.Valack:BAAANQAECgMIAwAAAA==.Valfore:BAABNQAECn8jAAIMAAgK1CGsGADmAgAMAAgK1CGsGADmAgAAAA==.Valizor:BAAANQAECgUIEgAAAA==.Valorya:BAAANQADCgEIAQAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAABNQAECn8aAAMTAAgK5xfZEQCEAQAfAAcKnhd9kQDsAQATAAYKmRXZEQCEAQAAAA==.Vayle:BAAANQADCggIDgABNQAECgkJLAABALMiAA==.',
Ve='Velaara:BAAANQAECgIIAgAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Velamun:BAAANQAECgYIBgAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vestoris:BAAANQAECgQIBwAAAA==.Vetta:BAACNQAFFH8KAAIPAAUKgAnNDwBNAQAPAAUKgAnNDwBNAQA1AAQKfxoAAg8ACQpMEVRtAL8BAA8ACQpMEVRtAL8BAAAA.',
Vg='Vger:BAAANQADCggIEwAAAA==.',
Vi='Vieora:BAAANQADCgYIBgAAAA==.Vikvikvik:BAAANQADCggIDgAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQAECgEIAQAAAA==.',
Vo='Volgagrad:BAAANQAECggIDQAAAA==.Vond:BAAANQABCgIJAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQAECgQICQAFAAAAAA==.',
Wa='Wardum:BAAANQAECgUICgAAAA==.Watt:BAAANQADCggICAABNQAFFAMICAAaADoaAA==.Wazul:BAAANQADCgcIGAAAAA==.',
Wh='Whisp:BAAANQAECgQIBgAAAA==.Whitearrows:BAABNQAECn82AAQBAAkKniHhDAB2AwABAAkKniHhDAB2AwAlAAUK7xbNCQCJAQAIAAQKcBBNUwDVAAAAAA==.Whitedecay:BAAANQAECgQIBAABNQAECgkJNgABAJ4hAA==.Whitespell:BAABNQAECn8XAAIQAAcKDBXL5gC5AQAQAAcKDBXL5gC5AQABNQAECgkJNgABAJ4hAA==.',
Wi='Wickfel:BAAANQAECgUICQAAAA==.Wicus:BAAANQADCggICAAAAA==.',
Wy='Wyldfarmer:BAAANQAECgUIDgAAAA==.',
Xa='Xanid:BAAANQAECgYIEQAAAA==.',
Xd='Xdwarf:BAAANQAECgYIDwABNQAECggIKgAWAJgXAA==.',
Xe='Xeroxoxo:BAABNQAECn8mAAIJAAkKIiB2HgDSAgAJAAkKIiB2HgDSAgAAAA==.Xevric:BAAANQAECggIAwAAAA==.',
Xi='Xieren:BAAANQAECgQIDQABNQAECgQIEQAFAAAAAA==.',
Xo='Xoz:BAAANQAECgQIBAAAAA==.',
Ya='Yasman:BAAANQAECgIIAgAAAA==.',
Ye='Yesenia:BAAANQAECgEIAQABNQAFFAYIDwADAPkhAA==.',
Ym='Ymedead:BAAANQAFFAEIAQABNQAFFAQIBgABAEcVAA==.',
Yo='Yoroichi:BAABNQAECn8qAAIWAAgKmBcHKwA4AgAWAAgKmBcHKwA4AgAAAA==.Yourmomsride:BAABNQAECn8dAAIQAAgKAAvl6AC1AQAQAAgKAAvl6AC1AQAAAA==.Youtube:BAABNQAECn8aAAIhAAkK4wNi2gDFAAAhAAkK4wNi2gDFAAAAAA==.',
Yu='Yueyue:BAABNQAECn8gAAIQAAkK3hacYwC3AgAQAAkK3hacYwC3AgAAAA==.Yungtwizzler:BAAANQADCggIEQABNQAECgQIBAAFAAAAAA==.',
['Yá']='Yáng:BAABNQAECn8eAAIYAAcK2iJYDgDBAgAYAAcK2iJYDgDBAgAAAA==.',
Za='Zarylathanea:BAABNQAECn8mAAIBAAgKKgotlgDYAQABAAgKKgotlgDYAQAAAA==.',
Ze='Zenheals:BAAANQAECggIAgAAAA==.Zeniel:BAAANQAECgEIAQAAAA==.Zeroskills:BAAANQAECgYIEgAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQAECgUIEQAAAA==.Zoog:BAACNQAFFH8LAAIhAAUKnQ1+DgB2AQAhAAUKnQ1+DgB2AQA1AAQKfx4AAiEACQqBHCwnAMoCACEACQqBHCwnAMoCAAAA.',
Zy='Zyrana:BAAANQADCgUICwAAAA==.Zyridal:BAABNQAECn8nAAIQAAgKfAQoEwFoAQAQAAgKfAQoEwFoAQAAAA==.Zyvara:BAABNQAECn8cAAIVAAcKEBZHHQCvAQAVAAcKEBZHHQCvAQAAAA==.',
['Zä']='Zärèlíä:BAACNQAFFH8QAAIaAAUKYxp8BgCZAQAaAAUKYxp8BgCZAQA1AAQKf1YAAhoACQqsJRsBAN4DABoACQqsJRsBAN4DAAE1AAQKCQkwABcABSQA.',
['Äp']='Äpples:BAAANQAECgQIBgAAAA==.',
['Æz']='Æz:BAABNQAECn8oAAIKAAgKeBFkOQDkAQAKAAgKeBFkOQDkAQAAAA==.',
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
