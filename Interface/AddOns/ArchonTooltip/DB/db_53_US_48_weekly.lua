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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Preservation','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Warrior-Arms','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abbyss:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Abirnar:BAAANQAECgIIAgAAAA==.Abramelinn:BAAANQAECgIIAgAAAA==.Abygayle:BAAANQADCggICAAAAA==.',
Ac='Acca:BAAANQAECgEIAQAAAA==.',
Ad='Adget:BAAANQAECgYICgAAAA==.Adorion:BAAANQADCgYIDgAAAA==.',
Ae='Aerali:BAAANQAECgYICgAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgMIAwAAAA==.Agôny:BAAANQAECgQICAAAAA==.',
Ah='Ahsõka:BAAANQADCgYICwAAAA==.',
Ai='Aidzboy:BAAANQADCggICwABNQAECgQIBAABAAAAAA==.',
Al='Aldin:BAAANQADCgIIAgAAAA==.Alexandrõs:BAAANQAECgEIAQAAAA==.Alfah:BAAANQADCgYIDQAAAA==.Aliatris:BAAANQADCggIEgAAAA==.Alicia:BAAANQADCgUIBQAAAA==.Alkamay:BAAANQADCgQIBAAAAA==.Allor:BAAANQADCggIEAAAAA==.Allorpally:BAAANQAECgMIBQAAAA==.Altofmyalt:BAAANQADCgIIAgAAAA==.Aluii:BAAANQAECgcIDQAAAA==.Alyssana:BAAANQAECgMIBgAAAA==.Alyxpally:BAAANQAECgEIAQAAAA==.Alyxpants:BAAANQAECgQIBQAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaria:BAAANQAECgMIAwAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQADCggIEAAAAA==.Angelsfly:BAAANQAECgEIAQAAAA==.Angæl:BAAANQADCggIEgAAAA==.Annallyne:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQADCgYIBgAAAA==.',
Ar='Arabellaa:BAAANQADCgIIAgAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQADCgcIEAAAAA==.Arcyandor:BAAANQADCgUICQAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgUIBwAAAA==.',
As='Ashmear:BAAANQADCgcIEwAAAA==.Ashê:BAAANQADCgYIBgAAAA==.Astalon:BAAANQABCgYICQAAAA==.',
At='Athreos:BAAANQAECgEIAQAAAA==.Atüned:BAAANQAECgYICQAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAAANQAECgUIEAAAAA==.',
Av='Avelane:BAAANQAECgQIBQAAAA==.',
Az='Azubasaurus:BAAANQAECgcIDQAAAA==.',
Ba='Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgMIAwAAAA==.Balerion:BAAANQADCgcIFQAAAA==.Barback:BAAANQABCgYICwAAAA==.Barkstard:BAAANQAECgcIDQAAAA==.Barleyalive:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQADCggIDgAAAA==.',
Be='Belarii:BAAANQADCgUICQABNQADCgcICgABAAAAAA==.Bellonae:BAAANQADCgcICgAAAA==.Belmenth:BAAANQADCgEIAQAAAA==.Bendecida:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.Benington:BAAANQAECgQIBAAAAA==.Benn:BAABNQAECoEfAAMCAAkJrCPxAACmAwACAAkJrCPxAACmAwADAAIJSh/uVACcAAAAAA==.Bergarr:BAAANQADCgQIBAAAAA==.',
Bh='Bhyta:BAAANQAECgQIBQAAAA==.',
Bi='Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAAANQAECgYICwAAAA==.',
Bj='Bjartastrasz:BAAANQAECgEIAQAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAAANQAECgYICwAAAA==.Blaumeux:BAAANQADCgYIBgAAAA==.Blazine:BAAANQABCgYIBwAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggICQABNQAECgQIBgABAAAAAA==.Bluesham:BAAANQADCggIFQAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAAANQAECgQIBgAAAA==.Bowsbfrhoez:BAAANQAECgUIEAAAAA==.Boyaka:BAAANQADCgYIBgABNQADCggIEAABAAAAAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.',
Bu='Bubblëøseven:BAAANQAECgMIAwAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQADCgYICwABNQAECgQIBgABAAAAAA==.',
['Bë']='Bëllädonna:BAAANQADCgYIDgAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoEjAAIEAAkJ3BrbIQDMAgAEAAkJ3BrbIQDMAgAAAA==.Cardoney:BAAANQAECgQICAAAAA==.Cariah:BAAANQAECgQIBwAAAA==.Catashax:BAAANQADCgcIEQAAAA==.',
Cd='Cdkit:BAAANQAECgUIEAAAAA==.',
Ce='Celestè:BAAANQADCgcIDwAAAA==.',
Ch='Chasstise:BAAANQADCggIIAAAAA==.Chazze:BAAANQADCgMIAQAAAA==.Cheazdruid:BAAANQADCgQIBAAAAA==.Cheggery:BAAANQADCgYIDgAAAA==.Chirp:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Chirpe:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Chubbypope:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgEIAQABAAAAAA==.Cindrick:BAAANQAFFAEIAgAAAA==.',
Cl='Clessta:BAAANQADCggIFQAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAAANQAECgQIBAAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgIIAwABAAAAAA==.',
Co='Coffêê:BAAANQAECgYICgAAAA==.Coldbringer:BAAANQAECgQIBAAAAA==.Coldpalmer:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Coleostrasz:BAAANQADCgEIAQAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Corastrasza:BAAANQADCggIEQAAAA==.',
Cr='Cresentmoon:BAAANQADCgcIEQAAAA==.Crimsonmage:BAAANQAECgEIAQAAAA==.',
Cu='Cursedlight:BAAANQAECgEIAgAAAA==.',
Cy='Cynnal:BAAANQADCgYIBgAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgQIBAAAAA==.Dahj:BAAANQADCggIDgAAAA==.Dalanar:BAAANQADCgYIBgAAAA==.Danathjo:BAAANQADCggIDgAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAAANQAECgIIAwAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAAANQAECgQIBgAAAA==.Debris:BAAANQAECgQIBAAAAA==.Dedmongrel:BAAANQAECgMIAwAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgEIAQAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAMIBAABAAAAAA==.Dengar:BAAANQADCggICAAAAA==.Desyphium:BAAANQAECggIEwAAAA==.Deviltrigger:BAAANQADCgQIBwAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQADCgcIEAAAAA==.Deweysan:BAAANQAECgEIAQAAAA==.Dex:BAABNQAECoEgAAIFAAgJayImCAADAwAFAAgJayImCAADAwAAAA==.',
Di='Direforge:BAAANQADCggIFQAAAA==.Disreputable:BAAANQADCgUIBQAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgQIBAAAAA==.Dracothyr:BAAANQADCggIEAAAAA==.Draemon:BAABNQAECoEaAAIGAAcJQyGMAQCiAgAGAAcJQyGMAQCiAgAAAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFIEJAAIHAAUJFxxzAADqAQAHAAUJFxxzAADqAQA1AAQKgRYAAwcACQmFI9IBAJIDAAcACQmFI9IBAJIDAAgABgloID4XAAACAAAA.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQADCgEIAQABNQAECgYIBwABAAAAAA==.Drastiricka:BAAANQADCgYICwAAAA==.Dreadlocksta:BAAANQADCgMIAwAAAA==.Dreamer:BAAANQADCgUIBwAAAA==.Drinkwater:BAAANQAECgIIAwAAAA==.Drucaila:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIDQAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgEIAQAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAAANQAECgcIEAAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eatduhpupu:BAAANQAECgQIBAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Elfhelm:BAAANQADCgcIFAAAAA==.Elipsis:BAAANQADCgYIBgAAAA==.Ellisinor:BAAANQADCggIIgAAAA==.Elured:BAAANQAECgQIBAAAAA==.',
Em='Embermist:BAAANQADCggIDwAAAA==.Emliy:BAAANQAECgYICAAAAA==.Emogirl:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAAANQAECgIIAgAAAA==.',
Ep='Ephesian:BAAANQAECgEIAQAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Erobas:BAAANQAECgUIBwAAAA==.Erodan:BAAANQAECgQIBgAAAA==.',
Es='Esserian:BAAANQAECgIIAgAAAA==.Estarae:BAAANQAECgQIBgAAAA==.Esthane:BAAANQAECgQIBAAAAA==.',
Et='Eternaldawn:BAAANQADCgYIBgAAAA==.',
Eu='Euphuzadan:BAAANQAECgYICgAAAA==.',
Ev='Eveliala:BAAANQABCgEIAQAAAA==.Everhealer:BAAANQAECgUIDgAAAA==.Evienarian:BAAANQABCgQICAAAAA==.Evillumber:BAAANQADCgYIEQAAAA==.',
Ex='Exiledemon:BAAANQAECgYICQAAAA==.',
Ey='Eyéspy:BAAANQAECgQIBAAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Fauvm:BAAANQAECgIIAgAAAA==.',
Fe='Feanassa:BAAANQADCgIIAgAAAA==.Fearwood:BAAANQADCggIDgAAAA==.Felfeet:BAAANQAECgQIBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQADCggIDwAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.',
Fi='Fishing:BAAANQAECgcICwAAAA==.',
Fl='Flaviousqt:BAAANQADCggIDAAAAA==.Flekzakzak:BAAANQAECgQIBAAAAA==.Flezappezix:BAAANQAFFAIIBAAAAA==.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAAANQAECgYIBwAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAECgkJGAAJANIgAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAABNQAECoEXAAMDAAgJ3iarBgA/AwADAAgJHyWrBgA/AwACAAYJjiY+BgCjAgAAAA==.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAABNQAECoEmAAIKAAgJuQhVEQCnAQAKAAgJuQhVEQCnAQAAAA==.Frostienips:BAAANQADCgcIBwAAAA==.Frostiness:BAAANQADCgUIBQAAAA==.Frostmagee:BAAANQADCgUIEAAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAAANQADCggIEgAAAA==.Fupanchoo:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Garthurn:BAAANQADCgQIBAAAAA==.Gaskull:BAAANQAECgQIBQAAAA==.Gaybacon:BAAANQADCgIIAgABNQADCggIFQABAAAAAA==.',
Gh='Ghostsaber:BAAANQADCggIFAAAAA==.',
Gi='Giddykitty:BAAANQADCgYIDQAAAA==.Gimballock:BAAANQADCgcIFQAAAA==.',
Gl='Glennthehen:BAAANQADCgcIBwAAAA==.',
Go='Goatvier:BAAANQAECggIEwAAAA==.Goblinator:BAAANQAECgMIAwAAAA==.Goodenia:BAAANQADCgQIBAAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goosef:BAAANQADCgEIAQAAAA==.Gopro:BAAANQADCgMIAwAAAA==.Gorhowl:BAAANQAECgYIBwAAAA==.Gorli:BAAANQADCgYIEAAAAA==.Gottolurveit:BAAANQADCggIFAAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAAANQAECgYICAAAAA==.Gravadin:BAAANQAECgQIBAAAAA==.Great:BAAANQADCgYIBgABNQAECgkJGAALABUhAA==.Gretchin:BAAANQAECgEIAgAAAA==.Groshlow:BAAANQAECgIIAgAAAA==.',
Gu='Guinness:BAAANQADCgIIAgAAAA==.Gunji:BAAANQAECgIIAgAAAA==.',
['Gä']='Gändalf:BAAANQAECgIIAgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesblood:BAABNQAECoEYAAIMAAkJlRwGCAAAAwAMAAkJlRwGCAAAAwAAAA==.Hakiheal:BAAANQAECgMIBAAAAA==.Hakzert:BAABNQAECoEYAAMNAAkJpAotCgD6AQANAAkJpAotCgD6AQAOAAcJGQpwFwBLAQAAAA==.Happyfeett:BAAANQADCgQIBAAAAA==.Harex:BAAANQAECgQIBQAAAA==.Harlon:BAAANQADCgMIBAAAAA==.Haylø:BAAANQADCggICwAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Hellsgate:BAAANQAECgIIAgAAAA==.Hellshunter:BAAANQAECgQIBQAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQADCgYIBwAAAA==.Hexalock:BAAANQAECgYIBgAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgUIBwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexentjie:BAAANQADCggICAAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hezaq:BAAANQADCggIFQAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollowvoice:BAAANQAECgQIBQAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAAANQAECgQIBgAAAA==.Horacio:BAAANQADCgcIEwAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgQIBAAAAA==.Huntymcshoot:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Huntér:BAAANQAECgEIAQAAAA==.',
['Hù']='Hùntrèss:BAAANQADCgcIEwAAAA==.',
Ic='Icdedpple:BAAANQAECgMIAwAAAA==.Icymama:BAAANQADCgcIDgAAAA==.',
Id='Idevouryou:BAAANQADCgYIDAAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Im='Imchirp:BAAANQADCgUIDQABNQAECgEIAQABAAAAAA==.Imicedup:BAAANQADCggIDgAAAA==.Impblaster:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
In='Inarius:BAAANQAECgQIBwAAAA==.Incompetent:BAAANQADCgUIDwAAAA==.Indriná:BAAANQAECgUIBQAAAA==.Inflictor:BAAANQAECgQIBQAAAA==.Insanenachos:BAAANQAECgEIAQAAAA==.Inumbra:BAAANQAECgMIAwAAAA==.',
Ir='Ironknee:BAAANQAECgYICAAAAA==.',
It='Ithareos:BAAANQADCggIFQAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQADCgcIBwAAAA==.',
Iz='Izate:BAAANQADCgYIBgAAAA==.Izulia:BAAANQAECgQIBgAAAA==.Izulid:BAAANQADCgQIBQABNQADCgYICwABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQAAAA==.Jabiraka:BAAANQADCggIEAAAAA==.Jackiexx:BAAANQAECgIIBAABNQAECgUICgABAAAAAA==.Jakestanater:BAAANQADCgcIEgAAAA==.Jassel:BAAANQAECgEIAQAAAA==.Jazmeine:BAAANQADCgIIAgAAAA==.',
Je='Jestër:BAAANQADCgMIAwABNQADCgQIBgABAAAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAAANQAECgQIBgAAAA==.',
Jj='Jjester:BAAANQADCgQIBgAAAA==.',
Jl='Jlabinos:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Jlaby:BAAANQAECgQIBQAAAA==.',
Jp='Jpxhunter:BAAANQAECgEIAQAAAA==.',
Ju='Juicei:BAAANQAECgMIBgAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
['Jë']='Jëster:BAAANQADCgEIAQABNQADCgQIBgABAAAAAA==.',
Ka='Kagéslammer:BAAANQADCgcIEgAAAA==.Kaiser:BAAANQAECgMIAwAAAA==.Kanundrum:BAAANQAECgEIAQAAAA==.Karaxynn:BAAANQAECgYICwAAAA==.Karmasnightt:BAAANQADCgQICAAAAA==.Kaulder:BAAANQADCgIIBAAAAA==.',
Ke='Kebabyy:BAAANQAECgQICQAAAA==.Keheia:BAAANQADCgYICQAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAAANQADCgcIFAAAAA==.Khodii:BAAANQADCgYICwAAAA==.Khoho:BAAANQADCggIDgAAAA==.Khrøne:BAAANQAECgUICQAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQABCgYICQAAAA==.',
Ki='Killsaw:BAAANQABCgIIAgAAAA==.Kity:BAAANQADCggICgAAAA==.',
Kn='Knail:BAAANQADCgcIEwAAAA==.Knickyou:BAAANQADCgYICAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQADCggIDgAAAA==.',
Kr='Kreuzschlitz:BAAANQADCgcIBwAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQADCggIEAAAAA==.Krippg:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.Kripwar:BAAANQAECgcICwAAAA==.Krizkin:BAAANQADCggIIAAAAA==.Krugg:BAAANQADCggIEgAAAA==.',
Ku='Kungpao:BAAANQAECgQIBAAAAA==.',
Ky='Kynhark:BAAANQADCgIIBQAAAA==.Kyoudo:BAAANQAECgQIBgAAAA==.',
La='Latricia:BAAANQADCggIEAAAAA==.Laurél:BAAANQAECgQIBQAAAA==.Layonpaws:BAAANQAECgcIEQAAAA==.',
Le='Lecked:BAAANQAECgEIAQAAAA==.Leggodex:BAAANQADCgcICAAAAA==.Leighandra:BAAANQADCgcIEQAAAA==.Lemures:BAAANQAECgEIAQAAAA==.Leonà:BAAANQABCgIIBAAAAA==.',
Li='Lidera:BAAANQADCgcIBwAAAA==.Liebspawn:BAAANQADCgYIDgAAAA==.Lightreign:BAAANQAECgEIAQAAAA==.Linarisa:BAAANQAECgIIBQAAAA==.Liquidate:BAAANQAECgIIAwAAAA==.Litori:BAAANQAECgMIAwAAAA==.',
Ll='Llux:BAAANQADCggICgAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAAANQAECgcIDwAAAA==.Looksmaxxor:BAAANQAECgUIBgAAAA==.Loryn:BAAANQAECgUIBgAAAA==.',
Lu='Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQAECgMIAwAAAA==.Lunavale:BAAANQAECgQIBAAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Lytemup:BAAANQADCggIDgAAAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Maenir:BAAANQADCggIDwAAAA==.Magnytize:BAAANQAECgUICAAAAA==.Magoose:BAAANQAECgIIAgAAAA==.Mags:BAAANQAECgcIDgAAAA==.Majinboom:BAAANQADCgYICgAAAA==.Maldred:BAAANQADCggIDAABNQAECgQICAABAAAAAA==.Maldreds:BAAANQAECgQICAAAAA==.Manicmonday:BAAANQADCgUICgAAAA==.Marsie:BAAANQAECgIIAwAAAA==.Mashex:BAAANQAECgMIAwAAAA==.',
Me='Medieval:BAAANQAECgQIBQAAAA==.Mediyah:BAAANQADCgYIEAAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQADCgQIBQABNQADCggIDQABAAAAAA==.Meljira:BAAANQADCggIDQAAAA==.Melonyummy:BAABNQAECoEXAAIHAAkJvyYaAAAKBAAHAAkJvyYaAAAKBAAAAA==.Menzel:BAAANQADCgUIBQABNQADCggIIAABAAAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQADCggIIAAAAA==.Messerian:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milzey:BAAANQAECgQIBQAAAA==.Mindweaver:BAAANQAECgIIAgAAAA==.Miradin:BAAANQADCgcICgAAAA==.Mirv:BAAANQAECgYICwAAAA==.Misspickles:BAAANQAECgQIBgAAAA==.Mistakoji:BAAANQAECgQIBgAAAA==.Mistspark:BAAANQADCgQIBQAAAA==.',
Mo='Moit:BAAANQADCgQIBAAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQADCgYIBgAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monononoke:BAAANQADCgEIAQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Morella:BAAANQAECgEIAQAAAA==.',
Mu='Munta:BAAANQADCgYIDwAAAA==.Munter:BAAANQAECgQICAAAAA==.Mursha:BAAANQAECgEIAQAAAA==.Muzblue:BAAANQAFFAEIAQAAAA==.Muzw:BAAANQAECgEIAQAAAA==.',
['Mï']='Mïkarika:BAAANQAECgEIAQAAAA==.',
Na='Naalaxii:BAAANQAECgYICgAAAA==.Naero:BAAANQADCgYIDQAAAA==.Naerond:BAAANQADCgUIBQAAAA==.Nalfeiin:BAAANQAECgQICAAAAA==.Narnardk:BAAANQAECgcIEAAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrstorm:BAAANQAECgQIBgAAAA==.Naturised:BAAANQADCggIFQAAAA==.Naursalla:BAAANQADCgYIDAAAAA==.Nawe:BAAANQAECgQIBAAAAA==.',
Ne='Neflyn:BAAANQADCggIFAAAAA==.Nemmystrata:BAAANQADCggIEwAAAA==.Nessaandra:BAAANQAECgQIBgAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDQAAAA==.',
Ni='Niftage:BAAANQADCgUICQABNQADCggIFQABAAAAAA==.Niftana:BAAANQADCggIFQAAAA==.Nimirie:BAAANQAECgMIAwAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQIBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Nokshaman:BAAANQAECgIIAwAAAA==.Noxtard:BAAANQADCggIEAAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQADCgYIDAAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCgYIDgAAAA==.',
Ok='Okazi:BAAANQAECgIIAwABNQAECgQIBQABAAAAAA==.',
Ol='Olafuga:BAAANQAECgQIBgAAAA==.',
Oo='Ookolok:BAAANQADCgYICQAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Op='Oppressor:BAAANQADCgYIBgAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCgcIDAAAAA==.Ormal:BAAANQADCgYICwAAAA==.',
Os='Osma:BAAANQAECgIIAgABNQAECgkJGAAPAKIlAA==.Osmess:BAAANQAECgYIDwABNQAECgkJGAAPAKIlAA==.Osmology:BAABNQAECoEYAAQPAAkJoiVNCADkAgAPAAcJdyVNCADkAgAQAAYJwxgXDwDUAQARAAEJ5xZKEgBKAAAAAA==.',
Oz='Ozzietree:BAABNQAECoEXAAISAAkJLRrFEQCHAgASAAkJLRrFEQCHAgAAAA==.',
Pa='Paddingtonn:BAAANQADCgcIGAAAAA==.Pandachì:BAAANQAECgMIBgAAAA==.Pandamick:BAAANQABCgIIAgAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Parallaxia:BAAANQAECgYIEAAAAA==.Paulmedic:BAAANQAECgQIBgAAAA==.',
Pb='Pbjellytime:BAAANQAECgIIBAAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQADCgYIEAAAAA==.',
Ph='Phallics:BAAANQAECgYIBgABNQAFFAMIAwABAAAAAA==.Phoènix:BAAANQAECgMIAwAAAA==.',
Pi='Pikyx:BAAANQAECgEIAQAAAA==.Pinkrock:BAAANQAECgQIBgAAAA==.',
Pl='Playboicarti:BAAANQAECgcIDgAAAA==.Plopperoo:BAAANQAECgIIAwAAAA==.',
Po='Pocaface:BAAANQAECgEIAQAAAA==.Pogmourne:BAABNQAECoEmAAIMAAgJ3RtyDwB/AgAMAAgJ3RtyDwB/AgAAAA==.Polyform:BAAANQAECgcIEAAAAA==.',
Pr='Preserved:BAAANQAECgMIAwAAAA==.Priestsen:BAAANQADCgcICwAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Puru:BAAANQADCggIEAAAAA==.',
Py='Pyrhus:BAAANQAECgQIBAAAAA==.',
['Pâ']='Pâkerious:BAAANQADCggIIAAAAA==.',
['Pæ']='Pælstrå:BAAANQADCgIIAgAAAA==.',
['Pè']='Pèppermint:BAAANQAECgEIAgABNQAECgQICAABAAAAAA==.',
Qi='Qicacid:BAAANQAFFAEIAQABNQAFFAEIAgABAAAAAA==.',
Ra='Raehalian:BAAANQADCgYIBgAAAA==.Rafedrood:BAAANQAECgMIAwAAAA==.Rafemonk:BAAANQADCggIFwABNQAECgQIBgABAAAAAA==.Rafepally:BAAANQAECgQIBgAAAA==.Raiigun:BAAANQAECgQIBgAAAA==.Rakutina:BAAANQADCgUICwAAAA==.Ramann:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Rastianklin:BAAANQADCgcIEQAAAA==.Ratbro:BAAANQAECgMIAwAAAA==.Rawrbewbz:BAAANQAECgYICwAAAA==.Rayburd:BAAANQAECgQIBgAAAA==.Raypejeet:BAABNQAECoEXAAIDAAkJnyKnAwCAAwADAAkJnyKnAwCAAwAAAA==.Raziiel:BAAANQAECgEIAQAAAA==.',
Rb='Rbed:BAAANQAECgYICgAAAA==.',
Re='Realhuman:BAAANQAECgYIBwAAAA==.Recharge:BAAANQAECgUIBQAAAA==.Redrock:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Relinna:BAAANQAECgIIAgAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Resly:BAAANQAECgcIDwAAAA==.Reulna:BAAANQADCgIIAgAAAA==.',
Rh='Rhodie:BAAANQAECgMIAwAAAA==.',
Ri='Ricuid:BAAANQADCggIFQAAAA==.Ridemption:BAAANQAECgIIAQAAAA==.Rifkin:BAAANQADCgcIDAAAAA==.Rigamautist:BAAANQAECgIIAgAAAA==.Rightguy:BAAANQADCgMIAwAAAA==.',
Ro='Roadkill:BAAANQADCgYICwAAAA==.Roots:BAAANQADCggIIAAAAA==.Rotelle:BAAANQADCgMIAwAAAA==.Rottenalbo:BAAANQAECgIIBAAAAA==.',
Ru='Rustyaslock:BAAANQAECgQIBgAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECgQIBAAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Saladin:BAAANQAECgMIAwAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQABCgIIAQAAAA==.Samoid:BAAANQADCgcIDQABNQAECgkJGAANAOEhAA==.Sanguiniüs:BAAANQAECgQICAAAAA==.Santhea:BAAANQADCgYIBgAAAA==.Sarixz:BAAANQAECgYICgAAAA==.Sarzyb:BAAANQAECgQIBgAAAA==.Sashka:BAAANQAECgYICgAAAA==.Satsuy:BAAANQAECgIIAgAAAA==.',
Sc='Scott:BAAANQAECgQICAAAAA==.Scrubturkey:BAAANQADCggIDgAAAA==.Scuntpetz:BAAANQABCgEIAQAAAA==.',
Se='Seamonology:BAAANQAECgcIEgAAAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seravael:BAAANQAECgMIAwAAAA==.Sethbash:BAAANQADCgcIBwAAAA==.',
Sh='Shadowvoice:BAAANQAECgIIAwAAAA==.Shallan:BAAANQAECgUIDQAAAA==.Shamann:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Shieldzu:BAAANQADCgYICwAAAA==.Shindig:BAAANQAECgUIDAAAAA==.Shlappy:BAABNQAECoEsAAIMAAgJTxvcDwB6AgAMAAgJTxvcDwB6AgAAAA==.',
Si='Silversham:BAAANQAECgQIBAAAAA==.Silversnow:BAAANQADCgUIBQAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAAANQAECgMIAgAAAA==.Skiddy:BAABNQAECoEYAAIJAAkJ0iDsAQBeAwAJAAkJ0iDsAQBeAwAAAA==.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skiphunter:BAAANQADCgIIBAAAAA==.Skrug:BAAANQADCggIDwAAAA==.',
Sl='Slysham:BAAANQAECgQIBQAAAA==.',
Sm='Smeevil:BAAANQAECgQIBAAAAA==.Smellyfridge:BAAANQADCgQICAABNQADCgYIBgABAAAAAA==.',
Sn='Sneeds:BAACNQAFFIEGAAIMAAIJmREdCgBHAAAMAAIJmREdCgBHAAA1AAQKgToAAgwACQlMJOIBAKoDAAwACQlMJOIBAKoDAAAA.Snowdrifter:BAAANQADCgEIAQAAAA==.Snowhail:BAAANQAECgMIAwAAAA==.',
So='Soal:BAAANQAECgQIBAAAAA==.Soaringsky:BAAANQAECggIEQAAAA==.Softfireball:BAAANQADCgQIBQAAAA==.Solarflares:BAAANQAECgQIBAAAAA==.Sopheeaa:BAAANQAECgQIBQAAAA==.Soria:BAAANQAECgMIAwAAAA==.Soulblessed:BAAANQAECgUICgAAAA==.Soursop:BAAANQADCgUIBQAAAA==.',
Sp='Sparkychops:BAAANQAECgIIAgAAAA==.Spaztik:BAAANQAECggIBAAAAA==.Spectretwo:BAAANQADCgYIEQAAAA==.Spknox:BAAANQADCggICAABNQAECgYIBwABAAAAAA==.Spooklet:BAAANQAECgEIAQAAAA==.Spoonboy:BAAANQAECgQIBgAAAA==.',
Sq='Squirtmore:BAAANQAECgQICQAAAA==.Squirtsalot:BAAANQAECgQIBAAAAA==.',
St='Starielle:BAAANQAECgEIAQAAAA==.Stark:BAAANQADCgYICgAAAA==.Steinman:BAAANQADCggIEwAAAA==.Stemple:BAAANQAECgQICAAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAAANQAECgEIAQAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQADCgYICwAAAA==.Stubsy:BAAANQADCgQIBAAAAA==.',
Su='Sublet:BAAANQADCggIIAAAAA==.Subwayy:BAAANQAECgEIAQAAAA==.Suunshine:BAAANQAECgUIBwAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAAANQAECgMIBgAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Synfal:BAAANQAECgEIAQAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAAANQAECgEIAgAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAAANQAECgQIBQAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICgAAAA==.',
Ta='Taemire:BAAANQADCggIFAABNQAECgQIBgABAAAAAA==.Tahlia:BAAANQAECgUIBgAAAA==.Takaiya:BAAANQAECgEIAQAAAA==.Tauna:BAAANQADCgQIBAAAAA==.',
Te='Technosis:BAAANQADCggIFwAAAA==.Techuu:BAABNQAECoEXAAITAAkJQyD5BwBsAwATAAkJQyD5BwBsAwAAAA==.',
Th='Thade:BAAANQADCgEIAQABNQADCggIFQABAAAAAA==.Thatdamdruid:BAAANQAECgMIAwAAAA==.Thekhole:BAAANQADCgUIBQAAAA==.Thekrelltoss:BAAANQAECgYICgAAAA==.Thoriandis:BAAANQADCgYIBwAAAA==.',
Tj='Tjirp:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
To='Torale:BAAANQADCggICAAAAA==.Totemstout:BAAANQAECgMIBwAAAA==.Toteshadow:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Tovuk:BAAANQAECgIIAgAAAA==.',
Tr='Tranquilitee:BAAANQAECgIIAwAAAA==.Traumateam:BAAANQADCgUICgABNQADCggIEAABAAAAAA==.Trebdk:BAAANQAECgMIBAAAAA==.Treecoleos:BAAANQAECgEIAgAAAA==.Treigha:BAAANQADCggIDwABNQAECgQIBgABAAAAAA==.Tripleseven:BAAANQADCgUIBQAAAA==.',
Tw='Tweetconic:BAAANQADCgcIDQAAAA==.Tweetess:BAAANQADCgEIAQAAAA==.Twothreesix:BAAANQADCgYICwAAAA==.Twîsted:BAAANQADCggIGAAAAA==.',
Ty='Tyborel:BAAANQAECgcICwAAAA==.Tydro:BAAANQADCgYIBwAAAA==.Tyranoc:BAAANQADCgUIBQAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Us='Usedtobecool:BAAANQAECgEIAQAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQADCgYICQAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAAANQAECgMIBgAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwAAAA==.Valthalus:BAAANQADCgUICQAAAA==.Valvet:BAAANQAECgMIAwAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQADCgUIBQAAAA==.Vellarya:BAAANQADCggICAAAAA==.Velthrax:BAABNQAECoEVAAIUAAYJ5yKQGQBcAgAUAAYJ5yKQGQBcAgAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velìn:BAAANQADCgUIBQAAAA==.Velín:BAAANQAECgYICwAAAA==.',
Vi='Villeneth:BAAANQADCggIDQAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAAANQAECgUIBAAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.',
Vo='Vokk:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Vozie:BAAANQAECgYICgAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAAANQAECgYICAAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
Wa='Wackman:BAAANQAECgQIBQAAAA==.Warmfridge:BAAANQADCgYIBgAAAA==.Wartiant:BAAANQAECgUIEAAAAA==.',
Wh='Whitehall:BAAANQADCggIEwAAAA==.Wholegrain:BAAANQADCgcIDwABNQAECgQICAABAAAAAA==.',
Wi='Windhorn:BAAANQADCggIFQAAAA==.Windi:BAAANQADCgYIDAAAAA==.Wiro:BAAANQADCgUIBwAAAA==.Wirø:BAAANQADCgEIAQAAAA==.',
Wo='Wobbling:BAAANQAECgYIBwAAAA==.Wobblock:BAAANQAECgMIAwAAAA==.Wombee:BAAANQADCgQIBAAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
['Wí']='Wíiman:BAAANQAECgcIDAAAAA==.',
Xa='Xalath:BAAANQADCggICAAAAA==.',
Xe='Xeenah:BAAANQAECgUIEAAAAA==.',
Xi='Xilef:BAAANQADCggIDgAAAA==.',
Xy='Xyz:BAABNQAECoEXAAMVAAkJzR5VAgA1AwAVAAkJiR5VAgA1AwAWAAUJbxY3GACBAQAAAA==.',
Ya='Yamaka:BAABNQAECoEWAAIXAAkJnSUmAADxAwAXAAkJnSUmAADxAwAAAA==.',
Ys='Yseult:BAAANQADCggIDQAAAA==.',
Za='Zaarock:BAAANQAECgcIDQAAAA==.Zaishadow:BAAANQAECgMIAwAAAA==.Zandro:BAAANQADCgYIDQAAAA==.Zanduill:BAAANQADCggIFQAAAA==.Zanhighawen:BAAANQADCggIDgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Zayva:BAAANQADCggIIAAAAA==.',
Ze='Zeali:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.Zealthyr:BAAANQAECgEIAgAAAA==.Zere:BAAANQAECgQICAABNQAECgcIEQABAAAAAA==.Zeztuknar:BAAANQADCgEIAQAAAA==.',
Zi='Zincberg:BAAANQADCgYICwAAAA==.',
Zo='Zorbax:BAAANQAECgEIAQAAAA==.',
Zy='Zykaei:BAAANQAECgYICwAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAQAAAA==.',
['Áy']='Áylamao:BAAANQAECgIIBQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggIEgAAAA==.',
['Éh']='Éh:BAAANQAECgQIBAAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECgUIEAABAAAAAA==.Ðisciple:BAAANQAECgUIEAAAAA==.',
['Øb']='Øbiwan:BAAANQADCgYICwAAAA==.',
['ßi']='ßinchicken:BAAANQAECgEIAQAAAA==.',
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
