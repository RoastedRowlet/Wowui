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

local lookup = {'Mage-Arcane','Druid-Restoration','Unknown-Unknown','Hunter-Marksmanship','Druid-Guardian','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Frost','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Warrior-Arms','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','Paladin-Protection','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Fury','Rogue-Outlaw','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abrothael:BAAANQAECgYICwAAAA==.',
Ad='Adorèè:BAAANQAECgUJCQAAAA==.',
Ae='Aedelas:BAAANQADCgQIBAAAAA==.Aelucãrd:BAAANQADCggJCAAAAA==.Aestua:BAAANQADCgQICQAAAA==.Aetheros:BAABNQAECoEgAAIBAAkKmxdETwCeAgABAAkKmxdETwCeAgAAAA==.',
Ag='Agarim:BAAANQADCgQICAAAAA==.',
Ai='Airlinna:BAABNQAECoEbAAICAAgKdRf4EQBJAgACAAgKdRf4EQBJAgAAAA==.Airoach:BAAANQADCggIJwAAAA==.',
Ak='Akers:BAAANQADCggICwABNQAECgQJBgADAAAAAA==.',
Al='Alaraen:BAAANQAECgQICgAAAA==.Alcremie:BAAANQAECgIIAwABNQAFFAYIEQAEALogAA==.Aleman:BAAANQADCgYIEAAAAA==.Aleve:BAAANQADCgIIAgAAAA==.Alexxandria:BAAANQADCggJCwAAAA==.Aleyah:BAAANQAECgUJBQAAAA==.Almarii:BAAANQAECgQICQAAAA==.Alraune:BAAANQAECgcJEgAAAA==.Alynndra:BAAANQAECgQICQAAAA==.Alyssazoe:BAAANQADCgIIBAAAAA==.',
Am='Ambler:BAAANQADCgcIDQAAAA==.',
An='Anarionhunts:BAAANQAECgMJCAAAAA==.Andius:BAAANQADCgcIGgAAAA==.Andoric:BAAANQABCgYICAAAAA==.Anirra:BAAANQAECgQICQAAAA==.Annaraeliri:BAAANQADCgMIAwAAAA==.',
Ap='Apert:BAAANQAECgQJCgAAAA==.Apnea:BAAANQADCgIIAgAAAA==.Appa:BAAANQADCgQIBAAAAA==.',
Ar='Ardenweald:BAABNQAECoEfAAMCAAgKRR2ADACiAgACAAgKRR2ADACiAgAFAAEKNgogNgAnAAAAAA==.Armyokittens:BAAANQADCgcJGwAAAA==.Arroezze:BAAANQADCgYIBQAAAA==.Arthurin:BAAANQAECgQIBgAAAA==.',
As='Ashaleth:BAAANQADCgUIBQAAAA==.Ashayo:BAAANQADCggJEQAAAA==.Astrana:BAAANQAECgYIEAAAAA==.',
At='Athelstan:BAAANQADCgcIBwAAAA==.',
Au='Augkward:BAAANQAECgMJAwABNQAFFAQJBwAGAOAVAA==.Aureldor:BAAANQADCgMIAwAAAA==.Automatic:BAABNQAECoEZAAMHAAgKNxkFEgB1AgAHAAgKABkFEgB1AgAIAAMKphzGKwAEAQAAAA==.Autoshot:BAAANQADCgMIBAAAAA==.',
Av='Avorek:BAAANQADCgUIBQAAAA==.Avorik:BAAANQAECgQIBAAAAA==.Avouric:BAAANQADCgUICQAAAA==.',
Az='Azaree:BAAANQAECgQJCgAAAA==.Azndak:BAAANQADCgcJBwAAAA==.',
Ba='Baelzabob:BAAANQADCgYJFwAAAA==.Bakaran:BAAANQADCgUJBQAAAA==.Barae:BAAANQADCgYIEgAAAA==.Barboosa:BAAANQAECgEIAQAAAA==.Barcmaul:BAAANQADCggIIQAAAA==.Bathzalts:BAAANQADCgYIBQAAAA==.Baylel:BAAANQAECgMJBQAAAA==.',
Bb='Bbqmonk:BAAANQADCggICAABNQAECgQJBAADAAAAAA==.',
Be='Bearbq:BAAANQAECgQJBAAAAA==.Belledolphin:BAAANQAECgUJBQAAAA==.Bellgold:BAAANQADCgEIAQABNQAECgUJCQADAAAAAA==.Berigo:BAAANQAECgcJEgAAAA==.Bertoxulous:BAAANQADCggJBQAAAA==.Bezvoker:BAAANQAECgUICAAAAA==.Beárwithme:BAAANQADCgQICAAAAA==.',
Bi='Birria:BAAANQADCgQIBAABNQADCgYJCgADAAAAAA==.',
Bj='Bjordrann:BAAANQADCgEIAQAAAA==.',
Bl='Blackhoofcow:BAAANQAECgEJAQAAAA==.Blackicewolf:BAABNQAECoEeAAIJAAgKnyLfAwAuAwAJAAgKnyLfAwAuAwAAAA==.Bleake:BAAANQADCgUIBQAAAA==.Bleunienn:BAAANQADCgYJBgAAAA==.Blueberrypie:BAAANQAECgUICAAAAA==.',
Bo='Bonbarrion:BAEBNQAECoEbAAQKAAgK/BsiOgATAgAKAAYKWR4iOgATAgALAAUKnQsUfgALAQAJAAIK5RQRHwClAAAAAA==.Borbory:BAAANQAECgUJCQAAAA==.Boringhuman:BAAANQAECgIIAgAAAA==.Borlorín:BAAANQADCgYIBgAAAA==.Borogove:BAAANQADCgYJDAAAAA==.',
Br='Brasca:BAAANQAECgQJCgAAAA==.Brisketdk:BAAANQAECgIIAgABNQAECgQJBAADAAAAAA==.Bruhmal:BAAANQAECgUJCQAAAA==.Brunner:BAAANQADCgEIAQAAAA==.Brynndolin:BAAANQAECgQJCgAAAA==.',
Bu='Burzolog:BAABNQAECoEaAAIIAAcKGBBjGgDIAQAIAAcKGBBjGgDIAQAAAA==.',
['Bä']='Bärk:BAABNQAECoEvAAIMAAgKURtcHwB0AgAMAAgKURtcHwB0AgAAAA==.',
Ca='Calanash:BAAANQADCgcIBwABNQAECgYJDQADAAAAAA==.Calazan:BAAANQAECgYJDQAAAA==.Cascious:BAAANQADCgcIBwABNQAFFAMIBQACAKgHAA==.Casylla:BAAANQADCgMJAwAAAA==.Cazym:BAAANQADCggICAABNQAECggIBgADAAAAAA==.',
Ce='Cedarjr:BAAANQAECgMIBAAAAA==.Cef:BAAANQAECgUICQAAAA==.Celindre:BAAANQADCgcJCQAAAA==.',
Ch='Cherrybomb:BAAANQADCgIIAgAAAA==.Chewbie:BAAANQAECgEIAQAAAA==.Chickentendi:BAAANQADCgQIBAABNQAECgQICgADAAAAAA==.Choonjung:BAAANQAECggIBwAAAA==.Chronis:BAAANQAECgEIAQAAAA==.',
Ci='Ciphon:BAAANQAECgIJAgAAAA==.Cirok:BAAANQADCgcIDQAAAA==.Civic:BAAANQAECgQIBAAAAA==.',
Ck='Cklyde:BAABNQAECoEhAAINAAkKiR/eCQBHAwANAAkKiR/eCQBHAwAAAA==.',
Cl='Claiyre:BAAANQAECgIJAgABNQAECgIIAgADAAAAAA==.Clewis:BAAANQABCgUICAAAAA==.Clubble:BAAANQAECgMJBAAAAA==.Clumperton:BAABNQAECoEZAAIOAAkKhB1VFgD0AgAOAAkKhB1VFgD0AgAAAA==.Clãsh:BAAANQAECgIIBAAAAA==.',
Co='Cochino:BAAANQAECgUIBgAAAA==.Concentrate:BAAANQAECgYJCwAAAQ==.Connan:BAAANQAECgMJBQABNQAECgUJDwADAAAAAA==.Constant:BAAANQADCggJEQAAAA==.Corbesan:BAAANQADCgcIBwABNQAECgQICAADAAAAAA==.Cordrann:BAAANQADCggJGgAAAA==.Coveness:BAAANQADCgIIAgAAAA==.Cowi:BAABNQAECoEdAAILAAkKjB10EQD8AgALAAkKjB10EQD8AgAAAA==.',
Cr='Crasusakechi:BAAANQAECgIJAgAAAA==.Crisisangel:BAAANQADCggIAgAAAA==.Cryomagus:BAABNQAECoEbAAIPAAgKkBXUHQAOAgAPAAgKkBXUHQAOAgAAAA==.',
Cu='Cuqquiform:BAABNQAECoEZAAMCAAcKFiTLDwBsAgACAAYKhCTLDwBsAgAMAAYKPh1XLAADAgAAAA==.',
Cy='Cylesia:BAAANQADCggIHAAAAA==.Cylthia:BAAANQADCgQJBAAAAA==.Cyrienna:BAAANQADCgYIBwAAAA==.',
Da='Daemata:BAAANQAECgEIAgAAAA==.Dajinbo:BAAANQAECgEJAQAAAA==.Damons:BAAANQAECgMJAwABNQAFFAEJAQADAAAAAA==.Dankinia:BAAANQADCgQIBAAAAA==.Darchlo:BAAANQADCgEIAQAAAA==.Darkhammer:BAAANQAECgIIBAAAAA==.Darkswift:BAABNQAECoEgAAIQAAkK6SFZEgBEAwAQAAkK6SFZEgBEAwAAAA==.Darnadda:BAAANQADCgcIFQAAAA==.Darowyn:BAAANQAECgUJCQAAAA==.Dashiell:BAAANQAECgMIAwABNQAECgQICAADAAAAAA==.Dawnflare:BAAANQADCgcIDQABNQAECgYJDgADAAAAAA==.',
De='Deathryder:BAAANQADCggICAAAAA==.Deaxus:BAAANQAECgMIBAABNQAECggIGwARAAAOAA==.Deb:BAAANQAECgQICQAAAA==.Delailia:BAAANQADCggIDgAAAA==.Delbelfine:BAABNQAECoEgAAINAAkKXBHtLQBJAgANAAkKXBHtLQBJAgAAAA==.Delfar:BAAANQADCgUIBQAAAA==.Delisomethng:BAAANQAECgUJDAAAAA==.Dellechero:BAAANQADCgYIDAAAAA==.Demilich:BAAANQADCgIJAgAAAA==.Demonra:BAAANQADCgMIAwAAAA==.Despaira:BAAANQAECgQIBwAAAA==.Dethyler:BAAANQAECgUJCQAAAA==.Devilwoman:BAAANQAECgQJCAAAAA==.Deyv:BAAANQAECgUJCQAAAA==.',
Di='Diancie:BAAANQAECgIIAgABNQAFFAYIEQAEALogAA==.Diddibeau:BAAANQAECgQICQAAAA==.Diddiblind:BAAANQADCgMIBgABNQAECgQICQADAAAAAA==.Diego:BAAANQADCgEIAQAAAA==.Divinezanon:BAAANQAFFAIIAwABNQAFFAQIBAADAAAAAA==.',
Do='Dontyagnomie:BAAANQAECgUJBwAAAA==.Doobu:BAAANQADCgcJFwAAAA==.Dooganitis:BAAANQAECgQJBQAAAA==.Dorne:BAAANQADCggIDwAAAA==.Doruk:BAAANQAECgQIBAAAAA==.',
Dr='Dreamsoul:BAAANQABCgQIBQAAAA==.Drfeelgreat:BAAANQADCgIIAwAAAA==.',
Du='Dullahstrasz:BAAANQADCgYIBgAAAA==.Dusksorrow:BAAANQADCgUIBQAAAA==.',
Dz='Dzud:BAAANQADCgUJBQAAAA==.',
Ed='Edovard:BAAANQADCggIHAAAAA==.',
Ee='Ee:BAAANQADCgcIDAABNQADCggICAADAAAAAA==.Eeragon:BAAANQAECgMIAwAAAA==.',
El='Elentari:BAAANQABCgMIAwAAAA==.Elfshadow:BAAANQABCgQJAwAAAA==.Eliyon:BAAANQADCggIIQAAAA==.Ellarinya:BAAANQADCgUJCgAAAA==.Ellemir:BAAANQADCgcIGgAAAA==.Elshifty:BAAANQADCgcIBwABNQAECggIAQADAAAAAA==.Eltanari:BAAANQADCggIGQAAAA==.Eluera:BAAANQAECggJDgAAAA==.Elyn:BAAANQAECgcIEQABNQAFFAEJAQADAAAAAA==.Elynthil:BAAANQAFFAEJAQAAAA==.',
Em='Emet:BAAANQABCgIIAgAAAA==.Emilie:BAAANQAECgEIAQAAAA==.Emunny:BAAANQAECgQJCgAAAA==.',
En='Endest:BAAANQAECgUJCQAAAA==.Enezalle:BAAANQAECgUJCQAAAA==.',
Eo='Eointhas:BAAANQAECgQJCgAAAA==.',
Ep='Ephimonk:BAAANQAECgQICAAAAA==.',
Er='Erenyeagar:BAAANQADCgYIBgAAAA==.Ernson:BAAANQADCgUJDQAAAA==.',
Eu='Euronymous:BAAANQAECgIJAwAAAA==.',
Ev='Evilandy:BAAANQAECgQIBQAAAA==.',
Fa='Faeleda:BAAANQADCgEIAQAAAA==.Fandrall:BAAANQADCgQIBgAAAA==.',
Fb='Fblthp:BAAANQAECgQJBgAAAA==.',
Fe='Felblood:BAAANQADCggJFwAAAA==.Ferndolyn:BAAANQADCgMIAwAAAA==.Fezduin:BAAANQADCgIIAgAAAA==.',
Fi='Finnagetit:BAAANQAECgUJBwAAAA==.',
Fl='Flagonslayer:BAAANQAECgIJAgAAAA==.Flaimefu:BAAANQADCggIIAAAAA==.Floorlicker:BAAANQADCgYIBgAAAA==.Flopsie:BAAANQAECgYJDQAAAA==.Fluffystorm:BAAANQADCgcIGgAAAA==.',
Fo='Forzod:BAAANQADCggJDwAAAA==.Forzzie:BAAANQADCgYICQAAAA==.Foxheals:BAAANQADCgcJBwAAAA==.Foxymagic:BAAANQAECgIJAgAAAA==.',
Fr='Frabjous:BAAANQAECgQJCgAAAA==.Freenk:BAAANQADCgcIEQAAAA==.Freezerburn:BAABNQAECoEfAAMBAAgKWRTfkwDmAQABAAcKMhTfkwDmAQASAAIKZhCDHwB9AAAAAA==.Frogstomper:BAAANQADCgEJAQAAAA==.',
Fu='Furn:BAAANQAECgQJCgAAAA==.Furryaz:BAAANQADCgQJBAAAAA==.Further:BAABNQAECoEgAAITAAkKLyRbCACYAwATAAkKLyRbCACYAwAAAA==.',
Fy='Fyrrek:BAAANQADCgYIDQAAAA==.',
Ga='Galadrien:BAAANQADCgYJBgAAAA==.Galavenat:BAAANQAECgUJCQAAAA==.Galroy:BAAANQADCgEIAQAAAA==.Galstan:BAAANQADCgUJCAAAAA==.Garbohydrate:BAAANQADCgEIAQAAAA==.Garbolicious:BAAANQADCgIJAgAAAA==.Garbothicc:BAAANQAECgQICQAAAA==.Garyh:BAACNQAFFIEUAAITAAcK1yB+AADlAgATAAcK1yB+AADlAgA1AAQKgScAAhMACQrPJtMAAPkDABMACQrPJtMAAPkDAAAA.Garyhreturns:BAAANQAECgUIBgABNQAFFAcIFAATANcgAA==.',
Ge='Geldeinmonch:BAAANQADCgYIBwABNQAECgQICAADAAAAAA==.Geldklerk:BAAANQADCgYIBwABNQAECgQICAADAAAAAA==.Geldverdamnt:BAAANQAECgQICAAAAA==.Gerasham:BAAANQADCgcIBwAAAA==.',
Gh='Ghost:BAAANQABCgQIBgAAAA==.Ghuramonk:BAAANQADCggICgAAAA==.',
Gi='Giacomo:BAAANQADCgYJCgAAAA==.Gil:BAAANQAECgQJBgAAAA==.Gildina:BAAANQADCggIHQAAAA==.Ginggy:BAAANQAECgUJDQABNQAFFAMIBQACAKgHAA==.Girafficz:BAABNQAECoEhAAIMAAkK3CVEAgDHAwAMAAkK3CVEAgDHAwABNQAFFAcIGQATAL8kAA==.',
Go='Gori:BAAANQAECgUJDwAAAA==.Gorin:BAAANQADCggIDAABNQAECgQICAADAAAAAA==.',
Gr='Graelle:BAAANQADCgYIBgAAAA==.Gralle:BAAANQAECgQICAAAAA==.Graug:BAAANQADCgUJBgABNQAECgMIAwADAAAAAA==.Gravehart:BAAANQADCggICAABNQAECgQJBgADAAAAAA==.Gravelbeard:BAAANQADCgIIBAAAAA==.Gregory:BAABNQAECoEUAAIBAAcK4xOekgDpAQABAAcK4xOekgDpAQABNQAECgMIAwADAAAAAA==.Greyantheril:BAAANQAECgUJCQAAAA==.Greyji:BAAANQAECgcIEQAAAA==.Grumb:BAABNQAECoEgAAIKAAkKzRUMJgCHAgAKAAkKzRUMJgCHAgAAAA==.',
Gu='Guenara:BAAANQAECgIJAgAAAQ==.Guillimon:BAAANQADCgQIBAABNQAECgYJEQADAAAAAA==.Gustytail:BAAANQAECgUICQAAAA==.',
Ha='Haardrada:BAAANQAECgUICAABNQAFFAcIFAATANcgAA==.Habit:BAAANQAECgYJEAAAAA==.Hadrianna:BAAANQAECgMIBQAAAA==.Halanir:BAAANQADCgIIAgAAAA==.Hanzul:BAAANQAECgUJCQAAAA==.Hapless:BAAANQAECgQJCQAAAA==.Hashanir:BAAANQADCgEIAQAAAA==.Hashat:BAAANQADCgIIAgAAAA==.Hawkfoot:BAAANQAECgIJAgAAAA==.',
He='Hearthbreakr:BAAANQAECgIIBAABNQAECgkJIgAKAIcYAA==.Hellanie:BAAANQADCgQIBwAAAA==.Hellbore:BAAANQAECgYJDgAAAA==.Hellchi:BAAANQAECgUJCAAAAA==.Hellinasel:BAAANQAECgMIAwAAAA==.Hemmy:BAABNQAECoEaAAINAAkKZyYhAAABBAANAAkKZyYhAAABBAAAAA==.Hermer:BAAANQADCgMIAwAAAA==.Heysham:BAAANQAECgUJCQAAAA==.Hezzakan:BAAANQADCggJHQAAAA==.',
Ho='Holycef:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.Holykow:BAAANQAECgUJCAAAAA==.Hotspur:BAAANQAECgQJCgAAAA==.Howlua:BAAANQADCgQJBAAAAA==.',
Hu='Huevomuerto:BAAANQADCgQICAAAAA==.Huevonyque:BAABNQAECoEhAAITAAkK7xwhJADjAgATAAkK7xwhJADjAgAAAA==.Huntsthewind:BAAANQADCgQIBAAAAA==.Huulgrim:BAAANQAECgUJCQABNQABCgMIAwADAAAAAA==.',
Hy='Hyejinx:BAAANQAECgUIBwAAAA==.',
Ic='Iceclaw:BAAANQADCgQJBAABNQADCgUJDgADAAAAAA==.Icona:BAAANQADCgQIBAAAAA==.',
Ih='Ihiannan:BAAANQADCgcIGgABNQAECgQJCgADAAAAAA==.',
Ii='Iiarian:BAAANQAECgQJCAAAAA==.',
Il='Ilivarra:BAAANQAECgQJBAAAAA==.Illisong:BAAANQADCgYJCQAAAA==.Illukana:BAABNQAECoEaAAIGAAgKkSHlEAD3AgAGAAgKkSHlEAD3AgABNQAECgkJKwAQAEQiAA==.',
In='Infoxy:BAAANQAECgUJCAAAAA==.Inthra:BAAANQAECgIIAwAAAA==.',
Ir='Irimas:BAAANQADCggJFwAAAA==.',
Is='Isopope:BAAANQABCgYIBgAAAA==.Isthian:BAAANQAECgUJCAAAAA==.',
It='Itako:BAAANQADCgYJGAAAAA==.Itoldhimso:BAAANQAECgEJAQAAAA==.',
Iv='Ivaldi:BAAANQADCgQJBwAAAA==.',
Ja='Jadelark:BAAANQAECgUICAAAAA==.Javèrt:BAABNQAECoEbAAIUAAgKrhdKJgAlAgAUAAgKrhdKJgAlAgAAAA==.Jaxina:BAAANQADCgUIBwABNQAECgUIDwADAAAAAA==.Jaxordamus:BAAANQAECgUIDwAAAA==.',
Je='Jekle:BAAANQADCgQIBAAAAA==.Jema:BAAANQAECgQIBQAAAA==.Jenilea:BAAANQAECgQJCgAAAA==.Jessaril:BAAANQAECgYJCwAAAA==.Jessbgood:BAAANQABCgIIAgAAAA==.',
Ji='Jimboree:BAABNQAECoEaAAIKAAgKWxvsJgCBAgAKAAgKWxvsJgCBAgAAAA==.Jinsu:BAAANQAECgEIAQAAAA==.Jinzeem:BAAANQADCggJHQAAAA==.Jiujitsunut:BAAANQADCgIIBAAAAA==.',
Jo='Jordend:BAAANQAECgEJAgAAAA==.Joseppii:BAAANQAECgQICgAAAA==.',
Jp='Jpxfrd:BAAANQABCgUJCgABNQADCgYJCgADAAAAAA==.',
Ju='Jungyuul:BAAANQAECgUJCgAAAA==.',
Jy='Jynnx:BAAANQADCgEIAQAAAA==.',
['Jâ']='Jâzzy:BAAANQAECgUICQAAAA==.Jâzzý:BAAANQADCggICgABNQAECgUICQADAAAAAA==.',
Ka='Kaajira:BAAANQADCgEIAQAAAA==.Kaandew:BAAANQADCggJHQAAAA==.Kailann:BAAANQAECgMIAwAAAA==.Kanji:BAAANQADCgcJDQAAAA==.Kaorin:BAAANQADCggIDQAAAA==.Karesta:BAAANQADCgQIBAAAAA==.Kaylith:BAAANQADCggIGgAAAA==.Kayra:BAAANQADCgYIDAAAAA==.',
Ke='Kegelsmash:BAAANQADCgMJAwABNQAECgcJGQAFANQlAA==.Kelanansi:BAAANQADCggIGwAAAA==.Kelanis:BAAANQADCgYIBgAAAA==.Kelel:BAABNQAECoEVAAMGAAcKfhKWRQDLAQAGAAcKfhKWRQDLAQAVAAEK/wwHHgAxAAAAAA==.Kessia:BAAANQADCggIHQAAAA==.Kessía:BAAANQADCgQIBAAAAA==.',
Kh='Khalistra:BAAANQAECgQJBQAAAA==.',
Ki='Kiroblade:BAAANQADCgcIDAABNQAECgcJEwADAAAAAA==.Kiropaly:BAAANQADCgYIDgABNQAECgcJEwADAAAAAA==.Kirotard:BAAANQAECgcJEwAAAA==.Kisldarin:BAAANQADCgUJBQAAAA==.Kithedrael:BAAANQAECgEJAQAAAA==.',
Kl='Klouded:BAAANQAECgYIBgAAAA==.',
Kn='Knuts:BAAANQADCgYICwAAAA==.',
Ko='Koa:BAAANQAECgIIBAAAAA==.Kojakk:BAAANQAECgQJCgAAAA==.Kordac:BAAANQAECgUJCQAAAA==.Korigan:BAAANQAECgMJCAAAAA==.Korvova:BAAANQADCgEIAQAAAA==.',
Kt='Kth:BAAANQABCgcIBwAAAA==.',
Ku='Kunamashiro:BAAANQAECgEJAQAAAA==.',
Ky='Kylê:BAAANQAECgEIAQAAAA==.Kymetra:BAAANQAECgUICgAAAA==.Kyttin:BAAANQADCgcIGgAAAA==.',
['Kä']='Kära:BAAANQADCggIDQABNQAECgUJDwADAAAAAA==.',
['Kÿ']='Kÿthe:BAAANQABCgUIBwAAAA==.',
La='Ladeeda:BAAANQADCgQIBwAAAA==.Laevi:BAAANQADCggJDwAAAA==.Lalena:BAAANQAECgIIAgAAAA==.Lawanda:BAAANQADCgEIAQABNQAECgQICQADAAAAAA==.',
Le='Leonineone:BAABNQAECoEgAAIWAAkKBxr2CwDlAgAWAAkKBxr2CwDlAgAAAA==.Ler:BAAANQADCgYIBgABNQADCggIHQADAAAAAA==.',
Li='Lichplease:BAABNQAECoEhAAIPAAkKgSPCBQBWAwAPAAkKgSPCBQBWAwAAAA==.Light:BAAANQAECggICAAAAA==.Lightlady:BAAANQADCggJFgAAAA==.Lightridge:BAAANQABCgUICQAAAA==.Lillythorne:BAAANQAECgUIBgAAAA==.Limewire:BAAANQAECgQIBAAAAA==.Lindsay:BAAANQADCgUJBQABNQAECgQICQADAAAAAA==.Litehlzonly:BAAANQAECgIIBAAAAA==.Literalcow:BAAANQABCgUJBQAAAA==.Livebeef:BAAANQADCgUIDwAAAA==.',
Lm='Lmaolock:BAAANQADCgEIAQAAAA==.',
Lo='Lohvadner:BAAANQADCggJFgAAAA==.Lothlum:BAAANQAECgQICAAAAA==.',
Lu='Lunacie:BAAANQADCgUICQAAAA==.Lunalia:BAAANQAECgEJAgAAAA==.Lupen:BAAANQAECgQIBgAAAA==.Luxurria:BAAANQADCgYICQAAAA==.',
Ly='Lynlin:BAAANQAECgMJBAAAAA==.',
Ma='Magesef:BAAANQAECgUJCQAAAA==.Magnusrn:BAAANQADCgUJDgAAAA==.Makinmemoist:BAAANQAECgIIAgAAAA==.Malandras:BAAANQADCgEIAQAAAA==.Malandrius:BAAANQADCggJGgAAAA==.Malehei:BAAANQADCgMIAwAAAA==.Malignities:BAAANQAECgYJEAAAAA==.Malthruin:BAAANQADCggIIQABNQAECggIGwARAAAOAA==.Manajamba:BAAANQAECgUJCAAAAA==.Manamidget:BAAANQADCgUICQAAAA==.Mancubus:BAAANQAECgYIEwAAAA==.Marosenth:BAAANQADCggJEgAAAA==.Marqadin:BAAANQADCgIIBAAAAA==.Maxidorf:BAAANQADCggJDgAAAA==.',
Me='Meleeno:BAAANQADCgIIBAAAAA==.Meush:BAABNQAECoErAAIQAAkKRCJEEwA9AwAQAAkKRCJEEwA9AwAAAA==.Mewkow:BAAANQADCggJHQAAAA==.Mewsa:BAAANQAECgQJCgAAAA==.',
Mi='Micha:BAAANQADCgcIDAAAAA==.Midgee:BAAANQADCggIGwAAAA==.Minimigraine:BAAANQAECgQIBgAAAA==.Miniroar:BAAANQADCgMIAwAAAA==.Miphisto:BAAANQADCgcIFwAAAA==.Mirandee:BAAANQAECgEJAQAAAA==.Mishrani:BAAANQADCggIFgAAAA==.Mite:BAAANQADCggICgAAAA==.',
Mo='Moa:BAAANQADCggJGQAAAA==.Molding:BAAANQAECgUJCgAAAA==.Mollusk:BAAANQADCgUJCwAAAA==.Monis:BAAANQAECgcJEgAAAA==.Montessarah:BAAANQADCgcJEwAAAA==.Moonstôrm:BAAANQADCgYJBgAAAA==.Mootalica:BAAANQADCgQIBAAAAA==.Mordraug:BAAANQADCggIEwAAAA==.Morinoe:BAAANQAECgQICQAAAA==.Mornwalker:BAAANQAECgUJCQAAAA==.',
Mu='Mudelf:BAAANQADCgYIDAAAAA==.Mumra:BAAANQAECgYIDgABNQAECgcIGQACABYkAA==.',
My='Mysticc:BAAANQADCggJFgAAAA==.Myxii:BAAANQAECgIIAgABNQAECgQJBAADAAAAAA==.',
['Mà']='Màdrigal:BAAANQADCggJHAAAAA==.',
['Mí']='Míckey:BAAANQAECgUJCQAAAA==.',
['Mÿ']='Mÿthunn:BAAANQAECgUJBwAAAA==.',
Na='Nadia:BAAANQADCgcIBwAAAA==.Nagratz:BAAANQAECgUJCQAAAA==.Naichingeru:BAAANQADCgcIGgAAAA==.Nalu:BAAANQADCggIDgAAAA==.Napalmo:BAAANQADCgUJCgAAAA==.Naterra:BAAANQAECgYJDgAAAA==.',
Ne='Necessities:BAAANQAECgMJAwAAAA==.Necrill:BAAANQAECgYJDQAAAA==.Neirwind:BAAANQADCggIEAAAAA==.',
Ni='Nichiwa:BAAANQAECgEIAQAAAA==.Niladros:BAAANQADCgcICwAAAA==.Nirazend:BAAANQADCgUJCgAAAA==.Nisaam:BAAANQADCgQJCgAAAA==.Niteterror:BAAANQAECgUIBwAAAA==.',
Nl='Nloc:BAAANQADCgYIDAAAAA==.Nlok:BAAANQADCgcJBwAAAA==.',
No='Nolmac:BAAANQADCggJGgAAAA==.Nomesacan:BAAANQADCgQIBAAAAA==.Nosleep:BAAANQADCgcIGgAAAA==.Novelia:BAAANQADCgIIAgAAAA==.',
Nu='Nuglife:BAAANQADCgYICwAAAA==.',
['Nà']='Nàtureuscary:BAAANQAECgQIBQAAAA==.',
Ob='Obtusepanda:BAAANQAECgUICgAAAA==.',
Oc='Ocupocorrer:BAAANQADCgYIBgAAAA==.',
Of='Offthechaeni:BAAANQADCggIDQAAAA==.',
Og='Ograndoe:BAABNQAECoEaAAIXAAgK+RgmDwAoAgAXAAgK+RgmDwAoAgAAAA==.',
Oh='Ohanzee:BAAANQADCgcIDgAAAA==.Ohku:BAAANQADCggJIAAAAA==.Ohok:BAAANQAECgUJCwAAAA==.',
Oi='Oisin:BAAANQADCggIHQAAAA==.',
Ol='Olomin:BAAANQADCgIIAwAAAA==.',
Om='Omathra:BAABNQAECoEbAAIRAAgKAA6uTgDlAQARAAgKAA6uTgDlAQAAAA==.',
On='Onikai:BAAANQAECgIJAgAAAA==.Onruk:BAAANQAECgQICAAAAA==.',
Op='Ophina:BAAANQAECgQJBgAAAA==.',
Or='Oreo:BAAANQADCggICAAAAA==.Orgish:BAAANQAECgIIAgABNQAECgQJBgADAAAAAA==.Orieda:BAAANQADCgUIBQAAAA==.Orihime:BAAANQADCgYIBgAAAA==.',
Os='Osage:BAABNQAECoEYAAITAAgKgyGeGgAYAwATAAgKgyGeGgAYAwAAAA==.',
Ox='Oxidising:BAAANQAECgYJDQAAAA==.',
Pa='Padrone:BAAANQADCgUJEgAAAA==.Paladullahan:BAAANQAECgQJBgAAAA==.Pawthos:BAAANQADCgcICwAAAA==.',
Pe='Pennonteller:BAAANQADCgQJBAAAAA==.Pennydredful:BAAANQABCgYIBwAAAA==.Perplnuggetz:BAAANQAECgEIAQAAAA==.Pewpewmcgraw:BAAANQAECgUIDAAAAA==.',
Pl='Plaguehart:BAAANQAECgQJBgAAAA==.Plagueniss:BAABNQAECoEiAAIYAAkK2CVJAADoAwAYAAkK2CVJAADoAwAAAA==.',
Po='Pompino:BAAANQABCgQIBAAAAA==.',
Pr='Primø:BAAANQAECgQICgAAAA==.',
Ps='Psychó:BAAANQAECggJDgAAAA==.',
Pu='Puerile:BAAANQADCggJFQAAAA==.Purplêlotus:BAABNQAECoEqAAIOAAgKBhRCOwBJAgAOAAgKBhRCOwBJAgAAAA==.Purrl:BAAANQAECgEJAQAAAA==.',
Py='Pyana:BAAANQADCgcIDQAAAA==.',
['Pö']='Pöppy:BAAANQAECgUJBwAAAA==.',
Qs='Qserie:BAAANQADCgYIFwAAAA==.',
Ra='Rabid:BAAANQADCgYIDAABNQAECgkJIAAEAAEYAA==.Racelon:BAAANQAECgcIEgAAAA==.Raidgriefer:BAAANQAECgcJEwAAAA==.Raistlín:BAAANQADCgcICwAAAA==.Rakwell:BAAANQAECgMJAwAAAA==.Raloth:BAAANQABCgQJBQAAAA==.Ramadin:BAAANQADCgEIAQABNQAECgkJIAAEAAEYAA==.Ramil:BAAANQAECgUJCQAAAA==.Ramorash:BAAANQAECgEJAQAAAA==.Randomeena:BAAANQADCgYIBgAAAA==.Raptorbait:BAAANQADCgQJCQAAAA==.',
Re='Reannis:BAAANQADCgUJBwAAAA==.Reanukeeves:BAAANQADCgMIAwAAAA==.Redvoid:BAAANQAECgQJCAABNQAECgkJIgAEAP8kAA==.Rekane:BAAANQAECgIJBAAAAA==.Relyste:BAAANQADCggIDgAAAA==.Renala:BAABNQAECoEZAAIZAAgK9wtdFQCdAQAZAAgK9wtdFQCdAQAAAA==.Reteril:BAABNQAECoEYAAIOAAgKPiFJFQD7AgAOAAgKPiFJFQD7AgAAAA==.Reyis:BAAANQAECgQJCgAAAA==.Reyvinite:BAAANQAECgQJBQAAAA==.',
Rh='Rhodaria:BAAANQADCggIIAAAAA==.',
Ri='Ricepicks:BAABNQAECoEaAAIHAAcKzQl6JwCaAQAHAAcKzQl6JwCaAQABNQADCgYIBgADAAAAAA==.Rilaka:BAAANQADCggJHAAAAA==.Rintaladin:BAAANQADCgMIAwAAAA==.Rissu:BAABNQAECoEYAAMHAAkKLRfMEwBfAgAHAAgKthXMEwBfAgAIAAcKVBbSFQD6AQAAAA==.Risuu:BAAANQAECgcICQAAAA==.',
Ro='Roasted:BAAANQAECgUJCQAAAA==.Roka:BAAANQABCgMIBAAAAA==.Ronathan:BAAANQAECgQICQAAAA==.Roper:BAAANQAECgYJEQAAAA==.Roshen:BAAANQADCggIHwAAAA==.Rosselyne:BAAANQADCgYJBgABNQAECgcIDgADAAAAAA==.Rouzou:BAAANQAECgUJCQAAAA==.',
Rr='Rrun:BAAANQAECgYJBgAAAA==.',
Ru='Rukia:BAABNQAECoEdAAMWAAgKGh45DgC8AgAWAAgKGh45DgC8AgAGAAMKbRDvjgCjAAAAAA==.Rumgold:BAAANQAECgUJCQAAAA==.Rustins:BAAANQADCgYICgAAAA==.',
Ry='Rynhart:BAAANQADCgQIBAABNQAECgQJBgADAAAAAA==.Ryoushen:BAAANQADCggJCAAAAA==.',
Sa='Sabele:BAAANQADCgEIAQABNQAECgEJAQADAAAAAA==.Sadie:BAAANQADCgUIDgAAAA==.Saintmichael:BAAANQADCgUICgAAAA==.Sapphism:BAACNQAFFIERAAMEAAYKuiCgAQA/AgAEAAYKex6gAQA/AgAOAAEKhiCBFQBtAAA1AAQKgScAAgQACQr/JD8CAKkDAAQACQr/JD8CAKkDAAAA.Sarai:BAAANQABCgUICQAAAA==.Sarbev:BAABNQAECoEcAAQaAAgKPBRRDgAlAgAaAAgKPBRRDgAlAgAbAAEKzwRoPAArAAAcAAEKyQfeGQAqAAAAAA==.Saskwatch:BAACNQAFFIEFAAICAAMKqAfnBQDWAAACAAMKqAfnBQDWAAA1AAQKgSMAAgIACQorGJYNAI8CAAIACQorGJYNAI8CAAAA.Savat:BAAANQAECgQIBQABNQAECgYJDQADAAAAAA==.Sayoko:BAAANQAECgUJDwAAAA==.Sayris:BAAANQAECgYJEgAAAA==.',
Sc='Scarymonster:BAAANQADCgIIAgAAAA==.Sckratchxx:BAAANQAECgUICQAAAA==.Scoochacho:BAAANQAECgYIDwAAAA==.',
Se='Senhunter:BAAANQAECgUICAAAAA==.Senmaster:BAAANQADCggIEQABNQAECgUICAADAAAAAA==.Sentrollock:BAAANQABCgIIAgABNQAECgUICAADAAAAAA==.Seradiin:BAAANQADCgEIAQAAAA==.Sereknight:BAAANQADCgQJBAAAAA==.',
Sh='Shakers:BAABNQAECoEgAAIOAAkKmh7ODwAkAwAOAAkKmh7ODwAkAwAAAA==.Shaleron:BAAANQADCgcICgAAAA==.Shamarq:BAAANQADCgcIGgAAAA==.Shamtastyc:BAAANQADCgUIBQABNQAECgQIBQADAAAAAA==.Shapewalker:BAABNQAECoEbAAIdAAgKRRZNBgAgAgAdAAgKRRZNBgAgAgAAAA==.Shayla:BAAANQADCgYICgAAAA==.Shaylina:BAAANQAECgQICwAAAA==.Shaylune:BAAANQADCggJEwABNQAECgQICwADAAAAAA==.Sheba:BAAANQABCgEIAQAAAA==.Shendhi:BAAANQABCgQIBAAAAA==.Sheoby:BAAANQABCgMJBAAAAA==.Shiftcen:BAAANQAECgQJBQAAAA==.Shintazhi:BAAANQAECgQICQAAAA==.Shirkan:BAABNQAECoEdAAIeAAgK+h+lAgDTAgAeAAgK+h+lAgDTAgAAAA==.Shojobeat:BAAANQAECgQIBAAAAA==.Shootypizza:BAAANQAECgcIBwABNQAFFAQJBgAfAC0VAA==.Shreddedbeef:BAAANQAECgUJCQAAAA==.Shwartz:BAAANQADCgQIBAAAAA==.',
Si='Simplicity:BAAANQAECgUIBgAAAA==.Sindrii:BAAANQAECgEJAQAAAA==.Sinhoi:BAAANQADCgUIBQABNQAECgEJAQADAAAAAA==.Sinku:BAAANQAECgIJAgAAAA==.Sinza:BAAANQADCgYJDAABNQAECgIJAgADAAAAAA==.Sixp:BAAANQADCgYICQABNQAECgkJIgAKAIcYAA==.',
Sk='Skadooshh:BAAANQADCgYJDQABNQAECgUJDwADAAAAAA==.Skarray:BAEANQAECgUJCQAAAA==.',
Sl='Slyraxis:BAAANQAECgQIBwAAAA==.',
So='Soleirra:BAAANQADCgEIAQABNQADCggICAADAAAAAA==.Sonas:BAAANQADCgcIDQAAAA==.Soohainao:BAAANQADCgcIDwABNQAECgkJIgAKAIcYAA==.Sorador:BAAANQADCgQIBwAAAA==.',
Sp='Spargelfürze:BAAANQADCgIIBAAAAA==.Spellgibson:BAAANQAECgcIDwAAAA==.Spiara:BAAANQABCgQIBAAAAA==.Spiraa:BAAANQADCggICAAAAA==.Spyroh:BAAANQAECgQICgAAAA==.',
St='Stealthgoat:BAAANQADCgQIBAAAAA==.Stinkyfeets:BAAANQABCgEJAQAAAA==.Stoogle:BAAANQAECggIEgAAAA==.Stormbrook:BAAANQAECgQJCgAAAA==.Stoutlager:BAAANQADCgYIBgAAAA==.Sturmdorf:BAAANQADCggJGAAAAA==.',
Su='Suhli:BAAANQADCgYJCgAAAA==.Sulfrick:BAAANQADCgcIGgAAAA==.Summannuz:BAAANQADCgIIAgAAAA==.',
Sv='Svurg:BAAANQAECgEJAQAAAA==.',
Sw='Sweetchi:BAAANQAECgUJCQAAAA==.',
Sy='Sybria:BAAANQAECgIIAgAAAA==.Sykko:BAAANQAECgIIAgAAAA==.Sylea:BAAANQAECgIIAgAAAA==.Sylverhunter:BAAANQABCgcICQABNQADCggJHgADAAAAAA==.Symet:BAAANQAECgEIAQAAAA==.',
['Så']='Såturn:BAAANQAECgMIBAAAAA==.',
Ta='Takaria:BAAANQAECgYJCAAAAA==.Takaris:BAAANQADCgcIBwAAAA==.Tal:BAEANQAECgIIAgAAAA==.Tankdium:BAAANQAECgUJBgAAAA==.Tapcon:BAAANQAECgIIAgAAAA==.Tape:BAAANQADCggJDwAAAA==.Tarlas:BAAANQAECgUJCgAAAA==.Tayllore:BAAANQAECgQJCgAAAA==.',
Te='Tearsheet:BAAANQADCgYIEwABNQAECgQJCgADAAAAAA==.Terah:BAAANQAECgUJCgABNQAFFAEIAQADAAAAAA==.Terendelev:BAAANQAECgcJEQAAAA==.Terrador:BAAANQAECgUICgAAAA==.Terramortua:BAABNQAECoEYAAIgAAkK1yMoBQCQAwAgAAkK1yMoBQCQAwABNQAFFAEIAQADAAAAAA==.Terraviridis:BAAANQAFFAEIAQAAAA==.',
Th='Thalassairi:BAAANQADCgMIAwABNQAECgQICQADAAAAAA==.Thaugtless:BAAANQADCgYJDAABNQAECgQICgADAAAAAA==.Thelonius:BAAANQAECgQIBgAAAA==.Therocksays:BAAANQAECgQJCgAAAA==.Thindead:BAAANQADCgIIAgABNQAECggJGQARAIUbAA==.Thinloc:BAABNQAECoEZAAQRAAgKhRudNgBDAgARAAcKjRqdNgBDAgAhAAQKrhgOJQAlAQAiAAEKCBtHHQBFAAAAAA==.Thinpal:BAAANQAECgIJAgABNQAECggJGQARAIUbAA==.Thragge:BAEANQAECgMIBAAAAA==.Thronjak:BAAANQAECgQJCgAAAA==.Thunderfury:BAAANQAECgUJCAAAAA==.',
Ti='Tidepod:BAAANQADCggIEAAAAA==.Tidêpod:BAAANQADCgYJBgAAAA==.Tienlong:BAAANQABCggJEQAAAA==.Tipride:BAABNQAECoEiAAMKAAkKhxiIOgARAgAKAAcKwRqIOgARAgALAAkKxQ9vOAAQAgAAAA==.Tiradis:BAAANQADCgMIAwAAAA==.Tiralie:BAAANQAECgQICAAAAA==.Tiryl:BAAANQADCggIGQAAAA==.',
Tn='Tnama:BAAANQADCgIIAgAAAA==.',
To='Togashi:BAAANQAECgQIBAAAAA==.Tolipes:BAAANQADCgYIBgAAAA==.Toogodly:BAAANQADCgcIDQAAAA==.Torent:BAAANQADCggIIAAAAA==.Toshinori:BAAANQADCgQJBAAAAA==.Totemdáddy:BAAANQAECgEIAwAAAA==.Tovëlo:BAAANQADCggJDgAAAA==.',
Tr='Treelight:BAAANQADCgEIAQAAAA==.Trehugga:BAAANQADCgcIBwAAAA==.Treldend:BAAANQADCgEJAQAAAA==.Trinogra:BAABNQAECoEgAAMEAAkKARiiEwB7AgAEAAkKsBeiEwB7AgAOAAEK7hfC6QBGAAAAAA==.Trunks:BAAANQAECgQICQABNQAECgUJDAADAAAAAA==.Trystern:BAAANQAECgQJCgAAAA==.',
Tu='Turmeric:BAAANQADCggIGgABNQADCggIJwADAAAAAA==.',
['Tä']='Tänya:BAAANQAECgQJCgAAAA==.',
Uh='Uhoh:BAAANQADCgUIBQAAAA==.',
Ul='Ultar:BAABNQAECoEbAAIQAAgKdSHfIADnAgAQAAgKdSHfIADnAgAAAA==.Ultodeesavag:BAAANQAECgQICQAAAA==.Ultradeath:BAAANQADCggICAAAAA==.',
Un='Undeadshaman:BAAANQAECgEIAgAAAA==.Unholyjinksy:BAAANQADCgUJBQAAAA==.Unvdi:BAAANQADCggJFQAAAA==.',
Va='Vaderrage:BAAANQAECgYICwAAAA==.Valeyria:BAAANQADCggJIAAAAA==.Valiyntha:BAAANQADCggJDwABNQAECgQICAADAAAAAA==.Valri:BAAANQADCgUJCQAAAA==.Vancasper:BAAANQAECgEJAQAAAA==.Varl:BAAANQADCgYICQABNQAECgkJIAARACshAA==.Varlock:BAABNQAECoEgAAQRAAkKKyHhFQDmAgARAAgKgCDhFQDmAgAiAAYKhR57BQDxAQAhAAQKIRJCKgAEAQAAAA==.Vasill:BAAANQAECgQJBAAAAA==.',
Ve='Velari:BAAANQAECgQJCgAAAA==.Velmathris:BAAANQAECgIIAgAAAA==.Ventnor:BAAANQADCgIIAgAAAA==.Veydh:BAAANQAECgYIDQAAAA==.Veymina:BAAANQADCgYJEgABNQAECgYIDQADAAAAAA==.',
Vi='Viinnee:BAAANQAECgQIBwAAAA==.Vilehart:BAAANQADCgMIAgABNQAECgQJBgADAAAAAA==.Vilya:BAAANQADCgYIBgAAAA==.Vincentlight:BAAANQADCggIHwAAAA==.Vixess:BAABNQAECoEeAAIGAAkKHRyQFQDUAgAGAAkKHRyQFQDUAgAAAA==.',
Vo='Voidpriest:BAAANQADCggICAAAAA==.Voidweaver:BAAANQADCgUICQAAAA==.Volteer:BAABNQAECoEYAAIaAAcKEQypFQCTAQAaAAcKEQypFQCTAQAAAA==.',
Vy='Vyara:BAAANQADCgIIAgABNQAECgUJDAADAAAAAA==.Vynddradoria:BAABNQAECoEbAAQiAAgKTBhFAwBlAgAiAAgKTBhFAwBlAgAhAAIKDQtyTgBxAAARAAEKigYW6AAyAAAAAA==.Vyndh:BAABNQAECoEVAAQjAAgKACRrBwA+AwAjAAgKACRrBwA+AwAdAAIKHRvMFQCbAAAkAAEKAwgzYAA5AAAAAA==.Vynlock:BAAANQAFFAEJAQAAAA==.Vynstaya:BAAANQADCgYJBgAAAA==.',
Wa='Walkerbowe:BAAANQAECgEJAQAAAA==.Walt:BAAANQAECgQJBwAAAA==.Wanderin:BAAANQAECgQJBgAAAA==.Wanderit:BAAANQADCgEIAQAAAA==.Waterbutcold:BAAANQAECgUJBgAAAA==.Waysmomtwo:BAAANQADCgYIBgAAAA==.',
We='Webby:BAAANQAECgUJDAAAAA==.',
Wh='Whiskerses:BAAANQAECgYJDwAAAA==.Whithers:BAAANQADCggIHQAAAA==.',
Wi='Wilmer:BAAANQAECgQJBAAAAA==.Wilyy:BAAANQAECgQIBQABNQAECggIHAAgAA4dAA==.Winterchild:BAAANQADCgIIAgAAAA==.',
Wo='Woodsylver:BAAANQADCggJHgAAAA==.Wookiee:BAAANQADCgQIBAAAAA==.Worski:BAAANQADCggIEQAAAA==.',
Wr='Wrathalthiel:BAAANQADCggIIQABNQAECgEIAQADAAAAAA==.Wratherael:BAAANQADCggIDQABNQAECgEIAQADAAAAAA==.Wraîth:BAABNQAECoEXAAIkAAgKowmZKQC/AQAkAAgKowmZKQC/AQAAAA==.',
Wy='Wynilla:BAAANQADCgcJGwAAAA==.',
Xa='Xanathar:BAAANQAECgMICAAAAA==.Xaphoris:BAAANQAECgEIAQABNQAECgQJCgADAAAAAA==.Xayleficent:BAAANQADCgYIBgAAAA==.Xaylia:BAAANQAECgQICgAAAA==.',
Xe='Xerhunt:BAAANQADCgUJBQABNQAECgQJCgADAAAAAA==.',
Xo='Xolotin:BAAANQADCgMJAwAAAA==.',
Ya='Yassi:BAAANQAECgUJCQAAAA==.',
Ye='Yelignar:BAAANQADCgUIBQAAAA==.',
Yn='Ynarii:BAAANQADCgQIBQAAAA==.Ynkdh:BAAANQAECgEIAQABNQAECggICQADAAAAAA==.',
Yo='Yoonhee:BAAANQAECgcIDgAAAA==.',
Yu='Yura:BAAANQADCgQIBQAAAA==.Yurtrus:BAAANQAECgIIAgAAAA==.',
Za='Zaghary:BAAANQAECgMJCQAAAA==.Zaphor:BAAANQADCgQIBAABNQAECgQJCgADAAAAAA==.Zarik:BAAANQADCgIIAwAAAA==.',
Ze='Zebjati:BAAANQAECgUJCQAAAA==.',
Zh='Zhend:BAAANQAECgUJCQAAAA==.',
Zo='Zoot:BAAANQADCgQIBAAAAA==.',
Zu='Zunch:BAAANQAECgEJAQAAAQ==.',
['Àz']='Àzazel:BAAANQAECgYJDgAAAA==.',
['Är']='Ärk:BAAANQAECgUICQAAAA==.Ärmistice:BAAANQAECgYIDgAAAA==.',
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
