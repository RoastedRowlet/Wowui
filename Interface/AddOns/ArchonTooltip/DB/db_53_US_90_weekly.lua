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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Druid-Balance','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Arcane','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Rogue-Outlaw','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','DeathKnight-Blood','Druid-Guardian','Paladin-Holy','DeathKnight-Frost','Priest-Holy','Mage-Frost','Priest-Shadow','Druid-Feral','Paladin-Protection','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abacus:BAAANQAECggIDgAAAA==.',
Ad='Adam:BAACNQAFFH8aAAQBAAkKzRd5BwDxAQABAAcKCRV5BwDxAQACAAIKdB3xCwCgAAADAAEKNRlPEwBTAAA1AAQKfzwABAIACgoSJY0IAHQCAAEACQq3JAEnAHQCAAIACApRG40IAHQCAAMAAwr5IAMmAFMAAAAA.Adumb:BAAANQAECgQIBAABNQAFFAkJFwAEAKkaAA==.',
Ak='Akurama:BAAANQAECgYICQAAAA==.',
Al='Allfrowns:BAAANQAECgcJDgAAAA==.Allsmiles:BAABNQAECn8YAAMFAAgKhCFxDwAzAgAFAAgKhCFxDwAzAgAGAAQKpBG4AQHZAAAAAA==.Allura:BAAANQAECgQIBQAAAA==.Alunaris:BAAANQAECgEJAgAAAA==.',
Am='Amoon:BAABNQAECn8+AAMHAAkKaxYEHADIAQAHAAkKaxYEHADIAQAIAAIKZxA7KgBiAAAAAA==.',
An='Ancalagon:BAAANQADCgQIBAAAAA==.',
Ar='Archymedes:BAAANQAECgIIAQAAAA==.Arckady:BAAANQAECgYICAAAAA==.Array:BAAANQADCggICAAAAA==.Artharius:BAABNQAECn8yAAMJAAoK1SLgDACPAgAJAAoK1SLgDACPAgAKAAUKNxQgHAAkAQAAAA==.',
As='Asbestos:BAAANQAECgMIAwAAAA==.',
Au='Auburnbeard:BAAANQAECgEJAQAAAA==.',
Av='Averle:BAAANQAECgIIAgAAAA==.',
Ba='Badchoices:BAAANQAECgEIAQAAAA==.Badkittie:BAAANQADCgUICgAAAA==.Baretta:BAABNQAECn8eAAQFAAcK8A6RHwABAQAFAAcK8A6RHwABAQAGAAYKyAXNCgHHAAALAAIK4wd0MgA4AAAAAA==.',
Be='Beefsnake:BAEBNQAECn8wAAIMAAoKehUnLAB5AgAMAAoKehUnLAB5AgAAAA==.Beefytips:BAAANQADCgIJAgAAAA==.Belinda:BAAANQAECgUICgABNQAFFAUICAANAJwZAA==.Bettyßaraxus:BAABNQAECn8mAAIBAAoKFROTQwALAgABAAoKFROTQwALAgAAAA==.Bettyßarrage:BAAANQADCgUIBQABNQAECgoKJgABABUTAA==.Bettyßlight:BAAANQADCgUICAABNQAECgoKJgABABUTAA==.',
Bi='Bigunsforu:BAABNQAECn8WAAIOAAoKkghkewDFAQAOAAoKkghkewDFAQAAAA==.',
Bl='Blóódlust:BAAANQAECgQIBAAAAA==.',
Bo='Bogs:BAABNQAECn8zAAIPAAoK4h7DLQCJAgAPAAoK4h7DLQCJAgAAAA==.Bolomorte:BAAANQADCgYIBgAAAA==.Boragish:BAABNQAECn8cAAIBAAkKVA7TcACIAQABAAkKVA7TcACIAQAAAA==.Boulderfist:BAAANQADCggIFAAAAA==.',
Br='Brolic:BAABNQAECn88AAIQAAoKkx0/EwCKAgAQAAoKkx0/EwCKAgAAAA==.',
Bu='Bubbleman:BAAANQADCgQIBAAAAA==.Bubblestomps:BAAANQADCgMIAwAAAA==.Burial:BAAANQAECgYICAAAAA==.Burntchicken:BAAANQABCgMIAwAAAA==.',
Bw='Bwonsamdy:BAAANQAECgIIAgAAAA==.',
['Bä']='Bämboo:BAABNQAECn8dAAIRAAgKUhomEQBsAgARAAgKUhomEQBsAgAAAA==.',
Ca='Cail:BAEBNQAECn8fAAISAAcKzAwnpQBKAQASAAcKzAwnpQBKAQAAAA==.Calamìty:BAAANQAECgMIAwABNQAECggIBQATAAAAAA==.Calisa:BAABNQAECn8/AAIUAAkK6hlrAgAKAgAUAAkK6hlrAgAKAgAAAA==.Callowz:BAAANQABCgYIBAAAAA==.Cantstandya:BAABNQAECn8vAAIVAAoKsyGdIQDaAgAVAAoKsyGdIQDaAgAAAA==.Carnifex:BAABNQAECn8VAAMSAAcK+BZRigCKAQASAAYK8xhRigCKAQAWAAcKLA7FjgBkAQABNQAECgkJGgABACEWAA==.',
Ce='Ceryph:BAAANQAECgEIAQAAAA==.',
Ch='Charis:BAAANQADCgEIAQAAAA==.Chewbub:BAAANQADCgIIAgAAAA==.Chigutotems:BAEBNQAECn8wAAIWAAoKqh2SFQAiAwAWAAoKqh2SFQAiAwAAAA==.Chow:BAAANQABCgUIBQABNQAECgYICAATAAAAAA==.Chozen:BAACNQAFFH8IAAIXAAMK5yHuDAAqAQAXAAMK5yHuDAAqAQA1AAQKfzMAAhcACgowJDoLADADABcACgowJDoLADADAAAA.Chroniccloud:BAAANQAECgEIAQAAAA==.',
Co='Cornelius:BAAANQAECgYIDwAAAA==.Corporicky:BAAANQAECgEIAQAAAA==.Coulee:BAAANQADCgUICwABNQAECgoKIgAQAB0aAA==.',
Cr='Cronicpain:BAAANQAECggICgAAAA==.',
Cy='Cymbi:BAAANQABCgQIAwAAAA==.',
Da='Daks:BAAANQADCgQIBAAAAA==.Darklucrezia:BAABNQAECn83AAMOAAoKaxlEaQBBAgAOAAkKwxpEaQBBAgAEAAEKBBDAaQAxAAAAAA==.Darkpyro:BAAANQADCggIEgAAAA==.',
De='Deetsy:BAAANQADCgYICAAAAA==.Dextrose:BAAANQAECggICwAAAA==.',
Di='Dicey:BAABNQAECn8aAAMBAAkKIRbJSAD6AQABAAkKIRbJSAD6AQACAAEK/A2ZdQA4AAAAAA==.',
Dk='Dkbig:BAAANQAECgYIDwAAAA==.',
Dr='Dracarius:BAAANQAECgYICAAAAA==.Drtypinkcake:BAAANQAECgYIDwAAAA==.Druidcant:BAAANQADCgYIBgAAAA==.Drworldwide:BAAANQAECggICQAAAA==.Dryad:BAAANQAECgYICAAAAA==.',
Du='Durkk:BAABNQAECn9EAAIYAAkKaSDwFABkAgAYAAkKaSDwFABkAgAAAA==.Durza:BAAANQADCggICAAAAA==.',
Dw='Dwayne:BAAANQAECgYIBgAAAA==.',
['Dä']='Dännydevito:BAAANQADCgMIBAAAAA==.',
Ea='Easyheal:BAAANQADCgYIBgABNQAECgYICAATAAAAAA==.',
El='Elric:BAAANQADCgYIBgAAAA==.',
En='Enss:BAAANQADCgUJBQAAAA==.',
Es='Estara:BAABNQAECn9CAAIZAAkKgg81JgBTAQAZAAkKgg81JgBTAQAAAA==.',
Et='Etali:BAABNQAECn84AAILAAkKexq2CQADAgALAAkKexq2CQADAgAAAA==.Etherious:BAAANQAECgUICAABNQAECgoKGAAaAA8RAA==.',
Fa='Fanis:BAABNQAECn8tAAIEAAgKowxbIQBiAQAEAAgKowxbIQBiAQAAAA==.Faynor:BAAANQADCgQIBAAAAA==.',
Fi='Fibo:BAAANQADCgQIBAAAAA==.',
Fl='Flashis:BAABNQAECn8XAAQJAAoKFQu0LwCaAQAJAAoKAQu0LwCaAQARAAUKWQM8OQClAAAKAAMK+gZHHgByAAAAAA==.Floor:BAAANQABCgIIAgAAAA==.Florago:BAAANQAECgYICAAAAA==.',
Fo='Force:BAAANQAECgEIAgAAAA==.',
Fr='Frakir:BAABNQAECn9EAAMWAAkKPhxWJgCVAgAWAAkKPhxWJgCVAgASAAEKAAApUwEkAAAAAA==.',
Fu='Furrypaw:BAABNQAECn83AAMRAAkK5CAoCADnAgARAAkK5CAoCADnAgAJAAEKAADocgAnAAAAAA==.Fuzzyy:BAAANQADCgUIBQABNQADCgQIBAATAAAAAA==.',
Fw='Fwapp:BAACNQAFFH8ZAAIaAAgKzBMBBwD6AQAaAAgKzBMBBwD6AQA1AAQKfzEAAhoACgq0JMoEAKoDABoACgq0JMoEAKoDAAAA.',
Ga='Galvanize:BAAANQAECgQIDwAAAA==.',
Ge='Genny:BAAANQAECggICAAAAA==.',
Gi='Gijaick:BAABNQAECn8cAAMCAAoKMA2SNQDsAAABAAoKhAuJsQBtAQACAAQKeguSNQDsAAAAAA==.',
Gl='Glizzo:BAABNQAECn9LAAIPAAoKrxZeSwAsAgAPAAoKrxZeSwAsAgAAAA==.Gloomrider:BAAANQADCgUIBQAAAA==.',
Go='Gold:BAAANQADCgUIBQAAAA==.Goldhawk:BAAANQAECgUIBQAAAA==.Gotwiped:BAABNQAECn81AAIbAAkKzyDXDwDUAgAbAAkKzyDXDwDUAgAAAA==.',
Gr='Grexx:BAAANQAECgMIBAABNQAFFAYIBgAcAEMcAA==.',
Gu='Gunnery:BAAANQAECggIDgAAAA==.',
Gy='Gyu:BAAANQADCgYIDQAAAA==.',
Ha='Hantaz:BAAANQAECggIDgAAAA==.Haoleboy:BAAANQAECgQIBAAAAA==.Hatter:BAABNQAECn8+AAMHAAoKzBskEQBIAgAHAAoKzBskEQBIAgAIAAcKXBfrDwC1AQAAAA==.',
He='Hellraiser:BAABNQAECn8cAAIYAAgKfBaPMgCAAQAYAAgKfBaPMgCAAQAAAA==.',
Hi='Hidduka:BAABNQAECn8aAAIaAAgKbxyaPAByAgAaAAgKbxyaPAByAgAAAA==.Hills:BAAANQAECgEIAQAAAA==.',
Ho='Holyascended:BAAANQADCggIFgAAAA==.Holydarkness:BAAANQADCgYIBgAAAA==.Holykilla:BAAANQADCgUIBQAAAA==.Holykiller:BAAANQADCgEIAQAAAA==.Hoplite:BAAANQAECggIDQAAAA==.Hothots:BAAANQABCgYIBgABNQAECgYICAATAAAAAA==.Howlly:BAABNQAECn83AAIdAAoKqiIPAwDbAgAdAAoKqiIPAwDbAgAAAA==.',
Hr='Hraun:BAAANQADCgIIAQAAAA==.',
Hu='Hulner:BAAANQAECggIAgAAAA==.',
Ik='Ikeanola:BAABNQAECn8eAAIVAAkKlgVF7QBBAQAVAAkKlgVF7QBBAQAAAA==.',
In='Inapa:BAAANQAECgYIBgAAAA==.Indras:BAAANQADCgcIFgAAAA==.Ines:BAABNQAECn8lAAIbAAkKih+EEgD5AgAbAAkKih+EEgD5AgAAAA==.Inhume:BAAANQADCggJCQAAAA==.Inter:BAAANQADCgIIAgAAAA==.',
Is='Ismarus:BAAANQAECgQIBQAAAA==.',
Ja='Jaarus:BAAANQAECgcIDgAAAA==.Jajal:BAABNQAECn8YAAIeAAkKCBH1JAAIAgAeAAkKCBH1JAAIAgABNQAECgoKFwAJABULAA==.Jankadish:BAABNQAECn8dAAQGAAkKUApOmgBKAQAGAAgKtAhOmgBKAQAFAAYKaAn3JwD/AAALAAEKjQbYOAApAAAAAA==.Jaspirian:BAAANQADCgYIBgAAAA==.',
Je='Jehm:BAABNQAECn8pAAIYAAoKCBDPUwClAQAYAAoKCBDPUwClAQAAAA==.Jerome:BAAANQADCgMIAwAAAA==.',
Ju='Juiceboxer:BAAANQAECgQICAABNQAECgUICwATAAAAAA==.Juicy:BAAANQADCgYIBgAAAA==.Justicehand:BAAANQAECgMIAgAAAA==.',
Ka='Kaestia:BAAANQAECgEIAQABNQAECgoKMQAdACEgAA==.Kagor:BAAANQADCgMIAwABNQAECgcIDgATAAAAAA==.Kalia:BAABNQAECn8xAAMdAAoKISDOBADWAgAdAAkK0iDOBADWAgAPAAkKMBilvAALAgAAAA==.Kalipto:BAAANQADCgcICAAAAA==.Katatonik:BAAANQAECgUIBQABNQAECgcIDgATAAAAAA==.Katharina:BAABNQAECn8bAAMaAAoKahN1YQD0AQAaAAoKahN1YQD0AQAVAAEKAABAuAEsAAAAAA==.Katoume:BAABNQAECn8jAAMfAAoKJCR4AgAuAwAfAAoKJCR4AgAuAwAZAAEKLRxJYABSAAABNQAECgoKIwAfACQkAA==.Katoumey:BAAANQAECgUIEAABNQAECgoKIwAfACQkAA==.Kaulder:BAAANQADCgMIAwAAAA==.',
Kh='Khumfuu:BAAANQAECgQICQAAAA==.',
Ki='Kinan:BAABNQAECn9FAAMOAAoKWSVrBQBjAwAOAAoKWSVrBQBjAwAEAAgKcCKyDAARAwAAAA==.',
Ko='Konan:BAAANQADCgMIAwAAAA==.Korlo:BAAANQAECgUIBwAAAA==.',
Ku='Kuala:BAAANQADCgIIAgAAAA==.',
Ky='Kythin:BAAANQAECgMIDAABNQAECgoKMQAdACEgAA==.',
La='Lacutis:BAAANQADCggICAAAAA==.',
Le='Leonus:BAAANQADCgQIBAAAAA==.',
Li='Lichmcconnel:BAABNQAECn81AAQDAAoKbxq0BQBgAgADAAoKbxq0BQBgAgACAAEKWAdjewAyAAABAAEKbQQzHgEuAAAAAA==.Lillica:BAAANQADCgQIBAAAAA==.Lilmeesh:BAAANQADCgQIBAAAAA==.Lisabeth:BAAANQAECgEIAQABNQAFFAkJFwAEAKkaAA==.',
Lo='Lomponic:BAEBNQAECn84AAIeAAoK8R40EQDoAgAeAAoK8R40EQDoAgAAAA==.Lonelyone:BAAANQAECgMIBAAAAA==.Lore:BAACNQAFFH8KAAIgAAYKWxH9BAAHAQAgAAYKWxH9BAAHAQA1AAQKfzUAAiAACgpkG2gZACkCACAACgpkG2gZACkCAAAA.',
Lu='Lunethra:BAABNQAECn8wAAIOAAoKEg6qawA8AgAOAAoKEg6qawA8AgAAAA==.Luukiss:BAAANQADCgQIBQAAAA==.Luyang:BAAANQADCgIIAgAAAA==.',
['Lü']='Lümen:BAAANQAECgIIBAAAAA==.',
Ma='Madcow:BAAANQADCgcIBwABNQAECggIHQAOAFAiAA==.Madhat:BAAANQAECggIDwAAAA==.Magerag:BAABNQAECn8lAAIPAAkKqCHCHgBdAwAPAAkKqCHCHgBdAwAAAA==.Malyc:BAAANQAECgQIBQAAAA==.',
Mc='Mcribz:BAACNQAFFH8IAAINAAUKnBlnBgC4AQANAAUKnBlnBgC4AQA1AAQKf0oAAg0ACgriJeIBAGoDAA0ACgriJeIBAGoDAAAA.',
Me='Meap:BAAANQAECgQIBQAAAA==.Mecatank:BAAANQAECgEJAQAAAA==.Medra:BAAANQABCgQIBAAAAA==.Meelonusk:BAABNQAECn8XAAMCAAkK8Q4vMgD9AAABAAcKMgzYrwBxAQACAAQKpBAvMgD9AAAAAA==.',
Mi='Michaelcoyle:BAABNQAECn9IAAIOAAoKYiGOFQBGAwAOAAoKYiGOFQBGAwAAAA==.Milo:BAAANQAECgYICwAAAA==.Mitra:BAABNQAECn8pAAIUAAgK5xpRAgAWAgAUAAgK5xpRAgAWAgAAAA==.',
Mo='Moesko:BAABNQAECn8dAAIhAAkKpByMIgDjAQAhAAkKpByMIgDjAQAAAA==.Mogianna:BAAANQABCgMIAwAAAA==.Monktup:BAAANQAECgEIAQAAAA==.Monkzo:BAAANQADCgcIBwABNQAECgoKMQAcACgaAA==.Monnehbaggs:BAACNQAFFH8GAAIcAAYKQxw7DwCfAQAcAAYKQxw7DwCfAQA1AAQKf1EAAxwACgrVJH0AAPUDABwACgrVJH0AAPUDACIABQqeGhUJAB4BAAAA.',
Mu='Munchies:BAAANQABCgIIAgAAAA==.Murdersamich:BAAANQADCggJCQAAAA==.',
My='Myraghor:BAABNQAECn88AAIZAAoKUyAoBQBMAwAZAAoKUyAoBQBMAwAAAA==.',
Na='Nalmec:BAAANQADCgQIBAAAAA==.Naysayre:BAAANQABCgEIAQAAAA==.',
Ne='Nebody:BAAANQAECgQICAAAAA==.Necriss:BAABNQAECn88AAIVAAkKhxAmnwCPAQAVAAkKhxAmnwCPAQAAAA==.',
Ni='Nike:BAABNQAECn8gAAIOAAoKzR2TXAAPAgAOAAoKzR2TXAAPAgAAAA==.',
No='Norni:BAAANQAECgYIEAAAAA==.Nowarning:BAAANQAECgYICAAAAA==.',
Og='Oghom:BAAANQADCggIGQAAAA==.',
Op='Opeep:BAAANQAECgYICwAAAA==.',
Or='Ordestur:BAAANQADCggICQAAAA==.Oruum:BAAANQAECgQIBAAAAA==.',
Os='Osos:BAAANQADCgQIBAAAAA==.',
Pa='Papachance:BAAANQAECgQIBgAAAA==.Papafrank:BAAANQAECgUIBgAAAA==.Papapump:BAABNQAECn8sAAIjAAoKxx5gCQCMAgAjAAoKxx5gCQCMAgAAAA==.Parlare:BAABNQAECn8hAAIhAAoKwxsGEwCZAgAhAAoKwxsGEwCZAgABNQAECgoKPAAcAKcfAA==.',
Pe='Perrinaya:BAAANQADCgQIBwAAAA==.',
Ph='Phoenixwing:BAAANQADCgYIDAAAAA==.',
Pi='Piedrita:BAAANQADCgMIAwAAAA==.Pinga:BAABNQAECn88AAMcAAoKpx+/JADBAgAcAAoKCB+/JADBAgAiAAYKMhoNCQDMAQAAAA==.',
Po='Poshifru:BAAANQAECgYIDwABNQABCgIIAgATAAAAAA==.',
Pr='Preposition:BAABNQAECn8uAAIOAAoKWBahWABpAgAOAAoKWBahWABpAgAAAA==.',
Pu='Pussduty:BAABNQAECn8/AAIOAAoK5yJwEwBRAwAOAAoK5yJwEwBRAwAAAA==.',
Ra='Raaziel:BAABNQAECn8VAAMDAAoKNgUKHACaAAABAAkKQgQG0QCvAAADAAQKJwYKHACaAAAAAA==.Racknar:BAABNQAECn8aAAIOAAkKAQzdgwCyAQAOAAkKAQzdgwCyAQAAAA==.Rafìki:BAAANQAECgcIEwAAAA==.Raggnar:BAABNQAECn8qAAISAAoK2h9OGwAmAwASAAoK2h9OGwAmAwAAAA==.Ragingwaters:BAAANQADCgYIBgAAAA==.Ranvir:BAAANQADCggIGgAAAA==.Raun:BAABNQAECn9LAAMVAAkKXSDZUQCgAgAVAAgKEiHZUQCgAgAaAAcKOQabuAAMAQAAAA==.',
Re='Reactionhank:BAAANQAECgUIBQAAAA==.Relaire:BAABNQAECn80AAIOAAkKZQoVlACNAQAOAAkKZQoVlACNAQAAAA==.',
Ri='Riku:BAABNQAECn88AAIfAAkKrh50CQBOAgAfAAkKrh50CQBOAgAAAA==.',
Ro='Roots:BAABNQAECn8sAAIMAAoKZSFjDQBfAwAMAAoKZSFjDQBfAwAAAA==.',
Ru='Rumplfourskn:BAAANQADCgIIAgAAAA==.',
Ry='Ryveri:BAABNQAECn8nAAIGAAoKABugWgB8AgAGAAoKABugWgB8AgAAAA==.',
Sa='Sablehide:BAABNQAECn8uAAQkAAgK0hKPCwBBAQAlAAgKbA1uGQCyAQAkAAcK0hKPCwBBAQAmAAIKvA8cRgBxAAAAAA==.Salute:BAAANQAECgYIBgAAAA==.Sanaty:BAAANQAECgcIDgAAAA==.Saryn:BAAANQAECgMIAwAAAA==.Sathanus:BAAANQAECgIIAgAAAA==.Sazuna:BAAANQAECgUIBwAAAA==.Sazuni:BAAANQAECgYIEAAAAA==.',
Se='Secrett:BAAANQADCgcIDgAAAA==.',
Sh='Shadowreaper:BAAANQAECgUIBQAAAA==.Shelby:BAAANQADCgYICQAAAA==.Shiggs:BAAANQAECgQIAwAAAA==.Shortsighted:BAABNQAECn8ZAAIOAAoKGhelSAA/AgAOAAoKGhelSAA/AgABNQAFFAUICAANAJwZAA==.Shoçknezz:BAAANQADCgYICwAAAA==.',
Si='Silentsnake:BAEANQAECggIBwABNQAECgoKMAAMAHoVAA==.Silverwolf:BAABNQAECn9PAAIjAAoKJhzDCACXAgAjAAoKJhzDCACXAgAAAA==.Simplyunlock:BAACNQAFFH8FAAIBAAIKkwIOLgBtAAABAAIKkwIOLgBtAAA1AAQKfzQABAEACgrAEy57APMBAAEACQr+Ei57APMBAAIABAptEeA3AOEAAAMAAQorBUcxACsAAAAA.Simplyvoided:BAAANQAECgIIAQAAAA==.Siphin:BAAANQAECggIAQAAAA==.Sizzlechop:BAABNQAECn8uAAIYAAkKLhLuNgBpAQAYAAkKLhLuNgBpAQAAAA==.Sizzlerocks:BAAANQADCgYIBgAAAA==.',
Sk='Skizzak:BAABNQAECn8pAAIMAAoK+ReiGABKAgAMAAoK+ReiGABKAgABNQAFFAUICAANAJwZAA==.',
Sl='Slee:BAAANQAECgMIBwAAAA==.Slimedog:BAAANQAECgEIAQAAAA==.',
Sm='Smelvin:BAAANQAECgYIEQABNQAECgkJFwACAPEOAA==.',
Sn='Snailslolol:BAABNQAECn87AAIaAAoKnBuvGgDjAgAaAAoKnBuvGgDjAgAAAA==.Snakes:BAEBNQAECn8hAAIYAAoKfxSkLACiAQAYAAoKfxSkLACiAQABNQAECgoKMAAMAHoVAA==.Sneaksatoke:BAAANQADCgMIAwAAAA==.Snåke:BAEANQAECggICAABNQAECgoKMAAMAHoVAA==.',
So='Solåra:BAAANQADCgUIBQABNQAECgoKHgAIAKUPAA==.Songs:BAAANQADCgQIBQABNQADCgcIEQATAAAAAA==.',
Sq='Squirtin:BAABNQAECn8ZAAMWAAcK9B8kRQD/AQAWAAYKHyMkRQD/AQASAAEKAADKHgFTAAAAAA==.',
St='Stalath:BAAANQAECgQIBAAAAA==.Stormquota:BAABNQAECn8mAAIjAAoKLCKTAwAUAwAjAAoKLCKTAwAUAwABNQAECgoKLwASADMiAA==.Stormwing:BAAANQAECgIIAQAAAA==.',
Su='Sumarr:BAAANQAECgcICAAAAA==.',
Sv='Svenn:BAAANQADCggIDwAAAA==.',
Sw='Swiftstrike:BAAANQADCgYIBgAAAA==.',
Ta='Taboo:BAAANQAECgYIDAAAAA==.Talron:BAAANQADCgcIEQAAAA==.Tango:BAAANQAECgIIAQAAAA==.Tatertots:BAABNQAECn80AAIbAAkKlxicKQBNAgAbAAkKlxicKQBNAgAAAA==.',
Te='Tea:BAABNQAECn84AAIOAAoK6CDdHQAgAwAOAAoK6CDdHQAgAwAAAA==.Teach:BAABNQAFFH8HAAMnAAMKLQPVAACgAAAnAAMKvwLVAACgAAAPAAIK3gJEQABsAAABNQAFFAMIBwAeAFsNAA==.Teilsande:BAAANQAECggIAQAAAA==.Teleportato:BAAANQAECgQIBAAAAA==.Templyn:BAABNQAECn85AAMYAAoKhxHrJgDGAQAYAAoKhxHrJgDGAQANAAEKAAAl5QAvAAAAAA==.',
Th='Thannos:BAAANQADCggIEwAAAA==.Theus:BAAANQADCgUICQAAAA==.Thyrus:BAABNQAECn82AAImAAoK3h3kDADXAgAmAAoK3h3kDADXAgABNQAECgoKPAAcAKcfAA==.',
Ti='Tirna:BAABNQAECn88AAIPAAkK8RN0dADGAQAPAAkK8RN0dADGAQAAAA==.',
To='Tomsellock:BAAANQADCggIFQAAAA==.Tonytemplar:BAAANQABCgIIBQAAAA==.',
Tu='Tullen:BAEBNQAECn9CAAIcAAkKfRVhSwAKAgAcAAkKfRVhSwAKAgAAAA==.Turanos:BAAANQAECgYICAAAAA==.Tutio:BAAANQADCgYIBgAAAA==.',
Ty='Tyindaris:BAAANQADCgUJCAAAAA==.',
['Té']='Témplýn:BAAANQAECgUIDQABNQAECgoKOQAYAIcRAA==.',
['Të']='Tëmplýn:BAAANQAECgQIBQABNQAECgoKOQAYAIcRAA==.Tëmplÿn:BAAANQAECgYIBgABNQAECgoKOQAYAIcRAA==.',
Ul='Ullr:BAAANQAECgEIAQAAAA==.Ultrachad:BAACNQAFFH8bAAIYAAgKnh/9BAAqAgAYAAgKnh/9BAAqAgA1AAQKfzcAAhgACgreIvEKAOECABgACgreIvEKAOECAAAA.',
Un='Unggoy:BAACNQAFFH8XAAMEAAkKqRrmBwDMAQAEAAgKzRjmBwDMAQAOAAEK0CVLLgBlAAA1AAQKfyYAAwQACgqEJMQOAPcCAAQACgolJMQOAPcCAA4AAQrrJjk9AWkAAAAA.Unholysin:BAAANQAECgUIBQAAAA==.',
Ur='Urianna:BAAANQAECgYIBAAAAA==.',
Uw='Uwuther:BAAANQAECgQICQAAAA==.',
Va='Vaelthirion:BAAANQAECgEIAQAAAA==.Vahidamus:BAABNQAECn8cAAMWAAkKBw5ZXQChAQAWAAkKBw5ZXQChAQASAAEKAADCWwEeAAAAAA==.Valmirax:BAAANQADCgcICgAAAA==.Valton:BAAANQAECgMIAgAAAA==.Vaurix:BAABNQAECn8iAAIeAAkKYxYvFwDyAQAeAAkKYxYvFwDyAQAAAA==.',
Ve='Vezarion:BAAANQADCgUIBgAAAA==.',
Wa='Wafuzz:BAAANQAECgQIBAAAAA==.Waters:BAAANQADCgMIAwAAAA==.',
We='Wesellpallys:BAAANQADCgUIBQABNQAECgkJFwACAPEOAA==.',
Wh='Whambamslam:BAAANQADCggICAAAAA==.',
Wi='Windhorn:BAAANQAECgQIBQAAAA==.Winds:BAAANQADCgcIEQAAAA==.Windtalker:BAAANQAECgUIBQABNQAECgcIDAATAAAAAA==.',
Wo='Wolfen:BAAANQADCggICAAAAA==.Wolfquota:BAABNQAECn8vAAISAAoKMyKlGAA1AwASAAoKMyKlGAA1AwAAAA==.Wombaa:BAABNQAECn86AAMNAAoKiCX5CAB4AwANAAkKiiX5CAB4AwAbAAoKlyO8CAAgAwAAAA==.',
Wr='Wrathdk:BAAANQAECgcIDgABNQAFFAIIAwATAAAAAA==.Wrathm:BAAANQAFFAIIAwAAAA==.Wrathmo:BAABNQAECn8WAAMJAAgKOhBqMACUAQAJAAcKExJqMACUAQAKAAQKaweFJACtAAABNQAFFAIIAwATAAAAAA==.Wrenkyian:BAAANQADCgUIBQAAAA==.',
Ya='Yani:BAAANQADCgYICgAAAA==.',
Ye='Yeah:BAAANQABCgUIBAAAAA==.',
Yo='Yoana:BAAANQABCgIIAgAAAA==.Yougotsniped:BAAANQADCgUIBQAAAA==.',
Za='Zakos:BAAANQADCggICAAAAA==.Zareeq:BAAANQADCgIIAgAAAA==.',
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
