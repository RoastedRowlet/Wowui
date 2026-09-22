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

local lookup = {'Mage-Arcane','Paladin-Retribution','DeathKnight-Blood','Evoker-Devastation','Unknown-Unknown','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Warrior-Protection','Paladin-Holy','Druid-Guardian','Rogue-Assassination','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Shaman-Restoration','Druid-Balance','Druid-Feral','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Priest-Holy','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Hunter-Marksmanship','DemonHunter-Havoc','Rogue-Subtlety','Druid-Restoration','Evoker-Preservation','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aadda:BAABNQAECoEfAAIBAAkKCxeEUgCUAgABAAkKCxeEUgCUAgAAAA==.',
Ab='Abcdpal:BAABNQAFFIEJAAICAAUKNR0XAgDsAQACAAUKNR0XAgDsAQAAAA==.Abena:BAAANQAECgUIBgAAAA==.Abighoul:BAAANQADCgYIBgAAAA==.Abusive:BAABNQAECoEgAAIDAAkKGR4hDgABAwADAAkKGR4hDgABAwAAAA==.',
Ac='Acat:BAAANQAECgEIAgAAAA==.',
Ae='Aerogosa:BAABNQAECoEgAAIEAAkKwSFeAwBQAwAEAAkKwSFeAwBQAwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAAANQAECgcJEgAAAA==.',
Ah='Ahlaris:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.',
Ai='Aicam:BAAANQAECgEJAQAAAA==.',
Ak='Akaza:BAAANQABCgIIBAAAAA==.',
Al='Alanalanalan:BAAANQAECgEIAQAAAA==.Alarg:BAAANQADCgIIAgABNQAECgUJCwAFAAAAAA==.Alatide:BAAANQAECgUJCwAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Altazar:BAABNQAECoEYAAIBAAcKUhAboADIAQABAAcKUhAboADIAQAAAA==.Alxath:BAABNQAECoEYAAIGAAgKrB/WDADmAgAGAAgKrB/WDADmAgAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAAANQAECgcJCwAAAA==.Amorinaron:BAABNQAECoEuAAIBAAkKEx+LIQAxAwABAAkKEx+LIQAxAwAAAA==.',
An='Anansi:BAAANQAECgIIAgABNQAFFAYIDwAEAFAgAA==.Andsong:BAAANQADCgUIBQABNQAECgUJCQAFAAAAAA==.Anfalas:BAABNQAECoEsAAIHAAkKYx7GDgA/AwAHAAkKYx7GDgA/AwAAAA==.Anic:BAAANQAECgYIDQAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgQIBgAAAA==.Anklestabber:BAABNQAECoEXAAIIAAgKYR+yAgDlAgAIAAgKYR+yAgDlAgAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anthlina:BAAANQADCgUJBwAAAA==.',
Ar='Archicrash:BAAANQADCgcICwAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAFAAAAAA==.Arcwave:BAAANQADCgcIEgAAAA==.Arcyon:BAAANQAECgYJDAAAAA==.Arethi:BAACNQAFFIEGAAIJAAMKsSQjAQBJAQAJAAMKsSQjAQBJAQA1AAQKgRwAAgkACQq0I3oBAIwDAAkACQq0I3oBAIwDAAAA.Arleos:BAABNQAECoEXAAIKAAgK5xmgJQB3AgAKAAgK5xmgJQB3AgAAAA==.Arroyo:BAAANQADCggIFwAAAA==.Artemasz:BAAANQAECgQJBgAAAA==.',
As='Asrelle:BAAANQAECgYIEgAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQADCgcJDAAAAA==.Astralfrog:BAAANQAECgQIBQAAAA==.',
At='Ateelasham:BAAANQABCgQIBQAAAA==.Atrophied:BAAANQAECgIIAgABNQAECggJGQALAL8fAA==.',
Au='Audeline:BAAANQAECgEIAgAAAA==.Augmented:BAAANQABCgYICgABNQAECggIIQAKAP4mAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQAECgEJAQAAAA==.',
Av='Avran:BAABNQAECoEXAAIGAAgK4xCrHAAbAgAGAAgK4xCrHAAbAgAAAA==.',
Az='Aziala:BAAANQAECgUIBQABNQAECggIHgAEAN8gAA==.Azreluna:BAABNQAECoEXAAIMAAgKsApoHgDuAQAMAAgKsApoHgDuAQAAAA==.',
Ba='Bajablight:BAAANQAECgEIAQAAAA==.Bajiggitee:BAABNQAECoEfAAIDAAgKiRhYIgBDAgADAAgKiRhYIgBDAgAAAA==.Ballsakz:BAAANQAECgMIAwABNQAECgUIBQAFAAAAAA==.Bananarosin:BAAANQAECgUJEAAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQABCgIJAgAFAAAAAA==.Baradoon:BAAANQAECgQIBwAAAA==.Bazrameet:BAAANQAECgYICQABNQAECgkJHQAEALYNAA==.',
Be='Bealzhunter:BAAANQADCgUJBgAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgIJAgAAAA==.Beo:BAABNQAECoEfAAINAAkK9hcyCQChAgANAAkK9hcyCQChAgAAAA==.',
Bi='Bigbluetaco:BAABNQAECoEaAAQOAAgKShilUAApAgAOAAgKgxWlUAApAgAJAAcKwg7gEQBvAQAPAAIKNgiZHABaAAAAAA==.Bigchug:BAABNQAECoEbAAIQAAkKUBrKCgDZAgAQAAkKUBrKCgDZAgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAFAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blech:BAABNQAECoEaAAIBAAcK7wsQsACkAQABAAcK7wsQsACkAQAAAA==.',
Bo='Bookerneg:BAAANQAECgQJBgAAAA==.Boomslang:BAAANQAECgQJCAAAAA==.Borlen:BAAANQAECgQJBwAAAA==.',
Br='Braids:BAAANQADCgUIBQABNQADCgUIBwAFAAAAAA==.Brassfeather:BAAANQAECgMIBQAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYIBgABNQAECgYJDgAFAAAAAA==.Brezzon:BAAANQAECgYJDgAAAA==.Brizzletwo:BAAANQAECgYIDQAAAA==.Brozzath:BAAANQAECgYICgABNQAECgYJDgAFAAAAAA==.Bryanka:BAAANQADCggICgAAAA==.Brättie:BAAANQADCggIEwAAAA==.Bróx:BAABNQAECoEXAAIOAAgK2xMwXAD/AQAOAAgK2xMwXAD/AQAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAYIDwAEAFAgAA==.Bubbajr:BAAANQAECgMJAwAAAA==.Burgy:BAAANQAECgQICwAAAA==.Burgydk:BAAANQAECgYIEAAAAA==.Buttfancy:BAAANQAECgYIEwAAAA==.',
['Bï']='Bïgdot:BAAANQAECgcIBwAAAA==.',
Ca='Caliery:BAAANQABCgEIAQAAAA==.Calmpressure:BAAANQAECggIDgAAAA==.Capnsparrow:BAAANQAECgEJAQAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgcJCQAAAA==.Carshas:BAAANQADCgYIBgAAAA==.Cas:BAAANQADCgIIAgAAAA==.Cassielee:BAAANQAECgIIAgAAAA==.Catabop:BAAANQAECgIIAwABNQAECggIGgARAKcfAA==.Catastorm:BAABNQAECoEaAAIRAAgKpx/FGADDAgARAAgKpx/FGADDAgAAAA==.Catavoker:BAAANQAECgQIBAABNQAECggIGgARAKcfAA==.Caustic:BAAANQAECgcJEQAAAA==.Caveatemptor:BAABNQAECoEdAAISAAgKxSFiGAC2AgASAAgKxSFiGAC2AgAAAA==.',
Ce='Celaina:BAAANQAECgMJAwAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgEJAQAAAA==.Chimeric:BAABNQAECoEZAAMLAAgKvx83BADkAgALAAgKvx83BADkAgATAAYKlwg6EgAgAQAAAA==.Chlover:BAAANQAECgQJBAAAAA==.Chmap:BAAANQADCggJFQABNQAECgEJAQAFAAAAAA==.Chontosh:BAAANQAECgQICAAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgEIAgAAAA==.',
Ci='Cindymccain:BAAANQAECgUJDgAAAA==.',
Cl='Clearsight:BAAANQAECgMJBAABNQAECgcIEwAFAAAAAA==.Clemfandengo:BAAANQAECgEIAgAAAA==.',
Co='Cometh:BAAANQADCggIEAAAAA==.Compute:BAABNQAECoEuAAIUAAkKMB3uDADbAgAUAAkKMB3uDADbAgABNQAECggJEAAFAAAAAA==.Corursa:BAAANQADCgcJCwABNQAECgUIBQAFAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Critterr:BAAANQABCggIDAAAAA==.Cronauer:BAAANQAECgIJAwAAAA==.Cryofrog:BAAANQABCgMJBgAAAA==.',
Cu='Cuppicakies:BAAANQADCgMIBAAAAA==.',
Da='Dabbington:BAAANQABCgYIBwAAAA==.Daddilock:BAAANQAECgEIAQAAAA==.Daddyfatslap:BAAANQAFFAEIAQAAAA==.Daggerz:BAAANQAECgUIDAAAAA==.Daguitas:BAAANQAECgQJBAAAAA==.Danasty:BAAANQABCgIIBQAAAA==.Danidakiesh:BAAANQAECgMIAwAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAAANQAECgQICQAAAA==.Daribow:BAAANQADCgcICwAAAA==.Darkcoffee:BAAANQAECggJDgAAAA==.Darkvalk:BAAANQADCgEJAQAAAA==.Daroc:BAAANQAECggIBgAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggJEAAAAA==.Dawgan:BAAANQAECgIIAwAAAA==.',
De='Deadlyfrog:BAAANQABCgQIBQAAAA==.Deamionn:BAAANQAECgQIBgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Demoinc:BAABNQAECoEZAAMPAAgKARkIBwAHAgAPAAYK7R0IBwAHAgAOAAYKqg8fjQBeAQAAAA==.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAECggIHQASAMUhAA==.Desipator:BAAANQAECgMIAwAAAA==.Destinyløl:BAAANQAECgUIBQAAAA==.',
Di='Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQADCgYJCQAAAA==.Divalatina:BAACNQAFFIEKAAIKAAUKGAMCBwBhAQAKAAUKGAMCBwBhAQA1AAQKgSIAAgoACQp/FWAiAIsCAAoACQp/FWAiAIsCAAAA.Divinefrog:BAAANQAECgEIAQAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAAANQAECgYIEgAAAA==.',
Dl='Dlxanomaly:BAAANQAECgYJDAAAAA==.',
Do='Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQAECgIIAgAAAA==.Dotsdaddy:BAAANQADCggJDwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIDQAAAA==.Dragondzntz:BAAANQAECgQIBgAAAA==.Dragonfrog:BAAANQABCgYICQAAAA==.Dragonmans:BAAANQADCgYIBgAAAA==.Dreamyeyes:BAAANQAECgUIDQAAAA==.Drerein:BAAANQAECgEIAQAAAA==.',
Du='Dubz:BAAANQAECggICgAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECoEhAAMVAAkKjBcZGwCOAgAVAAkKjBcZGwCOAgAUAAIK1w3OXABsAAAAAA==.Dupichu:BAAANQAECgYJDwAAAA==.',
Dy='Dyane:BAAANQADCgUIBQAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgUIBgAAAA==.',
El='Elekastra:BAAANQADCgcIEAAAAA==.Ellonan:BAAANQADCggICwABNQAECgkJHQAWALsTAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAAANQAECgYJDgAAAA==.Emopower:BAAANQAECgUICwAAAA==.',
En='Enderr:BAABNQAECoEWAAIQAAgKlRmnEABuAgAQAAgKlRmnEABuAgAAAA==.Enegma:BAAANQADCgYIBgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQJBAAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgUJDAABNQABCgIJAgAFAAAAAA==.Farwest:BAAANQADCgUIBQAAAA==.Fatherchung:BAAANQAECgEIAQAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQADCggIEwABNQAECggIHAAPAJMWAA==.Feythe:BAAANQADCgUJBQABNQAECggIFgAQAJUZAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgUIBQAAAA==.',
Fl='Flarehammer:BAABNQAECoEaAAICAAgKSiEeIwDaAgACAAgKSiEeIwDaAgAAAA==.Flogh:BAAANQAECgYIDQAAAA==.',
Fo='Fomanshi:BAABNQAECoEdAAIEAAkKtg3cDgAYAgAEAAkKtg3cDgAYAgAAAA==.Forleaf:BAAANQADCgYIBgAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBwAAAA==.Frexican:BAAANQAECgYJDgAAAA==.Fright:BAAANQAECgQIBgAAAA==.Frogleggs:BAAANQABCgMIAwAAAA==.Frogshock:BAAANQABCgcICQAAAA==.',
Fu='Fupabean:BAAANQADCgcIBwAAAA==.Fure:BAAANQADCgQIBAAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
['Fí']='Fíg:BAAANQADCgYIBgAAAA==.',
Ga='Gangdat:BAAANQADCgYIBgAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.Gewl:BAAANQADCgUIBQABNQAECggIFgAQAJUZAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgIIAwAAAA==.',
Go='Gorpy:BAACNQAFFIEKAAMXAAYKHx6lAQADAgAXAAUKhCKlAQADAgAYAAIKsRIrCACtAAA1AAQKgSQABBcACQphJRcLADUDABcACAoIJRcLADUDABgABwrCHXQIAFsCABkAAQrTHmwZAFkAAAAA.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcJDQAAAA==.Greenjesh:BAABNQAECoEWAAIBAAkKLxeeYQBqAgABAAkKLxeeYQBqAgAAAA==.Greensheesh:BAABNQAECoEdAAIBAAkKvxYhTwCeAgABAAkKvxYhTwCeAgABNQAECgkJFgABAC8XAA==.Greypilgram:BAAANQAECgIJAgAAAA==.Grimstank:BAAANQADCggJFQAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQAECgEIAQAAAA==.Grumbleface:BAACNQAFFIEIAAIKAAQKCRHCBwBJAQAKAAQKCRHCBwBJAQA1AAQKgR4AAgoACQqaH9wLADMDAAoACQqaH9wLADMDAAAA.Grumbletron:BAAANQAECgYJDwAAAA==.',
Gs='Gstatus:BAABNQAECoEWAAIHAAgKRQ0qRgDaAQAHAAgKRQ0qRgDaAQAAAA==.',
Gu='Gunel:BAAANQAECgEIAgAAAA==.',
Ha='Haawee:BAAANQAECgQIBQAAAA==.Hailcthulhu:BAABNQAECoEZAAIGAAcKux0mFwBdAgAGAAcKux0mFwBdAgAAAA==.Handcuffs:BAAANQAECgMJAwAAAA==.Handorn:BAAANQAECgMIBAABNQAECgkJJAAZAOEbAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAAANQAECgMJBgAAAA==.Haze:BAAANQAECggICAAAAA==.Hazzkul:BAABNQAECoEXAAIaAAcKaCNEHgDGAgAaAAcKaCNEHgDGAgAAAA==.',
He='Healness:BAABNQAECoEWAAIRAAgK5SIFDwAQAwARAAgK5SIFDwAQAwAAAA==.Helasam:BAAANQAECgIIAwAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAAANQAECgYJDgAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMJAwAAAA==.Hermes:BAABNQAECoEdAAMXAAgKMB64JACTAgAXAAcKKx+4JACTAgAYAAQKrA/kLQDuAAAAAA==.Hermestrisme:BAAANQADCgUJCAAAAA==.',
Hi='Hiemultis:BAAANQADCggJCAAAAA==.',
Ho='Holexplorer:BAABNQAECoEeAAIOAAgKiB9qJQDcAgAOAAgKiB9qJQDcAgAAAA==.Holytrashie:BAAANQAECgIJAgAAAA==.Honeybadger:BAAANQAECgYIEgAAAA==.Honnybuns:BAAANQABCgUIBQAAAA==.Hoofsmack:BAAANQADCgIIAgAAAA==.Hordeji:BAAANQADCgYIBgAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.',
Hs='Hsk:BAAANQAECgYJEgAAAA==.',
Hu='Hugostiglitx:BAAANQAECgEJAQAAAA==.Hulkaholic:BAAANQAECggJEAAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkdemon:BAAANQABCgUJBgAAAA==.Hulkhunts:BAAANQABCgUJCgAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ic='Icecat:BAAANQAECgYIDwAAAA==.',
Il='Ilian:BAAANQADCgQICwAAAA==.',
In='Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQADCgYJFgAAAA==.Inê:BAAANQAECgQIDAABNQAECggIDAAFAAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECgYJDQAFAAAAAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.Ironblast:BAAANQAECgYIEAAAAA==.Ironbolt:BAAANQADCgYICgABNQAECgYIEAAFAAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.',
It='Ithanksource:BAAANQAECgYICQABNQAECggIDgABAFMQAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jadethunder:BAAANQADCgEIAQABNQAECgQJBwAFAAAAAA==.Jake:BAAANQAECgEIAQAAAA==.Jankie:BAAANQAECggIEQAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.',
Ji='Jingburger:BAAANQAECggIDAAAAA==.Jinnosuke:BAAANQAECgMIBgAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johhnyp:BAAANQAECgQIAwAAAA==.Johnathanwow:BAAANQAECgQJBwAAAA==.Johnnytotem:BAABNQAECoEaAAMHAAkK4xN4LABeAgAHAAkK4xN4LABeAgARAAcKfAP6fAAPAQABNQAECgQIAwAFAAAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Justicé:BAAANQAECgQJBQAAAA==.',
Jy='Jykyl:BAAANQAECgYIDgAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQAECgIJAQAAAA==.Kaipod:BAAANQAECgUJCgAAAA==.Kaorrii:BAAANQAECgUIBQAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQADCgcIEgABNQAECgQJBwAFAAAAAA==.Kauthoon:BAAANQADCgQJBwAAAA==.Kaykotta:BAAANQADCgUIDQAAAA==.Kazademon:BAAANQAECgYIDgAAAA==.Kazmo:BAAANQAECgcJDQAAAA==.',
Ke='Kegheimer:BAAANQAECgIIAgABNQAECgUIDQAFAAAAAA==.Keigis:BAAANQADCgcICAAAAA==.Kensington:BAAANQAECgUIBQABNQAECggIGQADAOIeAA==.Keyalovar:BAABNQAECoHQAAIbAAgK/SZcAgCpAwAbAAgK/SZcAgCpAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAABNQAECggIAgAFAAAAAA==.',
Ki='Kimbecky:BAAANQADCgQJBQAAAA==.Kimchii:BAAANQADCgUIBgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAAANQAECgYJDgAAAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQAECgMIAwABNQAECgQICQAFAAAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAFAAAAAA==.Knobsnob:BAABNQAECoEgAAQcAAkKOx/rAwA/AgAbAAgKYx04FQDXAgAcAAYKViHrAwA/AgAdAAIKBBDDQwB8AAAAAA==.',
Kr='Kragden:BAAANQADCgMJAwABNQAECgUIDQAFAAAAAA==.Kriztina:BAAANQAECgEIAgAAAA==.Krizu:BAEANQADCgYIBgAAAA==.Kronkk:BAAANQADCgIIAgAAAA==.Kropie:BAAANQAECgUICQAAAA==.Krågden:BAAANQADCgUIBQABNQAECgUIDQAFAAAAAA==.',
Ku='Kunfuzion:BAAANQAECgQICQAAAA==.',
Ky='Kynga:BAAANQADCgUIBwAAAA==.',
La='Ladrian:BAABNQAECoEYAAQXAAkKLBDfWADAAQAXAAcKoBDfWADAAQAYAAIKMgtuTwBuAAAZAAEKcBOqHABIAAAAAA==.Landoresh:BAAANQAECgEIAgAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larenieth:BAAANQADCgcICQAAAA==.Larrykpinga:BAAANQADCgEIAQAAAA==.Larüd:BAAANQAECgcIEwAAAA==.Lasmon:BAAANQAECgcIEwAAAA==.',
Le='Legallyblind:BAAANQAECgcIEwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcJBwABNQAECgYIDQAFAAAAAA==.Lillithx:BAAANQAECgMJAwAAAA==.Lillucy:BAAANQADCgYIBgAAAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQAECgQIBAAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgQIBgAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Lizardfistin:BAACNQAFFIEPAAMEAAYKUCA9AQDlAQAEAAUKLSI9AQDlAQAeAAUKRh47AQDhAQA1AAQKgR0AAwQACQo0JfUBAIYDAAQACQo0JfUBAIYDAB4AAQoXILQUAFoAAAAA.',
Lo='Loads:BAAANQAECggIAQAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Loni:BAAANQAECgQIBgAAAA==.Loonaimp:BAAANQAECgMJBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAABNQAECoEdAAMfAAkKdiPLCQAHAwAfAAgKmyLLCQAHAwAaAAIKLSZ4uQDiAAAAAA==.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAABNQAECoEdAAMWAAkKuxPNDwAdAgAWAAkKuxPNDwAdAgACAAEKfgL2NwElAAAAAA==.Luminarria:BAAANQAECgMJBgAAAA==.Luminisong:BAAANQAECgQJBgAAAA==.Lupomic:BAAANQAECgIIAwAAAA==.',
Ma='Maeivalla:BAAANQAECgcJEQAAAA==.Mageler:BAAANQAECgcIEQAAAA==.Magicpurro:BAAANQAECggIDgABNQAFFAYIDwAEAFAgAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECgcIBwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECoEkAAIBAAkK4xk0QgDFAgABAAkK4xk0QgDFAgAAAA==.Margolis:BAAANQADCggICgABNQAFFAYICgAXAB8eAA==.Margrathwin:BAABNQAECoEYAAIHAAgKHRCZQAD0AQAHAAgKHRCZQAD0AQAAAA==.Marxman:BAAANQAECgYIBgABNQAFFAUJCQAfAOoOAA==.Mask:BAAANQADCgUIBQAAAA==.Mauchs:BAAANQADCgUICQAAAA==.',
Me='Meganite:BAAANQADCgYJFQAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAABNQAECoEZAAMgAAcKhRFrKADJAQAgAAcKhRFrKADJAQAGAAMKqAHrSgBjAAAAAA==.Milkmountain:BAAANQADCgIJAwAAAA==.Milkymoo:BAAANQADCgYIBgAAAA==.Minalina:BAAANQAECggIDQAAAA==.Minalinapr:BAAANQAECggJBAAAAA==.Minalinaria:BAAANQAECggJCgAAAA==.Mindedz:BAAANQAECgcJEwAAAA==.Minnow:BAAANQAECgYIDQAAAA==.Miren:BAAANQAECgcIEwAAAA==.Mittsmitts:BAAANQAECgEIAQAAAA==.',
Mo='Mochiberry:BAAANQAECggIAgAAAA==.Moistbuns:BAAANQAECgcIDAAAAA==.Molatova:BAAANQAECgYJCgAAAA==.Moozart:BAAANQAECgEIAQABNQAECggIGAAgADYXAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgIIAgAAAA==.Mortiferia:BAABNQAECoEdAAIbAAgKeiJvDgALAwAbAAgKeiJvDgALAwAAAA==.Mortzx:BAAANQAECgQIBAAAAA==.Motown:BAAANQAECggIEgAAAA==.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAABNQAECoEXAAIhAAgKFB+HBwDgAgAhAAgKFB+HBwDgAgAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgQJBwAFAAAAAA==.Mythomagic:BAAANQAECgcJEgAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Nakotak:BAAANQABCgQJBAAAAA==.Nanalady:BAAANQADCggICAAAAA==.Nastyjob:BAAANQAECgYIDAAAAA==.Nazgar:BAAANQADCgUJBQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggJEQAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQADCggIDwAAAA==.Nibelung:BAABNQAECoEkAAMSAAgKoiNdDQAwAwASAAgKoiNdDQAwAwAiAAEK2x++RABcAAAAAA==.Nikale:BAAANQAECgUIDQAAAA==.',
No='Nordy:BAAANQAECgUICwAAAA==.Normadin:BAAANQAECgYIEQAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYJCgABNQADCgIIAgAFAAAAAA==.',
Nv='Nvd:BAABNQAECoETAAMGAAkKfB4uFACBAgAGAAgKoyEuFACBAgAgAAEKRwVNYAA4AAABNQAFFAIJAgAFAAAAAA==.',
Ny='Nyan:BAAANQAECgcICQABNQAECggIIQAKAP4mAA==.Nysonnia:BAAANQAECgYICwABNQAECggIIQAKAP4mAA==.',
Ob='Obliterate:BAAANQAECgQJBwAAAA==.Obsidianfire:BAAANQADCgQIBAABNQAECgQJBwAFAAAAAA==.',
Od='Odonn:BAAANQADCgUICAAAAA==.Odìnsôn:BAAANQADCggIIAAAAA==.',
Om='Omegafortswl:BAAANQADCgYJFgAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.',
Oo='Oogiie:BAAANQADCgQIBAAAAA==.',
Or='Orbits:BAAANQAECgMIAwAAAA==.Oric:BAABNQAECoEhAAIKAAgK/iYcAwCkAwAKAAgK/iYcAwCkAwAAAA==.',
Pa='Pallverize:BAAANQADCggICAAAAA==.Pannmann:BAAANQAECgQJBAAAAA==.Panzerhunt:BAAANQAECgUIBQABNQAECgkJGAACAEAcAA==.Panzerpala:BAABNQAECoEYAAICAAkKQBx3JgDIAgACAAkKQBx3JgDIAgAAAA==.Panzersham:BAAANQADCggICAAAAA==.Paperdaen:BAAANQAECgYJCAAAAA==.Parkle:BAAANQADCgYIDwAAAA==.Pastore:BAAANQAECgcIDQAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgIIAgAAAA==.Pepitopingon:BAAANQABCggICwAAAA==.',
Pf='Pfeffernusse:BAABNQAFFIEJAAIfAAUK6g72BQCFAQAfAAUK6g72BQCFAQAAAA==.',
Ph='Phalluic:BAAANQADCgYIBgAAAA==.Philpriest:BAAANQAECggIEgAAAA==.',
Pl='Plagued:BAAANQAECgQJBwABNQABCgIJAgAFAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAAANQAECgcJDwAAAA==.Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAAANQAECgYICAAAAA==.',
Pr='Pragmax:BAAANQAECgYICQAAAA==.Praynation:BAAANQADCggJDAAAAA==.Prediction:BAAANQAECgEIAgAAAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAAANQAECgcJEQAAAA==.Purplehayz:BAAANQADCgMJAwAAAA==.',
Py='Pyrogale:BAAANQADCggIFgAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQAAAA==.',
Ql='Qlimax:BAAANQAECgEJAQAAAA==.',
Qu='Quadzilla:BAAANQAECgQIBAAAAA==.Quem:BAAANQAECgYJBQAAAA==.',
Ra='Rachet:BAAANQADCgYJBgAAAA==.Ragnalock:BAAANQAECgIJAgAAAA==.Ragnir:BAAANQADCgUIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMJAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQAECgIJAgAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQADCgUIDgAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAABNQAECoEcAAIhAAgKFRiADQBtAgAhAAgKFRiADQBtAgAAAA==.Relarian:BAAANQAECgUICQAAAA==.Releimus:BAAANQAECgYJBgAAAA==.Rentera:BAAANQADCggICAAAAA==.Revengeance:BAABNQAECoEXAAIWAAgKdhO3EwDgAQAWAAgKdhO3EwDgAQAAAA==.',
Ri='Rissler:BAAANQADCgMIAwAAAA==.',
Rm='Rmplstilskin:BAAANQADCgUIBQAAAA==.',
Ro='Roanoke:BAAANQABCgMIAwAAAA==.Rocketsauce:BAAANQAECgUJBwAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAFAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCgYIBgAAAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAAANQAECgYJEAAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAACNQAFFIEFAAIbAAMKuBjjCwAZAQAbAAMKuBjjCwAZAQA1AAQKgSIAAxsACQoxID8MACADABsACQr3Hz8MACADABwABArLHI0MABEBAAAA.Runehulk:BAAANQABCgQJBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.',
Ry='Ryuunosuke:BAABNQAECoEXAAIjAAgKfRKeFQD1AQAjAAgKfRKeFQD1AQAAAA==.',
Sa='Sabers:BAAANQAECgcJDgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinachi:BAAANQABCgIIAgAAAA==.Sabrinadin:BAAANQABCgQIBQAAAA==.Sadako:BAAANQADCgUICgAAAA==.Sakkraa:BAABNQAECoEkAAMZAAkK4RtGAQAJAwAZAAkK4RtGAQAJAwAXAAEKdg7Q3gA9AAAAAA==.Salla:BAAANQAECgMIAwAAAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAAANQAECgUJDQAAAA==.',
Sc='Schwimdy:BAAANQAECgQIBwAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Seeingeyedog:BAAANQAECgYIEgAAAA==.Seraphicfrog:BAAANQABCgYICgAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.',
Sh='Shadowscythe:BAAANQAECgQJCAAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Sharish:BAAANQABCgIIAgAAAA==.Shaundel:BAABNQAECoEhAAIRAAgKSRlRMAA4AgARAAgKSRlRMAA4AgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shezmu:BAABNQAECoEYAAIDAAgKDiFbDgD+AgADAAgKDiFbDgD+AgAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAECgkJHQAgANccAA==.Shlorp:BAAANQADCgIIAgAAAA==.Shoopa:BAAANQAECgMJBAAAAA==.Shoopah:BAAANQAECgUIEAAAAA==.Short:BAABNQAECoEWAAIhAAgK5gkgGADhAQAhAAgK5gkgGADhAQAAAA==.Shunned:BAAANQAECgEIAQAAAA==.Shyok:BAAANQADCgEJAQAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Siduiss:BAAANQAECgMJBAAAAA==.Silvrfoxx:BAAANQAECgEIAgAAAA==.Silvänus:BAABNQAECoEeAAMiAAgKESElCADxAgAiAAgKESElCADxAgASAAEKIwYvggAyAAAAAA==.Simsha:BAAANQAECgQIDAAAAA==.',
Sk='Skinnylejend:BAABNQAECoEVAAMdAAgKmxlMGAAiAgAdAAcK8RhMGAAiAgAbAAEKywWjpgA/AAAAAA==.Skipperty:BAAANQAECgEIAQAAAA==.Skizzy:BAAANQADCgMIAwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYJBgAAAA==.',
Sm='Smiley:BAAANQAECgUIEQAAAA==.',
Sn='Snac:BAAANQAECgIJAwAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAAANQAECgYJBwAAAA==.Sneakybeanz:BAAANQADCggIDAAAAA==.',
So='Someperson:BAAANQAECgQIBAAAAA==.Somoner:BAABNQAECoEhAAMYAAcKMCLsBAC2AgAYAAcKMCLsBAC2AgAZAAEKsw/GIAA6AAAAAA==.Sompal:BAAANQAECgQIBgABNQAECgcIIQAYADAiAA==.',
Sp='Sparksizzle:BAABNQAECoEfAAMBAAkKeRMKYwBlAgABAAkKeRMKYwBlAgAkAAMKqAZCBQCsAAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECoEYAAQYAAkKjCDDBQCcAgAYAAkKuhfDBQCcAgAXAAUK3B+AbQB8AQAZAAEKSRwKHABKAAABNQAFFAQJBAAFAAAAAA==.Spitfirex:BAAANQAFFAQJBAAAAA==.Spreadshecat:BAABNQAECoEOAAIBAAgKUxAWggASAgABAAgKUxAWggASAgAAAA==.',
St='Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQADCgcICAAAAA==.Stopzîlla:BAAANQAECgYJEAAAAA==.Strûmpet:BAAANQAECgIJAgAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sw='Swippie:BAAANQADCgYIEAAAAA==.',
Sy='Sylmar:BAAANQADCggIFAAAAA==.Syndora:BAABNQAECoEZAAIiAAgK6BrYEQBMAgAiAAgK6BrYEQBMAgAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQADCggIDgAAAA==.Tahu:BAAANQAECgYJDQAAAA==.Takal:BAAANQADCgYICwAAAA==.Talorn:BAAANQADCgUIBQAAAA==.Talreth:BAAANQAECgMIAwAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECgYJEgAFAAAAAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAAANQAECgYJDwAAAA==.Telemarketer:BAAANQADCgIIAgAAAA==.Tenebrisol:BAAANQADCgYJBgAAAA==.Ternal:BAAANQAECgEIAQAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAAANQAECgQIBwAAAA==.Terrous:BAABNQAECoEgAAIVAAkKZRucEwDUAgAVAAkKZRucEwDUAgAAAA==.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAAANQAECgYIEAAAAA==.Theoslight:BAAANQAECgIIAgAAAA==.Thepetmaster:BAAANQADCgUICgAAAA==.Thiccaxe:BAAANQAECgQIBAAAAA==.Thighler:BAAANQAECgUIBwAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Thraxia:BAAANQABCgQIBAAAAA==.Threxon:BAAANQAECgcJCwAAAA==.Thunderfire:BAAANQAECgQJBwAAAA==.',
Ti='Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAABNQAECoEiAAMGAAkKCx0iDwDEAgAGAAgKRB4iDwDEAgAlAAEKRBPNHABAAAAAAA==.Tokash:BAAANQADCggICQABNQAECgkJIgAGAAsdAA==.Tokashi:BAAANQAECgcIDQABNQAECgkJIgAGAAsdAA==.Tokeadin:BAAANQAECgYJEQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcJCgAAAA==.Toriimage:BAAANQAECgEIAQAAAA==.Toughluck:BAAANQADCgQIBAAAAA==.',
Tr='Trackervalk:BAAANQADCgIIAgAAAA==.Traellissa:BAAANQAECgEIAQAAAA==.Treeady:BAAANQAECgMJAgAAAA==.Trenbölöne:BAABNQAECoEaAAIOAAgKfx19MQCkAgAOAAgKfx19MQCkAgAAAA==.Treyrin:BAAANQAECgYIDgAAAA==.Tritonian:BAACNQAFFIEQAAIWAAYKiiU1AACkAgAWAAYKiiU1AACkAgA1AAQKgSEAAhYACQoqJp8AAN8DABYACQoqJp8AAN8DAAAA.Trixio:BAABNQAECoEWAAIMAAgK4B+4CAD/AgAMAAgK4B+4CAD/AgAAAA==.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAFFAYICgAXAB8eAA==.',
Tu='Turtle:BAABNQAECoEqAAIKAAkKzBvfEwDtAgAKAAkKzBvfEwDtAgAAAA==.',
Tw='Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAAANQAECgUJDAAAAA==.Tyranis:BAAANQADCgIIAgAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAAANQAECgYIEQAAAA==.',
Ud='Uddercleanse:BAAANQADCgYIBgABNQAECgkJIAAcADsfAA==.',
Um='Umbrianna:BAABNQAECoEWAAIgAAcK5QNQOwAfAQAgAAcK5QNQOwAfAQAAAA==.',
Un='Undeadashyra:BAAANQADCgYIBgAAAA==.Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uw='Uwuclapmexd:BAAANQADCgMJAwAAAA==.Uwuhunterxd:BAACNQAFFIEFAAIfAAIK3wUyEgCBAAAfAAIK3wUyEgCBAAA1AAQKgR0AAx8ACQqXGJ4SAIgCAB8ACQohGJ4SAIgCABoAAQpeIhDeAGQAAAAA.',
Va='Vaelowyn:BAAANQAECgEIAgAAAA==.Vaelthyr:BAAANQADCgcJCAABNQAECgkJHQAWALsTAA==.Vakar:BAAANQAECgQJCQAAAA==.Valkyriee:BAAANQABCgQIBgAAAA==.Varninn:BAAANQADCgcJDwAAAA==.Varonos:BAAANQAECggIAgAAAA==.Vasha:BAAANQAECgUIBQAAAA==.',
Ve='Ventee:BAAANQAECgMJBgAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQADCgYICwABNQAECggIHwADAIkYAA==.Vitadin:BAAANQAECgIIBQAAAA==.',
Vr='Vraugashan:BAAANQAECgYJCQAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECgYIEQAFAAAAAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.',
We='Wesson:BAAANQAECgQICgAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAAANQAFFAEJAQAAAA==.Wireless:BAABNQAECoEZAAMMAAgKUw4+IgDIAQAMAAcKTw0+IgDIAQAhAAcK5QlzHwCRAQAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgQJBwAAAA==.',
Xa='Xau:BAAANQABCgYIBgAAAA==.Xaveak:BAAANQADCgUIBQAAAA==.',
Xe='Xencero:BAAANQAECgQIBgABNQAECgQJBwAFAAAAAA==.Xeum:BAAANQAECgUIEQAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAAANQAECgYIDQAAAA==.Xhyros:BAABNQAECoEeAAIEAAgK3yBBBgD1AgAEAAgK3yBBBgD1AgAAAA==.',
Xi='Xiahou:BAABNQAECoEXAAIBAAgKayCnNADvAgABAAgKayCnNADvAgAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAFFAYICgAXAB8eAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAABNQAECoEkAAIEAAkKDSPmAQCIAwAEAAkKDSPmAQCIAwAAAA==.',
Yu='Yuanfen:BAAANQAECgEIAQAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgUJCwAAAA==.Zamlen:BAABNQAECoEaAAIBAAgKLRcPaQBWAgABAAgKLRcPaQBWAgAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAFAAAAAA==.Zazie:BAABNQAECoEWAAIDAAgKVhIbNADNAQADAAgKVhIbNADNAQAAAA==.',
Ze='Zedicuzz:BAAANQAECgQJDQAAAA==.Zeesala:BAAANQADCgUIBwABNQAECggIIQAKAP4mAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAAANQAECgUJCgAAAA==.',
Zu='Zugzugzugzug:BAABNQAECoEWAAMUAAgKDiMJCQAYAwAUAAgKDiMJCQAYAwADAAMKNSCPVwAYAQAAAA==.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQADCgYIDAABNQAECgUIBQAFAAAAAA==.',
['Ñe']='Ñemo:BAABNQAECoEdAAMaAAgKyiI8EgARAwAaAAgKyiI8EgARAwAfAAMKQxBKRQCSAAAAAA==.',
['Ør']='Øreo:BAAANQADCggIFQAAAA==.',
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
