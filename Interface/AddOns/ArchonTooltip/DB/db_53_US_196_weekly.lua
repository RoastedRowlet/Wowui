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

local lookup = {'Paladin-Holy','Unknown-Unknown','Druid-Balance','Druid-Restoration','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','Priest-Shadow','Hunter-BeastMastery','Mage-Arcane','DemonHunter-Vengeance','Paladin-Retribution','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Frost','Priest-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Evoker-Preservation','Priest-Discipline','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aakura:BAABNQAECoEcAAIBAAgKChvnIQCNAgABAAgKChvnIQCNAgAAAA==.Aamira:BAAANQADCgUJDAAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQADCggIEwAAAA==.',
Ad='Adamantus:BAAANQAECgEJAQAAAA==.Admetus:BAAANQADCgYIBgAAAA==.',
Ae='Aelasong:BAAANQADCgcIDQAAAA==.Aelioran:BAAANQAECgUJDAAAAA==.Aenlor:BAAANQAECgEIAQAAAA==.Aerwen:BAAANQADCgQJBAAAAA==.Aestar:BAAANQAECgMIAwAAAA==.Aethias:BAAANQADCgQJBAAAAA==.',
Ag='Aghwang:BAAANQAECgEIAQAAAA==.',
Ai='Airedhiel:BAAANQADCggIFgAAAA==.',
Ak='Akttara:BAAANQADCgIIAgAAAA==.',
Al='Alacantos:BAAANQAECgUIDgAAAA==.Alainnaingil:BAAANQADCggICAAAAA==.Alanjackson:BAAANQADCgYJEwAAAA==.Alawyn:BAAANQAECgYIEAAAAA==.Alayssaria:BAAANQAECgUJCwAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQAECgEIAQABNQAECgYJEAACAAAAAA==.Alltaken:BAAANQADCgcIEAAAAA==.Alokin:BAAANQADCgEIAQAAAA==.Alpharetta:BAACNQAFFIEFAAIDAAMKZB0vCgAjAQADAAMKZB0vCgAjAQA1AAQKgSAABAMACQpSHh4TAOwCAAMACQpSHh4TAOwCAAQABQohDy0rABsBAAUAAQrjEYghAEUAAAE1AAUUBQkJAAYA0xUA.Alsera:BAAANQAECggIEQAAAA==.',
Am='Amarae:BAAANQADCggJEgAAAA==.Amicoolyet:BAAANQADCgcIHgAAAA==.Ammon:BAAANQADCgYICAAAAA==.Amorene:BAABNQAECoEfAAMHAAkK8xxiFwDMAgAHAAkK8xxiFwDMAgAGAAgKqRbKMQA/AgAAAA==.Amorvane:BAAANQAECgUICQABNQAECgkJHwAHAPMcAA==.Amoryn:BAAANQAECgMIBAABNQAECgkJHwAHAPMcAA==.',
An='Anaraellea:BAAANQADCggIGAAAAA==.Andcheese:BAAANQADCgEIAQABNQAECgUJCgACAAAAAA==.Andramedally:BAAANQADCggIFgAAAA==.Andrusius:BAAANQAECgcJDQAAAA==.Angellena:BAAANQAECgYJDgAAAA==.Anian:BAAANQADCgYJEwAAAA==.Antadin:BAAANQAECgUJCQAAAA==.Anthela:BAAANQAECgYJBgABNQAECgYIDAACAAAAAA==.',
Ap='Apherilia:BAAANQAECgYIBgAAAA==.',
Ar='Aranos:BAAANQADCgYICQAAAA==.Ardrick:BAAANQAECgQIBgAAAA==.Arihua:BAAANQADCggIDgAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Aronau:BAAANQADCgYIDAAAAA==.Arosen:BAAANQAECgIIAwAAAA==.Arradinn:BAAANQAECggIAgAAAA==.Artforidiots:BAAANQAECgcJDAAAAA==.Arthurious:BAAANQADCggIGAAAAA==.',
As='Asenath:BAAANQAECgUJCwAAAA==.Askec:BAAANQAECgQIBQAAAA==.Asmodeus:BAAANQAECgcIDgAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQAECgIJBAAAAA==.',
Av='Avacado:BAAANQADCggICgABNQAFFAYIEQAEAEoYAA==.Avicularia:BAAANQADCgcJBwAAAA==.',
Aw='Awake:BAABNQAECoEYAAIIAAkKPxnAMQCiAgAIAAkKPxnAMQCiAgAAAA==.',
Ax='Axdk:BAAANQAECgUJCwAAAA==.',
Ay='Ayalha:BAAANQAECgcJEQAAAA==.',
Ba='Babychewie:BAAANQAECgYICwAAAA==.Babygumbo:BAAANQAECgQJBQAAAA==.Bacõn:BAAANQABCgQIBAAAAA==.Balla:BAAANQAECgQIBQAAAA==.Bambismash:BAAANQADCgYIDgAAAA==.Bazbuk:BAAANQAECgQIBAAAAA==.',
Be='Beansgreens:BAAANQADCgUJCQAAAA==.Beantism:BAAANQAECgUJCwAAAA==.Beardeath:BAAANQAECgYICwAAAA==.Bearleft:BAAANQABCgQJBgAAAA==.Beaross:BAAANQAECgUIBwAAAA==.Beeflomein:BAAANQAECgYICwAAAA==.Beledros:BAABNQAECoEdAAIJAAkKdx50BwA6AwAJAAkKdx50BwA6AwABNQAECgMJBQACAAAAAA==.Benadarek:BAAANQADCgYIDAAAAA==.Beratol:BAAANQAECgEJAQAAAA==.Bethny:BAAANQADCgYJBgAAAA==.',
Bi='Bigeasy:BAAANQADCgcIHgAAAA==.',
Bl='Blakkadin:BAAANQAECgIIAQABNQAECgkJJwAKAKskAA==.Blayzn:BAAANQADCgUIBwAAAA==.Bloodmoonpal:BAAANQADCgMIAwAAAA==.Bloodychêwy:BAAANQAECgIIAQAAAA==.Bluex:BAAANQADCgMIAwAAAA==.Blutdurst:BAAANQADCggIDAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAFFAUIBwALALQVAQ==.Bonelargeles:BAAANQAECgQIAgAAAA==.Boolk:BAAANQAECgQIBQABNQAECggIHAAMAOgQAA==.Booyaah:BAACNQAFFIEIAAIHAAUKpROVBACiAQAHAAUKpROVBACiAQA1AAQKgRkAAwcACQoYGQwtAEoCAAcACQoYGQwtAEoCAAYAAgpBGfO0AIMAAAAA.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Bravelee:BAAANQADCgYIBgAAAA==.Brazok:BAAANQAECgYIBgAAAA==.Brigade:BAABNQAECoEgAAMBAAkKYhdpIQCQAgABAAkKYhdpIQCQAgANAAQKkRUVrwAJAQAAAA==.Brigadester:BAABNQAECoEfAAIOAAkKzSKEAACRAwAOAAkKzSKEAACRAwAAAA==.Brogaine:BAAANQADCggIFgAAAA==.Broodin:BAAANQADCgYIBwAAAA==.Bruen:BAAANQADCgUIBQAAAA==.',
Bu='Bullbas:BAAANQADCggICgAAAA==.Bumdog:BAAANQAECgMIBAAAAA==.Burritorukh:BAAANQADCggJCAAAAA==.',
Ca='Calrisa:BAAANQAECgYIFAAAAQ==.Calrisyia:BAAANQADCgEIAQABNQAECgYIFAACAAAAAA==.Camin:BAAANQADCgUIBQAAAA==.Cancan:BAAANQAECgYIBgAAAA==.Carterhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAAANQAECgUJCwAAAA==.Cassapedia:BAAANQADCgcJEgABNQAECgUJCwACAAAAAA==.Cassawings:BAAANQADCgUICQABNQAECgUJCwACAAAAAA==.',
Ce='Celestria:BAAANQAECgYICwAAAA==.Celna:BAAANQADCgYJHAAAAA==.Celyssia:BAAANQAECgUJCwAAAA==.Cernos:BAAANQAECgEJAQAAAA==.',
Ch='Chance:BAAANQAECgYIEAAAAA==.Chardclass:BAAANQAECgIIAgABNQAFFAUJCgADAKISAA==.Charzard:BAAANQAECgUICgAAAA==.Cheerio:BAAANQAECgQIBAAAAA==.Cheezit:BAAANQADCggICAAAAA==.Chunknorris:BAAANQAECgUIBQAAAA==.',
Ci='Cinderson:BAAANQABCgMJAwAAAA==.',
Cl='Clömp:BAAANQAECgcJEQAAAA==.',
Co='Cocolu:BAAANQAECgIIAgAAAA==.Concretej:BAAANQADCggICAAAAA==.Coreion:BAAANQADCgcIEgAAAA==.Covvid:BAAANQADCgQIBAAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAABNQAECggIEgACAAAAAA==.Crisstos:BAAANQADCgYIDwAAAA==.Cristhel:BAABNQAECoEZAAIIAAgKHxxPPAB1AgAIAAgKHxxPPAB1AgAAAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQAECgEJAQAAAA==.',
Cs='Csg:BAAANQAECgUJBwAAAA==.',
Cy='Cyllene:BAAANQADCgYIDwAAAA==.',
['Cé']='Cérnunnos:BAAANQAECgYICwAAAA==.',
Da='Daag:BAAANQAECggIDwAAAA==.Daemonslayer:BAAANQAECgEIAQAAAA==.Daftknight:BAAANQAECgcIDgAAAA==.Daisycutter:BAABNQAECoEWAAIPAAgKPhD1IgD+AQAPAAgKPhD1IgD+AQAAAA==.Dakoo:BAAANQADCgIIAgAAAA==.Daluon:BAAANQABCgQIBAABNQAECgcJEQACAAAAAA==.Damai:BAAANQABCgYICgAAAA==.Dances:BAAANQAECgEJAQAAAA==.Daravanthel:BAAANQAECgYJDgAAAA==.Daresh:BAAANQAECgUICwABNQAECggJHQAQANAWAA==.Darkbeast:BAAANQAECgYIEQAAAA==.Darkbáine:BAABNQAECoEZAAIRAAcKCA/5KQCkAQARAAcKCA/5KQCkAQAAAA==.Darkdarion:BAAANQABCggIDQAAAA==.Darling:BAABNQAECoEcAAISAAkKMRHeMgAoAgASAAkKMRHeMgAoAgABNQAECgkKHAASADERAA==.Darmorg:BAABNQAECoEfAAITAAkKGCHVBwBjAwATAAkKGCHVBwBjAwAAAA==.Darthaxe:BAABNQAECoEdAAQUAAkKRRtHGACXAgAUAAkKRRtHGACXAgATAAEKgw17igBDAAARAAEKXw8WagA8AAAAAA==.Daskapital:BAAANQADCgEIAQABNQAECgQJBAACAAAAAA==.',
De='Deadrukh:BAAANQAECgUIBQAAAA==.Deathsurge:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Deegoddaem:BAAANQAECgUIBQAAAA==.Delacour:BAEBNQAECoEYAAILAAgK8hHEdAA1AgALAAgK8hHEdAA1AgABNQAECgYIEAACAAAAAA==.Dembjuicy:BAAANQADCgUIBQAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Derym:BAAANQADCgEIAQAAAA==.Dev:BAAANQAECggIAwAAAA==.Dezz:BAAANQAECgIIAgAAAA==.Dezza:BAAANQAECgQIBAAAAA==.',
Dh='Dharenar:BAABNQAECoEZAAMPAAcKtQ/nKgCxAQAPAAcKtQ/nKgCxAQAQAAMKRgKISAB2AAAAAA==.',
Di='Diazepam:BAAANQADCgYIBgAAAA==.Dingygubgub:BAAANQADCgMJAwAAAA==.Dizzyflores:BAAANQAECgUJCwAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQAECgUICgAAAA==.',
Do='Doomcore:BAAANQAECgcJEQAAAA==.Doomkin:BAAANQADCgMIAwAAAA==.Dooper:BAABNQAECoEcAAIVAAgKvx1KAwCpAgAVAAgKvx1KAwCpAgAAAA==.Dorbinn:BAAANQADCgUJBQAAAA==.Dorrf:BAAANQADCgcICwAAAA==.Doshneil:BAAANQADCggIFgAAAA==.',
Dr='Dragongor:BAAANQAECgEJAQAAAA==.Dragonsmight:BAAANQAECgYIDwAAAA==.Dreamvore:BAAANQAFFAEJAQAAAA==.Droknarr:BAAANQADCgQJBAAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQAECgMICQAAAA==.Dustobones:BAABNQAECoEWAAITAAcKCRYDMQDqAQATAAcKCRYDMQDqAQAAAA==.',
Dw='Dwee:BAAANQADCgUIBQABNQADCggIFQACAAAAAA==.Dweedy:BAAANQADCggIFQAAAA==.Dweela:BAAANQADCgIIAgABNQADCggIFQACAAAAAA==.',
Ea='Ealen:BAAANQADCgYIBgAAAA==.Eastón:BAAANQAECgUJBQAAAA==.',
Ee='Eellyqt:BAAANQADCgQIBAAAAA==.',
El='Eliyana:BAAANQAECgQIBgAAAA==.Elledrus:BAAANQAECgEIAQAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAAANQAECgUJCwAAAA==.Eluniel:BAAANQAECgYICQAAAA==.',
Em='Emberdk:BAACNQAFFIEJAAMTAAUK1RNzAwBmAQATAAQKnRVzAwBmAQAUAAEKtwwEIAApAAA1AAQKgSoAAhMACQrBHK4PAP8CABMACQrBHK4PAP8CAAAA.Emojones:BAAANQAECgIJAwAAAA==.',
Ep='Ephysa:BAAANQADCgYICQAAAA==.',
Es='Essenne:BAAANQADCgcJFwABNQAECgUJCwACAAAAAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgMJBQACAAAAAA==.Etrigg:BAAANQADCggICgAAAA==.',
Ex='Exava:BAAANQADCgEIAQAAAA==.Exstatik:BAAANQAECgcJDgAAAA==.',
Ey='Eyeamgroot:BAAANQAECgYICwAAAA==.Eyeholeman:BAAANQAECgIIAgAAAA==.',
Ez='Ezzrra:BAAANQAECgcJDwAAAA==.',
Fa='Faelunae:BAAANQADCgYIFQAAAA==.Faillock:BAACNQAFFIEGAAMWAAMK8gjECgCZAAAWAAIKNQXECgCZAAAXAAEKbhADIwBQAAA1AAQKgSQAAxcACQoeG8Y/AB4CABcABwo4G8Y/AB4CABYABAp/EBYuAO0AAAAA.Falora:BAAANQADCggIFgAAAA==.Fangshot:BAAANQAECgUJCAAAAA==.Farukk:BAAANQAECggJCAAAAA==.',
Fe='Feldwn:BAAANQADCgMIAwAAAA==.Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAAANQAECgUJCwAAAA==.Fezzik:BAAANQADCgQJBAAAAA==.',
Fi='Filthydegén:BAAANQADCgYIBwAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgQICwACAAAAAA==.Firedemon:BAAANQADCggJHwAAAA==.Firemedivh:BAAANQADCgIIAgAAAA==.Firevoid:BAAANQADCgQIBAAAAA==.Fishspells:BAABNQAECoEfAAILAAkKgxnGQwDAAgALAAkKgxnGQwDAAgAAAA==.',
Fl='Flashfrozen:BAAANQAECgUICgAAAA==.Flute:BAAANQAECgYICwAAAA==.',
Fo='Foxshot:BAAANQADCgQJBAAAAA==.Foxxe:BAAANQABCgIIAgAAAA==.',
Fr='Frayden:BAAANQAECgUJDAAAAA==.Frizmo:BAAANQADCgMJAwAAAA==.Frogprincess:BAAANQADCgcIFwAAAA==.Frontdeboeuf:BAAANQAECgEJAQAAAA==.Frostygrrl:BAAANQADCgQIBAAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQAECgQJBQAAAA==.Furricane:BAAANQADCgIJAQAAAA==.',
Ga='Gadios:BAABNQAECoEhAAMMAAkKNSIJAwDJAgAPAAkK1yDeCQAlAwAMAAcK+SIJAwDJAgAAAA==.Gaiyia:BAAANQAECgQJCAAAAA==.Galebjorn:BAAANQAECgQJEAAAAA==.Garfna:BAAANQADCggIGAAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Gascoigne:BAAANQAECgIJBAAAAA==.',
Ge='Gencil:BAAANQADCgcIFgAAAA==.Gerth:BAAANQADCgQIBAAAAA==.',
Gh='Ghadpri:BAAANQAECgEIAQAAAA==.Ghemanis:BAAANQADCggIEwAAAA==.',
Gi='Gimboo:BAAANQAECgcICAAAAA==.Gizzardo:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Gizzimo:BAAANQADCgQICwAAAA==.',
Gl='Glaon:BAAANQADCgQICAAAAA==.',
Go='Goobr:BAAANQAECgUJCAABNQAECgYJEAACAAAAAA==.Goover:BAAANQAECgUJBgAAAA==.Gosu:BAAANQAECgQJBgAAAA==.',
Gr='Gracelyn:BAAANQAECgUJCwAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQAECgUIBQAAAA==.Grezgara:BAAANQAECgEJAQAAAA==.Griimace:BAAANQAECgYICgAAAA==.Grimoldone:BAAANQAECgEIAQAAAA==.Grimverdict:BAAANQADCgYIDgABNQAECgcJEgACAAAAAA==.Grinderrg:BAAANQAECgcJEQAAAA==.Grizzlie:BAAANQADCgQJBAAAAA==.Grommashryon:BAAANQAECgUICwAAAA==.Grumbledecay:BAAANQAECgYIBgAAAA==.Grumbledore:BAACNQAFFIEHAAMLAAUKtBVPEABcAQALAAQKEhVPEABcAQAYAAEKOxgmBgBYAAA1AAQKgRwAAwsACQpMIWFpAFUCAAsABwozIGFpAFUCABgAAwqVJOsRAA4BAAAA.Grumbler:BAAANQAFFAIJAgABNQAFFAUIBwALALQVAA==.Grìmmørtal:BAAANQAECgEIAQAAAA==.Grìmwúlf:BAAANQAECgEIAQAAAA==.',
Gu='Gullard:BAAANQADCgIIAgAAAA==.Gumbö:BAAANQAECgQIBQAAAA==.Guttzes:BAAANQAECgQICAAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgQIBAAAAA==.',
Ha='Halidril:BAAANQAECgUIDgAAAA==.Hanshiro:BAAANQAECgcICwAAAA==.Hardin:BAAANQADCgcICwAAAA==.Hasel:BAAANQAECgQICAAAAA==.Hawkhunter:BAAANQAECgQIBwAAAA==.Hazzazz:BAAANQAECgEIAQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Hegs:BAABNQAECoEYAAMIAAcKlg4pewCYAQAIAAcKlg4pewCYAQAVAAEKvQmpIwAwAAAAAA==.Heladin:BAAANQADCggICAAAAA==.Helaku:BAAANQAECgYIDwAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hellbender:BAAANQABCgUJBgAAAA==.Hemogoblin:BAAANQADCggIHAAAAA==.Hershel:BAAANQADCgYIBgABNQAECgIJAwACAAAAAA==.Hevharuk:BAAANQAECgUJDAAAAA==.Hewk:BAAANQAECgUICAAAAA==.',
Ho='Hogslight:BAAANQADCgcIBwAAAA==.Holyhela:BAAANQADCgQIBAAAAA==.Homerism:BAAANQAECgUICAAAAA==.Hoofhearted:BAAANQADCggIEAAAAA==.Hotanimemoms:BAAANQADCgcJCgAAAA==.',
Hu='Hukuto:BAAANQADCgEJAQAAAA==.Huntrhen:BAAANQADCgIIAgABNQAECgYIEQACAAAAAA==.',
Hy='Hybris:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëxxy:BAAANQADCgYIBgAAAA==.',
Il='Illidares:BAABNQAECoEdAAIQAAgK0BbRFgBgAgAQAAgK0BbRFgBgAgAAAA==.',
Im='Implosion:BAAANQADCgcIHgAAAA==.Imwarminside:BAABNQAECoEZAAMYAAkKrh8GBQBLAgAYAAYK1CEGBQBLAgALAAYKqBwokADvAQAAAA==.',
In='Ingehunt:BAAANQADCgYIBgAAAA==.Innerrage:BAAANQAECgYIDQAAAA==.Innerstabz:BAAANQADCgcJBwAAAA==.',
Ir='Ireliae:BAAANQAECgQJBAABNQAECgkJHwARAJkZAA==.Irnakk:BAAANQAECgQIBAAAAA==.',
Is='Isaria:BAAANQADCgIJAgAAAA==.Iside:BAAANQADCgYIBwABNQAECgMIBAACAAAAAA==.Isindril:BAABNQAECoEXAAIDAAcK1AgyRABdAQADAAcK1AgyRABdAQAAAA==.Isnacky:BAAANQAECgEIAQAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jadianarcane:BAABNQAECoEXAAILAAgK8B1ZQwDBAgALAAgK8B1ZQwDBAgAAAA==.Jadianrogue:BAAANQADCgYIBgABNQAECggJFwALAPAdAA==.Jameswarren:BAAANQADCgYJGgAAAA==.Jannik:BAABNQAECoEaAAIIAAgK0CDUKADLAgAIAAgK0CDUKADLAgAAAA==.',
Je='Jenntly:BAAANQAECgEJAQABNQAECgkJHwARAJkZAA==.Jessibel:BAAANQADCgUICQAAAA==.',
Ji='Jirasia:BAABNQAECoEZAAIKAAcK0SQkHgDGAgAKAAcK0SQkHgDGAgAAAA==.',
Jm='Jmart:BAAANQAECgUICwAAAA==.',
Jo='Joedalok:BAAANQADCgcIEQABNQAECgUIDAACAAAAAA==.Joedamonk:BAAANQAECgUIDAAAAA==.Jovat:BAAANQADCgYICgAAAA==.',
Ju='Jundras:BAAANQAECgEJAQAAAA==.Juniormintz:BAAANQAECgUJCQAAAA==.',
Ka='Kadryck:BAAANQADCggIHgABNQAECgYJEAACAAAAAA==.Kageriyu:BAABNQAECoEdAAIVAAgKoSLOAQAVAwAVAAgKoSLOAQAVAwAAAA==.Kalmo:BAAANQAECgUJDwAAAA==.Kano:BAAANQADCgYIDAABNQAECgEIAQACAAAAAA==.Kanomoonbark:BAAANQAECgEIAQAAAA==.Kanorexia:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Kaotika:BAAANQAECgMIBQAAAA==.Kas:BAAANQADCgYIBgAAAA==.Kassira:BAAANQABCgMIAwAAAA==.Kayla:BAAANQAECgUJCAAAAA==.',
Ke='Keatøn:BAAANQAECgYJCQAAAA==.Kegsmash:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Kelethius:BAABNQAECoEbAAIIAAgKOSC+KgDCAgAIAAgKOSC+KgDCAgAAAA==.Kerek:BAAANQADCgMIAwAAAA==.Kesthus:BAAANQAECgcIEgAAAA==.Keystonelite:BAABNQAECoEXAAMQAAcKFBu5IwDTAQAQAAcK6BK5IwDTAQAPAAUKsh6LLACiAQAAAA==.Kezyah:BAAANQADCgcJEwAAAA==.',
Kh='Khatrina:BAAANQADCgUIBgAAAA==.Khârn:BAAANQADCgYIDgAAAA==.',
Ki='Killshotz:BAAANQADCgQIBAAAAA==.Kirkitin:BAAANQADCgUJCQAAAA==.',
Kl='Klaustralus:BAAANQADCgcIEQAAAA==.',
Kn='Knaan:BAAANQADCggIFQAAAA==.',
Ko='Koohwip:BAABNQAFFIEQAAIZAAcKhAM7AwDiAQAZAAcKhAM7AwDiAQAAAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Kr='Kramitt:BAAANQADCgQIBAAAAA==.',
Ku='Kungflupanda:BAABNQAECoEZAAIHAAgKkCJWDgAWAwAHAAgKkCJWDgAWAwABNQADCgEIAQACAAAAAA==.Kuruk:BAAANQADCgYICwAAAA==.Kutnarsha:BAAANQADCgEIAQAAAA==.',
['Kà']='Kànkàn:BAAANQAECgQIBgAAAA==.Kàylee:BAAANQAECgUJDQAAAA==.',
['Kï']='Kïller:BAAANQABCgMIAwAAAA==.',
La='Lagaris:BAAANQAECgEIAQAAAA==.Lamphands:BAAANQADCgYICAAAAA==.Lampz:BAAANQAECgMIAwAAAA==.Landaros:BAAANQAECgEJAQAAAA==.Lariniira:BAAANQADCggIDgAAAA==.Lastdance:BAAANQAECggIEgAAAA==.Laveda:BAAANQADCggIFgAAAA==.Lawgrus:BAAANQADCggICAABNQADCggICAACAAAAAA==.',
Ld='Ldycathlyn:BAAANQADCgMIBAAAAA==.',
Le='Leesy:BAAANQAECgQJBAABNQAECgYIDAACAAAAAA==.Leesylock:BAAANQAECgIIAwABNQAECgYIDAACAAAAAA==.Letri:BAAANQAECgUJDwAAAA==.Leyland:BAAANQADCgMIAwAAAA==.',
Li='Libnorathis:BAABNQAECoEgAAIUAAkKIw54MQDdAQAUAAkKIw54MQDdAQAAAA==.Licheternal:BAABNQAECoEfAAMRAAkKmRlxIAD2AQARAAcKzBpxIAD2AQATAAcKZRhyNADVAQAAAA==.Lieko:BAAANQADCggIFQABNQAECgYICwACAAAAAA==.Lightwolves:BAABNQAECoEfAAMNAAkKOSS5CACSAwANAAkKOSS5CACSAwABAAUKzQKBiwD0AAAAAA==.Limeaide:BAAANQAECgcJCwAAAA==.Liminalys:BAAANQAECgEJAQAAAA==.Littlesin:BAAANQABCgEJAQAAAA==.',
Lo='Lockrhen:BAAANQAECgYIEQAAAA==.Lonsoo:BAAANQADCgUIBQAAAA==.Lotharion:BAAANQAECgEIAQAAAA==.Lovelydeäth:BAABNQAECoEZAAILAAcKpCAGWwB8AgALAAcKpCAGWwB8AgAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYIBgAAAA==.Lunabell:BAAANQAECgcJDQAAAA==.',
Ly='Lycealon:BAAANQADCggIDAAAAA==.',
['Lé']='Léf:BAAANQAECgUJDAAAAA==.',
['Lï']='Lïlith:BAAANQADCggICAAAAA==.',
Ma='Macadamia:BAAANQADCgcICgAAAA==.Madbad:BAAANQAECgUJCwAAAA==.Maiderlook:BAAANQADCgMIAwAAAA==.Maidermaider:BAAANQAECgEJAQAAAA==.Maimgor:BAAANQAECgEJAQAAAA==.Makubai:BAAANQAECgMIBQAAAA==.Malenthal:BAAANQAECggICAAAAA==.Malza:BAAANQAECgMIBgAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAABNQAECoEcAAMSAAkK7BNAMAA2AgASAAkK7BNAMAA2AgAaAAIKNAO0FwBSAAAAAA==.Manawood:BAAANQAECgMIAwABNQAFFAUJCgAIADUSAA==.Mangodk:BAAANQAECgYIDAAAAA==.Maniic:BAAANQADCgcIGwAAAA==.Marien:BAAANQAECgEIAwABNQAECgYJDgACAAAAAA==.Marre:BAAANQAECgUIDwAAAA==.Matabei:BAAANQAECgcIDgAAAA==.Mater:BAAANQADCgYIDQAAAA==.Matsuda:BAABNQAECoEaAAIHAAcK+iEkIQCOAgAHAAcK+iEkIQCOAgAAAA==.Mavralara:BAAANQADCggIGAAAAA==.Mawea:BAAANQAECgYJDgAAAA==.Maxious:BAAANQAECgQJBgAAAA==.',
Mc='Mcfrown:BAAANQAECgEIAQAAAA==.Mclight:BAAANQAECgYIDgAAAA==.',
Me='Mechamonk:BAAANQAECgQJCAAAAA==.Medman:BAAANQADCgYJBgAAAA==.Megumïn:BAAANQAECgQIBQAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgYIDAACAAAAAA==.Melvin:BAAANQAECgYJEAAAAA==.Mercurý:BAAANQADCgYICQABNQAECgYIEQACAAAAAA==.Merlinsfire:BAAANQAECgIIAwAAAA==.Methingright:BAAANQADCgEIAQABNQAECgYIEAACAAAAAA==.Mewlilkitty:BAAANQADCgEIAQAAAA==.',
Mi='Michiro:BAAANQADCgQICAAAAA==.Miestra:BAAANQADCgQJBAAAAA==.Mightyraw:BAAANQADCgMIAwAAAA==.Mildfire:BAAANQADCgYJCwAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAAANQAECgUJCwAAAA==.',
Mk='Mknuttyy:BAAANQADCggIDAAAAA==.',
Mo='Mochafrap:BAAANQAECgQJAgAAAA==.Molly:BAAANQAECgQJBwAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAAANQAECgYIDwAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjamus:BAAANQADCgUIBQAAAA==.Mstrjonathan:BAAANQAECgUICAAAAA==.',
Mu='Mungogo:BAAANQAECgQJCAAAAA==.',
My='Myia:BAAANQADCgcIBwAAAA==.Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAAANQAECgYJDwAAAA==.Naive:BAAANQADCgUJBgAAAA==.Naivete:BAAANQAECgUICAAAAA==.Nalaria:BAABNQAECoEXAAIKAAcK8SKXHADPAgAKAAcK8SKXHADPAgAAAA==.Nastiee:BAAANQAECgUIDAAAAA==.',
Ne='Neava:BAAANQABCgQJBAAAAA==.Necrofeelsya:BAAANQADCgcIBwAAAA==.Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAACNQAFFIEMAAIQAAUK5BvQAgDVAQAQAAUK5BvQAgDVAQA1AAQKgSYAAhAACQpfJOQCAJ8DABAACQpfJOQCAJ8DAAAA.',
Ng='Ngorongoro:BAAANQADCgYJGgAAAA==.',
Ni='Niame:BAAANQAECgUIBgAAAA==.Nidalan:BAAANQADCgUIBQAAAA==.Nillaice:BAAANQADCgYICQAAAA==.Nindar:BAAANQADCgYIEwAAAA==.Ninjakitten:BAAANQAECgUJCAAAAA==.',
No='Nobuddude:BAAANQAECgIIBQAAAA==.Noiscopiamo:BAAANQAECggJEQAAAA==.',
Nu='Nualzie:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Ny='Nyxiis:BAAANQAECgQJBQAAAA==.',
Oa='Oashian:BAABNQAECoEXAAIbAAgKyBg2DwAnAgAbAAgKyBg2DwAnAgAAAA==.',
Ol='Oladra:BAAANQAECgUIDQAAAA==.',
Or='Orcishfury:BAAANQABCggIEgAAAA==.Orcrinds:BAAANQADCgYIBgAAAA==.Orgruun:BAAANQAECgUIBQAAAA==.Orr:BAAANQADCggIEwAAAA==.Orrindan:BAAANQAECgYJDwAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQAECgEIAQACAAAAAA==.',
Pa='Palaneer:BAAANQADCgYICgAAAA==.Palasquesea:BAAANQAECgYJBgAAAA==.Pallieguy:BAAANQAECgUICAAAAA==.Panburgler:BAAANQAECgEIAQAAAA==.Pandu:BAAANQADCggICAAAAA==.Patience:BAAANQAECgEIAQAAAA==.',
Pe='Peachtea:BAAANQAECggIBwAAAA==.Penetrate:BAAANQAECgUICAAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.Petrichora:BAAANQADCgMJAwAAAA==.',
Ph='Pharoahe:BAAANQADCgYIBgABNQAECgcJGgAHAPohAA==.Phett:BAAANQADCgQICAAAAA==.Philippe:BAAANQAECgUICQAAAA==.Philo:BAAANQAECgcJEgAAAA==.Phineasflame:BAAANQADCggIFgAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAABNQAECoEZAAMcAAcKXxZmHAABAgAcAAcKXxZmHAABAgAdAAEKXwsdQAA4AAAAAA==.Piggymaru:BAAANQAECgQICgAAAA==.Pikkin:BAAANQAECgUICAAAAA==.Pincushion:BAAANQAECgUICwAAAA==.',
Pl='Plagues:BAAANQAECgEIAQAAAA==.Plaidpally:BAAANQAECgEIAQAAAA==.',
Po='Pocari:BAAANQAECgQJBAAAAA==.Potaters:BAAANQADCggIDwAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQAECgQIBAAAAA==.',
Ps='Psynoria:BAAANQAECgIJAgAAAA==.',
Pu='Pu:BAAANQAECgQJBwAAAA==.',
Pw='Pwoopyrock:BAAANQADCgYIBgAAAA==.',
Py='Pyrose:BAAANQADCgcIGQAAAA==.Pyrowarrior:BAAANQADCggIFgAAAA==.',
['Pó']='Póe:BAAANQAECgQIBwAAAA==.',
Qi='Qiteag:BAAANQADCggIGQABNQAECgYJDAACAAAAAA==.',
Qk='Qkcomputer:BAAANQADCgMIAwABNQAECgYJDAACAAAAAA==.',
Qz='Qzymandia:BAAANQAECgYJDAAAAA==.',
Ra='Rachon:BAAANQADCgcIBwAAAA==.Raeorc:BAAANQADCgUIBQAAAA==.Rah:BAAANQAECgQIBAAAAA==.Raiset:BAAANQAECgYIDQAAAA==.Rakua:BAAANQADCggJCQABNQAECgUICgACAAAAAA==.Ramattra:BAAANQAECgQJCAAAAA==.Rambled:BAAANQADCgcICwAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambling:BAAANQAECgYIDwAAAA==.Rathnek:BAAANQADCgYJBgAAAA==.Rawrp:BAAANQAECgUICAAAAA==.',
Re='Recquency:BAAANQADCgUJDQAAAA==.Rekue:BAAANQADCgYJEQABNQAECgUJCwACAAAAAA==.Relenn:BAAANQADCgcIBwAAAA==.Remisnekro:BAAANQADCgYIFQAAAA==.Rengarage:BAAANQAECgEJAQAAAA==.Reshe:BAAANQADCgQJBAABNQAECgIJAwACAAAAAA==.Reyortsed:BAAANQADCgMIAwAAAA==.',
Rh='Rhiandali:BAAANQAECgYJDgAAAA==.Rhiasith:BAAANQADCggIEgABNQAECgYJDgACAAAAAA==.Rhonna:BAAANQAECgEJAgAAAA==.Rhyxi:BAAANQAECgUJCAAAAA==.',
Ri='Riddle:BAAANQAECgEIAQAAAA==.Riloah:BAAANQAECgYIDwAAAA==.Riptide:BAAANQADCgYICwABNQAECgMJBQACAAAAAA==.Rizon:BAAANQAECgEIAQAAAA==.',
Ro='Rocks:BAAANQAECgUJBQAAAA==.Rollis:BAAANQAECgUJCwAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Ru='Rubedö:BAAANQADCggIDQAAAA==.Ruckyss:BAAANQAECgYIDwAAAA==.Runedorgasm:BAAANQAECgcIDwAAAA==.Rusâ:BAAANQAECgUJBwAAAA==.',
Ry='Ryobie:BAAANQADCgYIBgAAAA==.',
Sa='Saazel:BAAANQAECgIJAwAAAA==.Saladriel:BAABNQAECoEaAAMYAAgKqgwrDgBNAQALAAgKQwixoADHAQAYAAYKHw4rDgBNAQAAAA==.Salandria:BAABNQAECoEiAAINAAgKjQxFaQDBAQANAAgKjQxFaQDBAQAAAA==.Sandeoki:BAAANQADCggIFwAAAA==.Sandz:BAAANQAECgIJAwAAAA==.Sanguinex:BAAANQADCgQIBQAAAA==.Sanlien:BAAANQAECgYJEwAAAA==.Sarif:BAAANQADCgUIEgAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sather:BAAANQAECgMIAwAAAA==.Sathona:BAAANQAECgQIBQABNQAECgcJDQACAAAAAA==.Satisfactree:BAAANQADCgcIBwABNQAECgcIGQAcAF8WAA==.Satsa:BAAANQAECgUIBgAAAA==.Savagedoodle:BAABNQAECoEfAAMXAAgKnB6THgCyAgAXAAgKnB6THgCyAgAWAAIKhBd3SgB8AAAAAA==.',
Sc='Scooters:BAAANQADCggIFAAAAA==.',
Se='Seidhra:BAAANQAECgYIEAAAAA==.Seiza:BAAANQAECgQIBwAAAA==.Sekhmet:BAAANQAECgMIBAAAAA==.Selenax:BAAANQADCgQIBwABNQAECgQICwACAAAAAA==.Seriola:BAAANQADCgcIDQAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAgAAAA==.',
Sh='Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQAECgQICQABNQAECgkJGQAYAK4fAA==.Shalash:BAAANQADCgIIAgAAAA==.Shalisaura:BAAANQAECgEIAQABNQAECgQICwACAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shamleesy:BAAANQAECgYIDAAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgUICgABNQAECgUJCQACAAAAAA==.Shinjii:BAAANQADCggICAAAAA==.Shinysuicune:BAAANQAECgEIAQAAAA==.Shivrael:BAAANQADCggJGAAAAA==.Showpup:BAAANQADCgUICgAAAA==.',
Si='Sickpup:BAAANQADCgcIDQAAAA==.Sifusplitter:BAAANQADCgcIBwABNQADCgEIAQACAAAAAA==.Silvernightz:BAAANQADCgYJFQAAAA==.Sinbreaker:BAAANQAECgQIBgAAAA==.',
Sk='Skaddamoosh:BAAANQAECgYJDwAAAA==.',
Sl='Sladecraven:BAAANQAECgEIAgAAAA==.Slopmelon:BAAANQAECgUJCAAAAA==.Sloppysplshr:BAAANQADCgMIAwAAAA==.Slowdeath:BAAANQADCggIEAAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.',
Sm='Smøkechedda:BAAANQAECgUJCQAAAA==.',
Sn='Snuffduck:BAAANQAECgYIEAAAAA==.Snugglbooty:BAAANQAECgQIBAAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAAANQAECgUICAAAAA==.Sonniy:BAAANQABCgQIBAAAAA==.Sorrentoone:BAAANQADCgcIGgAAAA==.Sorta:BAABNQAECoEZAAMaAAcKiRKVDAAQAQASAAcKaRHURQDKAQAaAAUKpA2VDAAQAQAAAA==.Sothoth:BAAANQABCgUIBwAAAA==.',
Sp='Spankinstein:BAAANQAECgcIEQABNQAECggJHQAQANAWAA==.Spellbraker:BAAANQAECgcJEQAAAA==.Spinraux:BAAANQADCggIFwAAAA==.Spookyvibes:BAAANQAECgEIAgAAAA==.',
St='Stanojustice:BAAANQADCggIGAAAAA==.Starburstz:BAAANQAECgEJAQAAAA==.Starfira:BAAANQAECgQIBAAAAA==.Starknight:BAACNQAFFIEKAAINAAUK+w2PBAB8AQANAAUK+w2PBAB8AQA1AAQKgSYAAg0ACQo0JLwGAKcDAA0ACQo0JLwGAKcDAAAA.Staywokee:BAABNQAECoEdAAIGAAgKfhnLKQBvAgAGAAgKfhnLKQBvAgAAAA==.Stilits:BAAANQAECgEJAQABNQAECgIIAgACAAAAAA==.Stinkyguy:BAAANQAECgEIAQAAAA==.Stolenblight:BAAANQADCgUICgAAAA==.Streamline:BAABNQAECoExAAMeAAgKiSI9AwATAwAeAAgKHSI9AwATAwAIAAgKhxy4NACVAgAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCggJDgAAAA==.',
Sw='Swagnasty:BAABNQAECoEeAAMRAAcKlxpqGgAxAgARAAcKlxpqGgAxAgATAAYKKw+WSQBhAQAAAA==.',
Sy='Sydarais:BAAANQAECgUJCwAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.Syphin:BAAANQADCgYIBgAAAA==.',
Ta='Takua:BAAANQAECgQICAAAAA==.Taleya:BAAANQAECgYJEQAAAA==.Tanarumn:BAAANQAECgIIAwAAAA==.Tanilyn:BAAANQADCgUICgAAAA==.Tarryn:BAAANQADCggIFgAAAA==.',
Te='Teahupoo:BAAANQADCgUIBwAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Terrorblades:BAAANQADCggICAABNQAECgcIGQAfADgbAA==.Tevye:BAAANQAECgUJBgAAAA==.',
Th='Thaelinn:BAAANQAECgEJAQABNQAECggIGAALAOMWAA==.Tharin:BAAANQADCggICQAAAA==.Theßrush:BAAANQAECgIIAgAAAA==.Thorag:BAAANQADCgIIAwABNQAECgcIGgAUAKckAA==.Thornlox:BAAANQAECgQIBwAAAA==.Thorwal:BAAANQADCgMIAwAAAA==.Thorzak:BAAANQAECgcJDwAAAA==.Threeplates:BAABNQAECoEeAAMdAAgKRBDhFAAGAgAdAAgKQQ/hFAAGAgAcAAcKmA/OJQCqAQAAAA==.',
Ti='Tiktik:BAAANQAECgUJDQAAAA==.Tiktikmage:BAAANQAECgIIAgAAAA==.Tismtasm:BAAANQAECgUJBQAAAA==.',
To='Toptree:BAAANQADCgUJCgAAAA==.Topétine:BAAANQAECgUJBgAAAA==.',
Tr='Traskk:BAAANQADCggIGQAAAA==.Trelious:BAAANQAECgUJCAAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQAECgMIBQAAAA==.Tryel:BAABNQAECoEhAAINAAkKpyLRDQBmAwANAAkKpyLRDQBmAwAAAA==.Trínídad:BAAANQAECgIIAgAAAA==.',
Tu='Tuaca:BAAANQADCgUIBwAAAA==.Turdpacker:BAAANQAECgcIBwAAAA==.Turdsmasher:BAAANQAECgEIAgAAAA==.Turumbar:BAAANQAECgUICwAAAA==.',
Tw='Twysted:BAAANQAECgcJDAAAAA==.',
Ty='Tybeross:BAAANQAECgQIBQAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Uh='Uhttred:BAAANQADCggICAABNQAECgcIDQACAAAAAA==.',
Ul='Ultrazord:BAAANQADCgYIFAAAAA==.',
Un='Unholynight:BAAANQADCgcIGAAAAA==.',
Up='Upiebottom:BAAANQAECgUJBQAAAA==.',
Ur='Urosh:BAAANQABCgcIBwAAAA==.',
Va='Vaks:BAAANQAECggJEwAAAA==.Valantriç:BAAANQAECgcICgAAAA==.Valkormyr:BAAANQAECgEIAQAAAA==.Vanishingson:BAAANQAECgQJCAAAAA==.Vanora:BAAANQADCggICAAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAAANQAECgcIDQAAAA==.Vaylkyrie:BAAANQADCgcJCgAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomessa:BAAANQAECgcJEgAAAA==.Venomsnake:BAAANQADCgcIHgAAAA==.Venura:BAAANQAECgQIBgAAAA==.Verelidaine:BAABNQAECoEZAAIKAAkKRiKnEAAdAwAKAAkKRiKnEAAdAwAAAA==.Vessper:BAABNQAECoEZAAMJAAgK2wZrKABjAQAJAAgK2wZrKABjAQASAAEK9QCbtwAcAAAAAA==.Vexmama:BAAANQADCgIJAQAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQAECgUICwABNQAECgUIDgACAAAAAA==.Vicious:BAAANQADCggIEgAAAA==.Victor:BAAANQAECgQICQAAAA==.',
Vo='Voidglazer:BAAANQAECgQJCQAAAA==.Vorvadoss:BAAANQADCgUJBQABNQADCgcIFgACAAAAAA==.Vosik:BAAANQADCgYIEwAAAA==.Voxxy:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.',
Vy='Vyne:BAAANQADCggIEwAAAA==.',
Wa='Wafsei:BAAANQADCggIDwAAAA==.',
We='Welcor:BAAANQADCgUJBgABNQAECgYJEwACAAAAAA==.Welkor:BAAANQAECgEIAQABNQAECgYJEwACAAAAAA==.Wetspots:BAAANQADCgcIBwAAAA==.',
Wh='Whammyshammy:BAAANQAECgQJBAAAAA==.Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Wildness:BAAANQADCgUJBwAAAA==.Wiligoldi:BAAANQAECgQICwAAAA==.Withsauce:BAAANQAECgUJCgAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAACNQAFFIEKAAIIAAUKNRLDBwCUAQAIAAUKNRLDBwCUAQA1AAQKgSYAAwgACQq2ITcUAD8DAAgACQq2ITcUAD8DABUAAQpyDBYiADYAAAAA.',
['Wä']='Wäyz:BAAANQADCggIBAAAAA==.',
Xa='Xanbar:BAAANQADCggIFgAAAA==.Xandent:BAAANQAECgQIBwAAAA==.Xanju:BAABNQAECoEZAAMfAAcKOBt4GQDrAQAfAAcKOBt4GQDrAQAgAAcKmQunEQBWAQAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.Xarc:BAAANQADCgMIAQAAAA==.Xarnlu:BAAANQADCgEIAQABNQAECgQJEAACAAAAAA==.',
Xe='Xep:BAABNQAECoEcAAIMAAgK6BBKCADWAQAMAAgK6BBKCADWAQAAAA==.',
Xi='Xinkz:BAAANQAECgUJCAAAAA==.',
Xu='Xunji:BAAANQADCggIFAAAAA==.',
Ya='Yaariissa:BAAANQADCgMIBAAAAA==.',
Yl='Ylliria:BAAANQAECgQICwAAAA==.',
Yo='Yourholyness:BAAANQAECgEIAQABNQAECgcIDQACAAAAAA==.',
Ys='Yso:BAAANQAECgEIAQAAAA==.',
['Yü']='Yüm:BAAANQADCgcIBwAAAA==.',
Za='Zafadk:BAAANQAECgYJCgABNQAECggJGQAIAB8cAA==.Zaletra:BAAANQAECgIJBAAAAA==.Zalil:BAAANQAECgEJAQAAAA==.Zarcyna:BAACNQAFFIEKAAQXAAUKox4aAgDoAQAXAAUKox4aAgDoAQAWAAEKfw0EEwBSAAAhAAEKQw3WBwBMAAA1AAQKgSoAAxcACQo3JqUAAOsDABcACQo3JqUAAOsDABYABAp0IzAbAHcBAAAA.Zathoron:BAABNQAECoEXAAMeAAcKbiNbBQCvAgAeAAcKuyJbBQCvAgAIAAUKUB1odQCrAQAAAA==.',
Ze='Zenfox:BAABNQAECoEbAAMiAAgKgQulFQCZAQAiAAgKgQulFQCZAQAgAAEKEwMDJwAdAAAAAA==.',
Zi='Ziatora:BAAANQAECgMJBQAAAA==.Zimmy:BAAANQADCggIFAAAAA==.',
Zo='Zosh:BAAANQAECgEIAQAAAA==.',
Zu='Zultaj:BAAANQAECgUICAAAAA==.Zumwalathas:BAAANQAECgUIBQAAAA==.',
['Àr']='Àriýa:BAAANQAECgUIBwAAAA==.',
['Âs']='Âstryl:BAAANQAECgEIAQAAAA==.',
['Ãl']='Ãleyah:BAAANQADCgQIBAAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQAECgMIAwAAAA==.',
['Äs']='Ästryl:BAAANQADCgcJCgAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAAANQAECgUICAAAAA==.',
['Ða']='Ðarrow:BAAANQAECgUIBgAAAA==.',
['Öm']='Ömni:BAAANQADCgUIBQAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgQIBwAAAA==.',
['ßa']='ßaroness:BAAANQAECgUIDgAAAA==.',
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
