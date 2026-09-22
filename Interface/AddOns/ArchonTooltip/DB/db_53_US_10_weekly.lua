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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Holy','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Druid-Feral','Druid-Guardian','Priest-Shadow','Warlock-Demonology','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Hunter-Survival','Warrior-Fury','Evoker-Devastation','Evoker-Augmentation','Mage-Arcane','Mage-Frost','Evoker-Preservation','DemonHunter-Devourer','Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','Paladin-Protection','Priest-Discipline','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Hunter-Marksmanship',}
local provider = {region='US',realm="Aman'Thul",name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aadonis:BAAANQADCgIIAwAAAA==.Aanubus:BAAANQADCggJDQABNQADCggIEAABAAAAAA==.Aarek:BAAANQABCgYIBgABNQAECgMIBAABAAAAAA==.',
Ab='Abyssalmaw:BAAANQAECgUIDwAAAA==.',
Ac='Achillesqt:BAAANQADCgIIAgAAAA==.Acionna:BAAANQADCggIHAAAAA==.',
Ad='Ada:BAAANQADCgIIAgAAAA==.Adekeahokeha:BAAANQADCgYIBQAAAA==.Adrenalin:BAAANQAECgYJDgAAAA==.',
Ae='Aedros:BAAANQAECgQIBQAAAA==.Aegis:BAAANQADCgIIAgAAAA==.Aellan:BAAANQAECgUIDwAAAA==.',
Af='Afflexion:BAAANQAECgYIBgAAAA==.',
Ag='Agonier:BAAANQAECgEIAQAAAA==.',
Aj='Ajira:BAAANQADCgcJDwAAAA==.',
Ak='Akiaki:BAAANQAECgEJAgAAAA==.',
Al='Aladk:BAABNQAECoEeAAMCAAgKLiH4DwDrAgACAAgKLiH4DwDrAgADAAEKUwJCnQAoAAAAAA==.Alafus:BAAANQAECgQIBQABNQAECggIHgACAC4hAA==.Alaldras:BAAANQAECgEIAQAAAA==.Alalock:BAAANQAECggICQABNQAECggIHgACAC4hAA==.Alaria:BAAANQAECgYIEwABNQAECggIGQAEANMdAA==.Alarian:BAABNQAECoEaAAIFAAgKaCPeDgAsAwAFAAgKaCPeDgAsAwAAAA==.Aldai:BAAANQAECgIIAgAAAA==.Alendros:BAAANQAECgIIAgAAAA==.Alexsia:BAAANQADCgEIAQAAAA==.Aliiah:BAAANQADCggICgAAAA==.Alir:BAABNQAECoEhAAIDAAgKPRzBGQCaAgADAAgKPRzBGQCaAgAAAA==.Alista:BAAANQADCgIIAgAAAA==.Alle:BAAANQAECgIIAgAAAA==.Allen:BAAANQAECgUIBgAAAA==.Allyren:BAAANQAECgYIDwAAAA==.Allythriea:BAAANQAECgIIAgAAAA==.Althen:BAAANQADCggICAAAAA==.',
Am='Ambertwo:BAAANQAECgQIBgAAAA==.Amitheria:BAAANQAECgQJCgAAAA==.',
An='Andreb:BAAANQAECgQIBwAAAA==.Andromyda:BAAANQAECgIJAgAAAA==.Angelofnite:BAAANQAECgIJAgAAAA==.Angelofpower:BAAANQADCgYIBgAAAA==.Angrychicken:BAAANQAECgIJAgAAAA==.Ankh:BAAANQAECgUJDQAAAA==.Antopanto:BAAANQAECgUIDAAAAA==.Anubiset:BAAANQADCgUIBQAAAA==.',
Ar='Aralia:BAAANQAECgIIAgAAAA==.Arasmina:BAABNQAECoEhAAIGAAgKryXkBgBrAwAGAAgKryXkBgBrAwAAAA==.Arcanystra:BAAANQAECgIJAgAAAA==.Arcathal:BAABNQAECoEcAAIHAAgKzhyhIgB/AgAHAAgKzhyhIgB/AgAAAA==.Arcshottx:BAAANQAECgUIDgAAAA==.Arliis:BAAANQAECgcJEwAAAA==.Arniy:BAAANQADCgYJDQABNQAECggIGQAEANMdAA==.Artey:BAAANQAECgcJEQAAAA==.',
As='Ascot:BAAANQADCgYJBwABNQAECgUIEAABAAAAAA==.Asenathe:BAAANQADCggIAgAAAA==.Ashaad:BAAANQAECgUJCwAAAA==.Asyluun:BAAANQAECgIJAgAAAA==.',
At='Atorvas:BAAANQADCgMIAwAAAA==.',
Au='Auchioane:BAAANQAECgUIDQAAAA==.Aurelyia:BAAANQAECgQJBgAAAA==.',
Aw='Awakenimg:BAAANQADCgEJAQAAAA==.',
Ay='Ayhai:BAAANQAECgQJBAAAAA==.',
Az='Azador:BAAANQAECgYIDAAAAA==.Azael:BAAANQAECgQIBAAAAA==.Azarion:BAAANQADCgEIAQAAAA==.Azayzel:BAAANQAECgIJAgAAAA==.Azemm:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.Azza:BAAANQADCgcIBwAAAA==.',
['Aé']='Aérfen:BAAANQADCgIJAgAAAA==.',
Ba='Backburner:BAAANQADCgMIAwAAAA==.Badvoodoo:BAABNQAECoEWAAICAAcKORczMwDTAQACAAcKORczMwDTAQAAAA==.Balahara:BAAANQADCgYIBgAAAA==.Balfor:BAAANQAECgUIEQAAAA==.Bandarpallie:BAAANQAECgEJAQAAAA==.Bara:BAAANQABCgMIAwAAAA==.Battlepope:BAAANQADCgIIAgAAAA==.Baynage:BAAANQAECgYIBgAAAA==.',
Be='Beastah:BAAANQADCgUJCAAAAA==.Beauxmax:BAAANQADCgYIBgAAAA==.Beefkakes:BAAANQADCggIGAAAAA==.Belest:BAAANQAECgUJCgAAAA==.Belfhee:BAAANQADCgEIAQAAAA==.Belkelmor:BAAANQAECgIJAgAAAA==.Bellaros:BAAANQAECgQIBgAAAA==.Belè:BAABNQAECoEaAAMIAAgKPReBGgBTAgAIAAgKPReBGgBTAgAJAAEKYQ+KHQA6AAAAAA==.Beorm:BAAANQADCgYICgAAAA==.Bermagi:BAAANQAECgMJBgAAAA==.',
Bi='Biders:BAAANQADCgEIAQAAAA==.Bigarchrules:BAAANQAECgEIAQAAAA==.Bigbanana:BAAANQAECgUICgAAAA==.Bigdaddy:BAABNQAECoEgAAIKAAgK9BmXOwB4AgAKAAgK9BmXOwB4AgAAAA==.Bigole:BAAANQAECgUIBQAAAA==.Bigrilla:BAAANQAECgEJAQAAAA==.Bigsecksi:BAAANQAECgMIAwAAAA==.Bilbearbagns:BAAANQAECgEJAQAAAA==.Billkills:BAAANQADCgIIAgAAAA==.Billpie:BAAANQAECgQIBAAAAA==.Binkei:BAAANQAECgYJBAAAAA==.Bitee:BAAANQAECgQIBAAAAA==.',
Bl='Blacklight:BAAANQABCgEJAQAAAA==.Blacksky:BAAANQAECgEJAQAAAA==.Blade:BAAANQAECgYIDwAAAA==.Blastette:BAAANQADCgYJGQAAAA==.Blayze:BAAANQAECgQIDAAAAA==.Bloodclaw:BAAANQABCgUIBwAAAA==.Bloodgimp:BAAANQAECgUJDQAAAA==.Bloodlust:BAAANQAECgcIDQAAAA==.Bloodslay:BAAANQAECgcJEwAAAA==.Bloodtank:BAAANQADCgYIBgAAAA==.Bluebrood:BAAANQAECgIJAwAAAA==.',
Bo='Boenarrow:BAAANQADCggIDAAAAA==.Bojack:BAAANQAECgUIBgAAAA==.Bombshot:BAAANQAECgIJAwAAAA==.Boomdeeznutz:BAAANQADCgUICwAAAA==.Boomkinbill:BAAANQADCgEIAQAAAA==.Boproblem:BAAANQADCgUIBQAAAA==.Botmage:BAAANQAECgYJDAAAAA==.Bovinei:BAAANQAECgIJAwAAAA==.',
Br='Brackk:BAAANQADCgYIDAAAAA==.Braedaevia:BAAANQAECgcJEgAAAA==.Brahnson:BAAANQADCgQICAAAAA==.Brawlzdeep:BAAANQADCgQIBAAAAA==.Breldyr:BAAANQAECgYIDgAAAA==.Bronnir:BAAANQADCgYICAAAAA==.Brotis:BAAANQADCggIEAAAAA==.Brylen:BAABNQAFFIEXAAILAAcKKiMaAAD/AgALAAcKKiMaAAD/AgAAAA==.',
Bu='Bubblerat:BAAANQAECgEJAQAAAA==.Bullus:BAAANQAECgEIAQAAAA==.Buntz:BAABNQAECoEhAAIKAAgK2SStFQA2AwAKAAgK2SStFQA2AwAAAA==.',
Ca='Caain:BAAANQAECgQJBAAAAA==.Caalypso:BAABNQAECoEmAAIMAAcKAB9qKwBSAgAMAAcKAB9qKwBSAgAAAA==.Caileron:BAAANQAECgIIBQAAAA==.Cakesnpies:BAAANQAECgcJEQAAAA==.Callamedic:BAAANQADCggIBwABNQADCggIEAABAAAAAA==.Callofdeath:BAAANQAECgIJAgAAAA==.Cancelyn:BAAANQADCgYIBwAAAA==.Capsmasher:BAAANQADCgYIBgAAAA==.Carb:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.Cashehm:BAAANQADCggIGQAAAA==.Caströ:BAABNQAECoEWAAMEAAcK8g/GFgCFAQAEAAcK8g/GFgCFAQANAAEKhRWVQwBCAAAAAA==.',
Ce='Cecilbgnome:BAAANQADCgYIAgAAAA==.Celad:BAAANQAECgYIEQAAAA==.Celestina:BAAANQABCgEIAQAAAA==.Cenedra:BAAANQAECgYJEAAAAA==.',
Ch='Chaihard:BAAANQADCgUIBQAAAA==.Cheesenonion:BAAANQADCgYICwABNQAECgYIEwABAAAAAA==.Chocolates:BAAANQADCgIIAgAAAA==.Chromitez:BAAANQAECgYIEQAAAA==.Chroren:BAAANQAECgYIDAAAAA==.Chubberz:BAAANQADCggICgABNQAECgcJEgABAAAAAA==.Churlish:BAAANQAECgYIEgAAAA==.',
Cl='Claptothetop:BAAANQAECgQJCAAAAA==.Clawyaeyeout:BAAANQADCgQIBAAAAA==.Cleavís:BAAANQAECgYIDgAAAA==.Cllu:BAAANQAECgYIBgAAAA==.',
Co='Cogedor:BAAANQADCgEIAQAAAA==.Colourzz:BAAANQADCgYJBgAAAA==.Conflict:BAAANQADCggIDAAAAA==.Coobs:BAAANQADCgYIBgAAAA==.Corepia:BAAANQAECgUICQAAAA==.Cozymonday:BAABNQAECoEaAAMOAAcKTh5TCAApAgAOAAcKFRpTCAApAgAPAAUKFSE8DQDFAQAAAA==.',
Cr='Cramberly:BAAANQAECgUJCgAAAA==.Craystone:BAAANQADCgQIBAAAAA==.Crayzdruid:BAAANQADCgQIBAAAAA==.Crikeys:BAAANQADCgYIDQAAAA==.Crispynips:BAAANQADCggIFQAAAA==.Cristeria:BAEANQAECgYJBgAAAA==.Crnreaper:BAAANQAECgIJAwAAAA==.Crotch:BAAANQABCgIIAgAAAA==.',
Cu='Custodes:BAAANQADCgYJEQAAAA==.',
Da='Dabita:BAABNQAECoEYAAIFAAYKURHycACbAQAFAAYKURHycACbAQAAAA==.Daewong:BAABNQAECoEZAAMEAAgK0x3bCQCRAgAEAAgK0x3bCQCRAgANAAEKuQMySQAvAAAAAA==.Dagami:BAAANQADCggIHAAAAA==.Daiganzan:BAAANQAECgMIAwAAAA==.Daisuke:BAAANQADCgcIGwAAAA==.Dajango:BAAANQAECgYIDwAAAA==.Daknar:BAAANQAECgYIDwAAAA==.Dalenvoidy:BAAANQADCggJGQAAAA==.Damâ:BAAANQADCgYIBgAAAA==.Dandal:BAAANQAECgQJBAAAAA==.Dankharx:BAAANQABCgQIBgAAAA==.Darkelas:BAAANQADCggICAAAAA==.Darknessbull:BAABNQAECoEbAAIKAAgKfxyNMgCeAgAKAAgKfxyNMgCeAgAAAA==.Daronn:BAAANQAECgcIEgAAAA==.Darthas:BAAANQAECgIIAgAAAA==.Dashhunt:BAAANQAECgUJEgAAAA==.Dashlock:BAAANQADCgcJBwABNQAECgUJEgABAAAAAA==.Dashmagic:BAAANQADCgUIBQABNQAECgUJEgABAAAAAA==.Davy:BAAANQAECgcIGAAAAQ==.Daxigar:BAAANQAECgIJAgAAAA==.',
De='Deathkill:BAAANQADCgcIDQAAAA==.Deekay:BAAANQADCgYICAAAAA==.Deeri:BAAANQAECgUIDgAAAA==.Defyndk:BAAANQADCgIIAgABNQAECgIJAwABAAAAAA==.Defynds:BAAANQAECgIJAwAAAA==.Demonesla:BAAANQADCgYIDQAAAA==.Demoslayer:BAAANQADCgUJCwAAAA==.Denardiir:BAAANQAECgMIBgABNQAECgYJEAABAAAAAA==.Desir:BAABNQAECoEYAAIIAAgKURpvFwB2AgAIAAgKURpvFwB2AgAAAA==.Desperate:BAAANQADCgUICgAAAA==.Destanna:BAAANQADCgYIDQAAAA==.Detoxic:BAAANQAECgEIAQAAAA==.Dewdeath:BAAANQAECgMIBQAAAA==.Dewdvoker:BAAANQAECgEJAQAAAA==.',
Di='Diabsoule:BAAANQADCgIIAgAAAA==.Dilendra:BAAANQAECgIIAgABNQAECgcJFgACADkXAA==.Diman:BAAANQADCgUIBQAAAA==.Dingodash:BAAANQAECgEIAQAAAA==.Dinngo:BAAANQABCgEIAQAAAA==.Diseased:BAAANQAECgUIEgAAAA==.Dizzimajizz:BAAANQAECgcIEgAAAA==.',
Dm='Dmgfordays:BAAANQAECgQIDwAAAA==.',
Do='Dogê:BAABNQAECoEYAAIQAAgKfQ02HADvAQAQAAgKfQ02HADvAQAAAA==.Domme:BAAANQAECggJEAAAAQ==.Dornag:BAAANQADCgMIBgAAAA==.Dovakin:BAAANQADCgYICgAAAA==.Downpour:BAAANQAECgMIAwAAAA==.',
Dr='Dragonhopes:BAAANQADCgYIBgAAAA==.Drated:BAAANQADCggIEAABNQAECgkJJgARAIIRAA==.Drazalgor:BAAANQADCggJIQAAAA==.Drepung:BAAANQAECgUIEAAAAA==.Dretlok:BAAANQAECgYIDgAAAA==.Droopyclam:BAAANQABCgQIBAAAAA==.Dryreach:BAAANQADCgEIAQAAAA==.',
Du='Duatani:BAAANQAECgEIAQAAAA==.Duck:BAAANQADCgYICQAAAA==.Duckpunch:BAAANQAECgQIBgAAAA==.Dukhan:BAABNQAECoEXAAISAAgKWAUXEgC5AQASAAgKWAUXEgC5AQAAAA==.Dukkhadk:BAAANQAECgMIBAAAAA==.Durinsoñ:BAAANQAECgYIEQAAAA==.Durzy:BAAANQAECgEJAQABNQAECggJGQATAAIkAA==.Duskaryn:BAAANQAECggJBQAAAA==.',
Dw='Dworglaranna:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.',
Dy='Dying:BAAANQAECgQIBAAAAA==.Dylanspally:BAAANQAECgYIEAAAAA==.Dyrtylox:BAAANQADCgUIBQAAAA==.',
Ea='Eaglekick:BAAANQAECgYJCgAAAA==.Earendill:BAAANQADCgEJAQAAAA==.Easilyamused:BAAANQAECgQJBgAAAA==.',
Ec='Eclips:BAAANQAECgEIAQAAAA==.',
Ed='Eddo:BAAANQADCgcJBwAAAA==.Edrissa:BAAANQADCggJCAAAAA==.',
Eg='Egosumvacca:BAAANQADCgYIBgAAAA==.',
El='Elandiel:BAABNQAECoEmAAQRAAkKghFNSQD5AQARAAgKbw9NSQD5AQAUAAQKuQ1JLAD3AAAVAAEK4wF/JgAhAAAAAA==.Elladale:BAAANQAECgUJCgAAAA==.Ellaxstrasza:BAAANQADCgcJDgAAAA==.Elleryl:BAAANQAECggICgAAAA==.Ellisen:BAAANQADCgcIDgAAAA==.Elryk:BAAANQAECgIIAgAAAA==.Elsaemonk:BAAANQADCggIDAAAAA==.Elynna:BAAANQAECggJCAAAAA==.',
Em='Emmaroids:BAAANQAECgMIAwAAAA==.Emmuu:BAAANQAECggJEgABNQADCggICAABAAAAAA==.',
En='Enjoi:BAAANQADCgQIBAAAAA==.Enoc:BAAANQAECgQJBgAAAA==.',
Er='Ero:BAAANQABCgcJBwAAAA==.',
Et='Etyeehaw:BAABNQAECoEmAAIWAAcKUCTfAQDkAgAWAAcKUCTfAQDkAgAAAA==.',
Ev='Evaêlfie:BAAANQADCgYICQAAAA==.Eviltank:BAAANQAECgMIBAAAAA==.',
Ez='Ezzbot:BAAANQAECgUIDgAAAA==.',
Fa='Fabulously:BAAANQAECgQJCgABNQAECgcIIQAXAPASAA==.Fallèn:BAAANQAECgIJAwAAAA==.Falnyr:BAABNQAECoEuAAIYAAgKKSHOBQABAwAYAAgKKSHOBQABAwAAAA==.Fanchone:BAAANQADCggIDAAAAA==.Fandahvis:BAAANQAECgQICQAAAA==.Fanney:BAAANQADCgIJAgAAAA==.Faroosh:BAAANQADCgYICAAAAA==.Fartshart:BAAANQAECgUJCgAAAA==.Favorite:BAAANQAECgEIAQAAAA==.',
Fe='Fearus:BAAANQABCgYICQAAAA==.Felanthropy:BAAANQAECgQICwAAAA==.Felbunny:BAAANQAECgcIEwAAAA==.Felfliction:BAAANQABCgEIAQAAAA==.Felinae:BAAANQAECgEJAQAAAQ==.Felmagus:BAAANQAECgMIBAAAAA==.Felrrak:BAACNQAFFIEHAAIIAAMKnAd/CADaAAAIAAMKnAd/CADaAAA1AAQKgT8AAggACQpRHFAMAP8CAAgACQpRHFAMAP8CAAAA.Felstro:BAAANQAECgQIBwAAAA==.Felwynbrooke:BAABNQAECoEbAAIWAAcKQhuZAwBTAgAWAAcKQhuZAwBTAgAAAA==.Ferynis:BAAANQAECgEJAQAAAA==.',
Fi='Firekhan:BAAANQAECgcJEwAAAA==.Fistful:BAABNQAECoEhAAIEAAgKyQ5FFACxAQAEAAgKyQ5FFACxAQAAAA==.',
Fl='Flador:BAAANQAECgYIDQAAAA==.Flickatotem:BAAANQAECgMJAwABNQAECgcIHwAZAG4DAA==.Florinka:BAAANQAECgIIAgAAAA==.Fluffydecay:BAAANQADCgEIAQABNQAECgcIEAABAAAAAA==.Flumble:BAAANQADCgQICAAAAA==.Fluticasone:BAAANQADCggJCAAAAA==.',
Fo='Forgedhorny:BAAANQADCgYIDAAAAA==.Forxiga:BAAANQAECgUICAAAAA==.Fourcheeks:BAABNQAECoEcAAIGAAgKbxCOQQDuAQAGAAgKbxCOQQDuAQAAAA==.Fourthchild:BAAANQADCgQIBAAAAA==.Fozzydk:BAAANQADCgYIBgAAAA==.',
Fr='Frell:BAAANQADCgQIBAAAAA==.Frez:BAAANQAECgIIBAAAAA==.Frierén:BAAANQADCggIFAAAAA==.Frisli:BAAANQAECgQIBAAAAA==.Frostburn:BAAANQABCgIIAQABNQADCggIHgABAAAAAA==.Frostlass:BAAANQAECgMJAwAAAA==.Frostveil:BAAANQAECgMIAwABNQAECggJBQABAAAAAA==.Frostyflakez:BAAANQAECgUIBwAAAA==.Frostyfruit:BAAANQAECgcIEQAAAA==.',
Fu='Furnous:BAABNQAECoErAAMaAAgKYg/hgwANAgAaAAgKYg/hgwANAgAbAAEK6BDGMAA3AAAAAA==.Fuzzydks:BAAANQADCggJFAABNQAECgYIDAABAAAAAA==.',
Ga='Galenddrel:BAAANQADCgIIAwAAAA==.Gant:BAAANQADCgYIDgAAAA==.Gargamus:BAAANQAECgQIBQAAAA==.',
Ge='Gemashdk:BAAANQADCgcICQABNQAECgYICwABAAAAAA==.Gemashrogue:BAAANQAECgYICwAAAA==.Gemtastic:BAAANQADCgQJBAAAAA==.Georgieanne:BAAANQADCggIEwAAAA==.',
Gh='Ghazali:BAAANQADCggICAAAAA==.Gheru:BAAANQAECgMIBAAAAA==.Ghoolies:BAAANQADCgYJGQABNQAECgYIDQABAAAAAA==.',
Gi='Gigadeekay:BAAANQADCgYIBgAAAA==.Gildartz:BAAANQAECgEIAQAAAA==.',
Gl='Glitterspark:BAAANQAECgMIBQAAAA==.Glittr:BAAANQAECgYJEAABNQAFFAMIBwAYANUSAA==.Glitty:BAACNQAFFIEHAAMYAAMK1RLkBAD3AAAYAAMK1RLkBAD3AAAcAAEK+AidDgBPAAA1AAQKgTYAAxgACQqIIvUCAF0DABgACQqIIvUCAF0DABwAAgqIFTwyAIAAAAAA.Glodslock:BAAANQAECgIJAwAAAA==.',
Go='Goated:BAAANQADCggIHgAAAA==.Goliathxx:BAAANQAECgEIAQAAAA==.Gonewe:BAAANQAECgIIBQAAAA==.Gongaga:BAAANQADCgYICQAAAA==.Googam:BAAANQAECgcJEgAAAA==.Gornuts:BAAANQAECgUIDQAAAA==.Gosly:BAABNQAECoEZAAIQAAgKGh/iCwDmAgAQAAgKGh/iCwDmAgAAAA==.Gozhuntsurv:BAAANQABCgEIAQAAAA==.Gozrogueolaw:BAAANQADCgUIBQAAAA==.',
Gr='Grailliford:BAAANQAECgQICwAAAA==.Grayfox:BAAANQAECgQIBAAAAA==.Greeneyes:BAAANQADCgYICQAAAA==.Grelle:BAAANQADCggIDAAAAA==.Grimlock:BAAANQADCggICAAAAA==.Grimthursday:BAAANQADCggJHQABNQAECgUJEgABAAAAAA==.Grip:BAAANQAECgcIDwAAAA==.Groxigar:BAAANQADCgQIBAAAAA==.Groxom:BAAANQADCgUIBQAAAA==.Grumpu:BAAANQADCgcIDwAAAA==.Grutok:BAAANQAECgMIBAAAAA==.',
Gu='Guldann:BAAANQABCgEIAQAAAA==.Guzwar:BAAANQAECgMIBgAAAA==.',
Gw='Gwydeon:BAAANQADCgMJAwABNQAECgEJAQABAAAAAA==.',
Gy='Gyftable:BAAANQAECgUIDQAAAA==.Gyokuro:BAAANQABCgYIBwAAAA==.Gypsierose:BAAANQAECgQJCgAAAA==.',
['Gí']='Gíngervítis:BAAANQADCgEIAQAAAA==.',
['Gï']='Gïmli:BAAANQAECgEJAQAAAA==.',
['Gò']='Gòrilla:BAAANQADCgYICgAAAA==.',
Ha='Haahuna:BAAANQADCgIJAgAAAA==.Hairytoad:BAABNQAECoElAAITAAYKewxXSQA+AQATAAYKewxXSQA+AQAAAA==.Hakoda:BAAANQADCgcJCQABNQADCggIEgABAAAAAA==.Hardlightsgt:BAAANQADCgIIAgAAAA==.Harriet:BAAANQADCgMJAwAAAA==.Harubless:BAAANQADCggICAAAAA==.Harushear:BAACNQAFFIESAAIdAAcKpRxyAACpAgAdAAcKpRxyAACpAgA1AAQKgSAAAh0ACQrfJfEBALUDAB0ACQrfJfEBALUDAAAA.Harushorn:BAAANQAECgUIBwAAAA==.Haruvion:BAAANQAECgcJBwABNQAFFAcIEgAdAKUcAA==.Harvester:BAAANQAECgUJCwAAAA==.Havocbringer:BAAANQAECgUICQAAAA==.',
He='Headaxe:BAAANQAECgQJCAAAAA==.Healmemutt:BAAANQAECgQIBQAAAA==.Hearte:BAABNQAECoEcAAISAAgKpxz2BgDJAgASAAgKpxz2BgDJAgAAAA==.Hellweaver:BAAANQADCgYIBgAAAA==.Hermano:BAAANQAECgUIEQABNQAECgcIDwABAAAAAA==.Hermiscuous:BAAANQAECgcIDwAAAA==.Hermy:BAAANQAECgYICwABNQAECgcIDwABAAAAAA==.Herpys:BAAANQADCgYIBgAAAA==.Hexmachine:BAAANQAECgYICgAAAA==.',
Hi='Hinotori:BAAANQADCgYJDwAAAA==.Hinters:BAAANQAECgUICgAAAA==.',
Ho='Hogglee:BAAANQADCgYIBgAAAA==.Holing:BAABNQAECoEhAAIeAAgKniFJHgD1AgAeAAgKniFJHgD1AgAAAA==.Holybm:BAAANQADCgUICgAAAA==.Holyhealz:BAEANQAECgEJAgAAAA==.Holymama:BAAANQAECgYJBgAAAA==.Holymoly:BAAANQADCgEIAQAAAA==.Honeyduke:BAAANQAECgYIEAAAAA==.Hopenottodie:BAAANQAECgQJDAAAAA==.Hopes:BAAANQAECgUIDQAAAA==.',
Hr='Hrulgath:BAAANQADCgQIAwAAAA==.',
Hu='Humbler:BAAANQADCgcICAAAAA==.Huntum:BAAANQADCgUIBQAAAA==.Huntzha:BAAANQAECgQIBQAAAA==.',
Hy='Hyndis:BAAANQAECgEJAQAAAA==.Hyorinmâru:BAAANQAECgUIDgAAAA==.',
['Hí']='Híppiechick:BAAANQAECgQICAAAAA==.',
Ia='Iamoutofammo:BAAANQAECgMJAwAAAA==.Ianix:BAAANQAECgYIDAAAAA==.',
Ic='Icanhelp:BAAANQADCgUJBQAAAA==.Iceni:BAAANQAECgYIDgAAAA==.Icepick:BAAANQADCggJCAABNQADCggIEAABAAAAAA==.',
Id='Idíot:BAAANQAECgIIBQAAAA==.',
If='Ifelforu:BAAANQAECgcIDgAAAA==.',
Ih='Ihaslegs:BAAANQAECgEIAQAAAA==.Ihitstuf:BAAANQAECgIIAgAAAA==.',
Il='Ilidun:BAAANQABCgIJAQAAAA==.Illimoo:BAAANQAECgQIBgAAAA==.Ilumminus:BAAANQADCgQIBwABNQADCggIHwABAAAAAA==.',
Im='Imoldgrèg:BAAANQADCgMIAwABNQAECgYIEQABAAAAAA==.',
In='Incineratus:BAAANQAECgYIDwAAAA==.Ineci:BAAANQADCgYJGQAAAA==.Infurrnal:BAAANQAECgUJDgAAAA==.Innerpeace:BAAANQAECgIJBAAAAA==.Inspirez:BAAANQADCgYJFgAAAA==.Instamissed:BAAANQADCgUIBQAAAA==.Intolerence:BAAANQADCggJEAAAAA==.',
Ip='Ipooptotems:BAAANQAECgIIAgAAAA==.',
Ir='Ironbeard:BAAANQADCgMIAwAAAA==.',
Is='Ishathon:BAAANQAECgEIAQAAAA==.Ishootstuff:BAABNQAECoEYAAIFAAcKlx3/PwA3AgAFAAcKlx3/PwA3AgAAAA==.',
It='Itsnotbatman:BAAANQAECgYJEQAAAA==.',
Iv='Ivanra:BAABNQAECoEYAAIWAAgK5R62AQD1AgAWAAgK5R62AQD1AgAAAA==.',
Iy='Iyna:BAAANQADCgUIBQAAAA==.',
Iz='Izlek:BAAANQAECgcIEgAAAA==.',
['Iì']='Iìe:BAAANQAECgYIEgAAAA==.',
Ja='Jagermaster:BAAANQADCgYIDQAAAA==.Janeygirl:BAAANQAECgUJDgAAAA==.',
Jc='Jcx:BAAANQADCgYJDgABNQAECgIJBAABAAAAAA==.',
Je='Jeningo:BAAANQABCgcICAAAAA==.Jeningze:BAAANQAECgEIAQAAAA==.Jestiny:BAAANQAECgQJBwAAAA==.Jezebel:BAAANQADCgYJGQAAAA==.',
Jo='Johannuz:BAAANQAECgcIDgAAAA==.Johngoblikon:BAAANQAECgQIBgAAAA==.Johnyf:BAAANQAECgIJAgAAAA==.Jonesy:BAABNQAECoEYAAIfAAgK1BJRDADMAQAfAAgK1BJRDADMAQAAAA==.Joneszy:BAAANQAECgEJAQAAAA==.Jononononono:BAABNQAECoEbAAIEAAcKpxyLDABKAgAEAAcKpxyLDABKAgAAAA==.Jonz:BAAANQAECgcJDwAAAA==.Jorabelia:BAAANQAECgMIAwAAAA==.Joshington:BAABNQAECoEYAAIFAAcKPCPwJgCbAgAFAAcKPCPwJgCbAgAAAA==.Jotuunnz:BAAANQADCgUIBQAAAA==.Jox:BAAANQADCgQIBAAAAA==.',
Ju='Juícyfruít:BAAANQABCgQIBwAAAA==.',
Ka='Kahlia:BAAANQADCgcIFgAAAA==.Kaiden:BAAANQADCgYIBgAAAA==.Kalanix:BAAANQAECgQJCgAAAA==.Kalji:BAAANQADCgcIBwABNQAECggIGQAEANMdAA==.Kanatari:BAAANQAECgQIBQAAAA==.Kansch:BAAANQADCgMIAwABNQAECggJLAAgAPgbAA==.Karaleigh:BAABNQAECoEcAAIEAAgKqwmiFgCHAQAEAAgKqwmiFgCHAQAAAA==.Katallia:BAAANQAECgQJBgAAAA==.Kateley:BAAANQAECgUIBwAAAA==.Kattadin:BAAANQAECgQJBAAAAA==.Kaybs:BAAANQAECgYICgAAAA==.',
Ke='Keanoo:BAAANQAECgQIBwAAAA==.Kekai:BAAANQABCgQICQAAAA==.Kelanthus:BAAANQAECgUJEQAAAA==.Kellalas:BAAANQADCgUIEAAAAA==.Kelvinator:BAAANQAECgIJAgAAAA==.Kernni:BAAANQAECgMIBQAAAA==.Kes:BAAANQAECgQIBgAAAA==.Kews:BAAANQADCgYJBgAAAA==.',
Kh='Khades:BAAANQADCgMJAwAAAA==.',
Ki='Kirisera:BAAANQAECgEIAgAAAA==.Kirstii:BAAANQADCgYIBgAAAA==.Kitkatzippy:BAAANQADCgQJBAAAAA==.Kittymik:BAEANQAECgYJEAAAAA==.Kixa:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.',
Kl='Klawfel:BAAANQADCgYICwAAAA==.',
Kn='Knöwledge:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ko='Kohatu:BAAANQABCgIIAgAAAA==.Komoekomoe:BAAANQADCgUIAgAAAA==.Kormath:BAAANQAECgEJAQAAAA==.Korrack:BAAANQAECgIJAwAAAA==.Korruptoor:BAAANQABCgQIBAAAAA==.Kotath:BAAANQADCgUIBwAAAA==.Kowbruh:BAAANQADCgYICwAAAA==.Kower:BAAANQADCgQIBAAAAA==.',
Kr='Krianlan:BAAANQAECgEJAQABNQAECggJBQABAAAAAA==.',
Ku='Kuddy:BAAANQAECgYIEgAAAA==.Kumamizu:BAAANQAECgIJAgAAAA==.',
Kw='Kwee:BAAANQAECgYJBQAAAA==.Kwr:BAAANQAECgEJAQAAAA==.Kwyn:BAAANQADCgYJGQABNQAECgYIDgABAAAAAA==.',
Ky='Kyeon:BAAANQADCgQJBAAAAA==.Kyxa:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.',
['Kè']='Kèw:BAAANQADCggJGQAAAA==.',
La='Lacronista:BAAANQAECgQJBgAAAA==.Lagavulin:BAAANQAECgYJEAAAAA==.Lalatinaford:BAAANQAECgIIAgAAAA==.Lambdadelta:BAAANQADCgIIAgAAAA==.Landacious:BAAANQADCgUIBQAAAA==.Lanthendis:BAAANQADCgEJAQAAAA==.Lazerchìckèn:BAAANQADCgQIBAAAAA==.',
Le='Lebronjr:BAABNQAECoEXAAIhAAgK4BqLDABaAgAhAAgK4BqLDABaAgAAAA==.Leella:BAAANQAECgEIAQAAAA==.Leere:BAAANQADCgYIBgAAAA==.Leeshpal:BAAANQADCgYICAAAAA==.Legolash:BAAANQAECgYIDwAAAA==.Lemerix:BAAANQADCgUIBwAAAA==.Leniisha:BAAANQAECgQJBgAAAA==.Lewy:BAAANQAECggJBgAAAA==.Lexicon:BAAANQAECgUIDQAAAA==.Lexxen:BAABNQAECoEgAAIHAAkKLSGDBAB/AwAHAAkKLSGDBAB/AwAAAA==.Leàfy:BAAANQAECgYIEQAAAA==.',
Li='Lightblade:BAAANQAECgUJEgAAAA==.Lilibewhan:BAAANQABCgEIAQAAAA==.Limonae:BAAANQAECgUIEwAAAA==.Lisellee:BAAANQADCgIIAgABNQAECgIIBQABAAAAAA==.',
Ll='Lljunior:BAAANQABCgMIAwAAAA==.',
Lo='Locha:BAAANQAECgEIAgAAAA==.Lockstøck:BAAANQAECgUICAAAAA==.Longicorn:BAAANQADCgYIBgABNQAECgkJHwAGAE8fAA==.Lostváyne:BAAANQADCgYJBgAAAA==.Lovemylamb:BAAANQAECgEIAQABNQAFFAUICgAUAMsVAA==.',
Ls='Ls:BAAANQAECggIEQAAAA==.',
Lu='Ludal:BAAANQADCgYJGAAAAA==.Luketism:BAAANQAECgUICQAAAA==.Lunarrage:BAAANQADCgUIBQAAAA==.Lunen:BAABNQAECoEhAAIPAAgKMhygBgB9AgAPAAgKMhygBgB9AgAAAA==.Lusidity:BAAANQADCggIDgAAAA==.',
Ly='Lyraria:BAAANQADCgIIAgAAAA==.Lythorn:BAAANQAECgUIBwAAAA==.',
['Lè']='Lèpton:BAAANQAECgEIAwAAAA==.',
['Lé']='Léäf:BAAANQAECgUIDgAAAA==.',
['Lõ']='Lõx:BAABNQAECoEXAAIRAAgKQCGdEAAIAwARAAgKQCGdEAAIAwAAAA==.',
Ma='Macloven:BAAANQAECgIJAgAAAA==.Madamgrey:BAAANQAECgUJDgAAAA==.Maebyfunke:BAAANQADCggICAAAAA==.Magestørm:BAAANQAECggIEwAAAA==.Magicboi:BAAANQADCgcIEQAAAA==.Magicmagnus:BAAANQADCggJGAAAAA==.Magictacos:BAABNQAECoEaAAIQAAcKSh/TEQCCAgAQAAcKSh/TEQCCAgAAAA==.Magistrasza:BAABNQAECoEhAAIaAAgKuwqMlgDfAQAaAAgKuwqMlgDfAQAAAA==.Majkusanagi:BAAANQAECgYJDgAAAA==.Makisig:BAAANQAECgYICwAAAA==.Malfy:BAAANQAECgEJAQAAAA==.Malvnaire:BAAANQAECgUJBQAAAA==.Mancrak:BAAANQADCgIIAgAAAA==.Maraach:BAAANQAECgYIDAAAAA==.Mariandor:BAAANQAECgIJAwAAAA==.Marlinn:BAABNQAECoEbAAIFAAgKFw7STAAMAgAFAAgKFw7STAAMAgABNQAFFAUIDQANAHoRAA==.Marlos:BAAANQAECgMIBAAAAA==.Marrmite:BAAANQADCgYIBgAAAA==.Marthaus:BAAANQADCgcJEgABNQAECgUJEgABAAAAAA==.Martmist:BAAANQAECgUJEgAAAA==.Mateo:BAAANQADCggIEgAAAA==.Mathias:BAAANQAECgQJBgAAAA==.Mattiass:BAAANQAECgMIBgAAAA==.Mattrik:BAAANQAECgYIDgAAAA==.Maulyou:BAAANQAECgYIBgAAAA==.Maximilia:BAABNQAECoEaAAIdAAgKQSHRCwD1AgAdAAgKQSHRCwD1AgAAAA==.Maydayx:BAABNQAECoEYAAIeAAgK4Bu3MACUAgAeAAgK4Bu3MACUAgABNQAFFAQJCwAIAL0XAA==.',
Mc='Mcdoom:BAAANQAECgcIEAAAAA==.Mcduff:BAAANQADCggIGgAAAA==.',
Me='Meaningreen:BAAANQADCgcIEAAAAA==.Mekuntizichi:BAAANQADCgcICAAAAA==.Melazaelf:BAAANQADCgYIDQAAAA==.Melzas:BAAANQADCgIIAgAAAA==.Mermoo:BAAANQAECgIIAgAAAA==.Messages:BAAANQAECgQIBAAAAA==.',
Mi='Midknîght:BAAANQADCgIIAgABNQAECgIJAwABAAAAAA==.Midwa:BAACNQAFFIEOAAIeAAUKIiFDAgDjAQAeAAUKIiFDAgDjAQA1AAQKgSQAAh4ACQqhJqEBAOwDAB4ACQqhJqEBAOwDAAAA.Miishah:BAAANQAECgYICwAAAA==.Minisaph:BAAANQADCgcIBwAAAA==.Missfun:BAAANQAECgYICwAAAA==.Mistel:BAAANQAECgUIBQAAAA==.Mistyfuzz:BAAANQAECgQJCQAAAA==.Mithrendir:BAAANQADCggIHwAAAA==.',
Mo='Mogimp:BAAANQADCgQIBwABNQAECgUJDQABAAAAAA==.Moguette:BAAANQAECgYIDAABNQAECgYIDAABAAAAAA==.Moistroll:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Molith:BAAANQABCgYICAAAAA==.Monkkha:BAAANQADCgYICAAAAA==.Montecarlo:BAAANQAECgYIEwAAAA==.Moonhill:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Moonrain:BAAANQABCgYJBgAAAA==.Moordenaar:BAAANQAECgYIDwAAAA==.Moosy:BAAANQAECgMIAwAAAA==.Morala:BAAANQADCgYIBgAAAA==.Morathia:BAAANQADCgIIAgAAAA==.Morgainne:BAAANQADCgEIAQAAAA==.Morphia:BAAANQADCgYIBgAAAA==.Morsoc:BAAANQAECgQIBAAAAA==.Mortarius:BAAANQAECgIIAgAAAA==.Movicol:BAAANQAECgUJBwAAAA==.Mozire:BAAANQAECgIJAwAAAA==.Moñklee:BAAANQADCgUIBgABNQADCgcIDQABAAAAAA==.',
Mt='Mth:BAAANQAECgUICAAAAA==.Mtnaan:BAAANQAECgEJAQAAAA==.',
Mu='Muerteamigo:BAAANQADCgMIAQAAAA==.Murz:BAAANQADCggIEQAAAA==.Musch:BAAANQADCgYIBgABNQAECggJLAAgAPgbAA==.Musde:BAABNQAECoEsAAMgAAgK+BvUDQCLAgAgAAgK+BvUDQCLAgATAAEKIgWmjQAjAAAAAA==.Musterick:BAAANQAECgIJBAAAAA==.Muther:BAAANQAECgQJDAAAAA==.',
My='Myctlan:BAAANQAECgEIAQAAAA==.Mylie:BAAANQABCgQIBwAAAA==.Myrddn:BAAANQAECgIIBQAAAA==.Myrdi:BAAANQADCgYICgABNQAECgMIBAABAAAAAA==.Myrsham:BAAANQAECgMIBAAAAA==.Mytearsheal:BAAANQAECgQICwAAAA==.Mythbrediir:BAAANQAECgYJEAAAAA==.',
['Mü']='Müläflaga:BAAANQADCggJCQAAAA==.',
Na='Naadina:BAAANQADCgYJFQAAAA==.Nadazarter:BAAANQAECgQICgAAAA==.Naggo:BAAANQADCgYIBwAAAA==.Nalph:BAAANQAECgUJBQAAAA==.Narassii:BAAANQADCgMIAwAAAA==.Narmaak:BAAANQADCgQIBAAAAA==.Nathun:BAAANQAECgIIBAAAAA==.Navillas:BAAANQAECgQICwAAAA==.Nayha:BAAANQAECgEIAQAAAA==.',
Ne='Nebulachimi:BAABNQAECoEsAAITAAgKJwi6PACNAQATAAgKJwi6PACNAQAAAA==.Nebulahikari:BAAANQADCgYJBgAAAA==.Nebularyu:BAAANQAECgMIBAAAAA==.Nedimus:BAAANQAECgQIEgABNQAECgEIAgABAAAAAA==.Nekhrimah:BAAANQAECgYIDQAAAA==.Neoaerith:BAAANQAECgYJDQAAAA==.Nerii:BAAANQAECgIJAgAAAA==.Nerpthas:BAAANQAECgQICAAAAA==.Neverlinkx:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ni='Niagarafall:BAAANQADCgIIAgAAAA==.Nidalàp:BAAANQADCgcIBwAAAA==.Nieriality:BAAANQAECgQIEgAAAA==.Nightshana:BAAANQADCgEIAQAAAA==.Nightslay:BAAANQABCgEIAQAAAA==.Nilin:BAAANQAECgYIEAAAAA==.Nina:BAAANQAECgYICgABNQABCgIIAgABAAAAAA==.Nisulus:BAAANQADCggIGwAAAA==.Niteañgel:BAAANQAECgIJAgAAAA==.Niç:BAAANQAECgYIDwAAAA==.',
No='Noala:BAAANQADCgQIBAAAAA==.Noctuana:BAAANQADCgYIGgABNQAECgMIBQABAAAAAA==.Nojruh:BAAANQADCgQICAAAAA==.North:BAABNQAECoEeAAIPAAkKdA+lDADRAQAPAAkKdA+lDADRAQAAAA==.Notbeezy:BAAANQAECgcIEQAAAA==.Nox:BAABNQAECoEXAAIQAAkKbRqsDQDFAgAQAAkKbRqsDQDFAgAAAA==.',
Nu='Numbnut:BAAANQADCgQIBAAAAA==.Numbskull:BAAANQADCgYICgAAAA==.Numnutts:BAAANQAECgYIEQAAAA==.Nutelle:BAAANQADCgYIBwAAAA==.',
['Nè']='Nèrp:BAAANQAECgcJEgAAAA==.',
['Nú']='Númenórean:BAABNQAECoEcAAIFAAcKjwmHbgCiAQAFAAcKjwmHbgCiAQAAAA==.',
['Nü']='Nüts:BAAANQAECgYIDQAAAA==.',
Oa='Oathorr:BAAANQADCgQIBAAAAA==.',
Ob='Obadiah:BAAANQADCgcIEwAAAA==.',
Og='Ogriv:BAAANQADCgUIBwAAAA==.',
Oi='Oii:BAAANQAECgEIAQAAAA==.',
Ol='Olunaija:BAAANQAECgQJBAAAAA==.',
Om='Omm:BAEANQAECgIIBQAAAA==.Omninan:BAAANQABCgEIAQAAAA==.',
On='Onlyclaws:BAAANQAECgcIBwAAAA==.',
Oo='Oos:BAAANQADCgQIBAAAAA==.',
Or='Oroqen:BAAANQAECgQIBgAAAA==.',
Ou='Ouchiheal:BAABNQAECoEXAAIMAAcKjRIeUQCkAQAMAAcKjRIeUQCkAQAAAA==.',
Ov='Overhealer:BAABNQAECoEeAAMHAAkKPxeDHAClAgAHAAkKPxeDHAClAgAiAAIKZAORFwBTAAAAAA==.',
['Oà']='Oàthor:BAAANQAECgEJAgAAAA==.',
Pa='Pachi:BAAANQAECgEJAQAAAA==.Padfoot:BAAANQABCgEIAQAAAA==.Paladipuss:BAAANQADCggIEgAAAA==.Paladumb:BAACNQAFFIEHAAIeAAMKiRO+CAD5AAAeAAMKiRO+CAD5AAA1AAQKgUYAAx4ACQqJH74VACwDAB4ACQqJH74VACwDACEAAQoQCltQACcAAAAA.Palatism:BAAANQAECgYIDgAAAA==.Pallywings:BAAANQAECgYJBgAAAA==.Panchovy:BAACNQAFFIENAAINAAUKehFTAwCDAQANAAUKehFTAwCDAQA1AAQKgSIAAg0ACQpKIncFAEcDAA0ACQpKIncFAEcDAAAA.Parrexion:BAAANQADCgEJAQAAAA==.',
Pe='Peculiar:BAAANQAECgMJBAAAAA==.Pegor:BAAANQADCgEIAQABNQAECgIIBQABAAAAAA==.Pegz:BAAANQADCgYIBgAAAA==.Pegzpaladin:BAAANQADCgcIBwAAAA==.Peps:BAAANQADCggICAAAAA==.Peseshet:BAAANQAECgQJBgAAAA==.',
Ph='Phantom:BAAANQADCgQIBQAAAA==.Phazonicide:BAAANQAECgIJAgAAAA==.Phlaea:BAAANQAECgUIDQAAAA==.',
Pi='Pieata:BAAANQADCggIFAAAAA==.',
Pl='Plazistank:BAAANQADCggICAABNQAECgUJCgABAAAAAA==.Plazzmma:BAAANQADCgMIAwABNQAECgUJCgABAAAAAA==.',
Po='Pogo:BAAANQAECgQICAAAAA==.Poisoning:BAAANQAECgUIBQAAAA==.Poknat:BAAANQADCggICAAAAA==.Polkievoke:BAAANQADCgUJBQAAAA==.Pomdoes:BAAANQADCgMIAwAAAA==.Poppylotus:BAAANQADCggJKgAAAA==.Poppyrift:BAAANQADCggJCQAAAA==.Postee:BAAANQADCggIEAAAAA==.Powerrager:BAAANQAECgEIAQAAAA==.',
Pr='Precioùs:BAAANQAECgUJEgAAAA==.Prettyhectic:BAABNQAECoEWAAIMAAcKfhxdMAA4AgAMAAcKfhxdMAA4AgAAAA==.Priincebun:BAAANQAECggICAAAAA==.Prinsesdonut:BAAANQAECgYIDgAAAA==.Projecjx:BAAANQADCgYICgAAAA==.Protagonist:BAACNQAFFIELAAIIAAQKICM9AwCvAQAIAAQKICM9AwCvAQA1AAQKgSAAAwgACQoFJCAJADEDAAgACAroIyAJADEDAB0ABQpVFI00ADUBAAE1AAUUBwgXAAsAKiMA.Proz:BAAANQADCgYIBgAAAA==.Prozium:BAAANQAECgYJEAABNQADCgYIBgABAAAAAA==.',
Pu='Purifythis:BAAANQADCgMIAwAAAA==.',
Py='Pyrotic:BAAANQADCgYICAAAAA==.Pyschotic:BAAANQADCgQIBAAAAA==.',
['Pä']='Pänya:BAAANQADCgUIBQAAAA==.',
['Pê']='Pêpsï:BAAANQABCgEIAgAAAA==.',
Qu='Quag:BAAANQADCgYJCAAAAA==.Quinny:BAAANQAECgYIDgAAAA==.Quintar:BAABNQAECoEgAAIHAAkKshn6HACiAgAHAAkKshn6HACiAgAAAA==.',
Ra='Raagnar:BAAANQAECgEJAQAAAA==.Rabbage:BAAANQAECgYJDwAAAA==.Raeka:BAABNQAECoEYAAMNAAcKQyUoCQD6AgANAAcKQyUoCQD6AgAEAAEKhwx1NgA1AAAAAA==.Raenda:BAAANQADCgYICgAAAA==.Ragarlem:BAAANQADCggIFgAAAA==.Ragefright:BAAANQAECgYJBgABNQAECgkJFwAQAG0aAA==.Rageie:BAAANQAECgQIBwAAAA==.Rageieboop:BAAANQAECgMIBQAAAA==.Ragemore:BAAANQAECgYIEAAAAA==.Rahvine:BAAANQADCggIHAAAAA==.Raiteq:BAAANQAECgcJEwAAAA==.Raitev:BAAANQAECgMIAwABNQAECgcJEwABAAAAAA==.Ramirezz:BAAANQADCggJCAABNQAECgIJAwABAAAAAA==.Ranmaoo:BAAANQAECgcJCAABNQABCgIIAgABAAAAAA==.Raputami:BAABNQAECoEZAAMLAAgKJRFFPQAEAgALAAgKJRFFPQAEAgAMAAEKewO25QAcAAAAAA==.Rastoons:BAAANQAECgIIBQAAAA==.Rawlôck:BAABNQAECoEhAAMRAAgKQRtaJwCGAgARAAgKQRtaJwCGAgAUAAMKsxAeOgC1AAAAAA==.Raxor:BAAANQAECgIIAwAAAA==.Raya:BAAANQAECgUJCgAAAA==.',
Rd='Rde:BAAANQAECgUJBQAAAA==.',
Re='Redoctobah:BAAANQAECgIJAgAAAA==.Regret:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reignrott:BAAANQAECgUIDgAAAA==.Reika:BAAANQAECgQIBAAAAA==.Replaceable:BAAANQABCgIIAwABNQAECgcJDwABAAAAAA==.Reptizzle:BAAANQADCgQIBAAAAA==.Restorer:BAAANQAECgEIBAAAAA==.Retalica:BAAANQAECgMIBAAAAA==.Retrishi:BAAANQAECgYJEgAAAA==.Retxbladés:BAAANQADCgUIDgAAAA==.Revelstat:BAAANQADCgQIBgAAAA==.Reverb:BAAANQAECgcJDwAAAA==.Rexonon:BAAANQAECgQIBAABNQAECggIGgALAJcUAA==.Rexsham:BAABNQAECoEaAAMLAAgKlxTnNwAfAgALAAgKlxTnNwAfAgAMAAEKliUDugBpAAAAAA==.Rexyclog:BAAANQAECgIIBQAAAA==.Reyku:BAAANQAECgQJBwAAAA==.',
Rh='Rhydon:BAAANQAECgEJAQAAAA==.',
Ri='Ricard:BAAANQADCggJCAAAAA==.Rickettsia:BAAANQAECgYIDwAAAA==.Rig:BAAANQADCggJCAABNQAECggIFQAKAO8aAA==.Rildis:BAAANQAECgQIBAABNQAECgUIDgABAAAAAA==.Rippen:BAAANQADCgYIDQAAAA==.Ritasu:BAAANQAECgEIAQAAAA==.',
Rl='Rlain:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.',
Ro='Robyngdfelow:BAAANQAECggIEAAAAA==.Rohovart:BAAANQAECgIJAgAAAA==.Rollingrick:BAAANQAECgYIEAAAAA==.Roseleaf:BAAANQABCgEIAQAAAA==.',
Rp='Rpro:BAAANQADCgEIAQAAAA==.',
Rr='Rroach:BAAANQAECgYIDwAAAA==.',
Ru='Runaway:BAAANQAECgIIAgAAAA==.Rustycrack:BAAANQAECgQIBwAAAA==.Ruul:BAAANQAECgEIAQAAAA==.',
Ry='Ryana:BAAANQABCgMIAwAAAA==.Ryilla:BAAANQAECgQIBAAAAA==.Rynoe:BAAANQAECgQJBAAAAA==.Ryri:BAAANQADCgEJAQAAAA==.Ryujinx:BAAANQADCgEIAQAAAA==.',
['Rá']='Ráric:BAAANQAECgIIAgAAAA==.',
['Ré']='Rémymartin:BAAANQADCggJDgABNQADCggIEAABAAAAAA==.',
Sa='Sableman:BAAANQADCgYIEQAAAA==.Saccromycaes:BAAANQAECgcJBwAAAA==.Saclem:BAAANQAECgIIAgAAAA==.Saha:BAAANQAECgMIBAAAAA==.Saintayah:BAAANQAECgYIEgAAAA==.Salokin:BAAANQAECgEIAQABNQAFFAUJDAACAHAaAA==.Salorellin:BAABNQAECoEhAAIdAAgKDyEYDADxAgAdAAgKDyEYDADxAgAAAA==.Sam:BAAANQABCgEIAQAAAA==.Sandrèena:BAAANQAECgYIDgAAAA==.Sanity:BAAANQAECgEJAQAAAA==.Sarakatawen:BAAANQAECgIIAgAAAA==.Sarumash:BAAANQAECgMIAwAAAA==.Satanah:BAAANQADCgYJDQAAAA==.Satomi:BAAANQAECgMIAwAAAA==.Satre:BAABNQAECoEWAAIZAAgKhxjzBAAyAgAZAAgKhxjzBAAyAgAAAA==.',
Se='Seculoe:BAAANQAECgYJDQAAAA==.Seedypete:BAAANQADCgcIDQAAAA==.Seemébloody:BAAANQAECgQIAwAAAA==.Seldarine:BAAANQAECgUJBQAAAA==.Selten:BAAANQAECgMIBAAAAA==.Sendel:BAAANQADCgQIBAAAAA==.Senele:BAAANQAECgEIAgAAAA==.Senescence:BAACNQAFFIEKAAQUAAUKyxWEAwDKAAAUAAIK/xyEAwDKAAARAAIKFhGFGQCXAAAVAAEKyxBRBwBOAAA1AAQKgSgABBEACQqdJHUaAMkCABEABwoPJHUaAMkCABQABQobIPEQANcBABUAAgoAJOkQALgAAAAA.Serperior:BAAANQAECgIJAgABNQABCgIIAgABAAAAAA==.Sesshomar:BAAANQADCgEIAQAAAA==.Seventhchild:BAAANQADCgUJCQAAAA==.',
Sh='Sh:BAAANQAECggJEgAAAA==.Shadopaw:BAAANQAECgQJDgAAAA==.Shadowrae:BAAANQAECgMJAwABNQAECgQIBgABAAAAAA==.Shadowsyy:BAAANQABCgUJBQAAAA==.Shadyllama:BAAANQAECgYIDgAAAA==.Shamkat:BAAANQADCggJGQAAAA==.Shammah:BAAANQAECgYIEQAAAA==.Shammbulance:BAAANQADCgIJAgAAAA==.Shamuoo:BAAANQADCgQIBAAAAA==.Sharlo:BAAANQADCgQJDgAAAA==.Sharnie:BAAANQAECgYIDgAAAA==.Shear:BAAANQAECggIAwAAAA==.Shellatrix:BAABNQAECoEWAAIfAAgKJRkCCQAnAgAfAAgKJRkCCQAnAgAAAA==.Shepp:BAAANQAECgYIEAAAAA==.Shommy:BAAANQADCggICAAAAA==.Shootette:BAAANQAECgYIDAAAAA==.Shãmtastic:BAAANQADCgYIBgAAAA==.',
Si='Silandryn:BAAANQAECgIJAgAAAA==.Sinderela:BAABNQAECoEXAAIeAAgKQwY5hgBtAQAeAAgKQwY5hgBtAQAAAA==.Sinisterwing:BAAANQAECgcJDwAAAA==.Siolani:BAAANQADCgMJAwAAAA==.',
Sk='Skeptikk:BAABNQAECoEhAAILAAgKSxptKgBrAgALAAgKSxptKgBrAgAAAA==.Skinnery:BAAANQAECgIJAgAAAA==.Skrull:BAAANQAECgcJEAAAAA==.',
Sl='Slateray:BAAANQAECgcJDwAAAA==.Slipnslide:BAAANQADCggICQAAAA==.',
Sm='Smaky:BAAANQAECgUICgAAAA==.Smaque:BAABNQAECoEjAAIKAAgKphsvOwB5AgAKAAgKphsvOwB5AgAAAA==.Smegging:BAAANQADCgYICQAAAA==.',
Sn='Snaare:BAAANQADCgYJDAAAAA==.',
So='Solcaris:BAAANQAECgIJAwAAAA==.Sorie:BAAANQAECgQIBQAAAA==.Soulwishper:BAAANQAECgQJBAAAAA==.Sourstraps:BAAANQADCgMIAwAAAA==.Soùlstealer:BAAANQADCgQIBAAAAA==.',
Sp='Sparkdead:BAAANQADCgQIBwAAAA==.Spazzimitazz:BAAANQADCgIIAgAAAA==.Spazzy:BAAANQAECgYIEwAAAA==.Spenna:BAAANQAECgUIBAAAAA==.Spudacus:BAAANQAECgUIDQAAAA==.Spuddk:BAABNQAECoEaAAIDAAgKCRErLAAKAgADAAgKCRErLAAKAgAAAA==.Spudsham:BAAANQAECgUJCAABNQAECggIGgADAAkRAA==.',
St='Stabforcash:BAACNQAFFIEQAAIjAAYKiiQ+AACbAgAjAAYKiiQ+AACbAgA1AAQKgRcAAyMACQpWI34DAG0DACMACQpWI34DAG0DACQABwoUBtAhAHYBAAAA.Starleaf:BAAANQADCgQIBgAAAA==.Stellarluse:BAAANQAECgIIBQAAAA==.Steller:BAAANQABCgEIAQAAAA==.Stickler:BAAANQAECgYIDgAAAA==.Stonkerella:BAAANQADCgIIAgAAAA==.Stonque:BAAANQADCgcIBwABNQAECggIIwAKAKYbAA==.Stormchief:BAAANQAECgEIAQAAAA==.Stormgoat:BAAANQADCgYIBwAAAA==.Stormie:BAAANQAECgQIBwAAAA==.Stormrider:BAAANQAECgYIEAAAAA==.Streuth:BAABNQAECoEhAAIlAAgK/SQMAgBaAwAlAAgK/SQMAgBaAwAAAA==.Strummer:BAACNQAFFIEHAAIFAAMKBiMiBgA6AQAFAAMKBiMiBgA6AQA1AAQKgUQAAwUACQoiJGgDALEDAAUACQoiJGgDALEDACYAAgpTFcBLAHUAAAAA.Stubbyholder:BAAANQADCggICAAAAA==.',
Su='Subaru:BAAANQAECgIJAgABNQAECgYIBgABAAAAAA==.Subaruu:BAAANQAECgYIBgAAAA==.Subsiding:BAAANQADCgYIBgAAAA==.Subtera:BAAANQADCgcIBwAAAA==.Supagroova:BAAANQADCgMJAwAAAA==.Supernothing:BAAANQAECgQJBwAAAA==.Superswede:BAAANQAECgQJCAAAAA==.Susurrus:BAAANQADCgUIBQAAAA==.',
Sw='Switchdoctor:BAAANQADCggJEAABNQADCggIEAABAAAAAA==.Sworf:BAABNQAECoEjAAILAAgKRBl9JwB+AgALAAgKRBl9JwB+AgAAAA==.',
Sy='Syaarhunter:BAAANQADCgcIFwAAAA==.Syaarknight:BAAANQADCgYJBwAAAA==.Syaarpally:BAAANQADCggIGQAAAA==.Syazar:BAAANQAECgQJBgAAAA==.Sylanthia:BAAANQAECgYIDQAAAA==.Sylblades:BAAANQAECgUIBQAAAA==.Sylwizard:BAAANQABCgEIAQAAAA==.',
['Só']='Sóg:BAAANQAECgEIAgABNQAECggIGgARALghAA==.',
['Sø']='Søbz:BAAANQADCggJIwAAAA==.Søg:BAABNQAECoEaAAQRAAgKuCGvPgAiAgARAAYK5B+vPgAiAgAVAAMK1xu8DAAOAQAUAAEK8iSjTwBtAAAAAA==.',
['Sù']='Sùnjin:BAAANQAECgIJAgABNQAECgUJDQABAAAAAA==.',
Ta='Tabknight:BAABNQAECoEcAAICAAgKAhNxLwDpAQACAAgKAhNxLwDpAQAAAA==.Taelron:BAAANQAECgIIAgAAAA==.Taelstard:BAAANQAECgQJCgAAAA==.Taichook:BAAANQAECgEIAQABNQAECggIJwAeADQgAA==.Taithos:BAABNQAECoEnAAIeAAgKNCCrJwDCAgAeAAgKNCCrJwDCAgAAAA==.Taizen:BAAANQAECgYIBgAAAA==.Talanardonis:BAAANQADCgQIBAAAAA==.Tanktough:BAAANQAECgUIBQAAAA==.Tarago:BAABNQAECoEZAAIDAAcKsx7SHgBuAgADAAcKsx7SHgBuAgAAAA==.Taranisis:BAAANQAECgQJCQAAAA==.Targetone:BAAANQAECgUJDQAAAA==.Tasall:BAAANQAECgQIBAAAAA==.Tauntflaunt:BAABNQAECoEcAAIDAAkKVSDhCABVAwADAAkKVSDhCABVAwAAAA==.Tayy:BAAANQADCgEIAQAAAA==.',
Te='Tech:BAAANQAECgUJDgAAAA==.Tempø:BAAANQAECgEJAgAAAA==.Tenkris:BAAANQAECgMIBAAAAA==.Tenleigh:BAAANQAECgIJAwAAAA==.Tenzero:BAAANQADCgYJBgAAAA==.Terroria:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Terrorizor:BAAANQAECgQICwAAAA==.',
Th='Thalía:BAAANQADCggIHwAAAA==.Thargroar:BAABNQAECoEbAAIOAAgKPyN4AgA8AwAOAAgKPyN4AgA8AwAAAA==.Thazix:BAAANQADCgYIDQABNQAECgYIEQABAAAAAA==.Theboysavior:BAAANQAECgEIAQAAAA==.Thefluffyman:BAAANQAECgUICgAAAA==.Themetzi:BAAANQADCgUIBQAAAA==.Thiss:BAAANQAECgYIEQAAAA==.Thordak:BAAANQAECgQJBgAAAA==.Thoridian:BAAANQADCgQIBwAAAA==.Thurlarra:BAAANQADCgEIAQAAAA==.Thùnder:BAAANQADCgYICQAAAA==.',
Ti='Tidewalker:BAAANQADCgYIBgAAAA==.Tigolbits:BAAANQADCgUIBQAAAA==.Titdor:BAAANQADCgIIAgAAAA==.',
To='Tobythemonk:BAABNQAECoEXAAIEAAgKqxYcDgAoAgAEAAgKqxYcDgAoAgAAAA==.Toehacker:BAAANQAECgcIEQAAAA==.Toliman:BAAANQADCgYIDQAAAA==.Tolkarkiller:BAAANQAECgUICQAAAA==.Tomarr:BAEBNQAECoEhAAIMAAgK2QpgVQCUAQAMAAgK2QpgVQCUAQABNQAECgUJCAABAAAAAA==.Tonsham:BAAANQADCgYIBwAAAA==.Totemspanker:BAAANQADCggJFAAAAA==.Totoki:BAAANQADCggICAAAAA==.Touchitonce:BAAANQAECgQJCwAAAA==.Toxic:BAAANQADCgIIAgAAAA==.Toóz:BAABNQAECoEZAAMLAAgKBBGnPAAHAgALAAgKBBGnPAAHAgAMAAcKXwTOcwAsAQAAAA==.',
Tr='Trailblayxur:BAAANQAECgYICwAAAA==.Tranqbillity:BAAANQABCgEIAQAAAA==.Traser:BAAANQADCgYJDAAAAA==.Trickyknight:BAABNQAECoE0AAMCAAkKyhmAJAAzAgACAAgKQRiAJAAzAgADAAcKoBnJKAAhAgAAAA==.Trickymage:BAAANQADCgUIBQAAAA==.Trinityheals:BAAANQAECgEIAQAAAA==.',
Tu='Tuckerius:BAAANQADCgYIBwAAAA==.Turahk:BAAANQAECgYICwAAAA==.Turtlesoup:BAAANQAECgUJEgAAAA==.',
Tw='Twofoottall:BAAANQAECgEJAQAAAA==.',
Ty='Tylendorian:BAAANQABCgEIAgAAAA==.Tylerolothus:BAAANQAECgEJAQAAAA==.Tynndera:BAAANQAECgMIBQAAAA==.Tyrawr:BAAANQAECgQIBAABNQAFFAUICwACABUUAA==.Tyth:BAAANQAECgYIDgAAAA==.',
['Tí']='Tím:BAAANQAECgYIDgAAAA==.',
Ud='Udderlyfuzzy:BAAANQAECgQIBgABNQAECgcIEAABAAAAAA==.',
Un='Unclegrandpa:BAAANQADCgQIBgAAAA==.',
Ur='Uranbraug:BAAANQABCgIIBAAAAA==.Urôt:BAAANQAFFAEIAQAAAA==.',
Uw='Uwusue:BAAANQAECgYIBwAAAA==.',
Va='Vaeline:BAAANQABCgUIBwAAAA==.Valac:BAACNQAFFIELAAICAAUKFRTDBgBhAQACAAUKFRTDBgBhAQA1AAQKgSQAAgIACQp+ImMHAFsDAAIACQp+ImMHAFsDAAAA.Valkyrie:BAAANQAECgcIDAAAAA==.Valothos:BAAANQAECgUJEgAAAA==.Valtiell:BAABNQAECoEhAAIkAAgKyx5yCADNAgAkAAgKyx5yCADNAgAAAA==.Valuri:BAAANQAECgYIDQAAAA==.Varainne:BAAANQAECgYIDwAAAA==.',
Ve='Vegimitê:BAAANQADCgUJBQAAAA==.Vegymite:BAAANQADCgEIAQAAAA==.Velgath:BAABNQAECoEqAAIkAAkKJBs3BwDnAgAkAAkKJBs3BwDnAgAAAA==.Velkhana:BAAANQAECgcIEQAAAA==.Velmorra:BAAANQAECgQJCgAAAA==.Veratis:BAAANQAECgEJAQAAAA==.',
Vi='Victoria:BAAANQAECgUJCwAAAA==.Vinee:BAAANQAECgIIBQAAAA==.Vioneva:BAAANQAECgYIEQAAAA==.Viscelock:BAAANQAECgcIEQAAAA==.Vivyregosa:BAACNQAFFIELAAIaAAUKKw16DACYAQAaAAUKKw16DACYAQA1AAQKgSQAAhoACQr7HWwyAPcCABoACQr7HWwyAPcCAAAA.',
Vx='Vxi:BAACNQAFFIEOAAIjAAUKlhs9AQDoAQAjAAUKlhs9AQDoAQA1AAQKgRcAAiMACQoKIXEIAAMDACMACQoKIXEIAAMDAAAA.',
Wa='Wagglehoof:BAAANQADCgcIDAAAAA==.Wain:BAAANQAECgEJAQAAAA==.Wakantanka:BAAANQAECgIIBQAAAA==.Wanglord:BAAANQAECgYIDAAAAA==.Wardõn:BAAANQADCgUIBgAAAA==.Warpig:BAAANQADCgUIBgAAAA==.Warriormilan:BAAANQADCgYIBwAAAA==.Waxedtaco:BAAANQAECgIJAwAAAA==.',
Wh='Wheato:BAABNQAECoEZAAMTAAgKAiT4DgAbAwATAAgKBSH4DgAbAwAPAAMKOCKiFgAnAQAAAA==.Wheyprotein:BAAANQADCggJCAAAAA==.Whipshot:BAAANQADCggICQAAAA==.Whiteflame:BAAANQAECgYICgAAAA==.Whiteopal:BAAANQAECgYIEQAAAA==.Whorship:BAAANQADCggJCAAAAA==.',
Wi='Willowsun:BAAANQAECgIIAgAAAA==.Winterzap:BAAANQADCggIGAAAAA==.Wipe:BAAANQADCggICAABNQAFFAcIFwALACojAA==.',
Wo='Wolfyhunter:BAAANQADCggJCAAAAA==.',
Wr='Wrathkiller:BAAANQADCgcJBwAAAA==.',
Wu='Wulfrick:BAAANQADCgMIBQAAAA==.',
['Wí']='Wítchypoo:BAAANQAECgQJBgAAAA==.',
Xa='Xane:BAAANQADCgYJEQAAAA==.Xanetia:BAAANQAECgIIAwAAAA==.Xatir:BAAANQADCgQIBwAAAA==.',
Xi='Xinful:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.Xint:BAAANQABCgEJAgAAAA==.',
Xj='Xjaryl:BAAANQADCgcIDgAAAA==.',
Xo='Xoger:BAAANQABCgQIBAAAAA==.',
Xy='Xyandris:BAAANQAECgQJBgAAAA==.',
['Xï']='Xïbalba:BAAANQABCgIJAgAAAA==.',
Ya='Yamasharma:BAAANQADCgYJFgAAAA==.',
Ye='Yeehaww:BAAANQAECgQIDAAAAA==.',
Yy='Yykes:BAAANQABCgIIAgAAAA==.',
Za='Zaharax:BAAANQAECgQICwAAAA==.Zaharaxis:BAAANQABCgEIAQAAAA==.Zaharis:BAAANQAECgUICAAAAA==.Zanakari:BAAANQADCgYJFAAAAA==.Zasilia:BAAANQADCgUIBQAAAA==.Zass:BAAANQADCgQIBAAAAA==.',
Ze='Zensetrazath:BAAANQAECgYIDwAAAA==.Zerath:BAAANQADCgYIBwAAAA==.',
Zh='Zhanqui:BAAANQAECgYICwAAAA==.',
Zi='Ziba:BAABNQAECoEhAAIFAAgKOhmFKQCOAgAFAAgKOhmFKQCOAgAAAA==.Zilithus:BAAANQADCgYIBgABNQAECgEJAQABAAAAAA==.Zingermage:BAEANQAECgcICwAAAA==.Zipzamzoom:BAAANQADCggIAgABNQADCggIEAABAAAAAA==.',
Zo='Zoroo:BAAANQAECgQIDwAAAA==.',
Zr='Zross:BAAANQADCgcIDQAAAA==.',
Zu='Zudo:BAAANQAECgUIDgAAAA==.Zuthrais:BAABNQAECoE4AAILAAkKAhHQMABEAgALAAkKAhHQMABEAgAAAA==.Zuulik:BAAANQADCgYIDgAAAA==.Zuuls:BAAANQADCggJCwAAAA==.',
Zz='Zz:BAACNQAFFIEQAAISAAcK1RUWAACnAgASAAcK1RUWAACnAgA1AAQKgSIAAhIACQpCJkIAAO8DABIACQpCJkIAAO8DAAAA.',
['Án']='Ángelpie:BAAANQAECgEIAgAAAA==.',
['Är']='Ärrôw:BAAANQADCgYIAgAAAA==.',
['Ås']='Åshka:BAAANQABCgQJAwAAAA==.',
['ßa']='ßankai:BAAANQAECgUIBQABNQAECgUIDgABAAAAAA==.',
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
