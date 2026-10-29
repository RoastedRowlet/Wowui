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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','Druid-Restoration','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','Shaman-Restoration','Monk-Brewmaster','Druid-Balance','Mage-Arcane','Mage-Frost','Evoker-Augmentation','Mage-Fire','Monk-Mistweaver','Warlock-Affliction','Hunter-Marksmanship','Warlock-Demonology',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abdulr:BAAANQAECggICAAAAA==.Abused:BAAANQADCgUIBwAAAA==.',
Ad='Adelaide:BAACNQAFFH8VAAMBAAYK3hiKDgCnAQABAAYK3hiKDgCnAQACAAQKWgQjCQC3AAA1AAQKfygAAwEACgrgHpMZAA8DAAEACgrgHpMZAA8DAAIABArOER8gAAcBAAE1AAUUBggNAAMAUSAA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8sAAMEAAkKyiXOBABoAwAEAAkKyiXOBABoAwAFAAEKmhYajQFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECgkJLAAEAMolAA==.',
Aj='Ajunlucky:BAACNQAFFH8NAAIGAAUK9hCZAADnAAAGAAUK9hCZAADnAAA1AAQKfzYAAgYACgqPISQCACwDAAYACgqPISQCACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECgkJLAAEAMolAA==.Alexari:BAAANQAECgEIAgAAAA==.Alnilam:BAABNQAECn8zAAIHAAoKshAdEgDlAQAHAAoKshAdEgDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
An='Andalu:BAAANQAECgEIAgAAAA==.',
Ap='Appypie:BAABNQAECn8UAAMIAAoKDQf/WwA5AQAIAAcKlQf/WwA5AQAJAAoKaQQLeAAXAQAAAA==.',
Ar='Arbys:BAAANQAECggIDwAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECn8yAAIKAAkKdSMVBQA6AwAKAAkKdSMVBQA6AwAAAA==.Armados:BAABNQAECn8mAAILAAoKHg6BXQBqAQALAAoKHg6BXQBqAQAAAA==.Aroxw:BAACNQAFFH8RAAILAAYKYw/ZCwAIAQALAAYKYw/ZCwAIAQA1AAQKfycAAwsACQp0IOc9ANECAAsACQp0IOc9ANECAAwAAQoAABQoAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Athineana:BAAANQAECgQIBQAAAA==.Atlim:BAAANQAECgIIBQAAAA==.',
Ay='Aylinn:BAAANQAECgYIEgAAAA==.Aylira:BAAANQAECgEIAwAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQAECgEIAgANAAAAAA==.',
Ba='Bad:BAAANQAECggICQAAAA==.Balfas:BAAANQADCgQIBAABNQAECgoKKAAOAFkXAA==.Ballidur:BAAANQAFFAEIAQABNQAECggIFQABAIscAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn84AAIMAAoKVyHMAQDeAgAMAAoKVyHMAQDeAgAAAA==.Bettyspready:BAABNQAECn8hAAIPAAgKohPDLgApAgAPAAgKohPDLgApAgAAAA==.',
Bi='Bigmanooshki:BAAANQAECgIIBwAAAA==.Bigpoppapump:BAAANQAECgYJDwAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAABNQAECn8dAAIQAAkKKAWxHwBbAQAQAAkKKAWxHwBbAQAAAA==.',
Bl='Blackfoot:BAABNQAECn8WAAIRAAoKJg8qdgC/AQARAAoKJg8qdgC/AQAAAA==.Blankjr:BAAANQAECgUIDAAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAYIDQADAFEgAA==.Blightmoss:BAAANQAECgQIBwABNQAECggIFwAFAGcXAA==.Blindpov:BAACNQAFFH8JAAISAAQK1yDjBgD6AAASAAQK1yDjBgD6AAA1AAQKfz8AAxIACgpRJpABAOIDABIACgpRJpABAOIDABMABwrDHy0rAOgBAAAA.',
Bo='Bodyodyodied:BAAANQAECgEIAgAAAA==.Bonquiquie:BAAANQAECgUIBQAAAA==.Boop:BAAANQAECgEIAQAAAA==.Borne:BAAANQAECgEIAwAAAA==.Bouberry:BAAANQAECgEIBgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8kAAISAAoKOhybEwAaAgASAAoKOhybEwAaAgAAAA==.Breakerr:BAAANQAECgMIBQAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn80AAIUAAoKwx+rCQAtAwAUAAoKwx+rCQAtAwAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgMaABjAgAFAAgKIBgMaABjAgAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xmDBwD7AQAGAAcKlBaDBwD7AQADAAMKIBTLGwHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAwAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAIVAAgKSwqdHQBpAQAVAAgKSwqdHQBpAQAAAA==.Carmakazie:BAAANQADCggICAAAAA==.Cattle:BAABNQAECn8xAAIWAAoKcRl+DgB8AgAWAAoKcRl+DgB8AgAAAA==.Cazul:BAAANQAECgcICgAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICwAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECggIEwAAAA==.',
Cl='Clawsofpeace:BAABNQAECn8jAAMXAAoKZBeIHgA6AgAXAAgK0haIHgA6AgAWAAgKvhG+GABIAQAAAA==.',
Co='Constanse:BAAANQAECgEIAgAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cr='Crewman:BAAANQAECgEIAQAAAA==.Crosshairs:BAAANQADCggICAABNQAECgoKPQATAJIiAA==.',
Cy='Cylic:BAABNQAECn8fAAIKAAgKiSIsCQDjAgAKAAgKiSIsCQDjAgAAAA==.Cyrùsdh:BAAANQAECgYIBgAAAA==.',
Da='Daddiestouch:BAABNQAECn8eAAMCAAgK2Rg8HABjAgACAAgK2Rg8HABjAgAYAAIKbgcdIwBPAAAAAA==.Dampundies:BAABNQAECn8YAAIZAAkKqRvyFgCVAgAZAAkKqRvyFgCVAgAAAA==.Dangerdream:BAABNQAECn89AAQTAAoKkiJUCgA1AwATAAoKkiJUCgA1AwAaAAcK4A4WEgC4AAASAAEKFRXkjQBAAAAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAgAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgoKHQATACoWAA==.Datsmywife:BAABNQAECn8zAAIbAAoKFxMOCQC2AQAbAAoKFxMOCQC2AQAAAA==.Davis:BAABNQAECn8qAAQcAAoKGhxEJQCqAgAcAAoKOBtEJQCqAgAJAAgKpQ03JQBtAQAIAAMKqBF3hQCaAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.',
De='Deadasice:BAAANQADCgEIAQABNQADCgIIAgANAAAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn83AAIdAAoKeh/fCgD1AgAdAAoKeh/fCgD1AgAAAA==.Derppriest:BAAANQADCggICAABNQAECgoKNwAdAHofAA==.Deviiarrc:BAACNQAFFH8XAAIdAAUK3hRNBgBiAQAdAAUK3hRNBgBiAQA1AAQKfz0AAh0ACgpII94EAGADAB0ACgpII94EAGADAAAA.Devviarc:BAAANQADCggICwABNQAFFAUIFwAdAN4UAA==.',
Di='Dibgargargad:BAABNQAECn8YAAIJAAoKZBeWEQAtAgAJAAoKZBeWEQAtAgAAAA==.',
Dl='Dlamb:BAABNQAECn8VAAIeAAcK3hv3fACVAQAeAAcK3hv3fACVAQAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn8nAAQMAAoKQyAOBwC9AQAMAAkKcSEOBwC9AQALAAMKBhjbDQHBAAAVAAMKhxChJgBjAAAAAA==.',
Dr='Dracar:BAABNQAECn8vAAIFAAoKIB8dDwCPAwAFAAoKIB8dDwCPAwAAAA==.Draennor:BAAANQAECgYIBwAAAA==.Dragoun:BAAANQAECgUIBgAAAA==.Draynor:BAAANQAECgEIAgAAAA==.Drmmrfist:BAABNQAECn8bAAIfAAgKURCTFACaAQAfAAgKURCTFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwippietiggs:BAABNQAECn81AAIFAAoKCB6iSAC7AgAFAAoKCB6iSAC7AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAECgcICAANAAAAAA==.Earthfeather:BAAANQAECgEIBgAAAA==.Easymac:BAAANQADCgIJAwABNQAECgoKJAASADocAA==.',
Ed='Edhochuli:BAAANQADCgIIAgABNQAFFAIIBgAgALgSAA==.',
Ee='Eetee:BAABNQAECn8ZAAMRAAgKPQqqUgAVAQARAAgKPQqqUgAVAQAeAAIKfRh+lwCOAAABNQAECgoKKgAEAHMMAA==.',
Eg='Eggon:BAAANQADCgEIAQAAAA==.Eggrolls:BAAANQAECgEIAQABNQAECgQICAANAAAAAA==.',
Eh='Ehemingway:BAABNQAECn8mAAIDAAkKthMjLQAsAgADAAkKthMjLQAsAgAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAYIDQADAFEgAA==.',
Em='Emberstone:BAAANQAECgQIBQAAAA==.Emoux:BAAANQAECgEIAQAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epicdragon:BAAANQADCgUIBQAAAA==.Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8eAAIPAAkKbQ9POgDqAQAPAAkKbQ9POgDqAQAAAA==.Ereye:BAABNQAECn8YAAIKAAcKHhaiHwDSAQAKAAcKHhaiHwDSAQAAAA==.',
Es='Esstina:BAAANQAECgIIAwAAAA==.Estuku:BAABNQAECn8iAAIhAAgKigmznwAGAQAhAAgKigmznwAGAQAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECgoKKgAEAHMMAA==.Etengaged:BAABNQAECn8qAAIEAAoKcwzLEwBsAQAEAAoKcwzLEwBsAQAAAA==.Ethavoc:BAABNQAECn8YAAIJAAgK0wcacgAtAQAJAAgK0wcacgAtAQABNQAECgoKKgAEAHMMAA==.',
Ev='Evrae:BAABNQAECn8iAAIKAAoKOBZCDwCGAgAKAAoKOBZCDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcICgAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAABNQAECn8dAAIBAAkK1Ql0hQCGAQABAAkK1Ql0hQCGAQAAAA==.Fatkow:BAAANQAECggIDAABNQAECgkJLgAcABImAA==.',
Fe='Fearthemoo:BAAANQADCgcIBwABNQAECggIHgACANkYAA==.Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fellumir:BAAANQAECgIIAgAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH8sAAMhAAkKER4lCQA1AgAhAAcKNRwlCQA1AgAiAAIKuiJDAgDSAAA1AAQKfyUAAiEACgoPIfJTANgCACEACgoPIfJTANgCAAAA.Finkler:BAABNQAECn8nAAMhAAkKnB7aewCGAgAhAAkKixvaewCGAgAiAAIK3yTNJADIAAABNQAFFAkJLAAhABEeAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgYIDAABNQAECgoKIwAXAGQXAA==.',
Fl='Flameshock:BAABNQAECn8yAAMiAAoKmA+xDwCtAQAhAAoKpQ0ZswAdAgAiAAgKXg+xDwCtAQAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgoKPgAZAH4UAA==.',
Fr='Frankda:BAAANQADCgIIAgAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friarmj:BAAANQADCgUICAAAAA==.Friendshaped:BAAANQAECgMIBAABNQAFFAcKGwADAKAiAA==.Friendship:BAAANQADCgEIAQAAAA==.Frigidbeach:BAAANQAECgIIBQAAAA==.Frivolous:BAAANQAECgEIAQAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH8kAAMjAAkKaRsgAQAXAgAjAAgKdxggAQAXAgAQAAUKMR6TAwC0AQA1AAQKfyAAAxAACgrYIa8OAHMCABAACQoJHq8OAHMCACMABAreJOIOAFQBAAAA.Gloreb:BAACNQAFFH8FAAIZAAUKXBeqCABXAQAZAAUKXBeqCABXAQA1AAQKfxUAAhkACAqGHYMPAPABABkACAqGHYMPAPABAAAA.',
Go='Goomi:BAABNQAECn8ZAAIRAAgKJg7kRgA6AQARAAgKJg7kRgA6AQAAAA==.Gordef:BAABNQAECn8dAAMiAAkKxBV3DADzAQAiAAkKNhV3DADzAQAkAAYKPw+1BABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMICQAAAA==.Grismago:BAAANQAECgYICAAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEwAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBgAAAA==.Haranor:BAAANQAECgMIBQAAAA==.Harrowing:BAABNQAECn9OAAIUAAoKsR4JGQAUAwAUAAoKsR4JGQAUAwAAAA==.Haurt:BAABNQAECn8sAAIgAAgKrAqbNAD7AAAgAAgKrAqbNAD7AAAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8eAAIJAAcKVhqEKABXAQAJAAcKVhqEKABXAQAAAA==.',
Hi='Hirokii:BAAANQAECgQICQAAAA==.Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8hAAMUAAoKHhnaMACjAgAUAAoKHhnaMACjAgAFAAgKWxw2iABAAQAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQAECgcIEQAAAA==.Hotmess:BAABNQAECn8dAAIlAAkK3RibCABDAgAlAAkK3RibCABDAgAAAA==.',
Hu='Hurg:BAAANQAECggICQAAAA==.Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAABNQAECn8eAAIeAAoKXSKhAwCtAwAeAAoKXSKhAwCtAwAAAA==.',
Il='Illindi:BAAANQADCgQIBAAAAA==.',
In='Insanê:BAABNQAECn8dAAMIAAkKQRU4LwAqAgAIAAkKbhQ4LwAqAgAJAAUKwBHGUwCcAAABNQAECgkJLAAZAJ8TAA==.Insañe:BAABNQAECn8sAAMZAAkKnxORHwAzAgAZAAkKnxORHwAzAgAfAAEKkRC6MQAxAAAAAA==.Instinkts:BAAANQAECgEIAQAAAA==.Invi:BAAANQAECgYIDwAAAA==.',
Ir='Irina:BAAANQAECgIIAgABNQAECgoKOgAmAJkZAA==.Irkellydonu:BAAANQAECgEIAQAAAA==.Ironbeef:BAAANQAECgYIDwAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQAECgEIAQABNQAECgQIDQANAAAAAA==.Jadengras:BAAANQAECgUIEwAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAABNQAECn8dAAIgAAoK+BfTEAA7AgAgAAoK+BfTEAA7AgAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAABNQAECn8VAAILAAgKrwjSzABbAQALAAgKrwjSzABbAQAAAA==.',
['Jë']='Jësus:BAABNQAECn8yAAMYAAoK/BYACwCTAQABAAkKVxgALgALAgAYAAgKaxMACwCTAQAAAA==.',
Ka='Kalandaelis:BAAANQAECgEIAgAAAA==.Kaldren:BAAANQADCgcIFQAAAA==.Kalel:BAAANQAECgUIEAAAAA==.Karaman:BAAANQADCgIIAwAAAA==.Karmakazie:BAAANQAECgUIDgAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn8tAAIDAAkKrBbUOwDyAQADAAkKrBbUOwDyAQAAAA==.Kazraghand:BAABNQAECn9BAAIGAAoKrxAmAwALAgAGAAoKrxAmAwALAgAAAA==.',
Ke='Keetanah:BAAANQAECgUIEwAAAA==.Kei:BAACNQAFFH8HAAITAAMKSg4WDgDGAAATAAMKSg4WDgDGAAA1AAQKfyYAAxMACgodGdYXAJ4CABMACgodGdYXAJ4CABIAAQrpDOiPADsAAAE1AAUUBggMAAMAcQsA.Kelsio:BAABNQAECn8tAAIDAAoKPxjYJwBCAgADAAoKPxjYJwBCAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAwAAAA==.',
Kh='Kharos:BAACNQAFFH8LAAIBAAQKaQe6EgAGAQABAAQKaQe6EgAGAQA1AAQKfzEAAgEACgq0D2ZSACwCAAEACgq0D2ZSACwCAAAA.',
Ki='Kikeo:BAACNQAFFH8MAAMDAAYKcQubEwCoAAADAAMKmw6bEwCoAAAnAAQKSAhjDgCEAAA1AAQKfxQAAycACQpWGMEbACMBACcACAqhFsEbACMBAAMABwocFhGKAB0BAAAA.Kinks:BAABNQAECn8hAAISAAoK0g7pHACyAQASAAoK0g7pHACyAQAAAA==.Kirkoth:BAAANQAECgMIBAAAAA==.',
Kn='Knuah:BAAANQAECgMIAwABNQAECgoKLAACALMUAA==.Knuts:BAAANQAECggIEgAAAA==.',
Ko='Korialz:BAAANQAECgEIAgAAAA==.Kovah:BAACNQAFFH8UAAIPAAgK0xlwAABGAgAPAAgK0xlwAABGAgA1AAQKfy8AAg8ACgoNIGwDAL0CAA8ACgoNIGwDAL0CAAAA.Kowtagion:BAABNQAECn8uAAMcAAkKEibcBACoAwAcAAkKEibcBACoAwAJAAEKeiVQswBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8mAAQDAAoKpBoWVACgAQAnAAkKmhjnMQC+AQADAAYKHhsWVACgAQAGAAIKYAHhEQBLAAABNQAFFAQICQAhAPkQAA==.Krostikard:BAAANQAECgQIBQAAAA==.',
Ku='Kumquat:BAAANQADCgYICQAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAAANQAECgUIDwAAAA==.Kyruutos:BAAANQAECgMICwAAAA==.',
['Kí']='Kítkat:BAABNQAECn8qAAIeAAkKsx1WEQDFAgAeAAkKsx1WEQDFAgAAAA==.',
La='Laziza:BAAANQAECgUIBgAAAA==.',
Le='Leibowitzy:BAABNQAECn8+AAMZAAoKfhQVJQD7AQAZAAoK3hIVJQD7AQAfAAYK5xT4CwAKAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAwAAAA==.Lenastin:BAAANQAECgcIDAABNQAFFAEIBwAUAHomAA==.Letra:BAAANQADCgMIAwAAAA==.',
Lh='Lhehitman:BAABNQAECn8lAAIiAAkK3SCoAgA4AwAiAAkK3SCoAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgUIDQAAAA==.Lightshax:BAABNQAECn8eAAIUAAgKtQ/ZcQDCAQAUAAgKtQ/ZcQDCAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8hAAIaAAkKegyaEQCXAQAaAAkKegyaEQCXAQAAAA==.Liv:BAAANQAECgMIBwAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQAECgMIAwAAAA==.',
Lu='Luckydog:BAAANQAECgcIEQAAAA==.Ludey:BAABNQAECn86AAMmAAoKmRkgBACiAgAmAAoKmRkgBACiAgAoAAEKVRQLOAFGAAAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgMIBgAAAA==.Lutray:BAABNQAECn8YAAIVAAkKRyLuBgDyAgAVAAkKRyLuBgDyAgAAAA==.',
Ma='Makaveleli:BAAANQAECgUIBwAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn87AAIBAAoKhBYZIABhAgABAAoKhBYZIABhAgAAAA==.Marodd:BAABNQAECn8eAAICAAkKaCClFQCxAgACAAkKaCClFQCxAgAAAA==.Mashira:BAAANQAECgQIBQAAAA==.Mashîra:BAACNQAFFH8OAAIDAAcKEB7gAwAgAgADAAcKEB7gAwAgAgA1AAQKfzoAAwMACgoOJiwEAEoDAAMACgoOJiwEAEoDACcABgr1HxUjADUCAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgUICQAAAA==.',
Me='Meanmachine:BAAANQAECgEIAQAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn8+AAQeAAoKyR4gHgDzAgAeAAoKyR4gHgDzAgAOAAEKAABqNQA6AAARAAEKAAC0PwEuAAAAAA==.Mekuro:BAAANQAECgQICgAAAA==.Melky:BAAANQAECgMIBQABNQAECgYIBgANAAAAAA==.Mellindria:BAAANQAECgEIAQAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgUIBQAAAA==.Mewfasa:BAAANQADCggICAAAAA==.Meyday:BAAANQAECgcIBwAAAA==.',
Mi='Mia:BAABNQAECn8WAAITAAkK0h/XEQDdAgATAAkK0h/XEQDdAgAAAA==.Migraine:BAAANQADCgQIBAAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyA6TACwAgAFAAgKOyA6TACwAgAAAA==.Minasuzune:BAABNQAECn8VAAMDAAkKkiCnaABCAgADAAkKkiCnaABCAgAnAAIK9AzTdQBkAAAAAA==.Miney:BAAANQAECgEIAQAAAA==.Minus:BAAANQAECgYIBgAAAA==.',
Mo='Moller:BAAANQAECgEIAgAAAA==.Monkchow:BAAANQADCgEIAQAAAA==.Moondotter:BAAANQAECgQIBgABNQAECgQIBwANAAAAAA==.Moongoddess:BAAANQAECgQIBwAAAA==.Moonslayer:BAABNQAECn8eAAIgAAkKJA44LgAfAQAgAAkKJA44LgAfAQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.Morf:BAAANQAECgEIAQAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.Myley:BAAANQAECgUIBAABNQAECgYIBgANAAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAcIDgADABAeAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAgABNQAFFAcIDgADABAeAA==.Måshîrå:BAAANQAECgYICgABNQAFFAcIDgADABAeAA==.',
Na='Nakor:BAABNQAECn8gAAIhAAcKYgT8MQE5AQAhAAcKYgT8MQE5AQAAAA==.Nalian:BAAANQAECgYJEQAAAA==.Nalliella:BAABNQAECn8hAAIMAAcKLBJwDwC1AQAMAAcKLBJwDwC1AQAAAA==.Narmak:BAAANQAECgEIAQAAAA==.Natalie:BAAANQAECggIAgAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAABNQAECn8UAAILAAcKKxIFqgC0AQALAAcKKxIFqgC0AQAAAA==.Nefeli:BAABNQAECn8xAAIjAAoKYxVxBQCOAgAjAAoKYxVxBQCOAgAAAA==.Nelinne:BAAANQAECgIIBAAAAA==.Nellevene:BAABNQAECn8YAAIjAAkKtgEGHACHAAAjAAkKtgEGHACHAAAAAA==.Nestia:BAAANQAECgUIDwAAAA==.Never:BAACNQAFFH8JAAMHAAMKDBgMDQCdAAAHAAIKIBUMDQCdAAAoAAIKexikHQB4AAA1AAQKfzcAAygACgqjIjAPALACACgACgpEIjAPALACAAcABQpHHjgdAIQBAAAA.',
Ni='Nightshade:BAABNQAECn8zAAIDAAoKABrVLwDdAgADAAoKABrVLwDdAgAAAA==.Nimbus:BAAANQAECggIDwAAAA==.Nix:BAAANQAECgEIAgAAAA==.',
No='No:BAAANQAECgEIAQAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8hAAIEAAkKHBLVHQD7AQAEAAkKHBLVHQD7AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAABNQAECn8WAAIPAAgKsAWYUwBuAQAPAAgKsAWYUwBuAQAAAA==.',
On='Oniana:BAABNQAECn8tAAInAAkK2wqpGgAuAQAnAAkK2wqpGgAuAQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAFFAIIBgAgALgSAA==.',
Ow='Owwmyballs:BAAANQAECggIEQAAAA==.',
Oz='Ozygo:BAAANQAECggICAAAAA==.',
Pa='Pagamas:BAACNQAFFH8OAAIhAAYKGxLMGQCrAQAhAAYKGxLMGQCrAQA1AAQKfyYAAyEACgr1HrxXANACACEACgr1HrxXANACACIAAgqLEa03AF4AAAAA.Palandari:BAAANQAECgUICQAAAA==.Pandawan:BAAANQAECgMICgAAAA==.Pandormu:BAAANQAECgYICgABNQAECgoKHAAmAPYTAA==.Panter:BAABNQAECn8cAAImAAoK9hOsBQBiAgAmAAoK9hOsBQBiAgAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAABNQAECn8VAAIbAAcKOw3OIQAEAQAbAAcKOw3OIQAEAQAAAA==.',
Ph='Phodoe:BAABNQAECn8gAAIXAAkKtAsfNAB6AQAXAAkKtAsfNAB6AQAAAA==.Phöebe:BAAANQAECgMIBAAAAA==.',
Pi='Pinquisitor:BAAANQAECgEIAgABNQAECgMICgANAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAAANQAECgYIEAAAAA==.',
Po='Pokeureyeout:BAABNQAECn8eAAIDAAcKkg1BiQAfAQADAAcKkg1BiQAfAQAAAA==.Port:BAAANQAECgUICAABNQAECgYIDwANAAAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECgoKIwAXAGQXAA==.Prodyne:BAABNQAECn86AAIhAAoKLhW/eQCKAgAhAAoKLhW/eQCKAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECggIHgACANkYAA==.',
Qa='Qariwarmi:BAAANQAECgIIAwAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAFFAQICAABAG0dAA==.Quiettreader:BAABNQAECn8+AAIiAAoKYxc7BQDDAgAiAAoKYxc7BQDDAgAAAA==.Quokka:BAAANQAECgMIBgAAAA==.',
Ra='Raegwin:BAAANQAECgcIDgAAAA==.Rafiki:BAAANQAECgMIAwAAAA==.Raidboss:BAAANQAECgcIEwAAAA==.',
Re='Redeath:BAAANQAECgQICAABNQAECgYICgANAAAAAA==.Redirect:BAAANQAECgUICQABNQAECgYICgANAAAAAA==.Redonculous:BAABNQAECn8sAAICAAoKsxSCHgBLAgACAAoKsxSCHgBLAgAAAA==.Redpool:BAACNQAFFH8GAAIeAAMKEQZDGQB3AAAeAAMKEQZDGQB3AAA1AAQKfzIAAh4ACgrmELFdAPYBAB4ACgrmELFdAPYBAAAA.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8nAAITAAcK7CBmGACZAgATAAcK7CBmGACZAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgkJMgAKAHUjAA==.Reymnant:BAAANQAECgIIBAAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.',
Ro='Ronx:BAABNQAECn8VAAIiAAYKmxnNEgB7AQAiAAYKmxnNEgB7AQAAAA==.Roxxiloxxi:BAABNQAECn8oAAMHAAoK/gW5GACmAQAHAAkKfga5GACmAQAoAAUKVgIXsgCNAAAAAA==.',
Ru='Rudeboy:BAABNQAECn8sAAIoAAoKXhkJVQBXAgAoAAoKXhkJVQBXAgAAAA==.Rumchata:BAAANQAECgEIAQABNQAFFAIIBgAgALgSAA==.Rushu:BAACNQAFFH8JAAIhAAQK+RCcGADlAAAhAAQK+RCcGADlAAA1AAQKfy4AAiEACgoNGXtcAMcCACEACgoNGXtcAMcCAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn83AAMUAAoKYReaQABiAgAUAAoKYReaQABiAgAFAAcKYQrx3wBbAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgcIEwANAAAAAA==.Sahria:BAAANQAECgYIBgAAAA==.Samlosco:BAAANQAECggIEQAAAA==.Sapphpal:BAAANQAECgYICAABNQAECggIDwANAAAAAA==.Sarhia:BAAANQAECgMIBAAAAA==.Savanari:BAAANQAECgEIAgABNQABCgIIAgANAAAAAA==.',
Sc='Schizadin:BAABNQAECn8iAAMEAAkKEiWzAQBFAwAEAAkKEiWzAQBFAwAFAAMKHgfbbQFxAAAAAA==.Schizology:BAAANQAECgcICQABNQAECgkJIgAEABIlAA==.Schnoze:BAAANQAECgUIEwAAAA==.',
Se='Seabane:BAAANQAECgUICAAAAA==.Sebekuul:BAAANQADCgYIBgAAAQ==.Selfie:BAAANQAECgEIAQAAAA==.Selys:BAACNQAFFH8KAAIhAAUKVQovLgAfAQAhAAUKVQovLgAfAQA1AAQKf0wAAyEACgrvGLEhAHICACEACgrvGLEhAHICACIAAgr1BoY5AFgAAAAA.Sepheturix:BAAANQAECgUICQAAAA==.Sephurik:BAACNQAFFH8aAAMhAAcKhxaGBwBzAQAhAAcKMhSGBwBzAQAiAAEKBAxqCgBWAAA1AAQKf0oAAyEACgpsJC4cAI4CACEACgqxIi4cAI4CACIAAgpEH5gpAKoAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgcIEwAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCggIDQAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAABNQAECn8UAAICAAcKXxhcGQBGAQACAAcKXxhcGQBGAQABNQAECgcIFQAeAN4bAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiftingmoon:BAAANQAECgQIBAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.Shiv:BAAANQAECggIAwAAAA==.Shyft:BAAANQAECgUIBgAAAA==.',
Si='Sidisi:BAAANQAECggIDwABNQAECgoKIwAnAIYgAA==.Sikanda:BAABNQAECn8YAAMcAAkK4RtnIwC2AgAcAAkK4RtnIwC2AgAIAAIKuhRVjACEAAABNQAECgoKIwAnAIYgAA==.Silvea:BAABNQAECn8gAAIRAAkKfBAFOQBxAQARAAkKfBAFOQBxAQAAAA==.Silvett:BAAANQAECgQIBgAAAA==.Sinara:BAAANQAECgQIBgAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn8wAAICAAoKrCAzDQAYAwACAAoKrCAzDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAAANQAECggIDwAAAA==.Sky:BAACNQAFFH8FAAIhAAMKfxeVQACxAAAhAAMKfxeVQACxAAA1AAQKfzEAAiEACgr4JOEVAHsDACEACgr4JOEVAHsDAAAA.Skyelf:BAABNQAECn8tAAIDAAoKaw1VPADwAQADAAoKaw1VPADwAQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDwAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECn81AAMeAAoKQxnOIADmAgAeAAoKQxnOIADmAgARAAEKxAMbzAAsAAAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAgIKAAOAOkdAA==.Solunara:BAAANQADCgUIBQABNQAECggIFwAFAGcXAA==.',
Sp='Spectrecles:BAACNQAFFH8GAAIgAAIKuBLbEACXAAAgAAIKuBLbEACXAAA1AAQKfzQAAyAACgpGGH4YANIBACAACgpGGH4YANIBABcAAQo8Bl5hACAAAAAA.Spectrecless:BAAANQAECgMIAwABNQAFFAIIBgAgALgSAA==.Speez:BAABNQAECn8dAAIDAAgKFBPfegAZAgADAAgKFBPfegAZAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.',
St='Stablehand:BAABNQAECn8ZAAIDAAcK5BMbpQC7AQADAAcK5BMbpQC7AQAAAA==.Steve:BAACNQAFFH8YAAMRAAcK0BA7AwCGAQARAAYK+xA7AwCGAQAOAAEK+A8oBQBfAAA1AAQKf0EABBEACgqGIxwUAFEDABEACgpsIxwUAFEDAA4ABgpaIFkMANEBAB4AAgpiAgUkASkAAAAA.Stonedfel:BAABNQAECn8vAAISAAoKnhIUOQDqAQASAAoKnhIUOQDqAQAAAA==.',
Su='Sunhoof:BAABNQAECn8XAAQFAAgKZxeIhAAeAgAFAAgKZxeIhAAeAgAEAAIKfRMUWgB0AAAUAAIKHAW2EQFTAAAAAA==.Supahotvile:BAACNQAFFH8GAAMPAAMKaQbICABlAAAKAAIKAQdqEwCLAAAPAAIKYgTICABlAAA1AAQKfyIAAw8ACgrLFBMsADgCAA8ACgpFDxMsADgCAAoABQroFsZDAFABAAAA.',
Sy='Syx:BAAANQAECgUICAAAAA==.',
['Sø']='Sørrow:BAABNQAECn8gAAITAAkKdA7qNQCUAQATAAkKdA7qNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8hAAMiAAkKkgfUFwA8AQAiAAkKXwfUFwA8AQAhAAYK9QG3ewHKAAAAAA==.Tabu:BAAANQADCgcIBwAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggIDQAAAA==.Tankoromma:BAAANQADCggIDwAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgUIEAANAAAAAA==.',
Te='Ten:BAAANQAECgIIBgAAAA==.Test:BAAANQAECggJAQAAAA==.',
Th='Theblakmamba:BAAANQADCgIIAgAAAA==.Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQAECgEIAQAAAA==.Thetaint:BAABNQAECn8zAAMPAAoKkiOnBACLAwAPAAoKkiOnBACLAwAKAAkKDRwXHAA8AgAAAA==.Thunderous:BAAANQADCgMIAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8NAAIDAAYKUSC/BwDSAQADAAYKUSC/BwDSAQA1AAQKfy0AAwMACgqTJVQDAFgDAAMACgqTJVQDAFgDACcAAQpAGVOBAEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgoKMAACAKwgAA==.',
To='Tomahawkchow:BAAANQAECggICwAAAA==.Totemofpeace:BAAANQADCggIEAABNQAECgoKIwAXAGQXAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Treehorse:BAAANQAECgQICAAAAA==.Trentlock:BAACNQAFFH8SAAQoAAYKUwTcHQB1AAAoAAQKcATcHQB1AAAHAAIKNQQnEABBAAAmAAEKAABrEgA+AAA1AAQKfzMAAygACgoOHo1SAF4CACgACgr0F41SAF4CAAcABAoyIV0hAGYBAAAA.Tristae:BAAANQAECgYIDQAAAA==.',
Ts='Tsu:BAABNQAECn8eAAMKAAkKTyPVIAAYAgAPAAcKcBsFMQAdAgAKAAgK1SPVIAAYAgAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgIIAgAAAA==.Unstablesha:BAAANQAECgcIDAAAAA==.',
Ut='Utilities:BAAANQAECgEIAgAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8PAAQcAAUKEBPqEQDtAAAcAAQKEBPqEQDtAAAIAAEKvAEeFwAuAAAJAAEKAADUNgAlAAA1AAQKfy8AAhwACgpwIbQVAAwDABwACgpwIbQVAAwDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQAECgEIAgAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vigiles:BAAANQAECgEIAQAAAA==.Vil:BAACNQAFFH8qAAICAAoKfh4qAAAYAwACAAoKfh4qAAAYAwA1AAQKfyoAAgIACgrJJkcCAL0DAAIACgrJJkcCAL0DAAAA.Vilonus:BAABNQAECn8mAAIoAAgKdhA1lAC0AQAoAAgKdhA1lAC0AQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgoKMAACAKwgAA==.',
Vo='Voidbwoy:BAAANQAECgEIAQAAAA==.Volairis:BAAANQAECgYICAABNQAFFAYICgAbAKEQAA==.Voy:BAABNQAECn8eAAIGAAgKtwgZCQCvAQAGAAgKtwgZCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICAAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
Wa='Wagyu:BAAANQAECgEIAQAAAA==.',
We='Weezy:BAABNQAECn8mAAMBAAoK2g77MQD2AQABAAkKPg/7MQD2AQACAAkKJAkwOABkAQAAAA==.',
Wi='Williie:BAAANQAECgcIDAAAAA==.Withengar:BAAANQAECgcIBgAAAA==.',
Wu='Wuoshi:BAAANQAECgUIEAAAAA==.Wuuzzyy:BAABNQAECn8nAAIgAAkKDRMlNwA0AgAgAAkKDRMlNwA0AgAAAA==.',
Xa='Xaliko:BAABNQAECn8SAAIoAAoKlxUjVABmAQAoAAoKlxUjVABmAQAAAA==.Xanbaran:BAABNQAECn86AAIBAAoKTQpRbgDTAQABAAoKTQpRbgDTAQAAAA==.',
Xi='Xiphus:BAAANQAECgIIBAAAAA==.',
Xm='Xmarks:BAAANQAECgUIBgAAAA==.',
Xy='Xyrters:BAAANQAECgEIAQAAAA==.Xyrtrew:BAACNQAFFH8OAAIeAAUKnCCaBwDeAQAeAAUKnCCaBwDeAQA1AAQKfzwAAx4ACgrFIiAQAEMDAB4ACgrFIiAQAEMDABEAAQoAAO4iAUsAAAAA.',
Ya='Yahenni:BAABNQAECn8jAAMnAAoKhiBNFQC0AgAnAAgKxB9NFQC0AgADAAkKUBh1YwBOAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAAANQAECggIDgAAAA==.Yukki:BAAANQAECggIDgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAABNQAECn8dAAITAAoKKhaSHwBSAgATAAoKKhaSHwBSAgAAAA==.Zaylas:BAAANQAECgEIAgAAAA==.',
Ze='Zerk:BAABNQAECn8XAAILAAkKYQJ+AwHWAAALAAkKYQJ+AwHWAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
['Ða']='Ðavîs:BAAANQAECgEIAgABNQAECgoKKgAcABocAA==.',
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
