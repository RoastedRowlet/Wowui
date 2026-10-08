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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Druid-Guardian','Druid-Balance','Druid-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Vengeance','Warrior-Arms','Warrior-Protection','Hunter-Marksmanship','Mage-Frost','Rogue-Subtlety','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Paladin-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaralyn:BAAANQAECgMIAwAAAA==.',
Ab='Abmikaze:BAAANQADCggICgAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Abysseon:BAABNQAECoEYAAMCAAgKMxp+JAA/AgACAAgKMxp+JAA/AgADAAMKawv3nAB9AAAAAA==.',
Ac='Ace:BAAANQAECgYIEwABNQAECgEIAQABAAAAAA==.',
Ad='Adios:BAACNQAFFIEQAAIEAAUKahIZBgCjAQAEAAUKahIZBgCjAQA1AAQKgSUAAgQACQpjHgcLAB4DAAQACQpjHgcLAB4DAAAA.Adorean:BAABNQAECoEbAAIFAAgKyxF4igDeAQAFAAgKyxF4igDeAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQICgAAAA==.Agrohn:BAAANQAECgYICgAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAAANQAECggIEwAAAA==.Aliine:BAAANQAECgUIDwAAAA==.',
Am='Ameiisaa:BAABNQAECoEXAAMGAAcKjQfezgDFAAAGAAUK0gPezgDFAAAHAAQKSQPk0QCbAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAABNQAECoE4AAIGAAkKWiCfFAA6AwAGAAkKWiCfFAA6AwAAAA==.',
An='Anxie:BAABNQAECoEUAAIIAAcK5QFXEAGQAAAIAAcK5QFXEAGQAAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAYIEQAJAG8cAA==.',
Ao='Aoifae:BAAANQAECgUIDAAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECoEZAAQKAAkKnAkzbgCbAQAKAAgKGgozbgCbAQALAAcKdgfROAA4AQAMAAEKMAVyKwAmAAAAAA==.Apprentice:BAAANQAECgYIDwAAAA==.',
Ar='Aramos:BAABNQAECoEgAAINAAgKDRlrNAB3AgANAAgKDRlrNAB3AgAAAA==.Aramôs:BAAANQAECgIIAwAAAA==.Arkhangel:BAABNQAECoEWAAIFAAgK7hh/XwBPAgAFAAgK7hh/XwBPAgAAAA==.Arta:BAAANQAECgIIAwAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgUIDQAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgkJKgADAK8TAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQICgAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.',
Be='Beaker:BAABNQAECoEgAAIOAAgKvREDFwC5AQAOAAgKvREDFwC5AQAAAA==.Beastmode:BAABNQAECoEmAAMPAAgK1BKwOQD5AQAPAAgK1BKwOQD5AQAQAAgKThPkIwDZAQAAAA==.Bedlem:BAAANQAECgUICwAAAA==.Beko:BAABNQAECoEaAAIRAAkKThsrTQDXAgARAAkKThsrTQDXAgAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAAANQAECgcIEQAAAA==.',
Bl='Blackhide:BAAANQABCgMIBAAAAA==.Blackpanthxr:BAABNQAECoEoAAQHAAkKHg3bYQC5AQAHAAkKHg3bYQC5AQASAAcKpQseGAC3AQAGAAcKoAZLmAA3AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICAAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIHAATAEIkAA==.Bloodyburst:BAABNQAECoEZAAMJAAgKnyLeBACaAgAJAAcKyiLeBACaAgAUAAIKDBzNbACsAAABNQAECggIHAATAEIkAA==.Bloodyfistz:BAABNQAECoEcAAMTAAgKQiTsCgAOAwATAAgKLiTsCgAOAwAVAAIKMyNZHwDGAAAAAA==.Blue:BAABNQAECoEbAAIGAAgKvBkRMgCMAgAGAAgKvBkRMgCMAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAAANQAECgYJCQAAAA==.Brewguts:BAAANQAECgcICwAAAA==.Brimscythe:BAABNQAECoEmAAIWAAgKQhzBCgCoAgAWAAgKQhzBCgCoAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAAANQAECgUIEAAAAA==.Calvey:BAAANQAECgMIAwAAAA==.Cambrai:BAAANQAECgQIBwAAAA==.Cannabelle:BAABNQAECoEeAAIIAAgKfSP+FAAyAwAIAAgKfSP+FAAyAwAAAA==.Carclias:BAABNQAECoEtAAMXAAkKCxgCDAAsAgAXAAgKBBcCDAAsAgAYAAcKhRWCdgDUAQAAAA==.Carthrix:BAAANQAECgYIBgAAAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAAANQAECgQICwAAAA==.',
Ce='Celery:BAAANQADCgIIAwABNQAFFAYIGgADAJsbAA==.Cellika:BAAANQAECgUICwAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chaoscookies:BAABNQAECoElAAMXAAgKqhTAFwClAQAXAAYKvBTAFwClAQAYAAUKWw+MswA5AQAAAA==.Chartkov:BAAANQAECgIIAwAAAA==.Cheezee:BAABNQAFFIEMAAIRAAYKgQ6vDgDeAQARAAYKgQ6vDgDeAQAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCggIDQAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECggIDQABAAAAAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQADCggJCAAAAA==.',
Cl='Clawsome:BAAANQADCggIEAAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAABNQAECoEeAAQZAAkKPBdxVgCPAQAZAAcKVhRxVgCPAQACAAcKFhc5UwAWAQADAAQK+xGSgQDPAAAAAA==.Comlock:BAAANQADCgYIDAAAAA==.Complacent:BAABNQAECoEWAAIOAAcK1QIsNAC3AAAOAAcK1QIsNAC3AAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBAAAAA==.Coriander:BAAANQAECgcIEwAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAAANQAECgYICwAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAcIFQATAG4WAA==.',
Cy='Cynical:BAAANQAECgEIAgABNQAECgEIAQABAAAAAA==.Cyonicus:BAABNQAECoEbAAIYAAgK8hnsSgBUAgAYAAgK8hnsSgBUAgAAAA==.Cyska:BAABNQAECoEqAAIDAAkKrxNCNQAXAgADAAkKrxNCNQAXAgAAAA==.',
['Cé']='Cécé:BAAANQAECgYIEwAAAA==.',
['Cë']='Cëcë:BAAANQADCgMICQAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECoEeAAIKAAgK2w6lVgDxAQAKAAgK2w6lVgDxAQAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQAECgcIEQAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYIGgAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECoEjAAIaAAkKEBF1CAAyAgAaAAkKEBF1CAAyAgABNQAFFAMICAAFANYbAA==.Davriell:BAAANQAECgUIBQAAAA==.Dax:BAAANQAECgUICwAAAA==.Daxing:BAAANQADCggIFAABNQAECgkJHwAKAI8dAA==.',
De='Deeppurple:BAAANQAECgMIBAAAAA==.Del:BAABNQAECoEjAAIbAAgKKCaQAQB5AwAbAAgKKCaQAQB5AwAAAA==.Demoniaca:BAAANQADCgEIAQAAAA==.Demonic:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgAAAA==.Demostache:BAABNQAECoEnAAMYAAkKXCHyJgDQAgAYAAgKxyDyJgDQAgAXAAIKyRXqSgCTAAABNQAECgkJHgAZADwXAA==.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECoEiAAIGAAgK+yC+HQD9AgAGAAgK+yC+HQD9AgAAAA==.',
Do='Dolomite:BAAANQAECgcIEwAAAA==.Dorow:BAABNQAECoEhAAMPAAkKKhrzLQBKAgAPAAgKCBrzLQBKAgAQAAQKsQzFQgDeAAABNQAECgkJGwATAFIZAA==.Dotabolt:BAAANQAECgYIEQAAAA==.',
Dr='Dracthyris:BAAANQAECgcIDgAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQADCgUICwAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECoEnAAISAAgK1x6NCQDJAgASAAgK1x6NCQDJAgAAAA==.',
Du='Dunsel:BAAANQAECgUIDAABNQAECggIJgAWAEIcAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgQIBAAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECoEfAAMcAAcKLxVbkgDHAQAcAAcKLxVbkgDHAQAdAAIKYw3jNABWAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggICAABNQAECgcIHwAcAC8VAA==.',
Eb='Ebonshade:BAAANQAECgEIAQAAAA==.',
Ed='Edena:BAAANQADCgYIBgAAAA==.Edginglord:BAAANQAECgQIBgAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Eloras:BAAANQAECgQIBQAAAA==.Elunbi:BAABNQAECoEoAAMKAAgKKh/6JQC2AgAKAAgKdB76JQC2AgAMAAYKkhQiDABjAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCggICQAAAA==.',
Ep='Epsilòn:BAEANQAECggIEAAAAA==.',
Er='Ernest:BAAANQAECgUICAAAAA==.Errani:BAAANQAECgQICQAAAA==.',
Es='Esper:BAAANQAECgYICQAAAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAAANQAECgUIBgAAAA==.',
Ev='Evilkarma:BAAANQAECgUIDgAAAA==.Evocatis:BAACNQAFFIEGAAIFAAMKaxqMDwAUAQAFAAMKaxqMDwAUAQA1AAQKgR8AAwUACQpyI7QjABwDAAUACQpyI7QjABwDAA0ABApTDZGxAPAAAAAA.',
Ey='Eyekonicklok:BAAANQAECgEIAQAAAA==.Eyesdeadeyed:BAABNQAECoEkAAIeAAkKSBSxIAArAgAeAAkKSBSxIAArAgAAAA==.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECoEcAAMFAAcKrh91UAB7AgAFAAcKrh91UAB7AgANAAUK2htmcACfAQAAAA==.Falco:BAAANQAECggIAQABNQAECggICAABAAAAAA==.Faon:BAAANQADCggICAAAAA==.Farrea:BAAANQADCggIFQAAAA==.Fatlock:BAAANQAECgMIBQABNQAECgkJJAATAJAZAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECgIIAwABNQAECgEIAQABAAAAAA==.Firebirdz:BAACNQAFFIEFAAIQAAIK2BP3DACdAAAQAAIK2BP3DACdAAA1AAQKgRgAAhAACQpLH8cPAL0CABAACQpLH8cPAL0CAAAA.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECoEdAAIEAAcKLwywMgCIAQAEAAcKLwywMgCIAQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Friargark:BAAANQADCgUICQAAAA==.Frizby:BAAANQAECgEIAQAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgUIDQAAAA==.',
Fy='Fyrelord:BAAANQAECgEIAQAAAA==.Fyuna:BAABNQAECoEgAAIHAAgKjR4AJAC3AgAHAAgKjR4AJAC3AgAAAA==.',
Ga='Gark:BAAANQAECgMIBAAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Gazzi:BAAANQAECgcIEgAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgUIDgABAAAAAA==.',
Gi='Giuseppee:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Gióvanna:BAAANQAECgIIAgAAAA==.',
Gl='Glodskegg:BAAANQAECgcIEgAAAA==.',
Go='Goldensea:BAAANQAECgMIBwAAAA==.Gotenk:BAAANQAECgYICgAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgMIBwAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAAANQAECgUIEAAAAA==.',
Gu='Guroo:BAABNQAECoEhAAIIAAgKaAsNhADUAQAIAAgKaAsNhADUAQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIAgAAAA==.',
Ha='Hagarn:BAABNQAECoEjAAIFAAkKwBLucAAfAgAFAAkKwBLucAAfAgAAAA==.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgcIGgADAIcTAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIDgAAAA==.Hazan:BAAANQAECggIDAABNQAECggIJwASANceAA==.',
He='Hexmachine:BAABNQAECoEjAAIYAAkKFxBUXAAgAgAYAAkKFxBUXAAgAgAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgEIAQAAAA==.',
Hy='Hypertext:BAAANQAECgYIDAAAAA==.',
Ia='Iamahriman:BAABNQAECoEWAAIGAAgKfQdBewCBAQAGAAgKfQdBewCBAQAAAA==.Iamarawn:BAAANQAECgQIEAAAAA==.',
Ig='Ignite:BAABNQAECoEhAAMRAAkKfB2YTADZAgARAAgKRh6YTADZAgAfAAEKJxe6OQBCAAAAAA==.',
Il='Illestria:BAABNQAECoEgAAIFAAcKBBSVmAC7AQAFAAcKBBSVmAC7AQAAAA==.Illumiscotty:BAABNQAECoEkAAMRAAkKCyWiCQCtAwARAAkKCyWiCQCtAwAfAAEKzBjWOgBAAAAAAA==.',
In='Incognonetoo:BAAANQAECgcICAAAAA==.Insania:BAAANQAECgYIEAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgYIGwAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCggJDgABNQAECgkJHwAKAI8dAA==.Jastirri:BAAANQAECgUICAAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUICAAAAA==.Jimothy:BAAANQADCggIDgABNQADCgQIBAABAAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAAANQAECgcIEgAAAA==.',
Ju='Juicez:BAAANQAECgIIAwAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggIBgAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIDwAAAA==.Katio:BAABNQAECoEpAAMUAAkKOh7yMQDdAQAUAAUKxCDyMQDdAQAgAAQKDhu3KwBJAQAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQAECgUIDgAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgMIBAAAAA==.Kessandra:BAACNQAFFIEXAAMYAAYKqyLWAQBdAgAYAAYKRyLWAQBdAgAhAAEK8CKwBgBfAAA1AAQKgR8AAyEACQpxJIwBAB8DACEACQr7IowBAB8DABgABQreHQOUAIQBAAAA.Kexally:BAAANQAECgEIAQAAAA==.Kexkan:BAAANQADCgQIDAABNQAECgEIAQABAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECgcIEgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAFFAEIAQAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAAANQAECgcIEgAAAA==.',
Ko='Koifo:BAAANQABCgUIBQAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAABNQAECoEaAAIDAAcKhxNqTgCbAQADAAcKhxNqTgCbAQAAAA==.Krystallus:BAAANQAECgQIBgAAAA==.',
Ku='Kurnea:BAAANQAECgQICAAAAA==.',
['Kó']='Kórrá:BAAANQADCgMIAwAAAA==.',
La='Lachlann:BAAANQAECgUIDAAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgkJGAAHALQQAA==.Lakartó:BAABNQAECoEsAAQWAAkKtRyECQDBAgAWAAkKlxuECQDBAgAiAAYKxRpTCQDBAQAjAAEKWB8cRABTAAAAAA==.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
Ld='Ldritch:BAACNQAFFIEMAAMgAAUK0xrEBgCFAQAgAAQKnRjEBgCFAQAUAAIKmxg6DgC1AAA1AAQKgSIABCAACQpFJC0XABUCACAABgqBIy0XABUCABQABQryI/gvAOkBAAkAAQo/Ge4XAEgAAAAA.',
Le='Leifson:BAAANQAECgUIBwAAAA==.Leonedis:BAAANQAECgQIDQAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAAANQAECgYIDgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgIIAwABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFIEGAAISAAMK7RkNAwAdAQASAAMK7RkNAwAdAQA1AAQKgSkAAhIACQoLIv0DAFADABIACQoLIv0DAFADAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECoEjAAMkAAgKuxlkEABPAgAkAAgKuxlkEABPAgATAAIKEgqtUwBlAAAAAA==.Luxurious:BAAANQAECgYIDwAAAA==.',
Ma='Maaca:BAAANQADCgYIDgAAAA==.Maecarepicha:BAAANQAECgUIBgAAAA==.Magicmoose:BAAANQABCggIDAAAAA==.Malachor:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Maligned:BAAANQAECgcIDgAAAA==.Martichoux:BAAANQAECgcIEgAAAA==.Mastakronik:BAAANQABCgIIAwAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECoErAAQNAAkKEh8jDgBKAwANAAkKEh8jDgBKAwAFAAIKeAc+VwFSAAAlAAEKpw5gaAAoAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAAANQAECgUIDwAAAA==.Mcmach:BAAANQAECgYIBwAAAA==.',
Me='Meddox:BAEANQABCggIDgAAAA==.Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAAANQAECgUIEAAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAAANQAECgUIDgAAAA==.Menotthatorc:BAAANQAECgIIAgABNQAECgkJHgAZADwXAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAAANQAECgUIDgAAAA==.Mesilana:BAAANQADCggIDAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQAECgUIEAAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgMIAwAAAA==.Monichan:BAAANQADCggICwAAAA==.Moosecheeks:BAAANQAECgcIEAAAAA==.Morganna:BAAANQABCggIDQAAAA==.Morior:BAAANQAECgUIDgAAAA==.Morslucifer:BAABNQAECoEXAAMhAAgKuBlVBAB1AgAhAAgKuBlVBAB1AgAXAAEKehPAbQA8AAAAAA==.Motorcade:BAABNQAECoEVAAIVAAYK1QJIIAC6AAAVAAYK1QJIIAC6AAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQAECgMIBgAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBQAAAA==.',
Na='Naula:BAAANQAECgEIAQAAAA==.',
Ne='Neather:BAAANQAECgYIDQAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nezkima:BAAANQADCgQIBAABNQAECgkJIgAHAGkfAA==.',
Ni='Nidivh:BAAANQAECgIIAwAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAAANQAECgUIDQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAABNQAECoEgAAIKAAgKQhktNwBpAgAKAAgKQhktNwBpAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgYIDQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQAECgUIDAAAAA==.Notron:BAAANQAECgYIDgAAAA==.Noz:BAAANQADCgYIEQAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQABCgEIAwAAAA==.Nychophysis:BAAANQAECgUIEAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oasis:BAAANQAECgEIAQAAAA==.',
Od='Odyssius:BAAANQAECggIAQAAAA==.',
Og='Ogden:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Om='Omars:BAAANQAECgUICAAAAA==.',
On='Ontherun:BAAANQADCgcIEQAAAA==.',
Op='Oprawinfury:BAAANQAECgIIAwAAAA==.',
Ou='Ourus:BAABNQAECoEsAAIdAAkKvSFiAwBQAwAdAAkKvSFiAwBQAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgIIAgAAAA==.Paulo:BAAANQAECgUIDgAAAA==.',
Pe='Pele:BAAANQAECgMIBAAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAAANQAECgcIEgAAAA==.',
Pi='Picklez:BAAANQAECgIIAgAAAA==.Piki:BAAANQAECgYIEwAAAA==.',
Po='Poepwn:BAABNQAECoEYAAQkAAYK/wmtKAACAQAkAAYK/wmtKAACAQAVAAIKTwXdKgBCAAATAAEKXgOAaQAgAAAAAA==.',
Pr='Pray:BAAANQAECgUIBQABNQAECgEIAQABAAAAAA==.Prescient:BAAANQAECggIBgAAAA==.',
Pu='Puffypanda:BAAANQAECgMIAwAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quill:BAAANQAECgcIEgAAAA==.',
Ra='Raging:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Ralz:BAAANQAECgUIEwAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAAANQAECgUIEAAAAA==.Ranua:BAAANQAECgQIBAABNQAECgkJHwAKAI8dAA==.Ratdemonmike:BAAANQAECgUIDQAAAA==.Rate:BAAANQAECgQIBwABNQAECgkJIgAEACUVAA==.Ratio:BAABNQAECoEiAAIEAAkKJRWMIAArAgAEAAkKJRWMIAArAgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAAANQAECgEIAgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgUIDQABNQAECgYIBgABAAAAAA==.',
Ru='Ruden:BAAANQAECgMIBQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDAABNQAECggIJwASANceAA==.',
Rw='Rwqr:BAABNQAECoEnAAImAAYKGQ5MRwBWAQAmAAYKGQ5MRwBWAQAAAA==.',
['Rä']='Räiden:BAAANQAECgUIDwAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECoEcAAMUAAgKHBLhKQASAgAUAAgKrBHhKQASAgAgAAEKYBcGRgBRAAAAAA==.Salin:BAAANQAECgUICAAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFIEXAAIlAAYK+CBqAQA4AgAlAAYK+CBqAQA4AgA1AAQKgSAAAiUACQoIJkkEAGEDACUACQoIJkkEAGEDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQAECgEIAQABNQAECgcIHQAIAPIfAA==.Scoobydo:BAAANQAECgIIAgABNQAECgcIHQAIAPIfAA==.Scratches:BAAANQAECgIIAwAAAA==.Scrubs:BAACNQAFFIEGAAIIAAQK8gKwFADsAAAIAAQK8gKwFADsAAA1AAQKgSAAAggACAoMGTxGAHMCAAgACAoMGTxGAHMCAAAA.',
Se='Seider:BAAANQAECggICAAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQABCgQIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQIAgABAAAAAA==.Shaggzy:BAACNQAFFIEVAAITAAcKbhYcAgBKAgATAAcKbhYcAgBKAgA1AAQKgSoAAhMACQoxJLMFAGUDABMACQoxJLMFAGUDAAAA.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQAECgUIEAAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgUIDQAAAA==.Shockdoctor:BAABNQAECoEYAAMHAAgK+CJWFQAKAwAHAAgK+CJWFQAKAwAGAAMKBQ6W4ACbAAAAAA==.Shortrange:BAAANQADCgEJAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwANACokAA==.',
Sl='Sleples:BAABNQAECoEdAAIIAAcK8h+FQACFAgAIAAcK8h+FQACFAgAAAA==.Slufgor:BAAANQAECgMIAwAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgcIEgAAAA==.',
Sn='Snoo:BAAANQAECgQICwAAAA==.',
So='Solarlite:BAAANQADCggICQAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECoEYAAMKAAgKRiREEQApAwAKAAgKRiREEQApAwAMAAIK8CTHEwDQAAAAAA==.Soulbreakër:BAABNQAECoEgAAICAAgKFwypOwCfAQACAAgKFwypOwCfAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAAANQAECgUICgABNQAECgYICwABAAAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgMIAwAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQAECgUICgAAAA==.',
Sr='Srbranchmgr:BAAANQADCgEIAQAAAA==.',
St='Starbrow:BAAANQAECggIEwAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgkJGgARAE4bAA==.Stilez:BAAANQAECggIAQABNQAECggIEAABAAAAAA==.Stormlight:BAAANQAECgQICAAAAA==.Strudelmaker:BAAANQAECgMIAwAAAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgIIAwAAAA==.',
Sy='Syland:BAAANQAECgUIDQAAAA==.Sylvanäs:BAAANQAECgQIBQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgkJHwAKAI8dAA==.Sysna:BAABNQAECoEiAAMLAAgKlyDyDwDeAgALAAcKrSTyDwDeAgAKAAcK7x55PwBIAgAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECoEbAAIHAAcKvhJXaQChAQAHAAcKvhJXaQChAQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECoEfAAIcAAgKeQy5lQC9AQAcAAgKeQy5lQC9AQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgkJHwAKAI8dAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Tergar:BAAANQAECgEIAQAAAA==.',
Th='Thaleas:BAAANQAECgQIBAAAAA==.Thegreatkhal:BAAANQAECgQICAAAAA==.Thorizine:BAAANQAECgYIEAAAAA==.Thorlas:BAAANQAECgUIDwAAAA==.Thotsfortots:BAAANQAECggIAwAAAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECoEbAAImAAcKZhnkMQDqAQAmAAcKZhnkMQDqAQAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECgcIDQAAAA==.Torment:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Torsion:BAAANQAECgMIBwAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAAANQAECgUIEQAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQAECgIIAwAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAYIDwAmAO8aAA==.Tust:BAAANQADCggIDgABNQADCgQIBAABAAAAAA==.',
Ty='Tylandy:BAABNQAECoEfAAIRAAgKLh/GQwDuAgARAAgKLh/GQwDuAgAAAA==.Tytaniormu:BAAANQAECgUIBgAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgUIBQAAAA==.',
Va='Vaayl:BAAANQAECgUIDgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAAANQAECgIIAwAAAA==.Valendera:BAAANQAECgcIEgAAAA==.Valguero:BAAANQADCgUIBQAAAA==.Valifadin:BAAANQAECgUIEAAAAA==.Valndrevy:BAAANQADCggIEwAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgUIBQAAAA==.Vansan:BAABNQAECoEfAAIKAAkKjx23GQD3AgAKAAkKjx23GQD3AgAAAA==.',
Ve='Venngennce:BAABNQAECoErAAICAAkKKx3fEQDgAgACAAkKKx3fEQDgAgAAAA==.',
Vi='Viktir:BAAANQADCgYICgABNQAECgMIBAABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Vorkath:BAABNQAECoEjAAMWAAgKjyRhBABFAwAWAAgKjyRhBABFAwAjAAQKOwpvNQDJAAAAAA==.Vormette:BAAANQADCgcIEgAAAA==.',
Vt='Vtae:BAAANQAECgMIBwAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECoEYAAIQAAcKRg6NLgBxAQAQAAcKRg6NLgBxAQAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAABNQAECoEVAAMCAAcK9wa8UAAjAQACAAcKsAW8UAAjAQADAAMKegeWoAByAAAAAA==.',
Wu='Wubblebubble:BAAANQAECgYICgAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgUIDQAAAA==.',
Xu='Xuzhu:BAAANQAECggIEgABNQAFFAUIBwAPAFILAA==.',
Yi='Yinei:BAAANQAECgEIAQAAAA==.',
Yl='Ylvis:BAABNQAECoEZAAIIAAcKVRegfQDjAQAIAAcKVRegfQDjAQAAAA==.',
Yo='Yol:BAABNQAECoEaAAIiAAkKFw7zCADQAQAiAAkKFw7zCADQAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECgcIGAAAAQ==.',
Yv='Yvetal:BAAANQAECgUICgABNQAECgkJHgAZADwXAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFIEJAAIQAAUKLBjFBACxAQAQAAUKLBjFBACxAQA1AAQKgSQAAxAACQpPI94DAHoDABAACQpPI94DAHoDAA8AAQrbBUGxAB4AAAAA.Zarra:BAAANQAECgIJBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQJBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAFFAUICQAQACwYAA==.Ziyar:BAAANQAECgIIBQABNQAFFAUICQAQACwYAA==.',
Zo='Zocorro:BAAANQAECgMIAwAAAA==.',
Zy='Zypherdius:BAAANQAECgIIAgAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFIEZAAIFAAUKShVgBwCwAQAFAAUKShVgBwCwAQA1AAQKgSgAAgUACQrbIVQqAAEDAAUACQrbIVQqAAEDAAAA.',
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
