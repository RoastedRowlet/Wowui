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

local lookup = {'DeathKnight-Blood','Hunter-BeastMastery','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Druid-Restoration','Warrior-Arms','Druid-Balance','Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Warlock-Demonology','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Priest-Discipline','Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Protection','Paladin-Protection','Druid-Feral','DeathKnight-Unholy','DemonHunter-Vengeance','Warrior-Fury','Monk-Mistweaver','Mage-Fire','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Ag='Agoobagoo:BAAANQAFFAIIAwABNQAFFAQICQABAFMaAA==.',
Al='Aliasx:BAAANQAECgQIBAAAAA==.Allarus:BAAANQADCgcICQAAAA==.Allwrong:BAAANQADCgQIBAAAAA==.Alotofsin:BAAANQAECgEIAQAAAA==.Alphadog:BAEBNQAECoEmAAICAAgKaiFGIQD1AgACAAgKaiFGIQD1AgAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAAANQAECgUICwAAAA==.Aminatou:BAABNQAECoEZAAIDAAgKURC6MwDcAQADAAgKURC6MwDcAQAAAA==.',
Ar='Ariaddne:BAABNQAECoEZAAQEAAgKTBZOEQA0AgAEAAgKmBROEQA0AgAFAAUKqRK4oAAkAQAGAAEKwRjD+gBCAAAAAA==.Artemîs:BAAANQAECgEIAQAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAABNQAFFIEHAAIHAAMKABMMDgDpAAAHAAMKABMMDgDpAAAAAA==.Augy:BAABNQAECoEiAAMIAAgK0B0JBgBIAgAIAAcKkxsJBgBIAgAJAAcKJRsNEwD/AQAAAA==.',
Ba='Bakuretsu:BAAANQAECgQIBAABNQAECgkJJQAKAKYbAA==.Barhead:BAAANQADCggIDgAAAA==.Barlow:BAAANQAECgYIBgAAAA==.',
Bb='Bbldrizzy:BAACNQAFFIELAAIFAAUKHSFhBgDpAQAFAAUKHSFhBgDpAQA1AAQKgSYAAgUACQrgJPgMAHMDAAUACQrgJPgMAHMDAAAA.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECggIHQALAGUdAA==.Beastlièduke:BAAANQADCgIIAgABNQAECggIHQALAGUdAA==.Belephon:BAAANQADCgYICAAAAA==.Belinda:BAAANQADCggIFwAAAA==.',
Bi='Bighunt:BAAANQAECgMIAwAAAA==.Bijju:BAAANQAECggIDAAAAA==.Binggus:BAABNQAECoEWAAIMAAgK9R6yTgCDAgAMAAgK9R6yTgCDAgAAAA==.',
Bl='Blabbybootze:BAAANQAECgYIEAAAAA==.Bladelight:BAAANQADCgcJDAAAAA==.Blighte:BAAANQAECgQIBAABNQAECgkJJAANACIeAA==.Blightfangs:BAAANQAECgYICQAAAA==.Bluzey:BAAANQADCgYIBgAAAA==.',
Bo='Bodakye:BAAANQAECgcIDwAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQAECgUIBQAAAA==.',
Br='Bracalina:BAAANQAECgEIAQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgEIAQAOAAAAAA==.Brorgy:BAAANQAECgUIEgAAAA==.Brovahkin:BAAANQABCggIEAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Buzzbuzz:BAAANQAECgMIBAAAAA==.',
By='Bywar:BAAANQADCgcICwAAAA==.',
['Bé']='Bébop:BAAANQAECggICAAAAA==.',
Ca='Caeruleus:BAAANQADCgQJBAAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAABNQAECoEhAAIPAAgKBBGYMgDZAQAPAAgKBBGYMgDZAQAAAA==.Chapelgnome:BAAANQADCgUJBQABNQAECgUIEgAOAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAABNQAECoEcAAMQAAcKCA+DrQCMAQAQAAcKCA+DrQCMAQARAAUKegf/tADpAAAAAA==.Chickenslop:BAAANQADCggIFgAAAA==.Chiptime:BAAANQAECgQICwAAAA==.Chri:BAAANQAECgQIBwAAAA==.Chrri:BAAANQAECgEIAQAAAA==.Chungotron:BAABNQAFFIEGAAIQAAQKlwjtDgAfAQAQAAQKlwjtDgAfAQAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Cl='Cladon:BAAANQAECggICAAAAA==.Clairity:BAAANQADCgcIBwAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAFFAMICAASAKcTAA==.Cormogh:BAAANQADCggJCwAAAA==.Cowhealer:BAABNQAECoEkAAMNAAkKIh7ZGQDfAgANAAkKIh7ZGQDfAgALAAMKGAoGTwCfAAAAAA==.',
Cr='Craeftig:BAAANQAECgcIEQAAAA==.Craeftigdk:BAAANQAECgYIEQABNQAECgcIEQAOAAAAAA==.Craeftigtwo:BAAANQADCggJDQABNQAECgcIEQAOAAAAAA==.Craeftigwl:BAAANQAECgIIAgABNQAECgcIEQAOAAAAAA==.Crepitus:BAABNQAECoEWAAMTAAYKTQqGKQBfAQATAAYKTQqGKQBfAQAUAAIKggThfQBdAAAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQAECgcICwABNQAECgcIEQAOAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgQIEQAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQAECgEIAQAOAAAAAA==.',
Da='Daamdam:BAAANQAECggICAAAAA==.Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Dariian:BAAANQAECggIBgAAAA==.Darkbeef:BAABNQAECoEVAAIVAAYKGwOB2wDmAAAVAAYKGwOB2wDmAAAAAA==.Darkjusticeh:BAAANQAECgUIBwAAAA==.Darlang:BAAANQAECgEIAQAAAA==.Darthbjóurn:BAAANQAECgUIBQAAAA==.Darthsyde:BAAANQAECgcICQAAAA==.',
De='Deadergriff:BAAANQAECgUIDgAAAA==.Deadicated:BAAANQAECgUIDwAAAA==.Deadinsíde:BAAANQAECggICAABNQAECggIEAAOAAAAAA==.Deathmark:BAAANQADCgYIBgAAAA==.Deeznutzs:BAAANQAECgYIBQAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQAECgUIBgAAAA==.Desunaito:BAACNQAFFIEJAAIPAAMKCRbACgDqAAAPAAMKCRbACgDqAAA1AAQKgS0AAg8ACQo4Ix8KADYDAA8ACQo4Ix8KADYDAAAA.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggICgABNQAFFAYICwAMAMgVAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dk='Dkzilong:BAAANQAECgEIAQABNQAFFAYICwAMAMgVAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECggIIAAWAMoYAA==.Docwyle:BAABNQAECoEgAAIWAAgKyhgKHwA6AgAWAAgKyhgKHwA6AgAAAA==.Doozey:BAAANQABCgcJBwAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQAECgEIAQAAAA==.Dracowulf:BAAANQAECgUIEQAAAA==.Dragonx:BAAANQAECgQIEwAAAA==.Drakowolf:BAAANQAECgYICQAAAA==.Drama:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECoEsAAIRAAgKeRojNwBrAgARAAgKeRojNwBrAgAAAA==.Dreorge:BAABNQAECoEXAAIHAAkKNBWOEQB+AgAHAAkKNBWOEQB+AgAAAA==.Drewceratops:BAABNQAECoEXAAIQAAgKZA42mgC4AQAQAAgKZA42mgC4AQAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAAANQAFFAEIAQAAAA==.Drogô:BAAANQAECgQIBAAAAA==.Dromgar:BAAANQAECggICAAAAA==.Dromkyr:BAABNQAECoEiAAIHAAgKFxBlHQDYAQAHAAgKFxBlHQDYAQAAAA==.Drossiechan:BAABNQAECoEYAAIXAAkKwRi3FwBiAgAXAAkKwRi3FwBiAgAAAA==.',
Du='Duellipa:BAAANQAECgQICQABNQAECgUIEgAOAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggJBwAAAA==.',
Ef='Effloria:BAABNQAECoEhAAILAAgK9yPFBwAyAwALAAgK9yPFBwAyAwAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.',
El='Elauvia:BAAANQAECgUICAAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
Em='Emleah:BAAANQAECgEIAgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQAECgQJBAABNQAECgYIEwAOAAAAAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwABNQAECgYIEwAOAAAAAA==.Encoremts:BAAANQAECgEIAQABNQAECgYIEwAOAAAAAA==.Encorep:BAAANQAECgYIEwAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQAECgYICQAAAA==.Fallingvoid:BAAANQAFFAIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgAOAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgAOAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fe='Fextardo:BAAANQADCgYIBgAAAA==.',
Fi='Finaliter:BAABNQAECoEqAAIQAAkK0huPOwDAAgAQAAkK0huPOwDAAgAAAA==.',
Fl='Flamingdrago:BAAANQAECgQIBQAAAA==.Flirtyflurry:BAAANQAECgQIBgAAAA==.',
Fo='Fox:BAACNQAFFIEJAAMUAAMKGho/CgAJAQAUAAMKGho/CgAJAQAYAAIK8hJmAgCZAAA1AAQKgTAAAxgACQoTJPEBAEEDABgACQp0IvEBAEEDABQABwoaHvIcAG0CAAAA.',
Fr='Fremder:BAAANQAECgUJBgAAAA==.Froggy:BAABNQAECoERAAIWAAkKzAVwNAB5AQAWAAkKzAVwNAB5AQAAAA==.Frogleap:BAAANQADCgUIBQABNQAECgkJEQAWAMwFAA==.Frogred:BAAANQADCgQIBAABNQAECgkJEQAWAMwFAA==.Frogtoad:BAAANQAECgEIAQABNQAECgkJEQAWAMwFAA==.',
Fu='Funeral:BAACNQAFFIEfAAQZAAcKIB+IAACFAQAZAAQKvRyIAACFAQAVAAQK8RxKDQBzAQAaAAEKThZ7BgBhAAA1AAQKgScABBkACQrnJTEBAIEDABkACQrpJDEBAIEDABUABgrmJFdPAEYCABoAAQrPDHItADEAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQADCgEIAQAAAA==.',
Fy='Fyjhrt:BAABNQAECoEbAAIYAAcK1R9TBQCCAgAYAAcK1R9TBQCCAgAAAA==.',
Ga='Galladin:BAAANQAECgMIBAAAAA==.Gallory:BAAANQAECggIBgAAAA==.Gayanall:BAAANQADCgMIAwAAAA==.',
Gd='Gdk:BAAANQAECgMIBAABNQAECggIIgAFAJIYAA==.Gdkdrake:BAAANQADCgUIBQABNQAECggIIgAFAJIYAA==.Gdkhunter:BAAANQADCggICAABNQAECggIIgAFAJIYAA==.Gdkmage:BAAANQAECgUICgABNQAECggIIgAFAJIYAA==.Gdkman:BAABNQAECoEiAAQFAAgKkhiQPwBNAgAFAAgKkhiQPwBNAgAGAAIKlwi28QBUAAAEAAEKfguNLgBAAAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECggIIgAFAJIYAA==.',
Ge='Geoprince:BAAANQADCgcIEAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIFAAAAA==.Ghoulfriend:BAAANQADCgUICgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAABNQAECoEZAAMUAAkKjh/bCAAzAwAUAAkKjh/bCAAzAwATAAQKnAV2OwC2AAABNQAFFAUICwAFAB0hAA==.Githrogathan:BAAANQAECgUIDgAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgAOAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.Gragasfat:BAAANQAECgIIAgAAAA==.Groundnpound:BAAANQADCgUJBQAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgkJKgACAGkNAA==.',
['Gö']='Gödhand:BAAANQAECgMIAwAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Harrypooc:BAAANQADCgQJBAAAAA==.Hasaro:BAABNQAECoEpAAIbAAkKwQzTGQCXAQAbAAkKwQzTGQCXAQAAAA==.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQAECgQICgAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQAECgMIBQAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.Helzer:BAAANQADCggIDwABNQAECggIIAAGAFEZAA==.',
Ho='Holybaphomet:BAAANQADCgUICQAAAA==.Holyfarts:BAABNQAECoEsAAQcAAkKJyEpAQA+AwAcAAkKrh4pAQA+AwAdAAgKqh53JwCuAgAeAAgKSxVYIQAGAgAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAFFAUIDwAfAJUOAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCggIGgAAAA==.',
Hx='Hx:BAAANQADCgYJDwAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.',
['Hõ']='Hõnor:BAABNQAECoEsAAMMAAkK9SHgHgAuAwAMAAkKxiDgHgAuAwAgAAUK+yBkEwDCAQABNQAECgkJKgAPAHMmAA==.',
Ia='Iammoo:BAAANQAECgIIAgAAAA==.',
Ig='Igriss:BAAANQAECgYIDgAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.Illuminaughd:BAAANQAECgMIBQAAAA==.Ilumii:BAAANQAECgMIAwAAAA==.Ilydris:BAAANQADCgIIAwAAAA==.',
Im='Imonthegcd:BAAANQAECgYIBgABNQAECgkJKgAPAHMmAA==.',
In='Infinitepain:BAABNQAECoEnAAIdAAkKbyDREAAsAwAdAAkKbyDREAAsAwAAAA==.Innodk:BAAANQAECgYIDAAAAA==.',
Ir='Irami:BAAANQAECgEIAQAAAA==.Iridellis:BAAANQADCgcIBwABNQAECggILAARAHkaAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jahjahblinks:BAAANQADCgYIFAABNQAECgkJKgACAGkNAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAABNQAECoEcAAIhAAgKrB8ODgCWAgAhAAgKrB8ODgCWAgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgMIBwAAAA==.',
Jo='Joedingle:BAAANQAECgUIEgAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAABNQAECoEYAAIQAAcKFhOjsgCBAQAQAAcKFhOjsgCBAQAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ju='Jumpy:BAAANQABCgMIAwAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgkJLQAiAEEkAA==.Kaitokit:BAABNQAECoE7AAMBAAkKNR9pDgAqAwABAAkKNR9pDgAqAwAjAAgKpA/5UwCaAQAAAA==.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAAANQAECgcIEgAAAA==.Kamera:BAABNQAECoEaAAQQAAkKHhzOWgBdAgAQAAgKeB3OWgBdAgARAAMK9gUK5gCBAAAhAAEKVBEGZQAuAAAAAA==.Kandessa:BAAANQADCgIJAwAAAA==.Kaylah:BAABNQAECoEeAAMYAAgKOCH5AgD+AgAYAAgK6iD5AgD+AgAUAAYKSx4bMgDcAQAAAA==.Kayllina:BAAANQAECgUIDAAAAA==.Kayotic:BAAANQAECgIIAwAAAA==.',
Ke='Kelmorphic:BAABNQAECoEhAAIkAAgKTCGrAwD8AgAkAAgKTCGrAwD8AgAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAFFAMICAASAKcTAA==.',
Ko='Kosmas:BAAANQAECgEJAQAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBgAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurisuw:BAAANQAECgIIAgAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQAECgUICAAAAA==.',
Ky='Kyarina:BAAANQABCggIDwAAAA==.',
['Kí']='Kíller:BAAANQAECgQICQAAAA==.',
La='Lamadda:BAAANQADCgUIBQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Le='Leafdaddy:BAAANQAECgUICQABNQAECgkJJgAKAGccAA==.Lelise:BAAANQAECggIDAAAAA==.Letusgiveita:BAAANQADCgQIBAAAAA==.',
Li='Lightbringr:BAAANQADCgYICwAAAA==.Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilpapi:BAAANQAECgYIBgABNQAECgkJIQAbAH8lAA==.Lilymei:BAAANQADCggIGAAAAA==.Linesondra:BAAANQADCgUICQAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAABNQAECoEhAAICAAgK7A68aQAUAgACAAgK7A68aQAUAgAAAA==.Livalifa:BAAANQAECgIIAgAAAA==.',
Lo='Lockenload:BAAANQAECgUIDAAAAA==.Lockme:BAAANQADCgUIBQAAAA==.Lohhar:BAAANQADCggIDgAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMJBQAAAA==.',
Lu='Lucens:BAABNQAECoEaAAIRAAgKXBD2XQDbAQARAAgKXBD2XQDbAQAAAA==.Lucerna:BAAANQAECgMIAwAAAA==.Lurchdh:BAEANQADCgQJBAABNQAECgkJVgAfAA4bAA==.Lurchdruid:BAEANQAECgIIAQABNQAECgkJVgAfAA4bAA==.Lurchmage:BAEANQAECggIEgABNQAECgkJVgAfAA4bAA==.Lurchn:BAEBNQAECoFWAAMfAAkKDhs1BADJAgAfAAkKDhs1BADJAgASAAkKrQdT1AC4AQAAAA==.',
Ly='Lyricai:BAAANQAECgUIDwAAAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Maemae:BAAANQADCgYICwAAAA==.Magallanes:BAAANQAECgQIBAAAAA==.Mapleleaf:BAAANQAECgQIBAAAAA==.Markyy:BAABNQAECoEgAAQQAAkKpiQ/CACwAwAQAAkKpiQ/CACwAwARAAQKLRCisgDuAAAhAAEKYSBXVQBbAAABNQAECgkJKgAPAHMmAA==.Matas:BAAANQAECgQICAAAAA==.Maylinfenora:BAABNQAECoEYAAIUAAcKhgwAPACgAQAUAAcKhgwAPACgAQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAABNQAECoEeAAIMAAgKRRGXhADrAQAMAAgKRRGXhADrAQAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Minisan:BAAANQADCgEIAQAAAA==.Misary:BAAANQAECgIIAgAAAA==.Mistake:BAAANQAECgUJCAAAAA==.',
Mo='Mogyar:BAABNQAECoEbAAIQAAcKLRdskQDNAQAQAAcKLRdskQDNAQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQAECgMIBgAAAA==.Monkeli:BAABNQAECoEaAAIlAAcKAhYDCwDxAQAlAAcKAhYDCwDxAQAAAA==.Moocifer:BAAANQADCgUIBwAAAA==.Moocifermoo:BAAANQADCgUIBQAAAA==.Moogrim:BAAANQADCggIEAAAAA==.Moonsiand:BAEBNQAECoEiAAICAAgKlx5GLQDEAgACAAgKlx5GLQDEAgABNQAECggIJgACAGohAA==.Moreldwiddle:BAAANQAECgQICgAAAA==.Morgaia:BAAANQAECgUIBQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAAANQAECgUIDwAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Ms='Mshottie:BAAANQAECgEIAQAAAA==.',
Mx='Mx:BAAANQADCgYIDwAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgcIEwAAAA==.Mythranite:BAAANQADCgMIAwAAAA==.Myway:BAAANQADCggICAAAAA==.',
['Mó']='Mócha:BAAANQAECgQIDQAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.',
Ne='Nekiron:BAAANQADCgQIBAAAAA==.Nellaa:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Nettik:BAAANQADCgUIBwAAAA==.Neverborn:BAABNQAECoEXAAINAAcK8w1VTwB3AQANAAcK8w1VTwB3AQAAAA==.',
Ni='Nightrage:BAAANQAECgMIBgAAAA==.Nilex:BAAANQAECgQIBAAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQAECgUIBQABNQAECggIIwASAFUhAA==.',
Nu='Numera:BAAANQADCgIIAwABNQAECgcICgAOAAAAAA==.Nutellaqq:BAABNQAECoEYAAISAAcKoht9mAAyAgASAAcKoht9mAAyAgAAAA==.',
Ob='Obeseotter:BAABNQAECoEuAAISAAgK7xdIiABUAgASAAgK7xdIiABUAgAAAA==.Oborax:BAEANQAECgYICgABNQAECggIJgACAGohAA==.',
Od='Od:BAAANQAECgIIAgAAAA==.',
Ol='Oliviabenson:BAAANQAFFAEIAQAAAA==.',
Ox='Oxsidius:BAAANQAECgQIBwAAAA==.',
Pa='Paldi:BAAANQAECgQIBAABNQAECgYIBgAOAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECggIDwAAAA==.Pariss:BAAANQADCgUIBQABNQAECggIEAAOAAAAAA==.Paws:BAAANQAECgUIDgAAAA==.Pawse:BAAANQADCggIDwAAAA==.',
Pe='Peaky:BAABNQAECoEjAAQmAAcKpwlQKgDyAAAmAAcKpwlQKgDyAAAKAAUKfQMLIgCkAAAXAAIKgAEaYgAsAAAAAA==.Perelia:BAAANQAECgYIEgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQAECgQICwAAAA==.Pooche:BAAANQAECgIIAwAAAA==.Popcola:BAAANQAECgQICQAAAA==.Powerpaladin:BAAANQABCgQIBAAAAA==.',
Pp='Ppc:BAAANQAECgQIBAABNQAFFAMICAASAKcTAA==.',
Pr='Prezu:BAEBNQAECoEVAAIHAAcKnA5wJgBkAQAHAAcKnA5wJgBkAQABNQAECggIDwAOAAAAAA==.Procyonx:BAAANQAECgEIAQAAAA==.Prophofdoom:BAABNQAECoEWAAIgAAcKGSLdCACYAgAgAAcKGSLdCACYAgAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAACNQAFFIEIAAISAAMKpxO7KgDzAAASAAMKpxO7KgDzAAA1AAQKgR8AAxIACQoPIaM3AAwDABIACQoPIaM3AAwDACcAAQqaAG4NACUAAAAA.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAAOAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Rastaqwon:BAAANQAECgEIAQAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Renoitukax:BAAANQAECgMIBAAAAA==.Restfuldark:BAAANQADCggICAAAAA==.Retrobution:BAABNQAECoEYAAIQAAkKQx8pJgASAwAQAAkKQx8pJgASAwAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Rockstéady:BAAANQAECggICAAAAA==.Roopall:BAABNQAECoEXAAIRAAgKOyCdHQDmAgARAAgKOyCdHQDmAgAAAA==.',
Ry='Rynzu:BAAANQAECgMIBAAAAA==.Ryzen:BAAANQAECgYICgAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAABNQAECoEZAAIhAAYK0QwKMwAgAQAhAAYK0QwKMwAgAQAAAA==.Sanshift:BAAANQADCgcICwAAAA==.Satansimp:BAAANQAECgIIAgAAAA==.',
Sc='Schadnfreude:BAABNQAECoEvAAQPAAkK8h08DgAGAwAPAAkK8h08DgAGAwABAAEKswtuwAAsAAAjAAEK1gdZ2QAnAAAAAA==.Schezmu:BAAANQAECgUICAAAAA==.',
Se='Sean:BAAANQADCgUICgAAAA==.Senorfiesta:BAAANQAECgUIDQAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAAANQAECgUIEgAAAA==.Shamans:BAAANQAECgQIBQAAAA==.Shambalaya:BAAANQAECgQIBAAAAA==.Shaokhan:BAAANQAECgQICQAAAA==.Shasta:BAABNQAECoEhAAIbAAkKfyVQAQDGAwAbAAkKfyVQAQDGAwAAAA==.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAABNQAECoEuAAMoAAkKXCMFAQByAwAoAAkKXCMFAQByAwACAAEKZRcHKwFJAAAAAA==.Shyx:BAABNQAECoEeAAMdAAgKdh4GHwDZAgAdAAgKdh4GHwDZAgAcAAEKjRmnIQBCAAAAAA==.',
Si='Simplèjack:BAABNQAECoEYAAISAAcKQwhb7gCHAQASAAcKQwhb7gCHAQAAAA==.Sinamon:BAAANQAECgMIBAAAAA==.Sinani:BAAANQADCgUJBQAAAA==.Sinnamon:BAAANQABCgQJBAABNQAECgMIBAAOAAAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgkJIQAMAGoYAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skram:BAAANQAECgQIBAABNQAECggIKwAQAA8OAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAAANQAECgcIDgAAAA==.',
Sm='Smallkat:BAAANQAECgUIBQAAAA==.Smirksfotm:BAAANQAECgUICAABNQAECggIEAAOAAAAAA==.Smoketail:BAAANQAECgUIBwAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYJCQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAABNQAECoEcAAMQAAcKIQnMxgBVAQAQAAcKIQnMxgBVAQAhAAIKBwXqXgA8AAAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Spikeprotein:BAAANQABCggICQAAAA==.Sprayandpray:BAAANQAECgMIBQAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQAECgMIAwAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQAECgUICQAAAA==.Susanno:BAAANQADCgUJCwAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQAECgEIAQAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgYIDQAOAAAAAA==.Talonflame:BAABNQAECoEgAAMpAAcKlBU1LQC9AQApAAcKkBI1LQC9AQACAAMKOhf89wDdAAAAAA==.Talonted:BAAANQAECgIIAgAAAA==.Tansu:BAAANQADCgcIDQAAAA==.Taterpuff:BAAANQABCgUIBQAAAA==.Taupo:BAAANQAECgEIAQAAAA==.Taxidermy:BAAANQADCgYIDAAAAA==.',
Te='Telarinda:BAAANQAECgIIAgAAAA==.',
Th='Thicclich:BAAANQAECgMIAwAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thinmint:BAAANQADCgYIBgAAAA==.Thisismeta:BAAANQAECgYICgAAAA==.Thorynwar:BAACNQAFFIEPAAIMAAUKAxgyDgCfAQAMAAUKAxgyDgCfAQA1AAQKgSEAAgwACQrkIEsdADUDAAwACQrkIEsdADUDAAE1AAQKCQklACMAZSYA.Thorýn:BAABNQAECoElAAMjAAkKZSaXDABAAwAjAAkKZSaXDABAAwABAAcKKxqKPQDrAQAAAA==.Thórin:BAAANQAECgYIDQAAAA==.',
Ti='Tierax:BAABNQAECoEgAAMTAAkKoR/wBwDwAgATAAgK8CDwBwDwAgAUAAIK8RmtcACYAAAAAA==.Tipsy:BAABNQAECoEZAAIGAAgKWxLOVgDfAQAGAAgKWxLOVgDfAQAAAA==.',
To='Tojì:BAAANQAECggIEAAAAA==.Tomfoolary:BAAANQADCgQIBAAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQAECgQIBAAAAA==.Torultrear:BAAANQAECgIJAgAAAA==.Tot:BAABNQAECoEhAAIGAAgKtw0nbQCVAQAGAAgKtw0nbQCVAQAAAA==.',
Tr='Tralleth:BAAANQAECgUIEAAAAA==.Trallock:BAAANQADCggIDgAAAA==.Traumatized:BAAANQADCgUIBwAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tu='Tuskyrex:BAAANQABCgIIAgAAAA==.',
Tw='Twinklord:BAAANQAECgYICwAAAA==.Twostroke:BAABNQAECoEYAAICAAkKsyOJBAC2AwACAAkKsyOJBAC2AwAAAA==.Twretwtwrewr:BAAANQADCgIIAgAAAA==.Twunkie:BAAANQADCgcIBwAAAA==.',
Ty='Tylopally:BAAANQAFFAIIAgAAAA==.Tyloremixdd:BAAANQADCgYIBwAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAECgkJKgAPAHMmAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCggIDgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECggIHAAhAKwfAA==.Vaeelrundor:BAABNQAECoEUAAICAAUKzgsG2AAeAQACAAUKzgsG2AAeAQAAAA==.Valyr:BAAANQADCgQIBAAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQADCgYIBwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQAECgUIDAAAAA==.Vedexd:BAABNQAECoEiAAICAAcKbg75kAC1AQACAAcKbg75kAC1AQAAAA==.Velarael:BAAANQAECgUIDQAAAA==.Veletharia:BAAANQADCgQIBAAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCggJDgAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAABNQAECoEiAAMVAAkKxBysOACPAgAVAAkKcRysOACPAgAZAAIKah2jQgCvAAAAAA==.Wastedsage:BAAANQAECgUICAAAAA==.Waterlou:BAAANQADCgIJAgAAAA==.',
Wh='Whatuphuz:BAAANQADCggIEAAAAA==.Wheresmyjaw:BAABNQAECoEkAAMVAAkKvBp1SQBYAgAVAAgKZxp1SQBYAgAZAAMKbRNpOQDQAAAAAA==.',
Wi='Wildthree:BAAANQAECgYIDgAAAA==.Wilkieswar:BAAANQADCggIEgABNQAECggIIAASACIgAA==.Willenda:BAAANQAECgEIAQAAAA==.Winterfall:BAAANQADCggIEAAAAA==.',
Wu='Wuinn:BAACNQAFFIEOAAIHAAYKfQmSBwClAQAHAAYKfQmSBwClAQA1AAQKgR0AAgcACQqUFCsTAGYCAAcACQqUFCsTAGYCAAAA.',
Xa='Xakutioner:BAABNQAECoEjAAINAAgKixxaIQCkAgANAAgKixxaIQCkAgAAAA==.Xaldiir:BAABNQAECoEXAAIDAAgKgBsEIQBsAgADAAgKgBsEIQBsAgAAAA==.',
Xe='Xenvoroo:BAAANQADCgIIAgAAAA==.Xerexia:BAABNQAECoEzAAIMAAgKQA03jQDUAQAMAAgKQA03jQDUAQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Xz='Xzarlatan:BAAANQADCgIIAgAAAA==.Xzarlatanfi:BAAANQADCgUIBQAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAABNQAECoEkAAIRAAkKEhkFJgC6AgARAAkKEhkFJgC6AgAAAA==.',
Yj='Yjn:BAAANQAECgcICAAAAA==.',
Yo='Yongyong:BAAANQAECgQICQAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAABNQAECoEfAAISAAgKgxVmmQAwAgASAAgKgxVmmQAwAgAAAA==.',
Za='Zalvianna:BAAANQAECgUIBgAAAA==.Zarathoz:BAAANQABCgYJBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgAOAAAAAA==.',
Ze='Zennith:BAAANQAECggIBwAAAA==.Zennithz:BAAANQAECggIEAAAAA==.Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilongmage:BAAANQAECgUJBQABNQAFFAYICwAMAMgVAA==.Zilongwar:BAACNQAFFIELAAIMAAYKyBUjDQCtAQAMAAYKyBUjDQCtAQA1AAQKgRsAAgwACQqqIk4jABwDAAwACQqqIk4jABwDAAAA.',
Zo='Zonecw:BAAANQAECgcIDgAAAA==.Zonedk:BAAANQAECgQIBgABNQAECgcIDgAOAAAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQAECgEIAQAOAAAAAA==.',
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
