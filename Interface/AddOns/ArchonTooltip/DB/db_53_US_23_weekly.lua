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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Mage-Arcane','Warrior-Protection','Shaman-Elemental','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Priest-Shadow','Paladin-Retribution','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Shaman-Restoration','Druid-Guardian','DeathKnight-Unholy','Priest-Holy','Warrior-Fury','Paladin-Holy','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Shaman-Enhancement','Warlock-Affliction',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaradh:BAABNQAECoEYAAIBAAgKZQeUDABXAQABAAgKZQeUDABXAQAAAA==.Aaradk:BAAANQAECgQJDQABNQAECggJGAABAGUHAA==.Aarahunt:BAAANQAECgIIAgABNQAECggJGAABAGUHAA==.',
Ab='Abaddondk:BAAANQAECgcICwABNQAECggJAQACAAAAAA==.Abilify:BAAANQABCgcIGwAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Acez:BAAANQAECggJEAAAAA==.Acidwaste:BAAANQADCgYICAAAAA==.',
Ad='Addilynn:BAAANQADCgEIAQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAAANQAECgYJDwAAAA==.',
Ae='Aelania:BAAANQAECgMJAwAAAA==.Aelunara:BAAANQAECgUJEQAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgQIBgAAAA==.',
Ai='Ailric:BAAANQAECgQJBgAAAA==.',
Al='Alarakian:BAAANQADCggIEgAAAA==.Alexei:BAAANQAECgUIBwAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAAANQAECgcJEwAAAA==.Alkhan:BAAANQAECgUJCQABNQAECggIGAADABoMAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgIIAgAAAA==.Altos:BAABNQAECoEbAAIEAAgKOAhGEgBoAQAEAAgKOAhGEgBoAQAAAA==.Alwayshazy:BAAANQABCgIIAgAAAA==.Alyssachik:BAAANQADCgcJDAAAAA==.',
Am='Amarxd:BAABNQAECoEjAAIFAAkKKSF/DABWAwAFAAkKKSF/DABWAwAAAA==.Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anavar:BAAANQADCgYICwAAAA==.Angerclaw:BAAANQAECgQIBgAAAA==.Animeow:BAAANQAFFAIIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annasun:BAAANQADCgUIBQABNQAECgMIBQACAAAAAA==.',
Ap='Apoth:BAAANQAECgEJAQABNQAECggJCAACAAAAAA==.Apotheke:BAAANQAECggJCAAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAAANQAECgUIDwAAAA==.Arcanofrosty:BAAANQAECgIJAwAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQAECgQJCAAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcJCwAAAA==.',
Aw='Awni:BAAANQAECgYIEAAAAA==.',
Ba='Bacon:BAAANQAECgcIEQAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAAANQAECgcJEwAAAA==.Baknow:BAAANQAECgEIAQAAAA==.Bambuu:BAAANQABCgYIBgAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgkJIgAGACcaAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgQIBgAAAA==.Bazzoo:BAAANQAECgYICAAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECoEZAAIHAAgKExkGKgCMAgAHAAgKExkGKgCMAgAAAA==.Benzos:BAABNQAECoEiAAMIAAkKoyO0BwAQAwAIAAgKxyG0BwAQAwAJAAgKZiJ6AgD4AgAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECoEZAAIKAAgKrRPHDwADAgAKAAgKrRPHDwADAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgMJBAABNQAECgQIDwACAAAAAA==.Bigpapapump:BAAANQADCggIAQAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQADCgYIBgAAAA==.',
Bl='Bluerose:BAAANQADCgcIDAAAAA==.Blurry:BAAANQAECgMIBQAAAA==.',
Bo='Bountmage:BAAANQADCggJDQAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgMJBAAAAA==.Brokentuskz:BAAANQAECggJAQAAAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.',
Bu='Buffbutton:BAAANQAECgQJCQABNQAECggJEgACAAAAAA==.Buffstallion:BAAANQAECgEIAQAAAA==.Buzzie:BAAANQADCgIJAgAAAA==.',
['Bï']='Bïllï:BAABNQAECoEbAAIFAAgKOCFoFgD6AgAFAAgKOCFoFgD6AgAAAA==.',
Ca='Caerisma:BAAANQAECgYJDgAAAQ==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQADCgEJAQAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQADCgYICQABNQAECgYJDgACAAAAAQ==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Cloax:BAABNQAECoEYAAILAAgKLR7LDQDDAgALAAgKLR7LDQDDAgAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCgcIBwAAAA==.',
Cr='Craerman:BAAANQADCgUJBQABNQAECgYJDgACAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAABNQAECoEaAAIMAAgKHxuoPQBcAgAMAAgKHxuoPQBcAgAAAA==.',
Cu='Cussack:BAABNQAECoEcAAINAAgK2yBjHwD9AgANAAgK2yBjHwD9AgAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgkJIgAGACcaAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgQJBgAAAA==.Darkgol:BAAANQADCggIFgABNQAECgYIEQACAAAAAA==.Darkmagix:BAAANQABCgEIAQAAAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQADCgUIBQAAAA==.',
De='Deadtalini:BAABNQAECoEWAAMOAAkKuhA5JwC7AQAOAAkK1Aw5JwC7AQAPAAUKoxFHXwD0AAAAAA==.Deah:BAAANQAECgQJBAAAAA==.Deaththroes:BAAANQAECgEIAQAAAA==.Deckerdramon:BAAANQAECgYIEAAAAA==.Demomachin:BAAANQAECgYJDgAAAA==.Demonnoodle:BAAANQADCgYIBgABNQAECgYIEQACAAAAAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Deucalyon:BAAANQADCggIFQAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAACNQAFFIEIAAIQAAUKzhAGBQCWAQAQAAUKzhAGBQCWAQA1AAQKgRsAAhAACQqPHNkVANgCABAACQqPHNkVANgCAAAA.',
Di='Dirtyhooves:BAAANQADCgYJBwAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFIEHAAIKAAQKJiPHAQClAQAKAAQKJiPHAQClAQA1AAQKgSMAAgoACQq1Jg0AAAcEAAoACQq1Jg0AAAcEAAAA.',
Do='Dohtem:BAAANQADCgYICwABNQAECggIEgACAAAAAA==.Donmegah:BAAANQAECgMJBAAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Draki:BAAANQADCgYIEAAAAA==.Dredtotem:BAAANQADCgcIBwAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAAANQAECgUIBgAAAA==.Dutanu:BAAANQAECgQIBgAAAA==.',
Ei='Eibhlean:BAAANQAECgUJCQABNQAECgEJAQACAAAAAA==.Eireckt:BAAANQADCgIIAgAAAA==.Eirrin:BAAANQAECgMJAwABNQAECgcJGwAHAGUjAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAAANQAECgQIBwAAAA==.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcICAAAAA==.Elleredreaux:BAAANQAECgYICAAAAA==.',
Em='Emongar:BAAANQABCgIIAgAAAA==.',
En='Endomorphism:BAAANQADCggIDgABNQAFFAUJCAARALAcAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Evilsugar:BAAANQABCgEIAQAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAAANQAECgUICQAAAA==.',
Fa='Fableshoot:BAAANQADCgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgACAAAAAA==.Fantasie:BAAANQADCgcIEAABNQAECgcIEwACAAAAAA==.Fatherclutch:BAAANQADCgQJBgABNQAECgcJBwACAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAABNQAECoEZAAIHAAgKux36JgCbAgAHAAgKux36JgCbAgAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgUIDwACAAAAAA==.Felwoof:BAAANQAECgYJEAAAAA==.Felzak:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYICwAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECoEjAAIOAAkK/CFTBQBeAwAOAAkK/CFTBQBeAwAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEJAQACAAAAAA==.Forthehordde:BAAANQABCgcJDQAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEJAQAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgMJBAABNQAECgcIEwACAAAAAA==.Fry:BAACNQAFFIEHAAILAAQKAAnQBQAtAQALAAQKAAnQBQAtAQA1AAQKgR4AAgsACQq3Gb4NAMQCAAsACQq3Gb4NAMQCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Furystrike:BAABNQAECoEWAAMEAAgKuiI3AwAVAwAEAAgKrCE3AwAVAwANAAgKuBqBRgBOAgABNQAECgkJLAASAGQjAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Galixie:BAAANQABCgIIAwAAAA==.Ganondrow:BAAANQAECgYIDwAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAAANQAECgYJBwAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQADCgYJDAAAAA==.',
Gh='Ghst:BAAANQAECgIIAgAAAA==.',
Gi='Gibayy:BAAANQAECgQIBQAAAA==.Gibsonex:BAAANQAECgEJAQAAAA==.Gildagni:BAAANQADCgcIBwAAAA==.Gilliamm:BAABNQAECoEdAAMGAAgKXhECHgCgAQAGAAYKehQCHgCgAQAIAAMKsArGSACwAAAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAAANQAECgYIEQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQAECgEJAQAAAA==.Gothbutta:BAAANQADCgYIDgAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Graydeon:BAAANQADCggJEAAAAA==.Greatangel:BAAANQADCgUIBAABNQAECgMIBQACAAAAAA==.Gregano:BAAANQADCgEIAQABNQAECgcIEgACAAAAAA==.Gregorian:BAAANQAECgcIEgAAAA==.Gremliin:BAABNQAECoEeAAITAAkKMB/RCgAwAwATAAkKMB/RCgAwAwAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQADCgYIBgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healminth:BAAANQAFFAIIAgAAAA==.Healthcare:BAAANQADCggIGQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hilltop:BAAANQABCgEJAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgEJAQAAAA==.Holdor:BAAANQADCgEIAQAAAA==.Holdors:BAAANQADCgYJBgAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAACAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgcIDQACAAAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIAgABNQAECgYIEQACAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYJBgACAAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQADCgYJBgABNQAFFAUJCQAQAIMcAA==.Intaria:BAABNQAECoEeAAMNAAgKpRPHUwAeAgANAAgKcBPHUwAeAgAUAAMKlw4dFgCtAAAAAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.Itsrambo:BAAANQAECgEIAQAAAA==.',
Ja='Jackbeef:BAABNQAECoEaAAIUAAgKlhxHAwCqAgAUAAgKlhxHAwCqAgAAAA==.Jadedhooves:BAAANQAECgQICgAAAA==.Jaggedlilhun:BAAANQAECgYIEQAAAA==.Jaggedshammy:BAAANQADCggIEAABNQAECgYIEQACAAAAAA==.Jagruk:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.Jareyk:BAAANQAECgYIEAAAAA==.Jarladorin:BAAANQADCgcJCgABNQAECgQIBQACAAAAAA==.Jaxodk:BAAANQAECgUIDQAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEJAgAAAA==.Jedai:BAABNQAECoErAAIVAAkKqx4nDgAdAwAVAAkKqx4nDgAdAwAAAA==.Jellybeann:BAAANQADCgQIBAAAAA==.Jerrysix:BAAANQAECgcIEAAAAA==.',
Ji='Jilseponie:BAAANQABCgMIBAABNQAECgIIAgACAAAAAA==.Jimmypop:BAAANQADCggICAAAAA==.',
Ju='Judadiah:BAAANQAECgQIBQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQAECgIJAgAAAA==.',
['Jä']='Jänice:BAAANQAECggJAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgYIEQACAAAAAA==.',
Ka='Kalrock:BAAANQAECgYJEAAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgYJEAACAAAAAA==.Kalulu:BAAANQADCgYIDAAAAA==.Kalyssi:BAAANQADCggIDgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIDgAAAA==.Katkot:BAAANQAECgQJBgAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazzulee:BAAANQADCgEJAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Keres:BAABNQAECoEgAAIPAAkKqCOnBACIAwAPAAkKqCOnBACIAwABNQAECgkJIAAPAKgjAA==.',
Kh='Khagolith:BAAANQAECgYJDgAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.',
Kk='Kkodabear:BAAANQADCggIDwAAAA==.',
Ko='Kobiter:BAAANQAECgUIDAABNQAECggIGgAEAFQgAA==.Kobito:BAABNQAECoEaAAMEAAgKVCAVBADpAgAEAAgKVCAVBADpAgANAAEKZw0z8wA+AAAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECoEfAAMHAAkKXyTpBACXAwAHAAkKXyTpBACXAwAWAAEKfhI7XQA2AAAAAA==.Koupe:BAAANQAECgUICwABNQAECgkJHwAHAF8kAA==.',
Kr='Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQIDwAAAA==.Kriss:BAAANQAECgEIAQAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgkJHwAHAF8kAA==.Kurirne:BAAANQADCgIJAgAAAA==.',
Ky='Kyewanda:BAAANQAECgUIBwAAAA==.Kyusakuu:BAAANQAECgYJDAAAAA==.',
La='Laanu:BAAANQAECgIJAgAAAA==.Lahey:BAABNQAECoEXAAINAAkKJQiAbgDAAQANAAkKJQiAbgDAAQAAAA==.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgMIBAAAAA==.Lavs:BAAANQAECgUICwAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgcIEQAAAA==.Lexiah:BAAANQAECgQIBwAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lizardbrain:BAAANQAECgMIAwAAAQ==.',
Lo='Loamathor:BAAANQADCggIFQAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lorilyn:BAAANQAECgUICwAAAA==.Lorthag:BAAANQAECgYIDgAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQAECgUIBwAAAA==.Lunareclips:BAAANQADCgIIAgAAAA==.Lunarus:BAAANQAECgUJCgAAAA==.',
['Lì']='Lìfe:BAAANQAECgYIEgAAAA==.',
['Ló']='Lónnìe:BAAANQAECgQJCQAAAA==.Lónníe:BAAANQAECgQIBQAAAA==.',
Ma='Macloving:BAAANQADCgYJBgAAAA==.Maelona:BAAANQAECgQIBgAAAA==.Magrumok:BAAANQAECgQIBwAAAA==.Magthars:BAAANQADCgcIDgAAAA==.Magtide:BAAANQAFFAEJAgAAAA==.Malväryx:BAAANQAECgMIAwAAAA==.Manbearpig:BAABNQAECoEeAAIHAAkKciIICQBkAwAHAAkKciIICQBkAwAAAA==.Manman:BAAANQAECgMJBAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgACAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUJBgAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAAANQAECgYIEgAAAA==.Mellindre:BAAANQADCgYJBgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAAANQAECgcIEQAAAA==.Mesa:BAABNQAECoHCAAIXAAgKWSb5AQCPAwAXAAgKWSb5AQCPAwAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECoEYAAMGAAcKBBZ3FAAMAgAGAAcK+RV3FAAMAgAIAAIKBwVcVgBdAAAAAA==.Microplastic:BAAANQAECggJEgAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAAANQAECgYJEQAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQADCggIFgAAAA==.Misosmol:BAAANQAECgEIAQAAAA==.Missogyny:BAAANQAECgYIEgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQADCgcIDwAAAA==.Mogando:BAAANQADCgcICgABNQAECgcJDQACAAAAAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgUIDwACAAAAAA==.Mogrogarg:BAAANQAECgUIDwAAAA==.Mogrosham:BAAANQAECgEJAQAAAA==.Mogrougarg:BAAANQAECgIJAgABNQAECgUIDwACAAAAAA==.Mojojojò:BAAANQADCgIIAgAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgkJHgAYAEoZAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAECggICAAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQADCggJCQAAAA==.Moribelar:BAAANQAECgEIAQAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQAECgQJBQABNQAECgYJDwACAAAAAA==.Morventhas:BAAANQADCgIJAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgUICAAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAAANQAECgUIDwAAAA==.Munusku:BAAANQADCgYJBgAAAA==.',
My='Myboycleetus:BAAANQAECgQJBwAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
Na='Nachobussy:BAAANQAFFAMJAwAAAA==.Nachothings:BAABNQAECoEYAAMZAAkKWxZAFQBzAgAZAAkKWxZAFQBzAgAaAAEKVhloWwBKAAABNQAFFAMJAwACAAAAAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgIJBAAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Nezha:BAAANQAECgEJAQABNQAECggIDAACAAAAAA==.',
Ni='Nightmist:BAAANQADCgcIFwAAAA==.Nihility:BAAANQAECggIDAAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgcJDQACAAAAAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Noodlestang:BAAANQAECgYIEQAAAA==.Nool:BAAANQAECgEIAQAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAAANQAECgcJDQAAAA==.Noriboness:BAAANQAECgQIBAAAAA==.Nosleep:BAABNQAECoEbAAIEAAgKMRg/CQAuAgAEAAgKMRg/CQAuAgAAAA==.Notdumb:BAAANQADCgUJDAAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgEIAQAAAA==.Nyduss:BAAANQAECgIIAwAAAA==.Nymphs:BAAANQADCgEIAQABNQAECgUIDQACAAAAAA==.Nyraxys:BAAANQAECgYIDgAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQADCgcJBwAAAA==.',
Od='Oddzmage:BAAANQAECgQJBAAAAA==.',
On='Onibushi:BAAANQAECgcIEwAAAA==.Onoda:BAAANQABCgEIAQAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECoEZAAIDAAkKJxp6MgD2AgADAAkKJxp6MgD2AgAAAA==.',
Or='Orastal:BAAANQAECgQJBgABNQAECgYIDgACAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oroki:BAAANQADCggIAgAAAA==.Oruun:BAABNQAECoEeAAIFAAgKiyCVFAAJAwAFAAgKiyCVFAAJAwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQJBwAAAA==.Pandadander:BAAANQADCgYIBgABNQAECgQJBwACAAAAAA==.Pandalo:BAAANQADCgUICQAAAA==.Pandalock:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Parasiite:BAAANQAECgYJDwAAAA==.',
Pe='Peepocute:BAAANQAECgQJBwAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQADCggICAAAAA==.Physiowar:BAAANQAECgYIDQAAAA==.',
Pi='Pickledeath:BAAANQAECgQJBgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECoEhAAMXAAgKhCTrBAA3AwAXAAgKhCTrBAA3AwAYAAIKMQr1JgB6AAAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQADCggJDAAAAA==.Preservation:BAAANQAECgcIDgAAAA==.',
Pu='Pugi:BAAANQADCgEIAQAAAA==.Putridstrike:BAAANQAECgEJAQABNQAECgkJLAASAGQjAA==.',
Qt='Qtiy:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.Qtyy:BAAANQAECgUICwAAAA==.',
Ra='Raawwrr:BAAANQADCggIDwAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ramped:BAAANQAECgQIBAAAAA==.Ranzor:BAAANQAECgUICQAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQAECgQICgAAAA==.',
Re='Redjak:BAAANQADCggICAAAAA==.Regino:BAAANQAECgMJCQAAAA==.Reitiado:BAAANQADCgIIAgAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgUIDwACAAAAAA==.Rekita:BAAANQAECgUIDwAAAA==.Remedi:BAAANQAECgUIBQAAAA==.Retaxus:BAAANQABCgEJBAAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAAANQAECgYJDgAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Rn='Rn:BAAANQAECgUJBwAAAA==.',
Ro='Roderika:BAAANQADCgcIDgABNQAECgkJIAAPAKgjAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAAANQAECgUJCwAAAA==.Romanflak:BAAANQADCgYIBgAAAA==.Roostr:BAAANQAECgYIDwAAAA==.Rord:BAAANQAECgUIDwAAAA==.Royjacked:BAAANQADCggIEgAAAA==.',
Ru='Rubberr:BAAANQAECgQIBQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgIIAgAAAA==.Runicstrike:BAABNQAECoEsAAQSAAkKZCMDCwA2AwASAAgKhiQDCwA2AwAPAAYKJhjDQACIAQAOAAUKYBgaOAA1AQAAAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCgYJBgAAAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAACAAAAAA==.Sahra:BAAANQAECgUIEgAAAA==.Sanctustrike:BAAANQAECggIEgABNQAECgkJLAASAGQjAA==.Saraphina:BAAANQAECgMIAwAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.',
Se='Sellandre:BAAANQAECgcJCAAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgcJDQACAAAAAA==.Seronja:BAAANQAECgEIAwAAAA==.Serpompom:BAAANQADCgUJBQAAAA==.',
Sh='Shazzai:BAAANQADCgYIDAAAAA==.Sherfight:BAAANQAECgcIEwAAAA==.Shielddaddy:BAAANQAECgEIAgAAAA==.Shieldsftl:BAAANQAECgIIAgAAAA==.Shiftycent:BAAANQADCgcICgAAAA==.Shnyaga:BAABNQAECoHJAAMTAAgKECVRBgBkAwATAAgKECVRBgBkAwALAAQKmh8XJQCFAQAAAA==.Shockybalboa:BAAANQADCgUJCQAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQABCgMIAwAAAA==.',
Si='Sianda:BAAANQABCgIIAgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQAAAA==.Sinsanityz:BAAANQAECggIBQAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQADCgIIAgAAAA==.',
Sk='Skinwalk:BAAANQAECgMIBQAAAA==.Skrai:BAAANQAECgIJAwAAAA==.',
Sl='Sleew:BAABNQAECoEaAAMbAAgKrxpDNgBFAgAbAAcKBRtDNgBFAgAcAAIKTRGBSQB/AAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sm='Smokintrees:BAAANQADCgUJBwAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIJAgAAAA==.Solnath:BAABNQAECoEaAAIaAAgKDSILCgAhAwAaAAgKDSILCgAhAwAAAA==.Souldaddy:BAAANQADCgQIBAAAAA==.',
Sp='Specsdraco:BAABNQAECoEeAAIWAAgKpyCnDADbAgAWAAgKpyCnDADbAgAAAA==.Spewpuke:BAABNQAECoEVAAMEAAgKGxzIBwBbAgAEAAcKjx7IBwBbAgANAAMKWgj20QCbAAAAAA==.Spicytomato:BAAANQAECgYJDwAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECoEYAAITAAgKPxF7PAD4AQATAAgKPxF7PAD4AQAAAA==.Starstorm:BAAANQADCgQIBAABNQAECggIGgAbAK8aAA==.Stgermain:BAABNQAECoEWAAMTAAgK9B20JwBjAgATAAcK9R20JwBjAgALAAUK9RQOKwBHAQAAAA==.Stormlotus:BAAANQAECgIIAgAAAA==.Stormsorrow:BAAANQAECgIJAgAAAA==.Strikeanywer:BAAANQADCgYICAAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgEJAQAAAA==.',
Sy='Sylrana:BAAANQAECgIIAgAAAA==.Sylri:BAAANQADCgYIBgAAAA==.',
Ta='Taktikil:BAAANQADCgYIDgAAAA==.Talrad:BAAANQAECgQIBgAAAA==.Tazerxface:BAABNQAECoEdAAIQAAkKkRDXOAAOAgAQAAkKkRDXOAAOAgAAAA==.',
Te='Tealgos:BAAANQAECgUIDwAAAA==.Teldrasa:BAAANQAECgQIBAAAAA==.',
Th='Thaiddous:BAAANQAECgYIDQAAAA==.Thanx:BAAANQAECgIIAgAAAA==.Thebeefchief:BAABNQAECoEZAAIRAAkKKiLdAQBuAwARAAkKKiLdAQBuAwAAAA==.Thebigmon:BAAANQAECgYJEgAAAA==.Thedabara:BAAANQADCgMIAwAAAA==.Thedon:BAAANQAECgIJAgAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQADCgUIBQAAAA==.Thrudheals:BAAANQAECgUIDAABNQAECgYIBgACAAAAAA==.Thrudtotems:BAAANQAECgYIBgAAAA==.Thugnastie:BAAANQAECgUIDAAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAAANQAECgMJAwAAAA==.Timeisdruid:BAAANQAECgEIAQAAAA==.Tinytina:BAAANQAECgUIBQAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgQIBwAAAA==.Togashi:BAABNQAECoEXAAIdAAcKiyGdDAC1AgAdAAcKiyGdDAC1AgAAAA==.Topacio:BAAANQADCggIEwAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAMJAwACAAAAAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQAECgQIBwAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECgYIDAAAAA==.Tricep:BAAANQADCgcIDAAAAA==.Tripallie:BAAANQADCgQJCQAAAA==.Trishian:BAAANQADCgQIBgAAAA==.Trunkmuffin:BAAANQAECgEJAQAAAA==.Truthless:BAEBNQAECoEcAAIVAAkKFBpZEwDxAgAVAAkKFBpZEwDxAgAAAA==.',
Tu='Tuckermax:BAAANQADCgYICwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAAANQAECgYJDQAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECggIIQAXAIQkAA==.',
Ug='Uglyashell:BAAANQADCgUICAAAAA==.',
Un='Unit:BAABNQAECoETAAIeAAcKLx3sCgBhAgAeAAcKLx3sCgBhAgAAAA==.',
Uv='Uva:BAAANQAECgEJAQAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECoEWAAIfAAgKORP0AwA7AgAfAAgKORP0AwA7AgAAAA==.Valsorin:BAAANQAECgEJAQAAAA==.Valtaea:BAABNQAECoEYAAIDAAgKGgxslQDiAQADAAgKGgxslQDiAQAAAA==.',
Vi='Vishas:BAAANQADCgMJAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgMJBAACAAAAAA==.Voidwaffle:BAAANQADCgYIBgAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAQABNQAECgQJBgACAAAAAA==.',
Wa='Wafflxs:BAABNQAECoEdAAIKAAkKtyRvAQCYAwAKAAkKtyRvAQCYAwAAAA==.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAAANQAECgYIEQAAAA==.Warglave:BAAANQAECgIIAgAAAA==.Warmo:BAAANQADCggICAAAAA==.Warunk:BAAANQAECgQIBAAAAA==.',
Wc='Wcldragon:BAAANQADCgEJAQAAAA==.',
We='Weiwu:BAABNQAECoEiAAIdAAgKWB5NDQCpAgAdAAgKWB5NDQCpAgAAAA==.Wellfookthat:BAABNQAECoEaAAIQAAgKeRwGHwCaAgAQAAgKeRwGHwCaAgAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECggIGgAQAHkcAA==.Weolf:BAAANQABCgIIAwAAAA==.',
Wh='Whiteshadows:BAAANQAECgUICQAAAA==.Whyvala:BAAANQADCgcIGgABNQADCgcIBwACAAAAAA==.Whyvara:BAAANQADCgcIBwAAAA==.',
Wi='Wiisp:BAAANQAECgQICAAAAA==.',
Wo='Wolnney:BAABNQAECoEZAAIMAAgKbiNSHAABAwAMAAgKbiNSHAABAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQJBAAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgYICwAAAA==.',
Xa='Xalatoes:BAACNQAFFIEJAAIQAAUKgxxLAwDVAQAQAAUKgxxLAwDVAQA1AAQKgSAAAhAACQraIGANACADABAACQraIGANACADAAAA.Xanathar:BAAANQADCgYJCAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQADCgQIBAAAAA==.',
Xi='Xionglieren:BAAANQABCgEIAQAAAA==.Xiren:BAAANQABCgIJBQAAAA==.',
Xr='Xraiz:BAAANQADCggIGgAAAA==.',
Xy='Xyne:BAAANQADCggJEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAABNQAECoEpAAIKAAkKEyOXAQCTAwAKAAkKEyOXAQCTAwAAAA==.Yourboyblue:BAAANQADCgYIEAAAAA==.',
Yv='Yverrius:BAAANQADCgMIBgAAAA==.',
Za='Zanydruid:BAAANQADCgQICAAAAA==.Zanza:BAAANQAECgMIBAAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggIDAAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.',
Zh='Zhamazu:BAAANQADCgQJBQAAAA==.Zhayden:BAAANQAECgUICQAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQADCgcIDAABNQAECgQIBgACAAAAAA==.Zombiez:BAABNQAECoEOAAISAAYKFAknTwBEAQASAAYKFAknTwBEAQAAAA==.Zoryn:BAAANQADCgcIEAABNQADCgEIAQACAAAAAA==.',
['Él']='Élowen:BAAANQAECgEIAQAAAA==.',
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
