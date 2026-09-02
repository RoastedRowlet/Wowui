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

local lookup = {'Unknown-Unknown','Mage-Arcane','Shaman-Restoration','Druid-Restoration','DeathKnight-Blood',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abbyss:BAAANQAECgIIAgAAAA==.Abirnar:BAAANQADCggIDwAAAA==.Abramelinn:BAAANQADCgMIBQABNQADCgYICQABAAAAAA==.',
Ac='Acca:BAAANQADCgcIDQAAAA==.',
Ad='Adget:BAAANQAECgQIBAAAAA==.Adorion:BAAANQADCgYIDgAAAA==.',
Ae='Aerali:BAAANQAECgQIBAAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.Agôny:BAAANQAECgQICAAAAA==.',
Ai='Aidzboy:BAAANQADCggICQAAAA==.',
Al='Aldin:BAAANQADCgIIAgAAAA==.Alfah:BAAANQADCgQIBwAAAA==.Aliatris:BAAANQADCgcICwAAAA==.Alicia:BAAANQADCgUIBQAAAA==.Allor:BAAANQADCggIEAAAAA==.Allorpally:BAAANQAECgIIAgAAAA==.Altofmyalt:BAAANQADCgIIAgAAAA==.Aluii:BAAANQAECgUIBgAAAA==.Alyssana:BAAANQAECgMIAwAAAA==.Alyxpants:BAAANQAECgIIAgAAAA==.',
Am='Amakhozi:BAAANQADCgYIBgAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaria:BAAANQADCggIDwAAAA==.Amity:BAAANQADCgQIBAAAAA==.',
An='Aneth:BAAANQADCggICwAAAA==.Angelsfly:BAAANQADCgcICQAAAA==.Angæl:BAAANQADCgcICgAAAA==.Annallyne:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Anti:BAAANQADCgQIBAAAAA==.',
Ar='Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQADCgUICQAAAA==.Arcyandor:BAAANQADCgUIBQAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgIIAgAAAA==.',
As='Ashmear:BAAANQADCgcIDAAAAA==.Astalon:BAAANQABCgQIBQAAAA==.',
At='Athreos:BAAANQAECgEIAQAAAA==.Atüned:BAAANQAECgMIAwAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAAANQAECgMIBgAAAA==.',
Av='Avelane:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Ay='Ayahuasca:BAAANQADCggICAAAAA==.',
Az='Azubasaurus:BAAANQAECgUIBgAAAA==.',
Ba='Baggageho:BAAANQADCgEIAQAAAA==.Balan:BAAANQAECgIIAgAAAA==.Balerion:BAAANQADCgYIDgAAAA==.Barback:BAAANQABCgQIBwAAAA==.Barkstard:BAAANQAECgQIBgAAAA==.Barleyalive:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQADCgYIBgAAAA==.',
Be='Belarii:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Bellonae:BAAANQADCgcIBwAAAA==.Belmenth:BAAANQADCgEIAQAAAA==.Bendecida:BAAANQADCgYICQAAAA==.Benington:BAAANQADCggICAAAAA==.Benn:BAAANQAECggIEwAAAA==.',
Bh='Bhyta:BAAANQAECgQIBQAAAA==.',
Bi='Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAAANQAECgQIBQAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAAANQAECgQIBQAAAA==.Blaumeux:BAAANQADCgYIBgAAAA==.Blazine:BAAANQABCgEIAQAAAA==.Bliss:BAAANQADCgcIDQAAAA==.Bloodaddict:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Bluesham:BAAANQADCgcIDQAAAA==.',
Bo='Bocko:BAAANQADCggIDwAAAA==.Bogblant:BAAANQAECgEIAgAAAA==.Bowsbfrhoez:BAAANQAECgMIBgAAAA==.',
Br='Branbeard:BAAANQAECgEIAQAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.',
Bu='Bubblëøseven:BAAANQAECgEIAQAAAA==.Bundie:BAAANQAECgMIAwAAAA==.Burdhammer:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
['Bë']='Bëllädonna:BAAANQADCgYIDgAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoEXAAICAAgJ7BqiHABdAgACAAgJ7BqiHABdAgAAAA==.Cardoney:BAAANQAECgEIAQAAAA==.Cariah:BAAANQAECgMIAwAAAA==.Catashax:BAAANQADCgYICgAAAA==.',
Cd='Cdkit:BAAANQAECgMIBgAAAA==.',
Ce='Celestè:BAAANQADCgcICQAAAA==.',
Ch='Chasstise:BAAANQADCgcIEAAAAA==.Chazze:BAAANQADCgEIAQAAAA==.Cheggery:BAAANQADCgQICAAAAA==.Chirp:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Chirpe:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.Chubbypope:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.',
Ci='Cindrick:BAAANQAECgYIBgABNQAFFAEIAQABAAAAAA==.',
Cl='Clessta:BAAANQADCgcIDQAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAAANQADCggIDgAAAA==.Clownworld:BAAANQADCgcIBQAAAA==.',
Co='Coffêê:BAAANQAECgQIBAAAAA==.Coldbringer:BAAANQADCgYIBgAAAA==.Coldpalmer:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Coleostrasz:BAAANQADCgEIAQAAAA==.Conkoura:BAAANQAECgEIAQAAAA==.Corastrasza:BAAANQADCgUIBwAAAA==.',
Cr='Cresentmoon:BAAANQADCgUICgAAAA==.Crimsonmage:BAAANQADCgUICAAAAA==.',
Cu='Cursedlight:BAAANQAECgEIAQAAAA==.',
Cy='Cynnal:BAAANQADCgYIBgAAAA==.',
Da='Dadoinkle:BAAANQADCgIIAgAAAA==.Dahj:BAAANQADCgcIDQAAAA==.Dalanar:BAAANQADCgYIBgAAAA==.Danathjo:BAAANQADCgYIBgAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAAANQAECgEIAQAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAAANQAECgIIAgAAAA==.Debris:BAAANQADCggICgAAAA==.Dedmongrel:BAAANQADCggIDgAAAA==.Delây:BAAANQADCgYIDAAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Dengar:BAAANQADCggICAAAAA==.Desyphium:BAAANQAECgcICwAAAA==.Deviltrigger:BAAANQADCgQIBAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQADCgUICgAAAA==.Dex:BAABNQAECoEcAAIDAAgJayJcAgArAwADAAgJayJcAgArAwAAAA==.',
Di='Direforge:BAAANQADCgcIDQAAAA==.Disreputable:BAAANQADCgUIBQAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQADCgYIBwAAAA==.Draemon:BAAANQAECgQICgAAAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAAANQAECgcIDQAAAA==.Drannith:BAAANQADCgUIAQAAAA==.Drasston:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Drastiricka:BAAANQADCgUIBQAAAA==.Dreadlocksta:BAAANQADCgMIAwAAAA==.Dreamer:BAAANQADCgEIAgAAAA==.Drinkwater:BAAANQAECgEIAQAAAA==.Drucaila:BAAANQADCgYIBgAAAA==.Druidss:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgQIBwAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQADCggIDgAAAA==.',
['Dî']='Dîv:BAAANQAECgYICQAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eatduhpupu:BAAANQADCgYIBgABNQADCggICQABAAAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Elfhelm:BAAANQADCgcIDQAAAA==.Elipsis:BAAANQADCgYIBgAAAA==.Ellisinor:BAAANQADCgUIEgAAAA==.Elured:BAAANQADCggIDgAAAA==.',
Em='Embermist:BAAANQADCgcIBwAAAA==.Emliy:BAAANQAECgMIBAAAAA==.Emogirl:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAAANQAECgIIAgAAAA==.',
Ep='Ephesian:BAAANQADCgcICgAAAA==.',
Er='Erobas:BAAANQADCggIHgAAAA==.Erodan:BAAANQAECgIIAgAAAA==.',
Es='Esserian:BAAANQADCgcIDQAAAA==.Estarae:BAAANQAECgEIAgAAAA==.Esthane:BAAANQADCggICAAAAA==.',
Eu='Euphuzadan:BAAANQAECgQIBAAAAA==.',
Ev='Everhealer:BAAANQAECgQICAAAAA==.Evillumber:BAAANQADCgUICwAAAA==.',
Ex='Exiledemon:BAAANQAECgMIAwAAAA==.',
Ey='Eyéspy:BAAANQADCggIDgAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Fauvm:BAAANQADCggIGQAAAA==.',
Fe='Feanassa:BAAANQADCgIIAgAAAA==.Fearwood:BAAANQADCgYIBgAAAA==.Felfeet:BAAANQAECgQIBQAAAA==.Fenrisfox:BAAANQADCggICgAAAA==.Ferrousman:BAAANQADCgcICwAAAA==.',
Fi='Fishing:BAAANQAECgQIBQAAAA==.',
Fl='Flaviousqt:BAAANQADCgYICgAAAA==.Flezappezix:BAAANQAECgcIDQAAAA==.Fluffpriest:BAAANQAECgEIAQAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAAANQAFFAIIAgAAAA==.',
Fr='Fragmented:BAAANQADCgcICQAAAA==.Fragments:BAAANQABCgIIAgABNQADCgcICQABAAAAAA==.Frair:BAABNQAECoEWAAIEAAcJUwi7DAB1AQAEAAcJUwi7DAB1AQAAAA==.Frostmagee:BAAANQADCgUICwAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAAANQADCgYICgAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Garthurn:BAAANQADCgIIAgAAAA==.Gaskull:BAAANQADCgUICwAAAA==.Gaybacon:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.',
Gh='Ghostsaber:BAAANQADCgcIDAAAAA==.',
Gi='Giddykitty:BAAANQADCgQIBwAAAA==.Gimballock:BAAANQADCgYIDgAAAA==.',
Go='Goatvier:BAAANQAECgcICwAAAA==.Goblinator:BAAANQADCgcIDgAAAA==.Goodenia:BAAANQADCgQIBAAAAA==.Googoo:BAAANQAECgEIAQAAAA==.Gorhowl:BAAANQAECgIIAgAAAA==.Gorli:BAAANQADCgYICgAAAA==.Gottolurveit:BAAANQADCgcIDAAAAA==.',
Gr='Gracela:BAAANQADCgYICAAAAA==.Grantuss:BAAANQAECgIIAgAAAA==.Gravadin:BAAANQAECgQIBAAAAA==.Great:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Gretchin:BAAANQAECgEIAQAAAA==.',
Gu='Guinness:BAAANQADCgIIAgAAAA==.Gunji:BAAANQADCgIIAgAAAA==.',
['Gä']='Gändalf:BAAANQAECgEIAQAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesblood:BAAANQAECgcIDQAAAA==.Hakiheal:BAAANQAECgIIAgAAAA==.Hakzert:BAAANQAECgcIDQAAAA==.Harex:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Harlon:BAAANQADCgMIBAAAAA==.Haylø:BAAANQADCgYIBgAAAA==.',
He='Healdewin:BAAANQADCgUICgAAAA==.Hellsgate:BAAANQADCgQIBAAAAA==.Hellshunter:BAAANQAECgEIAQAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgIIAgAAAA==.Hetzlock:BAAANQADCgYIBgAAAA==.Hexalock:BAAANQADCgYIBgAAAA==.Hexdh:BAAANQADCgIIAgAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexpriest:BAAANQAECgQIBAAAAA==.Hezaq:BAAANQADCgcIDQAAAA==.',
Ho='Hollowvoice:BAAANQAECgEIAQAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAAANQAECgIIAgAAAA==.Horacio:BAAANQADCgcIDQAAAA==.',
Hu='Humin:BAAANQADCgEIAQAAAA==.Huntér:BAAANQADCggICQAAAA==.',
['Hù']='Hùntrèss:BAAANQADCgYIDAAAAA==.',
Ic='Icdedpple:BAAANQADCggIDQAAAA==.Icymama:BAAANQADCgQIBwAAAA==.',
Id='Idevouryou:BAAANQADCgYIDAAAAA==.',
Im='Imchirp:BAAANQADCgUICAABNQADCgcIDQABAAAAAA==.Imicedup:BAAANQADCgYIBgAAAA==.Impblaster:BAAANQAECgEIAQAAAA==.',
In='Inarius:BAAANQADCggICgAAAA==.Incompetent:BAAANQADCgUICgAAAA==.Indriná:BAAANQADCgIIAgAAAA==.Inflictor:BAAANQAECgEIAQAAAA==.Insanenachos:BAAANQADCggICAAAAA==.Inumbra:BAAANQADCgIIAgAAAA==.',
Ir='Ironknee:BAAANQAECgIIAgAAAA==.',
It='Ithareos:BAAANQADCgcIDAAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.',
Iz='Izulia:BAAANQAECgIIAgAAAA==.',
Ja='Jabiraka:BAAANQADCgcICAAAAA==.Jackiexx:BAAANQAECgIIBAAAAA==.Jakestanater:BAAANQADCgYICwAAAA==.Jassel:BAAANQADCgUICgAAAA==.Jazmeine:BAAANQADCgIIAgAAAA==.',
Je='Jestër:BAAANQADCgIIAgABNQADCgQIBgABAAAAAA==.',
Ji='Jimjam:BAAANQADCgcIDQAAAA==.Jinx:BAAANQAECgEIAgAAAA==.',
Jj='Jjester:BAAANQADCgQIBgAAAA==.',
Jl='Jlaby:BAAANQAECgEIAQAAAA==.',
Jp='Jpxhunter:BAAANQADCggICAAAAA==.',
Ju='Juicei:BAAANQAECgMIAwAAAA==.',
Ka='Kagéslammer:BAAANQADCgcIDQAAAA==.Kaiser:BAAANQADCggIDwAAAA==.Kanundrum:BAAANQADCgcIDQAAAA==.Karaxynn:BAAANQAECgQIBQAAAA==.Kaulder:BAAANQADCgIIBAAAAA==.',
Ke='Kebabyy:BAAANQAECgEIAgAAAA==.Keheia:BAAANQADCgYIBwAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgUIBQAAAA==.',
Kh='Khacey:BAAANQADCgcIDQAAAA==.Khodii:BAAANQADCgUIBQAAAA==.Khoho:BAAANQADCgYIBgAAAA==.Khrøne:BAAANQAECgQIBAAAAA==.Khursed:BAAANQADCgYIBgAAAA==.',
Ki='Killsaw:BAAANQABCgIIAgAAAA==.Kity:BAAANQADCgcIAgAAAA==.',
Kn='Knail:BAAANQADCgYIDAAAAA==.Knickyou:BAAANQADCgYICAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQADCgYIBgAAAA==.',
Kr='Kreuzschlitz:BAAANQADCgcIBwAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krippg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Kripwar:BAAANQAECgMIAwAAAA==.Krizkin:BAAANQADCgYIEAAAAA==.Krugg:BAAANQADCgcICgAAAA==.',
Ku='Kungpao:BAAANQADCgYICAAAAA==.',
Ky='Kynhark:BAAANQADCgIIBQAAAA==.Kyoudo:BAAANQAECgEIAgAAAA==.',
La='Laurél:BAAANQAECgEIAQAAAA==.Layonpaws:BAAANQAECgUICQAAAA==.',
Le='Lecked:BAAANQAECgEIAQAAAA==.Leighandra:BAAANQADCgUICgAAAA==.Lemures:BAAANQADCggIBwAAAA==.Leonà:BAAANQABCgIIBAAAAA==.',
Li='Liebspawn:BAAANQADCgQICAAAAA==.Linarisa:BAAANQAECgEIAQAAAA==.Liquidate:BAAANQAECgEIAQAAAA==.Litori:BAAANQAECgMIAwAAAA==.',
Ll='Llux:BAAANQADCgIIAgAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAAANQAECgQICAAAAA==.Looksmaxxor:BAAANQADCgYIBgAAAA==.Loryn:BAAANQAECgEIAQAAAA==.',
Lu='Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQADCgYICQAAAA==.Lunavale:BAAANQADCgcIBwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQAAAA==.Lytemup:BAAANQADCgYIBgAAAA==.',
Ma='Maenir:BAAANQADCgcIBwAAAA==.Magnytize:BAAANQAECgQIAwAAAA==.Magoose:BAAANQAECgEIAQAAAA==.Mags:BAAANQAECgYIBwAAAA==.Majinboom:BAAANQADCgYIBgAAAA==.Maldred:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Maldreds:BAAANQAECgMIBAAAAA==.Manicmonday:BAAANQADCgUIBQAAAA==.Marsie:BAAANQAECgEIAQAAAA==.Mashex:BAAANQADCggIDwAAAA==.',
Me='Medieval:BAAANQAECgEIAQAAAA==.Mediyah:BAAANQADCgUICgAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.Meljira:BAAANQADCgUIBQAAAA==.Melonyummy:BAAANQAECgcIDQAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQADCgYIEAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milzey:BAAANQAECgEIAQAAAA==.Mindweaver:BAAANQADCgYICwAAAA==.Miradin:BAAANQADCgYICQAAAA==.Mirv:BAAANQAECgcICgAAAA==.Misspickles:BAAANQAECgIIAgAAAA==.Mistakoji:BAAANQAECgIIAgAAAA==.',
Mo='Mogwii:BAAANQAECggIBwAAAA==.Moit:BAAANQADCgQIBAAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQADCgYIBgAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monononoke:BAAANQADCgEIAQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Morella:BAAANQAECgEIAQAAAA==.',
Mu='Munta:BAAANQADCgYIDwAAAA==.Munter:BAAANQAECgQIBAAAAA==.Mursha:BAAANQADCgcIDQAAAA==.',
['Mï']='Mïkarika:BAAANQADCgEIAQAAAA==.',
Na='Naalaxii:BAAANQAECgQIBAAAAA==.Naero:BAAANQADCgUIBwAAAA==.Nalfeiin:BAAANQAECgEIAQAAAA==.Narnardk:BAAANQAECgYICQAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrstorm:BAAANQAECgEIAgAAAA==.Naturised:BAAANQADCgcIDQAAAA==.Nawe:BAAANQADCgQIBAAAAA==.',
Ne='Neflyn:BAAANQADCgcIDAAAAA==.Nemmystrata:BAAANQADCgYICwAAAA==.Nessaandra:BAAANQAECgIIAgAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgQIBgAAAA==.',
Ni='Niftage:BAAANQADCgQIBAABNQADCgcIDQABAAAAAA==.Niftana:BAAANQADCgcIDQAAAA==.Nimirie:BAAANQADCggIDwAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgIIAgAAAA==.Nokpaladin:BAAANQADCgQIBQABNQAECgEIAQABAAAAAA==.Nokshaman:BAAANQAECgEIAQAAAA==.Noxtard:BAAANQADCggIEAAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQADCgYIDAAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCgUICAAAAA==.',
Ok='Okazi:BAAANQAECgEIAQAAAA==.',
Ol='Olafuga:BAAANQAECgEIAgAAAA==.',
Oo='Ookolok:BAAANQADCgMIAwAAAA==.Oompaloompa:BAAANQABCgQIBAAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCgcIDAAAAA==.Ormal:BAAANQADCgUIBQAAAA==.',
Os='Osmess:BAAANQAECgUICQABNQAFFAIIAgABAAAAAA==.Osmology:BAAANQAFFAIIAgAAAA==.',
Oz='Ozzietree:BAAANQAECgcIDQAAAA==.',
Pa='Paddingtonn:BAAANQADCgYIEQAAAA==.Pandachì:BAAANQAECgMIAwAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Parallaxia:BAAANQAECgYICgAAAA==.Paulmedic:BAAANQAECgIIAgAAAA==.',
Pb='Pbjellytime:BAAANQADCgQIBAAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQADCgUICgAAAA==.',
Ph='Phoènix:BAAANQADCggIDgAAAA==.',
Pi='Pikyx:BAAANQADCggIDwAAAA==.Pinkrock:BAAANQAECgIIAgAAAA==.',
Pl='Playboicarti:BAAANQAECgYIBwAAAA==.Plopperoo:BAAANQADCgcIDAAAAA==.',
Po='Pocaface:BAAANQAECgEIAQAAAA==.Pogmourne:BAABNQAECoEWAAIFAAcJvRpWDAArAgAFAAcJvRpWDAArAgAAAA==.Polyform:BAAANQAECgUICQAAAA==.',
Pr='Preserved:BAAANQADCggIDwAAAA==.Priestsen:BAAANQADCgQIBAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgEIAQAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Puru:BAAANQADCgYICAAAAA==.',
Py='Pyrhus:BAAANQADCggIDgAAAA==.',
['Pâ']='Pâkerious:BAAANQADCgYIEAAAAA==.',
Qi='Qicacid:BAAANQAFFAEIAQAAAA==.',
Ra='Rafedrood:BAAANQADCggICAAAAA==.Rafemonk:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.Rafepally:BAAANQAECgIIAgAAAA==.Raiigun:BAAANQAECgIIAgAAAA==.Rakutina:BAAANQADCgUIBgAAAA==.Rastianklin:BAAANQADCgUICgAAAA==.Ratbro:BAAANQADCgcIDAAAAA==.Rawrbewbz:BAAANQAECgQIBQAAAA==.Rayburd:BAAANQAECgIIAgAAAA==.Raypejeet:BAAANQAECgcIDQAAAA==.Raziiel:BAAANQADCgMIAwAAAA==.',
Rb='Rbed:BAAANQAECgQIBgAAAA==.',
Re='Realhuman:BAAANQAECgEIAQAAAA==.Recharge:BAAANQADCgYIBgAAAA==.Relinna:BAAANQADCgUICQAAAA==.Remdelacrem:BAAANQAECgEIAQABNQAECgYIBwABAAAAAA==.Renegade:BAAANQADCggICAAAAA==.Resly:BAAANQAECgYICAAAAA==.Reulna:BAAANQADCgIIAgAAAA==.',
Rh='Rhodie:BAAANQADCggIDwAAAA==.',
Ri='Ricuid:BAAANQADCgcIDQAAAA==.Ridemption:BAAANQADCgYIBgAAAA==.Rifkin:BAAANQADCgUIBQAAAA==.Rigamautist:BAAANQADCgcIDQAAAA==.Rightguy:BAAANQADCgMIAwAAAA==.',
Ro='Roadkill:BAAANQADCgUICQAAAA==.Roots:BAAANQADCgYIEAAAAA==.Rotelle:BAAANQADCgMIAwAAAA==.Rottenalbo:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Ru='Rustyaslock:BAAANQAECgEIAgAAAA==.',
['Rè']='Rèmorseléss:BAAANQADCggICAAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Saladin:BAAANQADCgUIBwAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQABCgIIAQAAAA==.Samoid:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Sanguiniüs:BAAANQAECgQIBAAAAA==.Santhea:BAAANQADCgYIBgAAAA==.Sarixz:BAAANQAECgQIBAAAAA==.Sarzyb:BAAANQAECgIIAgAAAA==.Sashka:BAAANQAECgQIBAAAAA==.Satsuy:BAAANQAECgIIAQAAAA==.',
Sc='Scott:BAAANQADCggIFQABNQAECgMIBgABAAAAAA==.Scrubturkey:BAAANQADCgYIBgAAAA==.',
Se='Seamonology:BAAANQAECgYICwAAAA==.Seravael:BAAANQADCgYIBwAAAA==.',
Sh='Shadowvoice:BAAANQAECgEIAQAAAA==.Shallan:BAAANQAECgUICAAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Shieldzu:BAAANQADCgUIBQAAAA==.Shindig:BAAANQAECgEIAgAAAA==.Shlappy:BAABNQAECoEcAAIFAAgJ/RWvCgBPAgAFAAgJ/RWvCgBPAgAAAA==.',
Si='Silversham:BAAANQADCggIDQAAAA==.Silversnow:BAAANQADCgEIAQAAAA==.Silverstaria:BAAANQADCgYIDAAAAA==.',
Sk='Skeld:BAAANQADCgQIBAAAAA==.Skiddy:BAAANQAFFAIIAgAAAA==.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skiphunter:BAAANQADCgIIBAAAAA==.Skrug:BAAANQADCgYIBwAAAA==.',
Sl='Slysham:BAAANQAECgEIAQAAAA==.',
Sm='Smeevil:BAAANQADCggIDgAAAA==.Smellyfridge:BAAANQADCgQICAAAAA==.',
Sn='Sneeds:BAABNQAECoEiAAIFAAkJPh9iBAD5AgAFAAkJPh9iBAD5AgAAAA==.Snowhail:BAAANQADCggICAAAAA==.',
So='Soaringsky:BAAANQAECgYICQAAAA==.Softfireball:BAAANQADCgMIBAAAAA==.Sopheeaa:BAAANQAECgIIAgAAAA==.Soria:BAAANQADCggICgAAAA==.Soulblessed:BAAANQAECgQIBAAAAA==.',
Sp='Sparkychops:BAAANQADCgcIDgAAAA==.Spaztik:BAAANQAECggIBAAAAA==.Spectretwo:BAAANQADCgYICwAAAA==.Spooklet:BAAANQAECgEIAQAAAA==.Spoonboy:BAAANQAECgQIBAAAAA==.',
Sq='Squirtmore:BAAANQAECgQIBAAAAA==.',
St='Starielle:BAAANQADCgcIDAAAAA==.Stark:BAAANQADCgUIBQAAAA==.Steinman:BAAANQADCgcIDAAAAA==.Stemple:BAAANQAECgEIAQAAAA==.Stormblessed:BAAANQADCggIDwAAAA==.Stormfur:BAAANQADCgYIBgAAAA==.Stormyshadow:BAAANQADCgUIBQAAAA==.Stubsy:BAAANQADCgQIBAAAAA==.',
Su='Sublet:BAAANQADCgYIEAAAAA==.Subwayy:BAAANQADCgUIBQAAAA==.Suunshine:BAAANQAECgEIAgAAAA==.',
Sw='Swampÿ:BAAANQADCgMIBAAAAA==.Swordriel:BAAANQAECgMIAwAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAAANQAECgEIAQAAAA==.Syrezz:BAAANQADCgIIAgAAAA==.',
Sz='Szeras:BAAANQAECgEIAQAAAA==.',
['Sö']='Söurcream:BAAANQADCgUIBQAAAA==.',
Ta='Taemire:BAAANQADCgYIDAABNQAECgEIAgABAAAAAA==.Tahlia:BAAANQAECgEIAQAAAA==.Takaiya:BAAANQADCgcICQAAAA==.Tauna:BAAANQADCgQIBAAAAA==.',
Te='Technosis:BAAANQADCgYIDQAAAA==.Techuu:BAAANQAECgcIDQAAAA==.',
Th='Thade:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.Thatdamdruid:BAAANQADCggIDwAAAA==.Thekhole:BAAANQADCgUIBQAAAA==.Thekrelltoss:BAAANQAECgQIBAAAAA==.',
To='Totemstout:BAAANQAECgMIBgAAAA==.Toteshadow:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Tovuk:BAAANQADCggIEAAAAA==.',
Tr='Tranquilitee:BAAANQAECgEIAQAAAA==.Traumateam:BAAANQADCgUIBQAAAA==.Trebdk:BAAANQAECgIIAgAAAA==.Treecoleos:BAAANQADCgYIBwAAAA==.Treigha:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Tripleseven:BAAANQADCgUIBQAAAA==.',
Tw='Tweetconic:BAAANQADCgUIBgAAAA==.Tweetess:BAAANQADCgEIAQAAAA==.Twothreesix:BAAANQADCgYICwAAAA==.Twîsted:BAAANQADCggIEAAAAA==.',
Ty='Tyborel:BAAANQAECgQIBAAAAA==.Tydro:BAAANQADCgYIBwAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Us='Usedtobecool:BAAANQAECgEIAQAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQADCgIIAwAAAA==.Vaenir:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Valadria:BAAANQAECgMIAwAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgQIAwAAAA==.Valthalus:BAAANQADCgUICQAAAA==.Valvet:BAAANQADCgYIBgAAAA==.Vanirr:BAAANQADCgcIDgAAAA==.',
Ve='Velthrax:BAAANQAECgQICgAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velín:BAAANQAECgQIBQAAAA==.',
Vi='Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAAANQADCggIFQAAAA==.Vividèlity:BAAANQADCggICAAAAA==.',
Vo='Vokk:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Vozie:BAAANQAECgQIBAAAAA==.',
Vr='Vrothraxia:BAAANQAECgEIAQAAAA==.',
Vu='Vulcanos:BAAANQAECgIIAgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
Wa='Wackman:BAAANQADCgUIBgAAAA==.Wartiant:BAAANQAECgMIBgAAAA==.',
Wh='Whitehall:BAAANQADCgYICwAAAA==.',
Wi='Windhorn:BAAANQADCgcIDQAAAA==.Windi:BAAANQADCgQIBgAAAA==.Wiro:BAAANQADCgUIBQAAAA==.',
Wo='Wobbling:BAAANQAECgYIBgAAAA==.Wombee:BAAANQADCgQIBAAAAA==.',
['Wí']='Wíiman:BAAANQAECgUIBQAAAA==.',
Xe='Xeenah:BAAANQAECgMIBgAAAA==.Xenobi:BAAANQADCggICAAAAA==.',
Xi='Xilef:BAAANQADCgQIBgAAAA==.',
Xy='Xyz:BAAANQAECgcIDQAAAA==.',
Ya='Yamaka:BAAANQAECgcIDAAAAA==.',
Ys='Yseult:BAAANQADCgYIBgAAAA==.',
Za='Zaarock:BAAANQAECgUIBgAAAA==.Zandro:BAAANQADCgUIBwAAAA==.Zanduill:BAAANQADCggIDwAAAA==.Zanhighawen:BAAANQADCgYIBgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zayva:BAAANQADCgYIEAAAAA==.',
Ze='Zeali:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Zealthyr:BAAANQAECgEIAQAAAA==.Zere:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.Zeztuknar:BAAANQADCgEIAQAAAA==.',
Zi='Zincberg:BAAANQADCgUIBQAAAA==.',
Zo='Zorbax:BAAANQADCgcICAAAAA==.',
Zy='Zykaei:BAAANQAECgQIBQAAAA==.',
Zz='Zzeldris:BAAANQAECgQIBAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAQAAAA==.',
['Áy']='Áylamao:BAAANQAECgEIAQAAAA==.',
['Æc']='Æclipsè:BAAANQADCgYIDgAAAA==.',
['Éh']='Éh:BAAANQADCggICQAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECgMIBgABAAAAAA==.Ðisciple:BAAANQAECgMIBgAAAA==.',
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
