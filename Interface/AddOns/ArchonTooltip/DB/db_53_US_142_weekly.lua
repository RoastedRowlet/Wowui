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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Shaman-Elemental','Rogue-Assassination','Evoker-Devastation','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','Druid-Restoration','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Evoker-Preservation','Monk-Brewmaster','Druid-Balance','Mage-Arcane','Mage-Frost','Evoker-Augmentation','Mage-Fire','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Restoration','Warlock-Affliction','Warlock-Demonology','Shaman-Enhancement',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abdulr:BAAANQAECggICAAAAA==.Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAACNQAFFH8PAAMBAAUKyxiKDgCnAQABAAUKyxiKDgCnAQACAAEKAAALDgAAAAA1AAQKfycAAwEACgrgHpMZAA8DAAEACgrgHpMZAA8DAAIAAwrID4QXAMsAAAE1AAUUBQgMAAMA6SQA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8sAAMEAAkKyiXOBABoAwAEAAkKyiXOBABoAwAFAAEKmhYajQFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECgkJLAAEAMolAA==.',
Aj='Ajunlucky:BAACNQAFFH8LAAIGAAUKhQ5iAAD+AAAGAAUKhQ5iAAD+AAA1AAQKfzIAAgYACgoCISQCACwDAAYACgoCISQCACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECgkJLAAEAMolAA==.Alexari:BAAANQAECgEIAQAAAA==.Alnilam:BAABNQAECn8rAAIHAAoKTRAdEgDlAQAHAAoKTRAdEgDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAAANQAECggIEQAAAA==.',
Ar='Arbys:BAAANQAECggIDgAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECn8uAAIIAAkKBSMVBQA6AwAIAAkKBSMVBQA6AwAAAA==.Armados:BAABNQAECn8bAAIJAAcKIRFSZADQAAAJAAcKIRFSZADQAAAAAA==.Aroxw:BAACNQAFFH8QAAIJAAUKBxNAEwCVAQAJAAUKBxNAEwCVAQA1AAQKfyEAAwkACQpQH+c9ANECAAkACQpQH+c9ANECAAoAAQoAABQoAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Athineana:BAAANQAECgQIBAAAAA==.Atlim:BAAANQAECgEIAgAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQAECgEIAQALAAAAAA==.',
Ba='Bad:BAAANQAECggICQAAAA==.Balfas:BAAANQADCgQIBAABNQAECgoKHgAMABEWAA==.Ballidur:BAAANQAECgMIBAABNQAFFAUIBQABAGgHAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn8rAAIKAAkK6CGaAACDAgAKAAkK6CGaAACDAgAAAA==.Bettyspready:BAABNQAECn8bAAINAAgKohPDLgApAgANAAgKohPDLgApAgAAAA==.',
Bi='Bigmanooshki:BAAANQAECgIIAwAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAABNQAECn8ZAAIOAAgKigSxHwBbAQAOAAgKigSxHwBbAQAAAA==.',
Bl='Blackfoot:BAABNQAECn8WAAIMAAoKJg+MKwAPAQAMAAoKJg+MKwAPAQAAAA==.Blankjr:BAAANQAECgYICAAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAUIDAADAOkkAA==.Blightmoss:BAAANQAECgQIBwABNQAECggIFgAFAGcXAA==.Blindpov:BAACNQAFFH8IAAIPAAMK1yCqAwALAQAPAAMK1yCqAwALAQA1AAQKfz0AAw8ACgpRJpABAOIDAA8ACgpRJpABAOIDABAABwrDHy0rAOgBAAAA.',
Bo='Bodyodyodied:BAAANQADCgQIBAAAAA==.Bonquiquie:BAAANQAECgUIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Borne:BAAANQAECgEIAQAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8dAAIPAAoKxxjGJQBvAgAPAAoKxxjGJQBvAgAAAA==.Breakerr:BAAANQAECgMIAwAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn8rAAIRAAgK5B/HBQB2AgARAAgK5B/HBQB2AgAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgMaABjAgAFAAgKIBgMaABjAgAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xmDBwD7AQAGAAcKlBaDBwD7AQADAAMKIBTLGwHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAISAAgKSwqdHQBpAQASAAgKSwqdHQBpAQAAAA==.Carmakazie:BAAANQADCggICAAAAA==.Cattle:BAABNQAECn8rAAITAAoK/Bd+DgB8AgATAAoK/Bd+DgB8AgAAAA==.Cazul:BAAANQAECgEIAgAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICAAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECggIEQAAAA==.',
Cl='Clawsofpeace:BAABNQAECn8YAAMUAAoK3BaIHgA6AgAUAAgK0haIHgA6AgATAAUKbQ1zEgD1AAAAAA==.',
Co='Constanse:BAAANQADCgYICwAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cr='Crewman:BAAANQAECgEIAQAAAA==.',
Cy='Cylic:BAABNQAECn8fAAIIAAgKiSIsCQDjAgAIAAgKiSIsCQDjAgAAAA==.Cyrùsdh:BAAANQAECgUIBQAAAA==.',
Da='Daddiestouch:BAABNQAECn8VAAMCAAcKMxo8HABjAgACAAcKMxo8HABjAgAVAAIKbgcdIwBPAAAAAA==.Dampundies:BAABNQAECn8YAAIWAAkKqRvyFgCVAgAWAAkKqRvyFgCVAgAAAA==.Dangerdream:BAABNQAECn8zAAQQAAoKVCFUCgA1AwAQAAoKVCFUCgA1AwAXAAcK4A7yCQDKAAAPAAEKFRXkjQBAAAAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgoKGwAQACoWAA==.Datsmywife:BAABNQAECn8sAAIYAAoKehIJDQBPAgAYAAoKehIJDQBPAgAAAA==.Davis:BAABNQAECn8iAAQZAAoKOBtEJQCqAgAZAAoKOBtEJQCqAgAaAAMKqBF3hQCaAAAbAAEKWBEOxQA+AAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.',
De='Deadasice:BAAANQADCgEIAQABNQADCgIIAgALAAAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn8yAAIcAAkKNR/fCgD1AgAcAAkKNR/fCgD1AgAAAA==.Derppriest:BAAANQADCggICAABNQAECgkJMgAcADUfAA==.Deviiarrc:BAACNQAFFH8SAAIcAAUKzBA7BABTAQAcAAUKzBA7BABTAQA1AAQKfzkAAhwACgpII94EAGADABwACgpII94EAGADAAAA.Devviarc:BAAANQADCggICwABNQAFFAUIEgAcAMwQAA==.',
Dl='Dlamb:BAAANQAECgUIEQABNQAECgYIDwALAAAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn8eAAMKAAoKBx9iBABxAQAKAAkKCCBiBABxAQAJAAMKBhjbDQHBAAAAAA==.',
Dr='Dracar:BAABNQAECn8oAAIFAAkKTCMdDwCPAwAFAAkKTCMdDwCPAwAAAA==.Dragoun:BAAANQAECgEIAQAAAA==.Draynor:BAAANQAECgEIAQAAAA==.Drmmrfist:BAABNQAECn8bAAIdAAgKURCTFACaAQAdAAgKURCTFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwippietiggs:BAABNQAECn8sAAIFAAoKbxuiSAC7AgAFAAoKbxuiSAC7AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAcIIAARAGUmAA==.Earthfeather:BAAANQAECgEIAgAAAA==.Easymac:BAAANQADCgIJAwABNQAECgoKHQAPAMcYAA==.',
Ed='Edhochuli:BAAANQADCgIIAgABNQAECgoKKwAeALgQAA==.',
Ee='Eetee:BAABNQAECn8WAAIMAAgKPQp2IQA2AQAMAAgKPQp2IQA2AQABNQAECggIJgAEAC8MAA==.',
Eg='Eggrolls:BAAANQAECgEIAQABNQAECgQICAALAAAAAA==.',
Eh='Ehemingway:BAABNQAECn8dAAIDAAYKCRazLwBiAQADAAYKCRazLwBiAQAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAUIDAADAOkkAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQAECgEIAQAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epicdragon:BAAANQADCgUIBQAAAA==.Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8bAAINAAkK+w1POgDqAQANAAkK+w1POgDqAQAAAA==.Ereye:BAABNQAECn8YAAIIAAcKHhaiHwDSAQAIAAcKHhaiHwDSAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAABNQAECn8iAAIfAAgKiglOTwAdAQAfAAgKiglOTwAdAQAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECggIJgAEAC8MAA==.Etengaged:BAABNQAECn8mAAIEAAgKLwwYEwDzAAAEAAgKLwwYEwDzAAAAAA==.Ethavoc:BAABNQAECn8VAAIbAAgKyQcacgAtAQAbAAgKyQcacgAtAQABNQAECggIJgAEAC8MAA==.',
Ev='Evrae:BAABNQAECn8gAAIIAAoKOBZCDwCGAgAIAAoKOBZCDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAABNQAECn8ZAAIBAAgKOAh0hQCGAQABAAgKOAh0hQCGAQAAAA==.Fatkow:BAAANQAECggIBQABNQAECgkJLgAZABImAA==.',
Fe='Fearthemoo:BAAANQADCgcIBwABNQAECgcIFQACADMaAA==.Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fellumir:BAAANQAECgIIAgAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH8mAAMfAAkKnB0lCQA1AgAfAAcKFRwlCQA1AgAgAAIKbSG5BADIAAA1AAQKfyQAAh8ACgoPIfJTANgCAB8ACgoPIfJTANgCAAAA.Finkler:BAABNQAECn8nAAMfAAkKnB7aewCGAgAfAAkKixvaewCGAgAgAAIK3yTNJADIAAABNQAFFAkJJgAfAJwdAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgYIDAABNQAECgoKGAAUANwWAA==.',
Fl='Flameshock:BAABNQAECn8sAAMgAAoKBw+xDwCtAQAgAAgKXg+xDwCtAQAfAAoKFA2dYAD8AAAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgoKNAAdAM8TAA==.',
Fr='Frankda:BAAANQADCgIIAgAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friarmj:BAAANQADCgQIBAAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAcKGwADAKAiAA==.Friendship:BAAANQADCgEIAQAAAA==.Frigidbeach:BAAANQAECgIIAQAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH8bAAMOAAkK3ReTAwC0AQAOAAUKMR6TAwC0AQAhAAYKkxRQBACbAQA1AAQKfx8AAw4ACQr3Ia8OAHMCAA4ACQoJHq8OAHMCACEAAwonJuIOAFQBAAAA.Gloreb:BAABNQAFFH8FAAIWAAUKXBeqCABXAQAWAAUKXBeqCABXAQAAAA==.',
Go='Goomi:BAAANQAECgcIEQAAAA==.Gordef:BAABNQAECn8ZAAMgAAgK3xZ3DADzAQAgAAgKOhZ3DADzAQAiAAYKPw+1BABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgEIAgAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEgAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Harrowing:BAABNQAECn9IAAIRAAoKsR4JGQAUAwARAAoKsR4JGQAUAwAAAA==.Haurt:BAABNQAECn8lAAIeAAgKhgruUgCPAQAeAAgKhgruUgCPAQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8cAAIbAAcKERppEQBWAQAbAAcKERppEQBWAQAAAA==.',
Hi='Hirokii:BAAANQAECgQIBAAAAA==.Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8dAAMRAAoKHhnaMACjAgARAAoKHhnaMACjAgAFAAcKzxxRbQDrAAAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQAECggICAAAAA==.Hotmess:BAABNQAECn8bAAIjAAgKlBjYAgAZAgAjAAgKlBjYAgAZAgAAAA==.',
Hu='Hurg:BAAANQAECgEIAQAAAA==.Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAAANQAECggIEwAAAA==.',
Il='Illindi:BAAANQADCgIIAQAAAA==.',
In='Insanê:BAABNQAECn8YAAMaAAkKQRU4LwAqAgAaAAkKbhQ4LwAqAgAbAAUKORB9MAC0AAABNQAECgkJLAAWAJ8TAA==.Insañe:BAABNQAECn8sAAMWAAkKnxORHwAzAgAWAAkKnxORHwAzAgAdAAEKkRC6MQAxAAAAAA==.Invi:BAAANQAECgcICwAAAA==.',
Ir='Irkellydonu:BAAANQAECgEIAQAAAA==.Ironbeef:BAAANQAECgYICQAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgALAAAAAA==.Jadengras:BAAANQAECgUICgAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAABNQAECn8VAAIeAAgKERbPFAA1AQAeAAgKERbPFAA1AQAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAABNQAECn8VAAIJAAgKrwjSzABbAQAJAAgKrwjSzABbAQAAAA==.',
['Jë']='Jësus:BAABNQAECn8oAAMVAAoKUBQACwCTAQABAAkK0hQXYgD6AQAVAAcK1REACwCTAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgYIFAAAAA==.Kalel:BAAANQAECgUIDAAAAA==.Karaman:BAAANQADCgEIAQAAAA==.Karmakazie:BAAANQAECgYICwAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn8lAAIDAAgK6RTXOwBBAQADAAgK6RTXOwBBAQAAAA==.Kazraghand:BAABNQAECn8zAAIGAAoKJA8rBQB2AgAGAAoKJA8rBQB2AgAAAA==.',
Ke='Keetanah:BAAANQAECgUICgAAAA==.Kei:BAACNQAFFH8HAAIQAAMKSg4WDgDGAAAQAAMKSg4WDgDGAAA1AAQKfyYAAxAACgodGdYXAJ4CABAACgodGdYXAJ4CAA8AAQrpDOiPADsAAAE1AAUUBQgGACQAaQIA.Kelsio:BAABNQAECn8jAAIDAAoKdxYZTwCBAgADAAoKdxYZTwCBAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAACNQAFFH8IAAIBAAMKDwbYDwC8AAABAAMKDwbYDwC8AAA1AAQKfy0AAgEACgphD2ZSACwCAAEACgphD2ZSACwCAAAA.',
Ki='Kikeo:BAABNQAFFH8GAAMkAAUKaQL4CQB4AAAkAAQKcgP4CQB4AAADAAIKVgCxHAAZAAAAAA==.Kinks:BAABNQAECn8bAAIPAAcKtxCPGwAZAQAPAAcKtxCPGwAZAQAAAA==.Kirkoth:BAAANQAECgMIAwAAAA==.',
Kn='Knuah:BAAANQADCgYIBgABNQAECgoKIQACALUTAA==.Knuts:BAAANQAECggIBwAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAACNQAFFH8NAAINAAgKexBMAAAkAgANAAgKexBMAAAkAgA1AAQKfyYAAg0ACgrDHOcKADMDAA0ACgrDHOcKADMDAAAA.Kowtagion:BAABNQAECn8uAAMZAAkKEibcBACoAwAZAAkKEibcBACoAwAbAAEKeiVQswBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8dAAQkAAoKdhfnMQC+AQAkAAgKjxfnMQC+AQADAAMKsxjKIwGxAAAGAAIKYAHhEQBLAAABNQAFFAMICAAfAPkQAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAAANQAECgMICgAAAA==.Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECn8pAAIlAAgKbR+rBACiAgAlAAgKbR+rBACiAgAAAA==.',
La='Laziza:BAAANQAECgEIAQAAAA==.',
Le='Leibowitzy:BAABNQAECn80AAMdAAoKzxOyBgAEAQAWAAoKLhIVJQD7AQAdAAYKWhSyBgAEAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Lenastin:BAAANQAECgQIBAABNQAFFAEIBgARAHomAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQABCgIIAgAAAA==.',
Lh='Lhehitman:BAABNQAECn8iAAIgAAkK3SCoAgA4AwAgAAkK3SCoAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgQICAAAAA==.Lightshax:BAABNQAECn8eAAIRAAgKtQ/ZcQDCAQARAAgKtQ/ZcQDCAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8eAAIXAAkKcwuaEQCXAQAXAAkKcwuaEQCXAQAAAA==.Liv:BAAANQAECgMIBAAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQAECgUICwAAAA==.Ludey:BAABNQAECn84AAMmAAoKmRkgBACiAgAmAAoKmRkgBACiAgAnAAEKVRQLOAFGAAAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgEIAgAAAA==.Lutray:BAABNQAECn8UAAISAAgKhiLuBgDyAgASAAgKhiLuBgDyAgAAAA==.',
Ma='Makaveleli:BAAANQAECgUIBgAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn8yAAIBAAoKHBLdSQBIAgABAAoKHBLdSQBIAgAAAA==.Marodd:BAABNQAECn8aAAICAAkKQyClFQCxAgACAAkKQyClFQCxAgAAAA==.Mashira:BAAANQAECgMIAgAAAA==.Mashîra:BAACNQAFFH8NAAIDAAYKvxzgAwAgAgADAAYKvxzgAwAgAgA1AAQKfywAAwMACgrcJI8GAKkDAAMACgqnJI8GAKkDACQABgr1HxUjADUCAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgQIBAAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn86AAQlAAoKGh4gHgDzAgAlAAoKGh4gHgDzAgAoAAEKAABqNQA6AAAMAAEKAAC0PwEuAAAAAA==.Mekuro:BAAANQAECgQICgAAAA==.Melky:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgUIBQAAAA==.Mewfasa:BAAANQADCggICAAAAA==.Meyday:BAAANQAECgEIAQAAAA==.',
Mi='Mia:BAABNQAECn8UAAIQAAkKpBvXEQDdAgAQAAkKpBvXEQDdAgAAAA==.Migraine:BAAANQADCgQIBAAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyA6TACwAgAFAAgKOyA6TACwAgAAAA==.Minasuzune:BAABNQAECn8TAAMDAAgKVx+naABCAgADAAgKVx+naABCAgAkAAIK9AzTdQBkAAAAAA==.Miney:BAAANQADCgYICQAAAA==.Minus:BAAANQAECgEIAQAAAA==.',
Mo='Moller:BAAANQAECgEIAQAAAA==.Moondotter:BAAANQAECgQIBAABNQAECgQIBgALAAAAAA==.Moongoddess:BAAANQAECgQIBgAAAA==.Moonslayer:BAABNQAECn8ZAAIeAAgKgA1QSQDDAQAeAAgKgA1QSQDDAQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAYIDQADAL8cAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAYIDQADAL8cAA==.Måshîrå:BAAANQAECgYICgABNQAFFAYIDQADAL8cAA==.',
Na='Nakor:BAABNQAECn8gAAIfAAcKYgTtnACQAAAfAAcKYgTtnACQAAAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECn8bAAIKAAcKLBJwDwC1AQAKAAcKLBJwDwC1AQAAAA==.Natalie:BAAANQAECggIAQAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAAANQAECgYIDgAAAA==.Nefeli:BAABNQAECn8wAAIhAAoKYBVxBQCOAgAhAAoKYBVxBQCOAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAABNQAECn8VAAIhAAgKnAELCwBfAAAhAAgKnAELCwBfAAAAAA==.Nestia:BAAANQAECgUICwAAAA==.Never:BAACNQAFFH8JAAMHAAMKDBgMDQCdAAAHAAIKIBUMDQCdAAAnAAIKexicEwB9AAA1AAQKfy4AAycACgrtHn45AKcCACcACQpBHn45AKcCAAcABQpHHjgdAIQBAAAA.',
Ni='Nightshade:BAABNQAECn8xAAIDAAkKVhvVLwDdAgADAAkKVhvVLwDdAgAAAA==.Nimbus:BAAANQAECggICgAAAA==.Nix:BAAANQAECgEIAQAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8dAAIEAAgKkxPVHQD7AQAEAAgKkxPVHQD7AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAABNQAECn8WAAINAAgKsAWYUwBuAQANAAgKsAWYUwBuAQAAAA==.',
On='Oniana:BAABNQAECn8mAAIkAAgKFQpEEwDrAAAkAAgKFQpEEwDrAAAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAECgoKKwAeALgQAA==.',
Ow='Owwmyballs:BAAANQAECgUICAAAAA==.',
Oz='Ozygo:BAAANQAECgIIAgAAAA==.',
Pa='Pagamas:BAACNQAFFH8NAAIfAAUKkRbMGQCrAQAfAAUKkRbMGQCrAQA1AAQKfyUAAx8ACgq1HrxXANACAB8ACgq1HrxXANACACAAAgqLEa03AF4AAAAA.Palandari:BAAANQAECgUICAAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Pandormu:BAAANQAECgQIBAABNQAECgoKFQAmABMRAA==.Panter:BAABNQAECn8VAAImAAoKExEwAgBzAQAmAAoKExEwAgBzAQAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAAANQAECgYIDQAAAA==.',
Ph='Phodoe:BAABNQAECn8bAAIUAAgKbwofNAB6AQAUAAgKbwofNAB6AQAAAA==.Phöebe:BAAANQAECgIIAgAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMICAALAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAAANQAECgUICwAAAA==.',
Po='Pokeureyeout:BAABNQAECn8XAAIDAAYKfQ/CWwD1AAADAAYKfQ/CWwD1AAAAAA==.Port:BAAANQAECgUIBgABNQAECgYIDgALAAAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECgoKGAAUANwWAA==.Prodyne:BAABNQAECn85AAIfAAoKLhW/eQCKAgAfAAoKLhW/eQCKAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgcIFQACADMaAA==.',
Qa='Qariwarmi:BAAANQAECgIIAgAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAECgoKPQABAI0jAA==.Quiettreader:BAABNQAECn80AAIgAAoKYxc7BQDDAgAgAAoKYxc7BQDDAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAAANQAECgcIDQAAAA==.Rafiki:BAAANQAECgMIAwAAAA==.Raidboss:BAAANQAECgcIEAAAAA==.',
Re='Redeath:BAAANQAECgQIBgABNQAECgYICAALAAAAAA==.Redirect:BAAANQAECgIIAgABNQAECgYICAALAAAAAA==.Redonculous:BAABNQAECn8hAAICAAoKtROCHgBLAgACAAoKtROCHgBLAgAAAA==.Redpool:BAABNQAECn8uAAIlAAoKgQ6xXQD2AQAlAAoKgQ6xXQD2AQAAAA==.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8nAAIQAAcK7CBmGACZAgAQAAcK7CBmGACZAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgkJLgAIAAUjAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.',
Ro='Ronx:BAAANQAECgcIDgAAAA==.Roxxiloxxi:BAABNQAECn8oAAMHAAoK/gW5GACmAQAHAAkKfga5GACmAQAnAAUKVgL8dgCVAAAAAA==.',
Ru='Rudeboy:BAABNQAECn8rAAInAAoKyhgJVQBXAgAnAAoKyhgJVQBXAgAAAA==.Rumchata:BAAANQAECgEIAQABNQAECgoKKwAeALgQAA==.Rushu:BAACNQAFFH8IAAIfAAMK+RCSDgDpAAAfAAMK+RCSDgDpAAA1AAQKfyoAAh8ACgquGHtcAMcCAB8ACgquGHtcAMcCAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn82AAMRAAoKYRd7FACvAQARAAoKYRd7FACvAQAFAAcKYQrx3wBbAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgcIEgALAAAAAA==.Sahria:BAAANQAECgYIBQAAAA==.Samlosco:BAAANQAECggIDgAAAA==.Sapphpal:BAAANQAECgYICAABNQAECggICgALAAAAAA==.Sarhia:BAAANQAECgQIAwAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgALAAAAAA==.',
Sc='Schizology:BAAANQAECgEIAQAAAA==.Schnoze:BAAANQAECgQIDgAAAA==.',
Se='Seabane:BAAANQAECgEIAQAAAA==.Sebekuul:BAAANQADCgYIBgAAAQ==.Selys:BAACNQAFFH8IAAIfAAQKkAovLgAfAQAfAAQKkAovLgAfAQA1AAQKfzgAAx8ACgqmEJo0AFYBAB8ACgqmEJo0AFYBACAAAgr1BoY5AFgAAAAA.Sepheturix:BAAANQAECgUICQAAAA==.Sephurik:BAACNQAFFH8TAAMfAAUKvBLFKQA9AQAfAAUKvBLFKQA9AQAgAAEKXQBTFQBBAAA1AAQKf0EAAx8ACgq4I1krADkDAB8ACgo5IlkrADkDACAAAgpTHpgpAKoAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgcICAAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCggIDQAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAAANQAECgYIDwAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiftingmoon:BAAANQABCgYIBQAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.Shiv:BAAANQAECggIAgAAAA==.Shyft:BAAANQAECgUIBQAAAA==.',
Si='Sidisi:BAAANQAECgcICQABNQAECgoKIgAkAF4gAA==.Sikanda:BAABNQAECn8XAAMZAAkK4RtnIwC2AgAZAAkK4RtnIwC2AgAaAAIKuhRVjACEAAABNQAECgoKIgAkAF4gAA==.Silvea:BAABNQAECn8dAAIMAAgK+xGUIgAxAQAMAAgK+xGUIgAxAQAAAA==.Silvett:BAAANQAECgEIAQAAAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn8qAAICAAoKxx0zDQAYAwACAAoKxx0zDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAAANQAECgYIBwAAAA==.Sky:BAABNQAECn8sAAIfAAoKhSPhFQB7AwAfAAoKhSPhFQB7AwAAAA==.Skyelf:BAABNQAECn8kAAIDAAoKagzEjQDuAQADAAoKagzEjQDuAQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECn8xAAMlAAkKORvOIADmAgAlAAkKORvOIADmAgAMAAEKxAObmAAvAAAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAcIJwAoADUiAA==.Solunara:BAAANQADCgUIBQABNQAECggIFgAFAGcXAA==.',
Sp='Spectrecles:BAABNQAECn8rAAIeAAoKuBBLMwBLAgAeAAoKuBBLMwBLAgAAAA==.Spectrecless:BAAANQAECgMIAwABNQAECgoKKwAeALgQAA==.Speez:BAABNQAECn8cAAIDAAgK8BLfegAZAgADAAgK8BLfegAZAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.',
St='Stablehand:BAAANQAECgUIEgAAAA==.Steve:BAACNQAFFH8RAAIMAAQKJAlTEQBXAQAMAAQKJAlTEQBXAQA1AAQKfzgAAwwACgqNIhwUAFEDAAwACgqNIhwUAFEDACUAAgr/AQUkASkAAAAA.Stonedfel:BAABNQAECn8nAAIPAAoKJxEUOQDqAQAPAAoKJxEUOQDqAQAAAA==.',
Su='Sunhoof:BAABNQAECn8WAAQFAAgKZxeIhAAeAgAFAAgKZxeIhAAeAgAEAAIKfRMUWgB0AAARAAIKHAW2EQFTAAAAAA==.Supahotvile:BAABNQAECn8eAAMNAAoKPBATLAA4AgANAAoKRQ8TLAA4AgAIAAIKOxK0MwCJAAAAAA==.',
Sy='Syx:BAAANQAECgEIAgAAAA==.',
['Sø']='Sørrow:BAABNQAECn8dAAIQAAkKIwzqNQCUAQAQAAkKIwzqNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8dAAMgAAgKQQfUFwA8AQAgAAgKBQfUFwA8AQAfAAYK9QG3ewHKAAAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggIDQAAAA==.Tankoromma:BAAANQADCgYICAAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgQIDAALAAAAAA==.',
Te='Ten:BAAANQAECgIIAgAAAA==.Test:BAAANQAECggJAQAAAA==.',
Th='Theblakmamba:BAAANQADCgEIAQAAAA==.Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Theo:BAAANQAECgIIAgAAAA==.Thetaint:BAABNQAECn8pAAMNAAoKkiOnBACLAwANAAoKkiOnBACLAwAIAAIKEhiEMQCUAAAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8MAAIDAAUK6SS/BwDSAQADAAUK6SS/BwDSAQA1AAQKfyIAAwMACgriItIVAEQDAAMACgriItIVAEQDACQAAQpAGVOBAEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgoKKgACAMcdAA==.',
To='Tomahawkchow:BAAANQAECgMIAwAAAA==.Totemofpeace:BAAANQADCggIEAABNQAECgoKGAAUANwWAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Treehorse:BAAANQAECgQIBAAAAA==.Trentlock:BAACNQAFFH8MAAQHAAUKaQSaAwCHAAAnAAMK0QSdNQCIAAAHAAIKNQSaAwCHAAAmAAEKAABrEgA+AAA1AAQKfy8AAycACgocGY1SAF4CACcACgoCE41SAF4CAAcABAoyIV0hAGYBAAAA.Tristae:BAAANQAECgYICQAAAA==.',
Ts='Tsu:BAABNQAECn8WAAMIAAkKBx3gFgAlAQANAAcK/hoFMQAdAgAIAAYKZyHgFgAlAQAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgIIAgAAAA==.Unstablesha:BAAANQAECgcICwAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8LAAMZAAUKEBPqEQDtAAAZAAQKEBPqEQDtAAAbAAEKAADUNgAlAAA1AAQKfy4AAhkACgpkILQVAAwDABkACgpkILQVAAwDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQAECgEIAQAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vigiles:BAAANQAECgEIAQAAAA==.Vil:BAACNQAFFH8gAAICAAkKvhu3AAD7AgACAAkKvhu3AAD7AgA1AAQKfykAAgIACgq6JkcCAL0DAAIACgq6JkcCAL0DAAAA.Vilonus:BAABNQAECn8gAAInAAgKdhA1lAC0AQAnAAgKdhA1lAC0AQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgoKKgACAMcdAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Volairis:BAAANQAECgYICAABNQAFFAQIBQAYACoJAA==.Voy:BAABNQAECn8cAAIGAAgKlwgZCQCvAQAGAAgKlwgZCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICAAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
We='Weezy:BAABNQAECn8fAAMCAAoKpwswOABkAQACAAkKJAkwOABkAQABAAcK7AZerwAIAQAAAA==.',
Wi='Williie:BAAANQAECgcICwAAAA==.Withengar:BAAANQAECgYIBQAAAA==.',
Wu='Wuoshi:BAAANQAECgQIDAAAAA==.Wuuzzyy:BAABNQAECn8jAAIeAAkK4xIlNwA0AgAeAAkK4xIlNwA0AgAAAA==.',
Xa='Xaliko:BAAANQAECgcIDAAAAA==.Xanbaran:BAABNQAECn85AAIBAAoKKApRbgDTAQABAAoKKApRbgDTAQAAAA==.',
Xi='Xiphus:BAAANQAECgIIAwAAAA==.',
Xm='Xmarks:BAAANQAECgEIAQAAAA==.',
Xy='Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFH8MAAIlAAUKnCCaBwDeAQAlAAUKnCCaBwDeAQA1AAQKfzIAAyUACgrFIiAQAEMDACUACgrFIiAQAEMDAAwAAQoAAO4iAUsAAAAA.',
Ya='Yahenni:BAABNQAECn8iAAMkAAoKXiBNFQC0AgAkAAgKFx5NFQC0AgADAAkKUBh1YwBOAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAAANQAECggIDgAAAA==.Yukki:BAAANQAECggIBgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAABNQAECn8bAAIQAAoKKha8CgBoAQAQAAoKKha8CgBoAQAAAA==.',
Ze='Zerk:BAABNQAECn8XAAIJAAkKYQJ+AwHWAAAJAAkKYQJ+AwHWAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
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
