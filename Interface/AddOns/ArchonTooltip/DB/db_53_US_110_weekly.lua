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

local lookup = {'Druid-Restoration','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','DeathKnight-Frost','Priest-Holy','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Arcane','Mage-Frost','Warrior-Fury','Warrior-Protection','Priest-Shadow','Druid-Balance','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Druid-Guardian','Warlock-Affliction','Rogue-Subtlety','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abracanoobra:BAABNQAECn8WAAIBAAkKZBKbIAAhAgABAAkKZBKbIAAhAgAAAA==.Abuki:BAACNQAFFH8IAAICAAQKaxesBQBKAQACAAQKaxesBQBKAQA1AAQKfyMAAgIACQrAH0YJAPQCAAIACQrAH0YJAPQCAAAA.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECgQIBwAAAA==.',
Al='Alfuric:BAAANQAECgQIBwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgUICAADAAAAAA==.Althraniir:BAAANQADCgcIBwAAAA==.Altrois:BAABNQAECn8pAAIEAAkKWSHwCQBlAwAEAAkKWSHwCQBlAwAAAA==.',
Am='Amatrake:BAACNQAFFH8UAAIFAAYKMhdfAwDKAQAFAAYKMhdfAwDKAQA1AAQKfywAAgUACQr3Ha4NAL0CAAUACQr3Ha4NAL0CAAAA.Amatsano:BAEANQAECgQIBwAAAA==.Amorsith:BAABNQAECn8cAAMFAAkKtBlYDgC0AgAFAAkKtBlYDgC0AgAGAAYKwQzZ8AA0AQAAAA==.Amyst:BAABNQAECn8jAAIHAAgKbSEMSACuAgAHAAgKbSEMSACuAgAAAA==.',
An='Angrycrack:BAAANQAECgcIEAAAAA==.Angusill:BAAANQADCggIEgAAAA==.Animuggus:BAEANQAECgQIBwAAAA==.Anjunabeets:BAACNQAFFH8XAAMIAAcK9BZABgDuAQAIAAYK4BdABgDuAQAJAAEKRBNMLwBeAAA1AAQKfx4AAwgACQqTJOwZAIQCAAgACApZJOwZAIQCAAkAAgoTGlUqAZIAAAAA.Anthran:BAABNQAECn8hAAMKAAgKLRD+KQArAQAKAAUKaRD+KQArAQALAAUKSQpE3wAFAQAAAA==.',
Ao='Ao:BAAANQAECgIIAwAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAECggIGAAMAKYWAA==.Arcscythe:BAABNQAECn8eAAINAAgK0BQzAgA8AgANAAgK0BQzAgA8AgAAAA==.Arctron:BAAANQADCgQIBAABNQAECggIGAAMAKYWAA==.Artoo:BAAANQAECgIIAgAAAA==.',
As='Ashesonly:BAABNQAECn8qAAIOAAkKjhmOIQB9AgAOAAkKjhmOIQB9AgAAAA==.Assaulter:BAAANQADCgIIAgABNQAECgkJJwAJAD8gAA==.',
Au='Auramis:BAABNQAECn8tAAIPAAgK+iL6FwAVAwAPAAgK+iL6FwAVAwAAAA==.',
Az='Azariel:BAABNQAECn8nAAIQAAkKrh0bEAAeAwAQAAkKrh0bEAAeAwAAAA==.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFH8UAAIEAAYKDiQEAwBlAgAEAAYKDiQEAwBlAgA1AAQKfywAAgQACQprJPAKAFwDAAQACQprJPAKAFwDAAAA.Balgith:BAAANQAECgYIEAAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECn8cAAMGAAkKuQlvtgCrAQAGAAkKuQlvtgCrAQARAAUKhAmBuwABAQAAAA==.Barthoun:BAAANQAECggICwAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQAECgEIAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAACNQAFFH8MAAQOAAYKmBD1DAAGAQAOAAQK2w31DAAGAQASAAEKzRi2HABfAAAEAAEKAACnMgAuAAA1AAQKfzMABA4ACQpMIOURAPwCAA4ACQoMIOURAPwCABIACApYGTNIAPMBAAQAAgotGxamAIMAAAAA.Beoron:BAACNQAFFH8FAAITAAMK2RwDAgAVAQATAAMK2RwDAgAVAQA1AAQKfzQAAhMACQqUJUkBAMQDABMACQqUJUkBAMQDAAAA.Bettyßastion:BAABNQAECn8bAAIGAAcKIRXVqwDDAQAGAAcKIRXVqwDDAQAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECgUIBwAAAA==.Bio:BAAANQAECggIBwAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggIBwADAAAAAA==.Biolysis:BAAANQAECgQIBAABNQAECggIBwADAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAABNQAECn8dAAMUAAgKswmG8QClAQAUAAgK4giG8QClAQAVAAEKggbFRgA1AAAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAAANQAECgUIDgAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAAANQAECgUIEgAAAA==.Brontag:BAABNQAECn8kAAQWAAgKwB5LBwCDAgAWAAcKESBLBwCDAgAHAAYKrxlVngDMAQAXAAEKAACYQAA5AAAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgADAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAABNQAECn8ZAAMPAAgKUxiZUAAuAgAPAAgKUxiZUAAuAgAYAAEKAABRkgATAAAAAA==.Canekii:BAAANQAECgYIEQABNQAECggIGQAPAFMYAA==.Casini:BAAANQAECgcIBwAAAA==.Cathrîne:BAAANQADCggICAAAAA==.',
Ce='Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAACNQAFFH8GAAIJAAMK/R0TFAAdAQAJAAMK/R0TFAAdAQA1AAQKfyIAAgkACQpQI+sMAHYDAAkACQpQI+sMAHYDAAAA.',
Ch='Chaboomy:BAECNQAFFH8TAAIZAAYKzxZBCgDMAQAZAAYKzxZBCgDMAQA1AAQKfy4AAhkACQrzI7gNAFsDABkACQrzI7gNAFsDAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECn8nAAIHAAgKRhClmgDVAQAHAAgKRhClmgDVAQAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECn8jAAQUAAgK2BsHjgBjAgAUAAgK2BsHjgBjAgANAAUKGxHcBABMAQAVAAEKjh1IRwA0AAAAAA==.Conyay:BAAANQAECggIDQAAAA==.Cowploww:BAAANQADCgUIBQAAAA==.',
Cr='Croissant:BAABNQAECn8iAAILAAgKwx6QNwCrAgALAAgKwx6QNwCrAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalidan:BAAANQAECgUIBgABNQAECgkJHAAaAE0gAA==.Dalórien:BAAANQADCgUICgABNQADCgcIEwADAAAAAA==.Damaerin:BAAANQAECgQICgAAAA==.Darkis:BAAANQAECggIEgAAAA==.Darkseph:BAAANQAECgQIBgABNQAECgQIBwADAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFH8QAAMbAAYKhhsqCgDEAQAbAAUKhhsqCgDEAQAcAAEKpAMCLgA7AAA1AAQKfzIAAxsACQpgJa8GALIDABsACQpgJa8GALIDABwAAgoYDCL3AHcAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECn8dAAIdAAkKZRSvIwBlAgAdAAkKZRSvIwBlAgABNQAECgkJJwAJAD8gAA==.Delessia:BAAANQAECgYIBgAAAA==.Demonesque:BAAANQABCggIDwAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAACNQAFFH8IAAIeAAQK+iLsAQCSAQAeAAQK+iLsAQCSAQA1AAQKfx8AAh4ACQrPH6YHAAYDAB4ACQrPH6YHAAYDAAAA.Disastrous:BAACNQAFFH8FAAIJAAMKGQe1GgDfAAAJAAMKGQe1GgDfAAA1AAQKfyYAAgkACQq5E1dbAGACAAkACQq5E1dbAGACAAAA.',
Do='Doomangel:BAAANQAECgEIAQAAAA==.Doson:BAAANQAECgMIAwAAAA==.',
Dr='Dragonbison:BAAANQAECgQIBwAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgkJJwAJAD8gAA==.',
['Dø']='Døc:BAABNQAECn8vAAMcAAkKxRr5RQBGAgAcAAgK0Br5RQBGAgAbAAYKHRdbdgC6AQAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFH8SAAILAAYKwA7BCADfAQALAAYKwA7BCADfAQA1AAQKfywAAwsACQplHq4eAAcDAAsACQplHq4eAAcDAAoAAgrqDs9gAGIAAAAA.',
El='Eldranus:BAAANQAECgQIBwAAAA==.',
En='Enimed:BAABNQAECn8pAAIEAAkKWRa9NAA3AgAEAAkKWRa9NAA3AgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAACNQAFFH8FAAMKAAMK3BThDgCaAAALAAIKTBbILACkAAAKAAIKbg7hDgCaAAA1AAQKfyYABAoACQrQIAMbAJMBAAsABgqFHshiAC0CAAoABQpBIAMbAJMBAB8AAwpnIXQSAB8BAAAA.',
Fa='Falarion:BAAANQAECgYIBwAAAA==.Fam:BAABNQAECn81AAIUAAkKgyLtJQBIAwAUAAkKgyLtJQBIAwAAAA==.Fatherseph:BAAANQAECgQIBwAAAA==.',
Fi='Finkymcbinky:BAAANQAECgcICwAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECn8pAAIVAAkK/BlDBgCeAgAVAAkK/BlDBgCeAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggINQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECn8hAAIMAAkKcwgyFQCOAQAMAAkKcwgyFQCOAQAAAA==.',
Fr='Frostborne:BAABNQAECn8dAAISAAgKyxiBMQBkAgASAAgKyxiBMQBkAgAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frostystomp:BAAANQAECgcIBwABNQAFFAMIBQATANkcAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAADAAAAAA==.',
Fu='Funeral:BAAANQAECggIDwABNQAECgkJJwAJAD8gAA==.',
Ga='Gamjee:BAAANQAECgQIBwAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Gl='Glyndin:BAAANQADCgcIDQAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAQICAAeAPoiAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQAECgMIBAAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAAANQAECgMIBgAAAA==.',
Gu='Guilliman:BAABNQAECn8bAAIHAAgKghtXXAB0AgAHAAgKghtXXAB0AgAAAA==.Gulaj:BAABNQAECn8hAAIJAAgKLRPQdQAhAgAJAAgKLRPQdQAhAgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgUICgAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECn8lAAIPAAkK1hkfLgCtAgAPAAkK1hkfLgCtAgAAAA==.',
Hi='Hiruken:BAAANQADCgYIDwAAAA==.',
Ho='Hope:BAABNQAECn8WAAMBAAkK2BJTHwAtAgABAAkK2BJTHwAtAgAeAAEK6QMddgAKAAABNQAECgkKGgARAE8YAA==.Hortzel:BAAANQAECgQIBwAAAA==.Hotrollz:BAAANQADCgUIBQABNQAECgcIFwAYAEEOAA==.Howdoitotem:BAABNQAECn8gAAMbAAkKUhmpMQCwAgAbAAkKUhmpMQCwAgAcAAMK3gfO9gB3AAAAAA==.',
Hu='Hulkx:BAAANQAECgQICgAAAA==.Humaa:BAABNQAECn8eAAIGAAcKQBzXegAxAgAGAAcKQBzXegAxAgAAAA==.Huntus:BAABNQAECn8qAAIJAAgKBR1dOgC5AgAJAAgKBR1dOgC5AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icewiz:BAAANQABCgUIBQABNQAECgUICQADAAAAAA==.Icy:BAABNQAECn8VAAIHAAkKShUfYgBkAgAHAAkKShUfYgBkAgAAAA==.',
Im='Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECn8sAAIYAAkKrx0FDQAZAwAYAAkKrx0FDQAZAwAAAA==.',
Iz='Izuu:BAAANQAECgYICAAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQJBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAABNQAECn8oAAMgAAkKqhu5GgD/AQAgAAcKpRq5GgD/AQAdAAQKFhlJYgAjAQAAAA==.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAABNQAECn8UAAILAAcKVgucqQB6AQALAAcKVgucqQB6AQAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECgQIBwADAAAAAA==.',
Ka='Kankiro:BAAANQADCggIEAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQAECgUIDQAAAA==.Kelemvor:BAAANQAECggIEAAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAABNQAECn8ZAAIEAAkK8BZ5MwA9AgAEAAkK8BZ5MwA9AgAAAA==.',
Ki='Kimmy:BAAANQAECgYICwAAAA==.',
Kl='Kleenex:BAABNQAECn8bAAIVAAgKfRYwCABeAgAVAAgKfRYwCABeAgAAAA==.',
Ko='Koldiss:BAAANQADCgQIBAAAAA==.',
Kr='Krueger:BAAANQAECgYIBwABNQAECggIEwADAAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAFFAMIBgAcAEAIAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECn8nAAIJAAkKPyAxFgBBAwAJAAkKPyAxFgBBAwAAAA==.Leethalfu:BAABNQAECn8aAAIMAAkKoBeLCQCEAgAMAAkKoBeLCQCEAgAAAA==.Leethalrot:BAAANQAECgEIAQABNQAECgkJGgAMAKAXAA==.Legosi:BAAANQAECgYIEwAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECn8mAAILAAkKAh+xHwADAwALAAkKAh+xHwADAwAAAA==.Leviosa:BAAANQABCgUIBwAAAA==.',
Lh='Lhux:BAABNQAECn8rAAIJAAkK9h11KQDxAgAJAAkK9h11KQDxAgABNQAECgYIEQADAAAAAA==.Lhuxi:BAAANQAECgYIEQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAABNQAECn8kAAIZAAkKoyL6CwBqAwAZAAkKoyL6CwBqAwAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Ly='Lyxxie:BAABNQAECn8kAAMOAAkKBxz3JABnAgAOAAkKBxz3JABnAgASAAUKCQuBjADuAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECgIIAgAAAA==.Manafart:BAAANQADCgYJBgABNQAECggIJwAHAEYQAA==.Manbearpïg:BAAANQAECgQIBAAAAA==.Matsumushi:BAABNQAECn8mAAMMAAgKWBakDgAHAgAMAAgKWBakDgAHAgAhAAYKagfaQgD8AAAAAA==.',
Mc='Mcnastyy:BAAANQADCgYICgAAAA==.',
Me='Mefesto:BAABNQAECn8dAAIUAAkKvg/MswAaAgAUAAkKvg/MswAaAgABNQABCgQIBgADAAAAAA==.Mellore:BAAANQAECgIIAgABNQAECgkJJAAZAKMiAA==.Metsutan:BAABNQAECn8lAAIgAAgKeR43CwC/AgAgAAgKeR43CwC/AgAAAA==.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQAECgUICAAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgEIAQAAAA==.',
Na='Naes:BAAANQADCgcJDAAAAA==.Nazuresh:BAAANQADCggICAABNQAECgUIFgAZAAwPAA==.',
Ne='Necrodamus:BAAANQAECgQIBAAAAA==.Nekcrotic:BAABNQAECn8VAAMLAAgKshNDmgCfAQALAAcKuRJDmgCfAQAKAAIKIxAyWAB2AAAAAA==.Nekromant:BAABNQAECn8gAAMKAAcKRA1RSACmAAALAAYK2gk61gAYAQAKAAMKiA1RSACmAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgQIAwAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBQAAAA==.Nintales:BAAANQADCgcIBwAAAA==.',
No='Nohric:BAAANQAECgYIDwAAAA==.Noobieone:BAAANQADCggICAAAAA==.Norsem:BAAANQAECgUICQAAAA==.',
Ny='Nymera:BAAANQADCggIEQABNQAECgEIAQADAAAAAA==.',
Oh='Ohlorn:BAACNQAFFH8GAAIiAAQKEQ+VAwBBAQAiAAQKEQ+VAwBBAQA1AAQKfygAAiIACQoEJEoEAE8DACIACQoEJEoEAE8DAAAA.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onfleek:BAAANQAECgIIAwAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgQIBAAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQJBAADAAAAAA==.Palysuk:BAAANQADCggIFAAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAACNQAFFH8QAAMBAAUKKR2uBADWAQABAAUKKR2uBADWAQAZAAMKlA2mGADfAAA1AAQKfygABAEACQpWJukAANIDAAEACQpWJukAANIDABkAAQotGqKkAEwAABMAAQoAAKVAADUAAAE1AAQKBwgLAAMAAAAA.Parstout:BAAANQAECgcICwAAAA==.Pawsitivity:BAABNQAECn8mAAIbAAgKOSJEIAAIAwAbAAgKOSJEIAAIAwAAAA==.',
Pd='Pdbm:BAABNQAECn8aAAIGAAgK2R+bTgClAgAGAAgK2R+bTgClAgAAAA==.',
Pe='Petr:BAABNQAECn8oAAMPAAgKYx0cMAClAgAPAAgKYx0cMAClAgAYAAEKAAAOjQAcAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECn8jAAIRAAgK3h2tLgCpAgARAAgK3h2tLgCpAgAAAA==.',
Ph='Physix:BAAANQAECgEIAQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAABNQAECn8jAAMOAAkKLx6rFQDbAgAOAAkKcR2rFQDbAgASAAYKdxP+ZAB5AQAAAA==.',
Pr='Priestus:BAAANQAECgEIAQAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQABNQAECgkJHgAcAMwgAA==.',
Py='Pyraxx:BAABNQAECn83AAIVAAkKyiPFAACxAwAVAAkKyiPFAACxAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFH8VAAIjAAYKExrkAwAMAgAjAAYKExrkAwAMAgA1AAQKfyUAAiMACQrjIhUJAEQDACMACQrjIhUJAEQDAAAA.',
Qu='Quatermaine:BAAANQAECgUIDgAAAA==.',
Ra='Radovan:BAACNQAFFH8PAAMLAAUKFSBaFQBPAQALAAQKHCRaFQBPAQAKAAEKCBi7GgBQAAA1AAQKfzEAAwsACQpNJmQPAFQDAAsACAowJmQPAFQDAAoABQpDIKcaAJYBAAAA.Rayael:BAAANQAECgQICAABNQAECgkJLwAVAC8aAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAAANQAECgQICgABNQAECgUIFgAZAAwPAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECn8gAAMcAAgKTBVqlQBOAQAcAAYKXBFqlQBOAQAbAAYKBAgZxAAGAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Roktar:BAAANQADCgcICQABNQAECgEIAQADAAAAAA==.Rosaelyia:BAAANQADCgYIBgABNQAECgYIEQADAAAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECn8cAAIRAAgK4SCRJADXAgARAAgK4SCRJADXAgAAAA==.',
Sa='Samavati:BAAANQAECgYIEQAAAA==.Sarah:BAABNQAECn8tAAMPAAkKXiToAwCwAwAPAAkKXiToAwCwAwAkAAMKngu6GwCHAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFH8MAAIgAAUKaghACABwAQAgAAUKaghACABwAQA1AAQKfygAAiAACQotHOUMAKUCACAACQotHOUMAKUCAAAA.Sassyface:BAABNQAECn8pAAIKAAkKHw4/DAAyAgAKAAkKHw4/DAAyAgAAAA==.',
Se='Sellit:BAAANQAECgEIAQAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECggIBwABNQAECgkJJwAQAK4dAA==.Shadowdin:BAABNQAECn8eAAIRAAkKyhp6JgDOAgARAAkKyhp6JgDOAgAAAA==.Shamzilla:BAABNQAECn8oAAIbAAgKABuCMwCoAgAbAAgKABuCMwCoAgAAAA==.Shockblast:BAAANQADCggIFgAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECggIIQAKAC0QAA==.',
Si='Sibbrena:BAABNQAECn8jAAIYAAkKYBxoEwDKAgAYAAkKYBxoEwDKAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAAANQAECgUIDgAAAA==.Sinemon:BAAANQAECgQIBwAAAA==.Sinz:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAABNQAECn8nAAMRAAkKyyGvCgByAwARAAkKyyGvCgByAwAGAAQKNR/83QBZAQAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAAANQAECgQICgAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAUIDwALABUgAA==.',
Sm='Smartlurth:BAAANQAECgIIAgAAAA==.',
Sn='Snowjob:BAAANQAECgYIEgAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgcIHQAKAC0XAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgQIBwAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQABCgQIBQAAAA==.Stead:BAAANQAECgIIAgAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAAANQAECggIEwAAAA==.Stellar:BAAANQAECgQIBgABNQAECgkJNgAgAEggAA==.Stelthme:BAABNQAECn8bAAMdAAcKYBTXPADXAQAdAAcK9hPXPADXAQAgAAIKLw+4RACLAAABNQAECgkJNgAgAEggAA==.Strongman:BAAANQAECgIIAgAAAA==.',
Sw='Sweetie:BAAANQABCgYICAAAAA==.',
Ta='Takeshì:BAAANQADCgcIBwABNQAECgUIFgAZAAwPAA==.Tanìs:BAAANQAECgYICQAAAA==.Tarle:BAAANQAECgYIDgAAAA==.Tazath:BAAANQAECgUICAABNQAFFAMIBQATANkcAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECn8ZAAIEAAgKFBZFNwAqAgAEAAgKFBZFNwAqAgAAAA==.',
To='Tonhãotrovão:BAAANQAECgQIBAABNQAECgQIBAADAAAAAA==.',
Tr='Trashii:BAABNQAECn8nAAMlAAgK1w1DBwAIAgAlAAgK1w1DBwAIAgAIAAMKHwJOcQBrAAAAAA==.Treevive:BAAANQAECgUIBQABNQAECggIJAAPADwjAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAABNQAECn8hAAIbAAkK8R3zMwCmAgAbAAkK8R3zMwCmAgAAAA==.Trystan:BAABNQAECn8kAAIGAAgKXBAVowDVAQAGAAgKXBAVowDVAQAAAA==.',
Ts='Tsinga:BAAANQAECgQIBQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAACNQAFFH8GAAIMAAMKSRZ/BgDrAAAMAAMKSRZ/BgDrAAA1AAQKfyYAAgwACQohH0kFAA4DAAwACQohH0kFAA4DAAAA.Twohammered:BAAANQADCgcICwABNQAFFAMIBgAMAEkWAA==.',
['Tø']='Tøm:BAACNQAFFH8SAAIGAAYKxx4gBQAJAgAGAAYKxx4gBQAJAgA1AAQKfysAAgYACQpxI7EhADsDAAYACQpxI7EhADsDAAAA.',
Ul='Ullirus:BAAANQADCggIEQAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQAECgEIAQAAAA==.Unbiased:BAABNQAECn8pAAMSAAkKuhmeNABUAgASAAcK4RueNABUAgAOAAkKAxeZNAAEAgAAAA==.Unholyblodd:BAAANQADCggIIAAAAA==.Unshookable:BAABNQAECn8yAAICAAkKoyIyBQBOAwACAAkKoyIyBQBOAwAAAA==.',
Ur='Ursos:BAAANQAECgEIAQAAAA==.Urìko:BAAANQAECgQIBAAAAA==.',
Va='Vaelor:BAAANQADCgQIBAAAAA==.Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQAECgUIBQAAAA==.',
Vi='Vika:BAAANQADCggIDAABNQAECgEIAQADAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAAANQAECgUIDgAAAA==.Voidlockus:BAAANQAECgEIAQAAAA==.',
Vu='Vulcin:BAABNQAECn8fAAIRAAkKHRvGJQDRAgARAAkKHRvGJQDRAgABNQAECgkJNwAVAMojAA==.',
Wa='War:BAAANQADCgQIBAABNQAFFAMIBQAKANwUAA==.Wariuus:BAAANQAECgQIBAAAAA==.Watercupp:BAAANQAECgUICQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgUIBgAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAABNQAECn8cAAMcAAgKRxxuMACdAgAcAAgKRxxuMACdAgAbAAMKRhmY4wDKAAAAAA==.Windsor:BAAANQADCgEIAQAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQADCgcIBwADAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Za='Zandramadas:BAABNQAECn8jAAMBAAkKMhn7GABxAgABAAkKMhn7GABxAgAZAAgKGA9ASQC/AQAAAA==.Zaraline:BAAANQAECgYIEQAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgQIBwAAAA==.',
Zo='Zoomiez:BAAANQAECgIIBAAAAA==.',
Zp='Zpai:BAABNQAECn8YAAMMAAgKphYaDwD9AQAMAAgKphYaDwD9AQAhAAYKbAWpSwDFAAAAAA==.',
Zy='Zyfae:BAAANQAECggIBAAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
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
