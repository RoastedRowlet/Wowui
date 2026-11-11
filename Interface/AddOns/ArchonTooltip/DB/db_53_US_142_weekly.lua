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
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abdulr:BAAANQAECggICAAAAA==.Abused:BAAANQADCgUIBwAAAA==.',
Ad='Adelaide:BAACNQAFFH8bAAMBAAYKPBkADADMAQABAAYKPBkADADMAQACAAQKWgRhDQCqAAA1AAQKfyoAAwEACgqBIJMZAA8DAAEACgqBIJMZAA8DAAIABArOEdotAAABAAE1AAUUBwgPAAMARiEA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8sAAMEAAkKyiXOBABoAwAEAAkKyiXOBABoAwAFAAEKmhYajQFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECgkJLAAEAMolAA==.',
Aj='Ajunlucky:BAACNQAFFH8TAAIGAAYK9RBxAABBAQAGAAYK9RBxAABBAQA1AAQKfzsAAgYACgqPISQCACwDAAYACgqPISQCACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECgkJLAAEAMolAA==.Alnilam:BAABNQAECn8/AAIHAAoKJxIdEgDlAQAHAAoKJxIdEgDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAABNQAECn8UAAMIAAoKDQf/WwA5AQAIAAcKlQf/WwA5AQAJAAoKaQQLeAAXAQAAAA==.',
Ar='Arbys:BAAANQAECggIDgAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECn84AAIKAAkKdSMVBQA6AwAKAAkKdSMVBQA6AwAAAA==.Armados:BAABNQAECn82AAILAAoKAhW6PABAAgALAAoKAhW6PABAAgAAAA==.Aroxw:BAACNQAFFH8RAAILAAYKYw9AEwCVAQALAAYKYw9AEwCVAQA1AAQKfywAAwsACgo/Iec9ANECAAsACgo/Iec9ANECAAwAAQoAABQoAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Athineana:BAAANQAECgQIBAAAAA==.Atlim:BAAANQAECgQICQAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwAAAA==.',
Ba='Bad:BAAANQAECggICAAAAA==.Balfas:BAAANQADCgQIBAABNQAFFAUIBgANAEMJAA==.Ballidur:BAABNQAECn8UAAMOAAkKug4lJQC/AQAOAAkKug4lJQC/AQAPAAIKHgHPeQAiAAABNQAFFAQIBAAQAAAAAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn9MAAIMAAoKdiNeAQA3AwAMAAoKdiNeAQA3AwAAAA==.Bettyspready:BAABNQAECn8iAAIRAAkKLBTYHAA3AQARAAkKLBTYHAA3AQAAAA==.',
Bi='Bigbluecheez:BAAANQAECgEIAQAAAA==.Bigmanooshki:BAAANQAECgEIAgAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAABNQAECn8lAAISAAoK3wbFEwDmAAASAAoK3wbFEwDmAAAAAA==.',
Bl='Blackfoot:BAABNQAECn8WAAINAAoKJg8qdgC/AQANAAoKJg8qdgC/AQAAAA==.Blankjr:BAAANQAECgcIDgAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAcIDwADAEYhAA==.Blightmoss:BAAANQAECgQIBwABNQAECggIFwAFAGcXAA==.Blindpov:BAACNQAFFH8JAAITAAQK1yD+CwDoAAATAAQK1yD+CwDoAAA1AAQKf0YAAxMACgpRJpABAOIDABMACgpRJpABAOIDABQABwq2IAobAL8BAAAA.Bloodpride:BAAANQADCgcIFgAAAA==.',
Bo='Bodyodyodied:BAAANQAECgMIAwAAAA==.Bonquiquie:BAAANQAECgUIBAAAAA==.Boomyboi:BAAANQAECgQIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Borne:BAAANQABCgEIAQAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8oAAITAAoKfR8PEgCGAgATAAoKfR8PEgCGAgAAAA==.Breakerr:BAAANQAECgMIAgAAAA==.Brewzlee:BAAANQAECgMIAwAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn89AAMVAAoKwx/7EwAJAwAVAAoKwx/7EwAJAwAFAAMK5A8XTAFvAAAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgMaABjAgAFAAgKIBgMaABjAgAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xmDBwD7AQAGAAcKlBaDBwD7AQADAAMKIBTLGwHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAIWAAgKSwqdHQBpAQAWAAgKSwqdHQBpAQAAAA==.Carmakazie:BAAANQADCggICAAAAA==.Cattle:BAABNQAECn88AAIXAAoKehp+DgB8AgAXAAoKehp+DgB8AgAAAA==.Cazul:BAABNQAECn8XAAIYAAgK/AvWbAB9AQAYAAgK/AvWbAB9AQAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Cheetodemon:BAAANQADCgMIAQAAAA==.Chowdk:BAAANQADCggICwAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECggIDwAAAA==.Chowpal:BAAANQAECgYIBwAAAA==.',
Cl='Clawsofpeace:BAABNQAECn8vAAMPAAoKZBeIHgA6AgAPAAgK0haIHgA6AgAXAAgKehUYHgB8AQAAAA==.',
Co='Constanse:BAAANQADCgYIDAAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cr='Crewman:BAAANQAECgQIBgAAAA==.Crosshairs:BAAANQADCggIDgABNQAECgoKRQAUAJIiAA==.',
Cy='Cylic:BAABNQAECn8fAAIKAAgKiSIsCQDjAgAKAAgKiSIsCQDjAgAAAA==.Cyrùsdh:BAAANQAECgYIBQAAAA==.',
Da='Daddiestouch:BAABNQAECn8kAAMCAAoKrRpbDwBQAgACAAoKrRpbDwBQAgAZAAIKbgcdIwBPAAAAAA==.Dampundies:BAABNQAECn8YAAIaAAkKqRvyFgCVAgAaAAkKqRvyFgCVAgAAAA==.Dangerdream:BAABNQAECn9FAAQUAAoKkiJUCgA1AwAUAAoKkiJUCgA1AwAbAAcK4A7sGwD8AAATAAEKFRXkjQBAAAAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBQAAAA==.Dartini:BAAANQADCgIIAgABNQAECgoKKAAUADIZAA==.Dassani:BAAANQAECgIIAQAAAA==.Datsmywife:BAABNQAECn88AAIcAAoK5xVmCwABAgAcAAoK5xVmCwABAgAAAA==.Davis:BAABNQAECn8zAAQdAAoKdBxEJQCqAgAdAAoKgxtEJQCqAgAJAAgKtg1PNQBjAQAIAAMKqBF3hQCaAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.Daysies:BAAANQAECgEIAQAAAA==.',
De='Deadasice:BAAANQAECgYIBgAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn89AAIeAAoKCSEZBwDYAgAeAAoKCSEZBwDYAgAAAA==.Derppriest:BAAANQADCggICAABNQAECgoKPQAeAAkhAA==.Deviiarrc:BAACNQAFFH8bAAMeAAcKNBI/BgABAgAeAAcKNBI/BgABAgAfAAEKewE4DwAsAAA1AAQKf0UAAx4ACgpII94EAGADAB4ACgpII94EAGADAB8AAwpHBxIUAIwAAAAA.Devviarc:BAAANQADCggICwABNQAFFAcIGwAeADQSAA==.',
Di='Dibgargargad:BAABNQAECn8jAAIJAAoKbRytDwCbAgAJAAoKbRytDwCbAgAAAA==.',
Dl='Dlamb:BAAANQAECgUIEgABNQAECgcIFwACAF8YAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn8zAAQMAAoK+CDpBwAaAgAMAAoK7CDpBwAaAgALAAMKBhjbDQHBAAAWAAMKhxBWNQBbAAAAAA==.',
Dr='Dracar:BAABNQAECn89AAIFAAoK6SIdDwCPAwAFAAoK6SIdDwCPAwAAAA==.Draennor:BAAANQAECggIDgAAAA==.Dragoun:BAAANQAECggIDQAAAA==.Drmmrfist:BAABNQAECn8bAAIgAAgKURCTFACaAQAgAAgKURCTFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwib:BAAANQAECgcICAABNQAECggIEQAQAAAAAA==.Dwippietiggs:BAABNQAECn9BAAIFAAoKvR6iSAC7AgAFAAoKvR6iSAC7AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAcIIAAVAGUmAA==.Earthfeather:BAAANQAECgUIBgAAAA==.Easymac:BAAANQADCgIJAwABNQAECgoKKAATAH0fAA==.',
Ed='Edhochuli:BAAANQADCgIIAgABNQAFFAMIBwAOAEkNAA==.',
Ee='Eetee:BAEBNQAECn8kAAMNAAkK/gq3XgBSAQANAAkK/gq3XgBSAQAhAAMKhxFprgCsAAABNQAECgoKOgAEAEwNAA==.',
Eg='Eggon:BAAANQADCgEIAQAAAA==.Eggrolls:BAAANQAECgEIAQABNQAECgQICAAQAAAAAA==.',
Eh='Ehemingway:BAABNQAECn8vAAIDAAkKShfYOgBTAgADAAkKShfYOgBTAgAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAcIDwADAEYhAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQAECgEIAgAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epicdragon:BAAANQAECgEIAQAAAA==.Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8mAAIRAAoK3xBPOgDqAQARAAoK3xBPOgDqAQAAAA==.Ereye:BAABNQAECn8YAAIKAAcKHhaiHwDSAQAKAAcKHhaiHwDSAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAABNQAECn8iAAIiAAgKignd/wCOAQAiAAgKignd/wCOAQAAAA==.Esturi:BAAANQAECgQIBAAAAA==.',
Et='Etatoned:BAEANQADCgQIBAABNQAECgoKOgAEAEwNAA==.Etengaged:BAEBNQAECn86AAMEAAoKTA3YHABzAQAEAAoKTA3YHABzAQAFAAQK2ga7NAGKAAAAAA==.Ethavoc:BAEBNQAECn8YAAIJAAgK0wcacgAtAQAJAAgK0wcacgAtAQABNQAECgoKOgAEAEwNAA==.',
Ev='Evrae:BAABNQAECn8jAAIKAAoKOBZCDwCGAgAKAAoKOBZCDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcICwAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAABNQAECn8lAAIBAAoKCQt0hQCGAQABAAoKCQt0hQCGAQAAAA==.Fatduck:BAAANQADCgQIBAAAAA==.Fatkow:BAABNQAECn8eAAMcAAkKHBwHBgCXAgAcAAkKHBwHBgCXAgAXAAQKOx6uKwA6AQABNQAECgoKPgAdAC4mAA==.',
Fe='Fearthemoo:BAAANQADCgcICAABNQAECgoKJAACAK0aAA==.Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fellumir:BAAANQAECgIIAgAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH83AAMiAAkKUSIlCQA1AgAiAAcKKCIlCQA1AgAjAAIKuiJPBADGAAA1AAQKfyYAAiIACgpgIvJTANgCACIACgpgIvJTANgCAAAA.Finkler:BAABNQAECn8oAAMiAAoK0BzaewCGAgAiAAoKIRraewCGAgAjAAIK3yTNJADIAAABNQAFFAkJNwAiAFEiAA==.Firecow:BAAANQAECgIIAgAAAA==.Firedanny:BAAANQAECgUIBgAAAA==.Fistsofpeace:BAAANQAECgYICwABNQAECgoKLwAPAGQXAA==.',
Fl='Flameshock:BAABNQAECn82AAMjAAoKmA+xDwCtAQAiAAoK5Q0ZswAdAgAjAAgKXg+xDwCtAQAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgoKTwAgAHYZAA==.',
Fr='Frankda:BAAANQADCgIIAgABNQAECgYIBgAQAAAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friarmj:BAAANQADCgUICAAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAcKGwADAKAiAA==.Friendship:BAAANQAECgIIAQAAAA==.Frigidbeach:BAAANQAECgIIAwAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH84AAMSAAoKOh9nAAAGAgAfAAkKnxlEAQBrAgASAAcK/iFnAAAGAgA1AAQKfyEAAxIACgpxIq8OAHMCABIACgoCH68OAHMCAB8ABAreJOIOAFQBAAAA.Gloreb:BAACNQAFFH8FAAIaAAUKXBeqCABXAQAaAAUKXBeqCABXAQA1AAQKfxUAAhoACAqGHb8XAOEBABoACAqGHb8XAOEBAAAA.',
Go='Goomi:BAABNQAECn8lAAINAAgKTRBDWwBdAQANAAgKTRBDWwBdAQAAAA==.Gordef:BAABNQAECn8hAAMjAAoKuxV3DADzAQAjAAoKPxV3DADzAQAkAAYKPw+1BABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgQICQAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEwAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Haranor:BAAANQAECggIEQAAAA==.Harrowing:BAABNQAECn9ZAAIVAAoKsR4JGQAUAwAVAAoKsR4JGQAUAwAAAA==.Haurt:BAABNQAECn84AAIOAAoK5Qr9LgB2AQAOAAoK5Qr9LgB2AQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8hAAIJAAgKFBlRMAB+AQAJAAgKFBlRMAB+AQAAAA==.',
Hi='Hirokii:BAAANQAECgMIDQABNQAECggIEQAQAAAAAA==.Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8pAAMVAAoKHhnaMACjAgAVAAoKHhnaMACjAgAFAAkKQB85bQDiAQAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAABNQAECn8gAAMDAAoKtA22YADtAQADAAoKtA22YADtAQAlAAQKnQMGVABOAAAAAA==.Hotmess:BAABNQAECn8gAAImAAoKsxlICgCOAgAmAAoKsxlICgCOAgAAAA==.',
Hu='Hurg:BAAANQAECggIEwAAAA==.Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAABNQAECn8iAAIhAAoKbCLoBwCMAwAhAAoKbCLoBwCMAwAAAA==.',
Il='Illindi:BAAANQADCgQIBQAAAA==.',
In='Insanê:BAABNQAECn8qAAMIAAoKpBnELQDhAQAIAAoKpBnELQDhAQAJAAUKwBEVawCVAAABNQAECgkJMAAaAJ8TAA==.Insañe:BAABNQAECn8wAAMaAAkKnxORHwAzAgAaAAkKnxORHwAzAgAgAAEKkRC6MQAxAAAAAA==.Instinkts:BAAANQABCgIIAgABNQADCgYIBgAQAAAAAA==.Invi:BAAANQAECggIDwAAAA==.',
Ir='Irina:BAAANQABCggICgABNQAECgoKSgAnANIaAA==.Irkellydonu:BAAANQAECgEIAQAAAA==.Ironbeef:BAAANQAECgYIEgAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgAQAAAAAA==.Jadengras:BAABNQAECn8UAAQHAAUKcAfZOADdAAAHAAUKpQbZOADdAAAYAAQKpgWl4AB+AAAnAAEKxQHjLgAjAAAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAABNQAECn8eAAIOAAoKeBhkGQAuAgAOAAoKeBhkGQAuAgAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAABNQAECn8VAAILAAgKrwjSzABbAQALAAgKrwjSzABbAQAAAA==.',
['Jë']='Jësus:BAABNQAECn9AAAMBAAoKmBqnLQB7AgABAAoKkRqnLQB7AgAZAAgKaxMACwCTAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgcIFQAAAA==.Kalel:BAAANQAECgUIDAAAAA==.Karaman:BAAANQADCgIIAwAAAA==.Karmakazie:BAAANQAECgcICwAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn87AAIDAAkKixiwUwAOAgADAAkKixiwUwAOAgAAAA==.Kazraghand:BAABNQAECn9VAAIGAAoKrxDgBAAOAgAGAAoKrxDgBAAOAgAAAA==.',
Ke='Keetanah:BAAANQAECgUIDAAAAA==.Kei:BAACNQAFFH8HAAIUAAMKSg4WDgDGAAAUAAMKSg4WDgDGAAA1AAQKfycAAxQACgoxGtYXAJ4CABQACgoxGtYXAJ4CABMAAQrpDOiPADsAAAE1AAUUBwgPACUAJA0A.Kelsio:BAABNQAECn82AAIDAAoKJBnpPwBDAgADAAoKJBnpPwBDAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAACNQAFFH8MAAIBAAQKaQf8GwD6AAABAAQKaQf8GwD6AAA1AAQKfzcAAgEACgq8D2ZSACwCAAEACgq8D2ZSACwCAAAA.',
Ki='Kikeo:BAACNQAFFH8PAAMlAAcKJA3ZDwDJAAAlAAUKKgzZDwDJAAADAAMKmw41HQChAAA1AAQKfx0AAyUACQoZG7AaAJgBAAMABwocFvu0AJoBACUACArxGbAaAJgBAAAA.Kinks:BAABNQAECn8rAAMTAAoKbhCwKQCqAQATAAoKbhCwKQCqAQAbAAMK5QdGIgBmAAAAAA==.Kirkoth:BAAANQAECgMIAwAAAA==.',
Kn='Knuah:BAAANQAECgMIAwABNQAECgoKOAACABYYAA==.Knuts:BAABNQAECn8WAAIYAAoKIwMKrQDmAAAYAAoKIwMKrQDmAAAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAACNQAFFH8UAAIRAAgK0xkRAQAaAgARAAgK0xkRAQAaAgA1AAQKfy8AAhEACgoNIEYGAJcCABEACgoNIEYGAJcCAAAA.Kowtagion:BAABNQAECn8+AAQdAAoKLibcBACoAwAdAAoKLibcBACoAwAIAAcKTRzzJQASAgAJAAEKeiVQswBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8sAAQlAAoKERznMQC+AQADAAYKWiCBbgDJAQAlAAkKmhjnMQC+AQAGAAIKYAHhEQBLAAABNQAFFAQICQAiAPkQAA==.Kronko:BAAANQAECgIIAQAAAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQABNQAECgEIAQAQAAAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAABNQAECn8ZAAMdAAcKhgkBSADXAAAdAAcKAQgBSADXAAAJAAUKPAbsZwCeAAAAAA==.Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECn8uAAIhAAoKkxwTGADiAgAhAAoKkxwTGADiAgAAAA==.',
La='Laziza:BAABNQAECn8VAAINAAoKbQnBUAB/AQANAAoKbQnBUAB/AQAAAA==.',
Le='Leibowitzy:BAABNQAECn9PAAMgAAoKdhnOCQCVAQAaAAoKYRQVJQD7AQAgAAcKphvOCQCVAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Lenastin:BAAANQAECgcIDAABNQAFFAEIBwAVAHomAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQADCgEIAQAAAA==.',
Lh='Lhehitman:BAABNQAECn8oAAIjAAoK5RyoAgA4AwAjAAoK5RyoAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgUIEQAAAA==.Lightshax:BAABNQAECn8eAAIVAAgKtQ/ZcQDCAQAVAAgKtQ/ZcQDCAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8jAAIbAAoKNQ6aEQCXAQAbAAoKNQ6aEQCXAQAAAA==.Liv:BAAANQAECgMICwAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQAECgQIBAAAAA==.',
Lu='Luckydog:BAAANQAECgUICwAAAA==.Ludey:BAABNQAECn9KAAMnAAoK0hogBACiAgAnAAoK0hogBACiAgAYAAEKVRQLOAFGAAAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgQIAwAAAA==.Lutray:BAABNQAECn8gAAIWAAoKOCPuBgDyAgAWAAoKOCPuBgDyAgAAAA==.',
Ma='Makaveleli:BAAANQAECgUIBwAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn9IAAIBAAoKlhYGMABuAgABAAoKlhYGMABuAgAAAA==.Marodd:BAABNQAECn8mAAICAAoK0R+lFQCxAgACAAoK0R+lFQCxAgAAAA==.Mashira:BAAANQAECgMIBAAAAA==.Mashîra:BAACNQAFFH8OAAIDAAcKEB7gAwAgAgADAAcKEB7gAwAgAgA1AAQKfzwAAwMACgoOJo8GAKkDAAMACgoOJo8GAKkDACUABgr1HxUjADUCAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgUICQAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn9FAAQhAAoKyR4gHgDzAgAhAAoKyR4gHgDzAgAoAAEKAABqNQA6AAANAAEKAAC0PwEuAAAAAA==.Mekuro:BAAANQAECgQIDgAAAA==.Melky:BAABNQAECn8WAAMaAAkKag67IACAAQAaAAgKvAy7IACAAQAgAAQKGBF4FwCnAAAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgUIBAAAAA==.Mewfasa:BAAANQADCggICAAAAA==.Meyday:BAAANQAECgcIEAAAAA==.',
Mi='Mia:BAABNQAECn8cAAIUAAoKgyDXEQDdAgAUAAoKgyDXEQDdAgAAAA==.Migraine:BAAANQADCggIDAAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyA6TACwAgAFAAgKOyA6TACwAgAAAA==.Minasuzune:BAABNQAECn8aAAMDAAoKHSKnaABCAgADAAoKHSKnaABCAgAlAAIK9AzTdQBkAAAAAA==.Minus:BAAANQAECgcIEgABNQAECgkJFgAaAGoOAA==.',
Mo='Mojojojo:BAAANQAECgcIBwABNQAFFAQICQAiAPkQAA==.Moller:BAAANQAECgYICAAAAA==.Monkchow:BAAANQADCgEIAQAAAA==.Monkintrunk:BAAANQADCggICAABNQAECgYIBgAQAAAAAA==.Moondotter:BAAANQAECgUIBAAAAA==.Moongoddess:BAAANQAECgQICAABNQAECgUIBAAQAAAAAA==.Moonslayer:BAABNQAECn8jAAIOAAoKuhB1MQBmAQAOAAoKuhB1MQBmAQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.Myley:BAAANQAECggIEQABNQAECgkJFgAaAGoOAA==.',
['Mà']='Màgnus:BAAANQADCgEIAQAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAcIDgADABAeAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAcIDgADABAeAA==.Måshîrå:BAAANQAECgYICQABNQAFFAcIDgADABAeAA==.',
['Mê']='Mêl:BAAANQADCgQIBAAAAA==.',
Na='Nakor:BAABNQAECn8gAAIiAAcKYgT8MQE5AQAiAAcKYgT8MQE5AQAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECn8nAAMMAAcKLBJwDwC1AQAMAAcKLBJwDwC1AQALAAYKnwZMtwD0AAAAAA==.Natalie:BAAANQAECggIAQAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAABNQAECn8bAAMLAAgKOxEeiwBYAQALAAgKOxEeiwBYAQAWAAIKaApZMwBjAAAAAA==.Nefeli:BAABNQAECn8xAAIfAAoKYxVxBQCOAgAfAAoKYxVxBQCOAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAABNQAECn8aAAIfAAoKHwK4EwCRAAAfAAoKHwK4EwCRAAAAAA==.Nestia:BAABNQAECn8XAAITAAgKuQsYPAA1AQATAAgKuQsYPAA1AQAAAA==.Never:BAACNQAFFH8JAAMHAAMKDBgMDQCdAAAHAAIKIBUMDQCdAAAYAAIKexiiLgCcAAA1AAQKfzkAAxgACgrNIpMeAI4CABgACgpvIpMeAI4CAAcABQpHHjgdAIQBAAAA.',
Ni='Nightshade:BAABNQAECn86AAIDAAoKvR3VLwDdAgADAAoKvR3VLwDdAgAAAA==.Nimbus:BAAANQAECggIDQAAAA==.',
No='No:BAAANQAECgYIBgAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8oAAIEAAoKHRbVHQD7AQAEAAoKHRbVHQD7AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAABNQAECn8WAAIRAAgKsAWYUwBuAQARAAgKsAWYUwBuAQAAAA==.',
On='Oniana:BAABNQAECn8+AAIlAAoKmgwZFwDGAQAlAAoKmgwZFwDGAQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAFFAMIBwAOAEkNAA==.',
Ow='Owwmyballs:BAABNQAECn8dAAQdAAoKYwgPKwB5AQAdAAoKYwgPKwB5AQAIAAIKcQbjrwAvAAAJAAEK2QGkrgAZAAAAAA==.',
Oz='Ozygo:BAAANQAECgYIBgAAAA==.',
Pa='Pagamas:BAACNQAFFH8PAAMiAAcKoRPMGQCrAQAiAAYKGxLMGQCrAQAjAAEKvBnyDABWAAA1AAQKfygAAyIACgr1HrxXANACACIACgr1HrxXANACACMAAgqLEa03AF4AAAAA.Palandari:BAAANQAECgUICAAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Pandormu:BAAANQAECgYICQABNQAECgoKKQAnAKkWAA==.Panter:BAABNQAECn8pAAInAAoKqRasBQBiAgAnAAoKqRasBQBiAgAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAABNQAECn8YAAIcAAgKaQ3nIADdAAAcAAgKaQ3nIADdAAAAAA==.',
Ph='Phodoe:BAABNQAECn8oAAIPAAoK9QwfNAB6AQAPAAoK9QwfNAB6AQAAAA==.Phöebe:BAAANQAECgMIAQAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMICAAQAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAABNQAECn8XAAIiAAgKnRO3pgBEAQAiAAgKnRO3pgBEAQAAAA==.',
Po='Pokeureyeout:BAABNQAECn8nAAIDAAkKKwychACUAQADAAkKKwychACUAQAAAA==.Pole:BAAANQADCgUIBQABNQAECgkJNAAUADkcAA==.Port:BAAANQAECgUIBgAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECgoKLwAPAGQXAA==.Prodyne:BAABNQAECn86AAIiAAoKLhW/eQCKAgAiAAoKLhW/eQCKAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgoKJAACAK0aAA==.',
Qa='Qariwarmi:BAAANQAECgIIAgAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAFFAQICAABAG0dAA==.Quiettreader:BAABNQAECn9PAAIjAAoK7Bg7BQDDAgAjAAoK7Bg7BQDDAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAABNQAECn8XAAIIAAoKWBN0LQDjAQAIAAoKWBN0LQDjAQAAAA==.Rafiki:BAAANQAECgMIAwAAAA==.Raidboss:BAABNQAECn8WAAILAAoKTx3acQA+AgALAAoKTx3acQA+AgAAAA==.',
Re='Redeath:BAAANQAECgQIBgABNQAECgYIDAAQAAAAAA==.Redirect:BAAANQAECgUIBwABNQAECgYIDAAQAAAAAA==.Redonculous:BAABNQAECn84AAICAAoKFhiCHgBLAgACAAoKFhiCHgBLAgAAAA==.Redpool:BAACNQAFFH8IAAIhAAQKPwbrFQDtAAAhAAQKPwbrFQDtAAA1AAQKfzsAAiEACgpBEbFdAPYBACEACgpBEbFdAPYBAAAA.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8nAAIUAAcK7CBmGACZAgAUAAcK7CBmGACZAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgkJOAAKAHUjAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.Riggymortis:BAAANQAECgIIAgAAAA==.',
Ro='Ronx:BAABNQAECn8ZAAIjAAYK3xrNEgB7AQAjAAYK3xrNEgB7AQAAAA==.Roxxiloxxi:BAABNQAECn8sAAMHAAoKTwa5GACmAQAHAAkKfga5GACmAQAYAAUKoQPr2wCIAAAAAA==.',
Ru='Rudeboy:BAABNQAECn8sAAIYAAoKXhkJVQBXAgAYAAoKXhkJVQBXAgAAAA==.Rumchata:BAAANQAECgEIAQABNQAFFAMIBwAOAEkNAA==.Rushu:BAACNQAFFH8JAAIiAAQK+RCUJQDXAAAiAAQK+RCUJQDXAAA1AAQKfz0AAiIACgqdH9QWAOQCACIACgqdH9QWAOQCAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn87AAMVAAoKUxmaQABiAgAVAAoKUxmaQABiAgAFAAcKYQrx3wBbAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgcIEwAQAAAAAA==.Sahria:BAAANQAECgUICQAAAA==.Samlosco:BAABNQAECn8VAAISAAoKywQAEwDzAAASAAoKywQAEwDzAAAAAA==.Sapphpal:BAAANQAECgYICAABNQAECggIDQAQAAAAAA==.Sarhia:BAAANQAECgMIAwAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgAQAAAAAA==.',
Sc='Schizadin:BAABNQAECn80AAMEAAkKUyaPAACJAwAEAAkKUyaPAACJAwAFAAMKHgfbbQFxAAAAAA==.Schizology:BAAANQAECggIDgABNQAECgkJNAAEAFMmAA==.Schnoze:BAAANQAECgUIDgAAAA==.',
Se='Seabane:BAAANQAECggIEQAAAA==.Sebekuul:BAAANQADCgYIBgAAAQ==.Selfie:BAAANQADCgEIAQAAAA==.Selwenna:BAAANQADCgMIAwABNQAECggICQAQAAAAAA==.Selys:BAACNQAFFH8LAAIiAAUKVQovLgAfAQAiAAUKVQovLgAfAQA1AAQKf10AAyIACgrYHI0iAKoCACIACgrYHI0iAKoCACMAAgr1BoY5AFgAAAAA.Sepheturix:BAAANQAECgUICQAAAA==.Sephurik:BAACNQAFFH8tAAMiAAoKlBu+AgCMAgAiAAoKHxq+AgCMAgAjAAEKBAzcEABNAAA1AAQKf0sAAyIACgpsJFkrADkDACIACgqxIlkrADkDACMAAgpEH5gpAKoAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgcIHgAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCggIDgAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawman:BAAANQADCggICgAAAA==.Shawnalenee:BAABNQAECn8XAAICAAcKXxi+JQBAAQACAAcKXxi+JQBAAQAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiftingmoon:BAAANQAECgUIBAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.Shiv:BAAANQAECggIAgAAAA==.Shyft:BAAANQAECggICQAAAA==.',
Si='Sidisi:BAAANQAECggIDgABNQAECgoKKQAlAPYgAA==.Sikanda:BAABNQAECn8YAAMdAAkK4RtnIwC2AgAdAAkK4RtnIwC2AgAIAAIKuhRVjACEAAABNQAECgoKKQAlAPYgAA==.Silvea:BAABNQAECn8pAAINAAoK5BGuQAC6AQANAAoK5BGuQAC6AQAAAA==.Silvett:BAAANQAECgQIBQABNQAECgoKIAAmALMZAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn82AAICAAoKTSEzDQAYAwACAAoKTSEzDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAABNQAECn8jAAIJAAoKZAxlLgCKAQAJAAoKZAxlLgCKAQAAAA==.Sky:BAACNQAFFH8FAAIiAAMKfxeVQACxAAAiAAMKfxeVQACxAAA1AAQKfzIAAiIACgr4JOEVAHsDACIACgr4JOEVAHsDAAAA.Skyelf:BAABNQAECn8xAAIDAAoKfw2aZQDhAQADAAoKfw2aZQDhAQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECn81AAMhAAoKQxnOIADmAgAhAAoKQxnOIADmAgANAAEKxAOS/AAsAAAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAgIKAAoAOkdAA==.Solunara:BAAANQADCgUIBQABNQAECggIFwAFAGcXAA==.',
Sp='Spectrecles:BAACNQAFFH8HAAIOAAMKSQ0GEwDFAAAOAAMKSQ0GEwDFAAA1AAQKfzsAAw4ACgq8GCMbABsCAA4ACgq8GCMbABsCAA8AAQo8Bv58AB0AAAAA.Spectrecless:BAAANQAECgMIAwABNQAFFAMIBwAOAEkNAA==.Speez:BAABNQAECn8jAAIDAAgKFBPfegAZAgADAAgKFBPfegAZAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.Spèctral:BAAANQAECgQIBAABNQAECgoKIAAmALMZAA==.',
St='Stablehand:BAABNQAECn8hAAIDAAkKoxUmeACxAQADAAkKoxUmeACxAQAAAA==.Steve:BAACNQAFFH8oAAMNAAgK7BndBAChAQANAAcKmxbdBAChAQAoAAYKKxhSAQBoAQA1AAQKf0IABA0ACgqGIxwUAFEDAA0ACgpsIxwUAFEDACgABgpaIJ0UALIBACEAAgpiAgUkASkAAAAA.Stonedfel:BAABNQAECn8wAAITAAoKnhIUOQDqAQATAAoKnhIUOQDqAQAAAA==.Stonkbonkk:BAAANQAECgYIBgAAAA==.',
Su='Sunhoof:BAABNQAECn8XAAQFAAgKZxeIhAAeAgAFAAgKZxeIhAAeAgAEAAIKfRMUWgB0AAAVAAIKHAW2EQFTAAAAAA==.Supahotvile:BAACNQAFFH8GAAMKAAMKaQbPGwCKAAAKAAIKAQfPGwCKAAARAAIKYgT9DQBbAAA1AAQKfyYAAxEACgrWFRMsADgCABEACgpFDxMsADgCAAoABQqUGDZgAG0BAAAA.',
Sy='Syx:BAAANQAECgUICgAAAA==.',
['Sø']='Sørrow:BAABNQAECn8iAAIUAAoK5w3qNQCUAQAUAAoK5w3qNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8lAAMjAAoKgAfUFwA8AQAjAAoKVAfUFwA8AQAiAAYK9QG3ewHKAAAAAA==.Tabu:BAAANQAECgUIBwAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggIDQAAAA==.Tankoromma:BAAANQAECgYICwAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgUICwAQAAAAAA==.',
Te='Test:BAAANQAECggJAQAAAA==.',
Th='Tharil:BAAANQAECgQIBAAAAA==.Theblakmamba:BAAANQADCgIIBQAAAA==.Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAABNQAECn81AAMRAAoKkiOnBACLAwARAAoKkiOnBACLAwAKAAkKDRzWKQBHAgAAAA==.Thunderous:BAAANQADCgMIAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8PAAIDAAcKRiG/BwDSAQADAAcKRiG/BwDSAQA1AAQKfz8AAwMACgo7Jh8CAIMDAAMACgo7Jh8CAIMDACUAAQpAGVOBAEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgoKNgACAE0hAA==.',
To='Tomahawkchow:BAAANQAECggIEgAAAA==.Totemofpeace:BAAANQADCggIEAABNQAECgoKLwAPAGQXAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Treehorse:BAAANQAECgQICAAAAA==.Trentlock:BAACNQAFFH8VAAQYAAcK8AOFGwC8AAAYAAUKwgOFGwC8AAAnAAEKAABrEgA+AAAHAAIKNQShFAA+AAA1AAQKfz0ABBgACgo1Ho1SAF4CABgACgqTGI1SAF4CAAcABAoyIV0hAGYBACcAAwruG20aAJMAAAAA.Tristae:BAAANQAECgYICwAAAA==.',
Ts='Tsu:BAABNQAECn8hAAMKAAkKrSNzMgAeAgAKAAgK1SNzMgAeAgARAAcK3xsFMQAdAgAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgIIAgAAAA==.Unstablesha:BAAANQAECggIDwAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8UAAQdAAYKAhLXAwA3AQAdAAUKAhLXAwA3AQAIAAEKvAGwHwArAAAJAAEKAADUNgAlAAA1AAQKfzEAAh0ACgo0IrQVAAwDAB0ACgo0IrQVAAwDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQAECgIIAQAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vil:BAACNQAFFH8+AAICAAoKWyUiAAB2AwACAAoKWyUiAAB2AwA1AAQKfysAAgIACgrJJkcCAL0DAAIACgrJJkcCAL0DAAAA.Vilonus:BAABNQAECn8pAAIYAAoK0Q44ZwCNAQAYAAoK0Q44ZwCNAQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgoKNgACAE0hAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Volairis:BAAANQAECgYICAABNQAFFAYICgAcAKEQAA==.Voy:BAABNQAECn8eAAIGAAgKtwgZCQCvAQAGAAgKtwgZCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICAAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wa='Wallaroo:BAAANQADCgUIAgAAAA==.',
We='Weezy:BAABNQAECn8oAAMBAAoKKw+hTwDlAQABAAkKlw+hTwDlAQACAAkKJAkwOABkAQAAAA==.',
Wi='Williie:BAAANQAECggICwAAAA==.Withengar:BAAANQAECgcIBQAAAA==.',
Wu='Wuoshi:BAAANQAECgUICwAAAA==.Wuuzzyy:BAABNQAECn8oAAIOAAoKzRIlNwA0AgAOAAoKzRIlNwA0AgAAAA==.',
Xa='Xaliko:BAABNQAECn8YAAIYAAoKAhadYgCaAQAYAAoKAhadYgCaAQAAAA==.Xanbaran:BAABNQAECn86AAIBAAoKTQpRbgDTAQABAAoKTQpRbgDTAQAAAA==.Xandian:BAAANQAECgQIBAAAAA==.',
Xi='Xiphus:BAAANQAECgIIAwAAAA==.',
Xm='Xmarks:BAAANQAECggIDgAAAA==.',
Xy='Xyre:BAAANQABCgIIAgAAAA==.Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFH8SAAIhAAUKnCCaBwDeAQAhAAUKnCCaBwDeAQA1AAQKf00AAyEACgrFIiAQAEMDACEACgrFIiAQAEMDAA0AAQoAAO4iAUsAAAAA.',
Ya='Yahenni:BAABNQAECn8pAAMlAAoK9iBNFQC0AgAlAAgKRCBNFQC0AgADAAkKUBh1YwBOAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAABNQAECn8fAAIBAAkKYxHbQQAbAgABAAkKYxHbQQAbAgAAAA==.Yukki:BAABNQAECn8VAAMhAAkK3xH1NwAjAgAhAAkK3xH1NwAjAgANAAEK5gD9ZgEJAAAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAABNQAECn8oAAIUAAoKMhnCEAA+AgAUAAoKMhnCEAA+AgAAAA==.',
Ze='Zerk:BAABNQAECn8XAAILAAkKYQJ+AwHWAAALAAkKYQJ+AwHWAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
['Ða']='Ðavîs:BAAANQAECgEIAQABNQAECgoKMwAdAHQcAA==.',
['ßl']='ßlundetto:BAAANQAECgMIBAAAAA==.',
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
