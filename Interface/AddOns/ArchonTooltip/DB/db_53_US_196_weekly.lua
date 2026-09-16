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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Hunter-Survival','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Mage-Frost','Warrior-Arms','Evoker-Preservation','Priest-Holy','Priest-Discipline','DemonHunter-Devourer','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Warlock-Affliction',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aakura:BAAANQAECgcIEQAAAA==.Aamira:BAAANQADCgUICQAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQADCgcIEAAAAA==.',
Ad='Adamantus:BAAANQADCggIGQAAAA==.Admetus:BAAANQADCgYIBgAAAA==.',
Ae='Aelasong:BAAANQADCgcIDQAAAA==.Aelioran:BAAANQAECgQIBwAAAA==.Aenlor:BAAANQADCgYICwAAAA==.Aestar:BAAANQADCggIEAAAAA==.Aethias:BAAANQABCgEIAQAAAA==.',
Ag='Aghwang:BAAANQAECgEIAQAAAA==.',
Ai='Airedhiel:BAAANQADCgcIDgAAAA==.',
Al='Alacantos:BAAANQAECgUICgAAAA==.Alainnaingil:BAAANQADCggICAAAAA==.Alanjackson:BAAANQADCgYIDwAAAA==.Alawyn:BAAANQAECgYIEAAAAA==.Alayssaria:BAAANQAECgQIBgAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQAECgEIAQABNQAECgUICgABAAAAAA==.Alltaken:BAAANQADCgcIEAAAAA==.Alokin:BAAANQADCgEIAQAAAA==.Alpharetta:BAABNQAECoEdAAMCAAkJRh5QDgAEAwACAAkJRh5QDgAEAwADAAUJIQ/4IQAlAQABNQAECgkJHwAEAKEfAA==.Alsera:BAAANQAECgcICgAAAA==.',
Am='Amarae:BAAANQADCggIEgAAAA==.Amicoolyet:BAAANQADCgcIFwAAAA==.Ammon:BAAANQADCgYICAAAAA==.Amorene:BAABNQAECoEdAAMFAAkJ8xy5DgDpAgAFAAkJ8xy5DgDpAgAEAAcJchXRMwDuAQAAAA==.Amorvane:BAAANQAECgQIBAABNQAECgkJHQAFAPMcAA==.Amoryn:BAAANQAECgIIAgABNQAECgkJHQAFAPMcAA==.',
An='Anaraellea:BAAANQADCgYIEAAAAA==.Andcheese:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Andramedally:BAAANQADCgcIDgAAAA==.Andrusius:BAAANQAECgYIBgAAAA==.Angellena:BAAANQAECgQICAAAAA==.Anian:BAAANQADCgUIDQAAAA==.Antadin:BAAANQAECgQIBAAAAA==.Anthela:BAAANQAECgUIBQABNQAECgYIBgABAAAAAA==.',
Ap='Apherilia:BAAANQAECgYIBgAAAA==.',
Ar='Aranos:BAAANQADCgYICQAAAA==.Ardrick:BAAANQADCggIFQAAAA==.Arihua:BAAANQADCggIDgAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Aronau:BAAANQADCgYIDAAAAA==.Arosen:BAAANQAECgIIAwAAAA==.Artforidiots:BAAANQAECgUIBQAAAA==.Arthurious:BAAANQADCggIEwAAAA==.',
As='Asenath:BAAANQAECgQIBgAAAA==.Askec:BAAANQAECgEIAQAAAA==.Asmodeus:BAAANQAECgYIDQAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQAECgIIAgAAAA==.',
Av='Avacado:BAAANQADCggICgABNQAFFAYIDAACAHsZAA==.Avicularia:BAAANQADCgcIBwAAAA==.',
Aw='Awake:BAAANQAECggIEAAAAA==.',
Ax='Axdk:BAAANQAECgQIBgAAAA==.',
Ay='Ayalha:BAAANQAECgYICgAAAA==.',
Ba='Babychewie:BAAANQAECgQIBQAAAA==.Babygumbo:BAAANQAECgQIBAAAAA==.Balla:BAAANQAECgEIAQAAAA==.Bambismash:BAAANQADCgUICAAAAA==.',
Be='Beansgreens:BAAANQADCgMIBAAAAA==.Beantism:BAAANQAECgQIBgAAAA==.Beardeath:BAAANQAECgQIBQAAAA==.Bearleft:BAAANQABCgQIBgAAAA==.Beaross:BAAANQAECgUIBwAAAA==.Beeflomein:BAAANQAECgQIBQAAAA==.Beledros:BAABNQAECoEWAAIGAAgJvRpZDgCKAgAGAAgJvRpZDgCKAgABNQAECgMIBQABAAAAAA==.Benadarek:BAAANQADCgYIBgAAAA==.Beratol:BAAANQADCgUICAAAAA==.',
Bi='Bigeasy:BAAANQADCgcIFwAAAA==.',
Bl='Blakkadin:BAAANQADCgUIBgABNQAECgkJHQAHAJAdAA==.Blayzn:BAAANQADCgUIBwAAAA==.Bloodmoonpal:BAAANQADCgMIAwAAAA==.Bloodychêwy:BAAANQADCgcIBwAAAA==.Bluex:BAAANQADCgMIAwAAAA==.Blutdurst:BAAANQADCggIDAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAECgkJGQAIAPwgAQ==.Bonelargeles:BAAANQAECgQIAgAAAA==.Boolk:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Booyaah:BAABNQAECoEXAAMFAAkJ9hgpHgBpAgAFAAkJ9hgpHgBpAgAEAAIJQRlEkwCMAAAAAA==.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Bravelee:BAAANQADCgYIBgAAAA==.Brazok:BAAANQADCggIEAAAAA==.Brigade:BAABNQAECoEYAAMJAAkJaBRCGgCOAgAJAAkJaBRCGgCOAgAKAAEJvA8F7wAxAAAAAA==.Brigadester:BAABNQAECoEdAAILAAkJPyJXAACuAwALAAkJPyJXAACuAwAAAA==.Brogaine:BAAANQADCgcIDgAAAA==.Broodin:BAAANQADCgYIBwAAAA==.Bruen:BAAANQADCgUIBQAAAA==.',
Bu='Bullbas:BAAANQADCggICgAAAA==.Bumdog:BAAANQAECgIIAgAAAA==.Burritorukh:BAAANQADCggICAAAAA==.',
Ca='Calrisa:BAAANQAECgYIDgAAAQ==.Calrisyia:BAAANQADCgEIAQABNQAECgYIDgABAAAAAA==.Camin:BAAANQADCgUIBQAAAA==.Carltonhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAAANQAECgQIBgAAAA==.Cassapedia:BAAANQADCgYICwABNQAECgQIBgABAAAAAA==.Cassawings:BAAANQADCgUICQABNQAECgQIBgABAAAAAA==.',
Ce='Celestria:BAAANQAECgQIBQAAAA==.Celna:BAAANQADCgYIFgAAAA==.Celyssia:BAAANQAECgQIBgAAAA==.Cernos:BAAANQADCggIGAAAAA==.',
Ch='Chance:BAAANQAECgYIEAAAAA==.Chardclass:BAAANQAECgIIAgABNQAFFAUIBgACABELAA==.Charzard:BAAANQAECgQIBQAAAA==.Cheerio:BAAANQAECgQIBAAAAA==.Cheezit:BAAANQADCggICAAAAA==.',
Ci='Cinderson:BAAANQABCgMIAwAAAA==.',
Cl='Clömp:BAAANQAECgYICgAAAA==.',
Co='Cocolu:BAAANQADCgcIBwAAAA==.Coreion:BAAANQADCgcIEgAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAABNQAECggIDAABAAAAAA==.Crisstos:BAAANQADCgUICQAAAA==.Cristhel:BAAANQAECgcIEQAAAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQADCggIGQAAAA==.',
Cs='Csg:BAAANQAECgIIAgAAAA==.',
Cy='Cyllene:BAAANQADCgUICQAAAA==.',
['Cé']='Cérnunnos:BAAANQAECgQIBQAAAA==.',
Da='Daag:BAAANQAECggIBwAAAA==.Daemonslayer:BAAANQADCggIHQAAAA==.Daftknight:BAAANQAECgYIBwAAAA==.Daisycutter:BAABNQAECoEOAAIMAAcJARAbHwDIAQAMAAcJARAbHwDIAQAAAA==.Dakoo:BAAANQADCgIIAgAAAA==.Daluon:BAAANQABCgQIBAABNQAECgYICgABAAAAAA==.Damai:BAAANQABCgYICAAAAA==.Dances:BAAANQADCggIGQAAAA==.Daravanthel:BAAANQAECgYICAAAAA==.Daresh:BAAANQAECgQIBgABNQAECgcIEgABAAAAAA==.Darkbeast:BAAANQAECgUICwAAAA==.Darkbáine:BAAANQAECgcIEgAAAA==.Darkdarion:BAAANQABCggIDQAAAA==.Darling:BAAANQAECggIEwAAAA==.Darmorg:BAABNQAECoEXAAINAAkJSiBPBwBWAwANAAkJSiBPBwBWAwAAAA==.Darthaxe:BAABNQAECoEXAAQOAAkJfRlWFACPAgAOAAkJfRlWFACPAgANAAEJgw2LeABHAAAPAAEJXw/qSwBBAAAAAA==.Daskapital:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
De='Deathsurge:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Deegoddaem:BAAANQADCgcICwAAAA==.Delacour:BAEBNQAECoEVAAIIAAgJtBHUXQAuAgAIAAgJtBHUXQAuAgABNQAECgUICgABAAAAAA==.Dembjuicy:BAAANQADCgUIBQAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Derym:BAAANQADCgEIAQAAAA==.Dev:BAAANQAECggIAwAAAA==.Dezz:BAAANQAECgIIAgAAAA==.Dezza:BAAANQAECgMIAwAAAA==.',
Dh='Dharenar:BAAANQAECgYIEAAAAA==.',
Di='Diazepam:BAAANQADCgYIBgAAAA==.Dizzyflores:BAAANQAECgQIBgAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQAECgUIBQAAAA==.',
Do='Doomcore:BAAANQAECgYICgAAAA==.Dooper:BAAANQAECgYIEgAAAA==.Dorbinn:BAAANQADCgUIBQAAAA==.Dorrf:BAAANQADCgcICwAAAA==.Doshneil:BAAANQADCggIFgAAAA==.',
Dr='Dragongor:BAAANQADCggIGQAAAA==.Dragonsmight:BAAANQAECgYIDwAAAA==.Dreamvore:BAAANQAECgcIDQAAAA==.Droknarr:BAAANQABCgIIAwAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQAECgMIBQAAAA==.Dustobones:BAABNQAECoEQAAINAAYJURZvMgC0AQANAAYJURZvMgC0AQAAAA==.',
Dw='Dwee:BAAANQADCgUIBQABNQADCgYIDQABAAAAAA==.Dweedy:BAAANQADCgYIDQAAAA==.Dweela:BAAANQADCgIIAgABNQADCgYIDQABAAAAAA==.',
Ea='Ealen:BAAANQADCgYIBgAAAA==.Eastón:BAAANQADCggICAAAAA==.',
Ee='Eellyqt:BAAANQADCgQIBAAAAA==.',
El='Eliyana:BAAANQAECgQIBgAAAA==.Elledrus:BAAANQAECgEIAQAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAAANQAECgQIBgAAAA==.Eluniel:BAAANQAECgQIBQAAAA==.',
Em='Emberdk:BAABNQAECoEhAAINAAkJkRRMGACBAgANAAkJkRRMGACBAgAAAA==.Emojones:BAAANQAECgEIAQAAAA==.',
Ep='Ephysa:BAAANQADCgYICQAAAA==.',
Er='Erasra:BAAANQAECgYICwAAAA==.',
Es='Essenne:BAAANQADCgYIEAABNQAECgQIBgABAAAAAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Etrigg:BAAANQADCggICgAAAA==.',
Ex='Exava:BAAANQADCgEIAQAAAA==.Exstatik:BAAANQAECgYIBwAAAA==.',
Ey='Eyeamgroot:BAAANQAECgQIBQAAAA==.Eyeholeman:BAAANQAECgIIAgAAAA==.',
Ez='Ezzrra:BAAANQAECgYICgAAAA==.',
Fa='Faelunae:BAAANQADCgYIEAAAAA==.Faillock:BAABNQAECoEgAAMQAAkJTBr0LwAYAgAQAAcJKRr0LwAYAgARAAQJfxC7KQDyAAAAAA==.Falora:BAAANQADCgcIDgAAAA==.Fangshot:BAAANQAECgIIAwAAAA==.',
Fe='Feldwn:BAAANQADCgMIAwAAAA==.Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAAANQAECgQIBgAAAA==.Fezzik:BAAANQADCgQIBAAAAA==.',
Fi='Filthydegén:BAAANQADCgYIBwAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Firedemon:BAAANQADCgcIFwAAAA==.Firemedivh:BAAANQADCgIIAgAAAA==.Fishspells:BAAANQAECggIEwAAAA==.',
Fl='Flashfrozen:BAAANQAECgQIBQAAAA==.Flute:BAAANQAECgYICwAAAA==.',
Fo='Foxshot:BAAANQADCgQIBAAAAA==.Foxxe:BAAANQABCgIIAgAAAA==.',
Fr='Frayden:BAAANQAECgQIBwAAAA==.Frizmo:BAAANQADCgMIAwAAAA==.Frogprincess:BAAANQADCgcIFwAAAA==.Frontdeboeuf:BAAANQAECgEIAQAAAA==.Frostygrrl:BAAANQADCgQIBAAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQAECgEIAQAAAA==.Furricane:BAAANQADCgEIAQAAAA==.',
Ga='Gadios:BAABNQAECoEZAAMSAAgJUSJ0AgCmAgAMAAgJkSBZCgDqAgASAAcJlSB0AgCmAgAAAA==.Gaiyia:BAAANQAECgQIBAAAAA==.Galebjorn:BAAANQAECgQIEAAAAA==.Garfna:BAAANQADCggIGAAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Gascoigne:BAAANQAECgIIAgAAAA==.',
Ge='Gencil:BAAANQADCgcIEAAAAA==.Gerth:BAAANQADCgQIBAAAAA==.',
Gh='Ghadpri:BAAANQADCgEIAQAAAA==.Ghemanis:BAAANQADCgcICwAAAA==.',
Gi='Gimboo:BAAANQAECgEIAQAAAA==.Gizzimo:BAAANQADCgQICwAAAA==.',
Go='Goobr:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.Goover:BAAANQAECgEIAQAAAA==.Gosu:BAAANQAECgIIAgAAAA==.',
Gr='Gracelyn:BAAANQAECgQIBgAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQADCgYICwAAAA==.Grezgara:BAAANQADCggIGQAAAA==.Griimace:BAAANQAECgQIBAAAAA==.Grimoldone:BAAANQADCggIHQAAAA==.Grimverdict:BAAANQADCgQICAABNQAECgYICwABAAAAAA==.Grinderrg:BAAANQAECgYICgAAAA==.Grommashryon:BAAANQAECgUIBgAAAA==.Grumbledecay:BAAANQAECgYIBgAAAA==.Grumbledore:BAABNQAECoEZAAMIAAkJ/CBhSgBuAgAIAAcJzB9hSgBuAgATAAMJlSQ2DQAcAQAAAA==.Grumbler:BAAANQAECgQIBAABNQAECgkJGQAIAPwgAA==.Grìmwúlf:BAAANQAECgEIAQAAAA==.',
Gu='Gullard:BAAANQADCgIIAgAAAA==.Gumbö:BAAANQAECgQIBQAAAA==.Guttzes:BAAANQAECgMIBAAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgQIBAAAAA==.',
Ha='Halidril:BAAANQAECgQICQAAAA==.Hanshiro:BAAANQAECgcIBwAAAA==.Hardin:BAAANQADCgcICwAAAA==.Hasel:BAAANQAECgMIBAAAAA==.Hawkhunter:BAAANQAECgMIAwAAAA==.Hazzazz:BAAANQAECgEIAQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Hegs:BAAANQAECgYIDwAAAA==.Heladin:BAAANQADCggICAAAAA==.Helaku:BAAANQAECgUICQAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hemogoblin:BAAANQADCggIFAAAAA==.Hevharuk:BAAANQAECgQIBwAAAA==.Hewk:BAAANQAECgMIAwAAAA==.',
Ho='Hogslight:BAAANQADCgcIBwAAAA==.Homerism:BAAANQAECgIIAgAAAA==.Hoofhearted:BAAANQADCggIDwAAAA==.Hotanimemoms:BAAANQADCgMIAwAAAA==.',
Hu='Huntrhen:BAAANQADCgIIAgABNQAECgQICwABAAAAAA==.',
Hy='Hybris:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëxxy:BAAANQADCgYIBgAAAA==.',
Il='Illidares:BAAANQAECgcIEgAAAA==.',
Im='Implosion:BAAANQADCgcIFwAAAA==.Imwarminside:BAAANQAECgYICwAAAA==.',
In='Ingehunt:BAAANQADCgYIBgAAAA==.Innerrage:BAAANQAECgYICwAAAA==.',
Ir='Ireliae:BAAANQAECgQIBAABNQAECggIGQANAEoZAA==.Irnakk:BAAANQAECgQIBAAAAA==.',
Is='Isaria:BAAANQADCgIIAgAAAA==.Iside:BAAANQADCgYIBwABNQAECgEIAgABAAAAAA==.Isindril:BAAANQAECgYIEAAAAA==.Isnacky:BAAANQAECgEIAQAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jadianarcane:BAAANQAECgYIDQAAAA==.Jameswarren:BAAANQADCgYIFAAAAA==.Jannik:BAAANQAECgcIEgAAAA==.',
Je='Jenntly:BAAANQAECgEIAQABNQAECggIGQANAEoZAA==.Jessibel:BAAANQADCgUICQAAAA==.',
Ji='Jirasia:BAAANQAECgYIEAAAAA==.',
Jm='Jmart:BAAANQAECgQIBgAAAA==.',
Jo='Joedalok:BAAANQADCgYIEAABNQAECgUIDAABAAAAAA==.Joedamonk:BAAANQAECgUIDAAAAA==.Jovat:BAAANQADCgYICgAAAA==.',
Ju='Jundras:BAAANQADCggIGQAAAA==.Juniormintz:BAAANQAECgQIBAAAAA==.',
Ka='Kadryck:BAAANQADCggIFgABNQAECgUICgABAAAAAA==.Kageriyu:BAAANQAECgcIEwAAAA==.Kalmo:BAAANQAECgUICgAAAA==.Kano:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.Kanomoonbark:BAAANQADCggIDwAAAA==.Kanorexia:BAAANQADCggICAABNQADCggIDwABAAAAAA==.Kaotika:BAAANQAECgEIAgAAAA==.Kas:BAAANQADCgYIBgAAAA==.Kassira:BAAANQABCgMIAwAAAA==.Kayla:BAAANQAECgMIAwAAAA==.',
Ke='Keatøn:BAAANQAECgUIBQAAAA==.Kegsmash:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Kelethius:BAABNQAECoEZAAIUAAgJZB5lIQDOAgAUAAgJZB5lIQDOAgAAAA==.Kerek:BAAANQADCgMIAwAAAA==.Kesthus:BAAANQAECggIDQAAAA==.Keystonelite:BAAANQAECgYIEAAAAA==.Kezyah:BAAANQADCgYIDwAAAA==.',
Kh='Khatrina:BAAANQADCgUIBgAAAA==.Khârn:BAAANQADCgYIDgAAAA==.',
Ki='Kirkitin:BAAANQADCgQIBAAAAA==.',
Kl='Klaustralus:BAAANQADCgcIEQAAAA==.',
Kn='Knaan:BAAANQADCggIFQAAAA==.',
Ko='Koohwip:BAABNQAFFIEPAAIVAAcJhAPdAQDrAQAVAAcJhAPdAQDrAQAAAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Kr='Kramitt:BAAANQADCgQIBAAAAA==.',
Ku='Kungflupanda:BAAANQAECgcIDwABNQADCgEIAQABAAAAAA==.Kuruk:BAAANQADCgYICwAAAA==.Kutnarsha:BAAANQADCgEIAQAAAA==.',
['Kà']='Kànkàn:BAAANQAECgQIBgAAAA==.Kàylee:BAAANQAECgQICAAAAA==.',
['Kï']='Kïller:BAAANQABCgMIAwAAAA==.',
La='Lagaris:BAAANQADCggIHQAAAA==.Lampz:BAAANQAECgMIAwAAAA==.Landaros:BAAANQADCgcIEgAAAA==.Lariniira:BAAANQADCggIDgAAAA==.Lastdance:BAAANQAECggIDAAAAA==.Laveda:BAAANQADCgcIDgAAAA==.Lawgrus:BAAANQADCggICAABNQADCggICAABAAAAAA==.',
Ld='Ldycathlyn:BAAANQADCgEIAQAAAA==.',
Le='Leesylock:BAAANQAECgIIAwABNQAECgYIBgABAAAAAA==.Letri:BAAANQAECgQICgAAAA==.Leyland:BAAANQADCgMIAwAAAA==.',
Li='Libnorathis:BAAANQAECggIEwAAAA==.Licheternal:BAABNQAECoEZAAMNAAgJShl7KgDnAQANAAcJZRh7KgDnAQAPAAUJzhmEJABKAQAAAA==.Lieko:BAAANQADCggICwABNQAECgQIBQABAAAAAA==.Lightwolves:BAABNQAECoEbAAMKAAkJaSRfCwBRAwAKAAgJECVfCwBRAwAJAAUJzQLRbwD+AAAAAA==.Limeaide:BAAANQAECgMIBAAAAA==.Liminalys:BAAANQADCggIGQAAAA==.Littlesin:BAAANQABCgEIAQAAAA==.',
Lo='Lockrhen:BAAANQAECgQICwAAAA==.Lonsoo:BAAANQADCgUIBQAAAA==.Lotharion:BAAANQAECgEIAQAAAA==.Lovelydeäth:BAAANQAECgYIEAAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYIBgAAAA==.Lunabell:BAAANQAECgcIDAAAAA==.',
Ly='Lycealon:BAAANQADCgcIBwAAAA==.',
['Lé']='Léf:BAAANQAECgQIBwAAAA==.',
['Lï']='Lïlith:BAAANQADCggICAAAAA==.',
Ma='Macadamia:BAAANQADCgQIBAAAAA==.Madbad:BAAANQAECgQIBgAAAA==.Maiderlook:BAAANQADCgMIAwAAAA==.Maidermaider:BAAANQAECgEIAQAAAA==.Maimgor:BAAANQADCggIGQAAAA==.Makubai:BAAANQAECgEIAgAAAA==.Malza:BAAANQAECgMIBgAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAABNQAECoEXAAMWAAkJqBMpIwA2AgAWAAkJqBMpIwA2AgAXAAIJNAOVFABWAAAAAA==.Manawood:BAAANQAECgIIAgABNQAFFAMIBQAUAO8MAA==.Mangodk:BAAANQAECgYIDAAAAA==.Maniic:BAAANQADCgcIFAAAAA==.Marien:BAAANQAECgEIAgABNQAECgUICQABAAAAAA==.Marre:BAAANQAECgUIDwAAAA==.Matabei:BAAANQAECgYIDQAAAA==.Mater:BAAANQADCgYIDQAAAA==.Matsuda:BAAANQAECgYIEQAAAA==.Mavralara:BAAANQADCgYIEAAAAA==.Mawea:BAAANQAECgUICQAAAA==.Maxious:BAAANQAECgIIAgAAAA==.',
Mc='Mcfrown:BAAANQAECgEIAQAAAA==.Mclight:BAAANQAECgYICQAAAA==.',
Me='Mechamonk:BAAANQAECgQIBAAAAA==.Megumïn:BAAANQAECgQIBAAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.Melvin:BAAANQAECgUICgAAAA==.Mercurý:BAAANQADCgYICQABNQAECgYIEQABAAAAAA==.Merlinsfire:BAAANQAECgIIAwAAAA==.Methingright:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Mewlilkitty:BAAANQADCgEIAQAAAA==.',
Mi='Michiro:BAAANQADCgQIBAAAAA==.Mightyraw:BAAANQADCgMIAwAAAA==.Mildfire:BAAANQADCgUIBQAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAAANQAECgQIBgAAAA==.',
Mk='Mknuttyy:BAAANQADCggIDAAAAA==.',
Mo='Mochafrap:BAAANQADCgUIBQAAAA==.Molly:BAAANQAECgIIAwAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAAANQAECgUICQAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjamus:BAAANQADCgUIBQAAAA==.Mstrjonathan:BAAANQAECgUICAAAAA==.',
Mu='Mungogo:BAAANQADCggINwAAAA==.',
My='Myia:BAAANQADCgcIBwAAAA==.Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAAANQAECgYIDQAAAA==.Naive:BAAANQADCgUIBgAAAA==.Naivete:BAAANQAECgMIAwAAAA==.Nalaria:BAAANQAECgYIDwAAAA==.Nastiee:BAAANQAECgUIDAAAAA==.',
Ne='Neava:BAAANQABCgQIBAAAAA==.Necrofeelsya:BAAANQADCgcIBwAAAA==.Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAACNQAFFIEHAAIYAAQJxxrUAgCCAQAYAAQJxxrUAgCCAQA1AAQKgR8AAhgACQlkJOwBALEDABgACQlkJOwBALEDAAAA.',
Ng='Ngorongoro:BAAANQADCgYIFAAAAA==.',
Ni='Niame:BAAANQAECgEIAQAAAA==.Nillaice:BAAANQADCgYICQAAAA==.Nindar:BAAANQADCgYIDQAAAA==.Ninjakitten:BAAANQAECgMIAwAAAA==.',
No='Nobuddude:BAAANQAECgIIAwAAAA==.Noiscopiamo:BAAANQAECggIDwAAAA==.',
Ny='Nyxiis:BAAANQAECgEIAQAAAA==.',
Oa='Oashian:BAAANQAECgYIDgAAAA==.',
Ol='Oladra:BAAANQAECgQICAAAAA==.',
Or='Orcishfury:BAAANQABCgYIEAAAAA==.Orcrinds:BAAANQADCgYIBgAAAA==.Orgruun:BAAANQADCggICgAAAA==.Orr:BAAANQADCggIEwAAAA==.Orrindan:BAAANQAECgUICQAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQADCggIDgABAAAAAA==.',
Pa='Palaneer:BAAANQADCgYICgAAAA==.Palasquesea:BAAANQAECgQIBAAAAA==.Pallieguy:BAAANQAECgMIAwAAAA==.Pandu:BAAANQADCggICAAAAA==.Patience:BAAANQAECgEIAQAAAA==.',
Pe='Peachtea:BAAANQAECgQIAwAAAA==.Penetrate:BAAANQAECgUICAAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.',
Ph='Pharoahe:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.Phett:BAAANQADCgQICAAAAA==.Philippe:BAAANQAECgMIBAAAAA==.Philo:BAAANQAECgYIDQAAAA==.Phineasflame:BAAANQADCgcIDgAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAAANQAECgYIEQAAAA==.Piggymaru:BAAANQAECgQIBgAAAA==.Pikkin:BAAANQAECgMIAwAAAA==.Pincushion:BAAANQAECgQIBgAAAA==.',
Pl='Plagues:BAAANQADCggIHQAAAA==.',
Po='Pocari:BAAANQADCgYIBgAAAA==.Potaters:BAAANQADCgYIDAAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQAECgQIBAAAAA==.',
Ps='Psynoria:BAAANQAECgIIAgAAAA==.',
Pu='Pu:BAAANQAECgQIBQAAAA==.',
Py='Pyrose:BAAANQADCgcIEgAAAA==.Pyrowarrior:BAAANQADCggIEQAAAA==.',
['Pó']='Póe:BAAANQAECgQIBwAAAA==.',
Qi='Qiteag:BAAANQADCggIEQABNQAECgQIBgABAAAAAA==.',
Qk='Qkcomputer:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Qz='Qzymandia:BAAANQAECgQIBgAAAA==.',
Ra='Rachon:BAAANQADCgcIBwAAAA==.Raeorc:BAAANQADCgUIBQAAAA==.Rah:BAAANQAECgQIBAAAAA==.Raiset:BAAANQAECgQIBwAAAA==.Rakua:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Ramattra:BAAANQAECgQIBAAAAA==.Rambled:BAAANQADCgcIBwAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambling:BAAANQAECgUICQAAAA==.Rathnek:BAAANQADCgYIBgAAAA==.Rawrp:BAAANQAECgMIAwAAAA==.',
Re='Recquency:BAAANQADCgUICQAAAA==.Rekue:BAAANQADCgYICwABNQAECgQIBgABAAAAAA==.Remisnekro:BAAANQADCgYIEAAAAA==.Rengarage:BAAANQAECgEIAQAAAA==.Reshe:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Reyortsed:BAAANQADCgMIAwAAAA==.',
Rh='Rhiandali:BAAANQAECgUICAAAAA==.Rhiasith:BAAANQADCggIDQABNQAECgUICAABAAAAAA==.Rhonna:BAAANQAECgEIAQAAAA==.Rhyxi:BAAANQAECgMIAwAAAA==.',
Ri='Riddle:BAAANQAECgEIAQAAAA==.Riloah:BAAANQAECgUICAAAAA==.Riptide:BAAANQADCgYICwABNQAECgMIBQABAAAAAA==.Rizon:BAAANQADCggIHQAAAA==.',
Ro='Rocks:BAAANQABCgIIAgAAAA==.Rollis:BAAANQAECgQIBgAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Ru='Rubedö:BAAANQADCgcICwAAAA==.Ruckyss:BAAANQADCggIDgAAAA==.Runedorgasm:BAAANQAECgYICAAAAA==.Rusâ:BAAANQAECgEIAgAAAA==.',
Ry='Ryobie:BAAANQADCgYIBgAAAA==.',
Sa='Saazel:BAAANQAECgEIAQAAAA==.Saladriel:BAAANQAECgcIEAAAAA==.Salandria:BAABNQAECoEaAAIKAAcJPwsuYgB3AQAKAAcJPwsuYgB3AQAAAA==.Sandeoki:BAAANQADCgcIEAAAAA==.Sandz:BAAANQAECgEIAQAAAA==.Sanguinex:BAAANQADCgQIBQAAAA==.Sanlien:BAAANQAECgYIDQAAAA==.Sarif:BAAANQADCgUIDQAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sather:BAAANQAECgMIAwAAAA==.Sathona:BAAANQAECgQIBQABNQAECgYIBgABAAAAAA==.Satisfactree:BAAANQADCgcIBwABNQAECgYIEQABAAAAAA==.Satsa:BAAANQAECgUIBQAAAA==.Savagedoodle:BAABNQAECoEaAAMQAAgJtxy8FwCmAgAQAAgJtxy8FwCmAgARAAIJhBciQwB/AAAAAA==.',
Sc='Scooters:BAAANQADCgYIDAAAAA==.',
Se='Seidhra:BAAANQAECgUICgAAAA==.Seiza:BAAANQAECgQIBwAAAA==.Sekhmet:BAAANQAECgEIAgAAAA==.Selenax:BAAANQADCgQIBwABNQAECgQICAABAAAAAA==.Seriola:BAAANQADCgYIBwAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAgAAAA==.',
Sh='Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQAECgQIBgABNQAECgYICwABAAAAAA==.Shalash:BAAANQADCgIIAgAAAA==.Shalisaura:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shamleesy:BAAANQAECgYIBgAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgUICgABNQAECgQIBAABAAAAAA==.Shinjii:BAAANQADCggICAAAAA==.Shinysuicune:BAAANQAECgEIAQAAAA==.Shivrael:BAAANQADCggIEAAAAA==.Showpup:BAAANQADCgUICgAAAA==.',
Si='Sickpup:BAAANQADCgYIBgAAAA==.Silvernightz:BAAANQADCgYIEAAAAA==.Sinbreaker:BAAANQAECgQIBgAAAA==.',
Sk='Skaddamoosh:BAAANQAECgQICQAAAA==.Skaðì:BAAANQADCgEIAQAAAA==.',
Sl='Sladecraven:BAAANQAECgEIAgAAAA==.Slopmelon:BAAANQAECgMIAwAAAA==.Slowdeath:BAAANQADCgYICAAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgkJHgAFAMIYAA==.',
Sm='Smøkechedda:BAAANQAECgQIBAAAAA==.',
Sn='Snuffduck:BAAANQAECgYIEAAAAA==.Snugglbooty:BAAANQAECgQIBAAAAA==.Snugglebuns:BAAANQADCgIIAgAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAAANQAECgMIAwAAAA==.Sonniy:BAAANQABCgQIBAAAAA==.Sorrentoone:BAAANQADCgYIEwAAAA==.Sorta:BAAANQAECgYIEAAAAA==.Sothoth:BAAANQABCgUIBwAAAA==.',
Sp='Spankinstein:BAAANQAECgYIDQABNQAECgcIEgABAAAAAA==.Spellbraker:BAAANQAECgYICgAAAA==.Spinraux:BAAANQADCgcIEQAAAA==.Spookyvibes:BAAANQAECgEIAgAAAA==.',
St='Stanojustice:BAAANQADCgYIEAAAAA==.Starburstz:BAAANQADCggIGAAAAA==.Starknight:BAACNQAFFIEFAAIKAAMJJwuqBQDiAAAKAAMJJwuqBQDiAAA1AAQKgR0AAgoACQkbIp8JAGYDAAoACQkbIp8JAGYDAAAA.Staywokee:BAAANQAECgYIEwAAAA==.Stilits:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Stinkyguy:BAAANQAECgEIAQAAAA==.Stolenblight:BAAANQADCgUICgAAAA==.Streamline:BAABNQAECoEhAAMZAAgJsh5UBQB0AgAUAAgJ8RquLACQAgAZAAcJgB5UBQB0AgAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCgYICwAAAA==.',
Sw='Swagnasty:BAABNQAECoEXAAMPAAcJXxZ/FQD6AQAPAAcJXxZ/FQD6AQANAAYJKw99PQBvAQAAAA==.',
Sy='Sydarais:BAAANQAECgQIBgAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.',
Ta='Takua:BAAANQAECgMIBAAAAA==.Taleya:BAAANQAECgUICwAAAA==.Tanarumn:BAAANQAECgEIAQAAAA==.Tanilyn:BAAANQADCgUICgAAAA==.Tarryn:BAAANQADCgcIDgAAAA==.',
Te='Teahupoo:BAAANQADCgUIBwAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Terrorblades:BAAANQADCggICAABNQAECgYIEQABAAAAAA==.Tevye:BAAANQAECgEIAQAAAA==.',
Th='Tharin:BAAANQADCgEIAQAAAA==.Theßrush:BAAANQAECgEIAQAAAA==.Thorag:BAAANQADCgEIAQABNQAECgYIEQABAAAAAA==.Thornlox:BAAANQAECgMIAwAAAA==.Thorwal:BAAANQADCgEIAQAAAA==.Thorzak:BAAANQAECgYIDAAAAA==.Threeplates:BAABNQAECoEeAAMaAAgJRBD+EAAfAgAaAAgJQQ/+EAAfAgAbAAcJmA9DGQC6AQAAAA==.',
Ti='Tiktik:BAAANQAECgQICAAAAA==.Tiktikmage:BAAANQAECgIIAgAAAA==.Tiltz:BAAANQADCggIFgAAAA==.Tismtasm:BAAANQADCgUIBQAAAA==.',
To='Toptree:BAAANQADCgUIBgAAAA==.Topétine:BAAANQAECgQIBAAAAA==.',
Tr='Traskk:BAAANQADCggIEgAAAA==.Trelious:BAAANQAECgIIAwAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQAECgEIAgAAAA==.Tryel:BAABNQAECoEaAAIKAAkJpyLQBwB8AwAKAAkJpyLQBwB8AwAAAA==.Trínídad:BAAANQAECgIIAgAAAA==.',
Tu='Tuaca:BAAANQADCgIIAgAAAA==.Turdsmasher:BAAANQAECgEIAgAAAA==.Turumbar:BAAANQAECgQIBgAAAA==.',
Tw='Twysted:BAAANQAECgYICQAAAA==.',
Ty='Tybeross:BAAANQAECgEIAQAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Uh='Uhttred:BAAANQADCggICAABNQAECgYIBgABAAAAAA==.',
Ul='Ultrazord:BAAANQADCgYIFAAAAA==.',
Un='Unholynight:BAAANQADCgcIEgAAAA==.',
Ur='Urosh:BAAANQABCgcIBwAAAA==.',
Va='Vaks:BAAANQAECggIDwAAAA==.Valantriç:BAAANQAECgYICQAAAA==.Valkormyr:BAAANQAECgEIAQAAAA==.Vanishingson:BAAANQAECgQIBAAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAAANQAECgYIBgAAAA==.Vaylkyrie:BAAANQADCgUIBQAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomsnake:BAAANQADCgcIFwAAAA==.Venura:BAAANQAECgQIBgAAAA==.Verelidaine:BAABNQAECoEYAAIHAAkJRiKlCABJAwAHAAkJRiKlCABJAwAAAA==.Vessper:BAAANQAECgcIEAAAAA==.Vexmama:BAAANQADCgEIAQAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQAECgQIBgABNQAECgQICQABAAAAAA==.Vicious:BAAANQADCgcICgAAAA==.Victor:BAAANQAECgQIBQAAAA==.',
Vo='Voidglazer:BAAANQAECgQIBQAAAA==.Vorvadoss:BAAANQADCgUIBQABNQADCgcIEAABAAAAAA==.Vosik:BAAANQADCgYIEwAAAA==.Voxxy:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Vy='Vyne:BAAANQADCgcICwAAAA==.',
Wa='Wafsei:BAAANQADCggIDwAAAA==.',
We='Welcor:BAAANQADCgEIAQABNQAECgYIDQABAAAAAA==.Welkor:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Wetspots:BAAANQADCgEIAQAAAA==.',
Wh='Whammyshammy:BAAANQAECgQIBAAAAA==.Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Wildness:BAAANQADCgUIBQAAAA==.Wiligoldi:BAAANQAECgQIBwAAAA==.Withsauce:BAAANQAECgQIBQAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAACNQAFFIEFAAIUAAMJ7wzfCgDsAAAUAAMJ7wzfCgDsAAA1AAQKgSEAAxQACQmqIe8OAFADABQACQmqIe8OAFADABwAAQlyDF4cADYAAAAA.',
['Wä']='Wäyz:BAAANQADCggIBAABNQADCggIFgABAAAAAA==.',
Xa='Xanbar:BAAANQADCggIEQAAAA==.Xandent:BAAANQAECgMIAwAAAA==.Xanju:BAAANQAECgYIEQAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.Xarc:BAAANQADCgMIAQAAAA==.Xarnlu:BAAANQADCgEIAQABNQAECgQIEAABAAAAAA==.',
Xe='Xep:BAAANQAECgcIEgAAAA==.',
Xi='Xinkz:BAAANQAECgMIAwAAAA==.',
Xu='Xunji:BAAANQADCggIDQAAAA==.',
Ya='Yaariissa:BAAANQADCgMIBAAAAA==.',
Yl='Ylliria:BAAANQAECgQICAAAAA==.',
Yo='Yourholyness:BAAANQADCggIDwABNQAECgYIBgABAAAAAA==.',
Ys='Yso:BAAANQADCggIDgAAAA==.',
['Yü']='Yüm:BAAANQADCgcIBwAAAA==.',
Za='Zafadk:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Zaletra:BAAANQAECgIIAgAAAA==.Zalil:BAAANQADCggIGQAAAA==.Zarcyna:BAACNQAFFIEFAAQQAAMJ1xgeCgDBAAAQAAIJoh4eCgDBAAARAAEJfw3eDABUAAAdAAEJQw0CBQBNAAA1AAQKgSAAAxAACQmNJf8AAMgDABAACQl7Jf8AAMgDABEABAlzI6UaAGoBAAAA.Zathoron:BAAANQAECgYIEQAAAA==.',
Ze='Zenfox:BAAANQAECgcIEQAAAA==.',
Zi='Ziatora:BAAANQAECgMIBQAAAA==.Zimmy:BAAANQADCggIDQAAAA==.',
Zo='Zosh:BAAANQADCggIBgAAAA==.',
Zu='Zultaj:BAAANQAECgMIAwAAAA==.Zumwalathas:BAAANQADCgYIDAAAAA==.',
['Àr']='Àriýa:BAAANQAECgIIAgAAAA==.',
['Âs']='Âstryl:BAAANQAECgEIAQAAAA==.',
['Ãl']='Ãleyah:BAAANQADCgQIBAAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQADCgYIDQAAAA==.',
['Äs']='Ästryl:BAAANQADCgIIAwAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAAANQAECgMIAwAAAA==.',
['Ða']='Ðarrow:BAAANQAECgUIBgAAAA==.',
['Öm']='Ömni:BAAANQADCgUIBQAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgQIBwAAAA==.',
['ßa']='ßaroness:BAAANQAECgQICQAAAA==.',
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
