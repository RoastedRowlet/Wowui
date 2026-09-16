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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Holy','Warrior-Arms','Shaman-Elemental','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Survival','Evoker-Devastation','DemonHunter-Havoc','Mage-Arcane','Mage-Frost','Evoker-Preservation','DemonHunter-Devourer','Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','Druid-Guardian','Hunter-BeastMastery','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Paladin-Protection','DeathKnight-Blood','Rogue-Assassination','Warrior-Protection','Hunter-Marksmanship','Shaman-Restoration','Rogue-Subtlety','Shaman-Enhancement',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aadonis:BAAANQADCgIIAwAAAA==.Aanubus:BAAANQADCggIBwABNQADCggIEAABAAAAAA==.Aarek:BAAANQABCgYIBgABNQAECgIIAgABAAAAAA==.',
Ab='Abyssalmaw:BAAANQAECgUICwAAAA==.',
Ac='Achillesqt:BAAANQADCgIIAgAAAA==.Acionna:BAAANQADCggIHAAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgYIBQAAAA==.Adrenalin:BAAANQAECgUICQAAAA==.',
Ae='Aedros:BAAANQAECgMIBAAAAA==.Aegis:BAAANQADCgIIAgAAAA==.Aellan:BAAANQAECgUIDQAAAA==.',
Af='Afflexion:BAAANQADCggICAAAAA==.',
Ag='Agonier:BAAANQADCgUIBgAAAA==.',
Aj='Ajira:BAAANQADCgcIDwAAAA==.',
Ak='Akiaki:BAAANQAECgEIAgAAAA==.',
Al='Aladk:BAAANQAECgcIEwAAAA==.Alafus:BAAANQAECgQIBQABNQAECgcIEwABAAAAAA==.Alaldras:BAAANQADCgQIBAAAAA==.Alalock:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.Alaria:BAAANQAECgUICQABNQAECggIFwACAA8cAA==.Alarian:BAAANQAECgcIEAAAAA==.Aldai:BAAANQAECgIIAgAAAA==.Alendros:BAAANQAECgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAABNQAECoEZAAIDAAgJBRj+HgBDAgADAAgJBRj+HgBDAgAAAA==.Alista:BAAANQADCgIIAgAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAAANQAECgUICQAAAA==.Allythriea:BAAANQADCgcIEwAAAA==.Althen:BAAANQADCggICAAAAA==.',
Am='Ambertwo:BAAANQAECgIIAgAAAA==.Amitheria:BAAANQAECgQIBgAAAA==.',
An='Andreb:BAAANQAECgMIBgAAAA==.Andromyda:BAAANQADCgcIEwAAAA==.Angelofnite:BAAANQADCgcIEwAAAA==.Angelofpower:BAAANQADCgYIBgAAAA==.Angrychicken:BAAANQADCgUIBQAAAA==.Ankh:BAAANQAECgUICAAAAA==.Antopanto:BAAANQAECgQICAAAAA==.Anubiset:BAAANQADCgUIBQAAAA==.',
Ar='Aralia:BAAANQAECgIIAgAAAA==.Arasmina:BAABNQAECoEZAAIEAAgJMiViBQBnAwAEAAgJMiViBQBnAwAAAA==.Arcanystra:BAAANQADCgcIEQAAAA==.Arcathal:BAAANQAECgcIEQAAAA==.Arcshottx:BAAANQAECgUICQAAAA==.Arliis:BAAANQAECgYIDAAAAA==.Arniy:BAAANQADCgYIDQABNQAECggIFwACAA8cAA==.Artey:BAAANQAECgYICgAAAA==.',
As='Ascot:BAAANQADCgYIBwABNQAECgUICgABAAAAAA==.Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAAANQAECgQIBgAAAA==.Asyluun:BAAANQAECgIIAgAAAA==.',
At='Atorvas:BAAANQADCgMIAwAAAA==.',
Au='Auchioane:BAAANQAECgQICAAAAA==.Aurelyia:BAAANQAECgIIAgAAAA==.',
Aw='Awakenimg:BAAANQADCgEIAQAAAA==.',
Az='Azador:BAAANQAECgMIBgAAAA==.Azael:BAAANQAECgQIBAAAAA==.Azarion:BAAANQADCgEIAQAAAA==.Azayzel:BAAANQADCgYIBgAAAA==.Azemm:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.Azza:BAAANQADCgcIBwAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAAANQAECgUICwAAAA==.Balahara:BAAANQADCgYIBgAAAA==.Balfor:BAAANQAECgUIDQAAAA==.Bandarpallie:BAAANQAECgEIAQAAAA==.Bara:BAAANQABCgMIAwAAAA==.Battlepope:BAAANQADCgIIAgAAAA==.Baynage:BAAANQAECgYIBgAAAA==.',
Be='Beastah:BAAANQADCgUICAAAAA==.Beauxmax:BAAANQADCgYIBgAAAA==.Beefkakes:BAAANQADCggIEQAAAA==.Belest:BAAANQAECgEIAgAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQADCgcICQAAAA==.Bellaros:BAAANQAECgQIBgAAAA==.Belè:BAAANQAECgYIEAAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgIIAwAAAA==.',
Bi='Biders:BAAANQADCgEIAQAAAA==.Bigarchrules:BAAANQAECgEIAQAAAA==.Bigbanana:BAAANQAECgUICgAAAA==.Bigdaddy:BAABNQAECoEYAAIFAAgJWRP6RgAYAgAFAAgJWRP6RgAYAgAAAA==.Bigole:BAAANQAECgUIBQAAAA==.Bigsecksi:BAAANQAECgMIAwAAAA==.Bilbearbagns:BAAANQAECgEIAQAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQADCggIDwAAAA==.Binkei:BAAANQAECgUIAwAAAA==.',
Bl='Blacksky:BAAANQAECgEIAQAAAA==.Blade:BAAANQAECgUICQAAAA==.Blastette:BAAANQADCgYIFAAAAA==.Blayze:BAAANQAECgQIDAAAAA==.Bloodclaw:BAAANQABCgUIBQAAAA==.Bloodgimp:BAAANQAECgQICAAAAA==.Bloodlust:BAAANQAECgcIDQAAAA==.Bloodslay:BAAANQAECgUIDAAAAA==.Bloodtank:BAAANQADCgYIBgAAAA==.Bluebrood:BAAANQAECgEIAQAAAA==.',
Bo='Boenarrow:BAAANQADCggIDAAAAA==.Bojack:BAAANQAECgUIBgAAAA==.Bombshot:BAAANQAECgEIAQAAAA==.Boomdeeznutz:BAAANQADCgUICwAAAA==.Boomkinbill:BAAANQADCgEIAQAAAA==.Botmage:BAAANQAECgMIBgAAAA==.Bovinei:BAAANQAECgEIAQAAAA==.',
Br='Brackk:BAAANQADCgYIBgAAAA==.Braedaevia:BAAANQAECgcICwAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Brawlzdeep:BAAANQADCgQIBAAAAA==.Breldyr:BAAANQAECgYIDgAAAA==.Bronnir:BAAANQADCgYICAAAAA==.Brotis:BAAANQADCggIDwAAAA==.Brylen:BAABNQAFFIERAAIGAAcJ6CEYAADXAgAGAAcJ6CEYAADXAgAAAA==.',
Bu='Bubblerat:BAAANQADCgcIBwAAAA==.Bullus:BAAANQAECgEIAQAAAA==.Buntz:BAABNQAECoEZAAIFAAgJkCRdEQA8AwAFAAgJkCRdEQA8AwAAAA==.',
Ca='Caain:BAAANQAECgQIBAAAAA==.Caalypso:BAAANQAECgYIEgAAAA==.Caileron:BAAANQAECgIIAwAAAA==.Cakesnpies:BAAANQAECgYICgAAAA==.Callamedic:BAAANQADCggIBwABNQADCggIEAABAAAAAA==.Callofdeath:BAAANQADCgYICAAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Carb:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.Cashehm:BAAANQADCgcIEQAAAA==.Caströ:BAAANQAECgYIDgAAAA==.',
Ce='Cecilbgnome:BAAANQADCgYIAgAAAA==.Celad:BAAANQAECgYICwAAAA==.Cenedra:BAAANQAECgYICgAAAA==.',
Ch='Chaihard:BAAANQADCgUIBQAAAA==.Cheesenonion:BAAANQADCgYICwABNQAECgQIDQABAAAAAA==.Chocolates:BAAANQADCgIIAgAAAA==.Chromitez:BAAANQAECgYICwAAAA==.Chroren:BAAANQAECgYIDAAAAA==.Chubberz:BAAANQADCggICgABNQAECgYICgABAAAAAA==.Churlish:BAAANQAECgYIDQAAAA==.',
Cl='Claptothetop:BAAANQAECgQIBAAAAA==.Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAAANQAECgQICAAAAA==.Cllu:BAAANQAECgYIBgAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Colourzz:BAAANQABCgIIAgAAAA==.Conflict:BAAANQADCgMIBAAAAA==.Coobs:BAAANQADCgYIBgAAAA==.Corepia:BAAANQAECgQIBAAAAA==.Cozymonday:BAAANQAECgQIDwAAAA==.',
Cr='Cramberly:BAAANQAECgQIBQAAAA==.Crayzdruid:BAAANQADCgQIBAAAAA==.Crikeys:BAAANQADCgQIBwAAAA==.Crispynips:BAAANQADCggIFQAAAA==.Cristeria:BAEANQADCgEIAQAAAA==.Crnreaper:BAAANQAECgEIAQAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Cu='Custodes:BAAANQADCgYIDAAAAA==.',
Da='Dabita:BAAANQAECgQIEgAAAA==.Daewong:BAABNQAECoEXAAMCAAgJDxw0CACIAgACAAgJDxw0CACIAgAHAAEJuQPeOwAyAAAAAA==.Dagami:BAAANQADCggIFgAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQADCgcIGQAAAA==.Dajango:BAAANQAECgUICQAAAA==.Daknar:BAAANQAECgYICgAAAA==.Dalenvoidy:BAAANQADCgcIFgAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dankharx:BAAANQABCgQIBgAAAA==.Darkelas:BAAANQADCggICAAAAA==.Darknessbull:BAAANQAECgYIEAAAAA==.Daronn:BAAANQAECgYICwAAAA==.Darthas:BAAANQAECgIIAgAAAA==.Dashhunt:BAAANQAECgUIDQAAAA==.Dashmagic:BAAANQADCgUIBQABNQAECgUIDQABAAAAAA==.Davy:BAAANQAECgYIEQAAAQ==.',
De='Deadlyyrage:BAAANQADCgUIEAAAAA==.Deathkill:BAAANQADCgcIDQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgUICQAAAA==.Defyndk:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Defynds:BAAANQAECgEIAQAAAA==.Demonesla:BAAANQADCgQIBwAAAA==.Demoslayer:BAAANQADCgUICwAAAA==.Denardiir:BAAANQAECgMIBAABNQAECgUICgABAAAAAA==.Desir:BAAANQAECgYIEAAAAA==.Desperate:BAAANQADCgUICgAAAA==.Destanna:BAAANQADCgQIBwAAAA==.Detoxic:BAAANQAECgEIAQAAAA==.Dewdeath:BAAANQAECgEIAgAAAA==.Dewdvoker:BAAANQAECgEIAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dilendra:BAAANQADCggIEwABNQAECgUICwABAAAAAA==.Diman:BAAANQADCgUIBQAAAA==.Dingodash:BAAANQADCgcIBwAAAA==.Diseased:BAAANQAECgUIDQAAAA==.Dizzimajizz:BAAANQAECgUIDAAAAA==.',
Dm='Dmgfordays:BAAANQAECgQICgAAAA==.',
Do='Dogê:BAAANQAECgcIDgAAAA==.Domme:BAAANQAECgcIDAAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Dovakin:BAAANQADCgYICgAAAA==.Downpour:BAAANQADCgYICAAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drakenkorin:BAAANQADCgMIAwAAAA==.Drated:BAAANQADCggIEAABNQAECgkJGwAIAI8OAA==.Drazalgor:BAAANQADCggIEQAAAA==.Drepung:BAAANQAECgUICgAAAA==.Dretlok:BAAANQAECgQICAAAAA==.Droopyclam:BAAANQABCgQIBAAAAA==.',
Du='Duatani:BAAANQAECgEIAQAAAA==.Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBgAAAA==.Dukhan:BAAANQAECgYIDQAAAA==.Dukkhadk:BAAANQAECgEIAQAAAA==.Durinsoñ:BAAANQAECgYICwAAAA==.Durzy:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.Duskaryn:BAAANQAECggIBAAAAA==.',
Dw='Dworglaranna:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAAANQAECgYICwAAAA==.Dyrtylox:BAAANQADCgUIBQAAAA==.',
Ea='Eaglekick:BAAANQAECgQIBAAAAA==.Easilyamused:BAAANQAECgIIAgAAAA==.',
Ec='Eclips:BAAANQAECgEIAQAAAA==.',
Ed='Eddo:BAAANQADCgYIBgAAAA==.Edrissa:BAAANQADCgcIBwAAAA==.',
Eg='Egosumvacca:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAABNQAECoEbAAQIAAkJjw5mMwAHAgAIAAgJ+g5mMwAHAgAJAAMJUwjrPACVAAAKAAEJ4wGEIAAjAAAAAA==.Elladale:BAAANQAECgQIBQAAAA==.Ellaxstrasza:BAAANQADCgUIBwAAAA==.Elleryl:BAAANQAECgIIAgAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elryk:BAAANQAECgIIAgAAAA==.Elsaemonk:BAAANQADCggIDAAAAA==.Elynna:BAAANQADCgYIDgAAAA==.',
Em='Emmaroids:BAAANQADCggIDQAAAA==.Emmuu:BAAANQAECgYICgABNQADCggICAABAAAAAA==.',
En='Enjoi:BAAANQADCgQIBAAAAA==.Enoc:BAAANQAECgIIAgAAAA==.',
Et='Etyeehaw:BAABNQAECoEaAAILAAYJ3iONAgBpAgALAAYJ3iONAgBpAgAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQAECgEIAQAAAA==.',
Ez='Ezzbot:BAAANQAECgUICQAAAA==.',
Fa='Fabulously:BAAANQAECgQICgABNQAECgcIGgAFAJYKAA==.Fallèn:BAAANQAECgEIAQAAAA==.Falnyr:BAABNQAECoEeAAIMAAcJqR64CQBlAgAMAAcJqR64CQBlAgAAAA==.Fanchone:BAAANQADCggIDAAAAA==.Fandahvis:BAAANQAECgMIBAAAAA==.Faroosh:BAAANQADCgYICAAAAA==.Fartshart:BAAANQAECgQIBQAAAA==.Favorite:BAAANQAECgEIAQAAAA==.',
Fe='Fearus:BAAANQABCgYICAAAAA==.Felanthropy:BAAANQAECgEIAwAAAA==.Felbunny:BAAANQAECgYIDAAAAA==.Felfliction:BAAANQABCgEIAQAAAA==.Felinae:BAAANQAECgEIAQAAAQ==.Felmagus:BAAANQAECgMIBAAAAA==.Felrrak:BAABNQAECoEvAAINAAkJfxleCwDYAgANAAkJfxleCwDYAgAAAA==.Felstro:BAAANQAECgQIBQAAAA==.Felwynbrooke:BAAANQAECgQIDwAAAA==.Ferynis:BAAANQAECgEIAQAAAA==.',
Fi='Firekhan:BAAANQAECgYIDAAAAA==.Fistful:BAABNQAECoEZAAICAAgJ8Q1qEAC4AQACAAgJ8Q1qEAC4AQAAAA==.',
Fl='Flador:BAAANQAECgQIBwAAAA==.Flickatotem:BAAANQAECgIIAgAAAA==.Florinka:BAAANQAECgIIAgAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQADCgcIBwAAAA==.',
Fo='Forgedhorny:BAAANQADCgUIBgAAAA==.Forxiga:BAAANQAECgMIAwAAAA==.Fourcheeks:BAAANQAECgcIEQAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frell:BAAANQADCgQIBAAAAA==.Frez:BAAANQAECgEIAgAAAA==.Frierén:BAAANQADCggIFAAAAA==.Frisli:BAAANQAECgQIBAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCggIHgABAAAAAA==.Frostlass:BAAANQADCgQIBQAAAA==.Frostveil:BAAANQAECgMIAwABNQAECggIBAABAAAAAA==.Frostyflakez:BAAANQAECgQIBAAAAA==.Frostyfruit:BAAANQAECgYIEAAAAA==.',
Fu='Furnous:BAABNQAECoEbAAMOAAcJLgoklgCTAQAOAAcJNgkklgCTAQAPAAEJ6BBmJwA4AAAAAA==.Fuzzydks:BAAANQADCggIEgABNQAECgYIDAABAAAAAA==.',
Ga='Galenddrel:BAAANQADCgIIAwAAAA==.Gant:BAAANQADCgYIDgAAAA==.Gargamus:BAAANQAECgQIBQAAAA==.',
Ge='Gemashdk:BAAANQADCgcICQABNQAECgQIBgABAAAAAA==.Gemashrogue:BAAANQAECgQIBgAAAA==.Gemtastic:BAAANQADCgMIAwAAAA==.Georgieanne:BAAANQADCggIEwAAAA==.',
Gh='Ghazali:BAAANQADCggICAAAAA==.Gheru:BAAANQAECgMIBAAAAA==.Ghoolies:BAAANQADCgYIFAABNQAECgQIBwABAAAAAA==.',
Gi='Gigadeekay:BAAANQADCgYIBgAAAA==.Gildartz:BAAANQADCgYIBgAAAA==.',
Gl='Glitterspark:BAAANQAECgIIAgAAAA==.Glittr:BAAANQAECgUIBQABNQAECgkJMQAMANUhAA==.Glitty:BAABNQAECoExAAMMAAkJ1SECAgB4AwAMAAkJ1SECAgB4AwAQAAIJiBW6KgCCAAAAAA==.Glodslock:BAAANQAECgEIAQAAAA==.',
Go='Goated:BAAANQADCggIHgAAAA==.Goliathxx:BAAANQAECgEIAQAAAA==.Gonewe:BAAANQAECgIIAwAAAA==.Gongaga:BAAANQADCgYICQAAAA==.Googam:BAAANQAECgcICgAAAA==.Gornuts:BAAANQAECgQICAAAAA==.Gosly:BAAANQAECgcIDwAAAA==.Gozhuntsurv:BAAANQABCgEIAQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAAANQAECgEIAwAAAA==.Grayfox:BAAANQAECgQIBAAAAA==.Greeneyes:BAAANQADCgMIAwAAAA==.Grelle:BAAANQADCggIDAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggIFwABNQAECgUIDQABAAAAAA==.Grip:BAAANQAECgcIDwAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQAECgIIAgAAAA==.',
Gu='Guzwar:BAAANQAECgMIBgAAAA==.',
Gy='Gyftable:BAAANQAECgQICAAAAA==.Gypsierose:BAAANQAECgEIAgAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gï']='Gïmli:BAAANQADCgEIAQAAAA==.',
['Gò']='Gòrilla:BAAANQADCgYICgAAAA==.',
Ha='Hairytoad:BAAANQAECgUIEwAAAA==.Hakoda:BAAANQADCgMIAwABNQADCggIEgABAAAAAA==.Hardlightsgt:BAAANQADCgIIAgAAAA==.Harriet:BAAANQADCgMIAwAAAA==.Harubless:BAAANQADCggICAAAAA==.Harushear:BAACNQAFFIEMAAIRAAcJYRk1AAC0AgARAAcJYRk1AAC0AgA1AAQKgR0AAhEACQlvJasBALkDABEACQlvJasBALkDAAAA.Harushorn:BAAANQAECgUIBwAAAA==.Harvester:BAAANQAECgQIBgAAAA==.Havocbringer:BAAANQAECgQIBAAAAA==.',
He='Headaxe:BAAANQAECgQIBAAAAA==.Healmemutt:BAAANQAECgQIBQAAAA==.Hearte:BAAANQAECgcIEQAAAA==.Hellweaver:BAAANQADCgYIBgAAAA==.Hermano:BAAANQAECgUIEQABNQAECgYICwABAAAAAA==.Hermiscuous:BAAANQAECgEIAgABNQAECgYICwABAAAAAA==.Hermy:BAAANQAECgYICwAAAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAAANQAECgMIBAAAAA==.',
Hi='Hinotori:BAAANQADCgYIBgAAAA==.Hinters:BAAANQAECgUICQAAAA==.',
Ho='Holing:BAABNQAECoEZAAISAAgJ1CBrFgDtAgASAAgJ1CBrFgDtAgAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEIAgAAAA==.Holymoly:BAAANQADCgEIAQAAAA==.Honeyduke:BAAANQAECgUICgAAAA==.Hopenottodie:BAAANQAECgIIBAAAAA==.Hopes:BAAANQAECgQICAAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgcICAAAAA==.Huntum:BAAANQADCgUIBQAAAA==.Huntzha:BAAANQAECgIIAgAAAA==.',
Hy='Hyndis:BAAANQAECgEIAQAAAA==.Hyorinmâru:BAAANQAECgUIBgAAAA==.',
Ia='Iamoutofammo:BAAANQAECgIIAgAAAA==.Ianix:BAAANQAECgUIBgAAAA==.',
Ic='Iceni:BAAANQAECgQICAAAAA==.Icepick:BAAANQADCggICAABNQADCggIEAABAAAAAA==.',
Id='Idíot:BAAANQAECgIIAwAAAA==.',
If='Ifelforu:BAAANQAECgYIDAAAAA==.',
Ih='Ihaslegs:BAAANQAECgEIAQAAAA==.',
Il='Ilidun:BAAANQABCgIIAQAAAA==.Illimoo:BAAANQAECgIIAgAAAA==.Ilumminus:BAAANQADCgQIBwABNQADCggIFwABAAAAAA==.',
Im='Imoldgrèg:BAAANQADCgMIAwABNQAECgYICwABAAAAAA==.',
In='Incineratus:BAAANQAECgUICQAAAA==.Ineci:BAAANQADCgYIFAAAAA==.Infurrnal:BAAANQAECgUICQAAAA==.Innerpeace:BAAANQAECgEIAgAAAA==.Inspirez:BAAANQADCgYIEAAAAA==.Instamissed:BAAANQADCgUIBQAAAA==.Intolerence:BAAANQADCggIDAAAAA==.',
Ip='Ipooptotems:BAAANQADCgcIEwAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishootstuff:BAAANQAECgYIDwAAAA==.',
It='Itsnotbatman:BAAANQAECgUICwAAAA==.',
Iv='Ivanra:BAAANQAECgcIDgAAAA==.',
Iy='Iyna:BAAANQADCgUIBQAAAA==.',
Iz='Izlek:BAAANQAECgYICwAAAA==.',
['Iì']='Iìe:BAAANQAECgYIDgAAAA==.',
Ja='Jagermaster:BAAANQADCgQIBwAAAA==.Janeygirl:BAAANQAECgUIDQAAAA==.',
Jc='Jcx:BAAANQADCgYIDAABNQAECgEIAgABAAAAAA==.',
Je='Jeningo:BAAANQABCgcICAAAAA==.Jeningze:BAAANQADCgcIBwAAAA==.Jestiny:BAAANQAECgIIAwAAAA==.Jezebel:BAAANQADCgYIFAAAAA==.',
Jo='Johannuz:BAAANQAECgQICQAAAA==.Johngoblikon:BAAANQAECgIIAgAAAA==.Johnyf:BAAANQADCgcIEwAAAA==.Jonesy:BAABNQAECoEYAAITAAgJ1BINCQDrAQATAAgJ1BINCQDrAQAAAA==.Jononononono:BAAANQAECgYIEAAAAA==.Jonz:BAAANQAECgUICQAAAA==.Joshington:BAAANQAECgYIEAAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCgcIEAAAAA==.Kaiden:BAAANQADCgYIBgAAAA==.Kalanix:BAAANQAECgEIAgAAAA==.Kalji:BAAANQADCgcIBwABNQAECggIFwACAA8cAA==.Kanatari:BAAANQAECgQIBQAAAA==.Kansch:BAAANQADCgMIAwABNQAECgcIHAAUANIWAA==.Karaleigh:BAAANQAECgcIEQAAAA==.Katallia:BAAANQAECgIIAgAAAA==.Kateley:BAAANQAECgIIAgAAAA==.Kattadin:BAAANQADCggIEwAAAA==.Kaybs:BAAANQAECgQIBAAAAA==.',
Ke='Keanoo:BAAANQAECgQIBQAAAA==.Kekai:BAAANQABCgQICQAAAA==.Kelanthus:BAAANQAECgUIDAAAAA==.Kellalas:BAAANQADCgUIEAAAAA==.Kelvinator:BAAANQADCgcIDgAAAA==.Kernni:BAAANQAECgIIAgAAAA==.Kes:BAAANQAECgEIAQAAAA==.',
Kh='Khades:BAAANQADCgMIAwAAAA==.',
Ki='Kirisera:BAAANQAECgEIAgAAAA==.Kittymik:BAEANQAECgUICgAAAA==.Kixa:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
Kl='Klawfel:BAAANQADCgYICwAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Kormath:BAAANQAECgEIAQAAAA==.Korrack:BAAANQAECgEIAQAAAA==.Korruptoor:BAAANQABCgQIBAAAAA==.Kotath:BAAANQADCgUIBwAAAA==.Kowbruh:BAAANQADCgYICwAAAA==.',
Kr='Krianlan:BAAANQAECgEIAQABNQAECggIBAABAAAAAA==.',
Ku='Kuddy:BAAANQAECgYIDgAAAA==.Kumamizu:BAAANQADCgcIEwAAAA==.',
Kw='Kwr:BAAANQAECgEIAQAAAA==.Kwyn:BAAANQADCgYIFAABNQAECgQICAABAAAAAA==.',
Ky='Kyxa:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.',
['Kè']='Kèw:BAAANQADCgcIFgAAAA==.',
La='Lacronista:BAAANQAECgQIBAAAAA==.Lagavulin:BAAANQAECgYIBgAAAA==.Lalatinaford:BAAANQADCggICAAAAA==.Lambdadelta:BAAANQADCgIIAgAAAA==.Landacious:BAAANQADCgUIBQAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAAANQAECgcIDwAAAA==.Leella:BAAANQAECgEIAQAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYICAAAAA==.Legolash:BAAANQAECgUICQAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQAECgIIAgAAAA==.Lewy:BAAANQAECgIIBAAAAA==.Lexicon:BAAANQAECgUICgAAAA==.Lexxen:BAAANQAECgcIEwAAAA==.Leàfy:BAAANQAECgYICwAAAA==.',
Li='Lightblade:BAAANQAECgUIDQAAAA==.Lilibewhan:BAAANQABCgEIAQAAAA==.Limonae:BAAANQAECgQICwAAAA==.Lisellee:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
Ll='Lljunior:BAAANQABCgMIAwAAAA==.',
Lo='Locha:BAAANQAECgEIAgAAAA==.Lockstøck:BAAANQAECgUICAAAAA==.Longicorn:BAAANQADCgYIBgABNQAECgkJGAAEAA4fAA==.Lostváyne:BAAANQADCgYIBgAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAFFAQIBgAJAJcWAA==.',
Ls='Ls:BAAANQAECgQICQAAAA==.',
Lu='Ludal:BAAANQADCgYIEwAAAA==.Luketism:BAAANQAECgQIBgAAAA==.Lunarrage:BAAANQADCgEIAQABNQADCgUICAABAAAAAA==.Lunen:BAABNQAECoEZAAIVAAgJ/BtiBACSAgAVAAgJ/BtiBACSAgAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lyraria:BAAANQADCgIIAgAAAA==.Lythorn:BAAANQAECgEIAgAAAA==.',
['Lè']='Lèpton:BAAANQAECgEIAwAAAA==.',
['Lé']='Léäf:BAAANQAECgUIDQAAAA==.',
['Lõ']='Lõx:BAAANQAECgcIEAAAAA==.',
Ma='Madamgrey:BAAANQAECgUICQAAAA==.Maebyfunke:BAAANQADCggICAAAAA==.Magestørm:BAAANQAECggIDQAAAA==.Magicboi:BAAANQADCgcIEQAAAA==.Magicmagnus:BAAANQADCggIEAAAAA==.Magictacos:BAAANQAECgQIDwAAAA==.Magistrasza:BAABNQAECoEZAAIOAAgJOQethQC7AQAOAAgJOQethQC7AQAAAA==.Majkusanagi:BAAANQAECgQICAAAAA==.Makisig:BAAANQAECgUIBQAAAA==.Malfy:BAAANQAECgEIAQAAAA==.Malvnaire:BAAANQAECgQIBAAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAAANQAECgUIBgAAAA==.Mariandor:BAAANQAECgEIAQAAAA==.Marlinn:BAABNQAECoEYAAIWAAgJ3QxxOQATAgAWAAgJ3QxxOQATAgABNQAFFAUICAAHAAUKAA==.Marlos:BAAANQAECgEIAQAAAA==.Marrmite:BAAANQADCgYIBgAAAA==.Marthaus:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Martmist:BAAANQAECgUIDQAAAA==.Mateo:BAAANQADCggIEgAAAA==.Mathias:BAAANQAECgIIAgAAAA==.Mattiass:BAAANQAECgMIBgAAAA==.Mattrik:BAAANQAECgQICAAAAA==.Maulyou:BAAANQAECgYIBgAAAA==.Maximilia:BAAANQAECgcIEAAAAA==.Maydayx:BAAANQAECgcIDgABNQAECgkJLgANAPYhAA==.',
Mc='Mcdoom:BAAANQAECgYICgAAAA==.Mcduff:BAAANQADCggIFwAAAA==.',
Me='Meaningreen:BAAANQADCgcIEAAAAA==.Mekuntizichi:BAAANQADCgcICAAAAA==.Melazaelf:BAAANQADCgQIBwAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Mermoo:BAAANQADCgMIAwAAAA==.Messages:BAAANQADCggICAAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Midwa:BAACNQAFFIEKAAISAAUJwB0XAQDhAQASAAUJwB0XAQDhAQA1AAQKgSEAAhIACQmRJvkAAPMDABIACQmRJvkAAPMDAAAA.Miishah:BAAANQAECgUIBgAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAAANQAECgQIBQAAAA==.Mistel:BAAANQAECgQIBAAAAA==.Mistyfuzz:BAAANQAECgQIBgAAAA==.Mithrendir:BAAANQADCggIFwAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQAECgQICAABAAAAAA==.Moguette:BAAANQAECgUIBgABNQAECgUIBgABAAAAAA==.Moistroll:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Molith:BAAANQABCgYICAAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAAANQAECgQIDQAAAA==.Moonhill:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Moordenaar:BAAANQAECgUICQAAAA==.Moosy:BAAANQAECgMIAwAAAA==.Morala:BAAANQADCgYIBgAAAA==.Morgainne:BAAANQADCgEIAQAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Mortarius:BAAANQADCgcIEwAAAA==.Movicol:BAAANQAECgEIAgAAAA==.Mozire:BAAANQAECgEIAQAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgcIDQABAAAAAA==.',
Mt='Mth:BAAANQAECgUIBwAAAA==.Mtnaan:BAAANQAECgEIAQAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCggIEQAAAA==.Musch:BAAANQADCgYIBgABNQAECgcIHAAUANIWAA==.Musde:BAABNQAECoEcAAMUAAcJ0hZrEgD5AQAUAAcJ0hZrEgD5AQAXAAEJIgWjeQAjAAAAAA==.Musterick:BAAANQAECgEIAgAAAA==.Muther:BAAANQAECgIIBAAAAA==.',
My='Myctlan:BAAANQADCggIGQAAAA==.Mylie:BAAANQABCgQIBgAAAA==.Myrddn:BAAANQAECgIIAwAAAA==.Myrdi:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Myrsham:BAAANQAECgEIAQAAAA==.Mytearsheal:BAAANQAECgEIAwAAAA==.Mythbrediir:BAAANQAECgUICgAAAA==.',
['Mü']='Müläflaga:BAAANQADCgYIBgAAAA==.',
Na='Naadina:BAAANQADCgYIFAAAAA==.Nadazarter:BAAANQAECgEIAgAAAA==.Naggo:BAAANQADCgYIBwAAAA==.Nalph:BAAANQAECgQIBAAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Nathun:BAAANQAECgIIAwAAAA==.Navillas:BAAANQAECgEIAwAAAA==.Nayha:BAAANQAECgEIAQAAAA==.',
Ne='Nebulachimi:BAABNQAECoEeAAIXAAYJdQTORAAUAQAXAAYJdQTORAAUAQAAAA==.Nebularyu:BAAANQADCgUIDwAAAA==.Nedimus:BAAANQAECgQIDAABNQAECgEIAgABAAAAAA==.Nekhrimah:BAAANQAECgYIBwAAAA==.Neoaerith:BAAANQAECgUIBwAAAA==.Nerii:BAAANQAECgIIAgAAAA==.Nerpthas:BAAANQAECgMIBQAAAA==.Neverlinkx:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAAANQAECgQIDAAAAA==.Nilin:BAAANQAECgUICgAAAA==.Nina:BAAANQAECgYICgABNQABCgIIAgABAAAAAA==.Nisulus:BAAANQADCggIFgAAAA==.Niteañgel:BAAANQADCggIFAAAAA==.Niç:BAAANQAECgUICQAAAA==.',
No='Noala:BAAANQADCgQIBAAAAA==.Noctuana:BAAANQADCgYIFQABNQAECgMIAwABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAAANQAECgcIEgAAAA==.Notbeezy:BAAANQAECgYIEAAAAA==.Nox:BAABNQAECoEVAAIYAAkJNxivCgDVAgAYAAkJNxivCgDVAgAAAA==.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgYICgAAAA==.Numnutts:BAAANQAECgYICwAAAA==.Nutelle:BAAANQADCgYIBwAAAA==.',
['Nè']='Nèrp:BAAANQAECgYICgAAAA==.',
['Nú']='Númenórean:BAABNQAECoEaAAIWAAYJBgrBYAB7AQAWAAYJBgrBYAB7AQAAAA==.',
['Nü']='Nüts:BAAANQAECgQIBwAAAA==.',
Oa='Oathorr:BAAANQADCgQIBAAAAA==.',
Ob='Obadiah:BAAANQADCgYIDAAAAA==.',
Og='Ogriv:BAAANQADCgUIBwAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Ol='Olunaija:BAAANQADCggIEgAAAA==.',
Om='Omm:BAEANQAECgIIAwAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQAECgQIBgAAAA==.',
Ou='Ouchiheal:BAAANQAECgcIEAAAAA==.',
Ov='Overhealer:BAABNQAECoEXAAMZAAgJrhhhGwBsAgAZAAgJrhhhGwBsAgAaAAIJZAOzFABVAAAAAA==.',
['Oà']='Oàthor:BAAANQAECgEIAQAAAA==.',
Pa='Pachi:BAAANQAECgEIAQAAAA==.Paladipuss:BAAANQADCggIEgAAAA==.Paladumb:BAABNQAECoE2AAMSAAkJYhyNFwDkAgASAAkJYhyNFwDkAgAbAAEJEAp+QQAnAAAAAA==.Palatism:BAAANQAECgYIDgAAAA==.Panchovy:BAACNQAFFIEIAAIHAAUJBQpYAgB2AQAHAAUJBQpYAgB2AQA1AAQKgSAAAgcACQnBH1MFACsDAAcACQnBH1MFACsDAAAA.Parrexion:BAAANQADCgEIAQAAAA==.',
Pe='Peculiar:BAAANQAECgEIAQAAAA==.Pegor:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Pegz:BAAANQADCgYIBgAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQAECgIIAgAAAA==.',
Ph='Phantom:BAAANQADCgQIBQAAAA==.Phazonicide:BAAANQADCgcIDgAAAA==.Phlaea:BAAANQAECgUICQAAAA==.',
Pi='Pieata:BAAANQADCggIFAAAAA==.',
Pl='Plazistank:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Po='Pogo:BAAANQAECgQICAAAAA==.Poisoning:BAAANQAECgUIBQAAAA==.Poknat:BAAANQADCggICAAAAA==.Polkievoke:BAAANQADCgUIBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCggIIgAAAA==.Postee:BAAANQADCggIEAAAAA==.Powerrager:BAAANQAECgEIAQAAAA==.',
Pr='Precioùs:BAAANQAECgUIDQAAAA==.Prettyhectic:BAAANQAECgcIEgAAAA==.Priincebun:BAAANQAECggICAAAAA==.Prinsesdonut:BAAANQAECgQICAAAAA==.Projecjx:BAAANQADCgYICgAAAA==.Protagonist:BAACNQAFFIEHAAINAAIJTiJLBQDLAAANAAIJTiJLBQDLAAA1AAQKgRsAAw0ACQkkIrwKAOQCAA0ACAnKIbwKAOQCABEABQlVFMUuAD4BAAE1AAUUBwgRAAYA6CEA.Proz:BAAANQADCgYIBgAAAA==.Prozium:BAAANQAECgYICgABNQADCgYIBgABAAAAAA==.',
Pu='Purifythis:BAAANQADCgMIAwAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.Pyschotic:BAAANQADCgQIBAAAAA==.',
['Pä']='Pänya:BAAANQADCgUIBQAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAQAAAA==.',
Qu='Quag:BAAANQADCgYICAAAAA==.Quinny:BAAANQAECgQICAAAAA==.Quintar:BAAANQAECgYIEwAAAA==.',
Ra='Raagnar:BAAANQADCgcIBwAAAA==.Rabbage:BAAANQAECgYICQAAAA==.Raeka:BAAANQAECgYIDwAAAA==.Raenda:BAAANQADCgYICgAAAA==.Ragarlem:BAAANQADCggIFAAAAA==.Ragefright:BAAANQAECgYIBgABNQAECgkJFQAYADcYAA==.Rageie:BAAANQAECgMIAwAAAA==.Rageieboop:BAAANQAECgIIAgAAAA==.Ragemore:BAAANQAECgYIEAAAAA==.Rahvine:BAAANQADCggIFAAAAA==.Raiteq:BAAANQAECgcIDAAAAA==.Raitev:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Raputami:BAAANQAECgcIDwAAAA==.Rastoons:BAAANQAECgIIAwAAAA==.Rawlôck:BAABNQAECoEZAAMIAAgJ6heeLQAkAgAIAAcJOxmeLQAkAgAJAAMJsxA8NAC6AAAAAA==.Raxor:BAAANQAECgIIAgAAAA==.Raya:BAAANQAECgQIBQAAAA==.',
Rd='Rde:BAAANQAECgQIBAAAAA==.',
Re='Redoctobah:BAAANQADCgcIEwAAAA==.Regret:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reignrott:BAAANQAECgUICQAAAA==.Reika:BAAANQAECgQIBAAAAA==.Replaceable:BAAANQABCgIIAwABNQAECgYIDgABAAAAAA==.Reptizzle:BAAANQADCgQIBAAAAA==.Restorer:BAAANQAECgEIAwAAAA==.Retalica:BAAANQAECgEIAQAAAA==.Retrishi:BAAANQAECgUIDAAAAA==.Retxbladés:BAAANQADCgUIDgAAAA==.Revelstat:BAAANQADCgQIBgAAAA==.Reverb:BAAANQAECgYIDgAAAA==.Rexonon:BAAANQAECgQIBAABNQAECgYIDwABAAAAAA==.Rexsham:BAAANQAECgYIDwAAAA==.Rexyclog:BAAANQAECgIIAwAAAA==.Reyku:BAAANQAECgIIAwAAAA==.',
Rh='Rhydon:BAAANQADCgQIAgAAAA==.',
Ri='Ricard:BAAANQADCgcIBwAAAA==.Rickettsia:BAAANQAECgUICQAAAA==.Rig:BAAANQADCggICAAAAA==.Rildis:BAAANQADCggIDwABNQAECgUIBgABAAAAAA==.Rippen:BAAANQADCgYIDQAAAA==.Ritasu:BAAANQABCgUIAwAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
Ro='Robyngdfelow:BAAANQAECgcICgAAAA==.Rohovart:BAAANQADCgcIEwAAAA==.Rollingrick:BAAANQAECgUICgAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAAANQAECgUICQAAAA==.',
Ru='Runaway:BAAANQAECgIIAgAAAA==.Rustycrack:BAAANQAECgIIAwAAAA==.Ruul:BAAANQAECgEIAQAAAA==.',
Ry='Ryana:BAAANQABCgMIAwAAAA==.Ryilla:BAAANQADCgcIGAAAAA==.Rynoe:BAAANQADCggIDwAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.',
['Rá']='Ráric:BAAANQADCggIDgAAAA==.',
Sa='Sableman:BAAANQADCgYIEQAAAA==.Saccromycaes:BAAANQAECgIIAgAAAA==.Saclem:BAAANQAECgEIAQAAAA==.Saha:BAAANQAECgEIAQAAAA==.Saintayah:BAAANQAECgYIEgAAAA==.Salokin:BAAANQADCgYIBgABNQAFFAUICAAcAEwYAA==.Salorellin:BAABNQAECoEZAAIRAAgJ4iBWCgD4AgARAAgJ4iBWCgD4AgAAAA==.Sandrèena:BAAANQAECgQICAAAAA==.Sanity:BAAANQAECgEIAQAAAA==.Sarakatawen:BAAANQADCgcIJwAAAA==.Sarumash:BAAANQAECgMIAwAAAA==.Satanah:BAAANQADCgYIDQAAAA==.Satomi:BAAANQADCgUICQAAAA==.Satre:BAAANQAECgYIDQAAAA==.',
Se='Seculoe:BAAANQAECgQIBwAAAA==.Seedypete:BAAANQADCgcIDQAAAA==.Seemébloody:BAAANQAECgQIAwAAAA==.Seldarine:BAAANQAECgQIBAAAAA==.Selten:BAAANQAECgEIAQAAAA==.Sendel:BAAANQADCgQIBAAAAA==.Senele:BAAANQAECgEIAgAAAA==.Senescence:BAACNQAFFIEGAAQJAAQJlxZRAgDPAAAJAAIJ/xxRAgDPAAAIAAEJkw+BGABRAAAKAAEJyxChBABPAAA1AAQKgSUABAgACQkjJC8TAMcCAAgABwlxIy8TAMcCAAkABQkbIGUPAN4BAAoAAgkAJDcNALwAAAAA.Sesshomar:BAAANQADCgEIAQAAAA==.Seventhchild:BAAANQADCgQIBAAAAA==.',
Sh='Sh:BAAANQAECgYICwAAAA==.Shadopaw:BAAANQAECgMIBgAAAA==.Shadowsyy:BAAANQABCgMIAwAAAA==.Shadyllama:BAAANQAECgQICAAAAA==.Shamkat:BAAANQADCgcIFgAAAA==.Shammah:BAAANQAECgYICwAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgQICgAAAA==.Sharnie:BAAANQAECgQICAAAAA==.Shear:BAAANQAECggIAQAAAA==.Shellatrix:BAAANQAECgYIDQAAAA==.Shepp:BAAANQAECgYICwAAAA==.Shommy:BAAANQADCggICAAAAA==.Shootette:BAAANQAECgQIBgAAAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQAECgEIAQAAAA==.Sinderela:BAAANQAECgQICAAAAA==.Sinisterwing:BAAANQAECgYICAAAAA==.',
Sk='Skeptikk:BAABNQAECoEZAAIGAAgJXRmtIABsAgAGAAgJXRmtIABsAgAAAA==.Skinnery:BAAANQADCgcIEwAAAA==.Skrull:BAAANQAECgUICQAAAA==.',
Sl='Slateray:BAAANQAECgEIAQAAAA==.Slipnslide:BAAANQADCggICQAAAA==.',
Sm='Smaque:BAAANQAECgYIEQAAAA==.Smegging:BAAANQADCgYICQAAAA==.',
Sn='Snaare:BAAANQADCgYIDAAAAA==.',
So='Solcaris:BAAANQAECgEIAQAAAA==.Sorie:BAAANQAECgQIBAAAAA==.Sourstraps:BAAANQADCgMIAwAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Sparkdead:BAAANQADCgQIBwAAAA==.Spatspell:BAAANQADCggICQABNQADCggIEAABAAAAAA==.Spazzimitazz:BAAANQADCgIIAgAAAA==.Spazzy:BAAANQAECgUIDQAAAA==.Spenna:BAAANQAECgEIAQAAAA==.Spudacus:BAAANQAECgQICAAAAA==.Spuddk:BAAANQAECgYIDwAAAA==.Spudsham:BAAANQAECgQIBAABNQAECgYIDwABAAAAAA==.',
St='Stabforcash:BAABNQAFFIEKAAIdAAUJ4B9SAAASAgAdAAUJ4B9SAAASAgAAAA==.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQAECgIIAwAAAA==.Stickler:BAAANQAECgQICAAAAA==.Stonkerella:BAAANQADCgIIAgAAAA==.Stonque:BAAANQADCgcIBwABNQAECgYIEQABAAAAAA==.Stormchief:BAAANQADCgQIBAAAAA==.Stormgoat:BAAANQADCgYIBwAAAA==.Stormie:BAAANQAECgMIAwAAAA==.Stormrider:BAAANQAECgQICgAAAA==.Streuth:BAABNQAECoEZAAIeAAgJyyP0AQA8AwAeAAgJyyP0AQA8AwAAAA==.Strummer:BAABNQAECoE0AAMWAAkJISQBAgDDAwAWAAkJISQBAgDDAwAfAAIJUxUXPgB6AAAAAA==.Stubbyholder:BAAANQADCggICAAAAA==.',
Su='Subaru:BAAANQAECgIIAgAAAA==.Subaruu:BAAANQADCgQICAABNQAECgIIAgABAAAAAA==.Subsiding:BAAANQADCgYIBgAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQADCgIIAgAAAA==.Supernothing:BAAANQAECgIIAwAAAA==.Superswede:BAAANQADCggIHwAAAA==.Susurrus:BAAANQADCgUIBQAAAA==.',
Sw='Switchdoctor:BAAANQADCggIEAABNQADCggIEAABAAAAAA==.Sworf:BAABNQAECoEbAAIGAAgJMhcfIwBbAgAGAAgJMhcfIwBbAgAAAA==.',
Sy='Syaarhunter:BAAANQADCgcIFwAAAA==.Syaarknight:BAAANQADCgYIBwAAAA==.Syaarpally:BAAANQADCggIFAAAAA==.Syazar:BAAANQAECgIIAgAAAA==.Sylanthia:BAAANQAECgQIBwAAAA==.Sylblades:BAAANQAECgUIBQAAAA==.Sylwizard:BAAANQABCgEIAQAAAA==.',
['Só']='Sóg:BAAANQAECgEIAgABNQAECgcIEAABAAAAAA==.',
['Sø']='Søbz:BAAANQADCggIHQAAAA==.Søg:BAAANQAECgcIEAAAAA==.',
['Sù']='Sùnjin:BAAANQADCgcIFAABNQAECgQICAABAAAAAA==.',
Ta='Tabknight:BAAANQAECgcIEQAAAA==.Taelron:BAAANQAECgIIAgAAAA==.Taelstard:BAAANQAECgEIAgAAAA==.Taichook:BAAANQAECgEIAQABNQAECgcIGQASAH8eAA==.Taithos:BAABNQAECoEZAAISAAcJfx45MwA4AgASAAcJfx45MwA4AgAAAA==.Talanardonis:BAAANQADCgQIBAAAAA==.Tanktough:BAAANQAECgUIBQAAAA==.Tarago:BAAANQAECgUIEQAAAA==.Taranisis:BAAANQAECgMIBQAAAA==.Targetone:BAAANQAECgUICAAAAA==.Tasall:BAAANQADCggIEQAAAA==.Tauntflaunt:BAAANQAECgcIEAAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAAANQAECgUICQAAAA==.Tempø:BAAANQADCgYIEgAAAA==.Tenkris:BAAANQAECgEIAQAAAA==.Tenleigh:BAAANQAECgEIAQAAAA==.Terroria:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Terrorizor:BAAANQAECgEIAwAAAA==.',
Th='Thalía:BAAANQADCggIHwAAAA==.Thargroar:BAAANQAECgcIEQAAAA==.Thazix:BAAANQADCgQIBwABNQAECgYICwABAAAAAA==.Thefluffyman:BAAANQAECgQIBwAAAA==.Themetzi:BAAANQADCgUIBQAAAA==.Thiss:BAAANQAECgYICwAAAA==.Thordak:BAAANQAECgIIAgAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.Thùnder:BAAANQADCgMIAwAAAA==.',
Ti='Tigolbits:BAAANQADCgUIBQAAAA==.Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAAANQAECgcIDQAAAA==.Toehacker:BAAANQAECgYIEAAAAA==.Toliman:BAAANQADCgQIBwAAAA==.Tolkarkiller:BAAANQAECgQIBAAAAA==.Tomarr:BAEBNQAECoEZAAIgAAgJlwngQgCeAQAgAAgJlwngQgCeAQABNQAECgQIBQABAAAAAA==.Tonsham:BAAANQADCgYIBwAAAA==.Totemspanker:BAAANQADCgcIEwAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQAECgIIAwAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAAANQAECgcIDwAAAA==.',
Tr='Trailblayxur:BAAANQAECgQIBQAAAA==.Traser:BAAANQADCgUIBgAAAA==.Trickyknight:BAABNQAECoEaAAMcAAcJ/hjMJAD1AQAcAAcJ/hjMJAD1AQADAAEJwRv+dQBUAAAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.Trinityheals:BAAANQADCgYICgAAAA==.',
Tu='Tuckerius:BAAANQADCgYIBwAAAA==.Turahk:BAAANQAECgQIBQAAAA==.Turtlesoup:BAAANQAECgUIDQAAAA==.',
Tw='Twofoottall:BAAANQADCgMIAwAAAA==.',
Ty='Tylendorian:BAAANQABCgEIAQAAAA==.Tylerolothus:BAAANQAECgEIAQAAAA==.Tynndera:BAAANQAECgMIAwAAAA==.Tyrawr:BAAANQAECgQIBAABNQAECgkJIQAcANwhAA==.Tyth:BAAANQAECgQICAAAAA==.',
['Tí']='Tím:BAAANQAECgQICAAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgIIAwABNQAECgYICgABAAAAAA==.',
Un='Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Uranbraug:BAAANQABCgIIAgAAAA==.Urôt:BAAANQAECgcICAAAAA==.',
Uw='Uwusue:BAAANQAECgYIBwAAAA==.',
Va='Vaeline:BAAANQABCgUIBgAAAA==.Valac:BAABNQAECoEhAAIcAAkJ3CHvBQBfAwAcAAkJ3CHvBQBfAwAAAA==.Valkyrie:BAAANQAECgQIBQAAAA==.Valothos:BAAANQAECgMICAAAAA==.Valtiell:BAABNQAECoEZAAIhAAgJrh30BwDFAgAhAAgJrh30BwDFAgAAAA==.Valuri:BAAANQAECgUICAAAAA==.Varainne:BAAANQAECgUICQAAAA==.',
Ve='Vegimitê:BAAANQADCgUIBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAABNQAECoEcAAIhAAkJ+RZVCAC9AgAhAAkJ+RZVCAC9AgAAAA==.Velkhana:BAAANQAECgYIEAAAAA==.Velmorra:BAAANQAECgQIBwAAAA==.Veratis:BAAANQAECgEIAQAAAA==.',
Vi='Victoria:BAAANQAECgQIBgAAAA==.Vinee:BAAANQAECgIIAwAAAA==.Vioneva:BAAANQAECgYICwAAAA==.Viscelock:BAAANQAECgcICgAAAA==.Vivyregosa:BAACNQAFFIEGAAIOAAQJPA6ACQBcAQAOAAQJPA6ACQBcAQA1AAQKgSEAAg4ACQnoHechAAwDAA4ACQnoHechAAwDAAAA.',
Vx='Vxi:BAABNQAFFIEKAAIdAAUJhxeeAADUAQAdAAUJhxeeAADUAQAAAA==.',
Wa='Wagglehoof:BAAANQADCgcIDAAAAA==.Wain:BAAANQAECgEIAQAAAA==.Wakantanka:BAAANQAECgIIAwAAAA==.Wanglord:BAAANQAECgUICgAAAA==.Wardõn:BAAANQADCgUIBgAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQADCgIIAgAAAA==.Waxedtaco:BAAANQAECgEIAQAAAA==.',
Wh='Wheato:BAAANQAECgYIDwAAAA==.Wheyprotein:BAAANQADCggICAAAAA==.Whipshot:BAAANQADCggICQAAAA==.Whiteflame:BAAANQAECgQIBAAAAA==.Whiteopal:BAAANQAECgYICwAAAA==.',
Wi='Willowsun:BAAANQAECgIIAgAAAA==.Winterzap:BAAANQADCggIGAAAAA==.Wipe:BAAANQADCggICAABNQAFFAcIEQAGAOghAA==.',
Wo='Wolfyhunter:BAAANQADCgcIBwAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQAECgIIAgAAAA==.',
Xa='Xane:BAAANQADCgYIDAAAAA==.Xanetia:BAAANQAECgEIAQAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xi='Xinful:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Xint:BAAANQABCgEIAQAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Xo='Xoger:BAAANQABCgQIBAAAAA==.',
Xy='Xyandris:BAAANQAECgIIAgAAAA==.',
['Xï']='Xïbalba:BAAANQABCgIIAgAAAA==.',
Ya='Yamasharma:BAAANQADCgYIEAAAAA==.',
Ye='Yeehaww:BAAANQAECgQICAAAAA==.',
Yy='Yykes:BAAANQABCgIIAgAAAA==.',
Za='Zaharax:BAAANQAECgEIAwAAAA==.Zaharis:BAAANQAECgUICAAAAA==.Zanakari:BAAANQADCgYIEwAAAA==.Zasilia:BAAANQADCgUIBQAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAAANQAECgQICQAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAAANQAECgQIBQAAAA==.',
Zi='Ziba:BAABNQAECoEZAAIWAAgJTxfdJABwAgAWAAgJTxfdJABwAgAAAA==.Zilithus:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Zingermage:BAEANQAECgQIBAAAAA==.Zipzamzoom:BAAANQADCggIAgABNQADCggIEAABAAAAAA==.',
Zo='Zoroo:BAAANQAECgMIBwAAAA==.',
Zr='Zross:BAAANQADCgcIDQAAAA==.',
Zu='Zudo:BAAANQAECgUICgAAAA==.Zuthrais:BAABNQAECoEwAAIGAAkJ0A47KQAwAgAGAAkJ0A47KQAwAgAAAA==.Zuulik:BAAANQADCgYIDgAAAA==.Zuuls:BAAANQADCggICQAAAA==.',
Zz='Zz:BAACNQAFFIEMAAIiAAYJURUiAABKAgAiAAYJURUiAABKAgA1AAQKgSAAAiIACQm+JS4AAPIDACIACQm+JS4AAPIDAAAA.',
['Án']='Ángelpie:BAAANQAECgEIAQAAAA==.',
['Är']='Ärrôw:BAAANQADCgYIAgAAAA==.',
['Ås']='Åshka:BAAANQABCgQIAgAAAA==.',
['Él']='Élryk:BAAANQABCgYIDAAAAA==.',
['ßa']='ßankai:BAAANQADCggIDgABNQAECgUIBgABAAAAAA==.',
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
