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

local lookup = {'Warrior-Arms','Warrior-Fury','Unknown-Unknown','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Shaman-Restoration','Mage-Arcane','Priest-Holy','Rogue-Subtlety','Warrior-Protection','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Druid-Balance','Druid-Restoration','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Enhancement','DeathKnight-Frost','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAACNQAFFIEFAAIBAAMKyCCVFwAjAQABAAMKyCCVFwAjAQA1AAQKgR4AAwEACQqvIGwwAOkCAAEACQoUIGwwAOkCAAIAAQrGFywqAEIAAAAA.',
Ad='Adielia:BAAANQAECgUIEgAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgMIAwAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCggICgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCggIHgABNQAECgUIEQADAAAAAA==.Airflash:BAACNQAFFIEFAAIEAAIK4h/RCwCnAAAEAAIK4h/RCwCnAAA1AAQKgTQAAgQACAqeJPIGAEwDAAQACAqeJPIGAEwDAAAA.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQAECggIEgABNQAECgkJJwAFAEcgAA==.',
Al='Alexious:BAACNQAFFIEGAAIGAAMKhx9gBQAWAQAGAAMKhx9gBQAWAQA1AAQKgSgAAgYACQrNInAFAEIDAAYACQrNInAFAEIDAAAA.Aloonarn:BAAANQAECgQICAAAAA==.Alopix:BAAANQAECgUICwAAAA==.Alulla:BAACNQAFFIENAAMBAAUKwxfwEwBOAQABAAQKBRfwEwBOAQACAAIKvxlqAgCmAAA1AAQKgRwAAwIACQocH6IIAC4CAAEACApOH5w7AMECAAIABwqKHqIIAC4CAAAA.Alunira:BAABNQAECoEjAAMHAAgKLB0GIwDIAgAHAAgKLB0GIwDIAgAIAAYKURRHxABaAQAAAA==.',
Am='Amberrfrost:BAAANQAECgQICAAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQAECgUIDgAAAA==.Angrywar:BAABNQAECoEXAAIBAAgKLhEdiQDfAQABAAgKLhEdiQDfAQAAAA==.Anharon:BAAANQADCgYICQAAAA==.Ansatz:BAAANQAECgEIAwABNQAECgkJJgAJALYZAA==.',
Ap='Apokalypto:BAAANQAECgQIBAAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYIDwAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQAECgQIBwAAAA==.Asteriia:BAAANQAECgYIDwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQAECgIIAwABNQAECggIIQAKAHcIAA==.',
Az='Azarazan:BAAANQADCgYIDgAAAA==.Azka:BAABNQAECoEgAAIIAAkKeh8NJAAbAwAIAAkKeh8NJAAbAwAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAAANQAECgUIEQAAAA==.Baelmon:BAAANQADCgcIEgAAAA==.Baludis:BAAANQADCgcIEQAAAA==.Bamff:BAAANQAECgUICQAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Barreack:BAAANQADCgYICAAAAA==.Bast:BAABNQAECoEnAAMFAAkKRyCqAgAyAwAFAAkKRyCqAgAyAwALAAUKBhV3SABOAQAAAA==.Basthara:BAAANQAECggIEAABNQAECgkJJwAFAEcgAA==.',
Be='Beckianslip:BAAANQADCgUIBQAAAA==.Belphegor:BAAANQAECgEIAQABNQAECgYIDQADAAAAAA==.Benif:BAACNQAFFIEMAAIBAAUKOxttCwDIAQABAAUKOxttCwDIAQA1AAQKgSMAAgEACQqmJf4FAL8DAAEACQqmJf4FAL8DAAAA.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAABNQAECoEXAAIMAAgKeBeKSAAoAgAMAAgKeBeKSAAoAgAAAA==.Bewblover:BAAANQADCggIEwAAAA==.',
Bi='Bigbitehotdo:BAABNQAECoEmAAMEAAgKkiBREADEAgAEAAgKkiBREADEAgANAAEK3wGuSwAjAAAAAA==.Bighoney:BAAANQAECgEIAQAAAA==.Bigtommybuns:BAAANQADCgUIBQAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodeie:BAAANQADCgQIBAAAAA==.Bloodstoned:BAAANQAECgQIBgAAAA==.Blueboy:BAAANQAECgYIDAAAAA==.',
Bo='Boffadz:BAAANQAECggICAAAAA==.Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQAECgEIAQAAAA==.',
Br='Braugorlle:BAAANQAECgMIAwABNQAFFAMIBgAOAFwVAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcJBwADAAAAAA==.',
Bu='Buffmuffin:BAAANQAECgIIAgAAAA==.Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQAECgIIAwAAAA==.',
Ca='Cambrier:BAABNQAECoEpAAMCAAgKtSGtAwDxAgACAAgKqCCtAwDxAgABAAgKRxo6TwCBAgAAAA==.Cameraop:BAABNQAECoEXAAIPAAcKWwj09gB4AQAPAAcKWwj09gB4AQAAAA==.Capnsoap:BAAANQADCgYIBgABNQABCgEIAQADAAAAAA==.Capriestsun:BAAANQAECgMIAwAAAA==.Cardinal:BAAANQAECgEIAQAAAA==.Carynden:BAAANQADCgUIBQAAAA==.Castbo:BAAANQAECgYICAABNQAFFAUIEQAQADwRAA==.',
Ce='Celilinia:BAAANQAECgEIAQAAAA==.Cellesstia:BAAANQADCgMIBQABNQADCgUIDwADAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAFFAcIBwARAAoAAA==.Chalastorm:BAAANQADCgYIBwABNQAFFAcIBwARAAoAAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgQIBQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgQIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Cm='Cmx:BAAANQADCgUIBQAAAA==.',
Co='Codith:BAAANQADCgUIBQAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEJAQAAAA==.',
Cr='Creek:BAAANQABCgYIBgABNQAECgcIEwADAAAAAA==.Crnogorac:BAAANQAECggIAQAAAA==.Crotchgoblim:BAAANQADCgUIBwAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEIAQAAAA==.Cuddlesworth:BAAANQAECgYIDQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAQICQASAMEKAA==.',
Da='Daddyluis:BAAANQADCggICAAAAA==.Dadstonks:BAAANQABCgYJCAAAAA==.Dagoujiao:BAAANQAECgUIBgAAAA==.Dameiyo:BAAANQAECgYICwAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAAANQAECgUIEgAAAA==.Dankbo:BAACNQAFFIERAAMQAAUKPBFNEgBDAQAQAAQKHhVNEgBDAQATAAMK1gi4AQDXAAA1AAQKgTQAAxMACQpwIkQCAO0CABMACAq6IEQCAO0CABAACQrWHQEnALECAAAA.Darkcoffee:BAAANQAECgYICgAAAA==.Darkivie:BAAANQADCgYIBgABNQAECggIHAAIAM4FAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCgcIEwAAAA==.Devilcrybaby:BAAANQAECgIIAgAAAA==.Devildj:BAAANQAECgYIDQAAAA==.Dezadian:BAAANQAECgYICwAAAA==.',
Dh='Dhampyra:BAAANQAECgcIEAAAAA==.',
Di='Didicoralie:BAAANQADCgEJAQAAAA==.Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgYIBgAAAA==.Disolve:BAABNQAECoEgAAQUAAkKGRRSYwAMAgAUAAkKaxFSYwAMAgAVAAIK9hZJTQCMAAAWAAEKSCAPIQBaAAAAAA==.Dixxonciderr:BAABNQAECoE6AAQXAAkKCh7kBwAZAwAXAAkKCh7kBwAZAwAYAAYKOw25HgBKAQAZAAIKehMBGgB1AAAAAA==.',
Dm='Dmoe:BAAANQAECgQIBgAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQAECgIIAQAAAA==.',
Dr='Drac:BAAANQADCgMIAwAAAA==.Dribby:BAAANQADCgUIBQAAAA==.',
Du='Duhästmich:BAAANQADCgYIBgABNQAECggIIQAKAHcIAA==.Duplicate:BAACNQAFFIEKAAMaAAQKrA2NBgCWAAAPAAMKTghjMgDLAAAaAAIKGA+NBgCWAAA1AAQKgSIAAw8ACQpnGU2EAF0CAA8ACQpnGU2EAF0CABoAAQonG3c4AEUAAAAA.Dustdruid:BAABNQAECoEjAAIbAAgKRSGkGgDZAgAbAAgKRSGkGgDZAgAAAA==.Dustlock:BAAANQAECgcICwAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBwAAAA==.',
Ee='Eender:BAAANQAECgEIAQAAAA==.',
Eg='Eggrolls:BAABNQAECoEvAAIBAAkKHBqGNADZAgABAAkKHBqGNADZAgAAAA==.',
El='Eldenmorden:BAAANQADCgYIBgAAAA==.Eleshmelly:BAAANQADCgcIEQAAAA==.Ellayna:BAAANQADCgEIAQAAAA==.Ellcrys:BAABNQAECoEiAAIcAAgK+RVHHQAdAgAcAAgK+RVHHQAdAgAAAA==.Elletta:BAAANQAECgEIAQAAAA==.Elrae:BAAANQAECgUIBQAAAA==.',
Ep='Epoptes:BAAANQAECgEIAQAAAA==.',
Eq='Eqo:BAABNQAECoEdAAMQAAkKERJlZgC4AQAQAAkKERJlZgC4AQAdAAEKxQk4aAA9AAAAAA==.',
Er='Erisian:BAAANQAECgQIBAAAAA==.Erkêios:BAAANQAECggIDwAAAA==.Ersande:BAAANQAECgMIAwAAAA==.Ertz:BAAANQADCggICQAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAABNQAECoEYAAQYAAcKBh/zDAB6AgAYAAcKBh/zDAB6AgAZAAEKXw6mHwA2AAAXAAEKQAuHSQAvAAAAAA==.',
Ev='Evengelist:BAAANQAECgQIBgABNQAECgUICwADAAAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQAECgQIBAAAAA==.Falin:BAABNQAECoE6AAIIAAkKQhx7NQDWAgAIAAkKQhx7NQDWAgAAAA==.Faqueuedark:BAAANQAECgYIDAABNQAECgkJMgALABoiAA==.Faqueueeight:BAABNQAECoEyAAMLAAkKGiIfDQApAwALAAkKGiIfDQApAwAFAAgKVxWOCgACAgAAAA==.Fatsloth:BAAANQAECgUICAAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQADAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQAECgYIDAAAAA==.Ferrick:BAAANQAECgIIAgAAAA==.',
Fi='Fimtastic:BAABNQAECoEWAAIOAAcKSBRPbACYAQAOAAcKSBRPbACYAQAAAA==.Finasy:BAABNQAECoEWAAIeAAYKQiWsIwCBAgAeAAYKQiWsIwCBAgAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgUICAAAAA==.Fistymisty:BAABNQAECoEcAAIfAAkKHSCSAwA+AwAfAAkKHSCSAwA+AwAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fo='Foxrawruwu:BAAANQAECgYIDwAAAA==.',
Fr='Frakk:BAAANQAECggIAQAAAA==.Freezegarr:BAAANQAECggIEwABNQAECgkJFQAeANchAA==.Frostgrave:BAAANQADCgEIAQAAAA==.Frostya:BAAANQADCgEIAQAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.Furrybowner:BAAANQAECggIBQAAAA==.',
Ga='Galeriel:BAACNQAFFIEIAAIQAAMKjxvGFQAWAQAQAAMKjxvGFQAWAQA1AAQKgSkAAhAACQoYJcMGAIADABAACQoYJcMGAIADAAAA.Gallethline:BAAANQADCgcIEAAAAA==.Ganjgotti:BAAANQADCgYICQAAAA==.Garault:BAAANQAECgUIBwAAAA==.Gavered:BAAANQADCgMJBQAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQAECgUIEwAAAA==.',
Gh='Ghorros:BAAANQADCgMIAwAAAA==.',
Gi='Gilgahmesh:BAAANQAECgYIBwABNQAECgkJJQAHAGUbAA==.',
Gl='Glowpwr:BAAANQADCgcIBwAAAA==.',
Go='Goolgame:BAACNQAFFIEGAAMOAAMKXBXqEQD5AAAOAAMKXBXqEQD5AAAMAAIKwBTJHAChAAA1AAQKgScAAwwACQqtHyAxAJECAAwABwp5ICAxAJECAA4ABQq9Gyh2AHoBAAAA.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grammarg:BAAANQADCgMIAwAAAA==.Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAAANQAECgcIDwAAAA==.Gruldag:BAABNQAECoEoAAIPAAkKJRu5XgCuAgAPAAkKJRu5XgCuAgAAAA==.Grullander:BAABNQAECoEhAAIOAAgKyhMmVwDeAQAOAAgKyhMmVwDeAQAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAAANQAECgYIDgABNQAFFAQIBAADAAAAAA==.Halter:BAAANQADCgMIAwAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQAECgEIAQAAAA==.Hazzurd:BAABNQAECoEZAAIJAAcKVRNOfADmAQAJAAcKVRNOfADmAQAAAA==.',
He='Header:BAACNQAFFIEUAAIgAAYKWBh+BAD/AQAgAAYKWBh+BAD/AQA1AAQKgR8AAyAACQqRGXgdAEkCACAACQqRGXgdAEkCAAkABQrnCrDhAAwBAAAA.Healsorz:BAAANQADCgcIBwAAAA==.Helane:BAAANQADCgUIBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAABNQAECoEfAAMPAAgKuQ+y5wCUAQAPAAcK7Quy5wCUAQAaAAIKbxi2KACJAAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAABNQAECoEYAAMLAAcKpRZDOwCnAQALAAYKHBpDOwCnAQAhAAEK3AGDZwAjAAAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAFFAcIBwARAAoAAA==.Holykoi:BAABNQAECoEhAAIQAAgKZQ15ZQC7AQAQAAgKZQ15ZQC7AQAAAA==.',
Hr='Hroarr:BAABNQAECoEVAAIeAAkK1yHyCwBDAwAeAAkK1yHyCwBDAwAAAA==.',
Hu='Humancarnage:BAAANQADCgYIBwAAAA==.Huuh:BAAANQADCgQIBwAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQAECgYIDgAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgYIDwAAAA==.',
Ia='Iatros:BAAANQAECgYIDwAAAA==.',
Id='Idkno:BAAANQADCggIFQAAAA==.',
Ik='Ikara:BAAANQADCggICAABNQAECgkJFgAUAD0NAA==.',
Im='Imjustsaiyan:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAAANQAECgYIBgAAAA==.',
Io='Iorin:BAAANQADCgcIBwABNQAECggIFwAFAPQJAA==.',
It='Itwasntmebru:BAAANQADCgYIDgAAAA==.',
Iv='Ivantis:BAAANQADCgYIEgAAAA==.Ivie:BAAANQADCgUIDwAAAA==.',
Iw='Iwonabhornee:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAAANQAFFAIIAwAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECoEiAAMZAAkKCxXPBgApAgAZAAgK4xXPBgApAgAYAAgKKhErFQDZAQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQAECgMIBQAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Jollygreene:BAAANQAECgEIAgAAAA==.Jonestu:BAAANQADCggIDwAAAA==.',
Jp='Jpgigademon:BAAANQAECgMIBAAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIIAgAAAA==.Karametra:BAAANQAECgYIBgAAAA==.Karlldun:BAAANQAECgUIBQAAAA==.Kasmir:BAABNQAECoEgAAMUAAgKrhAQfgC/AQAUAAcK5REQfgC/AQAVAAEKLggOdgAxAAAAAA==.Kasnfriends:BAAANQADCgUIBQABNQAECggIIAAUAK4QAA==.',
Ke='Kevv:BAABNQAECoEdAAMMAAkKPBKxRwArAgAMAAkKPBKxRwArAgAiAAEKUgCCNAAcAAAAAA==.Keyniron:BAABNQAECoFZAAIIAAgKnSTqLwDrAgAIAAgKnSTqLwDrAgAAAA==.',
Kh='Khogent:BAAANQADCgQIBAAAAA==.Khonsu:BAAANQAECgQIBAAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgYIBwAAAA==.',
Ki='Kijanajr:BAAANQADCgEIAQAAAA==.Killaarrow:BAABNQAECoEgAAIJAAcKEApkmACkAQAJAAcKEApkmACkAQAAAA==.Kindleos:BAAANQADCgQJBAAAAA==.',
Kk='Kkpriest:BAAANQADCgEIAQAAAA==.',
Kl='Klay:BAAANQAECgYIDQAAAA==.',
Km='Kmarte:BAEANQAECgQICQABNQAECggIFgAIAFwXAA==.Kmartt:BAEBNQAECoEWAAIIAAgKXBdLbwAjAgAIAAgKXBdLbwAjAgAAAA==.',
Ko='Kosmic:BAAANQADCgcICQABNQAECgYIEgADAAAAAA==.Kosmicknight:BAAANQAECgYIEgAAAA==.',
Kr='Kraggers:BAAANQAECgUIDQAAAA==.Kraggoryqt:BAAANQAECgMIBAAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAABNQAECoEqAAIOAAkKkyA5EwAYAwAOAAkKkyA5EwAYAwAAAA==.',
Kw='Kwarr:BAACNQAFFIEHAAIiAAQKjRC9AgBLAQAiAAQKjRC9AgBLAQA1AAQKgSMAAiIACQrzHhcHAAEDACIACQrzHhcHAAEDAAE1AAUUBAgJABIAwQoA.',
La='Laganddecay:BAAANQABCggIFQAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgQIBAAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAFFAQICQAeALwgAA==.',
Le='Leasin:BAABNQAECoEdAAIdAAgKhR4dEgC/AgAdAAgKhR4dEgC/AgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgQIBAAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAABNQAECoEdAAIUAAcK7RidYAAUAgAUAAcK7RidYAAUAgAAAA==.Lilibejeane:BAAANQADCgIIAgABNQAECgMIBwADAAAAAA==.Lillynelazar:BAAANQAECgYIEQABNQAECgMIAwADAAAAAA==.Liloisback:BAAANQAECgcIDwAAAA==.Lilsquirtboy:BAAANQADCgUJBQABNQAECggIJgAEAJIgAA==.Linasonna:BAAANQAECgIIBAABNQAFFAMIBgAOAFwVAA==.Linithara:BAABNQAECoEXAAIFAAgK9AnAEgBPAQAFAAgK9AnAEgBPAQAAAA==.Littlehoosie:BAAANQAECggIBAAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAUIEAAjAJsXAA==.Loram:BAAANQADCgQIBAAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgIIAgAAAA==.',
Lu='Lucthedk:BAAANQAECggIDwAAAA==.Lukis:BAAANQAECgIIAgAAAA==.Lunarpriest:BAAANQAECgQIBAAAAA==.Lunitari:BAAANQAECgEIAQAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.Luxriel:BAAANQADCgYIBgAAAA==.',
['Lø']='Lørd:BAABNQAECoEZAAMgAAkKGhfyLgCuAQAgAAcKxBTyLgCuAQAJAAUKQxTTvQBTAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQAECgEIAQABNQAECgYIDwADAAAAAA==.Maladin:BAAANQAECgIIAgAAAA==.Malkurim:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQAECgQIBgAAAA==.Marceline:BAABNQAECoEXAAIJAAgK7BOpVQBIAgAJAAgK7BOpVQBIAgAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgUIDQAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQAECgEIAQAAAA==.Misconduct:BAAANQAECgUIDQABNQAECgYICgADAAAAAA==.',
Mm='Mmins:BAAANQAECgYICAAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQAECgIIAgAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgYICQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAABNQAECoEeAAIdAAkKqxZOFwB6AgAdAAkKqxZOFwB6AgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgMIBgAAAA==.Nawala:BAAANQAECgEIAQAAAA==.Nazura:BAAANQADCgcIDAAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEIAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.',
Ni='Nightforday:BAABNQAECoEzAAMKAAkKYyHzHADBAgAKAAkKYyHzHADBAgAjAAIKUhXmdwB/AAAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQAECgEIAQABNQAECgIIAwADAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.Noux:BAAANQADCgcIDAABNQAECgEIAQADAAAAAA==.',
Nu='Nube:BAAANQADCgUICAAAAA==.',
Ny='Nyababa:BAAANQAECgQIBgABNQAFFAUIDQABAMMXAA==.',
Og='Ogora:BAAANQADCgQIBgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.Oktavius:BAAANQAECgEIAQAAAA==.',
Op='Ophysia:BAAANQADCggIGQAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgUIBQAAAA==.',
Pa='Paapineau:BAAANQAECgUICwAAAA==.Packes:BAABNQAECoEiAAIeAAgKxhUJNAAdAgAeAAgKxhUJNAAdAgAAAA==.Pakkohruun:BAABNQAECoEZAAIIAAkK7xL5bQAmAgAIAAkK7xL5bQAmAgAAAA==.Pallywack:BAABNQAECoEYAAIIAAUK/Qsl8gD/AAAIAAUK/Qsl8gD/AAAAAA==.Palussy:BAAANQADCgQIBAAAAA==.Parthima:BAABNQAECoEdAAIbAAgKkAemUABwAQAbAAgKkAemUABwAQAAAA==.Partysnaxx:BAAANQABCgEIAQAAAA==.',
Pe='Peppercat:BAAANQAECgQIBwAAAA==.Pertophos:BAAANQAECgUICQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgEIAgAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECggIIgAeAMYVAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Popena:BAAANQAECgIIAgAAAA==.Porkbuns:BAABNQAECoEYAAIPAAgK9BKDnQAnAgAPAAgK9BKDnQAnAgAAAA==.Potatogg:BAAANQAECgIIAgAAAA==.',
Pr='Praedor:BAAANQAECgEJAQAAAA==.Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAABNQAECoEXAAIQAAkKIiHrBwB0AwAQAAkKIiHrBwB0AwABNQAFFAUIDAABADsbAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAACNQAFFIEJAAISAAQKwQo0AwDvAAASAAQKwQo0AwDvAAA1AAQKgRcAAxIACQrjFuEOABACABIABwrtGuEOABACAAEABwp6C1+6AFkBAAAA.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAQICQASAMEKAA==.',
Ra='Raathya:BAAANQAECgUIBgAAAA==.Raeljin:BAABNQAECoEZAAIMAAgKpBsGNQB+AgAMAAgKpBsGNQB+AgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQAECgUICQAAAA==.Rar:BAAANQAECgcIBwAAAA==.Ratgamerlol:BAABNQAECoEdAAIJAAcKySMyKgDPAgAJAAcKySMyKgDPAgAAAA==.Ravnur:BAAANQADCggICAAAAA==.Rayennagrom:BAAANQADCggIEwAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQAECgYICAAAAA==.Redlocks:BAAANQAECgUICgAAAA==.Reneana:BAAANQAECgUICAAAAA==.Restbo:BAAANQAECgcIDwABNQAFFAUIEQAQADwRAA==.',
Rh='Rhianonn:BAAANQAECgUIBQABNQADCgUIDwADAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Richardluis:BAAANQAECgUICwAAAA==.Rinehardtt:BAABNQAECoElAAIHAAkKZRuwHgDgAgAHAAkKZRuwHgDgAgAAAA==.Riverstyxx:BAAANQADCgUIBwAAAA==.Rivër:BAAANQADCggIHwAAAA==.',
Ro='Robbell:BAABNQAECoEcAAIJAAkK+RYROACfAgAJAAkK+RYROACfAgAAAA==.Rokyman:BAAANQAECgYICwAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBQAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAABNQAECoEYAAIcAAcKjxc7IAD9AQAcAAcKjxc7IAD9AQAAAA==.Rouby:BAAANQAECgEIAgAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAABNQAECoEXAAIIAAcKKAlwxwBTAQAIAAcKKAlwxwBTAQAAAA==.Runentug:BAACNQAFFIEJAAIeAAQKvCCQCgCCAQAeAAQKvCCQCgCCAQA1AAQKgRsAAh4ACQo+JLwJAFwDAB4ACQo+JLwJAFwDAAAA.Rustyspell:BAAANQADCgIIAgAAAA==.',
Ry='Ryumapriest:BAAANQABCgEIAQAAAA==.',
['Rî']='Rîft:BAAANQADCgEIAQAAAA==.',
Sa='Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgcIEQAAAA==.Sassitude:BAAANQADCgcIFQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAAANQAECgYIEAAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Semillin:BAAANQADCgMIAwAAAA==.Sensjei:BAAANQAECgUIDAAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgUICAAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAABNQAECoEcAAIIAAgKzgVp0QA+AQAIAAgKzgVp0QA+AQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shockrock:BAAANQADCgEIAQAAAA==.Shouzhe:BAAANQADCgUIBQAAAA==.Shroomjuice:BAAANQAECggIDwAAAA==.Shãdøwzzxz:BAAANQAECgUIDAAAAA==.',
Si='Silessra:BAAANQADCggICAAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQADAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggICQAAAA==.',
Sm='Smokeyhaze:BAAANQAECgYIDgAAAA==.Smokin:BAAANQAECgUIDwAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
So='Sollamor:BAAANQADCgcICQAAAA==.Solomonk:BAAANQAECgUIDQAAAA==.Solomus:BAAANQAECgUIDQAAAA==.Sonal:BAAANQAECgYIEwAAAA==.Soter:BAAANQAECgYIBgAAAA==.',
Sq='Squeaph:BAAANQADCgYIBgAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAABNQAECoEdAAIOAAgKBhspOQBSAgAOAAgKBhspOQBSAgABNQADCgUIDwADAAAAAA==.Stormroid:BAAANQAECgUICQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAAANQAECgUICgAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAABNQAECoEgAAIBAAkKGxsYPgC5AgABAAkKGxsYPgC5AgAAAA==.Superdark:BAAANQADCgIIAgAAAA==.',
Sw='Swurve:BAEANQAECgQIBwAAAA==.Swurves:BAAANQAECgIIAwABNQAECgYICAADAAAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
['Sã']='Sãvãge:BAAANQADCgIIAgAAAA==.',
Ta='Tabiji:BAEANQAECggICAAAAA==.Tadpole:BAAANQADCgYIBgAAAA==.Taedrum:BAAANQAECgUICgAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECggIKQANADQiAA==.Taloning:BAAANQADCgYIBgABNQAECggIKQANADQiAA==.Talonstryke:BAABNQAECoEpAAINAAgKNCJABwAFAwANAAgKNCJABwAFAwAAAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQAECgcIBwABNQAECgkJJwAFAEcgAA==.Tevers:BAAANQAECgEIAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAABNQAECoEWAAMUAAkKPQ17ZgACAgAUAAkKPQ17ZgACAgAWAAIKiQluIQBYAAAAAA==.Thebigshot:BAAANQAECgMIBQAAAA==.Theenforcer:BAABNQAECoE0AAIIAAkKFBDceQAIAgAIAAkKFBDceQAIAgAAAA==.Thegreekbeas:BAAANQADCgUIBQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQAECgUIDgAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAABNQAECoEWAAIkAAYK6xpqFgDAAQAkAAYK6xpqFgDAAQAAAA==.Thingtwø:BAAANQAECgEIAQAAAA==.Thistle:BAAANQADCgYIDAABNQAECggIGQAPAPUJAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titanslay:BAAANQADCgEIAQAAAA==.Titø:BAAANQADCgYIDQABNQADCgcIBwADAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICAAAAA==.',
To='Tokadin:BAAANQABCgQIBAAAAA==.Tomorrow:BAAANQAECgIJAgAAAA==.Totoo:BAABNQAFFIEHAAIRAAcKCgDCFAAkAAARAAcKCgDCFAAkAAAAAA==.',
Tr='Traedarra:BAAANQADCgEIAQAAAA==.Tralis:BAEANQADCggIDgAAAA==.Tranarra:BAABNQAECoEqAAIUAAcKbBg5YAAVAgAUAAcKbBg5YAAVAgAAAA==.Traylo:BAABNQAECoEZAAIJAAcKzhG1fQDjAQAJAAcKzhG1fQDjAQAAAA==.',
Tv='Tvak:BAABNQAECoEVAAIIAAYKBRrpkQDMAQAIAAYKBRrpkQDMAQAAAA==.',
Tw='Twistedsham:BAAANQAECggIBgAAAA==.Twopump:BAABNQAECoEgAAIIAAgK0QgErwCIAQAIAAgK0QgErwCIAQAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgQIBAAAAA==.',
Um='Umbressa:BAAANQADCgMIAwABNQAECgkJJgAJALYZAA==.Umbryx:BAAANQADCgIIAgABNQAECgYIDQADAAAAAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAABNQAECoEfAAMOAAkKxCDzEwATAwAOAAkKxCDzEwATAwAMAAEKqgsMIQEsAAABNQAFFAUIDQABAMMXAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgYIDwAAAA==.Valienni:BAAANQADCgYIDgAAAA==.Vanderdemon:BAAANQADCgMIAwAAAA==.Vanderius:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECggIAwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgQIBgABNQAECgkJLwAMAP8gAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAAANQAECgYIEwAAAA==.',
Vi='Vielitre:BAAANQADCgUIBwAAAA==.Vigossfel:BAAANQADCgMIBwAAAA==.Viintage:BAABNQAECoEdAAIPAAcKkBiSoQAfAgAPAAcKkBiSoQAfAgAAAA==.Viridius:BAAANQADCgMIBQAAAA==.Vishouspayne:BAAANQAECgQIBQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
Vy='Vyolence:BAAANQAECgEIAQABNQAECggIHQAdAIUeAA==.',
['Vä']='Väelün:BAAANQAECgUIEAABNQAECggIHQAkABgMAA==.',
['Vÿ']='Vÿ:BAAANQADCggICAAAAA==.',
Wa='Wachoosh:BAAANQAECgEIAQAAAA==.Waidmanns:BAABNQAECoEmAAMJAAkKthlZIwDsAgAJAAkKthlZIwDsAgAlAAEK9QKuEgAmAAAAAA==.Walmartstaff:BAAANQADCgIIAgAAAA==.Warfable:BAAANQADCgEIAQAAAA==.',
Wg='Wgnmd:BAAANQAECgQIBQAAAA==.',
Wh='Wham:BAAANQADCgUIBwAAAA==.Whatsaggro:BAABNQAECoEhAAIKAAgKdwiXXwBrAQAKAAgKdwiXXwBrAQAAAA==.Whatshadow:BAAANQADCgUICAAAAA==.Whatyamean:BAAANQAECgQICwAAAA==.Whoami:BAAANQAECggIBAAAAA==.Whoangry:BAAANQAECgcIEQAAAA==.Whomonk:BAAANQAECgIIBAAAAA==.',
Wi='Wickedchick:BAAANQADCggIEQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.Winterknight:BAAANQADCgQIBgAAAA==.',
Wr='Wrenn:BAAANQAECgEIAQAAAA==.Wrongname:BAAANQAECgMIBQAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
Xf='Xfloki:BAAANQADCgQIBAAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEBNQAECoElAAIJAAkKpxx8HAAMAwAJAAkKpxx8HAAMAwAAAA==.',
Yr='Yrdenal:BAAANQADCgcIBwAAAA==.',
Yu='Yugalipdeez:BAAANQAECgEIAQAAAA==.Yulian:BAAANQAECgQIBwAAAA==.',
Za='Zaartyn:BAABNQAECoEgAAIUAAkKhx99FwAWAwAUAAkKhx99FwAWAwAAAA==.Zaater:BAAANQAECgIIAQAAAA==.Zalin:BAAANQAECgEIAQABNQAECgkJFgAUAD0NAA==.Zanki:BAAANQAECgUIBQAAAA==.',
Ze='Zeebeth:BAABNQAECoEXAAIJAAgKGQ4OdQD4AQAJAAgKGQ4OdQD4AQAAAA==.Zefi:BAAANQAECgcIAgAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zenbu:BAAANQADCgIIAgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgYIFgAeAEIlAA==.Zerokai:BAAANQAECgUIBAAAAA==.Zeztz:BAAANQAECgcIDAAAAA==.',
Zo='Zomlo:BAAANQAECgEIAQAAAA==.Zooli:BAAANQADCggICAAAAA==.Zorosenpai:BAAANQADCgcIEQAAAA==.',
Zu='Zuggernaught:BAAANQADCgQIBgAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Âr']='Ârtemis:BAAANQADCggICAABNQAECgkJJwAFAEcgAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQAECgYICgAAAA==.',
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
