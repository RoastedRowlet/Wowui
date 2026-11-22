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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Druid-Balance','Druid-Restoration','Unknown-Unknown','Rogue-Assassination','Evoker-Devastation','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','Warlock-Demonology','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Monk-Brewmaster','Shaman-Restoration','Mage-Arcane','Mage-Frost','Mage-Fire','Hunter-Marksmanship','Monk-Mistweaver','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abdulr:BAAANQAECggICAAAAA==.Abused:BAAANQADCgUIBwAAAA==.',
Ad='Adelaide:BAACNQAFFH8bAAMBAAYKPBliDgDCAQABAAYKPBliDgDCAQACAAQKWgTlDgCqAAA1AAQKfyoAAwEACgqBIJMZAA8DAAEACgqBIJMZAA8DAAIABArOEWUxAAABAAE1AAUUBwgPAAMARiEA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8sAAMEAAkKyiXOBABoAwAEAAkKyiXOBABoAwAFAAEKmhYajQFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECgkJLAAEAMolAA==.',
Aj='Ajunlucky:BAACNQAFFH8TAAIGAAYK9RCGAAA5AQAGAAYK9RCGAAA5AQA1AAQKfzwAAgYACgqPISQCACwDAAYACgqPISQCACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECgkJLAAEAMolAA==.Alnilam:BAABNQAECn8/AAIHAAoKJxIdEgDlAQAHAAoKJxIdEgDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAABNQAECn8UAAMIAAoKDQf/WwA5AQAIAAcKlQf/WwA5AQAJAAoKaQQLeAAXAQAAAA==.',
Ar='Arbys:BAAANQAECggIDgAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECn84AAIKAAkKdSMVBQA6AwAKAAkKdSMVBQA6AwAAAA==.Armados:BAABNQAECn82AAILAAoKAhUCQgA8AgALAAoKAhUCQgA8AgAAAA==.Aroxw:BAACNQAFFH8RAAILAAYKYw9AEwCVAQALAAYKYw9AEwCVAQA1AAQKfywAAwsACgo/Iec9ANECAAsACgo/Iec9ANECAAwAAQoAABQoAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Athineana:BAAANQAECgQIBAAAAA==.Atlim:BAAANQAECgQIDAAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwAAAA==.',
Ba='Bad:BAAANQAECggICAAAAA==.Balfas:BAAANQADCgQIBAABNQAFFAUIBgANAEMJAA==.Ballidur:BAABNQAECn8UAAMOAAkKug4ZKAC+AQAOAAkKug4ZKAC+AQAPAAIKHgFbgAAiAAABNQAFFAUIBQABAGgHAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Beans:BAAANQADCgUIBQABNQAECgcIEgAQAAAAAA==.Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn9MAAIMAAoKdiOfAQAxAwAMAAoKdiOfAQAxAwAAAA==.Bettyspready:BAABNQAECn8iAAIRAAkKLBSSHgAzAQARAAkKLBSSHgAzAQAAAA==.',
Bi='Bigbluecheez:BAAANQAECgEIAQAAAA==.Bigmanooshki:BAAANQAECgEIAgAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAABNQAECn8lAAISAAoK3wYFFQDlAAASAAoK3wYFFQDlAAAAAA==.',
Bl='Blackfoot:BAABNQAECn8WAAINAAoKJg8qdgC/AQANAAoKJg8qdgC/AQAAAA==.Blankjr:BAAANQAECggIEgAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAcIDwADAEYhAA==.Blightmoss:BAAANQAECgQIBwABNQAECggIFwAFAGcXAA==.Blindpov:BAACNQAFFH8JAAITAAQK1yD4DQDlAAATAAQK1yD4DQDlAAA1AAQKf0YAAxMACgpRJpABAOIDABMACgpRJpABAOIDABQABwq2IJEdALkBAAAA.Bloodpride:BAAANQADCgcIFAAAAA==.',
Bo='Bodyodyodied:BAAANQAECgMIAwAAAA==.Bonquiquie:BAAANQAECgUIBAAAAA==.Boomyboi:BAAANQAECgQIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Borne:BAAANQABCgEIAQAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8oAAITAAoKfR8AFACCAgATAAoKfR8AFACCAgAAAA==.Breakerr:BAAANQAECgMIAgAAAA==.Brewzlee:BAAANQAECggICwAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn8+AAMVAAoKnCAqFAAZAwAVAAoKnCAqFAAZAwAFAAMK5A+MWwFvAAAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgMaABjAgAFAAgKIBgMaABjAgAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xmDBwD7AQAGAAcKlBaDBwD7AQADAAMKIBTLGwHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAIWAAgKSwqdHQBpAQAWAAgKSwqdHQBpAQAAAA==.Carmakazie:BAAANQADCggICAAAAA==.Cattle:BAABNQAECn9AAAIXAAoKehp+DgB8AgAXAAoKehp+DgB8AgAAAA==.Cazul:BAABNQAECn8dAAIYAAgKYw3qbgCNAQAYAAgKYw3qbgCNAQAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chaostorms:BAAANQADCgYIBgAAAA==.Cheetodemon:BAAANQADCgMIAQAAAA==.Chowdk:BAAANQADCggICwAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECggIDwAAAA==.Chowpal:BAAANQAECgYIBwAAAA==.',
Cl='Clawsofpeace:BAABNQAECn8vAAMPAAoKZBeIHgA6AgAPAAgK0haIHgA6AgAXAAgKehUZIQB6AQAAAA==.',
Co='Constanse:BAAANQADCgYICwAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cr='Crewman:BAAANQAECgQIDAAAAA==.Crosshairs:BAAANQADCggIDgABNQAFFAQIBwAUALULAA==.',
Cy='Cylic:BAABNQAECn8fAAIKAAgKiSIsCQDjAgAKAAgKiSIsCQDjAgAAAA==.Cyrùsdh:BAAANQAECgYIBQAAAA==.',
Da='Daddiestouch:BAABNQAECn8rAAMCAAoK8BsbDgB4AgACAAoK8BsbDgB4AgAZAAIKbgcdIwBPAAAAAA==.Dampundies:BAABNQAECn8YAAIaAAkKqRvyFgCVAgAaAAkKqRvyFgCVAgAAAA==.Dangerdream:BAACNQAFFH8HAAMUAAQKtQuFCQDJAAAUAAQKtQuFCQDJAAAbAAEK9gywCAAzAAA1AAQKf0YABBQACgqSIlQKADUDABQACgqSIlQKADUDABsABwrgDuwbAPwAABMAAQoVFeSNAEAAAAAA.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgoKKgAUABEaAA==.Dassani:BAAANQAECgIIAQAAAA==.Datsmywife:BAABNQAECn88AAIcAAoK5xUWDQD+AQAcAAoK5xUWDQD+AQAAAA==.Davis:BAABNQAECn8zAAQdAAoKdBxEJQCqAgAdAAoKgxtEJQCqAgAJAAgKtg2EOQBcAQAIAAMKqBF3hQCaAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.Daysies:BAAANQAECgEIAQAAAA==.',
De='Deadasice:BAAANQAECgYIBgAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn89AAIeAAoKCSHdBwDVAgAeAAoKCSHdBwDVAgAAAA==.Derppriest:BAAANQADCggICAABNQAECgoKPQAeAAkhAA==.Deviiarrc:BAACNQAFFH8bAAMeAAcKNBKGBwD8AQAeAAcKNBKGBwD8AQAfAAEKewHKEAAsAAA1AAQKf0YAAx4ACgpII94EAGADAB4ACgpII94EAGADAB8AAwpHB1oVAIwAAAAA.Devviarc:BAAANQADCggICwABNQAFFAcIGwAeADQSAA==.',
Di='Dibgargargad:BAABNQAECn8jAAIJAAoKbRzhEACVAgAJAAoKbRzhEACVAgAAAA==.',
Dl='Dlamb:BAAANQAECgUIEgABNQAECggIGAACAFoWAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn80AAQMAAoK+CD+CAAVAgAMAAoK7CD+CAAVAgALAAMKBhjbDQHBAAAWAAMKhxBBOQBbAAAAAA==.',
Dr='Dracar:BAABNQAECn89AAIFAAoK6SIdDwCPAwAFAAoK6SIdDwCPAwAAAA==.Draennor:BAAANQAECggIEAAAAA==.Dragoun:BAAANQAECggIEQAAAA==.Draynor:BAAANQAECgEIAQAAAA==.Drmmrfist:BAABNQAECn8bAAIgAAgKURCTFACaAQAgAAgKURCTFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwib:BAABNQAFFH8FAAIWAAUK2xbPAQA0AQAWAAUK2xbPAQA0AQAAAA==.Dwippietiggs:BAABNQAECn9BAAIFAAoKvR6iSAC7AgAFAAoKvR6iSAC7AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAcIIAAVAGUmAA==.Earthfeather:BAAANQAECgUIBgAAAA==.Easymac:BAAANQADCgIJAwABNQAECgoKKAATAH0fAA==.',
Ed='Edhochuli:BAAANQADCgIIAgABNQAFFAUICQAOANIKAA==.',
Ee='Eetee:BAEBNQAECn8mAAMNAAkK/gobZQBXAQANAAkK/gobZQBXAQAhAAMKhxELuACpAAABNQAECgoKQgAEAEwNAA==.',
Eg='Eggon:BAAANQADCgEIAQAAAA==.Eggrolls:BAAANQAECgEIAQABNQAECgQICAAQAAAAAA==.',
Eh='Ehemingway:BAABNQAECn81AAIDAAkKTBfqPQBbAgADAAkKTBfqPQBbAgAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAcIDwADAEYhAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQAECgIIBAAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epicdragon:BAAANQAECgEIAQAAAA==.Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8mAAIRAAoK3xBPOgDqAQARAAoK3xBPOgDqAQAAAA==.Ereye:BAABNQAECn8YAAIKAAcKHhaiHwDSAQAKAAcKHhaiHwDSAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAABNQAECn8iAAIiAAgKignd/wCOAQAiAAgKignd/wCOAQAAAA==.Esturi:BAAANQAECgQIBAAAAA==.',
Et='Etatoned:BAEANQADCgQIBAABNQAECgoKQgAEAEwNAA==.Etengaged:BAEBNQAECn9CAAMEAAoKTA1EHwB0AQAEAAoKTA1EHwB0AQAFAAQK2gZURAGJAAAAAA==.Ethavoc:BAEBNQAECn8YAAIJAAgK0wcacgAtAQAJAAgK0wcacgAtAQABNQAECgoKQgAEAEwNAA==.',
Ev='Evrae:BAABNQAECn8jAAIKAAoKOBZCDwCGAgAKAAoKOBZCDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcICgAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAABNQAECn8lAAIBAAoKCQt0hQCGAQABAAoKCQt0hQCGAQAAAA==.Fatduck:BAAANQADCgQIBAAAAA==.Fatkow:BAABNQAECn8fAAMcAAkKHBzOBgCUAgAcAAkKHBzOBgCUAgAXAAQKOx6uKwA6AQABNQAECgoKQwAdAC4mAA==.',
Fe='Fearthemoo:BAAANQADCgcIBwABNQAECgoKKwACAPAbAA==.Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fellumir:BAAANQAECgIIAgAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH8+AAMiAAkK2iIlCQA1AgAiAAcK5yIlCQA1AgAjAAIKuiIlBQDEAAA1AAQKfyYAAiIACgpgIvJTANgCACIACgpgIvJTANgCAAAA.Finkler:BAABNQAECn8oAAMiAAoK0BzaewCGAgAiAAoKIRraewCGAgAjAAIK3yTNJADIAAABNQAFFAkJPgAiANoiAA==.Firecow:BAAANQAECgQIBgAAAA==.Firedanny:BAAANQAECgUIBgAAAA==.Fistsofpeace:BAAANQAECgYICwABNQAECgoKLwAPAGQXAA==.',
Fl='Flameshock:BAABNQAECn86AAQjAAoKqA+xDwCtAQAiAAoK5Q0ZswAdAgAjAAgKXg+xDwCtAQAkAAMKmw5gBwCxAAAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgoKVgAgAAAbAA==.',
Fr='Frankda:BAAANQADCgIIAgABNQAECgYIBgAQAAAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friarmj:BAAANQADCgUICAAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAcKGwADAKAiAA==.Friendship:BAAANQAECgIIAQAAAA==.Frigidbeach:BAAANQAECgIIAwAAAA==.',
Ga='Galazeth:BAAANQADCggICAABNQAECgoKMgAlAPYgAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH9AAAMSAAoKYiB3AAANAgAfAAkKnxnnAAC3AgASAAcKXyR3AAANAgA1AAQKfyEAAxIACgpxIq8OAHMCABIACgoCH68OAHMCAB8ABAreJOIOAFQBAAAA.Gloreb:BAACNQAFFH8FAAIaAAUKXBeqCABXAQAaAAUKXBeqCABXAQA1AAQKfxUAAhoACAqGHdYcAFICABoACAqGHdYcAFICAAAA.',
Go='Goomi:BAABNQAECn8mAAINAAkKaxB/TwCaAQANAAkKaxB/TwCaAQAAAA==.Gordef:BAABNQAECn8hAAMjAAoKuxV3DADzAQAjAAoKPxV3DADzAQAkAAYKPw+1BABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgQICQAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEwAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Haranor:BAABNQAECn8XAAIcAAkKuhKeDgDgAQAcAAkKuhKeDgDgAQAAAA==.Harrowing:BAABNQAECn9dAAIVAAoKsR4JGQAUAwAVAAoKsR4JGQAUAwAAAA==.Haurt:BAABNQAECn8+AAIOAAoKYQzYLQCVAQAOAAoKYQzYLQCVAQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8oAAIJAAgKFBl+LQCdAQAJAAgKFBl+LQCdAQAAAA==.',
Hi='Hirokii:BAAANQAFFAEIAQABNQAFFAUIBQAWANsWAA==.Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8uAAMVAAoKHhnaMACjAgAVAAoKHhnaMACjAgAFAAkKQB+meQDaAQAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAABNQAECn8gAAMDAAoKtA2eawDrAQADAAoKtA2eawDrAQAlAAQKnQMbWABOAAAAAA==.Hotmess:BAABNQAECn8iAAImAAoKsxk5CwCLAgAmAAoKsxk5CwCLAgAAAA==.',
Hu='Hurg:BAABNQAECn8XAAIhAAkKGwqXZgCCAQAhAAkKGwqXZgCCAQAAAA==.Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAABNQAECn8iAAIhAAoKbCJMCQCFAwAhAAoKbCJMCQCFAwAAAA==.',
Il='Illindi:BAAANQADCgQIBAAAAA==.',
In='Insanê:BAABNQAECn8qAAMIAAoKpBk4LwAqAgAIAAoKpBk4LwAqAgAJAAUKwBHZcACQAAABNQAECgkJMAAaAJ8TAA==.Insañe:BAABNQAECn8wAAMaAAkKnxORHwAzAgAaAAkKnxORHwAzAgAgAAEKkRC6MQAxAAAAAA==.Instinkts:BAAANQABCgIIAgABNQADCgYIBgAQAAAAAA==.Invi:BAAANQAECggIDwAAAA==.',
Ir='Irina:BAAANQABCggICgABNQAECgoKSgAnANIaAA==.Irkellydonu:BAAANQAECgEIAQAAAA==.Ironbeef:BAAANQAECgYIEgAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgAQAAAAAA==.Jadengras:BAABNQAECn8UAAQHAAUKcAfZOADdAAAHAAUKpQbZOADdAAAYAAQKpgXo6QB+AAAnAAEKxQGWMgAiAAAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAABNQAECn8jAAIOAAoKwBvvEgCKAgAOAAoKwBvvEgCKAgAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAABNQAECn8VAAILAAgKrwjSzABbAQALAAgKrwjSzABbAQAAAA==.',
['Jë']='Jësus:BAABNQAECn9HAAMBAAoKVCFWDwBhAwABAAoKVCFWDwBhAwAZAAgKaxMACwCTAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgcIFQAAAA==.Kalel:BAAANQAECgUIDAAAAA==.Karaman:BAAANQADCgIIBAAAAA==.Karmakazie:BAAANQAECgYIDAAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn9CAAIDAAoKXxisPABeAgADAAoKXxisPABeAgAAAA==.Kazraghand:BAABNQAECn9ZAAIGAAoKrxBoBQAOAgAGAAoKrxBoBQAOAgAAAA==.',
Ke='Keetanah:BAAANQAECgUIDAAAAA==.Kei:BAACNQAFFH8HAAIUAAMKSg4WDgDGAAAUAAMKSg4WDgDGAAA1AAQKfycAAxQACgoxGtYXAJ4CABQACgoxGtYXAJ4CABMAAQrpDOiPADsAAAE1AAUUBwgQACUAJA0A.Kelsio:BAABNQAECn86AAIDAAoKQRkjQwBNAgADAAoKQRkjQwBNAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAACNQAFFH8NAAIBAAQKaQe+HwDyAAABAAQKaQe+HwDyAAA1AAQKfzsAAgEACgq8D2ZSACwCAAEACgq8D2ZSACwCAAAA.',
Ki='Kikeo:BAACNQAFFH8QAAMlAAcKJA1fEgDJAAAlAAUKKgxfEgDJAAADAAMKmw6OIACeAAA1AAQKfyEAAyUACQpjG9UbAKABACUACApFGtUbAKABAAMABwocFvu0AJoBAAAA.Kinks:BAABNQAECn8vAAMTAAoKfhCwKQDBAQATAAoKfhCwKQDBAQAbAAMK5QeeJABmAAAAAA==.Kirkoth:BAAANQAECgMIAwAAAA==.',
Kn='Knuah:BAAANQAECgMIAwABNQAECgoKOgACABYYAA==.Knuts:BAABNQAECn8WAAIYAAoKIwMUtwDlAAAYAAoKIwMUtwDlAAAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAACNQAFFH8UAAIRAAgK0xl8AQAMAgARAAgK0xl8AQAMAgA1AAQKfy8AAhEACgoNIOcGAJICABEACgoNIOcGAJICAAAA.Kowtagion:BAABNQAECn9DAAQdAAoKLibcBACoAwAdAAoKLibcBACoAwAIAAgKzB7YFgCVAgAJAAEKeiVQswBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8sAAQlAAoKERznMQC+AQADAAYKWiDzfADBAQAlAAkKmhjnMQC+AQAGAAIKYAHhEQBLAAABNQAFFAQICQAiAPkQAA==.Kronko:BAAANQAECgIIAQAAAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQABNQAECgEIAQAQAAAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAABNQAECn8gAAQdAAgKigitSwDWAAAdAAcKAQitSwDWAAAJAAUKTwiKaACpAAAIAAIKsAI3qwBDAAAAAA==.Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECn8uAAIhAAoKkxxtGwDcAgAhAAoKkxxtGwDcAgAAAA==.',
La='Laziza:BAABNQAECn8dAAINAAoKuAr4UgCPAQANAAoKuAr4UgCPAQAAAA==.',
Le='Leibowitzy:BAABNQAECn9WAAMgAAoKABuRBwDvAQAaAAoKYRQVJQD7AQAgAAgK7huRBwDvAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Lenastin:BAAANQAECgcIDAABNQAFFAEIBwAVAHomAA==.Letra:BAAANQADCgMIAwAAAA==.',
Lh='Lhehitman:BAABNQAECn8oAAIjAAoK5RyoAgA4AwAjAAoK5RyoAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgUIEQAAAA==.Lightshax:BAABNQAECn8eAAIVAAgKtQ/ZcQDCAQAVAAgKtQ/ZcQDCAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8jAAIbAAoKNQ6aEQCXAQAbAAoKNQ6aEQCXAQAAAA==.Liv:BAAANQAECgMICwAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQAECgQIBAAAAA==.',
Lu='Luckydog:BAAANQAECgUICwAAAA==.Ludey:BAABNQAECn9KAAMnAAoK0hogBACiAgAnAAoK0hogBACiAgAYAAEKVRQLOAFGAAAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgQIAwAAAA==.Lutray:BAABNQAECn8gAAIWAAoKOCPuBgDyAgAWAAoKOCPuBgDyAgAAAA==.',
Ly='Lythronax:BAAANQAECgIIAgAAAA==.',
Ma='Makaveleli:BAAANQAECgUIBwAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn9MAAIBAAoKlhYbNgBlAgABAAoKlhYbNgBlAgAAAA==.Marodd:BAABNQAECn8mAAICAAoK0R+lFQCxAgACAAoK0R+lFQCxAgAAAA==.Mashira:BAAANQAECgMIBAAAAA==.Mashîra:BAACNQAFFH8OAAIDAAcKEB7gAwAgAgADAAcKEB7gAwAgAgA1AAQKfzwAAwMACgoOJo8GAKkDAAMACgoOJo8GAKkDACUABgr1HxUjADUCAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgUICQAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn9FAAQhAAoKyR4gHgDzAgAhAAoKyR4gHgDzAgAoAAEKAABqNQA6AAANAAEKAAC0PwEuAAAAAA==.Mekuro:BAAANQAECgQIDgAAAA==.Melky:BAABNQAECn8YAAMaAAkKag5uIwCAAQAaAAgKvAxuIwCAAQAgAAQKGBEuGQCnAAAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgUIBAAAAA==.Mewfasa:BAAANQADCggICAAAAA==.Meyday:BAAANQAECgcIEQAAAA==.',
Mi='Mia:BAABNQAECn8cAAIUAAoKgyDXEQDdAgAUAAoKgyDXEQDdAgAAAA==.Migraine:BAAANQADCggIDAAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyA6TACwAgAFAAgKOyA6TACwAgAAAA==.Minasuzune:BAABNQAECn8aAAMDAAoKHSKnaABCAgADAAoKHSKnaABCAgAlAAIK9AzTdQBkAAAAAA==.Minus:BAABNQAECn8VAAIiAAgKZxTgZwDkAQAiAAgKZxTgZwDkAQABNQAECgkJGAAaAGoOAA==.',
Mo='Mojojojo:BAAANQAECgcIBwABNQAFFAQICQAiAPkQAA==.Moller:BAAANQAECgYICQAAAA==.Monkchow:BAAANQADCgEIAQAAAA==.Monkintrunk:BAAANQADCggICAABNQAECgYIBgAQAAAAAA==.Moondotter:BAAANQAECgUIBAAAAA==.Moongoddess:BAAANQAECgQICAABNQAECgUIBAAQAAAAAA==.Moonslayer:BAABNQAECn8jAAIOAAoKuhBtNQBkAQAOAAoKuhBtNQBkAQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.Myley:BAAANQAECggIEgABNQAECgkJGAAaAGoOAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAcIDgADABAeAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAcIDgADABAeAA==.Måshîrå:BAAANQAECgYICQABNQAFFAcIDgADABAeAA==.',
['Mê']='Mêl:BAAANQADCgQIBAAAAA==.',
Na='Nakor:BAABNQAECn8gAAIiAAcKYgT8MQE5AQAiAAcKYgT8MQE5AQAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECn8oAAMMAAgKVBBwDwC1AQAMAAcKLBJwDwC1AQALAAcKtAYPrgAeAQAAAA==.Natalie:BAAANQAECggIAQAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAABNQAECn8cAAMLAAkKNBCLggCBAQALAAkKNBCLggCBAQAWAAIKaAr8NgBjAAAAAA==.Nefeli:BAABNQAECn8xAAIfAAoKYxVxBQCOAgAfAAoKYxVxBQCOAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAABNQAECn8aAAIfAAoKHwIcFQCPAAAfAAoKHwIcFQCPAAAAAA==.Nestia:BAABNQAECn8bAAITAAkKIg4ONQB4AQATAAkKIg4ONQB4AQAAAA==.Never:BAACNQAFFH8JAAMHAAMKDBgMDQCdAAAHAAIKIBUMDQCdAAAYAAIKexiiLgCcAAA1AAQKfzkAAxgACgrNIvUiAIYCABgACgpvIvUiAIYCAAcABQpHHjgdAIQBAAAA.',
Ni='Nightshade:BAABNQAECn87AAIDAAoKvR3VLwDdAgADAAoKvR3VLwDdAgAAAA==.Nimbus:BAAANQAECgcIDgAAAA==.',
No='No:BAAANQAECgYIBgAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8sAAIEAAoKbBadFwC9AQAEAAoKbBadFwC9AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAABNQAECn8WAAIRAAgKsAWYUwBuAQARAAgKsAWYUwBuAQAAAA==.',
On='Oniana:BAABNQAECn9GAAIlAAoKCw5HFwDXAQAlAAoKCw5HFwDXAQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAFFAUICQAOANIKAA==.',
Ow='Owwmyballs:BAABNQAECn8dAAQdAAoKYwg5LgB4AQAdAAoKYwg5LgB4AQAIAAIKcQb5uAAvAAAJAAEK2QGGtQAZAAAAAA==.',
Oz='Ozygo:BAAANQAECgYIBgAAAA==.',
Pa='Pagamas:BAACNQAFFH8PAAMiAAcKoRPMGQCrAQAiAAYKGxLMGQCrAQAjAAEKvBl8DgBWAAA1AAQKfygAAyIACgr1HrxXANACACIACgr1HrxXANACACMAAgqLEa03AF4AAAAA.Palandari:BAAANQAECgUICAAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Pandormu:BAAANQAECgUICQABNQAECgoKMAAnAKIYAA==.Panter:BAABNQAECn8wAAInAAoKohisBQBiAgAnAAoKohisBQBiAgAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAABNQAECn8YAAIcAAgKaQ17JADdAAAcAAgKaQ17JADdAAAAAA==.',
Ph='Phodoe:BAABNQAECn8oAAIPAAoK9QwfNAB6AQAPAAoK9QwfNAB6AQAAAA==.Phöebe:BAAANQAECgMIAQAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMICAAQAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAABNQAECn8XAAIiAAgKnRN2sABEAQAiAAgKnRN2sABEAQAAAA==.',
Po='Pokeureyeout:BAABNQAECn8qAAIDAAkK/wymigCiAQADAAkK/wymigCiAQAAAA==.Pole:BAAANQADCgUIBQABNQAECgoKNgAUAMgaAA==.Port:BAAANQAECgUIBgAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECgoKLwAPAGQXAA==.Prodyne:BAABNQAECn86AAIiAAoKLhW/eQCKAgAiAAoKLhW/eQCKAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgoKKwACAPAbAA==.',
Qa='Qariwarmi:BAAANQAECgIIAgAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAFFAQICAABAG0dAA==.Quiettreader:BAABNQAECn9WAAIjAAoKEBk7BQDDAgAjAAoKEBk7BQDDAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAABNQAECn8XAAIIAAoKWBMoMgDeAQAIAAoKWBMoMgDeAQAAAA==.Rafiki:BAAANQAECgMIAwAAAA==.Raidboss:BAABNQAECn8WAAILAAoKTx3acQA+AgALAAoKTx3acQA+AgAAAA==.',
Re='Redeath:BAAANQAECgQIBgABNQAECgUICAAQAAAAAA==.Redirect:BAAANQAECgUICAAAAA==.Redonculous:BAABNQAECn86AAICAAoKFhiCHgBLAgACAAoKFhiCHgBLAgAAAA==.Redpool:BAACNQAFFH8IAAIhAAQKPwZhGADtAAAhAAQKPwZhGADtAAA1AAQKf0EAAiEACgq/FLtBAA0CACEACgq/FLtBAA0CAAAA.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8nAAIUAAcK7CBmGACZAgAUAAcK7CBmGACZAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgkJOAAKAHUjAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.Riggymortis:BAAANQAECgIIAgAAAA==.',
Ro='Ronx:BAABNQAECn8dAAIjAAcK8BnNEgB7AQAjAAcK8BnNEgB7AQAAAA==.Roxxiloxxi:BAABNQAECn8sAAMHAAoKTwa5GACmAQAHAAkKfga5GACmAQAYAAUKoQPN5QCGAAAAAA==.',
Ru='Rudeboy:BAABNQAECn8sAAIYAAoKXhkJVQBXAgAYAAoKXhkJVQBXAgAAAA==.Rumchata:BAAANQAECgEIAQABNQAFFAUICQAOANIKAA==.Rushu:BAACNQAFFH8JAAIiAAQK+RBSKgDOAAAiAAQK+RBSKgDOAAA1AAQKfz0AAiIACgqdH8UZAN4CACIACgqdH8UZAN4CAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn87AAMVAAoKUxmaQABiAgAVAAoKUxmaQABiAgAFAAcKYQrx3wBbAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgcIEwAQAAAAAA==.Sahria:BAAANQAECgUICQAAAA==.Samlosco:BAABNQAECn8VAAISAAoKywQ7FADzAAASAAoKywQ7FADzAAAAAA==.Sapphpal:BAAANQAECgYICAABNQAECgcIDgAQAAAAAA==.Sarhia:BAAANQAECgMIAwAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgAQAAAAAA==.',
Sc='Schizadin:BAABNQAECn82AAMEAAkKWyaZAACKAwAEAAkKWyaZAACKAwAFAAMKHgfbbQFxAAAAAA==.Schizology:BAAANQAECggIDgABNQAECgkJNgAEAFsmAA==.Schnoze:BAAANQAECgUIDgAAAA==.',
Se='Seabane:BAAANQAECggIEwAAAA==.Sebekuul:BAAANQADCgYIBgAAAQ==.Selwenna:BAAANQADCgMIAwABNQAECggIDwAQAAAAAA==.Selys:BAACNQAFFH8LAAIiAAUKVQovLgAfAQAiAAUKVQovLgAfAQA1AAQKf10AAyIACgrYHN4mAKMCACIACgrYHN4mAKMCACMAAgr1BoY5AFgAAAAA.Sepheturix:BAAANQAECgUICQAAAA==.Sephurik:BAACNQAFFH83AAMiAAoKuh6cAwCKAgAiAAoKwhucAwCKAgAjAAEKGRigDgBWAAA1AAQKf0sAAyIACgpsJFkrADkDACIACgqxIlkrADkDACMAAgpEH5gpAKoAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCggIDQAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawman:BAAANQADCggICAAAAA==.Shawnalenee:BAABNQAECn8YAAICAAgKWhZPIgB0AQACAAgKWhZPIgB0AQAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiftingmoon:BAAANQAECgQIBAAAAA==.Shiriax:BAAANQAECgIIBAAAAA==.Shiv:BAAANQAECggIAgAAAA==.Shyft:BAAANQAECggIDwAAAA==.',
Si='Sidisi:BAAANQAECggIDgABNQAECgoKMgAlAPYgAA==.Sikanda:BAABNQAECn8bAAMdAAoKNxtnIwC2AgAdAAoKNxtnIwC2AgAIAAIKuhRVjACEAAABNQAECgoKMgAlAPYgAA==.Silvea:BAABNQAECn8pAAINAAoK5BGxRgC6AQANAAoK5BGxRgC6AQAAAA==.Silvett:BAAANQAECgQIBQABNQAECgoKIgAmALMZAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn82AAICAAoKTSEzDQAYAwACAAoKTSEzDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skilersham:BAAANQADCgEIAgAAAA==.Skillertank:BAABNQAECn8sAAIJAAoKAxCiKAC6AQAJAAoKAxCiKAC6AQAAAA==.Sky:BAACNQAFFH8FAAIiAAMKfxeVQACxAAAiAAMKfxeVQACxAAA1AAQKfzIAAiIACgr4JOEVAHsDACIACgr4JOEVAHsDAAAA.Skyelf:BAABNQAECn81AAIDAAoKfw0FcQDeAQADAAoKfw0FcQDeAQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECn81AAMhAAoKQxnOIADmAgAhAAoKQxnOIADmAgANAAEKxANJCAEsAAAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAkJKQAoAHAcAA==.Solunara:BAAANQADCgUIBQABNQAECggIFwAFAGcXAA==.',
Sp='Spectrecles:BAACNQAFFH8JAAIOAAUK0greDwABAQAOAAUK0greDwABAQA1AAQKfzsAAw4ACgq8GCEdABoCAA4ACgq8GCEdABoCAA8AAQo8BqSDAB0AAAAA.Spectrecless:BAAANQAECgMIAwABNQAFFAUICQAOANIKAA==.Speez:BAABNQAECn8jAAIDAAgKFBPfegAZAgADAAgKFBPfegAZAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.Spèctral:BAAANQAECgQIBwABNQAECgoKIgAmALMZAA==.',
St='Stablehand:BAABNQAECn8hAAIDAAkKoxXBhACwAQADAAkKoxXBhACwAQAAAA==.Steve:BAACNQAFFH8xAAMoAAoKExeIAAAaAgAoAAgKkRWIAAAaAgANAAcKmxY7BgCaAQA1AAQKf0IABA0ACgqGIxwUAFEDAA0ACgpsIxwUAFEDACgABgpaIG0WAK8BACEAAgpiAgUkASkAAAAA.Stonedfel:BAABNQAECn8wAAITAAoKnhIUOQDqAQATAAoKnhIUOQDqAQAAAA==.Stonkbonkk:BAAANQAECgcICAAAAA==.',
Su='Sugarftx:BAAANQAECgYIBgAAAA==.Sunhoof:BAABNQAECn8XAAQFAAgKZxeIhAAeAgAFAAgKZxeIhAAeAgAEAAIKfRMUWgB0AAAVAAIKHAW2EQFTAAAAAA==.Supahotvile:BAACNQAFFH8GAAMKAAMKaQayHgCKAAAKAAIKAQeyHgCKAAARAAIKYgS1DwBbAAA1AAQKfyYAAxEACgrWFRMsADgCABEACgpFDxMsADgCAAoABQqUGARqAGwBAAAA.',
Sw='Sweetiefox:BAAANQAECgIIAgAAAA==.',
Sy='Syx:BAAANQAECgUICgAAAA==.',
['Sø']='Sørrow:BAABNQAECn8iAAIUAAoK5w3qNQCUAQAUAAoK5w3qNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8lAAMjAAoKgAfUFwA8AQAjAAoKVAfUFwA8AQAiAAYK9QG3ewHKAAAAAA==.Tabu:BAAANQAECgUIBwAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggIDQAAAA==.Tankoromma:BAAANQAECgYICwAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgUICwAQAAAAAA==.',
Te='Test:BAAANQAECggJAQAAAA==.',
Th='Tharil:BAAANQAECgQIBAAAAA==.Theblakmamba:BAAANQADCgIIBQAAAA==.Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAABNQAECn81AAMRAAoKkiOnBACLAwARAAoKkiOnBACLAwAKAAkKDRyBLgBEAgAAAA==.Thunderous:BAAANQADCgMIAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8PAAIDAAcKRiG/BwDSAQADAAcKRiG/BwDSAQA1AAQKfz8AAwMACgo7Jr8CAH8DAAMACgo7Jr8CAH8DACUAAQpAGVOBAEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgoKNgACAE0hAA==.',
To='Tomahawkchow:BAAANQAECggIEgAAAA==.Totemofpeace:BAAANQADCggIEAABNQAECgoKLwAPAGQXAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Treehorse:BAAANQAECgQICAAAAA==.Trentlock:BAACNQAFFH8WAAQYAAcK8ANPHwC3AAAYAAUKwgNPHwC3AAAnAAEKAABrEgA+AAAHAAIKNQQRFgA9AAA1AAQKf0EABBgACgoBH41SAF4CABgACgpfGY1SAF4CAAcABAoyIV0hAGYBACcAAwruGyMdAI8AAAAA.Tristae:BAAANQAECgYICwAAAA==.',
Ts='Tsu:BAABNQAECn8hAAMKAAkKrSOKNwAdAgAKAAgK1SOKNwAdAgARAAcK3xsFMQAdAgAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgIIAgAAAA==.Unstablesha:BAAANQAECgYIDwAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8UAAQdAAYKAhK9BAAsAQAdAAUKAhK9BAAsAQAIAAEKvAFkIgArAAAJAAEKAADUNgAlAAA1AAQKfzIAAh0ACgo0IrQVAAwDAB0ACgo0IrQVAAwDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQAECgIIAQAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vil:BAACNQAFFH9IAAICAAoKtiUkAACAAwACAAoKtiUkAACAAwA1AAQKfysAAgIACgrJJkcCAL0DAAIACgrJJkcCAL0DAAAA.Vilonus:BAABNQAECn8pAAIYAAoK0Q63bwCLAQAYAAoK0Q63bwCLAQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgoKNgACAE0hAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Volairis:BAAANQAECgYICAABNQAFFAYICgAcAKEQAA==.Voy:BAABNQAECn8eAAIGAAgKtwgZCQCvAQAGAAgKtwgZCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICAAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wa='Wagyu:BAAANQAECgEIAQAAAA==.Wallaroo:BAAANQADCgUIAgAAAA==.',
We='Weezy:BAABNQAECn8oAAMBAAoKKw9GWADcAQABAAkKlw9GWADcAQACAAkKJAkwOABkAQAAAA==.',
Wi='Williie:BAAANQAECggICwAAAA==.Withengar:BAAANQAECgcIBQAAAA==.',
Wu='Wuoshi:BAAANQAECgUICwAAAA==.Wuuzzyy:BAABNQAECn8oAAIOAAoKzRIlNwA0AgAOAAoKzRIlNwA0AgAAAA==.',
Xa='Xaliko:BAABNQAECn8YAAIYAAoKAhYVawCXAQAYAAoKAhYVawCXAQAAAA==.Xanbaran:BAABNQAECn86AAIBAAoKTQpRbgDTAQABAAoKTQpRbgDTAQAAAA==.Xandian:BAAANQAECgQIBAAAAA==.',
Xi='Xiphus:BAAANQAECgIIAwAAAA==.',
Xm='Xmarks:BAAANQAECggIEQAAAA==.',
Xy='Xyre:BAAANQABCgIIAgAAAA==.Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFH8SAAIhAAUKnCCaBwDeAQAhAAUKnCCaBwDeAQA1AAQKf00AAyEACgrFIiAQAEMDACEACgrFIiAQAEMDAA0AAQoAAO4iAUsAAAAA.',
Ya='Yahenni:BAABNQAECn8yAAMlAAoK9iBNFQC0AgAlAAkK8R1NFQC0AgADAAkKUBh1YwBOAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAABNQAECn8gAAIBAAkKYxH5SQAQAgABAAkKYxH5SQAQAgAAAA==.Yukki:BAABNQAECn8cAAMhAAkKaRItOwAqAgAhAAkKaRItOwAqAgANAAEK5gD9ZgEJAAAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAABNQAECn8qAAIUAAoKERp8EABRAgAUAAoKERp8EABRAgAAAA==.',
Ze='Zerk:BAABNQAECn8XAAILAAkKYQJ+AwHWAAALAAkKYQJ+AwHWAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
['Ða']='Ðavîs:BAAANQAECgEIAQABNQAECgoKMwAdAHQcAA==.',
['ßl']='ßlundetto:BAAANQAECgQICwAAAA==.',
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
