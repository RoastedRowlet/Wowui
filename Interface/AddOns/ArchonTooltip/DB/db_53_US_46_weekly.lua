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

local lookup = {'Unknown-Unknown','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Rogue-Subtlety','Shaman-Enhancement','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Druid-Guardian','Paladin-Retribution','Priest-Holy','Priest-Discipline','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Evoker-Preservation','Paladin-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aatto:BAAANQADCgYIBwABNQAECgMIAwABAAAAAA==.',
Ac='Acertrick:BAACNQAFFIEIAAICAAYJNhcFAABTAgACAAYJNhcFAABTAgA1AAQKgRoAAgIACQnvJCoAANsDAAIACQnvJCoAANsDAAAA.',
Ad='Adampriest:BAAANQAECgEIAQAAAA==.Addh:BAAANQAECgcIDwAAAA==.',
Ae='Aelwyd:BAABNQAECoEaAAQDAAkJpRC0BwBQAgADAAkJ7w60BwBQAgAEAAQJxQqOVQD4AAAFAAIJCwleDQByAAAAAA==.Aeoni:BAAANQADCggICAABNQAECgUICgABAAAAAA==.Aeronis:BAAANQADCggIEwAAAA==.Aery:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.Aessara:BAAANQADCggIEwAAAA==.',
Ag='Aggron:BAAANQAECggIEgAAAA==.',
Ai='Ailurun:BAAANQADCgEIAgAAAA==.',
Al='Alexassassin:BAABNQAECoEXAAIGAAkJqBpYBQDoAgAGAAkJqBpYBQDoAgAAAA==.Aloriannis:BAAANQAECgMIBgAAAA==.Aluas:BAAANQADCgcIEQAAAA==.',
Am='Amaracepally:BAAANQAECgQIBQAAAA==.Amethar:BAAANQAECgMIAwABNQAECgkJGgAHADglAA==.Amowdrood:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Amowshamow:BAAANQAECgQICAAAAA==.',
An='Anan:BAAANQAECgEIAQAAAA==.Anatall:BAAANQAECgcIDwAAAA==.Andrin:BAAANQAECgQIBAAAAA==.Andy:BAAANQADCgYIBgAAAA==.Aneira:BAAANQADCgUIBQAAAA==.Anitá:BAAANQADCgcIEAAAAA==.',
Ap='Applebees:BAAANQADCggICAAAAA==.',
Ar='Araragi:BAAANQADCggICAAAAA==.Archaon:BAAANQAECgcIBwAAAA==.Arei:BAAANQAECgcIDwAAAA==.Argosa:BAAANQAECgUICQAAAA==.Ari:BAAANQAECgYICwAAAA==.Arianagrande:BAAANQADCgcIEQAAAA==.Arihog:BAAANQAECgIIBAAAAA==.Arioch:BAAANQADCgEIAQAAAA==.Arkilytê:BAABNQAECoEZAAMIAAkJfiJqAgCSAwAIAAkJ9iFqAgCSAwAJAAEJdyR5MABlAAAAAA==.Aryä:BAAANQAECgEIAQAAAA==.',
As='Ascend:BAECNQAFFIEIAAIKAAYJwA24AAAMAgAKAAYJwA24AAAMAgA1AAQKgRoAAgoACQkEHocFADkDAAoACQkEHocFADkDAAAA.Astraeá:BAAANQAECgQIBAAAAA==.',
Au='Auroch:BAAANQAECgcIDgAAAA==.Auxilary:BAAANQAECgYIDgAAAA==.',
Av='Avalen:BAAANQADCgQICAAAAA==.Avarcis:BAAANQAECgQIBgAAAA==.Aveleni:BAAANQAECgYIDgAAAA==.Aveloree:BAAANQADCgYIDwAAAA==.',
Aw='Awakening:BAAANQABCgMIAwAAAA==.',
Az='Azelie:BAAANQAECgIIAgAAAA==.',
Ba='Baddragön:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Baidoom:BAAANQABCgQIBAAAAA==.Balcmeg:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Bandrui:BAAANQADCgYICwAAAA==.Banick:BAAANQADCgYIDQAAAA==.Bartszwar:BAAANQAECgYIEgAAAA==.',
Be='Bendie:BAAANQADCgYICAAAAA==.Beret:BAAANQAECgcIDwAAAA==.Bewmbat:BAAANQADCgcIBwABNQADCgEIAQABAAAAAQ==.',
Bg='Bgaraecen:BAAANQADCgQIBAAAAA==.',
Bi='Bigchimpn:BAAANQAECgIIAgAAAA==.Bimbo:BAAANQAECgMIBAAAAA==.Bindkickplz:BAAANQABCgMIBQAAAA==.Birdinii:BAAANQAECgcIBwAAAA==.Birstormrage:BAAANQAECgIIAgAAAA==.',
Bl='Blackrose:BAAANQADCgcICAAAAA==.Blacksmoke:BAAANQADCgUIBAAAAA==.Blacktusk:BAAANQAECgQIBgAAAA==.Bladestorm:BAAANQADCgYIBwAAAA==.Blargdruid:BAABNQAECoEbAAILAAgJ6xbFAwBIAgALAAgJ6xbFAwBIAgAAAA==.Blessthat:BAEANQADCgcIFAAAAA==.Blindnada:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
Bo='Bonkie:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.',
Br='Brewdyne:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Brignis:BAAANQADCgUIBQAAAA==.Brizz:BAAANQAECgIIAgABNQAECggIDgABAAAAAA==.Brojojojojo:BAAANQAECgMIBgAAAA==.Broxas:BAAANQAECgEIAQAAAA==.Brøken:BAAANQAECggIDQAAAA==.',
Bu='Bubbleblade:BAAANQADCgEIAQAAAA==.Bubblesbro:BAABNQAECoEYAAIMAAkJDCXkAQDHAwAMAAkJDCXkAQDHAwAAAA==.Bubkiss:BAAANQADCgEIAQAAAQ==.Buffalo:BAAANQAECgcIDwAAAA==.Buffs:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Bulbasaurz:BAAANQADCggIDwAAAA==.Buldair:BAAANQAECgEIAgAAAA==.Bunsski:BAAANQAECgMIAwAAAA==.Burntbacon:BAAANQADCggICAABNQAECgUICgABAAAAAA==.Burstygirl:BAAANQAECggIEQAAAA==.Buzzkill:BAAANQADCgMIAwAAAA==.',
['Bø']='Bøkari:BAAANQAECgQIBQAAAA==.',
Ca='Cakes:BAAANQADCgMIAwAAAA==.Callie:BAACNQAFFIEIAAINAAYJ0w+wAAAQAgANAAYJ0w+wAAAQAgA1AAQKgRoAAw0ACQnJIe4CAGEDAA0ACQnJIe4CAGEDAA4ACAkVCIkFAJoBAAAA.Caloren:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Calypsoza:BAAANQADCgMIBAAAAA==.Capitis:BAAANQAECgEIAQAAAA==.Catwink:BAAANQADCgYICAAAAA==.',
Ce='Celine:BAAANQAECgIIAgAAAA==.Ceol:BAAANQAECgMIAwAAAA==.Cernath:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Ch='Chaddbrochil:BAAANQADCgYIBgAAAA==.Chaosblade:BAAANQAECgEIAgAAAA==.Chilicheese:BAAANQADCgEIAQAAAA==.Chocobomb:BAABNQAECoEYAAMPAAkJuBOWHQAnAgAPAAgJnRKWHQAnAgAQAAYJxwFoVgD5AAAAAA==.Chosen:BAAANQADCgcICAAAAA==.Chronarfs:BAAANQAECgIIAgAAAA==.',
Ci='Cicatrizesp:BAAANQAECgcIDgAAAA==.Cive:BAAANQAECgMIAwAAAA==.',
Cl='Clayberd:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Co='Coldhearrted:BAAANQAECgcIDwAAAA==.Copyleft:BAAANQADCgQIBAAAAA==.Cosmere:BAAANQADCggIEAAAAA==.',
Cr='Cryt:BAAANQAECgQIBwAAAA==.',
Da='Dagather:BAAANQADCgQIBAAAAA==.Danendena:BAAANQAECgUIBgAAAA==.Danglars:BAAANQADCggICwABNQAECgYICwABAAAAAA==.Darkcorn:BAAANQAECgYIEgAAAA==.Darkdecayy:BAAANQADCgQIBQAAAA==.Darkshieldz:BAAANQAECgUICAAAAA==.Darktiranus:BAAANQADCggICAAAAA==.David:BAAANQAECggICwAAAA==.',
De='Deadkyle:BAAANQADCgQIBAAAAA==.Deadly:BAAANQADCgUIBQAAAA==.Deathcalls:BAAANQAECgEIAQAAAA==.Deathlywind:BAAANQAECgQIBAAAAA==.Delphias:BAAANQAECgQIBAAAAA==.Destrorin:BAAANQAECgQIBAAAAA==.Dethlok:BAAANQADCgUIBwAAAA==.Deucedeuce:BAAANQADCgUIEAAAAA==.Devowizard:BAABNQAFFIENAAIRAAcJqxg8AACNAgARAAcJqxg8AACNAgAAAA==.Dewshaman:BAAANQADCgIIAgAAAA==.',
Di='Dibib:BAACNQAFFIEIAAMEAAYJ8w2tAACrAQAEAAUJdw6tAACrAQADAAEJXwtJBgBcAAA1AAQKgRoAAwQACQlrIp4EACMDAAQACAnmIZ4EACMDAAMACAnXEncIAD8CAAAA.Dinglebery:BAAANQAECgUICgAAAA==.Dirac:BAAANQAECgEIAQAAAA==.Dirtybirdz:BAAANQADCggIEAAAAA==.Dislexy:BAAANQADCgQIBQAAAA==.',
Dk='Dkitty:BAAANQAECgQIBgAAAA==.Dkittykat:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Dkizzy:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Do='Dogs:BAAANQADCgYIBgAAAA==.Donkeydonng:BAAANQADCgUIBQAAAA==.Doodlez:BAAANQAECgEIAQAAAA==.Dota:BAAANQAECgEIAQAAAA==.',
Dr='Dracke:BAAANQADCggICAAAAA==.Draga:BAAANQAECgQIBAAAAA==.Dragondeezn:BAAANQADCgYIBgAAAA==.Drekzul:BAAANQAECgQIBAAAAA==.Drutara:BAAANQAECgYIBgAAAA==.',
Du='Ducey:BAAANQAECgEIAQAAAA==.Ducksicker:BAAANQADCggIEwAAAA==.Dumpsterbaby:BAAANQAECgQIBwAAAA==.Durlklok:BAAANQADCgQIBAAAAA==.',
['Dè']='Dèschain:BAAANQADCgUICgAAAA==.',
['Dé']='Démonic:BAAANQADCgQIBAAAAA==.',
['Dó']='Dóth:BAAANQAECgIIAgAAAA==.',
['Dø']='Dørf:BAAANQADCgUIBQAAAA==.',
Ef='Effinaye:BAAANQABCgYIBgAAAA==.',
Ei='Eightfingers:BAAANQAECgYICwAAAA==.Eisenklopfer:BAAANQAECgEIAQAAAA==.',
Ek='Ekim:BAAANQADCgUICgAAAA==.',
El='Elentiya:BAAANQADCgUIBwAAAA==.Elyaen:BAAANQAECgMIBQAAAA==.',
Em='Emailed:BAEBNQAECoEcAAMPAAkJURs+DQDfAgAPAAkJURs+DQDfAgAQAAMJJxdoWADxAAAAAA==.Emi:BAAANQAECgIIAgAAAA==.Emofemboy:BAAANQADCgUIBQAAAA==.',
En='Envy:BAAANQAECgYIBgAAAA==.',
Eo='Eore:BAAANQAECgUICAAAAA==.',
Er='Erequem:BAAANQADCgEIAQAAAA==.',
Eu='Eupatorus:BAAANQADCgUIBgAAAA==.',
Ew='Ewokhunter:BAAANQAECgYIDAAAAA==.',
Ex='Execuwute:BAAANQABCgYICAAAAA==.',
Fe='Felgibsonn:BAAANQADCgEIAQAAAA==.Felonee:BAAANQADCgcIEgAAAA==.Festermight:BAACNQAFFIEHAAQSAAMJVheXAQCuAAASAAIJhBOXAQCuAAATAAIJoBibAwCpAAAUAAEJvBCrDAA1AAA1AAQKgRoAAxIACQnQI0EDAB8DABIACAneIUEDAB8DABMACQkTH5ELAOcCAAAA.',
Fi='Finnhunter:BAAANQABCgIIAgAAAA==.Firenze:BAAANQADCgUIBwAAAA==.Fishpockets:BAAANQADCgEIAQAAAA==.',
Fl='Flosstradamu:BAAANQABCgMIAQAAAA==.',
Fr='Fredrock:BAAANQAECgYICwAAAA==.',
Fu='Fuzziewuzzie:BAAANQADCgQIBAAAAA==.',
['Fî']='Fîshy:BAAANQAFFAIIAgAAAA==.',
Ga='Gaibe:BAAANQAECggIEgAAAA==.Gamba:BAAANQAECgYICgAAAA==.',
Gb='Gb:BAAANQADCgYIBgAAAA==.',
Ge='Genghiscaulk:BAAANQAECgQICAAAAA==.Georgeknight:BAABNQAECoEZAAITAAkJXh7FCAAYAwATAAkJXh7FCAAYAwAAAA==.Gertrùde:BAAANQAECgEIAQAAAA==.Gerunash:BAAANQADCggICAABNQAFFAYIDAAGAL8KAA==.Gewnz:BAAANQAECgYIDAABNQADCgEIAQABAAAAAA==.',
Gi='Gildharts:BAAANQAECggICwAAAA==.Girl:BAAANQAECgIIAgAAAA==.',
Gl='Glowlimn:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.',
Go='Goblindur:BAAANQAECgQIBAAAAA==.',
Gr='Gradris:BAAANQAECgYIDgAAAA==.Greener:BAAANQAECgcIDAAAAA==.Griddy:BAAANQAECgMIAwAAAA==.Grimghar:BAAANQADCgcIEQAAAA==.Grimrael:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Grimreapyr:BAAANQADCgUIBgABNQAECgMIBQABAAAAAA==.Grimtar:BAAANQAECgUICAABNQAECgMIBQABAAAAAA==.Grimtariel:BAAANQAECgMIBQAAAA==.Grimzilla:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.Grippin:BAAANQAECgIIAgAAAA==.',
Gu='Guldar:BAAANQADCgYIBgAAAA==.Gunoil:BAAANQAECgQIBAAAAA==.',
['Gì']='Gìngerale:BAAANQADCgcIEQAAAA==.',
Ha='Hamrshifts:BAAANQADCgcIEQAAAA==.Harritapoter:BAAANQABCgYIBgAAAA==.Havartihavoc:BAAANQADCgcIEQAAAA==.Hawtdots:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.',
He='Healmeplx:BAAANQAECgIIAgAAAA==.Healsfadayz:BAAANQADCgYIBgAAAA==.Heiku:BAAANQADCggIBwAAAA==.Hekaraa:BAAANQADCgcIEAAAAA==.Hellhammer:BAAANQADCgcIDAAAAA==.Herenya:BAAANQAECgEIAQAAAA==.',
Hi='Hiccup:BAAANQADCgcICAAAAA==.Hideyourtoes:BAAANQAECgQIBAABNQAECgkJGAAVALoiAQ==.Himnick:BAACNQAFFIEMAAQFAAYJORwTAAA1AQAFAAMJ/xcTAAA1AQADAAMJAR9uAAAqAQAEAAIJZxDcBgCmAAA1AAQKgRoABAMACQkKI6YFAIcCAAMABwnWIKYFAIcCAAQABwksHewWAEcCAAUAAwnQH8MGAA8BAAAA.',
Ho='Holmadic:BAAANQADCggIAgAAAA==.Holyslimes:BAAANQADCgMIAwAAAA==.Honoree:BAAANQADCgYIDwAAAA==.Honse:BAAANQADCggIDwAAAA==.Hoodal:BAAANQAFFAIIAgAAAA==.Hope:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.',
Hu='Huntrez:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Hustlepuff:BAAANQADCgYIDQAAAA==.',
Hy='Hyllah:BAAANQADCgcIEQAAAA==.',
['Hè']='Hèrrinà:BAAANQAECgEIAgAAAA==.',
Ik='Ikissdudes:BAAANQAECgcICwAAAA==.',
Il='Illuunni:BAAANQAECgQIBQAAAA==.',
Im='Imbecile:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Imblack:BAAANQAECggIEQAAAA==.',
Jc='Jclaw:BAAANQADCggIDgAAAA==.',
Je='Jeddak:BAAANQADCggICAAAAA==.Jennzen:BAAANQADCgcIEAAAAA==.Jesterawr:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.',
Ji='Jinjin:BAAANQAECgYICwAAAA==.',
Jl='Jlimremix:BAAANQAECgIIAgAAAA==.',
Jo='Jouley:BAAANQADCgYICwAAAA==.',
Ju='Justamage:BAAANQAECgIIAgAAAA==.Justsaiyan:BAAANQADCggIDgAAAA==.',
Jx='Jx:BAAANQAECgcIDwAAAQ==.',
Jz='Jzimm:BAAANQADCgcICgAAAA==.',
['Jå']='Jåcob:BAAANQADCggIBgABNQAECgEIAQABAAAAAA==.',
Ka='Kadane:BAAANQADCgEIAQAAAA==.Kaeori:BAACNQAFFIEMAAIWAAYJ+RS2AAAXAgAWAAYJ+RS2AAAXAgA1AAQKgRoAAhYACQl3H9EIABcDABYACQl3H9EIABcDAAAA.Kalïsta:BAAANQAECgEIAQAAAA==.Karnesia:BAAANQABCgMIAwAAAA==.Karra:BAAANQAECgUICgAAAA==.Kayliezra:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.Kayssa:BAAANQAECgcIBwAAAA==.',
Ke='Keegan:BAAANQAECgcIDwAAAA==.Keiragosa:BAAANQAECgEIAQAAAA==.Keita:BAAANQAECgUIBQAAAA==.Kelaran:BAAANQADCgEIAQAAAA==.Kellired:BAAANQADCgIIAgAAAA==.Kelsara:BAAANQAECgcIEQAAAA==.',
Kh='Khaladyn:BAAANQADCgUIBQAAAA==.Khaladynie:BAAANQADCgQIBAAAAA==.Khazjin:BAAANQADCgUIBQAAAA==.',
Ki='Kiko:BAAANQADCgcIEAAAAA==.Killersmallz:BAAANQAECgQIBwAAAA==.Killshott:BAAANQADCgYIBgAAAA==.Killstardo:BAAANQADCgIIAgAAAA==.Kindatipsy:BAAANQADCgYIDQAAAA==.Kirasti:BAAANQADCgcIEQAAAA==.Kiriko:BAAANQADCgQIBAAAAA==.Kirkap:BAAANQADCgUIBQABNQAFFAYIDQAXADEmAA==.Kirkas:BAAANQAECgMIAwABNQAFFAYIDQAXADEmAA==.Kisspr:BAAANQAECgQIBQAAAA==.Kisswar:BAAANQADCgYIBgAAAA==.Kitkatt:BAAANQADCgQIBAAAAA==.Kittyen:BAAANQADCggICAAAAA==.',
Kl='Klet:BAAANQAECgUIBgAAAA==.',
Km='Kmage:BAAANQADCgcIEQAAAA==.',
Ko='Kogarasu:BAAANQADCgcIEQAAAA==.Kokodrilo:BAAANQADCggICAAAAA==.Koramar:BAAANQAECgIIAgABNQAFFAYIDAAGAL8KAA==.',
Kr='Kragarsf:BAAANQADCgcIEAAAAA==.',
Ku='Kubernaughty:BAAANQADCgYIBgAAAA==.Kuulistin:BAAANQAECgQIBAAAAA==.',
Ky='Kyoppy:BAAANQAECgcIDAAAAA==.',
La='Labluegirl:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Lacusclyne:BAAANQADCgEIAQAAAA==.Lavaßurst:BAAANQAECgEIAQAAAA==.',
Le='Leejohn:BAAANQADCgYIBgAAAA==.Legitasaurus:BAAANQADCggICAAAAA==.Legndairy:BAAANQAECgIIAgAAAA==.Legola:BAAANQADCgQIBQAAAA==.Lenala:BAAANQAECggIDAAAAA==.',
Li='Lightdeity:BAAANQADCgQIBgAAAA==.Lilbeefroni:BAAANQABCgEIAQAAAA==.Lilith:BAAANQAECgMIAwAAAA==.Lilythh:BAAANQADCgIIAgABNQADCgcIEAABAAAAAA==.Linessa:BAAANQAECgQIBAAAAA==.Littlelion:BAAANQAECgcIEAAAAA==.Littleteapot:BAAANQAECgMIAwAAAA==.',
Lo='Lockjim:BAAANQADCgMIAwAAAA==.',
Lu='Lucentil:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.Lucie:BAAANQAECgMIBQAAAA==.Lucigoosey:BAAANQAECgIIAgAAAA==.Luminth:BAAANQAECgUIBQAAAA==.',
Ly='Lyka:BAAANQAECgUIDAAAAA==.',
Ma='Madoria:BAAANQAECgQIBgAAAA==.Madorie:BAAANQAECgIIAgAAAA==.Magice:BAAANQAECgIIAgAAAA==.Magistus:BAABNQAFFIEHAAIYAAYJ6QwyAAD5AQAYAAYJ6QwyAAD5AQAAAA==.Marmalady:BAECNQAFFIEMAAIZAAYJVx95AAA+AgAZAAYJVx95AAA+AgA1AAQKgRoAAhkACQn+IxgBAIsDABkACQn+IxgBAIsDAAAA.Masa:BAACNQAFFIEIAAIXAAYJPxYlAAAoAgAXAAYJPxYlAAAoAgA1AAQKgRoAAhcACQnUI7EAAKEDABcACQnUI7EAAKEDAAAA.Masq:BAAANQAECgIIAgAAAA==.Matamharicas:BAAANQAECgUIBgAAAA==.Matt:BAAANQAECgMIBAAAAA==.Mauled:BAAANQAECgcIBwABNQAFFAYIDAAaAKMPAA==.Maulnificent:BAAANQAECgIIAgABNQAFFAYIDAAaAKMPAA==.Maulo:BAABNQAFFIEMAAIaAAYJow9YAADbAQAaAAYJow9YAADbAQAAAA==.Maynaminty:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.',
Mc='Mclovin:BAAANQADCgUIBQAAAA==.',
Me='Medspriest:BAAANQADCgcIDQAAAA==.Megasoreass:BAAANQADCggICwAAAA==.Meliria:BAAANQAECgcICgAAAA==.',
Mi='Microshanks:BAAANQADCggIAQAAAA==.Midgert:BAABNQAECoEZAAIRAAkJIh4mEAA8AwARAAkJIh4mEAA8AwAAAA==.Mimint:BAAANQAECgIIAgABNQAFFAYIDAAVAFYjAA==.Misfortune:BAAANQADCgUIBQAAAA==.Mistfit:BAAANQADCgYICgAAAA==.',
Mo='Moadebe:BAAANQADCgcIDwAAAA==.Moorpheus:BAAANQADCgYIBgAAAA==.Moreshaman:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Morphunter:BAAANQAECgIIAgAAAA==.Mozerdozer:BAAANQADCgYIBgAAAA==.',
Mu='Muthabara:BAAANQADCggICAAAAA==.Muwu:BAAANQAECgUICQAAAA==.',
My='Myfursona:BAAANQADCggICAAAAA==.Mysticpizza:BAAANQADCgEIAQAAAA==.Mystrali:BAAANQADCggIFwAAAA==.Myztified:BAAANQADCgUIBQAAAA==.',
['Mä']='Mädrina:BAAANQADCgYIBgAAAA==.',
Na='Naelyni:BAAANQAECgUIBQABNQADCggICAABAAAAAA==.Naloxone:BAAANQADCgEIAQAAAA==.Nathrezara:BAAANQABCgIIAgAAAA==.Nawtikal:BAAANQADCggIFQAAAA==.',
Ne='Necrootter:BAAANQAECgMIAwAAAA==.Negrumps:BAAANQADCgYIBgAAAA==.Nelune:BAAANQAECgIIAgAAAA==.Neoheals:BAAANQADCgcIBwAAAA==.Neotank:BAAANQADCgUIBQAAAA==.Netgehai:BAAANQADCgQIBAAAAA==.Neurosurgeon:BAAANQADCgEIAQAAAA==.Nezdh:BAACNQAFFIEIAAIJAAYJxxU7AAA1AgAJAAYJxxU7AAA1AgA1AAQKgRYAAwkACQkvJQwBALsDAAkACQkGJQwBALsDAAgABwmXHq0RAFICAAAA.',
Ni='Nizal:BAAANQADCgcIDQAAAA==.',
No='Nosimpin:BAAANQADCgYICAAAAA==.Notbrianp:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Notbrianpage:BAAANQAECgQIBAAAAA==.Nox:BAAANQADCgUIBQAAAA==.',
Nu='Nutzferbuttz:BAAANQADCgMIBAABNQAECgQICAABAAAAAA==.',
Ny='Nyllamage:BAAANQAFFAEIAQAAAA==.',
Ob='Obdromeda:BAAANQAECgYIDAAAAA==.Oberron:BAAANQAECgUICQABNQAECgcIDwABAAAAAA==.',
Ok='Okixs:BAAANQAECgYIDAAAAA==.',
On='Onebaddruid:BAAANQAECgQICAAAAA==.Onebadwarr:BAAANQAECggICAABNQAECgQICAABAAAAAA==.',
Oo='Oogabgooga:BAAANQAECgIIAgAAAA==.',
Os='Oscartheorc:BAAANQADCgEIAQAAAA==.Oshamma:BAAANQAECgQIBAAAAA==.Ossoleil:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ot='Otterfang:BAAANQAECgMIAwAAAA==.',
Oz='Ozatar:BAAANQADCggIDAABNQAECgQIBAABAAAAAA==.Ozen:BAAANQADCggIEAABNQAECgQIBAABAAAAAA==.Ozpal:BAAANQAECgQIBAAAAA==.Oztide:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.Oztington:BAAANQADCgEIAQAAAA==.',
Pa='Paiku:BAAANQADCgYICgAAAA==.Palaky:BAAANQAECgIIAgAAAA==.Para:BAAANQAECgQIBQAAAA==.',
Pe='Peahole:BAAANQADCgQIBAAAAA==.Pelusa:BAAANQAECgIIAgAAAA==.Penelopi:BAAANQAECgUIBQAAAA==.Penguinia:BAAANQAECgEIAQAAAA==.Pensman:BAAANQABCgQIBAAAAA==.',
Pi='Pitukis:BAAANQABCgQIBAAAAA==.',
Pl='Plandalorian:BAAANQADCgYIDQAAAA==.Platectonics:BAAANQADCgQIBgAAAA==.Plexadin:BAAANQAECgEIAQAAAA==.',
Po='Ponch:BAAANQADCgQIBAAAAA==.Popmybubble:BAAANQAECgQIBwAAAA==.',
Pr='Prepotenté:BAAANQAECgQICwAAAA==.Priesta:BAAANQAECggIEwAAAA==.Pronebone:BAAANQAECgMIBgAAAA==.',
Qu='Quomy:BAAANQAECgIIAgAAAA==.',
Ra='Rackblaster:BAAANQABCgMIAwAAAA==.Raei:BAABNQAECoEcAAIQAAkJZwvvIAAFAgAQAAkJZwvvIAAFAgAAAA==.Ragestrasz:BAAANQAECgMIAwAAAA==.Raladin:BAAANQAECgEIAQAAAA==.Ramchi:BAACNQAFFIEMAAMVAAYJUiHcAAD0AQAVAAUJxiHcAAD0AQAbAAEJER9iBQBqAAA1AAQKgRoAAxUACQnRJRwBAL0DABUACQkMJRwBAL0DABsAAQnMJb+DAGoAAAAA.Ramhorn:BAAANQADCgYICwAAAA==.Ramsaur:BAAANQAECgcIBwAAAA==.Ranniel:BAAANQADCgEIAQAAAA==.Rasalghul:BAAANQADCgUIBQAAAA==.Ratchetron:BAAANQABCgEIAQAAAA==.Raythe:BAAANQADCgIIAwAAAA==.Razorfists:BAAANQAECgcICwABNQAFFAYICAAZALkKAA==.Razorscales:BAACNQAFFIEIAAQZAAYJuQrZAgAXAQAZAAQJfwLZAgAXAQAcAAIJ6wfpAwCTAAAdAAEJpwF/AgBSAAA1AAQKgRsABBkACQlPEsoJAFsCABkACQlPEsoJAFsCABwABgk6G/QMANUBAB0AAQnVHecMAFEAAAAA.',
Re='Reckon:BAAANQADCggIFAAAAA==.Reeleaf:BAAANQAECgcIDQAAAA==.Remainn:BAAANQAECgEIAQAAAA==.Remlar:BAAANQADCggIDgABNQAECggIEQABAAAAAA==.Renske:BAAANQADCgUIBQAAAA==.',
Ri='Ride:BAAANQAECgEIAQAAAA==.Rizzard:BAAANQADCgYICgAAAA==.',
Ro='Roriel:BAAANQAECgUICQAAAA==.Rougarou:BAAANQAECgIIAgAAAA==.Rowdyronda:BAAANQABCgIIBAAAAA==.Roweana:BAAANQADCgcIEQAAAA==.',
Ru='Rubmytotéms:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Rumblecat:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.',
Ry='Rylankneth:BAAANQADCgYIBgAAAA==.',
['Rî']='Rîce:BAAANQAECgMIBgAAAA==.',
Sa='Sabelorn:BAAANQAECgUIBwAAAA==.Sacredfear:BAABNQAECoEXAAMEAAkJrhhjDwCNAgAEAAgJYxljDwCNAgADAAIJHA0/PgB1AAAAAA==.Sacredshammy:BAAANQAECgYICwABNQAECgkJFwAEAK4YAA==.Sandayy:BAACNQAFFIEIAAMbAAYJpiBoAACNAQAbAAQJ9x9oAACNAQAVAAQJrR9JAgB3AQA1AAQKgRkAAxsACQlJJfoIAAEDABsABwlGJvoIAAEDABUACAmgI+wIANoCAAAA.Satsao:BAAANQABCgQIAwAAAA==.Sawario:BAAANQADCgMIAwAAAA==.',
Sc='Screwheals:BAAANQAECgIIAgABNQAECgUICgABAAAAAA==.',
Se='Sellene:BAACNQAFFIENAAIXAAYJMSYKAAB0AgAXAAYJMSYKAAB0AgA1AAQKgRsAAhcACQmzJFcBAG0DABcACQmzJFcBAG0DAAAA.Sellina:BAAANQAECgIIAgABNQAFFAYIDQAXADEmAA==.Seneriya:BAAANQABCgIIAgAAAA==.Senorbang:BAAANQAECgMIBAAAAA==.Sep:BAAANQAECgYIDgAAAA==.Serenashadow:BAAANQADCgUIBQAAAA==.',
Sh='Shadowflare:BAAANQADCgcIDQAAAA==.Shaggsalt:BAAANQADCggICAAAAA==.Shalth:BAAANQABCgYIBgAAAA==.Shaolinhunk:BAAANQAECgUICAAAAA==.Sharks:BAAANQAECgcIDwAAAA==.Shawshanks:BAAANQADCgEIAQABNQADCggIAQABAAAAAA==.Shazzman:BAAANQADCgEIAQAAAA==.Shelandria:BAACNQAFFIEMAAIGAAYJvwp4AAAhAgAGAAYJvwp4AAAhAgA1AAQKgRoAAwYACQntGkgEAAkDAAYACQlvGkgEAAkDAB4AAgnQAwwqAG0AAAAA.Shiroee:BAAANQABCgQIAQABNQAECgMIAwABAAAAAA==.Shoda:BAACNQAFFIEHAAMbAAUJ6BEeAQAXAQAVAAQJaAmNAwAoAQAbAAMJKBgeAQAXAQA1AAQKgRoAAxUACQkjImUOAG4CABUABwmNIGUOAG4CABsABQmFJQ8mAAkCAAAA.Shootrmcgávn:BAAANQAECgMIAwAAAA==.Shreker:BAAANQAECgcIDwAAAA==.',
Si='Sidchatic:BAAANQADCgEIAQAAAA==.Sidebo:BAAANQADCgYIDAAAAA==.Sinhunter:BAAANQAECgQIBQAAAA==.Sirn:BAAANQADCgYIBgAAAA==.Sitonmytotem:BAAANQADCgIIAgABNQADCggIAQABAAAAAA==.',
Sj='Sjp:BAAANQADCgIIAgABNQAECgcICAABAAAAAA==.',
Sk='Skeetoo:BAAANQAECgcIDQAAAA==.Skiera:BAAANQADCggICAABNQAECgUICgABAAAAAA==.Skiplegs:BAAANQAECgcIDAAAAA==.Skorpeo:BAAANQADCggICAAAAA==.',
Sl='Slimes:BAAANQADCgIIAgAAAA==.Slimxx:BAAANQADCgYIBgAAAA==.',
Sm='Smargendk:BAAANQADCgYIBwAAAA==.Smargenrog:BAABNQAECoEaAAIHAAkJOCVKAADWAwAHAAkJOCVKAADWAwAAAA==.',
Sn='Snaven:BAAANQAECgEIAQAAAA==.Sneggs:BAAANQADCgYIFgAAAA==.Snifflez:BAAANQAECgQIBAAAAA==.Snipermonkey:BAAANQAECgUIBwAAAA==.',
So='Soiled:BAAANQAECgEIAQAAAA==.Solidshaft:BAAANQADCgcIDQAAAA==.Solikar:BAAANQADCgMIAwAAAA==.Sopheia:BAAANQAECgQIBQAAAA==.Soul:BAAANQAECgcIDwAAAA==.',
Sp='Spek:BAAANQAECggIEAAAAA==.Split:BAAANQAECgUIBgAAAA==.Springonion:BAAANQAECggIEAABNQAFFAYICwAQAM0NAA==.',
Sq='Squidward:BAAANQAECggIEgAAAA==.',
St='Standardhors:BAAANQADCggICAABNQAECgUICwABAAAAAA==.Steadchi:BAAANQAECgYIBgAAAA==.Steadyy:BAAANQABCgQIBAAAAA==.Steakburrito:BAAANQADCgYICgAAAA==.Stedk:BAACNQAFFIEIAAIUAAYJTiE3AABcAgAUAAYJTiE3AABcAgA1AAQKgRoAAhQACQmVJlAAAPQDABQACQmVJlAAAPQDAAAA.Steven:BAAANQAECgIIBAAAAA==.Strongshift:BAAANQAECgEIAQAAAA==.Stygwyggyr:BAAANQAECgYIDgAAAA==.',
Su='Sugarzcoat:BAAANQAECgMIBQAAAA==.Sulphurous:BAAANQADCgcIBwAAAA==.Supdudejr:BAAANQAECgQIBwAAAA==.Supernovi:BAAANQADCggICAAAAA==.',
Sw='Sweetstache:BAAANQABCgQIBgAAAA==.',
Sy='Sykomike:BAAANQAECgcIDAAAAA==.Syler:BAABNQAECoEZAAIeAAkJFSA2AgA8AwAeAAkJFSA2AgA8AwAAAA==.Sylár:BAAANQADCggIFAAAAA==.Symbol:BAAANQABCgQIBAAAAA==.Syreal:BAAANQADCgYICAAAAA==.',
['Sä']='Säcred:BAAANQAECgMIAwABNQAECgkJFwAEAK4YAA==.',
Ta='Tahlia:BAAANQAECgYIDAAAAA==.Talren:BAAANQAECgEIAQAAAA==.Talìa:BAAANQAECgQIBAAAAA==.Tannadà:BAAANQAECgcIDgAAAA==.Tasari:BAACNQAFFIEIAAIfAAYJvB4OAAA2AgAfAAYJvB4OAAA2AgA1AAQKgRkAAh8ACQlpJTsAAOIDAB8ACQlpJTsAAOIDAAAA.Taurenadin:BAAANQADCgIIAgAAAA==.Tayson:BAAANQABCgIIAwAAAA==.Tazzdingo:BAAANQABCgUIBQAAAA==.',
Te='Tekain:BAAANQAECgEIAQAAAA==.Tequilla:BAAANQADCgcIBwAAAA==.Terryn:BAAANQAECgEIAQAAAA==.Tesia:BAAANQADCgUIBwAAAA==.',
Th='Thedeadlypug:BAAANQADCgMIAwAAAA==.Theeripper:BAAANQAECgMIAwAAAA==.Thrashwar:BAAANQAECgEIAQAAAA==.Thrustie:BAAANQAECgMIBgAAAA==.Thusios:BAAANQAECgMIAwAAAA==.',
Ti='Tiazz:BAAANQADCgUIBQAAAA==.Tichu:BAAANQADCgUIBQAAAA==.Tiekho:BAAANQADCgUIBQAAAA==.Tifelia:BAAANQADCgYICwAAAA==.Tigorain:BAAANQADCgYIBQAAAA==.Tizirk:BAAANQADCggICAAAAA==.',
To='Toastybutter:BAAANQADCgYIDAAAAA==.Tonyz:BAAANQAECgIIAgAAAA==.Torrak:BAAANQAECgYIDAAAAA==.Torthie:BAACNQAFFIEIAAIRAAYJExLnAAAzAgARAAYJExLnAAAzAgA1AAQKgRkAAhEACQlxIhMKAG0DABEACQlxIhMKAG0DAAAA.Tothdk:BAAANQAFFAUIAQAAAA==.',
Tr='Trale:BAAANQABCgQIBAAAAA==.Treason:BAAANQADCgUIBQABNQADCggIFAABAAAAAA==.Treeage:BAAANQADCggIFQAAAA==.Tripp:BAAANQADCgcIDQAAAA==.Troeg:BAAANQABCgQIAgAAAA==.Trollerella:BAAANQADCgQIBAABNQAECggIEQABAAAAAA==.Trollzealot:BAAANQAECgMIAwAAAA==.Troxigar:BAAANQAECgIIAgAAAA==.',
Tu='Tullyspring:BAAANQADCgcICAAAAA==.Turkeysub:BAAANQADCgUIBQAAAA==.',
Tv='Tverdydk:BAAANQAECgMIAwAAAA==.',
Tw='Twertlekat:BAAANQAECgQIBAAAAA==.Twinkiez:BAAANQADCgYIBwABNQAECgMIBQABAAAAAA==.Twistkun:BAAANQAECgMIAwAAAA==.',
Un='Unclerod:BAAANQAECgEIAQAAAA==.Unfixable:BAAANQAECgMIAwABNQAFFAQIBQABAAAAAQ==.Unplayable:BAAANQAFFAQIBQAAAQ==.Unusualhorse:BAAANQAECgUICwAAAA==.',
Uu='Uunfar:BAAANQAECgcIDQAAAA==.',
Va='Valedia:BAAANQAECgIIAwAAAA==.Valn:BAAANQAECgQIBAAAAA==.Valtross:BAAANQADCgcIEAAAAA==.Vangough:BAAANQAECgYICwAAAA==.Vayu:BAAANQADCgQIBAAAAA==.',
Ve='Velvetvixen:BAAANQAECgQIBQAAAA==.',
Vi='Viper:BAAANQAECgcIDwAAAA==.',
Vl='Vlad:BAAANQAECgYIBgAAAA==.',
Vo='Voreâu:BAAANQADCgEIAQAAAA==.Vosslar:BAAANQAECgQIBQAAAA==.',
Vv='Vvarden:BAAANQADCgYICgAAAA==.',
['Vî']='Vîper:BAAANQADCggICwAAAA==.',
Wa='Waarrlockk:BAACNQAFFIEHAAMEAAUJvhaiAgAKAQAEAAMJeBeiAgAKAQADAAIJpxWbAgC8AAA1AAQKgRoAAwMACQmdIx8BAGIDAAMACQmcHx8BAGIDAAQABwmSHU4PAI0CAAAA.Walrusrider:BAAANQAECgQIBQAAAA==.Wang:BAAANQAECgcIDwAAAA==.Warbird:BAAANQAECgMIBQAAAA==.Warhmonger:BAAANQADCggICAAAAA==.Wassy:BAAANQAECgIIAgAAAA==.',
We='Wemgobyama:BAABNQAECoEYAAQVAAkJuiJRCADmAgAVAAgJOyJRCADmAgAbAAIJmiOqcQC6AAAgAAEJVgBVCgATAAAAAA==.',
Wh='Whm:BAAANQADCgYIBgAAAA==.Whobe:BAAANQAECgYIDAAAAA==.',
Wi='Witherfang:BAAANQAECgIIAwAAAA==.Wizsera:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.Wizshock:BAAANQAECgYIEgAAAA==.',
Wn='Wnred:BAACNQAFFIEHAAMcAAUJPxQIAQBrAQAcAAQJ5RcIAQBrAQAdAAEJqgUuAgBbAAA1AAQKgRoAAx0ACQmVI6AAAG4DAB0ACQk0IaAAAG4DABwACAkNIo4EAO4CAAAA.',
Wo='Wombly:BAAANQADCgQIBAAAAA==.Womboree:BAAANQAECgUIBwAAAA==.Wonderful:BAAANQADCgIIAgAAAA==.Woobie:BAAANQADCgEIAQAAAA==.',
Xa='Xanarius:BAAANQADCggIFwAAAA==.',
Ye='Yeofp:BAAANQADCgMIAQAAAA==.',
Yk='Ykime:BAAANQADCgEIAQAAAA==.',
Yu='Yukarna:BAAANQAECgUIBgAAAA==.',
Za='Zaafkiel:BAAANQAECgcIEQAAAA==.Zanaroth:BAAANQADCgcIEQAAAA==.Zandrissil:BAEANQADCgYIBgABNQAECgQIBAABAAAAAA==.Zarafie:BAEANQADCgUIBwABNQAECgQIBAABAAAAAA==.Zaraphym:BAEANQAECgQIBAAAAA==.Zarreh:BAAANQADCggIGAAAAA==.',
Ze='Zephyrine:BAAANQADCgQIBAAAAA==.',
Zh='Zhuzhu:BAAANQAECgYICQAAAA==.',
Zi='Zigy:BAAANQAECgcIDQAAAA==.',
Zo='Zoeý:BAAANQADCgcIBwAAAA==.Zombie:BAAANQAECgQIBgAAAA==.',
Zu='Zukko:BAAANQADCggIEAAAAA==.Zulkaris:BAAANQADCggICAAAAA==.Zuroxxar:BAEANQADCggICgABNQAECgQIBAABAAAAAA==.Zuwitsudh:BAAANQADCgQIBAAAAA==.',
Zy='Zynny:BAAANQAECgYIBgAAAA==.',
['Zë']='Zëll:BAAANQADCgYIDAAAAA==.',
['Åa']='Åa:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
['Ðo']='Ðolo:BAAANQADCgQICAABNQAECgQIBAABAAAAAA==.',
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
