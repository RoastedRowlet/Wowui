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

local lookup = {'Unknown-Unknown','Druid-Guardian','Druid-Balance','Mage-Arcane','Mage-Frost','Priest-Discipline','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Shaman-Restoration','Paladin-Holy','Hunter-BeastMastery','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','DeathKnight-Blood','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Warrior-Protection','Monk-Windwalker','Priest-Shadow','DemonHunter-Vengeance','Monk-Brewmaster','Paladin-Protection','Hunter-Marksmanship','DemonHunter-Havoc','Warlock-Demonology','Monk-Mistweaver','Shaman-Enhancement','Druid-Feral','Warlock-Destruction','Hunter-Survival','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abbyss:BAAANQAECgQICAABNQAECgUIDgABAAAAAA==.Abirnar:BAABNQAECn8iAAMCAAkKiRwREgA8AgACAAYKayEREgA8AgADAAgKqBS0OgAZAgAAAA==.Abramelinn:BAABNQAECn8zAAMEAAcKBw9u8gCjAQAEAAcKmw5u8gCjAQAFAAEKYxBTSAAyAAAAAA==.Abygayle:BAAANQAECgUICgAAAA==.',
Ac='Acca:BAAANQAECgUIEQAAAA==.',
Ad='Adget:BAABNQAECn8kAAIEAAkKBRABpgA0AgAEAAkKBRABpgA0AgAAAA==.Adicas:BAAANQABCgIJAgAAAA==.Adorion:BAAANQAECgYICgAAAA==.Adriosis:BAAANQADCgMIAwAAAA==.',
Ae='Aerali:BAABNQAECn8pAAMGAAkKfB9VAQBGAwAGAAkKfB9VAQBGAwAHAAEKpANN+QAyAAAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgYIEwABNQAECgcIDQABAAAAAA==.Agôny:BAAANQAECgQICAABNQAECggIJAAHALYaAA==.',
Ah='Ahsõka:BAAANQAECgQIBQAAAA==.',
Ai='Aidzboy:BAAANQAECgcIDwAAAA==.',
Al='Aldin:BAAANQAECgEIAQAAAA==.Alexandrõs:BAABNQAECn8eAAMIAAgKXiSFDQAkAwAIAAgKXiSFDQAkAwAJAAEKagIfAgEQAAAAAA==.Alfah:BAAANQAECgQIBAAAAA==.Aliatris:BAAANQAECgUIDgAAAA==.Alicia:BAAANQAECgIIAgAAAA==.Alkamay:BAABNQAECn8UAAIEAAUKAAeMWgH3AAAEAAUKAAeMWgH3AAAAAA==.Allor:BAAANQAECgEIBAAAAA==.Allorpally:BAABNQAECn8gAAIKAAkKvh2fOQDnAgAKAAkKvh2fOQDnAgAAAA==.Altofmyalt:BAAANQADCgIJAgAAAA==.Altrexa:BAAANQADCgIIAgAAAA==.Alui:BAAANQAECgUICgABNQAFFAMIBwALAJEPAA==.Aluii:BAACNQAFFH8HAAILAAMKkQ9fJADYAAALAAMKkQ9fJADYAAA1AAQKfyoAAgsACQqBIFY4AOACAAsACQqBIFY4AOACAAAA.Alyn:BAAANQAECgEIAQAAAA==.Alyssana:BAAANQAECgQICgAAAA==.Alyssius:BAABNQAECn8bAAIKAAgKMQ03tgCsAQAKAAgKMQ03tgCsAQAAAA==.Alyxdt:BAAANQAECgYIBgAAAA==.Alyxpally:BAAANQAECgcIDwAAAA==.Alyxpants:BAAANQAECgYIDAAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaranta:BAAANQADCgcIDgAAAA==.Amaria:BAABNQAECn8dAAIMAAgKdxxKNgCDAgAMAAgKdxxKNgCDAgAAAA==.Ambah:BAAANQADCggIEAAAAA==.Ambulance:BAABNQAECn8fAAINAAkKcBmsLACyAgANAAkKcBmsLACyAgAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQAECgUIEQAAAA==.Angelsfly:BAAANQAECgUIEQAAAA==.Angstrasz:BAAANQADCgQIBAAAAA==.Angæl:BAABNQAECn8XAAIMAAcKQAUusAAKAQAMAAcKQAUusAAKAQAAAA==.Annallyne:BAAANQADCgUIBQABNQAECgkJJgAOABUYAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQAECgQICQAAAA==.Anultrun:BAAANQAECgQICAAAAA==.',
Ar='Arabellaa:BAAANQAECgYIEAAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQAECgQIBwAAAA==.Archavrice:BAAANQAECgEIAQAAAA==.Arcyandor:BAAANQADCgcIEAAAAA==.Aremixlady:BAAANQAECgEIAQAAAA==.Aristomenis:BAAANQAECgYIBgAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgYJEwAAAA==.Arndul:BAAANQAFFAMIAwABNQAECgkJGAAEAD8WAA==.',
As='Asapxmello:BAAANQADCgMIAwAAAA==.Ashammylady:BAAANQADCgYIBgAAAA==.Ashmear:BAAANQAECgYICAAAAA==.Ashê:BAAANQAECgQIBwABNQAECgcICAABAAAAAA==.Astrîl:BAAANQADCggICAAAAA==.',
At='Athreos:BAAANQAECgYIBwAAAA==.Atticuss:BAAANQADCgUIBQAAAA==.Atüned:BAABNQAECn8jAAMNAAkKUSJxCwBsAwANAAkKUSJxCwBsAwAKAAIK2Q6PdAFhAAAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAABNQAECn9VAAMPAAgKhBNDXQAHAgAPAAgKhBNDXQAHAgAMAAMKCQXS9gB3AAAAAA==.Aurelía:BAAANQAECgMIBgAAAA==.Autumni:BAAANQADCgYICQABNQAECgUIBQABAAAAAA==.',
Av='Avelane:BAABNQAECn8pAAMKAAgKIBlldwA6AgAKAAgKIBlldwA6AgANAAYKXxVrhwCCAQAAAA==.Averia:BAAANQABCgIIAgAAAA==.Avrare:BAAANQADCgYIBgAAAA==.',
Az='Azrukia:BAAANQADCgcIBwABNQAECggIKQAQADsjAA==.Azubasaurus:BAACNQAFFH8HAAIRAAMKmCJlDQA0AQARAAMKmCJlDQA0AQA1AAQKfykAAxEACQoiJGACAJoDABEACQoiJGACAJoDABIAAwoaFb0qAM4AAAAA.',
Ba='Baeladar:BAAANQADCggICAAAAA==.Baelor:BAAANQAECgUIBwAAAA==.Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgcIEgAAAA==.Balerion:BAAANQAECgYIEQAAAA==.Barkstard:BAABNQAECn8oAAMDAAkKshh9LgBoAgADAAgKgxt9LgBoAgATAAMK6hIzTgDOAAAAAA==.Barleyalive:BAAANQAECgIIAgABNQADCgEIAQABAAAAAA==.Barleybrew:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQAECgUICgAAAA==.',
Be='Belarii:BAAANQAECgYIDwAAAA==.Bellonae:BAAANQAECgUIDgABNQAECgYIDwABAAAAAA==.Belmenth:BAAANQADCgMIBAAAAA==.Belun:BAAANQAECgEIAQAAAA==.Bendecida:BAAANQAECgIIAgABNQAECgcIMwAEAAcPAA==.Benington:BAAANQAECgYIEQAAAA==.Benn:BAACNQAFFH8dAAQJAAcK+BlFBwCkAQAJAAUKLhxFBwCkAQAIAAUKhhhXCgA4AQAUAAEKAAChLwA2AAA1AAQKfz4AAwgACQrCJWUHAGwDAAgACQrCJWUHAGwDAAkAAwoEHp+cAMEAAAAA.Beregond:BAAANQAECgQIBAABNQAECgUIEgABAAAAAA==.',
Bh='Bhyta:BAAANQAECgcIDAAAAA==.',
Bi='Bigpapper:BAAANQAECgIIAgAAAA==.Bishopbob:BAAANQADCgcIBwAAAA==.Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAABNQAECn8qAAIHAAkKTQYOewCkAQAHAAkKTQYOewCkAQAAAA==.Bitrusty:BAAANQADCggIDQABNQAECgcIHQANACsaAA==.',
Bj='Bjartastrasz:BAABNQAECn8ZAAISAAcK+AdnIABOAQASAAcK+AdnIABOAQAAAA==.Bjorc:BAAANQAECggIDwAAAA==.Bjoriannm:BAAANQAECggIBgABNQAECggIEAABAAAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAABNQAECn8pAAIOAAkKCSaFAwDOAwAOAAkKCSaFAwDOAwAAAA==.Blaumeux:BAAANQAECgQIBAAAAA==.Blazine:BAAANQABCggIDAAAAA==.Bliksem:BAAANQADCggICAAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQAECgEIAQABNQAECggIGwAEAJQHAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggIDQABNQAECgkJLQAKABsdAA==.Bluesham:BAABNQAECn8XAAIPAAcKJhE5iACMAQAPAAcKJhE5iACMAQAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAABNQAECn85AAIDAAkKLRehNABAAgADAAkKLRehNABAAgAAAA==.Boopmachine:BAAANQAECgIIAQABNQAECggIHAAVAK0NAA==.Boostmartyr:BAAANQADCgcIBwAAAA==.Bowsbfrhoez:BAABNQAECn9JAAIOAAgKTxk1WwBgAgAOAAgKTxk1WwBgAgAAAA==.Boyaka:BAAANQAECgMIAwABNQAECgYIGQAWAB0XAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brisingar:BAAANQAECgUIBQAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQAECgIIBAABNQAECgUICwABAAAAAA==.',
Bu='Bubblëøseven:BAAANQAECggIEAAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQAECgYICwABNQAECggIGAAXALkcAA==.Burds:BAAANQAECgYICAABNQAECggIGAAXALkcAA==.',
['Bë']='Bëllädonna:BAAANQAECgEIAQAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECn87AAIEAAkKRh2OdgCQAgAEAAkKRh2OdgCQAgAAAA==.Caffeínated:BAAANQAECgUIBQAAAA==.Candis:BAAANQADCgYIBgABNQAECgkJQgALADMmAA==.Cardoney:BAABNQAECn8tAAIKAAcK4Qc46wA/AQAKAAcK4Qc46wA/AQAAAA==.Cariah:BAABNQAECn8sAAIKAAgKayGWQQDNAgAKAAgKayGWQQDNAgAAAA==.Catashax:BAAANQADCgcJGAAAAA==.',
Cd='Cdkit:BAABNQAECn9VAAIYAAgKORu7CwB7AgAYAAgKORu7CwB7AgAAAA==.',
Ce='Celestè:BAAANQADCggIFgAAAA==.Celéstina:BAAANQADCgEIAQAAAA==.',
Ch='Chasstise:BAABNQAECn8YAAIHAAcKORXlbwDJAQAHAAcKORXlbwDJAQAAAA==.Chazze:BAAANQAECgEIAQAAAA==.Cheazdruid:BAAANQADCgQJBAAAAA==.Cheazy:BAAANQADCgUIBQAAAA==.Cheggery:BAAANQAECgQICQAAAA==.Chikubiz:BAAANQAECggICAAAAA==.Chillet:BAAANQAECgUIBQAAAA==.Chirp:BAAANQADCgIIAgABNQAECgYIGwANAE4kAA==.Chirpe:BAAANQAECgQJBAABNQAECgYIGwANAE4kAA==.Chokehan:BAAANQABCgEIAQAAAA==.Chubbypope:BAAANQAECgIIAgABNQAECgkJKAAVACslAA==.Chuxer:BAAANQADCgQIBAAAAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgMIAwABAAAAAA==.Cindrick:BAACNQAFFH8XAAIRAAQKNBPmDABDAQARAAQKNBPmDABDAQA1AAQKf1EAAxEACQo7IzMCAJ4DABEACQo7IzMCAJ4DABIAAwpdDkctALIAAAAA.',
Cl='Clessta:BAAANQAECgYIDwAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAABNQAECn8lAAIZAAkKmRnuFQCeAgAZAAkKmRnuFQCeAgAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgUIDwABAAAAAA==.Clynefate:BAAANQADCgIIAgAAAA==.',
Co='Coffêê:BAABNQAECn8yAAIMAAkKgSGQDwBFAwAMAAkKgSGQDwBFAwAAAA==.Coggers:BAAANQAECgQIBwAAAA==.Coldbringer:BAABNQAECn8dAAMUAAgKwRzfOwARAgAUAAcKwRzfOwARAgAIAAYKEhRXTQB6AQAAAA==.Coldpalmer:BAAANQAECgUIDQABNQAECgkJKQALADMZAA==.Coleostrasz:BAAANQADCgQJBAAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Conzriest:BAAANQAECgEIAQAAAA==.Corastrasza:BAAANQAECgUIEgAAAA==.Courtan:BAAANQADCggIEwAAAA==.',
Cr='Crawfkin:BAAANQADCgIIAgAAAA==.Cresentmoon:BAAANQAECgQIBgAAAA==.Crimsonmage:BAAANQAECgUICgAAAA==.Crowchild:BAAANQADCgQIBAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggIEwAAAA==.',
Cu='Cursedlight:BAABNQAECn8jAAMHAAkKSx/eEwAtAwAHAAkKSx/eEwAtAwAaAAYK2RwnJQADAgAAAA==.',
Cy='Cynnal:BAAANQAECgcIDwAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgUICQAAAA==.Dahj:BAABNQAECn8XAAIbAAcKCRk2DwC/AQAbAAcKCRk2DwC/AQAAAA==.Dalanar:BAAANQAECgUICgAAAA==.Danathjo:BAAANQAECgUICAAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Davoth:BAAANQAECgUICgAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAABNQAECn8jAAIOAAgKCRzARwCTAgAOAAgKCRzARwCTAgAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAABNQAECn8fAAMJAAgKYAl5ZwBvAQAJAAgKYAl5ZwBvAQAUAAIKiATNvwBFAAAAAA==.Debris:BAAANQAECgcIEAAAAA==.Deceit:BAAANQAECgIIAgAAAA==.Dedmongrel:BAABNQAECn8cAAMZAAcKaRA3LgCiAQAZAAcKaRA3LgCiAQAcAAEKRwHoNwAUAAAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgYIEgAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAYIEwACAAAiAA==.Dengar:BAABNQAECn8VAAIOAAkK4Bc/OgC5AgAOAAkK4Bc/OgC5AgAAAA==.Desyphium:BAACNQAFFH8WAAIKAAYKfh0vBgDuAQAKAAYKfh0vBgDuAQA1AAQKfyoAAwoACQqtI3kmACkDAAoACQqtI3kmACkDAB0AAQpKIIhkAEoAAAAA.Deviltrigger:BAAANQADCgUJCAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQAECgQIBAAAAA==.Deweysan:BAAANQAECgIIAwAAAA==.Dex:BAACNQAFFH8XAAIMAAUKiRQLDQB3AQAMAAUKiRQLDQB3AQA1AAQKfz4AAwwACQryIXEeAO8CAAwACQryIXEeAO8CAA8AAQoAFIQkAUEAAAAA.Dexpalaladin:BAAANQAECgEIAQAAAA==.Deyalane:BAAANQADCgQIBAAAAA==.',
Di='Direforge:BAABNQAECn8fAAIcAAcKmCLhCACXAgAcAAcKmCLhCACXAgAAAA==.Diriisharks:BAABNQAFFH8FAAIeAAMKWxZzFQDhAAAeAAMKWxZzFQDhAAAAAA==.Disreputable:BAAANQADCgUIBAAAAA==.',
Dk='Dkaillou:BAAANQADCgMJAwAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Dompt:BAAANQABCgQIBAAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgcIEAAAAA==.Dracothyr:BAAANQAECgQICAAAAA==.Draemon:BAABNQAECn9qAAIFAAkK2iVIAADfAwAFAAkK2iVIAADfAwAAAA==.Draenei:BAAANQAECggIDQABNQAECgkJKQALADMZAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFH8aAAIfAAgK4CLHAAD2AgAfAAgK4CLHAAD2AgA1AAQKfysAAx8ACQrqJZ4GAIsDAB8ACQrqJZ4GAIsDABAABgq6HwM1AJYBAAAA.Dragonscar:BAAANQAECgUICQABNQAECgYIDQABAAAAAA==.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQAECgYICQABNQAECgkJKQALADMZAA==.Drastiricka:BAAANQADCggIEwAAAA==.Dreadlocksta:BAAANQADCgMJAwAAAA==.Dreamer:BAAANQADCggIFgAAAA==.Drfel:BAAANQAECgQIBAAAAA==.Drinkwater:BAAANQAECgMIDAABNQAECgUIDwABAAAAAA==.Drizztdemon:BAAANQAECgIIAgABNQAFFAcIJQAgADchAA==.Drucaila:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECgkJMgAgANQjAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIEgAAAA==.Durkadurka:BAAANQABCgEIAQABNQAECgYIBwABAAAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgYIEQAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAACNQAFFH8JAAIEAAQKWB05IwBmAQAEAAQKWB05IwBmAQA1AAQKfz0AAgQACQoIJC0LAKoDAAQACQoIJC0LAKoDAAAA.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eastlord:BAAANQAECgEIAQAAAA==.Eatduhpupu:BAAANQAECgUIEwABNQAECgcIDwABAAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECggIJgAUAGgjAA==.Electricity:BAAANQADCgYIDAAAAA==.Elfhelm:BAAANQAECgYIEwAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellisinor:BAAANQAECgEIAQAAAA==.Eluneschosen:BAAANQAECgUJAgAAAA==.Elured:BAABNQAECn8jAAIHAAgKyggMiQB3AQAHAAgKyggMiQB3AQAAAA==.Elysalia:BAAANQAECgcIDgAAAA==.Elysean:BAAANQAECgQIBAAAAA==.',
Em='Embermist:BAAANQAECgYIEQAAAA==.Emliy:BAABNQAECn8lAAMRAAkK6RaqEQCPAgARAAkK6RaqEQCPAgASAAQKVQuZJwDzAAAAAA==.Emogirl:BAAANQAECgEIAQABNQAECgkJKgAOAAsmAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAABNQAECn8oAAQhAAkKkxxdCgDgAgAhAAkKkxxdCgDgAgAZAAgKKhGJKgDEAQAcAAEKAABPNgAeAAAAAA==.',
Ep='Ephesian:BAABNQAECn8dAAMKAAcKJhokgAAkAgAKAAcKyBkkgAAkAgAdAAYKuxloJAC5AQAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECgkJLQALAEMdAA==.Erobas:BAABNQAECn9PAAILAAgKKhrwdAAzAgALAAgKKhrwdAAzAgAAAA==.Erodan:BAABNQAECn8tAAILAAkKQx2ULwD+AgALAAkKQx2ULwD+AgAAAA==.',
Es='Esserian:BAAANQAECgYIDQAAAA==.Estarae:BAABNQAECn83AAQaAAkKmBPHOgBOAQAaAAcKxg3HOgBOAQAHAAMKSQZo2QCTAAAGAAEKggHQMwAOAAAAAA==.Esthane:BAABNQAECn8VAAIYAAgKaghmIgAyAQAYAAgKaghmIgAyAQAAAA==.',
Et='Eternaldawn:BAAANQADCggIFAAAAA==.Ethereall:BAAANQAECgUICQAAAA==.',
Eu='Euphuzadan:BAABNQAECn8yAAIgAAkK1CO8BgCXAwAgAAkK1CO8BgCXAwAAAA==.',
Ev='Eveliala:BAAANQABCgMIAwAAAA==.Everhealer:BAABNQAECn9XAAIGAAkKaR7YAQAcAwAGAAkKaR7YAQAcAwAAAA==.Evienarian:BAAANQABCgUICwAAAA==.Evillumber:BAAANQAECgYICgAAAA==.',
Ex='Exiledemon:BAAANQAECgYICgAAAA==.Exterminatus:BAAANQAECgYIBgABNQAECggIGAAiAGgeAA==.',
Ey='Eyéspy:BAAANQAECgYIBgAAAA==.',
Ez='Ezza:BAAANQAECgcIBQAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Faneragare:BAAANQAECgIIAwABNQAFFAYIGAAPAGglAA==.Fatonement:BAAANQAECgYICwABNQAECgcIDQABAAAAAA==.Fauvm:BAABNQAECn82AAIEAAgK4hVjpAA3AgAEAAgK4hVjpAA3AgAAAA==.',
Fe='Feanassa:BAABNQAECn8dAAMfAAcKGgUSVwAoAQAfAAcKGgUSVwAoAQAQAAMKegH8YgBYAAAAAA==.Fearwood:BAAANQAECgUIBQAAAA==.Felfeet:BAAANQAECgQJBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQAECgQIBAAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.Feyfoxe:BAAANQADCgIIAgAAAA==.',
Fi='Fishing:BAABNQAECn8oAAIPAAkKviPvDAB/AwAPAAkKviPvDAB/AwABNQAFFAMIBQAeAFsWAA==.Fishpup:BAAANQAECggIDAAAAA==.',
Fl='Flaviousqt:BAAANQAECgYICgAAAA==.Flavorofkrel:BAAANQADCggICAABNQAECgkJMgAEABQiAA==.Flekzakzak:BAABNQAECn8nAAIjAAgKuyC/BgD6AgAjAAgKuyC/BgD6AgAAAA==.Flekzugzug:BAABNQAECn8bAAIKAAgKaBqfagBZAgAKAAgKaBqfagBZAgABNQAECggIKgAJAGwkAA==.Flezappezix:BAACNQAFFH8YAAIPAAYKaCWEAwBrAgAPAAYKaCWEAwBrAgA1AAQKfxgAAg8ACQo5JDAiAP4CAA8ACQo5JDAiAP4CAAAA.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAABNQAECn8pAAMHAAkKOhoiMwCYAgAHAAkKOhoiMwCYAgAGAAcKLgkMDwA5AQAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAcIIgARAAgaAA==.Forald:BAAANQAECgQJBAAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forgery:BAAANQADCgYIBgAAAA==.Forman:BAACNQAFFH8UAAMJAAYKHx0WAgAsAgAJAAYK/hgWAgAsAgAIAAQK3yR7BwB7AQA1AAQKfx8AAwkACQp3JoQfAMwCAAkACAqNJIQfAMwCAAgABwoeJsoeAJECAAAA.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAACNQAFFH8cAAITAAUKLQp5CABgAQATAAUKLQp5CABgAQA1AAQKf2gAAhMACQr3FYEcAE0CABMACQr3FYEcAE0CAAAA.Frostienips:BAAANQAECgMIAwAAAA==.Frostiness:BAAANQADCgcIEQAAAA==.Frostmagee:BAAANQAECgQIBQAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAABNQAECn8qAAIYAAkKzQprGgCLAQAYAAkKzQprGgCLAQAAAA==.Fupanchoo:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Gallam:BAAANQADCggICAAAAA==.Garfeel:BAAANQAECgYIBgAAAA==.Garthurn:BAAANQAECgEIAQAAAA==.Gaskull:BAAANQAECgQICAAAAA==.Gaybacon:BAAANQADCgIIAgABNQAECgcIHwAcAJgiAA==.',
Ge='Gemli:BAAANQAECgUICQAAAA==.Geno:BAAANQAECgUIDAABNQAECgkJQgALADMmAA==.',
Gh='Ghostie:BAAANQADCggIEAAAAA==.Ghostsaber:BAAANQAECgUIEQAAAA==.',
Gi='Giddykitty:BAAANQAECgUIBgAAAA==.Gimballock:BAAANQAECgUIEgAAAA==.Gisakagda:BAAANQAECgQIBAAAAA==.Gital:BAAANQAECgEIAQAAAA==.',
Gl='Glennthehen:BAAANQAECgEIAQAAAA==.',
Go='Goatvier:BAACNQAFFH8WAAIbAAYK2yUlAACgAgAbAAYK2yUlAACgAgA1AAQKfykAAhsACQqEJowAANUDABsACQqEJowAANUDAAAA.Goblinator:BAAANQAECgYICwAAAA==.Golojo:BAAANQADCgQICAAAAA==.Goodenia:BAAANQAECgQIBAAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goomonic:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Goosef:BAAANQAECgcIDAAAAA==.Gopro:BAAANQADCgYIDwAAAA==.Gorbag:BAAANQADCgYJBwAAAA==.Gorhowl:BAABNQAECn8vAAILAAgK9h33TACfAgALAAgK9h33TACfAgAAAA==.Gorli:BAAANQADCggIHgAAAA==.Gottoloveit:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Gottolurveit:BAAANQAECgUICAAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAABNQAECn8sAAMKAAkK5SS6DgCQAwAKAAkK5SS6DgCQAwANAAMKTw/93ADBAAAAAA==.Gravadin:BAAANQAECgYICQAAAA==.Great:BAAANQAECgcIDwABNQAECgkJNAAdAEklAA==.Grennu:BAAANQADCggICAAAAA==.Gretchin:BAAANQAECgIIBAAAAA==.Groshlow:BAAANQAECgIIAwAAAA==.',
Gu='Guinness:BAAANQADCgIJAgAAAA==.Gulios:BAAANQAECgMIBQABNQAECgUIBwABAAAAAA==.Gunji:BAAANQAECgQIDQAAAA==.Guud:BAABNQAECn8dAAIMAAkKnxVPPgBkAgAMAAkKnxVPPgBkAgAAAA==.',
Gy='Gyukatsu:BAAANQADCgUIBQAAAA==.',
['Gä']='Gändalf:BAAANQAECgQIBgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesarrow:BAAANQAECgMIBgABNQAFFAYIEwAUAGEcAA==.Hadesblood:BAACNQAFFH8TAAIUAAYKYRxdCQDAAQAUAAYKYRxdCQDAAQA1AAQKfywAAhQACQrEITMSABkDABQACQrEITMSABkDAAAA.Hadeshammer:BAAANQAFFAEIAQABNQAFFAYIEwAUAGEcAA==.Hairlessrat:BAAANQAECgMIAwAAAA==.Hakzert:BAACNQAFFH8ZAAMhAAYKrhMYAwDUAQAhAAYKrhMYAwDUAQAZAAEKbQnrFAA/AAA1AAQKfykAAyEACQqAHW0KAN4CACEACQqAHW0KAN4CABkACQr3Cx0zAHgBAAAA.Happyfeett:BAAANQADCgQIBAAAAA==.Happyÿeet:BAAANQAECgQIBAAAAA==.Harex:BAABNQAECn8qAAQaAAgKrg/iKgDNAQAaAAgKrg/iKgDNAQAHAAcK+BQycgDBAQAGAAEKvQdgKAAzAAAAAA==.Harlon:BAAANQADCgcIEQAAAA==.Hartcake:BAAANQADCggIDAAAAA==.Haylø:BAAANQADCggICwAAAA==.Hazkalzzak:BAAANQADCggIEQAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Heckerz:BAAANQAECgEIAQAAAA==.Hektîc:BAAANQAECgcIDgAAAA==.Hellsgate:BAAANQAECgIIBgAAAA==.Hellshunter:BAABNQAECn8lAAIOAAgK9h/YNQDHAgAOAAgK9h/YNQDHAgAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQAECgQIAwAAAA==.Hexalock:BAABNQAECn8gAAIgAAkKcBPNVQBRAgAgAAkKcBPNVQBRAgAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgYICwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexiemattel:BAABNQAECn8VAAMkAAcKvBoYDgAXAgAkAAcKvBoYDgAXAgAgAAIKBQRJMQFPAAAAAA==.Hexington:BAAANQABCgMIAwAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hextralarge:BAAANQAECgcIDQAAAA==.Hezaq:BAABNQAECn8XAAIOAAcKzRlZhQD9AQAOAAcKzRlZhQD9AQAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollofeather:BAAANQAECgYIDAAAAA==.Hollowvoice:BAABNQAECn8qAAIUAAgKFCA1IgChAgAUAAgKFCA1IgChAgAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAABNQAECn8dAAMHAAgK1RxSMQCgAgAHAAgK1RxSMQCgAgAaAAMKLwi9XQCHAAAAAA==.Horacio:BAAANQAECgMIBgAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgYJBgAAAA==.Hunturd:BAAANQAECgMIBgAAAA==.Huntymcshoot:BAAANQAECgIIBAABNQAECggIEAABAAAAAA==.Huntér:BAAANQAECgcIDwAAAA==.',
['Hù']='Hùntrèss:BAAANQAECgYIEgAAAA==.',
['Hû']='Hûntress:BAAANQADCgYIBgAAAA==.',
Ic='Icdedpple:BAABNQAECn8eAAIIAAgKzxJVOwDdAQAIAAgKzxJVOwDdAQAAAA==.Icymama:BAAANQADCggIHwAAAA==.',
Id='Idevouryou:BAAANQADCgYIEQAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Il='Illicet:BAAANQADCgcIEAAAAA==.',
Im='Imchirp:BAAANQAECgQICAABNQAECgYIGwANAE4kAA==.Imicedup:BAAANQAECgUICgAAAA==.Impblaster:BAAANQAECgYIDQAAAA==.',
In='Inarius:BAABNQAECn8qAAIIAAcKpRTDQQC5AQAIAAcKpRTDQQC5AQAAAA==.Incompetent:BAAANQADCgcIFgAAAA==.Indriná:BAABNQAECn8aAAIHAAgKYhZjVgAcAgAHAAgKYhZjVgAcAgAAAA==.Inflictor:BAABNQAECn8jAAIMAAgKaxrjQABaAgAMAAgKaxrjQABaAgAAAA==.Insanenachos:BAAANQAECgUIEQAAAA==.Inumbra:BAAANQAECgQJBgAAAA==.',
Ir='Ironknee:BAABNQAECn8yAAIGAAkKyiHGAAB3AwAGAAkKyiHGAAB3AwAAAA==.',
Is='Isterra:BAAANQADCgUJBQAAAA==.',
It='Ithareos:BAAANQAECgUIDwAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQAECgUICwAAAA==.',
Iz='Izate:BAAANQAECgQICAAAAA==.Izulia:BAABNQAECn8mAAMUAAgKaCMqEgAZAwAUAAgKaCMqEgAZAwAIAAUKERMDWwA1AQAAAA==.Izulid:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQABNQAECgUIBQABAAAAAA==.Jabiraka:BAAANQADCggJEAAAAA==.Jackiexx:BAAANQAECgIIBAABNQAECgcIDgABAAAAAA==.Jackiie:BAAANQADCggIEAABNQAECgcIDgABAAAAAA==.Jadzena:BAAANQAECgIIAgABNQAFFAYIFwANAP4RAA==.Jaedrae:BAAANQADCgYIBgABNQAECgUIDwABAAAAAA==.Jahwe:BAAANQABCgMJBAAAAA==.Jakestanater:BAAANQAECgcIEwAAAA==.Jariko:BAAANQADCgYIBgAAAA==.Jassel:BAAANQAECgYIEwAAAA==.Jazmeine:BAAANQAECggIEAAAAA==.',
Jd='Jdubbs:BAAANQADCgcICQAAAA==.',
Je='Jestër:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAABNQAECn8rAAMPAAgKrg9UdgC6AQAPAAgKzQ1UdgC6AQAiAAcKYAv/HACOAQAAAA==.',
Jj='Jjester:BAAANQAECgYIDwAAAA==.',
Jl='Jlabinos:BAAANQAECgcIDwABNQAECggIIQADAFghAA==.Jlaby:BAABNQAECn8hAAIDAAgKWCHTHADgAgADAAgKWCHTHADgAgAAAA==.',
Jp='Jpxhunter:BAAANQAECggICwAAAA==.',
Ju='Juicei:BAABNQAECn8jAAIaAAgKvxYBIgAiAgAaAAgKvxYBIgAiAgAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
Jw='Jw:BAAANQAECggIAwAAAA==.',
['Jë']='Jëster:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.',
Ka='Kaehn:BAAANQAECgYIEQAAAA==.Kaesoron:BAABNQAECn82AAIgAAkKLBwVSgByAgAgAAkKLBwVSgByAgAAAA==.Kagéslammer:BAAANQADCggIGgAAAA==.Kairpally:BAAANQAECgYIDAAAAA==.Kaiser:BAABNQAECn8lAAMWAAkKeCFaBAD1AgAWAAgK3CBaBAD1AgALAAgKEB+KPADTAgAAAA==.Kaldrek:BAAANQADCgcICAAAAA==.Kanthan:BAAANQAECgEIAgAAAA==.Kanundrum:BAABNQAECn8bAAINAAYKTiRwOwB0AgANAAYKTiRwOwB0AgAAAA==.Karaxynn:BAABNQAECn8uAAIQAAkKjCD5DAASAwAQAAkKjCD5DAASAwAAAA==.Karmasnightt:BAAANQADCgYIEAAAAA==.Katratralle:BAAANQAECgEIAQAAAA==.Kaulder:BAAANQAECgUIDwAAAA==.',
Ke='Kebabyy:BAABNQAECn81AAMPAAkKMhWwUgArAgAPAAcKYBiwUgArAgAMAAcKxxreVQANAgAAAA==.Keeze:BAAANQADCgMIBAABNQAECggIHAAaAOoKAA==.Keheia:BAAANQADCgYICQAAAA==.Keilna:BAAANQAECgQIBAAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAABNQAECn8XAAIHAAcKRx+ZOwB4AgAHAAcKRx+ZOwB4AgAAAA==.Khodii:BAAANQAECgYIEAAAAA==.Khoho:BAAANQAECgUICgAAAA==.Khrøne:BAABNQAECn8eAAIJAAgKugyeYQCGAQAJAAgKugyeYQCGAQAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQAECgQIBwAAAA==.',
Ki='Kieranharrop:BAAANQAECgMIAwAAAA==.Killsaw:BAAANQABCgIIAgAAAA==.Kiltsusa:BAAANQAECggIAwAAAA==.Kity:BAAANQAECgUIEAAAAA==.',
Kn='Knail:BAAANQAECgUIEAAAAA==.Knickyou:BAAANQADCgYJCAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQAECgYICQAAAA==.Konokö:BAAANQADCgUJBQABNQAECgYICQABAAAAAA==.',
Kr='Kraii:BAAANQADCgIIAgAAAA==.Kreuzschlitz:BAAANQAECgEIAQAAAA==.Kreztek:BAAANQADCgQIBAAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQAECgUIDwAAAA==.Krippg:BAAANQADCgIIAgABNQAECggIIgALANwbAA==.Kripwar:BAABNQAECn8iAAILAAgK3BvxcgA4AgALAAgK3BvxcgA4AgAAAA==.Krizkin:BAAANQAECgYIDwAAAA==.Krugg:BAAANQAECgEIAgAAAA==.Krystal:BAAANQAECgcIDQAAAA==.',
Ku='Kungpao:BAAANQAECgcIBwAAAA==.Kurono:BAAANQADCgUIBQAAAA==.',
Ky='Kynhark:BAAANQAECgEIAQAAAA==.Kyoudo:BAABNQAECn89AAMWAAkKuhmUDQDaAQALAAkK+BjgawBLAgAWAAcKCxWUDQDaAQAAAA==.',
La='Laelha:BAAANQADCgUIBQAAAA==.Lasalia:BAAANQADCggIDAAAAA==.Latricia:BAAANQADCggIEAAAAA==.Laurél:BAABNQAECn8nAAIIAAgKqhNuOADtAQAIAAgKqhNuOADtAQAAAA==.Layonpaws:BAABNQAECn9LAAQdAAgKcyR4DgCyAgAdAAcKcyR4DgCyAgAKAAcKTxkqpQDRAQANAAEK+AptIwEuAAAAAA==.',
Le='Lecked:BAAANQAECgQIDQAAAA==.Leggodex:BAABNQAECn8UAAIOAAUKOxUyywBmAQAOAAUKOxUyywBmAQAAAA==.Leighandra:BAAANQAECgQIBwAAAA==.Lemures:BAABNQAECn8dAAIRAAgKEQ89IQDDAQARAAgKEQ89IQDDAQAAAA==.Leonà:BAAANQAECggIEwAAAA==.',
Li='Lidera:BAAANQADCggIDQAAAA==.Liebspawn:BAAANQAECgQICQAAAA==.Lightdefence:BAAANQADCgMIAwABNQAECgUIEwABAAAAAA==.Lightrasta:BAAANQAECgQIBgAAAA==.Lightreign:BAAANQAECgUIBwAAAA==.Lilhands:BAAANQAECgUIDwAAAA==.Linarisa:BAABNQAECn8jAAIeAAcKiiHQHQBgAgAeAAcKiiHQHQBgAgAAAA==.Liquidate:BAAANQAECgUJDQAAAA==.Litori:BAABNQAECn8hAAIJAAcKzBdfSwDkAQAJAAcKzBdfSwDkAQAAAA==.Littlepaly:BAAANQAECgEIAQAAAA==.Littleshammy:BAAANQAECgIIAwAAAA==.Livinlife:BAAANQADCgEIAQAAAA==.',
Ll='Llux:BAAANQADCggIDAAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAACNQAFFH8FAAIKAAIKCAXHKgBzAAAKAAIKCAXHKgBzAAA1AAQKfyoAAgoACQrMERiNAAYCAAoACQrMERiNAAYCAAAA.Looksmaxxor:BAABNQAECn8hAAIKAAkKxCCCIABAAwAKAAkKxCCCIABAAwAAAA==.Lorethemar:BAAANQADCgcIDQAAAA==.Loryn:BAABNQAECn8pAAIOAAkKWSLUJgD6AgAOAAkKWSLUJgD6AgAAAA==.',
Lu='Lucarro:BAAANQAFFAEIAQABNQAFFAQIFwARADQTAA==.Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAABNQAECn8ZAAIYAAUKQhh2IQA7AQAYAAUKQhh2IQA7AQAAAA==.Lunavale:BAAANQAECgcICwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECggIKQAKACAZAA==.Lytemup:BAAANQAECgUIBwAAAA==.',
['Lä']='Läkan:BAAANQAECgEIAQAAAA==.',
['Lù']='Lùcifer:BAABNQAECn8hAAMgAAkK2Q+IYAAzAgAgAAkK2Q+IYAAzAgAkAAEKAADjdAA5AAABNQAECgkJRAAUAHMcAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECgkJJgAOABUYAA==.Maenir:BAAANQADCggIDwAAAA==.Magnexion:BAAANQADCgQICAAAAA==.Magnytize:BAAANQAECgUIDgAAAA==.Magoose:BAABNQAECn8YAAIEAAkKPxaaggB5AgAEAAkKPxaaggB5AgAAAA==.Mags:BAACNQAFFH8IAAIDAAIKjAdkIACMAAADAAIKjAdkIACMAAA1AAQKfzoAAwMACQqyF1YpAIkCAAMACQqyF1YpAIkCABMABQpFDQAAAAAAAAAA.Majinboom:BAAANQAECggIDgAAAA==.Maldred:BAAANQAECgQIBwABNQAECgcIIQANANUeAA==.Maldreds:BAABNQAECn8hAAINAAcK1R4NPwBmAgANAAcK1R4NPwBmAgAAAA==.Manicmonday:BAAANQAECgQIBQAAAA==.Manycalavera:BAAANQAECgIIAgAAAA==.Marsie:BAABNQAECn8kAAIEAAgKaRjMpAA2AgAEAAgKaRjMpAA2AgAAAA==.Mashex:BAAANQAECgQJCgAAAA==.',
Me='Mealank:BAAANQAECggIAwABNQAECgkJKgAHAE0GAA==.Meatfridge:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Medieval:BAABNQAECn8mAAIIAAcKjiFxHQCbAgAIAAcKjiFxHQCbAgAAAA==.Mediyah:BAAANQADCgYIEwAAAA==.Medusacroft:BAAANQADCgUICAAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQAECgEJAQABNQAECgQIBwABAAAAAA==.Meljira:BAAANQAECgQIBwAAAA==.Melonyummy:BAACNQAFFH8aAAIfAAcK+yXiAADqAgAfAAcK+yXiAADqAgA1AAQKfygAAh8ACQrrJtgCAMUDAB8ACQrrJtgCAMUDAAAA.Menzel:BAAANQADCggIJwABNQAECgcIGAAdAGgYAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQAECgYIEAAAAA==.Mesohorni:BAAANQAECgUJAgAAAA==.Messerian:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.',
Mi='Michaelcai:BAAANQAECgEIAQAAAA==.Mikarika:BAAANQADCgEIAQAAAA==.Milky:BAAANQAECgUIBgABNQAFFAQIBAABAAAAAA==.Milzey:BAABNQAECn8rAAIlAAkKFiEJAQB8AwAlAAkKFiEJAQB8AwAAAA==.Mindweaver:BAABNQAECn8dAAIhAAcKMyEbDgCdAgAhAAcKMyEbDgCdAgAAAA==.Miniscule:BAAANQAECgYIBgAAAA==.Minizap:BAAANQAECggIEwAAAA==.Miradin:BAAANQAECgUICwAAAA==.Mirv:BAACNQAFFH8IAAIXAAMK7R6HAQA3AQAXAAMK7R6HAQA3AQA1AAQKfykAAhcACQqIIZEBADsDABcACQqIIZEBADsDAAAA.Misshapp:BAAANQADCgIIAgAAAA==.Misspickles:BAABNQAECn8tAAIPAAgKLR6rKgDTAgAPAAgKLR6rKgDTAgAAAA==.Mistakoji:BAAANQAECgUICAAAAA==.',
Mo='Mogwii:BAAANQAECggJAgAAAA==.Moit:BAAANQADCgYICwAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQAECgQIDAAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monoblood:BAAANQAECggIAgAAAA==.Monoearth:BAAANQAECgQIBAAAAA==.Monononoke:BAAANQADCgYIDQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monsteritis:BAAANQADCggICAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Moosocalypse:BAAANQADCgUIBQAAAA==.Morella:BAAANQAECgEIAQAAAA==.Morgai:BAAANQADCgcIBwAAAA==.',
Mu='Munta:BAAANQADCgYIFAAAAA==.Munter:BAABNQAECn8ZAAINAAgKcReYSgA8AgANAAgKcReYSgA8AgABNQAFFAQIBAABAAAAAA==.Mursha:BAAANQAECgUIEwAAAA==.Muted:BAABNQAECn8cAAIiAAkKixHUEgA5AgAiAAkKixHUEgA5AgAAAA==.Muzblue:BAACNQAFFH8QAAIPAAUK3CW5BgAJAgAPAAUK3CW5BgAJAgA1AAQKfx4AAg8ABwqqJtslAOoCAA8ABwqqJtslAOoCAAAA.Muzw:BAAANQAECgcIEAABNQAFFAgIBgAeAJglAA==.Muzz:BAAANQAECgMIAwAAAA==.',
My='Mythreem:BAAANQAECgMJAwAAAA==.',
['Mä']='Mädness:BAAANQAECgIIBAABNQAFFAcIGgAfAPslAA==.',
['Mï']='Mïkarika:BAABNQAECn8fAAIOAAcKJRF7lADcAQAOAAcKJRF7lADcAQAAAA==.',
Na='Naalaxii:BAABNQAECn8mAAIOAAkKFRg1SQCPAgAOAAkKFRg1SQCPAgAAAA==.Naero:BAABNQAECn8UAAMMAAUKRiKWXwDsAQAMAAUKRiKWXwDsAQAPAAMKMh+MxAAFAQAAAA==.Naerond:BAAANQAECgEIAQAAAA==.Nalfeiin:BAABNQAECn8nAAIJAAcKExIqWwCfAQAJAAcKExIqWwCfAQAAAA==.Narnardk:BAABNQAECn8bAAIIAAkKbB7NGwCoAgAIAAkKbB7NGwCoAgAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrex:BAAANQABCgUIBAAAAA==.Natrstorm:BAABNQAECn89AAIYAAkKsCNtBQAbAwAYAAkKsCNtBQAbAwAAAA==.Naturised:BAABNQAECn8XAAITAAcKbRIqMACVAQATAAcKbRIqMACVAQAAAA==.Naursalla:BAAANQADCggIEgAAAA==.Nawe:BAAANQAECgcIDQAAAA==.Naxaris:BAAANQADCgMIAwAAAA==.',
Ne='Necratia:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Neflyn:BAAANQAECgQIBgAAAA==.Nemmystrata:BAAANQAECgUIDwAAAA==.Nessaandra:BAABNQAECn8pAAIgAAgKiQnInACZAQAgAAgKiQnInACZAQAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDgAAAA==.',
Ni='Niftage:BAAANQAECgEIAgABNQAECgcIGgAOAJMPAA==.Niftana:BAABNQAECn8aAAIOAAcKkw8WnQDJAQAOAAcKkw8WnQDJAQAAAA==.Nimirie:BAAANQAECgcIDgAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQIBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Nokshaman:BAAANQAECgYIEwAAAA==.Noxtard:BAAANQADCggJEAAAAA==.',
Ny='Nyghtware:BAABNQAECn8VAAMFAAgKIAkhHgD3AAAFAAUKhAwhHgD3AAAEAAYK0QPrdQHOAAAAAA==.',
['Nì']='Nìx:BAAANQAECgUICQAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQAECgUIDQAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQAECgIIAgABNQAECgcIBQABAAAAAA==.',
Ok='Okazi:BAABNQAECn8lAAIhAAgK4xrNEABuAgAhAAgK4xrNEABuAgABNQAECggIKgAaAK4PAA==.',
Ol='Olafuga:BAABNQAECn89AAITAAkKrRqUGAB2AgATAAkKrRqUGAB2AgAAAA==.Oldblood:BAAANQABCgIJAgABNQADCgUIBQABAAAAAA==.',
Oo='Ookolok:BAAANQADCggIDQAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Op='Oppressor:BAAANQAECgMIAwAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCggIFAAAAA==.Ormal:BAAANQAECgIIAgAAAA==.',
Os='Osma:BAAANQAECgUIBwABNQAFFAcIJQAgADchAA==.Osmess:BAAANQAECgYIEwABNQAFFAcIJQAgADchAA==.Osmology:BAACNQAFFH8lAAQgAAcKNyEbAgB9AgAgAAYKASAbAgB9AgAkAAIKBSQUBQDIAAAXAAEKAAAaCwBQAAA1AAQKfysABCAACQo2JokwAMMCACAABwo1JokwAMMCACQABgpDGEUYAKkBABcAAQrnFusrAD4AAAAA.',
Ov='Overwhelmed:BAAANQAECgUIDwAAAA==.',
Oz='Ozzietree:BAABNQAECn8jAAIDAAkKnB+dIgC4AgADAAkKnB+dIgC4AgAAAA==.',
Pa='Paddingtonn:BAAANQAECgEIAQAAAA==.Pandachì:BAABNQAECn8lAAIiAAgKphA4FQARAgAiAAgKphA4FQARAgAAAA==.Pandamick:BAAANQAECgEIAQAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggJCAABNQAFFAIIBgAkAF4ZAA==.Parallaxia:BAACNQAFFH8GAAMkAAIKXhkgGABTAAAgAAEKURtzOgBWAAAkAAEKaxcgGABTAAA1AAQKfyUAAyAACQqyIUBcAD8CACAABwpkIEBcAD8CACQAAgr0JI1GAKwAAAAA.Paulmedic:BAABNQAECn8zAAMhAAkK0iYbAAAEBAAhAAkK0iYbAAAEBAAZAAcK+xVtKADYAQAAAA==.',
Pb='Pbjellytime:BAABNQAECn8aAAIiAAYKKBOmHACUAQAiAAYKKBOmHACUAQAAAA==.',
Pe='Peadle:BAAANQAECgYIBwABNQAECgkJKgAHAE0GAA==.Pegasuz:BAAANQAECggICQAAAA==.Pello:BAAANQADCgMIAwAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQAECgQIBgAAAA==.',
Ph='Phallics:BAAANQAECgcIEgABNQAFFAcIIAAdAFohAA==.Phoènix:BAABNQAECn8iAAIEAAgKNhtsfgCBAgAEAAgKNhtsfgCBAgAAAA==.',
Pi='Pikyx:BAABNQAECn8dAAIgAAcKVgUtyQAzAQAgAAcKVgUtyQAzAQAAAA==.Pinkrock:BAABNQAECn8tAAIKAAkKGx16OADsAgAKAAkKGx16OADsAgAAAA==.',
Pl='Playboicarti:BAAANQAECggIEAAAAA==.Playmate:BAAANQAECgYICgAAAA==.Plopperoo:BAABNQAECn8uAAIDAAcKTh6gKgCBAgADAAcKTh6gKgCBAgAAAA==.Plusop:BAAANQADCgMIAwABNQAFFAQIFwARADQTAA==.',
Po='Pocaface:BAABNQAECn8ZAAIOAAgKIg9rbgAyAgAOAAgKIg9rbgAyAgAAAA==.Pogmourne:BAACNQAFFH8cAAIUAAUK3Rl4CQC/AQAUAAUK3Rl4CQC/AQA1AAQKf2gAAhQACQrTIsYLAFMDABQACQrTIsYLAFMDAAAA.Polyform:BAABNQAECn8iAAMCAAkKPSK6BABXAwACAAkKPSK6BABXAwAjAAIKexmhMACGAAAAAA==.',
Pr='Preserved:BAABNQAECn8dAAMMAAcK0SJJLACvAgAMAAcK0SJJLACvAgAPAAQK1glw5ADIAAAAAA==.Priestsen:BAAANQADCggIIwAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Puru:BAABNQAECn8ZAAIWAAYKHRdvEgB4AQAWAAYKHRdvEgB4AQAAAA==.Pussiepunchn:BAAANQADCgMIAwAAAA==.',
Py='Pyrhus:BAABNQAECn8jAAIFAAgKKxI9DQDbAQAFAAgKKxI9DQDbAQAAAA==.',
['Pâ']='Pâkerious:BAAANQAECgYIEQAAAA==.',
['Pæ']='Pælstrå:BAABNQAECn8dAAIiAAgK9BTzEgA2AgAiAAgK9BTzEgA2AgAAAA==.',
['Pè']='Pèppermint:BAAANQAECgYJEAABNQAECggIJAAHALYaAA==.',
Qi='Qicacid:BAACNQAFFH8IAAMLAAQKIRlUFwBgAQALAAQKahhUFwBgAQAWAAEKISBWBQBPAAA1AAQKfzcAAwsACQq9JbwTAGsDAAsACAq4JbwTAGsDABYACAraHy4FANICAAE1AAUUBAgXABEANBMA.',
Ra='Racoondog:BAAANQAECgYICwABNQAECggIIgALANwbAA==.Raehalian:BAAANQADCgcICQAAAA==.Rafedrood:BAABNQAECn8aAAQCAAgK5QsgNwDnAAACAAUKew0gNwDnAAADAAUKzgbQfwDLAAAjAAQKFwc7LACqAAAAAA==.Rafemonk:BAABNQAECn8WAAMZAAYK8watRwDdAAAZAAYK8watRwDdAAAcAAEKXwX7MQAsAAABNQAECgkJLQAKABcPAA==.Rafepally:BAABNQAECn8tAAIKAAkKFw+QlAD2AQAKAAkKFw+QlAD2AQAAAA==.Raharn:BAAANQADCgYIBgAAAA==.Raiigun:BAABNQAECn8lAAIOAAgKow6ZhwD4AQAOAAgKow6ZhwD4AQAAAA==.Rakutina:BAAANQADCgUIDwAAAA==.Ramann:BAABNQAECn8jAAIFAAgKjxpEBwB8AgAFAAgKjxpEBwB8AgAAAA==.Rampart:BAAANQADCgcIBwAAAA==.Rarule:BAAANQAECggICQAAAA==.Rarulé:BAAANQAECggIBQAAAA==.Raspberry:BAAANQADCgQIBAAAAA==.Rastianklin:BAAANQAECgQIBgAAAA==.Ratbro:BAAANQAECgUIDwAAAA==.Rawrbewb:BAAANQAECgEIAgABNQAECgkJLgAEAJ8lAA==.Rawrbewbs:BAAANQAECgMIAwABNQAECgkJLgAEAJ8lAA==.Rawrbewbz:BAABNQAECn8uAAIEAAkKnyU1DACkAwAEAAkKnyU1DACkAwAAAA==.Rawrbutt:BAAANQAECgEIAQABNQAECgkJLgAEAJ8lAA==.Rawrnewbz:BAAANQAECgUIBwABNQAECgkJLgAEAJ8lAA==.Rawrnoobz:BAAANQAECgMIAwABNQAECgkJLgAEAJ8lAA==.Rayburd:BAABNQAECn8YAAMXAAgKuRx6BwAjAgAXAAcKtR56BwAjAgAgAAUKehMw0gAgAQAAAA==.Raypejeet:BAABNQAECn8XAAIJAAkKAyKrJQClAgAJAAkKAyKrJQClAgAAAA==.Raziiel:BAABNQAECn8iAAIfAAgKSQ7jPQDGAQAfAAgKSQ7jPQDGAQAAAA==.',
Rb='Rbed:BAAANQAECgYJDwAAAA==.',
Re='Realhuman:BAABNQAECn8pAAILAAkKMxlKWAB/AgALAAkKMxlKWAB/AgAAAA==.Recharge:BAABNQAECn8hAAIHAAgKjRcBSQBHAgAHAAgKjRcBSQBHAgAAAA==.Redhoaxx:BAAANQAECgUIBQAAAA==.Redpally:BAAANQAECgMIBAAAAA==.Redrock:BAAANQADCgYIBwABNQAECgkJLQAKABsdAA==.Relinna:BAABNQAECn8bAAMUAAcK0BiNTgC4AQAUAAYKSRuNTgC4AQAIAAIKlgcBngBNAAAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAFFAIICAADAIwHAA==.Rend:BAAANQADCgMIAwAAAA==.Renegade:BAAANQAECggIAgAAAA==.Resly:BAACNQAFFH8HAAIZAAMKTRmOCwDvAAAZAAMKTRmOCwDvAAA1AAQKfy0AAhkACQrKImYNAAMDABkACQrKImYNAAMDAAAA.Resurrected:BAAANQADCgYIBgAAAA==.Reulna:BAAANQADCgMIAwAAAA==.Revolutionix:BAAANQAECgUIEQAAAA==.',
Rh='Rhodie:BAABNQAECn8aAAMVAAgKPhluMQAUAgAVAAcKPhluMQAUAgAmAAIKWwZpSQBmAAAAAA==.Rhyfelglod:BAAANQAECgQIBAABNQAFFAMIBwARAJgiAA==.',
Ri='Ricuid:BAABNQAECn8XAAIjAAcKMBLBFgCJAQAjAAcKMBLBFgCJAQAAAA==.Ridemption:BAAANQAECgcIDAAAAA==.Rifkin:BAAANQAECgQIBQAAAA==.Rigamautist:BAABNQAECn8fAAIUAAcKbRX4SgDIAQAUAAcKbRX4SgDIAQAAAA==.Rightguy:BAAANQAECgQIBAAAAA==.Risaka:BAAANQAECgYICgAAAA==.',
Ro='Roadkill:BAAANQAECgIIBAAAAA==.Roar:BAAANQAECggIAQAAAA==.Roots:BAABNQAECn8YAAIhAAcK1hpWFgATAgAhAAcK1hpWFgATAgAAAA==.Rotelle:BAAANQADCgMJBQAAAA==.Rottenalbo:BAAANQAECgQJDAABNQAECgYIDQABAAAAAA==.',
Ru='Rustyaslock:BAABNQAECn85AAMgAAkKeA5fggDbAQAgAAkKeA5fggDbAQAkAAEK9wMbgAArAAAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECggIEwAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Sajal:BAAANQADCgIIAgABNQAECgkJIwAHAEsfAA==.Saladin:BAABNQAECn8dAAIdAAcKzhNXKgCGAQAdAAcKzhNXKgCGAQAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQAECgEJAQAAAA==.Samoid:BAAANQADCgcIDQABNQAFFAYIFAAhAO0cAA==.Sanguiniüs:BAAANQAECgYICwAAAA==.Santhea:BAAANQAECgUIDQAAAA==.Sarash:BAAANQAECgMIAwABNQADCgYICwABAAAAAA==.Sarixz:BAABNQAECn8jAAIPAAkK+hdvPwB1AgAPAAkK+hdvPwB1AgAAAA==.Sarzyb:BAABNQAECn8lAAIPAAkKLBBwWgAQAgAPAAkKLBBwWgAQAgAAAA==.Sashka:BAAANQAECggIEQAAAA==.Satsuy:BAAANQAFFAEIAQAAAA==.Savaric:BAAANQADCggIFQAAAA==.',
Sc='Scott:BAABNQAECn8/AAILAAkK/SCsIAA0AwALAAkK/SCsIAA0AwAAAA==.Scrubturkey:BAAANQAECgUICwAAAA==.Scuntpetz:BAAANQADCggIDQAAAA==.',
Se='Seamonology:BAAANQAECgcIEgABNQAFFAUIDwAUAFMLAA==.Seether:BAAANQAFFAQIBAABNQAFFAUIDAAVANkaAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seraithe:BAAANQABCgMIBQAAAA==.Seravael:BAAANQAECgUIDQAAAA==.Sethbash:BAAANQADCggIDwAAAA==.',
Sh='Shadowvoice:BAABNQAECn8bAAQEAAgKlAfv+QCVAQAEAAgKswbv+QCVAQAnAAIKZghwCQBwAAAFAAEKHQjDTQAqAAAAAA==.Shallan:BAABNQAECn8qAAMEAAgKSR7dpQA0AgAEAAcKgBzdpQA0AgAFAAIKGx8fKgCkAAAAAA==.Shamann:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Shapymcshift:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Shard:BAAANQADCggJEgAAAA==.Shelemouncy:BAAANQADCgYIBwABNQAECgkJKgAHAE0GAA==.Shieldzu:BAAANQAECgQIBAAAAA==.Shlappy:BAACNQAFFH8TAAIUAAUKQR57DgBmAQAUAAUKQR57DgBmAQA1AAQKf1UAAhQACQq4ITcQACoDABQACQq4ITcQACoDAAAA.',
Si='Sijki:BAAANQAECgUIBwAAAA==.Silversham:BAABNQAECn8hAAMMAAkKsR98PgBjAgAMAAgK2x58PgBjAgAPAAcKuQuvmgBfAQAAAA==.Silversnow:BAAANQADCggJFAAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAABNQAECn83AAIYAAgKFR7pCAC/AgAYAAgKFR7pCAC/AgAAAA==.Skiddy:BAACNQAFFH8iAAIRAAcKCBouAwBdAgARAAcKCBouAwBdAgA1AAQKfyoAAhEACQrMIbkIABcDABEACQrMIbkIABcDAAAA.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skrug:BAAANQAECgYICAAAAA==.',
Sl='Slowdeath:BAAANQAECgcIEAAAAA==.Slysham:BAABNQAECn8jAAIPAAgKVB2lMwCnAgAPAAgKVB2lMwCnAgAAAA==.',
Sm='Smeevil:BAABNQAECn8kAAMPAAgKfxcQcwDEAQAPAAYKLxsQcwDEAQAMAAYKKBLungA1AQAAAA==.Smellyfridge:BAAANQADCgQICAABNQAECgQICQABAAAAAA==.',
Sn='Snazzapriest:BAAANQAECgcIDgAAAA==.Sneeds:BAACNQAFFH8tAAIUAAcKVB40AgCFAgAUAAcKVB40AgCFAgA1AAQKf1gAAhQACQp9JV8FAJwDABQACQp9JV8FAJwDAAAA.Snowdrifter:BAAANQADCggICQAAAA==.Snowflicker:BAAANQAECgMIBgAAAA==.Snowhail:BAABNQAECn8gAAIdAAgKXBupEgB1AgAdAAgKXBupEgB1AgAAAA==.',
So='Soal:BAAANQAECgQIBgAAAA==.Soaringsky:BAACNQAFFH8OAAIEAAQKMQ9AKQA5AQAEAAQKMQ9AKQA5AQA1AAQKfycAAgQACQqrHXlWANMCAAQACQqrHXlWANMCAAAA.Solarflares:BAABNQAECn8pAAIDAAgKwQtZTwCdAQADAAgKwQtZTwCdAQAAAA==.Sopheeaa:BAABNQAECn8cAAIOAAcKlBDylADbAQAOAAcKlBDylADbAQAAAA==.Soria:BAAANQAECgYIDQAAAA==.Soulblessed:BAABNQAECn8qAAMNAAkK4x7xIADoAgANAAgKCyDxIADoAgAKAAYKaA1O9gArAQAAAA==.Soursop:BAAANQADCgUJCAAAAA==.',
Sp='Sparkychops:BAAANQAECgUIBwAAAA==.Spaztik:BAAANQAECggICwAAAA==.Spectrefive:BAAANQADCgcIFQAAAA==.Spectretwo:BAABNQAECn8UAAIHAAYKcBGKiwBvAQAHAAYKcBGKiwBvAQAAAA==.Spelcastro:BAAANQAECgYIDAAAAA==.Spherical:BAAANQAECgEIAQABNQAECgkJIgASACYhAA==.Spknox:BAAANQADCggIIAABNQAECggIDwABAAAAAA==.Splat:BAAANQAECgQIBAAAAA==.Spooklet:BAAANQAECgMIBAAAAA==.Spoonboy:BAABNQAECn8qAAIJAAkKmyC6DwA4AwAJAAkKmyC6DwA4AwAAAA==.',
Sq='Squirtmore:BAABNQAECn8ZAAIEAAgKVRRRtAAZAgAEAAgKVRRRtAAZAgAAAA==.Squirtsalot:BAABNQAECn8fAAMgAAgKCxxiYgAuAgAgAAgKsRhiYgAuAgAkAAEKvRtmbQBDAAAAAA==.',
St='Starielle:BAAANQAECgUIEwAAAA==.Stark:BAAANQAECgUIEQAAAA==.Steinman:BAAANQAECgMIBQABNQAECgUIBQABAAAAAA==.Stemple:BAABNQAECn8jAAIPAAcKHBpQVQAhAgAPAAcKHBpQVQAhAgAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAABNQAECn8aAAIiAAcK1R5pDwBwAgAiAAcK1R5pDwBwAgAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQAECgIIAgAAAA==.Stubsy:BAAANQADCgQJBAAAAA==.',
Su='Sublet:BAABNQAECn8YAAIdAAcKaBhxIgDLAQAdAAcKaBhxIgDLAQAAAA==.Subwayy:BAABNQAECn8oAAMEAAgKOhZZuAARAgAEAAgKJhBZuAARAgAFAAIKmBz3KQClAAABNQAECgkJNQAPADIVAA==.Sunshÿne:BAAANQAECgEIAQAAAA==.Suunshine:BAABNQAECn9EAAIUAAkKcxzQJQCMAgAUAAkKcxzQJQCMAgAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAABNQAECn8qAAITAAgKCQ6YLgCiAQATAAgKCQ6YLgCiAQAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Symbiotic:BAAANQAECgQIBAAAAA==.Synfal:BAABNQAECn8aAAIKAAgKcRlHcABLAgAKAAgKcRlHcABLAgAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAABNQAECn8pAAQZAAcKrwfgQQACAQAZAAYKJwfgQQACAQAcAAYKwQYzHwDuAAAhAAEKohPbSwAxAAAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAABNQAECn8bAAMXAAgKLhD1BwAVAgAXAAgKLhD1BwAVAgAgAAEKDwHRXgEFAAAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgcIDQABNQAECgUIEQABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICwAAAA==.',
['Sý']='Sýrézz:BAAANQADCggICAAAAA==.',
Ta='Taemire:BAAANQAECgMIAwABNQAECgkJNwAaAJgTAA==.Taezi:BAAANQADCgUIBQAAAA==.Tagger:BAAANQAECgUIBgAAAA==.Tahlia:BAABNQAECn8bAAIMAAgKphKtbwC5AQAMAAgKphKtbwC5AQAAAA==.Takaiya:BAABNQAECn8fAAMkAAcK/iJ0BADjAgAkAAcK/iJ0BADjAgAgAAEKAAC1MgFKAAAAAA==.Tanglethorn:BAAANQAECgUIBQAAAA==.Tauna:BAAANQADCgQIBAAAAA==.Taur:BAABNQAECn8ZAAIWAAgKDBZECgAlAgAWAAgKDBZECgAlAgAAAA==.',
Te='Technosis:BAAANQADCggIHQAAAA==.Techuu:BAACNQAFFH8cAAMLAAcK+hskBQB2AgALAAcK+hskBQB2AgAWAAIKEQYvAwCbAAA1AAQKfykAAgsACQqxI5cZAFADAAsACQqxI5cZAFADAAAA.',
Th='Thade:BAAANQADCgYICwABNQAECgcIHwAcAJgiAA==.Thalynra:BAAANQAECgIIAgAAAA==.Thatdamdruid:BAABNQAECn8ZAAIDAAgKwAHUiACsAAADAAgKwAHUiACsAAAAAA==.Thekhole:BAAANQAECggIDwAAAA==.Thekrelltoss:BAABNQAECn8yAAIEAAkKFCIEGgBtAwAEAAkKFCIEGgBtAwAAAA==.Thoriandis:BAAANQAECgQICwAAAA==.Thör:BAAANQADCggICAAAAA==.',
Ti='Tinderella:BAAANQADCgIJAgAAAA==.Tinjam:BAAANQADCgYJBgAAAA==.Tintarella:BAAANQADCgQJBAAAAA==.Titaniumman:BAAANQAECgYIEgAAAA==.',
Tj='Tjirp:BAAANQAECgUIDQABNQAECgYIGwANAE4kAA==.',
To='Tohka:BAAANQAECgQIBwABNQAECgkJLAAhANslAA==.Tohkna:BAAANQAECgIIAgABNQAECgkJLAAhANslAA==.Torale:BAAANQAECgMIBgAAAA==.Tormentar:BAAANQADCgMIAwAAAA==.Totemstout:BAAANQAECgQICAAAAA==.Totemìc:BAAANQADCgUIBwAAAA==.Toteshadow:BAAANQAECgQIBgABNQAECggIKQADAPcbAA==.Tovuk:BAABNQAECn8gAAIbAAgKzhoACQBbAgAbAAgKzhoACQBbAgAAAA==.',
Tr='Tranquilitee:BAABNQAECn8kAAITAAgKQR2WFgCLAgATAAgKQR2WFgCLAgAAAA==.Traphic:BAAANQAECgUIBQAAAA==.Traumateam:BAAANQADCgYJEAABNQAECgUIDwABAAAAAA==.Trebdk:BAAANQAECgYICgAAAA==.Trebpal:BAABNQAECn8iAAIdAAkKYx6aCAASAwAdAAkKYx6aCAASAwAAAA==.Treecoleos:BAABNQAECn8bAAMDAAgKxwkzVQCAAQADAAgKxwkzVQCAAQATAAgKYQngNQBoAQAAAA==.Treigha:BAAANQADCggIDwABNQAECgkJPQAWALoZAA==.Tripleseven:BAAANQADCgUIBQAAAA==.Triplesix:BAAANQAECgIIBAAAAA==.Trâck:BAAANQABCgIIAgAAAA==.',
Tw='Tweetconic:BAAANQAECgEIAQAAAA==.Tweetess:BAAANQAECgQIBAAAAA==.Twothreesix:BAAANQAECgEIAwAAAA==.Twîsted:BAAANQADCggIGAABNQAECggIGgAKAHEZAA==.',
Ty='Tyborel:BAABNQAECn8oAAMOAAkK0yKVIgALAwAOAAkK0yKVIgALAwAlAAgKtB0eBACuAgAAAA==.Tydro:BAABNQAECn8cAAMLAAgKeRUroQDFAQALAAcKoBMroQDFAQAWAAMKfxb7HADaAAAAAA==.Tyranoc:BAABNQAECn8bAAMbAAkK8BNlCgAxAgAbAAkK7BNlCgAxAgAfAAUKXgz9XAAHAQAAAA==.',
Tz='Tzago:BAAANQAECgEIAgAAAA==.',
Ud='Udòngeìn:BAAANQADCggIFAAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Un='Unholyvixen:BAAANQAECgYIBgAAAA==.',
Us='Usedtobecool:BAAANQAECgYIBwAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQAECgQIBAAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAABNQAECn8oAAIMAAgK6AuPggCBAQAMAAgK6AuPggCBAQAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwABNQABCggIDQABAAAAAA==.Valthalus:BAAANQADCgYIDwAAAA==.Valvet:BAAANQAECgUICAAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQAECgUICQAAAA==.Vellarya:BAAANQAECgYIEAAAAA==.Velthrax:BAABNQAECn8zAAIOAAkKuSQSBQC7AwAOAAkKuSQSBQC7AwAAAA==.Velypsi:BAAANQADCggIEgAAAA==.Velìn:BAAANQADCggIGwAAAA==.Velín:BAABNQAECn8uAAMLAAkKqhwdQwC9AgALAAkKqhwdQwC9AgAWAAIKxgu0KABlAAAAAA==.',
Vi='Vilaina:BAAANQAECgUICQAAAA==.Villeneth:BAAANQAECgYIDAAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAABNQAECn8kAAMLAAkKnBUPbgBFAgALAAkKnBUPbgBFAgAWAAEKAADyMgA0AAAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.Vizzo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Vo='Vocck:BAAANQAECgQIBQAAAA==.Vock:BAAANQABCgUIBQABNQAECgkJLgAEAIEYAA==.Vokk:BAAANQAECggIDQABNQAECgkJLgAEAIEYAA==.Vozie:BAABNQAECn8uAAIEAAkKgRikcQCaAgAEAAkKgRikcQCaAgAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAABNQAECn8eAAIEAAgKzxZPrAAoAgAEAAgKzxZPrAAoAgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
['Vâ']='Vânâ:BAAANQADCgYIBgAAAA==.',
['Vó']='Vóltron:BAAANQAECgUIBQAAAA==.',
Wa='Wackman:BAABNQAECn8qAAIJAAgKbCTCDgBAAwAJAAgKbCTCDgBAAwAAAA==.Wargold:BAAANQADCggICAABNQAECgkJIQAMALEfAA==.Warmfridge:BAAANQAECgQICQAAAA==.Wartiant:BAABNQAECn8tAAILAAcKOwz6vAB/AQALAAcKOwz6vAB/AQAAAA==.',
Wh='Whiskytango:BAAANQADCgEIAQAAAA==.Whitehall:BAAANQAECgUIEAAAAA==.Whocouldube:BAAANQADCgEJAQAAAA==.Wholegrain:BAABNQAECn8kAAIHAAgKthobQwBcAgAHAAgKthobQwBcAgAAAA==.',
Wi='Wickidin:BAAANQADCgMIAwAAAA==.Windhorn:BAABNQAECn8aAAIOAAcK9xSNjgDpAQAOAAcK9xSNjgDpAQAAAA==.Windi:BAAANQAECgYICgAAAA==.Wiro:BAAANQAECgUICAAAAA==.Wirø:BAAANQAECgUIDgAAAA==.',
Wo='Wobbling:BAABNQAECn8YAAILAAkKgxQreQAoAgALAAkKgxQreQAoAgAAAA==.Wobblock:BAAANQAECgUICgAAAA==.Wombee:BAAANQAECgQIBAAAAA==.Wonderia:BAABNQAECn8rAAIhAAkKvxibDgCVAgAhAAkKvxibDgCVAgAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
Wy='Wylia:BAABNQAECn8WAAIaAAgKrQiNNQBzAQAaAAgKrQiNNQBzAQAAAA==.',
['Wí']='Wíiman:BAAANQAECggIDwAAAA==.',
Xa='Xalath:BAAANQAECgUICAAAAA==.Xamxam:BAAANQADCgYIBgAAAA==.',
Xe='Xeenah:BAABNQAECn9XAAMeAAgKRwiLOQB+AQAeAAgKzwaLOQB+AQAOAAIKiQmGMAGAAAAAAA==.',
Xi='Xiconz:BAAANQADCgUIBQAAAA==.Xilef:BAAANQAECgUICAAAAA==.',
Xx='Xxjackie:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.',
Xy='Xyz:BAACNQAFFH8MAAMVAAUK2RpUCACEAQAVAAUK2RpUCACEAQAmAAEK9BYmFABIAAA1AAQKfxsAAxUACQp/IBMcAJkCABUACQooIBMcAJkCACYABQpJFGkwADYBAAAA.',
Ya='Yamaka:BAACNQAFFH8cAAICAAcKeSIdAADmAgACAAcKeSIdAADmAgA1AAQKfyUAAgIACQquJvUAAOUDAAIACQquJvUAAOUDAAAA.',
Ys='Yseult:BAAANQAECgQICgAAAA==.',
Za='Zaarocc:BAABNQAECn8ZAAIOAAkKTyBTEgBWAwAOAAkKTyBTEgBWAwAAAA==.Zaarock:BAACNQAFFH8HAAIJAAMKQBXqEAD3AAAJAAMKQBXqEAD3AAA1AAQKfy8AAwkACQrPH/sZAO8CAAkACQrPH/sZAO8CABQAAQoAAMDHADYAAAAA.Zaishadow:BAABNQAECn8cAAIVAAgKrQ0tNwD1AQAVAAgKrQ0tNwD1AQAAAA==.Zandro:BAABNQAECn8WAAMKAAcKMB0CzgB5AQAKAAUK6hoCzgB5AQANAAQKkBfRoABAAQAAAA==.Zandrocas:BAAANQAECgEIAgAAAA==.Zanduill:BAAANQAFFAEIAQAAAA==.Zanhighawen:BAAANQADCggIHgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQAECgcIEQAAAA==.Zayva:BAABNQAECn8YAAIfAAcKxApOTgBdAQAfAAcKxApOTgBdAQAAAA==.',
Ze='Zeala:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Zealfu:BAAANQAECgQIBwABNQAECgUIDgABAAAAAA==.Zeali:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Zeals:BAAANQADCgQIBAAAAA==.Zealthyr:BAAANQAECgUIDgAAAA==.Zeztuknar:BAAANQAECgYIDwAAAA==.',
Zi='Ziege:BAAANQAECgcICAAAAA==.Zincberg:BAAANQAECgIIAgAAAA==.Ziyn:BAABNQAECn8bAAINAAkKShffOQB7AgANAAkKShffOQB7AgABNQAFFAUICgAeALsPAA==.',
Zo='Zorbax:BAAANQAECgUIDwAAAA==.',
Zy='Zykaei:BAABNQAECn8sAAIhAAkK2yVrAQC6AwAhAAkK2yVrAQC6AwAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAgABNQAECgcIEQABAAAAAA==.',
['Ás']='Áshenshúgar:BAAANQAECgUIBQAAAA==.',
['Áy']='Áylamao:BAABNQAECn8rAAIfAAcKrQ4VSQB9AQAfAAcKrQ4VSQB9AQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggIPwAAAA==.',
['Éh']='Éh:BAABNQAECn8aAAIQAAgKfRAdKwDlAQAQAAgKfRAdKwDlAQAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECggIVgAGAIscAA==.Ðisciple:BAABNQAECn9WAAMGAAgKixySCADYAQAHAAcK7ByfRABWAgAGAAYK0RuSCADYAQAAAA==.',
['Øb']='Øbiwan:BAAANQAECgUIBQAAAA==.',
['Øc']='Øctavia:BAAANQADCgQIBQAAAA==.',
['ßi']='ßinchicken:BAABNQAECn8hAAISAAcK3QEBLADAAAASAAcK3QEBLADAAAAAAA==.',
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
