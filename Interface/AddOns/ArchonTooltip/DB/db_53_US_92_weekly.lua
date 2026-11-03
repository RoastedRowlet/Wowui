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

local lookup = {'Mage-Arcane','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Blood','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Rogue-Outlaw',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abrakådabruh:BAABNQAECn8kAAIBAAgKoxDBygDwAQABAAgKoxDBygDwAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQAECgQIBQAAAA==.',
Ae='Aeropos:BAAANQADCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8mAAICAAoKoBWofAAxAgACAAoKoBWofAAxAgAAAA==.',
Ai='Ainjel:BAAANQAECgMIAwAAAA==.Ainz:BAAANQADCgcICwAAAA==.',
Ak='Akaitsuki:BAABNQAECn8mAAMDAAkKkRQ3DwAeAgADAAkKkRQ3DwAeAgAEAAQKzAEcZAB1AAAAAA==.',
Al='Alex:BAAANQAECgEIAQAAAA==.Alexdh:BAAANQADCgcICAAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcICAAFAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcICAAFAAAAAA==.Alisson:BAAANQADCgEIAgABNQADCgcICAAFAAAAAA==.Alraric:BAAANQADCgEIAQAAAA==.',
Am='Amarantus:BAAANQAECggIDAABNQAECgoKQQAGALQcAA==.Amarndeus:BAAANQABCgcICQAAAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8kAAMHAAgKqxlfIAB/AgAHAAgKphlfIAB/AgAIAAYKvA6/YgAwAQABNQAFFAcIFAAJAK8XAA==.Anmodru:BAAANQADCgUIBgABNQAFFAcIFAAJAK8XAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAACNQAFFH8HAAIKAAIKHB8nAgC1AAAKAAIKHB8nAgC1AAA1AAQKfy4AAgoACgpeIvwDABMDAAoACgpeIvwDABMDAAAA.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arasha:BAAANQADCgEIAgAAAA==.Arcanizzon:BAAANQADCggICQAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgYICQAAAA==.',
As='Ashaala:BAAANQADCgEIAQAAAA==.Ashanor:BAAANQADCgEIAwAAAA==.Astravelle:BAAANQAECgUIDwAAAA==.',
At='Athená:BAAANQAECgYICQAAAA==.Athenä:BAABNQAECn8yAAILAAoKRh2MDQCmAgALAAoKRh2MDQCmAgAAAA==.',
Au='Aubrii:BAAANQAECgMIBgAAAA==.Aukatsang:BAABNQAECn8hAAMMAAkKKyEdEwDBAgAMAAkKKyEdEwDBAgANAAEKvAxTIQA5AAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8iAAIOAAgKHSEUDwCrAgAOAAgKHSEUDwCrAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxpCtAAbAgABAAcKwxpCtAAbAgAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAABNQAECn8gAAMPAAoKGhIyeQCgAQAPAAkKlhAyeQCgAQAQAAUK5AuZsgBxAAABNQAECgoKJgACAKAVAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8mAAIRAAoK3B2nBQDDAgARAAoK3B2nBQDDAgAAAA==.Beersnob:BAABNQAECn8iAAIMAAkKeAtFMwB8AQAMAAkKeAtFMwB8AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8fAAIQAAUKYhZJDQCaAQAQAAUKYhZJDQCaAQA1AAQKfy4AAhAACgo0I/oQAGYDABAACgo0I/oQAGYDAAAA.Bigmikeyg:BAABNQAECn8kAAICAAgK7Qp70wB1AQACAAgK7Qp70wB1AQAAAA==.Bigsteve:BAABNQAECn8gAAMSAAgKPhnpgAAZAgASAAgK1xjpgAAZAgARAAEK1htYLABTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Bodysnatcher:BAAANQADCgcIBwAAAA==.Bojak:BAAANQAECgUIBQAAAA==.Boomchickun:BAAANQABCgIIAgABNQAFFAYIEwATAGwWAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAFFAIIBwAKABwfAA==.Bronzesun:BAAANQADCggICAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8mAAIPAAkKJxUcRwDEAQAPAAkKJxUcRwDEAQAAAA==.',
['Bø']='Bønd:BAAANQAECgQIBgAAAA==.',
Ca='Caicos:BAECNQAFFH8GAAIUAAQK+wEeCwCcAAAUAAQK+wEeCwCcAAA1AAQKf0AABBQACgraEakIAMYBABQACgraEakIAMYBABUAAwotCihBAJgAABYAAQpXAQ0pABkAAAAA.Calizon:BAABNQAECn8hAAIOAAoKHwu6IAA0AQAOAAoKHwu6IAA0AQAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8pAAIQAAcKwAUJgQDVAAAQAAcKwAUJgQDVAAAAAA==.Caser:BAAANQADCgMJAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgQIAgAAAA==.',
Ce='Celenus:BAAANQAECggIDwAAAA==.Cell:BAACNQAFFH8RAAISAAcKpQvDDgDIAQASAAcKpQvDDgDIAQA1AAQKf0wAAxIACgpCI+cNAIsDABIACgpCI+cNAIsDABcABAo1Gj0fAMsAAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8TAAITAAYKbBbaAwAuAQATAAYKbBbaAwAuAQA1AAQKf0MAAhMACgoQImgFAPcCABMACgoQImgFAPcCAAAA.Cereall:BAAANQAECgUICAAAAA==.Cereas:BAABNQAECn8uAAILAAoKyRPCLAA9AgALAAoKyRPCLAA9AgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgcICwAAAA==.Chevota:BAEANQADCggIBwABNQAFFAQIBgAUAPsBAA==.Chicoh:BAAANQADCgEIAQAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAQAAAA==.Cloud:BAABNQAECn8sAAISAAoKbxqcTwCbAgASAAoKbxqcTwCbAgAAAA==.Clukdogg:BAABNQAECn8UAAIYAAgKRxobfAAWAgAYAAgKRxobfAAWAgAAAA==.',
Co='Combination:BAACNQAFFH8XAAMZAAcKog+YBADPAAAaAAYK/A4BCwAvAQAZAAMKBwyYBADPAAA1AAQKf0cAAxkACgpmIf0FALACABoACQrVIRMnAOgCABkACQq+F/0FALACAAAA.Corva:BAAANQAECgMIBAABNQAECgcIFQASADUaAA==.Corvenall:BAABNQAECn84AAIUAAoK0xNzCgCMAQAUAAoK0xNzCgCMAQAAAA==.Corwyn:BAABNQAECn8yAAIaAAkK/QTThgAaAQAaAAkK/QTThgAaAQAAAA==.',
Cr='Crashpad:BAAANQAECgUIBwAAAA==.Crosben:BAAANQAECgEIAQAAAA==.Crossbow:BAABNQAECn81AAIYAAoKLBj4QACoAgAYAAoKLBj4QACoAgAAAA==.',
Cy='Cyriia:BAAANQADCgEIAQAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQAECgIIAgAAAA==.Danglyudders:BAAANQAECgQIBAAAAA==.Danidani:BAABNQAECn8wAAIbAAoKmSAQIgDmAgAbAAoKmSAQIgDmAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUIDQAAAA==.Davand:BAAANQABCgIIAgAAAA==.Davinah:BAAANQAECgcIEwAAAA==.Dayje:BAAANQADCgUICAAAAA==.Dazarn:BAAANQADCgUIBQAAAA==.',
De='Deathation:BAAANQAECgYICAABNQAECgcIFQASADUaAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAABNQAECn8cAAIaAAgKzQSN0QAmAQAaAAgKzQSN0QAmAQAAAA==.Demontoarch:BAAANQAECgIIAgAAAA==.Devoutheart:BAAANQAECgEIAQABNQAECgEIAgAFAAAAAA==.',
Di='Diehappy:BAAANQAECgMIAwAAAA==.Dishonor:BAAANQADCgYIDwAAAA==.',
Do='Dommage:BAABNQAECn8wAAIBAAoKZSKbDwD/AgABAAoKZSKbDwD/AgABNQAFFAcIFAAcABcgAA==.Donkyote:BAAANQADCgEIAgAAAA==.Downbadd:BAAANQADCgEIAQAAAA==.',
Dr='Druida:BAABNQAECn8uAAQEAAoKZhEwJgB0AQAEAAkKChMwJgB0AQAGAAcK+AyoQwDlAAAcAAEKAACoXwA1AAAAAA==.Drywar:BAACNQAFFH8TAAISAAYKFhwmDAA0AQASAAYKFhwmDAA0AQA1AAQKfy4AAhIACgpFI3Y4AOMCABIACgpFI3Y4AOMCAAAA.',
Dt='Dtinnel:BAABNQAECn8hAAISAAoK1xCOmQDcAQASAAoK1xCOmQDcAQABNQAFFAUIDAAdAJIcAA==.',
Dw='Dway:BAAANQADCgUICQAAAA==.',
['Dà']='Dànger:BAAANQAECgYIDAAAAA==.',
Ec='Echidna:BAAANQAECgMIAwAAAA==.',
Ef='Efran:BAAANQADCgEIAQAAAA==.',
Eg='Ego:BAABNQAECn88AAISAAoKiCEwHQC2AgASAAoKiCEwHQC2AgAAAA==.',
Ei='Eisla:BAABNQAECn8gAAIHAAgK4hOQPADfAQAHAAgK4hOQPADfAQAAAA==.',
El='Elfor:BAAANQAECgQICAABNQAECgoKLgALAMkTAA==.Elpicosito:BAAANQAECgQIAgAAAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ep='Epiconx:BAAANQADCgEIAQAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQADCgEIAQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Farglight:BAAANQAECgEIAQAAAA==.Faunna:BAABNQAECn9BAAIGAAoKtBzMEwBUAgAGAAoKtBzMEwBUAgAAAA==.',
Fe='Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8lAAMBAAoKPwRsJwFKAQABAAoKPwRsJwFKAQAeAAEKAABbVAAbAAAAAA==.Felaz:BAABNQAECn9EAAIBAAoKUBwFKQB9AgABAAoKUBwFKQB9AgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAACNQAFFH8GAAIbAAMKwxe8GAD1AAAbAAMKwxe8GAD1AAA1AAQKf0oAAxsACgoWJL4CAP0DABsACgoWJL4CAP0DAB8ABQrbBugVAM0AAAAA.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAABNQAECn8mAAIgAAcKnQZUZwADAQAgAAcKnQZUZwADAQAAAA==.',
Fr='Friday:BAABNQAECn8zAAMPAAoKTRfHLQA6AgAPAAoKTRfHLQA6AgAQAAQKjw3GnACaAAAAAA==.Frikilatar:BAAANQAECgEIAQAAAA==.Frrank:BAACNQAFFH8TAAISAAcKJiaFAwAKAgASAAcKJiaFAwAKAgA1AAQKfzwAAhIACgrBJokCAHoDABIACgrBJokCAHoDAAAA.',
Ga='Galcain:BAABNQAECn8uAAMYAAoKsyObJgD9AgAYAAoKxSKbJgD9AgAhAAcKwhguMADMAQAAAA==.Galcoll:BAAANQADCgEIAQAAAA==.Garbagio:BAAANQABCggIDwAAAA==.',
Go='Googleyes:BAAANQADCgYIFQAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQAECgQIBAAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBQAAAA==.Grimseek:BAABNQAECn8pAAIhAAoKUhRzIwAyAgAhAAoKUhRzIwAyAgABNQAFFAcIFwAZAKIPAA==.Grimstar:BAAANQADCgEIAQAAAA==.Growlyr:BAABNQAECn8nAAMdAAoKCCK3GgDsAgAdAAoKCCK3GgDsAgAgAAQKUBkUWgDwAAAAAA==.Grumandel:BAABNQAECn8kAAIDAAgKqBbJDwARAgADAAgKqBbJDwARAgAAAA==.',
Ha='Hailstrike:BAABNQAECn8lAAIiAAoK8RqOEQBrAgAiAAoK8RqOEQBrAgAAAA==.Hakur:BAABNQAECn9CAAICAAoKnxGzaQC/AQACAAoKnxGzaQC/AQAAAA==.Halfpink:BAAANQAECgUIDgABNQAECggIHwAGAJkZAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8uAAIdAAoKQh14DACMAgAdAAoKQh14DACMAgAAAA==.Harribel:BAABNQAECn8iAAMBAAgKgAncEwFrAQABAAcKLgbcEwFrAQAeAAIKNxAfJQCBAAAAAA==.',
He='Heiferina:BAABNQAECn8dAAIYAAoKJQlldQCKAQAYAAoKJQlldQCKAQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAACNQAFFH8PAAQZAAcKbhFnAABEAQAZAAQK2RFnAABEAQAaAAQKFgjzIADvAAAjAAEKAAB9FAAAAAA1AAQKfxkABBkACQoCH3MUAMsBABoACAqAFjl3AP0BABkABQqyHXMUAMsBACMAAgoYHZYWAJIAAAAA.Help:BAAANQADCggIFAAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQAECggICwAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAABNQAECn8rAAIeAAkKJxRkDAD1AQAeAAkKJxRkDAD1AQAAAA==.',
Ig='Ignacia:BAAANQAFFAEIAQAAAA==.',
Il='Ilos:BAAANQAECggIEwAAAA==.',
Im='Immafrogger:BAAANQAECgYICQABNQAECgoKJgAbAPsgAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwAQAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECgcIDQAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jasmìne:BAAANQADCgEIAQABNQAECgoKQgAPAG4TAA==.Jawny:BAAANQADCgUIBwAAAA==.',
Jc='Jclif:BAABNQAECn8yAAIBAAoKGRFDcQCdAQABAAoKGRFDcQCdAQAAAA==.',
Je='Jehannum:BAABNQAECn8hAAIQAAgKhRCHfQCrAQAQAAgKhRCHfQCrAQAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECn8XAAIkAAoKjRxCHAADAwAkAAoKjRxCHAADAwABNQAFFAcIGAAPANYfAA==.Josen:BAABNQAECn8aAAIOAAcKUBfSHgDxAQAOAAcKUBfSHgDxAQAAAA==.',
Ka='Kach:BAAANQAECgIIAgAAAA==.Kaefaith:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgYIFwAAAA==.Kainiy:BAAANQADCgcIIQAAAA==.Kaizenn:BAAANQADCgIIAwAAAA==.Kaladjin:BAABNQAECn8oAAQMAAoKWBLsJAD9AQAMAAoKSxLsJAD9AQANAAcKgAfJGwAqAQAlAAYKDgywLgD1AAAAAA==.Katarena:BAABNQAECn8kAAIkAAoKTwiihACNAQAkAAoKTwiihACNAQAAAA==.Kathyra:BAEBNQAECn82AAMaAAkKHBV3OQCnAgAaAAkKHBV3OQCnAgAZAAEKfwLghgAhAAABNQAFFAQIBgAUAPsBAA==.Kavax:BAABNQAECn8XAAIkAAYK1BEfkABtAQAkAAYK1BEfkABtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIAgAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kelorth:BAAANQADCgcIBgAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECn8tAAISAAoKhRGsUwDPAQASAAoKhRGsUwDPAQABNQADCgcIBwAFAAAAAA==.Kiraelis:BAABNQAECn8xAAIhAAoKGBf4FAC6AQAhAAoKGBf4FAC6AQAAAA==.',
Ko='Konvik:BAAANQADCgUIDQAAAA==.Korvoh:BAABNQAECn8mAAIfAAgKXBXDCADUAQAfAAgKXBXDCADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8UAAIbAAYK5xsXCAAKAgAbAAYK5xsXCAAKAgA1AAQKfzEAAxsACgoGHVISABsDABsACgoGHVISABsDAB8ABQpTByoWAMkAAAAA.Krystn:BAAANQAECgIIAgAAAA==.',
Ku='Kumaro:BAAANQADCgEIAQAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAUIDAAdAJIcAA==.',
Kw='Kwinny:BAABNQAECn8lAAMkAAkK9Rq6LwCnAgAkAAkK9Rq6LwCnAgACAAEKwQdrZwE4AAAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynalin:BAAANQADCgEIAQAAAA==.Kynthria:BAAANQAECgYIDwABNQAECgoKGAABAOkeAA==.',
['Kä']='Kämik:BAABNQAECn8hAAMYAAgKFhdRfgARAgAYAAgKFhdRfgARAgAhAAEKAACZjAAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBgAAAA==.',
La='Lampion:BAABNQAECn8jAAITAAoKPgcWMQC4AQATAAoKPgcWMQC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECgoKLAAdAOcfAA==.Lasstchance:BAAANQAECgMIAgAAAA==.Latinamaddog:BAABNQAECn8sAAIaAAkKKRvfTABtAgAaAAkKKRvfTABtAgAAAA==.',
Le='Lelathon:BAAANQAECggICgAAAA==.Lenard:BAAANQAECgYIDQAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Lieb:BAAANQADCgcIBwAAAA==.Lightstorms:BAAANQADCgcIBwAAAA==.Lijepa:BAAANQABCgEIAQAAAA==.Likeatrain:BAABNQAECn8wAAMXAAgKUg02FwAbAQAXAAgKUg02FwAbAQASAAEKAABVNQEAAAAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8dAAIkAAoKPRSxbgDMAQAkAAoKPRSxbgDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgIIAgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.Loopdog:BAAANQAECgQIBwAAAA==.',
Lt='Ltdanslegs:BAABNQAECn8xAAIMAAoKuRwfDABzAgAMAAoKuRwfDABzAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBQAAAA==.Luciarra:BAAANQADCgEIAQAAAA==.Luxu:BAABNQAECn9FAAIiAAoKciJGDgA9AwAiAAoKciJGDgA9AwAAAA==.Luxzy:BAAANQAECgYIDAAAAA==.',
Ma='Magdog:BAAANQADCgMIBAAAAA==.Magicbarbee:BAAANQADCgYJDgAAAA==.Makarich:BAAANQAECgYIDQAAAA==.Malachron:BAABNQAECn8WAAIaAAgKLRSpkAC9AQAaAAgKLRSpkAC9AQAAAA==.Manbearcat:BAABNQAECn8fAAIGAAgKmRmVIADEAQAGAAgKmRmVIADEAQAAAA==.Manzanoso:BAAANQADCggIGAAAAA==.Marbleous:BAABNQAECn8rAAISAAgKjiANPgDRAgASAAgKjiANPgDRAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECggIHwAGAJkZAA==.',
Me='Meatcurtains:BAAANQADCgUIBgABNQAECgoKLAAdAOcfAA==.Melhina:BAAANQAECgQIBAABNQAECgkJKgAjABoXAA==.Memisstotem:BAABNQAECn8fAAMPAAkK4QsYegCdAQAPAAgKTQwYegCdAQAQAAUKAhKvsgAtAQAAAA==.Merle:BAABNQAECn83AAMSAAoKxB8fLwABAwASAAoKxB8fLwABAwARAAUKPxksGAAcAQAAAA==.',
Mi='Minaxy:BAABNQAECn88AAICAAkKqB9yKgAdAwACAAkKqB9yKgAdAwAAAA==.Miranza:BAAANQAECgUICgAAAA==.Mistborn:BAAANQAECgcIEQABNQAECgcIFwABAMMaAA==.Mistodon:BAAANQABCgcIDwAAAA==.Mistsofpoly:BAAANQAECgMIAgABNQAFFAcIEgAPAGYPAA==.Mizzon:BAAANQADCggIEgAAAA==.',
Mo='Momoku:BAABNQAECn8kAAIDAAgKRR5NCwB6AgADAAgKRR5NCwB6AgAAAA==.Moolimbo:BAAANQAECgcIDgABNQAECgoKNgAGAMIUAA==.Mootalstrike:BAABNQAECn8YAAISAAoKJQ77swCbAQASAAoKJQ77swCbAQAAAA==.Moshworm:BAABNQAECn8mAAIGAAkKxAj7ZAA5AQAGAAkKxAj7ZAA5AQAAAA==.',
Mu='Muramasa:BAAANQAECgcIBwABNQAFFAUIDAAdAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Nalaxx:BAAANQABCgUIBQAAAA==.Namis:BAAANQAECgUIBgAAAA==.',
Ne='Nelaphim:BAABNQAECn8oAAMeAAoKbByUCwAHAgAeAAoKbByUCwAHAgABAAYK2AusHQFaAQAAAA==.Neversneaky:BAAANQAECggIBwABNQAECgoKJQAiAPEaAA==.Nexassin:BAAANQAECgcIBwAAAA==.',
Ni='Nico:BAABNQAECn8pAAIYAAkKTB15MwBIAgAYAAkKTB15MwBIAgAAAA==.Nimz:BAABNQAECn8aAAQZAAgKJx4lHgB9AQAaAAgKFRXwowCNAQAZAAUK/h8lHgB9AQAjAAUKfxqcDwDxAAABNQAECgoKLAAdAOcfAA==.',
No='Noxxidari:BAABNQAECn81AAITAAoKtxy+DABkAgATAAoKtxy+DABkAgAAAA==.Noxxus:BAABNQAECn8qAAIOAAoKfhhxDAAzAgAOAAoKfhhxDAAzAgABNQAECgoKNQATALccAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECgYIDQABNQAECgoKLAAdAOcfAA==.',
Oa='Oakenshade:BAAANQADCgcICQAAAA==.',
Ob='Oblivia:BAAANQADCggIBgAAAA==.Obsidiansoul:BAAANQAECgMIAwAAAA==.',
Og='Oghma:BAAANQAECgcICAAAAA==.',
Ol='Oldmans:BAAANQADCgIIAgAAAA==.',
Om='Omnivus:BAAANQADCgEIAQAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgoKMgASAI4fAA==.Onepunch:BAAANQADCgcIBwAAAA==.Onezero:BAAANQADCgYIBgAAAA==.',
Or='Orchist:BAABNQAECn8eAAIRAAcKLx7GBwDwAQARAAcKLx7GBwDwAQAAAA==.Orimbo:BAABNQAECn82AAMGAAoKwhRbXABgAQAGAAcKDxBbXABgAQAEAAQKvQb8UQB4AAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICAABNQAECgIIAgAFAAAAAA==.',
Pa='Paidu:BAACNQAFFH8TAAQKAAcK7w0dAgC3AAALAAUKaBF3DQA2AQAKAAQKwBAdAgC3AAATAAIKkgKGDwBHAAA1AAQKfzMABAoACgquHtYEAE4CAAsACgpmHU0oAFwCAAoACAqdHtYEAE4CABMACAqzCj00AKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFwABAMMaAA==.',
Pe='Pestilancé:BAABNQAECn8mAAIgAAgKzwNabwDhAAAgAAgKzwNabwDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgYIBgAAAA==.',
Pi='Pingpaung:BAAANQAECgQIBQAAAA==.Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBQAAAA==.Piratecass:BAAANQAECgUIBAAAAA==.Pitchblende:BAABNQAECn8zAAIkAAoKDROxZwDgAQAkAAoKDROxZwDgAQAAAA==.',
Po='Polylock:BAAANQAECggIDgAAAA==.Portiaa:BAABNQAECn8VAAMBAAgKZwiDEQFvAQABAAcKYgeDEQFvAQAeAAIKgA1WNgBjAAAAAA==.Pothette:BAAANQAECgIIAgABNQAECgoKNAAmANEZAA==.',
Pr='Prangkim:BAAANQADCgUICwAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAABNQAECn8UAAIXAAUKihV5HwDJAAAXAAUKihV5HwDJAAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAACNQAFFH8OAAIiAAcK5hlbCgCyAQAiAAcK5hlbCgCyAQA1AAQKf08AAiIACgr0IygGAJIDACIACgr0IygGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgMIAwAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAABNQAECn8mAAMJAAgKvQ/jGADYAQAJAAgKvQ/jGADYAQAPAAYK6gd80QDEAAAAAA==.',
Ri='Riemann:BAAANQADCgEIAQAAAA==.',
Ro='Rockyx:BAAANQADCgEIAQAAAA==.Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8MAAIdAAUKkhyIBgDgAAAdAAUKkhyIBgDgAAA1AAQKf18AAh0ACgruJYEHAIgDAB0ACgruJYEHAIgDAAAA.',
['Ré']='Révölt:BAAANQAECgMIAwAAAA==.',
Sa='Saboo:BAABNQAECn8xAAIjAAoKSRaIBgBDAgAjAAoKSRaIBgBDAgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECn8kAAIVAAgKyhWPHQD1AQAVAAgKyhWPHQD1AQABNQAECgoKMQAMALkcAA==.Sapientia:BAABNQAECn8hAAICAAgKeAa87gA/AQACAAgKeAa87gA/AQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAgIGAABAG0PAA==.',
Se='Seasnan:BAAANQAECgIIAQAAAA==.Segur:BAAANQADCgEIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senapally:BAAANQADCgQIBQABNQAECgkJIAAYACUeAA==.Senlock:BAAANQADCgEIAQABNQAECgkJIAAYACUeAA==.',
Sh='Shadizzon:BAAANQADCgQIBQAAAA==.Shadowcloak:BAAANQADCgEIAgAAAA==.Shadowdeath:BAABNQAECn8qAAMgAAkKKQVJYAAkAQAgAAkKKQVJYAAkAQAdAAEK2gPlggApAAAAAA==.Shadowheàrt:BAAANQAECgYIEQAAAA==.Shadowshifty:BAAANQADCgcIDgAAAA==.Shadowtotem:BAAANQAECggIEQAAAA==.Shagi:BAAANQAECgIIBAAAAA==.Shamdü:BAABNQAECn9DAAISAAoKJiKnFgBfAwASAAoKJiKnFgBfAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQAECgEIAQABNQAFFAUIDAAdAJIcAA==.Shockybalboa:BAABNQAECn8XAAIQAAgKZAgWmgBkAQAQAAgKZAgWmgBkAQAAAA==.Showerthots:BAAANQAECgUICgAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEQAAAA==.',
Sk='Skooda:BAABNQAECn83AAIQAAoKLhZ/JwARAgAQAAoKLhZ/JwARAgAAAA==.Skybles:BAAANQAECgQICAAAAA==.Skyded:BAAANQADCgUIBgAAAA==.Skyfell:BAABNQAECn8qAAITAAoK8hT2JgANAgATAAoK8hT2JgANAgAAAA==.Skyknight:BAABNQAECn8iAAIRAAkK1RjdCABSAgARAAkK1RjdCABSAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQADCgEIAQAAAA==.',
So='Solcon:BAABNQAECn8cAAILAAkKxxgDNQAGAgALAAkKxxgDNQAGAgAAAA==.Solence:BAAANQAECgEIAwAAAA==.Somebodie:BAAANQAECgMIAwAAAA==.',
Sp='Spaazz:BAABNQAECn8jAAICAAgKnhfVmwDrAQACAAgKnhfVmwDrAQAAAA==.Sparkwire:BAAANQADCggICQAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIEAAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgoKLAAbAK8QAA==.Staroflight:BAAANQAECgEIAQABNQAECgoKLAAbAK8QAA==.Starweaver:BAABNQAECn8sAAMbAAoKrxCbOgAZAgAbAAoKrxCbOgAZAgAfAAEKtgFQMwAZAAAAAA==.Stormrender:BAABNQAECn82AAQMAAoKBxTSGwCQAQAMAAoKBxTSGwCQAQAlAAMK1gUoSABJAAANAAEK+AGjJgAdAAAAAA==.Stormsong:BAACNQAFFH8FAAIQAAMKuxFVGgDvAAAQAAMKuxFVGgDvAAA1AAQKfxkAAxAACQqlHOE1AKACABAACQqlHOE1AKACAA8AAwryCg3wAIoAAAAA.Strangecandy:BAABNQAECn8lAAITAAkK+gphIQBdAQATAAkK+gphIQBdAQAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECgoKNgAMAAcUAA==.',
Su='Sublïminals:BAABNQAECn86AAQkAAkKpiVLAwDbAwAkAAkKpiVLAwDbAwACAAcKmRqnmQDwAQAOAAMKkCGHRQDaAAAAAA==.Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAABNQAECn8gAAIBAAoKiRFyTwD6AQABAAoKiRFyTwD6AQAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgAFAAAAAA==.',
Sy='Sycla:BAABNQAECn8pAAMZAAoKMhq3GACmAQAaAAgK6hf5iwDJAQAZAAYKMBi3GACmAQAAAA==.Syedrine:BAAANQAECgQICAAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Tab:BAAANQAECgUICgAAAA==.Taloriesh:BAABNQAECn8bAAMbAAoKDhiJOgAZAgAbAAoKDhiJOgAZAgAnAAQKqQoGOQCeAAAAAA==.Tanazir:BAEANQAECgQIBQAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECggIBwAAAA==.',
Te='Tealzin:BAAANQADCgEIAQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECggIEwAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8pAAQaAAoKeyTRDQBgAwAaAAoKTiPRDQBgAwAZAAgKFSMWCgBWAgAjAAYKViEGCwDAAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgoKKQAaAHskAA==.Tillidari:BAAANQAECgQICgABNQAECgoKKQAaAHskAA==.',
To='Tohrnamental:BAAANQAECgMIAgAAAA==.Tohrnarc:BAABNQAECn8mAAIBAAoKlSCqiwBoAgABAAoKlSCqiwBoAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAABNQAECn8eAAIPAAcKXh1sUgAdAgAPAAcKXh1sUgAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8tAAIEAAkKHyAHDwCRAgAEAAkKHyAHDwCRAgAAAA==.',
Ts='Tseirpa:BAAANQADCgQIBgAAAA==.',
Tu='Turbomage:BAAANQADCgcICAAAAA==.Tuzzyfits:BAABNQAECn8zAAIPAAoKdxzfNgCDAgAPAAoKdxzfNgCDAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIEAAAAA==.',
Ty='Tyrethia:BAABNQAECn8VAAISAAcKNRoXqwCxAQASAAcKNRoXqwCxAQAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8HAAIZAAMKYgODDACfAAAZAAMKYgODDACfAAA1AAQKf1kAAhkACgqkG3EBAIQCABkACgqkG3EBAIQCAAAA.',
Ug='Uggaibo:BAAANQADCgcIDgAAAA==.Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECn8jAAQHAAkKcRk+HACcAgAHAAkKDhg+HACcAgAIAAcK9xhJHQDoAQAoAAEKMA+DHAAvAAAAAA==.',
Un='Undertaker:BAAANQADCgEIAQAAAA==.',
Va='Valcristo:BAABNQAECn8oAAIOAAoK+iMBDwCsAgAOAAoK+iMBDwCsAgAAAA==.Valdun:BAAANQADCgcIEwAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.',
Ve='Velistra:BAAANQADCgEIAQAAAA==.Venous:BAABNQAECn8lAAMHAAoKUBVFSQCfAQAHAAcKMBJFSQCfAQAIAAkKABGiKgBuAQAAAA==.Vestt:BAAANQADCggIFwAAAA==.Vexhalia:BAAANQADCgEIAQAAAA==.',
Vi='Vicariana:BAACNQAFFH8UAAMnAAcKyh/5AwBlAQAnAAUK+x35AwBlAQAbAAQKkgIPJAC6AAA1AAQKf0MABCcACgqDIRUJAK0CACcACgqDIRUJAK0CAB8ABgpnJJAEAH4CABsACQqgFvBQADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQAECgEIAQAAAA==.Viduus:BAABNQAECn8sAAMdAAoK5x/QEQBCAgAdAAoK5x/QEQBCAgAgAAcKnRYZQgC9AQAAAA==.Viv:BAABNQAECn8xAAMCAAoKSRheSgAWAgACAAoKSRheSgAWAgAkAAMKEyCTuwAFAQAAAA==.',
Vo='Vodmor:BAABNQAECn8hAAICAAcKQAQZ9gC+AAACAAcKQAQZ9gC+AAAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.Voran:BAAANQADCgIIAgAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.Waygun:BAAANQADCggICQAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAABNQAECn8pAAIZAAkKzg7ABwApAQAZAAkKzg7ABwApAQAAAA==.',
Wi='Wildheart:BAAANQAECgEIAgAAAA==.Windgoddess:BAAANQADCggICAAAAA==.Wingchún:BAAANQAECgYICgAAAA==.',
Wo='Woregontail:BAAANQAECgQICAAAAA==.Wowbelly:BAAANQAECggIEwAAAA==.',
Wr='Wraythe:BAAANQADCgEIAwAAAA==.',
Xa='Xalrissa:BAAANQADCgUICwAAAA==.Xandeath:BAAANQAECgcIEgAAAA==.Xandem:BAAANQAECgUIBAAAAA==.Xandros:BAABNQAECn8VAAIjAAcKKxBQCwC3AQAjAAcKKxBQCwC3AQAAAA==.Xanlight:BAAANQADCgIIAgAAAA==.',
Xo='Xonk:BAACNQAFFH8KAAIjAAQKCA4+AgDLAAAjAAQKCA4+AgDLAAA1AAQKfzcAAyMACgqyGzwEAJ8CACMACgqyGzwEAJ8CABkAAQqMG2JoAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEwAAAA==.',
Yi='Yiazmat:BAAANQADCgEIAQAAAA==.',
Ys='Ysondrie:BAAANQAECgQIBAAAAA==.',
Za='Zaklu:BAAANQAECgIIBAAAAA==.Zalagrimbor:BAABNQAECn8fAAMQAAkKeBcKRwBaAgAQAAkKeBcKRwBaAgAPAAMKgAWC/wBrAAAAAA==.Zalathar:BAAANQADCgEIAQAAAA==.Zaps:BAABNQAECn8tAAIQAAoKeCDQIgD9AgAQAAoKeCDQIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIhAAYKchlBBgDzAQAhAAYKchlBBgDzAQA1AAQKfyoAAiEACQoAI4cNAAYDACEACQoAI4cNAAYDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDQABNQAECgIIBAAFAAAAAA==.Zelie:BAABNQAECn8oAAMPAAoK3gu9gACKAQAPAAoK3gu9gACKAQAQAAUK4wDHDwFsAAAAAA==.Zenreto:BAABNQAECn8kAAIHAAgKSBejMgATAgAHAAgKSBejMgATAgAAAA==.',
Zh='Zhuri:BAAANQADCggIEwAAAA==.',
Zo='Zoeri:BAAANQAECgQICAAAAA==.Zoltraak:BAAANQADCgYIEQAAAA==.',
['Än']='Änmoa:BAACNQAFFH8UAAIJAAcKrxfiAACIAQAJAAcKrxfiAACIAQA1AAQKf0cAAgkACgpsJbsBAJ0DAAkACgpsJbsBAJ0DAAAA.',
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
