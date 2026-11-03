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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Shaman-Elemental','Rogue-Assassination','Evoker-Devastation','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','Druid-Restoration','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','Monk-Brewmaster','Druid-Balance','Mage-Arcane','Mage-Frost','Mage-Fire','Hunter-Marksmanship','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Shaman-Enhancement',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abdulr:BAAANQAECggICAAAAA==.Abused:BAAANQADCgUIBwAAAA==.',
Ad='Adelaide:BAACNQAFFH8bAAMBAAYKPBn0CADdAQABAAYKPBn0CADdAQACAAQKWgR6CwCvAAA1AAQKfyoAAwEACgqBIJMZAA8DAAEACgqBIJMZAA8DAAIABArOEeMoAAABAAE1AAUUBggNAAMAUSAA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8sAAMEAAkKyiXOBABoAwAEAAkKyiXOBABoAwAFAAEKmhYajQFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECgkJLAAEAMolAA==.',
Aj='Ajunlucky:BAACNQAFFH8SAAIGAAUKjxWrAAD5AAAGAAUKjxWrAAD5AAA1AAQKfzoAAgYACgqPISQCACwDAAYACgqPISQCACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECgkJLAAEAMolAA==.Alexari:BAAANQAECgEIAQAAAA==.Alnilam:BAABNQAECn87AAIHAAoKIBEdEgDlAQAHAAoKIBEdEgDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAABNQAECn8UAAMIAAoKDQf/WwA5AQAIAAcKlQf/WwA5AQAJAAoKaQQLeAAXAQAAAA==.',
Ar='Arbys:BAAANQAECggIDgAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQADCgEIAQAAAA==.Arkveld:BAABNQAECn84AAIKAAkKdSMVBQA6AwAKAAkKdSMVBQA6AwAAAA==.Armados:BAABNQAECn8wAAILAAoKlRKyRgD8AQALAAoKlRKyRgD8AQAAAA==.Aroxw:BAACNQAFFH8RAAILAAYKYw9AEwCVAQALAAYKYw9AEwCVAQA1AAQKfysAAwsACgrFIBYyAE8CAAsACgrFIBYyAE8CAAwAAQoAABQoAG0AAAAA.Arthritis:BAAANQADCgEIAQAAAA==.',
At='Athaal:BAAANQADCgEIAwAAAA==.Athineana:BAAANQAECgQIBAAAAA==.Atlim:BAAANQAECgMICQAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQAECgEIAQANAAAAAA==.',
Ba='Bad:BAAANQAECggICQAAAA==.Balfas:BAAANQADCgQIBAABNQAFFAUIBgAOAEMJAA==.Ballidur:BAAANQAFFAEIAQABNQAFFAQIBAANAAAAAA==.Ballsmasher:BAAANQADCggIEgAAAA==.Balruun:BAAANQADCgEIAQAAAA==.',
Be='Bearias:BAAANQADCgUIBgAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn8+AAIMAAoKryJaAgDmAgAMAAoKryJaAgDmAgAAAA==.Bettyspready:BAABNQAECn8iAAIPAAkKLBSwGgA6AQAPAAkKLBSwGgA6AQAAAA==.',
Bi='Bigmanooshki:BAAANQAECgEIBQAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQADCgEIAgAAAA==.Binnyi:BAABNQAECn8hAAIQAAoKfgWxHwBbAQAQAAoKfgWxHwBbAQAAAA==.',
Bl='Blackfoot:BAABNQAECn8WAAIOAAoKJg8qdgC/AQAOAAoKJg8qdgC/AQAAAA==.Blankjr:BAAANQAECgcIDAAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAYIDQADAFEgAA==.Blightmoss:BAAANQAECgQIBwABNQAECggIFwAFAGcXAA==.Blindpov:BAACNQAFFH8JAAIRAAQK1yDbCQDzAAARAAQK1yDbCQDzAAA1AAQKf0YAAxEACgpRJpABAOIDABEACgpRJpABAOIDABIABwq2ID8XAMoBAAAA.Bloodpride:BAAANQADCgcICQAAAA==.',
Bo='Bodyodyodied:BAAANQAECgMIAwAAAA==.Bonquiquie:BAAANQAECgUIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Borne:BAAANQAECgEIAQAAAA==.Bouberry:BAAANQAECgEIAgAAAA==.Bounce:BAAANQADCgYIDQAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8oAAIRAAoKfR9LDwCOAgARAAoKfR9LDwCOAgAAAA==.Breakerr:BAAANQAECgMIBAAAAA==.Brewzlee:BAAANQAECgIIAwAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn86AAMTAAoKwx/6DwAXAwATAAoKwx/6DwAXAwAFAAMK5A9SMAFwAAAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgMaABjAgAFAAgKIBgMaABjAgAAAA==.Burnnotice:BAAANQADCgEIAQABNQAECgMICAANAAAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xmDBwD7AQAGAAcKlBaDBwD7AQADAAMKIBTLGwHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAIUAAgKSwqdHQBpAQAUAAgKSwqdHQBpAQAAAA==.Carmakazie:BAAANQADCggICAAAAA==.Cattle:BAABNQAECn84AAIVAAoKehp+DgB8AgAVAAoKehp+DgB8AgAAAA==.Cazul:BAAANQAECgcIEAAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICwAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECggIEQAAAA==.Chowpal:BAAANQAECgYICAAAAA==.',
Cl='Clawsofpeace:BAABNQAECn8rAAMWAAoKZBeIHgA6AgAWAAgK0haIHgA6AgAVAAgKIxVOGgB6AQAAAA==.',
Co='Constanse:BAAANQADCgYIDAAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cr='Crewman:BAAANQAECgQIBwAAAA==.Crosshairs:BAAANQADCggIDgABNQAECgoKRQASAJIiAA==.',
Cy='Cylic:BAABNQAECn8fAAIKAAgKiSIsCQDjAgAKAAgKiSIsCQDjAgAAAA==.Cyrùsdh:BAAANQAECgYIBgAAAA==.',
Da='Daddiestouch:BAABNQAECn8gAAMCAAkKixuaEgD5AQACAAkKixuaEgD5AQAXAAIKbgcdIwBPAAAAAA==.Dampundies:BAABNQAECn8YAAIYAAkKqRvyFgCVAgAYAAkKqRvyFgCVAgAAAA==.Dangerdream:BAABNQAECn9FAAQSAAoKkiJUCgA1AwASAAoKkiJUCgA1AwAZAAcK4A5GFwC0AAARAAEKFRXkjQBAAAAAAA==.Dankheals:BAAANQADCgYICAAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgoKJwASACMZAA==.Dassani:BAAANQAECgIIAQAAAA==.Datsmywife:BAABNQAECn88AAIaAAoK5xUoCQALAgAaAAoK5xUoCQALAgAAAA==.Davis:BAABNQAECn8zAAQbAAoKdBwoFQAbAgAbAAoKgxsoFQAbAgAJAAgKtg2XLwBmAQAIAAMKqBF3hQCaAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.Daysies:BAAANQAECgEIAQAAAA==.',
De='Deadasice:BAAANQAECggICAAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn89AAIcAAoKCSEGBgDcAgAcAAoKCSEGBgDcAgAAAA==.Derppriest:BAAANQADCggICAABNQAECgoKPQAcAAkhAA==.Deviiarrc:BAACNQAFFH8aAAMcAAYKVxNwBgCvAQAcAAYKVxNwBgCvAQAdAAEKewExDQAuAAA1AAQKf0EAAhwACgpII94EAGADABwACgpII94EAGADAAAA.Devviarc:BAAANQADCggIDAABNQAFFAYIGgAcAFcTAA==.',
Di='Dibgargargad:BAABNQAECn8gAAIJAAoKcRoqEgBjAgAJAAoKcRoqEgBjAgAAAA==.',
Dl='Dlamb:BAABNQAECn8YAAIeAAcKOR/3fACVAQAeAAcKOR/3fACVAQAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn8wAAQMAAoKziDaBgAVAgAMAAoKwiDaBgAVAgALAAMKBhjbDQHBAAAUAAMKhxBULwBgAAAAAA==.',
Dr='Dracar:BAABNQAECn85AAIFAAoK6SIdDwCPAwAFAAoK6SIdDwCPAwAAAA==.Draennor:BAAANQAECgcICQAAAA==.Dragoun:BAAANQAECggIDQAAAA==.Draynor:BAAANQAECgEIAwAAAA==.Drmmrfist:BAABNQAECn8bAAIfAAgKURCTFACaAQAfAAgKURCTFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwib:BAAANQAECgEIAQABNQAECggIEAANAAAAAA==.Dwippietiggs:BAABNQAECn89AAIFAAoKvR6iSAC7AgAFAAoKvR6iSAC7AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAECggICgANAAAAAA==.Earthfeather:BAAANQAECgUICQAAAA==.Easymac:BAAANQADCgIJAwABNQAECgoKKAARAH0fAA==.',
Ed='Edhochuli:BAAANQADCgIIAgABNQAFFAMIBwAgAEkNAA==.',
Ee='Eetee:BAEBNQAECn8hAAMOAAkK/gpvUwBTAQAOAAkK/gpvUwBTAQAeAAMKhxFboQCvAAABNQAECgoKMAAEAB0NAA==.',
Eg='Eggon:BAAANQADCgEIAQAAAA==.Eggrolls:BAAANQAECgEIAQABNQAECgQICAANAAAAAA==.',
Eh='Ehemingway:BAABNQAECn8oAAIDAAkK3RQrPAAqAgADAAkK3RQrPAAqAgAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Eliantheria:BAAANQADCgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAYIDQADAFEgAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQAECgEIAgAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epicdragon:BAAANQADCgYICgAAAA==.Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8iAAIPAAoKHhBPOgDqAQAPAAoKHhBPOgDqAQAAAA==.Ereye:BAABNQAECn8YAAIKAAcKHhaiHwDSAQAKAAcKHhaiHwDSAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAABNQAECn8iAAIhAAgKignd/wCOAQAhAAgKignd/wCOAQAAAA==.Esturi:BAAANQAECgQIBQAAAA==.',
Et='Etatoned:BAEANQADCgQIBAABNQAECgoKMAAEAB0NAA==.Etengaged:BAEBNQAECn8wAAMEAAoKHQ3vGQBtAQAEAAoKHQ3vGQBtAQAFAAEKywRucQExAAAAAA==.Ethavoc:BAEBNQAECn8YAAIJAAgK0wcacgAtAQAJAAgK0wcacgAtAQABNQAECgoKMAAEAB0NAA==.',
Ev='Evrae:BAABNQAECn8jAAIKAAoKOBZCDwCGAgAKAAoKOBZCDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcICwAAAA==.',
Ey='Eyeofjazz:BAAANQADCgEIAgAAAA==.',
Fa='Faithshand:BAABNQAECn8hAAIBAAoKCQt0hQCGAQABAAoKCQt0hQCGAQAAAA==.Fatduck:BAAANQADCgQIBAAAAA==.Fatkow:BAABNQAECn8UAAMaAAgKlheVDwB/AQAaAAgKZBKVDwB/AQAVAAQKOx6uKwA6AQABNQAECgoKNwAbAC4mAA==.',
Fe='Fearthemoo:BAAANQADCgcIBwABNQAECgkJIAACAIsbAA==.Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fellumir:BAAANQAECgIIAgAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH80AAMhAAkK6yAeBgDXAQAhAAcKMSAeBgDXAQAiAAIKuiI4AwDQAAA1AAQKfyYAAiEACgpgIvJTANgCACEACgpgIvJTANgCAAAA.Finkler:BAABNQAECn8nAAMhAAkKnB7aewCGAgAhAAkKixvaewCGAgAiAAIK3yTNJADIAAABNQAFFAkJNAAhAOsgAA==.Firecow:BAAANQAECgIIAgAAAA==.Firedanny:BAAANQAECgUIBgAAAA==.Fistsofpeace:BAAANQAECgYIDAABNQAECgoKKwAWAGQXAA==.',
Fl='Flameshock:BAABNQAECn8yAAMiAAoKmA+xDwCtAQAhAAoKpQ0ZswAdAgAiAAgKXg+xDwCtAQAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgoKRwAfAKUYAA==.',
Fr='Frankda:BAAANQADCgIIAgABNQAECggICAANAAAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friarmj:BAAANQADCgUICAAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAcKGwADAKAiAA==.Friendship:BAAANQADCgEIAgAAAA==.Frigidbeach:BAAANQAECgIIBAAAAA==.Frivolous:BAAANQAECgEIAQAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH8uAAMQAAoKBx6IAAC0AQAdAAkKaxj/AABsAgAQAAYKHiWIAAC0AQA1AAQKfyEAAxAACgpxIq8OAHMCABAACgoCH68OAHMCAB0ABAreJOIOAFQBAAAA.Gloreb:BAACNQAFFH8FAAIYAAUKXBeqCABXAQAYAAUKXBeqCABXAQA1AAQKfxUAAhgACAqGHfAUAOQBABgACAqGHfAUAOQBAAAA.',
Go='Goomi:BAABNQAECn8fAAIOAAgKlw43WgA8AQAOAAgKlw43WgA8AQAAAA==.Gordef:BAABNQAECn8hAAMiAAoKuxV3DADzAQAiAAoKPxV3DADzAQAjAAYKPw+1BABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgUIBgAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEwAAAA==.',
Ha='Haakon:BAAANQADCgUIBgAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Haranor:BAAANQAECggIDgAAAA==.Harrowing:BAABNQAECn9VAAITAAoKsR4JGQAUAwATAAoKsR4JGQAUAwAAAA==.Haurt:BAABNQAECn8yAAIgAAoK3QpaKgB0AQAgAAoK3QpaKgB0AQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8hAAIJAAgKFBlFKwCBAQAJAAgKFBlFKwCBAQAAAA==.',
Hi='Hirokii:BAAANQAECgMIDQABNQAECggIEAANAAAAAA==.Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8pAAMTAAoKHhnaMACjAgATAAoKHhnaMACjAgAFAAkKQB9aWQDrAQAAAA==.Holymilkman:BAAANQADCgEIAQAAAA==.Hotdogramen:BAABNQAECn8bAAMDAAoKhQypVwDYAQADAAoKhQypVwDYAQAkAAMKmwGPVgA5AAAAAA==.Hotmess:BAABNQAECn8dAAIlAAkK3RgVDAAvAgAlAAkK3RgVDAAvAgAAAA==.',
Hu='Hurg:BAAANQAECgcIDgAAAA==.Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAABNQAECn8eAAIeAAoKbCIpBgCcAwAeAAoKbCIpBgCcAwAAAA==.',
Il='Illindi:BAAANQADCgQIBAAAAA==.Illona:BAAANQADCgEIAQAAAA==.',
In='Insanê:BAABNQAECn8iAAMIAAoK3Rg4LwAqAgAIAAoK3Rg4LwAqAgAJAAUKwBFHYwCWAAABNQAECgkJMAAYAJ8TAA==.Insañe:BAABNQAECn8wAAMYAAkKnxORHwAzAgAYAAkKnxORHwAzAgAfAAEKkRC6MQAxAAAAAA==.Instinkts:BAAANQABCgIIAgABNQADCgYIBgANAAAAAA==.Invi:BAAANQAECgcIDgAAAA==.',
Ir='Irina:BAAANQAECgIIAgABNQAECgoKRAAmANIaAA==.Irjazzagain:BAAANQADCgEIAQAAAA==.Irkellydonu:BAAANQAECgEIAQAAAA==.Ironbeef:BAAANQAECgYIEgAAAA==.',
It='Itsjazz:BAAANQADCgEIAQAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgANAAAAAA==.Jadengras:BAAANQAECgUIDwAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAABNQAECn8dAAIgAAoK+BdyFwAkAgAgAAoK+BdyFwAkAgAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAABNQAECn8VAAILAAgKrwjSzABbAQALAAgKrwjSzABbAQAAAA==.',
['Jë']='Jësus:BAABNQAECn85AAMBAAoKEBqOLABfAgABAAoKcxmOLABfAgAXAAgKaxMACwCTAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFgAAAA==.Kaldren:BAAANQADCgcIFgAAAA==.Kalel:BAAANQAECgUIDAAAAA==.Karaman:BAAANQADCgIIAwAAAA==.Karmakazie:BAAANQAECgYIDAAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn8zAAIDAAkKhRjySAACAgADAAkKhRjySAACAgAAAA==.Kazraghand:BAABNQAECn9NAAIGAAoKrxBjBAAIAgAGAAoKrxBjBAAIAgAAAA==.',
Ke='Keetanah:BAAANQAECgUIDgAAAA==.Kei:BAACNQAFFH8HAAISAAMKSg4WDgDGAAASAAMKSg4WDgDGAAA1AAQKfyYAAxIACgodGdYXAJ4CABIACgodGdYXAJ4CABEAAQrpDOiPADsAAAE1AAUUBggNAAMAcQsA.Kelsio:BAABNQAECn82AAIDAAoKJBngMgBKAgADAAoKJBngMgBKAgAAAA==.Kess:BAAANQADCgYICQAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAACNQAFFH8MAAIBAAQKaQfVFwADAQABAAQKaQfVFwADAQA1AAQKfzcAAgEACgq8D2ZSACwCAAEACgq8D2ZSACwCAAAA.',
Ki='Kikeo:BAACNQAFFH8NAAMDAAYKcQvuGQCiAAADAAMKmw7uGQCiAAAkAAQKSAgZEwB7AAA1AAQKfxoAAyQACQrKGhEYAI4BAAMABwocFvu0AJoBACQACAqXGREYAI4BAAAA.Kinks:BAABNQAECn8lAAIRAAoK2g/VJACnAQARAAoK2g/VJACnAQAAAA==.Kirkoth:BAAANQAECgMIAwAAAA==.',
Kn='Knuah:BAAANQAECgMIAwABNQAECgoKNQACALcXAA==.Knuts:BAABNQAECn8WAAInAAoKIwOJngDkAAAnAAoKIwOJngDkAAAAAA==.',
Ko='Korialz:BAAANQADCgYIAgAAAA==.Kovah:BAACNQAFFH8UAAIPAAgK0xm5AAAoAgAPAAgK0xm5AAAoAgA1AAQKfy8AAg8ACgoNIF0FAJ8CAA8ACgoNIF0FAJ8CAAAA.Kowtagion:BAABNQAECn83AAMbAAoKLiZtAgBTAwAbAAoKLiZtAgBTAwAJAAEKeiVQswBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8pAAQkAAoKPxvnMQC+AQAkAAkKmhjnMQC+AQADAAYKiR5KagCmAQAGAAIKYAHhEQBLAAABNQAFFAQICQAhAPkQAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICwABNQAECgEIAwANAAAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAABNQAECn8VAAMbAAcKAQgqQgDZAAAbAAcKAQgqQgDZAAAJAAIKAQJXiwA8AAAAAA==.Kyruutos:BAAANQAECgMICgAAAA==.',
['Kí']='Kítkat:BAABNQAECn8uAAIeAAoKkxx4EwDxAgAeAAoKkxx4EwDxAgAAAA==.',
La='Laziza:BAAANQAECggIDgAAAA==.',
Le='Leibowitzy:BAABNQAECn9HAAMfAAoKpRicCACXAQAYAAoKjxMVJQD7AQAfAAcKphucCACXAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Lenastin:BAAANQAECgcIDAABNQAFFAEIBwATAHomAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQADCgEIAQAAAA==.',
Lh='Lhehitman:BAABNQAECn8lAAIiAAkK3SCoAgA4AwAiAAkK3SCoAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgUIEQAAAA==.Lightshax:BAABNQAECn8eAAITAAgKtQ/ZcQDCAQATAAgKtQ/ZcQDCAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8jAAIZAAoKNQ6aEQCXAQAZAAoKNQ6aEQCXAQAAAA==.Liv:BAAANQAECgMICwAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQAECgMIAwAAAA==.',
Lu='Luckydog:BAAANQAECgUIDgAAAA==.Ludey:BAABNQAECn9EAAMmAAoK0hogBACiAgAmAAoK0hogBACiAgAnAAEKVRQLOAFGAAAAAA==.Lumidk:BAAANQADCgEIAQAAAA==.Lumiya:BAAANQAECgQIBQAAAA==.Lutray:BAABNQAECn8cAAIUAAoKbSLuBgDyAgAUAAoKbSLuBgDyAgAAAA==.',
Ma='Madmango:BAAANQADCgEIAQAAAA==.Makaveleli:BAAANQAECgUIBwAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn9EAAIBAAoKlhaKJwB8AgABAAoKlhaKJwB8AgAAAA==.Marodd:BAABNQAECn8iAAICAAoKqB+lFQCxAgACAAoKqB+lFQCxAgAAAA==.Mashira:BAAANQAECgQIBwAAAA==.Mashîra:BAACNQAFFH8OAAIDAAcKEB7gAwAgAgADAAcKEB7gAwAgAgA1AAQKfzwAAwMACgoOJo8GAKkDAAMACgoOJo8GAKkDACQABgr1HxUjADUCAAAA.Matilda:BAAANQADCgEIAgAAAA==.Mattsz:BAAANQAECgUICQAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn9CAAQeAAoKyR4gHgDzAgAeAAoKyR4gHgDzAgAoAAEKAABqNQA6AAAOAAEKAAC0PwEuAAAAAA==.Mekuro:BAAANQAECgQIDgAAAA==.Melky:BAAANQAECggIEAAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgUIBQAAAA==.Mewfasa:BAAANQADCggICAAAAA==.Meyday:BAAANQAECgcICwAAAA==.',
Mi='Mia:BAABNQAECn8YAAISAAkKFyDXEQDdAgASAAkKFyDXEQDdAgAAAA==.Migraine:BAAANQADCgQIBAAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyA6TACwAgAFAAgKOyA6TACwAgAAAA==.Minasuzune:BAABNQAECn8WAAMDAAoKvR6naABCAgADAAoKvR6naABCAgAkAAIK9AzTdQBkAAAAAA==.Miney:BAAANQADCgYIDwAAAA==.Minus:BAAANQAECgcIDQABNQAECggIEAANAAAAAA==.',
Mo='Mojojojo:BAAANQAECgcIBwABNQAFFAQICQAhAPkQAA==.Moller:BAAANQAECgYICAAAAA==.Monkchow:BAAANQADCgEIAQAAAA==.Monkintrunk:BAAANQADCggICAABNQAECggICAANAAAAAA==.Moondotter:BAAANQAECgUIBAAAAA==.Moongoddess:BAAANQAECgQIBgABNQAECgUIBAANAAAAAA==.Moonslayer:BAABNQAECn8fAAIgAAoKRw4rMABMAQAgAAoKRw4rMABMAQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQADCgEIAQAAAA==.Myley:BAAANQAECggICwABNQAECggIEAANAAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAcIDgADABAeAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAcIDgADABAeAA==.Måshîrå:BAAANQAECgYICgABNQAFFAcIDgADABAeAA==.',
Na='Nakor:BAABNQAECn8gAAIhAAcKYgT8MQE5AQAhAAcKYgT8MQE5AQAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECn8hAAIMAAcKLBJwDwC1AQAMAAcKLBJwDwC1AQAAAA==.Natalie:BAAANQAECggIAwAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAABNQAECn8aAAMLAAcKKxIFqgC0AQALAAcKKxIFqgC0AQAUAAIKaApQLgBkAAAAAA==.Nefeli:BAABNQAECn8xAAIdAAoKYxVxBQCOAgAdAAoKYxVxBQCOAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAABNQAECn8aAAIdAAoKHwLUEQCSAAAdAAoKHwLUEQCSAAAAAA==.Nestia:BAABNQAECn8VAAIRAAgKeQuFNgAvAQARAAgKeQuFNgAvAQAAAA==.Never:BAACNQAFFH8JAAMHAAMKDBgMDQCdAAAHAAIKIBUMDQCdAAAnAAIKexiyJAB2AAA1AAQKfzgAAycACgrNIkoaAI4CACcACgpvIkoaAI4CAAcABQpHHjgdAIQBAAAA.',
Ni='Nightshade:BAABNQAECn82AAIDAAoKWBvVLwDdAgADAAoKWBvVLwDdAgAAAA==.Nimbus:BAAANQAECggIDwAAAA==.Nix:BAAANQAECgEIAQAAAA==.',
No='No:BAAANQAECgcIBwAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8lAAIEAAoKKBHVHQD7AQAEAAoKKBHVHQD7AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAABNQAECn8WAAIPAAgKsAWYUwBuAQAPAAgKsAWYUwBuAQAAAA==.',
On='Oniana:BAABNQAECn80AAIkAAkKLgsBGgB0AQAkAAkKLgsBGgB0AQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAFFAMIBwAgAEkNAA==.',
Ow='Owwmyballs:BAABNQAECn8bAAQbAAoKYwhTJgB9AQAbAAoKYwhTJgB9AQAJAAEK2QH6owAaAAAIAAEKAADqtwAAAAAAAA==.',
Oz='Ozygo:BAAANQAECgYICAAAAA==.',
Pa='Pagamas:BAACNQAFFH8OAAIhAAYKGxLMGQCrAQAhAAYKGxLMGQCrAQA1AAQKfycAAyEACgr1HrxXANACACEACgr1HrxXANACACIAAgqLEa03AF4AAAAA.Palandari:BAAANQAECgUICAAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Pandormu:BAAANQAECgYICQABNQAECgoKIwAmAMAVAA==.Panter:BAABNQAECn8jAAImAAoKwBWsBQBiAgAmAAoKwBWsBQBiAgAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAABNQAECn8YAAIaAAgKaQ0bHADdAAAaAAgKaQ0bHADdAAAAAA==.',
Ph='Phodoe:BAABNQAECn8kAAIWAAoK9QwfNAB6AQAWAAoK9QwfNAB6AQAAAA==.Phöebe:BAAANQAECgMIBgAAAA==.',
Pi='Pikepole:BAAANQADCgEIAQAAAA==.Pinquisitor:BAAANQADCgQIAgABNQAECgMICAANAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAAANQAECgYIEwAAAA==.',
Po='Pokeureyeout:BAABNQAECn8gAAIDAAcKkg3utgCWAQADAAcKkg3utgCWAQAAAA==.Pole:BAAANQADCgUIBQABNQAECgkJNAASADkcAA==.Port:BAAANQAECgUIBgABNQAECgcIDgANAAAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECgoKKwAWAGQXAA==.Prodyne:BAABNQAECn86AAIhAAoKLhW/eQCKAgAhAAoKLhW/eQCKAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgkJIAACAIsbAA==.',
Qa='Qariwarmi:BAAANQAECgIIAgAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAFFAQICAABAG0dAA==.Quiettreader:BAABNQAECn9HAAIiAAoKuxg7BQDDAgAiAAoKuxg7BQDDAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAABNQAECn8XAAIIAAoKWBPKJgDlAQAIAAoKWBPKJgDlAQAAAA==.Rafiki:BAAANQAECgMIAwAAAA==.Raidboss:BAABNQAECn8WAAILAAoKTx3acQA+AgALAAoKTx3acQA+AgAAAA==.',
Re='Redeath:BAAANQAECgQIBgABNQAECgYICAANAAAAAA==.Redirect:BAAANQAECgUIBwABNQAECgYICAANAAAAAA==.Redonculous:BAABNQAECn81AAICAAoKtxeCHgBLAgACAAoKtxeCHgBLAgAAAA==.Redpool:BAACNQAFFH8IAAIeAAQKPwbyEgDtAAAeAAQKPwbyEgDtAAA1AAQKfzYAAh4ACgpBEbFdAPYBAB4ACgpBEbFdAPYBAAAA.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8nAAISAAcK7CBmGACZAgASAAcK7CBmGACZAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgkJOAAKAHUjAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.Riggymortis:BAAANQAECgIIAgAAAA==.',
Ro='Ronx:BAABNQAECn8WAAIiAAYKmxnNEgB7AQAiAAYKmxnNEgB7AQAAAA==.Roxxiloxxi:BAABNQAECn8oAAMHAAoK/gW5GACmAQAHAAkKfga5GACmAQAnAAUKVgKR0QB/AAAAAA==.',
Ru='Rudeboy:BAABNQAECn8sAAInAAoKXhkJVQBXAgAnAAoKXhkJVQBXAgAAAA==.Rumchata:BAAANQAECgEIAQABNQAFFAMIBwAgAEkNAA==.Rushu:BAACNQAFFH8JAAIhAAQK+RAfIADdAAAhAAQK+RAfIADdAAA1AAQKfzwAAiEACgo8H30dALICACEACgo8H30dALICAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn86AAMTAAoKUxmaQABiAgATAAoKUxmaQABiAgAFAAcKYQrx3wBbAQAAAA==.Sagitta:BAAANQADCgcICAABNQAECgcIEwANAAAAAA==.Sahria:BAAANQAECgUICQAAAA==.Samlosco:BAAANQAECggIEAAAAA==.Sapphpal:BAAANQAECgYICAABNQAECggIDwANAAAAAA==.Sarhia:BAAANQAECgMIAwAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgANAAAAAA==.',
Sc='Schizadin:BAABNQAECn8rAAMEAAkKuCU0AQBxAwAEAAkKuCU0AQBxAwAFAAMKHgfbbQFxAAAAAA==.Schizology:BAAANQAECgcICQABNQAECgkJKwAEALglAA==.Schnoze:BAAANQAECgUIDgAAAA==.',
Se='Seabane:BAAANQAECggIDQAAAA==.Sebekuul:BAAANQADCgYIBwAAAQ==.Selfie:BAAANQADCgEIAQAAAA==.Selwenna:BAAANQADCgMIAwABNQAECgQICAANAAAAAA==.Selys:BAACNQAFFH8LAAIhAAUKVQovLgAfAQAhAAUKVQovLgAfAQA1AAQKf1QAAyEACgrqGq0nAIQCACEACgrqGq0nAIQCACIAAgr1BoY5AFgAAAAA.Sence:BAAANQADCgEIAQAAAA==.Sepheturix:BAAANQAECgUICQAAAA==.Sephurik:BAACNQAFFH8kAAMhAAoK/hjNAQCSAgAhAAoKiRfNAQCSAgAiAAEKBAzuDQBWAAA1AAQKf0sAAyEACgpsJFkrADkDACEACgqxIlkrADkDACIAAgpEH5gpAKoAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQAECgEIAQAAAA==.Shadowwife:BAAANQADCgYIBwAAAA==.Shamaneez:BAAANQADCggIDwAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Sharpteeth:BAAANQADCgEIAQAAAA==.Shawnalenee:BAABNQAECn8WAAICAAcKXxhXIQBAAQACAAcKXxhXIQBAAQABNQAECgcIGAAeADkfAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiftingmoon:BAAANQAECgQIBAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.Shiv:BAAANQAECggIBAAAAA==.Shyft:BAAANQAECgQICAAAAA==.',
Si='Sidisi:BAAANQAECggIDwABNQAECgoKKAAkAJ4gAA==.Sikanda:BAABNQAECn8YAAMbAAkK4RtnIwC2AgAbAAkK4RtnIwC2AgAIAAIKuhRVjACEAAABNQAECgoKKAAkAJ4gAA==.Silvea:BAABNQAECn8oAAIOAAkKjhFNRwB+AQAOAAkKjhFNRwB+AQAAAA==.Silvett:BAAANQAECgQIBgAAAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn8yAAICAAoKsSAzDQAYAwACAAoKsSAzDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAABNQAECn8bAAIJAAgKgAuIPQAhAQAJAAgKgAuIPQAhAQAAAA==.Sky:BAACNQAFFH8FAAIhAAMKfxeVQACxAAAhAAMKfxeVQACxAAA1AAQKfzIAAiEACgr4JOEVAHsDACEACgr4JOEVAHsDAAAA.Skyelf:BAABNQAECn8tAAIDAAoKfw3XVwDYAQADAAoKfw3XVwDYAQAAAA==.',
Sl='Slimshadow:BAAANQADCgEIAQAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDwAAAA==.Smokebreak:BAAANQADCggICQAAAA==.',
Sn='Snooflepoof:BAABNQAECn81AAMeAAoKQxnOIADmAgAeAAoKQxnOIADmAgAOAAEKxAPg6gAsAAAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAgIKAAoAOkdAA==.Solunara:BAAANQADCgUIBQABNQAECggIFwAFAGcXAA==.',
Sp='Sparta:BAAANQADCgEIAQAAAA==.Spectrecles:BAACNQAFFH8HAAIgAAMKSQ1kEADGAAAgAAMKSQ1kEADGAAA1AAQKfzgAAyAACgpNGGwbAPYBACAACgpNGGwbAPYBABYAAQo8BulyAB0AAAAA.Spectrecless:BAAANQAECgMIAwABNQAFFAMIBwAgAEkNAA==.Speez:BAABNQAECn8jAAIDAAgKFBPfegAZAgADAAgKFBPfegAZAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.Spèctral:BAAANQADCgQIBAAAAA==.',
St='Stablehand:BAABNQAECn8gAAIDAAkKHRVxZQCyAQADAAkKHRVxZQCyAQAAAA==.Standpipe:BAAANQADCgEIAQAAAA==.Steve:BAACNQAFFH8gAAMOAAgKwRbYAwCjAQAOAAcKTxXYAwCjAQAoAAEK+B3lBQBnAAA1AAQKf0IABA4ACgqGIxwUAFEDAA4ACgpsIxwUAFEDACgABgpaIMURALgBAB4AAgpiAgUkASkAAAAA.Stevenzb:BAAANQAECgEIAQAAAA==.Stonedfel:BAABNQAECn8vAAIRAAoKnhIUOQDqAQARAAoKnhIUOQDqAQAAAA==.',
Su='Sugarftx:BAAANQAECgEIAQAAAA==.Sunhoof:BAABNQAECn8XAAQFAAgKZxeIhAAeAgAFAAgKZxeIhAAeAgAEAAIKfRMUWgB0AAATAAIKHAW2EQFTAAAAAA==.Supahotvile:BAACNQAFFH8GAAMKAAMKaQZrGACKAAAKAAIKAQdrGACKAAAPAAIKYgTPCwBdAAA1AAQKfyYAAw8ACgrWFRMsADgCAA8ACgpFDxMsADgCAAoABQqUGFxSAGwBAAAA.',
Sy='Syx:BAAANQAECgYICwAAAA==.',
['Sø']='Sørrow:BAABNQAECn8iAAISAAoK5w3qNQCUAQASAAoK5w3qNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8lAAMiAAoKgAfUFwA8AQAiAAoKVAfUFwA8AQAhAAYK9QG3ewHKAAAAAA==.Tabu:BAAANQAECgcICgAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggIDwAAAA==.Tankoromma:BAAANQAECgYICwAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgUIDAANAAAAAA==.Tarryne:BAAANQAECgEIAQAAAA==.',
Te='Ten:BAAANQAECgIIBQAAAA==.Test:BAAANQAECggJAQAAAA==.',
Th='Tharil:BAAANQAECgQIBAAAAA==.Theblakmamba:BAAANQADCgIIBAAAAA==.Thedawg:BAAANQADCgEIAgAAAA==.Thedayman:BAAANQADCggICQAAAA==.Thetaint:BAABNQAECn81AAMPAAoKkiOnBACLAwAPAAoKkiOnBACLAwAKAAkKDRz/IwBFAgAAAA==.Thunderous:BAAANQADCgMIBAAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8NAAIDAAYKUSC/BwDSAQADAAYKUSC/BwDSAQA1AAQKfzUAAwMACgosJqgDAGcDAAMACgosJqgDAGcDACQAAQpAGVOBAEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgoKMgACALEgAA==.',
To='Tomahawkchow:BAAANQAECggIEwAAAA==.Totemofpeace:BAAANQADCggIEQABNQAECgoKKwAWAGQXAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Treehorse:BAAANQAECgQICAAAAA==.Trentlock:BAACNQAFFH8TAAQnAAYKUwTRJAB1AAAnAAQKcATRJAB1AAAHAAIKNQTzEgA+AAAmAAEKAABrEgA+AAA1AAQKfzkABCcACgo1Ho1SAF4CACcACgocGI1SAF4CAAcABAoyIV0hAGYBACYAAwruG0IWAJUAAAAA.Tristae:BAAANQAECgYIDAAAAA==.',
Ts='Tsu:BAABNQAECn8gAAMKAAkKrSPXKgAdAgAKAAgK1SPXKgAdAgAPAAcK3xsFMQAdAgAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgIIAgAAAA==.Unstablesha:BAAANQAECggIEgAAAA==.',
Ut='Utilities:BAAANQADCggICQAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8TAAQbAAUKEBNeBgDjAAAbAAQKEBNeBgDjAAAIAAEKvAEtHAAtAAAJAAEKAADUNgAlAAA1AAQKfzAAAhsACgqMIbQVAAwDABsACgqMIbQVAAwDAAAA.',
Vd='Vdomil:BAAANQADCgEIAQAAAA==.',
Vi='Via:BAAANQAECgIIBAAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vigiles:BAAANQAECgEIAQAAAA==.Vil:BAACNQAFFH80AAICAAoKUCURAAB7AwACAAoKUCURAAB7AwA1AAQKfysAAgIACgrJJkcCAL0DAAIACgrJJkcCAL0DAAAA.Vilonus:BAABNQAECn8nAAInAAgKthA1lAC0AQAnAAgKthA1lAC0AQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgoKMgACALEgAA==.',
Vo='Voidbwoy:BAAANQADCggIFAAAAA==.Volairis:BAAANQAECgYICAABNQAFFAYICgAaAKEQAA==.Volumexthree:BAAANQADCgEIAQAAAA==.Voy:BAABNQAECn8eAAIGAAgKtwgZCQCvAQAGAAgKtwgZCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICgAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wa='Wagyu:BAAANQAECgEIAQAAAA==.Wallaroo:BAAANQADCgUIAgAAAA==.',
We='Weezy:BAABNQAECn8oAAMBAAoKKw+uRADtAQABAAkKlw+uRADtAQACAAkKJAkwOABkAQAAAA==.',
Wi='Williie:BAAANQAECgcICwAAAA==.Withengar:BAAANQAECgcIBgAAAA==.',
Wu='Wuoshi:BAAANQAECgUIDAAAAA==.Wuuzzyy:BAABNQAECn8nAAIgAAkKDRMlNwA0AgAgAAkKDRMlNwA0AgAAAA==.',
Xa='Xaliko:BAABNQAECn8WAAInAAoKAhZEVgCYAQAnAAoKAhZEVgCYAQAAAA==.Xanbaran:BAABNQAECn86AAIBAAoKTQpRbgDTAQABAAoKTQpRbgDTAQAAAA==.Xandian:BAAANQAECgQIBAAAAA==.',
Xi='Xiphus:BAAANQAECgIIAwAAAA==.',
Xm='Xmarks:BAAANQAECggIDgAAAA==.',
Xy='Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFH8SAAIeAAUKnCCaBwDeAQAeAAUKnCCaBwDeAQA1AAQKf0UAAx4ACgrFIiAQAEMDAB4ACgrFIiAQAEMDAA4AAQoAAO4iAUsAAAAA.',
Ya='Yahenni:BAABNQAECn8oAAMkAAoKniBNFQC0AgAkAAgK3x9NFQC0AgADAAkKUBh1YwBOAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAABNQAECn8WAAIBAAkK5A3WQAD+AQABAAkK5A3WQAD+AQAAAA==.Yukki:BAAANQAECggIDgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAABNQAECn8nAAISAAoKIxl6DgBHAgASAAoKIxl6DgBHAgAAAA==.',
Ze='Zerk:BAABNQAECn8XAAILAAkKYQJ+AwHWAAALAAkKYQJ+AwHWAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
['Ða']='Ðavîs:BAAANQAECgEIAgABNQAECgoKMwAbAHQcAA==.',
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
