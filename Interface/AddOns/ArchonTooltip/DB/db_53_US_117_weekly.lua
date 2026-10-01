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

local lookup = {'Warrior-Arms','Warrior-Fury','Unknown-Unknown','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Paladin-Retribution','Shaman-Elemental','Monk-Mistweaver','Priest-Holy','Warrior-Protection','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Restoration','Hunter-Marksmanship','DemonHunter-Devourer','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Blood','Priest-Shadow','DeathKnight-Frost','Paladin-Holy','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAABNQAECoEbAAMBAAkK0h74LADbAgABAAkKNx74LADbAgACAAEKxhexJABCAAAAAA==.',
Ad='Adielia:BAAANQAECgUIDQAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgMIAwAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCggIFQABNQAECgUIDAADAAAAAA==.Airflash:BAABNQAECoEpAAIEAAgK2SN+CAAiAwAEAAgK2SN+CAAiAwAAAA==.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQAECggIDwABNQAECgkJHwAFADMgAA==.',
Al='Alexious:BAABNQAECoElAAIGAAkK9CHQBAA9AwAGAAkK9CHQBAA9AwAAAA==.Aloonarn:BAAANQAECgQICAAAAA==.Alopix:BAAANQAECgUICgAAAA==.Alulla:BAACNQAFFIEIAAMBAAMKbRoIFAAFAQABAAMKbRoIFAAFAQACAAEKwRjdAwBLAAA1AAQKgRkAAwIACQqOHvYGADoCAAEACAo6HmM3ALECAAIABwqKHvYGADoCAAAA.Alunira:BAAANQAECgcIEwAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQAECgUICgAAAA==.Angrywar:BAAANQAECgYIDwAAAA==.Anharon:BAAANQADCgYIBwAAAA==.Ansatz:BAAANQAECgEIAgABNQAECgkJHgAHANAVAA==.',
Ap='Apokalypto:BAAANQADCgYIBwAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYJCQAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQAECgQIBwAAAA==.Asteriia:BAAANQAECgYIDwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQAECgEIAQABNQAECgcIGwAIAH0GAA==.',
Az='Azarazan:BAAANQADCgYICgAAAA==.Azka:BAABNQAECoEbAAIJAAkKPR+VHQAgAwAJAAkKPR+VHQAgAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAAANQAECgUIDAAAAA==.Baelmon:BAAANQADCgcIEgAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUIBwAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYIBgAAAA==.Bast:BAABNQAECoEfAAIFAAkKMyAZAgA9AwAFAAkKMyAZAgA9AwAAAA==.Basthara:BAAANQAECgcICQABNQAECgkJHwAFADMgAA==.',
Be='Belphegor:BAAANQADCgUIBQABNQAECgQICAADAAAAAA==.Benif:BAACNQAFFIEIAAIBAAQKhRRFDwBPAQABAAQKhRRFDwBPAQA1AAQKgR4AAgEACQqkJFoOAHUDAAEACQqkJFoOAHUDAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECoEXAAIKAAgKeBebOwA/AgAKAAgKeBebOwA/AgAAAA==.Bewblover:BAAANQADCgcIDQAAAA==.',
Bi='Bigbitehotdo:BAABNQAECoEfAAMEAAgK4B9JDwCzAgAEAAgK4B9JDwCzAgALAAEK3wFsRAAjAAAAAA==.Bighoney:BAAANQAECgEIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggJDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAAANQAECgEIAgAAAA==.Blueboy:BAAANQAECgYIDAAAAA==.',
Bo='Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQADCgEIAQAAAA==.',
Br='Braugorlle:BAAANQAECgMJAwABNQAECgkJIAAKAEUfAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcJBwADAAAAAA==.',
Bu='Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgIIAgAAAA==.',
Ca='Cambrier:BAABNQAECoEhAAMCAAgKtSG1AgACAwACAAgKqCC1AgACAwABAAIK7Rkn6QCmAAAAAA==.Cameraop:BAAANQAECgYIEQAAAA==.Capriestsun:BAAANQAECgEIAQAAAA==.Cardinal:BAAANQADCgYIDQAAAA==.Carynden:BAAANQADCgUIBQAAAA==.Castbo:BAAANQAECgUIBgABNQAFFAUIDgAMABAQAA==.',
Ce='Celilinia:BAAANQAECgEIAQAAAA==.Cellesstia:BAAANQADCgMIBQABNQADCgUIDwADAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAECggICwADAAAAAA==.Chalastorm:BAAANQADCgYIBwABNQAECggICwADAAAAAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgQIBQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQADCgUIBQAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEJAQAAAA==.',
Cr='Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgIIAgAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAAANQAECgQICAAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAQICQANAMEKAA==.',
Da='Dadstonks:BAAANQABCgYJCAAAAA==.Dameiyo:BAAANQAECgQIBAAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAAANQAECgUIDgAAAA==.Dankbo:BAACNQAFFIEOAAMMAAUKEBCsDQBTAQAMAAQKpxOsDQBTAQAOAAMKcgZwAQDfAAA1AAQKgTEAAw4ACQpwItYBAPYCAA4ACAq6INYBAPYCAAwACQrWHcweAL8CAAAA.Darkcoffee:BAAANQAECgQIBAAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgcIEAADAAAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCgYIDwAAAA==.Devildj:BAAANQAECgYIDAAAAA==.Dezadian:BAAANQAECgQIBgAAAA==.',
Dh='Dhampyra:BAAANQAECgcIEAAAAA==.',
Di='Didicoralie:BAAANQADCgEJAQAAAA==.Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgUIBgAAAA==.Disolve:BAAANQAECggICQAAAA==.Dixxonciderr:BAABNQAECoEzAAMPAAkKdx29BgAfAwAPAAkKdx29BgAfAwAQAAUKwgywHwAWAQAAAA==.',
Dm='Dmoe:BAAANQAECgIIBAAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQADCgYIDAAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dribby:BAAANQADCgUIBQAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECgcIGwAIAH0GAA==.Duplicate:BAACNQAFFIEGAAMRAAMKuQ7CBACZAAARAAIKbg7CBACZAAASAAIK3QdEOwB/AAA1AAQKgSAAAxIACQpOGVtuAG4CABIACQpOGVtuAG4CABEAAQonG+AwAEoAAAAA.Dustdruid:BAABNQAECoEfAAITAAgKRSHzFQDuAgATAAgKRSHzFQDuAgAAAA==.Dustlock:BAAANQAECgcICwAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECoEkAAIBAAkKWBE7aQAKAgABAAkKWBE7aQAKAgAAAA==.',
El='Eleshmelly:BAAANQADCgUIBQAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECoEbAAIUAAgKARTtGQAZAgAUAAgKARTtGQAZAgAAAA==.Elletta:BAAANQAECgEIAQAAAA==.Elrae:BAAANQAECgUIBQAAAA==.',
Eq='Eqo:BAAANQAECgcJEwAAAA==.',
Er='Erisian:BAAANQADCggIDwAAAA==.Erkêios:BAAANQAECgQIBQABNQAECggIIwAJAPQgAA==.Ersande:BAAANQAECgMIAwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAAANQAECgYIEwAAAA==.',
Ev='Evengelist:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAABNQAECoEpAAIJAAkKORiPPwCNAgAJAAkKORiPPwCNAgAAAA==.Faqueuedark:BAAANQAECgQIBgABNQAECgkJKQAVANUhAA==.Faqueueeight:BAABNQAECoEpAAMVAAkK1SFVCgA3AwAVAAkK1SFVCgA3AwAFAAcK0xLJCwCwAQAAAA==.Fatsloth:BAAANQAECgUICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQADAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQAECgUICwAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fimtastic:BAAANQAECgUIDgAAAA==.Finasy:BAAANQAECgYIEAAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgUICAAAAA==.Fistymisty:BAABNQAECoEZAAIWAAgK3iCLBAD4AgAWAAgK3iCLBAD4AgAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fo='Foxrawruwu:BAAANQAECgYICgAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAAANQAECgcICwABNQAECggIEgADAAAAAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgEIAQAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIBAAAAA==.',
Ga='Galeriel:BAACNQAFFIEGAAIMAAMKLRmvEQANAQAMAAMKLRmvEQANAQA1AAQKgSYAAgwACQoYJaYEAI4DAAwACQoYJaYEAI4DAAAA.Gallethline:BAAANQADCgcIDAAAAA==.Ganjgotti:BAAANQADCgYIBgAAAA==.Garault:BAAANQAECgQIBgAAAA==.Gavered:BAAANQADCgMJBQAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQAECgUIEAAAAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Goolgame:BAABNQAECoEgAAMKAAkKRR+vLQCGAgAKAAcK9B+vLQCGAgAXAAUKvRt0ZACJAQAAAA==.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAAANQAECgcICAAAAA==.Gruldag:BAABNQAECoEmAAISAAkKJRv2SgDHAgASAAkKJRv2SgDHAgAAAA==.Grullander:BAABNQAECoEZAAIXAAcK9xQqXACmAQAXAAcK9xQqXACmAQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAAANQAECgYIDgABNQAFFAQICAATAI0bAA==.Halter:BAAANQADCgMIAwAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAAANQAECgYIDwAAAA==.',
He='Header:BAACNQAFFIEOAAIYAAUKrBgVBgCpAQAYAAUKrBgVBgCpAQA1AAQKgR0AAxgACQqRGQMZAFwCABgACQqRGQMZAFwCAAcABQrnCvDDAA4BAAAA.Heersbeest:BAAANQABCgcICQAAAA==.Helane:BAAANQADCgUJBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECoEYAAMRAAcK4BDyIgCTAAASAAYKogy87gBaAQARAAIKbxjyIgCTAAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECoEXAAMVAAcKpRZAMQDAAQAVAAYKHBpAMQDAAQAZAAEK3AFZXwAjAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAECggICwADAAAAAA==.Holykoi:BAABNQAECoEaAAIMAAgKTQrOXgChAQAMAAgKTQrOXgChAQAAAA==.',
Hr='Hroarr:BAAANQAECggIEgAAAA==.',
Hu='Humancarnage:BAAANQADCgQIBQAAAA==.Huuh:BAAANQADCgQIBwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQAECgYIDgAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgUICQAAAA==.',
Ia='Iatros:BAAANQAECgUICgAAAA==.',
Id='Idkno:BAAANQADCggIEQAAAA==.',
Ik='Ikara:BAAANQADCggICAAAAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAAANQADCgYIBgAAAA==.',
Io='Iorin:BAAANQADCgcIBwABNQAECggIFgAFAKsIAA==.',
It='Itwasntmebru:BAAANQADCgYIBgAAAA==.',
Iv='Ivantis:BAAANQADCgYIEgAAAA==.Ivie:BAAANQADCgUIDwAAAA==.',
Iw='Iwonabhornee:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAAANQAFFAEIAQAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECoEgAAMaAAgKIBbYBgD5AQAaAAcKPhfYBgD5AQAQAAgKKhHPEgDiAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQAECgMIAwAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQADCgcICgAAAA==.',
Jp='Jpgigademon:BAAANQAECgMIBAAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIJAgAAAA==.Karametra:BAAANQAECgUIBQAAAA==.Karlldun:BAAANQAECgUIBQAAAA==.Kasmir:BAABNQAECoEYAAMbAAgKNQ9ycQCyAQAbAAcKtxBycQCyAQAcAAEKqgR8dQAqAAAAAA==.',
Ke='Kevv:BAABNQAECoEaAAMKAAkK3BEwOwBBAgAKAAkK3BEwOwBBAgAdAAEKUgANLwAdAAAAAA==.Keyniron:BAABNQAECoEqAAIJAAgKSCOnFgBGAwAJAAgKSCOnFgBGAwAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Killaarrow:BAABNQAECoEZAAIHAAcKSAgWjgCJAQAHAAcKSAgWjgCJAQAAAA==.Kindleos:BAAANQADCgQJBAAAAA==.',
Kl='Klay:BAAANQAECgUIBwAAAA==.',
Km='Kmarte:BAEANQAECgQICQABNQAECgcIDQADAAAAAA==.Kmartt:BAEANQAECgcIDQAAAA==.',
Ko='Kosmic:BAAANQADCgcIBwABNQAECgUIDAADAAAAAA==.Kosmicknight:BAAANQAECgUIDAAAAA==.',
Kr='Kraggers:BAAANQAECgUIDAAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAABNQAECoEhAAIXAAgKHSLMFwDlAgAXAAgKHSLMFwDlAgAAAA==.',
Kw='Kwarr:BAABNQAECoEhAAIdAAkK8x6dBQAOAwAdAAkK8x6dBQAOAwABNQAFFAQICQANAMEKAA==.',
La='Laganddecay:BAAANQABCggIFQAAAA==.Lalii:BAAANQADCgYIFQAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgIJAgAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQIBgAeAMUbAA==.',
Le='Leasin:BAABNQAECoEWAAIfAAcKlB3qFwBQAgAfAAcKlB3qFwBQAgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgQIBAAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECoEYAAIbAAYK1hhUagDIAQAbAAYK1hhUagDIAQAAAA==.Lilibejeane:BAAANQADCgIIAgABNQAECgIIBAADAAAAAA==.Lillynelazar:BAAANQAECgYIEQABNQAECgMIAwADAAAAAA==.Liloisback:BAAANQAECgYICAAAAA==.Lilsquirtboy:BAAANQADCgUJBQABNQAECggIHwAEAOAfAA==.Linasonna:BAAANQAECgIJAwABNQAECgkJIAAKAEUfAA==.Linithara:BAABNQAECoEWAAIFAAgKqwiuDwBWAQAFAAgKqwiuDwBWAQAAAA==.Littlehoosie:BAAANQAECggIBAAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAQIDAAgAN8RAA==.Loram:BAAANQADCgQIBAAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgIIAgAAAA==.',
Lu='Lucthedk:BAAANQAECgUICgAAAA==.Lukis:BAAANQAECgIIAgAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.',
['Lø']='Lørd:BAABNQAECoEXAAMYAAgKThdcLwB4AQAYAAYKphRcLwB4AQAHAAUKQxRXoQBaAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQADCgMIAwABNQAECgYICgADAAAAAA==.Maladin:BAAANQAECgIIAgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQAECgQIBgAAAA==.Marceline:BAAANQAECgcIDQAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgQICAAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQADCgYICgAAAA==.Misconduct:BAAANQAECgUICgAAAA==.',
Mm='Mmins:BAAANQAECgQIBAAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgMIAwAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAAANQAECgcIEgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQABCgEIAQAAAA==.Naniwa:BAAANQAECgMIBQAAAA==.Nazura:BAAANQADCgYJCwAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.',
Ni='Nightforday:BAABNQAECoExAAMIAAkKYyEJEQD/AgAIAAkKYyEJEQD/AgAgAAIKUhXGaACFAAAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.Noux:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.',
Nu='Nube:BAAANQADCgMIBAAAAA==.',
Ny='Nyababa:BAAANQAECgQIBAABNQAFFAMICAABAG0aAA==.',
Og='Ogora:BAAANQADCgIIAwAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.',
Op='Ophysia:BAAANQADCggIFgAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgUIBQAAAA==.',
Pa='Paapineau:BAAANQAECgUIBgAAAA==.Packes:BAABNQAECoEaAAIeAAcKoBCvSQCOAQAeAAcKoBCvSQCOAQAAAA==.Pakkohruun:BAABNQAECoEZAAIJAAkK7xIiVwA+AgAJAAkK7xIiVwA+AgAAAA==.Pallywack:BAAANQAECgQIEgAAAA==.Parthima:BAAANQAECgYIEQAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBQAAAA==.Pertophos:BAAANQAECgQIBAAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgEIAgAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgcIGgAeAKAQAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Popena:BAAANQAECgEIAQAAAA==.Porkbuns:BAABNQAECoEYAAISAAgK9BKUhwAyAgASAAgK9BKUhwAyAgAAAA==.Potatogg:BAAANQAECgEIAQAAAA==.',
Pr='Praedor:BAAANQAECgEJAQAAAA==.Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAAANQAECggIDAABNQAFFAQICAABAIUUAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFIEJAAINAAQKwQpuAgDxAAANAAQKwQpuAgDxAAA1AAQKgRcAAw0ACQrjFjcMAB8CAA0ABwrtGjcMAB8CAAEABwp6C6yjAF4BAAAA.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAQICQANAMEKAA==.',
Ra='Raathya:BAAANQAECgQIBAAAAA==.Raeljin:BAABNQAECoEWAAIKAAgKixuDLwB8AgAKAAgKixuDLwB8AgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUIBQAAAA==.Rar:BAAANQADCgMIAwAAAA==.Ratgamerlol:BAABNQAECoEZAAIHAAcKEiGNLQClAgAHAAcKEiGNLQClAgAAAA==.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQADCggIEwAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQAECgEIAQAAAA==.Redlocks:BAAANQAECgQIBgAAAA==.Reneana:BAAANQAECgUICAAAAA==.Restbo:BAAANQAECgYICAABNQAFFAUIDgAMABAQAA==.',
Rh='Rhianonn:BAAANQADCgQICAABNQADCgUIDwADAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Richardluis:BAAANQAECgUIBQAAAA==.Rinehardtt:BAABNQAECoEeAAIhAAkKnxqtGQDlAgAhAAkKnxqtGQDlAgAAAA==.Riverstyxx:BAAANQADCgIIAgAAAA==.Rivër:BAAANQADCgcIFwAAAA==.',
Ro='Robbell:BAABNQAECoEZAAIHAAgKRhcSQgBbAgAHAAgKRhcSQgBbAgAAAA==.Rokyman:BAAANQAECgUICQAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECoEYAAIUAAcKjxdzGwAHAgAUAAcKjxdzGwAHAgAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECoEXAAIJAAcKKAnEqQBbAQAJAAcKKAnEqQBbAQAAAA==.Runentug:BAACNQAFFIEGAAIeAAQKxRsoCgBaAQAeAAQKxRsoCgBaAQA1AAQKgRgAAh4ACQpPIwwLAD0DAB4ACQpPIwwLAD0DAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgYIEAAAAA==.Sassitude:BAAANQADCgcIDgAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAAANQAECgYIEAAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Semillin:BAAANQADCgMIAwAAAA==.Sensjei:BAAANQAECgQICAAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgMJAwAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAAANQAECgcIEAAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECgcICAAAAA==.Shãdøwzzxz:BAAANQAECgUICQAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQADAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggIBwAAAA==.',
Sm='Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAAANQAECgUICgAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
So='Sollamor:BAAANQADCgcICQAAAA==.Solomonk:BAAANQAECgQICAAAAA==.Solomus:BAAANQAECgUICAAAAA==.Sonal:BAAANQAECgYIEwAAAA==.Soter:BAAANQAECgUIBQAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAABNQAECoEaAAIXAAcKnxwMOgAvAgAXAAcKnxwMOgAvAgABNQADCgUIDwADAAAAAA==.Stormroid:BAAANQAECgQIBwAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAAANQAECgQIBQAAAA==.',
Su='Sugarontop:BAAANQADCgQJBAAAAA==.Sunmx:BAABNQAECoEeAAIBAAgKshr0SgBrAgABAAgKshr0SgBrAgAAAA==.Superdark:BAAANQADCgIJAgAAAA==.',
Sw='Swurve:BAEANQAECgQIBAAAAA==.Swurves:BAAANQAECgIIAwAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgIIAgAAAA==.',
Ta='Tadpole:BAAANQADCgYIBgAAAA==.Taedrum:BAAANQAECgQIBQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECggIIQALAC4gAA==.Taloning:BAAANQADCgYIBgABNQAECggIIQALAC4gAA==.Talonstryke:BAABNQAECoEhAAILAAgKLiDmCADRAgALAAgKLiDmCADRAgAAAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQADCggIDgABNQAECgkJHwAFADMgAA==.Tevers:BAAANQAECgEIAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAAANQAECgcIDQAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAABNQAECoEqAAIJAAgKSQ5lfgDJAQAJAAgKSQ5lfgDJAQAAAA==.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQAECgUICQAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAAANQAECgYIEAAAAA==.Thingtwø:BAAANQAECgEIAQAAAA==.Thistle:BAAANQADCgYIDAABNQAECgYIEgADAAAAAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwADAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICAAAAA==.',
To='Tokadin:BAAANQABCgQIBAAAAA==.Tomorrow:BAAANQAECgIJAgAAAA==.Totoo:BAAANQAECggICwAAAA==.',
Tr='Tralis:BAEANQADCggIDgAAAA==.Tranarra:BAABNQAECoEeAAIbAAUKchEClgBKAQAbAAUKchEClgBKAQAAAA==.Traylo:BAAANQAECgUIDgAAAA==.',
Tv='Tvak:BAABNQAECoEVAAIJAAYKBRoxdgDhAQAJAAYKBRoxdgDhAQAAAA==.',
Tw='Twopump:BAAANQAECgYIEwAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgQIBAAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgkJHgAHANAVAA==.Umbryx:BAAANQADCgIIAgABNQAECgQICAADAAAAAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAABNQAECoEeAAMXAAkKxCAuDwAiAwAXAAkKxCAuDwAiAwAKAAEKqgsQBAEuAAABNQAFFAMICAABAG0aAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgUICgAAAA==.Valienni:BAAANQADCgYIDgAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderius:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECgIJAwAAAA==.Vandersius:BAAANQADCggIDwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgIIAgABNQAECgkJJwAKAO0eAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAAANQAECgYIEQAAAA==.',
Vi='Vielitre:BAAANQADCgMIBAAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAAANQAECgYIEAAAAA==.Viridius:BAAANQADCgMJAwAAAA==.Vishouspayne:BAAANQAECgEIAQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
['Vä']='Väelün:BAAANQAECgUIDQABNQAECggIGAAiAGIKAA==.',
Wa='Wachoosh:BAAANQAECgEIAQAAAA==.Waidmanns:BAABNQAECoEeAAMHAAkK0BUjMACbAgAHAAkK0BUjMACbAgAjAAEK9QKgEAAsAAAAAA==.Walmartstaff:BAAANQADCgIIAgAAAA==.Warfable:BAAANQADCgEIAQAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBAAAAA==.',
Wh='Wham:BAAANQADCgUIBwAAAA==.Whatsaggro:BAABNQAECoEbAAIIAAcKfQZtXgAwAQAIAAcKfQZtXgAwAQAAAA==.Whatshadow:BAAANQADCgMIAwAAAA==.Whatyamean:BAAANQAECgMIBwAAAA==.Whoami:BAAANQAECggIAwAAAA==.Whoangry:BAAANQAECgcIDAAAAA==.Whomonk:BAAANQAECgIIAgAAAA==.',
Wi='Wickedchick:BAAANQADCgcIEAAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Winterknight:BAAANQADCgMIAwAAAA==.',
Wr='Wrenn:BAAANQAECgEIAQAAAA==.Wrongname:BAAANQAECgIIAwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECoEbAAIHAAkKNxp4HQDtAgAHAAkKNxp4HQDtAgAAAA==.',
Yr='Yrdenal:BAAANQADCgcIBwAAAA==.',
Yu='Yugalipdeez:BAAANQADCgEIAQAAAA==.Yulian:BAAANQAECgMIAwAAAA==.',
Za='Zaartyn:BAABNQAECoEaAAIbAAkKlR74EAAkAwAbAAkKlR74EAAkAwAAAA==.Zaater:BAAANQAECgEIAQAAAA==.Zalin:BAAANQADCggICAAAAA==.Zanki:BAAANQAECgEIAQAAAA==.',
Ze='Zeebeth:BAABNQAECoEXAAIHAAgKGQ7+XwADAgAHAAgKGQ7+XwADAgAAAA==.Zefi:BAAANQADCgYICQAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgYIEAADAAAAAA==.Zerokai:BAAANQADCgYIBgAAAA==.Zeztz:BAAANQAECgUIBQAAAA==.',
Zo='Zomlo:BAAANQAECgEIAQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgUICgAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Âr']='Ârtemis:BAAANQADCggICAABNQAECgkJHwAFADMgAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQAECgUIBQABNQAECgUICgADAAAAAA==.',
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
