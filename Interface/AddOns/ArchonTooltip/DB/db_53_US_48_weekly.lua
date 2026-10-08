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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Guardian','Mage-Arcane','Mage-Frost','Priest-Discipline','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Paladin-Holy','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','DeathKnight-Blood','Warlock-Affliction','Warrior-Protection','Rogue-Assassination','Monk-Windwalker','Priest-Shadow','Paladin-Protection','Monk-Brewmaster','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Monk-Mistweaver','Shaman-Enhancement','Druid-Feral','DemonHunter-Vengeance','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Rogue-Subtlety',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abbyss:BAAANQAECgQICAABNQAECgUIDAABAAAAAA==.Abirnar:BAABNQAECoEbAAMCAAcKbRsYPADpAQACAAcKyhYYPADpAQADAAMKyyAmKQAHAQAAAA==.Abramelinn:BAABNQAECoElAAMEAAcKVg3r3ACoAQAEAAcKCQ3r3ACoAQAFAAEKYxCYQQAyAAAAAA==.Abygayle:BAAANQAECgQICQAAAA==.',
Ac='Acca:BAAANQAECgUIDAAAAA==.',
Ad='Adget:BAABNQAECoEgAAIEAAgKNxE9uwDqAQAEAAgKNxE9uwDqAQAAAA==.Adicas:BAAANQABCgIJAgAAAA==.Adorion:BAAANQAECgQIBAAAAA==.Adriosis:BAAANQADCgMIAwAAAA==.',
Ae='Aerali:BAABNQAECoEjAAIGAAkK4hzzAQACAwAGAAkK4hzzAQACAwAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgYJDQABNQAECgcIBgABAAAAAA==.Agôny:BAAANQAECgQICAABNQAECggIJAAHALYaAA==.',
Ah='Ahsõka:BAAANQAECgQIBQAAAA==.',
Ai='Aidzboy:BAAANQAECgcIDQAAAA==.',
Al='Aldin:BAAANQAECgEIAQAAAA==.Alexandrõs:BAABNQAECoEXAAMIAAgK4CLBCwAjAwAIAAgK4CLBCwAjAwAJAAEKagI97QAQAAAAAA==.Alfah:BAAANQAECgQIBAAAAA==.Aliatris:BAAANQAECgUIDQAAAA==.Alicia:BAAANQAECgIIAgAAAA==.Alkamay:BAAANQAECgUIEAAAAA==.Allor:BAAANQAECgEIAwAAAA==.Allorpally:BAABNQAECoEbAAIKAAgKGh7aSACUAgAKAAgKGh7aSACUAgAAAA==.Altofmyalt:BAAANQADCgIJAgAAAA==.Alui:BAAANQAECgUIBQABNQAECgkJKAALAHsgAA==.Aluii:BAABNQAECoEoAAILAAkKeyAgLQD1AgALAAkKeyAgLQD1AgAAAA==.Alyn:BAAANQAECgEIAQAAAA==.Alyssana:BAAANQAECgQICgAAAA==.Alyssius:BAAANQAECgcIEwAAAA==.Alyxdt:BAAANQAECgYIBgAAAA==.Alyxpally:BAAANQAECgcICQAAAA==.Alyxpants:BAAANQAECgYIDAAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaranta:BAAANQADCgcIDgAAAA==.Amaria:BAAANQAECgcIEQAAAA==.Ambah:BAAANQADCggIEAAAAA==.Ambulance:BAABNQAECoEXAAIMAAgKzxjaQgA7AgAMAAgKzxjaQgA7AgAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQAECgUICAAAAA==.Angelsfly:BAAANQAECgUIDAAAAA==.Angæl:BAAANQAECgYIEAAAAA==.Annallyne:BAAANQADCgUIBQABNQAECggIIwANAOoaAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQAECgMIBQAAAA==.Anultrun:BAAANQAECgQICAAAAA==.',
Ar='Arabellaa:BAAANQAECgYICgAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQAECgIIAwAAAA==.Archavrice:BAAANQAECgEIAQAAAA==.Arcyandor:BAAANQADCgcIEAAAAA==.Aremixlady:BAAANQAECgEIAQAAAA==.Aristomenis:BAAANQAECgUIBQAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgYJEwAAAA==.Arndul:BAAANQAECgUICgABNQAFFAIIAgABAAAAAA==.',
As='Asapxmello:BAAANQADCgMIAwAAAA==.Ashammylady:BAAANQADCgYIBgAAAA==.Ashmear:BAAANQAECgIIAgAAAA==.Ashê:BAAANQAECgQIBwABNQAECgcICAABAAAAAA==.Astalon:BAAANQABCgYIEQAAAA==.Astrîl:BAAANQADCggICAAAAA==.',
At='Athreos:BAAANQAECgUIBwAAAA==.Atticuss:BAAANQADCgUIBQAAAA==.Atüned:BAABNQAECoEgAAMMAAgKhyKIFgARAwAMAAgKhyKIFgARAwAKAAIK2Q7eTAFiAAAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAABNQAECoFHAAMOAAgKxBLyTwALAgAOAAgKxBLyTwALAgAPAAMKCQVd4QB6AAAAAA==.Aurelía:BAAANQAECgMIBQAAAA==.Autumni:BAAANQADCgYICQABNQAECgUIBQABAAAAAA==.',
Av='Avelane:BAABNQAECoEiAAMKAAgKjRaObAAqAgAKAAgKjRaObAAqAgAMAAYKXxVveACHAQAAAA==.Averia:BAAANQABCgIIAgAAAA==.Avrare:BAAANQADCgYIBgAAAA==.',
Az='Azrukia:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Azubasaurus:BAABNQAECoEmAAMQAAkKIiT1AQChAwAQAAkKIiT1AQChAwARAAIKCBu+LACWAAAAAA==.',
Ba='Baeladar:BAAANQADCggICAAAAA==.Baelor:BAAANQAECgUIBwAAAA==.Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgcIEQAAAA==.Balerion:BAAANQAECgUIDQAAAA==.Barback:BAAANQABCgcIFQAAAA==.Barkstard:BAABNQAECoEnAAMCAAkK4hjFJwB0AgACAAgKbxvFJwB0AgASAAMK6hJ3RADUAAAAAA==.Barleyalive:BAAANQADCgQIBQABNQADCgEIAQABAAAAAA==.Barleybrew:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQAECgQICQAAAA==.',
Be='Belarii:BAAANQAECgYICgAAAA==.Bellonae:BAAANQAECgUIDgABNQAECgYICgABAAAAAA==.Belmenth:BAAANQADCgMIBAAAAA==.Bendecida:BAAANQAECgIIAgABNQAECgcIJQAEAFYNAA==.Benington:BAAANQAECgYJCwAAAA==.Benn:BAACNQAFFIEcAAQJAAYKwxnXBQCkAQAJAAUKrBjXBQCkAQAIAAQKqxd4BgBNAQATAAEKKROKKQA5AAA1AAQKgTsAAwgACQp+JZQFAHcDAAgACQp+JZQFAHcDAAkAAwoEHqqQAMEAAAAA.',
Bh='Bhyta:BAAANQAECgcIDAAAAA==.',
Bi='Bishopbob:BAAANQADCgcIBwAAAA==.Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAABNQAECoEoAAIHAAkKRwZnagCpAQAHAAkKRwZnagCpAQAAAA==.Bitrusty:BAAANQADCggIDQABNQAECgcIFgAMAPgZAA==.',
Bj='Bjartastrasz:BAAANQAECgYIEgAAAA==.Bjorc:BAAANQAECgYIBwAAAA==.Bjoriannm:BAAANQAECggIBgAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAABNQAECoEmAAINAAkKESZtAgDYAwANAAkKESZtAgDYAwAAAA==.Blaumeux:BAAANQAECgQIBAAAAA==.Blazine:BAAANQABCggIDAAAAA==.Bliksem:BAAANQADCggICAAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggIDQABNQAECggIJwAKAHgeAA==.Bluesham:BAAANQAECgYIEAAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAABNQAECoErAAICAAgKHxmWLQBMAgACAAgKHxmWLQBMAgAAAA==.Boostmartyr:BAAANQADCgcIBwAAAA==.Bowsbfrhoez:BAABNQAECoFJAAINAAgKUhqoRwBvAgANAAgKUhqoRwBvAgAAAA==.Boyaka:BAAANQAECgMIAwABNQAECgUIEAABAAAAAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brisingar:BAAANQAECgUIBQAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQAECgIIBAABNQAECgQICQABAAAAAA==.',
Bu='Bubblëøseven:BAAANQAECgYICgABNQAECggIBgABAAAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQAECgYIBgABNQAECggIFwAUAPMaAA==.Burds:BAAANQAECgYIBgABNQAECggIFwAUAPMaAA==.',
['Bë']='Bëllädonna:BAAANQAECgEIAQAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoE7AAIEAAkKdR6aYQCoAgAEAAkKdR6aYQCoAgAAAA==.Cardoney:BAABNQAECoEtAAIKAAcK0AeazABIAQAKAAcK0AeazABIAQAAAA==.Cariah:BAABNQAECoElAAIKAAgKvB/cPAC6AgAKAAgKvB/cPAC6AgAAAA==.Catashax:BAAANQADCgcJGAAAAA==.',
Cd='Cdkit:BAABNQAECoFHAAIVAAgKQxn/DAA4AgAVAAgKQxn/DAA4AgAAAA==.',
Ce='Celestè:BAAANQADCggIFgAAAA==.',
Ch='Chasstise:BAAANQAECgUIDwAAAA==.Chazze:BAAANQAECgEIAQAAAA==.Cheazdruid:BAAANQADCgQJBAAAAA==.Cheazy:BAAANQADCgUIBQAAAA==.Cheggery:BAAANQAECgMIBQAAAA==.Chikubiz:BAAANQAECggICAAAAA==.Chillet:BAAANQADCggJDgAAAA==.Chirp:BAAANQADCgIIAgABNQAECgUIEAABAAAAAA==.Chirpe:BAAANQAECgQJBAABNQAECgUIEAABAAAAAA==.Chokehan:BAAANQABCgEIAQAAAA==.Chubbypope:BAAANQAECgIIAgABNQAECgkJJAAWAB0lAA==.Chuxer:BAAANQADCgQIBAAAAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgMIAwABAAAAAA==.Cindrick:BAACNQAFFIEWAAIQAAQKQA+sCwAzAQAQAAQKQA+sCwAzAQA1AAQKgUsAAxAACQo7I+QBAKMDABAACQo7I+QBAKMDABEAAwplDwwqALYAAAAA.',
Cl='Clessta:BAAANQAECgUICQAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAABNQAECoEfAAIXAAkKvxgrFACSAgAXAAkKvxgrFACSAgAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgUIDwABAAAAAA==.Clynefate:BAAANQADCgIIAgAAAA==.',
Co='Coffêê:BAABNQAECoEqAAIPAAkKYCFjDQBBAwAPAAkKYCFjDQBBAwAAAA==.Coggers:BAAANQAECgQIBwAAAA==.Coldbringer:BAABNQAECoEdAAMTAAgKfhwDMwAjAgATAAcKnRwDMwAjAgAIAAYKOhZGPwCJAQAAAA==.Coldpalmer:BAAANQAECgUIDQABNQAECgkJKAALAI8ZAA==.Coleostrasz:BAAANQADCgQJBAAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Conzriest:BAAANQAECgEIAQABNQAECgQIDAABAAAAAA==.Corastrasza:BAAANQAECgUIDQAAAA==.Courtan:BAAANQADCggIEwAAAA==.',
Cr='Cresentmoon:BAAANQAECgIIAwAAAA==.Crimsonmage:BAAANQAECgUICgAAAA==.Crowchild:BAAANQADCgQIBAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggIEwAAAA==.',
Cu='Cursedlight:BAABNQAECoEhAAMHAAgK0x+mHADnAgAHAAgK0x+mHADnAgAYAAYKax8lIAASAgAAAA==.',
Cy='Cynnal:BAAANQAECgcIDwAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgUICQAAAA==.Dahj:BAAANQAECgYIEAAAAA==.Dalanar:BAAANQAECgQICQAAAA==.Danathjo:BAAANQAECgQIBwAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Davoth:BAAANQAECgQIBQAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAABNQAECoEcAAINAAcKxhtjYQApAgANAAcKxhtjYQApAgAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAABNQAECoEeAAMJAAgK9gi1aQBGAQAJAAcKMgm1aQBGAQATAAIKiATusABIAAAAAA==.Debris:BAAANQAECgcIDwAAAA==.Dedmongrel:BAAANQAECgYIEQAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgYIDAAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAYIEwADADQhAA==.Dengar:BAAANQAECgcIEAAAAA==.Desyphium:BAACNQAFFIEQAAIKAAUKIBNiCQCHAQAKAAUKIBNiCQCHAQA1AAQKgScAAwoACQrSIm8gACoDAAoACQrSIm8gACoDABkAAQpKIP1YAE4AAAAA.Deviltrigger:BAAANQADCgUJCAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQAECgIIAgAAAA==.Deweysan:BAAANQAECgIIAwAAAA==.Dex:BAACNQAFFIERAAIPAAUKiRTnCQCPAQAPAAUKiRTnCQCPAQA1AAQKgTwAAg8ACQryIa4XAPsCAA8ACQryIa4XAPsCAAAA.',
Di='Direforge:BAABNQAECoEZAAIaAAcK6x9qCACGAgAaAAcK6x9qCACGAgAAAA==.Diriisharks:BAAANQAFFAIIAgAAAA==.Disreputable:BAAANQADCgUIBAAAAA==.',
Dk='Dkaillou:BAAANQADCgMJAwAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgcIEAAAAA==.Dracothyr:BAAANQAECgQICAAAAA==.Draemon:BAABNQAECoFYAAIFAAkKEiYnAADoAwAFAAkKEiYnAADoAwAAAA==.Draenei:BAAANQAECgQIBQABNQAECgkJKAALAI8ZAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFIEXAAIbAAcKwyQDAQCzAgAbAAcKwyQDAQCzAgA1AAQKgSUAAxsACQqvJUgFAJQDABsACQqvJUgFAJQDABwABgpoICkuAK4BAAAA.Dragonscar:BAAANQAECgUICQABNQAECgYIDQABAAAAAA==.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQAECgUICAABNQAECgkJKAALAI8ZAA==.Drastiricka:BAAANQADCgcJEgAAAA==.Dreadlocksta:BAAANQADCgMJAwAAAA==.Dreamer:BAAANQADCggJEgAAAA==.Drfel:BAAANQAECgMIAwAAAA==.Drinkwater:BAAANQAECgMIDAABNQAECgUIDwABAAAAAA==.Drizztdemon:BAAANQAECgIIAgABNQAFFAcIGgAdACEgAA==.Drucaila:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECgkJKgAdAMsjAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIEgAAAA==.Durkadurka:BAAANQABCgEIAQABNQAECgIIAgABAAAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgUICwAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAABNQAECoE0AAIEAAkKjCF2HABcAwAEAAkKjCF2HABcAwAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eastlord:BAAANQABCgcICgAAAA==.Eatduhpupu:BAAANQAECgUIEgABNQAECgcIDQABAAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECggIIAATANEiAA==.Electricity:BAAANQADCgYIBgAAAA==.Elfhelm:BAAANQAECgYIEAAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellisinor:BAAANQAECgEIAQAAAA==.Eluneschosen:BAAANQAECgUJAgAAAA==.Elured:BAABNQAECoEjAAIHAAgKygiTdwB7AQAHAAgKygiTdwB7AQAAAA==.Elysalia:BAAANQAECgcIBwAAAA==.Elysean:BAAANQAECgQIBAAAAA==.',
Em='Embermist:BAAANQAECgYICwAAAA==.Emliy:BAABNQAECoEfAAMQAAkKJRbzEACGAgAQAAkKJRbzEACGAgARAAQKGQ/3JQDpAAAAAA==.Emogirl:BAAANQAECgEIAQABNQAECgkJJwANABcmAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAABNQAECoEiAAQeAAgKbhwJDQCQAgAeAAgKbhwJDQCQAgAXAAgKaRJEJADVAQAaAAEK9QOpMQAeAAAAAA==.',
Ep='Ephesian:BAABNQAECoEWAAMZAAcKrxkcHgDMAQAKAAcKQRcEiwDcAQAZAAYKOxocHgDMAQAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECggIJwALAIgfAA==.Erobas:BAABNQAECoE/AAILAAgK3BdTaAA3AgALAAgK3BdTaAA3AgAAAA==.Erodan:BAABNQAECoEnAAILAAgKiB/nNgDRAgALAAgKiB/nNgDRAgAAAA==.',
Es='Esserian:BAAANQAECgYIDAAAAA==.Estarae:BAABNQAECoEtAAQYAAgKYBRhNABZAQAYAAYKyQ9hNABZAQAHAAMKSQZxxACUAAAGAAEKggGILgAQAAAAAA==.Esthane:BAABNQAECoEVAAIVAAgKHQcGHgA5AQAVAAgKHQcGHgA5AQAAAA==.',
Et='Eternaldawn:BAAANQADCggIFAAAAA==.Ethereall:BAAANQAECgMIBAAAAA==.',
Eu='Euphuzadan:BAABNQAECoEqAAIdAAkKyyM4BgCPAwAdAAkKyyM4BgCPAwAAAA==.',
Ev='Eveliala:BAAANQABCgMIAwAAAA==.Everhealer:BAABNQAECoFMAAIGAAgKZByvAwCWAgAGAAgKZByvAwCWAgAAAA==.Evienarian:BAAANQABCgUICwAAAA==.Evillumber:BAAANQAECgUICQAAAA==.',
Ex='Exiledemon:BAAANQAECgYICgAAAA==.Exterminatus:BAAANQAECgYIBgABNQAECggIGAAfAA0fAA==.',
Ey='Eyéspy:BAAANQAECgYIBgAAAA==.',
Ez='Ezza:BAAANQAECgcIAwAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Faneragare:BAAANQAECgIIAgABNQAFFAYIEgAOAKMiAA==.Fatonement:BAAANQAECgYICwABNQAECgcICQABAAAAAA==.Fauvm:BAABNQAECoEqAAIEAAcKehiArgAEAgAEAAcKehiArgAEAgAAAA==.',
Fe='Feanassa:BAABNQAECoEXAAMbAAcKLwUFTgAqAQAbAAcKLwUFTgAqAQAcAAMKVAFbWABaAAAAAA==.Fearwood:BAAANQAECgQIBAAAAA==.Felfeet:BAAANQAECgQJBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQAECgQIBAAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.Feyfoxe:BAAANQADCgIIAgAAAA==.',
Fi='Fishing:BAABNQAECoEmAAIOAAkK3yO/CQCNAwAOAAkK3yO/CQCNAwABNQAFFAIIAgABAAAAAA==.',
Fl='Flaviousqt:BAAANQAECgYICgAAAA==.Flavorofkrel:BAAANQADCggICAABNQAECgkJKgAEAAcgAA==.Flekzakzak:BAABNQAECoEhAAIgAAgKax5mBgDeAgAgAAgKax5mBgDeAgAAAA==.Flekzugzug:BAAANQAECgcIEgABNQAECggIIwAJAKwkAA==.Flezappezix:BAACNQAFFIESAAIOAAYKoyIpBwDTAQAOAAYKoyIpBwDTAQA1AAQKgRgAAg4ACQrnIJUbAAwDAA4ACQrnIJUbAAwDAAAA.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAABNQAECoEmAAMHAAkKFhoOKQCnAgAHAAkKFhoOKQCnAgAGAAcKLgl2DQBGAQAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAcIGQAQAAAXAA==.Forald:BAAANQAECgQJBAAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAACNQAFFIEUAAMJAAYK2x+KAQAsAgAJAAYKFRyKAQAsAgAIAAQKpiQxBACVAQA1AAQKgR8AAwkACQqWJkkaANQCAAkACAoqJUkaANQCAAgABwovJvsWAK8CAAAA.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAACNQAFFIESAAISAAUKkgc1BwBbAQASAAUKkgc1BwBbAQA1AAQKgWIAAhIACQppFFcZAEkCABIACQppFFcZAEkCAAAA.Frostienips:BAAANQAECgMIAwAAAA==.Frostiness:BAAANQADCgcIEQAAAA==.Frostmagee:BAAANQAECgQIBAAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAABNQAECoEgAAIVAAcKnwx6HABKAQAVAAcKnwx6HABKAQAAAA==.Fupanchoo:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Garfeel:BAAANQAECgcIBgAAAA==.Garthurn:BAAANQADCgcIEwAAAA==.Gaskull:BAAANQAECgQICAAAAA==.Gaybacon:BAAANQADCgIIAgABNQAECgcIGQAaAOsfAA==.',
Ge='Gemli:BAAANQAECgQIBAAAAA==.Geno:BAAANQAECgUIDAABNQAECgkJOQALANUlAA==.',
Gh='Ghostie:BAAANQADCggIDQAAAA==.Ghostsaber:BAAANQAECgUIDQAAAA==.',
Gi='Giddykitty:BAAANQAECgQIBgAAAA==.Gimballock:BAAANQAECgUIDQAAAA==.Gisakagda:BAAANQAECgQIBAAAAA==.Gital:BAAANQAECgEJAQAAAA==.',
Gl='Glennthehen:BAAANQAECgEIAQAAAA==.',
Go='Goatvier:BAACNQAFFIEQAAIhAAUKTyZLAAA6AgAhAAUKTyZLAAA6AgA1AAQKgSYAAiEACQo6JmAAAN8DACEACQo6JmAAAN8DAAAA.Goblinator:BAAANQAECgYICgAAAA==.Golojo:BAAANQADCgQICAAAAA==.Goodenia:BAAANQAECgQIBAAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goomonic:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Goosef:BAAANQAECgcIDAAAAA==.Gopro:BAAANQADCgYIDwAAAA==.Gorbag:BAAANQADCgYJBwAAAA==.Gorhowl:BAABNQAECoEnAAILAAgKhRxmTACKAgALAAgKhRxmTACKAgAAAA==.Gorli:BAAANQADCggIHgAAAA==.Gottoloveit:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Gottolurveit:BAAANQAECgUICAAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAABNQAECoEpAAMKAAkKYSRpCQCnAwAKAAkKYSRpCQCnAwAMAAMKjg5lxADKAAAAAA==.Gravadin:BAAANQAECgYICQAAAA==.Great:BAAANQAECgcICQABNQAECgkJLQAZADQlAA==.Grennu:BAAANQADCggICAAAAA==.Gretchin:BAAANQAECgIIBAAAAA==.Groshlow:BAAANQAECgIIAwAAAA==.',
Gu='Guinness:BAAANQADCgIJAgAAAA==.Gulios:BAAANQAECgMIBQAAAA==.Gunji:BAAANQAECgUIDQAAAA==.Guud:BAABNQAECoEWAAIPAAkKnBRfOwBJAgAPAAkKnBRfOwBJAgAAAA==.',
Gy='Gyukatsu:BAAANQADCgUIBQAAAA==.',
['Gä']='Gändalf:BAAANQAECgQIBgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesarrow:BAAANQAECgMIBgABNQAFFAYIEgATAI8YAA==.Hadesblood:BAACNQAFFIESAAITAAYKjxi9BgDUAQATAAYKjxi9BgDUAQA1AAQKgSgAAhMACQpuHzwVAO0CABMACQpuHzwVAO0CAAAA.Hadeshammer:BAAANQAFFAEIAQABNQAFFAYIEgATAI8YAA==.Hakzert:BAACNQAFFIEVAAMeAAYKQRNlAgDpAQAeAAYKQRNlAgDpAQAXAAEKbQlGEgA/AAA1AAQKgScAAx4ACQqAHUgIAPACAB4ACQqAHUgIAPACABcACQqLCj8uAHIBAAAA.Happyfeett:BAAANQADCgQIBAAAAA==.Happyÿeet:BAAANQAECgQIBAAAAA==.Harex:BAABNQAECoEjAAQYAAgKqg8+JgDTAQAYAAgKqg8+JgDTAQAHAAcK+BQoYQDLAQAGAAEKvQf/JAA2AAAAAA==.Harlon:BAAANQADCgcICwAAAA==.Hartcake:BAAANQADCggIDAAAAA==.Haylø:BAAANQADCggICwAAAA==.Hazkalzzak:BAAANQADCggIEQAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Hektîc:BAAANQAECgcIDgAAAA==.Hellsgate:BAAANQAECgIIBAAAAA==.Hellshunter:BAABNQAECoEgAAINAAgK5R8oJgDgAgANAAgK5R8oJgDgAgAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQADCgYIBwAAAA==.Hexalock:BAABNQAECoEdAAIdAAgKpBYfVgAyAgAdAAgKpBYfVgAyAgAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgYICwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexentjie:BAAANQADCggILQAAAA==.Hexiemattel:BAAANQAECgYIEAAAAA==.Hexington:BAAANQABCgMIAwAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hextralarge:BAAANQAECgcICQAAAA==.Hezaq:BAAANQAECgYIEAAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollofeather:BAAANQAECgUICAAAAA==.Hollowvoice:BAABNQAECoEjAAITAAgKexzpIwB/AgATAAgKexzpIwB/AgAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAABNQAECoEYAAMHAAgKARztOABiAgAHAAgKARztOABiAgAYAAMKLwiBVACLAAAAAA==.Horacio:BAAANQAECgMIBQAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgYJBgAAAA==.Hunturd:BAAANQAECgMIBgAAAA==.Huntymcshoot:BAAANQAECgEIAwABNQAECggIBgABAAAAAA==.Huntér:BAAANQAECgcIDwAAAA==.',
['Hù']='Hùntrèss:BAAANQAECgUIDAAAAA==.',
['Hû']='Hûntress:BAAANQADCgYIBgAAAA==.',
Ic='Icdedpple:BAAANQAECgYIEwAAAA==.Icymama:BAAANQADCggIHwAAAA==.',
Id='Idevouryou:BAAANQADCgYIEQAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Il='Illicet:BAAANQADCgcIEAAAAA==.',
Im='Imchirp:BAAANQAECgQICAABNQAECgUIEAABAAAAAA==.Imicedup:BAAANQAECgQICQAAAA==.Impblaster:BAAANQAECgYIDQAAAA==.',
In='Inarius:BAABNQAECoEeAAIIAAcKdRG9PQCTAQAIAAcKdRG9PQCTAQAAAA==.Incompetent:BAAANQADCgcIFgAAAA==.Indriná:BAAANQAECgcIEgAAAA==.Inflictor:BAABNQAECoEjAAIPAAgKaxolNQBkAgAPAAgKaxolNQBkAgAAAA==.Insanenachos:BAAANQAECgUIEQAAAA==.Inumbra:BAAANQAECgQJBgAAAA==.',
Ir='Ironknee:BAABNQAECoEpAAIGAAkKLCG+AABtAwAGAAkKLCG+AABtAwAAAA==.',
Is='Isterra:BAAANQADCgUJBQAAAA==.',
It='Ithareos:BAAANQAECgQICgAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQAECgUICAAAAA==.',
Iz='Izate:BAAANQAECgQICAAAAA==.Izulia:BAABNQAECoEgAAITAAgK0SKRDgApAwATAAgK0SKRDgApAwAAAA==.Izulid:BAAANQADCgYICAABNQADCggIFQABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQABNQAECgUIBQABAAAAAA==.Jabiraka:BAAANQADCggJEAAAAA==.Jackiexx:BAAANQAECgIIBAABNQAECgcIDgABAAAAAA==.Jackiie:BAAANQADCggIEAABNQAECgcIDgABAAAAAA==.Jaedrae:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Jahwe:BAAANQABCgMJBAAAAA==.Jakestanater:BAAANQAECgcIDAAAAA==.Jassel:BAAANQAECgYIEwAAAA==.Jazmeine:BAAANQAECgcICAAAAA==.',
Jd='Jdubbs:BAAANQADCgcICQAAAA==.',
Je='Jestër:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAABNQAECoErAAMOAAgK2Q9hZADDAQAOAAgKcA5hZADDAQAfAAcKdwyqGACtAQAAAA==.',
Jj='Jjester:BAAANQAECgYIDwAAAA==.',
Jl='Jlabinos:BAAANQAECgcIDwABNQAECggIIQACALkgAA==.Jlaby:BAABNQAECoEhAAICAAgKuSDuFwDvAgACAAgKuSDuFwDvAgAAAA==.',
Jp='Jpxhunter:BAAANQAECggICwAAAA==.',
Ju='Juicei:BAABNQAECoEcAAIYAAgK2xRDHwAcAgAYAAgK2xRDHwAcAgAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
Jw='Jw:BAAANQAECggIAwAAAA==.',
['Jë']='Jëster:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.',
Ka='Kaehn:BAAANQAECgYICwAAAA==.Kaesoron:BAABNQAECoElAAIdAAgKARpLVgAyAgAdAAgKARpLVgAyAgAAAA==.Kagéslammer:BAAANQADCggIGgAAAA==.Kairpally:BAAANQAECgQIBgAAAA==.Kaiser:BAABNQAECoEbAAMiAAkKGyE7AwAIAwAiAAgKjSE7AwAIAwALAAcK2xkRagAzAgAAAA==.Kaldrek:BAAANQADCgcICAAAAA==.Kanundrum:BAAANQAECgUIEAAAAA==.Karaxynn:BAABNQAECoEpAAIcAAkKkB5jCwAaAwAcAAkKkB5jCwAaAwAAAA==.Karmasnightt:BAAANQADCgYIEAAAAA==.Katratralle:BAAANQADCggICQAAAA==.Kaulder:BAAANQAECgUICgAAAA==.',
Ke='Kebabyy:BAABNQAECoEvAAMOAAkKPxhjSQAkAgAOAAcKYxtjSQAkAgAPAAcKJBZ5bgCRAQAAAA==.Keeze:BAAANQADCgMJBAABNQAECggIHAAYAKILAA==.Keheia:BAAANQADCgYICQAAAA==.Keilna:BAAANQAECgQIBAAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAAANQAECgYIEAAAAA==.Khodii:BAAANQAECgYIEAAAAA==.Khoho:BAAANQAECgQICQAAAA==.Khrøne:BAABNQAECoEcAAIJAAgKBQx5WACHAQAJAAgKBQx5WACHAQAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQAECgEIAgAAAA==.',
Ki='Kieranharrop:BAAANQAECgMIAwAAAA==.Killsaw:BAAANQABCgIIAgAAAA==.Kiltsusa:BAAANQAECggIAwAAAA==.Kity:BAAANQAECgUIDAAAAA==.',
Kn='Knail:BAAANQAECgQICwAAAA==.Knickyou:BAAANQADCgYJCAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQAECgMIBAAAAA==.Konokö:BAAANQADCgUJBQABNQAECgMIBAABAAAAAA==.',
Kr='Kraii:BAAANQADCgIIAgAAAA==.Kreuzschlitz:BAAANQAECgEIAQAAAA==.Kreztek:BAAANQADCgQIBAAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQAECgUIDwAAAA==.Krippg:BAAANQADCgIIAgABNQAECggIHAALAI0ZAA==.Kripwar:BAABNQAECoEcAAILAAgKjRnRZwA5AgALAAgKjRnRZwA5AgAAAA==.Krizkin:BAAANQAECgUICQAAAA==.Krugg:BAAANQAECgEIAQAAAA==.Krystal:BAAANQAECgIIAgAAAA==.',
Ku='Kungpao:BAAANQAECgUIBgAAAA==.Kurono:BAAANQADCgUIBQAAAA==.',
Ky='Kynhark:BAAANQADCgQJDwAAAA==.Kyoudo:BAABNQAECoEvAAMiAAgKcxtJCwDrAQALAAgKnBm2WwBcAgAiAAcKYBdJCwDrAQAAAA==.',
La='Laelha:BAAANQADCgUIBQAAAA==.Lasalia:BAAANQADCggIDAAAAA==.Latricia:BAAANQADCggIEAAAAA==.Laurél:BAABNQAECoEfAAIIAAcKDw4IQgB4AQAIAAcKDw4IQgB4AQAAAA==.Layonpaws:BAABNQAECoFLAAQZAAgK0SRiCwDEAgAZAAcKfSRiCwDEAgAKAAcK+RqjhwDkAQAMAAEK+ArtCwEuAAAAAA==.',
Le='Lecked:BAAANQAECgQICQAAAA==.Leggodex:BAAANQAECgUIDwAAAA==.Leighandra:BAAANQAECgIIAwAAAA==.Lemures:BAABNQAECoEcAAIQAAgKjQ7kHgDEAQAQAAgKjQ7kHgDEAQAAAA==.Leonà:BAAANQAECgcIEAAAAA==.',
Li='Lidera:BAAANQADCggIDQAAAA==.Liebspawn:BAAANQAECgMIBQAAAA==.Lightdefence:BAAANQADCgMIAwABNQAECgUIDgABAAAAAA==.Lightrasta:BAAANQAECgIIAgAAAA==.Lightreign:BAAANQAECgUIBwAAAA==.Lilhands:BAAANQAECgUICgAAAA==.Linarisa:BAABNQAECoEjAAIjAAcKNiCQGQBxAgAjAAcKNiCQGQBxAgAAAA==.Liquidate:BAAANQAECgUJDQAAAA==.Litori:BAABNQAECoEdAAIJAAcKLxYsSQDLAQAJAAcKLxYsSQDLAQAAAA==.Littlepaly:BAAANQAECgEIAQAAAA==.Littleshammy:BAAANQAECgIIAwAAAA==.Livinlife:BAAANQADCgEIAQAAAA==.',
Ll='Llux:BAAANQADCggIDAAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAABNQAECoEnAAIKAAkKNREqfQD/AQAKAAkKNREqfQD/AQAAAA==.Looksmaxxor:BAABNQAECoEbAAIKAAgK2iAUMADqAgAKAAgK2iAUMADqAgAAAA==.Lorethemar:BAAANQADCgcICQAAAA==.Loryn:BAABNQAECoEjAAINAAgKpyNAGwASAwANAAgKpyNAGwASAwAAAA==.',
Lu='Lucarro:BAAANQAFFAEIAQABNQAFFAQIFgAQAEAPAA==.Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQAECgQIEQAAAA==.Lunavale:BAAANQAECgcICwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECggIIgAKAI0WAA==.Lytemup:BAAANQAECgQIBgAAAA==.',
['Lä']='Läkan:BAAANQAECgEIAQAAAA==.',
['Lù']='Lùcifer:BAAANQAECgcIEwABNQAECggIOQATAHweAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECggIIwANAOoaAA==.Maenir:BAAANQADCggIDwAAAA==.Magnytize:BAAANQAECgUIDAAAAA==.Magoose:BAAANQAFFAIIAgAAAA==.Mags:BAABNQAECoEoAAICAAkK6RcnJgCAAgACAAkK6RcnJgCAAgAAAA==.Majinboom:BAAANQAECggIDgAAAA==.Maldred:BAAANQAECgMIAwABNQAECgcIHAAMANAcAA==.Maldreds:BAABNQAECoEcAAIMAAcK0BwQPQBTAgAMAAcK0BwQPQBTAgAAAA==.Manicmonday:BAAANQAECgQIBQAAAA==.Marsie:BAABNQAECoEcAAIEAAgKDhQ0wADgAQAEAAgKDhQ0wADgAQAAAA==.Mashex:BAAANQAECgQJCgAAAA==.',
Me='Mealank:BAAANQAECggIAwABNQAECgkJKAAHAEcGAA==.Meatfridge:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Medieval:BAABNQAECoEfAAIIAAcKvyB5GQCZAgAIAAcKvyB5GQCZAgAAAA==.Mediyah:BAAANQADCgYIEwAAAA==.Medusacroft:BAAANQADCgUICAAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQAECgEJAQABNQAECgQIBwABAAAAAA==.Meljira:BAAANQAECgQIBwAAAA==.Melonyummy:BAACNQAFFIEUAAIbAAYKKCZ2AQCLAgAbAAYKKCZ2AQCLAgA1AAQKgScAAhsACQrFJtEBANUDABsACQrFJtEBANUDAAAA.Menzel:BAAANQADCggIHwABNQAECgUIDwABAAAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQAECgUICgAAAA==.Mesohorni:BAAANQAECgUJAgAAAA==.Messerian:BAAANQADCgMIAwABNQAECgYIDAABAAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milky:BAAANQAECgUIBgABNQAECggIGQAMAHEXAA==.Milzey:BAABNQAECoEjAAIkAAgKPSO5AQA7AwAkAAgKPSO5AQA7AwAAAA==.Mindweaver:BAABNQAECoEXAAIeAAcKfB+WDgBzAgAeAAcKfB+WDgBzAgAAAA==.Miniscule:BAAANQAECgYIBgAAAA==.Minizap:BAAANQAECgYICAAAAA==.Miradin:BAAANQAECgQIBwAAAA==.Mirv:BAACNQAFFIEFAAIUAAIKkiIeAgDTAAAUAAIKkiIeAgDTAAA1AAQKgSYAAhQACQrDIFYBADUDABQACQrDIFYBADUDAAAA.Misshapp:BAAANQADCgIIAgAAAA==.Misspickles:BAABNQAECoEnAAIOAAgKqB+UIgDfAgAOAAgKqB+UIgDfAgAAAA==.Mistakoji:BAAANQAECgUICAAAAA==.',
Mo='Mogwii:BAAANQAECggJAgAAAA==.Moit:BAAANQADCgYICwAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQAECgQIDAAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monoblood:BAAANQAECggIAgAAAA==.Monononoke:BAAANQADCgYIDQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Moosocalypse:BAAANQADCgUIBQAAAA==.Morella:BAAANQAECgEIAQAAAA==.Morgai:BAAANQADCgcIBwAAAA==.',
Mu='Munta:BAAANQADCgYIFAAAAA==.Munter:BAABNQAECoEZAAIMAAgKcRc7PwBKAgAMAAgKcRc7PwBKAgAAAA==.Mursha:BAAANQAECgUIDgAAAA==.Muted:BAABNQAECoEYAAIfAAkKbg9+EABFAgAfAAkKbg9+EABFAgAAAA==.Muzblue:BAACNQAFFIEMAAIOAAUKIRwGBwDYAQAOAAUKIRwGBwDYAQA1AAQKgRsAAg4ABwphJWkgAO0CAA4ABwphJWkgAO0CAAAA.Muzw:BAAANQAECgYIEAABNQAFFAcIBAABAAAAAA==.',
My='Mythreem:BAAANQAECgMJAwAAAA==.',
['Mä']='Mädness:BAAANQAECgIIAwABNQAFFAYIFAAbACgmAA==.',
['Mï']='Mïkarika:BAABNQAECoEYAAINAAcKiRDMfwDeAQANAAcKiRDMfwDeAQAAAA==.',
Na='Naalaxii:BAABNQAECoEjAAINAAgK6hqwTABhAgANAAgK6hqwTABhAgAAAA==.Naero:BAAANQAECgQICgAAAA==.Naerond:BAAANQAECgEIAQAAAA==.Nalfeiin:BAABNQAECoEbAAIJAAcKEBA3WwB8AQAJAAcKEBA3WwB8AQAAAA==.Narnardk:BAABNQAECoEbAAIIAAkKvB41FADKAgAIAAkKvB41FADKAgAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrex:BAAANQABCgUIBAAAAA==.Natrstorm:BAABNQAECoEvAAIVAAgKFiSPBAAeAwAVAAgKFiSPBAAeAwAAAA==.Naturised:BAAANQAECgYIEAAAAA==.Naursalla:BAAANQADCggIEgAAAA==.Nawe:BAAANQAECgcIDQAAAA==.Naxaris:BAAANQADCgMIAwAAAA==.',
Ne='Necratia:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Neflyn:BAAANQAECgQIBAAAAA==.Nemmystrata:BAAANQAECgUIDwAAAA==.Nessaandra:BAABNQAECoEiAAIdAAgK5AdViwCbAQAdAAgK5AdViwCbAQAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDgAAAA==.',
Ni='Niftage:BAAANQADCgYIGwABNQAECgYIEAABAAAAAA==.Niftana:BAAANQAECgYIEAAAAA==.Nimirie:BAAANQAECgUICAAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQIBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Nokshaman:BAAANQAECgYIEwAAAA==.Noxtard:BAAANQADCggJEAAAAA==.',
Ny='Nyghtware:BAAANQAECgUIDgAAAA==.',
['Nì']='Nìx:BAAANQAECgUIBgAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQAECgUIDQAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCggIGwABNQAECgcIAwABAAAAAA==.',
Ok='Okazi:BAABNQAECoEeAAIeAAgKqBnKDwBbAgAeAAgKqBnKDwBbAgABNQAECggIIwAYAKoPAA==.',
Ol='Olafuga:BAABNQAECoEvAAISAAgKAxxZFACEAgASAAgKAxxZFACEAgAAAA==.Oldblood:BAAANQABCgIJAgABNQADCgUIBQABAAAAAA==.',
Oo='Ookolok:BAAANQADCggIDQAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Op='Oppressor:BAAANQADCgcJDQAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCggIFAAAAA==.Ormal:BAAANQADCggIIQAAAA==.',
Os='Osma:BAAANQAECgUIBwABNQAFFAcIGgAdACEgAA==.Osmess:BAAANQAECgYIEwABNQAFFAcIGgAdACEgAA==.Osmology:BAACNQAFFIEaAAQdAAcKISDNAQBfAgAdAAYKJB/NAQBfAgAlAAIKBSQbBADPAAAUAAEKPx2pCABSAAA1AAQKgScABB0ACQo7JkwmANMCAB0ABwo7JkwmANMCACUABgrDGLEWAK8BABQAAQrnFicoAD4AAAAA.',
Ov='Overwhelmed:BAAANQAECgUIDwAAAA==.',
Oz='Ozzietree:BAABNQAECoEjAAICAAkKqh8qHQDFAgACAAkKqh8qHQDFAgAAAA==.',
Pa='Paddingtonn:BAAANQAECgEIAQAAAA==.Pandachì:BAABNQAECoEeAAIfAAgK5gxLEwAOAgAfAAgK5gxLEwAOAgAAAA==.Pandamick:BAAANQADCggICgAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggJCAABNQAECgkJIgAdABQhAA==.Parallaxia:BAABNQAECoEiAAMdAAkKFCFKWAAsAgAdAAcK+R9KWAAsAgAlAAIK9CSlQgCvAAAAAA==.Paulmedic:BAABNQAECoEtAAMeAAkKxSYUAAAGBAAeAAkKxSYUAAAGBAAXAAYKURaZLACCAQAAAA==.',
Pb='Pbjellytime:BAABNQAECoEZAAIfAAYKExJ1GACxAQAfAAYKExJ1GACxAQAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECgkJKAAHAEcGAA==.Pegasuz:BAAANQAECggIBwAAAA==.Pello:BAAANQADCgMIAwAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQAECgIIAgAAAA==.',
Ph='Phallics:BAAANQAECgcIEgABNQAFFAYIGQAZAHghAA==.Phoènix:BAABNQAECoEbAAIEAAgKQhcShwBXAgAEAAgKQhcShwBXAgAAAA==.',
Pi='Pikyx:BAAANQAECgYIEwAAAA==.Pinkrock:BAABNQAECoEnAAIKAAgKeB6iRQCeAgAKAAgKeB6iRQCeAgAAAA==.',
Pl='Playboicarti:BAAANQAECggIEAAAAA==.Playmate:BAAANQAECgYIBgAAAA==.Plopperoo:BAABNQAECoEiAAICAAcK8BltNAAdAgACAAcK8BltNAAdAgAAAA==.',
Po='Pocaface:BAAANQAECgcIDgAAAA==.Pogmourne:BAACNQAFFIESAAITAAUK2RmJCACqAQATAAUK2RmJCACqAQA1AAQKgWIAAhMACQrfIUEJAGEDABMACQrfIUEJAGEDAAAA.Polyform:BAABNQAECoEcAAMDAAgKESM7BgACAwADAAgKESM7BgACAwAgAAEK8xQDNAA9AAAAAA==.',
Pr='Preserved:BAAANQAECgYIEgAAAA==.Priestsen:BAAANQADCggIIwAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Puru:BAAANQAECgUIEAAAAA==.',
Py='Pyrhus:BAABNQAECoEiAAIFAAgKnhKxCgDoAQAFAAgKnhKxCgDoAQAAAA==.',
['Pâ']='Pâkerious:BAAANQAECgUICwAAAA==.',
['Pæ']='Pælstrå:BAAANQAECgcIEwAAAA==.',
['Pè']='Pèppermint:BAAANQAECgYJEAABNQAECggIJAAHALYaAA==.',
Qi='Qicacid:BAABNQAECoEyAAMLAAkK6CVgEQBwAwALAAgKxyVgEQBwAwAiAAgKYSEYBADfAgABNQAFFAQIFgAQAEAPAA==.',
Ra='Racoondog:BAAANQAECgYICQABNQAECggIHAALAI0ZAA==.Raehalian:BAAANQADCgcICQAAAA==.Rafedrood:BAABNQAECoEWAAQDAAgKkQlELwDYAAADAAUK3glELwDYAAACAAUKoAV1dQDLAAAgAAQKwQa3JwCXAAAAAA==.Rafemonk:BAAANQAECgYIEgABNQAECggIJwAKAKMPAA==.Rafepally:BAABNQAECoEnAAIKAAgKow8ykADQAQAKAAgKow8ykADQAQAAAA==.Raharn:BAAANQADCgYIBgAAAA==.Raiigun:BAABNQAECoEfAAINAAgK6gxPcgD+AQANAAgK6gxPcgD+AQAAAA==.Rakutina:BAAANQADCgUIDwAAAA==.Ramann:BAABNQAECoEcAAIFAAcKPhjICgDmAQAFAAcKPhjICgDmAQAAAA==.Rampart:BAAANQADCgcIBwAAAA==.Rarule:BAAANQAECggIBAAAAA==.Raspberry:BAAANQADCgQIBAAAAA==.Rastianklin:BAAANQAECgIIAwAAAA==.Ratbro:BAAANQAECgUIDwAAAA==.Rawrbewb:BAAANQAECgEIAQABNQAECgkJKwAEAM8lAA==.Rawrbewbz:BAABNQAECoErAAIEAAkKzyX6BwC4AwAEAAkKzyX6BwC4AwAAAA==.Rawrbutt:BAAANQAECgEIAQABNQAECgkJKwAEAM8lAA==.Rayburd:BAABNQAECoEXAAMUAAgK8xoBBgAyAgAUAAcKRBsBBgAyAgAdAAUKARLduAAtAQAAAA==.Raypejeet:BAABNQAECoEXAAIJAAkKnyIlHwCyAgAJAAkKnyIlHwCyAgAAAA==.Raziiel:BAABNQAECoEaAAIbAAcKig0MQACGAQAbAAcKig0MQACGAQAAAA==.',
Rb='Rbed:BAAANQAECgYJDwAAAA==.',
Re='Realhuman:BAABNQAECoEoAAILAAkKjxkeSACYAgALAAkKjxkeSACYAgAAAA==.Recharge:BAABNQAECoEhAAIHAAgKjRcEPQBRAgAHAAgKjRcEPQBRAgAAAA==.Redhoaxx:BAAANQAECgUIBQAAAA==.Redpally:BAAANQAECgMIBAAAAA==.Redrock:BAAANQADCgYIBwABNQAECggIJwAKAHgeAA==.Relinna:BAABNQAECoEVAAMTAAcKuRbHRQDDAQATAAYKbxjHRQDDAQAIAAIKlgfzhwBPAAAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAECgkJKAACAOkXAA==.Rend:BAAANQADCgMIAwAAAA==.Renegade:BAAANQAECggIAgAAAA==.Resly:BAABNQAECoEqAAIXAAkK3CGjCgATAwAXAAkK3CGjCgATAwAAAA==.Resurrected:BAAANQADCgYIBgAAAA==.Reulna:BAAANQADCgMIAwAAAA==.Revolutionix:BAAANQAECgQIDAAAAA==.',
Rh='Rhodie:BAAANQAECgcIEgAAAA==.',
Ri='Ricuid:BAAANQAECgYIEAAAAA==.Ridemption:BAAANQAECgYICwAAAA==.Rifkin:BAAANQAECgEIAQAAAA==.Rigamautist:BAABNQAECoEYAAITAAYKFhP3XgBVAQATAAYKFhP3XgBVAQAAAA==.Rightguy:BAAANQAECgQIBAAAAA==.Risaka:BAAANQAECgUIBQAAAA==.',
Ro='Roadkill:BAAANQAECgIIAgAAAA==.Roar:BAAANQAECggIAQAAAA==.Roots:BAAANQAECgUIDwAAAA==.Rotelle:BAAANQADCgMJBQAAAA==.Rottenalbo:BAAANQAECgQJDAABNQAECgYIDQABAAAAAA==.',
Ru='Rustyaslock:BAABNQAECoEvAAMdAAgKRw81dADbAQAdAAgKRw81dADbAQAlAAEK9wNDegAsAAAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECggIEwAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Sajal:BAAANQADCgIIAgABNQAECggIIQAHANMfAA==.Saladin:BAAANQAECgUIEQAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQAECgEJAQAAAA==.Samoid:BAAANQADCgcIDQABNQAFFAUIEgAeAP0bAA==.Sanguiniüs:BAAANQAECgQICwAAAA==.Santhea:BAAANQAECgUIDQAAAA==.Sarash:BAAANQADCggICAABNQADCgYICwABAAAAAA==.Sarixz:BAABNQAECoEgAAIOAAgKZhafSQAjAgAOAAgKZhafSQAjAgAAAA==.Sarzyb:BAABNQAECoEfAAIOAAgKRw9WYwDGAQAOAAgKRw9WYwDGAQAAAA==.Sashka:BAAANQAECggIEQAAAA==.Satsuy:BAAANQAFFAEIAQAAAA==.Savaric:BAAANQADCggIDgAAAA==.',
Sc='Scott:BAABNQAECoE5AAILAAkKkBx1MwDeAgALAAkKkBx1MwDeAgAAAA==.Scrubturkey:BAAANQAECgQICQAAAA==.Scuntpetz:BAAANQADCggIDQAAAA==.',
Se='Seamonology:BAABNQAECoEVAAIdAAgKvhhnYAAUAgAdAAgKvhhnYAAUAgABNQAFFAUICwATAOEIAA==.Seether:BAAANQAFFAQIBAABNQAFFAUIDAAWAMwTAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seraithe:BAAANQABCgIJBAAAAA==.Seravael:BAAANQAECgUIDQAAAA==.Sethbash:BAAANQADCggIDwAAAA==.',
Sh='Shadowvoice:BAAANQAECgcIEAAAAA==.Shallan:BAABNQAECoEqAAMEAAgKuB0FjQBKAgAEAAcKXBwFjQBKAgAFAAIKGx9qJACqAAAAAA==.Shamann:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Shapymcshift:BAAANQAECgEIAQABNQAECggIBgABAAAAAA==.Shard:BAAANQADCggJEgAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECgkJKAAHAEcGAA==.Shieldzu:BAAANQADCggIFQAAAA==.Shlappy:BAACNQAFFIERAAITAAUKTBo5CwB1AQATAAUKTBo5CwB1AQA1AAQKgVIAAhMACQo/ITINADcDABMACQo/ITINADcDAAAA.',
Si='Sijki:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Silversham:BAABNQAECoEfAAMPAAgKIx3SMgBvAgAPAAgKIx3SMgBvAgAOAAYK3wk1mgAzAQAAAA==.Silversnow:BAAANQADCggJFAAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAABNQAECoEnAAIVAAcKnx7YCgBnAgAVAAcKnx7YCgBnAgAAAA==.Skiddy:BAACNQAFFIEZAAIQAAcKABfkAgBGAgAQAAcKABfkAgBGAgA1AAQKgSYAAhAACQrMIXEHACEDABAACQrMIXEHACEDAAAA.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skrug:BAAANQAECgUIBwAAAA==.',
Sl='Slowdeath:BAAANQAECgcIDgAAAA==.Slysham:BAABNQAECoEcAAIOAAgKzhv4MACSAgAOAAgKzhv4MACSAgAAAA==.',
Sm='Smeevil:BAABNQAECoEjAAMOAAgKiBgWYQDOAQAOAAYKVhsWYQDOAQAPAAYK7hASkAAyAQAAAA==.Smellyfridge:BAAANQADCgQICAABNQAECgMIBQABAAAAAA==.',
Sn='Sneeds:BAACNQAFFIErAAITAAYKKx8/AwA7AgATAAYKKx8/AwA7AgA1AAQKgVIAAhMACQq8JDMFAJYDABMACQq8JDMFAJYDAAAA.Snowdrifter:BAAANQADCgEIAQAAAA==.Snowflicker:BAAANQAECgMIBQAAAA==.Snowhail:BAAANQAECgcIEwAAAA==.',
So='Soal:BAAANQAECgQIBgAAAA==.Soaringsky:BAACNQAFFIEKAAIEAAQKIgs+IgA1AQAEAAQKIgs+IgA1AQA1AAQKgSQAAgQACQoLHo9LANsCAAQACQoLHo9LANsCAAAA.Solarflares:BAABNQAECoEiAAICAAgKNgtrSACdAQACAAgKNgtrSACdAQAAAA==.Sopheeaa:BAABNQAECoEWAAINAAcKxg5LhwDMAQANAAcKxg5LhwDMAQAAAA==.Soria:BAAANQAECgYIDQAAAA==.Soulblessed:BAABNQAECoEoAAMMAAkKUB7RHADqAgAMAAgKZx/RHADqAgAKAAYKkA091QA3AQAAAA==.Soursop:BAAANQADCgUJCAAAAA==.',
Sp='Sparkychops:BAAANQAECgUIBwAAAA==.Spaztik:BAAANQAECggICwAAAA==.Spectrefive:BAAANQADCgcIDwAAAA==.Spectretwo:BAAANQAECgYIEAAAAA==.Spelcastro:BAAANQAECgYIDAAAAA==.Spherical:BAAANQAECgEIAQABNQAECgkJIAARAAsfAA==.Spknox:BAAANQADCggIIAABNQAECggIDwABAAAAAA==.Splat:BAAANQAECgQIBAAAAA==.Spooklet:BAAANQAECgMIBAAAAA==.Spoonboy:BAABNQAECoElAAIJAAkK1yBSDgAxAwAJAAkK1yBSDgAxAwAAAA==.',
Sq='Squirtmore:BAABNQAECoEZAAIEAAgKURV3mwArAgAEAAgKURV3mwArAgAAAA==.Squirtsalot:BAABNQAECoEbAAMdAAgKphkXTQBNAgAdAAgKyxcXTQBNAgAlAAEKdxYJaABFAAAAAA==.',
St='Starielle:BAAANQAECgUIDgAAAA==.Stark:BAAANQAECgUIEQAAAA==.Steinman:BAAANQAECgMIBQABNQAECgUIBQABAAAAAA==.Stemple:BAABNQAECoEeAAIOAAcKARqyUQAEAgAOAAcKARqyUQAEAgAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAAANQAECgYIEwAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQADCggIIQAAAA==.Stubsy:BAAANQADCgQJBAAAAA==.',
Su='Sublet:BAAANQAECgUIDwAAAA==.Subwayy:BAABNQAECoEbAAMEAAcK+BAjzQDHAQAEAAcKChAjzQDHAQAFAAEKuw01OwA/AAABNQAECgkJLwAOAD8YAA==.Sunshÿne:BAAANQAECgEIAQAAAA==.Suunshine:BAABNQAECoE5AAITAAgKfB57HwCeAgATAAgKfB57HwCeAgAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAABNQAECoEjAAISAAgKCQ5yKACrAQASAAgKCQ5yKACrAQAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Symbiotic:BAAANQAECgQIBAAAAA==.Synfal:BAAANQAECgYIEwAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAABNQAECoEgAAQXAAcKiQhGOgAKAQAXAAYKpghGOgAKAQAaAAYKmAXdHADsAAAeAAEKohMoRQAyAAAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAABNQAECoEaAAMUAAgKKxCpCADbAQAUAAcKVBKpCADbAQAdAAEKDwFwQgEFAAAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgcIDQABNQAECgUIEQABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICwAAAA==.',
['Sý']='Sýrézz:BAAANQADCggICAAAAA==.',
Ta='Taemire:BAAANQAECgMIAwABNQAECggILQAYAGAUAA==.Taezi:BAAANQADCgUIBQAAAA==.Tagger:BAAANQAECgUIBQAAAA==.Tahlia:BAABNQAECoEbAAIPAAgKphJwXwDBAQAPAAgKphJwXwDBAQAAAA==.Takaiya:BAABNQAECoEYAAMlAAcKXSHZCABkAgAlAAYKoCLZCABkAgAdAAEKyxmmGAFMAAAAAA==.Tanglethorn:BAAANQADCgQIBAAAAA==.Tauna:BAAANQADCgQIBAAAAA==.Taur:BAAANQAFFAEIAgAAAA==.',
Te='Technosis:BAAANQADCggIHQAAAA==.Techuu:BAACNQAFFIEWAAMLAAYKCRnbBgAhAgALAAYKCRnbBgAhAgAiAAIKEQaYAgCgAAA1AAQKgSgAAgsACQqdI7gSAGkDAAsACQqdI7gSAGkDAAAA.',
Th='Thade:BAAANQADCgYICwABNQAECgcIGQAaAOsfAA==.Thatdamdruid:BAAANQAECgcIDQAAAA==.Thekhole:BAAANQAECggIDgAAAA==.Thekrelltoss:BAABNQAECoEqAAIEAAkKByACLwAkAwAEAAkKByACLwAkAwAAAA==.Thoriandis:BAAANQAECgQICwAAAA==.Thör:BAAANQADCggICAAAAA==.',
Ti='Tinderella:BAAANQADCgIJAgAAAA==.Tinjam:BAAANQADCgYJBgAAAA==.Tintarella:BAAANQADCgQJBAAAAA==.Titaniumman:BAAANQAECgUICgAAAA==.',
Tj='Tjirp:BAAANQAECgUIDQABNQAECgUIEAABAAAAAA==.',
To='Tohka:BAAANQAECgMIAgABNQAECgkJKQAeAI4lAA==.Tohkna:BAAANQAECgIIAgABNQAECgkJKQAeAI4lAA==.Torale:BAAANQAECgIIAgAAAA==.Tormentar:BAAANQADCgMIAwAAAA==.Totemstout:BAAANQAECgQICAAAAA==.Totemìc:BAAANQADCgUIBwAAAA==.Toteshadow:BAAANQAECgIIAgABNQAECggIIgACAA0cAA==.Tovuk:BAABNQAECoEaAAIhAAcKhxrpCQAUAgAhAAcKhxrpCQAUAgAAAA==.',
Tr='Tranquilitee:BAABNQAECoEcAAISAAgKlxsFHgAUAgASAAgKlxsFHgAUAgAAAA==.Traumateam:BAAANQADCgYJEAABNQAECgUIDwABAAAAAA==.Trebdk:BAAANQAECgMIBAAAAA==.Trebpal:BAABNQAECoEcAAIZAAkKER2MCgDTAgAZAAkKER2MCgDTAgAAAA==.Treecoleos:BAAANQAECgcIEQAAAA==.Treigha:BAAANQADCggIDwABNQAECggILwAiAHMbAA==.Tripleseven:BAAANQADCgUIBQAAAA==.Triplesix:BAAANQAECgIIAwAAAA==.',
Tw='Tweetconic:BAAANQAECgEIAQAAAA==.Tweetess:BAAANQAECgQIBAAAAA==.Twothreesix:BAAANQAECgEIAwAAAA==.Twîsted:BAAANQADCggIGAABNQAECgYIEwABAAAAAA==.',
Ty='Tyborel:BAABNQAECoEiAAMNAAkK7yEGGAAiAwANAAkK7yEGGAAiAwAkAAYKuhjzBgDpAQAAAA==.Tydro:BAAANQAECgcIEgAAAA==.Tyranoc:BAAANQAECgcIEAAAAA==.',
Tz='Tzago:BAAANQAECgEIAgAAAA==.',
Ud='Udòngeìn:BAAANQADCggIFAAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Un='Unholyvixen:BAAANQAECgYIBgAAAA==.',
Us='Usedtobecool:BAAANQAECgYIBwAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQAECgQIBAAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAABNQAECoEhAAIPAAgKXQg5gABdAQAPAAgKXQg5gABdAQAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwAAAA==.Valthalus:BAAANQADCgYIDwAAAA==.Valvet:BAAANQAECgUICAAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQAECgQIBAAAAA==.Vellarya:BAAANQAECgYIEAAAAA==.Velthrax:BAABNQAECoEtAAINAAgKyCX5DwBRAwANAAgKyCX5DwBRAwAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velìn:BAAANQADCggIGwAAAA==.Velín:BAABNQAECoEoAAMLAAkKpRxOPwC1AgALAAkKpRxOPwC1AgAiAAIKVAx3JABnAAAAAA==.',
Vi='Vilaina:BAAANQAECgUICQAAAA==.Villeneth:BAAANQAECgYIBgAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAABNQAECoEkAAMLAAkKwRQoWgBgAgALAAkKwRQoWgBgAgAiAAEKjQzPLQA0AAAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.Vizzo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Vo='Vocck:BAAANQAECgQIBAAAAA==.Vock:BAAANQABCgUIBQABNQAECggIJwAEALYYAA==.Vokk:BAAANQAECgYIBgABNQAECggIJwAEALYYAA==.Vozie:BAABNQAECoEnAAIEAAgKthihjABLAgAEAAgKthihjABLAgAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAABNQAECoEeAAIEAAgKKRfRkwA8AgAEAAgKKRfRkwA8AgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
['Vâ']='Vânâ:BAAANQADCgYIBgAAAA==.',
['Vó']='Vóltron:BAAANQAECgUIBQAAAA==.',
Wa='Wackman:BAABNQAECoEjAAIJAAgKrCQSDABFAwAJAAgKrCQSDABFAwAAAA==.Wargold:BAAANQADCggICAABNQAECggIHwAPACMdAA==.Warmfridge:BAAANQAECgMIBQAAAA==.Wartiant:BAABNQAECoElAAILAAcKSAyWqQCIAQALAAcKSAyWqQCIAQAAAA==.',
Wh='Whiskytango:BAAANQADCgEIAQAAAA==.Whitehall:BAAANQAECgUIEAAAAA==.Whocouldube:BAAANQADCgEJAQAAAA==.Wholegrain:BAABNQAECoEkAAIHAAgKthqQNwBoAgAHAAgKthqQNwBoAgAAAA==.',
Wi='Wickidin:BAAANQADCgMIAwAAAA==.Windhorn:BAAANQAECgYIEAAAAA==.Windi:BAAANQAECgUIBQAAAA==.Wiro:BAAANQAECgUIBQAAAA==.Wirø:BAAANQAECgUIBQAAAA==.',
Wo='Wobbling:BAABNQAECoEYAAILAAkKRhUGZQBBAgALAAkKRhUGZQBBAgAAAA==.Wobblock:BAAANQAECgUICgAAAA==.Wombee:BAAANQAECgQIBAAAAA==.Wonderia:BAABNQAECoEeAAIeAAkK0xcNDgB8AgAeAAkK0xcNDgB8AgAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
Wy='Wylia:BAABNQAECoEWAAIYAAgKQQh8LwB/AQAYAAgKQQh8LwB/AQAAAA==.',
['Wí']='Wíiman:BAAANQAECggIDwAAAA==.',
Xa='Xalath:BAAANQAECgQIBwAAAA==.',
Xe='Xeenah:BAABNQAECoFJAAMjAAgKxQcINQB6AQAjAAgK2AYINQB6AQANAAIK1QhkFgF+AAAAAA==.',
Xi='Xiconz:BAAANQADCgUIBQAAAA==.Xilef:BAAANQAECgUICAAAAA==.',
Xx='Xxjackie:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.',
Xy='Xyz:BAACNQAFFIEMAAMWAAUKzBOzBQCUAQAWAAUKzBOzBQCUAQAmAAEK9BaiEQBPAAA1AAQKgRsAAxYACQpxH5UVAKoCABYACQotH5UVAKoCACYABQpvFlIsAEMBAAAA.',
Ya='Yamaka:BAACNQAFFIEWAAIDAAYK7SJEAABrAgADAAYK7SJEAABrAgA1AAQKgSUAAgMACQqkJqUAAOwDAAMACQqkJqUAAOwDAAAA.',
Ys='Yseult:BAAANQAECgQICgAAAA==.',
Za='Zaarocc:BAAANQAECgcIDQAAAA==.Zaarock:BAABNQAECoEsAAMJAAkK6R/JFgDtAgAJAAkK6R/JFgDtAgATAAEKgRMquQA3AAAAAA==.Zaishadow:BAAANQAECgcIEwAAAA==.Zandro:BAAANQAECgUICgAAAA==.Zandrocas:BAAANQADCgIIAgAAAA==.Zanduill:BAAANQAECggICAAAAA==.Zanhighawen:BAAANQADCggIHgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQAECgcIDQAAAA==.Zayva:BAAANQAECgUIDwAAAA==.',
Ze='Zealfu:BAAANQAECgMIAwABNQAECgUIDgABAAAAAA==.Zeali:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Zealthyr:BAAANQAECgUIDgAAAA==.Zeztuknar:BAAANQAECgYICgAAAA==.',
Zi='Ziege:BAAANQAECgUIBQAAAA==.Zincberg:BAAANQADCggIIQAAAA==.Ziyn:BAABNQAECoEYAAIMAAkKdBZfMQCFAgAMAAkKdBZfMQCFAgABNQAFFAQIBgAjAJoJAA==.',
Zo='Zorbax:BAAANQAECgUICgAAAA==.',
Zy='Zykaei:BAABNQAECoEpAAIeAAkKjiUpAQC5AwAeAAkKjiUpAQC5AwAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAgABNQAECgcIDQABAAAAAA==.',
['Áy']='Áylamao:BAABNQAECoErAAIbAAcKcA1oQACEAQAbAAcKcA1oQACEAQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggIPwAAAA==.',
['Éh']='Éh:BAABNQAECoEaAAIcAAgKexGwJAACAgAcAAgKexGwJAACAgAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECggISAAGANobAA==.Ðisciple:BAABNQAECoFIAAMGAAgK2huBBwDlAQAHAAcKYRnXTgAOAgAGAAYK0RuBBwDlAQAAAA==.',
['Øb']='Øbiwan:BAAANQAECgQIBQAAAA==.',
['Øc']='Øctavia:BAAANQADCgQIBQAAAA==.',
['ßi']='ßinchicken:BAAANQAECgYIEwAAAA==.',
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
