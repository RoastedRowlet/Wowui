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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Hunter-Survival','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','DeathKnight-Frost','Priest-Holy','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Arcane','Mage-Frost','Warrior-Fury','Warrior-Protection','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Druid-Guardian','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Monk-Windwalker','Shaman-Enhancement','Druid-Restoration','DemonHunter-Devourer','Priest-Discipline',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abracanoobra:BAAANQAECgcIEQAAAA==.Abuki:BAABNQAECoEgAAIBAAkKwB8yBwAGAwABAAkKwB8yBwAGAwAAAA==.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECgQIAwAAAA==.',
Al='Alfuric:BAAANQAECgQIBwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgMIBAACAAAAAA==.Althraniir:BAAANQADCgcIBwAAAA==.Altrois:BAABNQAECoEiAAIDAAgKNRkJLwA7AgADAAgKNRkJLwA7AgAAAA==.',
Am='Amatrake:BAACNQAFFIETAAIEAAYKtRWAAgDUAQAEAAYKtRWAAgDUAQA1AAQKgSkAAgQACQouHuoLALoCAAQACQouHuoLALoCAAAA.Amatsano:BAEANQAECgQIAwAAAA==.Amorsith:BAAANQAECgUIEQABNQAECgcIGAAFAK8OAA==.Amyst:BAABNQAECoEhAAIGAAgKfR/TQgCoAgAGAAgKfR/TQgCoAgAAAA==.',
An='Angrycrack:BAAANQAECgcIEAAAAA==.Angusill:BAAANQADCggIEgAAAA==.Animuggus:BAAANQAECgQIAwAAAA==.Anjunabeets:BAACNQAFFIEVAAMHAAcKBRY1BgDLAQAHAAYKexY1BgDLAQAIAAEKRBPgJwBeAAA1AAQKgR4AAwcACQpFJKYVAJoCAAcACAoPJKYVAJoCAAgAAgoTGpgPAZIAAAAA.Anthran:BAABNQAECoEfAAMJAAgKmg4sMAD8AAAKAAUKHwqWxgAPAQAJAAQKExMsMAD8AAAAAA==.',
Ao='Ao:BAAANQAECgIIAwAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAECggIFgALAJsSAA==.Arcscythe:BAABNQAECoEcAAIMAAgKexX3AQAyAgAMAAgKexX3AQAyAgAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAABNQAECoEiAAINAAkKLRc1HgBxAgANAAkKLRc1HgBxAgAAAA==.',
Au='Auramis:BAABNQAECoEmAAIOAAgKCiGWFwACAwAOAAgKCiGWFwACAwAAAA==.',
Az='Azariel:BAABNQAECoEcAAIPAAkKrRbaHgB9AgAPAAkKrRbaHgB9AgAAAA==.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFIETAAIDAAYKTiTcAQB2AgADAAYKTiTcAQB2AgA1AAQKgSkAAgMACQqvI8MIAGcDAAMACQqvI8MIAGcDAAAA.Balgith:BAAANQAECgUICgAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECoEYAAMQAAkKCw54uwBtAQAQAAgKngt4uwBtAQARAAUKhAmapQAMAQAAAA==.Barthoun:BAAANQAECgcICgAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQAECgEIAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAACNQAFFIELAAQNAAYKTA6ACAAXAQANAAQKYguACAAXAQASAAEKzRhoGQBfAAADAAEKcg82LQAuAAA1AAQKgS4ABA0ACQoIIYoQAOwCAA0ACQqlIIoQAOwCABIACAp5G6o/APkBAAMAAgqnGW+ZAIcAAAAA.Beoron:BAABNQAECoEyAAITAAkKiSXiAADRAwATAAkKiSXiAADRAwAAAA==.Bettyßastion:BAAANQAECgYIEQAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECgEIAQAAAA==.Bio:BAAANQAECggIBwAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggIBwACAAAAAA==.Biolysis:BAAANQADCgUIBQABNQAECggIBwACAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAABNQAECoEaAAMUAAcKOgkD+gByAQAUAAcKhwgD+gByAQAVAAEKggb2PwA1AAAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAAANQAECgYICgAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAAANQAECgQIDQAAAA==.Brontag:BAABNQAECoEgAAQWAAgK1B64BQCVAgAWAAcKCSG4BQCVAgAGAAYK/hFBqACMAQAXAAEKDBYROQA7AAAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgACAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAAANQAECgcIEwAAAA==.Canekii:BAAANQAECgYIEQABNQAECgcIEwACAAAAAA==.Casini:BAAANQAECgcIBwAAAA==.',
Ce='Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAABNQAECoEfAAIIAAkKpiMJDQBlAwAIAAkKpiMJDQBlAwAAAA==.',
Ch='Chaboomy:BAECNQAFFIESAAIYAAYK0RNECADKAQAYAAYK0RNECADKAQA1AAQKgSoAAhgACQqsI+cMAFUDABgACQqsI+cMAFUDAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECoEfAAIGAAgKaxBshADsAQAGAAgKaxBshADsAQAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECoEdAAQUAAgKqxuhdQB8AgAUAAgKqxuhdQB8AgAMAAMKfQzYBgC0AAAVAAEKjh0sPgA4AAAAAA==.Collie:BAEANQAECggIEQAAAA==.Conyay:BAAANQAECgcICQAAAA==.',
Cr='Croissant:BAABNQAECoEbAAIKAAgKjBxyNwCTAgAKAAgKjBxyNwCTAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgUICgABNQADCgcIEAACAAAAAA==.Damaerin:BAAANQAECgQIBgAAAA==.Darkis:BAAANQAECgcJDgAAAA==.Darkseph:BAAANQAECgQIAgABNQAECgUIBAACAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFIEPAAMZAAYK3BuABwDMAQAZAAUKwxuABwDMAQAaAAEKpAPsKABBAAA1AAQKgS0AAxkACQp+IwgKAIsDABkACQp+IwgKAIsDABoAAgoYDALlAHEAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECoEZAAIbAAkKghNJHgBjAgAbAAkKghNJHgBjAgABNQAECgkJIgAIACMgAA==.Delessia:BAAANQADCgcJDwAAAA==.Demonesque:BAAANQABCggIDwAAAA==.Deo:BAAANQAECggIEQAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAABNQAECoEcAAIcAAkKRB/dBQANAwAcAAkKRB/dBQANAwAAAA==.Disastrous:BAABNQAECoEjAAIIAAkKSBO+SwBjAgAIAAkKSBO+SwBjAgAAAA==.',
Do='Doomangel:BAAANQAECgEIAQAAAA==.Doson:BAAANQADCgcIDQAAAA==.',
Dr='Dragonbison:BAAANQAECgQIAwAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgkJIgAIACMgAA==.',
['Dø']='Døc:BAABNQAECoEmAAMaAAgKph09RAAlAgAaAAcKHB49RAAlAgAZAAYKchQ/eQCGAQAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFIERAAIKAAYKORPqBQDlAQAKAAYKORPqBQDlAQA1AAQKgSkAAwoACQoeHx0bAAQDAAoACQoeHx0bAAQDAAkAAgrqDlJcAGQAAAAA.',
El='Eldranus:BAAANQAECgQIAwAAAA==.',
En='Enimed:BAABNQAECoEgAAIDAAgKVRaZNwAKAgADAAgKVRaZNwAKAgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAABNQAECoEjAAQJAAkKXCFbGQCZAQAKAAYKpR+fXgAaAgAJAAUKhBtbGQCZAQAdAAMKZyEMEAAjAQAAAA==.',
Fa='Falarion:BAAANQAECgYIBgAAAA==.Fam:BAABNQAECoE1AAIUAAkKMSMiHABdAwAUAAkKMSMiHABdAwAAAA==.Fatherseph:BAAANQAECgUIBAAAAA==.',
Fi='Finkymcbinky:BAAANQAECgQIBAAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECoEgAAIVAAgKjRuyBgBlAgAVAAgKjRuyBgBlAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggILQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECoEYAAILAAgK5QdMFgBaAQALAAgK5QdMFgBaAQAAAA==.',
Fr='Frostborne:BAABNQAECoEXAAISAAcKdhYURwDVAQASAAcKdhYURwDVAQAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAACAAAAAA==.',
Fu='Funeral:BAAANQAECgcIBwABNQAECgkJIgAIACMgAA==.',
Ga='Gamjee:BAAANQAECgQIAwAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Gl='Glyndin:BAAANQADCgcIDQAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAECgkJHAAcAEQfAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQAECgEIAQAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAAANQAECgEIAgAAAA==.Gruvac:BAAANQADCggIGAABNQAECgUIBAACAAAAAA==.',
Gu='Guilliman:BAABNQAECoEVAAIGAAgKkBjtVwBnAgAGAAgKkBjtVwBnAgAAAA==.Gulaj:BAABNQAECoEZAAIIAAcKRBZccQABAgAIAAcKRBZccQABAgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgUICgAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECoEeAAIOAAgKJBntOwBWAgAOAAgKJBntOwBWAgAAAA==.',
Hi='Hiruken:BAAANQADCgYICgAAAA==.',
Ho='Hope:BAAANQAECggIDAABNQAECgkKGAARAE8YAA==.Hortzel:BAAANQAECgQIAwAAAA==.Howdoitotem:BAABNQAECoEaAAMZAAgKyhbNRQAzAgAZAAgKyhbNRQAzAgAaAAMK3gcS4gB4AAAAAA==.',
Hu='Hulkx:BAAANQAECgQICQAAAA==.Humaa:BAAANQAECgYIEwAAAA==.Huntus:BAABNQAECoEmAAIIAAgKIB0KMQC3AgAIAAgKIB0KMQC3AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icewiz:BAAANQABCgUIBQABNQAECgQIBAACAAAAAA==.Icy:BAAANQAECggIDAAAAA==.',
Im='Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECoEkAAIeAAkKGR0XDwDpAgAeAAkKGR0XDwDpAgAAAA==.',
Iz='Izuu:BAAANQAECgQIBQAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQJBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAABNQAECoElAAMfAAkKIBtEFwAUAgAfAAcKhxpEFwAUAgAbAAQKlhjDUwAfAQAAAA==.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAAANQAECgUICgAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECgUIBAACAAAAAA==.',
Ka='Kankiro:BAAANQADCggICAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQAECgUICAAAAA==.Kelemvor:BAAANQAECgcJDwAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECggIEwAAAA==.',
Ki='Kimmy:BAAANQAECgUICwAAAA==.',
Kl='Kleenex:BAAANQAECgYICwAAAA==.',
Ko='Koldiss:BAAANQADCgQIBAAAAA==.',
Kr='Krueger:BAAANQAECgQIBAABNQAECgUIDwACAAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAECgkJGgAaANoWAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECoEiAAIIAAkKIyCUEgA/AwAIAAkKIyCUEgA/AwAAAA==.Leethalfu:BAAANQAECgcIEAAAAA==.Leethalrot:BAAANQAECgEIAQABNQAECgcIEAACAAAAAA==.Legosi:BAAANQAECgYIEwAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECoEdAAIKAAgKDB9RKgDCAgAKAAgKDB9RKgDCAgAAAA==.Leviosa:BAAANQABCgUJBwAAAA==.',
Lh='Lhux:BAABNQAECoEjAAIIAAkKsRsmKQDUAgAIAAkKsRsmKQDUAgABNQAECgQICQACAAAAAA==.Lhuxi:BAAANQAECgQICQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAABNQAECoEhAAIYAAkKJCEZDgBJAwAYAAkKJCEZDgBJAwAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.',
Ly='Lyxxie:BAABNQAECoEhAAMNAAgKDBx8IwBHAgANAAgKPhp8IwBHAgASAAUKQxBSgQDwAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECgIIAgAAAA==.Manafart:BAAANQADCgYJBgABNQAECggIHwAGAGsQAA==.Matsumushi:BAABNQAECoEfAAMLAAgK7RYIDQANAgALAAgK7RYIDQANAgAgAAYKYQY1PwDkAAAAAA==.',
Mc='Mcnastyy:BAAANQADCgMIBAAAAA==.',
Me='Mefesto:BAABNQAECoEbAAIUAAkKshKumgAtAgAUAAkKshKumgAtAgABNQABCgQIBgACAAAAAA==.Mellore:BAAANQAECgIJAgABNQAECgkJIQAYACQhAA==.Metsutan:BAABNQAECoEgAAIfAAgK1BwNDACkAgAfAAgK1BwNDACkAgAAAA==.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQAECgMIAwAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgIIAQAAAA==.',
Na='Naes:BAAANQADCgcJDAAAAA==.',
Ne='Nekcrotic:BAAANQAECgcIEgAAAA==.Nekromant:BAABNQAECoEaAAMJAAcKlw65RACoAAAKAAUKdg4jvQAjAQAJAAMKiA25RACoAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgQIAwAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBQAAAA==.',
No='Nohric:BAAANQAECgYIDwAAAA==.Norsem:BAAANQAECgYICAAAAA==.',
Ny='Nymera:BAAANQADCggIDwABNQAECgEIAQACAAAAAA==.',
Oh='Ohlorn:BAABNQAECoEkAAIhAAkKASJaBABGAwAhAAkKASJaBABGAwAAAA==.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onfleek:BAAANQAECgIIAgAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgMIAwAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQJBAACAAAAAA==.Palysuk:BAAANQADCggIDQAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAACNQAFFIELAAMiAAQKXyAvCAA1AQAiAAMKOCMvCAA1AQAYAAMKlA3MFADhAAA1AAQKgSUABCIACQpWJp0AANwDACIACQpWJp0AANwDABgAAQotGrOVAE8AABMAAQrYDPI1ADcAAAE1AAQKBwgJAAIAAAAA.Parstout:BAAANQAECgcICQAAAA==.Pawsitivity:BAABNQAECoEjAAIZAAgKYiJvHAAGAwAZAAgKYiJvHAAGAwAAAA==.',
Pd='Pdbm:BAABNQAECoEXAAIQAAgKmB4gQQCsAgAQAAgKmB4gQQCsAgAAAA==.',
Pe='Petr:BAABNQAECoEnAAMOAAgKYx1ZJwCvAgAOAAgKYx1ZJwCvAgAeAAEKLAPzfgAeAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECoEaAAIRAAgKOhxfKwCgAgARAAgKOhxfKwCgAgAAAA==.',
Ph='Physix:BAAANQAECgEIAQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAABNQAECoEfAAMNAAgKuBtUKwAMAgANAAcKVRtUKwAMAgASAAYKbRRxWgB/AQAAAA==.',
Pr='Priestus:BAAANQAECgEIAQAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQABNQAECgkJHQAaAAQgAA==.',
Pu='Pugfoo:BAAANQADCgYIBgAAAA==.',
Py='Pyraxx:BAABNQAECoEtAAIVAAkKMSKLAQBgAwAVAAkKMSKLAQBgAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFIEQAAIjAAUK9R3iBADNAQAjAAUK9R3iBADNAQA1AAQKgSMAAiMACQqcIjkIAEcDACMACQqcIjkIAEcDAAAA.',
Qu='Quatermaine:BAAANQAECgUIBwAAAA==.',
Ra='Radovan:BAACNQAFFIEPAAMKAAUK5hhFDwBaAQAKAAQKHhlFDwBaAQAJAAEKCBiqFgBTAAA1AAQKgSkAAwoACQqWJRcUACcDAAoACAp9JRcUACcDAAkABQolIHAZAJgBAAAA.Rayael:BAAANQAECgQIBAABNQAECgkJJwAVAE4YAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAAANQAECgQIBgABNQAECgUIEQACAAAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECoEaAAMaAAgKqhLvkgAqAQAaAAYK2g3vkgAqAQAZAAYK5QaGrQAJAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Rosaelyia:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECoEcAAIRAAgK4SDYHgDfAgARAAgK4SDYHgDfAgAAAA==.',
Sa='Samavati:BAAANQAECgUICwAAAA==.Sarah:BAABNQAECoEqAAMOAAkKVCSjAgC2AwAOAAkKVCSjAgC2AwAkAAMKngtwGACRAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFIEMAAIfAAUKIQi7BgCHAQAfAAUKIQi7BgCHAQA1AAQKgSgAAh8ACQoJHYMKAL8CAB8ACQoJHYMKAL8CAAAA.Sassyface:BAABNQAECoEgAAIJAAgK9Q2dEgDVAQAJAAgK9Q2dEgDVAQAAAA==.',
Se='Sellit:BAAANQAECgEIAQAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECggIAwAAAA==.Shadowdin:BAABNQAECoEXAAIRAAgKthzPKgCjAgARAAgKthzPKgCjAgAAAA==.Shamzilla:BAABNQAECoEgAAIZAAgKbxnnOwBdAgAZAAgKbxnnOwBdAgAAAA==.Shockblast:BAAANQADCggIFgAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECggIHwAJAJoOAA==.',
Si='Sibbrena:BAABNQAECoEgAAIeAAgK2BuYFwB2AgAeAAgK2BuYFwB2AgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAAANQAECgQIDQAAAA==.Sinemon:BAAANQAECgQIAwAAAA==.Sinz:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAABNQAECoEeAAMRAAkKmiHfCAB1AwARAAkKmiHfCAB1AwAQAAEKGh6WWQFPAAAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAAANQAECgQIBwAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAUIDwAKAOYYAA==.',
Sm='Smartlurth:BAAANQADCgYIDAAAAA==.',
Sn='Snowjob:BAAANQAECgYIEgAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgYIEwACAAAAAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgQIAwAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQABCgQIBQAAAA==.Steakfries:BAAANQADCgMIAwAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAAANQAECgYIDgAAAA==.Stellar:BAAANQAECgIJAgABNQAECgkJLgAfAJIfAA==.Stelthme:BAABNQAECoEYAAMbAAYKkxJyPgCRAQAbAAYKKRJyPgCRAQAfAAEKgxNORgBOAAABNQAECgkJLgAfAJIfAA==.Strongman:BAAANQAECgIIAgAAAA==.',
Sw='Sweetie:BAAANQABCgYICAAAAA==.',
Ta='Tanìs:BAAANQAECgYICQAAAA==.Tarle:BAAANQAECgUICAAAAA==.Tazath:BAAANQAECgUICAABNQAECgkJMgATAIklAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECoEXAAIDAAgKHRfVMAAwAgADAAgKHRfVMAAwAgAAAA==.',
Tr='Trashii:BAABNQAECoEgAAMFAAgKtA5RBgARAgAFAAgKtA5RBgARAgAHAAMKUwO0ZQBuAAAAAA==.Treevive:BAAANQAECgUIBQABNQAECggIIQAOADwjAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAABNQAECoEhAAIZAAkKXx0YKgC1AgAZAAkKXx0YKgC1AgAAAA==.Trystan:BAABNQAECoEdAAIQAAgK7Q9tkADQAQAQAAgK7Q9tkADQAQAAAA==.',
Ts='Tsinga:BAAANQAECgEJAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAABNQAECoEjAAILAAkKER/LBAAKAwALAAkKER/LBAAKAwAAAA==.Twohammered:BAAANQADCgcICwABNQAECgkJIwALABEfAA==.',
['Tø']='Tøm:BAACNQAFFIERAAIQAAYK+xlWAwAfAgAQAAYK+xlWAwAfAgA1AAQKgSgAAhAACQrKIxcXAFUDABAACQrKIxcXAFUDAAAA.',
Ul='Ullirus:BAAANQADCggIEQAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQAECgEIAQAAAA==.Unbiased:BAABNQAECoEpAAMSAAkKIxvfLABdAgASAAcKFB3fLABdAgANAAkKlxZoKQAaAgAAAA==.Unholyblodd:BAAANQADCggIGAAAAA==.Unshookable:BAABNQAECoEyAAIBAAkKoyKwAwBhAwABAAkKoyKwAwBhAwAAAA==.',
Ur='Ursos:BAAANQAECgEIAQAAAA==.Urìko:BAAANQAECgQIBAAAAA==.',
Va='Vaelor:BAAANQADCgQIBAAAAA==.Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQAECgEIAQAAAA==.',
Vi='Vika:BAAANQADCggIDAABNQAECgEIAQACAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAAANQAECgQIDQAAAA==.Voidlockus:BAAANQAECgEIAQAAAA==.',
Vu='Vulcin:BAABNQAECoEfAAIRAAkKHRuWHgDhAgARAAkKHRuWHgDhAgABNQAECgkJLQAVADEiAA==.',
Wa='War:BAAANQADCgQIBAABNQAECgkJIwAJAFwhAA==.Wariuus:BAAANQAECgQIBAAAAA==.Watercupp:BAAANQAECgQIBAAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgQIBQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQAECgcIEQAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQADCgcIBwACAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
Za='Zandramadas:BAABNQAECoEgAAMiAAgKbxh9IwDdAQAiAAcKKxl9IwDdAQAYAAgKahCYQQDGAQAAAA==.Zaraline:BAAANQAECgYICwAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgQIAwAAAA==.',
Zo='Zoomiez:BAAANQAECgEIAQAAAA==.',
Zp='Zpai:BAABNQAECoEWAAMLAAgKmxJ7DwDVAQALAAgKmxJ7DwDVAQAgAAYKJwXcQgDMAAAAAA==.',
Zy='Zyfae:BAAANQAECggIAgAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
['Äc']='Ächilles:BAAANQABCgIIAgAAAA==.',
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
