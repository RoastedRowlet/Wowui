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

local lookup = {'DemonHunter-Vengeance','DeathKnight-Blood','Unknown-Unknown','Mage-Fire','DeathKnight-Unholy','Shaman-Elemental','Shaman-Enhancement','Shaman-Restoration','Mage-Arcane','Warrior-Protection','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Frost','Druid-Guardian','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Paladin-Holy','Priest-Discipline','Druid-Balance','Hunter-Marksmanship','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaradh:BAABNQAECoEcAAIBAAgKZQc5EABKAQABAAgKZQc5EABKAQAAAA==.Aaradk:BAABNQAECoEYAAICAAcKIg30UABsAQACAAcKIg30UABsAQABNQAECggIHAABAGUHAA==.Aarahunt:BAAANQAECgIIAgABNQAECggIHAABAGUHAA==.',
Ab='Abaddondk:BAAANQAECgcIEQABNQAECggJAQADAAAAAA==.Abilify:BAAANQABCgcIHwAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Acez:BAAANQAECggJEAAAAA==.Acidwaste:BAAANQADCgYIDgAAAA==.',
Ad='Addilynn:BAAANQADCgEIAQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECoEaAAIEAAgK9xHEAQAuAgAEAAgK9xHEAQAuAgAAAA==.',
Ae='Aelania:BAAANQAECgMJAwAAAA==.Aelunara:BAABNQAECoEcAAMFAAYKrhnJOgDUAQAFAAYKrhnJOgDUAQACAAEKbxAurgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgQIBAAAAA==.',
Ai='Ailric:BAAANQAECgUICwAAAA==.',
Al='Alarakian:BAAANQAECgEIAQAAAA==.Alexei:BAAANQAECgUIDAAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECoEYAAQGAAgK+QzCVQDTAQAGAAgK+QzCVQDTAQAHAAIKkgNkJwBbAAAIAAEKEwPPAAEcAAAAAA==.Alkhan:BAAANQAECgUIDQABNQAECgkJHAAJAOoLAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgUIBwAAAA==.Altos:BAABNQAECoEjAAIKAAkKZQqTEgCgAQAKAAkKZQqTEgCgAQAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQADCgcJDAAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anavar:BAAANQADCgYICwAAAA==.Angerclaw:BAAANQAECgQICgAAAA==.Animeow:BAAANQAFFAIIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgQIBgAAAA==.Annasun:BAAANQADCgUIBQABNQAECgYICwADAAAAAA==.',
Ap='Apoth:BAAANQAECgEJAQABNQAECggIDQADAAAAAA==.Apotheke:BAAANQAECggIDQAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAAANQAECgUIDwAAAA==.Arcanofrosty:BAAANQAECgQIBwAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQAECgQICgAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcICwAAAA==.',
Aw='Awni:BAABNQAECoEaAAILAAgKCRPVaAALAgALAAgKCRPVaAALAgAAAA==.',
Ba='Bacon:BAABNQAECoEeAAIMAAgKAQ2nIwDEAQAMAAgKAQ2nIwDEAQAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECoEUAAIJAAcKWh5EdgBbAgAJAAcKWh5EdgBbAgAAAA==.Baknow:BAAANQAECgEIAQAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgkJKAANAPsbAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgUICwAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYICgAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECgYICAAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECoEbAAIOAAgKGxlnPABuAgAOAAgKGxlnPABuAgAAAA==.Benzos:BAABNQAECoErAAMPAAkKuyRhBQBWAwAPAAgKPyRhBQBWAwAQAAgKZiIbAwDeAgAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECoEgAAIRAAgKrRPVEwDpAQARAAgKrRPVEwDpAQAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUICQAAAA==.Bigpapapump:BAAANQADCggIAQAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQADCgYIDAAAAA==.',
Bl='Bluerose:BAAANQAECgEIAQAAAA==.Blurry:BAAANQAECgYICwAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgQIDgADAAAAAA==.Bountmage:BAAANQAECgQIBAAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgUICQAAAA==.Brokentuskz:BAAANQAECggJAQAAAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.',
Bu='Buffbutton:BAAANQAECgUICgABNQAECgkJHQALAKMZAA==.Buffstallion:BAAANQAECgEIAgAAAA==.Buzzie:BAAANQADCgYICAAAAA==.',
['Bï']='Bïllï:BAABNQAECoEeAAIGAAkKeB/4FQAfAwAGAAkKeB/4FQAfAwAAAA==.',
Ca='Caerisma:BAAANQAECgYIFAAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQADCgQIBAAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQADCgYICQABNQAECgYIFAADAAAAAQ==.Chudmax:BAAANQADCgYICAAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Cloax:BAABNQAECoEfAAIMAAgKgR+VEAC3AgAMAAgKgR+VEAC3AgAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.',
Cr='Craerman:BAAANQADCgUJBQABNQAECgYIFAADAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAABNQAECoEgAAISAAgKxRtQTQBeAgASAAgKxRtQTQBeAgAAAA==.',
Cu='Cussack:BAABNQAECoEfAAILAAgKdyLxIgAHAwALAAgKdyLxIgAHAwAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgkJKAANAPsbAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgQICQAAAA==.Darkgol:BAAANQAECgUIBQABNQAECggIGgASALYQAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQADCgUIBQAAAA==.',
De='Deadlyheal:BAAANQADCgEIAQABNQADCggICAADAAAAAA==.Deadtalini:BAABNQAECoEfAAMTAAkKNhyNDgDnAgATAAkKcxuNDgDnAgACAAUKoxEabgDvAAAAAA==.Deah:BAAANQAECgQIBQAAAA==.Deaththroes:BAAANQAECgEIAQAAAA==.Deckerdramon:BAABNQAECoEaAAIKAAcKlh9oCQBjAgAKAAcKlh9oCQBjAgAAAA==.Demomachin:BAABNQAECoEYAAIBAAcKihA3DgBzAQABAAcKihA3DgBzAQAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgYIEgADAAAAAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Deucalyon:BAAANQADCggIGgAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAACNQAFFIENAAIIAAUKBRgyBgCwAQAIAAUKBRgyBgCwAQA1AAQKgR4AAggACQrGHAEeAMACAAgACQrGHAEeAMACAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggICQAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFIEMAAIRAAUKoSXmAAAvAgARAAUKoSXmAAAvAgA1AAQKgSkAAhEACQr2JgoAAA0EABEACQr2JgoAAA0EAAAA.',
Do='Dohtem:BAAANQADCgYICwABNQAECggIGAAHAPweAA==.Donmegah:BAAANQAECgUICQAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgEIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECggIEAADAAAAAA==.Dredtotem:BAAANQADCggICAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAAANQAECgUICwAAAA==.Dutanu:BAAANQAECgQIBgABNQAECgYIDQADAAAAAA==.',
Ei='Eibhlean:BAAANQAECgUIDgABNQAECgIIAwADAAAAAA==.Eireckt:BAAANQADCgcICQAAAA==.Eirrin:BAAANQAECgMIAwABNQAECgkJHgAOAOIhAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAAANQAECgUICAAAAA==.Eleforever:BAABNQAECoEjAAIGAAkKKSHpEQA+AwAGAAkKKSHpEQA+AwABNQAECgkJIwAGACkhAA==.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECgcICQAAAA==.',
Em='Emongar:BAAANQABCgIIAQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAUIDAAUAKsgAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Evlynia:BAAANQADCgEIAQAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECoEXAAIVAAgKggs5bADCAQAVAAgKggs5bADCAQAAAA==.',
Fa='Fableshoot:BAAANQADCgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgADAAAAAA==.Fatherclutch:BAAANQADCgQICAABNQAECgcICAADAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAABNQAECoEgAAIOAAgK4h31LgCgAgAOAAgK4h31LgCgAgAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgYIGgAWAF0KAA==.Felwoof:BAABNQAECoEgAAQXAAgKFh38DAA8AQAVAAUKdhz5eQCZAQAXAAQK1Rr8DAA8AQAYAAEKUyL3WgBcAAAAAA==.Felzak:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYICwAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECoEjAAITAAkK/CEfCgAgAwATAAkK/CEfCgAgAwAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAQADAAAAAA==.Forthehordde:BAAANQABCgcJCwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgMJBAABNQAECggIHgAZAGghAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFIEMAAIMAAUKnAyQBQCEAQAMAAUKnAyQBQCEAQA1AAQKgSAAAgwACQoNGxkRAK4CAAwACQoNGxkRAK4CAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Furystrike:BAABNQAECoEcAAMKAAgK3iSkAwAhAwAKAAgKNSOkAwAhAwALAAgKGxzDQACOAgAAAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECoEYAAIMAAgKkSFsCgAVAwAMAAgKkSFsCgAVAwAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAAANQAECgYIDAAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQAECgUIBQAAAA==.',
Gh='Ghst:BAAANQAECgcIBwAAAA==.',
Gi='Gibayy:BAAANQAECgQIBwAAAA==.Gibsonex:BAAANQAECgIIAwAAAA==.Gildagni:BAAANQADCgcICgAAAA==.Gilliamm:BAABNQAECoEkAAMNAAkK6xJxHwCtAQANAAYKVRZxHwCtAQAPAAUKMg5kQgAzAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAABNQAECoEaAAISAAgKthAgcADyAQASAAgKthAgcADyAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQAECgIIAwAAAA==.Gothbutta:BAAANQADCgYIEwAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQADCggJEAAAAA==.Greatangel:BAAANQADCgUIBAABNQAECgYICwADAAAAAA==.Gregano:BAAANQADCgEIAQABNQAECggIGQALABQJAA==.Gregorian:BAABNQAECoEZAAILAAgKFAlvmQB8AQALAAgKFAlvmQB8AQAAAA==.Gremliin:BAABNQAECoEnAAIZAAkKMB8DEAAdAwAZAAkKMB8DEAAdAwAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQADCggICAAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQADCgEIAQAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healminth:BAAANQAFFAIIAgAAAA==.Healthcare:BAAANQADCggIGQAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hilltop:BAAANQABCgEJAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgEIAgAAAA==.Holdor:BAAANQADCgEIAQAAAA==.Holdors:BAAANQADCgcIBwAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgcIEAADAAAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIAwABNQAECgYIEgADAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYJBgADAAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQADCgYIBgABNQAFFAYIDwAIAC0dAA==.Intaria:BAABNQAECoElAAMLAAgK1xRXXwAoAgALAAgKohRXXwAoAgAaAAMKlw5ZGgCpAAAAAA==.Invisibulity:BAAANQADCgQIBAABNQAECgYIGgAWAF0KAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.Itsrambo:BAAANQAECgEIAQAAAA==.',
Ja='Jackbeef:BAABNQAECoEgAAIaAAgKgB+FAwDTAgAaAAgKgB+FAwDTAgAAAA==.Jadedhooves:BAAANQAECgUIDwAAAA==.Jaggedlilhun:BAABNQAECoEZAAIOAAgK0w65YgD6AQAOAAgK0w65YgD6AQAAAA==.Jaggedshammy:BAAANQAECgUIBQABNQAECggIGQAOANMOAA==.Jagruk:BAAANQADCgIIAgABNQADCggICAADAAAAAA==.Jareyk:BAABNQAECoEbAAIbAAgK1RL8SAAAAgAbAAgK1RL8SAAAAgAAAA==.Jarladorin:BAAANQAECgEIAQABNQAECgYIDQADAAAAAA==.Jaxodk:BAAANQAECggIEwAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jedai:BAABNQAECoEvAAIbAAkKqx7vEgATAwAbAAkKqx7vEgATAwAAAA==.Jellybeann:BAAANQADCgQICAAAAA==.Jerrysix:BAABNQAECoEWAAMMAAcK+BRBIgDUAQAMAAcK+BRBIgDUAQAcAAMKgAdHFgCLAAAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgYICAADAAAAAA==.Jimmypop:BAAANQADCggICAAAAA==.',
Ju='Judadiah:BAAANQAECgYIDQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQAECgIIBAAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECggIGQAOANMOAA==.',
Ka='Kalrock:BAAANQAECgcIEQAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgcIEQADAAAAAA==.Kalulu:BAAANQADCgcIFQAAAA==.Kalyssi:BAAANQADCggIEQAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIFQAAAA==.Katkot:BAAANQAECgUICwAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazlan:BAAANQAECgMIAwAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Keres:BAABNQAECoEjAAICAAkKSiRMBQCLAwACAAkKSiRMBQCLAwABNQAECgkJIwACAEokAA==.',
Kh='Khagolith:BAABNQAECoEZAAIdAAcKeRLXPQC3AQAdAAcKeRLXPQC3AQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kizzazz:BAAANQADCgQIBAAAAA==.',
Kk='Kkodabear:BAAANQADCggIDwAAAA==.',
Kl='Klixeas:BAAANQADCgIIAgAAAA==.',
Ko='Kobiter:BAAANQAECgYIEQABNQAECggIHwAKAHIgAA==.Kobito:BAABNQAECoEfAAMKAAgKciClBQDXAgAKAAgKciClBQDXAgALAAQKZQuc0wDZAAAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECoEmAAMOAAkKKyUJAwDDAwAOAAkKKyUJAwDDAwAeAAEKfhLsbAA1AAAAAA==.Koupe:BAAANQAECgUIDwABNQAECgkJJgAOACslAA==.',
Kr='Krang:BAAANQAECgIIAQAAAA==.Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUICQADAAAAAA==.Kriss:BAAANQAECgMIBAAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgkJJgAOACslAA==.Kurirne:BAAANQADCgIIAgAAAA==.',
Ky='Kyewanda:BAAANQAECgUIBwAAAA==.Kyusakuu:BAAANQAECgYIDAAAAA==.',
La='Laanu:BAAANQAECgIJAgABNQAECggIHgANAHwVAA==.Lahey:BAABNQAECoEkAAILAAkKKw5LZgASAgALAAkKKw5LZgASAgAAAA==.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgUICQAAAA==.Lavs:BAAANQAECgYIEQAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgcIEQAAAA==.Lexiah:BAAANQAECgUICAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgQIBgADAAAAAA==.Lizardbrain:BAAANQAECgMIBQAAAQ==.',
Lo='Loamathor:BAAANQADCggIHQAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lorilyn:BAAANQAECgYIEQAAAA==.Lorthag:BAAANQAECgYIEwAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQAECgUICwAAAA==.Lunareclips:BAAANQADCgMIAwAAAA==.Lunarus:BAAANQAECgUIDwAAAA==.',
['Lì']='Lìfe:BAABNQAECoEXAAILAAcKdBPkfwDHAQALAAcKdBPkfwDHAQAAAA==.',
['Ló']='Lónnie:BAAANQADCggICAAAAA==.Lónnìe:BAAANQAECgQIDQAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgQIBAAAAA==.Maelona:BAAANQAECgUIBwAAAA==.Maen:BAAANQADCgcIBwAAAA==.Magrumok:BAAANQAECgUIDAAAAA==.Magthars:BAAANQAECgEIAQAAAA==.Magtide:BAAANQAFFAIIBAAAAA==.Malväryx:BAAANQAECgQIBwAAAA==.Manbearpig:BAABNQAECoEkAAIOAAkKgSJ7CwBgAwAOAAkKgSJ7CwBgAwAAAA==.Manman:BAAANQAECgMIBAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgADAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUIBgAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECoEgAAIJAAgKdh3WZQCCAgAJAAgKdh3WZQCCAgAAAA==.Mellindre:BAAANQADCggICQAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECoEaAAIfAAgKqwx3IwBpAQAfAAgKqwx3IwBpAQAAAA==.Mesa:BAABNQAECoEQAQMgAAkKPyYlAAD4AwAgAAkKPyYlAAD4AwAWAAEKGhI9MABJAAAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECoEcAAMNAAgKaRbmEQBDAgANAAgKYBbmEQBDAgAPAAIKBwWYawBbAAAAAA==.Microplastic:BAABNQAECoEdAAMLAAkKoxm2NAC7AgALAAkKoxm2NAC7AgAKAAUKYRURGwAoAQAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECoEYAAIFAAcK0Bq5MAAQAgAFAAcK0Bq5MAAQAgAAAA==.Minigunn:BAAANQADCggIDgAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgEIAQAAAA==.Misosmol:BAAANQAECgIIAwAAAA==.Missogyny:BAAANQAECgYIEgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQADCgcIFgAAAA==.Mogando:BAAANQAECgEIAQABNQAECggIEAADAAAAAA==.Mogrodeath:BAAANQAECgIIAQAAAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgcIGAAYAAwgAA==.Mogrogarg:BAABNQAECoEYAAMYAAcKDCAHIwBFAQAVAAUK2R/SaQDKAQAYAAQKrBoHIwBFAQAAAA==.Mogrosham:BAAANQAECgEIAgAAAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgcIGAAYAAwgAA==.Mojojojò:BAAANQAECgEIAQAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgkJJgAhAGAbAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAECggICAAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQADCggJCQAAAA==.Moribelar:BAAANQAECgEIAgAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQAECgQIBgABNQAECgcIGQAiAAkgAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgYIDgAAAA==.Mousyz:BAAANQADCgIIAgAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAABNQAECoEdAAISAAgK0gULqQBdAQASAAgK0gULqQBdAQAAAA==.Munusku:BAAANQAECgEIAQAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAAANQAECgEIAQAAAA==.',
Na='Nachobussy:BAABNQAFFIEIAAMOAAUK3g0yDgD3AAAOAAMK/RMyDgD3AAAeAAMKtgfaEADOAAAAAA==.Nachothings:BAABNQAECoEYAAMjAAkKWxb+GQBUAgAjAAkKWxb+GQBUAgAkAAEKVhnmbABGAAABNQAFFAUICAAOAN4NAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgIIBgAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECgEJAQABNQAECggIFgAVAD4kAA==.',
Ni='Nightmist:BAAANQADCgcIGwAAAA==.Nihility:BAABNQAECoEWAAMVAAgKPiTDHgDYAgAVAAcKKyTDHgDYAgAYAAIKuiBBPwCwAAAAAA==.Nirgand:BAAANQAECgEIAQABNQAECggIEAADAAAAAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Noodlestang:BAAANQAECgYIEgAAAA==.Nool:BAAANQAECgEIAQAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAAANQAECggIEAAAAA==.Noriboness:BAAANQAECgQIBQAAAA==.Nosleep:BAABNQAECoEiAAIKAAgKeRlnCwAzAgAKAAgKeRlnCwAzAgAAAA==.Notdumb:BAAANQADCgUJDAAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgMIAwAAAA==.Nyduss:BAAANQAECgMIBQAAAA==.Nymphs:BAAANQADCgEIAQABNQADCggIDgADAAAAAA==.Nyraxys:BAAANQAECgYIDAAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQAECgEIAQAAAA==.',
Od='Oddzmage:BAAANQAECgQICAAAAA==.',
On='Onibushi:BAABNQAECoEZAAILAAcK3RdxagAGAgALAAcK3RdxagAGAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECoEfAAIJAAkKaxsWOAD7AgAJAAkKaxsWOAD7AgAAAA==.',
Or='Orastal:BAAANQAECgcICgAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oroki:BAAANQADCggIAgAAAA==.Oruun:BAABNQAECoEtAAIGAAgK8iLgEgA3AwAGAAgK8iLgEgA3AwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQIBwAAAA==.Pandadander:BAAANQADCgYIBgABNQAECgUIDAADAAAAAA==.Pandalo:BAAANQADCgcIEAAAAA==.Pandalock:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.Parasiite:BAAANQAECgYIDwAAAA==.',
Pe='Peepocute:BAAANQAECgYIDgAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgQIBAAAAA==.Physiowar:BAAANQAECgYIEwAAAA==.',
Pi='Pickledeath:BAAANQAECgQJBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECoEpAAMgAAkK7iOMAQCoAwAgAAkK7iOMAQCoAwAWAAIKMQptLABtAAAAAA==.Popster:BAAANQADCgUIBQAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQADCggIEQAAAA==.Preservation:BAAANQAECgcIDgAAAA==.Prodipriest:BAAANQAECgcIBgAAAA==.',
Pu='Pugi:BAAANQADCgEIAQAAAA==.Putridstrike:BAAANQAECggICQABNQAECggIHAAKAN4kAA==.',
Qt='Qtiy:BAAANQADCgYICQABNQAECgYIEQADAAAAAA==.Qtyy:BAAANQAECgYIEQAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ramped:BAAANQAECgQIBQAAAA==.Ranzor:BAAANQAECgUICQAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQAECgQIDgAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAAANQAECgMICQAAAA==.Reitiado:BAAANQADCgIIAgAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgUIDwADAAAAAA==.Rekita:BAAANQAECgUIDwAAAA==.Remedi:BAAANQAECgYICgAAAA==.Retaxus:BAAANQABCgEJAQAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECoEYAAIOAAcKnw93fwCtAQAOAAcKnw93fwCtAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rimmjab:BAAANQADCgEIAQAAAA==.',
Rn='Rn:BAAANQAECgUJBwAAAA==.',
Ro='Roderika:BAAANQADCgcIDgABNQAECgkJIwACAEokAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAAANQAECgYIEQAAAA==.Romanflak:BAAANQAECgIIAgAAAA==.Roostr:BAABNQAECoEZAAIYAAcKqxREDwD2AQAYAAcKqxREDwD2AQAAAA==.Rord:BAAANQAECgYIEQAAAA==.Royjacked:BAAANQAECgEIAQAAAA==.',
Ru='Rubberr:BAAANQAECgQICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgIIAwAAAA==.Runicstrike:BAABNQAECoE0AAQFAAkKNSWyCgBBAwAFAAgKmiWyCgBBAwACAAYKqx67NwDpAQATAAUKYBiRRwAfAQABNQAECggIHAAKAN4kAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCgYJBgAAAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAADAAAAAA==.Sahra:BAABNQAECoEdAAIIAAgK6SWDCABgAwAIAAgK6SWDCABgAwAAAA==.Sanctustrike:BAABNQAECoEZAAMSAAkKZyH6NAC2AgASAAgKjR/6NAC2AgAfAAYKqR5pFwDoAQABNQAECggIHAAKAN4kAA==.Saraphina:BAAANQAECgQIBgAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAAANQAECgcIDwAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECggIEAADAAAAAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQAECgQIBAAAAA==.Sherfight:BAABNQAECoEeAAMZAAgKaCF+EQASAwAZAAgKaCF+EQASAwAMAAMKFxHoRwCiAAAAAA==.Shielddaddy:BAAANQAECgIIBAAAAA==.Shieldsftl:BAAANQAECgYICAAAAA==.Shiftycent:BAAANQAECggIAQAAAA==.Shnyaga:BAABNQAECoEXAQQZAAkKIiUrAQDQAwAZAAkKIiUrAQDQAwAMAAQKtB8eKwB7AQAcAAIKQRUoFQCbAAAAAA==.Shockybalboa:BAAANQADCgUIDgAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQABCgMIAgAAAA==.',
Si='Sianda:BAAANQABCgQIBAAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQAAAA==.Sinsanityz:BAAANQAECggICgAAAA==.Sixxsevenn:BAAANQADCgcIBwAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAAANQAECgMIBwAAAA==.Skrai:BAAANQAECgMIBQAAAA==.',
Sl='Sleew:BAABNQAECoEiAAMVAAgKWRviPwBTAgAVAAcKyBviPwBTAgAYAAIKTRF9TwB7AAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sm='Smokintrees:BAAANQADCgcIDAAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECoEhAAIkAAgKwCKsCwAmAwAkAAgKwCKsCwAmAwAAAA==.Souldaddy:BAAANQAECgEIAQAAAA==.',
Sp='Spankinstien:BAAANQADCggICAAAAA==.Specsdraco:BAABNQAECoEpAAIeAAkKFSH0BABwAwAeAAkKFSH0BABwAwAAAA==.Spewpuke:BAABNQAECoEgAAMKAAgKYR8DCACKAgAKAAcKCCEDCACKAgALAAUKzw4ctAAtAQAAAA==.Spicytomato:BAABNQAECoEbAAMXAAgKRiC9AQD6AgAXAAgKRiC9AQD6AgAYAAEKTxduZQBAAAAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECoEeAAIZAAgKXhNCSAD9AQAZAAgKXhNCSAD9AQAAAA==.Starstorm:BAAANQADCgQIBAABNQAECggIIgAVAFkbAA==.Stgermain:BAABNQAECoEYAAMZAAgK6x5pLwBpAgAZAAcKDh9pLwBpAgAMAAUK9RQeMwA2AQAAAA==.Stormlotus:BAAANQAECgIIBAAAAA==.Stormsorrow:BAAANQAECgQIBQAAAA==.Strikeanywer:BAAANQAECgIIAgAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgIIAgAAAA==.',
Sy='Sylrana:BAAANQAECgMIAwAAAA==.Sylri:BAAANQADCgYIBgAAAA==.',
Ta='Taktikil:BAAANQADCgYIEwAAAA==.Talrad:BAAANQAECgQIBgAAAA==.Tamale:BAAANQAECggIBQAAAA==.Tazerxface:BAABNQAECoEmAAIIAAkKExLPQgAJAgAIAAkKExLPQgAJAgAAAA==.',
Te='Tealgos:BAABNQAECoEaAAIWAAYKXQrxHQAxAQAWAAYKXQrxHQAxAQAAAA==.Teenyhands:BAAANQAECgQIBAAAAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAAANQAECgYIEwAAAA==.Thanx:BAAANQAECgIIAgAAAA==.Thebeefchief:BAACNQAFFIEGAAIUAAQKjhxPAQBlAQAUAAQKjhxPAQBlAQA1AAQKgRoAAhQACQoqIrUCAGEDABQACQoqIrUCAGEDAAAA.Thebigmon:BAABNQAECoEcAAIGAAcKzx2RNQBcAgAGAAcKzx2RNQBcAgAAAA==.Thedabara:BAAANQADCgMIAwAAAA==.Thedon:BAAANQAECgUIBwAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQADCgYIBQAAAA==.Thrudtotems:BAAANQAECgYIBwAAAA==.Thrudx:BAAANQAECgYIDwAAAA==.Thugnastie:BAAANQAECgUIDAAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAAANQAECgQICAAAAA==.Timeisdruid:BAAANQAECgEIAQAAAA==.Tinytina:BAAANQAECgUIBQAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgUIDAAAAA==.Togashi:BAABNQAECoEaAAIlAAcK+CGgEACeAgAlAAcK+CGgEACeAgAAAA==.Topacio:BAAANQADCggIGgAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAUICAAOAN4NAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQAECgUIDAAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECgYIDwAAAA==.Tricep:BAAANQADCggIEQAAAA==.Tripallie:BAAANQADCgQIDQAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Trunkmuffin:BAAANQAECgEIAQAAAA==.Truthless:BAEBNQAECoEkAAIbAAkKrh3HDgAzAwAbAAkKrh3HDgAzAwAAAA==.',
Tu='Tuckermax:BAAANQADCgYICwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAAANQAECgYIEwAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgkJKQAgAO4jAA==.',
Ug='Uglyashell:BAAANQAECgEIAQAAAA==.',
Un='Unit:BAABNQAECoEZAAIHAAcKMx9yCwCCAgAHAAcKMx9yCwCCAgAAAA==.',
Uv='Uva:BAAANQAECgIIAgAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECoEWAAIXAAgKORN1BQAnAgAXAAgKORN1BQAnAgAAAA==.Valsorin:BAAANQAECgIIAwAAAA==.Valtaea:BAABNQAECoEcAAIJAAkK6gvAnAABAgAJAAkK6gvAnAABAgAAAA==.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUICQADAAAAAA==.Voidwaffle:BAAANQADCgcIBwAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.',
Wa='Wafflxs:BAACNQAFFIEGAAIRAAUKZB84AgC8AQARAAUKZB84AgC8AQA1AAQKgSIAAhEACQrNJLsBAJUDABEACQrNJLsBAJUDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECoEaAAISAAgKLBmiVwA8AgASAAgKLBmiVwA8AgAAAA==.Warglave:BAAANQAECgQIBAAAAA==.Warmo:BAAANQADCggICAAAAA==.Warunk:BAAANQAECgYICAAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weiwu:BAABNQAECoEnAAIlAAkKwB2eCwDvAgAlAAkKwB2eCwDvAgAAAA==.Wellfookthat:BAABNQAECoEhAAIIAAgKayFKFwDoAgAIAAgKayFKFwDoAgAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECggIIQAIAGshAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAAANQAECgUIDgAAAA==.Whyvala:BAAANQADCgcIGgABNQADCgcIDgADAAAAAA==.Whyvara:BAAANQADCgcIDgAAAA==.',
Wi='Wiisp:BAAANQAECgUIDQAAAA==.',
Wo='Wolnney:BAABNQAECoEiAAISAAkKjiQgBwCvAwASAAkKjiQgBwCvAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQJBAAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgcIEgAAAA==.',
Xa='Xalatoes:BAACNQAFFIEPAAIIAAYKLR2LAgAwAgAIAAYKLR2LAgAwAgA1AAQKgSIAAggACQojIY0RABADAAgACQojIY0RABADAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQADCgUIBgAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQADCggIGQADAAAAAA==.Xiren:BAAANQABCgIJBAAAAA==.',
Xr='Xraiz:BAAANQAECgIIAgAAAA==.',
Xy='Xyne:BAAANQADCggJEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAABNQAECoEtAAIRAAkKMyScAQCbAwARAAkKMyScAQCbAwAAAA==.Yourboyblue:BAAANQADCgYIEAAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICAAAAA==.Zanza:BAAANQAECgQIBwAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zhayden:BAAANQAECgYIDwAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQADCgcIEwABNQAECgUIBwADAAAAAA==.Zombiez:BAABNQAECoEOAAIFAAYKFAmdZQARAQAFAAYKFAmdZQARAQAAAA==.Zoryn:BAAANQADCgcIEAABNQADCggICAADAAAAAA==.',
['Él']='Élowen:BAAANQAECgIIAwAAAA==.',
['ßo']='ßoß:BAAANQABCggICwAAAA==.',
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
