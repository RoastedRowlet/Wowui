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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Monk-Windwalker','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Elemental','Druid-Balance','Monk-Brewmaster','Paladin-Protection','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Frost','Shaman-Enhancement','Warrior-Fury','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJOAABAEggAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnfEAAeAQACAAQJ6RnfEAAeAQAuAAQKfxsAAgIACQldIOcFALECAAIACQldIOcFALECAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJMgADADIMAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8pAAMEAAgJBw7NCgBrAQAEAAgJmA3NCgBrAQAFAAcJiAqvSgD9AAAAAA==.Altruist:BAABLgAECn8fAAMGAAgJ3RtADwAvAgAGAAgJ3RtADwAvAgAHAAIJnATlBQFAAAABLgAECgkJPwACAPcbAA==.',
Am='Amaethon:BAABLgAECn8VAAIIAAkJeAreJgAZAQAIAAkJeAreJgAZAQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8/AAIJAAkJER9vDQDoAgAJAAkJER9vDQDoAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn84AAIBAAkJSCDYBABAAwABAAkJSCDYBABAAwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIKAAgJTAgWOwD6AAAKAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Around:BAAALgAECgUJBgAAAA==.Arrogant:BAAALgADCgMJAwAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn83AAQEAAkJghrBAgCEAgAEAAkJghrBAgCEAgAMAAQJpxSuHwD0AAAFAAEJsQPVmQAkAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8/AAINAAkJEhbZBAA6AgANAAkJEhbZBAA6AgAAAA==.',
Az='Azbogah:BAAALgAECgUJDgAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAOAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAAPAGccAA==.Balthenor:BAACLgAFFH8GAAIQAAIJqxMpIgCoAAAQAAIJqxMpIgCoAAAuAAQKfx4AAhAACAn+IZMRAAQDABAACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8sAAIKAAkJyRokDgC3AgAKAAkJyRokDgC3AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAALAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB9YcwBUAQADAAYJRB9YcwBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJCAAAAA==.Birdymage:BAABLgAECn8ZAAIRAAUJHBTexgD8AAARAAUJHBTexgD8AAAAAA==.',
Bl='Blightbeard:BAABLgAECn8YAAISAAgJ6gkziwBLAQASAAgJ6gkziwBLAQAAAA==.Blîss:BAAALgAECgcJCgAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAcJIAASAHkUAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.',
Br='Brut:BAABLgAECn8hAAIHAAkJNx5FRwCtAQAHAAkJNx5FRwCtAQAAAA==.',
Bu='Bustus:BAABLgAECn80AAITAAkJAg2YQQCIAQATAAkJAg2YQQCIAQAAAA==.',
Ca='Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8fAAQUAAgJWhWrHQDXAQAUAAgJWhWrHQDXAQABAAYJ+RY4JQCjAQAVAAMJexReRwDEAAAAAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8gAAIQAAYJNg9OugAOAQAQAAYJNg9OugAOAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8gAAIRAAYJaxMIoQA2AQARAAYJaxMIoQA2AQAAAA==.Cherub:BAAALgADCgMJAwAAAA==.Chilly:BAABLgAECn8VAAMQAAYJSgwjqwAsAQAQAAYJSgwjqwAsAQAWAAEJrwGgoAAYAAABLgAFFAUJFAAKAOYSAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn8/AAICAAkJ9xuWBwCGAgACAAkJ9xuWBwCGAgAAAA==.Corannis:BAABLgAECn8zAAIXAAkJShhXFABGAgAXAAkJShhXFABGAgAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJDQAYAKIJAA==.',
Cr='Cranberries:BAABLgAECn8bAAMVAAcJyxeyJgCLAQAVAAYJpxiyJgCLAQABAAcJNRDRLgBjAQAAAA==.Crockett:BAAALgADCggJCAABLgAECgUJEAALAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgIJAgAAAA==.Curtis:BAAALgAECgYJDQABLgAECgkJMQAZAEEfAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAECgkJPAAGANEVAA==.Damaso:BAAALgAECgMJAwAAAA==.Dantez:BAACLgAFFH8FAAMYAAUJpw1KJgD2AAAYAAQJpw1KJgD2AAATAAEJDA37aQBBAAAuAAQKfx8AAxgACQk8IuwDACMDABgACQk8IuwDACMDABMABgncDj1eABkBAAAA.Darkgenie:BAAALgAECgcJDQAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8vAAIHAAkJEBvOHQBeAgAHAAkJEBvOHQBeAgAAAA==.Dawnmane:BAAALgAECggJCAAAAA==.',
De='Delderach:BAABLgAECn8iAAIaAAcJGBZIFACGAQAaAAcJGBZIFACGAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn87AAISAAkJ+ByQGgClAgASAAkJ+ByQGgClAgAAAA==.',
Di='Dirkette:BAABLgAECn8qAAIBAAkJdARwNABDAQABAAkJdARwNABDAQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJKgABAHQEAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJKgABAHQEAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAAALgADCgEJAQABLgAECgkJPAAGANEVAA==.Dokai:BAABLgAECn84AAIPAAkJZxw4CwCMAgAPAAkJZxw4CwCMAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgcJFAAKAL8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJOQAbAHcWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBgAAAA==.Drewella:BAAALgADCgkJCQAAAA==.',
El='Elaenei:BAAALgADCgkJLAAAAA==.Eliance:BAABLgAECn8iAAINAAcJ2QQvFADiAAANAAcJ2QQvFADiAAAAAA==.Elienn:BAAALgAECgMJBAAAAA==.Elsewhere:BAABLgAECn8fAAMFAAkJkw8JJwCoAQAFAAkJkw8JJwCoAQAMAAEJwQhUQAAkAAAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8qAAIbAAkJmhbkFADFAQAbAAkJmhbkFADFAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgIJAgAAAA==.',
Fa='Fatherbetter:BAAALgAECgYJCAABLgAECgkJJQAHAHMhAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAASAHQGAA==.Feloras:BAAALgAECgYJEAAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.',
Fo='Foxina:BAAALgAECgQJBAAAAA==.',
Fu='Fusaa:BAABLgAECn9IAAIcAAkJKxkSIABiAgAcAAkJKxkSIABiAgAAAA==.',
Ga='Gahzoo:BAAALgADCgQJAQAAAA==.Gallindo:BAAALgAECgEJAQABLgAECgcJFgAdAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garu:BAAALgADCgQJBAAAAA==.',
Ge='Gelst:BAAALgAECgMJBAAAAA==.Gerbzarrion:BAABLgAECn8gAAIRAAcJRQk3sAAeAQARAAcJRQk3sAAeAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn88AAIGAAkJ0RVZEgAEAgAGAAkJ0RVZEgAEAgAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8JAAISAAQJjgxKgAADAQASAAQJjgxKgAADAQAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Hawknnin:BAABLgAECn8fAAIWAAcJjCCWDwCdAgAWAAcJjCCWDwCdAgAAAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8IAAIDAAMJKw8/XwDeAAADAAMJKw8/XwDeAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgMJAwAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAVAMsXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8dAAISAAkJ1Q2xWAC5AQASAAkJ1Q2xWAC5AQAAAA==.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAdAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8wAAMTAAgJCBy1FwCGAgATAAgJCBy1FwCGAgAYAAEJWAOkowAaAAAAAA==.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8WAAIQAAcJrhx8TwDXAQAQAAcJrhx8TwDXAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIeAAkJ0hcqBwAQAgAeAAkJ0hcqBwAQAgAAAA==.Kaimare:BAAALgADCgUJCgAAAA==.Kandistars:BAABLgAECn8oAAIYAAkJoBGfIADAAQAYAAkJoBGfIADAAQAAAA==.Kasia:BAABLgAECn8kAAIJAAgJnhuIJgAjAgAJAAgJnhuIJgAjAgAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAISAAgJiBZEXwCoAQASAAgJiBZEXwCoAQAAAA==.Kirarah:BAABLgAECn85AAIDAAgJ0CRUCwD2AgADAAgJ0CRUCwD2AgAAAA==.Kirarose:BAACLgAFFH8UAAMUAAYJexnQCwCcAQAUAAYJexnQCwCcAQAVAAIJ2gFyMwBDAAAuAAQKfxwAAxQACQmmIi8RAE4CABQACQmmIi8RAE4CABUAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn84AAIKAAkJng/pLQC/AQAKAAkJng/pLQC/AQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8VAAIFAAgJkwg5QQAhAQAFAAgJkwg5QQAhAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgALAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIOAAgJRhuhBQAqAgAOAAgJRhuhBQAqAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8tAAIDAAkJOyG1DwDPAgADAAkJOyG1DwDPAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8NAAIYAAMJogm0NAClAAAYAAMJogm0NAClAAAuAAQKfz0AAwgACQn1GGcKADsCAAgACQn1GGcKADsCABgACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8MAAMdAAMJdwXuJgCXAAAdAAMJfAHuJgCXAAADAAIJhwd8igCAAAAuAAQKfyUAAwMACQmKCRV7AEQBAAMACAkjChV7AEQBAB0AAgnOBotPAG4AAAAA.',
Lj='Ljósálfr:BAABLgAECn9BAAICAAkJLyTdAQA1AwACAAkJLyTdAQA1AwAAAA==.',
Lo='Lochramae:BAABLgAECn85AAIbAAkJdxZ1FwCoAQAbAAkJdxZ1FwCoAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAABLgAECn8lAAIHAAgJcyFKFgCPAgAHAAgJcyFKFgCPAgAAAA==.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCggJDgABLgAECgcJFAAKAL8VAA==.Magjistar:BAAALgADCgMJAwAAAA==.Mahangi:BAAALgADCgkJFgAAAA==.Mamimisan:BAABLgAECn8xAAIJAAkJvB9dCQAZAwAJAAkJvB9dCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAQAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJDQAAAA==.',
Mi='Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMIAAcJoRjgFQCfAQAIAAcJoRjgFQCfAQATAAMJ7AbYrwBWAAAAAA==.Mizeroni:BAAALgADCgcJBwAAAA==.Mizkat:BAABLgAECn8oAAQIAAkJ+xrECABcAgAIAAkJ+xrECABcAgAfAAEJSw5TTwA1AAATAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn8yAAMDAAgJMgwqZgBzAQADAAgJMgwqZgBzAQAgAAEJ1QFYRQAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQdAAgJlSVXBgCfAgAdAAcJ4iRXBgCfAgADAAYJliQoPwDhAQAgAAIJ/SPuHgCzAAAAAA==.',
['Më']='Mërcy:BAAALgAECgQJBQAAAA==.',
Na='Naklus:BAAALgAECgcJDwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8lAAIJAAkJRhSDIQBCAgAJAAkJRhSDIQBCAgABLgAECgkJPAAGANEVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgcJDAAAAA==.',
No='Noblesfan:BAAALgADCgMJAwAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAAALgAFFAQJBAABLgAFFAgJGgAHACshAA==.',
Or='Orees:BAAALgAECgEJAQAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIfAAYJMCC+DQDVAQAfAAYJMCC+DQDVAQAAAA==.',
Pa='Parne:BAAALgADCggJDQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgMJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn80AAIWAAkJ3xmXEQCGAgAWAAkJ3xmXEQCGAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn8/AAIhAAkJyhIgBwDiAQAhAAkJyhIgBwDiAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJMgADADIMAA==.Ranron:BAAALgAECgUJCQAAAA==.Rassaphore:BAABLgAECn8hAAIPAAgJfiHMCQCkAgAPAAgJfiHMCQCkAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8kAAIiAAgJwxWJDACsAQAiAAgJwxWJDACsAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAHADceAA==.Rionach:BAABLgAECn8/AAIIAAkJLwn+KAAMAQAIAAkJLwn+KAAMAQAAAA==.Ritsara:BAABLgAECn8UAAIaAAcJyQ2eJQDlAAAaAAcJyQ2eJQDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgALAAAAAA==.Rivon:BAABLgAECn8jAAMWAAkJgxhQIAD+AQAWAAgJWBdQIAD+AQAQAAEJagttdwE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAHAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMVAAkJYh/QCwCnAgAVAAgJPiDQCwCnAgAUAAEJAhnDdgBNAAAAAA==.',
Se='Seanan:BAABLgAECn8hAAIjAAkJlyAjAgACAwAjAAkJlyAjAgACAwABLgAECgkJKQAQAHgdAA==.Seanx:BAABLgAECn8pAAMQAAkJeB3wIQB8AgAQAAkJeB3wIQB8AgAaAAYJhhKVIwD0AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8IAAISAAIJrhko1wCJAAASAAIJrhko1wCJAAAAAA==.Shigurexx:BAABLgAECn9DAAMDAAkJVyC8DADqAgADAAkJVyC8DADqAgAgAAcJMhn2CwChAQAAAA==.Shoe:BAABLgAECn9HAAMEAAkJBhxtAwBfAgAEAAkJBhxtAwBfAgAFAAcJoBHzJAC0AQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIQAAcJ8gMQ8wDDAAAQAAcJ8gMQ8wDDAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgQJBQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgcJBAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Steelbutt:BAAALgADCggJCgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBgAAAA==.',
Ta='Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8kAAICAAgJlxbfFAChAQACAAgJlxbfFAChAQAAAA==.Tarkahunt:BAAALgADCgQJBAAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIIAAQJiBCVFADXAAAIAAQJiBCVFADXAAAuAAQKfxwAAggACQmwH28FALACAAgACQmwH28FALACAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAIRAAYJNSC8VgDWAQARAAYJNSC8VgDWAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.',
To='Toom:BAABLgAECn8iAAIDAAcJhA4mcABbAQADAAcJhA4mcABbAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgIJAgABLgAECgkJPAAGANEVAA==.Trophyhubby:BAABLgAECn8qAAMUAAkJIAfKMwBIAQAUAAkJIAfKMwBIAQAVAAcJ5QxVOgAJAQAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAECgkJQQACAC8kAA==.Tuladrin:BAAALgADCgQJBAAAAA==.Tumbler:BAAALgADCgkJCQABLgAECgkJMQAZAEEfAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8gAAMSAAcJeRSPIwDTAQASAAYJeRSPIwDTAQAbAAEJAACfVgAAAAAuAAQKfx8AAxIACQnZHtkiALQCABIACAn/HtkiALQCABsAAwkMGq4yAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAcJIAASAHkUAA==.',
Us='Usato:BAABLgAECn8UAAIKAAcJvxVtLgC8AQAKAAcJvxVtLgC8AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8cAAIQAAcJMwluwgACAQAQAAcJMwluwgACAQAAAA==.Valvet:BAAALgADCgkJLgAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAISAAUJdAY3hQD6AAASAAUJdAY3hQD6AAAuAAQKfxcAAxIACQlHExl/AGIBABIACAmdCRl/AGIBABsABQm7G48jADMBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJCQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIHAAcJHiTjJQBvAgAHAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwALAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgALAAAAAA==.',
Vy='Vylus:BAAALgAECgYJDgAAAA==.',
['Vá']='Vásh:BAAALgADCgkJEQAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgIJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8rAAIDAAkJXSJJBwAhAwADAAkJXSJJBwAhAwAAAA==.Windee:BAABLgAECn8ZAAIPAAYJqg1MRADrAAAPAAYJqg1MRADrAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMgAAgJdwt7GwDPAAADAAYJzg4EjwAcAQAgAAcJkwZ7GwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMOAAQJuw6rDQCjAAAcAAMJgAgkgQC+AAAOAAIJuhWrDQCjAAAuAAQKfyYABA4ACQk0HYkEAFECAA4ACQk0HYkEAFECABwABgmmEhxwAFkBACEAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAABLgAECn9FAAIkAAkJNSFzBQAIAwAkAAkJNSFzBQAIAwAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8QAAIjAAQJWg0JCwAMAQAjAAQJWg0JCwAMAQAuAAQKfxsAAiMACQnTHKMFAIICACMACQnTHKMFAIICAAAA.Zatika:BAABLgAECn85AAMRAAkJuhmuNwA3AgARAAkJxRauNwA3AgAlAAcJ1xgrBQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8iAAIYAAcJ8QihRAD2AAAYAAcJ8QihRAD2AAAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
