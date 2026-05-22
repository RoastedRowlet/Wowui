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

local lookup = {'Evoker-Augmentation','Unknown-Unknown','Warlock-Demonology','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Brewmaster','Mage-Frost','Druid-Balance','Druid-Restoration','Monk-Windwalker','Mage-Arcane','Warlock-Destruction','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Hunter-BeastMastery','Monk-Mistweaver','Druid-Feral','Warlock-Affliction','Mage-Fire','Hunter-Marksmanship','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAECgYJCAAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgADCgUJBQAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAQJCwABAHgWAA==.Aiyaiyai:BAAALgAECgYJDAAAAA==.',
Ak='Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.',
Am='Aminall:BAAALgAECgIJAgAAAA==.',
An='Anarreth:BAAALgADCgUJCAAAAA==.Andahla:BAAALgADCgEJAQAAAA==.Andore:BAAALgAECgUJEgAAAA==.Anewbyss:BAAALgAECgcJCwAAAA==.Angrymurloc:BAAALgAECgcJDgAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgQJBwAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAACAAAAAA==.Arms:BAAALgAECgcJCAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJBQAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAAALgAECgYJEQAAAA==.',
At='Atreana:BAABLgAECn8mAAIDAAgJYhNSQgCWAQADAAgJYhNSQgCWAQAAAA==.Attykus:BAABLgAECn8sAAIEAAgJYBI1MQDoAQAEAAgJYBI1MQDoAQAAAA==.',
Av='Avalerion:BAAALgAECgQJDAAAAA==.Avij:BAAALgAECgMJBgABLgAECgYJCQACAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Barrellroll:BAAALgADCgkJCQAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIFAAkJTw+/HQDIAQAFAAkJTw+/HQDIAQAAAA==.Bigpoppapump:BAAALgAECgMJBAAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIGAAcJ5QYdlgDxAAAGAAcJ5QYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8bAAIHAAcJux2uAACZAgAHAAcJux2uAACZAgAuAAQKfyUAAgcACQk+JFcMAKoCAAcACQk+JFcMAKoCAAAA.',
Bo='Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECgYJCgAAAA==.Bowdacious:BAAALgAECgMJBQAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAECgYJEQAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAAALgAECgcJEQAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
['Bá']='Báthory:BAAALgAECgkJDgAAAA==.',
Ca='Cal:BAAALgAECgYJCwABLgAECggJLwAIAJQdAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAABLgAECn8vAAIIAAgJlB1PCgBVAgAIAAgJlB1PCgBVAgAAAA==.Camelshammy:BAAALgAECgYJDQAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAAJACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgQJDQAAAA==.',
Ce='Cedarpoint:BAAALgADCgUJBQAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8cAAMKAAgJaBU5GgCeAQAKAAgJaBU5GgCeAQALAAIJFREkrAAxAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJBgAAAA==.Chizami:BAAALgAECgQJBAABLgAFFAQJDQALAOsMAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8cAAIMAAkJaiCyBQC2AgAMAAkJaiCyBQC2AgAAAA==.',
Ci='Circa:BAABLgAECn8aAAMJAAgJOBA5bgBfAQAJAAcJxBE5bgBfAQANAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8YAAIOAAkJig/8DgADAQAOAAkJig/8DgADAQAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Crocklock:BAABLgAECn8YAAIDAAYJDxUuZgAzAQADAAYJDxUuZgAzAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8iAAMPAAcJ2AbVugC/AAAPAAcJigXVugC/AAAQAAMJ7QX8MABWAAAAAA==.Damnatio:BAABLgAECn8gAAIPAAkJmCQhBwADAwAPAAkJmCQhBwADAwAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Darkclement:BAAALgAECgYJCwABLgAFFAMJBgAPAE0NAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgAECgMJBAAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAAALgAECgMJCAAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAACAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCAACAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECggJGgADAP0UAA==.Drahalah:BAABLgAECn8eAAIRAAgJWx/mIgA0AgARAAgJWx/mIgA0AgAAAA==.Drakeji:BAABLgAECn8vAAMBAAgJKAqCLQAsAQABAAgJKAqCLQAsAQASAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAECgkJCQABLgAFFAUJEgATAHUcAA==.',
Du='Dumplingg:BAAALgAECgcJCQAAAA==.',
Ea='Earthvoodoo:BAAALgAECgUJDQAAAA==.',
Eb='Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgADCgcJBwACAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAYJFgAPAPEgAA==.Eluneslight:BAAALgAECgEJAQAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJLAAEAGASAA==.',
En='Ender:BAAALgAECgEJAQAAAA==.',
Ep='Epi:BAAALgAECgcJEQAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJDgAAAA==.',
Ev='Evianda:BAAALgADCggJBwAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Faramír:BAAALgADCgYJBAAAAA==.Fatébringer:BAAALgAECggJDgAAAA==.',
Fe='Fennek:BAAALgAECgYJDgAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Ga='Garaylo:BAACLgAFFH8WAAIPAAYJ8SCTBgDLAQAPAAYJ8SCTBgDLAQAuAAQKfykAAg8ACQn1JMACAKwDAA8ACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIUAAkJtiLuAgAIAwAUAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJOAAMAJUgAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8jAAQRAAgJsRJ2ZwBNAQARAAgJJBB2ZwBNAQAVAAYJNQ0qEADwAAAWAAEJSh4nPABQAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAECgYJBgABLgAECgkJIQAIADYhAA==.',
Go='Goldenblight:BAAALgAECgIJBQAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgEJAQAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgUJCAAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJDQAAAA==.',
Gw='Gwaineedk:BAAALgAECgEJAQAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAACAAAAAA==.Halstron:BAABLgAECn8dAAIPAAgJYhrXMgDtAQAPAAgJYhrXMgDtAQAAAA==.Harribel:BAABLgAECn8bAAQWAAgJuwUBMQCIAAARAAYJ1wNqwgCkAAAWAAQJtQYBMQCIAAAVAAIJ8gHdFgA1AAAAAA==.',
He='Heliòs:BAAALgAECgMJAwAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQXAAkJTRXRJgDcAQAXAAkJTRXRJgDcAQAYAAMJXgfMJACLAAAHAAEJhA0boQAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECggJDgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8hAAIIAAkJNiERBQC8AgAIAAkJNiERBQC8AgAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8GAAIDAAIJ/wTtfQCBAAADAAIJ/wTtfQCBAAAuAAQKfx0AAgMACQlnDVlaALkBAAMACQlnDVlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgATAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
In='Inte:BAAALgADCgYJBgAAAA==.',
Iz='Izgin:BAABLgAECn8UAAIJAAYJJhO3iAArAQAJAAYJJhO3iAArAQAAAA==.',
Ja='Jaime:BAAALgADCgYJCQABLgAECgYJCAACAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgACAAAAAA==.Jantar:BAABLgAECn8bAAILAAkJ4xhZEACMAgALAAkJ4xhZEACMAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8UAAIXAAYJrwytUwD3AAAXAAYJrwytUwD3AAAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgYJCwAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwACAAAAAA==.',
Ju='Jugsy:BAAALgAECgYJDAAAAA==.Juliza:BAAALgADCgQJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaligo:BAABLgAECn84AAMXAAkJGRh1EAAeAgAXAAkJGRh1EAAeAgAYAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8SAAIGAAgJXgzlVgAwAQAGAAgJXgzlVgAwAQAAAA==.Kalygos:BAAALgADCgcJBwABLgAECggJLwAIAJQdAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgADCgkJEgAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8rAAIMAAkJryNEAgAiAwAMAAkJryNEAgAiAwAAAA==.Kegfupanda:BAAALgAECgEJAgAAAA==.Keleion:BAABLgAECn8nAAIGAAcJzRDTYwANAQAGAAcJzRDTYwANAQABLgAECgkJEwACAAAAAA==.Kevonjuravis:BAABLgAECn8YAAMIAAUJSgrgSQCcAAAMAAQJ7gmPUQDMAAAIAAUJLgrgSQCcAAAAAA==.',
Kh='Khalya:BAAALgADCgQJBAAAAA==.Khalyl:BAAALgAECgcJDwAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgIJAgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGgAAAA==.',
Ko='Koder:BAACLgAFFH8LAAIBAAQJeBY0GQAuAQABAAQJeBY0GQAuAQAuAAQKfyMABAEACAmtIbEGABIDAAEACAmtIbEGABIDABkAAgkOArJEAEoAABIAAQmAFSY9ADoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgUJBQAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn80AAMRAAgJURp8PADJAQARAAgJURp8PADJAQAVAAEJWAkAAAAAAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilithxander:BAAALgAECgQJBwAAAA==.Lizzybordan:BAAALgAECgUJCAAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAAALgAECgUJDQAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.',
Ly='Lynx:BAAALgAECgEJAQAAAA==.',
Ma='Mariskama:BAABLgAECn8UAAIaAAgJLgUdYQAnAQAaAAgJLgUdYQAnAQAAAA==.Markusthered:BAAALgAECgMJAwAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAUALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJEAAAAA==.',
Mi='Mikkais:BAAALgAECgQJCgAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8KAAIbAAQJoxiWEQBLAQAbAAQJoxiWEQBLAQAuAAQKfy0AAhsACAk0Hc4OAE0CABsACAk0Hc4OAE0CAAAA.Minni:BAAALgAECgcJEQAAAA==.',
Mo='Moolin:BAABLgAECn8XAAIcAAcJ6AN4HAC+AAAcAAcJ6AN4HAC+AAAAAA==.Moranthe:BAAALgAECgcJDAABLgAECgkJEgACAAAAAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAAALgAECgkJDgAAAA==.Munder:BAABLgAECn8cAAMDAAgJDBzxOAC2AQADAAgJ/hnxOAC2AQAdAAUJcBuMCQBbAQAAAA==.Mustymuppet:BAACLgAFFH8LAAIDAAQJ7AdBQQAGAQADAAQJ7AdBQQAGAQAuAAQKfyEAAwMACAmYGd8zAMkBAAMACAmYGd8zAMkBAA4AAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8YAAIeAAYJwxfXAwBtAQAeAAYJwxfXAwBtAQAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8ZAAIRAAgJwiJkEQCjAgARAAgJwiJkEQCjAgAAAA==.Nemini:BAAALgAECgEJAQAAAA==.Nena:BAAALgAECgQJDwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8XAAMSAAYJrArDDwDIAAASAAQJZgvDDwDIAAABAAIJxwe2cwAoAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAAALgAECgYJDQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Notagain:BAACLgAFFH8hAAIPAAcJMBvSAwAIAgAPAAcJMBvSAwAIAgAuAAQKfykAAg8ACQkBI5YHAFoDAA8ACQkBI5YHAFoDAAAA.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgQJBQAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.',
Ol='Olenza:BAAALgAECgEJAQAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAILAAYJChgpTABzAQALAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Pebbleshifts:BAAALgAECgIJAgAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peybreak:BAAALgAECgEJAQABLgAECgkJHgANABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgANABghAA==.Peycicle:BAABLgAECn8eAAINAAkJGCFKAQDOAgANAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgANABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgANABghAA==.Peytan:BAAALgAECgYJCwABLgAECgkJHgANABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgANABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8aAAIZAAgJuBj2BgBLAgAZAAgJuBj2BgBLAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8bAAMHAAgJQRiOKADDAQAHAAgJQRiOKADDAQAXAAEJFgP9iAAdAAAAAA==.',
Po='Poetuck:BAABLgAECn8iAAIJAAgJTA9SZQByAQAJAAgJTA9SZQByAQAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAACAAAAAA==.',
Pr='Proko:BAABLgAECn8aAAMXAAgJ9A+dNQAJAQAXAAYJ7hKdNQAJAQAHAAIJLA1wgQBgAAAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.',
Qa='Qatka:BAAALgAECgEJAQAAAA==.',
Qu='Quiver:BAABLgAECn8bAAIPAAcJ6QrEjQAKAQAPAAcJ6QrEjQAKAQAAAA==.',
['Qì']='Qìlen:BAAALgAECgYJDwAAAA==.',
Ra='Raein:BAABLgAECn8hAAMHAAcJyR6nFABSAgAHAAcJyR6nFABSAgAXAAYJnBcjLQA1AQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAAALgAFFAIJAgAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAECgUJCgAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBAAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAAALgAECgUJEwAAAA==.Renmore:BAAALgAECggJDwAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Risotto:BAAALgAECgIJAwAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAACAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJDwAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8cAAIaAAYJgQvebgAGAQAaAAYJgQvebgAGAQAAAA==.Ruele:BAAALgAECgkJEgAAAA==.Ruenan:BAABLgAECn8mAAMaAAgJnCaYBQADAwAaAAgJnCaYBQADAwAfAAMJlhKzaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn8rAAMKAAkJBg8aIABrAQAKAAkJYw0aIABrAQAgAAYJVxCXHADmAAAAAA==.Ryian:BAAALgADCgkJCQAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIgAAcJNgo/GAD0AAAgAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIhAAYJXgFFLwB7AAAhAAYJXgFFLwB7AAAAAA==.Sapthat:BAABLgAECn8bAAMiAAcJwyH7AwDqAQAiAAYJAyT7AwDqAQAjAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8UAAIJAAYJiAYgrQDqAAAJAAYJiAYgrQDqAAAAAA==.Savepebble:BAABLgAECn8aAAMDAAgJ/RReYwA6AQADAAcJ1w5eYwA6AQAOAAUJXxdHFwCxAAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAQAAAA==.',
Se='Seather:BAABLgAECn8aAAIkAAgJyhvDEwB4AgAkAAgJyhvDEwB4AgAAAA==.Seirin:BAABLgAECn8hAAIlAAcJkxL5IABzAQAlAAcJkxL5IABzAQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8PAAIfAAQJEB7UBwByAQAfAAQJEB7UBwByAQAuAAQKfzYAAh8ACQkeIZwBANICAB8ACQkeIZwBANICAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Serendipity:BAAALgADCgYJCQABLgAECgcJEQACAAAAAA==.Serqet:BAAALgAECgMJAwAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAAALgAECgcJDwAAAA==.Sheri:BAAALgAECgQJDQAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8WAAMLAAYJGxV9OwBeAQALAAYJGxV9OwBeAQAKAAEJaAIkewAVAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgMJBAAAAA==.',
Si='Sillygoose:BAACLgAFFH8ZAAIJAAcJFhHBDQDpAQAJAAcJFhHBDQDpAQAuAAQKfx4AAgkACQlJIJEVACcDAAkACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgQJCQACAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAYJFgAPAPEgAA==.Siorknav:BAABLgAECn8fAAIPAAgJiQ4ldAA6AQAPAAgJiQ4ldAA6AQAAAA==.',
Sk='Skalar:BAAALgAECgYJDwAAAA==.Skodah:BAAALgADCgkJEQABLgAECgQJCQACAAAAAA==.',
Sl='Släyr:BAAALgADCgIJAgAAAA==.',
So='Solunara:BAAALgADCgYJFQAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8ZAAIRAAcJ7Q6EZgBQAQARAAcJ7Q6EZgBQAQAAAA==.Sorrenda:BAAALgADCgkJCQAAAA==.Soup:BAABLgAECn8nAAIcAAkJ/g2rCwCfAQAcAAkJ/g2rCwCfAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIkAAkJdRmtDAAMAgAkAAkJdRmtDAAMAgAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBgAAAA==.Stovik:BAABLgAECn8qAAMYAAgJ9B1eBQA4AgAYAAgJ9B1eBQA4AgAHAAcJ0BGSMQCQAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgUJEQAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBQAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJBwAAAA==.Sylira:BAACLgAFFH8PAAMlAAYJ5xE1BAC3AQAlAAYJ5xE1BAC3AQAmAAEJMAB8NAATAAAuAAQKfy0AAyUACQkxHA4KAKwCACUACQkxHA4KAKwCACcAAwlrCmNSAIAAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAACAAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAITAAUJdRxLCABJAQATAAUJdRxLCABJAQAuAAQKfyMAAxMACQmxIDsCAAcDABMACQlaIDsCAAcDAAQABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgIJAwAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgQJBAABLgAECggJIQAmABEMAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJBQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgMJAwAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelil:BAAALgAECgMJAwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn8lAAIJAAkJLRiyQADYAQAJAAkJLRiyQADYAQAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAACAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgMJAwAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFAAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBQAAAA==.',
Un='Unoboxo:BAAALgADCgEJAQABLgAFFAQJBQABAKkNAA==.Unovoke:BAACLgAFFH8FAAIBAAQJqQ2zHgAXAQABAAQJqQ2zHgAXAQAuAAQKfzQAAgEACQkrHboLAFoCAAEACQkrHboLAFoCAAAA.',
Va='Valorash:BAABLgAECn8kAAMPAAgJQyAWGABzAgAPAAgJQyAWGABzAgAQAAYJ5Rq4DwDJAQAAAA==.Valorious:BAAALgAECgEJAQAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgMJAwAAAA==.Velintha:BAAALgAECgYJBwAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCAACAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAAALgAECgYJDwAAAA==.Vonderick:BAAALgADCgkJLgAAAA==.Voodoodog:BAAALgAECgIJBAABLgAECgUJDQACAAAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAQAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQACAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBAABLgAECgUJCAACAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQACAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIYAAcJ5xSuDgDRAQAYAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAECgcJHQAMAMciAA==.',
Wy='Wynce:BAAALgADCgcJBwAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgIJAgAAAA==.Xarn:BAABLgAECn8hAAIDAAkJtwciWwBOAQADAAkJtwciWwBOAQAAAA==.',
Xc='Xcïte:BAABLgAECn8WAAQnAAcJxhhVGQCoAQAnAAYJ9hxVGQCoAQAlAAMJ3RtaWADUAAAmAAQJrA6dPwCyAAAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.',
Yo='Yourlock:BAAALgADCgUJBQAAAA==.',
Yu='Yuji:BAABLgAECn8oAAIPAAgJKQ/uXABuAQAPAAgJKQ/uXABuAQAAAA==.',
Za='Zalectra:BAACLgAFFH8RAAIUAAQJHiFqBQB5AQAUAAQJHiFqBQB5AQAuAAQKfzcAAxQACQm2JUIAAMUDABQACQm2JUIAAMUDAB8AAgmhFgofAHUAAAAA.',
Ze='Zelila:BAAALgADCgYJCAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBgAAAA==.',
['Ål']='Ålloria:BAAALgAECgEJAQAAAA==.',
['ßl']='ßlackßetty:BAAALgADCgYJBwABLgADCgkJCQACAAAAAA==.',
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
