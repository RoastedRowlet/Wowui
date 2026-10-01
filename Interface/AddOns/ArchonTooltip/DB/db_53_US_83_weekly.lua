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

local lookup = {'Mage-Arcane','Druid-Restoration','Unknown-Unknown','Hunter-Marksmanship','Druid-Guardian','Hunter-BeastMastery','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Balance','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Warrior-Arms','Warrior-Protection','Warrior-Fury','Priest-Shadow','Priest-Discipline','Paladin-Protection','DeathKnight-Unholy','DemonHunter-Havoc','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abrothael:BAAANQAECgYICwAAAA==.',
Ad='Adorèè:BAAANQAECgUIDQAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aestua:BAAANQADCgQICQAAAA==.Aetheros:BAABNQAECoEoAAIBAAkKMBzkNQABAwABAAkKMBzkNQABAwAAAA==.',
Ag='Agarim:BAAANQADCgQICAAAAA==.',
Ai='Airlinna:BAABNQAECoEjAAICAAgKExoJFABkAgACAAgKExoJFABkAgAAAA==.Airoach:BAAANQAECgEIAQAAAA==.',
Ak='Akers:BAAANQADCggICwABNQAECgUICwADAAAAAA==.',
Al='Alaraen:BAAANQAECgUIDwAAAA==.Alcremie:BAAANQAECgIIAwABNQAFFAYIEQAEALogAA==.Aleman:BAAANQADCgYIEAAAAA==.Aleve:BAAANQADCgIIAgAAAA==.Alexxandria:BAAANQADCggJCwAAAA==.Aleyah:BAAANQAECgUJBQAAAA==.Almarii:BAAANQAECgUIDgAAAA==.Alraune:BAABNQAECoEcAAIFAAgKfyBPBQDxAgAFAAgKfyBPBQDxAgAAAA==.Alynndra:BAAANQAECgUIDgAAAA==.Alyssazoe:BAAANQADCgIIBAAAAA==.',
Am='Ambler:BAAANQADCgcIFAAAAA==.',
An='Anarionhunts:BAAANQAECgUIDAAAAA==.Andius:BAAANQADCggIIgAAAA==.Andoric:BAAANQABCgYICAAAAA==.Anirra:BAAANQAECgUIDgAAAA==.Annaraeliri:BAAANQADCggICwAAAA==.',
Ap='Apert:BAAANQAECgYIEAAAAA==.Apnea:BAAANQADCgIIAgAAAA==.Appa:BAAANQADCgUICQAAAA==.',
Ar='Ardenweald:BAABNQAECoEmAAMCAAgKRR0GEQCOAgACAAgKRR0GEQCOAgAFAAcKzRByFgB7AQAAAA==.Armyokittens:BAAANQADCggIIwAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgQICAAAAA==.',
As='Ashaleth:BAAANQADCgUIBQAAAA==.Ashayo:BAAANQADCggJEQAAAA==.Asphodel:BAAANQABCgQIBQAAAA==.Astrana:BAABNQAECoEaAAIGAAcK6A+RdQDIAQAGAAcK6A+RdQDIAQAAAA==.',
At='Athelstan:BAAANQADCgcIBwAAAA==.',
Au='Augkward:BAAANQAECgMIAwABNQAFFAUICwAHAMsYAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAABNQAECoEeAAMIAAkKNxtuCgAGAwAIAAkKBhtuCgAGAwAJAAMKphzYMAD6AAAAAA==.Autoshot:BAAANQADCgMIBAAAAA==.',
Av='Avorek:BAAANQADCgYICwAAAA==.Avorik:BAAANQAECgUICQAAAA==.Avouric:BAAANQAECgEIAQAAAA==.',
Az='Azaree:BAAANQAECgQJCgAAAA==.Azndak:BAAANQADCgcJBwAAAA==.',
Ba='Baelzabob:BAAANQADCgYIHQAAAA==.Bakaran:BAAANQADCgUJBQAAAA==.Barae:BAAANQAECgEIAQAAAA==.Barboosa:BAAANQAECgEIAQAAAA==.Barcmaul:BAAANQAECgQIBAAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQAECgUICgAAAA==.',
Bb='Bbqmonk:BAAANQADCggICAABNQAECgUICQADAAAAAA==.',
Be='Bearbq:BAAANQAECgUICQAAAA==.Belledolphin:BAAANQAECgcIDQAAAA==.Bellgold:BAAANQADCgYIBgABNQAECgUIDgADAAAAAA==.Berigo:BAABNQAECoEXAAMCAAgKmhDHHQDqAQACAAgKmhDHHQDqAQAKAAEKcgLlowAbAAAAAA==.Bertoxulous:BAAANQADCggIBQAAAA==.Bezvoker:BAAANQAECgYIDgAAAA==.Beárwithme:BAAANQADCgQICAAAAA==.',
Bi='Birria:BAAANQADCgQIBAABNQADCgYIEAADAAAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackhoofcow:BAAANQAECgEIAgAAAA==.Blackicewolf:BAABNQAECoEeAAILAAgKnyK3BQAMAwALAAgKnyK3BQAMAwAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQADCgYIBgAAAA==.Blueberrypie:BAAANQAECgUICAAAAA==.',
Bo='Bonbarrion:BAEBNQAECoEjAAQMAAgKHRxxOwA/AgAMAAcKvhpxOwA/AgANAAYKhAwJfgA7AQALAAIK5RRhIwCgAAAAAA==.Borbory:BAAANQAECgUIDgAAAA==.Boringhuman:BAAANQAECgQIBgAAAA==.Borlorín:BAAANQADCgYIBgAAAA==.Borogove:BAAANQADCgYJDAAAAA==.',
Br='Brasca:BAAANQAECgYIEAAAAA==.Brisketdk:BAAANQAECgIIAgABNQAECgUICQADAAAAAA==.Bruhmal:BAAANQAECgUJCQAAAA==.Brunner:BAAANQADCgEIAQAAAA==.Brynndolin:BAAANQAECgYIEAAAAA==.',
Bu='Burzolog:BAABNQAECoEhAAIJAAgKmBGuFQATAgAJAAgKmBGuFQATAgAAAA==.',
['Bä']='Bärk:BAABNQAECoFAAAMKAAkK1xqxGQDMAgAKAAkK1xqxGQDMAgACAAQKcBPyNQACAQAAAA==.',
Ca='Calanash:BAAANQADCgcIBwABNQAECgcIEgADAAAAAA==.Calazan:BAAANQAECgcIEgAAAA==.Calethron:BAAANQADCgUIBQAAAA==.Calliel:BAAANQADCgcIBwAAAA==.Cascious:BAAANQADCggIDwABNQAFFAQICQACAD4NAA==.Casylla:BAAANQADCgMJAwAAAA==.Cazym:BAAANQADCggICAABNQAECggIBgADAAAAAA==.',
Ce='Cedarjr:BAAANQAECgMIBAAAAA==.Cef:BAAANQAECgUIDgAAAA==.Celindre:BAAANQAECgIIAgAAAA==.',
Ch='Cherrybomb:BAAANQADCgIIAgAAAA==.Chewbie:BAAANQAECgEIAQAAAA==.Chickentendi:BAAANQADCgQIBAABNQAECgUIDwADAAAAAA==.Choonjung:BAAANQAECggIBwAAAA==.Chronis:BAAANQAECgEIAQAAAA==.',
Ci='Ciphon:BAAANQAECgIIAgAAAA==.Cirok:BAAANQADCgcIDQAAAA==.Civic:BAAANQAECgUICQAAAA==.',
Ck='Cklyde:BAABNQAECoEiAAIOAAkKiR/QDQA6AwAOAAkKiR/QDQA6AwAAAA==.',
Cl='Claiyre:BAAANQAECgQIBgABNQAECgQIBgADAAAAAA==.Clewis:BAAANQABCgUICAAAAA==.Clubble:BAAANQAECgMJBAAAAA==.Clumperton:BAABNQAECoEbAAIGAAkKax/sGgD6AgAGAAkKax/sGgD6AgAAAA==.Clãsh:BAAANQAECgIIBAAAAA==.',
Co='Cochino:BAAANQAECggIDQAAAA==.Concentrate:BAAANQAECgcIEQAAAQ==.Connan:BAAANQAECgUICQABNQAECggIGwANAP4kAA==.Constant:BAAANQADCggIGQAAAA==.Corbesan:BAAANQADCgcIBwABNQAECgUICAADAAAAAA==.Cordrann:BAAANQADCggIIgAAAA==.Coveness:BAAANQADCgMIAwAAAA==.Cowi:BAABNQAECoElAAINAAkKYh63FgDsAgANAAkKYh63FgDsAgAAAA==.',
Cr='Crasusakechi:BAAANQAECgQIBgAAAA==.Crisisangel:BAAANQADCggIAgAAAA==.Crossnover:BAAANQADCgYIBgABNQAECggIIQAGAKUVAA==.Cryomagus:BAABNQAECoEiAAMPAAgK0xcDJgAIAgAPAAgK0xcDJgAIAgAQAAEKMw+mrQAwAAAAAA==.',
Cu='Cuqquiform:BAABNQAECoEeAAMCAAgKyiNCDQDEAgACAAcKHSRCDQDEAgAKAAYKsB2sMwD+AQAAAA==.',
Cy='Cylesia:BAAANQADCggIHAAAAA==.Cylthia:BAAANQADCgcICgAAAA==.Cyrienna:BAAANQADCgYICQAAAA==.',
Da='Daemata:BAAANQAECgEIAgAAAA==.Dajinbo:BAAANQAECgQIBQAAAA==.Dalarium:BAAANQADCgYIBgAAAA==.Damons:BAAANQAECgMIAwABNQAECgkJGQAKAHYbAA==.Dankinia:BAAANQADCgUICQAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQAECgYICgAAAA==.Darkswift:BAABNQAECoEnAAIRAAkKQiLOGAA6AwARAAkKQiLOGAA6AwAAAA==.Darnadda:BAAANQAECgIIAgAAAA==.Darowyn:BAAANQAECgUIDgAAAA==.Dashiell:BAAANQAECgUICAAAAA==.Dawnflare:BAAANQAECgEIAQABNQAECgcIFAANAJARAA==.',
De='Deafdog:BAAANQADCgcIBwAAAA==.Deathryder:BAAANQADCggICAAAAA==.Deaxus:BAAANQAECgMIBQABNQAECggIIwASAL0OAA==.Deb:BAAANQAECgUIDgAAAA==.Defacer:BAAANQABCgYIBgAAAA==.Defame:BAAANQADCgEIAQABNQAECgUIDgADAAAAAA==.Delailia:BAAANQADCggIFgAAAA==.Delbelfine:BAABNQAECoEoAAIOAAkKDRP/NgBMAgAOAAkKDRP/NgBMAgAAAA==.Delfar:BAAANQADCgUIBQAAAA==.Delimeats:BAAANQADCgQIBAAAAA==.Delisomethng:BAAANQAECgUIEAAAAA==.Dellechero:BAAANQAECgYIBgAAAA==.Demilich:BAAANQAECgIIAgAAAA==.Demonra:BAAANQADCgMIAwAAAA==.Despaira:BAAANQAECgUIDAAAAA==.Dethyler:BAAANQAECgUIDgAAAA==.Devilwoman:BAAANQAECgUICQAAAA==.Deyv:BAAANQAECgUIDgAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAYIEQAEALogAA==.Diddibeau:BAAANQAECgUIDgAAAA==.Diddiblind:BAAANQADCgMIBgABNQAECgUIDgADAAAAAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAFFAIIAwABNQAFFAYICwACAIIWAA==.',
Do='Dontyagnomie:BAAANQAECgYIDAAAAA==.Doobu:BAAANQADCgcJFwAAAA==.Dooganitis:BAAANQAECgQICQAAAA==.Dorne:BAAANQADCggIDwAAAA==.Doruk:BAAANQAECgQIBAAAAA==.',
Dr='Dreamsoul:BAAANQABCgQIBQAAAA==.Drfeelgreat:BAAANQADCgIIAwAAAA==.',
Du='Dullahstrasz:BAAANQADCgYIBgAAAA==.Dusksorrow:BAAANQADCgUIBQAAAA==.',
Dz='Dzud:BAAANQADCgUIBQAAAA==.',
Ed='Edovard:BAAANQAECgEIAQAAAA==.',
Ee='Ee:BAAANQADCgcIDAABNQAECgEIAQADAAAAAA==.Eeragon:BAAANQAECgMIAwAAAA==.',
Ef='Efitzherbert:BAAANQAECgUIBQAAAA==.',
El='Elentari:BAAANQABCgMIAwAAAA==.Elfshadow:BAAANQABCgQIAwAAAA==.Eliyon:BAAANQAECgQIBAAAAA==.Ellarinya:BAAANQADCgUICgAAAA==.Ellemir:BAAANQADCgcIIQAAAA==.Elshifty:BAAANQADCgcIBwABNQAECggIAQADAAAAAA==.Eltanari:BAAANQAECgEIAQAAAA==.Eluera:BAAANQAECggIDgAAAA==.Elyn:BAAANQAECgcIEQABNQAFFAIIAwADAAAAAA==.Elynthil:BAAANQAFFAIIAwAAAA==.',
Em='Emet:BAAANQABCgIIAgAAAA==.Emilie:BAAANQAECgEIAgAAAA==.Emunny:BAAANQAECgYIEAAAAA==.',
En='Endest:BAAANQAECgUIDgAAAA==.Enezalle:BAAANQAECgUIDgAAAA==.',
Eo='Eointhas:BAAANQAECgYIEAAAAA==.',
Ep='Ephimonk:BAAANQAECgUIDQAAAA==.',
Er='Erenyeagar:BAAANQADCgYIDAAAAA==.Ernson:BAAANQADCgUJDQAAAA==.',
Eu='Euronymous:BAAANQAECgQIBwAAAA==.',
Ev='Evilandy:BAAANQAECgUICgAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.Fandrall:BAAANQADCgQIBgAAAA==.',
Fb='Fblthp:BAAANQAECgUICwAAAA==.',
Fe='Felblood:BAAANQADCggIGwAAAA==.Ferndolyn:BAAANQADCgMIAwAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAAANQAECgUIDAAAAA==.',
Fl='Flagonslayer:BAAANQAECgIJAgAAAA==.Flaimefu:BAAANQAECgEIAQAAAA==.Floopt:BAAANQAECgQIBAAAAA==.Floorlicker:BAAANQADCgYIBgAAAA==.Flopsie:BAAANQAECgcIEwAAAA==.Fluffystorm:BAAANQADCggIIgAAAA==.',
Fo='Forzod:BAAANQADCggIEwAAAA==.Forzzie:BAAANQADCgYICQAAAA==.Foxheals:BAAANQADCgcIBwAAAA==.Foxymagic:BAAANQAECgQIBgAAAA==.',
Fr='Frabjous:BAAANQAECgYIEAAAAA==.Freenk:BAAANQADCgcIEQAAAA==.Freezerburn:BAABNQAECoEnAAMBAAkK1xSTiwAoAgABAAgKxhSTiwAoAgATAAIKZhDeJQB6AAAAAA==.Frogstomper:BAAANQADCgEJAQAAAA==.',
Fu='Furn:BAAANQAECgYIEAAAAA==.Furryaz:BAAANQAECgQIBwAAAA==.Further:BAABNQAECoEnAAIUAAkK8yRABgCzAwAUAAkK8yRABgCzAwAAAA==.',
Fy='Fyrrek:BAAANQADCgYIDQAAAA==.',
Ga='Galadrien:BAAANQADCgYJBgAAAA==.Galavenat:BAAANQAECgUIDgAAAA==.Galroy:BAAANQADCgEIAQAAAA==.Galstan:BAAANQADCgUJCAAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbolicious:BAAANQADCgcIBwAAAA==.Garbothicc:BAAANQAECgUIDgAAAA==.Garyh:BAACNQAFFIEaAAIUAAcKISW/AADxAgAUAAcKISW/AADxAgA1AAQKgSoAAhQACQrPJnkBAO4DABQACQrPJnkBAO4DAAAA.Garyhreturns:BAAANQAECgUIBgABNQAFFAcIGgAUACElAA==.',
Ge='Geldeinmonch:BAAANQADCgYIBwABNQAECgUIDQADAAAAAA==.Geldklerk:BAAANQADCgYIDAABNQAECgUIDQADAAAAAA==.Geldverdamnt:BAAANQAECgUIDQAAAA==.Gerasham:BAAANQADCgcIBwAAAA==.',
Gh='Ghost:BAAANQABCgQIBgAAAA==.Ghuramonk:BAAANQADCggICgAAAA==.',
Gi='Giacomo:BAAANQAECgIIAgAAAA==.Gil:BAAANQAECgQJBgAAAA==.Gildina:BAAANQAECgIIAgAAAA==.Ginggy:BAAANQAECgYIEgABNQAFFAQICQACAD4NAA==.Girafficz:BAABNQAECoEhAAIKAAkK3CXqAwCxAwAKAAkK3CXqAwCxAwABNQAFFAcIIAAUAOMkAA==.',
Go='Gobb:BAAANQAECgUIBQAAAA==.Gori:BAABNQAECoEbAAMVAAkKdBleCQBkAgAVAAgKzhpeCQBkAgAWAAMK0AvUGwCVAAAAAA==.Gorin:BAAANQADCggIDAABNQAECgUICAADAAAAAA==.',
Gr='Graelle:BAAANQADCgYIBgAAAA==.Gralle:BAAANQAECgQICAAAAA==.Graug:BAAANQAECgMIAwABNQAECgQICAADAAAAAA==.Gravehart:BAAANQADCggIEAABNQAECgUICwADAAAAAA==.Gravelbeard:BAAANQADCgIIBAAAAA==.Gregory:BAABNQAECoEbAAIBAAgKXxPajgAhAgABAAgKXxPajgAhAgABNQAECgQICAADAAAAAA==.Greyantheril:BAAANQAECgUIDgAAAA==.Greyji:BAABNQAECoEeAAIGAAgKXw7jYAAAAgAGAAgKXw7jYAAAAgAAAA==.Grumb:BAABNQAECoEoAAIMAAkKqhcNKwCVAgAMAAkKqhcNKwCVAgAAAA==.',
Gu='Guenara:BAAANQAECgUIBwAAAQ==.Guillimon:BAAANQADCgQIBAABNQAECggIHQAXACgQAA==.Gustytail:BAAANQAECgUICQAAAA==.',
Ha='Haardrada:BAAANQAECgUIDQABNQAFFAcIGgAUACElAA==.Habit:BAABNQAECoEbAAIGAAgKuxbBPgBnAgAGAAgKuxbBPgBnAgAAAA==.Hadrianna:BAAANQAECgUICgAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAAANQAECgUIDgAAAA==.Hapless:BAAANQAECgQICQAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.Hawkfoot:BAAANQAECgQIBgAAAA==.',
He='Hearthbreakr:BAAANQAECgIIBAABNQAECgkJKgAMAIEaAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAABNQAECoEUAAIFAAYKXw3OHgAcAQAFAAYKXw3OHgAcAQAAAA==.Hellchi:BAAANQAECgUIDQAAAA==.Hellinasel:BAAANQAECgQICAAAAA==.Hemmy:BAABNQAECoEjAAIOAAkKxiYVAAAJBAAOAAkKxiYVAAAJBAAAAA==.Hermer:BAAANQADCgMIAwAAAA==.Heysham:BAAANQAECgUJCQAAAA==.Hezzakan:BAAANQAECgIIAgAAAA==.',
Ho='Holycef:BAAANQAECgQIBAABNQAECgUIDgADAAAAAA==.Holychild:BAAANQADCgYIBgAAAA==.Holykow:BAAANQAECgYIDgAAAA==.Hotspur:BAAANQAECgYIEAAAAA==.Howlua:BAAANQADCgQJBAAAAA==.',
Hu='Huevomuerto:BAAANQADCgQICAAAAA==.Huevonyque:BAABNQAECoEqAAIUAAkK7R+ZIQAOAwAUAAkK7R+ZIQAOAwAAAA==.Huntsthewind:BAAANQADCgUICQAAAA==.Huulgrim:BAAANQAECgUIDgABNQABCgMIAwADAAAAAA==.',
Hy='Hyejinx:BAAANQAECgUIBwAAAA==.',
Ic='Iceclaw:BAAANQADCgQIBAABNQADCgUIEwADAAAAAA==.Icona:BAAANQADCgQIBAAAAA==.',
Ih='Ihiannan:BAAANQADCggIIgABNQAECgYIEAADAAAAAA==.',
Ii='Iiarian:BAAANQAECgYIDgAAAA==.',
Il='Ilivarra:BAAANQAECgQJBAAAAA==.Illisong:BAAANQAECgUIBQAAAA==.Illukana:BAABNQAECoEjAAIHAAkKqB8DDQA1AwAHAAkKqB8DDQA1AwABNQAFFAQICgARALYbAA==.',
In='Infoxy:BAAANQAECgUJCAAAAA==.Inthra:BAAANQAECgIIAwAAAA==.',
Ir='Irimas:BAAANQADCggJFwAAAA==.',
Is='Isopope:BAAANQAECgYIBgAAAA==.Isthian:BAAANQAECgUIDQAAAA==.',
It='Itako:BAAANQADCggIIAAAAA==.Itoldhimso:BAAANQAECgMIBAAAAA==.',
Iv='Ivaldi:BAAANQADCgQIBwAAAA==.',
Ja='Jadelark:BAAANQAECgYIDgAAAA==.Javèrt:BAABNQAECoEjAAIQAAgKDRiWLAApAgAQAAgKDRiWLAApAgAAAA==.Jaxina:BAAANQAECgEIAQABNQAECgcIGQASAJsaAA==.Jaxordamus:BAABNQAECoEZAAISAAcKmxqCUgATAgASAAcKmxqCUgATAgAAAA==.',
Je='Jekle:BAAANQADCgQIBwAAAA==.Jema:BAAANQAECgQIBgAAAA==.Jenilea:BAAANQAECgYIEAAAAA==.Jessaril:BAAANQAECgYIEQAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAABNQAECoEhAAIMAAgK2h7tIgDEAgAMAAgK2h7tIgDEAgAAAA==.Jinsu:BAAANQAECgEIAQAAAA==.Jinzeem:BAAANQADCggIJQABNQAECgIIAgADAAAAAA==.Jiujitsunut:BAAANQADCgIIBAAAAA==.',
Jo='Jordend:BAAANQAECgEIAwAAAA==.Joseppii:BAAANQAECgQIDgAAAA==.',
Jp='Jpxfrd:BAAANQABCgUJCgABNQADCgYIEAADAAAAAA==.',
Ju='Jungyuul:BAAANQAECgUICwAAAA==.Junkhar:BAAANQABCgEIAQAAAA==.Junpimaeus:BAAANQAECgIIAgAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAAANQAECgUIDgAAAA==.Jâzzý:BAAANQADCggICgABNQAECgUIDgADAAAAAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQAECgIIAgAAAA==.Kailann:BAAANQAECgMIAwAAAA==.Kanji:BAAANQADCgcJDQAAAA==.Kaorin:BAAANQAECgEIAQAAAA==.Karesta:BAAANQAECgEIAQAAAA==.Kaylith:BAAANQAECgEIAQAAAA==.Kayra:BAAANQADCgcIDQAAAA==.',
Ke='Kegelsmash:BAAANQADCgMJAwABNQAECggIIAAFAG8lAA==.Kelanansi:BAAANQAECgEIAQAAAA==.Kelanis:BAAANQADCgYIBgAAAA==.Kelel:BAABNQAECoEXAAMHAAcKSxcSSgD1AQAHAAcKSxcSSgD1AQAYAAEK/wxIIwAxAAAAAA==.Kelessa:BAAANQADCgUIBQAAAA==.Kessia:BAAANQADCggIHQAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAAANQAECgUICgAAAA==.',
Ki='Kiroblade:BAAANQADCgcIDAABNQAECggIHQAGAFkWAA==.Kiropaly:BAAANQAECgQIBAABNQAECggIHQAGAFkWAA==.Kirotard:BAABNQAECoEdAAIGAAgKWRb1RwBJAgAGAAgKWRb1RwBJAgAAAA==.Kisldarin:BAAANQADCgUJBQAAAA==.Kithedrael:BAAANQAECgEJAQAAAA==.',
Kl='Klouded:BAAANQAECgYIBgAAAA==.',
Kn='Knuts:BAAANQADCgYICwABNQAECggIIgAGALIlAA==.',
Ko='Koa:BAAANQAECgUICQAAAA==.Kojakk:BAAANQAECgYIEAAAAA==.Kordac:BAAANQAECgUIDgAAAA==.Korigan:BAAANQAECgUIDAAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCggICwAAAA==.',
Ku='Kulluast:BAAANQADCgIIAgAAAA==.Kunamashiro:BAAANQAECgIIAwAAAA==.',
Ky='Kylê:BAAANQAECgEIAQAAAA==.Kymetra:BAAANQAECgUIDgAAAA==.Kyttin:BAAANQADCggIIgAAAA==.',
['Kä']='Kära:BAAANQAECgQIBAABNQAECggIGwANAP4kAA==.',
['Kÿ']='Kÿthe:BAAANQABCgYICQAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQAECgIIAgAAAA==.Lalena:BAAANQAECgUIBwAAAA==.Lawanda:BAAANQADCgEIAQABNQAECgUIDgADAAAAAA==.',
Le='Leonineone:BAABNQAECoEoAAIXAAkKyhz2CgANAwAXAAkKyhz2CgANAwAAAA==.Ler:BAAANQADCgYIBgABNQADCggIHQADAAAAAA==.',
Li='Lichplease:BAABNQAECoEmAAIPAAkKgSOGCQAqAwAPAAkKgSOGCQAqAwAAAA==.Light:BAAANQAECggIEAAAAA==.Lightlady:BAAANQAECgIIAgAAAA==.Lightridge:BAAANQABCgUICQAAAA==.Lightweight:BAAANQAECgQIBAAAAA==.Lillythorne:BAAANQAECgUICgAAAA==.Limewire:BAAANQAECgQIBAAAAA==.Lindsay:BAAANQADCgUIBQABNQAECgUIDgADAAAAAA==.Litehlzonly:BAAANQAECgQICAAAAA==.Literalcow:BAAANQABCgUJBQAAAA==.Livebeef:BAAANQADCgUIDwAAAA==.',
Lm='Lmaolock:BAAANQADCgEIAQAAAA==.',
Lo='Lohvadner:BAAANQADCggIGAAAAA==.Lothlum:BAAANQAECgQICAABNQAECgUICAADAAAAAA==.',
Lu='Lunacie:BAAANQADCgUICQAAAA==.Lunalia:BAAANQAECgEIAwAAAA==.Lupen:BAAANQAECgQIBgAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ly='Lynlin:BAAANQAECgMJBAAAAA==.Lynwalker:BAAANQAECgQIBAAAAA==.',
Ma='Magesef:BAAANQAECgUIDQAAAA==.Magnusrn:BAAANQADCgUIEwAAAA==.Makinmemoist:BAAANQAECgIIAgAAAA==.Malandras:BAAANQADCgEIAQAAAA==.Malandrius:BAAANQADCggIIgAAAA==.Malehei:BAAANQADCgMIAwAAAA==.Malemental:BAAANQADCggICAAAAA==.Malignities:BAAANQAECgYJEAAAAA==.Malthruin:BAAANQAECgEIAQABNQAECggIIwASAL0OAA==.Manajamba:BAAANQAECgUIDQAAAA==.Manamidget:BAAANQADCgUICQAAAA==.Mancubus:BAABNQAECoEeAAIRAAgKNx9OLADbAgARAAgKNx9OLADbAgAAAA==.Marosenth:BAAANQADCggIEwAAAA==.Marqadin:BAAANQADCgIIBAAAAA==.Maxidorf:BAAANQADCggIDgAAAA==.',
Me='Meleeno:BAAANQADCgIIBAAAAA==.Meush:BAACNQAFFIEKAAIRAAQKthsMCABoAQARAAQKthsMCABoAQA1AAQKgS4AAhEACQqxIpkdACADABEACQqxIpkdACADAAAA.Mewkow:BAAANQADCggIJQAAAA==.Mewsa:BAAANQAECgUIDwAAAA==.',
Mi='Micha:BAAANQADCgcIDAAAAA==.Midgee:BAAANQAECgEIAQAAAA==.Minidorf:BAAANQAECgIIAgAAAA==.Minimigraine:BAAANQAECgQIBgAAAA==.Miniroar:BAAANQADCgMIAwAAAA==.Miphisto:BAAANQADCggIHwAAAA==.Mirandee:BAAANQAECgEIAgAAAA==.Mishrani:BAAANQADCggIFgAAAA==.Mite:BAAANQADCggICgAAAA==.',
Mo='Moa:BAAANQADCggIIQAAAA==.Molding:BAAANQAECgYIEAAAAA==.Mollusk:BAAANQADCgUIEAAAAA==.Monis:BAABNQAECoEeAAIUAAgKAglqjQCfAQAUAAgKAglqjQCfAQAAAA==.Montessarah:BAAANQADCgcIGgAAAA==.Moonstôrm:BAAANQADCgYJBgAAAA==.Mootalica:BAAANQADCgQIBAAAAA==.Mordraug:BAAANQADCggIGwAAAA==.Morinoe:BAAANQAECgUIDgAAAA==.Mornwalker:BAAANQAECgUIDgAAAA==.',
Mu='Mudelf:BAAANQADCgYIDAAAAA==.Mumra:BAAANQAECgYIEQABNQAECggIHgACAMojAA==.',
My='Mysticc:BAAANQADCggIGgAAAA==.Myxii:BAAANQAECgIIAgABNQAECgUICQADAAAAAA==.',
['Mà']='Màdrigal:BAAANQADCggIJAAAAA==.',
['Mí']='Míckey:BAAANQAECgUIDgAAAA==.',
['Mÿ']='Mÿthunn:BAAANQAECgYIDQAAAA==.',
Na='Nadia:BAAANQADCgcIBwAAAA==.Nagratz:BAAANQAECgUIDgAAAA==.Naichingeru:BAAANQADCggIIgAAAA==.Nalu:BAAANQADCggIDgAAAA==.Napalmo:BAAANQADCgUICgAAAA==.Naterra:BAABNQAECoEUAAMNAAcKkBExXACmAQANAAcKkBExXACmAQAMAAQK1wZsvQC7AAAAAA==.Nazzgul:BAAANQABCgEIAQAAAA==.',
Ne='Necessities:BAAANQAECgUICAAAAA==.Necrill:BAAANQAECgcIEQAAAA==.Neirwind:BAAANQADCggIEAAAAA==.',
Ni='Nichiwa:BAAANQAECgMIAwAAAA==.Niladros:BAAANQADCgcICwAAAA==.Nirazend:BAAANQADCgUIDwAAAA==.Nisaam:BAAANQADCgUIDwAAAA==.Niteterror:BAAANQAECgUIBwAAAA==.',
Nl='Nloc:BAAANQADCgYIDAAAAA==.Nlok:BAAANQADCgcICwAAAA==.',
No='Nolmac:BAAANQAECgIIAgAAAA==.Nomesacan:BAAANQAECgQIBAAAAA==.Nosleep:BAAANQADCggIIgAAAA==.Novelia:BAAANQADCgIIAgAAAA==.',
Nu='Nuglife:BAAANQADCgYICwAAAA==.',
['Nà']='Nàtureuscary:BAAANQAECgQIBQAAAA==.',
Ob='Obtusepanda:BAAANQAECgUIDwAAAA==.',
Oc='Ocupocorrer:BAAANQAECgQIBAAAAA==.',
Of='Offthechaeni:BAAANQAECgEIAQAAAA==.',
Og='Ograndoe:BAABNQAECoEhAAIZAAgKURyoDwBWAgAZAAgKURyoDwBWAgAAAA==.',
Oh='Ohanzee:BAAANQADCgcIDgAAAA==.Ohku:BAAANQADCggIIwAAAA==.Ohok:BAAANQAECgUIDgAAAA==.',
Oi='Oisin:BAAANQAECgIIAgAAAA==.',
Ol='Olomin:BAAANQAECgQIBwAAAA==.',
Om='Omathra:BAABNQAECoEjAAISAAgKvQ73YQDiAQASAAgKvQ73YQDiAQAAAA==.',
On='Onikai:BAAANQAECgQIAgAAAA==.Onruk:BAAANQAECgQIDAAAAA==.',
Op='Ophina:BAAANQAECgUICwAAAA==.',
Or='Oreo:BAAANQAECgQIBAAAAA==.Orgish:BAAANQAECgIIAgABNQAECgQICQADAAAAAA==.Orieda:BAAANQADCgUIBQAAAA==.Orihime:BAAANQADCgYIBgAAAA==.',
Os='Osage:BAABNQAECoEiAAIUAAkKBiM0CgCSAwAUAAkKBiM0CgCSAwAAAA==.',
Ox='Oxidising:BAABNQAECoEZAAIMAAgKHxZfPAA7AgAMAAgKHxZfPAA7AgAAAA==.',
Oz='Ozborne:BAAANQAECgQICAAAAA==.',
Pa='Padrone:BAAANQADCgYIGAAAAA==.Paladullahan:BAAANQAECgUICwAAAA==.Pandthrall:BAAANQAECgQIBAAAAA==.Pawthos:BAAANQADCgcICwAAAA==.',
Pe='Pennonteller:BAAANQADCgQIBAAAAA==.Pennydredful:BAAANQABCgYIBwAAAA==.Perplnuggetz:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Pewpewmcgraw:BAAANQAECgcIEwAAAA==.',
Ph='Phobu:BAAANQAECgQIBAAAAA==.',
Pl='Plaguehart:BAAANQAECgUICwAAAA==.Plagueniss:BAABNQAECoEqAAIVAAkKPSZQAADvAwAVAAkKPSZQAADvAwAAAA==.',
Po='Pompina:BAAANQADCgUIBQAAAA==.Pompino:BAAANQABCgQIBAAAAA==.',
Pr='Primø:BAAANQAECgUIDwAAAA==.',
Ps='Psychó:BAABNQAECoEWAAIaAAgKzhz2IgBrAgAaAAgKzhz2IgBrAgAAAA==.',
Pu='Puerile:BAAANQAECgEIAQAAAA==.Purplêlotus:BAABNQAECoE0AAIGAAkKiBWPNgCDAgAGAAkKiBWPNgCDAgAAAA==.Purrl:BAAANQAECgEIAgAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
['Pö']='Pöppy:BAAANQAECgYICgAAAA==.',
Qs='Qserie:BAAANQADCgcIHgAAAA==.',
Ra='Rabid:BAAANQADCgYIDAABNQAECgkJIQAEAAIaAA==.Racelon:BAAANQAECgcIEgAAAA==.Raidgriefer:BAABNQAECoEYAAIbAAcK5iIrFwCfAgAbAAcK5iIrFwCfAgAAAA==.Raistlín:BAAANQAECgQIBAAAAA==.Rakwell:BAAANQAECgUICAAAAA==.Raloth:BAAANQABCgQJBQAAAA==.Ramadin:BAAANQADCgIIAgABNQAECgkJIQAEAAIaAA==.Ramil:BAAANQAECgUIDgAAAA==.Ramorash:BAAANQAECgEIAgAAAA==.Randomeena:BAAANQADCgYIBgAAAA==.Raptorbait:BAAANQADCgUIDgAAAA==.',
Re='Reannis:BAAANQADCgUIDAAAAA==.Reanukeeves:BAAANQADCgUICAAAAA==.Redvoid:BAAANQAECgQJCAABNQAFFAMIBwAEAMgaAA==.Rekane:BAAANQAECgIIBgAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAABNQAECoEhAAIcAAgKuRXiEAAiAgAcAAgKuRXiEAAiAgAAAA==.Reteril:BAABNQAECoEfAAIGAAgKzSKsGQABAwAGAAgKzSKsGQABAwAAAA==.Reyis:BAAANQAECgUIDwAAAA==.Reyvinite:BAAANQAECgUICgAAAA==.',
Rh='Rhodaria:BAAANQAECgEIAQAAAA==.',
Ri='Ricepicks:BAABNQAECoEmAAIIAAgKiwlaLADFAQAIAAgKiwlaLADFAQABNQADCgYIBgADAAAAAA==.Rilaka:BAAANQADCggIJAAAAA==.Rintaladin:BAAANQADCgMIAwABNQAECgUICwADAAAAAA==.Rissu:BAABNQAECoEgAAMIAAkKnhnjEgCeAgAIAAkKaRfjEgCeAgAJAAgKtBmXDQCBAgAAAA==.Risuu:BAAANQAECgcICwAAAA==.',
Ro='Roasted:BAAANQAECgUIDQAAAA==.Roka:BAAANQABCgMIBAAAAA==.Ronathan:BAAANQAECgUIDgAAAA==.Roper:BAABNQAECoEdAAMXAAgKKBBqIADoAQAXAAgKKBBqIADoAQAHAAcKBQ7wZgCCAQAAAA==.Roshen:BAAANQADCggIHwAAAA==.Rosselyne:BAAANQAECgMIAwABNQAECgcIDgADAAAAAA==.Rouzou:BAAANQAECgUIDgAAAA==.',
Rr='Rrun:BAAANQAECgYJBgAAAA==.',
Ru='Rukia:BAABNQAECoEnAAMXAAkKHyJ+DAD1AgAXAAgKuiF+DAD1AgAHAAQKoxL/jQD3AAAAAA==.Rumgold:BAAANQAECgUIDgAAAA==.Rustins:BAAANQADCgYICgAAAA==.',
Ry='Rynhart:BAAANQADCgQIBAABNQAECgUICwADAAAAAA==.Ryoushen:BAAANQADCggIDAAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Sadie:BAAANQADCgUIDgAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAACNQAFFIERAAMEAAYKuiAUAwAYAgAEAAYKex4UAwAYAgAGAAEKhiDDHgBmAAA1AAQKgSoAAgQACQrsJTYCALMDAAQACQrsJTYCALMDAAAA.Sarai:BAAANQABCgUICwAAAA==.Sarbev:BAABNQAECoEhAAQdAAkK1xLRDgA3AgAdAAkK1xLRDgA3AgAeAAIKAQ7TFwBkAAAfAAEKzwRmRAArAAAAAA==.Saskwatch:BAACNQAFFIEJAAICAAQKPg3+BQA8AQACAAQKPg3+BQA8AQA1AAQKgScAAgIACQqqG/0MAMcCAAIACQqqG/0MAMcCAAAA.Savat:BAAANQAECgUICgABNQAECgcIEQADAAAAAA==.Sayoko:BAABNQAECoEbAAINAAgK/iTsCQBSAwANAAgK/iTsCQBSAwAAAA==.Sayris:BAABNQAECoEdAAIGAAgK1gwPZAD3AQAGAAgK1gwPZAD3AQAAAA==.',
Sc='Scarymonster:BAAANQADCgIIAgAAAA==.Sckratchxx:BAAANQAECgUICQAAAA==.Scoochacho:BAABNQAECoEdAAIBAAgKWiLBKAAoAwABAAgKWiLBKAAoAwAAAA==.',
Se='Senhunter:BAAANQAECgUIDAAAAA==.Senmaster:BAAANQADCggIEQABNQAECgUIDAADAAAAAA==.Sentrollock:BAAANQABCgIIAgABNQAECgUIDAADAAAAAA==.Seradiin:BAAANQADCgEIAQAAAA==.Sereknight:BAAANQADCgQIBAAAAA==.',
Sh='Shakers:BAABNQAECoEnAAIGAAkKPB81FAAiAwAGAAkKPB81FAAiAwAAAA==.Shaleron:BAAANQADCgcICgAAAA==.Shamarq:BAAANQADCggIIgAAAA==.Shamtastyc:BAAANQADCgUIBQABNQAECgUICgADAAAAAA==.Shapewalker:BAABNQAECoEjAAMgAAgKdBo6BgBjAgAgAAgKdBo6BgBjAgAbAAEKaRfLbABHAAAAAA==.Shayla:BAAANQADCgYICgAAAA==.Shaylina:BAAANQAECgYIEQAAAA==.Shaylune:BAAANQADCggIGQABNQAECgYIEQADAAAAAA==.Sheba:BAAANQABCgEIAQAAAA==.Shendhi:BAAANQABCgQIBAAAAA==.Sheoby:BAAANQABCgMJBAAAAA==.Shiftcen:BAAANQAECgQIBgAAAA==.Shintazhi:BAAANQAECgUIDgAAAA==.Shirkan:BAABNQAECoElAAIWAAgKzCA6AwDkAgAWAAgKzCA6AwDkAgAAAA==.Shojobeat:BAAANQAECgQIBAAAAA==.Shootypizza:BAAANQAECgcIDgABNQAFFAUICgAJAEIaAA==.Shreddedbeef:BAAANQAECgYICgAAAA==.Shwartz:BAAANQADCgQIBAAAAA==.',
Si='Simplicity:BAAANQAECgUICwAAAA==.Sindrii:BAAANQAECgEIAQAAAA==.Sinhoi:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.Sinku:BAAANQAECgMIBQAAAA==.Sinza:BAAANQADCggIFAABNQAECgMIBQADAAAAAA==.Sixp:BAAANQADCgYICQABNQAECgkJKgAMAIEaAA==.',
Sk='Skadooshh:BAAANQAECgUIBgABNQAECggIGwANAP4kAA==.Skarray:BAEANQAECgUIDgAAAA==.',
Sl='Slyraxis:BAAANQAECgUIDAAAAA==.',
So='Soleirra:BAAANQADCgEIAQABNQADCggICAADAAAAAA==.Sonas:BAAANQADCgcIDQAAAA==.Soohainao:BAAANQADCgcIDwABNQAECgkJKgAMAIEaAA==.Sorador:BAAANQADCgQIBwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIBAAAAA==.Sparia:BAAANQAECgQIBAAAAA==.Spellgibson:BAABNQAECoEYAAIBAAgKcxjLewBOAgABAAgKcxjLewBOAgAAAA==.Spiara:BAAANQABCgQIBAAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAAANQAECgUIDwAAAA==.',
Sq='Squirrél:BAAANQADCgUIBQAAAA==.',
St='Stealthgoat:BAAANQADCgQIBAABNQADCgUIBQADAAAAAA==.Stinkyfeets:BAAANQABCgEJAQAAAA==.Stoogle:BAAANQAECggIEgAAAA==.Stormbrook:BAAANQAECgUIDwAAAA==.Stoutlager:BAAANQADCgYIBgAAAA==.Stubbytotems:BAAANQADCggICAABNQAECgUICQADAAAAAA==.Stumpnose:BAAANQAECgIIAgAAAA==.Sturmdorf:BAAANQAECgIIAgAAAA==.',
Su='Suhli:BAAANQADCgYIEAAAAA==.Sulfrick:BAAANQADCggIIgAAAA==.Summannuz:BAAANQADCgIIAgAAAA==.',
Sv='Svurg:BAAANQAECgEIAgAAAA==.',
Sw='Sweetchi:BAAANQAECgUIDQAAAA==.',
Sy='Sybria:BAAANQAECgQIBgAAAA==.Sykko:BAAANQAECgIIAgAAAA==.Sylea:BAAANQAECgIIAgAAAA==.Sylverhunter:BAAANQABCgcICwABNQAECgEIAQADAAAAAA==.Symet:BAAANQAECgIIAwAAAA==.',
['Så']='Såturn:BAAANQAECgMIBAAAAA==.',
Ta='Takaria:BAAANQAECgYJCAAAAA==.Takaris:BAAANQADCgcIBwAAAA==.Tal:BAEANQAECgYICAAAAA==.Tankdium:BAAANQAECgUICwAAAA==.Tapcon:BAAANQAECgQICAAAAA==.Tape:BAAANQADCggJDwAAAA==.Tarlas:BAAANQAECgYIEAAAAA==.Tayllore:BAAANQAECgYIDwAAAA==.',
Te='Tearsheet:BAAANQADCgcIGgABNQAECgYIEAADAAAAAA==.Terah:BAAANQAECgUIDgABNQAFFAIIAwADAAAAAA==.Terendelev:BAAANQAECgcIEQAAAA==.Terrador:BAAANQAECgUIDwAAAA==.Terramortua:BAABNQAECoEeAAIaAAkKJCTMBwBlAwAaAAkKJCTMBwBlAwABNQAFFAIIAwADAAAAAA==.Terraviridis:BAAANQAFFAIIAwAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQAECgUIDgADAAAAAA==.Thaugtless:BAAANQADCgYJDAABNQAECgUIDwADAAAAAA==.Thelonius:BAAANQAECgQIBgAAAA==.Therocksays:BAAANQAECgUIDwAAAA==.Thindead:BAAANQADCgIIAgABNQAECgkJIgASACgaAA==.Thinloc:BAABNQAECoEiAAQSAAkKKBooQQBPAgASAAgKahkoQQBPAgAhAAQKrhicKAAeAQAiAAIKrhWGFwCOAAAAAA==.Thinpal:BAAANQAECgIIAwABNQAECgkJIgASACgaAA==.Thragge:BAEANQAECgUICQAAAA==.Thronjak:BAAANQAECgUIDwAAAA==.Thunderfury:BAAANQAECgUIDQAAAA==.',
Ti='Tidepod:BAAANQADCggIEAAAAA==.Tidêpod:BAAANQADCgYIBgAAAA==.Tienlong:BAAANQABCggIEgAAAA==.Tipride:BAABNQAECoEqAAMMAAkKgRp+SgD9AQAMAAcKwRp+SgD9AQANAAkKYxEBRwD4AQAAAA==.Tiradis:BAAANQADCgMIAwAAAA==.Tiralie:BAAANQAECgQICAAAAA==.Tiryl:BAAANQADCggIIQAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQAECgQICAAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQAECgEIAQAAAA==.Toshinori:BAAANQADCggIDAAAAA==.Totemdáddy:BAAANQAECgQIBwAAAA==.Tovëlo:BAAANQAECgYIBgAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Treldend:BAAANQADCgEJAQAAAA==.Trinogra:BAABNQAECoEhAAMEAAkKAhqSFQCEAgAEAAkKsRmSFQCEAgAGAAEK7hcYDwFEAAAAAA==.Trunks:BAAANQAECgUIDgABNQAECgYIDQADAAAAAA==.Trystern:BAAANQAECgQJCgABNQAECgUIBQADAAAAAA==.',
Tu='Turmeric:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.',
['Tä']='Tänya:BAAANQAECgUIDwAAAA==.',
Uh='Uhno:BAAANQADCggICAAAAA==.Uhoh:BAAANQADCgUIBQAAAA==.',
Ul='Ultar:BAABNQAECoEiAAIRAAgK1yGnKgDiAgARAAgK1yGnKgDiAgAAAA==.Ultodeesavag:BAAANQAECgUIDgAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgEIAgAAAA==.Unholyjinksy:BAAANQAECgQIAwAAAA==.Unvdi:BAAANQADCggIFQAAAA==.',
Va='Vaderrage:BAABNQAECoERAAMWAAcKcx0WBgBdAgAWAAcKthwWBgBdAgAUAAIKgxgL7ACfAAAAAA==.Valeyria:BAAANQAECgUIBQAAAA==.Valiyntha:BAAANQAECgIIAgABNQAECgUIDQADAAAAAA==.Valri:BAAANQADCgUJCQAAAA==.Vancasper:BAAANQAECgEIAgAAAA==.Vanishmancha:BAAANQADCgMIAwAAAA==.Varl:BAAANQAECgUICQABNQAECgkJKAASAIciAA==.Varlock:BAABNQAECoEoAAQSAAkKhyIjEgAdAwASAAgKYiIjEgAdAwAiAAYKhR5XBwDfAQAhAAQKIRKXLgD8AAAAAA==.Vasill:BAAANQAECgQJBAAAAA==.',
Ve='Velari:BAAANQAECgYIEAAAAA==.Velmathris:BAAANQAECgUIBwAAAA==.Ventnor:BAAANQADCgIIAgAAAA==.Veydh:BAABNQAECoEWAAIgAAgKvCJrAgAiAwAgAAgKvCJrAgAiAwAAAA==.Veymina:BAAANQADCgYJEgABNQAECggIFgAgALwiAA==.',
Vi='Viinnee:BAAANQAECgYIDQAAAA==.Vilehart:BAAANQADCgMIAgABNQAECgUICwADAAAAAA==.Vilya:BAAANQADCgcIDQAAAA==.Vincentlight:BAAANQAECgEIAQAAAA==.Vixess:BAABNQAECoEmAAIHAAkKix2eFQD3AgAHAAkKix2eFQD3AgAAAA==.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volteer:BAABNQAECoEfAAIdAAcKPQ1KGACFAQAdAAcKPQ1KGACFAQAAAA==.',
Vu='Vudor:BAAANQAECgEIAQAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQAECgYIDQADAAAAAA==.Vynddradoria:BAABNQAECoEkAAQiAAkKIxnjAgCpAgAiAAkKIxnjAgCpAgAhAAIKDQv5VQBqAAASAAEKigZ8CQEyAAAAAA==.Vyndh:BAABNQAECoEZAAQjAAgKEyQcCgAdAwAjAAgKACQcCgAdAwAgAAUKMx9GCwC9AQAbAAEKAwj/cgA1AAAAAA==.Vynlock:BAAANQAFFAIIAwAAAA==.Vynstaya:BAAANQADCgYJBgAAAA==.',
Wa='Walkerbowe:BAAANQAECgIIAwAAAA==.Walt:BAAANQAECgQICwAAAA==.Wanderin:BAAANQAECgUICwAAAA==.Wanderit:BAAANQADCgEIAgAAAA==.Waterbutcold:BAAANQAECgUICgAAAA==.Waysmomtwo:BAAANQADCgYIBgAAAA==.',
We='Webby:BAAANQAECgYIDQAAAA==.',
Wh='Whiskerses:BAAANQAECgcIEQAAAA==.Whithers:BAAANQAECgEIAQAAAA==.',
Wi='Wilmer:BAAANQAECgQJBAAAAA==.Wilyy:BAAANQAECgQICQABNQAECgkJIgAaAOEcAA==.Winterchild:BAAANQADCgIIAgAAAA==.',
Wo='Woodsylver:BAAANQAECgEIAQAAAA==.Wookiee:BAAANQADCgUICQAAAA==.Worski:BAAANQAECgIIAgAAAA==.',
Wr='Wrathalthiel:BAAANQAECgEIAQAAAA==.Wratherael:BAAANQADCggIDQABNQAECgEIAQADAAAAAA==.Wraîth:BAABNQAECoEeAAIbAAgKkQt0MADGAQAbAAgKkQt0MADGAQAAAA==.',
Wy='Wynilla:BAAANQAECgIIAgAAAA==.',
Xa='Xanamage:BAAANQADCgUIBQAAAA==.Xanathar:BAAANQAECgMICAAAAA==.Xaphoris:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.Xayleficent:BAAANQADCgYIBgAAAA==.Xaylia:BAAANQAECgUIDwAAAA==.',
Xe='Xerhunt:BAAANQAECgUIBQAAAA==.Xerial:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.',
Xi='Xilorith:BAAANQAECggIBwAAAA==.',
Xo='Xolotin:BAAANQADCgMJAwAAAA==.',
Ya='Yassi:BAAANQAECgUIDgAAAA==.',
Ye='Yelignar:BAAANQADCgUIBQAAAA==.',
Yn='Ynarii:BAAANQADCgQIBQAAAA==.Ynkdh:BAAANQAECgEIAQABNQAECggIEAADAAAAAA==.',
Yo='Yoonhee:BAAANQAECgcIDgAAAA==.',
Yu='Yura:BAAANQADCgQIBQAAAA==.Yurtrus:BAAANQAECgIIAgAAAA==.',
Za='Zaghary:BAAANQAECgMICwAAAA==.Zaphor:BAAANQADCgQIBAABNQAECgUIBQADAAAAAA==.Zarik:BAAANQADCgIIAwAAAA==.',
Ze='Zebjati:BAAANQAECgUIDgAAAA==.',
Zh='Zhend:BAAANQAECgUIDQAAAA==.',
Zo='Zoot:BAAANQADCgQIBAAAAA==.',
Zu='Zunch:BAAANQAECgEIAgAAAQ==.',
['Àz']='Àzazel:BAABNQAECoEUAAMbAAYKew3yPgBVAQAbAAYKew3yPgBVAQAgAAMKHALlHwBfAAAAAA==.',
['Är']='Ärk:BAAANQAECgUIDQAAAA==.Ärmistice:BAAANQAECgYIDgAAAA==.',
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
