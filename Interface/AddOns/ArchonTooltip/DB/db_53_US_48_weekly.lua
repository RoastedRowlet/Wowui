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

local lookup = {'Unknown-Unknown','Mage-Arcane','Priest-Discipline','Paladin-Retribution','Warrior-Arms','Hunter-BeastMastery','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Priest-Holy','Warrior-Protection','Rogue-Assassination','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','Druid-Feral','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','Warlock-Affliction','Rogue-Subtlety',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abbyss:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Abirnar:BAAANQAECgYIEAAAAA==.Abramelinn:BAAANQAECgYIEwAAAA==.Abygayle:BAAANQAECgQICQAAAA==.',
Ac='Acca:BAAANQAECgQIBwAAAA==.',
Ad='Adget:BAABNQAECoEaAAICAAcKFRHywACzAQACAAcKFRHywACzAQAAAA==.Adicas:BAAANQABCgIJAgAAAA==.Adorion:BAAANQAECgQIBAAAAA==.',
Ae='Aerali:BAABNQAECoEjAAIDAAkK4hyGAgDAAgADAAkK4hyGAgDAAgAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgYJDQAAAA==.Agôny:BAAANQAECgQICAABNQAECgcIEAABAAAAAA==.',
Ah='Ahsõka:BAAANQADCgYIFgAAAA==.',
Ai='Aidzboy:BAAANQAECgcICQAAAA==.',
Al='Aldin:BAAANQAECgEIAQAAAA==.Alexandrõs:BAAANQAECgcIDwAAAA==.Alfah:BAAANQADCggIJAAAAA==.Aliatris:BAAANQAECgQICAAAAA==.Alicia:BAAANQADCgUIBQAAAA==.Alkamay:BAAANQAECgQICgAAAA==.Allor:BAAANQAECgEIAgAAAA==.Allorpally:BAABNQAECoEWAAIEAAgK5xxwRgB1AgAEAAgK5xxwRgB1AgAAAA==.Altofmyalt:BAAANQADCgIJAgAAAA==.Aluii:BAABNQAECoEmAAIFAAkKMiB+JAAAAwAFAAkKMiB+JAAAAwAAAA==.Alyssana:BAAANQAECgQICgAAAA==.Alyssius:BAAANQAECgcIDAAAAA==.Alyxdt:BAAANQAECgYIBgAAAA==.Alyxpally:BAAANQAECgIIAgAAAA==.Alyxpants:BAAANQAECgYJDAAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaranta:BAAANQADCgcIDgAAAA==.Amaria:BAAANQAECgYIEQAAAA==.Ambah:BAAANQADCggICAAAAA==.Ambulance:BAAANQAECgcIDAAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQAECgUIBwAAAA==.Angelsfly:BAAANQAECgUIBwAAAA==.Angæl:BAAANQAECgUICgAAAA==.Annallyne:BAAANQADCgUIBQABNQAECggIIQAGAH0aAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQAECgIIAwAAAA==.Anultrun:BAAANQAECgQICAAAAA==.',
Ar='Arabellaa:BAAANQAECgQIBAAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQAECgEIAQAAAA==.Archavrice:BAAANQAECgEIAQAAAA==.Arcyandor:BAAANQADCgcIEAAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgYJEwAAAA==.Arndul:BAAANQAECgUIBQABNQAFFAIIAgABAAAAAA==.',
As='Asapxmello:BAAANQADCgMIAwAAAA==.Ashammylady:BAAANQADCgYIBgAAAA==.Ashmear:BAAANQAECgIIAgAAAA==.Ashê:BAAANQAECgQIBgABNQAECgcICAABAAAAAA==.Astalon:BAAANQABCgYIEQAAAA==.Astrîl:BAAANQADCggICAAAAA==.',
At='Athreos:BAAANQAECgUIBwAAAA==.Atticuss:BAAANQADCgUIBQAAAA==.Atüned:BAABNQAECoEgAAMHAAgKhyL5EQAZAwAHAAgKhyL5EQAZAwAEAAIK2Q6CIwFnAAAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAABNQAECoE5AAMIAAgKBBB6UADmAQAIAAgKBBB6UADmAQAJAAMKCQUyygB+AAAAAA==.Aurelía:BAAANQAECgIIAgAAAA==.Autumni:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.',
Av='Avelane:BAABNQAECoEaAAMEAAcK6hCzjQCgAQAEAAcK6hCzjQCgAQAHAAYKXxU4aACPAQAAAA==.Averia:BAAANQABCgIIAgAAAA==.Avrare:BAAANQADCgYIBgAAAA==.',
Az='Azrukia:BAAANQADCgcIBwAAAA==.Azubasaurus:BAABNQAECoEkAAMKAAkKIiSAAQCqAwAKAAkKIiSAAQCqAwALAAIKCBvnKACZAAAAAA==.',
Ba='Baeladar:BAAANQADCgcIBwAAAA==.Baelor:BAAANQAECgUIBwAAAA==.Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgcIEAAAAA==.Balerion:BAAANQAECgQICAAAAA==.Barback:BAAANQABCgcIEwAAAA==.Barkstard:BAABNQAECoEkAAMMAAkKiBioIwB5AgAMAAgKFxuoIwB5AgANAAMKvxKwPADTAAAAAA==.Barleyalive:BAAANQADCgIIAgAAAA==.Battleaxe:BAAANQAECgQICQAAAA==.',
Be='Belarii:BAAANQAECgYICgAAAA==.Bellonae:BAAANQAECgQICQABNQAECgYICgABAAAAAA==.Belmenth:BAAANQADCgMIBAAAAA==.Bendecida:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Benington:BAAANQAECgYJCwAAAA==.Benn:BAACNQAFFIEWAAMOAAUKCxWcBABdAQAOAAQKqxecBABdAQAPAAEKigq5KQAmAAA1AAQKgTgAAw4ACQp+JQQEAIgDAA4ACQp+JQQEAIgDABAAAgpKH4iRAHcAAAAA.',
Bh='Bhyta:BAAANQAECgcIDAAAAA==.',
Bi='Bishopbob:BAAANQADCgcIBwAAAA==.Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAABNQAECoEjAAIRAAgKpAbYZgCDAQARAAgKpAbYZgCDAQAAAA==.Bitrusty:BAAANQADCggIDQABNQAECgYIDwABAAAAAA==.',
Bj='Bjartastrasz:BAAANQAECgYIDAAAAA==.Bjorc:BAAANQADCggIDAAAAA==.Bjoriannm:BAAANQAECggIBAAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAABNQAECoEjAAIGAAkKESaGAQDjAwAGAAkKESaGAQDjAwAAAA==.Blaumeux:BAAANQAECgQIBAAAAA==.Blazine:BAAANQABCggIDAAAAA==.Bliksem:BAAANQADCggICAAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggIDQABNQAECggIHwAEAHgeAA==.Bluesham:BAAANQAECgUICgAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAABNQAECoErAAIMAAgKHxnUJgBhAgAMAAgKHxnUJgBhAgAAAA==.Boostmartyr:BAAANQADCgcIBwAAAA==.Bowsbfrhoez:BAABNQAECoE7AAIGAAgKLBqoOAB8AgAGAAgKLBqoOAB8AgAAAA==.Boyaka:BAAANQAECgMIAwABNQAECgUICwABAAAAAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brisingar:BAAANQAECgUIBQAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQAECgIIBAABNQAECgQICQABAAAAAA==.',
Bu='Bubblëøseven:BAAANQAECgYICQABNQAECggIBAABAAAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQADCgYICwABNQAECgcIEwABAAAAAA==.Burds:BAAANQAECgYIBgABNQAECgcIEwABAAAAAA==.',
['Bë']='Bëllädonna:BAAANQADCggJKwAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoE7AAICAAkKdR58TgC+AgACAAkKdR58TgC+AgAAAA==.Cardoney:BAABNQAECoEgAAIEAAYKNgcozAAPAQAEAAYKNgcozAAPAQAAAA==.Cariah:BAABNQAECoEdAAIEAAgK9x5ENgCxAgAEAAgK9x5ENgCxAgAAAA==.Catashax:BAAANQADCgcJGAAAAA==.',
Cd='Cdkit:BAABNQAECoE7AAISAAgKQxlQCgBLAgASAAgKQxlQCgBLAgAAAA==.',
Ce='Celestè:BAAANQADCggIFgAAAA==.',
Ch='Chasstise:BAAANQAECgUICgAAAA==.Chazze:BAAANQAECgEIAQAAAA==.Cheazdruid:BAAANQADCgQJBAAAAA==.Cheazy:BAAANQADCgUIBQAAAA==.Cheggery:BAAANQAECgIIAwAAAA==.Chikubiz:BAAANQAECggICAAAAA==.Chillet:BAAANQADCggJDgAAAA==.Chirp:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Chirpe:BAAANQAECgQJBAABNQAECgUICQABAAAAAA==.Chokehan:BAAANQABCgEIAQAAAA==.Chubbypope:BAAANQAECgIIAgABNQAECgkJIQATAB0lAA==.Chuxer:BAAANQADCgQIBAAAAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgMIAwABAAAAAA==.Cindrick:BAACNQAFFIESAAIKAAQK5gp9CgAeAQAKAAQK5gp9CgAeAQA1AAQKgT0AAwoACQo7I3cBAKwDAAoACQo7I3cBAKwDAAsAAgoiC/wrAHEAAAAA.',
Cl='Clessta:BAAANQAECgUICQAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAABNQAECoEZAAIUAAkKPhjVEACbAgAUAAkKPhjVEACbAgAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgQIBQABAAAAAA==.Clynefate:BAAANQADCgIIAgAAAA==.',
Co='Coffêê:BAABNQAECoEkAAIJAAkK/CCxEQAPAwAJAAkK/CCxEQAPAwAAAA==.Coggers:BAAANQAECgQIBgAAAA==.Coldbringer:BAAANQAECgcIEwAAAA==.Coldpalmer:BAAANQAECgQICAABNQAECggIHwAFADEZAA==.Coleostrasz:BAAANQADCgQJBAAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Conzriest:BAAANQAECgEIAQAAAA==.Corastrasza:BAAANQAECgUICAAAAA==.Courtan:BAAANQADCgYJBgAAAA==.',
Cr='Cresentmoon:BAAANQAECgEIAQAAAA==.Crimsonmage:BAAANQAECgUICgAAAA==.Crowchild:BAAANQADCgQIBAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCgYIEAAAAA==.',
Cu='Cursedlight:BAABNQAECoEZAAMVAAgK/B9iGwAjAgAVAAYKax9iGwAjAgARAAMKmxtNigADAQAAAA==.',
Cy='Cynnal:BAAANQAECgcIDgAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgUICQAAAA==.Dahj:BAAANQAECgUICgAAAA==.Dalanar:BAAANQAECgQICQAAAA==.Danathjo:BAAANQAECgQIBwAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Davoth:BAAANQADCgUIBQAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAAANQAECgYIEgAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAABNQAECoEaAAMQAAgKuwgkWABKAQAQAAcK7wgkWABKAQAPAAIKhQSHuAAkAAAAAA==.Debris:BAAANQAECgcIDgAAAA==.Dedmongrel:BAAANQAECgYIDQAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgYICwAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAYIEwAWADQhAA==.Dengar:BAAANQAECgYICgAAAA==.Desyphium:BAACNQAFFIEKAAIEAAUKChHKBgCJAQAEAAUKChHKBgCJAQA1AAQKgSQAAwQACQrSIo4XAEEDAAQACQrSIo4XAEEDABcAAQpKIClNAFQAAAAA.Deviltrigger:BAAANQADCgUJCAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQAECgEIAQAAAA==.Deweysan:BAAANQAECgIIAwAAAA==.Dex:BAACNQAFFIERAAIJAAUKiRQsBwCaAQAJAAUKiRQsBwCaAQA1AAQKgTkAAgkACQryIdERAA4DAAkACQryIdERAA4DAAAA.',
Di='Direforge:BAAANQAECgUIDgAAAA==.Diriisharks:BAAANQAECgYIBwABNQAECgkJJgAIAN8jAA==.Disreputable:BAAANQADCgUIBAAAAA==.',
Dk='Dkaillou:BAAANQADCgMJAwAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgYICQAAAA==.Dracothyr:BAAANQAECgQICAAAAA==.Draemon:BAABNQAECoFOAAIYAAkK4iKgAACnAwAYAAkK4iKgAACnAwAAAA==.Draenei:BAAANQAECgEIAQABNQAECggIHwAFADEZAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFIEWAAIZAAcKwySNAADVAgAZAAcKwySNAADVAgA1AAQKgSIAAxkACQqvJagDAKgDABkACQqvJagDAKgDABoABgpoIE0pALoBAAAA.Dragonscar:BAAANQAECgUICQAAAA==.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQAECgQIBAABNQAECggIHwAFADEZAA==.Drastiricka:BAAANQADCgcJEgAAAA==.Dreadlocksta:BAAANQADCgMJAwAAAA==.Dreamer:BAAANQADCggJEgAAAA==.Drinkwater:BAAANQAECgMJDAABNQAECgQIBQABAAAAAA==.Drizztdemon:BAAANQAECgIIAgABNQAFFAYIEwAbAM8eAA==.Drucaila:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECgkJJAAcAMsjAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIEgAAAA==.Durkadurka:BAAANQABCgEIAQABNQAECgIIAgABAAAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgUICwAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAABNQAECoEsAAICAAkKlyAEKQAnAwACAAkKlyAEKQAnAwAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eastlord:BAAANQABCgYIBgAAAA==.Eatduhpupu:BAAANQAECgUIEAABNQAECgcICQABAAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECggIGQAPANEgAA==.Elfhelm:BAAANQAECgUICgAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellisinor:BAAANQAECgEIAQAAAA==.Eluneschosen:BAAANQAECgUJAgAAAA==.Elured:BAABNQAECoEbAAIRAAgKCAjnaQB3AQARAAgKCAjnaQB3AQAAAA==.Elysean:BAAANQAECgQIBAAAAA==.',
Em='Embermist:BAAANQAECgUICgAAAA==.Emliy:BAABNQAECoEbAAMKAAkKJRayDgCRAgAKAAkKJRayDgCRAgALAAMKXwyKJwCsAAAAAA==.Emogirl:BAAANQAECgEIAQABNQAECgkJJAAGABcmAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAABNQAECoEaAAMdAAgKJh6RDQBnAgAdAAcKHB+RDQBnAgAUAAgK4REMHwDfAQAAAA==.',
Ep='Ephesian:BAAANQAECgYIDgAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECggIHwAFAKEeAA==.Erobas:BAABNQAECoEvAAIFAAgKdBUkYgAfAgAFAAgKdBUkYgAfAgAAAA==.Erodan:BAABNQAECoEfAAIFAAgKoR4zNAC9AgAFAAgKoR4zNAC9AgAAAA==.',
Es='Esserian:BAAANQAECgMJBwAAAA==.Estarae:BAABNQAECoEtAAQVAAgKYBStLQBmAQAVAAYKyQ+tLQBmAQARAAMKSQaNqwCaAAADAAEKggEfKQAQAAAAAA==.Esthane:BAABNQAECoEVAAISAAgKHQdgGQA/AQASAAgKHQdgGQA/AQAAAA==.',
Et='Eternaldawn:BAAANQADCgYIDAAAAA==.Ethereall:BAAANQAECgMIBAAAAA==.',
Eu='Euphuzadan:BAABNQAECoEkAAIcAAkKyyOXDQA8AwAcAAkKyyOXDQA8AwAAAA==.',
Ev='Eveliala:BAAANQABCgMIAwAAAA==.Everhealer:BAABNQAECoE+AAIDAAgKARuGAwCEAgADAAgKARuGAwCEAgAAAA==.Evienarian:BAAANQABCgUICwAAAA==.Evillumber:BAAANQAECgMJBAAAAA==.',
Ex='Exiledemon:BAAANQAECgYICgAAAA==.Exterminatus:BAAANQAECgYIBgABNQAECgcIDwABAAAAAA==.',
Ey='Eyéspy:BAAANQAECgYIBgAAAA==.',
Ez='Ezza:BAAANQAECgcIAQAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Fatonement:BAAANQAECgYICwABNQAECgcICQABAAAAAA==.Fauvm:BAABNQAECoEkAAICAAcKehgplgAQAgACAAcKehgplgAQAgAAAA==.',
Fe='Feanassa:BAAANQAECgUIDgAAAA==.Fearwood:BAAANQAECgQIBAAAAA==.Felfeet:BAAANQAECgQJBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQAECgQIBAAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.Feyfoxe:BAAANQADCgIIAgAAAA==.',
Fi='Fishing:BAABNQAECoEmAAIIAAkK3yPaBgChAwAIAAkK3yPaBgChAwAAAA==.',
Fl='Flaviousqt:BAAANQAECgUICAAAAA==.Flavorofkrel:BAAANQADCggICAABNQAECgkJJAACAAcgAA==.Flekzakzak:BAABNQAECoEcAAIeAAgKaBxRCABqAgAeAAgKaBxRCABqAgAAAA==.Flekzugzug:BAAANQAECgUICAABNQAECggIHAAQAE8jAA==.Flezappezix:BAACNQAFFIEMAAIIAAUKwB1eCACFAQAIAAUKwB1eCACFAQA1AAQKgRcAAggACQrnIFcVACQDAAgACQrnIFcVACQDAAAA.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAABNQAECoEjAAMRAAkK4RfmKwB6AgARAAkK4RfmKwB6AgADAAcKLgm+CwBOAQAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAYIEgAKABYXAA==.Forald:BAAANQAECgQJBAAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAACNQAFFIEQAAMOAAYKDB/GAgCmAQAOAAQKpiTGAgCmAQAQAAQKdRbbBgA7AQA1AAQKgR0AAxAACQpxJk4SAPMCABAACAopJU4SAPMCAA4ABwoBJpUSALoCAAAA.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAACNQAFFIEIAAINAAMKuQqFCADaAAANAAMKuQqFCADaAAA1AAQKgVwAAg0ACQoPFEAVAFQCAA0ACQoPFEAVAFQCAAAA.Frostienips:BAAANQAECgMIAwAAAA==.Frostiness:BAAANQADCgYICwAAAA==.Frostmagee:BAAANQADCggIIAAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAABNQAECoEbAAISAAcKgAsWGQBCAQASAAcKgAsWGQBCAQAAAA==.Fupanchoo:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Galell:BAAANQADCgEIAQAAAA==.Garthurn:BAAANQADCgYJDAAAAA==.Gaskull:BAAANQAECgQICAAAAA==.Gaybacon:BAAANQADCgIIAgABNQAECgUIDgABAAAAAA==.',
Ge='Gemli:BAAANQABCgQJBAAAAA==.Geno:BAAANQAECgIIAgABNQAECgkJLgAFAFYlAA==.',
Gh='Ghostie:BAAANQADCgUIBQAAAA==.Ghostsaber:BAAANQAECgUICwAAAA==.',
Gi='Giddykitty:BAAANQADCggIHgAAAA==.Gimballock:BAAANQAECgQICAAAAA==.Gisakagda:BAAANQAECgQIBAAAAA==.Gital:BAAANQAECgEJAQAAAA==.',
Gl='Glennthehen:BAAANQAECgEIAQAAAA==.',
Go='Goatvier:BAACNQAFFIEKAAIfAAUKTyYuAAA/AgAfAAUKTyYuAAA/AgA1AAQKgSMAAh8ACQoyJkAAAOoDAB8ACQoyJkAAAOoDAAAA.Goblinator:BAAANQAECgYICgAAAA==.Golojo:BAAANQADCgQICAAAAA==.Goodenia:BAAANQADCgYICwAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goosef:BAAANQAECgQIBQAAAA==.Gopro:BAAANQADCgYIDwAAAA==.Gorbag:BAAANQADCgYJBwAAAA==.Gorhowl:BAABNQAECoEfAAIFAAgKERzXRQB8AgAFAAgKERzXRQB8AgAAAA==.Gorli:BAAANQADCggIHgAAAA==.Gottoloveit:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Gottolurveit:BAAANQAECgUICAAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAABNQAECoEgAAMEAAkK8yLTDQB7AwAEAAkK8yLTDQB7AwAHAAMKjg6erwDOAAAAAA==.Gravadin:BAAANQAECgYICQAAAA==.Great:BAAANQAECgMIAwABNQAECgkJJgAXANgkAA==.Grennu:BAAANQADCggICAAAAA==.Gretchin:BAAANQAECgIIBAAAAA==.Groshlow:BAAANQAECgIIAwAAAA==.',
Gu='Guinness:BAAANQADCgIJAgAAAA==.Gulios:BAAANQAECgMIBQAAAA==.Gunji:BAAANQAECgUIDQAAAA==.Guud:BAAANQAECgcIDQAAAA==.',
Gy='Gyukatsu:BAAANQADCgUJBQAAAA==.',
['Gä']='Gändalf:BAAANQAECgQIBgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesarrow:BAAANQAECgMIBgABNQAFFAYIEQAPAI8YAA==.Hadesblood:BAACNQAFFIERAAIPAAYKjximBADoAQAPAAYKjximBADoAQA1AAQKgScAAg8ACQoHH2USAPACAA8ACQoHH2USAPACAAAA.Hakzert:BAACNQAFFIERAAIdAAYKQROMAQDwAQAdAAYKQROMAQDwAQA1AAQKgSUAAx0ACQqAHbcGAP8CAB0ACQqAHbcGAP8CABQACArsCVwsAE0BAAAA.Happyfeett:BAAANQADCgQIBAAAAA==.Happyÿeet:BAAANQAECgQIBAAAAA==.Harex:BAABNQAECoEbAAMVAAgKqg/NIADkAQAVAAgKqg/NIADkAQARAAUKcRJKegA7AQAAAA==.Harlon:BAAANQADCgcICwAAAA==.Hartcake:BAAANQADCggIDAAAAA==.Haylø:BAAANQADCggICwAAAA==.Hazkalzzak:BAAANQADCgcIDgAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Hektîc:BAAANQAECgcIDgAAAA==.Hellsgate:BAAANQAECgIIAgAAAA==.Hellshunter:BAABNQAECoEaAAIGAAcK0x8hMgCUAgAGAAcK0x8hMgCUAgAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQADCgYIBwAAAA==.Hexalock:BAABNQAECoEbAAIcAAgKZRbDRgA8AgAcAAgKZRbDRgA8AgAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgYICwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexentjie:BAAANQADCggIJQAAAA==.Hexiemattel:BAAANQAECgYICwAAAA==.Hexington:BAAANQABCgMIAwAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hextralarge:BAAANQAECgcICQAAAA==.Hezaq:BAAANQAECgUICgAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollofeather:BAAANQAECgMIAwAAAA==.Hollowvoice:BAABNQAECoEbAAIPAAgKDBw9IQB1AgAPAAgKDBw9IQB1AgAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAAANQAECgcIEwAAAA==.Horacio:BAAANQAECgIIAgAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgYJBgAAAA==.Hunturd:BAAANQAECgMIBgAAAA==.Huntymcshoot:BAAANQAECgEIAgABNQAECggIBAABAAAAAA==.Huntér:BAAANQAECgcICQAAAA==.',
['Hù']='Hùntrèss:BAAANQAECgQIBwAAAA==.',
['Hû']='Hûntress:BAAANQADCgYIBgAAAA==.',
Ic='Icdedpple:BAAANQAECgYIDgAAAA==.Icymama:BAAANQADCggIHwAAAA==.',
Id='Idevouryou:BAAANQADCgYIEQAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Il='Illicet:BAAANQADCgcIEAAAAA==.',
Im='Imchirp:BAAANQAECgQICAABNQAECgUICQABAAAAAA==.Imicedup:BAAANQAECgQICQAAAA==.Impblaster:BAAANQAECgEJAQABNQAECgUICQABAAAAAA==.',
In='Inarius:BAAANQAECgYIEgAAAA==.Incompetent:BAAANQADCgcIFgAAAA==.Indriná:BAAANQAECgYJEQAAAA==.Inflictor:BAABNQAECoEbAAIJAAgKphcgOQAzAgAJAAgKphcgOQAzAgAAAA==.Insanenachos:BAAANQAECgUIDgAAAA==.Inumbra:BAAANQAECgQJBgAAAA==.',
Ir='Ironknee:BAABNQAECoEgAAIDAAgKvx/+AQDqAgADAAgKvx/+AQDqAgAAAA==.',
Is='Isterra:BAAANQADCgUJBQAAAA==.',
It='Ithareos:BAAANQAECgQICQAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQAECgQIBgAAAA==.',
Iz='Izate:BAAANQAECgQIBwAAAA==.Izulia:BAABNQAECoEZAAIPAAgK0SCoEQD4AgAPAAgK0SCoEQD4AgAAAA==.Izulid:BAAANQADCgYICAABNQADCggIFQABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQABNQAECgUIBQABAAAAAA==.Jabiraka:BAAANQADCggJEAAAAA==.Jackiexx:BAAANQAECgIIBAAAAA==.Jackiie:BAAANQADCggIEAABNQAECgIIBAABAAAAAA==.Jaedrae:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Jahwe:BAAANQABCgMJBAAAAA==.Jakestanater:BAAANQAECgUIBQAAAA==.Jassel:BAAANQAECgYIDQAAAA==.Jazmeine:BAAANQAECgEIAQAAAA==.',
Jd='Jdubbs:BAAANQADCgcICQAAAA==.',
Je='Jestër:BAAANQAECgEJAQABNQAECgYICgABAAAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAABNQAECoErAAMIAAgK2Q9DVgDRAQAIAAgKcA5DVgDRAQAgAAcKdwxiFQC4AQAAAA==.',
Jj='Jjester:BAAANQAECgYICgAAAA==.',
Jl='Jlabinos:BAAANQAECgcICwABNQAECggIGQAMAMAfAA==.Jlaby:BAABNQAECoEZAAIMAAgKwB8hFwDkAgAMAAgKwB8hFwDkAgAAAA==.',
Jp='Jpxhunter:BAAANQAECggICgAAAA==.',
Ju='Juicei:BAABNQAECoEcAAIVAAgK2xQ2IADqAQAVAAgK2xQ2IADqAQAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
Jw='Jw:BAAANQAECggIAwAAAA==.',
['Jë']='Jëster:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.',
Ka='Kaehn:BAAANQAECgUIBQAAAA==.Kaesoron:BAABNQAECoEhAAIcAAgKNhmiRABDAgAcAAgKNhmiRABDAgAAAA==.Kagéslammer:BAAANQADCggIGgAAAA==.Kairpally:BAAANQAECgIIAgAAAA==.Kaiser:BAAANQAECgcIEgAAAA==.Kanundrum:BAAANQAECgQICwABNQAECgUICQABAAAAAA==.Karaxynn:BAABNQAECoEmAAIaAAkKch2KCgAXAwAaAAkKch2KCgAXAwAAAA==.Karmasnightt:BAAANQADCgYIEAAAAA==.Katratralle:BAAANQADCggICAAAAA==.Kaulder:BAAANQAECgQIBQAAAA==.',
Ke='Kebabyy:BAABNQAECoEoAAMIAAcKMhsyPgAzAgAIAAcKMhsyPgAzAgAJAAUKhRojcABkAQAAAA==.Keeze:BAAANQADCgMJBAABNQAECggIHAAVAKILAA==.Keheia:BAAANQADCgYICQAAAA==.Keilna:BAAANQAECgIIAgAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAAANQAECgUICgAAAA==.Khodii:BAAANQAECgYIEAAAAA==.Khoho:BAAANQAECgQICQAAAA==.Khrøne:BAABNQAECoEXAAIQAAgKkgtNSQCLAQAQAAgKkgtNSQCLAQAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQAECgEIAgAAAA==.',
Ki='Kieranharrop:BAAANQAECgMIAwAAAA==.Killsaw:BAAANQABCgIIAgAAAA==.Kiltsusa:BAAANQAECggIAwAAAA==.Kity:BAAANQAECgMIBgAAAA==.',
Kn='Knail:BAAANQAECgQIBwAAAA==.Knickyou:BAAANQADCgYJCAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQAECgMIBAAAAA==.Konokö:BAAANQADCgUJBQABNQAECgMIBAABAAAAAA==.',
Kr='Kraii:BAAANQADCgIIAgAAAA==.Kreuzschlitz:BAAANQAECgEIAQAAAA==.Kreztek:BAAANQADCgQIBAAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQAECgUICgAAAA==.Krippg:BAAANQADCgIIAgABNQAECggIGgAFAI0ZAA==.Kripwar:BAABNQAECoEaAAIFAAgKjRkdVgBFAgAFAAgKjRkdVgBFAgAAAA==.Krizkin:BAAANQAECgUICQAAAA==.Krugg:BAAANQAECgEJAQAAAA==.',
Ku='Kungpao:BAAANQAECgUJBQAAAA==.Kurono:BAAANQADCgUJBQAAAA==.',
Ky='Kynhark:BAAANQADCgQJDwAAAA==.Kyoudo:BAABNQAECoErAAMhAAgKdxsgCQD7AQAFAAgKXxlfYQAhAgAhAAcKYBcgCQD7AQAAAA==.',
La='Laelha:BAAANQADCgUIBQAAAA==.Lasalia:BAAANQADCgUJBQAAAA==.Latricia:BAAANQADCggJEAAAAA==.Laurél:BAABNQAECoEYAAIOAAcK8Aw/PABoAQAOAAcK8Aw/PABoAQAAAA==.Layonpaws:BAABNQAECoE9AAQXAAgK0SQgCQDSAgAXAAcKfSQgCQDSAgAEAAcK+RrGbQD5AQAHAAEK+ArL8gAuAAAAAA==.',
Le='Lecked:BAAANQAECgMJBQAAAA==.Leggodex:BAAANQAECgQICQAAAA==.Leighandra:BAAANQAECgEIAQAAAA==.Lemures:BAAANQAECgcIEgAAAA==.Leonà:BAAANQAECgcICwAAAA==.',
Li='Lidera:BAAANQADCggIDQAAAA==.Liebspawn:BAAANQAECgIIAwAAAA==.Lightdefence:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.Lightrasta:BAAANQADCgQIBAAAAA==.Lightreign:BAAANQAECgQIBgAAAA==.Linarisa:BAABNQAECoEXAAIiAAUKrhs1MQBnAQAiAAUKrhs1MQBnAQAAAA==.Liquidate:BAAANQAECgUJDQAAAA==.Litori:BAAANQAECgUIEQAAAA==.Littlepaly:BAAANQABCgQIBAAAAA==.',
Ll='Llux:BAAANQADCggIDAAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAABNQAECoEkAAIEAAkKYRAJagAEAgAEAAkKYRAJagAEAgAAAA==.Looksmaxxor:BAABNQAECoEVAAIEAAgKEiDIKgDhAgAEAAgKEiDIKgDhAgAAAA==.Loryn:BAABNQAECoEbAAIGAAgK8SEtHADzAgAGAAgK8SEtHADzAgAAAA==.',
Lu='Lucarro:BAAANQAFFAEIAQABNQAFFAQIEgAKAOYKAA==.Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQAECgQIDgAAAA==.Lunavale:BAAANQAECgcICwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECgcIGgAEAOoQAA==.Lytemup:BAAANQAECgQIBgAAAA==.',
['Lä']='Läkan:BAAANQAECgEIAQAAAA==.',
['Lù']='Lùcifer:BAAANQAECgUIBgABNQAECggIMAAPADodAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECggIIQAGAH0aAA==.Maenir:BAAANQADCggIDwAAAA==.Magnytize:BAAANQAECgUICAAAAA==.Magoose:BAAANQAFFAIIAgAAAA==.Mags:BAABNQAECoEhAAIMAAgKjxm0KABSAgAMAAgKjxm0KABSAgAAAA==.Majinboom:BAAANQAECgcICwAAAA==.Maldred:BAAANQADCggIFAABNQAECgcIGgAHANAcAA==.Maldreds:BAABNQAECoEaAAIHAAcK0BzTMwBaAgAHAAcK0BzTMwBaAgAAAA==.Manicmonday:BAAANQADCggIHQAAAA==.Marsie:BAAANQAECgYIEgAAAA==.Mashex:BAAANQAECgQJCgAAAA==.',
Me='Medieval:BAABNQAECoEYAAIOAAcK1B6QHABaAgAOAAcK1B6QHABaAgAAAA==.Mediyah:BAAANQADCgYIEwAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQAECgEJAQABNQAECgQIBwABAAAAAA==.Meljira:BAAANQAECgQIBwAAAA==.Melonyummy:BAACNQAFFIEQAAIZAAYKEibwAACbAgAZAAYKEibwAACbAgA1AAQKgSQAAhkACQq/Jq4BANYDABkACQq/Jq4BANYDAAAA.Menzel:BAAANQADCgcIEgABNQAECgUICgABAAAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQAECgUICgAAAA==.Mesohorni:BAAANQAECgUJAgAAAA==.Messerian:BAAANQADCgMIAwABNQAECgMJBwABAAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milky:BAAANQAECgEJAQABNQAECgcJFwAHAEcZAA==.Milzey:BAABNQAECoEbAAIjAAgKHiK3AQAgAwAjAAgKHiK3AQAgAwAAAA==.Mindweaver:BAAANQAECgYIEAAAAA==.Miniscule:BAAANQAECgYIBgAAAA==.Minizap:BAAANQAECgEIAQAAAA==.Miradin:BAAANQAECgIJAwAAAA==.Mirv:BAACNQAFFIEDAAIkAAIK8x3sAQC/AAAkAAIK8x3sAQC/AAA1AAQKgSMAAiQACQpgHygBAC0DACQACQpgHygBAC0DAAAA.Misshapp:BAAANQADCgIIAgAAAA==.Misspickles:BAABNQAECoEfAAIIAAgKWB6rJAC6AgAIAAgKWB6rJAC6AgAAAA==.Mistakoji:BAAANQAECgUICAAAAA==.',
Mo='Mogwii:BAAANQAECggJAgAAAA==.Moit:BAAANQADCgYIBwAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQAECgQIDAAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monoblood:BAAANQAECggJAgAAAA==.Monononoke:BAAANQADCgYIDQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Moosocalypse:BAAANQADCgUIBQAAAA==.Morella:BAAANQAECgEIAQAAAA==.Morgai:BAAANQADCgcIBwAAAA==.',
Mu='Munta:BAAANQADCgYIFAAAAA==.Munter:BAABNQAECoEXAAIHAAcKRxnyQwAUAgAHAAcKRxnyQwAUAgAAAA==.Mursha:BAAANQAECgQICQAAAA==.Muted:BAAANQAECggIDgAAAA==.Muzblue:BAACNQAFFIEKAAIIAAUKIRzUBADfAQAIAAUKIRzUBADfAQA1AAQKgRcAAggABwodJbIcAO4CAAgABwodJbIcAO4CAAAA.Muzw:BAAANQAECgYIEAAAAA==.',
My='Mythreem:BAAANQAECgMJAwAAAA==.',
['Mä']='Mädness:BAAANQAECgIIAgABNQAFFAYIEAAZABImAA==.',
['Mï']='Mïkarika:BAAANQAECgYIDgAAAA==.',
Na='Naalaxii:BAABNQAECoEhAAIGAAgKfRpFQABiAgAGAAgKfRpFQABiAgAAAA==.Naero:BAAANQAECgQICAAAAA==.Naerond:BAAANQAECgEIAQAAAA==.Nalfeiin:BAABNQAECoEaAAIQAAYKWBAjVwBOAQAQAAYKWBAjVwBOAQAAAA==.Narnardk:BAABNQAECoEbAAIOAAkKvB7zDgDiAgAOAAkKvB7zDgDiAgAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrstorm:BAABNQAECoErAAISAAgK0SP1AwATAwASAAgK0SP1AwATAwAAAA==.Naturised:BAAANQAECgUICgAAAA==.Naursalla:BAAANQADCggIEgAAAA==.Nawe:BAAANQAECgcJDAAAAA==.',
Ne='Necratia:BAAANQAECgQIBAAAAA==.Neflyn:BAAANQADCggIHwAAAA==.Nemmystrata:BAAANQAECgUICwAAAA==.Nessaandra:BAABNQAECoEaAAIcAAcKdAYXlQBNAQAcAAcKdAYXlQBNAQAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDgAAAA==.',
Ni='Niftage:BAAANQADCgYIFQABNQAECgUICgABAAAAAA==.Niftana:BAAANQAECgUICgAAAA==.Nimirie:BAAANQAECgUICAAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQIBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Nokshaman:BAAANQAECgYIEwAAAA==.Noxtard:BAAANQADCggJEAAAAA==.',
Ny='Nyghtware:BAAANQAECgUICgAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQAECgUIDQAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCggIGwABNQAECgcIAQABAAAAAA==.',
Ok='Okazi:BAAANQAECgYIEgABNQAECggIGwAVAKoPAA==.',
Ol='Olafuga:BAABNQAECoErAAINAAgKAxw5EQCLAgANAAgKAxw5EQCLAgAAAA==.Oldblood:BAAANQABCgIJAgABNQADCgUIBQABAAAAAA==.',
Oo='Ookolok:BAAANQADCggIDQAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Op='Oppressor:BAAANQADCgcJDQAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCggIFAAAAA==.Ormal:BAAANQADCggJGgAAAA==.',
Os='Osma:BAAANQAECgUIBwABNQAFFAYIEwAbAM8eAA==.Osmess:BAAANQAECgYIEwABNQAFFAYIEwAbAM8eAA==.Osmology:BAACNQAFFIETAAQbAAYKzx4yAwDWAAAcAAQKNByCCAB/AQAbAAIKBSQyAwDWAAAkAAEKPx1+BgBVAAA1AAQKgSUABBwACQr+JSYfANUCABwABwrtJSYfANUCABsABgrDGBQVALkBACQAAQrnFkoiAEMAAAAA.',
Ov='Overwhelmed:BAAANQAECgQIBQAAAA==.',
Oz='Ozzietree:BAABNQAECoEjAAIMAAkKqh8wGADaAgAMAAkKqh8wGADaAgAAAA==.',
Pa='Paddingtonn:BAAANQADCgcJHAAAAA==.Pandachì:BAAANQAECgcIEgAAAA==.Pandamick:BAAANQADCggICgAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggJCAABNQAECgkJHwAcAAchAA==.Parallaxia:BAABNQAECoEfAAMcAAkKByGISAA2AgAcAAcK6B+ISAA2AgAbAAIK9CRePgC0AAAAAA==.Paulmedic:BAABNQAECoEgAAMdAAkKByT7AAC7AwAdAAkKByT7AAC7AwAUAAYKURaQJQCUAQAAAA==.',
Pb='Pbjellytime:BAAANQAECgUIDQAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECggIIwARAKQGAA==.Pegasuz:BAAANQAECggIBwAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQADCggIGAAAAA==.',
Ph='Phallics:BAAANQAECgcIEgABNQAFFAYIEwAXAMYdAA==.Phoènix:BAAANQAECgUIEAAAAA==.',
Pi='Pikyx:BAAANQAECgUIDQAAAA==.Pinkrock:BAABNQAECoEfAAIEAAgKeB5ONwCtAgAEAAgKeB5ONwCtAgAAAA==.',
Pl='Playboicarti:BAAANQAECggIEAAAAA==.Plopperoo:BAABNQAECoEYAAIMAAcKUhkhLwAhAgAMAAcKUhkhLwAhAgAAAA==.',
Po='Pocaface:BAAANQAECgYIBwAAAA==.Pogmourne:BAACNQAFFIEIAAIPAAMK0xxyDgAFAQAPAAMK0xxyDgAFAQA1AAQKgVwAAg8ACQqQHzMNACUDAA8ACQqQHzMNACUDAAAA.Polyform:BAABNQAECoEcAAMWAAgKESOMBAAOAwAWAAgKESOMBAAOAwAeAAEK8xT0KgA9AAAAAA==.',
Pr='Preserved:BAAANQAECgYIDQAAAA==.Priestsen:BAAANQADCggIGwAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Puru:BAAANQAECgUICwAAAA==.',
Py='Pyrhus:BAABNQAECoEaAAIYAAcKNRPwCgDDAQAYAAcKNRPwCgDDAQAAAA==.',
['Pâ']='Pâkerious:BAAANQAECgUIBgAAAA==.',
['Pæ']='Pælstrå:BAAANQAECgcIDAAAAA==.',
['Pè']='Pèppermint:BAAANQAECgYJEAABNQAECgcIEAABAAAAAA==.',
Qi='Qicacid:BAABNQAECoEmAAMhAAkK6yIGAwDwAgAhAAgKYSEGAwDwAgAFAAcKeCFARQB+AgABNQAFFAQIEgAKAOYKAA==.',
Ra='Racoondog:BAAANQAECgQIBAABNQAECggIGgAFAI0ZAA==.Raehalian:BAAANQADCgcICQAAAA==.Rafedrood:BAAANQAECgUIDgAAAA==.Rafemonk:BAAANQAECgYIDgABNQAECggIHwAEAH4PAA==.Rafepally:BAABNQAECoEfAAIEAAgKfg/8dwDcAQAEAAgKfg/8dwDcAQAAAA==.Raharn:BAAANQADCgYIBgAAAA==.Raiigun:BAAANQAECgcIEwAAAA==.Rakutina:BAAANQADCgUIDwAAAA==.Ramann:BAAANQAECgYIEgABNQAECggIGwASAGsfAA==.Rampart:BAAANQADCgcIBwAAAA==.Raspberry:BAAANQADCgQIBAAAAA==.Rastianklin:BAAANQAECgEIAQAAAA==.Ratbro:BAAANQAECgUIDwAAAA==.Rawrbewb:BAAANQAECgEIAQABNQAECgkJJgACAPMjAA==.Rawrbewbz:BAABNQAECoEmAAICAAkK8yPEDACXAwACAAkK8yPEDACXAwAAAA==.Rawrbutt:BAAANQAECgEIAQABNQAECgkJJgACAPMjAA==.Rayburd:BAAANQAECgcIEwAAAA==.Raypejeet:BAABNQAECoEXAAIQAAkKnyIcEwDsAgAQAAkKnyIcEwDsAgAAAA==.Raziiel:BAAANQAECgYIEAAAAA==.',
Rb='Rbed:BAAANQAECgYJDwAAAA==.',
Re='Realhuman:BAABNQAECoEfAAIFAAgKMRkTUwBPAgAFAAgKMRkTUwBPAgAAAA==.Recharge:BAABNQAECoEaAAIRAAgKIBf9MQBdAgARAAgKIBf9MQBdAgAAAA==.Redhoaxx:BAAANQAECgUIBQAAAA==.Redpally:BAAANQAECgMIBAAAAA==.Redrock:BAAANQADCgYIBwABNQAECggIHwAEAHgeAA==.Relinna:BAAANQAFFAEIAQAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAECggIIQAMAI8ZAA==.Rend:BAAANQADCgMIAwAAAA==.Renegade:BAAANQAECggIAQAAAA==.Resly:BAABNQAECoEnAAIUAAkKvR8bCwD2AgAUAAkKvR8bCwD2AgAAAA==.Reulna:BAAANQADCgIIAgAAAA==.Revolutionix:BAAANQAECgQICAAAAA==.',
Rh='Rhodie:BAAANQAECgYICwAAAA==.',
Ri='Ricuid:BAAANQAECgUICgAAAA==.Ridemption:BAAANQAECgYICgAAAA==.Rifkin:BAAANQAECgEIAQAAAA==.Rigamautist:BAAANQAECgUIEAAAAA==.Rightguy:BAAANQADCgYIBgAAAA==.',
Ro='Roadkill:BAAANQADCgYICwAAAA==.Roots:BAAANQAECgUICgAAAA==.Rotelle:BAAANQADCgMJBQAAAA==.Rottenalbo:BAAANQAECgQJDAABNQAECgUICQABAAAAAA==.',
Ru='Rustyaslock:BAABNQAECoErAAMcAAgKvA2GbgC7AQAcAAgKvA2GbgC7AQAbAAEK9wMIcwAuAAAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECgYICwAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Saladin:BAAANQAECgQIDAAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQAECgEJAQAAAA==.Samoid:BAAANQADCgcIDQABNQAFFAUIDQAdAC0bAA==.Sanguiniüs:BAAANQAECgQICwAAAA==.Santhea:BAAANQAECgUICAAAAA==.Sarash:BAAANQADCggICAABNQADCgYICwABAAAAAA==.Sarixz:BAABNQAECoEeAAIIAAgKBhVSPwAtAgAIAAgKBhVSPwAtAgAAAA==.Sarzyb:BAABNQAECoEfAAIIAAgKRw/OUwDaAQAIAAgKRw/OUwDaAQAAAA==.Sashka:BAAANQAECggIEQAAAA==.Satsuy:BAAANQAECggIBAAAAA==.Savaric:BAAANQADCggIDgAAAA==.',
Sc='Scott:BAABNQAECoExAAIFAAgK8BuUQwCEAgAFAAgK8BuUQwCEAgAAAA==.Scrubturkey:BAAANQAECgQICQAAAA==.Scuntpetz:BAAANQADCggIDQAAAA==.',
Se='Seamonology:BAABNQAECoEVAAIcAAgKvhiSTAAoAgAcAAgKvhiSTAAoAgAAAA==.Seether:BAAANQAECgMIBQABNQAFFAUIDAATAMwTAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seraithe:BAAANQABCgIJBAAAAA==.Seravael:BAAANQAECgUIDQAAAA==.Sethbash:BAAANQADCggIDwAAAA==.',
Sh='Shadowvoice:BAAANQAECgcIDwAAAA==.Shallan:BAABNQAECoEiAAMCAAgK/hwzhAA6AgACAAcK8RozhAA6AgAYAAIKGx8aHwC0AAAAAA==.Shamann:BAAANQADCgYIBgABNQAECgcICQABAAAAAA==.Shapymcshift:BAAANQAECgEIAQABNQAECggIBAABAAAAAA==.Shard:BAAANQADCggJEgAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECggIIwARAKQGAA==.Shieldzu:BAAANQADCggIFQAAAA==.Shlappy:BAACNQAFFIERAAIPAAUKTBo3CACHAQAPAAUKTBo3CACHAQA1AAQKgU8AAg8ACQo/IQoKAEkDAA8ACQo/IQoKAEkDAAAA.',
Si='Silversham:BAABNQAECoEZAAIJAAgKIx3EKQB+AgAJAAgKIx3EKQB+AgAAAA==.Silversnow:BAAANQADCggJFAAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAABNQAECoEaAAISAAcKDBiHDgDqAQASAAcKDBiHDgDqAQAAAA==.Skiddy:BAACNQAFFIESAAIKAAYKFhfJAwAHAgAKAAYKFhfJAwAHAgA1AAQKgSQAAgoACQrMIS0GACwDAAoACQrMIS0GACwDAAAA.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skrug:BAAANQAECgUIBwAAAA==.',
Sl='Slowdeath:BAAANQAECgcIDgAAAA==.Slysham:BAAANQAECgcIEQAAAA==.',
Sm='Smeevil:BAABNQAECoEbAAMIAAgKiBg+UQDjAQAIAAYKVhs+UQDjAQAJAAYKlBCwfwA2AQAAAA==.Smellyfridge:BAAANQADCgQICAABNQAECgIIAwABAAAAAA==.',
Sn='Sneeds:BAACNQAFFIEgAAIPAAYKFh05AwAZAgAPAAYKFh05AwAZAgA1AAQKgU4AAg8ACQqJJFQEAJoDAA8ACQqJJFQEAJoDAAAA.Snowdrifter:BAAANQADCgEIAQAAAA==.Snowflicker:BAAANQAECgIIAgAAAA==.Snowhail:BAAANQAECgYIEwAAAA==.',
So='Soal:BAAANQAECgQIBgAAAA==.Soaringsky:BAACNQAFFIEGAAICAAMKCgiuJQDnAAACAAMKCgiuJQDnAAA1AAQKgSEAAgIACQqoG1xNAMECAAIACQqoG1xNAMECAAAA.Solarflares:BAABNQAECoEbAAIMAAgKpwlCRACQAQAMAAgKpwlCRACQAQAAAA==.Sopheeaa:BAAANQAECgYIDwAAAA==.Soria:BAAANQAECgYIDQAAAA==.Soulblessed:BAABNQAECoEhAAMHAAkKCxwIHwDFAgAHAAgK2BwIHwDFAgAEAAYKkA3gtABBAQAAAA==.Soursop:BAAANQADCgUJCAAAAA==.',
Sp='Sparkychops:BAAANQAECgUIBwAAAA==.Spaztik:BAAANQAECggICwAAAA==.Spectrefive:BAAANQADCgcICAAAAA==.Spectretwo:BAAANQAECgQICAAAAA==.Spelcastro:BAAANQAECgYIDAAAAA==.Spherical:BAAANQAECgEIAQABNQAECgkJHgALALseAA==.Spknox:BAAANQADCggIIAABNQAECggIDwABAAAAAA==.Spooklet:BAAANQAECgEIAQAAAA==.Spoonboy:BAABNQAECoEdAAIQAAkKnSCyCQBNAwAQAAkKnSCyCQBNAwAAAA==.',
Sq='Squirtmore:BAAANQAECgcIEAAAAA==.Squirtsalot:BAAANQAECgcIEQAAAA==.',
St='Starielle:BAAANQAECgQICQAAAA==.Stark:BAAANQAECgUIEQAAAA==.Steinman:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.Stemple:BAAANQAECgUIDwAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAAANQAECgUIDQAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQADCggJGgAAAA==.Stubsy:BAAANQADCgQJBAAAAA==.',
Su='Sublet:BAAANQAECgUICgAAAA==.Subwayy:BAAANQAECgYIEgAAAA==.Sunshÿne:BAAANQAECgEIAQAAAA==.Suunshine:BAABNQAECoEwAAIPAAgKOh05HgCKAgAPAAgKOh05HgCKAgAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAABNQAECoEcAAINAAgK8g2QKAB0AQANAAgK8g2QKAB0AQAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Synfal:BAAANQAECgYIEgAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAAANQAECgYIEgAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAAANQAECgYIDwAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgcIDQABNQAECgUIDgABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICwAAAA==.',
['Sý']='Sýrézz:BAAANQADCggICAAAAA==.',
Ta='Taemire:BAAANQAECgMIAwABNQAECggILQAVAGAUAA==.Taezi:BAAANQADCgUIBQAAAA==.Tahlia:BAABNQAECoEbAAIJAAgKphLEUQDNAQAJAAgKphLEUQDNAQAAAA==.Takaiya:BAAANQAECgYIDgAAAA==.Tanglethorn:BAAANQADCgQIBAAAAA==.Tauna:BAAANQADCgQIBAAAAA==.Taur:BAAANQAFFAEIAQAAAA==.',
Te='Technosis:BAAANQADCggIGAAAAA==.Techuu:BAACNQAFFIERAAMFAAYKKRbnBQAIAgAFAAYKKRbnBQAIAgAhAAEKYQXxAwBKAAA1AAQKgSUAAgUACQqBI8YOAHIDAAUACQqBI8YOAHIDAAAA.',
Th='Thade:BAAANQADCgMIAwABNQAECgUIDgABAAAAAA==.Thatdamdruid:BAAANQAECgYIDQAAAA==.Thekhole:BAAANQAECggIDAAAAA==.Thekrelltoss:BAABNQAECoEkAAICAAkKByAeQADkAgACAAkKByAeQADkAgAAAA==.Thoriandis:BAAANQAECgQICAAAAA==.',
Ti='Tinderella:BAAANQADCgIJAgAAAA==.Tinjam:BAAANQADCgYJBgAAAA==.Tintarella:BAAANQADCgQJBAAAAA==.Titaniumman:BAAANQADCgYIBwAAAA==.',
Tj='Tjirp:BAAANQAECgUICQAAAA==.',
To='Tohka:BAAANQAECgMIAQABNQAECgkJJwAdAHUlAA==.Tohkna:BAAANQAECgIIAgABNQAECgkJJwAdAHUlAA==.Torale:BAAANQAECgIIAgAAAA==.Tormentar:BAAANQADCgMIAwAAAA==.Totemstout:BAAANQAECgQICAAAAA==.Toteshadow:BAAANQAECgIIAgABNQAECggIGwAMAPgZAA==.Tovuk:BAABNQAECoEZAAIfAAcKORpUCAAYAgAfAAcKORpUCAAYAgAAAA==.',
Tr='Tranquilitee:BAAANQAECgYIEgAAAA==.Traumateam:BAAANQADCgYJEAABNQAECgUICgABAAAAAA==.Trebdk:BAAANQAECgMIBAAAAA==.Trebpal:BAAANQAECgcIEwAAAA==.Treecoleos:BAAANQAECgcICgAAAA==.Treigha:BAAANQADCggIDwABNQAECggIKwAhAHcbAA==.Tripleseven:BAAANQADCgUIBQAAAA==.Triplesix:BAAANQAECgIIAgAAAA==.',
Tw='Tweetconic:BAAANQADCggIHgAAAA==.Tweetess:BAAANQADCgEJAQAAAA==.Twothreesix:BAAANQAECgEIAwAAAA==.Twîsted:BAAANQADCggIGAAAAA==.',
Ty='Tyborel:BAABNQAECoEfAAMGAAkKTSECHwDlAgAGAAgK9SICHwDlAgAjAAUK3hacBwCWAQAAAA==.Tydro:BAAANQAECgUICwAAAA==.Tyranoc:BAAANQAECgcIDAAAAA==.',
Ud='Udòngeìn:BAAANQADCgcIBwAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Us='Usedtobecool:BAAANQAECgYIBwAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQAECgQIBAAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAABNQAECoEaAAIJAAgKXQjQggAtAQAJAAgKXQjQggAtAQAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwAAAA==.Valthalus:BAAANQADCgYIDwAAAA==.Valvet:BAAANQAECgMIAwAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQADCggIDwAAAA==.Vellarya:BAAANQAECgUICgAAAA==.Velthrax:BAABNQAECoErAAIGAAgKyCU7CwBiAwAGAAgKyCU7CwBiAwAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velìn:BAAANQADCgYJDgAAAA==.Velín:BAABNQAECoElAAMFAAgK2x1cQQCMAgAFAAgK2x1cQQCMAgAhAAIKVAzBHwBoAAAAAA==.',
Vi='Vilaina:BAAANQADCgEJAQAAAA==.Villeneth:BAAANQADCggIDQAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAABNQAECoEdAAMFAAkKsg/xawABAgAFAAkKsg/xawABAgAhAAEKjQwvKAA0AAAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.Vizzo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Vo='Vocck:BAAANQAECgQIBAAAAA==.Vock:BAAANQABCgUIBQABNQAECggIIQACAJ8YAA==.Vokk:BAAANQADCgYIBgABNQAECggIIQACAJ8YAA==.Vozie:BAABNQAECoEhAAICAAgKnxgmewBPAgACAAgKnxgmewBPAgAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAABNQAECoEeAAICAAgKKRcTfQBLAgACAAgKKRcTfQBLAgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
['Vâ']='Vânâ:BAAANQADCgYIBgAAAA==.',
['Vó']='Vóltron:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.',
Wa='Wackman:BAABNQAECoEcAAIQAAgKTyNwDAAvAwAQAAgKTyNwDAAvAwAAAA==.Wargold:BAAANQADCggICAABNQAECggIGQAJACMdAA==.Warmfridge:BAAANQAECgIIAwAAAA==.Wartiant:BAABNQAECoEfAAIFAAcKPgkboABoAQAFAAcKPgkboABoAQAAAA==.',
Wh='Whiskytango:BAAANQADCgEIAQAAAA==.Whitehall:BAAANQAECgUICwAAAA==.Whocouldube:BAAANQADCgEJAQAAAA==.Wholegrain:BAAANQAECgcIEAAAAA==.',
Wi='Windhorn:BAAANQAECgUICgAAAA==.Windi:BAAANQADCgYIFgAAAA==.Wiro:BAAANQADCgUIBwAAAA==.Wirø:BAAANQADCgIIAwAAAA==.',
Wo='Wobbling:BAABNQAECoEYAAIFAAkKRhUnVgBFAgAFAAkKRhUnVgBFAgAAAA==.Wobblock:BAAANQAECgUICgAAAA==.Wombee:BAAANQADCggIGwAAAA==.Wonderia:BAABNQAECoEZAAIdAAgK9BVKEQAaAgAdAAgK9BVKEQAaAgAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
Wy='Wylia:BAAANQAECgcIEgAAAA==.',
['Wí']='Wíiman:BAAANQAECggIDwAAAA==.',
Xa='Xalath:BAAANQAECgQIBwAAAA==.',
Xe='Xeenah:BAABNQAECoE7AAMiAAgKxAcoMwBWAQAiAAcKVwcoMwBWAQAGAAIK1QjX9gCBAAAAAA==.',
Xi='Xiconz:BAAANQADCgUIBQAAAA==.Xilef:BAAANQAECgMJAwAAAA==.',
Xx='Xxjackie:BAAANQADCgcIDQABNQAECgIIBAABAAAAAA==.',
Xy='Xyz:BAACNQAFFIEMAAMTAAUKzBOEAwCgAQATAAUKzBOEAwCgAQAlAAEK9BZNDwBQAAA1AAQKgRsAAxMACQpxH6oPAMMCABMACQotH6oPAMMCACUABQpvFp0oAE4BAAAA.',
Ya='Yamaka:BAACNQAFFIERAAIWAAYK4CIpAABzAgAWAAYK4CIpAABzAgA1AAQKgSIAAhYACQqEJowAAOoDABYACQqEJowAAOoDAAAA.',
Ys='Yseult:BAAANQAECgQICQAAAA==.',
Za='Zaarocc:BAAANQAECgYIBgAAAA==.Zaarock:BAABNQAECoEoAAMQAAkKah/JEwDmAgAQAAkKah/JEwDmAgAPAAEKgROOqQA4AAAAAA==.Zaishadow:BAAANQAECgYIEwAAAA==.Zandro:BAAANQAECgQIBQAAAA==.Zandrocas:BAAANQADCgIIAgAAAA==.Zanduill:BAAANQADCggIIQAAAA==.Zanhighawen:BAAANQADCggIHgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQAECgcIDQAAAA==.Zayva:BAAANQAECgUICgAAAA==.',
Ze='Zealfu:BAAANQADCgIIAwABNQAECgUIDQABAAAAAA==.Zeali:BAAANQADCgEIAQABNQAECgUIDQABAAAAAA==.Zealthyr:BAAANQAECgUIDQAAAA==.Zeztuknar:BAAANQAECgQIBQAAAA==.',
Zi='Zincberg:BAAANQADCggJGgAAAA==.Ziyn:BAAANQAECgcIEwABNQAECgkJKQAGADYjAA==.',
Zo='Zorbax:BAAANQAECgQIBQAAAA==.',
Zy='Zykaei:BAABNQAECoEnAAIdAAkKdSXcAADDAwAdAAkKdSXcAADDAwAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAgABNQAECgcIDQABAAAAAA==.',
['Áy']='Áylamao:BAABNQAECoEfAAIZAAYKrQulQABJAQAZAAYKrQulQABJAQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggIPwAAAA==.',
['Éh']='Éh:BAABNQAECoEaAAIaAAgKexGdIAAMAgAaAAgKexGdIAAMAgAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECggIOgADANwZAA==.Ðisciple:BAABNQAECoE6AAMDAAgK3Bl7BgDrAQADAAYK0Rt7BgDrAQARAAcKFROnVQDGAQAAAA==.',
['Øb']='Øbiwan:BAAANQADCgYIFgAAAA==.',
['Øc']='Øctavia:BAAANQADCgQIBQAAAA==.',
['ßi']='ßinchicken:BAAANQAECgUIEQAAAA==.',
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
