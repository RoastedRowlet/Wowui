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

local lookup = {'Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Arcane','Warrior-Protection','Paladin-Retribution','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline','DemonHunter-Vengeance','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','Warrior-Fury','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Priest-Holy',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abbyss:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Abirnar:BAAANQAECgMIBQAAAA==.Abramelinn:BAAANQAECgIIBAAAAA==.Abygayle:BAAANQAECgEIAQAAAA==.',
Ac='Acca:BAAANQAECgEIAQAAAA==.',
Ad='Adget:BAAANQAECgYIDgAAAA==.Adorion:BAAANQADCgYIDgAAAA==.',
Ae='Aerali:BAAANQAECgcIEQAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgQIBwAAAA==.Agôny:BAAANQAECgQICAAAAA==.',
Ah='Ahsõka:BAAANQADCgYICwAAAA==.',
Ai='Aidzboy:BAAANQAECgEIAgABNQAECgQICAABAAAAAA==.',
Al='Aldin:BAAANQADCgQIAgAAAA==.Alexandrõs:BAAANQAECgcICAAAAA==.Alfah:BAAANQADCgcIFAAAAA==.Aliatris:BAAANQAECgIIAgAAAA==.Alicia:BAAANQADCgUIBQAAAA==.Alkamay:BAAANQAECgMIAwAAAA==.Allor:BAAANQADCggIEAAAAA==.Allorpally:BAAANQAECgYICwAAAA==.Altofmyalt:BAAANQADCgIIAgAAAA==.Aluii:BAABNQAECoEWAAICAAgJ1SAbGwD1AgACAAgJ1SAbGwD1AgAAAA==.Alyssana:BAAANQAECgQICgAAAA==.Alyxpally:BAAANQAECgEIAQAAAA==.Alyxpants:BAAANQAECgUIBgAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaria:BAAANQAECgQIBwAAAA==.Ambulance:BAAANQAECgcIBgAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQAECgIIAgAAAA==.Angelsfly:BAAANQAECgEIAgAAAA==.Angæl:BAAANQAECgIIAgAAAA==.Annallyne:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQADCggICAAAAA==.Anultrun:BAAANQAECgIIAgAAAA==.',
Ar='Arabellaa:BAAANQADCgIIAgAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQADCgcIFwAAAA==.Arcyandor:BAAANQADCgYIDgAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgYIDQAAAA==.',
As='Ashmear:BAAANQAECgIIAgAAAA==.Astalon:BAAANQABCgYIDQAAAA==.',
At='Athreos:BAAANQAECgIIAwAAAA==.Atüned:BAAANQAECgYIDwAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAABNQAECoEcAAMDAAYJcA/BTgBuAQADAAYJcA/BTgBuAQAEAAEJxQMUuwAtAAAAAA==.',
Av='Avelane:BAAANQAECgYICwAAAA==.',
Az='Azubasaurus:BAABNQAECoEYAAMFAAgJ+CSeAgBhAwAFAAgJ+CSeAgBhAwAGAAEJbBp2JQBOAAAAAA==.',
Ba='Baelor:BAAANQAECgIIAgAAAA==.Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgYICQAAAA==.Balerion:BAAANQAECgEIAQAAAA==.Barback:BAAANQABCgcIDAAAAA==.Barkstard:BAABNQAECoEYAAMHAAgJXRYxHwBBAgAHAAgJXRYxHwBBAgAIAAEJcAFSQgArAAAAAA==.Barleyalive:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQAECgEIAQAAAA==.',
Be='Belarii:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.Bellonae:BAAANQAECgIIAgAAAA==.Belmenth:BAAANQADCgEIAQAAAA==.Bendecida:BAAANQAECgIIAgABNQAECgIIBAABAAAAAA==.Benington:BAAANQAECgUIBQAAAA==.Benn:BAACNQAFFIEJAAMJAAQJrgohAwDiAAAJAAMJ+AshAwDiAAAKAAEJ0AalGAAlAAA1AAQKgSkAAwkACQkcJUcBALsDAAkACQkcJUcBALsDAAsAAglKH3JnAJUAAAAA.Bergarr:BAAANQADCgQIBAAAAA==.',
Bh='Bhyta:BAAANQAECgcIDAAAAA==.',
Bi='Bishopbob:BAAANQADCgcIBwAAAA==.Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAAANQAECgYIEQAAAA==.',
Bj='Bjartastrasz:BAAANQAECgIIAwAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAAANQAECgcIEAAAAA==.Blaumeux:BAAANQADCgYIBgAAAA==.Blazine:BAAANQABCgYIBwAAAA==.Bliksem:BAAANQADCggICAAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggIDQABNQAECgYIDAABAAAAAA==.Bluesham:BAAANQAECgIIAgAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAAANQAECgYIEgAAAA==.Bowsbfrhoez:BAABNQAECoEdAAIMAAcJMRqkLQBFAgAMAAcJMRqkLQBFAgAAAA==.Boyaka:BAAANQAECgMIAwAAAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQAECgIIAwAAAA==.',
Bu='Bubblëøseven:BAAANQAECgUICAAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQADCgYICwABNQAECgYIDAABAAAAAA==.',
['Bë']='Bëllädonna:BAAANQADCgcIGwAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoE1AAINAAkJQByYKgDmAgANAAkJQByYKgDmAgAAAA==.Cardoney:BAAANQAECgQIDAAAAA==.Cariah:BAAANQAECgUIDAAAAA==.Catashax:BAAANQADCgcIEQAAAA==.',
Cd='Cdkit:BAABNQAECoEdAAIOAAcJexJnCgDKAQAOAAcJexJnCgDKAQAAAA==.',
Ce='Celestè:BAAANQADCggIFgAAAA==.',
Ch='Chasstise:BAAANQAECgEIAQAAAA==.Chazze:BAAANQADCgQIBQAAAA==.Cheazdruid:BAAANQADCgQIBAAAAA==.Cheggery:BAAANQADCggIEAAAAA==.Chikubiz:BAAANQAECggICAAAAA==.Chirp:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Chirpe:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.Chubbypope:BAAANQAECgIIAgAAAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgEIAQABAAAAAA==.Cindrick:BAABNQAECoEcAAIFAAkJXxyOAwBCAwAFAAkJXxyOAwBCAwAAAA==.',
Cl='Clessta:BAAANQAECgIIAgAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAAANQAECgcICwAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgMICgABAAAAAA==.Clynefate:BAAANQADCgIIAgAAAA==.',
Co='Coffêê:BAAANQAECgcIEQAAAA==.Coggers:BAAANQADCgUIBQAAAA==.Coldbringer:BAAANQAECgQIBgAAAA==.Coldpalmer:BAAANQAECgQIBAABNQAECgYIDQABAAAAAA==.Coleostrasz:BAAANQADCgEIAQAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Corastrasza:BAAANQAECgIIAgAAAA==.',
Cr='Cresentmoon:BAAANQADCgcIGAAAAA==.Crimsonmage:BAAANQAECgUIBgAAAA==.Crowchild:BAAANQADCgQIBAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCgUIBQAAAA==.',
Cu='Cursedlight:BAAANQAECgYICAAAAA==.',
Cy='Cynnal:BAAANQADCgcIDQAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgUICQAAAA==.Dahj:BAAANQAECgIIAgAAAA==.Dalanar:BAAANQAECgEIAQAAAA==.Danathjo:BAAANQAECgEIAQAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAAANQAECgUICAAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAAANQAECgQICgAAAA==.Debris:BAAANQAECgYIBwAAAA==.Dedmongrel:BAAANQAECgQIBwAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgQIBQAAAA==.Demonicmonk:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Dengar:BAAANQAECgQIBAAAAA==.Desyphium:BAABNQAECoEbAAIPAAkJPiKoDABEAwAPAAkJPiKoDABEAwAAAA==.Deviltrigger:BAAANQADCgUICAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQADCgcIFgAAAA==.Deweysan:BAAANQAECgIIAwAAAA==.Dex:BAABNQAECoEjAAIEAAkJUCExCAA2AwAEAAkJUCExCAA2AwAAAA==.',
Di='Direforge:BAAANQAECgIIBAAAAA==.Disreputable:BAAANQADCgUIBAAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgQIBAAAAA==.Dracothyr:BAAANQADCggIEAAAAA==.Draemon:BAABNQAECoEnAAIQAAgJ3STNAABRAwAQAAgJ3STNAABRAwAAAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFIEPAAIRAAYJPCBoAABlAgARAAYJPCBoAABlAgA1AAQKgRkAAxEACQkiJWQCAKcDABEACQkiJWQCAKcDABIABgloIOkdAOgBAAAA.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQADCgEIAQABNQAECgYIDQABAAAAAA==.Drastiricka:BAAANQADCgYIEAAAAA==.Dreadlocksta:BAAANQADCgMIAwAAAA==.Dreamer:BAAANQADCggIDAAAAA==.Drinkwater:BAAANQAECgMICgAAAA==.Drucaila:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIEgAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgEIAQAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAABNQAECoEaAAINAAgJOyD4LwDRAgANAAgJOyD4LwDRAgAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eatduhpupu:BAAANQAECgQICAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Elfhelm:BAAANQAECgIIAgAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellisinor:BAAANQAECgEIAQAAAA==.Eluneschosen:BAAANQAECgEIAQAAAA==.Elured:BAAANQAECgYICgAAAA==.',
Em='Embermist:BAAANQAECgIIAgAAAA==.Emliy:BAAANQAECgYIDAAAAA==.Emogirl:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAAANQAECgYICAAAAA==.',
Ep='Ephesian:BAAANQAECgIIAwAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.Erobas:BAAANQAECgYIEQAAAA==.Erodan:BAAANQAECgYIDAAAAA==.',
Es='Esserian:BAAANQAECgIIBAAAAA==.Estarae:BAAANQAECgYIEgAAAA==.Esthane:BAAANQAECgYICgAAAA==.',
Et='Eternaldawn:BAAANQADCgYIDAAAAA==.',
Eu='Euphuzadan:BAAANQAECgcIEQAAAA==.',
Ev='Eveliala:BAAANQABCgMIAwAAAA==.Everhealer:BAABNQAECoEgAAITAAcJoRM9BQDZAQATAAcJoRM9BQDZAQAAAA==.Evienarian:BAAANQABCgUICwAAAA==.Evillumber:BAAANQAECgEIAQAAAA==.',
Ex='Exiledemon:BAAANQAECgYICgAAAA==.',
Ey='Eyéspy:BAAANQAECgYIBgAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Fatonement:BAAANQAECgUIBQAAAA==.Fauvm:BAAANQAECgQICQAAAA==.',
Fe='Feanassa:BAAANQAECgIIBAAAAA==.Fearwood:BAAANQADCggIDgAAAA==.Felfeet:BAAANQAECgQIBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQADCggIGAAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.',
Fi='Fishing:BAAANQAECgcIEgAAAA==.',
Fl='Flaviousqt:BAAANQAECgIIAgAAAA==.Flavorofkrel:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Flekzakzak:BAAANQAECgQICQAAAA==.Flekzugzug:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.Flezappezix:BAABNQAFFIEFAAIDAAIJ5RryCAC7AAADAAIJ5RryCAC7AAAAAA==.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAAANQAECgcIDgAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAUICAAFABsRAA==.Forald:BAAANQADCgMIAwAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAACNQAFFIEFAAMLAAQJxR3DAgAjAQALAAMJFx3DAgAjAQAJAAEJzh8jBwBlAAA1AAQKgRcAAwsACAneJkkKACcDAAsACAkfJUkKACcDAAkABgmOJkcMAI8CAAAA.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAABNQAECoE3AAIIAAkJRg4pEwDsAQAIAAkJRg4pEwDsAQAAAA==.Frostienips:BAAANQAECgMIAwAAAA==.Frostiness:BAAANQADCgYICwAAAA==.Frostmagee:BAAANQADCgYIEwAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAAANQAECgUICAAAAA==.Fupanchoo:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Garthurn:BAAANQADCgUIBgAAAA==.Gaskull:BAAANQAECgQICAAAAA==.Gaybacon:BAAANQADCgIIAgABNQAECgIIBAABAAAAAA==.',
Gh='Ghostsaber:BAAANQAECgIIAgAAAA==.',
Gi='Giddykitty:BAAANQADCgcIFAAAAA==.Gimballock:BAAANQAECgEIAQAAAA==.',
Gl='Glennthehen:BAAANQADCggIDAAAAA==.',
Go='Goatvier:BAABNQAECoEaAAIUAAkJ4CUtAADmAwAUAAkJ4CUtAADmAwAAAA==.Goblinator:BAAANQAECgQIBQAAAA==.Golojo:BAAANQADCgQICAAAAA==.Goodenia:BAAANQADCgQIBgAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goosef:BAAANQAECgIIAwAAAA==.Gopro:BAAANQADCgYICQAAAA==.Gorbag:BAAANQADCgYIBgAAAA==.Gorhowl:BAAANQAECgcIDQAAAA==.Gorli:BAAANQADCggIGAAAAA==.Gottoloveit:BAAANQADCgYIBgABNQADCggIHAABAAAAAA==.Gottolurveit:BAAANQADCggIHAAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAAANQAECgcIDQAAAA==.Gravadin:BAAANQAECgUIBQAAAA==.Great:BAAANQADCgYIBgABNQAECgkJHQAVAM8jAA==.Gretchin:BAAANQAECgIIBAAAAA==.Groshlow:BAAANQAECgIIAgAAAA==.',
Gu='Guinness:BAAANQADCgIIAgAAAA==.Gunji:BAAANQAECgQIBgAAAA==.',
['Gä']='Gändalf:BAAANQAECgQIBgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesblood:BAACNQAFFIEGAAIKAAQJdBsEBABvAQAKAAQJdBsEBABvAQA1AAQKgSEAAgoACQlIHhgLAAYDAAoACQlIHhgLAAYDAAAA.Hakiheal:BAAANQAECgYICgAAAA==.Hakzert:BAACNQAFFIEHAAIWAAUJZxHgAAC5AQAWAAUJZxHgAAC5AQA1AAQKgSAAAxYACQmAHTcDADEDABYACQmAHTcDADEDABcABwkZCl0gADcBAAAA.Happyfeett:BAAANQADCgQIBAAAAA==.Harex:BAAANQAECgUICgAAAA==.Harlon:BAAANQADCgMIBAAAAA==.Hartcake:BAAANQADCgQIBAAAAA==.Haylø:BAAANQADCggICwAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Hektîc:BAAANQADCgcIBwAAAA==.Hellsgate:BAAANQAECgIIAgAAAA==.Hellshunter:BAAANQAECgYICwAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQADCgYIBwAAAA==.Hexalock:BAAANQAECgYIDAAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgYICwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexentjie:BAAANQADCggIGAAAAA==.Hexiemattel:BAAANQAECgEIAQAAAA==.Hexington:BAAANQABCgMIAwAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hezaq:BAAANQAECgIIAgAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollowvoice:BAAANQAECgUICgAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAAANQAECgYIDAAAAA==.Horacio:BAAANQADCggIGgAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgQIBAAAAA==.Huntymcshoot:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Huntér:BAAANQAECgYIBwAAAA==.',
['Hù']='Hùntrèss:BAAANQAECgEIAQAAAA==.',
Ic='Icdedpple:BAAANQAECgQIBwAAAA==.Icymama:BAAANQADCgcIFQAAAA==.',
Id='Idevouryou:BAAANQADCgYIEQAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Il='Illicet:BAAANQADCgcICwAAAA==.',
Im='Imchirp:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Imicedup:BAAANQAECgEIAQAAAA==.Impblaster:BAAANQAECgEIAQABNQAECgQIDAABAAAAAA==.',
In='Inarius:BAAANQAECgQICwAAAA==.Incompetent:BAAANQADCgcIFgAAAA==.Indriná:BAAANQAECgYICwAAAA==.Inflictor:BAAANQAECgUICgAAAA==.Insanenachos:BAAANQAECgQIBQAAAA==.Inumbra:BAAANQAECgQIBgAAAA==.',
Ir='Ironknee:BAAANQAECgYIDgAAAA==.',
Is='Isterra:BAAANQADCgUIBQAAAA==.',
It='Ithareos:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQAECgEIAQAAAA==.',
Iz='Izate:BAAANQAECgIIAgAAAA==.Izulia:BAAANQAECgYIDAAAAA==.Izulid:BAAANQADCgYICAABNQADCgcIEgABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQABNQADCggICAABAAAAAA==.Jabiraka:BAAANQADCggIEAAAAA==.Jackiexx:BAAANQAECgIIBAAAAA==.Jakestanater:BAAANQADCgcIEwAAAA==.Jassel:BAAANQAECgIIAwAAAA==.Jazmeine:BAAANQADCgIIAgAAAA==.',
Je='Jestër:BAAANQAECgEIAQAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAAANQAECgYIEgAAAA==.',
Jj='Jjester:BAAANQADCgUIDAABNQAECgEIAQABAAAAAA==.',
Jl='Jlabinos:BAAANQAECgIIAgABNQAECgUICgABAAAAAA==.Jlaby:BAAANQAECgUICgAAAA==.',
Jp='Jpxhunter:BAAANQAECgcICAAAAA==.',
Ju='Juicei:BAAANQAECgQICgAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
Jw='Jw:BAAANQAECggIAwAAAA==.',
['Jë']='Jëster:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ka='Kaesoron:BAABNQAECoEZAAIYAAcJUBnGVgBxAQAYAAcJUBnGVgBxAQAAAA==.Kagéslammer:BAAANQADCggIGgAAAA==.Kaiser:BAAANQAECgUIBgAAAA==.Kanundrum:BAAANQAECgIIAwAAAA==.Karaxynn:BAAANQAECgcIEgAAAA==.Karmasnightt:BAAANQADCgYIDQAAAA==.Kaulder:BAAANQAECgEIAQAAAA==.',
Ke='Kebabyy:BAAANQAECgQIEQAAAA==.Keeze:BAAANQADCgIIAgABNQAECggIGQAZAKAKAA==.Keheia:BAAANQADCgYICQAAAA==.Keilna:BAAANQADCgQIBAAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAAANQAECgIIAgAAAA==.Khodii:BAAANQAECgIIAgAAAA==.Khoho:BAAANQAECgEIAQAAAA==.Khrøne:BAAANQAECgYIDwAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQADCgYIBwAAAA==.',
Ki='Killsaw:BAAANQABCgIIAgAAAA==.Kity:BAAANQAECgEIAQAAAA==.',
Kn='Knail:BAAANQAECgEIAQAAAA==.Knickyou:BAAANQADCgYICAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQAECgEIAQAAAA==.Konokö:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Kr='Kreuzschlitz:BAAANQAECgEIAQAAAA==.Kreztek:BAAANQADCgQIBAAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQAECgEIAQAAAA==.Krippg:BAAANQADCgIIAgABNQAECgcIEQABAAAAAA==.Kripwar:BAAANQAECgcIEQAAAA==.Krizkin:BAAANQAECgEIAQAAAA==.Krugg:BAAANQADCggIEgAAAA==.',
Ku='Kungpao:BAAANQAECgQIBAAAAA==.',
Ky='Kynhark:BAAANQADCgMICQAAAA==.Kyoudo:BAAANQAECgYIEgAAAA==.',
La='Laelha:BAAANQADCgUIBQAAAA==.Latricia:BAAANQADCggIEAAAAA==.Laurél:BAAANQAECgUICgAAAA==.Layonpaws:BAABNQAECoEfAAIPAAcJ+RoONwAkAgAPAAcJ+RoONwAkAgAAAA==.',
Le='Lecked:BAAANQAECgEIAgAAAA==.Leggodex:BAAANQAECgEIAQAAAA==.Leighandra:BAAANQADCgcIGAAAAA==.Lemures:BAAANQAECgYIBwAAAA==.Leonà:BAAANQAECgQIBAAAAA==.',
Li='Lidera:BAAANQADCggIDQAAAA==.Liebspawn:BAAANQADCggIEAAAAA==.Lightreign:BAAANQAECgIIAgAAAA==.Linarisa:BAAANQAECgQIDQAAAA==.Liquidate:BAAANQAECgUICAAAAA==.Litori:BAAANQAECgUIBwAAAA==.',
Ll='Llux:BAAANQADCggIDAAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAABNQAECoEaAAIPAAgJghCfQgDtAQAPAAgJghCfQgDtAQAAAA==.Looksmaxxor:BAAANQAECgUICAAAAA==.Loryn:BAAANQAECgYIDAAAAA==.',
Lu='Lucarro:BAAANQAECgQIBAABNQAECgkJHAAFAF8cAA==.Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQAECgQICgAAAA==.Lunavale:BAAANQAECgcICwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Lytemup:BAAANQAECgEIAQAAAA==.',
['Lä']='Läkan:BAAANQAECgEIAQAAAA==.',
['Lù']='Lùcifer:BAAANQABCgQIAgABNQAECgYIEQABAAAAAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.Maenir:BAAANQADCggIDwAAAA==.Magnytize:BAAANQAECgUICAAAAA==.Magoose:BAAANQAECgcICQAAAA==.Mags:BAABNQAECoEZAAIHAAgJPRjeGgBvAgAHAAgJPRjeGgBvAgAAAA==.Majinboom:BAAANQAECgQIBAAAAA==.Maldred:BAAANQADCggIFAABNQAECgUIDgABAAAAAA==.Maldreds:BAAANQAECgUIDgAAAA==.Manicmonday:BAAANQADCggIEgAAAA==.Marsie:BAAANQAECgQIBwAAAA==.Mashex:BAAANQAECgQIBwAAAA==.',
Me='Medieval:BAAANQAECgUICgAAAA==.Mediyah:BAAANQADCgYIEAAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Meljira:BAAANQAECgMIAwAAAA==.Melonyummy:BAACNQAFFIEGAAIRAAQJDSImAgCjAQARAAQJDSImAgCjAQA1AAQKgR8AAhEACQm/JlUAAP4DABEACQm/JlUAAP4DAAAA.Menzel:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQAECgEIAQAAAA==.Mesohorni:BAAANQAECgEIAQAAAA==.Messerian:BAAANQADCgMIAwABNQAECgIIBAABAAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milzey:BAAANQAECgUICgAAAA==.Mindweaver:BAAANQAECgMIBQAAAA==.Miniscule:BAAANQADCggICAAAAA==.Miradin:BAAANQAECgEIAQAAAA==.Mirv:BAAANQAECgcIEgAAAA==.Misshapp:BAAANQADCgIIAgAAAA==.Misspickles:BAAANQAECgUICwAAAA==.Mistakoji:BAAANQAECgUIBwAAAA==.',
Mo='Mogwii:BAAANQAECggIAgAAAA==.Moit:BAAANQADCgQIBAAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQADCgcIDQAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monononoke:BAAANQADCgYIDQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Moosocalypse:BAAANQADCgUIBQAAAA==.Morella:BAAANQAECgEIAQAAAA==.',
Mu='Munta:BAAANQADCgYIFAAAAA==.Munter:BAAANQAECgYIDgAAAA==.Mursha:BAAANQAECgIIAwAAAA==.Muzblue:BAAANQAFFAIIAwAAAA==.Muzw:BAAANQAECgQIBgAAAA==.',
['Mï']='Mïkarika:BAAANQAECgIIAwAAAA==.',
Na='Naalaxii:BAAANQAECgYIEAAAAA==.Naero:BAAANQAECgQIBAAAAA==.Naerond:BAAANQADCgUIBQAAAA==.Nalfeiin:BAAANQAECgQIDAAAAA==.Narnardk:BAABNQAECoEbAAIJAAkJvB7yBwDrAgAJAAkJvB7yBwDrAgAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrstorm:BAAANQAECgYIEgAAAA==.Naturised:BAAANQAECgIIAgAAAA==.Naursalla:BAAANQADCggIEgAAAA==.Nawe:BAAANQAECgQIBQAAAA==.',
Ne='Neflyn:BAAANQADCggIHAAAAA==.Nemmystrata:BAAANQAECgQIBAAAAA==.Nessaandra:BAAANQAECgUICwAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDgAAAA==.',
Ni='Niftage:BAAANQADCgYIDwABNQAECgMIAwABAAAAAA==.Niftana:BAAANQAECgMIAwAAAA==.Nimirie:BAAANQAECgQIBwAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQIBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Nokshaman:BAAANQAECgUICAAAAA==.Noxtard:BAAANQADCggIEAAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQADCgYIDAAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCgYIDgAAAA==.',
Ok='Okazi:BAAANQAECgUICAABNQAECgUICgABAAAAAA==.',
Ol='Olafuga:BAAANQAECgYIEgAAAA==.Oldblood:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Oo='Ookolok:BAAANQADCggIDQAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Op='Oppressor:BAAANQADCgcIDAAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCggIFAAAAA==.Ormal:BAAANQADCgcIEgAAAA==.',
Os='Osma:BAAANQAECgQIBQABNQAFFAUICAAYAPsVAA==.Osmess:BAAANQAECgYIEwABNQAFFAUICAAYAPsVAA==.Osmology:BAACNQAFFIEIAAMYAAUJ+xXqBgAAAQAYAAMJfhXqBgAAAQAaAAIJtxa3BAC3AAA1AAQKgSAABBgACQnJJUMQAN4CABgABwmpJUMQAN4CABoABgnDGMQQAM0BABsAAQnnFicZAEMAAAAA.',
Oz='Ozzietree:BAABNQAECoEgAAIHAAkJqh/lDQAJAwAHAAkJqh/lDQAJAwAAAA==.',
Pa='Paddingtonn:BAAANQADCgcIGAAAAA==.Pandachì:BAAANQAECgQICgAAAA==.Pandamick:BAAANQADCggICgAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggICAABNQAECggIGQAYAPofAA==.Parallaxia:BAABNQAECoEZAAMYAAgJ+h8DNgD7AQAYAAYJUh4DNgD7AQAaAAIJ9CTBMgDBAAAAAA==.Paulmedic:BAAANQAECgYIDAAAAA==.',
Pb='Pbjellytime:BAAANQAECgIIBAAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQADCgYIEAAAAA==.',
Ph='Phallics:BAAANQAECgYICwABNQAFFAUICAAVAPwUAA==.Phoènix:BAAANQAECgQIBwAAAA==.',
Pi='Pikyx:BAAANQAECgIIAwAAAA==.Pinkrock:BAAANQAECgYIDAAAAA==.',
Pl='Playboicarti:BAAANQAECggIDwAAAA==.Plopperoo:BAAANQAECgMIBQAAAA==.',
Po='Pocaface:BAAANQAECgEIAQAAAA==.Pogmourne:BAABNQAECoE3AAIKAAkJnBs1FACQAgAKAAkJnBs1FACQAgAAAA==.Polyform:BAABNQAECoEZAAMcAAgJCiMbAgApAwAcAAgJCiMbAgApAwAdAAEJ8xTJGgA+AAAAAA==.',
Pr='Preserved:BAAANQAECgQIBwAAAA==.Priestsen:BAAANQADCgcIEQAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Puru:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Py='Pyrhus:BAAANQAECgYICgAAAA==.',
['Pâ']='Pâkerious:BAAANQAECgEIAQAAAA==.',
['Pæ']='Pælstrå:BAAANQADCggICgAAAA==.',
['Pè']='Pèppermint:BAAANQAECgIIBAABNQAECgQICAABAAAAAA==.',
Qi='Qicacid:BAABNQAECoEZAAMeAAkJDB8xAQAZAwAeAAgJYSExAQAZAwACAAMJjhc5ogDOAAABNQAECgkJHAAFAF8cAA==.',
Ra='Raehalian:BAAANQADCgcICQAAAA==.Rafedrood:BAAANQAECgUIBgAAAA==.Rafemonk:BAAANQAECgQIBAABNQAECgYIDAABAAAAAA==.Rafepally:BAAANQAECgYIDAAAAA==.Raharn:BAAANQADCgYIBgAAAA==.Raiigun:BAAANQAECgQIBgAAAA==.Rakutina:BAAANQADCgUIDwAAAA==.Ramann:BAAANQAECgUIBwAAAA==.Raspberry:BAAANQADCgQIBAAAAA==.Rastianklin:BAAANQADCgcIFwAAAA==.Ratbro:BAAANQAECgQIBwAAAA==.Rawrbewbz:BAAANQAECgcIEgAAAA==.Rawrbutt:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Rayburd:BAAANQAECgYIDAAAAA==.Raypejeet:BAABNQAECoEXAAILAAkJnyLqBgBfAwALAAkJnyLqBgBfAwAAAA==.Raziiel:BAAANQAECgQIBQAAAA==.',
Rb='Rbed:BAAANQAECgYIDwAAAA==.',
Re='Realhuman:BAAANQAECgYIDQAAAA==.Recharge:BAAANQAECgYICwAAAA==.Redhoaxx:BAAANQADCggICAAAAA==.Redpally:BAAANQADCgYIBgAAAA==.Redrock:BAAANQADCgYIBwABNQAECgYIDAABAAAAAA==.Relinna:BAAANQAECgYICAAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAECggIGQAHAD0YAA==.Rend:BAAANQADCgMIAwAAAA==.Resly:BAABNQAECoEaAAIXAAgJYiBtCgCrAgAXAAgJYiBtCgCrAgAAAA==.Reulna:BAAANQADCgIIAgAAAA==.Revolutionix:BAAANQAECgIIAgAAAA==.',
Rh='Rhodie:BAAANQAECgUIBgAAAA==.',
Ri='Ricuid:BAAANQAECgIIAgAAAA==.Ridemption:BAAANQAECgMIAgAAAA==.Rifkin:BAAANQADCgcIEwAAAA==.Rigamautist:BAAANQAECgQIBgAAAA==.Rightguy:BAAANQADCgYIBgAAAA==.',
Ro='Roadkill:BAAANQADCgYICwAAAA==.Roots:BAAANQAECgEIAQAAAA==.Rotelle:BAAANQADCgMIBQAAAA==.Rottenalbo:BAAANQAECgQIDAAAAA==.',
Ru='Rustyaslock:BAAANQAECgYIEgAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECgQIBQAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Saladin:BAAANQAECgQIBwAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQAECgEIAQAAAA==.Samoid:BAAANQADCgcIDQABNQAECgkJHAAWAAYjAA==.Sanguiniüs:BAAANQAECgQICwAAAA==.Santhea:BAAANQADCgYICgAAAA==.Sarixz:BAAANQAECgYIEAAAAA==.Sarzyb:BAAANQAECgYIDAAAAA==.Sashka:BAAANQAECgYIDgAAAA==.Satsuy:BAAANQAECgMIAgAAAA==.',
Sc='Scott:BAAANQAECgYIEwAAAA==.Scrubturkey:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Scuntpetz:BAAANQADCggIDQAAAA==.',
Se='Seamonology:BAAANQAECgcIEgABNQAFFAEIAQABAAAAAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seraithe:BAAANQABCgIIBAAAAA==.Seravael:BAAANQAECgQIBwAAAA==.Sethbash:BAAANQADCggIDwAAAA==.',
Sh='Shadowvoice:BAAANQAECgUICAAAAA==.Shallan:BAAANQAECgYIDwAAAA==.Shamann:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Shapymcshift:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Shard:BAAANQADCggICAAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECgYIEQABAAAAAA==.Shieldzu:BAAANQADCgcIEgAAAA==.Shlappy:BAABNQAECoE1AAIKAAkJLx5BCwAEAwAKAAkJLx5BCwAEAwAAAA==.',
Si='Silversham:BAAANQAECgQICAAAAA==.Silversnow:BAAANQADCgcIDAAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAAANQAECgQIBgAAAA==.Skiddy:BAACNQAFFIEIAAIFAAUJGxHKAgCwAQAFAAUJGxHKAgCwAQA1AAQKgSAAAgUACQmtIV8DAEgDAAUACQmtIV8DAEgDAAAA.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skrug:BAAANQAECgIIAwAAAA==.',
Sl='Slysham:BAAANQAECgUICgAAAA==.',
Sm='Smeevil:BAAANQAECgYICgAAAA==.Smellyfridge:BAAANQADCgQICAABNQADCggICAABAAAAAA==.',
Sn='Sneeds:BAACNQAFFIEQAAIKAAUJbRqeCwCIAAAKAAUJbRqeCwCIAAA1AAQKgUYAAgoACQl9JBACAL0DAAoACQl9JBACAL0DAAAA.Snowdrifter:BAAANQADCgEIAQAAAA==.Snowhail:BAAANQAECgQIBwAAAA==.',
So='Soal:BAAANQAECgQIBgAAAA==.Soaringsky:BAABNQAECoEaAAINAAkJvRmmMQDKAgANAAkJvRmmMQDKAgAAAA==.Softfireball:BAAANQADCgYICAAAAA==.Solarflares:BAAANQAECgQICQAAAA==.Sopheeaa:BAAANQAECgQICQAAAA==.Soria:BAAANQAECgQIBwAAAA==.Soulblessed:BAAANQAECgcIEQAAAA==.Soursop:BAAANQADCgUIBgAAAA==.',
Sp='Sparkychops:BAAANQAECgUIBwAAAA==.Spaztik:BAAANQAECggICwAAAA==.Spectrefive:BAAANQADCgcICAAAAA==.Spectretwo:BAAANQADCgYIFwAAAA==.Spherical:BAAANQAECgEIAQABNQAECgkJGQAGAJMcAA==.Spknox:BAAANQADCggIGgAAAA==.Spooklet:BAAANQAECgEIAQAAAA==.Spoonboy:BAABNQAECoEVAAILAAgJFx5CEADXAgALAAgJFx5CEADXAgAAAA==.',
Sq='Squirtmore:BAAANQAECgQICQAAAA==.Squirtsalot:BAAANQAECgQIBgAAAA==.',
St='Starielle:BAAANQAECgIIAwAAAA==.Stark:BAAANQAECgQIBAAAAA==.Steinman:BAAANQAECgIIAgAAAA==.Stemple:BAAANQAECgQIDAAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAAANQAECgIIAwAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQADCgcIEgAAAA==.Stubsy:BAAANQADCgQIBAAAAA==.',
Su='Sublet:BAAANQAECgEIAQAAAA==.Subwayy:BAAANQAECgIIBAAAAA==.Sunshÿne:BAAANQADCgIIAgAAAA==.Suunshine:BAAANQAECgYIEQAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAAANQAECgQICgAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Synfal:BAAANQAECgMIBwAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAAANQAECgQICgAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAAANQAECgUICgAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICwAAAA==.',
Ta='Taemire:BAAANQAECgMIAwABNQAECgYIEgABAAAAAA==.Tahlia:BAAANQAECgUICQAAAA==.Takaiya:BAAANQAECgIIAwAAAA==.Tanglethorn:BAAANQADCgQIBAAAAA==.Tauna:BAAANQADCgQIBAAAAA==.',
Te='Technosis:BAAANQADCggIGAAAAA==.Techuu:BAACNQAFFIEGAAMCAAQJZQx5BwBDAQACAAQJZQx5BwBDAQAeAAEJYQXAAQBKAAA1AAQKgR8AAgIACQl6IeALAGsDAAIACQl6IeALAGsDAAAA.',
Th='Thade:BAAANQADCgMIAwABNQAECgIIBAABAAAAAA==.Thatdamdruid:BAAANQAECgQIBwAAAA==.Thekhole:BAAANQAECgQIBAAAAA==.Thekrelltoss:BAAANQAECgcIEQAAAA==.Thoriandis:BAAANQADCgYIBwAAAA==.',
Ti='Tinjam:BAAANQADCgYIBgAAAA==.',
Tj='Tjirp:BAAANQADCgYICwABNQAECgIIAwABAAAAAA==.',
To='Tohkna:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Torale:BAAANQADCggIDQAAAA==.Totemstout:BAAANQAECgQICAAAAA==.Toteshadow:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Tovuk:BAAANQAECgQICgAAAA==.',
Tr='Tranquilitee:BAAANQAECgQIBwAAAA==.Traumateam:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.Trebdk:BAAANQAECgMIBAAAAA==.Trebpal:BAAANQAECgUIBQAAAA==.Treecoleos:BAAANQAECgEIAgAAAA==.Treigha:BAAANQADCggIDwABNQAECgYIEgABAAAAAA==.Tripleseven:BAAANQADCgUIBQAAAA==.Triplesix:BAAANQADCgYIBgAAAA==.',
Tw='Tweetconic:BAAANQADCgcIFAAAAA==.Tweetess:BAAANQADCgEIAQAAAA==.Twothreesix:BAAANQAECgEIAwAAAA==.Twîsted:BAAANQADCggIGAAAAA==.',
Ty='Tyborel:BAAANQAECgcIEQAAAA==.Tydro:BAAANQAECgMIAwAAAA==.Tyranoc:BAAANQADCgUIBQAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Us='Usedtobecool:BAAANQAECgYIBwAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQAECgQIBAAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAAANQAECgQICgAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwAAAA==.Valthalus:BAAANQADCgYIDwAAAA==.Valvet:BAAANQAECgMIAwAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQADCgcIBwAAAA==.Vellarya:BAAANQAECgIIAgAAAA==.Velthrax:BAABNQAECoEdAAIMAAgJqyQvBwBeAwAMAAgJqyQvBwBeAwAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velìn:BAAANQADCgUICAAAAA==.Velín:BAAANQAECgcIEgAAAA==.',
Vi='Villeneth:BAAANQADCggIDQAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAAANQAECggICgAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.Vizzo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Vo='Vocck:BAAANQABCgEIAgAAAA==.Vock:BAAANQABCgUIBQABNQAECgYIEAABAAAAAA==.Vokk:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.Vozie:BAAANQAECgYIEAAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAAANQAECgYIDgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
['Vâ']='Vânâ:BAAANQADCgYIBgAAAA==.',
['Vó']='Vóltron:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.',
Wa='Wackman:BAAANQAECgcIDQAAAA==.Warmfridge:BAAANQADCggICAAAAA==.Wartiant:BAABNQAECoEXAAICAAYJbQlMeABSAQACAAYJbQlMeABSAQAAAA==.',
Wh='Whitehall:BAAANQAECgIIAgAAAA==.Wholegrain:BAAANQADCggIIgABNQAECgQICAABAAAAAA==.',
Wi='Windhorn:BAAANQAECgMIAwAAAA==.Windi:BAAANQADCgYIEAAAAA==.Wiro:BAAANQADCgUIBwAAAA==.Wirø:BAAANQADCgIIAwAAAA==.',
Wo='Wobbling:BAAANQAECgcIDQAAAA==.Wobblock:BAAANQAECgQIBwAAAA==.Wombee:BAAANQADCgcICwAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
Wy='Wylia:BAAANQAECgUIBQAAAA==.',
['Wí']='Wíiman:BAAANQAECgcIDAAAAA==.',
Xa='Xalath:BAAANQAECgEIAQAAAA==.',
Xe='Xeenah:BAABNQAECoEdAAMfAAcJEQVNKgAaAQAfAAYJWQRNKgAaAQAMAAEJYglRwABIAAAAAA==.',
Xi='Xilef:BAAANQADCggIFgAAAA==.',
Xx='Xxjackie:BAAANQADCgcIDQABNQAECgIIBAABAAAAAA==.',
Xy='Xyz:BAACNQAFFIEFAAMgAAMJSxcdAgAVAQAgAAMJFhcdAgAVAQAhAAEJ9Bb8CABWAAA1AAQKgRoAAyAACQlxH58FAAoDACAACQktH58FAAoDACEABQlvFhcfAGwBAAAA.',
Ya='Yamaka:BAACNQAFFIEGAAIcAAQJRyBxAACWAQAcAAQJRyBxAACWAQA1AAQKgR4AAhwACQmwJUgAAOUDABwACQmwJUgAAOUDAAAA.',
Ys='Yseult:BAAANQAECgIIAgAAAA==.',
Za='Zaarock:BAABNQAECoEWAAMLAAgJgR13EgC+AgALAAgJXhx3EgC+AgAKAAEJgRMSfwA6AAAAAA==.Zaishadow:BAAANQAECgQIBwAAAA==.Zandro:BAAANQADCgcIFAAAAA==.Zanduill:BAAANQADCggIHAAAAA==.Zanhighawen:BAAANQADCggIFgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Zayva:BAAANQAECgEIAQAAAA==.',
Ze='Zeali:BAAANQADCgEIAQABNQAECgIIBAABAAAAAA==.Zealthyr:BAAANQAECgIIBAAAAA==.Zere:BAAANQAECgQICQABNQAECggIHQAMALskAA==.Zeztuknar:BAAANQAECgEIAQAAAA==.',
Zi='Zincberg:BAAANQADCgcIEgAAAA==.',
Zo='Zorbax:BAAANQAECgEIAQAAAA==.',
Zy='Zykaei:BAAANQAECgcIEgAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAgAAAA==.',
['Áy']='Áylamao:BAAANQAECgQIDQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggIHwAAAA==.',
['Éh']='Éh:BAAANQAECgYICgAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECgcIHQATAPEYAA==.Ðisciple:BAABNQAECoEdAAMTAAcJ8RicBAD6AQATAAYJ0RucBAD6AQAiAAEJtAfwhwA9AAAAAA==.',
['Øb']='Øbiwan:BAAANQADCgYICwAAAA==.',
['Øc']='Øctavia:BAAANQADCgQIBQAAAA==.',
['ßi']='ßinchicken:BAAANQAECgQIBAAAAA==.',
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
