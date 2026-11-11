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

local lookup = {'Mage-Arcane','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Blood','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Rogue-Outlaw',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abrakådabruh:BAABNQAECn8oAAIBAAoKtw7BygDwAQABAAoKtw7BygDwAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQAECgQIBgAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8rAAICAAoKqxWofAAxAgACAAoKqxWofAAxAgAAAA==.',
Ai='Ainjel:BAAANQAECgMIAwAAAA==.Ainz:BAAANQAECgEIAQAAAA==.',
Ak='Akaitsuki:BAABNQAECn8mAAMDAAkKkRQ3DwAeAgADAAkKkRQ3DwAeAgAEAAQKzAEcZAB1AAAAAA==.',
Al='Alex:BAAANQAECgIIAwAAAA==.Alexdh:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Alexr:BAAANQAECgEIAQAAAA==.Alexxh:BAAANQADCgMIAwABNQAECgEIAQAFAAAAAA==.',
Am='Amarantus:BAAANQAECggIDQABNQAECgoKRAAGAOQdAA==.Amarndeus:BAAANQABCgcICQAAAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8mAAMHAAgKRRpfIAB/AgAHAAgKphlfIAB/AgAIAAgK+hCKRgDLAQABNQAFFAcIFAAJAK8XAA==.Anmodru:BAAANQADCgUIBQABNQAFFAcIFAAJAK8XAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAACNQAFFH8IAAIKAAMKDB18AQD/AAAKAAMKDB18AQD/AAA1AAQKfy8AAgoACgpeIvwDABMDAAoACgpeIvwDABMDAAAA.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arcanizzon:BAAANQADCggICAAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgYICgAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Ashanor:BAAANQAECgEIAQAAAA==.Astravelle:BAABNQAECn8UAAILAAUKXhj5LgAFAQALAAUKXhj5LgAFAQAAAA==.',
At='Athená:BAAANQAECgYIDAABNQAECgoKPAAMAMYeAA==.Athenä:BAABNQAECn88AAIMAAoKxh5vDADOAgAMAAoKxh5vDADOAgAAAA==.',
Au='Aubrii:BAAANQAECgQICQAAAA==.Aukatsang:BAABNQAECn8iAAMNAAkKKyEdEwDBAgANAAkKKyEdEwDBAgAOAAEKvAxbJAA4AAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEQAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8mAAIPAAoKcyAUDwCrAgAPAAoKcyAUDwCrAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxpCtAAbAgABAAcKwxpCtAAbAgABNQAECgkJGAAQAFcmAA==.Barbaricboss:BAAANQAECgQIBwAAAA==.Barrak:BAABNQAECn8iAAMRAAoKGhIyeQCgAQARAAkKlhAyeQCgAQASAAUKxhAPhgDrAAABNQAECgoKKwACAKsVAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8mAAITAAoK3B2nBQDDAgATAAoK3B2nBQDDAgAAAA==.Beersnob:BAABNQAECn8iAAINAAkKeAtFMwB8AQANAAkKeAtFMwB8AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8kAAISAAYKYhWDCAA9AQASAAYKYhWDCAA9AQA1AAQKfy4AAhIACgo0I/oQAGYDABIACgo0I/oQAGYDAAAA.Bigmikeyg:BAABNQAECn8mAAICAAgKZwt70wB1AQACAAgKZwt70wB1AQAAAA==.Bigsteve:BAABNQAECn8kAAMUAAoKhBjpgAAZAgAUAAoKNxjpgAAZAgATAAEK1htYLABTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Bodysnatcher:BAAANQAECgUIBQAAAA==.Bojak:BAAANQAECgYIBgAAAA==.Boomchickun:BAAANQAECgEIAQABNQAFFAYIFgAVAGwWAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAFFAMICAAKAAwdAA==.Bronzesun:BAAANQADCggIEAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8pAAIRAAoK+RQGPgAHAgARAAoK+RQGPgAHAgAAAA==.',
['Bø']='Bønd:BAAANQAECgQICAAAAA==.',
Ca='Caicos:BAECNQAFFH8GAAIWAAQK+wEeCwCcAAAWAAQK+wEeCwCcAAA1AAQKf0oABBYACgo2E84IAOEBABYACgo2E84IAOEBABcAAwotCihBAJgAABgAAQpXAQ0pABkAAAAA.Calizon:BAABNQAECn8hAAIPAAoKHwtgJQAvAQAPAAoKHwtgJQAvAQAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8rAAISAAgKcQZnegAIAQASAAgKcQZnegAIAQAAAA==.Caser:BAAANQADCgMJAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgQIAwAAAA==.',
Ce='Celenus:BAAANQAECggIEAAAAA==.Cell:BAACNQAFFH8RAAIUAAcKpQvDDgDIAQAUAAcKpQvDDgDIAQA1AAQKf0wAAxQACgpCI+cNAIsDABQACgpCI+cNAIsDABkABAo1GvYjAMQAAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8WAAIVAAYKbBakBAArAQAVAAYKbBakBAArAQA1AAQKf0wAAhUACgqNItcEABADABUACgqNItcEABADAAAA.Cereall:BAAANQAECgUICAAAAA==.Cereas:BAABNQAECn8xAAIMAAoKahTCLAA9AgAMAAoKahTCLAA9AgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgcICwAAAA==.Chevota:BAEANQADCggIBwABNQAFFAQIBgAWAPsBAA==.Chicoh:BAAANQABCgYIBgAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAgAAAA==.Cloud:BAABNQAECn8sAAIUAAoKbxqcTwCbAgAUAAoKbxqcTwCbAgAAAA==.Clukdogg:BAABNQAECn8UAAIaAAgKRxobfAAWAgAaAAgKRxobfAAWAgAAAA==.',
Co='Combination:BAACNQAFFH8XAAMbAAcKog+YBADPAAAcAAYK/A7gDQAuAQAbAAMKBwyYBADPAAA1AAQKf0kAAxsACgpmIf0FALACABwACQrVIRMnAOgCABsACQq+F/0FALACAAAA.Corva:BAAANQAECgMIBAABNQAECggICgAFAAAAAA==.Corvenall:BAABNQAECn84AAIWAAoK0xPRCwCKAQAWAAoK0xPRCwCKAQAAAA==.Corwyn:BAABNQAECn82AAIcAAoKlQSqkAAkAQAcAAoKlQSqkAAkAQAAAA==.',
Cr='Crashpad:BAAANQAECgUICgAAAA==.Crosben:BAAANQAECgIIAgAAAA==.Crossbow:BAABNQAECn81AAIaAAoKLBj4QACoAgAaAAoKLBj4QACoAgAAAA==.',
['Cõ']='Cõnker:BAAANQAECgIIAgAAAA==.',
Da='Daggers:BAAANQAECgUIBgAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQAECgIIAgAAAA==.Danglyudders:BAAANQAECgQIBwAAAA==.Danidani:BAABNQAECn80AAIQAAoK+yEQIgDmAgAQAAoK+yEQIgDmAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIBQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davand:BAAANQABCgIIAgAAAA==.Davinah:BAABNQAECn8eAAIRAAoKgQxaXACNAQARAAoKgQxaXACNAQAAAA==.Dayje:BAAANQADCgUICAAAAA==.Dazarn:BAAANQADCgUIBQAAAA==.',
De='Deathation:BAAANQAECggICgAAAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAABNQAECn8gAAIcAAoKTAWN0QAmAQAcAAoKTAWN0QAmAQAAAA==.Demontoarch:BAAANQAECgIIAgAAAA==.Devoutheart:BAAANQAECgEIAQABNQAECgEIAwAFAAAAAA==.',
Di='Diehappy:BAAANQAECgMIBAAAAA==.Dishonor:BAAANQADCgYIDwAAAA==.',
Do='Dommage:BAABNQAECn80AAIBAAoKhCLhEgD5AgABAAoKhCLhEgD5AgABNQAFFAcIFAALABcgAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAABNQAECn85AAQEAAoKvhI7IgDJAQAEAAkKiBQ7IgDJAQAGAAgKsg5ZSgDjAAALAAIKKgWoXwA1AAAAAA==.Drywar:BAACNQAFFH8TAAIUAAYKFhxoDwAuAQAUAAYKFhxoDwAuAQA1AAQKfy8AAhQACgpFI3Y4AOMCABQACgpFI3Y4AOMCAAAA.',
Dt='Dtinnel:BAABNQAECn8hAAIUAAoK1xCOmQDcAQAUAAoK1xCOmQDcAQABNQAFFAUIDAAdAJIcAA==.',
Du='Duck:BAAANQAECgEIAgAAAA==.',
Dw='Dway:BAAANQADCgUICQAAAA==.',
['Dà']='Dànger:BAAANQAECgYIDwAAAA==.',
Ec='Echidna:BAAANQAECgYICAAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn89AAIUAAoKiCEUIwCrAgAUAAoKiCEUIwCrAgAAAA==.',
Ei='Eisla:BAABNQAECn8kAAIHAAoK+RKQPADfAQAHAAoK+RKQPADfAQAAAA==.',
El='Elfor:BAAANQAECgQICAABNQAECgoKMQAMAGoUAA==.Elpicosito:BAAANQAECgUIBgAAAA==.',
Em='Emmone:BAAANQAECgQICgAAAA==.',
Ep='Epiconx:BAAANQADCgEIAQAAAA==.',
Ex='Exacerbator:BAAANQAECgEIAQAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Farglight:BAAANQAECgEIAQAAAA==.Faunna:BAABNQAECn9EAAIGAAoK5B3PEgB8AgAGAAoK5B3PEgB8AgAAAA==.',
Fe='Fearbomb:BAAANQAECgEIAQAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8lAAMBAAoKPwRsJwFKAQABAAoKPwRsJwFKAQAeAAEKAABbVAAbAAAAAA==.Feet:BAAANQAECgEIAgAAAA==.Felaz:BAABNQAECn9IAAIBAAoKNB0xLACDAgABAAoKNB0xLACDAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAACNQAFFH8GAAIQAAMKwxfEHADwAAAQAAMKwxfEHADwAAA1AAQKf00AAxAACgoWJLcDAPADABAACgoWJLcDAPADAB8ABQrbBugVAM0AAAAA.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAABNQAECn8qAAIgAAcKzwZUZwADAQAgAAcKzwZUZwADAQAAAA==.',
Fr='Friday:BAACNQAFFH8FAAMRAAIKPRMoIQCCAAARAAIKPRMoIQCCAAASAAEKcwHANgA4AAA1AAQKfzcAAxEACgpNF4M3ACYCABEACgpNF4M3ACYCABIABgoxDYZ+AP4AAAAA.Frikilatar:BAAANQAECgEIAgAAAA==.Frrank:BAACNQAFFH8TAAIUAAcKJibKBQD+AQAUAAcKJibKBQD+AQA1AAQKfz0AAhQACgrBJmMDAN4DABQACgrBJmMDAN4DAAAA.',
Ga='Galcain:BAABNQAECn8uAAMaAAoKsyObJgD9AgAaAAoKxSKbJgD9AgAhAAcKwhguMADMAQAAAA==.Garbagio:BAAANQABCggIDwAAAA==.',
Gl='Gleam:BAAANQABCgIIAgAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Gorizarev:BAAANQAECgMIAwABNQAECgYIDwAFAAAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQAECgQIBAAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECn8xAAIhAAoKqhVzIwAyAgAhAAoKqhVzIwAyAgABNQAFFAcIFwAbAKIPAA==.Grimstar:BAAANQAECgEIAQAAAA==.Growlyr:BAABNQAECn8nAAMdAAoKCCK3GgDsAgAdAAoKCCK3GgDsAgAgAAQKUBlVZQDtAAAAAA==.Grumandel:BAABNQAECn8oAAIDAAoK9BTJDwARAgADAAoK9BTJDwARAgAAAA==.',
Ha='Hailstrike:BAABNQAECn8pAAMiAAoK8Rr1EwBjAgAiAAoK8Rr1EwBjAgAgAAEK9w1+pgA9AAAAAA==.Hakur:BAABNQAECn9GAAICAAoK/xGHcwDUAQACAAoK/xGHcwDUAQAAAA==.Halfpink:BAAANQAECgUIDgABNQAECgkJJwAGAKcXAA==.Hamahara:BAAANQAECgEIAQAAAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8uAAIdAAoKQh3UDgCDAgAdAAoKQh3UDgCDAgAAAA==.Harribel:BAABNQAECn8mAAMeAAoKUQomGgDwAAABAAcKLgbcEwFrAQAeAAQKfg4mGgDwAAAAAA==.',
He='Heiferina:BAABNQAECn8dAAIaAAoKJQkGhQCTAQAaAAoKJQkGhQCTAQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAACNQAFFH8PAAQbAAcKbhF9AAA+AQAbAAQK2RF9AAA+AQAcAAQKFgjzIADvAAAjAAEKAADdGQAAAAA1AAQKfxoABBsACQoCH3MUAMsBABwACAqAFjl3AP0BABsABQqyHXMUAMsBACMAAwqMHKITAOEAAAAA.Help:BAAANQADCggIFwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQAECggIDAAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAwAAAA==.',
Ic='Icies:BAABNQAECn8rAAIeAAkKJxRkDAD1AQAeAAkKJxRkDAD1AQAAAA==.',
Ig='Ignacia:BAAANQAFFAEIAQAAAA==.',
Il='Ilos:BAAANQAECggIEwAAAA==.',
Im='Immafrogger:BAAANQAECgYICQABNQAECgoKJgAQAPsgAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwASAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECggIDwAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECn8zAAIBAAoKGRHpfQCcAQABAAoKGRHpfQCcAQAAAA==.',
Je='Jehannum:BAABNQAECn8lAAISAAoKDg+HfQCrAQASAAoKDg+HfQCrAQAAAA==.Jessira:BAAANQAECgUJEgAAAA==.',
Jo='Jonahheal:BAABNQAECn8XAAIkAAoKjRxCHAADAwAkAAoKjRxCHAADAwABNQAFFAcIGAARANYfAA==.Josen:BAABNQAECn8aAAIPAAcKUBfSHgDxAQAPAAcKUBfSHgDxAQAAAA==.',
Ka='Kach:BAAANQAECgIIAwAAAA==.Kaefaith:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgYIFwAAAA==.Kainiy:BAAANQADCgcIIQAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECn8oAAQNAAoKWBLsJAD9AQANAAoKSxLsJAD9AQAOAAcKgAfJGwAqAQAlAAYKDgywLgD1AAAAAA==.Katarena:BAABNQAECn8kAAIkAAoKTwiihACNAQAkAAoKTwiihACNAQAAAA==.Kathyra:BAEBNQAECn82AAMcAAkKHBV3OQCnAgAcAAkKHBV3OQCnAgAbAAEKfwLghgAhAAABNQAFFAQIBgAWAPsBAA==.Kavax:BAABNQAECn8XAAIkAAYK1BEfkABtAQAkAAYK1BEfkABtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIBQAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kelorth:BAAANQADCgcIBgAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAgAAAA==.',
Ki='Kinký:BAABNQAECn82AAIUAAoKlxFGWgDcAQAUAAoKlxFGWgDcAQABNQAECgEIAQAFAAAAAA==.Kiraelis:BAABNQAECn8yAAIhAAoKGBd6FwDAAQAhAAoKGBd6FwDAAQAAAA==.',
Ko='Konvik:BAAANQADCgUIDQAAAA==.Korvoh:BAABNQAECn8qAAIfAAoKJhTDCADUAQAfAAoKJhTDCADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8UAAIQAAYK5xsXCAAKAgAQAAYK5xsXCAAKAgA1AAQKfzEAAxAACgoGHc4WAA8DABAACgoGHc4WAA8DAB8ABQpTByoWAMkAAAAA.Krystn:BAAANQAECgIIBgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAUIDAAdAJIcAA==.',
Kw='Kwinny:BAABNQAECn8pAAMkAAoK2xy6LwCnAgAkAAoK2xy6LwCnAgACAAEKwQcEhwE1AAAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynalin:BAAANQADCgEIAQAAAA==.Kynthria:BAAANQAECgYIEgABNQAECgoKGAABAOkeAA==.',
['Kä']='Kämik:BAABNQAECn8jAAMaAAgKbRdRfgARAgAaAAgKbRdRfgARAgAhAAEKAACZjAAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECn8jAAIVAAoKPgcWMQC4AQAVAAoKPgcWMQC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECgoKMAAdAFchAA==.Lasstchance:BAAANQAECgMIAwAAAA==.Latinamaddog:BAABNQAECn8wAAIcAAoKuBpROAAgAgAcAAoKuBpROAAgAgAAAA==.',
Le='Lelathon:BAAANQAECggICgAAAA==.Lenard:BAAANQAECgYIDQAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Lieb:BAAANQADCgcIBwAAAA==.Lightstorms:BAAANQADCgcIBwAAAA==.Lijepa:BAAANQABCgEIAQAAAA==.Likeatrain:BAABNQAECn84AAMZAAgK2g25GgAZAQAZAAgK2g25GgAZAQAUAAEKAAANRwEAAAAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8gAAIkAAoKPRSxbgDMAQAkAAoKPRSxbgDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgEIBgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.Loopdog:BAAANQAECgQIBwAAAA==.',
Lt='Ltdanslegs:BAABNQAECn81AAINAAoKkB2tDACEAgANAAoKkB2tDACEAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECn9LAAIiAAoKtyJGDgA9AwAiAAoKtyJGDgA9AwAAAA==.Luxzy:BAAANQAECgYIDwAAAA==.',
Ma='Magdog:BAAANQADCgMIBAAAAA==.Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgcIDgAAAA==.Malachron:BAABNQAECn8YAAIcAAgKLRSpkAC9AQAcAAgKLRSpkAC9AQAAAA==.Manbearcat:BAABNQAECn8nAAMGAAkKpxfGIADjAQAGAAkKpxfGIADjAQAEAAIKGQSLbgA2AAAAAA==.Manzanoso:BAAANQADCggIGAAAAA==.Marbleous:BAABNQAECn8rAAIUAAgKjiANPgDRAgAUAAgKjiANPgDRAgAAAA==.Maybebeef:BAAANQAECgIIAgABNQAFFAQICgAUAGQUAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgkJJwAGAKcXAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgoKMAAdAFchAA==.Melancholic:BAAANQAECgEIAQABNQAECgcIDgAFAAAAAA==.Melhina:BAAANQAECgQIBAABNQAECgoKLQAjAN8WAA==.Memisstotem:BAABNQAECn8fAAMRAAkK4QsYegCdAQARAAgKTQwYegCdAQASAAUKAhKvsgAtAQAAAA==.Merle:BAABNQAECn83AAMUAAoKxB8fLwABAwAUAAoKxB8fLwABAwATAAUKPxksGAAcAQAAAA==.',
Mi='Mikarri:BAAANQAECgEIAgAAAA==.Minaxy:BAABNQAECn9AAAICAAkKqB9yKgAdAwACAAkKqB9yKgAdAwAAAA==.Miranza:BAAANQAECgYIDAAAAA==.Mistborn:BAABNQAECn8YAAIQAAkKVyYUJADcAgAQAAkKVyYUJADcAgAAAA==.Mistodon:BAAANQABCgcIDwAAAA==.Mistsofpoly:BAAANQAECgMIBAABNQAFFAcIEgARAGYPAA==.Mizzon:BAAANQADCggIEQAAAA==.',
Mo='Momoku:BAABNQAECn8mAAIDAAgKVx5NCwB6AgADAAgKVx5NCwB6AgAAAA==.Moolimbo:BAABNQAECn8ZAAISAAkKORNSRQCoAQASAAkKORNSRQCoAQABNQAECgoKNwAGAMIUAA==.Mootalstrike:BAABNQAECn8bAAIUAAoKOw77swCbAQAUAAoKOw77swCbAQAAAA==.Moshworm:BAABNQAECn8pAAIGAAoK5Qg7SADtAAAGAAoK5Qg7SADtAAAAAA==.',
Mu='Muramasa:BAAANQAECgcICgABNQAFFAUIDAAdAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Nadlus:BAAANQAECgUIBQAAAA==.Nalaxx:BAAANQAECgEIAQAAAA==.Namis:BAAANQAECgQICAAAAA==.',
Ne='Nelaphim:BAABNQAECn8rAAMeAAoKbByUCwAHAgAeAAoKbByUCwAHAgABAAYK2AusHQFaAQAAAA==.Neversneaky:BAAANQAECggIDAABNQAECgoKKQAiAPEaAA==.Nexassin:BAAANQAECgUICAAAAA==.',
Ni='Nico:BAABNQAECn8pAAIaAAkKTB3BQgCjAgAaAAkKTB3BQgCjAgAAAA==.Nimz:BAABNQAECn8dAAQbAAgKhx4lHgB9AQAcAAgKdRXwowCNAQAbAAUK/h8lHgB9AQAjAAYKfhigDwAlAQABNQAECgoKMAAdAFchAA==.',
No='Noctrine:BAAANQAECgEIAgAAAA==.Noxxidari:BAABNQAECn81AAIVAAoKtxw2DwBVAgAVAAoKtxw2DwBVAgAAAA==.Noxxus:BAABNQAECn8sAAIPAAoK1hh2DgAwAgAPAAoK1hh2DgAwAgABNQAECgoKNQAVALccAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECggIEgABNQAECgoKMAAdAFchAA==.',
Oa='Oakenshade:BAAANQADCgcICQAAAA==.',
Ob='Oblivia:BAAANQAECgEIAgAAAA==.Obsidiansoul:BAAANQAECgMIAwAAAA==.',
Og='Oghma:BAAANQAECgcICgAAAA==.',
Ol='Oldmans:BAAANQADCgIIAgAAAA==.',
Om='Omnivus:BAAANQAECgEIAgAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgoKMgAUAI4fAA==.Onepunch:BAAANQADCgcIBwAAAA==.Onezero:BAAANQADCgYICQAAAA==.',
Or='Orchist:BAABNQAECn8mAAITAAgKVh72BQBaAgATAAgKVh72BQBaAgAAAA==.Orimbo:BAABNQAECn83AAMGAAoKwhRbXABgAQAGAAcKDxBbXABgAQAEAAQKZgcHWQB+AAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICAABNQAECgIIBgAFAAAAAA==.',
Pa='Paidu:BAACNQAFFH8TAAQKAAcK7w12AgC0AAAMAAUKaBF3DQA2AQAKAAQKwBB2AgC0AAAVAAIKkgLvEABHAAA1AAQKfzMABAoACgquHrQFAEcCAAwACgpmHU0oAFwCAAoACAqdHrQFAEcCABUACAqzCj00AKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgkJGAAQAFcmAA==.',
Pe='Pestilancé:BAABNQAECn8qAAIgAAoKtQRabwDhAAAgAAoKtQRabwDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgYIBgAAAA==.',
Pi='Pingpaung:BAAANQAECgQIBQAAAA==.Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Piratecass:BAAANQAECgcICQAAAA==.Pitchblende:BAABNQAECn80AAIkAAoKDROxZwDgAQAkAAoKDROxZwDgAQAAAA==.',
Po='Polylock:BAAANQAECggIEAAAAA==.Portiaa:BAABNQAECn8VAAMBAAgKZwiDEQFvAQABAAcKYgeDEQFvAQAeAAIKgA1WNgBjAAAAAA==.Pothette:BAAANQAECgIIAgABNQAECgoKNAAmANEZAA==.',
Pr='Prangkim:BAAANQAECgIIAgAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBgAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAABNQAECn8UAAIZAAUKihUhJADDAAAZAAUKihUhJADDAAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Raszageth:BAAANQAECgEIAQAAAA==.Rathidk:BAACNQAFFH8OAAIiAAcK5hlbCgCyAQAiAAcK5hlbCgCyAQA1AAQKf1AAAiIACgr0IygGAJIDACIACgr0IygGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgMIBAAAAA==.Rendis:BAAANQAECgQIBwAAAA==.',
Rh='Rhayge:BAABNQAECn8qAAMJAAoK5A3jGADYAQAJAAoK5A3jGADYAQARAAYK6gd80QDEAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8MAAIdAAUKkhyEBwDbAAAdAAUKkhyEBwDbAAA1AAQKf2MAAh0ACgr8JYEHAIgDAB0ACgr8JYEHAIgDAAAA.',
['Ré']='Révölt:BAAANQAECgMIAwAAAA==.',
Sa='Saboo:BAABNQAECn8yAAIjAAoKpRaIBgBDAgAjAAoKpRaIBgBDAgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECn8nAAIXAAkKhxWPHQD1AQAXAAkKhxWPHQD1AQABNQAECgoKNQANAJAdAA==.Sapientia:BAABNQAECn8hAAICAAgKeAa87gA/AQACAAgKeAa87gA/AQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAgIGAABAG0PAA==.',
Se='Seasnan:BAAANQAECgIIAgAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAABNQAECn8VAAIRAAgKCxIbbQDEAQARAAgKCxIbbQDEAQAAAA==.Senapally:BAAANQADCgQIBAABNQAECggIDQAFAAAAAA==.Senlock:BAAANQABCgIIAgABNQAECggIDQAFAAAAAA==.',
Sh='Shadizzon:BAAANQADCgQIBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECn8qAAMgAAkKKQVJYAAkAQAgAAkKKQVJYAAkAQAdAAEK2gMZjAAoAAAAAA==.Shadowheàrt:BAABNQAECn8WAAIkAAcKpQt4nQBMAQAkAAcKpQt4nQBMAQAAAA==.Shadowshifty:BAAANQADCgcIDQAAAA==.Shadowtotem:BAABNQAECn8XAAMRAAkKYwpyngA6AQARAAkKYwpyngA6AQASAAUKrAWuwwBxAAAAAA==.Shagi:BAAANQAECgQIBwAAAA==.Shamdü:BAABNQAECn9DAAIUAAoKJiKnFgBfAwAUAAoKJiKnFgBfAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQAECgEIAQABNQAFFAUIDAAdAJIcAA==.Shockybalboa:BAABNQAECn8XAAISAAgKZAgWmgBkAQASAAgKZAgWmgBkAQAAAA==.Showerthots:BAAANQAECgUIDwAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECn83AAISAAoKLhZ2LgALAgASAAoKLhZ2LgALAgAAAA==.Skybles:BAAANQAECgUICQAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECn8qAAIVAAoK8hT2JgANAgAVAAoK8hT2JgANAgAAAA==.Skyknight:BAABNQAECn8iAAITAAkK1RjdCABSAgATAAkK1RjdCABSAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQADCgIIAgAAAA==.',
So='Solcon:BAABNQAECn8gAAIMAAoKhRgDNQAGAgAMAAoKhRgDNQAGAgAAAA==.Solence:BAAANQAECgEIBAAAAA==.Somebodie:BAAANQAECgQICwAAAA==.',
Sp='Spaazz:BAABNQAECn8nAAICAAoKBRXVmwDrAQACAAoKBRXVmwDrAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.Speedrunner:BAAANQAECgEIAQAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgoKLAAQAK8QAA==.Staroflight:BAAANQAECgEIAQABNQAECgoKLAAQAK8QAA==.Starweaver:BAABNQAECn8sAAMQAAoKrxBuRQANAgAQAAoKrxBuRQANAgAfAAEKtgFQMwAZAAAAAA==.Stormrender:BAABNQAECn84AAQNAAoKqxTAHgCTAQANAAoKqxTAHgCTAQAlAAMKvgYoSABJAAAOAAEK+AEQKgAcAAAAAA==.Stormsong:BAACNQAFFH8FAAISAAMKuxFVGgDvAAASAAMKuxFVGgDvAAA1AAQKfxkAAxIACQqlHOE1AKACABIACQqlHOE1AKACABEAAwryCg3wAIoAAAAA.Strangecandy:BAABNQAECn8qAAIVAAkK+gpFJQBbAQAVAAkK+gpFJQBbAQAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECgoKOAANAKsUAA==.',
Su='Sublïminals:BAABNQAECn9BAAQkAAoKCyQAAgATBAAkAAoKCyQAAgATBAACAAgKmRqnmQDwAQAPAAMKkCGHRQDaAAAAAA==.Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAABNQAECn8iAAIBAAoKiRHjWQD3AQABAAoKiRHjWQD3AQAAAA==.Superpull:BAAANQAECgUICQABNQAECgIIAgAFAAAAAA==.',
Sy='Sycla:BAABNQAECn8pAAMbAAoKMhq3GACmAQAcAAgK6hf5iwDJAQAbAAYKMBi3GACmAQAAAA==.Syedrine:BAAANQAECgQIDAAAAA==.Sylas:BAAANQAECgQICQAAAA==.',
Ta='Tab:BAAANQAECgUICwAAAA==.Taloriesh:BAABNQAECn8oAAMQAAoKYxk3KQCTAgAQAAoKYxk3KQCTAgAnAAQKqQpcPwCeAAAAAA==.Tanazir:BAEANQAECgUICgAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECggICgAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAABNQAECn8XAAMRAAgK7BsVVAAXAgARAAgK7BsVVAAXAgASAAIKYyP90ABdAAAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8qAAQcAAoKriTRDQBgAwAcAAoKWSTRDQBgAwAbAAgKFSMWCgBWAgAjAAYKViEGCwDAAQAAAA==.Tilatree:BAAANQAECgEIBAABNQAECgoKKgAcAK4kAA==.Tillidari:BAAANQAECgQIDAABNQAECgoKKgAcAK4kAA==.',
To='Tohrnamental:BAAANQAECgMIBAAAAA==.Tohrnarc:BAABNQAECn8nAAIBAAoKlSCqiwBoAgABAAoKlSCqiwBoAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQICAAAAA==.Totemwebz:BAABNQAECn8eAAIRAAcKXh1sUgAdAgARAAcKXh1sUgAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8xAAIEAAoKWR+SDQDYAgAEAAoKWR+SDQDYAgAAAA==.',
Ts='Tseirpa:BAAANQADCgQIBQAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECn8zAAIRAAoKdxzfNgCDAgARAAoKdxzfNgCDAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIEAAAAA==.',
Ty='Tyrethia:BAABNQAECn8VAAIUAAcKNRoXqwCxAQAUAAcKNRoXqwCxAQABNQAECggICgAFAAAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8HAAIbAAMKYgODDACfAAAbAAMKYgODDACfAAA1AAQKf2MAAhsACgpJHXcBAKACABsACgpJHXcBAKACAAAA.',
Ug='Uggaibo:BAAANQADCgcIDgAAAA==.Ugo:BAAANQAECgQIBQAAAA==.',
Um='Umbron:BAABNQAECn8jAAQHAAkKcRk+HACcAgAHAAkKDhg+HACcAgAIAAcK9xhJHQDoAQAoAAEKMA+DHAAvAAAAAA==.Umbrute:BAAANQAECgEIAQABNQAECgkJIwAHAHEZAA==.',
Un='Undertaker:BAAANQAECgEIAgAAAA==.',
Va='Valcristo:BAABNQAECn8rAAIPAAoKcCQBDwCsAgAPAAoKcCQBDwCsAgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.',
Ve='Venous:BAABNQAECn8oAAMHAAoK3RVFSQCfAQAHAAcKMBJFSQCfAQAIAAkKohGiKgBuAQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFH8UAAMnAAcKyh8XBQBYAQAnAAUK+x0XBQBYAQAQAAQKkgIPJAC6AAA1AAQKf0QABCcACgqDIXsKAKcCACcACgqDIXsKAKcCAB8ABgpnJJAEAH4CABAACQqgFvBQADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQAECgEIAQAAAA==.Viduus:BAABNQAECn8wAAMdAAoKVyGmEABrAgAdAAoKVyGmEABrAgAgAAgKrxYZQgC9AQAAAA==.Viv:BAABNQAECn8xAAMCAAoKSRjVWAAUAgACAAoKSRjVWAAUAgAkAAMKEyCTuwAFAQAAAA==.',
Vo='Vodmor:BAABNQAECn8qAAICAAoK7AXJugBGAQACAAoK7AXJugBGAQAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.Voran:BAAANQADCgIIAgAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.Waygun:BAAANQADCggICQAAAA==.',
We='Wedowarcrime:BAAANQAECgEIAQAAAA==.',
Wh='Whims:BAABNQAECn89AAIbAAoK3BGuAwDfAQAbAAoK3BGuAwDfAQAAAA==.',
Wi='Wildheart:BAAANQAECgEIAwAAAA==.Windgoddess:BAAANQADCggICAAAAA==.Wingchún:BAABNQAECn8UAAINAAgK7wtfIgBxAQANAAgK7wtfIgBxAQAAAA==.',
Wo='Woregontail:BAAANQAECgQICAAAAA==.Wowbelly:BAABNQAECn8YAAIlAAoKdiG6CQDuAgAlAAoKdiG6CQDuAgAAAA==.',
Xa='Xalrissa:BAAANQADCgUICgAAAA==.Xandeath:BAABNQAECn8WAAQiAAgKnA6COgBJAQAiAAcKuxCCOgBJAQAgAAMKfAPemgBdAAAdAAEKTgVX7AApAAAAAA==.Xandem:BAAANQAECgUIBQAAAA==.Xandros:BAABNQAECn8VAAIjAAcKKxBQCwC3AQAjAAcKKxBQCwC3AQAAAA==.Xanlight:BAAANQADCgIIAgAAAA==.',
Xo='Xonk:BAACNQAFFH8KAAIjAAQKCA41AwDKAAAjAAQKCA41AwDKAAA1AAQKfzgAAyMACgqyGzwEAJ8CACMACgqyGzwEAJ8CABsAAQqMG2JoAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcIDQAAAA==.',
Ys='Ysondrie:BAAANQAECgUIBQAAAA==.',
Za='Zaklu:BAAANQAECgIIBgAAAA==.Zalagrimbor:BAABNQAECn8fAAMSAAkKeBcKRwBaAgASAAkKeBcKRwBaAgARAAMKgAWC/wBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECn8tAAISAAoKeCDQIgD9AgASAAoKeCDQIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIhAAYKchlBBgDzAQAhAAYKchlBBgDzAQA1AAQKfyoAAiEACQoAI4cNAAYDACEACQoAI4cNAAYDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQAECgQIBwAFAAAAAA==.Zelie:BAABNQAECn8rAAMRAAoK3gu9gACKAQARAAoK3gu9gACKAQASAAUK4wDHDwFsAAAAAA==.Zenira:BAAANQAECgEIAQABNQAECggIDwAFAAAAAA==.Zenreto:BAABNQAECn8oAAIHAAoKZBSjMgATAgAHAAoKZBSjMgATAgAAAA==.',
Zh='Zhuri:BAAANQADCggIEgAAAA==.',
Zo='Zoeri:BAAANQAECgQICwAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFH8UAAIJAAcKrxciAQCAAQAJAAcKrxciAQCAAQA1AAQKf0sAAgkACgpsJbsBAJ0DAAkACgpsJbsBAJ0DAAAA.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
